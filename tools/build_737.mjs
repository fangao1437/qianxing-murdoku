// 从 736 派生，只改商城图层、布局和共用底板的页面可见性。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadTree,findScriptLeaf,writeGil} from './gil/gilwrite.mjs';
import {asIdList,setChildList,cloneField,stateBlocks,pairOf,setPair,pairValue,textsOf,writeVarint} from './gil/gilread.mjs';
const base=fileURLToPath(new URL('../../构建存档/',import.meta.url));
const out=path.join(base,'737/737_商城原生图标与全屏底色_v2.gil');
assert(!fs.existsSync(out),'737 成品已存在');
const g=loadTree(path.join(base,'736/736_调查商城.gil'));
const prefix='econ.shop736.';
const shop=k=>g.byName.get(prefix+k);
const field=(p,n)=>p.sub.find(f=>f.field===n);
function component(r,n){return r.field.sub.filter(x=>x.field===505).map(x=>field(x,503)?.sub?.find(f=>f.field===n)).find(Boolean);}
const root=g.recs.find(r=>r.id===shop('s0').parentId);
const leaf=findScriptLeaf(g);let lua=leaf.buf.toString('utf8');
function replace(a,b){assert.equal(lua.split(a).length,2,a);lua=lua.replace(a,()=>b);}
function node(key,replacement){const line=lua.split('\n').find(s=>s.includes(`push({id='${prefix}${key}',`));assert(line,key);replace(line+'\n',replacement?`      push({id='${prefix}${key}',parent='root',kind='image',${replacement}})\n`:'');}
const dropped=['s80','s81','return','s106','s107','s133','s134'];
const droppedIds=new Set();for(const key of dropped){const r=shop(key);node(key);assert.equal(r.parentId,root.id);droppedIds.add(r.id);const at=r.holder.indexOf(r.field);assert(at>=0);r.holder.splice(at,1);}
setChildList(root.childList,asIdList(root.childList.payload,true).map(Number).filter(id=>!droppedIds.has(id)));
const icons=[['s82','hex.back',100109,76,45,64,0xfff1e2ae,'true'],['s105','hex.hint',100120,592,264,76,0xff4f381f,'true'],['s132','hex.hint',100120,1316,321,65,0xff4f381f,"pick=='clue'"]];
for(const [key,source,asset,x,y,size,color,visible] of icons){const r=shop(key),im=component(r,84);assert.equal(Number(field(component(g.byName.get(source),84),503).num),asset);field(im,503).num=BigInt(asset);field(im,502).num=BigInt(color);
  for(const state of stateBlocks(r.field.sub,[])){setPair(pairOf(state,504),(x+size/2-960)*5/6,(540-y-size/2)*5/6);setPair(pairOf(state,505),size*5/6,size*5/6);const rot=field(state,508);if(rot){rot.sub=[];rot.payload=null;rot.len=0;}}
  node(key,`rect={x=${x},y=${y},w=${size},h=${size}},visible=${visible}`);
}
// 按选关返回旗原组合的顺序复制材质、相对位置和旋转。
const flagParts=['shadow','outline','outline.tri.top','outline.tri.bottom','ribbon','ribbon.tri.top','ribbon.tri.bottom'];
const order=asIdList(root.childList.payload,true).map(Number);
const ids=[],flagNodes=[];
function walk(fields,visit){for(const f of fields){visit(f);if(f.sub)walk(f.sub,visit);}}
const used=new Set();walk(g.tree,f=>{if(f.wt===0)used.add(Number(f.num));});let nextId=1073770300;
for(const suffix of flagParts){
 const proto=shop('s82'),record=cloneField(proto.field),name=prefix+'flag.'+suffix;
 while(used.has(nextId))nextId++;const id=nextId++;ids.push(id);
 const old=writeVarint(proto.id);walk(record.sub,f=>{if(f.wt===0&&Number(f.num)===proto.id)f.num=BigInt(id);else if(!f.sub&&f.wt===2&&f.payload?.equals(old)){f.payload=writeVarint(id);f.len=f.payload.length;}});
 const nf=textsOf(record.sub,[]).find(f=>f.payload.toString()===proto.name);nf.payload=Buffer.from(name);nf.len=nf.payload.length;
 const src=g.byName.get('art647.select.back.'+suffix),dest={field:record};
 component(dest,84).sub=component(src,84).sub.map(cloneField);
 const original=stateBlocks(src.field.sub,[])[0];const coord=(n,i)=>pairValue(pairOf(original,n),i);
 const w=coord(505,0),h=coord(505,1),cx=107+(coord(504,0)+730.9119873046875),cy=77-(coord(504,1)-293);
 for(const st of stateBlocks(record.sub,[])){setPair(pairOf(st,504),(cx-960)*5/6,(540-cy)*5/6);setPair(pairOf(st,505),w*5/6,h*5/6);const rotation=pairOf(original,508);st.sub=st.sub.filter(f=>f.field!==508);if(rotation)st.sub.push(cloneField(rotation));}
 proto.holder.push(record);flagNodes.push(`      push({id='${name}',parent='root',kind='image',visible=true,rect={x=${cx-w/2},y=${cy-h/2},w=${w},h=${h}}})`);
}
order.splice(order.indexOf(shop('s82').id),0,...ids);setChildList(root.childList,order);
const arrowLine=lua.split('\n').find(s=>s.includes(`push({id='${prefix}s82',`));replace(arrowLine,flagNodes.join('\n')+'\n'+arrowLine);
const hitKey='hit.leave',hit=shop(hitKey);const hitLine=lua.split('\n').find(s=>s.includes(`push({id='${prefix}${hitKey}',`));assert(hitLine.includes('w=157,h=88'));replace(hitLine,hitLine.replace('x=29,y=33,w=157,h=88','x=29,y=30,w=198,h=100'));
for(const st of stateBlocks(hit.field.sub,[])){setPair(pairOf(st,504),(128-960)*5/6,(540-80)*5/6);setPair(pairOf(st,505),198*5/6,100*5/6);}
// 仅移植四种设备的变换数据，不复制引用或默认可见性。
const fill=g.byName.get('adapt715r.background.fill');
const transforms=r=>field(component(r,13),12);
const source=transforms(fill),target=transforms(shop('s0'));
assert.equal(source.sub.filter(f=>f.field===501).length,4);
target.sub=source.sub.map(cloneField);
node('s0','visible=true,raycast=false');
replace('visible=set_visible(fill,true) and visible',"visible=set_visible(fill,page~='shop') and visible");
assert(lua.includes('构建标记 v736 / 调查商城'));lua=lua.replaceAll('构建标记 v736 / 调查商城','构建标记 v737 / 商城原生图标与全屏底色');
leaf.field.payload=Buffer.from(lua);
fs.mkdirSync(path.dirname(out),{recursive:true});
writeGil(g,out,{label:'737',expectMarker:'v737',expectRecs:g.recs.length-dropped.length+flagParts.length,assert:b=>{
 const rec=k=>b.byName.get(prefix+k),back=rec('s0');
 assert(findScriptLeaf(b).buf.equals(leaf.field.payload));for(const suffix of flagParts){assert.deepEqual(component(rec('flag.'+suffix),84).payload,component(b.byName.get('art647.select.back.'+suffix),84).payload);}assert(dropped.every(k=>!rec(k)));assert(icons.every(([key,,asset])=>Number(field(component(rec(key),84),503).num)===asset));
 assert.equal(Number(field(component(back,84),502).num),0xff3b2317);
 const states=transforms(back).sub.filter(f=>f.field===501).map(f=>field(f,502));assert.equal(states.length,4);
 for(const st of states){for(const [w,h] of [[1600,1200],[1920,1080],[1920,1200],[2340,1080],[2520,1080],[5120,1440]]){for(const [axis,span] of [[0,w],[1,h]]){const componentValue=n=>pairValue(pairOf(st,n),axis);assert.equal(componentValue(502),0);assert.equal(componentValue(503),1);assert.equal(componentValue(504),0);assert.equal(componentValue(505),0);assert.equal((componentValue(503)-componentValue(502))*span+componentValue(505),span);}}}
 console.log('成品断言通过：四套设备锚点 × 六种视口，商城底板零边距；三处原图标引用及返回旗的七层素材核对通过。');return true;
}});
