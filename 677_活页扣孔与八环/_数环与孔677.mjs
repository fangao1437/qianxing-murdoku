// 677 · 在「白纸区」检测深色像素来数环（避开棕边、顶部/底部横条），并量孔/圆头位置
//   设计全屏 1920×1080 → 1600×900；实机全屏 1604×960 → crop(2,30,1600,900)
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
  live676: await norm(CLIP + 'clipboard-2026-11-12T18-53-39-798Z-951172bb.png', 2, 30, 1600, 900),
};
const hex = c => '#' + c.slice(0, 3).map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
for (const [tag, d] of Object.entries(SRC)) {
  const px = (x, y) => { const i = (Math.round(y) * W + Math.round(x)) * 4; return [d[i], d[i + 1], d[i + 2]]; };
  // 白纸区：x∈[26,38]（环末端圆头所在），深色 = 环/孔
  const isDark = c => c[0] < 95 && c[1] < 85 && c[2] < 78;
  console.log('\n========== ' + tag + ' ==========');
  const rows = [];
  for (let y = 180; y <= 850; y++) {
    let n = 0; for (let x = 26; x <= 38; x++) if (isDark(px(x, y))) n++;
    rows.push({ y, n });
  }
  const segs = []; let cur = null;
  for (const r of rows) {
    if (r.n >= 3) { if (!cur) cur = { y0: r.y, y1: r.y, maxN: 0 }; cur.y1 = r.y; cur.maxN = Math.max(cur.maxN, r.n); }
    else if (cur) { segs.push(cur); cur = null; }
  }
  if (cur) segs.push(cur);
  const rings = segs.filter(s => s.y1 - s.y0 >= 5 && s.y1 - s.y0 <= 40);
  console.log(' 白纸区深色段（=环/孔）共 ' + rings.length + ' 个:');
  const centers = [];
  for (const s of rings) {
    const yc = (s.y0 + s.y1) / 2; centers.push(yc);
    console.log(`   y ${s.y0}-${s.y1} (高 ${s.y1 - s.y0 + 1}) 中心 ${yc.toFixed(1)}, 峰值 ${s.maxN}`);
    // 环中心行水平剖面（找深色圆头的 x 范围）
    const runs = []; let prev = null;
    for (let x = 0; x < 60; x++) {
      const c = px(x, yc), q = c.map(v => Math.round(v / 24) * 24);
      if (!prev || q.join() !== prev.q.join()) { runs.push({ x0: x, q, c }); prev = runs[runs.length - 1]; }
      else prev.x1 = x;
    }
    console.log('     ' + runs.map(r => `${r.x0}-${r.x1 ?? r.x0}:${hex(r.c)}`).join(' '));
  }
  if (centers.length > 1) console.log(' 平均间距', ((centers[centers.length - 1] - centers[0]) / (centers.length - 1)).toFixed(2));
  // 白纸上下边界（x=50 处由深棕跳到近白）
  let top = -1, bot = -1;
  for (let y = 150; y < 880; y++) { const c = px(50, y); if (c[0] > 190 && c[1] > 170 && c[2] > 130) { if (top < 0) top = y; bot = y; } }
  console.log(' 白纸(x=50) 上/下边界 y =', top, bot);
  // 棕边(x=10) 上下边界（由橙红封面跳到深棕）
  const bnd = [];
  for (let y = 150; y < 880; y++) { const c = px(10, y); if (c[0] < 100 && c[1] < 70 && c[2] < 60) bnd.push(y); }
  console.log(' 棕边(x=10) 深色范围 y =', bnd[0], bnd[bnd.length - 1]);
}
