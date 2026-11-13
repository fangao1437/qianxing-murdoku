// 675 火漆高精度拟合（不省图元）：
//   ① 从设计局部图逐角度提取火漆外缘半径 R(θ)（严格红色掩膜 + 中值平滑）
//   ② 把设计图映射到 1600×900 实机口径（中心 1326,342，k=53/median(R)）
//   ③ 按「外→内」5 层极坐标网格布椭圆，每层椭圆外缘贴 R(θ)、相邻大幅重叠
//   ④ 每枚椭圆颜色取设计图对应位置 7×7 中位色，按 R 通道量化到 8 级红阶
//      ⇒ 形状、顶部鼓包、左右亮弧、中心压印全部来自设计图像素，不是手工调参
// 输出 675_火漆图元.json + 675_火漆拟合预览.png（与设计稿并排）
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/package.json');
const { loadImage, createCanvas } = require('@napi-rs/canvas');
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/675_直边票券与火漆精拟合/';
const DESIGN = CLIP + 'clipboard-2026-11-12T00-38-15-264Z-3270e1f0.png';
const CENTER_D = [117.3, 145.3];         // 设计局部图红色掩膜质心（674 实测）
const CENTER = [1326, 342];              // 实机 1600×900 口径
const TARGET_R = 53;                     // 实机目标外缘半径（设计稿 bbox 105×106）

const im = await loadImage(DESIGN);
const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
cx.drawImage(im, 0, 0);
const d = cx.getImageData(0, 0, im.width, im.height).data;
const W = im.width, H = im.height;
const px = (x, y) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= W || y >= H) return null;
  const i = (y * W + x) * 4; return [d[i], d[i + 1], d[i + 2]];
};
// 严格「火漆红」：排除橙黄背景、白色斜带、深棕背景
const RED = c => c && c[0] > 130 && c[1] < 75 && c[2] < 75 && (c[0] - c[1]) > 100;

// ① 每 1° 求最远连续红色半径（允许 4px 间隙），再取 5° 网格 + 3 点中值平滑
const raw = [];
for (let deg = 0; deg < 360; deg++) {
  const a = deg * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a);
  let last = 0, gap = 0;
  for (let r = 4; r < 140; r += 0.5) {
    if (RED(px(CENTER_D[0] + dx * r, CENTER_D[1] + dy * r))) { last = r; gap = 0; }
    else if (last > 10 && ++gap > 8) break;
  }
  raw.push(last);
}
const smooth = raw.map((_, i) => {
  const v = [-2, -1, 0, 1, 2].map(k => raw[(i + k + 360) % 360]);
  return v.sort((a, b) => a - b)[2];
});
const NA = 72;                                    // 每 5° 一个轮廓采样
const Rd = Array.from({ length: NA }, (_, i) => smooth[i * 5]);
const medianR = [...Rd].sort((a, b) => a - b)[NA >> 1];
const k = TARGET_R / medianR;
const Rreal = Rd.map(v => v * k);

// ② 16 级红阶（按 R 通道量化，G/B 取设计稿实测的近似恒定值）
// 级差 5/255：设计稿亮弧是柔和渐变，级数太少会出现同心硬环
const RAMP = [140, 145, 150, 155, 160, 165, 170, 175, 180, 185, 190, 195, 200, 205, 210, 215];
const quant = c => {
  if (!c || !RED(c)) return '#AA0400';
  let best = 0, bd = 1e9;
  RAMP.forEach((v, i) => { const q = Math.abs(c[0] - v); if (q < bd) { bd = q; best = i; } });
  const R = RAMP[best], G = Math.round(4 + 3 * best / 15), B = Math.round(best / 15);
  return '#' + [R, G, B].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
};
// 设计图对应位置取 5×5 窗口的 90 分位：中位/75 分位会把左右亮带的局部峰值抹平
// （实测最亮色只剩 13~17 枚，其余全是与主体仅差 10/255 的 #B40601 ⇒ 1:1 下高光看不见）。
// 90 分位保留设计稿高光峰值，又比取最大值抗单点噪点。
const colorAt = (r, deg) => {
  const a = deg * Math.PI / 180;
  const x = CENTER_D[0] + (r / k) * Math.cos(a), y = CENTER_D[1] + (r / k) * Math.sin(a);
  const rs = [], gs = [], bs = [];
  for (let j = -2; j <= 2; j++) for (let i = -2; i <= 2; i++) {
    const c = px(x + i, y + j);
    if (c && RED(c)) { rs.push(c[0]); gs.push(c[1]); bs.push(c[2]); }
  }
  if (!rs.length) return null;
  rs.sort((p, q) => p - q); gs.sort((p, q) => p - q); bs.sort((p, q) => p - q);
  const q90 = arr => arr[Math.min(arr.length - 1, Math.floor(arr.length * 0.90))];
  return quant([q90(rs), q90(gs), q90(bs)]);
};
const Rof = deg => Rreal[Math.round(((deg % 360) + 360) % 360 / 5) % NA];

// ③ 极坐标网格：5 层 + 中心，绘制顺序「外→内」⇒ 内层盖住外层内缘，形成干净色阶环带
// 7 层密网格：层间距 7、椭圆直径 15 ⇒ 径向重叠 8px，色阶环带更窄、过渡更柔。
// 相邻椭圆角间距 5、半径 7.5 ⇒ 外缘凹陷 7.5−√(56.25−6.25)≈0.43px，轮廓平滑无扇贝。
// 最外层中心 R−7.5、直径 15 ⇒ 外缘精确贴设计稿 R(θ)。
const LAYERS = [
  { inset: 7.5, spacing: 5, dia: 15 },
  { inset: 14.5, spacing: 5, dia: 15 },
  { inset: 21.5, spacing: 5, dia: 15 },
  { inset: 28.5, spacing: 5, dia: 15 },
  { inset: 35.5, spacing: 5, dia: 15 },
  { inset: 42.5, spacing: 5, dia: 15 },
  { inset: 49.5, spacing: 5, dia: 15 },
];
const elements = [];
for (let L = 0; L < LAYERS.length; L++) {
  const { inset, spacing, dia } = LAYERS[L];
  const baseR = TARGET_R - inset;
  const N = Math.max(6, Math.round(2 * Math.PI * baseR / spacing));
  for (let i = 0; i < N; i++) {
    const deg = 360 * i / N, a = deg * Math.PI / 180;
    const R = Rof(deg);
    const r = R - inset;                       // 该角度外缘精确贴合设计稿轮廓
    if (r < 3) continue;
    // 层序「外→内」：内层椭圆会盖住本层内半，实际可见环带中心 ≈ r + d/2 − gap/2 = r + 4。
    // 取色必须用可见环带中心，否则会把设计稿 r≈42 的 #D70601 强亮区取成暗色。
    const colorR = r + 4;
    const color = colorAt(colorR, deg);
    if (!color) continue;
    elements.push({
      layer: L, deg: +deg.toFixed(1), r: +r.toFixed(2), colorR: +colorR.toFixed(2),
      cx: +(CENTER[0] + r * Math.cos(a)).toFixed(2),
      cy: +(CENTER[1] + r * Math.sin(a)).toFixed(2),
      w: dia, h: dia, rot: 0, color, imageId: 100002,
    });
  }
}
// 中心：1 枚大椭圆兜底（避免中心留洞）
elements.push({ layer: 7, deg: 0, r: 0, cx: CENTER[0], cy: CENTER[1],
  w: 22, h: 22, rot: 0, color: colorAt(4, 0) || '#AA0400', imageId: 100002 });

// ③b 高光峰（设计稿水平剖面实测）：左右 r≈42 处有 #D70601 窄亮带，
// 宽度只有 4~7 实机 px，15px 网格椭圆取分位必然把它平均成中间色。
// ⇒ 按剖面位置单独补一层沿弧密集排列的小椭圆，最后绘制（层序最上），
//   两端用 #CD0701 收尾做柔和过渡；全部仍是设计稿实测色与实测位置。
const HOT_R = 42, HOT_N = 13;
for (const side of [1, -1]) {
  for (let i = 0; i < HOT_N; i++) {
    const deg = (side === 1 ? 0 : 180) - 42 + 84 * i / (HOT_N - 1);
    const a = deg * Math.PI / 180;
    const color = (i === 0 || i === HOT_N - 1) ? '#CD0701' : '#D70701';
    elements.push({
      layer: 8, role: 'highlightPeak', deg: +deg.toFixed(1), r: HOT_R, colorR: HOT_R,
      cx: +(CENTER[0] + HOT_R * Math.cos(a)).toFixed(2),
      cy: +(CENTER[1] + HOT_R * Math.sin(a)).toFixed(2),
      w: 12, h: 12, rot: 0, color, imageId: 100002,
    });
  }
}

// ④ 离线预览：按 elements 顺序画椭圆（与设计稿并排）
const PW = 220, PH = 220, Z = 2;
const prev = createCanvas(PW * Z, PH * Z), pc = prev.getContext('2d');
pc.fillStyle = '#DD9833'; pc.fillRect(0, 0, PW * Z, PH * Z);
pc.save(); pc.scale(Z, Z);
for (const e of elements) {
  pc.fillStyle = e.color; pc.beginPath();
  pc.ellipse(PW / 2 + (e.cx - CENTER[0]), PH / 2 + (e.cy - CENTER[1]), e.w / 2, e.h / 2, 0, 0, Math.PI * 2);
  pc.fill();
}
pc.restore();
fs.writeFileSync(DIR + '675_火漆拟合预览.png', prev.toBuffer('image/png'));

const out = {
  version: 1, name: '675 wax high-precision fit',
  design: { file: DESIGN, size: [W, H], center: CENTER_D, medianRadiusDesign: +medianR.toFixed(2) },
  mapping: { k: +k.toFixed(5), center: CENTER, targetRadius: TARGET_R },
  outline: { samples: NA, designRadius: Rd.map(v => +v.toFixed(2)),
    realRadius: Rreal.map(v => +v.toFixed(2)) },
  colorRamp: RAMP.map(v => '#' + v.toString(16).toUpperCase()),
  gates: { elements: elements.length, maxElementRadius: +Math.max(...elements.map(e =>
    Math.hypot(e.cx - CENTER[0], e.cy - CENTER[1]) + e.w / 2)).toFixed(2), targetRadius: TARGET_R },
  elements,
};
fs.writeFileSync(DIR + '675_火漆图元.json', JSON.stringify(out, null, 2));
console.log(JSON.stringify({ medianRadiusDesign: +medianR.toFixed(2), k: +k.toFixed(5),
  elements: elements.length,
  layers: LAYERS.map((_, L) => elements.filter(e => e.layer === L).length),
  outlineMin: +Math.min(...Rreal).toFixed(2), outlineMax: +Math.max(...Rreal).toFixed(2),
  maxElementRadius: out.gates.maxElementRadius,
  colors: [...new Set(elements.map(e => e.color))].sort() }, null, 2));
