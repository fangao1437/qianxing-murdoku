/* v11b: 在 v10 稳定结构上做「按设计图精测」的定点修复
 * 1) 环形暗角：右侧渐变 + 四角柔光 + 上下黑边（全部在胶带之下）
 * 2) 档案袋硬边四边形投影（替代 106056 柔光）
 * 3) 橘红弧边楔形（替代 100003 直三角）
 * 4) 深橙四边形：按实测对角线重算局部方程
 * 5) 拍立得：缩小到设计尺寸、改双色照片、改白框色、硬边投影
 * 6) 胶带：改亮黄 + 右侧橙色渐变；爪印首组位置修正
 */
const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W = 1600, H = 900;
const BASE = '#B64A20';
const BAG = '#D99331', DARK = '#C86D20', RED = '#C85D11', LINE = '#6A3210';
const IVORY = '#FBE6B4', CORE = '#6E2B10', FRAME = '#FBF3CF';
const PHOTO_R = '#513C57', PHOTO_L = '#4A313D';
const TAPE = '#FCCA00', TAPE_ORANGE = '#B44A00';
const PAW = '#6E2B10', SHADOW = '#973813', BLACK = '#020101';
const TH = 15.4, BAG_C = [674, 350], BAG_W = 620, BAG_H = 900;
const POL_C = [1256, 516], POL_TH = 8;
const local = (c, t, u, v) => { const a = t * Math.PI / 180; return [c[0] + u * Math.cos(a) + v * Math.sin(a), c[1] - u * Math.sin(a) + v * Math.cos(a)]; };
// 右侧渐变压暗曲线（实测拟合，1600 坐标）
const rightR = x => x <= 1080 ? 183 : 183 - 113 * Math.pow((x - 1080) / 520, 1.6);
const bgColor = r => {
  const q = v => Math.max(0, Math.min(255, Math.round(v)));
  const h = n => q(n).toString(16).padStart(2, '0');
  return '#' + h(r) + h(r * 74 / 182) + h(r * 32 / 182);
};

function build(withText) {
  const els = []; let z = 0;
  const add = o => els.push(Object.assign({ id: 'e' + (++z), rotation: 0, opacity: 1, zIndex: z - 1, isBackground: false }, o));
  const img = (a, x, y, w, h, c, r = 0, o = 1) => add({ type: 'image', x, y, width: w, height: h, rotation: r, color: c, opacity: o, imageAssetId: a, imageType: 'stretch', imageTint: true });
  const rect = (x, y, w, h, c, o = 1) => img(100001, x, y, w, h, c, 0, o);
  const soft = (x, y, w, h, op) => img(106056, x, y, w, h, '#000000', 0, op);
  const circle = (x, y, d, c) => img(100002, x, y, d, d, c);
  const bag = (a, u, v, w, h, c, r = TH, o = 1) => { const [x, y] = local(BAG_C, TH, u, v); img(a, x, y, w, h, c, r, o); };
  const pol = (a, u, v, w, h, c, o = 1) => { const [x, y] = local(POL_C, POL_TH, u, v); img(a, x, y, w, h, c, POL_TH, o); };

  // 竖条扫描填充屏幕坐标任意简单多边形
  function poly(pts, color, opacity = 1, step = 2) {
    const xs = pts.map(p => p[0]), minX = Math.min(...xs), maxX = Math.max(...xs);
    for (let x = minX + step / 2; x < maxX; x += step) {
      const ys = [];
      for (let i = 0; i < pts.length; i++) {
        const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length];
        if ((x1 <= x && x2 > x) || (x2 <= x && x1 > x)) ys.push(y1 + (y2 - y1) * (x - x1) / (x2 - x1));
      }
      ys.sort((a, b) => a - b);
      for (let i = 0; i + 1 < ys.length; i += 2) {
        const y0 = Math.max(0, ys[i]), y1 = Math.min(H, ys[i + 1]);
        if (y1 - y0 > 0.5) rect(x, (y0 + y1) / 2, step + 0.9, y1 - y0 + 0.9, color, opacity);
      }
    }
  }

  // ---------- 1. 底色 + 环形暗角（设计图：中心183 / 四角51 / 右边76） ----------
  rect(800, 450, W, H, BASE);
  for (let x = 1080; x < 1600; x += 10) rect(x + 5, 450, 11, H, bgColor(rightR(x + 5)));
  soft(0, 0, 360, 360, 0.72); soft(0, 900, 360, 360, 0.72);
  soft(1600, 0, 360, 360, 0.30); soft(1600, 900, 360, 360, 0.30);
  rect(800, 22.5, W, 45, BLACK);
  rect(800, 881, W, 38, BLACK);

  // ---------- 2. 档案袋硬边投影（四边形，替代柔光） ----------
  // 设计图 1280: 斜边 x=1030-0.9y，右边界 x=1010，下边界 y=610
  poly([[1263, 28], [1263, 763], [1107, 763], [1014, 304]], SHADOW, 1, 3);

  // ---------- 3. 爪印 ----------
  for (const [ox, oy] of [[210, 135], [1090, 225], [1200, 285], [535, 640], [330, 560]]) {
    const cx = ox * 1.25, cy = oy * 1.25;
    img(100002, cx, cy + 10, 42.5, 35, PAW, -15);
    for (const [dx, dy] of [[-22, -14], [-8, -26], [9, -26], [23, -12]]) circle(cx + dx * 1.25, cy + dy * 1.25, 16.25, PAW);
  }

  // ---------- 4. 黄色胶带 + 右侧橙色渐变 ----------
  // ★ 用「不透明实色条带」直接拼出黄->橙渐变，避免半透明条带重叠产生竖条纹
  const mix = (c1, c2, t) => {
    const p = c => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
    const a = p(c1), b = p(c2);
    const h = v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0');
    return '#' + h(a[0] + (b[0] - a[0]) * t) + h(a[1] + (b[1] - a[1]) * t) + h(a[2] + (b[2] - a[2]) * t);
  };
  const tape = (cx, cy, rot, opMax, exp, u0) => {
    const a = rot * Math.PI / 180;
    const at = u => [cx + u * Math.cos(a), cy - u * Math.sin(a)];
    const N = 72, u1 = 900, du = (u1 - u0) / N;
    // 左侧纯黄整段
    img(100001, ...at((-950 + u0) / 2), u0 + 950, 100, TAPE, rot);
    for (let i = 0; i < N; i++) {
      const u = u0 + (i + 0.5) * du;
      if (u * Math.cos(a) + cx > 1650) continue;
      const [x, y] = at(u);
      const t = opMax * Math.pow((i + 0.5) / N, exp);
      img(100001, x, y, du + 0.6, 100, mix(TAPE, TAPE_ORANGE, t), rot);
    }
    // 右端剩余段用最深的橙色补齐
    const uEnd = 950;
    const [xe, ye] = at((900 + uEnd) / 2);
    img(100001, xe, ye, uEnd - 900, 100, mix(TAPE, TAPE_ORANGE, opMax), rot);
  };
  tape(800, 241, 9, 1.0, 0.7, 250);
  tape(800, 713, -7.6, 0.95, 1.0, 200);

  // ---------- 5. 文本框 ----------
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

  // ---------- 6. 档案袋主体（沿用 v10 刚体旋转矩形，避免锯齿） ----------
  img(100001, BAG_C[0], BAG_C[1], BAG_W, BAG_H, BAG, TH);

  // ---------- 7. 深橙四边形：按设计实测对角线换算到局部坐标 ----------
  // 袋体放大到 620×900 后，斜边 X=1288-0.901Y -> 局部 v = 263.2-0.6384u；底边夹到 v=445
  const U0 = -310, U1 = 310, N = 110, du = (U1 - U0) / N;
  for (let i = 0; i < N; i++) {
    const u = U0 + (i + 0.5) * du;
    const vTop = 263.2 - 0.6384 * u, vBot = 445;
    if (vBot - vTop < 1) continue;
    bag(100001, u, (vTop + vBot) / 2, du + 0.6, vBot - vTop + 1, DARK, TH, 0.95);
  }

  // ---------- 8. 橘红弧边楔形（屏幕坐标逐条铺，左边界实测抛物线） ----------
  const RED_POLY = [
    [474, 238], [476, 250], [472, 300], [468, 350], [464, 400], [460, 450],
    [456, 500], [453, 550], [450, 600], [456, 638],
    [451, 638], [443, 613], [436, 588], [430, 563], [423, 538],
    [417, 513], [414, 488], [416, 463], [424, 438], [433, 388],
    [443, 338], [451, 288], [461, 263],
  ];
  poly(RED_POLY, RED, 1, 2);

  // ---------- 9. 分割线（屏幕坐标，按设计图实测 y=-0.27X+220 / +880） ----------
  const line = (x0, y0, x1, y1, w) => {
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    img(100001, (x0 + x1) / 2, (y0 + y1) / 2, len, w, LINE, -Math.atan2(dy, dx) * 180 / Math.PI, 0.9);
  };
  line(300, 139, 950, 0, 4);
  line(488, 750, 1060, 596, 4);
  // 两个米白圆扣（设计图实测屏幕中心）
  for (const [x, y] of [[605, 6], [641, 131]]) { circle(x, y, 84, IVORY); circle(x, y, 20, CORE); }

  // ---------- 10. 拍立得（缩小到设计尺寸 + 双色照片 + 硬边投影） ----------
  pol(100001, 34, 40, 375, 365, SHADOW, 1);
  pol(100001, 0, 0, 375, 365, FRAME);
  pol(100001, 0, -14, 320, 250, PHOTO_R);
  pol(100001, -82, -14, 156, 250, PHOTO_L);

  return { canvas: { width: W, height: H, background: BASE }, elements: els, meta: { sourceType: 'editor', sourceName: 'police-v11', warnings: [] } };
}

(async () => {
  for (const j of [{ key: 'v11', t: true }, { key: 'v11-notext', t: false }]) {
    const sc = build(j.t);
    fs.writeFileSync(OUT + '/scene-' + j.key + '.json', JSON.stringify(sc, null, 2));
    console.log(j.key, 'elements', sc.elements.length);
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
