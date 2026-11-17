// 691 · 独立结构校验器（不复用 构建691.mjs 的任何断言对象）
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
const F691 = path.join(DIR, '691_橙黄通用卡与真机修复.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '691_设计与补丁.json'), 'utf8'));
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(TOOLS, 'gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(TOOLS, 'gilwrite.mjs')).href);
const { isHiddenRecord, imageTriple } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const g0 = readGil(F689), g1 = readGil(F691);
const s689 = findScriptLeaf(g0).buf.toString('utf8');
const s691 = findScriptLeaf(g1).buf.toString('utf8');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };

// ① 基准与产物
ck('689 基准 SHA 前缀', sha(F689).startsWith('f8798b9c89b1'), sha(F689).slice(0, 16));
ck('689 记录数 7921', g0.recs.length === 7921, g0.recs.length);
ck('691 记录数 7961', g1.recs.length === 7961, g1.recs.length);
ck('产物 SHA 与构建审计一致', (() => {
  const a = JSON.parse(fs.readFileSync(path.join(DIR, '691_构建审计.json'), 'utf8'));
  return a.output.sha256 === sha(F691);
})(), sha(F691).slice(0, 16));
ck('689 原件未被覆盖', fs.statSync(F689).size === 6984401, fs.statSync(F689).size);
ck('690 历史版本仍在', fs.existsSync(path.join(ROOT, 'qianxing-murdoku/690_通用线索卡/690_通用线索卡.gil')), 'ok');

// ② 逐记录比对
const m0 = new Map(g0.recs.map(r => [r.id, encodeMsg([r.field])]));
const m1 = new Map(g1.recs.map(r => [r.id, encodeMsg([r.field])]));
const addedIds = [...m1.keys()].filter(id => !m0.has(id));
const removedIds = [...m0.keys()].filter(id => !m1.has(id));
ck('新增记录恰好 40 条', addedIds.length === 40, addedIds.length);
ck('删除记录 0 条', removedIds.length === 0, removedIds.length);
const EXPECTED_CHANGED = new Set([
  1073742421, 1073742428, 1073742807, 1073742804, 1073742808, 1073742805,
  1073742809, 1073742806, 1073754315,
]);
const changed = [...m0.keys()].filter(id => !m1.get(id).equals(m0.get(id)));
ck('被修改的原记录恰好 9 条且全在预期名单',
  changed.length === 9 && changed.every(id => EXPECTED_CHANGED.has(id)), changed.join(','));
ck('rogue 改动 = 0', changed.filter(id => !EXPECTED_CHANGED.has(id)).length === 0, 'ok');
ck('未列入名单的 7912 条原记录逐字节全同',
  [...m0.keys()].filter(id => !EXPECTED_CHANGED.has(id)).every(id => m1.get(id).equals(m0.get(id))), 'checked');

// ③ 通用线索卡
const layerNames = SPEC.card.layers.map(s => s.name);
const added = g1.recs.filter(r => addedIds.includes(r.id));
ck('7 层通用卡图元 × 2 套', layerNames.every(n => added.filter(r => r.name === n).length === 2), 'ok');
ck('通用卡新层全部静态隐藏', added.filter(r => /^gen691\./.test(r.name)).every(r => isHiddenRecord(r.field)), 'ok');
const roots = g1.recs.filter(r => r.name === 'clue' && g1.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
ck('两套 clue 模板', roots.length === 2, roots.map(r => r.id).join(','));
for (const root of roots) {
  const cl = findChildListTop(root.field.sub);
  const seq = (asIdList(cl.payload, true) || []).map(id => g1.recs.find(q => q.id === id)?.name);
  const ib = seq.indexOf('gen.backrop'), it = seq.indexOf('gen.title'), ibody = seq.indexOf('gen.body');
  const ix = seq.map((n, i) => /^gen691\./.test(n || '') ? i : -1).filter(i => i >= 0);
  ck(`层序 #${root.id}：gen.backrop < gen691×7 < gen.title < gen.body`,
    ib >= 0 && it >= 0 && ix.length === 7 && Math.min(...ix) > ib && Math.max(...ix) < it && it < ibody,
    `backrop=${ib} gen691=${Math.min(...ix)}..${Math.max(...ix)} title=${it} body=${ibody}`);
  const gb = g1.recs.find(r => r.parentId === root.id && r.name === 'gen.backrop');
  const ip = imageTriple(gb.field);
  ck(`gen.backrop #${root.id}：100001 / 330×85.4 / 橙棕 #FF9A4A18 / 隐藏`,
    num(ip.node, 503) === 100001 && num(ip.node, 502) === 0xFF9A4A18
    && Math.abs(pairValue(pairOf(stateBlocks(gb.field.sub, [])[0], 505), 0) - 330) < 0.01
    && Math.abs(pairValue(pairOf(stateBlocks(gb.field.sub, [])[0], 505), 1) - 85.4) < 0.01
    && isHiddenRecord(gb.field), 'ok');
  for (const nm of ['gen.title', 'gen.body']) {
    const r = g1.recs.find(q => q.parentId === root.id && q.name === nm);
    const tp = ns(r.field, [505, 503, 75])[0];
    ck(`${nm} #${root.id} 深棕字 #FF4A2A12`, num(tp, 504) === 0xFF4A2A12, 'ok');
  }
  const gbody = g1.recs.find(r => r.parentId === root.id && r.name === 'gen.body');
  const st = stateBlocks(gbody.field.sub, [])[0];
  ck(`gen.body #${root.id} 居中 260×60`, Math.abs(pairValue(pairOf(st, 505), 0) - 260) < 0.01
    && Math.abs(pairValue(pairOf(st, 505), 1) - 60) < 0.01, 'ok');
}
ck('头像位 / letter 位留白（无 gen690 徽章类记录）',
  !g1.recs.some(r => /^gen690\./.test(r.name || '') || /^gen69[01]\.(seal|mark|badge|rule)/.test(r.name || '')), 'ok');
// 隐藏层计数
const hid0 = g0.recs.filter(r => isHiddenRecord(r.field)).length;
const hid1 = g1.recs.filter(r => isHiddenRecord(r.field)).length;
ck('689 隐藏层 945', hid0 === 945, hid0);
ck('691 新增 40 条全部静态隐藏', added.every(r => isHiddenRecord(r.field)),
  `${added.filter(r => !isHiddenRecord(r.field)).length} 条未隐藏`);

// ④ 普通卡可见层零改动
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
  num(imageTriple(g1.recs.find(q => q.id === 1073742422).field).node, 502) === 0xFF491B1E, 'ok');

// ⑤ 7×7 地板补齐
const floors = g1.recs.filter(r => /^floor\.cell\./.test(r.name || ''));
const faces = g1.recs.filter(r => r.name === 'face' && floors.some(f => f.id === r.parentId));
ck('floor.cell 容器 49 条', floors.length === 49, floors.length);
ck('floor.cell 的 face 49 条', faces.length === 49, faces.length);
const bf = g1.recs.find(r => r.name === 'board.floors');
const bfSeq = (asIdList(findChildListTop(bf.field.sub).payload, true) || []).map(id => g1.recs.find(q => q.id === id)?.name);
ck('board.floors childList 49', bfSeq.length === 49, bfSeq.length);
ck('13 个新增地板格都在 childList 且带 face',
  SPEC.floorCells.names.every(nm => {
    const r = floors.find(q => q.name === nm);
    return r && bfSeq.includes(nm) && g1.recs.some(q => q.parentId === r.id && q.name === 'face');
  }), 'ok');
ck('path_map 追加 13 行',
  SPEC.floorCells.names.every(nm => s691.includes(`["${nm}"] = "root/stage/board.floors/${nm}",`)), 'ok');
ck('ensure_cells 循环改为动态（含 8 上界，6×6 关也能隐藏第7/8行列）',
  s691.includes('for rr=1,math.max(8,rows,cols) do for cc=1,math.max(8,rows,cols) do'), 'ok');
ck('cfg.cells rows/cols = 7', s691.includes('rows     = 7,') && s691.includes('cols     = 7,'), 'ok');

// ⑥ 门裁剪 / 去重
ck('case_006 doors 9 → 5', s691.includes(SPEC.doors.new) && !s691.includes(SPEC.doors.old), 'ok');
ck('其余 3 关 doors 数组未改', (() => {
  const pick = (s, id) => {
    const i = s.indexOf(`["id"] = "${id}"`);
    const j = s.indexOf('["doors"] = {', i);
    return s.slice(j, s.indexOf('}, ["objects"]', j));
  };
  return ['case_004', 'case_005', 'case_007'].every(id => pick(s689, id) === pick(s691, id));
})(), 'ok');
ck('门显隐恒去重（down/right 恒 skip）', s691.includes('local skip = { down = true, right = true }'), 'ok');

// ⑦ 地毯
ck('整块地毯模板已停用', s691.includes('if string.find(k,"|rug",1,true) and o and o.SetVisible then'), 'ok');
ck('逐格 els 仍启用（FURN_BAKED=false）', s691.includes('M.FURN_BAKED = false'), 'ok');

// ⑧ 选关页记忆
ck('M.new 恢复页态', s691.includes('self.select_page = M.SELECT_PAGE or 1'), 'ok');
ck('翻页回写模块变量', s691.includes('M.SELECT_PAGE = self.select_page'), 'ok');
ck('首页选关同步模块变量', s691.includes('self.select_page = 1; M.SELECT_PAGE = 1'), 'ok');
ck('689 每帧同步链未改', ['_lookup_gen', 'sync_art649_page', '_mark_layer_raise',
  'HIGHLIGHT_TINT = 4294956107', 'sync_block640', 'sync_art647'].every(k => s691.includes(k)), 'ok');

// ⑨ Lua 可逆 / 语法
function revert(s) {
  for (let i = SPEC.luaPatches.length - 1; i >= 0; i--) {
    const p = SPEC.luaPatches[i];
    if (s.split(p.new).length - 1 !== p.count) throw Error('反向锚点数不符：' + p.name);
    s = s.split(p.new).join(p.old);
  }
  return s;
}
ck('12 项 Lua 补丁反向逐字节还原 689', revert(s691) === s689, `${s689.length} → ${s691.length}`);
function luacOk(text, tag) {
  const tmp = path.join(os.tmpdir(), `gil691_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, text, 'utf8');
  try { execFileSync('luac', ['-p', tmp], { stdio: 'pipe' }); return true; }
  catch (e) { return String(e.stderr || e.message).slice(0, 200); }
  finally { fs.rmSync(tmp, { force: true }); }
}
const L689 = luacOk(s689, 'c689'), L691 = luacOk(s691, 'c691');
ck('luac -p 689', L689 === true, L689 === true ? 'ok' : L689);
ck('luac -p 691', L691 === true, L691 === true ? 'ok' : L691);
ck('691_内嵌Lua_691.lua 与存档一致',
  fs.readFileSync(path.join(DIR, '691_内嵌Lua_691.lua'), 'utf8') === s691, 'ok');

// ⑩ 行为级验证报告
const beh = JSON.parse(fs.readFileSync(path.join(DIR, '691_行为验证.json'), 'utf8'));
ck('Lua 行为级 57/57（裁门不改谜题）', beh.verdict === true && beh.pass === 57, `${beh.pass}/${beh.pass + beh.fail}`);

// ⑪ 静态文本零改动（原记录）
function texts(r) {
  const out = [];
  (function w(f) { if (f.wt === 2 && f.payload && f.len > 0 && f.isText) out.push(f.payload.toString('utf8')); for (const q of f.sub || []) w(q); })(r.field);
  return out.join('\u0001');
}
const textChanged = [...m0.keys()].filter(id => !EXPECTED_CHANGED.has(id)
  && texts(g0.recs.find(r => r.id === id)) !== texts(g1.recs.find(r => r.id === id)));
ck('原记录静态文本零改动', textChanged.length === 0, textChanged.join(','));

const pass = checks.filter(c => c.pass).length, fail = checks.length - pass;
const report = { version: 691, verdict: fail === 0, pass, fail, checks,
  base: { sha256: sha(F689), records: g0.recs.length, hidden: hid0 },
  output: { sha256: sha(F691), bytes: fs.statSync(F691).size, records: g1.recs.length, hidden: hid1 },
  timestamp: new Date().toISOString() };
fs.writeFileSync(path.join(DIR, '691_结构校验.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ verdict: report.verdict, pass, fail, failed: checks.filter(c => !c.pass) }, null, 2));
if (fail) process.exit(1);
