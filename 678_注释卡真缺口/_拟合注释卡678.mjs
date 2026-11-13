// 678 · 注释卡（票券）两侧「几何真缺口」构造
//   ★ 用户做法：缩进两侧矩形边缘 → 增补三角形（+ 矩形平边缘段）→ 底下垫稍大一圈的同形状描边
//   ★ 关键安全边界：677 实测 23 枚渐变三角在票券本地坐标只覆盖 x∈[-70,51]、y∈[-33,33]，
//     故主体半宽从 80 缩到 71（缩进 9px）后渐变仍完整落在主体内 ⇒ 零溢出毛刺。
//   ★ 票券 rot=-13°；本地 → 屏幕：x'=lx*C-ly*S, y'=lx*S+ly*C，中心(384,211)，C=cos13,S=sin13
//     100003 顶点朝票券本地 +x（右）⇒ rot=257；朝 -x（左）⇒ rot=77（257 已在 672 实机验证）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);

const CENTER = [384, 211], ROT = -13;
const C = Math.cos(13 * Math.PI / 180), S = Math.sin(13 * Math.PI / 180);
const toScreen = (lx, ly) => [CENTER[0] + lx * C - ly * S, CENTER[1] + lx * S + ly * C];
const round = v => Math.round(v * 1000) / 1000;

// ① 几何参数（票券本地坐标）
const P = {
  indent: 9,            // 两侧各缩进 9px ⇒ 主体半宽 71（渐变最左 -70，留 1px 余量）
  mainW: 142, mainH: 66,        // 主体中央矩形 x∈[-71,71], y∈[-33,33]
  outlineW: 148, outlineH: 72,  // 描边中央矩形 x∈[-74,74], y∈[-36,36]（大一圈 3px）
  teethY: [-22, 0, 22],         // 每侧 3 个凸齿
  // 第二轮：平边缘段加宽（12→16），凹口收窄成 6px 的深棕 V 形（设计稿凹口是深棕而非背景色）；
  // 描边齿纵向 22 = 齿中心间距 22 ⇒ 描边齿恰好相接，凹口处露深棕描边、不露橙黄背景。
  mainRect: { w: 5, h: 16, dx: 73.5 },   // 平边缘段 x∈[71,76]
  mainTri:  { w: 16, h: 4, dx: 78 },     // 尖齿：底边 x=76、顶点 x=80
  outRect:  { w: 11, h: 22, dx: 73.5 }, // 描边平段 x∈[68,79]
  outTri:   { w: 22, h: 4, dx: 81 },    // 描边尖齿：底边 x=79、顶点 x=83
  colorMain: '#8C2800', colorOutline: '#592520',
};
const elements = [];
for (const side of [-1, 1]) {          // -1 左 / +1 右
  for (let i = 0; i < P.teethY.length; i++) {
    const y = P.teethY[i], tag = `${side < 0 ? 'l' : 'r'}${i + 1}`;
    // 描边齿（先画，在主体之下）
    for (const [suffix, cfg, layer, rot] of [
      ['rect', P.outRect, 'outline', ROT],
      ['tri',  P.outTri,  'outline', side > 0 ? 257 : 77],
    ]) {
      const [cx, cy] = toScreen(side * cfg.dx, y);
      elements.push({ name: `art678.tab.${layer}.${tag}.${suffix}`, layer, side, tooth: i + 1,
        cx: round(cx), cy: round(cy), w: cfg.w, h: cfg.h, rot,
        img: suffix === 'tri' ? 100003 : 100001,
        color: P.colorOutline, anchor: 'art641.game.help.tab' });
    }
    // 主体齿（后画，在渐变之前）
    for (const [suffix, cfg, layer, rot] of [
      ['rect', P.mainRect, 'main', ROT],
      ['tri',  P.mainTri,  'main', side > 0 ? 257 : 77],
    ]) {
      const [cx, cy] = toScreen(side * cfg.dx, y);
      elements.push({ name: `art678.tab.${layer}.${tag}.${suffix}`, layer, side, tooth: i + 1,
        cx: round(cx), cy: round(cy), w: cfg.w, h: cfg.h, rot,
        img: suffix === 'tri' ? 100003 : 100001,
        color: P.colorMain, anchor: 'art664.tab.mid.fit01' });
    }
  }
}
console.log('新增齿图元', elements.length, '（描边 12 / 主体 12）');

// ② 像素级「零溢出」闸门：主体 ⊆ 描边、渐变 ⊆ 主体
//    在票券本地放大 4× 的画布里画四种掩膜，逐像素比较（不依赖 .gil 渲染，纯解析几何）
const K = 4, LW = 200, LH = 100, OX = 100, OY = 50;
function maskCanvas() { const cv = createCanvas(LW * K, LH * K); return [cv, cv.getContext('2d')]; }
function localRect(cx, lx, ly, w, h, rotDeg) {
  cx.save(); cx.translate((OX + lx) * K, (OY + ly) * K);
  cx.rotate(rotDeg * Math.PI / 180); cx.scale(K, K);
  cx.fillStyle = '#fff'; cx.fillRect(-w / 2, -h / 2, w, h); cx.restore();
}
function localTri(cx, lx, ly, w, h, rotDeg) {
  // 100003：顶点(0,-h/2)、底边(-w/2,h/2)..(w/2,h/2)，渲染用 canvas rotate(-rot°)
  cx.save(); cx.translate((OX + lx) * K, (OY + ly) * K);
  cx.rotate(-rotDeg * Math.PI / 180); cx.scale(K, K);
  cx.fillStyle = '#fff'; cx.beginPath();
  cx.moveTo(0, -h / 2); cx.lineTo(-w / 2, h / 2); cx.lineTo(w / 2, h / 2); cx.closePath(); cx.fill(); cx.restore();
}
// 注意：上面 localRect/localTri 是在「票券本地」画，整体不旋转；齿三角的 rot 已含票券 -13°
//       为与真实屏幕一致，把票券 rot 从齿三角 rot 中扣掉：右齿 257+13=270, 左齿 77+13=90
const [cvO, cxO] = maskCanvas(), [cvM, cxM] = maskCanvas(), [cvT, cxT] = maskCanvas();
localRect(cxO, 0, 0, P.outlineW, P.outlineH, 0);
localRect(cxM, 0, 0, P.mainW, P.mainH, 0);
for (const side of [-1, 1]) for (const y of P.teethY) {
  localRect(cxO, side * P.outRect.dx, y, P.outRect.w, P.outRect.h, 0);
  localTri(cxO, side * P.outTri.dx, y, P.outTri.w, P.outTri.h, side > 0 ? 270 : 90);
  localRect(cxM, side * P.mainRect.dx, y, P.mainRect.w, P.mainRect.h, 0);
  localTri(cxM, side * P.mainTri.dx, y, P.mainTri.w, P.mainTri.h, side > 0 ? 270 : 90);
}
// 渐变三角：从 .gil 实读 23 枚，按本地顶点画（屏幕 → 本地的逆）
const GIL = path.join(ROOT, 'qianxing-murdoku/677_活页扣孔与八环/677_活页扣孔与八环.gil');
const g = readGil(GIL);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const toLocal = (sx, sy) => { const dx = sx - CENTER[0], dy = sy - CENTER[1]; return [dx * C + dy * S, -dx * S + dy * C]; };
const triRecs = g.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '') && !isHiddenRecord(r.field));
for (const r of triRecs) {
  const st = stateBlocks(r.field.sub, [])[0], p = pairOf(st, 504), sz = pairOf(st, 505);
  const sx = 800 + pairValue(p, 0), sy = 450 - pairValue(p, 1);
  const w = pairValue(sz, 0), h = pairValue(sz, 1);
  const rot = st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  // 三角屏幕顶点 → 本地（整体减掉票券 rot=+13°）
  const [lcx, lcy] = toLocal(sx, sy);
  cxT.save(); cxT.translate((OX + lcx) * K, (OY + lcy) * K);
  cxT.rotate((-rot - 13) * Math.PI / 180); cxT.scale(K, K);
  cxT.fillStyle = '#fff'; cxT.beginPath();
  cxT.moveTo(0, -h / 2); cxT.lineTo(-w / 2, h / 2); cxT.lineTo(w / 2, h / 2); cxT.closePath(); cxT.fill(); cxT.restore();
}
const dO = cxO.getImageData(0, 0, LW * K, LH * K).data;
const dM = cxM.getImageData(0, 0, LW * K, LH * K).data;
const dT = cxT.getImageData(0, 0, LW * K, LH * K).data;
let mainOutsideOutline = 0, gradOutsideMain = 0, gradPixels = 0, mainPixels = 0;
for (let i = 0; i < dT.length; i += 4) {
  const on = a => a[i + 3] > 8;
  if (on(dM)) { mainPixels++; if (!on(dO)) mainOutsideOutline++; }
  if (on(dT)) { gradPixels++; if (!on(dM)) gradOutsideMain++; }
}
console.log('零溢出闸门：主体像素', mainPixels, '溢出描边', mainOutsideOutline,
  '| 渐变像素', gradPixels, '溢出主体', gradOutsideMain);
if (mainOutsideOutline > 0 || gradOutsideMain > 0)
  throw Error('存在溢出毛刺：mainOutside=' + mainOutsideOutline + ' gradOutside=' + gradOutsideMain);

// ③ 预览：把新齿形 + 23 枚渐变 + 问号占位画出来，与设计稿并排
const PW = 260, PH = 150, PS = 2;
const pv = createCanvas(PW * PS * 2 + 20, PH * PS), q = pv.getContext('2d');
q.fillStyle = '#E7B83C'; q.fillRect(0, 0, pv.width, pv.height);
function drawPreview(xoff) {
  q.save(); q.translate(xoff, 0); q.scale(PS, PS);
  q.save(); q.translate(PW / 2, PH / 2);
  // 用「票券本地」画，整体旋转 +13°
  q.rotate(13 * Math.PI / 180);
  q.fillStyle = P.colorOutline; q.fillRect(-P.outlineW / 2, -P.outlineH / 2, P.outlineW, P.outlineH);
  q.fillStyle = P.colorMain; q.fillRect(-P.mainW / 2, -P.mainH / 2, P.mainW, P.mainH);
  for (const side of [-1, 1]) for (const y of P.teethY) {
    q.fillStyle = P.colorOutline;
    q.fillRect(side * P.outRect.dx - P.outRect.w / 2, y - P.outRect.h / 2, P.outRect.w, P.outRect.h);
    q.fillStyle = P.colorMain;
    q.fillRect(side * P.mainRect.dx - P.mainRect.w / 2, y - P.mainRect.h / 2, P.mainRect.w, P.mainRect.h);
  }
  for (const side of [-1, 1]) for (const y of P.teethY) {
    const tri = (lx, w, h, col, rotDeg) => {
      q.save(); q.translate(lx, y); q.rotate(-rotDeg * Math.PI / 180);
      q.fillStyle = col; q.beginPath(); q.moveTo(0, -h / 2); q.lineTo(-w / 2, h / 2); q.lineTo(w / 2, h / 2); q.closePath(); q.fill(); q.restore();
    };
    tri(side * P.outTri.dx, P.outTri.w, P.outTri.h, P.colorOutline, side > 0 ? 270 : 90);
    tri(side * P.mainTri.dx, P.mainTri.w, P.mainTri.h, P.colorMain, side > 0 ? 270 : 90);
  }
  // 渐变（从 .gil 实读）
  for (const r of triRecs) {
    const st = stateBlocks(r.field.sub, [])[0], p = pairOf(st, 504), sz = pairOf(st, 505);
    const sx = 800 + pairValue(p, 0), sy = 450 - pairValue(p, 1);
    const w = pairValue(sz, 0), h = pairValue(sz, 1);
    const rot = st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0;
    const [lcx, lcy] = toLocal(sx, sy);
    const ip = ns(r.field, [505, 503, 84])[0]; const c = ip ? (num(ip, 502) ?? 0) : 0;
    q.save(); q.translate(lcx, lcy); q.rotate((-rot - 13) * Math.PI / 180);
    q.fillStyle = `rgb(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255})`;
    q.beginPath(); q.moveTo(0, -h / 2); q.lineTo(-w / 2, h / 2); q.lineTo(w / 2, h / 2); q.closePath(); q.fill(); q.restore();
  }
  q.fillStyle = '#FFFDF3'; q.beginPath(); q.arc(0, 0, 20, 0, Math.PI * 2); q.fill();
  q.fillStyle = '#A63A12'; q.font = 'bold 30px sans-serif'; q.textAlign = 'center'; q.textBaseline = 'middle';
  q.fillText('?', 0, 1);
  q.restore(); q.restore();
}
drawPreview(0);
// 设计稿栏
const { loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const design = await loadImage('C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-12T19-27-07-222Z-a07c7cca.png');
q.drawImage(design, PW * PS + 20, 0, PW * PS, PH * PS);
fs.writeFileSync(path.join(DIR, '678_注释卡预览_678vs设计.png'), pv.toBuffer('image/png'));

const spec = {
  version: 1,
  userFeedback: '只做两侧边缘重做，缺口不要靠背景色补，从几何层面构造真缺口；不要溢出毛刺；缩进两侧矩形 + 增补三角形 + 底下垫稍大一圈同形状描边；部分区域还需矩形塑造平边缘，图形不必局限',
  geometry: P,
  safety: { gradientLocalX: [-70, 51], gradientLocalY: [-33, 33],
    mainHalfBefore: 80, mainHalfAfter: 71, marginPx: 1,
    note: '23 枚渐变三角逐枚按屏幕三角顶点反算到票券本地坐标，最左 -70；主体缩进到 ±71 留 1px 余量' },
  gates: { mainPixels, gradPixels, mainOutsideOutline, gradOutsideMain, zeroSpur: true },
  hidden: { tipHi: Array.from({ length: 8 }, (_, i) => `art677.ring.${i + 1}.tipHi`) },
  modifyExisting: {
    'art641.game.help.tab': { from: [384, 211, 160, 66], to: [384, 211, P.mainW, P.mainH] },
    'art661.tab.outline':   { from: [384, 211, 166, 72], to: [384, 211, P.outlineW, P.outlineH] },
  },
  elements,
};
fs.writeFileSync(path.join(DIR, '678_注释卡图元.json'), JSON.stringify(spec, null, 1));
console.log('产出 678_注释卡图元.json + 678_注释卡预览_678vs设计.png');
