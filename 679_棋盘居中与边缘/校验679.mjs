// 679 结构校验：678 → 679（棋盘移动端 y 居中 + 注释卡边缘连贯/圆润）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口/678_注释卡真缺口.gil'));
const B = readGil(path.join(DIR, '679_棋盘居中与边缘.gil'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '679_规格.json'), 'utf8'));
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
  const byIdB = new Map(B.recs.map(q => [q.id, q]));
  const cache = new Map();
  const states = q => stateBlocks(q.field.sub, []);
  function abs(q, d = 0) {
    if (!q || d > 12) return [800, 450];
    if (cache.has(q.id)) return cache.get(q.id);
    const st = states(q)[0], p = st && pairOf(st, 504);
    if (!p) return [800, 450];
    const [px, py] = q.parentId ? abs(byIdB.get(q.parentId), d + 1) : [800, 450];
    const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
    cache.set(q.id, res); return res;
  }
  const st = states(r)[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  if (!p || !s) return null;
  const [px, py] = r.parentId ? abs(byIdB.get(r.parentId)) : [800, 450];
  return [px + pairValue(p, 0), py - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)];
}
function rotOf(r) { return stateBlocks(r.field.sub, [])[0]?.sub?.find(q => q.field === 508)?.sub?.[0]?.f || 0; }
function textOf(r) { const tf = ns(r.field, [505, 503, 75, 510, 501])[0]; return tf?.payload?.toString('utf8') || ''; }
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const targetNames = new Set([
  ...SPEC.ticket.teeth.map(e => e.name), ...SPEC.ticket.rectModify.map(m => m.name),
  ...SPEC.board.roots.map(b => b.name),
]);
const changedNames = changed.map(id => ma.get(id).name || '#' + id);
const unexpected = changedNames.filter(n => !targetNames.has(n));
const namedA = n => A.recs.find(r => r.name === n), namedB = n => B.recs.find(r => r.name === n);
const near = (v, t) => Math.abs(v - t) < 0.03;

const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
const order = new Map(); rtB.sub.forEach((f, i) => order.set(f, i));
// 按记录 id 比较层序（不能用对象引用：两次 readGil 产生不同对象）
const idOf = (g, f) => g.recs.find(q => q.field === f)?.id;
const oldIdsA = rtA.sub.map(f => idOf(A, f)).filter(id => id != null);
const oldIdsB = rtB.sub.map(f => idOf(B, f)).filter(id => ma.has(id));
const orderSame = oldIdsA.length === oldIdsB.length && oldIdsA.every((id, i) => id === oldIdsB[i]);
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

// 既有成果（除 31 条目标层）逐字节不变
const keep = A.recs.filter(r => r.name && !targetNames.has(r.name)
  && (/^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art677\.ring\.|art678\.tab\.)/.test(r.name)
    || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame',
        'art658.clues.binding', 'art676.binding.mid'].includes(r.name))).map(r => r.name);
const prevUntouched = keep.every(n => enc(namedB(n)) === enc(namedA(n)));
const waxVisible = B.recs.filter(r => /^art675\.wax\./.test(r.name || '') && !isHiddenRecord(r.field)).length;

// ① 棋盘：x 不变、y +30、尺寸不变
const SHIFT = SPEC.board.shiftY;
const boardOk = SPEC.board.roots.every(b => {
  const a = namedA(b.name), c = namedB(b.name);
  const ga = (() => { const st = stateBlocks(a.field.sub, [])[0], p = pairOf(st, 504), s = pairOf(st, 505);
    return [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)]; })();
  const gc = geom(c);
  return near(gc[0], ga[0]) && near(gc[2], ga[2]) && near(gc[3], ga[3]) && near(gc[1], ga[1] + SHIFT);
});
const boardDetail = Object.fromEntries(SPEC.board.roots.map(b => {
  const st = stateBlocks(namedA(b.name).field.sub, [])[0], p = pairOf(st, 504);
  const before = [800 + pairValue(p, 0), 450 - pairValue(p, 1)].map(v => +v.toFixed(1));
  const st2 = stateBlocks(namedB(b.name).field.sub, [])[0], p2 = pairOf(st2, 504);
  const after = [800 + pairValue(p2, 0), 450 - pairValue(p2, 1)].map(v => +v.toFixed(1));
  return [b.name, { before, after }];
}));

// ② 注释卡齿：几何/颜色/img/rot 逐条一致
const teethOk = SPEC.ticket.teeth.every(e => {
  const r = namedB(e.name); if (!r || isHiddenRecord(r.field)) return false;
  const gm = geom(r);
  return imgColor(r) === 'FF' + e.color.slice(1).toUpperCase() && imgId(r) === e.img
    && near(gm[0], e.cx) && near(gm[1], e.cy) && near(gm[2], e.w) && near(gm[3], e.h)
    && Math.abs(rotOf(r) - e.rot) < 0.03;
});
const T = SPEC.ticket.geometry;
const rectOk = SPEC.ticket.rectModify.every(m => {
  const gm = geom(namedB(m.name));
  return near(gm[2], m.w) && near(gm[3], m.h)
    && (!m.color || imgColor(namedB(m.name)) === 'FF' + m.color.slice(1).toUpperCase());
});
const teethVisible = B.recs.filter(r => /^art678\.tab\./.test(r.name || '') && !isHiddenRecord(r.field)).length;
const Z = SPEC.ticket.gates;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  changedNames, unexpectedChanges: unexpected,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  recTopSame: orderSame, childListOk, dangling,
  previous: { untouched: prevUntouched, checked: keep.length, waxVisible },
  board: { ok: boardOk, shiftY: SHIFT, xUnchanged: true,
    measurement: SPEC.board.measurement, roots: SPEC.board.roots.length, detail: boardDetail },
  ticket: { teethOk, rectOk, teethVisible, zeroSpur: Z.zeroSpur,
    mainPx: Z.mainPx, mainOut: Z.mainOut, gradPx: Z.gradPx, gradOut: Z.gradOut,
    mainW: T.mainW, outlineW: T.outlineW, colors: [T.colorMainTooth, T.colorOutline] },
};
checks.verdict = added.length === 0 && removed.length === 0 && changed.length === targetNames.size
  && unexpected.length === 0 && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && orderSame && childListOk && dangling === 0
  && prevUntouched && waxVisible === 240
  && boardOk && teethOk && rectOk && teethVisible === SPEC.ticket.teeth.length
  && Z.zeroSpur && Z.mainOut === 0 && Z.gradOut === 0;
fs.writeFileSync(path.join(DIR, '679_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  unexpected: unexpected.length, scriptIdentical, textChanged: textChanged.length,
  bgChanged: bgChanged.length, recTopSame: orderSame, childListOk, dangling,
  prevUntouched, waxVisible, boardOk, teethOk, rectOk, teethVisible, zeroSpur: Z.zeroSpur }, null, 2));
if (!checks.verdict) process.exit(2);
