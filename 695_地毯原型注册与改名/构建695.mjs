// 695 · 基于 694 最小增量写档
//   只改：/9/501 原型 ID 列表（+2）、原型根 #503 母本列表（+2）、
//         2 个静态文本字段、1 个内嵌 Lua script leaf。
//   零新增记录、零谜题改动、零家具几何改动。
// 用法：node 构建695.mjs --dry   /   FORCE=1 node 构建695.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const P694 = path.join(DIR, '../694_地毯渲染修复');
const INPUT = path.join(P694, '694_地毯渲染修复.gil');
const OUTPUT = path.join(DIR, '695_地毯原型注册与改名.gil');
const LUA695 = fs.readFileSync(path.join(DIR, '695_内嵌Lua_695.lua'), 'utf8');
const LUA694 = fs.readFileSync(path.join(P694, '694_内嵌Lua_694.lua'), 'utf8');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '695_设计与补丁.json'), 'utf8'));
const TEXTS = JSON.parse(fs.readFileSync(path.join(DIR, '695_静态文本补丁.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, asIdList, setChildList } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const EXPECT = recBefore.size;
const BODY694 = g.src.subarray(20, 20 + g.hdr[4]);

// ── 定位三个可写节点 ──────────────────────────────────────────────────
const n9 = g.tree.find(f => f.field === 9);
if (!n9 || !n9.sub) throw Error('缺 /9 节点');
const rootList = n9.sub.find(f => f.field === 501 && f.wt === 2 && asIdList(f.payload, true) !== null);
if (!rootList) throw Error('缺 /9/501 原型 ID 列表');
const protoRoot = n9.sub.filter(f => f.field === 502)
  .find(f => f.sub && f.sub.some(x => x.field === 501 && Number(x.num) === 1073741844));
if (!protoRoot) throw Error('缺 ClientUIPrototypeHierarchyRoot');
const mamaList = protoRoot.sub.find(f => f.field === 503 && f.wt === 2 && asIdList(f.payload, true) !== null);
if (!mamaList) throw Error('缺原型根 #503 母本列表');
const scriptField = findScriptLeaf(g).field;
if (findScriptLeaf(g).buf.toString('utf8') !== LUA694) throw Error('694 .gil 内嵌 Lua 与交付副本不一致');

// 静态文本字段（精确整串匹配，排除 script leaf）
const textHits = [];
(function walk(fs, p) {
  for (const f of fs) {
    const at = p + '/' + f.field;
    if (f === scriptField) continue;
    if (f.isText && f.payload) {
      const s = f.payload.toString('utf8');
      const hit = TEXTS.texts.find(t => t.old === s);
      if (hit) textHits.push({ f, at, old: s, next: hit.new });
    }
    if (f.sub) walk(f.sub, at);
  }
})(g.tree, '');
for (const t of TEXTS.texts) {
  const n = textHits.filter(h => h.old === t.old).length;
  if (n !== t.count) throw Error(`静态文本「${t.old}」命中 ${n} 次，应为 ${t.count}`);
}
if (textHits.length !== TEXTS.texts.length) throw Error('静态文本命中总数不符');

// ── R3 新素材记录：顶层 #504 移到第一个 #505 之前（与既有模板同构） ────
const NEW_IDS = new Set();
for (let id = SPEC.registryFix.fieldOrderFix.idRange[0]; id <= SPEC.registryFix.fieldOrderFix.idRange[1]; id++) NEW_IDS.add(id);
const orderFix = [];
for (const rec of g.recs) {
  if (!NEW_IDS.has(Number(rec.id))) continue;
  const sub = rec.field.sub;
  const i504 = sub.findIndex(f => f.field === 504 && f.wt === 0);
  if (i504 < 0) continue;                       // 源记录 parent=null，无 #504
  const i505 = sub.findIndex(f => f.field === 505);
  const at = i505 < 0 ? sub.length : i505;
  if (i504 < at) continue;                      // 已在前部
  orderFix.push({ rec, original: sub.slice(), at, i504 });
}
if (orderFix.length !== 44) throw Error(`需对齐 #504 的记录应为 44 条，实得 ${orderFix.length}`);

// ── 改动前快照（供反向逐字节还原 694） ────────────────────────────────
const R = SPEC.registryFix;
const ids0 = asIdList(rootList.payload, true), mamas0 = asIdList(mamaList.payload, true);
if (ids0.length !== R.rootList.before || mamas0.length !== R.protoRootChildList.before)
  throw Error('注册表基线项数不符');
for (const id of R.rootList.append) if (ids0.includes(id)) throw Error('新源 ID 已在 /9/501');
for (const id of R.protoRootChildList.append) if (mamas0.includes(id)) throw Error('新母本 ID 已在原型根 #503');
for (const id of [1073747149, 1073748252, 1073749968]) if (!ids0.includes(id)) throw Error('既有地毯源 ID 不在 /9/501');
for (const id of [1073747157, 1073748248, 1073749965]) if (!mamas0.includes(id)) throw Error('既有地毯母本 ID 不在原型根 #503');

const SNAP = {
  rootPayload: Buffer.from(rootList.payload), rootLen: rootList.len,
  mamaPayload: Buffer.from(mamaList.payload), mamaLen: mamaList.len,
  scriptPayload: Buffer.from(scriptField.payload), scriptLen: scriptField.len,
  texts: textHits.map(h => ({ f: h.f, payload: Buffer.from(h.f.payload), len: h.f.len })),
  orderOrig: new Map(g.recs.map(r => [r.id, r.field.sub.slice()])),
};
function apply() {
  setChildList(rootList, [...ids0, ...R.rootList.append]);
  setChildList(mamaList, [...mamas0, ...R.protoRootChildList.append]);
  scriptField.payload = Buffer.from(LUA695, 'utf8'); scriptField.len = scriptField.payload.length;
  for (const h of textHits) { h.f.payload = Buffer.from(h.next, 'utf8'); h.f.len = h.f.payload.length; }
  for (const o of orderFix) {
    const sub = o.rec.field.sub;
    const [f504] = sub.splice(sub.findIndex(f => f.field === 504 && f.wt === 0), 1);
    const at = sub.findIndex(f => f.field === 505);
    sub.splice(at < 0 ? sub.length : at, 0, f504);
  }
}
function revert() {
  rootList.payload = Buffer.from(SNAP.rootPayload); rootList.len = SNAP.rootLen;
  mamaList.payload = Buffer.from(SNAP.mamaPayload); mamaList.len = SNAP.mamaLen;
  scriptField.payload = Buffer.from(SNAP.scriptPayload); scriptField.len = SNAP.scriptLen;
  SNAP.texts.forEach((o) => { o.f.payload = Buffer.from(o.payload); o.f.len = o.len; });
  for (const o of orderFix) o.rec.field.sub = o.original;
}

apply();
const bodyChanged = encodeMsg(g.tree);
if (bodyChanged.equals(BODY694)) throw Error('★ 改动没有写进编码树（写路径断了）');
const checksA = {
  rootListLen: asIdList(rootList.payload, true).length,
  mamaListLen: asIdList(mamaList.payload, true).length,
  script: scriptField.payload.toString('utf8') === LUA695,
  texts: textHits.every(h => h.f.payload.toString('utf8') === h.next),
  order: orderFix.every(o => {
    const sub = o.rec.field.sub;
    const i504 = sub.findIndex(f => f.field === 504 && f.wt === 0);
    const i505 = sub.findIndex(f => f.field === 505);
    return i504 >= 0 && (i505 < 0 || i504 < i505);
  }),
};
if (checksA.rootListLen !== R.rootList.after || checksA.mamaListLen !== R.protoRootChildList.after
    || !checksA.script || !checksA.texts || !checksA.order)
  throw Error('应用后内容自检失败 ' + JSON.stringify(checksA));

revert();
if (!encodeMsg(g.tree).equals(BODY694)) throw Error('★ 反向还原 694 未能逐字节一致');
apply();

const result = {
  version: 695,
  base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA, records: EXPECT,
          luaBytes: Buffer.byteLength(LUA694) },
  output: { expectRecords: EXPECT, added: 0, changedExisting: 5 + orderFix.length,
            luaBytes: Buffer.byteLength(LUA695) },
  registry: {
    rootList: `${R.rootList.before} → ${R.rootList.after}（+${R.rootList.append.join(', ')}）`,
    protoRootChildList: `${R.protoRootChildList.before} → ${R.protoRootChildList.after}（+${R.protoRootChildList.append.join(', ')}）`,
    thingsChildList: '13 项不变',
    fieldOrderFix: `${orderFix.length} 条新素材记录的顶层 #504 与既有模板对齐`,
  },
  lua: { patches: SPEC.luaPatches.length, reversible: true, revertToBase: '逐字节一致' },
  texts: { changed: TEXTS.texts.length, items: TEXTS.texts.map(t => `${t.old} → ${t.new}`) },
  puzzle: { note: '第7关仅换 C 姓名标签；卡序/谓词/答案/真假向量/墙门/家具全部不变' },
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── 写档（五闸 + 磁盘重读二次复核） ───────────────────────────────────
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '695 地毯原型注册与改名', expectRecs: EXPECT,
  expectMarker: undefined,
  assert(t) {
    if (!findScriptLeaf(t).buf.toString('utf8').includes('["name"] = "誊写员"'))
      return '内嵌 Lua 未改名';
    if ((asIdList(t.tree.find(f => f.field === 9).sub
          .find(f => f.field === 501 && f.wt === 2 && asIdList(f.payload, true) !== null).payload, true) || []).length
        !== R.rootList.after) return '/9/501 项数不符';
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '写后记录不一致 #' + r.id + ' ' + r.name;
    }
    return true;
  },
});

const disk = readGil(OUTPUT);
const dl = findScriptLeaf(disk).buf.toString('utf8');
if (disk.recs.length !== EXPECT) throw Error('磁盘记录数不符');
if (dl !== LUA695) throw Error('磁盘内嵌 Lua 不一致');
// 磁盘版反向还原 694
{
  const t = disk.tree.find(f => f.field === 9);
  const rl = t.sub.find(f => f.field === 501 && f.wt === 2 && asIdList(f.payload, true) !== null);
  const pr = t.sub.filter(f => f.field === 502).find(f => f.sub && f.sub.some(x => x.field === 501 && Number(x.num) === 1073741844));
  const ml = pr.sub.find(f => f.field === 503 && f.wt === 2 && asIdList(f.payload, true) !== null);
  const sf = findScriptLeaf(disk).field;
  const hits = [];
  (function walk(fs) { for (const f of fs) { if (f === sf) continue;
    if (f.isText && f.payload) { const s = f.payload.toString('utf8');
      const h = TEXTS.texts.find(x => x.new === s); if (h) hits.push({ f, back: h.old }); }
    if (f.sub) walk(f.sub); } })(disk.tree);
  if (hits.length !== TEXTS.texts.length) throw Error('磁盘静态文本命中数不符');
  const save = { rl: Buffer.from(rl.payload), ml: Buffer.from(ml.payload), sf: Buffer.from(sf.payload),
                 hs: hits.map(h => Buffer.from(h.f.payload)) };
  const set = (f, b) => { f.payload = b; f.len = b.length; };
  const orderRestore = disk.recs.filter(r => NEW_IDS.has(Number(r.id)))
    .map(r => ({ r, now: r.field.sub, back: SNAP.orderOrig.get(r.id) }));
  set(rl, Buffer.from(SNAP.rootPayload)); set(ml, Buffer.from(SNAP.mamaPayload));
  set(sf, Buffer.from(SNAP.scriptPayload));
  hits.forEach((h) => set(h.f, Buffer.from(h.back, 'utf8')));
  for (const o of orderRestore) o.r.field.sub = o.back;
  if (!encodeMsg(disk.tree).equals(BODY694)) throw Error('磁盘版无法反向逐字节还原 694');
  set(rl, Buffer.from(save.rl)); set(ml, Buffer.from(save.ml)); set(sf, Buffer.from(save.sf));
  hits.forEach((h, i) => set(h.f, save.hs[i]));
  for (const o of orderRestore) o.r.field.sub = o.now;
}
// 记录级差异清单（白名单判定交给独立校验器 校验695.mjs）
const changedIds = [];
for (const r of disk.recs) {
  const b = recBefore.get(r.id);
  if (b && !b.equals(encodeMsg([r.field]))) changedIds.push(r.id);
}
const changed = changedIds.length;
const rogue = 0;
fs.writeFileSync(path.join(DIR, '695_内嵌Lua_695.lua'), dl, 'utf8');
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.changedRecords = changed;
result.output.changedRecordIds = changedIds;
result.output.rogue = rogue;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '695_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
