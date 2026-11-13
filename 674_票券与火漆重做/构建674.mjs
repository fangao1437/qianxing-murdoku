// 674 · 基于 672 干净基准重建（673 不再是最新成果）
//
// 用户实机反馈：「实机效果与预览一致，这两处仍与设计图差距较大。
//   1. 火漆形状有明显偏差，高光表现不对；
//   2. 注释按钮颜色渐变设计不对（672 渐变反而是对的，但后三项也不对），
//      宽度不对，长度不对，边缘形状也不对。」
//
// ⇒ 从 672 重建（历史 668 教训：错版上反向恢复不如从干净基准重建）。
//   ★ 23 枚 art664.tab.*.fitNN 拟合三角「逐字节零改动」＝保留用户认可的 672 渐变。
//   ★ 只重做：票券长度/宽度/边缘形状 + 火漆形状/高光。
//
// 设计稿实测（以官方 40×40 白圆问号为标尺，设计局部图放大 1.389×）：
//   票券 178×68（1600×900 口径）；672 只有 140×66，673 更短 124×66 且大圆齿撑厚短边。
//   火漆水平剖面 y=145：左端 #B40806→#D70601→#B40806 亮带宽约 20px，中心大片 #AA0400，
//   右端同样亮带；垂直剖面底部也有 #B40806 宽亮边 ⇒ 亮红是「沿外缘一圈的宽渐变带」，
//   不是 673 的两条孤立细月牙。设计稿火漆 bbox 105×106（近正圆），673 是 104×112（尖鼓包撑高）。
//
// 输入  ../672_梯形与异色区/672_梯形与异色区.gil（7052 条）
// 输出  674_票券与火漆重做.gil（记录数不变，Lua/文本/层序/childList 全不动）
// 用法  FORCE=1 node 构建674.mjs   /   node 构建674.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/674_票券与火漆重做');
const INPUT = path.join(ROOT, 'qianxing-murdoku/672_梯形与异色区/672_梯形与异色区.gil');
const OUTPUT = path.join(DIR, '674_票券与火漆重做.gil');
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

// ── 参数 ──────────────────────────────────────────────────────────────────
// 票券：中心 (384,211)，局部 160×66（±80 / ±33），rot −13
// 凹口 x≤80 留在票券内（不会在背景上留深棕斑），凸齿外凸到 ±89 ⇒ 总长 178 ≈ 设计稿 177.8
const T = { cx: 384, cy: 211, w: 160, h: 66, rot: -13 };
const C = { base: '#8C2800', mid: '#AF3200', stroke: '#592520' };
// 深棕盖条(1/端) + 票券色圆齿(3/端，相邻重叠) ⇒ 连续波浪撕边；凹口是深棕描边色，不透背景
const TOOTH_Y = [-20, 0, 20];
// 火漆：中心 (1326,342)，外缘 R=54（12 枚 R=30 / d=48 大幅重叠 ⇒ 圆润无棱角）
const W = { cx: 1326, cy: 342 };
// #CC0602 取自设计稿水平剖面 x=194 实测色，作为「沿外缘的亮红环」比 #B40806 亮一档
const WC = { main: '#AA0400', rim: '#B40806', ring: '#CC0602', hot: '#D70601', stamp: '#A60400' };

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
const hidden = [], modified = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function hide(r) { if (!isHiddenRecord(r.field)) { setHiddenRecord(r.field, true); hidden.push(r.name); } touch(r); }
function show(r) { if (isHiddenRecord(r.field)) { setHiddenRecord(r.field, false); } touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const rotPt = (lx, ly) => {
  const a = -T.rot * Math.PI / 180;   // 渲染器 ctx.rotate(−rot) ⇒ 屏幕顺时针 +13°
  return [T.cx + lx * Math.cos(a) - ly * Math.sin(a), T.cy + lx * Math.sin(a) + ly * Math.cos(a)];
};

// ── ① 注释票券：长度/宽度/边缘形状，渐变零改动 ─────────────────────────
const fitNames = g.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')).map(r => r.name);
if (fitNames.length !== 23) throw Error('672 拟合三角数量不符：' + fitNames.length);
if (fitNames.some(n => isHiddenRecord(named(n).field))) throw Error('672 基线存在隐藏的拟合三角');
const fitBytes = new Map(fitNames.map(n => [n, encodeMsg([named(n).field])]));

const tabMain = named('art641.game.help.tab'), tabOutline = named('art661.tab.outline');
const gm0 = screenGeom(tabMain), go0 = screenGeom(tabOutline);
if (Math.abs(gm0[2] - 140) > 0.01 || Math.abs(go0[2] - 146) > 0.01) throw Error('基准票券几何不是 672');
// 长度 140→160，宽度(短边)维持 66；描边同宽、高 72 只留上下 3px
setGeomScreen(tabMain, T.cx, T.cy, T.w, T.h); setRot(tabMain, T.rot); retint(tabMain, C.base, 100001);
setGeomScreen(tabOutline, T.cx, T.cy, T.w, T.h + 6); setRot(tabOutline, T.rot); retint(tabOutline, C.stroke, 100001);

// 边缘：设计稿是「深棕 V 形凹口 + 票券色圆润凸齿」的连续波浪撕边，凹口不透背景。
// 664 用浅色背景矩形 ⇒ 白/黄竖带；674 凹口直接用描边深棕 #592520，零浅色带。
const edgeNames = g.recs.filter(r => /^art663\.tab\.edge\./.test(r.name || '')).map(r => r.name).sort();
const toothNames = g.recs.filter(r => /^art663\.tab\.tooth\./.test(r.name || '')).map(r => r.name).sort();
if (edgeNames.length !== 8 || toothNames.length !== 8) throw Error('票券撕边层数量不符');
const EDGE_SPEC = [];
for (const [side, tag] of [[-1, 'l'], [1, 'r']]) {
  // 深棕盖条只宽 6px（x∈[74,80]）：齿中心处被圆齿完全盖住，只在齿间露出窄 V 形凹口，
  // 不会形成 664 那种整条浅色竖带，也不会像 674 首版那样变成一条深棕竖带。
  const strip = named(`art663.tab.edge.${tag}0`);
  {
    const [x, y] = rotPt(side * 77, 0);
    show(strip); setGeomScreen(strip, x, y, 6, T.h); setRot(strip, T.rot);
    retint(strip, C.stroke, 100001);
    EDGE_SPEC.push({ name: strip.name, role: 'darkStrip', cx: +x.toFixed(2), cy: +y.toFixed(2),
      w: 6, h: T.h, rot: T.rot, color: C.stroke });
  }
  for (let i = 1; i <= 3; i++) hide(named(`art663.tab.edge.${tag}${i}`));
  // 3 枚票券色圆齿（16×26）：中心局部 x=±81 ⇒ 外凸到 ±89，总长 178；
  // 半高 13、y=−20/0/20 间距 20 < 26 ⇒ 相邻重叠，连成连续波浪齿
  TOOTH_Y.forEach((ly, i) => {
    const r = named(`art663.tab.tooth.${tag}${i}`);
    const [x, y] = rotPt(side * 81, ly);
    show(r); setGeomScreen(r, x, y, 16, 26); setRot(r, 0);
    retint(r, side < 0 ? C.mid : C.base, 100002);
    EDGE_SPEC.push({ name: r.name, role: 'tooth', cx: +x.toFixed(2), cy: +y.toFixed(2), w: 16, h: 26,
      color: side < 0 ? C.mid : C.base });
  });
  hide(named(`art663.tab.tooth.${tag}3`));
}

// ── ② 火漆：6 浅瓣圆润轮廓 + 宽浅鼓包 + 沿弧排列的宽渐变亮带 ──────────
// 统一 R=30 ⇒ 外缘 54、峰谷约 1.25px：圆润无棱角；不规则感由「宽浅鼓包 + 左右弧亮带」提供，
// 不用 R 交替（交替会形成过于明显的 6 瓣齿轮，与设计稿不符）
const WAX_R_HI = 28, WAX_R_LO = 28, WAX_D = 52, WAX_N = 12;
const WAX_EDGE = WAX_R_HI + WAX_D / 2;                  // 54
const R_OF = i => i % 2 === 0 ? WAX_R_HI : WAX_R_LO;
for (let i = 0; i < WAX_N; i++) {
  const r = named(`art663.wax.edge.${i}`);
  const a = 2 * Math.PI * i / WAX_N, R = R_OF(i);
  const cx = W.cx + R * Math.cos(a), cy = W.cy + R * Math.sin(a);
  show(r); setGeomScreen(r, cx, cy, WAX_D, WAX_D); setRot(r, 0); retint(r, WC.ring, 100002);
}
for (const n of g.recs.filter(r => /^art663\.wax\.lobe\./.test(r.name || '')).map(r => r.name)) hide(named(n));
// 三层柔和渐变：外沿 #CC0602(20px) → 中间 #B40806(6px) → 中心 #A60400 压印
// （设计稿水平剖面正是「亮红→亮红→主体」的过渡，硬边同心环是 672 的问题）
const waxCore = named('art663.wax.core');
show(waxCore); setGeomScreen(waxCore, W.cx, W.cy, 68, 68); setRot(waxCore, 0); retint(waxCore, WC.rim, 100002);
// 顶部鼓包：30×30 尖高 → 44×26 宽浅 #C00703（比外环亮一档，鼓出约 9px，与主体可区分）
const waxTop = named('art664.wax.top.lobe');
show(waxTop); setGeomScreen(waxTop, W.cx, 292, 44, 26); setRot(waxTop, 0); retint(waxTop, '#C00703', 100002);
// 高光：每侧 3 枚椭圆沿 R=44 圆弧排列（角度 −30/0/30 与 150/180/210），
// 中间 #D70601 最亮、两端 #B40806 收尾 ⇒ 沿边缘弯曲的宽渐变亮带，而非孤立竖直亮条。
const HOT_SPEC = [];
for (const [side, base] of [[1, 0], [-1, 3]]) {
  [[-30, WC.rim], [0, WC.hot], [30, WC.rim]].forEach(([deg, color], j) => {
    const a = (side === 1 ? deg : 180 - deg) * Math.PI / 180;
    const r = named(`art664.wax.ring.${base + j}`);
    const cx = W.cx + 43 * Math.cos(a), cy = W.cy + 43 * Math.sin(a);
    show(r); setGeomScreen(r, cx, cy, 16, 28); setRot(r, 0); retint(r, color, 100002);
    HOT_SPEC.push({ name: r.name, cx: +cx.toFixed(2), cy: +cy.toFixed(2), w: 16, h: 28, color,
      deg: side === 1 ? deg : 180 - deg });
  });
}
for (let i = 6; i < 16; i++) hide(named(`art664.wax.ring.${i}`));
hide(named('art664.wax.hot.l'));
hide(named('art664.wax.hot.r'));
hide(named('art664.wax.center'));
hide(named('art664.wax.stamp.rim'));
// 柔和圆形压印：56×56 #A60400（比中间层暗 8/255），去掉 672 的亮边+暗芯双硬环
const stampCore = named('art664.wax.stamp.core');
show(stampCore); setGeomScreen(stampCore, W.cx, W.cy, 56, 56); setRot(stampCore, 0);
retint(stampCore, WC.stamp, 100002);

// ── 几何闸门 ─────────────────────────────────────────────────────────────
// 票券总长（主体 + 凸齿外凸）与目标 177.8 的误差
const totalLength = T.w + 2 * 9;
if (Math.abs(totalLength - 177.8) > 3) throw Error('票券总长与设计稿不符：' + totalLength);
// 23 枚拟合三角逐字节不变（用户明确「672 渐变是对的」）
for (const n of fitNames)
  if (!fitBytes.get(n).equals(encodeMsg([named(n).field]))) throw Error('渐变三角被改动 ' + n);
// 深棕盖条不越过票券边界：中心 77 + 半宽 3 = 80 = 主体半宽
if (77 + 3 > T.w / 2 + 0.01) throw Error('深棕盖条越过票券边界会污染背景');
// 6 枚弧亮带整枚在 R=54 内（椭圆参数方程采样）
let hotMax = 0;
for (const H of HOT_SPEC) for (let t = 0; t < 360; t += 2) {
  const a = t * Math.PI / 180;
  const x = (H.cx - W.cx) + H.w / 2 * Math.cos(a);
  const y = (H.cy - W.cy) + H.h / 2 * Math.sin(a);
  hotMax = Math.max(hotMax, Math.hypot(x, y));
}
if (hotMax > WAX_EDGE) throw Error('火漆亮弧越出蜡封轮廓：' + hotMax.toFixed(2));
// 12 枚椭圆并集放射轮廓：6 浅瓣，峰谷 2~6px（圆润但非正圆）
function waxRadius(deg) {
  const a = deg * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a);
  let last = 0;
  for (let r = 20; r < 70; r += 0.25) {
    const x = W.cx + dx * r, y = W.cy + dy * r;
    let inside = false;
    for (let i = 0; i < WAX_N; i++) {
      const b = 2 * Math.PI * i / WAX_N, R = R_OF(i);
      const cx = W.cx + R * Math.cos(b), cy = W.cy + R * Math.sin(b);
      if (((x - cx) / (WAX_D / 2)) ** 2 + ((y - cy) / (WAX_D / 2)) ** 2 <= 1) { inside = true; break; }
    }
    if (inside) last = r;
  }
  return last;
}
const radii = Array.from({ length: 36 }, (_, i) => waxRadius(i * 10));
const rMin = Math.min(...radii), rMax = Math.max(...radii);
if (rMax - rMin > 6 || rMin < 48) throw Error('火漆轮廓异常：' + [rMin, rMax]);

// ── 可见层统计 ───────────────────────────────────────────────────────────
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const waxRegex = /^(art663\.wax\.|art664\.wax\.)/;
const visCount = re => g.recs.filter(r => re.test(r.name || '') && !isHiddenRecord(r.field)).length;
const tabVisible = visCount(tabRegex), waxVisible = visCount(waxRegex);
if (tabVisible > 41 || waxVisible > 22) throw Error('可见图元未达最少目标');

// ── 落盘 ─────────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    hidden: hidden.length, modified: modified.length,
    tabVisible, waxVisible, totalLength, designLength: 177.8,
    waxRadii: [rMin, rMax], hotMax: +hotMax.toFixed(2) }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '674 ticket size/edge + wax shape/highlight, keep 672 gradient, minimal primitives',
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
    const bf = new Map(g.recs.map(r => [r.field, r.id]));
    const af = new Map(t.recs.map(r => [r.field, r.id]));
    for (let i = 0; i < rt.sub.length; i++)
      if (bf.get(recTopOrderBefore[i]) !== af.get(rt.sub[i])) return '层序被改动 @' + i;
    const idx = new Map(); rt.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    for (const n of ['clues.help617', 'clues.help627.hit', ...fitNames]) {
      const a = t.recs.find(q => q.name === n);
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '按钮/热区/渐变被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '674 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '672_梯形与异色区.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '674_票券与火漆重做.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    userFeedback: '实机与预览一致；火漆形状/高光不对；注释按钮渐变应回到 672，宽度/长度/边缘形状仍不对',
    measurement: {
      whiteScale: '设计局部图 / 实机 1600×900 口径 = 1.389（以官方 40×40 白圆问号为标尺：设计 50px / 实机 36px）',
      designTicket: '178×68（1600×900 口径，旋转 −13° 校正后局部坐标 2%~98% 分位）',
      ticket672: '140×66', ticket673: '124×66 + 大圆齿撑厚短边',
      designWaxBBox: '105×106，radial 47.5~53.5（近正圆、浅起伏）',
      wax673BBox: '104×112（尖鼓包撑高 8px）',
      waxHorizontalProfile: '左缘 #B40806→#D70601→#B40806 亮带宽约 20px；中心大片 #AA0400；右缘同亮带',
      waxVerticalProfile: '底部 #B40806 宽亮边；顶部宽浅鼓包',
    },
    ticket: { center: [T.cx, T.cy], size: [T.w, T.h], rot: T.rot,
      totalLength, outline: [T.w, T.h + 6],
      gradient: '23 枚 art664.tab.*.fitNN 拟合三角逐字节零改动（用户认可 672 渐变）',
      edge: EDGE_SPEC },
    wax: { center: [W.cx, W.cy], colors: WC,
      lobes: { count: WAX_N, R: WAX_R_HI, d: WAX_D, edgeRadius: WAX_EDGE,
        color: WC.ring, note: '统一 R 保证圆润；#CC0602 取自设计稿水平剖面 x=194' },
      core: { w: 68, h: 68, color: WC.rim }, topLobe: { cx: W.cx, cy: 292, w: 44, h: 26, color: '#C00703' },
      hotArcs: HOT_SPEC, stamp: { w: 56, h: 56, color: WC.stamp },
      radii: { min: +rMin.toFixed(2), max: +rMax.toFixed(2), peakToValley: +(rMax - rMin).toFixed(2) },
      hotMaxRadius: +hotMax.toFixed(2) },
    gates: { totalLength, designLength: 177.8, gradientUntouched: true,
      notchInsideTicket: true, waxRadii: [+rMin.toFixed(2), +rMax.toFixed(2)], hotMaxRadius: +hotMax.toFixed(2) },
    minimalPrimitives: '不新增/删除记录；票券可见层 41→' + tabVisible + '、火漆 47→' + waxVisible
      + '；23 枚渐变三角全保留，仅替换 16 枚撕边层与火漆冗余层。',
    untouched: '23 枚渐变三角、clues.help617 / clues.help627.hit、内嵌 Lua、26 条文本、线索卡 671/672 成果、v19 背景子树、recTop 层序与 childList 均逐字节不变。',
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: 0, removed: 0, hidden: hidden.length, modified: modified.length },
  visibleLayers: { tabBefore: 41, tabAfter: tabVisible, waxBefore: 47, waxAfter: waxVisible },
  hidden, modified,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '674_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  hidden: hidden.length, modified: modified.length,
  tabVisible, waxVisible, totalLength,
  waxPeakToValley: +(rMax - rMin).toFixed(2), hotMax: +hotMax.toFixed(2),
  scriptBytes: scriptBefore.length, status: 'APPLIED' }, null, 2));
