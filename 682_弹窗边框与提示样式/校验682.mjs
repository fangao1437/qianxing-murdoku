// 682 结构校验：681 → 682（教程对比度/圈 + 弹窗边框 + EVIDENCE 卡 + 四键胶囊）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const { readGil, encodeMsg, writeVarint, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(REPO, 'tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(REPO, 'tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(REPO, '681_教程弹窗配色/681_教程弹窗配色.gil'));
const B = readGil(path.join(DIR, '682_弹窗边框与提示样式.gil'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '682_规格.json'), 'utf8'));
const AUDIT = JSON.parse(fs.readFileSync(path.join(DIR, '682_构建审计.json'), 'utf8'));
const CHANGES = JSON.parse(fs.readFileSync(path.join(DIR, '682_逐条改色清单.json'), 'utf8'));
const LAYERS = JSON.parse(fs.readFileSync(path.join(DIR, '682_新增层清单.json'), 'utf8'));
const enc = r => encodeMsg([r.field]);
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const byIdB = new Map(B.recs.map(r => [r.id, r]));
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const lum = h => { const [r, g, b] = [3, 5, 7].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
  .map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const CR = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)).toString('hex') !== enc(mb.get(id)).toString('hex'));

// ── 颜色字段（独立实现，不与构建脚本共用） ───────────────────────────────
function colorFields(r) {
  const out = [];
  (function w(f, d) {
    if (d > 30) return;
    if (f.wt === 2 && f.sub && f.field === 84) { const c = f.sub.find(x => x.field === 502 && x.wt === 0); if (c) out.push({ kind: 'fill', obj: c }); }
    if (f.wt === 2 && f.sub && f.field === 75) { const c = f.sub.find(x => x.field === 504 && x.wt === 0); if (c) out.push({ kind: 'font', obj: c }); }
    if (f.sub) for (const s of f.sub) w(s, d + 1);
  })(r.field, 0);
  return out;
}
const firstFill = r => colorFields(r).find(c => c.kind === 'fill')?.obj;
const firstFont = r => colorFields(r).find(c => c.kind === 'font')?.obj;
function imageId(r) {
  let out = null;
  (function w(f, d) { if (d > 30) return; if (f.field === 84 && f.sub) { const im = f.sub.find(x => x.field === 503 && x.wt === 0); if (im) out = Number(im.num); } if (f.sub) for (const s of f.sub) w(s, d + 1); })(r.field, 0);
  return out;
}

// ── ① 增删与预期 ─────────────────────────────────────────────────────────
const removedNames = removed.map(id => (ma.get(id).name || '') + '@' + (ma.get(id).parentId || ''));
const removedOk = removed.length === 8 && removed.every(id => ma.get(id).name === 'bg');
const addedOk = added.length === AUDIT.counts.added;
const dupIds = B.recs.length - new Set(B.recs.map(r => r.id)).size;

// ── ② 既有记录：只允许「颜色改动 + childList 同步 + 旧底板透明」 ───────────
const changeNames = new Set(CHANGES.map(c => c.name));
const childListParents = new Set(['modal', 'help617', 'hint635.menu', 'hint635.result', ...SPEC.buttons.names]);
// 收集 75(文字)/84(图元) 块里全部 wt0 数值字段：颜色 502/504 + 字号 512/513 等
function numFields(r) {
  const out = [];
  (function w(f, d) {
    if (d > 30) return;
    if ((f.field === 75 || f.field === 84) && f.sub) {
      (function take(q) { if (q.wt === 0) out.push(q); if (q.sub) for (const s of q.sub) take(s); })(f);
      return;
    }
    if (f.sub) for (const s of f.sub) w(s, d + 1);
  })(r.field, 0);
  return out;
}
const rogue = [];
let colorOnlyOk = true, colorDiffCount = 0;
for (const id of changed) {
  const ra = ma.get(id), rb = mb.get(id);
  const n = ra.name || '';
  const na = numFields(ra), nb = numFields(rb);
  if (na.length !== nb.length) { colorOnlyOk = false; rogue.push('数值字段数变化 ' + n); continue; }
  const saved = nb.map(f => f.num);
  for (let i = 0; i < nb.length; i++) nb[i].num = na[i].num;
  const reverted = enc(rb).toString('hex') === enc(ra).toString('hex');
  for (let i = 0; i < nb.length; i++) nb[i].num = saved[i];
  for (let i = 0; i < nb.length; i++) if (na[i].num !== saved[i]) colorDiffCount++;
  if (reverted) continue;                       // 纯 75/84 数值改动 ✓
  // 非数值改动只允许 childList 同步（父容器）
  const clA = findChildListTop(ra.field.sub), clB = findChildListTop(rb.field.sub);
  if (childListParents.has(n) && clA && clB) {
    const keep = clB.payload; clB.payload = Buffer.from(clA.payload); clB.len = clB.payload.length;
    const ok2 = enc(rb).toString('hex') === enc(ra).toString('hex');
    clB.payload = keep; clB.len = keep.length;
    if (ok2) continue;
  }
  colorOnlyOk = false; rogue.push('非预期改动 ' + n);
}
// 改动记录必须命中「逐条改色清单」（原始名或 父/子 别名）或为 childList 父级
const changedExtra = changed.filter(id => {
  const r = ma.get(id), n = r.name || '', pn = ma.get(r.parentId)?.name || '';
  return !changeNames.has(n) && !changeNames.has(pn + '/' + n) && !childListParents.has(n);
}).map(id => ma.get(id).name || '');

// ── ③ 新增层逐条几何/颜色/图元/显隐/父级 ─────────────────────────────────
const layerByName = new Map();
for (const r of B.recs.filter(r => added.includes(r.id))) {
  if (!layerByName.has(r.name)) layerByName.set(r.name, []);
  layerByName.get(r.name).push(r);
}
let layersOk = true; const layerErrors = [];
for (const L of LAYERS) {
  if (!L.name || L.note || L.name === 'frame' || L.name === 'card') continue;
  const r = (layerByName.get(L.name) || [])[0];
  if (!r) { layersOk = false; layerErrors.push('缺层 ' + L.name); continue; }
  const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  if (!p || !s) { layersOk = false; layerErrors.push('几何缺 ' + L.name); continue; }
  if (Math.abs(pairValue(p, 0) - L.dx) > 0.02 || Math.abs(pairValue(p, 1) - L.dy) > 0.02 ||
      Math.abs(pairValue(s, 0) - L.w) > 0.02 || Math.abs(pairValue(s, 1) - L.h) > 0.02) {
    layersOk = false; layerErrors.push('几何不符 ' + L.name); }
  if (L.color) { const o = firstFill(r); if (!o || hex(o.num) !== L.color) { layersOk = false; layerErrors.push('色不符 ' + L.name + ' ' + (o ? hex(o.num) : 'null')); } }
  if (L.imageId && imageId(r) !== L.imageId) { layersOk = false; layerErrors.push('图元不符 ' + L.name + ' ' + imageId(r)); }
  if (isHiddenRecord(r.field)) { layersOk = false; layerErrors.push('被隐藏 ' + L.name); }
}
const frameContainers = B.recs.filter(r => r.name === 'frame' && added.includes(r.id));
const cardContainers = B.recs.filter(r => r.name === 'card' && added.includes(r.id));
const decorOk = frameContainers.length === 2 && cardContainers.length === 2;

// ── ④ 教程：对比度 / 红绿圈 ──────────────────────────────────────────────
let pairs = 0, lowCR = 0; const pairSamples = [];
for (const r of B.recs.filter(r => /^td\./.test(r.name || '') && /\.(clueface|lg\.\d+|rule\.\d+\.num)\.bg$/.test(r.name))) {
  const glyph = B.recs.find(q => q.name === r.name.replace(/\.bg$/, ''));
  const a = firstFill(r), b = glyph && firstFont(glyph);
  if (!a || !b) continue;
  pairs++; const cr = CR(hex(a.num), hex(b.num));
  if (cr < 3) lowCR++;
  if (pairSamples.length < 8) pairSamples.push({ name: glyph.name, bg: hex(a.num), fg: hex(b.num), cr: +cr.toFixed(2) });
}
const rings = B.recs.filter(r => /\.ring\.[A-Z]\.\d+$/.test(r.name || ''));
const ringColors = [...new Set(rings.map(r => hex(firstFill(r).num)))];
const ringOk = rings.length === 180 && ringColors.length === 2 &&
  ringColors.includes('#FF4FAE5A') && ringColors.includes('#FFE0483A');

// ── ⑤ 四键：bg 已删、3 层胶囊、label 同首页 ─────────────────────────────
const btnOk = [], capsuleCounts = [];
for (const bid of SPEC.buttons.names) {
  const btn = B.recs.find(r => r.name === bid);
  if (!btn) { btnOk.push(bid + ':缺按钮'); continue; }
  const kids = B.recs.filter(r => r.parentId === btn.id);
  const bg = kids.find(r => r.name === 'bg');
  const caps = kids.filter(r => /capsule\.(body|left|right)$/.test(r.name || ''));
  const label = kids.find(r => r.name === 'label');
  const lf = label && firstFont(label);
  const sz = (() => { let v = null; (function w(f, d) { if (d > 30) return; if (f.field === 75 && f.sub) { const q = f.sub.find(x => x.field === 512 && x.wt === 0); if (q) v = Number(q.num); } if (f.sub) for (const s of f.sub) w(s, d + 1); })(label?.field || { field: 0 }, 0); return v; })();
  capsuleCounts.push(caps.length);
  const ok = !bg && caps.length === 3 && lf && hex(lf.num) === '#FF6B3A22' && sz === 24;
  if (!ok) btnOk.push(bid + ':' + JSON.stringify({ bg: !!bg, caps: caps.length, color: lf ? hex(lf.num) : null, size: sz }));
}

// ── ⑥ 脚本 / 层序 / childList / 悬空父 / 背景资产 ───────────────────────
const sA = findScriptLeaf(A).buf.toString('utf8'), sB = findScriptLeaf(B).buf.toString('utf8');
const scriptSame = sA === sB && Buffer.byteLength(sB) === 636689;
function descendants(g, n) {
  const byP = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byP.has(k)) byP.set(k, []); byP.get(k).push(r.id); }
  const out = new Set(), q = []; const root = g.recs.find(r => r.name === n); if (!root) return [];
  out.add(root.id); q.push(root.id);
  for (let i = 0; i < q.length; i++) for (const c of byP.get(q[i]) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v19'));
const bgChanged = changed.filter(id => bgA.has(id)).length;
const idOf = (g, f) => g.recs.find(q => q.field === f)?.id;
const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
// 只比「两版都还在」的旧记录相对层序（682 删了 8 个 bg，不能按绝对下标比）
const idsA = rtA.sub.map(f => idOf(A, f)).filter(id => id != null && ma.has(id) && mb.has(id));
const idsB = rtB.sub.map(f => idOf(B, f)).filter(id => id != null && ma.has(id) && mb.has(id));
const recTopSame = idsA.length === idsB.length && idsA.every((id, i) => id === idsB[i]);
const ord = new Map(); rtB.sub.forEach((f, i) => ord.set(f, i));
let childListOk = true;
for (const root of B.recs.filter(r => findChildListTop(r.field.sub))) {
  const cl = findChildListTop(root.field.sub);
  const list = asIdList(cl.payload, true) || [];
  const seq = list.filter(id => ord.has(mb.get(id)?.field));
  if (seq.some((id, i) => i > 0 && ord.get(mb.get(seq[i - 1]).field) > ord.get(mb.get(id).field))) { childListOk = false; break; }
  const kids = B.recs.filter(r => r.parentId === root.id).map(r => r.id);
  if (list.length !== kids.length || list.some(id => !kids.includes(id))) { childListOk = false; break; }
}
const idsSetB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsSetB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;
// 被删 ID 全文 0 引用
const bodyBytes = fs.readFileSync(path.join(DIR, '682_弹窗边框与提示样式.gil'));
const deletedRefs = removed.filter(id => bodyBytes.includes(Buffer.from(writeVarint(id))));

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, removedNames, removedOk, addedOk, dupIds,
  changed: changed.length, changedExtra, colorOnlyOk, colorDiffCount, rogue,
  layersOk, layerErrors, layerChecked: LAYERS.filter(L => L.name && !L.note && !['frame', 'card'].includes(L.name)).length,
  decor: { frameContainers: frameContainers.length, cardContainers: cardContainers.length, decorOk },
  tutorial: { circlePairs: pairs, lowContrastPairs: lowCR, pairSamples, rings: rings.length, ringColors, ringOk },
  buttons: { errors: btnOk, capsuleCounts },
  scriptSame, scriptBytes: [Buffer.byteLength(sA), Buffer.byteLength(sB)],
  policeV19Descendants: bgA.size, bgChanged,
  recTopSame, childListOk, dangling, deletedRefs: deletedRefs.length,
};
checks.verdict = removedOk && addedOk && dupIds === 0 && changedExtra.length === 0 &&
  colorOnlyOk && rogue.length === 0 && layersOk && layerErrors.length === 0 && decorOk &&
  pairs >= 90 && lowCR === 0 && ringOk && btnOk.length === 0 &&
  scriptSame && bgChanged === 0 && recTopSame && childListOk && dangling === 0 && deletedRefs.length === 0;
fs.writeFileSync(path.join(DIR, '682_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  changedExtra: changedExtra.length, rogue: rogue.length, colorOnlyOk,
  layersOk, layerErrors: layerErrors.length, decorOk,
  circlePairs: pairs, lowContrastPairs: lowCR, ringOk, buttonErrors: btnOk.length,
  scriptSame, bgChanged, recTopSame, childListOk, dangling, deletedRefs: deletedRefs.length }, null, 2));
if (!checks.verdict) process.exit(2);
