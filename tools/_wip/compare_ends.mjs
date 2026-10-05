// tools/_wip/compare_ends.mjs —— 临时：把两份 main.lua 的"块关键字/end"序列抽出来对齐比较
// 目的：定位我这次编辑到底多删/少留了哪一个 `end`（不猜行号）。
// 跑法：node tools/_wip/compare_ends.mjs
import fs from 'node:fs';

const A = 'versions/116-补active-v075/main.lua';   // 改之前
const B = 'lua/main.lua';                          // 改之后

// 去掉注释与字符串，只留结构关键字
function tokens(src) {
  const out = [];
  let i = 0, line = 1;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    if (ch === '\n') { line++; i++; continue; }
    // 长注释 / 长字符串
    if (ch === '-' && src[i + 1] === '-') {
      // 长注释 --[[ ... ]]
      const m = /^--\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const e = src.indexOf(close, i + m[0].length);
        if (e < 0) break;
        line += (src.slice(i, e + close.length).match(/\n/g) || []).length;
        i = e + close.length;
        continue;
      }
      // 行注释
      const e = src.indexOf('\n', i);
      i = e < 0 ? n : e;
      continue;
    }
    // 长字符串
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
    // 短字符串
    if (ch === '"' || ch === "'") {
      let j = i + 1;
      while (j < n) {
        if (src[j] === '\\') { j += 2; continue; }
        if (src[j] === ch) break;
        if (src[j] === '\n') { line++; }
        j++;
      }
      i = j + 1;
      continue;
    }
    // 标识符 / 关键字
    if (/[A-Za-z_]/.test(ch)) {
      let j = i;
      while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
      const w = src.slice(i, j);
      if (['if','then','elseif','else','end','do','for','while','repeat','until','function','return','break','local','not','and','or','in','nil','true','false'].includes(w)) {
        out.push({ w, line });
      }
      i = j;
      continue;
    }
    i++;
  }
  return out;
}

const ta = tokens(fs.readFileSync(A, 'utf8'));
const tb = tokens(fs.readFileSync(B, 'utf8'));

// 逐项对齐，跳过我的新增：只要关键字序列（去掉注释后）应严格一致，除了我删掉的那一个 end
let i = 0, j = 0;
const diffs = [];
while (i < ta.length && j < tb.length) {
  if (ta[i].w === tb[j].w) { i++; j++; continue; }
  diffs.push({ a: ta[i], b: tb[j] });
  if (diffs.length > 40) break;
  // 只报告，不自动对齐
  i++; j++;
}
console.log(`${A}: ${ta.length} 个结构关键字`);
console.log(`${B}: ${tb.length} 个结构关键字`);
console.log(`差值 = ${tb.length - ta.length}`);
console.log('\n== 前若干处不一致（a=改之前, b=改之后）==');
for (const d of diffs.slice(0, 30)) {
  console.log(`  a L${d.a.line} ${d.a.w}   |   b L${d.b.line} ${d.b.w}`);
}
if (diffs.length === 0) console.log('  （序列完全一致）');
