// 680 · 放大用户实机截图，便于定位被桌子挡住的 X 标记
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const F = 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-12T20-17-57-342Z-af9564f8.png';
const im = await loadImage(F);
console.log('原图', im.width, im.height);
const K = 2;
const cv = createCanvas(im.width * K, im.height * K), cx = cv.getContext('2d');
cx.imageSmoothingEnabled = false; cx.scale(K, K); cx.drawImage(im, 0, 0);
fs.writeFileSync(path.join(DIR, '680_实机_x2.png'), cv.toBuffer('image/png'));
// 棋盘区域裁切（原图 x∈[380,820], y∈[120,580]）放大 3 倍
const CW = 460, CH = 470, K2 = 3;
const c2 = createCanvas(CW * K2, CH * K2), q = c2.getContext('2d');
q.imageSmoothingEnabled = false; q.scale(K2, K2);
q.drawImage(im, 370, 120, CW, CH, 0, 0, CW, CH);
fs.writeFileSync(path.join(DIR, '680_棋盘局部_x3.png'), c2.toBuffer('image/png'));
console.log('产出 680_实机_x2.png / 680_棋盘局部_x3.png');
