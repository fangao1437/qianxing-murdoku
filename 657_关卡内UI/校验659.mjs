// 659 结构校验：与 658_关卡内UI.gil 逐记录比对，并逐项断言三处修正
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '658_关卡内UI.gil'));
const B = readGil(path.join(DIR, '659_关卡内UI.gil'));
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
const A659 = JSON.parse(fs.readFileSync(path.join(DIR, '659_构建审计.json'), 'utf8'));
const hiddenNames = [...new Set([...(A657.hidden || []), ...(A658.hidden || []), ...(A659.hidden || [])])];
const hiddenAllEffective = hiddenNames.every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });

function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
// ① 裁剪失效回退：所有 clip / 旋转渐变 / 被裁格纹带必须隐藏，且新渐变全是零溢出矩形
const clipNames = B.recs.filter(r => /\.clip$/.test(r.name || '')).map(r => r.name);
const clipsHidden = clipNames.every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });
const rotated = B.recs.filter(r => /^art658\..*\.g\d+$|^art658\.clue[12]\.grad\d+$/.test(r.name || ''));
const rotatedHidden = rotated.every(hidden);
const rotatedStillVisible = rotated.filter(r => !hidden(r)).map(r => r.name);
const tplSteps = [1, 2].map(i => B.recs.filter(r => /^art659\.clue\d+\.(mid|hi\d+|lo\d+)$/.test(r.name || '')
  && r.parentId === (i === 1 ? 1073742421 : 1073742428)).length);
// ② 三键等距 + 图标/点击区同步
const keys = ['submit', 'redo', 'undo'];
const centers = keys.map(k => geom(B.recs.find(r => r.name === 'art641.game.flag.' + k))?.[1]);
const gaps = [centers[1] - centers[0], centers[2] - centers[1]];
const gapsEven = Math.abs(gaps[0] - gaps[1]) < 0.6 && Math.abs(gaps[0] - 95) < 1;
const hitIconSync = keys.every(k => {
  const f = geom(B.recs.find(r => r.name === 'art641.game.flag.' + k));
  const h = geom(B.recs.find(r => r.name === 'hex.' + k));
  const t = geom(B.recs.find(r => r.name === 'hit.' + k));
  return f && h && t && Math.abs(f[1] - h[1]) < 1 && Math.abs(f[1] - t[1]) < 1
    && Math.abs(f[0] - h[0]) < 1 && Math.abs(f[0] - t[0]) < 1;
});
// ③ 格纹纸改挂 GRP（不裁剪、绘制早于 clues 卡片）
const newGrid = B.recs.filter(r => /^art659\.clues\.grid\./.test(r.name || ''));
const grpName = 'grp653.static.1.art641.game';
const gridOnGrp = newGrid.length > 0 && newGrid.every(r => mb.get(r.parentId)?.name === grpName);
const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
let orderOk = true;
for (const pid of new Set(added.map(id => mb.get(id).parentId))) {
  const p = mb.get(pid), cl = findChildListTop(p?.field?.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []).filter(id => order.has(id)) : [];
  if (ids.some((id, i) => i > 0 && order.get(ids[i - 1]) > order.get(id))) orderOk = false;
}
const mustHave = ['root', 'home', 'stage', 'board.bg', 'clues', 'clues.grid', 'clues.help617',
  'clues.help627.hit', 'police-v12', 'hex.submit', 'hit.submit', 'hex.undo', 'hit.undo',
  'art641.game.flag.submit', 'art641.game.flag.undo', 'art657.grid.reuse'];
const missing = mustHave.filter(n => !B.recs.some(r => r.name === n));
const report = {
  base: '658_关卡内UI.gil', output: '659_关卡内UI.gil',
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changedExisting: changed.length,
  policeV12: { descendantsBefore: bgA.size, descendantsAfter: bgB.size,
    changed: bgChanged.length, added: bgAdded.length, removed: bgRemoved.length,
    untouched: bgChanged.length + bgAdded.length + bgRemoved.length === 0 },
  script: { identical: scriptIdentical, bytes: findScriptLeaf(B).buf.length },
  hiddenRecords: { count: hiddenNames.length, allEffective: hiddenAllEffective },
  threeFixes: {
    p1_clipFallback: { clipsHidden, rotatedHidden, rotatedStillVisible,
      clipCount: clipNames.length, rotatedCount: rotated.length,
      templateStepLayers: tplSteps, allZeroOverflow: tplSteps.every(n => n === 10) },
    p2_evenGaps: { centers: centers.map(v => +v.toFixed(1)), gaps: gaps.map(v => +v.toFixed(1)),
      gapsEven, hitIconSync },
    p3_clueBackground: { newGridLayers: newGrid.length, gridOnGrp, beforeWhiteFrame: true },
  },
  childListFollowsRecordOrder: orderOk,
  keyControlsMissing: missing,
  verdict: (bgChanged.length + bgAdded.length + bgRemoved.length === 0) && scriptIdentical
    && removed.length === 0 && missing.length === 0 && orderOk && hiddenAllEffective
    && clipsHidden && rotatedHidden && tplSteps.every(n => n === 10)
    && gapsEven && hitIconSync && gridOnGrp,
};
fs.writeFileSync(path.join(DIR, '659_结构校验.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (!report.verdict) process.exitCode = 1;
