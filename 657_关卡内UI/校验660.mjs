// 660 结构校验：与 659_关卡内UI.gil 逐记录比对，并逐项断言本轮四项重做
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '659_关卡内UI.gil'));
const B = readGil(path.join(DIR, '660_关卡内UI.gil'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));

function descendants(g, rootName) {
  const byParent = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byParent.has(k)) byParent.set(k, []); byParent.set(k, [...(byParent.get(k) || []), r.id]); }
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
const audits = ['657', '658', '659', '660'].map(v =>
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

// ① 注释票券：旧 3 段色带隐藏；描边/亮矩形/斜边三角/补漏/撕齿齐全；问号与热区不变
const oldBandsHidden = [...Array(3)].every((_, i) => {
  const r = named(`art659.help.tab.band${i + 1}`); return r && hidden(r);
});
const tabLayers = ['art660.tab.outline', 'art660.tab.light.rect', 'art660.tab.light.tri',
  'art660.tab.light.patch1', 'art660.tab.light.patch2', 'art641.game.help.tab'];
const tabLayersPresent = tabLayers.every(n => !!named(n));
const tabTri = named('art660.tab.light.tri');
const nsField = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const fieldNum = (p, k) => { const z = p?.sub?.find(q => q.field === k && q.wt === 0); return z ? Number(z.num) : null; };
const tabTriIsRotatedTriangle = !!tabTri
  && fieldNum(nsField(tabTri.field, [505, 503, 84])[0], 503) === 100003
  && Math.abs(tabTriRot()) > 5;
function tabTriRot() {
  const st = stateBlocks(tabTri.field.sub, [])[0];
  return st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
}
const helpIconUntouched = enc(named('clues.help617')) === enc(ma.get(named('clues.help617').id));
const hitUntouched = enc(named('clues.help627.hit')) === enc(ma.get(named('clues.help627.hit').id));
const notchCount = B.recs.filter(r => /^art660\.tab\.notch\./.test(r.name || '') && !hidden(r)).length;
const tipCount = B.recs.filter(r => /^art660\.tab\.tip\./.test(r.name || '') && !hidden(r)).length;

// ② 燕尾旗胶带：旧 3 段色带隐藏、V 凹口三角保留且同步到新右端、亮斜三角存在
const oldRibBandsHidden = [...Array(3)].every((_, i) => {
  const r = named(`art659.ribbon.band${i + 1}`); return r && hidden(r);
});
const ribTri = named('art660.ribbon.light.tri');
const ribV = ['art657.game.notebook.ribbon.tri.top', 'art657.game.notebook.ribbon.tri.bottom']
  .map(n => geom(named(n)));
const ribVSync = ribV.every(g => g && Math.abs(g[0] - 504.5) < 3);

// ③ 新渐变法：旋转三角落在目标矩形内（零溢出），不依赖任何 clip 容器
const clipVisible = B.recs.filter(r => /\.clip$/.test(r.name || '') && !hidden(r)).map(r => r.name);
const rotatedVisible = B.recs.filter(r => /^art660\..*\.tri$/.test(r.name || '') && !hidden(r));
// 零溢出判据：压矮等腰三角的三个顶点必须落在各自目标矩形内（包围盒对尖三角过严）。
// 100003 局部顶点 (0,-h/2)、(-w/2,h/2)、(w/2,h/2)，渲染器按 rotate(-rot) 变换。
const rotatedInBounds = rotatedVisible.every(r => {
  const g = geom(r); if (!g) return false;
  const st = stateBlocks(r.field.sub, [])[0];
  const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  const a = -rot * Math.PI / 180, w = g[2], h = g[3];
  const pts = [[0, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]]
    .map(([x, y]) => [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)]);
  const lim = /^art660\.tab\./.test(r.name) ? [75, 45]
    : /^art660\.ribbon\./.test(r.name) ? [47, 31] : [167, 45];
  return pts.every(([x, y]) => Math.abs(x) <= lim[0] + 2 && Math.abs(y) <= lim[1] + 2);
});

// ④ 线索区三层背景：旧 87 层正交带隐藏；倾斜格纹纸 + 褐色封面 + 白框
const oldGridHidden = B.recs.filter(r => /^art659\.clues\.grid\./.test(r.name || '')).every(hidden);
const gridLayers = B.recs.filter(r => /^art660\.clues\.grid\./.test(r.name || '') && !hidden(r));
const gridRotConsistent = gridLayers.length > 10 && gridLayers.every(r => {
  const st = stateBlocks(r.field.sub, [])[0];
  const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return Math.abs(rot + 5.2) < 0.01;
});
const coverPresent = !!named('art660.clues.cover');
const dashLayers = B.recs.filter(r => /^art660\.clues\.cover\.dash\./.test(r.name || '') && !hidden(r)).length;
const frameG = geom(named('art657.game.notebook.frame'));
const frameResized = frameG && Math.abs(frameG[2] - 396) < 1 && Math.abs(frameG[3] - 515) < 1;

// ⑤ 模板内渐变：两套各 4 层，白线之后画
const tplLayers = [1, 2].map(i => B.recs.filter(r =>
  new RegExp(`^art660\\.clue${i}\\.`).test(r.name || '') && !hidden(r)).length);
const tplOk = tplLayers.every(n => n === 5);

// ⑥ 层序同序 / 关键控件齐全
const recTop = B.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
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
  && keyControlsMissing.length === 0 && orderOk && hiddenAllEffective
  && oldBandsHidden && oldRibBandsHidden && oldGridHidden
  && tabLayersPresent && tabTriIsRotatedTriangle && helpIconUntouched && hitUntouched
  && notchCount === 4 && tipCount === 4
  && ribVSync && !!ribTri
  && clipVisible.length === 0 && rotatedInBounds
  && gridRotConsistent && coverPresent && dashLayers === 38 && frameResized
  && tplOk;

const out = {
  base: '659_关卡内UI.gil', output: '660_关卡内UI.gil',
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changedExisting: changed.length,
  policeV12: { descendantsBefore: bgA.size, descendantsAfter: bgB.size, changed: bgChanged.length,
    untouched: bgChanged.length === 0 },
  script: { identical: scriptIdentical, bytes: findScriptLeaf(B).buf.length },
  hiddenRecords: { count: hiddenNames.length, allEffective: hiddenAllEffective },
  fixes: {
    p1_noteTicket: { oldBandsHidden, tabLayersPresent, tabTriIsRotatedTriangle,
      notchCount, tipCount, helpIconUntouched, hitUntouched },
    p2_swallowRibbon: { oldRibBandsHidden, ribTriPresent: !!ribTri, ribV: ribV.map(g => g && +g[0].toFixed(1)), ribVSync },
    p3_gradientMethod: { visibleClipContainers: clipVisible, rotatedTriangles: rotatedVisible.map(r => r.name),
      rotatedInBounds },
    p4_clueBackground: { oldGridHidden, gridLayers: gridLayers.length, gridRotConsistent,
      coverPresent, dashLayers, frame: frameG && frameG.map(v => +v.toFixed(1)), frameResized },
    p5_templateGradient: { layersPerTemplate: tplLayers, expected: 5, ok: tplOk },
  },
  childListFollowsRecordOrder: orderOk,
  keyControlsMissing,
  verdict,
};
fs.writeFileSync(path.join(DIR, '660_结构校验.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify(out, null, 2));
if (!verdict) process.exitCode = 1;
