# 実装の孫の PR ごとに、「最初の gh pr create より前に自己 compact したか」と、レビューのラウンド数・
# レビューの投稿数（ラウンド数の代わり）・インラインの指摘数を並べる。実装途中の compact が品質を落としていないかを
# 見る（ADR DOC-2610142337 §4）。使い方: python3 -I quality.py [開始日 YYYY-MM-DD] 。
# 投稿数も指摘数も gh から取る（取れなければ "-"。レビュワーの投稿は COMMENT なので状態では数えない）。
import json,glob,os,re,subprocess,sys
from datetime import datetime,timezone
since=datetime.fromisoformat((sys.argv[1] if len(sys.argv)>1 else '2026-10-13')+'T00:00:00+00:00')
root=os.path.expanduser('~/.claude/projects')
def gh(*a):
    try: return json.loads(subprocess.run(['gh',*a],capture_output=True,text=True,timeout=60,check=True).stdout)
    except Exception: return None
rows=[]
for f in sorted(glob.glob(root+'/*/*.jsonl')):
    if os.path.getmtime(f)<since.timestamp(): continue
    name=re.sub(r'^.*?-projects-','',f.split('/')[-2],count=1)
    if not re.search(r'-\d\d-',name): continue
    pending={};created=False;pr=None;midway=0;total=0;pr_seen=False
    for line in open(f,errors='ignore'):
        try:d=json.loads(line)
        except:continue
        if d.get('subtype')=='compact_boundary' and (d.get('compactMetadata') or {}).get('trigger')=='manual':
            total+=1
            if not pr_seen: midway+=1
        m=d.get('message') or {}
        c=m.get('content') if isinstance(m,dict) else None
        if not isinstance(c,list): continue
        for x in c:
            if x.get('type')=='tool_use':
                s=json.dumps(x.get('input',{}),ensure_ascii=False)
                if 'gh pr create' in s and not pr_seen: pending[x['id']]=1
            if x.get('type')=='tool_result' and x.get('tool_use_id') in pending:
                t=json.dumps(x.get('content'),ensure_ascii=False)
                u=re.search(r'github\.com/([\w.-]+/[\w.-]+)/pull/(\d+)',t)
                if u: pr=(u.group(1),u.group(2)); pr_seen=True
    if pr is None: continue
    rv=gh('pr','view',pr[1],'--repo',pr[0],'--json','reviews')
    ic=gh('api',f'repos/{pr[0]}/pulls/{pr[1]}/comments','--paginate')
    nrev=len(rv.get('reviews',[])) if rv else '-'
    rows.append((name,f'{pr[0]}#{pr[1]}',midway,total,nrev,len(ic) if isinstance(ic,list) else '-'))
print(f"{'session':40} {'PR':28} midway total reviews inline")
for r in rows: print(f"{r[0]:40} {r[1]:28} {r[2]:6} {r[3]:5} {r[4]!s:7} {r[5]!s}")
