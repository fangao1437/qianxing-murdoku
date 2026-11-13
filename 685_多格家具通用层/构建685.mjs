// 685 · 多格家具通用构造法：把 X 标记从「格子内」提到「stage 末尾的独立标记层」
//   输入 ../684_结算收紧与教程配色/684_结算收紧与教程配色.gil（7633 条）
//   用法 FORCE=1 node 构建685.mjs   /   node 构建685.mjs --dry
//
// ★ 结构性不变式（与家具 kind / span / 尺寸完全无关）
//   stage 内：cell.r.c（furn_anchor 允许在 stage 内部 SetAsLastSibling 抬格）
//   stage 末尾：art685.mark.overlay + 8×8 组 X 标记
//   ⇒ 家具抬层永远只在 stage 内，标记层恒在其上；on_tick 每帧复位，未来新增家具零改动。
//
// ★ 内嵌 Lua 六处补丁（反向替换逐字节验证）；源码 lua/*.lua 同步，dist 不重打包。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '685_多格家具通用构造规格.json'), 'utf8'));
const INPUT = path.join(REPO, SPEC.base.file);
const OUTPUT = path.join(DIR, SPEC.output.file);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
if (sha(INPUT) !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, setPair, cloneField,
  ensureChildListTop, findChildListTop, asIdList, setChildList, textsOf } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const recTop = g.tree.find(f => f.field === 9);
const orderOf = () => { const m = new Map(); recTop.sub.forEach((f, i) => m.set(f, i)); return m; };
const scriptLeaf = findScriptLeaf(g);
const s0 = scriptLeaf.buf.toString('utf8');
if (Buffer.byteLength(s0) !== SPEC.base.scriptBytes) throw Error('内嵌 Lua 字节数与规格不符');
const scriptOwner = g.recs.find(r => encodeMsg([r.field]).includes(scriptLeaf.buf.subarray(0, 64)));
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));
let maxId = BigInt(g.maxId);
const added = [], changes = [], newLayers = [];
const modified = new Set();
const touch = r => { if (r?.name) modified.add(r.name); };

// ── 字段工具 ─────────────────────────────────────────────────────────────
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function cloneRec(proto, name, parentId, hidden) {
  if (byName.has(name)) throw Error('重名控件 ' + name);
  const f = cloneField(proto.field);
  const id = Number(++maxId);
  remap(f.sub, proto.id, id);
  const nameLeaf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nameLeaf) throw Error('克隆原型缺名字叶子：' + proto.name);
  nameLeaf.payload = Buffer.from(name); nameLeaf.len = nameLeaf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parentId) });
  const cl = findChildListTop(f.sub);
  if (cl) setChildList(cl, []);
  if (hidden !== undefined) setHiddenRecord(f, hidden);
  const rec = { id, name, parentId, field: f };
  g.recs.push(rec); byId.set(id, rec); byName.set(name, rec); added.push(rec);
  return rec;
}
function setGeomAll(r, dx, dyUp, w, h) {
  let n = 0;
  for (const st of stateBlocks(r.field.sub, [])) {
    const p = pairOf(st, 504), z = pairOf(st, 505);
    if (!p || !z) continue;
    setPair(p, dx, dyUp); setPair(z, w, h); n++;
  }
  if (n === 0) throw Error('几何状态块缺失 ' + r.name);
  touch(r);
  return n;
}
function insertFieldsAfter(anchorField, fields) {
  const i = recTop.sub.indexOf(anchorField);
  if (i < 0) throw Error('recTop 锚点丢失');
  recTop.sub.splice(i + 1, 0, ...fields);
}
function syncChildList(parent) {
  const ord = orderOf();
  const ids = g.recs.filter(r => r.parentId === parent.id)
    .sort((a, b) => (ord.get(a.field) ?? 1e9) - (ord.get(b.field) ?? 1e9)).map(r => r.id);
  setChildList(ensureChildListTop(parent), ids);
  touch(parent);
  return ids;
}

// ═══════════════════════════════════════════════════════════════════════
// A. 结构：stage 末尾新增标记层 + 8×8 组 X 标记
// ═══════════════════════════════════════════════════════════════════════
const stage = R('stage'), root = R('root'), rugs = R('board.rugs');
const cellX = g.recs.find(r => r.name === 'x' && byId.get(r.parentId)?.name === 'content'
  && isHiddenRecord(r.field)); // 取 cell 模板里默认隐藏的 x 容器
if (!cellX) throw Error('找不到 cell 模板里的 x 容器');
// 684 的内嵌脚本是 g.tree 上的独立文本块（不在任何记录字段里），scriptOwner 可能为 undefined。
const strokeProtos = (asIdList(findChildListTop(cellX.field.sub)?.payload ?? null, true) || [])
  .map(id => byId.get(id)).filter(Boolean);
if (strokeProtos.length !== 2) throw Error('x 模板子控件不是 2 个');
const stageGeom = (() => { const st = stateBlocks(stage.field.sub, [])[0];
  const p = pairOf(st, 504), z = pairOf(st, 505);
  return { size: [pairValue(z, 0), pairValue(z, 1)], pos: [pairValue(p, 0), pairValue(p, 1)] }; })();

const overlay = cloneRec(stage, 'art685.mark.overlay', stage.id);
setGeomAll(overlay, 0, 0, stageGeom.size[0], stageGeom.size[1]);
changes.push({ tag: 'mark-layer', name: overlay.name, id: overlay.id, parent: 'stage',
  pos: [0, 0], size: stageGeom.size });

const MAXN = SPEC.markLayer.maxBoard;
const markIds = [];
for (let r = 1; r <= MAXN; r++) for (let c = 1; c <= MAXN; c++) {
  const base = `art685.mark.${r}.${c}`;
  const m = cloneRec(cellX, base, overlay.id, true);
  markIds.push(m.id);
  const s0r = cloneRec(strokeProtos[0], `${base}.stroke.0`, m.id, true);
  const s1r = cloneRec(strokeProtos[1], `${base}.stroke.1`, m.id, true);
  setChildList(ensureChildListTop(m), [s0r.id, s1r.id]);
  newLayers.push({ name: base, id: m.id, parent: overlay.name,
    strokes: [s0r.name, s1r.name], hidden: isHiddenRecord(m.field),
    strokeHidden: [isHiddenRecord(s0r.field), isHiddenRecord(s1r.field)] });
}
setChildList(ensureChildListTop(overlay), markIds);
// 新增记录插到 board.rugs 之后 ⇒ stage childList 排序后标记层恰好在最后
insertFieldsAfter(rugs.field, added.map(r => r.field));
const stageKids = syncChildList(stage);
if (stageKids[stageKids.length - 1] !== overlay.id) throw Error('标记层没有排在 stage 末尾');
if (stageKids.length !== 4) throw Error('stage 子层数量异常：' + stageKids.length);
// root childList 保持 684 原样（标记层是 stage 的子，不是 root 的子）
const rootKids = asIdList(findChildListTop(root.field.sub)?.payload ?? null, true) || [];
if (rootKids.length !== 97) throw Error('root childList 被意外改动');
changes.push({ tag: 'stage-childList', before: ['board.bg', 'board.floors', 'board.rugs'],
  after: stageKids.map(id => byId.get(id)?.name) });

// ═══════════════════════════════════════════════════════════════════════
// B. 内嵌 Lua：六处补丁
// ═══════════════════════════════════════════════════════════════════════
const HELPERS = `-- ═══════════════════════════════════════════════════════════════════════
-- ★ 685「多格家具通用构造法」：三层不变式
--   stage 内 = 格子层（cell.*）；跨格家具实例挂在各格 content/furn，尺寸 = span × 格，
--   允许越出格线；furn_anchor 把锚点格 SetAsLastSibling 抬到 stage 内最上。
--   症状：被抬高的整格连同越界家具压到邻格之上，把邻格 content/x 一起盖掉（地毯/桌子都出现过）。
--   不变式：art685.mark.overlay 恒为 stage 的最后一个子控件，X 标记全部画在它里面，
--           抬格只能发生在 stage 内部 ⇒ 结构上不存在「家具盖住 X」的绘制顺序。
--   通用性：与 kind / span_r×span_c / 缩放 / 层数 / 将来新增多少种家具完全无关；
--           新增家具照常下发 furn_tpl / furn_span / furn_offset 即可，不必再改层序表。
-- ═══════════════════════════════════════════════════════════════════════
function Adapter:_mark_layer_raise()
  local m = self._mark_layer
  if m == nil then
    m = self:find("art685.mark.overlay")
    if m == nil then return end
    self._mark_layer = m
  end
  if m.SetAsLastSibling ~= nil then pcall(function() m:SetAsLastSibling() end) end
end
function Adapter:_mark_layer_guard()
  if self._mark_guard_done then return end
  if self:find("art685.mark.overlay") == nil then
    if self.warn_once then self:warn_once("mark:missing",
      "685 通用标记层缺失：多格家具会再次盖住 X。请把 art685.mark.overlay 挂在 stage 末尾。") end
    return
  end
  self._mark_guard_done = true
end
-- cell.<r>.<c> → art685.mark.<r>.<c>；位置/尺寸直接复用建格时记下的同一组数值
function Adapter:_mark_ctrl(id)
  local rc = tostring(id):match("^cell%.(.+)$")
  if rc == nil then return nil, nil end
  local m = self:find("art685.mark." .. rc)
  if m == nil then return nil, nil end
  local p = self._cell_pos and self._cell_pos[id]
  local x, y, sz = nil, nil, nil
  if p ~= nil then
    x, y, sz = p[1], p[2], p[3]
  else
    local r, c = rc:match("^(%d+)%.(%d+)$")
    if r ~= nil then
      local n = self._board_n or math.max(tonumber(r) or 1, tonumber(c) or 1)
      x, y = self:cell_offset(tonumber(r), tonumber(c), n)
      sz = select(1, self:cell_geometry(n))
    end
  end
  if x ~= nil and m.SetAnchoredPosition ~= nil then
    pcall(function() m:SetAnchoredPosition(x, y) end)
  end
  if sz ~= nil and m.SetSizeDelta ~= nil then
    pcall(function() m:SetSizeDelta(sz, sz) end)
  end
  return m, rc
end
-- 真机父容器 SetVisible 不保证级联到子控件（v308 教训）⇒ 容器 + 两枚笔画逐层开关
function Adapter:_mark_set_visible(rc, on)
  local base = "art685.mark." .. rc
  local names = { base, base .. ".stroke.0", base .. ".stroke.1" }
  for i = 1, #names do
    local c = self:find(names[i])
    if c ~= nil and c.SetVisible then pcall(function() c:SetVisible(on) end) end
  end
end
-- 关卡切换：收起超出当前棋盘 n 的标记，避免上一关的 X 残留
function Adapter:_mark_scope()
  local n = self._board_n or 0
  if n <= 0 or n == self._mark_scope_n then return end
  self._mark_scope_n = n
  for r = 1, ${MAXN} do
    for c = 1, ${MAXN} do
      if r > n or c > n then
        self:_mark_set_visible(string.format("%d.%d", r, c), false)
      end
    end
  end
end
`;

const P2_FROM = `        if ctrl.SetAnchoredPosition and x ~= nil then
          pcall(function() ctrl:SetAnchoredPosition(x, y) end)
          self:_sync_floor(id,ctrl)
        end`;
const P2_TO = P2_FROM + `
        -- ★ 685：记下本格中心，标记层复用同一组数值（与 n / 家具尺寸无关）
        self._cell_pos = self._cell_pos or {}
        self._cell_pos[id] = { x, y, cell_size }
        self._board_n = n`;

const P3_FROM = `      self:_furn_try_all()
    end
  end)
  return made`;
const P3_TO = `      self:_furn_try_all()
    end
  end)
  -- ★ 685：建格完成后立刻把标记层复位到 stage 末尾
  self:_mark_layer_raise()
  return made`;

const P4_FROM = `  elseif key == "x_mark" then
    local c = self:sub(id, "x")
    if c and c.SetVisible then c:SetVisible(value and true or false) end
  end`;
const P4_TO = `  elseif key == "x_mark" then
    local c = self:sub(id, "x")
    if c and c.SetVisible then c:SetVisible(value and true or false) end
    -- ★ 685：镜像到 stage 末尾的标记层（格内 x 保留作兜底，同位同色叠加不可见）
    local m, rc = self:_mark_ctrl(id)
    if rc ~= nil then self:_mark_set_visible(rc, value and true or false) end
    self:_mark_scope()
    self:_mark_layer_raise()
  end`;

const P5_FROM = `  elseif key == "furn_anchor" then
    if value == true and ctrl ~= nil and ctrl.SetAsLastSibling ~= nil then
      local ok = pcall(function() ctrl:SetAsLastSibling() end)
      if not ok then return false end
      self._furn_anchors = self._furn_anchors or {}
      self._furn_anchors[id] = true
    end
    return true`;
const P5_TO = `  elseif key == "furn_anchor" then
    -- ★ 685 通用构造法：抬格只发生在 stage 内部；之后立刻把标记层复位，
    --   无论将来新增什么 kind / span 的多格家具，X 都不会被盖住。
    self:_mark_layer_guard()
    if value == true and ctrl ~= nil and ctrl.SetAsLastSibling ~= nil then
      local ok = pcall(function() ctrl:SetAsLastSibling() end)
      if not ok then return false end
      self._furn_anchors = self._furn_anchors or {}
      self._furn_anchors[id] = true
    end
    self:_mark_layer_raise()
    return true`;

const P6_FROM = `function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)`;
const P6_TO = P6_FROM + `
  -- ★ 685：每帧复位标记层 ⇒ 未来任何新的抬格代码都自动被覆盖，无需再改层序
  self:_mark_layer_raise()`;

const PATCHES = [
  { tag: 'helpers',       from: 'function Adapter:enforce_layers(cell_id)', to: HELPERS + 'function Adapter:enforce_layers(cell_id)' },
  { tag: 'cells_ensure',  from: P2_FROM, to: P2_TO },
  { tag: 'cells_end',     from: P3_FROM, to: P3_TO },
  { tag: 'x_mark',        from: P4_FROM, to: P4_TO },
  { tag: 'furn_anchor',   from: P5_FROM, to: P5_TO },
  { tag: 'on_tick',       from: P6_FROM, to: P6_TO },
];
let s1 = s0;
for (const p of PATCHES) {
  const n = s1.split(p.from).length - 1;
  if (n !== 1) throw Error(`内嵌 Lua 锚点不唯一/缺失 [${p.tag}] 出现 ${n} 次`);
  s1 = s1.replace(p.from, p.to);
}
// 反向替换逐字节验证：证明除这六处外与 684 完全相同
let rev = s1;
for (const p of [...PATCHES].reverse()) {
  const n = rev.split(p.to).length - 1;
  if (n !== 1) throw Error(`反向锚点不唯一 [${p.tag}] 出现 ${n} 次`);
  rev = rev.replace(p.to, p.from);
}
if (rev !== s0) throw Error('内嵌 Lua 补丁不干净（反向替换未还原 684）');
scriptLeaf.field.payload = Buffer.from(s1, 'utf8');
scriptLeaf.field.len = Buffer.byteLength(s1);
if (scriptOwner) touch(scriptOwner);
changes.push({ tag: 'lua', bytes: [Buffer.byteLength(s0), Buffer.byteLength(s1)], patches: PATCHES.map(p => p.tag) });

// ═══════════════════════════════════════════════════════════════════════
// C. 源码同步（幂等；dist 不重打包）
// ═══════════════════════════════════════════════════════════════════════
const crlf = t => t.replace(/\n/g, '\r\n');
const sourceSync = [];
function patchSource(file, pairs, marker) {
  const p = path.join(REPO, file);
  let src = fs.readFileSync(p, 'utf8');
  if (src.includes(marker)) { sourceSync.push({ file, status: 'already-patched' }); return; }
  const eol = src.includes('\r\n') ? crlf : (t => t);
  for (const q of pairs) {
    const from = eol(q.from), to = eol(q.to);
    const n = src.split(from).length - 1;
    if (n !== 1) throw Error(`源码锚点不唯一/缺失 ${file} [${q.tag}] 出现 ${n} 次`);
    src = src.replace(from, to);
  }
  fs.writeFileSync(p, src, 'utf8');
  sourceSync.push({ file, status: 'patched', patches: pairs.map(q => q.tag) });
}
const SRC_P2_FROM = `        local x, y = self:cell_offset(r, c, n)
        if ctrl.SetAnchoredPosition and x ~= nil then
          pcall(function() ctrl:SetAnchoredPosition(x, y) end)
        end`;
const SRC_P2_TO = SRC_P2_FROM + `
        -- ★ 685：记下本格中心，标记层复用同一组数值（与 n / 家具尺寸无关）
        self._cell_pos = self._cell_pos or {}
        self._cell_pos[id] = { x, y, cell_size }
        self._board_n = n`;
patchSource('lua/engine_adapter_qianxing.lua', [
  { tag: 'helpers',      from: PATCHES[0].from, to: PATCHES[0].to },
  { tag: 'cells_ensure', from: SRC_P2_FROM, to: SRC_P2_TO },
  { tag: 'cells_end',    from: P3_FROM, to: P3_TO },
  { tag: 'x_mark',       from: P4_FROM, to: P4_TO },
  { tag: 'furn_anchor',  from: P5_FROM, to: P5_TO },
  { tag: 'on_tick',      from: P6_FROM, to: P6_TO },
], 'function Adapter:_mark_layer_raise()');
// layer_order 处补注不变式说明
{
  const p = path.join(REPO, 'lua/entry_client_script.lua');
  let src = fs.readFileSync(p, 'utf8');
  if (!src.includes('685 三层不变式')) {
    const anchor = '        "rug_layer", "furn",';
    if (src.split(anchor).length - 1 !== 1) throw Error('entry layer_order 锚点不唯一');
    const E = src.includes('\r\n') ? '\r\n' : '\n';
    const note = anchor + E
      + '        -- ★ 685 三层不变式：格内层序只管 cell/content 内部；跨格家具由 furn_anchor' + E
      + '        --   把整格抬到 stage 内最上，会盖住邻格 x。故 X 标记统一移到 stage 末尾的' + E
      + '        --   art685.mark.overlay（见 engine_adapter_qianxing.lua 的 _mark_layer_raise）。' + E
      + '        --   该方案对任意 kind / span / 尺寸的多格家具通用，新增家具无需再改本表。';
    src = src.replace(anchor, note);
    fs.writeFileSync(p, src, 'utf8');
    sourceSync.push({ file: 'lua/entry_client_script.lua', status: 'patched', patches: ['invariant-note'] });
  } else sourceSync.push({ file: 'lua/entry_client_script.lua', status: 'already-patched' });
}

// ═══════════════════════════════════════════════════════════════════════
// D. 闸门
// ═══════════════════════════════════════════════════════════════════════
// 旧记录：除脚本记录与 stage/root 的 childList 外，逐字节不变
const allowedOld = new Set([scriptOwner?.id, stage.id].filter(Boolean));
const changedOld = [], rogue = [];
for (const r of g.recs) {
  const was = beforeBytes.get(r.id);
  if (!was) continue;                       // 新增
  if (encodeMsg([r.field]).equals(was)) continue;
  changedOld.push(r.name || r.id);
  if (!allowedOld.has(r.id)) rogue.push(r.name || r.id);
}
if (rogue.length) throw Error('存在非预期旧记录改动：' + rogue.slice(0, 8).join(', '));
if (added.length !== SPEC.markLayer.newRecords) throw Error('新增记录数不符：' + added.length);
if (g.recs.length !== SPEC.base.records + added.length) throw Error('总记录数不符');
for (const r of added) {
  if (r.parentId != null && !byId.has(r.parentId)) throw Error('新增悬空父 ' + r.name);
  if (r.name.startsWith('art685.mark.') && r.name !== 'art685.mark.overlay'
      && !isHiddenRecord(r.field)) throw Error('标记层未隐藏 ' + r.name);
}
if (isHiddenRecord(overlay.field)) throw Error('标记层容器被误隐藏');
if (newLayers.length !== MAXN * MAXN) throw Error('标记组数不符');
if (newLayers.some(l => !l.hidden || l.strokeHidden.some(v => !v))) throw Error('标记默认隐藏不完整');
// 层序单调（所有父级 childList 与 recTop 同序）
const ord = orderOf();
for (const parent of [root, stage, overlay, ...added.filter(r => r.name.match(/^art685\.mark\.\d+\.\d+$/))]) {
  const ids = asIdList(findChildListTop(parent.field.sub)?.payload ?? null, true) || [];
  const seq = ids.map(id => ord.get(byId.get(id)?.field) ?? -1);
  if (seq.some((v, i) => i > 0 && v < seq[i - 1])) throw Error('childList 与 recTop 不同序：' + parent.name);
}

if (DRY) {
  console.log(JSON.stringify({ dry: true, records: [beforeBytes.size, g.recs.length],
    added: added.length, removed: 0, changedOld, rogue: rogue.length,
    marks: newLayers.length, scriptBytes: [Buffer.byteLength(s0), Buffer.byteLength(s1)],
    stageChildren: stageKids.map(id => byId.get(id)?.name), sourceSync }, null, 2));
  process.exit(0);
}

const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '685 generic multi-cell furniture mark layer (X never occluded)',
  expectRecs: g.recs.length,
  assert(t) {
    const ids = new Set(t.recs.map(r => r.id));
    if (t.recs.length !== g.recs.length) return '记录数不符';
    for (const r of t.recs) {
      const want = afterBytes.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录回读不符 #' + r.id + ' ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const leaf = findScriptLeaf(t);
    if (!leaf.buf.equals(Buffer.from(s1, 'utf8'))) return '内嵌 Lua 发生变化';
    return true;
  },
});
const audit = {
  version: 685, name: 'generic multi-cell furniture mark layer', date: new Date().toISOString().slice(0, 10),
  base: { file: SPEC.base.file, sha256: sha(INPUT), records: beforeBytes.size, scriptBytes: Buffer.byteLength(s0) },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: g.recs.length, scriptBytes: Buffer.byteLength(s1) },
  architecture: SPEC.architecture, markLayer: SPEC.markLayer,
  counts: { recordsBefore: beforeBytes.size, recordsAfter: g.recs.length,
    added: added.length, removed: 0, changedOldRecords: changedOld.length, rogue: rogue.length },
  changes, newLayers, sourceSync,
  guarantees: [
    '标记层是 stage 的最后一个子控件，家具抬层作用域严格限定在 stage 内',
    '8×8 组 X 标记 + 每组 2 枚笔画，共 193 条新增记录，全部默认隐藏',
    '内嵌 Lua 六处补丁，反向替换后与 684 逐字节相同',
    '既有 7633 条记录中除脚本记录与 stage/root childList 外逐字节不变（rogue=0）',
    '所有父级 childList 与 recTop 同序，新增悬空父 0',
    '源码 lua/engine_adapter_qianxing.lua 与 lua/entry_client_script.lua 已同步；dist 不重打包',
  ],
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '685_构建审计.json'), JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
fs.writeFileSync(path.join(DIR, '685_新增层清单.json'), JSON.stringify(newLayers, null, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: [audit.counts.recordsBefore, audit.counts.recordsAfter],
  added: added.length, changedOld, rogue: rogue.length,
  scriptBytes: [Buffer.byteLength(s0), Buffer.byteLength(s1)], sourceSync, status: 'APPLIED' }, null, 2));
