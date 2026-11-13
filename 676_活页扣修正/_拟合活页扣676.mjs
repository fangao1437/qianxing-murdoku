// 676 · 从设计全屏图（1920×1080 → 1600×900 口径）逐像素拟合活页扣
//   ① 在 x∈[3,22] 找「上缘近黑线」水平段 ⇒ 设计稿环的 y 中心（自动，非目测）
//   ② 环的 x 范围/颜色分层由设计稿水平与垂直剖面实测（见 676_变更与验收.md）
//   ③ 输出 676_活页扣图元.json（构建/校验/渲染共用）+ 676_活页扣拟合预览.png
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
const px = (x, y) => { x = Math.round(x); y = Math.round(y); const i = (y * W + x) * 4; return [d[i], d[i + 1], d[i + 2]]; };
const hex = c => '#' + c.slice(0, 3).map(v => Math.round(v).toString(16).padStart(2, '0')).join('');

// ① 上缘近黑线（只取装订边内侧 x∈[3,22]，排除白纸与末端圆头）
const isBlack = c => c[0] < 46 && c[1] < 40 && c[2] < 36;
const rows = [];
for (let y = 260; y <= 720; y++) {
  let n = 0;
  for (let x = 3; x <= 22; x++) if (isBlack(px(x, y))) n++;
  rows.push({ y, n });
}
const rawSegs = []; let cur = null;
for (const r of rows) {
  if (r.n >= 6) { if (!cur) cur = { y0: r.y, y1: r.y, peak: 0 }; cur.y1 = r.y; cur.peak = Math.max(cur.peak, r.n); }
  else if (cur) { rawSegs.push(cur); cur = null; }
}
if (cur) rawSegs.push(cur);
// 环中部的浅棕高光会把上缘黑线切成两段（间隔 7~9px），合并间隔 ≤10px 的相邻段
const segs = [];
for (const s of rawSegs) {
  const p = segs[segs.length - 1];
  if (p && s.y0 - p.y1 <= 10) { p.y1 = s.y1; p.peak = Math.max(p.peak, s.peak); }
  else segs.push({ ...s });
}
const rings = segs.filter(s => s.y1 - s.y0 >= 8 && s.y1 - s.y0 <= 20 && s.y0 > 320 && s.y1 < 680);
if (rings.length !== 6) throw Error('设计稿环段数不符：' + rings.length + ' → ' + JSON.stringify(segs));
// 上缘黑线中心比环整体中心高约 2.5px（实测环段 352-370 中心 361，黑线 352-365 中心 358.5）
const centers = rings.map(s => (s.y0 + s.y1) / 2 + 2.5);
console.log('设计稿 6 组活页环（1600×900 口径）：');
rings.forEach((s, i) => console.log(`  #${i + 1} 上缘黑线 y=${s.y0}-${s.y1}, 中心 y=${centers[i].toFixed(1)}, 峰值黑像素 ${s.peak}`));
const step = (centers[5] - centers[0]) / 5;
console.log('  平均间距', step.toFixed(2), 'px（675 实机为 5 组 / 94px）');

// ② 棕边右界 / 白纸左界：在若干「环之间」的行找首个近白像素
const paperStarts = [];
for (const y of [300, 390, 460, 510, 570, 630, 690]) {
  for (let x = 2; x < 90; x++) {
    const c = px(x, y);
    if (c[0] > 200 && c[1] > 180 && c[2] > 145) { paperStarts.push(x); break; }
  }
}
paperStarts.sort((a, b) => a - b);
const PAPER_X = paperStarts[Math.floor(paperStarts.length / 2)];
console.log('  白纸左界 x 样本', paperStarts, '⇒ 取', PAPER_X, 'px（675 实机为 40）');

// ③ 颜色：设计稿剖面实测（1600 口径），逐点记录来源
const COLOR = {
  outer:  '#1C1410',  // 环整体暗基底（y=422 中心 x=0 #242118 的左端暗值）
  top:    '#0A0503',  // 上缘近黑线：y=353/414 x=5..20 实测 #090000~#0D0101
  mid:    '#393024',  // 主体棕灰：y=422 x=15 #342920 / x=20 #3E3326
  lit:    '#514535',  // 右段渐亮：y=422 x=30 #514535、y=600 x=27 #5F4B32
  low:    '#5E503A',  // 下缘浅棕高光：y=600 x=31~33 #5E503A
  tip:    '#15100D',  // 末端圆头（实测最暗处）：y=430 x=26 #0D0400 / x=33 #080100
  tipBlend:'#2C2318', // 末端与水平段过渡色（介于 outer 与 mid，避免突出成黑球）
  tipHi:  '#544B3A',  // 圆头下缘棕灰：y=430 x=29 #554C3D
  binding:'#3F1E15',  // 棕边主色：y=400 x=10 #3F1E15 / y=700 x=10 #321912
  midBand:'#4D2419',  // 棕边中部亮带：y=500 x=14 #5C2B1C 与 y=400 x=10 #3F1E15 的中值
  paper:  '#FDFBEC',  // 白纸：y=400 x=44 #FCFAED
};

// ④ 每组 7 层椭圆（先画在下）。几何来自设计稿：环右端 x≈35、高≈19、末端圆头下垂
// 第一轮（对照图③）末端是竖直圆柱头；第二轮把水平段收短、上缘黑线止于 x≈26，
// 末端改斜椭圆 rot=30°，做出设计稿「向右下弯的圆润钩头」
const LAYERS = [
  { key: 'outer', dx: 8,  dy: 0,    w: 44, h: 14,  rot: -8,  color: COLOR.outer },
  { key: 'mid',   dx: 9,  dy: -0.5, w: 42, h: 9,   rot: -8,  color: COLOR.mid   },
  { key: 'lit',   dx: 20, dy: 0,    w: 24, h: 7,   rot: -8,  color: COLOR.lit   },
  { key: 'low',   dx: 9,  dy: 3,    w: 40, h: 4,   rot: -8,  color: COLOR.low   },
  { key: 'top',   dx: 7,  dy: -5,   w: 42, h: 3.5, rot: -8,  color: COLOR.top   },
  // 定稿：末端改用与水平段同高的扁圆头（不是竖直圆柱、也不是两枚小球的双球头），
  // 与水平段大幅重叠 + 过渡色 ⇒ 单一圆润的下垂钩头
  { key: 'tip',   dx: 28, dy: 1,   w: 15, h: 12,  rot: 0,  color: COLOR.tipBlend },
  { key: 'tipHi', dx: 29, dy: 5,   w: 9,  h: 3,   rot: 0,  color: COLOR.tipHi   },
];
const elements = [];
centers.forEach((cy, i) => LAYERS.forEach(L => elements.push({
  name: `art676.ring.${i + 1}.${L.key}`,
  cx: L.dx, cy: +(cy + L.dy).toFixed(2), w: L.w, h: L.h, rot: L.rot, color: L.color,
  img: 100002,
})));

// ⑤ 预览：x∈[0,100], y∈[260,720]，3 倍放大
const PW = 100, PH = 460, S = 3, Y0 = 260;
const pv = createCanvas(PW * S, PH * S), q = pv.getContext('2d');
q.fillStyle = COLOR.binding; q.fillRect(0, 0, PAPER_X * S, PH * S);
q.fillStyle = COLOR.midBand; q.fillRect(6 * S, 0, 12 * S, PH * S);
q.fillStyle = COLOR.paper; q.fillRect(PAPER_X * S, 0, (PW - PAPER_X) * S, PH * S);
const draw = (ctx, e) => {
  const x = (e.cx) * S, y = (e.cy - Y0) * S;
  ctx.save(); ctx.translate(x, y); ctx.rotate(-e.rot * Math.PI / 180);
  ctx.scale(S, S); ctx.fillStyle = e.color; ctx.beginPath();
  ctx.ellipse(0, 0, e.w / 2, e.h / 2, 0, 0, Math.PI * 2); ctx.fill(); ctx.restore();
};
for (const e of elements) draw(q, e);
fs.writeFileSync(path.join(DIR, '676_活页扣拟合预览.png'), pv.toBuffer('image/png'));

const spec = {
  version: 1,
  design: { file: path.basename(DESIGN), size: [1920, 1080], mapping: '1920x1080 -> 1600x900 (x0.8333)' },
  measurement: {
    ringCount: 6, centers, step: +step.toFixed(2),
    ringTopSegments: rings.map(s => [s.y0, s.y1]),
    paperLeftX: PAPER_X, paperLeftSamples: paperStarts,
    liveRingCount: 5, liveCenters: [352, 445, 541, 636, 729], liveStep: 94,
    liveBindingWidth: 40, livePaperLeftX: 40, liveBindingColor: '#2E1A12',
    designYellowDashInBinding: 0,
  },
  binding: { centerX: 12, width: PAPER_X, height: 535, centerY: 513.5,
    color: COLOR.binding, midBand: { centerX: 12, width: 12, height: 535, centerY: 513.5, color: COLOR.midBand } },
  hidden: {
    rings: Array.from({ length: 5 }, (_, i) => ['outer', 'hi', 'shade', 'tip'].map(k => `art663.ring.${i + 1}.${k}`)).flat(),
    dashes: Array.from({ length: 12 }, (_, i) => `art658.clues.binding.dash${i + 1}`),
  },
  colors: COLOR, layers: LAYERS, elements,
};
fs.writeFileSync(path.join(DIR, '676_活页扣图元.json'), JSON.stringify(spec, null, 1));
console.log('产出 676_活页扣图元.json（' + elements.length + ' 层）与 676_活页扣拟合预览.png');
