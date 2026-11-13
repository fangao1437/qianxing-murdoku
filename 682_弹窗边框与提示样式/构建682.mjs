// 682 · 基于 681：教程对比度修复 / 红绿圈还原 / 非教程弹窗通用边框 / EVIDENCE 提示卡 / 四键纯色胶囊
//   输入 ../681_教程弹窗配色/681_教程弹窗配色.gil（7431 条）
//   输出 682_弹窗边框与提示样式.gil
//   规格 682_规格.json
//   用法 FORCE=1 node 构建682.mjs   /   node 构建682.mjs --dry
//
// 用户本轮决定（AskUserQuestion 已确认）：
//   ① 边框只给非教程弹窗（help617 + modal），教程 13 页只修对比度与红绿圈；
//   ② 12.png 只取「边框本体」：深棕外框 + 内侧虚线 + 四角金铆钉 + 米白内页，红绶带/放大镜/按键/小叉不复制；
//   ③ 两个四键弹窗的按键删 107179 bg，按 656 首页四键「1 矩形 + 2 圆」纯色胶囊重建。
//
// ★ 关键口径
//   · 新增层挂在名为 frame / card 的容器下（DECOR 名单内），避免被 hide_unlisted 扫掉；
//     所有图元坐标都是相对父容器的 504 对（x 右为正、y 上为正）。
//   · 两个四键弹窗共用一张 633×600 通用框；旧 633×383 `bg` 与 633×600 `result.bg` 改全透明，
//     避免两套框在结算态叠加。
//   · 红绿圈颜色逐条从 680 同名记录还原 = 内嵌 Lua M.RING_GREEN / M.RING_RED，不额外修改。
//   · 内嵌 Lua 本轮零改动。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '682_规格.json'), 'utf8'));
const INPUT = path.join(REPO, SPEC.base.file);
const BASE680 = path.join(REPO, '680_网格纸与家具层序/680_网格纸与家具层序.gil');
const OUTPUT = path.join(DIR, '682_弹窗边框与提示样式.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const BASE_SHA = sha(INPUT);
if (BASE_SHA !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, writeVarint, stateBlocks, pairOf, pairValue, setPair, cloneField,
  ensureChildListTop, findChildListTop, asIdList, setChildList, textsOf, recordsOf } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const g680 = readGil(BASE680);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const recTop = g.tree.find(f => f.field === 9);
const orderOf = () => { const m = new Map(); recTop.sub.forEach((f, i) => m.set(f, i)); return m; };
const scriptBefore = Buffer.from(findScriptLeaf(g).buf);
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));
let maxId = BigInt(g.maxId);
const added = [], deleted = [], modified = new Set(), colorChanges = [], newLayers = [];
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const big = h => BigInt('0x' + h.slice(1));
const argb6 = h => big('#FF' + h.slice(1));

// ── 字段工具（沿用 656 构建器口径） ────────────────────────────────────────
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
const states = r => stateBlocks(r.field.sub, []);
const imgParts = r => ns(r.field, [505, 503, 84]);
const txtParts = r => ns(r.field, [505, 503, 75]);
function colorFields(r) {
  const out = [];
  (function w(f, d = 0) {
    if (d > 30) return;
    if (f.field === 84 && f.sub) {
      const c = f.sub.find(x => x.field === 502 && x.wt === 0);
      if (c) out.push({ kind: 'fill', obj: c });
    }
    if (f.field === 75 && f.sub) {
      const c = f.sub.find(x => x.field === 504 && x.wt === 0);
      if (c) out.push({ kind: 'font', obj: c });
    }
    if (f.sub) for (const s of f.sub) w(s, d + 1);
  })(r.field, 0);
  return out;
}
function setColor(r, hex8) {
  for (const p of imgParts(r)) setNum(p, 502, Number(big(hex8) & 0xFFFFFFFFn));
  modified.add(r.name);
}
function setFont(r, hex8, size) {
  for (const p of txtParts(r)) {
    setNum(p, 504, Number(big(hex8) & 0xFFFFFFFFn));
    if (size) { setNum(p, 512, size); setNum(p, 513, size); }
  }
  modified.add(r.name);
}
function setGeomLocal(r, dx, dyUp, w, h) {
  for (const st of states(r)) {
    const p = pairOf(st, 504), s = pairOf(st, 505);
    if (!p || !s) throw Error('几何字段缺失 ' + r.name);
    setPair(p, dx, dyUp); setPair(s, w, h);
  }
  modified.add(r.name);
}
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function makeLayer(L, parent) {
  const proto = R(L.kind === 'text' ? 'hint635.menu.title' : 'td.home.page.1.help619.icon');
  const f = cloneField(proto.field);
  const id = Number(++maxId);
  remap(f.sub, proto.id, id);
  const nameLeaf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nameLeaf) throw Error('克隆原型缺名字叶子');
  nameLeaf.payload = Buffer.from(L.name); nameLeaf.len = nameLeaf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl0 = findChildListTop(f.sub); if (cl0) setChildList(cl0, []);
  setHiddenRecord(f, false);
  const rec = { id, name: L.name, parentId: parent.id, field: f };
  g.recs.push(rec); byId.set(id, rec); byName.set(L.name, rec);
  added.push(rec);
  setGeomLocal(rec, L.dx || 0, L.dy || 0, L.w, L.h);
  if (L.color) setColor(rec, L.color);
  if (L.imageId) { for (const p of imgParts(rec)) setNum(p, 503, L.imageId); }
  for (const p of imgParts(rec)) setNum(p, 504, 1);   // 使用染色
  newLayers.push({ name: L.name, parent: parent.name, dx: L.dx || 0, dy: L.dy || 0,
    w: L.w, h: L.h, color: L.color || null, imageId: L.imageId || 100001, rule: L.rule || '' });
  return rec;
}
function insertBlock(parent, anchorName, layers) {
  const anchor = R(anchorName);
  const created = layers.map(L => makeLayer(L, parent));
  const i = recTop.sub.indexOf(anchor.field);
  if (i < 0) throw Error('recTop 锚点丢失 ' + anchorName);
  recTop.sub.splice(i, 0, ...created.map(r => r.field));
  return created;
}
function syncChildList(parent) {
  const ord = orderOf();
  const ids = g.recs.filter(r => r.parentId === parent.id)
    .sort((a, b) => (ord.get(a.field) ?? 1e9) - (ord.get(b.field) ?? 1e9)).map(r => r.id);
  setChildList(ensureChildListTop(parent), ids);
  modified.add(parent.name);
}
function syncAllChildLists(parents) { for (const p of parents) syncChildList(p); }

// ═══════════════════════════════════════════════════════════════════════
// A. 教程页：褐色圆底文字对比度 + 红绿圈还原（只改 681 的 td.* 颜色字段）
// ═══════════════════════════════════════════════════════════════════════
const P = SPEC.palette;
const lum = h => {
  const [r, gg, b] = [3, 5, 7].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
    .map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
  return 0.2126 * r + 0.7152 * gg + 0.0722 * b;
};
const CR = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
const firstFill = r => colorFields(r).find(c => c.kind === 'fill')?.obj;
const firstFont = r => colorFields(r).find(c => c.kind === 'font')?.obj;

// A1 圆底/文字配对
const circlePairs = [];
for (const r of g.recs.filter(r => /^td\./.test(r.name || '') && /\.(clueface|lg\.\d+|rule\.\d+\.num)\.bg$/.test(r.name))) {
  const glyphName = r.name.replace(/\.bg$/, '');
  const glyph = byName.get(glyphName);
  const bgObj = firstFill(r), fgObj = glyph && firstFont(glyph);
  if (!bgObj || !fgObj) continue;
  const bgHex = hex(bgObj.num), oldHex = hex(fgObj.num);
  let to;
  if (/\.rule\.\d+\.num$/.test(glyphName)) to = '#FF' + P.gold.slice(1);
  else to = lum(bgHex) < 0.25 ? '#FFFFF5D6' : '#FF4B1B09';
  if (to !== oldHex) {
    fgObj.num = big(to);
    colorChanges.push({ name: glyphName, kind: 'font', from: oldHex, to, rule: 'A1 圆底对比度' });
    modified.add(glyphName);
  }
  circlePairs.push({ name: glyphName, bg: bgHex, from: oldHex, to, crBefore: +CR(bgHex, oldHex).toFixed(2), crAfter: +CR(bgHex, to).toFixed(2) });
}
if (circlePairs.length < 50) throw Error('圆底配对数量异常：' + circlePairs.length);

// A2 红绿圈：逐条还原 680 同名记录颜色
const map680 = new Map(g680.recs.map(r => [r.name, r]));
let ringCount = 0;
for (const r of g.recs.filter(r => /\.ring\.[A-Z]\.\d+$/.test(r.name || ''))) {
  const a = map680.get(r.name); if (!a) throw Error('680 缺圈记录 ' + r.name);
  const obj = firstFill(r), obj680 = firstFill(a);
  if (!obj || !obj680) throw Error('圈颜色字段缺失 ' + r.name);
  const from = hex(obj.num), to = hex(obj680.num);
  if (from !== to) { obj.num = obj680.num; colorChanges.push({ name: r.name, kind: 'fill', from, to, rule: 'A2 还原运行时红绿圈' }); modified.add(r.name); }
  ringCount++;
}
if (ringCount !== 180) throw Error('红绿圈数量异常：' + ringCount);

// ═══════════════════════════════════════════════════════════════════════
// B. 非教程弹窗：文字翻深墨、旧底板全透明
// ═══════════════════════════════════════════════════════════════════════
const popupRe = /^(help617|hint635\.|modal\.|result\.)/;
const popupParents = new Set(['help617', 'hint635.menu', 'hint635.result', 'modal',
  ...SPEC.buttons.names]);
const textMap = SPEC.popupText.map;
const fourKey = SPEC.popupText.fourKeyLabel;
for (const r of g.recs) {
  const n = r.name || '';
  const pn = byId.get(r.parentId)?.name || '';
  const inScope = popupRe.test(n) || (n === 'label' && (popupParents.has(pn) || /^modal\./.test(pn))) ||
    n === 'result.bg' || (n === 'bg' && pn === 'modal');
  if (!inScope) continue;
  const isFourKeyLabel = n === 'label' && SPEC.buttons.names.includes(pn);
  for (const c of colorFields(r)) {
    const from = hex(c.obj.num);
    if (isFourKeyLabel && c.kind === 'font' && from === fourKey.from) {
      c.obj.num = big('#FF' + fourKey.to.slice(1));
      for (const p of txtParts(r)) { setNum(p, 512, fourKey.size); setNum(p, 513, fourKey.size); }
      colorChanges.push({ name: pn + '/label', kind: 'font', from, to: '#FF' + fourKey.to.slice(1), rule: 'B 四键 label 同首页' });
      modified.add(pn + '/label');
      continue;
    }
    const to = textMap[from];
    if (to && to !== from) {
      c.obj.num = big(to);
      colorChanges.push({ name: n || pn + '/' + n, kind: c.kind, from, to, rule: 'B 弹窗文字翻深墨' });
      modified.add(n);
    }
  }
}
// 旧深藏青底板 → 全透明（边框/卡片由新增层承担）
const transparentBg = ['help617.bg', 'hint635.menu.bg', 'hint635.result.bg', 'result.bg'];
for (const n of transparentBg) {
  const obj = firstFill(R(n)); const from = hex(obj.num);
  obj.num = 0x00FFFFFFn;
  colorChanges.push({ name: n, kind: 'fill', from, to: '#00FFFFFF', rule: 'B 旧底板透明' });
  modified.add(n);
}
{
  const panel = g.recs.find(r => r.name === 'bg' && byId.get(r.parentId)?.name === 'modal');
  if (!panel) throw Error('缺 modal 面板 bg');
  const obj = firstFill(panel); const from = hex(obj.num);
  obj.num = 0x00FFFFFFn;
  colorChanges.push({ name: 'modal/bg', kind: 'fill', from, to: '#00FFFFFF', rule: 'B 旧底板透明' });
  modified.add('modal/bg');
}

// ═══════════════════════════════════════════════════════════════════════
// C. 12.png 通用边框（只给 help617 与 modal）
// ═══════════════════════════════════════════════════════════════════════
const C = {
  brown: '#FF' + P.frameBrown.slice(1), dark: '#FF' + P.frameDark.slice(1),
  dash: '#FF' + P.frameDash.slice(1), light: '#FF' + P.frameLight.slice(1),
  paper: '#FF' + P.paper.slice(1), gold: '#FF' + P.rivetGold.slice(1),
  edge: '#FF' + P.rivetEdge.slice(1),
};
function frameLayers(F) {
  const k = 'art682.' + F.key + '.frame';
  const t = F.t, w = F.w, h = F.h, d = t / 2;
  const L = [{ name: 'frame', dx: 0, dy: 0, w, h, color: C.brown, imageId: 100001, rule: 'C 外框本体' }];
  L.push({ name: k + '.light', dx: 0, dy: 0, w: w - 2 * t + 8, h: h - 2 * t + 8, color: C.light, imageId: 100001, rule: 'C 浅色内线' });
  L.push({ name: k + '.dark', dx: 0, dy: 0, w: w - 2 * t + 4, h: h - 2 * t + 4, color: C.dark, imageId: 100001, rule: 'C 深色内线' });
  L.push({ name: k + '.paper', dx: 0, dy: 0, w: w - 2 * t, h: h - 2 * t, color: C.paper, imageId: 107102, rule: 'C 米白内页' });
  const halfW = w / 2 - d, halfH = h / 2 - d;
  const stepX = 2 * halfW / F.dashH, stepY = 2 * halfH / F.dashV;
  for (let j = 0; j < F.dashH; j++) {
    const x = -halfW + (j + 0.5) * stepX;
    const dw = stepX * 0.62;
    L.push({ name: k + '.dash.top.' + j, dx: x, dy: halfH, w: dw, h: 3, color: C.dash, imageId: 100001, rule: 'C 上虚线' });
    L.push({ name: k + '.dash.bottom.' + j, dx: x, dy: -halfH, w: dw, h: 3, color: C.dash, imageId: 100001, rule: 'C 下虚线' });
  }
  for (let j = 0; j < F.dashV; j++) {
    const y = -halfH + (j + 0.5) * stepY;
    const dh = stepY * 0.62;
    L.push({ name: k + '.dash.left.' + j, dx: -halfW, dy: y, w: 3, h: dh, color: C.dash, imageId: 100001, rule: 'C 左虚线' });
    L.push({ name: k + '.dash.right.' + j, dx: halfW, dy: y, w: 3, h: dh, color: C.dash, imageId: 100001, rule: 'C 右虚线' });
  }
  for (const [sx, sy, tag] of [[-1, 1, 'tl'], [1, 1, 'tr'], [-1, -1, 'bl'], [1, -1, 'br']]) {
    const x = sx * (w / 2 - 1), y = sy * (h / 2 - 1);
    L.push({ name: k + '.rivet.' + tag + '.edge', dx: x, dy: y, w: 22, h: 22, color: C.edge, imageId: 100001, rule: 'C 铆钉外' });
    L.push({ name: k + '.rivet.' + tag + '.gold', dx: x, dy: y, w: 16, h: 16, color: C.gold, imageId: 100001, rule: 'C 铆钉金' });
    L.push({ name: k + '.rivet.' + tag + '.core', dx: x, dy: y, w: 6, h: 6, color: C.dark, imageId: 100001, rule: 'C 铆钉心' });
  }
  // 第 1 层是容器自身（name=frame），其余挂到它下面
  return L;
}
const frameParents = [];
for (const F of SPEC.frames) {
  const parent = R(F.parent);
  const L = frameLayers(F);
  const containerName = L[0].name;
  // 先建容器（名字必须是 DECOR 里的 'frame'），再把它作为其余层的父级
  const container = makeLayer({ ...L[0], name: 'frame' }, parent);
  const i = recTop.sub.indexOf(R(F.anchor).field);
  if (i < 0) throw Error('边框锚点丢失 ' + F.anchor);
  recTop.sub.splice(i, 0, container.field);
  const rest = L.slice(1).map(q => ({ ...q }));
  const created = rest.map(q => makeLayer(q, container));
  const j = recTop.sub.indexOf(container.field);
  recTop.sub.splice(j + 1, 0, ...created.map(r => r.field));
  // 容器自身的颜色/图元已在 makeLayer 设置；记录容器名重复会污染 byName，改用唯一别名登记
  byName.set('art682.' + F.key + '.frame.container', container);
  frameParents.push(parent, container);
  newLayers.push({ note: 'frame container ' + F.key, name: 'frame', parent: parent.name, dx: 0, dy: 0, w: F.w, h: F.h, color: C.brown, imageId: 100001, rule: 'C 容器' });
  void containerName;
}

// ═══════════════════════════════════════════════════════════════════════
// D. 9.png / 8.png EVIDENCE 提示卡（hint635.menu / hint635.result）
// ═══════════════════════════════════════════════════════════════════════
const ECOL = { card: '#FF' + P.evidenceCard.slice(1), shadow: '#FF' + P.evidenceShadow.slice(1), ink: '#FF' + P.evidenceInk.slice(1) };
const cardParents = [];
for (const E of SPEC.evidence) {
  const parent = R(E.parent), k = 'art682.' + E.key + '.card';
  const [sx, sy] = E.shadowOffset;
  const container = makeLayer({ name: 'card', dx: sx, dy: sy, w: E.w, h: E.h, color: ECOL.shadow, imageId: 107102, rule: 'D 卡片投影' }, parent);
  const i = recTop.sub.indexOf(R(E.anchor).field);
  if (i < 0) throw Error('卡片锚点丢失 ' + E.anchor);
  recTop.sub.splice(i, 0, container.field);
  const L = [
    { name: k + '.face', dx: -sx, dy: -sy, w: E.w, h: E.h, color: ECOL.card, imageId: 107102, rule: 'D 米白卡面' },
  ];
  if (E.headingUnderlineDy) L.push({ name: k + '.heading.rule', dx: 0, dy: E.headingUnderlineDy, w: E.w - 90, h: 2, color: ECOL.ink, imageId: 100001, rule: 'D 标题下划线' });
  E.linesDy.forEach((dy, idx) => L.push({ name: k + '.line.' + idx, dx: 0, dy, w: E.w - 70, h: 2, color: ECOL.ink, imageId: 100001, rule: 'D 横线' }));
  const created = L.map(q => makeLayer(q, container));
  const j = recTop.sub.indexOf(container.field);
  recTop.sub.splice(j + 1, 0, ...created.map(r => r.field));
  byName.set('art682.' + E.key + '.card.container', container);
  cardParents.push(parent, container);
}

// ═══════════════════════════════════════════════════════════════════════
// E. 四键弹窗：删 107179 bg + 首页同款纯色胶囊
// ═══════════════════════════════════════════════════════════════════════
const B = SPEC.buttons;
const capColor = '#FF' + B.color.slice(1);
const buttonParents = [];
for (const bid of B.names) {
  const btn = R(bid);
  const bgRec = g.recs.find(r => r.name === 'bg' && r.parentId === btn.id);
  if (!bgRec) throw Error('缺按钮 bg ' + bid);
  // ① recTop ② recs ③ 父 childList（稍后统一重算）
  const idx = recTop.sub.indexOf(bgRec.field);
  if (idx < 0) throw Error('按钮 bg 不在 recTop ' + bid);
  recTop.sub.splice(idx, 1);
  g.recs = g.recs.filter(r => r.id !== bgRec.id);
  byId.delete(bgRec.id);
  deleted.push({ id: bgRec.id, name: bid + '/bg' });
  // 胶囊 3 层，插在 label 之前
  const label = g.recs.find(r => r.name === 'label' && r.parentId === btn.id);
  if (!label) throw Error('缺按钮 label ' + bid);
  const anchorIdx = recTop.sub.indexOf(label.field);
  if (anchorIdx < 0) throw Error('label 不在 recTop ' + bid);
  const specs = [
    { suffix: 'body', ...B.body }, { suffix: 'left', ...B.left }, { suffix: 'right', ...B.right },
  ];
  const created = specs.map(s => makeLayer({
    name: 'art682.' + bid + '.capsule.' + s.suffix, dx: s.dx, dy: s.dy,
    w: s.w, h: s.h, color: capColor, imageId: s.imageId, rule: 'E 首页同款纯色胶囊',
  }, btn));
  recTop.sub.splice(anchorIdx, 0, ...created.map(r => r.field));
  buttonParents.push(btn);
}

// 统一重算所有受影响父级的 childList（按 recTop 顺序）
syncAllChildLists([...new Set([...frameParents, ...cardParents, ...buttonParents])]);
g.recs = recordsOf(g.tree);

// ═══════════════════════════════════════════════════════════════════════
// 闸门
// ═══════════════════════════════════════════════════════════════════════
if (!findScriptLeaf(g).buf.equals(scriptBefore)) throw Error('内嵌 Lua 被改动');
const idsNow = new Set(g.recs.map(r => r.id));
for (const d of deleted) if (idsNow.has(d.id)) throw Error('删除未生效 ' + d.name);
for (const r of g.recs) if (r.parentId != null && !idsNow.has(r.parentId) && !danglingBefore.has(r.id))
  throw Error('新增悬空父引用 ' + r.name);
// 被删 ID 全文 0 引用
const treeBytes = encodeMsg(g.tree);
for (const d of deleted) {
  const needle = Buffer.from(writeVarint(d.id));
  if (treeBytes.includes(needle)) throw Error('被删 ID 仍被引用 ' + d.name);
}
// 新增层几何/颜色/图元与规格一致（抽查逐条：重新读回）
for (const L of newLayers) {
  if (!L.name || L.note || L.name === 'frame' || L.name === 'card') continue;
  const r = byName.get(L.name) || g.recs.find(q => q.name === L.name);
  if (!r) throw Error('新增层丢失 ' + L.name);
  const st = states(r)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  if (Math.abs(pairValue(p, 0) - L.dx) > 0.01 || Math.abs(pairValue(p, 1) - L.dy) > 0.01 ||
      Math.abs(pairValue(s, 0) - L.w) > 0.01 || Math.abs(pairValue(s, 1) - L.h) > 0.01)
    throw Error('新增层几何不符 ' + L.name);
  const o = firstFill(r);
  if (L.color && (!o || hex(o.num) !== L.color)) throw Error('新增层颜色不符 ' + L.name + ' ' + (o ? hex(o.num) : 'null'));
  if (isHiddenRecord(r.field)) throw Error('新增层被隐藏 ' + L.name);
}
// 教程页除 A 外零改动：与 681 逐条比对，只有 A 命中名单可变
const aNames = new Set(colorChanges.filter(c => /^A/.test(c.rule)).map(c => c.name));
const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const touchedTd = [...beforeBytes.keys()].filter(id => afterBytes.has(id) && !beforeBytes.get(id).equals(afterBytes.get(id)) && /^td\./.test(byId.get(id)?.name || ''));
const rogue = touchedTd.filter(id => !aNames.has(byId.get(id).name));
if (rogue.length) throw Error('教程页有非预期改动：' + rogue.slice(0, 5).map(id => byId.get(id).name).join(','));

if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: BASE_SHA,
    records: [beforeBytes.size, g.recs.length], added: added.length, removed: deleted.length,
    colorChanges: colorChanges.length, circlePairs: circlePairs.length, ringCount,
    newLayers: newLayers.filter(L => L.name).length,
    contrastBefore: circlePairs.filter(p => p.crBefore < 3).length,
    contrastAfter: circlePairs.filter(p => p.crAfter < 3).length,
    scriptBytes: scriptBefore.length }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '682 tutorial contrast + popup frames + EVIDENCE cards + pure-color four-key capsules',
  expectRecs: g.recs.length,
  assert(t) {
    const ids = new Set(t.recs.map(r => r.id));
    if (t.recs.length !== g.recs.length) return '记录数不符';
    for (const r of t.recs) {
      const want = afterBytes.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录回读不符 #' + r.id + ' ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 变化';
    const rt = t.tree.find(q => q.field === 9);
    const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => ord.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && ord.get(t.recs.find(q => q.id === list[i - 1]).field) > ord.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});

const audit = {
  version: 682, name: '682 popup style', date: new Date().toISOString().slice(0, 10),
  base: { file: SPEC.base.file, sha256: BASE_SHA, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: g.recs.length, scriptBytes: scriptBefore.length },
  spec: { userDecisions: SPEC.userDecisions, palette: P, frames: SPEC.frames, evidence: SPEC.evidence,
    buttons: SPEC.buttons, limitations: SPEC.limitations },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: g.recs.length,
    added: added.length, removed: deleted.length, colorChanges: colorChanges.length,
    newLayers: newLayers.filter(L => L.name).length, circlePairs: circlePairs.length, ringCount },
  contrast: { lowBefore: circlePairs.filter(p => p.crBefore < 3).length,
    lowAfter: circlePairs.filter(p => p.crAfter < 3).length, samples: circlePairs.slice(0, 14) },
  deleted: deleted.map(d => d.name),
  colorChangesByRule: Object.fromEntries([...colorChanges.reduce((m, c) => m.set(c.rule, (m.get(c.rule) || 0) + 1), new Map())].sort()),
  guarantees: ['内嵌 Lua 逐字节相同', '教程页除对比度/红绿圈外零改动（逐条字节比对）',
    '被删 8 个 bg ID 全文 0 引用', '新增层几何/颜色/图元/显隐逐条断言',
    '所有受影响父级 childList 按 recTop 顺序重算', 'recTop 层序与 clue childList 同序'],
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '682_构建审计.json'), JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
fs.writeFileSync(path.join(DIR, '682_新增层清单.json'), JSON.stringify(newLayers.filter(L => L.name), null, 2));
fs.writeFileSync(path.join(DIR, '682_逐条改色清单.json'), JSON.stringify(colorChanges, null, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: [audit.counts.recordsBefore, audit.counts.recordsAfter],
  added: added.length, removed: deleted.length, colorChanges: colorChanges.length,
  contrastLow: [audit.contrast.lowBefore, audit.contrast.lowAfter], status: 'APPLIED' }, null, 2));
