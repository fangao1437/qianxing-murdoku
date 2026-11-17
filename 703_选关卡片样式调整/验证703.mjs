import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..'),TMP='C:/Users/18182/AppData/Local/Temp/feibo/f5ba929b-7e85-4809-9b5c-d6eaf42d9989';
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilread.mjs')),W=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const g=R.readGil(DIR+'/703_选关卡片样式调整.gil'),base=R.readGil(DIR+'/../702_选关渲染修复/702_选关渲染修复_v2.gil'),lua=W.findScriptLeaf(g).buf.toString('utf8'),checks=[];
const ck=(name,pass,detail='')=>checks.push({name,pass:!!pass,detail});
const at=(f,ns)=>ns.reduce((x,n)=>x?.sub?.find(y=>y.field===n&&y.wt===2),f),hidden=r=>r.field.sub.some(f=>f.field===505&&at(f,[503,14,17])?.sub?.some(x=>x.field===503&&x.wt===0));
const pool=g.recs.find(r=>r.name==='select.thumb.pool'),order=R.asIdList(pool.childList.payload,true);
ck('记录数8300且仅新增四底板',g.recs.length===base.recs.length+4&&g.recs.length===8300);
const bm=new Map(base.recs.map(r=>[r.id,r]));const unchanged=g.recs.filter(r=>bm.has(r.id)&&R.encodeMsg([r.field]).equals(R.encodeMsg([bm.get(r.id).field])));ck('8011条旧控件逐字节保留',unchanged.length===8011,unchanged.length);
const content=g.recs.filter(r=>/^select\.card\.\d+\.(boardbg|cell\.|wall\.|door\.)/.test(r.name||''));
ck('288图元全部使用cell模板矩形100001',content.length===288&&content.every(r=>{const f=r.field.sub.find(f=>f.field===505&&f.sub?.some(x=>x.field===502&&x.num===96n));return at(f,[503,84])?.sub?.find(f=>f.field===503)?.num===100001n}));
const nonfinite=[];for(const r of content){function walk(f){if(f.wt===5&&!Number.isFinite(f.f))nonfinite.push(r.name);for(const c of f.sub||[])walk(c)}walk(r.field)}ck('288图元无非有限浮点参数',nonfinite.length===0,nonfinite.slice(0,5));
for(let i=1;i<=4;i++){const b=g.recs.find(r=>r.name==='select.card.'+i+'.boardbg'),cells=g.recs.filter(r=>r.name?.startsWith('select.card.'+i+'.cell.'));ck('卡'+i+'底板同父级且在格子之前',b.parentId===pool.id&&hidden(b)&&cells.every(c=>order.indexOf(b.id)<order.indexOf(c.id)));}
ck('内嵌Lua与通用客户端和交付副本一致',lua===fs.readFileSync(DIR+'/../dist/client_script.lua','utf8')&&lua===fs.readFileSync(DIR+'/703_内嵌Lua_703.lua','utf8'));
const value=v=>Number.isFinite(v)?String(v):'(0/0)';
const fixture='local fixtures={\n'+g.recs.map(r=>{const st=R.stateBlocks(r.field.sub,[])[0],p=st?R.pairOf(st,504):null,z=st?R.pairOf(st,505):null;return `{id=${r.id},name=${JSON.stringify(r.name||'')},parent=${r.parentId||'nil'},kids={${r.childList?(R.asIdList(r.childList.payload,true)||[]).join(','):''}},x=${value(p?R.pairValue(p,0):0)},y=${value(p?R.pairValue(p,1):0)},w=${value(z?R.pairValue(z,0):1)},h=${value(z?R.pairValue(z,1):1)},visible=${!hidden(r)}},`}).join('\n')+'\n}\n';
let old=fs.readFileSync(DIR+'/../698_首页与缩略图修复/验证698.mjs','utf8'),h=old.split('const harness=`')[1].split('\n`;')[0].replaceAll('\\\\','\\');h=h.slice(0,h.indexOf(' -- 原始回放：')).replace('local o=objects[r.id]\n for _,id','local o=objects[r.id]\n o.parent=objects[r.parent]\n for _,id');
h=h.replace('function o:SetLocalScale() end',`function o:SetLocalScale(x,y,z) self.sx,self.sy,self.sz=x,y,z end
 function o:GetLocalScale() return self.sx or 1,self.sy or 1,self.sz or 1 end
 function o:GetAnchorMin() return table.unpack(self.amin or {.5,.5}) end
 function o:GetAnchorMax() return table.unpack(self.amax or {.5,.5}) end
 function o:GetPivot() return table.unpack(self.pivot or {.5,.5}) end`);
h=h.replace(' Enum={CursorEventType={CursorClick=1,CursorDown=2,CursorUp=3,CursorDrag=4}}',' Enum={CursorEventType={CursorClick=1,CursorDown=2,CursorUp=3,CursorDrag=4},TextHorizontalAlignment={Middle=1},TextVerticalAlignment={Middle=1}}');
const probe=`
local function effective(o) if not o then return false end;while o do if not o.visible or not o.active then return false end;o=o.parent end;return true end
local function near(x,y) return math.abs(x-y)<.01 end
local a=newAdapter();local u=newUI();u:render(a,true)
ck('首页弹窗父级关闭',not effective(byname.modal))
for _,p in ipairs({1,2,1}) do
 u.screen='select';u.select_page=p;u:render(a,true)
 for k=1,3 do a:on_tick(.2);u:tick(.2);u:render(a,false) end
 local plan={};for _,n in ipairs(u:build_layout(a)) do plan[n.id]=n end
 for slot=1,4 do
  local it=list[(p-1)*4+slot];local prefix='select.card.'..slot;local label=byname[prefix..'.info'];local bg=byname[prefix..'.boardbg']
  if it then
   local card=plan[prefix].rect;local br=plan[prefix..'.boardbg'].rect;local ir=plan[prefix..'.info'].rect
   ck('页'..p..'卡'..slot..'完整案件标题',effective(label) and label.text==it.name and utf8.len(label.text)~=nil,label.text)
   ck('页'..p..'卡'..slot..'取消顶部规格',not effective(byname[prefix..'.title']))
   ck('页'..p..'卡'..slot..'标题底部白边且居中',ir.y>=card.y+card.h*.88 and ir.y+ir.h<=card.y+card.h and near(ir.x+ir.w*.5,card.x+card.w*.5) and label.horizontalAlignment==1 and label.verticalAlignment==1)
   ck('页'..p..'卡'..slot..'底板正方形居中',effective(bg) and bg.imageId==100001 and bg.imageColor==4281871675 and near(br.w,br.h) and near(br.x+br.w*.5,card.x+card.w*.5) and near(br.y+br.h*.5,card.y+card.h*.5))
   local count,ok=0,true;local minx,miny,maxx,maxy=1e9,1e9,-1e9,-1e9
   for r=1,it.size.rows do for c=1,it.size.cols do local id=prefix..'.cell.'..r..'.'..c;local n=plan[id];local o=byname[id];local z=n.rect;count=count+1;ok=ok and effective(o) and o.imageId==100001 and not o.raycastTarget and near(z.w,z.h) and o.w>1 and o.h>1;minx=math.min(minx,z.x);miny=math.min(miny,z.y);maxx=math.max(maxx,z.x+z.w);maxy=math.max(maxy,z.y+z.h) end end
   ck('页'..p..'卡'..slot..'全部正方形纯色格子',ok,count)
   ck('页'..p..'卡'..slot..'棋盘中心与卡中心重合',near((minx+maxx)*.5,card.x+card.w*.5) and near((miny+maxy)*.5,card.y+card.h*.5))
   ck('页'..p..'卡'..slot..'底板四边外扩对称',br.x<minx and br.y<miny and br.x+br.w>maxx and br.y+br.h>maxy and near(minx-br.x,br.x+br.w-maxx) and near(miny-br.y,br.y+br.h-maxy))
   local key=a.event_latest['hit.'..prefix];local ev=key and a.events[key];ck('页'..p..'卡'..slot..'点击映射正确',ev and ev.id==it.id)
  else
   local all=not effective(bg) and not effective(label) and not effective(byname[prefix]);for _,s in ipairs(UI.Controller.THUMB_POOL)do all=all and not effective(byname[prefix..s]) end
   ck('末页空卡无内容残留',all)
  end
 end
end
u:on_input({action='home'});u:render(a,true);ck('返回首页关闭缩略图父级和标题',not effective(byname['select.thumb.pool']) and not effective(byname['select.card.1.info']))
local T=__require('tutorial_ui');for _,tag in ipairs({'home','l1','l2'}) do local t=T.new(a,{tag=tag,pages=tag=='home' and 1 or tag=='l1' and 8 or 4});t:init();t:open_ui();local close=byname['td.'..tag..'.btn.close'];ck('教程按钮绑定/'..tag,t.inited and close.callback~=nil);if close.callback then close.callback() end;ck('教程关闭/'..tag,not t.open and not byname['td.'..tag].visible)end
ck('零自动创建控件',spawns==0,spawns)
print('METRIC\\tindexBuilds\\t'..tostring(a._name_idx_builds))
`;
const file=TMP+'/703-replay.lua';fs.writeFileSync(file,lua.slice(0,lua.indexOf('local FORCE_LEVEL = nil'))+fixture+h+probe);
let out='';try{out=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[file],{encoding:'utf8',timeout:60000,maxBuffer:4000000});}catch(e){out=String(e.stdout||'');ck('回放执行',false,String(e.stderr||e.message))}
const metrics={};for(const line of out.split(/\r?\n/)){if(line.startsWith('CHECK\t')){const[,n,p,...d]=line.split('\t');ck(n,p==='true',d.join('\t'))}if(line.startsWith('METRIC\t')){const[,k,v]=line.split('\t');metrics[k]=v;}}
ck('实际运行产生足量检查',checks.length>80,checks.length);
function split(s){const ms=[...s.matchAll(/^__M\["([\w.]+)"\] = function\(\)\r?\n/gm)],e=s.indexOf('local FORCE_LEVEL = nil'),map=new Map();for(let i=0;i<ms.length;i++){let p=s.slice(ms[i].index+ms[i][0].length,i+1<ms.length?ms[i+1].index:e).replace(/\n-- ==== 入口：官方生命周期回调[^\n]*\s*$/,'').trimEnd();assert(p.endsWith('\nend'));map.set(ms[i][1],p.slice(0,-4).trimEnd())}return map;}
const N=split(lua),B=split(W.findScriptLeaf(base).buf.toString('utf8')),canon=s=>s.replace(/=\s*(?:__)?require\s*\(/g,'= __require(').replace(/pcall\s*\(\s*(?:__)?require/g,'pcall(__require').trimEnd();
for(const[name,body]of N){const fp=DIR+'/../lua/'+name.replaceAll('.','/')+'.lua';ck(name+'源码同步',canon(fs.readFileSync(fp,'utf8'))===canon(body));if(!['ui_controller','engine_adapter_qianxing'].includes(name))ck(name+'与702保持一致',body===B.get(name));execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',fp],{timeout:10000});}
execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',DIR+'/703_内嵌Lua_703.lua'],{timeout:10000});ck('模块及完整脚本语法',true);
const behaviorProbe=fs.readFileSync(DIR+'/../697_凹角内收与缩略图居中/验证697行为.mjs','utf8').split('const PROBE = `')[1].split('`;')[0];
function behavior(s,v){const f=TMP+'/703-behavior-'+v+'.lua';fs.writeFileSync(f,s.slice(0,s.indexOf('local FORCE_LEVEL = nil'))+behaviorProbe);return execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[f],{encoding:'utf8',timeout:45000}).split(/\r?\n/).filter(l=>/^(SPAWN|SPY|BEHAVIOR):/.test(l));}
ck('七关谜题家具地毯行为保持',JSON.stringify(behavior(lua,703))===JSON.stringify(behavior(W.findScriptLeaf(base).buf.toString('utf8'),702)));
const result={version:703,total:checks.length,pass:checks.filter(c=>c.pass).length,fail:checks.filter(c=>!c.pass).length,metrics,checks,limits:['真实存档父链与实际Lua控制器/适配器回放，控件API为模拟','未操作游戏，未验证实机像素或真实鼠标输入','没有与截图逐像素比较；本轮交付为gil而非网页']};fs.writeFileSync(DIR+'/703_验证结果.json',JSON.stringify(result,null,2));console.log(JSON.stringify({pass:result.pass,total:result.total,fail:result.fail,metrics,failed:checks.filter(c=>!c.pass)},null,2));assert.equal(result.fail,0);
