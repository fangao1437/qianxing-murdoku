// 675 · 基于 674 的两处整改
//   用户：「票券干脆两侧做直吧，加六个椭圆观感反而下降；至于火漆差距依然较为明显，
//          火漆先不考虑省图元，先高精度按设计图拟合」
//
// ① 票券两侧平直：隐藏 16 枚 art663.tab.edge.*/tooth.*（6 枚圆齿 + 盖条等），
//    主体保持 160×66、描边 160×72 → 166×72（左右各 3px 深棕直边）；
//    23 枚 672 渐变拟合三角逐字节零改动。可见层 33 → 25。
// ② 火漆高精度拟合（不省图元）：隐藏全部 50 条旧 wax 记录，
//    按 675_火漆图元.json 新增 240 枚椭圆 —— 外缘半径 R(θ) 逐 5° 取自设计稿；
//    主体 214 枚按「可见环带中心」取设计稿 5×5 的 90 分位色（16 级红阶）、外→内 7 层密网格；
//    另 26 枚按设计稿水平剖面实测位置(r≈42)补 #D70601 高光峰，最后绘制。
//
// 输入  ../674_票券与火漆重做/674_票券与火漆重做.gil（7052 条）
// 输出  675_直边票券与火漆精拟合.gil（7052 + 240 = 7292 条）
// 用法  FORCE=1 node 构建675.mjs   /   node 构建675.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/675_直边票券与火漆精拟合');
const INPUT = path.join(ROOT, 'qianxing-murdoku/674_票券与火漆重做/674_票券与火漆重做.gil');
const OUTPUT = path.join(DIR, '675_直边票券与火漆精拟合.gil');
const FIT = JSON.parse(fs.readFileSync(path.join(DIR, '675_火漆图元.json'), 'utf8'));
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
const recTopBeforeIds = recTop.sub.map(f => g.recs.find(r => r.field === f)?.id);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
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
const ANCHOR = 'art657.game.flag.hint.ribbon.tri.bottom';
if (!byName.has(ANCHOR)) throw Error('找不到火漆层序锚点 ' + ANCHOR);

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
  // 全部新层按 elements 顺序插在锚点之前（先画的在更下）
  const idx = recTop.sub.findIndex(q => q === byName.get(ANCHOR)?.field);
  if (idx < 0) throw Error('锚点不在 recTop');
  recTop.sub.splice(idx, 0, f);
  const ip = ns(f, [505, 503, 84])[0];
  if (!ip) throw Error('新层缺图片块 ' + name);
  setNum(ip, 502, colorOf(e.color)); setNum(ip, 503, 100002); setNum(ip, 504, 1);
  const r = { id, name, parentId: GRP.id, field: f };
  setGeomScreen(r, e.cx, e.cy, e.w, e.h);
  setRot(r, e.rot || 0);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}

// ── ① 票券：两侧做直 ────────────────────────────────────────────────────
for (const n of g.recs.filter(r => /^art663\.tab\.(edge|tooth)\./.test(r.name || '')).map(r => r.name))
  hide(named(n));
const tabMain = named('art641.game.help.tab'), tabOutline = named('art661.tab.outline');
const gm = screenGeom(tabMain), go = screenGeom(tabOutline);
if (Math.abs(gm[2] - 160) > 0.01 || Math.abs(go[2] - 160) > 0.01) throw Error('票券基准不是 674');
// 描边 160→166：左右各 3px 深棕直边，上下仍 3px
setGeomScreen(tabOutline, 384, 211, 166, 72); setRot(tabOutline, -13); retint(tabOutline, '#592520', 100001);

// ── ② 火漆：隐藏全部旧层，按设计稿拟合新增 ──────────────────────────────
const oldWax = g.recs.filter(r => /^(art663|art664)\.wax\./.test(r.name || ''));
if (oldWax.length !== 50) throw Error('旧蜡层数量不符：' + oldWax.length);
for (const r of oldWax) hide(r);
FIT.elements.forEach((e, i) => cloneLayer(`art675.wax.fit${String(i).padStart(3, '0')}`, e));

// ── childList 同步（新增 137 条要与 recTop 同序）────────────────────────
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
const fitNames = g.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')).map(r => r.name);
if (fitNames.length !== 23) throw Error('672 渐变三角数量不符');
const fitBytes = new Map(fitNames.map(n => [n, beforeBytes.get(named(n).id)]));
for (const n of fitNames)
  if (!fitBytes.get(n).equals(encodeMsg([named(n).field]))) throw Error('渐变三角被改动 ' + n);
// 新增椭圆零溢出：中心到火漆中心距离 + 半径 ≤ 该角度设计稿外缘 + 0.6px 容差
const outline = FIT.outline.realRadius;
let maxOverflow = 0;
for (let i = 0; i < added.length; i++) {
  const e = FIT.elements[i];
  const deg = Math.atan2(e.cy - 342, e.cx - 1326) * 180 / Math.PI;
  const R = outline[Math.round(((deg % 360) + 360) % 360 / 5) % outline.length];
  const reach = Math.hypot(e.cx - 1326, e.cy - 342) + e.w / 2;
  maxOverflow = Math.max(maxOverflow, reach - R);
}
if (maxOverflow > 0.6) throw Error('火漆图元溢出设计稿轮廓：' + maxOverflow.toFixed(2));
// 可见层
const allRecs = [...g.recs, ...added];
const tabVisible = allRecs.filter(r => /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/.test(r.name || '')
  && !isHiddenRecord(r.field)).length;
const waxVisible = allRecs.filter(r => /^art675\.wax\./.test(r.name || '') && !isHiddenRecord(r.field)).length;
if (tabVisible !== 25 || waxVisible !== FIT.elements.length)
  throw Error(`可见层数量不符：tab=${tabVisible}(期望25) wax=${waxVisible}(期望${FIT.elements.length})`);

const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(allRecs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length,
    tabVisible, waxVisible, maxOverflow: +maxOverflow.toFixed(3),
    gradientUntouched: true }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: `675 straight ticket edges + high-precision design-fit wax seal (${FIT.elements.length} ellipses)`,
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
    for (const n of ['clues.help617', 'clues.help627.hit', ...fitNames]) {
      const a = t.recs.find(q => q.name === n);
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '按钮/热区/渐变被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '675 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '674_票券与火漆重做.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '675_直边票券与火漆精拟合.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    userFeedback: '票券两侧做直（6 枚椭圆反而降低观感）；火漆先不考虑省图元，高精度按设计图拟合',
    ticket: { straight: true, main: [160, 66], outline: [166, 72],
      hiddenEdgeLayers: 16, gradient: '23 枚 672 拟合三角逐字节零改动', visibleLayers: tabVisible },
    wax: {
      method: '逐 5° 提取设计稿外缘半径 R(θ)；主体 214 枚按「可见环带中心」取设计稿 5×5 的 90 分位色（16 级红阶）、外→内 7 层密网格；另 26 枚按水平剖面实测 r≈42 补 #D70601 高光峰',
      designFile: FIT.design.file, mapping: FIT.mapping,
      outlineSamples: FIT.outline.samples, outlineRadius: FIT.outline.realRadius,
      colorLevels: [...new Set(FIT.elements.map(e => e.color))].sort(),
      elements: FIT.elements.length, maxOverflow: +maxOverflow.toFixed(3),
      visibleLayers: waxVisible,
    },
    gates: { gradientUntouched: true, maxOverflow: +maxOverflow.toFixed(3),
      tabVisible, waxVisible, added: added.length, hidden: hidden.length },
    untouched: '23 枚渐变三角、问号与热区、内嵌 Lua、26 条文本、线索卡 671/672 成果、v19 背景子树、clue 模板 childList 均逐字节不变；旧 50 条 wax 记录全部隐藏（不删除）。',
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, removed: 0, hidden: hidden.length, modified: modified.length },
  visibleLayers: { tabBefore: 33, tabAfter: tabVisible, waxBefore: 21, waxAfter: waxVisible },
  addedNames: added.map(r => r.name),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '675_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length,
  tabVisible, waxVisible, maxOverflow: +maxOverflow.toFixed(3),
  scriptBytes: scriptBefore.length, status: 'APPLIED' }, null, 2));
