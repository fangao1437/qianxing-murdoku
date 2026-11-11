// 663 离线渲染 + 设计图 / 实机基线 / 663 模拟 三栏对照 + 分区 MAE
// 口径：设计图 1920×1080 → 1600×900；实机 1604×960 → crop(4,58,1600,900)
// 实现侧 = 实机截图 + 663 静态 UI 层（透明底）覆盖，用于反映本轮改动后的画面。
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
const { isHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const audits = ['657', '658', '659', '660', '661', '663'].map(v =>
  JSON.parse(fs.readFileSync(path.join(DIR, `${v}_构建审计.json`), 'utf8')));
// 基线档只能用 657..661 的隐藏名单；若把 663 本轮隐藏的旧层也套到基线上，
// 基线渲染会凭空少掉旧图钉/旧活页环/静态白线，对照就失真了。
const HIDDEN_BASE = new Set(audits.slice(0, 5).flatMap(a => a.hidden || []));
const HIDDEN_663 = new Set(audits.flatMap(a => a.hidden || []));
const GAME = /^(art641\.game\.|art657\.game\.|art658\.|art659\.|art660\.|art661\.|art663\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|clues\.bg$|board\.bg$)/;
const TPL_IDS = new Set([1073742421, 1073742428]);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const f = p?.sub?.find(q => q.field === k && q.wt === 0); return f ? Number(f.num) : null; };

function load(file) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map();
  recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
  return { g, byId, order };
}
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505); if (!p || !s) return null;
  const rot = st.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return { cx: 800 + pairValue(p, 0), cy: 450 - pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1), rot };
}
function makeRenderer(L, HIDDEN) {
  const { g, byId, order } = L;
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
    const ip = ns(r.field, [505, 503, 84])[0];
    if (!ip) return null;
    const c = num(ip, 502) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    return { rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, a, imageId: num(ip, 503) || 100001 };
  }
  const clipIds = new Set(g.recs.filter(r => r.name && /\.clip$/.test(r.name) && !isHiddenRecord(r.field)).map(r => r.id));
  const statics = g.recs.filter(r => r.name && GAME.test(r.name)
    && !isHiddenRecord(r.field) && !HIDDEN.has(r.name) && !TPL_IDS.has(r.parentId) && !clipIds.has(r.parentId)
    && /^(?!hex\.|hit\.)/.test(r.name)
    && style(r) && geom(r) && geom(r).w > 1.5 && geom(r).h > 1.5 && style(r).a > 0.01)
    .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9))
    .map(r => ({ r, s: style(r) }));
  function drawShape(cx, layer, dx = 0, dy = 0) {
    const gm = geom(layer.r); let [X, Y] = absCenter(layer.r); X += dx; Y += dy;
    cx.save(); cx.translate(X, Y); cx.rotate(-gm.rot * Math.PI / 180);
    cx.fillStyle = layer.s.rgba;
    const w = gm.w, h = gm.h, id = layer.s.imageId;
    cx.beginPath();
    if (id === 100002) cx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
    else if (id === 100003) { cx.moveTo(0, -h / 2); cx.lineTo(-w / 2, h / 2); cx.lineTo(w / 2, h / 2); cx.closePath(); }
    else if (id === 107102) { const rad = Math.min(6, h / 2, w / 2);
      cx.moveTo(-w / 2 + rad, -h / 2); cx.arcTo(w / 2, -h / 2, w / 2, h / 2, rad);
      cx.arcTo(w / 2, h / 2, -w / 2, h / 2, rad); cx.arcTo(-w / 2, h / 2, -w / 2, -h / 2, rad);
      cx.arcTo(-w / 2, -h / 2, w / 2, -h / 2, rad); cx.closePath(); }
    else cx.rect(-w / 2, -h / 2, w, h);
    cx.fill(); cx.restore();
  }
  // 模拟实机时要排除「位于运行时棋盘之下」的底层纸：真机里棋盘格画在它们之上，
  // 若照单全叠会把实机棋盘盖成一块白板。这些层的颜色变化另用像素级映射体现。
  const SKIP_SIM = /^(art641\.game\.boardframe\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|art657\.game\.board\.tape\.|art663\.grid\.h)/;
  function render(transparent = true, skip = null, only = null) {
    const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
    if (!transparent) { cx.fillStyle = '#7A7A7A'; cx.fillRect(0, 0, 1600, 900); }
    for (const layer of statics) {
      if (only && !only.test(layer.r.name)) continue;
      if (skip && skip.test(layer.r.name)) continue;
      const sh = /^(art656\.home\.grid\.|art656\.home\.paper\.edge$|art663\.grid\.h)/.test(layer.r.name);
      drawShape(cx, layer, sh ? 105 : 0, sh ? -46 : 0);
    }
    // 问号本体（官方 100113 素材的离线近似）
    const help = g.recs.find(r => r.name === 'clues.help617');
    if (help) {
      const [hx, hy] = absCenter(help), hg = geom(help);
      cx.save(); cx.translate(hx, hy);
      cx.fillStyle = '#FDFAF5'; cx.beginPath(); cx.arc(0, 0, hg.w / 2, 0, Math.PI * 2); cx.fill();
      cx.fillStyle = '#8B2800'; cx.font = `bold ${Math.round(hg.h * 0.72)}px sans-serif`;
      cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText('?', 0, 1);
      cx.restore();
    }
    return cv;
  }
  return { statics, render };
}

const B = makeRenderer(load(path.join(DIR, '663_关卡内UI.gil')), HIDDEN_663);
const A = makeRenderer(load(path.join(DIR, '662v19.gil')), HIDDEN_BASE);
const ui663 = B.render(true), uiBase = A.render(true);
// 实机截图本身已含 662v19 的全部静态层与运行时内容，因此模拟「改动后」只叠加
// 本轮新增的 art663.* 层；再叠加旧静态层会把棋盘格/卡片文字整片盖掉。
const simLayer663 = B.render(true, null, /^art663\./);
fs.writeFileSync(path.join(OUT, '663_静态UI_663.png'), B.render(false).toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '663_静态UI_基线.png'), A.render(false).toBuffer('image/png'));

// ── 设计图 / 实机归一化 ─────────────────────────────────────────────────────
const designSrc = await loadImage(path.join(DIR, '_设计图_本轮.jpg'));
const implSrc = await loadImage(path.join(DIR, '_实机截图_本轮.png'));
const norm = (src, sx, sy, sw, sh) => {
  const c = createCanvas(1600, 900), cc = c.getContext('2d');
  cc.imageSmoothingEnabled = true;
  cc.drawImage(src, sx, sy, sw, sh, 0, 0, 1600, 900);
  return c;
};
const design = norm(designSrc, 0, 0, 1920, 1080);
const actual = norm(implSrc, 4, 58, 1600, 900);
fs.writeFileSync(path.join(OUT, '663_设计图_1600.png'), design.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '663_实机_1600.png'), actual.toBuffer('image/png'));

// 底层纸的改色用像素级映射（保留棋盘格内容），其余新增/改形层叠加
function recolor(canvas, from, to, tol = 18) {
  const ctx = canvas.getContext('2d');
  const im = ctx.getImageData(0, 0, 1600, 900), d = im.data;
  for (let i = 0; i < d.length; i += 4) {
    if (Math.abs(d[i] - from[0]) <= tol && Math.abs(d[i + 1] - from[1]) <= tol
        && Math.abs(d[i + 2] - from[2]) <= tol) {
      d[i] = to[0]; d[i + 1] = to[1]; d[i + 2] = to[2];
    }
  }
  ctx.putImageData(im, 0, 0);
}
const baseClone = () => { const c = createCanvas(1600, 900); c.getContext('2d').drawImage(actual, 0, 0); return c; };
const sim663 = baseClone(), sc = sim663.getContext('2d');
recolor(sim663, [0xFA, 0xEF, 0xCC], [0xFD, 0xFC, 0xE7]);   // boardframe.paper 白底板
recolor(sim663, [0xE5, 0xD2, 0xAA], [0xFB, 0xF3, 0xD8]);   // boardframe.shadow 淡化
// 擦除本轮隐藏的 4 条静态白线，再画回模板内随卡片滚动的 5 条白线（真机仍保留）
sc.fillStyle = '#68262A';
for (const cy of [368, 463, 559, 654]) sc.fillRect(223.5 - 325 / 2, cy - 7 / 2, 325, 7);
sc.fillStyle = '#FDFAF5';
for (const cy of [282.5, 375.5, 471, 566.5, 659.5]) sc.fillRect(223.5 - 330 / 2, cy - 5 / 2, 330, 5);
sc.drawImage(simLayer663, 0, 0);
fs.writeFileSync(path.join(OUT, '663_模拟实机.png'), sim663.toBuffer('image/png'));
// 基线 = 实机截图原图（同口径，无叠加、无改色）
const simBase = baseClone();
fs.writeFileSync(path.join(OUT, '663_模拟基线.png'), simBase.toBuffer('image/png'));

// ── 分区 MAE ────────────────────────────────────────────────────────────────
const D = design.getContext('2d').getImageData(0, 0, 1600, 900).data;
const S = sim663.getContext('2d').getImageData(0, 0, 1600, 900).data;
const S0 = simBase.getContext('2d').getImageData(0, 0, 1600, 900).data;
const REGIONS = {
  '① 注释票券': [300, 150, 470, 270],
  '② 线索区活页扣': [0, 270, 80, 760],
  '③ 棋盘白色底板·上': [580, 40, 1230, 135],
  '③ 棋盘白色底板·下': [580, 700, 1230, 785],
  '③ 棋盘白色底板·左': [580, 135, 655, 700],
  '④ 拍立得火漆': [1255, 275, 1395, 410],
  '⑤ 线索卡底板': [55, 275, 400, 760],
};
function mae(buf, [x0, y0, x1, y1]) {
  let sum = 0, n = 0;
  for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
    const i = (y * 1600 + x) * 4;
    sum += Math.abs(D[i] - buf[i]) + Math.abs(D[i + 1] - buf[i + 1]) + Math.abs(D[i + 2] - buf[i + 2]);
    n += 3;
  }
  return +(sum / n).toFixed(2);
}
const metrics = Object.entries(REGIONS).map(([name, box]) => ({
  region: name, box, maeBase: mae(S0, box), mae663: mae(S, box),
  delta: +(mae(S, box) - mae(S0, box)).toFixed(2),
}));
fs.writeFileSync(path.join(OUT, '663_差分指标.json'), JSON.stringify(metrics, null, 2));

// ── 五项局部三栏放大对照 ────────────────────────────────────────────────────
const CROPS = [
  ['663_局部_①注释票券', [290, 140, 200, 150], 2.6],
  ['663_局部_②活页扣', [0, 260, 100, 520], 1.9],
  ['663_局部_③白色底板', [560, 30, 690, 780], 0.85],
  ['663_局部_④拍立得火漆', [1230, 260, 210, 210], 2.2],
  ['663_局部_⑤线索卡底板', [20, 250, 430, 540], 1.25],
];
for (const [name, [x, y, w, h], s] of CROPS) {
  const W = Math.round(w * s), H = Math.round(h * s);
  const c = createCanvas(W * 3, H + 34), cc = c.getContext('2d');
  cc.fillStyle = '#1E1E1E'; cc.fillRect(0, 0, c.width, c.height);
  const labels = ['设计图', '实机基线 662v19', '663 调整后'];
  [design, simBase, sim663].forEach((src, i) => {
    cc.drawImage(src, x, y, w, h, i * W, 34, W, H);
    cc.fillStyle = '#E8E8E8'; cc.font = 'bold 17px "Microsoft YaHei",sans-serif';
    cc.fillText(labels[i], i * W + 10, 23);
    if (i) { cc.strokeStyle = '#444'; cc.lineWidth = 1; cc.beginPath(); cc.moveTo(i * W, 0); cc.lineTo(i * W, c.height); cc.stroke(); }
  });
  fs.writeFileSync(path.join(OUT, name + '.png'), c.toBuffer('image/png'));
}
// 全屏三栏
const fullW = 1100, fullH = Math.round(900 * fullW / 1600);
const full = createCanvas(fullW * 3, fullH + 34), fc = full.getContext('2d');
fc.fillStyle = '#1E1E1E'; fc.fillRect(0, 0, full.width, full.height);
['设计图', '实机基线 662v19', '663 调整后'].forEach((lab, i) => {
  fc.drawImage([design, simBase, sim663][i], 0, 0, 1600, 900, i * fullW, 34, fullW, fullH);
  fc.fillStyle = '#E8E8E8'; fc.font = 'bold 19px "Microsoft YaHei",sans-serif'; fc.fillText(lab, i * fullW + 12, 25);
});
fs.writeFileSync(path.join(OUT, '663_三栏总览.png'), full.toBuffer('image/png'));

console.log(JSON.stringify({
  uiLayers663: B.statics.length, uiLayersBase: A.statics.length,
  metrics, improved: metrics.filter(m => m.delta < 0).length,
  total: metrics.length, crops: CROPS.length,
}, null, 2));
