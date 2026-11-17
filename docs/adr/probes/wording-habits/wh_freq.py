#!/usr/bin/env python3
# AI が読んだファイルの回数を、リポごとに数える集計スクリプト（調査用の道具。配布しない）。
# 目的: 言葉の基準（DOC-2611172307）で書き直す文書を、読まれる頻度の高い順に決める。
# 入力: ~/.claude/projects/*/*.jsonl（会話ログ）。出力: リポごとの「読まれた回数の累積が一定の割合に達するまでのファイル」。
#
# 数えるもの（1ファイルにつき、1つの会話で何回読まれたかの合計）:
#   - Read ツールで読んだファイル
#   - Skill ツールで読み込んだスキルの SKILL.md（dotfiles の skills/<名前>/SKILL.md として数える）
#   - 会話の開始時に自動で読み込まれる CLAUDE.md・AGENTS.md（会話ごとに1回。作業ツリーの cwd から決める）
# 除くもの: docs/adr/ と docs/planning/（歴史の記録・現役の傘の計画書。持ち主の決定でスコープ外）。
#
# 使い方:
#   python3 wh_freq.py --since 2026-10-20 --until 2026-11-17 --share 0.8
#   python3 wh_freq.py --repo lorahaus --out-dir ~/.local/state/umbrella/wording-habits/targets
#   python3 wh_freq.py --repo dotfiles --ext md,jinja,sh --top 60
# 孫3 以降が対象を決めるときと、導入後に読まれ方が変わったかを見るときに、同じ引数で期間だけ変えて再実行できる。
# 出力にはファイル名が入る。他リポの出力はリポの外（--out-dir）へ書き、公開する文書には集計値だけを写す。

import argparse
import collections
import datetime
import glob
import json
import os
import re
import sys

HOME = os.path.expanduser('~')
PROJ_ROOT = os.path.join(HOME, 'projects') + os.sep
EXCLUDE_REL = re.compile(r'^docs/(adr|planning)/')
SKILL_DEPLOYED = re.compile(r'^' + re.escape(HOME) + r'/\.claude/skills/([^/]+)/(.*)$')
LINK_REPO = 'dotfiles'
# 配布される claude/CLAUDE.md は全会話が読むので、順位の分母に入れると他が埋もれる。対象にも入れない（既存の節の書き直しの担当は、孫2 の PR で司令官に報告した）
SKIP_REL = {'claude/CLAUDE.md'}
_skill_known = {}


def is_dotfiles_skill(name):
    """dotfiles の skills/ にあるスキルか（プラグインや他のスキルを dotfiles の読み込みに数えないため）。"""
    if name not in _skill_known:
        _skill_known[name] = bool(glob.glob(os.path.join(PROJ_ROOT, LINK_REPO, '*', 'skills', name, 'SKILL.md')))
    return _skill_known[name]


def split_repo_path(path):
    """絶対パスを (リポ名, リポ内の相対パス) に分ける。~/projects/<リポ>/<作業ツリー>/<相対> の形だけを扱う。"""
    if path.startswith(PROJ_ROOT):
        parts = path[len(PROJ_ROOT):].split('/', 2)
        if len(parts) == 3:
            return parts[0], parts[2]
    m = SKILL_DEPLOYED.match(path)
    if m and is_dotfiles_skill(m.group(1)):
        return LINK_REPO, 'skills/%s/%s' % (m.group(1), m.group(2))
    if path == os.path.join(HOME, '.claude', 'CLAUDE.md'):
        return LINK_REPO, 'claude/CLAUDE.md'
    return None


def parse_time(s):
    return datetime.datetime.fromisoformat(s).astimezone() if s else None


def scan_session(path, since, until):
    """1つの会話ログから、(リポ, 相対パス) ごとの読み込み回数を返す。"""
    counts = collections.Counter()
    cwd_repo = None
    for line in open(path, errors='ignore'):
        if '"type":"assistant"' not in line and cwd_repo is not None:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if cwd_repo is None and d.get('cwd'):
            r = split_repo_path(d['cwd'] + '/x')
            if r:
                cwd_repo = r[0]
        if d.get('type') != 'assistant' or not d.get('timestamp'):
            continue
        t = datetime.datetime.fromisoformat(d['timestamp'].replace('Z', '+00:00')).astimezone()
        if (since and t < since) or (until and t >= until):
            continue
        for b in (d.get('message') or {}).get('content') or []:
            if not isinstance(b, dict) or b.get('type') != 'tool_use':
                continue
            inp = b.get('input') or {}
            if b.get('name') == 'Read':
                r = split_repo_path(str(inp.get('file_path', '')))
                if r:
                    counts[r] += 1
            elif b.get('name') == 'Skill':
                name = str(inp.get('skill', '')).split(':')[-1]
                if name and is_dotfiles_skill(name):
                    counts[(LINK_REPO, 'skills/%s/SKILL.md' % name)] += 1
    if cwd_repo and counts:
        # 自動で読み込まれる指示文は、期間内に何か読んだ会話にだけ数える
        for rel in ('CLAUDE.md', 'AGENTS.md'):
            counts[(cwd_repo, rel)] += 1
    return counts


def find_chars(repo, rel, cache):
    """文字数は、そのリポの存在する作業ツリーのうち最も新しく更新されたものから取る。"""
    key = (repo, rel)
    if key not in cache:
        cands = glob.glob(os.path.join(PROJ_ROOT, repo, '*', rel))
        cands = [c for c in cands if os.path.isfile(c)]
        if cands:
            newest = max(cands, key=os.path.getmtime)
            cache[key] = len(open(newest, errors='ignore').read())
        else:
            cache[key] = None
    return cache[key]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', help='ISO 8601。省略なら制限なし')
    ap.add_argument('--until', help='ISO 8601（この時刻を含まない）')
    ap.add_argument('--share', type=float, default=0.8, help='読まれた回数の累積がこの割合に達するまでを対象の候補にする')
    ap.add_argument('--repo', help='このリポだけを出す（リポ名。省略なら全部）')
    ap.add_argument('--ext', default='md,jinja', help='対象にする拡張子のコンマ区切り（コード・コマンドの文面を見るなら sh,py を足す）')
    ap.add_argument('--top', type=int, default=0, help='候補のうち上位だけを出す（0 なら全部）')
    ap.add_argument('--out-dir', help='リポごとの表を <リポ名>.md として書く先（リポの外のディレクトリ）。省略なら標準出力へ集計だけ')
    ap.add_argument('--exclude-project', help='除くプロジェクトのディレクトリ名の正規表現')
    a = ap.parse_args()
    since, until = parse_time(a.since), parse_time(a.until)
    exts = set(a.ext.split(','))
    ex = re.compile(a.exclude_project) if a.exclude_project else None
    total = collections.Counter()
    for f in glob.glob(os.path.join(HOME, '.claude/projects/*/*.jsonl')):
        proj = f.split('/projects/')[1].split('/')[0]
        if ex and ex.search(proj):
            continue
        if since and os.path.getmtime(f) < since.timestamp():
            continue
        total.update(scan_session(f, since, until))
    by_repo = collections.defaultdict(list)
    for (repo, rel), n in total.items():
        if EXCLUDE_REL.match(rel) or rel in SKIP_REL or rel.rsplit('.', 1)[-1] not in exts:
            continue
        if a.repo and repo != a.repo:
            continue
        by_repo[repo].append((rel, n))
    cache = {}
    print('期間 %s 〜 %s / 拡張子 %s / 累積 %.0f%%' % (a.since or '-', a.until or '-', a.ext, a.share * 100))
    print('リポ  読まれたファイル数  読まれた回数(全体)  候補のファイル数  候補の回数の割合  候補の合計字数')
    for repo in sorted(by_repo):
        rows = sorted(by_repo[repo], key=lambda r: -r[1])
        tot = sum(n for _, n in rows)
        acc, cand = 0, []
        for rel, n in rows:
            if acc / tot >= a.share:
                break
            acc += n
            cand.append((rel, n, find_chars(repo, rel, cache)))
        if a.top:
            cand = cand[:a.top]
        chars = sum(c or 0 for _, _, c in cand)
        print('%s  %d  %d  %d  %.2f  %d' % (repo, len(rows), tot, len(cand), acc / tot if tot else 0, chars))
        if a.out_dir:
            os.makedirs(a.out_dir, exist_ok=True)
            with open(os.path.join(a.out_dir, repo + '.md'), 'w') as fp:
                fp.write('# %s の書き直し対象の候補（期間 %s 〜 %s、累積 %.0f%%）\n\n' % (repo, a.since or '-', a.until or '-', a.share * 100))
                fp.write('候補（○）は、読まれた回数の累積が %.0f%% に達するまで。○の無い行は、読まれる頻度が低いので、持ち主の判断で足す。\n\n' % (a.share * 100))
                fp.write('| 候補 | ファイル | 読まれた回数 | 累積の割合 | 字数 |\n|---|---|---|---|---|\n')
                acc2, ncand = 0, len(cand)
                for i, (rel, n) in enumerate(rows):
                    acc2 += n
                    c = find_chars(repo, rel, cache)
                    fp.write('| %s | %s | %d | %.2f | %s |\n' % ('○' if i < ncand else '', rel, n, acc2 / tot, c if c is not None else '不明（今は無い）'))
                fp.write('\n候補は %d ファイル・合計 %d 字\n' % (ncand, chars))
        elif a.repo:
            acc2 = 0
            for rel, n, c in cand:
                acc2 += n
                print('  %s  %d  %.2f  %s' % (rel, n, acc2 / tot, c if c is not None else '-'))


if __name__ == '__main__':
    sys.exit(main())
