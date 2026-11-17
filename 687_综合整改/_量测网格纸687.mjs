// 687 · 量测真机首页图 / 设计图里「中央米白卡片」与「斜网格纸」的相对位置
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ROOT = path.resolve('D:/新建文件夹/miHoYo Launcher');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const P2 = 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-13T23-37-34-904Z-34c934f6.png';
const P3 = 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-13T23-37-34-906Z-4314ceaf.jpg';
const OUT = path.join(ROOT, 'qianxing-murdoku/687_综合整改/_量测网格纸687.json');

function classify(r, g, b) {
  // 米白卡片：高亮、低饱和暖白
  if (r > 238 && g > 228 && b > 198 && (r - b) < 60) return 'CARD';
  // 网格纸：浅黄纸底 + 格线（比卡片暗、偏黄）
  if (r > 205 && g > 180 && b > 120 && (r - b) > 30 && (r - b) < 110) return 'GRID';
  return 'OTHER';
}
async function scan(file, label, xs) {
  const img = await loadImage(file);
  const cv = createCanvas(img.width, img.height);
  const c = cv.getContext('2d'); c.drawImage(img, 0, 0);
  const d = c.getImageData(0, 0, img.width, img.height).data;
  const res = { label, size: [img.width, img.height], columns: {} };
  for (const x of xs) {
    let prev = null, start = 0;
    const segs = [];
    for (let y = 0; y < img.height; y++) {
      const i = (y * img.width + x) * 4;
      const k = classify(d[i], d[i + 1], d[i + 2]);
      if (k !== prev) { if (prev && y - start >= 4) segs.push([prev, start, y - 1]); prev = k; start = y; }
    }
    if (prev) segs.push([prev, start, img.height - 1]);
    res.columns[x] = segs.filter(s => (s[2] - s[1]) >= 6);
  }
  return res;
}
const out = [];
out.push(await scan(P2, '实机 686 首页', [700, 800, 900, 1000]));
out.push(await scan(P3, '设计图', [840, 960, 1080, 1200]));
fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
for (const o of out) {
  console.log('\n=== ' + o.label + ' ' + o.size.join('x') + ' ===');
  for (const [x, segs] of Object.entries(o.columns)) {
    console.log('x=' + x, segs.map(s => s[0] + ':' + s[1] + '-' + s[2]).join(' | '));
  }
}
