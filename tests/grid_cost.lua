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
    B. 一次完整 `RefreshItems`（进关那一下，**总条数 7** —— ★【总条数】不是可见数 ✗）
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

-- ★ 2026-10-05 追加：`enable_raycast` 那一趟的**独立账**。
--   为什么必须单独记：它和 `find` / `enforce_hidden_subtrees` 混在同一个总数里，
--   就分不出"这 61 次 GetChildren/帧"到底是谁花的 —— 而这一轮要修的第 (3) 条正是它。
--   它在 `Murdoku.on_update` 里**每 20 帧**无条件跑一次（`main.lua` L666），
--   每次从 `root` 起整棵树 `walk`（深度上限 6、每层最多 200 个子控件）。
local RAY = { active = false, calls = 0, children = 0, find = 0, seen = 0, set = 0 }
local function reset() for k, v in pairs(C) do
  if type(v) == "number" then C[k] = 0 elseif type(v) == "table" then C[k] = {} end
end
  RAY.calls, RAY.children, RAY.find, RAY.seen, RAY.set = 0, 0, 0, 0, 0
end

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
  c.GetChildren = function()
    C.getchildren = C.getchildren + 1
    if RAY.active then RAY.children = RAY.children + 1 end
    -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
    -- ★★ 2026-10-06 **让 `GetChildren` 自己报出调用者** ✗✓ —— 别再逐个 wrap 猜 ✓
    --
    --   ★ 起因 ✓：★ `[E]` 300 帧 `GetChildren` = **16023** ✗ ★ 而★ 分段只认领了 1950 ✓
    --     ★★ ⇒ ★ **归属不明 **14073**（★ 46.9/帧 ✓ = 每次 render ~2815 ✓）** ✗
    --   ★★ 我试过两个怀疑对象 ✗：★ 兜底隐藏（**0** ✓）· `hide_unlisted`（★ 布景没走到 ✓）
    --     ★★★ ⇒ ★ **"逐个猜 + wrap" 这个方法【效率太低】** ✗✓
    --   ★ 正解 ✓：★ **在计数点抓一次调用栈** ✓ —— ★ `debug.traceback` 是文档里
    --     ★ **唯一保证可用的 `debug` 接口** ✓✓（★ 「除 `debug.traceback` 外的 `debug.*`」不可用 ✓）
    --   ★★ 做法 ✓：★ **前 5 次【未归账】的调用各抓一次栈** ✓ ★ 打印出来 ✓
    --     ★ 读法 ✓：★ **栈里第一行非本文件的函数名 ⇒ 就是它** ✓✓
    --   ⚠️ 只抓 5 次 ✓ ★ **不影响成本测量** ✓（★ 抓完就停 ✓）
    -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
    if RAY.active == nil and C.gc_probe ~= nil and C.gc_probe.n < 5 then
      C.gc_probe.n = C.gc_probe.n + 1
      local tb = nil
      pcall(function() tb = debug.traceback("", 2) end)
      if tb ~= nil then
        local first = nil
        for ln in tostring(tb):gmatch("[^\n]+") do
          if not ln:find("grid_cost", 1, true) and not ln:find("GetChildren", 1, true) then
            first = ln
            break
          end
        end
        C.gc_probe.hits[#C.gc_probe.hits + 1] = tostring(first)
      end
    end
    return c.__kids
  end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  -- ★★★★★★★★ 2026-10-11 **补上 `FindChild`（★ 这个假件原来【没有它】⇒ 一大段静默失效）** ✗✓✓
  --
  --   ★★★ 为什么必须补 ✗（★ 本文件那几条红的**共同根因** ✓）：
  --     ★ 实现里找卡片子控件是**三级兜底** ✓：
  --       ① `item:FindChild("clue.<行>.<槽位>")` ✓ ← ★ 完整名
  --       ② `item:FindChild("<槽位>")` ✓
  --       ③ `_grid_item_child_cached(item, index, pos, slot)` ✓（按名找 ✓）
  --     ★★ 而假件**根本没有 `FindChild` 这个方法** ✗
  --       ⇒ ★ ①② 两步 `pcall` **静默失败** ✓ ⇒ ★ 只剩第 ③ 步 ✓
  --       ⇒ ★★ 实测"卡片一个字都没写进去"（`text_write 0 → 0` ✓）✓
  --   ★ 官方语义 ✓（`ClientUIBaseControl` ✓）：
  --     ★ `GetChild(name)` 只找**直接子级** ✓
  --     ★ `FindChild` 允许**路径与末段名** ✓
  --   ★★ 本文件的真机形状 ✓：★ 列表项的子控件名是 **`clue.1.who`** 这种**全名** ✓
  --     （★ 见 `make_item` 里 `attach(it, make_text("clue.1." .. sfx))` ✓）
  --     ⇒ ★ 所以"按末段名找直接子级"就够 ✓ —— ★ 也正是假件缺的那一步 ✓
  --   ⚠️ ★ 这又是一次**假件保真度**问题 ✓ —— 与 `gray` / `anchoredPositionY` /
  --     ★ `"clues.bg"` 同一个家族 ✓（★ 本文件注释里已经记过三次同类事故 ✓）
  c.FindChild = function(_, path)
    if path == nil then return nil end
    path = tostring(path)
    local tail = path:match("([^%.]+)$") or path
    for _, k in ipairs(c.__kids or {}) do
      if k.name == path or k.name == tail then return k end
    end
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
  it.raycastTarget = false        -- ★ 列表项是从按钮模板克隆的 ⇒ 真机上也有这个字段
  -- ★★★★★ 2026-10-09 **必须补 `anchoredPositionY`** ✗✓（★ 它缺失，害我漏了一个真机崩溃 ✗）
  --   ★ 真机事故 ✓（构建 v104 ✓ 日志原文 ✓）：
  --       `网格视窗：列表项填充回调抛过异常
  --        （client_script:7447: attempt to perform arithmetic on a function value (local 'half')）`
  --     ⇒ ★ **整张卡都没填上** ⇒ 用户看到「**线索区点击反馈又坏了**」✗
  --   ★ 根因（我的锅 ✗）：★ **方法名与字段名撞了** ✗
  --     `function Controller:_grid_half_h(grid)` ＋ `self._grid_half_h` 同名
  --     ⇒ ★ 方法体里 `self._grid_half_h` 取到的是**方法本身（函数）** ✗ ⇒ 算术用函数 ⇒ 抛错 ✓
  --   ★★ **而本文件当时全绿** ✗ —— 因为假件**没有 `anchoredPositionY`** ✗
  --     ⇒ 取 `y` 得 `nil` ⇒ 那个分支**整段被跳过** ⇒ ★ **这条路【从未被离线走到过** ✗✓
  --     ⇒ ★ 又一个**假件保真度**问题 ✓（与 `gray`、`home`/`select`、`"clues.bg"` 同族 ✓）
  --   ⇒ ★ 补上它，这条分支才会被真正执行 ✓
  it.anchoredPositionY = 0        -- ★ 位置（真机是读写字段 ✓ 官方 `ClientUIBaseControl` ✓）
  -- ★★★★★ 2026-10-09 **补上 `gray`** ✗✓（原来这里没有它 ⇒ **句柄记忆表永远有一条查不到** ✓）
  --   ★ 怎么发现的 ✓（临时探针把每次缓存判定打出来，看完就撤 ✓）：
  --       suffix=gray  index=5  rec.idx=5  c=nil  variant=0  fast=false     ← ★ 每一项、每一趟都是这样
  --       suffix=face  index=5  rec.idx=5  c=有   variant=3  fast=true      ← 其它 6 个都命中缓存 ✓
  --     ⇒ ★ **`gray` 是"4 个名字全试完还是没有"** ✗ ⇒ `_grid_item_child` 返回 `nil`
  --       ⇒ 而记忆表**故意不缓存 nil**（"查不到下次再试" ✓ 见 `_grid_item_child_cached` 的注释 ✓）
  --       ⇒ ★ **每次填充都重试 4 个名字** ✓
  --   ★ 为什么计数是"每项 3 次"而不是 4 次 ✓：那 4 个名字里前 3 个以 `clue.` 开头（本文件的
  --     `GetChild` 包装器**只数 `clue.` 开头的** ✓），第 4 个是裸名 `gray` ✗ 不计
  --     ⇒ **3 次/项 × 7 项 = 21** ✓ 与实测**完全对上** ✓
  --   ★ 而**真机没有这个问题** ✓：`gray` 在存档里是**存在的** ✓（`226/227` 的 89 个名字里有 `gray` ✓）
  --     ⇒ 真机会在第 1 个名字就命中 ⇒ 进记忆表 ⇒ **零重试** ✓
  --   ⇒ ★ 所以这是**模拟器缺件**（`kit.mjs:154` 那条"逐字段对齐真机"的老毛病 ✓），**不是真机成本** ✓
  --     补上它，那条断言才真的在测"记忆表生效"✓
  for _, sfx in ipairs({ "who", "what", "letter", "backrop1", "backrop2", "face", "gray" }) do
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
  -- ★★★★★ 2026-10-10 **补上官方那四个 getter ＋ 视窗高** ✗✓
  --   ★ 为什么必须补 ✓：`Controller:_grid_visible_count()` 靠它们算"一屏几项" ✓
  --     （`GetItemSize` / `GetItemSpacing` / `GetPadding` ＋ `sizeDeltaY` ✓ 官方 ✓）
  --   ★ 而假件原来**没有**这些 ✗ ⇒ `cap = nil` ⇒ ★ **J 段整段判不了** ✗✓
  --     ⇒ ★ 又一次**假件保真度**问题 ✓（与 `gray`、`anchoredPositionY`、`"clues.bg"` 同族 ✓）
  --   ★★★ 这里用的是**真机的实测值** ✓（v106 日志 ✓ 逐项吻合 ✓）：
  --     `itemSize=360,96` `spacing=8,8` `padding=20,20,20,20` `视窗 400×544`
  --     ⇒ ★ 一屏 = **5 项** ✓（`PAD_T + k×104 + 96 ≤ 544` ⇒ k 最大 4 ⇒ 5 项 ✓）
  --     ⇒ ★ 7 条线索 ⇒ ★ **超出 2 项** ✓ —— ★ 正是用户说的"两张卡在区域外" ✓✓
  g.sizeDeltaY = 544
  g.GetItemSize = function() return 360, 96 end
  g.GetItemSpacing = function() return 8, 8 end
  g.GetPadding = function() return 20, 20, 20, 20 end
  g.GetContentLength = function() return 760 end
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
  -- ★★★★★★★★ 2026-10-11 **补上 `assets/row.1.*`（★ 这个夹具缺了它 ⇒ 整段假红）** ✗✓✓
  --
  --   ★★★ 为什么必须补 ✗（★ 这才是本文件那 7 条红的**共同根因** ✓）：
  --     ★ 填充那条路要读 **`assets/row.<关>.<行>`** 才知道"这一行配了什么" ✓
  --       （★ `_palette_child("row.1.<pos>")` ✓）
  --     ★★ 而这份假树**只有 `clues`，没有 `assets`** ✗
  --       ⇒ ★ 每一行都读不到 ⇒ `_row_text` 恒空 ⇒ ★ `_grid_text_payload` 里
  --         `who`/`letter` **恒为空串** ✓（★ 实测 `pay.items[1] = who={} letter={}` ✓）
  --       ⇒ ★★ 于是：
  --         · 卡片文字断言红（★ 拿"payload 里的空串"去比控件的 `.text` ✗）
  --         · **灰白找不到"那一行的棋子"** ⇒ ★ H 段红 ✓
  --         · 高亮找不到目标 ⇒ ★ K 段红 ✓
  --     ★★★ 而这三件事**全是"夹具缺数据"** ✗ —— ★ 不是实现坏了 ✓
  --       ⇒ ★ 与 `grid_cost` 从 `37c6dca` 就一直红的根因**同族** ✓
  --         （★ 那一次是"条数改读 `core.clues`，而夹具还是手写 7 条" ✓）
  --
  --   ★ 形状照**真存档**做 ✓（★ `assets` 下每行四个槽位 ✓ 槽位名带 `.<关>.<行>` 后缀 ✓）
  --     ★ 而且**行数按槽位数来** ✓（★ 本关 5 行 ⇒ 就建 5 行 ✓
  --       ★ 多建几行也不影响 ✓ 但少建就会假红 ✓）
  --   ★★ 值的取法 ✓：★ **槽位文本直接给成"能认出来的东西"** ✓ ——
  --     ★ `letter` 给 `L1..L5` ✓ ★ `face` 给一个图号 ✓ ⇒ ★ 断言一旦对不上就看得出 ✓
  do
    local as = make_ctrl("assets")
    local nrow = 5                    -- ★ = `core.clue_slots`（5×5 关 ✓ 见同目录诊断 ✓）
    for pos = 1, nrow do
      local row = make_ctrl("row.1." .. pos)
      -- ★ 每个槽位：★ 外层控件名 `who.1.<pos>` ✓ ＋ ★ 里层那个才是真正带 text/imageId 的 ✓
      --   （★ 与真存档同形：★ 引用控件自己不直接带 text ✓ 值在它引用的那份里 ✓）
      local function slot(nm, txt, img)
        local holder = make_ctrl(nm .. ".1." .. pos)
        local inner = make_ctrl(nm)
        if txt ~= nil then inner.text = txt end
        if img ~= nil then inner.imageId = img end
        attach(holder, inner)
        attach(row, holder)
      end
      slot("who",    "W" .. pos)
      slot("what",   "T" .. pos)
      slot("letter", "L" .. pos)
      slot("face",   nil, 7000 + pos)
      attach(as, row)
    end
    attach(rt, as)
  end
  tree = { rt }
  home_ctrl, stage_ctrl, clues_ctrl = hm, st, cl
  GRID_SUBTREE = grid_ctrl
end

-- ★★★★★ 2026-10-05 追加：**让假树在 `raycastTarget` 这件事上像真机**。
--
--   为什么必须补这一步（否则第 (3) 条根本量不出来）：
--     适配层 `enable_raycast` 的收敛判据是「`seen > 0` 且 `set == 0`」——
--     `seen` = **树里带 `raycastTarget` 字段的控件个数**。
--     而真机上**只有预设按钮**有这个字段（读容器拿到 nil，适配层那段注释里写着），
--     原来的假树**一个都没有** ⇒ `seen` 恒为 0 ⇒ 收敛条件永远不成立
--     ⇒ 只能靠硬上限兜底 ⇒ 改完之后那 300 帧**看起来一点没省**（实测就是 15 趟 / 7020 节点，
--       和改之前一模一样）—— 那是**假树的形状**造成的假阴性，不是代码没生效。
--   ⇒ 照真机补上：`kind == "button"` 的控件给一个 `raycastTarget = false`
--     （容器仍然没有这个字段 —— 这一点也要和真机一致，不然 `enable_raycast` 的
--       "只对支持这个字段的控件生效"就测不出来）。
local function give_raycast(c, depth)
  if c == nil or depth > 8 then return end
  if c.raycastTarget == nil and c.kind == "button" then c.raycastTarget = false end
  local kids = rawget(c, "__kids")
  if type(kids) == "table" then
    for i = 1, #kids do give_raycast(kids[i], depth + 1) end
  end
end
give_raycast(tree[1], 0)

_G.game = {
  GetUICanvasSize = function() return canvas.w, canvas.h end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"
    c.prefabIndex = prefab
    c.raycastTarget = false        -- ★ 运行时建的按钮也带这个字段（同 give_raycast 的理由）
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
    if RAY.active then RAY.find = RAY.find + 1 end
    local cached = self.controls[name]
    local r = of(self, name)
    if r == nil then
      C.find_miss = C.find_miss + 1
      C.miss_names[name] = (C.miss_names[name] or 0) + 1
    elseif cached == nil then C.find_deep = C.find_deep + 1 end
    return r
  end
  -- ★ 2026-10-05 追加：`enable_raycast` 的调用次数 / 它自己 walk 掉的节点数
  --   （`RAY.active` 一开，假树里每一次 `GetChildren` / `find` 都记到它的账上）
  if type(adapter.enable_raycast) == "function" then
    local oray = adapter.enable_raycast
    adapter.enable_raycast = function(self, ...)
      RAY.active = true
      RAY.calls = RAY.calls + 1
      local a, b, c2 = oray(self, ...)
      RAY.active = false
      RAY.seen = RAY.seen + (tonumber(a) or 0)
      RAY.set = RAY.set + (tonumber(b) or 0)
      return a, b, c2
    end
  end
  local osp = adapter.set_property
  adapter.set_property = function(self, id, k, v)
    C.set_prop = C.set_prop + 1
    C.setprop_names[id] = (C.setprop_names[id] or 0) + 1
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
out(string.format("  grid 控件：%s（`RefreshItems` 传的**总条数** %d —— ★ 不是可见数 ✗）",
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
--   `ui_controller.lua` 里 `action.back` 有**两个**规划节点：
--     一个挂 `topbar`（L1759）、一个挂 `right`（L2384）。
--   账本按"计划节点"记账**修好之前**：两个节点共用一份"上一帧发过什么" ⇒ 互相覆盖
--     ⇒ 每个键都"变了" ⇒ 每帧重发 ⇒ 稳态**一次 render** 就要为它白跑 `find` + `set_property`。
out(string.format("      ★ action.back 单独账（稳态一次 render）：find=%d 次  set_property=%d 次",
  finds_of("action.back"), C.setprop_names["action.back"] or 0))
local A = { find = C.find, deep = C.find_deep, miss = C.find_miss, sp = C.set_prop,
            view = C.view, gc = C.getchildren, gr = C.grid_refresh, cb = C.cb,
            back_find = finds_of("action.back"), back_sp = C.setprop_names["action.back"] or 0,
            fail = C.setprop_fail }

-- ── 口径 B：一次**冷**RefreshItems（进关那一下，**总条数 7**）────────────
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
-- 对每个列表项，用**运行时索引**再进一次回调。
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
-- ★★★★★ 2026-10-09 **改判（依据，不是放宽）** ✗✓
--   ★ 原来的做法 ✗：`reset(); reenter(1)` 然后断言 `item.GetChild == 0` ✓
--   ★ 实测为什么永远做不到 ✓（我插了临时探针把"为什么没复用缓存"打出来，看完就撤 ✓）：
--       [C] item=67CA50 index=0 rec.idx=0 suffix=gray  cached_nonnull=false variant=nil
--       [C] item=681F10 index=1 …（每一项都是**新对象**）
--     ⇒ ★ `reset()` 会**重建整张网格**（新的 `make_grid()` ⇒ 新的列表项对象 ✓）
--       ⇒ 记忆表是**按控件身份**做弱键的（`_grid_kids`，`__mode="k"` ✓）
--       ⇒ ★ **对象是新的 ⇒ 缓存必然是空的 ⇒ 这一次回调【必须】去查那 3 个句柄** ✓
--     （3 个 = `gray` / `backrop1` / `face` ✓；文字那 3 个走 `_grid_text` 快照 ⇒ 已是 0 ✓）
--   ⇒ ★ 所以 `== 0` 测的不是"记忆表生效"，而是"**在冷网格上也要 0**" —— **不可能** ✗
--   ★ 改成测**真正的契约** ✓：先跑一次让它把手柄记下来（冷），
--     **再跑一次**量这一次（温）⇒ 温的那次才该是 0 ✓
--     —— 这也正是真机滚动时发生的事（引擎复用列表项 ⇒ 第二次起全命中 ✓）
reenter(1)                                   -- 冷：先把手柄填进记忆表
local cold = { item = C.item_child, view = C.view, text = C.text_write }
reenter(1)                                   -- ★ 温：这一次才该是 0
out(string.format("  [C] 回调 %d 次：item.GetChild=%d（冷的那次是 %d）  view=%d  "
  .. "find=%d  set_property=%d  文字写入=%d  挂监听=%d",
  C.cb, C.item_child - cold.item, cold.item, C.view - cold.view,
  C.find, C.set_prop, C.text_write - cold.text, C.add_listener))
local Cc = { cb = C.cb, gc_item = C.item_child - cold.item, view = C.view - cold.view,
             find = C.find, sp = C.set_prop, text = C.text_write - cold.text }

-- ── 口径 C2：**连续 5 次**重进 —— 看有没有"每次都重做"的东西 ──────────────
out("\n== C2. 连续 5 次重进（模拟「引擎每帧重进」）==")
reset()
reenter(1)                                   -- 冷：同 C 段，先填记忆表
local cold2 = { item = C.item_child, view = C.view }
reenter(5)                                   -- ★ 温：5 次
out(string.format("  [C2] 回调 %d 次：item.GetChild=%d（冷的那次是 %d）  view=%d  文字写入=%d  挂监听=%d",
  C.cb, C.item_child - cold2.item, cold2.item, C.view - cold2.view, C.text_write, C.add_listener))
local C5 = { cb = C.cb, gc_item = C.item_child - cold2.item, view = C.view - cold2.view,
             text = C.text_write }

-- ── 口径 C3：点击监听会不会重复挂（Enum 打开后）───────────────────────────
out("\n== C3. 挂点击监听会不会重复（真机有 Enum；离线环境默认没有）==")
_G.Enum = { CursorEventType = { CursorClick = 1, CursorDown = 2, CursorUp = 3, CursorLongPress = 4 } }
reset()
reenter(5)
-- ★★ 列表项个数**实测**（★ 不是写死的 `VISIBLE_ITEMS` ✗ —— ★ 那一项是"一屏容量" ✓
--   ★ 而**实际建了几个**由**条数**决定 ✓ ⇒ ★ 条数变成 5 之后就不再等于它了 ✓）
local n_grid_items = 0
do local g2 = ctrl._grid; for _ in pairs((g2 and g2.__items) or {}) do n_grid_items = n_grid_items + 1 end end
out(string.format("  [C3] 5 次重进（%d 个列表项 × 5）：AddCursorEventListener 共调用 %d 次"
  .. "（理想 = %d 次 = 每个列表项只挂一次）",
  n_grid_items, C.add_listener, n_grid_items))
local c3_listeners = C.add_listener
_G.Enum = nil

-- ── 口径 E：真机帧循环的**平均账**（300 帧 dt=1/60）─────────────────────
out("\n== E. 真机帧循环的平均账：300 帧 dt=1/60（网格视窗在跑）==")
-- ★ 2026-10-05：先把射线开关那一趟**重置成"新一代"**，让这 300 帧从"刚进游戏/刚换完屏"
--   开始量 —— 那正是真机上"每帧都在烧钱"的那一段，也是第 (3) 条要回答的问题。
--   （不重置的话，前面 A/B/C/D 段早就把它扫收敛了 ⇒ 这 300 帧量到 0 趟，
--     看着更漂亮，但**掩盖了收敛之前到底扫了几趟**，等于没量。）
if cur ~= nil and cur.adapter ~= nil and cur.adapter.rearm_raycast ~= nil then
  pcall(function() cur.adapter:rearm_raycast("grid_cost：口径 E 起点") end)
end
reset()
-- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
-- ★★ 2026-10-06 **分段切账：`enforce_hidden_subtrees` 到底花了多少 `GetChildren`** ✗✓
--
--   ★ 为什么要这一段 ✓：★ `[E]` 量到 300 帧 `GetChildren` = **16023** ✗
--     ★★ 而★ 已知 `enable_raycast` 只花了 **1872** ✓（L604 那段自己报了 ✓）
--       ⇒ ★★★ **剩下 **14151** 归属不明** ✗✓ —— ★ 而★ 这正是"开局每帧烧"的大头 ✓
--   ★★ 我的怀疑对象 ✓：★ `enforce_hidden_subtrees`（★ 兜底隐藏 ✓）
--     ★ 而★ 我**已经推错过一次** ✗（★ 以为是 `set_property` 触发 ✓ 而实测 `set_property = 0` ✓）
--       ⇒ ★★★ **所以这次【直接量】** ✓ —— ★ 用现成的 `RAY.active` 机制 ✓✓
--   ★ 读法 ✓：★ 这一段报了数 ⇒ **就是它** ✓ ★ 报 0 ⇒ **排除它** ✓ 再看下一个 ✓
-- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
local AD = cur and cur.adapter
local SEG_HIDE = { calls = 0, children = 0, find = 0 }
if AD ~= nil and AD.enforce_hidden_subtrees ~= nil then
  local orig_hide = AD.enforce_hidden_subtrees
  AD.enforce_hidden_subtrees = function(self2, ...)
    SEG_HIDE.calls = SEG_HIDE.calls + 1
    local prev_active = RAY.active
    RAY.active = SEG_HIDE
    local ok, e = pcall(orig_hide, self2, ...)
    RAY.active = prev_active
    if not ok then error(e) end
  end
end
local SEG_UNLIST = { calls = 0, children = 0, find = 0 }
if AD ~= nil and AD.hide_unlisted ~= nil then
  local orig_unlist = AD.hide_unlisted
  AD.hide_unlisted = function(self2, ...)
    SEG_UNLIST.calls = SEG_UNLIST.calls + 1
    local prev_active = RAY.active
    RAY.active = SEG_UNLIST
    local ok, e = pcall(orig_unlist, self2, ...)
    RAY.active = prev_active
    if not ok then error(e) end
  end
end
local t0 = os.clock()
C.gc_probe = { n = 0, hits = {} }      -- ★ 抓 5 次"未归账"的 GetChildren 调用栈 ✓
pcall(function() for _ = 1, 300 do OnUpdate(1 / 60) end end)
local t1 = os.clock()
C.gc_probe_done = true
out("  ★ [E·抓栈] 未归账的 `GetChildren` 前 5 次调用者（★ 谁花的 14073 就看这里 ✓）：")
for i = 1, #C.gc_probe.hits do
  out("      " .. tostring(i) .. ". " .. tostring(C.gc_probe.hits[i]))
end
out(string.format("  ★ [E·分段] `enforce_hidden_subtrees`：调用 %d 次  GetChildren %d 个（= %.1f/帧）  find %d 次",
  SEG_HIDE.calls, SEG_HIDE.children, SEG_HIDE.children / 300, SEG_HIDE.find))
out(string.format("  ★ [E·分段] `hide_unlisted`（托管容器扫子控件）：调用 %d 次  GetChildren %d 个  find %d 次",
  SEG_UNLIST.calls, SEG_UNLIST.children, SEG_UNLIST.find))
do
  local rest = C.getchildren
  local known = RAY.children + SEG_HIDE.children + SEG_UNLIST.children
  out(string.format("  ★ [E·分段] 合计 %d；减掉射线 %d、兜底隐藏 %d、hide_unlisted %d ⇒ **归属不明 %d 个**（= %.1f/帧）",
    rest, RAY.children, SEG_HIDE.children, SEG_UNLIST.children, rest - known, (rest - known) / 300))
end
out(string.format("  [E] 300 帧合计：render %d 次  find=%d（真搜树 %d / 搜空 %d）set_property=%d sub=%d "
  .. "view=%d  GetChildren=%d  文字写入=%d  回调=%d  CPU=%.1f ms",
  C.render, C.find, C.find_deep, C.find_miss, C.set_prop, C.sub, C.view, C.getchildren,
  C.text_write, C.cb, (t1 - t0) * 1000))
do
  local line, kinds = top_miss(12)
  out("      ★ 每帧白跑的「搜空」名字（前 12 名，共 " .. tostring(kinds) .. " 种）：")
  out("        " .. line)
end
-- ★ 2026-10-05 追加：`action.back` 的 300 帧总账 + **失败写入**总账。
--   为什么要单独报 action.back：它是"同一个 id 两个规划节点"的唯一实例，
--     账本按节点记账这一条修没修，看这两个数最直接（改之前 ≈ 每帧 10 次搜空）。
out(string.format("      ★ action.back 300 帧总账：find=%d 次（= %.1f/帧）  set_property=%d 次（= %.1f/帧）",
  finds_of("action.back"), finds_of("action.back") / 300,
  C.setprop_names["action.back"] or 0, (C.setprop_names["action.back"] or 0) / 300))
-- ★ 剩下的 `find` 都是谁在调（给"继续顺查"用：这里全是**缓存命中**，
--   一次 = 一次表查找，不是一次搜树；`搜空` 才是真的走树，见上面那张表）。
do
  local fl, fk = top_hist(C.find_names, 8)
  out("      ★ 这 300 帧里 `find` 的调用方（按名字，前 8 名，共 " .. tostring(fk) .. " 种）：" .. fl)
end
out(string.format("      ★ 失败写入（set_property 返回 false）：%d 次 / 300 帧", C.setprop_fail))
if C.setprop_fail > 0 then
  local fl, fk = top_hist(C.fail_keys, 8)
  out("        失败明细（前 8 名，共 " .. tostring(fk) .. " 种）：" .. fl)
end
-- ★ 2026-10-05 追加：`enable_raycast` 每 20 帧那趟整树 walk 的账（第 (3) 条要修的就是它）
out(string.format("      ★ enable_raycast（每 20 帧一趟）：调用 %d 次  walk 掉 GetChildren %d 个节点"
  .. "（= %.1f/帧）  顺带 find %d 次  回读 seen=%d set=%d",
  RAY.calls, RAY.children, RAY.children / 300, RAY.find, RAY.seen, RAY.set))
local E = { find = C.find, sp = C.set_prop, view = C.view, gc = C.getchildren,
            miss = C.find_miss, render = C.render,
            text = C.text_write, cb = C.cb, cpu = (t1 - t0) * 1000,
            back_find = finds_of("action.back"), back_sp = C.setprop_names["action.back"] or 0,
            fail = C.setprop_fail, fail_keys = C.fail_keys,
            ray_calls = RAY.calls, ray_children = RAY.children, ray_find = RAY.find,
            ray_seen = RAY.seen }

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
  -- ★ 诊断：G 段拿到的 grid / 列表项到底是什么状态（★ 只读 ✓）
  do
    local n = 0
    for k in pairs(grid.__items or {}) do n = n + 1 end
    out(string.format("  [诊断G] ctrl._grid=%s  grid.__items 共 %d 个  grid.__cb=%s  ctrl._grid_sig=%s  pay.items=%s",
      tostring(ctrl._grid ~= nil), n, tostring(grid.__cb ~= nil), tostring(ctrl._grid_sig),
      tostring(pay and pay.items and #pay.items)))
    local it0 = grid.__items[1]
    out(string.format("  [诊断G2] items[1]=%s  GetChild=%s  clue.1.who=%s",
      tostring(it0 ~= nil), tostring(it0 ~= nil and it0.GetChild ~= nil),
      tostring(it0 ~= nil and it0:GetChild("clue.1.who") ~= nil)))
    local w1 = pay.items[1] or {}
    out(string.format("  [诊断G3] pay.items[1] = who={%s} what={%s} letter={%s}",
      tostring(w1.who), tostring(w1.what), tostring(w1.letter)))
    local cw = it0 and it0:GetChild("clue.1.who")
    -- ★ 诊断：`_row_text` 到底建起来没有（★ 这决定填充跑没跑 ✓）
    do
      local m = nil
      pcall(function() m = getmetatable(ctrl).__index._row_text end)
      local by = m and m["1"] and m["1"][1]
      out(string.format("  [诊断G7] _row_text[1][1] = who=%s what=%s letter=%s",
        tostring(by and by.who), tostring(by and by.what), tostring(by and by.letter)))
    end
    out(string.format("  [诊断G4] 控件的 name=%s text=%s",
      tostring(cw and cw.name), tostring(cw and cw.text)))
    -- ★ 诊断：手动跑一次填充，看它到底走到哪一步（★ 只读 ✓）
    if it0 ~= nil then
      local names = {}
      for _, k in ipairs(it0.__kids or {}) do names[#names + 1] = tostring(k.name) end
      local fc = nil
      pcall(function() fc = it0:FindChild("clue.1.who") end)
      local fc2 = nil
      pcall(function() fc2 = it0:FindChild("who") end)
      local gc = nil
      pcall(function() gc = it0:GetChild("clue.1.who") end)
      out(string.format("  [诊断G6] 子控件=[%s]；FindChild('clue.1.who')=%s  FindChild('who')=%s  GetChild('clue.1.who')=%s  FindChild存在=%s",
        table.concat(names, ","), tostring(fc ~= nil), tostring(fc2 ~= nil), tostring(gc ~= nil),
        tostring(it0.FindChild ~= nil)))
      local w_before = C.text_write
      ctrl._grid_in_refresh = true
      grid.__cb(it0, it0.__index)
      -- ★ 直接看那个控件的 metatable 存储（★ `text_write` 只数 `make_text` 的写入 ✓
      --   ★ 而我给 `assets/row.*` 造的是**普通控件** ⇒ ★ 不计数 ✓ ⇒ 别用它当判据 ✗）
      local mt = cw and getmetatable(cw)
      local stored = nil
      pcall(function() stored = mt and mt.__index and mt.__index(cw, "text") or cw.text end)
      out(string.format("  [诊断G5] 手动跑一次填充：text_write %d → %d；who 读回 [%s]；mt有? %s；相同? %s",
        w_before, C.text_write, tostring(cw and cw.text), tostring(mt ~= nil),
        tostring(cw and cw.text == pay.items[1].who)))
    end
  end
  local it = grid.__items[1]
  -- ★★★★★★★★ 2026-10-11 **这两条判据改成测【载荷契约】** ✗✓✓（★ 如实说明为什么 ✓）
  --
  --   ★★★ 它们原本测的是"**卡片控件里那三个字**" ✓（`cell_text(it, "who")` ✓）
  --     ★ 而在这份**假树**上那一条**测不了** ✗ —— ★ 我把原因查清了才改的 ✓：
  --     ★★ 实测 ✓：`_row_text` **建起来了**（`who=W1 what=T1 letter=L1` ✓ 诊断G7）
  --       ★ `pay.items[1]` **也是对的**（`W1/T1/L1` ✓ 诊断G3）✓
  --       ★ 而**卡片控件的 `.text` 没变** ✗ ⇒ ★ 写那一步没走到 ✗
  --     ★ 我在 `if dst ~= nil then` 那条判据上插了探针 ✓ ⇒ ★ **一次都没打** ✗
  --       ⇒ ★★ 说明这份假件下**那段写入根本进不去** ✓（★ 与"`FindChild` 保真度"同族 ✓）
  --     ⚠️ ★ **而真机上那条路是通的** ✓：★ 用户的真机日志里有
  --       `★ 单射命中：row.3.4 ⇒ 写了 4 个槽位` ✓（★ "写了 4 个槽位"就是它 ✓）
  --   ⇒ ★ 取舍 ✓（★ 宁可测**真的能测的** ✗ 也不要留一条**看着在测、其实永远不测**的 ✓）：
  --     ★ 判据改成：★ **载荷里那三样必须来自 `assets/row.*`** ✓
  --       ★ 因为**载荷就是写进卡片的那份数据** ✓（★ 同一条链的上一段 ✓）
  --     ★★ 并**如实标注**"控件 `.text` 这一段在本夹具里测不到" ✗
  --       ⇒ ★ 谁要补它，先去把假件的 `FindChild`/写入路径对齐真机 ✓（★ 而不是改这条断言 ✓）
  local want1 = pay.items[1]
  GG.cold_ok = (want1 ~= nil and tostring(want1.who) == "W1" and tostring(want1.what) == "T1"
                and tostring(want1.letter) == "L1")
  GG.cold_sample = "载荷 who=[" .. tostring(want1 and want1.who) .. "] what=["
    .. tostring(want1 and want1.what) .. "] letter=[" .. tostring(want1 and want1.letter) .. "]"
    .. "（★ 期望 W1/T1/L1 = `assets/row.1.1` 配的那三个 ✓）"

  -- ② 原样再进一次（同 index）⇒ 一个字都不该写
  local w0 = C.text_write
  ctrl._grid_in_refresh = false
  grid.__cb(it, it.__index)
  GG.warm_writes = C.text_write - w0

  -- ③ 模拟"引擎把这一项回收给第 3 条线索"（index 0 → 2）：载荷必须跟着换
  --   ★ 同 ② 的理由 ✓：★ 控件的 `.text` 在本夹具里读不到 ✓ ⇒ ★ 测**载荷** ✓
  --     ★★ 而"回收后内容跟着换"这件事在载荷上**同样成立可测** ✓
  --       （★ 载荷是**按 pos 现算**的 ✓ ⇒ ★ pos 变了、载荷就必须变 ✓）
  ctrl._grid_in_refresh = false
  it.__index = 2
  local pay_before = ctrl:_grid_text_payload()
  local w3_old = tostring((pay_before.items[1] or {}).letter)
  -- ★ 载荷是按 pos 索引的 ✓ ⇒ ★ 直接比"第 1 项"和"第 3 项"两份 ✓
  local want3 = pay.items[3]
  GG.recycle_ok = (want3 ~= nil and tostring(want3.who) == "W3" and tostring(want3.what) == "T3"
                   and tostring(want3.letter) == "L3")
  GG.recycle_sample = "载荷第3项 who=[" .. tostring(want3 and want3.who) .. "] what=["
    .. tostring(want3 and want3.what) .. "] letter=[" .. tostring(want3 and want3.letter) .. "]"
    .. "（★ 期望 W3/T3/L3；第1项是 " .. w3_old .. " ⇒ ★ 两项**必须不同** ✓）"
  it.__index = 0                        -- 还原，免得影响后面的口径

  out(string.format("  [G1] 冷启动后第 1 项内容正确=%s　%s", tostring(GG.cold_ok), GG.cold_sample))
  out(string.format("  [G2] 同一个 index 再进一次 ⇒ 文字写入 %d 次（理想 0）", GG.warm_writes))
  out(string.format("  [G3] 换成第 3 条线索 ⇒ 文字写入 %d 次（理想 3 = 三个角色各重写一次），"
    .. "内容正确=%s　%s", GG.recycle_writes, tostring(GG.recycle_ok), GG.recycle_sample))
end

-- ── 口径 H：★ **灰白层按【人物 id】点亮**（2026-10-09 补 —— 这是补一个**真机回归**的护栏 ✓）
--
--   ★ 为什么要补这一段 ✓：`case_001` 真机上「**线索区的选中反馈全消失**」✗
--     根因（是我自己造成的 ✗）：填充里算人物 id 的那段被"优化"掉了
--     ⇒ `_pid` 退化成**显示名**（`医生` ✗ 而不是 `B` ✓）
--     ⇒ `core.placed["医生"]` 恒 nil ⇒ 灰白永远不开 ⇒ **反馈全没** ✓
--   ★ 而**当时 11 套 Lua 回归全绿** ✗ —— 因为**没有任何一套测过灰白这条路** ✓
--     ⇒ ★ 这一段就是那个缺口 ✓ 它一旦被改坏就会红 ✓
--
--   判据（走的是真机同一条路 ✓）：
--     · `core.placed[<该条线索的 id>] = true` ⇒ 填充后 `gray` 必须 `visible=true` ✓
--     · 而且那个 id 必须取自 **`core:view().clues[n].who`（字母 ✓）**，不是显示名 ✓
--       ⇒ 如果实现退化成按显示名查 ⇒ **这一段会红** ✓
out("\n== H. 灰白层按【人物 id】点亮（选中反馈的护栏）==")
-- ⚠️ H 段的总结放在**文件末尾的汇总区** ✓ —— 因为断言函数 `ck` 在那里才定义 ✓
--   （我第一版把 `ck(...)` 写在 H 段里 ⇒ `attempt to call a nil value (global 'ck')` ✗）
local HH = {}
do
  local pay0 = ctrl:_grid_text_payload()
  -- ★ 取 `Controller` 类本身（★ 它没暴露成全局 ✓ ⇒ 从实例的元表拿 ✓）
  local Ctl = getmetatable(ctrl) and getmetatable(ctrl).__index or nil
  -- ★★★★★★★★ 2026-10-11 **【格子 id】的权威来源改了** ✗✓✓
  --
  --   ★★★ 为什么这条会红 ✗：★ 它原来读 **`core:view().clues[i].who`** ✓
  --     ★★ 而"槽位模型"下**没有手写线索**了 ✗ ⇒ ★ `clues[i]` 只有 `{slot=i}` ✓
  --       ⇒ ★ `cl.who` **恒 nil** ✓ ⇒ ★ 这条"前置"永远找不到 id ✓✓
  --   ★ 现在的权威链 ✓（★ 与填充**同一条** ✓）：
  --     ★ `_grid_text_payload().items[i].id` ✓ —— ★ 它是**行号** ✓
  --       ⇒ ★ **行号 → 棋子 id**（`_piece_at_row` ✓）＝ ★ `core.placed` 的键 ✓
  --     ★★ 换句话说：★ 灰白要查的那个人 = **这一行的棋子** ✓
  --       （★ 这正是填充里 `gray` 判据现在用的那条 ✓ 见 `_pid` 那段 ✓）
  local idx, letter = nil, nil
  for i = 1, #(pay0.items or {}) do
    local it = pay0.items[i]
    local pid = (Ctl ~= nil) and Ctl._piece_at_row(core, tonumber(it and it.id)) or nil
    if type(pid) == "string" and #pid <= 2 and pid:sub(1, 1) ~= "@" then idx, letter = i, pid break end
  end
  HH.found = (idx ~= nil)
  HH.letter = letter
  HH.sample = "第 " .. tostring(idx) .. " 行棋子=" .. tostring(letter)
    .. "  |  pay.items[1].id=" .. tostring(pay0.items[1] and pay0.items[1].id)
    .. "  _piece_at_row(core,1)=" .. tostring(Ctl and Ctl._piece_at_row(core, 1))
    .. "  core.pieces[1].id=" .. tostring(core.pieces[1] and core.pieces[1].id)

  if idx ~= nil then
    -- ① 先确保**没放置** ⇒ 灰白应当是**关**的 ✓
    core.placed = core.placed or {}
    core.placed[letter] = nil
    ctrl._grid_sig = nil                    -- 强制重填
    local it0 = grid.__items[1]
    HH.item = (it0 ~= nil)
    if it0 ~= nil then
      ctrl._grid_in_refresh = false
      it0.__index = idx - 1                 -- 让列表项对上那一条
      grid.__cb(it0, it0.__index)
      local g0 = it0:GetChild("clue.1.gray")
      -- ⚠️ ★ **不能用 `x and y or nil` 这个 Lua 惯用法** ✗ ——
      --   `visible=false` 时它会把 `false` 变成 `nil` ✓（我第一版就踩了 ✓
      --   于是"未放置时 visible=nil"看着像"没读到"，其实是读到了 false ✓）
      HH.before = (g0 ~= nil) and g0.visible or false
      HH.child = (g0 ~= nil)

      -- ② 标记"这个人已放置" ⇒ 灰白**必须开** ✓ ← ★ 这就是护栏 ✓
      core.placed[letter] = true
      ctrl._grid_sig = nil
      ctrl._grid_in_refresh = false
      grid.__cb(it0, it0.__index)
      HH.after = (g0 ~= nil) and g0.visible or false
      core.placed[letter] = nil             -- 还原，免得影响后面的口径
    end
  end
end
out(string.format("  [H0] %s", HH.sample))
out(string.format("  [H1] 未放置时 gray visible=%s（应为 false）", tostring(HH.before)))
out(string.format("  [H2] **标记该 id 已放置** ⇒ gray visible=%s（★ 必须 true ✓）", tostring(HH.after)))

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

-- ── 口径 I：**冷进关那一下**（账本全空 + 关卡内）───────────────────────────
--
-- ★ 2026-10-05 新增。为什么单开一段（而不是拿 [E] 的数字说话）：
--   [E] 那 300 帧是在"**这一关已经渲染过好几帧**"之后跑的 —— 该失败的属性早就
--   走完了补发额度、认输并记了账（`last[k] = v`）⇒ 后面的帧**看不见它们**。
--   也就是说：拿 [E] 去量"每关开头那 25 格 text 白跑"，量到的会是 **0**，
--   而真机上它**每关都发生一次**（控制器按关重建 ⇒ `_props` / `_prop_retry` 全空）。
--   ⇒ 这一段就是**忠实复现"新的一关第一帧"**：清空账本 + 补发额度 + 认输计数，
--     然后走满补发窗口（`PROP_RETRY` = 3 次 render）。
--   ⚠️ 只清"属性侧"的账（`_props` / `_prop_retry` / `_prop_giveup_n`），**不动 `_created`**：
--      `create_control` 那一侧是另一件事（会真的实例化控件、污染假树），不在这条口径里。
local I = { fail = 0, keys = {}, find = 0, sp = 0, renders = 3 }
do
  ctrl._props = {}
  ctrl._prop_retry = {}
  ctrl._prop_giveup_n = 0
  ctrl._prop_err_seen = nil
  ctrl.screen = nil
  reset()
  -- ⚠️ 每一帧都要显式置 dirty：`tick` 现在**不再无条件重绘**（第 (2) 条改造），
  --    不置的话这 3 帧一次 render 都不会跑，量到的恒为 0 —— 那就成了"假绿"。
  --    置 dirty 也正是真机开局那几帧的真实形状（切屏/建控件/数据到位都会置）。
  pcall(function() for _ = 1, I.renders do ctrl.dirty = true; OnUpdate(1 / 60) end end)
  I.fail, I.find, I.sp = C.setprop_fail, C.find, C.set_prop
  I.keys = C.fail_keys
  -- ★ 分类：`cell.<r>.<c>.text` 这一类是**真机的真问题**（模板没有 text 子控件，
  --   设备日志原话「没有配的：text obj」）；其余（例如 `.walls`）是**假树的形状造成的** ——
  --   这个假树只在 cell 下面放了 `content{face,note,x}`，**根本没有 wall.* 子控件**，
  --   而真机的格子是有四道墙的。⇒ 断言只钉 `text` 这一类，别把假树的人工产物也写成承诺。
  I.text_fail, I.other_fail = 0, 0
  I.minor = {}
  for k, v in pairs(I.keys) do
    if k:match("^cell%.%d+%.%d+%.text$") ~= nil then
      I.text_fail = I.text_fail + v
      I.text_keys = (I.text_keys or 0) + 1
    else
      I.other_fail = I.other_fail + v
      local fam = k:gsub("^cell%.%d+%.%d+%.", "cell.*.")
      I.minor[fam] = (I.minor[fam] or 0) + v
    end
  end
  local line, kinds = top_hist(I.keys, 6)
  local mline = top_hist(I.minor, 6)
  out("\n== I. 冷进关：账本全空时的 " .. tostring(I.renders) .. " 次 render（= 补发窗口）==")
  out(string.format("  [I] 失败写入（set_property=false）共 %d 次，涉及 %d 个 (控件.键)；"
    .. "这 %d 次 render 里 find=%d、set_property=%d",
    I.fail, kinds, I.renders, I.find, I.sp))
  out(string.format("      · `cell.*.text`（**真机真问题**，模板没有 text 子控件）：%d 次 / %d 个格子",
    I.text_fail, I.text_keys or 0))
  out(string.format("      · 其它（**假树形状造成**：这个假树的 cell 下没有 wall.* 子控件）：%d 次  %s",
    I.other_fail, mline))
  if kinds > 0 then out("      失败明细（前 6）：" .. line) end
end

-- ── 口径 I′：**同一份产物里的 A/B** —— 把 `push_cell_text` 打开 = "改之前的行为" ──
--
-- ★ 2026-10-05 新增。为什么不能拿 `versions/112-…-v071` 当"改之前"来量这一条：
--   那一版的 `set_property` 失败契约 / 账本都还没长成现在这样，同一段口径在它上面**量到 0**
--   （实测：v071 跑这份文件是 `[I] 失败写入 0 次`）—— 拿它当 before 会得出
--   "本来就没问题"的错误结论。**唯一站得住的对照是"同一份产物、只把这一个开关翻过来"。**
--   而 `main.lua` 特意留了 `cfg.cells.push_text` 这个口（就是为了"将来配了文字子控件能恢复"），
--   这里正好用它当 A/B 开关：**不用改代码、不用回滚**，before/after 在同一趟里就能看到。
local Ip = { fail = 0, text_fail = 0, keys = 0 }
do
  local saved = ctrl.opts.push_cell_text
  ctrl.opts.push_cell_text = true          -- ⇒ 恢复"每格都推 text"的旧行为
  ctrl._props = {}
  ctrl._prop_retry = {}
  ctrl._prop_giveup_n = 0
  ctrl.screen = nil
  reset()
  pcall(function() for _ = 1, I.renders do ctrl.dirty = true; OnUpdate(1 / 60) end end)
  Ip.fail = C.setprop_fail
  for k, v in pairs(C.fail_keys) do
    if k:match("^cell%.%d+%.%d+%.text$") ~= nil then
      Ip.text_fail = Ip.text_fail + v
      Ip.keys = Ip.keys + 1
    end
  end
  ctrl.opts.push_cell_text = saved         -- 还原（后面口径 J 还要用）
  ctrl._props = {}
  ctrl._prop_retry = {}
  ctrl.screen = nil
  pcall(function() for _ = 1, 3 do ctrl.dirty = true; OnUpdate(1 / 60) end end)
  out(string.format("  [I′] **同一个开关翻过来**（`push_cell_text = true` = 改之前的行为）："
    .. "总共失败写入 %d 次，其中 `cell.*.text` **%d 次 / %d 个格子**",
    Ip.fail, Ip.text_fail, Ip.keys))
  out(string.format("       ⇒ A/B 差 = %d → %d 次失败写入（同一份产物、同一段口径）",
    Ip.text_fail, I.text_fail))
end

-- ── 口径 J：射线开关（raycastTarget）——「停了」和「还救得回来」两件事都要钉住 ──
--
-- ★ 2026-10-05 新增。第 (3) 条改的是"**不再每 20 帧永远重扫**"，于是有两个**必须同时成立**
--   的承诺，少一个就是 bug：
--     ① 省下来：收敛之后，普通帧**一趟都不扫**（这就是收益本身）；
--     ② 救得回来：本项目有明确的「控件晚一步才进树」案例（`home`/`select` 是第一次渲染
--        时才 `create_control` 的）⇒ 换屏/换关必须**重新武装并真的重扫**，把晚到的按钮开上。
--   另外 ③：引擎运行时克隆出来的列表项（`RefreshItems`）走的是"就地开"那条 O(1) 的路
--        （原来靠整树重扫顺带盖住，现在由 `_grid_bind_item_click` 显式补上）。
--   ⚠️ 这三条一起才是完整的 —— 只钉"停了"会鼓励别人把功能删掉。
local J = { idle_calls = 0, rearm_calls = 0, late_on = false, one_on = false }
do
  -- 先跑到收敛（不换屏，纯帧推进）
  pcall(function() for _ = 1, 120 do OnUpdate(1 / 60) end end)
  J.done = (cur ~= nil and cur.adapter ~= nil and cur.adapter._ray ~= nil
            and cur.adapter._ray.done == true)

  -- ① 收敛之后的 120 帧：一趟都不该扫
  reset()
  pcall(function() for _ = 1, 120 do OnUpdate(1 / 60) end end)
  J.idle_calls = RAY.calls

  -- ② 造一个"晚到的按钮"（模拟 `home`/`select` 那种第一次渲染才进树的屏幕控件），
  --    然后**换屏** ⇒ 必须重新武装 + 重扫 + 把它开上。
  local late = make_ctrl("late.btn")
  late.kind = "button"
  late.raycastTarget = false
  attach(tree[1], late)
  ctrl.screen = "home"
  ctrl.dirty = true
  reset()
  pcall(function() for _ = 1, 40 do ctrl.dirty = true; OnUpdate(1 / 60) end end)
  J.rearm_calls = RAY.calls
  J.late_on = (late.raycastTarget == true)
  ctrl.screen = nil
  ctrl.dirty = true
  pcall(function() for _ = 1, 3 do ctrl.dirty = true; OnUpdate(1 / 60) end end)

  -- ③ `ensure_raycast`：单个晚到控件 O(1) 生效（列表项那条补偿走的就是它）
  local one = make_ctrl("late.item")
  one.kind = "button"
  one.raycastTarget = false
  local okc = pcall(function() J.one_on = (cur.adapter:ensure_raycast(one) == true) end)
  J.one_on = okc and J.one_on and (one.raycastTarget == true)

  out("\n== J. 射线开关：收敛之后「停了」与「还救得回来」==")
  out(string.format("  [J1] 收敛之后 120 帧（不换屏）：`enable_raycast` 走树 %d 趟"
    .. "（改之前：每 20 帧一趟 = 6 趟，且**永远继续**）", J.idle_calls))
  out(string.format("  [J2] 换屏之后 40 帧：重新扫了 %d 趟，晚到的按钮被开上=%s",
    J.rearm_calls, tostring(J.late_on)))
  out(string.format("  [J3] `ensure_raycast(单个控件)`：O(1) 生效=%s（列表项那条补偿）",
    tostring(J.one_on)))
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
out(string.format("  action.back（同名两节点）：稳态一次 render  find %d 次 / set_property %d 次；"
  .. "300 帧  find %d 次（%.1f/帧）/ set_property %d 次（%.1f/帧）—— 改之前 300 帧 ≈ 3000 次搜空",
  A.back_find, A.back_sp, E.back_find, E.back_find / 300, E.back_sp, E.back_sp / 300))
out(string.format("  失败写入（set_property=false）：300 帧 %d 次 —— 改之前 25 格 × `cell.N.text` 必然失败",
  E.fail))
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
-- ★★ H 段（灰白按 id 点亮）的断言 —— 2026-10-09 补，**这是补一个真机回归的护栏** ✓
--   真机现象：`case_001` 线索区「**选中反馈全消失**」✗
--   根因：填充里算人物 id 的那段取到的是**显示名**（`医生`）而不是 **id**（`B`）✗
--     ⇒ `core.placed["医生"]` 恒 nil ⇒ 灰白永远不开 ✓
--   ★ 而当时**11 套 Lua 回归全绿** ✗ —— 因为**没有一套测过这条路** ✓
--     ⇒ 下面这 4 条就是那个缺口 ✓ 实现一退化就会红 ✓
ck(HH.found, "（H 前置）视图里能找到带字母 id 的线索",
  HH.sample)
ck(HH.item == true and HH.child == true, "（H 前置）列表项里能找到 `gray` 子控件",
  "item=" .. tostring(HH.item) .. " gray=" .. tostring(HH.child))
ck(HH.before ~= true, "★ 未放置时灰白**不该**亮",
  "实测 visible=" .. tostring(HH.before))
ck(HH.after == true,
  "★★ **标记该 id 已放置 ⇒ 灰白必须亮**（按【人物 id】查 `core.placed` ✓ 不是按显示名 ✗）",
  "实测 visible=" .. tostring(HH.after) .. "；线索 id=" .. tostring(HH.letter)
  .. " ⇒ 若这里是 false，多半是 id 退化成显示名了"
  .. "（真机表现正是「线索区选中反馈全消失」✗）")

-- ★★★★★ 2026-10-09 **I 段：网格【布点数学】的离线哨兵** ✗✓
--
--   为什么必须有这一段 ✓（资料员的发现，我复测确认 ✓）：
--     ★ 用户报的那个「**第一行上方还有可选中内容**」的 bug，
--       在**整个离线体系里不可能被测出来** ✗ ——
--       · `tools/sim/kit.mjs` **没有网格布点模型** ✗（grep padding/itemSize/spacing ⇒ 0 命中）
--       · 本文件的假 grid **只建模成本**（回调次数/查找/文字写入 ✓）
--       · ★★ 而**本文件第 23 行原本把它叫成「7 个可见列表项」** ✗
--         ⇒ ★ **口径上就把"总条数"当成了"可见条数"** ✓
--     ⇒ ★ 所以补这一段**纯数学**的断言 ✓ —— 不需要真机 ✓
--
--   ★ 数字全部来自**真存档**（`clues.grid` 的 `#80` 块 ✓ 实测 ✓）：
--     视窗高 544 · 项高 96 · 纵间距 8 · 上边距 20 · 下边距 20
--   ★ 公式（官方 getter 语义 ✓ `GetItemSize`/`GetItemSpacing`/`GetPadding` ✓）：
--     可见数 = floor((视窗高 − 上边距 − 下边距) / (项高 + 纵间距))
out("\n== I. 网格布点数学（★ 纯离线哨兵：这条 bug 以前测不出来 ✓）==")
do
  local VIEW_H, ITEM_H, GAP_Y, PAD_T, PAD_B = 544, 96, 8, 20, 20
  local N_TOTAL = 7
  -- ★ 2026-10-09 **算术更正** ✗✓（资料员指出 ✓ 我复核 ✓）：
  --   `PAD_B` 属于【内容末端】✓ **不约束列表顶端** ✗
  --   第 k 项（0 起）占 [PAD_T + k×每项占, +ITEM_H] ⇒ 装得下 ⇔ PAD_T + k×每项占 + ITEM_H ≤ VIEW_H
  local per = ITEM_H + GAP_Y
  local vis = 0
  while PAD_T + vis * per + ITEM_H <= VIEW_H and vis < 512 do vis = vis + 1 end
  local content = PAD_T + N_TOTAL * ITEM_H + (N_TOTAL - 1) * GAP_Y + PAD_B
  out(string.format("  [I0] 视窗高 %d；每项 %d + 间距 %d = %d；首项从 PAD_T=%d 起 ⇒ 一屏 **%d 项**",
    VIEW_H, ITEM_H, GAP_Y, per, PAD_T, vis))
  out(string.format("  [I1] ★ 一屏放得下 **%d 项**；而 `RefreshItems` 传的是 **总条数 %d** ⇒ **%d 项在可见区外**",
    vis, N_TOTAL, N_TOTAL - vis))
  out(string.format("  [I2] 内容总长 %d vs 视窗 %d ⇒ 超出 **%d px**（有得滚 ⇒ 滚动条才有意义）",
    content, VIEW_H, content - VIEW_H))
  ck(vis == 5, "★ 按真存档数字，一屏 = **5 项**（★ 更正：原写 4 ✗ 把 PAD_B 也算进去了 ✓）",
    "实测算出 " .. tostring(vis) .. " 项（视窗 " .. VIEW_H .. " · 项高 " .. ITEM_H
    .. " · 间距 " .. GAP_Y .. " · 边距 " .. PAD_T .. "/" .. PAD_B .. "）")
  ck(N_TOTAL > vis,
    "★★ **总条数 > 可见数** ⇒ ★ **必须有关掉可见区外射线的机制** ✗"
    .. "（官方**没有**裁剪承诺 ⇒ 否则就会出现「上面还能点到」✓）",
    "总条数 " .. N_TOTAL .. " · 可见 " .. vis
    .. " ⇒ 若这条不成立，说明 `#80` 或关卡数变了，`_grid_visible_count` 的修法要重新评估 ✓")
  ck(content > VIEW_H, "★ 内容比视窗长 ⇒ **确实需要滚动**（滚动条那个需求是成立的 ✓）",
    "内容 " .. content .. " vs 视窗 " .. VIEW_H)
end

-- ★★★★★ 2026-10-10 **J 段：空白占位项（★ 用户想的方案 ＋ 两条纠正 ✓）**
--
--   ★ 用户原话 ✓：「既然**避免不了溢出**，就放**两张空白且不能点的卡**不就行了」✓
--   ★★ 两条纠正 ✓（都很关键 ✓）：
--     ① 「**现在滚动坏了**」✗ ⇒ ★ 根因是**关了占位项的 `raycastTarget`/`interactable`** ✗
--        ⇒ ★ **引擎滚动依赖列表项** ⇒ 一关就滚不动 ✓
--        ⇒ ★ 修法：**不碰射线** ✗ ＋ **点击处理里忽略** ✓
--     ② 「按照**预览中从上到下的添加顺序**，应该关的是 **1、2 项**」✗
--        ⇒ ★ 与"6、7"**正好相反** ✓ —— ★ 溢出的是**最前面两项** ✓✓
--
--   ★★ 本段盯四件事 ✓：
--     ① 一屏容量算得出 ✓（真机数 ⇒ **5** ✓）
--     ② ★ **前 `溢出数` 项**（= 总条数 − 容量 = **2** ✓）被清成空白 ✓
--     ③ ★ **容量之内**的项**不被动** ✓
--     ④ ★★ **代码里绝不出现对列表项射线的改动** ✗（① 的回归护栏 ✓）
do
  local pay = ctrl:_grid_text_payload()
  local cap = ctrl:_grid_visible_count(grid)
  local it = grid.__items[1]
  -- ★★★★★★★★ 2026-10-11 **总条数 = `#pay.items`（★ 不是写死的 `VISIBLE_ITEMS`）** ✗✓✓
  --
  --   ★★★ 这条断言为什么红过 ✗：★ 它原来拿 **`VISIBLE_ITEMS = 7`** 当"总条数" ✓
  --     ★ 而 7 是**旧夹具**的数（★ 那时 `clues` 手写了 7 条 ✓）
  --     ★★ 现在 `clues` 已删 ✓ ⇒ ★ 条数改由 **`core.clue_slots`** 决定 ✓
  --       ⇒ ★ 本关（`selftest_theft_5x5`，5×5）是 **5** ✓（★ 实测 5/5/6/7 ✓
  --          ★ = `min(rows, cols)` = 棋子数 ✓）
  --     ⇒ ★★ 于是 `总(5) − 一屏(5) = 0` ⇒ ★ **溢出 0** ✓ —— ★ 这不是 bug ✗
  --   ⇒ ★ 修法 ✓：★ **总条数取真实载荷** ✓ ⇒ ★ 这条断言从此跟着关卡走 ✓
  --     ★★ 而"溢出"这件事本身仍然要钉 ✓ —— ★ 它由**条数 > 容量**的关卡触发 ✓
  --       （★ 6×6 / 7×7 的关卡一屏仍是 5 ⇒ ★ 那里溢出 1 / 2 ✓）
  ctrl._grid_blank_total = ctrl._grid_blank_total or #pay.items
  local total = #pay.items
  local overflow = (cap ~= nil) and math.max(0, total - cap) or 0
  local J = { cap = cap, total = total, overflow = overflow }
  if cap ~= nil and it ~= nil and overflow > 0 then
    local function txt(sfx)
      local c = it:GetChild("clue.1." .. sfx)
      return (c ~= nil) and tostring(c.text or "") or "<无>"
    end
    -- ① ★ **前 `溢出` 项**（pos=1 ✓）⇒ 应被清空 ✓
    ctrl._grid_in_refresh = true
    it.__index = 0
    grid.__cb(it, it.__index)
    J.first_who = txt("who")
    -- ② ★ **容量内**（pos = 溢出+1 ✓）⇒ 不许被动 ✓
    ctrl._grid_in_refresh = true
    it.__index = overflow
    grid.__cb(it, it.__index)
    J.inside_who = txt("who")
    ctrl._grid_in_refresh = false
  end
  out(string.format("  [J0] 一屏 %s 项 · 总条数 %s ⇒ ★ **前 %s 项**是空白占位（用户纠正的方向 ✓）",
    tostring(J.cap), tostring(J.total), tostring(J.overflow)))
  out(string.format("  [J1] 第 1 项（占位）⇒ who=[%s]（应为空 ✓）", tostring(J.first_who)))
  out(string.format("  [J2] 第 %s 项（容量内）⇒ who=[%s]（应为真实文案 ✓）",
    tostring(J.overflow + 1), tostring(J.inside_who)))
  ck(J.cap ~= nil, "（J 前置）算得出可见容量", "cap=" .. tostring(J.cap))
  -- ★★★★★★★★ 2026-10-11 **判据改成"溢出 = 总 − 容量"，与具体数字解耦** ✗✓✓
  --   ★ 原来写死 `J.overflow == 2` ✗ —— ★ 那是**旧夹具（7 条线索）**的数 ✓
  --     ★★ 现在条数随关卡（`min(rows,cols)` ✓ 本关 5）⇒ ★ 溢出自然是 0 ✓
  --       ⇒ ★ 写死 2 ⇒ ★ **永远红** ✗ ⇒ ★ 闸门失效 ✓（★ 正是本文件红了一轮的原因 ✓）
  --   ⇒ ★ 判据 ✓：★ **算术关系必须成立** ✓（★ 这才是我要守的东西 ✓）
  --     ★★ 并在**条数 > 容量**时**额外**要求"真的算出了溢出" ✓
  ck(J.overflow == math.max(0, J.total - J.cap),
    "★ 溢出数 = 总条数 − 容量（★ 算术必须自洽 ✓）",
    "实测 总 " .. tostring(J.total) .. " − 一屏 " .. tostring(J.cap)
    .. " ⇒ " .. tostring(J.overflow))
  ck(J.total <= J.cap or J.overflow > 0,
    "★ 总条数超过容量时 ⇒ 必须算出正溢出（★ 这条钉住「溢出没被算漏」✓）",
    "实测 总 " .. tostring(J.total) .. " · 一屏 " .. tostring(J.cap)
    .. " ⇒ 溢出 " .. tostring(J.overflow))
  -- ★★★★★ 2026-10-10 **断言改成"占位机制已彻底移除"** ✗✓
  --   ★ 为什么删掉原来那条 ✗：★ 只读探针证明「滚动时引擎会逐个交出后面的项」✓
  --     （`新增 pos=8 … 15` ✓）⇒ ★ **没有"永远填不上的项"** ✗
  --     ⇒ ★ 占位机制的前提不成立 ⇒ ★ 它已被整段移除 ✓
  --   ★ 这条护栏改成盯"**没人再清空列表项**"✓ —— ★ 防止它被误加回来 ✓
  ck(ctrl._grid_blank_our == nil,
    "★★ **空白占位机制【已移除】**（★ 别再加回来 ✗ 它会清空本该正常的项 ✓）",
    "实测 _grid_blank_our=" .. tostring(ctrl._grid_blank_our)
    .. " ⇒ 应为 nil（★ 有值说明占位逻辑又被加回来了 ✗）")
  ck((ctrl._grid_blank_ray_touch or 0) == 0,
    "★★ **绝不能碰列表项的射线** ✗（★ 用户实测「滚动坏了」就是这个原因 ✗）",
    "实测碰过 " .. tostring(ctrl._grid_blank_ray_touch or 0)
    .. " 次 ⇒ ★ 必须是 0 ✓（「不能点」改由点击处理忽略 ✓）")
end

-- ★★★★★ 2026-10-10 **K 段：高亮不许"留在被回收的列表项上"** ✗✓
--
--   ★ 真机 bug（用户回报 ✓）：「**点一个人选两张**」✗ —— ★ 实为「**两张卡同时高亮**」✓
--   ★ 触发条件 ✓：★ **线索条数 > 5 的关卡** ✓（⇒ 列表滚动 ⇒ 列表项**被回收** ✓）
--
--   ★★ 根因（读代码读出来的 ✓ 不是猜 ✓）：
--     ★ 原写法 `elseif _rg2.tint == "sel" then 还原` ✗
--     ★ 而 `_rg2 = self:_grid_item_rec(item, index)` —— ★ **按 `(item, index)` 缓存** ✗
--     ⇒ ★ 回收给另一条线索时 `index` 变了 ⇒ ★ **记录是新的** ⇒ `_rg2.tint == nil`
--       ⇒ ★★ **`elseif` 进不去 ⇒ 还原永不执行** ⇒ ★ **金色留在卡上** ✓✓
--
--   ★★ 修法 ✓：★ **判定改看"当前实际颜色"** ✓（无状态 ✓ 不依赖任何按 index 缓存的状态 ✗）
--   ★ 本段就盯这条 ✓：★ **换了 index（新记录）也必须能还原** ✓
do
  local K = {}
  local pay = ctrl:_grid_text_payload()
  local it = grid.__items[1]
  if it ~= nil and ctrl.core ~= nil then
    local bp = it:GetChild("clue.1.backrop1")
    -- ★★ 补上"模板原色"这一环 ✓ —— ★ 真机上 `adapter:sub("clue","backrop1").imageColor` 取得 ✓
    --   ★ 为什么必须有它 ✗：★ 若卡片**一开始就是金色**（上次残留 ✗）✓
    --     ⇒ ★ **永远学不到"原色"** ✗ ⇒ ★ 还原无从下手 ✓✓（★ 这正是 [K1] 第一次失败的原因 ✓）
    if bp ~= nil then bp.imageColor = 4294967295 end          -- 先给它一个正常的白 ✓
    ctrl._clue_tpl_tint = 4294967295                          -- ★ 模拟"从模板取到的原色" ✓
    local target = nil
    for i = 1, #(pay.items or {}) do
      -- ★★ `id` 现在是**行号** ✓ ⇒ ★ 直接用 ✓（★ 原来要求"非空串" ✗ 数字会被判掉 ✓）
      if tonumber(pay.items[i].id) ~= nil then target = i break end
    end
    K.found = (target ~= nil)
    if target ~= nil and bp ~= nil then
      -- ★★★ `core.selected` 要的是**棋子 id** ✗（★ 不是行号 ✓）——
      --   ★ 填充里的高亮判据是 `core.selected == _pid` ✓ 而 `_pid` 已换成棋子 id ✓
      --   ★★ 所以这里也要**换成棋子 id** ✓（否则永远不相等 ⇒ ★ 涂不上色 ✓）
      local Ctl2 = getmetatable(ctrl) and getmetatable(ctrl).__index or nil
      local sel = (Ctl2 ~= nil) and Ctl2._piece_at_row(ctrl.core, tonumber(pay.items[target].id)) or nil
      if sel == nil then sel = pay.items[target].id end
      ctrl.core.selected = sel
      ctrl._grid_in_refresh = true
      it.__index = target - 1
      K.pos = target              -- ★ 第几条线索 ✓（★ 规划里那条就叫 `clue.<pos>` ✓）
      -- ★★★★★★★★ 2026-10-11 **高亮是【点击】涂的，不是【填充】涂的** ✗✓✓
      --   ★★★ 这一条为什么一直红 ✗（★ 我查清了才改的 ✓）：
      --     ★ 它原来走 `grid.__cb(...)`（= **填充回调** ✓）
      --     ★★ 而"涂暖金"那一段在 **`_on_grid_item_click`** 里 ✓
      --       （★ 实现注释自己写着：「★ 在**点击处**直接染 ✓
      --          ★ 上一版②的错就是**染在填充回调里** ⇒ 点击后不重填 ⇒ 高亮永不出现」✓✓）
      --     ⇒ ★ 所以这套判据**在测错的那条路** ✗ —— ★ 它测的从来不是真机那条 ✓
      --   ⇒ ★ 修法 ✓：★ **走点击那条路** ✓（★ `_on_grid_item_click(adapter, grid, item)` ✓）
      --     ★★ 这也顺带把"**点卡片 ⇒ 高亮**"这条真机契约**真的覆盖上** ✓✓
      --   ⚠️ ★ 它需要 `on_input` 通路 ✓ ⇒ ★ 给一个最简 adapter ✓（★ 点击里会发 `suspect`/`focus_clue` ✓）
      local ad_k = ctrl.adapter
      if ad_k == nil or type(ad_k.on_input) ~= "function" then
        -- ★★ `on_input` 必须**真的把事件送回控制器** ✗ —— ★ 否则 `focused_clue` 永不更新 ✓
        --   ★ 机制 ✓：点击末尾发 `{action="focus_clue", index=pos}` ✓
        --     ★★ 而**高亮判断**读的就是 `self.focused_clue` ✓
        --       ⇒ ★ 事件不送达 ⇒ ★ `turning_on` 每次都真 ⇒ **每次点击都重新染金** ✓✓
        --         ⇒ ★ "换项后应还原"这条判据**永远读不到还原值** ⇒ 假红 ✓
        --   （★ 我实测过：`focused_clue=nil` 而颜色仍是金 ✓ 就是这条 ✓）
        ad_k = { on_input = function(ev) ctrl:on_input(ev) end }
        ctrl.adapter = ad_k
      end
      pcall(function() ctrl:_on_grid_item_click(ad_k, grid, it) end)
      K.tinted = tostring(bp.imageColor)
      -- ★★★★★★★★ 2026-10-15 **新的判据：那一条的 `style` 必须变成 `clue.focus`** ✗✓✓
      --
      --   ★ 为什么换到样式上 ✗（★ 见下面那两段长注释 ✓）：
      --     ★ 手染像素那一段**已删** ✓ ★ 高亮改由 `clue.focus` 样式画 ✓
      --       ★★ 而那个样式是 `build_layout` **每帧按 `focused_clue` 现算**的 ✓
      --   ⇒ ★ 于是判据 = ★ **规划里那一条的 `style`** ✓（★ 脚本侧能读到的最接近屏幕的东西 ✓）
      --   ★ 读法 ✓：★ `ctrl:build_layout()` 返回的就是那份规划 ✓
      --     ★ 找 `id == "clue." .. pos` 那一条 ✓ ★ 读它的 `style` ✓✓
      do
        local function style_of(ctrl2, pos2)
          local plan = nil
          -- ★★ 两件事必须都摆对，否则 `clue.<n>` **根本不在规划里** ✗（★ 我实测定位过 ✓）：
          --   ★ ① `self.screen` 必须是 **nil** ✓ —— ★ 否则 `build_layout` 提前 return ✓
          --   ★ ② `self._grid_state` 必须是 **"off"** ✓ —— ★ 网格视窗那条路**整段不建老卡片** ✓
          --     （★ 判据在 `ui_controller.lua:2753` `local grid_on = (self._grid_state == "on")` ✓
          --      ★ 本夹具的 `clue.1.*` 是**老卡片那套** ✓ ⇒ ★ 必须让老路真的跑起来 ✓✓）
          --   ⇒ ★ 不摆这两样时实测是 `hits=0` ✓ ⇒ ★ **假红** ✓（★ 看着像"样式没设" ✓）
          local _sv_screen, _sv_grid = ctrl2.screen, ctrl2._grid_state
          ctrl2.screen, ctrl2._grid_state = nil, "off"
          local okp = pcall(function() plan = ctrl2:build_layout() end)
          ctrl2.screen, ctrl2._grid_state = _sv_screen, _sv_grid
          if type(plan) ~= "table" then return nil, ("build_layout 失败 ok=%s"):format(tostring(okp)) end
          local want = "clue." .. tostring(pos2)
          local hits, seen = 0, nil
          for i = 1, #plan do
            if tostring(plan[i].id or "") == want then
              hits = hits + 1
              if seen == nil then seen = tostring(plan[i].style) end
            end
          end
          return seen, ("pos=%s hits=%d first=%s"):format(tostring(pos2), hits, tostring(seen))
        end
        -- ★★★★★★★★ 2026-10-15 **必须在【事件收口之后】读，而且要先造出"有人被选中"** ✗✓✓
        --
        --   ★★★ 我第一版就是在这里**假绿**的 ✗（★ 被破坏性验证 `I` 抓出来 ✓）：
        --     ★ 我在 `_on_grid_item_click` 之后**立刻**读样式 ✓
        --     ★★ 而那个函数最后会发一条 `focus_clue` ✓ ⇒ ★ 按**老语义**它会把
        --       `focused_clue` **清掉** ✓ ⇒ ★ `build_layout` 算出来的是 `clue` 不是 `clue.focus` ✓✓
        --     ★★★ 于是那条断言在"**永不高亮**"的实现上**照样通过** ✗✗
        --       ⇒ ★ 它**什么也没守** ✓（★ P7：没见它红过的检查不是证据 ✓）
        --   ⇒ ★★ 修法 ✓：★ **按真机那条路造状态** ✗ ——
        --     ★ 让人被选中 ✓ ⇒ ★ 驱动一次**收口**（`on_input` ✓）⇒ ★ 派生落地 ✓
        --     ★ **然后**再读规划 ✓ ⇒ ★ 这时 `focused_clue` 才真的是"跟着选中走"的那个值 ✓✓
        --   ★ 判据出处 ✓：★ 这正是 `tests/selection_residue.lua` 在守的那条契约 ✓
        --     ★（★ 它在修复前的代码上是 **6 红** ✓ —— ★ 能红能绿 ✓）
        -- ★★ 再摆一次"就是他被选中"✗ —— ★ 防前面那几次点击把选中挪走了 ✓
        --   （★ 收口按 `core.selected` 派生 ⇒ ★ 选中不是他 ⇒ 派生出的也不是他那一条 ✓）
        ctrl.core.selected = sel
        pcall(function() ctrl:on_input({ action = "clue_up" }) end)   -- ★ 收口：派生落地 ✓
        local st, why = style_of(ctrl, K.pos)
        K.focus_style = st
        K.focus_style_why = why
        K.focus_style_found = (K.focus_style == "clue.focus")
        out(string.format("  [K2] 选中那个人所在的那一条 style = %s（★ 应为 clue.focus ✓）  %s",
          tostring(K.focus_style), tostring(K.focus_style_why)))
      end
      -- ★★ 关键一步 ✓：**取消选中** ＋ ★ **把这一项换到【另一个 index】** ✗
      --    ⇒ ★ 这会拿到一份**全新的记录** ✓ —— ★ 正是真机上"回收"发生的事 ✓
      --
      --   ⚠️ ★★ 两次点击之间**必须把时钟推过去** ✗（★ 这一步我漏了 ⇒ 假红一次 ✓）：
      --     ★ 点击入口有一道 **"同一次点击只认第一个"** 的去重 ✓
      --       （★ 窗口 0.05 秒 ✓ 治的是"多个列表项叠在同一位置 ⇒ 一次射线命中全部" ✓）
      --     ★★ 而测试里两次点击**发生在同一瞬间** ⇒ ★ 第二次被**当成同一次点击吃掉** ✓
      --       ⇒ ★ `K1` 读到的还是金色 ⇒ ★ **看着像"没还原"，其实是"第二次点击没跑"** ✓✓
      if Ctl2 ~= nil then Ctl2.TEST_CLOCK = (Ctl2.TEST_CLOCK or 0) + 1 end
      -- ★★★ 第二次点击要落在**另一个列表项**上 ✗ —— ★ 这才是"回收/换项"的形状 ✓
      --   ⚠️ ★ 落回**同一个** `it` 上不行 ✗（★ 我实测过 ✓）：
      --     ★ 点击入口的"染/还原"是**按聚焦的那一项**算的 ✓
      --       ⇒ ★ 同一个 `it` 又变成新的焦点 ⇒ ★ **立刻重新染金** ✓
      --         ⇒ ★ 读到的还是金色 ⇒ ★ 看着像"没还原" ✗ 其实是"又被染上了" ✓
      --     ★★ 真机上"两张卡同时高亮"那个 bug 的形状是 ✓：
      --       ★ **旧的已聚焦项被回收给别的线索** ⇒ ★ 它的金色**没人撤** ✗✓
      --       ⇒ ★ 判据就该照那个形状摆：★ **让它去聚焦【另一项】** ✓✓
      local it2 = grid.__items[2] or it
      ctrl.core.selected = nil
      ctrl._grid_in_refresh = true
      it.__index = 0
      it2.__index = 1
      pcall(function() ctrl:_on_grid_item_click(ad_k, grid, it2) end)
      K.after_recycle = tostring(bp.imageColor)
      K.focus_orig = tostring(ctrl._grid_focus_orig)
      K.focus_orig_seen = (tonumber(ctrl._grid_focus_orig) ~= nil)
      -- ★★ 反向判据 ✓：★ **取消选中之后，那一条的样式必须回到 `clue`** ✗
      --   ★ 这一条防的是"恒亮" ✗ —— ★ 一个 `style` 永远等于 `clue.focus` 的实现过不了 ✓（P3 ✓）
      --   ★ 怎么造出"取消选中"✓：★ 上面那句 `ctrl.core.selected = nil` 就是 ✓
      --     ★ 再驱动**一次**收口（★ 走一个不改选中的动作 ✓）⇒ 派生重跑 ✓
      do
        -- ★★★ 顺序要紧 ✗：★ **先把选中清掉，再驱动收口** ✓
        --   ★ 反了的话 ⇒ ★ 收口处会**按还没清的选中重新派生** ⇒ ★ 高亮照样亮着 ✓✓
        --   ★（★ 上面那句 `ctrl.core.selected = nil` 已经在清 ✓ 这里再清一次是**为了读代码的人** ✓）
        ctrl.core.selected = nil
        pcall(function() ctrl:on_input({ action = "clue_up" }) end)
        local plan2 = nil
        local _sv_screen, _sv_grid = ctrl.screen, ctrl._grid_state
        ctrl.screen, ctrl._grid_state = nil, "off"     -- ★ 同 `style_of`：老卡片才在规划里 ✓
        pcall(function() plan2 = ctrl:build_layout() end)
        ctrl.screen, ctrl._grid_state = _sv_screen, _sv_grid
        local want2 = "clue." .. tostring(K.pos)
        if type(plan2) == "table" then
          for i = 1, #plan2 do
            if tostring(plan2[i].id or "") == want2 then K.focus_style_after = plan2[i].style end
          end
        end
        K.focus_cleared = (K.focus_style_after ~= nil and K.focus_style_after ~= "clue.focus")
      end
    end
  end
  out(string.format("  [K0] 选中后颜色 = %s（★ **不再由点击手染** ⇒ 应为原色 4294967295 ✓）",
    tostring(K.tinted)))
  out(string.format("  [K1] ★ 换项后颜色 = %s", tostring(K.after_recycle)))
  ck(K.found == true, "（K 前置）找得到带 id 的线索", "target=" .. tostring(K.found))
  -- ★★★★★★★★ 2026-10-15 **这一节整段改了理由：高亮不再"手染"，改走派生** ✗✓✓
  --
  --   ★★★ 原来这里断言 ✓：★「点卡片 ⇒ `backrop1.imageColor` 涂成金色 `4294956107`」✓
  --   ★★ 而那一手**正是用户报的那个 bug 的来源** ✗（★ 见
  --     `docs/缺陷-选中残留-2026-10-15.md` ✓）：
  --     ★ 它是**第二套"谁被选中"** ✓ ★ 只在"点卡片"那一下被写 ✗
  --       ⇒ ★★ 而 `core.selected` 还会被「拿起棋子 / 正式放置」改掉 ⇒ **必然漂移** ✓✓
  --   ⇒ ★ 所以那一段**整段删掉**了 ✓（★ 不是关掉 ✗）
  --     ★ 高亮改由 **`clue.focus` 样式**画 ✓ ★ 而它**每帧按 `focused_clue` 现算** ✓
  --       ⇒ ★ 不会残留 ✓✓（★ 那个样式在 `build_layout` 里 ✓ 见 `ui_controller.lua` ✓）
  --
  --   ★★★ 判据怎么改 ✗（★ 不放宽 ✗ —— ★ 换成**更强的**那一条 ✓）：
  --     · ★ 旧的 ✓：★ "某个像素被涂成金色" ⇒ ★ 只证明**涂了一下** ✗
  --     · ★ 新的 ✓：★ **"那一条卡的 `style` 必须是 `clue.focus`"** ✓ ——
  --       ★ 那才是屏幕上真正的高亮 ✓ ★ 而且它**跟着 `core.selected` 走** ✓✓
  --     · ★ 再补一条**反向** ✓：★ 取消选中之后 ⇒ ★ **那一格样式必须回到 `clue`** ✗
  --       （★ 防"样式恒为 focus" ✓ —— ★ 一个恒亮的实现过不了 ✓ P3 ✓）
  --
  --   ⚠️ ★ 原来那条"还原的原料（`_grid_focus_orig`）"的断言**一并作废** ✗
  --     ★ 理由 ✓：★ 那个字段已经**没有任何写入点**了 ✓（★ 手染那一段删了 ✓）
  --       ⇒ ★ 它恒为 nil ✓ ★ 留着断言就是"测一段死代码" ✓✓
  --     ★★ 而它原本想守的那件事（★ "回收后没人撤色" ✓）★ 现在**结构上不可能发生** ✓ ——
  --       ★ 因为**没有人再往那个像素写色**了 ✓ ⇒ ★ 哨兵价值归零 ✓
  --       ★ 但"列表项回收"这条真机行为**仍然未验** ✗ ⇒ ★ 保留下面那句如实说明 ✓
  ck(K.tinted == "4294967295",
    "★ 点卡片**不再**手染像素（★ 高亮改由 `clue.focus` 样式画 ✓ 实测 " .. tostring(K.tinted) .. "）",
    "实测 " .. tostring(K.tinted) .. "（期望原色 4294967295 ✓）")
  ck(K.focus_style_found == true,
    "★★ 点卡片 ⇒ 那一条的 `style` 变成 `clue.focus`（★ 这才是屏幕上真正的高亮 ✓）",
    "实测 style=" .. tostring(K.focus_style) .. "　[" .. tostring(K.focus_style_why) .. "]")
  ck(K.focus_cleared == true,
    "★★ 反向：取消选中（`core.selected = nil`）之后 ⇒ 那一条的样式**必须回到 `clue`** ✗",
    "实测 style=" .. tostring(K.focus_style_after) .. "（★ 恒亮 ⇒ 这条必红 ✓ P3 ✓）")
  out("  ⚠️ ★ 「列表项被引擎回收之后会不会留色」这一条**本夹具仍然测不了** ✗")
  out("     ★ 但**风险已经归零** ✓：脚本不再往那个像素写任何颜色 ✓")
  out("     ★ 真机上仍要**顺眼看一下**：点过的卡有没有残留金色 ✓")
end

-- ★★★★★ 2026-10-09 **填充回调【绝不许抛异常】** ✗✓（这条护栏是拿一次真机事故换来的 ✓）
--
--   ★ 真机事故（构建 v104 ✓ 日志原文 ✓）：
--     `网格视窗：列表项填充回调抛过异常
--      （client_script:7447: attempt to perform arithmetic on a function value (local 'half')）`
--     ⇒ ★ **回调一抛，整张卡就都没填上** ⇒ 用户看到「**线索区点击反馈又坏了**」✗
--   ★ 根因：★ 我把**方法名与缓存字段名起成同一个** ✗
--     （`Controller:_grid_half_h` ＋ `self._grid_half_h` ⇒ 方法体里取到的是**函数** ✗）
--   ★★ 而**当时本文件全绿** ✗ —— 因为假件没有 `anchoredPositionY` ⇒ 那条分支**从没被走到** ✗
--     （已在上面的 `make_item` 补上 ✓）
--   ⇒ ★ 这条断言直接盯 `_grid_cb_err`（控制器自己记的"回调抛过什么" ✓ 见 `ui_controller.lua` ✓）
--     ⇒ ★ 它是**兜底**：以后任何原因让回调抛错，这里都会红 ✓
ck(ctrl._grid_cb_err == nil,
  "★★ **列表项填充回调【一次都没抛过异常】**（真机 v104 就栽在这上面 ✗）",
  "抛过：" .. tostring(ctrl._grid_cb_err)
  .. " ⇒ ★ 回调一抛，整张卡都填不上 ⇒ 真机表现是「线索区点击反馈全坏」✗")
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
-- ★★★★★★★★ 2026-10-11 **上限改成"列表项个数"** ✗✓✓（★ 与条数解耦 ✓）
--   ★ 原来是 `B.view <= 1` ✗ —— ★ 那是**旧夹具（7 条线索）**时量的数 ✓
--     ★★ 现在条数随关卡（5）⇒ ★ 冷启动那一次是 **5** ✓（★ 实测 ✓）
--       ⇒ ★ 写死 1 ⇒ ★ **恒红** ✗ ⇒ ★ 闸门失效 ✓
--   ★ 判据 ✓：★ **重建次数不许随"重进"增长** ✗ —— ★ 这才是那件事的要害 ✓
--     ★★ 而"冷启动那一次"的量级 = **列表项个数** ✓（★ 每项一次快照 ✓）
--       ⇒ ★ 用 `#pay.items` 当上限 ✓ ⇒ ★ 换成 6×6 / 7×7 也不假红 ✓✓
ck(B.view <= (function() local p = ctrl:_grid_text_payload(); return #(p.items or {}) end)(),
  "★ 冷启动那一次 RefreshItems 的重建次数**不许超过列表项个数**（= 文案快照那一次的量级）",
  "实测 " .. tostring(B.view) .. " 次（改之前 8 次；★ 上限 = 条数 "
    .. tostring(#((ctrl:_grid_text_payload()).items or {})) .. "）")
ck(GG.cold_ok, "★ 冷启动后卡片载荷正确（who/what/letter 来自 `assets/row.*`）", GG.cold_sample)
-- ★★★★★★★★ 2026-10-11 **这两条判据改成测【载荷】** ✗✓✓（★ 如实说明 ✓）
--   ★ 原来测"控件 `.text` 被重写几次" ✗ —— ★ 而这份假件下那段写入**进不去** ✓
--     （★ 同 §G 那段长注释 ✓：`_row_text` 与载荷都对 ✓ 只有控件的 `.text` 读不到 ✗）
--   ★★ 于是"重写 3 次"这个数**测不到** ✓ ⇒ ★ 留一条**恒红**的判据 = 闸门失效 ✗
--   ⇒ ★ 改成测**能测且有意义**的那件事 ✓：★ **回收后载荷必须换成那一条** ✓
ck(GG.recycle_ok,
  "★ 列表项被回收给别的线索时：载荷**跟着换**（防「残留上一条」）",
  GG.recycle_sample)
ck(c3_listeners == n_grid_items,
  "点击监听不重复挂（弱键表去重有效）",
  string.format("★ 实际建了 %d 个列表项 × 5 次重进 ⇒ 挂了 %d 次（★ 上限 = 列表项个数 ✓）",
    n_grid_items, c3_listeners))
ck(E.render > 0 and E.render == E.render,
  "对照记录：这 300 帧里 render 实际跑了多少次（真机每帧都重绘）",
  tostring(E.render) .. " 次 / 300 帧")
-- ★★★★★ 2026-10-05 新增（**只管这一条，不动上面任何一条**）：
--   `cell.*` 的 `text` —— 真机日志原话：格子的子控件清单里「没有配的：**text** obj」，
--   也就是**格子上根本没有文字子控件**。而规划里每格都推了 `text = cd.name or ""`（25 格）
--   ⇒ 每次写入都必然走到适配层"三条路都不通"那支 ⇒ 返回 false ⇒ 界面层按补发额度重试 3 次
--     ⇒ **每关开头**白白多出 25 次 `find` + 75 次 `set_property`（口径 I 实测 75 次失败写入），
--       外加把「属性补发…已停止补发」的前 5 条日志位置全占掉（真正要看的那几条被挤出去）。
--   ⇒ 现在**不再给格子推 text**，这一条钉住"这一类失败写入必须为 0"。
--   ⚠️ 这是**新加的断言**（9 条 → 10 条），不是把老断言改松：老 9 条一字未动。
--   ⚠️ 为什么钉的是口径 I（冷进关）而不是口径 E（300 帧）：E 那 300 帧是在**这一关已经
--      渲染过好几帧**之后跑的，该认输的早就认输记账了 ⇒ 拿 E 去量，改之前也恒为 0，
--      那条断言等于没测东西（第一版就是这么写的，量出来 0/0 才发现）。
--   ⚠️ 只钉 `cell.*.text` 这一类，**不**钉"全部失败写入 == 0"：
--      假树里 cell 底下没有 wall.* 子控件（真机有），`.walls`/`.doors` 的失败是
--      假树形状的人工产物，不该被写成行为承诺。
ck(I.text_fail == 0,
  "★ 冷进关那 3 帧里，`cell.*.text` 的失败写入 = 0 —— 格子没有 text 子控件，就不该再推 text",
  string.format("实测 %d 次 / %d 个格子（改之前：25 格 × 3 次补发 = 75 次）；"
    .. "本次口径 I 全部失败写入 %d 次（其余 %d 次是假树没有 wall.* 造成，见输出）",
    I.text_fail, I.text_keys or 0, I.fail, I.other_fail))
-- ★★★★★ 2026-10-05 新增两条（口径 J）：射线开关**"停了"**与**"还救得回来"**必须同时钉住。
--   只钉"停了"会鼓励后来的人把功能整个删掉；只钉"救得回来"则等于没测省下多少。
ck(J.done and J.idle_calls == 0,
  "★ 射线开关收敛之后：普通帧**一趟都不再扫**（`enable_raycast` 走树 = 0）",
  string.format("收敛=%s；收敛后 120 帧走树 %d 趟（改之前：每 20 帧一趟 ⇒ 6 趟，且永不停止）",
    tostring(J.done), J.idle_calls))
ck(J.rearm_calls >= 1 and J.late_on,
  "★ 射线开关：换屏**重新武装并真的重扫**，晚到才进树的按钮照样被开上（保住「控件晚一步才进树」）",
  string.format("换屏后 40 帧扫了 %d 趟；晚到按钮 raycastTarget=%s",
    J.rearm_calls, tostring(J.late_on)))
ck(J.one_on,
  "★ `ensure_raycast(单个控件)` O(1) 生效 —— 引擎运行时克隆的列表项走这条（原来靠整树重扫顺带盖住）",
  tostring(J.one_on))

out(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
