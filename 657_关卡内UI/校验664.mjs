// 664 结构校验：663 → 664 逐记录比对 + 三项验收断言
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '663_关卡内UI.gil'));
const B = readGil(path.join(DIR, '664_关卡内UI.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '664_构建审计.json'), 'utf8'));
const fit = JSON.parse(fs.readFileSync(path.join(DIR, '664_色阶图元.json'), 'utf8'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const addedIds = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));
function descendants(g, rootName) {
  const byParent = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byParent.has(k)) byParent.set(k, []); byParent.get(k).push(r.id); }
  const out = new Set(), q = [];
  const root = g.recs.find(r => r.name === rootName); if (!root) return [];
  out.add(root.id); q.push(root.id);
  for (let i = 0; i < q.length; i++) for (const c of byParent.get(q[i]) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v19')), bgB = new Set(descendants(B, 'police-v19'));
const bgChanged = changed.filter(id => bgA.has(id) || bgB.has(id));
const scriptIdentical = findScriptLeaf(A).buf.equals(findScriptLeaf(B).buf);
function hidden(r) {
  const walk = f => { if (!f.sub) return false;
    if (f.field === 17 && f.wt === 2 && f.sub && f.sub.some(x => x.field === 503 && Number(x.num) === 1)) return true;
    return f.sub.some(walk); };
  return (r.field.sub || []).some(walk);
}
const audits = ['657', '658', '659', '660', '661', '663', '664'].map(v =>
  JSON.parse(fs.readFileSync(path.join(DIR, `${v}_构建审计.json`), 'utf8')));
const hiddenNames = [...new Set(audits.flatMap(a => a.hidden || []))];
const hiddenAllEffective = hiddenNames.every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });
const named = n => B.recs.find(r => r.name === n);
function geom(r) {
  if (!r) return null;
  const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
function color(r) {
  const nsF = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
  const p = nsF(r?.field, [505, 503, 84])[0];
  const z = p?.sub?.find(q => q.field === 502 && q.wt === 0);
  return z ? '#' + (Number(z.num) & 0xffffff).toString(16).padStart(6, '0').toUpperCase() : null;
}
function rotOf(r) { const st = stateBlocks(r.field.sub, [])[0]; return st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0; }
function imageId(r) {
  const nsF = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
  const p = nsF(r?.field, [505, 503, 84])[0];
  const z = p?.sub?.find(q => q.field === 503 && q.wt === 0);
  return z ? Number(z.num) : null;
}
const recTop = B.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });

// ① tape 真删
const tapeA = A.recs.filter(r => /^art657\.game\.board\.tape\./.test(r.name || ''));
const tapeB = B.recs.filter(r => /^art657\.game\.board\.tape\./.test(r.name || ''));
const grp = named('grp653.static.1.art641.game');
const cl = findChildListTop(grp?.field?.sub || []);
const grpList = cl ? (asIdList(cl.payload, true) || []) : [];
const tapeIds = new Set(tapeA.map(r => r.id));
const tapeGone = tapeA.length === 53 && tapeB.length === 0
  && removed.length === 53 && removed.every(id => tapeIds.has(id))
  && !grpList.some(id => tapeIds.has(id));

// ② 上下对称 + 斜网格纸大小/颜色/角度保留
const INNER_TOP = 107, INNER_BOTTOM = 732;
const paper = geom(named('art641.game.boardframe.paper'));
const gridPaper = geom(named('art656.home.grid.paper'));
// art656.home.grid.* 挂在 art657.grid.reuse 下，真机 sync_art641() 对整组做 (105,−46) 位移
const GRID_DY = -46;
const paperOver = paper ? [INNER_TOP - (paper[1] - paper[3] / 2), (paper[1] + paper[3] / 2) - INNER_BOTTOM] : null;
const gridOver = gridPaper
  ? [INNER_TOP - (gridPaper[1] + GRID_DY - gridPaper[3] / 2),
     (gridPaper[1] + GRID_DY + gridPaper[3] / 2) - INNER_BOTTOM] : null;
const symmetric = paperOver && gridPaper && Math.abs(paperOver[0] - paperOver[1]) < 1.5
  && Math.abs(gridOver[0] - gridOver[1]) < 1.5;
const oldGrid = A.recs.filter(r => /^art656\.home\.grid\./.test(r.name || ''));
const gridPreserved = oldGrid.every(r => {
  const a = ma.get(r.id), b = mb.get(r.id);
  if (!a || !b) return false;
  const ga = geom(a), gb = geom(b);
  return ga && gb && Math.abs(ga[2] - gb[2]) < 1e-6 && Math.abs(ga[3] - gb[3]) < 1e-6
    && Math.abs(rotOf(a) - rotOf(b)) < 1e-6 && color(a) === color(b);
});

// ③ 票券 3 级阶梯 + 撕纸边
const fitLayers = B.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit/.test(r.name || '') && !hidden(r));
const fitRotOk = fitLayers.length === 23 && fitLayers.every(r => { const v = rotOf(r); return v >= 0 && v < 360; });
const fitColorOk = fitLayers.filter(r => color(r) === '#AF3200').length === 14
  && fitLayers.filter(r => color(r) === '#CB4C19').length === 9
  && fitLayers.every(r => imageId(r) === 100003);
const ticketOk = color(named('art641.game.help.tab')) === '#8C2800'
  && color(named('art661.tab.outline')) === '#592520'
  && fitRotOk && fitColorOk
  && fit.steps.every(s => s.verification.coverage === 100 && s.verification.overflowVertices === 0);
const notchCount = B.recs.filter(r => /^art663\.tab\.edge\./.test(r.name || '') && !hidden(r)
  && ['#FDF6DC', '#E7B53C'].includes(color(r))).length;
const toothCount = B.recs.filter(r => /^art663\.tab\.tooth\./.test(r.name || '') && !hidden(r)
  && ['#AF3200', '#8C2800'].includes(color(r))).length;
const edgeOk = notchCount === 8 && toothCount === 8
  && ['art661.tab.light.rect', 'art661.tab.light.tri', 'art661.tab.light.patch1', 'art661.tab.light.patch2']
    .every(n => hidden(named(n)));
const helpUntouched = enc(named('clues.help617')) === enc(ma.get(named('clues.help617').id));
const hitUntouched = enc(named('clues.help627.hit')) === enc(ma.get(named('clues.help627.hit').id));

// ④ 火漆亮环/压印
const waxRing = B.recs.filter(r => /^art664\.wax\.ring\./.test(r.name || '') && !hidden(r));
const waxOk = waxRing.length === 16 && waxRing.every(r => color(r) === '#B40806')
  && color(named('art664.wax.top.lobe')) === '#B40806'
  && color(named('art664.wax.center')) === '#AA0400'
  && color(named('art664.wax.hot.l')) === '#D70601'
  && color(named('art664.wax.hot.r')) === '#D70601'
  && color(named('art664.wax.stamp.rim')) === '#B40806'
  && color(named('art664.wax.stamp.core')) === '#A60400'
  && ['art663.wax.glow.l', 'art663.wax.glow.r', 'art663.wax.inner'].every(n => hidden(named(n)));

// ⑤ childList / 关键控件 / 悬空父 / 白名单
const allowed = new Set();
for (const n of [...audit.modified, ...audit.hidden]) { const r = A.recs.find(q => q.name === n); if (r) allowed.add(r.id); }
allowed.add(grp.id);
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));
let orderOk = true;
for (const pid of new Set([...addedIds.map(id => mb.get(id).parentId), grp.id])) {
  const p = mb.get(pid), c = findChildListTop(p?.field?.sub || []);
  const ids = c ? (asIdList(c.payload, true) || []).filter(id => order.has(id)) : [];
  if (ids.some((id, i) => i > 0 && order.get(ids[i - 1]) > order.get(id))) orderOk = false;
}
const mustHave = ['root', 'clues', 'clues.help617', 'clues.help627.hit', 'police-v19',
  'art641.game.help.tab', 'art641.game.boardframe.paper', 'art656.home.grid.paper',
  'art657.grid.reuse', 'grp653.static.1.art641.game'];
const keyControlsMissing = mustHave.filter(n => !named(n));
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;
const clipVisible = B.recs.filter(r => /\.clip$/.test(r.name || '') && !hidden(r)).length;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: addedIds.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected, scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  hiddenNamesAccumulated: hiddenNames.length, hiddenAllEffective,
  tapeGone, tapeBefore: tapeA.length, tapeAfter: tapeB.length, tapeInChildList: grpList.filter(id => tapeIds.has(id)).length,
  symmetric, paperOver, gridOver, gridPreserved, shifted: audit.counts.shifted,
  ticketOk, fitLayers: fitLayers.length, fitRotOk, fitColorOk, notchCount, toothCount, edgeOk,
  helpUntouched, hitUntouched,
  waxOk, waxRing: waxRing.length,
  orderOk, keyControlsMissing, dangling, clipVisible,
};
checks.verdict = scriptIdentical && bgChanged.length === 0 && hiddenAllEffective
  && unexpected.length === 0 && orderOk && keyControlsMissing.length === 0
  && dangling === 0 && clipVisible === 0
  && tapeGone && symmetric && gridPreserved && audit.counts.shifted === 51
  && ticketOk && edgeOk && helpUntouched && hitUntouched && waxOk;
fs.writeFileSync(path.join(DIR, '664_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify(checks, null, 2));
if (!checks.verdict) process.exitCode = 1;
