--[[----------------------------------------------------------------------------
  tests/selection_residue.lua —— **选中残留**（★ 真机报的两个症状的回归 ✓）

  用户原话（2026-10-15 ✓）：
    ①「**放置 v 后选择了 d，一不小心把 v 取消了，
        点出来的标记是 v 的，但显示选择的 d，
        此时再长按放置，放的会是 v**」✗
    ②「**出现过 d 有选中高亮但没有选中行为的情况**」✗

  ── 判据（★ 两向 ✓ 见 P3）────────────────────────────────────────────────

  症状的本质是一句话：**卡片高亮 ≠ 真正选中**。
  所以本文件把"屏幕说的"与"行为实际用的"**同时**钉住，两边都要对：

    · 屏幕（高亮）  = `focused_clue`（★ 它就是 `clue.focus` 样式的唯一输入 ✓）
    · 行为（选中）  = `core.selected`（★ `hold_cell` / `tap_cell` 只认它 ✓）

  单向断言的问题 ✗：★ 只断言"高亮 = 某值"⇒ 一个**从不高亮**的实现也能过 ✓
  ⇒ 所以每一条都是「**该亮的亮了 ∧ 该灭的灭了**」✓

  ── 机制 ────────────────────────────────────────────────────────────────

  高亮在 2026-10-15 之后是**派生值** ✓：`focused_clue` = 选中那个人配在第几行 ✓
  派生点只有一个 ✓：`Controller:_sync_clue_focus`（★ 在 `on_input` 收口处调 ✓）
  ⇒ 本文件**故意只用手势驱动**（不直接写 `focused_clue`）✓
    —— ★ 直接写它就是"又造一份状态" ✗ 那样测不出真机那条路 ✓

  跑法：lua tests/selection_residue.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL  " .. msg) end
end

-- ── 时间：与真机一样一帧一帧地过（★ 累加 `dt` ✓ 不乘任何系数 ✗）────────────
local CLK = 0
local function reset_clock() CLK = 0; UIC.TEST_CLOCK = 0 end
local function advance(c, seconds)
  local step = 1 / 60
  local left = seconds
  while left > 1e-9 do
    local d = (left > step) and step or left
    left = left - d
    CLK = CLK + d
    UIC.TEST_CLOCK = CLK
    c:tick(d)
  end
end

-- ── 手势（★ 全部走真机那条路 ✓ 一个字都不直接写状态 ✗）──────────────────
local function long_press(c, r, cc)
  reset_clock()
  c:on_cell_down(r, cc, 100, 100)
  advance(c, 0.45)
  local okp = c:on_cell_up(r, cc, 100, 100)
  c:on_input({ action = "click", r = r, c = cc })   -- 长按后尾随的那次点击（被抑制 ✓）
  return okp
end
local function tap_cell(c, r, cc)
  c._suppress_click = nil
  -- ★★★ 同 `tap_card` 的理由 ✓：★ 清掉"同一次点击只认第一个"那道闩 ✗✓
  --   ★★ 不清的后果（★ 本轮实测踩到 ✓）：★ `tap_card` 刚记过 `_grid_click_at` ✓
  --     ★ 紧接着 `tap_cell` 落在 **CPU 时间 0.05 秒**以内
  --       ⇒ ★★ **"拿起棋子"这一次点击被静默丢掉** ✓ ⇒ ★ 选中**根本没变** ✓✓
  --     ★ 症状 ✓：★ 看着像"高亮没跟着走" ✗ ★ 其实**那一步压根没发生** ✓
  --   ★ 真机上这两下之间隔的是**人的手指** ✓（★ 远大于 0.05 秒 ✓）⇒ ★ 清掉才是对的 ✓
  c._grid_click_at = nil
  c:on_input({ action = "click", r = r, c = cc })
end
local function undo(c) c:on_input({ action = "undo" }) end

-- ── 一个新控制器（★ 与 `input_logic.lua` 同一个造法 ✓）──────────────────
local lv = require("levels.case_001")

-- ★★★★★★★★ 2026-10-15 **把「点卡片」摆成真机那条路** ✗✓✓
--
--   ★★ 为什么不能只发一个 `suspect` 了事 ✗（★ 这正是"假绿"的来源 ✓）：
--     ★ 真机上点一张卡要经过 **`_on_grid_item_click`** ✓（`ui_controller.lua` ✓）
--       ★ 而它做的事**不止选人**：★ 它还判"要不要取消"、还要发 `focus_clue` ✓
--       ★★ 少走这一段 ⇒ ★ **被测的东西不是真机那个** ✗（P2 ✓）
--     ★★★ 实证 ✓：只在"发一个 `suspect`"的版本上跑，
--       ★ **修复前的代码也能过** ✗ —— 因为那条路绕开了有缺陷的那一段 ✓✓
--   ⇒ ★ 所以这里**照 `tests/clue_slots.lua` 的造法**搭一份最小控件树 ✓：
--     ★ `root` → `assets` → `row.<关>.<行>`（`who`/`what`/`letter`/`face`）✓
--     ★ 再走 `_fill_grid_item` 把单射**真的落一次账** ✓
--     ★ 然后**调 `_on_grid_item_click`** ✓ ⇒ ★ 与真机同一条路 ✓✓
local function ctrl(name, kids, text)
  local x = { name = name, _kids = kids or {} }
  if text ~= nil then x.text = text end
  x.GetChildren = function() return x._kids end
  x.FindChild = function(_, n)
    for _, k in ipairs(x._kids) do if k.name == n then return k end end
    return nil
  end
  x.GetChild = x.FindChild
  return x
end

-- 给一个控制器把 `row.*` 与卡片都摆好（★ 与真机同构 ✓）
--   ⚠️ ★ 控件名里的 `<关>` 必须是 **`self:_level_ordinal()`** ✗（★ 不是写死的 1 ✓）
--     ★ 实证 ✓：★ `case_001` 在注册表里排第 **2** ⇒ ★ `row.1.*` 一个都查不到 ⇒
--       ★★ 单射**一条都不落账** ⇒ ★ `_person_id_for_pos` 落回兜底 ✓✓
--       （★ 这是本项目踩过多次的"名称对不上 ⇒ 静默不生效"同型 ✓）
local function build_rows(c)
  local core = c.core
  local nslot = #core.pieces
  local lvno = c:_level_ordinal()
  local rows = {}
  for pos = 1, nslot do
    local id = tostring(core.pieces[pos].id)
    rows[pos] = ctrl("row." .. lvno .. "." .. pos, {
      ctrl("who." .. lvno .. "." .. pos,    { ctrl("who",    {}, id) }),
      ctrl("what." .. lvno .. "." .. pos,   { ctrl("what",   {}, "文" .. pos) }),
      ctrl("letter." .. lvno .. "." .. pos, { ctrl("letter", {}, string.upper(id)) }),
      ctrl("face." .. lvno .. "." .. pos,   { ctrl("face",   { ctrl("img", { imageId = 900 + pos }) }) }),
    })
  end
  _G.game = { GetClientUIRoots = function() return { ctrl("root", { ctrl("assets", rows) }) } end }
  -- ★ 与真机同一条落账路 ✓（★ 用 `_grid_in_refresh` 区分"我们那趟" ✓ 见实现注释 ✓）
  c._grid_in_refresh = true
  for pos = 1, nslot do
    local card = {}
    for _, nm in ipairs({ "who", "what", "letter", "face" }) do
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { ctrl(nm, {}) })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", card), pos - 1)   -- ★ index 0 起 ✓（引擎口径 ✓）
  end
  c._grid_in_refresh = false
  return rows
end

-- ★★★★★★★★ 2026-10-15（第二轮）**列表项：真机上高亮【真正】长在上面的那个东西** ✗✓✓
--
--   ★★★ 为什么第一轮的用例没抓到"没修好" ✗（★ 这一条是本轮最该记的教训 ✓）：
--     ★ 第一轮只断言了**老卡片**的 `clue.focus` 样式 ✓
--     ★★ 而真机 `_grid_state == "on"` ⇒ ★ **老卡片整段不进规划** ⇒
--       ★★ **那条断言在真机上是空的** ✗✓ ★ 它守的是一个真机根本读不到的值 ✓
--     ⇒ ★★ 于是"6 红 → 0 红"全是**模拟器那条路**上的 ✓ ★ 真机那条**一条都没覆盖** ✓✓
--   ⇒ ★ 修法 ✓：★ **照真机那样造列表项** ✓ ★ 断言 `backrop1.imageColor` ✓
--     ★（★ 那就是用户看得见的那张卡 ✓ ★ 也是原来的手动染色写的同一个控件 ✓）
--   ★ 造法 ✓：★ 与 `tests/grid_cost.lua` 的 K 段同一条 ✓（★ 它已经证明这条路能跑起来 ✓）
--     ★ 每个 item 的子控件要**带 `clue.<pos>.<槽位>` 与短名两份** ✓
--     ★ 因为填充两侧都试：★ 先 `FindChild("clue.N.who")` ✓ 再 `FindChild("who")` ✓
-- 造一个最小网格视窗（★ 只要填充与定位能跑 ✓ 不需要真的滚动 ✓）
local function build_grid(c)
  local nslot = #c.core.pieces
  local items = {}
  for pos = 1, nslot do
    local card = {}
    for _, nm in ipairs({ "who", "what", "letter", "face", "backrop1", "backrop2" }) do
      -- ★★★ 形状必须与真机一致 ✗✓：★ **`item:GetChild("clue.N.backrop1")` 拿到的
      --   【就是那个图片控件本身】** ✓（★ 存档实证 ✓：`backrop1` 父=`clue` ✓ 尺寸 360x96 ✓）
      --   ★★ 而它**不必**再往下钻一层去找同名的东西 ✗
      --     ★ 我第一版把它套成「外层容器 + 内层同名叶子」⇒ ★★
      --       ★ **写的人写外层、读的人读内层** ⇒ ★ 两边不是同一个表 ⇒ **永远读不到** ✓✓
      --     ★ 症状 ✓：★ 回读恒 `nil` / 恒原色 ⇒ ★ 看着像"填充没画" ✗ 其实是**夹具形状不对** ✓
      --   ★ 真机那边的对应事实 ✓：★ 图片控件有 `imageId` / `imageSource` ✓
      --     ★ 而"设图"要 `SetImage` ✓ —— ★ 那是**单射**那条路的事 ✓
      --     ★ 本节的 `imageColor` 是**读写字段** ✓（★ 适配层注释：乘算着色 ✓）⇒ ★ 直接赋值 ✓
      local leaf = ctrl("clue." .. pos .. "." .. nm, {})
      leaf.imageColor = 4294967295            -- ★ 原色（白）✓ —— 与真机模板一致 ✓
      card[#card + 1] = leaf
    end
    items[pos] = ctrl("item", card)
    items[pos].__index = pos - 1              -- ★ 引擎 index 0 起 ✓
  end
  c._grid_base = 0
  c._grid_state = "on"                        -- ★ 真机就是这个 ✓
  c._grid_seen = {}
  c._grid_in_refresh = true
  for pos = 1, nslot do
    c:_fill_grid_item(nil, nil, items[pos], pos - 1)
  end
  c._grid_in_refresh = false
  c.__grid_items = items            -- ★ 点卡片时要用**真的那一个** ✓（见 `tap_card` ✓）
  return items
end

-- 取某一条卡上 `backrop1` 的当前颜色（★ 用户看得见的那一笔 ✓）
--   ★ 取法与**写的人同源** ✗：★ 实现里走 `_grid_item_child(item, index, pos, "backrop1")`
--     ⇒ ★ 先 `item:GetChild("clue.<index>.<suffix>")` ✓ 再 `clue.<pos>.<suffix>` ✓ …
--   ★★ 这里就用**同一个入口**读 ✓ —— ★ 别自己另拼一个名字 ✗
--     （★ 我第一版自己多钻了一层 ⇒ ★ 读的不是写的那一个 ⇒ **假红** ✓）
local function card_tint(c, items, pos)
  local it = items[pos]
  if it == nil then return nil end
  local leaf = nil
  pcall(function() leaf = c:_grid_item_child(it, pos - 1, pos, "backrop1") end)
  if leaf == nil then return nil end
  local v = nil
  pcall(function() v = leaf.imageColor end)
  return v
end

-- 让引擎"重进一次填充"（★ 真机上滚动/刷新时就会发生 ✓）
--   ★★ `_grid_in_refresh` 必须是 **true** ✗✓（★ 这一条我第一版写反了 ⇒ 假红 ✓）：
--     ★ 它标的是"**这是我们自己那趟**" ✓ ⇒ ★ 单射落账 ＋ 高亮那一笔**都在那一趟里** ✓
--     ★ 而"引擎重进"那趟（false ✓）按设计**只按 index 刷内容** ✗
--       ⇒ ★★ 拿 false 去测"高亮会不会跟着走" ⇒ ★ **测的不是那条路** ✓✓
local function refill(c, items)
  c._grid_in_refresh = true
  for pos = 1, #items do
    pcall(function() c:_fill_grid_item(nil, nil, items[pos], pos - 1) end)
  end
  c._grid_in_refresh = false
end

local function fresh()
  UIC.Controller._row_text = {}      -- ★ 模块级表 ✓ 每个实例自己重来一遍 ✓
  UIC.Controller._row_letter = {}
  UIC.Controller._row_face = nil
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  c._grid_base = 0                   -- ★ 引擎索引 0 起 ✓（`pos = index − 基准 + 1` ✓）
  build_rows(c)
  UIC.Controller._piece_core = core
  return c
end

-- 人 → 它配在第几行（★ 用**公开入口**求 ✓ 不手算 id 顺序 ✓）
local function pos_of(c, id)
  for i = 1, #c.core.pieces do
    if tostring(c.core.pieces[i].id) == tostring(id) then return i end
  end
  return nil
end

-- ★ 「点卡片」= ★ **真机那一下** ✓：
--   ★ 假适配器的 `on_input` **转手就进控制器**（★ 真机是 `main.lua` 接的 ✓）
--   ★ 然后调 `_on_grid_item_click` —— ★ 引擎回调里就是它 ✓
local function tap_card(c, pos)
  -- ★ 这些子控件就是"卡上那个人"的来源 ✓ —— ★ 少一个都会**静默降级** ✗（见上面那段 ✓）
  local card = {}
  for _, nm in ipairs({ "who", "what", "letter", "face" }) do
    card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { ctrl(nm, {}) })
  end
  local it = ctrl("item", card)
  -- ★★ 如果这一关造了真的网格列表项 ⇒ **点真的那一个** ✗✓
  --   ★ 为什么必须这样 ✗：★ `_on_grid_item_click` 先用 `_grid_pos_of_item` 认"这是第几条" ✓
  --     ★ 而它查的是 `_grid_seen[item]`（★ 填充时按**控件身份**记的 ✓）
  --     ★★ 拿一个**临时造的新 item** 去点 ⇒ ★ **表里没有它** ⇒ ★ 这次点击**整条丢掉** ✓✓
  --       （★ 症状 = "点了没反应" ✓ ★ 我第一版就是全红在这上面 ✓）
  --     ★ 兜底是问引擎 ✓ 而这里给的 `GetItemIndex` 恒回 `pos-1` ⇒ ★ 也能中 ✓
  --       ★ 但那只证明"兜底能跑" ✗ ★ **不是真机那条路**（真机走填充记录 ✓）✓
  if c.__grid_items ~= nil and c.__grid_items[pos] ~= nil then
    it = c.__grid_items[pos]
  end
  local fired = {}
  local ad = { on_input = function(ev) fired[#fired + 1] = ev; c:on_input(ev) end }
  -- ★★ `self.adapter` **故意不设** ✗ —— ★ 生产里控制器的 `self.adapter` **就是 nil** ✓
  --   ★ 依据 ✓：★ `main.lua:462` 的 `self.adapter = adapter` 里的 `self` 是 **`Murdoku`** ✓
  --     ★（★ `main.lua:471` 那句 `adapter.on_input = function(event) controller:on_input(event) end` ✓）
  --     ★★ 而控制器**从来没有**拿到过适配器 ⇒ ★ 两条路**恰好只选一次** ✓✓
  --   ⚠️ ★ 若在这里补一句 `c.adapter = ad` ⇒ ★ `_on_grid_item_click` 会**两条路各发一次** ✓
  --     ★（★ 6878 用 `self.adapter` ✓ 6887 用参数 `adapter` ✓）⇒ ★ **选中会被打两遍** ✓
  --     ★★ 那测的就不是真机 ✓ —— ★ 所以**不设** ✓ 与真机逐字同构 ✓✓
  it.GetChild = function(_, n)
    for _, k in ipairs(it._kids) do if k.name == n then return k end end
    return nil
  end
  local _saved_enum = _G.Enum
  _G.Enum = { CursorEventType = { CursorClick = 1 } }
  local g = { GetItemIndex = function(_, _item) return pos - 1 end }   -- ★ 引擎 0 起 ✓
  -- ★★ 清掉"同一次点击的后续项"那道去重闩 ✓（★ 它按 `os.clock()` 的 0.05 秒窗口 ✓）
  --   ★ 为什么要清 ✗：★ 那是给"**同一次**射线命中多个叠在一起的列表项"用的 ✓
  --   ★★ 而这里是玩家**先点一张、过一会儿再点另一张** ✓ ⇒ ★ 不同的两次点击 ✓
  --   ★ 不清的后果 ✗：★ `os.clock()` 是 **CPU 时间** ✓ ★ 离线跑几十毫秒就够到 0.05 ✓
  --     ⇒ ★★ **第二次之后的点击会被静默丢掉** ✓✓（★ 我第一版就踩了 ✓ 症状 = "全红" ✓）
  c._grid_click_at = nil
  local it_before = it.GetChild
  c:_on_grid_item_click(ad, g, it)
  if os.getenv("SELRES_DBG") ~= nil then
    local names = {}
    for i = 1, #fired do names[#names + 1] = tostring(fired[i].action) .. "=" .. tostring(fired[i].id) end
    print(string.format("   [dbg] pos=%s pid=%s fired=[%s] sel=%s fc=%s kids=%d GetChildSame=%s",
      tostring(pos), tostring(c:_person_id_for_pos(pos)), table.concat(names, ","),
      tostring(c.core.selected), tostring(c.focused_clue), #(it._kids or {}),
      tostring(it.GetChild == it_before)))
  end
  _G.Enum = _saved_enum
  return fired
end

-- ★★★★★★★★ 2026-10-15 **点完卡："选中"已经落地，"高亮"要等下一帧** ✗✓✓
--
--   ★★ 机制 ✓（★ 三个探针交叉确认过 ✓）：
--     ★ `_on_grid_item_click` 里**两个事件用的不是同一个适配器** ✗：
--       · ① 发 `suspect` ⇒ 走 **`self.adapter`** ✓
--         ★★ 而生产里控制器的 `self.adapter` **是 nil** ✓
--           （★ `main.lua:462` 的 `self.adapter = adapter` 里的 `self` 是 **`Murdoku`** ✓
--            ★ 见 `main.lua:471`：`adapter.on_input = function(event) controller:on_input(event) end` ✓）
--         ⇒ ★ 落到 `else` 分支：★ **`self:on_input(ev2)`** ✓ ⇒ ★ 选中 + 派生**都做了** ✓
--       · ② 发 `focus_clue` ⇒ 走**参数 `adapter`** ✓ ★ 真机把它转给控制器 ✓
--         ⇒ ★ 该分支**照常播特效**（★ 高亮已经不归它管 ✓）
--     ★★ 于是"点一下卡"**结束时** ✓：★ `core.selected` **已经是那个人** ✓
--       ★ 而 `focused_clue` 要等**下一帧**（`sync_clue_grid` → 计划 → 样式 ✓）才反映 ✓✓
--   ⇒ ★★ 所以断言分两处 ✓：
--     · ★ "选中落地"⇒ ★ 点完**立刻**查 `core.selected` ✓
--     · ★ "高亮跟上"⇒ ★ 先 `settle_highlight` 驱动一次**不改选中**的事件 ✓ 再查 ✓
--       （★ 那一趟正好复刻"下一帧重算计划"那一步 ✓✓）
local function settle_highlight(c)
  -- ★ 挑一个**不碰选中、不碰棋盘、不碰高亮**的动作 ✓（滚线索窗口 ✓）
  c:on_input({ action = "clue_up" })
end

-- ★★ 哨兵 ✓：★ 单射**真的落了账**才算"点卡片"这条路成立 ✗
--   （★ 不查 ⇒ 命名一错（如把 `<关>` 写成 1 ✓）⇒ **一条都不落账** ⇒
--    ★ 本文件会变成"全红"或"全绿"而你看不出原因 ✗✓）
local function injection_ok(c)
  local m = UIC.Controller._row_letter
  if type(m) ~= "table" then return false end
  for i = 1, #c.core.pieces do
    if m[i] == nil then return false end
  end
  return true
end

-- ★ V / D 各配在第几行 —— 由**关卡自己的棋子表**取 ✓（★ 不手写数字 ✗ 关卡改了也不会假绿 ✓）
local V_POS, D_POS
do
  local c0 = fresh()
  V_POS, D_POS = pos_of(c0, "V"), pos_of(c0, "D")
end

print(string.format("  前提：V 在第 %s 行，D 在第 %s 行", tostring(V_POS), tostring(D_POS)))
ok(V_POS ~= nil and D_POS ~= nil, "★ 前提：case_001 里 V 与 D 都能定位到行")
-- ★★ 前提闸 ✓：★ 前面几条断言**全都**依赖"单射落账了" ✗
--   ⇒ ★ 没落账就**先在这里红** ✓ ★ 而不是让 20 条一起红（那样看不出病因 ✓ P11 ✓）
do
  local c0 = fresh()
  ok(injection_ok(c0),
    "★★ 前提：`row.<关>.<行>` 的单射**真的落账了**（★ 没落账 ⇒ 下面全部无意义 ✗）")
  ok(c0:_level_ordinal() ~= nil,
    "★★ 前提：`_level_ordinal()` 拿得到关序（实测 " .. tostring(c0:_level_ordinal()) .. "）")
end

-- ── 屏幕 vs 行为的一致性判据 ────────────────────────────────────────────
--   ★ 返回"不一致"的人类可读描述 ✓ nil = 一致 ✓
local function mismatch(c, tag)
  local sel = c.core.selected
  local want = nil
  if sel ~= nil then want = pos_of(c, sel) end
  local got = c.focused_clue
  if want ~= got then
    return string.format("【%s】选中=%s（⇒ 该亮第 %s 张卡）而高亮在第 %s 张卡 ✗",
      tag, tostring(sel), tostring(want), tostring(got))
  end
  return nil
end

local function assert_consistent(c, tag)
  local m = mismatch(c, tag)
  ok(m == nil, m or tag)
end

--------------------------------------------------------------------------------
-- 1. 用户症状 ①：放 V → 选 D → 取消 V ⇒ 屏幕与行为必须一致
--------------------------------------------------------------------------------
do
  local c = fresh()
  -- 选 V 并正式放置
  tap_card(c, V_POS)
  ok(c.core.selected == "V", "★ 前提：点 V 那张卡 ⇒ 选中 V（实测 "
    .. tostring(c.core.selected) .. "）")
  settle_highlight(c)
  ok(c.focused_clue == V_POS, "★ 且高亮在第 " .. tostring(V_POS) .. " 张卡（实测 "
    .. tostring(c.focused_clue) .. "）")
  ok(long_press(c, 3, 1) == true, "★ 前提：长按 (3,1) ⇒ 放下 V")
  ok(c.core.grid[3][1] == "V", "★ 前提：V 确实在 (3,1)")
  -- ★ 放置后选中被清 ⇒ 高亮**必须同时灭** ✗✓（★ 两向 ✓）
  ok(c.core.selected == nil, "★ 正式放置后 core.selected 归 nil")
  ok(c.focused_clue == nil, "★ 而且卡片高亮也必须归 nil（★ 不许留一张亮着 ✗）")
  ok(c.focused_clue ~= V_POS and c.focused_clue ~= D_POS,
    "★ 两张卡都不亮（★ 反向半边 ✓ 一个「从不高亮」的实现过不了上面那条 ✓）")

  -- 选 D
  tap_card(c, D_POS)
  settle_highlight(c)
  ok(c.core.selected == "D", "★ 前提：点 D 那张卡 ⇒ 选中 D")
  ok(c.focused_clue == D_POS, "★ 高亮跟着走到第 " .. tostring(D_POS) .. " 张卡（实测 "
    .. tostring(c.focused_clue) .. "）")

  -- ★★★ 关键一步：取消 V（单击已放置的格子 = 拿起 ✓ 核心会把人选上 ✓）
  tap_cell(c, 3, 1)
  settle_highlight(c)
  ok(c.core.grid[3][1] == nil, "★ 取消 V：棋子拿下来了")
  ok(c.core.selected == "V", "★ 拿起 V ⇒ 核心把 V 选上（★ 核心的既有语义 ✓）")
  -- ★★★ 这就是用户报的那一句 ✗✓：
  ok(c.focused_clue == V_POS,
    "★★ 拿起 V 之后，高亮**必须跟到 V 那张卡**（实测高亮在第 "
    .. tostring(c.focused_clue) .. " 张，期望第 " .. tostring(V_POS) .. " 张）"
    .. "　⇒ ★ 用户报的「显示选择的 d」就是这里 ✗")
  ok(c.focused_clue ~= D_POS,
    "★★ 而且**不许**还留在 D 那张卡上（★ 那一张已经不表示任何东西了 ✓）"
    .. "　⇒ ★ 用户报的「有选中高亮但没有选中行为」就是这里 ✗")
  assert_consistent(c, "取消 V 之后")

  -- ★★★ 行为判据：此刻长按，落的必须是**屏幕说的那个人** ✓
  local screen_says = c:_person_id_for_pos(c.focused_clue)
  local okp = long_press(c, 1, 1)
  ok(okp == true and c.core.grid[1][1] ~= nil, "★ 此时长按 (1,1) 能落子")
  ok(c.core.grid[1][1] == screen_says,
    "★★ 落下的必须是【屏幕说的那个人】= " .. tostring(screen_says)
    .. "（实测 " .. tostring(c.core.grid[1][1]) .. "）"
    .. "　⇒ ★ 用户报的「再长按放置，放的会是 v」就是这里 ✗")
  ok(c.core.grid[1][1] ~= "D",
    "★★ 反向：此刻**不该**落下 D（★ 那是「点卡片」留下的残影 ✗）")
end

--------------------------------------------------------------------------------
-- 2. 用户症状 ②：高亮说"选中了" ⇒ 行为必须真的是选中了
--      ★ 判据 = 拿高亮那张卡上的人去棋盘做一次笔记 / 一次放置，必须成功 ✓
--------------------------------------------------------------------------------
do
  local c = fresh()
  tap_card(c, V_POS); long_press(c, 3, 1)     -- 放 V
  tap_card(c, D_POS)                          -- 选 D
  settle_highlight(c)
  tap_cell(c, 3, 1)                           -- 取消 V ⇒ 选中变成 V、高亮必须跟走
  settle_highlight(c)

  local shown = c:_person_id_for_pos(c.focused_clue)
  ok(shown ~= nil, "★ 高亮那张卡能解析出人（实测 " .. tostring(shown) .. "）")
  ok(shown == c.core.selected,
    "★★ 高亮那张卡上的人 = 真正选中的人（高亮=" .. tostring(shown)
    .. " 选中=" .. tostring(c.core.selected) .. "）")
  -- ★ 行为面：单击空格 ⇒ 必须**真的**标上那个人的笔记 ✓（★ 不是"看着像选中" ✗）
  local oknote = c.core:tap_cell(5, 5)
  ok(oknote == true and c.core.notes[5][5] ~= nil and c.core.notes[5][5][shown] == true,
    "★★ 高亮说选中的那个人，笔记**真的标得上**（★ 这才叫「有选中行为」✓）")
end

--------------------------------------------------------------------------------
-- 3. "再点一次取消"这条语义**不许被改坏**（★ 两向 ✓）
--------------------------------------------------------------------------------
do
  local c = fresh()
  tap_card(c, D_POS)
  settle_highlight(c)
  ok(c.core.selected == "D" and c.focused_clue == D_POS,
    "★ 第一次点 D 卡 ⇒ 选中 D（选中=" .. tostring(c.core.selected)
    .. " 高亮=" .. tostring(c.focused_clue) .. "）")
  tap_card(c, D_POS)
  settle_highlight(c)
  ok(c.core.selected == nil, "★ 再点一次同一张卡 ⇒ 选中取消（实测 "
    .. tostring(c.core.selected) .. "）")
  ok(c.focused_clue == nil, "★ 且高亮同时灭（实测 " .. tostring(c.focused_clue) .. "）")
  -- ★ 反向：取消之后，换点**别**的卡必须能正常选上 ✓
  tap_card(c, V_POS)
  settle_highlight(c)
  ok(c.core.selected == "V" and c.focused_clue == V_POS,
    "★ 取消之后换一个人照样能选上（★ 防「一次取消之后再也选不中」✗）"
    .. "（选中=" .. tostring(c.core.selected) .. " 高亮=" .. tostring(c.focused_clue) .. "）")
end

--------------------------------------------------------------------------------
-- 4. 撤销 / 重做也要跟着走（★ 它们也改棋盘与选中 ✓）
--------------------------------------------------------------------------------
do
  local c = fresh()
  tap_card(c, V_POS); long_press(c, 3, 1)
  tap_card(c, D_POS)
  settle_highlight(c)
  ok(c.focused_clue == D_POS, "★ 前提：选中 D 时高亮在 D（实测 "
    .. tostring(c.focused_clue) .. "）")
  undo(c)
  assert_consistent(c, "撤销之后")
  ok(c.focused_clue ~= D_POS or c.core.selected == "D",
    "★ 撤销之后高亮不许「说 D」而选中不是 D ✗")
  -- ★ 撤销把 V 放回原位（`undo` 清掉那次 place ✓）⇒ 选中仍是 D ✓
  ok(c.core.selected == "D", "★ 撤销只动棋盘、不动选中（实测 " .. tostring(c.core.selected) .. "）")
  settle_highlight(c)
  assert_consistent(c, "撤销之后（复查）")
end

--------------------------------------------------------------------------------
-- 5. 棋盘格显示的字母，必须就是**那一格那个人**的字母（★ 用户说的"标记" ✓）
--      ★ 两向 ✓：该有的有 ✗ 该没有的没有 ✓
--------------------------------------------------------------------------------
do
  local c = fresh()
  tap_card(c, V_POS)
  -- ★ 给一个**空格子**打 V 的标记（单击 ✅ ✅ 这样棋盘上会出现 V 的字母 ✓）
  tap_cell(c, 4, 4)
  local cl = c.core:view().cells[4][4]
  ok(cl.suspect == nil, "★ 前提：(4,4) 是空格子")
  ok(c.core.notes[4][4] ~= nil and c.core.notes[4][4]["V"] == true,
    "★ 前提：单击 (4,4) ⇒ 标上了 V 的笔记")
  local shown = UIC.Controller.letter_of(c.core:view(), "V")
  ok(shown == "V", "★ V 那一格该显示的字母是 " .. tostring(shown))
  -- ★ 再选 D 并放置 ⇒ (4,4) 的标记**不许**被别的东西顶掉 ✓
  tap_card(c, D_POS)
  long_press(c, 1, 1)
  ok(c.core.notes[4][4] ~= nil and c.core.notes[4][4]["V"] == true,
    "★ 放 D 到别处之后，(4,4) 的 V 标记还在（★ 反向 ✓ 没被清掉 ✓）")
  ok(c.core.grid[1][1] == "D", "★ 而 D 落在 (1,1)")
  ok(UIC.Controller.letter_of(c.core:view(), c.core.grid[1][1]) == "D",
    "★ (1,1) 那一格该显示的字母是 D（★ 不是 V ✗）")
end

--------------------------------------------------------------------------------
-- 6. ★★★★★★★★ **真机那条路：网格列表项上的高亮** ✗✓✓
--
--   ★★★ 为什么单开一节 ✗（★ 这一节就是第一轮漏掉的那条路 ✓）：
--     ★ 1~5 节判的是 **`focused_clue` / 老卡片样式** ✓
--     ★★ 而真机 `_grid_state == "on"` ⇒ ★ **老卡片不进规划** ⇒ ★ 那几节在真机上**读不到** ✓
--     ★★★ 真机上用户看得见的那张卡 = ★ **网格视窗的列表项** ✓
--       ★ 它上面那笔底色 = `clue.<pos>.backrop1.imageColor` ✓
--   ⇒ ★★ 所以这一节**只断言那一笔颜色** ✓ —— ★ 那才是"显示选择的 d"里那个"显示" ✓✓
--
--   ★ 判据是**两向**的 ✓：★ 该亮的那张亮 ✓ ★ 且**别的那张必须灭** ✗（P3 ✓）
--------------------------------------------------------------------------------
do
  local c = fresh()
  local items = build_grid(c)
  ok(#items >= 2, "★ 前提：造出了 ≥2 个列表项（实测 " .. tostring(#items) .. "）")
  local TINT = 4294956107          -- ★ 与实现里 `HIGHLIGHT_TINT` 同一个值 ✓（暖金 ✓）
  local ORIG = 4294967295          -- ★ 原色（白 ✓）

  -- ★ 前提闸 ✓：全灭（★ 一个都没选中 ✓）
  local lit0 = {}
  for pos = 1, #items do lit0[pos] = card_tint(c, items, pos) end
  ok(lit0[V_POS] == ORIG and lit0[D_POS] == ORIG,
    "★ 前提：还没选人 ⇒ 两张卡都是原色（实测 V=" .. tostring(lit0[V_POS])
    .. " D=" .. tostring(lit0[D_POS]) .. "）")

  -- ① 选 D ⇒ **D 那张必须亮**，且 V 那张必须**不亮** ✓（两向 ✓）
  tap_card(c, D_POS)
  refill(c, items)
  local litD, litV = card_tint(c, items, D_POS), card_tint(c, items, V_POS)
  ok(litD == TINT, "★★ 真机路：选中 D ⇒ **D 那张卡亮**（实测 " .. tostring(litD)
    .. "，期望 " .. tostring(TINT) .. "）")
  ok(litV ~= TINT, "★★ 反向：V 那张卡**不许**亮（实测 " .. tostring(litV) .. "）")
  ok(c.core.selected == "D", "★ 且 core.selected = D（★ 高亮与选中一致 ✓）")

  -- ② ★★★ 用户那一步：放 V → 选 D → **拿起 V** ⇒ 高亮必须**从 D 走到 V** ✗✓
  --   ★★ 判据顺序要紧 ✗：★ 每一步都**先断言前置**（选中到底变成了谁 ✓）
  --     ★ 再断言高亮 ✓ —— ★ 不然红了分不清"选中没变"还是"高亮没跟" ✓✓
  --     ★（★ 我这一节第一版就是栽在这上面：★ 拿一个**没满足的前提**去判结论 ✓）
  tap_card(c, V_POS); long_press(c, 3, 1)
  refill(c, items)
  ok(c.core.grid[3][1] == "V", "★ 前提：V 放在 (3,1)")
  ok(c.core.selected == nil, "★ 前提：正式放置后选中被清（实测 "
    .. tostring(c.core.selected) .. "）")
  ok(card_tint(c, items, D_POS) == ORIG,
    "★ 前提：没选人 ⇒ D 那张灭（实测 " .. tostring(card_tint(c, items, D_POS)) .. "）")

  tap_card(c, D_POS)                       -- 选 D
  refill(c, items)
  ok(c.core.selected == "D", "★ 前提：点 D 卡 ⇒ 选中 D（实测 "
    .. tostring(c.core.selected) .. "）")
  ok(card_tint(c, items, D_POS) == TINT, "★ 前提：D 亮（实测 "
    .. tostring(card_tint(c, items, D_POS)) .. "）")

  -- ★★★ 关键一步：★ 拿起 V（★ 单击已放置的格子 ✓ 核心会把 V 选上 ✓）
  tap_cell(c, 3, 1)
  ok(c.core.grid[3][1] == nil, "★ 前提：V 被拿起来了")
  ok(c.core.selected == "V", "★ 前提：拿起 V ⇒ core.selected = V（实测 "
    .. tostring(c.core.selected) .. "）")
  refill(c, items)
  local afterV, afterD = card_tint(c, items, V_POS), card_tint(c, items, D_POS)
  ok(afterV == TINT,
    "★★★ 真机路：拿起 V 之后，**V 那张卡必须亮**（实测 " .. tostring(afterV)
    .. "，期望 " .. tostring(TINT) .. "）")
  ok(afterD == ORIG,
    "★★★ 而 **D 那张必须灭**（实测 " .. tostring(afterD)
    .. "）　⇒ ★ 用户报的「显示选择的 d」就是这一笔 ✗")

  -- ③ ★★★ 行为面：此刻长按，落下的必须是**亮着那张卡上的人** ✓
  local lit_pos = (card_tint(c, items, V_POS) == TINT) and V_POS or D_POS
  local shown = c:_person_id_for_pos(lit_pos)
  long_press(c, 1, 1)
  ok(c.core.grid[1][1] == shown,
    "★★★ 亮着第 " .. tostring(lit_pos) .. " 张卡（= " .. tostring(shown)
    .. "）⇒ 长按落下的必须是它（实测 " .. tostring(c.core.grid[1][1])
    .. "）　⇒ ★ 用户报的「再长按放置，放的会是 v」就是这里 ✗")

  -- ④ 幂等 ✓：再重进几次填充 ⇒ 颜色**不许变** ✗（★ 防"每帧换色" ✓）
  --   ★ 注意 ✓：★ 上一步长按**已经把 V 放下去、选中被清了** ✓
  --     ⇒ ★ 这里的前置是"没人被选中" ✓ ★ 所以两张都该是原色 ✓
  ok(c.core.selected == nil, "★ 前提：长按放置后选中已清（实测 "
    .. tostring(c.core.selected) .. "）")
  refill(c, items); refill(c, items)
  ok(card_tint(c, items, V_POS) == ORIG and card_tint(c, items, D_POS) == ORIG,
    "★ 反复重进填充 ⇒ 颜色稳定且都灭（V=" .. tostring(card_tint(c, items, V_POS))
    .. " D=" .. tostring(card_tint(c, items, D_POS)) .. "）")
end

--------------------------------------------------------------------------------
-- 7. "再点一次取消" —— ★ 在**真机那条路**上也要成立 ✓
--      ★ 判据 = ★ `core.selected` **只由"是不是他"决定** ✗（★ 不看谁亮着 ✓）
--------------------------------------------------------------------------------
do
  local c = fresh()
  local items = build_grid(c)
  local TINT = 4294956107
  local ORIG = 4294967295

  tap_card(c, V_POS)
  refill(c, items)
  ok(c.core.selected == "V", "★ 前提：点 V 卡 ⇒ 选中 V（实测 " .. tostring(c.core.selected) .. "）")
  ok(card_tint(c, items, V_POS) == TINT, "★ 前提：V 亮（实测 "
    .. tostring(card_tint(c, items, V_POS)) .. "）")

  -- ★ 再点**同一张** ⇒ 取消 ✓
  tap_card(c, V_POS)
  refill(c, items)
  ok(c.core.selected == nil, "★★ 再点一次同一张卡 ⇒ **选中取消**（实测 "
    .. tostring(c.core.selected) .. "）")
  ok(card_tint(c, items, V_POS) == ORIG, "★★ 且 V 那张**必须灭**（实测 "
    .. tostring(card_tint(c, items, V_POS)) .. "）")

  -- ★ 反向 ✓：取消之后**换一个人**照样能选上 ✗（★ 防"一次取消之后再也选不中" ✓）
  tap_card(c, D_POS)
  refill(c, items)
  ok(c.core.selected == "D", "★ 取消之后换一个人照样能选上（实测 "
    .. tostring(c.core.selected) .. "）")
  ok(card_tint(c, items, D_POS) == TINT and card_tint(c, items, V_POS) == ORIG,
    "★ 且只有 D 亮（D=" .. tostring(card_tint(c, items, D_POS))
    .. " V=" .. tostring(card_tint(c, items, V_POS)) .. "）")

  print("  [PASS] 真机那条路：再点一次取消 ✓ 换人重选 ✓（两向都钉住 ✓）")
end

print(string.format("selection_residue: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
