"""実装の孫のツール結果の内訳。種類・Bash 先頭語・1回の大きさ・読み直しを出す。

文字数に加え、次の呼び出しの文脈の増分（トークン）を、直前のツール結果へ文字数比で配って見る。
画像は文字数で測れないため、増分から画像以外の分を引いた残りで見る代わりに件数だけ数える。
出力は大きくなりうるので、ファイルへ書き出してから要約を見ること。
"""
import json, glob, os, re, collections
from datetime import datetime, timezone

since = datetime(2026, 10, 13, 4, 53, tzinfo=timezone.utc)
root = os.path.expanduser('~/.claude/projects')
kind_chars = collections.Counter(); kind_tok = collections.Counter(); kind_n = collections.Counter()
bash_chars = collections.Counter(); bash_tok = collections.Counter(); bash_n = collections.Counter()
sizes = []; images = 0
repeat = collections.Counter(); sessions = 0


def clen(c):
    if isinstance(c, str): return len(c)
    if isinstance(c, list):
        return sum(len(x.get('text', '')) if x.get('type') == 'text' else 0 for x in c)
    return 0


def head_word(cmd):
    cmd = cmd.strip()
    cmd = re.sub(r'^(cd [^;&|]+(&&|;)\s*)', '', cmd)
    cmd = re.sub(r'^(\w+=\S+\s+)+', '', cmd)
    w = cmd.split()
    if not w: return '?'
    if w[0] in ('git', 'gh', 'ocw') and len(w) > 1: return w[0] + ' ' + w[1]
    if w[0] in ('python3', 'python') and '-m' in w: return 'python -m ' + w[w.index('-m') + 1]
    return w[0]


for f in sorted(glob.glob(root + '/*/*.jsonl')):
    if os.path.getmtime(f) < since.timestamp(): continue
    name = re.sub(r'^.*?-projects-', '', f.split('/')[-2], count=1)
    if not re.search(r'-\d\d-', name): continue
    seen = set(); prev_ctx = None; pending = []; uses = {}; sessions += 1
    for line in open(f, errors='ignore'):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get('message') or {}
        c = m.get('content')
        if d.get('type') == 'assistant' and m.get('usage') and m.get('id') not in seen:
            seen.add(m['id']); u = m['usage']
            ctx = u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0) + u.get('input_tokens', 0)
            if prev_ctx is not None and pending:
                delta = max(ctx - prev_ctx, 0)
                tot = sum(p[2] for p in pending) or 1
                for kind, bw, ch in pending:
                    t = delta * ch / tot
                    kind_tok[kind] += t
                    if bw: bash_tok[bw] += t
            pending = []; prev_ctx = ctx
        if isinstance(c, list):
            for x in c:
                if x.get('type') == 'tool_use':
                    inp = x.get('input', {})
                    key = x['name']
                    if key.startswith('mcp__'): key = 'mcp'
                    bw = head_word(inp.get('command', '')) if x['name'] == 'Bash' else None
                    sig = x['name'] + ':' + (inp.get('command') or inp.get('file_path') or inp.get('pattern') or '')[:200]
                    uses[x['id']] = (key, bw, sig)
                if x.get('type') == 'tool_result':
                    key, bw, sig = uses.get(x.get('tool_use_id'), ('?', None, '?'))
                    rc = x.get('content')
                    if isinstance(rc, list): images += sum(1 for y in rc if y.get('type') == 'image')
                    ch = clen(rc)
                    kind_chars[key] += ch; kind_n[key] += 1; sizes.append(ch)
                    if bw: bash_chars[bw] += ch; bash_n[bw] += 1
                    if ch > 5000: repeat[sig] += 1
                    pending.append((key, bw, max(ch, 1)))

print(f'sessions={sessions} tool_results={len(sizes)} images={images}')
print('\n== kind: n / chars(k) / est tokens(k)')
for k, v in kind_chars.most_common(): print(f'{k:12} {kind_n[k]:6} {v//1000:8} {int(kind_tok[k])//1000:8}')
print('\n== Bash head word: n / chars(k) / est tokens(k)')
for k, v in bash_chars.most_common(20): print(f'{k:28} {bash_n[k]:6} {v//1000:8} {int(bash_tok[k])//1000:8}')
sizes.sort(reverse=True); tot = sum(sizes) or 1
print('\n== size distribution (chars)')
for lo, hi in [(0, 1000), (1000, 5000), (5000, 20000), (20000, 10**9)]:
    s = [x for x in sizes if lo <= x < hi]
    print(f'{lo:>6}-{hi if hi<10**9 else "inf":>6}: n={len(s):6} share={100*sum(s)/tot:5.1f}%')
print('top10 share of chars: %.1f%%' % (100 * sum(sizes[:10]) / tot))
print('\n== large (>5000) results repeated within a session-run: count>=2')
print(sum(1 for v in repeat.values() if v >= 2), 'of', len(repeat), 'distinct signatures')
