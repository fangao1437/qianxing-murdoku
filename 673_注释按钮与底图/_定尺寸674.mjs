// 674 定尺寸：以「官方白圆问号」为标尺，把设计稿局部图换算到 1600×900 实机口径，
// 量出设计稿票券真实 W×H；并采火漆水平剖面的高光梯度。
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/package.json');
const { loadImage, createCanvas } = require('@napi-rs/canvas');
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/673_注释按钮与底图/';
async function load(file, norm) {
  const im = await loadImage(CLIP + file);
  let w = im.width, h = im.height;
  const cv = createCanvas(norm ? 1600 : w, norm ? 900 : h), cx = cv.getContext('2d');
  if (norm) cx.drawImage(im, -4, -58, 1604, 960), w = 1600, h = 900;
  else cx.drawImage(im, 0, 0);
  return { w, h, d: cx.getImageData(0, 0, w, h).data };
}
const px = (o, x, y) => { x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= o.w || y >= o.h) return null;
  const i = (y * o.w + x) * 4; return [o.d[i], o.d[i + 1], o.d[i + 2]]; };
const hex = c => c ? '#' + c.map(v => v.toString(16).padStart(2, '0')).join('') : null;
const WHITE = c => c && c[0] > 232 && c[1] > 226 && c[2] > 210;
const dist = (c, t) => Math.hypot(c[0] - t[0], c[1] - t[1], c[2] - t[2]);
const TICKET = c => c && [[140, 40, 0], [175, 50, 0], [203, 76, 25]].some(t => dist(c, t) < 34);
function bbox(o, win, pred) {
  const [x0, y0, x1, y1] = win;
  let n = 0, sx = 0, sy = 0, a = 1e9, b = -1, c = 1e9, d = -1;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (pred(px(o, x, y))) {
    n++; sx += x; sy += y; a = Math.min(a, x); b = Math.max(b, x); c = Math.min(c, y); d = Math.max(d, y);
  }
  return { n, bbox: [a, c, b, d], size: [b - a + 1, d - c + 1], centroid: [sx / n, sy / n] };
}
// 票券旋转 −13°（屏幕顺时针 +13°）校正回局部坐标，取 2%~98% 分位数抑制离群
function localSize(o, win, cx0, cy0) {
  const [x0, y0, x1, y1] = win, a = 13 * Math.PI / 180, L = [], T = [];
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (TICKET(px(o, x, y))) {
    const dx = x - cx0, dy = y - cy0;
    L.push(dx * Math.cos(a) + dy * Math.sin(a));
    T.push(-dx * Math.sin(a) + dy * Math.cos(a));
  }
  L.sort((p, q) => p - q); T.sort((p, q) => p - q);
  const q = (arr, f) => arr[Math.floor(arr.length * f)];
  return { samples: L.length,
    length: +(q(L, .98) - q(L, .02)).toFixed(1), thickness: +(q(T, .98) - q(T, .02)).toFixed(1),
    lx: [+q(L, .02).toFixed(1), +q(L, .98).toFixed(1)], ly: [+q(T, .02).toFixed(1), +q(T, .98).toFixed(1)] };
}

const designTab = await load('clipboard-2026-11-12T00-38-15-262Z-1bd702c9.png', false);
const impl = await load('clipboard-2026-11-12T01-30-21-260Z-4d209a9e.png', true);
const designWax = await load('clipboard-2026-11-12T00-38-15-264Z-3270e1f0.png', false);

// ① 白圆问号标尺
// 窗口收紧到「只含白圆」：设计局部 (130..183, 88..142)，实机 (363..400, 192..230)
const wDesign = bbox(designTab, [125, 82, 195, 155], WHITE);
const wImpl = bbox(impl, [355, 185, 410, 240], WHITE);
const k = (wDesign.size[0] + wDesign.size[1]) / (wImpl.size[0] + wImpl.size[1]);
// ② 设计稿票券局部尺寸
const dq = bbox(designTab, [0, 0, 304, 218], TICKET);
const dLocal = localSize(designTab, [0, 0, 304, 218], dq.centroid[0], dq.centroid[1]);
const iq = bbox(impl, [260, 140, 520, 280], TICKET);
const iLocal = localSize(impl, [260, 140, 520, 280], iq.centroid[0], iq.centroid[1]);
// ③ 火漆水平剖面（设计稿局部图 y=145，x 20..220 每 6px）
const waxProfile = [];
for (let x = 20; x <= 220; x += 6) waxProfile.push({ x, c: hex(px(designWax, x, 145)) });
// ④ 火漆垂直剖面（x=117, y 50..240 每 6px）
const waxVProfile = [];
for (let y = 50; y <= 240; y += 6) waxVProfile.push({ y, c: hex(px(designWax, 117, y)) });

const out = {
  whiteScale: { design: wDesign, impl: wImpl, k: +k.toFixed(3),
    note: '设计局部图相对 1600×900 实机口径的放大倍率（以官方 40×40 白圆问号为标尺）' },
  ticket: { designLocal: dLocal, implLocal: iLocal,
    designIn1600: { length: +(dLocal.length / k).toFixed(1), thickness: +(dLocal.thickness / k).toFixed(1) },
    implIn1600: { length: +iLocal.length.toFixed(1), thickness: +iLocal.thickness.toFixed(1) },
    currentSave: { w: 124, h: 66, base672: { w: 140, h: 66 }, outline: 124 },
  },
  waxProfile, waxVProfile,
};
fs.writeFileSync(DIR + '674_定尺寸.json', JSON.stringify(out, null, 2));
console.log(JSON.stringify({ whiteScale: out.whiteScale, ticket: out.ticket }, null, 2));
console.log('\n=== 火漆水平剖面 y=145 ===');
console.log(waxProfile.map(p => p.x + ':' + p.c).join(' '));
console.log('\n=== 火漆垂直剖面 x=117 ===');
console.log(waxVProfile.map(p => p.y + ':' + p.c).join(' '));
