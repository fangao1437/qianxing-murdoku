// 663 分层渲染：确认棋盘下两张网格纸的层序与位置（只读 662v19.gil）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const OUT = path.join(DIR, '预览');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const audits = ['657', '658', '659', '660', '661'].map(v =>
  JSON.parse(fs.readFileSync(path.join(DIR, `${v}_构建审计.json`), 'utf8')));
const HIDDEN = new Set(audits.flatMap(a => a.hidden || []));
const g = readGil(path.join(DIR, '662v19.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const GAME = /^(art641\.game\.|art657\.game\.|art658\.|art659\.|art660\.|art661\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|hex\.|hit\.|hud\.|clues\.bg$|board\.bg$)/;
const TPL_IDS = new Set([1073742421, 1073742428]);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const f = p?.sub?.find(q => q.field === k && q.wt === 0); return f ? Number(f.num) : null; };
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
  const ip = ns(r.field, [505, 503, 84])[0], tp = ns(r.field, [505, 503, 75])[0];
  if (ip) { const c = num(ip, 502) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    return { kind: 'image', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a, imageId: num(ip, 503) || 100001 }; }
  if (tp) { const c = num(tp, 504) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
    return { kind: 'text', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a,
      text: tf?.payload?.toString('utf8') || '', size: num(tp, 512) || 24 }; }
  return null;
}
function drawShape(cx, L, dx = 0, dy = 0, override = null) {
  const gm = geom(L.r); let [X, Y] = absCenter(L.r); X += dx; Y += dy;
  cx.save(); cx.translate(X, Y); cx.rotate(-gm.rot * Math.PI / 180);
  cx.fillStyle = override || L.s.rgba;
  const w = gm.w, h = gm.h, id = L.s.imageId;
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
const clipIds = new Set(g.recs.filter(r => r.name && /\.clip$/.test(r.name) && !isHiddenRecord(r.field)).map(r => r.id));
const statics = g.recs.filter(r => r.name && GAME.test(r.name)
  && !isHiddenRecord(r.field) && !HIDDEN.has(r.name) && !TPL_IDS.has(r.parentId) && !clipIds.has(r.parentId)
  && !/^hex\./.test(r.name) && !/^hit\./.test(r.name)
  && style(r) && style(r).kind === 'image' && geom(r) && geom(r).w > 1.5 && geom(r).h > 1.5 && style(r).alpha > 0.01)
  .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9))
  .map(r => ({ r, s: style(r) }));

const GROUPS = {
  'A_全部静态UI': () => true,
  'B_656网格纸': L => /^art656\.home\.grid\./.test(L.r.name),
  'C_boardframe纸框': L => /^art641\.game\.boardframe/.test(L.r.name),
  'D_661网格纸': L => /^art661\.clues\.grid/.test(L.r.name),
  'E_棋盘格纹胶带': L => /^art657\.game\.board\.tape/.test(L.r.name),
  'F_线索区': L => { const [x, y] = absCenter(L.r); return x < 570 && y > 100 && y < 850; },
};
for (const [name, pred] of Object.entries(GROUPS)) {
  const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
  cx.fillStyle = '#7A7A7A'; cx.fillRect(0, 0, 1600, 900);
  for (const L of statics) {
    if (!pred(L)) continue;
    const dx = /^art656\.home\.(grid\.|paper\.edge$)/.test(L.r.name) ? 105 : 0;
    const dy = /^art656\.home\.(grid\.|paper\.edge$)/.test(L.r.name) ? -46 : 0;
    drawShape(cx, L, dx, dy);
  }
  fs.writeFileSync(path.join(OUT, name + '.png'), cv.toBuffer('image/png'));
  console.log(name, statics.filter(pred).length, '层');
}
// 两张网格纸用伪彩色标出叠放关系
const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
cx.fillStyle = '#555'; cx.fillRect(0, 0, 1600, 900);
for (const L of statics) {
  let col = null;
  if (/^art656\.home\.grid\./.test(L.r.name)) col = 'rgba(255,80,80,0.55)';
  if (/^art641\.game\.boardframe/.test(L.r.name)) col = 'rgba(80,255,120,0.55)';
  if (/^art661\.clues\.grid/.test(L.r.name)) col = 'rgba(80,140,255,0.55)';
  if (!col) continue;
  const sh = /^art656\.home\.grid\./.test(L.r.name);
  drawShape(cx, L, sh ? 105 : 0, sh ? -46 : 0, col);
}
fs.writeFileSync(path.join(OUT, 'G_网格纸层序伪彩.png'), cv.toBuffer('image/png'));
console.log('G 伪彩图已出（红=656 / 绿=boardframe / 蓝=661）');
