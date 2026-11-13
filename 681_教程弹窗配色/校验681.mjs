// 681 结构校验：680 → 681（只验证「教程弹窗改色」这一件事，其余全部逐字节不变）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(REPO, 'tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(REPO, 'tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const A = readGil(path.join(REPO, '680_网格纸与家具层序/680_网格纸与家具层序.gil'));
const B = readGil(path.join(DIR, '681_教程弹窗配色.gil'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '681_配色规格.json'), 'utf8'));
const CHANGELOG = JSON.parse(fs.readFileSync(path.join(DIR, '681_逐条改色清单.json'), 'utf8'));
const enc = r => encodeMsg([r.field]);
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)).toString('hex') !== enc(mb.get(id)).toString('hex'));
const changedExtra = changed.filter(id => !/^td\./.test(ma.get(id).name || ''));
const hexOf = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');

// ── 颜色字段定位（与构建脚本同一口径，独立实现避免互证） ─────────────────
function colorFields(r) {
  const out = [];
  (function w(f, d) {
    if (d > 30) return;
    if (f.wt === 2 && f.sub && f.field === 84) {
      const c = f.sub.find(x => x.field === 502 && x.wt === 0);
      if (c) out.push({ kind: 'fill', obj: c });
    }
    if (f.wt === 2 && f.sub && f.field === 75) {
      const c = f.sub.find(x => x.field === 504 && x.wt === 0);
      if (c) out.push({ kind: 'font', obj: c });
    }
    if (f.sub) for (const s of f.sub) w(s, d + 1);
  })(r.field, 0);
  return out;
}
const colorPairs = [];
for (const r of B.recs.filter(r => /^td\./.test(r.name || ''))) {
  const a = ma.get(r.id);
  for (const c of colorFields(r)) colorPairs.push({ id: r.id, name: r.name, ...c });
}
const beforeColors = new Map(), afterColors = new Map();
for (const c of colorPairs) {
  beforeColors.set(c.id + ':' + c.obj.field, null); // 占位，实际逐条比对在下面
}
// 以记录为单位，把 B 的颜色还原成 A 的值，再比对整条记录字节
let colorOnly = true, colorChanges = 0;
const details = [];
for (const id of changed) {
  const ra = ma.get(id), rb = mb.get(id);
  const ca = colorFields(ra), cb = colorFields(rb);
  if (ca.length !== cb.length) { colorOnly = false; details.push('颜色字段数量不符 ' + rb.name); continue; }
  const saved = cb.map(c => c.obj.num);
  for (let i = 0; i < cb.length; i++) cb[i].obj.num = ca[i].obj.num;
  const reverted = enc(rb).toString('hex') === enc(ra).toString('hex');
  for (let i = 0; i < cb.length; i++) cb[i].obj.num = saved[i];
  if (!reverted) { colorOnly = false; details.push('除颜色外有改动 ' + rb.name); }
  for (let i = 0; i < cb.length; i++) if (ca[i].obj.num !== saved[i]) {
    colorChanges++;
    details.push({ name: rb.name, kind: cb[i].kind, from: hexOf(ca[i].obj.num), to: hexOf(saved[i]) });
  }
}
const detailChanges = details.filter(d => typeof d === 'object');
const detailErrors = details.filter(d => typeof d === 'string');

// ── 文本 / 几何 / 图元 id / 旋转 逐记录比对 ──────────────────────────────
function snapshot(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const rot = st?.sub?.find(q => q.field === 508)?.sub?.[0]?.f ?? null;
  const texts = [], images = [];
  (function w(f, d) {
    if (d > 30) return;
    if (f.field === 501 && f.wt === 2 && f.payload) texts.push(f.payload.toString('utf8'));
    if (f.field === 84 && f.sub) {
      const im = f.sub.find(x => x.field === 503 && x.wt === 0);
      if (im) images.push(Number(im.num));
    }
    if (f.sub) for (const q of f.sub) w(q, d + 1);
  })(r.field, 0);
  return JSON.stringify([p ? [pairValue(p, 0), pairValue(p, 1)] : null,
    s ? [pairValue(s, 0), pairValue(s, 1)] : null, rot, texts, images]);
}
const geomTextChanged = [...ma.keys()].filter(id => mb.has(id) && snapshot(ma.get(id)) !== snapshot(mb.get(id)));

// ── 脚本 / 层序 / childList / 悬空父 / 背景 ──────────────────────────────
const sA = findScriptLeaf(A).buf.toString('utf8'), sB = findScriptLeaf(B).buf.toString('utf8');
const scriptSame = sA === sB && Buffer.byteLength(sB) === 636689;
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
const idOf = (g, f) => g.recs.find(q => q.field === f)?.id;
const rtA = A.tree.find(q => q.field === 9), rtB = B.tree.find(q => q.field === 9);
const idsA = rtA.sub.map(f => idOf(A, f)).filter(id => id != null);
const idsB = rtB.sub.map(f => idOf(B, f)).filter(id => id != null);
const recTopSame = idsA.length === idsB.length && idsA.every((id, i) => id === idsB[i]);
const order = new Map(); rtB.sub.forEach((f, i) => order.set(f, i));
const childListOk = B.recs.filter(r => r.name === 'clue').every(root => {
  const cl = findChildListTop(root.field.sub);
  const list = cl ? (asIdList(cl.payload, true) || []).filter(id => mb.has(id)) : [];
  return list.every((id, j) => j === 0 || order.get(mb.get(list[j - 1]).field) <= order.get(mb.get(id).field));
});
const idsSetB = new Set(mb.keys());
const dangling = B.recs.filter(r => r.parentId != null && !idsSetB.has(r.parentId)
  && !(ma.has(r.id) && ma.get(r.id).parentId === r.parentId && !new Set(ma.keys()).has(r.parentId))).length;

// ── 目标色断言 ───────────────────────────────────────────────────────────
const colorOf = (name, kind = 'fill') => {
  const r = B.recs.find(q => q.name === name); if (!r) return null;
  const c = colorFields(r).find(q => q.kind === kind); return c ? hexOf(c.obj.num) : null;
};
const targets = {
  'td.home.bg': ['#FFFFF5D6'], 'td.l1.bg': ['#FFFFF5D6'], 'td.l2.bg': ['#FFFFF5D6'],
  'td.home.board.svg.1': ['#FF87533E'], 'td.l1.board.svg.1': ['#FF87533E'], 'td.l2.board.svg.1': ['#FF87533E'],
  'td.home.closex': ['#FF47271A'], 'td.l1.closex': ['#FF47271A'], 'td.l2.closex': ['#FF47271A'],
  'td.home.page.1.nextbg': ['#FFD84511'], 'td.l1.page.1.nextbg': ['#FFD84511'],
  'td.l1.page.1.step.1': ['#FF87533E'], 'td.l1.page.1.step.2': ['#FFA0672F'],
  'td.l1.page.1.stepn.1.bg': ['#FFF7A530'], 'td.l1.page.1.stepn.2.bg': ['#FFDDB551'],
  'td.l1.page.1.main': ['#FFC9AC6D'], 'td.l1.page.1.clue': null,
  'td.home.page.1.title': null,
};
const targetResult = {}; let targetsOk = true;
for (const [name, want] of Object.entries(targets)) {
  const got = colorOf(name, /title$/.test(name) ? 'font' : 'fill');
  targetResult[name] = { got, want };
  if (want && got !== want[0]) targetsOk = false;
}
// 关键页标签色（逐页酌情）
const tagColors = {};
for (const tag of ['l1', 'l2']) {
  const n = tag === 'l1' ? 8 : 4;
  for (let i = 1; i <= n; i++) tagColors[`${tag}.page.${i}.tagbg`] = colorOf(`td.${tag}.page.${i}.tagbg`);
}
const tagOk = tagColors['l1.page.8.tagbg'] === '#FFF7A530'
  && tagColors['l1.page.1.tagbg'] === '#FF9D9657'
  && tagColors['l2.page.1.tagbg'] === '#FF93381D'
  && tagColors['l2.page.4.tagbg'] === '#FFD84511';

// 新颜色必须全部来自规格调色板（含保留 alpha 的半透明映射）
const allowed = new Set([
  ...Object.values(SPEC.fillMap), ...Object.values(SPEC.fontMap),
  ...SPEC.rules.map(r => r.to),
  ...Object.keys(SPEC.fillMap), ...Object.keys(SPEC.fontMap),
]);
const unexpectedColors = [...new Set(detailChanges.map(d => d.to).filter(c => !allowed.has(c)))];

// 逐页统计
const perPage = {};
for (const d of detailChanges) {
  const m = d.name.match(/^(td\.(?:home|l1|l2)\.page\.\d+)/);
  const k = m ? m[1] : d.name.replace(/^(td\.(?:home|l1|l2)).*/, '$1(共享层)');
  if (!perPage[k]) perPage[k] = { fill: 0, font: 0 };
  perPage[k][d.kind]++;
}
const pagesTouched = Object.keys(perPage).filter(k => k.includes('.page.')).length;

const checks = {
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changed: changed.length,
  changedExtra: changedExtra.map(id => ma.get(id).name),
  colorFieldsChanged: colorChanges, colorOnlyChanges: colorOnly,
  colorDiffErrors: detailErrors,
  geomTextChanged: geomTextChanged.length,
  scriptSame, scriptBytes: [Buffer.byteLength(sA), Buffer.byteLength(sB)],
  policeV19Descendants: bgA.size, bgChanged: bgChanged.length,
  recTopSame, childListOk, dangling,
  targetsOk, targetResult, tagColors, tagOk,
  unexpectedColors, pagesTouched, perPage: Object.fromEntries(Object.entries(perPage).sort()),
  changelogItems: CHANGELOG.total,
};
checks.verdict = added.length === 0 && removed.length === 0
  && changed.length === 2160 && changedExtra.length === 0
  && colorChanges === 2161 && colorOnly && detailErrors.length === 0
  && geomTextChanged.length === 0 && scriptSame
  && bgChanged.length === 0 && recTopSame && childListOk && dangling === 0
  && targetsOk && tagOk && unexpectedColors.length === 0
  && pagesTouched === 13 && checks.changelogItems === 2161;
fs.writeFileSync(path.join(DIR, '681_结构校验.json'), JSON.stringify(checks, null, 2));
console.log(JSON.stringify({ verdict: checks.verdict, records: [A.recs.length, B.recs.length],
  added: added.length, removed: removed.length, changed: changed.length,
  colorFieldsChanged: colorChanges, colorOnlyChanges: colorOnly,
  geomTextChanged: geomTextChanged.length, scriptSame, bgChanged: bgChanged.length,
  recTopSame, childListOk, dangling, targetsOk, tagOk,
  unexpectedColors: unexpectedColors.length, pagesTouched }, null, 2));
if (!checks.verdict) process.exit(2);
