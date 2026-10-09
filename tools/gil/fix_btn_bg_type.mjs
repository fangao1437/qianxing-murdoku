// tools/gil/fix_btn_bg_type.mjs —— 给四键的 `bg` 补上 **`imageType = 拉伸`**（★ 这是"没图"的真因 ✓）
//
// ════════════════════════════════════════════════════════════════════════════
// ★★ 真因（2026-10-09，逐字段比对 + 素材库查证 ✓ 两条独立证据指向同一处）
// ════════════════════════════════════════════════════════════════════════════
//
// ① **逐字段比对**（`_cmp_bg.mjs`，递归摊平"渲染正常的 bg" vs "不渲染的 bg"）
//    基准 = `home.select.bg`（用户一直在用、看得见 ✓）
//    差异只有三处，其中一处是**我缺了一个叶子** ✗：
//        它 有 、我 没有 ：`/505/503/84/504 = 1`
//    而 `/505/503/84` 正是**图片那一段**（`/502`=imageSource ✓ `/503`=imageId ✓）
//    ⇒ ★ `#504` 是**紧挨着图 id 的另一个图片属性** ✓
//
// ② **素材库查证**（`tools/qx/library-catalog.json` ✓）
//        `/images/107179 = {"id":107179,"img":"sprite/107179.png",
//                           "border":"border/107179.json"}`
//    ⇒ ★★ **`107179` 带 `border`（= 九宫格配置）** ✗✓
//      而别的素材（如 `100109` 那类图标）**没有 `border`** ✓
//
// ③ **项目自己的注释早就点到了这件事** ✓
//    `ui_controller.lua:2997`：★ 素材 `107179`（760×152，**两端全圆角**、米白）✓
//    `ui_controller.lua:4390`：★「**乙：图设上了但没渲染** ⇒ 应读到 `107179` ✓」
//    ★ 而格子那段的日志说明也写着 ✓：
//      「格面用的是【基础】…**只有当你给 face 换了九宫格/三宫格素材、想让四角不被压扁时，
//        才需要把图片类型改成【拉伸】**」✓✓
//
// ⇒ ★★ **结论**：`107179` 是**九宫格素材**，而 `bg` 的图片类型还是**默认的【基础】** ✗
//    ⇒ **引擎按"基础"去铺一张九宫格图 ⇒ 画面上什么都没有** ✓
//    ⇒ 这就是"imageId 回读=107179 却没图"的答案 ✓
//
// ⚠️ **为什么脚本那条路修不好** ✗：`SetImage(src, id)` **只设图和源，不设图片类型** ✓
//    ⇒ 所以 `main.lua` 的入口层那段（回读=107179 ✓）和 `ui_controller.lua` 的
//      `set_image_deep(bg, 107179, …)` **都改不了这个类型** ✓
//    ⇒ ★ 只能**在存档里写** ✓ —— 正好符合用户那条"能走存档就走存档" ✓
//
// 改法（★ **只加一个叶子** ✓ 不删任何东西 ✓）：
//   把 `home.select.bg` 的 `/505/503/84/504` 克隆到四键的 `bg` 上 ✓
//   地址：`#505` → `#503` → `#84` 这个节点里，加一个 `#504 = 1` ✓
//
// 用法：
//   node tools/gil/fix_btn_bg_type.mjs --in=<存档> --dump
//   node tools/gil/fix_btn_bg_type.mjs --in=<存档> --out=<输出>

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, cloneField, stateBlocks, pairOf, pairValue } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const arg = (k, d) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : d; };
const P = (p) => (p == null ? null : (path.isAbsolute(p) ? p : path.resolve(ROOT, p)));

const IN = P(arg('in'));
const OUT = P(arg('out', arg('in')));
const DUMP = argv.includes('--dump');
const KEYS = (arg('keys') || 'modal.exit,modal.save,modal.settle,modal.cancel').split(',').map((s) => s.trim()).filter(Boolean);
const REF = arg('ref', 'home.select');          // ★ 渲染正常的按钮（基准 ✓）
const IMG_NODE = [505, 503, 84];                 //    图片那一段（`/502`=源 `/503`=id ✓）
const TYPE_LEAF = 504;                           // ★ 缺的就是它（1 = 拉伸/九宫格 ✓）

if (!IN) { console.error('用法: node tools/gil/fix_btn_bg_type.mjs --in=<存档> [--out=<输出>] [--dump]'); process.exit(1); }

const g = readGil(IN);
console.log('存档：' + path.basename(IN) + '（记录 ' + g.recs.length + ' 条）');

// ── 按**字段号**下钻（★ 不能按深度 ✗ —— `gen_icons.mjs` 那条教训 ✓）────────
function nodesAt(fields, p) {
  let level = fields;
  for (let i = 0; i < p.length; i++) {
    const hits = level.filter((f) => f.field === p[i] && f.sub);
    if (i === p.length - 1) return hits;
    level = hits.flatMap((f) => f.sub);
  }
  return [];
}
const childOf = (name, cname) => {
  const rec = g.byName.get(name);
  if (!rec) return null;
  return g.recs.find((r) => r.parentId === rec.id && r.name === cname) || null;
};
// 取"图片那一段"节点（`/505/503/84` ✓）
const imgNodeOf = (rec) => nodesAt(rec && rec.field && rec.field.sub, IMG_NODE)[0] || null;
const typeLeafOf = (rec) => {
  const nd = imgNodeOf(rec);
  if (!nd) return null;
  return (nd.sub || []).find((f) => f.field === TYPE_LEAF && f.wt === 0) || null;
};
const imgIdOf = (rec) => {
  const nd = imgNodeOf(rec);
  if (!nd) return null;
  const f = (nd.sub || []).find((x) => x.field === 503 && x.wt === 0);
  return f ? String(f.num) : null;
};
const geo = (rec) => {
  const o = []; stateBlocks(rec.field.sub, o);
  if (!o[0]) return '（无状态块）';
  return 'pos=(' + pairValue(pairOf(o[0], 504), 0) + ',' + pairValue(pairOf(o[0], 504), 1) + ')'
    + ' size=(' + pairValue(pairOf(o[0], 505), 0) + '×' + pairValue(pairOf(o[0], 505), 1) + ')';
};

// ── 基准：从严禁"没图"的那个按钮上取现成的 `#504` 叶子 ✓ ─────────────────
const refBg = childOf(REF, 'bg');
if (!refBg) { console.error('✗ 找不到基准 ' + REF + '.bg'); process.exit(2); }
const refLeaf = typeLeafOf(refBg);
if (!refLeaf) {
  console.error('✗ 基准 ' + REF + '.bg 里也没有 /505/503/84/504 —— 换 --ref= 再试');
  process.exit(2);
}
console.log('基准：' + REF + '.bg  #' + refBg.id + '  imageId=' + imgIdOf(refBg)
  + '  **图片类型叶子 `/505/503/84/504` = ' + refLeaf.num + '** ✓（这就是四键缺的那一个）');

console.log('\n── 改前 ──');
for (const k of KEYS) {
  const bg = childOf(k, 'bg');
  if (!bg) { console.log('  ✗ ' + k + '.bg 不存在'); continue; }
  const t = typeLeafOf(bg);
  console.log('  ' + k.padEnd(14) + ' bg#' + bg.id + '  ' + geo(bg)
    + '  imageId=' + imgIdOf(bg)
    + '  图片类型=' + (t ? String(t.num) : '**缺** ✗'));
}

if (DUMP) { console.log('\n（--dump 模式，未写文件）'); process.exit(0); }

// ── 写：只**追加**那个叶子 ✓ ───────────────────────────────────────────────
let fixed = 0, skipped = 0;
for (const k of KEYS) {
  const bg = childOf(k, 'bg');
  if (!bg) continue;
  if (typeLeafOf(bg) !== null) { skipped++; continue; }        // ★ 幂等：已有就不动 ✓
  const nd = imgNodeOf(bg);
  if (!nd) { console.error('  ✗ ' + k + '.bg 里找不到 /505/503/84 节点'); continue; }
  if (!nd.sub) nd.sub = [];
  nd.sub.push(cloneField(refLeaf));
  fixed++;
}
console.log('\n补上图片类型叶子的 bg：' + fixed + ' 个（本来就有、没动的：' + skipped + ' 个）');

const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(OUT, buf);
console.log('已写出：' + path.basename(OUT) + '（' + fs.statSync(OUT).size + ' 字节）');

// ── 复读核对（★ 从磁盘重读 ✓）──────────────────────────────────────────────
const g2 = readGil(OUT);
console.log('\n── 复读核对（从磁盘重读）──');
let bad = 0;
for (const k of KEYS) {
  const rec = g2.byName.get(k);
  const bg = rec && g2.recs.find((r) => r.parentId === rec.id && r.name === 'bg');
  const t = bg && typeLeafOf(bg);
  const ok = t !== null && String(t.num) === String(refLeaf.num);
  if (!ok) bad++;
  console.log('  ' + (ok ? '✅' : '❌') + ' ' + k.padEnd(14)
    + ' 图片类型=' + (t ? String(t.num) : '**缺**') + '  imageId=' + (bg ? imgIdOf(bg) : '—')
    + '  ' + (bg ? geo(bg) : ''));
}
console.log('\n' + (bad === 0 ? '★ 四键的图片类型都补上了 ✓' : '❌ 还有 ' + bad + ' 个没补上'));
console.log('⚠️ 交付前**必须**跑：node tools/gil/roundtrip.mjs ' + path.basename(OUT));
process.exit(bad === 0 ? 0 : 3);
