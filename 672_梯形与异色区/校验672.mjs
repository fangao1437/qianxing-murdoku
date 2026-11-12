// 672 结构校验：671 → 672（几何构造、描边色、最少图元、高亮不变）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/671_文本与细线/671_文本与细线.gil'));
const B = readGil(path.join(DIR, '672_梯形与异色区.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '672_构建审计.json'), 'utf8'));
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
const imgColor = r => ((num(ns(r.field, [505, 503, 84])[0], 502) ?? 0) >>> 0).toString(16).toUpperCase().padStart(8, '0');
const imgId = r => num(ns(r.field, [505, 503, 84])[0], 503);
const textColor = r => ((num(ns(r.field, [505, 503, 75])[0], 504) ?? 0) >>> 0).toString(16).toUpperCase();
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return p && s ? { g: [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)], rot } : null;
}
function textOf(r) { const tf = ns(r.field, [505, 503, 75, 510, 501])[0]; return tf?.payload?.toString('utf8') || ''; }
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const allowed = new Set(audit.modified.flatMap(n2 => A.recs.filter(q => q.name === n2).map(q => q.id)));
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));

const RECT = { x0: 638, y0: 410.3, x1: 962, y1: 489.7 };
function triVerts(r) {
  const q = geom(r); if (!q) return [];
  const [cx, cy, w, h] = q.g, a = -q.rot * Math.PI / 180;
  return [[0, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]]
    .map(([x, y]) => [cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)]);
}
const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const tplRoots = B.recs.filter(r => r.name === 'clue' && B.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
const tpl = tplRoots.map((root, i) => {
  const n = i + 1, kids = B.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const hi = kids.find(r => r.name === `art671.clue${n}.hi`);
  const lo = kids.find(r => r.name === `art671.clue${n}.lo`);
  const trap = kids.find(r => r.name === `art672.clue${n}.trap`);
  const mid1 = kids.find(r => r.name === `art672.clue${n}.mid1`);
  const mid2 = kids.find(r => r.name === `art672.clue${n}.mid2`);
  const corner = kids.find(r => r.name === `art672.clue${n}.corner`);
  const art = [hi, lo, trap, mid1, mid2, corner];
  const texts = kids.filter(r => ['who', 'what', 'letter', 'face'].includes(r.name));
  const firstText = Math.min(...texts.map(r => order.get(r.field)));
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []) : [];
  const ordered = list.filter(id => mb.has(id));
  const verts = [lo, mid1, mid2, corner].flatMap(triVerts);
  const near = (v, t) => Math.abs(v - t) < 0.02;
  return {
    rootId: root.id,
    backrop1: { geom: geom(b1).g.map(v => +v.toFixed(2)), color: imgColor(b1) },
    backrop2: { geom: geom(b2).g.map(v => +v.toFixed(2)), color: imgColor(b2) },
    hi: { color: imgColor(hi), geom: geom(hi).g.map(v => +v.toFixed(2)) },
    lo: { color: imgColor(lo), imageId: imgId(lo), geom: geom(lo).g.map(v => +v.toFixed(2)), rot: +geom(lo).rot.toFixed(3) },
    trap: { color: imgColor(trap), imageId: imgId(trap), geom: geom(trap).g.map(v => +v.toFixed(2)) },
    mid1: { color: imgColor(mid1), imageId: imgId(mid1), rot: +geom(mid1).rot.toFixed(3) },
    mid2: { color: imgColor(mid2), imageId: imgId(mid2), rot: +geom(mid2).rot.toFixed(3) },
    corner: { color: imgColor(corner), imageId: imgId(corner), rot: +geom(corner).rot.toFixed(3) },
    visibleArt: [trap, mid1, mid2, corner].filter(r => r && !isHiddenRecord(r.field)).length,
    artAllBeforeText: art.every(r => r && order.get(r.field) < firstText),
    allVerticesInside: verts.every(([x, y]) => x >= RECT.x0 - 0.02 && x <= RECT.x1 + 0.02
      && y >= RECT.y0 - 0.02 && y <= RECT.y1 + 0.02),
    oldAllHidden: kids.filter(r => /^art670\.clue/.test(r.name || '')).every(r => isHiddenRecord(r.field)),
    childListOk: ordered.every((id, j) => j === 0 || order.get(mb.get(ordered[j - 1]).field) <= order.get(mb.get(ordered[j]).field)),
    text: Object.fromEntries(['who', 'what', 'letter'].map(n2 => [n2, textColor(kids.find(r => r.name === n2))])),
    checks: {
      strokeDarkRed: imgColor(b1) === 'FF491B1E',
      mainUnchanged: imgColor(b2) === 'FF68262A',
      hiUnchanged: imgColor(hi) === 'FF9D3033',
      loIsCover: imgColor(lo) === 'FF68262A' && imgId(lo) === 100003
        && near(geom(lo).rot, audit.spec.geometry.coverTriangle.rot)
        && near(geom(lo).g[2], audit.spec.geometry.coverTriangle.w),
      trapIsRect: imgId(trap) === 100001 && imgColor(trap) === 'FF611F23'
        && near(geom(trap).g[2], audit.spec.geometry.trapRect.w)
        && near(geom(trap).g[3], audit.spec.geometry.trapRect.h),
      midAreTriangles: [mid1, mid2].every(r => imgId(r) === 100003 && imgColor(r) === 'FF702830'),
      cornerIsTriangle: imgId(corner) === 100003 && imgColor(corner) === 'FF611F23',
      backropGeom: Math.abs(geom(b1).g[2] - 330) < 0.01 && Math.abs(geom(b2).g[2] - 324) < 0.01,
    },
  };
});
const tplOk = tpl.length === 2 && tpl.every(c =>
  Object.values(c.checks).every(Boolean) && c.visibleArt === 4 && c.artAllBeforeText
  && c.allVerticesInside && c.oldAllHidden && c.childListOk
  && c.text.who === 'FFFFFFFF' && c.text.what === 'FFFFFFFF' && c.text.letter === 'FFFFFFFF');
const named = n2 => B.recs.find(r => r.name === n2);
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
  staticBackdropHidden, tplOk, tpl,
  visibleLayersPerTemplate: audit.visibleLayersPerTemplate,
  previousVisibleLayersPerTemplate: audit.previousVisibleLayersPerTemplate,
  gates: audit.spec.gates, dangling,
  highlightUnchanged: scriptIdentical,
};
// 实际改动记录 = 每模板 backrop1(描边色) / lo(改形改色) / clue(childList 同步) = 6 条
checks.verdict = removed.length === 0 && added.length === 8 && changed.length === 6
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && staticBackdropHidden && tplOk && dangling === 0
  && audit.spec.gates.midCoverage >= 0.999 && audit.spec.gates.trapAccuracy >= 0.995;
fs.writeFileSync(path.join(DIR, '672_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ ...checks, tpl: checks.tpl.map(c => ({ rootId: c.rootId, checks: c.checks, visibleArt: c.visibleArt })) }, null, 2));
if (!checks.verdict) process.exitCode = 1;
