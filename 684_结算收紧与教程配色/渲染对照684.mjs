// 684 · 离线简化渲染对照（683 → 684）
//   node 渲染对照684.mjs
//   产物 684_对照_结算弹窗.png / 684_对照_首页教程.png
// ★ 简化纯色模拟，不是实机像素验收（673 结论）。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(REPO, 'tools/gil/gilread.mjs')).href);
const { isHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = path.join(REPO, '683_弹窗细线与四键/683_弹窗细线与四键.gil');
const B = path.join(DIR, '684_结算收紧与教程配色.gil');
const FONT = '"Microsoft YaHei",sans-serif';
const rgba = c => { const n = Number(BigInt.asUintN(32, BigInt(c))); return `rgba(${(n >>> 16) & 255},${(n >>> 8) & 255},${n & 255},${((n >>> 24) & 255) / 255})`; };

function prepare(file) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const rt = g.tree.find(f => f.field === 9);
  const order = new Map(); rt.sub.forEach((f, i) => order.set(f, i));
  const cache = new Map();
  function abs(r, d = 0) {
    if (!r || d > 14) return [800, 450];
    if (cache.has(r.id)) return cache.get(r.id);
    const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504);
    if (!p) return [800, 450];
    const [px, py] = r.parentId ? abs(byId.get(r.parentId), d + 1) : [800, 450];
    const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
    cache.set(r.id, res); return res;
  }
  return { g, order, abs, byId };
}
function collect(f, out, d = 0) {
  if (d > 30) return;
  if (f.field === 84 && f.sub) {
    const c = f.sub.find(x => x.field === 502 && x.wt === 0), im = f.sub.find(x => x.field === 503 && x.wt === 0);
    if (c) out.fill = { v: Number(BigInt.asUintN(32, BigInt(c.num))), img: im ? Number(im.num) : 100001 };
  }
  if (f.field === 75 && f.sub) {
    const o = {};
    for (const s of f.sub) {
      if (s.wt === 0) o[s.field] = Number(s.num);
      else if (s.wt === 2 && s.sub) { const t = s.sub.find(q => q.field === 501 && q.wt === 2); if (t) o.text = t.payload.toString('utf8'); }
    }
    if (o[504] != null) out.text = o;
  }
  if (f.sub) for (const s of f.sub) collect(s, out, d + 1);
}
function roundRect(c, l) {
  const rx = Math.min(l.w, l.h) * 0.0625, x = -l.w / 2, y = -l.h / 2;
  c.moveTo(x + rx, y); c.lineTo(x + l.w - rx, y); c.quadraticCurveTo(x + l.w, y, x + l.w, y + rx);
  c.lineTo(x + l.w, y + l.h - rx); c.quadraticCurveTo(x + l.w, y + l.h, x + l.w - rx, y + l.h);
  c.lineTo(x + rx, y + l.h); c.quadraticCurveTo(x, y + l.h, x, y + l.h - rx);
  c.lineTo(x, y + rx); c.quadraticCurveTo(x, y, x + rx, y); c.closePath();
}
function glassStroke(c, l, color) {   // 683 的 100120 官方小图标示意
  c.strokeStyle = color; c.lineCap = 'round';
  c.lineWidth = Math.max(4, l.w * 0.15);
  c.beginPath(); c.arc(-l.w * 0.13, l.h * 0.13, l.w * 0.29, 0, Math.PI * 2); c.stroke();
  c.lineWidth = Math.max(6, l.w * 0.19);
  c.beginPath(); c.moveTo(l.w * 0.08, -l.h * 0.09); c.lineTo(l.w * 0.42, -l.h * 0.43); c.stroke();
}
function drawScene(ctx, filter, crop) {
  const { g, order, abs } = ctx;
  const [x0, y0, w, h] = crop;
  const cv = createCanvas(w, h), c = cv.getContext('2d');
  c.fillStyle = '#8F4B28'; c.fillRect(0, 0, w, h);
  const layers = g.recs.filter(r => filter(r) && !isHiddenRecord(r.field)).map(r => {
    const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
    const p = pairOf(st, 504), s = pairOf(st, 505); if (!p || !s) return null;
    const o = {}; collect(r.field, o);
    const [cx, cy] = abs(r);
    return { o: order.get(r.field) ?? 1e9, cx, cy, w: pairValue(s, 0), h: pairValue(s, 1),
      fill: o.fill || null, text: o.text || null,
      rot: st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);
  for (const l of layers) {
    c.save(); c.translate(l.cx - x0, l.cy - y0); c.rotate(-l.rot * Math.PI / 180);
    if (l.fill) {
      const { v, img } = l.fill, color = rgba(v);
      if (img === 100120) glassStroke(c, l, color);
      else {
        c.fillStyle = color; c.beginPath();
        if (img === 100002) c.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
        else if (img === 100003) { c.moveTo(0, -l.h / 2); c.lineTo(-l.w / 2, l.h / 2); c.lineTo(l.w / 2, l.h / 2); c.closePath(); }
        else if (img === 107102) roundRect(c, l);
        else c.rect(-l.w / 2, -l.h / 2, l.w, l.h);
        c.fill();
      }
    }
    c.restore();
    if (l.text && l.text.text) {
      c.save(); c.translate(l.cx - x0, l.cy - y0);
      c.fillStyle = rgba(l.text[504]); c.textAlign = 'center'; c.textBaseline = 'middle';
      c.font = `bold ${l.text[512] || 16}px ${FONT}`;
      c.fillText(l.text.text, 0, 0, l.w); c.restore();
    }
  }
  return cv;
}
const before = prepare(A), after = prepare(B);
const label = (c, t, x, y, size = 15, color = '#2A1A10') => {
  c.fillStyle = color; c.font = `bold ${size}px ${FONT}`; c.textAlign = 'left'; c.textBaseline = 'top'; c.fillText(t, x, y);
};
const EXIT_KEYS = ['modal.exit', 'modal.save', 'modal.settle', 'modal.cancel'];
const RESULT_KEYS = ['result.next', 'result.exit', 'result.home', 'result.settle'];
function chain(ctx, r) {
  const a = []; let cur = r, guard = 0;
  while (cur && guard++ < 12) { a.push(cur.name || ''); cur = ctx.byId.get(cur.parentId); }
  return a;
}
function popupFilter(ctx, rootName, mode) {
  return r => {
    const ch = chain(ctx, r), n = ch[0] || '';
    if (!n || !ch.includes(rootName)) return false;
    if (rootName !== 'modal') return true;
    if (ch.includes('frame')) return true;
    if (n === 'art' && ch[1] === 'modal') return true;
    if (/^art68[234]\.modal\.frame\./.test(n)) return true;
    if (mode === 'exit') {
      if (n === 'bg' && ch.includes('modal')) return true;
      if (/^modal\.(title|body|stats|settle\.countdown)$/.test(n)) return true;
      if (EXIT_KEYS.some(k => ch.includes(k))) return true;
      return /^modal\.(exit|save|settle|cancel)$/.test(n);
    }
    if (n === 'win' || n === 'result.bg' || /^result\.(title\.1|msg\.1|settle\.countdown)$/.test(n)) return true;
    if (RESULT_KEYS.some(k => ch.includes(k))) return true;
    return /^result\.(next|exit|home|settle)$/.test(n);
  };
}
const scenes = [
  { title: '提交后 / 结算弹窗（本次重点）', root: 'modal', mode: 'result', crop: [440, 120, 720, 660] },
  { title: '退出菜单四键（放大镜水印同步改）', root: 'modal', mode: 'exit', crop: [440, 120, 720, 660] },
  { title: '注释说明 help617', root: 'help617', mode: '', crop: [380, 200, 840, 500] },
];
{
  const GAP = 14, HEAD = 40, W1 = 720;
  const W = W1 * 2 + 3 * GAP, H = HEAD + scenes.reduce((a, s) => a + s.crop[3] + 28, 0) + GAP;
  const cv = createCanvas(W, H), c = cv.getContext('2d');
  c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, W, H);
  label(c, '683（按钮压边框 / 5 字被裁 / 100120 小图标）', GAP, 10, 15);
  label(c, '684 整改后', W1 + 2 * GAP, 10, 17);
  let y = HEAD;
  scenes.forEach(s => {
    c.drawImage(drawScene(before, popupFilter(before, s.root, s.mode), s.crop), GAP, y);
    c.drawImage(drawScene(after, popupFilter(after, s.root, s.mode), s.crop), W1 + 2 * GAP, y);
    label(c, s.title, GAP + 2, y + s.crop[3] + 4, 14);
    y += s.crop[3] + 28;
  });
  const out = path.join(DIR, '684_对照_结算弹窗.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, W + 'x' + H);
}
// 首页教程五卡染色
{
  const W = 760, H = 428, GAP = 14, HEAD = 40;
  const cv = createCanvas(W * 2 + 3 * GAP, H + HEAD + 30), c = cv.getContext('2d');
  c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, cv.width, cv.height);
  label(c, '683（第 5 张通栏卡 #D5C39D 浅一档）', GAP, 10, 15);
  label(c, '684（五卡统一 #C9AC6D = 4.png 左大卡）', W + 2 * GAP, 10, 16);
  const f = r => /^td\.home/.test(r.name || '');
  const a = drawScene(before, f, [0, 0, 1600, 900]);
  const b = drawScene(after, f, [0, 0, 1600, 900]);
  c.drawImage(a, GAP, HEAD, W, H); c.drawImage(b, W + 2 * GAP, HEAD, W, H);
  const out = path.join(DIR, '684_对照_首页教程.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, cv.width + 'x' + cv.height);
}
