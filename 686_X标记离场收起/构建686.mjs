// 686 · X 标记离场收起：父容器隐藏不级联 ⇒ 逐层关灯 + 屏幕门控
//   输入 ../685_多格家具通用层/685_多格家具通用层.gil（7826 条）
//   用法 FORCE=1 node 构建686.mjs   /   node 构建686.mjs --dry
//
// ★ 本轮只改内嵌 Lua（五处补丁），记录表 0 新增 / 0 删除 / 0 修改。
//   反向替换逐字节还原 685，证明没有夹带其它变化。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '686_离场收起规格.json'), 'utf8'));
const INPUT = path.join(REPO, SPEC.base.file);
const OUTPUT = path.join(DIR, SPEC.output.file);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
if (sha(INPUT) !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, findChildListTop, asIdList } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));

const g = readGil(INPUT);
const recTop = g.tree.find(f => f.field === 9);
const scriptLeaf = findScriptLeaf(g);
const s0 = scriptLeaf.buf.toString('utf8');
if (Buffer.byteLength(s0) !== SPEC.base.scriptBytes) throw Error('内嵌 Lua 字节数与规格不符');
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const byId = new Map(g.recs.map(r => [r.id, r]));

// ═══════════════════════════════════════════════════════════════════════
// A. 内嵌 Lua 五处补丁
// ═══════════════════════════════════════════════════════════════════════
const HELP686 = `-- ═══════════════════════════════════════════════════════════════════════
-- ★ 686「X 标记离场收起」：父容器隐藏不级联，必须逐层关灯
--   685 误判：以为 stage 在 home/select 被整体隐藏时，挂在它下面的标记层会跟着消失。
--   真机反证（v308 已记录）：父容器 SetVisible 不保证级联到子控件 ⇒ 关卡内点亮的
--   X 标记会残留在新界面上。且标记层控件不在 layout_plan 的 nodes 表里，Controller 的
--   _shown 差异下发 / hide_unlisted 都不会给它们下发 visible=false ⇒ 永远没人关灯。
--   ⇒ 按项目既有范式（visible 分支里显式切 board.floors / board.rugs）逐层收起。
-- ═══════════════════════════════════════════════════════════════════════
function Adapter:_mark_all_ctrls()
  if self._mark_ctl_cache ~= nil then return self._mark_ctl_cache end
  local t = {}
  for r = 1, 8 do
    for c = 1, 8 do
      local base = "art685.mark." .. r .. "." .. c
      local names = { base, base .. ".stroke.0", base .. ".stroke.1" }
      for i = 1, #names do
        local q = self:find(names[i])
        if q ~= nil then t[#t + 1] = q end
      end
    end
  end
  if #t >= 192 then self._mark_ctl_cache = t end   -- 控件树未就绪时不缓存，下次重建
  return t
end
function Adapter:_mark_hide_all()
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    local q = t[i]
    if q.SetVisible ~= nil then pcall(function() q:SetVisible(false) end) end
  end
  self._mark_screen_on = false
end
`;

const P1_FROM = 'function Adapter:_mark_ctrl(id)';
const P1_TO = HELP686 + P1_FROM;

const P2_FROM = `function Adapter:_mark_set_visible(rc, on)
  local base = "art685.mark." .. rc`;
const P2_TO = `function Adapter:_mark_set_visible(rc, on)
  -- ★ 686：关卡外一律不点亮（防止切屏瞬间 x_mark 抢先下发把 X 又打开）
  if on == true and self._mark_screen_on == false then on = false end
  local base = "art685.mark." .. rc`;

const P3_FROM = `  elseif key == "visible" then
    if id == ((self.cfg.cells or {}).parent or "board") then`;
const P3_TO = `  elseif key == "visible" then
    -- ★ 686：stage 被隐藏时整层收起（父容器隐藏不级联子控件）
    if id == ((self.cfg.cells or {}).parent or "board") and value ~= true then
      self:_mark_hide_all()
    end
    if id == ((self.cfg.cells or {}).parent or "board") then`;

const P4_FROM = `    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl,value==true) end`;
const P4_TO = P4_FROM + `
    -- ★ 686：cell 的 visible 随 self.screen 变化（离开关卡 = false）。标记层不在
    --   layout_plan 节点表里，没人给它关灯 ⇒ 这里逐组收起并置屏幕门控。
    do
      local rc = tostring(id):match("^cell%.(.+)$")
      if rc ~= nil then
        if value == true then
          self._mark_screen_on = true
        else
          self._mark_screen_on = false
          self:_mark_set_visible(rc, false)
        end
      end
    end`;

const P5_FROM = `function Adapter:hide_unlisted(keep)
  local hidden = 0`;
const P5_TO = `function Adapter:hide_unlisted(keep)
  -- ★ 686：keep = layout_plan 的 seen 集合；没有任何 cell.* ⇒ 当前不在关卡内，
  --   逐层收起 192 个标记控件，兜住首帧 / _shown 重建等没有 cell visible 下发的路径。
  do
    local in_level = false
    for k in pairs(keep or {}) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then in_level = true; break end
    end
    if not in_level then self:_mark_hide_all() else self._mark_screen_on = true end
  end
  local hidden = 0`;

const PATCHES = [
  { tag: 'helpers',         from: P1_FROM, to: P1_TO },
  { tag: 'screen_gate',     from: P2_FROM, to: P2_TO },
  { tag: 'visible_stage',   from: P3_FROM, to: P3_TO },
  { tag: 'visible_cell',    from: P4_FROM, to: P4_TO },
  { tag: 'hide_unlisted',   from: P5_FROM, to: P5_TO },
];
let s1 = s0;
for (const p of PATCHES) {
  const n = s1.split(p.from).length - 1;
  if (n !== 1) throw Error(`内嵌 Lua 锚点不唯一/缺失 [${p.tag}] 出现 ${n} 次`);
  s1 = s1.replace(p.from, p.to);
}
let rev = s1;
for (const p of [...PATCHES].reverse()) {
  const n = rev.split(p.to).length - 1;
  if (n !== 1) throw Error(`反向锚点不唯一 [${p.tag}] 出现 ${n} 次`);
  rev = rev.replace(p.to, p.from);
}
if (rev !== s0) throw Error('内嵌 Lua 补丁不干净（反向替换未还原 685）');
scriptLeaf.field.payload = Buffer.from(s1, 'utf8');
scriptLeaf.field.len = Buffer.byteLength(s1);

// ═══════════════════════════════════════════════════════════════════════
// B. 源码同步（幂等；CRLF；源码是较旧版本，visible 分支锚点不同）
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
// 源码 visible 分支：在 `local vis = ... / ctrl:SetVisible(vis)` 之后统一注入
const SRC_VIS_FROM = `    local vis = value and true or false
    if ctrl.SetVisible then pcall(function() ctrl:SetVisible(vis) end) end`;
const SRC_VIS_TO = SRC_VIS_FROM + `
    -- ★ 686：离开关卡时逐层收起 X 标记层（父容器隐藏不级联子控件）
    do
      local rc686 = tostring(id):match("^cell%.(.+)$")
      if rc686 ~= nil then
        if vis then self._mark_screen_on = true
        else self._mark_screen_on = false; self:_mark_set_visible(rc686, false) end
      end
      if id == ((self.cfg.cells or {}).parent or "board") and not vis then
        self:_mark_hide_all()
      end
    end`;
patchSource('lua/engine_adapter_qianxing.lua', [
  { tag: 'helpers',       from: P1_FROM, to: P1_TO },
  { tag: 'screen_gate',   from: P2_FROM, to: P2_TO },
  { tag: 'visible_cell',  from: SRC_VIS_FROM, to: SRC_VIS_TO },
  { tag: 'hide_unlisted', from: P5_FROM, to: P5_TO },
], 'function Adapter:_mark_hide_all()');
{
  const p = path.join(REPO, 'lua/entry_client_script.lua');
  let src = fs.readFileSync(p, 'utf8');
  if (!src.includes('686 离场收起')) {
    const anchor = '        --   该方案对任意 kind / span / 尺寸的多格家具通用，新增家具无需再改本表。';
    if (src.split(anchor).length - 1 !== 1) throw Error('entry 不变式注释锚点不唯一');
    const E = src.includes('\r\n') ? '\r\n' : '\n';
    src = src.replace(anchor, anchor + E
      + '        -- ★ 686 离场收起：父容器隐藏不级联 ⇒ stage/cell 被隐藏时必须逐层 SetVisible(false)' + E
      + '        --   8×8 组标记；并用 _mark_screen_on 门控挡住切屏瞬间的 x_mark 抢先点亮。');
    fs.writeFileSync(p, src, 'utf8');
    sourceSync.push({ file: 'lua/entry_client_script.lua', status: 'patched', patches: ['686-note'] });
  } else sourceSync.push({ file: 'lua/entry_client_script.lua', status: 'already-patched' });
}

// ═══════════════════════════════════════════════════════════════════════
// C. 闸门：记录表零改动
// ═══════════════════════════════════════════════════════════════════════
const changedOld = [];
for (const r of g.recs) {
  const was = beforeBytes.get(r.id);
  if (was && !encodeMsg([r.field]).equals(was)) changedOld.push(r.name || r.id);
}
if (changedOld.length) throw Error('记录表被意外改动：' + changedOld.slice(0, 8).join(', '));
if (g.recs.length !== SPEC.base.records) throw Error('记录数不符');
const stage = g.recs.find(r => r.name === 'stage');
const stageKids = asIdList(findChildListTop(stage.field.sub)?.payload ?? null, true) || [];
if (stageKids.length !== 4) throw Error('stage 子层不是 4：' + stageKids.length);
if (byId.get(stageKids.at(-1))?.name !== 'art685.mark.overlay') throw Error('标记层不在 stage 末尾');

if (DRY) {
  console.log(JSON.stringify({ dry: true, records: [beforeBytes.size, g.recs.length],
    added: 0, removed: 0, changedOld,
    scriptBytes: [Buffer.byteLength(s0), Buffer.byteLength(s1)],
    patches: PATCHES.map(p => p.tag), sourceSync }, null, 2));
  process.exit(0);
}

const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '686 X marks hide on leaving level (per-layer SetVisible + screen gate)',
  expectRecs: g.recs.length,
  assert(t) {
    if (t.recs.length !== g.recs.length) return '记录数不符';
    for (const r of t.recs) {
      const want = afterBytes.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录回读不符 #' + r.id + ' ' + r.name;
    }
    const leaf = findScriptLeaf(t);
    if (!leaf.buf.equals(Buffer.from(s1, 'utf8'))) return '内嵌 Lua 发生变化';
    return true;
  },
});
const audit = {
  version: 686, name: 'X marks hide on leaving level', date: new Date().toISOString().slice(0, 10),
  base: { file: SPEC.base.file, sha256: sha(INPUT), records: beforeBytes.size, scriptBytes: Buffer.byteLength(s0) },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: g.recs.length, scriptBytes: Buffer.byteLength(s1) },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: g.recs.length,
    added: 0, removed: 0, changedOldRecords: changedOld.length },
  patches: PATCHES.map(p => p.tag), sourceSync,
  guarantees: [
    '内嵌 Lua 五处补丁，反向替换后与 685 逐字节相同',
    '记录表 7826 条 0 新增 / 0 删除 / 0 修改',
    'stage 末尾标记层与 193 条标记记录逐字节保留',
    '源码 lua/engine_adapter_qianxing.lua / lua/entry_client_script.lua 同步；dist 不重打包',
  ],
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '686_构建审计.json'), JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: [audit.counts.recordsBefore, audit.counts.recordsAfter],
  changedOld, scriptBytes: [Buffer.byteLength(s0), Buffer.byteLength(s1)],
  patches: audit.patches, sourceSync, status: 'APPLIED' }, null, 2));
