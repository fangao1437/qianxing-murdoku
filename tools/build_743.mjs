// 743：从50bc994的742 v13派生，仅修改内嵌Lua，不覆盖基准或旧源码。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {loadTree,findScriptLeaf,writeGil} from './gil/gilwrite.mjs';
import {encodeMsg} from './gil/gilread.mjs';
const repo=fileURLToPath(new URL('../',import.meta.url));
const temp='C:/Users/18182/AppData/Local/Temp/feibo/a87c9796-134a-4fff-a062-1a9468726681';
const out=path.resolve(process.argv[2]||path.join(repo,'743_全面性能优化/743_全面性能优化.gil'));
const base=path.join(repo,'742_调查背包美术还原/742_调查背包美术还原_v13.gil');
assert(!fs.existsSync(out),'输出已存在，拒绝覆盖');
const sha=b=>createHash('sha256').update(b).digest('hex');
const g=loadTree(base),leaf=findScriptLeaf(g),original=leaf.buf.toString('utf8');
assert.equal(sha(g.src),'b2c46e289e86fb660529c3ded53b46f2c109279ef4c7f7842441302fc2c87414');
let lua=original;
const patches=[];
function patch(tag,before,after){assert.equal(lua.split(before).length,2,'补丁不唯一 '+tag);lua=lua.replace(before,()=>after);patches.push(tag);}
// 按父路径分组，只存一次父路径；第一次查找才展开该名字的完整段数组。
// 显式路径逐项映射不变，不扩大前缀匹配、不删回退、不跨帧缓存控件对象。
const start=lua.indexOf('local STATIC_PATH_655 = {'),end=lua.indexOf('local function path_lookup_655',start);
assert(start>0&&end>start);
const block=lua.slice(start,end),routes=[...block.matchAll(/\["([^"\n]+)"\]\s*=\s*"([^"\n]+)"/g)].map(m=>[m[1],m[2]]);
assert(routes.length>2000);
const groups=new Map(),reconstructed=new Map();
for(const [name,route]of routes){assert(!reconstructed.has(name));const parts=route.split('/');assert.equal(parts.pop(),name);const parent=parts.join('/');if(!groups.has(parent))groups.set(parent,[]);groups.get(parent).push(name);reconstructed.set(name,parent?parent+'/'+name:name);}
assert.deepEqual([...reconstructed],routes);
let compact='local STATIC_PATH_655 = {}\ndo\n  local function add(parent, names)\n    for name in names:gmatch("[^\\n]+") do STATIC_PATH_655[name] = parent end\n  end\n';
for(const [parent,names]of groups){assert(!names.some(n=>n.includes(']=]')));compact+='  add('+JSON.stringify(parent)+', [=['+names.join('\n')+']=])\n';}
compact+='end\n\n';
patch('共享静态路径父前缀',block,compact);
patch('静态路径首次使用展开','  local route = STATIC_PATH_655[name]\n  if route == nil then',`  local route = STATIC_PATH_655[name]
  if type(route) == "string" then
    route = route == "" and name or (route .. "/" .. name)
  end
  if route == nil then`);
// 动态路径分支立即在同一次调用中拆成数组，不会把完整路径当父路径再次拼接。
// 每节点存在性检查改为模块函数，保留成功/异常/nil的原逻辑与写失败重查。
patch('存在性检查共用函数','function Controller:_render_impl(adapter, force)',`local function render_exists743(adapter, id, found)
  if found or type(adapter.find) ~= "function" then return true, found end
  local ok, handle = pcall(adapter.find, adapter, id)
  found = ok and handle ~= nil
  return found or not ok, found
end
local function rect_record743(last, rect)
  local saved = last.__rect
  if saved == nil then saved = {}; last.__rect = saved end
  saved.x, saved.y, saved.w, saved.h = rect.x, rect.y, rect.w, rect.h
end
function Controller:_render_impl(adapter, force)`);
patch('记录创建前是否已存在','    local select_ctrl = nil\n    if select_content','    local was_created743 = self._created[n.id]\n    local select_ctrl = nil\n    if select_content');
patch('复用同一节点已成功的查找',`    local found = false
    local function exists_now()
      if found or type(adapter.find) ~= "function" then return true end
      local ok, handle = pcall(adapter.find, adapter, n.id)
      found = ok and handle ~= nil
      return found or not ok
    end`, `    local found = was_created743 and self._created[n.id] and select_ctrl ~= nil or false`);
patch('属性存在性检查','          local exists = exists_now()','          local exists\n          exists, found = render_exists743(adapter, n.id, found)');
patch('矩形存在性检查','      local rect_exists = exists_now()','      local rect_exists\n      rect_exists, found = render_exists743(adapter, n.id, found)');
const rect='last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }';
assert.equal(lua.split(rect).length,4);lua=lua.replaceAll(rect,'rect_record743(last, n.rect)');patches.push('复用私有矩形账本3处');
// 只读常量提升到模块级，赋值点经构建断言限定。
const iconsStart=lua.indexOf('    local ICON_ASSETS = {'),iconsEnd=lua.indexOf('    local pend_action =',iconsStart);
assert(iconsStart>0&&iconsEnd>iconsStart);
const constants=lua.slice(iconsStart,iconsEnd);
patch('布局固定表只构造一次',constants,'');
patch('布局固定表模块级定义','function Controller:build_layout(ui_adapter)',constants+'function Controller:build_layout(ui_adapter)');
patch('批处理开始免临时闭包','batched = pcall(function() adapter:begin_furn_batch() end)','batched = pcall(adapter.begin_furn_batch, adapter)');
patch('批处理结束免临时闭包','if batched then pcall(function() adapter:end_furn_batch() end) end','if batched then pcall(adapter.end_furn_batch, adapter) end');
const marker='构建标记 v742 / 调查背包美术还原 v13';assert(lua.includes(marker));lua=lua.replaceAll(marker,'构建标记 v743 / 全面性能优化');
fs.mkdirSync(temp,{recursive:true});
fs.writeFileSync(path.join(temp,'candidate743.lua'),lua);
const syntax=spawnSync('lua',['-e',"assert(load(io.read('*a'))); print('SYNTAX PASS')"],{input:lua,encoding:'utf8',timeout:30000});
assert.equal(syntax.status,0,syntax.stderr);console.log(syntax.stdout.trim());
function cold(s){const p=spawnSync('lua',[path.join(repo,'tests/shop_cold_render.lua')],{input:s,encoding:'utf8',timeout:60000});assert.equal(p.status,0,p.stderr);const m=p.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);assert(m,p.stdout);return m.slice(1).map(Number);}
const before=cold(original),after=cold(lua);
assert.deepEqual(after.slice(0,2),before.slice(0,2));assert(after[3]<before[3]);
console.log('COLD v13',before,'743',after);
// --candidate用于运行独立差分测试，未通过前不导出正式gil。
const stats={baseCommit:'50bc9940f15db1eed084b7022cfe135796ade2fb',baseSha256:sha(g.src),baseBytes:g.src.length,scriptBytesBefore:Buffer.byteLength(original),scriptBytesAfter:Buffer.byteLength(lua),routes:routes.length,parentGroups:groups.size,routeBytesBefore:Buffer.byteLength(block),routeBytesAfter:Buffer.byteLength(compact),patches,cold:{before,after},records:g.recs.length};
if(process.argv.includes('--candidate')){fs.writeFileSync(path.join(temp,'candidate_stats.json'),JSON.stringify(stats,null,2));console.log(JSON.stringify(stats,null,2));process.exit(0);}
const validationArg=process.argv.find(a=>a.startsWith('--validation='));
const validationPath=validationArg?path.resolve(validationArg.slice(13)):
  (fs.existsSync(path.join(temp,'validation743.json'))?path.join(temp,'validation743.json'):
    path.join(repo,'743_全面性能优化/743_性能与验证.json'));
const validationFile=JSON.parse(fs.readFileSync(validationPath,'utf8'));
const validation=validationFile.validation||validationFile;
assert.equal(validation.candidateSha256,sha(Buffer.from(lua)),'测试对象不是当前候选');assert.equal(validation.pass,true);
leaf.field.payload=Buffer.from(lua);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
fs.mkdirSync(path.dirname(out),{recursive:true});
const recordBytes=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const report=writeGil(g,out,{label:'743 全面性能优化',expectDiffs:1,expectMarker:'v743',expectRecs:g.recs.length,assert(saved){assert(findScriptLeaf(saved).buf.equals(Buffer.from(lua)));assert(saved.trailer.equals(g.trailer));for(const r of saved.recs)assert(encodeMsg([r.field]).equals(recordBytes.get(r.id)),r.name);return true;}});
fs.writeFileSync(path.join(path.dirname(out),'743_内嵌脚本.lua'),lua);
fs.writeFileSync(path.join(path.dirname(out),'743_性能与验证.json'),JSON.stringify({...stats,outputBytes:report.bytes,outputSha256:sha(report.g2.src),controlRecordsChanged:0,fieldDifferences:report.diffs,validation,limits:['离线模拟不代表实机帧率；未导入游戏','保留逐帧显隐、层序、查找TTL和迟到重试，未实施跨帧子列表缓存','通用lua和dist是旧基线，743以本构建器及743内嵌脚本为源，不用旧打包入口覆盖']},null,2));
console.log('OUTPUT',out,report.bytes,sha(report.g2.src));
