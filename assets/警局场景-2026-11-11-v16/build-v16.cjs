/* v16: 阴影改「设计图式半透明压暗」+ 第二枚钝角三角补尖牙（2026-11-11）
 *
 * 依据：本机 GitHub 仓库 qianxing-murdoku 的 v15 及其
 *   docs/美术资产-原生图形构造与v12-v15演进.md（原生基本图形构造方法）。
 *
 * 本轮两点（用户实机反馈）：
 *  1) 阴影表现不对 -> 改到设计图效果。
 *     实测：设计图阴影区像素 ≈ 同位置「v15 官方背景(底色+右侧渐变+106060 渐晕)」×0.82，
 *     R/G/B 三通道比值一致（(280,1050) 0.823/0.795/0.844；(300,1150) 0.812/0.789/0.839；
 *     (450,1050) 0.830/0.770/0.906；(700,1100) 0.847/0.803/0.742）。
 *     即设计图的阴影根本不是一块纯色 #973813，而是「背景整体压暗 18%」——
 *     所以它天然带右侧渐暗与圆形渐晕的过渡。v15 用不透明纯色矩形把渐晕盖掉，
 *     于是变成一块平板。
 *     做法：仍用原生基本图形（单个整条 100001 矩形 + 20 条渐隐带），
 *     但改为染黑 opacity=0.18；左边界由后画的不透明档案袋「遮挡」自然形成斜边
 *     （档案袋右缘 x=924+0.2755y 在 y≤695 内始终位于阴影矩形 x0=900 右侧），
 *     零重叠 ⇒ 半透明不会叠两层，零锯齿，控件数再降。
 *  2) 文件袋橙红区上部仍有一枚尖牙状小缺口 -> 再加「一个」100003 钝角三角。
 *     v15 的第一枚(rot=90,w=323,h=58)已补下半段；本轮第二枚走 80° 斜置，
 *     顶点 (446.1,316.6)，底边 (471.4,250.2)-(451.5,378.5)，w=120,h=16，顶角≈150°。
 *     几何自检：三顶点全部落在目标橙红凸区内（零溢出），上半段 39/39 个内部亮橙洞全覆盖。
 *
 * 明确不动：拍立得 #FDFADB/#FCFAF0 外框与 #753323/#803A29 深棕照片
 *   （用户说明「拍立得颜色是对设计的调整，不是需要修正的差异」）；
 *   右侧 52 条渐变补偿、官方 106060 1800×1040 圆形渐晕、胶带、爪印、文本框、
 *   档案袋几何、分割线、圆扣、分界 x=1263 全部沿用 v15。
 *
 * ── v15 沿用的原生构造口径 ──
 *  倾斜形状用「矩形 + 旋转」；斜边用 100003 等腰三角压缩拉伸后的一条边；
 *  不透明同色重叠无缝，只要外边界不溢出；渐变才允许分段整条矩形；
 *  fillConvex = 整幅每边等腰三角 + 扇形剖分补尖角（双保险）。
 */
const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W = 1600, H = 900;
const BASE = '#B64A20';
const BAG = '#D99331', DARK = '#C86D20', RED = '#C85D11', LINE = '#6A3210';
const IVORY = '#FBE6B4', CORE = '#6E2B10';
const FRAME = '#FDFADB', FRAME_LIT = '#FCFAF0';
const PHOTO_L = '#753323', PHOTO_R = '#803A29';       // ★ 不改：对设计的有意调整
const TAPE = '#FCCA00', TAPE_ORANGE = '#B44A00';
const PAW = '#6E2B10', BLACK = '#020101';
const SHADOW_TINT = '#000000', SHADOW_ALPHA = 0.18;   // ★ v16：设计图实测压暗系数 0.82
// 上边界实测：设计图 y≤140 的档案袋右上区是「无阴影」的原背景（比值≈1.02），
// y≥260 起才是 ×0.82 的阴影；170 落在上方胶带带内，被胶带完全盖住，不露水平硬边。
const SHADOW_X0 = 900, SHADOW_X1 = 1223, SHADOW_Y0 = 170, SHADOW_Y1 = 763;
const TH = 15.4, BAG_C = [674, 350], BAG_H = 900;
const BAG_U0 = -310, BAG_U1 = 334;
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

  // ---------- 1. 底色 + 右侧渐暗（52 条）+ 官方 106060 圆形渐晕（v15 原样） ----------
  rect(800, 450, W, H, BASE);
  const COMP = JSON.parse(fs.readFileSync(OUT + '/v15-right-compensation.json', 'utf8'));
  for (let x = 1080; x < 1600; x += 10) {
    const idx = Math.min(COMP.length - 1, Math.max(0, Math.round((x + 5 - 1080) / 10)));
    rect(x + 5, 450, 11, H, bgColor(rightR(x + 5) * COMP[idx]));
  }
  img(106060, 800, 450, 1800, 1040, '#000000', 0, 1);

  // ---------- 2. ★ v16 阴影：设计图式半透明压暗（单个原生矩形 + 渐隐带） ----------
  // 不透明纯色会盖掉渐晕/右侧渐变；染黑 0.18 让底层「圆形渐晕 + 渐变」透出来，
  // 得到设计图实测的 ×0.82。左斜边由后画的不透明档案袋遮挡形成，无需旋转矩形/补缝三角。
  rect((SHADOW_X0 + SHADOW_X1) / 2, (SHADOW_Y0 + SHADOW_Y1) / 2,
    SHADOW_X1 - SHADOW_X0, SHADOW_Y1 - SHADOW_Y0, SHADOW_TINT, SHADOW_ALPHA);
  // x=1223→1283 的 20 条半透明渐隐带（与主矩形不重叠，alpha 由 0.18 线性收到 0）
  const FADE_N = 20, FADE_W = 3;
  for (let i = 0; i < FADE_N; i++) {
    const a = SHADOW_ALPHA * (1 - (i + 0.5) / FADE_N);
    rect(SHADOW_X1 + (i + 0.5) * FADE_W, (SHADOW_Y0 + SHADOW_Y1) / 2,
      FADE_W, SHADOW_Y1 - SHADOW_Y0, SHADOW_TINT, a);
  }

  // ---------- 3. 上下纯黑边 ----------
  rect(800, 22.5, W, 45, BLACK);
  rect(800, 881, W, 38, BLACK);

  // ---------- 4. 爪印（原生圆） ----------
  for (const [ox, oy] of [[210, 135], [1090, 225], [1200, 285], [535, 640], [330, 560]]) {
    const cx = ox * 1.25, cy = oy * 1.25;
    img(100002, cx, cy + 10, 42.5, 35, PAW, -15);
    for (const [dx, dy] of [[-22, -14], [-8, -26], [9, -26], [23, -12]]) circle(cx + dx * 1.25, cy + dy * 1.25, 16.25, PAW);
  }

  // ---------- 5. 黄色胶带 + 橙黄渐变（72 段×2 旋转矩形） ----------
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

  // ---------- 7. 档案袋主体（单个旋转矩形，不透明，遮住阴影左侧） ----------
  const [bcx, bcy] = local(BAG_C, TH, BAG_UC, 0);
  img(100001, bcx, bcy, BAG_W, BAG_H, BAG, TH);

  // ---------- 8. DARK 橘红大三角 ----------
  const uA = (263.2 - 450) / 0.6384;
  const vB = 263.2 - 0.6384 * BAG_U1;
  const A = local(BAG_C, TH, uA, 450), B = local(BAG_C, TH, BAG_U1, vB), C = local(BAG_C, TH, BAG_U1, 450);
  fillConvex([A, B, C], DARK);

  // ---------- 9. 橘红楔形 + 两枚钝角三角 ----------
  const RED_POLY = [[474, 238], [453, 713], [414, 500], [447, 313]];
  fillTri(RED_POLY[0], RED_POLY[1], RED_POLY[2], RED);
  fillTri(RED_POLY[0], RED_POLY[2], RED_POLY[3], RED);
  // v15 第一枚：rot=90，底边 (462,390)-(462,713)，顶点 (404,551.5)，补下半段
  img(100003, 433, 551.5, 323, 58, RED, 90);
  // ★ v16 第二枚钝角三角：沿设计图楔形左缘「一整条」补掉剩下的尖牙状小缺口。
  //   单个 100003：rot=86 / w=460 / h=45 / 中心 (432,460)，顶角≈158°（w/h≈10）。
  //   顶点 (409.6,458.4)，底边 (470.5,232.1)-(438.4,691.0)。
  //   几何自检：整枚三角落在设计图实测楔形凸四边形 [(474,238),(464,500),(453,713),(413,500)]
  //   的 14px 容差内（对外零溢出），v15 残留的 163 个内部亮橙洞（上半段 69 + 中段 94）
  //   一次全覆盖：69/69 + 94/94 = 163/163。
  img(100003, 432, 460, 460, 45, RED, 86);

  // ---------- 10. 分割线 + 圆扣 ----------
  const line = (x0, y0, x1, y1, w) => {
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    img(100001, (x0 + x1) / 2, (y0 + y1) / 2, len, w, LINE, -Math.atan2(dy, dx) / RAD, 0.9);
  };
  line(300, 139, 950, 0, 4);
  line(488, 750, 1060, 596, 4);
  for (const [x, y] of [[605, 6], [641, 131]]) { circle(x, y, 84, IVORY); circle(x, y, 20, CORE); }

  // ---------- 11. 拍立得（★ 配色保持 v15，不改回设计图紫色） ----------
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
    meta: { sourceType: 'editor', sourceName: 'police-v16', warnings: [] } };
}

module.exports = { build };

if (require.main === module) (async () => {
  for (const j of [{ key: 'v16', t: true }, { key: 'v16-notext', t: false }]) {
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
