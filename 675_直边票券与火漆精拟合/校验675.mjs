// 675 结构校验：674 → 675（票券平直边 + 火漆高精度拟合）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/674_票券与火漆重做/674_票券与火漆重做.gil'));
const B = readGil(path.join(DIR, '675_直边票券与火漆精拟合.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '675_构建审计.json'), 'utf8'));
const FIT = JSON.parse(fs.readFileSync(path.join(DIR, '675_火漆图元.json'), 'utf8'));
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
function textOf(r) { const tf = ns(r.field, [505, 503, 75, 510, 501])[0]; return tf?.payload?.toString('utf8') || ''; }
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const allowName = n => /^(art663|art664)\.wax\./.test(n)
  || /^art663\.tab\.(edge|tooth)\./.test(n)
  || ['art661.tab.outline', 'grp653.static.1.art641.game'].includes(n);
const unexpected = changed.filter(id => !allowName(ma.get(id).name || ''))
  .map(id => ma.get(id).name || ('#' + id));
const named = n => B.recs.find(r => r.name === n);
const vis = n => named(n) && !isHiddenRecord(named(n).field);
const near = (v, t) => Math.abs(v - t) < 0.03;
const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
const idOf = (g, f) => g.recs.find(r => r.field === f)?.id;
// 旧记录相对顺序不变（新增层插在锚点前，允许整体插入）
const oldIdsA = rtA.sub.map(f => idOf(A, f)).filter(id => id != null);
const oldIdsB = rtB.sub.map(f => idOf(B, f)).filter(id => ma.has(id));
const orderSame = oldIdsA.length === oldIdsB.length
  && oldIdsA.every((id, i) => id === oldIdsB[i]);
const order = new Map(); rtB.sub.forEach((f, i) => order.set(f, i));
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

// ★ 672 渐变 23 枚三角 + 问号/热区逐字节不变
const fitNames = A.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')).map(r => r.name);
const gradientUntouched = fitNames.length === 23
  && fitNames.every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const helpUntouched = ['clues.help617', 'clues.help627.hit']
  .every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));

// ① 票券两侧平直
const tabEdges = A.recs.filter(r => /^art663\.tab\.(edge|tooth)\./.test(r.name || '')).map(r => r.name);
const straightOk = tabEdges.length === 16 && tabEdges.every(n => !vis(n))
  && near(geom(named('art641.game.help.tab'))[2], 160)
  && near(geom(named('art661.tab.outline'))[2], 166)
  && near(geom(named('art661.tab.outline'))[3], 72);
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const tabVisible = B.recs.filter(r => tabRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;

// ② 火漆拟合层
const oldWax = A.recs.filter(r => /^(art663|art664)\.wax\./.test(r.name || '')).map(r => r.name);
const oldWaxHidden = oldWax.length === 50 && oldWax.every(n => !vis(n));
const newWax = B.recs.filter(r => /^art675\.wax\./.test(r.name || ''));
const seq = newWax.map(r => ({ r, o: order.get(r.field) })).sort((a, b) => a.o - b.o).map(x => x.r);
const waxSeqOk = seq.length === FIT.elements.length && seq.every((r, i) => {
  const e = FIT.elements[i], g = geom(r);
  return r.name === `art675.wax.fit${String(i).padStart(3, '0')}`
    && !isHiddenRecord(r.field) && imgId(r) === 100002
    && imgColor(r) === 'FF' + e.color.slice(1).toUpperCase()
    && near(g[0], e.cx) && near(g[1], e.cy) && near(g[2], e.w) && near(g[3], e.h);
});
const waxVisible = newWax.filter(r => !isHiddenRecord(r.field)).length;
// 零溢出：每个椭圆最远点 ≤ 该角度设计稿外缘 + 0.6
const outline = FIT.outline.realRadius;
let maxOverflow = 0;
FIT.elements.forEach(e => {
  const deg = Math.atan2(e.cy - 342, e.cx - 1326) * 180 / Math.PI;
  const R = outline[Math.round(((deg % 360) + 360) % 360 / 5) % outline.length];
  maxOverflow = Math.max(maxOverflow, Math.hypot(e.cx - 1326, e.cy - 342) + e.w / 2 - R);
});

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  oldRecordOrderSame: orderSame, childListOk, dangling,
  gradientUntouched, fitCount: fitNames.length, helpUntouched,
  ticket: { straightOk, hiddenEdgeLayers: tabEdges.length, visibleLayers: tabVisible,
    mainGeom: geom(named('art641.game.help.tab')).map(v => +v.toFixed(2)),
    outlineGeom: geom(named('art661.tab.outline')).map(v => +v.toFixed(2)) },
  wax: { oldWaxHidden, oldWaxCount: oldWax.length,
    newLayers: newWax.length, visibleLayers: waxVisible, waxSeqOk,
    maxOverflow: +maxOverflow.toFixed(3), designOutline: [+Math.min(...outline).toFixed(2), +Math.max(...outline).toFixed(2)],
    colorLevels: [...new Set(FIT.elements.map(e => e.color))].sort() },
  gates: audit.spec.gates,
};
checks.verdict = removed.length === 0 && added.length === FIT.elements.length
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && orderSame && childListOk && dangling === 0
  && gradientUntouched && helpUntouched
  && tabVisible === 25 && straightOk
  && oldWaxHidden && waxVisible === FIT.elements.length && waxSeqOk && maxOverflow <= 0.6;
fs.writeFileSync(path.join(DIR, '675_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length, unexpected,
  scriptIdentical, textChanged: textChanged.length, bgChanged: bgChanged.length,
  oldRecordOrderSame: orderSame, childListOk, dangling, gradientUntouched, helpUntouched,
  ticket: checks.ticket, wax: checks.wax }, null, 2));
if (!checks.verdict) process.exitCode = 1;
