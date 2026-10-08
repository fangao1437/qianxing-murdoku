// tools/_wip/inspect_root.mjs —— 查存档里 `root` 段的结构（★ 怀疑它才是权威树 ✓）
//
// 起因（2026-10-06 第 8/12 轮 ✓）：
//   ★ 我改了 `tree[].parentId`（49 个格子 board→stage ✓）并 load ✓
//   ★ 而试玩日志仍是「stage 树上实际有 **0** 个子控件」✗
//   ⇒ ★ 说明会话**不把 `tree[].parentId` 当权威** ✓
//   ★ 各段体积：tree 238055 · boxes 611041 · **root 1430243** · inspector 3794
//   ⇒ ★★ **root 最大 ⇒ 先查它** ✓
//
// 用法：node tools/_wip/inspect_root.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const FILE = path.join(root, 'sim-save', 'murdoku.save.json');
const s = JSON.parse(fs.readFileSync(FILE, 'utf8'));

const r = s.root;
console.log('=== s.root 类型 = ' + (Array.isArray(r) ? ('数组 ' + r.length) : typeof r) + ' ===');
if (Array.isArray(r)) {
  console.log('  前 3 项 keys: ' + r.slice(0, 3).map(x => Object.keys(x).join(',')).join(' || '));
  console.log('  例: ' + JSON.stringify(r[0]).slice(0, 400));
} else if (r && typeof r === 'object') {
  console.log('  keys: ' + Object.keys(r).slice(0, 20).join(' | '));
  for (const k of Object.keys(r).slice(0, 6)) {
    const v = r[k];
    console.log('    ' + k + ' : ' + (Array.isArray(v) ? ('数组 ' + v.length) : typeof v) +
      '  ' + JSON.stringify(v).slice(0, 160));
  }
}

// 在 root 段里找 cell.1.1 的上下文（★ 看它的父级字段叫什么 ✓）
const rawRoot = JSON.stringify(r);
console.log('=== root 段里找 cell.1.1 ===');
let i = rawRoot.indexOf('cell.1.1');
let n = 0;
while (i >= 0 && n < 3) {
  console.log('  --- 命中 ' + (n + 1) + ' @ ' + i + ' ---');
  console.log('  ' + rawRoot.slice(Math.max(0, i - 260), i + 160));
  i = rawRoot.indexOf('cell.1.1', i + 1);
  n++;
}
if (n === 0) console.log('  ✗ root 段里没有 cell.1.1');

// 找 stage / board 在 root 段里的表现
for (const nm of ['"stage"', '"board"']) {
  const j = rawRoot.indexOf(nm);
  console.log('  root 段里 ' + nm + ' 位置 = ' + j + (j >= 0 ? ('  上下文: ' + rawRoot.slice(Math.max(0, j - 140), j + 140)) : ''));
}
