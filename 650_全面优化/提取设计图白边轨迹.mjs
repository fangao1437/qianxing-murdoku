// 从 1920x1080 选关设计图提取撕边白线中心轨迹（设计坐标）
// 白线是奶油色 #FFF6E6 系；黄色便签 #FFFCF5 用 R-B>15 && B<235 排除。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));

// 可用命令行覆盖设计图路径；默认使用本轮用户提供的设计图
const DESIGN = process.argv[2] || 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-09T15-35-20-107Z-3d70640f.jpg';
const OUT = HERE;
const im = await loadImage(DESIGN);
const W = im.width, H = im.height;
const cv = createCanvas(W, H), cx = cv.getContext('2d');
cx.drawImage(im, 0, 0);
const d = cx.getImageData(0, 0, W, H).data;
const isWhite = (x, y) => {
  if (x < 0 || y < 0 || x >= W || y >= H) return false;
  const i = (y * W + x) * 4, R = d[i], G = d[i + 1], B = d[i + 2];
  return R > 205 && G > 190 && B > 135 && R - B > 14 && R - B < 95 && B < 238 && G - B > 8;
};

// TR：每列取白线像素的 y 中值（白线在纸片下缘）
function traceTR(x0, x1, y0, y1) {
  const pts = [];
  for (let x = x0; x <= x1; x += 2) {
    const ys = [];
    for (let y = y0; y <= y1; y++) if (isWhite(x, y)) ys.push(y);
    if (ys.length) pts.push([x, ys.reduce((a, b) => a + b, 0) / ys.length, ys.length]);
  }
  return pts;
}
// BL：每行取白线像素的 x 中值（白线在纸片右缘）
function traceBL(y0, y1, x0, x1) {
  const pts = [];
  for (let y = y0; y <= y1; y += 2) {
    const xs = [];
    for (let x = x0; x <= x1; x++) if (isWhite(x, y)) xs.push(x);
    if (xs.length) pts.push([xs.reduce((a, b) => a + b, 0) / xs.length, y, xs.length]);
  }
  return pts;
}

const tr = traceTR(1420, 1919, 0, 300);
const bl = traceBL(780, 1079, 0, 460);
// 中值滤波去掉孤立噪声（窗口 5），保留手撕折角
function median(pts, k = 2) {
  return pts.map((p, i) => {
    const nb = pts.slice(Math.max(0, i - k), Math.min(pts.length, i + k + 1)).map(q => q[1]).sort((a, b) => a - b);
    return [p[0], nb[Math.floor(nb.length / 2)], p[2]];
  });
}
const trS = median(tr), blS = median(bl);
const stat = a => ({ n: a.length, first: a[0], last: a[a.length - 1], thickMin: Math.min(...a.map(p => p[2])), thickMax: Math.max(...a.map(p => p[2])), thickAvg: +(a.reduce((s, p) => s + p[2], 0) / a.length).toFixed(1) });
console.log('design', W, H);
console.log('TR', JSON.stringify(stat(trS)));
console.log('BL', JSON.stringify(stat(blS)));
fs.writeFileSync(path.join(OUT, '651_设计图白边轨迹.json'), JSON.stringify({ design: [W, H], tr: trS, bl: blS }, null, 1));

// 叠加预览：轨迹画成绿色，另存裁切对照
for (const [tag, pts, box] of [['TR', trS, [1400, 0, 520, 320]], ['BL', blS, [0, 760, 500, 320]]]) {
  const k = 2, c = createCanvas(box[2] * k, box[3] * k), cc = c.getContext('2d');
  cc.drawImage(im, box[0], box[1], box[2], box[3], 0, 0, box[2] * k, box[3] * k);
  cc.strokeStyle = '#00ff88'; cc.lineWidth = 2; cc.beginPath();
  pts.forEach((p, i) => { const X = (p[0] - box[0]) * k, Y = (p[1] - box[1]) * k; i ? cc.lineTo(X, Y) : cc.moveTo(X, Y); });
  cc.stroke();
  fs.writeFileSync(path.join(OUT, '651_轨迹核对_' + tag + '.png'), c.toBuffer('image/png'));
}
