--[[----------------------------------------------------------------------------
  levels/simple.lua —— **"直接指定第几行放什么"** 的关卡写法（用户 2026-10-09 要求）

  用户原话：
    · 「我的要求只是**我能直接指定第几关第几行放什么**」
    · 「只要符合我目标的**达成方案**就行；素材往哪填、从哪取**随时可以改**」

  ── 为什么需要它 ──────────────────────────────────────────────────────────
  现在写一关要同时维护**七处**：
      suspects / walls / doors / objects / meta / solution / clues
  而其中**只有 `board`（谁在第几行第几列）是你真正想表达的东西** ✓
  其余六处都是**同一件事的派生**或**结构性噪音** ✓

  ⇒ 本模块让你**只写 `board`** ✓，其余自动派生 ✓
    （仍然**完全兼容**旧写法 —— 现有 4 关一个字都不用改 ✓）

  ── 用法 ──────────────────────────────────────────────────────────────────
      local S = require("levels.simple")
      return S.expand {
        id = "case_004", name = "案件 004 · …",
        rows = 5, cols = 5,

        -- ★ 就这一张表：第几行、第几列、放谁
        board = {
          { r = 1, c = 3, who = "D" },
          { r = 3, c = 1, who = "A" },
          { r = 2, c = 2, who = "B" },
          { r = 5, c = 4, who = "C" },
          { r = 4, c = 5, who = "V" },
        },

        -- 也可以**只写行**，列自动推（见下面 `deduce_cols`）
        --   board = { { r = 1, who = "D" }, { r = 3, who = "A" }, … }

        people = {                       -- 名字 / 头像（可省，省了就用字母当名字）
          D = { name = "旧识古董商" },
          V = { name = "收藏家", victim = true },
        },
        thief = "D",
        clues = { … },                   -- ★ **必须手写** ✓（★ 不再自动生成 ✓ 见下 ✓）
      }

  产物 = 引擎认识的完整关卡表 ✓（`init.lua` / `murdoku_core` 不需要改 ✓）

  ⚠️ 纪律：**不猜**。列推不出来时它**报错并列出候选**，不替玩家决定 ✓
----------------------------------------------------------------------------]]--

local M = {}

-- ── 只给行时把列推出来 ────────────────────────────────────────────────────
--   规则（与引擎的 `one_per_row` / `one_per_col` 一致 ✓）：
--     每行恰好一人、每列恰好一人 ⇒ 若某一行只差一列没人占 ⇒ 就是它 ✓
--   ⚠️ 推不出来 ⇒ **报错**，不要瞎填 ✓
local function deduce_cols(board, rows, cols)
  local taken = {}                     -- taken[c] = true
  for i = 1, #board do
    local b = board[i]
    if b.c ~= nil then taken[b.c] = true end
  end
  for i = 1, #board do
    local b = board[i]
    if b.c == nil then
      local free = {}
      for c = 1, cols do if not taken[c] then free[#free + 1] = c end end
      if #free ~= 1 then
        error(string.format(
          "levels.simple：第 %d 行（who=%s）没给列，而剩下的空列有 %d 个（%s）⇒ 推不出来。"
          .. "请直接写 `c = <第几列>`。",
          b.r or i, tostring(b.who), #free,
          (function() local t = {} for k = 1, #free do t[k] = tostring(free[k]) end return table.concat(t, ",") end)()))
      end
      b.c = free[1]
      taken[free[1]] = true
    end
  end
end

-- ★★★ 2026-10-11 **`auto_clues` 已删** ✗✓（★ 用户原话 ✓）：
--   「★ **原本那套为每关人物发位置和字母的逻辑直接删了** ✓
--    ★ **关卡设计本来就要改** ✓ ★ **不用留着他了**」✓
-- ★ 删掉的正是这个函数 ✓：★ 它给**每个人**自动发两条 `in_row` / `in_col`
--   ⇒ 那就是"**为每关人物发位置**" ✓ ★ 也正是那套要被换掉的东西 ✓
-- ⇒ ★★ 现在：★ `clues` **必须手写** ✓ —— ★ 不写就是**空** ✓ ★ **不再自动编** ✓✓

-- ── 展开 ──────────────────────────────────────────────────────────────────
function M.expand(spec)
  assert(type(spec) == "table", "levels.simple.expand：要一张表")
  assert(type(spec.board) == "table" and #spec.board > 0,
    "levels.simple.expand：至少要给 `board`（谁在第几行第几列）")

  local rows = spec.rows or 5
  local cols = spec.cols or rows

  -- ① 列：给全了就不动，缺了才推 ✓
  local board = {}
  for i = 1, #spec.board do
    local b = spec.board[i]
    assert(type(b.who) == "string" and b.who ~= "", "levels.simple：board 第 " .. i .. " 项缺 `who`")
    assert(type(b.r) == "number", "levels.simple：board 第 " .. i .. " 项（who=" .. b.who .. "）缺 `r`")
    board[i] = { r = b.r, c = b.c, who = b.who }
  end
  deduce_cols(board, rows, cols)

  -- ② solution：**直接从 board 派生** ✓（这就是"第几行放什么"的本体 ✓）
  local solution, ids = {}, {}
  for i = 1, #board do
    local b = board[i]
    assert(solution[b.who] == nil, "levels.simple：`" .. b.who .. "` 在 board 里出现了两次")
    solution[b.who] = { r = b.r, c = b.c }
    ids[#ids + 1] = b.who
  end
  table.sort(ids)

  -- ③ suspects：也从 board 派生（名字/头像来自 `people`，缺省用字母 ✓）
  local people = spec.people or {}
  local suspects = {}
  for i = 1, #ids do
    local id = ids[i]
    local p = people[id] or {}
    suspects[i] = {
      id = id,
      name = p.name or id,
      portrait = p.portrait or ("portrait." .. id),
      gender = p.gender,
      is_victim = (p.victim == true) or (spec.victim == id),
    }
  end

  -- ④ 组装：**用户写的字段优先**，派生字段只在缺省时补 ✓
  local lv = {}
  for k, v in pairs(spec) do lv[k] = v end     -- 透传（walls/doors/objects/meta/… 一个不丢 ✓）
  lv.board = nil                               -- 这是"输入格式"，不进引擎 ✓
  lv.rows, lv.cols = rows, cols
  lv.size = lv.size or { rows = rows, cols = cols }
  lv.suspects = lv.suspects or suspects
  lv.solution = lv.solution or solution
  -- ★★★ 2026-10-11 **不再自动生成线索** ✗✓（★ 原来这里是 `lv.clues or auto_clues(board)` ✓）
  --   ★ 用户明确要求删掉那套"为每关人物发位置和字母"的逻辑 ✓ ⇒ ★ **不写就是空** ✓
  --   ⚠️ ★ 后果 ✓：★ 线索空 ⇒ `Core.new` 照旧能起来 ✓ ★ 但 `validate_levels` 的**唯一解**
  --     闸门会报多个解 ✓ —— ★ 那是**内容还没设计** ✓ ★ 不是逻辑坏了 ✓
  lv.clues = lv.clues or {}
  lv.victim = lv.victim or (function()
    for i = 1, #suspects do if suspects[i].is_victim then return { id = suspects[i].id, name = suspects[i].name } end end
    return nil
  end)()
  lv.roles = lv.roles or { thief = spec.thief }
  lv.meta = lv.meta or { false_clue = 0, announce = "none" }
  return lv
end

-- ── 一个可直接用的样例（也是自检脚本 `tests/simple_level.lua` 的夹具）─────
function M.demo()
  return M.expand {
    id = "demo_simple", name = "样例 · 直白摆放表",
    rows = 4, cols = 4,
    board = {
      { r = 1, c = 2, who = "D" },
      { r = 2, c = 4, who = "A" },
      { r = 3, c = 1, who = "B" },
      { r = 4, c = 3, who = "V" },
    },
    people = {
      A = { name = "值班保安" },
      B = { name = "前台姑娘" },
      D = { name = "旧识古董商" },
      V = { name = "收藏家", victim = true },
    },
    thief = "D",
  }
end

return M
