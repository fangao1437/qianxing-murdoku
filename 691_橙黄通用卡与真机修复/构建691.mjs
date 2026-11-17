// 691 · 基于 689 干净基准重建（690 靛蓝金方案弃用，保留为历史）
//   A 通用线索卡：橙黄 + 只留标题/正文 + 头像/letter 位留白（两套 clue 模板各 7 层）
//   B 地毯：停用整块模板，改由逐格 els 对齐格线
//   C 第6关门 9→5（每对区域留一个通道）
//   D 7×7：补 13 组 floor.cell（含 face），path_map / ensure_cells / cfg 同步
//   E 选关页记忆 + 门显隐去重
//   全部内嵌 Lua 补丁可反向逐字节还原 689；唯一写档通道 writeGil。
// 用法：FORCE=1 node 构建691.mjs  /  node 构建691.mjs --dry
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const INPUT = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_性能负载优化.gil');
const OUTPUT = path.join(DIR, '691_橙黄通用卡与真机修复.gil');
const LUA691 = path.join(DIR, '691_内嵌Lua_691.lua');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '691_设计与补丁.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf,
  findChildListTop, asIdList, setChildList } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const { setHiddenRecord, isHiddenRecord, imageTriple } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

// ── Lua 补丁（可逆） ──────────────────────────────────────────────────────
const P = SPEC.luaPatches;
function applyPatches(src) {
  let s = src;
  for (const p of P) {
    const n = s.split(p.old).length - 1;
    if (n !== p.count) throw Error(`补丁 ${p.name} 锚点数应为 ${p.count}，实得 ${n}`);
    s = s.split(p.old).join(p.new);
  }
  return s;
}
function revertPatches(s) {
  for (let i = P.length - 1; i >= 0; i--) {
    const p = P[i];
    const n = s.split(p.new).length - 1;
    if (n !== p.count) throw Error(`反向补丁 ${p.name} 新锚点数应为 ${p.count}，实得 ${n}`);
    s = s.split(p.new).join(p.old);
  }
  return s;
}

const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const s689 = findScriptLeaf(g).buf.toString('utf8');
const s691 = applyPatches(s689);
if (revertPatches(s691) !== s689) throw Error('Lua 补丁无法逐字节反向还原 689');

const recTop = g.tree.find(q => q.field === 9);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
let order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const ids0 = new Set(g.recs.map(r => r.id));
const danglingBefore = new Set(g.recs.filter(r => r.parentId != null && !ids0.has(r.parentId)).map(r => r.id));

// ── 字段工具 ──────────────────────────────────────────────────────────────
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt(hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function replaceTextPayload(f, from, to) {
  let hit = 0;
  (function walk(x) {
    if (x.wt === 2 && x.payload && x.payload.toString('utf8') === from) {
      x.payload = Buffer.from(to, 'utf8'); x.len = x.payload.length; x.isText = true; hit++;
    }
    for (const q of x.sub || []) walk(q);
  })(f);
  return hit;
}
function states(r) { return stateBlocks(r.field.sub, []); }
function reshape(r, o) {
  for (const st of states(r)) {
    setPair(pairOf(st, 504), o.x, o.y);
    setPair(pairOf(st, 505), o.w, o.h);
    if (o.rot != null) {
      let rf = st.sub.find(q => q.field === 508);
      if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
      rf.sub = [{ field: 3, wt: 5, f: o.rot }]; rf.payload = null; rf.len = 5;
    }
  }
  touch(r);
}
function setImage(r, imageId, color) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块：' + r.name);
  setNum(p, 502, colorOf(color)); setNum(p, 503, imageId); setNum(p, 504, 1);
  touch(r);
}
function setTextColor(r, color) {
  const p = ns(r.field, [505, 503, 75])[0];
  if (!p) throw Error('找不到文本块：' + r.name);
  setNum(p, 504, colorOf(color)); touch(r);
}
const touched = new Set(), modified = new Set(), added = [];
function touch(r) { touched.add(r.id); if (r.name) modified.add(r.name); }
let max = BigInt(g.maxId);
const PROTO_IMG = 'td.home.page.1.help619.icon';
function remapOne(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remapOne(q.sub, from, to, d + 1);
  }
}
function cloneLayer(parent, spec, proto, beforeId) {
  const f = cloneField(proto.field);
  const id = Number(++max);
  remapOne(f.sub, proto.id, id);
  if (replaceTextPayload(f, proto.name, spec.name) !== 1) throw Error('名字替换失败：' + spec.name);
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = (function find(ff) { return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  const idx = recTop.sub.findIndex(q => q === byId.get(beforeId)?.field);
  if (idx < 0) throw Error('beforeId 不在 recTop：' + beforeId);
  recTop.sub.splice(idx, 0, f);
  const r = { id, name: spec.name, parentId: parent.id, field: f };
  setImage(r, spec.imageId, spec.color);
  reshape(r, spec);
  setHiddenRecord(f, true);
  added.push(r); byId.set(id, r); touched.add(id);
  if (!isHiddenRecord(f)) throw Error('新层未隐藏：' + spec.name);
  return r;
}
function remapIds(f, idMap) {
  (function walk(x) {
    if (x.num != null && idMap.has(Number(x.num))) x.num = BigInt(idMap.get(Number(x.num)));
    for (const q of x.sub || []) walk(q);
  })(f);
  const cl = findChildListTop(f.sub || []);
  if (cl) {
    const ids = asIdList(cl.payload, true) || [];
    setChildList(cl, ids.map(i => idMap.get(i) ?? i));
  }
}

// ── A 通用线索卡（两套 clue 模板） ────────────────────────────────────────
const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (TPL.length !== 2) throw Error('clue 模板数不符：' + TPL.length);
const cardSummary = [];
for (const root of TPL) {
  const kid = nm => g.recs.find(r => r.parentId === root.id && r.name === nm);
  const gb = kid('gen.backrop'), gt = kid('gen.title'), gbody = kid('gen.body');
  if (!gb || !gt || !gbody) throw Error('gen.* 三件缺失 #' + root.id);
  if (!isHiddenRecord(gb.field) || !isHiddenRecord(gt.field) || isHiddenRecord(gbody.field))
    throw Error('gen.* 初始显隐形态不符 #' + root.id);
  const mb = SPEC.card.modify.find(m => m.name === 'gen.backrop');
  const mt = SPEC.card.modify.find(m => m.name === 'gen.title');
  const md = SPEC.card.modify.find(m => m.name === 'gen.body');
  setImage(gb, mb.imageId, mb.color); reshape(gb, mb);
  setTextColor(gt, mt.textColor);
  reshape(gbody, md); setTextColor(gbody, md.textColor);
  const protoImg = byName.get(PROTO_IMG);
  if (!protoImg) throw Error('图片原型缺失');
  for (const spec of SPEC.card.layers) cloneLayer(root, spec, protoImg, gt.id);
  cardSummary.push({ rootId: root.id, genBackropId: gb.id, layers: SPEC.card.layers.map(s => s.name) });
}

// ── D 7×7 地板补齐 ────────────────────────────────────────────────────────
const bf = g.recs.find(r => r.name === 'board.floors');
if (!bf) throw Error('找不到 board.floors');
const floorRoots = [];
function copyFloorCell(srcName, dstName) {
  const root = byName.get(srcName);
  if (!root || root.parentId !== bf.id) throw Error('地板原型缺失：' + srcName);
  const family = [root, ...g.recs.filter(r => r.parentId === root.id)];
  const idMap = new Map(family.map(r => [r.id, Number(++max)]));
  let insertAt = recTop.sub.findIndex(f => f === root.field) + 1;
  for (const r of family) {
    const f = cloneField(r.field);
    remapIds(f, idMap);
    const newName = r.id === root.id ? dstName : r.name;
    if (r.id === root.id && replaceTextPayload(f, r.name, newName) !== 1)
      throw Error('地板名字替换失败：' + dstName);
    try { setHiddenRecord(f, true); } catch (e) { /* 记录结构若无可见性块，交给运行时同步 */ }
    recTop.sub.splice(insertAt++, 0, f);
    const nr = {
      id: idMap.get(r.id), name: newName,
      parentId: r.id === root.id ? bf.id : idMap.get(r.parentId), field: f,
    };
    added.push(nr); byId.set(nr.id, nr); touched.add(nr.id);
    if (r.id === root.id) floorRoots.push(nr);
  }
}
for (const nm of SPEC.floorCells.names) copyFloorCell('floor.cell.6.6', nm);

// ── childList 同步（按 recTop 顺序） ───────────────────────────────────────
order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
for (const pid of new Set([...TPL.map(r => r.id), bf.id])) {
  const p = byId.get(pid), cl = findChildListTop(p.field.sub);
  if (!cl) throw Error('找不到 childList #' + pid);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (order.get(byId.get(a)?.field) ?? 1e9) - (order.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids); touch(p);
}

// ── 结构硬闸门 ────────────────────────────────────────────────────────────
const EXPECTED_RECS = recBefore.size + added.length;
for (const root of TPL) {
  const kids = g.recs.filter(r => r.parentId === root.id).concat(added.filter(r => r.parentId === root.id));
  const cl = findChildListTop(root.field.sub);
  const seq = (asIdList(cl.payload, true) || []).map(id => byId.get(id)?.name);
  const ib = seq.indexOf('gen.backrop'), it = seq.indexOf('gen.title'), ibody = seq.indexOf('gen.body');
  const ix = seq.map((n, i) => /^gen691\./.test(n || '') ? i : -1).filter(i => i >= 0);
  if (!(ib >= 0 && it >= 0 && ibody >= 0 && ix.length === SPEC.card.layers.length
        && Math.min(...ix) > ib && Math.max(...ix) < it && it < ibody))
    throw Error('通用卡层序不符 #' + root.id);
  for (const s of SPEC.card.layers)
    if (kids.filter(k => k.name === s.name).length !== 1) throw Error('新层重名/缺失 ' + s.name);
}
const bfSeq = (asIdList(findChildListTop(bf.field.sub).payload, true) || []).map(id => byId.get(id)?.name);
if (bfSeq.length !== 49) throw Error('board.floors childList 应为 49，实得 ' + bfSeq.length);
for (const nm of SPEC.floorCells.names)
  if (!bfSeq.includes(nm)) throw Error('地板层未进 childList：' + nm);

const result = {
  version: 691,
  base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA, records: recBefore.size, luaBytes: Buffer.byteLength(s689) },
  output: { expectRecords: EXPECTED_RECS, luaBytes: Buffer.byteLength(s691) },
  counts: { cardLayersPerTemplate: SPEC.card.layers.length, cardLayersTotal: SPEC.card.layers.length * 2,
    floorFamilies: SPEC.floorCells.names.length, floorRecords: SPEC.floorCells.names.length * 2,
    addedTotal: added.length, modifiedRecords: touched.size },
  lua: { patches: P.map(p => ({ name: p.name, count: p.count })), reversible: true },
  doors: { level: SPEC.doors.level, before: 9, after: SPEC.doors.kept.length, dropped: SPEC.doors.dropped },
  cardSummary,
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── 写档（唯一通道 writeGil） ─────────────────────────────────────────────
const script = Buffer.from(s691, 'utf8');
const leaf = findScriptLeaf(g).field;
leaf.payload = script; leaf.len = script.length;
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '691 橙黄通用卡 + 真机修复', expectRecs: EXPECTED_RECS,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(script)) return '内嵌 Lua 不一致';
    const ids2 = new Set(t.recs.map(q => q.id));
    const addedIds = new Set(added.map(a => a.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touched.has(r.id) && !addedIds.has(r.id) && !recBefore.get(r.id).equals(encodeMsg([r.field])))
        return '非目标记录被改动 ' + r.name;
      if (r.parentId != null && !danglingBefore.has(r.id) && !ids2.has(r.parentId))
        return '新增悬空父引用 ' + r.name + ' #' + r.id;
    }
    for (const nm of SPEC.card.layers.map(s => s.name))
      if (t.recs.filter(r => r.name === nm).length !== 2) return '通用卡层套装不完整 ' + nm;
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const gen = t.recs.filter(q => q.parentId === root.id && /^gen691\./.test(q.name || ''));
      if (gen.length !== SPEC.card.layers.length || gen.some(q => !isHiddenRecord(q.field)))
        return '通用卡层数量/隐藏不符 #' + root.id;
    }
    const floors = t.recs.filter(r => /^floor\.cell\./.test(r.name || ''));
    if (floors.length !== 49) return 'floor.cell 容器应为 49 条，实得 ' + floors.length;
    const faces = t.recs.filter(r => r.name === 'face' && floors.some(f => f.id === r.parentId));
    if (faces.length !== 49) return 'floor.cell 的 face 子控件应为 49 条，实得 ' + faces.length;
    return true;
  },
});

// ── 磁盘重读二次复核 ──────────────────────────────────────────────────────
const disk = readGil(OUTPUT);
if (disk.recs.length !== EXPECTED_RECS) throw Error('磁盘记录数不符');
if (!findScriptLeaf(disk).buf.equals(script)) throw Error('磁盘内嵌 Lua 不一致');
if (revertPatches(findScriptLeaf(disk).buf.toString('utf8')) !== s689)
  throw Error('磁盘 Lua 无法反向还原 689');
let changed = 0;
for (const r of disk.recs) {
  const b = recBefore.get(r.id);
  if (b && !touched.has(r.id) && !b.equals(encodeMsg([r.field]))) changed++;
}
if (changed) throw Error('非目标记录被改动 ' + changed);
fs.writeFileSync(LUA691, s691, 'utf8');
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.unexpectedChangedRecords = changed;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '691_构建审计.json'),
  JSON.stringify(result, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify(result, null, 2));
