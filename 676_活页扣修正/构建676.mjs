// 676 · 基于 675 的「活页扣」专项整改（675 保留未改）
//   用户反馈：问题主要在活页扣表现、多余黄色虚线、白底向左延伸过短导致棕色边太宽。
//   ① 活页扣：隐藏 20 条 art663.ring.*（灰色高光 + 孤立黑球、5 组/94px）；
//      按设计全屏图逐像素测出的 6 组/59.6px、x 右端 35、上黑中棕下浅棕的粗弧钩，
//      新增 42 枚 100002 椭圆（6 组 × 7 层）。
//   ② 多余黄色虚线：隐藏 12 条 art658.clues.binding.dash*（设计稿装订边无黄色像素）。
//   ③ 棕边：art658.clues.binding 40→24 宽（设计稿白纸左界 x=24），色 #2E1A12→#3F1E15，
//      并补 1 条 12px 中带 #4D2419；收窄后原本被盖住的白色 notebook.frame 从 x=24 露出。
//
// 输入  ../675_直边票券与火漆精拟合/675_直边票券与火漆精拟合.gil（7292 条）
// 输出  676_活页扣修正.gil（7292 + 43 = 7335 条）
// 用法  FORCE=1 node 构建676.mjs   /   node 构建676.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/676_活页扣修正');
const INPUT = path.join(ROOT, 'qianxing-murdoku/675_直边票券与火漆精拟合/675_直边票券与火漆精拟合.gil');
const OUTPUT = path.join(DIR, '676_活页扣修正.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '676_活页扣图元.json'), 'utf8'));
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf, encodeMsg,
  ensureChildListTop, findChildListTop, asIdList, setChildList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recTop = g.tree.find(q => q.field === 9);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!p.sub) p.sub = [];
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
const cache = new Map();
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (cache.has(r.id)) return cache.get(r.id);
  const st = states(r)[0], p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  cache.set(r.id, res); return res;
}
function screenGeom(r) {
  const st = states(r)[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  if (!p || !s) return null;
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  return [px + pairValue(p, 0), py - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)];
}
function setGeomScreen(r, cx, cy, w, h) {
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - px, py - cy);
    setPair(pairOf(st, 505), w, h);
  }
  cache.delete(r.id); touch(r);
}
function setRot(r, deg) {
  for (const st of states(r)) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }]; rf.payload = null; rf.len = 5;
  }
  touch(r);
}
function retint(r, hex, imageId = null) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(hex));
  if (imageId !== null) { setNum(p, 503, imageId); setNum(p, 504, 1); }
  touch(r);
}
const hidden = [], modified = [], added = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function hide(r) { if (!isHiddenRecord(r.field)) { setHiddenRecord(r.field, true); hidden.push(r.name); } touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');
const PROTO_IMG = 'td.home.page.1.help619.icon';
const ANCHOR = 'art663.ring.1.outer';
if (!byName.has(ANCHOR)) throw Error('找不到活页扣层序锚点 ' + ANCHOR);

function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
let max = BigInt(g.maxId);
function cloneLayer(name, e) {
  const proto = byName.get(PROTO_IMG);
  if (!proto) throw Error('缺图片原型 ' + PROTO_IMG);
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nf) throw Error('找不到原型名字字段');
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(GRP.id) });
  const cl = (function find(ff) { return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  const idx = recTop.sub.findIndex(q => q === byName.get(ANCHOR)?.field);
  if (idx < 0) throw Error('锚点不在 recTop');
  recTop.sub.splice(idx, 0, f);
  const ip = ns(f, [505, 503, 84])[0];
  if (!ip) throw Error('新层缺图片块 ' + name);
  setNum(ip, 502, colorOf(e.color)); setNum(ip, 503, e.img || 100002); setNum(ip, 504, 1);
  const r = { id, name, parentId: GRP.id, field: f };
  setGeomScreen(r, e.cx, e.cy, e.w, e.h);
  setRot(r, e.rot || 0);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}

// ── ① 隐藏旧活页扣（20 层）与装订边黄色虚线（12 层）────────────────────
for (const n of SPEC.hidden.rings) hide(named(n));
for (const n of SPEC.hidden.dashes) hide(named(n));
if (hidden.length !== 32) throw Error('隐藏数量不符：' + hidden.length);

// ── ② 棕色边：40 → 24（设计稿白纸左界 x=24），改设计稿色 ─────────────────
const binding = named('art658.clues.binding');
const bg = screenGeom(binding);
if (Math.abs(bg[2] - 40) > 0.01 || Math.abs(bg[0] - 20) > 0.01) throw Error('装订边基准不是 675：' + bg);
const B = SPEC.binding;
setGeomScreen(binding, B.centerX, B.centerY, B.width, B.height);
retint(binding, B.color, 100001);
// 中带（设计稿棕边中部更亮），先画在环之下
const M = B.midBand;
cloneLayer('art676.binding.mid', { cx: M.centerX, cy: M.centerY, w: M.width, h: M.height,
  rot: 0, color: M.color, img: 100001 });

// ── ③ 新活页扣 42 层（6 组 × 7 层）─────────────────────────────────────
for (const e of SPEC.elements) cloneLayer(e.name, e);

// ── childList 同步 ───────────────────────────────────────────────────────
const fieldIndex = new Map();
recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set([...added.map(r => r.parentId), GRP.id])) {
  const p = byId.get(pid);
  if (!p) throw Error('父记录丢失 ' + pid);
  const cl = ensureChildListTop(p);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids);
  touch(p);
}

// ── 闸门 ─────────────────────────────────────────────────────────────────
// 675 成果（票券 25 层 / 火漆 240 层 / 672 渐变 23 枚三角）逐字节不变
const keepNames = [
  ...g.recs.filter(r => /^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art641\.game\.help\.tab$|art661\.tab\.outline$)/.test(r.name || '')).map(r => r.name),
  'clues.help617', 'clues.help627.hit',
];
const keepBytes = new Map(keepNames.map(n => [n, beforeBytes.get(named(n).id)]));
for (const n of keepNames)
  if (!keepBytes.get(n).equals(encodeMsg([named(n).field]))) throw Error('675 成果被改动 ' + n);
if (keepNames.filter(n => /^art675\.wax\./.test(n)).length !== 240) throw Error('675 火漆层数不符');
if (keepNames.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n)).length !== 23) throw Error('672 渐变三角数不符');
// 新增层零溢出：环右端 ≤ 36（设计稿实测 35）
const maxRight = Math.max(...SPEC.elements.map(e => e.cx + e.w / 2));
if (maxRight > 36.5) throw Error('活页扣溢出设计稿右端：' + maxRight);
// 可见层
const allRecs = [...g.recs, ...added];
const ringVisible = allRecs.filter(r => /^art676\.ring\./.test(r.name || '') && !isHiddenRecord(r.field)).length;
const oldRingVisible = allRecs.filter(r => /^art663\.ring\./.test(r.name || '') && !isHiddenRecord(r.field)).length;
const dashVisible = allRecs.filter(r => /^art658\.clues\.binding\.dash/.test(r.name || '') && !isHiddenRecord(r.field)).length;
if (ringVisible !== SPEC.elements.length || oldRingVisible !== 0 || dashVisible !== 0)
  throw Error(`可见层不符 ring=${ringVisible} old=${oldRingVisible} dash=${dashVisible}`);

const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(allRecs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length,
    ringVisible, maxRight, keepNames: keepNames.length }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: `676 binder rings design-fit (6x7 ellipses), binding 40->24, remove yellow dashes`,
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touchedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return '非目标记录被改动 ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const rt = t.tree.find(q => q.field === 9);
    const idx = new Map(); rt.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    for (const n of keepNames) {
      const a = t.recs.find(q => q.name === n);
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '675 成果被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '676 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '675_直边票券与火漆精拟合.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '676_活页扣修正.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    userFeedback: '活页扣表现、多余黄色虚线、白底向左延伸过短导致棕色边太宽',
    measurement: SPEC.measurement,
    binding: { before: [20, 513.5, 40, 535, '#2E1A12'], after: [B.centerX, B.centerY, B.width, B.height, B.color],
      midBand: M, paperLeftAfter: SPEC.measurement.paperLeftX },
    rings: { before: 'art663.ring.1..5 × 4 层 = 20（灰高光 #6C6962 + 孤立黑球，5 组 / 94px）',
      after: 'art676.ring.1..6 × 7 层 = 42（上黑 / 中棕灰 / 右段渐亮 / 下浅棕 / 末端下垂圆头）',
      count: 6, layersPerRing: SPEC.layers.length, maxRight, colors: SPEC.colors },
    hidden: { rings: SPEC.hidden.rings.length, dashes: SPEC.hidden.dashes.length },
    keepUntouched: keepNames.length,
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, removed: 0, hidden: hidden.length, modified: modified.length },
  visibleLayers: { ringBefore: 20, ringAfter: ringVisible, dashBefore: 12, dashAfter: dashVisible },
  addedNames: added.map(r => r.name), hiddenNames: hidden,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '676_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, ringVisible, dashVisible,
  maxRight, scriptBytes: scriptBefore.length, status: 'APPLIED' }, null, 2));
