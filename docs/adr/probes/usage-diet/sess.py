# セッション別の重さ（文脈の合計・最大・30万超の呼び出し数）と、期間内の compact 回数。
# 費用の外れ値が1本のセッションに引っ張られていないかを確かめるのに使う。
# 使い方: USAGE_SINCE / USAGE_UNTIL を他のスクリプトと同じく渡し、引数に表示件数（既定 10）。
# 会話の本文は出さない（プロジェクトのディレクトリ名とセッション ID だけ）。
import json, glob, os, sys, datetime

since = datetime.datetime.fromisoformat(os.environ.get('USAGE_SINCE', '2026-10-11T16:00')).astimezone()
until = datetime.datetime.fromisoformat(os.environ.get('USAGE_UNTIL', '2026-10-12T22:00')).astimezone()
top = int(sys.argv[1]) if len(sys.argv) > 1 else 10


def ts(d):
    return datetime.datetime.fromisoformat(d['timestamp'].replace('Z', '+00:00'))


rows = []
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    if os.path.getmtime(f) < since.timestamp():
        continue
    ctx = {}
    compacts = 0
    for line in open(f, errors='ignore'):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if not d.get('timestamp') or not (since <= ts(d) < until):
            continue
        if d.get('type') == 'system' and d.get('subtype') == 'compact_boundary':
            compacts += 1
        if d.get('type') == 'assistant':
            m = d.get('message', {})
            u = m.get('usage') or {}
            if m.get('id'):
                ctx[m['id']] = sum(u.get(k, 0) for k in ('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens'))
    if not ctx:
        continue
    v = list(ctx.values())
    proj = f.split('/projects/')[1].split('/')[0]
    sid = os.path.basename(f)[:8]
    rows.append((sum(v), max(v), sum(c > 300000 for c in v), len(v), compacts, proj, sid))

rows.sort(reverse=True)
print('文脈の合計  最大  30万超/呼び出し  compact  プロジェクト  セッション')
for total, mx, over, n, comp, proj, sid in rows[:top]:
    print(f'{total / 1e6:7.0f}M {mx / 1e3:5.0f}k {over:5d}/{n:5d} {comp:3d} {proj} {sid}')
