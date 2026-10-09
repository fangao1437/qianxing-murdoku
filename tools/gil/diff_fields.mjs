// tools/gil/diff_fields.mjs —— 两个 `.gil` 的**字段级**（结构化）比对
//
// ════════════════════════════════════════════════════════════════════════════
// ★★★ 为什么必须有这个工具（2026-10-10 立 ✓）
// ════════════════════════════════════════════════════════════════════════════
//
//   ★ 起因：`fix_clue_tpl_origin.mjs` 这类"只改一个值"的编辑，**第一次就把 `#503` 改坏了** ✗。
//     ★ "只改一个值"是**靠人嘴保证的** ✗ —— ★ 而人嘴保证不了 ✓。
//   ⇒ ★ 判据要**可执行** ✓：★ **拿输出和输入做一次完整的结构化比对，
//     差异必须【正好是】你声称要改的那几个叶子** ✓ —— ★ 多一个字节都算失败 ✗
//
//   ⚠️ 为什么不能只比字节 / 只比哈希 ✗：
//     ★ 字节比对只能告诉你"变了" ✓，**不能告诉你"变的是不是只有那一个值"** ✗；
//     ★ 而且它**分不清"值变了"和"结构坏了"** ✗（长度前缀写错、字段顺序错位都能过哈希 ✗）。
//   ⇒ ★ 本工具按**字段树**并行下走 ✓，逐节点比 `(字段号, wire type, 值)` ✓
//     ★ 任何一处"一边有 sub、一边没有"✗ / "子字段个数不同"✗ / "值不同"✗ 都会**带路径报出来** ✓
//
//   ★ 判据（wire type 各自的"值"）：
//     · wt0 varint   ⇒ 比 `num`
//     · wt5 float    ⇒ 比**原始 4 字节**（比 `===` 更严 ✓，能抓到 NaN / -0 的位级差异 ✓）
//     · wt1 fixed64  ⇒ 比**原始 8 字节**
//     · wt2 消息     ⇒ 两边都有 `sub` ⇒ **递归** ✓；否则比 `payload` 字节 ✓
//
//   ★ 附带：差异路径会带上**它所属的控件记录**（用 `readGil` 自己的记录判据 ✓），
//     这样"第 3 个状态块的位置对"这种话能直接落到「哪个控件」上 ✓。
//
// 用法：
//   node tools/gil/diff_fields.mjs <A.gil> <B.gil>            # 全量报告
//   node tools/gil/diff_fields.mjs <A.gil> <B.gil> --max=20   # 最多列 20 条
// 退出码：0 = 无差异；3 = 有差异；2 = 用法/解析错误

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseMsg, recordsOf, KNOWN_TYPES } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const P = (p) => (path.isAbsolute(p) ? p : path.resolve(ROOT, p));
const opt = (k, d) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : d; };
const pos = argv.filter((s) => !s.startsWith('--'));
const MAX = Number(opt('max', '50'));

if (pos.length < 2) {
  console.error('用法: node tools/gil/diff_fields.mjs <A.gil> <B.gil> [--max=N]');
  process.exit(2);
}
const [FA, FB] = [P(pos[0]), P(pos[1])];

/** 读成"字段树 + 记录归属表" */
function load(file) {
  const src = fs.readFileSync(file);
  const hdr = []; for (let i = 0; i < 5; i++) hdr.push(src.readUInt32BE(i * 4));
  const bodyEnd = 20 + hdr[4];
  const tree = parseMsg(src, 20, bodyEnd, 0);
  if (!tree) { console.error('✗ 体解析失败：' + file); process.exit(2); }
  // 记录归属：★ 必须用**同一棵树的**记录（`recordsOf` 收树不重解析 ✓，
  //   否则对象身份对不上 ⇒ 归属全会打成"(非控件记录)" ✗ —— 2026-10-10 实测踩到 ✓）
  const owner = new Map();
  for (const r of recordsOf(tree)) owner.set(r.field, (r.name || '?') + ' #' + r.id);
  return { file, src, tree, bodyEnd, trailerLen: src.length - bodyEnd, owner, hdr };
}

const A = load(FA), B = load(FB);

const fmtF = (b) => { const v = b.readFloatLE(0); return Number.isInteger(v) ? String(v) : String(v); };
const hex = (b, n = 16) => b.subarray(0, Math.min(n, b.length)).toString('hex') + (b.length > n ? '…' : '');

const diffs = [];
let compared = 0;
const push = (kind, where, detail, ctx) => diffs.push({ kind, where, detail, ctx });

/** 从当前节点往上找最近的"记录"名（owner 表里有的那一层） */
function ownerLabel(chain) {
  for (let i = chain.length - 1; i >= 0; i--) {
    const lbl = A.owner.get(chain[i]) || B.owner.get(chain[i]);
    if (lbl) return lbl;
  }
  return '(非控件记录)';
}

function walkTree(fa, fb, pathStr, chain, depth) {
  if (fa.length !== fb.length) {
    push('子字段个数不同', pathStr, `A=${fa.length} 个  B=${fb.length} 个`, ownerLabel(chain));
    // 仍然继续比公共前缀，方便定位
  }
  const n = Math.min(fa.length, fb.length);
  for (let i = 0; i < n; i++) {
    const x = fa[i], y = fb[i];
    const p = pathStr + '#' + x.field + '[' + i + ']';
    const ctx = ownerLabel([...chain, x]);
    compared++;
    if (x.field !== y.field || x.wt !== y.wt) {
      push('字段号/类型不同', p, `A=#${x.field}/wt${x.wt}  B=#${y.field}/wt${y.wt}`, ctx);
      continue;
    }
    if (x.wt === 0) {
      if (x.num !== y.num) push('varint 值变化', p, `${x.num} → ${y.num}`, ctx);
    } else if (x.wt === 5) {
      const ra = A.src.subarray(x.s1 - 4, x.s1), rb = B.src.subarray(y.s1 - 4, y.s1);
      if (!ra.equals(rb)) push('float 值变化', p, `${fmtF(ra)} (${ra.toString('hex')}) → ${fmtF(rb)} (${rb.toString('hex')})`, ctx);
    } else if (x.wt === 1) {
      const ra = A.src.subarray(x.s1 - 8, x.s1), rb = B.src.subarray(y.s1 - 8, y.s1);
      if (!ra.equals(rb)) push('fixed64 值变化', p, `${hex(ra, 8)} → ${hex(rb, 8)}`, ctx);
    } else {
      if (x.sub !== null && y.sub !== null) {
        walkTree(x.sub, y.sub, p + '/', [...chain, x], depth + 1);
      } else if (x.sub !== null || y.sub !== null) {
        push('结构不同（一边是消息、一边是裸字节）', p, `A.sub=${x.sub ? x.sub.length + '子' : 'null'}  B.sub=${y.sub ? y.sub.length + '子' : 'null'}`, ctx);
      } else {
        const pa = x.payload || Buffer.alloc(0), pb = y.payload || Buffer.alloc(0);
        if (!pa.equals(pb)) push('裸 payload 变化', p, `${pa.length}B ${hex(pa)} → ${pb.length}B ${hex(pb)}`, ctx);
      }
    }
  }
  // 比完之后，如果 B 多出来的字段也报一下（上面只报了条数）
}

console.log('A = ' + path.basename(FA) + '（' + fs.statSync(FA).size + ' 字节，体 ' + A.hdr[4] + '）');
console.log('B = ' + path.basename(FB) + '（' + fs.statSync(FB).size + ' 字节，体 ' + B.hdr[4] + '）');
console.log('外层头 A=' + A.hdr.join(',') + '   B=' + B.hdr.join(','));
console.log('尾 A=' + A.trailerLen + 'B   B=' + B.trailerLen + 'B');
console.log('');

// 顶层也要比
walkTree(A.tree, B.tree, '/', [], 0);

console.log('比过的字段节点：' + compared + ' 个');
console.log('差异：' + diffs.length + ' 处');
if (diffs.length === 0) {
  console.log('\n★★★ 两个文件**字段级完全一致**（连 float 的位模式都一样）。');
  process.exit(0);
}
console.log('');
const byKind = new Map();
for (const d of diffs) byKind.set(d.kind, (byKind.get(d.kind) || 0) + 1);
for (const [k, c] of byKind) console.log('  · ' + k + ' × ' + c);
console.log('');
for (const d of diffs.slice(0, MAX)) {
  console.log('  [' + d.kind + '] ' + d.where);
  console.log('      控件：' + d.ctx);
  console.log('      ' + d.detail);
}
if (diffs.length > MAX) console.log('  …还有 ' + (diffs.length - MAX) + ' 处（用 --max= 调）');
process.exit(3);
