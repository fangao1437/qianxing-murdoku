// 667 结构校验：666 → 667 逐记录比对 + 三项验收断言
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/666_线索换位/666_线索换位.gil'));
const B = readGil(path.join(DIR, '667_线索卡背景.gil'));
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '667_构建审计.json'), 'utf8'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
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
const bgA = new Set(descendants(A, 'police-v19'));
const bgChanged = changed.filter(id => bgA.has(id));
const scriptIdentical = findScriptLeaf(A).buf.equals(findScriptLeaf(B).buf);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const numOf = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function color(r) {
  const p = ns(r?.field, [505, 503, 84])[0];
  const c = p ? numOf(p, 502) : null;
  return c === null ? null : (c >>> 0).toString(16).padStart(8, '0').toUpperCase();
}
function size(r) {
  const st = stateBlocks(r.field.sub, [])[0], s = st && pairOf(st, 505);
  return s ? [pairValue(s, 0), pairValue(s, 1)] : null;
}
const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const named = n => B.recs.find(r => r.name === n);

// ① 隐藏生效
const hiddenOk = audit.hidden.length === 61
  && audit.hidden.every(n => { const r = named(n); return r && isHiddenRecord(r.field); });
const tplRoots = B.recs.filter(r => r.name === 'clue' && B.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
const tplChecks = tplRoots.map(root => {
  const kids = B.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const reds = kids.filter(r => /^(art658\.clue\d+\.bg|art658\.clue\d+\.rule|art661\.clue\d+\.)/.test(r.name || ''));
  const sz1 = size(b1), sz2 = size(b2);
  return {
    rootId: root.id,
    backrop1: color(b1), backrop2: color(b2),
    outlinePx: sz1 && sz2 ? +((sz1[0] - sz2[0]) / 2).toFixed(2) : null,
    layerOrder: (order.get(b1.field) < order.get(b2.field)),
    redsAllHidden: reds.every(r => isHiddenRecord(r.field)),
    redsCount: reds.length,
  };
});
const tplOk = tplChecks.length === 2 && tplChecks.every(c =>
  c.backrop1 === 'FF56565E' && c.backrop2 === 'FFFDFAEF'
  && Math.abs(c.outlinePx - 3) < 0.01 && c.layerOrder && c.redsAllHidden && c.redsCount === 30);
const staticRedHidden = ['art657.game.notebook.page', 'art657.game.notebook.page.mid', 'art657.game.notebook.page.lower']
  .every(n => { const r = named(n); return r && isHiddenRecord(r.field); });
const whiteFrame = color(named('art657.game.notebook.frame'));

// ② 变更白名单 + childList 同序
// 两套模板的 backrop1/backrop2 同名，必须把所有同名记录都纳入白名单
const allowed = new Set(audit.modified.flatMap(n => A.recs.filter(q => q.name === n).map(q => q.id)));
const unexpected = changed.filter(id => !allowed.has(id)).map(id => ma.get(id).name || ('#' + id));
let childListOk = true;
for (const root of tplRoots) {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  if (list.some((id, i) => i > 0 && order.get(mb.get(list[i - 1]).field) > order.get(mb.get(id).field))) childListOk = false;
}
const idsB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;
// 666 的 26 条文本「内容」必须零改动（只比文本 payload，不比字色）
function textOf(r) {
  // 只取文本控件的正文字段（与仓库渲染器同路径），名字/二进制 payload 不算文本内容
  const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
  return tf?.payload?.toString('utf8') || '';
}
const textChanged = changed.filter(id => textOf(ma.get(id)) !== textOf(mb.get(id)));
// 白底可读性：两套模板 who/what/letter 字色
const textColors = tplRoots.map(root => {
  const kids = B.recs.filter(r => r.parentId === root.id);
  return Object.fromEntries(['who', 'what', 'letter'].map(n => {
    const tp = ns(kids.find(r => r.name === n)?.field, [505, 503, 75])[0];
    const c = tp ? numOf(tp, 504) : null;
    return [n, c === null ? null : (c >>> 0).toString(16).padStart(8, '0').toUpperCase()];
  }));
});
const textColorsOk = textColors.every(c => c.who === 'FF3A2A22' && c.what === 'FF3A2A22' && c.letter === 'FF28241E');

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  unexpectedChanges: unexpected, textRecordsChanged: textChanged.length,
  scriptIdentical, scriptBytes: findScriptLeaf(B).buf.length,
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  hiddenOk, hiddenCount: audit.hidden.length,
  tplOk, tplChecks,   staticRedHidden, whiteFrame, textColors, textColorsOk,
  childListOk, dangling,
};
checks.verdict = added.length === 0 && removed.length === 0 && scriptIdentical
  && bgChanged.length === 0 && unexpected.length === 0 && textChanged.length === 0
  && hiddenOk && tplOk && staticRedHidden && textColorsOk && childListOk && dangling === 0;
fs.writeFileSync(path.join(DIR, '667_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify(checks, null, 2));
if (!checks.verdict) process.exitCode = 1;
