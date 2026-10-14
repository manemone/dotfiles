import json,glob,os,re
from datetime import datetime,timezone,timedelta
JST=timezone(timedelta(hours=9))
since=datetime(2026,10,13,4,53,tzinfo=timezone.utc)
PR={'opus':dict(inp=4,out=20,r=.2,w5=5,w1=8),'sonnet':dict(inp=2,out=10,r=.2,w5=2.5,w1=4),
    'fable':dict(inp=10,out=50,r=.25,w5=12.5,w1=20),'haiku':dict(inp=.1,out=.5,r=.01,w5=.125,w1=.2)}
def price(model):
    for k in PR:
        if k in (model or ''): return PR[k]
    return PR['opus']
def ts(d): return datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
root=os.path.expanduser('~/.claude/projects')
tot_save=tot_cost=tot_sess=0;rows_out=[]
for f in sorted(glob.glob(root+'/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    rows=[]
    for line in open(f,errors='ignore'):
        try:rows.append(json.loads(line))
        except:pass
    # dedupe assistant calls
    calls=[];seen=set();events=[]
    for i,d in enumerate(rows):
        if d.get('subtype')=='compact_boundary': events.append(('C',i,d))
        if d.get('type')=='user' and 'queued /compact for pane' in json.dumps(d,ensure_ascii=False): events.append(('Q',i,d))
        m=d.get('message') or {}
        if d.get('type')=='assistant' and m.get('usage') and m.get('id') not in seen:
            seen.add(m.get('id')); calls.append((i,d))
    sess_cost=0
    def cost(d):
        u=d['message']['usage'];p=price(d['message'].get('model'))
        cc=u.get('cache_creation') or {}
        w1=cc.get('ephemeral_1h_input_tokens',0); w5=u.get('cache_creation_input_tokens',0)-w1
        return (u.get('input_tokens',0)*p['inp']+u.get('output_tokens',0)*p['out']+u.get('cache_read_input_tokens',0)*p['r']+w5*p['w5']+w1*p['w1'])/1e6
    for i,d in calls:
        if ts(d)>=since: sess_cost+=cost(d)
    tot_sess+=sess_cost
    bounds=[i for k,i,d in events if k=='C']
    lastQ=None
    for k,i,d in events:
        if k=='Q': lastQ=ts(d); continue
        if not lastQ or (ts(d)-lastQ)>timedelta(minutes=10) or ts(d)<since: lastQ=None; continue
        lastQ=None
        pre=d.get('compactMetadata',{}).get('preTokens',0)
        nxt=min([b for b in bounds if b>i],default=10**9)
        after=[c for j,c in calls if i<j<nxt]
        if not after: continue
        u0=after[0]['message']['usage']
        post=u0.get('input_tokens',0)+u0.get('cache_read_input_tokens',0)+u0.get('cache_creation_input_tokens',0)
        D=pre-post; save=0
        for c in after[1:]:
            u=c['message']['usage'];p=price(c['message'].get('model'))
            r=u.get('cache_read_input_tokens',0);w=u.get('cache_creation_input_tokens',0)
            cc=u.get('cache_creation') or {};w1=cc.get('ephemeral_1h_input_tokens',0)
            fw=w/(r+w) if r+w else 0; wp=(p['w1'] if w1>w/2 else p['w5'])
            save+=D*(fw*wp+(1-fw)*p['r'])/1e6
        p=price(after[0]['message'].get('model'))
        u=u0;cc=u.get('cache_creation') or {}
        wp=p['w1'] if cc.get('ephemeral_1h_input_tokens',0)>u.get('cache_creation_input_tokens',0)/2 else p['w5']
        c_cost=(pre*p['r']+10000*p['out']+u.get('cache_creation_input_tokens',0)*(wp-p['r']))/1e6
        tot_save+=save;tot_cost+=c_cost
        hrs=(ts(after[-1])-ts(d)).total_seconds()/3600
        rows_out.append(f"{ts(d).astimezone(JST):%m/%d %H:%M} {re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1):38} {after[0]['message'].get('model','')[:15]:15} pre={pre//1000}k post={post//1000}k calls={len(after):5} span={hrs:4.1f}h save=${save:6.2f} cost=${c_cost:5.2f}")
print(*rows_out,sep='\n')
print(f"\nTOTAL gross save=${tot_save:.2f}  compact cost=${tot_cost:.2f}  net=${tot_save-tot_cost:.2f}")
print(f"all sessions spend since deploy (API換算) = ${tot_sess:.2f}")
