#!/usr/bin/env node
// 临时诊断：逐行打印块深度的**变化点**，用来定位多余的 `end`（不改任何源文件）
import fs from 'node:fs';
import { scanBlocks } from './check_nesting.mjs';

const file = process.argv[2];
const from = parseInt(process.argv[3] || '1', 10);
const to = parseInt(process.argv[4] || '999999', 10);
const src = fs.readFileSync(file, 'utf8');
const { rows, finalDepth } = scanBlocks(src);
console.log(`# 全文末深度 = ${finalDepth}（应为 0；负 = 多了 end）`);
for (const r of rows) {
  if (r.line < from || r.line > to) continue;
  if (r.depthAfter !== r.depthBefore) {
    const d = r.depthAfter - r.depthBefore;
    const sign = d > 0 ? `+${d}` : `${d}`;
    console.log(`${String(r.line).padStart(5)}  ${String(r.depthBefore).padStart(2)} -> ${String(r.depthAfter).padStart(2)}  ${sign.padStart(2)}  ::  ${r.text.trim().slice(0, 88)}`);
  }
}
