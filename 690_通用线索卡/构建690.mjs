// 690 · 基于 689 新增「通用线索卡」（同构异色）
//   ① 两套 clue 模板各新增 12 枚 gen690.* 图元（静态隐藏，运行时由名单点亮）；
//   ② 改造既有 gen.backrop / gen.title / gen.body 三件；
//   ③ 内嵌 Lua 只改两处：显隐名单扩展 + 通用卡高亮目标 backrop1 → gen.backrop。
//   689 原件逐字节保留；Lua 补丁与记录改动均可反向还原 689。
// 用法：FORCE=1 node 构建690.mjs  /  node 构建690.mjs --dry
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const INPUT = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_性能负载优化.gil');
const OUTPUT = path.join(DIR, '690_通用线索卡.gil');
const LUA690 = path.join(DIR, '690_内嵌Lua_690.lua');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '690_通用线索卡图元.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, setPair, cloneField, textsOf,
  findChildListTop, asIdList, setChildList } =
  await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const { setHiddenRecord, isHiddenRecord, imageTriple } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

// ── 内嵌 Lua：可逆补丁 ────────────────────────────────────────────────────
const OLD_LIST = SPEC.lua.oldList;
const NEW_LIST = `ipairs({ ${SPEC.lua.genLayers.map(n => `"${n}"`).join(', ')} })`;
const HL_OLD = `    pcall(function() _cp = item:FindChild("backrop1") end)`;
const HL_NEW = `    pcall(function() _cp = item:FindChild("${'gen.backrop'}") end)`;
function patchLua(src) {
  const nList = src.split(OLD_LIST).length - 1;
  if (nList !== 2) throw Error(`显隐名单定位数应为 2，实得 ${nList}`);
  const nHl = src.split(HL_OLD).length - 1;
  if (nHl !== 1) throw Error(`高亮目标定位数应为 1，实得 ${nHl}`);
  return src.split(OLD_LIST).join(NEW_LIST).split(HL_OLD).join(HL_NEW);
}
function revertLua(s) {
  return s.split(NEW_LIST).join(OLD_LIST).split(HL_NEW).join(HL_OLD);
}

// ── gil 工具 ──────────────────────────────────────────────────────────────
const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const script689 = findScriptLeaf(g).buf.toString('utf8');
const script690 = patchLua(script689);
if (revertLua(script690) !== script689) throw Error('Lua 补丁无法逐字节反向还原 689');
const recTop = g.tree.find(q => q.field === 9);
const byId = new Map(g.recs.map(r => [r.id, r]));
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
// 689 基准里本就有 36 条指向模板母本容器（非记录节点）的父引用，属既有形态，不算新增悬空
const ids0 = new Set(g.recs.map(r => r.id));
const danglingBefore = new Set(g.recs.filter(r => r.parentId != null && !ids0.has(r.parentId)).map(r => r.id));
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
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
function setFont(r, font) {
  const p = ns(r.field, [505, 503, 75])[0];
  if (!p) throw Error('找不到文本块：' + r.name);
  for (const [k, v] of Object.entries(font)) setNum(p, Number(k), v);
  touch(r);
}

const touched = new Set(), modified = new Set(), added = [];
function touch(r) { touched.add(r.id); if (r.name) modified.add(r.name); }
let max = BigInt(g.maxId);
const PROTO_IMG = 'td.home.page.1.help619.icon';
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function cloneLayer(parent, spec, proto, beforeId) {
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  if (replaceTextPayload(f, proto.name, spec.name) !== 1)
    throw Error('名字字段替换失败：' + spec.name);
  if (spec.proto === 'text' && replaceTextPayload(f, '通用线索', spec.text) !== 1)
    throw Error('文本内容替换失败：' + spec.name);
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = (function find(ff) {
    return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true));
  })(f);
  if (cl) setChildList(cl, []);
  const idx = recTop.sub.findIndex(q => q === byId.get(beforeId)?.field);
  if (idx < 0) throw Error('beforeId 不在 recTop：' + beforeId);
  recTop.sub.splice(idx, 0, f);
  const r = { id, name: spec.name, parentId: parent.id, field: f };
  if (spec.proto === 'text') {
    setTextColor(r, spec.textColor);
    if (spec.font) setFont(r, spec.font);
  } else setImage(r, spec.imageId, spec.color);
  reshape(r, spec);
  setHiddenRecord(f, true);                 // 静态隐藏：只在通用项上由 Lua 点亮
  added.push(r); byId.set(id, r); touched.add(id);
  if (!isHiddenRecord(f)) throw Error('新层未隐藏：' + spec.name);
  return r;
}

// ── 两套 clue 模板 ────────────────────────────────────────────────────────
const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (TPL.length !== 2) throw Error('clue 模板数不符：' + TPL.length);
const summary = [];
for (const root of TPL) {
  const kid = nm => g.recs.find(r => r.parentId === root.id && r.name === nm);
  const gb = kid('gen.backrop'), gt = kid('gen.title'), gbody = kid('gen.body');
  if (!gb || !gt || !gbody) throw Error('gen.* 三件缺失 #' + root.id);
  if (!isHiddenRecord(gb.field) || !isHiddenRecord(gt.field) || isHiddenRecord(gbody.field))
    throw Error('gen.* 初始显隐形态不符 #' + root.id);
  const mb = SPEC.modify.find(m => m.name === 'gen.backrop');
  const mt = SPEC.modify.find(m => m.name === 'gen.title');
  const md = SPEC.modify.find(m => m.name === 'gen.body');
  setImage(gb, mb.imageId, mb.color); reshape(gb, mb);
  setTextColor(gt, mt.textColor);
  reshape(gbody, md); setTextColor(gbody, md.textColor);
  const protoImg = g.recs.find(r => r.name === PROTO_IMG);
  if (!protoImg) throw Error('图片原型缺失');
  for (const spec of SPEC.layers)
    cloneLayer(root, spec, spec.proto === 'text' ? gt : protoImg, gt.id);
  summary.push({ rootId: root.id, genBackropId: gb.id, genTitleId: gt.id, genBodyId: gbody.id,
    added: SPEC.layers.map(s => s.name) });
}

// ── childList 同步（按 recTop 顺序） ──────────────────────────────────────
const fieldIndex = new Map(); recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set(added.map(r => r.parentId))) {
  const p = byId.get(pid), cl = findChildListTop(p.field.sub);
  if (!cl) throw Error('找不到 childList #' + pid);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids); touch(p);
}

// ── 几何/层序硬闸门 ───────────────────────────────────────────────────────
const EXPECTED_RECS = recBefore.size + added.length;
for (const s of summary) {
  const kids = g.recs.filter(r => r.parentId === s.rootId).concat(added.filter(r => r.parentId === s.rootId));
  const names = kids.map(r => r.name);
  for (const spec of SPEC.layers)
    if (names.filter(n => n === spec.name).length !== 1) throw Error('新层重名/缺失 ' + spec.name);
  const cl = findChildListTop(byId.get(s.rootId).field.sub);
  const seq = (asIdList(cl.payload, true) || []).map(id => byId.get(id)?.name);
  const iBackrop = seq.indexOf('gen.backrop'), iTitle = seq.indexOf('gen.title'), iBody = seq.indexOf('gen.body');
  const iGen = seq.map((n, i) => /^gen690\./.test(n || '') ? i : -1).filter(i => i >= 0);
  if (!(iBackrop >= 0 && iTitle >= 0 && iBody >= 0 && iGen.length === SPEC.layers.length
        && Math.min(...iGen) > iBackrop && Math.max(...iGen) < iTitle && iTitle < iBody))
    throw Error('通用卡层序不符 #' + s.rootId);
}
const result = {
  version: 690, base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA,
    records: recBefore.size, luaBytes: Buffer.byteLength(script689) },
  output: { expectRecords: EXPECTED_RECS, luaBytes: Buffer.byteLength(script690) },
  counts: { addedPerTemplate: SPEC.layers.length, templates: TPL.length,
    addedTotal: added.length, modifiedRecords: touched.size },
  lua: { listOccurrences: 2, highlightOccurrences: 1, genLayers: SPEC.lua.genLayers.length,
    reversible: true },
  layers: SPEC.layers.map(s => ({ name: s.name, role: s.role })),
  summary,
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── 写档：唯一通道 writeGil ───────────────────────────────────────────────
const script = Buffer.from(script690, 'utf8');
const leaf = findScriptLeaf(g).field;
leaf.payload = script; leaf.len = script.length;
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '690 通用线索卡（同构异色）', expectRecs: EXPECTED_RECS,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(script)) return '内嵌 Lua 不一致';
    const ids2 = new Set(t.recs.map(q => q.id));
    const addedIds = new Set(added.map(a => a.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touched.has(r.id) && !addedIds.has(r.id)
          && !recBefore.get(r.id).equals(encodeMsg([r.field]))) return '非目标记录被改动 ' + r.name;
      if (r.parentId != null && !danglingBefore.has(r.id) && !ids2.has(r.parentId))
        return '新增悬空父引用 ' + r.name + ' #' + r.id;
    }
    for (const nm of SPEC.layers.map(s => s.name))
      if (t.recs.filter(r => r.name === nm).length !== 2) return '新层套装不完整 ' + nm;
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const kids = t.recs.filter(q => q.parentId === root.id);
      const gen = kids.filter(q => /^gen690\./.test(q.name || ''));
      if (gen.length !== SPEC.layers.length) return '新层数量不符 #' + root.id;
      if (gen.some(q => !isHiddenRecord(q.field))) return '新层未静态隐藏 #' + root.id;
      const cl = findChildListTop(root.field.sub);
      const seq = (asIdList(cl.payload, true) || []).map(id => t.recs.find(q => q.id === id)?.name);
      const ib = seq.indexOf('gen.backrop'), it = seq.indexOf('gen.title');
      const ix = seq.map((n, i) => /^gen690\./.test(n || '') ? i : -1).filter(i => i >= 0);
      if (!(ib >= 0 && it >= 0 && Math.min(...ix) > ib && Math.max(...ix) < it))
        return '磁盘层序不符 #' + root.id;
    }
    return true;
  },
});

// ── 磁盘重读二次复核 ──────────────────────────────────────────────────────
const disk = readGil(OUTPUT);
if (disk.recs.length !== EXPECTED_RECS) throw Error('磁盘记录数不符');
if (!findScriptLeaf(disk).buf.equals(script)) throw Error('磁盘内嵌 Lua 不一致');
let changed = 0;
for (const r of disk.recs) {
  const b = recBefore.get(r.id);
  if (b && !touched.has(r.id) && !b.equals(encodeMsg([r.field]))) changed++;
}
if (changed) throw Error('非目标记录被改动 ' + changed);
if (revertLua(findScriptLeaf(disk).buf.toString('utf8')) !== script689)
  throw Error('磁盘 Lua 无法反向还原 689');
fs.writeFileSync(LUA690, script690, 'utf8');
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.unexpectedChangedRecords = changed;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '690_构建审计.json'),
  JSON.stringify(result, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify(result, null, 2));
