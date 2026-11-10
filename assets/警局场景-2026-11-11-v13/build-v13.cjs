/* v13: 基于 v12 的三处定点调整（2026-11-11）
 *
 * 1) 档案袋橙红色（DARK）区延伸到档案袋边缘：vBot 445->450 贴齐底边，
 *    并把 DARK 右边界与背景阴影四边形左边界之间那条 ~24px 的底色缝隙补成 DARK，
 *    使橙红区一路延伸、与阴影相接（对应设计图 @image#4）。
 * 2) 加强左侧暗角、右侧不变：保留 v12 的 52 条右侧渐变条与官方 106060 渐晕（一行未改），
 *    只在 x<500 叠加按设计图实测亮度场生成的左侧角部压暗网格；x>=500 无任何新增图元。
 * 3) 拍立得按设计图改颜色与旋转：屏幕角度 -8° -> +14°（项目 POL_TH 8 -> -14），
 *    照片由紫改深棕红、外框改更白；大三角形阴影在拍立得上的屏幕竖直分界 x=1263 保持不变，
 *    按新刚体角度重算「同角度旋转矩形 + 补竖直分界的细长三角」。
 *
 * 导出格式与 v12 完全一致：/api/export/{gia,png}，text / notext 两份。
 */
const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W = 1600, H = 900;
const BASE = '#B64A20';
const BAG = '#D99331', DARK = '#C86D20', RED = '#C85D11', LINE = '#6A3210';
const IVORY = '#FBE6B4', CORE = '#6E2B10';
// v13: 设计图拍立得配色（教程/数独界面设计图实测）
const FRAME = '#FDFADB', FRAME_LIT = '#FCFAF0';        // 外框：更白
const PHOTO_L = '#753323', PHOTO_R = '#803A29';        // 照片：深棕红（左=阴影内，右=阴影外）
const TAPE = '#FCCA00', TAPE_ORANGE = '#B44A00';
const PAW = '#6E2B10', SHADOW = '#973813', BLACK = '#020101';
const TH = 15.4, BAG_C = [674, 350], BAG_W = 620, BAG_H = 900;
const POL_C = [1256, 516], POL_TH = -14;   // v12: +8（屏幕 -8°，逆时针）-> -14（屏幕 +14°，顺时针）
const SPLIT = 1263;
const local = (c, t, u, v) => { const a = t * Math.PI / 180; return [c[0] + u * Math.cos(a) + v * Math.sin(a), c[1] - u * Math.sin(a) + v * Math.cos(a)]; };
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
  const circle = (x, y, d, c) => img(100002, x, y, d, d, c);
  const bag = (a, u, v, w, h, c, r = TH, o = 1) => { const [x, y] = local(BAG_C, TH, u, v); img(a, x, y, w, h, c, r, o); };
  const pol = (a, u, v, w, h, c, o = 1) => { const [x, y] = local(POL_C, POL_TH, u, v); img(a, x, y, w, h, c, POL_TH, o); };

  function poly(pts, color, step = 2) {
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
        if (y1 - y0 > 0.5) rect(x, (y0 + y1) / 2, step + 0.9, y1 - y0 + 0.9, color, 1);
      }
    }
  }
  // 竖直左边界 + 斜上边界 + 斜下边界的细长三角（把「随相框旋转的斜分界」补成屏幕竖直分界）
  function gapTri(x0, yTop0, topK, yBot0, botK, x1, color, step = 2) {
    // 不透明实色扫描，步长 2px 仍接近刚体斜边；不透明重叠不会像半透明叠条那样产生条纹
    for (let x = x0 + step / 2; x < x1; x += step) {
      const yt = yTop0 + topK * (x - x0);
      const yb = yBot0 + botK * (x - x0);
      if (yb - yt > 0.4) rect(x, (yt + yb) / 2, step + 0.9, yb - yt + 0.9, color, 1);
    }
  }
  // v13: 按新角度重算「右半旋转矩形 + 补缝三角」，分界仍是屏幕竖直 x=SPLIT
  function rightHalf(w, h, vOff, color) {
    const t = POL_TH * Math.PI / 180, ca = Math.cos(t), sa = Math.sin(t);
    const P = (u, v) => [POL_C[0] + u * ca + v * sa, POL_C[1] - u * sa + v * ca];
    const TL = P(-w / 2, vOff - h / 2), TR = P(w / 2, vOff - h / 2);
    const BR = P(w / 2, vOff + h / 2), BL = P(-w / 2, vOff + h / 2);
    const kTop = (TR[1] - TL[1]) / (TR[0] - TL[0]), kBot = (BR[1] - BL[1]) / (BR[0] - BL[0]);
    const yA = TL[1] + kTop * (SPLIT - TL[0]), yB = BL[1] + kBot * (SPLIT - BL[0]);
    const kLeft = ca / sa;                    // 与相框 v 轴平行的左边界斜率
    const delta = (yB - yA) / (kTop - kLeft);
    gapTri(SPLIT, yA, kTop, yB, kLeft, SPLIT + delta, color);
    const u0 = (SPLIT - POL_C[0]) * ca - (yB - POL_C[1]) * sa;
    const uc = (u0 + w / 2) / 2;
    const [cx, cy] = P(uc, vOff);
    img(100001, cx, cy, w / 2 - u0 + 0.6, h, color, POL_TH);
    return { TL, TR, BR, BL, yA, yB, kTop, kLeft, delta, u0, rect: [cx, cy, w / 2 - u0 + 0.6, h] };
  }

  // ---------- 1. 底色 + 右侧渐暗 + 官方径向暗角（v12 原样，一行未改） ----------
  rect(800, 450, W, H, BASE);
  for (let x = 1080; x < 1600; x += 10) rect(x + 5, 450, 11, H, bgColor(rightR(x + 5)));
  img(106060, 800, 450, 2200, 1100, '#000000', 0, 1);

  // ---------- 1b. ★ v13 左侧暗角加强（右侧零新增图元） ----------
  // 设计图暗角实测：左上 (10,90)=52 / 左中 (10,450)=177 / 左下 (10,840)=53；
  // v12 依次为 161 / 176 / 158 —— 四角明显偏亮、左中基本一致。
  // 采用「官方 106056 柔影多层同心椭圆」：每层自带渐隐羽化，叠出连续的角部压暗，
  // 不会出现逐格实色网格的色块/竖条纹；椭圆中心放在画面左上/左下角点，
  // 半径 <=130x320，故 x>150、y 中部、整个右半幅完全不被覆盖。
  // 参数由 tune-vignette.cjs 按设计图 21 个干净采样点数值搜索得出。
  const VIG = (typeof globalThis.VIG_CFG === 'object' && globalThis.VIG_CFG) ||
    { n: 12, w0: 240, w1: 30, h0: 600, h1: 100, op0: 0.115, op1: 0.05 };
  let vignetteCells = 0;
  for (const cy of [0, 900]) for (let i = 0; i < VIG.n; i++) {
    const t = VIG.n > 1 ? i / (VIG.n - 1) : 0;
    const w = VIG.w0 + (VIG.w1 - VIG.w0) * t;
    const h = VIG.h0 + (VIG.h1 - VIG.h0) * t;
    const op = VIG.op0 + (VIG.op1 - VIG.op0) * t;
    img(106056, 0, cy, w, h, '#000000', 0, op);
    vignetteCells++;
  }

  // ---------- 2. 档案袋硬边投影（v12 原样） ----------
  poly([[1263, 28], [1263, 763], [1107, 763], [1014, 304]], SHADOW, 3);

  // ---------- 3. 上下纯黑边 ----------
  rect(800, 22.5, W, 45, BLACK);
  rect(800, 881, W, 38, BLACK);

  // ---------- 4. 爪印 ----------
  for (const [ox, oy] of [[210, 135], [1090, 225], [1200, 285], [535, 640], [330, 560]]) {
    const cx = ox * 1.25, cy = oy * 1.25;
    img(100002, cx, cy + 10, 42.5, 35, PAW, -15);
    for (const [dx, dy] of [[-22, -14], [-8, -26], [9, -26], [23, -12]]) circle(cx + dx * 1.25, cy + dy * 1.25, 16.25, PAW);
  }

  // ---------- 5. 黄色胶带 + 右侧橙色渐变 ----------
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
  img(100001, BAG_C[0], BAG_C[1], BAG_W, BAG_H, BAG, TH);

  // ---------- 8. 深橙四边形：vBot 445 -> 450，橙红区贴齐档案袋底边 ----------
  const U0 = -310, U1 = 310, N = 310, du = (U1 - U0) / N;
  for (let i = 0; i < N; i++) {
    const u = U0 + (i + 0.5) * du;
    const vTop = 263.2 - 0.6384 * u, vBot = 450;
    if (vBot - vTop < 1) continue;
    bag(100001, u, (vTop + vBot) / 2, du + 0.6, vBot - vTop + 1, DARK, TH, 1);
  }
  // ★ v13: 把 DARK 右边界 (990,331)->(1092,702) 与背景阴影左边界 (1014,304)->(1107,763)
  //   之间那条约 24px 的底色缝隙补成 DARK，使橙红色区域一路延伸到档案袋边缘并与阴影相接。
  //   （设计图 y=400 处 DARK 到 1032 紧接 SHADOW 1034；v12 是 DARK 到 1008 + BASE 1010-1032 + SHADOW 1034）
  poly([[990, 331], [1014, 304], [1094, 702]], DARK, 3);

  // ---------- 9. 橘红楔形（v12 原样） ----------
  const RED_POLY = [[474, 238], [456, 638], [414, 500], [447, 313]];
  poly(RED_POLY, RED, 1);

  // ---------- 10. 分割线 + 圆扣 ----------
  const line = (x0, y0, x1, y1, w) => {
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    img(100001, (x0 + x1) / 2, (y0 + y1) / 2, len, w, LINE, -Math.atan2(dy, dx) * 180 / Math.PI, 0.9);
  };
  line(300, 139, 950, 0, 4);
  line(488, 750, 1060, 596, 4);
  for (const [x, y] of [[605, 6], [641, 131]]) { circle(x, y, 84, IVORY); circle(x, y, 20, CORE); }

  // ---------- 11. 拍立得：v13 角度/颜色；分界 x=SPLIT 与实机一致 ----------
  // 顺序：白框 -> 右半白框 -> 完整照片(左色) -> 右半照片(右色)
  const frameGeo = (() => { pol(100001, 0, 0, 375, 365, FRAME); return rightHalf(375, 365, 0, FRAME_LIT); })();
  const photoGeo = (() => { pol(100001, 0, -14, 320, 250, PHOTO_L); return rightHalf(320, 250, -14, PHOTO_R); })();

  return {
    canvas: { width: W, height: H, background: BASE }, elements: els,
    meta: { sourceType: 'editor', sourceName: 'police-v13', warnings: [] },
    _debug: { vignetteCells, POL_TH, SPLIT, frameGeo, photoGeo,
      colors: { FRAME, FRAME_LIT, PHOTO_L, PHOTO_R, DARK } }
  };
}

module.exports = { build };

if (require.main === module) (async () => {
  for (const j of [{ key: 'v13', t: true }, { key: 'v13-notext', t: false }]) {
    const dbg = build(j.t)._debug;
    const sc = build(j.t);
    delete sc._debug;
    fs.writeFileSync(OUT + '/scene-' + j.key + '.json', JSON.stringify(sc, null, 2));
    console.log(j.key, 'elements', sc.elements.length, 'vignetteCells', dbg.vignetteCells,
      'frameRect', dbg.frameGeo.rect.map(v => +v.toFixed(1)).join(','),
      'photoRect', dbg.photoGeo.rect.map(v => +v.toFixed(1)).join(','));
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
  // 调试几何另存，供 finalize/verify 使用
  const dbg = build(true)._debug;
  fs.writeFileSync(OUT + '/v13-geometry.json', JSON.stringify(dbg, null, 2));
})();
