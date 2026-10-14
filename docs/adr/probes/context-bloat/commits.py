# 実装の孫ごとに、git commit の呼び出し番号とそのときの文脈、最初の gh pr create の番号を出す。
# 実装途中の区切り（コミット直後・文脈が閾値超）が、実際にどのくらい来るかを見る（ADR DOC-2610142337）。
import json,glob,os,re,sys
from datetime import datetime,timezone
since=datetime(2026,10,13,4,53,tzinfo=timezone.utc)
THR=int(sys.argv[1]) if len(sys.argv)>1 else 200000
root=os.path.expanduser('~/.claude/projects')
for f in sorted(glob.glob(root+'/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    name=re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1)
    if not re.search(r'-\d\d-',name): continue
    seen=set();n=0;ctx=0;pr=None;commits=[];first=None
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        if first is None and d.get('type')=='user':
            c=(d.get('message') or {}).get('content'); first=c if isinstance(c,str) else json.dumps(c,ensure_ascii=False)
        m=d.get('message') or {}
        if d.get('type')=='assistant' and m.get('usage') and m.get('id') not in seen:
            seen.add(m['id']);n+=1;u=m['usage']
            ctx=u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)+u.get('input_tokens',0)
        c=m.get('content')
        if isinstance(c,list):
            for x in c:
                if x.get('type')!='tool_use': continue
                s=json.dumps(x.get('input',{}),ensure_ascii=False)
                if re.search(r'git commit',s) and pr is None: commits.append((n,ctx))
                if pr is None and 'gh pr create' in s: pr=n  # commit と同じ呼び出しで PR を作る孫は、そのコミットも数える
    if n<30 or 'PRレビュー' in (first or '')[:200]: continue  # レビュワーは miss.py と同じ判定で除く
    hits=[(i,c) for i,c in commits if c>THR]
    print(f"{name:40} calls={n:4} pr_create@{pr} commits_before_pr={len(commits)} over{THR//1000}k={len(hits)} first_hit@{hits[0][0] if hits else None}")
