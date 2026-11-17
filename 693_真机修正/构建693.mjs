// 693 · 基于 691 增量写档
//   1 内嵌 Lua：45 项可逆补丁 + case_003 整体替换 + 2 个 prefab 占位符
//   2 三格 L 地毯：新建 2 套独立素材（源/母本/引用三件套 + content + 9 层），
//     完全复用现有家具引用路线；不复用、不拉伸任何 2 格模板
//   3 静态文本：1~7 关 who/what 共 42 条（人名前加字母；「我」不加）
//   4 唯一写档通道 writeGil；输入 691 原件逐字节保留
// 用法：node 构建693.mjs --dry   /   FORCE=1 node 构建693.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const INPUT = path.join(DIR, '../691_橙黄通用卡与真机修复/691_橙黄通用卡与真机修复.gil');
const OUTPUT = path.join(DIR, '693_第三关与三格地毯.gil');
const LUA693 = path.join(DIR, '693_内嵌Lua_693.lua');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '693_设计与补丁.json'), 'utf8'));
const TEXTS = JSON.parse(fs.readFileSync(path.join(DIR, '693_静态文本补丁.json'), 'utf8')).texts;
const FURN = JSON.parse(fs.readFileSync(path.join(DIR, '693_家具规格.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, setPair, cloneField, textsOf,
        findChildListTop, asIdList, setChildList } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const { isHiddenRecord } = await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const s691 = findScriptLeaf(g).buf.toString('utf8');
const recTop = g.tree.find(q => q.field === 9);
if (!recTop) throw Error('找不到 recTop');
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
let max = BigInt(g.maxId);
const touched = new Set(), added = [];
function touch(r) { touched.add(r.id); }

// ── 字段工具 ──────────────────────────────────────────────────────────
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function setImage(r, imageId, color) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块：' + r.name);
  setNum(p, 502, parseInt(color.replace('0x', ''), 16) >>> 0);
  setNum(p, 503, imageId);
  setNum(p, 504, 1);
  touch(r);
}
function setGeom(r, x, y, w, h) {
  const st = stateBlocks(r.field.sub, []);
  if (!st.length) throw Error('找不到几何状态块：' + r.name);
  for (const s of st) {
    setPair(pairOf(s, 504), x, y);
    setPair(pairOf(s, 505), w, h);
  }
  touch(r);
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
const tn = r => ns(r.field, [505, 503, 75, 510, 501])[0];
const txt = (r, t) => {
  const f = tn(r); if (!f) throw Error('缺文本字段 ' + r.name);
  f.payload = Buffer.from(t); f.len = f.payload.length; touched.add(r.id);
};

// ── A 新建三格地毯素材（每个模板 23 条记录） ──────────────────────────
const PROTO = {
  src: 1073748252, mama: 1073748248, ref: 1073749162,
  contentSrc: 1073748253, contentMama: 1073748249,
  layersSrc: [1073748254, 1073749157, 1073749158],
  layersMama: [1073749159, 1073749160, 1073749161],
};
const FAMILY = [PROTO.src, PROTO.mama, PROTO.ref, PROTO.contentSrc, PROTO.contentMama,
                ...PROTO.layersSrc, ...PROTO.layersMama];
if (FAMILY.length !== 11 || FAMILY.some(id => !byId.has(id))) throw Error('原型家族不完整');
const things = g.recs.find(r => r.name === 'things');
if (!things) throw Error('缺 things');
const thingsCL = findChildListTop(things.field.sub);
const thingsSeq0 = asIdList(thingsCL.payload, true) || [];

const prefabIds = {};
const tplOrder = ['furn.rug.4', 'furn.rug.5'];
let insertAt = recTop.sub.findIndex(f => f === byId.get(PROTO.src).field) + 1;
if (insertAt <= 0) throw Error('原型源记录不在 recTop');

for (const tpl of tplOrder) {
  const spec = FURN.newAssets[tpl];
  if (!spec) throw Error('缺素材规格 ' + tpl);
  const idMap = new Map(FAMILY.map(id => [id, Number(++max)]));
  // 额外 6 层/份 content：以原型 3 层各克隆 2 次
  const extra = [];
  for (const [tag, protos] of [['src', PROTO.layersSrc], ['mama', PROTO.layersMama]]) {
    for (let rep = 0; rep < 2; rep++) {
      for (const p of protos) extra.push({ proto: p, tag, rep });
    }
  }
  for (const e of extra) e.id = Number(++max);

  const newLayersSrc = [];
  const newLayersMama = [];
  for (let rep = 0; rep < 3; rep++) {
    for (let j = 0; j < 3; j++) {
      newLayersSrc.push(rep === 0 ? idMap.get(PROTO.layersSrc[j])
                                  : extra.find(e => e.tag === 'src' && e.rep === rep - 1 && e.proto === PROTO.layersSrc[j]).id);
      newLayersMama.push(rep === 0 ? idMap.get(PROTO.layersMama[j])
                                   : extra.find(e => e.tag === 'mama' && e.rep === rep - 1 && e.proto === PROTO.layersMama[j]).id);
    }
  }

  // 克隆 11 条原型 + 12 条额外层
  const cloned = [];
  for (const id of FAMILY) {
    const proto = byId.get(id);
    const f = cloneField(proto.field);
    remapIds(f, idMap);
    let name = proto.name;
    if ([PROTO.src, PROTO.mama, PROTO.ref].includes(id)) {
      if (replaceTextPayload(f, 'furn.rug.2', tpl) !== 1) throw Error('模板名替换失败 ' + tpl);
      name = tpl;
    }
    const parentId = [PROTO.src].includes(id) ? null
      : [PROTO.mama].includes(id) ? 1073741844
      : [PROTO.ref].includes(id) ? things.id
      : (idMap.get(proto.parentId) || proto.parentId);
    // 父字段（顶层 #504）显式写回
    f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
    if (parentId != null) f.sub.push({ field: 504, wt: 0, num: BigInt(parentId) });
    recTop.sub.splice(insertAt++, 0, f);
    const r = { id: idMap.get(id), name, parentId, field: f };
    cloned.push(r); added.push(r); byId.set(r.id, r); touched.add(r.id);
  }
  for (const e of extra) {
    const proto = byId.get(e.proto);
    const f = cloneField(proto.field);
    // 新层：自身 ID 与父 content ID 重映射
    (function walk(x) {
      if (x.num != null && Number(x.num) === e.proto) x.num = BigInt(e.id);
      if (x.num != null && idMap.has(Number(x.num))) x.num = BigInt(idMap.get(Number(x.num)));
      for (const q of x.sub || []) walk(q);
    })(f);
    f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
    const parentContent = e.tag === 'src' ? idMap.get(PROTO.contentSrc) : idMap.get(PROTO.contentMama);
    f.sub.push({ field: 504, wt: 0, num: BigInt(parentContent) });
    recTop.sub.splice(insertAt++, 0, f);
    const r = { id: e.id, name: proto.name, parentId: parentContent, field: f };
    cloned.push(r); added.push(r); byId.set(r.id, r); touched.add(r.id);
  }

  const rec = id => byId.get(id);
  // content：216×216，childList = 9 层
  for (const [cid, layers] of [[idMap.get(PROTO.contentSrc), newLayersSrc],
                               [idMap.get(PROTO.contentMama), newLayersMama]]) {
    const c = rec(cid);
    setGeom(c, 0, 0, spec.canvas.W, spec.canvas.H);
    const cl = findChildListTop(c.field.sub);
    if (!cl) throw Error('content 缺 childList');
    setChildList(cl, layers);
  }
  // 9 层：按规格设置位置/尺寸/颜色/图元（3 格 × 3 圈，零溢出、不拉伸）
  for (const [tag, layers] of [['src', newLayersSrc], ['mama', newLayersMama]]) {
    spec.layers.forEach((L, j) => {
      const r = rec(layers[j]);
      setGeom(r, L.x, L.y, L.w, L.h);
      setImage(r, L.imageId, L.color);
    });
  }
  prefabIds[tpl] = idMap.get(PROTO.src);
  if (isHiddenRecord(rec(idMap.get(PROTO.src)).field)) throw Error('新素材源不应静态隐藏 ' + tpl);
  console.log(`新素材 ${tpl}: 记录 ${cloned.length} 条，层 ${spec.layers.length}，源 ID ${prefabIds[tpl]}`);
}
// things.childList 追加两个引用控件
const newRefs = tplOrder.map(t => added.find(r => r.name === t && r.parentId === things.id));
if (newRefs.some(r => !r)) throw Error('新引用控件缺失');
setChildList(thingsCL, [...thingsSeq0, ...newRefs.map(r => r.id)]);
touch(things);

// ── B 内嵌 Lua：占位符 → 实际 prefab ID；补丁 + 模块替换 ──────────────
let P = SPEC.luaPatches.map(p => ({
  ...p,
  old: p.old.replace('__RUG4_PREFAB__', prefabIds['furn.rug.4'])
           .replace('__RUG5_PREFAB__', prefabIds['furn.rug.5']),
  new: p.new.replace('__RUG4_PREFAB__', prefabIds['furn.rug.4'])
           .replace('__RUG5_PREFAB__', prefabIds['furn.rug.5']),
}));
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
let s = applyPatches(s691);
// 693 有两个模块整体替换（第3关定稿、第4关 A/D 内容互换）
const MODREPS = SPEC.moduleReplacements;
const savedModules = [];
for (const mr of MODREPS) {
  const i = s.indexOf(mr.marker);
  if (i < 0) throw Error('模块未找到 ' + mr.name);
  const j = s.indexOf('\nend', i);
  if (j < 0) throw Error('模块结束未找到 ' + mr.name);
  savedModules.push({ old: s.slice(i, j + 4), neu: mr.newModule.trimEnd() });
  s = s.slice(0, i) + mr.newModule.trimEnd() + s.slice(j + 4);
}
function revertAll(s2) {
  let back = s2;
  for (let k = savedModules.length - 1; k >= 0; k--)
    back = back.replace(savedModules[k].neu, savedModules[k].old);
  return revertPatches(back);
}
if (revertAll(s) !== s691) throw Error('Lua 补丁/模块无法逐字节反向还原 691');
if (s.includes('__RUG4_PREFAB__') || s.includes('__RUG5_PREFAB__')) throw Error('占位符未替换');

// ── C 静态文本（who / what） ───────────────────────────────────────────
let textCount = 0;
for (const [lv, rows] of Object.entries(TEXTS)) {
  for (const t of rows) {
    for (const [slot, val] of [['letter', t.letter], ['who', t.who], ['what', t.what]]) {
      const r = byName.get(`${slot}.${lv}.${t.slot}`);
      if (!r) throw Error(`缺静态文本 ${slot}.${lv}.${t.slot}`);
      txt(r, val); textCount++;
    }
  }
}

// ── D 结构硬闸门 ──────────────────────────────────────────────────────
const EXPECT = recBefore.size + added.length;
for (const tpl of tplOrder) {
  const spec = FURN.newAssets[tpl];
  const src = added.find(r => r.name === tpl && r.parentId === null);
  const mama = added.find(r => r.name === tpl && r.parentId === 1073741844);
  const ref = added.find(r => r.name === tpl && r.parentId === things.id);
  if (!src || !mama || !ref) throw Error('三件套不完整 ' + tpl);
  const kids = added.filter(r => r.parentId === src.id);
  if (kids.length !== 1) throw Error('源 content 数不符 ' + tpl);
  const layers = added.filter(r => r.parentId === kids[0].id);
  if (layers.length !== spec.layerCount) throw Error('层数不符 ' + tpl + ' ' + layers.length);
  const cl = findChildListTop(kids[0].field.sub);
  if ((asIdList(cl.payload, true) || []).length !== spec.layerCount) throw Error('childList 层数不符');
  if (layers.some(r => isHiddenRecord(r.field))) throw Error('新素材层不应静态隐藏 ' + tpl);
}
const thingsSeq = asIdList(thingsCL.payload, true) || [];
if (thingsSeq.length !== thingsSeq0.length + 2) throw Error('things.childList 未追加 2 项');
if (textCount !== 126) throw Error('静态文本条数不符：' + textCount);

const script = Buffer.from(s, 'utf8');
const leaf = findScriptLeaf(g).field;
leaf.payload = script; leaf.len = script.length;

const result = {
  version: 693,
  base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA, records: recBefore.size,
          luaBytes: Buffer.byteLength(s691) },
  output: { expectRecords: EXPECT, luaBytes: script.length, added: added.length,
            changedExisting: touched.size - added.length, prefabIds },
  lua: { patches: P.length, modulesReplaced: MODREPS.map(m => m.name), reversible: true },
  texts: { records: textCount, levels: Object.keys(TEXTS).map(Number).sort() },
  carpet: tplOrder.map(t => ({ template: t, sourceId: prefabIds[t],
                               layers: FURN.newAssets[t].layerCount,
                               canvas: FURN.newAssets[t].canvas })),
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── E 写档（五闸） ────────────────────────────────────────────────────
const addedIds = new Set(added.map(a => a.id));
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '693 第三关与三格地毯', expectRecs: EXPECT,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(script)) return '内嵌 Lua 不一致';
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touched.has(r.id) && !addedIds.has(r.id) && !recBefore.get(r.id).equals(encodeMsg([r.field])))
        return '非目标记录被改动 ' + r.name;
    }
    return true;
  },
});

// ── F 磁盘重读二次复核 ────────────────────────────────────────────────
const disk = readGil(OUTPUT);
if (disk.recs.length !== EXPECT) throw Error('磁盘记录数不符');
const diskLua = findScriptLeaf(disk).buf.toString('utf8');
if (!findScriptLeaf(disk).buf.equals(script)) throw Error('磁盘内嵌 Lua 不一致');
if (revertAll(diskLua) !== s691) throw Error('磁盘 Lua 无法反向还原 691');
let rogue = 0;
for (const r of disk.recs) {
  const b = recBefore.get(r.id);
  if (b && !touched.has(r.id) && !b.equals(encodeMsg([r.field]))) rogue++;
}
if (rogue) throw Error('出现白名单外旧记录改动 ' + rogue);
const diskByName = new Map(disk.recs.filter(r => r.name).map(r => [r.name, r]));
for (const [lv, rows] of Object.entries(TEXTS))
  for (const t of rows)
    for (const [slot, val] of [['letter', t.letter], ['who', t.who], ['what', t.what]]) {
      const r = diskByName.get(`${slot}.${lv}.${t.slot}`);
      if (!r || tn(r).payload.toString('utf8') !== val)
        throw Error('磁盘文本不符 ' + slot + '.' + lv + '.' + t.slot);
    }
fs.writeFileSync(LUA693, diskLua, 'utf8');
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.rogue = rogue;
result.output.luaRoundtrip = true;
result.output.textVerified = true;
fs.writeFileSync(path.join(DIR, '693_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
