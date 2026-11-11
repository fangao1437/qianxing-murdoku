// 661 结构校验：与 660_关卡内UI.gil 逐记录比对，并断言本轮四项重做
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '660_关卡内UI.gil'));
const B = readGil(path.join(DIR, '661_关卡内UI.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '661_构建审计.json'), 'utf8'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));
function descendants(g, rootName) {
  const byParent = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byParent.has(k)) byParent.set(k, []); byParent.get(k).push(r.id); }
  const out = new Set(), q = [];
  const root = g.recs.find(r => r.name === rootName);
  if (!root) return [];
  out.add(root.id); q.push(root.id);
  for (let i = 0; i < q.length; i++) for (const c of byParent.get(q[i]) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v12')), bgB = new Set(descendants(B, 'police-v12'));
const bgChanged = changed.filter(id => bgA.has(id) || bgB.has(id));
const scriptIdentical = findScriptLeaf(A).buf.equals(findScriptLeaf(B).buf);
function hidden(r) {
  const walk = f => { if (!f.sub) return false;
    if (f.field === 17 && f.wt === 2 && f.sub && f.sub.some(x => x.field === 503 && Number(x.num) === 1)) return true;
    return f.sub.some(walk); };
  return (r.field.sub || []).some(walk);
}
const audits = ['657', '658', '659', '660', '661'].map(v =>
  JSON.parse(fs.readFileSync(path.join(DIR, `${v}_构建审计.json`), 'utf8')));
const hiddenNames = [...new Set(audits.flatMap(a => a.hidden || []))];
const hiddenAllEffective = hiddenNames.every(n => { const r = B.recs.find(q => q.name === n); return r && hidden(r); });
function geom(r) {
  if (!r) return null;
  const st = stateBlocks(r.field.sub, [])[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
const named = n => B.recs.find(r => r.name === n);

// ① 660 本轮视觉层全部隐藏；661 新层全部出现且可见
const old660Hidden = B.recs.filter(r => /^art660\./.test(r.name || '')).every(hidden);
const new661 = B.recs.filter(r => /^art661\./.test(r.name || '') && !hidden(r));
const new661Ok = new661.length >= 150;

// ② 问号本体与点击热区逐字节未动；黑色方格仍隐藏（用户明确不还原）
const helpUntouched = enc(named('clues.help617')) === enc(ma.get(named('clues.help617').id));
const hitUntouched = enc(named('clues.help627.hit')) === enc(ma.get(named('clues.help627.hit').id));
const slotsHidden = [...Array(5)].every((_, i) => { const r = named(`art657.game.notebook.slot.${i + 1}`); return r && hidden(r); });

// ③ 燕尾旗：矩形收成 62×57 @447,346.5；V 凹口两三角 54×28.5 @478；三级色阶存在
const ribG = geom(named('art657.game.notebook.ribbon'));
const ribOk = ribG && Math.abs(ribG[0] - 447) < 1 && Math.abs(ribG[2] - 62) < 1 && Math.abs(ribG[3] - 57) < 1;
const vg = ['art657.game.notebook.ribbon.tri.top', 'art657.game.notebook.ribbon.tri.bottom'].map(n => geom(named(n)));
const vOk = vg.every(g => g && Math.abs(g[0] - 478) < 1 && Math.abs(g[2] - 54) < 1);
const ribBands = ['mid', 'dark'].every(t => new661.some(r => r.name.startsWith(`art661.ribbon.${t}.`)));

// ④ 线索卡两套模板：base + 4 个色阶，且白线在同组最后绘制
const recTop = B.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const tplLayers = [1, 2].map(i => B.recs.filter(r =>
  new RegExp(`^art661\\.clue${i}\\.`).test(r.name || '') && !hidden(r)).length);
const tplOk = tplLayers.every(n => n >= 5);
const ruleAfter = [1, 2].every(i => {
  const rule = named(`art658.clue${i}.rule`);
  const last = Math.max(...B.recs.filter(r => new RegExp(`^art661\\.clue${i}\\.`).test(r.name || ''))
    .map(r => order.get(r.id) ?? -1));
  return last < (order.get(rule.id) ?? 1e9);
});

// ⑤ 三层背景：倾斜格纹纸（纸 + 格线全部同 rot）、褐色封面、38 段尖端虚线、白框
const gridLayers = B.recs.filter(r => /^art661\.clues\.grid\./.test(r.name || '') && !hidden(r));
const gridRotConsistent = gridLayers.length >= 50 && gridLayers.every(r => {
  const st = stateBlocks(r.field.sub, [])[0];
  const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return Math.abs(rot + 6) < 0.01;
});
const dashLayers = B.recs.filter(r => /^art661\.clues\.cover\.dash\./.test(r.name || '') && !hidden(r)).length;
const coverColor = (() => {
  const r = named('art661.clues.cover');
  const nsF = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
  const p = nsF(r.field, [505, 503, 84])[0];
  const z = p?.sub?.find(q => q.field === 502 && q.wt === 0);
  return z ? Number(z.num) & 0xffffff : null;
})();
const frameG = geom(named('art657.game.notebook.frame'));
const frameOk = frameG && Math.abs(frameG[2] - 396) < 1 && Math.abs(frameG[3] - 515) < 1;

// ⑥ 阶梯色阶自检：覆盖率 ≥99%、零溢出、三角旋转角为正
const regionStats = audit.regions || [];
const regionOk = regionStats.length === 10 && regionStats.every(r => r.coverage >= 0.99 && !r.overflow && r.triRot > 0 && r.triRot < 180);
const clipVisible = B.recs.filter(r => /\.clip$/.test(r.name || '') && !hidden(r)).length;

// ⑦ childList 同序 / 关键控件齐全
let orderOk = true;
for (const pid of new Set(added.map(id => mb.get(id).parentId))) {
  const p = mb.get(pid), cl = findChildListTop(p?.field?.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []).filter(id => order.has(id)) : [];
  if (ids.some((id, i) => i > 0 && order.get(ids[i - 1]) > order.get(id))) orderOk = false;
}
const mustHave = ['root', 'home', 'stage', 'board.bg', 'clues', 'clues.grid', 'clues.help617',
  'clues.help627.hit', 'police-v12', 'hex.submit', 'hit.submit', 'hex.undo', 'hit.undo',
  'art641.game.help.tab', 'art657.game.notebook.frame', 'art657.grid.reuse'];
const keyControlsMissing = mustHave.filter(n => !named(n));

const verdict = bgChanged.length === 0 && scriptIdentical && removed.length === 0
  && keyControlsMissing.length === 0 && orderOk && hiddenAllEffective && old660Hidden && new661Ok
  && helpUntouched && hitUntouched && slotsHidden
  && ribOk && vOk && ribBands
  && tplOk && ruleAfter
  && gridRotConsistent && dashLayers === 38 && coverColor !== null && frameOk
  && regionOk && clipVisible === 0;

const out = {
  base: '660_关卡内UI.gil', output: '661_关卡内UI.gil',
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changedExisting: changed.length,
  policeV12: { descendantsBefore: bgA.size, descendantsAfter: bgB.size, changed: bgChanged.length,
    untouched: bgChanged.length === 0 },
  script: { identical: scriptIdentical, bytes: findScriptLeaf(B).buf.length },
  hiddenRecords: { count: hiddenNames.length, allEffective: hiddenAllEffective, art660AllHidden: old660Hidden },
  fixes: {
    p1_threeLayerBackground: { gridLayers: gridLayers.length, gridRotConsistent,
      coverColor: coverColor === null ? null : '#' + coverColor.toString(16).padStart(6, '0'),
      dashLayers, frame: frameG && frameG.map(v => +v.toFixed(1)), frameOk },
    p2_annotationTicket: { helpIconUntouched: helpUntouched, hitUntouched,
      ticketLayers: new661.filter(r => /^art661\.tab\./.test(r.name)).length },
    p3_steppedRibbon: { rib: ribG, ribOk, ribbonVTriangles: vg.map(g => g && g.map(v => +v.toFixed(1))), vOk, ribBands },
    p4_steppedClueCards: { layersPerTemplate: tplLayers, tplOk, ruleAfter },
    p5_v15Method: { regions: regionStats.length, minCoverage: Math.min(...regionStats.map(r => r.coverage)),
      zeroOverflow: regionStats.every(r => !r.overflow),
      triangleRotations: [...new Set(regionStats.map(r => r.triRot))], visibleClipContainers: clipVisible },
    blackSlotsStillHidden: slotsHidden,
  },
  childListFollowsRecordOrder: orderOk,
  keyControlsMissing,
  verdict,
};
fs.writeFileSync(path.join(DIR, '661_结构校验.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify(out, null, 2));
if (!verdict) process.exitCode = 1;
