/* v19: 严格按设计图重做阴影三处缺陷（2026-11-11）
 *
 * 用户 @skill:ui-review 对比设计图指出 3 个缺陷：
 *   ① 第一组对比：下方轮廓仍然不齐
 *   ② 第二组对比：黄带区域没有阴影设计，且左侧阴影边界不在一条直线上
 *   ③ 第二组对比：阴影中有一个高亮缺漏
 *
 * 【根因】v18 的阴影是 8 块不同斜率的形状拼出来的，且画在胶带之前：
 *   - TUP 三角左边界斜率 -0.65、Q1 左边界 +0.2755、TLEFT 亮三角又是一段，
 *     三段斜率不同 → 「左侧阴影边界不在一条直线上」
 *   - 阴影在胶带之前 → 黄带完全盖住阴影 → 「黄带区域没有阴影设计」
 *   - 拟合闸门被放宽到 99.5%，三角间缝隙露出亮橙底色；再加上 TLEFT 亮红棕
 *     三角 (#B44926) 本身 → 「阴影中有一个高亮缺漏」
 *   - Q2 下边界写成水平线 y=763，而设计图是档案袋底边斜线 → 「下方轮廓仍然不齐」
 *
 * 【v19 构造】从设计图直接量出四条边界，用 tool 仓 fit-primitive-shape.mjs
 *   的 A+B+C 顶角三角生成 100% 覆盖 / 0 溢出的不透明 100003：
 *     L1   x = -0.8847y + 1283.75   实测 MAE 1.06px（y140..250 逐行取色拟合）
 *     袋右缘 x = 924 + 0.2755y      与 L1 交于 (1009,310)
 *     底边  x = -3.6426y + 3565.9  实测 MAE 1.64px（y700..840 逐行取色拟合）
 *     右边界 x = 1263（设计图清晰竖直分界，沿用 v17/v18）
 *   主体拆 S1（L1 上段，y60..310）/S2（袋右缘中段，y310..底边斜线），按 x 分 3 带取
 *   设计图实测色 #94391A / #8F381A / #873619；细长块再按 y 细分以达 100% 覆盖。
 *   另补「黄带阴影」梯形，画在胶带之后、文字之前，橙黄 3 带 #FCA903 /
 *   #F89D04 / #F59403，左边界与 L1 严格共线。
 *   阴影下边界改为设计图实测的档案袋底边斜线 y=978.7-0.2745x（v18 误写成水平
 *   线 y=763，且把阴影一直涂到黑边），斜线以下恢复亮红棕背景 → 下方轮廓齐整。
 *   已按 L1 重定位 TUP 深棕三角、删除 TLEFT 亮块，彻底消除阴影内的高亮缺漏。
 *   下方补 y=805 水平硬边：黄带下缘到 y805 的深棕楔形 + 其下亮红棕背景带。
 *
 * 拍立得配色（用户明确说明是对设计的有意调整，不是差异）、官方 106060 渐晕、
 * 52 条右侧渐变、爪印、胶带渐变、档案袋几何、楔形拟合 wedge-fit.json、
 * 分割线、圆扣、上下黑边全部沿用 v18。
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
// v19 起阴影由 shadow-elements.json 定义；以下仅为设计图边界常量（备查）
const SHADOW_X0 = 900, SHADOW_X1 = 1263, SHADOW_Y0 = 170, SHADOW_Y1 = 763;
const TH = 15.4, BAG_C = [674, 350], BAG_H = 900;
const BAG_U0 = -291, BAG_U1 = 334;   // ★ v19: 左缘右移 19px，RED 贴到档案袋边
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

  // ---------- 2. ★ v19 阴影：按设计图实测边界严格构造的连续多边形 ----------
  //   左边界上段 L1: x=-0.8847y+1283.75（贯穿黄带，实测 MAE 1.06px）
  //   左边界下段：档案袋右缘 x=924+0.2755y，两段在 (1009,310) 相交
  //   右边界 x=1263；下边界 = 档案袋底边斜线 y=978.7-0.2745x（不再用水平 y=763）
  //   全部 100% 覆盖 / 0 溢出，消除三角拼接缝露出亮底色的「高亮缺漏」
  const shadow = JSON.parse(fs.readFileSync(path.join(HERE, 'shadow-elements.json'), 'utf8'));
  for (const e of shadow.elements) img(e.imageAssetId, e.x, e.y, e.width, e.height, e.color, e.rotation, e.opacity);

  // ---------- 2.5 ★ v19 下方亮背景带：设计图 y≈805 的水平硬边 ----------
  //   设计图黄带下方深棕楔形到 y=805 就结束，其下是亮红棕背景 (183,75,37)；
  //   v18 把阴影一直涂到黑边，形成一片渐变暗棕 → 「下方轮廓仍然不齐」。
  //   这里按设计图 y=830 实测色分 6 带重画 y[805,862]，恢复清晰水平硬边。
  const lowerBand = JSON.parse(fs.readFileSync(path.join(HERE, 'lower-band-rects.json'), 'utf8'));
  for (const e of lowerBand) img(e.imageAssetId, e.x, e.y, e.width, e.height, e.color, e.rotation, e.opacity);

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

  // ---------- 5.4 ★ v19 黄带下方深棕楔形（设计图下方轮廓） ----------
  //   上边界 = POLICE TIME 黄带下缘 y=763.4+0.1334(x-800)，下边界 = 水平 y=805。
  //   v18 没有这块，黄带下方直接是一片渐变暗棕，与亮背景之间没有硬边。
  const bottomWedge = JSON.parse(fs.readFileSync(path.join(HERE, 'wedge-bottom.json'), 'utf8'));
  for (const e of bottomWedge.elements) img(e.imageAssetId, e.x, e.y, e.width, e.height, e.color, e.rotation, e.opacity);

  // ---------- 5.5 ★ v19 黄带上的阴影（设计图有、v18 完全没有） ----------
  //   设计图黄色 POLICE 带上有一条斜向硬边，就是阴影左边界 L1 压在胶带上产生的：
  //   L1 左侧亮黄 (252,202,0)，右侧被压暗成橙黄 (248,157,4)。
  //   v18 把阴影画在胶带之前，黄带把它整个盖住了 → 「黄带区域没有阴影设计」。
  //   这里在胶带之后、文字之前补画 L1 右侧沿黄带上下缘的梯形，橙黄分 3 带取实测色。
  //   梯形四边与胶带上下缘、阴影左边界 L1 严格共线，100% 覆盖 / 0 溢出。
  const tapeShadow = JSON.parse(fs.readFileSync(path.join(HERE, 'tape-elements.json'), 'utf8'));
  for (const e of tapeShadow.elements) img(e.imageAssetId, e.x, e.y, e.width, e.height, e.color, e.rotation, e.opacity);

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
  line(483, 750, 1045, 598, 4);   // ★ v19: 设计图实测端点
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
    meta: { sourceType: 'editor', sourceName: 'police-v19', warnings: [] } };
}

module.exports = { build };

if (require.main === module) (async () => {
  for (const j of [{ key: 'v19', t: true }, { key: 'v19-notext', t: false }]) {
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
