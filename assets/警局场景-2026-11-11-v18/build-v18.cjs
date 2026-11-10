/* v18: 阴影按设计图完整形状重做（上/左/下边界）+ 橙红区贴档案袋边 + 下方细线复位（2026-11-11）
 *
 * 用户反馈：v17 的「四边形大块」阴影边界形状不完整，左侧/上侧/下侧多个区域都缺；
 *          橙红色区域没贴到文件袋边；下方的黑色细线也与设计图不符。
 *
 * ① 阴影：删掉靠胶带/档案袋遮挡来「借」边界的半透明矩形，改成从设计图量出的
 *    完整多边形，四条边全部显式构造、都是清晰硬边：
 *      上边 = POLICE 胶带下缘斜线 (990,255) -> (1263,212)
 *      左边 = 档案袋右缘斜线     (990,255) -> (1115,695)
 *      下边 = 档案袋底边         (1115,695) -> (869,763)
 *      右边 = x=1263 竖线       (1263,212) -> (1263,763)
 *    凹角拆成 Q1/Q2 两个凸块；另补两块设计图实测的三角：
 *      TUP  [(1250,50),(1185,150),(1270,150)] 胶带上方深棕三角（上侧阴影）；
 *      TLEFT[(996,255),(1055,255),(1013,303)] 胶带下方较亮红棕三角（左侧缺口），
 *            逐行实测 y260 x996-1053 / y280 x1001-1035 / y300 x1006-1017。
 *    按 x 分 3 带（<1100 / 1100-1200 / >1200），颜色取设计图阴影区实测中值
 *    #94391A / #8F381A / #873619，保留右侧渐变明暗过渡。
 *    每块用 tool 仓 fit-primitive-shape.mjs 的 A+B+C 顶角三角生成不透明 100003
 *    （同色不透明重叠无缝、零溢出、覆盖率 >=99.5%），见 shadow-elements.json。
 * ② 橙红贴袋边：设计图 y=520/560/600 深红背景直接接 RED（419/430/440），
 *    v17 夹了 19px 亮橙 BAG 带；BAG_U0 -310 -> -291 让袋左缘与 RED 左缘重合。
 * ③ 下方细线：按设计图实测端点 (483,750) -> (1045,598) 复位。
 * 其余（拍立得配色、官方 106060 渐晕、右侧渐变、楔形拟合 wedge-fit.json 等）沿用 v17。
 */
const fs = require('fs');
const path = require('path');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const HERE = __dirname;
const W = 1600, H = 900;
const BASE = '#B64A20';
const BAG = '#D99331', DARK = '#C86D20', LINE = '#6A3210';
const IVORY = '#FBE6B4', CORE = '#6E2B10';
const FRAME = '#FDFADB', FRAME_LIT = '#FCFAF0';
const PHOTO_L = '#753323', PHOTO_R = '#803A29';       // ★ 不改
const TAPE = '#FCCA00', TAPE_ORANGE = '#B44A00';
const PAW = '#6E2B10', BLACK = '#020101';
const SHADOW_TINT = '#000000', SHADOW_ALPHA = 0.18;   // 设计图实测 背景×0.82
// v18 起阴影由 shadow-elements.json 定义；以下仅为设计图边界常量（备查）
const SHADOW_X0 = 900, SHADOW_X1 = 1263, SHADOW_Y0 = 170, SHADOW_Y1 = 763;
const TH = 15.4, BAG_C = [674, 350], BAG_H = 900;
const BAG_U0 = -291, BAG_U1 = 334;   // ★ v18: 左缘右移 19px，RED 贴到档案袋边
const BAG_W = BAG_U1 - BAG_U0, BAG_UC = (BAG_U0 + BAG_U1) / 2;
const POL_C = [1256, 516], POL_TH = -14;
const SPLIT = 1263;
const RAD = Math.PI / 180;
const local = (c, t, u, v) => { const a = t * RAD; return [c[0] + u * Math.cos(a) + v * Math.sin(a), c[1] - u * Math.sin(a) + v * Math.cos(a)]; };
const rightR = x => x <= 1080 ? 183 : 183 - 113 * Math.pow((x - 1080) / 520, 1.6);
const bgColor = r => { const q = v => Math.max(0, Math.min(255, Math.round(v))); const h = n => q(n).toString(16).padStart(2, '0'); return '#' + h(r) + h(r * 74 / 182) + h(r * 32 / 182); };

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
    const rot = Math.atan2(-n[0], -n[1]) / RAD;
    img(100003, cx, cy, len, lo, color, rot, 1);
  }
  function fillTri(A, B, C, color) {
    edgeTri(A, B, C, color); edgeTri(B, C, A, color); edgeTri(C, A, B, color);
  }
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
  function fillConvex(pts, color) {
    if (pts.length === 3) { fillTri(pts[0], pts[1], pts[2], color); return; }
    for (let i = 0; i < pts.length; i++) edgeTriPoly(pts[i], pts[(i + 1) % pts.length], pts, color);
    for (let i = 1; i < pts.length - 1; i++) fillTri(pts[0], pts[i], pts[i + 1], color);
  }

  // ---------- 1. 底色 + 右侧渐暗（52 条）+ 官方 106060 圆形渐晕 ----------
  rect(800, 450, W, H, BASE);
  const COMP = JSON.parse(fs.readFileSync(OUT + '/v15-right-compensation.json', 'utf8'));
  for (let x = 1080; x < 1600; x += 10) {
    const idx = Math.min(COMP.length - 1, Math.max(0, Math.round((x + 5 - 1080) / 10)));
    rect(x + 5, 450, 11, H, bgColor(rightR(x + 5) * COMP[idx]));
  }
  img(106060, 800, 450, 1800, 1040, '#000000', 0, 1);

  // ---------- 2. ★ v18 阴影：按设计图完整形状的硬边多边形（不再靠遮挡借边界） ----------
  const shadow = JSON.parse(fs.readFileSync(path.join(HERE, 'shadow-elements.json'), 'utf8'));
  for (const e of shadow.elements) img(e.imageAssetId, e.x, e.y, e.width, e.height, e.color, e.rotation, e.opacity);

  // ---------- 3. 上下纯黑边 ----------
  rect(800, 22.5, W, 45, BLACK);
  rect(800, 881, W, 38, BLACK);

  // ---------- 4. 爪印 ----------
  for (const [ox, oy] of [[210, 135], [1090, 225], [1200, 285], [535, 640], [330, 560]]) {
    const cx = ox * 1.25, cy = oy * 1.25;
    img(100002, cx, cy + 10, 42.5, 35, PAW, -15);
    for (const [dx, dy] of [[-22, -14], [-8, -26], [9, -26], [23, -12]]) circle(cx + dx * 1.25, cy + dy * 1.25, 16.25, PAW);
  }

  // ---------- 5. 黄色胶带 + 橙黄渐变 ----------
  const mix = (c1, c2, t) => {
    const p = c => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
    const a = p(c1), b = p(c2);
    const h = v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0');
    return '#' + h(a[0] + (b[0] - a[0]) * t) + h(a[1] + (b[1] - a[1]) * t) + h(a[2] + (b[2] - a[2]) * t);
  };
  const tape = (cx, cy, rot, opMax, exp, u0) => {
    const a = rot * RAD;
    const at = u => [cx + u * Math.cos(a), cy - u * Math.sin(a)];
    const N = 72, u1 = 900, du = (u1 - u0) / N;
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

  // ---------- 7. 档案袋主体 ----------
  const [bcx, bcy] = local(BAG_C, TH, BAG_UC, 0);
  img(100001, bcx, bcy, BAG_W, BAG_H, BAG, TH);

  // ---------- 8. DARK 橘红大三角 ----------
  const uA = (263.2 - 450) / 0.6384;
  const vB = 263.2 - 0.6384 * BAG_U1;
  const A = local(BAG_C, TH, uA, 450), B = local(BAG_C, TH, BAG_U1, vB), C = local(BAG_C, TH, BAG_U1, 450);
  fillConvex([A, B, C], DARK);

  // ---------- 9. ★ 橙红楔形：直接消费拟合工具产出的 26 枚原生 100003 ----------
  const fit = JSON.parse(fs.readFileSync(path.join(HERE, 'wedge-fit.json'), 'utf8'));
  for (const e of fit.elements) img(e.imageAssetId, e.x, e.y, e.width, e.height, e.color, e.rotation, e.opacity);

  // ---------- 10. 分割线 + 圆扣 ----------
  const line = (x0, y0, x1, y1, w) => {
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    img(100001, (x0 + x1) / 2, (y0 + y1) / 2, len, w, LINE, -Math.atan2(dy, dx) / RAD, 0.9);
  };
  line(300, 139, 950, 0, 4);
  line(483, 750, 1045, 598, 4);   // ★ v18: 设计图实测端点
  for (const [x, y] of [[605, 6], [641, 131]]) { circle(x, y, 84, IVORY); circle(x, y, 20, CORE); }

  // ---------- 11. 拍立得（★ 配色保持 v15） ----------
  function rightHalf(w, h, vOff, color) {
    const t = POL_TH * RAD, ca = Math.cos(t), sa = Math.sin(t);
    const P = (u, v) => [POL_C[0] + u * ca + v * sa, POL_C[1] - u * sa + v * ca];
    const TL = P(-w / 2, vOff - h / 2), TR = P(w / 2, vOff - h / 2);
    const BR = P(w / 2, vOff + h / 2), BL = P(-w / 2, vOff + h / 2);
    const kTop = (TR[1] - TL[1]) / (TR[0] - TL[0]), kBot = (BR[1] - BL[1]) / (BR[0] - BL[0]);
    const yA = TL[1] + kTop * (SPLIT - TL[0]), yB = BL[1] + kBot * (SPLIT - BL[0]);
    const kLeft = ca / sa;
    const delta = (yB - yA) / (kTop - kLeft);
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
    meta: { sourceType: 'editor', sourceName: 'police-v18', warnings: [] } };
}

module.exports = { build };

if (require.main === module) (async () => {
  for (const j of [{ key: 'v18', t: true }, { key: 'v18-notext', t: false }]) {
    const sc = build(j.t);
    fs.writeFileSync(OUT + '/scene-' + j.key + '.json', JSON.stringify(sc, null, 2));
    console.log(j.key, 'elements', sc.elements.length, 'triangles', sc.elements.filter(e => e.imageAssetId === 100003).length);
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
