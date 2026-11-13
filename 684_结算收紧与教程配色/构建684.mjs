// 684 · 基于 683 真机反馈整改
//   ① 提交后/结算弹窗：收紧四键间距 + 整体上移 + 加宽 5 字 label，按钮不再压边框、文字不再被裁
//   ② 背景放大镜：删 100120 官方小图标，按 12.png 用纯图元精确复刻粗实心环 + 45° 粗短柄
//   ③ 首页教程五张规则卡染色统一，统一色严格取 4.png 的 #C9AC6D
//   输入 ../683_弹窗细线与四键/683_弹窗细线与四键.gil（7621 条）
//   用法 FORCE=1 node 构建684.mjs   /   node 构建684.mjs --dry
//
// ★ 口径
//   · 放大镜新层挂在 frame（DECOR 容器）下，插在 inner.face 之后；不碰内嵌 Lua。
//   · 柄用 5 枚 100002 阶梯圆沿 45° 排列，避免依赖矩形负旋转角（历史真机有不出图记录）。
//   · 只改首页教程 td.home.page.1.rule.5；其余 12 页教程与首页其它层保持 683。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '684_规格.json'), 'utf8'));
const INPUT = path.join(REPO, SPEC.base.file);
const OUTPUT = path.join(DIR, '684_结算收紧与教程配色.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
if (sha(INPUT) !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, writeVarint, stateBlocks, pairOf, pairValue, setPair, cloneField,
  ensureChildListTop, findChildListTop, asIdList, setChildList, textsOf, recordsOf } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const recTop = g.tree.find(f => f.field === 9);
const orderOf = () => { const m = new Map(); recTop.sub.forEach((f, i) => m.set(f, i)); return m; };
const scriptBefore = Buffer.from(findScriptLeaf(g).buf);
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));
let maxId = BigInt(g.maxId);
const added = [], deleted = [], modified = new Set(), newLayers = [], changes = [];
const created = new Map();
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const big = h => BigInt('0x' + h.slice(1));

// ── 字段工具（沿用 682/683 构建器口径） ───────────────────────────────────
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
const states = r => stateBlocks(r.field.sub, []);
const imgParts = r => ns(r.field, [505, 503, 84]);
function firstFill(r) {
  for (const p of imgParts(r)) {
    const c = p.sub.find(x => x.field === 502 && x.wt === 0);
    if (c) return c;
  }
  return null;
}
function setGeomLocal(r, dx, dyUp, w, h) {
  for (const st of states(r)) {
    const p = pairOf(st, 504), s = pairOf(st, 505);
    if (!p || !s) throw Error('几何字段缺失 ' + r.name);
    setPair(p, dx, dyUp); setPair(s, w, h);
  }
  modified.add(r.name);
}
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function makeLayer(L, parent, key) {
  const proto = R('td.home.page.1.help619.icon');   // 纯图元：有 84 无 75
  const f = cloneField(proto.field);
  const id = Number(++maxId);
  remap(f.sub, proto.id, id);
  const nameLeaf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nameLeaf) throw Error('克隆原型缺名字叶子');
  nameLeaf.payload = Buffer.from(L.name); nameLeaf.len = nameLeaf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl0 = findChildListTop(f.sub); if (cl0) setChildList(cl0, []);
  setHiddenRecord(f, false);
  const rec = { id, name: L.name, parentId: parent.id, field: f };
  g.recs.push(rec); byId.set(id, rec); byName.set(L.name, rec);
  added.push(rec);
  if (key) created.set(key, rec);
  setGeomLocal(rec, L.dx || 0, L.dy || 0, L.w, L.h);
  for (const p of imgParts(rec)) {
    setNum(p, 502, Number(big(L.color) & 0xFFFFFFFFn));
    setNum(p, 503, L.imageId);
    setNum(p, 504, 1);                              // 使用染色
  }
  newLayers.push({ key: key || L.name, name: L.name, parent: parent.name,
    dx: L.dx || 0, dy: L.dy || 0, w: L.w, h: L.h, color: L.color, imageId: L.imageId, rule: L.rule || '' });
  return rec;
}
function insertAfter(anchor, recs) {
  const i = recTop.sub.indexOf(anchor.field);
  if (i < 0) throw Error('recTop 锚点丢失 ' + anchor.name);
  recTop.sub.splice(i + 1, 0, ...recs.map(r => r.field));
}
function syncChildList(parent) {
  const ord = orderOf();
  const ids = g.recs.filter(r => r.parentId === parent.id)
    .sort((a, b) => (ord.get(a.field) ?? 1e9) - (ord.get(b.field) ?? 1e9)).map(r => r.id);
  setChildList(ensureChildListTop(parent), ids);
  modified.add(parent.name);
}
const touchedParents = new Set();
const touch = p => touchedParents.add(p);
function syncAll() { for (const p of touchedParents) syncChildList(p); }
function removeRecord(r, tag) {
  const i = recTop.sub.indexOf(r.field);
  if (i < 0) throw Error('记录不在 recTop ' + r.name);
  recTop.sub.splice(i, 1);
  g.recs = g.recs.filter(q => q.id !== r.id);
  byId.delete(r.id); byName.delete(r.name);
  deleted.push({ id: r.id, name: r.name, tag });
}

// ═══════════════════════════════════════════════════════════════════════
// A. 提交后/结算弹窗：收紧间距 + 上移 + 加宽 label
// ═══════════════════════════════════════════════════════════════════════
const RP = SPEC.resultPopup;
RP.buttons.names.forEach((n, i) => {
  const r = R(n), st = states(r)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  const y0 = pairValue(p, 1), w = pairValue(s, 0), h = pairValue(s, 1);
  if (Math.abs(y0 - RP.buttons.beforeY[i]) > 0.01) throw Error('结算四键基准不符 ' + n + ' = ' + y0);
  setGeomLocal(r, pairValue(p, 0), RP.buttons.afterY[i], w, h);
  changes.push({ name: n, rule: 'A 收紧间距+上移', fromY: y0, toY: RP.buttons.afterY[i] });
});
for (const n of RP.labels.names) {
  const label = g.recs.find(r => r.name === 'label' && r.parentId === R(n).id);
  if (!label) throw Error('缺 label ' + n);
  const st = states(label)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  const w0 = pairValue(s, 0);
  if (Math.abs(w0 - RP.labels.widthBefore) > 0.01) throw Error('label 基准宽度不符 ' + n + ' = ' + w0);
  setGeomLocal(label, pairValue(p, 0), pairValue(p, 1), RP.labels.widthAfter, pairValue(s, 1));
  changes.push({ name: n + '/label', rule: 'A 加宽让 5 字文本完整', fromW: w0, toW: RP.labels.widthAfter });
}
{
  const cd = R(RP.countdown.name), st = states(cd)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  if (Math.abs(pairValue(p, 1) - RP.countdown.beforeY) > 0.01) throw Error('结算倒计时基准不符');
  setGeomLocal(cd, pairValue(p, 0), RP.countdown.afterY, pairValue(s, 0), pairValue(s, 1));
  changes.push({ name: RP.countdown.name, rule: 'A 倒计时移进内页', fromY: RP.countdown.beforeY, toY: RP.countdown.afterY });
}

// ═══════════════════════════════════════════════════════════════════════
// B. 背景放大镜：删 100120 小图标，按 12.png 用纯图元精确复刻
// ═══════════════════════════════════════════════════════════════════════
const G = SPEC.glass;
const glassColor = '#FF' + G.refGeometry.color.slice(1);
const paperColor = '#FF' + G.refGeometry.paperColor.slice(1);
for (const F of G.frames) {
  const popup = R(F.key);
  const frameContainer = g.recs.find(r => r.name === 'frame' && r.parentId === popup.id);
  if (!frameContainer) throw Error('缺 frame 容器 ' + F.key);
  const oldGlass = R('art683.' + F.key + '.frame.glass');
  if (oldGlass.parentId !== frameContainer.id) throw Error('683 放大镜父级异常 ' + F.key);
  removeRecord(oldGlass, 'B 删 100120 官方小图标');
  touch(frameContainer);

  const [cx, cy] = F.center, [hx0, hy0] = F.handleStart, [sx, sy] = F.handleStep;
  const L = [
    { suffix: 'ring', dx: cx, dy: cy, w: F.ring, h: F.ring, color: glassColor, imageId: 100002, rule: 'B 12.png 粗实心外环' },
    { suffix: 'hole', dx: cx, dy: cy, w: F.hole, h: F.hole, color: paperColor, imageId: 100002, rule: 'B 挖空（内页纸色）' },
  ];
  for (let j = 0; j < F.handleCount; j++)
    L.push({ suffix: 'handle.' + j, dx: hx0 + j * sx, dy: hy0 + j * sy,
      w: F.handleDot, h: F.handleDot, color: glassColor, imageId: 100002, rule: 'B 45° 粗短柄阶梯' + j });
  const anchor = R('art683.' + F.key + '.frame.inner.face');
  const recs = L.map(q => makeLayer({
    name: 'art684.' + F.key + '.frame.glass.' + q.suffix, dx: q.dx, dy: q.dy,
    w: q.w, h: q.h, color: q.color, imageId: q.imageId, rule: q.rule,
  }, frameContainer, 'glass:' + F.key + ':' + q.suffix));
  insertAfter(anchor, recs);
}

// ═══════════════════════════════════════════════════════════════════════
// C. 首页教程五卡染色统一 + 最深分区严格取设计图色
// ═══════════════════════════════════════════════════════════════════════
const H = SPEC.homeTutorial;
{
  const r = R(H.unify.name), o = firstFill(r);
  const from = hex(o.num);
  if (from !== H.unify.from) throw Error('第 5 卡基准色不符 ' + from);
  o.num = big(H.unify.to);
  modified.add(r.name);
  changes.push({ name: r.name, rule: 'C 五卡染色统一（严格取 4.png #C9AC6D）', from, to: H.unify.to });
  // 核对：五卡与其边框/编号圆底必须已严格取设计图色
  for (let i = 1; i <= 5; i++) {
    const card = R('td.home.page.1.rule.' + i), c = firstFill(card);
    if (hex(c.num) !== H.strictDesignColor.value) throw Error('第 ' + i + ' 卡颜色未统一 ' + hex(c.num));
    if (hex(firstFill(R('td.home.page.1.rule.' + i + '.border')).num) !== '#FF6C402E')
      throw Error('第 ' + i + ' 卡边框偏离 4.png 外框 #6C402E');
    if (hex(firstFill(R('td.home.page.1.rule.' + i + '.num.bg')).num) !== '#FF47271A')
      throw Error('第 ' + i + ' 卡编号圆底偏离设计稿深墨 #47271A');
  }
}

// 统一重算所有受影响父级 childList
syncAll();
g.recs = recordsOf(g.tree);

// ═══════════════════════════════════════════════════════════════════════
// 闸门
// ═══════════════════════════════════════════════════════════════════════
if (!findScriptLeaf(g).buf.equals(scriptBefore)) throw Error('内嵌 Lua 被改动');
const idsNow = new Set(g.recs.map(r => r.id));
for (const d of deleted) if (idsNow.has(d.id)) throw Error('删除未生效 ' + d.name);
for (const r of g.recs) if (r.parentId != null && !idsNow.has(r.parentId) && !danglingBefore.has(r.id))
  throw Error('新增悬空父引用 ' + r.name);
const treeBytes = encodeMsg(g.tree);
for (const d of deleted) {
  const needle = Buffer.from(writeVarint(d.id));
  if (treeBytes.includes(needle)) throw Error('被删 ID 仍被引用 ' + d.name);
}
// 新增层逐条断言
for (const L of newLayers) {
  const r = created.get(L.key);
  if (!r) throw Error('新增层丢失 ' + L.key);
  const st = states(r)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  if (Math.abs(pairValue(p, 0) - L.dx) > 0.01 || Math.abs(pairValue(p, 1) - L.dy) > 0.01 ||
      Math.abs(pairValue(s, 0) - L.w) > 0.01 || Math.abs(pairValue(s, 1) - L.h) > 0.01)
    throw Error('新增层几何不符 ' + L.key);
  const o = firstFill(r);
  if (!o || hex(o.num) !== L.color) throw Error('新增层颜色不符 ' + L.key);
  const im = imgParts(r)[0]?.sub.find(q => q.field === 503 && q.wt === 0);
  if (!im || Number(im.num) !== L.imageId) throw Error('新增层图元不符 ' + L.key);
  if (isHiddenRecord(r.field)) throw Error('新增层被隐藏 ' + L.key);
  if (!idsNow.has(r.parentId)) throw Error('新增层父级异常 ' + L.key);
}
// 结算四键 / label / 放大镜层序
RP.buttons.names.forEach((n, i) => {
  if (Math.abs(pairValue(pairOf(states(R(n))[0], 504), 1) - RP.buttons.afterY[i]) > 0.01)
    throw Error('结算四键未按规格收紧 ' + n);
});
for (const F of G.frames) {
  const face = R('art683.' + F.key + '.frame.inner.face');
  const ord = orderOf();
  const ring = created.get('glass:' + F.key + ':ring');
  if (!(ord.get(face.field) < ord.get(ring.field))) throw Error('放大镜层序异常 ' + F.key);
  if (g.recs.some(r => r.name === 'art683.' + F.key + '.frame.glass')) throw Error('100120 未删净 ' + F.key);
}
// 旧记录改动白名单
const allowed = new Set();
for (const n of RP.buttons.names) { allowed.add(R(n).id); allowed.add(g.recs.find(r => r.name === 'label' && r.parentId === R(n).id).id); }
allowed.add(R(RP.countdown.name).id);
allowed.add(R(H.unify.name).id);
for (const F of G.frames) {
  const popup = R(F.key);
  allowed.add(g.recs.find(r => r.name === 'frame' && r.parentId === popup.id).id);
}
const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const changedOld = [...beforeBytes.keys()].filter(id =>
  afterBytes.has(id) && !beforeBytes.get(id).equals(afterBytes.get(id)));
const rogue = changedOld.filter(id => !allowed.has(id));
if (rogue.length) throw Error('存在非预期旧记录改动：' + rogue.slice(0, 6).map(id => byId.get(id)?.name || id).join(','));

if (DRY) {
  console.log(JSON.stringify({ dry: true, records: [beforeBytes.size, g.recs.length],
    added: added.length, removed: deleted.length, newLayers: newLayers.length,
    changedOldRecords: changedOld.length, rogue: rogue.length,
    resultY: RP.buttons.afterY, scriptBytes: scriptBefore.length }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '684 result popup tighten + 12.png magnifier replica + unified home tutorial cards',
  expectRecs: g.recs.length,
  assert(t) {
    const ids = new Set(t.recs.map(r => r.id));
    if (t.recs.length !== g.recs.length) return '记录数不符';
    for (const r of t.recs) {
      const want = afterBytes.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录回读不符 #' + r.id + ' ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 变化';
    const rt = t.tree.find(q => q.field === 9);
    const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => ord.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && ord.get(t.recs.find(q => q.id === list[i - 1]).field) > ord.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});
const audit = {
  version: 684, name: '684 result tighten + magnifier + tutorial colors', date: new Date().toISOString().slice(0, 10),
  base: { file: SPEC.base.file, sha256: sha(INPUT), records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: g.recs.length, scriptBytes: scriptBefore.length },
  spec: { measurements: SPEC.measurements, resultPopup: RP, glass: G, homeTutorial: H, limitations: SPEC.limitations },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: g.recs.length,
    added: added.length, removed: deleted.length, newLayers: newLayers.length,
    changedOldRecords: changedOld.length, rogue: rogue.length },
  changes, deleted,
  guarantees: ['内嵌 Lua 逐字节相同', '旧记录改动全部落在白名单（rogue=0）',
    '被删 2 个 100120 层 ID 全文 0 引用', '新增层几何/颜色/图元/显隐/父级逐条断言',
    '五卡颜色/边框/编号圆底逐条核对设计图色', '所有受影响父级 childList 按 recTop 重算'],
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '684_构建审计.json'), JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
fs.writeFileSync(path.join(DIR, '684_新增层清单.json'), JSON.stringify(newLayers, null, 2));
fs.writeFileSync(path.join(DIR, '684_逐条变更清单.json'), JSON.stringify(changes, null, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: [audit.counts.recordsBefore, audit.counts.recordsAfter],
  added: added.length, removed: deleted.length, newLayers: newLayers.length,
  changedOldRecords: changedOld.length, rogue: rogue.length, status: 'APPLIED' }, null, 2));
