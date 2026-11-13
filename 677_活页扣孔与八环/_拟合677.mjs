// 677 · 从设计全屏图（1920×1080 → 1600×900）在「白纸区」自动检出 8 组活页环，
//      并产出「孔在下 / 环伸进孔里」的分层规格 + 预览。
//   ★ 676 用 x∈[3,22]（棕边内近黑线）检测，顶部/底部横条把首尾两组吞掉，误得 6 组；
//     改用 x∈[26,38]（白纸上的环末端/孔）检测，棕边与横条都不干扰 ⇒ 稳定 8 组。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DESIGN = CLIP + 'clipboard-2026-11-12T18-12-49-749Z-01c344c8.jpg';
const W = 1600, H = 900;
const im = await loadImage(DESIGN);
const cv = createCanvas(W, H), cx = cv.getContext('2d');
cx.drawImage(im, 0, 0, 1920, 1080, 0, 0, W, H);
const d = cx.getImageData(0, 0, W, H).data;
const px = (x, y) => { const i = (Math.round(y) * W + Math.round(x)) * 4; return [d[i], d[i + 1], d[i + 2]]; };

// ① 白纸区深色段（环末端/孔）；排除 y>760 的底部横条
const isDark = c => c[0] < 95 && c[1] < 85 && c[2] < 78;
const segs = []; let cur = null;
for (let y = 250; y <= 760; y++) {
  let n = 0; for (let x = 26; x <= 38; x++) if (isDark(px(x, y))) n++;
  if (n >= 3) { if (!cur) cur = { y0: y, y1: y }; cur.y1 = y; }
  else if (cur) { segs.push(cur); cur = null; }
}
if (cur) segs.push(cur);
const rings = segs.filter(s => s.y1 - s.y0 >= 8 && s.y1 - s.y0 <= 25);
if (rings.length !== 8) throw Error('设计稿环数不是 8：' + rings.length + ' ' + JSON.stringify(segs));
const centers = rings.map(s => (s.y0 + s.y1) / 2);
const step = (centers[7] - centers[0]) / 7;
console.log('设计稿 8 组活页环（1600×900 口径，白纸区检出）：');
rings.forEach((s, i) => console.log(`  #${i + 1} y=${s.y0}-${s.y1} 中心 ${centers[i]}`));
console.log('  平均间距', step.toFixed(2), 'px；676 只有 6 组 y=361..659');

// ② 颜色（设计稿剖面实测，见 676/677_变更与验收.md）
const C = {
  holeOuter: '#1C1410',  // 孔缘：深棕（与环暗基底同色，避免 676 那种纯黑粗环）
  holeInner: '#393024',  // 孔内壁：与环身同色棕灰 ⇒ 靠形状而非色差表现穿插
  outer:     '#1C1410',  // 环暗基底
  top:       '#0A0503',  // 上缘近黑线（y=353/414 x=5..20 #090000）
  mid:       '#393024',  // 环身棕灰（y=422 x=15 #342920）
  lit:       '#514535',  // 右段渐亮（y=422 x=30 #514535）
  low:       '#5E503A',  // 下缘浅棕高光（y=600 x=31 #5E503A）
  tip:       '#2C2318',  // 伸进孔里的环头（与环身过渡）
  tipHi:     '#544B3A',  // 环头下缘高光
  binding:   '#3F1E15',
  midBand:   '#4D2419',
  paper:     '#FDFBEC',
};

// ③ 每组 9 层：孔（2 层）先画在下 → 环带（5 层）压上去 → 环头（2 层）伸进孔内
//    孔比环带高 6px ⇒ 孔的上下缘露出，形成「环穿过孔」的层次（676 是孔在环之上的独立球）
const LAYERS = [
  { key: 'holeOuter', dx: 28, dy: 1,   w: 17, h: 18,   rot: 0,  color: C.holeOuter },
  { key: 'holeInner', dx: 28, dy: 1,   w: 14, h: 13,   rot: 0,  color: C.holeInner },
  { key: 'outer',     dx: 8,  dy: 0,   w: 44, h: 14,   rot: -8, color: C.outer     },
  { key: 'mid',       dx: 9,  dy: -0.5,w: 42, h: 9,    rot: -8, color: C.mid       },
  { key: 'lit',       dx: 20, dy: 0,   w: 24, h: 7,    rot: -8, color: C.lit       },
  { key: 'low',       dx: 9,  dy: 3,   w: 40, h: 4,    rot: -8, color: C.low       },
  { key: 'top',       dx: 7,  dy: -5,  w: 42, h: 3.5,  rot: -8, color: C.top       },
  { key: 'tip',       dx: 29, dy: 2,   w: 13, h: 11,   rot: 0,  color: C.tip       },
  { key: 'tipHi',     dx: 30, dy: 5,   w: 9,  h: 3,    rot: 0,  color: C.tipHi     },
];
const elements = [];
centers.forEach((cy, i) => LAYERS.forEach(L => elements.push({
  name: `art677.ring.${i + 1}.${L.key}`, group: i + 1, kind: L.key,
  cx: L.dx, cy: +(cy + L.dy).toFixed(2), w: L.w, h: L.h, rot: L.rot,
  color: L.color, img: 100002,
})));

// ④ 棕边：与白框 art657.game.notebook.frame (222,517) 396×515 上下严格对齐
const FRAME = { cx: 222, cy: 517, w: 396, h: 515 };
const BIND = { cx: 12, cy: FRAME.cy, w: 24, h: FRAME.h, color: C.binding };
const MID = { name: 'art676.binding.mid', cx: 12, cy: FRAME.cy, w: 12, h: FRAME.h, color: C.midBand };

// ⑤ 预览（3× 放大，画孔在下/环在上的穿插）
const PW = 100, PH = 560, S = 3, Y0 = 250;
const pv = createCanvas(PW * S, PH * S), q = pv.getContext('2d');
q.fillStyle = C.binding; q.fillRect(0, 0, 24 * S, PH * S);
q.fillStyle = C.midBand; q.fillRect(6 * S, 0, 12 * S, PH * S);
q.fillStyle = C.paper; q.fillRect(24 * S, 0, (PW - 24) * S, PH * S);
for (const e of elements) {
  q.save(); q.translate(e.cx * S, (e.cy - Y0) * S); q.rotate(-e.rot * Math.PI / 180); q.scale(S, S);
  q.fillStyle = e.color; q.beginPath(); q.ellipse(0, 0, e.w / 2, e.h / 2, 0, 0, Math.PI * 2); q.fill(); q.restore();
}
fs.writeFileSync(path.join(DIR, '677_活页扣拟合预览.png'), pv.toBuffer('image/png'));

const spec = {
  version: 1,
  design: { file: path.basename(DESIGN), size: [1920, 1080], mapping: '1920x1080 -> 1600x900' },
  detection: { method: '白纸区 x∈[26,38] 深色像素逐行成段（避开棕边与上下横条）',
    segments: rings.map(s => [s.y0, s.y1]), centers, count: 8, step: +step.toFixed(2),
    wrong676Count: 6, wrong676Centers: [361, 422, 480.5, 539, 597.5, 659] },
  hole: { layerOrder: 'holeOuter/holeInner 先画（在环带之下）；环带与环头后画并压进孔内',
    heightGainOverRing: 6, centerX: 28, designRightEdge: 36 },
  binding: { ...BIND, before: { cx: 12, cy: 513.5, w: 24, h: 535 },
    frame: FRAME, top: FRAME.cy - FRAME.h / 2, bottom: FRAME.cy + FRAME.h / 2,
    midBand: MID },
  hidden: { rings676: Array.from({ length: 6 }, (_, i) =>
    ['outer','mid','lit','low','top','tip','tipHi'].map(k => `art676.ring.${i + 1}.${k}`)).flat() },
  colors: C, layers: LAYERS, elements,
};
fs.writeFileSync(path.join(DIR, '677_活页扣图元.json'), JSON.stringify(spec, null, 1));
console.log('产出 677_活页扣图元.json（' + elements.length + ' 层 / 8 组）与拟合预览');
console.log('棕边上下边界', spec.binding.top, spec.binding.bottom, '（白框同值）');
