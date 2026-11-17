// 689 综合验证
//   A. Lua 行为级：用落盘内嵌 Lua 的真实模块段，加载 4 关、摆满预设答案、核对真假向量与提示格
//   B. 每帧同步链行为等价模拟：抽 688/689 真实同步层函数体交给 lua.exe 跑，
//      统计稳态帧调用数，并逐场景核对控件最终状态完全一致
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const GIL688 = path.join(ROOT, 'qianxing-murdoku/688_第4至7关接入/688_第4至7关接入.gil');
const GIL689 = path.join(DIR, '689_性能负载优化.gil');
const url = p => pathToFileURL(p).href;
const { readGil } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const LUA = {
  '688': findScriptLeaf(readGil(GIL688)).buf.toString('utf8'),
  '689': findScriptLeaf(readGil(GIL689)).buf.toString('utf8'),
};
const TMP = os.tmpdir();
const runLua = (tag, src) => {
  const f = `_wb689_${tag}.lua`;
  const p = path.join(TMP, f);
  fs.writeFileSync(p, src, 'utf8');
  return execFileSync('lua.exe', [f], { cwd: TMP, encoding: 'utf8', timeout: 120000 });
};
const slice = (s, a, b) => {
  const i = s.indexOf(a), j = s.indexOf(b, i + a.length);
  if (i < 0 || j < 0) throw Error('片段边界未找到：' + a + ' / ' + b);
  return s.slice(i, j);
};

// ── A. 行为级验证 ───────────────────────────────────────────────────────
const BEH_TAIL = `
local Core = __require("murdoku_core")
local names = {"levels.case_004","levels.case_005","levels.case_006","levels.case_007"}
local function out(kind, name, detail) print(kind .. "|" .. name .. "|" .. tostring(detail or "")) end
local CHECKS, PASS, FAIL = 0, 0, 0
local function ck(name, ok, detail)
  CHECKS = CHECKS + 1
  if ok then PASS = PASS + 1; out("PASS", name, detail) else FAIL = FAIL + 1; out("FAIL", name, detail) end
end
for _, nm in ipairs(names) do
  local okL, lv = pcall(__require, nm)
  ck(nm .. " 模块可加载", okL and type(lv) == "table", tostring(lv))
  if okL and type(lv) == "table" then
    local vok, errs = Core.validate_level(lv)
    ck(nm .. " validate_level", vok == true, type(errs) == "table" and table.concat(errs, ";") or tostring(errs))
    local okN, core = pcall(Core.new, lv, {})
    ck(nm .. " Core.new", okN and core ~= nil, tostring(core))
    if okN and core then
      local nClue, nSus = #(core.clues or {}), #(lv.suspects or {})
      ck(nm .. " 线索条数=人数", nClue == nSus, nClue .. "/" .. nSus)
      local placed = 0
      for id, p in pairs(lv.solution or {}) do
        core:select_suspect(id)
        local ok = core:hold_cell(p.r, p.c)
        if ok then placed = placed + 1 end
      end
      ck(nm .. " 预设答案摆满", placed == nSus and core:is_full(), placed .. "/" .. nSus)
      local res = core:clue_results()
      local vec, exp = {}, {}
      for i = 1, #res do vec[i] = res[i].satisfied and "1" or "0"; exp[i] = "1" end
      local fc = lv.meta and lv.meta.false_clue or 0
      if fc >= 1 and fc <= #exp then exp[fc] = "0" end
      ck(nm .. " 预设答案真假向量", table.concat(vec) == table.concat(exp),
         "got=" .. table.concat(vec) .. " exp=" .. table.concat(exp))
      local hbad = {}
      for i = 1, #res do
        local h = core:clue_hint(i)
        local pv = lv.hint_preview and lv.hint_preview[tostring(i)]
        local got, cnt = {}, 0
        if h then
          for _, cell in ipairs(h.cells or {}) do got[#got+1] = cell.r .. ":" .. cell.c end
          cnt = h.count or #got
        end
        if pv then
          if cnt ~= pv.count then hbad[#hbad+1] = i .. ":count" end
          if table.concat(got, ",") ~= table.concat(pv.cells or {}, ",") then hbad[#hbad+1] = i .. ":cells" end
        elseif cnt ~= 0 then hbad[#hbad+1] = i .. ":expect0" end
      end
      ck(nm .. " 浅蓝提示格逐卡一致", #hbad == 0, #hbad == 0 and #res .. "卡" or table.concat(hbad, ","))
    end
  end
end
print("SUMMARY|" .. CHECKS .. "|" .. PASS .. "|" .. FAIL)
`;
const beh = {};
for (const v of ['688', '689']) {
  const head = slice(LUA[v], 'local __M = {}', 'local FORCE_LEVEL = nil');
  const raw = runLua('beh' + v, head + '\n' + BEH_TAIL);
  const checks = [], lines = raw.trim().split('\n');
  let summary = null;
  for (const ln of lines) {
    const p = ln.split('|');
    if (p[0] === 'PASS' || p[0] === 'FAIL') checks.push({ ok: p[0] === 'PASS', name: p[1], detail: p.slice(2).join('|') });
    if (p[0] === 'SUMMARY') summary = { checks: +p[1], pass: +p[2], fail: +p[3] };
  }
  beh[v] = { summary, checks, raw: raw.trim() };
}

// ── B. 每帧同步链行为等价模拟 ───────────────────────────────────────────
const MOCK_HEAD = `
local C = { find=0, color=0, bind=0, visible=0, setsibling=0, pcall=0, colorwrites=0 }
local raw_pcall = pcall
pcall = function(...) C.pcall = C.pcall + 1; return raw_pcall(...) end
local ctrls = {}
local function mk(name)
  local c = { name=name, visible=true, active=true, clickAudioId=1, imageColor=0, textColor=0, showCursor=false }
  function c:SetVisible(v) self.visible = v and true or false end
  function c:SetActive(v) self.active = v and true or false end
  function c:SetAsLastSibling() C.setsibling = C.setsibling + 1 end
  function c:SetAnchoredPosition(x,y) self.ax, self.ay = x, y end
  function c:SetSizeDelta(w,h) self.sw, self.sh = w, h end
  function c:GetChildren() return {} end
  function c:AddCursorEventListener() end
  ctrls[name] = c
  return c
end
local adapter = { _lookup_gen = 1 }
function adapter:find(name)
  C.find = C.find + 1
  return ctrls[name] or mk(name)
end
local LIST7 = {"case_001","case_002","case_003","case_004","case_005","case_006","case_007"}
local ctrl = { screen="game", select_page=1, modal=nil, pending=nil,
  opts={ levels=function() return LIST7 end } }
function ctrl:can_settle() return C.settle_ready == true end
local Murdoku = {}
function Murdoku.current() return { adapter=adapter, controller=ctrl } end
local TUT_SETS = { l1="l1", l2="l2", home="home" }
local tutorial_inst = {}
local util = { bound={} }
function util:_bind(name, fn, resolved)
  C.bind = C.bind + 1
  if resolved == nil or self.bound[resolved] then return resolved ~= nil end
  self.bound[resolved] = true
  return true
end
function tutorial_instance(tag) return util end
`;
// help_visible 是同步区块之前的真实函数体
const HELP = v => slice(LUA[v], 'local function help_visible(c, v)', 'local function help_write(c, v)')
  .replace('local function help_visible(c, v)', 'local function help_visible(c, v)\n  C.visible = C.visible + 1');
const SYNC = v => slice(LUA[v], 'local BLOCK640 = {', 'function OnInit()');
const PERF_TAIL = `
local FRAMES = 600
local function frame()
  sync_art641()
  sync_art647()
  sync_art649_page()
  sync_block640()
end
-- 预热：让首帧的控件查找 / 绑定 / 染色完成
for i = 1, 10 do frame() end
local function resetC() for k in pairs(C) do C[k] = 0 end end
local function snap()
  local keys = {}
  for k in pairs(ctrls) do keys[#keys+1] = k end
  table.sort(keys)
  local t = {}
  for _, k in ipairs(keys) do
    local c = ctrls[k]
    t[#t+1] = k .. "=" .. tostring(c.visible) .. "/" .. tostring(c.active) .. "/" ..
      tostring(c.imageColor) .. "/" .. tostring(c.textColor) .. "/" .. tostring(c.clickAudioId) ..
      "/" .. tostring(c.ax) .. "/" .. tostring(c.ay)
  end
  return table.concat(t, ";")
end
local events = {
  { at=100, label="稳态600帧", apply=function() end },
  { at=200, label="切屏 game->select", apply=function() ctrl.screen="select" end },
  { at=300, label="结算解锁 ready=true", apply=function() C.settle_ready=true end },
  { at=400, label="控件树重建 gen=2", apply=function() adapter._lookup_gen=2 end },
  { at=500, label="翻到选关第2页", apply=function() ctrl.select_page=2 end },
  { at=560, label="教程 l1 打开", apply=function() tutorial_inst.l1={open=true} end },
}
resetC()
local marks = {}
for i = 1, FRAMES do
  for _, e in ipairs(events) do if e.at == i then e.apply() end end
  frame()
  for _, e in ipairs(events) do
    if e.at == i then marks[#marks+1] = e.label .. "|" .. snap() end
  end
end
print("COUNTS|" .. C.find .. "|" .. C.color .. "|" .. C.bind .. "|" .. C.visible ..
      "|" .. C.setsibling .. "|" .. C.pcall .. "|" .. C.colorwrites .. "|" .. FRAMES)
print("FINAL|" .. snap())
for _, m in ipairs(marks) do print("MARK|" .. m) end
`;
// write_art_color650 内部计数：在注入前给真实函数体套一层计数（不改动语义）
function instrumentColor(src) {
  return src.replace('local function write_art_color650(c, key, want)',
    'local function write_art_color650(c, key, want)\n  C.color = C.color + 1');
}
const perf = {};
for (const v of ['688', '689']) {
  const src = MOCK_HEAD + HELP(v) + '\n' + instrumentColor(SYNC(v)) + '\n' + PERF_TAIL;
  const raw = runLua('perf' + v, src);
  const counts = {}, marks = [];
  let final = null, lines = raw.trim().split('\n');
  for (const ln of lines) {
    const p = ln.split('|');
    if (p[0] === 'COUNTS') {
      ['find','color','bind','visible','setsibling','pcall','colorwrites','frames'].forEach((k, i) => counts[k] = +p[i+1]);
    } else if (p[0] === 'FINAL') final = p.slice(1).join('|');
    else if (p[0] === 'MARK') marks.push({ label: p[1], state: p.slice(2).join('|') });
  }
  perf[v] = { counts, final, marks, raw: raw.trim() };
}

// ── 汇总 ────────────────────────────────────────────────────────────────
const report = {
  timestamp: new Date().toISOString(),
  baseSha688: crypto.createHash('sha256').update(fs.readFileSync(GIL688)).digest('hex'),
  outSha689: crypto.createHash('sha256').update(fs.readFileSync(GIL689)).digest('hex'),
  behavioral: Object.fromEntries(['688','689'].map(v => [v, beh[v].summary])),
  behavioralIdentical: (() => {
    // Lua 打印的 table: 0x... 是运行时地址，两版必然不同，比较时规范化掉
    const norm = arr => JSON.stringify(arr.map(c => ({ ok: c.ok, name: c.name,
      detail: String(c.detail).replace(/table:\s*0x?[0-9A-Fa-f]+/g, 'table') })));
    return norm(beh['688'].checks) === norm(beh['689'].checks);
  })(),
  behavioralChecks: beh['689'].checks,
  perFrame: { '688': perf['688'].counts, '689': perf['689'].counts },
  perFrameReduction: {},
  finalStateIdentical: perf['688'].final === perf['689'].final,
  scenarioStates: perf['689'].marks.map((m, i) => ({
    label: m.label, identical: perf['688'].marks[i] && perf['688'].marks[i].state === m.state,
  })),
};
for (const k of ['find','color','bind','setsibling','pcall']) {
  const a = perf['688'].counts[k], b = perf['689'].counts[k];
  report.perFrameReduction[k] = { from: a, to: b, delta: a - b,
    pct: a > 0 ? Math.round((a - b) / a * 1000) / 10 : null };
}
report.verdict = beh['688'].summary.fail === 0 && beh['689'].summary.fail === 0 &&
  report.behavioralIdentical && report.finalStateIdentical &&
  report.scenarioStates.every(s => s.identical) &&
  Object.values(report.perFrameReduction).every(r => r.delta >= 0);
fs.writeFileSync(path.join(DIR, '689_验证报告.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({
  behavioral: report.behavioral,
  behavioralIdentical: report.behavioralIdentical,
  perFrame: report.perFrame,
  perFrameReduction: report.perFrameReduction,
  finalStateIdentical: report.finalStateIdentical,
  scenarioStates: report.scenarioStates,
  verdict: report.verdict,
}, null, 2));
if (!report.verdict) process.exit(1);
