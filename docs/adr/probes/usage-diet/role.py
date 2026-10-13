import json,glob,os,re,collections,datetime
since=datetime.datetime.fromisoformat(os.environ.get('USAGE_SINCE','2026-10-11T16:00')).astimezone()
until=datetime.datetime.fromisoformat(os.environ.get('USAGE_UNTIL','2026-10-12T22:00')).astimezone()
# 集計対象のリポ名をカンマ区切りで渡す（例: USAGE_REPOS=dotfiles,other-repo）
REPOS=[r for r in os.environ.get('USAGE_REPOS','dotfiles').split(',') if r]
def branch(proj):
    p=re.sub(r'^.*?-projects-','',proj,count=1)
    for r in REPOS:
        if p.startswith(r+'-'): return r,p[len(r)+1:]
    return '?',p
def classify(proj,texts):
    r,b=branch(proj)
    if any('PRレビューを実行してください' in t for t in texts[:2]): return 'レビュー'
    if b in('master','main'): return '会話'
    if b=='training-sessions': return '会話(学習)'
    if re.match(r'^[a-z0-9]+-\d\d-',b): return '実装'
    if any('孫' in t and 'プロンプ' in t for t in texts[:2]): return '実装'
    return '司令官'
agg=collections.defaultdict(lambda:collections.Counter()); nsess=collections.Counter()
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    proj=f.split('/projects/')[1].split('/')[0]
    texts=[];msgs={}
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        if d.get('type')=='user' and not d.get('isMeta') and len(texts)<3:
            c=d['message'].get('content')
            if isinstance(c,list): c=' '.join(x.get('text','') for x in c if isinstance(x,dict))
            if c and not c.startswith('<local-command') and 'command-name>' not in c and not c.startswith('<task-notification'): texts.append(c)
        if d.get('type')=='assistant' and d.get('timestamp'):
            t=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
            m=d.get('message',{})
            if since<=t<until and m.get('id'): msgs[m['id']]=(m.get('model') or '',m.get('usage') or {})
    if not msgs: continue
    role=classify(proj,texts); nsess[role]+=1
    for mo,u in msgs.values():
        tok=sum(u.get(k,0) for k in('input_tokens','output_tokens','cache_creation_input_tokens','cache_read_input_tokens'))
        mult=0.6 if 'sonnet' in mo else (0.2 if 'haiku' in mo else 1)
        cost=mult*(u.get('input_tokens',0)+1.25*u.get('cache_creation_input_tokens',0)+0.1*u.get('cache_read_input_tokens',0)+5*u.get('output_tokens',0))
        a=agg[role]; a['calls']+=1; a['tok']+=tok; a['cost']+=cost
        a['opus' if 'opus' in mo else 'other']+=tok
T=sum(a['tok'] for a in agg.values()); C=sum(a['cost'] for a in agg.values())
print(f"{'role':10} sess calls  tokens(億) tok% cost% opus%")
for r,a in sorted(agg.items(),key=lambda x:-x[1]['cost']):
    print(f"{r:10} {nsess[r]:4} {a['calls']:5} {a['tok']/1e8:8.2f} {100*a['tok']/T:5.1f} {100*a['cost']/C:5.1f} {100*a['opus']/a['tok']:5.0f}")
