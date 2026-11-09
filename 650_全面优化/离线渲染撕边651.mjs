// 离线渲染 gil 中全部 art*.select.tear.* 图层（画布 1600x900），用于不看真机也能复核撕边。
// 用法：node 离线渲染撕边651.mjs [输入.gil] [输出.png] [--dark]
// 渲染顺序取全局记录表；几何、颜色、旋转全部从磁盘记录反解，不依赖构建器内存状态。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);

const input = process.argv[2] || path.join(HERE, '651_撕边修复.gil');
const output = process.argv[3] || path.join(HERE, '651_撕边渲染.png');
const dark = process.argv.includes('--dark');
const g = readGil(input);
const recTop = g.tree.find(q => q.field === 9);
const byField = new Map(g.recs.map(r => [r.field, r]));
const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
if (dark) { cx.fillStyle = '#160C06'; cx.fillRect(0, 0, 1600, 900); }
let n = 0;
for (const f of recTop.sub) {
  const r = byField.get(f);
  if (!r || !/^art\d+\.select\.tear\./.test(r.name || '')) continue;
  const st = stateBlocks(r.field.sub, [])[0];
  if (!st) continue;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  if (!p?.sub || !s?.sub) continue;
  const X = 800 + p.sub[0].f, Y = 450 - p.sub[1].f, W = s.sub[0].f, H = s.sub[1].f;
  const rf = st.sub.find(q => q.field === 508);
  const rot = rf?.sub?.[0]?.f || 0;
  let argb = 0xffffffff;
  for (const p505 of (r.field.sub || []).filter(q => q.field === 505))
    for (const p503 of (p505.sub || []).filter(q => q.field === 503))
      for (const leaf of (p503.sub || []).filter(q => q.field === 84)) {
        const c = leaf.sub?.find(q => q.field === 502 && q.wt === 0);
        if (c) argb = Number(c.num);
      }
  const a = ((argb >>> 24) & 255) / 255, R = (argb >>> 16) & 255, G = (argb >>> 8) & 255, B = argb & 255;
  cx.save(); cx.translate(X, Y); cx.rotate(-rot * Math.PI / 180);
  cx.fillStyle = `rgba(${R},${G},${B},${a})`;
  cx.fillRect(-W / 2, -H / 2, W, H);
  cx.restore(); n++;
}
fs.writeFileSync(output, cv.toBuffer('image/png'));
console.log(JSON.stringify({ input, output, drawn: n, records: g.recs.length, dark }));
