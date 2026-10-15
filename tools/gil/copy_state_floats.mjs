// tools/gil/copy_state_floats.mjs —— 把【原型】状态块里的浮点对补进【新控件】（**只补缺失/NaN 的**）
//
// 为什么需要它（2026-10-15 真机判决，第三次修复）：
//   ★ `add_button.mjs` 克隆 `home.select` 时**只克隆了记录本身与子控件** ✗
//     ★ 没有把状态块里那几对"布局浮点"补上 ⇒ ★ 新控件的它们是 **NaN** ✓
//   ★ 对照实测（`374-结算按钮-v243.gil`，四个状态块 **完全一致**）：
//       home.select : #501/#1..3 = 1,1,1   #502 = 0.5,0.5   #503 = 0.5,0.5   #506 = 0.5,0.5
//       settle.btn  : #501/#1..3 = NaN     #502 = NaN,NaN   #503 = NaN,NaN   #506 = NaN,NaN
//   ⇒ ★★ 结局：★ **位置与尺寸（#504/#505）我写对了、设备回读也是对的** ✓
//      ★ 但**锚点/轴心是 NaN** ✗ ⇒ ★ 命中判定算不出矩形 ⇒ ★ 整屏都算作它 ✓✓
//      （★ 这正是"`raycast = false` 没挡住"＋"换层序也没用"的原因 ✓）
//
// ⚠️ 规矩（本仓的老规矩 ✓）：
//   · ★ **只补 NaN / 缺失**的那些 ✓ —— 有值的字段**一个字都不动** ✓
//   · ★ 只按**状态块内相同路径**抄 ✓（`#50x/#50y` 位置固定 ✓）
//   · ★ 写盘走 `writeGil()`（往返 ＋ 从磁盘重读 ＋ diff 三道闸 ✓）
//
// 用法：
//   node tools/gil/copy_state_floats.mjs --in=<in.gil> --out=<out.gil> --from=home.select --to=settle.btn [--dry]
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil } from './gilread.mjs';
import { writeGil } from './gilwrite.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3).replace(/^"|"$/g, '') : null; };
const DRY = argv.includes('--dry');

const IN = argOf('in'), OUT = argOf('out'), FROM = argOf('from'), TO = argOf('to');
if (!IN || !OUT || !FROM || !TO) {
  console.error('用法: node tools/gil/copy_state_floats.mjs --in=<in.gil> --out=<out.gil> --from=<原型名> --to=<目标名> [--dry]');
  process.exit(1);
}

const g = readGil(path.isAbsolute(IN) ? IN : path.join(ROOT, IN));
const src = g.byName.get(FROM), dst = g.byName.get(TO);
if (!src) { console.error('❌ 找不到原型 ' + FROM); process.exit(2); }
if (!dst) { console.error('❌ 找不到目标 ' + TO); process.exit(3); }

// 把一个状态块摊平成 path(不含块序号) → wt5 字段 的映射
function floats_(blk) {
  const m = new Map();
  (function w(fs, p) {
    for (const f of fs) {
      if (f.wt === 5) m.set(p + '/#' + f.field, f);
      if (f.sub) w(f.sub, p + '/#' + f.field);
    }
  })(blk.sub, '');
  return m;
}

let filled = 0, kept = 0, missing = 0;
const detail = [];
const nBlocks = Math.min(src.states.length, dst.states.length);
if (src.states.length !== dst.states.length) {
  console.error('❌ 状态块数量不同：原型 ' + src.states.length + ' 目标 ' + dst.states.length);
  process.exit(4);
}
for (let i = 0; i < nBlocks; i++) {
  const a = floats_(src.states[i]);
  const b = floats_(dst.states[i]);
  for (const [p, bs] of b) {
    // ★ 位置/尺寸（#504/#505）**不碰** ✓ —— 那是脚本/工具写进去的正确值 ✓
    if (p.indexOf('/#504/') === 0 || p.indexOf('/#505/') === 0) { kept++; continue; }
    if (Number.isFinite(bs.f)) { kept++; continue; }          // ★ 有值就不动 ✓
    const as = a.get(p);
    if (!as || !Number.isFinite(as.f)) { missing++; continue; }  // ★ 原型也没有 ⇒ 不动，记账 ✓
    detail.push('blk' + i + ' ' + p + ' : ' + bs.f + ' → ' + as.f);
    bs.f = as.f;
    filled++;
  }
}

console.log('原型 ' + FROM + ' #' + src.id + ' → 目标 ' + TO + ' #' + dst.id);
console.log('  补上 ' + filled + ' 个浮点 / 保持 ' + kept + ' 个 / 原型也没有 ' + missing + ' 个');
for (const d of detail.slice(0, 16)) console.log('    ' + d);
if (detail.length > 16) console.log('    …（共 ' + detail.length + ' 条）');

if (DRY) { console.log('--dry：不写文件 ✓'); process.exit(0); }
if (filled === 0) { console.log('（没有需要补的 ✓ 不写文件）'); process.exit(0); }

const rep = writeGil(g, path.isAbsolute(OUT) ? OUT : path.join(ROOT, OUT), {
  label: '补状态块浮点：' + TO + ' ← ' + FROM,
  assert: (g2) => {
    const bad = [];
    const s2 = g2.byName.get(FROM), d2 = g2.byName.get(TO);
    // ① 目标里 NaN/缺失的布局浮点应当**一个不剩** ✓（#504/#505 除外）
    let left = 0;
    for (let i = 0; i < d2.states.length; i++) {
      const a = floats_(s2.states[i]), b = floats_(d2.states[i]);
      for (const [p, bs] of b) {
        if (p.indexOf('/#504/') === 0 || p.indexOf('/#505/') === 0) continue;
        if (!Number.isFinite(bs.f) && a.has(p) && Number.isFinite(a.get(p).f)) left++;
      }
    }
    if (left > 0) bad.push('回读仍有 ' + left + ' 个该补没补的浮点');
    // ② 位置/尺寸必须**一位不变** ✓
    const geom = (r) => r.states.map((blk) => {
      const pair = (n) => { const p = blk.sub.find((x) => x.field === n); if (!p || !p.sub) return 'null';
        return p.sub.filter((x) => x.wt === 5).map((x) => x.f).join(','); };
      return pair(504) + '|' + pair(505);
    }).join('  ');
    const before = geom(dst), after = geom(d2);
    if (before !== after) bad.push('几何被改动了 ✗ ' + before + ' → ' + after);
    // ③ 原型必须**一字未动** ✓
    if (geom(src) !== geom(s2)) bad.push('原型被改动了 ✗');
    return bad.length ? bad.join('；') : true;
  },
});
console.log('  输出：' + path.basename(OUT) + '（' + rep.bytes + ' 字节，记录 ' + rep.recs + ' 条，字段差异 ' + rep.diffs + ' 处）');
