// 715 -> 父级定位实验版。参考：679已记录移动端1600x720可见区，非通用安全区。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg,cloneField,asIdList,ensureChildListTop,setChildList,textsOf,pairOf,pairValue,setPair} from '../tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf} from '../tools/gil/gilwrite.mjs';
const DIR=path.dirname(fileURLToPath(import.meta.url));
const INPUT=path.resolve(DIR,'../715_设计复核/715_全线索规则复核修订.gil');
const OUTPUT=path.join(DIR,'自适应调整版.gil');
const LUA=path.join(DIR,'自适应客户端脚本.lua');
const AUDIT=path.join(DIR,'坐标对照与验证.json');
const DRY=process.argv.includes('--dry');
if(!DRY && fs.existsSync(OUTPUT) && !process.argv.includes('--rebuild'))throw Error('输出已存在，拒绝覆盖');
const g=readGil(INPUT), original=readGil(INPUT);
const before=new Map(original.recs.map(r=>[r.id,encodeMsg([r.field])]));
const byId=new Map(g.recs.map(r=>[r.id,r]));
const named=n=>{const rs=g.recs.filter(r=>r.name===n);assert.equal(rs.length,1,'名称应唯一 '+n);return rs[0];};
const ns=(f,ks)=>ks.reduce((a,k)=>a.flatMap(x=>(x.sub||[]).filter(y=>y.field===k)),[f]);
function platforms(r){return ns(r.field,[505,503,13,12,501]).map(p=>({type:Number(p.sub.find(f=>f.field===501&&f.wt===0)?.num??0),s:p.sub.find(f=>f.field===502)?.sub})).filter(p=>p.s).map(p=>({...p,s:{sub:p.s}}));}
const pair=(s,n)=>[pairValue(pairOf(s,n),0),pairValue(pairOf(s,n),1)];
function setP(s,n,x,y){let p=pairOf(s,n);if(!p){p={field:n,wt:2,sub:[],payload:null};s.sub.push(p);}setPair(p,x,y);}
const kids=r=>r.childList?(asIdList(r.childList.payload,true)||[]):[];
function setKids(r,ids){r.childList=ensureChildListTop(r);r.childList.sub=null;setChildList(r.childList,ids);}
const ANCHORS={LM:[0,.5],RM:[1,.5],TL:[0,1],TR:[1,1],BR:[1,0],TC:[.5,1],BC:[.5,0]};
const refs={w:1600,h:720,canvasW:1600,canvasH:900,source:'679历史1280x576截图映射：1600画布可见y=90..810；本版假设沿用该移动端参考，不是715实测'};
const targets=[],groups=[],touched=new Set(),reparented=new Set(),changedParents=new Set();
let maxId=Number(g.maxId);
const rawScript=findScriptLeaf(g).buf.toString('utf8');
assert(Buffer.from(rawScript).equals(fs.readFileSync(path.resolve(DIR,'../715_设计复核/715_客户端脚本.lua'))));
function addTarget(r,key){
 if(targets.some(t=>t.id===r.id))throw Error('重复目标 '+r.name);
 const ps=platforms(r);assert.equal(ps.length,4,r.name+' 四端');
 const states=ps.map(({type,s})=>{const pos=pair(s,504);assert(pos.every(Number.isFinite));const a=pair(s,502),b=pair(s,503),piv=pair(s,506);assert(a.every((v,i)=>Math.abs(v-.5)<.001)&&b.every(v=>Math.abs(v-.5)<.001),'目标必须中心锚点 '+r.name);assert(piv.every(v=>Math.abs(v-.5)<.001));
  const [ax,ay]=ANCHORS[key],ox=pos[0]-(ax-.5)*refs.w,oy=pos[1]-(ay-.5)*refs.h;
  const editor=[ox+(ax-.5)*1600,oy+(ay-.5)*900];setP(s,504,...editor);
  return {platform:type,reference:pos,edgeOffset:[ox,oy],editor};});
 targets.push({id:r.id,name:r.name,parent:byId.get(r.parentId)?.name,key,states});touched.add(r.id);
}
function remap(ff,from,to,depth=0){for(const f of ff||[]){if(!(depth===0&&f.field===504)&&f.wt===0&&Number(f.num)===from)f.num=BigInt(to);if(f.sub)remap(f.sub,from,to,depth+1);}}
function addGroup(parent,ids,key){
 const proto=named('art641.game'),field=cloneField(proto.field),id=++maxId,name='adapt715.'+key+'.'+(groups.length+1);
 remap(field.sub,proto.id,id);
 const nf=textsOf(field.sub,[]).find(f=>f.payload.toString('utf8')===proto.name);assert(nf);nf.payload=Buffer.from(name);nf.len=nf.payload.length;
 field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(parent.id);
 for(const p of ns(field,[505,503,14,17])){p.sub=[];p.payload=Buffer.alloc(0);p.len=0;p.isText=false;}
 const r={id,name,parentId:parent.id,field};setKids(r,ids);
 // New groups retain parent dimensions so their centred children keep identical local coordinates.
 const parentStates=platforms(parent);
 for(const {type,s} of platforms(r)){const p=parentStates.find(p=>p.type===type);assert(p);const size=pair(p.s,505);setP(s,505,...size);setP(s,504,0,0);}
 const siblings=kids(parent),at=siblings.indexOf(ids[0]);assert.deepEqual(siblings.slice(at,at+ids.length),ids);
 setKids(parent,[...siblings.slice(0,at),id,...siblings.slice(at+ids.length)]);changedParents.add(parent.id);
 for(const cid of ids){const c=byId.get(cid);assert.equal(c.parentId,parent.id);c.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(id);c.parentId=id;reparented.add(cid);}
 g.recHolder.push(field);g.recs.push(r);byId.set(id,r);
 groups.push({id,name,parent:parent.name,key,children:ids,childNames:ids.map(i=>byId.get(i).name)});addTarget(r,key);
}
function classify(r,parent){const n=r.name||'';
 if(parent==='grp653.static.1.art641.game'){
  if(/^art641\.game\.board(frame|bottom)/.test(n))return null;
  const f=n.match(/^art(?:641|657)\.game\.flag\.(back|submit|redo|undo|hint)(?:\.|$)/);
  if(f)return f[1]==='back'?'TL':f[1]==='hint'?'BR':'TR';
  if(/^art(?:663|664|675)\.wax\./.test(n))return 'BR';
  if(/^art657\.game\.pin(?:\.|$)/.test(n))return 'RM';
  return 'LM';
 }
 if(parent==='grp653.static.1.art641.home'){
  if(/^art(?:641|656)\.home\.camera\./.test(n))return 'LM';
  if(/^art656\.home\.(note|wave)\./.test(n))return 'RM';
 }
 if(/^art647\.(home|select)\.settle\./.test(n))return 'BR';
 if(/^art647\.select\.back\./.test(n))return 'TL';
 if(n==='art647.select.diamond.left')return 'LM';
 if(n==='art647.select.diamond.right')return 'RM';
 if(parent==='home'&&/^home\.tutorial627\./.test(n))return 'LM';
 return null;
}
const parents=['grp653.static.1.art641.game','grp653.static.1.art641.home','art641.home','art642.select.buttons','grp653.static.1.art642.select.buttons','home'];
for(const pn of parents){const p=named(pn),ids=[...kids(p)];let run=[],key=null;const flush=()=>{if(run.length)addGroup(p,run,key);run=[];};for(const id of ids){const c=byId.get(id);assert(c);const k=classify(c,pn);if(k!==key){flush();key=k;}if(k)run.push(id);}flush();}
const direct={clues:'LM',topbar:'LM','clues.help617':'LM','clues.help627.hit':'LM','settle.btn':'BR','settle.btn.countdown':'BR','select.back':'TL','hit.select.back':'TL','hit.select.prev':'LM','hit.select.next':'RM','hint635.menu':'BR','hint635.result':'BR'};
for(const s of ['hex','hit'])for(const n of ['back','submit','redo','undo','hint'])direct[s+'.'+n]=n==='back'?'TL':n==='hint'?'BR':'TR';
// Confirmation controls stay with centred modal/confirmation layout, like other popup controls.
for(const [n,k] of Object.entries(direct))addTarget(named(n),k);
// Server image references police-v19 as an asset; it is not a live client root.
const serverBackground=byId.get(1073742783);assert(serverBackground);
const serverBackgroundBefore=platforms(serverBackground).map(({type,s})=>({platform:type,min:pair(s,502),max:pair(s,503),pos:pair(s,504),size:pair(s,505)}));
for(const {s} of platforms(serverBackground)){setP(s,502,0,0);setP(s,503,1,1);setP(s,504,0,0);setP(s,505,0,0);}
const backgroundNames=['art642.select.backdrop'];
const backgrounds=backgroundNames.map(n=>{const r=named(n),ps=platforms(r);assert.equal(ps.length,4);return {id:r.id,name:n,states:ps.map(({type,s})=>({platform:type,pos:pair(s,504),size:pair(s,505)}))};});
// Exact paths: preserve existing entries and add routes for new groups / moved controls.
const root=named('root'),paths=new Map();function walk(r,p=[]){const q=[...p,r.name];paths.set(r.id,q.join('/'));for(const id of kids(r))walk(byId.get(id),q);}walk(root);
let script=rawScript;
const tableStart=script.indexOf('local STATIC_PATH_655 = {'),tableEnd=script.indexOf('\nlocal function path_lookup_655',tableStart);
assert(tableStart>=0&&tableEnd>tableStart);
let table=script.slice(tableStart,tableEnd);
for(const r of g.recs){if(!paths.has(r.id)||!r.name)continue;const key='['+JSON.stringify(r.name)+']';const value=JSON.stringify(paths.get(r.id));const escaped=key.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');const rx=new RegExp('  '+escaped+' = "[^"\\n]*",');
 if(rx.test(table))table=table.replace(rx,'  '+key+' = '+value+',');
 else if(targets.some(t=>t.id===r.id)||reparented.has(r.id))table=table.replace(/\n}\s*$/,'\n  '+key+' = '+value+',\n}\n');
}
script=script.slice(0,tableStart)+table+script.slice(tableEnd);
// Preserve old traversal semantics for the one group inserted below home.
const homeGroup=groups.find(x=>x.parent==='home');assert(homeGroup);
script=script.replace('local DECOR = {','local DECOR = {\n  ['+JSON.stringify(homeGroup.name)+'] = true,');
// Adaptation uses immutable original per-platform values (no cumulative offset/scale).
const luaRows=targets.map(t=>'  {name='+JSON.stringify(t.name)+', ax='+ANCHORS[t.key][0]+', ay='+ANCHORS[t.key][1]+', pos={'+t.states.map(s=>'['+s.platform+']={'+s.reference.join(',')+'}').join(',')+'}},').join('\n');
const bgRows=backgrounds.map(t=>'  {name='+JSON.stringify(t.name)+', base={'+t.states.map(s=>'['+s.platform+']={'+[...s.pos,...s.size].join(',')+'}').join(',')+'}},').join('\n');
const runtime=`
-- ADAPT715 BEGIN: reference visible rectangle 1600x720; fixed centred controls are excluded.
local ADAPT715_TARGETS = {
${luaRows}
}
local ADAPT715_BACKGROUNDS = {
${bgRows}
}
local adapt715_state = {elapsed=1,signature=nil,handles={},logged=false}
local function adapt715_pair(c, method)
  if c == nil or c[method] == nil then return nil end
  local ok,x,y=pcall(function() return c[method](c) end)
  if not ok then return nil end
  if type(x)=="number" and type(y)=="number" then return x,y end
  if x~=nil then local good,a,b=pcall(function() return x.x or x.X,x.y or x.Y end);if good then return a,b end end
end
local function adapt715_size(c,w,h,depth)
  if c==nil or depth>12 then return nil end
  local sw,sh=adapt715_pair(c,"GetSizeDelta")
  local ax,ay=adapt715_pair(c,"GetAnchorMin")
  local bx,by=adapt715_pair(c,"GetAnchorMax")
  if type(sw)~="number" or type(sh)~="number" or type(ax)~="number" or type(ay)~="number" or type(bx)~="number" or type(by)~="number" then return nil end
  local pw,ph=w,h
  if math.abs(bx-ax)>0.00001 or math.abs(by-ay)>0.00001 then
    local p=nil;pcall(function() p=c.parent end)
    if p~=nil then local x,y=adapt715_size(p,w,h,depth+1);if x~=nil then pw,ph=x,y end end
  end
  return pw*(bx-ax)+sw,ph*(by-ay)+sh
end
local function sync_adapt715(dt,force)
  if not adapter then return end
  local st=adapt715_state
  st.elapsed=st.elapsed+(dt or 0)
  if not force and st.elapsed<0.5 then return end
  st.elapsed=0
  local ok,w,h=pcall(function() return game.GetUICanvasSize() end)
  if not ok or type(w)~="number" or type(h)~="number" or w~=w or h~=h or w<=0 or h<=0 or w==math.huge or h==math.huge then return end
  local gen=adapter._lookup_gen or 0
  if st.gen~=gen then st.handles={};st.signature=nil;st.gen=gen end
  local root=adapter:find("root")
  local rw,rh=adapt715_size(root,w,h,0)
  if type(rw)~="number" or type(rh)~="number" or rw~=rw or rh~=rh or rw<=0 or rh<=0 then return end
  local device="unknown"
  pcall(function() local d=game.GetDevice();device=tostring(d.Name or d.FullName or d) end)
  local platform=0
  if device=="Mobile" then platform=1 elseif device=="Controller" then platform=2 elseif device=="MobileController" then platform=3 end
  local signature=string.format("%.3f/%.3f/%s/%s",rw,rh,device,tostring(gen))
  if signature==st.signature and not force then return end
  local complete=true
  local function find(name)
    local c=st.handles[name]
    if c==nil then c=adapter:find(name);st.handles[name]=c end
    return c
  end
  for _,spec in ipairs(ADAPT715_TARGETS) do
    local c=find(spec.name)
    local p=spec.pos[platform] or spec.pos[0]
    local x=p[1]+(spec.ax-0.5)*(rw-1600)
    local y=p[2]+(spec.ay-0.5)*(rh-720)
    if c==nil then complete=false else
      local good=pcall(function() c:SetAnchoredPosition(x,y) end)
      if not good then complete=false end
    end
  end
  for _,spec in ipairs(ADAPT715_BACKGROUNDS) do
    local c=find(spec.name)
    local b=spec.base[platform] or spec.base[0]
    local scale=math.max(rw/b[3],rh/b[4])
    if c==nil then complete=false else
      local good=pcall(function() c:SetLocalScale(scale,scale,1) end)
      if not good then complete=false end
    end
  end
  if complete then st.signature=signature end
  if st.logSignature~=signature then
    st.logSignature=signature
    print("[adapt715] canvas="..tostring(w).."x"..tostring(h).." root="..tostring(rw).."x"..tostring(rh).." device="..device.." complete="..tostring(complete))
    if math.abs(w-1600)<1 and math.abs(h-900)<1 then
      print("[adapt715] canvas reports reference 1600x900; physical visible area/safe-area is not verified. Native parent mapping requires device verification.")
    end
  end
end
-- ADAPT715 END
`;
const insert='local art641_cache = nil';assert(script.includes(insert));script=script.replace(insert,runtime+'\n'+insert);
script=script.replace(/  sync_block640\(\)\r?\nend/,'  sync_block640()\n  sync_adapt715(dt, false)\nend');
assert(script.includes('sync_adapt715(dt, false)'));
script=script.replace('  pcall(check_canvas)','  pcall(check_canvas)\n  pcall(function() sync_adapt715(0, true) end)');
script=script.replace('构建标记 v715 / 2026-11-17 / 全线索保留复核与第四五七关修订','构建标记 v715 / 2026-11-17 / 基于715父级定位自适应实验版');
// Avoid the old warning suggesting a global redesign which would move protected UI.
script=script.replace('或改 ui_controller.lua 的 M.CANVAS / M.SCALE。','本实验版由父级定位适配处理；固定区域保持715坐标。');
const leaf=findScriptLeaf(g);leaf.field.payload=Buffer.from(script);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
// Controlled original records: only geometry #504 of target parents, parent ids and child lists.
function strip(r){const f=cloneField(r.field);if(reparented.has(r.id))f.sub=f.sub.filter(x=>!(x.field===504&&x.wt===0));if(changedParents.has(r.id))f.sub=f.sub.filter(x=>x.field!==503);if(touched.has(r.id)){for(const p of ns(f,[505,503,13,12,501,502]))p.sub=p.sub.filter(x=>x.field!==504);}if(r.id===serverBackground.id){for(const p of ns(f,[505,503,13,12,501,502]))p.sub=p.sub.filter(x=>![502,503,504,505].includes(x.field));}return encodeMsg([f]);}
for(const old of original.recs){const cur=byId.get(old.id);assert(cur);assert(strip(old).equals(strip(cur)),'超出允许字段 '+old.name);}
const protectedNames=['stage','board.bg','art657.grid.reuse','modal','td.home','td.l1','td.l2','help617','home.select','home.continue','home.shop','home.bag'];
for(const n of protectedNames){const r=named(n);assert(before.get(r.id).equals(encodeMsg([r.field])),'保护对象被改 '+n);}
const groupIds=new Set(groups.map(x=>x.id));
function flattened(gx){const m=new Map(gx.recs.map(r=>[r.id,r])),out=[];function visit(id){const r=m.get(id);assert(r);if(!groupIds.has(id))out.push(id);for(const c of kids(r))visit(c);}visit(root.id);return out;}
assert.deepEqual(flattened(g),flattened(original),'原始绘制顺序变化');
const audit={base:path.basename(INPUT),reference:refs,interpretation:{backgrounds:backgroundNames,clues:'left-middle; whole card area including help tab moves together',protected:protectedNames,centerSelectCards:'unchanged as a centred composition'},recordsBefore:original.recs.length,recordsAfter:g.recs.length,groups,targets,backgrounds,serverBackground:{id:serverBackground.id,asset:'police-v19',mode:'native full stretch, aspect ratio may change',before:serverBackgroundBefore},checks:{sourceLuaEqualsEmbedded:true,onlyAllowedFieldsChanged:true,protectedRecordsUnchanged:true,originalDrawOrderUnchanged:true},realGameTest:false,limitations:['参考可见区沿用679记录，未取得715本轮跨端实测。','若画布和父尺寸都固定而宿主另行裁切，本版无法从固定值推断屏幕比例。','只移动父级不缩放棋盘或线索；极窄宽度可能重叠，需要实机验证后决定。']};
if(DRY){console.log(JSON.stringify({records:audit.recordsAfter,groups:groups.length,targets:targets.length,groupList:groups.map(x=>({name:x.name,parent:x.parent,key:x.key,count:x.children.length})),backgrounds},null,2));process.exit(0);}
fs.writeFileSync(LUA,script);
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const report=writeGil(g,OUTPUT,{label:'715 父级定位与背景缩放',expectRecs:g.recs.length,expectMarker:'v715',quiet:true,assert:g2=>{
 for(const r of g2.recs)assert(expected.get(r.id)?.equals(encodeMsg([r.field])),'落盘不符 '+r.name);
 assert(findScriptLeaf(g2).buf.equals(Buffer.from(script)));assert(g2.trailer.equals(original.trailer));
 const m=new Map(g2.recs.map(r=>[r.id,r]));for(const r of g2.recs)for(const id of kids(r)){assert(m.has(id));assert.equal(m.get(id).parentId,r.id);}
 assert.deepEqual(flattened(g2),flattened(original));return true;
}});
audit.checks.diskReread=true;audit.checks.roundtrip=true;audit.checks.bidirectionalParents=true;
audit.inputSha256=crypto.createHash('sha256').update(original.src).digest('hex');audit.outputSha256=crypto.createHash('sha256').update(report.g2.src).digest('hex');audit.bytes=report.bytes;audit.fieldDifferences=report.diffs;
fs.writeFileSync(AUDIT,JSON.stringify(audit,null,2));
console.log(JSON.stringify({output:OUTPUT,records:report.recs,groups:groups.length,targets:targets.length,bytes:report.bytes,checks:audit.checks}));
