// 715 原档独立重建。保留模板、玩法与固定区域；可动UI平移，背景/火漆分离。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg,cloneField,asIdList,ensureChildListTop,setChildList,textsOf,pairOf,pairValue,setPair} from '../tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf} from '../tools/gil/gilwrite.mjs';
const DIR=path.dirname(fileURLToPath(import.meta.url));
const INPUT=path.resolve(DIR,'../715_设计复核/715_全线索规则复核修订.gil');
const OUT=path.join(DIR,'715_UI自适应修订版_v12.gil'),LUA=path.join(DIR,'715_UI自适应修订版_v12.lua'),AUDIT=path.join(DIR,'715_UI自适应修订审计_v12.json');
const DRY=process.argv.includes('--dry');
const g=readGil(INPUT),original=readGil(INPUT),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
assert.equal(hash(original.src),'0eb5a67f4ed8710f9f4a00026e2011d579cd455c0f21efd9624442c98ce79c5e');
const raw=findScriptLeaf(g).buf.toString('utf8').replace(/\r\n/g,'\n');
const ns=(f,ks)=>ks.reduce((a,k)=>a.flatMap(x=>(x.sub||[]).filter(y=>y.field===k)),[f]);
const by=new Map(g.recs.map(r=>[r.id,r]));
const R=n=>{const rows=g.recs.filter(r=>r.name===n);assert.equal(rows.length,1,n);return rows[0];};
const kids=r=>r.childList?(asIdList(r.childList.payload,true)||[]):[];
function setKids(r,ids){r.childList=ensureChildListTop(r);r.childList.sub=null;setChildList(r.childList,ids);}
const plats=r=>ns(r.field,[505,503,13,12,501]).map(p=>({pt:Number(p.sub.find(f=>f.field===501&&f.wt===0)?.num??0),s:p.sub.find(f=>f.field===502)}));
const pair=(s,n)=>[pairValue(pairOf(s,n),0),pairValue(pairOf(s,n),1)];
function setP(s,n,x,y){let f=pairOf(s,n);if(!f){f={field:n,wt:2,sub:[],payload:null};s.sub.push(f);}setPair(f,x,y);}
function vec(s,n,xyz){let f=pairOf(s,n);if(!f){f={field:n,wt:2,sub:[],payload:null};s.sub.push(f);}f.sub=xyz.map((v,i)=>({field:i+1,wt:5,f:v}));}
const A={LM:[0,.5],RM:[1,.5],TL:[0,1],TR:[1,1],BR:[1,0],WAX:[.5,.5]};
const oldBytes=new Map(original.recs.map(r=>[r.id,encodeMsg([r.field])]));
const protectedIds=new Set();
const protectionRoots=['stage','modal','td.home','td.l1','td.l2','help617','hint635.menu','hint635.result','home.select','home.continue','home.shop','home.bag','art657.grid.reuse','block640.modal','block640.confirm','block640.home','block640.l1','block640.l2'];
function descendants(id,set){if(set.has(id))return;set.add(id);for(const cid of kids(by.get(id)))descendants(cid,set);}
for(const n of protectionRoots)descendants(R(n).id,protectedIds);
for(const r of g.recs)if(/^(art641\.game\.board|art657\.game\.board|art656\.home\.button\.|hex\.(ok|no)$|hit\.(ok|no)$)/.test(r.name||''))protectedIds.add(r.id);
const runtimeWithoutPaths=raw.replace(/local STATIC_PATH_655 = \{[\s\S]*?\n}\s*\n(?=local function path_lookup_655)/,'');
const clientIds=new Set();descendants(R('root').id,clientIds);
const hidden=r=>ns(r.field,[505,503,14,17]).some(f=>f.sub?.some(x=>x.field===503&&x.wt===0));
const removed=g.recs.filter(r=>clientIds.has(r.id)&&!protectedIds.has(r.id)&&/^art\d+\./.test(r.name||'')&&hidden(r)&&kids(r).length===0&&!runtimeWithoutPaths.includes(r.name));
const deleted=new Set(removed.map(r=>r.id));
const changedParents=new Set(),reparented=new Set(),touched=new Set(),backUnified=new Set(),geometryChanged=new Set();
// v10：恢复647/658历史返回旗完整配方（撤销658只对back施加的0.78）。
// 以现有旗面中心保持定位，七层同步恢复尺寸与相对间距；图标/热区仍同中心。
const backPairs=[['select.back','hex.back'],['hit.select.back','hit.back']];
const gameBack=R('art641.game.flag.back');
const originalBackCenters=new Map(plats(gameBack).map(({pt,s})=>[pt,pair(s,504)]));
for(const r of g.recs.filter(r=>r.name==='art641.game.flag.back'||r.name?.startsWith('art657.game.flag.back.'))){
 for(const {pt,s} of plats(r)){
  const c=originalBackCenters.get(pt),p=pair(s,504),z=pair(s,505);
  setP(s,504,c[0]+(p[0]-c[0])/.78,c[1]+(p[1]-c[1])/.78);
  setP(s,505,z[0]/.78,z[1]/.78);
 }
 backUnified.add(r.id);
}
for(const r of g.recs.filter(r=>/^art647\.select\.back\./.test(r.name||''))){
 const suffix=r.name.slice('art647.select.back.'.length);
 const source=g.recs.find(x=>x.name==='art657.game.flag.back.'+suffix)||g.recs.find(x=>x.name===(suffix==='ribbon'?'art641.game.flag.back':'art641.game.flag.back.'+suffix));
 assert(source,'返回键缺少同名图元 '+suffix);backPairs.push([r.name,source.name]);
}
for(const [dst,src] of backPairs){const r=R(dst),o=R(src);for(const {pt,s} of plats(r)){const ref=plats(o).find(x=>x.pt===pt).s; s.sub=cloneField(ref).sub;}backUnified.add(r.id);}
for(const r of g.recs){const ids=kids(r);if(ids.some(id=>deleted.has(id))){setKids(r,ids.filter(id=>!deleted.has(id)));changedParents.add(r.id);}}
for(const r of removed){const i=g.recHolder.indexOf(r.field);assert(i>=0);g.recHolder.splice(i,1);by.delete(r.id);}
g.recs=g.recs.filter(r=>!deleted.has(r.id));
assert.equal(g.recs.filter(r=>/^art675\.wax\./.test(r.name||'')).length,240);
assert.equal(g.recs.filter(r=>/^(art663|art664)\.wax\./.test(r.name||'')).length,0);
const groups=[],targets=[];let max=Number(g.maxId);
function addTarget(r,key){assert(!protectedIds.has(r.id),'保护目标 '+r.name);const states=plats(r).map(({pt,s})=>{const pos=pair(s,504);assert(pos.every(Number.isFinite));const [ax,ay]=A[key];const mobile=pt===1||pt===3;const editor=[pos[0],pos[1]+(mobile?0:(ay-.5)*180)];setP(s,504,...editor);return{pt,base:pos,editor};});assert.deepEqual(states.map(x=>x.pt).sort(),[0,1,2,3]);targets.push({id:r.id,name:r.name,key,ax:A[key][0],ay:A[key][1],states});touched.add(r.id);}
function addGroup(parent,ids,key){assert(ids.length);for(const id of ids)assert(!protectedIds.has(id));const proto=R('art641.game'),field=cloneField(proto.field),id=++max,name='adapt715r.'+key+'.'+(groups.length+1);
 function remap(fs,d=0){for(const f of fs||[]){if(!(d===0&&f.field===504)&&f.wt===0&&Number(f.num)===proto.id)f.num=BigInt(id);if(f.sub)remap(f.sub,d+1);}}remap(field.sub);
 const nf=textsOf(field.sub,[]).find(f=>f.payload.toString('utf8')===proto.name);nf.payload=Buffer.from(name);nf.len=nf.payload.length;
 field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(parent.id);
 for(const f of ns(field,[505,503,14,17])){f.sub=[];f.payload=Buffer.alloc(0);f.len=0;f.isText=false;}
 const r={id,name,parentId:parent.id,field};setKids(r,ids);
 for(const {pt,s} of plats(r)){setP(s,505,...pair(plats(parent).find(x=>x.pt===pt).s,505));setP(s,504,0,0);vec(s,501,[1,1,1]);vec(s,508,[0,0,0]);}
 const all=kids(parent),at=all.indexOf(ids[0]);assert.deepEqual(all.slice(at,at+ids.length),ids);setKids(parent,[...all.slice(0,at),id,...all.slice(at+ids.length)]);changedParents.add(parent.id);
 for(const cid of ids){const c=by.get(cid);c.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(id);c.parentId=id;reparented.add(cid);}
 const insert=g.recHolder.indexOf(by.get(ids[0]).field);assert(insert>=0);g.recHolder.splice(insert,0,field);g.recs.push(r);by.set(id,r);groups.push({id,name,parent:parent.name,key,children:ids,childNames:ids.map(i=>by.get(i).name)});addTarget(r,key);
}
function classify(r,parent){const n=r.name||'';if(protectedIds.has(r.id))return null;
 if(parent==='grp653.static.1.art641.game'){
  if(/^art675\.wax\./.test(n))return'WAX';
  const flag=n.match(/^art(?:641|657)\.game\.flag\.(back|submit|redo|undo|hint)(?:\.|$)/);if(flag)return flag[1]==='back'?'TL':flag[1]==='hint'?'BR':'TR';
  if(/(notebook|clues|binding|\.tab\.|help\.tab|\.ring|\.tape|ribbon|sticker)/.test(n))return'LM';
  return null;
 }
 if(parent==='grp653.static.1.art641.home'){
  if(/^art(?:641|656)\.home\.camera\./.test(n))return'LM';
  if(/^art656\.home\.(note|wave)\./.test(n))return'RM';
 }
 if(/^art647\.(home|select)\.settle\./.test(n))return'BR';
 if(/^art647\.select\.back\./.test(n))return'TL';
 if(n==='art647.select.diamond.left')return'LM';if(n==='art647.select.diamond.right')return'RM';
 if(parent==='home'&&/^home\.tutorial627\./.test(n))return'LM';return null;
}
for(const pn of ['grp653.static.1.art641.game','grp653.static.1.art641.home','art641.home','art642.select.buttons','grp653.static.1.art642.select.buttons','home']){const p=R(pn);let run=[],key=null;const flush=()=>{if(run.length)addGroup(p,run,key);run=[];};for(const id of [...kids(p)]){const k=classify(by.get(id),pn);if(k!==key){flush();key=k;}if(k)run.push(id);}flush();}
const direct={clues:'LM',topbar:'LM','clues.help617':'LM','clues.help627.hit':'LM','settle.btn':'BR','settle.btn.countdown':'BR','select.back':'TL','hit.select.back':'TL','hit.select.prev':'LM','hit.select.next':'RM'};
for(const s of ['hex','hit'])for(const n of ['back','submit','redo','undo','hint'])direct[s+'.'+n]=n==='back'?'TL':n==='hint'?'BR':'TR';
for(const[n,k]of Object.entries(direct))addTarget(R(n),k);
// v8：附加运行时目标不修改存档，保护记录保持逐字节相同。
for(const [name,ax,ay] of [['select.title',.5,1],['select.page',.5,0],['hex.ok',0,1],['hex.no',0,1],['hit.ok',0,1],['hit.no',0,1]]){
 const r=R(name);targets.push({id:r.id,name,key:'EDGE',ax,ay,states:plats(r).map(({pt,s})=>{const p=pair(s,504);return{pt,base:[p[0],p[1]-(ay-.5)*180],editor:p};})});
}
const wax=groups.filter(x=>x.key==='WAX');assert.equal(wax.length,1);assert.equal(wax[0].children.length,240);
// v5：撕边保持原图元，新增两个独立定位父级；不沿用整屏cover。
const tearGroups=[];
for(const side of ['tr','bl']){
 const rows=g.recs.filter(r=>(r.name||'').startsWith('art651.select.tear.'+side+'.'));
 for(const pid of new Set(rows.map(r=>r.parentId))){
  const parent=by.get(pid),wanted=new Set(rows.filter(r=>r.parentId===pid).map(r=>r.id));
  let run=[];const flush=()=>{if(!run.length)return;addGroup(parent,run,side==='tr'?'TR':'BR');const gr=groups.at(-1);targets.pop();gr.key='TEAR_'+side;tearGroups.push({name:gr.name,side});for(const {s}of plats(by.get(gr.id)))setP(s,504,0,0);run=[];};
  for(const id of [...kids(parent)]){if(wanted.has(id))run.push(id);else flush();}flush();
 }
}
// v10：将撕边父组从board子树重挂到选关美术最后。
// 原父组为零位移/单位缩放，先逐端断言，避免重挂引入新偏移。
const tearLeafIds=new Set();
for(const t of tearGroups){
 const r=R(t.name),old=by.get(r.parentId),dest=R('art641.select');
 for(let a=old;a&&a.id!==dest.id;a=by.get(a.parentId)){
  for(const {s}of plats(a)){
   assert(pair(s,504).every(v=>Math.abs(v)<.01),'撕边原祖先非零位移 '+a.name);
   assert(pair(s,502).every(v=>Math.abs(v-.5)<.01)&&pair(s,503).every(v=>Math.abs(v-.5)<.01),'撕边原祖先非中心锚点 '+a.name);
   assert(pairOf(s,501).sub.every(v=>Math.abs(v.f-1)<.01),'撕边原祖先非单位缩放 '+a.name);
  }
 }
 setKids(old,kids(old).filter(id=>id!==r.id));changedParents.add(old.id);
 setKids(dest,[...kids(dest),r.id]);changedParents.add(dest.id);
 r.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(dest.id);r.parentId=dest.id;
 for(const id of kids(r))tearLeafIds.add(id);
 const group=groups.find(x=>x.id===r.id);group.parent=dest.name;
}
// v3：把整张素材组转换为客户端图元层；拍立得仍为完整背景的一部分。
const bg=by.get(1073742783);assert(bg);
const bgStates=plats(bg).map(({pt,s})=>({pt,pos:pair(s,504),size:pair(s,505),min:pair(s,502),max:pair(s,503)}));
const backdrop=R('art642.select.backdrop');
const bgSource=R('police-v19'), bgSourceRows=kids(bgSource).map(id=>by.get(id));
assert.equal(bgSourceRows.length,649);
const converted=[], extraIds=new Set();
const imageProto=R('art675.wax.fit000');
const textProto=g.recs.find(r=>clientIds.has(r.id)&&ns(r.field,[505,503,75]).length&&kids(r).length===0);
assert(textProto,'缺客户端文字原型');
function putNum(f,k,v){let q=f.sub.find(x=>x.field===k&&x.wt===0);if(!q)f.sub.push(q={field:k,wt:0});q.num=BigInt(v);}
function newClient(proto,name,parent){
 const field=cloneField(proto.field),id=++max;
 function remap(fs,d=0){for(const f of fs||[]){if(!(d===0&&f.field===504)&&f.wt===0&&Number(f.num)===proto.id)f.num=BigInt(id);if(f.sub)remap(f.sub,d+1);}}remap(field.sub);
 const nf=textsOf(field.sub,[]).find(f=>f.payload.toString('utf8')===proto.name);assert(nf);nf.payload=Buffer.from(name);nf.len=nf.payload.length;
 field.sub=field.sub.filter(f=>!(f.field===504&&f.wt===0));field.sub.push({field:504,wt:0,num:BigInt(parent.id)});
 const r={id,name,parentId:parent.id,field};setKids(r,[]);
 for(const f of ns(field,[505,503,14,17])){f.sub=[];f.payload=Buffer.alloc(0);f.len=0;f.isText=false;}
 // 克隆美术原型时移除可能的脚本组件；所选原型必须无脚本。
 assert(!textsOf(field.sub,[]).some(f=>/\.lua$/.test(f.payload.toString('utf8'))),'美术原型含脚本');
 g.recHolder.push(field);g.recs.push(r);by.set(id,r);extraIds.add(id);return r;
}
function centerRect(r,w,h){for(const {s}of plats(r)){setP(s,502,.5,.5);setP(s,503,.5,.5);setP(s,504,0,0);setP(s,505,w,h);setP(s,506,.5,.5);vec(s,501,[1,1,1]);vec(s,508,[0,0,0]);}}
const clientRoot=R('root');
const coverRoot=newClient(R('art641.game'),'adapt715r.background',clientRoot);centerRect(coverRoot,1600,900);
const baseSource=bgSourceRows.find(r=>r.name==='1');assert(baseSource);
const baseImage=ns(baseSource.field,[505,503,31])[0];const baseColor=Number(baseImage.sub.find(f=>f.field===4).num);
const guard=newClient(imageProto,'adapt715r.background.fill',clientRoot);centerRect(guard,0,0);
for(const {s}of plats(guard)){setP(s,502,0,0);setP(s,503,1,1);}
const gi=ns(guard.field,[505,503,84])[0];putNum(gi,502,baseColor);putNum(gi,503,100001);putNum(gi,504,1);
// 服务器素材清单前景在前（末项1为不透明底色）；客户端先底后前，必须反序。
for(const src of [...bgSourceRows].reverse()){
 assert.equal(kids(src).length,0,'背景有嵌套图元');
 const im=ns(src.field,[505,503,31])[0],tx=ns(src.field,[505,503,19])[0];assert(Boolean(im)!==Boolean(tx),'未知背景图元');
 const r=newClient(im?imageProto:textProto,'adapt715r.background.part.'+src.name,coverRoot);
 for(const {pt,s}of plats(r)){const from=plats(src).find(x=>x.pt===pt);assert(from);s.sub=cloneField(from.s).sub;}
 if(im){
  const image=Number(im.sub.find(f=>f.field===2)?.num);assert([100001,100002,100003,106060].includes(image));
  assert(!(im.sub.find(f=>f.field===6)?.sub?.length),'不支持嵌套素材');
  const dest=ns(r.field,[505,503,84])[0];putNum(dest,503,image);putNum(dest,502,Number(im.sub.find(f=>f.field===4)?.num??4294967295n));putNum(dest,504,1);
 }else{
  const dest=ns(r.field,[505,503,75])[0];assert(dest);
  const get=(k,d)=>Number(tx.sub.find(f=>f.field===k&&f.wt===0)?.num??d);
  const txt=ns(tx,[505,501])[0];assert(txt?.isText);
  const dt=ns(dest,[510,501])[0];assert(dt);dt.payload=Buffer.from(txt.payload);dt.len=dt.payload.length;dt.sub=null;dt.isText=true;
  putNum(dest,512,get(502,48));putNum(dest,513,get(507,24));putNum(dest,502,0);
  putNum(dest,504,get(510,4294967295));putNum(dest,505,get(511,16777215));
  putNum(dest,506,1);putNum(dest,507,get(515,858993459));
  putNum(dest,508,get(508,1));putNum(dest,509,get(509,1));
 }
 converted.push({sourceId:src.id,id:r.id,name:r.name,kind:im?'image':'text'});
}
setKids(coverRoot,converted.map(x=>x.id));
setKids(clientRoot,[guard.id,coverRoot.id,...kids(clientRoot)]);changedParents.add(clientRoot.id);
// 将新增记录也放在原客户端内容之前，使记录顺序和子列表一致。
const extraFields=g.recHolder.filter(f=>extraIds.has(Number(f.sub?.find(x=>x.field===501&&x.wt===0)?.num)));
for(const f of extraFields)g.recHolder.splice(g.recHolder.indexOf(f),1);
const insertion=g.recHolder.indexOf(clientRoot.field)+1;
const newOrder=[guard,coverRoot,...converted.map(x=>by.get(x.id))].map(r=>r.field);
g.recHolder.splice(insertion,0,...newOrder);
// v12：恢复v3的服务器背景停绘，避免客户端边缘露出第二套拉伸装饰。
for(const {s}of plats(bg))vec(s,501,[0,0,0]);
// 选关底色移到root底层，以原生拉伸覆盖实际宿主；不再按API数值缩小。
const selectBase=R('art647.select.bg.base'),selectBaseOldParent=by.get(selectBase.parentId);
setKids(selectBaseOldParent,kids(selectBaseOldParent).filter(id=>id!==selectBase.id));changedParents.add(selectBaseOldParent.id);
selectBase.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(clientRoot.id);selectBase.parentId=clientRoot.id;reparented.add(selectBase.id);
setKids(clientRoot,[guard.id,coverRoot.id,selectBase.id,...kids(clientRoot).filter(id=>![guard.id,coverRoot.id,selectBase.id].includes(id))]);
for(const {s}of plats(selectBase)){setP(s,502,0,0);setP(s,503,1,1);setP(s,504,0,0);setP(s,505,4,4);setP(s,506,.5,.5);vec(s,501,[1,1,1]);}
geometryChanged.add(selectBase.id);
g.recHolder.splice(g.recHolder.indexOf(selectBase.field),1);g.recHolder.splice(g.recHolder.indexOf(converted.at(-1) && by.get(converted.at(-1).id).field)+1,0,selectBase.field);
const paths=new Map();function walk(r,p=[]){const q=[...p,r.name];paths.set(r.id,q.join('/'));for(const id of kids(r))walk(by.get(id),q);}walk(R('root'));
const start=raw.indexOf('local STATIC_PATH_655 = {'),end=raw.indexOf('\nlocal function path_lookup_655',start);assert(start>0&&end>start);
const oldTable=raw.slice(start,end),routes=new Map();for(const m of oldTable.matchAll(/  \["([^"\n]+)"\] = "([^"\n]+)",/g))routes.set(m[1],m[2]);
for(const r of removed)routes.delete(r.name);
for(const r of g.recs)if(paths.has(r.id)&&(routes.has(r.name)||targets.some(t=>t.id===r.id)||reparented.has(r.id)||extraIds.has(r.id)))routes.set(r.name,paths.get(r.id));
for(const n of ['art642.select.backdrop','art642.select.board','art642.select.paper','art642.select.thread','art642.select.frames','art642.select.lighting','art647.select.bg.base',...tearGroups.map(x=>x.name)])routes.set(n,paths.get(R(n).id));
const table='local STATIC_PATH_655 = {\n'+[...routes].map(([k,v])=>'  ['+JSON.stringify(k)+'] = '+JSON.stringify(v)+',').join('\n')+'\n}\n';
let script=raw.slice(0,start)+table+raw.slice(end);
const homeGroups=groups.filter(x=>x.parent==='home');script=script.replace('local DECOR = {','local DECOR = {\n'+[...homeGroups.map(x=>x.name),'adapt715r.background','adapt715r.background.fill','art647.select.bg.base'].map(n=>'  ['+JSON.stringify(n)+'] = true,').join('\n'));
const luaRows=targets.map(t=>'  {name='+JSON.stringify(t.name)+',kind='+JSON.stringify(t.key)+',ax='+t.ax+',ay='+t.ay+',base={'+t.states.map(s=>'['+s.pt+']={'+s.base.join(',')+'}').join(',')+'}},').join('\n');
const selectColor=Number(ns(R('art647.select.bg.base').field,[505,503,84])[0].sub.find(f=>f.field===502).num);
const config='local ADAPT715R_HOME_COLOR = '+baseColor+'\nlocal ADAPT715R_SELECT_COLOR = '+selectColor+'\nlocal ADAPT715R_TEARS = {'+tearGroups.map(t=>'{name='+JSON.stringify(t.name)+',side='+JSON.stringify(t.side)+'}').join(',')+'}\nlocal ADAPT715R_TARGETS = {\n'+luaRows+'\n}\n';
const runtime=fs.readFileSync(path.join(DIR,'适配运行时.lua'),'utf8').replace('-- TARGET_TABLE',config);
assert(runtime.includes('local function sync_adapt715r'));
script=script.replace('local art641_cache = nil',runtime+'\nlocal art641_cache = nil');
script=script.replace('  sync_block640()\nend','  sync_block640()\n  sync_adapt715r(dt, false)\nend');
script=script.replace('  pcall(check_canvas)','  pcall(check_canvas)\n  sync_adapt715r(0, true)');
script=script.replace('构建标记 v715 / 2026-11-17 / 全线索保留复核与第四五七关修订','构建标记 v715 / 2026-11-18 / v12恢复v3设计坐标与原生底色拉伸修复');
const selectPatches=[["visible = true,\n                 rect = r, image = CARD_MAT", "visible = true, pos_runtime = true,\n                 rect = r, image = CARD_MAT"], ["rect = r, event = { action = \"pick_level\", id = it.id }", "rect = r, pos_runtime = true, event = { action = \"pick_level\", id = it.id }"], ["visible = t.result ~= \"\", text = t.result,\n                 rect = { x = r.x, y = r.y + r.h + 10, w = math.max(r.w, 220), h = 72 }", "visible = t.result ~= \"\", text = t.result, pos_runtime = true,\n                 rect = { x = r.x, y = r.y + r.h + 10 * (ui_adapter and ui_adapter._select715_scale or 1), w = math.max(r.w, 220 * (ui_adapter and ui_adapter._select715_scale or 1)), h = 72 * (ui_adapter and ui_adapter._select715_scale or 1) }"], ["ui_adapter and ui_adapter.cfg and ui_adapter.cfg.scale)", "ui_adapter and ui_adapter.cfg and ui_adapter.cfg.scale, ui_adapter and ui_adapter._select715_scale)"], ["function Controller:push_room_thumb(push, cardId, it, cardRect, parent, canvas_scale)", "function Controller:push_room_thumb(push, cardId, it, cardRect, parent, canvas_scale, card_scale)"], ["  local gap_px = 2\n", "  local unit = tonumber(card_scale) or 1\n  if unit <= 0 or unit ~= unit or unit == math.huge then unit = 1 end\n  local gap_px = 2 * unit\n"], ["math.max(4, math.floor(cardRect.w * sc * 0.022 + 0.5))", "math.max(4 * unit, math.floor(cardRect.w * sc * 0.022 + 0.5))"], ["local wall_width, door_width = 5 / sc, 5 / sc", "local wall_width, door_width = 5 * unit / sc, 5 * unit / sc"], ["math.max(8, math.floor(cell_px * 0.44 + 0.5))", "math.max(8 * unit, math.floor(cell_px * 0.44 + 0.5))"], ["  return id == \"select.thumb.pool\"\n", "  return id == \"select.thumb.pool\"\n    or id:match(\"^select%.card%.%d+$\") ~= nil\n    or id:match(\"^hit%.select%.card%.%d+$\") ~= nil\n"]];
for(const [a,b] of selectPatches){assert.equal(script.split(a).length-1,1,"选关补丁定位 "+a.slice(0,60));script=script.replace(a,b);}
const visibilityPatch=[[`  for i = 1, #nodes do
    local id = nodes[i].id
    local hide = HIDE[id] == true
    if not hide then
      for k = 1, #PREFIX do
        if id:sub(1, #PREFIX[k]) == PREFIX[k] then hide = true break end
      end
    end
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    if hide then nodes[i].visible = false end
  end`, `  for i = 1, #nodes do
    local id = nodes[i].id
    local hide = HIDE[id] == true
    if not hide then
      for k = 1, #PREFIX do
        if id:sub(1, #PREFIX[k]) == PREFIX[k] then hide = true break end
      end
    end
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    -- v6：显隐必须双向收口；旧版只写 false，返回当前页时不会恢复。
    local declared = nodes[i]._declared_visible
    if declared == nil then declared = nodes[i].visible ~= false end
    nodes[i]._declared_visible = declared
    nodes[i].visible = (not hide) and declared or false
  end`]];
for(const [a,b] of visibilityPatch){assert.equal(script.split(a).length-1,1,"页面显隐补丁定位");script=script.replace(a,b);}

const leaf=findScriptLeaf(g);leaf.field.payload=Buffer.from(script);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
// 硬保护：固定区域整树和祖先变换，原玩法模块、背景素材母本。
for(const id of protectedIds)assert(oldBytes.get(id).equals(encodeMsg([by.get(id).field])),'保护记录变化 '+by.get(id).name);
for(const n of ['root','home','art641.game','art641.home','art641.select','grp653.static.1.art641.game','grp653.static.1.art641.home']){const r=R(n),o=original.recs.find(x=>x.id===r.id);assert.deepEqual(plats(r).map(x=>encodeMsg([x.s]).toString('hex')),plats(o).map(x=>encodeMsg([x.s]).toString('hex')),'祖先变换变化 '+n);}
const sourceModules=raw.slice(0,raw.indexOf('local adapter   = nil'));const newModules=script.slice(0,script.indexOf('local adapter   = nil'));
const stripModule=s=>visibilityPatch.reduce((v,[a,b])=>v.replace(b,a),selectPatches.reduce((v,[a,b])=>v.replace(b,a),s).replace(/构建标记 v715[^\n]*/g,'构建标记 v715').replace(/local STATIC_PATH_655 = \{[\s\S]*?\n}\s*\n(?=local function path_lookup_655)/,'')).replace(/local DECOR = \{[\s\S]*?(?=  \["home.tutorial627.bg"\])/,'local DECOR = {\n');
{const a=stripModule(newModules),b=stripModule(sourceModules);if(a!==b){let i=0;while(i<Math.min(a.length,b.length)&&a[i]===b[i])i++;console.log('MODULE_DIFF',i,JSON.stringify(a.slice(i-100,i+180)),JSON.stringify(b.slice(i-100,i+180)));}assert(a===b,'玩法模块差异');}
assert.equal((script.match(/sync_adapt715r\(dt, false\)/g)||[]).length,1,'更新入口必须存在且唯一');
function strip(r){const f=cloneField(r.field);if(reparented.has(r.id))f.sub=f.sub.filter(x=>!(x.field===504&&x.wt===0));if(changedParents.has(r.id))f.sub=f.sub.filter(x=>x.field!==503);if(backUnified.has(r.id)||geometryChanged.has(r.id))for(const p of ns(f,[505,503,13,12,501,502]))p.sub=[];else if(touched.has(r.id))for(const p of ns(f,[505,503,13,12,501,502]))p.sub=p.sub.filter(x=>x.field!==504);if(r.id===bg.id)for(const p of ns(f,[505,503,13,12,501,502]))p.sub=p.sub.filter(x=>![501,502,503,504,505].includes(x.field));return encodeMsg([f]);}
for(const r of original.recs)if(!deleted.has(r.id))assert(strip(r).equals(strip(by.get(r.id))),'超范围变化 '+r.name);
const groupIds=new Set(groups.map(x=>x.id));function flattened(gx){const m=new Map(gx.recs.map(x=>[x.id,x])),out=[];function visit(id){if(deleted.has(id))return;const r=m.get(id);if(!groupIds.has(id)&&!extraIds.has(id)&&!tearLeafIds.has(id)&&id!==selectBase.id)out.push(id);for(const c of kids(r))visit(c);}visit(R('root').id);return out;}
assert.deepEqual(flattened(g),flattened(original));
const boundaryProfiles=[
  ['PC 16:9',16/9],['PC 21:9',21/9],['触屏 16:9',16/9],['触屏 19.5:9',19.5/9],['触屏 4:3',4/3],
  ['主机手柄 16:9',16/9],['主机手柄 21:9',21/9],['移动手柄 16:9',16/9],['移动手柄 19.5:9',19.5/9],['移动手柄 4:3',4/3],
  ['额外 16:10',16/10],['额外 20:9',20/9]
];
const boundaryCases=[];
for(const [profile,ratio] of boundaryProfiles){
  for(const width of [1280,1600,1920]){
    const height=width/ratio,designWidth=1600,designHeight=1600/ratio;
    const cover=Math.max(1,designHeight/900),cardScale=Math.min(cover,designWidth/1120,designHeight/600);
    // 使用存档实际背景底色叶层；静态祖先中心、单位缩放另有断言。
    for(const {s} of plats(R('adapt715r.background.part.1'))){
      const size=pair(s,505),pos=pair(s,504);
      assert((size[0]/2-Math.abs(pos[0]))*cover>=designWidth/2-1e-5);
      assert((size[1]/2-Math.abs(pos[1]))*cover>=designHeight/2-1e-5);
    }
    assert(cardScale>0&&1120*cardScale<=designWidth+1e-9&&600*cardScale<=designHeight+1e-9,'卡片越界 '+profile+' '+width);
    boundaryCases.push({profile,reportedWidth:width,reportedHeight:+height.toFixed(4),designWidth,designHeight:+designHeight.toFixed(4),cover:+cover.toFixed(6),cardScale:+cardScale.toFixed(6),paperScale:+cardScale.toFixed(6),backgroundCoversInDesignWidthModel:true,cardGroupFits:true});
  }
}
for(const {s}of plats(selectBase)){assert.deepEqual(pair(s,502),[0,0]);assert.deepEqual(pair(s,503),[1,1]);assert.deepEqual(pair(s,505),[4,4]);}
assert.equal(selectBase.parentId,clientRoot.id);
for(const {s}of plats(bg))assert(pairOf(s,501).sub.every(f=>f.f===0),'服务器重复背景仍在绘制');
for(const name of ['art641.select','art642.select.backdrop','grp653.static.1.art642.select.backdrop'])for(const {s}of plats(R(name))){assert.deepEqual(pair(s,504),[0,0]);assert(pairOf(s,501).sub.every(f=>Math.abs(f.f-1)<1e-5));}
const audit={base:path.basename(INPUT),baseSha256:hash(original.src),recordsBefore:original.recs.length,recordsAfter:g.recs.length,groups,targets,removed:removed.map(r=>({id:r.id,name:r.name,reason:'隐藏的客户端静态美术叶层，排除固定区域，无Lua运行时引用'})),protectedCount:protectedIds.size,background:{serverId:bg.id,asset:'police-v19',mode:'原生满幅拉伸；非等比cover',before:bgStates,clientBackdrop:backdrop.name},wax:{group:wax[0].name,count:240,mode:'独立客户端父级；相对1600x900背景中心分别乘W/1600、H/900'},boundaryRegression:{profiles:boundaryProfiles.map(([name])=>name),cases:boundaryCases,assertions:['背景cover同时覆盖宽高','选关衬纸/白框统一cardScale','卡片组不越出可用矩形'],realGameTest:false},limitations:['已移除移动端固定1600x720兜底，所有设备只使用有效UI画布尺寸。','root恢复原生满拉伸、零偏移与单位缩放。','不将画布API数值当成物理像素；选关背景纸、卡片衬纸和白框共用cover链。'],realGameTest:false};
if(DRY){console.log(JSON.stringify({records:audit.recordsAfter,removed:removed.length,groups:groups.length,targets:targets.length,wax:audit.wax,protected:protectedIds.size},null,2));process.exit(0);}
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const report=writeGil(g,OUT,{label:'715 UI分端修订与废弃美术清理',expectRecs:g.recs.length,expectMarker:'v715',quiet:true,assert:g2=>{const m=new Map(g2.recs.map(r=>[r.id,r]));for(const r of g2.recs){assert(expected.get(r.id)?.equals(encodeMsg([r.field])),'落盘 '+r.name);for(const id of kids(r)){assert(m.has(id));assert.equal(m.get(id).parentId,r.id);}}for(const id of deleted)assert(!m.has(id));assert(findScriptLeaf(g2).buf.equals(Buffer.from(script)));assert(g2.trailer.equals(original.trailer));assert.deepEqual(flattened(g2),flattened(original));return true;}});
audit.revision=12;audit.startupFix='选关成绩布局倍率读取允许ui_adapter为空；修复layout_plan中断导致首页初始化清理未执行';audit.selectCardScale="由cover统一驱动，受1120x600卡片组可用矩形上限约束；衬纸、白框、动态缩略图、文字与点击区同步";audit.visibilityFix="页面显隐双向恢复；背景子层逐层互斥；不透明底色常驻且按页面换色；选关底色严格覆盖画布";audit.officialProfiles=['PC 16:9','PC 21:9','触屏 16:9','触屏 19.5:9','触屏 4:3','主机手柄 16:9','主机手柄 21:9','移动手柄 16:9','移动手柄 19.5:9','移动手柄 4:3'];audit.tearGroups=tearGroups;audit.tearMode="原生尺寸，右上/左下贴边平移，六组置于选关美术末尾并逐层显隐";audit.backUnified=backPairs;audit.background.mode='服务器原生满屏拉伸兜底＋客户端等比cover背景＋常驻客户端底色';audit.background.converted=converted;audit.background.guard=guard.name;audit.background.sourceAssetPreserved=true;audit.background.serverDisabledByZeroScale=false;audit.background.serverFullStretch=true;audit.background.clientRoot=coverRoot.name;audit.background.visibilityProtectedByDecor=true;audit.background.selectCoverParents=['art642.select.backdrop','art642.select.paper','art642.select.thread'];audit.background.selectCardParents=['art642.select.lighting','art642.select.frames'];audit.background.selectFixedParents=['art642.select.buttons'];audit.wax.mode='独立父级，使用与完整背景相同的中心、尺度及重试逻辑';audit.limitations=['未操作游戏进行实机渲染验证；不能宣称真实设备漏边已彻底消失。','卡片组使用cover并受可用矩形上限约束；极窄或极矮画布仍需实机确认文字可读性。','服务器兜底背景允许非等比拉伸；边缘可能显示背景装饰延伸，需实机检查。','客户端背景649图元和服务器底层同时保留；需实机观察性能、裁剪、安全区和命中。'];audit.checks={diskReread:true,roundtrip:true,protectedSubtrees:true,ancestorTransforms:true,gameModulesUnchanged:true,drawOrderExceptRequestedTears:true,tearsAboveSelectArt:true,parentChildLinks:true};audit.rootPositionFix={previous:'v9中心定尺寸、min(cw/1600,ch/900)缩放',current:'根满拉伸、选关背景与卡片按cover统一；固定玩法根仍单位缩放',basis:'用户第四张原移动端截图、v3左右边界思路与v10上下覆盖问题',readback:'位置、尺寸差、缩放、锚点及pivot均校验',realGameVerified:false};audit.backFix={recipe:'647完整返回旗配方',height:79.2,previousHeight:61.776,gameAndSelect:true};audit.requestedReorder={names:tearGroups.map(t=>t.name),leafCount:tearLeafIds.size,scope:'仅撕边相对其它选关美术的绘制顺序允许变化'};audit.selectCardScale='背景纸、连线、衬纸、白框及动态内容共用min(cover,1600/1120,designHeight/600)；底纹独立cover';
audit.background.mode='服务器背景零缩放停绘；客户端背景按1600宽设计坐标等比cover；选关底色重挂root并原生全拉伸';
audit.background.serverDisabledByZeroScale=true;audit.background.serverFullStretch=false;
audit.background.selectCoverParents=['art642.select.backdrop'];audit.background.selectCardParents=['art642.select.paper','art642.select.thread','art642.select.lighting','art642.select.frames'];
audit.background.selectBase={name:selectBase.name,oldParent:selectBaseOldParent.name,parent:clientRoot.name,anchorMin:[0,0],anchorMax:[1,1],sizeDelta:[4,4],page:'select'};
audit.background.assessment='v3停绘服务器背景、v11恢复绘制已由四端存档证实；背景露出唯一实机根因尚未由日志证实。';
audit.tearMode='fit等比缩放与角部偏移，沿用六组置顶和逐层显隐';
audit.boundaryRegression.assertions=['实际背景底色叶层在1600宽设计模型覆盖宽高','选关底色root满拉伸且不依赖API绝对数值','纸/连线/衬纸/白框共用cardScale','服务器背景四端停绘','卡片组不越出设计可用矩形'];
audit.limitations=['未操作游戏进行实机渲染验证；v12是修复候选，不宣称已消除真实设备漏边。','1600宽设计映射沿用v3并用截图对照支持，实际宿主/API映射尚无运行日志确认。','API若固定返回16:9则不能推断实际设备比例；不使用固定移动端720高度冒充测量。','模型不模拟引擎裁剪、字体栅格化、原生安全区和触控命中。'];
audit.checks.drawOrderExceptRequestedTearsAndSelectBase=true;delete audit.checks.drawOrderExceptRequestedTears;
audit.checks.selectBaseRootStretch=true;audit.checks.serverBackgroundDisabled=true;
audit.rootPositionFix={previous:'v11直接采用API宽高并重写root，侧栏受绝对数值影响',current:'保留原生root，w=1600,h=1600*ch/cw；背景在此设计空间cover',basis:'v3实机对照与v11独立宿主模型失败案例；不是实机尺寸测量',realGameVerified:false};
audit.requestedReorder.scope='仅撕边置顶与选关底色移到root背景层允许改变绘制顺序';
audit.visibilityFix='页面显隐双向恢复；服务器重复背景停绘；root下选关底色按页面显示';
audit.outputSha256=hash(report.g2.src);fs.writeFileSync(LUA,script);fs.writeFileSync(AUDIT,JSON.stringify(audit,null,2));console.log(JSON.stringify({output:OUT,removed:removed.length,groups:groups.length,targets:targets.length,records:g.recs.length,checks:audit.checks}));
