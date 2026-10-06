// tools/_wip/inspect_plan.mjs —— 只读检查 layout-plan.json 的父级结构
//
// 为什么要有它（2026-10-06）：
//   play 日志说「stage 树上实际有 **0** 个子控件」✗ —— 而真机是 27 个 ✓
//   ⇒ ★ 怀疑：★ 计划里 `cell.*` 的 `parent` 写的是 **`board`** ✗
//     而模拟器里**根本没有 `board` 这个控件** ✓ ⇒ 挂不上 ⇒ stage 空 ✓
//   ⇒ ★ 本探针把这条**从文件里证实/证伪** ✗（★ 不靠推断 ✓）
//
// 用法：node tools/_wip/inspect_plan.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const f = path.join(root, 'tools', 'sim', 'out', 'layout-plan.json');
const plan = JSON.parse(fs.readFileSync(f, 'utf8'));
const ns = plan.nodes || [];

console.log('=== 计划：' + ns.length + ' 个节点 ===');

const byId = new Map();
for (const n of ns) byId.set(String(n.id), n);

// ① 有没有 board / stage / selbar
console.log('--- 关键容器是否存在 ---');
for (const want of ['root', 'board', 'stage', 'selbar', 'home', 'select', 'clues']) {
  const n = byId.get(want);
  console.log('  ' + want.padEnd(10) + (n ? ('存在 ✓ kind=' + n.kind + ' parent=' + JSON.stringify(n.parent))
    : '**不存在** ✗'));
}

// ② 各 parent 值的分布（★ 父级不存在的会被单独标出 ✓）
console.log('--- parent 值分布（★ ✗ = 父级不在计划里 ✓）---');
const dist = new Map();
for (const n of ns) {
  const p = n.parent === undefined ? '(无)' : String(n.parent);
  if (!dist.has(p)) dist.set(p, []);
  dist.get(p).push(String(n.id));
}
const rows = [...dist.entries()].sort((a, b) => b[1].length - a[1].length);
for (const [p, ids] of rows) {
  const exists = p === '(无)' ? '-' : (byId.has(p) ? '✓' : '✗');
  console.log('  ' + (exists + ' ' + p).padEnd(22) + ids.length + ' 个   例: ' + ids.slice(0, 4).join(', '));
}

// ③ 格子（cell.*）的父级到底是什么
console.log('--- cell.* 的父级 ---');
const cells = ns.filter(n => /^cell\./.test(String(n.id)));
console.log('  cell.* 节点数 = ' + cells.length);
const cellParents = new Map();
for (const c of cells) {
  const p = String(c.parent);
  cellParents.set(p, (cellParents.get(p) || 0) + 1);
}
for (const [p, n] of cellParents) {
  console.log('    parent=' + JSON.stringify(p) + ' × ' + n + (byId.has(p) ? '  ✓计划里有' : '  ✗**计划里没有**'));
}
if (cells[0]) console.log('    例：' + JSON.stringify({ id: cells[0].id, parent: cells[0].parent, kind: cells[0].kind }));

// ④ selbar / selbtn（★ 上轮查到命中 0 ✓ 这里再确认一次 ✓）
console.log('--- selbar / selbtn / tpl.* ---');
const sel = ns.filter(n => /selbar|selbtn|tpl\./.test(String(n.id)));
console.log('  命中 = ' + sel.length);
for (const n of sel.slice(0, 6)) console.log('    ' + JSON.stringify({ id: n.id, parent: n.parent, kind: n.kind }));

// ⑤ 顶层结构（第一个节点是不是那个 server-container）
console.log('--- 前 5 个节点的 id/kind/parent ---');
for (const n of ns.slice(0, 5)) console.log('    ' + JSON.stringify({ id: n.id, kind: n.kind, parent: n.parent }));
