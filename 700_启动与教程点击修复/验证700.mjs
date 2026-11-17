// 复用699结构/七关回归，增加能区分695/699的延迟加载与事件绑定测试。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..'),TMP=process.env.FEIBO_TMP;if(!TMP)throw Error('需要任务FEIBO_TMP');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs'))),W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const checks=[];const ck=(name,pass,detail='')=>checks.push({name,pass:!!pass,detail});
const g=R.readGil(path.join(DIR,'700_启动与教程点击修复.gil')),base=R.readGil(path.join(DIR,'../699_教程与交互修复/699_教程与交互修复.gil'));const bmap=new Map(base.recs.map(r=>[r.id,r]));
ck('全部8296控件记录与699逐字节一致',g.recs.length===8296&&g.recs.every(r=>bmap.has(r.id)&&R.encodeMsg([r.field]).equals(R.encodeMsg([bmap.get(r.id).field]))));
ck('存档编码往返一致',R.encodeMsg(g.tree).equals(g.src.subarray(20,20+g.hdr[4])));
for(const tag of ['home','l1','l2'])for(const suffix of ['.btn.close','.btn.next',...(tag==='home'?[]:['.btn.prev'])]){const r=g.recs.find(r=>r.name==='td.'+tag+suffix),p=g.recs.find(r=>r.name==='td.'+tag);ck(tag+suffix+'位于真实教程根容器',r&&p&&r.parentId===p.id)}
let old=fs.readFileSync(path.join(DIR,'../699_教程与交互修复/验证699.mjs'),'utf8').replaceAll('699','700').replaceAll('700_教程与交互修复.gil','700_启动与教程点击修复.gil');
old=old.replace("const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');",'const DIR='+JSON.stringify(DIR)+',ROOT='+JSON.stringify(ROOT)+';');
old=old.replace("ck('教程模块与695逐字一致',B.map.get('tutorial_ui')===N.map.get('tutorial_ui'));","ck('教程模块包含700延迟绑定修复',N.map.get('tutorial_ui').includes('if not next_bound or not close_bound'));");
const regression=path.join(TMP,'700-existing.mjs');fs.writeFileSync(regression,old);console.log(execFileSync('node',[regression],{encoding:'utf8',timeout:180000,maxBuffer:4000000}));
const layout=JSON.parse(fs.readFileSync(path.join(DIR,'700_验证结果.json'),'utf8'));checks.push(...layout.checks);
const probe=`
local EA=__require('engine_adapter_qianxing');local T=__require('tutorial_ui');Enum={CursorEventType={CursorClick=1}}
local function ck(n,v) print('DELAY\\t'..n..'\\t'..tostring(not not v)) end
local function obj(name) local o={name=name,kids={},visible=true,active=true,raycastTarget=false,interactable=true,binds=0}
 function o:GetChildren() return self.kids end
 function o:GetChild(n) for _,c in ipairs(self.kids)do if c.name==n then return c end end end
 function o:SetVisible(v)self.visible=v end
 function o:SetActive(v)self.active=v end
 function o:AddCursorEventListener(e,fn)if self.fail then error('not ready')end;self.binds=self.binds+1;self.callback=fn end
 return o end
local function scene(tag,pages,mode)
 local rt=obj('root');local td=obj('td.'..tag);rt.kids={td};game={GetClientUIRoots=function()return {rt}end}
 local a=EA.new({debug_event=false});assert(a:find(td.name));a:find('board')
 local close,next,prev=obj(td.name..'.btn.close'),obj(td.name..'.btn.next'),obj(td.name..'.btn.prev')
 local t=T.new(a,{tag=tag,pages=pages})
 if mode=='before' then t:init();ck(tag..'/missing-not-inited',not t.inited)end
 td.kids={close,next,prev};if mode=='failure' then close.fail=true end
 t:init()
 if mode=='failure' then ck(tag..'/failed-bind-not-inited',not t.inited);close.fail=false;t:init()end
 t:open_ui();local ready=close.callback~=nil and next.callback~=nil and (pages==1 or prev.callback~=nil)
 ck(tag..'/'..mode..'/bound',ready)
 if ready then
  close.callback();ck(tag..'/'..mode..'/close',not t.open and not td.visible)
  t:open_ui();if pages>1 then next.callback();ck(tag..'/'..mode..'/next-page',t.page==2);prev.callback();ck(tag..'/'..mode..'/prev-page',t.page==1);t:go(pages)end
  next.callback();ck(tag..'/'..mode..'/last-next-closes',not t.open)
  for i=1,5 do t:init()end;ck(tag..'/'..mode..'/no-duplicate',close.binds==1 and next.binds==1)
 end
 return ready
end
local first=scene('home',1,'sameframe');ck('original-repro',first)
if IS700 then for _,mode in ipairs({'before','failure'})do scene('home',1,mode)end;for _,tag in ipairs({'l1','l2'})do for _,mode in ipairs({'sameframe','before','failure'})do scene(tag,tag=='l1' and 8 or 4,mode)end end end
`;
const differential={};for(const v of [695,699,700]){const d=v===695?'695_地毯原型注册与改名':v===699?'699_教程与交互修复':'700_启动与教程点击修复';const lua=fs.readFileSync(path.join(DIR,'..',d,v+'_内嵌Lua_'+v+'.lua'),'utf8');const f=path.join(TMP,'700-delay-'+v+'.lua');fs.writeFileSync(f,lua.slice(0,lua.indexOf('local FORCE_LEVEL = nil'))+'\nlocal IS700='+String(v===700)+'\n'+probe.replaceAll('\\t','\t'));const out=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[f],{encoding:'utf8',timeout:30000});const rows=out.split(/\r?\n/).filter(l=>l.startsWith('DELAY\t')).map(l=>{const [,name,ok]=l.split('\t');return {name,pass:ok==='true'}});differential[v]=rows;if(v===700)for(const row of rows)ck('延迟绑定/'+row.name,row.pass);}
ck('原始故障695通过699失败700通过',differential[695].find(r=>r.name==='original-repro')?.pass===true&&differential[699].find(r=>r.name==='original-repro')?.pass===false&&differential[700].find(r=>r.name==='original-repro')?.pass===true);
const result={version:700,total:checks.length,pass:checks.filter(c=>c.pass).length,fail:checks.filter(c=>!c.pass).length,metrics:layout.metrics,differential,checks,limits:['延迟挂载场景可复现695与699差异；并非真机射线点击证明','真实控件树回放API仍为mock，不用于证明帧率或像素视觉','未重跑上一轮已丢失临时脚本的54项完整入口回放']};fs.writeFileSync(path.join(DIR,'700_验证结果.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({pass:result.pass,total:result.total,fail:result.fail,metrics:result.metrics,differential},null,2));assert.equal(result.fail,0);
