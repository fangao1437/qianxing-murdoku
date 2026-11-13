// 674 离线模拟四栏：672 基线 / 673（被否） / 674 / 设计稿
// 层全部从 .gil 实读；背景为设计稿配色的简化模拟（与 673 同口径，实机已验证预览可信）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const FILES = {
  v672: path.join(ROOT, 'qianxing-murdoku/672_梯形与异色区/672_梯形与异色区.gil'),
  v673: path.join(ROOT, 'qianxing-murdoku/673_注释按钮与底图/673_注释按钮与底图.gil'),
  v674: path.join(DIR, '674_票券与火漆重做.gil'),
};
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const DESIGN = {
  tab: CLIP + 'clipboard-2026-11-12T00-38-15-262Z-1bd702c9.png',
  wax: CLIP + 'clipboard-2026-11-12T00-38-15-264Z-3270e1f0.png',
};
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };

function layersOf(file, regex) {
  const g = readGil(file);
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  return g.recs.filter(r => regex.test(r.name || '') && !isHiddenRecord(r.field)).map(r => {
    const st = stateBlocks(r.field.sub, [])[0];
    const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
    const ip = ns(r.field, [505, 503, 84])[0];
    const c = ip ? (num(ip, 502) ?? 0) : 0;
    const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
    return {
      name: r.name, o: order.get(r.field) ?? 1e9,
      cx: p ? 800 + pairValue(p, 0) : 800, cy: p ? 450 - pairValue(p, 1) : 450,
      w: s ? pairValue(s, 0) : 0, h: s ? pairValue(s, 1) : 0,
      rgb: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${((c >>> 24) & 255) / 255})`,
      img: ip ? (num(ip, 503) || 100001) : 100001, rot,
    };
  }).sort((a, b) => a.o - b.o);
}
function drawLayers(cx, L, cfg) {
  for (const l of L) {
    const x = cfg.W / 2 + (l.cx - cfg.center[0]) * cfg.scale;
    const y = cfg.H / 2 + (l.cy - cfg.center[1]) * cfg.scale;
    cx.save(); cx.translate(x, y); cx.rotate(-l.rot * Math.PI / 180); cx.scale(cfg.scale, cfg.scale);
    cx.fillStyle = l.rgb; cx.beginPath();
    if (l.img === 100002) cx.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
    else if (l.img === 100003) { cx.moveTo(0, -l.h / 2); cx.lineTo(-l.w / 2, l.h / 2); cx.lineTo(l.w / 2, l.h / 2); cx.closePath(); }
    else cx.rect(-l.w / 2, -l.h / 2, l.w, l.h);
    cx.fill(); cx.restore();
  }
}
function backgroundTab(cx, W, H) {
  cx.fillStyle = '#E7B83C'; cx.fillRect(0, 0, W, H);
  cx.fillStyle = '#DC642A'; cx.beginPath();
  cx.moveTo(0, 0); cx.lineTo(W * 0.30, 0); cx.lineTo(W * 0.22, H * 0.66); cx.lineTo(0, H * 0.58);
  cx.closePath(); cx.fill();
  cx.fillStyle = '#F5EBC7'; cx.fillRect(0, H * 0.66, W, H * 0.34);
  cx.strokeStyle = '#E8DBAB'; cx.lineWidth = 1;
  for (let x = 0; x < W; x += 16) { cx.beginPath(); cx.moveTo(x, H * 0.66); cx.lineTo(x, H); cx.stroke(); }
  for (let y = H * 0.66; y < H; y += 16) { cx.beginPath(); cx.moveTo(0, y); cx.lineTo(W, y); cx.stroke(); }
  cx.fillStyle = '#8A3B25'; cx.fillRect(0, H * 0.76, W, H * 0.12);
  cx.strokeStyle = '#E7B83C'; cx.lineWidth = 3; cx.setLineDash([10, 8]);
  cx.beginPath(); cx.moveTo(0, H * 0.82); cx.lineTo(W, H * 0.82); cx.stroke(); cx.setLineDash([]);
}
function backgroundWax(cx, W, H) {
  cx.fillStyle = '#E7B83C'; cx.fillRect(0, 0, W, H);
  cx.fillStyle = '#FBF8EA'; cx.beginPath();
  cx.moveTo(0, H * 0.68); cx.lineTo(W, H * 0.48); cx.lineTo(W, H * 0.72); cx.lineTo(0, H * 0.92);
  cx.closePath(); cx.fill();
  cx.fillStyle = '#7A3A1C'; cx.beginPath();
  cx.moveTo(0, H * 0.92); cx.lineTo(W, H * 0.72); cx.lineTo(W, H); cx.lineTo(0, H);
  cx.closePath(); cx.fill();
  cx.fillStyle = '#241710'; cx.beginPath();
  cx.moveTo(W, H * 0.10); cx.lineTo(W - 22, H * 0.16); cx.lineTo(W, H * 0.22);
  cx.moveTo(W, H * 0.30); cx.lineTo(W - 22, H * 0.36); cx.lineTo(W, H * 0.42); cx.fill();
}
function overlayTab(cx, W, H) {
  cx.save(); cx.translate(W / 2, H / 2);
  cx.fillStyle = '#FFF9F0'; cx.beginPath(); cx.arc(0, 0, 20, 0, Math.PI * 2); cx.fill();
  cx.fillStyle = '#A63A12'; cx.font = 'bold 30px "Microsoft YaHei",sans-serif';
  cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText('?', 0, 1); cx.restore();
}
const CFG = {
  tab: { W: 260, H: 160, center: [384, 211], scale: 1,
    regex: /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/,
    bg: backgroundTab, overlay: overlayTab },
  wax: { W: 200, H: 160, center: [1326, 342], scale: 1,
    regex: /^(art663\.wax\.|art664\.wax\.)/, bg: backgroundWax, overlay: null },
};
async function designPanel(cfg, file) {
  const im = await loadImage(file);
  const cv = createCanvas(cfg.W, cfg.H), cx = cv.getContext('2d');
  cx.fillStyle = '#E7B83C'; cx.fillRect(0, 0, cfg.W, cfg.H);
  const k = Math.min(cfg.W / im.width, cfg.H / im.height);
  const w = im.width * k, h = im.height * k;
  cx.drawImage(im, (cfg.W - w) / 2, (cfg.H - h) / 2, w, h);
  return cv;
}
for (const [tag, cfg] of Object.entries(CFG)) {
  const L = Object.fromEntries(Object.entries(FILES).map(([v, f]) => [v, layersOf(f, cfg.regex)]));
  const make = (key) => {
    const cv = createCanvas(cfg.W, cfg.H), cx = cv.getContext('2d');
    cfg.bg(cx, cfg.W, cfg.H); drawLayers(cx, L[key], cfg);
    if (cfg.overlay) cfg.overlay(cx, cfg.W, cfg.H);
    return cv;
  };
  const panels = [make('v672'), make('v673'), make('v674'), await designPanel(cfg, DESIGN[tag])];
  const labels = ['672 基线（渐变对）', '673（被否）', '674 整改后', '设计稿'];
  const HEAD = 34;
  const tri = createCanvas(cfg.W * panels.length, cfg.H + HEAD), tc = tri.getContext('2d');
  tc.fillStyle = '#1E1E1E'; tc.fillRect(0, 0, tri.width, tri.height);
  panels.forEach((cv, i) => {
    tc.drawImage(cv, i * cfg.W, HEAD);
    tc.fillStyle = i === 2 ? '#7CFC9A' : '#EDEDED';
    tc.font = 'bold 14px "Microsoft YaHei",sans-serif';
    tc.fillText(labels[i], i * cfg.W + 8, 22);
    if (i) { tc.strokeStyle = '#555'; tc.beginPath(); tc.moveTo(i * cfg.W, 0); tc.lineTo(i * cfg.W, tri.height); tc.stroke(); }
  });
  fs.writeFileSync(path.join(DIR, `674_对照_${tag}.png`), tri.toBuffer('image/png'));
  fs.writeFileSync(path.join(DIR, `674_预览_${tag}.png`), panels[2].toBuffer('image/png'));
  console.log(tag, '可见层 672/673/674 =', L.v672.length, L.v673.length, L.v674.length);
}
