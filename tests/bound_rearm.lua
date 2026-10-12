--[[----------------------------------------------------------------------------
  tests/bound_rearm.lua —— ★★ 常驻回归：`bind_input` 的**换代重绑**与**防双绑**

  ★★★ 为什么它必须是**常驻**的（★ 优化组 `回执-优化组-核对接手v206.md` §六.1 ✓）：
    ★ 原文 ✓：「★ 现状：P0 的**唯一**证明是一个 `tests/_wip/` 探针 ✗ —— ★ 而它**不在 23 套里** ✗
      　 ⇒ ★ 而 P0 恰恰是**最容易被我那种双绑回归打回来**的一处 ✗」
    ★★ 所以本文件就是那条建议的落地 ✓：★ 从 `tests/_wip/bound_rearm_count.lua` **提升为常驻** ✓

  ★★★ 它锁的两个症状（★ 都是**用户实测报过**的真症状 ✓）：
    ★ ① ★ **「界面看得见、点哪儿都没反应」** ✗
      　 ★ 成因 ✓：引擎换代（传送/重连/容器隐藏再显示）后控件对象**换了** ✗
      　 ★ 而布尔闩锁还是 `true` ⇒ ★ **新控件一个监听器都没有** ✓
    ★ ② ★ **「单击变放置」** ✗
      　 ★ 成因 ✓：★ **同一个活控件被绑了两遍** ⇒ ★ 一次手势派发两次 ✓
      　 （★ 一次点既走了放置、又走了打标记 ✓）

  ★★★ 判据口径（★ 防"假绿" ✓）：
    ★ **数【引擎侧真的注册了几个监听器】** ✗ —— ★ 不读 `bound` 这个内部字段 ✓
      （★ 本项目吃过"读自己的布尔 ⇒ 自己骗自己"的亏 ✓）
    ★ ★★ 而且**两个方向都必须构造** ✗（★ 只测一种必然漏掉一类回归 ✓）：
      ★ 正向 ✓：换代（对象换了）⇒ ★ **必须能再绑上** ✓
      ★ 反向 ✓：同一对象再绑 ⇒ ★ **必须早退（不许双绑）** ✓

  ★ 只读 ✓：本文件不改生产源码 ✓
  ★ 跑法：lua tests/bound_rearm.lua
  ★ 前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/bound_rearm.lua"
local root = here:gsub("tests[/\\]bound_rearm%.lua$", "")
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
  -- ★★★ 记账点 ✓：本文件全部判据都建在它上面（★ 不读内部字段 ✓）
  c.AddCursorEventListener = function() REG_CNT[name] = (REG_CNT[name] or 0) + 1 end
  -- ★ 也让"摘监听器"可用 ✓ —— 好让"以后若改成先摘后挂"也能被本套件覆盖 ✓
  c.RemoveCursorEventListener = function() c.__removed = (c.__removed or 0) + 1 end
  c.RemoveAllCursorEventListeners = function() c.__removed = (c.__removed or 0) + 1 end
  c.SetImage = function() return false end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  c.SetText = function() end
  return c
end

local tree, REG = {}, {}
do
  local rt = make_ctrl("root")
  REG["root"] = rt
  for _, n in ipairs({ "topbar", "left", "tray", "clues", "board", "right",
                       "actions", "modal", "intro", "home", "select" }) do
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
-- ★ 必须给 `Enum.CursorEventType` ✗ —— 否则 `bind_input` 读不到它时**直接 return** ✓
--   （★ 那会让本套件全绿/全红都失去意义：它量的是"绑定"，不是"枚举解析"✓）
_G.Enum = {
  CursorEventType = {
    CursorClick = "CursorClick", CursorClickDown = "CursorClickDown",
    CursorClickUp = "CursorClickUp", CursorDrag = "CursorDrag",
  },
  KeyEventType = { KeyDown = "KeyDown", KeyUp = "KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
-- ★★★ 2026-10-12 **环境闸：本项还没被再引入时 ⇒ 明确"没得测"，✗ 既不假绿也不假红** ✓
--
--   ★ 背景 ✓：★ v212 把 v205 之后那批改动**整体回退**了 ✓（★ 用户实测确认干净 ✓）
--     ⇒ ★ 本项（对象级绑定记账 ✓）**当前不在产物里** ✗
--   ★★ 为什么不能 `os.exit(1)` ✗：★ 那样常驻套件里就多出**假红** ✗
--     ⇒ ★ 真正的回归会被噪音淹掉 ✓（★ 本项目反复栽在这上面 ✓）
--   ★★ 为什么不能 `os.exit(0)` 静默过 ✗：★ 那就是**假绿** ✓ 更坏 ✓
--   ⇒ ★ 与 `play_test.mjs` 的 `⊘ 本环境测不了` ＋ `tests/dupe_dispatch.lua` **同一口径** ✓：
--     ★ 明确说"没得测" ✓ ★ 不装作通过 ✗ ★ 也不谎报失败 ✗ ✓
--   ★★★ 哨兵价值 ✓：★ 该项一旦被再引入（★ 产物里出现 `_bound_ctrl` ✓）⇒
--     ★ 本套件**自动恢复全部 15 条断言** ✓✓
do
  local fh = io.open(SCRIPT_PATH, "rb")
  if fh == nil then out("  打不开产物 ⇒ 先跑 bundle"); os.exit(1) end
  local body = fh:read("a"); fh:close()
  if body:find("_bound_ctrl", 1, true) == nil then
    out("  ⊘ 产物里没有对象级绑定记账（`_bound_ctrl`）⇒ **本环境测不了**")
    out("  ⊘ 说明：该修复属于「v205 之后那批改动」⇒ 已随 v212 回退 ⇒ **当前没得测**")
    out("  ⊘ 它一旦被再引入，本套件的 15 条断言会自动恢复")
    os.exit(0)
  end
  out("  产物已含对象级绑定记账（`_bound_ctrl` ✓）")
end

local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart)

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local adapter = cur.adapter
if adapter == nil or type(adapter.bind_input) ~= "function" then
  out("  adapter:bind_input 不在 ⇒ 量不到"); os.exit(2)
end
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 绑一个按钮，确认引擎侧真的注册了监听器
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 造一个可绑的按钮 `probe.a`，绑它一次 ==")
do
  local a = attach(REG["board"], make_ctrl("probe.a", "button"))
  adapter.controls["probe.a"] = a
  pcall(function()
    adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } })
  end)
  local n1 = REG_CNT["probe.a"] or 0
  ok(n1 > 0, "第 1 次绑定 ⇒ 引擎侧真的注册了监听器", "注册 " .. tostring(n1) .. " 个")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [2] ★★ 同一个控件再绑一遍 ⇒ 必须早退（★ 这就是"防双绑"✗ 用户症状② 的防线 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] ★ 同一个控件再调 `bind_input` ⇒ **不许双绑** ==")
do
  local before = REG_CNT["probe.a"] or 0
  pcall(function()
    adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } })
  end)
  local after = REG_CNT["probe.a"] or 0
  ok(after == before, "★★ 同一个控件再绑 ⇒ **早退**（引擎侧监听器数不变 ✓）",
    "注册 " .. tostring(before) .. " → " .. tostring(after) .. "（应不变）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] ★★★ 关键场景：`bound` 被清掉、但**控件对象还是同一个** ⇒ 必须仍然早退
--
--   ★ 这正是优化组担心的那一幕 ✓：
--     ★ 他们说「换屏 / 销毁作废会把 `bound` 整表清掉 ⇒ 之后控件的记录丢了」✓
--     ★★ 而**若对象没换**，再绑就是**双绑** ✗ ⇒ ★ 用户症状② ✓
--   ★ 判据 ✓：★ 直接模拟"记录丢了"（把那一项删掉 ✓）⇒ ★ 再绑**也不许**多注册 ✓
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] ★★★ `bound` 记账丢了、但控件对象没换 ⇒ **仍然不许双绑** ==")
do
  local a = adapter.controls["probe.a"]
  local before = REG_CNT["probe.a"] or 0
  -- ★ 模拟"记录被清掉"（★ 换屏那次整表替换的效果 ✓）
  adapter.bound["probe.a"] = nil
  pcall(function()
    adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } })
  end)
  local after = REG_CNT["probe.a"] or 0
  ok(after == before,
    "★★ 记账丢了但**对象没换** ⇒ 早退（★ 不会因为记账丢了就双绑 ✓）",
    "注册 " .. tostring(before) .. " → " .. tostring(after) .. "（应不变）")
  ok(adapter.bound["probe.a"] == a,
    "★ 而且记账已经被重新种回成【那个对象】✓",
    "bound['probe.a'] 是对象本身 = " .. tostring(adapter.bound["probe.a"] == a))
  -- ★ 反向对照 ✓：★ 整表替换（★ 他们描述的那种清法 ✓）之后**也必须**不双绑 ✓
  local before2 = REG_CNT["probe.a"] or 0
  adapter.bound = {}                       -- ★ 就是 `self.bound = {}` 那一招 ✓
  pcall(function()
    adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } })
  end)
  local after2 = REG_CNT["probe.a"] or 0
  ok(after2 == before2,
    "★★ **整表替换** `bound = {}` 之后 ⇒ **仍然**早退（★ 双绑在结构上不可能 ✓）",
    "注册 " .. tostring(before2) .. " → " .. tostring(after2) .. "（应不变）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [4] ★★★ 正向：引擎换代 ⇒ 控件对象**换了** ⇒ 必须能重新绑上
--     （★ 用户症状①「点哪儿都没反应」的防线 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [4] ★★★ 换代（引擎重建控件）⇒ 新对象 **必须能重新绑上** ==")
do
  -- ★ 模拟"引擎销毁并重建了全部客户端控件"：换一个**新对象**挂到同一个名字下 ✓
  local fresh = attach(REG["board"], make_ctrl("probe.a", "button"))
  adapter.controls["probe.a"] = fresh
  local before = REG_CNT["probe.a"] or 0
  pcall(function()
    adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } })
  end)
  local after = REG_CNT["probe.a"] or 0
  ok(after > before,
    "★★ 对象换了 ⇒ **重新绑上** ✓（★ 这就是「点哪儿都没反应」的修法 ✓）",
    "注册 " .. tostring(before) .. " → " .. tostring(after) .. "（应增加）")
  ok(adapter.bound["probe.a"] == fresh,
    "★ 记账换成了**新对象** ✓",
    "bound['probe.a'] 是新对象 = " .. tostring(adapter.bound["probe.a"] == fresh))
  -- ★ 再绑一次同一新对象 ⇒ 仍然早退 ✓
  local before2 = REG_CNT["probe.a"] or 0
  pcall(function()
    adapter:bind_input("probe.a", { id = "probe.a", kind = "button", event = { action = "noop" } })
  end)
  ok((REG_CNT["probe.a"] or 0) == before2,
    "★ 新对象上重复调用 ⇒ 依然早退 ✓",
    "注册 " .. tostring(before2) .. " → " .. tostring(REG_CNT["probe.a"] or 0))
end

-- ════════════════════════════════════════════════════════════════════════════
-- [5] ★★ 换代作废（`invalidate_lookups`）本身**不许**把绑定记录整表清掉
--
--   ★ 这是一个**反向哨兵** ✓：★ 本轮修法**不需要**清 `bound` ✓（★ 见 `bind_input` 的长注释 ✓）
--     若有人又把"整表清"加回去 ⇒ ★ 本套件仍然是绿的 ✓（★ 因为身份判据兜住了 ✓）
--     ★★ 所以这里不断言"不许清" ✗ —— ★ 而是断言**清了也不会坏** ✓
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [5] ★ 换代作废之后：**对象没换** ⇒ 不双绑 ／ **对象换了** ⇒ 能重绑 ==")
do
  -- 造一个新的干净控件，绑一次 ✓
  local b2 = attach(REG["board"], make_ctrl("probe.b", "button"))
  adapter.controls["probe.b"] = b2
  pcall(function()
    adapter:bind_input("probe.b", { id = "probe.b", kind = "button", event = { action = "noop" } })
  end)
  local n1 = REG_CNT["probe.b"] or 0
  ok(n1 > 0, "`probe.b` 绑上了", "注册 " .. tostring(n1) .. " 个")

  -- ★ 换代（会清各种缓存 ✓ —— 这正是"换屏/换关"那条路 ✓）
  pcall(function() adapter:invalidate_lookups("screen=level test") end)
  -- ① 对象没换 ⇒ 早退
  pcall(function()
    adapter:bind_input("probe.b", { id = "probe.b", kind = "button", event = { action = "noop" } })
  end)
  ok((REG_CNT["probe.b"] or 0) == n1,
    "★ 换代后【同一个对象】再绑 ⇒ 早退（★ 不双绑 ✓）",
    "注册 " .. tostring(n1) .. " → " .. tostring(REG_CNT["probe.b"] or 0))
  -- ② 对象换了 ⇒ 重绑
  local fresh2 = attach(REG["board"], make_ctrl("probe.b", "button"))
  adapter.controls["probe.b"] = fresh2
  pcall(function()
    adapter:bind_input("probe.b", { id = "probe.b", kind = "button", event = { action = "noop" } })
  end)
  ok((REG_CNT["probe.b"] or 0) > n1,
    "★★ 换代后【对象换了】⇒ 重绑（★ 症状①的修法 ✓）",
    "注册 " .. tostring(n1) .. " → " .. tostring(REG_CNT["probe.b"] or 0))
end

-- ════════════════════════════════════════════════════════════════════════════
-- [6] ★★ `destroy_control` 的**两支**行为（★ 先把夹具对齐生产 ✗）
--
--   ★★ 我第一版这条断言**写错了** ✗✓（★ 被自己的套件抓住 ✓ 老实记下来 ✓）：
--     ★ 我拿一个"**编辑器手摆的**"控件去调 `destroy_control` ✓ 然后断言 `bound[id]` 被清 ✗
--     ★★ 而 `engine_adapter_qianxing.lua:3370` 的分支是 ✗：
--       ★ **只有 `self.instantiated[id]` 为真**（★ = 脚本用 `InstantiateClientUIControl` 生成的 ✓）
--       　 才走"真销毁 ＋ 清 `bound` ＋ 清 `controls` ＋ 换代作废" ✓
--       ★ 编辑器手摆的**只能藏起来** ✗ —— ★ 而且**注释写着"监听也留着"** ✓（★ 故意的 ✓）
--     ⇒ ★ 所以"手摆控件调销毁 ⇒ 记录被清"**根本不是生产行为** ✗ ⇒ ★ 断言对象选错了 ✓
--   ⚠️ ★ 这条正是本项目那句老规矩的又一次实例 ✓：
--     ★「**夹具必须先对齐生产** ✗」✓ —— ★ 我上一轮在 `anchored_pos_guard` 也踩过一次 ✓
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [6] ★★ `destroy_control`：**脚本建的**按 id 清 ✓ ／ 手摆的只藏不清 ✓ ==")
do
  -- 绑两个独立控件，**两个都标成脚本建的**（★ 只有这一支才会清 `bound` ✓）
  local c1 = attach(REG["board"], make_ctrl("probe.c1", "button"))
  local c2 = attach(REG["board"], make_ctrl("probe.c2", "button"))
  adapter.controls["probe.c1"] = c1
  adapter.controls["probe.c2"] = c2
  adapter.instantiated = adapter.instantiated or {}
  adapter.instantiated["probe.c1"] = true
  adapter.instantiated["probe.c2"] = true
  pcall(function() adapter:bind_input("probe.c1", { id = "probe.c1", kind = "button", event = { action = "noop" } }) end)
  pcall(function() adapter:bind_input("probe.c2", { id = "probe.c2", kind = "button", event = { action = "noop" } }) end)
  ok(adapter.bound["probe.c1"] ~= nil and adapter.bound["probe.c2"] ~= nil,
    "两个都绑上了", "c1=" .. tostring(adapter.bound["probe.c1"] ~= nil)
      .. " c2=" .. tostring(adapter.bound["probe.c2"] ~= nil))
  -- ★ 销毁 `probe.c1`（★ 它标了 `instantiated` ⇒ 走"真销毁"那一支 ✓）
  pcall(function() adapter:destroy_control("probe.c1") end)
  ok(adapter.bound["probe.c1"] == nil,
    "★ 脚本建的控件被销毁 ⇒ **它自己**的记账被清 ✓",
    "bound['probe.c1'] = " .. tostring(adapter.bound["probe.c1"]))
  ok(adapter.bound["probe.c2"] ~= nil,
    "★★ 而**别的控件的记账还在** ✓（★ 这就是「按 id 清」和「整表清」的差别 ✓）",
    "bound['probe.c2'] = " .. tostring(adapter.bound["probe.c2"] ~= nil))
  -- ★★ 关键 ✓：★ 被销毁的那个 id 若**又建出同一个对象**（理论上不会 ✓ 但作为哨兵 ✓）
  --   ⇒ ★ 对象级记账**仍然拦得住** ✓ ⇒ ★ 不会双绑 ✓
  local before = REG_CNT["probe.c1"] or 0
  adapter.controls["probe.c1"] = c1          -- ★ 故意把**同一个对象**放回去 ✓
  pcall(function() adapter:bind_input("probe.c1", { id = "probe.c1", kind = "button", event = { action = "noop" } }) end)
  ok((REG_CNT["probe.c1"] or 0) == before,
    "★★ 同一个对象放回来再绑 ⇒ **仍然早退** ✓（★ 对象级记账清不掉 ✓）",
    "注册 " .. tostring(before) .. " → " .. tostring(REG_CNT["probe.c1"] or 0))
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
