// 663 设计图测量：取色 + 区域主色 + 轮廓扫描 + 局部放大裁剪
// 口径：设计图 jpg 1920x1080；1600x900 屏幕坐标 ×1.2 得 jpg 坐标
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const OUT = path.join(DIR, '预览');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const K = 1.2;
const img = await loadImage(path.join(DIR, '_设计图_本轮.jpg'));
const impl = await loadImage(path.join(DIR, '_实机截图_本轮.png'));
const cv = createCanvas(img.width, img.height), cx = cv.getContext('2d');
cx.drawImage(img, 0, 0);
const D = cx.getImageData(0, 0, img.width, img.height).data;
const cv2 = createCanvas(impl.width, impl.height), cx2 = cv2.getContext('2d');
cx2.drawImage(impl, 0, 0);
const A = cx2.getImageData(0, 0, impl.width, impl.height).data;
const px = (buf, w, x, y) => { const i = (Math.round(y) * w + Math.round(x)) * 4; return [buf[i], buf[i + 1], buf[i + 2]]; };
const hex = c => '#' + c.map(v => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
const dpx = (x, y) => px(D, img.width, x * K, y * K);        // 1600口径 → 设计图
const apx = (x, y) => px(A, impl.width, x + 2, y + 38);      // 实机截图 crop(2,38)

// 区域主色（4bit 量化直方图）
function palette(buf, w, x0, y0, x1, y1, step = 2) {
  const h = new Map();
  for (let y = Math.round(y0); y < y1; y += step) for (let x = Math.round(x0); x < x1; x += step) {
    const [r, g, b] = px(buf, w, x, y);
    const k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    const e = h.get(k) || { n: 0, r: 0, g: 0, b: 0 };
    e.n++; e.r += r; e.g += g; e.b += b; h.set(k, e);
  }
  return [...h.values()].sort((a, b) => b.n - a.n).slice(0, 6)
    .map(e => ({ hex: hex([e.r / e.n, e.g / e.n, e.b / e.n]), pct: +(e.n / ([...h.values()].reduce((s, v) => s + v.n, 0)) * 100).toFixed(1) }));
}

const points = {
  '票券_主体': [384, 200], '票券_左下': [335, 230], '票券_右上': [430, 185], '票券_描边': [384, 172],
  '白底板_左上': [620, 90], '白底板_中左': [600, 400], '白底板_下': [900, 760], '白底板_右': [1210, 400],
  '格纹带_顶': [900, 85], '格纹带_底': [900, 770], '格纹线': [900, 100],
  '火漆_中心': [1320, 340], '火漆_边缘': [1270, 340], '火漆_高光': [1300, 320],
  '线索卡_中': [230, 400], '线索卡_左上': [100, 340], '线索卡_右下': [350, 470],
  '活页环_1': [20, 322], '活页环_2': [20, 415], '活页环_3': [20, 511],
};
console.log('=== 取样点（设计图 / 实机）1600x900 口径 ===');
for (const [k, [x, y]] of Object.entries(points))
  console.log(k.padEnd(16), `(${String(x).padStart(4)},${String(y).padStart(3)})`, '设计', hex(dpx(x, y)), ' 实机', hex(apx(x, y)));

console.log('\n=== 设计图区域主色（jpg 坐标） ===');
const rois = {
  '票券': [370, 195, 550, 295],
  '棋盘白底板_上': [720, 100, 1400, 160],
  '棋盘白底板_左': [700, 300, 740, 700],
  '棋盘白底板_下': [720, 900, 1400, 960],
  '格纹带_顶': [720, 60, 1400, 130],
  '火漆': [1520, 390, 1660, 490],
  '活页环带': [0, 350, 60, 900],
  '线索卡': [120, 400, 500, 470],
};
for (const [k, [x0, y0, x1, y1]] of Object.entries(rois))
  console.log(k.padEnd(18), palette(D, img.width, x0, y0, x1, y1).map(e => `${e.hex}:${e.pct}%`).join('  '));

// 火漆轮廓：在 jpg 上按红色阈值逐行扫描最长连续段
function redSegment(y, x0, x1) {
  let best = null, cur = null;
  for (let x = x0; x < x1; x++) {
    const [r, g, b] = px(D, img.width, x, y);
    const red = r > 120 && r > g * 1.7 && r > b * 1.7 && g < 130;
    if (red) { if (!cur) cur = { a: x, b: x }; else cur.b = x; }
    else if (cur) { if (!best || cur.b - cur.a > best.b - best.a) best = cur; cur = null; }
  }
  if (cur && (!best || cur.b - cur.a > best.b - best.a)) best = cur;
  return best;
}
console.log('\n=== 设计图火漆红色轮廓（jpg 坐标；1600口径 = /1.2） ===');
for (let y = 330; y <= 500; y += 10) {
  const s = redSegment(y, 1450, 1720);
  console.log('y=' + y, s ? `x=${s.a}..${s.b} w=${s.b - s.a}  (1600口径 y=${(y / K).toFixed(0)} x=${(s.a / K).toFixed(0)}..${(s.b / K).toFixed(0)})` : '-');
}

// 局部放大裁剪（1600 口径 → jpg）
const crops = [
  ['663_设计_票券', img, 290, 140, 190, 140, 3],
  ['663_设计_活页环', img, 0, 260, 90, 520, 2],
  ['663_设计_火漆', img, 1240, 270, 200, 200, 2.4],
  ['663_设计_白底板', img, 570, 30, 700, 780, 1],
  ['663_实机_票券', impl, 290, 178, 190, 140, 3],
  ['663_实机_活页环', impl, 0, 298, 90, 520, 2],
  ['663_实机_火漆', impl, 1240, 308, 200, 200, 2.4],
];
for (const [name, src, x, y, w, h, s] of crops) {
  const ox = src === img ? K : 1, oy = src === img ? K : 1;
  const c = createCanvas(Math.round(w * s), Math.round(h * s)), cc = c.getContext('2d');
  cc.imageSmoothingEnabled = true;
  cc.drawImage(src, x * ox, y * oy + (src === impl ? 38 : 0), w * ox, h * oy, 0, 0, c.width, c.height);
  fs.writeFileSync(path.join(OUT, name + '.png'), c.toBuffer('image/png'));
}
console.log('\n局部放大图已输出', crops.length, '张');
