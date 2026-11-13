// 676 · 诊断：列出 675 存档中所有「可见」静态层在左侧笔记本区域（x<520）的几何/颜色/图片类型
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const FILE = process.argv[2] || path.join(ROOT, 'qianxing-murdoku/675_直边票券与火漆精拟合/675_直边票券与火漆精拟合.gil');
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { isHiddenRecord } = await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(FILE);
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const cache = new Map();
function states(r) { return stateBlocks(r.field.sub, []); }
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (cache.has(r.id)) return cache.get(r.id);
  const st = states(r)[0], p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  cache.set(r.id, res); return res;
}
function geom(r) {
  const st = states(r)[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505); if (!p || !s) return null;
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  return [px + pairValue(p, 0), py - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)];
}
const rotOf = r => states(r)[0]?.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0;
const out = [];
for (const r of g.recs) {
  if (!r.name || isHiddenRecord(r.field)) continue;
  const gm = geom(r); if (!gm) continue;
  const [x, y, w, h] = gm;
  if (x + w / 2 < -10 || x - w / 2 > 560 || y + h / 2 < 40 || y - h / 2 > 860) continue;
  const ip = ns(r.field, [505, 503, 84])[0];
  const c = ip ? (num(ip, 502) ?? 0) : 0;
  const hex = '#' + (c >>> 0).toString(16).padStart(8, '0');
  out.push({ o: order.get(r.field) ?? 1e9, name: r.name, x: +x.toFixed(1), y: +y.toFixed(1),
    w: +w.toFixed(1), h: +h.toFixed(1), hex, img: ip ? (num(ip, 503) || 100001) : 100001,
    rot: rotOf(r), parent: r.parentId });
}
out.sort((a, b) => a.o - b.o);
const FILTER = process.argv[3] || '';
const list = FILTER ? out.filter(o => o.name.includes(FILTER)) : out;
for (const o of list) console.log(String(o.o).padStart(5), o.name.padEnd(42),
  `(${String(o.x).padStart(6)},${String(o.y).padStart(6)}) ${String(o.w).padStart(6)}x${String(o.h).padStart(6)}`,
  o.hex, 'img=' + o.img, 'rot=' + o.rot);
console.log('可见静态层（左侧区域）总数', out.length, '筛选后', list.length);
fs.writeFileSync(path.join(DIR, '676_诊断层表.json'), JSON.stringify(out, null, 1));
