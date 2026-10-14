import json,glob,os,re,sys
from datetime import datetime,timezone,timedelta
JST=timezone(timedelta(hours=9))
since=datetime(2026,10,13,4,53,tzinfo=timezone.utc)
root=os.path.expanduser('~/.claude/projects')
for f in sorted(glob.glob(root+'/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    ev=[];pending={}
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        ts=d.get('timestamp')
        t=datetime.fromisoformat(ts.replace('Z','+00:00')) if ts else None
        if d.get('subtype')=='compact_boundary':
            m=d.get('compactMetadata',{})
            ev.append((t,'COMPACT',m.get('trigger'),m.get('preTokens')))
        msg=d.get('message') or {}
        c=msg.get('content') if isinstance(msg,dict) else None
        if isinstance(c,list):
            for x in c:
                if x.get('type')=='tool_use' and 'self-compact' in json.dumps(x.get('input',{})):
                    pending[x['id']]=t
                if x.get('type')=='tool_result' and x.get('tool_use_id') in pending:
                    r=x.get('content'); r=json.dumps(r,ensure_ascii=False)[:120]
                    ev.append((pending.pop(x['tool_use_id']),'SELFCMD',r,''))
                if x.get('type')=='text' and isinstance(x.get('text'),str) and x['text'].startswith('復帰メモがあれば読み'):
                    ev.append((t,'RESUME-PROMPT','',''))
    ev=[e for e in ev if e[0] and e[0]>=since]
    if ev:
        print('==',re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1),os.path.basename(f)[:8])
        for e in ev: print('  ',e[0].astimezone(JST).strftime('%m/%d %H:%M'),*e[1:])
