// 从 738 成品派生。前景沿用设计坐标，两个覆盖层在同一坐标系下居中超铺。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {loadTree,findScriptLeaf,writeGil} from './gil/gilwrite.mjs';
import {asIdList,setChildList,cloneField,pairOf,setPair,pairValue} from './gil/gilread.mjs';
const dir=fileURLToPath(new URL('../../构建存档/',import.meta.url));
const out=path.join(dir,'739/739_调查商城全屏与选中态.gil');
assert(!fs.existsSync(out),'739 已存在');
const g=loadTree(path.join(dir,'738/738_商城冷启动显隐修复.gil'));
const prefix='econ.shop736.';
const record=(tree,n)=>tree.byName.get(prefix+'s'+n);
const field=(obj,n)=>obj?.sub?.find(f=>f.field===n);
const component=(r,n)=>r.field.sub.filter(f=>f.field===505).map(f=>field(field(f,503),n)).find(Boolean);
const transforms=r=>field(component(r,13),12);
const states=r=>transforms(r).sub.filter(f=>f.field===501).map(f=>field(f,502));
const leaf=findScriptLeaf(g),original=leaf.buf.toString('utf8');
const lines=original.split('\n');
const nodeIndex=n=>lines.findIndex(l=>l.includes(`push({id='${prefix}s${n}',`));
const expected=new Map();
function shape(n,x,y,w,h,{angle,color}={}) {
  const r=record(g,n), blocks=states(r);assert.equal(blocks.length,4);
  for(const b of blocks){
    assert(setPair(pairOf(b,504),(x+w/2-960)*5/6,(540-y-h/2)*5/6));
    assert(setPair(pairOf(b,505),w*5/6,h*5/6));
    if(angle!==undefined){const rot=field(b,508);rot.sub=angle?[{field:3,wt:5,f:angle}]:[];rot.payload=null;rot.len=angle?5:0;}
  }
  if(color!==undefined)field(component(r,84),502).num=BigInt('0xff'+color);
  const i=nodeIndex(n);assert(i>=0 && /rect=\{[^}]+\}/.test(lines[i]));
  lines[i]=lines[i].replace(/rect=\{[^}]+\}/,`rect={x=${x},y=${y},w=${w},h=${h}}`);
  expected.set(n,{x,y,w,h,angle,color});
}
// 用普通居中控件的变换替代旧拉伸模板，避免运行时尺寸与存档锚点叠加。
transforms(record(g,0)).sub=transforms(record(g,148)).sub.map(cloneField);
for(const n of [0,148])shape(n,-1920,-1080,5760,3240);
// 45° 方块被主板及中央矩形覆盖，只露出两侧的三角形部分。
function shoulder(n,cx,tip,color){const radius=48,side=radius*Math.SQRT2;shape(n,cx-side/2,tip+radius-side/2,side,side,{angle:45,color});}
shoulder(39,570,52,'6D0701');shoulder(40,1350,52,'6D0701');
shoulder(41,572,57,'DA9347');shoulder(42,1348,57,'DA9347');
shape(3,570,52,780,54);shape(4,572,57,776,50);shape(5,570,102,780,15);
// 余下 22 段缝线围合四边，四角以斜线收口。
for(let i=0;i<8;i++)for(let j=0;j<2;j++)shape(43+2*i+j,1303+i*52,138+65*j,32,3);
for(const [n,x,y,angle] of [[59,1272,144,30],[60,1699,144,-30],[61,1272,198,-30],[62,1699,198,30]])shape(n,x,y,20,3,{angle});
shape(63,1270,160,3,22);shape(64,1723,160,3,22);
for(const [n,x] of [[108,150],[123,479]]){shape(n,x,208,298,219,{color:'F2C970'});shape(n+1,x,208,13,219,{color:'CB963F'});}
// 同步画布子项和 Lua 排列，金底在凹槽之上、货品和点击热区之下。
const root=g.recs.find(r=>r.id===record(g,0).parentId);
let order=asIdList(root.childList.payload,true).map(Number);
function before(numbers,anchor){
  const ids=numbers.map(n=>record(g,n).id),moved=numbers.map(n=>lines[nodeIndex(n)]);
  assert(ids.every(id=>order.includes(id)) && moved.every(Boolean));
  order=order.filter(id=>!ids.includes(id));const idx=order.indexOf(record(g,anchor).id);assert(idx>=0);order.splice(idx,0,...ids);
  for(const l of moved)lines.splice(lines.indexOf(l),1);lines.splice(nodeIndex(anchor),0,...moved);
}
before([1,3,39,40,41,42,4,2,5],6);before([108,109],13);before([123,124],16);
setChildList(root.childList,order);
const script=lines.join('\n').replaceAll('构建标记 v738 / 商城冷启动显隐修复','构建标记 v739 / 调查商城全屏与选中态');
leaf.field.payload=Buffer.from(script);
const cold=fileURLToPath(new URL('../tests/shop_cold_render.lua',import.meta.url));
function replay(file,bytes){const r=spawnSync('lua',[file],{input:bytes,encoding:'utf8'});assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout;}
fs.mkdirSync(path.dirname(out),{recursive:true});
// 验收通过再发布到最终路径。
const stage=process.argv[2];assert(stage && !fs.existsSync(stage));
writeGil(g,stage,{label:'739',expectMarker:'v739',assert:b=>{
 const bytes=findScriptLeaf(b).buf;assert(bytes.equals(leaf.field.payload));
 const near=(a,z)=>assert(Math.abs(a-z)<0.001,`${a} != ${z}`);
 for(const [n,{x,y,w,h,angle,color}] of expected){const r=record(b,n);for(const s of states(r)){
   const v=(f,i)=>pairValue(field(s,f),i);near(v(504,0),(x+w/2-960)*5/6);near(v(504,1),(540-y-h/2)*5/6);near(v(505,0),w*5/6);near(v(505,1),h*5/6);
   if(angle!==undefined)near(field(field(s,508),3)?.f??0,angle);
   if(n===0 || n===148){for(const i of [0,1])for(const f of [502,503,506])near(v(f,i),0.5);
     for(const [vw,vh] of [[1600,1200],[1920,1200],[1920,1080],[2520,1080],[5120,1440]]){const scale=Math.min(vw/1920,vh/1080)*6/5;assert(v(505,0)*scale>=vw && v(505,1)*scale>=vh);}}
 }if(color)assert.equal(field(component(r,84),502).num,BigInt('0xff'+color));}
 const savedOrder=asIdList(b.recs.find(r=>r.id===root.id).childList.payload,true).map(Number);assert.deepEqual(savedOrder,order);
 for(const r of b.recs)if(r.id!==root.id && !r.name?.startsWith(prefix))assert(r.field.payload.equals(g.recs.find(p=>p.id===r.id).field.payload),r.name);
 console.log(replay(cold,bytes).trim());console.log(replay(process.argv[3],bytes).trim());return true;
}});
fs.copyFileSync(stage,out,fs.constants.COPYFILE_EXCL);console.log(out);
