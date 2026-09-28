// tools/gil/apply_layout.mjs —— 把**规划里的几何**应用到现有 .gil（位置 + 尺寸）
//
// 为什么需要这个工具：
//   控件的位置/尺寸**存在 .gil 里**，所以改了 `ui_controller` 的 LAYOUT 之后，
//   光重打包脚本是不够的 —— 存档里的坐标还是旧的。
//   而重新生成整个存档会**丢掉用户在编辑器里做的东西**（例如 `assets` 调色板容器、
//   他自己配的图片和状态节点）。所以正确做法是：**只在现有存档上更新几何**。
//
// 与 gen_bulk.mjs 的分工：
//   · gen_bulk        从零生成（首次搭建、或要重做整套界面时）
//   · apply_layout    在现有存档上打补丁（改布局、微调位置时）—— 本项目常规做法
//
// 用法：
//   node tools/gil/apply_layout.mjs --in=a.gil --out=b.gil                 # 用默认规划
//   node tools/gil/apply_layout.mjs --in=a.gil --out=b.gil --plan=xxx.json
//   node tools/gil/apply_layout.mjs --in=a.gil --out=b.gil --probe

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, setPair, pairOf, stateBlocks } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const DRY = argv.includes('--probe');

const BASE = argOf('in');
const OUT = argOf('out') || BASE;
const PLAN = argOf('plan') || path.join(ROOT, 'tools', 'sim', 'out', 'layout-plan.json');
if (!BASE) { console.error('必须给 --in='); process.exit(1); }

const plan = JSON.parse(fs.readFileSync(PLAN, 'utf8'));
const g = readGil(BASE);
console.log('存档：' + path.basename(BASE) + '  控件记录 ' + g.recs.length + ' 条');
console.log('规划：' + path.basename(PLAN) + '  ' + plan.nodes.length + ' 个节点');

// 规划里的几何是**画布绝对坐标**（中心点 + 宽高）；
// 但 `.gil` 里存的是**相对父级中心**的偏移（官方嵌套控件语义）。
// 所以要把父节点也找出来做一次换算 —— 这一步不能省，
// 直接写中心点会让所有子控件都偏到父级原点去。
const byId = new Map(plan.nodes.map((n) => [n.id, n]));

let moved = 0, sized = 0, missing = 0, skipped = 0;

for (const node of plan.nodes) {
  const rec = g.byName.get(node.id);
  if (!rec) { missing++; continue; }
  if (rec.states.length !== 4) { skipped++; continue; }

  // 父级中心（规划里没有父节点就当作根 = 画布中心）
  let pcx = 0, pcy = 0;
  if (node.parent) {
    const p = byId.get(node.parent);
    if (p) { pcx = p.cx; pcy = p.cy; }
  }
  // 规划是"左上原点"的画布坐标；存档里 y 是**从下往上**的，需要翻转。
  // 规划自己已经做过一次翻转（plan.canvas 里的 cx/cy 就是最终画布坐标），
  // 这里只做"绝对 → 相对父级中心"的最后一步。
  const relX = node.cx - pcx;
  const relY = node.cy - pcy;

  let okPos = false, okSize = false;
  for (const block of stateBlocks(rec.field.sub, [])) {
    if (setPair(pairOf(block, 504), relX, relY)) okPos = true;
    if (setPair(pairOf(block, 505), node.w, node.h)) okSize = true;
  }
  if (okPos) moved++;
  if (okSize) sized++;
}

console.log('位置更新：' + moved + ' 个   尺寸更新：' + sized + ' 个');
console.log('存档里没有的规划节点：' + missing + ' 个（正常 —— 规划是多状态并集的一部分）');
console.log('状态块不是 4 的控件（跳过）：' + skipped + ' 个');

if (moved === 0) { console.log('\n无需改动'); process.exit(0); }
if (DRY) { console.log('\n--probe：不写文件'); process.exit(0); }

const body = encodeMsg(g.tree);
const buf = g.pack(body);
fs.writeFileSync(OUT, buf);

const g2 = readGil(OUT);
console.log('\n输出：' + path.basename(OUT) + '  ' + buf.length + ' 字节（原 ' + g.src.length + '）');
const tr = buf.subarray(buf.length - g.trailer.length);
console.log('  尾 ' + tr.toString('hex') + (tr.equals(g.trailer) ? '  ✅' : '  ❌')
  + '   记录 ' + g2.recs.length + '（原 ' + g.recs.length + '，应相等）');

// 抽验几个关键控件的最终位置
console.log('\n  抽验（画布绝对坐标应为规划值）：');
for (const id of ['board', 'actions', 'tool.place', 'ruler.c.1']) {
  const n = byId.get(id);
  const r = g2.byName.get(id);
  if (!n || !r) { console.log('    ' + id + ' → 缺'); continue; }
  let relX = null, relY = null, w = null, h = null;
  for (const block of stateBlocks(r.field.sub, [])) {
    const p = pairOf(block, 504);
    if (p && p.sub) {
      relX = (p.sub.find((x) => x.field === 501) || {}).f;
      relY = (p.sub.find((x) => x.field === 502) || {}).f;
    }
    const s = pairOf(block, 505);
    if (s && s.sub) {
      const a = (s.sub.find((x) => x.field === 501) || {}).f;
      const b = (s.sub.find((x) => x.field === 502) || {}).f;
      if (typeof a === 'number') { w = a; h = b; }
    }
    break;
  }
  console.log('    ' + id.padEnd(14) + ' 存档相对(' + relX + ',' + relY + ') ' + w + 'x' + h
    + '   规划(' + n.cx + ',' + n.cy + ') ' + n.w + 'x' + n.h);
}
process.exit(0);
