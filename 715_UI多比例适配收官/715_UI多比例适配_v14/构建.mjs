import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, pairValue, pairOf } from '../qianxing-murdoku/tools/gil/gilread.mjs';
import { findScriptLeaf, writeGil } from '../qianxing-murdoku/tools/gil/gilwrite.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url));
const g=readGil(path.join(dir,'../715_UI多比例适配_v13.gil'));
const out=path.join(dir,'../715_UI多比例适配_v14.gil');
assert(!fs.existsSync(out),'同名输出已存在');
const leaf=findScriptLeaf(g), original=leaf.buf.toString('utf8');
const first=original.indexOf('-- ADAPT715R BEGIN'),last=original.indexOf('-- ADAPT715R END',first);
assert(first>0 && last>first);
let adapt=original.slice(first,last);
function patch(a,b){assert.equal(adapt.split(a).length,2,a);adapt=adapt.replace(a,()=>b);}
const recs=new Map(g.recs.map(r=>[r.name,r]));
const rows=[];
for(let i=640;i<=649;i++){
  const r=recs.get(`adapt715r.background.part.${i}`);assert.equal(r.parentId,recs.get('adapt715r.background').id);
  assert(original.includes('["'+r.name+'"]'));
  const states=[505,503,13,12,501,502].reduce((a,k)=>a.flatMap(f=>(f.sub||[]).filter(v=>v.field===k)),[r.field]);
  assert.equal(states.length,4);
  const all=states.map(s=>{const scale=pairOf(s,501).sub.map(f=>f.f);assert.deepEqual(scale,[1,1,1]);return [0,1].map(j=>pairValue(pairOf(s,504),j));});
  all.forEach(p=>assert.deepEqual(p,all[0]));rows.push(`  {${JSON.stringify(r.name)},${all[0].join(',')},1},`);
}
const helpers=fs.readFileSync(path.join(dir,'适配运行时.lua'),'utf8').replace('-- PHOTO_ROWS',()=> '\n'+rows.join('\n'));
patch('local function sync_adapt715r(dt,force)',helpers+'\nlocal function sync_adapt715r(dt,force)');
patch('local cardScale=math.min(math.max(w/1600,h/900),w/1120,h/600)','local cardScale=adapt14_cards(w,h)');
patch("  transform('adapt715r.background',0,0,fit)\n  transform('art642.select.backdrop',0,0,fit)","  local scene,shift=adapt14_background(w,h,transform)");
patch("  transform('art642.select.board',0,0,1)","  adapt14_photo(find,transform,scene,shift,1,page)\n  adapt14_pagers(find,transform,w)\n  transform('art642.select.board',0,0,1)");
patch("transform(v.name,sign*(cw-1600*fit)/2,sign*(ch-900*fit)/2,fit)","transform(v.name,adapt14_corner(w,h,v.side))");
patch('[adapt715-v13]','[adapt715-v14]');patch("' art='..fit","' scene='..scene");
const lua=original.slice(0,first)+adapt+original.slice(last);
const script=lua.replace('v13 四边延展与完整主画','v14 分层铺满与美术裁切');assert.notEqual(lua,script);
const compile=spawnSync('lua',['-e','assert(load(io.read("*a")))'],{input:script,encoding:'utf8'});assert.equal(compile.status,0,compile.stderr);
leaf.field.payload=Buffer.from(script);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
const records=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
writeGil(g,out,{expectRecs:8430,expectDiffs:1,expectMarker:'v715',quiet:true,assert:r=>{
  assert(findScriptLeaf(r).buf.equals(Buffer.from(script)));assert(r.trailer.equals(g.trailer));
  for(const row of r.recs)assert(records.get(row.id).equals(encodeMsg([row.field])));return true;
}});
console.log('记录数',records.size,'字段差异',1,'输出 SHA256',createHash('sha256').update(fs.readFileSync(out)).digest('hex'));
