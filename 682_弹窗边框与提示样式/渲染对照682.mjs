// 682 · 离线简化渲染对照（教程页 + 非教程弹窗）
//   node 渲染对照682.mjs
//   产物 682_对照_弹窗.png / 682_对照_教程页.png
// ★ 简化纯色模拟：矩形/圆/圆角矩形/圆环/三角 + 文本，不含真实素材与字体度量，只作形状与配色前后对照。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(REPO, 'tools/gil/gilread.mjs')).href);
const { isHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = path.join(REPO, '681_教程弹窗配色/681_教程弹窗配色.gil');
const B = path.join(DIR, '682_弹窗边框与提示样式.gil');
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
function drawScene(ctx, filter, crop) {
  const { g, order, abs } = ctx;
  const [x0, y0, w, h] = crop;
  const cv = createCanvas(w, h), c = cv.getContext('2d');
  c.fillStyle = '#E7B83C'; c.fillRect(0, 0, w, h);   // 模拟游戏暖色底
  const layers = g.recs.filter(r => filter(r) && !isHiddenRecord(r.field)).map(r => {
    const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
    const p = pairOf(st, 504), s = pairOf(st, 505); if (!p || !s) return null;
    const o = {}; collect(r.field, o);
    const [cx, cy] = abs(r);
    return { o: order.get(r.field) ?? 1e9, cx, cy, w: pairValue(s, 0), h: pairValue(s, 1),
      fill: o.fill || null, text: o.text || null, rot: st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);
  for (const l of layers) {
    c.save(); c.translate(l.cx - x0, l.cy - y0); c.rotate(-l.rot * Math.PI / 180);
    if (l.fill) {
      const { v, img } = l.fill;
      c.fillStyle = rgba(v); c.beginPath();
      if (img === 100002) c.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
      else if (img === 100003) { c.moveTo(0, -l.h / 2); c.lineTo(-l.w / 2, l.h / 2); c.lineTo(l.w / 2, l.h / 2); c.closePath(); }
      else if (img === 107102) { // 96² 圆角板，r≈6 随尺寸等比
        const rx = Math.min(l.w, l.h) * 0.0625, ry = rx;
        const x = -l.w / 2, y = -l.h / 2;
        c.moveTo(x + rx, y); c.lineTo(x + l.w - rx, y); c.quadraticCurveTo(x + l.w, y, x + l.w, y + ry);
        c.lineTo(x + l.w, y + l.h - ry); c.quadraticCurveTo(x + l.w, y + l.h, x + l.w - rx, y + l.h);
        c.lineTo(x + rx, y + l.h); c.quadraticCurveTo(x, y + l.h, x, y + l.h - ry);
        c.lineTo(x, y + ry); c.quadraticCurveTo(x, y, x + rx, y); c.closePath();
      } else c.rect(-l.w / 2, -l.h / 2, l.w, l.h);
      c.fill();
      if (img === 100006) { c.strokeStyle = rgba(v); c.lineWidth = Math.max(2, l.w * 0.12); c.stroke(); }
    }
    c.restore();
    if (l.text && l.text.text) {
      c.save(); c.translate(l.cx - x0, l.cy - y0);
      c.fillStyle = rgba(l.text[504]); c.textAlign = 'center'; c.textBaseline = 'middle';
      c.font = `${l.text[512] || 16}px ${FONT}`;
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
function popupFilter(ctx, rootName, mode) {
  const byId = ctx.byId;
  return r => {
    const n = r.name || '', pn = byId.get(r.parentId)?.name || '';
    if (!n) return false;
    let cur = r, guard = 0;
    while (cur && guard++ < 12) {
      if (cur.name === rootName) {
        if (rootName !== 'modal') return true;
        const isFrame = n === 'frame' || n.startsWith('art682.' + rootName + '.frame');
        if (isFrame) return true;
        if (mode === 'exit') {
          if (n === 'bg' && pn === 'modal') return true;
          if (/^modal\.(title|body|stats)$/.test(n)) return true;
          if (EXIT_KEYS.includes(pn)) return true;              // label / capsule
          return /^modal\.(exit|save|settle|cancel)$/.test(n);
        }
        if (n === 'win' || n === 'result.bg' || /^result\.(title\.1|msg\.1|settle\.countdown)$/.test(n)) return true;
        if (RESULT_KEYS.includes(pn)) return true;              // label / capsule
        return /^result\.(next|exit|home|settle)$/.test(n);
      }
      cur = byId.get(cur.parentId);
    }
    return false;
  };
}
// 弹窗场景
const scenes = [
  { title: '注释说明 help617', root: 'help617', mode: '', crop: [380, 200, 840, 500] },
  { title: '退出菜单四键', root: 'modal', mode: 'exit', crop: [440, 120, 720, 660] },
  { title: '结算四键', root: 'modal', mode: 'result', crop: [440, 120, 720, 660] },
  { title: '提示菜单 hint635.menu', root: 'hint635.menu', mode: '', crop: [1010, 390, 540, 330] },
  { title: '提示结果 hint635.result', root: 'hint635.result', mode: '', crop: [1010, 420, 540, 280] },
];
{
  const GAP = 14, HEAD = 34;
  const widths = scenes.map(s => s.crop[2]);
  const W = Math.max(...widths) * 2 + 3 * GAP;
  const rowsH = scenes.map(s => s.crop[3] + 26);
  const H = HEAD + rowsH.reduce((a, b) => a + b, 0) + GAP;
  const cv = createCanvas(W, H), c = cv.getContext('2d');
  c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, W, H);
  label(c, '681 改色前', GAP, 8, 17); label(c, '682 改色后', Math.max(...widths) + 2 * GAP, 8, 17);
  let y = HEAD + GAP;
  scenes.forEach((s, i) => {
    const a = drawScene(before, popupFilter(before, s.root, s.mode), s.crop);
    const b = drawScene(after, popupFilter(after, s.root, s.mode), s.crop);
    c.drawImage(a, GAP, y); c.drawImage(b, Math.max(...widths) + 2 * GAP, y);
    label(c, s.title, GAP + 2, y + s.crop[3] + 3, 14);
    y += s.crop[3] + 26;
  });
  const out = path.join(DIR, '682_对照_弹窗.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, W + 'x' + H);
}
// 教程页（对比度 / 红绿圈）
{
  const pages = [['home', 1, '首页 · 玩法总览'], ['l1', 8, '第一关 8/8 指认'], ['l2', 4, '第二关 4/4 收口']];
  const W = 480, H = 270, GAP = 12, HEAD = 34;
  const cv = createCanvas(2 * W + 3 * GAP, HEAD + pages.length * (H + 28) + GAP), c = cv.getContext('2d');
  c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, cv.width, cv.height);
  label(c, '681（低对比度圆底 / 圈被改色）', GAP, 8, 15);
  label(c, '682（圆底文字达标 / 红绿圈还原）', W + 2 * GAP, 8, 15);
  pages.forEach(([tag, pno, title], i) => {
    const root = `td.${tag}`, page = `${root}.page.${pno}`;
    const f = r => { const n = r.name || ''; if (!n.startsWith('td.')) return false;
      if (n === root || (n.startsWith(root + '.') && !/\.page\./.test(n))) return true;
      return n === page || n.startsWith(page + '.'); };
    const y = HEAD + i * (H + 28) + GAP;
    const a = drawScene(before, f, [0, 0, 1600, 900]);
    const b = drawScene(after, f, [0, 0, 1600, 900]);
    c.drawImage(a, GAP, y, W, H); c.drawImage(b, W + 2 * GAP, y, W, H);
    label(c, title, GAP + 2, y + H + 4, 14);
  });
  const out = path.join(DIR, '682_对照_教程页.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, cv.width + 'x' + cv.height);
}
