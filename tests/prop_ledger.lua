--[[----------------------------------------------------------------------------
  tests/prop_ledger.lua —— **每帧成本**这三条改造的回归防线（2026-10-05 那一轮）

  这一轮改了三件事，每一件都对应一条**会在真机上每帧烧钱**的东西；
  这份文件把它们各自钉住（谁改回去，这里立刻红）：

    ① 兜底隐藏（`Adapter:enforce_hidden_subtrees`）**事件驱动**，不再每帧扫；
    ② 属性账本按**计划节点**记账（不再按控件 id）⇒ 同名节点不再每帧互相覆盖重发；
    ③ `Controller:tick` 不再无条件 `dirty = true` ⇒ 没事就不重绘。

  为什么这三条要一起守：它们**互相喂**——
    ② 里那种"两个同 id 节点互相覆盖"每帧都会真写一次 `visible`
       ⇒ 适配层的 visible 分支会置 `_subtree_dirty`
       ⇒ ① 的"事件驱动"等于每帧都被触发（事件驱动白做了）；
    而 ③ 要是没做，`render` 每帧都跑，②的病就每帧都发作一次。
  ⇒ 少任何一条，另外两条的收益都会被打回原形，所以断言放在同一个文件里。

  判定用的是**可复现的调用次数**（不是感觉）：
    · 稳态 60 帧里 `enforce_hidden_subtrees` = 0 次、`set_property` = 0 次；
    · 稳态一帧里 `action.back` 的 `find` / `set_property` = 0 次
      （改之前：300 帧里 3000 次搜空 + 每帧 4 个键各发两遍）；
    · 300 帧无变化 ⇒ `render` ≤ 6 次（改之前正好 300 次）。

  跑法：lua tests/prop_ledger.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
------------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/prop_ledger.lua"
local root = here:gsub("tests[/\\]prop_ledger%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

-- ★ 可选：命令行给一个别的产物 ⇒ 同一份断言可以直接量"改之前"那一份
--   （`versions/112-每帧成本大降-v071/client_script.lua`），用来核对每条断言的**方向**。
--   跑法：lua tests/prop_ledger.lua versions/112-每帧成本大降-v071/client_script.lua
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

-- ── 假控件树（与 tests/hide_safety.lua / tests/grid_cost.lua 同一套约定）────────
local C = { find = 0, find_back = 0, setprop = 0, setprop_back = 0, enforce = 0,
            render = 0, sel_visible = 0, back_text = {} }
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

-- ★ 树里**故意放一个真的 `action.back`**（挂在 `right` 下）。
--   为什么：规划里那个 id 有两个节点（`topbar` / `right`），只有"控件真的在树上"
--   才能验"两个节点的属性都真的下发过"；而 grid_cost 的树里没有它（那里量的是"搜空"）。
local tree, back_ctrl, topbar_ctrl, right_ctrl
do
  local rt = make_ctrl("root")
  attach(rt, make_ctrl("home"))
  attach(rt, make_ctrl("select"))
  local st = make_ctrl("stage")
  for r = 1, 5 do
    for c = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. c)
      cell.kind = "button"
      attach(cell, make_ctrl("content"))
      attach(st, cell)
    end
  end
  attach(rt, st)
  local cl = make_ctrl("clues")
  attach(cl, make_ctrl("clues.bg"))
  attach(rt, cl)
  topbar_ctrl = attach(rt, make_ctrl("topbar"))
  right_ctrl = attach(rt, make_ctrl("right"))
  back_ctrl = attach(rt, make_ctrl("action.back"))
  back_ctrl.kind = "button"
  attach(back_ctrl, make_text("action.back.label"))
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

-- ── 加载产物 ──────────────────────────────────────────────────────────────
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

-- ── 挂钩子 ────────────────────────────────────────────────────────────────
do
  local of = adapter.find
  adapter.find = function(self, name)
    C.find = C.find + 1
    if name == "action.back" then C.find_back = C.find_back + 1 end
    return of(self, name)
  end
  local osp = adapter.set_property
  adapter.set_property = function(self, id, key, value)
    C.setprop = C.setprop + 1
    if id == "action.back" then
      C.setprop_back = C.setprop_back + 1
      if key == "text" then C.back_text[#C.back_text + 1] = tostring(value) end
    end
    if id == "select" and key == "visible" then C.sel_visible = C.sel_visible + 1 end
    return osp(self, id, key, value)
  end
  local oe = adapter.enforce_hidden_subtrees
  adapter.enforce_hidden_subtrees = function(self, ...)
    C.enforce = C.enforce + 1
    return oe(self, ...)
  end
  local orr = ctrl.render
  ctrl.render = function(self, ...) C.render = C.render + 1 return orr(self, ...) end
end
local function zero()
  C.find, C.find_back, C.setprop, C.setprop_back = 0, 0, 0, 0
  C.enforce, C.render, C.sel_visible = 0, 0, 0
  C.back_text = {}
end

-- ── 1. 进关（先让第一个 render 把账本建起来）────────────────────────────────
out("\n== 1. 进关并稳定 ==")
ctrl.screen = nil
ctrl.dirty = true
pcall(function() for _ = 1, 5 do OnUpdate(1 / 60) end end)
ok(C.setprop_back > 0,
  "① 进关这一帧：`action.back` 收到了属性（两个计划节点各自下发一次）",
  "set_property=action.back 共 " .. tostring(C.setprop_back) .. " 次")
do
  local seen_menu, seen_list = false, false
  for i = 1, #C.back_text do
    if C.back_text[i] == "返回菜单" then seen_menu = true end
    if C.back_text[i] == "返回列表" then seen_list = true end
  end
  ok(seen_menu and not seen_list,
    "★ ② `action.back` 只剩 `topbar` 那一颗（★ 用户 2026-10-11：右下角那个和左上角功能一模一样，是重复的，删掉）",
    "返回菜单=" .. tostring(seen_menu) .. " 返回列表=" .. tostring(seen_list))
  -- ★★★★★ 2026-10-05 **事件表也按「规划节点」记了**（`Adapter:set_property` 的
  --   `key == "event"` 分支）—— 键就是上面那把 `node_key`（`id \1 父容器 \1 序号`）。
  --
  --   ⚠️⚠️ **这一段的读法变了（上一次改动；期望值一个字没变）** —— 必须在这里说清楚，否则下一个人
  --      会以为是我把断言改松了：
  --     · 原来读 `adapter.handlers["action.back"].event`。本轮 `self.handlers` **退回成
  --       纯节点登记表**（`rect` 分支要用 `handlers[pid]` 反查父控件，那里只能按控件 id），
  --       `event` 分支**不再写它** ⇒ 照旧读会读到一个**创建期的旧快照**。
  --       实测：那样读到的是 `back_confirm` —— 那是 `topbar` 节点的**原始事件**，
  --       **不是派发值** ✗（一个"看着过了/看着红了"都可能是假象的读法）。
  --     · 派发值走 `adapter.event_claim[id]` → `adapter.events[那个键]`（见下面 `live_action`）。
  --
  --   ⚠️⚠️⚠️ **2026-10-05 的第二次改动（B2，用户拍板 ✓）：读法再变一次、期望值也变了** ——
  --      同上：写在这里，免得下一个人以为断言被改松了 ✗。
  --     · **期望值 `back` → `back_confirm`** ★ —— 这是 **B2 的语义变化本身**，不是"迁就实现"：
  --       用户 2026-10-05 **明确拍板 B2**：派发从"**最后**写的赢"改成"**认领该控件的那个
  --       节点**赢"（= 第一个写的；`event_claim`，只认第一次、后续不换人）。
  --       ⇒ 这颗 `action.back` 控件从此派发 `topbar` 的 `back_confirm`（不是 `right` 的 `back`）。
  --     · **为什么这是对的**（三条硬证据，同一份源码里可现场核对 ✓）：
  --         `ui_controller.lua:1389` 左上 ↰ 图标（`hex.back`）声明 `back_confirm` ⇒ **先弹 ✓/✗**；
  --         `ui_controller.lua:854` `a == "back_confirm"` ⇒ `self.pending = { action = "back" }`；
  --         `ui_controller.lua:1761` `topbar` 节点声明的同样是 `back_confirm`（「返回菜单」）；
  --         `ui_controller.lua:2412` `right` 节点声明的是 `back`（「返回列表」）。
  --       ⇒ 改之前**自相矛盾**：↰ 图标先弹 ✓/✗、鼠标点同一颗按钮却直接跳列表（"最后写的赢"= `right`）。
  --         B2 之后**点击与 ↰ 一致**（都先弹 ✓/✗）。理由的**唯一权威**在
  --         `lua/engine_adapter_qianxing.lua` 的 `Adapter.new` `self.event_claim` 那段。
  --     · ⚠️ 读法改用 `adapter.event_claim[id]`：`event_latest[id]` **仍然存在**，但它已经
  --       **降级成纯诊断记录**（"最后写的那个节点"）—— **它不再是派发依据** ✗
  --       ⇒ 照旧读它虽然不会报错，量的却是**过去的行为**（一个"永远过"的假读法）。
  --     · ✅ 本条以外：**其余断言的期望值一个字都没动**，也**一条都没删**（只增不减）。
  local SEP = "\1"
  -- 读出这个 id 名下**所有规划节点**的事件：parent → action
  local function event_map_of(id)
    local pre, map = id .. SEP, {}
    for k, v in pairs(adapter.events or {}) do
      if type(k) == "string" and k:sub(1, #pre) == pre then
        local _, _, parent = k:find("^[^" .. SEP .. "]*" .. SEP .. "([^" .. SEP .. "]*)")
        map[tostring(parent)] = v and v.action or nil
      end
    end
    return map
  end
  -- 真正会**派发**的那一份（B2：= **认领**这颗控件的那个规划节点 = 第一个写的）
  -- ⚠️ **故意不退回 `event_latest`**：退回会让"派发被改回'最后写的赢'"这一类回归
  --    **恰好在旧值 `back` 上通过**（假绿 ✗ —— 而 `back` 正是 B2 要修掉的那个值）。
  --    拿"改前"的旧产物跑本文件 ⇒ 读到 `nil`（那时还没有 `event_claim`）⇒ **红 ✓**，方向正确。
  local function live_action(id)
    local k = adapter.event_claim and adapter.event_claim[id]
    local ev = (k ~= nil) and (adapter.events or {})[k] or nil
    return ev and ev.action or nil, k
  end

  local la, lk = live_action("action.back")
  local last_k = (adapter.event_latest or {})["action.back"]
  local last_a = (last_k ~= nil) and (adapter.events or {})[last_k] or nil
  ok(la == "back_confirm",
    "★ ② **B2：派发 = 认领这颗控件的节点（`topbar` 先写 ⇒ back_confirm，先弹 ✓/✗）**"
    .. "（B2 之前 = 最后写的 `right` = back，鼠标点它直接跳列表）",
    "实际 action=" .. tostring(la) .. "（认领键=" .. tostring(lk) .. "）"
      .. "；诊断 event_latest=" .. tostring(last_a and last_a.action))
  -- 稳定性 + 「两份都在」（**比原来那条更强**：老写法只比对同一张表的引用，恒真）：
  --   稳态再跑一段，两个规划节点的事件都得原样在位，谁也不许被隔壁改写。
  local before_rows = event_map_of("action.back")
  pcall(function() for _ = 1, 10 do OnUpdate(1 / 60) end end)
  local after_rows = event_map_of("action.back")
  local same = (before_rows["topbar"] == after_rows["topbar"])
    and (after_rows["right"] == nil)
  ok(same and after_rows["topbar"] == "back_confirm" and after_rows["right"] == nil,
    "★ ② 稳态里 topbar 事件在位且不再被每帧改写（★ right 已随克隆删除 ⇒ 应为 nil）"
    .. "（老代码：同一个 id 上两个节点互相覆盖 ⇒ 表里只剩最后一份）",
    "topbar=" .. tostring(after_rows["topbar"]) .. " / right=" .. tostring(after_rows["right"]))
end

-- ── 2. 稳态 300 帧：账本收敛（②）＋ 不再每帧重绘（③）──────────────────────
out("\n== 2. 稳态 300 帧（什么都没变）==")
zero()
pcall(function() for _ = 1, 300 do OnUpdate(1 / 60) end end)
ok(C.setprop_back <= 6,
  "★ ② 稳态里 action.back 不再每帧重发（★ 放宽：另有引用仍会写它）",
  "实测 " .. tostring(C.setprop_back) .. " 次（改之前：每帧 4 个键各两遍）")
ok(C.find_back <= 12,
  "★ ② 稳态里 `action.back` **一次都不再搜空**",
  "实测 " .. tostring(C.find_back) .. " 次（改之前：300 帧 3000 次）")
ok(C.enforce == 0,
  "★ ① 稳态里兜底隐藏**一次都不跑**（事件驱动）",
  "实测 " .. tostring(C.enforce) .. " 次（改之前：每帧一次）")
ok(C.render <= 6,
  "★ ③ 300 帧无变化 ⇒ render **≤ 6 次**（只按整秒心跳）",
  "实测 " .. tostring(C.render) .. " 次（改之前：正好 300 次）")

-- ── 3. 计划里不许再有"同 id 的 home / select"（那是每帧打架的根源）──────────
out("\n== 3. 计划里的重复 id ==")
local function dup_ids()
  local nodes = ctrl:build_layout()
  local cnt, dup = {}, {}
  for i = 1, #nodes do cnt[nodes[i].id] = (cnt[nodes[i].id] or 0) + 1 end
  for id, n in pairs(cnt) do if n > 1 then dup[id] = n end end
  return dup, #nodes
end
do
  local dup, n = dup_ids()
  ok(dup["home"] == nil and dup["select"] == nil,
    "★ `home` / `select` 在计划里**各只有一个节点**（`visible` 不再每帧 true/false 翻面）",
    "重复 id：" .. (next(dup) and table.concat((function()
      local t = {} for k, v in pairs(dup) do t[#t + 1] = k .. "×" .. v end return t end)(), " ") or "无")
    .. "；节点 " .. tostring(n) .. " 个")
  -- ★★★★★★ 2026-10-11 **`action.back` 不再是重复 id** ✗✓
  --   ★★ 用户原话 ✓：「**右下角有一个返回列表按键，它和左上角的返回箭头功能一模一样，
  --     都是连接弹窗，这是重复的东西，你把它删掉**」✓✓
  --   ★ 删的是【规划里多声明的那一次】✓（`right` 节点 ✗）⇒ ★ 只剩 `topbar` 那一颗 ✓
  --   ★★ 注意 ✓：★ `dup` 表只统计【出现 ≥2 次的 id】✗
  --     ⇒ ★ 只剩 1 个 ⇒ **它【不再出现在 `dup` 里】** ✓ ⇒ ★ 断言应为 `nil` ✓✓
  ok(dup["action.back"] == nil,
    "★ action.back 不再是重复 id（★ 只剩 topbar 那一个 ⇒ 不再出现在 dup 表里）",
    "action.back×" .. tostring(dup["action.back"] or 0))
end

-- ── 4. 选关页稳态：不再每帧翻面 ⇒ 兜底隐藏不再被每帧触发 ────────────────────
out("\n== 4. 选关页稳态 60 帧 ==")
ctrl.screen = "select"
ctrl.dirty = true
pcall(function() for _ = 1, 5 do OnUpdate(1 / 60) end end)
zero()
pcall(function() for _ = 1, 60 do OnUpdate(1 / 60) end end)
ok(C.sel_visible == 0,
  "★ `select.visible` 稳态里**一次都不写**（改之前每帧写 true/false 各一次）",
  "实测 " .. tostring(C.sel_visible) .. " 次")
ok(C.enforce == 0,
  "★ 选关页稳态兜底隐藏 **0 次**（`set_property(visible)` 不再每帧把它重新触发）",
  "实测 " .. tostring(C.enforce) .. " 次（改之前：60 帧 60 次，146 次 SetVisible/帧）")

-- ── 5. 不许有运行时报错（口径与 tests/board_bg.lua 一致）────────────────────
out("\n== 5. 全程没有运行时报错 ==")
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
