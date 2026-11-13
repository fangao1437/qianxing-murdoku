// 677 · 把设计局部/实机局部按 y 分段放大，便于逐个数环、看清「孔」与环的穿插关系
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
  ['设计局部', CLIP + 'clipboard-2026-11-12T18-12-49-747Z-dc55a700.png', 4, 4],
  ['实机局部', CLIP + 'clipboard-2026-11-12T18-53-39-796Z-039a55c4.png', 4, 2],
];
for (const [tag, file, k, parts] of JOBS) {
  const im = await loadImage(file);
  const H = Math.ceil(im.height / parts);
  for (let i = 0; i < parts; i++) {
    const y0 = i * H, hh = Math.min(H, im.height - y0);
    const cv = createCanvas(im.width * k, hh * k), cx = cv.getContext('2d');
    cx.imageSmoothingEnabled = false; cx.scale(k, k);
    cx.drawImage(im, 0, y0, im.width, hh, 0, 0, im.width, hh);
    const out = path.join(DIR, `677_${tag}_段${i + 1}_y${y0}-${y0 + hh}_x${k}.png`);
    fs.writeFileSync(out, cv.toBuffer('image/png'));
    console.log(out);
  }
}
