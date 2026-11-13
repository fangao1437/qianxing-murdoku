// 677 · 放大用户新给的 676 实机局部/全屏，并重新逐像素数设计稿的活页环与「孔」
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const F = {
  liveCrop:  CLIP + 'clipboard-2026-11-12T18-53-39-796Z-039a55c4.png',   // 676 实机局部
  liveFull:  CLIP + 'clipboard-2026-11-12T18-53-39-798Z-951172bb.png',   // 676 实机全屏
  designCrop: CLIP + 'clipboard-2026-11-12T18-12-49-747Z-dc55a700.png',  // 设计局部
  designFull: CLIP + 'clipboard-2026-11-12T18-12-49-749Z-01c344c8.jpg',  // 设计全屏
};
const hex = c => '#' + c.slice(0, 3).map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
async function upscale(file, out, k) {
  const im = await loadImage(file);
  const cv = createCanvas(im.width * k, im.height * k), cx = cv.getContext('2d');
  cx.imageSmoothingEnabled = false; cx.scale(k, k); cx.drawImage(im, 0, 0);
  fs.writeFileSync(path.join(DIR, out), cv.toBuffer('image/png'));
  console.log(out, im.width, im.height, 'x' + k);
}
await upscale(F.liveCrop, '677_实机局部_x4.png', 4);
await upscale(F.designCrop, '677_设计局部_x4.png', 4);

// 设计局部 82×964 与 676 实机局部：逐行检测「环上缘近黑带」与「孔」（深黑小圆）
for (const [tag, file, k] of [['设计局部', F.designCrop, 1.6], ['实机局部', F.liveCrop, 1]]) {
  const im = await loadImage(file);
  const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
  cx.drawImage(im, 0, 0);
  const d = cx.getImageData(0, 0, im.width, im.height).data, W = im.width, H = im.height;
  const px = (x, y) => { const i = (Math.round(y) * W + Math.round(x)) * 4; return [d[i], d[i + 1], d[i + 2]]; };
  const isBlack = c => c[0] < 46 && c[1] < 40 && c[2] < 36;
  console.log('\n===== ' + tag + ' ' + W + 'x' + H + ' k=' + k + ' =====');
  // x 带宽取左侧 60% 里的一段（避开右侧白纸）
  const x0 = Math.round(W * .05), x1 = Math.round(W * .42);
  const segs = []; let cur = null;
  for (let y = 0; y < H; y++) {
    let n = 0; for (let x = x0; x <= x1; x++) if (isBlack(px(x, y))) n++;
    if (n >= Math.max(3, (x1 - x0) * .4)) { if (!cur) cur = { y0: y, y1: y, maxN: 0 }; cur.y1 = y; cur.maxN = Math.max(cur.maxN, n); }
    else if (cur) { segs.push(cur); cur = null; }
  }
  if (cur) segs.push(cur);
  console.log(' 近黑段（局部像素 → 实机口径 = /' + k + '）:');
  for (const s of segs) console.log(`   y ${s.y0}-${s.y1} (高 ${s.y1 - s.y0 + 1}) 中心 ${((s.y0 + s.y1) / 2).toFixed(1)} → 实机 ${((s.y0 + s.y1) / 2 / k).toFixed(1)}, 峰值 ${s.maxN}`);
  // 孔：在每个环中部附近，找 x 接近白纸左界的深黑块（逐列统计）
  for (const y of [Math.round(H * .2), Math.round(H * .5)]) {
    const runs = []; let prev = null;
    for (let x = 0; x < W; x++) {
      const c = px(x, y), q = c.map(v => Math.round(v / 24) * 24);
      if (!prev || q.join() !== prev.q.join()) { runs.push({ x0: x, q, c }); prev = runs[runs.length - 1]; }
      else prev.x1 = x;
    }
    console.log(` y=${y} 剖面: ` + runs.map(r => `${r.x0}-${r.x1 ?? r.x0}:${hex(r.c)}`).join(' '));
  }
}
