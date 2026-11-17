// 从磁盘.gil重建控件树，运行真实控制器/适配器；不以生成布局代替真实控件覆盖。
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const TMP='C:/Users/18182/AppData/Local/Temp/feibo/dc8b3f22-b61a-4842-b219-754f2e124c5d/698-repair';
fs.mkdirSync(TMP,{recursive:true});
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(DIR,'698_首页与缩略图修复.gil');
const basePath=path.join(DIR,'../697_凹角内收与缩略图居中/697_凹角内收与缩略图居中.gil');
const g=R.readGil(input),base=R.readGil(basePath),lua=W.findScriptLeaf(g).buf.toString('utf8');
const checks=[];const ck=(name,ok,detail='')=>checks.push({name,pass:!!ok,detail});
const root=g.recs.find(r=>r.name==='root');
const baseIds=new Map(base.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const added=g.recs.filter(r=>!baseIds.has(r.id));
const changed=g.recs.filter(r=>baseIds.has(r.id)&&!baseIds.get(r.id).equals(R.encodeMsg([r.field])));
ck('已有8010条非root控件逐字节保持',changed.length===1&&changed[0].name==='root',changed.map(r=>r.name));
ck('没有删除旧控件',base.recs.every(r=>g.recs.some(t=>t.id===r.id)));
ck('新增控件284条',added.length===284,added.length);
ck('内嵌Lua等于交付副本',W.findScriptLeaf(g).buf.equals(fs.readFileSync(path.join(DIR,'698_内嵌Lua_698.lua'))));
ck('完整存档编码往返一致',R.encodeMsg(g.tree).equals(g.src.subarray(20,20+g.hdr[4])));
ck('构建标记v698',W.markerOf(lua)==='v698');
function at(f,nums){return nums.reduce((x,n)=>x?.sub?.find(y=>y.field===n&&y.wt===2),f)}
function hidden(r){return r.field.sub.some(f=>f.field===505&&at(f,[503,14,17])?.sub?.some(x=>x.field===503&&x.wt===0));}
const rootKids=R.asIdList(root.childList.payload,true);
ck('控件池真实父级与子列表一一对应',added.every(r=>r.parentId===root.id&&rootKids.filter(id=>id===r.id).length===1));
ck('控件池名字唯一',added.every(r=>g.recs.filter(t=>t.name===r.name).length===1));
ck('控件池默认全部隐藏',added.every(hidden));
ck('控件池没有子控件和旧原型回指',added.every(r=>!r.childList&&r.field.sub.some(f=>f.field===501&&Number(f.num)===r.id)));
for(const card of [1,2,3,4]){
 const rows=added.filter(r=>r.name.startsWith('select.card.'+card+'.'));
 const order=rows.map(r=>({rank:r.name.includes('.cell.')?0:r.name.includes('.wall.')?1:2,at:rootKids.indexOf(r.id)})).sort((a,b)=>a.at-b.at);
 ck('卡片'+card+'底色→墙→门绘制顺序',order.every((r,i)=>!i||r.rank>=order[i-1].rank));
}
const quote=s=>JSON.stringify(s).replaceAll('\\u2028','\\n');
function fixtureOf(g){return 'local fixtures={\n'+g.recs.map(r=>{
 const st=R.stateBlocks(r.field.sub,[])[0];const p=st?R.pairOf(st,504):null,z=st?R.pairOf(st,505):null;
 const kids=r.childList?R.asIdList(r.childList.payload,true)||[]:[];
 return `{id=${r.id},name=${quote(r.name||'')},parent=${r.parentId||'nil'},kids={${kids.join(',')}},x=${p?R.pairValue(p,0):0},y=${p?R.pairValue(p,1):0},w=${z?R.pairValue(z,0):1},h=${z?R.pairValue(z,1):1},visible=${!hidden(r)}},`;
}).join('\n')+'\n}\n';}
const harness=`
local EA=__require('engine_adapter_qianxing')
local UI=__require('ui_controller')
local LV=__require('levels.init')
local Core=__require('murdoku_core')
local reads,writes,firstHideScan=0,0,nil
local objects,byname,roots={},{},{}
local function ck(name,ok,detail) print('CHECK\\t'..name..'\\t'..tostring(not not ok)..'\\t'..tostring(detail or '')) end
for _,r in ipairs(fixtures) do
 local o={name=r.name,kids={},visible=r.visible,active=true,x=r.x,y=r.y,w=r.w,h=r.h,
 text='',fontColor=0xFFFFFFFF,fontSize=20,imageId=106053,imageSource=0,imageColor=0xFFFFFFFF,
 raycastTarget=false,blockRaycast=false,interactable=false}
 objects[r.id]=o
 if byname[r.name]==nil then byname[r.name]=o end
 function o:GetChildren() reads=reads+1;return self.kids end
 function o:GetChild(name)
  if type(name)=='number' then return self.kids[name+1] end
  for _,c in ipairs(self.kids) do if c.name==name then return c end end
 end
 function o:GetChildCount() return #self.kids end
 function o:SetVisible(v)
  writes=writes+1
  self.visible=v
  if self.name=='modal' and not v and firstHideScan==nil then firstHideScan=reads end
 end
 function o:SetActive(v) self.active=v end
 function o:GetAnchoredPosition() return self.x,self.y end
 function o:SetAnchoredPosition(x,y) self.x,self.y=x,y end
 function o:GetSizeDelta() return self.w,self.h end
 function o:SetSizeDelta(w,h) self.w,self.h=w,h end
 function o:SetAnchorMin(x,y) self.amin={x,y} end
 function o:SetAnchorMax(x,y) self.amax={x,y} end
 function o:SetPivot(x,y) self.pivot={x,y} end
 function o:SetImage(source,id) self.imageSource,self.imageId=source,id end
 function o:SetLocalScale() end
 function o:SetAsLastSibling() end
 function o:AddCursorEventListener(event,cb) self.callback=cb end
end
for _,r in ipairs(fixtures) do
 local o=objects[r.id]
 for _,id in ipairs(r.kids) do if objects[id] then o.kids[#o.kids+1]=objects[id] end end
 if r.name=='root' then roots[#roots+1]=o end
end
local spawns=0
 game={GetClientUIRoots=function() return roots end,
 InstantiateClientUIControl=function() spawns=spawns+1;error('测试禁止自动创建') end}
 Enum={CursorEventType={CursorClick=1,CursorDown=2,CursorUp=3,CursorDrag=4}}
 local cfg={auto_create=false,respect_editor_rect=true,use_grid=false,scale=5/6,canvas_w=1600,canvas_h=900,
 debug_event=false,debug_click=false,cells={parent='stage'}}
 local function newAdapter() return EA.new(cfg) end
 local list=LV.ui_list()
 local function newUI() UI.SELECT_PAGE=1;return UI.new(Core.new(__require('levels.case_001')),{screen='home',levels=list,skip_intro=true}) end
 -- 原始回放：严格重放首帧layout_plan隐藏调用，便于与697基准比较。
 local raw=newAdapter();local u=newUI();local seen={}
 for _,n in ipairs(u:build_layout()) do seen[n.id]=true end
 reads=0
 local before=0
 for _,n in ipairs(u:layout_plan()) do if not seen[n.id] then
  if n.id=='modal' then before=raw._name_idx_builds or 0 end
  raw:set_property(n.id,'visible',false)
 end end
 print('METRIC\\trawScans\\t'..tostring(raw._name_idx_builds or 0))
 print('METRIC\\trawChildReads\\t'..reads)
 ck('首帧索引重建不超过1次',(raw._name_idx_builds or 0)<=1,raw._name_idx_builds)
 -- 主路径：给所有弹窗子层设为可见，且mock故意不级联父级隐藏。
 local popup=byname.modal
 local function visit(o,fn,seen)
  seen=seen or {};if not o or seen[o] then return end;seen[o]=true;fn(o)
  for _,c in ipairs(o.kids) do visit(c,fn,seen) end
 end
 visit(popup,function(o)o.visible=true end)
 local a=newAdapter();u=newUI();reads=0;firstHideScan=nil
 local propErrors={}
 local originalSet=EA.Adapter.set_property
 a.set_property=function(self,id,key,value,nkey)
  local ok,res=pcall(originalSet,self,id,key,value,nkey)
  if not ok then propErrors[#propErrors+1]=id..':'..key..':'..tostring(res);error(res) end
  return res
 end
 local ok,err=pcall(function()u:render(a,true)end)
 ck('真实控制器首页首帧可执行',ok,err)
 local leaked=0;visit(popup,function(o)if o.visible then leaked=leaked+1 end end)
 ck('首页弹窗及全部子层收净',leaked==0,leaked)
 ck('弹窗在首轮树扫描内关闭',firstHideScan and firstHideScan<6500,firstHideScan)
 print('METRIC\\thomeScans\\t'..tostring(a._name_idx_builds or 0))
 print('METRIC\\thomeChildReads\\t'..reads)
 local function verifyPage(page)
  local layout=u:build_layout(a)
  local expected={};local errors={};local cells,wall,door=0,0,0
  for _,n in ipairs(layout) do expected[n.id]=n end
  for _,r in ipairs(fixtures) do
   if r.name:match('^select%.card%.%d+%.cell%.') or r.name:match('^select%.card%.%d+%.wall%.') or r.name:match('^select%.card%.%d+%.door%.') then
    local n=expected[r.name];local o=objects[r.id]
    if not n or o.visible~=(n.visible~=false) then errors[#errors+1]=r.name..':visible' end
    if n and n.visible~=false then
     if r.name:find('.cell.',1,true) then cells=cells+1 end
     if r.name:find('.wall.',1,true) then wall=wall+1 end
     if r.name:find('.door.',1,true) then door=door+1 end
     if o.imageColor~=EA.pack_color(n.tint.r,n.tint.g,n.tint.b,n.tint.a) then errors[#errors+1]=r.name..':color' end
     if o.w<1 or o.h<1 or o.raycastTarget or o.blockRaycast or o.interactable then errors[#errors+1]=r.name..':geometryOrRaycast' end
    end
   end
  end
  local expectedCells=0
  for i=1,4 do local it=list[(page-1)*4+i]
   if it then
    expectedCells=expectedCells+it.size.rows*it.size.cols
    local target=a.event_latest['hit.select.card.'..i]
    local evt=target and a.events[target]
    if not evt or evt.id~=it.id or evt.action~='pick_level' then errors[#errors+1]='click:'..i end
    local nodes={};UI.Controller:push_room_thumb(function(n) if n.id:find('.cell.',1,true) and n.visible then nodes[#nodes+1]=n end end,'select.card.'..i,it,{x=250,y=330,w=279,h=388.8},'root')
    local minx,miny,maxx,maxy=1e9,1e9,-1e9,-1e9
    for _,n in ipairs(nodes) do minx=math.min(minx,n.rect.x);miny=math.min(miny,n.rect.y);maxx=math.max(maxx,n.rect.x+n.rect.w);maxy=math.max(maxy,n.rect.y+n.rect.h) end
    if math.abs(maxx-minx-(maxy-miny))>0.1 then errors[#errors+1]='notSquare:'..i end
   else
    for _,suffix in ipairs({'','.title','.info','.result'}) do local o=byname['select.card.'..i..suffix];if o and o.visible then errors[#errors+1]='emptyCard:'..i..suffix end end
   end
  end
  ck('第'..page..'页真实控件更新与多余项隐藏',#errors==0,table.concat(errors,','))
  ck('第'..page..'页格子数正确',cells==expectedCells,cells..'/'..expectedCells)
  print('METRIC\\tpage'..page..'Visible\\t'..cells..','..wall..','..door)
 end
 local function renderSelect(page)
  u.screen='select';u.modal=nil;u.select_page=page;u.dirty=true
  local ok,err=pcall(function()u:render(a,true)end)
  ck('选关第'..page..'页render成功',ok,err)
  if ok then verifyPage(page) end
 end
 renderSelect(1);renderSelect(2);renderSelect(1)
 -- 冷启动在末页，确保首帧不存在上一页留下的显隐前提。
 local cold=newUI();cold.screen='select';cold.select_page=2
 local ca=newAdapter();local cok,cerr=pcall(function()cold:render(ca,true)end)
 ck('冷启动直接进入第2页',cok,cerr)
 u.screen='home';u.modal=nil;u:render(a,true)
 local residue=0
 for _,r in ipairs(fixtures) do if r.name:match('^select%.card%.%d+%.') and r.name:match('%.cell%.|%.wall%.') then end
  if r.name:match('^select%.card%.%d+%.cell%.') or r.name:match('^select%.card%.%d+%.wall%.') or r.name:match('^select%.card%.%d+%.door%.') then if objects[r.id].visible then residue=residue+1 end end
 end
 ck('选关返回首页没有缩略图残留',residue==0,residue)
 ck('全流程不自动创建控件',spawns==0,spawns)
 ck('属性下发无异常',#propErrors==0,table.concat(propErrors,';'))
 -- 索引TTL与结构变化：连续缺失不重复扫，迟到项仍能恢复。
 local cache=newAdapter();cache:find('root');local start=cache._name_idx_builds or 0
 for i=1,300 do cache:find('missing698.'..i) end
 ck('300个不同缺失名只建一次索引',(cache._name_idx_builds or 0)-start<=1,(cache._name_idx_builds or 0)-start)
 cache:find('late698');cache.clock=1.1;cache:find('late698')
 local late={name='late698',GetChildren=function()return {}end}
 roots[1].kids[#roots[1].kids+1]=late;cache.clock=2.2
 ck('二次缺失后迟到控件仍可恢复',cache:find('late698')==late)
 cache:invalidate_lookups('test');ck('结构代数变化后恢复',cache:find('late698')==late)
 table.remove(roots[1].kids)
 -- 子树恢复必须同时保持本来隐藏的子控件。
 a:set_property('modal','visible',true)
 local marker=popup.kids[1]
 marker.visible=false
 a:set_property('modal','visible',false)
 a:set_property('modal','visible',true)
 ck('弹窗重开恢复可见装饰',popup.visible and popup.kids[2].visible)
 ck('弹窗重开保留本来隐藏的子层',marker.visible==false)
 a:set_property('modal','visible',false)
 a:set_property(popup.kids[2].name,'visible',false)
 a:set_property('modal','visible',true)
 ck('门控期间子层显隐修改不丢失',popup.kids[2].visible==false)
 -- 七关全部短名、布局覆盖、房间格子墙门与谜题不变量。
 for i,it in ipairs(list) do
  local parts=u:level_card_parts(it)
  ck(it.id..'短名为有效UTF8',utf8.len(parts.short)~=nil,parts.short)
  local thumb={};UI.Controller:push_room_thumb(function(n)thumb[#thumb+1]=n end,'select.card.1',it,{x=250,y=330,w=279,h=388.8},'root')
  local absent=0;local cells,walls,doors=0,0,0
  for _,n in ipairs(thumb) do
   if not a:find(n.id) then absent=absent+1 end
   if n.visible~=false then
    if n.id:find('.cell.',1,true) then cells=cells+1 end
    if n.id:find('.wall.',1,true) then walls=walls+1 end
    if n.id:find('.door.',1,true) then doors=doors+1 end
   end
  end
  ck(it.id..'缩略图每个节点真实存在',absent==0,absent)
  ck(it.id..'格墙门数量匹配',cells==it.size.rows*it.size.cols and walls==#it.walls and doors==#it.doors,cells..','..walls..','..doors)
 end
 print('METRIC\\tpropertyWrites\\t'..writes)
`;
fs.writeFileSync(TMP+'/regression.lua',lua.slice(0,lua.indexOf('local FORCE_LEVEL = nil'))+fixtureOf(g)+harness);
let out='';try{out=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[TMP+'/regression.lua'],{encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});}catch(e){out=String(e.stdout||'');ck('Lua回归完整执行',false,String(e.stderr||e.message));}
const metrics={};for(const line of out.split(/\r?\n/)){
 if(line.startsWith('CHECK\t')){const [,name,pass,...detail]=line.split('\t');ck(name,pass==='true',detail.join('\t'));}
 if(line.startsWith('METRIC\t')){const [,key,...value]=line.split('\t');metrics[key]=value.join('\t');}
}
// 复用既有七关行为探针，比较完整room/adj/clues/hints/carpet输出，避免仅做结构检查。
const oldTest=fs.readFileSync(path.join(DIR,'../697_凹角内收与缩略图居中/验证697行为.mjs'),'utf8');
const probe=oldTest.split('const PROBE = `')[1].split('`;')[0];
function behavior(src,tag){const f=TMP+'/behavior_'+tag+'.lua';fs.writeFileSync(f,src.slice(0,src.indexOf('local FORCE_LEVEL = nil'))+probe);return execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[f],{encoding:'utf8',timeout:120000}).split(/\r?\n/).filter(l=>/^(SPAWN|SPY|BEHAVIOR):/.test(l));}
try{const b=behavior(W.findScriptLeaf(base).buf.toString('utf8'),'697'),n=behavior(lua,'698');ck('七关谜题线索提示房间家具地毯行为逐项保持',JSON.stringify(b)===JSON.stringify(n));ck('五种地毯模板路径正常',n.find(s=>s.startsWith('SPAWN:'))?.split(';').every(s=>s.endsWith('true:true')),n.find(s=>s.startsWith('SPAWN:')));}catch(e){ck('七关行为执行',false,String(e.stderr||e.message));}
try{execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',path.join(DIR,'698_内嵌Lua_698.lua')],{encoding:'utf8',timeout:120000});ck('完整内嵌Lua语法通过',true);}catch(e){ck('完整内嵌Lua语法通过',false,String(e.stderr||e.message));}
// 通用源码/打包产物必须与698修复版一致，不能仅检查构建成功。
const distPath=path.join(ROOT,'qianxing-murdoku/dist/client_script.lua');
const dist=fs.readFileSync(distPath,'utf8');
function splitBundle(text){
 const marks=[...text.matchAll(/^__M\["([\w.]+)"\] = function\(\)\r?\n/gm)];
 const entryAt=text.indexOf('local FORCE_LEVEL = nil');
 const map=new Map();
 for(let i=0;i<marks.length;i++){
  let part=text.slice(marks[i].index+marks[i][0].length,i+1<marks.length?marks[i+1].index:entryAt);
  // 通用打包器在最后模块与入口之间添加固定说明行。
  part=part.replace(/\n-- ==== 入口：官方生命周期回调（OnInit \/ OnStart \/ OnUpdate \/ \.\.\.）==== --\s*$/,'');
  part=part.trimEnd();
  if(!part.endsWith('\nend'))throw Error('模块包装异常 '+marks[i][1]);
  map.set(marks[i][1],part.slice(0,-4).trimEnd());
 }
 return {map,entry:text.slice(entryAt).trimEnd()};
}
const canonical=s=>s.replace(/=\s*__require\s*\(/g,'= __require(').replace(/pcall\s*\(\s*__require/g,'pcall(__require').trimEnd();
const packed=splitBundle(dist),embedded=splitBundle(lua);
ck('通用构建包含相同17个模块',packed.map.size===17&&JSON.stringify([...packed.map.keys()])===JSON.stringify([...embedded.map.keys()]));
for(const [name,body] of embedded.map){
 ck(name+'通用构建模块正文与698一致',canonical(packed.map.get(name)||'')===canonical(body));
 const sourcePath=path.join(ROOT,'qianxing-murdoku/lua',name.replaceAll('.','/')+'.lua');
 const source=fs.readFileSync(sourcePath,'utf8');
 ck(name+'通用源码可还原698模块',canonical(source.replaceAll('__require','require').replace(/=\s*require\s*\(/g,'= __require(').replace(/pcall\s*\(\s*require/g,'pcall(__require'))===canonical(body));
}
ck('通用构建入口与698一致',canonical(packed.entry)===canonical(embedded.entry));
const entrySource=fs.readFileSync(path.join(ROOT,'qianxing-murdoku/lua/entry_client_script.lua'),'utf8');
ck('通用入口源码与698一致',canonical(entrySource.replace(/=\s*require\s*\(/g,'= __require(').replace(/pcall\s*\(\s*require/g,'pcall(__require'))===canonical(embedded.entry));
const distRegression=TMP+'/regression_dist.lua';
fs.writeFileSync(distRegression,dist.slice(0,dist.indexOf('local FORCE_LEVEL = nil'))+fixtureOf(g)+harness);
try{
 const distOut=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[distRegression],{encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});
 const rows=distOut.split(/\r?\n/).filter(s=>s.startsWith('CHECK\t'));
 ck('通用dist完成全部页面回归',rows.length===out.split(/\r?\n/).filter(s=>s.startsWith('CHECK\t')).length,rows.length);
 for(const line of rows){const [,name,pass,...detail]=line.split('\t');ck('dist/'+name,pass==='true',detail.join('\t'));}
 ck('通用dist七关行为与698一致',JSON.stringify(behavior(dist,'dist'))===JSON.stringify(behavior(lua,'embedded')));
}catch(e){ck('通用dist完整回归执行',false,String(e.stderr||e.message));}
const syntaxFiles=[...embedded.map.keys()].map(name=>path.join(ROOT,'qianxing-murdoku/lua',name.replaceAll('.','/')+'.lua'));
syntaxFiles.push(path.join(ROOT,'qianxing-murdoku/lua/entry_client_script.lua'),path.join(ROOT,'qianxing-murdoku/tools/bundle_client_script.lua'),distPath);
let syntaxErrors=[];for(const file of syntaxFiles){try{execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',file],{encoding:'utf8',timeout:120000});}catch(e){syntaxErrors.push({file,error:String(e.stderr||e.message)});}}
ck('18个运行源码及打包器和dist语法通过',syntaxErrors.length===0,syntaxErrors);
const result={version:698,pass:checks.filter(c=>c.pass).length,fail:checks.filter(c=>!c.pass).length,total:checks.length,metrics,sourceSync:{modules:17,entry:true,dist:distPath,sourceFiles:18},baseline697:{missing:201,indexBuilds:208,childReads:1126944,invalidNames:2},limits:['真实Lua和磁盘控件树重放；控件API由mock模拟，未导入游戏','真机帧率、输入命中与视觉表现不在离线回放可证明范围内'],checks};
fs.writeFileSync(path.join(DIR,'698_验证结果.json'),JSON.stringify(result,null,2));
console.log('698 回归 '+result.pass+'/'+result.total+'，失败 '+result.fail);
console.log('METRICS',JSON.stringify(metrics));
for(const c of checks.filter(c=>!c.pass))console.log('FAIL',c.name,JSON.stringify(c.detail));
if(!checks.some(c=>c.name==='首帧索引重建不超过1次')){console.log(out.slice(-10000));process.exit(2);}
process.exit(result.fail?1:0);
