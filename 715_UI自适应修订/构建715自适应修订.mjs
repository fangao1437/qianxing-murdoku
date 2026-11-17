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
const OUT=path.join(DIR,'715_UI自适应修订版.gil'),LUA=path.join(DIR,'715_UI自适应修订版.lua'),AUDIT=path.join(DIR,'715_UI自适应修订审计.json');
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
const changedParents=new Set(),reparented=new Set(),touched=new Set();
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
  if(/(notebook|clues|\.tab\.|help\.tab|\.ring|\.tape|ribbon|sticker)/.test(n))return'LM';
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
const wax=groups.filter(x=>x.key==='WAX');assert.equal(wax.length,1);assert.equal(wax[0].children.length,240);
// 外部整张图片实际承载控件，不能改素材母本 police-v19。
const bg=by.get(1073742783);assert(bg);const bgStates=plats(bg).map(({pt,s})=>({pt,pos:pair(s,504),size:pair(s,505),min:pair(s,502),max:pair(s,503)}));
for(const {s}of plats(bg)){setP(s,502,0,0);setP(s,503,1,1);setP(s,504,0,0);setP(s,505,0,0);}
const backdrop=R('art642.select.backdrop');
const paths=new Map();function walk(r,p=[]){const q=[...p,r.name];paths.set(r.id,q.join('/'));for(const id of kids(r))walk(by.get(id),q);}walk(R('root'));
const start=raw.indexOf('local STATIC_PATH_655 = {'),end=raw.indexOf('\nlocal function path_lookup_655',start);assert(start>0&&end>start);
const oldTable=raw.slice(start,end),routes=new Map();for(const m of oldTable.matchAll(/  \["([^"\n]+)"\] = "([^"\n]+)",/g))routes.set(m[1],m[2]);
for(const r of removed)routes.delete(r.name);
for(const r of g.recs)if(paths.has(r.id)&&(routes.has(r.name)||targets.some(t=>t.id===r.id)||reparented.has(r.id)))routes.set(r.name,paths.get(r.id));
const table='local STATIC_PATH_655 = {\n'+[...routes].map(([k,v])=>'  ['+JSON.stringify(k)+'] = '+JSON.stringify(v)+',').join('\n')+'\n}\n';
let script=raw.slice(0,start)+table+raw.slice(end);
const homeGroups=groups.filter(x=>x.parent==='home');script=script.replace('local DECOR = {','local DECOR = {\n'+homeGroups.map(x=>'  ['+JSON.stringify(x.name)+'] = true,').join('\n'));
const luaRows=targets.map(t=>'  {name='+JSON.stringify(t.name)+',kind='+JSON.stringify(t.key)+',ax='+t.ax+',ay='+t.ay+',base={'+t.states.map(s=>'['+s.pt+']={'+s.base.join(',')+'}').join(',')+'}},').join('\n');
const config='local ADAPT715R_TARGETS = {\n'+luaRows+'\n}\n';
const runtime=fs.readFileSync(path.join(DIR,'适配运行时.lua'),'utf8').replace('-- TARGET_TABLE',config);
assert(runtime.includes('local function sync_adapt715r'));
script=script.replace('local art641_cache = nil',runtime+'\nlocal art641_cache = nil');
script=script.replace('  sync_block640()\nend','  sync_block640()\n  sync_adapt715r(dt, false)\nend');
script=script.replace('  pcall(check_canvas)','  pcall(check_canvas)\n  sync_adapt715r(0, true)');
script=script.replace('构建标记 v715 / 2026-11-17 / 全线索保留复核与第四五七关修订','构建标记 v715 / 2026-11-18 / 分端定位与火漆独立映射修订');
const leaf=findScriptLeaf(g);leaf.field.payload=Buffer.from(script);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
// 硬保护：固定区域整树和祖先变换，原玩法模块、背景素材母本。
for(const id of protectedIds)assert(oldBytes.get(id).equals(encodeMsg([by.get(id).field])),'保护记录变化 '+by.get(id).name);
for(const n of ['root','home','art641.game','art641.home','art641.select','grp653.static.1.art641.game','grp653.static.1.art641.home']){const r=R(n),o=original.recs.find(x=>x.id===r.id);assert.deepEqual(plats(r).map(x=>encodeMsg([x.s]).toString('hex')),plats(o).map(x=>encodeMsg([x.s]).toString('hex')),'祖先变换变化 '+n);}
const sourceModules=raw.slice(0,raw.indexOf('local adapter   = nil'));const newModules=script.slice(0,script.indexOf('local adapter   = nil'));
const stripModule=s=>s.replace(/构建标记 v715[^\n]*/g,'构建标记 v715').replace(/local STATIC_PATH_655 = \{[\s\S]*?\n}\s*\n(?=local function path_lookup_655)/,'').replace(/local DECOR = \{[\s\S]*?(?=  \["home.tutorial627.bg"\])/,'local DECOR = {\n');
{const a=stripModule(newModules),b=stripModule(sourceModules);if(a!==b){let i=0;while(i<Math.min(a.length,b.length)&&a[i]===b[i])i++;console.log('MODULE_DIFF',i,JSON.stringify(a.slice(i-100,i+180)),JSON.stringify(b.slice(i-100,i+180)));}assert(a===b,'玩法模块差异');}
assert.equal((script.match(/sync_adapt715r\(dt, false\)/g)||[]).length,1,'更新入口必须存在且唯一');
function strip(r){const f=cloneField(r.field);if(reparented.has(r.id))f.sub=f.sub.filter(x=>!(x.field===504&&x.wt===0));if(changedParents.has(r.id))f.sub=f.sub.filter(x=>x.field!==503);if(touched.has(r.id))for(const p of ns(f,[505,503,13,12,501,502]))p.sub=p.sub.filter(x=>x.field!==504);if(r.id===bg.id)for(const p of ns(f,[505,503,13,12,501,502]))p.sub=p.sub.filter(x=>![502,503,504,505].includes(x.field));return encodeMsg([f]);}
for(const r of original.recs)if(!deleted.has(r.id))assert(strip(r).equals(strip(by.get(r.id))),'超范围变化 '+r.name);
const groupIds=new Set(groups.map(x=>x.id));function flattened(gx){const m=new Map(gx.recs.map(x=>[x.id,x])),out=[];function visit(id){if(deleted.has(id))return;const r=m.get(id);if(!groupIds.has(id))out.push(id);for(const c of kids(r))visit(c);}visit(R('root').id);return out;}
assert.deepEqual(flattened(g),flattened(original));
const audit={base:path.basename(INPUT),baseSha256:hash(original.src),recordsBefore:original.recs.length,recordsAfter:g.recs.length,groups,targets,removed:removed.map(r=>({id:r.id,name:r.name,reason:'隐藏的客户端静态美术叶层，排除固定区域，无Lua运行时引用'})),protectedCount:protectedIds.size,background:{serverId:bg.id,asset:'police-v19',mode:'原生满幅拉伸；非等比cover',before:bgStates,clientBackdrop:backdrop.name},wax:{group:wax[0].name,count:240,mode:'独立客户端父级；相对1600x900背景中心分别乘W/1600、H/900'},limitations:['画布恒1600x900且输入为触屏时用历史1600x720参考可见区，属于分端兜底，不能识别所有手机实际比例。','服务器背景与客户端画布实际映射仍需真机日志核对；不声称已支持所有比例。','棋盘放大未取得同设备前后测量；本版固定区域整树及祖先几何保持715。'],realGameTest:false};
if(DRY){console.log(JSON.stringify({records:audit.recordsAfter,removed:removed.length,groups:groups.length,targets:targets.length,wax:audit.wax,protected:protectedIds.size},null,2));process.exit(0);}
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const report=writeGil(g,OUT,{label:'715 UI分端修订与废弃美术清理',expectRecs:g.recs.length,expectMarker:'v715',quiet:true,assert:g2=>{const m=new Map(g2.recs.map(r=>[r.id,r]));for(const r of g2.recs){assert(expected.get(r.id)?.equals(encodeMsg([r.field])),'落盘 '+r.name);for(const id of kids(r)){assert(m.has(id));assert.equal(m.get(id).parentId,r.id);}}for(const id of deleted)assert(!m.has(id));assert(findScriptLeaf(g2).buf.equals(Buffer.from(script)));assert(g2.trailer.equals(original.trailer));assert.deepEqual(flattened(g2),flattened(original));return true;}});
audit.checks={diskReread:true,roundtrip:true,protectedSubtrees:true,ancestorTransforms:true,gameModulesUnchanged:true,drawOrder:true,parentChildLinks:true};audit.outputSha256=hash(report.g2.src);fs.writeFileSync(LUA,script);fs.writeFileSync(AUDIT,JSON.stringify(audit,null,2));console.log(JSON.stringify({output:OUT,removed:removed.length,groups:groups.length,targets:targets.length,records:g.recs.length,checks:audit.checks}));
