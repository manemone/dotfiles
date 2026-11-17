#!/usr/bin/env python3
# AI の返事の言葉の悪癖を数える集計スクリプト（調査用の道具。配布しない）。
# 入力: ~/.claude/projects/*/*.jsonl の assistant の発言（本文と、送る文・メモリへの書き込み）。
# 出力: 件数・割合だけ。会話の本文は出さない（--examples を付けたときも語の前後の文字数だけ）。
#
# 数えるもの（計画書 DOC-2611172104 設計0 の 1）:
#   悪癖1: 和語に開いた言い換え（OPEN）と、同じ意味の漢語・カタカナ語（PLAIN）の出現数と比
#   悪癖2: 全面禁止の宣言の言い回し（BAN）の出現数
# 使ってよい和語（引く・探す・立てる・止める・回す）はどの正規表現にも入れない。
#
# 使い方:
#   python3 wh.py --since 2026-10-20 --until 2026-11-17 --by week
#   python3 wh.py --since 2026-11-10 --by project --exclude-project 'wording|wh-0'
#   python3 wh.py --channel text,send,memory --by none
# 孫2 の前後比較には、同じ引数で期間だけ変えて2回回す。
import argparse, collections, datetime, glob, json, os, re, sys

# 悪癖1 の和語に開いた言い換え。各語の誤検出（普通の用法）は、前後の文字の条件で外してある。
OPEN = {
    '確かめ': r'確かめ',
    '直し': r'(?<![りきみじけえびちぎしせてれい見手立])直し(?![たい合])',  # 〜し直す型（やり直し・見直し・書き直し・立て直し・回し直しなど）を除く
    '測り': r'(?<![計観予推目])測り(?!知)',
    '割り出し': r'(?:割り出[しす]|(?:原因|内訳|費用)を割[るっ])',
    '控え': r'控え[をがにはので]',  # 控えめ・控える・控えて（差し控え）を除く
    '写し': r'(?<![書き映])写し(?![出込])',  # 書き写し・映し・写し出すを除く
    '焼いた指示': r'焼いた(?:指示|プロンプト|ルール)',
}
# 同じ意味の漢語・カタカナ語。比の分母に使う
PLAIN = {
    '確認': r'確認',
    '修正': r'修正',
    '計測': r'計測',
    '切り分け・内訳': r'切り分け|内訳|分解',
    'キャッシュ': r'キャッシュ|cache',
    'コピー': r'コピー',
}
# 悪癖2: 全面禁止の宣言。「一切」単独（事実の記述）は数えず、禁止の述語と組になったときだけ数える
BAN_PRED = r'(?:しません|しない|使いません|使わない|入れません|入れない|やりません|やらない|行いません|行わない|書きません|書かない|触りません|触らない|出しません|出さない|避けます)'
BAN = {
    '一切〜しない': r'一切[^。\n、]{0,20}' + BAN_PRED,
    '二度と〜しない': r'(?:二度と|金輪際)[^。\n、]{0,20}' + BAN_PRED,
    '今後は〜しない': r'今後(?:は|も)?[^。\n、]{0,15}' + BAN_PRED,
}

FENCE = re.compile(r'```.*?```', re.S)
INLINE = re.compile(r'`[^`\n]*`')
QUOTE_LINE = re.compile(r'^\s*>.*$', re.M)
BRACKET = re.compile(r'「[^」\n]*」|『[^』\n]*』')  # 持ち主の語の引用・語そのものへの言及を外す
PATHURL = re.compile(r'https?://\S+|[\w./~-]*/[\w./-]+')


def clean(text, keep_quotes):
    t = FENCE.sub(' ', text)
    t = INLINE.sub(' ', t)
    t = QUOTE_LINE.sub(' ', t)
    t = PATHURL.sub(' ', t)
    if not keep_quotes:
        t = BRACKET.sub(' ', t)
    return t


def parse_time(s):
    return datetime.datetime.fromisoformat(s).astimezone() if s else None


def week_of(dt):
    d = dt.date()
    return (d - datetime.timedelta(days=d.weekday())).isoformat()


def iter_texts(path, channels, since, until):
    """(時刻, チャンネル, 本文) を返す。"""
    for line in open(path, errors='ignore'):
        if '"type":"assistant"' not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get('type') != 'assistant' or not d.get('timestamp'):
            continue
        t = datetime.datetime.fromisoformat(d['timestamp'].replace('Z', '+00:00')).astimezone()
        if (since and t < since) or (until and t >= until):
            continue
        for b in (d.get('message') or {}).get('content') or []:
            if not isinstance(b, dict):
                continue
            if b.get('type') == 'text' and 'text' in channels:
                yield t, 'text', b.get('text', '')
            elif b.get('type') == 'tool_use':
                inp = b.get('input') or {}
                if b.get('name') == 'SendMessage' and 'send' in channels:
                    yield t, 'send', str(inp.get('message', ''))
                elif b.get('name') in ('Write', 'Edit') and 'memory' in channels and '/memory/' in str(inp.get('file_path', '')):
                    yield t, 'memory', str(inp.get('content') or inp.get('new_string') or '')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', help='ISO 8601。省略なら制限なし')
    ap.add_argument('--until', help='ISO 8601（この時刻を含まない）')
    ap.add_argument('--by', choices=['none', 'week', 'project', 'channel', 'word'], default='none')
    ap.add_argument('--channel', default='text', help='text,send,memory のコンマ区切り')
    ap.add_argument('--exclude-project', help='除くプロジェクトのディレクトリ名の正規表現（語を話題にした会話を外す）')
    ap.add_argument('--include-project', help='対象にするプロジェクトの正規表現')
    ap.add_argument('--keep-quotes', action='store_true', help='「」の中も数える')
    ap.add_argument('--ctx', action='store_true', help='開いた語ごとに、直前・直後1文字の分布を出す（正規表現の誤検出の点検用）')
    ap.add_argument('--top', type=int, default=15)
    a = ap.parse_args()
    since, until = parse_time(a.since), parse_time(a.until)
    channels = set(a.channel.split(','))
    ex = re.compile(a.exclude_project) if a.exclude_project else None
    inc = re.compile(a.include_project) if a.include_project else None
    pats = {k: re.compile(v) for grp in (OPEN, PLAIN, BAN) for k, v in grp.items()}
    stat = collections.defaultdict(collections.Counter)
    ctx = collections.defaultdict(collections.Counter)
    for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
        proj = f.split('/projects/')[1].split('/')[0]
        if ex and ex.search(proj) or (inc and not inc.search(proj)):
            continue
        if since and os.path.getmtime(f) < since.timestamp():
            continue
        for t, ch, text in iter_texts(f, channels, since, until):
            key = {'none': 'all', 'week': week_of(t), 'project': proj, 'channel': ch, 'word': 'all'}[a.by]
            c = stat[key]
            body = clean(text, a.keep_quotes)
            c['_msgs'] += 1
            c['_chars'] += len(body)
            hit = False
            for k, p in pats.items():
                n = len(p.findall(body))
                c[k] += n
                hit = hit or (n > 0 and k in OPEN)
                if a.ctx and k in OPEN:
                    for m in p.finditer(body):
                        ctx[k][(body[max(0, m.start() - 1):m.start()], body[m.end():m.end() + 1])] += 1
            c['_hit_msgs'] += hit  # 開いた語を1つ以上含む発言の数（Stop hook で止まる割合の見積もりに使う）
    def row(key, c):
        o = sum(c[k] for k in OPEN)
        p = sum(c[k] for k in PLAIN)
        b = sum(c[k] for k in BAN)
        ratio = o / (o + p) if o + p else 0.0
        per = lambda n: n / c['_chars'] * 10000 if c['_chars'] else 0.0
        return (key, c['_msgs'], c['_chars'], o, p, ratio, per(o), b, per(b), c['_hit_msgs'])
    print(f"期間 {a.since or '-'} 〜 {a.until or '-'} / 対象 {','.join(sorted(channels))} / 集計 {a.by}"
          f" / 引用{'を含む' if a.keep_quotes else 'は除く'}")
    if a.by == 'word':
        c = stat['all']
        print('語  件数')
        for k in list(OPEN) + list(PLAIN) + list(BAN):
            print(f'{k}  {c[k]}')
    for k, cc in ctx.items():
        print(f'[{k}] 前後1字 上位: ' + ' '.join(f'{b!r}_{f!r}:{n}' for (b, f), n in cc.most_common(8)))
    rows = [row(k, c) for k, c in stat.items()]
    rows.sort(key=lambda r: (r[0] if a.by == 'week' else -r[2]))
    print('キー  発言数  文字数  開いた語  漢語  開いた語の割合  開いた語/万字  全面禁止  全面禁止/万字  開いた語を含む発言')
    for r in rows[:a.top] if a.by == 'project' else rows:
        print(f'{r[0]}  {r[1]}  {r[2]}  {r[3]}  {r[4]}  {r[5]:.2f}  {r[6]:.2f}  {r[7]}  {r[8]:.2f}  {r[9]}')


if __name__ == '__main__':
    sys.exit(main())
