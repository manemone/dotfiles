"""設計3 の観点（キャッシュ書き込み・固定部分・文脈の太り方・レビュアー）で実ログを深掘りする。

使い方: USAGE_REPOS=dotfiles,<他のリポ名> python3 -I deep.py <cache|fixed|band|tools|review|all>
期間は USAGE_SINCE / USAGE_UNTIL（ISO 8601。既定は 2026-10-11T16:00〜2026-10-12T22:00。背景4 の期間（終わりは 21:xx）とほぼ同じで、終わりだけ 22:00 に固定）。
ログは読むだけで書き換えない。会話の本文は集計に使うだけで出力しない（分類名・数値だけを出す）。
"""
import json,glob,os,re,collections,datetime,statistics,sys
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'role.py')).read().split('agg=collections')[0])  # since / until / REPOS / classify を共有
P={'opus':(4,20,0.20,5,8),'sonnet':(2,10,0.20,2.5,4),'haiku':(0.10,0.50,0.01,0.125,0.20)}
CHARS_PER_TOKEN=3.0  # 日本語混じりの粗い換算。文字数→トークン数の見積もりにだけ使う
ROLES=['実装','司令官','レビュー','会話(学習)','会話']


def price(mo):
    return P['opus' if 'opus' in mo else ('sonnet' if 'sonnet' in mo else 'haiku')]


def writes(u):
    cc=u.get('cache_creation') or {}
    if cc: return cc.get('ephemeral_5m_input_tokens',0),cc.get('ephemeral_1h_input_tokens',0)
    return u.get('cache_creation_input_tokens',0),0


def ctx(u):
    return u.get('input_tokens',0)+u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)


def cost_parts(mo,u):
    pi,po,pr,p5,p1=price(mo); w5,w1=writes(u)
    return dict(read=pr*u.get('cache_read_input_tokens',0)/1e6,write=(p5*w5+p1*w1)/1e6,
                out=po*u.get('output_tokens',0)/1e6,inp=pi*u.get('input_tokens',0)/1e6)


def text_of(c):
    if isinstance(c,list): return ' '.join(x.get('text','') for x in c if isinstance(x,dict))
    return c or ''


def tool_label(x):
    """tool_use を集計用の分類名にする（Bash はコマンドの先頭語、Read はパスの種類。中身は出さない）。"""
    n=x.get('name'); i=x.get('input') or {}
    if n=='Bash':
        segs=[g.strip() for g in re.split(r'&&|;|\|\|',i.get('command') or '') if g.strip()]
        segs=[g for g in segs if not g.startswith(('cd ','export '))] or ['?']
        w=[v for v in segs[0].split() if not re.match(r'^[A-Za-z_]+=',v)] or ['?']
        return 'Bash:'+os.path.basename(w[0])
    if n=='Read':
        p=i.get('file_path') or ''
        if p.endswith('SKILL.md'): return 'Read:SKILL.md'
        if '/planning/' in p: return 'Read:計画書'
        if p.endswith(('AGENTS.md','CLAUDE.md')): return 'Read:AGENTS/CLAUDE.md'
        return 'Read:その他'
    return n


def load():
    """セッションごとに、期間内の assistant 呼び出し（message.id で重複排除）と、期間内の user/tool_result を読む。"""
    out=[]
    for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
        if os.path.getmtime(f)<since.timestamp(): continue
        proj=f.split('/projects/')[1].split('/')[0]
        texts=[]; calls={}; order=[]; events=[]; tool_names={}; humans=0; rereview=0
        for line in open(f,errors='ignore'):
            try: d=json.loads(line)
            except: continue
            ty=d.get('type')
            if ty=='user' and d.get('isMeta'):
                s=text_of(d['message'].get('content'))
                if s.startswith('Base directory for this skill'):
                    m=re.search(r'skills/([^/\s]+)',s.split('\n',1)[0])
                    events.append(('skill',len(order),m.group(1) if m else '?',len(s)))
            if ty=='user' and not d.get('isMeta'):
                c=d['message'].get('content')
                if len(texts)<3:
                    s=text_of(c)
                    if s and not s.startswith('<local-command') and 'command-name>' not in s and not s.startswith('<task-notification'): texts.append(s)
                if isinstance(c,list) and any(isinstance(x,dict) and x.get('type')=='tool_result' for x in c):
                    for x in c:
                        if isinstance(x,dict) and x.get('type')=='tool_result':
                            events.append(('result',len(order),tool_names.get(x.get('tool_use_id'),'?'),len(text_of(x.get('content')))))
                else:
                    s=text_of(c)
                    if s.startswith('Base directory for this skill'):
                        m=re.search(r'skills/([^/\s]+)',s.split('\n',1)[0])
                        events.append(('skill',len(order),m.group(1) if m else '?',len(s)))
                    elif '再レビュー依頼' in s[:40]: rereview+=1
                    elif s and not s.startswith('<'): humans+=1
            if ty=='assistant' and d.get('timestamp'):
                m=d.get('message',{}); i=m.get('id')
                if not i: continue
                t=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
                for x in m.get('content') or []:
                    if isinstance(x,dict) and x.get('type')=='tool_use': tool_names[x.get('id')]=tool_label(x)
                if i not in calls: order.append(i)
                calls[i]=(t,m.get('model') or '',m.get('usage') or {})
        seq=[calls[i] for i in order if since<=calls[i][0]<until]
        if not seq: continue
        out.append(dict(proj=proj,role=classify(proj,texts),calls=seq,events=events,humans=humans,rereview=rereview,
                        first=texts[:1],base=ctx(calls[order[0]][2]),head=calls[order[0]]))
    return out


def cache(S):
    print('== cache: 役割別の書き込み（5分/1時間）と、キャッシュ切れによる再書き込み')
    print('miss = 直前の呼び出しの文脈の半分未満しか読めなかった呼び出し。rewrite$ = 取りこぼした分(直前文脈-読めた量)の書き込み単価換算')
    print(f"{'role':10} {'write$':>7} {'5m%':>4} {'1h%':>4} {'calls':>6} {'miss':>5} {'rewrite$':>8} {'rw/role$':>8} {'gap<5m':>6} {'5m-1h':>6} {'>1h':>5}")
    for role in ROLES:
        w5t=w1t=0; wc=0; calls=miss=0; rew=0.0; tot=0.0; g=[0,0,0]
        for s in (x for x in S if x['role']==role):
            prev=None
            for t,mo,u in s['calls']:
                cp=cost_parts(mo,u); tot+=sum(cp.values()); wc+=cp['write']
                w5,w1=writes(u); pi,po,pr,p5,p1=price(mo); w5t+=w5*p5/1e6; w1t+=w1*p1/1e6; calls+=1
                if prev is not None:
                    pt,pc=prev; r=u.get('cache_read_input_tokens',0)
                    if r<0.5*pc and ctx(u)>=0.5*pc:
                        miss+=1; lost=max(0,pc-r); share=min(1,lost/max(1,w5+w1))
                        rew+=cp['write']*share
                        gap=(t-pt).total_seconds(); g[0 if gap<300 else (1 if gap<3600 else 2)]+=1
                prev=(t,ctx(u))
        if not calls: continue
        wt=w5t+w1t or 1
        print(f"{role:10} {wc:7.0f} {100*w5t/wt:4.0f} {100*w1t/wt:4.0f} {calls:6d} {miss:5d} {rew:8.0f} {100*rew/max(tot,1):7.1f}% {g[0]:6d} {g[1]:6d} {g[2]:5d}")


def fixed(S):
    print('== fixed: セッション最初の呼び出し（期間より前でも）の文脈（システムプロンプト・ツール定義・CLAUDE.md・スキル一覧などの固定部分）')
    print('fixed$ = 最初の文脈 × 期間内の呼び出し回数 を読み価格で読み直す費用の見積もり（compact 後は小さく見積もりすぎ・過大の両方がありうる）')
    print(f"{'role':10} {'sess':>4} {'base中央値':>9} {'p90':>8} {'calls/sess':>10} {'fixed$':>7} {'role$':>7} {'share':>6}")
    for role in ROLES:
        bases=[]; fx=0.0; tot=0.0; n=0
        for s in (x for x in S if x['role']==role):
            c0=s['calls'][0]; b=s['base']; bases.append(b); n+=len(s['calls'])
            pi,po,pr,p5,p1=price(c0[1]); w5,w1=writes(c0[2])
            fx+=b*len(s['calls'])*pr/1e6
            tot+=sum(sum(cost_parts(mo,u).values()) for _,mo,u in s['calls'])
        if not bases: continue
        bases.sort()
        print(f"{role:10} {len(bases):4d} {bases[len(bases)//2]:9,} {bases[int(len(bases)*.9)]:8,} {n/len(bases):10.0f} {fx:7.0f} {tot:7.0f} {100*fx/max(tot,1):5.1f}%")


def startup(S):
    print('== startup: セッション起動（最初の呼び出し）のコスト。最初の呼び出しが期間内のセッションだけ')
    print(f"{'role':10} {'sess':>4} {'読めた中央値':>10} {'書いた中央値':>10} {'書込$計':>7} {'role$':>7} {'割合':>6}")
    for role in ROLES:
        rd=[];wr=[];wc=0.0;tot=0.0
        for s in (x for x in S if x['role']==role):
            t,mo,u=s['head']
            tot+=sum(sum(cost_parts(m,v).values()) for _,m,v in s['calls'])
            if not since<=t<until: continue
            rd.append(u.get('cache_read_input_tokens',0)); wr.append(u.get('cache_creation_input_tokens',0)); wc+=cost_parts(mo,u)['write']
        if rd:
            rd.sort(); wr.sort()
            print(f"{role:10} {len(rd):4d} {rd[len(rd)//2]:10,} {wr[len(wr)//2]:10,} {wc:7.0f} {tot:7.0f} {100*wc/max(tot,1):5.1f}%")


def band(S):
    print('== band: 1コールあたりの文脈の大きさ別の費用（読み+書き+出力。単位 $）')
    edges=[50e3,100e3,200e3,300e3]; names=['<50k','50-100k','100-200k','200-300k','>300k']
    print(f"{'role':10} "+' '.join(f'{n:>9}' for n in names)+'   (割合%)')
    for role in ROLES:
        v=[0.0]*5
        for s in (x for x in S if x['role']==role):
            for t,mo,u in s['calls']:
                k=sum(ctx(u)>=e for e in edges); v[k]+=sum(cost_parts(mo,u).values())
        T=sum(v)
        if T: print(f"{role:10} "+' '.join(f'{x:9.0f}' for x in v)+'   '+' '.join(f'{100*x/T:.0f}' for x in v))


def tools(S):
    print('== tools: 文脈に入った中身が、以降の呼び出しで何回読み直されたか（重み = 推定トークン × 以降の呼び出し回数）')
    print(f'推定トークン = 文字数 / {CHARS_PER_TOKEN}。重みは「読み直されたトークンの延べ数」で、費用の按分ではなく相対比較用')
    for role in ('実装','司令官','レビュー'):
        w=collections.Counter(); raw=collections.Counter(); cnt=collections.Counter(); sk=collections.defaultdict(lambda:[0,0,0])
        for s in (x for x in S if x['role']==role):
            n=len(s['calls'])
            for kind,idx,name,ln in s['events']:
                rem=max(0,n-idx); tk=ln/CHARS_PER_TOKEN
                key=name if kind=='result' else 'スキル本文'
                w[key]+=tk*rem; raw[key]+=tk; cnt[key]+=1
                if kind=='skill': a=sk[name]; a[0]+=1; a[1]+=tk; a[2]+=tk*rem
        T=sum(w.values()) or 1
        print(f'-- {role} （延べ {T/1e9:.2f}G トークン読み）')
        for k,v in w.most_common(8): print(f'   {k:14} 重み{100*v/T:5.1f}%  件数{cnt[k]:6d}  平均{raw[k]/max(cnt[k],1):7.0f}tok')
        for k,a in sorted(sk.items(),key=lambda x:-x[1][2])[:5]:
            print(f'   スキル {k:22} 読込{a[0]:4d}回  平均{a[1]/a[0]:6.0f}tok  重み{100*a[2]/T:4.1f}%')


def review(S):
    print('== review: レビュアーの会話の使い方')
    byproj=collections.defaultdict(list)
    for s in S:
        if s['role']=='レビュー': byproj[s['proj']].append(s)
    ses=[s for v in byproj.values() for s in v]
    if not ses:
        print('この期間にレビュアーのセッションはありません'); return
    rr=collections.Counter(min(s['rereview'],5) for s in ses)
    print('再レビュー依頼を受けた回数の分布（5以上は5に丸め。0 = 初回レビューだけで終わった）:',dict(sorted(rr.items())))
    print(f'レビュアーのセッション {len(ses)} 本 / ワークツリー {len(byproj)} 個（1ワークツリーあたり {len(ses)/max(1,len(byproj)):.1f} 本）')
    ncalls=sorted(len(s['calls']) for s in ses)
    print(f'呼び出し数 中央値{ncalls[len(ncalls)//2]} p90 {ncalls[int(len(ncalls)*.9)]} 最大{ncalls[-1]}')
    models=collections.Counter(); c_by=collections.Counter()
    for s in ses:
        for t,mo,u in s['calls']:
            models[mo]+=1; c_by[mo]+=sum(cost_parts(mo,u).values())
    print('モデル別 呼び出し数と費用:',{k:(models[k],round(c_by[k])) for k in models})
    mult=[v for v in byproj.values() if len(v)>1]
    print(f'複数のレビュアーセッションを持つワークツリー {len(mult)} 個（ラウンドごとに作り直している可能性）')
    firstctx=sorted(ctx(s['calls'][0][2]) for s in ses)
    print(f'先頭文脈 中央値{firstctx[len(firstctx)//2]:,}  最終文脈 中央値{statistics.median(ctx(s["calls"][-1][2]) for s in ses):,.0f}')
    reuse=sum(1 for s in ses if s['rereview']>=1)
    print(f'同じセッションで再レビュー依頼を受けたもの（ラウンドをまたいだ使い回し）{reuse} 本 / {len(ses)} 本')
    gr=[(len(s['calls']),s['rereview']) for s in ses]
    for k in (0,1,2):
        xs=[sum(sum(cost_parts(mo,u).values()) for _,mo,u in s['calls']) for s in ses if min(s['rereview'],2)==k]
        if xs: print(f'  再レビュー{k}{"+" if k==2 else ""}回: {len(xs)}本 1本あたり ${statistics.mean(xs):.1f}')
    print('費用: 全レビュー $%.0f'%sum(sum(cost_parts(mo,u).values()) for s in ses for t,mo,u in s['calls']))


def simcap(S):
    print('== simcap: 文脈が上限 C を超えたら compact して target まで縮める、と仮定したときの読み費用の削減見込み')
    print('compact 1回のコスト = 上限ぶんの読み + target ぶんの書き込み(1時間) + 出力4k。削減 = 縮んだ分の読み直しが消える分。target=80k')
    caps=(150e3,200e3,300e3); target=80e3
    print(f"{'role':10} {'role$':>7} "+' '.join(f'C={int(c/1e3)}k(回/削減$/純%)'.rjust(22) for c in caps))
    for role in ROLES:
        tot=0.0; res={c:[0,0.0] for c in caps}
        for s in (x for x in S if x['role']==role):
            for t,mo,u in s['calls']: tot+=sum(cost_parts(mo,u).values())
            pi,po,pr,p5,p1=price(s['calls'][0][1])
            for c in caps:
                red=0.0
                for t,mo,u in s['calls']:
                    eff=ctx(u)-red
                    if eff>c:
                        res[c][0]+=1; res[c][1]-=(c*pr+target*p1+4e3*po)/1e6; red=ctx(u)-target; eff=target
                    res[c][1]+=red*pr/1e6
        if tot: print(f"{role:10} {tot:7.0f} "+' '.join(f'{res[c][0]:4d}回 {res[c][1]:5.0f}$ {100*res[c][1]/tot:5.1f}%'.rjust(22) for c in caps))


def files():
    print('== files: 毎セッションに載りうる固定部分のサイズ（文字数。トークン換算の目安は文字数/3）')
    root=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../../..'))
    cands=['AGENTS.md','claude/CLAUDE.md','skills/umbrella-orchestrator/SKILL.md','skills/pr-review-loop/SKILL.md']
    cands+=sorted(glob.glob(os.path.join(root,'skills','*','SKILL.md')))
    seen=set()
    for p in cands:
        p=p if os.path.isabs(p) else os.path.join(root,p)
        if p in seen or not os.path.exists(p): continue
        seen.add(p); n=len(open(p,errors='ignore').read())
        print(f'   {os.path.relpath(p,root):45} {n:7,}字 ≒{n/CHARS_PER_TOKEN:7,.0f}tok')
    desc=0
    for p in glob.glob(os.path.join(root,'skills','*','SKILL.md')):
        m=re.search(r'^description:\s*(.*)$',open(p,errors='ignore').read(),re.M)
        desc+=len(m.group(1)) if m else 0
    print(f'   スキル説明文(description)の合計 {desc:,}字 ≒{desc/CHARS_PER_TOKEN:,.0f}tok（一覧として常に載る）')


def ttl(S):
    print('== ttl: キャッシュ書き込みを全部5分TTLにしたら、という仮定（実際はすべて1時間TTLで書かれている）')
    print('削減 = 書き込みの単価差(1h-5m)。増加 = 呼び出し間隔が5分超〜1時間未満だった呼び出しで、直前文脈を読みでなく5分価格で書き直す分')
    print(f"{'role':10} {'削減$':>7} {'増加$':>7} {'純$':>7} {'role$':>7} {'間隔5m超の呼び出し':>16}")
    for role in ROLES:
        sv=ex=tot=0.0; n=0
        for s in (x for x in S if x['role']==role):
            prev=None
            for t,mo,u in s['calls']:
                pi,po,pr,p5,p1=price(mo); w5,w1=writes(u); sv+=w1*(p1-p5)/1e6; tot+=sum(cost_parts(mo,u).values())
                if prev is not None and 300<(t-prev[0]).total_seconds()<3600:
                    ex+=prev[1]*(p5-pr)/1e6; n+=1
                prev=(t,ctx(u))
        if tot: print(f"{role:10} {sv:7.0f} {ex:7.0f} {sv-ex:7.0f} {tot:7.0f} {n:16d}")


def bases():
    print('== bases: プロジェクトの種類別の、セッション最初の呼び出しの文脈（期間を問わない全ログ。固定部分の下限を見る）')
    by=collections.defaultdict(list)
    for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
        proj=f.split('/projects/')[1].split('/')[0]
        for line in open(f,errors='ignore'):
            try: d=json.loads(line)
            except: continue
            if d.get('type')=='assistant' and (d.get('message') or {}).get('usage') and not d.get('isSidechain'):
                u=d['message']['usage']; r,b=branch(proj)
                k='リポ外(ホーム・tmp)' if r=='?' else ('dotfiles' if r=='dotfiles' else '製品リポ')
                by[k].append(ctx(u)); break
    for k,v in by.items():
        v.sort(); print(f'   {k:16} {len(v):4d}本  最小{v[0]:,}  中央値{v[len(v)//2]:,}  p90 {v[int(len(v)*.9)]:,}')


def main():
    what=sys.argv[1] if len(sys.argv)>1 else 'all'
    S=load()
    print(f'期間 {since:%Y-%m-%d %H:%M} 〜 {until:%Y-%m-%d %H:%M} / セッション{len(S)}本')
    if what in('files','all'): files(); print()
    if what in('bases','all'): bases(); print()
    for name,fn in (('cache',cache),('fixed',fixed),('startup',startup),('band',band),('tools',tools),('review',review),('simcap',simcap),('ttl',ttl)):
        if what in(name,'all'): fn(S); print()


main()
