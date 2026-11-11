// 658 结构校验：与 657改.gil 逐记录比对
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '657改.gil'));
const B = readGil(path.join(DIR, '658_关卡内UI.gil'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));

function descendants(g, rootName) {
  const byParent = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byParent.has(k)) byParent.set(k, []); byParent.get(k).push(r.id); }
  const root = g.recs.find(r => r.name === rootName); if (!root) return [];
  const out = new Set([root.id]), q = [root.id];
  while (q.length) for (const c of byParent.get(q.shift()) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v12')), bgB = new Set(descendants(B, 'police-v12'));
const bgChanged = changed.filter(id => bgA.has(id) || bgB.has(id));
const bgAdded = added.filter(id => bgB.has(id));
const bgRemoved = removed.filter(id => bgA.has(id));
const scriptIdentical = findScriptLeaf(A).buf.equals(findScriptLeaf(B).buf);

function hidden(r) {
  const walk = f => { if (!f.sub) return false;
    if (f.field === 17 && f.wt === 2 && f.sub && f.sub.some(x => x.field === 503 && Number(x.num) === 1)) return true;
    return f.sub.some(walk); };
  return (r.field.sub || []).some(walk);
}
const A657 = JSON.parse(fs.readFileSync(path.join(DIR, '657_构建审计.json'), 'utf8'));
const A658 = JSON.parse(fs.readFileSync(path.join(DIR, '658_构建审计.json'), 'utf8'));
const hiddenNames = [...(A657.hidden || []), ...(A658.hidden || [])];
const hiddenAllEffective = hiddenNames.every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });

const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const newRecs = added.map(id => mb.get(id));
const allowedParents = new Set(['grp653.static.1.art641.game', 'clues', 'root', 'clue',
  'art658.help.tab.clip', 'art658.ribbon.clip']);
const wrongParent = newRecs.filter(r => !allowedParents.has(mb.get(r.parentId)?.name) && !/^art658\..*\.clip$/.test(mb.get(r.parentId)?.name || '')).map(r => r.name);
let orderOk = true;
for (const pid of new Set(newRecs.map(r => r.parentId))) {
  const p = mb.get(pid), cl = findChildListTop(p?.field?.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []).filter(id => order.has(id)) : [];
  if (ids.some((id, i) => i > 0 && order.get(ids[i - 1]) > order.get(id))) orderOk = false;
}
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
const num = (r, k) => { const p = (f, ks) => ks.reduce((a, x) => a.flatMap(y => (y.sub || []).filter(z => z.field === x)), [f]);
  const ip = p(r.field, [505, 503, 84])[0]; const f = ip?.sub?.find(q => q.field === k && q.wt === 0); return f ? Number(f.num) : null; };
const help = B.recs.find(r => r.name === 'clues.help617');
const helpMaterialRestored = !!help && num(help, 502) === 0xffffffff && num(help, 503) === 100113;
const selfDrawnHidden = ['art657.game.sticker.q.dot', 'art657.game.sticker.q.mark']
  .every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });
const slotsHidden = Array.from({ length: 5 }, (_, i) => `art657.game.notebook.slot.${i + 1}`)
  .every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });
// 旗面按选关尺寸：submit/redo/undo/hint 应为 134.6x79.2，back 为 139.2x79.2*0.78
const flagSizes = {};
for (const k of ['back', 'submit', 'redo', 'undo', 'hint']) {
  const r = B.recs.find(q => q.name === 'art641.game.flag.' + k);
  flagSizes[k] = r ? [+geom(r)[2].toFixed(1), +geom(r)[3].toFixed(1)] : null;
}
const sizeOk = ['submit', 'redo', 'undo', 'hint'].every(k => Math.abs(flagSizes[k][0] - 134.6) < 0.5 && Math.abs(flagSizes[k][1] - 79.2) < 0.5);
// 两套 clue 模板各 5 层新渐变
const tplNew = [1073742421, 1073742428].map(id => B.recs.filter(r => r.parentId === id && /^art658\.clue/.test(r.name || '')).length);
const clipCount = B.recs.filter(r => /\.clip$/.test(r.name || '')).length;

const keys = ['root', 'home', 'stage', 'board.bg', 'clues', 'clues.grid', 'clues.help617', 'clues.help627.hit',
  'police-v12', 'hex.back', 'hex.hint', 'hit.hint', 'art641.game.help.tab', 'art657.grid.reuse'];
const missing = keys.filter(n => !B.recs.some(r => r.name === n));
const report = {
  base: '657改.gil', output: '658_关卡内UI.gil',
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changedExisting: changed.length,
  policeV12: { descendantsBefore: bgA.size, descendantsAfter: bgB.size,
    changed: bgChanged.length, added: bgAdded.length, removed: bgRemoved.length,
    untouched: bgChanged.length + bgAdded.length + bgRemoved.length === 0 },
  script: { identical: scriptIdentical, bytes: findScriptLeaf(B).buf.length },
  hiddenRecords: { count: hiddenNames.length, allEffective: hiddenAllEffective },
  sixPoints: {
    p1_hintMaterialRestored: helpMaterialRestored, p1_selfDrawnHidden: selfDrawnHidden,
    p2_flagSizesFromSelect: sizeOk, p2_flagSizes: flagSizes,
    p3_ticketGradientClip: clipCount >= 2, p3_clipCount: clipCount,
    p4_clueTemplateLayers: tplNew, p4_templateLayersOk: tplNew.every(n => n === 5),
    p5_clippedGradientUsed: clipCount >= 2,
    p6_blackSlotsHidden: slotsHidden,
  },
  newLayers: { count: newRecs.length, wrongParent, childListFollowsRecordOrder: orderOk },
  keyControlsMissing: missing,
  verdict: (bgChanged.length + bgAdded.length + bgRemoved.length === 0) && scriptIdentical
    && removed.length === 0 && missing.length === 0 && wrongParent.length === 0 && orderOk
    && hiddenAllEffective && helpMaterialRestored && selfDrawnHidden && slotsHidden && sizeOk
    && tplNew.every(n => n === 5) && clipCount >= 2,
};
fs.writeFileSync(path.join(DIR, '658_结构校验.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (!report.verdict) process.exitCode = 1;
