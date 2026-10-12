import json,glob,os,sys,collections,datetime
since=datetime.datetime(2026,10,11,16,0).astimezone()
msgs={}
for f in glob.glob(os.path.expanduser('~/.claude/projects/**/*.jsonl'),recursive=True):
    if os.path.getmtime(f)<since.timestamp(): continue
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        if d.get('type')!='assistant':continue
        ts=d.get('timestamp')
        if not ts:continue
        t=datetime.datetime.fromisoformat(ts.replace('Z','+00:00'))
        if t<since:continue
        m=d.get('message',{});u=m.get('usage') or {}
        if not m.get('id'):continue
        msgs[m['id']]=(f,m.get('model'),u,t,d.get('sessionId'),d.get('isSidechain'))
def w(u): return u.get('input_tokens',0)+u.get('output_tokens',0)+u.get('cache_creation_input_tokens',0)+u.get('cache_read_input_tokens',0)
by=collections.defaultdict(lambda:[0,0,0,0,0,0])
bym=collections.Counter(); byh=collections.Counter(); byproj=collections.Counter()
for f,mo,u,t,s,sc in msgs.values():
    k=(f.split('/projects/')[1].split('/')[0], s)
    r=by[k]; r[0]+=1; r[1]+=u.get('input_tokens',0); r[2]+=u.get('output_tokens',0); r[3]+=u.get('cache_creation_input_tokens',0); r[4]+=u.get('cache_read_input_tokens',0)
    bym[mo]+=w(u); byh[t.astimezone().strftime('%m-%d %H')]+=w(u); byproj[k[0]]+=w(u)
print('msgs',len(msgs))
print('== model'); [print(f'{v:>14,} {k}') for k,v in bym.most_common()]
print('== project'); [print(f'{v:>14,} {k}') for k,v in byproj.most_common(15)]
print('== top sessions (n, in, out, cache_create, cache_read)')
for k,r in sorted(by.items(),key=lambda x:-(x[1][1]+x[1][2]+x[1][3]+x[1][4]))[:15]:
    print(r[:5], k[0][-45:], k[1])
print('== hourly'); [print(k, f'{v:,}') for k,v in sorted(byh.items())]
print('== sessions', len(by), 'projects', len(byproj))
ctx=[ (u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)+u.get('input_tokens',0), mo, sc) for f,mo,u,t,s,sc in msgs.values()]
import statistics
for mo in set(c[1] for c in ctx):
    xs=sorted(c[0] for c in ctx if c[1]==mo)
    if xs: print(mo, 'calls',len(xs),'median ctx',xs[len(xs)//2],'p90',xs[int(len(xs)*.9)],'>300k',sum(x>300000 for x in xs))
print('sidechain calls', sum(1 for c in ctx if c[2]), 'tokens', sum(c[0] for c in ctx if c[2]))
# overnight 02-08 sessions
night=collections.Counter()
for f,mo,u,t,s,sc in msgs.values():
    if 2<=t.astimezone().hour<8: night[f.split('/projects/')[1][:70]]+=1
print('== night calls'); [print(v,k) for k,v in night.most_common(8)]
