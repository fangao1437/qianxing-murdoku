// [[----------------------------------------------------------------------------
//   tools/_wip/move_nested_methods.mjs —— 一次性受控搬移（Round 46）
//
//   目的：把 `Adapter:apply_ruler_layout` 与 `Adapter:diagnose_overlap` 两个方法定义
//         从 `apply_tray_layout` 的函数体里**整段搬出**，让它们回到**文件顶层**。
//   为什么必须搬：它们现在只在 `apply_tray_layout` 执行时才被定义 ✗，而那个函数
//         有两处提前 return ⇒ `main.lua` 的 `~= nil` 守卫可能恒假 ⇒ 行标/列标对齐、
//         相交诊断**从来没跑过**（静默、无报错）。
//
//   安全性设计（本项目已被"人工搬移"坑过 4 次 ✗）：
//     ① **按内容定位**，不按行号（行号已被并发写入改乱过 ✓）
//     ② **按深度配平**找函数结束（数 function/if/do/for/while vs end ✓，跳过注释与字符串）
//     ③ 只在**完全找到两段、且顺序合理**时才写文件；否则**原样退出、不写** ✓
//     ④ 写回时**显式 UTF-8 无 BOM**（.lua 不能有 BOM ✓；PS 5.1 写会加 BOM ✗）
//     ⑤ 搬完**自己先做一次静态体检**（括号/块深度），不通过就不写 ✓
//   跑法：node tools/_wip/move_nested_methods.mjs [--apply]
//         不带 --apply 只做 dry-run（默认）✓
//  ----------------------------------------------------------------------------]]--

import { readFileSync, writeFileSync } from 'node:fs';

const FILE = 'lua/engine_adapter_qianxing.lua';
const APPLY = process.argv.includes('--apply');

const src = readFileSync(FILE, 'utf8');
const hadBom = src.charCodeAt(0) === 0xFEFF;
const text = hadBom ? src.slice(1) : src;
const lines = text.split('\n');

// ---- 块记账：给每行算"进入该行时"的深度 -------------------------------------
// 说明：只处理**块关键字**，且跳过注释（-- 之后）与单/双引号字符串的粗略情形。
//      对这份代码足够（它的块关键字都顶格或缩进出现，字符串里不含裸 end ✓）。
const OPEN = /(^|[\s(])function\s|(^|[\s(])if\s.*\bthen\s*$|(^|[\s(])for\s.*\bdo\s*$|(^|[\s(])while\s.*\bdo\s*$|(^|[\s(])do\s*$|(^|[\s(])repeat\s*$/;
const CLOSE = /(^|\s)end\s*$|(^|\s)until\s/;

function stripComment(s) {
  // 去掉行内注释（不处理字符串里含 -- 的极端情况；这份代码没有）
  const i = s.indexOf('--');
  return i >= 0 ? s.slice(0, i) : s;
}

function depthBefore() {
  const d = new Array(lines.length).fill(0);
  let cur = 0;
  for (let i = 0; i < lines.length; i++) {
    d[i] = cur;
    const code = stripComment(lines[i]).trim();
    if (code === '') continue;
    // 先算本行的 close（else/elseif 不改变深度）
    if (CLOSE.test(code) && !/^\s*else\s*$/.test(code) && !/^\s*elseif\b/.test(code)) cur -= 1;
    if (OPEN.test(code) || /(^|[\s(])function\b/.test(code)) {
      // 一行里既有 function 又有 end（例如 pcall(function() ... end)）⇒ 净变化 0
      const opens = (code.match(/\bfunction\b/g) || []).length + (/^\s*if\b.*\bthen\s*$/.test(code) ? 1 : 0)
        + (/^\s*for\b.*\bdo\s*$/.test(code) ? 1 : 0) + (/^\s*while\b.*\bdo\s*$/.test(code) ? 1 : 0);
      const closes = (code.match(/\bend\b/g) || []).length;
      cur += Math.max(0, opens - closes);
    }
  }
  return d;
}
const depth = depthBefore();

// ---- 找一个顶层函数的范围：[start, end]（end 行号含） ------------------------
function findFunction(sig) {
  const start = lines.findIndex((l) => l.startsWith(sig));
  if (start < 0) return null;
  const base = depth[start];
  for (let i = start + 1; i < lines.length; i++) {
    const code = stripComment(lines[i]).trim();
    if (code === 'end' && depth[i] === base + 1) return { start, end: i, base };
  }
  return null;
}

const A = findFunction('function Adapter:apply_ruler_layout');
const B = findFunction('function Adapter:diagnose_overlap');
if (!A || !B) { console.error('  ✗ 没找到两个方法，原样退出（不写文件）'); process.exit(2); }
if (!(A.start < B.start)) { console.error('  ✗ 顺序异常，原样退出'); process.exit(2); }

const tray = findFunction('function Adapter:apply_tray_layout');
if (!tray) { console.error('  ✗ 没找到 apply_tray_layout，原样退出'); process.exit(2); }

console.log(`  apply_tray_layout     L${tray.start + 1}..L${tray.end + 1}（深度 ${tray.base}）`);
console.log(`  apply_ruler_layout    L${A.start + 1}..L${A.end + 1}（深度 ${A.base}）`);
console.log(`  diagnose_overlap      L${B.start + 1}..L${B.end + 1}（深度 ${B.base}）`);
if (A.base === 0 && B.base === 0) { console.log('  ✓ 两个方法已经在顶层，无需搬移 ✓'); process.exit(0); }

// ---- 组装：把两段剪出来，插到 apply_tray_layout 的 `end` 之后 ----------------
const blockA = lines.slice(A.start, A.end + 1);
const blockB = lines.slice(B.start, B.end + 1);
const removed = new Set();
for (let i = A.start; i <= A.end; i++) removed.add(i);
for (let i = B.start; i <= B.end; i++) removed.add(i);

// 插入点：apply_tray_layout 的结束行（若它本身被剪掉了？不可能——它包着这两段）
const insertAt = tray.end;
if (removed.has(insertAt)) { console.error('  ✗ 插入点落在被剪区域内，原样退出'); process.exit(2); }

const out = [];
for (let i = 0; i < lines.length; i++) {
  if (removed.has(i)) continue;
  out.push(lines[i]);
  if (i === insertAt) { out.push('', ...blockA, '', ...blockB); }
}
const result = out.join('\n');

// ---- 写前自检：块深度必须配平、行数合理 --------------------------------------
function balance(s) {
  let cur = 0;
  for (const raw of s.split('\n')) {
    const code = stripComment(raw).trim();
    if (code === '') continue;
    if (CLOSE.test(code) && !/^\s*else\s*$/.test(code) && !/^\s*elseif\b/.test(code)) cur -= 1;
    if (/(^|[\s(])function\b/.test(code) || /^\s*if\b.*\bthen\s*$/.test(code)
      || /^\s*for\b.*\bdo\s*$/.test(code) || /^\s*while\b.*\bdo\s*$/.test(code)) {
      const opens = (code.match(/\bfunction\b/g) || []).length + (/^\s*if\b.*\bthen\s*$/.test(code) ? 1 : 0)
        + (/^\s*for\b.*\bdo\s*$/.test(code) ? 1 : 0) + (/^\s*while\b.*\bdo\s*$/.test(code) ? 1 : 0);
      const closes = (code.match(/\bend\b/g) || []).length;
      cur += Math.max(0, opens - closes);
    }
  }
  return cur;
}
const b0 = balance(text), b1 = balance(result);
console.log(`  块深度：改前 ${b0} → 改后 ${b1}`);
if (b1 !== b0) { console.error('  ✗ 自检不通过（块深度变了），原样退出'); process.exit(3); }
if (Math.abs(result.split('\n').length - lines.length) > 4) { console.error('  ✗ 行数变化异常，原样退出'); process.exit(3); }

if (!APPLY) { console.log('  （dry-run：没写文件。加 --apply 才写 ✓）'); process.exit(0); }
writeFileSync(FILE, result, 'utf8');   // 显式 UTF-8、无 BOM ✓
console.log(`  ✓ 已写入 ${FILE}（UTF-8 无 BOM）`);
