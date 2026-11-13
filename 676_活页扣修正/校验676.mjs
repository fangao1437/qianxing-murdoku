// 676 结构校验：675 → 676（活页扣按设计稿重拟合 + 装订边收窄 + 去黄虚线）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/675_直边票券与火漆精拟合/675_直边票券与火漆精拟合.gil'));
const B = readGil(path.join(DIR, '676_活页扣修正.gil'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '676_活页扣图元.json'), 'utf8'));
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
const allowName = n => /^art663\.ring\./.test(n)
  || /^art658\.clues\.binding(\.dash\d+)?$/.test(n)
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

// ★ 675 全部成果逐字节不变（票券 25 层 / 火漆 240 层 / 672 渐变 23 枚 / 问号热区）
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const waxRegex = /^art675\.wax\./;
const keep675 = A.recs.filter(r => tabRegex.test(r.name || '') || waxRegex.test(r.name || '')
  || /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')
  || ['clues.help617', 'clues.help627.hit'].includes(r.name)).map(r => r.name);
const prev675Untouched = keep675.every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const fitNames = keep675.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n));
const gradientUntouched = fitNames.length === 23;
const helpUntouched = ['clues.help617', 'clues.help627.hit']
  .every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const tabVisible = B.recs.filter(r => tabRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;
const waxVisible = B.recs.filter(r => waxRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;

// ① 黄虚线与旧环全部隐藏
const dashNames = A.recs.filter(r => /^art658\.clues\.binding\.dash\d+$/.test(r.name || '')).map(r => r.name);
const oldRingNames = A.recs.filter(r => /^art663\.ring\./.test(r.name || '')).map(r => r.name);
const dashesHidden = dashNames.length === 12 && dashNames.every(n => !vis(n));
const oldRingsHidden = oldRingNames.length === 20 && oldRingNames.every(n => !vis(n));

// ② 装订边：40 → 24，颜色换成设计稿棕；白纸左界（notebook.frame 未改）保持 x=24
const bindingGeom = geom(named('art658.clues.binding'));
const BND = SPEC.binding;
const bindingOk = near(bindingGeom[0], BND.centerX) && near(bindingGeom[1], BND.centerY)
  && near(bindingGeom[2], BND.width) && near(bindingGeom[3], BND.height)
  && imgColor(named('art658.clues.binding')) === 'FF' + BND.color.slice(1).toUpperCase();
const frameGeom = geom(named('art657.game.notebook.frame'));
const frameLeft = frameGeom[0] - frameGeom[2] / 2;
const frameUntouched = enc(named('art657.game.notebook.frame')) === enc(A.recs.find(r => r.name === 'art657.game.notebook.frame'));
const paperLeftOk = near(frameLeft, SPEC.measurement.paperLeftX) && frameUntouched;
const mid = named('art676.binding.mid');
const midOk = !!mid && !isHiddenRecord(mid.field)
  && near(geom(mid)[2], BND.midBand.width) && imgColor(mid) === 'FF' + BND.midBand.color.slice(1).toUpperCase();

// ③ 新活页扣 42 层：层序/几何/颜色/图片类型/旋转与拟合规格逐条一致
const newRings = B.recs.filter(r => /^art676\.ring\./.test(r.name || ''));
const seq = newRings.map(r => ({ r, o: order.get(r.field) })).sort((a, b) => a.o - b.o).map(x => x.r);
const ringSeqOk = seq.length === SPEC.elements.length && seq.every((r, i) => {
  const e = SPEC.elements[i], gm = geom(r);
  return r.name === e.name && !isHiddenRecord(r.field)
    && imgId(r) === (e.img || 100002)
    && imgColor(r) === 'FF' + e.color.slice(1).toUpperCase()
    && near(gm[0], e.cx) && near(gm[1], e.cy) && near(gm[2], e.w) && near(gm[3], e.h)
    && Math.abs(rotOf(r) - (e.rot || 0)) < 0.03;
});
const ringVisible = newRings.filter(r => !isHiddenRecord(r.field)).length;
const maxRight = Math.max(...SPEC.elements.map(e => e.cx + e.w / 2));
const centers = SPEC.measurement.centers;
const stepOk = Math.abs((centers[5] - centers[0]) / 5 - SPEC.measurement.step) < 0.1 && centers.length === 6;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  oldRecordOrderSame: orderSame, childListOk, dangling,
  previous675: { untouched: prev675Untouched, checked: keep675.length,
    gradientUntouched, fitCount: fitNames.length, helpUntouched, tabVisible, waxVisible },
  binding: { ok: bindingOk, geom: bindingGeom.map(v => +v.toFixed(2)), color: imgColor(named('art658.clues.binding')),
    before: [20, 513.5, 40, 535, 'FF2E1A12'], paperLeft: frameLeft, paperLeftOk, midBandOk: midOk },
  rings: { oldRingsHidden, oldCount: oldRingNames.length, dashesHidden, dashCount: dashNames.length,
    newLayers: newRings.length, visibleLayers: ringVisible, ringSeqOk,
    centers, step: +((centers[5] - centers[0]) / 5).toFixed(2), stepOk,
    maxRight, colors: [...new Set(SPEC.elements.map(e => e.color))].sort() },
};
checks.verdict = removed.length === 0 && added.length === SPEC.elements.length + 1
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && orderSame && childListOk && dangling === 0
  && prev675Untouched && gradientUntouched && helpUntouched && tabVisible === 25 && waxVisible === 240
  && dashesHidden && oldRingsHidden && bindingOk && paperLeftOk && midOk
  && ringVisible === SPEC.elements.length && ringSeqOk && stepOk && maxRight <= 36.5;
fs.writeFileSync(path.join(DIR, '676_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  unexpected: unexpected.length, scriptIdentical, textChanged: textChanged.length,
  bgChanged: bgChanged.length, orderSame, childListOk, dangling,
  prev675Untouched, tabVisible, waxVisible, dashesHidden, oldRingsHidden,
  bindingOk, paperLeftOk, midOk, ringVisible, ringSeqOk, maxRight }, null, 2));
if (!checks.verdict) process.exit(2);
