// 实际存档父链 + 真实控制器/适配器，明确覆盖延迟挂载、文本失败与tick。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..'),TMP='C:/Users/18182/AppData/Local/Temp/feibo/cde5993a-3d1c-4dea-a5b7-be2ef0558166';
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilread.mjs')),W=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const g=R.readGil(DIR+'/701_选关缩略图与关卡名修复.gil'),base=R.readGil(DIR+'/../700_启动与教程点击修复/700_启动与教程点击修复.gil'),lua=W.findScriptLeaf(g).buf.toString('utf8'),checks=[];const ck=(name,pass,detail='')=>checks.push({name,pass:!!pass,detail});
const bm=new Map(base.recs.map(r=>[r.id,r]));ck('8296条控件记录与700逐字节一致',g.recs.length===8296&&g.recs.every(r=>R.encodeMsg([r.field]).equals(R.encodeMsg([bm.get(r.id).field]))));ck('内嵌脚本等于dist和交付副本',lua===fs.readFileSync(DIR+'/../dist/client_script.lua','utf8')&&lua===fs.readFileSync(DIR+'/701_内嵌Lua_701.lua','utf8'));
const at=(f,ns)=>ns.reduce((x,n)=>x?.sub?.find(y=>y.field===n&&y.wt===2),f),hidden=r=>r.field.sub.some(f=>f.field===505&&at(f,[503,14,17])?.sub?.some(x=>x.field===503&&x.wt===0));
const fixture='local fixtures={\n'+g.recs.map(r=>{const st=R.stateBlocks(r.field.sub,[])[0],p=st?R.pairOf(st,504):null,z=st?R.pairOf(st,505):null;return `{id=${r.id},name=${JSON.stringify(r.name||'')},parent=${r.parentId||'nil'},kids={${r.childList?(R.asIdList(r.childList.payload,true)||[]).join(','):''}},x=${p?R.pairValue(p,0):0},y=${p?R.pairValue(p,1):0},w=${z?R.pairValue(z,0):1},h=${z?R.pairValue(z,1):1},visible=${!hidden(r)}},`}).join('\n')+'\n}\n';
let old=fs.readFileSync(DIR+'/../698_首页与缩略图修复/验证698.mjs','utf8'),h=old.split('const harness=`')[1].split('\n`;')[0].replaceAll('\\\\','\\');h=h.slice(0,h.indexOf(' -- 原始回放：')).replace('local o=objects[r.id]\n for _,id','local o=objects[r.id]\n o.parent=objects[r.parent]\n for _,id');
const probe=`
local function effective(o) if not o then return false end;while o do if not o.visible or not o.active then return false end;o=o.parent end;return true end
local a=newAdapter();local u=newUI();u:render(a,true)
local function page(p)
 u.screen='select';u.select_page=p;u:render(a,true)
 for i=1,3 do a:on_tick(.2);u:tick(.2);u:render(a,false) end
 local names,thumbs,extra=0,0,0
 for slot=1,4 do local it=list[(p-1)*4+slot];local prefix='select.card.'..slot
  local info=byname[prefix..'.info'];local title=byname[prefix..'.title']
  if it then local parts=u:level_card_parts(it)
   if effective(info) and info.text==parts.short and info.fontColor==0xFF4A2E1C and utf8.len(info.text) and info.w>1 then names=names+1 end
   ck('第'..p..'页卡'..slot..'参数文本',effective(title) and title.text==parts.info)
   local count=0;for r=1,it.size.rows do for c=1,it.size.cols do local o=byname[prefix..'.cell.'..r..'.'..c];if effective(o) and o.w>1 and o.h>1 and o.imageColor>0xFFFFFF and not o.raycastTarget then count=count+1 end end end
   ck('第'..p..'页卡'..slot..'真实父链及全部格子',count==it.size.rows*it.size.cols,count)
   thumbs=thumbs+count
   local key=a.event_latest['hit.'..prefix];local ev=key and a.events[key];ck('第'..p..'页卡'..slot..'点击关卡映射',ev and ev.id==it.id)
  else
   if effective(info) or effective(title) or effective(byname[prefix]) then extra=extra+1 end
   for _,suffix in ipairs(UI.Controller.THUMB_POOL)do if effective(byname[prefix..suffix])then extra=extra+1 end end
  end
 end
 ck('第'..p..'页全部关卡名实际可见',names==math.min(4,#list-(p-1)*4),names)
 ck('第'..p..'页无空卡残留',extra==0,extra)
 print('METRIC\\tpage'..p..'Cells\\t'..thumbs)
end
page(1);page(2);page(1)
u:on_input({action='home'});u:render(a,true);a:on_tick(.2)
ck('返回首页缩略图父级关闭',not effective(byname['select.thumb.pool']))
ck('返回首页关卡名关闭',not effective(byname['select.card.1.info']))
local late={};local rt=byname.root
for i=#rt.kids,1,-1 do local o=rt.kids[i];if o.name=='select.thumb.pool' or o.name:match('^select%.card%.%d+%.info$') or o.name:match('^select%.card%.%d+%.title$') then late[#late+1]=o;table.remove(rt.kids,i);o.visible=false;o.text='' end end
local b=newAdapter();local w=newUI();w:render(b,true);w:on_input({action='levelselect'});w:render(b,true)
for i=1,5 do b:on_tick(.2);w:tick(.2);w:render(b,true)end
for _,o in ipairs(late)do rt.kids[#rt.kids+1]=o end
b:on_tick(2);w:tick(2);w:render(b,true);b:on_tick(.2)
for _,name in ipairs({'select.thumb.pool','select.card.1.info','select.card.1.cell.1.1','select.card.4.info','select.card.4.cell.1.1'})do local o=byname[name];ck('迟到恢复/'..name,effective(o) and (not name:match('%.info$') or o.text~=''))end
ck('迟到恢复没有重复全树扫描',(b._name_idx_builds or 0)<=4,b._name_idx_builds)
-- 文本读初值为nil时，直接赋值仍可用；写入连续四次失败也应恢复。
local info=byname['select.card.1.info'];info.text=nil
local direct=b:set_property(info.name,'text','空值恢复');ck('原生文本空初值仍写入',direct and info.text=='空值恢复')
info.text=nil;local attempts=0;setmetatable(info,{__newindex=function(t,k,v)if k=='text' then attempts=attempts+1;if attempts<=4 then error('temporary text not ready')end end;rawset(t,k,v)end})
w._props={};for i=1,7 do b:on_tick(.2);w:tick(.2);w:render(b,true)end;setmetatable(info,nil)
ck('文本四次失败后仍补发',info.text==w:level_card_parts(list[1]).short,attempts)
-- 三套教程继续使用700模块，执行真实注册回调。
local T=__require('tutorial_ui')
for _,tag in ipairs({'home','l1','l2'}) do local t=T.new(b,{tag=tag,pages=tag=='home' and 1 or tag=='l1' and 8 or 4});t:init();t:open_ui();local close=byname['td.'..tag..'.btn.close'];ck('教程必需按钮绑定/'..tag,t.inited and close.callback~=nil);if close.callback then close.callback()end;ck('教程关闭/'..tag,not t.open and not byname['td.'..tag].visible)end
print('METRIC\\tindexBuilds\\t'..tostring(a._name_idx_builds))
`;
const f=TMP+'/701-validation.lua';fs.writeFileSync(f,lua.slice(0,lua.indexOf('local FORCE_LEVEL = nil'))+fixture+h+probe.replaceAll('\\t','\t'));
let output='';try{output=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[f],{encoding:'utf8',timeout:90000,maxBuffer:4000000})}catch(e){output=String(e.stdout||'');ck('Lua回放完整执行',false,String(e.stderr||e.message))}
const metrics={};for(const l of output.split(/\r?\n/)){if(l.startsWith('CHECK\t')){const [,n,p,...d]=l.split('\t');ck(n,p==='true',d.join('\t'))}if(l.startsWith('METRIC\t')){const [,k,v]=l.split('\t');metrics[k]=v}}
ck('回放产生完整检查',checks.length>40,checks.length);
function split(s){const ms=[...s.matchAll(/^__M\["([\w.]+)"\] = function\(\)\r?\n/gm)],e=s.indexOf('local FORCE_LEVEL = nil'),map=new Map();for(let i=0;i<ms.length;i++){let p=s.slice(ms[i].index+ms[i][0].length,i+1<ms.length?ms[i+1].index:e).replace(/\n-- ==== 入口：官方生命周期回调[^\n]*\s*$/,'').trimEnd();assert(p.endsWith('\nend'));map.set(ms[i][1],p.slice(0,-4).trimEnd())}return {map,entry:s.slice(e).trimEnd()}}
const N=split(lua),B=split(W.findScriptLeaf(base).buf.toString('utf8')),canon=s=>s.replace(/=\s*(?:__)?require\s*\(/g,'= __require(').replace(/pcall\s*\(\s*(?:__)?require/g,'pcall(__require').trimEnd();
ck('教程模块与700逐字节保持',N.map.get('tutorial_ui')===B.map.get('tutorial_ui'));
for(const [name,body]of N.map){const fp=DIR+'/../lua/'+name.replaceAll('.','/')+'.lua';ck(name+'源码与存档同步',canon(fs.readFileSync(fp,'utf8'))===canon(body));execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',fp],{timeout:30000})}
execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',DIR+'/701_内嵌Lua_701.lua'],{timeout:30000});ck('全部模块与完整脚本语法',true);
const behaviorProbe=fs.readFileSync(DIR+'/../697_凹角内收与缩略图居中/验证697行为.mjs','utf8').split('const PROBE = `')[1].split('`;')[0];function behavior(s,v){const fp=TMP+'/701-behavior-'+v+'.lua';fs.writeFileSync(fp,s.slice(0,s.indexOf('local FORCE_LEVEL = nil'))+behaviorProbe);return execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[fp],{encoding:'utf8',timeout:60000}).split(/\r?\n/).filter(l=>/^(SPAWN|SPY|BEHAVIOR):/.test(l))}ck('七关谜题家具地毯行为与700一致',JSON.stringify(behavior(lua,701))===JSON.stringify(behavior(W.findScriptLeaf(base).buf.toString('utf8'),700)));
const result={version:701,total:checks.length,pass:checks.filter(c=>c.pass).length,fail:checks.filter(c=>!c.pass).length,metrics,checks,limits:['控件API由mock模拟；使用真实存档父链并运行真实适配器tick','700普通加载离线路径能写入，故不能断言截图全部由迟到加载造成','未导入游戏，未验证实际像素或真实鼠标命中','未覆盖旧版验证报告']};fs.writeFileSync(DIR+'/701_验证结果.json',JSON.stringify(result,null,2));console.log(JSON.stringify({pass:result.pass,total:result.total,fail:result.fail,metrics,failed:checks.filter(c=>!c.pass)},null,2));assert.equal(result.fail,0);
