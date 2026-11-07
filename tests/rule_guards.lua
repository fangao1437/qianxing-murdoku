--[[----------------------------------------------------------------------------
  tests/rule_guards.lua —— 本轮三条新规则的守卫用例（v279）

  规则（用户本轮三条原话 → 契约见 docs/rules-guards-v279.md）：
    P  已经放置的人物的**同行同列**内不能再放置其它人物
    X  ✗ 标记与铅笔笔记**互斥**：任何方式出现的 ✗ 都擦掉该格全部笔记；
       在有 ✗ 的格上打笔记，则打的同时擦掉 ✗
    B  不可放置人物的**障碍物**格上也不可打笔记（✗ 仍然可以）

  为什么先写用例再改代码（TDD）：
    这三条全是"状态不变量"，而违反不变量的写法**在盘面上几乎看不出来**
    （多一个 ✗、少一条笔记，玩家只会觉得"点了一下没反应"）。
    所以先把判据钉死，再改 murdoku_core.lua。

  ⚠️ 双向断言纪律：每个状态变化同时断言
    「该发生的发生了」**和**「不该发生的没发生」——
    只断言一半的用例，曾经在"撤销不还原"这类缺陷上给过假绿。

  跑法：lua tests/rule_guards.lua
  退出码：0 全通过 / 1 有失败（与仓库其它 35 套一致）
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local M    = Core

local passed, failed = 0, 0
local function ok(cond, label, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  [FAIL] " .. label .. (detail ~= nil and ("   << " .. tostring(detail)) or ""))
  end
end
local function section(title) print("== " .. title .. " ==") end

-- 注释掉的调试位：需要看盘面时临时打开
local function dump_notes(core)
  local out = {}
  for r = 1, core.rows do
    for c = 1, core.cols do
      local n = {}
      for k in pairs(core.notes[r][c] or {}) do n[#n + 1] = tostring(k) end
      table.sort(n)
      if #n > 0 or core.x_marks[r][c] then
        out[#out + 1] = string.format("(%d,%d)%s%s", r, c,
          (#n > 0 and ("n=" .. table.concat(n, "")) or ""),
          core.x_marks[r][c] and "X" or "")
      end
    end
  end
  return table.concat(out, " ")
end

-------------------------------------------------------------------------------
-- 测试床：5×5，5 枚棋子，答案在主对角线上；(1,5) 是障碍物（不可站人）
-------------------------------------------------------------------------------
local function base_level()
  return {
    id = "guard_5x5",
    name = "守卫用例床",
    size = { rows = 5, cols = 5 },
    suspects = {
      { id = "A", name = "甲" },
      { id = "B", name = "乙" },
      { id = "C", name = "丙" },
      { id = "D", name = "丁" },
      { id = "V", name = "受害者", is_victim = true },
    },
    victim = { id = "V" },
    roles = { thief = "A" },
    -- (1,5) 障碍物：站不了人 ⇒ 本轮规则 B 的靶子
    blocked = { { r = 1, c = 5 } },
    -- 答案只需要"存在"，本文件测的是交互不变量，不是解题
    solution = {
      { who = "A", r = 1, c = 1 },
      { who = "B", r = 2, c = 2 },
      { who = "C", r = 3, c = 3 },
      { who = "D", r = 4, c = 4 },
      { who = "V", r = 5, c = 5 },
    },
  }
end

local function new_core(patches)
  local lv = base_level()
  for k, v in pairs(patches or {}) do lv[k] = v end
  local core, errs = Core.new(lv)
  if core == nil then
    print("  [FAIL] 用例床建不起来：" .. tostring(errs and errs[1]))
    failed = failed + 1
    return nil
  end
  return core
end

local function pick(core, id)          -- 选中（select_suspect 是"切换"，这里保证是选中态）
  if core.selected ~= id then core:select_suspect(id) end
  return core.selected == id
end

local function note_ids(core, r, c)
  local n = {}
  for k in pairs(core.notes[r][c] or {}) do n[#n + 1] = k end
  table.sort(n)
  return n
end

local function has_note(core, r, c, id)
  return core.notes[r][c] ~= nil and core.notes[r][c][id] == true
end

-- view() 的全局不变量：任何格子都不能同时"有 ✗"和"有笔记"
local function assert_view_invariant(core, tag)
  local vm = core:view()
  local bad = nil
  for r = 1, core.rows do
    for c = 1, core.cols do
      local cell = vm.cells[r][c]
      if cell.x and #cell.notes > 0 then bad = { r = r, c = c } end
    end
  end
  ok(bad == nil, tag .. "：view() 里不存在同时有 ✗ 和笔记的格子",
    bad and ("(" .. bad.r .. "," .. bad.c .. ")"))
end

-------------------------------------------------------------------------------
-- P. 放置守卫：同行同列不能再放"其它人物"
-------------------------------------------------------------------------------
section("P1 同行已有别人 ⇒ 正式放置被拒")
do
  local core = new_core()
  pick(core, "A")
  ok(core:hold_cell(2, 2) == true, "P1 前置：A 落在 (2,2)")
  -- ★ 双向：A 真的在盘上、且同行其余格被自动标了 ✗
  ok(core.grid[2][2] == "A", "P1 A 在 (2,2)")
  ok(core.x_marks[2][3] == true, "P1 同行 (2,3) 被自动标 ✗")
  pick(core, "B")
  local okb, why = core:hold_cell(2, 4)
  ok(okb == false, "P1 同行第 4 格拒绝放 B", tostring(okb))
  ok(core.grid[2][4] == nil, "P1 拒绝后 (2,4) 仍是空的（没偷偷放进去）", tostring(core.grid[2][4]))
  ok(core.pos["B"] == nil, "P1 拒绝后 B 仍不在盘上", core.pos["B"] and (core.pos["B"].r .. "," .. core.pos["B"].c))
  ok(core.row_count[2] == 1, "P1 第 2 行人数仍是 1", tostring(core.row_count[2]))
  ok(type(why) == "string" and #why > 0, "P1 拒绝时给出原因（玩家/日志看得见）", tostring(why))
  ok(why and (why:find("行", 1, true) ~= nil), "P1 原因里点明是「行」冲突", tostring(why))
end

section("P2 同列已有别人 ⇒ 正式放置被拒")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 2)
  pick(core, "C")
  local okc, why = core:hold_cell(4, 2)
  ok(okc == false, "P2 同列第 2 列拒绝放 C", tostring(okc))
  ok(core.grid[4][2] == nil, "P2 拒绝后 (4,2) 仍是空的")
  ok(type(why) == "string" and why:find("列", 1, true) ~= nil, "P2 原因里点明是「列」冲突", tostring(why))
end

section("P3 不同行不同列 ⇒ 照常放得下")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 2)
  pick(core, "B")
  local okb = core:hold_cell(4, 5)
  ok(okb == true, "P3 (4,5) 与 (2,2) 不同行列 ⇒ 允许", tostring(okb))
  ok(core.grid[4][5] == "B", "P3 B 真的落在 (4,5)")
end

section("P4 同一个人在本行内换列 ⇒ 允许（拦的是「其它人物」）")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 2)
  pick(core, "A")                      -- 长按成功后会取消选中，这里重新选
  local okm, whym = core:hold_cell(2, 4)
  ok(okm == true, "P4 A 从 (2,2) 挪到 (2,4) 允许", tostring(whym))
  ok(core.grid[2][4] == "A", "P4 新格有 A")
  ok(core.grid[2][2] == nil, "P4 旧格清空（不是复制成两个人）")
  ok(core.row_count[2] == 1, "P4 第 2 行人数仍为 1", tostring(core.row_count[2]))
end

section("P5 同列内换行 ⇒ 允许")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 3)
  pick(core, "A")
  local okm = core:hold_cell(4, 3)
  ok(okm == true, "P5 A 从 (2,3) 挪到 (4,3) 允许", tostring(okm))
  ok(core.col_count[3] == 1, "P5 第 3 列人数仍为 1", tostring(core.col_count[3]))
end

section("P6 预放置（双击路径）同样受守卫")
do
  local core = new_core()
  pick(core, "A")
  core:pre_place(2, 2)
  pick(core, "B")
  local okb, why = core:pre_place(2, 5)
  ok(okb == false, "P6 预放置到同行也被拒", tostring(okb))
  ok(core.grid[2][5] == nil, "P6 拒绝后 (2,5) 仍是空的")
  ok(type(why) == "string", "P6 预放置的拒绝也带原因", tostring(why))
end

section("P7 换人站在同一格 ⇒ 允许（目标格的旧人会离场）")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 2)
  pick(core, "B")
  local okb = core:hold_cell(2, 2)
  ok(okb == true, "P7 把 B 放到 A 所站的 (2,2) 允许", tostring(okb))
  ok(core.grid[2][2] == "B", "P7 该格现在是 B")
  ok(core.pos["A"] == nil, "P7 A 已离场（不是两人同格）", core.pos["A"] and "仍在盘上")
end

section("P8 守卫只在交互层：存档/分享码恢复不被拦")
do
  local core = new_core()
  local save = {
    version = 2, level_id = "guard_5x5",
    cells = { { r = 2, c = 2, id = "A" }, { r = 2, c = 4, id = "B" } },
  }
  local okd = core:deserialize(save)
  ok(okd == true, "P8 同行两人的存档仍能载入", tostring(okd))
  ok(core.grid[2][2] == "A" and core.grid[2][4] == "B",
    "P8 两人都恢复了（恢复语义不受交互守卫影响）")
  local has_row = false
  for _, v in ipairs(core:violations()) do if v.kind == "row" then has_row = true end end
  ok(has_row == true, "P8 违规照旧由 violations() 如实上报（不隐藏）")
end

section("P9 关卡关掉 one_per_row ⇒ 同行不拦（同列仍拦）")
do
  local core = new_core({ rules = { one_per_row = false } })
  pick(core, "A")
  core:hold_cell(2, 2)
  pick(core, "B")
  local okb = core:hold_cell(2, 4)
  ok(okb == true, "P9 关了 one_per_row ⇒ 同行允许", tostring(okb))
  pick(core, "C")
  local okc = core:hold_cell(4, 2)
  ok(okc == false, "P9 但同列仍然拦", tostring(okc))
end

-------------------------------------------------------------------------------
-- X. ✗ 与笔记互斥
-------------------------------------------------------------------------------
section("X1 先有笔记，再打 ✗ ⇒ 笔记被擦掉")
do
  local core = new_core()
  pick(core, "C")
  ok(core:tap_cell(3, 1) == true, "X1 前置：在 (3,1) 给 C 打笔记")
  ok(has_note(core, 3, 1, "C") == true, "X1 笔记真的写进去了")
  ok(core:toggle_x(3, 1) == true, "X1 (3,1) 打上 ✗")
  ok(core.x_marks[3][1] == true, "X1 ✗ 生效")
  ok(#note_ids(core, 3, 1) == 0, "X1 该格笔记被清空（「任何方式」含手动切 ✗）", dump_notes(core))
end

section("X2 先有 ✗，再打笔记 ⇒ ✗ 被擦掉")
do
  local core = new_core()
  core:toggle_x(3, 1)
  ok(core.x_marks[3][1] == true, "X2 前置：(3,1) 有 ✗")
  pick(core, "C")
  ok(core:tap_cell(3, 1) == true, "X2 在 (3,1) 打笔记")
  ok(has_note(core, 3, 1, "C") == true, "X2 笔记写进去了")
  ok(core.x_marks[3][1] == false, "X2 同一动作把 ✗ 擦掉（「标记的同时擦除」）")
end

section("X3 放置派生的自动 ✗ 也会擦掉同行同列的笔记")
do
  local core = new_core()
  pick(core, "C")
  core:tap_cell(2, 4)                 -- 笔记落在第 2 行
  pick(core, "C")
  core:tap_cell(4, 2)                 -- 另一个笔记落第 2 列
  ok(has_note(core, 2, 4, "C") and has_note(core, 4, 2, "C"), "X3 前置：两条笔记都在")
  pick(core, "A")
  core:hold_cell(2, 2)                -- 自动给第 2 行 / 第 2 列其余格标 ✗
  ok(core.x_marks[2][4] == true, "X3 同行 (2,4) 自动 ✗")
  ok(core.x_marks[4][2] == true, "X3 同列 (4,2) 自动 ✗")
  ok(#note_ids(core, 2, 4) == 0, "X3 同行那条笔记被擦掉")
  ok(#note_ids(core, 4, 2) == 0, "X3 同列那条笔记被擦掉")
end

section("X4 撤销「打 ✗」⇒ 被它擦掉的笔记回来")
do
  local core = new_core()
  pick(core, "C")
  core:tap_cell(3, 1)
  core:toggle_x(3, 1)
  ok(#note_ids(core, 3, 1) == 0, "X4 前置：✗ 已把笔记擦掉")
  ok(core:undo() == true, "X4 撤销这一步 ✗")
  ok(core.x_marks[3][1] == false, "X4 ✗ 被撤销")
  ok(has_note(core, 3, 1, "C") == true, "X4 笔记恢复（撤销不该吞掉玩家的草稿）", dump_notes(core))
end

section("X5 撤销「在 ✗ 上打笔记」⇒ ✗ 回来")
do
  local core = new_core()
  core:toggle_x(3, 1)
  pick(core, "C")
  core:tap_cell(3, 1)
  ok(core.x_marks[3][1] == false and has_note(core, 3, 1, "C"), "X5 前置：笔记取代了 ✗")
  ok(core:undo() == true, "X5 撤销这一步笔记")
  ok(core.x_marks[3][1] == true, "X5 ✗ 恢复")
  ok(#note_ids(core, 3, 1) == 0, "X5 笔记撤掉")
end

section("X6 撤销一次放置 ⇒ 自动 ✗ 与被它擦掉的笔记一起还原")
do
  local core = new_core()
  pick(core, "C")
  core:tap_cell(2, 4)
  pick(core, "A")
  core:hold_cell(2, 2)
  ok(core.x_marks[2][4] == true and #note_ids(core, 2, 4) == 0, "X6 前置：自动 ✗ 擦掉笔记")
  ok(core:undo() == true, "X6 撤销这次放置")
  ok(core.grid[2][2] == nil, "X6 A 被撤下")
  ok(core.x_marks[2][4] == false, "X6 自动 ✗ 一起还原")
  ok(has_note(core, 2, 4, "C") == true, "X6 被自动 ✗ 擦掉的笔记也还原", dump_notes(core))
end

section("X7 拿起棋子走的是同一套还原（不是第三条路）")
do
  local core = new_core()
  pick(core, "C")
  core:tap_cell(2, 4)
  pick(core, "A")
  core:pre_place(2, 2)                -- 预放置：不擦笔记、但会标自动 ✗
  ok(core.x_marks[2][4] == true, "X7 前置：预放置也标了自动 ✗")
  ok(core:tap_cell(2, 2) == true, "X7 单击把 A 拿起（place 模式对已占格 = 拿起）")
  ok(core.grid[2][2] == nil, "X7 A 真的被拿起")
  ok(core.x_marks[2][4] == false, "X7 自动 ✗ 随拿起一起还原")
  ok(has_note(core, 2, 4, "C") == true, "X7 被自动 ✗ 擦掉的笔记恢复", dump_notes(core))
end

section("X8 存档往返：脏存档（同时有 ✗ 和笔记）被清洗成互斥")
do
  local core = new_core()
  local dirty = {
    version = 2, level_id = "guard_5x5",
    cells = {
      { r = 3, c = 1, notes = { "C" }, x = true },   -- 两个都有 ⇒ ✗ 赢
      { r = 4, c = 1, notes = { "C", "D" } },        -- 只有笔记 ⇒ 原样
    },
  }
  ok(core:deserialize(dirty) == true, "X8 脏存档能载入（不报错，做清洗）")
  ok(core.x_marks[3][1] == true, "X8 该格 ✗ 保留")
  ok(#note_ids(core, 3, 1) == 0, "X8 该格笔记被丢弃（✗ 与笔记互斥）", dump_notes(core))
  ok(#note_ids(core, 4, 1) == 2, "X8 干净的笔记格原样保留", tostring(#note_ids(core, 4, 1)))
  assert_view_invariant(core, "X8")
  -- 存回去也不能再出现"又 ✗ 又笔记"
  local round = core:serialize()
  local bad = nil
  for _, e in ipairs(round.cells) do
    if e.x and e.notes and #e.notes > 0 then bad = e end
  end
  ok(bad == nil, "X8 serialize 不会写出同时含 ✗ 与笔记的格")
end

section("X9 分享码解码也守同一条不变量")
do
  local core = new_core()
  -- 5×5：X 打头 ⇒ 该格只能是 ✗，不能被笔记覆盖
  local code = "X24-"
  local okc = core:decode_state(code)
  ok(okc == true, "X9 分享码解出来了", tostring(okc))
  ok(core.x_marks[1][1] == true, "X9 第一格是 ✗")
  ok(#note_ids(core, 1, 1) == 0, "X9 第一格没有笔记")
  assert_view_invariant(core, "X9")
end

-------------------------------------------------------------------------------
-- B. 障碍物格不可打笔记
-------------------------------------------------------------------------------
section("B1 障碍物格拒绝铅笔笔记（place 模式的「选中后单击」路径）")
do
  local core = new_core()
  ok(core:is_blocked(1, 5) == true, "B1 用例床 (1,5) 是障碍物")
  pick(core, "A")
  local okn, why = core:tap_cell(1, 5)
  ok(okn == false, "B1 障碍格打笔记被拒", tostring(okn))
  ok(#note_ids(core, 1, 5) == 0, "B1 被拒之后该格仍无笔记（没偷偷写进去）", dump_notes(core))
  ok(type(why) == "string" and #why > 0, "B1 拒绝带原因", tostring(why))
end

section("B2 障碍物格拒绝铅笔笔记（MODE_NOTE 强制笔记路径）")
do
  local core = new_core()
  core:set_mode(M.MODE_NOTE)
  pick(core, "B")
  local okn, why = core:tap_cell(1, 5)
  ok(okn == false, "B2 NOTE 模式下同样被拒", tostring(okn))
  ok(#note_ids(core, 1, 5) == 0, "B2 仍无笔记")
  ok(type(why) == "string" and #why > 0, "B2 拒绝带原因", tostring(why))
end

section("B3 障碍物格仍然可以打/擦 ✗（旧行为保留）")
do
  local core = new_core()
  ok(core:toggle_x(1, 5) == true, "B3 障碍格可以打 ✗")
  ok(core.x_marks[1][5] == true, "B3 ✗ 生效")
  ok(core:toggle_x(1, 5) == true, "B3 再点一次可以取消 ✗")
  ok(core.x_marks[1][5] == false, "B3 ✗ 已取消")
end

section("B4 普通格打笔记照旧（对照组，防止一刀切）")
do
  local core = new_core()
  ok(core:is_blocked(1, 4) == false, "B4 (1,4) 不是障碍物")
  pick(core, "A")
  ok(core:tap_cell(1, 4) == true, "B4 普通格打笔记允许")
  ok(has_note(core, 1, 4, "A") == true, "B4 笔记真的写进去")
end

section("B5 脏存档把笔记塞进障碍格 ⇒ 载入时清洗掉")
do
  local core = new_core()
  local dirty = {
    version = 2, level_id = "guard_5x5",
    cells = { { r = 1, c = 5, notes = { "A", "B" } } },
  }
  ok(core:deserialize(dirty) == true, "B5 脏存档能载入")
  ok(#note_ids(core, 1, 5) == 0, "B5 障碍格的笔记被丢弃", dump_notes(core))
  assert_view_invariant(core, "B5")
end

-------------------------------------------------------------------------------
-- R. 回归：这几条老行为不许被本轮改坏
-------------------------------------------------------------------------------
section("R1 拿起棋子会还原它派生的自动 ✗（v2026-09-28 的老行为）")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 2)
  ok(core.x_marks[2][3] == true, "R1 前置：同行自动 ✗")
  core:tap_cell(2, 2)
  ok(core.x_marks[2][3] == false, "R1 拿起后自动 ✗ 被还原")
end

section("R2 正式放置后不能再给这个人打笔记（v2026-09-28 的老行为）")
do
  local core = new_core()
  pick(core, "A")
  core:hold_cell(2, 2)
  ok(core.placed and core.placed["A"] == true, "R2 placed[A] 置位")
  pick(core, "A")
  local okn, why = core:tap_cell(4, 4)
  ok(okn == false, "R2 给他打笔记被拒", tostring(okn))
  ok(type(why) == "string", "R2 拒绝带原因", tostring(why))
end

section("R3 笔记 / ✗ 不计步：历史里仍只有 place/clear 这类真落子")
do
  local core = new_core()
  pick(core, "C")
  core:tap_cell(3, 1)      -- note
  core:toggle_x(3, 4)      -- x
  local kinds = {}
  for i = 1, #core.history do kinds[#kinds + 1] = core.history[i].kind end
  table.sort(kinds)
  ok(#kinds == 2, "R3 两次草稿动作 = 两条历史", table.concat(kinds, ","))
  ok(kinds[1] == "note" and kinds[2] == "x",
    "R3 历史 kind 仍是 note / x（界面按 kind 判断计步，不许换成 place）",
    table.concat(kinds, ","))
end

section("R5 ★ 不变量：橡皮擦模式下永远没有选中的人（v282 删掉的「长按清空全盘」靠它才是死码）")
do
  local core = new_core()
  ok(core:set_mode(M.MODE_ERASE) == true, "R5 切到橡皮擦模式")
  ok(core.selected == nil, "R5 切到橡皮擦模式时 selected 被清空")
  pick(core, "A")
  ok(core.selected == "A", "R5 选了人之后 selected=A")
  ok(core.mode == M.MODE_PLACE,
    "R5 ★ 选人会把模式切回 place（正是这条让「长按橡皮擦」那段永远进不去）", tostring(core.mode))
  -- 反向：橡皮擦模式下长按格子也不许清盘（现在走的是普通放置/拒绝逻辑）
  core:set_mode(M.MODE_ERASE)
  local before = core.grid[2][2]
  local okl = core:hold_cell(2, 2)
  ok(okl == false, "R5 橡皮擦模式下长按（没有选中的人）⇒ 拒绝，不清盘", tostring(okl))
  ok(core.grid[2][2] == before, "R5 盘面没被动过（没有偷偷 clear_all）")
end

section("R6 全盘不变量：随便点一通之后也不会有格子同时有 ✗ 与笔记")
do
  local core = new_core()
  local seq = {
    { "pick", "A" }, { "tap", 2, 2 }, { "pick", "B" }, { "tap", 2, 5 },
    { "x", 3, 3 }, { "pick", "C" }, { "tap", 3, 3 }, { "pick", "D" },
    { "hold", 4, 4 }, { "tap", 1, 5 }, { "x", 1, 5 }, { "tap", 5, 5 },
  }
  for _, step in ipairs(seq) do
    if step[1] == "pick" then pick(core, step[2])
    elseif step[1] == "tap" then core:tap_cell(step[2], step[3])
    elseif step[1] == "hold" then core:hold_cell(step[2], step[3])
    elseif step[1] == "x" then core:toggle_x(step[2], step[3]) end
  end
  assert_view_invariant(core, "R4")
  -- 障碍格上没有笔记
  local blocked_note = nil
  for r = 1, core.rows do
    for c = 1, core.cols do
      if core:is_blocked(r, c) and #note_ids(core, r, c) > 0 then blocked_note = { r, c } end
    end
  end
  ok(blocked_note == nil, "R4 障碍格上没有残留笔记", blocked_note and (blocked_note[1] .. "," .. blocked_note[2]))
end

-------------------------------------------------------------------------------
print(string.format("\n结果：%d 通过 / %d 失败", passed, failed))
if failed > 0 then os.exit(1) end
