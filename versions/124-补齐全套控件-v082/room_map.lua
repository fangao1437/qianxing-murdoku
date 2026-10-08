-- lua/room_map.lua —— **房间（连通区域）计算，只有这一处实现**
--
-- ★★★ 2026-09-30：为什么要单独抽一个模块。
--
--   起因：选关卡片要画**棋盘缩略图**（参考《派蒙的执律庭实习》的卡片：
--   缩略图里是"房间色块"）。而缩略图要算的是**别的关卡**的房间 ——
--   不能借用"当前正在跑的那一关"的核心对象。
--
--   那两个函数（`build_walls` / `compute_rooms`）本来长在 `murdoku_core.lua` 里，
--   只服务于"当前关卡"。如果我在界面层再写一遍连通区域算法，
--   就又变成本工程反复踩的**"同一件事两处实现 ⇒ 必然漂移"**
--   （前面吃过：`erases` 动效、运行时上色 vs 存档静态图、自动 ✗ 的三处还原、
--     缩放表、关卡清单……）。
--   ⇒ 抽到这里，**核心和界面层共用同一份**：
--       · `murdoku_core.build_walls` / `compute_rooms` 直接转调本模块（API 不变）
--       · `levels.init.ui_list` 用 `boxes` 给每关算好缩略图要的房间框
--
--   本模块**不依赖任何其它模块**（纯函数，只吃关卡数据），所以两边都能安全 require。

local M = {}

local function wall_key(kind, r, c)
  return kind .. ":" .. tostring(r) .. ":" .. tostring(c)
end
M.wall_key = wall_key

-- 墙集合。三种写法都认（与核心原来的实现完全一致）：
--   A: { {"v", r, c}, ... }
--   B: { v = { {"r","c"} | "r:c" }, h = {...} }
function M.build_walls(level, rows, cols)   -- luacheck: ignore rows cols
  local set = {}
  local walls = level and level.walls
  if type(walls) ~= "table" then return set end
  for i = 1, #walls do
    local w = walls[i]
    if type(w) == "table" and type(w[1]) == "string" and (w[1] == "v" or w[1] == "h") then
      set[wall_key(w[1], tonumber(w[2]), tonumber(w[3]))] = true
    end
  end
  for _, kind in ipairs({ "v", "h" }) do
    local list = walls[kind]
    if type(list) == "table" then
      for i = 1, #list do
        local w = list[i]
        if type(w) == "string" then
          local a, b = w:match("^(%d+):(%d+)$")
          if a then set[wall_key(kind, tonumber(a), tonumber(b))] = true end
        elseif type(w) == "table" then
          set[wall_key(kind, tonumber(w[1]), tonumber(w[2]))] = true
        end
      end
    end
  end
  return set
end

-- 洪水填充：返回 room[r][c] = 房间号，以及房间总数
function M.compute_rooms(rows, cols, wall_set)
  local room = {}
  for r = 1, rows do
    room[r] = {}
    for c = 1, cols do room[r][c] = 0 end
  end
  local index = 0
  for sr = 1, rows do
    for sc = 1, cols do
      if room[sr][sc] == 0 then
        index = index + 1
        local stack = { { sr, sc } }
        room[sr][sc] = index
        while #stack > 0 do
          local cur = table.remove(stack)
          local r, c = cur[1], cur[2]
          if c < cols and not wall_set[wall_key("v", r, c)] and room[r][c + 1] == 0 then
            room[r][c + 1] = index; stack[#stack + 1] = { r, c + 1 }
          end
          if c > 1 and not wall_set[wall_key("v", r, c - 1)] and room[r][c - 1] == 0 then
            room[r][c - 1] = index; stack[#stack + 1] = { r, c - 1 }
          end
          if r < rows and not wall_set[wall_key("h", r, c)] and room[r + 1][c] == 0 then
            room[r + 1][c] = index; stack[#stack + 1] = { r + 1, c }
          end
          if r > 1 and not wall_set[wall_key("h", r - 1, c)] and room[r - 1][c] == 0 then
            room[r - 1][c] = index; stack[#stack + 1] = { r - 1, c }
          end
        end
      end
    end
  end
  return room, index
end

-- 给界面层用：每一关的**房间外框**（缩略图画色块用）。
--
--   返回 { { r1, c1, r2, c2, cells }, ... }（按房间号排序，1 起）。
--   只给"外框"而不是逐格，是因为缩略图按**房间色块**画：
--   参考图的缩略图就是几块彩色区域，不是逐个格子。
--   ★ 好处：每张卡片只要 **每关房间数** 个控件（本项目 3~6 个），
--     而不是 rows×cols 个（最多 49 个）—— 8 张卡片也只要几十个控件。
--
--   读不到 size / walls 就返回空表（**不编数据** —— 缩略图宁可不画）。
function M.boxes(level)
  local sz = level and level.size
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  if not rows or not cols or rows < 1 or cols < 1 then return {} end
  local ws = M.build_walls(level, rows, cols)
  local room, n = M.compute_rooms(rows, cols, ws)
  local out = {}
  for id = 1, n do out[id] = nil end
  for r = 1, rows do
    for c = 1, cols do
      local id = room[r][c]
      local b = out[id]
      if b == nil then
        out[id] = { r1 = r, c1 = c, r2 = r, c2 = c, cells = 1 }
      else
        if r < b.r1 then b.r1 = r end
        if r > b.r2 then b.r2 = r end
        if c < b.c1 then b.c1 = c end
        if c > b.c2 then b.c2 = c end
        b.cells = b.cells + 1
      end
    end
  end
  -- 压实成数组（房间号从 1 连续）
  local list = {}
  for id = 1, n do if out[id] then list[#list + 1] = out[id] end end
  return list
end

return M
