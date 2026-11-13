// 680 · 模拟真机 sync_art641() 覆盖父坐标后的两栏对照（679 / 680）
//      ★ 离线直接读 .gil 看不出差别（679 改父、680 改子，两者离线都下移 30）；
//        真机 Lua 把 art657.grid.reuse 父坐标强制设为 (105,46) ⇒ 679 改父失效、680 改子仍生效。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const FILES = {
  v679: path.join(ROOT, 'qianxing-murdoku/679_棋盘居中与边缘/679_棋盘居中与边缘.gil'),
  v680: path.join(DIR, '680_网格纸与家具层序.gil'),
};
// 真机 Lua：gp:SetAnchoredPosition(105, 46) ⇒ 父绝对中心 (800+105, 450-46)
const OVERRIDE = [905, 404];
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function layersOf(file) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const states = r => stateBlocks(r.field.sub, []);
  const cache = new Map();
  function abs(r, d = 0) {
    if (!r || d > 12) return [800, 450];
    if (r.name === 'art657.grid.reuse') return OVERRIDE;   // ★ 模拟真机覆盖
    if (cache.has(r.id)) return cache.get(r.id);
    const st = states(r)[0], p = st && pairOf(st, 504);
    if (!p) return [800, 450];
    const [px, py] = r.parentId ? abs(byId.get(r.parentId), d + 1) : [800, 450];
    const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
    cache.set(r.id, res); return res;
  }
  const RE = /^(board\.|floor\.cell\.|art641\.game\.boardframe\.|art641\.game\.boardbottom$|art656\.home\.grid\.|art663\.grid\.|art656\.home\.paper\.edge$)/;
  return g.recs.filter(r => RE.test(r.name || '') && !isHiddenRecord(r.field)).map(r => {
    const st = states(r)[0], p = st && pairOf(st, 504), sz = st && pairOf(st, 505);
    if (!p || !sz) return null;
    const [px, py] = r.parentId ? abs(byId.get(r.parentId)) : [800, 450];
    const ip = ns(r.field, [505, 503, 84])[0];
    const c = ip ? (num(ip, 502) ?? 0) : 0;
    return { o: order.get(r.field) ?? 1e9, name: r.name,
      cx: px + pairValue(p, 0), cy: py - pairValue(p, 1),
      w: pairValue(sz, 0), h: pairValue(sz, 1),
      rgb: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${((c >>> 24) & 255) / 255})`,
      img: ip ? (num(ip, 503) || 100001) : 100001,
      rot: st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);
}
const BW = 640, BH = 360, s = BW / 1600, GAP = 20;
const cv = createCanvas(BW * 2 + GAP, BH + 44), cx = cv.getContext('2d');
cx.fillStyle = '#fff'; cx.fillRect(0, 0, cv.width, cv.height);
for (const [i, key] of [[0, 'v679'], [1, 'v680']]) {
  const off = i * (BW + GAP);
  cx.fillStyle = '#E7B83C'; cx.fillRect(off, 0, BW, BH);
  cx.save(); cx.beginPath(); cx.rect(off, 0, BW, BH); cx.clip();
  for (const l of layersOf(FILES[key])) {
    const x = off + l.cx * s, y = l.cy * s;
    cx.save(); cx.translate(x, y); cx.rotate(-l.rot * Math.PI / 180); cx.scale(s, s);
    cx.fillStyle = l.rgb; cx.beginPath();
    if (l.img === 100002) cx.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
    else if (l.img === 100003) { cx.moveTo(0, -l.h / 2); cx.lineTo(-l.w / 2, l.h / 2); cx.lineTo(l.w / 2, l.h / 2); cx.closePath(); }
    else cx.rect(-l.w / 2, -l.h / 2, l.w, l.h);
    cx.fill(); cx.restore();
  }
  cx.restore();
  cx.strokeStyle = '#e02020'; cx.lineWidth = 2;
  cx.strokeRect(off + 1, 90 * s, BW - 2, 720 * s);
  cx.fillStyle = '#222'; cx.font = 'bold 16px "Microsoft YaHei",sans-serif';
  cx.fillText(i === 0
    ? '① 679 真机：网格纸没跟随下移（Lua 覆盖父坐标）'
    : '② 680 真机模拟：网格纸与白底板一起下移 30',
    off + 8, BH + 28);
}
const out = path.join(DIR, '680_对照_网格纸跟随.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(out, cv.width, cv.height);
