import json,glob,os,re
from datetime import datetime,timezone
since=datetime(2026,10,13,4,53,tzinfo=timezone.utc)
root=os.path.expanduser('~/.claude/projects')
for f in sorted(glob.glob(root+'/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    name=re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1)
    if not re.search(r'-\d\d-',name): continue
    seen=set();n=0;cross=None;pr=None;tools={};maxc=0;big_tools={}
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        m=d.get('message') or {}
        if d.get('type')=='assistant' and m.get('usage') and m.get('id') not in seen:
            seen.add(m['id']);n+=1;u=m['usage']
            ctx=u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)+u.get('input_tokens',0)
            maxc=max(maxc,ctx)
            if ctx>200000 and cross is None: cross=n
        c=m.get('content')
        if isinstance(c,list):
            for x in c:
                if x.get('type')=='tool_use':
                    s=json.dumps(x.get('input',{}))
                    if pr is None and 'gh pr create' in s: pr=n
                if x.get('type')=='tool_result':
                    t=json.dumps(x.get('content'),ensure_ascii=False)
                    tools.setdefault('_',0); tools['_']+=len(t)
    if n<30: continue
    print(f"{name:40} calls={n:4} max={maxc//1000}k cross200k@{cross} pr_create@{pr} toolresult_chars={tools.get('_',0)//1000}k")
