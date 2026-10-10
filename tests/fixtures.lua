--[[----------------------------------------------------------------------------
  tests/fixtures.lua —— 给**离线测试**用的关卡（★ 带线索 ✓）

  ★★★ 为什么需要它 ✗（★ 2026-10-11 ✓）：
    ★ 用户要求把「**为每关人物发位置和字母的那套逻辑**」**整段删掉** ✓
     （★ 原话 ✓：「★ 原本那套为每关人物发位置和字母的逻辑直接删了 ✓
        ★ 关卡设计本来就要改 ✓ ★ 不用留着他了」✓）
    ⇒ ★★ **真关卡现在【没有线索】** ✓（★ `lua/levels/case_00N.lua` 的 `clues` 已删 ✓）

    ★ 而一批测试测的是「**有线索时**引擎行为对不对」✗：
      · `tests/selftest.lua`          ★ 线索判定 / 假话 / 唯一解 / 解出盗窃者 ✓
      · `tests/simple_level.lua`      ★ `levels/simple` 的展开 ✓
      · `tests/row_letter_map.lua`    ★ 单射把 `row.*` 的 `letter` 落到 `_row_letter` ✓
      · `tests/cell_mark_letter.lua`  ★ 格子显示 `letter` 而不是人物 id ✓
      · `tests/row_letter_stability.lua` ★ 同一人的字母必须确定 ✓

    ⇒ ★★ **它们需要"一条线索齐全的关卡"** ✓ —— ★ 而**真关卡已经不提供**了 ✗
      ★ 所以把这份"测试用关卡"**独立出来** ✓ —— ★ 不塞回真关卡 ✓（★ 那是用户要清的 ✓）
      ★ 也不塞进 `lua/` ✓（★ 那是**运行时** ✓ 一个测试专用模块不该进运行时 ✓）

  ★ 用法 ✓：
    local F = require("tests.fixtures")
    local lv = F.clue_level_5x5()      -- ★ 自检关的孪生兄弟 ＋ 7 条线索 ✓
    local lv = F.clue_level_6x6()      -- ★ 6×6 ＋ 15 条线索 ✓

  ★★ 纪律 ✓：★ 本文件的关卡**只服务于测试** ✓ ——
    ★ **不要**把它注册进 `levels/init.lua` ✗ ★ **不要**让游戏能选到它 ✗
----------------------------------------------------------------------------]]--

local M = {}

-- ★ 自检关（5×5）的**完整克隆** ＋ 它原来那 7 条线索 ✓
--   ★ 布局/墙/门/物件/答案全部照抄真关卡 ✓ ⇒ ★ 其它断言（区域、门径、唯一解）继续成立 ✓
function M.clue_level_5x5()
  local base = require("levels.demo_selftest")
  local lv = {}
  for k, v in pairs(base) do lv[k] = v end
  -- ★ 线索：★ 前 6 条为真 ✓ ★ 第 7 条是声明好的那句假话 ✓（★ `false_clue = 7` ✓）
  lv.clues = {
    { type = "at",     who = "B", r = 3, c = 2 },        -- 真
    { type = "at",     who = "A", r = 5, c = 3 },        -- 真
    { type = "at",     who = "V", r = 4, c = 1 },        -- 真
    { type = "at",     who = "D", r = 1, c = 4 },        -- 真
    { type = "in_row", who = "@thief", r = 1 },          -- 真（角色别名）
    { type = "in_col", who = "@accomplice", c = 5 },     -- 真
    { type = "in_col", who = "B", c = 1 },               -- ★ 第 7 条：假话（B 实际在第 2 列）
  }
  lv.meta = { false_clue = 7, announce = "one" }
  return lv
end

-- ★ `case_001`（5×5）的完整克隆 ＋ 它原来那 8 条线索 ✓
function M.clue_level_case001()
  local base = require("levels.case_001")
  local lv = {}
  for k, v in pairs(base) do lv[k] = v end
  lv.clues = {
    { type = "at",         who = "V",      r = 4, c = 5 },   -- 受害者就在保险库内室
    { type = "in_col",     who = "@thief", c = 3 },          -- 盗窃者在第 3 列
    { type = "in_row",     who = "@thief", r = 1 },          -- 盗窃者在第 1 行
    { type = "in_row",     who = "C",      r = 5 },          -- 清洁工在第 5 行
    { type = "in_col",     who = "B",      c = 2 },          -- 前台姑娘在第 2 列
    { type = "same_room",  a = "A", b = "B" },               -- 保安与前台在同一区
    { type = "in_row",     who = "A",      r = 3 },          -- 保安在第 3 行
    { type = "in_col",     who = "A",      c = 4 },          -- ★ 第 8 条：假话
  }
  lv.meta = { false_clue = 8, announce = "unknown" }
  return lv
end

-- ★ `case_002`（6×6）的完整克隆 ＋ 它原来那 15 条线索 ✓
--   ★★ 特意保留"**4 个人各被两条线索点到**"这个形状 ✗ ——
--      ★ `V` ← 1/2 ✓ ★ `E` ← 4/5 ✓ ★ `@thief` ← 6/7 ✓ ★ `@accomplice` ← 8/9 ✓
--      ⇒ ★ 它是 `row_letter_stability` 那个 bug 的**复现形状** ✓✓
function M.clue_level_6x6()
  local base = require("levels.case_002")
  local lv = {}
  for k, v in pairs(base) do lv[k] = v end
  lv.clues = {
    { type = "abs_col_from", who = "V",  n = 1, from = "right" },
    { type = "abs_row_from", who = "V",  n = 2, from = "bottom" },
    { type = "alone_with",   a = "V", b = "E" },
    { type = "col_offset", who = "E", other = "V", d = -1 },
    { type = "row_offset", who = "E", other = "V", d = 1 },
    { type = "abs_col_from", who = "@thief", n = 1 },
    { type = "abs_row_from", who = "@thief", n = 1 },
    { type = "col_offset", who = "@accomplice", other = "@thief", d = 3 },
    { type = "row_offset", who = "@accomplice", other = "@thief", d = 1 },
    { type = "col_offset", who = "A", other = "V", d = -3 },
    { type = "row_offset", who = "A", other = "V", d = -2 },
    { type = "col_offset", who = "B", other = "A", d = -1 },
    { type = "row_offset", who = "B", other = "A", d = 1 },
    { type = "not_role", who = "D" },
    { type = "abs_col_from", who = "C", n = 1 },
  }
  lv.meta = { false_clue = 15, announce = "one" }
  return lv
end

return M
