// tools/_wip/reparent_cells.mjs —— 把存档里 `cell.*` 的父级从 board 改到 stage
//
// 背景（2026-10-06 第 6/12 轮 ✓）：
//   计划里格子原本挂 `board` ✗ —— 而 `board` 在真机与模拟器**都不存在** ✗
//   真机日志：★「stage 树上实际有 27 个子控件」✓ ⇒ ★ 真机里格子挂在 `stage` 下 ✓
//   ⇒ 已在 Lua 侧把 `parent` 改成 `stage` ✓（提交 5d0c2f2 ✓）
//   ⇒ ★ 但模拟器会话里的**存档**还是旧的 ✗ ⇒ 本脚本负责把它对齐 ✓
//
// ⚠️ 两条踩过的坑（★ 都写在这里，免得再犯 ✓）：
//   ① ★ 磁盘上的 save **滞后于会话** ✗ —— 会话只在保存时才写回 ✓
//      ⇒ 所以改完文件**必须**再 `qxqy_studio_load` 一次 ✓
//   ② ★ 中文路径必须 `fileURLToPath`** ✗ —— `new URL().pathname` 会 URL 编码 ✓
//
// 用法：
//   node tools/_wip/reparent_cells.mjs            ← 只报告（默认 ✓ 安全）
//   node tools/_wip/reparent_cells.mjs --apply    ← 真的改文件
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const FILE = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(root, 'sim-save', 'murdoku.save.json');
const APPLY = process.argv.includes('--apply');

const raw = fs.readFileSync(FILE, 'utf8');
const s = JSON.parse(raw);

// 节点表：存档把树放在 `tree`（数组，带 parentId ✓）
const tree = s.tree || [];
const byId = new Map();
for (const n of tree) byId.set(String(n.id), n);

// 找 stage / board
const stage = tree.find(n => n.name === 'stage');
const board = tree.find(n => n.name === 'board');
console.log('=== ' + path.relative(root, FILE) + ' ===');
console.log('  树节点数 = ' + tree.length);
console.log('  stage = ' + (stage ? ('id=' + stage.id + ' guid=' + stage.guid + ' parentId=' + JSON.stringify(stage.parentId)) : '**找不到** ✗'));
console.log('  board = ' + (board ? ('id=' + board.id + ' guid=' + board.guid + ' parentId=' + JSON.stringify(board.parentId)) : '**找不到** ✗'));

if (!stage) {
  console.log('  ✗ 没有 stage ⇒ 无法重挂，先查存档为什么缺 stage');
  process.exit(0);
}

// 统计 cell.* 当前的 parentId
const cells = tree.filter(n => /^cell\./.test(String(n.name)));
console.log('  cell.* 节点数 = ' + cells.length);
const dist = new Map();
for (const c of cells) {
  const p = String(c.parentId);
  dist.set(p, (dist.get(p) || 0) + 1);
}
for (const [p, n] of dist) {
  const holder = byId.get(p);
  console.log('    parentId=' + JSON.stringify(p) + ' × ' + n +
    '  → ' + (holder ? ('「' + holder.name + '」') : '**树里没有这个 id** ✗'));
}

// 要改的：parentId 指向 board（或不是 stage）的那些
const need = cells.filter(c => String(c.parentId) !== String(stage.id));
console.log('  需要重挂到 stage 的 = ' + need.length + ' 个');
if (need.length > 0) {
  console.log('    例：' + need.slice(0, 4).map(c => c.name + '(' + c.parentId + '→' + stage.id + ')').join('  '));
}

if (!APPLY) {
  console.log('  （只报告模式 ✓ 要真改请加 --apply ✓）');
  process.exit(0);
}

for (const c of need) c.parentId = stage.id;
fs.writeFileSync(FILE, JSON.stringify(s));
console.log('  ✓ 已写回 ' + need.length + ' 个格子的 parentId → ' + stage.id +
  '（存档 ' + (fs.statSync(FILE).size / 1048576).toFixed(2) + ' MB）');
console.log('  ⚠️ 下一步必须 `qxqy_studio_load` 一次，否则会话里还是旧的 ✓');
