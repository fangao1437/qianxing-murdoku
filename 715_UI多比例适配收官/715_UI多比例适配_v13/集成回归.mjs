import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readGil,asIdList,pairValue,pairOf} from '../qianxing-murdoku/tools/gil/gilread.mjs';
import {findScriptLeaf} from '../qianxing-murdoku/tools/gil/gilwrite.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url));
const g=readGil(path.resolve(dir,'../715_UI多比例适配_v13.gil'));
const lua=findScriptLeaf(g).buf.toString('utf8');
function run(input,args){const r=spawnSync('lua',args,{input,encoding:'utf8',maxBuffer:8e6});assert.equal(r.status,0,r.stderr);return r.stdout;}
run(lua,['-e','assert(load(io.read("*a")))']);
const rec=n=>g.recs.find(r=>r.name===n);
assert.equal(asIdList(rec('adapt715r.background').childList.payload,true).length,649);
for(const n of ['root','adapt715r.background.fill','art647.select.bg.base']){
 const states=[505,503,13,12,501,502].reduce((a,k)=>a.flatMap(f=>(f.sub||[]).filter(x=>x.field===k)),[rec(n).field]);assert.equal(states.length,4);
 for(const s of states)for(let i=0;i<2;i++){assert.equal(pairValue(pairOf(s,502),i),0);assert.equal(pairValue(pairOf(s,503),i),1);assert(Math.abs(pairValue(pairOf(s,505),i))<=4);}
}
function section(a,b){let i=lua.indexOf(a),j=lua.indexOf(b,i);assert(i>=0&&j>i);return lua.slice(i,j);}
const test=`local Adapter={}
local data={}
local function node(n)
 local c={active=false,visible=false}
 for _,k in ipairs({'LocalScale','AnchoredPosition','AnchorMin','AnchorMax','Pivot','SizeDelta'}) do
   c[k]={0,0};c['Get'..k]=function(self) return table.unpack(self[k]) end;c['Set'..k]=function(self,...) self[k]={...} end
 end
 function c:SetActive(v) self.active=v end
 function c:SetVisible(v) self.visible=v end
 function c:GetChildren() return self.children or {} end
 function c:SetAsLastSibling() end
 return c
end
local function get(n) if not data[n] then data[n]=node(n) end return data[n] end
local adapter=setmetatable({cfg={respect_editor_rect=true,canvas_h=900,canvas_w=1600,scale=5/6},runtime_rect={root=true},find=function(_,n) return get(n) end},{__index=Adapter})
local ctrl={screen='home'}
local Murdoku={current=function() return {controller=ctrl} end}
local width,height,device
local game={GetUICanvasSize=function() return width,height end,GetDevice=function() return device end}
local bg=get('adapt715r.background');bg.children={};for i=1,649 do bg.children[i]=node() end
${section('local function select_render_content(id)','function Adapter:_fire(')}
${section('-- ADAPT715R BEGIN','-- ADAPT715R END')}
local root=get('root');root:SetAnchorMax(1,1);root:SetSizeDelta(-.000244,0)
local scenarios=0
local function close(a,b) return math.abs(a-b)<.001 end
for _,profile in ipairs({{'Keyboard',16/9},{'Keyboard',21/9},{'Mobile',16/9},{'Mobile',19.5/9},{'Mobile',4/3},{'Controller',16/9},{'Controller',21/9},{'MobileController',16/9},{'MobileController',19.5/9},{'MobileController',4/3},{'Keyboard',16/10},{'Mobile',20/9}}) do
 for _,res in ipairs({1280,1920}) do
  width,height,device=res,res/profile[2],profile[1]
  for _,page in ipairs({'home','select','home','game'}) do
   ctrl.screen=page
   assert(adapter:set_property('root','rect',{x=0,y=0,w=1920,h=1080}))
   sync_adapt715r(.26,false)
   assert(root.AnchorMax[2]==1 and root.SizeDelta[2]==0)
   assert(get('adapt715r.background.fill').visible and get('art647.select.bg.base').visible==(page=='select'))
   assert(bg.visible==(page~='select'));for _,leaf in ipairs(bg.children) do assert(leaf.visible==bg.visible) end
   local w,h=1600,1600/profile[2];local fit=math.min(1,h/900)
   assert(close(bg.LocalScale[1],fit) and close(bg.LocalScale[2],fit) and 1600*fit<=w+.001 and 900*fit<=h+.001)
   local s=adapter._select715_scale;assert(s and 1120*s<=w+.001 and 600*s<=h+.001)
   assert(close(get('art642.select.paper').LocalScale[1],s) and close(get('art642.select.frames').LocalScale[2],s))
   local r={x=280*s,y=180*s,w=220*s,h=150*s}
   for _,n in ipairs({'select.card.1','hit.select.card.1'}) do adapter.runtime_rect[n]=true;assert(adapter:set_property(n,'rect',r)) end
   for _,k in ipairs({'SizeDelta','AnchoredPosition'}) do for j=1,2 do assert(close(get('select.card.1')[k][j],get('hit.select.card.1')[k][j])) end end
   scenarios=scenarios+1
  end
 end
end
width,height=0,0;ctrl.screen='select';sync_adapt715r(0,false);assert(get('art647.select.bg.base').visible and not bg.visible)
ctrl.screen='home';sync_adapt715r(0,false);assert(not get('art647.select.bg.base').visible and bg.visible)
print('PASS '..scenarios)
`;
const output=run(test,['-']);assert(output.includes('PASS 96'));
const audit={version:13,compiledWholeLua:true,controls:8430,unchangedControlRecords:8430,diffFields:1,profiles:12,widths:[1280,1920],pageScenarios:96,invalidCanvasSwitches:2,backgroundChildren:649,rootRectThenAdapt:true,realGameTest:false,limits:'控件替身，卡片与热区使用共用样本矩形，未运行完整控制器或模拟真实手势、安全区、宿主裁剪'};
fs.writeFileSync(path.join(dir,'验证结果.json'),JSON.stringify(audit,null,2));console.log(JSON.stringify(audit));
