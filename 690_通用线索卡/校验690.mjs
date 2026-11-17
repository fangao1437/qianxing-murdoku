// 690 · 独立结构校验器（不复用 构建690.mjs 的任何断言对象）
// 用法：node 校验690.mjs  → 690_结构校验.json（verdict=true 才通过）
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const F689 = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_性能负载优化.gil');
const F690 = path.join(DIR, '690_通用线索卡.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '690_通用线索卡图元.json'), 'utf8'));
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const { isHiddenRecord, imageTriple } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const g0 = readGil(F689), g1 = readGil(F690);
const s689 = findScriptLeaf(g0).buf.toString('utf8');
const s690 = findScriptLeaf(g1).buf.toString('utf8');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });

// ① 基准与产物
ck('689 基准 SHA 前缀', sha(F689).startsWith('f8798b9c89b1'), sha(F689).slice(0, 16));
ck('689 记录数 7921', g0.recs.length === 7921, g0.recs.length);
ck('690 记录数 7945', g1.recs.length === 7945, g1.recs.length);
ck('产物 SHA 与构建审计一致', (() => {
  const a = JSON.parse(fs.readFileSync(path.join(DIR, '690_构建审计.json'), 'utf8'));
  return a.output.sha256 === sha(F690);
})(), sha(F690).slice(0, 16));
ck('689 原件未被覆盖', fs.statSync(F689).size === 6984401, fs.statSync(F689).size);

// ② 逐记录比对：非目标记录逐字节全同
const m0 = new Map(g0.recs.map(r => [r.id, encodeMsg([r.field])]));
const m1 = new Map(g1.recs.map(r => [r.id, encodeMsg([r.field])]));
const addedIds = [...m1.keys()].filter(id => !m0.has(id));
const removedIds = [...m0.keys()].filter(id => !m1.has(id));
ck('新增记录恰好 24 条', addedIds.length === 24, addedIds.length);
ck('删除记录 0 条', removedIds.length === 0, removedIds.length);
const changed = [...m0.keys()].filter(id => !m1.get(id).equals(m0.get(id)));
const EXPECTED_CHANGED = new Set([
  1073742421, 1073742428,            // 两套 clue 根的 childList
  1073742807, 1073742804,            // gen.backrop
  1073742808, 1073742805,            // gen.title
  1073742809, 1073742806,            // gen.body
]);
ck('被修改的原记录恰好 8 条且全在预期名单', changed.length === 8 && changed.every(id => EXPECTED_CHANGED.has(id)),
  changed.join(','));
const rogue = changed.filter(id => !EXPECTED_CHANGED.has(id));
ck('rogue 改动 = 0', rogue.length === 0, rogue.join(','));
ck('未列入名单的 7913 条原记录逐字节全同',
  [...m0.keys()].filter(id => !EXPECTED_CHANGED.has(id)).every(id => m1.get(id).equals(m0.get(id))), 'checked');

// ③ 新层套装、隐藏、父归属、层序
const names = SPEC.layers.map(s => s.name);
const addedRecs = g1.recs.filter(r => addedIds.includes(r.id));
ck('新层名字集合与规格一致',
  names.every(n => addedRecs.filter(r => r.name === n).length === 2)
  && addedRecs.every(r => names.includes(r.name)), addedRecs.map(r => r.name).join(','));
ck('新层全部静态隐藏', addedRecs.every(r => isHiddenRecord(r.field)),
  addedRecs.filter(r => !isHiddenRecord(r.field)).map(r => r.name).join(','));
const roots = g1.recs.filter(r => r.name === 'clue' && g1.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
ck('两套 clue 模板', roots.length === 2, roots.map(r => r.id).join(','));
ck('新层全部挂在两套 clue 根下',
  addedRecs.every(r => roots.some(q => q.id === r.parentId)), 'ok');
for (const root of roots) {
  const cl = findChildListTop(root.field.sub);
  const seq = (asIdList(cl.payload, true) || []).map(id => g1.recs.find(q => q.id === id)?.name);
  const ib = seq.indexOf('gen.backrop'), it = seq.indexOf('gen.title'), ibody = seq.indexOf('gen.body');
  const ix = seq.map((n, i) => /^gen690\./.test(n || '') ? i : -1).filter(i => i >= 0);
  ck(`层序 #${root.id}：gen.backrop < gen690×12 < gen.title < gen.body`,
    ib >= 0 && it >= 0 && ibody >= 0 && ix.length === 12
    && Math.min(...ix) > ib && Math.max(...ix) < it && it < ibody,
    `backrop=${ib} gen690=${Math.min(...ix)}..${Math.max(...ix)} title=${it} body=${ibody}`);
  const recTop = g1.tree.find(q => q.field === 9);
  const idx = new Map(); recTop.sub.forEach((f, i) => idx.set(f, i));
  const ids = (asIdList(cl.payload, true) || []);
  ck(`childList 与 recTop 同序 #${root.id}`,
    ids.every((id, i) => i === 0 || idx.get(g1.recs.find(q => q.id === ids[i - 1])?.field)
      <= idx.get(g1.recs.find(q => q.id === id)?.field)), 'ok');
}
// 隐藏层计数
const hid0 = g0.recs.filter(r => isHiddenRecord(r.field)).length;
const hid1 = g1.recs.filter(r => isHiddenRecord(r.field)).length;
ck('隐藏层 945 → 969（+24，全部为新增层）', hid0 === 945 && hid1 === 969, `${hid0} → ${hid1}`);

// ④ 普通卡可见层零改动
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function normalLayers(g) {
  return g.recs.filter(r => r.parentId === 1073742421 && r.name
    && /^(backrop1|backrop2|art671\.clue1\.|art672\.clue1\.)/.test(r.name) && !isHiddenRecord(r.field))
    .map(r => {
      const st = stateBlocks(r.field.sub, [])[0];
      const p = st && pairOf(st, 504), s = st && pairOf(st, 505), ip = imageTriple(r.field);
      return [r.name, pairValue(p, 0), pairValue(p, 1), pairValue(s, 0), pairValue(s, 1),
        num(ip?.node, 502), num(ip?.node, 503), st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0].join('|');
    }).sort();
}
ck('普通卡 8 个可见视觉层逐字段相同',
  JSON.stringify(normalLayers(g0)) === JSON.stringify(normalLayers(g1)), normalLayers(g1).length);
ck('普通卡 backrop1 高亮基色仍 #FF491B1E',
  (() => { const r = g1.recs.find(q => q.id === 1073742422); return num(imageTriple(r.field).node, 502) === 0xFF491B1E; })(), 'ok');

// ⑤ gen.* 三件改造结果
const kid = (g, pid, nm) => g.recs.find(r => r.parentId === pid && r.name === nm);
for (const root of roots) {
  const gb = kid(g1, root.id, 'gen.backrop'), gt = kid(g1, root.id, 'gen.title'), gbody = kid(g1, root.id, 'gen.body');
  const ip = imageTriple(gb.field);
  ck(`gen.backrop #${root.id}：100001 / 330×85.4 / #FF20304F / 隐藏`,
    num(ip.node, 503) === 100001 && num(ip.node, 502) === 0xFF20304F
    && Math.abs(pairValue(pairOf(stateBlocks(gb.field.sub, [])[0], 505), 0) - 330) < 0.01
    && Math.abs(pairValue(pairOf(stateBlocks(gb.field.sub, [])[0], 505), 1) - 85.4) < 0.01
    && isHiddenRecord(gb.field), 'ok');
  const tp = ns(gt.field, [505, 503, 75])[0], bp = ns(gbody.field, [505, 503, 75])[0];
  ck(`gen.title #${root.id}：文案「通用线索」不变 / 字色金`,
    num(tp, 504) === 0xFFE8C877
    && (() => { let hit = false; (function w(f) { if (f.wt === 2 && f.payload?.toString('utf8') === '通用线索') hit = true; for (const q of f.sub || []) w(q); })(gt.field); return hit; })(), 'ok');
  ck(`gen.body #${root.id}：236×56 @ (14,-2) / 白字 / 可见`,
    Math.abs(pairValue(pairOf(stateBlocks(gbody.field.sub, [])[0], 504), 0) - 14) < 0.01
    && Math.abs(pairValue(pairOf(stateBlocks(gbody.field.sub, [])[0], 505), 0) - 236) < 0.01
    && num(bp, 504) === 0xFFFFFFFF && !isHiddenRecord(gbody.field), 'ok');
}

// ⑥ 静态文本零改动（原记录）
function textsOfRec(r) {
  const out = [];
  (function w(f) { if (f.wt === 2 && f.payload && f.len > 0 && f.isText) out.push(f.payload.toString('utf8')); for (const q of f.sub || []) w(q); })(r.field);
  return out.join('');
}
const textChanged = [...m0.keys()].filter(id => !EXPECTED_CHANGED.has(id)
  && textsOfRec(g0.recs.find(r => r.id === id)) !== textsOfRec(g1.recs.find(r => r.id === id)));
ck('原记录静态文本零改动', textChanged.length === 0, textChanged.join(','));
ck('新增文本控件只有「公」「真」', (() => {
  const t = addedRecs.filter(r => SPEC.layers.filter(s => s.proto === 'text').some(s => s.name === r.name))
    .map(textsOfRec);
  return t.length === 4 && t.filter(x => x.includes('公')).length === 2 && t.filter(x => x.includes('真')).length === 2;
})(), 'ok');

// ⑦ 内嵌 Lua：补丁、可逆性、689 性能优化保留
const OLD_LIST = SPEC.lua.oldList;
const NEW_LIST = `ipairs({ ${SPEC.lua.genLayers.map(n => `"${n}"`).join(', ')} })`;
const HL_OLD = `    pcall(function() _cp = item:FindChild("backrop1") end)`;
const HL_NEW = `    pcall(function() _cp = item:FindChild("gen.backrop") end)`;
ck('690 Lua：显隐名单 2 处、每项 15 层', s690.split(NEW_LIST).length - 1 === 2
  && SPEC.lua.genLayers.length === 15, 'ok');
ck('690 Lua：高亮目标改为 gen.backrop', s690.split(HL_NEW).length - 1 === 1, 'ok');
ck('690 Lua：反向补丁逐字节还原 689',
  s690.split(NEW_LIST).join(OLD_LIST).split(HL_NEW).join(HL_OLD) === s689, `${s689.length} → ${s690.length}`);
ck('689 性能补丁全部保留',
  ['_mark_layer_raise', 'sync_art647', 'sync_art649_page', 'sync_block640', 'HIGHLIGHT_TINT = 4294956107']
    .every(k => s690.includes(k)), 'ok');
ck('685 每帧抬层不变式 / 686 离场收起仍在',
  s690.includes('_mark_layer_raise') && s690.includes('on_tick'), 'ok');
ck('通用线索交互链路未改',
  ['focus_general', 'general_focus', '_has_general_clue', 'clue_hint_general'].every(k => s690.includes(k)), 'ok');

// ⑦b 运行时名单 ↔ 存档控件对账（证明「点亮/熄灭」真的能命中每个新层）
const lists = [...s690.matchAll(/ipairs\(\{([^}]*gen690\.[^}]*)\}\)/g)].map(m => [...m[1].matchAll(/"([^"]+)"/g)].map(x => x[1]));
ck('Lua 两处显隐名单完全一致', lists.length === 2 && JSON.stringify(lists[0]) === JSON.stringify(lists[1]),
  lists.map(l => l.length).join('/'));
ck('名单 = 规格 15 层（gen.* 3 + gen690.* 12）',
  JSON.stringify(lists[0]) === JSON.stringify(SPEC.lua.genLayers), lists[0]?.length);
ck('名单里每个名字在两套 clue 模板下都找得到',
  lists[0].every(n => roots.every(root => g1.recs.some(r => r.parentId === root.id && r.name === n))), 'ok');
ck('新增 12 层全部进入显隐名单',
  names.every(n => lists[0].includes(n)), names.filter(n => !lists[0].includes(n)).join(','));
// 字号：徽记与字母徽同口径
const textField = (pid, nm) => {
  const r = kid(g1, pid, nm);
  return r ? ns(r.field, [505, 503, 75])[0] : null;
};
const f = (p, k) => num(p, k);
ck('「真」字号与 letter 一致（30/20）', (() => {
  const a = textField(1073742421, 'gen690.badge'), b = textField(1073742421, 'letter');
  return f(a, 512) === f(b, 512) && f(a, 513) === f(b, 513) && f(a, 512) === 30;
})(), 'ok');
ck('「公」字号略收（24/18）', (() => {
  const a = textField(1073742421, 'gen690.mark');
  return f(a, 512) === 24 && f(a, 513) === 18;
})(), 'ok');

// ⑧ luac -p（中文路径会乱码 ⇒ 复制到 ASCII 临时名）
function luacOk(text, tag) {
  const tmp = path.join(os.tmpdir(), `gil690_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, text, 'utf8');
  try { execFileSync('luac', ['-p', tmp], { stdio: 'pipe' }); return true; }
  catch (e) { return String(e.stderr || e.message).slice(0, 200); }
  finally { fs.rmSync(tmp, { force: true }); }
}
const L689 = luacOk(s689, 'a689'), L690 = luacOk(s690, 'a690');
ck('luac -p 689', L689 === true, L689 === true ? 'ok' : L689);
ck('luac -p 690', L690 === true, L690 === true ? 'ok' : L690);

// ⑨ 落盘脚本与存档一致
const diskLua = fs.readFileSync(path.join(DIR, '690_内嵌Lua_690.lua'), 'utf8');
ck('690_内嵌Lua_690.lua 与存档内嵌脚本一致', diskLua === s690, diskLua.length);

const pass = checks.filter(c => c.pass).length, fail = checks.length - pass;
const report = { version: 690, verdict: fail === 0, pass, fail, checks,
  base: { file: path.basename(F689), sha256: sha(F689), records: g0.recs.length, hidden: hid0 },
  output: { file: path.basename(F690), sha256: sha(F690), bytes: fs.statSync(F690).size,
    records: g1.recs.length, hidden: hid1 },
  timestamp: new Date().toISOString() };
fs.writeFileSync(path.join(DIR, '690_结构校验.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ verdict: report.verdict, pass, fail,
  failed: checks.filter(c => !c.pass) }, null, 2));
if (fail) process.exit(1);
