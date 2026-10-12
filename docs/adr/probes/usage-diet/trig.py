import json,glob,os,re,collections,datetime,sys
sys.path.insert(0,'')
since=datetime.datetime(2026,10,11,16,0).astimezone()
exec(open(os.path.join(os.path.dirname(__file__),'role.py')).read().split('agg=collections')[0])
P={'opus':(4,20,0.20,5,8),'sonnet':(2,10,0.20,2.5,4),'haiku':(0.10,0.50,0.01,0.125,0.20)}
def cost(mo,u):
    k='opus' if 'opus' in mo else ('sonnet' if 'sonnet' in mo else 'haiku')
    pi,po,pr,p5,p1=P[k]; cc=u.get('cache_creation') or {}
    w1=cc.get('ephemeral_1h_input_tokens',0); w5=cc.get('ephemeral_5m_input_tokens',0) if cc else u.get('cache_creation_input_tokens',0)
    return (pi*u.get('input_tokens',0)+po*u.get('output_tokens',0)+pr*u.get('cache_read_input_tokens',0)+p5*w5+p1*w1)/1e6
by=collections.Counter(); turns=collections.Counter(); samples={}
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    proj=f.split('/projects/')[1].split('/')[0]
    lines=[]
    for line in open(f,errors='ignore'):
        try: lines.append(json.loads(line))
        except: pass
    texts=[]
    for d in lines:
        if d.get('type')=='user' and not d.get('isMeta') and len(texts)<3:
            c=d['message'].get('content')
            if isinstance(c,list): c=' '.join(x.get('text','') for x in c if isinstance(x,dict))
            if c and not c.startswith('<local-command') and 'command-name>' not in c and not c.startswith('<task-notification'): texts.append(c)
    if classify(proj,texts)!='司令官': continue
    trig='?'; seen=set()
    for d in lines:
        if d.get('type')=='user':
            c=d['message'].get('content')
            if isinstance(c,list):
                if all(isinstance(x,dict) and x.get('type')=='tool_result' for x in c): continue
                c=' '.join(x.get('text','') for x in c if isinstance(x,dict))
            if not c: continue
            if c.startswith('# 傘ブランチ自動進行'): trig='cron巡回'
            elif c.startswith('Base directory for this skill') or c.startswith('[Image'): continue
            elif 'Another Claude session sent a message' in c: trig='セッション間メッセージ'
            elif 'マージしました' in c and len(c)<200: trig='孫の完了通知'
            elif c.startswith('<task-notification'): trig='バックグラウンド/Monitor通知'
            elif c.startswith('This session is being continued'): trig='compact後の再開'
            else: trig='人間/その他'
            turns[trig]+=1; samples.setdefault(trig,c[:100])
        if d.get('type')=='assistant' and d.get('timestamp'):
            t=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
            m=d.get('message',{})
            if t>=since and m.get('id') and m['id'] not in seen:
                seen.add(m['id']); by[trig]+=cost(m.get('model') or '',m.get('usage') or {})
T=sum(by.values())
for k,v in by.most_common(): print(f'{k:24} ${v:6.0f} {100*v/T:4.0f}%  turns={turns[k]}')
for k,v in samples.items(): print('--',k,'|',v.replace('\n',' '))
