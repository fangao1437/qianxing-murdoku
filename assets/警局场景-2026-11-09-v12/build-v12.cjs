/* v12: 按 v11 实机截图 + 原始设计图逐点复查后的定点修复
 *
 * 用户指出的四类问题：
 *  1) 档案袋橘红色区域边缘不够平直   -> 楔形改「直边三角」+ 1px 扫描；深橙区扫描步长 5.6px -> 2px、不透明
 *  2) 旁边阴影部分上方有溢出         -> 阴影四边形改到黑色上下边「之下」绘制（黑边盖住尖角）
 *  3) 不同物体间的衔接没做好         -> 竖直分界线 x=1263 贯穿背景 / 拍立得 / 胶带，不再各画各的
 *  4) 拍立得的阴影表现错误           -> 删掉整块深棕矩形投影，改为设计图的「竖直明暗分界」
 *  5) 暗角（用户更正：是「凹的、从中心往周围渐暗」的径向渐晕，v10 及以前版本已有实现）
 *     -> 删掉 v11 的 4 个 106056 矩形大方块，回到 v10 的官方 106060 径向暗角素材；
 *        v12 中途曾误做成「四角各自凸起的同心圆暗斑」，已按用户指正废弃。
 *     其余不符：左上/左下硬边暗块、拍立得右半白框、底带右侧偏暗等一并对齐设计图
 *
 * 基于 v11（dfa8708）稳定结构；场景坐标 1600x900，设计图 1280x720 ×1.25。
 */
const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W = 1600, H = 900;
const BASE = '#B64A20';
const BAG = '#D99331', DARK = '#C86D20', RED = '#C85D11', LINE = '#6A3210';
const IVORY = '#FBE6B4', CORE = '#6E2B10';
const FRAME = '#FBF3CF', FRAME_LIT = '#F8F5EC';
const PHOTO_R = '#513C57', PHOTO_L = '#4A313D';
const TAPE = '#FCCA00', TAPE_ORANGE = '#B44A00';
const PAW = '#6E2B10', SHADOW = '#973813', BLACK = '#020101';
const TH = 15.4, BAG_C = [674, 350], BAG_W = 620, BAG_H = 900;
const POL_C = [1256, 516], POL_TH = 8;
const SPLIT = 1263;            // 设计图 x=1010.4(1280) -> 1600；阴影四边形右边界 / 明暗分界线
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

  // 屏幕坐标任意简单多边形的竖条扫描填充（步长越小，斜边越平直）
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
  // 竖直左边界 + 斜上边界 + 斜下边界的细长三角（用于把「随相框旋转的斜分界」补成屏幕竖直分界）
  function gapTri(x0, yTop0, topK, yBot0, botK, x1, color) {
    for (let x = x0 + 0.5; x < x1; x += 1) {
      const yt = yTop0 + topK * (x - x0);
      const yb = yBot0 + botK * (x - x0);
      if (yb - yt > 0.4) rect(x, (yt + yb) / 2, 1.9, yb - yt + 0.9, color, 1);
    }
  }
  // ---------- 1. 底色 + 右侧渐暗 + 官方径向暗角（凹形） ----------
  // 设计图暗角：中心 183 / 四角 50 / 左边中 178 / 右边中 76 / 上边中 182 / 下边中 183，
  //   等值线以画面中心为圆心、连续向四周渐暗 —— 用户说的「凹的、从中心往周围渐暗」。
  //   v10 及以前版本用官方 106060 径向暗角素材（finalize-v10.cjs 明确记录配方与
  //   knownDiff「暗角是径向渐变，原设计图右侧另有额外压暗」）；v11 把它丢掉换成
  //   4 个 106056 大方块（矩形硬边），v12 恢复官方径向渐晕。
  rect(800, 450, W, H, BASE);
  // 右侧不透明渐变条 = v11 精调的「额外压暗」曲线，原样保留、一行未改
  for (let x = 1080; x < 1600; x += 10) rect(x + 5, 450, 11, H, bgColor(rightR(x + 5)));
  // ★ 官方径向暗角 106060：中心透明 → 四周渐暗，单个控件、凹形连续。
  //   顺序关键：必须画在渐变条「之上」，否则 x=1080 处会出现一条竖直硬边；
  //   而 106060 大尺寸在中线 alpha 极小，叠加后右侧渐暗曲线几乎不变。
  //   v10 配方 1800×1040 op1；本版按设计图剖面调为 2200×1100 op1（中心亮区略大、四角仍明显）。
  //   实测：左上角 R=113（设计 54，v11 矩形块 52）、上边中 164（设计 182）、左边中 168（设计 180）、
  //   中心 182；右侧中线偏差 2.89/255（≈1.1%，渐变条 52 条参数一行未改，曲线形状不变）；
  //   x=1080 无竖边。四角强度弱于设计图是官方 106060 素材 alpha 剖面的固有限制，
  //   若追求更贴数值可改 2600×1400 op0.7（MAE 更低但暗角偏淡）。
  img(106060, 800, 450, 2200, 1100, '#000000', 0, 1);

  // ---------- 2. 档案袋硬边投影（必须先于黑边，尖角不再溢出到黑边之上） ----------
  poly([[1263, 28], [1263, 763], [1107, 763], [1014, 304]], SHADOW, 3);

  // ---------- 3. 上下纯黑边（盖住阴影尖角；胶带仍压在黑边之上） ----------
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

  // ---------- 8. 深橙四边形（步长 5.6px -> 2px，去掉 0.95 半透明叠条） ----------
  const U0 = -310, U1 = 310, N = 310, du = (U1 - U0) / N;
  for (let i = 0; i < N; i++) {
    const u = U0 + (i + 0.5) * du;
    const vTop = 263.2 - 0.6384 * u, vBot = 445;
    if (vBot - vTop < 1) continue;
    bag(100001, u, (vTop + vBot) / 2, du + 0.6, vBot - vTop + 1, DARK, TH, 1);
  }

  // ---------- 9. 橘红楔形：改「全直边四边形」 ----------
  // 设计图实测（1600）：右边界 X=488.4-0.05Y 顶(474,238)->底(456,638)；
  // 左边界折点 (414,500) 最宽，上段经 (447,313) 回到顶点。
  // v11 用抛物线逐点多边形 + 2px 竖条 => 香蕉形 + 明显锯齿；这里四条边全是直线、1px 台阶。
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

  // ---------- 11. 拍立得：无矩形投影；明暗分界改为屏幕竖直 x=SPLIT ----------
  // 顺序：白框 -> 右半白框 -> 完整照片(左色) -> 右半照片(右色)
  // 右半用「与相框同角度的旋转矩形」+「补成竖直分界的细长三角」拼出，
  // 这样外边缘是平滑刚体边、分界线是屏幕竖直线，且与设计图的阴影右边界 x=1263 对齐。
  // 相框四角（rot=+8，中心 1256,516，375x365）：TL(1044.9,361.4) TR(1416.3,309.2)
  //   BR(1467.1,670.6) BL(1095.7,722.8)；x=SPLIT 处顶边 y=330.8、底边 y=699.3
  // 照片四角（中心 1254.05,502.14，320x250）：TL(1078.2,400.6) TR(1395.1,356.0)
  //   BR(1429.9,603.6) BL(1113.1,648.2)；x=SPLIT 处顶边 y=374.6、底边 y=627.1
  pol(100001, 0, 0, 375, 365, FRAME);
  img(100001, 1365.0, 500.7, 154.7, 364.9, FRAME_LIT, 8.03);
  gapTri(1263, 330.8, 7.114, 699.3, -0.1406, 1313.9, FRAME_LIT);
  pol(100001, 0, -14, 320, 250, PHOTO_L);
  img(100001, 1346.45, 489.1, 133.4, 250.0, PHOTO_R, 8.03);
  gapTri(1263, 374.6, 7.115, 627.1, -0.1407, 1297.8, PHOTO_R);

  return { canvas: { width: W, height: H, background: BASE }, elements: els, meta: { sourceType: 'editor', sourceName: 'police-v12', warnings: [] } };
}

(async () => {
  for (const j of [{ key: 'v12', t: true }, { key: 'v12-notext', t: false }]) {
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
