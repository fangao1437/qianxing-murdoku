// 681 · 基于 680 存档，把 13 页教程弹窗的填充色 / 字色整体换成设计稿暖色档案纸风格
//   输入  ../680_网格纸与家具层序/680_网格纸与家具层序.gil（7431 条）
//   输出  681_教程弹窗配色.gil（7431 条，0 新增 / 0 删除，仅改 td.* 的颜色字段）
//   规格  681_配色规格.json（palette / fillMap / fontMap / rules，规则按顺序首个命中）
//   用法  FORCE=1 node 构建681.mjs   /   node 构建681.mjs --dry
//
// ★ 颜色字段只有两处（全量扫描 2278 条 td.* 记录实测，见 681_变更与验收.md）：
//     fill = /502/505/503/84/502  (图元填充色 ARGB)
//     font = /502/505/503/75/504  (文字 fontColor ARGB)
//   每条记录恰好 1 个颜色字段（1 条同时有 fill+font），共 1202 + 959 = 2161 处。
// ★ 本轮不碰：几何(504/505)、旋转(508)、文本(510/501)、图元 id(503)、层序、childList、内嵌 Lua。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const INPUT = path.join(REPO, '680_网格纸与家具层序/680_网格纸与家具层序.gil');
const OUTPUT = path.join(DIR, '681_教程弹窗配色.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '681_配色规格.json'), 'utf8'));
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const BASE_SHA = sha(INPUT);
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { isHiddenRecord } = await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const scriptLeaf = findScriptLeaf(g);
const scriptBefore = Buffer.from(scriptLeaf.buf);
const recTop = g.tree.find(f => f.field === 9);
const orderBefore = recTop.sub.slice();
const fieldToIdBefore = new Map(g.recs.map(r => [r.field, r.id]));
const idOrderBefore = orderBefore.map(f => fieldToIdBefore.get(f)).filter(id => id != null);
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));

// ── 规则编译：逐页/分组规则优先于全局规则 ─────────────────────────────────
const compiled = SPEC.rules.map(r => ({
  ...r,
  scopeRe: r.scope === 'all' ? null : new RegExp(r.scope),
  nameRe: new RegExp(r.name),
}));
const orderedRules = [
  ...compiled.filter(r => r.scopeRe),     // 逐页规则先命中
  ...compiled.filter(r => !r.scopeRe),    // 全局角色规则
];
const hexOf = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const bigOf = h => BigInt('0x' + h.slice(1));

// 找出一条记录里所有颜色字段（返回字段对象本身，改它的 num 即可）
function colorFields(record) {
  const out = [];
  function walk(f, d = 0) {
    if (d > 30) return;
    if (f.wt === 2 && f.sub) {
      if (f.field === 84) {
        const c = f.sub.find(x => x.field === 502 && x.wt === 0);
        if (c) out.push({ kind: 'fill', obj: c });
      } else if (f.field === 75) {
        const c = f.sub.find(x => x.field === 504 && x.wt === 0);
        if (c) out.push({ kind: 'font', obj: c });
      }
    }
    if (f.sub) for (const s of f.sub) walk(s, d + 1);
  }
  walk(record.field, 0);
  return out;
}

const changes = [];
const unmapped = [];
const ruleHits = new Map();
const tdRecs = g.recs.filter(r => /^td\./.test(r.name || ''));
for (const r of tdRecs) {
  for (const { kind, obj } of colorFields(r)) {
    const old = hexOf(obj.num);
    const rule = orderedRules.find(q =>
      (q.scopeRe ? q.scopeRe.test(r.name) : true) && q.kind === kind &&
      q.nameRe.test(r.name) && q.from === old);
    const map = kind === 'fill' ? SPEC.fillMap : SPEC.fontMap;
    const to = rule ? rule.to : map[old];
    if (!to) { unmapped.push({ name: r.name, kind, old }); continue; }
    if (to === old) continue;
    obj.num = bigOf(to);
    changes.push({ id: r.id, name: r.name, kind, old, to,
      rule: rule ? rule.id : (kind === 'fill' ? 'fillMap' : 'fontMap'), obj, was: bigOf(old) });
    if (rule) ruleHits.set(rule.id, (ruleHits.get(rule.id) || 0) + 1);
  }
}
if (unmapped.length) throw Error('存在未覆盖的颜色：' + JSON.stringify(unmapped.slice(0, 8)));
if (!changes.length) throw Error('没有发生任何颜色变更');

// ── 闸门 ①：只改了颜色字段（把颜色逐条还原后，所有记录必须与 680 逐字节相同） ──
for (const c of changes) c.obj.num = c.was;
for (const [id, before] of beforeBytes) {
  const after = encodeMsg([byId.get(id).field]);
  if (!before.equals(after)) throw Error('除颜色外还有字段被改动 #' + id + ' ' + (byId.get(id).name || ''));
}
for (const c of changes) c.obj.num = bigOf(c.to);

// ── 闸门 ②：几何 / 文本 / 层序 / 脚本 / 背景资产全部不变 ─────────────────
const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const changedIds = [...beforeBytes.keys()].filter(id => !beforeBytes.get(id).equals(afterBytes.get(id)));
const changedExtra = changedIds.filter(id => !/^td\./.test(byId.get(id).name || ''));
if (changedExtra.length) throw Error('非教程记录被改动：' + changedExtra.slice(0, 5).map(id => byId.get(id).name).join(','));
if (!scriptLeaf.buf.equals(scriptBefore)) throw Error('内嵌 Lua 被改动');
if (recTop.sub.length !== orderBefore.length || recTop.sub.some((f, i) => f !== orderBefore[i]))
  throw Error('recTop 层序被改动');

// v19 背景子树（police-v19）零改动
const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
for (const id of bgIds) if (!beforeBytes.get(id).equals(afterBytes.get(id))) throw Error('v19 背景被改动');

// 几何与文本抽出来做独立比对（双保险，不依赖字节还原）
function snapshot(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const texts = [];
  (function w(f, d = 0) {
    if (d > 30) return;
    if (f.field === 501 && f.wt === 2 && f.payload) texts.push(f.payload.toString('utf8'));
    if (f.sub) for (const q of f.sub) w(q, d + 1);
  })(r.field, 0);
  return JSON.stringify([p ? [pairValue(p, 0), pairValue(p, 1)] : null,
    s ? [pairValue(s, 0), pairValue(s, 1)] : null, texts]);
}
// 由于是在同一棵树上原地改的颜色，几何/文本内存值未动；写盘后由校验脚本再读一次比对。

// ── 写盘 ─────────────────────────────────────────────────────────────────
if (DRY) {
  const perPage = {};
  for (const c of changes) {
    const m = c.name.match(/^(td\.(?:home|l1|l2)\.page\.\d+)/);
    const k = m ? m[1] : c.name.replace(/^(td\.(?:home|l1|l2)).*/, '$1(共享层)');
    perPage[k] = (perPage[k] || 0) + 1;
  }
  console.log(JSON.stringify({ dry: true, baseSha256: BASE_SHA,
    records: [beforeBytes.size, afterBytes.size], colorFieldsChanged: changes.length,
    recordsChanged: changedIds.length, fill: changes.filter(c => c.kind === 'fill').length,
    font: changes.filter(c => c.kind === 'font').length,
    ruleHits: Object.fromEntries([...ruleHits].sort()), unmapped: unmapped.length,
    perPage, scriptBytes: scriptBefore.length }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '681 tutorial popup recolor to warm clipboard/paper design palette (13 pages)',
  expectRecs: afterBytes.size,
  assert(t) {
    const ids = new Set(t.recs.map(r => r.id));
    if (t.recs.length !== afterBytes.size) return '记录数不符';
    for (const r of t.recs) {
      const want = afterBytes.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录回读不符 #' + r.id + ' ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const leaf = findScriptLeaf(t);
    if (!leaf.buf.equals(scriptBefore)) return '内嵌 Lua 变化';
    const rt = t.tree.find(q => q.field === 9);
    const fieldToIdAfter = new Map(t.recs.map(r => [r.field, r.id]));
    const idOrderAfter = rt.sub.map(f => fieldToIdAfter.get(f)).filter(id => id != null);
    if (idOrderAfter.length !== idOrderBefore.length || idOrderAfter.some((id, i) => id !== idOrderBefore[i]))
      return 'recTop 层序变化';
    const idx = new Map(); rt.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});

// ── 审计 ─────────────────────────────────────────────────────────────────
const perPage = {};
for (const c of changes) {
  const m = c.name.match(/^(td\.(?:home|l1|l2)\.page\.\d+)/);
  const k = m ? m[1] : c.name.replace(/^(td\.(?:home|l1|l2)).*/, '$1(共享层)');
  if (!perPage[k]) perPage[k] = { fill: 0, font: 0, rules: new Set() };
  perPage[k][c.kind]++;
  perPage[k].rules.add(c.rule);
}
const perPageOut = Object.fromEntries(Object.entries(perPage).sort()
  .map(([k, v]) => [k, { fill: v.fill, font: v.font, total: v.fill + v.font, rules: [...v.rules].sort() }]));
const hist = (key) => {
  const m = new Map();
  for (const c of changes) m.set(c[key], (m.get(c[key]) || 0) + 1);
  return Object.fromEntries([...m].sort((a, b) => b[1] - a[1]));
};
const audit = {
  version: 681, name: '681 tutorial popup recolor', date: new Date().toISOString().slice(0, 10),
  base: { file: path.basename(INPUT), sha256: BASE_SHA, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: afterBytes.size, scriptBytes: scriptBefore.length },
  spec: {
    designRefs: SPEC.designRefs, palette: SPEC.palette,
    colorFieldPaths: SPEC.colorFieldPaths,
    rules: SPEC.rules.length, pageAdjustments: SPEC.pageAdjustments, limitations: SPEC.limitations,
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: afterBytes.size,
    added: 0, removed: 0, recordsChanged: changedIds.length,
    colorFieldsChanged: changes.length, fill: changes.filter(c => c.kind === 'fill').length,
    font: changes.filter(c => c.kind === 'font').length, unmapped: 0 },
  ruleHits: Object.fromEntries([...ruleHits].sort()),
  mapHits: { fillMap: changes.filter(c => c.rule === 'fillMap').length,
    fontMap: changes.filter(c => c.rule === 'fontMap').length },
  beforeColors: hist('old'), afterColors: hist('to'), perPage: perPageOut,
  guarantees: ['仅 td.* 记录被改', '颜色逐条还原后与 680 逐字节相同 ⇒ 几何/文本/图元/旋转零改动',
    '内嵌 Lua 逐字节相同', 'recTop 层序与 childList 同序', 'police-v19 背景子树零改动', '0 新增 / 0 删除'],
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '681_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
fs.writeFileSync(path.join(DIR, '681_逐条改色清单.json'), JSON.stringify({
  base: audit.base.file, baseSha256: BASE_SHA, total: changes.length,
  items: changes.map(({ id, name, kind, old, to, rule }) => ({ id, name, kind, from: old, to, rule })),
}, null, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: [audit.counts.recordsBefore, audit.counts.recordsAfter],
  colorFieldsChanged: changes.length, recordsChanged: changedIds.length,
  ruleHits: Object.keys(audit.ruleHits).length, status: 'APPLIED' }, null, 2));
