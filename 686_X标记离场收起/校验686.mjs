// 686 · 结构闸门 + Lua 行为级模拟
//   ① 记录表 7826 条逐字节全同（只改内嵌 Lua）
//   ② 内嵌 Lua 五处补丁，反向替换逐字节还原 685
//   ③ 结构：stage 末尾标记层、193 条标记记录保留
//   ④ 行为模拟：用 lua.exe 真跑 685/686 的辅助函数，验证「离场逐层收起 + 屏幕门控」
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, findChildListTop, asIdList } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const A = path.join(REPO, '685_多格家具通用层/685_多格家具通用层.gil');
const B = path.join(DIR, '686_X标记离场收起.gil');
const ga = readGil(A), gb = readGil(B);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const checks = [];
const ck = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail }); if (!ok) console.log('  FAIL', name, detail ?? ''); };

// ── ① 记录表 ────────────────────────────────────────────────────────────
const ba = new Map(ga.recs.map(r => [r.id, encodeMsg([r.field])]));
const bb = new Map(gb.recs.map(r => [r.id, encodeMsg([r.field])]));
const added = [...bb.keys()].filter(id => !ba.has(id));
const removed = [...ba.keys()].filter(id => !bb.has(id));
const changed = [...ba.keys()].filter(id => bb.has(id) && !ba.get(id).equals(bb.get(id)));
ck('记录数 7826→7826', ga.recs.length === 7826 && gb.recs.length === 7826, [ga.recs.length, gb.recs.length]);
ck('0 新增 / 0 删除', added.length === 0 && removed.length === 0, [added.length, removed.length]);
ck('7826 条旧记录逐字节全同', changed.length === 0, changed.length);
const marksA = ga.recs.filter(r => (r.name || '').startsWith('art685.mark.'));
const marksB = gb.recs.filter(r => (r.name || '').startsWith('art685.mark.'));
ck('193 条标记记录完整保留', marksA.length === 193 && marksB.length === 193
  && marksA.every(r => bb.has(r.id) && ba.get(r.id).equals(bb.get(r.id))), [marksA.length, marksB.length]);
ck('192 条标记仍默认隐藏', gb.recs.filter(r => /^art685\.mark\.\d+\.\d+(\.stroke\.[01])?$/.test(r.name || '')
  && isHiddenRecord(r.field)).length === 192);
const byIdB = new Map(gb.recs.map(r => [r.id, r]));
const stageB = gb.recs.find(r => r.name === 'stage');
const sk = asIdList(findChildListTop(stageB.field.sub)?.payload ?? null, true) || [];
ck('stage 末尾仍是标记层', sk.length === 4 && byIdB.get(sk.at(-1))?.name === 'art685.mark.overlay',
  sk.map(id => byIdB.get(id)?.name));
// 所有父级 childList 与 recTop 同序
const rt = gb.tree.find(f => f.field === 9);
const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
let orderOk = true, bad = '';
for (const r of gb.recs) {
  const cl = findChildListTop(r.field.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  const seq = ids.map(id => ord.get(byIdB.get(id)?.field) ?? -1);
  if (seq.some((v, i) => i > 0 && v < seq[i - 1])) { orderOk = false; bad = r.name; break; }
}
ck('所有父级 childList 与 recTop 同序', orderOk, bad);

// ── ② 内嵌 Lua ──────────────────────────────────────────────────────────
const sa = findScriptLeaf(ga).buf.toString('utf8'), sb = findScriptLeaf(gb).buf.toString('utf8');
ck('内嵌 Lua 641,321 → 644,453 B', Buffer.byteLength(sa) === 641321 && Buffer.byteLength(sb) === 644453,
  [Buffer.byteLength(sa), Buffer.byteLength(sb)]);
const needles = {
  allCtrls: 'function Adapter:_mark_all_ctrls()',
  hideAll: 'function Adapter:_mark_hide_all()',
  cacheGuard: 'if #t >= 192 then self._mark_ctl_cache = t end',
  gate: 'if on == true and self._mark_screen_on == false then on = false end',
  visibleStage: 'if id == ((self.cfg.cells or {}).parent or "board") and value ~= true then',
  visibleCell: 'if value == true then\n          self._mark_screen_on = true',
  cellHide: 'self:_mark_set_visible(rc, false)',
  hideUnlisted: 'if not in_level then self:_mark_hide_all() else self._mark_screen_on = true end',
  keepScan: 'k:sub(1, 5) == "cell."',
};
for (const [k, v] of Object.entries(needles)) ck('Lua 补丁 ' + k, sb.includes(v));
ck('685 的五个补丁未被 686 覆盖', ['function Adapter:_mark_layer_raise()', 'function Adapter:_mark_ctrl(id)',
  'function Adapter:_mark_scope()', 'local m, rc = self:_mark_ctrl(id)', 'self:_mark_layer_raise()'].every(v => sb.includes(v)));
// 反向还原：把 686 新增片段删掉应逐字节回到 685
let rev = sb;
const HELP = rev.slice(rev.indexOf('-- ═══════════════════════════════════════════════════════════════════════\n-- ★ 686'),
  rev.indexOf('function Adapter:_mark_ctrl(id)'));
if (!HELP.length) throw Error('找不到 686 helpers 块');
rev = rev.replace(HELP, '');
rev = rev
  .replace('\n  -- ★ 686：关卡外一律不点亮（防止切屏瞬间 x_mark 抢先下发把 X 又打开）\n'
    + '  if on == true and self._mark_screen_on == false then on = false end', '')
  .replace('    -- ★ 686：stage 被隐藏时整层收起（父容器隐藏不级联子控件）\n'
    + '    if id == ((self.cfg.cells or {}).parent or "board") and value ~= true then\n'
    + '      self:_mark_hide_all()\n    end\n', '')
  .replace('\n    -- ★ 686：cell 的 visible 随 self.screen 变化（离开关卡 = false）。标记层不在\n'
    + '    --   layout_plan 节点表里，没人给它关灯 ⇒ 这里逐组收起并置屏幕门控。\n'
    + '    do\n'
    + '      local rc = tostring(id):match("^cell%.(.+)$")\n'
    + '      if rc ~= nil then\n'
    + '        if value == true then\n'
    + '          self._mark_screen_on = true\n'
    + '        else\n'
    + '          self._mark_screen_on = false\n'
    + '          self:_mark_set_visible(rc, false)\n'
    + '        end\n'
    + '      end\n'
    + '    end', '')
  .replace('  -- ★ 686：keep = layout_plan 的 seen 集合；没有任何 cell.* ⇒ 当前不在关卡内，\n'
    + '  --   逐层收起 192 个标记控件，兜住首帧 / _shown 重建等没有 cell visible 下发的路径。\n'
    + '  do\n'
    + '    local in_level = false\n'
    + '    for k in pairs(keep or {}) do\n'
    + '      if type(k) == "string" and k:sub(1, 5) == "cell." then in_level = true; break end\n'
    + '    end\n'
    + '    if not in_level then self:_mark_hide_all() else self._mark_screen_on = true end\n'
    + '  end\n', '');
ck('内嵌 Lua 反向还原 = 685 逐字节', rev === sa, rev === sa ? 'OK' : `差 ${Buffer.byteLength(rev) - Buffer.byteLength(sa)} B`);

// ── ③ 源码同步 ──────────────────────────────────────────────────────────
const srcA = fs.readFileSync(path.join(REPO, 'lua/engine_adapter_qianxing.lua'), 'utf8');
const srcB = fs.readFileSync(path.join(REPO, 'lua/entry_client_script.lua'), 'utf8');
ck('源码 adapter 含 686 四个补丁', ['function Adapter:_mark_hide_all()', 'function Adapter:_mark_all_ctrls()',
  'if on == true and self._mark_screen_on == false', 'if not in_level then self:_mark_hide_all()'].every(v => srcA.includes(v)));
ck('源码 entry 含 686 不变式注释', srcB.includes('686 离场收起'));

// ── ④ Lua 行为级模拟 ────────────────────────────────────────────────────
// 从两份内嵌 Lua 里抽出 _mark_set_visible / _mark_all_ctrls / _mark_hide_all 三个函数体，
// 用 mock 控件树真跑一遍，验证「离场收起」和「屏幕门控」。
const cut = (s, name) => {
  const start = s.indexOf('function Adapter:' + name + '(');
  if (start < 0) return null;
  const m = s.slice(start).match(/^function Adapter:[^\n]+\n[\s\S]*?\nend\n/);
  return m ? m[0] : null;
};
const simLua = (sa686, isNew) => {
  const parts = [];
  for (const n of ['_mark_all_ctrls', '_mark_hide_all', '_mark_set_visible']) {
    const f = cut(sa686, n);
    if (f) parts.push(f);
  }
  return `
local ctrls = {}
for r = 1, 8 do for c = 1, 8 do
  local base = "art685.mark." .. r .. "." .. c
  for _, nm in ipairs({base, base..".stroke.0", base..".stroke.1"}) do
    ctrls[nm] = { name=nm, visible=false,
      SetVisible=function(self,v) self.visible = (v == true) end }
  end
end end
local Adapter = {}
Adapter.__index = Adapter
function Adapter:find(n) return ctrls[n] end
${parts.join('\n')}
local a = setmetatable({}, Adapter)
local LIT = { "2.2", "2.4", "4.1", "5.5" }
local function shown()
  local n = 0
  for r = 1, 8 do for c = 1, 8 do
    local base = "art685.mark." .. r .. "." .. c
    for _, nm in ipairs({base, base..".stroke.0", base..".stroke.1"}) do
      if ctrls[nm].visible then n = n + 1 end
    end
  end end
  return n
end
-- 关卡内：点亮 4 组 X
for i = 1, #LIT do a:_mark_set_visible(LIT[i], true) end
local in_level_shown = shown()
-- 离开关卡：等价于 visible_stage / hide_unlisted 钩子调用 _mark_hide_all()
${isNew ? 'a:_mark_hide_all()' : '-- 685 无 _mark_hide_all，也无门控：父容器隐藏不级联'}
local after_leave = shown()
-- 切屏瞬间抢先下发 x_mark=true
${isNew ? 'a:_mark_set_visible("3.3", true)' : 'a:_mark_set_visible("3.3", true)'}
local after_race = shown()
print(string.format('%d %d %d', in_level_shown, after_leave, after_race))
`;
};
const LUA = 'C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe';
const f685 = path.join(DIR, '_模拟685.lua'), f686 = path.join(DIR, '_模拟686.lua');
fs.writeFileSync(f685, simLua(sa, false), 'utf8');
fs.writeFileSync(f686, simLua(sb, true), 'utf8');
const parse = t => t.trim().split(/\s+/).map(Number);
const [i685, l685, r685] = parse(execFileSync(LUA, [f685], { encoding: 'utf8' }));
const [i686, l686, r686] = parse(execFileSync(LUA, [f686], { encoding: 'utf8' }));
const sim = { v685: { inLevel: i685, afterLeave: l685, afterRace: r685 },
  v686: { inLevel: i686, afterLeave: l686, afterRace: r686 } };
fs.writeFileSync(path.join(DIR, '686_行为模拟.json'), JSON.stringify(sim, null, 2));
ck('685 模拟复现残留（关卡内 12 / 离场仍 12）', i685 === 12 && l685 === 12, sim.v685);
ck('686 关卡内 X 正常显示（12 个控件）', i686 === 12, i686);
ck('686 离场后 192 个控件全部关灯', l686 === 0, l686);
ck('686 屏幕门控挡住切屏抢先点亮', r686 === 0, r686);

// ── 汇总 ────────────────────────────────────────────────────────────────
const gen = JSON.parse(fs.readFileSync(path.join(DIR, '686_通用性验证.json'), 'utf8'));
ck('通用性验证 verdict=true', gen.verdict === true);
const failed = checks.filter(q => !q.ok);
const result = {
  version: 686, verdict: failed.length === 0,
  base: { file: path.basename(A), sha256: sha(A), records: ga.recs.length, scriptBytes: Buffer.byteLength(sa) },
  output: { file: path.basename(B), sha256: sha(B), bytes: fs.statSync(B).size,
    records: gb.recs.length, scriptBytes: Buffer.byteLength(sb) },
  checks, behaviorSimulation: sim,
  generality: { cases: gen.generality?.enumeratedCases ?? gen.enumeratedCases,
    uncovered: gen.generality?.uncoveredCells ?? gen.uncoveredCells },
  failed: failed.map(q => q.name),
  summary: { total: checks.length, passed: checks.length - failed.length, failed: failed.length },
};
fs.writeFileSync(path.join(DIR, '686_结构校验.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify({ verdict: result.verdict, ...result.summary, failed: result.failed,
  records: [ga.recs.length, gb.recs.length], sha: result.output.sha256,
  scriptBytes: [Buffer.byteLength(sa), Buffer.byteLength(sb)], behaviorSimulation: sim }, null, 2));
if (failed.length) process.exitCode = 1;
