// tools/_wip/reparent_in_root.mjs —— 把 `cell.*` 从 board 的子节点搬到 stage 的子节点
//
// 为什么（2026-10-06 第 9/12 轮 ✓ 这是**第三个**才找对的地方 ✗）：
//   ★ `s.root` 是**嵌套树** ✓（字段 `children` ✓ **没有 `parentId`** ✗）
//     ⇒ ★★ 层级靠**嵌套**表达 ⇒ ★ **它才是权威** ✓
//   ★ `s.tree` 是**派生摘要** ✗（我第 7 轮改的是它 ⇒ **改了没用** ✓ 已在第 8 轮证实 ✓）
//   ⇒ ★ 所以本脚本**两处都改** ✓（★ 权威层必须改 ✓ 摘要层顺手保持一致 ✓）
//
// 三段定位（两处一致 ✓）：stage = n31 ✓ · board = n105 ✓ · cell.1.1 = n125 ✓
//
// 用法：
//   node tools/_wip/reparent_in_root.mjs            ← 只报告
//   node tools/_wip/reparent_in_root.mjs --apply    ← 真改
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const FILE = path.join(root, 'sim-save', 'murdoku.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(FILE, 'utf8'));

// ── 在嵌套树里按 name 找节点（★ 深度优先 ✓ 找到就返回 ✓）──────────────
function findByName(node, want, depth) {
  if (!node || (depth || 0) > 12) return null;
  if (node.name === want) return node;
  const kids = node.children;
  if (!Array.isArray(kids)) return null;
  for (const k of kids) {
    const hit = findByName(k, want, (depth || 0) + 1);
    if (hit) return hit;
  }
  return null;
}

const stage = findByName(s.root, 'stage');
const board = findByName(s.root, 'board');
console.log('=== root 嵌套树 ===');
console.log('  stage = ' + (stage ? ('id=' + stage.id + ' 子节点 ' + (stage.children || []).length) : '**找不到** ✗'));
console.log('  board = ' + (board ? ('id=' + board.id + ' 子节点 ' + (board.children || []).length) : '**找不到** ✗'));

if (!stage || !board) { console.log('  ✗ 缺 stage 或 board ⇒ 不能搬'); process.exit(0); }

const kids = board.children || [];
const cells = kids.filter(c => /^cell\./.test(String(c.name)));
const others = kids.filter(c => !/^cell\./.test(String(c.name)));
console.log('  board 下：★ cell.* = ' + cells.length + ' 个 · 其它 = ' + others.length + ' 个（' +
  others.map(o => o.name).slice(0, 6).join(', ') + '）');
console.log('  stage 下（搬之前）= ' + (stage.children || []).length + ' 个');

if (cells.length === 0) { console.log('  ✓ board 下已经没有 cell.* ⇒ 无需搬'); process.exit(0); }

if (!APPLY) { console.log('  （只报告 ✓ 要真改加 --apply ✓）'); process.exit(0); }

// ① 权威层：搬 children
board.children = others;
stage.children = (stage.children || []).concat(cells);

// ② 摘要层：同步 tree[].parentId（★ 第 7 轮已经改过 ✓ 这里兜一遍 ✓）
let fixedTree = 0;
for (const n of (s.tree || [])) {
  if (/^cell\./.test(String(n.name)) && String(n.parentId) !== String(stage.id)) {
    n.parentId = stage.id; fixedTree++;
  }
}

fs.writeFileSync(FILE, JSON.stringify(s));
console.log('  ✓ 搬好了：board 剩 ' + board.children.length + ' 个 · stage 现在 ' + stage.children.length + ' 个');
console.log('  ✓ 摘要层同步 ' + fixedTree + ' 个 parentId');
console.log('  ⚠️ 下一步必须 `qxqy_studio_load` ✓ 然后 `play start` 验「stage 树上实际有 27 个子控件」✓');
