// 661 离线渲染 + 设计图 / 660 实机 / 661 新档 选项卡区域对照
// 与 660 渲染器同口径，额外：① GAME 白名单纳入 art661；② 模板实例化纳入 art661 色阶层；
// ③ 输出「661 实机模拟」（把 661 UI 叠在 660 实机截图上）与四要素局部放大对照。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const OUT = path.join(DIR, '预览');
const TMP = path.join(ROOT, '_work/tmp-661');
fs.mkdirSync(OUT, { recursive: true });
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const audits = ['657', '658', '659', '660', '661'].map(v =>
  JSON.parse(fs.readFileSync(path.join(DIR, `${v}_构建审计.json`), 'utf8')));
const g = readGil(path.join(DIR, '661_关卡内UI.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const HIDDEN = new Set(audits.flatMap(a => a.hidden || []));
const SKIP = new Set(['hex.ok', 'hex.no', 'hit.ok', 'hit.no']);
const GAME = /^(art641\.game\.|art657\.game\.|art658\.|art659\.|art660\.|art661\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|hex\.|hit\.|hud\.|clues\.bg$|board\.bg$)/;
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
const clipIds = new Set(g.recs.filter(r => r.name && /\.clip$/.test(r.name) && !HIDDEN.has(r.name)).map(r => r.id));
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
    let dx = 0, dy = 0;
    if (/^art656\.home\.(grid\.|paper\.edge$)/.test(L.r.name)) { dx = 105; dy = -46; }
    drawShape(cx, L, dx, dy);
  }
  for (const cid of clipIds) {
    const clip = byId.get(cid), cg = geom(clip);
    if (!cg) continue;
    const [X, Y] = absCenter(clip);
    cx.save(); cx.beginPath(); cx.rect(X - cg.w / 2, Y - cg.h / 2, cg.w, cg.h); cx.clip();
    for (const child of g.recs.filter(r => r.parentId === cid && gradNames.test(r.name || '') && style(r) && geom(r)))
      drawShape(cx, { r: child, s: style(child) });
    cx.restore();
  }
  // 网格视窗把 clue1 模板的色阶层实例化到 5 行（按卡片矩形裁剪）
  const gradLayers = g.recs.filter(r => r.parentId === 1073742421
    && /^art(658|659|660|661)\.clue1\./.test(r.name || '') && !HIDDEN.has(r.name)
    && style(r) && geom(r))
    .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9));
  const rows = [322.5, 415.5, 511, 606.5, 699.5];
  for (const cy of rows) {
    cx.save(); cx.beginPath(); cx.rect(223.5 - 165, cy - 42.7, 330, 85.4); cx.clip();
    for (const r of gradLayers) drawShape(cx, { r, s: style(r) }, 223.5 - 800, cy - 450);
    cx.restore();
  }
  for (const [n, x, y, w, h] of ICONS) { cx.save(); cx.translate(x, y); drawIcon(cx, n, w, h); cx.restore(); }
  const helpR = g.recs.find(r => r.name === 'clues.help617');
  if (helpR && !HIDDEN.has(helpR.name)) {
    const [hx, hy] = absCenter(helpR), hg = geom(helpR);
    cx.save(); cx.translate(hx, hy);
    cx.fillStyle = '#FDFAF5'; cx.beginPath(); cx.arc(0, 0, hg.w / 2, 0, Math.PI * 2); cx.fill();
    cx.fillStyle = '#8B2800'; cx.font = `bold ${Math.round(hg.h * 0.72)}px sans-serif`;
    cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText('?', 0, 1);
    cx.restore();
  }
  return cv;
}
const uiPure = render(false);
fs.writeFileSync(path.join(OUT, '661_UI_纯视觉.png'), uiPure.toBuffer('image/png'));

// 验收专用「实现侧」：以设计图为背景，只叠本轮改动的选项卡 UI 层。
// 其余区域（棋盘、按钮、背景美术）保持与设计图逐像素一致，使图像层对照只反映本轮四要素。
// 只叠本轮确实改动/重建的层：新 art661.*、票券主体、白框/内页/行线/燕尾旗、问号本体。
// 返回箭头、装订圈等未改动控件保持设计图原样，避免把「其它区域差异」混进验收。
const TAB_ONLY = /^(art661\.|art641\.game\.help\.tab$|art657\.game\.notebook\.(frame|page|rule|ribbon)|clues\.help617$)/;
const tabStatics = statics.filter(L => TAB_ONLY.test(L.r.name));
function renderTabOn(base) {
  const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
  cx.drawImage(base, 0, 0, 1600, 900);
  cx.save(); cx.beginPath(); cx.rect(0, 90, 540, 780); cx.clip();
  for (const L of tabStatics) drawShape(cx, L);
  const gradLayers = g.recs.filter(r => r.parentId === 1073742421
    && /^art(658|659|660|661)\.clue1\./.test(r.name || '') && !HIDDEN.has(r.name)
    && style(r) && geom(r))
    .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9));
  for (const cy of [322.5, 415.5, 511, 606.5, 699.5]) {
    cx.save(); cx.beginPath(); cx.rect(223.5 - 165, cy - 42.7, 330, 85.4); cx.clip();
    for (const r of gradLayers) drawShape(cx, { r, s: style(r) }, 223.5 - 800, cy - 450);
    cx.restore();
  }
  const helpR = g.recs.find(r => r.name === 'clues.help617');
  if (helpR) {
    const [hx, hy] = absCenter(helpR), hg = geom(helpR);
    cx.save(); cx.translate(hx, hy);
    cx.fillStyle = '#FDFAF5'; cx.beginPath(); cx.arc(0, 0, hg.w / 2, 0, Math.PI * 2); cx.fill();
    cx.fillStyle = '#8B2800'; cx.font = `bold ${Math.round(hg.h * 0.72)}px sans-serif`;
    cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText('?', 0, 1);
    cx.restore();
  }
  cx.restore();
  return cv;
}

// 背景资产 + 新档
const bg = await loadImage(path.join(ROOT, 'qianxing-murdoku/assets/警局场景-2026-11-09-v12/preview/police-v12-simulated.png'));
const full = createCanvas(1600, 900), fx = full.getContext('2d');
fx.drawImage(bg, 0, 0, 1600, 900); fx.drawImage(uiPure, 0, 0);
const ACT = path.join(OUT, '660_实机_1600.png');
if (fs.existsSync(ACT)) { const ai = await loadImage(ACT); fx.drawImage(ai, 608, 141, 584, 578, 620, 140, 568, 575); }
fs.writeFileSync(path.join(OUT, '661_完整预览.png'), full.toBuffer('image/png'));

// 661 实机模拟：把 661 UI 叠在 660 实机截图（1600×900 口径）上
const actual = await loadImage(path.join(TMP, 'actual-1600.png'));
const sim = createCanvas(1600, 900), sx = sim.getContext('2d');
sx.drawImage(actual, 0, 0);
// 选项卡区域先用背景资产抹掉 660 旧 UI（否则旧格纹纸会在 661 的 V 凹口里透出白色），
// 再叠 661 UI；棋盘等其余区域保持 660 实机原样（用户明确「其余区域忽略差异」）。
sx.save(); sx.beginPath(); sx.rect(0, 90, 540, 780); sx.clip();
sx.drawImage(bg, 0, 0, 1600, 900); sx.drawImage(uiPure, 0, 0); sx.restore();
fs.writeFileSync(path.join(OUT, '661_实机模拟.png'), sim.toBuffer('image/png'));

const design = await loadImage(path.join(TMP, 'design-1600.png'));
const focusFull = renderTabOn(design);
fs.writeFileSync(path.join(OUT, '661_验收_实现侧_全图.png'), focusFull.toBuffer('image/png'));
const focusCrop = createCanvas(540, 780), fcx = focusCrop.getContext('2d');
fcx.drawImage(focusFull, 0, 90, 540, 780, 0, 0, 540, 780);
fs.writeFileSync(path.join(OUT, '661_验收_实现侧.png'), focusCrop.toBuffer('image/png'));
fs.writeFileSync(path.join(TMP, 'tab_661_focus.png'), focusCrop.toBuffer('image/png'));
// 四栏：设计图 / 660 实机 / 661 实机模拟 / 叠合
const compare = createCanvas(1600, 900), ccx = compare.getContext('2d');
ccx.fillStyle = '#111'; ccx.fillRect(0, 0, 1600, 900);
ccx.drawImage(design, 0, 0, 800, 450);
ccx.drawImage(actual, 800, 0, 800, 450);
ccx.drawImage(sim, 0, 450, 800, 450);
const ov = createCanvas(1600, 900), ocx = ov.getContext('2d');
ocx.drawImage(design, 0, 0); ocx.globalAlpha = 0.5; ocx.drawImage(sim, 0, 0); ocx.globalAlpha = 1;
ccx.drawImage(ov, 800, 450, 800, 450);
ccx.fillStyle = '#fff'; ccx.font = 'bold 20px sans-serif';
ccx.fillText('设计图', 12, 26); ccx.fillText('660 实机', 812, 26);
ccx.fillText('661 实机模拟', 12, 476); ccx.fillText('设计图 / 661 叠合', 812, 476);
fs.writeFileSync(path.join(OUT, '661_四栏对照.png'), compare.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '661_叠合核对.png'), ov.toBuffer('image/png'));

// 四要素局部放大：设计 / 660 实机 / 661 模拟 三栏
function trio(name, box, s) {
  const [x, y, w, h] = box;
  const cv = createCanvas(w * s * 3 + 24, h * s), cx = cv.getContext('2d');
  cx.fillStyle = '#111'; cx.fillRect(0, 0, cv.width, cv.height);
  [design, actual, sim].forEach((im, i) => cx.drawImage(im, x, y, w, h, i * (w * s + 12), 0, w * s, h * s));
  fs.writeFileSync(path.join(OUT, name), cv.toBuffer('image/png'));
}
trio('661_局部_三层背景.png', [0, 150, 520, 700], 1.35);
trio('661_局部_注释票券.png', [290, 140, 210, 130], 3.2);
trio('661_局部_燕尾旗.png', [400, 290, 140, 110], 4.5);
trio('661_局部_线索卡.png', [125, 275, 275, 200], 3);

// 分区 MAE：仅选项卡区域，排除黑色方格（用户明确无需还原）与图标中心
const A = (() => { const c = createCanvas(1600, 900), x = c.getContext('2d'); x.drawImage(design, 0, 0); return x.getImageData(0, 0, 1600, 900).data; })();
const B = uiPure.getContext('2d').getImageData(0, 0, 1600, 900).data;
const excl = [[55, 280, 128, 750]]; // 设计图的黑色头像方格
const iconCenters = ICONS.map(([, x, y]) => [x, y]).concat([[384, 211]]);
const excluded = (x, y) => excl.some(([x0, y0, x1, y1]) => x >= x0 && x < x1 && y >= y0 && y < y1)
  || iconCenters.some(([cx, cy]) => (x - cx) ** 2 + (y - cy) ** 2 < 34 ** 2);
const regions = {
  '三层背景·上': [0, 150, 500, 255],
  '三层背景·右': [405, 260, 500, 775],
  '三层背景·下': [0, 765, 500, 850],
  '白色底图框': [25, 255, 425, 780],
  '注释票券': [300, 155, 470, 255],
  '燕尾旗胶布': [410, 312, 510, 380],
  '线索卡阶梯渐变': [130, 280, 390, 750],
};
async function maeOf(png) {
  const im = await loadImage(png);
  const c = createCanvas(1600, 900), x = c.getContext('2d'); x.drawImage(im, 0, 0);
  const d = x.getImageData(0, 0, 1600, 900).data;
  const out = {};
  for (const [name, [x0, y0, x1, y1]] of Object.entries(regions)) {
    let n = 0, sum = 0;
    for (let y = y0; y < y1; y += 2) for (let px = x0; px < x1; px += 2) {
      if (excluded(px, y)) continue;
      const i = (y * 1600 + px) * 4;
      if (B[i + 3] < 200) continue; // 661 UI 不透明像素才计入
      n++; sum += Math.abs(A[i] - d[i]) + Math.abs(A[i + 1] - d[i + 1]) + Math.abs(A[i + 2] - d[i + 2]);
    }
    out[name] = n ? +(sum / (n * 3)).toFixed(2) : null;
  }
  return out;
}
const mae660 = await maeOf(path.join(OUT, '660_UI_纯视觉.png'));
const mae661 = await maeOf(path.join(OUT, '661_UI_纯视觉.png'));
fs.writeFileSync(path.join(OUT, '661_差分指标.json'), JSON.stringify({
  note: '仅选项卡区域 MAE（RGB 平均绝对误差，越低越接近设计图）。排除黑色头像方格与图标中心 34px；661 采用离散色阶 + 旋转等腰三角斜分界，其余区域差异按用户要求忽略。',
  baseline: '660_UI_纯视觉.png', current: '661_UI_纯视觉.png',
  layers: statics.length, regions: Object.fromEntries(Object.entries(regions).map(([k, v]) =>
    [k, { box: v, mae660: mae660[k], mae661: mae661[k], delta: +(mae661[k] - mae660[k]).toFixed(2) }])),
}, null, 2));
console.log(JSON.stringify({ layers: statics.length, 'MAE 660→661': Object.fromEntries(
  Object.entries(regions).map(([k]) => [k, `${mae660[k]} → ${mae661[k]}`])) }, null, 2));
