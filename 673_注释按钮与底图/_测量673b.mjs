// 673 精确测量：红色掩膜 → 质心/面积/放射轮廓；并导出 3x 放大局部图与并排对照图
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/package.json');
const { loadImage, createCanvas } = require('@napi-rs/canvas');
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/673_注释按钮与底图/';
const FILES = {
  implTab: 'clipboard-2026-11-12T00-38-15-258Z-1109872e.png',
  implWax: 'clipboard-2026-11-12T00-38-15-259Z-f877aec3.png',
  designTab: 'clipboard-2026-11-12T00-38-15-262Z-1bd702c9.png',
  designWax: 'clipboard-2026-11-12T00-38-15-264Z-3270e1f0.png',
};
async function load(file) {
  const im = await loadImage(file);
  const cv = createCanvas(im.width, im.height), cx = cv.getContext('2d');
  cx.drawImage(im, 0, 0);
  return { cv, w: im.width, h: im.height, d: cx.getImageData(0, 0, im.width, im.height).data };
}
const px = (o, x, y) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= o.w || y >= o.h) return null;
  const i = (y * o.w + x) * 4; return [o.d[i], o.d[i + 1], o.d[i + 2]];
};
// 严格「饱和红」：R 足够高、G/B 低、且与背景棕（G 偏高）区分
const RED = c => c && c[0] >= 135 && c[1] <= 55 && c[2] <= 55 && (c[0] - c[1]) >= 105;
function mask(o) {
  const m = new Uint8Array(o.w * o.h);
  for (let y = 0; y < o.h; y++) for (let x = 0; x < o.w; x++)
    m[y * o.w + x] = RED(px(o, x, y)) ? 1 : 0;
  return m;
}
function analyze(o, m) {
  let n = 0, sx = 0, sy = 0, minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
  for (let y = 0; y < o.h; y++) for (let x = 0; x < o.w; x++) if (m[y * o.w + x]) {
    n++; sx += x; sy += y;
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  }
  const cx0 = sx / n, cy0 = sy / n;
  const radial = [];
  for (let a = 0; a < 360; a += 10) {
    const t = a * Math.PI / 180, dx = Math.cos(t), dy = Math.sin(t);
    let last = 0;
    for (let r = 2; r < Math.max(o.w, o.h); r += 0.5) {
      const x = Math.round(cx0 + dx * r), y = Math.round(cy0 + dy * r);
      if (x < 0 || y < 0 || x >= o.w || y >= o.h) break;
      if (m[y * o.w + x]) last = r;
      else if (last > 6 && r - last > 4) break;
    }
    radial.push(+last.toFixed(1));
  }
  // 逐行：红色连续段（取最长）
  const rows = [];
  for (let y = 0; y < o.h; y += Math.max(1, Math.round(o.h / 24))) {
    let best = null, cur = null;
    for (let x = 0; x < o.w; x++) {
      if (m[y * o.w + x]) { if (!cur) cur = [x, x]; else cur[1] = x; }
      else if (cur) { if (!best || cur[1] - cur[0] > best[1] - best[0]) best = cur; cur = null; }
    }
    if (cur && (!best || cur[1] - cur[0] > best[1] - best[0])) best = cur;
    if (best) rows.push({ y, span: best });
  }
  return { area: n, centroid: [+cx0.toFixed(1), +cy0.toFixed(1)],
    bbox: [minX, minY, maxX, maxY], radial, rows };
}
function zoom(o, k, out) {
  const cv = createCanvas(o.w * k, o.h * k), cx = cv.getContext('2d');
  cx.imageSmoothingEnabled = false;
  cx.drawImage(o.cv, 0, 0, o.w * k, o.h * k);
  fs.writeFileSync(out, cv.toBuffer('image/png'));
}
const result = {};
const loaded = {};
for (const [k, f] of Object.entries(FILES)) {
  const o = await load(CLIP + f); loaded[k] = o;
  const m = mask(o); result[k] = { size: [o.w, o.h], ...analyze(o, m) };
  zoom(o, 3, DIR + '673_放大_' + k + '.png');
}
// 并排：实机(缩放至设计高度) + 设计
for (const [tag, a, b] of [['Tab', 'implTab', 'designTab'], ['Wax', 'implWax', 'designWax']]) {
  const A = loaded[a], B = loaded[b], H = B.h, WA = Math.round(A.w * H / A.h);
  const cv = createCanvas(WA + B.w + 20, H), cx = cv.getContext('2d');
  cx.fillStyle = '#222'; cx.fillRect(0, 0, cv.width, H);
  cx.drawImage(A.cv, 0, 0, WA, H); cx.drawImage(B.cv, WA + 20, 0);
  fs.writeFileSync(DIR + '673_并排_' + tag + '.png', cv.toBuffer('image/png'));
}
fs.writeFileSync(DIR + '673_测量b.json', JSON.stringify(result, null, 2));
for (const [k, v] of Object.entries(result)) {
  console.log('\n===', k, v.size.join('x'), '===');
  console.log('area', v.area, 'centroid', v.centroid, 'bbox', v.bbox);
  console.log('radial', v.radial.join(' '));
  console.log('rows', JSON.stringify(v.rows));
}
