// 678 结构校验：677 → 678（注释卡几何真缺口 + 去掉环末端小椭圆）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/677_活页扣孔与八环/677_活页扣孔与八环.gil'));
const B = readGil(path.join(DIR, '678_注释卡真缺口.gil'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '678_注释卡图元.json'), 'utf8'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));
function descendants(g, n) {
  const byP = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byP.has(k)) byP.set(k, []); byP.get(k).push(r.id); }
  const out = new Set(), q = []; const root = g.recs.find(r => r.name === n); if (!root) return [];
  out.add(root.id); q.push(root.id);
  for (let i = 0; i < q.length; i++) for (const c of byP.get(q[i]) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v19'));
const bgChanged = changed.filter(id => bgA.has(id));
const scriptIdentical = findScriptLeaf(A).buf.equals(findScriptLeaf(B).buf);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const ip = r => ns(r.field, [505, 503, 84])[0];
const imgColor = r => ((num(ip(r), 502) ?? 0) >>> 0).toString(16).toUpperCase().padStart(8, '0');
const imgId = r => num(ip(r), 503);
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
function rotOf(r) { return stateBlocks(r.field.sub, [])[0]?.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0; }
function textOf(r) { const tf = ns(r.field, [505, 503, 75, 510, 501])[0]; return tf?.payload?.toString('utf8') || ''; }
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const allowName = n => /^art677\.ring\.\d+\.tipHi$/.test(n)
  || ['art641.game.help.tab', 'art661.tab.outline', 'grp653.static.1.art641.game'].includes(n);
const unexpected = changed.filter(id => !allowName(ma.get(id).name || ''))
  .map(id => ma.get(id).name || ('#' + id));
const named = n => B.recs.find(r => r.name === n);
const vis = n => named(n) && !isHiddenRecord(named(n).field);
const near = (v, t) => Math.abs(v - t) < 0.03;
const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
const idOf = (g, f) => g.recs.find(r => r.field === f)?.id;
const oldIdsA = rtA.sub.map(f => idOf(A, f)).filter(id => id != null);
const oldIdsB = rtB.sub.map(f => idOf(B, f)).filter(id => ma.has(id));
const orderSame = oldIdsA.length === oldIdsB.length && oldIdsA.every((id, i) => id === oldIdsB[i]);
const order = new Map(); rtB.sub.forEach((f, i) => order.set(f, i));
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

// ★ 677 全部既有成果（除 8 条 tipHi 与票券主体/描边）逐字节不变
const keep = A.recs.filter(r => /^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art677\.ring\.)/.test(r.name || '')
  && !SPEC.hidden.tipHi.includes(r.name)
  || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame',
      'art658.clues.binding', 'art676.binding.mid'].includes(r.name)).map(r => r.name);
const prevUntouched = keep.every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const fitNames = keep.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n));
const gradientUntouched = fitNames.length === 23;
const helpUntouched = ['clues.help617', 'clues.help627.hit']
  .every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const waxVisible = B.recs.filter(r => /^art675\.wax\./.test(r.name || '') && !isHiddenRecord(r.field)).length;

// ① 环末端小椭圆全隐藏
const tipHiHidden = SPEC.hidden.tipHi.length === 8 && SPEC.hidden.tipHi.every(n => !vis(n));
const otherRingsKept = B.recs.filter(r => /^art677\.ring\./.test(r.name || '') && !isHiddenRecord(r.field)).length;

// ② 票券主体/描边缩进
const tabGeom = geom(named('art641.game.help.tab')), outGeom = geom(named('art661.tab.outline'));
const M = SPEC.modifyExisting;
const shrinkOk = near(tabGeom[2], M['art641.game.help.tab'].to[2]) && near(tabGeom[3], M['art641.game.help.tab'].to[3])
  && near(outGeom[2], M['art661.tab.outline'].to[2]) && near(outGeom[3], M['art661.tab.outline'].to[3])
  && near(tabGeom[0], 384) && near(tabGeom[1], 211)
  && Math.abs(rotOf(named('art641.game.help.tab')) + 13) < 0.03;

// ③ 24 枚齿：几何/颜色/img/rot/层序逐条一致
const teeth = B.recs.filter(r => /^art678\.tab\./.test(r.name || ''));
const teethSeqOk = teeth.length === SPEC.elements.length && SPEC.elements.every(e => {
  const r = named(e.name); if (!r || isHiddenRecord(r.field)) return false;
  const gm = geom(r);
  return imgColor(r) === 'FF' + e.color.slice(1).toUpperCase()
    && imgId(r) === e.img
    && near(gm[0], e.cx) && near(gm[1], e.cy) && near(gm[2], e.w) && near(gm[3], e.h)
    && Math.abs(rotOf(r) - e.rot) < 0.03;
});
const layerOk = SPEC.elements.every(e => {
  const o = order.get(named(e.name).field);
  return e.layer === 'outline' ? o < order.get(named('art641.game.help.tab').field)
    : o > order.get(named('art641.game.help.tab').field)
      && o < order.get(named('art664.tab.mid.fit01').field);
});
const teethVisible = teeth.filter(r => !isHiddenRecord(r.field)).length;
const Z = SPEC.gates;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  oldRecordOrderSame: orderSame, childListOk, dangling,
  previous: { untouched: prevUntouched, checked: keep.length,
    gradientUntouched, fitCount: fitNames.length, helpUntouched, waxVisible },
  rings: { tipHiHidden, hiddenCount: SPEC.hidden.tipHi.length, otherRingsVisible: otherRingsKept },
  ticket: { shrinkOk, tabGeom: tabGeom.map(v => +v.toFixed(2)), outlineGeom: outGeom.map(v => +v.toFixed(2)),
    safety: SPEC.safety, zeroSpur: Z.zeroSpur, mainOutsideOutline: Z.mainOutsideOutline,
    gradOutsideMain: Z.gradOutsideMain, teeth: teeth.length, teethVisible, teethSeqOk, layerOk,
    colors: [...new Set(SPEC.elements.map(e => e.color))], rots: [...new Set(SPEC.elements.map(e => e.rot))].sort((a, b) => a - b) },
};
checks.verdict = removed.length === 0 && added.length === SPEC.elements.length
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && orderSame && childListOk && dangling === 0
  && prevUntouched && gradientUntouched && helpUntouched && waxVisible === 240
  && tipHiHidden && otherRingsKept === 64
  && shrinkOk && teethVisible === SPEC.elements.length && teethSeqOk && layerOk
  && Z.zeroSpur && Z.mainOutsideOutline === 0 && Z.gradOutsideMain === 0;
fs.writeFileSync(path.join(DIR, '678_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  unexpected: unexpected.length, scriptIdentical, textChanged: textChanged.length,
  bgChanged: bgChanged.length, orderSame, childListOk, dangling,
  prevUntouched, gradientUntouched, waxVisible, tipHiHidden, otherRingsKept,
  shrinkOk, teethVisible, teethSeqOk, layerOk, zeroSpur: Z.zeroSpur }, null, 2));
if (!checks.verdict) process.exit(2);
