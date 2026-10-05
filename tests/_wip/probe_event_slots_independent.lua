--[[----------------------------------------------------------------------------
  tests/_wip/probe_event_slots_independent.lua —— **独立复核探针**（只读）

  复核对象：`lua/engine_adapter_qianxing.lua` 的**事件表**
    · 改前：`set_property(id, "event", v)` 直接写 `handlers[id].event` ——
      `build_layout` 里两个同 id 的规划节点（`action.back`：一个挂 `topbar`、一个挂 `right`）
      **共用一格** ⇒ 后写的把先写的静默吃掉（"只有最后一份赢"）。
    · 改后：事件按**规划节点的键**（`id \1 父容器 \1 序号`，与属性账本同一把键）各占一格。

  为什么这份探针要和作者那份分开写（`probe_event_table.lua`）：
    同一份结论被**另一条独立读法**复现才算数。所以这里：
      · 不走作者写的任何辅助函数，只调**渲染真正走的那条路**（`Controller:_set_prop`）
        和**适配层的公开入口**（`set_property`）；
      · 读法写成"新版键优先、老版控件级兜底"的**版本无关**解析器
        ⇒ 同一份探针直接跑"改前产物"和"改后产物"，对照就出来了；
      · 另加两条作者那份没量的东西：
          ① 每颗同名控件**各挂了几条光标监听**（"两个按钮各自有绑定"到底绑在哪颗上）；
          ② 真点一下 `topbar` 那颗 ⇒ 实际派发的 action 是什么。

  ★★★★★ 2026-10-05 **B2（用户拍板 ✓）：派发 = "认领该控件的那个节点"（第一个写的），
  不再是"最后写的那个"。** 本探针另加两条独立判据：
    · **真按钮点一下**（点 `bind_input` 注册的 click 回调 ⇒ `live_event()` 现查）
      ⇒ 改前派发 `back`（直接跳列表 ✗）、改后派发 **`back_confirm`**（先弹 ✓/✗ ✓）；
    · 派发是否跟着**认领者那一格**走（而不是跟着最后一次写入）—— 让"最后写的"落在
      **非认领者**（`right`）身上，两种规则给出的答案就会**不同**，一眼能分。

  跑法（在工程根目录）：
    lua tests/_wip/probe_event_slots_independent.lua                       # 对 dist/client_script.lua
    lua tests/_wip/probe_event_slots_independent.lua <另一份产物路径>       # 改前/改后对照
----------------------------------------------------------------------------]]--]]

local here = (arg and arg[0]) or "tests/_wip/probe_event_slots_independent.lua"
local root = here:gsub("tests[/\\]_wip[/\\]probe_event_slots_independent%.lua$", "")
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

-- ── 假控件树（与 tests/prop_ledger.lua 同一套约定）──────────────────────────
--
-- ★ 关键差别：`action.back` 在这里**有两颗**，分别挂在 `topbar` 与 `right` 下 ——
--   这正是规划里那两个节点各自声明的父容器（真机存档里只有 `topbar` 那颗，
--   这里两颗都摆出来，是为了看出"第二条规划节点会不会去抢第一颗的绑定"）。
local C = { listeners = {}, clicks = 0 }
local function attach(parent, c)
  if parent == nil then return nil end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end
local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true, __kids = {}, __on = {} }
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
  -- ★ 把监听**按事件类型**记下来：这样"哪颗控件挂了几条"是可数的。
  c.AddCursorEventListener = function(_, evt_type, cb)
    c.__on[#c.__on + 1] = { type = evt_type, cb = cb }
    C.listeners[name] = (C.listeners[name] or 0) + 1
  end
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

local tree, back_topbar, back_right, topbar_ctrl, right_ctrl
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
  -- ★ 两颗同名控件：**先 topbar 后 right**（深度优先 ⇒ `find("action.back")` 命中 topbar 那颗）
  back_topbar = attach(topbar_ctrl, make_ctrl("action.back"))
  back_topbar.kind = "button"
  attach(back_topbar, make_text("action.back.label"))
  back_right = attach(right_ctrl, make_ctrl("action.back"))
  back_right.kind = "button"
  attach(back_right, make_text("action.back.label"))
  tree = { rt }
end

_G.Enum = {
  CursorEventType = {
    CursorClick = "CursorClick", CursorDown = "CursorDown",
    CursorUp = "CursorUp", CursorDrag = "CursorDrag",
  },
}
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

-- ── 加载产物 ──────────────────────────────────────────────────────────────
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then
  out("  加载失败：" .. tostring(lerr)); os.exit(1)
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

-- 抓"真实派发了什么事件"：包一层 on_input（`_fire` 会把它转给界面层）
local fired = {}
do
  local orig = adapter.on_input
  adapter.on_input = function(evt)
    fired[#fired + 1] = evt and evt.action or nil
    if orig then orig(evt) end
  end
end

-- ── 1. 计划层：两个节点、两个不同事件 ──────────────────────────────────────
out("\n== 1. 计划（build_layout）里的 action.back ==")
local nodes, key_of_parent = nil, {}
do
  local okb, ns = pcall(function() return ctrl:build_layout() end)
  if not okb then out("  build_layout 抛错：" .. tostring(ns)); os.exit(1) end
  nodes = ns
  local seq = {}
  local list = {}
  for i = 1, #nodes do
    local n = nodes[i]
    local base = tostring(n.id) .. "\1" .. tostring(n.parent)
    seq[base] = (seq[base] or 0) + 1
    if n.id == "action.back" then
      key_of_parent[n.parent] = base .. "\1" .. tostring(seq[base])
      list[#list + 1] = n
    end
  end
  for i = 1, #list do
    out(string.format("    · parent=%-7s action=%-13s rect=(%g,%g %gx%g)  node_key=%s",
      tostring(list[i].parent), tostring(list[i].event and list[i].event.action),
      list[i].rect.x, list[i].rect.y, list[i].rect.w, list[i].rect.h,
      tostring(key_of_parent[list[i].parent]):gsub("\1", " | ")))
  end
  ok(#list == 2, "★ 布局没动：计划里仍然是**两个** action.back 节点",
    "实测 " .. tostring(#list) .. " 个")
  local a = list[1] and list[1].event and list[1].event.action
  local b = list[2] and list[2].event and list[2].event.action
  ok(a ~= b, "★ 两个节点的 event 本来就不一样（这正是「必须两份都在」的理由）",
    tostring(a) .. " vs " .. tostring(b))
end

-- ── 事件读法（**版本无关**）：新版按规划节点键，老版只有控件级一份 ──────────
local function read_slots()
  local res, src = {}, "?"
  -- 新版：规划节点键 -> 事件表（作者那份叫 `events`；本探针也认 `node_events` 这个名字）
  local tbl = adapter.events or adapter.node_events
  if type(tbl) == "table" then
    for parent, key in pairs(key_of_parent) do
      local v = tbl[key]
      if type(v) == "table" then
        res[parent] = v.action
        src = "按规划节点键（" .. tostring(tbl == adapter.events and "adapter.events" or "adapter.node_events") .. "）"
      end
    end
  end
  if next(res) == nil then
    -- 老版：控件级一格 —— 两个规划节点共用它
    local h = adapter.handlers and adapter.handlers["action.back"]
    local v = h and h.event
    if type(v) == "table" then
      for parent in pairs(key_of_parent) do res[parent] = v.action end
      src = "控件级一格（adapter.handlers[id].event）"
    end
  end
  return res, src
end

local function show_slots(tag)
  local res, src = read_slots()
  out("    " .. tag .. "  读法=" .. src .. "  条目=" .. tostring((function()
    local n = 0 for _ in pairs(res) do n = n + 1 end return n end)()))
  for _, parent in ipairs({ "topbar", "right" }) do
    out(string.format("        · parent=%-7s action=%s", parent, tostring(res[parent])))
  end
  return res, src
end

-- ── 派发值读取（**版本无关**）：改后 = `event_claim`（认领者 = 第一个写的）；改前 = `event_latest` ──
local function key_parent(k)
  local _, _, parent = tostring(k):find("^[^" .. "\1" .. "]*" .. "\1" .. "([^" .. "\1" .. "]*)")
  return parent
end
local function dispatch_read()
  local k, src = nil, "（没有可读的派发记录）"
  if type(adapter.event_claim) == "table" then
    k = adapter.event_claim["action.back"]
    if k ~= nil then src = "event_claim（认领者 = 第一个写的 ✓ B2）" end
  end
  if k == nil and type(adapter.event_latest) == "table" then
    k = adapter.event_latest["action.back"]
    if k ~= nil then src = "event_latest（最后写的 ✗ 改前规则）" end
  end
  local ev = (k ~= nil) and (adapter.events or {})[k] or nil
  return ev and ev.action or nil, k, src
end
-- 点一下"真机上真有的那一颗"（= `find` 命中的那颗 = 挂上了监听的那颗）
local function click_topbar_back()
  local before = #fired
  if #back_topbar.__on > 0 and back_topbar.__on[1] ~= nil then
    pcall(function() back_topbar.__on[1].cb({ GetUIPos = function() return 0, 0 end }) end)
  end
  local got = {}
  for i = before + 1, #fired do got[#got + 1] = tostring(fired[i]) end
  return got[1], got
end

-- ── 2. 真实渲染路径：OnUpdate 跑几帧，两个节点各自下发一次 ──────────────────
out("\n== 2. 真实渲染路径（OnUpdate × 5，两个节点各自下发 event）==")
ctrl.screen = nil
ctrl.dirty = true
pcall(function() for _ = 1, 5 do OnUpdate(1 / 60) end end)
local slots_after_render = show_slots("渲染之后：")

-- ── 2b. ★★★ B2 核心：**真按钮点一下**派发的是哪一份？─────────────────────────
--   为什么要在这里点：本探针的假树里 `action.back` 摆了两颗裸控件（看"监听挂在哪颗"），
--   但**绑定只发生在 `find` 命中的那颗**（真机上一个 id 只有一颗控件 ⇒ 等价于"只有一条监听"）。
--   点它 = 真机上玩家点那颗 `action.back`。
--   `live_event()` 是在**点击那一刻**现查的 ⇒ 它读到什么，玩家就得到什么。
out("\n== 2b. 真按钮点一下（点 bind_input 注册的 click 回调）==")
do
  local a, got = click_topbar_back()
  out("  点了 `action.back` ⇒ 派发 action = " .. tostring(a or "（没有派发）"))
  out("  点击后控制器状态：pending.action = "
    .. tostring(ctrl.pending and ctrl.pending.action or "nil")
    .. "；screen = " .. tostring(ctrl.screen))
  ok(a == "back_confirm",
    "★★★ B2：真按钮点一下 ⇒ 派发 **back_confirm**"
    .. "（改前 = 最后写的 `right` = back ⇒ 鼠标点它直接跳列表 ✗）",
    "实际派发=" .. tostring(a) .. "（改前实测是 back ✗）")
  ok(ctrl.pending ~= nil and ctrl.pending.action == "back",
    "★★★ 并且据此进**先弹 ✓/✗**：`ui_controller.lua:855` 把 pending 设成 { action = \"back\" }"
    .. " ⇒ 与左上 ↰ 图标（`hex.back` = back_confirm）走同一条路",
    "pending.action=" .. tostring(ctrl.pending and ctrl.pending.action or "nil"))
  -- 反向对照：`back` 那条路是"直接跳列表"（`ui_controller.lua:1043-1047`：screen = "select"）。
  --   所以"派发 back 还是 back_confirm"**不是措辞差别**，是两种完全不同的行为。
  local a0, k0, src0 = dispatch_read()
  out("  派发读法：" .. tostring(src0) .. "；认领的节点键 parent="
    .. tostring(k0 ~= nil and key_parent(k0) or "nil"))
  ok(a0 == "back_confirm" and k0 ~= nil and key_parent(k0) == "topbar",
    "★★★ 派发记录 = **认领者**（`topbar` 那个节点）⇒ 与上面「点一下」的结果一致（同一个来源）",
    "action=" .. tostring(a0) .. "；认领者 parent=" .. tostring(k0 ~= nil and key_parent(k0) or "nil"))
end

-- ── 3. 分别驱动（隔离）：A → B → A，看两份会不会互相覆盖 ────────────────────
out("\n== 3. 分别驱动两个节点的事件设置（A=topbar → B=right → A 再来一次）==")
local KEY_A, KEY_B = key_of_parent["topbar"], key_of_parent["right"]
local function drive(parent, action)
  local key = key_of_parent[parent]
  -- 走渲染真正走的那条路（老版 `_set_prop` 只有 4 个参数，多传一个也无害）
  pcall(function() ctrl:_set_prop(adapter, "action.back", "event", { action = action }, key) end)
end
drive("topbar", "A_ONLY")
local s1 = show_slots("驱动 A（topbar=A_ONLY）之后：")
drive("right", "B_ONLY")
local s2 = show_slots("再驱动 B（right=B_ONLY）之后：")
drive("topbar", "A_AGAIN")
local s3 = show_slots("再驱动 A（topbar=A_AGAIN）之后：")

ok(s2["topbar"] == "A_ONLY", "★ 驱动 B 之后，A 那一份**没有被覆盖**（按节点分槽的判据）",
  "topbar=" .. tostring(s2["topbar"]) .. "（改前会是 B_ONLY = 只有最后一份赢）")
ok(s3["right"] == "B_ONLY", "★ 回头再驱动 A，B 那一份**也没有被覆盖**",
  "right=" .. tostring(s3["right"]) .. "（改前会是 A_AGAIN）")
ok(s3["topbar"] == "A_AGAIN" and s3["right"] == "B_ONLY",
  "★ **两份事件同时都在**，且各自指向自己的动作",
  "topbar=" .. tostring(s3["topbar"]) .. " / right=" .. tostring(s3["right"]))

-- ── 3b. ★★★ B2：让"最后写的"落在**非认领者**身上 ⇒ 派发跟着谁一目了然 ─────────
out("\n== 3b. 最后写的是非认领者（right）⇒ 派发跟谁走 ==")
do
  local claim_before = adapter.event_claim and adapter.event_claim["action.back"] or nil
  drive("right", "B_FINAL")            -- 最后写的 = `right`（非认领者）
  local a_fin, k_fin, src_fin = dispatch_read()
  out("  派发读法：" .. tostring(src_fin))
  out("  最后写的是 `right`（B_FINAL）⇒ 派发 = " .. tostring(a_fin)
    .. "（认领者 parent=" .. tostring(k_fin ~= nil and key_parent(k_fin) or "nil") .. "）")
  ok(a_fin == "A_AGAIN" and k_fin == KEY_A,
    "★★★ B2：**派发跟着认领者那一格**（`topbar` = A_AGAIN），**不跟最后写的那个**（`right` = B_FINAL）",
    "实际 dispatch=" .. tostring(a_fin) .. "（改前会派发 B_FINAL ✗）")

  -- 乱序 + 重复：右、左交替写 5 轮（共 10 次）⇒ 认领者不许换人
  for i = 1, 5 do
    drive("right", "B_R" .. tostring(i))
    drive("topbar", "A_R" .. tostring(i))
  end
  local claim_after = adapter.event_claim and adapter.event_claim["action.back"] or nil
  ok(claim_before ~= nil and claim_after == claim_before,
    "★★★ 乱序/重复写 10 次 ⇒ **认领者一个字节都没变**（只认第一次 ✓）",
    "before=" .. tostring(claim_before):gsub("\1", " | ")
      .. "；after=" .. tostring(claim_after):gsub("\1", " | "))
  local a3, k3 = dispatch_read()
  ok(k3 == claim_before and a3 == "A_R5",
    "★★ 认领者不变 ⇒ 派发 = 认领者那一格的**当前值**（A_R5），不是非认领者最后写的 B_R5",
    "实际 action=" .. tostring(a3) .. "（认领者格=A_R5 / right 最后写=B_R5）")
end

-- ── 4. 监听挂在哪颗控件上 + 再点一下看派发谁 ────────────────────────────────
out("\n== 4. 监听与派发（两颗同名控件各挂了几条、点 topbar 那颗派发什么）==")
do
  local lt = C.listeners["action.back"] or 0
  -- 监听是按控件对象记的：统计时直接数每颗控件自己的 `__on`
  local n_top = #back_topbar.__on
  local n_right = #back_right.__on
  out("    topbar 那颗控件上的光标监听条数 = " .. tostring(n_top))
  out("    right  那颗控件上的光标监听条数 = " .. tostring(n_right))
  out("    （登记总数 " .. tostring(lt) .. "；每次 bind_input 会挂 click/down/up/drag 若干条）")
  -- ★ 这一条是**预期行为**、不是缺陷：`create_control` 按 **id** 建控件 ⇒ 一个 id 一颗控件、
  --   一次绑定 ⇒ 真机上**只有一颗** `action.back`、**只有一条**（组）监听。
  --   本探针摆两颗裸控件只是为了"看得出绑定落在哪一颗"。
  ok(n_top > 0 and n_right == 0,
    "★ 绑定只落在 `find` 命中的那一颗上：另一颗 **0 条监听**"
    .. "（真机上一个 id 只有一颗控件 ⇒ 等价于「只有一条监听」）",
    "topbar=" .. tostring(n_top) .. " 条 / right=" .. tostring(n_right) .. " 条")

  local a4, got = click_topbar_back()
  out("    点 topbar 那颗 ⇒ 派发 action = " .. (next(got) and table.concat(got, ",") or "（没有派发）"))
  -- 派发 = **认领者那一格的当前值**（不写死具体值：这一节前面已经驱动过好几轮）
  local claim_key = adapter.event_claim and adapter.event_claim["action.back"] or nil
  local expect = nil
  if claim_key ~= nil and type(adapter.events) == "table" and adapter.events[claim_key] ~= nil then
    expect = adapter.events[claim_key].action
  end
  ok(a4 ~= nil and expect ~= nil and a4 == expect,
    "★★ 再点一次 ⇒ 派发 = **认领者那一格的当前值**（同一个来源，不会漂到别的节点）",
    "实际=" .. tostring(a4) .. "；认领者那一格=" .. tostring(expect)
      .. "（认领者 parent=" .. tostring(claim_key ~= nil and key_parent(claim_key) or "nil") .. "）")

  local before2 = #fired
  if n_right > 0 and back_right.__on[1] ~= nil then
    pcall(function()
      back_right.__on[1].cb({ GetUIPos = function() return 0, 0 end })
    end)
  end
  local got2 = {}
  for i = before2 + 1, #fired do got2[#got2 + 1] = tostring(fired[i]) end
  out("    点 right  那颗 ⇒ 派发 action = " .. (next(got2) and table.concat(got2, ",") or "（没有派发：它压根没绑上 ✗ 预期 ✓）"))
end

-- ── 5. 没有运行时报错 ─────────────────────────────────────────────────────
out("\n== 5. 全程没有运行时报错 ==")
do
  -- ⚠️ 只认**运行时报错**（attempt to / bad argument / nil value）。
  --    假树里 `content` 没有 `disableCursorEventPassthrough` 字段，适配层会走
  --    `printerr` 报一句"请在编辑器里勾选…" —— 那是**预存在的环境提示**，
  --    不是这一轮引入的错，所以单独计数、不算失败。
  local bad, notes = 0, 0
  for i = 1, #logs do
    local t = logs[i].text
    if t:find("attempt to ", 1, true) or t:find("bad argument", 1, true)
      or t:find("nil value", 1, true) then
      bad = bad + 1
      if bad <= 5 then out("    !! " .. t:sub(1, 160)) end
    elseif logs[i].level == "error" then
      notes = notes + 1
    end
  end
  ok(bad == 0, "没有运行时报错（attempt to / bad argument / nil value）",
    "(" .. bad .. " 条；另有 " .. notes .. " 条 printerr 级的**环境提示**，不计)")
end

out(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
