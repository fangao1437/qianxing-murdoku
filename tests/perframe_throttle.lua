--[[----------------------------------------------------------------------------
  tests/perframe_throttle.lua —— 离线验「适配器方法到底在不在」+「每帧节流在哪一档」

  ⚠️ 本文件由「代码体检 · 第一遍」的**深层结构审计**新增，是两份实证之一
     （另一份是 `tools/audit/check_nesting.mjs` 的静态扫描）。
     **请勿删除**：它钉住的正是"定义丢了也零报错"这一类静默失效。

  理由（本轮实测抓到的两个真凶，两条都能被本文件复现）：
    ① `lua/engine_adapter_qianxing.lua` 的 `if self.cfg.btn_art == true and print then`
       （L2371）**没有被关闭** ⇒ 把两个本该在顶层的方法定义吞进了 `apply_tray_layout`
       的函数体里：`Adapter:apply_ruler_layout`（L2378）与 `Adapter:diagnose_overlap`（L2461）。
       ⇒ 它们在**加载时不存在**，而所有调用点都写着 `if adapter.xxx ~= nil then`
         （防呆守卫）⇒ **静默跳过、零报错** ⇒ 「行标/列标对齐」这个功能从来没跑过。
    ② `lua/main.lua` 的 `if (current.frames or 0) % 300 == 0 then`（L1461）**没有被关闭**，
       把"按屏同步运行时控件可见性"（注释写明**每帧**）与"每 30 帧点亮 25 个 face"
       整段套了进去 ⇒ 实际节流是**每 300 帧**。

  判据（全部只看"引擎侧真的被调用了多少次"，不依赖任何内部变量）：
    [0] 调用点用 `~= nil` 守卫过的适配器方法**必须真的存在** —— 缺一个 = 那个功能静默失效。
    [A] 关卡内稳态 60 帧：`cell.*` / `selbar` 被按屏同步的次数（每帧 ⇒ 60）。
    [B] 帧号 == 300 那一帧确实会跑一次（证明代码在，只是节流位错）。
    [C] `apply_ruler_layout`（每次 render 都被调）在稳态里重复打印的次数（内容没变 ⇒ ≤1）。

  跑法：lua tests/perframe_throttle.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/perframe_throttle.lua"
local root = here:gsub("tests[/\\]perframe_throttle%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print          -- 测试自己的输出（被测试代码的 print 会被劫持）

local pass, fail = 0, 0
local function ok(cond, label, detail)
  if cond then
    pass = pass + 1
    out("  [PASS] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  else
    fail = fail + 1
    out("  [FAIL] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  end
end

-- ── 劫持日志 ────────────────────────────────────────────────────────────────
local logs = {}
local function collect(level, ...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
end
_G.print = function(...) collect("info", ...) end
_G.printerr = function(...) collect("error", ...) end

-- ── 假控件树 ────────────────────────────────────────────────────────────────
local C = { vis = {} }
local function bump(name)
  C.vis[name] = (C.vis[name] or 0) + 1
end
local function attach(parent, c)
  if parent == nil then return nil end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end
local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true, __kids = {} }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v) c.visible = v; bump(name) end
  c.SetActive = function(_, v) c.active = v end
  c.SetSizeDelta = function(_, w, h) c.w, c.h = w, h end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
  c.SetAnchoredPosition = function(_, x, y) c.ax, c.ay = x, y end
  c.GetAnchoredPosition = function() return c.ax or 0, c.ay or 0 end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() end
  c.SetLocalScale = function() end
  c.AddCursorEventListener = function() end
  c.SetImage = function() return false end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  return c
end
local function make_text(name)
  local c = make_ctrl(name)
  c.kind = "text"
  local store = { text = name }
  return setmetatable(c, {
    __index = function(_, k) if k == "text" then return store.text end return nil end,
    __newindex = function(t, k, v) if k == "text" then store.text = v else rawset(t, k, v) end end,
  })
end

local tree
do
  local rt = make_ctrl("root")
  attach(rt, make_ctrl("home"))
  attach(rt, make_ctrl("select"))
  local st = make_ctrl("stage")
  for r = 1, 5 do
    for c = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. c)
      cell.kind = "button"
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
  local board = attach(rt, make_ctrl("board"))
  local ruler = attach(board, make_ctrl("ruler"))
  for i = 1, 5 do
    attach(ruler, make_text("ruler.c." .. i))
    attach(ruler, make_text("ruler.r." .. i))
  end
  attach(rt, make_ctrl("topbar"))
  attach(rt, make_ctrl("right"))
  local cl = attach(rt, make_ctrl("clues"))
  attach(cl, make_ctrl("clues.bg"))
  tree = { rt }
end

_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"
    c.prefabIndex = prefab
    attach(parent, c)
    return c
  end,
  DestroyClientUIControl = function() end,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end,
  PrintClientUITree = function() end,
  ServerSignal = function()
    local s = {}
    s.AddInt = function() end; s.AddFloat = function() end
    s.AddString = function() end; s.AddBool = function() end; s.SendSignal = function() end
    return s
  end,
  PlayAudio2D = function() end,
  GetText = function() return "" end,
}
_G.script = {
  EnableUpdate = function() end,
  RegisterServerSignalHandler = function() end,
  RegisterCustomVariableChangedHandler = function() end,
  Invoke = function() end,
  GetParam = function() return nil end,
}
_G.Enum = nil

-- ── 加载产物 ────────────────────────────────────────────────────────────────
local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then
  out("  加载失败：" .. tostring(lerr) .. "　→ 先跑 `lua tools/bundle_client_script.lua`")
  os.exit(1)
end
assert(pcall(chunk))
local ok1, err1 = pcall(OnInit)
local ok2, err2 = pcall(OnStart)
if not (ok1 and ok2) then
  out("  OnInit/OnStart 失败：" .. tostring(err1) .. " / " .. tostring(err2)); os.exit(1)
end

local dbg = _G.__murdoku_debug
local cur = dbg.Murdoku.current()
local ctrl, adapter = cur.controller, cur.adapter

-- ── 0. 适配器方法"到底在不在"──────────────────────────────────────────────
out("\n== 0. 适配器方法存在性（守卫型调用点）==")
do
  local names = {
    "_cells_beacon_button", "_cells_signal", "count_names", "dump_names", "near_names",
    "invalidate_lookups", "ensure_raycast", "rearm_raycast", "input_profile", "hide_unlisted",
    "apply_ruler_layout", "ensure_widgets", "ensure_cells", "apply_tray_layout",
    "diagnose_overlap", "diagnose_cell", "diagnose_grid", "diagnose_template",
    "seal_containers", "seal_container", "enable_cursor", "enable_raycast", "report_missing",
    "find", "sub", "set_property", "create_control", "destroy_control", "play_effect",
    "on_tick", "signal_emit", "set_image_deep", "cell_geometry", "enforce_hidden_subtrees",
    "bind_input", "bind_keys", "open_click_passthrough",
  }
  local miss = {}
  for i = 1, #names do
    if type(adapter[names[i]]) ~= "function" then miss[#miss + 1] = names[i] end
  end
  ok(#miss == 0,
    "★ 调用点用 `~= nil` 守卫过的适配器方法**全都存在**（缺一个 = 那个功能静默失效）",
    #miss == 0 and ("全部存在（" .. #names .. " 个）")
      or ("缺失 " .. #miss .. " 个：" .. table.concat(miss, " / ")))
end

-- ── 挂钩子 ────────────────────────────────────────────────────────────────
local C2 = { render = 0, ruler = 0, ruler_ret = nil, err = nil }
do
  local orr = ctrl.render
  ctrl.render = function(self, ...) C2.render = C2.render + 1 return orr(self, ...) end
  if type(adapter.apply_ruler_layout) == "function" then
    local oar = adapter.apply_ruler_layout
    adapter.apply_ruler_layout = function(self, ...)
      C2.ruler = C2.ruler + 1
      local n = oar(self, ...)
      C2.ruler_ret = n
      return n
    end
  end
end
local function step(n)
  for _ = 1, n do
    local o, e = pcall(OnUpdate, 1 / 60)
    if not o then C2.err = tostring(e) end
  end
end
local function frames_now() return cur.frames or 0 end
local function vis_of(name) return C.vis[name] or 0 end
local function count_log(pat)
  local n = 0
  for i = 1, #logs do if logs[i].text:find(pat, 1, true) then n = n + 1 end end
  return n
end

-- 进关卡内（screen = nil ⇒ main.lua 里 scr_now = "level"）
ctrl.screen = nil
ctrl.dirty = true
step(5)
ok(C2.err == nil, "（前置）进关卡这几帧 OnUpdate 不抛错", tostring(C2.err))

----------------------------------------------------------------------------
out("\n== A. 关卡内稳态 60 帧：节流位到底在哪一档 ==")
-- ⚠️⚠️ 【口径无效，别拿 A/B 两节当证据】2026-10-05 实测：
--   本文件的假树**与真机不同构** —— `OnInit/OnStart` 期间 `stage`（连同 25 个 `cell.*`）
--   被 `ensure_cells` / `_park_control` 改名或挪走，`adapter:find("cell.1.1")` 恒为 nil
--   ⇒ `setv()` 拿不到控件 ⇒ 这里的计数**必然是 0，与 `%300` 门无关** ✗。
--   证据：下面 §B 的 `[诊断] find 逐个` 那两行。
--   ⇒ 「`%30` 被 `%300` 套住」这条结论的**有效证据是静态块深度**：
--        node tools/audit/check_nesting.mjs --depths=lua/main.lua:1480-1590
--        （`%30` 那行 depth=2 ⇒ 在外层 `%300` 的 `if` 里面）
--   A/B 两节先留着当**诊断输出**；要让它们恢复有效，得先把假树补成同构（find 能命 central cell.*）。
local f0 = frames_now()
out(string.format("  起始帧号 = %d（下一次 frames%%300==0 在第 %d 帧）",
  f0, (math.floor(f0 / 300) + 1) * 300))
local base_cell = vis_of("cell.1.1")
local base_bar  = vis_of("selbar")
step(60)
local d_cell = vis_of("cell.1.1") - base_cell
local d_bar  = vis_of("selbar") - base_bar

ok(d_cell >= 55,
  "★ 关卡内 60 帧里 `cell.*` 被按屏同步（注释：**每帧**压住）",
  "实测 cell.1.1 SetVisible " .. d_cell .. " 次（每帧应为 60；每 30 帧为 2；每 300 帧为 0）")
ok(d_bar >= 55,
  "★ 关卡内 60 帧里 `selbar` 被压住（注释 L1522-1525：**必须每帧压住才稳**）",
  "实测 selbar SetVisible " .. d_bar .. " 次")

----------------------------------------------------------------------------
out("\n== B. 帧号 == 300 那一帧：这两段**确实存在**，只是节流位错 ==")
local need = 300 - frames_now()
if need > 0 then step(need) end
ok(frames_now() == 300, "（先把帧号推到刚好 300）", "frames=" .. tostring(frames_now()))
-- ⚠️ 计数必须在"这一帧"之前取：`current.frames` 是在 on_update **末尾**自增的，
--    所以帧号 == 300 的那一次 OnUpdate，判据 `frames % 300 == 0` 命中的正是它。
local before = vis_of("cell.1.1")
local bar_before = vis_of("selbar")
out(string.format("  [诊断] 调 OnUpdate 前：frames=%s screen=%s 同一会话=%s",
  tostring(cur.frames), tostring(cur.controller and cur.controller.screen),
  tostring(cur == dbg.Murdoku.current())))
out(string.format("  [诊断] setv 能不能拿到控件：controls['cell.1.1']=%s  find('cell.1.1')=%s  controls['selbar']=%s",
  tostring(adapter.controls and adapter.controls["cell.1.1"] ~= nil),
  tostring(adapter:find("cell.1.1") ~= nil),
  tostring(adapter.controls and adapter.controls["selbar"] ~= nil)))
do
  local probe_names = { "root", "stage", "board", "ruler", "home", "clues", "cell.1.1", "cell.1.2", "selbar" }
  local parts = {}
  for i = 1, #probe_names do
    parts[#parts + 1] = probe_names[i] .. "=" .. tostring(adapter:find(probe_names[i]) ~= nil)
  end
  out("  [诊断] find 逐个： " .. table.concat(parts, "  "))
  local rt = tree[1]
  local function count_kids(c, d)
    if c == nil or d > 4 then return 0 end
    local n = 0
    for _, k in ipairs(c.__kids or {}) do n = n + 1 + count_kids(k, d + 1) end
    return n
  end
  out(string.format("  [诊断] 假树：根数=%d，root 名字=%s，root 子树节点数=%d",
    #tree, tostring(rt and rt.name), count_kids(rt, 0)))
end
step(1)
out(string.format("  [诊断] 调 OnUpdate 后：frames=%s  cell.1.1 Δ=%d  selbar Δ=%d",
  tostring(cur.frames), vis_of("cell.1.1") - before, vis_of("selbar") - bar_before))
out(string.format("  [诊断] 调 OnUpdate 后：frames=%s screen=%s 同一会话=%s",
  tostring(cur.frames), tostring(cur.controller and cur.controller.screen),
  tostring(cur == dbg.Murdoku.current())))
local fired = vis_of("cell.1.1") - before
ok(fired > 0,
  "★ 帧号 == 300 那一帧，`cell.*` 的按屏同步**确实会跑**（证明代码在，只是节流位错）",
  "实测 cell.1.1 SetVisible " .. tostring(fired) .. " 次")

----------------------------------------------------------------------------
out("\n== C. `apply_ruler_layout` 的重复打印（每次 render 都调）==")
local n_ruler = count_log("行标/列标已按格子实际位置对齐")
local n_check = count_log("核对：cell.1.1=")
out(string.format("  render 调用 = %d 次，apply_ruler_layout 调用 = %d 次（最后一次返回 %s）",
  C2.render, C2.ruler, tostring(C2.ruler_ret)))
out(string.format("  「行标/列标已按格子实际位置对齐」打了 %d 次，「核对：cell.1.1=」打了 %d 次",
  n_ruler, n_check))
ok(n_ruler <= 1,
  "★ 稳态里「行标/列标已按格子实际位置对齐」**不重复打**（内容没变就没有新信息）",
  "实测 " .. tostring(n_ruler) .. " 次 / " .. tostring(C2.ruler) .. " 次调用；"
  .. "每次 render 各打 2 行 ⇒ 会话越长日志越多")

----------------------------------------------------------------------------
out("\n== D. 不许有运行时报错（口径与 tests/prop_ledger.lua 一致）==")
do
  local bad = {}
  for i = 1, #logs do
    local L = logs[i]
    if L.level == "error" then
      if L.text:find("attempt to", 1, true) or L.text:find("nil value", 1, true)
        or L.text:find("bad argument", 1, true) then
        bad[#bad + 1] = L.text
      end
    end
  end
  ok(#bad == 0, "没有 printerr 级的 attempt to / nil value / bad argument",
    #bad == 0 and "(0 条)" or ("第一条：" .. tostring(bad[1])))
end

out(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
