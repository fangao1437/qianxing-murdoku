// 736 提供公共运行代码；只从 737 v2 移入商城外观。冷启动回归仅在构建端执行。
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {loadTree, findScriptLeaf, writeGil} from './gil/gilwrite.mjs';
const here = fileURLToPath(new URL('../../构建存档/',import.meta.url));
const baseline = loadTree(path.join(here,'736/736_调查商城.gil'));
const visual = loadTree(path.join(here,'737/737_商城原生图标与全屏底色_v2.gil'));
const out = path.join(here,'738/738_商城冷启动显隐修复.gil');
assert(!fs.existsSync(out),'目标文件已存在');
const prefix = 'econ.shop736.';
const rootId = baseline.byName.get(prefix+'s0').parentId;
function assertSharedRecords(other) {
  const publicRecords = g => g.recs.filter(r => r.id !== rootId && !r.name?.startsWith(prefix));
  const old = publicRecords(baseline), current = publicRecords(other);
  assert.equal(current.length,old.length);
  for(let i=0;i<old.length;i++) {
    assert.equal(current[i].id,old[i].id);
    assert(current[i].field.payload.equals(old[i].field.payload),old[i].name);
  }
}
assertSharedRecords(visual);
const source = findScriptLeaf(baseline).buf.toString('utf8');
const donor = findScriptLeaf(visual);
const shop = /    elseif self\.screen == 'shop' then[\s\S]*?(?=    elseif self\.screen == 'bag' then)/g;
const oneShop = text => { const rows = [...text.matchAll(shop)]; assert.equal(rows.length,1); return rows[0][0]; };
const oldRect = oneShop(source).split('\n').find(line=>line.includes("id='econ.shop736.s0'"));
const visualShop = oneShop(donor.buf.toString('utf8'));
const brokenRect = visualShop.split('\n').find(line=>line.includes("id='econ.shop736.s0'"));
assert(oldRect.includes('rect=') && !brokenRect.includes('rect='));
// 存档里的全屏锚点负责实际尺寸，脚本中的设计矩形供全页规划、渲染缓存使用。
const fixedShop = visualShop.replace(brokenRect,oldRect);
const fillOld = 'visible=set_visible(fill,true) and visible';
assert.equal(source.split(fillOld).length,2);
const fixed = source.replace(oneShop(source),()=>fixedShop)
  .replace(fillOld,"visible=set_visible(fill,page~='shop') and visible")
  .replaceAll('构建标记 v736 / 调查商城','构建标记 v738 / 商城冷启动显隐修复');
const test = fileURLToPath(new URL('../tests/shop_cold_render.lua',import.meta.url));
function replay(bytes) {
  const r=spawnSync('lua',[test],{input:bytes,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  const counts = /COLD=(\d+) WRITES=(\d+)/.exec(r.stdout);
  assert(counts,r.stdout);return counts.slice(1).map(Number);
}
const budget = replay(Buffer.from(source));
const candidate = Buffer.from(fixed);
const counts = replay(candidate);
console.log('736 与 738 的首页/切页累计写次数',budget,counts);
assert(counts.every((n,i)=>n<=budget[i]),'属性写次数超过 736');
donor.field.payload=candidate;
fs.mkdirSync(path.dirname(out),{recursive:true});
writeGil(visual,out,{label:'738',expectRecs:baseline.recs.length,expectDiffs:1,expectMarker:'v738',assert:g=>{
  assertSharedRecords(g);const bytes=findScriptLeaf(g).buf;
  assert(bytes.equals(candidate));assert.deepEqual(replay(bytes),counts);
  return true;
}});
