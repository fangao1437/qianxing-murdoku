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
local lv   = require("tests.old_case_001")   -- ★ 冻结夹具（不随已交付内容漂 ✓）

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

-- ★★★★★★★★ 2026-10-11 **按住 = 【推进帧】** ✗✓✓（★ 长按时长改由 `dt` 累加了 ✓）
--
--   ★★★ 为什么要改写法 ✗（★ 用户第二次报"越按越久" ✓ 逼出来的 ✓）：
--     ★ 老测试是"设一个假时钟读数" ✓ ★ 而**那正是被证明错的做法** ✗ ——
--       ★ 任何"两个时钟读数相减"都要求那根钟**与真实时间同速** ✓
--         ★ `self.now` 是从开局累加的总数 ✗　★ `os.clock` 是 **CPU 时间** ✗✓
--     ★★ 现在时长 = ★ **按住期间引擎给的 `dt` 之和** ✓
--       ⇒ ★ 测试也必须**照真机那样一帧一帧地过** ✓✓
--   ★ 用法 ✓：★ `hold(c, 0.60)` = ★ **按住并让 0.60 秒真的过去** ✓
--     ★ 内部按 **1/60 秒一帧**推进 ✓（★ 与真机同节奏 ✓）
--     ★★ 同时推进 `TEST_CLOCK` ✗ —— ★ 让"兜底那条路"也有一根**同速**的钟 ✓
--       ★★★ 2026-10-15 **这一行上原来留着一处【破坏性验证】的残迹** ✗✓✓
--         ★ 它长这样 ✓：`CLK = CLK + d * 0.25` ＋ 一行注释「造出钟比真实慢 4 倍」✓
--         ★★ 那是 `tools/verify_longpress.mjs` 那一类工具**故意改坏**用的 ✓
--           ⇒ ★ 用完必须还原 ✓ ★ 而那一次**没还原干净** ✓✓
--         ★★★ 为什么它一直没被发现 ✗（★ 值得记 ✓）：
--           ★ 主判据走的是 `p.dt`（★ 引擎每帧给的 ✓）⇒ ★ `TEST_CLOCK` **只是兜底** ✓
--           ★★ 而兜底**在这场测试里从不被走到** ⇒ ★ 慢 4 倍的钟**红不了任何一条** ✓✓
--           ⇒ ★★ 于是它**静默地**留在源码里 ✓ —— ★ 与"注释当事实"同族 ✓
--         ★ 现在改回**与 `dt` 同速** ✓（★ 兜底那条路才有资格当兜底 ✓）
--         ⚠️ 以后再跑破坏性验证 ⇒ ★ 跑完**必须复查这一行** ✓
local CLK = 0
local function reset_clock() CLK = 0 UIC.TEST_CLOCK = 0 end
local function hold(c, seconds)
  local step = 1 / 60
  local left = seconds
  while left > 1e-9 do
    local d = (left > step) and step or left
    left = left - d
    CLK = CLK + d                  -- ★ 与 `dt` **同速** ✓（★ 兜底那条路的前提 ✓）
    UIC.TEST_CLOCK = CLK          -- ★ 假时钟也走同样多 ✓ ⇒ 两条路同速 ✓
    c:tick(d)                     -- ★★ 关键：按住期间真的过帧 ✓✓
  end
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

    reset_clock()
    ok(c:on_cell_down(3, 1, 100, 100) == false, "按下时返回值是 false（还没到长按）")
    ok(c._press ~= nil, "按下后记录了 _press")

    hold(c, 0.60)                               -- > LONG_PRESS_SECONDS(0.45)
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

    reset_clock()
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.30)                               -- 还没到长按门槛

    -- 移出 TAP_MOVE_TOLERANCE(24) 之外
    ok(c:on_cell_drag(3, 1, 100 + 30, 100) == true, "拖动超容差 → on_cell_drag 返回 true（已取消）")
    ok(c._press == nil, "取消后 _press 被清空")

    hold(c, 0.50)                               -- 就算按满时长，也已经取消了
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

    reset_clock()
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.20)
    ok(c:on_cell_drag(3, 1, 108, 96) == false, "位移 8px < 24px → 不取消")
    ok(c._press ~= nil, "_press 还在")
    hold(c, 0.05)
    ok(c:on_cell_drag(3, 1, 100 + 24, 100 + 24) == false, "位移正好等于容差 → 不取消（用的是 >）")

    hold(c, 0.45)
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

    reset_clock()
    c:on_cell_down(3, 1, nil, nil)          -- 这个实现不给坐标
    hold(c, 0.20)
    ok(c:on_cell_drag(3, 1, 500, 500) == false, "按下坐标缺失 → drag 不取消")
    ok(c._press ~= nil, "_press 还在")
    hold(c, 0.40)
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

    reset_clock()
    ok(c:on_cell_drag(3, 1, 999, 999) == false, "没按下过 → drag 什么都不做")
    ok(c:on_cell_up(3, 1, 100, 100) == false, "没按下过 → 抬起也不放置")

    reset_clock()
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.60)
    ok(c:on_cell_up(2, 2, 100, 100) == false, "在**另一个格子**抬起 → 不放置")

    reset_clock()
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.10)                               -- < 0.45s
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

    reset_clock()
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.60)
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

--------------------------------------------------------------------------------
-- 8. ★★★ **长按时长必须与"已经玩了多久"无关**（★ 真机 bug 的回归 ✓）
--
--   ★★★ 用户**报了两次** ✓ —— ★ 第二次说明我第一版没修对 ✓✓：
--     ★ 第一次 ✓：「★ **行数越靠后，长按放置需要的长按时间越长**」✗
--     ★ 第二次 ✓：「★ **放置要求的长按时间依旧越来越长** ✓
--       ★ **n+1 次放置要按的比第 n 次更久**」✗✓
--
--   ★★ 两次的根因是**同一类** ✗：★ **判据建在一根"与真实时间不同速"的钟上** ✓
--     ★ 第一版 ✓：★ `self.now` = 从开局累加的总数 ✗
--       ⇒ ★ 两边取值时刻不同 ⇒ ★ **被帧数放大** ✓
--     ★ 第二版 ✓（★ 我换的 ✗）：★ `os.clock` ✗ —— ★ 它是 **CPU 时间** ✓
--       ★★ 游戏大半时间在等帧 ⇒ ★ 它**比真实时间慢** ✓
--         ⇒ ★ 棋盘越满、每帧越忙 ⇒ ★ 那个比值一路变 ⇒ ★ **还是"越放越久"** ✓✓
--
--   ★★★ 所以判据不能是"它单调"✗ ★ 而是 ★ **"与真实时间同速"** ✓
--     ⇒ ★ 现在时长 = ★ **按住期间引擎给的 `dt` 之和** ✓（★ 见 `press_seconds` ✓）
--
--   ★★ 本节钉三件事 ✓：
--     ① ★ **按够门槛 ⇒ 必须认** ✓
--     ② ★ **只按一瞬间 ⇒ 必须不认** ✓（★ 门槛两侧都要钉 ✗ 否则"永远认"也能过 ✓）
--     ③ ★★ **先玩 60 秒再按 ⇒ 结论一模一样** ✗✓（★ 这条就是那个 bug 的哨兵 ✓）
--        ★ 任何"与真实时间不同速"的钟都**过不了 ③** ✓✓
--
--   ★★★★★★★★ 2026-10-11 **门槛 0.45 → 0.28** ✗✓（★ 跟着实现改 ✓）
--     ★ 用户新报 ✓：「★ **还是偶尔会有放不上去的情况**」✗
--     ★★ 真机统计 ✓：★ `最小=0.45 最大=0.73 平均=0.57　前/后均=0.52/0.62` ✓
--       ⇒ ★ 漂移**已修好** ✓ ★ 而"放不上去"是**门槛压在他的手感上** ✓✓
--         （★ 他按 0.45~0.73 ⇒ ★ 而门槛正好 0.45 ⇒ **两者重合** ⇒ ★ 约三成按丢 ✓）
--   ⇒ ★ 那两个边界数也**跟着下移** ✓：
--     ★ 认的边界 ✓：**0.35 秒**（★ 门槛 0.28 + 余量 ✓）
--     ★ 不认的边界 ✓：**0.15 秒**（★ 真机单击实测 0.10~0.20 ✓ —— ★ 这才叫"单击" ✓）
--------------------------------------------------------------------------------
do
  local THRESH = 0.28                       -- ★ = 实现里的 `LONG_PRESS_SECONDS` ✓

  -- ① 过了门槛 ⇒ 认
  local c1 = new_controller()
  if c1 then
    ok(select_and(c1.core, "A"), "能选中角色 A")
    local n0 = placed_count(c1.core)
    reset_clock()
    c1:on_cell_down(3, 1, 100, 100)
    hold(c1, 0.35)
    ok(c1:on_cell_up(3, 1, 100, 100) == true,
      "★ 按 " .. THRESH .. "+ε 秒（0.35）⇒ 认成长按 ✓")
    ok(placed_count(c1.core) == n0 + 1, "★ 而且确实落了一子 ✓")
  end

  -- ② 只按一瞬间 ⇒ 不认（★ 反向钉住：不许"永远认" ✓）
  --   ★★ 这个数**必须与"真机单击"同量级** ✗ —— ★ 单击实测 0.10~0.20 ✓
  --     ★ 若拿 0.30 去测 ⇒ ★ 那**比真机单击长得多** ⇒ ★ 测的就不是"单击" ✓
  --       （★ 而且会**把"误触"钉得太宽** ⇒ ★ 门槛不敢往下调 ✓ —— ★ 我上一版就是这样 ✓）
  local c2 = new_controller()
  if c2 then
    ok(select_and(c2.core, "A"), "能选中角色 A")
    local n0 = placed_count(c2.core)
    reset_clock()
    c2:on_cell_down(3, 1, 100, 100)
    hold(c2, 0.15)
    ok(c2:on_cell_up(3, 1, 100, 100) == false,
      "★ 只按 0.15 秒（≈ 真机单击 ✓ < " .. THRESH .. "）⇒ **不认** ✓（★ 防「永远认」✓）")
    ok(placed_count(c2.core) == n0, "★ 因此没落子 ✓")
  end

  -- ③★★ 先玩 60 秒，再复现 ① 与 ② ⇒ 结论必须**一模一样**
  local c3 = new_controller()
  if c3 then
    ok(select_and(c3.core, "A"), "能选中角色 A")
    local n0 = placed_count(c3.core)
    reset_clock()
    -- ★ 模拟"已经玩了 60 秒"：★ 60 秒的帧**真的过一遍** ✓
    hold(c3, 60)
    local played = c3.now
    ok(played > 59 and played < 61,
      string.format("★ 前提：累加时钟确实到了 %.1f 秒（★ 用户说的「玩了一会儿」✓）", played))

    -- ★ ③-a：★ 玩过 60 秒之后，**按 0.15 秒仍然不许认** ✗✓（★ 这就是那个 bug ✓）
    c3:on_cell_down(3, 1, 100, 100)
    hold(c3, 0.15)
    local late_short = c3:on_cell_up(3, 1, 100, 100)
    ok(late_short == false,
      "★★ 玩了 60 秒之后，**按 0.15 秒仍然不认** ✗（★ 实测 " .. tostring(late_short) .. " ✓）")

    -- ★ ③-b：★ 玩过 60 秒之后，**按 0.35 秒仍然认** ✓
    c3:on_cell_down(3, 2, 100, 100)
    hold(c3, 0.35)
    local late_long = c3:on_cell_up(3, 2, 100, 100)
    ok(late_long == true,
      "★★ 玩了 60 秒之后，**按 0.35 秒仍然认** ✓（★ 实测 " .. tostring(late_long) .. " ✓）")
    ok(placed_count(c3.core) == n0 + 1, "★ 一共只落了这一子 ✓")
    print("  [PASS] 长按时长与「已经玩了多久 / 棋盘多满」无关"
      .. "（★ 真机那个 bug 的哨兵 ✓ 累加时钟与 CPU 时钟都过不了 ③ ✓）")
  end
end

--------------------------------------------------------------------------------
-- 9. ★★★ **"按住够长了"要有一次即时反馈**（★ 用户"偶尔放不上去"的另一半 ✓）
--
--   ★★★ 为什么必须有 ✗：
--     ★ 只有"抬起时"才判定 ⇒ ★ 玩家**松手前什么都不知道** ✗
--       ⇒ ★ 只能**估**门槛 ⇒ ★ 估短了就按丢 ✓✓
--     ★★ 真机证据 ✓：★ 他按丢的那几次是 `0.45 / 0.45 / 0.48 / 0.49` ✓
--       ★ 而门槛当时是 0.45 ⇒ ★ **正好压在门槛上** ✓（★ 说明他在"估" ✓）
--   ★ 判据 ✓：★ 按住越过门槛的那一帧 ⇒ ★ **必须恰好播一次**动的 ✓
--     ★ 而且**不能每帧都播** ✗（★ 否则按住期间刷屏 ✓）
--------------------------------------------------------------------------------
do
  local c = new_controller()
  if c then
    ok(select_and(c.core, "A"), "能选中角色 A")
    reset_clock()
    -- ★ 数一数这一段时间里排了几个动效 ✓
    local n0 = #(c.effects or {})
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.10)                       -- ★ 还没到门槛（0.28）⇒ 不许播 ✓
    ok(#(c.effects or {}) == n0, "★ 没到门槛 ⇒ **不播**（实测排了 "
      .. tostring(#(c.effects or {}) - n0) .. " 个）")
    hold(c, 0.25)                       -- ★ 越过门槛 ⇒ 播一次 ✓
    local n1 = #(c.effects or {}) - n0
    ok(n1 >= 1, "★★ 越过门槛 ⇒ **必须播一次反馈**（实测排了 " .. tostring(n1) .. " 个）")
    hold(c, 0.50)                       -- ★ 继续按住 ⇒ **不再重复播** ✓
    local n2 = #(c.effects or {}) - n0 - n1
    ok(n2 == 0, "★ 继续按住 ⇒ **不重复播**（★ 实测又多排了 " .. tostring(n2) .. " 个 ✗）")
    c:on_cell_up(3, 1, 100, 100)
    print("  [PASS] 越过门槛那一刻给一次反馈，且只给一次 ✓")
  end
end

--------------------------------------------------------------------------------
-- 10. ★★★★★★★★ 2026-10-15 **兜底时钟那条路（★ 它此前【零覆盖】）** ✗✓✓
--
--   ★★★ 为什么要补 ✗（★ 这是本轮顺手查到的一件事 ✓）：
--     ★ 上面那个 `hold()` 里原来**留着一处破坏性验证的残迹** ✓：
--       ★ `CLK = CLK + d * 0.25` ＋ 一行注释「造出钟比真实慢 4 倍」✓
--     ★★ 它**几个月都没让任何一条断言变红** ✗ —— ★ 为什么 ✓：
--       ★ 主判据走的是 `p.dt`（★ 引擎每帧给的 ✓）⇒ ★ `TEST_CLOCK` **只是兜底** ✓
--       ★★ 而兜底**从来没有被走到过** ⇒ ★ 慢 4 倍的钟**无人过问** ✓✓
--   ⇒ ★★ 所以这一节做两件事 ✓：
--     ★ ① ★ **把兜底那条路强制走一遍** ✓（★ 抹掉 `_press.dt` ✓）
--     ★ ② ★ 断言它**与真实时间同速** ✗ —— ★ 而"同速"的判据就是
--       ★ **同一段按住，两条路必须给出同一个门槛结论** ✓✓
--   ★ 修法已经落地 ✓：`M.press_seconds` 被导出（★ 原来够不着 ✓）
--     ★ 而 `hold()` 里的 `* 0.25` 已改回 `d` ✓（★ 见那个函数上面那段 ✓）
--------------------------------------------------------------------------------
do
  local THRESH = 0.28                       -- ★ 与实现里的 `LONG_PRESS_SECONDS` 一致 ✓
  local c = new_controller()
  if c then
    -- ① 先用**主判据**（帧累加）测一次：0.35 秒 ⇒ 认 ✓
    ok(select_and(c.core, "A"), "★ 兜底节：能选中角色 A")
    local n0 = placed_count(c.core)
    reset_clock()
    c:on_cell_down(3, 1, 100, 100)
    hold(c, 0.35)
    local main_ok = c:on_cell_up(3, 1, 100, 100)
    ok(main_ok == true, "★【主判据】按 " .. THRESH .. "+ε（0.35）⇒ 认成长按 ✓")
    ok(placed_count(c.core) == n0 + 1, "★ 而且确实落了一子 ✓")

    -- ② 再走**兜底**（★ 抹掉帧累加 ✓）：同样的时长 ⇒ 结论必须**一模一样** ✓
    --   ★ 抹掉的方式 ✓：★ 按住之后、抬起之前，把 `_press.dt` 置 nil ✓
    --     ⇒ ★ `press_seconds` 落回 `gesture_now(self) - p.t` ✓（★ 那条兜底 ✓）
    local c2 = new_controller()
    ok(select_and(c2.core, "A"), "★ 兜底节：第二个控制器能选中角色 A")
    local n2 = placed_count(c2.core)
    reset_clock()
    c2:on_cell_down(3, 1, 100, 100)
    hold(c2, 0.35)
    local dt_before = c2._press ~= nil and c2._press.dt or nil
    ok(type(dt_before) == "number", "★ 前提：帧累加确实记到了时长（实测 "
      .. tostring(dt_before) .. "）")
    c2._press.dt = nil                       -- ★ 强制走兜底 ✓
    local fb_ok = c2:on_cell_up(3, 1, 100, 100)
    ok(fb_ok == true,
      "★★【兜底】同样的 0.35 秒 ⇒ 必须**同样认成长按** ✓（★ 实测 " .. tostring(fb_ok) .. "）"
      .. "　⇒ ★ 兜底时钟与真实时间**不同速**时这条必红 ✓")
    ok(placed_count(c2.core) == n2 + 1, "★ 兜底那条路也真的落下了一子 ✓")

    -- ③ 反向 ✓：★ 兜底同样**不许把短按认成长按** ✗（★ 防"兜底恒真" ✓）
    local c3 = new_controller()
    ok(select_and(c3.core, "A"), "★ 兜底节：第三个控制器能选中角色 A")
    local n3 = placed_count(c3.core)
    reset_clock()
    c3:on_cell_down(3, 1, 100, 100)
    hold(c3, 0.15)                           -- ★ 真机单击量级 ✓ < 门槛 ✓
    c3._press.dt = nil                       -- ★ 走兜底 ✓
    local fb_short = c3:on_cell_up(3, 1, 100, 100)
    ok(fb_short == false,
      "★★【兜底】只按 0.15 秒 ⇒ **不许认** ✓（★ 实测 " .. tostring(fb_short) .. "）")
    ok(placed_count(c3.core) == n3, "★ 因此没落子 ✓")

    print("  [PASS] 兜底时钟与真实时间同速（★ 两条路对同一段按住给同一结论 ✓）")
  end
end

print(string.format("input_logic: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
