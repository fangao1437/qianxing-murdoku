// 676 · 把实机全屏与设计全屏的「左侧笔记本/活页扣」区域按同一实机口径裁出并并排
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const LIVE = CLIP + 'clipboard-2026-11-12T18-12-49-745Z-0f4aaaf1.png';   // 1604x960 (截图带窗口)
const DESIGN = CLIP + 'clipboard-2026-11-12T18-12-49-749Z-01c344c8.jpg';  // 1920x1080

// 实机截图：窗口标题栏约 30px，左右各 1px 边框；游戏画面 1600x900
// 设计稿 1920x1080 -> 实机 1600x900：k = 1600/1920
const SRC = {
  live: { im: await loadImage(LIVE), ox: 2, oy: 30, k: 1600 / 1600 },
  design: { im: await loadImage(DESIGN), ox: 0, oy: 0, k: 1600 / 1920 },
};
// 目标：实机口径 x∈[0,460], y∈[180,820]，输出放大 1.6 倍
const X0 = 0, Y0 = 180, W = 460, H = 640, S = 1.6;
const cv = createCanvas(W * S * 2 + 30, H * S), cx = cv.getContext('2d');
cx.fillStyle = '#ffffff'; cx.fillRect(0, 0, cv.width, cv.height);
let i = 0;
for (const [tag, s] of Object.entries(SRC)) {
  cx.save();
  cx.beginPath(); cx.rect(i * (W * S + 30), 0, W * S, H * S); cx.clip();
  cx.translate(i * (W * S + 30), 0); cx.scale(S, S);
  cx.drawImage(s.im, s.ox + X0 / s.k, s.oy + Y0 / s.k, W / s.k, H / s.k, 0, 0, W, H);
  cx.restore(); i++;
}
cx.fillStyle = '#222'; cx.font = 'bold 20px sans-serif';
cx.fillText('实机 675（1600 口径）', 8, 24);
cx.fillText('设计稿（1920→1600 口径）', W * S + 38, 24);
const out = path.join(DIR, '676_左侧对照_实机vs设计.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(out, cv.width, cv.height);

// 单独把活页扣那条窄带放大 4 倍，便于逐像素量形状/颜色
for (const [tag, s] of Object.entries(SRC)) {
  const X = 0, Y = 230, CW = 80, CH = 560, K = 3;
  const c = createCanvas(CW * K, CH * K), q = c.getContext('2d');
  q.imageSmoothingEnabled = false; q.scale(K, K);
  q.drawImage(s.im, s.ox + X / s.k, s.oy + Y / s.k, CW / s.k, CH / s.k, 0, 0, CW, CH);
  const f = path.join(DIR, `676_活页扣窄带_${tag}_x${K}.png`);
  fs.writeFileSync(f, c.toBuffer('image/png')); console.log(f);
}
