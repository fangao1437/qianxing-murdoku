--[[----------------------------------------------------------------------------
  tests/_wip/probe_event_table.lua —— **只读探针**：适配层的「事件表」是不是按**规划节点**记的。

  它要回答的问题（一句话）：
    `action.back` 在计划里是**两个不同的按钮**（`topbar` 的「返回菜单」= `back_confirm`、
    `right` 的「返回列表」= `back`）—— 两个事件**能不能同时存在**，还是**后写的把先写的吃掉**？

  做法（全程走**真实通路**，不另造键）：
    ① `build_layout()` 取计划 ⇒ 按 `parent` 找出那两个 `action.back` 节点，
       读出**它们各自的** `event.action`（这是"正确答案"，不是探针自己编的）；
    ② 让渲染循环照常跑（`Controller:render` ⇒ `Controller:_set_prop` ⇒ `Adapter:set_property`
       的 `key == "event"` 分支）—— 两个节点**各自**驱动一次；
    ③ **只读**事件表，逐条摊开：键 → action，并从键里解出 parent；
    ④ 断言：两份都在 ✓、各自指向**自己**的 action ✓、各自的 parent 对得上 ✓。

  改前 / 改后对照（这就是"探针有方向"的证据）：
    · 改前（事件表按控件 id）：表里只有 **1** 条，是**最后**驱动的那个节点（`right`/`back`）
      ⇒ 「只有最后一份赢」复现 ✓
    · 改后（事件表按规划节点 node_key）：表里 **2** 条，`topbar`→`back_confirm`、
      `right`→`back` ⇒ 两份都在且各归各 ✓

  ★★★★★ 2026-10-05 **B2（用户拍板 ✓）：派发从"最后写的赢"改成"认领该控件的那个节点赢"。**
    本探针量的是"**派发值**"（`bind_input` 里 `live_event()` 现查的那一份）：

      · 改前（派发 = `event_latest[id]` = **最后**写的节点）：
        渲染顺序是 `topbar` 先写 `back_confirm`、`right` 后写 `back`
        ⇒ 派发 = `back`（≠ 左上 ↰ 图标的 `back_confirm`）✗
      · 改后（派发 = `event_claim[id]` = **第一个**写的节点 = 认领者）：
        ⇒ 派发 = **`back_confirm`** ✓ —— 与左上 ↰ 图标（`ui_controller.lua:1389`）**一致**，
          都走 `ui_controller.lua:854` 的"先弹 ✓/✗"（`self.pending = { action = "back" }`）。

    ⚠️ 对照怎么跑：本探针支持 `lua tests/_wip/probe_event_table.lua <另一份产物路径>`，
       拿"改前"的产物再跑一遍，**同一条断言就会红**（`实际 action=back`）—— 那就是对照。

  ⚠️ 本文件**只读**：不改计划、不改布局、不写产品源码；只驱动已有的渲染通路并读结果。
  ⚠️ 它在 `_wip/` ⇒ **不算回归防线**（规矩见同目录 README.md）；结论要人工确认。

  跑法：lua tests/_wip/probe_event_table.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/probe_event_table.lua"
local root = here:gsub("tests[/\\]_wip[/\\]probe_event_table%.lua$", "")
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

-- ── 假控件树（与 tests/prop_ledger.lua 同一套约定）─────────────────────────
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

local tree, back_ctrl
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
  attach(rt, make_ctrl("topbar"))
  attach(rt, make_ctrl("right"))
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

-- ── 记录"两个节点各自被驱动过 event"（只记账，不改行为）──────────────────
local drives = {}
do
  local osp = adapter.set_property
  adapter.set_property = function(self, id, key, value, nkey)
    if id == "action.back" and key == "event" then
      drives[#drives + 1] = {
        action = value and value.action or nil,
        nkey = nkey,
      }
    end
    return osp(self, id, key, value, nkey)
  end
end

-- ── 事件表读取（只读）────────────────────────────────────────────────────
-- 改后：`adapter.events[key]`，键 = ui_controller 的 `node_key` = `id \1 父容器 \1 序号`；
-- 改前：`adapter.handlers[id].event`，键 = 控件 id。
-- 探针**优先读新的**，读不到才退回旧的 —— 这样同一份探针能在改前/改后各跑一次做对照。
local SEP = "\1"
local function snapshot_events(id)
  local rows = {}
  local pre = id .. SEP
  if type(adapter.events) == "table" then
    for k, v in pairs(adapter.events) do
      if type(k) == "string" and k:sub(1, #pre) == pre then
        rows[#rows + 1] = { key = k, ev = v }
      end
    end
  end
  if #rows > 0 then
    table.sort(rows, function(a, b) return a.key < b.key end)
    return rows, "adapter.events（按规划节点 node_key）"
  end
  local h = adapter.handlers and adapter.handlers[id] or nil
  if type(h) == "table" and h.event ~= nil then
    rows[1] = { key = id, ev = h.event }
    return rows, "adapter.handlers（按控件 id）"
  end
  return rows, "（空表）"
end

-- 从 node_key 里解出**父容器**（键格式：`id \1 父容器 \1 同(id,父容器)的第几次出现`）
local function key_parent(k)
  local _, _, parent = k:find("^[^" .. SEP .. "]*" .. SEP .. "([^" .. SEP .. "]*)")
  return parent
end

-- ── 派发值读取（**版本无关的读法**，用来做改前/改后对照）──────────────────────
-- 改后（B2）：`adapter.event_claim[id]` = **认领**这颗控件的规划节点 = **第一个**写的那个；
-- 改前      ：`adapter.event_latest[id]` = **最后**写的那个。
-- ⇒ 先读新的；没有 `event_claim`（老的产物）才退回 `event_latest`。
--   两个字段在**改后的产物里都存在**（`event_latest` 降级成纯诊断），所以"退回"只会发生在
--   拿**老产物**跑本探针的时候 —— 那正是对照要跑的那一次 ✓。
local function dispatch_read(id)
  local k, src = nil, "（没有可读的派发记录：既无 event_claim 也无 event_latest）"
  if type(adapter.event_claim) == "table" then
    k = adapter.event_claim[id]
    if k ~= nil then src = "event_claim（认领者 = 第一个写的 ✓ B2 规则）" end
  end
  if k == nil and type(adapter.event_latest) == "table" then
    k = adapter.event_latest[id]
    if k ~= nil then src = "event_latest（最后写的 ✗ 改前规则 / 改后仅作诊断）" end
  end
  local ev = (k ~= nil) and (adapter.events or {})[k] or nil
  return ev and ev.action or nil, k, src
end

-- ── 进关（先让渲染把账本/事件表建起来）──────────────────────────────────────
-- ⚠️ 账本是"变了才发"的：**第一次**渲染（在 OnStart 里，早于本探针）已经把两个节点的
--    event 发完并记了账，之后再跑多少帧都不会重发 ⇒ 直接量会量到 0 次。
--    ⇒ 这里把账本清空一次（= 回到「刚进关」那一刻的语义），下一次 render 就必然把
--      两个节点的 event **各发一遍**。这一步只动账本，不动计划、不动布局、不动源码。
out("\n== 1. 进关 ==")
ctrl.screen = nil
ctrl.dirty = true
pcall(function() for _ = 1, 5 do OnUpdate(1 / 60) end end)

-- ── 2. 计划里那两个 action.back 节点（按 parent 区分）───────────────────────
out("\n== 2. 计划（build_layout）里的 action.back ==")
local plan = {}
do
  local nodes = ctrl:build_layout()
  for i = 1, #nodes do
    local n = nodes[i]
    if n.id == "action.back" then
      plan[#plan + 1] = {
        parent = n.parent,
        action = n.event and n.event.action or nil,
        rect = n.rect,
      }
    end
  end
  table.sort(plan, function(a, b) return tostring(a.parent) < tostring(b.parent) end)
  out("  计划里 action.back 共 " .. tostring(#plan) .. " 个节点：")
  for i = 1, #plan do
    local p = plan[i]
    out(string.format("    · parent=%-8s action=%-14s rect=(%g,%g %gx%g)",
      tostring(p.parent), tostring(p.action),
      p.rect and p.rect.x or -1, p.rect and p.rect.y or -1,
      p.rect and p.rect.w or -1, p.rect and p.rect.h or -1))
  end
end

do
  local by_parent = {}
  for i = 1, #plan do by_parent[tostring(plan[i].parent)] = plan[i] end
  ok(#plan == 2,
    "★ 布局没动：计划里仍然是**两个** action.back 节点",
    "实测 " .. tostring(#plan) .. " 个")
  ok(by_parent["topbar"] ~= nil and by_parent["right"] ~= nil,
    "★ 两个节点分别挂 topbar / right（用户的设计，一个字没改）",
    "topbar=" .. tostring(by_parent["topbar"] and by_parent["topbar"].action)
      .. "  right=" .. tostring(by_parent["right"] and by_parent["right"].action))
  ok(by_parent["topbar"] and by_parent["topbar"].action == "back_confirm"
     and by_parent["right"] and by_parent["right"].action == "back",
    "★ 两个节点的 event **本来就是不同的**（这就是「必须两份都在」的理由）",
    "topbar=" .. tostring(by_parent["topbar"] and by_parent["topbar"].action)
      .. " / right=" .. tostring(by_parent["right"] and by_parent["right"].action))
end

-- ── 节点键 & "定点驱动某一个节点"的小工具 ───────────────────────────────────
--   键 = ui_controller 的 `node_key` = `id \1 父容器 \1 同(id,父容器)的第几次出现`
--   （探针**按同一条规则自己算一遍**，不读产品内部变量；这样"驱动的是哪个节点"是明确的）
local key_of_parent = {}
do
  local nodes = ctrl:build_layout()
  local seq = {}
  for i = 1, #nodes do
    local n = nodes[i]
    local base = tostring(n.id) .. SEP .. tostring(n.parent)
    seq[base] = (seq[base] or 0) + 1
    if n.id == "action.back" then
      key_of_parent[n.parent] = base .. SEP .. tostring(seq[base])
    end
  end
end
local function drive(parent, action)
  local key = key_of_parent[parent]
  -- ★ 走渲染**真正走的那条路**：`Controller:_set_prop` ⇒ `Adapter:set_property`（带 nkey）
  pcall(function() ctrl:_set_prop(adapter, "action.back", "event", { action = action }, key) end)
end

-- ── 3. 两个节点各自驱动过一次 event（走 _set_prop ⇒ set_property 的真实通路）──
out("\n== 3. 驱动（Controller:render ⇒ _set_prop ⇒ Adapter:set_property）==")
ctrl._props = {}          -- 清账本 = 回到「刚进关」⇒ 这一次 render 必然两个节点各发一遍
drives = {}
ctrl.dirty = true
pcall(function() ctrl:render(adapter, true) end)
do
  out("  event 分支被驱动 " .. tostring(#drives) .. " 次：")
  local driven = {}
  for i = 1, #drives do
    out("    · 第" .. i .. "次  action=" .. tostring(drives[i].action)
      .. "   node_key=" .. (drives[i].nkey ~= nil and "有" or "无（按控件 id）"))
    driven[tostring(drives[i].action)] = true
  end
  local n_driven = 0
  for _ in pairs(driven) do n_driven = n_driven + 1 end
  ok(driven["back_confirm"] and driven["back"],
    "★ **两个节点各自**把 event 驱动过一次（back_confirm 与 back 都发过）",
    "驱动到的不同 action：" .. tostring(n_driven) .. " 种")
end

-- ── 3b. ★★★ B2 的核心：派发 = **认领者**（第一个写 event 的节点），不是"最后写的" ──
--
--   这一节用的是**真实通路**刚跑出来的结果（上一节 `ctrl:render(adapter, true)`）：
--     `build_layout()` 里 `topbar` 节点先写 `back_confirm`、`right` 节点后写 `back`
--   ⇒ 认领者 = `topbar`（先写）⇒ 派发必须是 `back_confirm`。
--   改前：`event_latest` = `right` ⇒ 派发 `back`（**本节的第 2 条断言当场变红** = 对照 ✓）。
out("\n== 3b. 派发值（B2：认领者赢 / 改前：最后写的赢）==")
do
  local a, k, src = dispatch_read("action.back")
  out("  派发读法：" .. tostring(src))
  out("  认领的节点键：" .. tostring(k):gsub(SEP, " \\1 "))
  out("  派发 action = " .. tostring(a))
  ok(k ~= nil and key_parent(k) == "topbar",
    "★★★ B2：认领这颗控件的是 **topbar** 那个节点（**第一个**给它写 event 的）",
    "认领键的 parent=" .. tostring(k ~= nil and key_parent(k) or "nil"))
  ok(a == "back_confirm",
    "★★★ B2：**派发 back_confirm** ⇒ 与左上 ↰ 图标一致（先弹 ✓/✗）"
    .. "（改前 = 最后写的 `right` = back ⇒ 鼠标点它直接跳列表）",
    "实际 action=" .. tostring(a) .. "（改前实测会是 back ✗）")
  -- `event_latest` **仍然存在**，但已降级成纯诊断：它记的仍是"最后写的那个"（`right`）。
  -- 这条断言专门钉住"两个字段各司其职"：派发不读它、但仍能查"谁后写过"。
  local last = (type(adapter.event_latest) == "table") and adapter.event_latest["action.back"] or nil
  ok(last ~= nil and key_parent(last) == "right" and last ~= k,
    "★ `event_latest` **保留**、仍记\"最后写的那个\"（`right`）—— 但它**已不是派发依据**（纯诊断）",
    "event_latest 的 parent=" .. tostring(last ~= nil and key_parent(last) or "nil")
      .. "；认领者的 parent=" .. tostring(k ~= nil and key_parent(k) or "nil"))
end

-- ── 3c. ★ 任意顺序 / 重复写入 N 次 ⇒ **认领者不变**（"只认第一次"的判据）──────
out("\n== 3c. 重复 & 乱序写入（认领者不许换人）==")
do
  local before = adapter.event_claim and adapter.event_claim["action.back"] or nil
  -- 先让"最后写的"落在**非认领者**身上：这样"派发跟着认领者"和"派发跟着最后写的"
  -- 才会给出**不同**的答案（否则两种规则在这一步看不出区别）。
  drive("right", "B_LAST")
  local a1, k1 = dispatch_read("action.back")
  out("  最后写的是 `right`（B_LAST）⇒ 派发 = " .. tostring(a1)
    .. "（读法=" .. tostring(k1 and key_parent(k1)) .. "）")
  ok(a1 ~= "B_LAST" and a1 ~= "back",
    "★★ 最后写的是**非认领者**（`right`/B_LAST）⇒ 派发**不跟着最后写的走**（B2 的判据）",
    "实际 action=" .. tostring(a1) .. "（改前会是 B_LAST ✗）")

  -- 乱序 + 重复：右、左交替写 7 轮（共 14 次）
  for i = 1, 7 do
    drive("right", "B_LOOP" .. tostring(i))
    drive("topbar", "A_LOOP" .. tostring(i))
  end
  drive("right", "B_LOOP_TAIL")     -- ★ 收尾**故意**用非认领者写最后一次
  local after = adapter.event_claim and adapter.event_claim["action.back"] or nil
  ok(before ~= nil and after == before,
    "★★★ 又写了 15 次（两种顺序都有）⇒ **认领者一个字节都没变**（只认第一次 ✓）",
    "before=" .. tostring(before):gsub(SEP, " \\1 ")
      .. "；after=" .. tostring(after):gsub(SEP, " \\1 "))
  local a2, k2 = dispatch_read("action.back")
  ok(k2 == before and a2 == "A_LOOP7",
    "★★ 认领者不变 ⇒ 派发跟着**认领者那一格的最新值**走（`topbar` = A_LOOP7），不跟着 B_LOOP_TAIL",
    "实际 action=" .. tostring(a2) .. "（认领者那格 = A_LOOP7；非认领者最后写的是 B_LOOP_TAIL）")

  -- 收尾：把两个槽**恢复成计划值**（清账本 + 再渲染一次 = 回到"刚进关"的语义）。
  --   ⚠️ 必须恢复：上面那些 `drive` 是**绕过账本**直接写适配层的，而账本仍记着"计划值已下发"
  --      ⇒ 不恢复的话，后面几节读到的是探针自己写进去的 A_LOOP7/B_LOOP_TAIL（假状态 ✗）。
  ctrl._props = {}
  ctrl.dirty = true
  pcall(function() ctrl:render(adapter, true) end)
  local a3, k3 = dispatch_read("action.back")
  ok(a3 == "back_confirm" and k3 == before,
    "★★ 恢复计划值后：**同一个认领者**、派发又回到 `back_confirm`（认领关系没被那些写入搞乱）",
    "实际 action=" .. tostring(a3) .. "；认领者 parent="
      .. tostring(k3 ~= nil and key_parent(k3) or "nil"))
end

-- ── 4. 只读事件表 ─────────────────────────────────────────────────────────
out("\n== 4. 事件表（只读）==")
local rows, how = snapshot_events("action.back")
out("  读法：" .. how)
out("  表里 action.back 的条目：" .. tostring(#rows) .. " 条")
for i = 1, #rows do
  local r = rows[i]
  out("    · key=" .. tostring(r.key):gsub(SEP, " \\1 ")
    .. "   parent=" .. tostring(key_parent(r.key))
    .. "   action=" .. tostring(r.ev and r.ev.action))
end

do
  local by_parent = {}
  for i = 1, #rows do by_parent[tostring(key_parent(rows[i].key))] = rows[i].ev end
  ok(#rows >= 2,
    "★★ **两份事件都在**（不是只有最后一份赢）",
    "实测 " .. tostring(#rows) .. " 条")
  ok(by_parent["topbar"] ~= nil and by_parent["topbar"].action == "back_confirm",
    "★★ topbar 那一份**指向自己的 action**（back_confirm）",
    "实际 " .. tostring(by_parent["topbar"] and by_parent["topbar"].action))
  ok(by_parent["right"] ~= nil and by_parent["right"].action == "back",
    "★★ right 那一份**指向自己的 action**（back）",
    "实际 " .. tostring(by_parent["right"] and by_parent["right"].action))
  ok(by_parent["topbar"] and by_parent["right"]
     and by_parent["topbar"].action ~= by_parent["right"].action,
    "★ 两份**确实是不同的**事件（同 id 但不同规划节点 ⇒ 不再互相覆盖）",
    "topbar=" .. tostring(by_parent["topbar"] and by_parent["topbar"].action)
      .. " / right=" .. tostring(by_parent["right"] and by_parent["right"].action))
end

-- ── 5. 稳态：再多跑一段，两份都还在（不是只在那一帧侥幸存在）────────────────
out("\n== 5. 稳态 60 帧后再看一次 ==")
drives = {}
pcall(function() for _ = 1, 60 do OnUpdate(1 / 60) end end)
local rows2, how2 = snapshot_events("action.back")
out("  读法：" .. how2 .. "；条目 " .. tostring(#rows2) .. " 条；"
  .. "稳态里 event 又被驱动 " .. tostring(#drives) .. " 次")
local bp2 = {}
for i = 1, #rows2 do bp2[tostring(key_parent(rows2[i].key))] = rows2[i].ev end
ok(bp2["topbar"] ~= nil and bp2["topbar"].action == "back_confirm"
   and bp2["right"] ~= nil and bp2["right"].action == "back",
  "★★ 稳态里两份**依然各自在位**（没有被下一帧的另一个节点改写）",
  "topbar=" .. tostring(bp2["topbar"] and bp2["topbar"].action)
    .. " / right=" .. tostring(bp2["right"] and bp2["right"].action))
-- ★ B2：稳态再跑 60 帧之后，**派发**也必须还是认领者那一份（不是"只在那一帧侥幸对"）。
do
  local a4, k4, src4 = dispatch_read("action.back")
  out("  稳态派发读法：" .. tostring(src4) .. "；派发 action = " .. tostring(a4))
  ok(a4 == "back_confirm" and k4 ~= nil and key_parent(k4) == "topbar",
    "★★★ 稳态 60 帧后**派发仍是 `back_confirm`**（认领者 = `topbar`，不随时间/帧序漂移）",
    "实际 action=" .. tostring(a4) .. "；认领者 parent="
      .. tostring(k4 ~= nil and key_parent(k4) or "nil"))
end

-- ── 6. 不许有运行时报错（口径与 tests/prop_ledger.lua 一致）────────────────
out("\n== 6. 全程没有运行时报错 ==")
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
