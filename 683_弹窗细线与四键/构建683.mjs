// 683 · 基于 682 真机反馈整改
//   ① 返回/退出菜单四键垂直居中（整体下移 108）
//   ② 8 个四键的胶囊收进 DECOR 容器 art（修运行时被隐藏）+ 垫 2px 深棕描边，填充仍为首页同色 #FCECD4
//   ③ 通用边框补 12.png 的最外圈深墨细线 / 内页内圈深色细线 / 官方放大镜 100120 水印
//   ④ 删除首页纸右缘杂质矩形 art656.home.paper.edge
//   输入 ../682_弹窗边框与提示样式/682_弹窗边框与提示样式.gil（7582 条）
//   用法 FORCE=1 node 构建683.mjs   /   node 构建683.mjs --dry
//
// ★ 本轮最关键口径（别再踩）
//   · 内嵌 Lua 的 DECOR 表只豁免「短名」：label/bg/icon/face/art/frame/card/image/img/...
//     682 新增的 art682.*.capsule.* 是按钮的直接子控件且是完整长名，
//     被 Adapter:enforce_hidden_subtrees 逐个 SetVisible(false) ⇒ 真机只剩 label 文字。
//     683 把胶囊 6 层收进名为 art 的直接子容器：DECOR 命中后整个 if 块跳过，子树全部幸存。
//   · 最外圈深墨细线不能挂在 frame 容器下（会盖住容器自身的棕框），必须挂在
//     modal / help617 下、插在 frame 容器之前，且名字取 DECOR 短名 art。
//   · 放大镜直接用官方图元 100120（hex.hint 提示按钮图标），染色 #F9EFC7，不用拼圆+柄。
//   · 内嵌 Lua 本轮零改动；只改存档。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '683_规格.json'), 'utf8'));
const INPUT = path.join(REPO, SPEC.base.file);
const OUTPUT = path.join(DIR, '683_弹窗细线与四键.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const BASE_SHA = sha(INPUT);
if (BASE_SHA !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符');
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
const created = new Map();                 // 唯一 key -> 新增记录（避开 DECOR 短名重名）
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const big = h => BigInt('0x' + h.slice(1));
const argb = h => big('#FF' + h.slice(1));

// ── 字段工具（沿用 682 构建器口径） ───────────────────────────────────────
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
function setColor(r, hex8) {
  for (const p of imgParts(r)) setNum(p, 502, Number(big(hex8) & 0xFFFFFFFFn));
  modified.add(r.name);
}
function setGeomLocal(r, dx, dyUp, w, h) {
  for (const st of states(r)) {
    const p = pairOf(st, 504), s = pairOf(st, 505);
    if (!p || !s) throw Error('几何字段缺失 ' + r.name);
    setPair(p, dx, dyUp); setPair(s, w, h);
  }
  modified.add(r.name);
}
function shiftY(r, dy, rule) {
  let n = 0;
  for (const st of states(r)) {
    const p = pairOf(st, 504);
    if (!p) continue;
    const y = pairValue(p, 1);
    setPair(p, pairValue(p, 0), y + dy);
    n++;
  }
  if (!n) throw Error('找不到 504 位置对 ' + r.name);
  modified.add(r.name);
  changes.push({ name: r.name, rule, dy, states: n });
}
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function reparent(rec, parent) {
  const p = rec.field.sub.find(q => q.field === 504 && q.wt === 0);
  if (!p) throw Error('缺顶层父引用 ' + rec.name);
  p.num = BigInt(parent.id);
  rec.parentId = parent.id;
  modified.add(rec.name);
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
  g.recs.push(rec); byId.set(id, rec);
  if (!/^(art|frame|card|label|bg)$/.test(L.name)) byName.set(L.name, rec);
  added.push(rec);
  if (key) created.set(key, rec);
  setGeomLocal(rec, L.dx || 0, L.dy || 0, L.w, L.h);
  if (L.color) setColor(rec, L.color);
  if (L.imageId) for (const p of imgParts(rec)) setNum(p, 503, L.imageId);
  for (const p of imgParts(rec)) setNum(p, 504, 1);   // 使用染色
  newLayers.push({ key: key || L.name, name: L.name, parent: parent.name,
    dx: L.dx || 0, dy: L.dy || 0, w: L.w, h: L.h,
    color: L.color || null, imageId: L.imageId || 100001, rule: L.rule || '' });
  return rec;
}
function insertBefore(anchor, recs) {
  const i = recTop.sub.indexOf(anchor.field);
  if (i < 0) throw Error('recTop 锚点丢失 ' + anchor.name);
  recTop.sub.splice(i, 0, ...recs.map(r => r.field));
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

const P = SPEC.palette;

// ═══════════════════════════════════════════════════════════════════════
// A. 返回弹窗四键居中（只动退出菜单这一组，结算态 result.* 不动）
// ═══════════════════════════════════════════════════════════════════════
const C = SPEC.fourKeysCenter;
C.scope.forEach((n, i) => {
  const r = R(n);
  const st = states(r)[0], p = pairOf(st, 504);
  const y0 = pairValue(p, 1);
  if (Math.abs(y0 - C.beforeY[i]) > 0.01) throw Error('四键基准 y 不符 ' + n + ' = ' + y0);
  shiftY(r, C.dy, 'A 四键垂直居中');
  const y1 = pairValue(pairOf(states(r)[0], 504), 1);
  if (Math.abs(y1 - C.afterY[i]) > 0.01) throw Error('四键下移结果不符 ' + n);
});
for (const a of C.also) {
  const r = R(a.name);
  const st = states(r)[0], p = pairOf(st, 504);
  if (Math.abs(pairValue(p, 1) - a.beforeY) > 0.01) throw Error('倒计时基准不符 ' + a.name);
  shiftY(r, a.dy, 'A 倒计时移到四键下方留白（避免被新显示的胶囊盖住）');
  if (Math.abs(pairValue(pairOf(states(r)[0], 504), 1) - a.afterY) > 0.01)
    throw Error('倒计时落点不符 ' + a.name);
}

// ═══════════════════════════════════════════════════════════════════════
// B. 胶囊可见性：DECOR 容器 art + 2px 深棕描边（填充仍为首页同色）
// ═══════════════════════════════════════════════════════════════════════
const B = SPEC.capsule;
for (const bid of B.buttons) {
  const btn = R(bid);
  const caps = ['body', 'left', 'right'].map(s => R('art682.' + bid + '.capsule.' + s));
  const label = g.recs.find(r => r.name === 'label' && r.parentId === btn.id);
  if (!label) throw Error('缺 label ' + bid);

  // ① 透明 DECOR 容器，插在原胶囊层之前
  const groupKey = 'group:' + bid;
  const group = makeLayer({ name: 'art', dx: 0, dy: 0, w: B.containerGeom[0], h: B.containerGeom[1],
    color: '#00FFFFFF', imageId: 100001, rule: 'B DECOR 容器（运行时隐藏兜底豁免）' }, btn, groupKey);
  insertBefore(caps[0], [group]);

  // ② 描边 3 层：挂在容器下，插在容器之后（= 填充层之前）
  const O = B.outline, outlineColor = '#FF' + O.color.slice(1);
  const outlineSpecs = [
    { suffix: 'body', dx: O.body[2], w: O.body[0], h: O.body[1], imageId: O.imageRect },
    { suffix: 'left', dx: -O.circle[2], w: O.circle[0], h: O.circle[1], imageId: O.imageCircle },
    { suffix: 'right', dx: O.circle[2], w: O.circle[0], h: O.circle[1], imageId: O.imageCircle },
  ];
  const outlines = outlineSpecs.map(s => makeLayer({
    name: 'art683.' + bid + '.outline.' + s.suffix, dx: s.dx, dy: 0, w: s.w, h: s.h,
    color: outlineColor, imageId: s.imageId, rule: 'B 2px 深棕描边（轮廓可见）',
  }, group, 'outline:' + bid + ':' + s.suffix));
  insertAfter(group, outlines);

  // ③ 682 的 3 层填充改为容器子控件（几何是相对按钮的；容器中心=按钮中心，坐标不变）
  for (const c of caps) {
    reparent(c, group);
    changes.push({ name: c.name, rule: 'B 填充层改挂 DECOR 容器', parent: group.id });
  }
  touch(btn); touch(group);
}

// ═══════════════════════════════════════════════════════════════════════
// C. 通用边框：外圈深墨细线 / 内页内圈深色细线 / 官方放大镜水印
// ═══════════════════════════════════════════════════════════════════════
const A = SPEC.frameAdd;
for (const F of SPEC.frames) {
  const popup = R(F.key);                                  // help617 / modal
  const frameContainer = g.recs.find(r => r.name === 'frame' && r.parentId === popup.id);
  if (!frameContainer) throw Error('缺 frame 容器 ' + F.key);
  const light = R('art682.' + F.key + '.frame.light');
  const paper = R('art682.' + F.key + '.frame.paper');

  // ① 最外圈深墨细线：挂在弹窗下、frame 容器之前（不能挂 frame 下，否则盖住棕框）
  const rim = makeLayer({ name: 'art', dx: 0, dy: 0, w: F.rim[0], h: F.rim[1],
    color: '#FF' + A.rim.color.slice(1), imageId: A.rim.imageId, rule: 'C 外框最外圈深墨细线' },
    popup, 'rim:' + F.key);
  insertBefore(frameContainer, [rim]);
  touch(popup);

  // ② 内页内圈细线（2 层）+ ③ 官方放大镜水印：都挂 frame 容器下，paper 之后
  const innerLine = makeLayer({ name: 'art683.' + F.key + '.frame.inner.line', dx: 0, dy: 0,
    w: F.innerBorder[0], h: F.innerBorder[1], color: '#FF' + A.innerBorder.color.slice(1),
    imageId: A.innerBorder.imageId, rule: 'C 内页内圈深色细线' }, frameContainer, 'innerLine:' + F.key);
  const innerFace = makeLayer({ name: 'art683.' + F.key + '.frame.inner.face', dx: 0, dy: 0,
    w: F.innerFace[0], h: F.innerFace[1], color: '#FF' + P.paper.slice(1),
    imageId: A.innerFace.imageId, rule: 'C 内圈线内米白填充' }, frameContainer, 'innerFace:' + F.key);
  const glass = makeLayer({ name: 'art683.' + F.key + '.frame.glass', dx: F.glass.dx, dy: F.glass.dy,
    w: F.glass.w, h: F.glass.h, color: '#FF' + A.glass.color.slice(1),
    imageId: A.glass.imageId, rule: 'C 100120 官方放大镜水印' }, frameContainer, 'glass:' + F.key);
  insertAfter(paper, [innerLine, innerFace, glass]);
  touch(frameContainer);
}

// ═══════════════════════════════════════════════════════════════════════
// D. 首页杂质矩形删除（三处同步）
// ═══════════════════════════════════════════════════════════════════════
const IMP = SPEC.homeImpurity;
const imp = R(IMP.name);
if (imp.id !== IMP.id) throw Error('杂质矩形 ID 不符：' + imp.id);
const impParent = R(IMP.parent);
if (imp.parentId !== impParent.id) throw Error('杂质矩形父级不符');
const ii = recTop.sub.indexOf(imp.field);
if (ii < 0) throw Error('杂质矩形不在 recTop');
recTop.sub.splice(ii, 1);
g.recs = g.recs.filter(r => r.id !== imp.id);
byId.delete(imp.id); byName.delete(IMP.name);
deleted.push({ id: imp.id, name: IMP.name, parent: IMP.parent });
touch(impParent);

// 统一重算所有受影响父级的 childList
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

// 新增层逐条断言：几何 / 颜色 / 图元 / 显隐 / 父级
for (const L of newLayers) {
  const r = created.get(L.key);
  if (!r) throw Error('新增层丢失 ' + L.key);
  const st = states(r)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  if (Math.abs(pairValue(p, 0) - L.dx) > 0.01 || Math.abs(pairValue(p, 1) - L.dy) > 0.01 ||
      Math.abs(pairValue(s, 0) - L.w) > 0.01 || Math.abs(pairValue(s, 1) - L.h) > 0.01)
    throw Error('新增层几何不符 ' + L.key);
  const o = firstFill(r);
  if (L.color && (!o || hex(o.num) !== L.color)) throw Error('新增层颜色不符 ' + L.key + ' ' + (o ? hex(o.num) : 'null'));
  if (L.imageId) {
    const im = imgParts(r)[0]?.sub.find(q => q.field === 503 && q.wt === 0);
    if (!im || Number(im.num) !== L.imageId) throw Error('新增层图元不符 ' + L.key);
  }
  if (isHiddenRecord(r.field)) throw Error('新增层被隐藏 ' + L.key);
  if (r.parentId == null || !idsNow.has(r.parentId)) throw Error('新增层父级异常 ' + L.key);
}
// DECOR 容器短名与官方放大镜图元
for (const bid of B.buttons) {
  const grp = created.get('group:' + bid);
  if (grp.name !== 'art') throw Error('容器名不是 DECOR 短名 ' + bid);
  const caps = ['body', 'left', 'right'].map(s => byName.get('art682.' + bid + '.capsule.' + s));
  if (caps.some(c => !c || c.parentId !== grp.id)) throw Error('填充层未挂到容器 ' + bid);
}
for (const F of SPEC.frames) {
  const glass = created.get('glass:' + F.key);
  const im = imgParts(glass)[0]?.sub.find(q => q.field === 503 && q.wt === 0);
  if (!im || Number(im.num) !== 100120) throw Error('放大镜不是官方 100120 ' + F.key);
  if (created.get('rim:' + F.key).name !== 'art') throw Error('外圈细线未用 DECOR 短名 ' + F.key);
}
// 四键最终 y
C.scope.forEach((n, i) => {
  const y = pairValue(pairOf(states(R(n))[0], 504), 1);
  if (Math.abs(y - C.afterY[i]) > 0.01) throw Error('四键未居中 ' + n);
});

// 旧记录改动白名单：除以下记录外，全部与 682 逐字节相同
const allowed = new Set();
for (const n of [...C.scope, ...C.also.map(a => a.name)]) allowed.add(R(n).id);
for (const bid of B.buttons) {
  allowed.add(R(bid).id);
  for (const s of ['body', 'left', 'right']) allowed.add(R('art682.' + bid + '.capsule.' + s).id);
  allowed.add(created.get('group:' + bid).parentId);   // 按钮（childList）
}
for (const F of SPEC.frames) {
  const popup = R(F.key); allowed.add(popup.id);
  const fc = g.recs.find(r => r.name === 'frame' && r.parentId === popup.id);
  allowed.add(fc.id);
}
allowed.add(impParent.id);
const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const changedOld = [...beforeBytes.keys()].filter(id =>
  afterBytes.has(id) && !beforeBytes.get(id).equals(afterBytes.get(id)));
const rogue = changedOld.filter(id => !allowed.has(id));
if (rogue.length) throw Error('存在非预期旧记录改动：' + rogue.slice(0, 6).map(id => byId.get(id)?.name || id).join(','));

if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: BASE_SHA,
    records: [beforeBytes.size, g.recs.length], added: added.length, removed: deleted.length,
    newLayers: newLayers.length, changedOldRecords: changedOld.length, rogue: rogue.length,
    fourKeysY: C.afterY, scriptBytes: scriptBefore.length }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '683 popup four-key centering + visible capsules + frame hairlines + official magnifier + home impurity removal',
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
  version: 683, name: '683 popup hairlines and four-key', date: new Date().toISOString().slice(0, 10),
  base: { file: SPEC.base.file, sha256: BASE_SHA, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: g.recs.length, scriptBytes: scriptBefore.length },
  spec: { rootCause: SPEC.rootCause, palette: P, fourKeysCenter: C, capsule: B,
    frames: SPEC.frames, frameAdd: A, homeImpurity: IMP, limitations: SPEC.limitations },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: g.recs.length,
    added: added.length, removed: deleted.length, newLayers: newLayers.length,
    changedOldRecords: changedOld.length, rogue: rogue.length },
  changes, deleted,
  guarantees: ['内嵌 Lua 逐字节相同', '旧记录改动全部落在白名单（rogue=0）',
    '被删杂质矩形 ID 全文 0 引用', '新增层几何/颜色/图元/显隐/父级逐条断言',
    '所有受影响父级 childList 按 recTop 顺序重算', '胶囊层与外圈细线用 DECOR 短名豁免'],
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '683_构建审计.json'), JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
fs.writeFileSync(path.join(DIR, '683_新增层清单.json'), JSON.stringify(newLayers, null, 2));
fs.writeFileSync(path.join(DIR, '683_逐条变更清单.json'), JSON.stringify(changes, null, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: [audit.counts.recordsBefore, audit.counts.recordsAfter],
  added: added.length, removed: deleted.length, newLayers: newLayers.length,
  changedOldRecords: changedOld.length, rogue: rogue.length, status: 'APPLIED' }, null, 2));
