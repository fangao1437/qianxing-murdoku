--[[----------------------------------------------------------------------------
  tests/_wip/probe_cell_click_chain.lua —— 离线把「点格子没反应」切成 A/B/C 三段

  ★ 纯离线探针：不跑模拟器（tools/sim/* 一个都不碰）✓ 不依赖任何引擎 ✓
  ★ 只【读】lua/**，一个字节都不改 ✓
  ★ 搭法照抄 `tests/selftest.lua`（已验证可用 ✓）：Core.new + UIC.new + 桩适配器
  ★ A 段用【假引擎】把真适配器（engine_adapter_qianxing）跑起来：
      假控件树 + 假 Enum + 手工触发 AddCursorEventListener 注册的回调
      —— 等价于引擎真的派发了一次 CursorClick（不经过模拟器 ✓）

  跑法：
    lua tests/_wip/probe_cell_click_chain.lua

  三段与判据（全部只看实测输出）：
    [C 逻辑层] 直接喂 `on_input{action=click, r, c, phase=click}`
               · 间隔 0 / 0.1s / 0.4s 各来一次双击 → grid 是否被放置 / moves 是否 +1
               · **没选人**时（= 模拟器 13/13 的真实前置）→ 看拒绝原因
    [B 路由层] `on_input` 收 click：phase 各档、r/c 为 nil、_suppress_click
    [A 事件层] 真适配器 + 假引擎：bind_input 到底绑没绑 · 派发到 on_input 的字段与类型
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/probe_cell_click_chain.lua"
local root = here:gsub("tests[/\\]_wip[/\\]probe_cell_click_chain%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

package.path = table.concat({
  package.path,
  root .. "lua/?.lua",
  root .. "lua/?/init.lua",
  root .. "?.lua",
}, ";")

local Core     = require("murdoku_core")
local UIC      = require("ui_controller")
local Adapters = require("engine_adapter")
local Qianxing = require("engine_adapter_qianxing")
local Level    = require("levels.demo_selftest")

local out = print                     -- 我自己的输出（被探代码的 print 会被劫持）
local logs = {}
local function collect(level, ...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
end
_G.print = function(...) collect("info", ...) end
_G.printerr = function(...) collect("error", ...) end

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    out("  [PASS] " .. name .. (extra and ("   " .. tostring(extra)) or ""))
  else
    fail = fail + 1
    out("  [FAIL] " .. name .. (extra and ("   " .. tostring(extra)) or ""))
  end
end
-- 只记事、不判红绿（用于打印"实测值"）
local function note(name, val)
  out("  [实测] " .. name .. " = " .. tostring(val))
end
local function show_logs(pat, limit)
  limit = limit or 6
  local n = 0
  for i = 1, #logs do
    if logs[i].text:find(pat, 1, true) then
      n = n + 1
      if n <= limit then out("      | " .. logs[i].text) end
    end
  end
  if n == 0 then out("      | （没有匹配 " .. pat .. " 的日志）") end
  if n > limit then out("      | …（共 " .. n .. " 条，只列前 " .. limit .. " 条）") end
end
local function progress_of(ctrl)
  local vm = ctrl.core:view()
  return string.format("%d / %d", ctrl:placed_count(vm), vm.piece_count)
end
local function moves_of(c)
  local vm = c:view()
  return (vm.hud and vm.hud.moves) or 0
end

out("==================================================================")
out(" probe_cell_click_chain —— A/B/C 三段离线切开")
out("==================================================================")

local core = assert(Core.new(Level))
local stub = Adapters.new_stub()
local ctrl = UIC.new(core, { skip_intro = true })
ctrl:render(stub, true)

-- 每小节之间把控制器的"手势/双击记忆"清干净（否则上一节的 last_click 会串味）
local function reset_ctrl()
  core:reset()
  ctrl.now = 0
  ctrl.last_click = nil
  ctrl.pending_click = nil
  ctrl._press = nil
  ctrl._suppress_click = nil
  ctrl._refuse_seen = {}
end
local function click(r, c, phase)
  ctrl:on_input({ action = "click", r = r, c = c, phase = phase or "click" })
end

----------------------------------------------------------------------------
out("")
out("== C 段（逻辑层）：直接喂 on_input{action=click, r, c, phase=click} ==")
out("   —— 绕开适配层，只看 ui_controller:on_cell_click 自己认不认双击")
out("   （前置：先选一个角色，否则请求一定会被 pre_place 的门控拒掉）")

-- C1 两次点击【间隔 0】（完全不推进时钟）
reset_ctrl()
core:select_suspect("A")
click(1, 1); click(1, 1)
note("C1 间隔0     grid[1][1]", tostring(core.grid[1][1]))
note("C1 间隔0     moves      ", tostring(moves_of(core)))
note("C1 间隔0     进度       ", progress_of(ctrl))
check("C1 间隔 0 ⇒ 双击成立、放下去了", core.grid[1][1] == "A", tostring(core.grid[1][1]))
check("C1 间隔 0 ⇒ 步数 +1", moves_of(core) == 1, tostring(moves_of(core)))

-- C2 两次点击【间隔 0.1s】（推进一次 tick，仍在 0.35 窗口内）
reset_ctrl()
core:select_suspect("A")
click(1, 1); ctrl:tick(0.1); click(1, 1)
note("C2 间隔0.1   grid[1][1]", tostring(core.grid[1][1]))
note("C2 间隔0.1   moves      ", tostring(moves_of(core)))
note("C2 间隔0.1   进度       ", progress_of(ctrl))
check("C2 间隔 0.1s ⇒ 双击成立、放下去了", core.grid[1][1] == "A", tostring(core.grid[1][1]))

-- C3 两次点击【间隔 0.4s】（越过 DOUBLE_CLICK_SECONDS = 0.35）
reset_ctrl()
core:select_suspect("A")
click(1, 1); ctrl:tick(0.4); click(1, 1)
note("C3 间隔0.4   grid[1][1]", tostring(core.grid[1][1]))
note("C3 间隔0.4   moves      ", tostring(moves_of(core)))
note("C3 间隔0.4   notes[1][1]", tostring(core.notes[1][1]["A"]))
check("C3 间隔 0.4s ⇒ 【不算】双击（没有放置）", core.grid[1][1] == nil, tostring(core.grid[1][1]))

-- C4 ★ 模拟器 13/13 的真实前置：**没有任何人被选中**
--
--    为什么这是真实前置：`probe_cursor.mjs` 的点击序列是
--      click(tray.A) → click(cell.1.3) → tick(0.03) → click(cell.1.3)
--    而 `tray.A` 这个控件**不在运行树里**（模拟器日志原话：`tray.A **找不到这个控件**`
--    ✓ 计划里也没有它 ✓）⇒ 这一步点了个空 ⇒ 没有人被选中。
reset_ctrl()
local selected_before = core.selected
note("C4 前置 selected", tostring(selected_before))
click(1, 1); ctrl:tick(0.03); click(1, 1)
note("C4 grid[1][1] ", tostring(core.grid[1][1]))
note("C4 moves      ", tostring(moves_of(core)))
note("C4 x_marks[1][1]", tostring(core.x_marks[1][1]))
note("C4 进度       ", progress_of(ctrl))
do
  local why = {}
  for k, v in pairs(ctrl._refuse_seen or {}) do why[#why + 1] = k .. "×" .. tostring(v) end
  note("C4 拒绝原因  ", (#why > 0) and table.concat(why, " / ") or "（没有拒绝记录）")
end
check("C4 没选人 ⇒ 双击【放不下去】（复刻 13/13 的 0/5）", core.grid[1][1] == nil,
  tostring(core.grid[1][1]))
out("   ↓ ui_controller 自己打的拒绝原因（原话）")
show_logs("没生效", 3)

-- C5 同上，但比较：**先补一次选中**（= 把 13/13 缺的那一步补上）
reset_ctrl()
ctrl:on_input({ action = "suspect", id = "A" })
note("C5 补选后 selected", tostring(core.selected))
click(1, 1); ctrl:tick(0.03); click(1, 1)
note("C5 grid[1][1] ", tostring(core.grid[1][1]))
note("C5 moves      ", tostring(moves_of(core)))
note("C5 进度       ", progress_of(ctrl))
check("C5 补上选中 ⇒ 同一套双击**立刻能放置**（C 段本身是好的）",
  core.grid[1][1] == "A", tostring(core.grid[1][1]))

----------------------------------------------------------------------------
out("")
out("== B 段（路由层）：on_input 收到 click 之后的走向 ==")

-- B1 phase = click（适配层给的就是这个）→ 必须走到 on_cell_click
reset_ctrl()
core:select_suspect("A")
click(1, 2)
note("B1 notes[1][2][A]", tostring(core.notes[1][2]["A"]))
check("B1 phase=click ⇒ 走到 on_cell_click（落了笔记）", core.notes[1][2]["A"] == true,
  tostring(core.notes[1][2]["A"]))

-- B2 phase = down / up / drag（真实引擎会先派发这两档）
reset_ctrl()
core:select_suspect("A")
click(1, 2, "down")
note("B2 _press 记录", tostring(ctrl._press and ctrl._press.r) .. "," ..
  tostring(ctrl._press and ctrl._press.c))
click(1, 2, "up")
note("B2 notes[1][2][A]（up 之后）", tostring(core.notes[1][2]["A"]))
check("B2 phase=down/up ⇒ 不进 on_cell_click（只走手势）", core.notes[1][2]["A"] == nil,
  tostring(core.notes[1][2]["A"]))

-- B3 r/c 为 nil（= ① 号 bug 没修时的样子）
--
-- ★★★★★ 2026-10-05 **已反向：从"记录崩溃"改成"哨兵：不许崩"** ✓✗（**不是删断言** ✗）
--   原来这条断言的是「`r`/`c` 为 nil ⇒ **崩**」✗ —— ★ 那是**如实记录当时的 bug** ✓
--   ⇒ ★ 后来 `Controller:on_cell_click` 加了 `if r == nil or c == nil then return end` ✓
--     （依据：★ **两处独立实测**都发现它会抛 ✓ —— 见 `docs/点格子没反应-三段切开结论.md` ✓）
--   ⇒ ★ **崩溃不存在了** ✗ ⇒ 旧断言**必然变红** ✗ —— ★ 但那**不是退化** ✓ 是**修复生效** ✓
--   ★ 处置按 §E5：**反向成哨兵** ✓ —— ★ 断言「**不许崩**」✓ ⇒ **这个崩溃一旦回来，立刻变红** ✓✓
--   ⚠️ 注意：**"不崩"不等于"无事发生"** ✗ —— nil 点击应当**安静地什么都不做** ✓
--     （★ 那一层由 `probe_click_path.lua` 的 "r/c 为 nil ⇒ 不放置" 断言守着 ✓）
reset_ctrl()
core:select_suspect("A")
local ok_b3, err_b3 = pcall(function()
  ctrl:on_input({ action = "click", phase = "click" })
end)
note("B3 pcall 成功", tostring(ok_b3))
note("B3 错误信息", tostring(err_b3))
check("B3 `r`/`c` 为 nil ⇒ **不崩** ✓（哨兵：此崩溃已修 ✗ —— 回来即变红 ✓）",
  ok_b3 == true, tostring(err_b3))

-- B4 _suppress_click（长按成功后会置位）→ 会不会把点击吞掉
reset_ctrl()
core:select_suspect("A")
ctrl._suppress_click = true
click(1, 2)
note("B4 notes[1][2][A]", tostring(core.notes[1][2]["A"]))
note("B4 _suppress_click 之后", tostring(ctrl._suppress_click))
check("B4 有 _suppress_click ⇒ 这一次 click 被吞（笔记没落）", core.notes[1][2]["A"] == nil,
  tostring(core.notes[1][2]["A"]))
check("B4 吞掉之后标志已清（不会永久吞）", ctrl._suppress_click == nil)

----------------------------------------------------------------------------
out("")
out("== A 段（事件层）：真适配器 + 假引擎 ==")
out("   —— 假控件树 + 假 Enum，走 build_layout → render → create_control → bind_input")

-- 假控件树：结构与真机同形的一小片（root > stage > board > cell.r.c …）
local fake_tree = {}
local function make_ctrl(name, kind)
  local c = {
    name = name, kind = kind or "container", visible = true, active = true,
    interactable = true, raycastTarget = true, __kids = {}, cbs = {}, cb_n = 0,
  }
  c.GetChildren = function(self) return self.__kids end
  c.GetChild = function(self, key)
    if type(key) == "number" then return self.__kids[key + 1] end
    for i = 1, #self.__kids do if self.__kids[i].name == key then return self.__kids[i] end end
    return nil
  end
  c.GetChildCount = function(self) return #self.__kids end
  c.GetParent = function(self) return self.__parent end
  c.SetVisible = function(self, v) self.visible = v end
  c.SetActive = function(self, v) self.active = v end
  c.SetSizeDelta = function(self, w, h) self.w, self.h = w, h end
  c.GetSizeDelta = function(self) return self.w or 0, self.h or 0 end
  c.SetAnchoredPosition = function(self, x, y) self.ax, self.ay = x, y end
  c.GetAnchoredPosition = function(self) return self.ax or 0, self.ay or 0 end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() end
  c.SetLocalScale = function() end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  c.SetImage = function() return true end
  -- ★ 关键：把引擎注册进来的回调**收下来**，稍后手工触发（= 引擎派发了一次点击）
  c.AddCursorEventListener = function(self, kind, cb)
    self.cbs[kind] = cb
    self.cb_n = self.cb_n + 1
  end
  return c
end
local function attach(parent, c)
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end
local T = {}
-- 按名字在假树里找控件（假树很小，深度优先足够）
local function tree_find(name)
  for i = 1, #fake_tree do
    local stack = { fake_tree[i] }
    while #stack > 0 do
      local cur = table.remove(stack)
      if cur.name == name then return cur end
      for j = 1, #cur.__kids do stack[#stack + 1] = cur.__kids[j] end
    end
  end
  return nil
end
do
  local rt = make_ctrl("root")
  attach(rt, make_ctrl("home"))
  attach(rt, make_ctrl("select"))
  local st = attach(rt, make_ctrl("stage"))
  local board = attach(st, make_ctrl("board"))
  for r = 1, core.rows do
    for c = 1, core.cols do
      local cell = make_ctrl("cell." .. r .. "." .. c, "button")
      local content = attach(cell, make_ctrl("content"))
      attach(content, make_ctrl("face"))
      attach(cell, make_ctrl("note"))
      attach(cell, make_ctrl("x"))
      attach(board, cell)
    end
  end
  attach(st, make_ctrl("ruler"))
  attach(rt, make_ctrl("topbar"))
  attach(rt, make_ctrl("right"))
  attach(rt, make_ctrl("clues"))
  fake_tree = { rt }
  T.root = rt
  T.cell11 = tree_find("cell.1.1")
  T.cell13 = tree_find("cell.1.3")
end
note("假树里 cell.1.1 的 name", tostring(T.cell11 and T.cell11.name))
note("假树里 cell.1.3 的 name", tostring(T.cell13 and T.cell13.name))

_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return fake_tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)", "button")
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
-- ★ 枚举必须给：bind_input 拿不到 CursorEventType.CursorClick 时会**直接 return**（L4454-4458）
local ENUM_CLICK, ENUM_DOWN, ENUM_UP, ENUM_DRAG = 101, 102, 103, 104
_G.Enum = { CursorEventType = {
  CursorClick = ENUM_CLICK, CursorDown = ENUM_DOWN,
  CursorUp = ENUM_UP, CursorDrag = ENUM_DRAG,
} }

local adapter = Qianxing.new({
  apply_rect = false,
  debug_click = false,     -- 关掉点击日志，避免淹没证据（下面单独看派发结果）
  debug_event = false,
})
local core2 = assert(Core.new(Level))
local ctrl2 = UIC.new(core2, { skip_intro = true })

local got = {}                            -- adapter.on_input 收到的事件（逐条记下来）
adapter.on_input = function(evt)
  local e = { n = #got + 1 }
  for k, v in pairs(evt) do e[k] = v; e[k .. "_type"] = type(v) end
  got[#got + 1] = e
  -- 真链路：main.lua:278 就是这么把它转给控制器的（这里包 pcall，免得一次崩溃中断探针）
  local ok, err = pcall(function() ctrl2:on_input(evt) end)
  if not ok then e.handler_error = tostring(err) end
end

local ok_render, err_render = pcall(function() ctrl2:render(adapter, true) end)
note("ctrl2:render 是否成功", tostring(ok_render))
if not ok_render then note("render 错误", tostring(err_render)) end

note("adapter.bound['cell.1.1']", tostring(adapter.bound and adapter.bound["cell.1.1"]))
note("假控件 cell.1.1 收到的回调数", tostring(T.cell11.cb_n))
note("假控件 cell.1.3 收到的回调数", tostring(T.cell13.cb_n))
check("A1 create_control 时给 cell.1.1 绑上了光标事件", adapter.bound ~= nil
  and adapter.bound["cell.1.1"] == true, tostring(adapter.bound and adapter.bound["cell.1.1"]))
check("A1 引擎侧真的注册了回调（AddCursorEventListener 被调到）", T.cell11.cb_n > 0,
  tostring(T.cell11.cb_n))

-- A2 手工触发引擎回调 = 引擎派发了一次 CursorClick
got = {}
local cb = T.cell13.cbs[ENUM_CLICK]
note("cell.1.3 的 CursorClick 回调存在", tostring(cb ~= nil))
if cb then
  cb({ GetUIPos = function() return 123.0, 456.0 end })
end
local e1 = got[1]
if e1 == nil then
  check("A2 派发到 adapter.on_input", false, "on_input 一次都没被调到")
else
  note("A2 action", tostring(e1.action) .. " (" .. tostring(e1.action_type) .. ")")
  note("A2 phase ", tostring(e1.phase) .. " (" .. tostring(e1.phase_type) .. ")")
  note("A2 r     ", tostring(e1.r) .. " (" .. tostring(e1.r_type) .. ")")
  note("A2 c     ", tostring(e1.c) .. " (" .. tostring(e1.c_type) .. ")")
  note("A2 x,y   ", tostring(e1.x) .. "," .. tostring(e1.y))
  check("A2 on_input 收到 action=click", e1.action == "click", tostring(e1.action))
  check("A2 phase=click（不是 down/up/drag）", e1.phase == "click", tostring(e1.phase))
  check("A2 r 是 number 且 = 1", e1.r == 1 and e1.r_type == "number", tostring(e1.r))
  check("A2 c 是 number 且 = 3", e1.c == 3 and e1.c_type == "number", tostring(e1.c))
  check("A2 控制器侧没有抛错", e1.handler_error == nil, tostring(e1.handler_error))
end
out("   ↓ _fire 自己打的三层计数（原话）")
show_logs("[T3Q] _fire#", 3)
show_logs("[T3Q] on_cell_click#", 2)

-- A3 负对照：把 Enum 抽掉 ⇒ bind_input 应当【绑不上】（证明上面的 bound=true 有意义）
do
  local saved = _G.Enum
  _G.Enum = nil
  local core3 = assert(Core.new(Level))
  local ctrl3 = UIC.new(core3, { skip_intro = true })
  local ad3 = Qianxing.new({ apply_rect = false, debug_click = false, debug_event = false })
  ad3.on_input = function() end
  local okc = pcall(function() ctrl3:render(ad3, true) end)
  note("A3 没有 Enum 时 render 成功", tostring(okc))
  note("A3 没有 Enum 时 bound['cell.1.1']", tostring(ad3.bound and ad3.bound["cell.1.1"]))
  check("A3 负对照：没有 CursorEventType ⇒ 一个都没绑上（= 判据能红）",
    (ad3.bound == nil) or (ad3.bound["cell.1.1"] ~= true),
    tostring(ad3.bound and ad3.bound["cell.1.1"]))
  _G.Enum = saved
end

----------------------------------------------------------------------------
out("")
out("== A→B→C 端到端：复刻 13/13 probe_cursor.mjs 的动作序列 ==")
out("   click(tray.A) → tick(0.03) → click(cell.1.3) → tick(0.03) → click(cell.1.3)")
out("   （tray.A 这个控件在运行树里【不存在】—— 模拟器日志原话：tray.A **找不到这个控件**）")

local function fire(name, kind)
  local c = tree_find(name)
  if c == nil then return false end
  local f = c.cbs[kind or ENUM_CLICK]
  if f == nil then return false end
  f({ GetUIPos = function() return 0.0, 0.0 end })
  return true
end

-- E1 复刻：点 tray.A（树里没有这个控件 ⇒ 点了个空）
core2:reset()
ctrl2.now = 0
ctrl2.last_click = nil
ctrl2._press = nil
ctrl2._suppress_click = nil
ctrl2._refuse_seen = {}
note("E1 假树里有 tray.A 吗", tostring(fake_tree[1] ~= nil and fire("tray.A") and "有" or "没有"))
note("E1 点完之后 core.selected", tostring(core2.selected))
check("E1 点 tray.A 之后【没有人被选中】（这正是模拟器里的状态）", core2.selected == nil,
  tostring(core2.selected))

-- E2 两次点 cell.1.3（走完整 A→B→C）
got = {}
fire("cell.1.3"); ctrl2:tick(0.03); fire("cell.1.3"); ctrl2:tick(0.05)
note("E2 on_input 收到次数", tostring(#got))
note("E2 grid[1][3]", tostring(core2.grid[1][3]))
note("E2 x_marks[1][3]", tostring(core2.x_marks[1][3]))
note("E2 moves", tostring(moves_of(core2)))
do
  local vm = core2:view()
  note("E2 进度（hud.progress 同源）", string.format("%d / %d", ctrl2:placed_count(vm), vm.piece_count))
end
show_logs("没生效", 3)
check("E2 复刻出 13/13 的观测值：**放不上去**（先点 tray.A 时）", core2.grid[1][3] == nil,
  tostring(core2.grid[1][3]))

-- E3 把缺的那一步补上（= 让某个控件发出 suspect 事件，等价于"头像卡本来该在"）
core2:reset()
ctrl2.now = 0
ctrl2.last_click = nil
ctrl2._press = nil
ctrl2._suppress_click = nil
ctrl2._refuse_seen = {}
ctrl2:on_input({ action = "suspect", id = "A" })
note("E3 选中", tostring(core2.selected))
got = {}
fire("cell.1.3"); ctrl2:tick(0.03); fire("cell.1.3"); ctrl2:tick(0.05)
note("E3 grid[1][3]", tostring(core2.grid[1][3]))
note("E3 moves", tostring(moves_of(core2)))
do
  local vm = core2:view()
  note("E3 进度", string.format("%d / %d", ctrl2:placed_count(vm), vm.piece_count))
end
check("E3 只补「选中」这一步 ⇒ 同一条 A→B→C 立刻能放置（1 / 5）",
  core2.grid[1][3] == "A", tostring(core2.grid[1][3]))
check("E3 步数 +1", moves_of(core2) == 1, tostring(moves_of(core2)))

----------------------------------------------------------------------------
out("")
out("== 附带测量一：down / up 两档的 `r`/`c` 到底从哪来 ==")
out("   engine_adapter_qianxing.lua:4556 / :4562 的 down / up 回调【没有传 src_id】")
out("   （_fire 的补 r/c 那一段只对 click 档生效）—— 那手势凭什么还能正确长按？")

do
  core2:reset()
  ctrl2.now = 0
  ctrl2.last_click = nil
  ctrl2._press = nil
  ctrl2._suppress_click = nil
  ctrl2._refuse_seen = {}
  core2:select_suspect("A")
  got = {}
  local okd = fire("cell.1.3", ENUM_DOWN)
  note("down 派发成功", tostring(okd))
  note("controller._press", tostring(ctrl2._press and
    (tostring(ctrl2._press.r) .. "," .. tostring(ctrl2._press.c))))
  check("D1 down 档【也】拿到了 r/c = 1,3 —— 来源不是 _fire，而是 node.event 自己带的",
    ctrl2._press ~= nil and ctrl2._press.r == 1 and ctrl2._press.c == 3,
    tostring(ctrl2._press and ctrl2._press.r))
  ctrl2:tick(0.5)                          -- 按住 0.5s > LONG_PRESS_SECONDS = 0.45
  fire("cell.1.3", ENUM_UP)
  note("D1 长按 0.5s 抬起后的 grid[1][3]", tostring(core2.grid[1][3]))
  note("D1 moves", tostring(moves_of(core2)))
  check("D1 长按抬起 ⇒ 正式放置成功（当前源码下这条路是通的）",
    core2.grid[1][3] == "A", tostring(core2.grid[1][3]))
end

----------------------------------------------------------------------------
out("")
out("== 附带测量二：把事件表换成兜底值 { action = click }（= 坑位清单里描述的漂移状态）==")
out("   做法：**不动 lua/**，只把适配器里这条控件的『认领事件』换成兜底表")
out("   ⇒ 等价于 `live_event()` 走到第三档 —— 这时只有 `_fire` 的补 r/c 能救 click 档")

do
  local claim = adapter.event_claim["cell.1.3"]
  local saved = claim and adapter.events[claim] or nil
  if claim ~= nil then adapter.events[claim] = { action = "click" } end
  note("被替换的认领键", tostring(claim))
  note("替换后 live_event 的 r/c", tostring((claim and adapter.events[claim].r)))

  -- D2a：click 档 ⇒ _fire 从 src_id 补 r/c（这正是提交 6f04c64 修的那一条）
  core2:reset()
  ctrl2.now = 0
  ctrl2.last_click = nil
  ctrl2._press = nil
  ctrl2._suppress_click = nil
  ctrl2._refuse_seen = {}
  core2:select_suspect("A")
  got = {}
  fire("cell.1.3")
  note("D2a on_input 收到的 r/c",
    tostring(got[1] and got[1].r) .. " (" .. tostring(got[1] and got[1].r_type) .. ") / " ..
    tostring(got[1] and got[1].c) .. " (" .. tostring(got[1] and got[1].c_type) .. ")")
  note("D2a notes[1][3][A]", tostring(core2.notes[1][3]["A"]))
  check("D2a 事件表没有 r/c 时，click 档仍然拿到 number 的 r/c（_fire 的修法有效）",
    got[1] ~= nil and got[1].r == 1 and got[1].r_type == "number"
    and got[1].c == 3 and got[1].c_type == "number",
    tostring(got[1] and got[1].r))
  check("D2a click 档照常生效（落了笔记）", core2.notes[1][3]["A"] == true,
    tostring(core2.notes[1][3]["A"]))

  -- D2b：down / up 档 ⇒ 事件表里没有 r/c
  --
  -- ★★★★★ 2026-10-05 **已反向：从"记录崩溃"改成"哨兵：不许崩"** ✓✗（**不是删断言** ✗）
  --   原来断言的是「长按抬起 ⇒ **崩**」✗（`do_place(nil,nil)` → `hold_cell` 比较 nil ✓）
  --   ⇒ ★ 后来 `bind_input` 的 **down/up 回调也传了 `src_id`** ✓
  --     （`engine_adapter_qianxing.lua` 的 `self:_fire(live_event(), "down", data, id)` ✓）
  --     ⇒ `_fire` 从 `cell.<R>.<C>` 解析出 r/c ✓ ⇒ ★ **不再有 nil** ✗ ⇒ **不崩了** ✓
  --   ★ 处置按 §E5：**反向成哨兵** ✓ —— ★ 断言「**不许崩**」✓ ⇒ **崩溃一旦回来立刻变红** ✓✓
  core2:reset()
  ctrl2.now = 0
  ctrl2.last_click = nil
  ctrl2._press = nil
  ctrl2._suppress_click = nil
  ctrl2._refuse_seen = {}
  core2:select_suspect("A")
  got = {}
  fire("cell.1.3", ENUM_DOWN)
  note("D2b _press（down 之后）", tostring(ctrl2._press and
    (tostring(ctrl2._press.r) .. "," .. tostring(ctrl2._press.c))))
  ctrl2:tick(0.5)
  fire("cell.1.3", ENUM_UP)
  local e_up = got[#got]
  note("D2b up 之后控制器抛的错", tostring(e_up and e_up.handler_error))
  check("D2b 事件表没有 r/c 时长按抬起 ⇒ **不崩** ✓（哨兵：此崩溃已修 ✗ —— 回来即变红 ✓）",
    e_up ~= nil and e_up.handler_error == nil,
    tostring(e_up and e_up.handler_error))

  if claim ~= nil then adapter.events[claim] = saved end
end

----------------------------------------------------------------------------
out("")
out("==================================================================")
out(string.format(" 结果：%d 通过 / %d 失败", pass, fail))
out("==================================================================")
if fail > 0 then os.exit(1) end
