// 679 · 两组对照：注释卡（678 离线 / 679 离线 / 设计稿）与棋盘居中（678 / 679，标移动端可见框）
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
  v678: path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口/678_注释卡真缺口.gil'),
  v679: path.join(DIR, '679_棋盘居中与边缘.gil'),
};
const DESIGN = CLIP + 'clipboard-2026-11-12T19-27-07-222Z-a07c7cca.png';
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function layersOf(file, regex) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const cache = new Map();
  const states = r => stateBlocks(r.field.sub, []);
  function abs(r, d = 0) {
    if (!r || d > 12) return [800, 450];
    if (cache.has(r.id)) return cache.get(r.id);
    const st = states(r)[0], p = st && pairOf(st, 504);
    if (!p) return [800, 450];
    const [px, py] = r.parentId ? abs(byId.get(r.parentId), d + 1) : [800, 450];
    const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
    cache.set(r.id, res); return res;
  }
  return g.recs.filter(r => regex.test(r.name || '') && !isHiddenRecord(r.field)).map(r => {
    const st = states(r)[0], p = st && pairOf(st, 504), sz = st && pairOf(st, 505);
    if (!p || !sz) return null;
    const [px, py] = r.parentId ? abs(byId.get(r.parentId)) : [800, 450];
    const ipp = ns(r.field, [505, 503, 84])[0];
    const c = ipp ? (num(ipp, 502) ?? 0) : 0;
    return { o: order.get(r.field) ?? 1e9, name: r.name,
      cx: px + pairValue(p, 0), cy: py - pairValue(p, 1),
      w: pairValue(sz, 0), h: pairValue(sz, 1),
      rgb: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${((c >>> 24) & 255) / 255})`,
      img: ipp ? (num(ipp, 503) || 100001) : 100001,
      rot: st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);
}
function draw(cx, L, cfg, xoff, yoff) {
  for (const l of L) {
    const x = xoff + l.cx * cfg.s, y = yoff + l.cy * cfg.s;
    cx.save(); cx.translate(x, y); cx.rotate(-l.rot * Math.PI / 180); cx.scale(cfg.s, cfg.s);
    cx.fillStyle = l.rgb; cx.beginPath();
    if (l.img === 100002) cx.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
    else if (l.img === 100003) { cx.moveTo(0, -l.h / 2); cx.lineTo(-l.w / 2, l.h / 2); cx.lineTo(l.w / 2, l.h / 2); cx.closePath(); }
    else cx.rect(-l.w / 2, -l.h / 2, l.w, l.h);
    cx.fill(); cx.restore();
  }
}
// ① 注释卡三栏
{
  const X0 = 290, Y0 = 155, CW = 190, CH = 110, S = 3, GAP = 16;
  const PW = CW * S, PH = CH * S;
  const cv = createCanvas(PW * 3 + GAP * 2, PH + 42), cx = cv.getContext('2d');
  cx.fillStyle = '#fff'; cx.fillRect(0, 0, cv.width, cv.height);
  const RE = /^(art641\.game\.help\.tab|art661\.tab\.|art664\.tab\.|art678\.tab\.)/;
  for (const [i, key] of [[0, 'v678'], [1, 'v679']]) {
    const off = (PW + GAP) * i;
    cx.fillStyle = '#E7B83C'; cx.fillRect(off, 0, PW, PH);
    cx.fillStyle = '#F5EBC7'; cx.fillRect(off, PH * .62, PW, PH * .38);
    cx.save(); cx.translate(off - X0 * S, -Y0 * S);
    draw(cx, layersOf(FILES[key], RE), { s: S }, 0, 0);
    cx.restore();
    // 问号占位
    cx.save(); cx.translate(off + (384 - X0) * S, (211 - Y0) * S); cx.scale(S, S);
    cx.fillStyle = '#FFFDF3'; cx.beginPath(); cx.arc(0, 0, 20, 0, Math.PI * 2); cx.fill();
    cx.fillStyle = '#A63A12'; cx.font = 'bold 30px sans-serif'; cx.textAlign = 'center'; cx.textBaseline = 'middle';
    cx.fillText('?', 0, 1); cx.restore();
  }
  const design = await loadImage(DESIGN);
  cx.drawImage(design, (PW + GAP) * 2, 0, PW, PH);
  cx.fillStyle = '#222'; cx.font = 'bold 20px "Microsoft YaHei",sans-serif';
  ['① 678 离线', '② 679 离线（颜色连贯 + 圆润波浪边）', '③ 设计稿']
    .forEach((s, i) => cx.fillText(s, (PW + GAP) * i + 6, PH + 30));
  fs.writeFileSync(path.join(DIR, '679_对照_注释卡.png'), cv.toBuffer('image/png'));
  console.log('679_对照_注释卡.png', cv.width, cv.height);
}
// ② 棋盘居中两栏（1600×900 → 640×360，红框＝移动端可见区 y∈[90,810]）
{
  const BW = 640, BH = 360, s = BW / 1600, GAP = 20;
  const cv = createCanvas(BW * 2 + GAP, BH + 42), cx = cv.getContext('2d');
  cx.fillStyle = '#fff'; cx.fillRect(0, 0, cv.width, cv.height);
  const RE = /^(board\.|floor\.cell\.|art641\.game\.boardframe\.|art641\.game\.boardbottom$|art656\.home\.grid\.|art663\.grid\.|art656\.home\.paper\.edge$)/;
  for (const [i, key] of [[0, 'v678'], [1, 'v679']]) {
    const off = i * (BW + GAP);
    cx.fillStyle = '#E7B83C'; cx.fillRect(off, 0, BW, BH);
    cx.save(); cx.beginPath(); cx.rect(off, 0, BW, BH); cx.clip();
    draw(cx, layersOf(FILES[key], RE), { s }, off, 0);
    cx.restore();
    cx.strokeStyle = '#e02020'; cx.lineWidth = 2;
    cx.strokeRect(off + 1, 90 * s, BW - 2, 720 * s);
    cx.fillStyle = '#222'; cx.font = 'bold 17px "Microsoft YaHei",sans-serif';
    cx.fillText(i === 0 ? '① 678：棋盘中心 y=420（移动端偏上）' : '② 679：棋盘中心 y=450（移动端居中，x 不变）',
      off + 8, BH + 28);
  }
  fs.writeFileSync(path.join(DIR, '679_对照_棋盘居中.png'), cv.toBuffer('image/png'));
  console.log('679_对照_棋盘居中.png', cv.width, cv.height);
}
