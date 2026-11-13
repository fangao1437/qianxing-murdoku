// 673 结构校验：672 → 673（两处形状整改、最少图元、Lua/文本/层序/热区零改动）
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
const B = readGil(path.join(DIR, '673_注释按钮与底图.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '673_构建审计.json'), 'utf8'));
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
  const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return p && s ? { g: [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)], rot } : null;
}
function textOf(r) { const tf = ns(r.field, [505, 503, 75, 510, 501])[0]; return tf?.payload?.toString('utf8') || ''; }
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const allowed = new Set(audit.modified.flatMap(n => A.recs.filter(q => q.name === n).map(q => q.id)));
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));
const named = n => B.recs.find(r => r.name === n);
const vis = n => named(n) && !isHiddenRecord(named(n).field);
const recTopB = B.tree.find(q => q.field === 9), recTopA = A.tree.find(q => q.field === 9);
const idOfField = (g, f) => g.recs.find(r => r.field === f)?.id;
const orderSame = recTopA.sub.length === recTopB.sub.length
  && recTopA.sub.every((f, i) => idOfField(A, f) === idOfField(B, recTopB.sub[i]));
const order = new Map(); recTopB.sub.forEach((f, i) => order.set(f, i));
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

// 票券几何
const T = { cx: 384, cy: 211, w: 124, h: 66, rot: -13 };
const a = -T.rot * Math.PI / 180;
const unrot = (x, y) => { const dx = x - T.cx, dy = y - T.cy;
  return [dx * Math.cos(a) + dy * Math.sin(a), -dx * Math.sin(a) + dy * Math.cos(a)]; };
function triVerts(r) {
  const q = geom(r); if (!q) return [];
  const [cx, cy, w, h] = q.g, r0 = -q.rot * Math.PI / 180;
  return [[0, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]]
    .map(([x, y]) => [cx + x * Math.cos(r0) - y * Math.sin(r0), cy + x * Math.sin(r0) + y * Math.cos(r0)]);
}
const gMain = geom(named('art641.game.help.tab')), gOutline = geom(named('art661.tab.outline'));
const mid = named('art664.tab.mid.fit01'), hi = named('art664.tab.hi.fit15');
const verts = [...triVerts(mid), ...triVerts(hi)].map(p => unrot(p[0], p[1]));
const vertsInside = verts.every(([lx, ly]) => Math.abs(lx) <= T.w / 2 + 0.02 && Math.abs(ly) <= T.h / 2 + 0.02);
const near = (v, t) => Math.abs(v - t) < 0.02;
const tabRegex = /^(art641\.game\.help\.tab|art661\.tab\.|art663\.tab\.|art664\.tab\.)/;
const waxRegex = /^(art663\.wax\.|art664\.wax\.)/;
const tabVisible = B.recs.filter(r => tabRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;
const waxVisible = B.recs.filter(r => waxRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;
const tabVisibleBefore = A.recs.filter(r => tabRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;
const waxVisibleBefore = A.recs.filter(r => waxRegex.test(r.name || '') && !isHiddenRecord(r.field)).length;
const teeth = ['l', 'r'].flatMap(t => [0, 1, 2].map(i => ({
  rim: named(`art663.tab.edge.${t}${i + 1}`), tooth: named(`art663.tab.tooth.${t}${i}`) })));
const teethOk = teeth.every(({ rim, tooth }) => {
  const gr = geom(rim), gt = geom(tooth);
  return vis(rim.name) && vis(tooth.name) && imgId(rim) === 100002 && imgId(tooth) === 100002
    && imgColor(rim) === 'FF592520' && near(gr.g[2], 24) && near(gr.g[3], 30)
    && near(gt.g[2], 21) && near(gt.g[3], 27)
    && imgColor(tooth) === 'FF8C2800'
    && near(gr.g[0], gt.g[0]) && near(gr.g[1], gt.g[1]);
});
const bgRectHidden = ['l', 'r'].every(t => !vis(`art663.tab.edge.${t}0`));
const fitHidden = B.recs.filter(r => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(r.name || '')
  && !['art664.tab.mid.fit01', 'art664.tab.hi.fit15'].includes(r.name) && !isHiddenRecord(r.field)).length === 0;

// 火漆几何
const waxLobes = Array.from({ length: 10 }, (_, i) => named(`art663.wax.edge.${i}`));
const waxOk = waxLobes.every(r => r && vis(r.name) && imgId(r) === 100002 && near(geom(r).g[2], 44))
  && [10, 11].every(i => !vis(`art663.wax.edge.${i}`))
  && ['art664.wax.center', 'art664.wax.stamp.rim'].every(n => !vis(n))
  && B.recs.filter(r => /^art664\.wax\.ring\./.test(r.name || '') && !isHiddenRecord(r.field)).length === 0;
const stamp = named('art664.wax.stamp.core');
const stampOk = vis(stamp.name) && imgColor(stamp) === 'FF9C0400' && near(geom(stamp).g[2], 64) && near(geom(stamp).g[3], 58);
const hotArcs = ['art664.wax.hot.l', 'art664.wax.hot.r'].map(n => named(n));
const hotColors = hotArcs.every(r => vis(r.name) && imgColor(r) === 'FFD70601'
  && near(geom(r).g[2], 12) && near(geom(r).g[3], 44));
const lobesUniform = waxLobes.every(r => imgColor(r) === 'FFB40806');
const coreOk = near(geom(named('art663.wax.core')).g[2], 84);

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  orderSame, childListOk, dangling,
  helpAndHitUnchanged: ['clues.help617', 'clues.help627.hit']
    .every(n => enc(named(n)) === enc(A.recs.find(r => r.name === n))),
  visibleLayers: { tabBefore: tabVisibleBefore, tabAfter: tabVisible,
    waxBefore: waxVisibleBefore, waxAfter: waxVisible },
  ticket: {
    main: { geom: gMain.g.map(v => +v.toFixed(2)), color: imgColor(named('art641.game.help.tab')) },
    outline: { geom: gOutline.g.map(v => +v.toFixed(2)) },
    mid: { rot: +geom(mid).rot.toFixed(2), color: imgColor(mid), imageId: imgId(mid) },
    hi: { rot: +geom(hi).rot.toFixed(2), color: imgColor(hi), imageId: imgId(hi) },
    vertsInside, teethOk, bgRectHidden, fitHidden,
  },
  wax: { lobesVisible: waxLobes.filter(r => vis(r.name)).length, waxOk, stampOk, hotColors,
    lobesUniform, coreOk, radii: audit.spec.wax.radii },
  gates: audit.spec.gates,
};
checks.verdict = removed.length === 0 && added.length === 0 && changed.length === audit.counts.modified
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && orderSame && childListOk && dangling === 0
  && checks.helpAndHitUnchanged
  && tabVisible === 16 && waxVisible === 15
  && near(gMain.g[2], 124) && near(gMain.g[3], 66) && near(gOutline.g[2], 124) && near(gOutline.g[3], 72)
  && imgColor(named('art641.game.help.tab')) === 'FF8C2800'
  && imgColor(named('art661.tab.outline')) === 'FF592520'
  && near(geom(mid).rot, 32) && near(geom(hi).rot, 32)
  && imgColor(mid) === 'FFAF3200' && imgColor(hi) === 'FFCB4C19'
  && imgId(mid) === 100003 && imgId(hi) === 100003
  && vertsInside && teethOk && bgRectHidden && fitHidden
  && waxOk && stampOk && hotColors && lobesUniform && coreOk;
fs.writeFileSync(path.join(DIR, '673_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length, unexpected,
  scriptIdentical, textChanged: textChanged.length, bgChanged: bgChanged.length,
  orderSame, childListOk, dangling, helpAndHitUnchanged: checks.helpAndHitUnchanged,
  visibleLayers: checks.visibleLayers, ticket: checks.ticket, wax: checks.wax }, null, 2));
if (!checks.verdict) process.exitCode = 1;
