#!/usr/bin/env node
// 临时：把「块深度流水」按行打印（含文本），用来人工核对每一层配对。
// 用法：node tools/audit/_ledger.mjs <文件> <起始行> <结束行>
import fs from 'node:fs';
import { scanBlocks } from './check_nesting.mjs';

const [, , file, a, b] = process.argv;
const from = parseInt(a, 10), to = parseInt(b, 10);
const { rows, finalDepth } = scanBlocks(fs.readFileSync(file, 'utf8'));
console.log(`# ${file}  行 ${from}..${to}  全文末深度=${finalDepth}`);
for (const r of rows) {
  if (r.line < from || r.line > to) continue;
  const d = r.depthAfter - r.depthBefore;
  const tag = d === 0 ? '  ' : (d > 0 ? `+${d}` : `${d}`);
  console.log(`${String(r.line).padStart(5)} [${tag.padStart(2)}] d${r.depthAfter}  ${r.text.trim().slice(0, 74)}`);
}
