// 676 · 把用户给的四张参考图（实机局部/全屏、设计局部/全屏）放大保存，便于逐像素对照
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const SRC = [
  ['实机局部', CLIP + 'clipboard-2026-11-12T18-12-49-745Z-dad752a9.png', 4],
  ['实机全屏', CLIP + 'clipboard-2026-11-12T18-12-49-745Z-0f4aaaf1.png', 2],
  ['设计局部', CLIP + 'clipboard-2026-11-12T18-12-49-747Z-dc55a700.png', 2],
  ['设计全屏', CLIP + 'clipboard-2026-11-12T18-12-49-749Z-01c344c8.jpg', 1],
];
for (const [tag, file, k] of SRC) {
  const im = await loadImage(file);
  const cv = createCanvas(im.width * k, im.height * k), cx = cv.getContext('2d');
  cx.imageSmoothingEnabled = false;
  cx.drawImage(im, 0, 0, cv.width, cv.height);
  const out = path.join(DIR, `676_参考_${tag}_x${k}.png`);
  fs.writeFileSync(out, cv.toBuffer('image/png'));
  console.log(tag, im.width, im.height, '->', out);
}
