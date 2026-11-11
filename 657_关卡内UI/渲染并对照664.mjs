// 664 离线渲染：设计图 / 663 实机 / 664 静态 UI 三栏对照 + 逐点取色 ΔE
// 口径：设计图 1920×1080 → 1600×900；实机 1604×960 → crop(4,58,1600,900)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const OUT = path.join(DIR, '预览');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const versions = ['657', '658', '659', '660', '661', '663', '664'];
const audits = versions.map(v => JSON.parse(fs.readFileSync(path.join(DIR, `${v}_构建审计.json`), 'utf8')));
const hiddenOf = n => new Set(audits.slice(0, n).flatMap(a => a.hidden || []));
const GAME = /^(art641\.game\.|art657\.game\.|art658\.|art659\.|art660\.|art661\.|art663\.|art664\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|clues\.bg$|board\.bg$)/;
const TPL_IDS = new Set([1073742421, 1073742428]);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const f = p?.sub?.find(q => q.field === k && q.wt === 0); return f ? Number(f.num) : null; };

function load(file, hidden) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map();
  recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
  function geom(r) {
    const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
    const p = pairOf(st, 504), s = pairOf(st, 505); if (!p || !s) return null;
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
    const ip = ns(r.field, [505, 503, 84])[0]; if (!ip) return null;
    const c = num(ip, 502) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    return { rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, a, imageId: num(ip, 503) || 100001 };
  }
  const clipIds = new Set(g.recs.filter(r => r.name && /\.clip$/.test(r.name) && !isHiddenRecord(r.field)).map(r => r.id));
  const statics = g.recs.filter(r => r.name && GAME.test(r.name)
    && !isHiddenRecord(r.field) && !hidden.has(r.name) && !TPL_IDS.has(r.parentId) && !clipIds.has(r.parentId)
    && !/^hex\.|^hit\./.test(r.name)
    && style(r) && geom(r) && geom(r).w > 1.5 && geom(r).h > 1.5 && style(r).a > 0.01)
    .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9))
    .map(r => ({ r, s: style(r) }));
  function drawShape(cx, layer) {
    const gm = geom(layer.r); let [X, Y] = absCenter(layer.r);
    const sh = /^(art656\.home\.grid\.|art656\.home\.paper\.edge$|art663\.grid\.h)/.test(layer.r.name);
    if (sh) { X += 105; Y -= 46; }
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
  function render(gray = true) {
    const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
    if (gray) { cx.fillStyle = '#7A7A7A'; cx.fillRect(0, 0, 1600, 900); }
    for (const layer of statics) drawShape(cx, layer);
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

const B = load(path.join(DIR, '664_关卡内UI.gil'), hiddenOf(7));
const A = load(path.join(DIR, '663_关卡内UI.gil'), hiddenOf(6));
const ui664 = B.render(true), ui663 = A.render(true);
fs.writeFileSync(path.join(OUT, '664_静态UI.png'), ui664.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '664_静态UI_663基线.png'), ui663.toBuffer('image/png'));

const designSrc = await loadImage(path.join(DIR, '_设计图_664.jpg'));
const implSrc = await loadImage(path.join(DIR, '_实机截图_664.png'));
const norm = (src, sx, sy, sw, sh) => {
  const c = createCanvas(1600, 900), cc = c.getContext('2d');
  cc.imageSmoothingEnabled = true; cc.drawImage(src, sx, sy, sw, sh, 0, 0, 1600, 900); return c;
};
const design = norm(designSrc, 0, 0, 1920, 1080);
const actual = norm(implSrc, 4, 58, 1600, 900);
fs.writeFileSync(path.join(OUT, '664_设计图_1600.png'), design.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '664_实机_1600.png'), actual.toBuffer('image/png'));

function triptych(file, box, scale, labels = ['设计图', '663 实机', '664 静态 UI']) {
  const [x, y, w, h] = box, W = Math.round(w * scale), H = Math.round(h * scale);
  const c = createCanvas(W * 3, H + 36), cc = c.getContext('2d');
  cc.fillStyle = '#1E1E1E'; cc.fillRect(0, 0, c.width, c.height);
  [design, actual, ui664].forEach((src, i) => {
    cc.drawImage(src, x, y, w, h, i * W, 36, W, H);
    cc.fillStyle = '#EDEDED'; cc.font = 'bold 17px "Microsoft YaHei",sans-serif';
    cc.fillText(labels[i], i * W + 10, 24);
    if (i) { cc.strokeStyle = '#444'; cc.lineWidth = 1; cc.beginPath(); cc.moveTo(i * W, 0); cc.lineTo(i * W, c.height); cc.stroke(); }
  });
  fs.writeFileSync(path.join(OUT, file), c.toBuffer('image/png'));
}
triptych('664_三栏总览.png', [0, 0, 1600, 900], 0.72);
triptych('664_局部_①票券.png', [290, 140, 200, 150], 2.6);
triptych('664_局部_②格纹与底板.png', [540, 20, 720, 820], 0.85);
triptych('664_局部_③火漆.png', [1230, 260, 210, 210], 2.2);

// 逐点取色 ΔE：设计图 vs 663 静态层 vs 664 静态层
const get = (img, x, y, k = 1) => {
  const c = createCanvas(img.width, img.height), cx = c.getContext('2d'); cx.drawImage(img, 0, 0);
  const p = cx.getImageData(Math.round(x * k), Math.round(y * k), 1, 1).data;
  return [p[0], p[1], p[2]];
};
const hex = c => '#' + c.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
const lab = c => {
  const f = v => { v /= 255; return v > 0.04045 ? Math.pow((v + 0.055) / 1.055, 2.4) : v / 12.92; };
  const [r, g, b] = c.map(f);
  const X = 0.4124 * r + 0.3576 * g + 0.1805 * b, Y = 0.2126 * r + 0.7152 * g + 0.0722 * b,
        Z = 0.0193 * r + 0.1192 * g + 0.9505 * b;
  const q = t => t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116;
  return [116 * q(Y) - 16, 500 * (q(X / 0.95047) - q(Y)), 200 * (q(Y) - q(Z / 1.08883))];
};
const de = (p, q) => { const a = lab(p), b = lab(q); return +Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]).toFixed(2); };
const POINTS = [
  ['票券·亮阶', 340, 195], ['票券·中阶', 365, 215], ['票券·底色', 425, 200],
  ['白底板·右', 1210, 400], ['白底板·上', 900, 90], ['白底板·下', 900, 760],
  ['火漆·左亮环', 1284, 342], ['火漆·中心', 1320, 340], ['火漆·右亮环', 1370, 342],
];
const rows = POINTS.map(([n, x, y]) => {
  const D = get(designSrc, x * 1.2, y * 1.2), A6 = get(ui663, x, y), B6 = get(ui664, x, y);
  return { element: n, at: [x, y], design: hex(D), v663: hex(A6), v664: hex(B6),
    deltaE663: de(D, A6), deltaE664: de(D, B6), improved: de(D, B6) < de(D, A6) };
});
fs.writeFileSync(path.join(OUT, '664_取色对照.json'), JSON.stringify(rows, null, 2));
console.log(JSON.stringify({
  uiLayers664: B.statics.length, uiLayers663: A.statics.length,
  color: rows, improved: rows.filter(r => r.improved).length, total: rows.length,
}, null, 2));
