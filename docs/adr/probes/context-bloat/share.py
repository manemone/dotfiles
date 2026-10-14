"""実装の孫ごとに、文脈の最大値の内訳（ツール結果・出力・その他）を見る。

最大文脈（トークン）に対し、出力トークンの累計（思考・本文・ツール入力が文脈へ積まれる分）と
ツール呼び出しの入力文字数も並べる。
ツール結果は文字数を 3.5 文字/トークンで換算して並べる（日本語は 1 文字あたりのトークンが多いので過小見積り）。
差分は、スキル本文の注入・会話・思考・システム部分など、ツール結果以外が押し上げた分。
スキル本文は tool_result に載らず別メッセージで入るので、Skill 呼び出し直後の文脈の増分も出す。
"""
import json, glob, os, re
from datetime import datetime, timezone

since = datetime(2026, 10, 13, 4, 53, tzinfo=timezone.utc)
root = os.path.expanduser('~/.claude/projects')
rows = []
skill_jumps = []
for f in sorted(glob.glob(root + '/*/*.jsonl')):
    if os.path.getmtime(f) < since.timestamp(): continue
    name = re.sub(r'^.*?-projects-', '', f.split('/')[-2], count=1)
    if not re.search(r'-\d\d-', name): continue
    seen = set(); n = 0; first = None; maxc = 0; chars = 0; prev = None; skill_pending = None; out_tok = 0; use_chars = 0
    for line in open(f, errors='ignore'):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get('message') or {}
        c = m.get('content')
        if d.get('type') == 'assistant' and m.get('usage') and m.get('id') not in seen:
            seen.add(m['id']); n += 1; u = m['usage']; out_tok += u.get('output_tokens', 0)
            ctx = u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0) + u.get('input_tokens', 0)
            if first is None: first = ctx
            maxc = max(maxc, ctx)
            if skill_pending is not None and prev is not None:
                skill_jumps.append((skill_pending, ctx - prev)); skill_pending = None
            prev = ctx
        if isinstance(c, list):
            for x in c:
                if x.get('type') == 'tool_use': use_chars += len(json.dumps(x.get('input', {}), ensure_ascii=False))
                if x.get('type') == 'tool_use' and x.get('name') == 'Skill':
                    skill_pending = (x.get('input') or {}).get('skill', '?')
                if x.get('type') == 'tool_result':
                    rc = x.get('content')
                    if isinstance(rc, str): chars += len(rc)
                    elif isinstance(rc, list): chars += sum(len(y.get('text', '')) for y in rc if y.get('type') == 'text')
    if n >= 30: rows.append((maxc, name, n, first, chars, out_tok, use_chars))
rows.sort(reverse=True)
print(f'{"session":40} calls  first  max   toolres(est tok)  other(max-first-toolres)')
for maxc, name, n, first, chars, out_tok, use_chars in rows[:25]:
    tr = int(chars / 3.5)
    print(f'{name:40} {n:4} {first//1000:5}k {maxc//1000:4}k {tr//1000:8}k {(maxc-first-tr)//1000:8}k out={out_tok//1000}k use_in_chars={use_chars//1000}k')
import collections
agg = collections.defaultdict(list)
for s, j in skill_jumps: agg[s].append(j)
print('\n== Skill call -> next-call context jump (tokens)')
for s, js in sorted(agg.items(), key=lambda kv: -sum(kv[1])):
    js.sort(); print(f'{s:28} n={len(js):3} median={js[len(js)//2]//1000}k max={js[-1]//1000}k')
