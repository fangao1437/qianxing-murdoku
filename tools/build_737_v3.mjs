// 由 737 v2 派生，页面控制器仍负责运行时的显示和隐藏。
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {loadTree,findScriptLeaf,writeGil} from './gil/gilwrite.mjs';
import {cloneField} from './gil/gilread.mjs';
const dir = new URL('../../构建存档/737/', import.meta.url);
const filename = '737_商城原生图标与全屏底色';
const base = loadTree(fileURLToPath(new URL(filename+'_v2.gil',dir)));
const out = fileURLToPath(new URL(filename+'_v3.gil',dir));
assert(!fs.existsSync(out),'输出已存在');
const child = (f,n) => f.sub?.find(s=>s.field===n);
function visibility(r) {
  const slot=r.field.sub.find(f=>f.field===505 && child(f,501)?.num===4n && child(f,502)?.num===86n);
  const flag=child(child(child(slot,503),14),17);
  assert(flag,r.name);return flag;
}
const hidden = r => child(visibility(r),503)?.num===1n;
// 只选由布局显式控制的实体。装饰子树不按前缀递归改写。
const owned = r => /^(?:modal(?:\.|$)|result\.|win(?:\.|$)|hex\.|hit\.(?:back|submit|redo|undo|hint|ok|no)$|hit\.select\.|select\.(?:back$|title$|page$|card\.)|econ\.(?:shop|bag)\.|settle\.btn(?:\.countdown)?$)/.test(r.name);
const required=['modal','result.title.1','result.title.2','result.title.3','modal.next','modal.again','select.card.1','hex.hint','hit.hint','hit.select.card.1'];
for(const n of required) assert(!hidden(base.byName.get(n)),n+' 应复现旧版可见初值');
const template=visibility(base.byName.get('econ.shop736.wallet'));
let changes=0;
for(const r of base.recs.filter(owned)) {
  if(hidden(r)) continue;
  const f=visibility(r); assert.equal(f.payload.length,0,r.name);
  Object.assign(f,cloneField(template)); changes++;
}
const leaf=findScriptLeaf(base);let lua=leaf.buf.toString('utf8');
function replace(from,to) {assert.equal(lua.split(from).length,2,from);lua=lua.replace(from,()=>to);}
replace('if not started then\n    retry_elapsed', 'if not started then\n    if started == nil then return end\n    retry_elapsed');
replace('        started = true       \n      else\n        if adapter == nil', '        started = nil -- 重试用尽，只有成功创建会话才能进入游戏更新。\n      else\n        if adapter == nil');
lua=lua.replaceAll('构建标记 v737 / 商城原生图标与全屏底色','构建标记 v737 / 商城原生图标与全屏底色 v3');
leaf.field.payload=Buffer.from(lua);
writeGil(base,out,{label:'737 v3',expectRecs:base.recs.length,expectMarker:'v737',assert:g=>{
  for(const r of g.recs.filter(owned)) assert(hidden(r),r.name);
  for(const r of g.recs.filter(r=>r.name?.startsWith('econ.shop736.'))) assert(hidden(r),r.name);
  const bytes=findScriptLeaf(g).buf;assert(bytes.equals(leaf.field.payload));
  const p=spawnSync('luac',['-p','-'],{input:bytes});assert.equal(p.status,0,p.stderr?.toString());
  console.log(`回读 ${g.recs.length} 控件，${changes} 个从默认显示改为隐藏，${g.recs.filter(owned).length} 个受管控件全部通过。`);
  return true;
}});
