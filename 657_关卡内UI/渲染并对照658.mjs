// 658 离线渲染 + 设计图 / 657改实机对照
// 与 657 渲染器同口径，额外模拟：① 引擎「父级矩形裁剪」；② 网格视窗把 clue 模板实例化 5 行。
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
const AUDIT = JSON.parse(fs.readFileSync(path.join(DIR, '658_构建审计.json'), 'utf8'));
const AUDIT657 = JSON.parse(fs.readFileSync(path.join(DIR, '657_构建审计.json'), 'utf8'));
const g = readGil(path.join(DIR, '658_关卡内UI.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
// 657 隐藏的 36 条旧笔记本层 + 658 本轮隐藏的 7 条，都要跳过（否则旧深黑底板会被误画）
const HIDDEN = new Set([...(AUDIT657.hidden || []), ...(AUDIT.hidden || [])]);
const SKIP = new Set(['hex.ok', 'hex.no', 'hit.ok', 'hit.no']);
const GAME = /^(art641\.game\.|art657\.game\.|art658\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|hex\.|hit\.|hud\.|clues\.bg$|board\.bg$)/;
const TPL_IDS = new Set([1073742421, 1073742428]);
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
  const gm = geom(r); if (!gm) return [800, 450];
  let res;
  if (!r.parentId || depth > 12) res = [gm.cx, gm.cy];
  else { const p = byId.get(r.parentId); if (!p) res = [gm.cx, gm.cy];
    else { const [px, py] = absCenter(p, depth + 1); res = [px + (gm.cx - 800), py + (gm.cy - 450)]; } }
  cache.set(r.id, res); return res;
}
function style(r) {
  const ip = ns(r.field, [505, 503, 84])[0], tp = ns(r.field, [505, 503, 75])[0];
  if (ip) { const c = num(ip, 502) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    return { kind: 'image', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a, imageId: num(ip, 503) || 100001 }; }
  if (tp) { const c = num(tp, 504) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
    return { kind: 'text', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a,
      text: tf?.payload?.toString('utf8') || '', size: num(tp, 512) || 24 }; }
  return null;
}
function drawShape(cx, L, dx = 0, dy = 0) {
  const gm = geom(L.r); let [X, Y] = absCenter(L.r);
  X += dx; Y += dy;
  const s = L.s;
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
function drawIcon(cx, name, w, h) {
  cx.save(); cx.strokeStyle = '#F5ECD2'; cx.fillStyle = '#F5ECD2';
  cx.lineWidth = Math.max(6, w * 0.13); cx.lineCap = 'round'; cx.lineJoin = 'round';
  const R = w * 0.36;
  if (name === 'hex.back') { cx.beginPath(); cx.arc(0, 0, R, -Math.PI * 0.75, Math.PI * 0.7); cx.stroke();
    cx.beginPath(); cx.moveTo(-R * 0.75, -R * 0.55); cx.lineTo(-R * 0.2, -R * 0.95); cx.lineTo(-R * 0.35, -R * 0.02); cx.closePath(); cx.fill(); }
  else if (name === 'hex.submit') { cx.beginPath(); cx.moveTo(0, -h * 0.42); cx.lineTo(w * 0.36, -h * 0.05);
    cx.lineTo(w * 0.15, -h * 0.05); cx.lineTo(w * 0.15, h * 0.42); cx.lineTo(-w * 0.15, h * 0.42);
    cx.lineTo(-w * 0.15, -h * 0.05); cx.lineTo(-w * 0.36, -h * 0.05); cx.closePath(); cx.fill(); }
  else if (name === 'hex.redo' || name === 'hex.undo') { const dir = name === 'hex.redo' ? 1 : -1;
    cx.beginPath(); cx.arc(0, 0, R, -Math.PI * 0.65 * dir, Math.PI * 0.85 * dir, dir < 0); cx.stroke();
    cx.beginPath(); cx.moveTo(dir * R * 0.95, -R * 0.6); cx.lineTo(dir * R * 0.35, -R * 0.9);
    cx.lineTo(dir * R * 0.62, -R * 0.15); cx.closePath(); cx.fill(); }
  else if (name === 'hex.hint') { cx.beginPath(); cx.arc(-w * 0.08, -h * 0.08, R * 0.72, 0, Math.PI * 2); cx.stroke();
    cx.beginPath(); cx.moveTo(w * 0.14, h * 0.14); cx.lineTo(w * 0.42, h * 0.42); cx.stroke(); }
  else cx.fillRect(-w / 4, -h / 4, w / 2, h / 2);
  cx.restore();
}
// 静态层（排除模板定义与 clip 子层，它们单独按裁剪绘制）
const clipIds = new Set(g.recs.filter(r => r.name && /\.clip$/.test(r.name)).map(r => r.id));
const gradNames = /^art658\..*\.g\d+$/;
const statics = g.recs.filter(r => r.name && GAME.test(r.name) && !SKIP.has(r.name) && !HIDDEN.has(r.name)
  && !TPL_IDS.has(r.parentId) && !clipIds.has(r.parentId) && !gradNames.test(r.name)
  && !/^hex\./.test(r.name)
  && style(r) && geom(r) && geom(r).w > 1.5 && geom(r).h > 1.5 && style(r).alpha > 0.01)
  .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9))
  .map(r => ({ r, s: style(r) }));
const ICONS = [];
for (const k of ['back', 'submit', 'redo', 'undo', 'hint']) {
  const r = byId.get(g.recs.find(q => q.name === 'hex.' + k)?.id);
  if (r) { const [x, y] = absCenter(r), gm = geom(r); ICONS.push([r.name, x, y, gm.w, gm.h]); }
}
function render(withText) {
  const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
  for (const L of statics) {
    if (L.s.kind === 'text' && !withText) continue;
    if (/^hit\./.test(L.r.name)) continue;
    // 首页网格纸在关卡内由 sync_art641() 父级坐标移到棋盘背后（离线不跑 Lua）
    let dx = 0, dy = 0;
    if (/^art656\.home\.(grid\.|paper\.edge$)/.test(L.r.name)) { dx = 105; dy = -46; }
    drawShape(cx, L, dx, dy);
  }
  // 父级矩形裁剪：clip 容器内的渐变层
  for (const cid of clipIds) {
    const clip = byId.get(cid), cg = geom(clip);
    if (!cg) continue;
    const [X, Y] = absCenter(clip);
    cx.save(); cx.beginPath(); cx.rect(X - cg.w / 2, Y - cg.h / 2, cg.w, cg.h); cx.clip();
    for (const child of g.recs.filter(r => r.parentId === cid && gradNames.test(r.name || '') && style(r) && geom(r)))
      drawShape(cx, { r: child, s: style(child) });
    cx.restore();
  }
  // 网格视窗：把第一套 clue 模板的渐变层实例化到 5 行，并按卡片矩形裁剪
  const gradLayers = g.recs.filter(r => r.parentId === 1073742421 && /^art658\.clue1\./.test(r.name || '')
    && style(r) && geom(r));
  const rows = [322.5, 415.5, 511, 606.5, 699.5];
  for (const cy of rows) {
    cx.save(); cx.beginPath(); cx.rect(223.5 - 165, cy - 42.7, 330, 85.4); cx.clip();
    for (const r of gradLayers) drawShape(cx, { r, s: style(r) }, 223.5 - 800, cy - 450);
    cx.restore();
  }
  for (const [n, x, y, w, h] of ICONS) { cx.save(); cx.translate(x, y); drawIcon(cx, n, w, h); cx.restore(); }
  // 提示按钮本体：已恢复官方 100113（红圈白 ?），离线用白圆+棕问号近似
  const helpR = g.recs.find(r => r.name === 'clues.help617');
  if (helpR && !HIDDEN.has(helpR.name)) {
    const [hx, hy] = absCenter(helpR), hg = geom(helpR);
    cx.save(); cx.translate(hx, hy);
    cx.fillStyle = '#FDFAF5'; cx.beginPath(); cx.arc(0, 0, hg.w / 2, 0, Math.PI * 2); cx.fill();
    cx.fillStyle = '#A0300C'; cx.font = `bold ${Math.round(hg.h * 0.72)}px sans-serif`;
    cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText('?', 0, 1);
    cx.restore();
  }
  return cv;
}
const uiPure = render(false);
fs.writeFileSync(path.join(OUT, '658_UI_纯视觉.png'), uiPure.toBuffer('image/png'));

// 背景 + 新档
const bg = await loadImage(path.join(ROOT, 'qianxing-murdoku/assets/警局场景-2026-11-09-v12/preview/police-v12-simulated.png'));
const full = createCanvas(1600, 900), fx = full.getContext('2d');
fx.drawImage(bg, 0, 0, 1600, 900); fx.drawImage(uiPure, 0, 0);
// 棋盘内容是运行时实例（gil 无记录），用 657改 实机截图占位，留出深紫内框
const ACT = path.join(OUT, '658_实机_1600.png');
if (fs.existsSync(ACT)) { const ai = await loadImage(ACT); fx.drawImage(ai, 608, 141, 584, 578, 620, 140, 568, 575); }
fs.writeFileSync(path.join(OUT, '658_完整预览.png'), full.toBuffer('image/png'));

// 四栏：设计图 / 657改实机 / 658 新档 / 叠合
const design = await loadImage(path.join(OUT, '658_设计_1600.png'));
const actual = fs.existsSync(ACT) ? await loadImage(ACT) : null;
const compare = createCanvas(1600, 900), ccx = compare.getContext('2d');
ccx.fillStyle = '#111'; ccx.fillRect(0, 0, 1600, 900);
ccx.drawImage(design, 0, 0, 800, 450);
if (actual) ccx.drawImage(actual, 800, 0, 800, 450);
ccx.drawImage(full, 0, 450, 800, 450);
const ov = createCanvas(1600, 900), ocx = ov.getContext('2d');
ocx.drawImage(design, 0, 0); ocx.globalAlpha = 0.5; ocx.drawImage(uiPure, 0, 0); ocx.globalAlpha = 1;
ccx.drawImage(ov, 800, 450, 800, 450);
ccx.fillStyle = '#fff'; ccx.font = 'bold 20px sans-serif';
ccx.fillText('设计图', 12, 26); ccx.fillText('657改 实机', 812, 26);
ccx.fillText('658 新档', 12, 476); ccx.fillText('设计图 / 658 UI 叠合', 812, 476);
fs.writeFileSync(path.join(OUT, '658_四栏对照.png'), compare.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '658_叠合核对.png'), ov.toBuffer('image/png'));

// 分区 MAE（排除棋盘内部、线索文本、图标中心）
const A = (() => { const c = createCanvas(1600, 900), x = c.getContext('2d'); x.drawImage(design, 0, 0); return x.getImageData(0, 0, 1600, 900).data; })();
const B = uiPure.getContext('2d').getImageData(0, 0, 1600, 900).data;
const excl = [[600, 107, 1207, 733], [115, 285, 386, 740]];
const iconCenters = ICONS.map(([, x, y]) => [x, y]).concat([[384, 211]]);
const excluded = (x, y) => excl.some(([x0, y0, x1, y1]) => x >= x0 && x < x1 && y >= y0 && y < y1)
  || iconCenters.some(([cx, cy]) => (x - cx) ** 2 + (y - cy) ** 2 < 38 ** 2);
const regions = {
  '笔记本与装订': [0, 150, 500, 800], '棋盘纸框': [560, 30, 1240, 790],
  '左上返回': [20, 95, 220, 225], '右上三键': [1380, 95, 1600, 390],
  '红色图钉': [1250, 270, 1390, 410], '右下放大镜': [1380, 680, 1590, 790],
  '问号便利贴': [280, 150, 470, 270],
};
const diff = {};
for (const [name, [x0, y0, x1, y1]] of Object.entries(regions)) {
  let n = 0, sum = 0;
  for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
    if (excluded(x, y)) continue;
    const i = (y * 1600 + x) * 4;
    if (B[i + 3] < 200) continue;
    n++; sum += Math.abs(A[i] - B[i]) + Math.abs(A[i + 1] - B[i + 1]) + Math.abs(A[i + 2] - B[i + 2]);
  }
  diff[name] = { coveredPx: n, maeRGB: n ? +(sum / (n * 3)).toFixed(2) : null };
}
fs.writeFileSync(path.join(OUT, '658_差分指标.json'), JSON.stringify({
  note: 'MAE 为 658 UI 不透明像素与设计图同位置 RGB 的平均绝对误差；排除棋盘内部、线索卡文本区与图标中心 38px。父级裁剪与模板实例化为离线模拟。',
  regions: diff, layers: statics.length, clipContainers: clipIds.size,
}, null, 2));
console.log(JSON.stringify({ layers: statics.length, clipContainers: clipIds.size, diff }, null, 2));
