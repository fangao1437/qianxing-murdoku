// 696 · 基于 695 增量写档
//   A 三格地毯凹角：两套 L 形素材的源/母本 content 各补 1 层深棕角片（+4 条记录）
//   B 选关缩略图：只改内嵌 Lua（5 项可逆补丁），零静态文本改动
// 用法：node 构建696.mjs --dry   /   FORCE=1 node 构建696.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const P695 = path.join(DIR, '../695_地毯原型注册与改名');
const INPUT = path.join(P695, '695_地毯原型注册与改名.gil');
const OUTPUT = path.join(DIR, '696_凹角与选关缩略图.gil');
const LUA695 = fs.readFileSync(path.join(P695, '695_内嵌Lua_695.lua'), 'utf8');
const LUA696 = fs.readFileSync(path.join(DIR, '696_内嵌Lua_696.lua'), 'utf8');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '696_设计与补丁.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, cloneField, stateBlocks, pairOf, setPair,
        findChildListTop, asIdList, setChildList } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const EXPECT = recBefore.size + 4;
const BODY695 = g.src.subarray(20, 20 + g.hdr[4]);
if (findScriptLeaf(g).buf.toString('utf8') !== LUA695) throw Error('695 .gil 内嵌 Lua 与交付副本不一致');
const scriptField = findScriptLeaf(g).field;
const recTop = g.tree.find(q => q.field === 9);
if (!recTop) throw Error('找不到 recTop');
const byId = new Map(g.recs.map(r => [Number(r.id), r]));
let max = BigInt(g.maxId);

// ── 工具 ──────────────────────────────────────────────────────────────
function walk(f, fn) { fn(f); for (const q of f.sub || []) walk(q, fn); }
function setGeom(f, x, y, w, h) {
  const st = stateBlocks(f.sub, []);
  if (!st.length) throw Error('层记录缺几何状态块');
  for (const s of st) {
    setPair(pairOf(s, 504), x, y);
    setPair(pairOf(s, 505), w, h);
  }
}
function imgColor(f) {
  let found = null;
  const ns = (fields, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [fields]);
  const p = ns({ sub: f.sub }, [505, 503, 84])[0];
  if (p && p.sub) {
    const q = p.sub.find(x => x.field === 502 && x.wt === 0);
    if (q) found = Number(q.num) >>> 0;
  }
  return found;
}

// ── A 凹角补片：4 条新层记录 + 4 个 content.childList 9→10 ────────────
const C = SPEC.cornerPatch;
const added = [];
const childSnaps = [];
for (const p of C.patches) {
  const proto = byId.get(p.cloneFrom);
  if (!proto) throw Error('克隆原型缺失 #' + p.cloneFrom);
  const content = byId.get(p.content);
  if (!content) throw Error('content 缺失 #' + p.content);
  const cl = findChildListTop(content.field.sub);
  const ids0 = cl ? (asIdList(cl.payload, true) || []) : null;
  if (!cl || ids0.length !== 9) throw Error('content.childList 应为 9 项 #' + p.content);
  if (imgColor(proto.field) !== parseInt(C.color.replace('0x', ''), 16))
    throw Error('克隆原型不是深棕外框色 #' + p.cloneFrom);

  const f = cloneField(proto.field);
  const newId = Number(++max);
  walk(f, x => { if (x.num != null && Number(x.num) === p.cloneFrom) x.num = BigInt(newId); });
  const top504 = f.sub.find(q => q.field === 504 && q.wt === 0);
  if (!top504) throw Error('克隆层缺顶层 #504');
  top504.num = BigInt(p.content);
  setGeom(f, p.x, p.y, C.size, C.size);
  // 与既有模板同构：#504 必须在第一个 #505 之前（695 已对齐，克隆自然继承）
  const i504 = f.sub.findIndex(q => q.field === 504 && q.wt === 0);
  const i505 = f.sub.findIndex(q => q.field === 505);
  if (i505 >= 0 && i504 > i505) throw Error('新层 #504 位置异常');

  const at = recTop.sub.indexOf(proto.field);
  if (at < 0) throw Error('原型层不在 recTop #' + p.cloneFrom);
  recTop.sub.splice(at + 1, 0, f);
  childSnaps.push({ cl, payload: Buffer.from(cl.payload), len: cl.len });
  setChildList(cl, [...ids0, newId]);
  added.push({ id: newId, content: p.content, template: p.template, copy: p.copy,
               x: p.x, y: p.y, size: C.size, color: C.color });
}

// ── B 内嵌 Lua ────────────────────────────────────────────────────────
const SNAP = {
  scriptPayload: Buffer.from(scriptField.payload), scriptLen: scriptField.len,
};
// 精确定位刚插入的 4 个字段对象（用于反向还原）
SNAP.inserted = recTop.sub.filter(f => {
  const t = f.sub && f.sub.find(x => x.field === 501 && x.wt === 0);
  return t && added.some(a => Number(t.num) === a.id);
});
if (SNAP.inserted.length !== 4) throw Error('新插入字段定位失败 ' + SNAP.inserted.length);
scriptField.payload = Buffer.from(LUA696, 'utf8'); scriptField.len = scriptField.payload.length;

// ── 反向逐字节还原 695（内存级） ──────────────────────────────────────
function revert() {
  scriptField.payload = Buffer.from(SNAP.scriptPayload); scriptField.len = SNAP.scriptLen;
  for (const o of childSnaps) { o.cl.payload = Buffer.from(o.payload); o.cl.len = o.len; }
  for (const f of SNAP.inserted) {
    const i = recTop.sub.indexOf(f);
    if (i >= 0) recTop.sub.splice(i, 1);
  }
}
function apply() {
  scriptField.payload = Buffer.from(LUA696, 'utf8'); scriptField.len = scriptField.payload.length;
  for (let k = 0; k < childSnaps.length; k++) {
    const o = childSnaps[k];
    setChildList(o.cl, [...(asIdList(o.payload, true) || []), added[k].id]);
  }
  // 按原型层之后的位置重新插入
  for (let k = 0; k < SNAP.inserted.length; k++) {
    const f = SNAP.inserted[k], p = C.patches[k];
    const proto = byId.get(p.cloneFrom);
    const at = recTop.sub.indexOf(proto.field);
    recTop.sub.splice(at + 1, 0, f);
  }
}
if (encodeMsg(g.tree).equals(BODY695)) throw Error('★ 改动没有写进编码树');
revert();
if (!encodeMsg(g.tree).equals(BODY695)) throw Error('★ 反向还原 695 未能逐字节一致');
apply();

const result = {
  version: 696,
  base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA, records: recBefore.size,
          luaBytes: Buffer.byteLength(LUA695) },
  output: { expectRecords: EXPECT, added: 4, luaBytes: Buffer.byteLength(LUA696) },
  corner: { patches: added, color: C.color, size: C.size, note: C.note },
  lua: { patches: SPEC.luaPatches.length, reversible: true, revertToBase: '逐字节一致' },
  selectThumb: SPEC.selectThumb,
  texts: { changed: 0, note: '关卡名走 Lua 动态文本；静态文本零改动' },
  puzzle: { note: '谜题数据零改动；695 的三格地毯原型注册与人名改写全部保留' },
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── 写档 ──────────────────────────────────────────────────────────────
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '696 凹角与选关缩略图', expectRecs: EXPECT,
  assert(t) {
    if (findScriptLeaf(t).buf.toString('utf8') !== LUA696) return '内嵌 Lua 不一致';
    for (const a of added) {
      const r = t.recs.find(x => Number(x.id) === a.id);
      if (!r || String(r.parentId) !== String(a.content)) return '新角片缺失 #' + a.id;
    }
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want) continue;                   // 696 新增的 4 条角片
      if (!want.equals(encodeMsg([r.field]))) return '写后记录不一致 #' + r.id + ' ' + r.name;
    }
    return true;
  },
});

const disk = readGil(OUTPUT);
if (disk.recs.length !== EXPECT) throw Error('磁盘记录数不符');
if (findScriptLeaf(disk).buf.toString('utf8') !== LUA696) throw Error('磁盘 Lua 不一致');
// 磁盘版反向还原 695
{
  const d9 = disk.tree.find(q => q.field === 9);
  const dScript = findScriptLeaf(disk).field;
  const dContents = C.patches.map(p => {
    const r = disk.recs.find(x => Number(x.id) === p.content);
    return findChildListTop(r.field.sub);
  });
  const dNew = d9.sub.filter(f => {
    const t = f.sub && f.sub.find(x => x.field === 501 && x.wt === 0);
    return t && added.some(a => Number(t.num) === a.id);
  });
  if (dNew.length !== 4 || dContents.some(x => !x)) throw Error('磁盘新记录定位失败');
  const save = { script: Buffer.from(dScript.payload), cls: dContents.map(x => Buffer.from(x.payload)) };
  dScript.payload = Buffer.from(SNAP.scriptPayload); dScript.len = dScript.payload.length;
  dContents.forEach((cl, k) => { cl.payload = Buffer.from(childSnaps[k].payload); cl.len = childSnaps[k].len; });
  for (const f of dNew) { const i = d9.sub.indexOf(f); if (i >= 0) d9.sub.splice(i, 1); }
  if (!encodeMsg(disk.tree).equals(BODY695)) throw Error('磁盘版无法反向逐字节还原 695');
  dScript.payload = save.script; dScript.len = save.script.length;
  dContents.forEach((cl, k) => { cl.payload = save.cls[k]; cl.len = save.cls[k].length; });
  for (let k = 0; k < dNew.length; k++) {
    const proto = disk.recs.find(x => Number(x.id) === C.patches[k].cloneFrom);
    const at = d9.sub.indexOf(proto.field);
    d9.sub.splice(at + 1, 0, dNew[k]);
  }
}
const changedIds = [];
for (const r of disk.recs) {
  const b = recBefore.get(r.id);
  if (b && !b.equals(encodeMsg([r.field]))) changedIds.push(r.id);
}
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.changedExisting = changedIds.length;
result.output.changedRecordIds = changedIds;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '696_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
