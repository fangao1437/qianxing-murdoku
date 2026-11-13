// 676 · 从「设计全屏」与「实机全屏」在 1600×900 统一口径下测量活页环/棕边/白纸/黄虚线
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const W = 1600, H = 900;
async function norm(file, sx, sy, sw, sh) {
  const im = await loadImage(file);
  const cv = createCanvas(W, H), cx = cv.getContext('2d');
  cx.drawImage(im, sx, sy, sw, sh, 0, 0, W, H);
  return cx.getImageData(0, 0, W, H).data;
}
const SRC = {
  design: await norm(CLIP + 'clipboard-2026-11-12T18-12-49-749Z-01c344c8.jpg', 0, 0, 1920, 1080),
  live: await norm(CLIP + 'clipboard-2026-11-12T18-12-49-745Z-0f4aaaf1.png', 2, 30, 1600, 900),
};
const hex = c => '#' + c.slice(0, 3).map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
for (const [tag, d] of Object.entries(SRC)) {
  const px = (x, y) => { x = Math.round(x); y = Math.round(y); if (x < 0 || y < 0 || x >= W || y >= H) return [0, 0, 0];
    const i = (y * W + x) * 4; return [d[i], d[i + 1], d[i + 2]]; };
  console.log('\n========== ' + tag + ' (1600x900 口径) ==========');
  // ① 水平剖面（在环中心附近与两环之间）
  for (const y of [250, 290, 330, 380, 430, 500, 600, 700]) {
    const runs = []; let prev = null;
    for (let x = 0; x < 100; x++) {
      const c = px(x, y), q = c.map(v => Math.round(v / 20) * 20);
      if (!prev || q.join() !== prev.q.join()) { runs.push({ x0: x, q, c }); prev = runs[runs.length - 1]; }
      else prev.x1 = x;
    }
    console.log(` y=${y}: ` + runs.map(r => `${r.x0}-${r.x1 ?? r.x0}:${hex(r.c)}`).join(' '));
  }
  // ② 近黑环掩膜（明显比棕边黑的像素），逐行统计 x∈[0,60]
  const isRing = c => c[0] < 44 && c[1] < 38 && c[2] < 34;
  const rows = [];
  for (let y = 150; y < 850; y++) {
    let n = 0, xmin = 999, xmax = -1;
    for (let x = 0; x < 60; x++) if (isRing(px(x, y))) { n++; xmin = Math.min(xmin, x); xmax = Math.max(xmax, x); }
    rows.push({ y, n, xmin, xmax });
  }
  const segs = []; let cur = null;
  for (const r of rows) {
    if (r.n >= 3) { if (!cur) cur = { y0: r.y, y1: r.y, n: 0, xmin: 999, xmax: 0 };
      cur.y1 = r.y; cur.n += r.n; cur.xmin = Math.min(cur.xmin, r.xmin); cur.xmax = Math.max(cur.xmax, r.xmax); }
    else if (cur) { segs.push(cur); cur = null; }
  }
  if (cur) segs.push(cur);
  console.log(' 近黑环段:');
  for (const s of segs.filter(s => s.y1 - s.y0 >= 3)) {
    const yc = (s.y0 + s.y1) / 2;
    console.log(`   y ${s.y0}-${s.y1} (高 ${s.y1 - s.y0 + 1}) 中心 ${yc.toFixed(1)}, x ${s.xmin}-${s.xmax}`);
    // 环中心行的颜色剖面
    console.log('     ' + [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50].map(x => `${x}:${hex(px(x, yc))}`).join(' '));
    // 上下 1/3 处
    console.log('     上 ' + [5, 15, 25, 35, 45].map(x => `${x}:${hex(px(x, s.y0 + 1))}`).join(' ') +
      ' | 下 ' + [5, 15, 25, 35, 45].map(x => `${x}:${hex(px(x, s.y1 - 1))}`).join(' '));
  }
  // ③ 黄色虚线像素：按行/列聚类
  const isY = c => c[0] > 185 && c[1] > 125 && c[2] < 130 && c[0] - c[2] > 100;
  const colCount = new Array(500).fill(0), rowCount = new Array(900).fill(0);
  for (let y = 150; y < 850; y++) for (let x = 0; x < 500; x++) if (isY(px(x, y))) { colCount[x]++; rowCount[y]++; }
  const cols = colCount.map((n, x) => [x, n]).filter(p => p[1] > 20).map(p => p[0]);
  const rowPeaks = rowCount.map((n, y) => [y, n]).filter(p => p[1] > 40).map(p => p[0]);
  console.log(' 黄虚线集中列 x:', cols.length ? `${Math.min(...cols)}..${Math.max(...cols)} (${cols.length} 列)` : '无');
  console.log(' 黄虚线集中行 y:', rowPeaks.length ? `${Math.min(...rowPeaks)}..${Math.max(...rowPeaks)} (${rowPeaks.length} 行)` : '无');
  // ④ 棕色边右界 / 白纸左界：在若干 y 找从深棕跳到浅色的 x
  for (const y of [300, 400, 500, 600, 700]) {
    let edge = -1;
    for (let x = 2; x < 120; x++) { const c = px(x, y); if (c[0] > 170 && c[1] > 150 && c[2] > 120) { edge = x; break; } }
    console.log(` y=${y} 白/米黄起点 x=${edge}, x=10 ${hex(px(10, y))}, x=25 ${hex(px(25, y))}, x=35 ${hex(px(35, y))}, x=50 ${hex(px(50, y))}`);
  }
}
