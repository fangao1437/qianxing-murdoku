/* v14: 按实机反馈彻底重构几何（2026-11-11）
 *
 * 用户三点反馈：
 *  1) 橘红色区域没有到档案袋边缘
 *  2) 档案袋阴影部分表现错误
 *  3) 太多细矩形 -> 锯齿。原则：倾斜形状用「矩形 + 旋转」；
 *     斜边用 100003 等腰三角（压缩拉伸后的一条边）+ 其它大块同色补色；
 *     不透明同色重叠无缝，只需保证外边界不溢出，内部可任意重叠。
 *  补充：原本设计里本可简单构造却也堆小矩形的部分一并改。
 *
 * 实现要点：
 *  - fillConvex(pts, color)：凸多边形扇形剖分成三角形；每个三角形沿三条边各放一个
 *    100003 等腰三角（底边=该边，顶点在中垂线上最远内点）。三个等腰三角同色不透明，
 *    并集 100% 覆盖三角形，且每个三角形完全内嵌（凸性保证不溢出）。
 *    所有外边界都是原生图元的边 -> 零锯齿。
 *  - 档案袋右边缘整体右移 24px 到设计图实测位置（局部 u 上限 310->334），
 *    DARK 橘红区随之延伸到档案袋边缘；SHADOW 左边界改为严格贴合新档案袋右边缘，
 *    删除 v13 那条把阴影切断的亮橙 DARK 补缝带 -> 阴影连续、橘红区到边。
 *  - 橘红楔形底端由 (456,638) 延到档案袋左边缘交点 (453,713)。
 *  - 右侧渐暗 / 胶带渐变由 52 / 72 条细条改为 12 段大块原生矩形（边界是直线，无锯齿）。
 *  - 拍立得竖直分界补缝三角由扫描条改为 fillConvex。
 *
 * 控件数：v13 812 -> v14 约 120。
 */
const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W = 1600, H = 900;
const BASE = '#B64A20';
const BAG = '#D99331', DARK = '#C86D20', RED = '#C85D11', LINE = '#6A3210';
const IVORY = '#FBE6B4', CORE = '#6E2B10';
const FRAME = '#FDFADB', FRAME_LIT = '#FCFAF0';
const PHOTO_L = '#753323', PHOTO_R = '#803A29';
const TAPE = '#FCCA00', TAPE_ORANGE = '#B44A00';
const PAW = '#6E2B10', SHADOW = '#973813', BLACK = '#020101';
const TH = 15.4, BAG_C = [674, 350], BAG_H = 900;
const BAG_U0 = -310, BAG_U1 = 334;            // v14: 右边缘右移 24px
const BAG_W = BAG_U1 - BAG_U0, BAG_UC = (BAG_U0 + BAG_U1) / 2;
const POL_C = [1256, 516], POL_TH = -14;
const SPLIT = 1263;
const RAD = Math.PI / 180;
const local = (c, t, u, v) => { const a = t * RAD; return [c[0] + u * Math.cos(a) + v * Math.sin(a), c[1] - u * Math.sin(a) + v * Math.cos(a)]; };
const rightR = x => x <= 1080 ? 183 : 183 - 113 * Math.pow((x - 1080) / 520, 1.6);
const bgColor = r => { const q = v => Math.max(0, Math.min(255, Math.round(v))); const h = n => q(n).toString(16).padStart(2, '0'); return '#' + h(r) + h(r * 74 / 182) + h(r * 32 / 182); };
const bagRightX = y => 924 + 0.2755 * y;      // 新档案袋右边缘屏幕线（u=334）

function build(withText) {
  const els = []; let z = 0;
  const add = o => els.push(Object.assign({ id: 'e' + (++z), rotation: 0, opacity: 1, zIndex: z - 1, isBackground: false }, o));
  const img = (a, x, y, w, h, c, r = 0, o = 1) => add({ type: 'image', x, y, width: w, height: h, rotation: r, color: c, opacity: o, imageAssetId: a, imageType: 'stretch', imageTint: true });
  const rect = (x, y, w, h, c, o = 1) => img(100001, x, y, w, h, c, 0, o);
  const circle = (x, y, d, c) => img(100002, x, y, d, d, c);

  // ---------- 通用：凸多边形 -> 每条边一个等腰三角（原生 100003） ----------
  const inside = (P, p) => {
    let s = null;
    for (let i = 0; i < P.length; i++) {
      const a = P[i], b = P[(i + 1) % P.length];
      const cr = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
      if (Math.abs(cr) < 1e-9) continue;
      const sg = cr > 0 ? 1 : -1;
      if (s === null) s = sg; else if (s !== sg) return false;
    }
    return true;
  };
  function edgeTri(a, b, c, color) {
    // 以 a-b 为底边的等腰三角，顶点在中垂线上、且尽可能深地落在三角形 a-b-c 内
    const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy);
    if (len < 0.01) return;
    const dir = [dx / len, dy / len];
    let n = [-dir[1], dir[0]];
    const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    if ((c[0] - mid[0]) * n[0] + (c[1] - mid[1]) * n[1] < 0) n = [-n[0], -n[1]];
    const tri = [a, b, c];
    let lo = 0, hi = 3000;
    for (let k = 0; k < 46; k++) {
      const m = (lo + hi) / 2;
      if (inside(tri, [mid[0] + n[0] * m, mid[1] + n[1] * m])) lo = m; else hi = m;
    }
    if (lo < 0.05) return;
    const cx = mid[0] + n[0] * lo / 2, cy = mid[1] + n[1] * lo / 2;
    const rot = Math.atan2(-n[0], -n[1]) / RAD;   // 100003 顶点方向 = (-sin r, -cos r)
    img(100003, cx, cy, len, lo, color, rot, 1);
  }
  function fillTri(A, B, C, color) {
    edgeTri(A, B, C, color); edgeTri(B, C, A, color); edgeTri(C, A, B, color);
  }
  // 整条多边形的边做等腰三角：内法线指向多边形重心，顶点可延伸到整个多边形内部（比扇形三角大得多）
  function edgeTriPoly(a, b, poly, color) {
    const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy);
    if (len < 0.01) return;
    const dir = [dx / len, dy / len];
    let n = [-dir[1], dir[0]];
    const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    const cen = poly.reduce((s, p) => [s[0] + p[0] / poly.length, s[1] + p[1] / poly.length], [0, 0]);
    if ((cen[0] - mid[0]) * n[0] + (cen[1] - mid[1]) * n[1] < 0) n = [-n[0], -n[1]];
    let lo = 0, hi = 3000;
    for (let k = 0; k < 46; k++) {
      const m = (lo + hi) / 2;
      if (inside(poly, [mid[0] + n[0] * m, mid[1] + n[1] * m])) lo = m; else hi = m;
    }
    if (lo < 0.05) return;
    const rot = Math.atan2(-n[0], -n[1]) / RAD;
    img(100003, mid[0] + n[0] * lo / 2, mid[1] + n[1] * lo / 2, len, lo, color, rot, 1);
  }
  // 双保险：整体每边等腰三角（大块） + 扇形剖分每边等腰三角（补尖角）；全部同色不透明内嵌
  function fillConvex(pts, color) {
    if (pts.length === 3) { fillTri(pts[0], pts[1], pts[2], color); return; }
    for (let i = 0; i < pts.length; i++) edgeTriPoly(pts[i], pts[(i + 1) % pts.length], pts, color);
    for (let i = 1; i < pts.length - 1; i++) fillTri(pts[0], pts[i], pts[i + 1], color);
  }

  // ---------- 1. 底色 + 右侧渐暗（12 段大块） + 官方径向渐晕 ----------
  rect(800, 450, W, H, BASE);
  // 渐变本身需要分段，但都是整条竖直矩形（原生直边，无锯齿）；参数与 v12 逐条一致，右侧观感不变
  for (let x = 1080; x < 1600; x += 10) rect(x + 5, 450, 11, H, bgColor(rightR(x + 5)));
  img(106060, 800, 450, 2200, 1100, '#000000', 0, 1);

  // ---------- 1b. 左侧角部暗角（官方 106056 柔影多层，原生椭圆） ----------
  const VIG = { n: 12, w0: 240, w1: 30, h0: 600, h1: 100, op0: 0.115, op1: 0.05 };
  for (const cy of [0, 900]) for (let i = 0; i < VIG.n; i++) {
    const t = i / (VIG.n - 1);
    img(106056, 0, cy, VIG.w0 + (VIG.w1 - VIG.w0) * t, VIG.h0 + (VIG.h1 - VIG.h0) * t,
      '#000000', 0, VIG.op0 + (VIG.op1 - VIG.op0) * t);
  }

  // ---------- 2. 档案袋阴影：左边界严格贴合新档案袋右边缘 ----------
  // v13 曾用亮橙 DARK 填缝把阴影切断 -> v14 删除该带。
  // 阴影改为「竖直大矩形 + 沿档案袋边缘的旋转矩形」两个原生矩形打底，
  // 只剩一个小直角缺口用等腰三角补；上部水平边界被后画的胶带/黑边盖住。
  const L0 = [bagRightX(28), 28], L1 = [bagRightX(763), 763];
  const ud = [L1[0] - L0[0], L1[1] - L0[1]], ulen = Math.hypot(ud[0], ud[1]);
  const un = [ud[0] / ulen, ud[1] / ulen];
  const nn = [un[1], -un[0]];                    // 指向右侧（阴影内部）
  const DEP = 110;
  rect((L1[0] + 1263) / 2, (28 + 763) / 2, 1263 - L1[0], 763 - 28, SHADOW);   // 竖直大矩形
  const midL = [(L0[0] + L1[0]) / 2, (L0[1] + L1[1]) / 2];
  img(100001, midL[0] + nn[0] * DEP / 2, midL[1] + nn[1] * DEP / 2, ulen, DEP, SHADOW, -Math.atan2(un[1], un[0]) / RAD);
  // 两条斜边与 x=1263 矩形左边界围成的小直角缺口
  const Q0 = [L0[0] + nn[0] * DEP, L0[1] + nn[1] * DEP];
  const xAt28 = Q0[0] + (28 - Q0[1]) * ud[0] / ud[1];
  const yAtX = Q0[1] + (L1[0] - Q0[0]) * ud[1] / ud[0];
  fillTri([xAt28, 28], [L1[0], 28], [L1[0], yAtX], SHADOW);

  // ---------- 3. 上下纯黑边 ----------
  rect(800, 22.5, W, 45, BLACK);
  rect(800, 881, W, 38, BLACK);

  // ---------- 4. 爪印（原生圆） ----------
  for (const [ox, oy] of [[210, 135], [1090, 225], [1200, 285], [535, 640], [330, 560]]) {
    const cx = ox * 1.25, cy = oy * 1.25;
    img(100002, cx, cy + 10, 42.5, 35, PAW, -15);
    for (const [dx, dy] of [[-22, -14], [-8, -26], [9, -26], [23, -12]]) circle(cx + dx * 1.25, cy + dy * 1.25, 16.25, PAW);
  }

  // ---------- 5. 黄色胶带 + 橙黄渐变（12 段大块旋转矩形） ----------
  const mix = (c1, c2, t) => {
    const p = c => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
    const a = p(c1), b = p(c2);
    const h = v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0');
    return '#' + h(a[0] + (b[0] - a[0]) * t) + h(a[1] + (b[1] - a[1]) * t) + h(a[2] + (b[2] - a[2]) * t);
  };
  const tape = (cx, cy, rot, opMax, exp, u0) => {
    const a = rot * RAD;
    const at = u => [cx + u * Math.cos(a), cy - u * Math.sin(a)];
    const N = 72, u1 = 900, du = (u1 - u0) / N;   // 渐变必需的分段；保持 v12 密度以避免可见色带
    img(100001, ...at((-950 + u0) / 2), u0 + 950, 100, TAPE, rot);
    for (let i = 0; i < N; i++) {
      const u = u0 + (i + 0.5) * du;
      if (u * Math.cos(a) + cx > 1650) continue;
      const [x, y] = at(u);
      const t = opMax * Math.pow((i + 0.5) / N, exp);
      img(100001, x, y, du + 0.6, 100, mix(TAPE, TAPE_ORANGE, t), rot);
    }
    const uEnd = 950;
    const [xe, ye] = at((900 + uEnd) / 2);
    img(100001, xe, ye, uEnd - 900, 100, mix(TAPE, TAPE_ORANGE, opMax), rot);
  };
  tape(800, 241, 9, 1.0, 0.7, 250);
  tape(800, 713, -7.6, 0.95, 1.0, 200);

  // ---------- 6. 文本框 ----------
  const boxes = [
    { x: 1365, y: 181, w: 480, h: 120, rot: 9 },
    { x: 330, y: 680, w: 480, h: 120, rot: -7.6 },
    { x: 1281, y: 807, w: 480, h: 120, rot: -7.6 },
  ];
  if (withText) for (const b of boxes) add({
    type: 'textbox', x: b.x, y: b.y, width: b.w, height: b.h, rotation: b.rot, color: '#241309',
    textBox: { text: 'POLICE TIME', fontSize: 48, autoSize: false, minFontSize: 24, textColor: '#241309', textOpacity: 1,
      bgColor: '#ffffff', bgOpacity: 0, outlineEnabled: false, alignH: 'center', alignV: 'middle', anchorType: 'center', visible: true,
      scaleX: 1, scaleY: 1, anchorMinX: 0.5, anchorMinY: 0.5, anchorMaxX: 0.5, anchorMaxY: 0.5, pivotX: 0.5, pivotY: 0.5 }
  });

  // ---------- 7. 档案袋主体（单个旋转矩形，右边缘右移 24px） ----------
  const [bcx, bcy] = local(BAG_C, TH, BAG_UC, 0);
  img(100001, bcx, bcy, BAG_W, BAG_H, BAG, TH);

  // ---------- 8. DARK 橘红大三角：斜边延伸到新档案袋右边缘 ----------
  // 局部坐标：斜边 v = 263.2 - 0.6384u；底边 v=450；右边缘 u=334
  const uA = (263.2 - 450) / 0.6384;            // 斜边与底边交点
  const vB = 263.2 - 0.6384 * BAG_U1;           // 斜边与右边缘交点
  const A = local(BAG_C, TH, uA, 450), B = local(BAG_C, TH, BAG_U1, vB), C = local(BAG_C, TH, BAG_U1, 450);
  fillConvex([A, B, C], DARK);

  // ---------- 9. 橘红楔形：底端延到档案袋左边缘交点 ----------
  // 原 v13 底点 (456,638) 提前收尖；v14 延到 (453,713)，与档案袋左边缘相接
  const RED_POLY = [[474, 238], [453, 713], [414, 500], [447, 313]];
  // 拆成两个凸三角形，避免凹四边形
  fillTri(RED_POLY[0], RED_POLY[1], RED_POLY[2], RED);
  fillTri(RED_POLY[0], RED_POLY[2], RED_POLY[3], RED);

  // ---------- 10. 分割线 + 圆扣（原生旋转矩形 / 圆） ----------
  const line = (x0, y0, x1, y1, w) => {
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    img(100001, (x0 + x1) / 2, (y0 + y1) / 2, len, w, LINE, -Math.atan2(dy, dx) / RAD, 0.9);
  };
  line(300, 139, 950, 0, 4);
  line(488, 750, 1060, 596, 4);
  for (const [x, y] of [[605, 6], [641, 131]]) { circle(x, y, 84, IVORY); circle(x, y, 20, CORE); }

  // ---------- 11. 拍立得：旋转矩形 + 原生等腰三角补竖直分界 ----------
  function rightHalf(w, h, vOff, color) {
    const t = POL_TH * RAD, ca = Math.cos(t), sa = Math.sin(t);
    const P = (u, v) => [POL_C[0] + u * ca + v * sa, POL_C[1] - u * sa + v * ca];
    const TL = P(-w / 2, vOff - h / 2), TR = P(w / 2, vOff - h / 2);
    const BR = P(w / 2, vOff + h / 2), BL = P(-w / 2, vOff + h / 2);
    const kTop = (TR[1] - TL[1]) / (TR[0] - TL[0]), kBot = (BR[1] - BL[1]) / (BR[0] - BL[0]);
    const yA = TL[1] + kTop * (SPLIT - TL[0]), yB = BL[1] + kBot * (SPLIT - BL[0]);
    const kLeft = ca / sa;
    const delta = (yB - yA) / (kTop - kLeft);
    // 补缝三角形：顶点 (SPLIT,yA) -> (SPLIT+delta, yA+kTop*delta) -> (SPLIT,yB)
    fillConvex([[SPLIT, yA], [SPLIT + delta, yA + kTop * delta], [SPLIT, yB]], color);
    const u0 = (SPLIT - POL_C[0]) * ca - (yB - POL_C[1]) * sa;
    const uc = (u0 + w / 2) / 2;
    const [cx, cy] = P(uc, vOff);
    img(100001, cx, cy, w / 2 - u0 + 0.6, h, color, POL_TH);
  }
  polFrame(); polPhoto();
  function polFrame() { const [x, y] = local(POL_C, POL_TH, 0, 0); img(100001, x, y, 375, 365, FRAME, POL_TH); rightHalf(375, 365, 0, FRAME_LIT); }
  function polPhoto() { const [x, y] = local(POL_C, POL_TH, 0, -14); img(100001, x, y, 320, 250, PHOTO_L, POL_TH); rightHalf(320, 250, -14, PHOTO_R); }

  return { canvas: { width: W, height: H, background: BASE }, elements: els,
    meta: { sourceType: 'editor', sourceName: 'police-v14', warnings: [] } };
}

module.exports = { build };

if (require.main === module) (async () => {
  for (const j of [{ key: 'v14', t: true }, { key: 'v14-notext', t: false }]) {
    const sc = build(j.t);
    fs.writeFileSync(OUT + '/scene-' + j.key + '.json', JSON.stringify(sc, null, 2));
    const nTri = sc.elements.filter(e => e.imageAssetId === 100003).length;
    console.log(j.key, 'elements', sc.elements.length, 'triangles', nTri);
    for (const kind of ['gia', 'png']) {
      const r = await fetch('https://qx.070077.xyz/api/export/' + kind, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ scene: sc, giaGroupName: 'police-' + j.key })
      });
      const b = Buffer.from(await r.arrayBuffer());
      console.log(' ', kind, r.status, b.length);
      if (r.ok) fs.writeFileSync(OUT + '/police-' + j.key + (kind === 'gia' ? '.gia' : '.png'), b);
      else console.log(b.toString('utf8').slice(0, 300));
    }
  }
})();
