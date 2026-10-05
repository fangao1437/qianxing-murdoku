--[[----------------------------------------------------------------------------
  tests/_wip/ruler_cost.lua —— 量化「两个方法第一次真正生效」带来的**新开销**

  背景：修好「方法被吞进 `apply_tray_layout`」之前，`apply_ruler_layout` /
  `diagnose_overlap` **从来没跑过** ⇒ 它们是"免费"的。修好后它们真的会跑，
  所以必须量清楚**跑在哪里、跑几次、每次多少钱** —— 尤其"在不在每帧路径上"。

  量法：假环境（同 tests/perframe_throttle.lua 的约定）+ 给 `adapter.find` 记账，
  然后推 60 帧稳态，数：
    A. `apply_ruler_layout` 被调次数（`main.lua:75` 的守卫在 `Murdoku.render()` 里 ⇒ 每次 render 一次）
    B. 它一次调用做多少次 `find`（按 5×5：1 个 ruler + 5 列标 + 5×5 格子 + 5 行标 + 5×5 格子 + 核对 2 个）
    C. `diagnose_overlap` 的开机成本（`MANAGED` 容器数 × 子控件数 × GetUIPos/GetSizeDelta）
  跑法：lua tests/_wip/ruler_cost.lua
  前置：先 `lua tools/bundle_client_script.lua`
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/ruler_cost.lua"
local root = here:gsub("tests[/\\]_wip[/\\]ruler_cost%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end
local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")

local out = print
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

-- ── 假控件树（带调用计数）────────────────────────────────────────────────
local K = { find = 0, getui = 0, getanchor = 0, setanchor = 0, setpivot = 0,
            find_names = {}, kids = 0 }
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
  c.SetAnchoredPosition = function(_, x, y) c.ax, c.ay = x, y; K.setanchor = K.setanchor + 1 end
  c.GetAnchoredPosition = function() K.getanchor = K.getanchor + 1 return c.ax or 0, c.ay or 0 end
  c.GetUIPos = function() K.getui = K.getui + 1 return { x = c.ax or 0, y = c.ay or 0 } end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() c.pivotSet = true; K.setpivot = K.setpivot + 1 end
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

local tree, g_kids
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
  local cl = attach(rt, make_ctrl("clues"))
  for i = 1, 6 do attach(cl, make_ctrl("clue." .. i)) end
  tree = { rt }
end

_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)"); c.kind = "button"; c.prefabIndex = prefab
    attach(parent, c); return c
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

out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
assert(pcall(chunk))
assert(pcall(OnInit)); assert(pcall(OnStart))

local dbg = _G.__murdoku_debug
local cur = dbg.Murdoku.current()
local ctrl, adapter = cur.controller, cur.adapter

-- ── 给 find 记账（这是 apply_ruler_layout 的主要成本）──────────────────────
local F = { n = 0, misses = 0, names = {} }
do
  local of = adapter.find
  adapter.find = function(self, name, ...)
    F.n = F.n + 1
    F.names[name] = (F.names[name] or 0) + 1
    local r = of(self, name, ...)
    if r == nil then F.misses = F.misses + 1 end
    return r
  end
end
local R = { calls = 0, ret = nil, err = nil }
do
  local orl = adapter.apply_ruler_layout
  adapter.apply_ruler_layout = function(self, ...)
    R.calls = R.calls + 1
    local a, b = pcall(orl, self, ...)
    if not a then R.err = tostring(b) else R.ret = b end
    return b
  end
end
local D = { calls = 0 }
do
  local od = adapter.diagnose_overlap
  adapter.diagnose_overlap = function(self, ...)
    D.calls = D.calls + 1
    return od(self, ...)
  end
end

-- ── A. 一次调用的成本（先把计数器归零，避免把"切屏那次"算进来）────────────
out("\n== A. `apply_ruler_layout(5,5)` 单次成本 ==")
ctrl.screen = nil
pcall(OnUpdate, 1 / 60)          -- 让切屏/首帧那一轮先跑完
F.n, K.getui, K.getanchor, K.setanchor, K.setpivot = 0, 0, 0, 0, 0
for k in pairs(F.names) do F.names[k] = nil end
R.calls = 0
adapter:apply_ruler_layout(5, 5)
local d_find = F.n
local d_getui = K.getui
out(string.format("  单次调用：find %d 次、GetUIPos %d 次、GetAnchoredPosition %d 次、SetAnchoredPosition %d 次、SetPivot %d 次；返回 %s",
  d_find, d_getui, K.getanchor, K.setanchor, K.setpivot, tostring(R.ret)))
out("  find 明细（按次数降序，前 8 个）：")
local findlist = {}
for k, v in pairs(F.names) do findlist[#findlist + 1] = { k = k, v = v } end
table.sort(findlist, function(a, b) return a.v > b.v end)
for i = 1, math.min(8, #findlist) do
  out(string.format("    %-16s %d 次", findlist[i].k, findlist[i].v))
end

-- ── B. 它到底在不在**每帧**路径上 ────────────────────────────────────────
out("\n== B. 在不在每帧路径上（推 60 帧稳态）==")
local F1, R1 = F.n, R.calls
local frames1 = cur.frames or 0
local r0 = ctrl.render
local RC = { render = 0 }
ctrl.render = function(self, ...) RC.render = RC.render + 1 return r0(self, ...) end
for _ = 1, 60 do pcall(OnUpdate, 1 / 60) end
local dF, dR, dFrame = F.n - F1, R.calls - R1, (cur.frames or 0) - frames1
out(string.format("  60 帧里：OnUpdate 走了 %d 帧、controller.render %d 次、apply_ruler_layout %d 次",
  dFrame, RC.render, dR))
out(string.format("  这 60 帧里 find 共 %d 次 ⇒ 平均 %.1f 次/帧（其中 ruler 对齐占 %d 次）",
  dF, dF / math.max(1, dFrame), dR * d_find))
out(string.format("  ⚠️ 判读：apply_ruler_layout 每帧 %.2f 次 ⇒ **在每帧路径上**（main.lua:75 在 Murdoku.render 里）",
  dR / math.max(1, dFrame)))

-- ── C. diagnose_overlap 的开机成本 ───────────────────────────────────────
out("\n== C. `diagnose_overlap` 的单次成本（开机跑一次）==")
local f2, g2 = F.n, K.getui
local okd, hits = pcall(function() return adapter:diagnose_overlap() end)
out(string.format("  单次调用：find %d 次、GetUIPos %d 次、GetSizeDelta/子控件遍历；返回 %s（ok=%s）",
  F.n - f2, K.getui - g2, tostring(hits), tostring(okd)))
out(string.format("  诊断期间 print %d 行", #logs))

out("\n== 结论 ==")
out(string.format("  · `apply_ruler_layout`：**每帧**被调（随 Murdoku.render），单次 %d 次 find + %d 次写属性",
  d_find, K.setanchor))
out(string.format("  · `diagnose_overlap`：**开机一次**（main.lua:544，cfg.overlap_diag 可关）"))
out(string.format("  · 无运行时报错：%d 条 error 级 attempt/nil/bad argument",
  (function()
    local n = 0
    for i = 1, #logs do
      local L = logs[i]
      if L.level == "error" and (L.text:find("attempt to", 1, true) or L.text:find("nil value", 1, true)) then n = n + 1 end
    end
    return n
  end)()))
