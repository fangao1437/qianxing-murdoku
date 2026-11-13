// 674 结构校验：672 → 674（保留 672 渐变、重做票券尺寸/边缘与火漆形状/高光）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/672_梯形与异色区/672_梯形与异色区.gil'));
const B = readGil(path.join(DIR, '674_票券与火漆重做.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '674_构建审计.json'), 'utf8'));
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
const allowed = new Set(audit.modified.flatMap(n => A.recs.filter(q => q.name === n).map(q => q.id)));
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));
const named = n => B.recs.find(r => r.name === n);
const vis = n => named(n) && !isHiddenRecord(named(n).field);
const near = (v, t) => Math.abs(v - t) < 0.02;
const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
const idOf = (g, f) => g.recs.find(r => r.field === f)?.id;
const orderSame = rtA.sub.length === rtB.sub.length && rtA.sub.every((f, i) => idOf(A, f) === idOf(B, rtB.sub[i]));
const order = new Map(); rtB.sub.forEach((f, i) => order.set(f, i));
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

// ★ 用户认可「672 渐变是对的」⇒ 23 枚拟合三角必须逐字节不变
const fitNames = A.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')).map(r => r.name);
const fitUntouched = fitNames.length === 23 && fitNames.every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));
const untouchedExtras = ['clues.help617', 'clues.help627.hit']
  .every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n)));

// 票券尺寸与撕边
const gm = geom(named('art641.game.help.tab')), go = geom(named('art661.tab.outline'));
const ticketOk = near(gm[2], 160) && near(gm[3], 66) && near(go[2], 160) && near(go[3], 72)
  && imgColor(named('art641.game.help.tab')) === 'FF8C2800'
  && imgColor(named('art661.tab.outline')) === 'FF592520';
const stripOk = ['l', 'r'].every(t => {
  const r = named(`art663.tab.edge.${t}0`);
  return vis(r.name) && imgId(r) === 100001 && imgColor(r) === 'FF592520' && near(geom(r)[2], 6);
});
const toothOk = ['l', 'r'].every(t => [0, 1, 2].every(i => {
  const r = named(`art663.tab.tooth.${t}${i}`);
  return vis(r.name) && imgId(r) === 100002 && near(geom(r)[2], 16) && near(geom(r)[3], 26);
}));
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const waxRegex = /^(art663\.wax\.|art664\.wax\.)/;
const visCount = (g, re) => g.recs.filter(r => re.test(r.name || '') && !isHiddenRecord(r.field)).length;
const tabVisible = visCount(B, tabRegex), waxVisible = visCount(B, waxRegex);

// 火漆
const lobes = Array.from({ length: 12 }, (_, i) => named(`art663.wax.edge.${i}`));
const lobesOk = lobes.every(r => vis(r.name) && imgId(r) === 100002
  && near(geom(r)[2], 52) && imgColor(r) === 'FFCC0602');
const coreOk = near(geom(named('art663.wax.core'))[2], 68) && imgColor(named('art663.wax.core')) === 'FFB40806';
const topOk = near(geom(named('art664.wax.top.lobe'))[2], 44) && near(geom(named('art664.wax.top.lobe'))[3], 26);
const arcsOk = Array.from({ length: 6 }, (_, i) => named(`art664.wax.ring.${i}`))
  .every(r => vis(r.name) && near(geom(r)[2], 16) && near(geom(r)[3], 28))
  && Array.from({ length: 10 }, (_, i) => named(`art664.wax.ring.${i + 6}`)).every(r => !vis(r.name));
const stampOk = near(geom(named('art664.wax.stamp.core'))[2], 56);
const waxHiddenOk = ['art664.wax.hot.l', 'art664.wax.hot.r', 'art664.wax.center', 'art664.wax.stamp.rim']
  .every(n => !vis(n)) && A.recs.filter(r => /^art663\.wax\.lobe\./.test(r.name || ''))
  .every(r => !vis(r.name));

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  orderSame, childListOk, dangling,
  gradientUntouched: fitUntouched, fitCount: fitNames.length,
  helpAndHitUntouched: untouchedExtras,
  visibleLayers: { tabBefore: visCount(A, tabRegex), tabAfter: tabVisible,
    waxBefore: visCount(A, waxRegex), waxAfter: waxVisible },
  ticket: { mainGeom: gm.map(v => +v.toFixed(2)), outlineGeom: go.map(v => +v.toFixed(2)),
    totalLength: 160 + 2 * 9, designLength: 177.8, ticketOk, stripOk, toothOk },
  wax: { lobesOk, coreOk, topOk, arcsOk, stampOk, waxHiddenOk,
    radii: audit.spec.wax.radii, hotMaxRadius: audit.spec.wax.hotMaxRadius },
  gates: audit.spec.gates,
};
checks.verdict = removed.length === 0 && added.length === 0
  && changed.length === audit.counts.modified && unexpected.length === 0
  && scriptIdentical && textChanged.length === 0 && bgChanged.length === 0
  && orderSame && childListOk && dangling === 0
  && fitUntouched && untouchedExtras
  && tabVisible === 33 && waxVisible === 21
  && ticketOk && stripOk && toothOk
  && lobesOk && coreOk && topOk && arcsOk && stampOk && waxHiddenOk;
fs.writeFileSync(path.join(DIR, '674_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length, unexpected,
  scriptIdentical, textChanged: textChanged.length, bgChanged: bgChanged.length,
  orderSame, childListOk, dangling, gradientUntouched: fitUntouched,
  helpAndHitUntouched: untouchedExtras, visibleLayers: checks.visibleLayers,
  ticket: checks.ticket, wax: checks.wax }, null, 2));
if (!checks.verdict) process.exitCode = 1;
