#!/usr/bin/env node
// 临时：打印一段行区间的「净深度变化」，并列出该区间内每个 end 的行号。
// 用法：node tools/audit/_region_balance.mjs <文件> <起始行> <结束行>
import fs from 'node:fs';
import { scanBlocks } from './check_nesting.mjs';

const [, , file, a, b] = process.argv;
const from = parseInt(a, 10), to = parseInt(b, 10);
const { rows } = scanBlocks(fs.readFileSync(file, 'utf8'));
let net = 0;
const ends = [];
for (const r of rows) {
  if (r.line < from || r.line > to) continue;
  const d = r.depthAfter - r.depthBefore;
  if (d !== 0) {
    net += d;
    if (d < 0) ends.push(`${r.line}(d${d})`);
  }
}
console.log(`${file}  行 ${from}..${to}  净变化 = ${net > 0 ? '+' : ''}${net}`);
console.log(`  end 行： ${ends.join(' ')}`);
