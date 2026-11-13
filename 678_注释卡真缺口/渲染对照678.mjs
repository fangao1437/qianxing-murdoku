// 678 · 四栏注释卡对照：677 实机局部 / 677 离线 / 678 离线 / 设计稿局部
//      离线栏所有层从 .gil 实读（含 100001 矩形与 100003 三角），问号为占位
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
const CLIP = 'C:/Users/18182/.workbuddy/clipboard-images/';
const FILES = {
  v677: path.join(ROOT, 'qianxing-murdoku/677_活页扣孔与八环/677_活页扣孔与八环.gil'),
  v678: path.join(DIR, '678_注释卡真缺口.gil'),
};
const LIVE677 = CLIP + 'clipboard-2026-11-12T19-27-07-223Z-04f0df5d.png';  // 实机局部 214x122
const DESIGN = CLIP + 'clipboard-2026-11-12T19-27-07-222Z-a07c7cca.png';  // 设计局部 290x174
const X0 = 290, Y0 = 155, CW = 190, CH = 110, S = 3, GAP = 16;
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function layersOf(file) {
  const g = readGil(file);
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  return g.recs.filter(r => /tab|help\.tab/.test(r.name || '') && !isHiddenRecord(r.field)).map(r => {
    const st = stateBlocks(r.field.sub, [])[0];
    const p = st && pairOf(st, 504), sz = st && pairOf(st, 505);
    if (!p || !sz) return null;
    const cx = 800 + pairValue(p, 0), cy = 450 - pairValue(p, 1);
    const w = pairValue(sz, 0), h = pairValue(sz, 1);
    if (cx + Math.max(w, h) / 2 < X0 - 20 || cx - Math.max(w, h) / 2 > X0 + CW + 20) return null;
    const ip = ns(r.field, [505, 503, 84])[0];
    const c = ip ? (num(ip, 502) ?? 0) : 0;
    return { name: r.name, o: order.get(r.field) ?? 1e9, cx, cy, w, h,
      rgb: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${((c >>> 24) & 255) / 255})`,
      img: ip ? (num(ip, 503) || 100001) : 100001,
      rot: st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);
}
function drawLayers(cx, L, xoff) {
  for (const l of L) {
    const x = xoff + (l.cx - X0) * S, y = (l.cy - Y0) * S;
    cx.save(); cx.translate(x, y); cx.rotate(-l.rot * Math.PI / 180); cx.scale(S, S);
    cx.fillStyle = l.rgb; cx.beginPath();
    if (l.img === 100002) cx.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
    else if (l.img === 100003) { cx.moveTo(0, -l.h / 2); cx.lineTo(-l.w / 2, l.h / 2); cx.lineTo(l.w / 2, l.h / 2); cx.closePath(); }
    else cx.rect(-l.w / 2, -l.h / 2, l.w, l.h);
    cx.fill(); cx.restore();
  }
  // 问号占位（官方 40×40 白圆 @384,211）
  cx.save(); cx.translate(xoff + (384 - X0) * S, (211 - Y0) * S); cx.scale(S, S);
  cx.fillStyle = '#FFFDF3'; cx.beginPath(); cx.arc(0, 0, 20, 0, Math.PI * 2); cx.fill();
  cx.fillStyle = '#A63A12'; cx.font = 'bold 30px sans-serif'; cx.textAlign = 'center'; cx.textBaseline = 'middle';
  cx.fillText('?', 0, 1); cx.restore();
}
const PW = CW * S, PH = CH * S;
const cv = createCanvas(PW * 4 + GAP * 3, PH + 42), cx = cv.getContext('2d');
cx.fillStyle = '#fff'; cx.fillRect(0, 0, cv.width, cv.height);
// ① 实机 / ④ 设计稿（局部图拉伸到同栏尺寸）
for (const [i, file] of [[0, LIVE677], [3, DESIGN]]) {
  const im = await loadImage(file);
  cx.drawImage(im, (PW + GAP) * i, 0, PW, PH);
}
// ②③ 离线
for (const [i, key] of [[1, 'v677'], [2, 'v678']]) {
  const off = (PW + GAP) * i;
  cx.fillStyle = '#E7B83C'; cx.fillRect(off, 0, PW, PH);
  cx.fillStyle = '#F5EBC7'; cx.fillRect(off, PH * .62, PW, PH * .38);
  drawLayers(cx, layersOf(FILES[key]), off);
}
cx.fillStyle = '#222'; cx.font = 'bold 20px "Microsoft YaHei",sans-serif';
['① 677 实机（平边）', '② 677 离线', '③ 678 离线（几何真缺口）', '④ 设计稿']
  .forEach((s, i) => cx.fillText(s, (PW + GAP) * i + 6, PH + 30));
const out = path.join(DIR, '678_对照_注释卡.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(out, cv.width, cv.height, '层(677/678)=', layersOf(FILES.v677).length, layersOf(FILES.v678).length);
