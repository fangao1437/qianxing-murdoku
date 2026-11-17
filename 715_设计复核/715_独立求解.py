import json,itertools,copy,hashlib,time
from pathlib import Path
T=Path(__file__).resolve().parent
class Puzzle:
 def __init__(self,d):
  self.d=d;self.n=d['size']['rows'];self.names=[s['id'] for s in d['suspects']];self.vi=self.names.index(d['victim']['id']);n=self.n
  def cell(p):return (p['r']-1)*n+p['c']-1
  self.cell=cell;self.obj={k:set(map(cell,v['cells'])) for k,v in d['objects'].items()}
  self.block=set(map(cell,d.get('blocked',[])))|set(map(cell,d.get('water',[])))
  for k,v in d['objects'].items():
   if not v['occupiable']:self.block|=self.obj[k]
  def edge(e):
   dr=1 if e[0]=='h' else 0;dc=1-dr;a=(e[1]-1)*n+e[2]-1;return tuple(sorted((a,a+dr*n+dc)))
  walls=set(map(edge,d['walls']));self.room={};rid=0
  for a in range(n*n):
   if a in self.room:continue
   self.room[a]=rid;todo=[a]
   while todo:
    b=todo.pop()
    for c in range(n*n):
     if c not in self.room and abs(c//n-b//n)+abs(c%n-b%n)==1 and tuple(sorted((b,c))) not in walls:self.room[c]=rid;todo.append(c)
   rid+=1
  self.adj={r:set() for r in range(rid)}
  for e in d['doors']:
   a,b=edge(e);ra,rb=self.room[a],self.room[b];assert ra!=rb
   self.adj[ra].add(rb);self.adj[rb].add(ra)
  self.stand=set(range(n*n))-self.block
  self.beside={k:{a for a in self.stand if any(self.room[a]==self.room[b] and abs(a//n-b//n)+abs(a%n-b%n)==1 for b in cells)} for k,cells in self.obj.items()}
  self.cards=d['clues'];self.general=d.get('general_clues',[]);self.cache={}
 def ev(self,cl,x):
  t=cl['type'];n=self.n
  def p(k):return x[self.names.index(cl[k])]
  if t in ('on_object','only_on_object','beside_object','not_beside_object'):
   cells=self.beside[cl['object']] if 'beside' in t else self.obj[cl['object']];z=p('who') in cells
   if t=='only_on_object':z=z and sum(v in cells for v in x)==1
   return not z if t=='not_beside_object' else z
  if t=='above':return p('a')//n<p('b')//n and (cl.get('same_column')==False or p('a')%n==p('b')%n)
  if t in ('same_room','not_with','different_room'):return (self.room[p('a')]==self.room[p('b')])==(t=='same_room')
  if t=='in_col':return p('who')%n==cl['c']-1
  if t=='in_row':return p('who')//n==cl['r']-1
  if t=='n_on_object':return sum(v in self.obj[cl['object']] for v in x)==cl['n']
  raise ValueError(cl)
 def solve(self,removed=(),nogeneral=False,negative=None):
  key=(tuple(sorted(removed)),nogeneral,negative)
  if key in self.cache:return self.cache[key]
  cls=[c for i,c in enumerate(self.cards) if i not in removed and i!=negative]+([] if nogeneral else list(self.general));n=self.n
  # Negative card stays as an enforced false predicate, never ignored.
  negative_card=self.cards[negative] if negative is not None else None
  dom=[set(self.stand) for _ in self.names];binary=[];globals=[]
  for c in cls:
   t=c['type']
   if t in ('on_object','only_on_object','beside_object','not_beside_object','in_col','in_row'):
    i=self.names.index(c['who']);s=self.stand
    if t in ('on_object','only_on_object'):s=self.obj[c['object']]
    elif t=='beside_object':s=self.beside[c['object']]
    elif t=='not_beside_object':s=self.stand-self.beside[c['object']]
    elif t=='in_col':s={v for v in self.stand if v%n==c['c']-1}
    elif t=='in_row':s={v for v in self.stand if v//n==c['r']-1}
    dom[i]&=s
    if t=='only_on_object':
     for j in range(n):
      if j!=i:dom[j]-=self.obj[c['object']]
   elif t=='n_on_object':globals.append(c)
   else:binary.append((self.names.index(c['a']),self.names.index(c['b']),c))
  order=sorted(range(n),key=lambda i:len(dom[i]));x=[-1]*n;out=[]
  def rec(k,rs,cs):
   if k==n:
    if all(self.ev(c,x) for c in globals) and (negative_card is None or not self.ev(negative_card,x)):out.append(tuple(x))
    return
   i=order[k]
   for a in sorted(dom[i]):
    r,c=divmod(a,n)
    if rs>>r&1 or cs>>c&1:continue
    x[i]=a
    if all(x[j]<0 or x[h]<0 or self.ev(cl,x) for j,h,cl in binary):rec(k+1,rs|1<<r,cs|1<<c)
    x[i]=-1
  rec(0,0,0);self.cache[key]=out;return out
 def people(self,x,h):
  vr=self.room[x[self.vi]];tr=self.room[x[h]]
  if tr not in self.adj[vr]:return False
  counts={r:sum(self.room[a]==r for i,a in enumerate(x) if i!=h) for r in self.adj[vr]}
  return all(counts[tr]>v for r,v in counts.items() if r!=tr)
 def audit(self,removed=(),nogeneral=False,relaxed=False):
  s0=self.solve(removed,nogeneral);announce=self.d.get('meta',{}).get('announce','unknown');final=set();branches=[]
  for h,name in enumerate(self.names):
   if h==self.vi:continue
   p0=sorted({x[h] for x in s0});truth_raw=[x for x in s0 if self.people(x,h)]
   truth_final=truth_raw if announce!='one' and len(p0)>1 and len({x[h] for x in truth_raw})==1 else []
   # All card predicates are retained. This identity hypothesis enforces exactly its owner's card FALSE.
   sf=self.solve(removed,nogeneral,negative=h) if h not in removed else []
   pf=sorted({x[h] for x in sf});lie_raw=[x for x in sf if self.people(x,h)]
   lie_final=lie_raw if announce!='none' and len(pf)==1 else []
   for x in truth_final+lie_final:final.add((name,x))
   branches.append({'person':name,'truth':{'before_boards':len(s0),'before_positions':p0,'people_boards':len(truth_raw),'after_positions':sorted({x[h] for x in truth_raw}),'final':len(truth_final)},'lie':{'before_boards':len(sf),'before_positions':pf,'people_boards':len(lie_raw),'after_positions':sorted({x[h] for x in lie_raw}),'final':len(lie_final)},'final':len(truth_final)+len(lie_final)})
  return {'alltrue':len(s0),'alltrue_boards':s0,'branches':branches,'solutions':[{'thief':h,'positions':dict(zip(self.names,x))} for h,x in sorted(final)],'count':len(final)}
 def hints(self):
  res=[]
  for c in self.cards:
   t=c['type'];s=set();rule='不做位置提示'
   if t in ('on_object','only_on_object'):s=self.obj[c['object']]&self.stand;rule='该家具自己的格子'
   elif t in ('beside_object','not_beside_object'):s=self.beside[c['object']];rule='该家具四邻、同区域、可站人的格'
   elif t=='in_col':s={v for v in self.stand if v%self.n==c['c']-1};rule=f"第 {c['c']} 列的可站格"
   res.append({'rule':rule,'cells':[f'{v//self.n+1}:{v%self.n+1}' for v in sorted(s)],'count':len(s)})
  return res

def revised(d):
 d=copy.deepcopy(d);lv=int(d['id'][-3:])
 if lv==4:d['clues'][0]={'type':'same_room','a':'A','b':'V'};d['clues'][1]={'type':'beside_object','who':'B','object':'桌子'}
 if lv==5:
  old={'r':5,'c':2};assert old in d['objects']['书架']['cells'];d['objects']['书架']['cells'][d['objects']['书架']['cells'].index(old)]={'r':4,'c':1}
 if lv==7:d['clues'][0]={'type':'beside_object','who':'A','object':'植物'};d['clues'][5]={'type':'in_col','who':'B','c':5}
 return d

def main():
 import sys
 source=Path(sys.argv[1]) if len(sys.argv)>1 else T/'715_关卡设计.json'
 data=json.loads(source.read_text(encoding='utf8'))
 for d in data[2:]:
  p=Puzzle(d);r=p.audit();print(json.dumps({'level':d['id'],'count':r['count'],'solutions':r['solutions'],'branches':r['branches']},ensure_ascii=False))
if __name__=='__main__':main()
