// 677 结构校验：676 → 677（8 环 + 孔穿插 + 棕边上下对齐）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/676_活页扣修正/676_活页扣修正.gil'));
const B = readGil(path.join(DIR, '677_活页扣孔与八环.gil'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '677_活页扣图元.json'), 'utf8'));
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
const allowName = n => /^art676\.ring\./.test(n)
  || /^art658\.clues\.binding$/.test(n) || /^art676\.binding\.mid$/.test(n)
  || ['grp653.static.1.art641.game'].includes(n);
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

// ★ 675/676 全部既有成果逐字节不变
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const waxRegex = /^art675\.wax\./;
const keep = A.recs.filter(r => tabRegex.test(r.name || '') || waxRegex.test(r.name || '')
  || /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')
  || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame'].includes(r.name)).map(r => r.name);
const prevUntouched = keep.every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const fitNames = keep.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n));
const gradientUntouched = fitNames.length === 23;
const helpUntouched = ['clues.help617', 'clues.help627.hit']
  .every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const tabVisible = B.recs.filter(r => tabRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;
const waxVisible = B.recs.filter(r => waxRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;

// ① 676 环层全部隐藏
const oldRingNames = A.recs.filter(r => /^art676\.ring\./.test(r.name || '')).map(r => r.name);
const oldRingsHidden = oldRingNames.length === 42 && oldRingNames.every(n => !vis(n));

// ② 棕边/中带与白框上下严格对齐（用户：褐色边上下略有溢出白色底板高度）
const frame = geom(named('art657.game.notebook.frame'));
const binding = geom(named('art658.clues.binding'));
const mid = geom(named('art676.binding.mid'));
const F = SPEC.binding.frame;
const aligned = near(frame[1], F.cy) && near(frame[3], F.h)
  && [binding, mid].every(v => near(v[1], F.cy) && near(v[3], F.h));
const top = binding[1] - binding[3] / 2, bottom = binding[1] + binding[3] / 2;
const topBefore = 513.5 - 535 / 2, bottomBefore = 513.5 + 535 / 2;
const bindingColorKept = imgColor(named('art658.clues.binding')) === 'FF3F1E15';
const paperLeft = frame[0] - frame[2] / 2;
const paperLeftOk = near(paperLeft, 24);

// ③ 8 组 × 9 层：层序、几何、颜色、旋转、孔在环之下
const newRings = B.recs.filter(r => /^art677\.ring\./.test(r.name || ''));
const seq = newRings.map(r => ({ r, o: order.get(r.field) })).sort((a, b) => a.o - b.o).map(x => x.r);
const ringSeqOk = seq.length === SPEC.elements.length && seq.every((r, i) => {
  const e = SPEC.elements[i], gm = geom(r);
  return r.name === e.name && !isHiddenRecord(r.field)
    && imgId(r) === (e.img || 100002)
    && imgColor(r) === 'FF' + e.color.slice(1).toUpperCase()
    && near(gm[0], e.cx) && near(gm[1], e.cy) && near(gm[2], e.w) && near(gm[3], e.h)
    && Math.abs(rotOf(r) - (e.rot || 0)) < 0.03;
});
const holeBelow = SPEC.elements.filter(e => e.kind.startsWith('hole')).every(h =>
  SPEC.elements.filter(e => e.group === h.group && !e.kind.startsWith('hole'))
    .every(r => order.get(named(h.name).field) < order.get(named(r.name).field)));
const ringVisible = newRings.filter(r => !isHiddenRecord(r.field)).length;
const centers = SPEC.detection.centers;
const count8 = centers.length === 8 && SPEC.elements.filter(e => e.kind === 'holeOuter').length === 8;
const stepOk = Math.abs((centers[7] - centers[0]) / 7 - SPEC.detection.step) < 0.1;
const maxRight = Math.max(...SPEC.elements.map(e => e.cx + e.w / 2));

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  oldRecordOrderSame: orderSame, childListOk, dangling,
  previous: { untouched: prevUntouched, checked: keep.length,
    gradientUntouched, fitCount: fitNames.length, helpUntouched, tabVisible, waxVisible },
  binding: { aligned, geom: binding.map(v => +v.toFixed(2)), midGeom: mid.map(v => +v.toFixed(2)),
    frameGeom: frame.map(v => +v.toFixed(2)), top, bottom,
    beforeTop: topBefore, beforeBottom: bottomBefore, colorKept: bindingColorKept,
    paperLeft, paperLeftOk },
  rings: { oldRingsHidden, oldCount: oldRingNames.length,
    newLayers: newRings.length, visibleLayers: ringVisible, ringSeqOk, holeBelow,
    count8, centers, step: +((centers[7] - centers[0]) / 7).toFixed(2), stepOk,
    maxRight, colors: [...new Set(SPEC.elements.map(e => e.color))].sort() },
};
checks.verdict = removed.length === 0 && added.length === SPEC.elements.length
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && orderSame && childListOk && dangling === 0
  && prevUntouched && gradientUntouched && helpUntouched && tabVisible === 25 && waxVisible === 240
  && oldRingsHidden && aligned && bindingColorKept && paperLeftOk
  && ringVisible === SPEC.elements.length && ringSeqOk && holeBelow
  && count8 && stepOk && maxRight <= 38;
fs.writeFileSync(path.join(DIR, '677_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  unexpected: unexpected.length, scriptIdentical, textChanged: textChanged.length,
  bgChanged: bgChanged.length, orderSame, childListOk, dangling,
  prevUntouched, tabVisible, waxVisible, oldRingsHidden, aligned,
  bindingTopBottom: [top, bottom], paperLeft,
  ringVisible, ringSeqOk, holeBelow, count8, step: checks.rings.step, maxRight }, null, 2));
if (!checks.verdict) process.exit(2);
