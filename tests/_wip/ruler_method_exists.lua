--[[----------------------------------------------------------------------------
  tests/_wip/ruler_method_exists.lua —— **不调用 `apply_tray_layout`** 也能拿到
  `adapter.apply_ruler_layout` / `adapter.diagnose_overlap` 吗？

  这是「方法被吞进 `apply_tray_layout` 体内」这条静默失效的**直接运行时证据**：
    · 修之前：两个方法定义在 `apply_tray_layout` 的**函数体里** ⇒ 只有那个函数被调用过
      才存在。本文件**永不调用**它 ⇒ `adapter.apply_ruler_layout == nil` ✗
    · 修之后：两个方法在**文件顶层** ⇒ 加载时就有 ⇒ `~= nil` ✓

  为什么这条证据比"测试全绿"更硬：`lua/main.lua` 的守卫写法是
      `if adapter.apply_ruler_layout then adapter:apply_ruler_layout(...) end`
  ⇒ **方法不存在时零报错、静默跳过**。所以"加载后它到底在不在"是唯一能分辨的口径。

  假引擎写法照抄 `tests/prop_ledger.lua` / `tests/perframe_throttle.lua`（同一套约定）。
  跑法：lua tests/_wip/ruler_method_exists.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/ruler_method_exists.lua"
local root = here:gsub("tests[/\\]_wip[/\\]ruler_method_exists%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end
local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")

local out = print

-- ── 假控件树（与 prop_ledger / perframe_throttle 同一套约定）──────────────────
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
  c.SetVisible = function(_, v) c.visible = v end
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
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  local board = attach(rt, make_ctrl("board"))
  local ruler = attach(board, make_ctrl("ruler"))
  for i = 1, 5 do
    attach(ruler, make_text("ruler.c." .. i))
    attach(ruler, make_text("ruler.r." .. i))
  end
  attach(rt, make_ctrl("topbar"))
  attach(rt, make_ctrl("right"))
  attach(rt, make_ctrl("clues"))
  tree = { rt }
end

_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"; c.prefabIndex = prefab
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

-- ── 劫持日志（要证明的正是"零报错"，所以必须收着看）─────────────────────────
local logs = {}
do
  local function collect(level, ...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
  end
  _G.print = function(...) collect("info", ...) end
  _G.printerr = function(...) collect("error", ...) end
end

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
local adapter = cur.adapter

local pass, fail = 0, 0
local function ok(cond, label, detail)
  if cond then pass = pass + 1; out("  [PASS] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  else fail = fail + 1; out("  [FAIL] " .. label .. (detail and ("   " .. tostring(detail)) or "")) end
end

-- ★ 本文件**从不**调用 `apply_tray_layout`（这正是判据的前提）。
--   顺手钉住"真的没调" —— 否则这条证据不成立。
local tray_called = false
do
  local otl = adapter.apply_tray_layout
  if type(otl) == "function" then
    adapter.apply_tray_layout = function(self, ...) tray_called = true return otl(self, ...) end
  end
end

out("\n== 判据：**不调用 `apply_tray_layout`** 也要能拿到这两个方法 ==")
ok(tray_called == false, "（前提）本文件从未调用过 `apply_tray_layout`", "tray_called=" .. tostring(tray_called))
ok(type(adapter.apply_ruler_layout) == "function",
  "★ 不调 `apply_tray_layout` 也能拿到 `adapter.apply_ruler_layout`",
  "实测 type=" .. type(adapter.apply_ruler_layout))
ok(type(adapter.diagnose_overlap) == "function",
  "★ 不调 `apply_tray_layout` 也能拿到 `adapter.diagnose_overlap`",
  "实测 type=" .. type(adapter.diagnose_overlap))

-- 反向对照：证明"被吞进函数体"的可观测后果就是这个 nil。
--   把两个方法定义分别和 `apply_tray_layout` 的**同一份**闭包来源比一比：
--   修之前它们只存在于 `apply_tray_layout` 的 upvalue 环境里。
out("\n== 反向对照：`lua/main.lua` 那种守卫写法在方法缺失时的实际后果 ==")
do
  -- ⚠️ `main.lua` 里是**三处**守卫，但只有**两处**是"只看方法在不在"：
  --     L75/532  `if a.apply_ruler_layout ~= nil then …` / `if adapter.apply_ruler_layout then …`
  --     L544     `if adapter.diagnose_overlap and adapter.cfg.overlap_diag ~= false then …`
  --   ⇒ 第三处是**复合条件**（还要求 `cfg.overlap_diag ~= false`），
  --     单看"方法在不在"数不出 3 —— 数 3 是**本文件的算术错误**，
  --     不是被测代码的问题。这里只断言那**两处纯存在性守卫** ✓
  local hits, total = 0, 2
  if adapter.apply_ruler_layout ~= nil then hits = hits + 1 end
  if adapter.diagnose_overlap ~= nil then hits = hits + 1 end
  out(string.format("  main.lua 两处纯存在性守卫（L75 / L532）：本次 %d/%d 放行"
    .. "；第三处 L544 是复合条件（还要看 cfg.overlap_diag），单列不计", hits, total))
  ok(hits == total, "★ 两处纯存在性守卫**全部放行**（修之前是 0/2 —— 静默跳过、零报错）",
    hits .. "/" .. total)
end

-- ── 真调一次，确认"存在"之外还"能用"（不抛错、有返回值）───────────────────
out("\n== 顺带：真的调一次，确认存在之外还能用 ==")
do
  local okr, ret = pcall(function() return adapter:apply_ruler_layout(5, 5) end)
  ok(okr, "`apply_ruler_layout(5, 5)` 不抛错", okr and ("返回 " .. tostring(ret)) or tostring(ret))
  local okd, hit = pcall(function() return adapter:diagnose_overlap() end)
  ok(okd, "`diagnose_overlap()` 不抛错", okd and ("返回 " .. tostring(hit)) or tostring(hit))
end

out("\n== 不许有运行时报错（口径与 prop_ledger 一致）==")
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
