--[[----------------------------------------------------------------------------
  tests/grid_cost.lua —— **量**「网格视窗」这条路上每次渲染到底发了多少次调用

  为什么要有这个文件（用户硬证据，2026-10-05）：
    同一台设备上对比两个包 ——
      · `191-位置交给编辑器.gil`（v058，**网格视窗之前**）：流畅 ✓
      · 当前（v069，**带网格视窗**）：明显流畅，但对**比之前还是略有卡顿** ✗
    ⇒ 回退是"网格视窗那一轮"引进来的（v067/v068 已经修掉两条补发热路、v069 又把
      上限收到 3，用户说还是卡 ⇒ 病根不在这两条）。
    ⇒ 在动代码之前**先量**：一次 `RefreshItems`（含引擎滚动重进）到底做了多少事？

  量什么（全部是"真机会真实发生"的调用，不是猜的）：
    · `Adapter:find` 的调用次数，以及其中**真的走了深度优先搜树**的次数
      （缓存命中不算 —— `find` 只缓存首次命中，见 engine_adapter_qianxing 的 find）
    · 假控件树里 `GetChildren` 被访问的**总节点数**（= 搜树成本的真身）
    · 列表项上的 `GetChild` 调用次数（`_grid_item_child` 试 4 种名字，实测命中第几种）
    · 适配层 `set_property` 的调用次数（写属性 = 真机上的 Unity 侧调用）
    · `Core:view()` 的调用次数（它每次都重建 25/49 个格子的视图表，很贵）
    · 网格视窗 `RefreshItems` 的调用次数、引擎**重进回调**的次数

  三个口径（分开报，别混在一起）：
    A. 稳态一帧（什么状态都没变，`dirty=false`）：`sync_clue_grid` + `render` 各做了什么
    B. 一次完整 `RefreshItems`（进关那一下，7 个可见列表项）
    C. 引擎**滚动重进**一次回调（如果它每帧重进，这就是**每帧**的账）

  跑法：lua tests/grid_cost.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua

  ★ 2026-10-05 追加的三个**只加不减**的计数（这一轮修 (3)(4) 两条要用）：
    · `setprop_fail`：`set_property` **返回 false**（= 适配层明确说"这次没送到"）的次数。
      改之前每个 cell 的 `text` 必然落进这里（模板没有 text 子控件），25 格 × 补发额度；
      改之后必须为 **0**（判定段最后一条断言就钉它）。
    · `find_names`：`find` **按名字**的直方图 —— 用来单独盯 `action.back` 这种
      "同一个 id 出现在两个规划节点上"的控件（`miss_names` 只记"搜空"的，收敛之后就看不见了）。
    · `fail_keys`：失败的 `<id>.<键>` 直方图（失败到底长什么样，一眼可查）。
    ⚠️ 这三个都是**新加的观测**，没有动、也没有放松任何一条原断言。

  ★ 可选：命令行给一个别的产物 ⇒ 同一份断言可以直接量"改之前"那一份
    （`versions/112-每帧成本大降-v071/client_script.lua`），用来核对每条断言的**方向**。
    跑法：lua tests/grid_cost.lua versions/112-每帧成本大降-v071/client_script.lua
    （与 `tests/prop_ledger.lua` 同一个约定）
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/grid_cost.lua"
local root = here:gsub("tests[/\\]grid_cost%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")

local out = print

-- 被测试代码的日志一律**收起来**（进关那一段会刷很多行，挡住我们要看的数字）；
-- 只在最后需要排查时把尾部摊出来。
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
local function dump_tail(n, title)
  out("  ---- " .. title .. "（最后 " .. tostring(n) .. " 行）----")
  local from = #logs - n + 1
  if from < 1 then from = 1 end
  for i = from, #logs do
    out("  " .. (logs[i].level == "error" and "[err] " or "[   ] ") .. logs[i].text)
  end
  out("  ---- 日志结束 ----")
end

-- ── 计数器 ────────────────────────────────────────────────────────────────
local C = {
  find = 0,         -- Adapter:find 被调用次数
  find_deep = 0,    -- 其中**真的搜了树**的次数（缓存没命中、且命中了）
  find_miss = 0,    -- 搜了树且没搜到（最贵的：整棵树走完）
  set_prop = 0,     -- Adapter:set_property 调用次数
  sub = 0,          -- Adapter:sub 调用次数
  view = 0,         -- Core:view() 调用次数
  getchildren = 0,  -- 假树里 GetChildren 被访问的节点次数（= 搜树成本）
  item_child = 0,   -- 列表项上的 GetChild 调用次数（_grid_item_child）
  item_child_hit1 = 0, -- 第 1 种名字就命中的次数
  item_child_tries = {}, -- 每种名字被试了几次
  miss_names = {},  -- 「搜了树但没搜到」的名字直方图（每帧白跑的就是它们）
  render = 0,       -- Controller:render 真正执行了几次
  setvis = 0,       -- SetVisible 总调用次数
  setvis_grid = 0,  -- 其中打在「网格视窗及其列表项」那一棵子树上的次数
  grid_refresh = 0, -- grid:RefreshItems 被调用次数
  cb = 0,           -- RefreshItems 回调被进入次数
  add_listener = 0, -- 列表项 AddCursorEventListener 调用次数
  text_write = 0,   -- 列表项文字写入次数
  -- ★ 2026-10-05 追加（只加不减，见文件头）：
  setprop_fail = 0, -- set_property 返回 **false**（适配层明确说"没送到"）的次数
  find_names = {},  -- find 的**按名字**直方图（盯 action.back 这种同名节点）
  setprop_names = {}, -- set_property 的**按 id**直方图（同上，看它到底重发了几笔）
  fail_keys = {},   -- 失败直方图：`<id>.<键>` → 次数
}
local function reset() for k, v in pairs(C) do
  if type(v) == "number" then C[k] = 0 elseif type(v) == "table" then C[k] = {} end
end end

-- ── 假控件 ────────────────────────────────────────────────────────────────
local GRID_SUBTREE = nil          -- 建好树之后指向 clues.grid（用来分辨"谁被 SetVisible"）
local function in_grid_subtree(c)
  local p, guard = c, 0
  while p ~= nil and guard < 8 do
    if p == GRID_SUBTREE then return true end
    p = p.__parent
    guard = guard + 1
  end
  return false
end

local function attach(parent, c)
  if parent == nil then return end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
end

local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true, __kids = {} }
  c.GetChildren = function() C.getchildren = C.getchildren + 1 return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v)
    c.visible = v
    C.setvis = C.setvis + 1
    if GRID_SUBTREE ~= nil and in_grid_subtree(c) then C.setvis_grid = C.setvis_grid + 1 end
  end
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

-- 文字控件：`text` 可写（列表项里的 who/what/letter 就是这种）
-- ★ `text` 字段的**每一次写入**都记账 —— 真机上那是 Unity 的文本重排，
--   内容没变还写 = 白花（"每帧重排文字"是 UI 卡顿最常见的来源）。
--   ⚠️ 计数器必须走 `__newindex` 且**表里不能先有 text 这个键** ——
--      Lua 的 `__newindex` 只在键**不存在**时触发，`rawset(t,"text",..)` 之后
--      再赋值就变成普通赋值、一次都记不到（第一版就踩了这个：数出来恒为 0）。
local function make_text(name)
  local c = make_ctrl(name)
  c.kind = "text"
  local store = { text = name }
  return setmetatable(c, {
    __index = function(_, k) if k == "text" then return store.text end return nil end,
    __newindex = function(t, k, v)
      if k == "text" then
        C.text_write = C.text_write + 1
        store.text = v
      else
        rawset(t, k, v)
      end
    end,
  })
end

-- ★ 列表项：名字按**真机存档**来 —— 模板 1073742421 的子控件叫 `clue.1.who` /
--   `clue.1.what` / `clue.1.letter`（用户是照着第 1 张卡另存的模板）。
--   ⇒ `_grid_item_child` 试的 4 种名字里，只有第 3 种 `clue.1.<后缀>` 能命中
--     （index 恰好 == 1 的第 2 项会第 1 种就命中）—— 这就是真机的形状，不是最坏假设。
local function make_item()
  local it = make_ctrl("clue")
  it.kind = "button"
  for _, sfx in ipairs({ "who", "what", "letter", "backrop1", "backrop2", "face" }) do
    attach(it, make_text("clue.1." .. sfx))
  end
  -- 列表项上的 GetChild **单独计数**（真机上它是引擎侧的子树查找，比 GetChildren 便宜，
  -- 但一次回调里几十下也是实打实的开销）
  local base_get = it.GetChild
  it.GetChild = function(self, key)
    if type(key) == "string" and key:sub(1, 5) == "clue." then
      C.item_child = C.item_child + 1
      local n = C.item_child
      -- 记"第几次试就命中"：名字是 clue.<num>.<后缀> 形状，逐个记
      C.item_child_tries[key] = (C.item_child_tries[key] or 0) + 1
      local hit = base_get(self, key)
      if hit ~= nil then C.item_child_hit1 = C.item_child_hit1 + 0 end
      return hit
    end
    return base_get(self, key)
  end
  it.AddCursorEventListener = function() C.add_listener = C.add_listener + 1 end
  return it
end

-- 网格视窗控件：按官方 API 实现（itemCount / itemPrefabIndex / RefreshItems / GetItemIndex）
local VISIBLE_ITEMS = 7
local function make_grid()
  local g = make_ctrl("clues.grid")
  g.kind = "grid"
  g.itemPrefabIndex = -1
  g.itemCount = 0
  g.scrollProgress = 0
  g.__items = {}
  g.__base = 0                     -- 官方/Unity 那套是 0 起（本项目要判的就是这个）
  g.RefreshItems = function(self, n, cb)
    C.grid_refresh = C.grid_refresh + 1
    self.__cb, self.__n = cb, n
    self.itemCount = n
    local vis = math.min(n, VISIBLE_ITEMS)
    for i = 1, vis do
      local item = self.__items[i]
      if item == nil then
        item = make_item()
        item.__index = self.__base + i - 1
        self.__items[i] = item
        attach(self, item)
      end
      C.cb = C.cb + 1
      cb(item, item.__index)        -- ★ 引擎传的是**运行时索引**（0 起）
    end
    return true
  end
  g.GetItemIndex = function(self, item) return item and item.__index or nil end
  return g
end

-- ── 假控件树：root → home / stage（49 格）/ clues（clues.bg + clues.grid + 老卡片）──
local canvas = { w = 1600.0, h = 900.0 }
local tree, home_ctrl, stage_ctrl, clues_ctrl, grid_ctrl, legacy_cards
do
  local rt = make_ctrl("root")
  local hm = make_ctrl("home")
  local st = make_ctrl("stage")
  for r = 1, 7 do
    for cc = 1, 7 do
      local cell = make_ctrl("cell." .. r .. "." .. cc)
      cell.kind = "button"
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))
      attach(content, make_ctrl("note"))
      attach(content, make_ctrl("x"))
      attach(cell, content)
      attach(st, cell)
    end
  end
  local cl = make_ctrl("clues")
  attach(cl, make_ctrl("clues.bg"))
  grid_ctrl = make_grid()
  attach(cl, grid_ctrl)
  -- 编辑器里遗留的老卡片（`hide_unlisted` 要把它们关掉；`find` 也会扫到它们）
  legacy_cards = {}
  for i = 1, 18 do
    local card = make_ctrl("clue." .. i)
    card.kind = "button"
    for _, sfx in ipairs({ "who", "what", "letter", "face", "backrop1" }) do
      attach(card, make_text("clue." .. i .. "." .. sfx))
    end
    attach(cl, card)
    legacy_cards[i] = card
  end
  attach(rt, hm)
  attach(rt, st)
  attach(rt, cl)
  tree = { rt }
  home_ctrl, stage_ctrl, clues_ctrl = hm, st, cl
  GRID_SUBTREE = grid_ctrl
end

_G.game = {
  GetUICanvasSize = function() return canvas.w, canvas.h end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"
    c.prefabIndex = prefab
    local content = make_ctrl("content")
    attach(content, make_ctrl("face"))
    attach(c, content)
    attach(parent, c)
    return c
  end,
  DestroyClientUIControl = function(c) end,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end,
  PrintClientUITree = function() end,
  ServerSignal = function()
    local s = {}
    s.AddInt = function() end; s.AddFloat = function() end
    s.AddString = function() end; s.AddBool = function() end
    s.SendSignal = function() end
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
-- ★ 故意**不给** Enum：与 tests/board_bg.lua 同一套环境（适配层全程 nil-safe 降级）。
--   代价：`_grid_bind_item_click` 会在 `enum_at` 那里提前返回 ⇒ 点击绑定不参与计数。
--   真机上 Enum 是有的，所以下面单独用 `PROBE_ENUM` 再量一次"挂了监听之后"的账。
_G.Enum = nil

-- ── 加载产物 ──────────────────────────────────────────────────────────────
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then
  out("  加载失败：" .. tostring(lerr) .. "　→ 先跑 `lua tools/bundle_client_script.lua`")
  os.exit(1)
end
local okrun, rerr = pcall(chunk)
if not okrun then out("  chunk 执行失败：" .. tostring(rerr)); os.exit(1) end

local ok1, err1 = pcall(OnInit)
local ok2, err2 = pcall(OnStart)
if not (ok1 and ok2) then
  out("  OnInit/OnStart 失败：" .. tostring(err1) .. " / " .. tostring(err2)); os.exit(1)
end

local dbg = _G.__murdoku_debug
local Murdoku = dbg.Murdoku
local cur = Murdoku.current()
local ctrl, adapter = cur.controller, cur.adapter

-- ── 挂钩子 ────────────────────────────────────────────────────────────────
local core = ctrl.core
do
  local of = adapter.find
  adapter.find = function(self, name)
    C.find = C.find + 1
    C.find_names[name] = (C.find_names[name] or 0) + 1
    local cached = self.controls[name]
    local r = of(self, name)
    if r == nil then
      C.find_miss = C.find_miss + 1
      C.miss_names[name] = (C.miss_names[name] or 0) + 1
    elseif cached == nil then C.find_deep = C.find_deep + 1 end
    return r
  end
  local osp = adapter.set_property
  adapter.set_property = function(self, id, k, v)
    C.set_prop = C.set_prop + 1
    local r = osp(self, id, k, v)
    -- ★ 只认**明确的 false**（适配层的契约：false = 这次没送到）；老适配器不返回值 ⇒ 不算失败
    --   （同一个约定见 ui_controller 的 `_set_prop`）。
    if r == false then
      C.setprop_fail = C.setprop_fail + 1
      local fk = tostring(id) .. "." .. tostring(k)
      C.fail_keys[fk] = (C.fail_keys[fk] or 0) + 1
    end
    return r
  end
  local osub = adapter.sub
  adapter.sub = function(self, a, b)
    C.sub = C.sub + 1
    return osub(self, a, b)
  end
  local ov = core.view
  core.view = function(self, ...) C.view = C.view + 1 return ov(self, ...) end
  local orend = ctrl.render
  ctrl.render = function(self, ...) C.render = C.render + 1 return orend(self, ...) end
end

-- 直方图 → "名字×次数 名字×次数"，按次数降序（通用的那个；`top_miss` 走它）
local function top_hist(hist, limit)
  local t = {}
  for name, n in pairs(hist) do t[#t + 1] = { name = name, n = n } end
  table.sort(t, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  local out_t = {}
  for i = 1, math.min(limit, #t) do out_t[i] = t[i].name .. "×" .. t[i].n end
  return table.concat(out_t, "  "), #t
end

-- 「搜空」直方图：打印前 N 名 —— 每帧白跑的到底是哪些名字
local function top_miss(limit) return top_hist(C.miss_names, limit) end

-- ★ 2026-10-05 追加：单独把某个名字的 `find` 次数取出来。
--   为什么不能只看 `miss_names`：账本按计划节点记账**修好之后**，`action.back` 就不再"搜空"了
--   ⇒ 它在 `miss_names` 里直接消失，**"0 次"和"没统计"分不开**。
--   要报 before/after 就必须看**全部 find**，所以这里是 `find_names`。
local function finds_of(name) return C.find_names[name] or 0 end

local n_clues = #((core:view() or {}).clues or {})
out(string.format("  关卡=%s  棋盘=%dx%d  线索=%d 条  cfg.use_grid=%s  prefab=%s",
  tostring((core.level or {}).id or "?"), core.rows, core.cols, n_clues,
  tostring(adapter.cfg.use_grid), tostring(adapter.cfg.clues_grid_prefab)))
out(string.format("  grid 控件：%s（列表项 %d 个可见）",
  tostring(grid_ctrl ~= nil), VISIBLE_ITEMS))

-- 让网格这条路真的接管（真机：关卡内 `controller.screen` 是 nil）
ctrl.screen = nil
ctrl.dirty = true
pcall(function() for _ = 1, 3 do OnUpdate(0.5) end end)

local state_line = string.format(
  "  网格状态 _grid_state=%s  索引基准=%s  控件找到=%s  回调共进入=%d 次",
  tostring(ctrl._grid_state), tostring(ctrl._grid_base),
  tostring(ctrl._grid ~= nil), C.cb)

-- ── 口径 A：稳态一帧 ──────────────────────────────────────────────────────
out("\n== A. 稳态一帧（什么都没变：dirty=false，只走「每秒一次」的那条重绘）==")
reset()
local view_before = C.view
ctrl.dirty = true
pcall(function() OnUpdate(0.5) end)      -- 这一帧会真的 render（dirty）
reset()
ctrl.dirty = false
pcall(function() OnUpdate(0.5) end)      -- 这一帧：sec 没变、dirty=false ⇒ **不 render**
out(string.format("  [A0] 不重绘的一帧：find=%d  set_property=%d  view=%d  GetChildren=%d",
  C.find, C.set_prop, C.view, C.getchildren))
reset()
pcall(function() Murdoku.render() end)   -- 真机每秒至少走一次的那条路
out(string.format("  [A1] 一次 render：find=%d（真搜树 %d / 搜空 %d）set_property=%d sub=%d "
  .. "view=%d  GetChildren=%d  grid_refresh=%d  cb=%d",
  C.find, C.find_deep, C.find_miss, C.set_prop, C.sub, C.view, C.getchildren,
  C.grid_refresh, C.cb))
-- ★ 2026-10-05：把 `action.back` **单独拎出来报**（同一个 id 有两个规划节点的那个控件）。
--   `uic` 那两行是 `uic_controller.lua` 里 `action.back` 的**两个**节点：
--     一个挂 `topbar`（L1759）、一个挂 `right`（L2384）。
--   账本按节点记账**修好之前**：两个节点每帧互相覆盖 ⇒ 每个键都"变了" ⇒ 每帧重发
--     ⇒ 稳态**一次 render** 就要为它白跑 `find` 若干次 + `set_property` 若干次。
out(string.format("      ★ action.back 单独账（稳态一次 render）：find=%d 次  set_property=%d 次",
  finds_of("action.back"), (function()
    local n = 0
    for k, v in pairs(C.fail_keys) do if k:sub(1, 11) == "action.back" then n = n + v end end
    return n
  end)()))
local A = { find = C.find, deep = C.find_deep, miss = C.find_miss, sp = C.set_prop,
            view = C.view, gc = C.getchildren, gr = C.grid_refresh, cb = C.cb,
            back_find = finds_of("action.back"), fail = C.setprop_fail }

-- ── 口径 B：一次**冷**RefreshItems（进关那一下，7 个可见列表项）────────────
out("\n== B. 一次冷 RefreshItems（进关那一下：句柄/文案都还没缓存）==")
ctrl._grid_sig = nil                      -- 骗过"条数没变就跳过"的守卫，强制重发一次
ctrl._grid_kids = nil                     -- 清掉记忆表 = 冷启动那一次
ctrl._grid_text = nil
reset()
pcall(function() ctrl:sync_clue_grid(adapter) end)
out(string.format("  [B] grid_refresh=%d  cb=%d（= 列表项个数）  item.GetChild=%d  文字写入=%d  "
  .. "view=%d（=1 次文案快照）  find=%d（真搜树 %d / 搜空 %d）  set_property=%d  GetChildren=%d",
  C.grid_refresh, C.cb, C.item_child, C.text_write, C.view, C.find, C.find_deep,
  C.find_miss, C.set_prop, C.getchildren))
local B = { gc_item = C.item_child, view = C.view, find = C.find, deep = C.find_deep,
            miss = C.find_miss, sp = C.set_prop, cb = C.cb, gr = C.grid_refresh,
            text = C.text_write }
-- 名字命中分布：第 1 / 2 / 3 种名字各命中几次（说明「4 种名字依次试」的真实代价）
out(string.format("      列表项 GetChild 尝试过的名字种类=%d 种，总调用=%d 次（平均每项 %.1f 次）",
  (function() local n = 0 for _ in pairs(C.item_child_tries) do n = n + 1 end return n end)(),
  C.item_child, C.cb > 0 and (C.item_child / C.cb) or 0))

-- ── 口径 C：引擎滚动重进一次回调（= 如果它每帧重进，这就是每帧的账）────────
local grid = ctrl._grid
-- 「引擎重进一次回调」= 官方「列表发生滚动时对列表项内容进行刷新」那句话的字面实现：
-- 对每个可见列表项，用**运行时索引**再进一次回调。
local function reenter(rounds)
  if grid == nil or grid.__cb == nil then return end
  ctrl._grid_in_refresh = false           -- 模拟"回调从引擎那边进来"（不是我们调的）
  for _ = 1, (rounds or 1) do
    for i = 1, VISIBLE_ITEMS do
      local item = grid.__items[i]
      if item ~= nil then
        C.cb = C.cb + 1
        grid.__cb(item, item.__index)
      end
    end
  end
end

out("\n== C. 引擎滚动重进一次回调（官方：「列表发生滚动时对列表项内容进行刷新」）==")
reset()
reenter(1)
out(string.format("  [C] 回调 %d 次：item.GetChild=%d  view=%d（★每条线索重建一次整视图！）  "
  .. "find=%d  set_property=%d  文字写入=%d  挂监听=%d",
  C.cb, C.item_child, C.view, C.find, C.set_prop, C.text_write, C.add_listener))
local Cc = { cb = C.cb, gc_item = C.item_child, view = C.view, find = C.find,
             sp = C.set_prop, text = C.text_write }

-- ── 口径 C2：**连续 5 次**重进 —— 看有没有"每次都重做"的东西 ──────────────
out("\n== C2. 连续 5 次重进（模拟「引擎每帧重进」）==")
reset()
reenter(5)
out(string.format("  [C2] 回调 %d 次：item.GetChild=%d  view=%d  文字写入=%d  挂监听=%d",
  C.cb, C.item_child, C.view, C.text_write, C.add_listener))
local C5 = { cb = C.cb, gc_item = C.item_child, view = C.view, text = C.text_write }

-- ── 口径 C3：点击监听会不会重复挂（Enum 打开后）───────────────────────────
out("\n== C3. 挂点击监听会不会重复（真机有 Enum；离线环境默认没有）==")
_G.Enum = { CursorEventType = { CursorClick = 1, CursorDown = 2, CursorUp = 3, CursorLongPress = 4 } }
reset()
reenter(5)
out(string.format("  [C3] 5 次重进（%d 个列表项 × 5）：AddCursorEventListener 共调用 %d 次"
  .. "（理想 = %d 次 = 每个列表项只挂一次）",
  VISIBLE_ITEMS, C.add_listener, VISIBLE_ITEMS))
local c3_listeners = C.add_listener
_G.Enum = nil

-- ── 口径 E：真机帧循环的**平均账**（300 帧 dt=1/60）─────────────────────
out("\n== E. 真机帧循环的平均账：300 帧 dt=1/60（网格视窗在跑）==")
reset()
local t0 = os.clock()
pcall(function() for _ = 1, 300 do OnUpdate(1 / 60) end end)
local t1 = os.clock()
out(string.format("  [E] 300 帧合计：render %d 次  find=%d（真搜树 %d / 搜空 %d）set_property=%d sub=%d "
  .. "view=%d  GetChildren=%d  文字写入=%d  回调=%d  CPU=%.1f ms",
  C.render, C.find, C.find_deep, C.find_miss, C.set_prop, C.sub, C.view, C.getchildren,
  C.text_write, C.cb, (t1 - t0) * 1000))
do
  local line, kinds = top_miss(12)
  out("      ★ 每帧白跑的「搜空」名字（前 12 名，共 " .. tostring(kinds) .. " 种）：")
  out("        " .. line)
end
local E = { find = C.find, sp = C.set_prop, view = C.view, gc = C.getchildren,
            miss = C.find_miss, render = C.render,
            text = C.text_write, cb = C.cb, cpu = (t1 - t0) * 1000 }

-- ── 口径 F：`Core:view()` 本身多贵（它是**整视图重建**：所有格子 + 线索 + 结构报告）──
out("\n== F. `core:view()` 单次成本（它每重建一次都要造上百个表）==")
do
  local N = 200
  local tv0 = os.clock()
  for _ = 1, N do core:view() end
  local tv1 = os.clock()
  local per = (tv1 - tv0) / N * 1000
  out(string.format("  [F] %d 次 view()：合计 %.1f ms，单次 %.3f ms；"
    .. "若**每帧**多调一次，60fps 下就是 %.1f%% 的帧预算（16.7ms）",
    N, (tv1 - tv0) * 1000, per, per / 16.7 * 100))
  F_view_ms = per
end

-- ── 口径 G：**正确性** —— 记忆表不许把内容记错（"复用列表项"最容易出错的场景）──
out("\n== G. 正确性：换了 index 的列表项，文字必须跟着换（复用场景）==")
local GG = { cold_ok = false, recycle_ok = false, warm_writes = -1, recycle_writes = -1 }
do
  local function cell_text(it, suffix)
    local c = nil
    pcall(function() c = it:GetChild("clue.1." .. suffix) end)
    return (c ~= nil) and tostring(c.text) or "<没有这个子控件>"
  end
  local pay = ctrl:_grid_text_payload()
  local it = grid.__items[1]
  -- ① 冷启动这一遍之后，第 1 项（引擎索引 0 ⇒ pos 1）的文字必须 == 第 1 条线索
  local want1 = pay.items[1]
  GG.cold_ok = (cell_text(it, "who") == want1.who and cell_text(it, "what") == want1.what
                and cell_text(it, "letter") == want1.letter)
  GG.cold_sample = "who=[" .. cell_text(it, "who") .. "] what=[" .. cell_text(it, "what")
    .. "] letter=[" .. cell_text(it, "letter") .. "]"

  -- ② 原样再进一次（同 index）⇒ 一个字都不该写
  local w0 = C.text_write
  ctrl._grid_in_refresh = false
  grid.__cb(it, it.__index)
  GG.warm_writes = C.text_write - w0

  -- ③ 模拟"引擎把这一项回收给第 3 条线索"（index 0 → 2）：三个角色**必须重写**
  local w1 = C.text_write
  it.__index = 2
  grid.__cb(it, it.__index)
  GG.recycle_writes = C.text_write - w1
  local want3 = pay.items[3]
  GG.recycle_ok = (cell_text(it, "who") == want3.who and cell_text(it, "what") == want3.what
                   and cell_text(it, "letter") == want3.letter)
  GG.recycle_sample = "who=[" .. cell_text(it, "who") .. "] what=[" .. cell_text(it, "what")
    .. "] letter=[" .. cell_text(it, "letter") .. "]"
  it.__index = 0                        -- 还原，免得影响后面的口径

  out(string.format("  [G1] 冷启动后第 1 项内容正确=%s　%s", tostring(GG.cold_ok), GG.cold_sample))
  out(string.format("  [G2] 同一个 index 再进一次 ⇒ 文字写入 %d 次（理想 0）", GG.warm_writes))
  out(string.format("  [G3] 换成第 3 条线索 ⇒ 文字写入 %d 次（理想 3 = 三个角色各重写一次），"
    .. "内容正确=%s　%s", GG.recycle_writes, tostring(GG.recycle_ok), GG.recycle_sample))
end

-- ── 口径 D：老路径（cfg.use_grid=false）做同一个动作，作对照 ──────────────
out("\n== D. 对照：老路径（手写滚动）一帧的账（cfg.use_grid=false）==")
adapter.cfg.use_grid = false
ctrl._grid = nil
ctrl._grid_state = "off"
ctrl._grid_sig = nil
ctrl._built = nil
ctrl._created = {}
ctrl._props = {}
ctrl._shown = nil
ctrl.dirty = true
reset()
pcall(function() OnUpdate(0.5) end)
out(string.format("  [D] 老路径一帧：find=%d（真搜树 %d / 搜空 %d）set_property=%d sub=%d "
  .. "view=%d  GetChildren=%d",
  C.find, C.find_deep, C.find_miss, C.set_prop, C.sub, C.view, C.getchildren))
adapter.cfg.use_grid = true

-- ── 口径 H：选关页上那趟「每帧兜底隐藏」有没有扫到网格的列表项 ──────────────
out("\n== H. 选关页：每帧的「兜底隐藏」（adapter:enforce_hidden_subtrees）扫了什么 ==")
local H = { setvis = 0, setvis_grid = 0, gc = 0, find = 0, frames = 60 }
do
  ctrl._grid = grid                      -- 回到网格这条路（前面 D 段把它关了）
  ctrl._grid_state = "on"
  ctrl._grid_sig = nil
  ctrl.screen = "select"
  ctrl.dirty = true
  pcall(function() for _ = 1, 3 do OnUpdate(1 / 60) end end)   -- 先切过去、稳定
  reset()
  pcall(function() for _ = 1, H.frames do OnUpdate(1 / 60) end end)
  H.setvis, H.setvis_grid, H.gc, H.find = C.setvis, C.setvis_grid, C.getchildren, C.find
  out(string.format("  [H] 选关页 %d 帧：SetVisible %d 次（其中打在**网格视窗子树**上 %d 次）、"
    .. "GetChildren %d 次、find %d 次",
    H.frames, H.setvis, H.setvis_grid, H.gc, H.find))
  out(string.format("      ⇒ 平均每帧：SetVisible %.1f 次（网格子树 %.1f 次）、GetChildren %.1f 次",
    H.setvis / H.frames, H.setvis_grid / H.frames, H.gc / H.frames))
  ctrl.screen = nil
  ctrl.dirty = true
  pcall(function() for _ = 1, 3 do OnUpdate(1 / 60) end end)
end

-- ── 汇总 ──────────────────────────────────────────────────────────────────
out("\n================ 汇总（真机上是这些调用被引擎执行）================")
out(string.format("  稳态一次 render      ：find %d（真搜树 %d / 搜空 %d）、set_property %d、"
  .. "view %d、GetChildren 访问 %d 个节点",
  A.find, A.deep, A.miss, A.sp, A.view, A.gc))
out(string.format("  一次冷 RefreshItems  ：列表项 GetChild %d 次、view %d 次、文字写入 %d 次",
  B.gc_item, B.view, B.text))
out(string.format("  引擎重进一次回调     ：列表项 GetChild %d 次、**view %d 次**、文字写入 %d 次",
  Cc.gc_item, Cc.view, Cc.text))
out(string.format("  连续 5 次重进        ：列表项 GetChild %d 次、view %d 次、文字写入 %d 次、"
  .. "挂监听 %d 次（理想每个列表项只挂一次 = %d）",
  C5.gc_item, C5.view, C5.text, c3_listeners, VISIBLE_ITEMS))
out(string.format("  300 帧（dt=1/60）    ：render %d 次、find %d、set_property %d、view %d、"
  .. "GetChildren %d、文字写入 %d、CPU %.1f ms",
  E.render, E.find, E.sp, E.view, E.gc, E.text, E.cpu))
out(string.format("  选关页每帧兜底隐藏   ：SetVisible %.0f 次（其中网格子树 %.0f 次）、"
  .. "GetChildren %.0f 次 —— **v057 同款代码**，不是网格那一轮引进的（见 H 段）",
  H.setvis / H.frames, H.setvis_grid / H.frames, H.gc / H.frames))
out("")
out(state_line)
out(string.format("  结论行（能直接和真机日志对上）：一次回调 = %d 次列表项查找 + %d 次整视图重建 + "
  .. "%d 次文字写入；若引擎**每帧**重进，就是每帧这么多",
  Cc.gc_item, Cc.view, Cc.text))

-- ── 判定：这个文件同时是**回归防线**（谁把记忆表改坏，这里立刻红）──────────
out("\n================ 判定 ================")
local pass, fail = 0, 0
local function ck(cond, label, detail)
  if cond then
    pass = pass + 1
    out("  [PASS] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  else
    fail = fail + 1
    out("  [FAIL] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  end
end
ck(A.view <= 1,
  "稳态一次 render 里 view() ≤ 1 次（网格那句「多余的整视图重建」已去掉）",
  "实测 " .. tostring(A.view) .. " 次（改之前是 2：网格 1 + 布局 1）；单次 " ..
  string.format("%.3f ms", F_view_ms))
ck(Cc.gc_item == 0 and Cc.view == 0 and Cc.text == 0,
  "引擎重进一次回调：列表项 GetChild / view() / 文字写入 **全为 0**（记忆表生效）",
  string.format("GetChild=%d view=%d 文字=%d（改之前：54 / 7 / 21）",
    Cc.gc_item, Cc.view, Cc.text))
ck(C5.gc_item == 0 and C5.view == 0,
  "连续 5 次重进：GetChild / view() 仍为 0（不会随重进次数增长）",
  string.format("GetChild=%d view=%d（改之前：270 / 35）", C5.gc_item, C5.view))
ck(B.view <= 1,
  "冷启动那一次 RefreshItems 只重建 1 次视图（= 文案快照那一次）",
  "实测 " .. tostring(B.view) .. " 次（改之前 8 次）")
ck(GG.cold_ok, "冷启动后列表项内容正确（who/what/letter 与线索对得上）", GG.cold_sample)
ck(GG.warm_writes == 0, "同一个 index 再进一次：**一个字都不写**（内容没变）",
  "实测 " .. tostring(GG.warm_writes) .. " 次")
ck(GG.recycle_writes == 3 and GG.recycle_ok,
  "★ 列表项被回收给别的线索时：三个角色**全部重写**且内容正确（防「残留上一条」）",
  string.format("重写 %d 次，内容正确=%s　%s", GG.recycle_writes, tostring(GG.recycle_ok),
    GG.recycle_sample))
ck(c3_listeners == VISIBLE_ITEMS,
  "点击监听不重复挂（弱键表去重有效）",
  string.format("7 个列表项 × 5 次重进 ⇒ 挂了 %d 次", c3_listeners))
ck(E.render > 0 and E.render == E.render,
  "对照记录：这 300 帧里 render 实际跑了多少次（真机每帧都重绘）",
  tostring(E.render) .. " 次 / 300 帧")

out(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
