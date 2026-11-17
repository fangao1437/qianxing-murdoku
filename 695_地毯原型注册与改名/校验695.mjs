// 695 · 独立结构校验器（不复用构建器的断言）
//   ① 两处原型注册表闭环  ② 三件套引用链  ③ 改名三处  ④ 白名单外零改动
//   ⑤ 全树反向逐字节还原 694  ⑥ roundtrip / luac -p
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, asIdList } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const F694 = path.join(DIR, '../694_地毯渲染修复/694_地毯渲染修复.gil');
const F695 = path.join(DIR, '695_地毯原型注册与改名.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '695_设计与补丁.json'), 'utf8'));
const TEXTS = JSON.parse(fs.readFileSync(path.join(DIR, '695_静态文本补丁.json'), 'utf8'));
const K = JSON.parse(fs.readFileSync(path.join(DIR, '695_关卡数据.json'), 'utf8'));

const A = readGil(F694), B = readGil(F695);
const checks = [];
const ck = (group, name, ok, detail) => checks.push({ group, name, pass: !!ok, detail: String(detail ?? '') });

function n9(g) { return g.tree.find(f => f.field === 9); }
function rootList(g) { return n9(g).sub.find(f => f.field === 501 && f.wt === 2 && asIdList(f.payload, true) !== null); }
function protoRoot(g) {
  return n9(g).sub.filter(f => f.field === 502)
    .find(f => f.sub && f.sub.some(x => x.field === 501 && Number(x.num) === 1073741844));
}
function mamaList(g) {
  const p = protoRoot(g);
  return p && p.sub.find(f => f.field === 503 && f.wt === 2 && asIdList(f.payload, true) !== null);
}
function thingsList(g) {
  const t = g.recs.find(r => r.name === 'things');
  const f = t && t.field.sub.find(x => x.field === 503 && x.wt === 2 && asIdList(x.payload, true) !== null);
  return f && (asIdList(f.payload, true) || []);
}
function texts(g) {
  const out = [];
  const sf = findScriptLeaf(g).field;
  (function walk(fs) { for (const f of fs) {
    if (f === sf) continue;
    if (f.isText && f.payload) out.push({ f, s: f.payload.toString('utf8') });
    if (f.sub) walk(f.sub);
  } })(g.tree);
  return out;
}
function recNums(r) {
  const out = [];
  (function walk(fs) { for (const f of fs) {
    if (f.num != null) out.push(Number(f.num));
    if (f.sub) walk(f.sub);
  } })(r.field.sub);
  return out;
}

// ── ① 规模 ────────────────────────────────────────────────────────────
ck('规模', '记录数 8007 与 694 相同', A.recs.length === B.recs.length && B.recs.length === 8007,
   `${A.recs.length} → ${B.recs.length}`);
ck('规模', '695 输出字节 ≠ 694', fs.statSync(F695).size !== fs.statSync(F694).size,
   `${fs.statSync(F694).size} → ${fs.statSync(F695).size}`);

// ── ② 注册表 ──────────────────────────────────────────────────────────
const ra = asIdList(rootList(A).payload, true), rb = asIdList(rootList(B).payload, true);
const ma = asIdList(mamaList(A).payload, true), mb = asIdList(mamaList(B).payload, true);
ck('注册表', '/9/501 43 → 45', ra.length === 43 && rb.length === 45, `${ra.length} → ${rb.length}`);
ck('注册表', '/9/501 前 43 项逐项不变', ra.every((x, i) => x === rb[i]), 'ok');
ck('注册表', '/9/501 新增 2 个新源 ID',
   SPEC.registryFix.rootList.append.every(id => rb.includes(id) && !ra.includes(id)),
   SPEC.registryFix.rootList.append.join(','));
ck('注册表', '/9/501 既有地毯/植物源 ID 全在',
   [1073747149, 1073748252, 1073749968, 1073753953].every(id => rb.includes(id)), '4/4');
ck('注册表', '原型根 #503 33 → 35', ma.length === 33 && mb.length === 35, `${ma.length} → ${mb.length}`);
ck('注册表', '原型根 #503 前 33 项逐项不变', ma.every((x, i) => x === mb[i]), 'ok');
ck('注册表', '原型根 #503 新增 2 个新母本 ID',
   SPEC.registryFix.protoRootChildList.append.every(id => mb.includes(id) && !ma.includes(id)),
   SPEC.registryFix.protoRootChildList.append.join(','));
ck('注册表', '原型根 #503 既有地毯母本全在',
   [1073747157, 1073748248, 1073749965].every(id => mb.includes(id)), '3/3');
const ta = thingsList(A), tb = thingsList(B);
ck('注册表', 'things.childList 13 项且与 694 逐项相同',
   ta.length === 13 && tb.length === 13 && ta.every((x, i) => x === tb[i]), `${ta.length}/${tb.length}`);

// ── ③ 三件套 + 引用链 ────────────────────────────────────────────────
const chain = [
  ['rug.4 源', 1073760711, null], ['rug.4 母本', 1073760712, 1073741844], ['rug.4 引用', 1073760713, 1073742795],
  ['rug.5 源', 1073760734, null], ['rug.5 母本', 1073760735, 1073741844], ['rug.5 引用', 1073760736, 1073742795],
];
for (const [nm, id, parent] of chain) {
  const r = B.recs.find(x => Number(x.id) === id);
  ck('素材三件套', nm + ' #' + id + ' 存在且父正确',
     !!r && String(r.parentId) === String(parent), r ? `${r.name} parent=${r.parentId}` : 'MISSING');
}
ck('素材三件套', 'rug.4 引用控件 referencedPrefabIndex 指向新源',
   recNums(B.recs.find(x => Number(x.id) === 1073760713)).includes(1073760711), 'ok');
ck('素材三件套', 'rug.5 引用控件 referencedPrefabIndex 指向新源',
   recNums(B.recs.find(x => Number(x.id) === 1073760736)).includes(1073760734), 'ok');
const L695 = findScriptLeaf(B).buf.toString('utf8');
ck('Lua 引用链', 'cfg.furn_tpl_prefab.rug_4/rug_5 = 新源 ID',
   L695.includes('rug_4    = 1073760711') && L695.includes('rug_5    = 1073760734'), 'ok');
ck('Lua 引用链', 'path_map 含 furn.rug.4 / .5',
   L695.includes('["furn.rug.4"] = "root/things/furn.rug.4"')
   && L695.includes('["furn.rug.5"] = "root/things/furn.rug.5"'), 'ok');
ck('Lua 引用链', '整块模板路径 _spawn_whole_rug 仍在',
   L695.includes('return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,'), 'ok');
ck('Lua 引用链', '逐格 rug_cell_els 仍关闭',
   !L695.includes('res.cell[cell[1]][cell[2]].els = F.rug_cell_els'), 'ok');
ck('Lua 引用链', '695 新增实例化失败诊断日志',
   L695.includes('地毯模板实例化失败：ckey='), 'ok');

// ── ④ 改名 ────────────────────────────────────────────────────────────
const tB = texts(B), tA = texts(A);
for (const t of TEXTS.texts) {
  const nOld = tB.filter(h => h.s === t.old).length, nNew = tB.filter(h => h.s === t.new).length;
  ck('改名', `静态文本「${t.old}」→「${t.new}」`,
     nOld === 0 && nNew === t.count && tA.filter(h => h.s === t.old).length === t.count,
     `695 old=${nOld} new=${nNew}; 694 old=${tA.filter(h => h.s === t.old).length}`);
}
ck('改名', '695 全档（含 Lua）无「墨绿誊写」',
   !L695.includes('墨绿誊写') && !tB.some(h => h.s.includes('墨绿誊写')), 'ok');
ck('改名', 'Lua case_007 suspects[C].name = 誊写员',
   L695.includes('["name"] = "誊写员"'), 'ok');
ck('改名', '695 名字表 names[7].C = 誊写员', K.names['7'].C === '誊写员', K.names['7'].C);
ck('改名', 'who.7.3 与名字表一致（who 不加字母）',
   tB.filter(h => h.s === K.names['7'].C).length === 1, 'ok');
ck('改名', 'what 正文保留字母前缀 C',
   tB.some(h => h.s === 'C誊写员比我靠左2列'), 'ok');

// ── ⑤ 白名单外零改动 ─────────────────────────────────────────────────
const NEW_IDS = new Set();
for (let id = SPEC.registryFix.fieldOrderFix.idRange[0]; id <= SPEC.registryFix.fieldOrderFix.idRange[1]; id++)
  NEW_IDS.add(id);
const before = new Map(A.recs.map(r => [r.id, encodeMsg([r.field])]));
const changed = B.recs.filter(r => {
  const b = before.get(r.id);
  return !b || !b.equals(encodeMsg([r.field]));
}).map(r => Number(r.id));
const TEXT_IDS = [1073760644, 1073760652];
ck('零改动', '记录级变动恰好 46 条（44 素材对齐 + 2 文本）',
   changed.length === 46 && TEXT_IDS.every(id => changed.includes(id)), String(changed.length));
ck('零改动', '白名单外零改动（rogue=0）',
   changed.every(id => NEW_IDS.has(id) || TEXT_IDS.includes(id)), changed.slice(0, 60).join(','));
ck('零改动', '其余 7961 条记录逐字节相同',
   B.recs.length - changed.length === 7961, String(B.recs.length - changed.length));
// R3：顶层 #504 位置
function p504(r) { return r.field.sub.findIndex(f => f.field === 504 && f.wt === 0); }
function p505(r) { const i = r.field.sub.findIndex(f => f.field === 505); return i < 0 ? 9999 : i; }
const newRecsB = B.recs.filter(r => NEW_IDS.has(Number(r.id)));
const newRecsA = A.recs.filter(r => NEW_IDS.has(Number(r.id)));
ck('R3 字段顺序', '46 条新素材记录齐全', newRecsB.length === 46 && newRecsA.length === 46,
   `${newRecsA.length}/${newRecsB.length}`);
ck('R3 字段顺序', '695：44 条带父记录的 #504 均在第一个 #505 之前',
   newRecsB.filter(r => p504(r) >= 0).every(r => p504(r) < p505(r)),
   `${newRecsB.filter(r => p504(r) >= 0).length} 条`);
ck('R3 字段顺序', '694 对照：这些 #504 原本都在记录末尾',
   newRecsA.filter(r => p504(r) >= 0).every(r => p504(r) > p505(r)), 'ok');
ck('R3 字段顺序', '既有可显示模板（rug.2 / plant.2）#504 本就在前部',
   [1073748254, 1073748253, 1073748248, 1073749162, 1073753948].every(id => {
     const r = B.recs.find(x => Number(x.id) === id);
     return r && p504(r) >= 0 && p504(r) < p505(r);
   }), '5/5');

// ── ⑥ 全树反向还原 694（逐字节） ─────────────────────────────────────
{
  const rl = rootList(B), ml = mamaList(B), sf = findScriptLeaf(B).field;
  const sfA = findScriptLeaf(A).field;
  const hits = TEXTS.texts.map(t => ({ f: tB.find(h => h.s === t.new).f, back: t.old }));
  const save = { rl: Buffer.from(rl.payload), ml: Buffer.from(ml.payload), sf: Buffer.from(sf.payload),
                 hs: hits.map(h => Buffer.from(h.f.payload)) };
  const set = (f, b) => { f.payload = b; f.len = b.length; };
  const orderRestore = B.recs.filter(r => NEW_IDS.has(Number(r.id)))
    .map(r => ({ r, now: r.field.sub, back: A.recs.find(x => x.id === r.id).field.sub }));
  set(rl, Buffer.from(rootList(A).payload)); set(ml, Buffer.from(mamaList(A).payload));
  set(sf, Buffer.from(sfA.payload));
  hits.forEach(h => set(h.f, Buffer.from(h.back, 'utf8')));
  for (const o of orderRestore) o.r.field.sub = o.back;
  const body694 = A.src.subarray(20, 20 + A.hdr[4]);
  ck('反向还原', '全部改动回退后重编码 == 694 body（逐字节）',
     encodeMsg(B.tree).equals(body694), `${encodeMsg(B.tree).length} / ${body694.length}`);
  set(rl, save.rl); set(ml, save.ml); set(sf, save.sf);
  hits.forEach((h, i) => set(h.f, save.hs[i]));
  for (const o of orderRestore) o.r.field.sub = o.now;
  ck('反向还原', '695 body 重编码与落盘字节一致',
     encodeMsg(B.tree).equals(B.src.subarray(20, 20 + B.hdr[4])), 'ok');
}

// ── ⑦ 外部闸门：roundtrip / luac -p ──────────────────────────────────
try {
  const out = execFileSync(process.execPath,
    [path.join(TOOLS, 'roundtrip.mjs'), F695], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  ck('外部闸门', 'roundtrip 逐字节往返 PASS', /PASS|一致|OK|✓/.test(out), out.trim().slice(0, 200));
} catch (e) {
  ck('外部闸门', 'roundtrip 逐字节往返 PASS', false, String(e.stdout || e.message).slice(0, 300));
}
{
  const tmp = path.join(os.tmpdir(), `gil695_syntax_${process.pid}.lua`);
  fs.writeFileSync(tmp, L695, 'utf8');
  try {
    execFileSync('"C:/Users/18182/AppData/Local/Programs/Lua/bin/luac"', ['-p', tmp],
                 { stdio: ['ignore', 'pipe', 'pipe'], shell: true, timeout: 60000 });
    ck('外部闸门', 'luac -p 内嵌 Lua 语法 PASS', true, 'ok');
  } catch (e) {
    ck('外部闸门', 'luac -p 内嵌 Lua 语法 PASS', false, String(e.stderr || e.message).slice(0, 300));
  } finally { fs.rmSync(tmp, { force: true }); }
}

const failed = checks.filter(c => !c.pass);
const out = { version: 695, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length,
              registry: { rootList: `${ra.length}→${rb.length}`, protoRoot: `${ma.length}→${mb.length}` },
              changedRecordIds: changed, checks };
fs.writeFileSync(path.join(DIR, '695_结构校验.json'), JSON.stringify(out, null, 2));
console.log(`695 结构校验 ${out.pass}/${out.total} PASS`);
for (const f of failed) console.log('  FAIL:', f.group, f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
