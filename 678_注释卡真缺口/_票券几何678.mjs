// 678 · 精确计算 23 枚 100003 渐变三角的「屏幕三角形顶点」→「票券本地坐标」范围
//    100003 顶点：(0,-h/2), (-w/2,+h/2), (+w/2,+h/2)；渲染用 canvas rotate(-rot°)
//    票券 rot=-13 → 屏幕转回本地：lx=dx*C+dy*S, ly=-dx*S+dy*C (C=cos13,S=sin13)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const GIL = path.join(ROOT, 'qianxing-murdoku/677_活页扣孔与八环/677_活页扣孔与八环.gil');
const g = readGil(GIL);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  if (!p || !s) return null;
  return [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1),
    st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0];
}
const C = Math.cos(13 * Math.PI / 180), S = Math.sin(13 * Math.PI / 180);
const toLocal = (sx, sy) => { const dx = sx - 384, dy = sy - 211; return [dx * C + dy * S, -dx * S + dy * C]; };
const tri = g.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '') && !isHiddenRecord(r.field));
let gMinX = 1e9, gMaxX = -1e9;
const rows = [];
for (const r of tri) {
  const [sx, sy, w, h, rot] = geom(r);
  const th = -rot * Math.PI / 180, ct = Math.cos(th), st = Math.sin(th);
  const verts = [[0, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]].map(([vx, vy]) => {
    const x = vx * ct - vy * st, y = vx * st + vy * ct;
    return toLocal(sx + x, sy + y);
  });
  const xs = verts.map(v => v[0]), ys = verts.map(v => v[1]);
  const lo = Math.min(...xs), hi = Math.max(...xs);
  gMinX = Math.min(gMinX, lo); gMaxX = Math.max(gMaxX, hi);
  rows.push({ name: r.name, lo: +lo.toFixed(1), hi: +hi.toFixed(1),
    ly0: +Math.min(...ys).toFixed(1), ly1: +Math.max(...ys).toFixed(1), verts: verts.map(v => v.map(x => +x.toFixed(1))) });
}
console.log('===== 渐变三角精确本地范围（票券 160×66 → 本地 x∈[-80,80], y∈[-33,33]）=====');
for (const r of rows) console.log(`  ${r.name.padEnd(26)} x∈[${String(r.lo).padStart(7)},${String(r.hi).padStart(6)}]  y∈[${String(r.ly0).padStart(6)},${String(r.ly1).padStart(6)}]`);
console.log('  总 x 范围', gMinX.toFixed(1), gMaxX.toFixed(1));
console.log('  主体原半宽 80；缩进 d 后主体半宽 80-d');
console.log('  渐变三角实际覆盖 x 上界', gMaxX.toFixed(1), '下界', gMinX.toFixed(1));
fs.writeFileSync(path.join(DIR, '678_渐变三角本地范围.json'), JSON.stringify({ rows, gMinX, gMaxX }, null, 1));
