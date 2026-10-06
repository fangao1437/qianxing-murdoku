-- [[----------------------------------------------------------------------------
--   tests/_wip/probe_level_edges.lua —— ★★ 四关的"墙/门边"到底算出了什么
--
--   ★ 起因（用户 2026-10-05 的观察 ✓）：
--     · 「第一次渲染不齐【只发生在第一关】」✗
--     · 「退出试玩重新进游戏、直接点后三关也不会不齐 —— 那时格子【也是第一次被渲染】」✓
--     ⇒ ★★ 所以"格子本次新建"【不是】原因 ✗ ⇒ **第一关自己的数据/代码里混进了什么** ✓
--
--   ★ 已知的两条硬事实：
--     ① `demo_selftest.lua`（第一关）3931 字节，其它三关 6380 / 7591 / 7513 ✗
--     ② 真机日志里两处【对不上】：
--          · 逐格自检：「本关需要的墙/门边：door.left door.up wall.down wall.left wall.right wall.up」← 6 条
--          · 边缘适配只报了 4 条：wall.up · wall.left · wall.right · door.down
--     ③ `murdoku_core.lua:121` 的 `M.build_walls` 走 `RoomMap.build_walls`（room_map.lua）✓
--        而 :125 还有一份 `build_walls_OLD`【直接读 level.walls】✗ —— 两者可能不一致 ✓
--
--   ★ 本探针要回答：
--     · 四关各自算出多少条"需要的边"✗ 与"门"✗
--     · ★ **第一关是不是唯一的异类** ✓（若是 ⇒ 元凶在第一关数据或其换算 ✓）
--     · ★ `level.walls` 的原始三元组 vs **算出来的格边** 对不对得上 ✓
--
--   跑法：`lua tests/_wip/probe_level_edges.lua`
--   ★ 纯离线 ✓ 不占模拟器 ✓ 不改任何文件 ✓
--  ----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "tests/_wip"
local root = HERE .. "/../.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/?.lua;" .. package.path

local Core = require("murdoku_core")

local LEVELS = {
  { id = "selftest_theft_5x5", mod = "levels.demo_selftest" },   -- ★ 第一关（用户报的 ✗）
  { id = "case_001",           mod = "levels.case_001" },
  { id = "case_002",           mod = "levels.case_002" },
  { id = "case_003",           mod = "levels.case_003" },
}

local function count_keys(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

-- ★ 找出 core 上真正能给出"每格墙/门"的那个接口（名字可能不叫 view ✗ ⇒ 自己探 ✓）
local function find_view_api(core)
  if type(core.view) == "function" then return "core:view(r,c)", core.view end
  if type(core.cell_view) == "function" then return "core:cell_view(r,c)", core.cell_view end
  if type(core.cell) == "function" then return "core:cell(r,c)", core.cell end
  if type(core.grid_view) == "function" then return "core:grid_view(r,c)", core.grid_view end
  return nil, nil
end

local function true_sides(t)
  local out = {}
  if type(t) == "table" then
    for _, s in ipairs({ "up", "down", "left", "right" }) do
      if t[s] == true then out[#out + 1] = s end
    end
  end
  return out
end

print("=== ① 每关的原始数据 vs 算出来的边 ===")
local rows_summary = {}
for _, L in ipairs(LEVELS) do
  local ok, lv = pcall(require, L.mod)
  if not ok then
    print(string.format("  %-22s ★ require 失败：%s", L.id, tostring(lv)))
  else
    local core, errs = Core.new(lv)
    if core == nil then
      print(string.format("  %-22s ★ Core.new 失败：%s", L.id, tostring(errs and errs[1])))
    else
      -- ★★ 必须先 reset() ✗ —— `Core.new` 之后 `view()` 返回的是空表 ✓
      --   （依据：`tests/selftest.lua` 的 `place_answer` 第一句就是 `core:reset()` ✓）
      pcall(function() core:reset() end)
      pcall(function() if core.start ~= nil then core:start() end end)
      local rows = lv.size and lv.size.rows or 0
      local cols = lv.size and lv.size.cols or 0
      local n_wall_raw = (type(lv.walls) == "table") and #lv.walls or -1
      local n_door_raw = (type(lv.doors) == "table") and #lv.doors or -1
      -- 算出每格需要哪些边
      -- ★★★★★ 2026-10-06 **改用实测确认的接口** ✗✓
      --   旧写法猜了四个"每格接口"（`core:view(r,c)` 之类 ✗）⇒ ★ 全都返回空 ✗
      --   ⇒ 真机/探针日志原话：`(2,2) 实测：walls={} doors={} room=nil` ✓
      --     ⇒ ★★ 于是"每格墙边 0.00 vs 0.00" —— **全是假的** ✓
      --   ★ 正确接口（★ 已由 `tests/_wip/probe_wall_set.lua` 实测确认 ✓）：
      --     · `core:view()` **不带参数** ✓ ⇒ 返回整视图 ✓
      --     · 每格：`vm.cells[r][c].walls = { up/down/left/right }` ✓ `.doors` 同 ✓
      --     （★ 不带参数是重点 ✗ —— 传 `(r,c)` 会静默返回空表 ✓ 不报错 ✓）
      local vm = nil
      pcall(function() vm = core:view() end)
      local api = (type(vm) == "table" and type(vm.cells) == "table") and "core:view()" or "**取不到**"
      local n_wall_true, n_door_true, n_cell_with_wall = 0, 0, 0
      local sample = nil
      if type(vm) == "table" and type(vm.cells) == "table" then
        for r = 1, rows do
          for c = 1, cols do
            local v = vm.cells[r] and vm.cells[r][c]
            if type(v) == "table" then
              local ws = true_sides(v.walls)
              local ds = true_sides(v.doors)
              n_wall_true = n_wall_true + #ws
              n_door_true = n_door_true + #ds
              if #ws > 0 then n_cell_with_wall = n_cell_with_wall + 1 end
              if r == 2 and c == 2 then sample = v end
            end
          end
        end
      end
      print(string.format("  %-22s %dx%d  原始 walls=%2d doors=%2d  ⇒ 算出 墙边=%3d 门边=%2d（有墙的格子 %d 个）  api=%s",
        L.id, rows, cols, n_wall_raw, n_door_raw, n_wall_true, n_door_true, n_cell_with_wall, tostring(api)))
      if sample ~= nil then
        local ws, ds = true_sides(sample.walls), true_sides(sample.doors)
        print(string.format("        ★ (2,2) 实测：walls={%s}  doors={%s}  room=%s",
          table.concat(ws, ","), table.concat(ds, ","), tostring(sample.room)))
      end
      rows_summary[#rows_summary + 1] = {
        id = L.id, wall = n_wall_true, door = n_door_true, cells = n_cell_with_wall,
        raw_w = n_wall_raw, raw_d = n_door_raw,
      }
    end
  end
end

print("\n=== ② 原始三元组展开（h/v, 行, 列）—— 看第一关到底特殊在哪 ===")
for _, L in ipairs(LEVELS) do
  local ok, lv = pcall(require, L.mod)
  if ok then
    local function dump(tbl, tag)
      local parts = {}
      if type(tbl) == "table" then
        for i = 1, #tbl do
          local t = tbl[i]
          if type(t) == "table" then
            parts[#parts + 1] = tostring(t[1]) .. tostring(t[2]) .. "," .. tostring(t[3])
          end
        end
      end
      print(string.format("  %-22s %-6s %s", L.id, tag, table.concat(parts, "  ")))
    end
    dump(lv.walls, "walls")
    dump(lv.doors, "doors")
  end
end

print("\n=== ③ ★ 判定：第一关是不是唯一的异类 ===")
local base = rows_summary[1]
local same = 0
for i = 2, #rows_summary do
  local s = rows_summary[i]
  -- ★ 归一化：按格子数折算"每格多少条墙边"✗（5x5 与 7x7 不能直接比总数 ✓）
  local per_cell_1 = (base.cells > 0) and (base.wall / base.cells) or 0
  local per_cell_i = (s.cells > 0) and (s.wall / s.cells) or 0
  local delta = math.abs(per_cell_1 - per_cell_i)
  print(string.format("  第一关 vs %-12s  每格墙边 %.2f vs %.2f  Δ=%.2f%s",
    s.id, per_cell_1, per_cell_i, delta, (delta > 0.30) and "   ★★ 差异明显 ✗" or "   （接近 ✓）"))
  if delta <= 0.30 then same = same + 1 end
end
print(string.format("  ⇒ 与第一关接近的关卡数：%d / %d", same, #rows_summary - 1))
print("  ★ 若【一个都不接近】⇒ 第一关的墙布局就是唯一的异类 ✓ 元凶在它或其换算 ✓")
print("  ★ 若【全都接近】⇒ 数据不是原因 ✗ ⇒ 回到渲染/下发层 ✓")

print("\n════════ 探针结束（纯离线 ✓ 未改任何文件 ✓）════════")
