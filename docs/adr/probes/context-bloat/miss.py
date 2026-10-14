import json,glob,os,re
from datetime import datetime,timezone
since=datetime(2026,10,13,4,53,tzinfo=timezone.utc)
root=os.path.expanduser('~/.claude/projects')
agg={}
for f in glob.glob(root+'/*/*.jsonl'):
    if os.path.getmtime(f)<since.timestamp(): continue
    name=re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1)
    first=None;seen=set();calls=[]
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        if first is None and d.get('type')=='user':
            c=(d.get('message') or {}).get('content'); first=c if isinstance(c,str) else json.dumps(c,ensure_ascii=False)
        m=d.get('message') or {}
        if d.get('type')=='assistant' and m.get('usage') and m.get('id') not in seen:
            seen.add(m['id']);calls.append(d)
    role='review' if first and 'PRレビュー' in first[:200] else ('impl' if re.search(r'-\d\d-',name) else 'other')
    a=agg.setdefault(role,dict(sess=0,n=0,big=0,cost=0,excess=0))
    a['sess']+=1
    for d in calls:
        if datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))<since: continue
        u=d['message']['usage'];r=u.get('cache_read_input_tokens',0);w=u.get('cache_creation_input_tokens',0);ctx=r+w+u.get('input_tokens',0)
        rate=(r*.2+w*5)/(r+w) if r+w else .2  # $/M blended
        a['n']+=1;a['cost']+=(r*.2+w*5+u.get('output_tokens',0)*15)/1e6
        if ctx>200000: a['big']+=1;a['excess']+=(ctx-80000)*rate/1e6
for k,a in agg.items(): print(k,{x:round(y,2) for x,y in a.items()})
