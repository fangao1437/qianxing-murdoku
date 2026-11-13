// 679 · 从移动端截图量出棋盘/白底板/网格纸的垂直中心，换算 1600 口径需要下移的 Δy
//   x 映射由 1600→1080 得 k=0.675、x0=0（用 board.bg 左右边界验证）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const FILE = 'C:/Users/18182/Documents/Tencent Files/1586811038/nt_qq/nt_data/Pic/2026-11/Thumb/509b763e2547db51b2d098cb919a4ce1_720.jpg';
const im = await loadImage(FILE);
const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
cx.drawImage(im, 0, 0);
const W = im.width, H = im.height, d = cx.getImageData(0, 0, W, H).data;
const px = (x, y) => { const i = (Math.round(y) * W + Math.round(x)) * 4; return [d[i], d[i + 1], d[i + 2]]; };
console.log('移动端截图', W, 'x', H, '宽高比', (W / H).toFixed(3));
const k = W / 1600;
console.log('x 缩放 k =', k.toFixed(4), '（1600→' + W + '，x0=0）');

// 目标色（JPEG 有偏差，用容差）
const TARGETS = {
  boardBg:  { c: [56, 45, 59],   tol: 26, name: '棋盘深色框 #382D3B' },
  paper:    { c: [253, 252, 231], tol: 20, name: '白底板 #FDFCE7' },
  gridPaper:{ c: [248, 224, 168], tol: 26, name: '斜网格纸 #F8E0A8' },
};
for (const [key, t] of Object.entries(TARGETS)) {
  const hit = (c) => Math.abs(c[0] - t.c[0]) < t.tol && Math.abs(c[1] - t.c[1]) < t.tol && Math.abs(c[2] - t.c[2]) < t.tol;
  // 逐行统计命中数（只取棋盘列范围 x∈[0.34W,0.78W]）
  const x0 = Math.round(W * .34), x1 = Math.round(W * .78);
  const rows = [];
  for (let y = 0; y < H; y++) {
    let n = 0; for (let x = x0; x < x1; x++) if (hit(px(x, y))) n++;
    rows.push(n);
  }
  const thr = Math.max(6, (x1 - x0) * .08);
  const ys = rows.map((n, y) => [y, n]).filter(p => p[1] > thr).map(p => p[0]);
  if (!ys.length) { console.log(' ', t.name, '未检出'); continue; }
  const top = Math.min(...ys), bot = Math.max(...ys), cy = (top + bot) / 2;
  console.log(` ${t.name}: y ${top}..${bot}, 中心 ${cy.toFixed(1)}, 屏幕中心 ${(H / 2).toFixed(1)}, 偏上 ${(H / 2 - cy).toFixed(1)}px`);
  console.log(`   ⇒ 1600 口径 Δy = ${((H / 2 - cy) / k).toFixed(2)}px（下移）；原图 y 范围 ${(top / k).toFixed(1)}..${(bot / k).toFixed(1)}`);
}
// 棋盘深色框左右边界（验证 x 映射）
{
  const y = Math.round(H * .45);
  const hit = c => Math.abs(c[0] - 56) < 26 && Math.abs(c[1] - 45) < 26 && Math.abs(c[2] - 59) < 26;
  const xs = []; for (let x = 0; x < W; x++) if (hit(px(x, y))) xs.push(x);
  if (xs.length) console.log(' 深色框 x 范围', Math.min(...xs), Math.max(...xs), '→ 原图', (Math.min(...xs) / k).toFixed(1), (Math.max(...xs) / k).toFixed(1));
}
// 上下留白（用「非背景橙黄」的简单判断：棋盘列里近白/深色像素的最上最下）
{
  const x0 = Math.round(W * .34), x1 = Math.round(W * .78);
  let top = -1, bot = -1;
  for (let y = 0; y < H; y++) {
    let n = 0;
    for (let x = x0; x < x1; x++) { const c = px(x, y); if (c[0] > 215 && c[1] > 205 && c[2] > 185) n++; }
    if (n > (x1 - x0) * .3) { if (top < 0) top = y; bot = y; }
  }
  console.log(' 棋盘列亮色区 y', top, '..', bot, '→ 上留白', top, '下留白', H - 1 - bot);
}
