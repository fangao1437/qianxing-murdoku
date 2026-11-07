--[[----------------------------------------------------------------------------
  tests/_wip/repro_select_residue.lua —— **复现用户报的选中残留**

  用户原话（2026-10-15 转述）：
    「放置 v 后选择了 d，一不小心把 v 取消了，
      点出来的标记是 v 的，但显示选择的 d，
      此时再长按放置，放的会是 v」

  第二句（怀疑同源）：
    「出现过 d 有选中高亮但没有选中行为的情况」

  本探针的目的**不是**断言，而是**把每一步的状态摊开**：
    · 核心层  `core.selected`
    · 卡片高亮 `controller.focused_clue`
    · 棋盘格  `cell(r,c)` 的 suspect / note
    · 点击闩锁 `last_click`
  每一步都同时打【显示器说的】与【行为实际用的】，
  两者的差就是用户看到的那句话。

  跑法：lua tests/_wip/repro_select_residue.lua
        lua tests/_wip/repro_select_residue.lua --quiet
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/../.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")

local QUIET = false
for _, a in ipairs(arg or {}) do if a == "--quiet" then QUIET = true end end

local out = {}
local function say(s)
  out[#out + 1] = s
  if not QUIET then print(s) end
end

-- ★ 假时钟：与真机一样"同速"（★ 不要乘系数：测试自己造的钟必须与 dt 同速）
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

-- ── 与真机同一条通路的四个手势 ───────────────────────────────────────────

-- ① 长按格子 = 正式放置（on_cell_down → 帧 → on_cell_up）
local function long_press(c, r, c2)
  reset_clock()
  c:on_cell_down(r, c2, 100, 100)
  advance(c, 0.45)
  local placed = c:on_cell_up(r, c2, 100, 100)
  -- 长按会把跟随的那次 CursorClick 抑制掉
  c:on_input({ action = "click", r = r, c = c2 })
  return placed
end

-- ② 单击格子（无抑制，走真机那条 on_input 路径）
local function tap_cell(c, r, c2)
  c._suppress_click = nil
  c:on_input({ action = "click", r = r, c = c2 })
end

-- ③ 点线索卡：真机走 `_grid_item_click`，那里做两件事 ——
--      · 先把 `focused_clue` 切到这张卡（并在棋盘上染色）
--      · 再发 `{action="suspect", id=<卡上那个人>}`（经 adapter.on_input → controller:on_input）
--    探针把这两件事按同一顺序做一遍（★ 不改判定，只复刻顺序）
local function tap_clue_card(c, pos)
  local pid = c:_person_id_for_pos(pos)
  local turning_on = (c.focused_clue ~= pos)
  if turning_on then c.focused_clue = pos else c.focused_clue = nil end
  c._grid_focus_item, c._grid_focus_idx, c._grid_focus_pos = nil, nil, nil
  if pid ~= nil then
    c:on_input({ action = "suspect", id = pid })
  end
  return pid
end

-- ── 状态快照 ────────────────────────────────────────────────────────────
local function letter_of(c, id)
  return UIC.Controller.letter_of(c.core:view(), id)
end

local function dump(c, tag)
  local vm = c.core:view()
  local sel = c.core.selected
  say(string.format(
    "  [%s] core.selected=%s（它的 letter=%s）  卡片高亮 focused_clue=%s  棋盘=%s",
    tag, tostring(sel), tostring(letter_of(c, sel)),
    tostring(c.focused_clue), c.core:encode_state()))
  -- 每个"已放置"的格子，看它**显示**的 note 是什么
  for r = 1, vm.rows do
    for cc = 1, vm.cols do
      local cd = vm.cells[r][cc]
      local n = (c.core.notes and c.core.notes[r] and c.core.notes[r][cc]) or nil
      local ids = {}
      if type(n) == "table" then for k, v in pairs(n) do if v then ids[#ids + 1] = tostring(k) end end end
      table.sort(ids)
      if cd.suspect ~= nil or #ids > 0 then
        local shown = {}
        for i = 1, #ids do shown[i] = tostring(letter_of(c, ids[i])) end
        say(string.format("       cell(%d,%d) 人=%s（letter=%s）  标记={%s} ⇒ 格子上会显示「%s」",
          r, cc, tostring(cd.suspect), tostring(letter_of(c, cd.suspect)),
          table.concat(ids, ","), table.concat(shown, " ")))
      end
    end
  end
end

-- ── 场景 ────────────────────────────────────────────────────────────────
local lv = require("levels.case_001")
local core, errs = Core.new(lv)
if core == nil then
  print("关卡建不起来：" .. tostring(errs and errs[1]))
  os.exit(2)
end
local c = UIC.new(core, { skip_intro = true })

say("== 棋子顺序 ==")
for i = 1, #core.pieces do
  say(string.format("   行%-2d → %s", i, tostring(core.pieces[i].id)))
end

-- ★ 行的键：与真机一样，用 `row.<关>.<行>` 那条线落账
UIC.Controller._row_letter = {}
for i = 1, #core.pieces do
  UIC.Controller._row_letter[i] = string.upper(tostring(core.pieces[i].id))
end
UIC.Controller._piece_core = core

say("")
say("== 第 1 步：选 V 并长按放置 ==")
c:on_input({ action = "suspect", id = "V" })
dump(c, "选 V 后")
local V_CELL = { r = 3, c = 1 }
long_press(c, V_CELL.r, V_CELL.c)
dump(c, "长按放 V 后")

say("")
say("== 第 2 步：点线索卡选 D ==")
-- 找到 D 在第几行 / 第几张卡
local d_pos = nil
for i = 1, #core.pieces do if tostring(core.pieces[i].id) == "D" then d_pos = i end end
say("   D 在行 " .. tostring(d_pos))
local pid = tap_clue_card(c, d_pos)
say("   点卡后解析出的人 = " .. tostring(pid))
dump(c, "选 D 后")

say("")
say("== 第 3 步：把 V 取消掉（单击已放置的格子 = 拿起）==")
tap_cell(c, V_CELL.r, V_CELL.c)
dump(c, "拿起 V 后")

say("")
say("== 第 4 步：此时长按放置 —— 放的会是谁？==")
local sel_before = c.core.selected
local new_cell = { r = 1, c = 1 }
long_press(c, new_cell.r, new_cell.c)
local who = c.core.grid[new_cell.r][new_cell.c]
say(string.format("   长按前 core.selected=%s ⇒ 实际放到 (%d,%d) 的是 %s",
  tostring(sel_before), new_cell.r, new_cell.c, tostring(who)))
dump(c, "长按后")

say("")
say("== 对照：第 3 步改用【再点一次同一张卡】取消选中 ==")
local core2, e2 = Core.new(lv)
local c2 = UIC.new(core2, { skip_intro = true })
UIC.Controller._row_letter = {}
for i = 1, #core2.pieces do UIC.Controller._row_letter[i] = string.upper(tostring(core2.pieces[i].id)) end
UIC.Controller._piece_core = core2
c2:on_input({ action = "suspect", id = "V" })
long_press(c2, 3, 1)
tap_clue_card(c2, d_pos)         -- 选 D
tap_clue_card(c2, d_pos)         -- 再点一次 = 取消选中 + 卡片高亮也取消
dump(c2, "取消选中 D 后")
local sb2 = c2.core.selected
long_press(c2, 2, 2)
say(string.format("   长按前 core.selected=%s ⇒ 实际放到 (2,2) 的是 %s",
  tostring(sb2), tostring(c2.core.grid[2][2])))

os.exit(0)
