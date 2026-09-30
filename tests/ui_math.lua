--[[----------------------------------------------------------------------------
  tests/ui_math.lua —— 界面坐标自洽性回归测试（不需要游戏环境）

  为什么需要它：界面坐标有**两套算法**，必须永远算出同一个结果 ——
    A) 编辑器/仿真那份：ui_controller.build_layout() 在设计空间排格子，
       再经 M.to_canvas() 换成画布空间的「中心点绝对坐标」；
    B) 运行时那份：engine_adapter_qianxing.cell_offset() 在运行时按
       「相对父级中心的偏移」把格子重新摆正（因为编辑器里填的位置不可全信）。
  两套一旦漂移，症状是"编辑器里对、一进游玩就歪"，而且很难查。
  所以这里对 5×5 和 6×6 都验一遍。

  跑法： lua tests/ui_math.lua
----------------------------------------------------------------------------]]--

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local Core     = require("murdoku_core")
local UIC      = require("ui_controller")
local Qianxing = require("engine_adapter_qianxing")

local pass, fail = 0, 0
local function ok(cond, label, detail)
  if cond then
    pass = pass + 1
    print("  [PASS] " .. label .. (detail and ("   " .. detail) or ""))
  else
    fail = fail + 1
    print("  [FAIL] " .. label .. (detail and ("   " .. detail) or ""))
  end
end

local function near(a, b, tol) return math.abs(a - b) <= (tol or 2) end

----------------------------------------------------------------------------
print("== 1. M.to_canvas：设计空间 → 画布空间 ==")
do
  -- 设计空间 1920×1080，左上原点、Y 向下；画布 1600×900，左下原点、Y 向上
  ok(UIC.CANVAS.width == 1600 and UIC.CANVAS.height == 900, "画布是 1600×900")
  ok(math.abs(UIC.SCALE - 5 / 6) < 1e-9, "缩放 = 5/6", string.format("%.6f", UIC.SCALE))

  -- 整屏：设计空间 (0,0,1920,1080) → 画布中心 (800,450)，尺寸 1600×900
  local c = UIC.to_canvas({ x = 0, y = 0, w = 1920, h = 1080 })
  ok(c.cx == 800 and c.cy == 450, "整屏矩形映射到画布中心 (800,450)",
    string.format("得到 (%d,%d)", c.cx, c.cy))
  ok(c.w == 1600 and c.h == 900, "整屏尺寸映射为 1600×900",
    string.format("得到 %d×%d", c.w, c.h))

  -- 设计空间左上角一个小方块 → 画布空间的**左上角**，即 cy 应该接近 900
  local tl = UIC.to_canvas({ x = 0, y = 0, w = 120, h = 60 })
  ok(near(tl.cx, 50) and near(tl.cy, 875), "设计空间左上角 → 画布左上角",
    string.format("(%d,%d)", tl.cx, tl.cy))

  -- 设计空间左下角 → 画布左下角，cy 应接近 25
  local bl = UIC.to_canvas({ x = 0, y = 1080 - 60, w = 120, h = 60 })
  ok(near(bl.cx, 50) and near(bl.cy, 25), "设计空间左下角 → 画布左下角",
    string.format("(%d,%d)", bl.cx, bl.cy))
end

----------------------------------------------------------------------------
-- 造一个 n×n 的假关卡（只需要 rows/cols/棋子数与受害者，用来驱动布局）
local function fake_level(n)
  local suspects, solution = {}, {}
  for i = 1, n do
    local id = string.char(64 + i)                  -- A, B, C, ...
    suspects[i] = { id = id, name = "角色" .. i }
    solution[id] = { r = i, c = i }
  end
  suspects[n].is_victim = true
  return {
    id = "fake_" .. n,
    name = "几何测试 " .. n .. "×" .. n,
    size = { rows = n, cols = n },
    rules = { one_per_row = true, one_per_col = true, place_all = true },
    suspects = suspects,
    victim = { id = suspects[n].id },
    -- 偷窃版规则要求 roles.thief 必填（第 n 个是受害者，所以取第 1 个当盗窃者）
    roles = { thief = suspects[1].id },
    solution = solution,
    clues = {},
  }
end

local function check_board(n)
  print(string.format("\n== %d×%d 棋盘：编辑器算法 vs 运行时算法 ==", n, n))

  local core, errs = Core.new(fake_level(n))
  if not core then
    ok(false, "构造 " .. n .. "×" .. n .. " 关卡", table.concat(errs or {}, " / "))
    return
  end

  local ctl = UIC.new(core, {})
  local plan = ctl:layout_plan()
  local byId = {}
  for i = 1, #plan do byId[plan[i].id] = plan[i] end

  -- 棋盘容器与格子的画布绝对中心
  local board = byId["board"]
  ok(board ~= nil, "布局里有 board")
  if not board then return end

  -- 运行时算法：用 board 的实际画布尺寸算「相对父级中心的偏移」
  local ad = Qianxing.new({
    cells = {
      probe = "cell.1.1", parent = "board",
      -- 故意不给 parent_w/h：让它退回默认值，所以显式传实际值来模拟"读到了实际尺寸"
      parent_w = board.w, parent_h = board.h,
      ruler = 37, gap = 3,
    },
  })

  local maxdiff = 0
  local worst = nil
  for r = 1, n do
    for c = 1, n do
      local cell = byId[string.format("cell.%d.%d", r, c)]
      if cell == nil then
        ok(false, string.format("布局里缺 cell.%d.%d", r, c))
        return
      end
      -- 运行时：offset 是相对父级中心的偏移 → 换算成画布绝对中心
      local ox, oy = ad:cell_offset(r, c, n)
      local absx, absy = board.cx + ox, board.cy + oy
      local dx, dy = math.abs(absx - cell.cx), math.abs(absy - cell.cy)
      if dx > maxdiff then maxdiff, worst = dx, string.format("cell.%d.%d Δx=%.1f", r, c, dx) end
      if dy > maxdiff then maxdiff, worst = dy, string.format("cell.%d.%d Δy=%.1f", r, c, dy) end
    end
  end

  ok(maxdiff <= 3, string.format("%d×%d：%d 个格子两套算法一致（最大偏差 %.1f px）",
      n, n, n * n, maxdiff), worst or "完美重合")

  -- 格子必须落在 board 内
  local c1 = byId["cell.1.1"]
  local cn = byId[string.format("cell.%d.%d", n, n)]
  local half = c1.w / 2
  ok(c1.cx - half >= board.cx - board.w / 2 - 1 and c1.cy + half <= board.cy + board.h / 2 + 1,
    string.format("%d×%d：左上角格子没跑出 board", n, n),
    string.format("格子 %d,%d 尺寸 %d；board 中心 %d,%d 尺寸 %d", c1.cx, c1.cy, c1.w, board.cx, board.cy, board.w))
  ok(cn.cx + half <= board.cx + board.w / 2 + 1 and cn.cy - half >= board.cy - board.h / 2 - 1,
    string.format("%d×%d：右下角格子没跑出 board", n, n))

  -- 格子不能互相重叠
  ok(c1.w > 0 and c1.w < 200, string.format("%d×%d：格子边长合理（%d px）", n, n, c1.w))

  -- 标尺数量
  for c = 1, n do
    if byId["ruler.c." .. c] == nil then ok(false, "缺 ruler.c." .. c) return end
  end
  for r = 1, n do
    if byId["ruler.r." .. r] == nil then ok(false, "缺 ruler.r." .. r) return end
  end
  ok(true, string.format("%d×%d：行列标尺齐全（各 %d 个）", n, n, n))
end

check_board(5)
check_board(6)
check_board(7)

----------------------------------------------------------------------------
-- 3.2 容器不重叠：头像卡必须待在 tray 里，tray 不能压住 clues
--     （2026-09-26 实测踩过两次：卡片溢出 tray 把线索盖住了。这两条断言就是为此加的。）
----------------------------------------------------------------------------
local function check_no_overlap(n)
  print(string.format("\n== %d×%d：左侧面板不重叠 ==", n, n))
  local core, errs = Core.new(fake_level(n))
  if not core then
    ok(false, "构造 " .. n .. "×" .. n .. " 关卡", table.concat(errs or {}, " / "))
    return
  end
  local ctl = UIC.new(core, {})
  local plan = ctl:layout_plan()
  local byId = {}
  for i = 1, #plan do byId[plan[i].id] = plan[i] end

  local tray, clues, legend = byId["tray"], byId["clues"], byId["legend"]
  ok(tray ~= nil and clues ~= nil and legend ~= nil, "容器齐全（tray / clues / legend）")
  if not tray then return end

  -- 每张头像卡都必须在 tray 的矩形里
  local escaped, worst = 0, nil
  for i = 1, #plan do
    local nd = plan[i]
    if nd.parent == "tray" then
      local l, r = nd.cx - nd.w / 2, nd.cx + nd.w / 2
      local b, t = nd.cy - nd.h / 2, nd.cy + nd.h / 2
      local tl, tr = tray.cx - tray.w / 2, tray.cx + tray.w / 2
      local tb, tt = tray.cy - tray.h / 2, tray.cy + tray.h / 2
      if l < tl - 1 or r > tr + 1 or b < tb - 1 or t > tt + 1 then
        escaped = escaped + 1
        worst = worst or string.format("%s 中心(%.1f,%.1f) %d×%d 超出 tray(中心 %.1f,%.1f %d×%d)",
          nd.id, nd.cx, nd.cy, nd.w, nd.h, tray.cx, tray.cy, tray.w, tray.h)
      end
    end
  end
  ok(escaped == 0, string.format("%d×%d：%d 张头像卡都在 tray 容器内", n, n, n), worst or "全部在界内")

  -- 卡片的最低边不能压到线索区的最高边
  local card_bottom = math.huge
  for i = 1, #plan do
    local nd = plan[i]
    if nd.parent == "tray" then
      card_bottom = math.min(card_bottom, nd.cy - nd.h / 2)
    end
  end
  local clues_top = clues.cy + clues.h / 2
  ok(card_bottom >= clues_top - 1,
    string.format("%d×%d：头像卡没有压住线索区", n, n),
    string.format("卡片最低 %.1f vs 线索最高 %.1f", card_bottom, clues_top))

  -- 线索 + legend 也不能互相压
  local legend_top = legend.cy + legend.h / 2
  local clues_bottom = clues.cy - clues.h / 2
  ok(clues_bottom >= legend_top - 1,
    string.format("%d×%d：线索区和图例不重叠", n, n),
    string.format("线索最低 %.1f vs 图例最高 %.1f", clues_bottom, legend_top))
end

check_no_overlap(5)
check_no_overlap(6)
check_no_overlap(7)

----------------------------------------------------------------------------
print("\n== 3. 画布边界：所有控件都在 1600×900 之内 ==")
do
  local core, cerrs = Core.new(fake_level(6))
  if not core then
    ok(false, "构造 6×6 关卡（边界检查）", table.concat(cerrs or {}, " / "))
  else
    local ctl = UIC.new(core, {})
    local plan = ctl:layout_plan()
    local outside, worst = 0, nil
    for i = 1, #plan do
      local nd = plan[i]
      -- 弹窗/教程允许覆盖整屏；只查明显越界的
      local l, r = nd.cx - nd.w / 2, nd.cx + nd.w / 2
      local b, t = nd.cy - nd.h / 2, nd.cy + nd.h / 2
      if l < -60 or r > 1660 or b < -60 or t > 960 then
        outside = outside + 1
        worst = worst or string.format("%s 中心(%d,%d) 尺寸%d×%d", nd.id, nd.cx, nd.cy, nd.w, nd.h)
      end
    end
    ok(outside == 0, "没有控件明显跑出画布", worst or ("检查了 " .. #plan .. " 个控件"))
  end
end

----------------------------------------------------------------------------
print("\n== 4. 每个已登记关卡都要放得进界面 ==")
do
  -- 为什么要有这一段：线索区能显示的行数是**硬上限**（clue_max_visible），
  -- 超出的线索根本不会生成控件 —— 玩家看不到线索就没法解题。
  -- 2026-09-26 就发生过：case_003 写了 18 条线索，而界面只放 12 行。
  local Levels = require("levels.init")
  local all = Levels.all()
  local lerrs = Levels.load_errors()
  ok(#lerrs == 0, "关卡模块都能加载",
    (#lerrs > 0) and (lerrs[1].module .. ": " .. tostring(lerrs[1].error)) or (#all .. " 关"))

  -- ★★★ 2026-09-30：**这条断言的约束变了，所以改了它**（不是"改测试让它变绿"，是约束真的变了）。
  --
  --   以前：线索区要**一屏放得下全部** `clue_max_visible` 条 —— 因为放不下的线索
  --         连控件都不会生成，玩家看不到，而线索是解题的全部依据。
  --   现在：线索区改成**可滚动窗口**（参考《派蒙的执律庭实习》左侧那个带滚轮的列表）。
  --         18 条控件**照旧全部生成**，只是分屏显示 ⇒ "放得下"不再是必要条件，
  --         真正要保证的是：**窗口 + 滚动能覆盖到每一条**。
  --   ⇒ 新断言：
  --     ① 窗口至少能放 1 行（否则滚动没有意义）
  --     ② 生成上限 `clue_max_visible` ≥ 任何关卡的线索数（保证"每一条都有控件"）
  local max_clues = UIC.LAYOUT.clue_max_visible
  local win_rows = math.floor(UIC.LAYOUT.clues.h / UIC.LAYOUT.clue_row_h)
  local declared_rows = UIC.LAYOUT.clue_rows or 0
  ok(win_rows >= 1 and declared_rows >= 1 and declared_rows <= win_rows,
    string.format("线索窗口可见行数合法（clue_rows=%d，区域能放 %d 行）", declared_rows, win_rows),
    string.format("clues.h=%d / clue_row_h=%d = %d 行（可滚动）",
      UIC.LAYOUT.clues.h, UIC.LAYOUT.clue_row_h, win_rows))
  ok(max_clues >= 1,
    string.format("线索生成上限 ≥ 1（当前 %d 条）", max_clues))

  for i = 1, #all do
    local lv = all[i]
    local nclue = #(lv.clues or {})
    local npiece = #(lv.suspects or {})
    ok(nclue <= max_clues,
      string.format("%s：%d 条线索 ≤ 界面上限 %d", tostring(lv.id), nclue, max_clues),
      (nclue > max_clues) and "超出的线索玩家看不到，关卡不可解！" or nil)
    -- 头像卡永远只占 2 行（列数自适应），所以人数上限 = 2 * 单行列数
    ok(npiece <= 16, string.format("%s：%d 个角色在头像卡布局能力内", tostring(lv.id), npiece))
  end
end

-- ── 5. 房间计算（`lua/room_map.lua`）─────────────────────────────────────────
--
-- ★ 2026-09-30：选关卡片的棋盘缩略图要按**房间色块**画，房间算法被抽成独立模块
--   （`murdoku_core` 转调它，界面层也用它 —— 只有这一处实现）。
--   这里钉住它的**基本不变量**，免得哪天改动把缩略图/游戏内房间判定弄歪。
do
  local RoomMap = require("room_map")
  -- ⚠️ `Levels` 是上面那个 `do` 块里的局部变量，这里取不到（我第一版就踩了：
  --    `attempt to index a nil value`）⇒ 自己 require 一份。
  local Levels = require("levels.init")
  local all = Levels.all()
  ok(type(RoomMap.boxes) == "function", "room_map.boxes 存在")

  for i = 1, #all do
    local lv = all[i]
    local rows = lv.size and lv.size.rows
    local cols = lv.size and lv.size.cols
    local boxes = RoomMap.boxes(lv)
    -- ① 每个格子都被划进某个房间（房间数 ≥ 1）
    ok(#boxes >= 1, string.format("%s：至少算出 1 个房间（实际 %d）", tostring(lv.id), #boxes))
    -- ② 房间框加起来**至少覆盖棋盘面积**（框会重叠，所以只查下界）
    local cover = 0
    for j = 1, #boxes do cover = cover + (boxes[j].r2 - boxes[j].r1 + 1) * (boxes[j].c2 - boxes[j].c1 + 1) end
    ok(cover >= rows * cols,
      string.format("%s：房间框覆盖 ≥ 棋盘 %d 格（实际 %d）", tostring(lv.id), rows * cols, cover))
    -- ③ 每个框都在棋盘范围内
    local inside = true
    for j = 1, #boxes do
      local b = boxes[j]
      if b.r1 < 1 or b.c1 < 1 or b.r2 > rows or b.c2 > cols then inside = false end
    end
    ok(inside, string.format("%s：所有房间框都在棋盘内", tostring(lv.id)))
    -- ④ 与核心口径**一致**（这是"只有一处实现"的证据）
    local Core = require("murdoku_core")
    local ws = Core.build_walls(lv, rows, cols)
    local _, n_core = Core.compute_rooms(rows, cols, ws)
    ok(n_core == #boxes,
      string.format("%s：核心与 room_map 算出的房间数一致（%d）", tostring(lv.id), n_core),
      (n_core ~= #boxes) and "两处实现漂移了！" or nil)
  end
end

print(string.format("\n结果：%d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
