// 680 结构校验：679 → 680（网格纸跟随下移 + rug_layer/furn 排在 x 之下）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/679_棋盘居中与边缘/679_棋盘居中与边缘.gil'));
const B = readGil(path.join(DIR, '680_网格纸与家具层序.gil'));
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
const sA = findScriptLeaf(A).buf.toString('utf8'), sB = findScriptLeaf(B).buf.toString('utf8');
const st = r => stateBlocks(r.field.sub, [])[0];
const pair504 = r => pairOf(st(r), 504);
const namedA = n => A.recs.find(r => r.name === n), namedB = n => B.recs.find(r => r.name === n);
const near = (v, t) => Math.abs(v - t) < 0.03;

// ① 网格纸：父 504 y 恢复 0，49 子层 y 各 -30（x/w/h 不变）
const reuseA = namedA('art657.grid.reuse'), reuseB = namedB('art657.grid.reuse');
const kidsA = A.recs.filter(r => r.parentId === reuseA.id);
const kidsB = B.recs.filter(r => r.parentId === reuseB.id);
const parentY = pairValue(pair504(reuseB), 1);
const parentOk = near(parentY, 0) && kidsA.length === 49 && kidsB.length === 49;
const gridOk = kidsA.every(a => {
  const b = mb.get(a.id); if (!b) return false;
  const pa = pair504(a), pb = pair504(b);
  const sa = pairOf(st(a), 505), sb = pairOf(st(b), 505);
  return near(pairValue(pb, 0), pairValue(pa, 0))
    && near(pairValue(pb, 1), pairValue(pa, 1) - 30)
    && near(pairValue(sb, 0), pairValue(sa, 0)) && near(pairValue(sb, 1), pairValue(sa, 1));
});
const gridSample = ['art656.home.grid.paper', 'art656.home.grid.v0', 'art663.grid.h22'].map(n => ({
  name: n,
  before: [pairValue(pair504(namedA(n)), 0), pairValue(pair504(namedA(n)), 1)].map(v => +v.toFixed(1)),
  after: [pairValue(pair504(namedB(n)), 0), pairValue(pair504(namedB(n)), 1)].map(v => +v.toFixed(1)),
}));

// ② 内嵌 Lua：仅插入一行，且位置在 obj12 之后 / x 之前
const ANCHOR = '        "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",\n';
const PATCH = ANCHOR + '        "rug_layer", "furn",\n';
const scriptClean = sB.replace(PATCH, ANCHOR) === sA
  && (sB.match(/"rug_layer", "furn",/g) || []).length === 1
  && (sA.match(/"rug_layer", "furn",/g) || []).length === 0;
const li = sB.indexOf('layer_order = {');
const block = sB.slice(li, sB.indexOf('},', li));
const pos = { obj12: block.indexOf('"obj12"'), rug: block.indexOf('"rug_layer"'),
  furn: block.indexOf('"furn"'), portrait: block.indexOf('"portrait"'), x: block.indexOf('"x"') };
const orderOk = pos.obj12 < pos.rug && pos.rug < pos.furn && pos.furn < pos.portrait && pos.portrait < pos.x;
const srcSynced = fs.readFileSync(path.join(ROOT, 'qianxing-murdoku/lua/entry_client_script.lua'), 'utf8')
  .includes('"rug_layer", "furn",');

// ③ 既有成果（除 50 条目标）逐字节不变
const targetNames = new Set([...kidsA.map(k => k.name), 'art657.grid.reuse']);
const keep = A.recs.filter(r => r.name && !targetNames.has(r.name)
  && (/^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art677\.ring\.|art678\.tab\.)/.test(r.name)
    || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame',
        'art658.clues.binding', 'art676.binding.mid', 'stage',
        'art641.game.boardframe.paper', 'art641.game.boardframe.shadow', 'art641.game.boardbottom',
        'art641.game.help.tab', 'art661.tab.outline'].includes(r.name))).map(r => r.name);
const prevUntouched = keep.every(n => enc(namedB(n)) === enc(namedA(n)));
const changedExtra = changed.filter(id => {
  const n = ma.get(id).name;
  return n && !targetNames.has(n) && !keep.includes(n);
}).map(id => ma.get(id).name);
const textChanged = 0; // 本轮不改任何文本字段（脚本按字节校验，见 scriptClean）

// ④ 层序
const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
const idOf = (g, f) => g.recs.find(q => q.field === f)?.id;
const oldIdsA = rtA.sub.map(f => idOf(A, f)).filter(id => id != null);
const oldIdsB = rtB.sub.map(f => idOf(B, f)).filter(id => ma.has(id));
const recTopSame = oldIdsA.length === oldIdsB.length && oldIdsA.every((id, i) => id === oldIdsB[i]);
const order = new Map(); rtB.sub.forEach((f, i) => order.set(f, i));
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;
const waxVisible = B.recs.filter(r => /^art675\.wax\./.test(r.name || '') && !isHiddenRecord(r.field)).length;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  changedExtra, textRecordsChanged: textChanged,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  recTopSame, childListOk, dangling,
  previous: { untouched: prevUntouched, checked: keep.length, waxVisible },
  gridPaper: { parentOk, parentY, gridOk, kids: kidsA.length, shiftY: -30, xUnchanged: true, sample: gridSample,
    rootCause: 'sync_art641() 的 SetAnchoredPosition(105,46) 覆盖父坐标' },
  xMark: { scriptClean, orderOk, orderPos: pos, srcSynced,
    scriptBytes: [Buffer.byteLength(sA), Buffer.byteLength(sB)],
    inserted: '"rug_layer", "furn"' },
};
checks.verdict = added.length === 0 && removed.length === 0 && changed.length === 50
  && changedExtra.length === 0 && bgChanged.length === 0
  && recTopSame && childListOk && dangling === 0
  && prevUntouched && waxVisible === 240
  && parentOk && gridOk && scriptClean && orderOk && srcSynced;
fs.writeFileSync(path.join(DIR, '680_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  changedExtra: changedExtra.length, bgChanged: bgChanged.length,
  recTopSame, childListOk, dangling, prevUntouched, waxVisible,
  parentOk, gridOk, scriptClean, orderOk, srcSynced,
  scriptBytes: checks.xMark.scriptBytes }, null, 2));
if (!checks.verdict) process.exit(2);
