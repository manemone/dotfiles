#!/usr/bin/env python3
# 過去の返事を、モデルに文脈で判定させて、言葉の癖の割合（基準値）を出す調査用の道具。配布しない。
# 正規表現の語の数え方（wh.py）は例の語の出現の目安にすぎない（調査結果 DOC-2611172119 §2）。語の適否は文脈で決まるので、
# こちらは基準の文書（docs/design/ の「AI が書く文章の言葉」）をそのまま判定の基準に渡し、モデルに文脈で判定させる。
#
# 流れ:
#   1. ~/.claude/projects/*/*.jsonl から、持ち主に表示される本文（final・text）と送る文（send）を集める（wh.py の iter_texts を使う）
#   2. 一定の長さのものから、乱数の種を固定して無作為に N 件を抜く（同じ引数なら同じ件が選ばれる）
#   3. 複数件をまとめて1回の `claude -p` で判定する。一時の作業ディレクトリと一時の設定ディレクトリで、会話を保存せず、
#      ツールを使わせない。CLAUDE.md（プロジェクトのものも ~/.claude/ のものも）は読ませない（実 $HOME の設定は書き換えない）
#   4. 割合と費用の合計を出す。判定の妥当性の確認用に、約20件を本文と理由つきでリポの外へ置く
#
# 使い方:
#   python3 wh_judge.py --since 2026-11-10 --until 2026-11-17 --n 300 --out-dir "$(mktemp -d)"
#   python3 wh_judge.py --since 2026-11-17 --n 300 --samples ~/.local/state/umbrella/wording-habits/judge-samples.md
# 導入後の比較は、同じ --n --seed --channel --model で期間だけ変えて回す。
# 出力の標準出力には割合と費用だけを出す。本文・理由は --out-dir と --samples のファイル（リポの外）にだけ書く。

import argparse
import glob
import json
import os
import random
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import wh  # noqa: E402  同じディレクトリの集計スクリプト。本文の抽出と整形をそのまま使う

ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
HABITS = ['h1', 'h2', 'h3']
NAMES = {
    'h1': '読み手がその文脈で実際に使う名前で書いていない（言葉の置き換え・造語・比喩・定着していない語・呼び分け）',
    'h2': '決まり文句・AI 特有の言い回しで文を埋め、その文脈の具体的な中身を書いていない',
    'h3': '指摘を受けて、その場面の話でなく「今後一切しない」のような規則・全面禁止に広げている',
}
SYSTEM = """あなたは、AI が書いた日本語の返事を、基準の文書に沿って判定する審査役です。ツールは使わず、判定だけを返します。

# 基準の文書
{standard}

# 判定のしかた
- 以下の各項目（id 付きの返事）について、基準の文書の1〜3 に該当するかを、**その文脈で**判定する。語の一覧と照らすのではなく、
  読み手がその文脈でふだん使う名前かどうかを、前後の文と話題から判断する（「引く・探す・立てる・止める・回す」や、定着した
  カタカナ語は、そのまま使ってよい）。コード・コマンド・引用の中は対象外
- h1 = 1 の節（読み手の名前）に該当、h2 = 2 の節（決まり文句）に該当、h3 = 3 の節（全面禁止への拡大）に該当。該当は 1、非該当は 0
- 迷う程度のものは 0 にする。根拠が文から読み取れるものだけを 1 にする
- reason は日本語で1文（該当する箇所を短く引いて、なぜ該当するか。非該当なら空文字でよい）
- 出力は JSON の配列だけ（前置き・コードブロック無し）: [{{"id": 1, "h1": 0, "h2": 1, "h3": 0, "reason": "..."}}, ...]
  項目の数と同じ件数を、id の順に返す
"""


def find_standard(path):
    if path:
        return path
    c = glob.glob(os.path.join(ROOT, 'docs', 'design', 'DOC-*_AIが書く文章の言葉.md'))
    if not c:
        sys.exit('基準の文書が見つからない。--standard で渡す')
    return c[0]


def collect(args, since, until):
    """条件に合う本文を、乱数の種を固定した貯水池抽出で n 件だけ残す。"""
    rng = random.Random(args.seed)
    channels = set(args.channel.split(','))
    ex = re.compile(args.exclude_project) if args.exclude_project else None
    pool, seen = [], 0
    for f in sorted(glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl'))):
        proj = f.split('/projects/')[1].split('/')[0]
        if ex and ex.search(proj):
            continue
        if since and os.path.getmtime(f) < since.timestamp():
            continue
        for t, ch, text in wh.iter_texts(f, channels, since, until):
            body = wh.clean(text, True).strip()
            if not (args.min_chars <= len(body) <= args.max_chars_keep):
                continue
            seen += 1
            item = {'time': t.isoformat(timespec='minutes'), 'channel': ch, 'text': body[:args.max_chars]}
            if len(pool) < args.n:
                pool.append(item)
            else:
                j = rng.randrange(seen)
                if j < args.n:
                    pool[j] = item
    return pool, seen


def judge_batch(items, system, model, budget):
    body = '\n\n'.join('### id=%d\n%s' % (i, it['text']) for i, it in items)
    cmd = ['claude', '-p', '--model', model, '--output-format', 'json', '--no-session-persistence',
           '--system-prompt', system, '--tools', '', '--disable-slash-commands', '--max-budget-usd', str(budget)]
    # 一時ディレクトリで実行する。作業ディレクトリだけでなく設定ディレクトリ（CLAUDE_CONFIG_DIR）も一時のものにして、
    # プロジェクトの CLAUDE.md とユーザーの ~/.claude/CLAUDE.md（と人格の import）を判定役の文脈に入れない。
    # 入れると、配布で ~/.claude/CLAUDE.md が変わった前後で判定の条件が変わり、基準値と比べられなくなる。
    # 認証は、実設定の資格情報ファイルへの symlink だけを一時の設定ディレクトリに置いて通す（実設定は書き換えない）
    with tempfile.TemporaryDirectory() as tmp:
        cfg, work = os.path.join(tmp, 'cfg'), os.path.join(tmp, 'work')
        os.makedirs(cfg)
        os.makedirs(work)
        cred = os.path.expanduser('~/.claude/.credentials.json')
        if os.path.exists(cred):
            os.symlink(cred, os.path.join(cfg, '.credentials.json'))
        env = dict(os.environ, CLAUDE_CONFIG_DIR=cfg)
        p = subprocess.run(cmd, input=body, capture_output=True, text=True, cwd=work, env=env, timeout=300)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-300:])
    out = json.loads(p.stdout)
    text = out.get('result', '')
    m = re.search(r'\[.*\]', text, re.S)
    return json.loads(m.group(0)), float(out.get('total_cost_usd') or 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', help='ISO 8601')
    ap.add_argument('--until', help='ISO 8601（この時刻を含まない）')
    ap.add_argument('--n', type=int, default=300, help='判定する件数')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--batch', type=int, default=10, help='1回の呼び出しでまとめて判定する件数')
    ap.add_argument('--channel', default='final,send', help='wh.py の iter_texts のチャンネル。既定は持ち主に表示される本文の最後と送る文')
    ap.add_argument('--model', default='haiku')
    ap.add_argument('--min-chars', type=int, default=80, help='これより短い発言は除く')
    ap.add_argument('--max-chars-keep', type=int, default=6000, help='これより長い発言（ログの貼り付け等）は除く')
    ap.add_argument('--max-chars', type=int, default=1500, help='判定に渡す本文の最大字数')
    ap.add_argument('--budget', type=float, default=0.5, help='1回の呼び出しの上限（ドル）')
    ap.add_argument('--exclude-project', help='除くプロジェクトのディレクトリ名の正規表現（語を話題にした会話を外す）')
    ap.add_argument('--standard', help='基準の文書のパス（省略なら docs/design/ から探す）')
    ap.add_argument('--out-dir', help='判定結果の JSON を書く先（リポの外のディレクトリ）')
    ap.add_argument('--samples', help='妥当性の確認用の約20件を本文と理由つきで書くファイル（リポの外）')
    ap.add_argument('--samples-n', type=int, default=20)
    a = ap.parse_args()
    since, until = wh.parse_time(a.since), wh.parse_time(a.until)
    system = SYSTEM.format(standard=open(find_standard(a.standard)).read())
    pool, seen = collect(a, since, until)
    results, cost = [], 0.0
    for s in range(0, len(pool), a.batch):
        chunk = list(enumerate(pool[s:s + a.batch], 1))
        try:
            rows, c = judge_batch(chunk, system, a.model, a.budget)
        except Exception as e:  # 1回の失敗で全体を止めない。失敗した件は集計から外し、件数を出す
            print('batch %d 失敗: %s' % (s // a.batch, str(e)[:120]), file=sys.stderr)
            continue
        cost += c
        by_id = {r.get('id'): r for r in rows if isinstance(r, dict)}
        for i, it in chunk:
            r = by_id.get(i)
            if r:
                results.append(dict(it, **{h: int(bool(r.get(h))) for h in HABITS}, reason=str(r.get('reason', ''))))
    n = len(results)
    print('期間 %s 〜 %s / 対象 %s / モデル %s / 乱数の種 %d' % (a.since or '-', a.until or '-', a.channel, a.model, a.seed))
    print('候補の発言 %d 件から %d 件を抜き、%d 件を判定（失敗した分は除く）。費用の合計 %.3f ドル（1件あたり %.4f ドル）'
          % (seen, len(pool), n, cost, cost / n if n else 0))
    for h in HABITS:
        k = sum(r[h] for r in results)
        print('%s %s: %d 件（%.1f%%）' % (h, NAMES[h][:20], k, 100.0 * k / n if n else 0))
    for ch in sorted({r['channel'] for r in results}):
        sub = [r for r in results if r['channel'] == ch]
        print('  %s %d 件: ' % (ch, len(sub)) + ' '.join('%s=%.1f%%' % (h, 100.0 * sum(r[h] for r in sub) / len(sub)) for h in HABITS))
    if a.out_dir:
        os.makedirs(a.out_dir, exist_ok=True)
        with open(os.path.join(a.out_dir, 'judge-results.json'), 'w') as fp:
            json.dump(results, fp, ensure_ascii=False, indent=1)
    if a.samples:
        rng = random.Random(a.seed)
        hit = [r for r in results if any(r[h] for h in HABITS)]
        miss = [r for r in results if not any(r[h] for h in HABITS)]
        pick = rng.sample(hit, min(len(hit), a.samples_n // 2)) + rng.sample(miss, min(len(miss), a.samples_n - min(len(hit), a.samples_n // 2)))
        rng.shuffle(pick)
        with open(a.samples, 'w') as fp:
            fp.write('# 判定の妥当性の確認用（モデル %s。件数 %d）\n\n持ち主が、判定が自分の感覚と合っているかを見るための抜粋です。'
                     '各項目の h1=読み手の名前・h2=決まり文句・h3=全面禁止への拡大、1 が該当。会話の本文を含むので、リポの外に置いて公開しないこと。\n\n' % (a.model, len(pick)))
            for i, r in enumerate(pick, 1):
                fp.write('## %d（%s・%s） h1=%d h2=%d h3=%d\n\n判定の理由: %s\n\n```\n%s\n```\n\n' % (
                    i, r['time'], r['channel'], r['h1'], r['h2'], r['h3'], r['reason'] or '（非該当）', r['text']))


if __name__ == '__main__':
    sys.exit(main())
