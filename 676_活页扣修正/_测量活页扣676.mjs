// 676 · 逐像素测量设计局部图 / 实机局部图的活页扣：形状、颜色、间距、棕色边与白底边界
// 设计局部 82×964 与实机局部 54×604 都是「实机 1600×900 口径」的裁切；
// 设计局部放大系数 1.6（964/604 ≈ 1.596），故 设计局部像素 /1.6 = 实机口径像素。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const FILES = {
  design: CLIP + 'clipboard-2026-11-12T18-12-49-747Z-dc55a700.png',
  live: CLIP + 'clipboard-2026-11-12T18-12-49-745Z-dad752a9.png',
};
const hex = c => '#' + c.slice(0, 3).map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
for (const [tag, f] of Object.entries(FILES)) {
  const im = await loadImage(f);
  const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
  cx.drawImage(im, 0, 0);
  const d = cx.getImageData(0, 0, im.width, im.height).data;
  const W = im.width, H = im.height;
  const px = (x, y) => { x = Math.round(x); y = Math.round(y); if (x < 0 || y < 0 || x >= W || y >= H) return [0, 0, 0];
    const i = (y * W + x) * 4; return [d[i], d[i + 1], d[i + 2]]; };
  const K = tag === 'design' ? 1.6 : 1;   // 设计局部 → 实机口径的缩放
  console.log('\n========== ' + tag + ' ' + W + 'x' + H + ' (k=' + K + ') ==========');

  // ① 水平剖面：取若干 y，逐列打印颜色段（合并相近色）
  for (const y of [Math.round(H * .12), Math.round(H * .25), Math.round(H * .5)]) {
    const runs = []; let prev = null;
    for (let x = 0; x < W; x++) {
      const c = px(x, y);
      const q = c.map(v => Math.round(v / 24) * 24);
      if (!prev || q.join() !== prev.q.join()) { runs.push({ x0: x, q, c }); prev = runs[runs.length - 1]; }
      else { prev.x1 = x; }
    }
    console.log(' y=' + y + ' 剖面:', runs.map(r => `${r.x0}-${r.x1 ?? r.x0}:${hex(r.c)}`).join(' '));
  }

  // ② 竖直剖面：x = 棕色边中部 / 白纸中部
  for (const x of [Math.round(W * .1), Math.round(W * .35), Math.round(W * .6), Math.round(W * .9)]) {
    const samples = [.1, .3, .5, .7, .9].map(t => hex(px(x, Math.round(H * t))));
    console.log(' x=' + x + ' 竖采样:', samples.join(' '));
  }

  // ③ 活页扣暗色掩膜（明显比棕底暗的近黑/深棕），逐行统计最右 x
  const isRing = c => c[0] < 90 && c[1] < 78 && c[2] < 70 && c[0] < c[1] * 2.2 + 12;
  const rows = [];
  for (let y = 0; y < H; y++) {
    let n = 0, xmax = -1, xs = [];
    for (let x = 0; x < Math.min(W, Math.round(46 * K)); x++) {
      if (isRing(px(x, y))) { n++; xmax = x; xs.push(x); }
    }
    rows.push({ y, n, xmax, xmin: xs.length ? xs[0] : -1 });
  }
  // 连续段（n>=4 视为环）
  const segs = []; let cur = null;
  for (const r of rows) {
    if (r.n >= 4) { if (!cur) cur = { y0: r.y, y1: r.y, n: 0, xmax: 0, xmin: 999 };
      cur.y1 = r.y; cur.n += r.n; cur.xmax = Math.max(cur.xmax, r.xmax); cur.xmin = Math.min(cur.xmin, r.xmin); }
    else if (cur) { segs.push(cur); cur = null; }
  }
  if (cur) segs.push(cur);
  console.log(' 环段（原始像素 -> 实机口径）:');
  for (const s of segs.filter(s => s.y1 - s.y0 > 5))
    console.log(`   y ${s.y0}-${s.y1} (实机 ${(s.y0 / K).toFixed(1)}-${(s.y1 / K).toFixed(1)}) 中心 ${((s.y0 + s.y1) / 2 / K).toFixed(1)}, x ${s.xmin}-${s.xmax} (实机 ${(s.xmin / K).toFixed(1)}-${(s.xmax / K).toFixed(1)}), 暗像素 ${s.n}`);

  // ④ 环内颜色剖面：取第一个环中部，逐 x 每 4px 采样上下 5 行
  const s0 = segs.filter(s => s.y1 - s.y0 > 8)[0];
  if (s0) {
    console.log(' 首个环上下颜色剖面 (x: 上1/4, 中, 下3/4):');
    const yc = Math.round((s0.y0 + s0.y1) / 2), hh = Math.max(2, Math.round((s0.y1 - s0.y0) / 2));
    for (let x = 0; x < Math.min(W, 70); x += 4)
      console.log(`   x=${String(x).padStart(2)} (实机 ${(x / K).toFixed(1)}) 上 ${hex(px(x, yc - Math.round(hh * .6)))} 中 ${hex(px(x, yc))} 下 ${hex(px(x, yc + Math.round(hh * .6)))}`);
  }
  // ⑤ 黄色虚线检测（R>190,G>130,B<110）
  const yellow = [];
  for (let y = 0; y < H; y++) for (let x = 0; x < Math.min(W, Math.round(50 * K)); x++) {
    const c = px(x, y); if (c[0] > 190 && c[1] > 130 && c[2] < 120) yellow.push([x, y]);
  }
  console.log(' 黄色虚线像素数:', yellow.length, 'x范围', yellow.length ? [Math.min(...yellow.map(p => p[0])), Math.max(...yellow.map(p => p[0]))] : '-');
}
