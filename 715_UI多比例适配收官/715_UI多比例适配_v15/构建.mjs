import fs from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {readGil,encodeMsg,pairOf,pairValue} from '../qianxing-murdoku/tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf} from '../qianxing-murdoku/tools/gil/gilwrite.mjs';
const file=v=>fileURLToPath(new URL(`../715_UI多比例适配_v${v}.gil`,import.meta.url));
assert(!fs.existsSync(file(15)),'v15 已存在');
const g=readGil(file(14)), leaf=findScriptLeaf(g);
let lua=leaf.buf.toString();
function patch(a,b){assert.equal(lua.split(a).length,2,String(a).slice(0,100));lua=lua.replace(a,()=>b);}
const byName=new Map(g.recs.map(r=>[r.name,r]));
function states(name){return [505,503,13,12,501,502].reduce((rows,k)=>rows.flatMap(f=>(f.sub||[]).filter(x=>x.field===k)),[byName.get(name).field]);}
function rect(name){const rows=states(name).map(s=>[504,505].flatMap(k=>[0,1].map(i=>pairValue(pairOf(s,k),i))));assert.equal(rows.length,4);for(const r of rows)assert.deepEqual(r,rows[0]);return rows[0];}
// 取暖色板与四条描边内缘的交集，额外内收两个单位避免纹理采样露缝。
const [cx,cy,bw,bh]=rect('art647.select.board.warm');
const borders=['left','right','bottom','top'].map(n=>rect('art647.select.border.'+n));
const [L,R,B,T]=borders;
const x0=Math.max(cx-bw/2,L[0]+L[2]/2)+2,x1=Math.min(cx+bw/2,R[0]-R[2]/2)-2;
const y0=Math.max(cy-bh/2,B[1]+B[3]/2)+2,y1=Math.min(cy+bh/2,T[1]-T[3]/2)-2;
assert(x1>x0&&y1>y0);
patch('local function adapt14_background(w,h,transform)','local function adapt14_background(w,h,transform,slot)');
patch("  transform('art642.select.backdrop',0,0,math.max((w+4)/1600,(h+4)/900))",`  if slot==1 or slot==3 then
    local s=math.max((w+4)/${x1-x0},(h+4)/${y1-y0})
    transform('art642.select.backdrop',${-(x0+x1)/2}*s,${-(y0+y1)/2}*s,s)
  else
    transform('art642.select.backdrop',0,0,math.max((w+4)/1600,(h+4)/900))
  end`);
patch('local scene,shift=adapt14_background(w,h,transform)','local scene,shift=adapt14_background(w,h,transform,slot)');
// 相纸原图元已挂在背景下，移除 v14 的逆缩放即可继承同一世界变换。
const photoStart=lua.indexOf('local PHOTO14='),photoEnd=lua.indexOf('local function adapt14_corner',photoStart);
assert(photoStart>0&&photoEnd>photoStart);
patch(lua.slice(photoStart,photoEnd),'');
patch('adapt14_photo(find,transform,scene,shift,1,page)',"transform('adapt715r.WAX.12',0,shift,scene)");
const buttonRows=['adapt715r.TL.2','adapt715r.TR.3','adapt715r.TL.5','adapt715r.TR.6','adapt715r.TL.9','adapt715r.TR.10','adapt715r.TL.21','select.back','hit.select.back',...['back','submit','redo','undo'].flatMap(n=>['hex.'+n,'hit.'+n])];
for(const name of buttonRows){
  const row=lua.split('\n').find(s=>s.startsWith(`  {name="${name}",kind=`));assert(row,name);
  let count=0;const next=row.replace(/\[([13])\]=\{([^,]+),([-\d.]+)\}/g,(_,slot,x,y)=>{count++;return `[${slot}]={${x},${Number(y)-20}}`;});
  assert.equal(count,2,name);patch(row,next);
}
patch('[adapt715-v14]','[adapt715-v15]');patch('v14 分层铺满与美术裁切','v15 移动选关满幅与装饰同步');
const compile=spawnSync('lua',['-e','assert(load(io.read("*a")))'],{input:lua,encoding:'utf8'});assert.equal(compile.status,0,compile.stderr);
leaf.field.payload=Buffer.from(lua);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
const original=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
writeGil(g,file(15),{expectRecs:8430,expectDiffs:1,expectMarker:'v715',quiet:true,assert:r=>{
  assert(findScriptLeaf(r).buf.equals(Buffer.from(lua)));assert(r.trailer.equals(g.trailer));
  for(const row of r.recs)assert(original.get(row.id).equals(encodeMsg([row.field])));return true;
}});
console.log('输出 v15，逐条对照记录',original.size,'；选关有效边界',x0,x1,y0,y1,'；下移的美术组和交互节点',buttonRows.length);
