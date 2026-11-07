--[[----------------------------------------------------------------------------
  tests/_wip/repro_select_residue2.lua —— 第二个症状的复现 + 场景矩阵

  用户第二句：「出现过 d 有选中高亮但没有选中行为的情况」
  ⇒ 判据 = ★ **卡片高亮说"选中了 D" ∧ `core.selected` 说"没选 D"**（或 nil）
    · "有选中高亮" = `focused_clue == <D 那一行>`
    · "没有选中行为" = `core.selected ~= "D"`
      （行为 = 长按放置时 `hold_cell` 用的是 `core.selected`）

  本探针把**所有会改 `core.selected` 的手势**都走一遍，
  每一步都同时读【高亮】与【行为】，两者不一致就标 ✗。
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/../.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")

local bad = 0
local function report(tag, sel, focused, expect_focused)
  local mismatch = (expect_focused ~= focused)
  if mismatch then bad = bad + 1 end
  print(string.format("  %s %-42s core.selected=%-5s 高亮卡片=%-5s（期望 %s）",
    mismatch and "✗" or "✓", tag, tostring(sel), tostring(focused), tostring(expect_focused)))
end

local function fresh(level)
  local core = Core.new(level)
  local c = UIC.new(core, { skip_intro = true })
  UIC.Controller._row_letter = {}
  for i = 1, #core.pieces do
    UIC.Controller._row_letter[i] = string.upper(tostring(core.pieces[i].id))
  end
  UIC.Controller._piece_core = core
  return c
end

local CLK = 0
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
local function long_press(c, r, c2)
  c:on_cell_down(r, c2, 100, 100)
  advance(c, 0.45)
  local ok = c:on_cell_up(r, c2, 100, 100)
  c:on_input({ action = "click", r = r, c = c2 })
  return ok
end
local function tap_cell(c, r, c2) c._suppress_click = nil; c:on_input({ action = "click", r = r, c = c2 }) end
local function tap_card(c, pos)
  local pid = c:_person_id_for_pos(pos)
  c.focused_clue = (c.focused_clue ~= pos) and pos or nil
  c._grid_focus_item, c._grid_focus_idx, c._grid_focus_pos = nil, nil, nil
  if pid ~= nil then c:on_input({ action = "suspect", id = pid }) end
  return pid
end
-- D 在 case_001 的第 4 行；V 在第 5 行
local D_POS, V_POS = 4, 5

print("== 场景 A：放 V → 选 D → 拿起 V（用户报的那一条）==")
do
  local c = fresh(require("levels.case_001"))
  c:on_input({ action = "suspect", id = "V" }); long_press(c, 3, 1)
  tap_card(c, D_POS)
  report("选完 D（高亮应=D 且选中应=D）", c.core.selected, c.focused_clue, D_POS)
  tap_cell(c, 3, 1)                    -- 拿起 V：拿起会把人选上（core 的设计）
  report("拿起 V 之后（选中变成 V ⇒ 高亮必须跟着走）", c.core.selected, c.focused_clue, V_POS)
end

print("")
print("== 场景 B：放 V → 选 D → 再点一次 D 卡取消选中 ==")
do
  local c = fresh(require("levels.case_001"))
  c:on_input({ action = "suspect", id = "V" }); long_press(c, 3, 1)
  tap_card(c, D_POS)
  tap_card(c, D_POS)
  report("取消选中 D 之后（选中=nil ⇒ 高亮必须=nil）", c.core.selected, c.focused_clue, nil)
end

print("")
print("== 场景 C：放 V → 选 D → 拿起 V → **再点 D 卡**（第二次点会怎样）==")
do
  local c = fresh(require("levels.case_001"))
  c:on_input({ action = "suspect", id = "V" }); long_press(c, 3, 1)
  tap_card(c, D_POS)
  tap_cell(c, 3, 1)                     -- 高亮仍停在 D（残留）
  local before = c.core.selected
  tap_card(c, D_POS)                    -- 玩家想"再选 D"
  print(string.format("     拿起 V 后 core.selected=%s；再点 D 卡 ⇒ core.selected=%s",
    tostring(before), tostring(c.core.selected)))
  report("再点 D 卡之后", c.core.selected, c.focused_clue, D_POS)
end

print("")
print("== 场景 D：放 V → 选 D → 拿起 V → 长按放置（放的会是谁）==")
do
  local c = fresh(require("levels.case_001"))
  c:on_input({ action = "suspect", id = "V" }); long_press(c, 3, 1)
  tap_card(c, D_POS)
  tap_cell(c, 3, 1)
  local sel = c.core.selected
  long_press(c, 1, 1)
  local who = c.core.grid[1][1]
  local ok = (who == c.focused_clue and false) or true
  print(string.format("     长按前 core.selected=%s　高亮卡片=%s ⇒ 落到 (1,1) 的是 %s",
    tostring(sel), tostring(c.focused_clue), tostring(who)))
  if tostring(who) ~= tostring(sel) then
    print("     ✗ 落下的不是【长按那一刻 core.selected】说的那个人")
  end
end

print("")
print(string.format("不一致次数 = %d", bad))
os.exit(0)
