// 669 结构校验：668 → 669，核对控件位置/层序/颜色/缩放
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/668_线索卡染色/668_线索卡染色.gil'));
const B = readGil(path.join(DIR, '669_旧高亮方案.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '669_构建审计.json'), 'utf8'));
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
const imgColor = r => ((num(ns(r.field, [505, 503, 84])[0], 502) ?? 0) >>> 0).toString(16).toUpperCase();
const textColor = r => ((num(ns(r.field, [505, 503, 75])[0], 504) ?? 0) >>> 0).toString(16).toUpperCase();
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
function textOf(r) { const tf = ns(r.field, [505, 503, 75, 510, 501])[0]; return tf?.payload?.toString('utf8') || ''; }
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const allowed = new Set(audit.modified.flatMap(n => A.recs.filter(q => q.name === n).map(q => q.id)));
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));

const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const tplRoots = B.recs.filter(r => r.name === 'clue' && B.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
const SX = 324 / 330, SY = 79.4 / 85.4;
const tpl = tplRoots.map(root => {
  const kids = B.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const bg = kids.find(r => /^art658\.clue\d+\.bg$/.test(r.name || ''));
  const grad = kids.filter(r => /^(art658\.clue\d+\.bg|art658\.clue\d+\.rule|art661\.clue\d+\.)/.test(r.name || '') && !isHiddenRecord(r.field));
  const g1 = geom(b1), g2 = geom(b2), gb = geom(bg);
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []) : [];
  const ordered = list.filter(id => mb.has(id));
  return {
    rootId: root.id,
    backrop1: { geom: g1.map(v => +v.toFixed(2)), color: imgColor(b1) },
    backrop2: { geom: g2.map(v => +v.toFixed(2)), color: imgColor(b2) },
    outline: [+((g1[2] - g2[2]) / 2).toFixed(2), +((g1[3] - g2[3]) / 2).toFixed(2)],
    bgGeom: gb.map(v => +v.toFixed(2)),
    gradientScaled: Math.abs(gb[2] - 330 * SX) < 0.1 && Math.abs(gb[3] - 85.4 * SY) < 0.1,
    gradientVisible: grad.length,
    layerOrder: [order.get(b1.field), order.get(b2.field), order.get(bg.field)],
    layerOrderOk: order.get(b1.field) < order.get(b2.field) && order.get(b2.field) < order.get(bg.field),
    childListOk: list.indexOf(b1.id) < list.indexOf(b2.id) && list.indexOf(b2.id) < list.indexOf(bg.id)
      && ordered.every((id, i) => i === 0 || order.get(mb.get(ordered[i - 1]).field) <= order.get(mb.get(id).field)),
    text: Object.fromEntries(['who', 'what', 'letter'].map(n => [n, textColor(kids.find(r => r.name === n))])),
  };
});
const tplOk = tpl.length === 2 && tpl.every(c =>
  c.backrop1.color === 'FF56565E' && c.backrop2.color === 'FF611F23'
  && Math.abs(c.outline[0] - 3) < 0.01 && Math.abs(c.outline[1] - 3) < 0.01
  && c.gradientScaled && c.gradientVisible === 30 && c.layerOrderOk && c.childListOk
  && c.text.who === 'FFFFFFFF' && c.text.what === 'FFFFFFFF' && c.text.letter === 'FFFFFFFF');
const named = n => B.recs.find(r => r.name === n);
const staticBackdropHidden = isHiddenRecord(named('art657.game.notebook.page').field);
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected, scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  staticBackdropHidden, tplOk, tpl, dangling,
};
checks.verdict = added.length === 0 && removed.length === 0 && scriptIdentical
  && textChanged.length === 0 && bgChanged.length === 0 && unexpected.length === 0
  && staticBackdropHidden && tplOk && dangling === 0;
fs.writeFileSync(path.join(DIR, '669_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify(checks, null, 2));
if (!checks.verdict) process.exitCode = 1;
