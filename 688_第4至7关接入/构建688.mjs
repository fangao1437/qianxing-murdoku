// 688 · 把第4/5/6/7关（v15 定稿）写入存档
//   基准 687（保留未改）。用法：node 构建688.mjs [--dry]
//
// 口径：
//   · 内嵌 Lua 4 处定点补丁（可反向逐字节还原）：LIST 注册、case_004 覆盖、
//     新增 case_005/006/007、方位词 only-axis 对称扩展。
//   · 静态文本：第4关覆盖人名/本人自述卡面；克隆 row.2.* 家族生成 5/6/7 关行控件
//     （第6关 7×7 需第 7 行）。选关屏每页复用 4 个卡位，无需新增卡片。
//   · 家具：objects 写入关卡 Lua（运行时由已有 furn.* 模板实例化），不动美术层。
//   · 浅蓝提示：hint 子控件沿用 687；逐卡格清单写入关卡 hint_preview 只读元数据。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const INPUT = path.join(REPO, '687_综合整改/687_综合整改.gil');
const OUTPUT = path.join(DIR, '688_第4至7关接入.gil');
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, cloneField, textsOf, bigIds, ensureChildListTop,
        findChildListTop, asIdList, setChildList, encodeMsg } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const PATCH = JSON.parse(fs.readFileSync(path.join(DIR, '688_内嵌Lua_补丁.json'), 'utf8'));
const TEXTS = JSON.parse(fs.readFileSync(path.join(DIR, '688_静态文本补丁.json'), 'utf8')).texts;
const DATA = JSON.parse(fs.readFileSync(path.join(DIR, '688_关卡数据.json'), 'utf8'));

const g = readGil(INPUT);
const before = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const byName = new Map(g.recs.map(r => [r.name, r]));
const R = n => { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const tn = r => ns(r.field, [505, 503, 75, 510, 501])[0];
const txt = (r, t) => {
  const f = tn(r); if (!f) throw Error('缺文本字段 ' + r.name);
  f.payload = Buffer.from(t); f.len = f.payload.length; changed.add(r.id);
};
const added = [], changed = new Set(), audit = [];
let max = BigInt(g.maxId);

// ── 1. 克隆行控件家族：row.<lv>.<i>（家族 5 条：root/who/letter/what/face） ──
function copyRow(srcLv, dstLv, srcI, dstI) {
  const root = R(`row.${srcLv}.${srcI}`);
  const family = g.recs.filter(r => r.id === root.id || r.parentId === root.id);
  const map = new Map(family.map(r => [r.id, Number(++max)]));
  for (const src of family) {
    const f = cloneField(src.field);
    const id = map.get(src.id);
    const name = src.name.replace(`.${srcLv}.${srcI}`, `.${dstLv}.${dstI}`);
    (function remap(a) {
      for (const q of a) {
        if (q.num !== undefined && map.has(Number(q.num))) q.num = BigInt(map.get(Number(q.num)));
        if (q.sub) remap(q.sub);
      }
    })(f.sub);
    const namef = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === src.name);
    if (!namef) throw Error('找不到记录名字段 ' + src.name);
    namef.payload = Buffer.from(name); namef.len = namef.payload.length;
    const cl = findChildListTop(f.sub);
    if (cl) setChildList(cl, asIdList(cl.payload, true).map(v => map.get(v) || v));
    // 插到 src 在 tree 中的 holder 之后（保持 recTop 顺序不变）
    const stack = [g.tree]; let found = false;
    while (stack.length && !found) {
      const a = stack.pop();
      for (let j = 0; j < a.length; j++) {
        const q = a[j]; if (!q.sub) continue;
        if (bigIds(q.sub, [])[0]?.num === BigInt(src.id)) { a.splice(j + 1, 0, f); found = true; break; }
        stack.push(q.sub);
      }
    }
    if (!found) throw Error('holder 未找到 ' + src.name);
    const r = { id, name, parentId: map.get(src.parentId) || src.parentId, field: f };
    added.push(r); byName.set(name, r);
  }
  const parent = g.recs.find(r => r.id === root.parentId);
  const cl = ensureChildListTop(parent);
  setChildList(cl, [...asIdList(cl.payload, true), map.get(root.id)]);
  changed.add(parent.id);
}

for (const item of DATA.levels) {
  const lv = item.level;
  const n = item.texts.length;
  if (lv === 4) {
    // 第4关已有 6 行静态控件：只覆盖文本
    for (const t of item.texts) {
      txt(R(`letter.4.${t.slot}`), t.letter);
      txt(R(`who.4.${t.slot}`), t.who);
      txt(R(`what.4.${t.slot}`), t.what);
      audit.push({ kind: 'text', level: 4, slot: t.slot, who: t.who, what: t.what });
    }
  } else {
    // 目标行 1..n；第6关 n=7 时第 7 行复用 row.2.6 家族作模板（几何在运行时按行号重排）
    for (let i = 1; i <= n; i++) copyRow(2, lv, Math.min(i, 6), i);
    for (const t of item.texts) {
      txt(byName.get(`letter.${lv}.${t.slot}`), t.letter);
      txt(byName.get(`who.${lv}.${t.slot}`), t.who);
      txt(byName.get(`what.${lv}.${t.slot}`), t.what);
      audit.push({ kind: 'text+clone', level: lv, slot: t.slot, who: t.who, what: t.what });
    }
  }
}

// ── 2. 内嵌 Lua 定点补丁 ───────────────────────────────────────────────
const leaf = findScriptLeaf(g).field;
let s = leaf.payload.toString('utf8');
const s0 = s;
function replaceOnce(old, neu, label) {
  const k = s.indexOf(old);
  if (k < 0) throw Error('补丁锚点未找到：' + label);
  if (s.indexOf(old, k + 1) >= 0) throw Error('补丁锚点不唯一：' + label);
  s = s.slice(0, k) + neu + s.slice(k + old.length);
}

// 2a LIST
replaceOnce(PATCH.patches[0].old, PATCH.patches[0].new, 'LIST');

// 2b case_004 模块整体替换 + 追加 005/006/007
const marker = '__M["levels.case_004"] = function()';
const i0 = s.indexOf(marker);
if (i0 < 0) throw Error('case_004 模块未找到');
const j0 = s.indexOf('\nend', i0);
if (j0 < 0) throw Error('case_004 模块结束未找到');
const oldModule = s.slice(i0, j0 + 4);
const newModules = PATCH.modules.join('\n');
s = s.slice(0, i0) + newModules.trimEnd() + s.slice(j0 + 4);

// 2c 方位词「只比轴」对称扩展：above 已有 same_column=false，
//    给 below / left_of / right_of 补同款可选分支（默认路径逐字节不变）。
const axisPatches = [
  {
    old: 'reg("below", {\n  params = { "a", "b" },\n  validate = function(ctx, cl) return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,',
    neu: 'reg("below", {\n  params = { "a", "b" },\n  validate = function(ctx, cl)\n    if cl.same_column == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)\n      return a ~= nil and b ~= nil and a.r > b.r end\n    return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,',
  },
  {
    old: 'reg("left_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl) return ctx.is_left_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,',
    neu: 'reg("left_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl)\n    if cl.same_row == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)\n      return a ~= nil and b ~= nil and a.c < b.c end\n    return ctx.is_left_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,',
  },
  {
    old: 'reg("right_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl) return ctx.is_left_of(ctx.pos(cl.b), ctx.pos(cl.a)) end,',
    neu: 'reg("right_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl)\n    if cl.same_row == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)\n      return a ~= nil and b ~= nil and a.c > b.c end\n    return ctx.is_left_of(ctx.pos(cl.b), ctx.pos(cl.a)) end,',
  },
];
for (let i = 0; i < axisPatches.length; i++)
  replaceOnce(axisPatches[i].old, axisPatches[i].neu, 'axis patch ' + i);

const script = Buffer.from(s, 'utf8');
leaf.payload = script; leaf.len = script.length;

// ── 3. 写档（五闸） ────────────────────────────────────────────────────
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const result = {
  base: { file: path.relative(ROOT, INPUT), sha256: sha(INPUT), records: g.recs.length,
          scriptBytes: Buffer.byteLength(s0) },
  output: { scriptBytes: script.length, added: added.length,
            changedExisting: changed.size, expectRecords: expected.size },
  patches: ['LIST 注册 5/6/7', 'case_004 覆盖', 'case_005/006/007 新增',
            'below/left_of/right_of 只比轴对称扩展'],
  texts: audit,
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

writeGil(g, OUTPUT, {
  label: '688 第4至7关接入', expectRecs: expected.size,
  assert(t) {
    const l = findScriptLeaf(t);
    if (!l.buf.equals(script)) return 'script mismatch';
    for (const r of t.recs) {
      const e = expected.get(r.id);
      if (!e || !e.equals(encodeMsg([r.field]))) return 'record mismatch ' + r.name;
    }
    return true;
  },
});

// ── 4. 磁盘重读复核 ────────────────────────────────────────────────────
const disk = readGil(OUTPUT);
const names = new Map(disk.recs.map(r => [r.name, r]));
let rogue = 0;
for (const r of disk.recs)
  if (before.has(r.id) && !changed.has(r.id) && !before.get(r.id).equals(encodeMsg([r.field]))) rogue++;
if (rogue) throw Error('出现白名单外旧记录改动：' + rogue);
const diskLeaf = findScriptLeaf(disk);
if (!diskLeaf.buf.equals(script)) throw Error('磁盘内嵌 Lua 不一致');
for (const item of DATA.levels)
  for (const t of item.texts)
    for (const [slot, val] of [['letter', t.letter], ['who', t.who], ['what', t.what]]) {
      const r = names.get(`${slot}.${item.level}.${t.slot}`);
      if (!r) throw Error('缺静态文本 ' + slot + '.' + item.level + '.' + t.slot);
      if (tn(r).payload.toString('utf8') !== val) throw Error('文本不符 ' + r.name);
    }
result.output.sha256 = sha(OUTPUT);
result.output.recordsOnDisk = disk.recs.length;
result.output.rogue = rogue;
result.output.luaRoundtrip = true;
result.output.textVerified = true;
fs.writeFileSync(path.join(DIR, '688_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify({ records: disk.recs.length, added: added.length,
  changedExisting: changed.size, rogue, sha256: result.output.sha256 }, null, 2));
