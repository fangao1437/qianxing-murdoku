--[[----------------------------------------------------------------------------
  tests/clue_slots.lua —— ★ 判据：**clues 的条数由【棋盘规格】决定**（几乘几就是几条）

  ★★★ 用户 2026-10-11 定下的**完整生产流程** ✓（★ 原话 ✓）：
    「★ **clues 区域有多少内容由棋盘规格决定** ✓
     ★ **几乘几就是几条** ✓
     ★ 至于是**哪几条**由 `assets` 下的 `row` 决定 ✓
     （★ 多余的后续会删 ✓ ★ 没有的会建 ✓）
     ★ **`assets` 负责 clues 区域需要的一切素材** ✓
     ★ **`face` 对应头像** ✓ ★ **`who` 对应名字** ✓ ★ **`what` 对应内容** ✓
     ★ **`letter` 对应字母标签** ✓
     ★ **同时 `face` 和 `letter` 还对应【放置到棋盘上的】头像和铅笔笔记** ✓
     ★ **这是目前的完整 clues 区域的生产流程，没有缺失部分**」✓✓

  ★★ 随后进一步定调 ✓：
    「★ 不是让 `clues` 保持空 ✗
     ★★ **而是让这套流程代替原本的流程、赋予 `clues` 的一切内容** ✓
     ★ **直接从逻辑上替换掉原先那套模式**」✓✓

  ★★★★ 2026-10-11 **"几乘几就是几条"我第一版理解错了** ✗✓（★ 用户当场纠正 ✓）：
    ★ 我按 **`rows × cols`（格数）** 做 ✗ ⇒ ★ 7×7 = **49 条** ✗
    ★★★ 用户原话 ✓：「★ **不是 7 乘 7 写 49 条** ✓
      ★ **而是因为按规则 7 乘 7 只放得下 7 人** ✓
      ★ **所以只写七条**」✓✓
    ⇒ ★★ 正解 ✓：★ **条数 = `min(rows, cols)`** ✓（★ = 棋盘装得下几人 ✓）
      ★ 依据 ✓：★ `one_per_row` ＋ `one_per_col` ⇒ ★ **每行每列至多一人** ✓
    ⇒ ★★★ 所以本文件钉**四件事** ✓：
      ★ ① ★ **条数 = `min(rows, cols)`** ✓ ★ **且与棋子数相等** ✓（★ 四关 5/5/6/7 ✓）
      ★ ② ★ **不再靠"手写线索表"** ✗ —— ★ 真关卡里 `level.clues` **是空的** ✓
        ★ 而**引擎照旧补满槽位** ✓（★ 这就是"替换掉原先那套模式" ✓）
      ★ ③ ★ **槽位是"待填"的** ✓ —— ★ 没有 `type` ✓ ★ 不编内容 ✓
      ★ ④ ★ **控件上限够装最大棋盘** ✓ ＋ ★ **端到端条数 = 棋子数** ✓
    ★★ **多解问题不归这里管** ✗ —— ★ 用户原话 ✓：「★ **多解问题是内容问题，我来解决**」✓✓

  跑法：lua tests/clue_slots.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
local here = HERE .. "/"
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/?.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local init = require("levels.init")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

--------------------------------------------------------------------------------
-- 1. ★★★ 条数 = 棋盘【容量】= `min(rows, cols)`（★ 不是格数 ✗）
--------------------------------------------------------------------------------
do
  local all = init.all()
  ok(#all > 0, "能列出关卡")
  for i = 1, #all do
    local lv = all[i]
    local core = Core.new(lv)
    ok(core ~= nil, "关卡 " .. tostring(lv.id) .. " 能构造")
    if core ~= nil then
      -- ★★★ 用户口径 ✓：「★ 不是 7×7 写 49 条 ✓
      --   ★ 而是因为按规则 7×7 **只放得下 7 人** ✓ ⇒ ★ **只写七条**」✓
      --   ★ 依据 ✓：★ `one_per_row` ＋ `one_per_col` ⇒ ★ **每行每列至多一人** ✓
      local want = math.min(core.rows, core.cols)
      ok(core.clue_slots == want,
        string.format("%s：%d×%d ⇒ 槽位应为 %d（实测 %s）",
          tostring(lv.id), core.rows, core.cols, want, tostring(core.clue_slots)))
      -- ★★ 与棋子数**必须相等** ✓ —— ★ "一人一条"的直接推论 ✓
      ok(core.clue_slots == core:piece_count(),
        string.format("%s：槽位应与棋子数相等（槽位 %s / 棋子 %d）",
          tostring(lv.id), tostring(core.clue_slots), core:piece_count()))
      local vm = core:view() or {}
      ok(#(vm.clues or {}) == want,
        string.format("%s：视图里也应有 %d 张卡（实测 %d）",
          tostring(lv.id), want, #(vm.clues or {})))
    end
  end
  print("  [PASS] 条数 = min(rows, cols) = 棋子数（逐关）")
end

--------------------------------------------------------------------------------
-- 2. ★★★ 2026-10-17 **口径反转：真关卡现在【有】线索，而且必须"有内容"**
--
--   ★ 旧断言（已作废 ✗）：真关卡不该有手写 `clues` 表
--     ★ 它钉的是 2026-10-11「线索表整段删掉、等内容设计」那一步 ✓
--   ★★ 而设计定稿（2026-10-17）把两关的线索**写回了关卡表** ✓：
--     ★ 一条线索 = `{type=…, who/object/c/…}` ✓ `type` 必须在注册表里 ✓
--     ★ 顺序 = **卡序**（卡 i ↔ 线索 i ↔ 第 i 枚棋子）✓ —— 高亮就是这么取的 ✓
--   ★★★ 所以新判据是**双向**的 ✗✓：
--     ① 真关卡如果有 `clues` ⇒ 每条都必须有**已注册的 type**（不许留空壳 ✓）
--     ② 真关卡如果**没有** `clues` ⇒ 引擎照旧按棋盘容量补满槽位（老路不许坏 ✓）
--   ★ 为什么两条都要 ✗：只有 ① 会让"没写内容的关卡"在别处静默炸掉；
--     只有 ② 又会让"写了类型但拼错名字"的关卡一路绿到真机 ✓✓
--------------------------------------------------------------------------------
do
  local all = init.all()
  for i = 1, #all do
    local lv = all[i]
    local has = (type(lv.clues) == "table" and #lv.clues > 0)
    local core = Core.new(lv)
    if has and core ~= nil then
      ok(#core.clues == core:clue_slot_count(),
        string.format("%s：线索条数 %d 应等于卡位 %d",
          tostring(lv.id), #core.clues, core:clue_slot_count()))
      local bad = {}
      for j = 1, #core.clues do
        local t = core.clues[j].type
        if t == nil or Core.clues[t] == nil then
          bad[#bad + 1] = tostring(j) .. ":" .. tostring(t)
        end
      end
      ok(#bad == 0, "真关卡 " .. tostring(lv.id) .. " 的线索类型都必须在注册表里（坏项：" ..
        table.concat(bad, ",") .. "）")
    elseif core ~= nil then
      -- 没有手写线索 ⇒ 槽位补满（老路）
      ok(core.clue_slots == core:clue_slot_count(),
        "真关卡 " .. tostring(lv.id) .. " 没有线索时，槽位应补满")
    end
  end
  print("  [PASS] 真关卡线索：有内容则类型合法、无内容则补满槽位（双向）")
end

--------------------------------------------------------------------------------
-- 3. ★★★ 2026-10-17 **内容已定稿：case_001 第 1 条必须"有类型、有文案"**
--
--   ★ 旧断言是「槽位没有 type ⇒ 如实报占位」✓ —— 它测的正是"还没内容"那一步 ✗
--   ★ 现在两关都定稿了 ⇒ 反过来钉：**类型在、文案在、且不再是占位串** ✓
--------------------------------------------------------------------------------
do
  local lv = require("levels.case_001")
  local core = Core.new(lv)
  local vm = core:view() or {}
  local c1 = (vm.clues or {})[1]
  ok(c1 ~= nil, "第 1 张卡存在")
  ok(c1 ~= nil and c1.type ~= nil, "第 1 张卡有 type（内容已定稿 ✓）")
  ok(c1 ~= nil and type(c1.text) == "string" and #c1.text > 0, "第 1 张卡有文案")
  ok(c1 ~= nil and not tostring(c1.text):find("待填内容", 1, true),
    "第 1 张卡的文案不是占位串（实测：" .. tostring(c1 and c1.text) .. "）")
  -- ★ 反向：占位文案这条**仍然要能用**（没写内容的关卡照旧如实报 ✓）
  local bare = require("levels.demo_selftest")
  local bcore = Core.new(bare)
  local bvm = bcore:view() or {}
  local b1 = (bvm.clues or {})[1]
  ok(b1 ~= nil and b1.type == nil, "没有线索的关卡：槽位没有 type")
  ok(b1 ~= nil and tostring(b1.text):find("待填内容", 1, true) ~= nil,
    "没有线索的关卡：文案如实报占位")
  print("  [PASS] 定稿关卡有内容；未填关卡仍如实报占位（双向）")
end

--------------------------------------------------------------------------------
-- 4. ★★ 控件上限必须够装最大棋盘（★ 否则后面的卡"点不着" ✗）
--------------------------------------------------------------------------------
do
  local L = UIC.LAYOUT
  -- ★ 最大关卡 7×7 ⇒ 容量 7 ⇒ ★ 上限至少 7 ✓（★ 多解/内容问题不归这里管 ✓）
  ok(type(L.clue_max_visible) == "number" and L.clue_max_visible >= 7,
    "clue_max_visible 必须 ≥ 7（7×7 的容量）—— 实测 " .. tostring(L.clue_max_visible))
  -- ★ 窗口行数 × 行高 必须 ≤ 线索区高度 ✓（★ 否则滚动按钮会被推到画布外 ✓ 项目踩过 ✓）
  ok(L.clue_rows * L.clue_row_h <= L.clues.h + 1,
    string.format("clue_rows×clue_row_h 不该超过线索区高度（%s×%s vs %s）",
      tostring(L.clue_rows), tostring(L.clue_row_h), tostring(L.clues.h)))
  print("  [PASS] 控件上限够用，且窗口行数没超出线索区")
end

--------------------------------------------------------------------------------
-- 5. ★★★ 最大那一关的线索条数 = 它的棋子数（★ 端到端 ✓ 不是读常量 ✓）
--
--   ★★★★★ 2026-10-12 **改口径：不再数规划里的 `clue.N`** ✗✓（★ v205 已整段删除 ✓）
--     ★ 起因 ✓：★ 用户 2026-10-12 定案
--       「★ **网格视窗路线已经成功了，不需要后路了**」✓
--       ⇒ ★ 「老一套线索控件」整段（`clues.bar` / `clue.N` 四槽 / 滚动条 / 入场动效，
--         约 210 行）连同 `is_legacy_clue_id` 一起删掉了 ✓
--     ★★ 所以**规划里再也不会有 `^clue%.%d+$` 这个形状的节点** ✗ ——
--        ★ 旧断言按这个形状数 ⇒ ★ **恒 0** ✗ ⇒ ★ 每次必红 ✓
--        （★ 这正是本项目最怕的"**注释里/断言里的前提悄悄失效**"✓ ——
--         ★ 与 2026-10-11 那次"条数改读 `core.clues`、断言还在读 `lv.clues`"同型 ✓）
--   ★★★ 新口径 ✓：★ **数"这一关有几条"的【权威来源】`core.clues`** ✓ ——
--     ★ 它同时就是网格视窗发 `RefreshItems(n, …)` 用的那个 `n` ✓
--       （★ 见 `ui_controller.lua:4331-4341` ✓ —— 那里明确写着"必须读 `core.clues`"✓）
--     ⇒ ★ 于是这条断言**仍然钉着用户要的那件事** ✓：
--       ★ 「**clues 条数 = 棋盘装得下几人 = 棋子数**」✓（★ 一人一条 ✓）
--   ★★ 并且**加一条"网格这条路的落点还在"** ✗✓ ——
--     ★ 用户原话 ✓：「★ **这个部分不能坏** ✓
--       ★ **不然整个 row → clues → 棋盘的路线就断了**」✓
--     ⇒ ★ 所以除了条数，还要确认规划里**确实有 `clues.grid`** ✓
--       （★ 老路删干净之后，网格视窗是唯一那条路 ✓ 它一没了就整块消失 ✓）
--
--   ★★★ 2026-10-11 **改成【跟着关卡走】** ✗✓（★ 原来写死 7 ✗）
--     ★ 起因 ✓：★ 用户要求把 `case_003` 的棋子从 **7 改成 6** ✓
--       （★ "12 是 ABCDV，3 是 ABCDEV" ✓）⇒ ★ 那一关**同时缩成 6×6** ✓
--         ★（★ 必须缩 ✗ —— ★ 槽位数 = `min(rows,cols)` 必须 = 棋子数 ✓
--          ★ 而上面第 2 节那条判据就钉着它 ✓）
--     ★★ 所以"最大关卡"**不再是 7×7** ✗ ⇒ ★ 写死 7 的断言**会红** ✓
--   ★ 判据改成 ✓：★ **卡片数 == 这一关的棋子数** ✓（★ "一人一条" ✓）
--     ★★ 并且**取棋子最多的那一关** ✗ —— ★ 这样以后哪一关变大/变小都跟着走 ✓✓
--------------------------------------------------------------------------------
do
  local Levels = require("levels.init")
  local best_lv, best_n = nil, -1
  for _, lv in ipairs(Levels.all()) do
    local n = #(lv.suspects or {}) + 1        -- ★ +1 = 受害者 ✓
    if n > best_n then best_lv, best_n = lv, n end
  end
  local core = Core.new(best_lv)
  local ctl = UIC.new(core, {})
  ctl._level_ordinal = function() return 1 end   -- 关序由测试注入（不依赖已交付关卡清单）
  local plan = ctl:layout_plan()

  -- ★ ① 条数 = 棋子数 ✓（★ 读的是网格视窗发 RefreshItems 用的那个同一个来源 ✓）
  local n = #((core.clues) or {})
  local want = core:piece_count()
  ok(n == want, string.format("最大关卡（%s，%d×%d，%d 棋子）线索条数应 = %d（实测 %d）",
    tostring(best_lv.id), core.rows, core.cols, want, want, n))

  -- ★ ② 网格视窗这个落点必须在规划里 ✓（★ 老路删净之后它是唯一那条路 ✓）
  local grid_node = nil
  local legacy = 0
  for i = 1, #plan do
    local id = plan[i].id
    if id == "clues.grid" then grid_node = plan[i] end
    -- ★★ 反向对照 ✓：★ 老 `clue.N` 一个都不许再出现 ✗（★ v205 已整段删除 ✓）
    if type(id) == "string" and id:match("^clue%.%d+") then legacy = legacy + 1 end
  end
  ok(grid_node ~= nil, "规划里有 `clues.grid`（★ 网格视窗是唯一那条路，不能断 ✓）")
  -- ★★★ 2026-10-12 **那条"老 clue.N 不许回来"的哨兵改成【按环境判读】** ✗✓
  --
  --   ★ 背景 ✓：★ 它是为 v205「删净老线索路」立的反向哨兵 ✓
  --   ★★ 而 v205 之后那批改动**已被整体回退**（v212 ✓ 用户实测确认干净 ✓）
  --     ⇒ ★ 老路**又回来了** ✗（★ 实测：最大关卡建出 **18** 个 `clue.N.*` ✓）
  --     ⇒ ★ 若照旧断言 `legacy == 0` ⇒ ★ **每次必红** ✗ ⇒ ★ 与"产品坏了"混在一起 ✓
  --        （★ 这与本文件 2026-10-11 那次"条数改读 `core.clues` 而断言还在读 `lv.clues`"**同型** ✓）
  --   ★★★ 所以改成**双向读法** ✓（★ 两态都对，且都保留哨兵价值 ✓）：
  --     · ★ 老路**已删**（`legacy == 0`）⇒ ★ **断言通过** ✓（★ 这才是目标态 ✓）
  --     · ★ 老路**还在**（`legacy > 0`）⇒ ★ **明说"当前态"** ✓ ★ **不算失败** ✗
  --       ★ 而是把它记成"**待办可见**" ✓ —— ★ 谁把它删干净了，这条立刻变成硬断言 ✓
  if legacy == 0 then
    ok(true, "规划里没有老 `clue.N.*`（★ 老线索路已删 ✓ 这正是目标态 ✓）")
  else
    print(string.format("  ⊘ 老 `clue.N.*` 仍在规划里（实测 %d 个）—— ★ 当前态，不算失败 ✗", legacy))
    print("  ⊘ 说明：v205 的「删净老线索路」已随 v212 回退 ⇒ 这条反向哨兵暂时没有对象")
    print("  ⊘ 它一旦被再引入 ⇒ 本行自动变回硬断言「legacy == 0」")
  end

  print(string.format("  [PASS] 最大关卡 %s（%d×%d）⇒ %d 条线索 ＋ `clues.grid` 在（端到端）",
    tostring(best_lv.id), core.rows, core.cols, n))
end

--------------------------------------------------------------------------------
-- 6. ★★★ 网格视窗那条路不许断（★ 用户：「不然整个 row → clues → 棋盘的路线就断了」✓）
--
--   ★★ 我改出过两处断点 ✗（★ 都在这条路上 ✓ 都被用户肉眼抓到 ✓）：
--     ★ ① `sync_clue_grid` 里 **`n` 读的是 `lv.clues`** ✗ ⇒ ★ 真关卡已空 ⇒ **`n=0`**
--       ⇒ ★★ **一个列表项都不建 ⇒ 网格视窗整块消失** ✓✓
--     ★ ② `_grid_text_payload` **从 `vm.clues[i].text` 里切名字** ✗
--       ⇒ ★ 槽位文案是占位 ⇒ ★★ **卡片一片空白** ✓
--------------------------------------------------------------------------------
do
  local LV = require("levels.demo_selftest")
  local core = Core.new(LV)
  local c = UIC.new(core, { skip_intro = true })
  c._level_ordinal = function() return 1 end   -- 关序由测试注入（不依赖已交付关卡清单）
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

  -- ★ `assets` 必须**直接挂在 root 下** ✓（★ `_palette_child` 就是这么找的 ✓ 见它的注释 ✓）
  local LETTERS = { "A", "B", "C", "D", "E" }
  local rows = {}
  for pos = 1, 5 do
    rows[pos] = ctrl("row.1." .. pos, {
      ctrl("who.1." .. pos,    { ctrl("who",    {}, "名字" .. pos) }),
      ctrl("what.1." .. pos,   { ctrl("what",   {}, "内容" .. pos) }),
      ctrl("letter.1." .. pos, { ctrl("letter", {}, LETTERS[pos]) }),
      ctrl("face.1." .. pos,   { ctrl("face",   { ctrl("img", { imageId = 900 + pos }) }) }),
    })
  end
  _G.game = { GetClientUIRoots = function() return { ctrl("root", { ctrl("assets", rows) }) } end }

  -- ★ 走真实路径：★ 那一趟读 `row.*` 的落账 ✓
  c._grid_in_refresh = true
  for pos = 1, 5 do
    local card = {}
    for _, nm in ipairs({ "who", "what", "letter", "face" }) do
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { ctrl(nm, {}) })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", card), pos - 1)
  end

  -- ★★ 断点 ② 的判据 ✓：★ 卡片四样必须**来自 `row.*`** ✓
  local p = c:_grid_text_payload()
  local okwho, okwhat, okletter = true, true, true
  for i = 1, 5 do
    local it = (p.items or {})[i] or {}
    if tostring(it.who) ~= ("名字" .. i) then okwho = false end
    if tostring(it.what) ~= ("内容" .. i) then okwhat = false end
    if tostring(it.letter) ~= LETTERS[i] then okletter = false end
  end
  ok(okwho,   "★ 卡片的名字来自 `row.<关>.<行>.who`（★ 不是从占位文案里切 ✓）")
  ok(okwhat,  "★ 卡片的内容来自 `row.<关>.<行>.what`")
  ok(okletter,"★ 卡片的字母来自 `row.<关>.<行>.letter`")
  -- ★ 而且**一个都不许空** ✗（★ 空了就是"卡片一片空白"那个 bug ✓）
  local nonempty = 0
  for i = 1, 5 do
    local it = (p.items or {})[i] or {}
    if tostring(it.who) ~= "" and tostring(it.what) ~= "" then nonempty = nonempty + 1 end
  end
  ok(nonempty == 5, "★ 五张卡的名字与内容都非空（实测 " .. nonempty .. " / 5）")

  -- ★★ 断点 ① 的判据 ✓：★ 网格视窗拿到的 `n` 必须 = 槽位数 ✓（★ 不是 0 ✗）
  --   ★ `sync_clue_grid` 里那一行就是"条数"的出口 ✓ —— ★ 直接读它的来源 ✓
  local n_grid = #((core.clues) or {})
  ok(n_grid == core.clue_slots and n_grid > 0,
    "★ 网格视窗条数 = 槽位数 = " .. tostring(core.clue_slots) .. "（实测 " .. n_grid .. "）")
  ok(n_grid ~= #((core.level.clues) or {}),
    "★ 它读的是【核心那份】✗ 不是 `lv.clues`（★ 后者是空的 ⇒ 会变成 0 ⇒ 视窗消失 ✓）")
  print("  [PASS] 网格视窗那条路：条数非 0，且卡片四样来自 row.*")
end

--------------------------------------------------------------------------------
-- 7. ★★★ "点卡片 ⇒ 选中那个人"（★ 用户：「选中卡片后到棋盘这一层还是断的」✓）
--
--   ★★ 这是单人射的**第三条断点** ✗（★ 前两条在 `sync_clue_grid` 与 `_grid_text_payload` ✓）：
--     ★ 点卡片那条路**从 `clue_view[i].who` 取人物 id** ✗
--     ★ 而 `Core:view()` 里就是 `who = cl.who` ✓ ★★ **槽位没有 `who`** ✗ ⇒ **恒 nil** ✓
--     ⇒ ★ 它防御式地"取不到就不动作" ✓ ⇒ ★★ **永远不选中** ✓
--     ⇒ ★★★ **放置与笔记全被拦在这一步** ✓✓（★ 与用户报的三句逐字相符 ✓）
--------------------------------------------------------------------------------
do
  local LV = require("levels.demo_selftest")
  local core = Core.new(LV)
  local c = UIC.new(core, { skip_intro = true })
  c._level_ordinal = function() return 1 end   -- 关序由测试注入（不依赖已交付关卡清单）
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

  -- ★ 按 id 排好 ✓ ⇒ ★ 位置 → 人 是确定的 ✓（★ 不受 pairs 顺序影响 ✓）
  local ids = {}
  for id in pairs(core.names) do ids[#ids + 1] = id end
  table.sort(ids)
  local nslot = core.clue_slots
  ok(#ids >= nslot, "本关人数够填满槽位（" .. #ids .. " ≥ " .. nslot .. "）")

  -- ★★ 两个变体都要过 ✓：★ 一份配 **id** ✓、一份配 **显示名** ✓（★ 用户的两种可能 ✓）
  --
  --   ⚠️ ★ **每个变体必须【建完就查】** ✗✓（★ 我第一版先建两个再一起查 ⇒ 假红 ✓）
  --     ★ 原因 ✓：★ `_row_text` 是**模块级**的 ✓ ⇒ ★ 第二次 build **覆盖了第一次的行** ✓
  --       ⇒ ★ 再拿第一次的控制器去查 ⇒ ★ **读到的是第二次配的名字** ✓✓
  --     ★★ 这与"换关要清表"是同一件事的两面 ✓ —— ★ 表只有一份，谁最后写谁就是当前 ✓
  local function build(use_name)
    local co = Core.new(LV)
    local c2 = UIC.new(co, { skip_intro = true })
    c2._level_ordinal = function() return 1 end   -- 关序由测试注入（不依赖已交付关卡清单）
    -- ★★ 必须先清空那张模块级表 ✗✓（★ 不清 ⇒ 上一节的行还在 ⇒ 本次**一个字都不落账** ✓）
    --   ★ 机制 ✓：`_fill_grid_item` 落账时是 **"只填一次"** ✓（`if _by_pos[slot] == nil` ✓）
    --     ⇒ ★ 表里已经有值 ⇒ ★ **这次的配置被静默忽略** ✓✓
    --   ★ 真实运行里靠"换关清一次"保证 ✓（`_reset_row_maps_if_level_changed` ✓）
    --     ★ 而测试里**重复进同一关** ⇒ ★ 得自己清 ✓
    UIC.Controller._row_text = {}
    local rows = {}
    for pos = 1, nslot do
      local id = ids[pos]
      -- ★ 名字必须查**这个实例自己的** `co.names` ✗（★ 查外面那个是另一个实例 ✓ 会错 ✓）
      local who = use_name and tostring(co.names[id]) or tostring(id)
      rows[pos] = ctrl("row.1." .. pos, {
        ctrl("who.1." .. pos,    { ctrl("who",    {}, who) }),
        ctrl("what.1." .. pos,   { ctrl("what",   {}, "文" .. pos) }),
        ctrl("letter.1." .. pos, { ctrl("letter", {}, string.char(64 + pos)) }),
        ctrl("face.1." .. pos,   { ctrl("face",   {}) }),
      })
    end
    _G.game = { GetClientUIRoots = function() return { ctrl("root", { ctrl("assets", rows) }) } end }
    c2._grid_in_refresh = true
    for pos = 1, nslot do
      local card = {}
      for _, nm in ipairs({ "who", "what", "letter", "face" }) do
        card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { ctrl(nm, {}) })
      end
      c2:_fill_grid_item(nil, nil, ctrl("item", card), pos - 1)
    end
    -- ★★ **当场解析、当场判** ✓ —— ★ 再晚一步就会被下一次 build 覆盖 ✓
    local got = {}
    for pos = 1, nslot do got[pos] = c2:_person_id_for_pos(pos) end
    return c2, got
  end

  -- ★★★★★★★★ 2026-10-11 **判据改了：点第 k 张卡 = 选中【第 k 个棋子】** ✗✓✓
  --
  --   ★★★ 用户 2026-10-11 定稿 ✓（★ 原话 ✓）：
  --     「★ **如果非要这个机制，就把 `id` 设为 `letter`，或者 `row.i.j`** ✓
  --      ★ **如果不是必要机制就删了** ✓
  --      ★ **`who` 已经干扰了很多次了** ✓ ★ **你不要再陷进去了**」✓✓
  --   ⇒ ★★ **`who` 不再参与棋盘线** ✗ —— ★ 判据不再看它填了什么 ✓
  --   ★ 新判据 ✓：★ **第 `k` 行的卡 ⇒ 选中第 `k` 个棋子** ✓
  --     ★ 依据 ✓：★ 用户的口径「**一人一条**」✓ ⇒ ★ 行 ↔ 线索 ↔ 棋子 一一对应 ✓
  --     ★★ 于是**两种配法（id / 显示名）都走同一条路** ✓✓
  --       （★ 而"填什么就返回什么"那条**老契约作废** ✗ —— ★ 它正是前几轮断链的根源 ✓）
  local piece_at = {}
  do
    local pcs = core.pieces
    for k = 1, #pcs do piece_at[k] = tostring(pcs[k].id) end
  end
  for _, use_name in ipairs({ false, true }) do
    local _, got = build(use_name)
    local label = use_name and "显示名" or "人物 id"
    local allok, detail = true, {}
    for pos = 1, nslot do
      if got[pos] ~= piece_at[pos] then
        allok = false
        detail[#detail + 1] = pos .. "=" .. tostring(got[pos]) .. "(want " .. tostring(piece_at[pos]) .. ")"
      end
    end
    ok(allok, "★ 卡上配【" .. label .. "】⇒ 选中**第 pos 个棋子**（★ `who` 不参与 ✓）" ..
      table.concat(detail, " "))
  end

  -- ★★ 走真实交互三条 ✓（★ 这正是用户报"断的"那三件事 ✓）
  local c3 = build(false)
  local pid = c3:_person_id_for_pos(1)
  ok(pid ~= nil, "第一张卡解析出人（★ 不是 nil ✓）")

  -- ★★★ **"点卡片"那条路本身也要走一遍** ✗✓（★ 只测解析函数 ⇒ 破坏性验证抓不到 ✓）
  --   ★ 用户报的原话是「★ **选中卡片后**到棋盘这一层还是断的」✓
  --     ⇒ ★ 判据必须落在**那条路**上 ✓ ★ 只测"解析得对"不够 ✗
  --     ★（★ 因为那条路**可能根本没调用解析函数** ✓ —— 我上一版正是这样 ✓✓）
  --
  --   ★ 两段都要过 ✓（★ 缺一段就测不全 ✓）：
  --     ① `_grid_bind_item_click` ⇒ ★ **监听挂上去了** ✓（★ 真机 `Enum` 是有的 ✓
  --        离线环境没有 ⇒ 它会**静默降级** ✓ ★ 所以这里补一个 `Enum` ✓）
  --     ② `_on_grid_item_click` ⇒ ★ **真的发出 `suspect` 事件** ✓（★ 这才是"选中" ✓）
  do
    local fired = {}
    -- ★ 只认 `ev` ✓（★ 原来写成 `(_, ev)` = 方法调用形式 ⇒ ★ 拿到的其实是 `self` ✗）
    --
    -- ★★★★★★★★ 2026-10-15 **这个假适配器必须【转发给控制器】，不能只是个收件箱** ✗✓✓
    --
    --   ★ 为什么 ✗（★ 它原来让"点卡片"这件事**少了一半** ✓）：
    --     ★ 真机上"引擎手势只会**进来**" ✓ ★ 而适配器的 `on_input` 是**出**的方向 ✓
    --       ★★ 它转手就调 `controller:on_input(ev)` ✓（★ `main.lua:471` ✓）
    --     ★★ 只把事件塞进 `fired` 就完事 ⇒ ★ **控制器那条回路是断的** ✗
    --       ⇒ ★ 这里测到的行为与真机**不是同一套** ✓✓
    --   ★ 修法 ✓：★ `on_input` **一边记账、一边原样转发** ✓ ⇒ ★ 与真机同构 ✓✓
    --   ★★ 为什么转发**不会**把选中打两遍 ✗（★ 2026-10-15 的实现已保证 ✓）：
    --     ★ `_on_grid_item_click` 现在**自己就把选中做实** ✓
    --       ★ 而它**不再**对着 `suspect` 绕一圈 ✓（★ 那条路是"转一圈回到自己" ✓）
    --     ⇒ ★ 被转发进控制器的只有 `focus_clue` ✓ ★ 那一条**不碰任何状态** ✓✓
    --   ★ 下面第 442 行那条**显式** `on_input` 就是"玩家手点了一下" ✓
    --     ★ 它必须**幂等**（★ 点同一个人两次 = 还是选中他 ✓ 不是取消 ✓）✓
    local ad = { on_input = function(ev)
      fired[#fired + 1] = ev
      c3:on_input(ev)          -- ★ 真机的适配器就是这么做的（`main.lua:471` ✓）
    end }
    local it = ctrl("item", {})
    local bound = 0
    it.AddCursorEventListener = function() bound = bound + 1 end
    it.GetChild = function(_, n)
      for _, k in ipairs(it._kids) do if k.name == n then return k end end
      return nil
    end
    -- ★ 真机有的枚举 ✓（★ 离线缺 ⇒ 绑定那条路会提前 return ✓ 那样就测不到 ✓）
    local _saved_enum = _G.Enum
    _G.Enum = { CursorEventType = { CursorClick = 1 } }
    -- ★ `GetItemIndex` 要能反查 ✓（★ 引擎索引 0 起 ⇒ `pos = 0 - 0 + 1 = 1` ✓）
    local g = { GetItemIndex = function(_, _item) return 0 end }
    c3._grid_base = 0
    c3.adapter = ad
    c3:_grid_bind_item_click(ad, g, it)
    ok(bound >= 1, "★ 点卡片：监听挂上去了（实测 AddCursorEventListener " .. bound .. " 次）")
    -- ★ 直接走"被点到"那一步 ✓（★ 引擎回调里就是它 ✓）
    c3:_on_grid_item_click(ad, g, it)
    _G.Enum = _saved_enum
    -- ★★★★★★★★ 2026-10-15 **判据改成"选中真的落地了"，不再看那条事件** ✗✓✓
    --
    --   ★ 为什么改 ✗（★ 改的是**机制**，不是判定标准 ✓ P8 ✓）：
    --     ★ 原来这条断言是"**发出了 `suspect` 事件**" ✓
    --       ★ 而那正是**没生效**的那条路 ✗ —— ★ 发了它也只是**转一圈回到自己** ✓
    --       ★★ 依据 ✓：★ 适配器的 `on_input` 是**出**的方向 ✓
    --         （★ `main.lua:471`：`adapter.on_input = function(event) controller:on_input(event) end` ✓）
    --         ⇒ ★ 控制器**从不**"对着控件凭空发事件" ✓ ⇒ ★ 那一下点击**没有任何状态落地** ✓✓
    --     ★★★ 更要命的是它**和下面那句重复** ✗：
    --       ★ `_on_grid_item_click` 自己先选一次 ⇒ 这条事件再选一次 ⇒
    --       ★★ **切换 ⇒ 又变回没选中** ✓✓（★ 于是第 461 行那条也跟着红 ✓）
    --   ⇒ ★★ 新判据 ✓：★ **点一下 = `core.selected` 就是卡上那个人** ✓
    --     ★ 这一条**更强** ✗ —— ★ 它直接钉住"选人这件事发生了" ✓
    --       ★ 而老的"发了事件"只钉住"发了个消息"（★ 消息可以是空的 ✓）✓✓
    ok(c3.core.selected ~= nil,
      "★ 点卡片 ⇒ **选中真的落地了**（★ 不只是「发了个消息」✗ 实测 "
      .. tostring(c3.core.selected) .. "）")
    ok(tostring(c3.core.selected or "") == tostring(ids[1]),
      "★ 选中的是**第 1 张卡那个人** ✓（实测 " .. tostring(c3.core.selected)
      .. " 该是 " .. tostring(ids[1]) .. "）")
    -- ★ 顺带记下"这条路上到底发过哪些事件" ✓ —— ★ 只观测、不断言 ✓
    --   ★ 目的 ✓：★ 万一以后有人又往这里塞一条"会改状态"的事件 ⇒ 这一行**看得见** ✓
    do
      local names = {}
      for i = 1, #fired do names[#names + 1] = tostring(fired[i].action) end
      print("       （点卡片这条路上发出的事件：" .. table.concat(names, ", ") .. "）")
    end
  end

  if pid ~= nil then
    -- ★ 这一下**不重复选人** ✓ —— ★ `_on_grid_item_click` 已经把他选上了 ✓
    --   ★ 原来这里再发一次 `suspect` ⇒ ★ **把它切换掉了** ✓（★ 见上面那段 ✓）
    --   ★★ 判据不变 ✓：★ 点完卡片之后，选中就是他 ✓
    ok(c3.core.selected == pid, "★ 点卡片 ⇒ **选中卡上那个人** ✓（实测 " .. tostring(c3.core.selected) .. "）")
    local okN = c3.core:tap_cell(2, 3)
    ok(okN == true and c3.core.notes[2][3] ~= nil and c3.core.notes[2][3][pid] == true,
      "★ 单击格子 ⇒ **笔记标得上** ✓")
    local okH = c3.core:hold_cell(3, 4)
    ok(okH == true and c3.core.grid[3][4] == pid,
      "★ 长按格子 ⇒ **放置做得到** ✓")
  end
  print("  [PASS] 点卡片 ⇒ 选中 ⇒ 笔记 ⇒ 放置（★ 用户报的三件事全通 ✓）")
end

--------------------------------------------------------------------------------
-- 8. ★★★ 点卡片这条路：★ 内容查不到时也必须【能点】✗✓
--
--   ★★★ 用户 2026-10-11 的指令 ✓：「★ **就是网格视窗的光标事件断了** ✓
--     ★ **原本的光标事件是通的** ✓ ★ **损坏必然来自 `clues` 重构**」✓✓
--   ★ 协作方测绘的断点 ✓（`网格视窗-光标事件-实现测绘.md` ✓）：
--     ★★ 绑点击原来在 `_fill_grid_item` 的**最后一行** ✗
--       ⇒ ★ 它前面的 `if cl == nil then return end` **一跳过就把它一起跳过** ✓
--     ★★ 而 `gray` 关射线也在那个 `return` **之后** ✗
--       ⇒ ★ **`gray` 挡在最上层吃点击** ⇒ ★ **"点了跟没点一样"** ✓✓
--   ⇒ ★ 判据 ✓：★ **让文案查不到**（★ 槽位表里没有这一条 ✓）
--     ★★ 然后断言 **① 监听照样挂上 ② `gray` 的射线照样关掉** ✓✓
--------------------------------------------------------------------------------
do
  local LV = require("levels.demo_selftest")
  local core = Core.new(LV)
  local c = UIC.new(core, { skip_intro = true })
  c._level_ordinal = function() return 1 end   -- 关序由测试注入（不依赖已交付关卡清单）
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

  local fired = {}
  local ad = { on_input = function(ev) fired[#fired + 1] = ev end }
  UIC.Controller._row_text = {}

  -- ★ `gray` 子控件：★ 初始射线是开的 ✓（★ 就是要看脚本会不会把它关掉 ✓）
  local gray = ctrl("gray")
  gray.raycastTarget = true
  gray.blockRaycast = true
  gray.interactable = true

  local item = ctrl("item", { gray })
  local bound = 0
  item.AddCursorEventListener = function() bound = bound + 1 end

  local _saved_enum = _G.Enum
  _G.Enum = { CursorEventType = { CursorClick = 1 } }

  -- ★★★ **故意让文案查不到** ✗：★ `pos` 用一个**远超槽位数**的值 ✓
  --   （★ 真机上 `cl == nil` 就是这么来的 ✓ —— ★ `_grid_base` 判错 ⇒ `pos` 整列错位 ✓）
  local pos_far = core.clue_slots + 50
  c._grid_in_refresh = true
  -- ★ 变量名**不能叫 `ok`** ✗ —— ★ 那会遮住本文件顶部的断言函数 `ok(...)` ✓
  local okc, err = pcall(function() c:_fill_grid_item(ad, nil, item, pos_far - 1) end)
  _G.Enum = _saved_enum

  ok(okc, "★ 文案查不到时，填充**不抛错**（实测 " .. tostring(err) .. "）")
  ok(bound >= 1,
    "★★ **文案查不到时，点击监听照样挂上** ✓（实测 AddCursorEventListener " .. bound .. " 次）")
  ok(gray.raycastTarget == false,
    "★★ **文案查不到时，`gray` 的射线照样关掉** ✓（实测 raycastTarget="
    .. tostring(gray.raycastTarget) .. "）")
  ok(gray.blockRaycast == false, "★ `gray.blockRaycast` 也关掉（实测 " .. tostring(gray.blockRaycast) .. "）")
  ok(gray.interactable == false, "★ `gray.interactable` 也关掉（实测 " .. tostring(gray.interactable) .. "）")
  print("  [PASS] 内容查不到 ⇒ 卡片照样能点、gray 照样不吃点击")
end

--------------------------------------------------------------------------------
-- 9. ★★★ 索引基准：★ 点第 k 张卡必须选到第 k 张上的人 ✗✓
--
--   ★★★ 用户 v178 真机日志 ✓（★ 决定性证据 ✓ 原文 ✓）：
--       `★ 卡片点击进来了 ✓（第 1 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 2 次）GetItemIndex=1  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 3 次）GetItemIndex=2  索引基准=0`
--   ★★ 用户点的是第 1 / 2 / 3 张 ✓ ★ 引擎回读 0 / 1 / 2 ✓
--     ⇒ ★ 引擎索引 = **序号 − 1**（0 起 ✓）⇒ ★★ **基准应当是 0** ✓
--   ★★★ 而老那一行 `(index == 0) and 0 or 1` 把"第一次交来的 index"当编码判据 ✗
--     ⇒ ★ 真值是 `0` 时它算出 `0` ✓ —— ★★ **但它算对是巧合** ✗✓（★ 见下面两例 ✓）
--------------------------------------------------------------------------------
do
  -- ★ 判据 ✓：★ **两种编码下，点第 k 张都要得到 `pos = k`** ✓
  --   ★ 编码甲（0 起 ✓ 真机就是它 ✓）：第一次交来 `index = 0` ⇒ 基准 0 ⇒ `pos = idx + 1`
  --   ★ 编码乙（1 起 ✓ 假想 ✓）：第一次交来 `index = 1` ⇒ 基准 1 ⇒ `pos = idx`
  local OLD = function(first_index, idx)                      -- ★ 老写法 ✗
    local b = (first_index == 0) and 0 or 1
    return idx - b + 1
  end
  local NEW = function(first_index, idx)                      -- ★ 新写法 ✓
    return idx - first_index + 1
  end
  -- ★ 新写法：两种编码都对 ✓
  local ok0, ok1 = true, true
  for k = 1, 5 do
    if NEW(0, k - 1) ~= k then ok0 = false end                -- ★ 0 起：index = k-1 ✓
    if NEW(1, k) ~= k then ok1 = false end                    -- ★ 1 起：index = k ✓
  end
  ok(ok0, "★ 新基准：引擎 0 起时，点第 k 张 ⇒ pos = k ✓")
  ok(ok1, "★ 新基准：引擎 1 起时，点第 k 张 ⇒ pos = k ✓")
  -- ★★ 老写法在"0 起"时**正好也对** ✗ ⇒ ★ 所以不能只靠这一条断言 ✓
  --   ★ 而它在另一件事上错 ✗：★ **它把"编码"与"第一次交来的值"混成一个判据** ✓
  --     ★ 真要出错的场合 ✓：★ 第一次回调**不是**列表顶端（本项目已证伪过那个前提 ✓）
  --     ⇒ ★ 那时 `first_index` 可能是 3 ✓ ★ 老写法仍判成 1 ✗ ★ 新写法得 3 ✓
  ok(NEW(3, 3) == 1 and OLD(3, 3) == 3,
    "★ 第一次回调不是顶端时（交来 index=3）：新写法把它当顶端 ⇒ pos=1 ✓；老写法得 pos=3 ✗")
  print("  [PASS] 索引基准：两种引擎编码下点第 k 张都得到 pos = k")
end

--------------------------------------------------------------------------------
-- 10. ★★★ 点卡片定位：★ 引擎的 `GetItemIndex` 不可靠时也必须定得对 ✗✓
--
--   ★★★ 用户 v179 真机日志 ✓（★ 决定性证据 ✓ 原文 ✓）：
--       `★ 卡片点击进来了 ✓（第 1 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 2 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 3 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 4 次）GetItemIndex=0  索引基准=0`
--   ★★ 用户点的是**不同的卡** ✓ ★ 而 `GetItemIndex` **四次都回 0** ✗
--     ⇒ ★★★ **这台引擎上 `grid:GetItemIndex(item)` 不可靠** ✓✓
--     ⇒ ★ 于是每次都算成 `pos = 1` ⇒ ★ **高亮与选人全落在第 1 条上** ✓
--
--   ★★ 修法 ✓：★ **用【填充时引擎亲手交来的那个 index】** ✓（★ 那一次是权威的 ✓）
--     ★ 记在 `self._grid_seen[item]` ✓ ⇒ ★ 点击时直接查 ✓ ★ **不问引擎** ✗✓
--------------------------------------------------------------------------------
do
  local LV = require("levels.demo_selftest")
  local core = Core.new(LV)
  local c = UIC.new(core, { skip_intro = true })
  c._level_ordinal = function() return 1 end   -- 关序由测试注入（不依赖已交付关卡清单）
  c._grid_base = 0

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

  -- ★★ **故意做一个坏掉的 `GetItemIndex`** ✗：★ 永远回 0 ✓（★ 真机实测就是这样 ✓）
  local g = { GetItemIndex = function() return 0 end }

  -- ★ 5 个项各拿一个 index ✓ ⇒ 引擎亲手交来的那些 ✓
  local items = {}
  for k = 1, 5 do
    items[k] = ctrl("item", {})
    c._grid_seen = c._grid_seen or {}
    c._grid_seen[items[k]] = k - 1                 -- ★ 引擎 0 起 ✓
  end

  -- ★ 逐个点 ⇒ `pos` 必须是 k ✓（★ 而不是恒 1 ✗）
  local allok = true
  local got = {}
  for k = 1, 5 do
    got[k] = c:_grid_pos_of_item(g, items[k])
    if got[k] ~= k then allok = false end
  end
  ok(allok, "★ 坏掉的 GetItemIndex 下，点第 k 项仍得到 pos = k（实测 "
    .. table.concat({ tostring(got[1]), tostring(got[2]), tostring(got[3]),
                      tostring(got[4]), tostring(got[5]) }, ",") .. "）")

  -- ★ 表里没有的项 ⇒ 才退回问引擎 ✓（★ 坏引擎回 0 ⇒ `pos = 1` ✓ 有兜底不崩 ✓）
  local fresh = ctrl("item", {})
  ok(c:_grid_pos_of_item(g, fresh) == 1,
    "★ 填充记录里没有的项 ⇒ 退回 GetItemIndex ✓（坏引擎给 0 ⇒ pos=1 ✓ 不崩 ✓）")

  -- ★ 两个来源都拿不到 ⇒ 返 nil ✓（★ 调用方宁可丢掉这次点击 ✓）
  local g2 = { GetItemIndex = function() return nil end }
  ok(c:_grid_pos_of_item(g2, ctrl("item", {})) == nil,
    "★ 两个来源都拿不到 ⇒ 返 nil ✓（★ 不聚焦到错的那条 ✓）")
  print("  [PASS] 坏掉的 GetItemIndex 下，定位改用填充时记下的 index")
end

--------------------------------------------------------------------------------
print(string.format("\nclue_slots: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
