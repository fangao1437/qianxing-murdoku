// 674：把 673 实机截图两处局部按原图像素裁出并 3× 放大，供与设计稿放大图逐点比对
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/package.json');
const { loadImage, createCanvas } = require('@napi-rs/canvas');
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/673_注释按钮与底图/';
const im = await loadImage(CLIP + 'clipboard-2026-11-12T01-30-21-260Z-4d209a9e.png');
const src = createCanvas(im.width, im.height), sc = src.getContext('2d');
sc.drawImage(im, 0, 0);
// 1600×900 口径 + (4,58) 还原到 1604×960 原图
for (const [tag, box, k] of [
  ['ticket', [250, 110, 330, 200], 3],
  ['wax', [1230, 250, 200, 200], 3],
]) {
  const [x, y, w, h] = box;
  const cv = createCanvas(w * k, h * k), cx = cv.getContext('2d');
  cx.imageSmoothingEnabled = false;
  cx.drawImage(src, x + 4, y + 58, w, h, 0, 0, w * k, h * k);
  fs.writeFileSync(DIR + `674_实机放大_${tag}.png`, cv.toBuffer('image/png'));
  console.log('输出', tag, box);
}
