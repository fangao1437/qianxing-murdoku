// 复用698的真实存档树/控制器回放，移除与652父级显隐语义冲突的假设；另核对695链路。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const TMP=process.env.FEIBO_TMP;if(!TMP)throw Error('需要本任务FEIBO_TMP目录');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs'))),W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const g=R.readGil(path.join(DIR,'699_教程与交互修复.gil')),lua=W.findScriptLeaf(g).buf.toString('utf8');
const checks=[];function ck(name,ok,detail=''){checks.push({name,pass:!!ok,detail})}
const old=fs.readFileSync(path.join(DIR,'../698_首页与缩略图修复/验证698.mjs'),'utf8');
const at=(f,ns)=>ns.reduce((x,n)=>x?.sub?.find(y=>y.field===n&&y.wt===2),f);
const hidden=r=>r.field.sub.some(f=>f.field===505&&at(f,[503,14,17])?.sub?.some(x=>x.field===503&&x.wt===0));
const quote=s=>JSON.stringify(s);let fixture='local fixtures={\n'+g.recs.map(r=>{const st=R.stateBlocks(r.field.sub,[])[0],p=st?R.pairOf(st,504):null,z=st?R.pairOf(st,505):null;const num=n=>Number.isFinite(n)?n:0;return `{id=${r.id},name=${quote(r.name||'')},parent=${r.parentId||'nil'},kids={${r.childList?(R.asIdList(r.childList.payload,true)||[]).join(','):''}},x=${num(p&&R.pairValue(p,0))},y=${num(p&&R.pairValue(p,1))},w=${num(z&&R.pairValue(z,0))},h=${num(z&&R.pairValue(z,1))},visible=${!hidden(r)}},`}).join('\n')+'\n}\n';
let harness=old.split('const harness=`')[1].split('\n`;')[0];assert(harness);
// JS模板中的转义原样还原为Lua源码。
harness=harness.replaceAll('\\\\','\\');
const a=harness.indexOf(' -- 主路径：'),b=harness.indexOf(' local function verifyPage(page)');assert(a>=0&&b>a);
harness=harness.slice(0,a)+` local a=newAdapter();u=newUI();reads=0
 local propErrors={}
 local ok,err=pcall(function()u:render(a,true)end)
 ck('首页真实控制器首帧可执行',ok,err)
 ck('首页弹窗父级隐藏',byname.modal.visible==false)
 print('METRIC\\thomeChildReads\\t'..reads)
`+harness.slice(b);
const c=harness.indexOf(' -- 子树恢复必须'),d=harness.indexOf(' -- 七关全部');assert(c>=0&&d>c);harness=harness.slice(0,c)+harness.slice(d);
const f=path.join(TMP,'699-layout.lua');fs.writeFileSync(f,lua.slice(0,lua.indexOf('local FORCE_LEVEL = nil'))+fixture+harness);
const out=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[f],{encoding:'utf8',timeout:120000,maxBuffer:4000000});
const metrics={};for(const line of out.split(/\r?\n/)){if(line.startsWith('CHECK\t')){const [,name,pass,...detail]=line.split('\t');ck(name,pass==='true',detail.join('\t'))}if(line.startsWith('METRIC\t')){const [,key,...v]=line.split('\t');metrics[key]=v.join('\t')}}
function split(s){const ms=[...s.matchAll(/^__M\["([\w.]+)"\] = function\(\)\r?\n/gm)],e=s.indexOf('local FORCE_LEVEL = nil'),map=new Map();for(let i=0;i<ms.length;i++){let body=s.slice(ms[i].index+ms[i][0].length,i+1<ms.length?ms[i+1].index:e).replace(/\n-- ==== 入口：官方生命周期回调[^\n]*\s*$/,'').trimEnd();assert(body.endsWith('\nend'));map.set(ms[i][1],body.slice(0,-4).trimEnd())}return {map,entry:s.slice(e).trimEnd()}}
const canon=s=>s.replace(/=\s*(?:__)?require\s*\(/g,'= __require(').replace(/pcall\s*\(\s*(?:__)?require/g,'pcall(__require').trimEnd();
const B=split(fs.readFileSync(path.join(DIR,'../695_地毯原型注册与改名/695_内嵌Lua_695.lua'),'utf8')),N=split(lua);
ck('教程模块与695逐字一致',B.map.get('tutorial_ui')===N.map.get('tutorial_ui'));
ck('入口除版本标记外与695一致',B.entry.replace(/构建标记 v635[^\n]+/,'VERSION')===N.entry.replace(/构建标记 v699[^\n]+/,'VERSION'));
ck('不含698递归显隐账本',!lua.includes('_popup_gated')&&!lua.includes('_popup_saved'));
ck('存档内嵌Lua等于dist及交付副本',fs.readFileSync(path.join(DIR,'../dist/client_script.lua'),'utf8')===lua&&fs.readFileSync(path.join(DIR,'699_内嵌Lua_699.lua'),'utf8')===lua);
for(const [name,body]of N.map){const src=fs.readFileSync(path.join(DIR,'../lua',name.replaceAll('.','/')+'.lua'),'utf8');ck(name+'源码与存档一致',canon(src)===canon(body))}
ck('入口源码一致',canon(fs.readFileSync(path.join(DIR,'../lua/entry_client_script.lua'),'utf8'))===canon(N.entry));
const probeFile=fs.readFileSync(path.join(DIR,'../697_凹角内收与缩略图居中/验证697行为.mjs'),'utf8'),probe=probeFile.split('const PROBE = `')[1].split('`;')[0];
function behavior(s,tag){const fp=path.join(TMP,'699-behavior-'+tag+'.lua');fs.writeFileSync(fp,s.slice(0,s.indexOf('local FORCE_LEVEL = nil'))+probe);return execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[fp],{encoding:'utf8',timeout:120000}).split(/\r?\n/).filter(l=>/^(SPAWN|SPY|BEHAVIOR):/.test(l))}
ck('七关谜题家具地毯行为与698保持',JSON.stringify(behavior(lua,'699'))===JSON.stringify(behavior(fs.readFileSync(path.join(DIR,'../698_首页与缩略图修复/698_内嵌Lua_698.lua'),'utf8'),'698')));
const syntax=[...N.map.keys()].map(n=>path.join(DIR,'../lua',n.replaceAll('.','/')+'.lua'));syntax.push(path.join(DIR,'../lua/entry_client_script.lua'),path.join(DIR,'../dist/client_script.lua'));for(const file of syntax){execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe',['-p',file],{timeout:30000})}ck('18个运行源码和dist语法通过',true);
const result={version:699,total:checks.length,pass:checks.filter(c=>c.pass).length,fail:checks.filter(c=>!c.pass).length,metrics,checks,limits:['控件API由mock模拟；采用祖先显隐计算有效状态','本脚本不证明真机鼠标命中、像素视觉或帧率','完整入口对照回放结果另见699_入口对照结果.json']};
fs.writeFileSync(path.join(DIR,'699_验证结果.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({pass:result.pass,total:result.total,fail:result.fail,metrics},null,2));for(const r of checks.filter(r=>!r.pass))console.log('FAIL',r.name,r.detail);if(result.fail)process.exit(1);
