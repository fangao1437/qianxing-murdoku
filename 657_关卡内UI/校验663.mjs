// 663 结构校验：662v19.gil → 663_关卡内UI.gil 逐记录比对 + 五项验收断言
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '662v19.gil'));
const B = readGil(path.join(DIR, '663_关卡内UI.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '663_构建审计.json'), 'utf8'));
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
const audits = ['657', '658', '659', '660', '661', '663'].map(v =>
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
function rotOf(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  return st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
}
const recTop = B.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });

// ── 变更白名单：审计里 modified/hidden 的现有记录 + 两个 childList 父容器 ──
const allowed = new Set();
for (const n of [...audit.modified, ...audit.hidden]) {
  const r = ma.get([...ma.values()].find(q => q.name === n)?.id);
  if (r) allowed.add(r.id);
}
const parentNames = ['grp653.static.1.art641.game', 'art657.grid.reuse'];
for (const n of parentNames) { const r = B.recs.find(q => q.name === n); if (r) allowed.add(r.id); }
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));

// ① 票券
const t = geom(named('art641.game.help.tab'));
const tOutline = geom(named('art661.tab.outline'));
const tabOk = t && Math.abs(t[2] - 140) < 0.5 && Math.abs(t[3] - 66) < 0.5
  && tOutline && Math.abs(tOutline[2] - 146) < 0.5 && Math.abs(tOutline[3] - 72) < 0.5
  && color(named('art641.game.help.tab')) === '#8B2800'
  && color(named('art661.tab.light.rect')) === '#A83408';
const tabTeeth = B.recs.filter(r => /^art663\.tab\.(edge|tooth)\./.test(r.name || '') && !hidden(r)).length;
const helpUntouched = enc(named('clues.help617')) === enc(ma.get(named('clues.help617').id));
const hitUntouched = enc(named('clues.help627.hit')) === enc(ma.get(named('clues.help627.hit').id));

// ② 活页环
const ringLayers = B.recs.filter(r => /^art663\.ring\./.test(r.name || '') && !hidden(r));
const oldRingsHidden = [1, 2, 3, 4, 5].every(k =>
  hidden(named(`art657.game.notebook.ring.${k}`)) && hidden(named(`art657.game.notebook.ringhole.${k}`)));
const ringOk = ringLayers.length === 20 && oldRingsHidden;

// ③ 白底板 + 第二张网格纸零改动 + 19 条补线
const paperColor = color(named('art641.game.boardframe.paper'));
const shadowColor = color(named('art641.game.boardframe.shadow'));
const oldGrid = A.recs.filter(r => /^art656\.home\.grid\./.test(r.name || ''));
const oldGridUntouched = oldGrid.every(r => enc(r) === enc(mb.get(r.id)));
const oldGridRotPreserved = oldGrid.every(r => Math.abs(rotOf(r) - rotOf(ma.get(r.id))) < 1e-6);
const newGridLines = B.recs.filter(r => /^art663\.grid\.h/.test(r.name || '') && !hidden(r));
const gridLineStepOk = (() => {
  const ys = newGridLines.map(r => geom(r)[1]).sort((a, b) => a - b);
  return ys.length === 19 && ys.every((y, i) => i === 0 || Math.abs((y - ys[i - 1]) - 29.84) < 0.02);
})();
const gridOk = paperColor === '#FDFCE7' && shadowColor === '#FBF3D8'
  && oldGridUntouched && oldGridRotPreserved && gridLineStepOk && newGridLines.length === 19;
// 662 精修的线索区网格纸也必须零改动
const cluesGridUntouched = A.recs.filter(r => /^art661\.clues\.grid\./.test(r.name || ''))
  .every(r => enc(r) === enc(mb.get(r.id)));

// ④ 火漆
const waxLayers = B.recs.filter(r => /^art663\.wax\./.test(r.name || '') && !hidden(r));
const oldPinHidden = ['art657.game.pin.border', 'art657.game.pin', 'art657.game.pin.mid', 'art657.game.pin.hilite']
  .every(n => hidden(named(n)));
const waxOk = waxLayers.length === 28 && oldPinHidden;

// ⑤ 纯色底板
const pageColor = color(named('art657.game.notebook.page'));
const pageOk = pageColor === '#68262A'
  && ['art657.game.notebook.page.mid', 'art657.game.notebook.page.lower',
      'art657.game.notebook.rule.1', 'art657.game.notebook.rule.2',
      'art657.game.notebook.rule.3', 'art657.game.notebook.rule.4'].every(n => hidden(named(n)));

// ⑥ childList 同序 / 关键控件 / 无悬空父 / 可见 clip
let orderOk = true;
for (const pid of new Set(addedIds.map(id => mb.get(id).parentId))) {
  const p = mb.get(pid), cl = findChildListTop(p?.field?.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []).filter(id => order.has(id)) : [];
  if (ids.some((id, i) => i > 0 && order.get(ids[i - 1]) > order.get(id))) orderOk = false;
}
const mustHave = ['root', 'home', 'clues', 'clues.grid', 'clues.help617', 'clues.help627.hit',
  'police-v19', 'art641.game.help.tab', 'art641.game.boardframe.paper',
  'art657.game.notebook.page', 'art657.grid.reuse', 'grp653.static.1.art641.game'];
const keyControlsMissing = mustHave.filter(n => !named(n));
const dangling = B.recs.filter(r => r.parentId != null && !mb.has(r.parentId) && !A.recs.some(q => q.id === r.id && q.parentId != null && !ma.has(q.parentId))).length;
const clipVisible = B.recs.filter(r => /\.clip$/.test(r.name || '') && !hidden(r)).length;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: addedIds.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  hiddenNamesAccumulated: hiddenNames.length, hiddenAllEffective,
  tabOk, tabTeeth, helpUntouched, hitUntouched,
  ringOk, ringLayers: ringLayers.length, oldRingsHidden,
  gridOk, paperColor, shadowColor, oldGridUntouched, oldGridRotPreserved,
  newGridLines: newGridLines.length, gridLineStepOk, cluesGridUntouched,
  waxOk, waxLayers: waxLayers.length, oldPinHidden,
  pageOk, pageColor,
  orderOk, keyControlsMissing, dangling, clipVisible,
};
checks.verdict = removed.length === 0 && bgChanged.length === 0 && scriptIdentical
  && hiddenAllEffective && orderOk && keyControlsMissing.length === 0 && dangling === 0
  && clipVisible === 0 && unexpected.length === 0
  && tabOk && tabTeeth === 16 && helpUntouched && hitUntouched
  && ringOk && gridOk && cluesGridUntouched && waxOk && pageOk;
fs.writeFileSync(path.join(DIR, '663_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify(checks, null, 2));
if (!checks.verdict) process.exitCode = 1;
