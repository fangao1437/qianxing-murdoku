// 673 · 基于 672 最新存档的两处实机整改：注释票券 + 拍立得火漆（用户称「底图」红圆）
//
// 输入 672_梯形与异色区/672_梯形与异色区.gil（7052 条，最新可导入成果）
// 输出 673_注释按钮与底图.gil（记录数不变 7052，Lua/文本/层序/childList 全不动）
//
// ★ 原则：质量优先，其次最少图元。本轮不新增任何记录，只复用已有层改形改色 + 隐藏冗余层：
//   票券可见层 41 → 16，火漆可见层 47 → 11。
//
// ① 注释票券（设计图实测：同色波浪撕边 + 两条 45° 斜分界，无浅色竖带、无黑色虚线描边）
//   ★ 根因：664 用「纯色背景矩形 + 圆齿」做凹口，但票券两端真实背景跨
//     #DC642A(橙棕) / #E6B33B(橙黄) / #F5EBC7(米白) 多色渐变 ⇒ 任何纯色都会形成白/黄竖带。
//     673 改为「主体矩形收窄 + 票券色凸齿外凸」，凹口直接露出真实背景，完全不画背景色。
//   - 主体 140→124、描边 146→124（只留上下 3px 深棕边）；两端各 3 枚齿后总宽仍 ~146，不变。
//   - 23 枚 100003 拟合三角 → 只留 2 枚解析等腰直角三角（671 方法，rot 归一化到 [0,360)）
//     底 #8C2800 → mid #AF3200（26.6%）→ hi #CB4C19（9.8%），设计图实测 26.2% / 10.1%
//   - 每端 3 枚深棕描边齿(18×18) + 3 枚票券色齿(15×15)，齿自带描边；凹口露出真实背景
//   - clues.help617 官方问号与 clues.help627.hit 热区逐字节不动
//
// ② 火漆（设计图实测：浅起伏蜡封、左右弧形亮光、上下主体色、柔和暗压印）
//   - 12 枚重叠 106 正圆深色外沿 → 10 枚 R=30 / d=44 大幅重叠椭圆（峰谷 ~2.8px，不是花朵）
//     0°/180° #D70601（左右最亮，最后画）、四角 #B40806、上下 #AA0400
//   - 隐藏 12 lobe / 16 ring / 2 hot / center / stamp.rim（去掉完整亮环与突兀椭圆高光块）
//   - 保留 core 92 圆盖住内圈（亮弧只剩外缘 ~9px）、顶部鼓包；stamp.core 改 64×58 #A80300 柔压印
//
// 仓库工具：gilread/gilwrite 读写、ops.js 隐藏、fit-primitive-shape.mjs 的思路（本轮改用解析等腰直角三角，
//           比 23 枚拟合三角少一个数量级且避开非标准旋转角）、@napi-rs/canvas 做像素实测与离线渲染。
//
// 用法：FORCE=1 node 构建673.mjs   /   node 构建673.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/673_注释按钮与底图');
const INPUT = path.join(ROOT, 'qianxing-murdoku/672_梯形与异色区/672_梯形与异色区.gil');
const OUTPUT = path.join(DIR, '673_注释按钮与底图.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, setPair, encodeMsg, findChildListTop, asIdList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

// ── 设计图实测参数 ────────────────────────────────────────────────────────
// 票券：中心 (384,211)、原 140×66 → 673 主体 124×66、rot −13（渲染器 ctx.rotate(−rot) ⇒ 屏幕顺时针 +13°）
// 两端齿外凸到 ±73 ⇒ 总宽仍 ≈146，与设计图/实机一致
const T = { cx: 384, cy: 211, w: 124, h: 66, rot: -13, originalW: 140 };
const C = { base: '#8C2800', mid: '#AF3200', hi: '#CB4C19', stroke: '#592520' };
// 实测背景（仅作诊断记录，本轮不画背景色）：左 #DC642A→#F5EBC7、右 #E6B33B→#F5EBC7 渐变
const BG_SAMPLES = { leftTop: '#DC642A', leftBottom: '#F5EBC7', rightTop: '#E6B33B' };
// 火漆：中心 (1326,342)，原外径 106（R=53）
const W = { cx: 1326, cy: 342 };
// 压印纯色需比主体暗 ~14/255 才在设计稿观感下可见（#A60400 只差 4/255，离线渲染几乎看不见）
const WC = { main: '#AA0400', rim: '#B40806', hot: '#D70601', stamp: '#9C0400' };

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recTop = g.tree.find(q => q.field === 9);
const recTopOrderBefore = recTop.sub.slice();
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
const cache = new Map();
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (cache.has(r.id)) return cache.get(r.id);
  const st = states(r)[0], p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  cache.set(r.id, res); return res;
}
function screenGeom(r) {
  const st = states(r)[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  if (!p || !s) return null;
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  return [px + pairValue(p, 0), py - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)];
}
function setGeomScreen(r, cx, cy, w, h) {
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - px, py - cy);
    setPair(pairOf(st, 505), w, h);
  }
  cache.delete(r.id); touch(r);
}
function setRot(r, deg) {
  for (const st of states(r)) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }]; rf.payload = null; rf.len = 5;
  }
  touch(r);
}
function retint(r, hex, imageId = null) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(hex));
  if (imageId !== null) { setNum(p, 503, imageId); setNum(p, 504, 1); }
  touch(r);
}
const hidden = [], shown = [], modified = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function hide(r) { if (!isHiddenRecord(r.field)) { setHiddenRecord(r.field, true); hidden.push(r.name); } touch(r); }
function show(r) { if (isHiddenRecord(r.field)) { setHiddenRecord(r.field, false); shown.push(r.name); } touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
// 票券局部坐标 → 屏幕坐标（663/664 已实机验证：角度传 −T.rot）
const rotPt = (lx, ly) => {
  const a = -T.rot * Math.PI / 180;
  return [T.cx + lx * Math.cos(a) - ly * Math.sin(a), T.cy + lx * Math.sin(a) + ly * Math.cos(a)];
};
const unrotPt = (x, y) => {
  const a = -T.rot * Math.PI / 180, dx = x - T.cx, dy = y - T.cy;
  return [dx * Math.cos(a) + dy * Math.sin(a), -dx * Math.sin(a) + dy * Math.cos(a)];
};
// 100003 等腰三角：底边 E1→E2、顶点 P，h = 顶点到底边的高，中心 = 底边中点与顶点的中点
function triParams(E1, E2, P) {
  const M = [(E1[0] + E2[0]) / 2, (E1[1] + E2[1]) / 2];
  const dx = P[0] - M[0], dy = P[1] - M[1], d = Math.hypot(dx, dy);
  let rot = Math.atan2(-dx / d, -dy / d) * 180 / Math.PI;
  rot = ((rot % 360) + 360) % 360;             // 归一化，避开历史「负角不出图」
  return { cx: (M[0] + P[0]) / 2, cy: (M[1] + P[1]) / 2,
    w: Math.hypot(E2[0] - E1[0], E2[1] - E1[1]), h: d, rot, verts: [E1, E2, P] };
}

// ── ① 注释票券 ───────────────────────────────────────────────────────────
// 主体收窄到 124（±62）后，两条 45° 斜分界的三角顶点同步收进 ±62，避免画到票券外
const MID = triParams(rotPt(4, -33), rotPt(-62, 33), rotPt(-62, -33));   // 中阶，斜边长 66√2，26.6%
const HI = triParams(rotPt(-22, -33), rotPt(-62, 7), rotPt(-62, -33));   // 亮阶，斜边长 40√2，9.8%
const fitNames = [...g.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')).map(r => r.name)];
if (fitNames.length !== 23) throw Error('664 拟合三角数量不符：' + fitNames.length);
for (const n of fitNames)
  if (n !== 'art664.tab.mid.fit01' && n !== 'art664.tab.hi.fit15') hide(named(n));
reshape(named('art664.tab.mid.fit01'), MID, C.mid);
reshape(named('art664.tab.hi.fit15'), HI, C.hi);
function reshape(r, o, color) {
  setGeomScreen(r, o.cx, o.cy, o.w, o.h);
  setRot(r, o.rot);
  retint(r, color, 100003);
}
// 主体/描边收窄：凹口（x∈[62,73] 的齿间）直接露出真实背景，不画任何背景色
const tabMain = named('art641.game.help.tab'), tabOutline = named('art661.tab.outline');
if (Math.abs(screenGeom(tabMain)[2] - T.originalW) > 0.01 || Math.abs(screenGeom(tabOutline)[2] - 146) > 0.01)
  throw Error('票券主体几何与 672 不符');
setGeomScreen(tabMain, T.cx, T.cy, T.w, T.h); setRot(tabMain, T.rot); retint(tabMain, C.base, 100001);
setGeomScreen(tabOutline, T.cx, T.cy, T.w, T.h + 6); setRot(tabOutline, T.rot); retint(tabOutline, C.stroke, 100001);
// 每端 3 枚深棕描边齿（26×26）+ 3 枚票券色齿（23×23）；l0/r0 与 tooth.l3/r3 隐藏
// ★ 齿必须相邻重叠（间距 22 < 直径 26/23）才连成连续波浪边，否则会退化成 663 的「分离圆珠串」
const edgeNames = g.recs.filter(r => /^art663\.tab\.edge\./.test(r.name || '')).map(r => r.name).sort();
const toothNames = g.recs.filter(r => /^art663\.tab\.tooth\./.test(r.name || '')).map(r => r.name).sort();
if (edgeNames.length !== 8 || toothNames.length !== 8) throw Error('票券撕边层数量不符');
const NOTCH_LY = [-22, 0, 22];
const EDGE_SPEC = [];
for (const [side, tag] of [[-1, 'l'], [1, 'r']]) {
  hide(named(`art663.tab.edge.${tag}0`));       // 弃用 664 纯色背景矩形（白/黄竖带根因）
  for (let i = 0; i < 3; i++) {
    const [sx, sy] = rotPt(side * 58, NOTCH_LY[i]);
    const rim = named(`art663.tab.edge.${tag}${i + 1}`);
    // 扁椭圆（h>w）：相邻大幅重叠 ⇒ 深棕描边连成一条连续波浪线，而不是「一圈圈独立圆珠」
    show(rim); setGeomScreen(rim, sx, sy, 24, 30); setRot(rim, 0); retint(rim, C.stroke, 100002);
    const tooth = named(`art663.tab.tooth.${tag}${i}`);
    // 齿与票券主体同色：不同色会让齿变成一串独立圆点（第二轮渲染实测）
    show(tooth); setGeomScreen(tooth, sx, sy, 21, 27); setRot(tooth, 0);
    retint(tooth, C.base, 100002);
    EDGE_SPEC.push({ name: tooth.name, rim: rim.name, cx: +sx.toFixed(2), cy: +sy.toFixed(2),
      rimSize: [24, 30], toothSize: [21, 27], color: C.base });
  }
  hide(named(`art663.tab.tooth.${tag}3`));
}

// ── ② 火漆 / 底图红圆 ───────────────────────────────────────────────────
// 10 枚大幅重叠椭圆：R=30 / d=44 ⇒ 外缘 52（与原 106 圆半径 53 一致），相邻中心距 18.5，
// 峰谷 ~2.8px ⇒ 浅起伏蜡封而非「8 瓣花朵/齿轮」（663 踩过：R=38 会成花）。
// ★ 10 枚全部同色 #B40806：按方位分色会让浅起伏在视觉上变成「10 色花瓣」（第二轮渲染实测）。
//   左右最亮 #D70601 改由 2 枚独立长椭圆给出（贴边弧带，不随瓣走）。
const WAX_R = 30, WAX_D = 44;
const LOBES = [
  { deg: 36 }, { deg: 72 }, { deg: 108 }, { deg: 144 }, { deg: 216 },
  { deg: 252 }, { deg: 288 }, { deg: 324 }, { deg: 0 }, { deg: 180 },
].map(o => ({ ...o, color: WC.rim }));
const WAX_SPEC = [];
LOBES.forEach((L, i) => {
  const r = named(`art663.wax.edge.${i}`);
  const a = L.deg * Math.PI / 180, cx = W.cx + WAX_R * Math.cos(a), cy = W.cy + WAX_R * Math.sin(a);
  show(r); setGeomScreen(r, cx, cy, WAX_D, WAX_D); setRot(r, 0); retint(r, L.color, 100002);
  WAX_SPEC.push({ name: r.name, deg: L.deg, cx: +cx.toFixed(2), cy: +cy.toFixed(2),
    w: WAX_D, h: WAX_D, color: L.color });
});
for (let i = 10; i < 12; i++) hide(named(`art663.wax.edge.${i}`));
for (const n of g.recs.filter(r => /^art663\.wax\.lobe\./.test(r.name || '')).map(r => r.name)) hide(named(n));
for (const n of g.recs.filter(r => /^art664\.wax\.ring\./.test(r.name || '')).map(r => r.name)) hide(named(n));
// 左右最亮弧带：2 枚短月牙椭圆（12×44 @ x=±45），解析保证整枚落在 R=52 蜡封内
// （14×64 会在上下端越出圆轮廓，渲染成两根竖直硬条；本参数 θ=45° 时 x²+y²=2667<2704）
for (const [n, dx] of [['art664.wax.hot.l', -45], ['art664.wax.hot.r', 45]]) {
  const r = named(n);
  show(r); setGeomScreen(r, W.cx + dx, W.cy, 12, 44); setRot(r, 0); retint(r, WC.hot, 100002);
}
// core 92→84（半径 46→42）⇒ 亮红外环宽 6→10px，贴近设计稿剖面
const waxCore = named('art663.wax.core');
setGeomScreen(waxCore, W.cx, W.cy, 84, 84); setRot(waxCore, 0); retint(waxCore, WC.main, 100002);
for (const n of ['art664.wax.center', 'art664.wax.stamp.rim']) hide(named(n));
// 柔和暗压印（去掉 664 的亮边+暗芯双硬环）
const stampCore = named('art664.wax.stamp.core');
show(stampCore); setGeomScreen(stampCore, W.cx, W.cy, 64, 58); setRot(stampCore, 0);
retint(stampCore, WC.stamp, 100002);
// 顶部鼓包保持 672 原样（30×30 #B40806 @ (1326,296)，外缘半径 61 ⇒ 顶部鼓出 ~9px）

// ── 几何闸门 ─────────────────────────────────────────────────────────────
const inTicket = (p, eps = 0.02) => {
  const [lx, ly] = unrotPt(p[0], p[1]);
  return Math.abs(lx) <= T.w / 2 + eps && Math.abs(ly) <= T.h / 2 + eps;
};
const triVertsInside = [...MID.verts, ...HI.verts].every(p => inTicket(p));
if (!triVertsInside) throw Error('分界三角顶点溢出票券');
// 三角面积占比（自检：与设计图实测 26.2% / 10.1% 同量级）
const areaTicket = T.w * T.h;
const triArea = t => Math.abs((t.verts[1][0] - t.verts[0][0]) * (t.verts[2][1] - t.verts[0][1])
  - (t.verts[2][0] - t.verts[0][0]) * (t.verts[1][1] - t.verts[0][1])) / 2;
const midRatio = triArea(MID) / areaTicket, hiRatio = triArea(HI) / areaTicket;
if (midRatio < 0.18 || midRatio > 0.30 || hiRatio < 0.06 || hiRatio > 0.13)
  throw Error('斜分界面积占比与设计图不符');
// 火漆轮廓：36 个角度放射求并集外缘，峰谷应落在 2~8px（浅起伏蜡封，不是正圆也不是花朵）
function waxRadius(deg) {
  const a = deg * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a);
  let last = 0;
  for (let r = 20; r < 70; r += 0.25) {
    const x = W.cx + dx * r, y = W.cy + dy * r;
    const inside = WAX_SPEC.some(L => ((x - L.cx) / (WAX_D / 2)) ** 2 + ((y - L.cy) / (WAX_D / 2)) ** 2 <= 1);
    if (inside) last = r;
  }
  return last;
}
const radii = Array.from({ length: 36 }, (_, i) => waxRadius(i * 10));
const rMin = Math.min(...radii), rMax = Math.max(...radii);
if (rMax - rMin < 1 || rMax - rMin > 6 || rMin < 46) throw Error('火漆起伏异常：' + [rMin, rMax]);

// ── 可见层统计 ───────────────────────────────────────────────────────────
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const waxRegex = /^(art663\.wax\.|art664\.wax\.)/;
const visible = list => list.filter(n => !isHiddenRecord(named(n).field)).length;
const tabAll = g.recs.filter(r => tabRegex.test(r.name || '')).map(r => r.name);
const waxAll = g.recs.filter(r => waxRegex.test(r.name || '')).map(r => r.name);
const tabVisibleBefore = 41, waxVisibleBefore = 47;   // 由 _盘点673.mjs 实读 672 得出（火漆 50 条中 3 条旧 glow/inner 已隐藏）
const tabVisibleAfter = visible(tabAll), waxVisibleAfter = visible(waxAll);
if (tabVisibleAfter > 20 || waxVisibleAfter > 18) throw Error('可见图元未达最少目标');

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    hidden: hidden.length, shown: shown.length, modified: modified.length,
    tabVisibleBefore, tabVisibleAfter, waxVisibleBefore, waxVisibleAfter,
    midRatio: +(midRatio * 100).toFixed(2), hiRatio: +(hiRatio * 100).toFixed(2),
    waxRadii: [rMin, rMax], MID, HI }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '673 ticket wave edge + two 45deg triangles + wax-seal lobes, minimal primitives',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touchedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return '非目标记录被改动 ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const rt = t.tree.find(q => q.field === 9);
    if (rt.sub.length !== recTopOrderBefore.length) return 'recTop 字段数变化';
    // 重读树的 field 是新对象，只能按记录 id 比对层序
    const beforeFieldId = new Map(g.recs.map(r => [r.field, r.id]));
    const afterFieldId = new Map(t.recs.map(r => [r.field, r.id]));
    for (let i = 0; i < rt.sub.length; i++)
      if (beforeFieldId.get(recTopOrderBefore[i]) !== afterFieldId.get(rt.sub[i])) return '层序被改动 @' + i;
    const idx = new Map(); rt.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    // 官方问号与热区逐字节不动
    for (const n of ['clues.help617', 'clues.help627.hit']) {
      const a = t.recs.find(q => q.name === n);
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '按钮本体/热区被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '673 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '672_梯形与异色区.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '673_注释按钮与底图.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    reference: '用户 6 图：实机全局 + 票券/火漆局部；设计稿全局 + 票券/火漆局部。设计局部 304×218 / 260×288，实机局部 180×128 / 152×138。',
    measured: {
      tabPaletteImpl: '#AF3200 / #8C2800 / #CB4C19（与设计图一致，颜色本轮不动）',
      tabPaletteDesign: '#AF3200(1556) / #8C2800(1382) / #CB4C19(354)',
      tabBackground: '实测左端 #DC642A(30,70)/#DA6228(30,100)→#F5EBC7(30,130)、右端 #E6B33B(280,70/130)、'
        + '上方 #E8B93C(150,20)、下方 #8A3B25(150,180)：跨多色渐变，纯色矩形必然形成竖带（664 根因）',
      tabShape: '设计图两端各 3~4 枚圆润凸齿 + 露出真实背景的凹口；整圈深棕描边；两条平行 45° 斜分界',
      implTabShape: '两端 20px 浅色竖带 + 21px 圆齿形成白/黄闪电状撕裂带；23 枚拟合三角',
      waxPalette: '#AA0400(2334) / #B40806(2354) / #D70601(216)，实机同色',
      waxShape: '设计图 8 瓣浅起伏（radial 82~91.5，峰谷 9.5px / 直径 177px）、左右弧形亮光、顶部鼓包、柔和暗压印',
      implWaxShape: '完美正圆（radial 52.5~55 恒定）+ 左右突兀椭圆高光块 + 完整亮环 + 双硬同心压印',
    },
    ticket: { center: [T.cx, T.cy], size: [T.w, T.h], rot: T.rot, colors: C,
      midTriangle: MID, hiTriangle: HI, midRatio: +(midRatio * 100).toFixed(2), hiRatio: +(hiRatio * 100).toFixed(2),
      edge: EDGE_SPEC },
    wax: { center: [W.cx, W.cy], colors: WC, lobes: WAX_SPEC,
      radii: { min: +rMin.toFixed(2), max: +rMax.toFixed(2), peakToValley: +(rMax - rMin).toFixed(2) },
      stampCore: { w: 64, h: 58, color: WC.stamp } },
    gates: { triVertsInside, midRatio: +midRatio.toFixed(4), hiRatio: +hiRatio.toFixed(4),
      waxPeakToValley: +(rMax - rMin).toFixed(2), waxMinRadius: +rMin.toFixed(2) },
    minimalPrimitives: '不新增任何记录（7052 条不变）；票券可见视觉层 41→' + tabVisibleAfter
      + '、火漆 50→' + waxVisibleAfter + '；23 枚拟合三角减为 2 枚解析等腰直角三角（rot 归一化到 [0,360)）。',
    untouched: 'clues.help617 官方问号、clues.help627.hit 热区、内嵌 Lua、26 条文本、线索卡 671/672 全部成果、v19 背景子树、recTop 层序与 childList 均逐字节不变。',
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: 0, removed: 0, hidden: hidden.length, shown: shown.length, modified: modified.length },
  visibleLayers: { tabBefore: tabVisibleBefore, tabAfter: tabVisibleAfter,
    waxBefore: waxVisibleBefore, waxAfter: waxVisibleAfter },
  hidden, shown, modified,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '673_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  hidden: hidden.length, shown: shown.length, modified: modified.length,
  tabVisible: [tabVisibleBefore, tabVisibleAfter], waxVisible: [waxVisibleBefore, waxVisibleAfter],
  midRatio: +(midRatio * 100).toFixed(2), hiRatio: +(hiRatio * 100).toFixed(2),
  waxPeakToValley: +(rMax - rMin).toFixed(2), scriptBytes: scriptBefore.length, status: 'APPLIED' }, null, 2));
