import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg,pairOf,pairValue} from '../qianxing-murdoku/tools/gil/gilread.mjs';
import {findScriptLeaf,writeGil} from '../qianxing-murdoku/tools/gil/gilwrite.mjs';
const file=v=>fileURLToPath(new URL(`../715_UI多比例适配_v${v}.gil`,import.meta.url));
const g=readGil(file(15)),leaf=findScriptLeaf(g);
let lua=leaf.buf.toString();
const byId=new Map(g.recs.map(r=>[r.id,r])),byName=new Map(g.recs.map(r=>[r.name,r]));
function states(r){return [505,503,13,12,501,502].reduce((rows,k)=>rows.flatMap(f=>(f.sub||[]).filter(x=>x.field===k)),[r.field]);}
function rect(s){return [504,505].flatMap(k=>[0,1].map(i=>pairValue(pairOf(s,k),i)));}
if(process.argv.includes('--layers')){
 for(const r of g.recs){const p=byId.get(r.parentId)?.name||'';if(!(/art642\.select\.(frames|paper)$/.test(p)||/^select\.card\.\d$|^hit\.select\.card\.\d$/.test(r.name)))continue;console.log(p,r.name,rect(states(r)[0]).map(n=>+n.toFixed(2)).join(','));}
 const lines=lua.split('\n');for(const [i,l] of lines.entries())if(/_select715_scale|ADAPT715R_TEARS =|local function .*select.*rect|local .*CARD_X|local .*CARD_CX/.test(l))console.log(i+1,lines.slice(i,i+7).join('\n'));
 process.exit(0);
}
const retry=process.argv.includes('--replace-candidate');
if(fs.existsSync(file(16)))assert(retry,'v16 已存在');
const papers=[1,2,3,4].map(i=>byName.get(`art647.select.card.${i}.paper`));
const changed=new Set();
for(let slot=0;slot<4;slot++){
 const boxes=papers.map(r=>rect(states(r)[slot]));
 const span=boxes[3][0]+boxes[3][2]/2-boxes[0][0]+boxes[0][2]/2;
 const gap=(span-boxes.reduce((sum,b)=>sum+b[2],0))/3;
 let edge=-span/2;
 for(const [index,[oldX,,width]] of boxes.entries()){
  const i=index+1, center=edge+width/2, dx=center-oldX;
  for(const name of [`art647.select.kraft.${i}`,`art647.select.kraft.${i}.rule`,`art647.select.card.shadow.${i}`,...['paper','opening','opening.border','tab'].map(s=>`art647.select.card.${i}.${s}`),`select.card.${i}`,`hit.select.card.${i}`]){
   const r=byName.get(name),x=pairOf(states(r)[slot],504).sub.find(f=>f.field===501&&f.wt===5);
   x.f=Math.fround(name.startsWith('art647.')?x.f+dx:center);changed.add(r.id);
  }
  edge+=width+gap;
 }
}
assert.equal(changed.size,36);
function patch(before,after){assert.equal(lua.split(before).length,2,before);lua=lua.replace(before,()=>after);}
patch('return sign*(w-1600*scale)/2,sign*(h-900*scale)/2,scale',`local wide=math.min(1,math.max(0,(9*w/h-16)/4))
  local inset=wide*scale
  local ix=side=='tr' and 2 or 16
  local iy=side=='tr' and 12 or 2
  return sign*((w-1600*scale)/2-ix*inset),sign*((h-900*scale)/2-iy*inset),scale`);
patch('[adapt715-v15]','[adapt715-v16]');patch('v15 移动选关满幅与装饰同步','v16 选关四卡等距居中与长屏撕边');
function run(code){const p=spawnSync('lua',['-'],{input:code,encoding:'utf8'});assert.equal(p.status,0,p.stderr);return p.stdout;}
const compiler=spawnSync('lua',['-e','assert(load(io.read("*a")))'],{input:lua,encoding:'utf8'});assert.equal(compiler.status,0,compiler.stderr);
leaf.field.payload=Buffer.from(lua);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
if(retry){const prior=readGil(file(16));const previous=lua.replace(/  local ix=side=='tr' and 2 or 16\n  local iy=side=='tr' and 12 or 2\n  return sign\*\(\(w-1600\*scale\)\/2-ix\*inset\),sign\*\(\(h-900\*scale\)\/2-iy\*inset\),scale/, '  return sign*((w-1600*scale)/2-16*inset),sign*((h-900*scale)/2-12*inset),scale');assert.notEqual(previous,lua);assert.equal(findScriptLeaf(prior).buf.toString(),previous);assert.equal(prior.recs.length,expected.size);for(const r of prior.recs)assert(expected.get(r.id).equals(encodeMsg([r.field])));}
const report=writeGil(g,file(16),{expectRecs:8430,expectMarker:'v715',quiet:true,assert:r=>{
 assert(findScriptLeaf(r).buf.equals(Buffer.from(lua)));assert(r.trailer.equals(g.trailer));for(const rec of r.recs)assert(expected.get(rec.id).equals(encodeMsg([rec.field])));return true;
}});
const saved=report.g2.recs,embedded=findScriptLeaf(report.g2).buf.toString().replace(/\r/g,'');
const slice=(start,end)=>{const a=embedded.indexOf(start),b=embedded.indexOf(end,a+1);assert(a>=0&&b>a,start);return embedded.slice(a,b);};
const names=new Map(saved.map(r=>[r.name,r]));const matrix=Array.from({length:4},(_,slot)=>papers.map(r=>'{'+rect(states(names.get(r.name))[slot]).join(',')+'}'));
const layout=slice('        local CARD_W, CARD_H = 279, 388.8','    end\n    local show_settle');
const corners=saved.filter(r=>/^art651\.select\.tear\.(tr|bl)\.paper\./.test(r.name));assert(corners.length>2);
const tearData=corners.map(r=>`{'${r.name.includes('.tr.')?'tr':'bl'}',${rect(states(r)[0]).join(',')}}`);
console.log(run(`local Controller={}; local print0=print; local print=nil
${slice('function Controller:editor_card_box','function Controller:push_room_thumb')}
${slice('local function adapt14_corner','local function adapt14_pagers')}
local matrix={${matrix.map(a=>'{'+a.join(',')+'}').join(',')}}
local tears={${tearData.join(',')}}
local near=function(x,y) assert(math.abs(x-y)<.001,tostring(x)..' vs '..tostring(y)) end
local n=0
for _,ratio in ipairs({4/3,16/9,19.5/9,20/9,21/9}) do
 local w,h=1600,1600/ratio; local k=adapt14_cards(w,h)
 for _,side in ipairs({'tr','bl'}) do
  local x,y,s=adapt14_corner(w,h,side);local sg=side=='tr' and 1 or -1
  local oldX,oldY=sg*(w-1600*s)/2,sg*(h-900*s)/2
  if ratio<=16/9 then near(x,oldX);near(y,oldY) else assert(sg*(oldX-x)>0 and sg*(oldY-y)>0) end
  local xe,ye,inside=0,0,false
  for _,t in ipairs(tears) do if t[1]==side then local a,b=sg*x+sg*t[2]*s,sg*y+sg*t[3]*s;xe=math.max(xe,a+t[4]*s/2);ye=math.max(ye,b+t[5]*s/2);if a<w/2 and b<h/2 and a>0 and b>0 then inside=true end end end
  assert(xe>=w/2 and ye>=h/2 and inside,'纸边未同时跨边并进入画内')
 end
 for _,boxes in ipairs(matrix) do
  local ui_adapter={cfg={scale=5/6,canvas_w=1600,canvas_h=900},_select715_scale=k}
  function ui_adapter:find(name)
   local idx=tonumber(name:match('art647%.select%.card%.(%d+)%.paper'))
   local b=idx and boxes[idx] or {0,0,1600,900};local ps=name=='art642.select.frames' and k or 1
   return {GetSizeDelta=function() return b[3],b[4] end,GetAnchoredPosition=function() return b[1],b[2] end,GetLocalScale=function() return ps,ps end}
  end
  for _,lst_base in ipairs({0,4,0}) do
   local self=Controller;local PER=4;local list={};for i=1,7 do list[i]={id=i} end
   function self:level_card_parts(it)return {short=tostring(it.id),result=''} end
   local thumbs={};function self:push_room_thumb(_,id,it,b) if it then thumbs[id]=b end end
   local nodes={};local function push(p) nodes[p.id]=p end
${layout}
   local gaps={};local prev,last,left
   for i,b in ipairs(boxes) do
    local id='select.card.'..i;local node=nodes[id];local hit=nodes['hit.'..id];local r=node.rect
    local L=r.x*5/6;last=(r.x+r.w)*5/6;if prev then gaps[#gaps+1]=L-prev else left=L end;prev=last
    near((L+last)/2,800+b[1]*k);assert(hit.visible==(lst_base+i<=7));if hit.visible then assert(hit.rect==r and hit.event.id==lst_base+i and thumbs[id]==r);local t=nodes[id..'.info'];near(t.rect.x+t.rect.w/2,r.x+r.w/2);assert(t.text==tostring(lst_base+i)) end
   end
   near(left,1600-last);near(gaps[1],gaps[2]);near(gaps[2],gaps[3]);n=n+1
  end
 end
end
print0('五种比例、四端状态、首页→尾页→首页，布局检查通过 '..n..' 次')`));
console.log('v16 已回读，记录',saved.length,'差异字段',report.diffs,'选关基准净间距',(rect(states(papers[1])[0])[0]-rect(states(papers[0])[0])[0]-200).toFixed(3));
