// 678 · 基于 677 的两处整改（677 保留未改）
//   ① 用户：「环末端上这个小椭圆不要」⇒ 隐藏 8 条 art677.ring.N.tipHi（浅灰小椭圆）
//   ② 用户：「对注释卡再做一轮修正……只做两侧边缘重做，缺口不要靠背景色补，
//      从几何层面构造真缺口，且一定不要有溢出构造边缘的毛刺，其实只用缩进两侧矩形边缘
//      一段距离，增补几个三角形，底下垫一层稍大一圈的同形状描边即可」
//      ＋「部分区域还需要矩形来塑造平边缘，图形不必局限我给的」
//      ⇒ 主体/描边矩形各缩进 9px（半宽 80→71 / 83→74）；每侧 3 个凸齿，
//        每齿 = 1 枚矩形（平边缘段）+ 1 枚 100003 三角（尖端）；描边齿整体大一圈 3px。
//      ★ 零溢出硬闸门：23 枚渐变三角本地 x∈[-70,51]，主体半宽 71 ⇒ 渐变全在主体内；
//        像素级掩膜验证「主体 ⊆ 描边、渐变 ⊆ 主体」均为 0 溢出。
//
// 输入  ../677_活页扣孔与八环/677_活页扣孔与八环.gil（7407 条）
// 输出  678_注释卡真缺口.gil（7407 + 24 = 7431 条）
// 用法  FORCE=1 node 构建678.mjs   /   node 构建678.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口');
const INPUT = path.join(ROOT, 'qianxing-murdoku/677_活页扣孔与八环/677_活页扣孔与八环.gil');
const OUTPUT = path.join(DIR, '678_注释卡真缺口.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '678_注释卡图元.json'), 'utf8'));
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
  if (!p.sub) p.sub = [];
  let f = p.sub.find(q => q.field === k && q.wt === 0);
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
const hidden = [], modified = [], added = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function hide(r) { if (!isHiddenRecord(r.field)) { setHiddenRecord(r.field, true); hidden.push(r.name); } touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');
const PROTO_IMG = 'td.home.page.1.help619.icon';

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
  const idx = recTop.sub.findIndex(q => q === byName.get(e.anchor)?.field);
  if (idx < 0) throw Error('锚点不在 recTop ' + e.anchor);
  recTop.sub.splice(idx, 0, f);
  const ip = ns(f, [505, 503, 84])[0];
  if (!ip) throw Error('新层缺图片块 ' + name);
  setNum(ip, 502, colorOf(e.color)); setNum(ip, 503, e.img); setNum(ip, 504, 1);
  const r = { id, name, parentId: GRP.id, field: f };
  setGeomScreen(r, e.cx, e.cy, e.w, e.h);
  setRot(r, e.rot);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}

// ── ① 去掉环末端浅灰小椭圆（8 条 tipHi）──────────────────────────────────
for (const n of SPEC.hidden.tipHi) hide(named(n));
if (hidden.length !== 8) throw Error('tipHi 隐藏数量不符：' + hidden.length);

// ── ② 注释卡：主体/描边两侧缩进 ──────────────────────────────────────────
const M = SPEC.modifyExisting;
const tab = named('art641.game.help.tab'), outline = named('art661.tab.outline');
const tg = screenGeom(tab), og = screenGeom(outline);
if (Math.abs(tg[2] - 160) > 0.01 || Math.abs(og[2] - 166) > 0.01) throw Error('票券基准不是 677');
setGeomScreen(tab, 384, 211, M['art641.game.help.tab'].to[2], M['art641.game.help.tab'].to[3]);
setRot(tab, -13);
setGeomScreen(outline, 384, 211, M['art661.tab.outline'].to[2], M['art661.tab.outline'].to[3]);
setRot(outline, -13);

// ── ③ 24 枚齿图元（描边齿在主体之前 / 主体齿在渐变之前）──────────────────
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
// 677 全部成果（除 8 条 tipHi 与票券主体/描边）逐字节不变
const keepNames = g.recs.filter(r =>
  /^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art677\.ring\.)/.test(r.name || '')
  && !SPEC.hidden.tipHi.includes(r.name)
  || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame',
      'art658.clues.binding', 'art676.binding.mid'].includes(r.name)).map(r => r.name);
const keepBytes = new Map(keepNames.map(n => [n, beforeBytes.get(named(n).id)]));
for (const n of keepNames)
  if (!keepBytes.get(n).equals(encodeMsg([named(n).field]))) throw Error('677 成果被改动 ' + n);
if (keepNames.filter(n => /^art675\.wax\./.test(n)).length !== 240) throw Error('675 火漆层数不符');
if (keepNames.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n)).length !== 23) throw Error('672 渐变三角数不符');
if (keepNames.filter(n => /^art677\.ring\./.test(n)).length !== 64) throw Error('677 环层数不符');
// 零溢出（由 _拟合注释卡678.mjs 的像素级掩膜闸门给出）
const Z = SPEC.gates;
if (!Z.zeroSpur || Z.mainOutsideOutline !== 0 || Z.gradOutsideMain !== 0)
  throw Error('零溢出闸门未通过');
// 层序：描边齿 < 主体 < 主体齿 < 渐变三角
const orderNow = new Map(); recTop.sub.forEach((f, i) => orderNow.set(f, i));
const LAYER_OK = SPEC.elements.every(e => {
  const o = orderNow.get(byName.get(e.name).field);
  return e.layer === 'outline' ? o < orderNow.get(tab.field)
    : o > orderNow.get(tab.field) && o < orderNow.get(named('art664.tab.mid.fit01').field);
});
if (!LAYER_OK) throw Error('齿层序不符合「描边齿 → 主体 → 主体齿 → 渐变」');
const allRecs = [...g.recs, ...added];
const teethVisible = allRecs.filter(r => /^art678\.tab\./.test(r.name || '') && !isHiddenRecord(r.field)).length;
const tipHiVisible = allRecs.filter(r => /\.tipHi$/.test(r.name || '') && !isHiddenRecord(r.field)).length;
if (teethVisible !== SPEC.elements.length || tipHiVisible !== 0) throw Error('可见层数量不符');

const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(allRecs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length,
    teethVisible, tipHiVisible, layerOk: LAYER_OK, zeroSpur: Z.zeroSpur,
    keepNames: keepNames.length }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '678 annotation ticket true geometric notches + remove ring tip highlight',
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
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '677 成果被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '678 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '677_活页扣孔与八环.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '678_注释卡真缺口.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    userFeedback: SPEC.userFeedback,
    rings: { hiddenTipHi: SPEC.hidden.tipHi.length, note: '去掉环末端浅灰小椭圆' },
    ticket: { geometry: SPEC.geometry, safety: SPEC.safety, gates: SPEC.gates,
      modifyExisting: SPEC.modifyExisting, teeth: SPEC.elements.length,
      layerOrder: '描边齿 → 主体 → 主体齿 → 672 渐变三角', layerOk: LAYER_OK },
    keepUntouched: keepNames.length,
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, removed: 0, hidden: hidden.length, modified: modified.length },
  addedNames: added.map(r => r.name), hiddenNames: hidden,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '678_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, teethVisible, tipHiVisible,
  zeroSpur: Z.zeroSpur, layerOk: LAYER_OK, scriptBytes: scriptBefore.length, status: 'APPLIED' }, null, 2));
