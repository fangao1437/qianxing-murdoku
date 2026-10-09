// tools/gil/fix_clue_tpl_origin.mjs —— 把列表项模板 `clue` 归零到 (0,0)
//
// ════════════════════════════════════════════════════════════════════════════
// ★★★ 为什么做这个（用户 2026-10-10 的关键观察 ✓）
// ════════════════════════════════════════════════════════════════════════════
//
//   用户原话 ✓：
//     「网格视窗的**五项预览是都在范围内的**，没有问题 ✓
//      但**模板确实从 -2 位置开始填的** ✗ —— 这一点似乎与不裁剪的解释**不相干** ✓
//      ★ 我只设了**五项**且视窗**装得下**，**为什么会从负数区域开始填模板**？」
//
//   ⇒ ★★ 这一问**指向布局原点** ✓：
//     · ★ 视窗装得下 ✓、预览 5 项都在范围内 ✓ ⇒ ★ **不该有负数** ✗
//     · ★ 而实际**从 −2 开始填** ✗ ⇒ ★ **列表项的起点不在视窗顶部** ✓
//     · ⇒ ★ **带了一个偏移** ✓ —— ★ 那偏移只能是**模板自己的位置** ✓✓
//
//   ★ 存档实测（`246`/`248`/`249` 三份一致 ✓）：
//       模板 `clue`   #1073742421   ★ **pos = (-6, 212)**  ✗ **不在 (0,0)**
//       容器 `clues`  #1073742359   pos = (-570, -61.1)  size = 400×544
//       网格 `clues.grid` #1073742420  pos = (0, 0)  size = 400×544
//     ⇒ ★★ **`212` ≈ `clues` 容器的【上边缘】(= -61.1 + 272 = +210.9)** ✓
//       ⇒ ★ 模板坐在**容器上边缘** ✗ ⇒ ★ 若引擎以它为原点，
//         **前几项就会被推到负数区** ✓✓ —— ★ **与用户观察完全吻合** ✓
//
//   ★ 资料员早先提过「★ 引擎以**模板位置**为原点」这条（**假说 A** ✓）
//     ★ 我当时**用官方文本把它否掉了** ✗（官方《网格视窗控件》只写"列表项大小 ＋ 边距"✓
//        没提模板位置 ✓）⇒ ★ **但你这条实测把它救回来了** ✓✓
//     ⚠️ 而我早先的否证理由是"几何上也解释不了'上面还有内容'"✗ ——
//        ★ 那是因为我**假设**了原点在顶部 ✓ ⇒ ★ **假设错了，结论就错了** ✓
//
//   ⇒ ★ 修法 ✓：★ **把模板归零到 (0,0)** ✓
//     ★ 这是**只改一个值**的编辑 ✓（最安全那一档 ✓ 不加不删任何字段 ✓）
//     ★ 而且**可逆** ✓（原值记在下面 ✓）
//
//   ★ 原值备查 ✓：pos = **(-6, 212)**（x=-6 ✓ y=212 ✓）
//     ⇒ ★ 要回退就把这两个数写回去 ✓
//
// 用法：
//   node tools/gil/fix_clue_tpl_origin.mjs --in=<存档> --dump
//   node tools/gil/fix_clue_tpl_origin.mjs --in=<存档> --out=<输出>

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, stateBlocks, pairOf, pairValue } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const arg = (k, d) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : d; };
const P = (p) => (p == null ? null : (path.isAbsolute(p) ? p : path.resolve(ROOT, p)));

const IN = P(arg('in'));
const OUT = P(arg('out', arg('in')));
const DUMP = argv.includes('--dump');
const TPL = arg('tpl', 'clue');
const WANT_X = Number(arg('x', '0'));
const WANT_Y = Number(arg('y', '0'));

if (!IN) { console.error('用法: node tools/gil/fix_clue_tpl_origin.mjs --in=<存档> [--out=<输出>] [--dump]'); process.exit(1); }

const g = readGil(IN);
console.log('存档：' + path.basename(IN) + '（记录 ' + g.recs.length + ' 条）');

const tpl = g.recs.find((r) => r.name === TPL);
if (tpl === undefined) { console.error('✗ 找不到模板 ' + TPL); process.exit(2); }

// 定位列表项模板的"位置"叶子：在它第 1 个状态块的 `/501/502` 里，字段 `#504`（x,y 一对）
const geo = (rec) => {
  const o = []; stateBlocks(rec.field.sub, o);
  if (!o[0]) return null;
  return { blk: o[0], x: pairOf(o[0], 504), y: pairOf(o[0], 505) };
};
const posPair = (rec) => {
  const o = []; stateBlocks(rec.field.sub, o);
  if (!o[0]) return null;
  return pairOf(o[0], 504);
};

const before = posPair(tpl);
if (before === null) { console.error('✗ 模板里找不到位置对'); process.exit(2); }
const bx = pairValue(before, 0), by = pairValue(before, 1);
console.log('模板 ' + TPL + '  #' + tpl.id + '　★ 位置 = (' + bx + ', ' + by + ')');

// 顺带把容器与网格的位置打出来，便于对照
for (const nm of ['clues', 'clues.grid']) {
  const r = g.recs.find((x) => x.name === nm);
  if (r === undefined) continue;
  const p = posPair(r);
  console.log('  ' + nm.padEnd(12) + ' 位置 = (' + (p ? pairValue(p, 0) : '?') + ', ' + (p ? pairValue(p, 1) : '?') + ')');
}

if (DUMP) { console.log('\n（--dump 模式，未写文件）'); process.exit(0); }

// ★ 只改值 ✓ —— 不加叶子、不删叶子 ✓
const setPair = (pair, x, y) => {
  if (pair === null) return false;
  let n = 0;
  for (const f of pair.sub || []) {
    if (f.field === 501 && f.wt === 5) { f.f = x; n++; }
    else if (f.field === 502 && f.wt === 5) { f.f = y; n++; }
  }
  return n >= 2;
};
const ok = setPair(before, WANT_X, WANT_Y);
console.log('\n写入 (' + WANT_X + ', ' + WANT_Y + ') ⇒ ' + (ok ? '成功 ✓' : '失败 ✗（位置对里没有 501/502 两个浮点）'));

const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(OUT, buf);
console.log('已写出：' + path.basename(OUT) + '（' + fs.statSync(OUT).size + ' 字节）');

// ── 复读核对（★ 从磁盘重读 ✓）──────────────────────────────────────────────
const g2 = readGil(OUT);
const t2 = g2.recs.find((r) => r.name === TPL);
const after = posPair(t2);
const ax = pairValue(after, 0), ay = pairValue(after, 1);
const good = String(ax) === String(WANT_X) && String(ay) === String(WANT_Y);
console.log('\n── 复读核对（从磁盘重读）──');
console.log('  ' + (good ? '✅' : '❌') + ' 模板 ' + TPL + ' 位置 = (' + ax + ', ' + ay + ')'
  + '　（原值 (' + bx + ', ' + by + ')，要回退就写回这两个数 ✓）');
console.log('  ⓘ 其他字段**一个都没动** ✓（只改值 ✓ 不加不删 ✓）');
console.log('\n' + (good ? '★ 模板已归零 ✓ —— 请真机看"还从负数区开始填吗"' : '❌ 没写进去'));
console.log('⚠️ 交付前**必须**跑：node tools/gil/roundtrip.mjs ' + path.basename(OUT));
process.exit(good ? 0 : 3);
