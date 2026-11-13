// 679 · 两项规格
//  ① 注释卡边缘：678 的齿是「深棕粗带 + 纯基色暗齿」，与设计稿「主体亮部连续延伸 + 细深棕描边」不连贯。
//     679 让主体齿改用主体亮部色 #AF3200、描边改浅为 #6B2A12（连贯），齿尖由尖三角改圆润椭圆，
//     描边齿纵向 22→20 让凹口留 2px V 形；仍保持几何真缺口、零溢出。
//  ② 棋盘移动端 y 居中：移动端截图 1280×576，k=0.8 ⇒ 可见原图区 y∈[90,810]、中心 450。
//     棋盘主体 board.bg/boardframe.paper 中心 y≈420 ⇒ 偏上 30px ⇒ 整组下移 Δy=+30，x 不变。
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

// ── ① 注释卡齿形 ────────────────────────────────────────────────────────
const CENTER = [384, 211], C = Math.cos(13 * Math.PI / 180), S = Math.sin(13 * Math.PI / 180);
const toScreen = (lx, ly) => [CENTER[0] + lx * C - ly * S, CENTER[1] + lx * S + ly * C];
const round = v => Math.round(v * 1000) / 1000;
const T = {
  colorMainBase: '#8C2800',   // 主体中央矩形（不变）
  colorMainTooth: '#AF3200',  // ★ 主体齿：改用 672 渐变 mid 同色 ⇒ 与亮部连贯
  colorOutline: '#6B2A12',    // ★ 描边：由 #592520 改浅为深红棕 ⇒ 与主体连贯
  // ★ 缩进从 9px 收到 8px（主体半宽 72，渐变最左 -70 仍有 2px 余量）；
  //   齿纵向 20 ≈ 齿距 22 ⇒ 凹口只有 2px 窄缝，齿**连成波浪带**而不是分离圆球（设计稿形状）。
  mainW: 144, mainH: 66, outlineW: 150, outlineH: 72,
  teethY: [-22, 0, 22],
  mainRect:  { w: 6, h: 20, dx: 75, rot: -13, img: 100001 },   // 平段 x∈[72,78]
  mainRound: { w: 8, h: 20, dx: 76, rot: -13, img: 100002 },   // 圆齿 x∈[72,80]
  outRect:   { w: 12, h: 24, dx: 75, rot: -13, img: 100001 },  // 描边平段 x∈[69,81]
  outRound:  { w: 12, h: 24, dx: 77, rot: -13, img: 100002 },  // 描边圆齿 x∈[71,83]
};
const teethFinal = [];
for (const side of [-1, 1]) for (let i = 0; i < T.teethY.length; i++) {
  const y = T.teethY[i], tag = `${side < 0 ? 'l' : 'r'}${i + 1}`;
  for (const [base, cfg, layer, color] of [
    ['rect', T.outRect,   'outline', T.colorOutline],
    ['tri',  T.outRound,  'outline', T.colorOutline],
    ['rect', T.mainRect,  'main',    T.colorMainTooth],
    ['tri',  T.mainRound, 'main',    T.colorMainTooth],
  ]) {
    const [cx, cy] = toScreen(side * cfg.dx, y);
    teethFinal.push({ name: `art678.tab.${layer}.${tag}.${base}`, layer, side, tooth: i + 1,
      cx: round(cx), cy: round(cy), w: cfg.w, h: cfg.h, rot: cfg.rot, img: cfg.img, color });
  }
}
console.log('注释卡齿层', teethFinal.length, '（沿用 678 名字，改几何/颜色/img/rot，不新增记录）');

// 中央矩形：改描边色 + 微调宽度（142/148 → 144/150，缩进由 9px 收到 8px）
const rectModify = [
  { name: 'art641.game.help.tab', color: null, w: T.mainW, h: T.mainH },
  { name: 'art661.tab.outline', color: T.colorOutline, w: T.outlineW, h: T.outlineH },
];

// ── ② 棋盘下移 ──────────────────────────────────────────────────────────
const SHIFT = 30;
const boardRoots = [
  { name: 'stage', note: '带动 board.bg / board.floors / board.rugs 与 36 枚 floor.cell.*' },
  { name: 'art657.grid.reuse', note: '带动 49 枚斜网格纸/网格线' },
  { name: 'art641.game.boardframe.paper', note: '白色底板' },
  { name: 'art641.game.boardframe.shadow', note: '底板阴影' },
  { name: 'art641.game.boardbottom', note: '底板下沿' },
];
console.log('棋盘下移 Δy =', SHIFT, '（1600 口径，x 不变），根层', boardRoots.length);

// ── 零溢出闸门（票券本地 4× 掩膜，沿用 678 方法）────────────────────────
const K = 4, LW = 200, LH = 100, OX = 100, OY = 50;
function mk() { const cv = createCanvas(LW * K, LH * K); return [cv, cv.getContext('2d')]; }
const [cvO, cxO] = mk(), [cvM, cxM] = mk(), [cvT, cxT] = mk();
function shape(cx, lx, ly, w, h, img) {
  cx.save(); cx.translate((OX + lx) * K, (OY + ly) * K);
  cx.scale(K, K); cx.fillStyle = '#fff'; cx.beginPath();
  if (img === 100002) cx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
  else cx.rect(-w / 2, -h / 2, w, h);
  cx.fill(); cx.restore();
}
shape(cxO, 0, 0, 150, 72, 100001);
shape(cxM, 0, 0, 144, 66, 100001);
for (const side of [-1, 1]) for (const y of T.teethY) {
  shape(cxO, side * T.outRect.dx, y, T.outRect.w, T.outRect.h, 100001);
  shape(cxO, side * T.outRound.dx, y, T.outRound.w, T.outRound.h, 100002);
  shape(cxM, side * T.mainRect.dx, y, T.mainRect.w, T.mainRect.h, 100001);
  shape(cxM, side * T.mainRound.dx, y, T.mainRound.w, T.mainRound.h, 100002);
}
// 23 枚渐变三角：从 678.gil 实读
const GIL = path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口/678_注释卡真缺口.gil');
const g = readGil(GIL);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const toLocal = (sx, sy) => { const dx = sx - CENTER[0], dy = sy - CENTER[1]; return [dx * C + dy * S, -dx * S + dy * C]; };
const triRecs = g.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '') && !isHiddenRecord(r.field));
for (const r of triRecs) {
  const st = stateBlocks(r.field.sub, [])[0], p = pairOf(st, 504), sz = pairOf(st, 505);
  const sx = 800 + pairValue(p, 0), sy = 450 - pairValue(p, 1), w = pairValue(sz, 0), h = pairValue(sz, 1);
  const rot = st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  const [lcx, lcy] = toLocal(sx, sy);
  cxT.save(); cxT.translate((OX + lcx) * K, (OY + lcy) * K);
  cxT.rotate((-rot - 13) * Math.PI / 180); cxT.scale(K, K);
  cxT.fillStyle = '#fff'; cxT.beginPath();
  cxT.moveTo(0, -h / 2); cxT.lineTo(-w / 2, h / 2); cxT.lineTo(w / 2, h / 2); cxT.closePath(); cxT.fill(); cxT.restore();
}
const dO = cxO.getImageData(0, 0, LW * K, LH * K).data;
const dM = cxM.getImageData(0, 0, LW * K, LH * K).data;
const dT = cxT.getImageData(0, 0, LW * K, LH * K).data;
let mainPx = 0, mainOut = 0, gradPx = 0, gradOut = 0;
for (let i = 0; i < dT.length; i += 4) {
  const on = a => a[i + 3] > 8;
  if (on(dM)) { mainPx++; if (!on(dO)) mainOut++; }
  if (on(dT)) { gradPx++; if (!on(dM)) gradOut++; }
}
console.log('零溢出闸门：主体', mainPx, '溢出描边', mainOut, '| 渐变', gradPx, '溢出主体', gradOut);
if (mainOut > 0 || gradOut > 0) throw Error('存在溢出毛刺');

// ── 预览：注释卡 679 vs 设计稿；棋盘居中前后（移动端可见框）──────────────
const { loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
{
  const PW = 260, PH = 150, PS = 2;
  const pv = createCanvas(PW * PS * 2 + 20, PH * PS), q = pv.getContext('2d');
  q.fillStyle = '#E7B83C'; q.fillRect(0, 0, pv.width, pv.height);
  q.save(); q.translate(PW / 2 * PS, PH / 2 * PS); q.rotate(13 * Math.PI / 180); q.scale(PS, PS);
  const R = (lx, ly, w, h, c, img) => {
    q.save(); q.translate(lx, ly); q.fillStyle = c;
    if (img === 100002) { q.beginPath(); q.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2); q.fill(); }
    else q.fillRect(-w / 2, -h / 2, w, h);
    q.restore();
  };
  R(0, 0, 150, 72, T.colorOutline, 100001); R(0, 0, 144, 66, T.colorMainBase, 100001);
  for (const side of [-1, 1]) for (const y of T.teethY) {
    R(side * T.outRect.dx, y, T.outRect.w, T.outRect.h, T.colorOutline, 100001);
    R(side * T.outRound.dx, y, T.outRound.w, T.outRound.h, T.colorOutline, 100002);
    R(side * T.mainRect.dx, y, T.mainRect.w, T.mainRect.h, T.colorMainTooth, 100001);
    R(side * T.mainRound.dx, y, T.mainRound.w, T.mainRound.h, T.colorMainTooth, 100002);
  }
  for (const r of triRecs) {
    const st = stateBlocks(r.field.sub, [])[0], p = pairOf(st, 504), sz = pairOf(st, 505);
    const sx = 800 + pairValue(p, 0), sy = 450 - pairValue(p, 1), w = pairValue(sz, 0), h = pairValue(sz, 1);
    const rot = st.sub?.find(q2 => q2.field === 508)?.sub?.[0]?.f || 0;
    const [lcx, lcy] = toLocal(sx, sy);
    const ip = ns(r.field, [505, 503, 84])[0], c = ip ? (num(ip, 502) ?? 0) : 0;
    q.save(); q.translate(lcx, lcy); q.rotate((-rot - 13) * Math.PI / 180);
    q.fillStyle = `rgb(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255})`;
    q.beginPath(); q.moveTo(0, -h / 2); q.lineTo(-w / 2, h / 2); q.lineTo(w / 2, h / 2); q.closePath(); q.fill(); q.restore();
  }
  R(0, 0, 40, 40, '#FFFDF3', 100002);
  q.fillStyle = '#A63A12'; q.font = 'bold 30px sans-serif'; q.textAlign = 'center'; q.textBaseline = 'middle'; q.fillText('?', 0, 1);
  q.restore();
  const design = await loadImage('C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-12T19-27-07-222Z-a07c7cca.png');
  q.drawImage(design, PW * PS + 20, 0, PW * PS, PH * PS);
  fs.writeFileSync(path.join(DIR, '679_注释卡预览_679vs设计.png'), pv.toBuffer('image/png'));
}
{
  // 棋盘居中示意：1600×900 缩到 640×360，画移动端可见框 y∈[90,810]
  const BW = 640, BH = 360, bs = BW / 1600;
  const pv = createCanvas(BW * 2 + 20, BH + 40), q = pv.getContext('2d');
  q.fillStyle = '#fff'; q.fillRect(0, 0, pv.width, pv.height);
  for (const [i, dy] of [[0, 0], [1, SHIFT]]) {
    const off = i * (BW + 20);
    q.fillStyle = '#E7B83C'; q.fillRect(off, 0, BW, BH);
    q.strokeStyle = '#e00'; q.lineWidth = 2;
    q.strokeRect(off + 1, 90 * bs, BW - 2, 720 * bs);   // 移动端可见区
    q.fillStyle = '#FDFCE7'; q.fillRect(off + (904 - 323) * bs, (419.5 + dy - 366) * bs, 646 * bs, 732 * bs);
    q.fillStyle = '#382D3B'; q.fillRect(off + (903.5 - 303.5) * bs, (420 + dy - 313) * bs, 607 * bs, 626 * bs);
    q.fillStyle = '#222'; q.font = 'bold 18px sans-serif';
    q.fillText(i === 0 ? '678：棋盘中心 y=420（偏上 30）' : '679：棋盘中心 y=450（移动端居中）', off + 8, BH + 26);
  }
  fs.writeFileSync(path.join(DIR, '679_棋盘居中示意.png'), pv.toBuffer('image/png'));
}

const spec = {
  version: 1,
  ticket: { geometry: T, teeth: teethFinal, rectModify,
    gates: { mainPx, mainOut, gradPx, gradOut, zeroSpur: mainOut === 0 && gradOut === 0 },
    safety: '23 枚渐变三角本地 x∈[-70,51]，主体半宽 71 ⇒ 渐变仍全在主体内' },
  board: { shiftY: SHIFT, roots: boardRoots,
    measurement: { mobileScreenshot: [1280, 576], k: 0.8, visibleY: [90, 810], visibleCenterY: 450,
      boardCenterYBefore: 420, deltaY: 30,
      measured: { darkFrameCenterPx: 263.5, screenCenterPx: 288, offsetPx: 24.5, offset1600: 30.63 } },
    note: '只改 5 个根层 y；stage 带动 36 枚 floor.cell.*，art657.grid.reuse 带动 49 枚网格层；x 全部不变' },
};
fs.writeFileSync(path.join(DIR, '679_规格.json'), JSON.stringify(spec, null, 1));
console.log('产出 679_规格.json + 两张预览');
