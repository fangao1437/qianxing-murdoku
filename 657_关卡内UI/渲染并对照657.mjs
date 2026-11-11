// 657 离线渲染 + 设计图 / 实机对照与分区差分
// 用法：node 渲染并对照657.mjs [输入.gil]
// 口径与 656 渲染器一致：从磁盘记录反解几何/颜色/旋转，按全局记录表顺序绘制。
// 棋盘内部内容与线索卡文本属运行时实例，gil 里没有记录 → 差分时按用户口径排除这两块区域。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const OUT = path.join(DIR, '预览');
fs.mkdirSync(OUT, { recursive: true });
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const AUDIT = JSON.parse(fs.readFileSync(path.join(DIR, '657_构建审计.json'), 'utf8'));
const g = readGil(process.argv[2] || path.join(DIR, '657_关卡内UI.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const HIDDEN = new Set(AUDIT.hidden);
const SKIP = new Set(['hex.ok', 'hex.no', 'hit.ok', 'hit.no']);
const GAME = /^(art641\.game\.|art657\.game\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|hex\.|hit\.|hud\.|clues\.bg$|board\.bg$)/;
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const f = p?.sub?.find(q => q.field === k && q.wt === 0); return f ? Number(f.num) : null; };

function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  if (!p || !s) return null;
  const rot = st.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return { cx: 800 + pairValue(p, 0), cy: 450 - pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1), rot };
}
const cache = new Map();
function absCenter(r, depth = 0) {
  if (cache.has(r.id)) return cache.get(r.id);
  const gm = geom(r);
  if (!gm) return [800, 450];
  let res;
  if (!r.parentId || depth > 12) res = [gm.cx, gm.cy];
  else {
    const p = byId.get(r.parentId);
    if (!p) res = [gm.cx, gm.cy];
    else { const [px, py] = absCenter(p, depth + 1); res = [px + (gm.cx - 800), py + (gm.cy - 450)]; }
  }
  cache.set(r.id, res); return res;
}
function style(r) {
  const ip = ns(r.field, [505, 503, 84])[0], tp = ns(r.field, [505, 503, 75])[0];
  if (ip) {
    const c = num(ip, 502) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    return { kind: 'image', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a, imageId: num(ip, 503) || 100001 };
  }
  if (tp) {
    const c = num(tp, 504) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
    return { kind: 'text', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a,
      text: tf?.payload?.toString('utf8') || '', size: num(tp, 512) || 24 };
  }
  return null;
}
const layers = g.recs.filter(r => r.name && GAME.test(r.name) && !SKIP.has(r.name) && !HIDDEN.has(r.name)
  && !/^hex\./.test(r.name)   // 官方素材图标在 gil 里只有 imageId，统一在 render() 末尾按坐标补画
  && style(r) && geom(r) && geom(r).w > 1.5 && geom(r).h > 1.5 && style(r).alpha > 0.01)
  .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9))
  .map(r => ({ r, s: style(r) }));

// hex.* 是官方素材图标（gil 里只存 imageId），离线用简化白色符号还原位置
function drawIcon(cx, name, w, h) {
  cx.save();
  cx.strokeStyle = '#F5ECD2'; cx.fillStyle = '#F5ECD2';
  cx.lineWidth = Math.max(6, w * 0.13); cx.lineCap = 'round'; cx.lineJoin = 'round';
  const R = w * 0.36;
  if (name === 'hex.back') {
    cx.beginPath(); cx.arc(0, 0, R, -Math.PI * 0.75, Math.PI * 0.7); cx.stroke();
    cx.beginPath(); cx.moveTo(-R * 0.75, -R * 0.55); cx.lineTo(-R * 0.2, -R * 0.95);
    cx.lineTo(-R * 0.35, -R * 0.02); cx.closePath(); cx.fill();
  } else if (name === 'hex.submit') {
    cx.beginPath(); cx.moveTo(0, -h * 0.42); cx.lineTo(w * 0.36, -h * 0.05);
    cx.lineTo(w * 0.15, -h * 0.05); cx.lineTo(w * 0.15, h * 0.42); cx.lineTo(-w * 0.15, h * 0.42);
    cx.lineTo(-w * 0.15, -h * 0.05); cx.lineTo(-w * 0.36, -h * 0.05); cx.closePath(); cx.fill();
  } else if (name === 'hex.redo' || name === 'hex.undo') {
    const dir = name === 'hex.redo' ? 1 : -1;
    cx.beginPath(); cx.arc(0, 0, R, -Math.PI * 0.65 * dir, Math.PI * 0.85 * dir, dir < 0); cx.stroke();
    cx.beginPath(); cx.moveTo(dir * R * 0.95, -R * 0.6); cx.lineTo(dir * R * 0.35, -R * 0.9);
    cx.lineTo(dir * R * 0.62, -R * 0.15); cx.closePath(); cx.fill();
  } else if (name === 'hex.hint') {
    cx.beginPath(); cx.arc(-w * 0.08, -h * 0.08, R * 0.72, 0, Math.PI * 2); cx.stroke();
    cx.beginPath(); cx.moveTo(w * 0.14, h * 0.14); cx.lineTo(w * 0.42, h * 0.42); cx.stroke();
  } else cx.fillRect(-w / 4, -h / 4, w / 2, h / 2);
  cx.restore();
}
function draw(cx, L, withText) {
  const gm = geom(L.r);
  let [X, Y] = absCenter(L.r);
  // 首页网格纸由父级 art657.grid.reuse 承载，关卡内由 sync_art641() 把父坐标设为 (105,46)；
  // 离线渲染不跑 Lua，这里按同一位移模拟（存档 y 向上 ⇒ 屏幕 y 减 46）。
  if (/^art656\.home\.(grid\.|paper\.edge$)/.test(L.r.name)) { X += 105; Y -= 46; }
  const s = L.s;
  if (s.kind === 'text' && !withText) return;
  if (/^hex\./.test(L.r.name)) { cx.save(); cx.translate(X, Y); drawIcon(cx, L.r.name, gm.w, gm.h); cx.restore(); return; }
  if (/^hit\./.test(L.r.name)) return;                  // 透明命中区
  cx.save(); cx.translate(X, Y); cx.rotate(-gm.rot * Math.PI / 180);
  cx.fillStyle = s.rgba;
  if (s.kind === 'text') {
    cx.font = `bold ${s.size}px "Microsoft YaHei","SimHei",sans-serif`;
    cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText(s.text, 0, 0);
  } else {
    const w = gm.w, h = gm.h, id = s.imageId;
    cx.beginPath();
    if (id === 100002) cx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
    else if (id === 100003) { cx.moveTo(0, -h / 2); cx.lineTo(-w / 2, h / 2); cx.lineTo(w / 2, h / 2); cx.closePath(); }
    else if (id === 107102) {
      const rad = Math.min(6, h / 2, w / 2);
      cx.moveTo(-w / 2 + rad, -h / 2);
      cx.arcTo(w / 2, -h / 2, w / 2, h / 2, rad); cx.arcTo(w / 2, h / 2, -w / 2, h / 2, rad);
      cx.arcTo(-w / 2, h / 2, -w / 2, -h / 2, rad); cx.arcTo(-w / 2, -h / 2, w / 2, -h / 2, rad);
      cx.closePath();
    } else cx.rect(-w / 2, -h / 2, w, h);
    cx.fill();
  }
  cx.restore();
}
const ICONS = [
  ['hex.back', 70, 157, 64, 64], ['hex.submit', 1486, 151.5, 70, 70],
  ['hex.redo', 1486, 248, 70, 70], ['hex.undo', 1486, 340, 70, 70],
  ['hex.hint', 1486, 731.5, 70, 70],
];
function render(withText) {
  const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
  for (const L of layers) draw(cx, L, withText);
  for (const [n, x, y, w, h] of ICONS) {
    cx.save(); cx.translate(x, y); drawIcon(cx, n, w, h); cx.restore();
  }
  return cv;
}
const uiPure = render(false), uiFull = render(true);
fs.writeFileSync(path.join(OUT, '657_UI_纯视觉.png'), uiPure.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '657_UI_含功能文字.png'), uiFull.toBuffer('image/png'));

// 背景：v12 独立项目预览图
const bgFile = path.join(ROOT, 'qianxing-murdoku/assets/警局场景-2026-11-09-v12/preview/police-v12-simulated.png');
const bg = await loadImage(bgFile);
const full = createCanvas(1600, 900), fx = full.getContext('2d');
fx.drawImage(bg, 0, 0, 1600, 900); fx.drawImage(uiFull, 0, 0);

// 设计图 6236x3508 -> 1600x900
const designSrc = await loadImage(path.join(ROOT, '美术参考/7836B9C55A22F86B556DBDAA5E18EDA2.png'));
const dv = createCanvas(1600, 900), dx = dv.getContext('2d');
dx.drawImage(designSrc, 0, 0, 1600, 900);
fs.writeFileSync(path.join(OUT, '657_设计图_1600x900.png'), dv.toBuffer('image/png'));

// 实机截图 crop(4,58,1600,900)
const ACTUAL = 'C:/Users/18182/.workbuddy/clipboard-images/clipboard-2026-11-10T14-47-41-683Z-be5164b3.png';
let actual = null;
if (fs.existsSync(ACTUAL)) {
  const ai = await loadImage(ACTUAL);
  const av = createCanvas(1600, 900), ax = av.getContext('2d');
  ax.drawImage(ai, 4, 58, 1600, 900, 0, 0, 1600, 900);
  fs.writeFileSync(path.join(OUT, '657_实机_1600x900.png'), av.toBuffer('image/png'));
  actual = av;
}
// 棋盘内部内容是运行时实例（gil 里没有记录），按用户口径不算差距；
// 完整预览里贴入原实机的棋盘内容占位，只用于看图，不写进存档、不参与差分。
// 只贴格子内容区，四周留出 board.bg 的深紫内框（设计图约 20px 边）
if (actual) fx.drawImage(actual, 608, 141, 584, 578, 620, 140, 568, 575);
fs.writeFileSync(path.join(OUT, '657_完整预览.png'), full.toBuffer('image/png'));

// 四栏对照：设计图 / 原实机 / 657 新档 / 叠合
const compare = createCanvas(1600, 900), ccx = compare.getContext('2d');
ccx.fillStyle = '#111'; ccx.fillRect(0, 0, 1600, 900);
ccx.drawImage(dv, 0, 0, 800, 450);
if (actual) ccx.drawImage(actual, 800, 0, 800, 450);
ccx.drawImage(full, 0, 450, 800, 450);
const ov = createCanvas(1600, 900), ocx = ov.getContext('2d');
ocx.drawImage(dv, 0, 0); ocx.globalAlpha = 0.5; ocx.drawImage(uiPure, 0, 0);
ocx.globalAlpha = 1;
ccx.drawImage(ov, 800, 450, 800, 450);
ccx.fillStyle = '#fff'; ccx.font = 'bold 20px sans-serif';
ccx.fillText('设计图', 12, 26); ccx.fillText('原实机', 812, 26);
ccx.fillText('657 新档 + v12 背景', 12, 476); ccx.fillText('设计图 / 657 UI 叠合', 812, 476);
fs.writeFileSync(path.join(OUT, '657_四栏对照.png'), compare.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '657_叠合核对.png'), ov.toBuffer('image/png'));

// 分区 MAE：只在 657 UI 不透明像素上比 RGB；按用户口径排除棋盘内部、线索卡文本区与图标中心
const A = dx.getImageData(0, 0, 1600, 900).data;
const B = uiPure.getContext('2d').getImageData(0, 0, 1600, 900).data;
const excludedRects = [
  [600, 107, 1207, 733],   // 棋盘内部内容
  [115, 285, 386, 740],   // 线索卡文本区
];
const iconCenters = [[70, 157], [1486, 151.5], [1486, 240.5], [1486, 330], [1486, 731.5], [384, 211]];
const excluded = (x, y) => excludedRects.some(([x0, y0, x1, y1]) => x >= x0 && x < x1 && y >= y0 && y < y1)
  || iconCenters.some(([cx, cy]) => (x - cx) ** 2 + (y - cy) ** 2 < 38 ** 2);
const regions = {
  '笔记本与装订': [0, 150, 500, 800],
  '棋盘纸框': [560, 30, 1240, 790],
  '左上返回': [20, 95, 170, 225],
  '右上三键': [1380, 95, 1600, 390],
  '红色图钉': [1250, 270, 1390, 410],
  '右下放大镜': [1380, 680, 1590, 790],
  '问号便利贴': [280, 150, 470, 270],
};
const diff = {};
for (const [name, [x0, y0, x1, y1]] of Object.entries(regions)) {
  let n = 0, sum = 0;
  for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
    if (excluded(x, y)) continue;
    const i = (y * 1600 + x) * 4;
    if (B[i + 3] < 200) continue;
    n++;
    sum += Math.abs(A[i] - B[i]) + Math.abs(A[i + 1] - B[i + 1]) + Math.abs(A[i + 2] - B[i + 2]);
  }
  diff[name] = { coveredPx: n, maeRGB: n ? +(sum / (n * 3)).toFixed(2) : null };
}
fs.writeFileSync(path.join(OUT, '657_差分指标.json'), JSON.stringify({
  note: 'MAE 为 657 UI 不透明像素与设计图同位置 RGB 的平均绝对误差（0-255）。按用户口径排除棋盘内部内容、线索卡文本；图标中心 38px 半径也排除（离线用简化符号绘制，不代表真机素材）。',
  excludedRegions: ['棋盘内部 x600-1207/y107-733', '线索卡文本区 x115-386/y285-740'],
  regions: diff, layers: layers.length,
}, null, 2));
console.log(JSON.stringify({ layers: layers.length, hidden: HIDDEN.size, diff }, null, 2));
