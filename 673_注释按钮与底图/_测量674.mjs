// 674 测量：把「设计全局 1920×1080」与「673 实机 1604×960」统一到 1600×900 口径，
// 逐像素量出 票券/火漆 的包围盒、轮廓、面积、质心，避免再凭目测调尺寸。
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/package.json');
const { loadImage, createCanvas } = require('@napi-rs/canvas');
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/673_注释按钮与底图/';
const SRC = {
  impl673: 'clipboard-2026-11-12T01-30-21-260Z-4d209a9e.png',
  impl672: 'clipboard-2026-11-12T00-38-15-254Z-90427cd9.png',
  design: 'clipboard-2026-11-12T00-38-15-260Z-01c344c8.jpg',
  designTab: 'clipboard-2026-11-12T00-38-15-262Z-1bd702c9.png',
  designWax: 'clipboard-2026-11-12T00-38-15-264Z-3270e1f0.png',
};
async function norm(file, kind) {
  const im = await loadImage(CLIP + file);
  const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
  if (kind === 'impl') cx.drawImage(im, -4, -58, 1604, 960);   // crop(4,58,1600,900)
  else cx.drawImage(im, 0, 0, 1600, 900);                       // 1920×1080 → 1600×900
  return { w: 1600, h: 900, d: cx.getImageData(0, 0, 1600, 900).data };
}
const px = (o, x, y) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= o.w || y >= o.h) return null;
  const i = (y * o.w + x) * 4; return [o.d[i], o.d[i + 1], o.d[i + 2]];
};
const hex = c => c ? '#' + c.map(v => v.toString(16).padStart(2, '0')).join('') : null;
// 严格色距：只认设计稿实测的三级票券色 / 火漆色，排除背景橙棕 #A6482A、#DC642A
const dist = (c, t) => Math.hypot(c[0] - t[0], c[1] - t[1], c[2] - t[2]);
const TICKET = c => c && [[140, 40, 0], [175, 50, 0], [203, 76, 25]]
  .some(t => dist(c, t) < 32);
const WAX = c => c && [[170, 4, 0], [180, 8, 6], [215, 6, 1], [156, 4, 0], [142, 6, 0]]
  .some(t => dist(c, t) < 34);
const WIN = {
  ticket: [250, 110, 580, 310],
  wax: [1230, 250, 1430, 440],
};
function measure(o, win, pred) {
  const [x0, y0, x1, y1] = win;
  let n = 0, sx = 0, sy = 0, minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
  const rows = [];
  for (let y = y0; y < y1; y++) {
    let a = -1, b = -1;
    for (let x = x0; x < x1; x++) if (pred(px(o, x, y))) {
      n++; sx += x; sy += y;
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      if (a < 0) a = x; b = x;
    }
    if (a >= 0) rows.push({ y, span: [a, b] });
  }
  const cx0 = sx / n, cy0 = sy / n;
  const radial = [];
  for (let deg = 0; deg < 360; deg += 10) {
    const t = deg * Math.PI / 180, dx = Math.cos(t), dy = Math.sin(t);
    let last = 0;
    for (let r = 4; r < 200; r += 0.5) {
      if (pred(px(o, cx0 + dx * r, cy0 + dy * r))) last = r;
      else if (last > 8 && r - last > 4) break;
    }
    radial.push(+last.toFixed(1));
  }
  return {
    area: n, centroid: [+cx0.toFixed(1), +cy0.toFixed(1)],
    bbox: [minX, minY, maxX, maxY], size: [maxX - minX + 1, maxY - minY + 1],
    rowSample: rows.filter((_, i) => i % Math.max(1, Math.round(rows.length / 14)) === 0),
    radial,
  };
}
// 局部图：票券/火漆的精确轮廓（不缩放，按原图像素）
async function local(file, pred) {
  const im = await loadImage(CLIP + file);
  const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
  cx.drawImage(im, 0, 0);
  const o = { w: im.width, h: im.height, d: cx.getImageData(0, 0, im.width, im.height).data };
  return { size: [o.w, o.h], ...measure(o, [0, 0, o.w, o.h], pred) };
}
const out = {};
for (const [k, f] of Object.entries(SRC)) {
  const isLocal = k.startsWith('designTab') || k.startsWith('designWax');
  if (isLocal) {
    out[k] = await local(f, k === 'designTab' ? TICKET : WAX);
    continue;
  }
  const o = await norm(f, k.startsWith('impl') ? 'impl' : 'design');
  out[k] = { ticket: measure(o, WIN.ticket, TICKET), wax: measure(o, WIN.wax, WAX) };
}
// 票券局部图：沿 45° 斜线方向采样颜色，找色阶分界（设计稿渐变结构）
{
  const im = await loadImage(CLIP + SRC.designTab);
  const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
  cx.drawImage(im, 0, 0);
  const o = { w: im.width, h: im.height, d: cx.getImageData(0, 0, im.width, im.height).data };
  const shades = [];
  for (let x = 60; x <= 250; x += 10) {
    const row = [];
    for (let y = 60; y <= 140; y += 10) row.push(hex(px(o, x, y)));
    shades.push({ x, row });
  }
  out.designTabShades = shades;
}
fs.writeFileSync(DIR + '674_测量.json', JSON.stringify(out, null, 2));
for (const [k, v] of Object.entries(out)) {
  if (k === 'designTabShades') continue;
  console.log('\n===', k, '===');
  for (const [part, m] of (v.ticket ? Object.entries(v) : [['local', v]])) {
    console.log(part, 'area', m.area, 'bbox', m.bbox, 'size', m.size || '-', 'centroid', m.centroid);
    if (m.radial) console.log('  radial', m.radial.join(' '));
    if (m.rowSample) console.log('  rows', JSON.stringify(m.rowSample));
  }
}
console.log('\n=== designTab shades (x -> y60..140) ===');
for (const s of out.designTabShades) console.log(s.x, s.row.join(' '));
