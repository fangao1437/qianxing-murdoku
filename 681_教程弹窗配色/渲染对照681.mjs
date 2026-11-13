// 681 · 教程弹窗改色前后离线对照（13 页全量 + 设计稿对照）
//   用法 node 渲染对照681.mjs
//   产物 681_对照_全13页_改色后.png / 681_对照_前后成对.png / 681_对照_设计稿对照.png
// ★ 口径：离线简化渲染（矩形/椭圆/三角 + 文本），不加载真实图片素材与字体度量，
//   只用于颜色前后对照，不作像素级验收（历史 673 已证实一致度会被简化背景污染）。
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

const BASE = path.join(REPO, '680_网格纸与家具层序/680_网格纸与家具层序.gil');
const AFTER = path.join(DIR, '681_教程弹窗配色.gil');
const PAGES = [['home', 1], ...Array.from({ length: 8 }, (_, i) => ['l1', i + 1]),
  ...Array.from({ length: 4 }, (_, i) => ['l2', i + 1])];
const PAGE_LABEL = {
  'home.p1': '首页 · 玩法总览',
  'l1.p1': '第一关 1/8 认识棋盘', 'l1.p2': '第一关 2/8 选人',
  'l1.p3': '第一关 3/8 放人', 'l1.p4': '第一关 4/8 推理一',
  'l1.p5': '第一关 5/8 推理二', 'l1.p6': '第一关 6/8 推理三',
  'l1.p7': '第一关 7/8 收口', 'l1.p8': '第一关 8/8 指认',
  'l2.p1': '第二关 1/4 复习', 'l2.p2': '第二关 2/4 假话',
  'l2.p3': '第二关 3/4 抓谎', 'l2.p4': '第二关 4/4 收口',
};
const FONT = '"Microsoft YaHei",sans-serif';
const rgba = c => {
  const n = Number(BigInt.asUintN(32, BigInt(c)));
  return `rgba(${(n >>> 16) & 255},${(n >>> 8) & 255},${n & 255},${((n >>> 24) & 255) / 255})`;
};

function prepare(file) {
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(f => f.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const cache = new Map();
  function abs(r, d = 0) {
    if (!r || d > 12) return [800, 450];
    if (cache.has(r.id)) return cache.get(r.id);
    const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504);
    if (!p) return [800, 450];
    const [px, py] = r.parentId ? abs(byId.get(r.parentId), d + 1) : [800, 450];
    const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
    cache.set(r.id, res); return res;
  }
  return { g, order, abs };
}
function collect(f, kind, out, d = 0) {
  if (d > 30) return;
  if (kind === 'fill' && f.field === 84 && f.sub) {
    const c = f.sub.find(x => x.field === 502 && x.wt === 0);
    const im = f.sub.find(x => x.field === 503 && x.wt === 0);
    if (c) out.push({ v: Number(BigInt.asUintN(32, BigInt(c.num))), img: im ? Number(im.num) : 100001 });
  }
  if (kind === 'text' && f.field === 75 && f.sub) {
    const o = {};
    for (const s of f.sub) {
      if (s.wt === 0) o[s.field] = Number(s.num);
      else if (s.wt === 2 && s.sub) {
        const t = s.sub.find(q => q.field === 501 && q.wt === 2);
        if (t) o.text = t.payload.toString('utf8');
      }
    }
    if (o[504] != null) out.push(o);
  }
  if (f.sub) for (const s of f.sub) collect(s, kind, out, d + 1);
}
function pageCanvas(ctx, tag, pno, scale) {
  const { g, order, abs } = ctx;
  const rootName = `td.${tag}`, pageName = `td.${tag}.page.${pno}`;
  const sel = g.recs.filter(r => {
    const n = r.name || '';
    if (!n.startsWith('td.') || isHiddenRecord(r.field)) return false;
    if (n === rootName || (n.startsWith(rootName + '.') && !/\.page\./.test(n))) return true;
    return n === pageName || n.startsWith(pageName + '.');
  });
  const layers = sel.map(r => {
    const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
    const p = pairOf(st, 504), sz = pairOf(st, 505); if (!p || !sz) return null;
    const fill = [], text = [];
    collect(r.field, 'fill', fill); collect(r.field, 'text', text);
    const [cx, cy] = abs(r);
    return { o: order.get(r.field) ?? 1e9, cx, cy, w: pairValue(sz, 0), h: pairValue(sz, 1),
      fill: fill[0] || null, text: text[0] || null,
      rot: st.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).filter(Boolean).sort((a, b) => a.o - b.o);

  const cv = createCanvas(Math.round(1600 * scale), Math.round(900 * scale));
  const c = cv.getContext('2d');
  c.fillStyle = '#E7B83C'; c.fillRect(0, 0, cv.width, cv.height);   // 模拟游戏暖色底
  for (const l of layers) {
    c.save(); c.translate(l.cx * scale, l.cy * scale); c.rotate(-l.rot * Math.PI / 180); c.scale(scale, scale);
    if (l.fill) {
      c.fillStyle = rgba(l.fill.v); c.beginPath();
      if (l.fill.img === 100002) c.ellipse(0, 0, l.w / 2, l.h / 2, 0, 0, Math.PI * 2);
      else if (l.fill.img === 100003) { c.moveTo(0, -l.h / 2); c.lineTo(-l.w / 2, l.h / 2); c.lineTo(l.w / 2, l.h / 2); c.closePath(); }
      else c.rect(-l.w / 2, -l.h / 2, l.w, l.h);
      c.fill();
    }
    c.restore();
    if (l.text && l.text.text) {
      c.save(); c.translate(l.cx * scale, l.cy * scale); c.scale(scale, scale);
      c.fillStyle = rgba(l.text[504]); c.textAlign = 'center'; c.textBaseline = 'middle';
      c.font = `${l.text[512] || 16}px ${FONT}`;
      c.fillText(l.text.text, 0, 0, l.w); c.restore();
    }
  }
  return cv;
}
const before = prepare(BASE), after = prepare(AFTER);
const label = (c, txt, x, y, size = 18, color = '#2A1A10') => {
  c.fillStyle = color; c.font = `bold ${size}px ${FONT}`; c.textAlign = 'left'; c.textBaseline = 'top';
  c.fillText(txt, x, y);
};

// ① 全 13 页改色后总览
{
  const W = 400, H = 225, GAP = 12, COLS = 3, ROWS = 5, HEAD = 34;
  const cv = createCanvas(COLS * W + (COLS + 1) * GAP, HEAD + ROWS * (H + 26) + GAP);
  const c = cv.getContext('2d'); c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, cv.width, cv.height);
  label(c, '681 · 13 页教程弹窗改色后总览（离线简化渲染）', GAP, 8, 19);
  PAGES.forEach(([tag, pno], i) => {
    const col = i % COLS, row = Math.floor(i / COLS);
    const x = GAP + col * (W + GAP), y = HEAD + row * (H + 26) + GAP;
    c.drawImage(pageCanvas(after, tag, pno, W / 1600), x, y);
    label(c, PAGE_LABEL[`${tag}.p${pno}`], x + 2, y + H + 4, 14);
  });
  const out = path.join(DIR, '681_对照_全13页_改色后.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, cv.width + 'x' + cv.height);
}

// ② 13 页前后成对
{
  const W = 480, H = 270, GAP = 12, HEAD = 40;
  const cv = createCanvas(2 * W + 3 * GAP, HEAD + PAGES.length * (H + 28) + GAP);
  const c = cv.getContext('2d'); c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, cv.width, cv.height);
  label(c, '680 改色前', GAP, 8, 18); label(c, '681 改色后', W + 2 * GAP, 8, 18);
  PAGES.forEach(([tag, pno], i) => {
    const y = HEAD + i * (H + 28) + GAP;
    c.drawImage(pageCanvas(before, tag, pno, W / 1600), GAP, y);
    c.drawImage(pageCanvas(after, tag, pno, W / 1600), W + 2 * GAP, y);
    label(c, PAGE_LABEL[`${tag}.p${pno}`], GAP + 2, y + H + 4, 14);
  });
  const out = path.join(DIR, '681_对照_前后成对.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, cv.width + 'x' + cv.height);
}

// ③ 设计稿 + 三张代表页
{
  const RW = 420, RH = 236, PW = 630, PH = 354, GAP = 14;
  const W = 2 * PW + 3 * GAP;
  const H = 30 + RH + 24 + 3 * (PH + 26) + GAP;
  const cv = createCanvas(W, H);
  const c = cv.getContext('2d'); c.fillStyle = '#F3F0E6'; c.fillRect(0, 0, cv.width, cv.height);
  label(c, '设计稿通用模板（美术参考 4 / 5 / 12）', GAP, 4, 18);
  const refs = [];
  for (const f of ['4.png', '5.png', '12.png'])
    refs.push(await loadImage(fs.readFileSync(path.join(ROOT, '美术参考', f))));
  for (let i = 0; i < 3; i++) c.drawImage(refs[i], GAP + i * (RW + GAP), 28, RW, RH);
  const picks = [['home', 1], ['l1', 1], ['l2', 3]];
  picks.forEach(([tag, pno], i) => {
    const y = 30 + RH + 24 + i * (PH + 26);
    c.drawImage(pageCanvas(before, tag, pno, PW / 1600), GAP, y);
    c.drawImage(pageCanvas(after, tag, pno, PW / 1600), PW + 2 * GAP, y);
    label(c, `680 改色前 · ${PAGE_LABEL[`${tag}.p${pno}`]}`, GAP + 2, y + PH + 3, 14);
    label(c, `681 改色后 · ${PAGE_LABEL[`${tag}.p${pno}`]}`, PW + 2 * GAP + 2, y + PH + 3, 14);
  });
  const out = path.join(DIR, '681_对照_设计稿对照.png');
  fs.writeFileSync(out, cv.toBuffer('image/png')); console.log(out, cv.width + 'x' + cv.height);
}
