#!/usr/bin/env node
// 临时对账：把两份 Lua 的「块深度流水」对齐比较，找出多余的 end/少掉的块。
// 用法：node tools/audit/_reconcile_blocks.mjs <原文件> <改后文件>
import fs from 'node:fs';
import { scanBlocks } from './check_nesting.mjs';

const [, , aPath, bPath] = process.argv;

function deltaSeq(file) {
  const { rows } = scanBlocks(fs.readFileSync(file, 'utf8'));
  const out = [];
  for (const r of rows) {
    const d = r.depthAfter - r.depthBefore;
    if (d !== 0) out.push({ line: r.line, d, text: r.text.trim() });
  }
  return out;
}

const A = deltaSeq(aPath);
const B = deltaSeq(bPath);

console.log(`原：${aPath}  变化点 ${A.length} 个，净 ${A.reduce((s, x) => s + x.d, 0)}`);
console.log(`改：${bPath}  变化点 ${B.length} 个，净 ${B.reduce((s, x) => s + x.d, 0)}`);

// 逐项配平：按「块嵌套文本」近似匹配 —— 这里只做前缀对齐后找首个分叉点
let i = 0, j = 0;
const firstDiv = [];
while (i < A.length && j < B.length) {
  if (A[i].d === B[j].d && A[i].text === B[j].text) { i++; j++; continue; }
  firstDiv.push({ a: A[i], b: B[j] });
  if (firstDiv.length >= 12) break;
  // 试探：原多了一个（改后少）或改后多了一个
  if (A[i].d !== B[j].d || A[i].text !== B[j].text) {
    // 尝试跳过原的一项 或 改的一项，看哪个能重新对齐
    const skipA = A[i + 1] && A[i + 1].d === B[j].d && A[i + 1].text === B[j].text;
    const skipB = B[j + 1] && A[i].d === B[j + 1].d && A[i].text === B[j + 1].text;
    if (skipA) { i++; continue; }
    if (skipB) { j++; continue; }
    i++; j++;
  }
}
console.log('\n首个分叉点（最多 12 条）：');
for (const p of firstDiv) {
  console.log(`  原 ${String(p.a.line).padStart(5)} d=${String(p.a.d).padStart(2)} :: ${p.a.text.slice(0, 76)}`);
  console.log(`  改 ${String(p.b.line).padStart(5)} d=${String(p.b.d).padStart(2)} :: ${p.b.text.slice(0, 76)}`);
  console.log('');
}
