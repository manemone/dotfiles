import json,glob,os,re
from datetime import datetime,timezone,timedelta
JST=timezone(timedelta(hours=9))
since=datetime(2026,10,13,4,53,tzinfo=timezone.utc)
root=os.path.expanduser('~/.claude/projects')
P='復帰メモがあれば読み、計画書の続きから再開'
for f in sorted(glob.glob(root+'/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    rows=[]
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        rows.append(d)
    selfq=False
    for i,d in enumerate(rows):
        s=json.dumps(d,ensure_ascii=False)
        if d.get('type')=='user' and 'queued /compact for pane' in s: selfq=True
        if d.get('subtype')=='compact_boundary' and selfq:
            selfq=False
            t0=datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
            pre=d.get('compactMetadata',{}).get('preTokens')
            resume=None;post=None;turns=0
            for e in rows[i+1:]:
                m=e.get('message') or {}
                if e.get('type')=='user' and not e.get('isCompactSummary') and resume is None:
                    c=m.get('content')
                    txt=c if isinstance(c,str) else ' '.join(x.get('text','') for x in c if isinstance(x,dict))
                    if P in txt:
                        resume=datetime.fromisoformat(e['timestamp'].replace('Z','+00:00'))
                if e.get('type')=='assistant' and resume and post is None:
                    u=m.get('usage',{})
                    post=u.get('input_tokens',0)+u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)
                if e.get('type')=='assistant' and resume: turns+=1
            name=re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1)
            dt=f"+{(resume-t0).seconds//60}m" if resume else 'NO RESUME'
            print(f"{t0.astimezone(JST):%m/%d %H:%M} {name:40} pre={pre} post={post} resume={dt} turns_after={turns}")
