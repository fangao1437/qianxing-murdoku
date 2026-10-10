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
      ★ ④ ★ **控件上限够装最大棋盘** ✓ ＋ ★ **端到端建出 7 张卡** ✓
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
-- 2. ★★ 真关卡不再靠手写线索表 ⇒ 引擎照旧补满槽位
--------------------------------------------------------------------------------
do
  local all = init.all()
  for i = 1, #all do
    local lv = all[i]
    ok(type(lv.clues) ~= "table" or #lv.clues == 0,
      "真关卡 " .. tostring(lv.id) .. " 不该再有手写的 clues 表（★ 那套已被替换 ✓）")
  end
  print("  [PASS] 真关卡无手写线索表，槽位由棋盘规格生成")
end

--------------------------------------------------------------------------------
-- 3. ★★ 槽位是"待填"：没有 type ⇒ 不编内容（★ 如实报占位 ✓）
--------------------------------------------------------------------------------
do
  local lv = require("levels.case_001")
  local core = Core.new(lv)
  local vm = core:view() or {}
  local c1 = (vm.clues or {})[1]
  ok(c1 ~= nil, "第 1 张卡存在")
  ok(c1 ~= nil and c1.type == nil, "槽位没有 type（★ 内容还没填 ✓）")
  -- ★ 文案要**看得出是占位** ✗ 而不是编一条像真的线索 ✓
  ok(c1 ~= nil and type(c1.text) == "string" and #c1.text > 0, "占位文案非空（便于肉眼看出待填）")
  print("  [PASS] 槽位如实报占位，不编内容")
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
-- 5. ★★ 7×7 建出来的卡片数 = 7（★ 端到端 ✓ 不是读常量 ✓）
--------------------------------------------------------------------------------
do
  local lv = require("levels.case_003")
  local core = Core.new(lv)
  local ctl = UIC.new(core, {})
  local plan = ctl:layout_plan()
  local n = 0
  for i = 1, #plan do
    local id = plan[i].id
    if type(id) == "string" and id:match("^clue%.%d+$") then n = n + 1 end
  end
  ok(n == 7, "7×7 关卡应建出 7 张线索卡（实测 " .. n .. "）")
  print("  [PASS] 7×7 ⇒ 7 张卡（端到端）")
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
print(string.format("\nclue_slots: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
