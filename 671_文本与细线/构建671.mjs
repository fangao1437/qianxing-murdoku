// 671 · 修文本遮挡 + 两条细线 + 模板图元极简化
//
// 670 实机三个问题：
//  ① 文本被盖：art670.* 64 层插在 who 之前，但 letter(73)/what(74)/face(75) 比 who(108) 更早，
//     所以只有 who 可见，正文/字母/头像全被渐变盖住。
//  ② 上方浅红竖细线：art670.clueN.s250 的 fillRegion① 安全矩形右边界 xb≈804，
//     与三角斜边之间形成一条竖直硬边（#70272E 略亮）。
//  ③ 左下角深红细线溢出：fillRegion③ 的补漏矩形在左下角越出 324×79.4 边界。
//
// 用户要求「优化线索模板控件数量，不破坏效果下追求最少图元」——
// 不再修补拼接，直接改用 100003 等腰直角三角的原生斜边做分界：
//   backrop1 (330×85.4 #56565E 染色区)
//     → backrop2 (324×79.4 #68262A 主枣红，整卡铺满，红色就放在 backrop2)
//     → art671.clueN.hi  1 枚 100003 #9D3033 左上亮红直角三角
//     → art671.clueN.lo  1 枚 100003 #611F23 右下暗红直角三角
//     → 文字/头像
// 每套模板视觉层从 32 层降到 4 层（含两个 backrop），新增仅 2 层/模板。
// 三角顶点全部严格落在 324×79.4 内，边缘由 backrop2 矩形给出 ⇒ 零溢出、平直、不漏底色、无缝隙细线。
//
// 基准：670_渐变收敛.gil
// 输出：671_文本与细线.gil + 671_构建审计.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/671_文本与细线');
const INPUT = path.join(ROOT, 'qianxing-murdoku/670_渐变收敛/670_渐变收敛.gil');
const OUTPUT = path.join(DIR, '671_文本与细线.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const DRY = process.argv.includes('--dry');

const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf,
  findChildListTop, asIdList, setChildList } =
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
const origIds = new Set(g.recs.map(r => r.id));
const origParent = new Map(g.recs.map(r => [r.id, r.parentId]));
const danglingBefore = new Set([...origIds].filter(id =>
  origParent.get(id) != null && !origIds.has(origParent.get(id))));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
function screenGeom(r) {
  const st = states(r)[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
const added = [], hidden = [], touched = new Set(), modified = [];
function touch(r) { touched.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function hide(r) {
  if (isHiddenRecord(r.field)) return;
  setHiddenRecord(r.field, true); hidden.push(r.name); touch(r);
}
function retint(r, hex) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(hex)); setNum(p, 504, 1); touch(r);
}
const PROTO = 'td.home.page.1.help619.icon';
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
let max = BigInt(g.maxId);
function cloneLayer(parent, name, o) {
  const proto = byName.get(o.proto || PROTO);
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  if (parent) f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = (function find(ff) { return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  const idx = recTop.sub.findIndex(q => q === byId.get(o.beforeId)?.field);
  if (idx < 0) throw Error('beforeId 不在 recTop ' + o.beforeId);
  recTop.sub.splice(idx, 0, f);
  const ip = ns(f, [505, 503, 84])[0];
  if (o.color) { setNum(ip, 502, colorOf(o.color)); setNum(ip, 503, o.imageId ?? 100001); setNum(ip, 504, 1); }
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  for (const st of states(r)) {
    setPair(pairOf(st, 504), o.cx - 800, 450 - o.cy);
    setPair(pairOf(st, 505), o.w, o.h);
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: o.rot || 0 }]; rf.payload = null; rf.len = 5;
  }
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}

// ── 100003 等腰直角三角：w=2h、rot=45/225，三顶点严格落在卡片内 ──────────
// 卡片 324×79.4：x638..962 / y410.3..489.7（中心 800,450）
const RECT = { x0: 638, y0: 410.3, x1: 962, y1: 489.7 };
const SIDE = RECT.y1 - RECT.y0;                 // 79.4，两腰长度（不溢出）
const H = SIDE / Math.SQRT2;                    // 56.144
const W = 2 * H;                                // 112.288
const D = H / 2 / Math.SQRT2;                   // 19.85，中心到顶点的 x/y 偏移
const TRIS = [
  { tag: 'hi', color: '#9D3033', rot: 45, cx: RECT.x0 + D, cy: RECT.y0 + D },        // 顶点=左上角
  { tag: 'lo', color: '#611F23', rot: 225, cx: RECT.x1 - D, cy: RECT.y1 - D },       // 顶点=右下角
];
function triVertices(cx, cy, w, h, rot) {
  const a = -rot * Math.PI / 180;
  const loc = [[0, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]];
  return loc.map(([x, y]) => [cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)]);
}
for (const t of TRIS) {
  const v = triVertices(t.cx, t.cy, W, H, t.rot);
  const ok = v.every(([x, y]) => x >= RECT.x0 - 0.01 && x <= RECT.x1 + 0.01
    && y >= RECT.y0 - 0.01 && y <= RECT.y1 + 0.01);
  if (!ok) throw Error(t.tag + ' 三角顶点溢出卡片：' + JSON.stringify(v));
  t.vertices = v.map(p => p.map(n => +n.toFixed(2)));
}

const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (TPL.length !== 2) throw Error('clue 模板数不符：' + TPL.length);
const summary = [];
let n = 0;
for (const root of TPL) {
  n++;
  const kids = g.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const g1 = screenGeom(b1), g2 = screenGeom(b2);
  if (Math.abs(g1[2] - 330) > 0.01 || Math.abs(g2[2] - 324) > 0.01) throw Error('backrop 几何不符');
  // ① 隐藏 670 的 64 层拼接渐变（浅红竖线 / 左下深红溢出的来源）
  const old = kids.filter(r => /^art670\.clue/.test(r.name || ''));
  if (old.length !== 32) throw Error('670 渐变层数不符：' + old.length);
  for (const r of old) hide(r);
  // ② 红色主色直接放在 backrop2（整卡铺满）
  retint(b2, '#68262A');
  // ③ 找最早的「文本/头像」控件，新层必须插在它之前（修复文本被盖）
  const textKids = kids.filter(r => ['who', 'what', 'letter', 'face'].includes(r.name));
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  textKids.sort((a, b) => order.get(a.field) - order.get(b.field));
  const firstText = textKids[0];
  if (!firstText) throw Error('模板缺文本控件：' + root.id);
  for (const t of TRIS)
    cloneLayer(root, `art671.clue${n}.${t.tag}`, {
      cx: t.cx, cy: t.cy, w: W, h: H, rot: t.rot,
      color: t.color, imageId: 100003, beforeId: firstText.id,
    });
  summary.push({ rootId: root.id, hiddenOld: old.length,
    backrop1: [g1[2], g1[3]], backrop2: [g2[2], g2[3]], backrop2Color: 'FF68262A',
    firstText: firstText.name, firstTextOrder: order.get(firstText.field), newLayers: TRIS.length });
}

// ── childList 同步 ──────────────────────────────────────────────────────────
const fieldIndex = new Map(); recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set(added.map(r => r.parentId))) {
  const p = byId.get(pid), cl = findChildListTop(p.field.sub);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids); touch(p);
}

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })(g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE, recordsBefore: beforeBytes.size,
    recordsAfter: expected.size, added: added.length, hidden: hidden.length,
    triangles: TRIS, summary }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '671 minimal 2-triangle clue gradient, text layer order fixed',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touched.has(r.id) && !added.some(a => a.id === r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return '非目标记录被改动 ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const recTop2 = t.tree.find(q => q.field === 9);
    const idx = new Map(); recTop2.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const kids = t.recs.filter(q => q.parentId === root.id);
      const visibleArt = kids.filter(q => /^art671\./.test(q.name || '') && !isHiddenRecord(q.field));
      const texts = kids.filter(q => ['who', 'what', 'letter', 'face'].includes(q.name));
      const firstText = Math.min(...texts.map(q => idx.get(q.field)));
      if (visibleArt.length !== 2) return '新层数量不符 #' + root.id;
      if (visibleArt.some(q => idx.get(q.field) > firstText)) return '渐变层仍在文本之上 #' + root.id;
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '671 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '670_渐变收敛.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '671_文本与细线.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    problem1: '670 的 art670.* 64 层插在 who 之前，但 letter/what/face 比 who 更早 ⇒ 正文/字母/头像被渐变盖住，只剩 who 可见。',
    problem2: 'art670.clueN.s250 的 fillRegion 安全矩形右边界 xb≈804 形成竖直浅红细线；补漏矩形在左下角越界形成深红细线。',
    minimalSolution: '隐藏 64 层拼接渐变；红色主色 #68262A 直接放 backrop2(324×79.4 整卡)；仅新增 2 枚 100003 等腰直角三角(w=2h, rot 45/225) 做左上亮红与右下暗部。每模板视觉层 32→4，新增仅 2 层。',
    geometry: { rect: RECT, side: SIDE, w: +W.toFixed(3), h: +H.toFixed(3), triangles: TRIS.map(t => ({ tag: t.tag, color: t.color, rot: t.rot, cx: +t.cx.toFixed(2), cy: +t.cy.toFixed(2), vertices: t.vertices })) },
    guarantees: '两枚三角顶点全部落在 324×79.4 内（构建时硬校验）⇒ 零溢出、左下无细线；边缘由 backrop2 矩形给出 ⇒ 平直；整卡铺满主色 ⇒ 不漏底色；无补漏矩形/安全矩形 ⇒ 无拼接细线；新层插在最早文本控件之前 ⇒ 文本/头像完整可见。',
    kept: 'backrop1 #FF56565E 染色区、白字、白色底板、内嵌 Lua、26 条文本、v19 背景子树全部保持 670 原样。',
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  visibleLayersPerTemplate: 4, previousVisibleLayersPerTemplate: 32,
  summary, hidden, modified, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '671_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length,
  visibleLayersPerTemplate: 4, scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
