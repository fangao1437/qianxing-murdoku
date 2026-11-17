// 687 · 把用户三张图裁切放大（坐标按真实像素）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ROOT = path.resolve('D:/新建文件夹/miHoYo Launcher');
const OUT = path.join(ROOT, 'qianxing-murdoku/687_综合整改');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));

const P1 = 'C:/Users/18182/Pictures/Screenshots/屏幕截图 2026-11-14 034056.png';
const P2 = 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-13T23-37-34-904Z-34c934f6.png';
const P3 = 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-13T23-37-34-906Z-4314ceaf.jpg';

async function crop(src, box, scale, out) {
  const img = await loadImage(src);
  const [x, y, w, h] = box;
  const cv = createCanvas(Math.round(w * scale), Math.round(h * scale));
  const c = cv.getContext('2d');
  c.imageSmoothingEnabled = false;
  c.drawImage(img, x, y, w, h, 0, 0, w * scale, h * scale);
  fs.writeFileSync(path.join(OUT, out), cv.toBuffer('image/png'));
  console.log(out, 'src', img.width + 'x' + img.height, 'box', JSON.stringify(box), 'scale', scale);
}
// 图1：1604×960，左上公告 + 倒计时 / 右下结算按钮 / 弹窗
await crop(P1, [0, 190, 620, 130], 2, '_图1_左上放大.png');
await crop(P1, [1300, 680, 304, 190], 3, '_图1_右下放大.png');
await crop(P1, [440, 140, 740, 720], 1, '_图1_弹窗放大.png');
// 首页对比：整体缩小到同宽并排，另存各自的中央区域
await crop(P2, [380, 80, 860, 880], 1, '_图2_首页中央.png');
await crop(P3, [450, 40, 1020, 1000], 1, '_图3_设计中央.png');
