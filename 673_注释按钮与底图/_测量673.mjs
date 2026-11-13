// 673 测量：6 张图的尺寸 / 主色 / 轮廓剖面（给两处局部改动的解析参数用）
// 依赖 qianxing-murdoku-tool/node_modules/@napi-rs/canvas（可读写 png 与 jpg）
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/package.json');
const { loadImage, createCanvas } = require('@napi-rs/canvas');
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const IMG = {
  implFull: CLIP + 'clipboard-2026-11-12T00-38-15-254Z-90427cd9.png',
  implTab: CLIP + 'clipboard-2026-11-12T00-38-15-258Z-1109872e.png',
  implWax: CLIP + 'clipboard-2026-11-12T00-38-15-259Z-f877aec3.png',
  designFull: CLIP + 'clipboard-2026-11-12T00-38-15-260Z-01c344c8.jpg',
  designTab: CLIP + 'clipboard-2026-11-12T00-38-15-262Z-1bd702c9.png',
  designWax: CLIP + 'clipboard-2026-11-12T00-38-15-264Z-3270e1f0.png',
};
async function data(file) {
  const im = await loadImage(file);
  const cv = createCanvas(im.width, im.height);
  const cx = cv.getContext('2d');
  cx.drawImage(im, 0, 0);
  const d = cx.getImageData(0, 0, im.width, im.height).data;
  return { w: im.width, h: im.height, d };
}
const px = (o, x, y) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= o.w || y >= o.h) return null;
  const i = (y * o.w + x) * 4;
  return [o.d[i], o.d[i + 1], o.d[i + 2], o.d[i + 3]];
};
const hex = c => c ? '#' + c.slice(0, 3).map(v => v.toString(16).padStart(2, '0')).join('') : null;
const isRed = c => c && c[0] > 110 && c[0] < 235 && c[1] < 105 && c[2] < 80 && c[3] > 200;
const isWax = c => c && c[0] > 120 && c[1] < 70 && c[2] < 70 && c[3] > 200;

function palette(o, box, pred) {
  const [x0, y0, x1, y1] = box, m = new Map();
  for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
    const c = px(o, x, y); if (!c || (pred && !pred(c))) continue;
    const k = hex(c); m.set(k, (m.get(k) || 0) + 1);
  }
  return [...m].sort((a, b) => b[1] - a[1]).slice(0, 14).map(([color, n]) => ({ color, n }));
}
function rowSpan(o, y, pred) {
  let a = -1, b = -1;
  for (let x = 0; x < o.w; x++) { if (pred(px(o, x, y))) { if (a < 0) a = x; b = x; } }
  return a < 0 ? null : [a, b];
}
function radial(o, cx0, cy0, pred, degStep = 15) {
  const out = [];
  for (let a = 0; a < 360; a += degStep) {
    const t = a * Math.PI / 180, dx = Math.cos(t), dy = Math.sin(t);
    let last = 0;
    for (let r = 4; r < Math.min(o.w, o.h) / 2; r += 0.5) {
      if (pred(px(o, cx0 + dx * r, cy0 + dy * r))) last = r;
      else if (last > 8 && r - last > 3) break;
    }
    out.push({ deg: a, r: +last.toFixed(1) });
  }
  return out;
}

const out = {};
for (const [k, f] of Object.entries(IMG)) {
  const o = await data(f);
  out[k] = { size: [o.w, o.h], samples: {} };
  const P = {
    implTab: [[90, 55], [45, 30], [140, 80], [90, 20], [90, 95], [5, 5], [175, 5]],
    designTab: [[175, 110], [60, 60], [280, 180], [175, 60], [300, 60], [10, 10], [340, 10], [175, 215]],
    implWax: [[90, 85], [90, 20], [30, 85], [150, 85], [90, 150], [5, 5]],
    designWax: [[128, 128], [128, 25], [30, 128], [226, 128], [128, 230], [5, 5]],
  }[k] || [];
  out[k].samples = P.map(([x, y]) => ({ xy: [x, y], rgb: px(o, x, y), hex: hex(px(o, x, y)) }));
  if (k.includes('Tab')) {
    out[k].palette = palette(o, [0, 0, o.w, o.h], isRed);
    out[k].rows = {};
    for (let y = Math.round(o.h * 0.15); y < o.h * 0.9; y += Math.round(o.h / 10)) {
      out[k].rows[y] = { red: rowSpan(o, y, isRed) };
    }
  }
  if (k.includes('Wax')) {
    out[k].palette = palette(o, [0, 0, o.w, o.h], isWax);
    const cx0 = Math.round(o.w / 2), cy0 = Math.round(o.h / 2);
    out[k].radial = radial(o, cx0, cy0, isWax, 15);
    out[k].hLine = Array.from({ length: 9 }, (_, i) => {
      const y = Math.round(o.h * (0.2 + i * 0.075));
      return { y, span: rowSpan(o, y, isWax) };
    });
  }
}
fs.writeFileSync('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/673_注释按钮与底图/673_测量.json', JSON.stringify(out, null, 2));
for (const [k, v] of Object.entries(out)) {
  console.log('\n===', k, v.size.join('x'), '===');
  console.log('samples', v.samples.map(s => s.xy.join(',') + ':' + s.hex).join('  '));
  if (v.palette) console.log('palette', v.palette.slice(0, 8).map(p => p.color + '(' + p.n + ')').join(' '));
  if (v.rows) console.log('rows', JSON.stringify(v.rows));
  if (v.radial) console.log('radial', v.radial.map(r => r.deg + ':' + r.r).join(' '));
  if (v.hLine) console.log('hLine', JSON.stringify(v.hLine));
}
