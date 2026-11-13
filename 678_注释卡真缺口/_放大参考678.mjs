// 678 · 放大用户三张参考图（环末端小椭圆 / 设计注释卡 / 实机注释卡）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const JOBS = [
  ['环末端', CLIP + 'clipboard-2026-11-12T19-27-07-220Z-c92a5376.png', 3],
  ['设计注释卡', CLIP + 'clipboard-2026-11-12T19-27-07-222Z-a07c7cca.png', 3],
  ['实机注释卡', CLIP + 'clipboard-2026-11-12T19-27-07-223Z-04f0df5d.png', 3],
];
for (const [tag, file, k] of JOBS) {
  const im = await loadImage(file);
  const cv = createCanvas(im.width * k, im.height * k), cx = cv.getContext('2d');
  cx.imageSmoothingEnabled = false; cx.scale(k, k); cx.drawImage(im, 0, 0);
  const out = path.join(DIR, `678_参考_${tag}_x${k}.png`);
  fs.writeFileSync(out, cv.toBuffer('image/png'));
  console.log(tag, im.width, im.height, '->', out);
}
