--[[----------------------------------------------------------------------------
  tests/input_logic.lua —— 输入手势状态机（纯 Lua，不依赖游戏环境）

  为什么单独有这个文件：
    模拟器的 pointer 动作只有 `down` / `up` 两种（**没有 move**），所以
    `Adapter:bind_input` 里新加的 **CursorDrag** 分支在模拟器回归里
    **永远走不到** —— 靠 tools/sim/probe_input.mjs 是验不到的。

    而这条分支恰好是移动端最要紧的一条：按住时手指一动就该放弃长按判定，
    否则"按住想微调"会在松手时落子。所以这里直接把 Controller 造出来，
    调 on_cell_down / on_cell_drag / on_cell_up，把整条手势路径钉死。

  顺带用同一套路径复验两件原本只在模拟器里验过的事：
    · 长按 = 放置（移动端主路径）
    · 长按放置后 `_suppress_click` 置位（抑制尾随的那次 CursorClick）

  跑法：lua tests/input_logic.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local lv   = require("levels.case_001")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL  " .. msg)
  end
end

local function new_controller()
  local core, errs = Core.new(lv)
  if core == nil then
    print("  FAIL  关卡建不起来：" .. tostring(errs and errs[1]))
    failed = failed + 1
    return nil
  end
  -- skip_intro：手势测试不关心开屏教程
  return UIC.new(core, { skip_intro = true })
end

local function placed_count(core)
  local n = 0
  for _, p in pairs(core.pos or {}) do if p ~= nil then n = n + 1 end end
  return n
end

-- 选一个人，然后把 (r,c) 交出去（模拟器里是点 tray.X 再点格子）
local function select_and(core, id)
  core:select_suspect(id)
  return core.selected == id
end

--------------------------------------------------------------------------------
-- 1. 长按 = 放置（**纯 Lua 复验**，与 probe_input.mjs 第 1 节同一条路径）
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    ok(select_and(c.core, "A"), "能选中角色 A")
    local n0 = placed_count(c.core)

    c.now = 0
    ok(c:on_cell_down(3, 1, 100, 100) == false, "按下时返回值是 false（还没到长按）")
    ok(c._press ~= nil, "按下后记录了 _press")

    c.now = 0.60                       -- > LONG_PRESS_SECONDS(0.45)
    ok(c:on_cell_up(3, 1, 100, 100) == true, "长按后抬起被判为放置")
    ok(placed_count(c.core) == n0 + 1, "确实放下了一个人")
    ok(c._suppress_click == true, "长按放置后置位 _suppress_click（抑制尾随 CursorClick）")
    ok(c._press == nil, "抬走后 _press 被清空")
  end
end

--------------------------------------------------------------------------------
-- 2. 按住期间移动超过容差 → **当场**取消，松手也不再放置
--    （这条就是模拟器测不到的那条）
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    ok(select_and(c.core, "A"), "能选中角色 A")
    local n0 = placed_count(c.core)

    c.now = 0
    c:on_cell_down(3, 1, 100, 100)
    c.now = 0.30                       -- 还没到长按门槛

    -- 移出 TAP_MOVE_TOLERANCE(24) 之外
    ok(c:on_cell_drag(3, 1, 100 + 30, 100) == true, "拖动超容差 → on_cell_drag 返回 true（已取消）")
    ok(c._press == nil, "取消后 _press 被清空")

    c.now = 0.80                       -- 就算按满时长，也已经取消了
    ok(c:on_cell_up(3, 1, 130, 100) == false, "取消之后抬起不再放置")
    ok(placed_count(c.core) == n0, "没有多出人")
    ok(c._suppress_click ~= true, "没放置就不会去抑制点击")
  end
end

--------------------------------------------------------------------------------
-- 3. 按住时的**轻微抖动**不该取消（手指不可能完全静止）
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    select_and(c.core, "A")
    local n0 = placed_count(c.core)

    c.now = 0
    c:on_cell_down(3, 1, 100, 100)
    c.now = 0.20
    ok(c:on_cell_drag(3, 1, 108, 96) == false, "位移 8px < 24px → 不取消")
    ok(c._press ~= nil, "_press 还在")
    c.now = 0.25
    ok(c:on_cell_drag(3, 1, 100 + 24, 100 + 24) == false, "位移正好等于容差 → 不取消（用的是 >）")

    c.now = 0.70
    ok(c:on_cell_up(3, 1, 124, 124) == true, "抖动之后长按依然生效")
    ok(placed_count(c.core) == n0 + 1, "放下了一个人")
  end
end

--------------------------------------------------------------------------------
-- 4. 拿不到坐标时**什么都不做**（宁可退回"抬起时判断"，也不要误取消）
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    select_and(c.core, "A")
    local n0 = placed_count(c.core)

    c.now = 0
    c:on_cell_down(3, 1, nil, nil)          -- 这个实现不给坐标
    c.now = 0.20
    ok(c:on_cell_drag(3, 1, 500, 500) == false, "按下坐标缺失 → drag 不取消")
    ok(c._press ~= nil, "_press 还在")
    c.now = 0.60
    ok(c:on_cell_up(3, 1, 500, 500) == true, "坐标全缺失时长按仍然生效（不看位移）")
    ok(placed_count(c.core) == n0 + 1, "放下了一个人")
  end
end

--------------------------------------------------------------------------------
-- 5. 没有按下过的拖动 / 在别处抬起 / 时长不够 —— 都不该放置
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    select_and(c.core, "A")
    local n0 = placed_count(c.core)

    c.now = 0
    ok(c:on_cell_drag(3, 1, 999, 999) == false, "没按下过 → drag 什么都不做")
    ok(c:on_cell_up(3, 1, 100, 100) == false, "没按下过 → 抬起也不放置")

    c.now = 0
    c:on_cell_down(3, 1, 100, 100)
    c.now = 0.60
    ok(c:on_cell_up(2, 2, 100, 100) == false, "在**另一个格子**抬起 → 不放置")

    c.now = 0
    c:on_cell_down(3, 1, 100, 100)
    c.now = 0.10                       -- < 0.45s
    ok(c:on_cell_up(3, 1, 100, 100) == false, "时长不够 → 不放置（交给单击逻辑）")

    ok(placed_count(c.core) == n0, "以上一个都没放下")
  end
end

--------------------------------------------------------------------------------
-- 6. 抬起位置位移过大 = 划动，不算长按（Up 坐标这条兜底路径）
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    select_and(c.core, "A")
    local n0 = placed_count(c.core)

    c.now = 0
    c:on_cell_down(3, 1, 100, 100)
    c.now = 0.80
    ok(c:on_cell_up(3, 1, 100 + 40, 100) == false, "抬起时位移 40px → 判为划动，不放置")
    ok(placed_count(c.core) == n0, "没有多出人")
  end
end

--------------------------------------------------------------------------------
-- 7. 键盘路径：方向键移动光标 + 放置（PC 加分项）
--
-- ⚠️ `event.key` 是 **`Enum.KeyEventType` 的名字**（官方**语义事件**），
--    不是物理键码 —— 见 ui_controller 里 KB_ACTIONS 的注释。
--    官方**没有** Return / Enter / Escape 事件，所以放置绑「拾取/交互」(F)、
--    "关弹窗/选关"绑奇匠按键42 (Backspace)。
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    select_and(c.core, "A")
    local n0 = placed_count(c.core)

    ok(c:on_key({ key = "KeyboardCraftspersonKey39Down" }) == true, "→（奇匠按键39）被消费")
    ok(c.kb.c == 2, "键盘光标右移一格")
    ok(c.kb_active == true, "按过方向键 → 键盘光标激活（棋盘上会高亮）")

    -- 把光标移到答案格 (3,1)：从 (1,2) 出发
    c:on_key({ key = "KeyboardCraftspersonKey37Down" })   -- ↓
    c:on_key({ key = "KeyboardCraftspersonKey37Down" })   -- ↓
    c:on_key({ key = "KeyboardCraftspersonKey38Down" })   -- ←
    ok(c.kb.r == 3 and c.kb.c == 1, "光标到 (3,1)，当前 (" .. c.kb.r .. "," .. c.kb.c .. ")")

    ok(c:on_key({ key = "KeyboardInteractKeyDown" }) == true, "F（拾取/交互）被消费")
    ok(placed_count(c.core) == n0 + 1, "F 把选中的人放到了光标格")

    -- 数字键选人（奇匠按键1 = 默认物理键 `1`）
    ok(c:on_key({ key = "KeyboardCraftspersonKey1Down" }) == true, "数字1（奇匠按键1）被消费")
    ok(c.core.selected == c.core:view().tray[1].id, "数字键选中了第 1 个角色")

    -- 未映射的键事件**不该被消费**（要让游戏自己处理）
    ok(c:on_key({ key = "KeyboardSprintKeyDown" }) == false, "未映射的键事件不消费")

    -- 边界：不能移出棋盘
    for _ = 1, 10 do c:on_key({ key = "KeyboardCraftspersonKey36Down" }) end
    ok(c.kb.r == 1, "光标上边界夹住（r=1）")
  end
end

print(string.format("input_logic: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
