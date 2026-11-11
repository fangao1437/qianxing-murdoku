// 664 精确测量：棋盘上下边界 / 票券阶梯色阶与撕轮廓 / 火漆质感分层
// 设计图优先用 6236×3508 原 PNG（无 JPEG 压缩），比例 6236/1600 = 3.8975
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const BIG = await loadImage(path.join(ROOT, '美术参考/F94C1F62B0B36CC04E573100F70037A5.png'));
const JPG = await loadImage(path.join(DIR, '_设计图_664.jpg'));
const IMPL = await loadImage(path.join(DIR, '_实机截图_664.png'));
const KB = BIG.width / 1600, KJ = JPG.width / 1600;
function pixels(img) {
  const c = createCanvas(img.width, img.height), cx = c.getContext('2d');
  cx.drawImage(img, 0, 0);
  return { w: img.width, d: cx.getImageData(0, 0, img.width, img.height).data };
}
const P = { big: pixels(BIG), jpg: pixels(JPG), impl: pixels(IMPL) };
const px = (S, x, y) => { const i = (Math.round(y) * S.w + Math.round(x)) * 4; return [S.d[i], S.d[i + 1], S.d[i + 2]]; };
const hex = c => '#' + c.map(v => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
// 1600×900 屏幕坐标 → 各图像素
const db = (x, y) => px(P.big, x * KB, y * KB);
const dj = (x, y) => px(P.jpg, x * KJ, y * KJ);
const im = (x, y) => px(P.impl, x + 4, y + 58);
const near = (c, t, tol = 22) => Math.abs(c[0] - t[0]) <= tol && Math.abs(c[1] - t[1]) <= tol && Math.abs(c[2] - t[2]) <= tol;

// ── A. 棋盘纵剖面：x=900 列扫描，找深紫内框 / 近白底板 / 格线 ──────────────
function scanColumn(name, get, targets) {
  const rows = [];
  for (let y = 20; y < 860; y++) {
    const c = get(900, y);
    let tag = '';
    for (const [k, [t, tol]] of Object.entries(targets)) if (near(c, t, tol)) { tag = k; break; }
    rows.push(tag);
  }
  // 压缩成区间
  const seg = []; let cur = rows[0], st = 20;
  for (let i = 1; i < rows.length; i++) if (rows[i] !== cur) {
    if (i + 20 - st >= 3 && cur) seg.push(`${cur}:${st}..${19 + i}`);
    cur = rows[i]; st = 20 + i;
  }
  if (cur) seg.push(`${cur}:${st}..879`);
  console.log(`\n=== A ${name} · x=900 纵剖面（区间 >=3px） ===`);
  console.log(seg.filter(s => /^(purple|white|gridline|paper)/.test(s)).join('\n'));
  // 深紫连续段
  let best = null, cur2 = null;
  for (let y = 20; y < 860; y++) {
    if (rows[y - 20] === 'purple') { if (!cur2) cur2 = { a: y, b: y }; else cur2.b = y; }
    else if (cur2) { if (!best || cur2.b - cur2.a > best.b - best.a) best = cur2; cur2 = null; }
  }
  if (cur2 && (!best || cur2.b - cur2.a > best.b - best.a)) best = cur2;
  console.log('深紫内框最长连续段:', best ? `y=${best.a}..${best.b} (高 ${best.b - best.a})` : '无');
  return best;
}
const T = {
  purple: [[0x38, 0x2D, 0x3B], 26],
  white: [[0xFD, 0xFC, 0xE7], 14],
  nearwhite: [[0xFD, 0xFD, 0xE7], 12],
  cream: [[0xFA, 0xEF, 0xCC], 12],
  gridline: [[0xE4, 0xD2, 0xA8], 20],
  gridline2: [[0xE8, 0xDB, 0xAB], 20],
};
scanColumn('设计图(big)', db, T);
scanColumn('设计图(jpg)', dj, T);
scanColumn('实机 663', im, T);

// 逐行打印上/下边缘带颜色，供人工确认对称量
console.log('\n=== A2 上/下边缘带逐 4px 取色（屏幕 y；设计big / 实机） ===');
for (let y = 30; y <= 130; y += 6) console.log('上 y=' + String(y).padStart(3), hex(db(900, y)), hex(im(900, y)));
for (let y = 700; y <= 810; y += 6) console.log('下 y=' + String(y).padStart(3), hex(db(900, y)), hex(im(900, y)));

// ── B. 票券阶梯色阶：沿长边（rot −13）避开 ? 白圆采样 ──────────────────────
const TC = { cx: 384, cy: 211, rot: -13, w: 140, h: 66 };
const rotPt = (lx, ly) => {
  const a = -TC.rot * Math.PI / 180; // 渲染器 ctx.rotate(-rot) ⇒ +13°
  return [TC.cx + lx * Math.cos(a) - ly * Math.sin(a), TC.cy + lx * Math.sin(a) + ly * Math.cos(a)];
};
console.log('\n=== B 设计图票券沿长边色阶（局部 x，局部 y=-18 / 0 / +18） ===');
for (let lx = -66; lx <= 66; lx += 6) {
  const cols = [-18, 0, 18].map(ly => { const [x, y] = rotPt(lx, ly); return hex(db(x, y)); });
  console.log('lx=' + String(lx).padStart(4), cols.join('  '));
}
// 用 2D 网格聚类票券主色（排除 ? 白圆与描边）
const hist = new Map();
for (let lx = -68; lx <= 68; lx += 1.5) for (let ly = -30; ly <= 30; ly += 1.5) {
  if (Math.abs(lx) < 22 && Math.abs(ly) < 22) continue;
  const [x, y] = rotPt(lx, ly), c = db(x, y);
  const k = ((c[0] >> 3) << 10) | ((c[1] >> 3) << 5) | (c[2] >> 3);
  const e = hist.get(k) || { n: 0, r: 0, g: 0, b: 0 }; e.n++; e.r += c[0]; e.g += c[1]; e.b += c[2]; hist.set(k, e);
}
const tot = [...hist.values()].reduce((s, e) => s + e.n, 0);
console.log('\n票券主色 TOP10:');
[...hist.values()].sort((a, b) => b.n - a.n).slice(0, 10)
  .forEach(e => console.log('  ', hex([e.r / e.n, e.g / e.n, e.b / e.n]), (e.n / tot * 100).toFixed(1) + '%'));

// ── C. 票券撕边轮廓（设计 big）：逐局部 y 找深红像素最左/最右边界 ──────────
function isTicketRed(c) { return c[0] > 90 && c[0] < 220 && c[1] < 110 && c[2] < 80 && c[0] > c[1] * 1.5; }
console.log('\n=== C 设计图票券两端轮廓（局部 y → 左/右边界，局部 x） ===');
for (let ly = -40; ly <= 40; ly += 4) {
  let L = null, R = null;
  for (let lx = -90; lx <= 90; lx += 0.5) {
    const [x, y] = rotPt(lx, ly);
    if (isTicketRed(db(x, y))) { if (L === null) L = lx; R = lx; }
  }
  console.log('ly=' + String(ly).padStart(4), 'L=' + (L === null ? '-' : L.toFixed(1)), 'R=' + (R === null ? '-' : R.toFixed(1)));
}

// ── D. 火漆质感：中心 (1326,342) 水平/垂直剖面 ─────────────────────────────
console.log('\n=== D 设计图火漆水平剖面 y=342（屏幕 x → 色） ===');
for (let x = 1260; x <= 1392; x += 4) console.log('x=' + String(x).padStart(4), hex(db(x, 342)));
console.log('\n=== D2 设计图火漆垂直剖面 x=1326 ===');
for (let y = 280; y <= 404; y += 4) console.log('y=' + String(y).padStart(4), hex(db(1326, y)));
console.log('\n=== D3 实机火漆水平剖面 y=342 ===');
for (let x = 1260; x <= 1392; x += 8) console.log('x=' + String(x).padStart(4), hex(im(x, 342)));
fs.writeFileSync(path.join(DIR, '预览/664_测量说明.json'), JSON.stringify({
  note: '664 测量输出见控制台；设计图优先 6236×3508 原 PNG，实机 1604×960 crop(4,58)',
  ticket: TC, waxCenter: [1326, 342], scale: { big: KB, jpg: KJ },
}, null, 2));
