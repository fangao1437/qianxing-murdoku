// 685 · 结构闸门：684 → 685 逐条核对
//   ① 记录集合 / 旧记录字节 / 文本 / 背景后代
//   ② 标记层不变式（stage 末尾、64 组、193 条新增、全部默认隐藏、几何/旋转/颜色）
//   ③ 内嵌 Lua 六处补丁（反向替换逐字节还原 684）
//   ④ childList 与 recTop 同序、悬空父 0
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList, textsOf } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const { isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const A = path.join(ROOT, 'qianxing-murdoku/684_结算收紧与教程配色/684_结算收紧与教程配色.gil');
const B = path.join(DIR, '685_多格家具通用层.gil');
const ga = readGil(A), gb = readGil(B);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const checks = [];
const ck = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail }); if (!ok) console.log('  FAIL', name, detail ?? ''); };

// ── 通用读法 ─────────────────────────────────────────────────────────────
const index = g => {
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
  const rt = g.tree.find(f => f.field === 9);
  const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
  return { byId, byName, rt, ord };
};
const ia = index(ga), ib = index(gb);
const bytes = g => new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const ba = bytes(ga), bb = bytes(gb);
const kidsOf = r => { const cl = findChildListTop(r.field.sub || []); return cl ? (asIdList(cl.payload, true) || []) : []; };
const geom = r => { const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), z = pairOf(st, 505);
  return { pos: p ? [pairValue(p, 0), pairValue(p, 1)] : null, size: z ? [pairValue(z, 0), pairValue(z, 1)] : null }; };
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const appearance = r => { const ip = ns(r.field, [505, 503, 84])[0]; return ip ? {
  color: '#' + (num(ip, 502) ?? 0).toString(16).padStart(8, '0'), img: num(ip, 503) || 100001 } : null; };
const rotOf = r => stateBlocks(r.field.sub, [])[0]?.sub?.find(q => q.field === 508)?.sub?.[0]?.f;
const textsOfRec = r => textsOf(r.field.sub, []).map(q => q.payload?.toString('utf8')).join('|');

// ── ① 记录集合 / 旧记录字节 / 文本 ───────────────────────────────────────
const addedIds = [...bb.keys()].filter(id => !ba.has(id));
const removedIds = [...ba.keys()].filter(id => !bb.has(id));
ck('记录数 7633→7826', ga.recs.length === 7633 && gb.recs.length === 7826, [ga.recs.length, gb.recs.length]);
ck('新增 193 / 删除 0', addedIds.length === 193 && removedIds.length === 0, [addedIds.length, removedIds.length]);
const changedOld = [...ba.keys()].filter(id => bb.has(id) && !ba.get(id).equals(bb.get(id)));
ck('旧记录改动仅 stage 一条', changedOld.length === 1 && ia.byId.get(changedOld[0])?.name === 'stage',
  changedOld.map(id => ia.byId.get(id)?.name));
ck('除 stage 外旧记录逐字节相同', changedOld.every(id => ia.byId.get(id)?.name === 'stage'));
ck('旧记录文本 0 改动', [...ba.keys()].every(id => bb.has(id)
  && textsOfRec(ia.byId.get(id)) === textsOfRec(ib.byId.get(id))));
// 背景后代：找名字含 police / v19 的静态组，核对其后代未变
const bg = ga.recs.find(r => /police.*v19|v19.*police/i.test(r.name || ''));
if (bg) {
  const desc = new Set([bg.id]);
  let grew = true;
  while (grew) { grew = false; for (const r of ga.recs) if (r.parentId != null && desc.has(r.parentId) && !desc.has(r.id)) { desc.add(r.id); grew = true; } }
  const dirty = [...desc].filter(id => bb.has(id) && ba.has(id) && !ba.get(id).equals(bb.get(id)));
  ck(`背景 ${bg.name} 的 ${desc.size} 个后代 0 改动`, dirty.length === 0, dirty.length);
} else ck('背景组存在（跳过后代检查）', true, 'not-found');

// ── ② 标记层不变式 ──────────────────────────────────────────────────────
const stageA = ia.byName.get('stage'), stageB = ib.byName.get('stage'), ov = ib.byName.get('art685.mark.overlay');
ck('标记层存在', !!ov);
ck('标记层父 = stage', ov?.parentId === stageB.id);
const skA = kidsOf(stageA), skB = kidsOf(stageB);
ck('stage 子层 3→4', skA.length === 3 && skB.length === 4, [skA.length, skB.length]);
ck('标记层是 stage 最后一个子控件', skB.at(-1) === ov.id, skB.map(id => ib.byId.get(id)?.name));
ck('前 3 个子层顺序不变', skA.every((id, i) => id === skB[i]));
const go = geom(ov), gs = geom(stageB);
ck('标记层 pos=(0,0)', Math.abs(go.pos[0]) < 0.01 && Math.abs(go.pos[1]) < 0.01, go.pos);
ck('标记层 size 与 stage 相同', Math.abs(go.size[0] - gs.size[0]) < 0.01 && Math.abs(go.size[1] - gs.size[1]) < 0.01, [go.size, gs.size]);
ck('标记层容器可见', !isHiddenRecord(ov.field));
// root childList 未被改动
const rootA = ia.byName.get('root'), rootB = ib.byName.get('root');
ck('root childList 97 条且顺序不变', kidsOf(rootA).length === 97 && kidsOf(rootA).join() === kidsOf(rootB).join());

const MAXN = 8;
let markOk = 0, hiddenOk = 0, strokeOk = 0, rotOk = 0, colorOk = 0, sizeOk = 0, parentOk = 0;
const protoX = ga.recs.find(r => r.name === 'x' && ia.byId.get(r.parentId)?.name === 'content' && isHiddenRecord(r.field));
const protoStrokes = kidsOf(protoX).map(id => ia.byId.get(id));
const wantColor = appearance(protoStrokes[0])?.color?.toLowerCase();
const wantSize = geom(protoStrokes[0])?.size;
for (let r = 1; r <= MAXN; r++) for (let col = 1; col <= MAXN; col++) {
  const base = `art685.mark.${r}.${col}`;
  const m = ib.byName.get(base);
  if (!m) continue;
  markOk++;
  if (isHiddenRecord(m.field)) hiddenOk++;
  if (m.parentId === ov.id) parentOk++;
  const names = kidsOf(m).map(id => ib.byId.get(id)?.name);
  const s0 = ib.byName.get(base + '.stroke.0'), s1 = ib.byName.get(base + '.stroke.1');
  if (names.length === 2 && names.includes(base + '.stroke.0') && names.includes(base + '.stroke.1')) strokeOk++;
  if (s0 && s1) {
    if (isHiddenRecord(s0.field) && isHiddenRecord(s1.field)) hiddenOk += 2;
    const rot = [rotOf(s0), rotOf(s1)];
    if (rot.includes(45) && rot.includes(-45)) rotOk++;
    if (appearance(s0)?.color?.toLowerCase() === wantColor && appearance(s1)?.color?.toLowerCase() === wantColor) colorOk++;
    for (const s of [s0, s1]) {
      const z = geom(s)?.size;
      if (z && Math.abs(z[0] - wantSize[0]) < 0.01 && Math.abs(z[1] - wantSize[1]) < 0.01) sizeOk++;
    }
  }
}
ck('64 组标记容器', markOk === 64, markOk);
ck('标记父级全部 = 标记层', parentOk === 64, parentOk);
ck('64 组各有 2 枚笔画', strokeOk === 64, strokeOk);
ck('192 条标记记录全部默认隐藏', hiddenOk === 192, hiddenOk);
ck('笔画旋转 +45/-45', rotOk === 64, rotOk);
ck('笔画颜色与原型一致 ' + wantColor, colorOk === 64, colorOk);
ck('128 枚笔画尺寸与原型一致', sizeOk === 128, sizeOk);
ck('新增记录全部无悬空父', addedIds.every(id => ib.byId.get(id).parentId == null || ib.byId.has(ib.byId.get(id).parentId)));

// ── ③ 内嵌 Lua ──────────────────────────────────────────────────────────
const sa = findScriptLeaf(ga).buf.toString('utf8'), sb = findScriptLeaf(gb).buf.toString('utf8');
ck('内嵌 Lua 636,689 → 641,321 B', Buffer.byteLength(sa) === 636689 && Buffer.byteLength(sb) === 641321,
  [Buffer.byteLength(sa), Buffer.byteLength(sb)]);
const markers = {
  raise: 'function Adapter:_mark_layer_raise()',
  guard: 'function Adapter:_mark_layer_guard()',
  ctrl: 'function Adapter:_mark_ctrl(id)',
  setvis: 'function Adapter:_mark_set_visible(rc, on)',
  scope: 'function Adapter:_mark_scope()',
  cellpos: 'self._cell_pos[id] = { x, y, cell_size }',
  xmark: 'local m, rc = self:_mark_ctrl(id)',
  anchorGuard: 'self:_mark_layer_guard()',
  tick: 'self:_mark_layer_raise()',
};
for (const [k, v] of Object.entries(markers)) ck('Lua 补丁 ' + k, sb.includes(v));
ck('Lua 每帧复位（on_tick）', /function Adapter:on_tick\(dt\)\n  self\.clock = self\.clock \+ \(dt or 0\)\n  -- ★ 685[\s\S]{0,120}self:_mark_layer_raise\(\)/.test(sb));
ck('Lua 保留了 680 的 rug_layer/furn', sb.includes('"rug_layer", "furn",'));
ck('Lua 无针对具体家具 kind/span 的层序特判', !/rug_layer.*furn.*SetAsLastSibling|furn_tpl.*SetSiblingIndex/.test(sb));
// 反向还原：把 685 里新增的六段文本按补丁定义删掉，应得回 684
let rev = sb;
const HELP = rev.slice(rev.indexOf('-- ═══════════════════════════════════════════════════════════════════════'),
  rev.indexOf('function Adapter:enforce_layers(cell_id)'));
if (HELP.length > 0) rev = rev.replace(HELP, '');
rev = rev
  .replace('\n        -- ★ 685：记下本格中心，标记层复用同一组数值（与 n / 家具尺寸无关）\n'
    + '        self._cell_pos = self._cell_pos or {}\n        self._cell_pos[id] = { x, y, cell_size }\n        self._board_n = n', '')
  .replace('\n  -- ★ 685：建格完成后立刻把标记层复位到 stage 末尾\n  self:_mark_layer_raise()', '')
  .replace('\n    -- ★ 685：镜像到 stage 末尾的标记层（格内 x 保留作兜底，同位同色叠加不可见）\n'
    + '    local m, rc = self:_mark_ctrl(id)\n    if rc ~= nil then self:_mark_set_visible(rc, value and true or false) end\n'
    + '    self:_mark_scope()\n    self:_mark_layer_raise()', '')
  .replace('    -- ★ 685 通用构造法：抬格只发生在 stage 内部；之后立刻把标记层复位，\n'
    + '    --   无论将来新增什么 kind / span 的多格家具，X 都不会被盖住。\n    self:_mark_layer_guard()\n', '')
  .replace('    self:_mark_layer_raise()\n    return true\n\n  elseif key == "object"', '    return true\n\n  elseif key == "object"')
  .replace('\n  -- ★ 685：每帧复位标记层 ⇒ 未来任何新的抬格代码都自动被覆盖，无需再改层序\n  self:_mark_layer_raise()', '');
ck('内嵌 Lua 反向还原 = 684 逐字节', rev === sa, rev === sa ? 'OK' : `差 ${Buffer.byteLength(rev) - Buffer.byteLength(sa)} B`);

// ── ④ childList 同序 ────────────────────────────────────────────────────
let orderOk = true, bad = '';
for (const r of gb.recs) {
  const ids = kidsOf(r);
  const seq = ids.map(id => ib.ord.get(ib.byId.get(id)?.field) ?? -1);
  if (seq.some((v, i) => i > 0 && v < seq[i - 1])) { orderOk = false; bad = r.name; break; }
}
ck('所有父级 childList 与 recTop 同序', orderOk, bad);

// ── 汇总 ────────────────────────────────────────────────────────────────
const failed = checks.filter(q => !q.ok);
const gen = JSON.parse(fs.readFileSync(path.join(DIR, '685_通用性验证.json'), 'utf8'));
ck('通用性验证 verdict=true', gen.verdict === true);
const result = {
  version: 685, verdict: failed.length === 0,
  base: { file: path.basename(A), sha256: sha(A), records: ga.recs.length, scriptBytes: Buffer.byteLength(sa) },
  output: { file: path.basename(B), sha256: sha(B), bytes: fs.statSync(B).size,
    records: gb.recs.length, scriptBytes: Buffer.byteLength(sb) },
  checks: checks.filter(q => !q.name.startsWith('Lua 补丁') && !q.name.startsWith('笔画')),
  luaPatchChecks: checks.filter(q => q.name.startsWith('Lua 补丁')).length,
  failed: failed.map(q => q.name),
  generality: { cases: gen.generality.enumeratedCases, uncovered: gen.generality.uncoveredCells,
    structuralOk: gen.structural.ok },
  summary: { total: checks.length, passed: checks.length - failed.length, failed: failed.length },
};
fs.writeFileSync(path.join(DIR, '685_结构校验.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify({ verdict: result.verdict, ...result.summary, failed: result.failed,
  records: [ga.recs.length, gb.recs.length], sha: result.output.sha256,
  generalityCases: result.generality.cases }, null, 2));
if (failed.length) process.exitCode = 1;
