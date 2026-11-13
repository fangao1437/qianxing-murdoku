// 676 · 四栏活页扣对照：实机截图裁切 / 675 离线模拟 / 676 离线模拟 / 设计稿裁切
//   离线栏的每一层都从 .gil 实读（几何/颜色/旋转/层序），非手工绘制
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
  v675: path.join(ROOT, 'qianxing-murdoku/675_直边票券与火漆精拟合/675_直边票券与火漆精拟合.gil'),
  v676: path.join(DIR, '676_活页扣修正.gil'),
};
const LIVE = CLIP + 'clipboard-2026-11-12T18-12-49-745Z-0f4aaaf1.png';   // 1604x960
const DESIGN = CLIP + 'clipboard-2026-11-12T18-12-49-749Z-01c344c8.jpg';  // 1920x1080
const X0 = 0, Y0 = 240, CW = 90, CH = 520, S = 3, GAP = 16;

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function layersOf(file) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
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
  const RE = /^(art658\.clues\.|art657\.game\.notebook\.|art661\.clues\.|art663\.ring\.|art676\.|art641\.game\.notebook\.)/;
  return g.recs.filter(r => RE.test(r.name || '') && !isHiddenRecord(r.field)).map(r => {
    const st = states(r)[0];
    const p = st && pairOf(st, 504), sz = st && pairOf(st, 505);
    if (!p || !sz) return null;
    const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
    const ip = ns(r.field, [505, 503, 84])[0];
    const c = ip ? (num(ip, 502) ?? 0) : 0;
    return { name: r.name, o: order.get(r.field) ?? 1e9,
      cx: px + pairValue(p, 0), cy: py - pairValue(p, 1),
      w: pairValue(sz, 0), h: pairValue(sz, 1),
      rgb: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${((c >>> 24) & 255) / 255})`,
      img: ip ? (num(ip, 503) || 100001) : 100001,
      rot: st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);
}
function drawLayers(cx, L, xoff) {
  for (const l of L) {
    if (l.cx + l.w / 2 < X0 - 20 || l.cx - l.w / 2 > X0 + CW + 20) continue;
    const x = xoff + (l.cx - X0) * S, y = (l.cy - Y0) * S;
    cx.save(); cx.translate(x, y); cx.rotate(-l.rot * Math.PI / 180); cx.scale(S, S);
    cx.fillStyle = l.rgb; cx.beginPath();
    if (l.img === 100002) cx.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
    else if (l.img === 100003) { cx.moveTo(0, -l.h / 2); cx.lineTo(-l.w / 2, l.h / 2); cx.lineTo(l.w / 2, l.h / 2); cx.closePath(); }
    else cx.rect(-l.w / 2, -l.h / 2, l.w, l.h);
    cx.fill(); cx.restore();
  }
}
async function photoPanel(file, sx, sy, sw, sh, xoff, cx) {
  const im = await loadImage(file);
  const tmp = createCanvas(1600, 900), t = tmp.getContext('2d');
  t.drawImage(im, sx, sy, sw, sh, 0, 0, 1600, 900);
  cx.drawImage(tmp, X0, Y0, CW, CH, xoff, 0, CW * S, CH * S);
}
const PW = CW * S, PH = CH * S;
const cv = createCanvas(PW * 4 + GAP * 3, PH + 42), cx = cv.getContext('2d');
cx.fillStyle = '#ffffff'; cx.fillRect(0, 0, cv.width, cv.height);
const labels = ['① 实机 675（截图）', '② 675 离线模拟', '③ 676 离线模拟', '④ 设计稿'];
// ① 实机
await photoPanel(LIVE, 2, 30, 1600, 900, 0, cx);
// ② 675 / ③ 676 离线
cx.fillStyle = '#A6482A'; cx.fillRect(PW + GAP, 0, PW, PH);
drawLayers(cx, layersOf(FILES.v675), PW + GAP);
cx.fillStyle = '#A6482A'; cx.fillRect((PW + GAP) * 2, 0, PW, PH);
drawLayers(cx, layersOf(FILES.v676), (PW + GAP) * 2);
// ④ 设计稿
await photoPanel(DESIGN, 0, 0, 1920, 1080, (PW + GAP) * 3, cx);
cx.fillStyle = '#222'; cx.font = 'bold 22px "Microsoft YaHei",sans-serif';
labels.forEach((s, i) => cx.fillText(s, (PW + GAP) * i + 6, PH + 30));
const out = path.join(DIR, '676_对照_活页扣.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(out, cv.width, cv.height, '层(675/676)=', layersOf(FILES.v675).length, layersOf(FILES.v676).length);
