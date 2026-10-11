--[[----------------------------------------------------------------------------
  tests/_wip/bound_rearm_count.lua —— 【探针】量 `bound` 的两件事

  ★ 量什么（2026-10-11 陈旧句柄修复）：
     ① **换代时 `bound` 一定会被清** ⇒ 引擎重建控件之后，新控件**能被重新绑上** ✓
        （改之前：`bound[id]` 恒 true ⇒ `bind_input` 早退 ⇒
         **新控件一个监听器都没有** ⇒ "界面看得见、点哪儿都没反应" ✗✓）
     ② **`create_control` 那条路【不】清 `bound`** ⇒ 不会把同一个控件绑两遍 ✓
        （这是本次最容易踩的坑 ✓：清了 ⇒ 建控件时白白清掉 ⇒ 可能双绑 ⇒ 点一下派发两次 ✗）

  ★ 口径（防"假绿"）：
     · ★ **要数的是"引擎侧真的被注册了几个监听器"** ✓ —— 不是读 `bound` 这个内部字段 ✓
       所以在假控件上**自己数** `AddCursorEventListener` 被调了几次 ✓（无法自欺 ✓）
     · **正向对照**：换代之后必须能**再绑上**（计数继续涨）✓
     · **反向对照**：`create_control` 之后**不许**出现"同一个 id 绑两次" ✓
     · 只读：本文件**不改任何生产源码** ✓

  跑法：lua tests/_wip/bound_rearm_count.lua
  前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/bound_rearm_count.lua"
local root = here:gsub("tests[/\\]_wip[/\\]bound_rearm_count%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do
  local function sink(...) end
  _G.print = sink
  _G.printerr = sink
end

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

-- ── 记账：引擎侧真的注册了几个光标监听器（按控件名）────────────────────────
local REG_CNT = {}
local function attach(parent, c)
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end

local function make_ctrl(name, kind)
  local c = {
    name = name, kind = kind or "container", visible = true, active = true,
    __kids = {}, interactable = true, raycastTarget = false,
  }
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
  c.SetAlpha = function() end
  -- ★ 记账点：这是"引擎侧真的注册了几个监听器"的唯一可信来源 ✓
  c.AddCursorEventListener = function() REG_CNT[name] = (REG_CNT[name] or 0) + 1 end
  c.SetImage = function() return false end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  return c
end

local tree, REG = {}, {}
do
  local rt = make_ctrl("root")
  REG["root"] = rt
  for _, n in ipairs({ "topbar", "left", "tray", "clues", "board", "right", "actions", "modal", "intro", "home", "select" }) do
    REG[n] = attach(rt, make_ctrl(n))
  end
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)", "button")
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
    s.AddInt = b; s.AddFloat = b; s.AddString = b; s.AddBool = b; s.SendSignal = b
    return s
  end,
  PlayAudio2D = b,
  GetText = function() return "" end,
}
_G.script = {
  EnableUpdate = b, RegisterServerSignalHandler = b,
  RegisterCustomVariableChangedHandler = b, Invoke = b,
  GetParam = function() return nil end,
}
-- ★ 必须给 `Enum.CursorEventType` —— 否则 `bind_input` 在读不到它时**直接 return** ✓
--   （那会让本探针全绿/全红都失去意义：它量的是"绑定"，不是"枚举解析"✓）
_G.Enum = {
  CursorEventType = {
    CursorClick = "CursorClick", CursorClickDown = "CursorClickDown",
    CursorClickUp = "CursorClickUp", CursorDrag = "CursorDrag",
  },
  KeyEventType = { KeyDown = "KeyDown", KeyUp = "KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
-- 先验"新参数在不在"——否则量的是旧产物
do
  local fh = io.open(SCRIPT_PATH, "rb")
  if fh == nil then out("  打不开产物 ⇒ 先跑 bundle"); os.exit(1) end
  local body = fh:read("a"); fh:close()
  if body:find("keep_bindings", 1, true) == nil then
    out("  ✗ 产物里没有 `keep_bindings` ⇒ 这是旧产物 ⇒ 量不到（不伪造数字）")
    os.exit(1)
  end
  out("  产物已含 `keep_bindings`（换代清 bound ✓ 建控件不清 ✓）")
end

local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart)

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local adapter, ctrl = cur.adapter, cur.controller
if adapter == nil or type(adapter.bind_input) ~= "function" then
  out("  adapter:bind_input 不在 ⇒ 量不到"); os.exit(2)
end
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 绑一个按钮 A，确认引擎侧真的注册了监听器
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 坏一个可绑的按钮 `probe.a`，绑它一次 ==")
do
  local a = attach(REG["board"], make_ctrl("probe.a", "button"))
  adapter.controls["probe.a"] = a
  pcall(function() adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } }) end)
  local n1 = REG_CNT["probe.a"] or 0
  ok(n1 > 0, "第 1 次绑定 ⇒ 引擎侧真的注册了监听器", "注册 " .. tostring(n1) .. " 个")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [2] 同一代里再绑同一个 id ⇒ 必须**早退**（不能双绑）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] 同一代里重复调用 `bind_input` ⇒ 不许双绑 ==")
do
  local before = REG_CNT["probe.a"] or 0
  pcall(function() adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } }) end)
  local after = REG_CNT["probe.a"] or 0
  ok(after == before, "★★ 防重复绑定仍然有效（`bound` 闩锁 ✓）",
    "注册 " .. tostring(before) .. " → " .. tostring(after) .. "（应不变）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] 换代（切屏）⇒ `bound` 被清 ⇒ 新控件**能重新绑上**
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] 换代（切屏）后：新控件必须能重新绑上 ==")
do
  -- 模拟"引擎销毁并重建了全部客户端控件"：换一个**新的**控件对象挂到同一个名字下
  local fresh = attach(REG["board"], make_ctrl("probe.a", "button"))
  adapter.controls["probe.a"] = fresh
  local before = REG_CNT["probe.a"] or 0

  -- 换代事件：改 screen 让 Controller:render 走 invalidate_lookups 那条路
  ctrl.screen = "select"
  ctrl.dirty = true
  pcall(function() ctrl:render(adapter) end)

  -- 换代之后，新控件应当可以被重新绑上
  pcall(function() adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } }) end)
  local after = REG_CNT["probe.a"] or 0
  ok(after > before,
    "★★ 换代后【新控件能被重新绑上】（改之前 `bound` 恒 true ⇒ 一个监听器都没有 ✗）",
    "注册 " .. tostring(before) .. " → " .. tostring(after) .. "（应增加）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [4] 反向对照：`create_control` 那条路**不许**清 `bound`（否则可能双绑）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [4] 反向对照：`create_control` 里那次作废**不许**清 `bound` ==")
do
  -- 绑好一个探针控件，然后模拟 `create_control` 内部那次 invalidate
  local b2 = attach(REG["board"], make_ctrl("probe.b", "button"))
  adapter.controls["probe.b"] = b2
  pcall(function() adapter:bind_input("probe.b", { id = "probe.b", kind = "button", event = { action = "noop" } }) end)
  local n1 = REG_CNT["probe.b"] or 0

  -- ★ 这是 `create_control` 的确切调用形状（带 keep_bindings ✓）
  pcall(function() adapter:invalidate_lookups("create:probe.b", { keep_bindings = true }) end)
  -- ★★ 直接证据（不是靠 n2==n1 这种"可能只是因为早退"的间接判断 ✗）：
  --    `keep_bindings = true` ⇒ `bound` 里**这一条还在** ✓
  --    若它被清了 ⇒ 下面那次 `bind_input` 就会**再注册一遍** ⇒ 双绑 ✗
  local still_bound = false
  pcall(function() still_bound = (adapter.bound ~= nil and adapter.bound["probe.b"] == true) end)
  ok(still_bound,
    "★★ 直接证据：`keep_bindings=true` 之后 `bound['probe.b']` **仍在**（没被清 ✓）",
    "bound['probe.b']=" .. tostring(still_bound))
  -- 之后再调一次 bind_input：若 `bound` 被清了 ⇒ 会**再绑一遍** ⇒ 双绑 ✗
  pcall(function() adapter:bind_input("probe.b", { id = "probe.b", kind = "button", event = { action = "noop" } }) end)
  local n2 = REG_CNT["probe.b"] or 0
  ok(n2 == n1,
    "★★ `create_control` 那次作废**不清** `bound` ⇒ 不会双绑（监听器数不变 ✓）",
    "注册 " .. tostring(n1) .. " → " .. tostring(n2) .. "（应不变）")

  -- 正面对照：**不带** keep_bindings 的作废（= 换代）**必须**清
  pcall(function() adapter:invalidate_lookups("screen=x level=y") end)
  local cleared = false
  pcall(function() cleared = (adapter.bound == nil or adapter.bound["probe.b"] == nil) end)
  ok(cleared,
    "★ 对照：换代那次作废**会**清 `bound`（bound['probe.b'] 消失 ✓）",
    "cleared=" .. tostring(cleared))
  pcall(function() adapter:bind_input("probe.b", { id = "probe.b", kind = "button", event = { action = "noop" } }) end)
  local n3 = REG_CNT["probe.b"] or 0
  ok(n3 > n2,
    "★ 对照：换代那次作废**会**清 `bound` ⇒ 随后能重新绑上",
    "注册 " .. tostring(n2) .. " → " .. tostring(n3) .. "（应增加）")
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
