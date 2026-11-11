// 668 结构校验：666 → 668 逐记录比对（应只有 1 条变化）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/666_线索换位/666_线索换位.gil'));
const B = readGil(path.join(DIR, '668_线索卡染色.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '668_构建审计.json'), 'utf8'));
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
function textOf(r) {
  const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
  return tf?.payload?.toString('utf8') || '';
}
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
const named = n => B.recs.find(r => r.name === n);
const page = named('art657.game.notebook.page');
const frame = named('art657.game.notebook.frame');

// 两套模板：渐变可见 / backrop 透明 / 文字白 / 层序 backrop1 在渐变之后
const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const tplRoots = B.recs.filter(r => r.name === 'clue' && B.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
const tpl = tplRoots.map(root => {
  const kids = B.recs.filter(r => r.parentId === root.id);
  const grad = kids.filter(r => /^art661\.clue/.test(r.name || '') && !isHiddenRecord(r.field));
  const bg = kids.find(r => /^art658\.clue\d+\.bg$/.test(r.name || ''));
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const lastGrad = Math.max(...grad.map(r => order.get(r.field)));
  return {
    rootId: root.id, gradientLayers: grad.length, bgVisible: !isHiddenRecord(bg.field),
    bgColor: imgColor(bg), backrop1: imgColor(b1), backrop2: imgColor(b2),
    backrop1AfterGradient: order.get(b1.field) > lastGrad && order.get(b1.field) < order.get(b2.field),
    text: Object.fromEntries(['who', 'what', 'letter'].map(n => [n, textColor(kids.find(r => r.name === n))])),
  };
});
const tplOk = tpl.length === 2 && tpl.every(c => c.gradientLayers === 28 && c.bgVisible
  && c.bgColor === 'FF68282A' && c.backrop1 === 'FFFFFF' && c.backrop2 === 'FFFFFF'
  && c.backrop1AfterGradient
  && c.text.who === 'FFFFFFFF' && c.text.what === 'FFFFFFFF' && c.text.letter === 'FFFFFFFF');
let childListOk = true;
for (const root of tplRoots) {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  if (list.some((id, i) => i > 0 && order.get(mb.get(list[i - 1]).field) > order.get(mb.get(id).field))) childListOk = false;
}
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  changedNames: changed.map(id => ma.get(id).name),
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  textRecordsChanged: textChanged.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  staticBackdropHidden: isHiddenRecord(page.field), whiteFrame: imgColor(frame),
  tplOk, tpl, childListOk, dangling,
};
checks.verdict = added.length === 0 && removed.length === 0 && changed.length === 1
  && changed[0] === page.id && scriptIdentical && textChanged.length === 0
  && bgChanged.length === 0 && checks.staticBackdropHidden && tplOk && childListOk && dangling === 0;
fs.writeFileSync(path.join(DIR, '668_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify(checks, null, 2));
if (!checks.verdict) process.exitCode = 1;
