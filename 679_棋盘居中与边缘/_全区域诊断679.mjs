// 679 · 列出 678.gil 中棋盘区域（x∈[330,1280]）的全部可见静态层
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const FILE = path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口/678_注释卡真缺口.gil');
const g = readGil(FILE);
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const cache = new Map();
const states = r => stateBlocks(r.field.sub, []);
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (cache.has(r.id)) return cache.get(r.id);
  const st = states(r)[0], p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  cache.set(r.id, res); return res;
}
const out = [];
for (const r of g.recs) {
  if (!r.name || isHiddenRecord(r.field)) continue;
  const st = states(r)[0]; if (!st) continue;
  const p = pairOf(st, 504), s = pairOf(st, 505); if (!p || !s) continue;
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  const x = px + pairValue(p, 0), y = py - pairValue(p, 1);
  const w = pairValue(s, 0), h = pairValue(s, 1);
  if (x + w / 2 < 320 || x - w / 2 > 1290 || y + h / 2 < -20 || y - h / 2 > 940) continue;
  const ip = ns(r.field, [505, 503, 84])[0];
  const c = ip ? (num(ip, 502) ?? 0) : 0;
  out.push({ o: order.get(r.field) ?? 1e9, name: r.name,
    x: +x.toFixed(1), y: +y.toFixed(1), w: +w.toFixed(1), h: +h.toFixed(1),
    hex: '#' + (c >>> 0).toString(16).padStart(8, '0'),
    img: ip ? (num(ip, 503) || 100001) : 100001,
    rot: st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0, parent: r.parentId });
}
out.sort((a, b) => a.o - b.o);
const FILTER = process.argv[2] || '';
for (const o of out.filter(q => !FILTER || q.name.includes(FILTER)))
  console.log(String(o.o).padStart(5), o.name.padEnd(42),
    `(${String(o.x).padStart(7)},${String(o.y).padStart(7)}) ${String(o.w).padStart(7)}x${String(o.h).padStart(7)}`,
    o.hex, 'img=' + o.img, 'rot=' + o.rot);
console.log('可见层总数', out.length, '筛选后', out.filter(q => !FILTER || q.name.includes(FILTER)).length);
fs.writeFileSync(path.join(DIR, '679_棋盘区域层表.json'), JSON.stringify(out, null, 1));
