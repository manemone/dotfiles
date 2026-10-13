import json,glob,os,re,collections,datetime
since=datetime.datetime.fromisoformat(os.environ.get('USAGE_SINCE','2026-10-11T16:00')).astimezone()
until=datetime.datetime.fromisoformat(os.environ.get('USAGE_UNTIL','2026-10-12T22:00')).astimezone()
P={'opus':(4,20,0.20,5,8),'sonnet':(2,10,0.20,2.5,4),'haiku':(0.10,0.50,0.01,0.125,0.20)}
def cost(mo,u):
    k='opus' if 'opus' in mo else ('sonnet' if 'sonnet' in mo else 'haiku')
    pi,po,pr,p5,p1=P[k]; cc=u.get('cache_creation') or {}
    w1=cc.get('ephemeral_1h_input_tokens',0); w5=cc.get('ephemeral_5m_input_tokens',0) if cc else u.get('cache_creation_input_tokens',0)
    return (pi*u.get('input_tokens',0)+po*u.get('output_tokens',0)+pr*u.get('cache_read_input_tokens',0)+p5*w5+p1*w1)/1e6
by=collections.Counter(); n=collections.Counter(); recv=collections.Counter()
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    trig='other'; seen=set()
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        if d.get('type')=='user':
            c=d['message'].get('content')
            if isinstance(c,list):
                if all(isinstance(x,dict) and x.get('type')=='tool_result' for x in c): continue
                c=' '.join(x.get('text','') for x in c if isinstance(x,dict))
            if not c or c.startswith('Base directory') or c.startswith('[Image'): continue
            if 'Another Claude session sent a message' in c:
                b=re.sub(r'.*?<cross-session-message[^>]*>','',c,flags=re.S).strip()
                if b.startswith('ハブ') or b.startswith('【ハブ'): trig='ハブの周知'
                elif '返事は不要' in b[:80] or '返事は要りません' in b[:80] or 'お知らせ' in b[:40]: trig='他の傘からのお知らせ'
                elif b.startswith(('計画書','ブリーフ')): trig='spawn・引き継ぎ指示'
                elif re.search(r'PR\s*#?\d+',b[:200]): trig='PR・承認・マージの報告'
                else: trig='その他のセッション間'
                t=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
                if since<=t<until: n[trig]+=1
            else: trig='other'
        if d.get('type')=='assistant' and d.get('timestamp'):
            t=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
            m=d.get('message',{})
            if since<=t<until and m.get('id') and m['id'] not in seen:
                seen.add(m['id']); by[trig]+=cost(m.get('model') or '',m.get('usage') or {})
T=sum(by.values())
for k,v in by.most_common(): print(f'{k:16} ${v:6.0f} {100*v/T:4.1f}%  受信={n[k]}')
