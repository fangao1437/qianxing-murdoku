// tools/_wip/compare_ends2.mjs —— 临时：报告两份 main.lua 结构关键字序列的**增删**
// 手法：去注释/字符串后取结构关键字序列；用一个 LCS 找出"只在一边出现"的关键字。
import fs from 'node:fs';

const A = process.argv[2] || 'versions/116-补active-v075/main.lua';
const B = process.argv[3] || 'lua/main.lua';

function tokens(src) {
  const out = [];
  let i = 0, line = 1;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    if (ch === '\n') { line++; i++; continue; }
    if (ch === '-' && src[i + 1] === '-') {
      const m = /^--\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const e = src.indexOf(close, i + m[0].length);
        if (e < 0) break;
        line += (src.slice(i, e + close.length).match(/\n/g) || []).length;
        i = e + close.length;
        continue;
      }
      const e = src.indexOf('\n', i);
      i = e < 0 ? n : e;
      continue;
    }
    if (ch === '[') {
      const m = /^\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const e = src.indexOf(close, i + m[0].length);
        if (e < 0) break;
        line += (src.slice(i, e + close.length).match(/\n/g) || []).length;
        i = e + close.length;
        continue;
      }
    }
    if (ch === '"' || ch === "'") {
      let j = i + 1;
      while (j < n) {
        if (src[j] === '\\') { j += 2; continue; }
        if (src[j] === ch) break;
        if (src[j] === '\n') line++;
        j++;
      }
      i = j + 1;
      continue;
    }
    if (/[A-Za-z_]/.test(ch)) {
      let j = i;
      while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
      const w = src.slice(i, j);
      const KW = ['if','then','elseif','else','end','do','for','while','repeat','until',
                  'function','return','break','local','not','and','or','in','nil','true','false'];
      if (KW.includes(w)) out.push({ w, line });
      i = j;
      continue;
    }
    i++;
  }
  return out;
}

const a = tokens(fs.readFileSync(A, 'utf8'));
const b = tokens(fs.readFileSync(B, 'utf8'));
console.log(`${A}: ${a.length} 个结构关键字`);
console.log(`${B}: ${b.length} 个结构关键字   差值 = ${b.length - a.length}`);

// LCS（长度够小，直接做 O(n*m) 但用 Map 压缩：这里 n≈1800 ⇒ 3.2M 单元，可以接受）
const n = a.length, m = b.length;
const W = m + 1;
const dp = new Int32Array((n + 1) * W);
for (let i = n - 1; i >= 0; i--) {
  for (let j = m - 1; j >= 0; j--) {
    dp[i * W + j] = (a[i].w === b[j].w)
      ? dp[(i + 1) * W + (j + 1)] + 1
      : Math.max(dp[(i + 1) * W + j], dp[i * W + (j + 1)]);
  }
}
let i = 0, j = 0;
const onlyA = [], onlyB = [];
while (i < n && j < m) {
  if (a[i].w === b[j].w) { i++; j++; continue; }
  if (dp[(i + 1) * W + j] >= dp[i * W + (j + 1)]) { onlyA.push(a[i]); i++; }
  else { onlyB.push(b[j]); j++; }
}
while (i < n) { onlyA.push(a[i]); i++; }
while (j < m) { onlyB.push(b[j]); j++; }

console.log(`\n== 只在**改之前**里有的关键字（${onlyA.length} 个）==`);
for (const t of onlyA) console.log(`  A L${t.line}  ${t.w}`);
console.log(`\n== 只在**改之后**里有的关键字（${onlyB.length} 个）==`);
for (const t of onlyB) console.log(`  B L${t.line}  ${t.w}`);
