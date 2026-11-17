// 688 独立校验（不复用构建脚本的断言对象）
//   ① 逐记录按 id 比对 687 与 688，白名单外零改动
//   ② 新增记录名字唯一、父子关系完整
//   ③ 内嵌 Lua 反向补丁可逐字节还原 687
//   ④ 静态文本 / 顺序 / 家具 / 提示格逐条核对
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const A = path.join(REPO, '687_综合整改/687_综合整改.gil');
const B = path.join(DIR, '688_第4至7关接入.gil');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, asIdList, findChildListTop } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

const a = readGil(A), b = readGil(B);
const Arec = new Map(a.recs.map(r => [r.id, r]));
const Brec = new Map(b.recs.map(r => [r.id, r]));
const ns = (f, ks) => ks.reduce((x, k) => x.flatMap(y => (y.sub || []).filter(z => z.field === k)), [f]);
const tn = r => { const f = ns(r.field, [505, 503, 75, 510, 501])[0]; return f?.payload?.toString('utf8') ?? null; };
const DATA = JSON.parse(fs.readFileSync(path.join(DIR, '688_关卡数据.json'), 'utf8'));
const TEXTS = JSON.parse(fs.readFileSync(path.join(DIR, '688_静态文本补丁.json'), 'utf8')).texts;
const HINTS = JSON.parse(fs.readFileSync(path.join(DIR, '688_浅蓝提示格.json'), 'utf8')).levels;
const PATCH = JSON.parse(fs.readFileSync(path.join(DIR, '688_内嵌Lua_补丁.json'), 'utf8'));
const checks = [];
const ck = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail }); if (!ok) console.log('  FAIL', name, detail); };

// ① 旧记录逐条：白名单 = 第4关 18 条文本 + assets 父容器
const allowed = new Set();
for (let i = 1; i <= 6; i++)
  for (const s of ['letter', 'who', 'what']) {
    const r = Arec.get([...Arec.values()].find(x => x.name === `${s}.4.${i}`)?.id);
    if (r) allowed.add(r.id);
  }
const assets = [...Arec.values()].find(r => r.name === 'assets');
if (assets) allowed.add(assets.id);
let rogue = [], changedAllowed = 0;
for (const [id, r] of Arec) {
  const q = Brec.get(id);
  if (!q) { rogue.push('记录丢失 ' + r.name); continue; }
  if (!encodeMsg([r.field]).equals(encodeMsg([q.field]))) {
    if (allowed.has(id)) changedAllowed++;
    else rogue.push('白名单外改动 ' + r.name);
  }
}
ck('旧记录白名单外零改动 (rogue=0)', rogue.length === 0, rogue.slice(0, 8));
// 文本值本就相同的记录不会产生字段 diff，故白名单内改动数 ≤ 19 且全部落在白名单
ck('白名单内改动均为第4关文本/父容器', changedAllowed <= 18 + 1 && changedAllowed > 0,
   changedAllowed);

// ② 新增记录
const added = b.recs.filter(r => !Arec.has(r.id));
ck('新增记录数 = 95', added.length === 95, added.length);
// 687 基线本就有 1570 个 null/容器重复名；只需保证「新增记录」名字唯一且不与旧名冲突
const aname = a.recs.map(r => r.name);
const adup = new Set(aname.filter((n, i) => aname.indexOf(n) !== i));
const bnames = b.recs.map(r => r.name);
const newDup = bnames.filter((n, i) => bnames.indexOf(n) !== i && !adup.has(n));
ck('新增记录名唯一（基线固有重复名不计）', newDup.length === 0, [...new Set(newDup)].slice(0, 6));
const oldNames = new Set(aname);
ck('新增记录名不与旧名冲突',
   added.every(r => !oldNames.has(r.name)), added.filter(r => oldNames.has(r.name)).map(r => r.name));
const dangling = added.filter(r => r.parentId != null && !Brec.has(r.parentId));
ck('新增记录无悬空父', dangling.length === 0, dangling.map(r => r.name).slice(0, 6));
for (const item of DATA.levels) {
  const lv = item.level, n = item.texts.length;
  for (let i = 1; i <= n; i++) {
    const root = b.recs.find(r => r.name === `row.${lv}.${i}`);
    if (!root) { ck(`row.${lv}.${i} 存在`, false); continue; }
    const cl = findChildListTop(root.field.sub);
    const kids = cl ? asIdList(cl.payload, true) : [];
    const okSlots = ['who', 'letter', 'what'].every(s => {
      const r = b.recs.find(x => x.name === `${s}.${lv}.${i}`);
      return r && r.parentId === root.id && kids.includes(r.id);
    });
    ck(`row.${lv}.${i} 三文本父子链接`, okSlots);
  }
}
ck('第6关第7行存在', b.recs.some(r => r.name === 'row.6.7'));

// ③ 静态文本逐条（含顺序）
let textBad = [];
for (const item of DATA.levels)
  for (const t of item.texts)
    for (const [slot, val] of [['letter', t.letter], ['who', t.who], ['what', t.what]]) {
      const r = b.recs.find(x => x.name === `${slot}.${item.level}.${t.slot}`);
      if (!r || tn(r) !== val) textBad.push(`${slot}.${item.level}.${t.slot}`);
    }
ck('静态文本 75 处逐条一致', textBad.length === 0, textBad.slice(0, 8));
// 前两关文本未被改动
let oldBad = [];
for (const lv of [1, 2, 3])
  for (let i = 1; i <= (lv === 1 ? 5 : 6); i++)
    for (const s of ['who', 'letter', 'what']) {
      const x = a.recs.find(r => r.name === `${s}.${lv}.${i}`);
      const y = b.recs.find(r => r.name === `${s}.${lv}.${i}`);
      if (x && y && tn(x) !== tn(y)) oldBad.push(`${s}.${lv}.${i}`);
    }
ck('前3关静态文本零改动', oldBad.length === 0, oldBad.slice(0, 8));

// ④ 内嵌 Lua：反向补丁还原 687（逐字节）
const sa = findScriptLeaf(a).buf.toString('utf8');
const sb = findScriptLeaf(b).buf.toString('utf8');
let rev = sb;
// 反做 2c 方位补丁
const axis = [
  ['reg("below", {\n  params = { "a", "b" },\n  validate = function(ctx, cl)\n    if cl.same_column == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)\n      return a ~= nil and b ~= nil and a.r > b.r end\n    return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,',
   'reg("below", {\n  params = { "a", "b" },\n  validate = function(ctx, cl) return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,'],
  ['reg("left_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl)\n    if cl.same_row == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)\n      return a ~= nil and b ~= nil and a.c < b.c end\n    return ctx.is_left_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,',
   'reg("left_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl) return ctx.is_left_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,'],
  ['reg("right_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl)\n    if cl.same_row == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)\n      return a ~= nil and b ~= nil and a.c > b.c end\n    return ctx.is_left_of(ctx.pos(cl.b), ctx.pos(cl.a)) end,',
   'reg("right_of", {\n  params = { "a", "b" },\n  validate = function(ctx, cl) return ctx.is_left_of(ctx.pos(cl.b), ctx.pos(cl.a)) end,'],
];
for (const [neu, old] of axis) { if (!rev.includes(neu)) throw Error('反向补丁锚点缺失'); rev = rev.replace(neu, old); }
// 反做 2b 模块：定位新模块整体，换回旧 case_004
const i0 = rev.indexOf('__M["levels.case_004"] = function()');
const iEnd = rev.indexOf('__M["levels.case_007"] = function()');
if (i0 < 0 || iEnd < 0) throw Error('模块边界缺失');
const jEnd = rev.indexOf('\nend', iEnd);
const oldModule = sa.slice(sa.indexOf('__M["levels.case_004"] = function()'),
                           sa.indexOf('\nend', sa.indexOf('__M["levels.case_004"] = function()')) + 4);
rev = rev.slice(0, i0) + oldModule + rev.slice(jEnd + 4);
// 反做 2a LIST
rev = rev.replace(PATCH.patches[0].new, PATCH.patches[0].old);
ck('内嵌 Lua 反向补丁逐字节还原 687', rev === sa,
   rev === sa ? '' : `长度 ${Buffer.byteLength(rev)} vs ${Buffer.byteLength(sa)}`);
fs.writeFileSync(path.join(DIR, '688_内嵌Lua_688.lua'), sb, 'utf8');
ck('688 注册 7 关',
   ['case_001', 'case_002', 'case_003', 'case_004', 'case_005', 'case_006', 'case_007']
     .every(x => sb.includes(`__M["levels.${x}"]`)));
ck('688 无未注册线索类型', !/above_any|below_any|left_any|right_any/.test(sb));

// ⑤ 家具 / 提示格 / 顺序元数据
let hintBad = [];
for (const item of DATA.levels) {
  const lv = item.level;
  const preview = item.lua.hint_preview;
  for (const h of HINTS[String(lv)]) {
    const p = preview[String(h.slot)];
    if (!p || p.count !== h.count || JSON.stringify(p.cells) !== JSON.stringify(h.cells))
      hintBad.push(`${lv}-${h.slot}`);
  }
}
ck('hint_preview 与逐卡提示格清单一致', hintBad.length === 0, hintBad.slice(0, 8));
const furniture = {};
for (const item of DATA.levels) furniture[item.level] = Object.keys(item.lua.objects);
ck('四关家具类型均在本地已支持6类内',
   Object.values(furniture).flat().every(k => ['桌子', '椅子', '书架', '植物', '地毯'].includes(k)),
   JSON.stringify(furniture));

const pass = checks.filter(c => c.ok).length;
const out = { timestamp: new Date().toISOString(),
  base: { sha256: crypto.createHash('sha256').update(fs.readFileSync(A)).digest('hex'), records: a.recs.length },
  output: { sha256: crypto.createHash('sha256').update(fs.readFileSync(B)).digest('hex'), records: b.recs.length },
  checks: checks.length, pass, fail: checks.length - pass,
  verdict: pass === checks.length, details: checks };
fs.writeFileSync(path.join(DIR, '688_校验报告.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify({ checks: checks.length, pass, fail: checks.length - pass,
  verdict: out.verdict, records: b.recs.length }, null, 2));
if (!out.verdict) process.exit(1);
