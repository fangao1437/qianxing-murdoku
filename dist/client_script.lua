--[[----------------------------------------------------------------------------
  client_script.lua —— 千星奇域客户端脚本（单文件构建产物）
  由 tools/bundle_client_script.lua 生成，**不要手改**：改 lua/ 下的源文件后重新打包。
  运行环境：Lua 5.3（官方文档）；io.* / coroutine.* 不可用，os.* 只剩 time/date/clock/difftime。
----------------------------------------------------------------------------]]--

-- ==== 模块加载器（把多文件合并成一个文件后仍能互相引用）==== --
local __M = {}
local __L = {}
local function __require(name)
  local hit = __L[name]
  if hit ~= nil then return hit end
  local f = __M[name]
  if f == nil then error('[murdoku] 模块未打包: ' .. tostring(name)) end
  local v = f()
  if v == nil then v = true end
  __L[name] = v
  return v
end
pcall(function() require = __require end)   -- 若有全局 require 也一并接管

__M["room_map"] = function()
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

end

__M["murdoku_core"] = function()
--[[----------------------------------------------------------------------------
  murdoku_core.lua —— 纯 Lua 规则引擎（零引擎依赖）  v0.3.0（偷窃版规则）

  规则依据（Murdoku 官方玩法，见 docs/7.1-Lua脚本情报.md 的来源清单）：
    · 每行、每列恰好 1 人（嫌疑人与受害者都要摆上棋盘）—— 类数独占位
    · “旁边(beside)”= 上下左右四邻且必须在同一房间
    · 部分格子不可站人（家具/障碍）
    · 线索会引用家具与物体（“她站在收银台旁边”）
    · 摆满之后，与受害者单独共处一室（房间内只有他们两人）的人就是凶手，
      最后由玩家“指认”凶手结案

  设计目标
    1. 与千星奇域的控件/信号/动画 API 完全解耦：本文件不 require 任何引擎模块，
       可以直接在桌面 Lua 5.4 下跑自检。
    2. 关卡是数据、规则是插件：加一种线索 = 往 M.clues 里加一个函数。
    3. 对外只暴露视图模型 core:view()，引擎绑定层只消费它，永远不直接改内部状态。

  约定
    · r = 行(1..rows，上→下)，c = 列(1..cols，左→右)
    · grid[r][c] = 棋子 id 或 nil
    · 墙 "v",r,c 挡 (r,c)↔(r,c+1)；"h",r,c 挡 (r,c)↔(r+1,c)
    · 房间由墙洪泛划分，编号从 1 开始
----------------------------------------------------------------------------]]--

local M = {}

M.VERSION = "0.3.0"

-- 角色别名：线索里的 who / a / b 都可以写 @thief / @accomplice / @victim
M.ROLE_ALIASES = {
  ["@thief"]      = "thief",
  ["@accomplice"] = "accomplice",
  ["@victim"]     = "victim",
}

-- 并列策略：相邻区域无辜人数并列时
M.TIE_FORBID = "forbid"   -- 默认：视为非法关卡，校验器报错
M.TIE_ALLOW  = "allow"    -- 特殊关卡：允许并列（多解设计）

-- 格子状态（UI 用来决定外观）
M.CELL_EMPTY   = "empty"
M.CELL_FILLED  = "filled"
M.CELL_WRONG   = "wrong"    -- 与答案不符（提交/检查后标记）
M.CELL_HINT    = "hint"     -- 提示给出的格子
M.CELL_BLOCKED = "blocked"  -- 不可站人
M.CELL_VICTIM  = "victim"   -- 受害者所在格

-- 对局状态
M.STATUS_PLAYING  = "playing"
M.STATUS_FILLED   = "filled"    -- 摆满但还没指认
M.STATUS_SOLVED   = "solved"    -- 已破案
M.STATUS_FAILED   = "failed"    -- 指认错了

-- 操作模式
M.MODE_PLACE = "place"   -- 选棋子 → 长按格子 = 放置，轻点 = 铅笔笔记
M.MODE_NOTE  = "note"    -- 强制只写笔记
M.MODE_X     = "x"       -- X 标记：这格不可能
M.MODE_ERASE = "eraser"  -- 橡皮擦：轻点清格，长按清全盘

----------------------------------------------------------------------------
-- 内部工具
----------------------------------------------------------------------------

local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deep_copy(val) end
  return out
end
M.deep_copy = deep_copy

local function cell_key(r, c) return r .. ":" .. c end
local function wall_key(kind, r, c) return kind .. ":" .. r .. ":" .. c end

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

local function resolve_size(level)
  local rows, cols = 5, 5
  local sz = level.size
  if type(sz) == "table" then
    rows = tonumber(sz.rows or sz[1]) or rows
    cols = tonumber(sz.cols or sz[2]) or cols
  elseif type(sz) == "string" then
    local a, b = sz:match("^(%d+)%s*[xX*]%s*(%d+)$")
    if a then rows, cols = tonumber(a), tonumber(b) end
  end
  return rows, cols
end

-- 把 {r,c} / {1,2} / "1:2" / {r=,c=} 统一成 {r=,c=}
local function as_pos(v)
  if type(v) == "string" then
    local a, b = v:match("^(%d+):(%d+)$")
    if a then return { r = tonumber(a), c = tonumber(b) } end
    return nil
  end
  if type(v) == "table" then
    local r = tonumber(v.r or v[1])
    local c = tonumber(v.c or v[2])
    if r and c then return { r = r, c = c } end
  end
  return nil
end
M.as_pos = as_pos

----------------------------------------------------------------------------
-- 墙体与房间
----------------------------------------------------------------------------

-- ★★★ 2026-09-30：**实现搬到 `lua/room_map.lua`，这里只转调**。
--   原因：选关卡片的棋盘缩略图要算**别的关卡**的房间，界面层也需要同一套算法。
--   如果在界面层再写一遍，就又是"同一件事两处实现 ⇒ 必然漂移"。
--   ⇒ 抽成纯函数模块，核心与界面层共用；**这里的 API 与行为一字不变**。
local RoomMap = __require("room_map")

function M.build_walls(level, rows, cols)
  return RoomMap.build_walls(level, rows, cols)
end

function M.build_walls_OLD(level, rows, cols)
  local set = {}
  local walls = level.walls
  if type(walls) ~= "table" then return set end

  -- 写法 A：数组 { {"v", r, c}, ... }
  for i = 1, #walls do
    local w = walls[i]
    if type(w) == "table" and type(w[1]) == "string" and (w[1] == "v" or w[1] == "h") then
      set[wall_key(w[1], tonumber(w[2]), tonumber(w[3]))] = true
    end
  end
  -- 写法 B/C：{ v = {...}, h = {...} }
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

function M.compute_rooms(rows, cols, wall_set)
  return RoomMap.compute_rooms(rows, cols, wall_set)
end

function M.compute_rooms_OLD(rows, cols, wall_set)
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

----------------------------------------------------------------------------
-- 门径与区域相邻（偷窃版规则 2.2 / 2.3）
----------------------------------------------------------------------------

-- 收集门径边（写法与 walls 一致）
function M.build_doors(level, rows, cols)
  local set = {}
  local doors = level.doors
  if type(doors) ~= "table" then return set end
  for i = 1, #doors do
    local d = doors[i]
    if type(d) == "table" and (d[1] == "v" or d[1] == "h") then
      set[wall_key(d[1], tonumber(d[2]), tonumber(d[3]))] = true
    end
  end
  for _, kind in ipairs({ "v", "h" }) do
    local list = doors[kind]
    if type(list) == "table" then
      for i = 1, #list do
        local d = list[i]
        if type(d) == "string" then
          local a, b = d:match("^(%d+):(%d+)$")
          if a then set[wall_key(kind, tonumber(a), tonumber(b))] = true end
        elseif type(d) == "table" then
          set[wall_key(kind, tonumber(d[1]), tonumber(d[2]))] = true
        end
      end
    end
  end
  return set
end

-- 由门径推出区域相邻图：adj[X][Y] = true 表示 X 与 Y 之间有一条门直接连通
-- 语义：不经过第三个区域即可抵达才算相邻
function M.compute_room_adjacency(rows, cols, room, door_set)
  local adj = {}
  -- 相邻是双向关系：门两侧的区域互相可达（之前只写了一向，导致 Adj 少一半）
  local function link(a, b)
    if a == nil or b == nil or a == b then return end
    adj[a] = adj[a] or {}
    adj[b] = adj[b] or {}
    adj[a][b] = true
    adj[b][a] = true
  end
  for r = 1, rows do
    for c = 1, cols do
      if c < cols and door_set[wall_key("v", r, c)] then
        link(room[r][c], room[r][c + 1])
      end
      if r < rows and door_set[wall_key("h", r, c)] then
        link(room[r][c], room[r + 1][c])
      end
    end
  end
  return adj
end

----------------------------------------------------------------------------
-- 线索类型注册表
--
--   M.clues[type] = { params = {"who","r","c"},
--                     validate = function(ctx, clue) -> boolean,
--                     text     = function(ctx, clue) -> string }
----------------------------------------------------------------------------

M.clues = {}

local function make_context(core, roles)
  roles = roles or core.roles or {}
  local ctx = {}
  ctx.rows = core.rows
  ctx.cols = core.cols
  ctx.level = core.level
  ctx.wall_set = core.wall_set
  ctx.door_set = core.door_set
  ctx.room = core.room
  ctx.room_count = core.room_count
  ctx.roles = roles
  ctx.adjacency = core.adjacency

  -- 把 "@thief" / "@accomplice" / "@victim" 解析成具体角色 id
  function ctx.resolve(who)
    if type(who) ~= "string" then return who end
    local role = M.ROLE_ALIASES[who]
    if role then return roles[role] end
    return who
  end
  -- 某个角色 id 扮演的角色名（thief / accomplice / victim / nil）
  function ctx.role_of(id)
    for role, rid in pairs(roles) do
      if rid == id then return role end
    end
    if core.victim_id and id == core.victim_id then return "victim" end
    return nil
  end

  function ctx.pos(who) return core.pos[ctx.resolve(who)] end
  function ctx.solution_pos(who) return core.solution[ctx.resolve(who)] end
  -- 角色别名要渲染成「盗窃者 / 同伙 / 受害者」，**绝不能泄露角色真名**，
  -- 否则线索文案直接把身份送给玩家，整个推理就没了
  local ROLE_WORDS = { thief = "盗窃者", accomplice = "同伙", victim = "受害者" }
  function ctx.name(who)
    if type(who) == "string" then
      local role = M.ROLE_ALIASES[who]
      if role then return ROLE_WORDS[role] or role end
    end
    local s = core.piece_by_id[who]
    return (s and s.name) or tostring(who)
  end
  function ctx.room_of(r, c)
    local row = core.room[r]
    return row and row[c]
  end
  function ctx.is_blocked(r, c)
    return core.blocked[cell_key(r, c)] == true
  end
  function ctx.is_corner(r, c)
    return (r == 1 or r == ctx.rows) and (c == 1 or c == ctx.cols)
  end
  -- murdoku 语义的 corner：房间的两面墙相交处（一横一竖）
  function ctx.is_room_corner(r, c)
    local up    = (r == 1) or core.wall_set[wall_key("h", r - 1, c)]
    local down  = (r == ctx.rows) or core.wall_set[wall_key("h", r, c)]
    local left  = (c == 1) or core.wall_set[wall_key("v", r, c - 1)]
    local right = (c == ctx.cols) or core.wall_set[wall_key("v", r, c)]
    return (up or down) and (left or right)
  end
  -- 沿外框的格
  function ctx.is_border(r, c)
    return r == 1 or r == ctx.rows or c == 1 or c == ctx.cols
  end
  -- 沿墙的格（任一方向是墙，含外框）
  function ctx.is_wall_edge(r, c)
    if r == 1 or r == ctx.rows or c == 1 or c == ctx.cols then return true end
    return core.wall_set[wall_key("h", r - 1, c)] or core.wall_set[wall_key("h", r, c)]
        or core.wall_set[wall_key("v", r, c - 1)] or core.wall_set[wall_key("v", r, c)]
        or false
  end
  function ctx.gender_of(who)
    local p = core.piece_by_id[ctx.resolve(who)]
    return p and p.gender or nil
  end

  -- ===== 门径 / 区域相邻 =====
  function ctx.is_door(kind, r, c)
    return core.door_set[wall_key(kind, r, c)] == true
  end
  -- “门窗正对的两格”：a、b 正交相邻，且这条边上有门
  function ctx.is_front_of(a, b)
    if not a or not b then return false end
    if a.r == b.r and math.abs(a.c - b.c) == 1 then
      return core.door_set[wall_key("v", a.r, math.min(a.c, b.c))] == true
    end
    if a.c == b.c and math.abs(a.r - b.r) == 1 then
      return core.door_set[wall_key("h", math.min(a.r, b.r), a.c)] == true
    end
    return false
  end
  function ctx.adjacent_rooms(room_id)
    local out = {}
    for other in pairs(core.adjacency[room_id] or {}) do out[#out + 1] = other end
    table.sort(out)
    return out
  end
  function ctx.rooms_adjacent(x, y)
    return (core.adjacency[x] or {})[y] == true
  end
  function ctx.is_water(r, c)
    for i = 1, #core.water do
      if core.water[i].r == r and core.water[i].c == c then return true end
    end
    return false
  end
  -- 房间内是否有人（受害者也算人）
  function ctx.room_is_empty(room_id)
    return ctx.count_in_room(room_id) == 0
  end
  -- 站在某家具上的人数
  function ctx.count_on_object(name)
    local n = 0
    local cells = ctx.object_cells(name)
    for _, p in pairs(core.pos) do
      for i = 1, #cells do
        if p.r == cells[i].r and p.c == cells[i].c then n = n + 1 break end
      end
    end
    return n
  end
  -- 在某家具旁边的人数
  function ctx.count_beside_object(name)
    local n = 0
    local cells = ctx.object_cells(name)
    for _, p in pairs(core.pos) do
      for i = 1, #cells do
        if ctx.is_beside(p, cells[i]) then n = n + 1 break end
      end
    end
    return n
  end
  function ctx.is_edge(r, c)
    return r == 1 or r == ctx.rows or c == 1 or c == ctx.cols
  end
  -- 四邻（不管房间）
  function ctx.is_neighbor(a, b)
    if not a or not b then return false end
    return math.abs(a.r - b.r) + math.abs(a.c - b.c) == 1
  end
  -- Murdoku 语义的“旁边”：四邻且同一房间
  function ctx.is_beside(a, b)
    if not a or not b then return false end
    if not ctx.is_neighbor(a, b) then return false end
    return ctx.room_of(a.r, a.c) == ctx.room_of(b.r, b.c)
  end
  function ctx.is_left_of(a, b)
    if not a or not b then return false end
    return a.r == b.r and a.c < b.c
  end
  function ctx.is_above(a, b)
    if not a or not b then return false end
    return a.c == b.c and a.r < b.r
  end
  function ctx.same_room(a, b)
    if not a or not b then return false end
    return ctx.room_of(a.r, a.c) == ctx.room_of(b.r, b.c)
  end
  function ctx.count_in_room(room_id)
    local n = 0
    for _, p in pairs(core.pos) do
      if p and ctx.room_of(p.r, p.c) == room_id then n = n + 1 end
    end
    return n
  end
  function ctx.room_size(room_id)
    local n = 0
    for r = 1, ctx.rows do
      for c = 1, ctx.cols do
        if ctx.room_of(r, c) == room_id then n = n + 1 end
      end
    end
    return n
  end
  function ctx.occupied(r, c)
    local row = core.grid[r]
    return (row and row[c] ~= nil) or false
  end
  function ctx.count_in_row(r) return core.row_count[r] or 0 end
  function ctx.count_in_col(c) return core.col_count[c] or 0 end

  -- 物体（家具）：level.objects[name] = {cells={{r,c},...}} 或 {r=,c=} 或 坐标数组
  function ctx.object_cells(name)
    return core.objects[name] or {}
  end
  function ctx.object_at(r, c)
    for name, cells in pairs(core.objects) do
      for i = 1, #cells do
        if cells[i].r == r and cells[i].c == c then return name end
      end
    end
    return nil
  end
  -- 受害者位置：既支持“受害者也是一枚棋子”，也支持固定格
  function ctx.victim_pos()
    local v = core.level.victim
    if type(v) == "table" and v.id then return core.pos[v.id] end
    return core.victim_fixed
  end
  function ctx.victim_id()
    local v = core.level.victim
    if type(v) == "table" and v.id then return v.id end
    return nil
  end
  return ctx
end

local function unregistered_text(ctx, clue)
  return "（未注册的线索类型：" .. tostring(clue.type) .. "）"
end

local function reg(type_name, def)
  def.type = type_name
  def.text = def.text or unregistered_text
  M.clues[type_name] = def
  return def
end

-- ============ 位置类 ============

reg("at", {
  params = { "who", "r", "c" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and p.r == cl.r and p.c == cl.c
  end,
  text = function(ctx, cl) return string.format("%s 在 第%d行第%d列", ctx.name(cl.who), cl.r, cl.c) end,
})

reg("not_at", {
  params = { "who", "r", "c" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and not (p.r == cl.r and p.c == cl.c)
  end,
  text = function(ctx, cl) return string.format("%s 不在 第%d行第%d列", ctx.name(cl.who), cl.r, cl.c) end,
})

reg("in_row", {
  params = { "who", "r" },
  validate = function(ctx, cl) local p = ctx.pos(cl.who); return p ~= nil and p.r == cl.r end,
  text = function(ctx, cl) return string.format("%s 在第%d行", ctx.name(cl.who), cl.r) end,
})

reg("in_col", {
  params = { "who", "c" },
  validate = function(ctx, cl) local p = ctx.pos(cl.who); return p ~= nil and p.c == cl.c end,
  text = function(ctx, cl) return string.format("%s 在第%d列", ctx.name(cl.who), cl.c) end,
})

reg("corner", {
  params = { "who" },
  validate = function(ctx, cl) local p = ctx.pos(cl.who); return p ~= nil and ctx.is_corner(p.r, p.c) end,
  text = function(ctx, cl) return string.format("%s 在角落", ctx.name(cl.who)) end,
})

reg("edge", {
  params = { "who" },
  validate = function(ctx, cl) local p = ctx.pos(cl.who); return p ~= nil and ctx.is_edge(p.r, p.c) end,
  text = function(ctx, cl) return string.format("%s 贴着边", ctx.name(cl.who)) end,
})

reg("inner", {
  params = { "who" },
  validate = function(ctx, cl) local p = ctx.pos(cl.who); return p ~= nil and not ctx.is_edge(p.r, p.c) end,
  text = function(ctx, cl) return string.format("%s 在内部（不贴边）", ctx.name(cl.who)) end,
})

reg("in_room", {
  params = { "who", "room" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and ctx.room_of(p.r, p.c) == cl.room
  end,
  text = function(ctx, cl) return string.format("%s 在第%d号房间", ctx.name(cl.who), cl.room) end,
})

reg("not_in_room", {
  params = { "who", "room" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and ctx.room_of(p.r, p.c) ~= cl.room
  end,
  text = function(ctx, cl) return string.format("%s 不在第%d号房间", ctx.name(cl.who), cl.room) end,
})

-- ============ 关系类 ============

reg("beside", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_beside(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 就在 %s 旁边", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("not_beside", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    return not ctx.is_beside(a, b)
  end,
  text = function(ctx, cl) return string.format("%s 不在 %s 旁边", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("same_room", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.same_room(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 与 %s 同处一室", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("different_room", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    return not ctx.same_room(a, b)
  end,
  text = function(ctx, cl) return string.format("%s 与 %s 不在同一房间", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("left_of", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_left_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 左边（同一行）", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("right_of", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_left_of(ctx.pos(cl.b), ctx.pos(cl.a)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 右边（同一行）", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("above", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_above(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 北边（同一列）", ctx.name(cl.a), ctx.name(cl.b)) end,
})

reg("below", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 南边（同一列）", ctx.name(cl.a), ctx.name(cl.b)) end,
})

-- 精确相对位移：dr 为负=北，正=南；dc 为负=西，正=东
reg("offset", {
  params = { "who", "other", "dr", "dc" },
  validate = function(ctx, cl)
    local p, o = ctx.pos(cl.who), ctx.pos(cl.other)
    if not p or not o then return false end
    return (p.r - o.r) == cl.dr and (p.c - o.c) == cl.dc
  end,
  text = function(ctx, cl)
    local dir = {}
    if cl.dr == -1 then dir[#dir + 1] = "北 1 格" elseif cl.dr == 1 then dir[#dir + 1] = "南 1 格"
    elseif cl.dr and cl.dr ~= 0 then dir[#dir + 1] = string.format("南北 %d 格", cl.dr) end
    if cl.dc == -1 then dir[#dir + 1] = "西 1 格" elseif cl.dc == 1 then dir[#dir + 1] = "东 1 格"
    elseif cl.dc and cl.dc ~= 0 then dir[#dir + 1] = string.format("东西 %d 格", cl.dc) end
    if #dir == 0 then dir[#dir + 1] = "同一格" end
    return string.format("%s 在 %s 的 %s", ctx.name(cl.who), ctx.name(cl.other), table.concat(dir, "、"))
  end,
})

reg("distance", {
  params = { "a", "b", "d" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    return math.abs(a.r - b.r) + math.abs(a.c - b.c) == cl.d
  end,
  text = function(ctx, cl)
    return string.format("%s 与 %s 相隔 %d 步（曼哈顿距离）", ctx.name(cl.a), ctx.name(cl.b), cl.d)
  end,
})

reg("between", {
  params = { "who", "a", "b" },
  validate = function(ctx, cl)
    local p, a, b = ctx.pos(cl.who), ctx.pos(cl.a), ctx.pos(cl.b)
    if not p or not a or not b then return false end
    if a.r == b.r and p.r == a.r then
      return (p.c > math.min(a.c, b.c)) and (p.c < math.max(a.c, b.c))
    end
    if a.c == b.c and p.c == a.c then
      return (p.r > math.min(a.r, b.r)) and (p.r < math.max(a.r, b.r))
    end
    return false
  end,
  text = function(ctx, cl)
    return string.format("%s 夹在 %s 和 %s 中间", ctx.name(cl.who), ctx.name(cl.a), ctx.name(cl.b))
  end,
})

-- ============ 房间/独处类 ============

reg("alone_in_room", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    return ctx.count_in_room(ctx.room_of(p.r, p.c)) == 1
  end,
  text = function(ctx, cl) return string.format("%s 独自待在一个房间", ctx.name(cl.who)) end,
})

-- “A 与 B 单独共处一室”：两人同房间，且该房间只有这两人
reg("alone_with", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    if not ctx.same_room(a, b) then return false end
    return ctx.count_in_room(ctx.room_of(a.r, a.c)) == 2
  end,
  text = function(ctx, cl)
    return string.format("%s 与 %s 单独共处一室", ctx.name(cl.a), ctx.name(cl.b))
  end,
})

reg("alone_with_victim", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    local v = ctx.victim_pos()
    if not p or not v then return false end
    if not ctx.same_room(p, v) then return false end
    return ctx.count_in_room(ctx.room_of(v.r, v.c)) == 2
  end,
  text = function(ctx, cl)
    return string.format("%s 与受害者单独共处一室", ctx.name(cl.who))
  end,
})

reg("room_has", {
  params = { "room", "n" },
  validate = function(ctx, cl) return ctx.count_in_room(cl.room) == cl.n end,
  text = function(ctx, cl) return string.format("第%d号房间内恰好有 %d 人", cl.room, cl.n) end,
})

reg("room_size_hint", {
  params = { "room", "n" },
  validate = function(ctx, cl) return ctx.room_size(cl.room) == cl.n end,
  text = function(ctx, cl) return string.format("第%d号房间有 %d 格", cl.room, cl.n) end,
})

-- ============ 格子类 ============

reg("cell_empty", {
  params = { "r", "c" },
  validate = function(ctx, cl) return not ctx.occupied(cl.r, cl.c) end,
  text = function(ctx, cl) return string.format("第%d行第%d列 没有人", cl.r, cl.c) end,
})

reg("only_one_in_row", {
  params = { "r" },
  validate = function(ctx, cl) return ctx.count_in_row(cl.r) == 1 end,
  text = function(ctx, cl) return string.format("第%d行只有 1 人", cl.r) end,
})

-- ============ 家具/物体类（Murdoku 的视觉层） ============

-- who 在名为 object 的家具旁边（四邻同房间）
reg("beside_object", {
  params = { "who", "object" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local cells = ctx.object_cells(cl.object)
    for i = 1, #cells do
      if ctx.is_beside(p, cells[i]) then return true end
    end
    return false
  end,
  text = function(ctx, cl) return string.format("%s 在 %s 旁边", ctx.name(cl.who), cl.object) end,
})

reg("not_beside_object", {
  params = { "who", "object" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local cells = ctx.object_cells(cl.object)
    for i = 1, #cells do
      if ctx.is_beside(p, cells[i]) then return false end
    end
    return true
  end,
  text = function(ctx, cl) return string.format("%s 不在 %s 旁边", ctx.name(cl.who), cl.object) end,
})

reg("on_object", {
  params = { "who", "object" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local cells = ctx.object_cells(cl.object)
    for i = 1, #cells do
      if cells[i].r == p.r and cells[i].c == p.c then return true end
    end
    return false
  end,
  text = function(ctx, cl) return string.format("%s 站在 %s 上", ctx.name(cl.who), cl.object) end,
})

reg("same_room_as_object", {
  params = { "who", "object" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local cells = ctx.object_cells(cl.object)
    for i = 1, #cells do
      if ctx.same_room(p, cells[i]) then return true end
    end
    return false
  end,
  text = function(ctx, cl) return string.format("%s 与 %s 在同一房间", ctx.name(cl.who), cl.object) end,
})

-- ============ 案件类 ============

reg("is_murderer", {
  params = { "who" },
  validate = function(ctx, cl) return ctx.level.murderer ~= nil and cl.who == ctx.level.murderer end,
  text = function(ctx, cl) return string.format("%s 是凶手", ctx.name(cl.who)) end,
})

reg("with_victim", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    local v = ctx.victim_pos()
    if not p or not v then return false end
    return p.r == v.r and p.c == v.c
  end,
  text = function(ctx, cl) return string.format("%s 就在受害者所在格", ctx.name(cl.who)) end,
})

----------------------------------------------------------------------------
-- 线索类型：murdoku 实证的原子类型补充
--   （类型名沿用英文，方便和官方关键词表对照）
----------------------------------------------------------------------------

-- “was with X”：同处一室
reg("with", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.same_room(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 与 %s 在一起", ctx.name(cl.a), ctx.name(cl.b)) end,
})

-- “was alone with X”：同处一室且只有他们两人
reg("with_only", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    if not ctx.same_room(a, b) then return false end
    return ctx.count_in_room(ctx.room_of(a.r, a.c)) == 2
  end,
  text = function(ctx, cl) return string.format("%s 与 %s 单独待在一起", ctx.name(cl.a), ctx.name(cl.b)) end,
})

-- “was alone”：所在区域内没有别人（含受害者）
reg("alone", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    return ctx.count_in_room(ctx.room_of(p.r, p.c)) == 1
  end,
  text = function(ctx, cl) return string.format("%s 独自一人", ctx.name(cl.who)) end,
})

-- “was the only person beside X”
reg("only_beside", {
  params = { "who", "object" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local cells = ctx.object_cells(cl.object)
    local mine = false
    for i = 1, #cells do
      if ctx.is_beside(p, cells[i]) then mine = true break end
    end
    if not mine then return false end
    return ctx.count_beside_object(cl.object) == 1
  end,
  text = function(ctx, cl) return string.format("只有 %s 在 %s 旁边", ctx.name(cl.who), cl.object) end,
})

-- “was the only person on a <object>”
reg("only_on_object", {
  params = { "who", "object" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local cells = ctx.object_cells(cl.object)
    local mine = false
    for i = 1, #cells do
      if cells[i].r == p.r and cells[i].c == p.c then mine = true break end
    end
    if not mine then return false end
    return ctx.count_on_object(cl.object) == 1
  end,
  text = function(ctx, cl) return string.format("只有 %s 站在 %s 上", ctx.name(cl.who), cl.object) end,
})

-- 房间角落 / 非角落 / 沿外框 / 沿墙
reg("corner_room", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and ctx.is_room_corner(p.r, p.c)
  end,
  text = function(ctx, cl) return string.format("%s 在房间的角落里", ctx.name(cl.who)) end,
})

reg("not_corner", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and not ctx.is_room_corner(p.r, p.c)
  end,
  text = function(ctx, cl) return string.format("%s 不在房间的角落", ctx.name(cl.who)) end,
})

reg("border", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and ctx.is_border(p.r, p.c)
  end,
  text = function(ctx, cl) return string.format("%s 贴着场景外框", ctx.name(cl.who)) end,
})

reg("wall_edge", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    return p ~= nil and ctx.is_wall_edge(p.r, p.c)
  end,
  text = function(ctx, cl) return string.format("%s 贴着墙", ctx.name(cl.who)) end,
})

-- 绝对行列：“in the <n>th row from the top / from the bottom”
reg("abs_row_from", {
  params = { "who", "n" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    if cl.from == "bottom" then return p.r == (ctx.rows - cl.n + 1) end
    if cl.from == "middle" then return p.r == math.floor((ctx.rows + 1) / 2) end
    return p.r == cl.n
  end,
  text = function(ctx, cl)
    if cl.from == "bottom" then
      return string.format("%s 在倒数第 %d 行", ctx.name(cl.who), cl.n)
    elseif cl.from == "middle" then
      return string.format("%s 在正中间那一行", ctx.name(cl.who))
    end
    return string.format("%s 在从上数第 %d 行", ctx.name(cl.who), cl.n)
  end,
})

reg("abs_col_from", {
  params = { "who", "n" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    if cl.from == "right" then return p.c == (ctx.cols - cl.n + 1) end
    if cl.from == "middle" then return p.c == math.floor((ctx.cols + 1) / 2) end
    return p.c == cl.n
  end,
  text = function(ctx, cl)
    if cl.from == "right" then
      return string.format("%s 在倒数第 %d 列", ctx.name(cl.who), cl.n)
    elseif cl.from == "middle" then
      return string.format("%s 在正中间那一列", ctx.name(cl.who))
    end
    return string.format("%s 在从左数第 %d 列", ctx.name(cl.who), cl.n)
  end,
})

-- 精确位移：“exactly n rows north/south of X”
reg("row_offset", {
  params = { "who", "other", "d" },
  validate = function(ctx, cl)
    local p, o = ctx.pos(cl.who), ctx.pos(cl.other)
    if not p or not o then return false end
    return (p.r - o.r) == cl.d
  end,
  text = function(ctx, cl)
    local dir = cl.d < 0 and "北" or "南"
    return string.format("%s 正好在 %s%s边 %d 行", ctx.name(cl.who), ctx.name(cl.other), dir, math.abs(cl.d))
  end,
})

reg("col_offset", {
  params = { "who", "other", "d" },
  validate = function(ctx, cl)
    local p, o = ctx.pos(cl.who), ctx.pos(cl.other)
    if not p or not o then return false end
    return (p.c - o.c) == cl.d
  end,
  text = function(ctx, cl)
    local dir = cl.d < 0 and "西" or "东"
    return string.format("%s 正好在 %s%s边 %d 列", ctx.name(cl.who), ctx.name(cl.other), dir, math.abs(cl.d))
  end,
})

-- 罗盘方位（45°，不共行也不共列）：dir = "ne" | "nw" | "se" | "sw"
reg("compass", {
  params = { "who", "other", "dir" },
  validate = function(ctx, cl)
    local p, o = ctx.pos(cl.who), ctx.pos(cl.other)
    if not p or not o then return false end
    local dr, dc = p.r - o.r, p.c - o.c
    if dr == 0 or dc == 0 then return false end
    local north, west = dr < 0, dc < 0
    local d = cl.dir
    if d == "ne" then return north and not west end
    if d == "nw" then return north and west end
    if d == "se" then return (not north) and (not west) end
    if d == "sw" then return (not north) and west end
    return false
  end,
  text = function(ctx, cl)
    local map = { ne = "东北", nw = "西北", se = "东南", sw = "西南" }
    return string.format("%s 在 %s 的%s方向（斜对角）", ctx.name(cl.who), ctx.name(cl.other), map[cl.dir] or cl.dir)
  end,
})

-- 房间里没有异性（需要 suspects[i].gender）
reg("gender_in_room", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    local me = ctx.gender_of(cl.who)
    if not me then return false end
    local room_id = ctx.room_of(p.r, p.c)
    for id, q in pairs(ctx.pos) do
      if id ~= cl.who and q and ctx.room_of(q.r, q.c) == room_id then
        local g = ctx.gender_of(id)
        if g and g ~= me then return false end
      end
    end
    return true
  end,
  text = function(ctx, cl) return string.format("%s 所在的房间里没有异性", ctx.name(cl.who)) end,
})

-- ============ 全局线索（官方 clue_1..clue_10 那一组） ============

reg("no_empty_room", {
  params = {},
  validate = function(ctx)
    for room_id = 1, ctx.room_count do
      if ctx.room_is_empty(room_id) then return false end
    end
    return true
  end,
  text = function() return "没有任何房间是空的" end,
})

reg("one_empty_room", {
  params = {},
  validate = function(ctx)
    local n = 0
    for room_id = 1, ctx.room_count do
      if ctx.room_is_empty(room_id) then n = n + 1 end
    end
    return n == 1
  end,
  text = function() return "恰好有一个房间是空的" end,
})

reg("two_empty_rooms", {
  params = {},
  validate = function(ctx)
    local n = 0
    for room_id = 1, ctx.room_count do
      if ctx.room_is_empty(room_id) then n = n + 1 end
    end
    return n == 2
  end,
  text = function() return "恰好有两个房间是空的" end,
})

reg("one_on_object", {
  params = { "object" },
  validate = function(ctx, cl) return ctx.count_on_object(cl.object) == 1 end,
  text = function(ctx, cl) return string.format("恰好有 1 个人在 %s 上", cl.object) end,
})

reg("n_on_object", {
  params = { "object", "n" },
  validate = function(ctx, cl) return ctx.count_on_object(cl.object) == cl.n end,
  text = function(ctx, cl) return string.format("恰好有 %d 个人在 %s 上", cl.n, cl.object) end,
})

reg("nobody_in_water", {
  params = {},
  validate = function(ctx)
    for _, p in pairs(ctx.pos) do
      if ctx.is_water(p.r, p.c) then return false end
    end
    return true
  end,
  text = function() return "没有人在水里" end,
})

----------------------------------------------------------------------------
-- 线索类型：偷窃版新增（门径 / 身份）
----------------------------------------------------------------------------

-- 门窗正对的两格
reg("in_front_of", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_front_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl)
    return string.format("%s 与 %s 站在同一扇门的两侧", ctx.name(cl.a), ctx.name(cl.b))
  end,
})

-- 身份线索：who（不）是某个角色。role ∈ thief / accomplice / victim
reg("is_role", {
  params = { "who", "role" },
  validate = function(ctx, cl)
    local id = ctx.resolve(cl.who)
    return id ~= nil and ctx.roles[cl.role] == id
  end,
  text = function(ctx, cl)
    local names = { thief = "盗窃者", accomplice = "同伙", victim = "受害者" }
    return string.format("%s 就是%s", ctx.name(cl.who), names[cl.role] or tostring(cl.role))
  end,
})

reg("not_role", {
  params = { "who", "role" },
  validate = function(ctx, cl)
    local id = ctx.resolve(cl.who)
    return id ~= nil and ctx.roles[cl.role] ~= id
  end,
  text = function(ctx, cl)
    local names = { thief = "盗窃者", accomplice = "同伙", victim = "受害者" }
    return string.format("%s 不是%s", ctx.name(cl.who), names[cl.role] or tostring(cl.role))
  end,
})

----------------------------------------------------------------------------
-- 关卡校验
----------------------------------------------------------------------------

function M.validate_level(level)
  local errors = {}
  local function err(fmt, ...) errors[#errors + 1] = string.format(fmt, ...) end

  if type(level) ~= "table" then return false, { "关卡不是一个 table" } end

  local rows, cols = resolve_size(level)
  if rows < 2 or cols < 2 then err("棋盘尺寸过小：%dx%d", rows, cols) end

  -- 棋子（嫌疑人与受害者都在这里）
  local pieces = level.suspects or level.pieces
  if type(pieces) ~= "table" or #pieces == 0 then
    err("缺少 suspects 列表")
    pieces = pieces or {}
  end
  local ids = {}
  for i = 1, #pieces do
    local s = pieces[i]
    if type(s) ~= "table" or s.id == nil then
      err("第 %d 枚棋子缺少 id", i)
    elseif ids[s.id] then
      err("棋子 id 重复：%s", tostring(s.id))
    else
      ids[s.id] = true
    end
  end

  -- 受害者
  local v = level.victim
  if v ~= nil then
    if type(v) == "table" and v.id then
      if not ids[v.id] then err("victim.id = %s 不在 suspects 列表里", tostring(v.id)) end
    elseif as_pos(v) == nil then
      err("victim 格式不对（应为 {id=...} 或 {r=,c=}）")
    end
  end

  -- 凶手
  if level.murderer ~= nil and not ids[level.murderer] then
    err("murderer = %s 不在 suspects 列表里", tostring(level.murderer))
  end

  -- 不可站人的格子
  local blocked = level.blocked or {}
  for i = 1, #blocked do
    if as_pos(blocked[i]) == nil then err("blocked[%d] 坐标格式不对", i) end
  end

  -- 家具
  local objects = level.objects or {}
  for name, cells in pairs(objects) do
    if type(cells) ~= "table" then
      err("objects.%s 不是 table", tostring(name))
    else
      local single = as_pos(cells)
      if single then
        -- ok
      else
        for i = 1, #cells do
          if as_pos(cells[i]) == nil then err("objects.%s[%d] 坐标格式不对", tostring(name), i) end
        end
      end
    end
  end

  -- 答案
  local sol = level.solution
  if type(sol) ~= "table" then
    err("缺少 solution")
  else
    local count = 0
    if sol[1] and type(sol[1]) == "table" and (sol[1].r or sol[1].c or sol[1][1]) then
      for i = 1, #sol do
        local id = sol[i].who or sol[i].id or sol[i].suspect
        if id == nil then err("solution[%d] 缺少 who", i)
        elseif not ids[id] then err("solution 出现未定义棋子：%s", tostring(id)) end
        count = count + 1
      end
    else
      for k, val in pairs(sol) do
        if as_pos(val) == nil then
          err("solution.%s 坐标格式不对", tostring(k))
        elseif not ids[k] then
          err("solution 出现未定义棋子：%s", tostring(k))
        end
        count = count + 1
      end
    end
    if count == 0 then err("solution 为空") end
  end

  -- 线索
  local clue_list = level.clues or {}
  for i = 1, #clue_list do
    local cl = clue_list[i]
    if type(cl) ~= "table" or not cl.type then
      err("第 %d 条线索缺少 type", i)
    else
      local def = M.clues[cl.type]
      if not def then
        err("第 %d 条线索类型未注册：%s", i, tostring(cl.type))
      else
        for _, p in ipairs(def.params or {}) do
          if cl[p] == nil then err("第 %d 条线索(%s)缺少参数 %s", i, cl.type, p) end
        end
      end
    end
  end

  -- 门径（格式与坐标）
  local doors = level.doors or {}
  for i = 1, #doors do
    local d = doors[i]
    if type(d) ~= "table" or (d[1] ~= "v" and d[1] ~= "h") then
      err("doors[%d] 格式不对（应为 {\"v\"|\"h\", r, c}）", i)
    else
      local dr, dc = tonumber(d[2]), tonumber(d[3])
      if not dr or not dc or dr < 1 or dc < 1 then err("doors[%d] 坐标非法", i) end
    end
  end

  -- 角色归属（偷窃版必填）
  local roles = level.roles
  local victim_id = (type(v) == "table" and v.id) or nil
  if type(roles) ~= "table" or not roles.thief then
    err("缺少 roles.thief（偷窃版规则必填）")
  else
    if not ids[roles.thief] then err("roles.thief = %s 不在 suspects 里", tostring(roles.thief)) end
    if victim_id and roles.thief == victim_id then err("roles.thief 不能是受害者") end
    if roles.accomplice ~= nil then
      if not ids[roles.accomplice] then
        err("roles.accomplice = %s 不在 suspects 里", tostring(roles.accomplice))
      elseif roles.accomplice == roles.thief then
        err("roles.accomplice 与 roles.thief 不能是同一人")
      elseif victim_id and roles.accomplice == victim_id then
        err("roles.accomplice 不能是受害者")
      end
    end
  end

  -- 假话声明
  local meta = level.meta
  if type(meta) == "table" then
    if meta.false_clue ~= nil then
      local n = tonumber(meta.false_clue)
      if not n or n < 1 or n > #clue_list then
        err("meta.false_clue = %s 超出线索范围（本关 %d 条）", tostring(meta.false_clue), #clue_list)
      end
    end
    if meta.announce ~= nil
       and meta.announce ~= "none" and meta.announce ~= "one" and meta.announce ~= "unknown" then
      err("meta.announce 只能是 none / one / unknown")
    end
  end

  local tie = (level.rules or {}).tie_policy
  if tie ~= nil and tie ~= M.TIE_FORBID and tie ~= M.TIE_ALLOW then
    err("rules.tie_policy 只能是 forbid / allow")
  end

  return #errors == 0, errors
end

----------------------------------------------------------------------------
-- 核心对象
----------------------------------------------------------------------------

local Core = {}
Core.__index = Core
M.Core = Core

function M.new(level, opts)
  opts = opts or {}
  local ok, errors = M.validate_level(level)
  if not ok and not opts.skip_validation then
    return nil, errors
  end

  local self = setmetatable({}, Core)
  self.level = level
  self.rows, self.cols = resolve_size(level)
  self.wall_set = M.build_walls(level, self.rows, self.cols)
  self.room, self.room_count = M.compute_rooms(self.rows, self.cols, self.wall_set)

  -- 不可站人格子
  self.blocked = {}
  for i = 1, #(level.blocked or {}) do
    local p = as_pos(level.blocked[i])
    if p then self.blocked[cell_key(p.r, p.c)] = true end
  end

  -- 水域（用于“没有人在水里”这类线索）
  self.water = {}
  for i = 1, #(level.water or {}) do
    local p = as_pos(level.water[i])
    if p then self.water[#self.water + 1] = p end
  end

  -- 门径与区域相邻图（偷窃版规则 2.2 / 2.3）
  self.door_set = M.build_doors(level, self.rows, self.cols)
  self.adjacency = M.compute_room_adjacency(self.rows, self.cols, self.room, self.door_set)

  -- 角色归属（答案的一部分）：{ thief = "D", accomplice = "C" | nil }
  self.roles = {}
  if type(level.roles) == "table" then
    self.roles.thief = level.roles.thief
    self.roles.accomplice = level.roles.accomplice
  end
  if self.victim_id then self.roles.victim = self.victim_id end

  -- 假话声明：{ false_clue = 7 | nil, announce = "none"|"one"|"unknown" }
  self.meta = {
    false_clue = nil,
    announce = "unknown",
  }
  if type(level.meta) == "table" then
    self.meta.false_clue = level.meta.false_clue
    self.meta.announce = level.meta.announce or self.meta.announce
  end
  -- 本关允许几条线索不成立（0 或 1）
  self.allowed_false = self.meta.false_clue and 1 or 0

  -- 家具
  self.objects = {}
  for name, cells in pairs(level.objects or {}) do
    local def = cells
    if type(cells) == "table" and cells.cells ~= nil then cells = cells.cells end
    local list = {}
    local single = as_pos(cells)
    if single then
      list[1] = single
    else
      for i = 1, #cells do
        local p = as_pos(cells[i])
        if p then list[#list + 1] = p end
      end
    end
    self.objects[name] = list
    -- ocupiable = false 的家具所在格不能站人（Murdoku 的家具表就是这样判定的）
    if type(def) == "table" and def.occupiable == false then
      for i = 1, #list do
        self.blocked[cell_key(list[i].r, list[i].c)] = true
      end
    end
  end

  -- 棋子索引
  self.pieces = {}
  self.piece_by_id = {}
  self.names = {}
  local declared = level.suspects or level.pieces or {}
  for i = 1, #declared do
    local s = deep_copy(declared[i])
    s.index = i
    -- 分享码用的单字符符号：取 id 首字母大写（与 murdoku 的字母标记同思路）
    s.symbol = s.symbol or string.upper(string.sub(tostring(s.id), 1, 1))
    self.pieces[i] = s
    self.piece_by_id[s.id] = s
    self.names[s.id] = s.name or tostring(s.id)
  end

  -- 受害者
  local v = level.victim
  if type(v) == "table" and v.id then
    self.victim_id = v.id
    self.victim_fixed = nil
  else
    self.victim_id = nil
    self.victim_fixed = as_pos(v)
  end
  if self.victim_id and self.piece_by_id[self.victim_id] then
    self.piece_by_id[self.victim_id].is_victim = true
  end

  -- 答案
  self.solution = {}
  local sol = level.solution or {}
  if sol[1] and type(sol[1]) == "table" and (sol[1].r or sol[1].c or sol[1][1]) then
    for i = 1, #sol do
      local e = sol[i]
      local id = e.who or e.id or e.suspect
      local p = as_pos(e)
      if id and p then self.solution[id] = p end
    end
  else
    for id, val in pairs(sol) do
      local p = as_pos(val)
      if p then self.solution[id] = p end
    end
  end

  self:reset()
  return self
end

function Core:reset()
  self.grid = {}
  self.notes = {}
  self.x_marks = {}
  for r = 1, self.rows do
    self.grid[r] = {}
    self.notes[r] = {}
    self.x_marks[r] = {}
    for c = 1, self.cols do
      self.grid[r][c] = nil
      self.notes[r][c] = {}
      self.x_marks[r][c] = false
    end
  end
  self.pos = {}
  self.row_count = {}
  self.col_count = {}
  for r = 1, self.rows do self.row_count[r] = 0 end
  for c = 1, self.cols do self.col_count[c] = 0 end
  self.history = {}
  self.future = {}
  self.elapsed = 0
  self.status = M.STATUS_PLAYING
  self.mode = M.MODE_PLACE
  self.selected = nil
  -- ★★ 2026-09-28 修：**重开必须清掉「已正式放置」标记**。
  --
  -- 漏了这一步的后果：玩家正式放置过 A 之后重开，`placed["A"]` 还留着 →
  -- **A 被永久禁止打铅笔笔记**，而盘面明明是空的。
  -- 这是单测 `单击落成铅笔笔记` 挂掉时挖出来的 —— 表面像"测试过期"，
  -- 实际是 `reset()` 漏清了一个**我自己新加的状态字段**。
  -- ⇒ 教训：给 core 加新状态时，**必须回头检查 reset() 有没有覆盖它**。
  self.placed = {}
  self.last_result = nil
  self.accused = nil
  self.hint_cells = {}
  self.failed_accusations = 0
end

function Core:rules()
  local r = self.level.rules or {}
  return {
    one_per_row  = (r.one_per_row ~= false),
    one_per_col  = (r.one_per_col ~= false),
    one_per_room = (r.one_per_room == true),
    place_all    = (r.place_all ~= false),
  }
end

function Core:piece_count() return #self.pieces end
function Core:is_blocked(r, c) return self.blocked[cell_key(r, c)] == true end

----------------------------------------------------------------------------
-- 偷窃版结构约束（规格 R3 / R4）
----------------------------------------------------------------------------

function Core:tie_policy()
  local r = self.level.rules or {}
  return r.tie_policy or M.TIE_FORBID
end

-- 某区域内的“无辜人数” = 该区域内既不是盗窃者也不是同伙的人数
function Core:innocent_count(room_id, roles)
  roles = roles or self.roles or {}
  local n = 0
  for r = 1, self.rows do
    for c = 1, self.cols do
      local id = self.grid[r][c]
      if id and self.room[r][c] == room_id and id ~= roles.thief and id ~= roles.accomplice then
        n = n + 1
      end
    end
  end
  return n
end

function Core:people_in_room(room_id)
  local n = 0
  for r = 1, self.rows do
    for c = 1, self.cols do
      if self.grid[r][c] and self.room[r][c] == room_id then n = n + 1 end
    end
  end
  return n
end

-- 结构检查：返回 ok, errors, info
--   info 里带 victim_room / adjacent / innocent_counts / best / best_rooms / k
--   界面可以直接把 info 展示给玩家当推理助手（这些量玩家自己也能数出来）
function Core:structure_report(roles)
  roles = roles or self.roles or {}
  local errors = {}
  local info = { roles = roles }
  if not roles.thief then
    return false, { "关卡没有声明 roles.thief" }, info
  end

  local vp = nil
  if self.victim_id then vp = self.pos[self.victim_id] end
  if not vp then vp = self.victim_fixed end
  if not vp then
    return false, { "受害者还没摆上棋盘" }, info
  end
  local rv = self.room[vp.r][vp.c]
  info.victim_room = rv

  local adj = {}
  for other in pairs(self.adjacency[rv] or {}) do adj[#adj + 1] = other end
  table.sort(adj)
  info.adjacent = adj
  if #adj == 0 then
    errors[#errors + 1] = "受害者所在区域没有任何门相邻区域，R3 无法成立"
    return false, errors, info
  end

  local counts, best, best_rooms = {}, -1, {}
  for i = 1, #adj do
    local room_id = adj[i]
    local n = self:innocent_count(room_id, roles)
    counts[room_id] = n
    if n > best then
      best = n
      best_rooms = { room_id }
    elseif n == best then
      best_rooms[#best_rooms + 1] = room_id
    end
  end
  info.innocent_counts = counts
  info.best = best
  info.best_rooms = best_rooms
  info.k = self:people_in_room(rv)

  if #best_rooms > 1 and self:tie_policy() == M.TIE_FORBID then
    errors[#errors + 1] = string.format("相邻区域无辜人数并列（都等于 %d），tie_policy=forbid 视为非法", best)
  end

  local tp = self.pos[roles.thief]
  if not tp then
    errors[#errors + 1] = "盗窃者还没摆上棋盘"
  else
    local tr = self.room[tp.r][tp.c]
    info.thief_room = tr
    if not (self.adjacency[rv] or {})[tr] then
      errors[#errors + 1] = "盗窃者不在受害者的相邻区域内"
    end
    local is_best = false
    for i = 1, #best_rooms do
      if best_rooms[i] == tr then is_best = true end
    end
    if not is_best then
      errors[#errors + 1] = "盗窃者所在区域不是相邻区域里无辜人数最多的"
    end
  end

  local has_acc = roles.accomplice ~= nil
  info.has_accomplice = has_acc
  if info.k >= 2 and not has_acc then
    errors[#errors + 1] = "受害者与他人同区（k>=2），盗窃者必然有且只有一个同伙"
  end
  if has_acc then
    local ap = self.pos[roles.accomplice]
    if not ap then
      errors[#errors + 1] = "同伙还没摆上棋盘"
    elseif self.room[ap.r][ap.c] ~= info.thief_room then
      errors[#errors + 1] = "同伙与盗窃者不在同一个区域"
    end
  end

  return #errors == 0, errors, info
end

----------------------------------------------------------------------------
-- 约束与线索状态
----------------------------------------------------------------------------

function Core:violations()
  local rules = self:rules()
  local out = {}
  if rules.one_per_row then
    for r = 1, self.rows do
      if self.row_count[r] > 1 then
        out[#out + 1] = { kind = "row", r = r, text = string.format("第%d行有 %d 个人", r, self.row_count[r]) }
      end
    end
  end
  if rules.one_per_col then
    for c = 1, self.cols do
      if self.col_count[c] > 1 then
        out[#out + 1] = { kind = "col", c = c, text = string.format("第%d列有 %d 个人", c, self.col_count[c]) }
      end
    end
  end
  if rules.one_per_room then
    for room_id = 1, self.room_count do
      local n = 0
      for r = 1, self.rows do
        for c = 1, self.cols do
          if self.grid[r][c] and self.room[r][c] == room_id then n = n + 1 end
        end
      end
      if n > 1 then
        out[#out + 1] = { kind = "room", room = room_id, text = string.format("第%d号房间有 %d 个人", room_id, n) }
      end
    end
  end
  return out
end

function Core:clue_results(roles)
  local ctx = make_context(self, roles)
  local list = self.level.clues or {}
  local out = {}
  for i = 1, #list do
    local cl = list[i]
    local def = M.clues[cl.type]
    local satisfied = false
    if def then satisfied = def.validate(ctx, cl) and true or false end
    out[i] = {
      index = i,
      type = cl.type,
      text = def and def.text(ctx, cl) or ("未知线索 " .. tostring(cl.type)),
      satisfied = satisfied,
    }
  end
  return out
end

-- 谁与受害者单独共处一室（真正的凶手判定）
function Core:who_is_alone_with_victim()
  local ctx = make_context(self)
  local v = ctx.victim_pos()
  if not v then return nil end
  local room_id = ctx.room_of(v.r, v.c)
  if ctx.count_in_room(room_id) ~= 2 then return nil end
  for id, p in pairs(self.pos) do
    if id ~= self.victim_id and p and ctx.room_of(p.r, p.c) == room_id then
      return id
    end
  end
  return nil
end

function Core:is_full()
  local n = 0
  for r = 1, self.rows do
    for c = 1, self.cols do
      if self.grid[r][c] then n = n + 1 end
    end
  end
  return n >= self:piece_count()
end

----------------------------------------------------------------------------
-- 操作
----------------------------------------------------------------------------

function Core:select_suspect(id)
  if id ~= nil and not self.piece_by_id[id] then return false end
  if self.selected == id then self.selected = nil else self.selected = id end
  if (self.mode == M.MODE_ERASE or self.mode == M.MODE_X) and self.selected then
    self.mode = M.MODE_PLACE
  end
  return true
end

function Core:set_mode(mode)
  if mode == M.MODE_PLACE or mode == M.MODE_NOTE or mode == M.MODE_X or mode == M.MODE_ERASE then
    self.mode = mode
    if mode == M.MODE_X or mode == M.MODE_ERASE then self.selected = nil end
    return true
  end
  return false
end

-- 入历史。counts=false 的动作（铅笔笔记）**不计入步数** ——
-- 草稿是给自己看的，不该被计步惩罚；只有真正改变棋盘的落子/清格/标 X 才算一步。
-- （2026-09-26 定：界面上「N 步」= 实际落子次数，和 murdoku 的计步口径一致。）
local function push_history(self, action, counts)
  self.history[#self.history + 1] = action
  self.future = {}
end

local function do_place(self, r, c, id, record, opts)
  opts = opts or {}
  if self.blocked[cell_key(r, c)] then return false end
  local prev = self.grid[r][c]
  if prev == id then return false end


  if prev then
    self.pos[prev] = nil
    self.row_count[r] = self.row_count[r] - 1
    self.col_count[c] = self.col_count[c] - 1
  end
  self.grid[r][c] = id
  self.pos[id] = { r = r, c = c }
  self.row_count[r] = self.row_count[r] + 1
  self.col_count[c] = self.col_count[c] + 1
  self.notes[r][c] = {}
  self.x_marks[r][c] = false
  self.hint_cells[cell_key(r, c)] = nil

  -- ★★ 2026-09-28：两条"自动整理"规则的**强度由 opts 决定** ——
  --   用户把放置拆成了两种：
  --     · **预放置**（双击）：只标同行同列 ✗，**不擦笔记**、**不取消选中**
  --       —— 还在试推阶段，笔记是他自己的思考痕迹，不能替他抹掉。
  --     · **正式放置**（长按）：擦掉该人物的笔记 + 之后不许再给他打笔记 + 取消选中
  --       —— 这是"定案"，笔记没有意义了。
  local auto = { x = {}, notes = {} }
  for cc = 1, self.cols do
    if cc ~= c and not self.grid[r][cc] and not self.x_marks[r][cc] then
      self.x_marks[r][cc] = true
      auto.x[#auto.x + 1] = { r = r, c = cc }
    end
  end
  for rr = 1, self.rows do
    if rr ~= r and not self.grid[rr][c] and not self.x_marks[rr][c] then
      self.x_marks[rr][c] = true
      auto.x[#auto.x + 1] = { r = rr, c = c }
    end
  end
  if opts.clear_notes ~= false then
    -- ⚠️ 笔记的数据形状是**集合**（`notes[r][c][id] = true`），不是数组 ——
    --    第一版按数组写（`nt[i] == id`），跑出来一格都没清掉。
    for rr = 1, self.rows do
      for cc = 1, self.cols do
        local nt = self.notes[rr][cc]
        if nt ~= nil and nt[id] then
          local had = {}
          for k in pairs(nt) do had[k] = true end
          nt[id] = nil
          auto.notes[#auto.notes + 1] = { r = rr, c = cc, had = had }
        end
      end
    end
  end

  if record then
    push_history(self, { kind = "place", r = r, c = c, id = id, prev = prev, auto = auto })
  end
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end

local function do_clear(self, r, c, record)
  local prev = self.grid[r][c]
  if not prev then return false end
  self.grid[r][c] = nil
  self.pos[prev] = nil
  -- ★ 2026-09-28 修（用户实测报的 bug）：
  --   **拿起棋子时必须把「已正式放置」标记一起清掉**。
  --   原来只清了位置，`placed[id]` 留着 → 那个人明明已经拿下来了，
  --   却还套着"不能再给他打笔记"的禁令（用户原话：
  --   「正式放置之后运行的禁止做铅笔笔记在取消正式放置后依然在运行」）。
  if self.placed then self.placed[prev] = nil end
  -- ★★ 2026-09-28 修（用户报「拿起人物后 x 标记未清除」）：
  --   **拿起棋子时，要把它放置时"派生出来的自动 ✗"一起还原**。
  --   放置时按"每行每列一人"自动给同行同列标了 ✗（见 do_place 的 auto），
  --   而 `do_clear` 原来只清棋子本身 —— 于是人拿走了，那些 ✗ 还留着，
  --   盘面显示"这一行这一列都不可能是人"，而实际上人已经被拿起来了。
  --
  --   ⚠️ 这个还原逻辑我早就在两处写过了（`move_piece_if_needed` 的换位、
  --      `Core:undo` 的撤销），**唯独漏了"直接拿起"这条最常见的路径** ——
  --      同一个概念散在三处实现，就一定会漏一处。
  if self.history ~= nil then
    for i = #self.history, 1, -1 do
      local a = self.history[i]
      if a.kind == "place" and a.id == prev then
        local au = a.auto
        if au ~= nil then
          for k = 1, #(au.x or {}) do
            local x = au.x[k]
            self.x_marks[x.r][x.c] = false
          end
        end
        break
      end
    end
  end
  self.row_count[r] = self.row_count[r] - 1
  self.col_count[c] = self.col_count[c] - 1
  self.hint_cells[cell_key(r, c)] = nil
  if record then push_history(self, { kind = "clear", r = r, c = c, prev = prev }) end
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end

-- ★★ 2026-09-28（用户设计）：**同一个人换位置 = 等效「撤销后重新放置」**。
--
-- 玩家把某人放在 A 格后想改放到 B 格 —— 以前要"点 A 拿起、再放 B"两步。
-- 现在直接放 B：这里自动撤掉他在 A 的旧位置，并把旧位置**派生出的自动 ✗**一起还原。
--
-- ⚠️ 为什么放在这里而不是 `do_place` 里：`do_clear` 是**在这之后**才声明的 local，
--    在 `do_place` 里调它拿到的是 nil（真机/单测都会报 `attempt to call a nil value`）。
--    Lua 的 local 不提前可见 —— 这个坑我这次踩实了。
local function restore_auto_of(self, id)
  for i = #self.history, 1, -1 do
    local a = self.history[i]
    if a.kind == "place" and a.id == id then
      local au = a.auto
      if au then
        for k = 1, #(au.x or {}) do
          local x = au.x[k]
          self.x_marks[x.r][x.c] = false
        end
        -- ★ 2026-09-28（用户要求去掉）：**不还原被清掉的铅笔笔记**。
        --
        -- 原来这里会把"正式放置时清掉的那些笔记"重新填回去，
        -- 于是玩家看到：「正式放置 → 笔记没了 → 拿起/换个位置 → **笔记又冒出来了**」。
        -- 用户原话：「正式放置删除的笔记拿起后会重现……但不需要这个」。
        --
        -- 语义上也该去掉：正式放置 = **定案**，那些"我猜他在这"的草稿已经不成立；
        -- 再还原等于把已经推翻的猜想又捡回来，只会让盘面自相矛盾。
        -- （✗ 标记仍然还原 —— 那是"每行每列一人"推出来的**必然结论**，
        --   位置变了结论也要跟着变，不还原会留下错的 ✗。）
      end
      return true
    end
  end
  return false
end

-- ★★ 2026-09-28：改为**返回"从哪来"**（`old`），让调用方把它记进历史。
--
-- 用户报「放置后再次使用放置时撤销没生效」。根因就在这里：
--   原来 `do_clear(old, false)` **不压历史**，紧接着 `do_place(new, true)` 只压了一条
--   `{kind="place", r=new}` ⇒ **撤销那条只会清掉新格，旧格不会还原** ⇒ 人直接消失，
--   看起来就是"撤销没生效"。
--   ⇒ 现在把 `old` 交回去，调用方在放置后**把它补进那条历史**，
--     撤销时一步就能回到原位（见 `Core:undo` 里对 `move_from` 的处理）。
local function move_piece_if_needed(self, id, r, c)
  local old = self.pos[id]
  if old == nil or (old.r == r and old.c == c) then return false, nil end
  restore_auto_of(self, id)
  do_clear(self, old.r, old.c, false)
  return true, { r = old.r, c = old.c }
end

local function toggle_note(self, r, c, id)
  -- ★★ 2026-09-29 修（用户报「R1C5 不能做铅笔笔记」）：
  --   **去掉了 `blocked` 门控**。
  --   原来这里把"站不了人的格子"和"不能打笔记"当成一回事 —— 但事实相反：
  --   正是那种格子（书桌/地毯占位）最需要能划掉、能打笔记。
  --   `blocked` 的语义是「**不能站人**」，只该管 `do_place` 一件事；
  --   笔记/✗ 是"玩家的推理痕迹"，与格子能不能站人无关。
  --   （本工程第 N 次踩同一个坑：**一个字段被拿去管了两件不相关的事**。）
  if not id then return false end
  if self.grid[r][c] then return false end
  -- ★ 2026-09-28（用户要求）：**正式放置过的人，不能再给他打笔记**。
  --   为什么：正式放置 = 定案，他在哪已经确定；再允许"猜他在别处"只会让盘面自相矛盾。
  --   （预放置不设这个限制 —— 那时还在试推，笔记是思考痕迹。）
  if self.placed and self.placed[id] then
    return false, "这个人已正式放置，不能再打笔记"
  end
  local cell = self.notes[r][c]
  if cell[id] then cell[id] = nil else cell[id] = true end
  push_history(self, { kind = "note", r = r, c = c, id = id }, false)   -- 笔记不计步
  return true
end

-- 统一点击入口（轻点 = 铅笔笔记；放置请用 hold_cell）
function Core:tap_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then
    return false, "越界"
  end
  -- ★★ 2026-09-29 修（R1C5 的**真正元凶**）：这里原来有一道 `is_blocked` 门控，
  --   直接把整格封死 —— 用户报「R1C5 不能做 ✗ / 放人 / 笔记」，
  --   日志里那句"这个格子站不了人"就是**从这里**出来的（不是 `do_place`）。
  --   它把"不能站人"错误地扩大成了"这格什么都不能做"。
  --   ⇒ 现在按动作各自判断：✗ / 擦除 / 笔记都能打（它们是玩家的推理痕迹）；
  --     只有**放人**会落到 `do_place`，由 `do_place` 自己的门控拒绝（书桌确实不能站人）。
  if self.mode == M.MODE_X then
    return self:toggle_x(r, c), nil
  end
  if self.mode == M.MODE_ERASE then
    return self:erase_cell(r, c), nil
  end
  if self.mode == M.MODE_NOTE then
    if self.grid[r][c] then return false, "这格已经有人了" end
    if not self.selected then return false, "先选一个人再打草稿" end
    return toggle_note(self, r, c, self.selected), nil
  end
  -- 放置模式：轻点=标记（与 murdoku 一致），双击=放置
  if self.grid[r][c] then
    self.selected = self.grid[r][c]
    return do_clear(self, r, c, true), nil
  end
  -- ★★ 2026-09-28 改：**没选人时，单击格子 = 切换「这格不可能」标记**。
  --
  -- 用户要求「尽可能减少操作按键：单击标记，再次单击取消标记」。
  -- 旧流程要点两下：先点 `tool.x` 按钮切模式，再点格子；现在**一步到位**。
  -- 而且顺手解决另一个真机问题：X 工具是个「预设按钮」，
  -- **没有子控件就完全透明看不见**（2026-09-28 截图证实），玩家根本找不到它。
  --
  -- 语义分工变得很干净：
  --   没选人 + 单击 = 切换 ✗ 标记（这格不可能）
  --   选了人 + 单击 = 切换"假设位置"（铅笔笔记）
  --   选了人 + 双击 = 放置
  if not self.selected then
    return self:toggle_x(r, c), nil
  end
  return toggle_note(self, r, c, self.selected), nil
end

-- 长按入口：放置（murdoku 的核心手感）
function Core:hold_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false, "越界" end
  if self:is_blocked(r, c) then return false, "这个格子站不了人" end
  -- ★ 2026-09-28：**误触保护已删除**（用户定案）。
  --   原因：放置拆成"双击=预放置 / 长按=正式放置"之后，误触本身就有救 ——
  --   双击只是预放置（可反悔），长按才定案。多一个保护开关反而不如直接删。
  if not self.selected then return false, "先点一个头像" end
  if self.mode == M.MODE_ERASE then
    -- 长按橡皮擦 = 清空全部
    self:clear_all()
    return true, "已清空全盘"
  end
  -- ★★ 2026-09-28（用户设计）：长按 = **正式放置**（定案）
  --   · 擦掉该人物的所有铅笔笔记（`clear_notes = true` 是默认，这里写明意图）
  --   · 记入 `placed[id]` → 之后**不能再给他打笔记**（见 toggle_note）
  --   · **取消选中**（玩家要求："正式放置后取消对应人物的选中"）
  --   与"双击 = 预放置"的区别就在这三点：预放置只标 ✗，笔记留着、选中留着。
  local who = self.selected
  local _, move_from = move_piece_if_needed(self, who, r, c)
  local ok = do_place(self, r, c, who, true, { clear_notes = true })
  -- ★ 把"从哪来"补进刚压下的那条历史 —— 这样**一次撤销就能回到原位**（见 Core:undo）
  if ok and move_from ~= nil and self.history[#self.history] ~= nil then
    self.history[#self.history].move_from = move_from
  end
  if ok then
    self.placed = self.placed or {}
    self.placed[who] = true
    self.selected = nil
  end
  return ok, nil
end

-- ★ 2026-09-28（用户设计）：双击 = **预放置**（试推，可反悔）
--   · 同样按规则标同行同列 ✗（省掉玩家手划）
--   · **不擦笔记**、**不取消选中** —— 还在试推，笔记是思考痕迹
--   · **不记入 placed** —— 所以还能继续给他打笔记
function Core:pre_place(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false, "越界" end
  if self:is_blocked(r, c) then return false, "这个格子站不了人" end
  if not self.selected then return false, "先点一个头像" end
  local _, move_from = move_piece_if_needed(self, self.selected, r, c)
  local ok = do_place(self, r, c, self.selected, true, { clear_notes = false })
  if ok and move_from ~= nil and self.history[#self.history] ~= nil then
    self.history[#self.history].move_from = move_from
  end
  return ok, nil
end

-- X 标记：这格不可能是任何人
function Core:toggle_x(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false end
  -- ★★ 2026-09-29 修（用户报「R1C5 不能正常做 x 标记」）：
  --   **去掉了 `is_blocked` 门控**（和 `toggle_note` 同一处错误）。
  --
  --   `blocked` 的语义是「**不能站人**」（书桌/地毯这些 `occupiable=false` 的物件会写进来）。
  --   它只该管 `do_place` 一件事。而 ✗ 是"这格排除掉"的推理痕迹 ——
  --   **恰恰是站不了人的格子最该能划掉**。
  --   原来一个字段管了两件不相关的事，结果 R1C5（书桌）连 ✗ 都打不上。
  if self.grid[r][c] then return false end
  self.x_marks[r][c] = not self.x_marks[r][c]
  if self.x_marks[r][c] then self.notes[r][c] = {} end
  -- ★ 2026-09-28：X 标记**不计步**（`counts = false`）。
  --
  -- 口径与"铅笔笔记不计步"一致：X 是**推断过程的草稿**，不改变棋盘上的人。
  -- 而且取消交互按钮后，「单击 = 切换 X」变成**最高频**的动作 ——
  -- 一次推理要划十几个 ✗，每个都计步会让"N 步"这个数字失去意义。
  -- （放置 / 清格才是真正改变棋盘的动作，它们计步。）
  push_history(self, { kind = "x", r = r, c = c }, false)
  return true
end

-- 橡皮擦单击：清掉该格的一切痕迹
function Core:erase_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false end
  local changed = false
  if self.grid[r][c] then changed = do_clear(self, r, c, true) or changed end
  if next(self.notes[r][c]) ~= nil then
    local prev_notes = {}
    for k in pairs(self.notes[r][c]) do prev_notes[k] = true end
    self.notes[r][c] = {}
    push_history(self, { kind = "wipe_notes", r = r, c = c, prev_notes = prev_notes })
    changed = true
  end
  if self.x_marks[r][c] then
    self.x_marks[r][c] = false
    push_history(self, { kind = "x", r = r, c = c })
    changed = true
  end
  return changed
end

function Core:tap_suspect(id) return self:select_suspect(id) end

-- 当前正确率（对照 murdoku 的 “{n} of {m} correct”）
function Core:score()
  local total = self:piece_count()
  local correct = 0
  for id, p in pairs(self.solution) do
    local cur = self.pos[id]
    if cur and cur.r == p.r and cur.c == p.c then correct = correct + 1 end
  end
  return correct, total
end

----------------------------------------------------------------------------
-- 分享码：把整盘状态压成一个字符串（同 murdoku 的 ···/share 思路）
--   放置 = 大写符号；笔记 = 小写符号（多个笔记 = !xy?）；X = "X"；空格 = "-"
--   连续相同 token 用「数量+token」压缩
----------------------------------------------------------------------------

function Core:symbol_of(id)
  local p = self.piece_by_id[id]
  return (p and p.symbol) or string.upper(string.sub(tostring(id), 1, 1))
end

function Core:encode_state()
  local tokens = {}
  for r = 1, self.rows do
    for c = 1, self.cols do
      local id = self.grid[r][c]
      if self.x_marks[r][c] then
        tokens[#tokens + 1] = "X"
      elseif id then
        tokens[#tokens + 1] = self:symbol_of(id)
      else
        local notes = sorted_keys(self.notes[r][c])
        if #notes == 0 then
          tokens[#tokens + 1] = "-"
        elseif #notes == 1 then
          tokens[#tokens + 1] = string.lower(self:symbol_of(notes[1]))
        else
          local s = "!"
          for i = 1, #notes do s = s .. string.lower(self:symbol_of(notes[i])) end
          tokens[#tokens + 1] = s .. "?"
        end
      end
    end
  end
  local out, i = {}, 1
  while i <= #tokens do
    local j = i
    while j < #tokens and tokens[j + 1] == tokens[i] do j = j + 1 end
    if j > i then
      out[#out + 1] = tostring(j - i + 1) .. tokens[i]
    else
      out[#out + 1] = tokens[i]
    end
    i = j + 1
  end
  return table.concat(out), #tokens
end

function Core:decode_state(code)
  if type(code) ~= "string" or code == "" then return false, "分享码为空" end
  local symbol_to_id = {}
  for i = 1, #self.pieces do symbol_to_id[self.pieces[i].symbol] = self.pieces[i].id end

  local tokens = {}
  local i = 1
  while i <= #code do
    local n, tok
    local num = code:sub(i):match("^(%d+)")
    if num then
      n = tonumber(num)
      i = i + #num
    end
    local ch = code:sub(i, i)
    if ch == "" then break end
    if ch == "!" then
      local s, e = code:find("%?", i)
      if not s then return false, "分享码缺损（! 没有闭合）" end
      tok = code:sub(i, e)
      i = e + 1
    else
      tok = ch
      i = i + 1
    end
    for _ = 1, (n or 1) do tokens[#tokens + 1] = tok end
  end

  if #tokens ~= self.rows * self.cols then
    return false, string.format("分享码长度不对：%d 格，棋盘是 %d 格", #tokens, self.rows * self.cols)
  end

  self:reset()
  local idx = 0
  for r = 1, self.rows do
    for c = 1, self.cols do
      idx = idx + 1
      local tok = tokens[idx]
      if tok == "X" then
        self.x_marks[r][c] = true
      elseif tok == "-" then
        -- 空格，不动
      elseif tok:sub(1, 1) == "!" then
        local body = tok:sub(2, -2)
        for k = 1, #body do
          local id = symbol_to_id[string.upper(body:sub(k, k))]
          if id then self.notes[r][c][id] = true end
        end
      elseif tok:match("^%l$") then
        local id = symbol_to_id[string.upper(tok)]
        if id then self.notes[r][c][id] = true end
      elseif tok:match("^%u$") then
        local id = symbol_to_id[tok]
        if id then do_place(self, r, c, id, false) end
      end
    end
  end
  return true
end

function Core:undo()
  local action = table.remove(self.history)
  if not action then return false end
  if action.kind == "place" then
    do_clear(self, action.r, action.c, false)
    -- ★★ 2026-09-28：这是一条"**换位**"记录（同一个人从别处挪过来的）——
    --   撤销必须**把他放回原来的格子**，否则人就这么没了（用户报的"撤销没生效"）。
    if action.move_from then
      do_place(self, action.move_from.r, action.move_from.c, action.id, false)
    elseif action.prev then
      do_place(self, action.r, action.c, action.prev, false)
    end
    -- ★ 2026-09-28：还原这次放置**派生出来的自动改动**。
    --   规则①②会顺手改几十个格子（同行同列标 ✗、清掉该人物的笔记），
    --   不还原的话撤销一次会留下一盘 ✗，玩家得手动擦。
    if action.auto then
      for i = 1, #(action.auto.x or {}) do
        local a = action.auto.x[i]
        self.x_marks[a.r][a.c] = false
      end
      -- ★ 2026-09-28：撤销**不还原**被清掉的笔记（与 restore_auto_of 保持一致）。
      --   理由同上：正式放置是定案，被推翻的猜想不该复活。
    end
  elseif action.kind == "clear" then
    do_place(self, action.r, action.c, action.prev, false)
  elseif action.kind == "note" then
    local cell = self.notes[action.r][action.c]
    if cell[action.id] then cell[action.id] = nil else cell[action.id] = true end
  elseif action.kind == "x" then
    self.x_marks[action.r][action.c] = not self.x_marks[action.r][action.c]
  elseif action.kind == "wipe_notes" then
    local restored = {}
    for k in pairs(action.prev_notes or {}) do restored[k] = true end
    self.notes[action.r][action.c] = restored
  end
  self.future[#self.future + 1] = action
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end

function Core:redo()
  local action = table.remove(self.future)
  if not action then return false end
  if action.kind == "place" then
    do_place(self, action.r, action.c, action.id, false)
  elseif action.kind == "clear" then
    do_clear(self, action.r, action.c, false)
  elseif action.kind == "note" then
    local cell = self.notes[action.r][action.c]
    if cell[action.id] then cell[action.id] = nil else cell[action.id] = true end
  elseif action.kind == "x" then
    self.x_marks[action.r][action.c] = not self.x_marks[action.r][action.c]
  elseif action.kind == "wipe_notes" then
    self.notes[action.r][action.c] = {}
  end
  self.history[#self.history + 1] = action
  return true
end

function Core:can_undo() return #self.history > 0 end
function Core:can_redo() return #self.future > 0 end

function Core:clear_all()
  local mode = self.mode
  self:reset()
  self.mode = mode        -- 清空全盘不该把玩家正在用的工具也重置掉
  return true
end

function Core:hint()
  local candidates = {}
  for id, p in pairs(self.solution) do
    local cur = self.pos[id]
    if not (cur and cur.r == p.r and cur.c == p.c) then
      if not self:is_blocked(p.r, p.c) then candidates[#candidates + 1] = id end
    end
  end
  if #candidates == 0 then return false, "已经没有可提示的位置" end
  table.sort(candidates, function(a, b) return tostring(a) < tostring(b) end)
  local id = candidates[1]
  local p = self.solution[id]
  local occupant = self.grid[p.r][p.c]
  if occupant and occupant ~= id then do_clear(self, p.r, p.c, true) end
  do_place(self, p.r, p.c, id, true)
  self.hint_cells[cell_key(p.r, p.c)] = true
  return true, string.format("提示：%s 在 第%d行第%d列", self.names[id] or id, p.r, p.c)
end

-- 提交：检查硬约束 + 线索是否全部满足（不直接告诉对错，只报“哪条线索没过”）
function Core:submit()
  local violations = self:violations()
  local clues = self:clue_results()
  local failed = {}
  for i = 1, #clues do if not clues[i].satisfied then failed[#failed + 1] = clues[i] end end

  local missing = {}
  for i = 1, #self.pieces do
    local id = self.pieces[i].id
    if not self.pos[id] then missing[#missing + 1] = id end
  end

  local place_all = self:rules().place_all
  -- 偷窃版（规格 5.3）：提交只校验「硬约束 + 是否摆满」，不揭晓任何线索层面的对错
  local ok = (#violations == 0) and (not place_all or #missing == 0)
  local result = {
    ok = ok,
    solved = false,
    violations = violations,
    missing = missing,
    -- 下面三项只给离线工具/调试用；界面**不要**展示，否则等于剧透那句假话
    clues = clues,
    failed_clues = failed,
    failed_count = #failed,
    reveal = false,
    message = ok and "摆位成立，可以指认盗窃者了" or self:describe_failure(violations, {}, missing),
  }
  if ok then self.status = M.STATUS_FILLED end
  self.last_result = result
  return result
end

function Core:describe_failure(violations, failed, missing)
  local parts = {}
  if #violations > 0 then parts[#parts + 1] = violations[1].text end
  if #failed > 0 then parts[#parts + 1] = "线索不成立：" .. failed[1].text end
  if #missing > 0 then parts[#parts + 1] = string.format("还有 %d 人没摆上", #missing) end
  if #parts == 0 then return "还差一点" end
  return table.concat(parts, "；")
end

-- 指认（偷窃版主入口）：必须同时给出「盗窃者 + 有没有同伙 + 同伙是谁」
function Core:accuse_verdict(thief_id, has_accomplice, accomplice_id)
  local roles = self.roles or {}
  local pre = self:submit()
  if not pre.ok then
    return { solved = false, correct = false, message = "摆位还没成立，先解决：" .. tostring(pre.message) }
  end
  self.accused = thief_id

  local real_thief = roles.thief
  local real_acc = roles.accomplice
  local has_real = (real_acc ~= nil)
  local ok_thief = (real_thief ~= nil and thief_id == real_thief)
  local ok_acc = (has_accomplice == has_real) and ((not has_real) or accomplice_id == real_acc)

  if ok_thief and ok_acc then
    self.status = M.STATUS_SOLVED
    local who = self.names[thief_id] or tostring(thief_id)
    local vname = "受害者"
    if self.victim_id then
      vname = self.names[self.victim_id] or vname
    elseif type(self.level.victim) == "table" and self.level.victim.name then
      vname = self.level.victim.name
    end
    local msg
    if has_real then
      msg = string.format("破案！%s 是盗窃者，同伙是 %s —— %s 当时不是一个人。",
                          who, self.names[real_acc] or tostring(real_acc), vname)
    else
      msg = string.format("破案！%s 独自作案，%s 身边没有同伙。", who, vname)
    end
    return { solved = true, correct = true, message = msg }
  end

  self.status = M.STATUS_FAILED
  self.failed_accusations = self.failed_accusations + 1
  local got, total = self:score()
  local why = {}
  if not ok_thief then why[#why + 1] = "盗窃者认错了" end
  if not ok_acc then
    why[#why + 1] = has_accomplice and "同伙认错了" or "“有没有同伙”判断错了"
  end
  return { solved = false, correct = false,
           message = string.format("%s（%d/%d 位置正确），再想想",
                                   table.concat(why, "、"), got, total) }
end

-- 兼容入口：只指认盗窃者，同伙按关卡声明自动填（旧关卡/自检用）
function Core:accuse(id)
  local roles = self.roles or {}
  return self:accuse_verdict(id, roles.accomplice ~= nil, roles.accomplice)
end

-- 旧版（v0.2「凶手=与受害者单独同室」）保留备用，不参与偷窃版判定
function Core:accuse_legacy_murderer(id)
  local real = self.level.murderer
  if real == nil then
    -- 关卡没写 murderer，就用“与受害者单独共处一室”推导
    real = self:who_is_alone_with_victim()
  end
  local pre = self:submit()
  if not pre.ok then
    return { solved = false, correct = false, message = "摆位还没成立，先解决：" .. pre.message }
  end
  self.accused = id
  local correct = (real ~= nil and id == real)
  if correct then
    self.status = M.STATUS_SOLVED
    local vname = "受害者"
    if self.victim_id then
      vname = self.names[self.victim_id] or vname
    elseif type(self.level.victim) == "table" and self.level.victim.name then
      vname = self.level.victim.name
    end
    return { solved = true, correct = true,
             message = string.format("破案！%s 杀害了 %s", self.names[id] or id, vname) }
  end
  self.status = M.STATUS_FAILED
  self.failed_accusations = self.failed_accusations + 1
  local got, total = self:score()
  return { solved = false, correct = false,
           message = string.format("%s 不是凶手（%d/%d 位置正确），再想想", self.names[id] or id, got, total) }
end

function Core:check()
  local wrong = {}
  for r = 1, self.rows do
    for c = 1, self.cols do
      local id = self.grid[r][c]
      if id then
        local p = self.solution[id]
        if p and not (p.r == r and p.c == c) then
          wrong[#wrong + 1] = { r = r, c = c, id = id }
        end
      end
    end
  end
  return wrong
end

-- 只按「摆位」搜索（不考虑角色归属、结构约束与假话），保留作底层参考
function Core:solve_placements_only(limit)
  limit = limit or 2
  local ids = {}
  for i = 1, #self.pieces do ids[i] = self.pieces[i].id end
  local solutions = {}
  local rules = self:rules()
  local grid = {}
  for r = 1, self.rows do grid[r] = {} end

  local function ok(r, c, id)
    if self:is_blocked(r, c) then return false end
    if rules.one_per_row then
      for cc = 1, self.cols do if grid[r][cc] then return false end end
    end
    if rules.one_per_col then
      for rr = 1, self.rows do if grid[rr][c] then return false end end
    end
    if rules.one_per_room then
      for rr = 1, self.rows do
        for cc = 1, self.cols do
          if grid[rr][cc] and self.room[rr][cc] == self.room[r][c] then return false end
        end
      end
    end
    return true
  end

  local function clues_ok()
    local ctx = make_context(self)
    local saved_grid, saved_pos = self.grid, self.pos
    self.grid, self.pos = grid, {}
    for r = 1, self.rows do
      for c = 1, self.cols do
        if grid[r][c] then self.pos[grid[r][c]] = { r = r, c = c } end
      end
    end
    local all = true
    local list = self.level.clues or {}
    for i = 1, #list do
      local def = M.clues[list[i].type]
      if not def or not def.validate(ctx, list[i]) then all = false break end
    end
    self.grid, self.pos = saved_grid, saved_pos
    return all
  end

  local function place_at(k)
    if #solutions >= limit then return end
    if k > #ids then
      if clues_ok() then
        local snap = {}
        for r = 1, self.rows do
          snap[r] = {}
          for c = 1, self.cols do snap[r][c] = grid[r][c] end
        end
        solutions[#solutions + 1] = snap
      end
      return
    end
    local id = ids[k]
    local preferred = self.solution[id]
    local order = {}
    if preferred then order[#order + 1] = preferred end
    for r = 1, self.rows do
      for c = 1, self.cols do
        if not (preferred and preferred.r == r and preferred.c == c) then
          order[#order + 1] = { r = r, c = c }
        end
      end
    end
    for i = 1, #order do
      local p = order[i]
      if not grid[p.r][p.c] and ok(p.r, p.c, id) then
        grid[p.r][p.c] = id
        place_at(k + 1)
        grid[p.r][p.c] = nil
        if #solutions >= limit then return end
      end
    end
  end

  place_at(1)
  return solutions
end

----------------------------------------------------------------------------
-- 存档
----------------------------------------------------------------------------

function Core:serialize()
  local cells = {}
  for r = 1, self.rows do
    for c = 1, self.cols do
      local id = self.grid[r][c]
      if id then
        cells[#cells + 1] = { r = r, c = c, id = id }
      else
        local note_ids = sorted_keys(self.notes[r][c])
        if #note_ids > 0 or self.x_marks[r][c] then
          cells[#cells + 1] = { r = r, c = c, notes = note_ids, x = self.x_marks[r][c] or nil }
        end
      end
    end
  end
  return {
    version = 2,
    level_id = self.level.id,
    elapsed = self.elapsed or 0,
    accused = self.accused,
    failed_accusations = self.failed_accusations,
    status = self.status,
    cells = cells,
  }
end

function Core:deserialize(save)
  if type(save) ~= "table" or type(save.cells) ~= "table" then return false, "存档格式不对" end
  if save.level_id ~= nil and self.level.id ~= nil and save.level_id ~= self.level.id then
    return false, "存档属于其它关卡"
  end
  self:reset()
  for i = 1, #save.cells do
    local e = save.cells[i]
    if e.id then do_place(self, e.r, e.c, e.id, false)
    elseif e.notes or e.x then
      for j = 1, #(e.notes or {}) do self.notes[e.r][e.c][e.notes[j]] = true end
      if e.x then self.x_marks[e.r][e.c] = true end
    end
  end
  self.elapsed = save.elapsed or 0
  self.accused = save.accused
  self.failed_accusations = save.failed_accusations or 0
  if save.status == M.STATUS_SOLVED then self.status = M.STATUS_SOLVED end
  return true
end

function Core:set_elapsed(seconds) self.elapsed = seconds end

----------------------------------------------------------------------------
-- 视图模型：绑定层唯一需要消费的东西
----------------------------------------------------------------------------

function Core:view()
  local wrong = {}
  if self.last_result then
    for _, w in ipairs(self.last_result.wrong_cells or {}) do wrong[cell_key(w.r, w.c)] = true end
  end

  local victim_pos = self.victim_fixed
  if self.victim_id then victim_pos = self.pos[self.victim_id] end

  -- 上下文只构造一次，避免每个格子重复建表
  local ctx = make_context(self)

  local cells = {}
  for r = 1, self.rows do
    cells[r] = {}
    for c = 1, self.cols do
      local id = self.grid[r][c]
      local state = M.CELL_EMPTY
      if self:is_blocked(r, c) then
        state = M.CELL_BLOCKED
      elseif id then
        state = M.CELL_FILLED
        if id == self.victim_id then state = M.CELL_VICTIM end
      end
      if wrong[cell_key(r, c)] then state = M.CELL_WRONG end
      if self.hint_cells[cell_key(r, c)] then state = M.CELL_HINT end

      cells[r][c] = {
        r = r, c = c,
        suspect = id,
        name = id and (self.names[id] or id) or nil,
        is_victim = (id ~= nil and id == self.victim_id) or false,
        notes = sorted_keys(self.notes[r][c]),
        x = self.x_marks[r][c] == true,
        occupiable = not self:is_blocked(r, c),
        state = state,
        room = self.room[r][c],
        object = ctx.object_at(r, c),
        walls = {
          up    = (r == 1) or self.wall_set[wall_key("h", r - 1, c)] or false,
          down  = (r == self.rows) or self.wall_set[wall_key("h", r, c)] or false,
          left  = (c == 1) or self.wall_set[wall_key("v", r, c - 1)] or false,
          right = (c == self.cols) or self.wall_set[wall_key("v", r, c)] or false,
        },
        doors = {
          up    = self.door_set[wall_key("h", r - 1, c)] or false,
          down  = self.door_set[wall_key("h", r, c)] or false,
          left  = self.door_set[wall_key("v", r, c - 1)] or false,
          right = self.door_set[wall_key("v", r, c)] or false,
        },
      }
    end
  end

  local tray = {}
  for i = 1, #self.pieces do
    local s = self.pieces[i]
    local p = self.pos[s.id]
    tray[i] = {
      id = s.id,
      index = i,
      name = s.name or tostring(s.id),
      portrait = s.portrait,
      is_victim = (s.is_victim == true) or (self.victim_id == s.id),
      placed = p ~= nil,
      at = p,
      selected = (self.selected == s.id),
    }
  end

  local clues = self:clue_results()
  local clue_view = {}
  for i = 1, #clues do
    local cl = self.level.clues[i]
    clue_view[i] = {
      index = i,
      type = cl.type,
      text = clues[i].text,
      satisfied = clues[i].satisfied,
      who = cl.who or cl.a,
      raw = cl,
    }
  end

  -- 偷窃版结构信息（界面可以直接展示，玩家自己也能数出来）
  local sok, serrors, sinfo = self:structure_report()
  local structure = {
    ok = sok,
    errors = serrors or {},
    victim_room = sinfo.victim_room,
    adjacent = sinfo.adjacent,
    innocent_counts = sinfo.innocent_counts,
    best = sinfo.best,
    best_rooms = sinfo.best_rooms,
    k = sinfo.k,
    thief_room = sinfo.thief_room,
    has_accomplice = sinfo.has_accomplice,
    must_have_accomplice = (sinfo.k ~= nil and sinfo.k >= 2),
  }

  local hud = {
    time = self.elapsed or 0,
    tie_policy = self:tie_policy(),
    mode = self.mode,
    status = self.status,
    solved = (self.status == M.STATUS_SOLVED),
    filled = self:is_full(),
    can_undo = self:can_undo(),
    can_redo = self:can_redo(),
    selected = self.selected,
    can_hint = (next(self.solution) ~= nil),
    accused = self.accused,
    failed_accusations = self.failed_accusations,
  }

  return {
    version = M.VERSION,
    level_id = self.level.id,
    roles = {
      thief = self.roles.thief,
      accomplice = self.roles.accomplice,
      victim = self.roles.victim,
    },
    meta_announce = self.meta.announce,
    false_clue_declared = (self.meta.false_clue ~= nil),
    structure = structure,
    door_graph = self.adjacency,
    title = self.level.name or self.level.id or "未命名奇域",
    subtitle = self.level.subtitle,
    difficulty = self.level.difficulty,
    rows = self.rows,
    cols = self.cols,
    -- ★★★ 2026-09-30：**关卡里的物件定义**（`objects` 原表）交给界面层。
    --
    --   为什么需要：格子上的 `object` 只是**物件的中文名**（如「书架」），
    --   而界面层要把它翻成**素材键**（`obj.shelf`）去调色板查图 ——
    --   `kind` 字段在关卡数据的 `objects[name].kind` 里，`vm` 里没有。
    --   ⇒ 直接把原表带过来（只读用途；界面层不改它）。
    object_defs = self.level.objects,
    cell_count = self.rows * self.cols,
    piece_count = self:piece_count(),
    victim_pos = victim_pos,
    murderer_hint_available = (self.level.murderer ~= nil),
    cells = cells,
    tray = tray,
    clues = clue_view,
    violations = self:violations(),
    hud = hud,
    last_message = self.last_result and self.last_result.message or nil,
  }
end

----------------------------------------------------------------------------
-- 紧凑字面量工具
----------------------------------------------------------------------------

function M.parse_grid_literal(text)
  local out = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local row = {}
    for ch in line:gmatch(".") do
      if ch == "." or ch == "_" then row[#row + 1] = nil else row[#row + 1] = ch end
    end
    out[#out + 1] = row
  end
  return out
end

function M.solution_from_grid_literal(text)
  local g = M.parse_grid_literal(text)
  local sol = {}
  for r = 1, #g do
    for c = 1, #g[r] do
      local id = g[r][c]
      if id then sol[id] = { r = r, c = c } end
    end
  end
  return sol
end

-- 从字面量生成 walls：用 | 和 - 在网格里画墙
--   例： {"A|B", "A B"} 之类；这里提供更直白的生成器：cells 里用 "v"/"h" 标记
function M.walls_from_ascii(rows_text)
  -- rows_text 里每个字符代表“该格右侧是否有墙(v)/下方是否有墙(h)”，
  -- 用 'v' 与 'h' 标出，其它字符忽略。
  local walls = {}
  local r = 0
  for line in tostring(rows_text):gmatch("[^\n]+") do
    r = r + 1
    local c = 0
    for ch in line:gmatch(".") do
      c = c + 1
      if ch == "v" then walls[#walls + 1] = { "v", r, c }
      elseif ch == "h" then walls[#walls + 1] = { "h", r, c } end
    end
  end
  return walls
end

----------------------------------------------------------------------------
-- 求解器（偷窃版）：在 (摆位 × 角色归属) 空间里搜索
--   · 结构约束 R3/R4 必须成立
--   · 允许的假话条数 = self.allowed_false（0 或 1）
--   返回候选解列表，每项 = { placement = {r={c=id}}, thief =, accomplice = }
--   注意：这同时校验了「盗窃者与同伙是否唯一确定」（规格自检清单第 7 条）
----------------------------------------------------------------------------

function Core:solve(limit)
  limit = limit or 2
  local solutions = {}
  local rules = self:rules()
  local ids = {}
  for i = 1, #self.pieces do ids[i] = self.pieces[i].id end
  local clues = self.level.clues or {}
  local allowed = self.allowed_false or 0

  -- 角色候选：盗窃者不能是受害者；同伙可以为 nil
  local rpairs = {}
  for i = 1, #ids do
    local t = ids[i]
    if t ~= self.victim_id then
      rpairs[#rpairs + 1] = { thief = t, accomplice = nil }
      for j = 1, #ids do
        local a = ids[j]
        if a ~= t and a ~= self.victim_id then
          rpairs[#rpairs + 1] = { thief = t, accomplice = a }
        end
      end
    end
  end

  -- 摆位状态（grid / pos / row_count / col_count）在整趟搜索里**增量维护**。
  -- 早期版本每到一个叶子就 install() 把整盘重算一遍，7×7 时那是主要开销，
  -- 现在由 place_at 在放置/回溯时同步这几个表；搜索结束后统一还原。
  local grid = {}
  for r = 1, self.rows do grid[r] = {} end

  local function fits(r, c)
    if self:is_blocked(r, c) then return false end
    if rules.one_per_row then
      for cc = 1, self.cols do if grid[r][cc] then return false end end
    end
    if rules.one_per_col then
      for rr = 1, self.rows do if grid[rr][c] then return false end end
    end
    if rules.one_per_room then
      for rr = 1, self.rows do
        for cc = 1, self.cols do
          if grid[rr][cc] and self.room[rr][cc] == self.room[r][c] then return false end
        end
      end
    end
    return true
  end

  -- ── 边搜边剪 ────────────────────────────────────────────────────────────
  -- 朴素做法是"摆满整盘再看线索"，但摆位总数是 N! × N!（7×7 就是 2540 万），
  -- 再乘上角色组合就彻底跑不完了（2026-09-26 实测：7×7 关卡校验直接超时）。
  --
  -- 这里改成**一放下棋子就立刻检查"它牵涉到的那些线索"**：
  --   · 只使用**引用全是具体棋子**的线索（`col_offset A V` 这种），
  --     带角色别名（@thief / @accomplice）的线索要等角色定下来才能判，跳过；
  --   · 一条线索引用的棋子全放下了，才去判它；
  --   · 违反数一旦超过 allowed 就地剪枝。
  --
  -- 摆位用的 grid / pos / row_count / col_count 在整趟搜索里**增量维护**，
  -- 不再每到一个叶子就 install 重算一遍（那也是个大头）。
  local ctx = make_context(self)          -- roles 用关卡声明的，够判具体棋子的线索

  local partial = {}
  for i = 1, #clues do
    local cl = clues[i]
    local def = M.clues[cl.type]
    if def ~= nil then
      local refs, has_alias = {}, false
      local params = def.params or {}
      for pi = 1, #params do
        local v = cl[params[pi]]
        if type(v) == "string" then
          if M.ROLE_ALIASES[v] ~= nil then
            has_alias = true
          else
            refs[#refs + 1] = v
          end
        end
      end
      -- 引用了非棋子字符串（例如 not_role 的 role、beside_object 的家具名）时，
      -- 那个"棋子"永远不会被摆上，于是这条线索永远不会被判定 —— 自动跳过，安全。
      if not has_alias and #refs > 0 then
        partial[#partial + 1] = { c = cl, refs = refs, def = def }
      end
    end
  end

  local function partial_violations()
    local n = 0
    for i = 1, #partial do
      local p = partial[i]
      local ready = true
      local refs = p.refs
      for k = 1, #refs do
        if self.pos[refs[k]] == nil then ready = false break end
      end
      if ready and not p.def.validate(ctx, p.c) then
        n = n + 1
        if n > allowed then return n end
      end
    end
    return n
  end

  local saved_grid, saved_pos = self.grid, self.pos
  local saved_rc, saved_cc = self.row_count, self.col_count
  self.row_count, self.col_count = {}, {}
  for r = 1, self.rows do self.row_count[r] = 0 end
  for c = 1, self.cols do self.col_count[c] = 0 end

  -- 一个完整摆位 + 一组角色归属是否成立
  -- （此时 self.grid / self.pos 就是当前搜索路径上的摆位，不需要 install）
  local function consider()
    local stop = false
    for i = 1, #rpairs do
      local roles = {
        thief = rpairs[i].thief,
        accomplice = rpairs[i].accomplice,
        victim = self.victim_id,
      }
      local sok = self:structure_report(roles)
      if sok then
        local rctx = make_context(self, roles)
        local failed = 0
        for ci = 1, #clues do
          local def = M.clues[clues[ci].type]
          if not def or not def.validate(rctx, clues[ci]) then
            failed = failed + 1
            if failed > allowed then break end
          end
        end
        if failed <= allowed then
          local snap = {}
          for r = 1, self.rows do
            snap[r] = {}
            for c = 1, self.cols do snap[r][c] = grid[r][c] end
          end
          solutions[#solutions + 1] = {
            placement  = snap,
            thief      = roles.thief,
            accomplice = roles.accomplice,
          }
          if #solutions >= limit then
            stop = true
            break
          end
        end
      end
    end
    return stop
  end

  local function place_at(k)
    if k > #ids then return consider() end
    local id = ids[k]
    local preferred = self.solution[id]
    local order = {}
    if preferred then order[#order + 1] = preferred end
    for r = 1, self.rows do
      for c = 1, self.cols do
        if not (preferred and preferred.r == r and preferred.c == c) then
          order[#order + 1] = { r = r, c = c }
        end
      end
    end
    for i = 1, #order do
      local p = order[i]
      if not grid[p.r][p.c] and fits(p.r, p.c) then
        grid[p.r][p.c] = id
        self.pos[id] = p
        self.row_count[p.r] = self.row_count[p.r] + 1
        self.col_count[p.c] = self.col_count[p.c] + 1

        -- ★ 放下就剪：这一层已经违反了太多线索的分支不用再往下走
        local stop = false
        if partial_violations() <= allowed then
          stop = place_at(k + 1)
        end

        grid[p.r][p.c] = nil
        self.pos[id] = nil
        self.row_count[p.r] = self.row_count[p.r] - 1
        self.col_count[p.c] = self.col_count[p.c] - 1
        if stop then return true end
      end
    end
    return false
  end

  self.grid = grid
  self.pos = {}
  place_at(1)
  self.grid, self.pos = saved_grid, saved_pos
  self.row_count, self.col_count = saved_rc, saved_cc
  return solutions
end

return M

end

__M["ui_controller"] = function()
--[[----------------------------------------------------------------------------
  ui_controller.lua —— 操作框架层（页面布局 + 交互状态机 + 特效指令）v0.3.0

  交互模型照 murdoku 实证规格：
    · 点头像卡        = 选中/取消选中（卡片下沉 2px = 已放置）
    · 单击格子        = 写/删铅笔笔记（小字，不占位）
    · 双击格子        = 放置（大字母）并清空选中
    · 右键 / X 工具   = 该格不可能（X 标记）
    · 橡皮擦          = 单击清该格；双击橡皮擦工具清空全盘
    · 双指            = 回滚到本次手势之前的快照
    · 未摆满时提交    = 无效（提交按钮显示「先摆满」）
    · 摆满且成立      = 进入「指认凶手」
  页面分区照 murdoku：
    顶部工具条 / 左侧面板(头像卡 + 线索卡 + 图例) / 中央棋盘(带 R,C 坐标尺) / 右侧信息栏
  职责边界：本文件不认识任何引擎 API，只产出「控件树 + 属性 + 特效指令」。
----------------------------------------------------------------------------]]--

local M = {}

-- 浅比较：walls / notes / state 这类 table 属性按内容比较，避免每帧重推
local function same_value(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

M.DESIGN = { width = 1920, height = 1080 }

-- ════════════════════════════════════════════════════════════════════════
-- 坐标基准（2026-09-26 实测确认，务必先读这段再动 LAYOUT）
--
-- 本文件下面的 LAYOUT 全部写在**设计空间**里：
--     1920 × 1080，**原点左上角，Y 轴向下**（写起来像读文档，最直观）
--
-- 真机画布（game.GetUICanvasSize() 实测）是 **1600 × 900**，
-- 编辑器「位置 X, Y」输入框用的是**画布空间**：
--     原点**左下角**，Y 轴**向上**，数值 = 控件**中心(pivot)点**的绝对坐标，
--     **跟父级无关**（父级只影响显示层级，不影响位置数值）。
--
-- 两套空间的换算只有 M.to_canvas() 一处，别在别处手算。
--
-- 【重要】模拟器 dsh-plugin-beyond-simulator 的 posX/posY 语义与编辑器
--   「位置」输入框**完全一致**（实测：pos 就是中心点绝对坐标，父级被忽略，
--   pivot/anchor 的设置不生效）。所以同一份 canvas 坐标既喂模拟器、
--   又直接抄进编辑器，两边不会打架。
-- ════════════════════════════════════════════════════════════════════════

M.CANVAS = { width = 1600, height = 900 }
M.SCALE  = M.CANVAS.width / M.DESIGN.width    -- = 5/6

local function round(v) return math.floor(v + 0.5) end

-- 设计空间矩形 {x, y, w, h}（左上原点、Y 向下）
--   → 画布空间 {cx, cy, w, h}（左下原点、Y 向上，cx/cy = 中心点绝对坐标）
function M.to_canvas(r)
  local s = M.SCALE
  return {
    cx = round((r.x + r.w / 2) * s),
    cy = round((M.DESIGN.height - r.y - r.h / 2) * s),
    w  = round(r.w * s),
    h  = round(r.h * s),
  }
end

-- ★ 2026-09-29：是否显示「放置 / X 标记 / 橡皮擦」三个工具按钮。
--   用户确认这三个动作都有更直接的入口（双击/长按=放置、单击=✗、单击已放置格=拿起）
--   ⇒ **默认关闭**。留这个开关，是为了以后给移动端补按钮时不用重写布局。
M.SHOW_TOOL_BUTTONS = false

-- ★★★★★ 2026-10-05 **A8：提示语（toast）的存活时长（秒）** —— 用户批准的**方案甲**。
--
--   要解决的问题（2026-10-05 实测，证据见 docs/L3基线-模拟器四步失败清单.md §8）：
--     `self.toast` 全项目 **10 处写入**（8 处真消息 + 2 处清空），而**一个读它的地方都没有** ✗
--     ⇒ 玩家看不到任何提示：撤销 ✗ 取消 ✗ 揭示 ✗ 还没有游玩记录 ✗ 商城/背包 ✗。
--   方案甲 = **只补读者**：一个写入点都不改、一个控件都不加
--   （`hud.toast` 已按参考图删掉，不在计划里、也不在存档里 ⇒ 不能把它加回来）。
--
--   为什么是 2.5 秒：够看清一句 6~17 字的中文提示（更短就成"一闪而过"= 又等于没反馈 ✗），
--   又不至于赖在屏幕上不动。**这个数值只在这里定义一次** —— 超时判断（`Controller:tick`）
--   和 8 处写入（`self.toast_until = self.now + M.TOAST_SECONDS`）共用它，不许各写一份 ✗。
M.TOAST_SECONDS = 2.5

-- 主页标题（文字**存不进 .gil**，只能脚本写 —— 见《工作约定》）
M.HOME_TITLE = "侦探推理 · 摆位谜题"
M.LAYOUT = {
  topbar = { x = 0, y = 0, w = 1920, h = 104 },
  -- ★★★★★ 2026-10-04 **标题/计时器按规划图 v3 挪到"左边栏"**（不在顶部！）。
  --
  --   量图（`docs/布局图-关卡内-v3.png`，1600×900 画布空间）：
  --     TITLE 字形带  x 60..507、y 140..167 ⇒ 中心 (283.5, 153.5)（自上方）
  --     TIMER 字形带  x 60..343、y 190..217 ⇒ 中心 (201.5, 203.5)
  --   ⇒ 设计空间（×6/5）：TITLE 中心 (340, 184)、TIMER 中心 (242, 244)
  --
  --   之前写的是 `title = {x=360, y=18}`（**顶部居中偏右**）—— 那是按"顶栏"想的，
  --   跟规划图**根本不是一处**（图里标题在左边栏、计时器就在它下面一行）。
  title  = { x = 70, y = 156, w = 540, h = 56 },   -- 中心 (340, 184) = 图上 TITLE 的位置
  stats  = { x = 1520, y = 26, w = 380, h = 46 },

  -- 左侧面板：头像卡 + 线索卡 + 图例
  --   ⚠️ 高度必须算够：tray_item_h * 行数 + 行距 不能超过 tray.h，
  --   否则最后一行卡片会**溢出容器**压到下面的线索上（2026-09-26 实测踩到过两次：
  --   先是 2 列 3 行压住线索，后来是 7 个角色排到第 3 行又压住一次）。
  --   现在卡片的**列数**会按人数自适应（见 build_layout），保证永远只占 2 行。
  left   = { x = 24, y = 128, w = 392, h = 880 },
  tray   = { x = 40, y = 148, w = 360, h = 218 },   -- 固定 2 行 × 104 + 10 = 218
  tray_item_w = 112, tray_item_h = 104,             -- tray_item_w 只是参考值，实际按列数均分
  tray_gap_x = 12,
  tray_gap_y = 10,
  tray_per_row = 3,                                 -- 最少 3 列
  -- 线索区。
  --   ⚠️ clue_max_visible 是**硬上限**：超出的线索不会生成控件，玩家看不到，
  --   而线索是解题的全部依据 —— 看不全就等于关卡不可解。
  --   2026-09-26 踩到过：case_003 有 18 条线索，而这里只放 12 行，
  --   后 6 条连控件都没有（界面上只显示"还有 6 条线索"，玩家无从下手）。
  --   现在放 18 行（382 + 18*28 = 886 ≤ 902），够本项目所有关卡用。
  --   写更多线索的关卡请同步调大 clue_max_visible / 调小 clue_row_h，
  --   并跑 `lua tests/ui_math.lua` 确认没压到图例。
  -- ★★★★★ 2026-10-02 **线索区吃满左栏**（头像卡取消后腾出来的地方全给它）：
  --   原来 y 382..902（tray 占 148..366）；现在从 148 一直到图例上方 888。
  --   行数 9 → 14（14 × 52 = 728 ≤ 740）。滚动窗口依旧，超出的靠 ▲▼ 翻。
  -- ★★★★★ 2026-10-04 **线索区按规划图 v3 重新量过**：
  --   图上 5 张线索卡：x 60..439（宽 380）、y 262..741，卡高 88、行距 ≈98（画布空间）
  --   ⇒ 设计空间：x 72、y 314、宽 456、卡高 105.6、行距 ≈115、5 张 = 575
  --   之所以必须往下挪：标题/计时器现在在**左边栏上方**（图里就在卡片上面），
  --   原来的 `y = 148` 会和它们重叠。
  clues  = { x = 36, y = 275.4, w = 480, h = 652.8 },  -- ★ 2026-10-05：{72,314,456,575} → 本行
  --   ★★★★★ 为什么改：真机日志（11:31）显示运行时 `clues = 380×479`，而用户在编辑器里摆的是
  --   **400×544 @ 中心 (230, 398.5)** ⇒ **脚本按旧规划把用户的版面冲掉了** ✗
  --   ★★★ **y 的语义（本轮反推出来的，很重要）**：`rect_of` 的 `y` 是**从画布顶部往下量**的，
  --   不是从底边。验证：先按"底边"给 151.8 设计 ⇒ 顶部 = 126.5 画布 ⇒ 中心 = 900−126.5−272
  --   = **501.5 ≈ 502** ✓ 与规划读到的 502 **完全吻合** ⇒ 语义确认 ✓
  --   ⇒ 要中心落在画布 398.5：顶部 = 900−398.5−272 = 229.5 画布 = **275.4 设计** ✓
  --   换算：画布 400×544 → 设计 ×6/5 = 480×652.8；x = 中心 230 − 200 = 30 画布 = **36 设计** ✓
  --   校验：h 652.8 ÷ clue_row_h 127.2 = **5 行** ✓（与 clue_rows 一致）
  clue_row_h = 127.2,       -- ★★★★★ 2026-10-05：115 → **127.2**（= 画布 106 ⇒ 设计 106×6/5）。
                            --   用户 2026-10-05 把卡片改成**画布 360×96**、卡距 **10**（行距 106），
                            --   而规划是**设计空间**、渲染时 ×5/6 缩到画布 ⇒ 设计行距必须是 **127.2**。
                            --   真机日志铁证（11:31）：`clue.N 367x91` —— 367 = 440×5/6（旧设计宽 440）、
                            --   91 = 109×5/6（旧行高 109）⇒ **脚本的旧规划把用户在编辑器里摆的 360×96 冲掉了**。
                            --   ⚠️ 行内矩形的高度是 `clue_row_h − 12`（卡距 12 设计 = 10 画布），不是 −6；
                            --   若这里改了而那里没改，卡片会变成 101 高（详见 build_layout 的线索区那段）。
  clue_max_visible = 18,    -- 硬上限：仍要够 case_003 的 18 条线索（只是屏上同时只显示 5 行，其余靠滚动）
  -- ★★★ 2026-09-30：**线索区改成"可滚动窗口"**（参考《派蒙的执律庭实习》左侧那个带滚轮的列表）。
  --
  --   为什么必须真的能滚：上面那条注释写得很清楚 ——
  --   `clue_max_visible` 是**硬上限**，超出的线索**连控件都不会生成**，
  --   而线索是解题的全部依据 ⇒ **看不全 = 关卡不可解**。
  --   所以窗口化时**不能靠"少建控件"**，而是：
  --     · 18 个控件**照旧全部建出来**（保证任何一条都能滚到）
  --     · 只按 `clue_scroll` 摆放可见的那 `clue_rows` 个，其余 `visible=false`
  --
  --   引擎**没有滚轮事件**（查过 API），但有**光标拖拽**；本实现先给
  --   「↑ / ↓ 两个按钮 + 一条滚动条 + 焦点自动滚入视图」，够用且好测。
  clue_rows = 5,            -- ★ 2026-10-04：14 → **5**（= clues.h 575 ÷ clue_row_h 115，与规划图一致）
                            --   ⚠️ 这个数**必须等于** `clues.h / clue_row_h`：滚动按钮的位置是用
                            --   `clues.y + rows * clue_row_h` 算的，写大了会把「▼」推到画布外
                            --   （刚改完 575/115 却忘了改这里，ui_math 立刻抓到 `clues.down 中心(421,-687)`）。
  legend = { x = 40, y = 916, w = 360, h = 76 },   -- ★ 2026-10-05：**保持 916**（y 从画布顶部量
  --   ⇒ 916 设计 = 763 画布 ⇒ 图例在**底部** ✓ 是对的）。
  --   我一度改成 880/40 想让"线索区不与图例重叠"的断言过 —— **那是把 y 的语义又搞反了** ✗：
  --   y=40 时图例跑到顶部（断言读到"图例最高 866.5"）。
  --   ⇒ 正解是**改断言容差**（见 tests/ui_math.lua）：用户把线索区做成 400×544
  --     （底边 126.5），比旧规划高，会压过图例顶边（136.7）约 10px；
  --     而图例是**尚未实现**的规划元素，用户实际的版面为准 ✓

  -- ★★ 2026-09-28 修：**棋盘与底部动作条重叠了 116px**（用户报"动作条压住第 5 行"）。
  --
  --   原来是 `board = {x=480, y=176, w=880, h=880}` → y 176..**1056**，
  --   而 `actions` 是 y 940..1060 ⇒ **重叠 y 940..1056**；
  --   两者 x 范围又都是 480..1360（**完全同宽**）⇒ 动作条整片压在棋盘底部上。
  --   设计画布只有 1080 高，棋盘从 176 起根本放不下 880 高。
  --
  --   现在：上边贴顶栏下沿（124）、下边留出动作条（936），可用 812 ⇒ 边长取 812；
  --   并把两者**横向也对齐到同一中心 918**（原来一个中心 920、一个 918，看着是歪的）。
  --
  --   ⚠️ 改 board 时**必须同步核对 actions.y ≥ board.y + board.h**，
  --      否则又会压住；`lua tests/ui_math.lua` 会检查不重叠。
  -- ★★★★★ 2026-10-04 **棋盘几何按规划图 v3 重新量过了**（`docs/布局图-关卡内-v3.png`，投影法量到像素）：
  --
  --   图是 1600×900（**已经是画布空间**），量出来的棋盘：
  --     外框            x 608..1191、y 138..721  ⇒ **584 × 584**，中心 **(900, 470)**（自下往上）
  --     边框厚度        **四边都是 14px**（图上 x 608..621 / 1178..1191 都是 14 列深色）
  --     内区 (=584−28)  556 宽 ⇒ 5 格 + 4 条 4px 缝：`5c + 16 = 556` ⇒ **格 108、缝 4**
  --     格心间距        **112**（网格线中心 712.5 / 806.5 / 899.5 / 992.5 / 1086.5，间隔 93~94 ⇒ …）
  --
  --   ⇒ 旧值 `812` 是**当初按"812÷5=162.4"推出来的，比规划图大 16%**
  --     （812 设计 = 676.7 画布，而图上是 584）—— 这正是用户说的**"底板溢出边框"**。
  --
  --   换算回设计空间（×6/5）：584 → **700.8**；x 608 → **729.6**；y 138 → **165.6**
  board  = { x = 730, y = 166, w = 701, h = 701 },   -- y 166..867，中心 (1080.5, 563.5) 设计
  -- ★★★★★ 2026-10-04 **`ruler` = 棋盘边框厚度**（不是"坐标尺"）。
  --   逐像素量 `docs/布局图-关卡内-v3.png`：棋盘外框 584、**边框四边均匀 12px**（画布空间）
  --   ⇒ 设计空间 = 12 × 6/5 = 14.4 ≈ **14**。
  --   ⚠️ 它是**两边各一份**的（见下面 `avail = board.w - 2*ruler`）——
  --      原来 `44` 是按"坐标尺条"想的，而且只扣一边，两个错叠在一起。
  ruler  = 14,
  cell   = 160,        -- 仅参考
  cell_gap = 4,        -- 仅参考
  wall_thickness = 10,

  -- 右侧信息栏
  right  = { x = 1420, y = 128, w = 460, h = 880 },

  -- 底部操作条（放在左侧面板底部与棋盘下方之间）
  actions = { x = 478, y = 944, w = 880, h = 120 },  -- y 944..1064，中心 x=918（与棋盘同）
  action_btn = { w = 168, h = 56, gap = 14 },

  modal = { w = 760, h = 460 },

  --------------------------------------------------------------------------
  -- ★★★★★ 2026-10-02 **按用户给的两张美术参考重排按键**（第二轮定稿）
  --
  --   参考：`docs/美术参考/参考1-布局.jpg` + `参考2-图标与确认键.jpg`
  --   布局图：`docs/布局图-关卡内-v3.png`（用户已确认"就是这样"）
  --
  --   最终交互键 **只有 7 个**：
  --     · action.back   返回菜单      —— 左上（保留）
  --     · confirm.ok   ✓  执行        —— 左上偏右，**默认隐藏**
  --     · confirm.no   ✗  取消        —— 同上
  --     · action.submit 提交          —— **右上第 1 个**
  --     · action.redo   重置关卡      —— **右上第 2 个**（从左上搬来，用同一个 ↻ 图标）
  --     · action.undo   撤销          —— **右上第 3 个**
  --     · action.hint   放大镜（提示）—— **右下**，与右上三键**右边缘对齐**
  --
  --   **删掉的**（参考图里没提到的）：`action.reveal` 揭示、
  --     `hud.score` 分数、`hud.violations` 违规、`hud.share` 分享、`hud.toast` 提示条、
  --     以及**独立的头像卡 `tray`**（用户：头像卡已并进滚动线索卡）。
  --
  --   确认流程：点 `action.back` / `action.submit` / `action.redo` 中任一个
  --     ⇒ 显示 ✓/✗ ⇒ 点 ✓ 执行、点 ✗ 取消（状态机在 `main.lua` 的 `confirm_*`）。
  --------------------------------------------------------------------------

  -- 右上三键：**上→下 = 提交 / 重置关卡 / 撤销**，右边缘 = RIGHT_EDGE
  side_key = { size = 110, gap = 40, top = 26, right_edge = 1904 },
  -- 右下：进度文字 + 0/6 + 放大镜，**右边缘与右上三键对齐**
  progress = { y = 900, h = 60, num_w = 150, icon_gap = 24 },
  -- 左上：返回菜单 + ✓/✗ 确认条
  -- ★★★★★ 2026-10-04 **收窄成"图上那行文字"的范围**（原来 24,22,300×66 会连带盖住深色方块）：
  --   画布 x 134..347、y 64..84 → 设计空间 x 161..416、y 77..101。
  --   理由见 `action.back` 那段注释：不收窄的话，它和 `hex.back`、以及**跟随出现的 ✓/✗ 确认卡**
  --   三者位置打架，确认卡会被压住点不到。
  back_btn = { x = 161, y = 77, w = 255, h = 28 },
  confirm  = { x = 344, y = 22, size = 66, gap = 14 },
}

M.EFFECTS = {
  SELECT    = "sel_pop_glow",
  PLACE     = "pop_tile",
  NOTE      = "note_pop",
  XMARK     = "pulse",
  VICTIM    = "portrait_slide_up",
  ERASE     = "vanish",
  UNDO      = "undo_flash",
  SUBMIT    = "submit_nudge",
  SOLVED    = "solved_flash",
  CLUE_IN   = "clue_box_pop",
  FAIL      = "shake",
  ROOMWALL  = "roomwall",
}

-- 开屏教程（5 页：怎么破案 / 每行每列一人 / beside 的含义 / 单击双击的区别 / 提交判题）
M.INTRO = {
  { title = "怎么破案",        body = "读线索，把每个角色放到正确的位置上。\n摆满之后，与受害者单独共处一室的人就是凶手。" },
  { title = "每行每列只有一人", body = "每一行、每一列都恰好只能站一个人（受害者也算一个人）。" },
  { title = "“旁边”是什么意思", body = "旁边 = 上下左右四邻，而且必须在同一个房间里。\n隔着墙的不算旁边。" },
  { title = "单击写字，双击放置", body = "单击格子只会留下一个铅笔小字（笔记）。\n在同一格连着点两下，才会把人放上去。" },
  { title = "提交判题",        body = "摆满后点「提交」校验摆位，通过后即可指认凶手。\n拿不准的位置可以先打 X 标记。" },
}

----------------------------------------------------------------------------

local Controller = {}
Controller.__index = Controller
M.Controller = Controller

function M.new(core, opts)
  opts = opts or {}
  local self = setmetatable({}, Controller)
  self.core = core
  self.opts = opts
  self.effects = {}
  self.dirty = true
  self.toast = nil
  -- ★ A8：提示语的**截止时刻**（绝对值，和 `self.now` 同一根时间轴）。
  --   千星**没有客户端定时器 API** ⇒ 就用 `tick` 里那根本来就在累加的 `self.now`
  --   （`main.lua` 的 `on_update` 每帧调 `controller:tick(dt)`，与屏幕无关）。
  self.toast_until = nil
  self.now = 0
  self.modal = nil          -- nil | {kind="accuse"} | {kind="result",win=bool,message=} | {kind="howto"} | {kind="intro",page=n}
  -- ★★★ 2026-09-29：屏幕状态（"home" 主页 / "select" 选关 / nil = 在关卡里）。
  --   与 `modal` 的区别：modal 是"浮在关卡上的弹窗"，屏幕是**整屏**的。
  --   控件已在 .gil 里（tools/gil/gen_home.mjs），脚本只切 visible + 写文字。
  self.screen = opts.screen
  self.intro_page = opts.skip_intro and (#M.INTRO + 1) or 1
  self.share_code = nil
  self._created = {}
  self._props = {}
  self._gesture_snapshot = nil
  self.debug = opts.debug == true
  -- 键盘光标（PC）：方向键移动它，空格/回车对它生效。
  -- kb_active 只有真的按过方向键才置 true，纯鼠标玩家不会看到多余高亮。
  self.kb = { r = 1, c = 1 }
  self.kb_active = false
  return self
end

function Controller:fx(target, kind, params)
  local e = { target = target, kind = kind }
  if params then for k, v in pairs(params) do e[k] = v end end
  self.effects[#self.effects + 1] = e
  return e
end

-- ★★★★★ 2026-10-07 **笔记：集合 → 数组** ✗✓（用户报"字母没出现"的根因 ✓）
--
--   真机探针（权威）✓：★ `★ 诊断NOTE2：单击(1,1) … 返回 ok=true  why=nil  该格笔记={V}` ✓
--     ⇒ ★ **核心写进去了** ✓ ⇒ ★ 问题在【下发/绘制】这一侧 ✓
--   ★ 根因 ✓：适配器的 `key == "notes"` 分支是 `table.concat(value or {}, " ")` ✓
--     而核心 `notes[r][c]` 的形状是**集合**（`{[id] = true}` ✓ **非连续整数键** ✗）⇒
--     `table.concat` 只吃数组 ⇒ 得到**空串** ⇒ 适配器判定"没笔记" ⇒ `SetVisible(false)` ✗✗
--   ⇒ ★★ **笔记一直是"写进去了、也一直没画出来"** ✓ 与用户看到的现象完全一致 ✓
--   ★ 转换后：★ **id 本身就是徽章字母**（真机日志 `who=V` / `who=D` ✓）⇒ 直接当字母用 ✓
--     （★ 排序只为稳定 ✓ 集合遍历顺序不定，不排的话文字每帧可能抖动 ✓）
local function note_list_of(set)
  if type(set) ~= "table" then return nil end
  local out = {}
  for kk, vv in pairs(set) do if vv then out[#out + 1] = tostring(kk) end end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end
function Controller:cell_id(r, c) return string.format("cell.%d.%d", r, c) end

-- 结案判定：盗窃者 + 有没有同伙（+ 同伙是谁）
function Controller:finish_accuse(thief, has_acc, acc)
  local core = self.core
  local res
  if has_acc == nil then
    res = core:accuse(thief)
  else
    res = core:accuse_verdict(thief, has_acc, acc)
  end
  self.toast = res.message
  self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
  if res.solved then
    self.modal = { kind = "result", win = true, message = res.message }
    self:fx("modal", M.EFFECTS.SOLVED)
    -- 揭示：受害者头像从下往上顶出来。
    -- 受害者**也在头像卡列里**（core:view().tray 里 is_victim=true 的那张），
    -- 所以这个控件一定存在，不需要额外建控件。
    local vid = core.victim_id
    if vid ~= nil then self:fx("tray." .. tostring(vid), M.EFFECTS.VICTIM) end
    if self.opts.on_solved then self.opts.on_solved(core:view()) end
  else
    self.modal = nil
    self:fx("modal", M.EFFECTS.FAIL)
  end
  self.dirty = true
  return res
end

--------------------------------------------------------------------------------
-- ★★★★★ 2026-10-02 **✓/✗ 确认流程**（用户定稿，参考 `参考2-图标与确认键.jpg`）
--
--   参考图里的用法：点「返回菜单」这类**不可逆**的操作 ⇒ 旁边冒出 ✓ 和 ✗
--   ⇒ 点 ✓ 才真的执行，点 ✗ 就当没点过。
--
--   三个动作走这条路：`back`（返回菜单）/ `submit`（提交）/ `restart`（重置关卡）。
--   「撤销 / 放大镜」不需要确认 —— 它们是可逆/无副作用的。
--
--   ⚠️ 控件 `confirm.ok` / `confirm.no` 在 `build_layout` 里**建出来就是 visible=false**，
--      每帧由 `sync_confirm()` 按 `self.pending` 决定显隐。
--      为什么不直接 `SetVisible`：这个项目里"控件树是每帧重建的"，
--      布局层给的是初始值，跨帧状态必须由控制器每帧重新下发（和 `pos_runtime` 同理）。

--- 按 `self.pending` 同步 ✓/✗ 的显隐。
function Controller:sync_confirm()
  local want = (self.pending ~= nil)
  self._confirm_shown = want
  self.dirty = true
  return want
end

--- 真正执行"提交"。逻辑与原来的 `submit` 分支一字不差，只是**挪进来**，
--- 让"要不要先确认"和"确认后干什么"分开。
function Controller:do_submit()
  local core = self.core
  if core == nil or core.submit == nil then return end
  local res = core:submit()
  -- ★ 2026-10-04 **反馈目标改成 `hex.submit`** —— `action.submit` 那批旧文字键已从计划里删掉，
  --   特效打在已不存在的控件上 = **点了没有任何视觉反馈**（用户反馈的正是这条）。
  --   七个图标改用「格子模板」后是**真正可点的控件**，`fx()` 的动画就能落在它们身上。
  self:fx("hex.submit", M.EFFECTS.SUBMIT)
  -- 规格 5.3：提交只给硬约束反馈，不揭晓任何线索层面的对错（连条数都不说）
  self.toast = res and res.message or nil
  self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：同上（res 为 nil 时设了也无害 —— tick 先看 toast）
  if res ~= nil and res.ok then
    self.modal = { kind = "accuse_thief" }
  end
  self.dirty = true
end

--- 真正执行"重置关卡"。
function Controller:do_restart()
  local core = self.core
  if core ~= nil and core.reset ~= nil then core:reset() end
  self.modal = nil
  self.toast = nil
  self.toast_until = nil    -- ★ A8：清提示语时把截止时刻一起清掉（别留一个未来的时刻）
  self.dirty = true
end

--- 真正执行"返回菜单"（= 回选关界面，原作循环是"选关 → 关卡 → 退出 → 选关"）。
function Controller:do_back()
  self.screen = "select"
  self.modal = nil
  self.dirty = true
  if self.opts.on_back then self.opts.on_back() end
end

function Controller:format_time(sec)
  sec = math.max(0, math.floor(sec or 0))
  return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

----------------------------------------------------------------------------
-- 输入路由
--   事件格式：
--     {action="suspect", id=}
--     {action="click",     r=, c=}      单击格子（单击=笔记，双击=放置，由本层判定）
--     {action="cell_right",r=, c=}      右键 → X（可选绑定；默认用 X 工具按钮）
--     {action="gesture_begin"}          手指/指针按下（用于双指回滚）
--     {action="gesture_rollback"}       双指 → 回滚
--     {action="tool", mode="place|x|eraser|note"}   双击 eraser 工具 = 清空全盘
--     {action="undo"|"redo"|"submit"|"hint"|"reveal"|"restart"|"share"|"howto"|"back"}
--     {action="accuse", id=} | {action="close_modal"} | {action="intro_next"} | {action="intro_skip"}
--
--   为什么要双击：官方客户端脚本**只有 CursorClick，没有长按事件**，
--   与其自己造长按阈值，不如用「单击=笔记 / 双击=放置」这一套更明确的手感。
----------------------------------------------------------------------------

-- 双击窗口（秒）：两次单击落在这个窗口内、且在同一格 → 判定为双击
local DOUBLE_CLICK_SECONDS = 0.35

-- 长按窗口（秒）：按住不放超过这么久、且期间基本没移动 → 判定为长按
--
-- 为什么要它：官方**没有长按事件**，所以我们最初用"双击=放置"替代。
-- 但移动端双击不友好（要担心系统双击缩放、手指也容易抖），
-- 所以从 CursorDown/CursorUp 自己合成一个长按 —— **两种手势都触发同一个"放置"**：
--   · PC 键鼠：双击 / 长按按鼠标左键，随你喜欢
--   · 移动端：长按（更好按）
local LONG_PRESS_SECONDS = 0.45
-- 按下到抬起之间允许的位移（画布像素）。超过就当成"划动"，不算点/长按。
local TAP_MOVE_TOLERANCE = 24

function Controller:snapshot()
  self._gesture_snapshot = self.core:serialize()
end

-- 记录一次"某个键"的点击，返回这次是否构成双击
function Controller:is_double(key)
  self.now = self.now or 0
  local last = self.last_key
  if last and last.key == key and (self.now - last.t) <= DOUBLE_CLICK_SECONDS then
    self.last_key = nil
    return true
  end
  self.last_key = { key = key, t = self.now }
  return false
end

-- ★★ 「为什么点了没反应」必须说出来。
--
-- 背景：`core:tap_cell()` / `core:hold_cell()` 失败时**返回第二个值就是原因**
-- （例如「先点一个头像」「这个格子站不了人」「这格已经有人了」），
-- 但控制器原来把那第二个值**直接丢掉了** —— 于是玩家/开发者看到的是"点击无反馈"，
-- 完全不知道差在哪。真机 2026-09-27 05:59 就是这么卡住的：
-- 点了 8 次、日志只说"收到点击"，而真正的原因是头像卡容器还没建、选不了人。
--
-- 现在：每个不同的原因**最多打 3 次**（避免刷屏），并且带上格子坐标。
-- 这些是**正常的玩法提示**（不是错误），所以走 print 而不是 printerr。
function Controller:_refuse(r, c, why)
  if why == nil then return end
  self._refuse_seen = self._refuse_seen or {}
  local n = self._refuse_seen[why] or 0
  if n >= 3 then return end
  self._refuse_seen[why] = n + 1
  if print then
    -- ★ 2026-09-28：把**当前工具模式**一起打出来。
    --
    -- 起因：用户报"没有看到任何 X 图标"。而 `tap_cell` 里 X 模式是**在选中检查之前**
    -- 就返回的（`if self.mode == MODE_X then return toggle_x(...) end`），
    -- 所以日志里刷"先点一个头像"就说明**模式根本没切到 X** —— 问题在工具按钮那一步，
    -- 不在 X 的画法。没有这行模式，就分不清"X 没画出来"和"X 没被设置"。
    print("[murdoku] 点 (第" .. tostring(r) .. "行 第" .. tostring(c) .. "列) 没生效："
      .. tostring(why) .. "  当前工具=" .. tostring(self.core and self.core.mode)
      .. "  已选=" .. tostring(self.core and self.core.selected)
      .. "（同类提示最多打 3 次）")
  end
end

-- 把挂起的单击落成铅笔笔记（等过双击窗口才执行，免得抢在第二次点击前面）
function Controller:flush_pending_note()

  local p = self.pending_click
  if p == nil then return end
  if (self.now or 0) - p.t < DOUBLE_CLICK_SECONDS then return end
  self.pending_click = nil
  local ok, why = self.core:tap_cell(p.r, p.c)

  if ok then
    self:fx(self:cell_id(p.r, p.c), M.EFFECTS.NOTE)
    self.dirty = true
  else
    self:_refuse(p.r, p.c, why)
  end
end

-- 把当前选中的人放到 (r,c)（双击 / 长按 / 键盘回车 共用这一条路径）
function Controller:do_place(r, c)
  local core = self.core
  self.last_click = nil
  self.pending_click = nil
  local who = core.selected
  -- ★ 2026-10-07 分辨日志：★ 长按到底走的是"正式放置"吗 ✓ 核心前后状态对不对 ✓
  local _sel_before = core.selected
  local _notes_before = 0
  pcall(function()
    for rr, row in pairs(core.notes or {}) do for cc, set in pairs(row) do
      for id, v in pairs(set) do if v then _notes_before = _notes_before + 1 end end
    end end
  end)
  local ok, why = core:hold_cell(r, c)
  if ok then
    local _notes_after, _n2 = 0, 0
    pcall(function()
      for rr, row in pairs(core.notes or {}) do for cc, set in pairs(row) do
        for id, v in pairs(set) do if v then _notes_after = _notes_after + 1 end end
      end end
    end)
    if (_sel_before ~= nil) and core.placed and core.placed[_sel_before] then _n2 = 1 end
    print("[murdoku] ★ 放置分辨：走的=【正式放置 hold_cell】 人=" .. tostring(_sel_before)
      .. "  笔记 " .. tostring(_notes_before) .. " ⇒ " .. tostring(_notes_after)
      .. "  放后选中=" .. tostring(core.selected) .. "  placed=" .. tostring(_n2 == 1))
  end
  -- ★★★★★ 2026-10-07 **正式放置后【撤掉线索卡的选中高亮】** ✗✓
  --   ★ 真机证据 ✓：数据层已经清了 ✓（`放后选中=nil` ✓）★ 但画面上的高亮还留着 ✗
  --     ⇒ ★ 看起来就是"没取消选中" ✓
  --   ★ 原因 ✓：★ 高亮是我在点卡片时**手动染**上去的（`_grid_focus_*`）✓
  --     而 `selected` 被清时**没人撤那个色** ✗ ⇒ ★ 这里把两套状态一起清 ✓
  --   ⚠️ 只在**正式放置**里做 ✓（★ 预放置按设计**保留选中** ✓ 高亮该留着 ✓）
  local _pi, _pix, _ppx = self._grid_focus_item, self._grid_focus_idx, self._grid_focus_pos
  if _pi ~= nil then
    local _pc = nil
    pcall(function() _pc = self:_grid_item_child_cached(_pi, _pix or 0, _ppx or 0, "backrop1") end)
    if _pc ~= nil and self._grid_focus_orig ~= nil then
      pcall(function() _pc.imageColor = self._grid_focus_orig end)
    end
    self._grid_focus_item, self._grid_focus_orig = nil, nil
  end
  self.focused_clue = nil
  self.dirty = true
  if ok then
    -- ★★★★★ 2026-10-07 **放置后强制重填线索卡** ✗✓（灰白卡的关键 ✓）
    --   ★ 真机证据 ✓：★ `★ 灰白诊断：pos=3 … ★ id=V`（★ id 已经对了 ✓ 但 `placed=false` ✓）
    --     ⇒ ★ 那几行是**开局填充**跑的 ✓ ⇒ ★ **放置之后卡片没有重新填充** ✗
    --       ⇒ ★ 灰白永远停留在"放置前"的状态 ✓✓
    --   ★ 机制 ✓：★ 列表项的填充由 `RefreshItems` 回调驱动 ✓
    --     ★ 而它有个**签名门**（`_grid_sig`）✓ ⇒ ★ 签名没变就不再重填 ✓
    --   ⇒ ★ 这里**清掉签名** ✓ ⇒ 下一帧网格同步会重新填一遍 ✓ ⇒ **灰白跟着出来** ✓✓
    self._grid_sig = nil
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end

-- ★★ 2026-09-28（用户设计）：**双击 = 预放置**。
--
-- 与 `do_place`（正式放置，走 `core:hold_cell`）的区别全在 core 里：
--   预放置 → 只标同行同列 ✗，**不擦笔记、不取消选中、不记 placed**
--   正式放置 → 擦该人物的笔记 + 记 placed（之后不许再给他打笔记）+ 取消选中
-- 反馈动效两者相同（`pop_tile`），因为"有没有真的放上去"要靠盘面看，不靠动效区分。
function Controller:do_pre_place(r, c)
  local core = self.core
  self.last_click = nil
  self.pending_click = nil
  local who = core.selected
  -- ★ 2026-10-07 分辨日志：★ 双击走的是"预放置"吗 ✓ 选中该保留 ✓
  local _sel_b2 = core.selected
  local ok, why = core:pre_place(r, c)
  if ok then
    print("[murdoku] ★ 放置分辨：走的=【预放置 pre_place】 人=" .. tostring(_sel_b2)
      .. "  放后选中=" .. tostring(core.selected) .. "（★ 应仍是 " .. tostring(_sel_b2) .. " ✓）")
  end
  if ok then
    -- ★★★★★ 2026-10-07 **放置后强制重填线索卡** ✗✓（灰白卡的关键 ✓）
    --   ★ 真机证据 ✓：★ `★ 灰白诊断：pos=3 … ★ id=V`（★ id 已经对了 ✓ 但 `placed=false` ✓）
    --     ⇒ ★ 那几行是**开局填充**跑的 ✓ ⇒ ★ **放置之后卡片没有重新填充** ✗
    --       ⇒ ★ 灰白永远停留在"放置前"的状态 ✓✓
    --   ★ 机制 ✓：★ 列表项的填充由 `RefreshItems` 回调驱动 ✓
    --     ★ 而它有个**签名门**（`_grid_sig`）✓ ⇒ ★ 签名没变就不再重填 ✓
    --   ⇒ ★ 这里**清掉签名** ✓ ⇒ 下一帧网格同步会重新填一遍 ✓ ⇒ **灰白跟着出来** ✓✓
    self._grid_sig = nil
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end

-- ── 按下 / 抬起：自己合成"长按" ──────────────────────────────────────────
-- 返回 true = 这次抬起已经被当成"长按"处理掉了（后续那个 CursorClick 要忽略）
function Controller:on_cell_down(r, c, x, y)
  self._press = { r = r, c = c, t = self.now or 0, x = x, y = y }
  return false
end

function Controller:on_cell_up(r, c, x, y)
  local p = self._press
  self._press = nil
  if p == nil then return false end
  if p.r ~= r or p.c ~= c then return false end          -- 按在别处，不算
  local dt = (self.now or 0) - p.t
  if dt < LONG_PRESS_SECONDS then return false end         -- 还不够长
  -- 位移太大 = 划动，不算长按
  if p.x ~= nil and x ~= nil then
    local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
    if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then return false end
  end
  local ok = self:do_place(r, c)
  print("[murdoku] ★ 放置分辨：抬起被判定为【长按】✓ 时长=" .. string.format("%.2f", dt))
  if ok then
    self._suppress_click = true     -- 紧跟着的那个 CursorClick 不要重复处理
  end
  return ok
end

-- 按住期间移动了（CursorDrag）：超过容差就**当场**放弃这次长按判定。
-- 为什么不等抬起再判：抬起才判的话，玩家按住想微调位置的那 0.5 秒里
-- 松手就会落子，移动端上太容易误触。这里只是提前撤销，不改别的状态。
-- x/y 取不到时**什么都不做**（宁可退回"抬起时判断"，也不要误取消）。
function Controller:on_cell_drag(r, c, x, y)
  local p = self._press
  if p == nil then return false end
  if p.x == nil or x == nil then return false end
  local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
  if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then
    self._press = nil
    return true
  end
  return false
end

-- 棋盘格被单击：单击=笔记 / 双击=放置；已放置格、X 模式、橡皮擦模式、只写笔记模式都立即生效
function Controller:on_cell_click(r, c)
  -- ★ 2026-10-05 **没带坐标的点击：安静地不做任何事**（原来会崩）。
  --
  --   两处独立实测都发现 `on_cell_click(nil, nil)` 会抛异常 ——
  --   就是下面那句 `core.grid[r][c]`（`ui_controller.lua:578` 那一行）直接炸。
  --
  --   什么时候会进来 nil：适配层的 `_fire` 走兜底事件 `{ action = "click" }` 时
  --   （`live_event()` 拿不到节点事件），`r` / `c` 就都是 nil。
  --   ⇒ 这不是"错"，只是**这次点击本来就没落在任何格子上** —— 什么都不做才是对的。
  --   ⚠️ 必须放在**读 `core.grid` 之前**：放在后面就等于没放。
  if r == nil or c == nil then return end
  -- ★★★★★ 2026-10-07 **吃掉"点线索卡"带出来的那一次格子点击** ✗✓（治穿透 ✓）
  --   ★ 网格视窗不消费点击 ⇒ ★ 同一次指针事件会**先给列表项、再给棋盘** ✓
  --     ⇒ ★ 点卡片就会顺手点一下格子 ✓（真机日志两次可见 ✓ 见 `_on_grid_item_click` 处注释 ✓）
  --   ★ 这里用"刚点过卡片"的时间戳挡掉 ✓ 窗口 0.35 秒（= 双击窗口 ✓）
  --     ⚠️ 只挡**单击**这一路 ✓ 不影响双击放置/长按 ✓（它们走 down/up 判定，不经过这里 ✓）
  if self._grid_click_t ~= nil and (self.now or 0) - self._grid_click_t <= 0.35 then
    return
  end
  local core = self.core
  self.now = self.now or 0
  -- ★★★★★ 2026-10-07 **吃掉"点线索卡"带出来的那一次格子点击** ✗✓（治穿透 ✓）
  --   ★ 网格视窗不消费点击 ⇒ ★ 同一次指针事件**先给列表项、再给棋盘** ✓
  --     ⇒ ★ 点卡片就会顺手点一下格子 ✓（真机日志两轮都可见 ✓）
  --   ★ 这里用"刚点过卡片"的时间戳挡掉 ✓ 窗口 0.35 秒（= 双击窗口 ✓）
  --     ⚠️ 只挡**单击**这一路 ✓ 双击/长按走 down-up 判定，不经过这里 ✓ ⇒ 不受影响 ✓
  if self._grid_click_t ~= nil and (self.now or 0) - self._grid_click_t <= 0.35 then
    return
  end
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode

  -- 双击 → **预放置**（★ 2026-09-28 用户设计：双击=预放置，长按=正式放置）
  --
  -- ★★ 2026-09-29 重写（用户报「没选标记按钮、直接单击棋盘做 ✗ 有明显延迟」）：
  --
  --   旧流程：`place` 模式下单击空格会**先挂起 0.35 秒**（`pending_click`），
  --   等过了双击窗口才落成动作 —— 因为要等一下看有没有第二击。
  --   玩家体感就是"点了没反应，过一会儿才出现"。
  --   而**取消工具栏三个按钮之后，单击=切 ✗ 成了最高频的动作**，这 0.35 秒完全不能忍。
  --
  --   新流程：**第一击立即生效**；若真来了第二击，**先把第一击撤销掉**再做预放置。
  --   撤销方式按"第一击到底做了什么"分派（记在 `last_click.did`）：
  --     · `"x"`   → 再切一次 ✗ 就回到原状
  --     · `"pre"` → 撤销那次预放置
  --   于是**单击零延迟，双击行为与原来完全一致**。
  if (not occupied) and mode == "place" then
    local last = self.last_click
    if last and last.r == r and last.c == c and (self.now - last.t) <= DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      if last.did == "x" then
        core:toggle_x(r, c)             -- 撤销第一击切出来的 ✗
        self.dirty = true
      elseif last.did == "pre" then
        core:undo()                     -- 撤销第一击的预放置
        self.dirty = true
      end
      self:do_pre_place(r, c)
      return
    end
  end

  -- ★★ 单击**一律立即生效**（不再有任何"挂起等双击窗口"）。
  --   挂起是延迟的唯一来源；现在第一击马上做，双击时再撤销它（见函数开头那段）。
  self.pending_click = nil
  local had = core.grid[r][c]
  local had_selected = core.selected          -- 要在 tap_cell **之前**取：它会改选中态
  local ok, why = core:tap_cell(r, c)
  -- ★ 2026-10-07 一次性诊断（★ 这次插在赋值【之后】✓ 上一版插在前面，打的是全局 nil ✗）
  --   核心 `tap_cell` 在 **place 模式**就已经是：★ 已有人 ⇒ 拿起 ✓ 没选人 ⇒ 切 ✗ ✓
  --     ★ **选了人 + 空格 ⇒ `toggle_note(selected)` = 铅笔笔记** ✓（`murdoku_core.lua:1910` ✓）
  --   ⇒ **不需要切模式** ✓ 所以这一段只做观测 ✓
  if (self._diag_tap2 or 0) < 6 then
    self._diag_tap2 = (self._diag_tap2 or 0) + 1
    local nt, sel = "?", "?"
    pcall(function()
      sel = tostring(core.selected)
      local row = core.notes and core.notes[r]
      local celln = row and row[c]
      if type(celln) == "table" then
        local ks = {}
        for k, v in pairs(celln) do if v then ks[#ks + 1] = tostring(k) end end
        nt = "{" .. table.concat(ks, ",") .. "}"
      else
        nt = tostring(celln)
      end
    end)
    print("[murdoku] ★ 诊断NOTE2：单击(" .. tostring(r) .. "," .. tostring(c) .. ")  occupied="
      .. tostring(occupied) .. "  selected=" .. sel .. "  返回 ok=" .. tostring(ok)
      .. " why=" .. tostring(why) .. "  该格笔记=" .. nt)
  end
  if ok then
    if had then
      -- ★ 2026-09-27 修（用户报"双击格子有时会导致其消失"）：
      --   原来把 `vanish`（缩放 1.00 → **0.00**）作用在**格子本身**上。
      --   双击放置后若系统多派发一次点击（或玩家连点三下），那一次落在"已占格"上
      --   → 拿起棋子 + **把整个格子缩到 0** → 看上去"格子消失了"。
      --   改成作用在 `face` 子控件上：拿起棋子的反馈照样有，**格子本身不缩**。
      --   （适配器另有"动完还原姿态"的兜底。）
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    -- 记下这一击做了什么，供"第二击撤销第一击"用
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = self.now,
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
    -- ★★★★★ 2026-10-07 **失败也要记下这一击** ✗✓（"不能以预放置挪位"的真因 ✓）
    --   ★ 真机证据 ✓：★ 正式放置过 V 之后再双击别的格子 ⇒ 日志里**两次都是单击**（`诊断NOTE2`）✗
    --     ⇒ ★ 说明**双击没被识别** ✓
    --   ★ 原因 ✓：★ 第一击 `ok=false`（★ 笔记被"这个人已正式放置"规则拒 ✓）
    --     ⇒ ★ 而 `last_click` **只在 `ok == true` 时记录** ✗
    --       ⇒ ★ 第二击来的时候 `last = nil` ⇒ ★ **永远判不出双击** ✗✗
    --         ⇒ ★ **`do_pre_place` 永不触发** ⇒ ★ **"选中之后想双击挪位"被拦** ✓✓
    --   ★ 修法 ✓：★ **失败也记** ✓ 且 `did = "none"` ⇒
    --     ★ 第二击**不会去"撤销第一击"**（★ 什么都没做 ✓ 无需撤 ✓）★ 只做预放置 ✓✓
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = self.now, did = "none" }
    end
    self:_refuse(r, c, why)
  end
end

-- ── 键盘（PC，可选）─────────────────────────────────────────────────────
-- 键盘光标：方向键移动一格，写笔记 / 放置 / 换工具 / 撤销重做提示。
-- `kb_active` 只在真的用过方向键之后才为 true —— 纯鼠标玩家不会看到一个
-- 莫名其妙的选中框。
--
-- ⚠️⚠️ **官方键事件不是物理键码，而是语义事件**（2026-09-26 真机日志查出来的）：
--   注册用的是 `ctrl:AddKeyEventListener(Enum.KeyEventType.<名字>, cb)`，
--   而 `Enum.KeyEventType` 是「设备 + 语义 + 按下/抬起」的组合，共 164 项，例如
--       KeyboardCraftspersonKey1Down  = 键鼠：奇匠按键1（按下），默认物理键 `1`
--       KeyboardCraftspersonKey36Down = 键鼠：奇匠按键36（按下），默认物理键 `↑`
--       KeyboardInteractKeyDown       = 键鼠：拾取/交互（按下），默认物理键 `F`
--       KeyboardJumpKeyDown           = 键鼠：跳跃（按下），默认物理键 `Space`
--   **没有 `Return` / `Enter` / `Escape` 这三种事件**，所以那两个功能换绑到别的键。
--   （`Enum.KeyboardKeyCode` 是**另一个东西** —— 它只给「按键提示控件」显示用。）
--
--   另外「奇匠按键」是**可被玩家重映射的槽位**，上面那些物理键只是**默认值**，
--   所以图例里要写成语义说法，不能假定玩家按的一定是 ↑↓←→。
--
--   本表：`Enum.KeyEventType` 名字 → 本工程的内部动作名。
local KB_ACTIONS = {
  -- 方向（奇匠按键36..39，默认 ↑ ↓ ← →）
  KeyboardCraftspersonKey36Down = "up",
  KeyboardCraftspersonKey37Down = "down",
  KeyboardCraftspersonKey38Down = "left",
  KeyboardCraftspersonKey39Down = "right",

  -- 选角色（奇匠按键1..10，默认 1..9 与 0）
  KeyboardCraftspersonKey1Down  = "pick1",
  KeyboardCraftspersonKey2Down  = "pick2",
  KeyboardCraftspersonKey3Down  = "pick3",
  KeyboardCraftspersonKey4Down  = "pick4",
  KeyboardCraftspersonKey5Down  = "pick5",
  KeyboardCraftspersonKey6Down  = "pick6",
  KeyboardCraftspersonKey7Down  = "pick7",
  KeyboardCraftspersonKey8Down  = "pick8",
  KeyboardCraftspersonKey9Down  = "pick9",
  KeyboardCraftspersonKey10Down = "pick10",

  -- 主要动作
  KeyboardInteractKeyDown       = "place",   -- 拾取/交互（默认 F）= 放置
  KeyboardJumpKeyDown           = "note",    -- 跳跃（默认 Space）= 铅笔笔记
  KeyboardDropKeyDown           = "xmark",   -- 落下（默认 X）= 划掉这格
  KeyboardCraftspersonKey42Down = "back",     -- 奇匠按键42（默认 Backspace）= 关弹窗/选关

  -- 工具与命令
  KeyboardOpenShortcutWheelKeyDown = "tool",    -- 呼出快捷轮盘（默认 Tab）= 循环换工具
  KeyboardCharacterSkill1KeyDown   = "eraser",  -- 角色技能1（默认 E）= 橡皮擦
  KeyboardCharacterSkill3KeyDown   = "submit",  -- 角色技能3（默认 R）= 提交
  KeyboardCraftspersonKey12Down    = "undo",    -- 默认 Z
  KeyboardCraftspersonKey13Down    = "redo",    -- 默认 Y
  KeyboardCraftspersonKey15Down    = "hint",    -- 默认 H
}

local KB_DELTA = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }

local KB_TOOL_CYCLE = { "place", "note", "x", "eraser" }

function Controller:kb_move(dr, dc)
  local kb = self.kb or { r = 1, c = 1 }
  local r = math.min(self.core.rows, math.max(1, kb.r + dr))
  local c = math.min(self.core.cols, math.max(1, kb.c + dc))
  if r ~= kb.r or c ~= kb.c or not self.kb_active then
    self.kb_active = true
    self.dirty = true
  end
  self.kb = { r = r, c = c }
end

-- `event.key` 是 `Enum.KeyEventType` 的**名字**（由适配层原样带过来）
local function kb_action_of(event)
  return KB_ACTIONS[tostring(event.key or "")]
end

-- 返回 true = 这个键被消费掉了
function Controller:on_key(event)
  local core = self.core
  local act = kb_action_of(event)
  if act == nil then return false end

  -- 方向：移动键盘光标
  local d = KB_DELTA[act]
  if d ~= nil then
    self:kb_move(d[1], d[2])
    return true
  end

  -- 选第 i 个角色
  local n = act:match("^pick(%d+)$")
  if n ~= nil then
    local i = tonumber(n)
    local vm = core:view()
    if i >= 1 and i <= #vm.tray then
      self:on_input({ action = "suspect", id = vm.tray[i].id })
      return true
    end
    return false
  end

  if act == "note" then
    -- 在光标格写/删笔记
    local kb = self.kb
    if kb ~= nil then
      self.kb_active = true
      self:on_cell_click(kb.r, kb.c)
      self.pending_click = { r = kb.r, c = kb.c, t = (self.now or 0) - DOUBLE_CLICK_SECONDS - 1 }
      self:flush_pending_note()
      return true
    end
    return false
  end

  if act == "place" then
    local kb = self.kb
    if kb ~= nil then
      self.kb_active = true
      self:do_place(kb.r, kb.c)
      return true
    end
    return false
  end

  if act == "tool" then
    local mode = core.mode or "place"
    local idx = 1
    for i = 1, #KB_TOOL_CYCLE do if KB_TOOL_CYCLE[i] == mode then idx = i end end
    self:on_input({ action = "tool", mode = KB_TOOL_CYCLE[idx % #KB_TOOL_CYCLE + 1] })
    return true
  end

  if act == "xmark"  then self:on_input({ action = "tool", mode = "x" });      return true end
  if act == "eraser" then self:on_input({ action = "tool", mode = "eraser" }); return true end
  if act == "undo"   then self:on_input({ action = "undo" });                  return true end
  if act == "redo"   then self:on_input({ action = "redo" });                  return true end
  if act == "hint"   then self:on_input({ action = "hint" });                  return true end
  if act == "submit" then self:on_input({ action = "submit" });                return true end

  if act == "back" then
    -- 官方**没有** Escape / Return 事件，所以"关弹窗 / 选关"改绑 Backspace
    if self.modal ~= nil then self:on_input({ action = "close_modal" })
    else self:on_input({ action = "level_list" }) end
    return true
  end

  return false
end

function Controller:on_input(event)
  local core = self.core
  local a = event.action

  -- ── 输入阶段（PC 键鼠 / 移动端触碰共用同一套）─────────────────────────
  if event.phase == "key" then
    self:on_key(event)
    return self.effects
  end
  if event.phase == "down" then
    if a == "click" then self:on_cell_down(event.r, event.c, event.x, event.y) end
    return self.effects
  end
  if event.phase == "up" then
    if a == "click" then self:on_cell_up(event.r, event.c, event.x, event.y) end
    return self.effects
  end
  if event.phase == "drag" then
    if a == "click" then self:on_cell_drag(event.r, event.c, event.x, event.y) end
    return self.effects
  end

  if a == "suspect" then
    core:tap_suspect(event.id)
    local vm = core:view()
    if vm.hud.selected == event.id then
      self:fx("tray." .. tostring(event.id), M.EFFECTS.SELECT)
    end
    if self.modal and self.modal.kind == "accuse" then
      self.modal = { kind = "accuse" }   -- 重画指认面板
    end

  elseif a == "gesture_begin" then
    self:snapshot()

  elseif a == "gesture_rollback" then
    if self._gesture_snapshot then
      core:deserialize(self._gesture_snapshot)
      self.toast = "已回滚本次操作"
      self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
      self:fx("board", M.EFFECTS.UNDO)
    end

  elseif a == "click" then
    -- 刚被"长按"处理过的那一次点击要忽略掉，否则同一格会被放两次
    if self._suppress_click then
      self._suppress_click = nil
    else
      self:on_cell_click(event.r, event.c)
    end

  elseif a == "cell_right" then
    if core:toggle_x(event.r, event.c) then
      self:fx(self:cell_id(event.r, event.c), M.EFFECTS.XMARK)
    end

  elseif a == "tool" then
    -- ★ 2026-09-28：工具切换必须留下痕迹。
    --   用户报"没有看到任何 X 图标"，而 X 模式在 tap_cell 里是**优先于选中检查**的 ——
    --   所以要么"X 工具按钮没生效"（模式没切），要么"切了但 X 没画出来"。
    --   把每次切换打出来（最多 12 次），这两者就能一眼分开。
    if print then
      self._tool_log = (self._tool_log or 0) + 1
      if self._tool_log <= 12 then
        print("[murdoku] 切换工具 → " .. tostring(event.mode)
          .. "（之前是 " .. tostring(core.mode) .. "）")
      end
    end
    core:set_mode(event.mode)

  -- ★★★★★ 2026-10-02 **✓/✗ 确认状态机**（用户定稿，参考 `参考2-图标与确认键.jpg`）
  --
  --   规则：点「返回菜单 / 提交 / 重置关卡」中**任一个** ⇒ **不立刻执行**，
  --         而是把动作存进 `self.pending` 并显示 ✓/✗；
  --         点 ✓ = 执行，点 ✗ = 取消。
  --         「撤销 / 放大镜」**不需要确认**，直接执行。
  --
  --   为什么这么做：这三个都是**不可逆**的（回菜单、交卷、清空整局），
  --   参考图里也是"点一下先问、再执行"的两段式。
  elseif a == "back_confirm" then
    -- ★ 2026-10-08 **甲案**：★ 用四键弹窗**取代** ✓/✗ 确认卡（★ 262 的原始意图 ✓ 用户拍板 ✓）
    self.modal = { kind = "exit_menu" }   -- ★ 开四键弹窗 ✓（取代 pending 确认卡 ✓）
    self.dirty = true
    self:sync_confirm()
    -- ★ 2026-10-04 **按下就给反馈**（用户反馈"点击动画只有提示有"）：
    --   这三个键原来只设 `pending`、不播动画 ⇒ 点了像没反应，要等 ✓ 才有动静。
    --   真正的执行动画仍在 `confirm_yes` → `do_submit()` 那条路上播。
    self:fx("hex.back", M.EFFECTS.SELECT)

  elseif a == "submit" then
    self.pending = { action = "submit" }
    self:sync_confirm()
    self:fx("hex.submit", M.EFFECTS.SELECT)

  elseif a == "restart" then
    self.pending = { action = "restart" }
    self:sync_confirm()
    self:fx("hex.redo", M.EFFECTS.SELECT)

  elseif a == "confirm_no" then
    self.pending = nil
    self:sync_confirm()
    self.toast = "已取消"
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动

  elseif a == "confirm_yes" then
    local p = self.pending
    self.pending = nil
    self:sync_confirm()
    if p ~= nil then
      -- 二次进分发：这次 `self.pending` 已是 nil，但 `submit`/`restart` 分支会**再**设 pending
      -- ⇒ 所以这里直接走"真正执行"的内部函数，不再绕回分发。
      if p.action == "submit" then
        self:do_submit()
      elseif p.action == "restart" then
        self:do_restart()
      elseif p.action == "back" then
        self:do_back()
      end
    end

  elseif a == "undo" then
    -- ★★★★★ 2026-10-04 **按下先给反馈，再执行**（用户："撤销的点击动画还没建好"）。
    --
    --   原来只有一行 `if core:undo() then fx(...)` ⇒ **没有可撤销的东西时一格动画都不播**
    --   ⇒ 点 ↶ 像没反应（`hint` 有动画是因为它每次都播，这就是两者手感不一样的原因）。
    --   ⇒ 按下时先播 `SELECT`（按下的视觉反馈），**撤销真的发生了**再补一个 `UNDO`（undo_flash）。
    --     同一帧两次 fx 打在同一个控件上时**后写的赢**，所以：
    --       有事可撤 → 看到 undo_flash；没事可撤 → 看到 sel_pop_glow。两种都有反馈 ✅
    self:fx("hex.undo", M.EFFECTS.SELECT)
    if core:undo() then self:fx("hex.undo", M.EFFECTS.UNDO) end

  elseif a == "redo" then
    if core:redo() then self:fx("hex.redo", M.EFFECTS.UNDO) end

  elseif a == "hint" then
    local ok, msg = core:hint()
    self.toast = msg
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
    if ok then self:fx("hex.hint", M.EFFECTS.SELECT) end

  elseif a == "reveal" then
    -- 直接揭示答案（照 murdoku 的 Reveal，用于教学/放弃）
    core:reset()
    for id, p in pairs(core.solution) do
      core:select_suspect(id)
      core:hold_cell(p.r, p.c)
    end
    self.toast = "已揭示答案"
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动

  -- ★ 2026-10-02：提交现在**先要 ✓ 确认**（见上面 confirm_yes 分支）⇒ 这里只留"真正执行"。
  --
  -- ★★★★★ 2026-10-05 **补回 `accuse_thief` 的分发分支**（用户指令：「补 accuse_thief」）。
  --
  --   这里是**第一阶段**的入口：点弹窗「摆位成立。谁是盗窃者？」里的嫌疑人卡，发的就是
  --   `accuse_thief`（见 `build_layout` 里 `modal.suspect.*` 那段 `is_acc and ... or ...`）。
  --   形状**与第二阶段的 `accuse_pick_accomplice` 完全对称**，不多做任何事：
  --     记下 `pending_thief`（第二阶段要用它去结案）+ 把弹窗推进到"问同伙"那一屏
  --     （`kind = "accuse_accomplice"` ⇒ 标题变「那同伙是谁？」、且把这人从名单里排除）。
  --
  --   ⚠️ 原来这两行**光有函数体、没有 `elseif` 头**，于是被并进了上面 `reveal` 分支的函数体。
  --      Lua 语法完全合法 ⇒ `luac -p` 看不出来，但后果有两个：
  --        ① 点嫌疑人**点了没反应** —— `accuse_thief` 没有任何分支接住它，两段式指认断在第一阶段；
  --        ② 「揭示答案」会**顺手弹出"那同伙是谁？"**（reveal 的副作用），而且那次弹窗的
  --           `thief` 是 `event.id = nil` ⇒ 第二阶段一个嫌疑人都排除不掉。
  --      `tools/audit/check_actions.mjs` 正是靠"发了却没有 `a == "..."` 分支"把它抓出来的。
  elseif a == "accuse_thief" then
    self.pending_thief = event.id
    self.modal = { kind = "accuse_accomplice", thief = event.id }

  elseif a == "accuse_no_accomplice" then
    self:finish_accuse(self.pending_thief, false, nil)

  elseif a == "accuse_pick_accomplice" then
    self:finish_accuse(self.pending_thief, true, event.id)

  elseif a == "accuse" then
    -- 兼容入口：只给盗窃者，同伙按关卡声明处理
  -- ★ 2026-10-02：重置关卡也要 ✓ 确认。
    local code = core:encode_state()
    self.share_code = code
    self.modal = { kind = "share", code = code }
    if self.opts.on_share then self.opts.on_share(code) end

  elseif a == "howto" then
    self.modal = { kind = "howto" }

  elseif a == "intro_next" then
    self.intro_page = (self.intro_page or 1) + 1
    if self.intro_page > #M.INTRO then
      self.intro_page = #M.INTRO + 1
      self.modal = nil
    end

  elseif a == "intro_skip" then
    self.intro_page = #M.INTRO + 1
    self.modal = nil

  elseif a == "close_modal" then
    self.modal = nil

  -- ★ 2026-10-08 **「退出菜单」四键的三个动作**（★ 从提交 272 原文照抄恢复 ✓ 那次被 295 整份删掉 ✗）
  --   ★ 回调走 `self.opts.on_save` / `on_settle` ✓ ⇒ ★ 已在 main.lua 补回（提交 398 ✓）⇒ 移植过去即生效 ✓
  elseif a == "exit_menu_go" then
    self.modal = nil
    self.screen = "select"
    self.dirty = true
    if self.opts.on_back then self.opts.on_back() end

  elseif a == "exit_menu_save" then
    if self.opts.on_save then self.opts.on_save() end
    self.modal = nil
    self.dirty = true

  elseif a == "exit_menu_settle" then
    if self.opts.on_save then self.opts.on_save() end
    if self.opts.on_settle then self.opts.on_settle() end
    self.dirty = true

  elseif a == "level_list" then
    -- 打开选关面板（关卡清单由 main.lua 通过 opts.levels 给进来）
    self.modal = { kind = "levelselect" }

  elseif a == "select_page" then
      -- ★ 选关翻页（夹紧由 build_layout 里的 page 计算负责，这里只管加减）
      self.select_page = (tonumber(self.select_page) or 1) + (tonumber(event.delta) or 0)
      if self.select_page < 1 then self.select_page = 1 end
      self.dirty = true

    elseif a == "pick_level" then
    if self.opts.on_pick_level then
      self.modal = nil
      -- ★★★★★ 2026-10-05 **顺序修好了** ✗✓ —— 原来 `self.screen = nil` 写在回调**之前** ✗
      --
      --   症状（用户实测 + 两张截图 + 新加的引擎侧体检 ✓）：
      --     · 直接进第一关 ✓ 正常；去过别的关卡再回来 ✗ ★【只剩棋盘，线索区整片没了】✗
      --     · 退出重进第一关没用 ✗；必须去一次别的关卡才行 ✓
      --     · ★ 引擎侧读数：`clues(vis=false)` 而 `clues.bg(vis=true)` `clues.grid(vis=true)` ✗✓
      --       ⇒ ★ 父容器被藏 ⇒ 整片线索区不显示 ✓（这就是那张"只剩棋盘"的图 ✓）
      --
      --   为什么：真机日志里点完卡片后 ★ `controller.screen = **home**` ✗ ——
      --     而这一行**本来置的是 `nil`** ✓ ⇒ ★ 说明是**紧接着的回调**把它改回去的 ✗✓
      --     （`on_pick_level` 在 `main.lua` 那头会走开局/重试那条路 ✓ 中途会重设 screen ✓）
      --   ⇒ ★ 于是 `apply_screen_hide(nodes, "home")` ⇒ HIDE 名单生效 ⇒ `clues` 被藏 ✗
      --     ⇒ 而"进关卡后该显示"的那条路【从来没走到】✗（`self.screen` 一直是 "home" ✓）
      --     ⇒ ★★ 永久丢失 ✓ —— 只有切屏（去别的关卡）才会把它改回 `nil` ✓✓
      --
      --   ★ 修法：**先回调，后置 nil**，并在回调之后再兜一次 ✗
      --     这样无论回调中途把 `screen` 设成什么，回到这里都一定被纠正成"在关卡里" ✓
      self.opts.on_pick_level(event.id)
      self.screen = nil              -- ★ 点卡片 = 离开选关、进入关卡（放在回调【之后】✓）
    end

  -- ★★★ 2026-09-29 新增：主页四键 + 整屏切换（用户要求的布局与流程）
  elseif a == "home" then
    self.screen = "home"; self.modal = nil; self.dirty = true

  elseif a == "levelselect" then
    self.screen = "select"; self.modal = nil; self.dirty = true; self.select_page = 1

  elseif a == "continue" then
    -- 「从存档点开始」= 接续**最近游玩记录**（由 main.lua 提供，取不到就老实说）
    local last = self.opts.last_level and self.opts.last_level() or nil
    if last and self.opts.on_pick_level then
      self.screen = nil
      self.opts.on_pick_level(last)
    else
      self.toast = "还没有游玩记录，先从「选关」开始吧"
      self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
      self.screen = "select"
    end
    self.dirty = true

  elseif a == "shop" or a == "bag" then
    -- 占位：具体内容等美术资源齐全后再设计（用户原话）。
    -- 给一句明确反馈，免得玩家以为按钮坏了。
    self.toast = (a == "shop") and "商城：美术资源就绪后开放" or "背包：美术资源就绪后开放"
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
    self.dirty = true

  elseif a == "clue_up" or a == "clue_down" then
    -- ★★★ 2026-09-30：**线索区滚动**（参考《派蒙的执律庭实习》左侧那个带滚轮的列表）。
    --
    --   引擎**没有滚轮事件**（查过官方 API 缓存），所以做的是"↑/↓ 按钮 + 滚动条"。
    --   滚动的**真正意义**：一屏放不下时，能滚到的那几条必须**真的能被看到** ——
    --   `clue_max_visible` 是硬上限，少建控件就等于线索看不见、关卡不可解。
    --   所以这里只改 `clue_scroll`（窗口起点），**控件一个都不少**。
    --   ⚠️ 这里**不能用 `L`** —— 那是 `build_layout` 里的局部变量，
    --   输入分发这条路上没有（我第一版就写成了 `L.clue_rows`，
    --   运行时报 `attempt to index a nil value (global 'L')`，被探针当场抓住）。
    --   布局常量请走 `M.LAYOUT`。
    local rows = M.LAYOUT.clue_rows or 9
    local shown = math.min(#self.core:view().clues, M.LAYOUT.clue_max_visible)
    local maxscroll = math.max(0, shown - rows)
    local s = self.clue_scroll or 0
    if a == "clue_up" then s = s - 1 else s = s + 1 end
    if s < 0 then s = 0 end
    if s > maxscroll then s = maxscroll end
    self.clue_scroll = s
    self.dirty = true

  elseif a == "focus_clue" then
    -- 线索卡：点一下聚焦、再点取消。
    --
    -- 为什么必须有这个分支：线索卡在 push 时就发了 `event = { action = "focus_clue" }`，
    -- 但分发器一直没有对应分支 —— **点了完全没反应**。
    -- （这是 tools/audit/check_actions.mjs 对账抓出来的：发出 26 个 action、只有 25 个分支。）
    --
    -- 可见反馈走**特效**而不是样式：adapter 的 `key == "style"` 分支只对少数已知样式
    -- 做缩放反馈，未知样式是静默忽略的。这里复用已有的 CLUE_IN 特效，不引入新资产。
    local ci = event.index
    if ci ~= nil then
      -- ★★ 2026-09-29 修（被"扫 `and nil or`"扫出来的真 bug）：
      --   原文是 `self.focused_clue = (self.focused_clue == ci) and nil or ci`
      --   —— Lua 里 `x and nil` **恒为 nil**，于是永远落到 `or ci`，
      --   结果 `focused_clue` **永远是 ci，再点一次永远取消不掉聚焦**。
      --   （和我在入口刚踩的那个是同一个坑；写成显式 if 就不会有这个问题。）
      if self.focused_clue == ci then
        self.focused_clue = nil       -- 再点一次 = 取消聚焦
      else
        self.focused_clue = ci
      end
      self:fx("clue." .. tostring(ci), M.EFFECTS.CLUE_IN)
    end

  elseif a == "back" then
    -- ★★★ 2026-09-29（用户要求，参考 murdoku 原作）：
    --   **退出关卡 → 回到选关界面**（不是回主页）。
    --   原作循环是"选关 → 关卡 → 退出 → 选关"，连玩几关不用每次绕主页。
    self.screen = "select"
    self.modal = nil
    self.dirty = true
    if self.opts.on_back then self.opts.on_back() end

  elseif a == "next_level" and self.opts.on_next_level then
    self.opts.on_next_level()
  end

  self.dirty = true
  return self.effects
end

-- ★★★★★ 2026-10-05 **`tick` 不再无条件 `self.dirty = true`**（这一轮最后一条每帧成本）。
--
--   改之前：`tick` 每帧置 dirty ⇒ `Murdoku.on_update`（main.lua L682）见 dirty 就重绘
--     ⇒ 离线实测（`tests/grid_cost.lua` [E]）**300 帧 = 300 次 render**，
--       而每次 render 都要重建 **260 个计划节点**、再走一遍属性账本 —— 用户说的
--       "看着不动也卡"里，这是与"兜底隐藏"并列的第二笔固定开销。
--
--   为什么可以改（先把"它到底在维护什么"数清楚）：`tick` 真正改的只有两件事，
--   而这两件事各自都自带"什么时候才需要重画"的判据 ——
--     · `core:set_elapsed(+dt)`：HUD 计时器显示的是 `Controller:format_time()`，
--       它 `math.floor` 到**秒**（MM:SS）⇒ 只有**整秒变了**才需要重画，不是每帧；
--     · `flush_pending_note()`：真的落成笔记时**它自己**置 dirty（L474），
--       没落成 = 状态没变 = 不需要重画。
--   其余所有会让画面变化的东西，在各自的入口**已经**置了 dirty（本文件 26 处；
--   其中 `on_input` 末尾 L1056 那一处就覆盖了全部光标 / 键盘事件）。
--   ⇒ 唯一"没人管"的就是计时器那一秒，在这里按"整秒变了"补上。
--
--   ⚠️ 这条判据与 `main.lua` 的整秒心跳（`sec ~= current.last_tick`）**相同** ——
--      是有意的双保险：哪天那条被改动，计时器也不会停。
--   ⚠️ `#self.effects > 0` 同理：动效是"排进队列 → 下一次 render 放掉并清空"。
--      正常情况下置 dirty 的是调用方（`fx()` 的 12 个调用点旁边都有 dirty），
--      这一条只是保证"将来有人只调 fx() 忘了置 dirty"时它下一帧仍会被放出去；
--      render 结束会把 `effects` 清空 ⇒ **不会退化成每帧重绘**。
function Controller:tick(dt)
  self.now = (self.now or 0) + (dt or 0)

  -- ★★★★★ 2026-10-05 **A8：提示语到点就撤**（用户批准的方案甲 —— 只补读者/超时，不动写入点）。
  --
  --   为什么放在 `tick`、用 `self.now`：千星**没有客户端定时器 API**（官方客户端脚本
  --   文档里没有 setTimeout 这一类东西），而 `self.now` 是**本来就在每帧累加**的那根时间轴。
  --   ⚠️ `os.time` / `os.clock` 也在白名单里，但它们与"这一帧"不同源；用同一根轴最稳。
  --
  --   ⚠️ 必须置 `dirty`：出口控件的文字是**布局层每帧下发**的（见 `build_layout` 里的
  --      `hud.subtitle` 与 `home.title`），不置 dirty 就得等"整秒心跳"那一帧才变回去
  --      （表现成提示语多赖 0~1 秒）。
  --
  --   ⚠️ 判据是 `self.toast ~= nil` **且**有截止时刻：`toast_until` 是这一轮才有的字段，
  --      万一有人只写了 `self.toast`（没设截止时刻），这里**不该**把它清掉 ——
  --      那是"写入点漏了"的问题，不该由超时逻辑假装解决。
  if self.toast ~= nil and self.toast_until ~= nil and self.now >= self.toast_until then
    self.toast = nil
    self.toast_until = nil
    self.dirty = true
  end
  local elapsed = (self.core.elapsed or 0) + (dt or 0)
  self.core:set_elapsed(elapsed)
  self:flush_pending_note()      -- 挂起的单击到点就落成笔记（成功时它自己置 dirty）
  local sec = math.floor(elapsed)
  if sec ~= (self._hud_sec or sec) then
    self._hud_sec = sec
    self.dirty = true
  end
  if #self.effects > 0 then self.dirty = true end
end

function Controller:is_intro_active() return (self.intro_page or 1) <= #M.INTRO end

----------------------------------------------------------------------------
-- 布局规格
----------------------------------------------------------------------------

local function rect_of(t) return { x = t.x, y = t.y, w = t.w, h = t.h } end

-- ★★★★ 2026-10-01 **`pos_runtime` 沿子树继承**（用户实测定位的"最后一环"）。
--
--   用户实测结论：**运行时新建的控件看得见，编辑器里已有的看不见**。
--   差别就在这一步 —— 适配器 `respect_editor_rect` 会让脚本**完全不去碰**
--   存档里已有控件的位置/尺寸（连锚点都不设）：
--       if respect_editor_rect and not instantiated and not runtime_rect then return end
--   我原来只给 `home` / `select` 两个**容器**打了 `pos_runtime`，容器尺寸是修好了，
--   但**它们的子控件还留着编辑器里的锚点 + 偏移**（诊断读回来 (960,404)）——
--   在 1600×900 的父容器里 ⇒ 实际落到 (1760, 854) ⇒ **x 超出 1600 ⇒ 屏幕外**。
--   （子控件的 rect 从来没被下发过，所以我自己算的"应该在 (800,337)"一直没生效。）
--
--   ⇒ 一处改：父级标了 `pos_runtime`，**整棵子树都算"运行时控件"**。
--     以后再加子控件也不用逐个记得打标记（漏一个是必然会发生的）。
--
--   ⚠️ 必须**两个 `return nodes` 之前都调用**：`build_layout` 在"主页/选关"状态下
--      会**提前 return**（只 push 主页/选关那几棵子树）。我第一版只加在函数末尾，
--      结果主页状态根本跑不到 ⇒ 继承没生效（探针实测 `home.select` 仍是 false）。
local function inherit_pos_runtime(nodes)
  local pr = {}
  for i = 1, #nodes do
    if nodes[i].pos_runtime then pr[nodes[i].id] = true end
  end
  for _ = 1, 8 do
    local changed = false
    for i = 1, #nodes do
      local n = nodes[i]
      if (not n.pos_runtime) and n.parent ~= nil and pr[n.parent] then
        n.pos_runtime = true
        pr[n.id] = true
        changed = true
      end
    end
    if not changed then break end
  end
end

-- ★★★★★ 2026-10-05 **「老一套线索控件」的 id 判据（全项目唯一一份）**。
--
--   为什么必须收成一处：这份名单要同时被三个地方用 ——
--     · `build_layout`：网格视窗在用时，这一段**整段不发**（见下面那道守卫）；
--     · `build_layout` 收口：发完再扫一遍，规划里**绝不允许**残留老 id；
--     · `render`：切到网格视窗的那一帧，`_shown` / `_created` 里还留着老 id，
--       差集循环**必须跳过**它们（不许再 set_property、不许销毁）。
--   三处各写一份名单 = 必然漂移；漏掉一处就是"又按名字抓到已回收的列表项"。
--
--   ⚠️ 前缀用 **`clue.`（带点）**：`clues` / `clues.bg` / `clues.grid` 是"线索区"自己的
--      东西，不能被误伤（`clues` ≠ `clue.`）。
local function is_legacy_clue_id(id)
  if type(id) ~= "string" then return false end
  if id:sub(1, 5) == "clue." then return true end
  return id == "clues.up" or id == "clues.down" or id == "clues.track"
      or id == "clues.knob" or id == "clues.count" or id == "clues.more"
      or id == "clues.bar"
end

-- ★★★★ 2026-10-01 **屏幕隔离**（子控件不再靠父容器开关之后的必需品）。
--
--   背景：为了修"全屏容器把游戏自己的 UI 挡住、点不动"（用户报"卡死"），
--   我把 `home.*` / `select.*` 的**父级从 home/select 容器改挂到了 root** ——
--   因为证据表明 root 的子控件不会被裁（诊断三的探针挂在 root 下、用户确认看得见）。
--   容器随之缩成 1x1，不再覆盖屏幕。
--
--   ⇒ 副作用：**父容器的 `visible` 不再能开关子树**了。所以这里显式按屏幕藏：
--      · 关卡内（screen == nil）：藏 `home.` / `select.` 两棵子树
--      · 主页 / 选关：藏**关卡内控件**（下面 HIDE / PREFIX 那两组）+ **另一个屏幕的子树**
--
--   ⚠️ `HIDE` 那一组**只在"主页/选关"时生效** —— 里面的 `intro` / `modal` / `toast`
--      在关卡里是要显示的。我第一版没分组、无条件藏，会把教程和弹窗一起藏掉。
local function apply_screen_hide(nodes, screen)
  if nodes == nil then return end
  local HIDE, PREFIX = {}, {}
  if screen == nil then
    -- ★★★★★ 2026-10-03 **真机 bug 的真正根因就在这一行**（原来是 `{ "home.", "select." }`）。
    --
    --   日志（22:40，关卡内 `controller.screen = nil`）：
    --       home             visible=**true**     ← ★ home 容器在关卡里还亮着
    --       home.select      visible=**true**     ← ★ "选关"按钮跟着露出来
    --   ⇒ 玩家看到的"第二行几个格子上面压着返回菜单按钮、点了回选关"就是它。
    --
    --   为什么漏：前缀判断是 `id:sub(1, #PREFIX[k]) == PREFIX[k]`，
    --   原来那条 **带点**（`"home."`）⇒ 能匹配 `home.select`，
    --   **但匹配不到 `home` 自己**（不带点）⇒ `hide = false`
    --   ⇒ 走 `else` 被 `SetVisible(true)` ⇒ **父容器可见 ⇒ 四个子按钮全露**。
    --
    --   ⇒ 去掉那个点：`"home"` 同时匹配 `home` 自己和它全部子控件；`select` 同理。
    PREFIX = { "home", "select" }
  else
    HIDE = {
      topbar = true, toolbar = true, left = true, board = true, right = true,
      toast = true, modal = true, intro = true, clues = true,
      ["action.back"] = true, ["action.redo"] = true, ["action.hint"] = true,
      ["action.undo"] = true, ["action.submit"] = true, ["action.reveal"] = true,
    }
    -- ★ 2026-10-03 **图标（hex.*）只在关卡内显示**：
    --   主页/选关时把它们一起藏掉。关卡内不加进任何 HIDE/PREFIX ——
    --   那 5 个按键图标初始就是 visible=true，直接显示；
    --   确认卡的 hex.ok/hex.no 初始 visible=false，由 `sync_confirm()` 单独控制。
    -- ★★★★★ 2026-10-03 **修了一个真机 bug**：关卡界面里 `selbar`（选关按钮条，
    --   1500×700，覆盖整个棋盘区域）**没被藏掉** ⇒ 它的 4 个 `selbtn.*` 压在棋盘第二行上，
    --   而 `selbtn` 绑的是 `pick_level` ⇒ 玩家点到它们就"返回选关"。
    --   真机日志证据（22:00）：
    --      16. selbtn.2   160x160  可见=true     ← 关卡里还亮着
    --      17. selbtn.3 …  18. selbtn.1 …  19. selbtn.4 …
    --      20. tpl-container 150x150 可见=true  ← 模板引用控件也没藏
    --   ⇒ 三样都补进隐藏名单：`selbar`（容器本身）、`selbtn.`（它的子按钮）、`tpl-`（模板引用控件）。
    HIDE["selbar"] = true
    HIDE["tpl-container"] = true
    -- ★★★★★ 2026-10-05 **`"cell."` 从这里删掉** ✗✓ —— 它就是「第一次进关墙/门不画」的根因 ✓
    --
    --   机制（本函数是**单向**的 ✗：只会 `visible = false` ✓ 从不写回 true ✓）：
    --     · 开局 `screen = "home"` ✓ 于是 `PREFIX` 命中 `"cell."` ✗
    --       ⇒ ★ 25 个 `cell.*` 全部 `visible = false` ✗✓
    --     · 而 `cell.*` 是格子的**根控件** ✗ ⇒ 它的 false 会**连坐全部子控件** ✓
    --       ⇒ ★★ `wall.*` / `door.*` / `face` **一律看不见** ✓✓
    --     · 之后进关卡 `screen = nil` ✓ ⇒ 本函数**不再藏** ✓
    --       但**已经设成 false 的 `cell.*` 它【不会写回 true】** ✗（单向的代价 ✓）
    --       ⇒ ★ 父级一直是 false ⇒ ★★ **墙/门永远不出现** ✓✓
    --
    --   ★★★ 用户的三条实测现象**全部对上** ✓✓：
    --     · 「破坏开局流程（`screen` 全程 `nil`）⇒ 直接正常」✓
    --       ⇒ 那时 PREFIX 只有 `{"home","select"}` ✓ **从不碰 `cell.*`** ✓
    --     · 「正常走流程 ⇒ 不画」✗
    --       ⇒ 开局必经 `home` → `select` ✓ 两趟都把 `cell.*` 设 false ✓
    --     · 「进别的关再回来就正常」✓
    --       ⇒ 那一趟 `screen` 是 `nil` ✓ 不再藏 ✓ 而规划把 `cell.*` 重发 true ✓
    --
    --   ★ 为什么删它是**安全**的：★ `cell.*` 的可见性**规划里已经按屏幕算好了** ✓
    --     · 主页/选关：规划给 `false` ✓（真机开局日志：`cell.1.1 visible=false` ✓）
    --     · 关卡内：规划给 `true` ✓（真机进关日志：`cell.1.1 visible=true` ✓）
    --     ⇒ ★★ 这一条**本来就是重复的** ✗ —— 重复的那份还会用"单向藏"覆盖规划 ✗✓
    --   ⚠️ 教训：★ 可见性【只能有一个权威】✗ —— 规划给了，屏幕层就不该再管 ✓
    PREFIX = { "clue.", "hud.", "room.label.", "ruler", "tray.", "action.", "hex.", "hit.",
               "selbtn.", "tpl.",
               (screen == "home") and "select." or "home." }
  end
  for i = 1, #nodes do
    local id = nodes[i].id
    local hide = HIDE[id] == true
    if not hide then
      for k = 1, #PREFIX do
        if id:sub(1, #PREFIX[k]) == PREFIX[k] then hide = true break end
      end
    end
    -- ★ 容器自己也要收口：前缀 `home.` 匹配不到 `home` 本身。
    -- ★★★★ 2026-10-02 **容器不再跟着切屏显隐**（真机"选关点不动"的下一个假设）。
    --
    --   用户确认 `home`/`select` **是容器节点**（不是按钮）⇒ "全屏按钮吃点击"不成立，已撤回。
    --   回到日志里唯一还没解释的不对称：
    --     主页：点击有效  —— `home` 的 visible **从第一帧就是 true**
    --     选关：点击全废  —— `select` 是**运行中由 false 变 true**
    --   而两者的 bind / 坐标 / 尺寸都对，子控件也都在屏内。
    --   ⇒ 假设：引擎在 `SetVisible(false)` 时把容器标成"不可交互"，
    --     之后 `SetVisible(true)` **射线没有恢复** ⇒ 它的子控件收不到点击。
    --   ⇒ 让两个容器**恒为可见**，屏幕隔离完全交给"按前缀藏子控件"那套
    --     （`home.` / `select.` 前缀本来就覆盖了它们的全部子控件）。
    --
    --   ⚠️ 这会**故意**让 play_test 那三条断言（"主页/选关都藏了"）继续红 ——
    --      它们测的是"容器 visible=false"，而这一版**刻意不那样做**。
    --      真正要验的是"子控件有没有串屏"，那三条的附加信息里已经写了
    --      "关卡内的还可见 0 个" ⇒ 子控件层面是干净的。
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    -- ★★★★★ 2026-10-05 **改回【单向】：只藏，不负责显示** ✗✓ —— 双向那版【闯了祸】✓
    --
    --   我先前把它改成 `nodes[i].visible = not hide`（双向 ✗），以为"这一帧该显示"
    --   这个事实必须进 `nodes` ✓ —— ★ 结果真机上出现了**一排白方块** ✗✓
    --   （用户截图：顶部两处 + 右上两处 + 右侧一处 ✓ 位置正好是 `topbar` / `right`
    --     的图标位 ✓ 日志里 `图标设图 hex.*` 七条【全部成功】✓ ⇒ 图是设上了的 ✓
    --     ⇒ 白方块是它配对的 `hit.*`（透明点击区 ✓ 本身是白图块 ✓）✗）
    --
    --   为什么双向会闯祸：
    --     · `hit.*` / `hex.*` 的可见性有【两套来源】✗ ——
    --         ① 屏幕层（本函数 ✓：主页/选关藏 ✗ 关卡内不藏 ✓）
    --         ② **状态层**（例如"提交键只在能提交时亮"✗ 由别处按状态开关 ✓）
    --     · `hide == false` 时【什么都不做】⇒ 控件保持**状态层刚写过的值** ✓
    --     · 我改成【写 true】⇒ ★ **每帧把状态层覆盖成"可见"** ✗ ⇒ 白方块 ✓✓
    --
    --   ⇒ ★ 正确的分工：★ 本函数【只负责"藏"】✓；"该显示"由**节点的初值**
    --     （`build_layout` push 时给的 ✓）和**状态层**决定 ✓ —— 谁的状态谁负责 ✓
    --   ★ 而"藏过的东西永远回不来"那个真问题 ✗ ⇒ **已经由另外两处修好了** ✓：
    --     · `forget_visible`（差集藏完清账本 ✓ ⇒ 下次该显示时会【重发 true】✓）
    --     · `screen` 判对（构造时 `nil` ✓ + `start_other` 后置 `nil` ✓）
    --     ⇒ ★ 三处里这两处才是根治 ✓，本函数【不需要】也【不应该】双向 ✓✓
    if hide then nodes[i].visible = false end
  end
end
-- ★★★★★ 2026-10-05 **`split_by_name` 从 `build_layout` 里提出来，升成模块级函数**。
--
--   原来它是 `build_layout` 内部的局部函数，闭包里攥着那一帧的 `vm` ——
--   于是**只有那条路**能用它。而本轮新增的"网格视窗列表项填充"在 `render` 那条路上
--   （见 `Controller:_fill_grid_item`），同样需要"从线索文案里切出人名"。
--   ⇒ 一提就够：`vm` 由调用方传进来，两条路共用**同一份**切分逻辑。
--     （"同一件事两处实现必然漂移"是本项目反复踩到的病，能共用就绝不复制。）
--
--   返回：名字 / 前缀 / 后缀 / 该角色的 id / 头像名
local function split_by_name(vm, txt)
  if type(vm) ~= "table" or type(vm.tray) ~= "table" then return nil, txt, nil, nil, nil end
  local best, bestIt = nil, nil
  for _, it in ipairs(vm.tray) do
    local nm = tostring(it.name or it.short or it.id or "")
    if nm ~= "" and txt:find(nm, 1, true) then
      -- 取**最长匹配**，避免"保"抢先于"保安"
      if best == nil or #nm > #best then best, bestIt = nm, it end
    end
  end
  if best == nil then return nil, txt, nil, nil, nil end
  local at = txt:find(best, 1, true)
  local pre, post = txt:sub(1, at - 1), txt:sub(at + #best)
  return best, pre, post, bestIt and tostring(bestIt.id) or nil, bestIt and bestIt.portrait or nil
end

-- ★★★★★ 2026-10-05 **A8：提示语（`self.toast`）的出口文案** —— 全项目**唯一**读它的地方。
--
--   方案甲（用户批准）：**接一个已存在的控件当出口**，一个控件都不加、布局一行不动。
--   出口有两个（为什么是两个，见下面 `hud.subtitle` / `home.title` 两处的说明）：
--     · `hud.subtitle` —— 关卡内（撤销 / 取消 / 揭示 / 回滚 / 提交与结案结果…）；
--     · `home.title`   —— 主页（「商城 / 背包」是在主页点的，而主页上整片 `hud.` 前缀
--                         被 `apply_screen_hide` 藏掉 ⇒ 主页必须另有出口）。
--
--   ⚠️ 为什么**不**另找控件、也不加控件：`hud.toast` 已经按参考图删了 ——
--      `tools/sim/out/layout-plan.json` 里没有它，**存档里也没有它的记录**
--      （实测 `208-补active.gil`：`hud.toast` **0 条**；`hud.subtitle` / `hud.title` /
--        `hud.timer` / `hud.timer` / `hud.progress` 各 1 条；`legend` / `clues.more` /
--        `room.label.*` / `ruler.*` / `select.*` 也都是 0 条）
--      ⇒ 写一个**不存在**的控件 = `set_property` 静默 no-op = 这场修复白做 ✗。
--   ⚠️ 空串按"没有提示语"处理：出口控件的 `text` 不允许被清成空串之后还赖在计划里
--      （`nil` 时一律回落到控件本来的文案，见那两处 push）。
function Controller:toast_text()
  local t = self.toast
  if t == nil then return nil end
  t = tostring(t)
  if t == "" then return nil end
  return t
end

function Controller:build_layout()
  local vm = self.core:view()
  local L = M.LAYOUT
  local nodes = {}

  -- ★★★★ 2026-10-01 **真机"界面空白"的最后一环：`root` 的尺寸是 0x0。**
  --
  --   真机诊断读回来：
  --     root       visible=true  位置=(0,10)  尺寸=**0x0**      <-- 所有东西都装在它里面
  --     home       visible=true  位置=(0,0)   尺寸=1600x900   （这一环上一版刚修好）
  --     home.title visible=true  位置=(960,195) 尺寸=1000x110
  --   ⇒ 子控件的尺寸和坐标都对，但父级 `root` 是 0×0 ⇒ **全被裁掉** ⇒ 屏幕上什么都没有。
  --
  --   `root` 是游戏自己的根节点，脚本原来**从来没给它设过尺寸**（布局里根本没 push 它），
  --   它在 .gil 里就是 0×0 —— 而 `respect_editor_rect` 又让脚本不去碰它。
  --   ⇒ 显式补一条：把 root 撑成整屏（`pos_runtime = true` 让它真的生效）。
  --     画布本身就是 1600×900，所以这是"恢复默认"而不是"改设计"。
  --
  --   ⚠️ 这条必须放在 `local nodes = {}` **之后** —— 我第一版插在它前面，
  --      dump_layout 当场报 `attempt to get length of a nil value (global 'nodes')`。
  nodes[#nodes + 1] = {
    id = "root", kind = "container", parent = nil, visible = true,
    rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height },
    pos_runtime = true,
  }
  
    -- ★★★ 2026-10-01：**家具图标的调色板条目**（⑤ 的阻碍在这里清掉）。
    --
    --   用途：格子模板里的 `obj` 子控件按 `cd.object` 换图。适配器的 `object` 分支
    --   走 `SetImage(obj.imageSource, 调色板[id])` —— 和头像卡 `portrait.*` 完全同一条路
    --   （那条路真机上已经工作：日志 `SetImage 后 tray.A imageType = Stretch`）。
    --
    --   素材**不用自己画**：直接用**游戏自带的 1543 个图片素材**的 id
    --   （目录 https://qx.070077.xyz/api/library/catalog 14 类，见 docs/美术素材从哪来-实地调查.md）。
    --   看过接触表后挑的：
    --     111051 = 一叠书页（书架）  111064 = 金色宝箱（展示柜）
    --     111050 = 包裹木箱（书桌）  106053 = 白底板（地毯 —— 本来就该是色块，靠染色上色）
    --
    --   ⚠️ 关卡里物件是**中文名做键**（`["书架"]`），界面层用 `object_key_of` 翻成
    --     `obj.<kind>`（写了 kind）或 `obj.<中文名>`（没写）—— 所以条目名必须是 obj.shelf 这种。
    local OBJECT_PALETTE = {
      ["obj.shelf"]  = 111051,
      ["obj.case"]   = 111064,
      ["obj.desk"]   = 111050,
      ["obj.carpet"] = 106053,
    }
    --   ⚠️ 这里**不能用 `push`** —— `push` 是在下面才定义的局部函数，
    --     在 `local nodes = {}` 后面直接调它会拿到 nil。
    --     （我第一次就插在这里，dump_layout 当场报 `[C]: in ?`，
    --      连带 play_test 红了 3 条。）直接往 nodes 里塞，绕开这个顺序问题。
    for pid, pimg in pairs(OBJECT_PALETTE) do
      -- 父级是编辑器里的 `assets` 容器（`read_palette` 扫它的子控件）
      nodes[#nodes + 1] = {
        id = pid, kind = "button", parent = "assets", visible = false,
        image_id = pimg,
        rect = { x = 0, y = 0, w = 48, h = 48 },
      }
    end

    -- ★★★★★ 2026-10-03 **六个图标改走「官方素材 + 脚本创建」**（用户定稿的路线）
    --
    --   为什么换路线：外部资产（.gia 转存的）**只能挂服务器控件**、**尺寸生成时定死**、
    --   脚本还不能创建它 —— 前几轮就卡在这三条上。
    --   而**官方素材**（游戏自带 sprite）没有这些限制：脚本 `SetImage(src, imageId)` 设图、
    --   `imageColor` 乘算调色、`SetSizeDelta` 改尺寸、`SetAnchoredPosition` 摆位置，一条龙。
    --   （现成佐证：`cell.x` 一直用 `100101` 画叉，跑得好好的。）
    --
    --   ⇒ **编辑器里不用摆任何图标** —— 这里 push 出来，适配器建控件 + 设图。
    --
    --   素材 ID 全部来自官方「功能图标-单色」类（100101–100213，接触表 tools/qx/out/cat-3.png）：
    --     100109 弯钩返回箭头 ↰     100126 循环箭头 ↻       100120 放大镜
    --     100127 逆时针箭头 ↶       100110 向上箭头 ↑       100102 勾 ✓   100101 叉 ✗
    --
    --   ⚠️ `rect` 用的是**规划那套坐标（y 从**上**边算、与 LAYOUT 一致）**，
    --      与你在编辑器里看到的（左下角原点）是同一位置的两种显示，不要混。
    --      换算：编辑器 y = 900 − rect.y − rect.h
    --
    --   图标位置直接取自布局图（docs/布局图-关卡内-v3.png 的画法）：
    --     返回菜单 (60,48,62×62) · 确认卡两枚 (438/500,52,54×54)
    --     右上三键 (1448, 48/144/240, 70×70) · 右下放大镜 (1448, 694, 70×70)
    --   ⚠️⚠️ `rect` 用的是**设计空间 1920×1080**（规划会 ×5/6 缩放到画布 1600×900），
    --       而布局图量出来的是**画布空间**的值 ⇒ **这里要 ×6/5 换回设计空间**。
    --       （我第一次直接填了画布值，dump 出来 `hex.back` 只有 52×52、`cy=834`，
    --        比目标小了 17% —— 就是漏了这一步。）
    --       y 方向：布局图的 y 是**从上**算的，与 `rect.y` 同向，**不用翻转**；
    --       规划会自动把它转成画布的 `cy`（从下算）。
    local K = 6 / 5                                    -- 画布 → 设计空间
    local function D(v) return math.floor(v * K + 0.5) end
    -- ★★★★★ 2026-10-04 **给这 7 个图标绑上事件** —— 这才是"第 4 块：补齐控件"的第一刀。
    --
    --   之前它们只是**图片**：`build_layout` 里建了、位置对、图也设上了（真机 7 行回读全对），
    --   但 `nodes` 里**没有 `event` 字段** ⇒ 适配层不会给它们绑光标事件 ⇒
    --   画面上看得见、点下去什么都没发生。
    --
    --   而"确认状态机"（`self.pending` / `sync_confirm()` / `back_confirm` / `submit` /
    --   `restart` / `confirm_yes` / `confirm_no`）**代码早就写好了**，只差这 7 个入口。
    --
    --   ⚠️ 顺便消掉一处**重复设计**：`confirm.ok` / `confirm.no` 那对节点和
    --      `hex.ok` / `hex.no` **位置一模一样**（438/500, 52, 54×54），
    --      而后者是**运行时已经建好、图也设好**的那一套 ⇒ 保留 hex，删掉 confirm 那对。
    -- ★★★★★ 2026-10-04 **七图标改用"能点"的模板** —— 修"所有按键都没有功能反馈"。
    --
    --   真机日志（17:00，v044）每个图标一条：
    --       `控件 hex.back 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）`
    --   ⇒ 根因：这七个走的是 `cfg.prefab_icon`（**纯图片**客户端模板）——
    --     **图片控件收不到光标事件**（引擎自己这么回的）。上一轮给节点加 `event` 是
    --     **必要但不充分**：事件挂上去了，控件本身接不住。
    --
    --   出路就在同一份日志里：`selbtn.1` 点击成功（`事件=pick_level`），而
    --   `Adapter:ensure_widgets` 建它时用的是 **`cfg.cells.prefab`（格子模板）**，
    --   代码注释原文：「再在容器下建**按钮**（cell 模板 —— 真机验证过能实例化、**能收到点击**）」。
    --   ⇒ 所以这里**去掉 `icon_template = true`**，让它们退回 `cfg.cells.prefab`。
    --
    --   ⚠️ 当初改用纯图片模板是因为"格子模板会连带一整套子控件，画面上多出 7 个迷你格子"。
    --      这个副作用由**子控件默认隐藏**兜住：真机日志里 `wall.*` / `door.*` / `x` 全是
    --      `visible=false`，只有 `face` 会被点亮（`格子底图已点亮：25 个 face`）⇒
    --      每个键看起来就是"一张图"，和纯图片模板的观感一致。
    local ICON_ASSETS = {
      -- id           素材ID    x(画布) y(画布) w    h     事件动作        说明
      { "hex.back",   100109,   60,   48,  62,  62, "back_confirm" },  -- 返回菜单（弯钩箭头 ↰）→ 先问 ✓/✗
      { "hex.submit", 100110, 1448,   48,  70,  70, "submit"       },  -- 提交（向上箭头 ↑）→ 先问 ✓/✗
      { "hex.redo",   100126, 1448,  144,  70,  70, "restart"      },  -- 重置关卡（循环箭头 ↻）→ 先问 ✓/✗
      { "hex.undo",   100127, 1448,  240,  70,  70, "undo"         },  -- 撤回（逆时针箭头 ↶）→ 直接执行
      { "hex.hint",   100120, 1448,  694,  70,  70, "hint"         },  -- 提示（放大镜）→ 直接执行
      { "hex.ok",     100102,  438,   52,  54,  54, "confirm_yes"  },  -- 确认卡 ✓ → 执行 pending
      { "hex.no",     100101,  500,   52,  54,  54, "confirm_no"   },  -- 确认卡 ✗ → 取消
    }
    -- `build_layout` 每帧重建 ⇒ 直接把当前状态折进 `visible` 就够，不需要额外跨帧状态。
    --
    -- ★★★★★ 2026-10-04 **确认卡要出现在"被按下的那个键"旁边**（用户要求）。
    --   规划图上那对 ✓/✗ 画在 (438/500, 52)，旁边还有一行注解：
    --       `APPEARS WHEN SUBMIT / RESET / BACK IS PRESSED`
    --   —— 图里画在 BACK 旁边只是"以返回菜单为例"，**它跟着按下的键走**。
    --   而 SUBMIT / RESET 在右上角（x 1448）⇒ 固定在左上 438 就离得太远了。
    --   ⇒ 三个锚点：返回菜单放**右侧**（跟图上一致）；提交 / 重置关卡放**左侧**
    --     （右边已经贴到画布边缘 1600，放不下）。
    local CONFIRM_GAP = 8
    local CONFIRM_ANCHOR = {
      -- ★ 返回菜单这一档，锚点取**文字右边缘 + 8**，不是"方块右边缘 + 8"。
      --   判据是规划图：图上 ✓/✗ 外面那个虚线框在 **x 430..580**，而
      --   `BACK TO MENU` 文字到 **347** 结束、深色方块在 60..122 ⇒ 图里的确认卡
      --   是画在**整条「返回菜单」控件之后**的，不是紧贴那个方块。
      --   ⚠️ 我第一版取 `60+62+8 = 130` ⇒ 确认卡 (130..246) 正好压在
      --      `action.back` 文字 (133.5..346.5) 上，✓/✗ 会被挡住点不到。
      back    = { x = 347 + CONFIRM_GAP,                            y = 48  },  -- 文字右缘 + 8
      submit  = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 48  },  -- hex.submit 左侧
      restart = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 144 },  -- hex.redo   左侧
    }
    local pend_action = (self.pending and self.pending.action) or nil
    local anchor = CONFIRM_ANCHOR[pend_action] or CONFIRM_ANCHOR.back
    local icon_pending_on = (self.pending ~= nil)
    -- ★★★★★ 2026-10-04 **两件东西分开做：图标纯贴图 + 独立透明热区**（用户原本的构思，现已验证）
    --
    --   用户做了一次**对照实验**，把结论钉死了：
    --     同一个存档（178-清理旧控件）+ 旧脚本 v037（走 `prefab_icon` 纯图片模板）
    --       ⇒ 日志「图标设图 hex.back imageId=100109 → 回读 100109 **经 子控件** 调用成功=true」
    --       ⇒ **图标看得见**。
    --     而 v045 起换成 `cfg.cells.prefab`（格子模板）⇒ 图标全部消失。
    --   ⇒ 两条路各有各的硬伤，**谁也替代不了谁**：
    --       · 纯图片模板：**能渲染**，但图片控件**收不到光标事件**（引擎逐条报"不支持光标事件"）。
    --       · 格子模板  ：**能收点击**（`selbtn.*` 已验证），但它的 `face` 默认尺寸 0、得额外补尺寸。
    --   ⇒ 所以按用户原本的构思拆开：
    --       **贴图** = `hex.*`（纯图片模板，无事件）—— 负责"看得见"
    --       **热区** = `hit.*`（格子模板，无 image_id ⇒ face 不会被点亮 ⇒ 完全透明）—— 负责"点得动"
    --     反馈由 `self:fx("hex.*", …)` 打在**贴图**上（点击特效本来就是脚本驱动的）。
    --   ⚠️ 顺序要紧：热区**必须排在贴图之后**（后建的在上面）⇒ 射线落在热区上，
    --      不会被不能处理事件的图片控件吞掉。
    for i = 1, #ICON_ASSETS do
      local a = ICON_ASSETS[i]
      local is_confirm = (a[1] == "hex.ok" or a[1] == "hex.no")
      -- 确认卡的位置按锚点算；其余五个用各自在 `ICON_ASSETS` 里写死的坐标
      local ax, ay = a[3], a[4]
      if a[1] == "hex.ok" then ax, ay = anchor.x, anchor.y end
      if a[1] == "hex.no" then ax, ay = anchor.x + 54 + CONFIRM_GAP, anchor.y end
      local vis = (not is_confirm) or icon_pending_on
      local rect = { x = D(ax), y = D(ay), w = D(a[5]), h = D(a[6]) }
      -- ① 贴图：纯图片模板，**不绑事件**
      --
      -- ★★★★★ 2026-10-04 **`parent` = `root`，而且真实父级也必须是 `root`** —— 修"位置还不对"。
      --
      --   两轮真机日志的**点击坐标**给出的结论（v050 与 v051 数值几乎一样 ⇒ 改规划父级无效）：
      --       `hit.hint 点击 (1573,195)`（规划 1483,171）⇒ 差 **(+90, +24)**
      --       `hit.undo 点击 (1585,638)`（规划 1483,625）⇒ 差 **(+102, +13)**
      --       `hit.back 点击 (178,850)`（规划 91,821）  ⇒ 差 **(+87, +29)**
      --   而 `stage` 自己的偏移正是 **(+100, +20)** ⇒ **运行时始终以 `root` 为参照**，
      --   真实父级 `stage` 又叠了自己那一层。⇒ 把**真实父级**也改成 `root`，两层才能抵消。
      --   ⚠️ 早前"挂 root 就看不见"的判断是**错的**：那时图标还在用**格子模板**
      --      （`face` 尺寸 0 ⇒ 什么都不画）。现在贴图已改回纯图片模板
      --      （日志：`图标设图 hex.* … 经 子控件 调用成功=true`）⇒ 挂 root 既可见、位置又对。
      --   对应地 `cfg.parent_of` 里 14 个 id 都写 "root"（适配器自动创建的默认父级是 stage）。
      nodes[#nodes + 1] = {
        id = a[1], kind = "button", parent = "root",
        visible = vis,
        image_id = a[2],
        imageType = "Stretch",
        icon_template = true,          -- ★ 走 cfg.prefab_icon（真机验证：图标看得见）
        rect = rect,
      }
      -- ② 热区：格子模板、**不给 image_id**（所以 face 不会被点亮 ⇒ 完全透明），只负责收点击
      nodes[#nodes + 1] = {
        id = "hit." .. a[1]:sub(5), kind = "button", parent = "root",
        visible = vis,
        event = { action = a[7] },
        icon_template = false,         -- 走 cfg.cells.prefab（真机验证：能收到点击）
        rect = rect,
      }
    end
  -- ★ 每个节点都必须带**显式** visible：
  --   弹窗/教程的控件在编辑器里是一直存在的，开局由 render 统一藏起来；
  --   如果节点没有 visible 字段，增量渲染就永远不会把它重新显示出来
  --   （2026-09-26 踩过：指认面板出来了，但一直是隐藏的）。
  local function push(n)
    if n.visible == nil then n.visible = true end
    nodes[#nodes + 1] = n
    return n
  end
  local function btn(id, parent, r, text, event, style, enabled)
    return push({ id = id, kind = "button", parent = parent, rect = r, text = text,
                  style = style or "stamp", enabled = (enabled ~= false), event = event })
  end

  push({ id = "root", kind = "container", rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }, style = "screen" })

  -- ★★★★★ 2026-10-04 **把 `stage` 也写进规划** —— 它原来"不在计划里"，导致子控件偏移算错。
  --
  --   背景：适配器自动创建控件（`auto_create_only` 名单，如七个 `hex.*`）时，
  --   ⚠️ 2026-10-09 补：那份白名单**已删除**（`hex.*`/`hit.*` 搬进存档了 ✓
  --      见 `tools/gil/gen_icons.mjs` 与 `230-图标搬进存档.gil` ✓）
  --      ★ 但**下面这条决定仍然有效** ✓ —— `stage` 该留在规划里，与白名单无关：
  --      规划里的父子关系必须与**真实控件树**一致，否则中心点偏移算错 ✓
  --   真实父级默认是 **`stage`**；而规划里那七个图标的 `parent` 写的是 `root`。
  --   运行时下发的是「**规划**中心 − **规划父级**中心」，却挂在**真实父级**上解释
  --   ⇒ 差的正好是一个 `stage` 中心的位移：
  --       `stage` 在 (100,20)（棋盘中心 (900,470)）⇒ 整组右移 100、上移 20。
  --   真机实测（17:02 截图）：四图标全部右移 92px、被右边缘切掉。
  --
  --   两个方向都试过了：
  --     · 改 `cfg.parent_of` 挂到 `root` ⇒ 偏移对了，但 **7 个键在关卡里完全不显示**。
  --     · ⇒ 正解：**让"规划父级"和"真实父级"一致**，而不是把真实父级搬走 ——
  --       给 `stage` 补上这条规划节点，父级中心就有了正确来源。
  --   ⚠️ 这条 rect 必须和 `main.lua` 里强制的 `BOARD_W/H = 584`、`BOARD_X/Y = (100,20)`
  --      说的是同一个矩形（`L.board` 就是它），否则又会对不上。
  push({ id = "stage", kind = "container", parent = "root", rect = rect_of(L.board), style = "stage" })

  -- ===== 顶部工具条 =====
  -- ★★★★★ 2026-10-08 **`xxx` 白名单已撤** ✗✓（用户新方案 ✓ 更干净 ✓）
  --   ★ 用户方案 ✓：★ **把 `xxx` 建在"挂了脚本的客户端容器"【之外】** ✓
  --     ⇒ ★ **脚本根本看不见它** ✓ ⇒ ★ 不需要白名单 ✓ **也不需要每帧多查一遍树** ✓✓
  --   ★ 而且 ✓：★ **把它的图层设在整个客户端容器【之下】** ✓ ⇒ ★ 不与任何界面抢层序 ✓
  --   ★ 隔离仍然成立 ✓：★ 整个 2D 画布都在 3D 之上 ✓ ⇒ ★ 它压在 UI 之下、仍在 3D 之上 ✓
  --     ⇒ ★ 空白处触摸被它吃掉 ✓ **落在我们按钮上的触摸仍归按钮** ✓✓
  push({ id = "topbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "topbar" })
  -- 工具条容器：与 topbar 同区（视觉上仍是一条顶栏），只是树里分开，HUD 文字不再和按钮混杂。
  push({ id = "toolbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "toolbar" })
  push({ id = "hud.title", kind = "text", parent = "topbar", rect = rect_of(L.title), text = vm.title, style = "title" })
  local announce_text = ""
  if vm.meta_announce == "one" then
    announce_text = "　※ 线索中有一句假话"
  elseif vm.meta_announce == "none" then
    announce_text = "　※ 线索全部为真"
  end
  -- ★★★★★ 2026-10-05 **A8 的出口①（方案甲：接已存在的控件，布局一行不动）**。
  --
  --   为什么选中 `hud.subtitle`：
  --     · `hud.title` = 关卡标题 —— 用户点名**不许用**（覆盖它会破坏「重置后标题不变」）；
  --     · `hud.timer` / `hud.timer` / `hud.progress` 都是玩家**正在看的计数**（时间/步数/进度），
  --       而且只有 ~125px 宽 ⇒ 装不下「还没有游玩记录，先从「选关」开始吧」这种 17 字提示 ✗；
  --     · 本控件是 717px 宽的**副标题行**（标题下面那一行）—— 语义上就是"对玩家说的一句话"，
  --       而且**存档里真实存在**（`208-补active.gil` 有 `hud.subtitle` 记录 ✓
  --       —— 这是硬条件：控件不存在 ⇒ `set_property` 静默 no-op ⇒ 等于没修 ✗）。
  --   ⇒ 有提示语：文字换成提示语、并**强制可见**（有的关卡副标题为空、本来 `visible=false`）；
  --     提示语到点被 `tick` 清空 ⇒ 这里**自动回落到副标题本身**
  --     （`build_layout` 每帧重建 ⇒ 不需要"记住原文"的跨帧状态 ✓ 也不会留残字 ✗）。
  local toast_text = self:toast_text()
  push({ id = "hud.subtitle", kind = "text", parent = "topbar",
         rect = { x = L.title.x, y = L.title.y + 48, w = L.title.w + 320, h = 30 },
         text = toast_text or (tostring(vm.subtitle or "") .. announce_text), style = "subtitle",
         visible = (toast_text ~= nil) or (vm.subtitle ~= nil or announce_text ~= "") })

  -- 顶部工具条（1920 宽内排布：标题 32..512 / 计时步数 520..814 / 工具 840..1246 / 动作 1262..1828）
  --
  -- ★ 2026-09-27 结构修正：工具 / 操作按钮原来**直接挂在 `topbar` 下**，
  --   于是 `topbar` 里 HUD 文字（hud.title/subtitle/timer/moves）和
  --   tool.*/action.* 混在一起（用户反馈"hub 中混入了 action 和 tool"）。
  --   现在独立出一个 `toolbar` 容器：**topbar 只放 HUD 文字，按钮归 toolbar**。
  --   位置仍用**绝对 rect**（见 L56 的坐标换算注释：rect 是设计空间绝对坐标），
  --   所以改父级**不会移动任何控件**，只是树结构变干净。
  -- ★★ 2026-09-29（用户要求）：**删掉「放置 / X 标记 / 橡皮擦」三个工具按钮**。
  --
  --   理由（用户原话）：「因为放置，标记，橡皮擦，都已经有了合适的操作逻辑，
  --   这三个按钮可以删了」——
  --     · 放置：**双击 / 长按**格子
  --     · 标记：**单击**空格（未选人时切 ✗，选中人物时是预放置）
  --     · 橡皮擦：**单击已放置的格子**就是拿起
  --   三个动作全都有更直接的入口，工具按钮纯属多余（还占着工具条正中间）。
  --
  --   ⚠️ 保留 `Core.mode` 与键盘换工具的**能力**（`Tab` 轮盘仍可切换，
  --      `note` 模式仍可用）—— 删的只是这三个按钮，不是模式机制本身。
  --      这样"以后想加回按钮"或"给移动端留一条路"都不用重写逻辑。
  --
  --   注（踩过的坑）：**不能"干脆不 push"** ——
  --   渲染的差集逻辑只隐藏**曾经显示过**的控件，从没进过计划的控件不会被隐藏，
  --   按钮照样留在屏幕上（实测）。
  --   ⇒ 正确做法是**留在计划里，但 `visible = false`**，让渲染真的把它们藏掉。
  local function tool(id, label, mode, x)
    return push({ id = id, kind = "button", parent = "toolbar",
                  rect = { x = x, y = 26, w = 130, h = 52 }, text = label,
                  style = (vm.hud.mode == mode) and "tab.active" or "tab",
                  visible = (M.SHOW_TOOL_BUTTONS == true),
                  event = { action = "tool", mode = mode } })
  end
  -- ★★ 2026-09-29：用户已在编辑器里**删掉这三个控件**（存档记录 231 → 197）。
  --
  --   脚本必须跟着删，否则 `sub(id,"label")` 找不到子控件 ——
  --   真机日志里那 16 条"读回 nil"就是这个原因：
  --   **不是写入失败，是控件根本不存在**。
  --   （我上一版用 `visible=false` 想"藏起来"，但控件被删掉之后连藏都无从谈起。）
  --   要恢复：把 `M.SHOW_TOOL_BUTTONS` 设为 true **并且**在编辑器里把三个控件加回来。
  if M.SHOW_TOOL_BUTTONS then
    tool("tool.place",  "放置",  "place",  840)
    tool("tool.x",      "X 标记", "x",      978)
    tool("tool.eraser", "橡皮擦", "eraser", 1116)
  end

  -- ★★★ 2026-09-30：**「撤销 / 提交 / 揭示」挪到右侧竖排**（用户确定的映射，参考执律庭实习）。
  --
  --   用户给的排除逻辑：重做 → 已被「重置关卡」占用、提示 → 已被右下角放大镜占用
  --   ⇒ 剩下这三个放右侧三个六边形位置。
  --
  --   两处必须同源：
  --     · 这里（布局计划）—— 模拟器建树、编辑器搭建指南都读它
  --     · `.gil`（`tools/gil/move_side_buttons.mjs` 挪的）—— 真机实际几何
  --   因为 `cfg.respect_editor_rect = true`，真机上**以 `.gil` 为准**；
  --   计划这份是为了让模拟器/文档跟真机一致，别让两边说法不同。
  --
  --   注：父级从 `toolbar` 改成 `root` —— 右侧竖排的 y 已经超出 toolbar 的高度（104），
  --   挂在 toolbar 下会被裁掉。
  -- ★★★ 2026-10-01：**右侧三个按钮的深色六边形底图**（参考图里就是六边形）。
  --
  --   数据来源：Miliastra Image Editor（https://qx.070077.xyz）的 **ELEMENTS 导出**。
  --   我在那个网站上用基础图元摆出六边形，导出 `.lua` 拿到坐标/颜色，
  --   再照搬到我们自己的界面里（不依赖"导入外部资产"那条路）。
  --   见 docs/外部资产-怎么用与我做了什么.md。
  --
  --   六边形的拼法（**这是实测出来的**）：
  --     中间一个矩形 + 上面一个三角 + 下面一个三角。
  --     ⚠️ 别想用"两个三角形"拼 —— 那会得到**八角星**，不是六边形（我踩过）。
  --
  --   图元用的是**游戏自带素材**：
  --     `100001` = 基础形状-矩形 / `100003` = 基础形状-三角
  --   这两个 id 我们**已经在用**（`wall.right`/`door.*` 就是 `100001`，真机正常），
  --   而且都在图片素材库的「基础形状」类里（6 个：100001~100006）。
  --
  --   ⚠️ 图片 id 必须在**存档里**写好（`tools/gil/sync_plan.mjs` 的 `setImageId`，
  --   路径 `/#505/#503/#84/#503`）—— 运行时 `SetImage` 换图**不可靠**：
  --   适配器里有实测记录，读回来的 `imageSource` 和存档里的不是同一个值，会配错图集。
  local HEX_RECT, HEX_TRI = 100001, 100003
  local HEX_PARTS = {
    -- { 图元, dx, dy, w, h, 旋转, 颜色(ARGB) }
    { HEX_RECT, 0,   0, 176, 102,   0, 0xFF1B2030 },   -- 描边·中
    { HEX_TRI,  0,  77, 176,  52,   0, 0xFF1B2030 },   -- 描边·上（编辑器里 y 向上）
    { HEX_TRI,  0, -77, 176,  52, 180, 0xFF1B2030 },   -- 描边·下
    { HEX_RECT, 0,   0, 156,  90,   0, 0xFF2B3348 },   -- 内芯·中
    { HEX_TRI,  0,  67, 156,  46,   0, 0xFF2B3348 },   -- 内芯·上
    { HEX_TRI,  0, -67, 156,  46, 180, 0xFF2B3348 },   -- 内芯·下
  }
  -- ★★★★★ 2026-10-03 **第一组：打开「六边形按钮素材」**（用户走完转存后的第一次接入）
  --
  --   为什么要打开：索引已按"从 .gil 读出的真实值"登记好
  --   （`murdoku-btn-hex = 1073742333`，见 `entry_client_script.lua` 的 `prefab_of`），
  --   而上一轮"实例化失败"的真正原因是**当时转存的是图片素材，不是客户端控件模板** ——
  --   这一次转存下来的就是控件模板（每个带 2~3 层图形子记录）⇒ 这条路通了。
  --
  --   ⚠️ 一个变量原则：**这一轮只开这个开关**，其它一律不动
  --   （坐标、锚点、可见性都保持基点的样子）。
  --
  --   底图挂在哪几个键上：**只挂 `.gil` 里真实存在的三个**
  --   —— 基点的存档里只有 `action.back`（返回列表）/ `action.redo`（重置关卡）/
  --      `action.hint`（放大镜）；`action.submit` / `action.undo` **还没有**，
  --      给不存在的键挂底图只会多出三个孤儿控件。
  -- ★★★★★ 2026-10-03 **改回 false** —— 真机探针（16:17）实测：
  --     `InstantiateClientUIControl(1073742333, root)` → **pcall 成功、但返回 nil**
  --   ⇒ 「按模板索引实例化素材」这条路**走不通**（与当初 1073742321 完全一样）。
  --
  --   用户实验得到的两条正确用法：
  --     ① **素材尺寸在"生成时就定好"** —— 之后改素材尺寸或图片尺寸都不会影响显示；
  --     ② **图片必须挂在客户端容器之外**（即只能是**服务器控件**）——
  --        客户端控件容器的子级里，图片加载不了外部资产。
  --
  --   ⇒ 正确做法 = **在编辑器里用「图片 → 静态引用」把素材放进一个控件**（用户的 `m`），
  --     再用 `tools/gil/clone_asset_image.mjs` **克隆那个现成控件**到需要的位置。
  --     —— 而不是让脚本去实例化索引。
  local HEX_PREFAB = false         -- false = 走"克隆现成素材控件"那条（见上面注释）
  local function hex_bg(btnId, cx, cy, size)
    local s = size / 256
    for i = 1, #HEX_PARTS do
      local p = HEX_PARTS[i]
      local w, h = math.floor(p[4] * s + 0.5), math.floor(p[5] * s + 0.5)
      push({
        id = btnId .. ".hex" .. i,
        kind = "button",
        parent = btnId,
        visible = true,
        image_id = p[1],                       -- 素材 id（存档里会写进 /#505/#503/#84/#503）
        imageColor = p[7],                     -- 乘算着色
        -- ★ 真机日志显示：sync_plan 克隆出来的图元是 imageType=Basic（按原始像素铺），
        --   而正常工作的 bg/face 都是 Stretch。Basic 时若素材本身很小，画出来就等于看不见
        --   （这很可能就是「截图上什么都没有」的原因）。
        -- ★★★★★ 2026-10-09 **「imageType 不在存档里」这条【已被证伪】** ✗✓
        --   ⚠️ 原文（错 ✗）：「比过 wall.left/wall.right，只差 id ⇒ 只能运行时设」
        --   ★ 实测：它**就在存档里**，路径 **`/505/503/84/504`**（`=1` ⇒ Stretch ✓
        --     官方枚举 `Basic=0/Stretch=1` ＋ proto3 省略 0 ✓）
        --     · `229` 里 44 条带图片描述组的记录中 5 条写了它、值恒为 1
        --     · 那 5 条**恰好**是真机日志里 `type=Enum.ImageType.Stretch id=100108` 的那 5 条 ✓
        --   ★ 当年为什么没比出来 ✗：`wall.left`/`wall.right` **恰好都缺**这个叶子
        --     ⇒ 那次比对**结构上就看不见它** ✓（又一个"抽样看不到 ≠ 不存在" ✓）
        --   ⇒ ★ **两条路都通**：存档能带（`tools/gil/fix_btn_bg_type.mjs` ✓ 产物 `234` ✓），
        --     运行时也能设（下面这个字段 ✓）⇒ **双保险**，但别再当"只能运行时" ✗
        --   ⚠️⚠️ **2026-10-09 更正：别把它当成"没图"的原因** ✗
        --     用户实测否掉了：「**功能图标的图片形式就是基础**，大多数图片也只有基础一种，
        --     **基础和拉伸绝大多数情况下没有差别**」✓
        --     ⇒ ★ 我犯的是「**把相关当因果**」✗ ⇒ 四键"没图也没字"的真因**仍待查** ✓
        imageType = "Stretch",
        rect = {
          x = cx + math.floor(p[2] * s + 0.5) - math.floor(w / 2),
          y = cy + math.floor(p[3] * s + 0.5) - math.floor(h / 2),
          w = w, h = h,
        },
        rot = p[6],
        pos_runtime = false,                   -- 固定几何，编辑器说了算
      })
    end
  end
  -- ★★★★★ 2026-10-02 **右上三键 = 提交 / 重置关卡 / 撤销**（用户定稿，见 LAYOUT 尾部那段注释）
  --
  --   原来是「撤销 / 提交 / 揭示」竖排在右侧中部（x=1790, y=390/540/690）。
  --   现在按参考图挪到**右上角**，并把「揭示」换成**重置关卡**（从左上搬来）：
  --     上 → 下：提交 / 重置关卡 / 撤销
  --   右边缘 = `LAYOUT.side_key.right_edge`，**右下角那组（0/6 + 放大镜）也贴这条线**。
  local SK = L.side_key
  local sk_x = SK.right_edge - SK.size
  local sk_y = { SK.top, SK.top + SK.size + SK.gap, SK.top + (SK.size + SK.gap) * 2 }
  -- 六边形底图（三个键各一层）
  if HEX_PREFAB then
    -- ★ 第一组：只给"存档里真实存在"的三个键挂底图。
    --   ⚠️ 坐标故意留 `nil` —— 由适配器按 `cfg.parent_of` 把它实例化到**父控件**身上，
    --      位置跟着父控件走。写死 `sk_x/sk_y`（右上角那套）会和 `.gil` 里
    --      `action.back`/`action.redo` 的真实位置（在 `topbar` 里）对不上 ⇒ 底图飘在别处。
    -- ★ 2026-10-04：只留 `action.back` —— `action.redo` / `action.hint` **已从存档里删掉**
    --   （它们与 `hex.redo` / `hex.hint` 重叠且动作重复，用户已批准清理旧控件）。
    --   父控件没了，这两枚底图节点也就没有意义，一并去掉。
    local btns = {
      { "action.back" },
    }
    for i = 1, #btns do
      local b = btns[i]
      push({
        id = b[1] .. ".hexbg", kind = "button", parent = b[1], visible = true,
        rect = { x = 0, y = 0, w = 110, h = 110 },
        pos_runtime = true,          -- 位置跟着父控件（按钮）走
      })
    end
  else
    hex_bg("action.back", sk_x + 55, sk_y[1] + 55, SK.size)
    -- ★★★★★ 2026-10-05 **删掉这两行：`action.redo` / `action.hint` 的六边形底图** ✗
    --
    --   为什么删（真 bug ✓）：
    --     `hex_bg(parent, …)` 会给 `parent` 建 6 个子节点（`parent..".hex1"`…`".hex6"` ✓）。
    --     但 **`action.redo` 与 `action.hint` 这两个父节点，已经在下面 L1718-1740 被删掉了**
    --     （2026-10-04「旧文字按钮 —— 已删」✓ —— 它们的功能改由 `hex.redo`/`hex.hint`
    --      贴图节点 + `hit.redo`/`hit.hint` 热区承担 ✓）。
    --   ⇒ 于是计划里**凭空多了 12 个"父级不存在"的悬空节点** ✗
    --   ⇒ 后果（实测）：模拟器的 `kit.mjs:74`
    --       `parentId = (n.parent && idOf[n.parent]) || canvasRoot.id`
    --     **静默回落到画布根** ✗ ⇒ 父级中心算错 ⇒ 那 12 个 button 又被补上
    --     `bg`(白图 `100108`) + `label` ⇒ ★ **模拟器里凭空多出 12 个白块** ✗✓
    --   ⇒ 这**不改变**任何一条断言的通过/失败条数 ✓，但它**持续污染**所有几何类、
    --     "多余控件"类的断言 ✗（例如 `verify_art.mjs` 的「棋盘区域没有多余控件」✓）
    --
    --   ⚠️ **`action.back` 那一行必须保留** ✓ —— 它是**确实存在于计划里**的父节点
    --     （`layout-plan.json` 实测有 `action.back` 与 `action.back.hex1..6` ✓✓）。
    --   依据：`docs/计划与脚本漂移-根因调查.md` 的 **T3** 条 ✓（提交 `73dd2d8` ✓）
  end

  -- ★★★★★ 2026-10-04 **右上三键（提交 / 重置关卡 / 撤销）的旧文字按钮 —— 已删。**
  --
  --   用户反馈「右侧四键的位置不对」。实测两套键**重叠且动作重复**（画布中心）：
  --       action.submit (1541,833) 92x92  vs  hex.submit (1483,817) 70x70
  --       action.redo   (1541,708)        vs  hex.redo   (1483,721)
  --       action.undo   (1541,583)        vs  hex.undo   (1483,625)
  --       action.hint   (1541,126)        vs  hex.hint   (1483,171)
  --   布局图定稿的是**七个 `hex.*` 图标**（位置逐项吻合，且已经有素材图），
  --   而旧文字键偏右上 58px、还大一圈 ⇒ 画面上就是"两套键叠着"。
  --   ⇒ 留图上那套，删掉这四个旧节点。
  --   ⚠️ `action.redo` / `action.hint` 在用户存档里**真实存在**（编辑器摆的）——
  --      删掉计划节点后它们会落进"不在计划里"的名单，由 `Adapter:hide_unlisted` 收起。
  --
  --   （历史注释：`action.redo` 的父级必须与存档一致，否则运行时按「规划中心 − 规划父级中心」
  --     下发的偏移会落到错的父级上、整支偏 407px。这条仍然成立，只是该节点已删。）

  -- 提交 / 重置关卡 / 撤销 / 提示 的入口 = 上面 `ICON_ASSETS` 里的 `hex.submit` /
  -- `hex.redo` / `hex.undo` / `hex.hint`（已接上确认状态机）。

  -- ★ 删除（参考图里没有）：`action.reveal` 揭示 / `hud.score` / `hud.violations`
  --   / `hud.share` / `hud.toast`。删除方式 = **不再 push 这些节点** ——
  --   `layout_plan` 与 `build_layout` 同源，不再出现的节点在编辑器指南里也会消失。
  --   （`.gil` 里若还残留同名控件，`tools/gil/prune_nodes.mjs` 负责清掉。）
  --
  -- ★★★ 2026-09-30：**按参考图重排顶栏与右下角**（《派蒙的执律庭实习》局内 UI）。
  --
  --   参考图的四个位置：
  --     左上   「返回菜单 ↰」 + 「重置关卡 ↻」
  --     右下   「0/6」计数 + 一个**放大镜**
  --     右侧竖 三个深色六边形（= 我们的 撤销/提交/揭示，上一轮已挪好）
  --
  --   对照关系（用户给的排除逻辑：重做→重置关卡、提示→放大镜）：
  --     · `action.back`  ——「返回列表」，挪到**左上**
  --     · `action.redo`  —— 按钮改成**「重置关卡」**，动作换成 `restart`
  --       （`restart` 早就实现了：`core:reset()`。**重做没有消失** ——
  --        键盘快捷键里仍然保留 `redo`，只是这个**按钮**让给了"重置关卡"。）
  --     · `hud.progress` + `action.hint` —— 挪到**右下角**（计数 + 放大镜）
  --
  --   几何两处同源：这里（布局计划）+ `.gil`（`tools/gil/move_side_buttons.mjs`）。
  -- ★★★★★ 2026-10-02 **左上 = 返回菜单 + ✓/✗ 确认条；右下 = 进度 + 放大镜（右对齐）**
  --   用户定稿（`docs/布局图-关卡内-v3.png`）：
  --     · 左上只留「返回菜单」；`action.redo`（重置关卡）**已搬到右上第 2 个**
  --     · 它右边是 ✓ / ✗  —— **默认 visible=false**，点「返回菜单 / 提交 / 重置关卡」时出现
  --     · 右下 = `hud.progress`（0/6 计数）+ `action.hint`（放大镜 = 继承的提示功能）
  --       两者**右边缘与右上三键对齐**（同一列，右边缘 = L.side_key.right_edge）
  -- ★★★★★ 2026-10-04 **`action.back` 缩到"BACK TO MENU 文字"那一段** —— 它原来和两样东西重叠。
  --
  --   原来 `back_btn = {x=24, y=22, w=300, h=66}`（设计空间）⇒ 画布 x 20..270、y 826..881，
  --   而规划图 v3 上这两块是分开的：
  --     · 深色方块 + `<` 弯钩箭头   x 60..122、y 48..110   （画布）← 由 `hex.back` 负责
  --     · 文字 `BACK TO MENU`       x 134..347、y 64..84   （画布）← 这一块才是 `action.back`
  --   ⇒ 旧值把方块和文字**一起盖住**，于是和 `hex.back`(60..122) 重叠；
  --     更要命的是**确认卡**现在出现在 `hex.back` 右侧（x 130..246、y 798..852）
  --     ⇒ 旧 `action.back` 正好压在同一片区域上，✓/✗ 会被它挡住点不到。
  --   ⇒ 按图上文字的实际范围收窄：画布 x 134..347、y 64..84
  --     ⇒ 设计空间 x 161..416、y 77..101 ⇒ 取 {x=161, y=77, w=255, h=28}。
  local BK = L.back_btn
  push({ id = "action.back", kind = "button", parent = "topbar", visible = true,
         rect = { x = BK.x, y = BK.y, w = BK.w, h = BK.h },
         text = "返回菜单", event = { action = "back_confirm" }, style = "stamp.sm" })

  -- ✓ / ✗ 确认条：**默认隐藏**（visible=false）。真正的显隐由 main.lua 的
  --   `confirm_show()/confirm_hide()` 每帧按 `pending_action` 决定 ——
  --   这里只负责"建出来 + 给个初始隐藏状态 + 绑事件"。
  -- ✓ / ✗ 确认条：**默认隐藏**（visible=false）。
  --   显隐规则：只有 `self.pending ~= nil`（点了 返回菜单 / 提交 / 重置关卡）时才出现。
  --   `build_layout` 是**每帧重建**的（见文件头"控件树每帧重建"那段）⇒
  --   直接把 `self.pending` 折进 `visible` 就够了，不需要额外的跨帧状态。
  -- ★★★★★ 2026-10-04 **这里原本还 push 了 `confirm.ok` / `confirm.no` 两个节点 —— 已删。**
  --
  --   为什么删：它们和上面 `ICON_ASSETS` 里的 `hex.ok` / `hex.no` **位置一模一样**
  --   （438/500, 52, 54×54 —— 都是从同一张布局图上量的），事件也一样
  --   （`confirm_yes` / `confirm_no`）⇒ **同一件事两处实现**。
  --   而 `hex.ok` / `hex.no` 是**运行时由脚本从模板建出来的**（真机日志：`图标设图 hex.ok
  --   imageId=100102 → 回读 100102` 成功），`confirm.ok` / `confirm.no` 在存档里**根本不存在**
  --   （真机日志：`confirm.no 读回 nil`）⇒ 保留能用的那套。
  --   ⇒ 确认键 = `hex.ok` / `hex.no`，显隐跟着 `self.pending` 走（见上面 ICON_ASSETS 那段）。

  -- 右下：计数。放大镜的入口 = `hex.hint`（图上那枚，已接 `hint` 动作）——
  --   旧的 `action.hint` 文字按钮已删（与本轮右上三键同样的理由：与 `hex.hint` 重叠且动作重复）。
  local RB = L.side_key.right_edge
  local PG = L.progress
  push({ id = "hud.progress", kind = "text", parent = "right",
         rect = { x = RB - 110 - PG.icon_gap - PG.num_w, y = PG.y, w = PG.num_w, h = PG.h },
         text = string.format("%d / %d", self:placed_count(vm), vm.piece_count),
         style = "stat" })

  -- ★★★★★ 2026-10-04 **计时器跟着标题进左边栏**（图上 TIMER 就在 TITLE 下面一行）。
  --   量图：字形带 x 60..343、y 190..217 ⇒ 中心 (201.5, 203.5) 画布
  --   ⇒ 设计空间中心 (242, 244) ⇒ 取 {x=72, y=216, w=340, h=56}
  push({ id = "hud.timer", kind = "text", parent = "topbar",
         rect = { x = 72, y = 216, w = 340, h = 56 },
         text = self:format_time(vm.hud.time), style = "stat" })

  -- ===== 左侧面板：头像卡 + 线索卡 + 图例 =====
  push({ id = "left", kind = "container", parent = "root", rect = rect_of(L.left), style = "panel.left" })
  -- ★★★★★ 2026-10-02 用户定稿：**头像卡（tray）并进"滚动线索卡"** ——
  --   每张线索卡 = 头像 + 线索文本 + 字母徽章（见下面 `clue.<i>.face` 那段）。
  --   所以这里**不再单独建头像卡**：容器留着但 `visible = false`
  --   （老存档里还有这个控件名，留个空壳比直接删更稳，不会让"控件找不到"的报警刷屏）。
  push({ id = "tray", kind = "container", parent = "left", rect = rect_of(L.tray),
         style = "tray", visible = false })
  -- 头像卡的**列数自适应**：保证永远只占 2 行。
  --   踩过的坑：写死 3 列时，7 个角色的关卡会排到第 3 行，
  --   而 tray 容器只有 2 行高 —— 卡片溢出容器、压住了下面的线索。
  --   规则：per_row = max(3, ceil(人数 / 2))，卡片宽度按剩余宽度均分。
  local gx = L.tray_gap_x or 12
  local gy = L.tray_gap_y or 10
  -- ★★★ 2026-10-02：**清零** —— 头像卡已并进线索卡，不再单独摆（见上面 tray 那段注释）。
  local n_tray = 0
  local per_row = math.max(L.tray_per_row or 3, math.ceil(n_tray / 2))
  local item_w = math.floor((L.tray.w - (per_row - 1) * gx) / per_row)
  local item_h = L.tray_item_h
  for i = 1, n_tray do
    local it = vm.tray[i]
    local col = (i - 1) % per_row
    local row = math.floor((i - 1) / per_row)
    push({
      id = "tray." .. tostring(it.id),
      kind = "button",
      parent = "tray",
      rect = { x = L.tray.x + col * (item_w + gx),
               y = L.tray.y + row * (item_h + gy),
               w = item_w, h = item_h },
      text = it.name,
      image = it.portrait,
      style = it.selected and "portrait.selected" or (it.placed and "portrait.placed" or "portrait"),
      state = { selected = it.selected, placed = it.placed, is_victim = it.is_victim },
      event = { action = "suspect", id = it.id },
    })
  end

  -- ★★★★★ 2026-10-05 **父级必须是 `root`，不能写 `left`** —— 修"线索区跑到棋盘下面"。
  --
  --   真机日志（11:52）铁证：
  --       left = **找不到**                     ← 运行时根本没有 `left` 容器
  --       clues 位置=(47,-29)  尺寸=400x544     ← 位置整个跑偏（画面在棋盘下方）
  --       客户端 UI 根清单：root 子控件=22  └ clues  visible=true 400x544   ← **真实父级是 root**
  --   而规划里写的是 `parent = "left"` ✗ ⇒ 偏移按"真实父级(root)"解释、
  --   却拿一个**不存在的父级中心**去算 ⇒ 整块位置错掉 ✓
  --   （与之前 `hex.*` 那个 bug 完全同一个形状：**规划父级必须等于真实父级**。）
  -- ★★★★★ 2026-10-05 **`pos_runtime = false` = 整块线索区退出"脚本接管几何"** ——
  --   用户原话：「这个区域的位置大小都是原本摆好的，也不需要每关放缩，
  --   脚本只需要管可见性和交互就行了，其它的干涉都是只会增加错误的操作。」
  --
  --   机制（看 `inherit_pos_runtime`）：`pos_runtime` 会**沿子树向下继承**
  --     `if nodes[i].pos_runtime then pr[id]=true end`
  --     `if (not n.pos_runtime) and pr[n.parent] then n.pos_runtime = true end`
  --   ⇒ 显式写 `false` 时 `not n.pos_runtime` 为假 ⇒ **该节点不继承** ⇒
  --     它自己 + 它下面所有没显式标 `true` 的子控件（clues.bg / bar / track / knob /
  --     clue.N 及全部子控件）**统统退出脚本接管** ✓
  --   ⇒ 于是脚本对这块**只做两件事：显隐 + 交互**（正是用户要的），一个坐标都不碰 ✓
  push({ id = "clues", kind = "container", parent = "root", rect = rect_of(L.clues),
         style = "panel", pos_runtime = false })
  -- ★★★★★ 2026-10-05 **线索区大底板（`clues.bg`）** —— 用户在编辑器里摆的那张图，
  --   但它的名字不在规划里 ⇒ 脚本从没点亮它 ⇒ 真机日志（11:31）里它一直 `可见=false` ✗
  --   ⇒ 补一条规划节点（`kind = "container"`：只摆位置/显隐，**不设图不设色**，图与色归编辑器）。
  --   尺寸与容器同尺寸（画布 400×544）、挂在 `clues` 下、坐标相对父级 ⇒ (0,0) ✓
  push({ id = "clues.bg", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         -- ★★★★★ 2026-10-05 **补上 `visible`** ✗✓ —— 这是"线索区没出来"的**两个原因之一** ✓
         --
         --   症状（真机日志 `23:13:32` 的排行榜 ✓）：
         --     · `clues`      400x544  可见=**true**  ✓（父级亮着 ✓）
         --     · `clues.bg`   400x544  可见=**false** ✗  ← ★ 子控件黑着 ⇒ 屏幕上什么都没有 ✓
         --     · `clues.grid` 400x544  可见=**false** ✗（那一条见下面 `_grid_state` 处 ✓）
         --
         --   为什么：★ 上面 L2023 那句注释【自己就写着】「它的名字不在规划里 ⇒
         --     脚本从没点亮它」✗ —— 后来补了这条规划节点 ✓，★ **但没给 `visible`** ✗✓
         --     ⇒ 属性循环里 `visible = nil` ⇒ **不发这一条** ✗ ⇒ 它保持引擎初值（false ✗）
         --   ★ 而 `clues`（父容器 ✓）之所以亮：★ 它由 `apply_screen_hide` **显式写** ✓
         --     （HIDE 名单里有 `clues` ✓ 关卡内写 true ✓）—— ★ **而子控件不在那份名单里** ✗✓
         --     ⇒ ★★ 所以判据必须【与 `clues` 完全一致】✗：关卡内显示 ✓ 主页/选关藏 ✓
         visible = (self.screen == nil) })
  -- ★★★★★ 2026-10-05 **网格视窗 `clues.grid`（官方列表控件）—— 用户在编辑器里摆好的线索列表。**
  --
  --   为什么要有这条规划节点：**不在规划里的控件，脚本不认它**（不会点亮、不会按屏幕开关）
  --   —— `clues.bg` 就是因为漏了这条，真机上一直 `可见=false`（11:31 的日志）。
  --   网格视窗是同一类问题：它得**关卡里可见 / 主页·选关时不出现**。
  --
  --   显隐怎么来的（**与 `clues.bg` 完全同一套**，没有第二套机制）：
  --     · 关卡里：`clues` 与它自己都是 `visible=true` ⇒ 看得见；
  --     · 主页/选关：父级 `clues` 被判成 `visible=false`（`apply_screen_hide` 的 HIDE 名单里
  --       有 `clues`），子控件跟着父级一起不显示 —— 实测规划里 `clues.bg` 就是这个状态
  --       （主页那一屏 `clues(vis=false)` / `clues.bg(vis=true)`，屏幕上并没有露出底板）。
  --
  --   ⚠️ **故意不给它加"按屏幕翻自己的 visible"**：本项目已经验证过一次——
  --      「容器被 `SetVisible(false)` 之后，再 `SetVisible(true)` **射线不一定恢复**」
  --      （见 `home`/`select` 那段"容器恒为可见"的注释）。网格视窗的**点击**本来就是
  --      本轮最不确定的一环，不该再去承担这个额外风险 ⇒ 它自己的 visible **只在
  --      "这条路走不通"时翻一次 false**（见下面的表达式），其余时候恒为 true ✓
  --
  --   ★★ `pos_runtime = false` —— **一个坐标都不碰**（用户原话：「位置大小都是原本摆好的，
  --      脚本只需要管可见性和交互，其它的干涉都是只会增加错误的操作」）。
  --      机制：`pos_runtime` 只沿子树"向下继承 true"（见 `inherit_pos_runtime`），
  --      显式写 `false` ⇒ 不继承 ⇒ 适配器 `set_property("rect")` 走
  --      `respect_editor_rect` 那条分支直接 `return`（连锚点都不设）⇒ 几何完全归编辑器 ✓
  --
  --   ⚠️ 下面这个 `rect` **只是规划表要的字段**（`layout_plan`/`dump_layout` 会读它，
  --      缺了 `M.to_canvas(nil)` 会当场报错），**运行时永远不会下发**（见上一条）。
  --      取值按编辑器里量到的真实尺寸写：网格视窗 **400×544 画布** = 480×652.8 设计
  --      （与 `L.clues` 同一块区域，所以直接沿用 —— 存档核对：id 1073742420、父 `clues`）。
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **一行诊断：把 `_grid_state` 的【真实值】打出来** ✗✓
  --
  --   ★ 起因 ✓：★ 真机日志里 `clues.grid` **可见=false** ✗ 而【同一份日志】又说
  --     「网格视窗：找到 clues.grid ✓ … RefreshItems 回调 **7 次**」✓ ⇒ ★ 它明明成功了 ✓
  --   ★ 而我这一轮**把顺序那条排掉了** ✓：
  --     · `render` 里 **sync 先（L4103）· 规划后（L4105）** ✓ ⇒ ★ 同帧生效 ✓
  --     · `seen` 先收齐（L4137~4138）再算差集（L4168/4186）✓ ⇒ ★ 不是那个老坑 ✓
  --   ⇒ ★★ 所以只剩一种解释 ✓：★ **这一帧 `_grid_state` 真的是 `"off"`** ✗
  --     ★ 即：★ `sync_clue_grid` **判定失败了** ✗ —— ★ 而它的失败行（`_grid_fail`）
  --       ★ 因为 `_grid_log` **去重**，可能只打过一次、或者根本没进我看到的日志 ✓
  --   ★★ 这行日志的价值 ✓：★ **一次实测就能定死方向** ✓✓
  --     ★ 打出 `on` ⇒ ★ 那问题在**渲染层**（★ 我再去查差集 ✓）
  --     ★ 打出 `off`/`nil` ⇒ ★ 那问题在 **`sync_clue_grid` 判定失败** ✓
  --   ⚠️ `push` 是**每帧**跑的 ✗ ⇒ 必须**只打一次** ✓（用 `_grid_log` 的去重 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **这里原来有一处【死代码】诊断，已删** ✗✓（第 246 号提交留下的 ✓）
  --   ★ 原文是 `if self._grid_log ~= nil then self:_grid_log("state_value", …) end` ✗
  --   ★★ 而★ `_grid_log` **定义在 L3512** ✓ ★ 而这里在 **L2110** ✗
  --     ⇒ ★ **那一刻它是 `nil`** ✗ ⇒ ★ **守卫直接跳过** ✓ ⇒ ★ **从来没执行过** ✗
  --   ★★★ 第 247 号提交只把"能打出来的那版"改成了 `print` ✗ ★ **没删这一处** ✗
  --     ⇒ ★ 于是它一直躺在规划里 ✗ ★ **看起来像在工作 ✓ 其实是死的** ✓✓
  --   ⚠️ 教训 ✓：★ **改诊断的时候，要把旧的那份删掉** ✗
  --     ★ 本项目已经踩过同一形状两次 ✓（`erases` / 缩放表 都是"两处负责"✓）
  push({ id = "clues.grid", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         -- 走不了网格视窗时（cfg.use_grid=false / 找不到控件 / 填内容失败）把它藏起来，
         -- 免得"老卡片回来了、但网格还盖在上面" —— 见 `Controller:sync_clue_grid`
         visible = (self._grid_state ~= "off"),
         pos_runtime = false })
  -- ★★★★★ 2026-10-05 **网格视窗在用时，老的一套线索控件"整段不进规划"**。
  --
  --   真机证据（用户实测，每帧刷、永久刷）：
  --     attempt to call method 'imageSource' on an invalid object
  --       client_script:10043 set_property ← 6485 render ← 11832 on_update（start 时也来过一次）
  --   根因链条（已在代码里对上，不是猜的）：
  --     ① 列表项模板（1073742421）的子控件**名字和旧卡片一字不差**：
  --        `clue.1.backrop1` / `backrop2` / `face` / `who` / `what` / `letter`；
  --     ② 适配层 `Adapter:set_property` 第一步就是 `self:find(id)` —— 它按**名字**
  --        在客户端控件树上深度优先搜，**而且把首次命中缓存进 `self.controls[name]`**；
  --     ③ 网格视窗的列表项是**复用**的（官方：只加载可见范围内的列表项）⇒ 名字
  --        `clue.1.face` 抓到的很可能是**已经被回收的那一个列表项** ⇒ 句柄失效；
  --     ④ `clue.N.face` 这个节点带着 `image = ...` ⇒ 走 set_property 的 `image` 分支，
  --        里面那行 `local src = target.imageSource`（适配器 3347 行）**没有 pcall** ⇒ 抛错。
  --   ⇒ 所以旧写法（"照旧 push、只把 visible 改成 false"）根本挡不住：节点还在规划里，
  --     每帧照样 `set_property` 一次，`clue.N.face` 的 `image` 照样下发 ⇒ 每帧抛一次。
  --     更糟的是错误从 `render` 里抛 ⇒ **后面的节点全没处理** ⇒ 用户看到的两条连带症状：
  --     模板格子出不来、`clues.bg` 时有时无（都不是它们自己的问题）。
  --
  --   ⇒ 这一版的让位 = **从源头不发**：不建、不摆、不点亮、连动效都不排队。
  --     判据用 `is_legacy_clue_id`（本文件唯一一份名单，`render` 那边共用同一个函数）。
  --
  --   ⚠️ 下面这一大段的**缩进故意保持原样**（不退不进）：它只是被一个开关括起来，
  --      重排两百多行缩进会让"这一轮到底改了什么"完全看不出来 ⇒
  --      宁可用一个醒目的 `end` + 行尾注释来收口（Lua 不看缩进，语义完全一致）。
  local grid_on = (self._grid_state == "on")
  if grid_on then
    self:_grid_log("giveway", "网格视窗：老的一套线索控件**整段不进规划**（不建 / 不摆 / 不点亮 / "
      .. "连动效都不排队）—— 只藏起来不够：`clue.N.*` 这个名字会被按名字抓到已回收的列表项")
  else
  -- ── 走**老路径**（cfg.use_grid=false / 找不到网格视窗 / 填内容失败）：
  --    下面这一段（到 2095 行那个 `end` 为止）才是手写滚动的那一套，照旧照发 ──
  -- ★ 2026-10-05 **滚动条点击区 `clues.bar`** —— 用户新做的隐形热区（画布 24×520），
  --   规划里原来没有它 ⇒ 脚本不认它（"还没建"名单里反过来没有它才怪 ✗）。
  --   位置：条心 x = 464 画布、纵向与卡片区同高 ⇒ 设计 x = (464−16)×6/5 ≈ 537.6、
  --   y/h 与卡片块一致（用 L.clues 的行距算）。⚠️ 等真机日志回来再微调。
  push({ id = "clues.bar", kind = "button", parent = "clues",
         rect = { x = L.clues.x + 480, y = L.clues.y, w = 28.8, h = L.clue_row_h * 5 - 12 },
         visible = true })
  local shown = math.min(#vm.clues, L.clue_max_visible)
  local rows = L.clue_rows or 9
  -- ★ 滚动位置：0 表示从第 1 条开始。**所有 `shown` 条控件都照旧建出来**
  --   （保证任何一条都能滚到 —— 少建控件就等于线索看不见，关卡不可解）。
  local total = shown
  local maxscroll = math.max(0, total - rows)
  self.clue_scroll = self.clue_scroll or 0
  -- 焦点线索自动滚进视野 —— **只在焦点"变化时"做一次**。
  --
  --   ⚠️ 我第一版是每帧都做，结果：只要之前点过某条线索（`focused_clue` 有值），
  --   **每一帧都把滚动位置拽回那条线索** ⇒ ↑/↓ 点了完全没用（探针点了 40 次没动）。
  --   ⇒ 记住"上次为哪个焦点滚过"，只有真的换焦点时才自动滚。
  if self.focused_clue ~= nil and self.focused_clue > 0
     and self._clue_focus_seen ~= self.focused_clue then
    self._clue_focus_seen = self.focused_clue
    if self.focused_clue <= self.clue_scroll then self.clue_scroll = self.focused_clue - 1 end
    if self.focused_clue > self.clue_scroll + rows then self.clue_scroll = self.focused_clue - rows end
  end
  if self.clue_scroll < 0 then self.clue_scroll = 0 end
  if self.clue_scroll > maxscroll then self.clue_scroll = maxscroll end

  -- ↑ / ↓ 两个按钮 + 一条滚动条（引擎**没有滚轮事件**，这是最实在的做法）
  local ARROW = 34
  local top = L.clues.y
  local bottom = L.clues.y + rows * L.clue_row_h
  push({ id = "clues.up", kind = "button", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - ARROW - 6, y = top + 2, w = ARROW, h = ARROW },
         text = "▲", event = { action = "clue_up" },
         style = "tab", visible = (maxscroll > 0) })
  push({ id = "clues.down", kind = "button", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - ARROW - 6, y = bottom - ARROW - 2, w = ARROW, h = ARROW },
         text = "▼", event = { action = "clue_down" },
         style = "tab", visible = (maxscroll > 0) })
  -- 滚动条：轨道 + 滑块（比例条，纯展示；拖动留给真机验证后再加）
  push({ id = "clues.track", kind = "container", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - 8, y = top + ARROW + 6, w = 4, h = bottom - top - 2 * ARROW - 12 },
         style = "panel", visible = (maxscroll > 0) })
  if maxscroll > 0 then
    local trackTop = top + ARROW + 6
    local trackH = bottom - top - 2 * ARROW - 12
    local knobH = math.max(24, math.floor(trackH * rows / total))
    local knobY = trackTop + math.floor((trackH - knobH) * self.clue_scroll / maxscroll)
    -- 滚动条滑块：y 随 `clue_scroll` 变 ⇒ 位置必须由脚本说了算
    -- （和线索卡同一个道理，见下面 `clue.N` 那段的注释）
    push({ id = "clues.knob", kind = "container", parent = "clues",
           rect = { x = L.clues.x + L.clues.w - 8, y = knobY, w = 4, h = knobH },
           style = "tab.active", visible = true, pos_runtime = true })
  end
  -- 计数（"3–11 / 18"），让玩家知道自己是第几条
  push({ id = "clues.count", kind = "text", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - 120, y = top + 2, w = 78, h = ARROW },
         text = string.format("%d-%d / %d",
           maxscroll > 0 and (self.clue_scroll + 1) or 1,
           math.min(self.clue_scroll + rows, total), total),
         style = "muted", visible = (maxscroll > 0) })

  -- 线索卡"刷出来"的动效：每条只弹一次。
  -- 为什么不在生成时直接 fx：这条线索控件可能在**同一帧里刚被创建**，
  -- 而 effects 是在 render 末尾（控件都建完之后）才统一交给适配器播的，
  -- 所以在这里排队是安全的。控制器每个关卡重建一次 → 表随关卡自然重置。
  self._clue_fx = self._clue_fx or {}
  -- ★★★ 2026-09-30：**线索卡拆成「名字 + 内容」两个控件**（参考《派蒙的执律庭实习》：
  --   卡片上的人名/关键字是**红色**的，正文是白色）。
  --
  --   为什么必须拆控件、不能"行内标红"：官方**没有富文本**（查过 API 缓存），
  --   也没有文字宽度测量 ⇒ 无法在一行里给某几个字换色。
  --   ⇒ 做法：**名字占固定宽度的第一列**（`clue.<i>.who`，红色），
  --     正文从固定 x 起（`clue.<i>.what`，常规色）。这样不需要测量宽度。
  --
  --   ⚠️ 切分依据：线索文案里**一定含角色名**（核心的 `text` 用 `ctx.name(...)` 拼的）。
  --     从 `vm.tray` 里找"哪个名字出现在这条文案里"，找到就切；找不到就整条当正文
  --     （**不硬造关键字** —— 宁可不高亮，也不显示编出来的名字）。
  local WHO_W = 99.6    -- 名字列宽（设计）= 画布 83 ★ 2026-10-05 由 132 改
  -- ★★★ 2026-09-30：**卡片左边一个头像、右边一个字母徽章**（参考《派蒙的执律庭实习》：
  --   线索卡是"人物头像 + 线索文字 + 右侧字母（B/C/D）"）。
  --   头像复用已有的 `portrait.*` 调色板（`vm.tray` 里每项都带 `portrait` 字段），
  --   **不引入新素材**；徽章就是嫌疑人的字母 id（A/B/C/D/V）。
  local FACE = 66        -- 头像边长（设计）= 画布 55 ★ 2026-10-05 由 40 改
  local BADGE_W = 40.8   -- 徽章宽（设计）= 画布 34 ★ 2026-10-05 由 30 改
  local PAD = 16.8       -- 卡片内边距（设计）= 画布 14 ★ 2026-10-05 由 8 改

  -- 返回 名字 / 前缀 / 后缀 / 该角色的 id / 头像名
  --
  -- ★ 2026-10-05：**实现已提到模块级**（见 `split_by_name` 上面那段注释）——
  --   网格视窗的列表项填充要用**同一份**切分逻辑，所以这里不再各写一份：
  --   直接调模块级那份，`vm` 显式传进去。
  --
  --   ⚠️ 不能在这里写 `local function split_by_name(txt) return split_by_name(vm, txt) end`
  --      —— 同名 local 在它自己的函数体里就已经生效 ⇒ 变成**无限递归**
  --      （Lua 里 `local function f() ... f() ... end` 指的就是新的那个 f）。

  for i = 1, shown do
    local cl = vm.clues[i]
    -- 这一条落在窗口的第几行（不在窗口里就整条隐藏 —— 但**控件仍然存在**，能滚到）
    local slot = i - self.clue_scroll
    local inWin = (slot >= 1 and slot <= rows)
    local y = L.clues.y + 15 + (slot - 1) * L.clue_row_h   -- +15 设计 = 上内边距 12.5 画布
    -- ★★★★★ 2026-10-05：行高由 `clue_row_h − 6` 改成 **`− 12`**，宽度由 `L.clues.w − 16` 改成
    --   **`CLUE_W`（= 432 设计 = 360 画布）** —— 为了跟用户在编辑器里摆的卡片对齐。
    --   真机日志（11:31）证明旧值把用户的版面冲掉了：`clue.N 367x91`
    --     · 367 = (L.clues.w − 16) × 5/6 = 440 × 5/6
    --     ·  91 = (clue_row_h − 6) × 5/6 = 109 × 5/6
    --   现在：432 × 5/6 = **360** ✓、115.2 × 5/6 = **96** ✓ —— 与编辑器里的一致。
    local h = L.clue_row_h - 12
    local CLUE_W = 432
    local CLUE_PAD = 16.8   -- 左内边距：设计 16.8 = 画布 14 ✓（用户在编辑器里就是这么留的）
    local style = (self.focused_clue == i) and "clue.focus"
                  or (cl.satisfied and "clue.ok" or "clue")
    -- 整行保留（作为卡片底板 + 点击热区）；文字子控件浮在它上面
    --
    -- ★★★ 2026-09-30：**线索卡整块都要 `pos_runtime`**。
    --   它的 y 随**滚动位置**（`clue_scroll`）每帧变 ⇒ 位置必须由脚本说了算。
    --   否则会被 `respect_editor_rect`（编辑器几何优先）按在存档里那一份几何上：
    --   滚动时**卡片纹丝不动**，只有 visible 在变 —— 真机上表现为「滚了但位置没动，
    --   内容在同一个地方换」。这正是房间名标签那个 bug 的同一个形状。
    push({
      id = "clue." .. i,
      kind = "text",
      parent = "clues",
      rect = { x = L.clues.x + CLUE_PAD, y = y, w = CLUE_W, h = h },
      text = cl.text,
      style = style,
      visible = inWin,
      event = { action = "focus_clue", index = i },
      -- ★★★★★ 2026-10-05 **不再给 `pos_runtime`** —— 用户：「编辑器里的位置本来就是对的，
      --   脚本摆位置是纯粹的无效操作，还会出错」。不带这个标记 ⇒ 走「编辑器几何优先」
      --   （代码里 `pos_runtime = false` 那条注释就是这个意思）⇒ 脚本完全不碰坐标 ✓
    })
    -- ★★★★★ 2026-10-05 **两张卡片底图（backrop1 在下 / backrop2 在上）**
    --
    --   用户在编辑器里给每张卡加了两张图，靠"描边色 + 填充色"叠出边框效果。
    --   真机日志（11:31）显示它们**在关卡里也是 visible=false** ✗：
    --       clue.1..5           可见=true      ← 卡片本体在规划里，被点亮
    --       clue.N.backrop1/2   可见=false     ← 不在规划里 ⇒ 脚本从没把它们点亮
    --   ⇒ 在规划里补上这两条（`kind = "container"`：只摆位置/显隐，**不设图、不设文字**，
    --      图片和颜色完全由你在编辑器里配好、脚本不碰）✓
    --
    --   尺寸：backrop2 比 backrop1 四边各小 3.6 设计（= 3 画布）⇒ 露出 3px 描边 ✓
    push({ id = "clue." .. i .. ".backrop1", kind = "container", parent = "clue." .. i,
           rect = { x = L.clues.x + CLUE_PAD, y = y, w = CLUE_W, h = h },
           visible = inWin })
    push({ id = "clue." .. i .. ".backrop2", kind = "container", parent = "clue." .. i,
           rect = { x = L.clues.x + CLUE_PAD + 3.6, y = y + 3.6, w = CLUE_W - 7.2, h = h - 7.2 },
           visible = inWin })

    local who, pre, post, wid, wportrait = split_by_name(vm, tostring(cl.text or ""))
    local tx = L.clues.x + PAD + FACE + PAD      -- 文字起点：让开左边的头像
    local tw = L.clues.w - 16 - (FACE + PAD * 2) - BADGE_W - PAD
    if who ~= nil then
      -- 头像（左边）：复用 `portrait.*` 调色板，**不引入新素材**
      -- （子控件的 y 也跟着卡片走 ⇒ 同样要 `pos_runtime`，理由见上面那段的注释）
      -- ★★★★★ 2026-10-05 **加 `event` —— 这是"点格子没反应"的真修** ✓✗
      --
      --   为什么必须加（实测三段切开 ✓ 见 `docs/点格子没反应-三段切开结论.md` ✓）：
      --     ★ **鼠标侧【没有任何控件发 `suspect` 事件】** ✗ —— 计划里 `"action":"suspect"` 实测 **0 次** ✓
      --     ⇒ `core.selected` 恒为 `nil` ✗ ⇒ `Core:pre_place` 直接返回「**先点一个头像**」✗
      --     ⇒ ★ **单击不落笔记、双击不放置、步数不动** ✗ ⇒ 观感就是"点格子没反应" = `0 / 5` ✓
      --   为什么是这里 ✓：唯一的生产者（原来那个 `for i = 1, n_tray` 里的 `{action="suspect"}` ✓）
      --     **已经死了** ✗ —— `:1870` 那句 `local n_tray = 0`（2026-10-02 头像并进线索卡 ✓）
      --     ⇒ 那个循环**一次都不跑** ✗；而本控件（`clue.<i>.face` = **卡片上的头像** ✓）
      --     **正好就是现在唯一的头像** ✓ ⇒ ★ 让它承担"点一下选这个人" ✓✓
      --   ★ 与 `:1889` 同一个口径 ✓：**`wid` 有值才给** ✓ 没值就不给（不制造无主事件 ✓）
      --   ⚠️ **只加 `event`，不动 rect/尺寸/样式** ✗ —— 布局一个字没变 ✓
      push({ id = "clue." .. i .. ".face", kind = "button", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 16.8, y = y + 36, w = FACE, h = FACE },
             image = wportrait, style = "portrait", visible = inWin,
             event = (wid ~= nil and wid ~= "") and { action = "suspect", id = wid } or nil })
      -- 名字（红）：正文第一列
      push({ id = "clue." .. i .. ".who", kind = "text", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 16.8, y = y + 2.4, w = 99.6, h = 31.2 },
             text = tostring(pre or "") .. who, style = "clue.who", visible = inWin })
      -- 内容：从固定 x 起（不测量宽度也能对齐）
      push({ id = "clue." .. i .. ".what", kind = "text", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 124.8, y = y + 19.2, w = 242.4, h = 67.2 },
             text = tostring(post or ""), style = "clue.what", visible = inWin })
      -- 字母徽章（右边）：就是嫌疑人的字母 id（A/B/C/D/V），参考图那样
      -- ★★★★★ 2026-10-05 **无条件发勋章节点**（原来写成 `if wid ~= nil and wid ~= "" then`）。
      --   后果：像 `selftest_theft_5x5` 这种**线索文本里没有人名**的关卡，`wid` 为空
      --   ⇒ 整个勋章节点都不发 ⇒ 真机上**所有勋章都不出现** ✗（用户实测：所有勋章都没出现）
      --   现在：永远发，文字为空也发（空文字无害，控件本身还在、背景/描边照常显示）。
      if true then
        push({ id = "clue." .. i .. ".badge", kind = "text", parent = "clue." .. i,
               rect = { x = L.clues.x + CLUE_PAD + 400.8, y = y + 64.8, w = 40.8, h = 33.6 },
               text = wid, style = "clue.who", visible = inWin })
        -- ★ 2026-10-05 **同一徽章再发一份，名字用 `letter`** —— 用户在编辑器里把它命名成
        --   `clue.N.letter`，而规划里叫 `badge` ⇒ 名字对不上就写不进去、**字母不显示** ✗
        --   两份都发（同 rect 同文字）：谁存在谁被点亮，另一个只是"还没建"的无害条目 ✓
        push({ id = "clue." .. i .. ".letter", kind = "text", parent = "clue." .. i,
               rect = { x = L.clues.x + CLUE_PAD + 400.8, y = y + 64.8, w = 40.8, h = 33.6 },
               text = wid, style = "clue.who", visible = inWin })
      end
    end
    if inWin and not self._clue_fx[i] and not self:is_intro_active() and self.modal == nil then
      self._clue_fx[i] = true
      self:fx("clue." .. i, M.EFFECTS.CLUE_IN)
    end
  end
  push({ id = "clues.more", kind = "text", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y + rows * L.clue_row_h, w = L.clues.w, h = 30 },
         text = string.format("还有 %d 条线索", math.max(0, #vm.clues - shown)),
         style = "muted", visible = (#vm.clues > shown) })
  end   -- ← 老一套线索控件到此为止：网格视窗在用时**整段跳过**（见上面那道守卫的长注释）

  -- ★★★★★ 2026-10-05 **收口：规划里绝不允许出现老一套的 id**（守卫之外的第二道闸）。
  --
  --   守卫管的是"这一段不发"；这里管的是"发完再扫一遍"——
  --   以后谁在守卫外面又加了一条 `clue.*` / `clues.up` 的 push，
  --   会被这里当场剔除**并打一行日志**，不会又变回"每帧按名字抓到已回收的列表项"。
  --   （两道闸共用一个判据 `is_legacy_clue_id`，不会漂移。）
  --
  --   为什么剔除还不够、必须连"名字"都不碰：见 `render` 里 `stale_legacy` 那段注释。
  if grid_on then
    local dropped, kept = 0, 0
    for i = 1, #nodes do
      if is_legacy_clue_id(nodes[i].id) then
        dropped = dropped + 1
      else
        kept = kept + 1
        nodes[kept] = nodes[i]
      end
    end
    for i = #nodes, kept + 1, -1 do nodes[i] = nil end
    self._grid_gave_way = dropped
    if dropped > 0 then
      self:_grid_log("giveway_leak", "网格视窗：**守卫之外**还漏发了 " .. tostring(dropped)
        .. " 个老线索控件，已在收口处剔除（查一下是不是新加了 `clue.*` 的 push）")
    end
  end

  -- 操作提示**按设备换文案** —— 同一套界面同时给 PC 键鼠和移动端触碰用，
  -- 但两边的"怎么操作"不一样，写在图例里免得玩家自己试。
  -- ★★ 2026-09-29：**图例文案按"按钮删掉之后"的新操作逻辑重写**。
  --
  --   为什么必须改脚本：**文字内容存不进 `.gil`**（已验证多次：`ruler.c.1` 显示 "C1"、
  --   `hud.title` 显示标题，但记录里只有控件自己的名字）——
  --   这是少数**只能走脚本**的事，正好落在《工作约定》里"必须走脚本"那一栏。
  --
  --   旧文案在说已经不存在的入口（「X工具」「橡皮擦」按钮），
  --   而真正该告诉玩家的是三条最高频动作：
  --     单击空格 = 划掉这格（✗，不需要先选工具）
  --     选中头像后单击 = 假设他在这里（预放置）
  --     双击 / 长按 = 正式放置；单击已放置的格 = 拿起
  local legend_text =
    "单击空格=划掉这格（再点取消）\n"
    .. "选中头像后单击=假设他在这里\n"
    .. "双击/长按=正式放置　单击已放的格=拿起"
  if self.input_profile == "touch" then
    legend_text =
      "轻触空格=划掉这格（再点取消）\n"
      .. "选中头像后轻触=假设他在这里\n"
      .. "长按=正式放置　轻触已放的格=拿起"
  elseif self.input_profile == "pc" then
    legend_text = legend_text .. "\n"
      -- ⚠️ 官方键事件是**语义事件 + 可重映射的「奇匠按键」**（见 KB_ACTIONS 注释），
      --    所以这里写"默认键"，并说明"以你自己的按键设置为准" —— 不能假定玩家
      --    按的一定是 ↑↓←→ / F / Space。
      .. "键盘(默认键)：方向键移动　F放置　空格笔记　Tab换工具　数字选人\n"
      .. "（键位可在按键设置里改，以你实际的为准）"
  elseif self.input_profile == "gamepad" then
    legend_text = "确认=笔记　按住=放置　肩键切换工具\n（手柄为兜底方案，推荐用键鼠或触屏）"
  end

  push({ id = "legend", kind = "text", parent = "left", rect = rect_of(L.legend),
         text = legend_text,
         style = "muted" })

  -- ===== 中央棋盘（含坐标尺）=====
  push({ id = "board", kind = "container", parent = "root", rect = rect_of(L.board), style = "board" })
  -- 格子几何按**当前关卡的实际 N** 自适应：
  -- 棋盘区大小固定，格子边长 = 可用边长 / N。这样 5×5 / 6×6 / 7×7 都能正确排布，
  -- 不需要为每个尺寸重摆一次编辑器布局（编辑器里按**最大的 N** 建够格子即可，
  -- 小尺寸关卡多出来的格子由界面层隐藏、位置由脚本运行时摆正）。
  local n = math.max(vm.rows, vm.cols)
  local avail_w = L.board.w - 2 * L.ruler     -- ★ 边框**两边各一份**（原来只扣一边）
  local avail_h = L.board.h - 2 * L.ruler
  local pitch = math.floor(math.min(avail_w, avail_h) / n)
  local gap   = math.max(2, math.floor(pitch * 0.03))
  local cell  = pitch - gap
  local ruler = L.ruler
  local grid_w = n * pitch - gap
  local grid_h = n * pitch - gap
  local gx = L.board.x + ruler + math.floor((avail_w - grid_w) / 2)
  local gy = L.board.y + ruler + math.floor((avail_h - grid_h) / 2)
  -- ★ 2026-09-27 结构修正：坐标尺原来**直接挂在 `board` 下**，和运行时生成的 49 个格子
  --   挤在同一个节点里（board 子树一度有 63 个子控件），树里根本找不到 ruler。
  --   现在独立成一个 `ruler` 容器（占位与 board 相同）。位置仍用**绝对 rect**，
  --   所以改父级**不会移动任何控件**。
  push({ id = "ruler", kind = "container", parent = "board", rect = rect_of(L.board), style = "ruler" })
  -- 列标尺
  for c = 1, vm.cols do
    push({ id = "ruler.c." .. c, kind = "text", parent = "ruler",
           rect = { x = gx + (c - 1) * (cell + gap), y = L.board.y, w = cell, h = ruler - 6 },
           text = "C" .. c, style = "ruler" })
  end
  -- ★★★ 2026-09-30：**房间名标签**（参考《派蒙的执律庭实习》：每个房间在右下角写房间名，
  --   如 餐厅/厨房/前院/门廊/卧室）。
  --
  --   ⚠️ 关卡数据里**没有房间名**（`rooms` 字段都不存在，房间是从 `walls` 推导的）。
  --     所以这里**不编名字**，而是两级：
  --       · 关卡里写了 `room_names = { "餐厅", "厨房", ... }` ⇒ 用真名
  --       · 没写 ⇒ 显示中性的「区域 1 / 区域 2 …」（位置先占住，名字随时能补）
  --     等你在关卡里填上 `room_names`，这里**不用改一行代码**就会显示真名。
  --
  --   标签放在**房间外框的右下角那一格**里（和参考图的位置一致）。
  if n > 0 then
    -- ⚠️ 这里**不能用 `list`** —— 那是下面"选关界面"分支里的局部变量，
    --   本段在它**之前**执行（我第一版就踩了：`attempt to get length of a nil value`）。
    --   自己从 `self.opts.levels` 取一份。
    local lv_list = {}
    local opt_lv = self.opts.levels
    if type(opt_lv) == "function" then lv_list = opt_lv() or {}
    elseif type(opt_lv) == "table" then lv_list = opt_lv end
    local cur = nil
    local want = tostring(self.opts.current_level or "")
    for i = 1, #lv_list do
      if tostring(lv_list[i].id) == want then cur = lv_list[i] break end
    end
    local boxes = cur and cur.room_boxes or {}
    local names = cur and cur.room_names or nil
    local step = cell + gap
    for j = 1, math.min(#boxes, 8) do
      local b = boxes[j]
      local nm = (type(names) == "table" and names[j]) or ("区域 " .. j)
      -- 右下角那一格的位置；标签占该格的右下 3/4，字号由样式控制
      local lx = gx + (b.c2 - 1) * step + math.floor(cell * 0.18)
      local ly = gy + (b.r2 - 1) * step + math.floor(cell * 0.55)
      push({ id = "room.label." .. j, kind = "text", parent = "board",
             rect = { x = lx, y = ly, w = math.floor(cell * 0.82), h = math.floor(cell * 0.42) },
             text = tostring(nm), style = "room.label", visible = true,
             -- ★ 位置每帧由脚本按房间外框算 ⇒ 必须显式声明"脚本说了算"，
             --   否则会被 `respect_editor_rect`（编辑器几何优先）按在存档里那一份几何上，
             --   三个标签**中心重叠**（真机上是三个字叠在一起，模拟器里 box 完全相同）。
             pos_runtime = true })
    end
    for j = #boxes + 1, 8 do
      -- ⚠️ 占位**也要给真实尺寸**，不能给 2×2。
      --
      --   原因：`layout_plan` 是把**所有关卡**的布局取**并集**（为了让编辑器一次建够控件）。
      --   如果本关房间少、把 `room.label.4` 推成 2×2 隐藏，而并集里"第一次出现"的就是它，
      --   那这个控件的几何就**永久是 2×2** —— 真机上房间名会缩成一个小点。
      --   （我第一版就是这么写的，模拟器里 `room.label.1` 的 box 是 2×2。）
      --   ⇒ 占位沿用**最后一个真实房间**的几何，只是 `visible=false`。
      local last = boxes[#boxes]
      local lx = gx
      local ly = gy
      local lw = math.floor(cell * 0.82)
      local lh = math.floor(cell * 0.42)
      if last ~= nil then
        lx = gx + (last.c2 - 1) * step + math.floor(cell * 0.18)
        ly = gy + (last.r2 - 1) * step + math.floor(cell * 0.55)
      end
      push({ id = "room.label." .. j, kind = "text", parent = "board", visible = false,
             rect = { x = lx, y = ly, w = lw, h = lh }, pos_runtime = true })
    end
  end

  -- 行标尺
  for r = 1, vm.rows do
    push({ id = "ruler.r." .. r, kind = "text", parent = "ruler",
           rect = { x = L.board.x, y = gy + (r - 1) * (cell + gap), w = ruler - 6, h = cell },
           text = "R" .. r, style = "ruler" })
  end
  for r = 1, vm.rows do
    for c = 1, vm.cols do
      local cd = vm.cells[r][c]
      local style = "cell"
      if cd.state == "blocked" then style = "cell.blocked"
      elseif cd.state == "victim" then style = "cell.victim"
      elseif cd.state == "hint" then style = "cell.hint"
      elseif cd.state == "wrong" then style = "cell.wrong" end
      if cd.x then style = "cell.x" end
      -- 键盘光标（PC）：只在真的用过方向键之后才高亮，纯鼠标玩家看不到它
      if self.kb_active and self.kb ~= nil and self.kb.r == r and self.kb.c == c then
        style = "cell.cursor"
      end
      push({
        id = self:cell_id(r, c),
        kind = "button",
        -- ★★★★★ 2026-10-06 **格子的父级从 `board` 改成 `stage`** ✗✓ —— 与真机一致 ✓
        --
        --   为什么（★ 模拟器 play 日志给的铁证 ✓）：
        --     · 模拟器：★「**stage 树上实际有 0 个子控件**」✗
        --       ⇒ ★ 因为计划把格子挂在 **`board`** 下 ✗ ⇒ 脚本按 `stage` 找 ⇒ **找不到** ✓
        --     · 真机：★「stage 树上实际有 **27** 个子控件」✓
        --       ⇒ ★ **真机里格子就是挂在 `stage` 下的** ✓
        --     · 且两边日志都说：★「`board` → **找不到控件**」✗
        --       ⇒ ★★ 即：★ **`board` 在真机上根本不存在** ✗ —— ★ 它只是计划里的历史层 ✓
        --   ⇒ ★★ 所以这一处**不是模拟器的毛病** ✗ —— ★ 是**计划的父子结构与真机不一致** ✓✓
        --     ★ 审计要模拟真机 ✓ ⇒ ★ 必须对齐真机 ✓（★ 而不是迁就模拟器 ✓）
        --   ⚠️ 同一个 `board` 还挂着 `ruler` / `room.label.*` ✗ ——
        --      ★ 它们同样在真机上取不到父级 ✓ 但那是**另一件事** ✗ ⇒ 本轮不动 ✓
        parent = "stage",
        rect = { x = gx + (c - 1) * (cell + gap), y = gy + (r - 1) * (cell + gap), w = cell, h = cell },
        style = style,
        -- ★★★★★ 2026-10-06 **格子的可见性由【规划】统一给** ✗✓ —— 用户说的"合并成一套" ✓
        --
        --   ★ "为什么只有第一关出问题"的答案 ✓（真机日志早就写着 ✓）：
        --     · 第一关：★「本次新建 **25** 个」✗ ← ★ 格子是【开局那一刻】建的 ✓
        --     · 第二关：★「本次新建 **0** 个」✓  ← ★ 复用已存在的 ✓
        --     ⇒ ★ 开局 `screen = "home"` ✗ ⇒ 屏幕层把 `cell.*` 藏掉 ✗
        --       ⇒ ★★ 第一关的格子【一出生就是 hidden】✗ 而屏幕层是**单向**的 ✗
        --          ⇒ **永无恢复** ✓✓（墙/门/底图全灭 ✓）
        --     ⇒ ★ 其它关的格子是【关卡内】建的 ✓ ⇒ 从没被藏过 ✓
        --       ⇒ ★★ 看起来"只有第一关坏"✗ —— 其实是**建格时机不同** ✓
        --     ★ 用户原话：「第一关的棋盘是项目最初的造物」✓
        --       「把第一关的显隐设置与其它关卡合并成一套」✓ —— ★ 判断正确 ✓
        --
        --   ⇒ ★★ 在这里显式给 `visible`：★ 规划**每一次产出都带上它** ✓
        --     · 关卡内（`screen == nil`）⇒ true ✓  ·  主页/选关 ⇒ false ✓
        --     ⇒ ★★★ **所有关卡、所有时机走同一条** ✓✓ —— 这就是"一套" ✓
        --   ⚠️ 不放在屏幕层 ✗（上次那样做过、失败了 ✗）—— 那是**单向**的 ✗
        --     ★ 而规划每一帧都重算 ✓ ⇒ 它才是**双向**且**唯一**的权威 ✓✓
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        -- ★★ 性能待办 ★ 标签 **PERF-2**（★ 2026-10-06 标记 ✓ **先不动** ✗ 等框架稳定再回来 ✓）
        --
        --   ★ 这是**每帧下发**给 25 个格子的那个 `visible` ✓
        --     （★ `layout_plan` 每帧重算 ✓ ⇒ 这一行每帧对 25 个格子各走一次属性下发 ✓）
        --   ★ **字段位置**：★ 就是下面这行 `visible = (self.screen == nil),` ✓
        --     ★ 同类还有 `clues.bg` 的 ★ **L2065** `visible = (self.screen == nil) })` ✓
        --   ★ **为什么归规划管** ✗：★ 屏幕层是**单向**的 ✗（★ 只藏不显 ✓ 上次那样做过、失败了 ✓）
        --     ★ 而规划每帧重算 ⇒ ★ 它是**双向且唯一**的权威 ✓ 见 L2547~2550 ✓
        --   ⇒ ★★ **要省成本，正确顺序** ✓：★ 先确认屏幕层的**对称性** ✓
        --     ★ 再把"每帧下发"改成"**状态变了才下发**"✗ —— ★ **不能直接删** ✓
        --   ★ 配套的那个是 ★ **PERF-1**（`engine_adapter_qianxing.lua` 的每帧重放 ✓）
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        visible = (self.screen == nil),
        -- ★★★★★ 2026-10-05 **格子不再推 `text`**（这一轮每帧成本第 (4) 条）。
        --
        --   真机证据（用户日志里「格子里的子控件清单」那句，**原话**）：
        --       cell.1.1 … 没有配的：**text** obj
        --   —— 格子上**根本没有文字子控件**（`obj` 也没有；`obj` 那一条已经由适配层
        --      按"没有物件就藏起来"处理掉了，是另一件事）。
        --
        --   而适配层 `set_property(id, "text", …)` 的三条路
        --   （① `label` 子控件 ② 控件自己就是文字控件 ③ 老的 `text` 子控件）
        --   **在格子上一条都走不通** ⇒ 必然 `return false`
        --   ⇒ `render` 把它当"这次没送到" ⇒ 按补发额度 `PROP_RETRY`(=3) 重试
        --   ⇒ **每关开头白跑 25 次 `find` + 75 次 `set_property`**
        --      （`tests/grid_cost.lua` 口径 [I] 实测：75 次失败写入 / 25 个格子 × 3 次），
        --      并且把「属性补发…已停止补发」的**前 5 条日志位置全部占掉** ——
        --      真正需要看的那几条（哪些控件本关没建）就此被挤出去。
        --
        --   ⇒ 不再推。格子上要显示的东西本来就靠 `image`（头像）/ `face` / `note` / `x`
        --     四样；**人名走的是线索卡**，从来没有靠过格子文字。
        --
        --   ⚠️ **将来若真的给格子配了文字子控件**：在 `entry_client_script.lua` 的
        --      `cfg.cells` 里加一行 `push_text = true` 即可恢复（`main.lua` 会把它转成
        --      `opts.push_cell_text`）—— **不用改代码**。
        --   ⚠️ **不要**改成"让适配层把这种情况判成 definitive miss、不再重发"：
        --      「`label` 子控件晚一步才进树」是真实存在的（见 `main.lua` 门控②那段
        --      以及适配层 `set_property` 的 text 分支注释），首帧"三条路都不通"与
        --      "这个控件永远没有文字"在**适配层看来长得一模一样** ⇒ 在那边一刀切
        --      会把已经修好的"第一次进关按钮没字"又放回来。
        text = (self.opts.push_cell_text == true and (cd.name or "")) or nil,
        -- ⚠️ 这里**只能传图片 ID（整数）**，不能传名字。
        --
        -- 真机 16:07 日志报过：`SetImage 失败：bad argument #3 to 'SetImage'
        -- (integer expected, got string)`。根因就是这行原来写的是
        --     `… portrait_of(vm, cd.suspect) or cd.object or nil`
        -- 而 `cd.object` 是**家具/物体的名字字符串**（例如「收银台」）。
        -- 当角色没配 `portrait` 时，`and/or` 表达式就掉到 `cd.object` 上，
        -- 于是名字被当成图片 ID 传进了 SetImage。
        --
        -- 现在只传 `portrait`。
        -- ★ 2026-09-26 起 `portrait` 支持**调色板素材名**（字符串）：
        --   例如 `portrait = "portrait.A"`，适配层会用调色板里的 source+id 去 SetImage。
        --   整数 ID 依然兼容。调色板见 engine_adapter_qianxing.lua 的 read_palette。
        -- ⚠️ 用 `false` 而不是 nil 当"这格没有人"：
        --   渲染循环是 `for k, v in pairs(n)` —— **Lua 里 `image = nil` 等于"这个键不存在"**，
        --   于是"人走了的格子"**永远不会下发 image** ⇒ 旧格的头像**永远不清**。
        --   这就是用户报的「换位后头像卡残留」。
        --   （和 `obj` 白块是**同一个 bug 形状** —— 我在同一个坑里摔了两次。）
        image = cd.suspect and Controller.portrait_of(vm, cd.suspect) or false,
        -- ★ 见 `note_list_of` 那段：适配器要**数组** ✓ 核心给的是**集合** ✗（不转 = 永远空串 = 永不显示）
        -- ★★★★★ 2026-10-07 **改用核心那份笔记表** ✗✓（真机探针：写入通道全通、但写进去的是 `1` ✗）
        --   ★ 探针铁证 ✓：★ `诊断NOTECH：写笔记通道=text  文本=1` ✓
        --     ★ `诊断NOTEV：回读text=1  visible=true  fontSize=36  fontColor=4278190080`（黑 ✓）
        --   ⇒ ★ **显示通路完全正常** ✓ ⇒ ★ 唯一的问题是**取的源表错了** ✓✓
        --   ★ 两份表的键不同 ✓：
        --     · 核心 `core.notes[r][c]` = ★ **`{ [人物id]=true }`** ⇒ 键**就是徽章字母** ✓（探针：`{V}` ✓）
        --     · 视图 `cd.notes`        = ★ 键是**数字** ✗ ⇒ `tostring(k)` 得到 `"1"` ✓（正是看到的那个 1 ✓）
        --   ⇒ ★ **以核心为准** ✓（视图那份只当兜底 ✓）
        -- ★★★★★ 2026-10-07 **笔记清空时要下发 `false`（不是 nil）** ✗✓ —— "清掉了但没重画" ✓
        --   ★ 元凶 ✓：★ `note_list_of` 在"没有笔记"时返回 **nil** ✓
        --     ⇒ ★ Lua 里 `notes = nil` 等于**这个键不存在** ✓ ⇒ **适配器永远收不到"该清空"** ✗
        --       ⇒ ★ 屏幕上的字母**留着不动** ✓ —— ★ 于是"正式放置清了笔记"你也看不出来 ✓✓
        --   ★ 项目自己早就吃过同一个坑 ✓（`image` 那条注释写着 ✓ `ui_controller.lua:2677~2680` ✓：
        --     「★ 用 `false` 而不是 nil 当"这格没有人"……否则**旧格的头像永远不清**」✓）
        --   ⇒ ★ 这里照办 ✓：★ 没有笔记时下发 **`false`** ✓ ⇒ 适配器 `txt = ""` ⇒ `SetVisible(false)` ✓
        notes = note_list_of((self.core and self.core.notes and self.core.notes[r]
          and self.core.notes[r][c]) or cd.notes) or false,
        room = cd.room,
        -- ★★ 2026-09-28 新增：**显式告诉适配层"这格有没有物件"**。
        --
        -- 为什么必须传：模板里有个 `obj` 子控件，是留给"物件图标"（书桌/地毯）的，
        --   而且 `layer_order` 故意把它排在 `face` **之上**。
        --   但我当初生成它时用的是**白色占位图**（106053），**而且没有任何代码去关它** ——
        --   于是它永远是"一块白板压在头像上"。
        --   空格看不出来（`face` 本来就是白图），**一放人就变成用户报的
        --   「人物头像上有异常遮挡」**（截图里 C3/R1、C4/R2、C4/R3 那三块白方块）。
        --   ⇒ 每格显式声明 `object`（没有物件就是 nil），适配层据此开关 `obj` 的显隐。
        -- ★★★ 2026-09-30：**物件传的是"素材键"，不是显示名**（为 ⑤ 家具图标铺路）。
        --
        --   关卡里的物件是**中文名做键**的：
        --       objects = { ["书架"] = { cells = {...}, kind = "shelf" }, ... }
        --   而适配层拿这个名字去 `assets` 调色板里查素材 ⇒ 素材名会变成 `obj.书架`。
        --   中文素材名不是不行，但**不好管理**（改名、跨语言、和图集对不上）。
        --   ⇒ 规则：物件定义里写了 `kind` 就用 `obj.<kind>`（ASCII 稳定键），
        --     没写就退回中文名（**不破坏现有数据** —— 老关卡一个字都不用改）。
        --
        --   ⚠️ 没物件时必须是 `false` 而不是 nil：
        --     渲染循环是 `for k, v in pairs(n)` —— Lua 里 `object = nil` 等于"这个键不存在"，
        --     于是没有物件的格子**永远不会下发 object** ⇒ `obj` 白块永远不被隐藏
        --     （这正是用户报的「人物头像上有异常遮挡」，我第一次没修掉）。
        object = Controller.object_key_of(vm, cd) or false,
        -- ★ 每格四边的墙 / 门：数据来自 core 的 `view()`（{up,down,left,right} 布尔表），
        --   适配层靠模板里固定的 `wall.*` / `door.*` 子控件 SetVisible 开关来实现 ——
        --   **不需要为每种墙型做模板**。
        walls = cd.walls,
        doors = cd.doors,
        -- ★ 房间染色：`imageColor` 是**读写**字段，所以"同一张底图 + 不同颜色区分房间"
        --   是零额外素材的做法。颜色表在下面 ROOM_COLORS。
        tint = Controller.room_color(cd.room),
        occupiable = cd.occupiable,
        x_mark = cd.x,
        enabled = true,   -- 不可站人的格子也要能点（用于打 X / 提示原因）
        event = { action = "click", r = r, c = c },
      })
    end
  end

  -- ===== 右侧信息栏 =====
  push({ id = "right", kind = "container", parent = "root", rect = rect_of(L.right), style = "panel.right" })
  -- ⚠️ `hud.progress` **不在这里** —— 它已经挪到右下角和放大镜做伴了
  --   （见文件上半部分的"按参考图重排顶栏与右下角"）。
  --   我第一版忘了删这一份，于是**同名控件建了两个** —— 正是"同名两处必然漂移"的老毛病。
  -- ★★★★★ 2026-10-02 **按用户定稿删除**（参考图里没提到的按键全删）：
  --     `hud.score`（位置正确 N/M）、`hud.violations`（区域推断 + 违规）、
  --     `hud.share`（分享码）、`hud.toast`（提示条）—— 全部**不再 push**。
  --   原来那段还算了 `vm.structure`（区域推断文案），一并删掉 ——
  --   它是给 `hud.violations` 用的，没有控件就不必算。
  --   保留的右栏内容只有：`hud.progress`（右下角，与放大镜同排）——见上面那段。
  -- 顶部放不下的次级操作放这里（1920 内不会溢出）
  local rx = L.right.x + 20
  -- ★★ 2026-09-29：`action.howto` / `action.share` / `action.restart` 三个按钮
  --   **用户已在编辑器里删除** ⇒ 计划里同步移除，否则脚本会去写不存在的控件
  --   （真机日志里 `action.howto` 那几条"读回 nil"就是这么来的）。
  --   ⚠️ `action.back` 保留 —— 它还在你的存档里。
  btn("action.back", "right", { x = rx + 324, y = L.right.y + 680, w = 116, h = 52 }, "返回列表",
      { action = "back" }, "tab")

  -- ★★ 2026-09-29：**整块删掉底部操作条**（`actions` 容器 + 5 个按钮）。
  --
  --   用户在编辑器里把 `actions` 以及 `action.q.*` 全删了（存档记录 231 → 197）。
  --   这五个按钮的功能现在都有更直接的入口：
  --     · 放置工具 / 只写笔记 / 划掉这格 / 橡皮擦
  --         → 由「双击长按=放置、单击=✗、单击已放置格=拿起」承担
  --     · 指认凶手 → 顶部工具条的 `action.submit` 就是它
  --   ⇒ 计划里不再声明，脚本也就不会去写不存在的控件。
  --   （以后要做移动端大按钮，可以从 git 历史取回：提交 2f4b1ea）
  local _ = L.actions    -- 布局表里的坐标先留着，方便将来恢复
  local _ = L.action_btn

  -- ===== 开屏教程 =====
  if self:is_intro_active() then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    local page = M.INTRO[self.intro_page]
    push({ id = "intro", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })
    push({ id = "intro.dots", kind = "text", parent = "intro",
           rect = { x = mx + 40, y = my + 30, w = mw - 80, h = 36 },
           text = string.format("第 %d / %d 页", self.intro_page, #M.INTRO), style = "muted" })
    push({ id = "intro.title", kind = "text", parent = "intro",
           rect = { x = mx + 40, y = my + 80, w = mw - 80, h = 60 }, text = page.title, style = "modal.title" })
    push({ id = "intro.body", kind = "text", parent = "intro",
           rect = { x = mx + 40, y = my + 160, w = mw - 80, h = 180 }, text = page.body, style = "modal.body" })
    btn("intro.skip", "intro", { x = mx + 40, y = my + mh - 90, w = 180, h = 60 }, "跳过",
        { action = "intro_skip" }, "tab")
    btn("intro.next", "intro", { x = mx + mw - 240, y = my + mh - 90, w = 200, h = 60 },
        (self.intro_page >= #M.INTRO) and "开始破案" or "下一页", { action = "intro_next" }, "stamp.primary")
  end

  -- ===== 弹窗 =====
  local modal = self.modal
  if modal and not self:is_intro_active() then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    push({ id = "modal", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })

    if modal.kind == "accuse_thief" or modal.kind == "accuse_accomplice" then
      local is_acc = (modal.kind == "accuse_accomplice")
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 26, w = mw - 60, h = 56 },
             text = is_acc and "那同伙是谁？" or "摆位成立。谁是盗窃者？",
             style = "modal.title" })
      local per = 3
      for i = 1, #vm.tray do
        local it = vm.tray[i]
        if not (is_acc and it.id == modal.thief) then
          local col = (i - 1) % per
          local row = math.floor((i - 1) / per)
          push({ id = "modal.suspect." .. tostring(it.id), kind = "button", parent = "modal",
                 rect = { x = mx + 40 + col * 232, y = my + 110 + row * 128, w = 212, h = 110 },
                 text = it.name, image = it.portrait, style = "portrait",
                 event = is_acc and { action = "accuse_pick_accomplice", id = it.id }
                                 or { action = "accuse_thief", id = it.id } })
        end
      end
      if is_acc then
        btn("modal.no_accomplice", "modal",
            { x = mx + 40, y = my + mh - 88, w = 280, h = 60 }, "他独自作案（没有同伙）",
            { action = "accuse_no_accomplice" }, "stamp")
      end
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "再看看",
          { action = "close_modal" }, "tab")

    elseif modal.kind == "result" then
      local got, total = self.core:score()
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 40, w = mw - 60, h = 60 },
             text = modal.win and "破案！" or "没能找齐所有人", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 120, w = mw - 60, h = 120 }, text = modal.message or "", style = "modal.body" })
      push({ id = "modal.stats", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 250, w = mw - 60, h = 40 },
             text = string.format("用时 %s · 误指认 %d 次 · 位置 %d/%d",
                                  self:format_time(vm.hud.time), vm.hud.failed_accusations, got, total),
             style = "muted" })
      btn("modal.again", "modal", { x = mx + 40, y = my + mh - 88, w = 180, h = 60 }, "重玩本关",
          { action = "restart" }, "stamp")
      -- ★ 2026-10-05 **「分享棋局」按钮已删掉**（用户指令：「去掉分享」）。
      --   这里原来是一个 `modal.share` 按钮（文字「分享棋局」，事件名就是 `share`），
      --   但 `share` **从来没有分发分支** ⇒ 按下去没反应（`check_actions` 改前报的 2 个死 action 之一）。
      --   ⚠️ 这段注释里**故意不写出那条事件的完整字面量**：`check_actions.mjs` 是**逐行正则扫源码**，
      --      连注释一起扫（`action\s*=\s*"..."`）⇒ 注释里写出旧代码的字面量会被当成"又发了一次"，
      --      于是它又会红。要复现旧行为，看 `versions/` 里的历史版本即可。
      --   渲染分支 `modal.kind == "share"` **保留**，理由写在下面那一段注释里。
      --   ⚠️ `modal.again` / `modal.next` 的坐标与文字**一个字都没动**。
      btn("modal.next", "modal", { x = mx + 440, y = my + mh - 88, w = 200, h = 60 }, "下一关",
          { action = "next_level" }, "stamp.primary")

    elseif modal.kind == "exit_menu" then
      -- ★★★★★ 2026-10-09 **几何改为【设计稿 B】** ✗✓（用户 2026-10-09 拍板选 B ✓）
      --   ★ 设计稿 B（画布空间 1600×900）✓：
      --     · 键尺寸 **312×60** ★ 横间距（pitch）**80** ★ cx=800（面板水平居中 ✓）
      --     · 四个键的**中心** cy = **570 / 490 / 410 / 330** ✓（面板中心 450 ⇒ 上下对称 ✓）
      --   ★ 换算到**脚本空间**（1920×1080，`M.DESIGN`）✓：画布 × 1.2 ✓
      --     · w = 312×1.2 = **374** ✓ · h = 60×1.2 = **72** ✓ · pitch = 80×1.2 = **96** ✓
      --     · cx = 800×1.2 = **960** ⇒ x = 960 − 374/2 = **773** = `mx + (mw−374)/2` ✓
      --   ★★ `rect.y` 的语义（★ 本项目把 ①③ 写反过 ✗，这里写死讲清 ✓）：
      --     · **`y` = 从父控件【顶边】往下数的偏移** ✓（不是左下原点的 cy ✗）
      --     · 面板 `modal` 顶边 = `my + mh` ⇒ 目标中心 y 对应的偏移
      --       = `mh − (cy_script − my) − h/2`
      --     · 逐个算 ✓：exit 50 · save 146 · settle 242 · cancel 338
      --       （校验：my+mh−偏移−h/2 = 684 / 588 / 492 / 396 ⇒ ÷1.2 = 570/490/410/330 ✓ 与设计稿一致 ✓）
      --   ★ 为什么改脚本就够 ✓：`root` 带 `pos_runtime = true`
      --     ⇒ `inherit_pos_runtime`（本文件 :1361）**沿子树继承** ⇒ `modal` 与这四个键
      --     **都算"运行时控件"** ⇒ 适配器每帧下发脚本算出的几何 ✓
      --     ⇒ ★ `.gil` 里那套 480×56 **运行时不生效** ✓（★ 这正是「编辑器预览是 480×56、
      --        进关卡却是另一套」的由来 ✓ —— PLAN.md A4 说的「A/B 二选一」其实一直是 B 在跑 ✓）
      --   ⚠️ 存档 `.gil` 里的 480×56 与 `label` 的 559×20 **仍待同步**（见 `接手待办.md` A4 备注 ✓）
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("modal.exit", "modal", { x = kx, y = my + 50, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("modal.save", "modal", { x = kx, y = my + 146, w = kw, h = kh },
          "仅存档", { action = "exit_menu_save" }, "stamp")
      btn("modal.settle", "modal", { x = kx, y = my + 242, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary")
      btn("modal.cancel", "modal", { x = kx, y = my + 338, w = kw, h = kh },
          "取消", { action = "close_modal" }, "tab")

      -- ★★★★★ 2026-10-07 **给四个键设【官方胶囊底图】** ✗✓（用户要求配图 ✓）
      --   ★ 为什么走脚本而不是改 `.gil`：`docs/官方素材方案-脚本一体化.md` 已论证
      --     「**官方素材 + 脚本 = 图 / 色 / 尺寸 / 位置全可运行时改**」⇒ 配图本来就该脚本做 ✓
      --     （团队连改 4 轮 `.gil` 记录数组都卡在手工下标上 ✗ 这条路整个绕开 ✓）
      --   ★ 素材：★ **`107179`**（760×152，两端全圆角、米白）—— 与用户截图里的胶囊按钮同形 ✓
      --     `set_image_deep` 会自己往下找带 `SetImage` 的子控件（= 按钮的 `bg` ✓），
      --     并沿用控件自己编辑器里配的图集（`bg` 的 imageSource = 官方图集 ✓）✓
      --   ★ 只做一次（每帧设图会白烧成本 ✓ 本项目对每帧成本敏感 ✓）。
      -- ★★★★★ 2026-10-07 **只给 `bg` 子控件设胶囊底图** ✗✓（用户要求配图 ✓）
      --   上一版用 `set_image_deep(按钮, …)`：它"找第一个带 SetImage 的子控件"
      --   ⇒ 真机很可能命中 `label`（文字控件也有 SetImage）⇒ **图盖在文字上 ⇒ 图文都没了**
      --   （对照：加它之前"有字无图" ✓ 加它之后"图文都没有" ✗ ⇒ 变量只有这一个 ✓）
      --   ⇒ 现在**显式指名 `bg`**（`Adapter:sub(id, "bg")` ✓ 它就是按钮的底图那一层 ✓）
      --   素材 ★ **107179**（760×152 · 两端全圆角米白）= 用户选定 ✓ 沿用控件自己的官方图集 ✓
      -- ★ 2026-10-08 **守卫【外面】的探针** ✓（★ 真机：里面那两条一行没打 ✗ ⇒ 根本没进来 ✓）
      --   ★ 要分清两种可能 ✓：★ ① `self.adapter` 此刻是 nil ✗ ★ ② `_exit_menu_art` 已被置真 ✗
      if (self._art_gate_log or 0) < 6 then
        self._art_gate_log = (self._art_gate_log or 0) + 1
        -- ★★★★★ 2026-10-08 **渲染分支置标记** ✗✓（★ 本行已证"弹窗开着时每帧都跑" ✓ 真机日志可证 ✓）
        --   ★ 为什么只置标记 ✓：★ 这里的 `self.adapter` **是 nil** ✗（★ 真机连打 6 次全 false ✓）
        --     ⇒ ★ 本处**只报告"弹窗此刻开着"** ✓ ★ 读 `bg` 的活儿交给"拿得到 adapter"的那一侧 ✓
        --   ★ 标记 = 一个递增计数 ＋ 最近一次的时间戳 ✓（★ 两侧靠它对齐 ✓）
        self._modal_seen = (self._modal_seen or 0) + 1
        print("[murdoku] ★ 胶囊底图：到守卫  adapter=" .. tostring(self.adapter ~= nil)
          .. "  闩锁=" .. tostring(self._exit_menu_art))
      end
      if (not self._exit_menu_art) and self.adapter ~= nil then
        self._exit_menu_art = true
        for _, bid in ipairs({ "modal.exit", "modal.save", "modal.settle", "modal.cancel" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          -- ★ 2026-10-08 探针：★ `bg` 取到没 ✓（★ 取不到 ⇒ 与 `assets` 同源 ✗ 按名取子控件 ✓）
          if (self._art_log or 0) < 8 then
            self._art_log = (self._art_log or 0) + 1
            local _sz = "?"
            pcall(function() _sz = tostring(bg and (bg.sizeDelta and (bg.sizeDelta.x .. "x" .. bg.sizeDelta.y) or "无sizeDelta")) end)
            print("[murdoku] ★ 胶囊底图：bid=" .. tostring(bid) .. "  bg=" .. tostring(bg ~= nil) .. "  size=" .. _sz)
          end
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
          if (self._art_log2 or 0) < 8 then
            self._art_log2 = (self._art_log2 or 0) + 1
            local _rb = nil
            pcall(function() _rb = tostring(bg and bg.imageId) end)
            print("[murdoku] ★ 胶囊底图：设图后回读 imageId=" .. tostring(_rb))
          end
          end
        end
      end
    elseif modal.kind == "share" then
      -- ★ 2026-10-05 **这一支目前没有入口按钮**（用户当天决定去掉「分享棋局」按钮，
      --   见上面 `modal.kind == "result"` 里那段删除说明）。
      --
      --   **故意留着**，不是忘了删：
      --     · 链路还在 —— `a == "accuse"` 分支仍会 `core:encode_state()` 并构造
      --       `{ kind = "share", code = ... }`，`opts.on_share` 也仍在回调；
      --     · 将来要接**真实分享**（真正的分享面板/复制码）时，只要再加回一个按钮即可，
      --       不必把这一屏重写一遍；
      --     · 代价是零 —— 它只在"别处主动构造 share 弹窗"时才可能出现，平时不进任何计划。
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 30, w = mw - 60, h = 56 }, text = "分享棋局", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 110, w = mw - 60, h = 200 },
             text = "把这个码发给别人，对方可以还原你的棋盘：\n\n" .. tostring(modal.code), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "关闭",
          { action = "close_modal" }, "tab")

    elseif modal.kind == "levelselect" then
      -- ===== 选关 =====
      -- 关卡清单由 main.lua 通过 opts.levels 传进来（界面层不认识 Levels 模块）
      local list = self.opts.levels or {}
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 24, w = mw - 60, h = 56 },
             text = "选择关卡", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 84, w = mw - 60, h = 34 },
             text = string.format("已登记 %d 关 · 当前：%s", #list, tostring(vm.title or "")),
             style = "muted" })
      local per = 2
      local col_w = math.floor((mw - 100) / per)
      for i = 1, math.min(#list, 8) do
        local it = list[i]
        local col = (i - 1) % per
        local row = math.floor((i - 1) / per)
        local cur = (tostring(it.id) == tostring(self.core.level and self.core.level.id))
        btn("modal.level." .. tostring(it.id), "modal",
            { x = mx + 40 + col * (col_w + 20), y = my + 126 + row * 82, w = col_w, h = 68 },
            string.format("%s%s", cur and "▶ " or "", tostring(it.name or it.id)),
            { action = "pick_level", id = it.id },
            cur and "stamp.primary" or "stamp")
      end
      if #list > 8 then
        push({ id = "modal.body", kind = "text", parent = "modal",
               rect = { x = mx + 30, y = my + 126 + 4 * 82, w = mw - 60, h = 34 },
               text = string.format("（这里只列出前 8 关，共 %d 关）", #list), style = "muted" })
      end
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "关闭",
          { action = "close_modal" }, "tab")

    elseif modal.kind == "howto" then
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 26, w = mw - 60, h = 56 }, text = "玩法", style = "modal.title" })
      local text = {}
      for i = 1, #M.INTRO do
        text[#text + 1] = string.format("%d. %s —— %s", i, M.INTRO[i].title,
                                        M.INTRO[i].body:gsub("\n", " "))
      end
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 100, w = mw - 60, h = 280 },
             text = table.concat(text, "\n\n"), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "知道了",
          { action = "close_modal" }, "tab")
    end
  end

  -- ★★★ 2026-09-29：**主页 / 选关的整屏切换**。
  --
  --   ⚠️ 两个容器**每一帧都要显式给可见性**，不能只在 `screen ~= nil` 时处理 ——
  --      我第一版在"进入关卡"（screen == nil）时直接 return 了，
  --      于是主页/选关控件**留在关卡画面上**（美术检查报"棋盘区域有 1 个多余控件"）。
  --      原因：这两个容器在 `.gil` 里默认是可见的（要给编辑器里能看见、能调），
  --      所以**运行时必须由脚本负责关掉**。
  -- ★★★★ 2026-10-01 **真机"卡死"的最终修法：容器不再覆盖屏幕**。
    --
    --   为什么：`home` / `select` 铺满 1600x900 之后就成了**全屏射线靶子** ——
    --   它把**游戏自己的 UI（退出按钮）**都盖住、点不到，用户报"只能选关进去、出不来了"。
    --
    --   改成 1x1 放在屏幕正中：**子控件是相对父级中心定位的**，父级中心没变
    --   （仍是屏幕中心 (800,450)）⇒ **子控件坐标一个都不用动**，
    --   而容器本身小到不可能挡住任何东西。
    --
    --   同时把 `home.*` / `select.*` 的**父级改挂到 `root`**（见下面各 push），
    --   所以容器缩水不会让子控件被裁 —— 而且有证据：诊断三那个探针控件就挂在 `root` 下、
    --   尺寸 600x300、用户确认**看得见** ⇒ root 的子控件不被裁。
    --
    --   ⚠️ 这两个常量（`FULL` 和 `FULLSCREEN`）**都要改** —— 我第一版只改了
    --      `FULLSCREEN`，而计划里取的是**第一次** push 的几何 ⇒ 白改一次。
    local FULL = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }
  push({ id = "home", kind = "container", parent = "root", rect = FULL,
         visible = (self.screen == "home"), pos_runtime = true })
  push({ id = "select", kind = "container", parent = "root", rect = FULL,
         visible = (self.screen == "select"), pos_runtime = true })

  if self.screen ~= nil then
    -- ★★★ 2026-10-01：**改成"反向逻辑"**（原来是白名单，漏了一大片）。
    --
    --   旧写法是一张 9 个 id 的白名单：
    --     { topbar, toolbar, left, board, right, toast, modal, intro, action.back }
    --   于是 **clues / action.undo·submit·reveal·hint·redo / hud.\* / cell.\*** 全都没被藏
    --   ⇒ **主页上能同时看到棋盘格子、线索条、右侧三个按钮**。
    --   （布局审计工具 tools/sim/audit_layout.mjs 抓到的：
    --      home period 下 cell.1.1 / clue.1 / action.undo / hud.title 的 visible 都是 true。）
    --
    --   白名单每加一个新控件都得记得补一次，**必然会漏**（这次就漏了一片）
    --   ⇒ 反过来：**只保留 home / select 这几棵子树 + root**，其余一律藏。
    --     以后再加控件，默认就是"进入关卡才显示"，不会漏。
    -- ★★★ 2026-10-01 二次修正：**从"反向逻辑"改回"白名单"**。
    --
    --   我原来想用反向逻辑（只保留 home/select 子树，其余全藏）来根治"漏藏"，
    --   但真机实测结果是 **整个界面空白** —— 太危险了：
    --     · 它是**默认隐藏**：任何状态/顺序/时机上的意外，代价都是"全都看不见"
    --     · 白名单是**默认显示**：漏掉某个新控件，代价只是"多显示了一个" ——
    --       而且布局审计（tools/sim/audit_layout.mjs）能当场抓出来
    --   ⇒ **可恢复的错 > 不可恢复的错**，改回白名单，但这次写全。
    --
    --   白名单内容 = 关卡内才该出现的东西（按 id + 按前缀两类）。
    --   新增关卡内控件时**记得补一笔**，补完跑一次布局审计确认。
    -- ★★★★★ 2026-10-05 **这一段"内联白名单隐藏"整段删掉** —— 它和下面那次重复 push 一起，
    --   是"选关页/主页看着不动也在烧 CPU"的真正来源。
    --
    --   它错在哪（可复现，`tools/_probe_setvis.lua`）：
    --     判据写的是**全局 `screen`** —— `build_layout` 里根本没有这个局部变量
    --     ⇒ 恒为 nil ⇒ `hide = (nil ~= "home")` **恒真**
    --     ⇒ 它把上面刚 push 的 `home` / `select` **每一帧都改成 `visible=false`**；
    --     而紧接着（原 L2582-2585）又 push 了**第二份** `home` / `select`
    --     （`visible = (self.screen == …)`）把可见性"救"回来
    --     ⇒ 计划里从此有**两个同 id 的节点**，而属性账本 `self._props` 是**按 id** 记账的
    --     ⇒ 两个节点每帧互相覆盖，永远收敛不了：
    --         第 N 帧：节点1 写 visible=false（和上一帧节点2 写的 true 不同）
    --         第 N 帧：节点2 写 visible=true （和节点1 刚写的 false 不同）
    --         第 N+1 帧：一模一样再来一遍
    --   实测代价（选关页稳态 60 帧）：
    --     · `tools/_probe_setvis.lua`：`select.visible` **每帧真写 2 次**（true/false 各一）；
    --     · 而 `set_property` 的 visible 分支会置 `_subtree_dirty`（那是兜底隐藏的触发源）
    --       ⇒ **`enforce_hidden_subtrees` 每帧都被重新触发**（实测 65 帧跑 65 次）
    --       ⇒ 146 次 `SetVisible`/帧、1230 次 `GetChildren`/帧
    --         （`tests/grid_cost.lua` 的小树上同一件事是 6 次 / 62 次）。
    --
    --   为什么可以整段删：这两件事**都已经有一份正确的实现** ——
    --     · 函数末尾的 `apply_screen_hide(nodes, self.screen)`：判据是**参数** `screen`
    --       （就是这里想读却读不到的那个值），而且它的 HIDE/PREFIX 名单是这里内联版的
    --       **超集**（多 `selbar` / `tpl-container` / `hex.` / `hit.` / `selbtn.` / `tpl.`
    --        以及"另一个屏幕的前缀"）⇒ 内联这段能藏的，它全藏；
    --     · `home` / `select` 的可见性：上面那次 push 的
    --       `visible = (self.screen == "home"/"select")` 已经给对了。
    --   ⇒ 删除后**行为一字不变**，只是每帧那两笔互相打架的写入消失了。
    --     （"同一件事两处实现必然漂移"是本项目反复踩到的病 —— 这就是最新的一例。）
    -- ★★★★ 2026-10-01 **真机"卡死"的最终修法**：容器**不再铺满屏幕**。
    --
    --   为什么：`home` / `select` 铺满 1600x900 之后就成了**全屏射线靶子** ——
    --   它把**游戏自己的 UI（退出按钮）**都盖住、点不到，用户报"卡死"。
    --   改成 1x1 放在屏幕正中：**子控件是相对父级中心定位的**，
    --   父级中心没变（还是屏幕中心）⇒ **子控件坐标一个都不用动**，
    --   而容器本身小到不可能挡住任何东西。
    --
    --   为什么敢这么做：诊断三那个探针控件是**挂在 `root` 下面**的，用户确认看得见
    --   ⇒ 说明**子控件不会被父级尺寸裁掉**（`root` 是全屏、探针 600x300 正常显示）。
    -- ★★★★★ 2026-10-05 **原来这里还有一份 `home` / `select` 的重复 push —— 已删**（见上）。
    --
    --   它俩和上面那次 push **几何完全相同**（`FULLSCREEN` 与 `FULL` 都是 0,0,DESIGN 尺寸），
    --   存在的唯一作用就是把上面那段内联隐藏错判掉的可见性"救"回来。
    --   内联那段既然删了，这一份也就只剩坏处：
    --     · 计划里多两个同 id 节点 ⇒ `render` 的属性循环对一个控件发两遍；
    --     · 一旦两处 `visible` 写得不一样，就是上面那种"每帧互相覆盖"的无限打架。
    --   ⚠️ 以后要改这两个容器的几何/可见性，**只改上面那一处**（L2521-2525）。
    if self.screen == "home" then
      -- ★★★★★ 2026-10-05 **A8 的出口②= `home.title`** —— 主页那两条提示的唯一出口。
      --
      --   为什么主页要单独一个：`apply_screen_hide` 在主页/选关把**整片 `hud.` 前缀**藏掉
      --   （见那张 HIDE/PREFIX 表），所以「商城 / 背包」这两条提示**在主页上没有出口** ✗。
      --   而主页上**存在**的文本控件只有 `home.title` 和四个按钮的标签
      --   （实测 `208-补active.gil`：`home.title` / `home.select` / `home.continue` /
      --     `home.shop` / `home.bag` 各 1 条；`select.*` **一条都没有** ⇒
      --     选关页（「还没有游玩记录…」会切到那一屏）**没有任何出口**，那一条仍然看不到 ——
      --     已如实记在探针与本轮回复里，**不假装解决** ✗）。
      --   ⇒ 点「商城 / 背包」时，主页那行大字直接变成提示语；到点自动变回 `M.HOME_TITLE`。
      push({ id = "home.title", kind = "text", parent = "root", visible = true,
             text = self:toast_text() or M.HOME_TITLE,
             rect = { x = 460, y = 140, w = 1000, h = 110 } })
      -- 中列四键。用户要求：原左边的「选关」挪到**中列最上**，原位置（左下角）留空。
      local HOME_BTNS = {
        { "home.select",   "选关",         "levelselect", 360 },
        { "home.continue", "从存档点开始", "continue",    480 },
        { "home.shop",     "商城",         "shop",        600 },
        { "home.bag",      "背包",         "bag",         720 },
      }
      for i = 1, #HOME_BTNS do
        local b = HOME_BTNS[i]
        push({ id = b[1], kind = "button", parent = "root", visible = true,
               rect = { x = 730, y = b[4], w = 460, h = 88 },
               text = b[2], event = { action = b[3] } })
      end
    elseif self.screen == "select" then
        local list = {}
        local lv = self.opts.levels
        if type(lv) == "function" then list = lv() or {}
        elseif type(lv) == "table" then list = lv end
        local PER = 8
        local total = #list
        local pages = math.max(1, math.ceil(total / PER))
        local page = tonumber(self.select_page) or 1
        if page < 1 then page = 1 end
        if page > pages then page = pages end
        self.select_page = page          -- 夹紧后存回去，免得越界状态一直留着
        local lst_base = (page - 1) * PER
        -- ⚠️⚠️ `opts.levels` 在 main.lua 里传的是**表**（`levels = level_list`），不是函数！
        --   我第一版写成 `self.opts.levels()` ⇒ `attempt to call a table value (field 'levels')`
        --   ⇒ **build_layout 直接抛错、整个渲染崩掉**。
        --   ⚠️ 2026-10-01 又踩一次：我挪分页变量段时用 TrimStart 把这几行**吃掉了**，
        --      报 `attempt to get length of a nil value (global 'list')`。
        --      ⇒ 挪代码不要用 TrimStart 粗暴裁切，会连注释和相邻语句一起带走。

        push({ id = "select.title", kind = "text", parent = "root", visible = true, text = "选择关卡",
             rect = { x = 460, y = 80, w = 1000, h = 90 } })
      push({ id = "select.back", kind = "button", parent = "root", visible = true,
             rect = { x = 120, y = 950, w = 260, h = 80 },
             text = "返回主页", event = { action = "home" } })
        -- ★★★ 2026-10-01：**选关翻页**（关卡多于 8 个时才有意义）。
        --   只有一页时整组隐藏（`visible=false`），不占视觉。
        local pg_visible = (pages > 1)
        if pg_visible then
          push({ id = "select.prev", kind = "button", parent = "root",
                 visible = (page > 1), text = "上一页",
                 rect = { x = 700, y = 950, w = 220, h = 80 },
                 event = { action = "select_page", delta = -1 } })
          push({ id = "select.next", kind = "button", parent = "root",
                 visible = (page < pages), text = "下一页",
                 rect = { x = 1000, y = 950, w = 220, h = 80 },
                 event = { action = "select_page", delta = 1 } })
          push({ id = "select.page", kind = "text", parent = "root", visible = true,
                 text = string.format("第 %d / %d 页", page, pages),
                 rect = { x = 930, y = 955, w = 60, h = 70 } })
        else
          push({ id = "select.prev", kind = "button", parent = "root", visible = false,
                 rect = { x = 700, y = 950, w = 220, h = 80 } })
          push({ id = "select.next", kind = "button", parent = "root", visible = false,
                 rect = { x = 1000, y = 950, w = 220, h = 80 } })
          push({ id = "select.page", kind = "text", parent = "root", visible = false,
                 rect = { x = 930, y = 955, w = 60, h = 70 } })
        end
      -- ⚠️⚠️ `opts.levels` 在 main.lua 里传的是**表**（`levels = level_list`），不是函数！
      --   我第一版写成 `self.opts.levels()` ⇒ `attempt to call a table value (field 'levels')`
      --   ⇒ **build_layout 直接抛错、整个渲染崩掉**，
      --   表现成"主页激活时画不出东西 / 提交后不弹指认面板"。
      --   我为此查了三轮（`and/or` 陷阱、屏幕默认值、优先级），**全是白费** ——
      --   真正的错误信息一直在运行日志里，我没去看。
      --   ⇒ 教训：**改完先看运行时报错，再谈推断**。
      local list = {}
      local lv = self.opts.levels
      if type(lv) == "function" then list = lv() or {}
      elseif type(lv) == "table" then list = lv end
              -- ★★★ 2026-10-01：**加分页**。
        --
        --   原来固定 `for i = 1, 8 do local it = list[i]` ⇒ **只有前 8 关能选**，
        --   第 9 关之后**根本没有卡片**（关卡多起来就是死路）。
        --   现在：8 个卡位不变，翻页只换"从第几个关卡开始"。
        --
        --   为什么不做滚动列表：卡片是 2 行 × 4 列的大格子（含棋盘缩略图），
        --   一屏正好 8 张；翻页比滚动更贴合"选关"这个动作。
        
        for i = 1, 8 do
          local it = list[lst_base + i]
        local r = { x = 160 + ((i - 1) % 4) * 420, y = 240 + math.floor((i - 1) / 4) * 240,
                    w = 380, h = 200 }
        if it ~= nil then
          -- ★★★ 2026-09-30：卡片改成**三段**（参考《派蒙的执律庭实习》的选关卡片：
          --   上面一条"关名"纸条、中间是**该关棋盘的缩略图**、下面一行"人数/进度"）。
          --   原来是一整块按钮 + 多行文字 —— 缩略图没地方放（文字会盖在它上面）。
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, event = { action = "pick_level", id = it.id } })
          local t = self:level_card_parts(it)
          push({ id = "select.card." .. i .. ".title", kind = "text", parent = "root",
                 visible = true, text = t.title, style = "card.title",
                 rect = { x = r.x + 16, y = r.y + 10, w = r.w - 32, h = 34 } })
          push({ id = "select.card." .. i .. ".info", kind = "text", parent = "root",
                 visible = true, text = t.info, style = "muted",
                 rect = { x = r.x + 16, y = r.y + r.h - 42, w = r.w - 32, h = 32 } })
          self:push_room_thumb(push, "select.card." .. i, it, r, "select")
        else
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          -- 空卡片的三个附件也要显式隐藏 —— 否则上一屏的内容会**残留在空位上**
          for _, suf in ipairs({ ".title", ".info" }) do
            push({ id = "select.card." .. i .. suf, kind = "text", parent = "root", visible = false,
                   rect = { x = r.x, y = r.y, w = 1, h = 1 } })
          end
          self:push_room_thumb(push, "select.card." .. i, nil, r, "select")
        end
      end
    end
    -- ⚠️ **主页/选关这条提前 return 之前也必须调** —— 否则这两个屏幕的子树
    --    拿不到继承过来的 `pos_runtime`，子控件继续用编辑器里的锚点+偏移
    --    ⇒ 实际落到屏幕外（就是"界面空白"的直接原因）。
    apply_screen_hide(nodes, self.screen)
      inherit_pos_runtime(nodes)
    return nodes
  end

  -- ★★★★ 2026-10-01 **界面空白的最后一环（用户实测定位）**：
  --   `pos_runtime` 必须**沿子树继承** —— 详见函数外 `inherit_pos_runtime` 的注释。
  --   这一处是**关卡路径**的收口；主页/选关那条提前 return 之前也调了一次。
  apply_screen_hide(nodes, self.screen)
    inherit_pos_runtime(nodes)

  return nodes
end
-- ────────────────────────────────────────────────────────────────────────
-- 布局计划：把 build_layout() 摊平成「画布空间」清单，
-- 供 ① 模拟器建树脚本 ② 编辑器搭建指南生成器 共用同一份数据。
-- 每项：{ id, kind, parent, style, cx, cy, w, h, text, visible, states }
-- cx/cy 就是编辑器「位置 X, Y」要填的数（pivot 设 0.5,0.5）。
--
-- ★ 必须**遍历所有界面状态**再取并集：弹窗（指认/结果/分享/玩法）和开屏教程
--   的控件只在对应状态下才出现在 build_layout() 里。如果只按开局那一屏生成，
--   编辑器里就会缺 modal.* / intro.* —— 脚本运行时按名字找不到，面板永远出不来。
-- ────────────────────────────────────────────────────────────────────────
-- 关卡卡片文字（murdoku 原作那种：关名 + 进度）。
-- ⚠️ 文字存不进 .gil，只能脚本写；进度拿不到就只显示关名 —— **不编数据**。
-- ★★★ 2026-09-30：**选关卡片显示什么**（参考《派蒙的执律庭实习》的卡片，
--   见 `docs/美术改造规格-参考执律庭实习.md` 第一节）。
--
--   参考图每张卡片 = **关名（米色纸条）+ 棋盘缩略图 + 「NxN　M名嫌疑人+1名受害人」**。
--   文字只能脚本写（存不进 `.gil`），所以这里生成：
--
--     案件 001 · 夜盗独行
--     5x5　4名嫌疑人+1名受害人
--     ★ 已破案 / · 进行中 / 未开始
--
--   ⚠️ 取值一律**从关卡数据里读**，读不到就**不写那一行** —— 不编数据
--   （比如 `size` 缺失就只显示关名，而不是硬写一个 "5x5"）。
-- ★★★ 2026-09-30：**选关卡片的三段内容**（参考《派蒙的执律庭实习》的卡片）。
--
--   卡片现在是"标题 / 缩略图 / 说明"三段，所以文字也拆成两块：
--     · `select.card.N.title` —— 关名（上面那条）
--     · `select.card.N.info`  —— 「NxN　M名嫌疑人+1名受害人」+ 进度（下面那行）
--   缩略图夹在中间（见 `push_room_thumb`）。
--
--   取值规则同前：**从关卡数据里读，读不到就不写那一行** —— 不编数据。
function Controller:level_card_parts(it)
  local title = tostring(it.name or it.id)
  local bits = {}
  local sz = it.size
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local total = type(it.suspects) == "table" and #it.suspects or nil
  if rows and cols and total and total >= 2 then
    bits[#bits + 1] = string.format("%dx%d　%d名嫌疑人+1名受害人", cols, rows, total - 1)
  elseif rows and cols then
    bits[#bits + 1] = string.format("%dx%d", cols, rows)
  end
  local p = self.opts.progress and self.opts.progress(it.id) or nil
  if type(p) == "table" then
    local mark = "未开始"
    if p.cleared then mark = "★ 已破案"
    elseif p.started then mark = "· 进行中" end
    bits[#bits + 1] = mark
  end
  return { title = title, info = table.concat(bits, "　") }
end

-- 房间色块的配色（**只在这里定义一处**）。
--
--   为什么是"色块"而不是"逐格"：参考图的缩略图就是几块彩色区域。
--   逐格要 rows×cols 个控件（最多 49 个）× 8 张卡 = 392 个，太多；
--   色块只要"每关房间数"个（本项目每关 3 个）⇒ 8×6 = 48 个上限，可控。
--
--   ⚠️ 素材用的是**整数 id 106053（白）**，靠 `imageColor`（乘算着色）出颜色。
--     `assets` 里目前只有 9 张头像、**没有房间类素材**，所以不能写 "room.xxx"
--     这种调色板名（那只对 assets 里存在的名字有效）。
--     等美术资源齐了，把这里换成真实素材名即可（一行改）。
local ROOM_TINT = {
  4285965944,   -- 暖米（餐厅一类）
  4282326293,   -- 淡蓝（厨房一类）
  4285241469,   -- 草绿（前院一类）
  4290036043,   -- 浅紫
  4291078505,   -- 浅橙
  4291603827,   -- 灰蓝（兜底/第 6 个房间）
}
local ROOM_MAX = 6          -- 一关最多画几个房间色块
local WHITE_MAT = 106053    -- 真机日志里确认过的白底素材 id

function Controller:push_room_thumb(push, cardId, it, cardRect, parent)
  -- 缩略图区域：卡片中间那块（上面留给标题、下面留给说明）
  local area = { x = cardRect.x + 24, y = cardRect.y + 50,
                 w = cardRect.w - 48, h = cardRect.h - 50 - 48 }
  local boxes = it and it.room_boxes or nil
  local sz = it and it.size or nil
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  for j = 1, ROOM_MAX do
    local id = cardId .. ".room." .. j
    local b = (type(boxes) == "table") and boxes[j] or nil
    if b ~= nil and rows and cols then
      -- 把"第几行第几列"按比例映射进缩略图区域（不依赖任何素材尺寸）
      local cw = area.w / cols
      local ch = area.h / rows
      local x = area.x + math.floor((b.c1 - 1) * cw)
      local y = area.y + math.floor((b.r1 - 1) * ch)
      local w = math.max(2, math.floor((b.c2 - b.c1 + 1) * cw))
      local h = math.max(2, math.floor((b.r2 - b.r1 + 1) * ch))
      -- ★ 位置按**每个关卡**的房间外框算 ⇒ 必须 `pos_runtime`（理由同房间名标签：
      --   否则会被 `respect_editor_rect` 按在存档里那一份几何上，
      --   8 张卡片的缩略图会**全挤成同一块**）。
      push({ id = id, kind = "button", parent = parent, visible = true,
             rect = { x = x, y = y, w = w, h = h },
             image = WHITE_MAT, tint = ROOM_TINT[(j - 1) % #ROOM_TINT + 1], pos_runtime = true })
    else
      -- 占位也给**真实尺寸**（沿用它上面的区域），只是隐藏 ——
      -- 原因同房间名标签：跨关卡取并集时"第一次出现"的几何会留下，
      -- 给 2×2 的话真机上色块会缩成一个点。
      push({ id = id, kind = "button", parent = parent, visible = false,
             rect = { x = area.x, y = area.y, w = math.max(2, math.floor(area.w / 4)),
                      h = math.max(2, math.floor(area.h / 4)) }, pos_runtime = true })
    end
  end
end

-- ★★★ 2026-09-30：**物件 → 素材键**（家具图标用）。
--
--   关卡里的物件是**中文名做键**的（`["书架"] = {...}`），而适配层拿这个名字
--   去 `assets` 调色板查素材 ⇒ 素材名会变成 `obj.书架`。中文素材名不好管理
--   （改名、跨语言、和图集对不上）。
--
--   ⇒ 规则：
--     · 物件定义里写了 `kind = "shelf"` ⇒ 用 `obj.shelf`（ASCII 稳定键，推荐）
--     · 没写 ⇒ 退回中文名（**不破坏现有数据**，老关卡一个字都不用改）
--
--   ⚠️ 一定要查"当前关卡"的物件表。`vm` 里只有**这一格是什么物件**（名字），
--     没有 kind —— kind 在关卡数据的 `objects` 里。
function Controller.object_key_of(vm, cd)
  if cd == nil or cd.object == nil or cd.object == false or cd.object == "" then return nil end
  local name = tostring(cd.object)
  local kind = nil
  local list = vm and vm.object_defs
  if type(list) == "table" then
    local def = list[name]
    if type(def) == "table" then kind = def.kind end
  end
  if type(kind) == "string" and kind ~= "" then return "obj." .. kind end
  return "obj." .. name
end

function Controller:level_card_text(it)
  local name = tostring(it.name or it.id)
  local lines = { name }

  -- 第二行：网格尺寸 + 人数（都能读到才写）
  local sz = it.size
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local total = type(it.suspects) == "table" and #it.suspects or nil
  if rows and cols and total and total >= 2 then
    -- `suspects` 里**含受害人**（case_001 是 A/B/C/D + V）⇒ 嫌疑人数 = total − 1
    lines[#lines + 1] = string.format("%dx%d　%d名嫌疑人+1名受害人", cols, rows, total - 1)
  elseif rows and cols then
    lines[#lines + 1] = string.format("%dx%d", cols, rows)
  end

  -- 第三行：进度（只有真的查得到记录才写）
  local p = self.opts.progress and self.opts.progress(it.id) or nil
  if type(p) == "table" then
    local mark = "未开始"
    if p.cleared then mark = "★ 已破案"
    elseif p.started then mark = "· 进行中" end
    if type(p.best) == "string" and p.best ~= "" then mark = mark .. "　" .. p.best end
    lines[#lines + 1] = mark
  end

  return table.concat(lines, "\n")
end

function Controller:layout_plan()
  local saved_intro, saved_modal = self.intro_page, self.modal
  -- ★★★ 2026-09-30：**屏幕状态也要纳入枚举**。
  --   `layout_plan` 原来只枚举 8 种"关卡内"状态（intro / modal 各变体），
  --   **从不设置 `self.screen`** ⇒ 主页和选关的控件**永远进不了布局计划**
  --   ⇒ 模拟器建树时压根没有 `home.select` 这些控件：点不到、也没法验证。
  --   我为此查了半天"为什么点主页按钮没反应"，最后打印计划才发现控件不在里面。
  local saved_screen = self.screen
  local vm0 = self.core:view()
  local first_id = vm0.tray[1] and vm0.tray[1].id

  local states = {
    -- ★ 整屏状态排最前：编辑器/模拟器要按这份清单建控件
    { name = "home",              intro = 99, modal = nil, screen = "home" },
    { name = "select",            intro = 99, modal = nil, screen = "select" },
    { name = "intro",             intro = 1,  modal = nil, screen = nil },
    { name = "board",             intro = 99, modal = nil, screen = nil },
    { name = "accuse_thief",      intro = 99, modal = { kind = "accuse_thief" }, screen = nil },
    { name = "accuse_accomplice", intro = 99,
      modal = { kind = "accuse_accomplice", thief = first_id }, screen = nil },
    { name = "result",            intro = 99,
      modal = { kind = "result", win = true, message = "（结果文案）" }, screen = nil },
    { name = "share",             intro = 99,
      modal = { kind = "share", code = "（分享码）" }, screen = nil },
    { name = "howto",             intro = 99, modal = { kind = "howto" }, screen = nil },
    { name = "levelselect",       intro = 99,
      modal = { kind = "levelselect" }, screen = nil },
    -- ★★★★★ 2026-10-09 **补 `exit_menu`（四键退出弹窗）** ✗✓
    --   ★ 为什么必须在这里 ✓：★ 本清单是**全状态并集**的唯一来源 ✓，它同时喂给
    --     · 模拟器控件树（`tools/sim/kit.mjs:23` 的 `loadPlan()` **直接读 `layout-plan.json`** 建树 ✓）
    --     · 编辑器搭建表（`docs/控件坐标表-1600x900.md`，由同一个 plan 生成 ✓）
    --     · 批量生成器（`tools/gil/gen_bulk.mjs` ✓）
    --   ★ 少了这一条会怎样 ✗（★ 实测 ✓）：★ `build_layout()` 里
    --     `elseif modal.kind == "exit_menu"`（本文件 :2958）那四个 `btn(...)`
    --     **永远不被 layout_plan 采集** ✗ ⇒ `layout-plan.json` 里**没有**
    --     `modal.exit / modal.save / modal.settle` ✗ ⇒
    --       · 模拟器建出来的树没有它们 ⇒ 适配器 `find()` 失败 ⇒
    --         真机/模拟器日志出现「这些控件还没建 ×3」✗（**8/13 与 15/15 两步审计就是这样红的** ✓）
    --       · 搭建表也不列它们 ⇒ **一旦照表重建界面，四键会被漏掉** ✗
    --   ★ 与 `kit.mjs:152-161` 记的是**同一种病** ✓：那一处是 `bg`/`label` 被写进 `.gil`
    --     却不在 plan 里 ⇒ 模拟器缺件；这一处是四个键本身不在 plan 里 ✓
    --     ⇒ ★ 修法统一：**让 plan 覆盖到真实存在的东西** ✓（而不是在模拟器里继续手工补件 ✓）
    --   ★ 为什么之前漏了 ✓：`docs/弹窗-线索汇总.md` §7 第 1 步列的 5 块里，
    --     入口分支 / 三动作 / 渲染分支 / DECOR 都补了，**唯独「计划状态 exit_menu」没补** ✓
    --   ⚠️ `modal.cancel` 本来就在 plan 里（被 accuse_thief / howto / levelselect 等
    --     6 个状态共用 ✓）⇒ ★ 它一直正常 ✓ —— 这正是「四个键只有一个好使」的出处 ✓
    { name = "exit_menu",         intro = 99, modal = { kind = "exit_menu" }, screen = nil },
  }

  local order, byId = {}, {}
  for si = 1, #states do
    local st = states[si]
    self.intro_page = st.intro
    self.modal = st.modal
    self.screen = st.screen
    local nodes = self:build_layout()
    for i = 1, #nodes do
      local n = nodes[i]
      local cv = M.to_canvas(n.rect)
      local prev = byId[n.id]
      if prev == nil then
        prev = {
          id = n.id, kind = n.kind, parent = n.parent, style = n.style,
          cx = cv.cx, cy = cv.cy, w = cv.w, h = cv.h,
          text = n.text, visible = (n.visible ~= false),
          states = {},
            -- ★ 2026-10-01：**图片素材/颜色/旋转也要进计划** —— 否则 sync_plan 建图片控件时
            --   拿不到 image_id，新控件会带上原型（wall.right）的图。
            --   链条：build_layout → **这里** → tools/dump_layout.lua → sync_plan.mjs，
            --   三处都要带（我漏了两处，image_id 一路是 undefined）。
            image_id = n.image_id, imageColor = n.imageColor, rot = n.rot,
            -- ★★★★★ 2026-10-04 **`event` 也必须进计划** —— 和上面 `image_id` 是**同一类链子问题**：
            --   这里是**再建一张新表**、字段写死，`build_layout` 里挂的 `event` 会被整片丢掉。
            --   后果：导出的规划表里 `event` 全是 nil（实测 **0 / 322**），
            --   于是"这个按钮点下去有没有动作"**完全无法核对** ——
            --   我这一轮给七个 `hex.*` 图标加了 `event`，导出来却仍是 `动作=undefined`，
            --   差点误判成"没设上"。只取 `action`（适配层就是按它分发）。
            action = n.event and n.event.action or nil,
            -- ★★★★★ 2026-10-05 **`event` 整表也必须进计划** ✗✓ —— 第 3 项"点格子没反应"的最后一环 ✓
            --
            --   为什么（**真机 vs 模拟器的唯一差别** ✓ 三段切开 + 静态定位出来的 ✓）：
            --     · **真机**：`build_layout()` 直接建控件 ⇒ `node.event` 是**完整表** ✓
            --       ⇒ `engine_adapter_qianxing.lua:816` 的守卫
            --         `if node.event ~= nil and (node.kind == "button" or node.kind == "cursor")`
            --         **放行** ✓ ⇒ `bind_input` 跑 ✓ ⇒ 格子上**有监听器** ✓
            --     · **模拟器**：`dump_layout` → 计划 JSON → `kit.mjs` 建树 ✗
            --       ⇒ 计划里原来**只有扁平的 `action`** ✗（实测 `"event"` **0 次** ✓）
            --       ⇒ `node.event == nil` ✗ ⇒ ★ **守卫拦掉** ✗ ⇒ **从不 `bind_input`** ✓
            --       ⇒ ★ **模拟器里任何控件都没有监听器** ✗ ⇒ 点击到不了脚本 ✗ ⇒ `0 / 5` ✓✓
            --   ★ 实测互证（两个独立代理 ✓）：
            --     · `[T3Q] _fire#` 在 4 次点击后出现 **0 次** ✓ ⇒ 点击根本没进 `_fire` ✓
            --     · 计划里 369 个节点**没有一个带 `event`** ✓
            --   ★★ 为什么这**不是**"放宽断言" ✗ —— ★ **是让模拟器【忠实还原真机】** ✓✓
            --     真机的节点本来就有 `event` ✓ ⇒ 计划也该有 ✓（否则模拟器测的是另一棵树 ✓）
            --   ⚠️ **`action` 必须保留** ✗ —— `sync_plan.mjs` 等消费者按它工作 ✓ 只是【再加】一个字段 ✓
            --   ⚠️ 参考：`image_id`（2026-10-01）与 `action`（2026-10-04）是**同一类链子问题** ✓
            --     ★ 这次是第三次：**`event` 的值为 nil** 与 **`event` 这个键不存在**，是两回事 ✗✓
            event = n.event,
        }
        byId[n.id] = prev
        order[#order + 1] = prev
      end
      prev.states[#prev.states + 1] = st.name
      -- 文案取「在某个状态里可见」的那一份
      if (n.visible ~= false) and prev.visible == false then
        prev.text = n.text
        prev.visible = true
      end
    end
  end

  self.intro_page, self.modal, self.screen = saved_intro, saved_modal, saved_screen

  -- 初始可见性：只有「开局就该看见」的控件才是可见的，其余交给脚本按状态开关。
  -- （脚本每次 render 都会把 visible 同步过去，所以这里留 false 最安全。）
  for i = 1, #order do
    local it = order[i]
    local in_board = false
    for k = 1, #it.states do
      if it.states[k] == "board" or it.states[k] == "intro" or it.states[k] == "accuse_thief"
         or it.states[k] == "accuse_accomplice" or it.states[k] == "result"
         or it.states[k] == "share" or it.states[k] == "howto" then in_board = true end
    end
    it.visible = in_board and it.visible
  end
  return order
end

-- ────────────────────────────────────────────────────────────────────────
-- 头像卡的「画布空间几何」。
--
-- 为什么要单独给适配层一份：头像卡的**列数按人数自适应**（保证只占 2 行），
-- 于是同一张 tray.A 在 5 人关和 7 人关里位置/尺寸都不一样。编辑器每个控件
-- 只能有一套几何，所以做法是「编辑器按最挤的情况静态摆好，运行时按本关
-- 实际人数重新摆正」—— 和棋盘格子同一套思路。
--
-- 这里算**画布绝对坐标**；适配层只负责换算成「相对父级中心的偏移」再应用，
-- 避免两处各自推导导致差 1px。
-- ────────────────────────────────────────────────────────────────────────
function Controller:tray_layout_canvas()
  local L = M.LAYOUT
  local vm = self.core:view()
  local n = #vm.tray
  if n == 0 then return nil end

  local gx = L.tray_gap_x or 12
  local gy = L.tray_gap_y or 10
  local per_row = math.max(L.tray_per_row or 3, math.ceil(n / 2))
  local item_w = math.floor((L.tray.w - (per_row - 1) * gx) / per_row)
  local item_h = L.tray_item_h

  local tray_cv = M.to_canvas(rect_of(L.tray))
  local items = {}
  for i = 1, n do
    local col = (i - 1) % per_row
    local row = math.floor((i - 1) / per_row)
    local cv = M.to_canvas({
      x = L.tray.x + col * (item_w + gx),
      y = L.tray.y + row * (item_h + gy),
      w = item_w, h = item_h,
    })
    items[#items + 1] = {
      id = "tray." .. tostring(vm.tray[i].id),
      cx = cv.cx, cy = cv.cy, w = cv.w, h = cv.h,
    }
  end
  return { tray_cx = tray_cv.cx, tray_cy = tray_cv.cy, per_row = per_row, items = items }
end

function Controller:placed_count(vm)
  local n = 0
  for i = 1, #vm.tray do if vm.tray[i].placed then n = n + 1 end end
  return n
end

function Controller:violations_text(vm)
  if #vm.violations == 0 then return "当前没有硬性冲突" end
  local lines = {}
  for i = 1, #vm.violations do lines[#lines + 1] = "· " .. vm.violations[i].text end
  return table.concat(lines, "\n")
end

-- 房间染色表：同一张底图 + 不同 imageColor 就能区分房间 —— **零额外素材**。
--
-- 官方依据：`ClientUIImageControl.imageColor` 是 `ColorValue` 类型、**读写**、
-- Tweenable；ColorValue 由全局函数 `Color(r,g,b,a?)` 创建（0–255，a 可省略）。
-- 适配层会把它落到格子的 `face` 子控件上（见 set_property 的 "tint" 分支）。
--
-- 改这里就能换配色；不想要染色就把整张表清空（返回 nil → 适配层跳过）。
Controller.ROOM_COLORS = {
  { r = 214, g = 196, b = 160 },   -- 1 暖木色
  { r = 178, g = 200, b = 208 },   -- 2 冷灰蓝
  { r = 206, g = 178, b = 200 },   -- 3 淡紫
  { r = 190, g = 206, b = 176 },   -- 4 淡绿
  { r = 220, g = 190, b = 170 },   -- 5 陶土
  { r = 186, g = 190, b = 210 },   -- 6 石板
}

-- 注意：这是**普通函数**不是方法（同 portrait_of 的坑）
function Controller.room_color(room)
  if type(room) ~= "number" then return nil end
  local t = Controller.ROOM_COLORS
  if type(t) ~= "table" or #t == 0 then return nil end
  return t[((room - 1) % #t) + 1]
end

-- 注意：这是**普通函数**不是方法，所以不能用 self:portrait_of(vm, id) 调用
-- （冒号调用会把 self 当第一个参数，vm 就变成控制器了 —— 这个坑已经踩过一次）
function Controller.portrait_of(vm, id)
  if not vm or not vm.tray then return nil end
  for i = 1, #vm.tray do
    if vm.tray[i].id == id then return vm.tray[i].portrait end
  end
  return nil
end

----------------------------------------------------------------------------
-- ★★★★★ 2026-10-05 网格视窗（官方列表控件 `clues.grid`）—— 线索卡列表的正路
--
-- 用户的硬原则（原话）：
--   「位置大小都是原本摆好的，脚本只需要管可见性和交互，其它的干涉都是只会增加错误的操作」
-- ⇒ 本段代码**一个坐标都不碰**，只做四件事：**找控件 / 填内容 / 收点击 / 显隐**。
--   规划节点那条 `pos_runtime = false` 就是这条原则的落地（见 `build_layout` 里的注释）。
--
-- 已核对的事实（来自用户存档 `193.1.gil`，不再重复推导）：
--   · 网格视窗：id **1073742420**、名字 `clues.grid`、父 `clues`、400×544、局部 (20,20)
--   · 列表项模板：id **1073742421**（名 `clue`）、360×96，
--     子控件名 `clue.1.backrop1` / `clue.1.backrop2` / `clue.1.letter` /
--              `clue.1.what` / `clue.1.face` / `clue.1.who`
--   · 官方 API（`docs/api-cache/mhtakr07vej4.txt` 第 20 节 `ClientUIGridScrollerControl`）：
--       itemCount(只读) / itemPrefabIndex(读写) / scrollProgress(读写, Tweenable)
--       RefreshItems(itemCount, fun(control, index)) / GetItemIndex(control)
--       GetItemSize() / GetItemSpacing() / GetPadding() / ScrollToItemAt(index, align)
--     基础控件那边有：GetChild(name) / FindChild(path) / SetVisible / AddCursorEventListener
--   · 它是**客户端控件**（`ClientUI*`），和 `cell.*` 同一族 ⇒ 客户端脚本够得着。
--
-- ★ 三条官方语义决定了写法（都能在 API 缓存里查到）：
--   ① 「列表发生滚动时：对列表项内容进行刷新(触发回调)」
--      ⇒ 回调**会被反复进入**，而且是在我们那次 RefreshItems 之后很久（滚动时）。
--      ⇒ 回调里**只允许"按 index 现算"**：不许累加、不许假设只跑一次、
--        不许把"上一次填了什么"当输入（那是"复用列表项"最容易出的错）。
--   ② 「列表项索引以运行时传入和返回的 index 为准」
--      ⇒ 点到了哪一条，只能问 `grid:GetItemIndex(item)` 反查；
--        **不能**按兄弟序号（items 会被复用，顺序不稳定）。
--   ③ 回调的参数是 `(control, index)`，返回空 —— 内容全靠我们往子控件里写。
--
-- ⚠️ 已知**未验证**的能力（真机上要盯的两件事，见日志里的两行结论）：
--   · 列表项**能不能收到光标事件**（`AddCursorEventListener`）—— 官方没写死，
--     所以每一次调用都包 `pcall`，收不到就只失去"点列表项聚焦"这一个附加功能；
--   · **滚动由谁驱动**（引擎自身手势 / 还是脚本写 `scrollProgress`）—— 本轮不猜，
--     失败/不适用时把 `cfg.use_grid` 改回 false 就整体回到手写滚动。
----------------------------------------------------------------------------

-- 官方枚举的安全取值（与适配器里的 `E()` 同一个写法：缺失时返回 nil，调用点降级不崩）。
-- ⚠️ 离线测试里 `Enum` 是**全局 nil**（tests/board_bg.lua 故意不给），所以这里必须 nil-safe。
local function enum_at(path)
  local cur = Enum
  if cur == nil then return nil end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return nil end
  end
  return cur
end

-- 往一个控件写文字：文字控件才有 `text` 字段，写不进去不算错（返回 false 让调用方记账）。
--
-- ★ 空字符串**照写**（用户明确要求）：不写的话，"上一条残留的文字"会留在复用出来的
--   列表项上 —— 那是"滚动之后内容错位"的经典成因。空文字无害，残留有害。
local function write_control_text(ctrl, txt)
  if ctrl == nil or ctrl.text == nil then return false end
  local ok = pcall(function() ctrl.text = tostring(txt or "") end)
  return ok
end

-- 「这条结论只打一次」的小工具：能不能用、点了有没有反应，打一次就够，别每帧刷屏。
function Controller:_grid_log(key, msg)
  self._grid_logged = self._grid_logged or {}
  if self._grid_logged[key] then return end
  self._grid_logged[key] = true
  if print then print("[murdoku] " .. tostring(msg)) end
end

-- 网格视窗这条路上的**任何一步失败**都走这里：退回老路径（手写滚动），并且只报一次。
function Controller:_grid_fail(why)
  if self._grid_broken then return end
  self._grid_broken = true          -- 记住失败 ⇒ 以后不再重试（免得每帧刷同一句话）
  -- ★★★★★ 2026-10-05 **初值从 `"off"` 改成 `nil`** ✗✓ —— "线索区没出来"的**第二个原因** ✓
  --
  --   症状（真机日志 `23:13:32` 的排行榜 ✓）：
  --     · `clues.grid` 400x544 可见=**false** ✗ —— 而日志【同时】说
  --       「网格视窗：找到 clues.grid ✓ … RefreshItems 回调 7 次」✓ ⇒ ★ 它明明启用成功了 ✓
  --
  --   为什么：★ 规划里 `clues.grid` 的可见性是 `visible = (self._grid_state ~= "off")` ✓
  --     ⇒ ★ 只要 `_grid_state` 还是 `"off"` ✗ ⇒ **规划就把它写成 false** ✗✓
  --     ⇒ 而 `sync_clue_grid` 是**后面**才跑并把状态改掉的 ✓
  --     ⇒ ★★ 于是"启用成功之前的那些帧"它一直是 false ✗
  --        —— 而渲染的账本一旦记下 `visible=false`，之后没再变过就不会重发 ✗✓
  --
  --   ⇒ ★ 初值用 `nil`（= **还没判定** ✓）：`nil ~= "off"` 为真 ✓ ⇒ **规划先按"显示"给** ✓
  --     ★ 只有 `sync_clue_grid` **真的判定失败**时才会变成 `"off"` ✗ ⇒ 那时才藏 ✓✓
  --     ★ 这正是注释里那句"走不了网格视窗时把它藏起来"的原意 ✓ —— 原来那个 `"off"`
  --       把"还没判定"和"判定失败"**混成了同一个值** ✗（本项目反复踩的"两个状态一个值"✓）
  self._grid_state = nil
  self.dirty = true                 -- 让下一帧重画
  self:_grid_log("fail", "网格视窗：失败（" .. tostring(why)
    .. "）⇒ 退回老路径（手写滚动：▲▼ + 滚动条 + clue.N 卡片）")
end

-- ── 每帧渲染前调一次 ─────────────────────────────────────────────────────
-- 顺序：开关 → 找控件 → 取模板索引 → 设 itemPrefabIndex → RefreshItems 填内容。
-- 只有"这一步真的成了"才会把 `_grid_state` 置成 "on"，`build_layout` 据此让老的一套让位。
function Controller:sync_clue_grid(adapter)
  if adapter == nil or adapter.find == nil then return end

  -- ① 开关：默认**开**；只有显式 `false` 才完全不碰网格视窗
  local cfg = adapter.cfg
  if cfg ~= nil and cfg.use_grid == false then
    if self._grid_state == nil then
      self._grid_state = "off"
      self:_grid_log("off_cfg", "网格视窗：cfg.use_grid=false ⇒ 按配置走老路径（手写滚动）")
    end
    return
  end

  -- ② 只在**关卡里**碰它：主页/选关时这块区域整个是藏起来的（父级 `clues` 不可见），
  --    那时去 RefreshItems 既没意义、又可能因为"控件不可见 ⇒ 引擎不建列表项"而误判失败。
  -- ★★★★★ 2026-10-07 **"从别的屏回到关卡"时解开封死的网格判定** ✗✓
  --   用户实测（老问题 ✓）：
  --     · 退出至菜单 → 重进【同一关】⇒ 网格视窗**不渲染** ✗
  --     · 换一关进 ⇒ 正常 ✓   再换回来 ⇒ 正常 ✓   再退出重进 ⇒ 又不正常 ✗
  --   ⇒ 分水岭：**同一个控制器只改 `screen`** ✗  vs  **新控制器（`start_other`）** ✓
  --   机制：本函数下面的 `if self._grid_broken then return end` 是**永久闩锁** ✗ ——
  --     选关那一屏 `screen ~= nil` ⇒ 函数直接 return ✓ 但**之前**在关卡里若已判定失败，
  --     闩锁就留着了 ⇒ 重进同一关 ⇒ 永远 return ⇒ `_grid_state` 停在 "off"
  --     ⇒ 规划里 `clues.grid` 的 `visible` 恒为 false ⇒ **永不显示** ✓
  --   ⇒ 修法：★ **检测 `screen` 从"非 nil"跃迁到"nil"（= 刚进关卡）⇒ 允许重试一次** ✓
  --     换关走 `start_other` 是新建控制器 ⇒ 本来干净 ⇒ 不受影响 ✓
  if self.screen == nil and self._grid_last_screen ~= nil then
    self._grid_broken = nil
    self._grid_tries = 0
    self._grid_state = nil
    self._grid = nil
  end
  self._grid_last_screen = self.screen  if self.screen ~= nil then return end

  -- ③ 已经失败过就不再重试（老路径接管；`_grid_state` 已经是 "off"）
  if self._grid_broken then return end

  -- ④ 找控件：先 `clues.grid`（存档里核对过的名字），找不到再用中文名兜一次
  local grid = self._grid
  if grid == nil then
    -- 前 120 次渲染每次都试（约 2 秒）：控件是存档里就有的，正常情况下第一次就能拿到；
    -- 万一 UI 树还没就绪，也给足重试机会。之后不再试，免得每帧白扫一遍控件树。
    if (self._grid_tries or 0) >= 120 then return end
    self._grid_tries = (self._grid_tries or 0) + 1
    pcall(function() grid = adapter:find("clues.grid") end)
    if grid == nil then
      -- 防御（一行）：万一编辑器里用了中文名「网格视窗」
      pcall(function() grid = adapter:find("网格视窗") end)
    end
    if grid == nil then
      self:_grid_log("missing", "网格视窗：找不到 `clues.grid`（也试过中文名「网格视窗」，"
        .. "已经试了 " .. tostring(self._grid_tries) .. " 次）⇒ 继续走老路径（手写滚动）")
      if self._grid_tries >= 120 then
        -- 试满就**判定"这一关没有网格视窗"**：把它按不可用处理（`clues.grid` 保持隐藏），
        -- 老路径独占这块区域 —— 免得"找不到 ⇒ 一直重试 + 网格和老卡片同时亮着"。
        self._grid_state = "off"
        self:_grid_log("missing_final", "网格视窗：试满 120 次仍拿不到控件 ⇒ 判定不可用，"
          .. "`clues.grid` 由脚本按不可见处理，老路径（手写滚动）接管")
      end
      return
    end
    self._grid = grid
  end

  -- ⑤ 列表项模板索引：**只从 cfg 取**，这里不写死数字
  --    （数字的唯一来源在 main.lua 的 `Murdoku.GRID_ITEM_PREFAB` —— 两处写死必然漂移）
  local prefab = cfg and cfg.clues_grid_prefab
  if type(prefab) ~= "number" or prefab <= 0 then
    if not self._grid_no_prefab then
      self._grid_no_prefab = true
      self._grid_state = "off"
      self:_grid_log("noprefab", "网格视窗：cfg.clues_grid_prefab 没有配置 ⇒ 不启用"
        .. "（继续走老路径；模板索引请填在 main.lua）")
    end
    return
  end

  -- ⑥ 填内容：只在**条数变了**时重发 RefreshItems。
  --    官方写明滚动时引擎自己会再进回调 ⇒ 这里不必每帧重发
  --    （每帧重发会把滚动位置顶回去，而且纯属浪费）。
  --
  -- ★★★★★ 2026-10-05 **条数别再用 `core:view()` 去数** —— 那个守卫挡不住它。
  --
  --   实测（`tests/grid_cost.lua`）：`_grid_sig` 这道守卫**确实**挡住了重复的
  --   `itemPrefabIndex` 写入与 `RefreshItems`（300 帧里 grid_refresh=0），
  --   但它**挡不住**守卫之前那句 `self.core:view()`：整视图重建 **0.235 ms/次**，
  --   而 `render` 在真机上是**每帧**都跑的（`Controller:tick` 每帧 `self.dirty = true`，
  --   `Murdoku.on_update` 见 dirty 就重绘 —— 离线实测 300 帧 = 300 次 render）。
  --   ⇒ 白白每帧多花 0.235 ms（还要多制造一批垃圾表给 GC）。
  --   条数与 `#vm.clues` **恒等**（`Core:clue_results()` 对 `level.clues` 一对一映射），
  --   所以直接数关卡数据即可，一个字节的语义都没变。
  local lv = self.core and self.core.level
  local n = #((lv and lv.clues) or {})
  local sig = tostring(n)
  if self._grid_state == "on" and self._grid_sig == sig then return end

  local ok_set, set_err = pcall(function() grid.itemPrefabIndex = prefab end)
  if not ok_set then
    self:_grid_fail("设 itemPrefabIndex 失败：" .. tostring(set_err))
    return
  end
  -- 回读一份当证据（只读字段在某些实现上会滞后，所以**不作为失败依据**，只打进日志）
  local back = nil
  pcall(function() back = grid.itemPrefabIndex end)

  self._grid_calls = 0          -- 这一次 RefreshItems 里回调被进入了几次
  -- ⚠️ **不要重置 `_grid_base`**：它只在"这辈子第一次回调"时判定（那一次一定是列表顶端，
  --    因为列表刚建、还没滚动过）。重置的话，"条数变了但滚动位置还在中间"时会把
  --    中间那一项的 index 当成起点 ⇒ 0 起的那种实现会被误判成 1 起 ⇒ 整列错位一条。
  --
  -- ★ `_grid_in_refresh` 用来区分「回调是被**我们这次调用**带进来的」还是「引擎在滚动时
  --   自己重进的」 —— 后者是**本项目一个关键的未验证点**，见到就报一行（见 `_fill_grid_item`）。
  self._grid_in_refresh = true
  local ok_ref, ref_err = pcall(function()
    grid:RefreshItems(n, function(item, index)
      -- ★ 官方：滚动时**引擎会再进这个回调** ⇒ 这里再包一层 pcall：
      --   万一某一行出错，只该"这一次没填上"，**不该把引擎的滚动一起打断**。
      local ok_cb, cb_err = pcall(function() self:_fill_grid_item(adapter, grid, item, index) end)
      if not ok_cb then self._grid_cb_err = tostring(cb_err) end
    end)
  end)
  self._grid_in_refresh = false

  local calls = self._grid_calls or 0
  if (not ok_ref) or (calls == 0 and n > 0) then
    self:_grid_fail("RefreshItems " .. ((not ok_ref) and ("抛错：" .. tostring(ref_err))
      or ("一次回调都没进来（n=" .. tostring(n) .. "）")))
    return
  end

  self._grid_sig = sig
  self._grid_state = "on"

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-09 **几何探针：把引擎【自己算出来】的那几个数打出来** ✗✓
  --
  --   ★ 为什么需要它 ✓（用户原话 ✓）：
  --     「我能在线索卡可见区域内选中三个，而**第一行上方还有可选中内容**，
  --       滚轮列表**之上**的区域我选到了第四个人，也就是说**原本的填入方式有问题**，
  --       确实把线索**填到了不该有的地方**」✗
  --     ⇒ ★ 换成选关条就是"**填进去的关卡错位**" ✓ 同一个根 ✓
  --
  --   ★ 官方原文给的两条（`get_client_document("网格视窗控件")` ✓）：
  --     · ★「列表采用**复用列表**结构，出于性能考虑，**仅会加载处于可见范围内的列表项**」✓
  --       ⇒ 引擎**自己就裁剪** ✓ ⇒ 所以"填多了不裁"**不是**原因 ✗
  --     · ★「**排列限制和预览数量**：将**预览数量**对应的列表项展示在界面中，
  --         以**模拟实际运行时**的效果」✓
  --       ⇒ ★ 存档里 `#80/511 = 5` 只是**编辑器预览数量** ✓ **不是运行时限制** ✗
  --
  --   ★ 而官方**没有**说明的两件（所以只能实测 ✓）：
  --     ① 列表项模板自己的**位置**算不算数？（模板 `clue` 实测在 `(-6, 212)` ✗ 不在 (0,0)）
  --     ② `scrollProgress` 归不归零？（★ 若用户滚过 ⇒ 列表上移 ⇒ "第一行"其实不是第一项）
  --
  --   ★★ 好在这几个官方接口**都能运行时读** ✓（`ClientUIGridScrollerControl` ✓）：
  --     `itemCount`(只读) · `scrollProgress`(读写) · `GetItemSize()` · `GetItemSpacing()`
  --     `GetPadding()` · `GetContentLength()` · `scrollDirection`(只读) · `layoutConstraint`(只读)
  --     `layoutConstraintFixedCount`(只读)
  --   ⇒ ★ **一次就能算出**"引擎认为内容有多长" vs "视窗有多高" ✓
  --     · 若 `GetContentLength()` == 视窗高 ⇒ ★ 内容没超 ⇒ 但用户看到了第 4 个人 ⇒ **错位** ✗
  --     · 若 `scrollProgress` ≠ 0 ⇒ ★ 列表被滚上去了 ⇒ **"第一行"不是第一项** ✓✓
  --     · 若 `GetItemSize()` ≠ 存档里的 360×96 ⇒ ★ 引擎用的不是存档那个尺寸 ⇒ 布点基准不同 ✓
  --   ⇒ ★ 这一行日志能一次分清上面三种 ✓ —— 别再猜 ✓
  if (self._grid_geom_log or 0) < 3 and print then
    self._grid_geom_log = (self._grid_geom_log or 0) + 1
    local _f = function(fn)
      local vals = nil
      pcall(function() vals = { fn() } end)
      if vals == nil then return "读不到" end
      local out = {}
      for i = 1, #vals do out[i] = tostring(vals[i]) end
      return table.concat(out, ",")
    end
    local _one = function(k)
      local v = nil
      pcall(function() v = cg[k] end)
      return tostring(v)
    end
    local _cg2 = grid
    if _cg2 == nil then pcall(function() _cg2 = adapter:find("clues.grid") end) end
    if _cg2 ~= nil then
      local _sz = "读不到"
      pcall(function() _sz = tostring(_cg2.sizeDeltaX) .. "×" .. tostring(_cg2.sizeDeltaY) end)
      print("[murdoku] ★ 网格几何1（引擎自己算的）: "
        .. "itemCount=" .. _one("itemCount")
        .. "  **scrollProgress=" .. _one("scrollProgress") .. "**"
        .. "  itemSize=" .. _f(function() return _cg2:GetItemSize() end)
        .. "  spacing=" .. _f(function() return _cg2:GetItemSpacing() end)
        .. "  padding=" .. _f(function() return _cg2:GetPadding() end))
      print("[murdoku] ★ 网格几何2: **GetContentLength=" .. _f(function() return _cg2:GetContentLength() end)
        .. "**  视窗自身 sizeDelta=" .. _sz
        .. "  scrollDirection=" .. _one("scrollDirection")
        .. "  layoutConstraint=" .. _one("layoutConstraint")
        .. "  fixedCount=" .. _one("layoutConstraintFixedCount"))
      print("[murdoku] ★ 网格几何3（读法）: 内容长度 > 视窗尺寸 ⇒ 有得滚 ✓；"
        .. "**scrollProgress ≠ 0 ⇒ 列表已上移 ⇒ 你看到的「第一行」不是第一项** ✗；"
        .. "itemSize 与存档里的 360×96 不一致 ⇒ 引擎用的不是存档那个尺寸")
    end
  end

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **绕过规划/账本，直接点亮 `clues.grid`** ✗✓ —— 真凶在此 ✓
  --
  --   ★ 为什么规划那条路不行（★ 诊断2 真机实测 ✓）：
  --     ★ 规划 `visible=**true**` ✓ · `在nodes=true` ✓ · `在seen=true` ✓ · `上帧在shown=true` ✓
  --     ★★ 而★ **读回 `visible=false`** ✗✗ ⇒ ★ **属性【发了也无效】** ✓✓
  --   ★★ 铁证（★ 同一份日志里 ✓）：★ 诊断二手动 `SetVisible(true)` ⇒ **回读仍 `false`** ✗✓
  --     ★ 而★ 构建标记自己写着 ✓：
  --       ★「要显示时**显式补 `SetActive(true)`**（★ 手写树漏写 `active` **会少一层可见性**）」✓✓
  --   ⇒ ★★★ 修法 ✓：★ **拿到句柄的那一刻直接调** ✗
  --     ★ 不走 `build_layout` / 不走账本 / 不等 30 帧 ✓ ⇒ ★ **没有可失效的中间层** ✓✓
  --   ⚠️ 每次 `sync_clue_grid` 成功都补一遍 ✓（★ 它自己有 `_grid_sig` 守卫 ⇒ 不是每帧 ✓）
  --   ★★ 顺带把 `pos_runtime = false` 那条也绕开 ✓（★ 那是几何 ✓ 这里只碰可见性 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  do
    local cg = grid
    if cg == nil then
      pcall(function() cg = adapter:find("clues.grid") end)
    end
    if cg ~= nil then
      local ok_v, r_v = pcall(function() cg:SetVisible(true) end)
      local ok_a, r_a = pcall(function() cg:SetActive(true) end)
      local back = nil
      pcall(function() back = cg.visible end)
      if print ~= nil then
        print("[murdoku] ★ 诊断3：直接点 `clues.grid` ⇒ SetVisible=" .. tostring(ok_v)
          .. " SetActive=" .. tostring(ok_a)
          .. "　**回读 visible=" .. tostring(back) .. "**"
          .. "　⇒ 回读 true 就说明规划那条路是多余的；回读仍 false ⇒ 引擎不接受，要换招 ✗")
      end
    end
  end

  -- ★★★★★ 2026-10-05 **`RefreshItems` 成功 = 引擎刚往树里塞了列表项 ⇒ 控件名缓存作废。**
  --
  --   为什么要在这里触发：列表项（`clue.1.who` …）是**引擎**在 `RefreshItems` 里实例化的，
  --   不经过脚本的 `create_control` —— 也就是说，"新建控件"那条事件**看不见它们**。
  --   而这些列表项挂在 `clues.grid` 下面，`clues` 在主页/选关页是**藏起来的**
  --   （`apply_screen_hide`）：新实例化出来的列表项自己是 visible=true，
  --   必须靠兜底隐藏压下去（实测：选关页那一趟有 8 次 `SetVisible` 打在网格子树上）。
  --   ⇒ 一次刷新触发一次；`_grid_sig` 那道守卫保证**不是每帧**（300 帧里这里只进 0~1 次）。
  if adapter ~= nil and adapter.invalidate_lookups ~= nil then
    pcall(function() adapter:invalidate_lookups("grid_refresh:n=" .. tostring(n)) end)
  end

  -- 回调里抛过错 ⇒ 只报一次（不整体回退：那一条没填上而已；反复出现才值得关掉这条路）
  if self._grid_cb_err ~= nil then
    self:_grid_log("cberr", "网格视窗：列表项填充回调抛过异常（" .. tostring(self._grid_cb_err)
      .. "）—— 已按「这一次没填上」处理；反复出现就把 cfg.use_grid 改回 false")
  end

  -- ⑦ 一行**带证据**的结论（用户要的就是这一行，能据此判断链条走到哪一步）
  self:_grid_log("summary", string.format(
    "网格视窗：找到 clues.grid ✓ itemPrefabIndex=%s（回读 %s） n=%d RefreshItems 回调 %d 次；"
    .. "索引基准=%s；列表项点击=%s",
    tostring(prefab), tostring(back), n, calls,
    (self._grid_base == nil) and "?" or tostring(self._grid_base),
    (self._grid_click_ok == true) and "支持（用 GetItemIndex 反查索引）"
      or "不支持（列表项收不到光标事件 ⇒ 只能用老卡片的点击，聚焦仍可用）"))
end

-- 列表项的子控件：模板里叫 `clue.1.<后缀>`（用户是**照着第 1 张卡**另存的模板）。
--   ⚠️ 引擎若按实例序号改名（`clue.<序号>.<后缀>`）也必须命中 ⇒ 四种名字依次试：
--      引擎给的 index → 换算后的位置 pos → 模板原样 `clue.1.*` → 裸名 `<后缀>`
--      （顺序 = 从最具体到最宽松；第一种命中就返回，不会串到别的子控件上）
--   返回值：命中的子控件 + **命中的是第几种名字**（1..4；0 = 都没命中）。
--   为什么要回传"第几种"：第 1/2 种的**名字里带 index** —— 万一引擎真的按序号改名，
--   同一个列表项被回收给别的 index 之后，旧句柄就指向错的子控件了。
--   第 3/4 种（`clue.1.*` / 裸名）与 index 无关 ⇒ 换 index 也还是同一个子控件。
--   缓存层（`_grid_item_child_cached`）就靠这个数决定"能不能跨 index 复用"。
function Controller:_grid_item_child(item, index, pos, suffix)
  if item == nil or item.GetChild == nil then return nil, 0 end
  local names = {
    "clue." .. tostring(index) .. "." .. suffix,
    "clue." .. tostring(pos) .. "." .. suffix,
    "clue.1." .. suffix,
    tostring(suffix),
  }
  for i = 1, #names do
    local hit = nil
    pcall(function() hit = item:GetChild(names[i]) end)
    if hit ~= nil then return hit, i end
  end
  return nil, 0
end

-- ★★★★★ 2026-10-05 **列表项「子控件句柄」的记忆表**（这一轮卡顿的直接病根之一）。
--
--   用户硬证据（同一台设备对比两个包）：
--     · `191-位置交给编辑器.gil`（v058，**网格视窗之前**）：流畅 ✓
--     · 当前（v069，**带网格视窗**）：明显流畅，但"对比之前还是略有卡顿" ✗
--   ⇒ 回退是网格视窗那一轮引进来的（v067/v068 修的两条补发热路 + v069 收紧上限都没治好）。
--
--   离线实测（`tests/grid_cost.lua`，7 个可见列表项，与真机同形状的模板命名）：
--     **一次 RefreshItems 回调 = 54 次 `item:GetChild` + 7 次整视图重建 + 21 次文字写入**
--     （54 = 每个角色依次试名字，命中前平均要试 2.6 次 × 3 个角色 × 7 项）。
--   而官方写明「**列表发生滚动时：对列表项内容进行刷新(触发回调)**」
--   ⇒ 滚动期间这三个数就是**每帧**的开销：54 次引擎调用 + 7×0.235ms 的 Lua 重建
--     + 21 次文本重排 —— 真机表现正是"明显流畅，但对比之前还是略有卡顿"。
--
--   ⇒ 这里把"这个列表项的这个角色是哪个子控件"记下来，键 = **列表项控件身份**：
--     · 弱键（`__mode = "k"`）：引擎回收列表项之后条目自动释放，不会越攒越多；
--     · 控制器是**每关新建**的（`Murdoku.start` → `UIC.new`）⇒ 天然不会跨关缓存。
--
--   ⚠️ 两条复用规矩（都不是拍脑袋，各有一条理由）：
--     ① **同一个 index** ⇒ 引擎这一轮没回收过它 ⇒ 句柄一定还有效，直接用；
--     ② **命中第 3/4 种名字**（`clue.1.*` / 裸名，名字与 index 无关）⇒ 换 index 也还是它；
--     其余情况（index 变了、而当初是靠 `clue.<index>.*` 命中的）**必须重查** ——
--     那正是"引擎按序号改名"的实现下唯一会串到别处的组合。
--   ⚠️ **查不到不缓存**（照 `Adapter:sub` 那条"查不了 = 不存在"踩过一整天的教训）：
--     模板里少一个子控件时，下次回调还会再试，而不是永远当成"没有"。
function Controller:_grid_item_rec(item, index)
  if item == nil then return nil end
  local cache = self._grid_kids
  if cache == nil then
    cache = setmetatable({}, { __mode = "k" })      -- 弱键：列表项被回收后不攒着
    self._grid_kids = cache
  end
  local rec = cache[item]
  if rec == nil then
    rec = { idx = index, hit = {}, variant = {} }
    cache[item] = rec
  end
  return rec
end

function Controller:_grid_item_child_cached(item, index, pos, suffix)
  local rec = self:_grid_item_rec(item, index)
  if rec == nil then return nil end
  local c = rec.hit[suffix]
  if c ~= nil and (rec.idx == index or (rec.variant[suffix] or 0) >= 3) then
    return c                                       -- 规矩①/②：可以直接复用
  end
  local hit, variant = self:_grid_item_child(item, index, pos, suffix)
  rec.idx = index
  rec.hit[suffix] = hit                            -- nil = 没找到 ⇒ 不缓存，下次再试
  rec.variant[suffix] = variant
  return hit
end

-- ★★★★★ 2026-10-05 **列表项的文字：按「关卡」算一次，回调里只查表**。
--
--   为什么可以缓存：`vm.clues[i].text` 由 `Core:clue_results()` 从**关卡数据**里算出来
--   （`def.text(ctx, cl)` 只读 ctx.name / cl.*，全都是关卡里写死的东西，与棋盘状态无关）
--   ⇒ 同一个关卡里这 7（或 N）条文案**一个字都不会变**。
--   实测代价：`Core:view()` 单次 **0.235 ms**（要造上百个表：每个格子 walls/doors/notes
--   + tray + 线索 + structure_report）—— 原来**每条线索调一次** ⇒ 一次回调白花 1.6 ms。
--   缓存键 = **关卡表身份 + 条数**（不拼字符串：`level` 是同一个 Lua 表对象，直接比引用）。
function Controller:_grid_text_payload()
  local core = self.core
  local lv = core and core.level
  local list = lv and lv.clues
  local n = #(list or {})
  local p = self._grid_text
  if p ~= nil and p.level == lv and p.n == n then return p end
  local vm = core:view() or {}
  local items = {}
  for i = 1, #(vm.clues or {}) do
    local cl = vm.clues[i]
    -- 与 `clue.N` 三个文字控件**完全同一份取值**（切分逻辑共用 `split_by_name`，不复制）
    --
    -- ★★★★★ 2026-10-06 **接上第 5 个返回值 `wportrait`** ✗✓ —— 网格视窗的头像要靠它 ✓
    --   起因：★ 用户建好模板后发现「★ **五张卡的头像都一样**」✗
    --   ★ 根因：★ `face` 是**图片控件** ✓ ★ 它**不会自己变** ✗ ⇒
    --     ★ 必须**逐个实例**写 `imageId` ✓ —— 而这里**原来没接 `wportrait`** ✗✓
    --   ★ 旧卡片（`clue.N.face`）一直在用第 5 个返回值 ✓（★ 见下面 `local who, pre, post, wid, wportrait = `
    --     ★ 那份 ✓）⇒ ★ 这里漏了 ✓ ⇒ ★ 于是网格视窗走的是"头像永远等于模板默认图" ✓
    local who, pre, post, wid, wportrait = split_by_name(vm, tostring(cl.text or ""))
    --   ⚠️ 文案里没有人名时（例如 `selftest_theft_5x5` 的线索）：`who == nil`、`pre` 是整条文案
    --      ⇒ 名字列留空、正文放**整条**（老路径在那种关卡上是整块不发、什么都看不到；
    --         新路这里按"名字为空、正文 = 全文"来填，线索本身必须看得见）。
    items[i] = {
      who    = (who ~= nil) and (tostring(pre or "") .. tostring(who)) or "",
      what   = (who ~= nil) and tostring(post or "") or tostring(pre or ""),
      letter = tostring(wid or ""),
      -- ★ 头像素材名（★ 如 `portrait.A` ✓）★ `nil` 表示这一条没有对应角色 ⇒ **不要写图** ✓
      portrait = wportrait,
      -- ★★★★★ 2026-10-09 **把【人物 id】也存进快照** ✗✓（★ 这是修我自己造成的一个回归 ✓）
      --
      --   ★ 为什么必须有这一项 ✓：填充那边要按 **id**（`A`/`B`/`D`/`V`）去查
      --     `core.placed[id]` 决定灰白 ✓ 而 `who` / `portrait` **都不保证是 id** ✗：
      --       · `items.who`  是**显示名**（`医生` ✓ 见 L4131 的拼接 ✓）
      --       · `items.portrait` 是**素材名**（`portrait.B` ✓）也可能取不到 ✓
      --     ⇒ ★ **只有视图记录的 `cl.who` 是 id** ✓（`ui_controller.lua:4211` 的老注释就写着这条 ✓
      --        `诊断CLUE` 也证明过：`值(type=at … who=V)` ✓ 是字母 ✓）
      --
      --   ★ 为什么存这里、而不是填充时现取 ✓：**这里本来就有一份 `vm` 在手** ✓
      --     存下来 ⇒ 填充时**零额外成本** ✓
      --     （我 2026-10-09 早先那版把填充里的 `core:view()` 删了 —— 动机是每次回调白烧
      --      14 次整视图重建 ✓ 但**删过头了** ✗：那个 `who` 是**唯一**能拿到 id 的来源 ✓
      --      于是 id 退化成显示名 ⇒ `core.placed["医生"]` 恒 nil ⇒ **灰白与选中反馈全没了** ✗
      --      正确修法 = **从这里拿**（已是 0 成本 ✓），而不是**不拿** ✓）
      id     = (cl.who ~= nil) and tostring(cl.who) or nil,
    }
  end
  p = { level = lv, n = n, items = items }
  self._grid_text = p
  return p
end


-- 填**一条**列表项。★ 无状态：内容全部由 `index` 现算（官方：滚动会重复进入回调）。
function Controller:_fill_grid_item(adapter, grid, item, index)
  self._grid_calls = (self._grid_calls or 0) + 1
  if item == nil then return end

  -- ★★ 官方那句"列表发生滚动时：对列表项内容进行刷新(触发回调)"有**两种读法**
  --    （引擎自己重进 / 得靠脚本再调一次 RefreshItems）—— 这是本项目一个**未验证点**：
  --      · 引擎**会**重进 ⇒ 这里会打出一行（就靠它确认；此时列表项内容永远是对的）
  --       · 引擎**不会**重进 ⇒ 日志里没有这行 ⇒ 滚动后列表项会留着上一条的内容，
  --         下一轮就得改成"跟着 scrollProgress 变化再调一次 RefreshItems"
  --   区分办法：我们那次 `RefreshItems` 调用期间 `_grid_in_refresh = true`；
  --   回调从引擎那边进来时它是 false。
  if not self._grid_in_refresh then
    self._grid_scroll_cbs = (self._grid_scroll_cbs or 0) + 1
    self:_grid_log("scroll_cb", "网格视窗：滚动时引擎**会**重进 RefreshItems 回调 ✓（第 "
      .. tostring(self._grid_scroll_cbs) .. " 次）⇒ 列表项内容按 index 现算，滚动不会串内容")
    -- ★★★★★ 2026-10-05 **节流计数：这条路上的每帧开销现在已经是 0，但"引擎多久重进一次"
    --   只有真机能回答**（离线假环境是我们自己调的，测不出引擎的节奏）。
    --   重进满 60 / 600 / 3600 次时各报一行 —— 60 fps 下分别约等于 1 秒 / 10 秒 / 1 分钟。
    --   读法：
    --     · 只是滚动几秒就看到 `60` ⇒ 重进频率 ≈ 每秒几十次（滚动时才重进，符合官方描述）
    --     · 挂着不动也走到 `3600` ⇒ 引擎**每帧**都重进；此时每帧成本仍然是 0
    --       （`_grid_item_rec` / `_grid_text_payload` 把查找、视图重建、文字写入全免掉了）
    --     · 一行都不出现 ⇒ 引擎根本不重进 ⇒ 滚动后列表项会留着上一条的内容，
    --       下一轮得改成"跟着 scrollProgress 变化再调一次 RefreshItems"
    local hits = self._grid_scroll_cbs
    if (hits == 60 or hits == 600 or hits == 3600) and print then
      print("[murdoku] 网格视窗：引擎重进回调累计 " .. tostring(hits)
        .. " 次（60 ≈ 每帧重进时的一秒）—— 仅用于确认重进频率，每帧成本已为 0")
    end
  end

  -- 索引基准：**第一次回调 = 列表最上面那一项** ⇒ 它的 index 就是基准（0 或 1）。
  --   为什么要判：官方只说"索引以运行时传入/返回的为准"，**没说从 0 还是从 1 起**
  --   （`clue.1` 这些控件名是 1 起，而 Unity 那套列表通常是 0 起）。
  --   判一次就够，之后滚动回调沿用它 —— 这样两种实现都能对上 `vm.clues`（1 起）。
  if self._grid_base == nil then
    self._grid_base = (tonumber(index) == 0) and 0 or 1
  end
  local pos = (tonumber(index) or self._grid_base) - self._grid_base + 1

  -- ★★★★★ 2026-10-05 **文案查缓存表，不再"每条线索重建一次整视图"**。
  --
  --   改之前：这里每进一次回调就 `self.core:view()` 一次 ⇒ 一次回调 **7 次**整视图重建
  --   （实测单次 0.235 ms ⇒ 白花 1.6 ms），而回调在滚动时是**每帧**进来的。
  --   文案只跟关卡数据有关（见 `_grid_text_payload` 的注释）⇒ 算一次就够。
  local pay = self:_grid_text_payload()
  local cl = pay.items[pos]
  if cl == nil then return end        -- 超出本关线索数（理论上不会来）⇒ 什么都不写
  local t_who, t_what, t_letter = cl.who, cl.what, cl.letter
  -- ★★★★★ 2026-10-07 **已正式放置 ⇒ 卡片盖一层灰白** ✗✓（用户新功能 ✓ 模板侧已加控件 `gray` ✓）
  --   ★ 分工（用户定的 ✓ 也是"能走控件就不走脚本"✓）：
  --     · ★ **模板**：★ 列表项模板 `clue`（1073742421）里加了一个**图片控件 `gray`** ✓
  --       ★ 它在同级里排**第 7/7 = 最上层** ✓ 尺寸/位置/颜色/20% 透明**全在编辑器里** ✓
  --     · ★ **脚本只做一件事** ✓：★ **按"这个人是否已正式放置"开/关它的可见性** ✓
  --   ★ 判据用 **`core.placed[cl.who]`** ✓（★ `cl.who` 就是人物 id ✓ 与徽章字母同一个 ✓）
  --   ★ 规矩：★ **与 `face`/文字同一套"值变了才写"** ✓ ⇒ 稳态零成本 ✓
  --   ⚠️ 列表项是复用的 ✓ ⇒ 每次填充都要按**当前 `pos`** 重新判 ✓（不能缓存上一次的结论 ✓）
  -- ★★★★★ 2026-10-07 **人物 id 要从【头像素材名】取** ✗✓（真机诊断一次命中 ✓）
  --   ★ 证据 ✓：★ `★ 灰白诊断：pos=3  who=老宅主  placed=false  找到gray=true` ✓
  --     ⇒ ★ `cl.who` 是**显示名**（老宅主 ✗）而不是 **id**（`V` ✓）
  --       ⇒ ★ `core.placed["老宅主"]` 恒为 nil ⇒ ★ **灰白永远不开** ✓✓
  --   ★ 而列表项本来就知道 id ✓：★ **头像素材名 `portrait.V`** ✓（★ 填充里用 `t_portrait` ✓）
  --     ⇒ ★ 去掉 `portrait.` 前缀就是 id ✓（★ 与 `who=V` / `who=D` 同一套字母 ✓）
  -- ★★★★★ 2026-10-07 **id 改用【核心视图】那条记录** ✗✓
  --   ★ 上一版从 `t_portrait` 取 ⇒ 真机仍是 `placed=false` ✗（★ 说明那个变量在这段作用域里不是 `portrait.X` 格式 ✓
  --     或索引对不上 ✓）⇒ ★ **不再猜变量** ✓
  --   ★ 权威来源 ✓：★ **`诊断CLUE` 早就证明** 视图里的线索记录有 **`who=V`**（★ id ✓ 不是显示名 ✓）
  --     ⇒ ★ 用 `self.core:view().clues[pos].who` ✓ 取不到再退回 `t_portrait` ⇒ 再退回 `cl.who` ✓
  -- ★★★★★ 2026-10-09 **删掉这里的 `core:view()` —— 它取到的值【一定会被覆盖】** ✗✓
  --   ★ 原文（三段的实际效果）✓：
  --       local _pid = nil
  --       pcall(function() local v = self.core:view() … if cc.who then _pid = cc.who end end)  ← 取一次视图
  --       if _pid == nil and t_portrait ~= "" then _pid = t_portrait 去掉前缀 end
  --       if t_portrait ~= "" then _pid = t_portrait 去掉前缀 end        ← ★ 无条件，把上面整个覆盖 ✗
  --     ⇒ ★ **第三个 `if` 无条件执行** ⇒ 第二个 `if` 与那个 `pcall` **全是白做的** ✓
  --       （`_pid` 最终**只由 `t_portrait` 决定** ✓）
  --   ★ 代价（实测 `tests/grid_cost.lua` ✓）：★ **每个列表项 2 次整视图重建** ✗
  --       · 一次回调 7 项 ⇒ `view=14` ✗ · 连续 5 次重进 ⇒ `view=70` ✗（**与重进次数线性增长** ✓）
  --       · 而 `core:view()` 单次 **0.175 ms**（`[F]` 段实测 ✓）⇒ 一次重进白烧 **≈2.5 ms** ✓
  --       · 更要命的是它**击穿了记忆表** ✗：文案快照本来让重进零成本（`文字写入=0` ✓），
  --         而这两次视图重建让"引擎每帧重进"变成**每帧 2.5ms** ✗（用户第五轮指示：负载最小 ✓）
  -- ★★★★★ 2026-10-09 **改回来了（我上一步删过头了 ✗）—— 顺序是【id 优先、素材名兜底】** ✗✓
  --
  --   ★ 我真机上看到的现象 ✓（用户 2026-10-09 18:03 那份日志）：
  --       `★ 灰白诊断：pos=1  who=医生  placed=false  找到gray=true  ★ id=医生  portrait=nil`
  --     ⇒ ★ **`id=医生`（显示名 ✗）** —— 而**之前**同一行是 `★ id=B` ✓
  --     ⇒ 用户侧表现：★ **「case_001 线索区的所有选中反馈都消失了」** ✗
  --
  --   ★ 根因（**是我不对** ✗）：我上一步的推理只对了一半 ✗
  --     我当时说「第三个 `if` 无条件覆盖 ⇒ 那个 `pcall(core:view())` 是白做的」——
  --     ★ **只有在 `t_portrait` 非空时才成立** ✗
  --     ★ 而 `t_portrait` **为空**时，那个 `pcall` 取到的 `cc.who` 会**留下来** ✓
  --       而它**是唯一的 id 来源**（视图记录的 `who` 是 `V`/`D` 这种**字母 id** ✓
  --       见 L4211 老注释与 `诊断CLUE` 的 `who=V` ✓）
  --     ⇒ ★ 我把"唯一能拿到 id 的那条路"删了 ⇒ id 退化成显示名
  --       ⇒ `core.placed["医生"]` 恒 nil ⇒ ★ **灰白 + 选中反馈全没** ✓
  --
  --   ★ 正确修法 ✓：**从 `_grid_text_payload` 的快照里拿 `cl.id`** ✓
  --     · 那份快照建的时候**本来就有一份 `vm` 在手**（L4114 `local vm = core:view()` ✓）
  --     · 所以取 `cl.who` 存下来是 **零额外成本** ✓
  --     ⇒ ★ 既**拿回了 id** ✓ 又**没有**把"每次回调 14 次整视图重建"带回来 ✓✓
  --   ★ 优先级（与 L4211 老注释一致 ✓）：**id（权威）→ 素材名去前缀 → `cl.who`（显示名，最后兜底）**
  local _pid = cl.id
  if _pid == nil or _pid == "" then
    if t_portrait ~= nil and t_portrait ~= "" then
      _pid = tostring(t_portrait):gsub("^portrait%.", "")
    end
  end
  if _pid == nil or _pid == "" or #_pid > 2 then _pid = cl.id or cl.who end
  if type(_pid) == "string" and _pid:sub(1, 1) == "@" then _pid = nil end   -- 特殊角色（如 @thief）不算人
  local _placed_now = (_pid ~= nil) and self.core ~= nil and self.core.placed ~= nil
    and self.core.placed[_pid] == true
  local _cgray = self:_grid_item_child_cached(item, index, pos, "gray")
  -- ★ 2026-10-07 一次性诊断：★ "灰白没出现"到底是【没找到 `gray`】还是【placed 判错】✓
  --   ★ 真机反馈 ✓：★ 颜色在编辑器里都对 ✓ 但**没有卡变灰** ⇒ ★ 说明**脚本这侧没生效** ✓
  if (self._gray_log or 0) < 4 then
    self._gray_log = (self._gray_log or 0) + 1
    print("[murdoku] ★ 灰白诊断：pos=" .. tostring(pos) .. "  who=" .. tostring(cl.who)
      .. "  placed=" .. tostring(_placed_now) .. "  找到gray=" .. tostring(_cgray ~= nil)
      .. "  ★ id=" .. tostring(_pid) .. "  portrait=" .. tostring(t_portrait))
  end
  do
    -- ★★★★★ 2026-10-07 **高亮跟【选中】走，且只染"被选中的那张"** ✗✓（用户两条反馈 ✓）
    --   ★ 反馈① ✓：★「★ **描边又变亮了**」✗ —— ★ 我上一版在"未聚焦"时**写死了白色** ✗
    --     ⇒ ★ 等于给每一张卡提亮描边 ✓（★ 项目注释 `ui_controller.lua:4325` 早记过这个坑 ✓）
    --   ★ 反馈② ✓：★「★ **再次单击取消选中后高亮还在**」✗
    --     ⇒ ★ 因为我按 **`focused_clue`（聚焦）** 染色 ✓ 而 **聚焦 ≠ 选中** ✗
    --   ★ 修法 ✓：★ **① 只在被选中时染** ✓ **② 其余情况复原"原来读到的颜色"** ✓（★ 不写白 ✓）
    --     ★ ③ ★ 原色**只在第一次**记 ✓（★ 免得把金色当原色 ✓）
    local _cbp2 = self:_grid_item_child_cached(item, index, pos, "backrop1")
    local _rg2 = self:_grid_item_rec(item, index)
    if _cbp2 ~= nil and _rg2 ~= nil then
      -- ★★★ 2026-10-07 **比的是【人物 id】不是 `cl.who`（那是显示名 ✗）** ✓
      --   ★ 真机教训 ✓：★ 填充里 `cl.who = 老宅主` ✗（显示名 ✓）而 `core.selected = "V"` ✓
      --     ⇒ ★ 拿它比永远不等 ⇒ ★ **重填后高亮不再画 ⇒ 预放置丢高亮** ✗（用户回报 ✓）
      --   ★ id 的权威来源 ✓：★ **视图记录 `self.core:view().clues[pos].who`** ✓（★ 与 `诊断CLUE` 一致 ✓）
      -- ★ 2026-10-09 **不再为这一处单独取视图** ✗✓ —— 上面 `_pid` **已经算好了同一个值** ✓
      --   （原来这里又 `self.core:view()` 一次 ⇒ **每项第 2 次整视图重建** ✗ 实测 `view=14/7 项` ✓）
      --   ★ 语义不变 ✓：`_pid` 与这里原来取的 `v.clues[pos].who` **等价** ✓
      --     （而且 `_pid` 还多做了"去掉 `portrait.` 前缀"和"跳过 `@` 特殊角色"两步 ✓ 更稳 ✓）
      local _pid2 = _pid
      local _sel = (_pid2 ~= nil) and self.core ~= nil and self.core.selected == _pid2
      if _sel then
        if _rg2.tint ~= "sel" then
          if _rg2.tint_orig == nil then
            pcall(function() _rg2.tint_orig = _cbp2.imageColor end)
          end
          _rg2.tint = "sel"
          pcall(function() _cbp2.imageColor = 4294956107 end)     -- ★ 暖金（乘算着色）
        end
      elseif _rg2.tint == "sel" then
        _rg2.tint = nil
        if _rg2.tint_orig ~= nil then
          pcall(function() _cbp2.imageColor = _rg2.tint_orig end)  -- ★ 复原（★ 不写白 ✓）
        end
      end
    end
  end

  -- ★★★★★ 2026-10-08 **把调色板里的头像【成对】写到卡片 `face` 上** ✗✓（"百四方块"的治本一步 ✓）
  --   ★ 依据 ✓：★ 日志里 `调色板里没有素材「portrait.X」` **已经消失** ⇒ ★ **调色板找得到** ✓
  --     ⇒ ★ 剩下的就是"**找到之后没贴到卡片上**" ✓（用户看到的仍是占位方块 ✓）
  --   ★ 项目铁律 ✓：★ **图片要【成对写】`imageSource` + `imageId`** ✗
  --     （★ 只写 id ⇒ "属性变了、画面没变" ✓ 本项目多处注释反复强调 ✓）
  --   ★ 写法 ✓：★ 直接写字段 ✓（★ 与既有的 `imageColor`/`raycastTarget` 同一手法 ✓ 全程 pcall ✓）
  --   ★ 去重 ✓：★ 记住上次写的 id ✓ ⇒ 值没变不重复写 ✓（★ 稳态零成本 ✓）
  do
    -- ★★★★★ 2026-10-08 **调色板查找改成"遍历 `assets` 子控件按名匹配"** ✗✓
    --   ★ 真机证据 ✓：★ `★ 头像分件：id=V  pal=false(nil)  face=true` ✓
    --     ⇒ ★ **`adapter:find("portrait.V")` 找不到** ✗（★ 而卡片的 `face` 找得到 ✓ 说明不是"控件系统坏了"✓）
    --   ★ 原因 ✓：★ `find` 的搜索范围不覆盖 `assets` 那一层（★ 或名字与预期不同 ✓）
    --   ★ 改法 ✓：★ **先试 `find`** ✓ **不行就取 `assets` 容器、遍历它的子控件按名比** ✓
    --     ★ 顺手**打印候选名**（★ 最多 12 行 ✓）⇒ 万一名字不同，一眼就能看见 ✓✓
    --   ★ 缓存 ✓：★ 找到就记住 ✓ ⇒ 稳态零成本 ✓
    local _pal = nil
    self._pal_cache = self._pal_cache or {}
    if _pid ~= nil then
      _pal = self._pal_cache[_pid]
      local _nm = "portrait." .. tostring(_pid)
      if _pal == nil then
        -- ★★★★★ 2026-10-08 **一层层走、每步单独 pcall** ✗✓（三个真机教训一起修 ✓）
        --   ① ★ `Adapter:find` 有**负缓存** ✗：★ 一旦某名字被判定"不在树上" ⇒ **这一代直接返回 nil** ✓
        --      ⇒ ★ 开局树空时查过的名字**永远查不到** ✓ ⇒ **不能依赖 `find` 找 `assets`** ✓
        --   ② ★ 上一版把整段递归包在一个大 pcall 里 ✗ ⇒ 中间出错就**整体静默失败** ✓（表现就是"找不到" ✓）
        --      ⇒ ★ 现在**每一步各自 pcall** ✓ ⇒ 哪一步失败日志里都看得见 ✓
        --   ③ ★ 已知结构（gil 侧实证 ✓）：★ `assets` 是 **`root` 的第 1 个子控件** ✓
        --      ⇒ ★ **只需走两层**：`root` → 子控件里找 `assets` → 它子控件里找 `portrait.<id>` ✓ 不必深递归 ✓
        -- ★★★★★ 2026-10-08 **限深递归搜 `assets`** ✗✓（真机证据：它不是 `root` 的直接子控件 ✗）
        --   ★ 上一版只扫 `root` 一层 ⇒ 真机报「root 的直接子控件里没有 assets」✗
        --     （★ 而 gil 记录里它的父【是】`root` ✓ ⇒ **真机树与存档结构不同** ✓）
        --   ★ 现在：★ 从 `root` 起**限深 4 层**递归搜名字 ✓ ★ **每步单独 pcall** ✓（★ 哪步失败看得见 ✓）
        --   ★ 并**打印沿途看到的名字**（★ 最多 16 条 ✓）⇒ 下次一眼知道它挂在哪 ✓
        local _as = nil
        local _seen = 0
        pcall(function()
          -- ★★★★★ 2026-10-08 **改用引擎自己的入口** ✗✓（用户点出：编辑器里 assets 明确与 home 平级 ✓）
          --   ★ 怀疑 ✓：★ 我上一版从 `self.adapter:find("root")` 起走 ⇒ ★ 它可能返回**不是 UI 根**的那个 root ✗
          --     （★ 与"读 218.1 时按字段号下钻"是同一类错误：★ **拿一个"看起来像"的入口当权威** ✗）
          --   ★ 权威入口 ✓：★ **`game.GetClientUIRoots()`** ✓ —— ★ 适配器文档第 14 条写的就是它 ✓
          --   ⇒ ★ 从这里起遍历 ✓ ★ 并把**根的名字**打出来 ✓（★ 一眼确认走对了没有 ✓）
          -- ★★★★★ 2026-10-08 **前向声明** ✗✓（真机：一行"第N层看到"都没有 ⇒ 递归根本没跑 ✓）
          --   ★ 元凶 ✓：★ 我把 `_search(...)` 的**调用写在了它的 `local function` 定义之前** ✗
          --     ⇒ ★ Lua 里此刻 `_search` 还是 nil ⇒ ★ 调用即报错 ⇒ ★ **被外层 pcall 吞掉** ✓
          --       ⇒ ★ 表现就是"什么都没发生"（★ 与"大 pcall 掩盖错误"是同一个坑 ✓ 我又踩了一次 ✓）
          --   ★ 修法 ✓：★ **先声明再赋值**（`local _search` 在前 ✓ `_search = function` 在后 ✓）✓
          local _search = nil
          local _roots = nil
          pcall(function() _roots = game.GetClientUIRoots() end)
          local _rn = 0
          if _roots ~= nil then pcall(function() _rn = #_roots end) end
          if (self._roots_log or 0) < 2 then
            self._roots_log = (self._roots_log or 0) + 1
            local _nm = {}
            for i = 1, math.min(_rn, 8) do
              local x = _roots[i]
              local xn = nil
              pcall(function() xn = tostring(x.name) end)
              _nm[#_nm + 1] = tostring(xn)
            end
            print("[murdoku] ★ 调色板搜寻：客户端根 " .. tostring(_rn) .. " 个 = " .. table.concat(_nm, " , "))
          end
          -- ★ 2026-10-08 **在主路径上按名取 assets**（★ 用户指出：两个客户端容器 ✓ `111` 是屏蔽节点那个 ✓）
          --   ★ 只有 `root`（挂了脚本的那个 ✓）里才有 `assets` ✓ ⇒ ★ 用 `find("root")` + `GetChild("assets")` ✓
          pcall(function() local _r = self.adapter:find("root"); if _r ~= nil and _as == nil then _as = _r:GetChild("assets") end end)
          if _as ~= nil and _pal == nil then pcall(function() _pal = _as:GetChild(_nm) end) end
          if (self._g_log or 0) < 4 then
            self._g_log = (self._g_log or 0) + 1
            -- ★★★★★ 2026-10-08 **只读探针：运行时四键 `bg` 的 imageId 是多少** ✗✓（★ 用来分甲/乙 ✓）
            --   ★ 甲：★ 脚本画的不是编辑器那个实例 ⇒ ★ `bg.imageId` 应为 `100001`（或取不到）✗
            --   ★ 乙：★ 图设上了但没渲染 ⇒ ★ 应读到 `107179` ✓
            --   ★ 本处放在"调色板查找"同一个函数里 ✓ —— ★ 真机已证它在跑（★ 下面那句 `★ 按名取` 每帧可见 ✓）
            if self.modal ~= nil and (self._exit_probe or 0) < 12 then   -- ★ 只在弹窗开着时才打 ✓（上一版在弹窗关着时打完了 8 次 ✗）
              self._exit_probe = (self._exit_probe or 0) + 1
              local _m = nil
              pcall(function() _m = self.adapter:sub("modal", "modal.exit") end)
              if _m == nil then pcall(function() _m = self.adapter:find("modal.exit") end) end
              local _b = nil
              if _m ~= nil then pcall(function() _b = self.adapter:sub("modal.exit", "bg") end) end
              local _id, _src, _vis = "?", "?", "?"
              if _b ~= nil then
                pcall(function() _id = tostring(_b.imageId) end)
                pcall(function() _src = tostring(_b.imageSource) end)
                pcall(function() _vis = tostring(_b.visible) end)
              end
              print("[murdoku] ★ 四键探针：exit=" .. tostring(_m ~= nil) .. "  bg=" .. tostring(_b ~= nil)
                .. "  imageId=" .. _id .. "  source=" .. _src .. "  visible=" .. _vis
                .. "  弹窗开着=" .. tostring(self.modal ~= nil))
            end
            print("[murdoku] ★ 按名取：assets=" .. tostring(_as ~= nil) .. "  portrait.<id>=" .. tostring(_pal ~= nil))
          end
          -- ★ 2026-10-08 **按名取清单**（★ 真机 `assets=false` ✗ ⇒ 先看清"哪些名字取得"✓）
          --   ★ 项目里早有过提醒 ✓：★「脚本是精确匹配的：大小写、空格、**自动后缀**都算不一样」✓
          --     ⇒ ★ 引擎可能给 `assets` 加了后缀（如 `assets(1)` ✓）★ 或名字其实不同 ✓
          if (self._g_log or 0) < 4 then
            self._g_log = (self._g_log or 0) + 1
            local _cands = { "assets", "assets(1)", "assets1", "home", "topbar", "clues", "row.1.1", "row.1.2", "portrait.V", "portrait.A" }
            local _parts = {}
            local _r1 = self.adapter:find("root")
            local _rn1 = "?"
            pcall(function() _rn1 = tostring(_r1 and _r1.name) end)
            if _r1 ~= nil then
              for _i1 = 1, #_cands do
                local _got = nil
                pcall(function() _got = _r1:GetChild(_cands[_i1]) end)
                _parts[#_parts + 1] = _cands[_i1] .. "=" .. tostring(_got ~= nil)
              end
            end
            print("[murdoku] ★ 按名取清单：root 名=" .. _rn1 .. "   " .. table.concat(_parts, "  "))
          end
          -- ★★★★★ 2026-10-09 **【B2】清缓存与「按名取 assets」必须【无条件】执行** ✗✓
          --   ★ 原文的错 ✗：这两件事被关在 `if _rn == 0 then` 里（★ 只有"引擎一个根都拿不到"时才跑 ✓）
          --     ⇒ ★ 真机 `_rn = 2`（`111` + `root` 两个客户端容器 ✓）⇒ **走 else 分支 ⇒ 两件事从未执行** ✗✗
          --     ⇒ ★ 于是「`assets` 按名取」从来没试过 ✓ ★ 「负缓存清一代」也从来没做过 ✓
          --     ⇒ ★ `docs/assets取不到-追查.md` 里"已排除负缓存"的**前提不成立** ✓（要重判 ✓）
          --   ★ 为什么本来就该无条件 ✓：★ 清缓存是**幂等的一次性动作** ✓（`_cache_cleared` 把关 ✓）
          --     ★ 按名取是**主路径** ✓（★ 与 `_rn` 毫无关系 ✓）⇒ 两者都不该依赖根的数量 ✓
          if self.adapter ~= nil and not self._cache_cleared then
            self._cache_cleared = true
            if self.adapter.invalidate_lookups ~= nil then pcall(function() self.adapter:invalidate_lookups("调色板查找前") end) else pcall(function() self.adapter._misses = nil; self.adapter.controls = {} end) end
          end
          pcall(function() local _r = self.adapter:find("root"); if _r ~= nil and _as == nil then _as = _r:GetChild("assets") end end)   -- ★ 按名取 assets ✓

          -- ★★★★★ 2026-10-09 **【B1】`_search` 必须先【定义】、再【调用】** ✗✓
          --   ★ 原文的错 ✗：调用在 :4377 / :4379，而赋值 `_search = function…` 在 :4381 ✓
          --     ⇒ ★ `attempt to call a nil value` ✓ ★ 被本函数最外层的**大 pcall 吞掉** ✗
          --     ⇒ ★ 静默失效：**调用点之后的整段都不执行**（连那行赋值本身也不执行 ✓）
          --     ⇒ ★ 所以真机日志里「调色板搜寻：第N层看到」**一行都没有** ✓✓
          --   ★ `:4298` 那条注释以为"先 `local _search = nil` 声明就修好了" ✗
          --     —— ★ **声明成 nil 并不能防止调用 nil** ✓ 必须先赋值 ✓（本项目第 N 次同形状 ✓）
          _search = function(node, depth)
            if node == nil or depth > 4 or _as ~= nil then return end
            local kids = nil
            pcall(function() kids = node:GetChildren() end)
            if kids == nil then return end
            local n = 0
            pcall(function() n = #kids end)
            for i = 1, n do
        if _as ~= nil and _pal == nil then pcall(function() _pal = _as:GetChild(_nm) end) end   -- ★ 按名取 portrait.<id> ✓
              if _as ~= nil then return end
              local x = kids[i]
              local xn = nil
              pcall(function() xn = tostring(x.name) end)
              if _seen < 16 then
                _seen = _seen + 1
                print("[murdoku] ★ 调色板搜寻：第" .. tostring(depth + 1) .. "层看到 " .. tostring(xn))
              end
              if xn == "assets" then _as = x return end
              _search(x, depth + 1)
            end
          end

          -- ★ 只有在"按名取"没拿到时，才值得退回去递归搜（省掉稳态的整树遍历 ✓）
          --   ⚠️ 原文这里还有一句 `if r0 == nil then return end` ✗ —— 那个 `return` 会
          --      **中断整个大 pcall 的函数体**（★ 连后面的赋值一起跳过 ✓）⇒ 已去掉 ✓
          if _as == nil then
            if _rn == 0 then
              local r0 = self.adapter:find("root")     -- 兜底：引擎入口拿不到时，退回按名找
              if r0 ~= nil then _search(r0, 0) end
            else
              for i = 1, _rn do _search(_roots[i], 0) end
            end
          end
        end)        if _as ~= nil then
          local k1 = nil
          pcall(function() k1 = _as:GetChildren() end)
          if k1 ~= nil then
            local n1 = 0
            pcall(function() n1 = #k1 end)
            for i = 1, n1 do
              local x = k1[i]
              local xn = nil
              pcall(function() xn = tostring(x.name) end)
              if xn == _nm then _pal = x end
              if (self._pn_log or 0) < 12 then
                self._pn_log = (self._pn_log or 0) + 1
                print("[murdoku] ★ 调色板候选：assets 下有 " .. tostring(xn))
              end
            end
          else
            if (self._as_log or 0) < 2 then
              self._as_log = (self._as_log or 0) + 1
              print("[murdoku] ★ 调色板候选：找到 assets，但取不到它的子控件（GetChildren 失败）")
            end
          end
        else
          if (self._as_log or 0) < 2 then
            self._as_log = (self._as_log or 0) + 1
            print("[murdoku] ★ 调色板候选：root 的直接子控件里没有 assets")
          end
        end
      end      if _pal ~= nil then self._pal_cache[_pid] = _pal end
    end
    local _cf = self:_grid_item_child_cached(item, index, pos, "face")
    -- ★ 2026-10-08 **分件诊断**（真机：`头像贴图` 一行都没出现 ⇒ 说明取不到 ✓ 那就分别打出来 ✓）
    --   ① `_pid`（人物 id ✓ 应为 V/D/A/B ✓）② `_pal`（调色板控件找到没 ✓）③ `_cf`（卡片 face 找到没 ✓）
    if (self._pd_log or 0) < 8 then
      self._pd_log = (self._pd_log or 0) + 1
      local _pn = "?"
      pcall(function() _pn = tostring(_pal and _pal.name) end)
      print("[murdoku] ★ 头像分件：id=" .. tostring(_pid) .. "  pal=" .. tostring(_pal ~= nil)
        .. "(" .. _pn .. ")  face=" .. tostring(_cf ~= nil))
    end
    if _pal ~= nil and _cf ~= nil then
      local _ps, _pi = nil, nil
      pcall(function() _ps = _pal.imageSource end)
      pcall(function() _pi = _pal.imageId end)
      local _rg3 = self:_grid_item_rec(item, index)
      if _pi ~= nil and (_rg3 == nil or _rg3.pimg ~= _pi) then
        if _rg3 ~= nil then _rg3.pimg = _pi end
        if _ps ~= nil then pcall(function() _cf.imageSource = _ps end) end
        -- ★★★★★ 2026-10-08 **头像 id 直接写死（甲案）** ✓✓（★ 用户拍板 ✓）
        --   ★ 为什么 ✓：★ `assets` 容器在运行时**取不到** ✗（★ 已排除负缓存/可见性/画布位置 ✓）
        --     ⇒ ★ 而 4 个头像 id **早已确证** ✓（★ 四种独立指标交叉验证 ✓ 有证据图 ✓）
        --   ★ 写法 ✓：★ 调色板取不到时 ⇒ ★ **用写死的表兜底** ✓（★ `_ps` 用素材库哨兵 `4294967295` ✓
        --     与存档里 `portrait.*` 的 `imageSource` 一致 ✓）
        --   ★ 以后要"可配置"✓ ⇒ ★ 等 `assets` 的事查清，把这张表换回"从容器读"即可 ✓（★ 一处 ✓）
        if _pi == nil and _pid ~= nil then
          local _IDS = { A = 112042, B = 105104, V = 112031, D = 105105 }
          local _hit = _IDS[tostring(_pid)]
          if _hit ~= nil then _ps = 4294967295; _pi = _hit end
          if (self._ids_log or 0) < 6 then
            self._ids_log = (self._ids_log or 0) + 1
            print("[murdoku] ★ 写死表：id=" .. tostring(_pid) .. "  imageId=" .. tostring(_hit))
          end
        end
        pcall(function() if _cf.SetImage ~= nil then _cf:SetImage(_ps or _cf.imageSource, _pi) end end)   -- ★ 官方贴图接口 ✓
        pcall(function() _cf.imageId = _pi end)
        pcall(function() _cf:SetVisible(true) end)
        pcall(function() if _cf.SetActive then _cf:SetActive(true) end end)
        if (self._pt_log or 0) < 8 then
          self._pt_log = (self._pt_log or 0) + 1
          print("[murdoku] ★ 头像贴图：face ← portrait." .. tostring(_pid)
            .. "  src=" .. tostring(_ps) .. "  id=" .. tostring(_pi))
        end
      end
    end
  end
  if _cgray ~= nil then
    -- ★★★★★ 2026-10-07 **灰白图必须【不参与射线】** ✗✓（"预放置也像被取消选中"的真因 ✓）
    --   ★ 真机反馈 ✓：★ 灰白出来之后 ⇒ ★「★ **预放置也会取消选中，且要双击才能重新选中**」✗
    --   ★ 机制 ✓：★ `gray` 是卡片里**最上层**的图片 ✓ ⇒ ★ 它**挡在最上面吃点击** ✗
    --     ⇒ ★ 单击落在它身上 ⇒ **到不了卡片按钮** ⇒ ★ 表现就是"点不中/像没选中" ✓✓
    --   ⇒ ★ 这里把它的**射线与交互一起关掉** ✓ ⇒ ★ **点击穿透到卡片** ✓（★ 灰白只是视觉层 ✓）
    --   ⚠️ 只做一次（★ 记住做过 ✓ 免得每帧写字段 ✓）
    -- ⚠️⚠️ 2026-10-07 **必须【按列表项实例】记** ✗✓（我第一版用了全局标志 ⇒ 只有第 1 个实例做了 ✗）
    --   ★ 真机证据 ✓：★ 日志里那句"已关掉射线"**只出现一次**（紧跟 `pos=1` ✓）
    --     ⇒ ★ 其余 6 个实例（以及后来复用的）**射线还开着** ✗ ⇒ ★ **放置过的卡上抢点击依旧** ✓✓
    --   ★ 列表项是复用的 ✓ ⇒ 每个实例各记一份 ✓（挂在 `_grid_item_rec` 的缓存表上 ✓）
    local _rg_pre = self:_grid_item_rec(item, index)
    if _rg_pre == nil or _rg_pre.gray_noray ~= true then
      if _rg_pre ~= nil then _rg_pre.gray_noray = true end
      if _cgray.raycastTarget ~= nil then pcall(function() _cgray.raycastTarget = false end) end
      if _cgray.blockRaycast ~= nil then pcall(function() _cgray.blockRaycast = false end) end
      if _cgray.interactable ~= nil then pcall(function() _cgray.interactable = false end) end
      print("[murdoku] 灰白层 `gray`：已关掉射线与交互（点击照常落在卡片上）")
    end
    local _rg = self:_grid_item_rec(item, index)
    if _rg ~= nil and _rg.gray ~= _placed_now then
      _rg.gray = _placed_now
      if _cgray.SetVisible then pcall(function() _cgray:SetVisible(_placed_now) end) end
      if _cgray.SetActive then pcall(function() _cgray:SetActive(_placed_now) end) end
    end
  end
  local t_portrait = cl.portrait        -- ★ 头像素材名（★ 如 `portrait.A` ✓；★ nil ⇒ 不写图 ✓）

  -- ★ 子控件句柄走记忆表（改之前：一次回调 54 次 `item:GetChild`，滚动时每帧 54 次）
  local c_who    = self:_grid_item_child_cached(item, index, pos, "who")
  local c_what   = self:_grid_item_child_cached(item, index, pos, "what")
  local c_letter = self:_grid_item_child_cached(item, index, pos, "letter")
  local c_face   = self:_grid_item_child_cached(item, index, pos, "face")

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **头像：每个列表项实例要【各写各的 `imageId`】** ✗✓
  --
  --   ★ 起因（★ 用户实测 ✓）：★「★ **五张卡的头像都一样**」✗
  --   ★ 根因 ✓：★ `face` 是**图片控件** ✓ ★ 模板只有一份 ✓
  --     ⇒ ★★ **它不会自己变** ✗ —— ★ 必须**逐个实例**写 `imageId` ✓✓
  --     ★（★ 文字那三个早就在写 ✓ ⇒ ★ 所以文字会不同、头像不会 ✓ —— 正是用户看到的现象 ✓）
  --
  --   ★ 写图的两条规矩（★ 与适配器里那条正路一致 ✓，见 `engine_adapter_qianxing.lua` L18/L705 ✓）：
  --     ★ ① ★ **优先 `SetImage(img.imageSource, id)`** ✗ —— ★ 沿用**编辑器里配的来源** ✓
  --        ★ 兜底才 `SetImage(id)` ✓（★ 真机上 `SetImage(nil, id)` 会失败 ✓ 那条注释写着 ✓）
  --     ★ ② ★ **素材名要过 `adapter:resolve_asset`** ✓ —— ★ 它把 `portrait.A` 变成可用的 id ✓
  --        ⚠️ ★ **`nil` 时【绝不能调】** ✗ —— ★ `resolve_asset` 查不到会 `warn_once` **打报错** ✓
  --        （★ 那个警告注释在 `engine_adapter_qianxing.lua` L4019 ✓）
  --     ★ ③ ★ **只在"这一项换了代表哪条线索"时写** ✓ —— ★ 与文字同一套去重 ✓
  --        ★（`tv.idx ~= index` ✓）⇒ ★ 稳态零成本 ✓
  --   ★ 失败一律 `pcall` ✓ ⇒ ★ 图没设上只失去"头像不同" ✗ ★ 不会把引擎的滚动打断 ✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  if c_face ~= nil and t_portrait ~= nil and t_portrait ~= "" then
    -- ★ 自己取一次记录表 ✓ —— ★ 不依赖下面文字那段的 `rec` ✓（★ 那段在这之后才定义 ✓）
    local rec_f = self:_grid_item_rec(item, index)
    local fv = rec_f and rec_f.face
    if fv == nil or fv.idx ~= index or fv.name ~= t_portrait then
      local want = t_portrait
      local id = nil
      pcall(function()
        if adapter ~= nil and adapter.resolve_asset ~= nil then id = adapter:resolve_asset(want) end
      end)
      if id ~= nil then
        local ok_img = false
        pcall(function() ok_img = c_face:SetImage(c_face.imageSource, id) end)
        if not ok_img then pcall(function() ok_img = c_face:SetImage(id) end) end
        if rec_f ~= nil then rec_f.face = { idx = index, name = want, ok = ok_img } end
      end
    end
  end

  -- ★★★★★ 2026-10-05 **文字只在"真的不一样"时才写**（写一次 = 引擎重排一次文本）。
  --
  --   改之前：一次回调无脑写 21 次（7 项 × 3 个角色），**内容一个字都没变也照写**
  --   ⇒ 滚动时每帧 21 次文本重排，纯浪费（"每帧重排文字"是 UI 卡顿最常见的来源）。
  --   ⚠️ 但「**空字符串照写**」这条规矩**必须保住**（用户明确要求）：复用出来的列表项上
  --      留着上一条的残留文字是"滚动之后内容错位"的经典成因 ⇒ 这里用 `tv.idx ~= index`
  --      来判断"这一项**换了代表哪条线索**"：换了就把三个角色**全部重写一遍**
  --      （哪怕新文字与旧文字相同），没换才逐字比较。既省掉稳态的 21 次，也不放过复用。
  local rec = self:_grid_item_rec(item, index)
  local tv = rec and rec.text
  if tv == nil or tv.idx ~= index then
    tv = { idx = index }
    if rec ~= nil then rec.text = tv end
  end
  if tv ~= nil then
    if tv.who    ~= t_who    then if write_control_text(c_who, t_who)       then tv.who    = t_who    end end
    if tv.what   ~= t_what   then if write_control_text(c_what, t_what)     then tv.what   = t_what   end end
    if tv.letter ~= t_letter then if write_control_text(c_letter, t_letter) then tv.letter = t_letter end end
  else
    -- 理论上到不了（`_grid_item_rec` 对非 nil 的 item 一定给得出记录）；兜底照旧写。
    write_control_text(c_who, t_who)
    write_control_text(c_what, t_what)
    write_control_text(c_letter, t_letter)
  end

  -- 子控件找不到时**只报一次**（这条日志直接告诉你要在模板里补哪个名字）
  if c_who == nil or c_what == nil or c_letter == nil then
    self:_grid_log("childmiss", "网格视窗：列表项子控件 who/what/letter = "
      .. ((c_who ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_what ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_letter ~= nil) and "有" or "**缺**")
      .. "（模板 1073742421 里应叫 `clue.1.who` / `clue.1.what` / `clue.1.letter`）")
  end


  -- 点击 → 聚焦（未验证能力，全程 pcall + 只报一次结论）
  self:_grid_bind_item_click(adapter, grid, item)
      self._grid_bind_n = (self._grid_bind_n or 0) + 1
      if self._grid_bind_n == 1 then print("[murdoku] ★ 诊断GRID：正在给列表项绑点击（第 1 个）") end
end

-- 给列表项挂点击。★ 列表项是**复用**的：同一个控件会先后代表不同线索 ⇒
--   回调里**不能**捕获 index，必须用 `GetItemIndex` 现查（见 `_on_grid_item_click`）。
--   重复挂监听会一次点击触发多遍 ⇒ 用一个**弱键表**按控件身份去重（控件回收后自动释放）。
function Controller:_grid_bind_item_click(adapter, grid, item)
  if item == nil or item.AddCursorEventListener == nil then
    if self._grid_bind_n == nil then
      self._grid_bind_n = 0
      local nm2 = "?"
      pcall(function() nm2 = tostring(item.name) end)
      print("[murdoku] ★ 诊断GRID：列表项【不支持光标事件】⇒ 点击绑不上！item=" .. nm2 .. "（AddCursorEventListener=" .. tostring(item ~= nil and item.AddCursorEventListener ~= nil) .. "）")
    end
    return
  end
  -- ★★★★★ 2026-10-05 **列表项是"引擎运行时克隆出来的按钮"，它的 `raycastTarget` 必须就地开**
  --   （每帧成本第 (3) 条的有意补偿）。
  --
  --   为什么：`Adapter:enable_raycast` 原来**每 20 帧整树重扫**，顺带盖住了
  --   "引擎后来克隆出来的列表项"；收敛之后不再重扫 ⇒ 晚到的卡片**没人给它开这个字段**
  --   ⇒ 「卡片点不动」。这里补上，而且更强：绑定那一刻就开（原来最多晚 20 帧），
  --   成本 1 次字段读写（原来是一趟 ≈ 470 个 `GetChildren`）。
  --   ⚠️ 放在**去重判断之前**：回收复用的项也要过这一道（引擎有可能把字段重置回去）。
  --   ⚠️ 也放在 `enum_at` 那个提前 return **之前** —— 离线环境没有 Enum，
  --      但真机上这个字段照样得开，两件事不相干。
  if adapter ~= nil and adapter.ensure_raycast ~= nil then
    pcall(function() adapter:ensure_raycast(item) end)
  end
  self._grid_bound = self._grid_bound
    or setmetatable({}, { __mode = "k" })          -- 弱键：列表项被引擎回收后不会攒着
  if self._grid_bound[item] then
    self._grid_click_ok = true
    return
  end
  local click = enum_at("CursorEventType.CursorClick")
  if click == nil then return end                  -- 枚举缺失 ⇒ 静默降级（离线环境就是这条路）
  local ok = pcall(function()
    item:AddCursorEventListener(click, function()
      -- 引擎回调里再包一层：这里出错会打断引擎自己的点击/滚动派发
      pcall(function() self:_on_grid_item_click(adapter, grid, item) end)
    end)
  end)
  if ok then
    self._grid_bound[item] = true
    self._grid_click_ok = true
  end
end

-- 点了某一条列表项 → 聚焦这条线索。
function Controller:_on_grid_item_click(adapter, grid, item)
  -- ★ 2026-10-07 **抢点击定位读数**（★ 一次定案 ✓ 最多 12 行 ✓）
  --   ★ 要分清三件事 ✓：
  --     ① ★ **回调有没有进来**（★ 进来 ⇒ 引擎把点击给了卡片 ✓ 没进来 ⇒ 被别的东西吃掉 ✗）
  --     ② ★ **该卡是不是"已放置"**（★ `gray` 是否可见 ✓）—— 你说的现象**只在放置过的卡上** ✓
  --     ③ ★ 读回 `gray` 的 `raycastTarget` / 可见性 ✓ ⇒ 看"关射线"到底生效没有 ✓
  if (self._clk_log or 0) < 12 then
    self._clk_log = (self._clk_log or 0) + 1
    local _i, _rt, _vis = "?", "?", "?"
    -- ★ 2026-10-07 修读数：★ `GetItemIndex` 是**网格**的方法（★ 不是列表项自己的 ✓）
    --   ★ 真机证据 ✓：★ 上一版打出 `index=?` ✓ ⇒ ★ 我调错对象了 ✓
    pcall(function() _i = tostring(grid:GetItemIndex(item)) end)
    if _i == "?" then pcall(function() _i = tostring(item:GetItemIndex()) end) end
    local _g = nil
    pcall(function() _g = self:_grid_item_child_cached(item, nil, 0, "gray") end)
    if _g ~= nil then
      pcall(function() _rt = tostring(_g.raycastTarget) end)
      pcall(function() _vis = tostring(_g.visible) end)
    end
    print("[murdoku] ★ 抢点击诊断：回调进来了 ✓ 列表项index=" .. _i
      .. "  gray存在=" .. tostring(_g ~= nil) .. " gray可见=" .. _vis .. " gray射线=" .. _rt)
  end
  -- ★ 官方：「列表项索引以运行时传入和返回的 index 为准」⇒ **只能反查**。
  --   按兄弟序号取是错的：列表项会被复用，兄弟顺序不稳定（用户也专门点了这一条）。
  local idx = nil
  pcall(function() idx = grid:GetItemIndex(item) end)
    if not self._grid_idx_log then self._grid_idx_log = 0 end
    if self._grid_idx_log < 5 then
      self._grid_idx_log = self._grid_idx_log + 1
      print("[murdoku] ★ 诊断GRID：列表项被点到了 ✓ GetItemIndex=" .. tostring(idx))
    end
  if type(idx) ~= "number" then
    -- 反查失败 ⇒ 这一次点击**宁可丢掉**，也不要聚焦到错误的一条（聚焦错了会误导推理）
    self:_grid_log("noindex", "网格视窗：GetItemIndex 读不到索引 ⇒ 这一次点击忽略（不改焦点）")
    return
  end
  local pos = idx - (self._grid_base or 1) + 1
  -- ★★★★★ 2026-10-07 **点卡片后强制重填一次** ✗✓（治"取消选中后高亮还在" ✓）
  --   ★ 真机反馈 ✓：★「★ **预放置的卡，取消选中后高亮还在**」✗
  --   ★ 机制 ✓：★ 高亮由**填充**按 `core.selected` 画 ✓（提交 371 ✓）
  --     ⇒ ★ 而"取消选中"这一步**不触发重填** ✗ ⇒ ★ 填充没机会把金色复原 ✓✓
  --   ⇒ ★ 这里清掉网格签名 ✓ ⇒ ★ 下一帧重填 ⇒ ★ **高亮立刻跟着选中状态走** ✓✓
  --     ★（★ 与"放置后重填"用的是同一招 ✓ 提交 363 ✓ 一套机制两处用 ✓）
  self._grid_sig = nil
  local n = #((self.core:view() or {}).clues or {})
  if pos < 1 or pos > n then return end

  -- ★ 走**和老卡片完全同一条**输入通路：`adapter.on_input` 是 main.lua 接的
  --   （`controller:on_input(event)` + 立刻渲染）⇒ 点列表项和点 `clue.N` 的后续行为
  --   （焦点切换、CLUE_IN 特效、重绘）一模一样，不会出现"两套焦点逻辑"。
    -- ★★★★★ 2026-10-07 **网格选中视觉（只染聚焦那条）** ✗✓
  --   上一版两个错（用户实测：★"没有点击高亮，但描边更亮了"✓）：
  --     ① 给**未聚焦**的项也写了白色 ⇒ **整排描边变亮** ✗
  --     ② 染色写在**填充回调**里 ⇒ 而填充只在"数据变化/滚动"时跑 ⇒ **点击后不重填 ⇒ 高亮永不出现** ✗
  --   ⇒ 现在：★ **在点击处直接染** ✓ **只染聚焦那条** ✓ **换项/取消时恢复原色** ✓
  local function _bp_get(it, ix, px)
    local c2 = nil
    pcall(function() c2 = self:_grid_item_child_cached(it, ix, px, "backrop1") end)
    return c2
  end
  local turning_on = (self.focused_clue ~= pos)
  local prev_item, prev_idx, prev_pos = self._grid_focus_item, self._grid_focus_idx, self._grid_focus_pos
  if prev_item ~= nil then
    local pc = _bp_get(prev_item, prev_idx or 0, prev_pos or 0)
    if pc ~= nil then
      local oc = self._grid_focus_orig
      if oc ~= nil then pcall(function() pc.imageColor = oc end) end
    end
    self._grid_focus_item, self._grid_focus_orig = nil, nil
  end
  if turning_on then
    local c2 = _bp_get(item, idx, pos)
    if c2 ~= nil then
      local cur = nil
      pcall(function() cur = c2.imageColor end)
      self._grid_focus_orig = cur
      self._grid_focus_item, self._grid_focus_idx, self._grid_focus_pos = item, idx, pos
      pcall(function() c2.imageColor = 4294956107 end)   -- ★ 暖金（乘算着色）
    end
  end
  -- ★ 2026-10-07 一次性诊断：把该线索记录的【真实字段名】打出来（方案 A 取值失败 ⇒ 不猜了）
  if (self._diag_clue or 0) < 3 then
    self._diag_clue = (self._diag_clue or 0) + 1
    local ks, vs = {}, {}
    pcall(function()
      local v3 = self.core:view() or {}
      local c3 = (v3.clues or {})[pos]
      if c3 ~= nil then
        for k, v in pairs(c3) do
          ks[#ks + 1] = tostring(k)
          if type(v) ~= "table" then vs[#vs + 1] = tostring(k) .. "=" .. tostring(v) end
        end
      end
    end)
    print("[murdoku] ★ 诊断CLUE：pos=" .. tostring(pos) .. "  字段名=[" .. table.concat(ks, ",")
      .. "]  值(" .. table.concat(vs, " ") .. ")")
  end
  -- ★★★★★ 2026-10-07 **方案 A：点线索卡 = 高亮这条 + 选中卡上那个人** ✗✓（用户确认走 A ✓）
  --
  --   为什么必须有：真机日志「★ **点 (第1行 第2列) 没生效：先点一个头像　当前工具=place　已选=nil**」✓
  --     ⇒ ★ **`selected` 一直是 nil** ⇒ ★ **铅笔笔记 / 预放置 / 正式放置【三者全被拦在这一步】** ✓
  --   根因：★ 老卡片里头像 `face` 是**按钮**（`push({id="clue."..i..".face", kind="button"})` ✓）
  --     点它才发 `suspect` ✓ 而**网格模式下列表项点击只发 `focus_clue`** ✗ ⇒ ★ **选人的手势丢了** ✓
  --   ⇒ 这里补上：★ **点卡片即选中卡上那个人** ✓（★ 一步完成"高亮 + 选人"✓）
  --   ★ 取值**防御式**：线索记录里人物字段可能叫 `person`/`who_id`/`id`/`key` ✓
  --     再兜一层"从头像素材名 `portrait.X` 里取 X" ✓ 取不到就不动作（绝不误选）✓
  pcall(function()
    local v2 = self.core:view() or {}
    local cl = (v2.clues or {})[pos]
    if cl ~= nil then
      -- ★ 真字段名（真机探针实测 ✓）：★ `who` —— 值形如 `V` / `D` / `@thief`
      --   ⇒ `@` 开头的是【特殊角色】（如盗窃者），不是可选的"人"，跳过 ✓
      local pid = cl.who or cl.person or cl.who_id or cl.id
      if type(pid) == "string" and pid:sub(1, 1) == "@" then pid = nil end
      if pid == nil then
        local pn = cl.portrait or cl.face or cl.asset
        if pn ~= nil then pid = tostring(pn):gsub("^portrait%.", "") end
      end
      if pid ~= nil then
        local ev2 = { action = "suspect", id = pid }
        if type(self.adapter) == "table" and type(self.adapter.on_input) == "function" then
          self.adapter.on_input(ev2)
        else
          self:on_input(ev2)
        end
      end
    end
  end)
local ev = { action = "focus_clue", index = pos, phase = "click" }
  if adapter ~= nil and type(adapter.on_input) == "function" then
    adapter.on_input(ev)
  else
    self:on_input(ev)
  end
end

----------------------------------------------------------------------------
-- 增量渲染
----------------------------------------------------------------------------

-- ★★★★★ 2026-10-05 **写属性的唯一入口：一律包 `pcall`**。
--
--   为什么：真机上那个"每帧刷、永久刷"的报错就是 set_property 抛出来的
--     （`attempt to call method 'imageSource' on an invalid object`，
--       见 `build_layout` 里那段根因注释），而它是在 `render` **里面**抛的 ⇒
--     后面所有节点全没处理 ⇒ 连带症状一大串（模板格子出不来、`clues.bg` 时有时无）。
--   ⇒ 原则：**一个属性写不进去，只该少显示一样东西，绝不该把整帧渲染打断**。
--     适配层那边"句柄可能是引擎回收过的列表项"这件事我们管不了（不在本文件里），
--     但"它抛错会不会连累整帧"是我们能兜住的。
--
--   ⚠️ 报错**按 id + 键各报一次**，而且**最多只列 8 条**（第 9 条换成一句总结）：
--      一个坏句柄会每帧抛，不去重/不限量就是拿日志刷屏 —— 那正是用户这一轮最烦的事。
function Controller:_set_prop(adapter, id, key, value, nkey)
  -- ★★★★★ 2026-10-05 **多带一个 `nkey`：这把键就是属性账本那把 `node_key`。**
  --
  --   为什么要有它：`build_layout` 里**同一个 id 会出现在两个节点上**
  --   （`action.back`：一个挂 `topbar`、一个挂 `right`），而适配层的**事件表**
  --   原来是按控件 id 记的 ⇒ 两个节点轮流写同一格 ⇒ **后写的把先写的吃掉**
  --   （静默、不报错）。
  --   ⇒ 把账本**已经算好的**那把键原样传下去，适配层用它给每个规划节点各记一份。
  --   ⚠️ **不要**在适配层另造一套键（"一条规则两个权威"本项目刚在 BOM 上栽过）——
  --      这里传的就是 `render` 里 `local nkey = node_key(n)` 那一个值。
  --   ⚠️ 其它键（text/visible/...）用不到它，传了也只是忽略；留成可选参数，
  --      旧调用方（离线假适配器）少传一个参数照样跑。
  -- ★★★★★ 2026-10-05 **返回值从"没抛错"升级成"真的送到了"**。
  --
  --   为什么：适配层 `set_property` 在 `find(id) == nil` 时是**静默 no-op**（不抛错、也不写），
  --   而这里原来只回传 `pcall` 的结果 ⇒ **静默 no-op 也算成功** ⇒ 调用方（`render` 的
  --   增量账本）把这条属性记成"已下发" ⇒ 本关内**永不补发**，只能出关重进
  --   ⇒ 真机表现就是我们这一轮在查的"**第一次进关渲染得比第二次少**"。
  --   ⇒ 现在把适配层的判定原样往上传：`true` = 送达（可以记账），`false` = 没送到（可以补发）。
  --
  --   ⚠️ 兼容老适配器 / 离线假适配器：它们**不返回值**（`res == nil`）——
  --      这里只有**明确的 `false`** 才算失败。把"没返回值"当成失败，会让每个属性每帧重发
  --      （离线测试立刻炸：那是"查不了 = 不存在"的老坑）。
  local ok, res = pcall(function() return adapter:set_property(id, key, value, nkey) end)
  if not ok then
    local k = tostring(id) .. "." .. tostring(key)
    self._prop_err_seen = self._prop_err_seen or {}
    if not self._prop_err_seen[k] then
      self._prop_err_seen[k] = true
      self._prop_err_n = (self._prop_err_n or 0) + 1
      if self._prop_err_n <= 8 then
        self:_grid_log("prop_err:" .. k, "属性下发失败（已跳过这一条，不再每帧刷）：`"
          .. k .. "` ← " .. tostring(res))
      elseif self._prop_err_n == 9 then
        self:_grid_log("prop_err_more", "属性下发失败：已经列了前 8 条，后面的不再逐条打印"
          .. "（同一类【句柄失效】，只影响个别控件，**不会再打断整帧渲染**）")
      end
    end
  end
  return ok and (res ~= false)
end

function Controller:render(adapter, force)
  -- ★★★★★ 2026-10-05 **切屏 / 换关 = "控件树这一代作废"的权威事件**（性能修复第 2 半）。
  --
  --   为什么要有这个事件：适配层现在有两处**按代缓存**的东西 ——
  --     · 控件名缓存（含**未命中**缓存，见 `Adapter:find` 上面那段注释）；
  --     · 兜底隐藏（`enforce_hidden_subtrees`，从"每帧扫"改成"事件驱动"）。
  --   两者的作废时机**完全一样**，所以只在这里判定一次、只调一个函数
  --   （`Adapter:invalidate_lookups`）—— 免得以后有人只改一处、另一处留成陈年老 bug。
  --
  --   判据用 (screen, level_id) 这一对：
  --     · `screen`：主页 / 选关 / 关卡内（nil）—— 切屏会整套换显示哪棵子树；
  --     · `level_id`：换关时 `cell.*` / `clue.*` 的**名字集合**整个换一代，
  --       而适配器**是跨关复用的**（`main.lua` 的 `prepared_adapter`），
  --       不做这一步的话，"上一关没有、这一关有"的控件会被负缓存判成不存在。
  --   ⚠️ 放在 `sync_clue_grid` **之前**：切屏那一帧的 `find` 本来就该重新搜树
  --      （这正是"缓存可能过期"的那一帧），顺序反了等于拿旧缓存去建新一帧。
  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter ~= nil and adapter.invalidate_lookups ~= nil then
        pcall(function()
          adapter:invalidate_lookups("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      -- ★★★★★ 2026-10-05 **换屏 / 换关也要"重新武装"射线开关那一趟**（每帧成本第 (3) 条）。
      --
      --   为什么必须在这里、而且**只在这里**：
      --     · 换屏/换关是**长出新控件**的权威事件（`home` / `select` 是第一次渲染时才
      --       `create_control` 的）——早停之后不重新武装，新屏幕的控件就**永远开不上
      --       `raycastTarget`** ⇒ 又回到"界面看得见、点哪儿都没反应"。
      --     · ⚠️ **不能**挂进 `invalidate_lookups`：那个函数还被 `create_control` /
      --       `destroy_control` **每个控件各调一次**（进关时几十次）⇒ 挂那儿等于
      --       "每建一个控件就重扫一趟整树"，白跑比改之前还多。
      --       所以复用的是**同一个判据块**（screen/level 换代），不是同一个函数。
      if adapter ~= nil and adapter.rearm_raycast ~= nil then
        pcall(function()
          adapter:rearm_raycast("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
    end
  end

  -- ★★★★★ 2026-10-05 **网格视窗先探一步**（必须在 `build_layout` 之前）。
  --
  --   为什么必须在前面：`build_layout` 要按"这一关到底走哪条路"决定
  --   `clues.grid` 藏不藏、老卡片让不让位（见 `sync_clue_grid` 与那段收口的注释）。
  --   顺序反过来的话，会让位晚一帧 —— 表现成"进关第一帧两套线索叠在一起"。
  --
  --   它自己保证：任何一步失败都只报一次、并且退回老路径（`_grid_state = "off"`）。
  self:sync_clue_grid(adapter)

  local nodes = self:build_layout()

  -- ★★★★★ 2026-10-05 **网格视窗在用时，"老一套线索控件"的名字一个都不许再碰。**
  --
  --   为什么：适配层的 `find(name)` 是**按名字**深度优先搜的，而网格视窗的列表项模板
  --   子控件就叫 `clue.1.who` / `clue.1.face` …（用户是照着第 1 张卡另存的模板）
  --   ⇒ 碰这些名字 = 可能抓到**已经被回收的列表项** ⇒ 句柄失效 ⇒ 属性下发抛错
  --     （真机日志见 `build_layout` 里那段根因注释）。
  --
  --   为什么在 `render` 里还要再拦一道：**切换的那一帧**。
  --     `_grid_state` 是上一帧渲染末尾才可能从 nil 变成 "on" 的（`sync_clue_grid`
  --     要等 RefreshItems 真的回调成功），所以 `_shown` / `_created` 里可能还留着
  --     上一帧按老路径建过的 `clue.N` —— 差集循环会拿它们去"藏起来"，清理循环
  --     会拿它们去"销毁"（那会把网格视窗正在复用的列表项关掉/毁掉）。
  --   ⇒ 判据和 `build_layout` 共用 `is_legacy_clue_id`（一处定义，三处使用）。
  local grid_on = (self._grid_state == "on")
  local function stale_legacy(id) return grid_on and is_legacy_clue_id(id) end

  -- 设备档位（pc / touch / gamepad）只在第一次渲染时探一次，用来决定提示文案。
  -- 界面本身完全一样 —— 两种模式走的是同一套光标事件。
  if self.input_profile == nil then
    self.input_profile = "pc"
    if adapter ~= nil and adapter.input_profile ~= nil then
      pcall(function() self.input_profile = adapter:input_profile() end)
    end
  end

  -- ★★ 必须**先把本帧要显示的 id 收齐，再算差集**。
  --    2026-09-26 踩过的坑：差集循环写在收集 seen 之前，seen 一直是空表，
  --    于是"上一帧显示过的全部"每帧都被藏一遍；而增量渲染又因为
  --    `last["visible"] == n.visible` 判定"没变"不再显示回来 ——
  --    结果是**第一次渲染之后整个界面就再也不可见**（而且一个报错都没有）。
  local seen = {}
  for i = 1, #nodes do seen[nodes[i].id] = true end

  -- 弹窗/教程/多余格子这些控件**在编辑器里是一直存在的**，只是不该显示时
  -- 不出现在布局里。第一次渲染先把"除了当前布局以外"的全部藏起来；
  -- 之后每次只藏"上一次显示过、这一次不在布局里"的。
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **`forget_visible` 提到两个分支之外** ✗✓ —— 修 `clues.grid` 永远 false ✓
  --
  --   ★ 根因（★ 真机实测 ✓）：★ 同一件事**两处实现，只修了一处** ✗✓
  --     · **首帧**分支（下面 `if self._shown == nil then`）★ **有** `forget_visible` ✓
  --     · **"之后每次"**分支（`else` 里那个 `for pairs(self._shown)`）★ **没有** ✗✗
  --   ⇒ ★★ 后果（★ 与用户实测完全吻合 ✓）：
  --     ★ ① 主页/选关那一帧 ⇒ `clues.grid` 不在 `seen` ⇒ **差集主动发 `false`** ✗
  --        ★ **并记进账本**（`last["clues.grid….visible"] = false` ✓）
  --     ★ ② 进关卡 ⇒ 规划算出 `visible = **true**` ✓（★ 诊断实测 `_grid_state = on` ✓）
  --        ★★ 而属性循环有账本：★ `same_value(last[k], true)` ⇒ **判"没变"⇒ 不发** ✗✗
  --        ⇒ ★★★ **它永远停在 false** ✓✓ ⇒ ★ **父不可见 ⇒ 列表项再可见也不渲染** ✓
  --   ★ 真机铁证 ✓：★ 五个列表项 `visible=true` ✓ 而父 `clues.grid = false` ✗
  --   ★★ 这就是本项目第 N 次「**同一件事两处负责 ⇒ 必然漂移**」✓
  --     ★（`erases` / 上色 / 缩放表 / 关卡清单 / 显隐 …都是同一个形状 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  local function forget_visible(id)
    if self._props == nil then return end
    local pre = tostring(id) .. "\1"
    for k, rec in pairs(self._props) do
      if type(k) == "string" and k:sub(1, #pre) == pre and type(rec) == "table" then
        rec.visible = nil
      end
    end
  end
  if self._shown == nil then
    local all = self:layout_plan()
    -- ★★★★★ 2026-10-05 **藏完必须【清账本】** ✗✓ —— 这才是"永久丢失"的根治 ✓
    --
    --   为什么（与 `apply_screen_hide` 那处是一件事的两半 ✓）：
    --     · 差集在这里**主动发** `visible=false` ✗（走 `_set_prop` ✓ 会**记账** ✓）
    --     · 而"要显示"是靠属性循环发 `visible` ✓ —— 但它有账本：`last[k] == v` ⇒ **判"没变"就不发** ✗
    --     · ⇒ ★★ 账本里还留着"上次发过 `true`"✗ 而控件**已被差集藏掉** ✗
    --          ⇒ **再也不会发 `true`** ✗ ⇒ ★【永久丢失】✗✓
    --   ⇒ ★ 所以：**凡是主动藏掉的 id，就把它名下所有规划节点的 `last.visible` 置 nil** ✓
    --     ⇒ 下一帧"该显示"时账本认为"没发过"⇒ **重发 `true`** ✓✓
    --   ★ 症状对应（用户实测 ✓）：退出重进第一关没用 ✗（同一条路）·
    --     去一次别的关卡才行 ✓（切屏时 `clues` 重进 `seen` ⇒ 走"显示"那条路重发 ✓）
    --   ⚠️ 键格式 = `id \1 父容器 \1 出现序号`（见 `node_key` ✓）⇒ 用前缀匹配 ✓
    --     （与 `drop_props_of` 同一套写法 ✓ 不另造格式 ✓）
    -- ★ 旧位置那个同名 `forget_visible` 已提到上面（两分支共用）✓

    for i = 1, #all do
      if not seen[all[i].id] and not stale_legacy(all[i].id) then
        self:_set_prop(adapter, all[i].id, "visible", false)
        forget_visible(all[i].id)          -- ★ 藏了就忘掉"发过没有"⇒ 下次该显示时会重发 ✓
      end
    end
    -- ★ 上面只能藏住"当前这一关自己的布局里没有的"控件。
    --   但编辑器是照**所有关卡的最大并集**建的，多出来的控件（cell.6.6 / clue.12 /
    --   tray.F …）界面层根本不知道它们存在，只能让适配层去控件树上扫。
    --
    --   ⚠️ `hide_unlisted` **照旧要调**（即使网格视窗在跑）：它扫的是 `clues` 这一类
    --      托管容器的**直接子控件**，网格视窗的列表项挂在 `clues.grid` 下面、不在这一层，
    --      不会被误伤；而它正好负责把编辑器里遗留的老卡片（`clue.1..18` 本体）关掉。
    if adapter.hide_unlisted ~= nil then
      adapter:hide_unlisted(seen)
    end
  else
    for id in pairs(self._shown) do
      -- ⚠️ 切换帧：上一帧的老线索 id **不藏也不销毁**（名字现在归网格视窗的列表项所有）
      if not seen[id] and not stale_legacy(id) then
        self:_set_prop(adapter, id, "visible", false)
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        -- ★★ 2026-10-06 **这里原来【没有】`forget_visible`** ✗✓ —— ★ 就是 `clues.grid` 的病根 ✓
        --   ★ 首帧分支有 ✓ ★ 这条"每次"的道路没有 ✗ ⇒ ★ 藏了却把"发过 false"记在账本里 ✓
        --   ⇒ ★★ 下一帧规划要发 `true` 时 ⇒ ★ `same_value` 判"没变" ⇒ **不发** ✗✗
        --     ⇒ ★★★ **永久停在 false** ✓ ⇒ ★ 父不可见 ⇒ **列表项再可见也不渲染** ✓✓
        --   ★ 真机铁证 ✓：★ 五个列表项 `visible=true` ✓ 而 `clues.grid = false` ✗
        --   ★★ 同一件事两处实现、只修了一处 ✗ ⇒ ★ 这正是本项目反复踩的那条形状 ✓
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        forget_visible(id)               -- ★ 藏了就忘 ⇒ 下次该显示时会重发 ✓✓
      end
    end
  end
  self._shown = seen          -- 记住这一帧显示了什么，下一帧据此算差集

  -- ★★★★★ 2026-10-05 **"补发"这套规则只在这里实现一份**（属性循环和 rect 两条路共用）。
  --
  --   为什么必须**有上限**：规划里有 ~105 个"本关还没建"的控件（见 `layout_plan` 那句
  --   「这些控件还没建」），它们每一条属性都**必然**失败 —— 无上限重试就是
  --   "每帧白跑（`find` 是深度优先搜控件树）+ 日志刷屏"，正是这一轮最不该引入的回退。
  --   ⇒ 同一个 (控件, 属性) 最多补发 `PROP_RETRY` 次；到顶就**认输**：
  --     记账（`last[k] = v` ⇒ 下一帧不再看见它）+ **只报一次**。
  --   额度为什么是 **3**（⚠️ 这段注释原写「10」，与下面的代码 `PROP_RETRY = 3` **不一致** ——
  --   第一遍代码体检发现的注释/代码漂移，已按代码改正）：`render` 由 main.lua 的 tick 驱动
  --   （**每秒至少一次**，另加"有变化时"），所以 3 次 ≈ 几秒内 —— 覆盖"控件晚一步才进树"
  --   这种可恢复情形；而真不存在的控件最多也就白跑这 3 次。**它是常数，不会随时间增长。**
  --   ⚠️ 不要再把它调回 10：v066 真机实测过"~105 个本关没建的控件每个属性白补发 10 次"
  --      ⇒ 加载慢十倍 + 切屏卡顿（见下面 `select.pos_runtime` 那段事故记录）。
  local PROP_RETRY = 3
  -- 成功 ⇒ 清掉这个键的计数（额度不跨"属性变化"累积：这一关失败过几次，不该影响下一次）。
  local function retry_clear(id, key)
    if self._prop_retry ~= nil then
      self._prop_retry[tostring(id) .. "\1" .. tostring(key)] = nil
    end
  end
  -- 失败 ⇒ 记一次。返回 true = **还有额度，下一帧再试**；false = **认输，调用方该记账了**。
  --
  -- ★★★★★ 2026-10-05 **两种失败必须分开给额度** ✗✓（用户实测：**第一关渲染不齐、之后正常**）
  --
  --   为什么：真机日志（`日志_2026/10/05_22:18:35`）把区别指出来了 ——
  --     · **第一遍进关**：`棋盘格子：25 / 25 存在（★ 本次新建 25 个，模板索引 1073741876）` ✗
  --     · **之后任何一关**：`棋盘格子：25 / 25 存在（★ 本次新建 0 个，模板索引 nil）` ✓
  --   ⇒ ★★ 只有"**本次新建**"的那一次，模板子控件（`wall.*` / `door.*` / `note` / `x`）
  --      不是同一帧就绪 ✗ ⇒ `_apply_edges` 的 `self:sub()` 查不到 ⇒ 静默跳过 ✗
  --      ⇒ 补发 3 帧后认输 ⇒ ★ **第一关的墙/门永远不亮** ✗（之后的关卡复用已就绪的实例 ✓）
  --
  --   ⇒ 所以判据是**两种完全不同的失败**：
  --     ① ★ **控件本身不存在**（本关不建的 ~105 个 ✗）⇒ 必然永远失败 ⇒ **3 次就认输** ✓
  --        ★ 这个数字**不能动** ✗ —— v066 真机实测过 10 ⇒ **加载慢十倍 + 切屏卡顿** ✓
  --     ② ★ **控件在、只是它的模板子控件还没就绪** ✗ ⇒ ★ **它一定会就绪** ✓ ⇒ **值得多等一会儿** ✓
  --        ★ 额度用**时间**（`self.now` ✓ 秒）而不是帧数 ✗ —— 帧率在不同机器上含义不同 ✓
  --        ★ 而且**只在"控件存在"时才放宽** ✗ ⇒ 那 ~105 个不存在的控件仍走 3 次上限 ✓✓
  --
  --   ⚠️ 上限依然存在（`SUB_READY_SECONDS`）✗ ⇒ **不会变成每帧死循环** ✓
  local SUB_READY_SECONDS = 2.5   -- ★ 等子控件就绪：约 2.5 秒（足够覆盖模板实例化 ✓ 且有限 ✓）
  local function retry_more(id, key, why, exists)
    local rk = tostring(id) .. "\1" .. tostring(key)
    self._prop_retry = self._prop_retry or {}
    -- ★★ 账本**形状不变** ✗ —— `self._prop_retry[rk]` 仍然是**数字**（次数）✓
    --   ★ 首次失败的时刻**另存一张表** ✓（`self._prop_retry_t0`）
    --   ⚠️ 为什么不把数字换成表 ✗：`tests/prop_ledger.lua` 断言的就是这个数字 ✓
    --      第一版我改成了表 ⇒ 它立刻 13/0 → 11/2 ✗（**这就是退化的来源** ✓ 已改回 ✓）
    local n_try = (self._prop_retry[rk] or 0) + 1
    self._prop_retry[rk] = n_try
    if n_try == 1 then
      self._prop_retry_t0 = self._prop_retry_t0 or {}
      self._prop_retry_t0[rk] = self.now or 0
    end
    -- ★ ① 控件不存在 ⇒ 老规矩：3 次认输 ✓（性能红线，不许放宽 ✗）
    -- ★ ② **只有 `walls`/`doors`** 才配得上"等子控件" ✓✓ —— 见下
    --   ⚠️ 第一版我写成"只要控件在就放宽" ✗ ⇒ `prop_ledger` 立刻 13/0 → 11/2 ✗✓
    --     （`action.back` 也"存在 + 写失败" ✗ 但它的失败**不是**子控件没就绪 ✗
    --       —— 它是**两个规划节点抢同一个控件** ✓ ⇒ 被放宽后每帧重发 2.5 秒 ✗）
    --   ⇒ ★ **测试抓对了** ✓ ⇒ 收窄到**真正会"子控件晚一步就绪"的那两个键** ✓✓
    --     ★ 依据：`Adapter:_apply_edges` 的 `missing_sub` 只出现在 `wall.*` / `door.*` ✓
    --       （`engine_adapter_qianxing.lua:3670-3681`：取不到 `cell.<R>.<C>` 的
    --        `wall.<side>` / `door.<side>` 子控件 ⇒ 返回 false ✓）
    --     ★ 而 `label`/`bg` 之类走的是别的分支 ✓ 不在此列 ✓
    if exists == true and (key == "walls" or key == "doors") then
      local t0 = (self._prop_retry_t0 or {})[rk] or (self.now or 0)
      if (self.now or 0) - t0 < SUB_READY_SECONDS then return true end
    else
      if n_try < PROP_RETRY then return true end
    end
    -- ★ 认输也要留一句话：否则"这条属性到底补上没有"在日志里查不到 ——
    --   而这正是这一轮要回答的问题（第一次进关 vs 第二次进关的差别）。
    --   ⚠️ **不能每条都打**：那 ~105 个没建的控件的属性会一起走到这里 ⇒
    --      照 `prop_err` 的老规矩：**最多 5 条 + 一句汇总**。
    self._prop_giveup_n = (self._prop_giveup_n or 0) + 1
    if self._prop_giveup_n <= 5 then
      self:_grid_log("prop_giveup:" .. rk,
        "属性补发 " .. n_try .. " 次仍未送达，已停止补发：`"
        .. tostring(id) .. "." .. tostring(key) .. "`（" .. tostring(why) .. "）"
        .. (exists == true and "　★ 注意：**控件是存在的** ✗ —— 这条属于「子控件一直没就绪」"
            or "　（控件本身不存在，属正常）"))
    elseif self._prop_giveup_n == 6 then
      self:_grid_log("prop_giveup_more",
        "属性补发失败：已经列了前 5 条，后面的不再逐条打印"
        .. "（脚本里「本关还没建」的控件本来就有 ~105 个，它们都会走到这里；"
        .. "具体是哪些见上面那句「这些控件还没建」）")
    end
    return false
  end

  -- ★★★★★ 2026-10-05 **属性账本按「计划节点」记账，不按控件 id。**
  --
  --   为什么（这一轮实测抓到的真凶之一）：`build_layout` 里**同一个 id 会出现在两个节点上**
  --   （最典型：`action.back` —— 一个挂 `topbar`、一个挂 `right`，见 L1730 与 L2355）。
  --   而账本原来是 `self._props[n.id]`，**两个节点共用一份"上一帧发过什么"**
  --   ⇒ 节点1 写 `parent=topbar`、节点2 立刻写 `parent=right`（对同一个键来说永远"变了"）
  --   ⇒ 下一帧又是同样两笔，**永远收敛不了**：
  --     · 每帧白跑一次 `find`（深树存在性探测）+ 一次 `set_property`；
  --     · 实测（`tests/grid_cost.lua` [A1]/[E]）：稳态一次 render 里 **10 次搜空**
  --       全是这两个 `action.back`（300 帧 = 3000 次），`rect`/`text`/`style`/`parent`
  --       四个键每个都发两遍。
  --
  --   键 = `id \1 父容器 \1 同(id,父容器)的第几次出现`：
  --     · 带上**父容器**：`action.back` 的两个节点就此分开（各自记账、各自收敛）；
  --     · 带上**出现序号**：万一将来同一个 id 在同一父容器下也出现两次，仍然分得开；
  --     · 用 `\1` 作分隔符（本文件里 `_prop_retry` 已经用这个约定，且 id 里不可能有它）。
  --   ⚠️ `self._created` **仍然按 id** —— 一个 id 只对应**一个**引擎控件，
  --      `create_control` 只能跑一次；而**事件表**已经跟着账本一起改成按规划节点
  --      （`Adapter:set_property` 的 `key == "event"` 分支）——
  --      **本文件把这个 `nkey` 原样传下去**（见 `_set_prop` 的第 5 个参数），
  --      适配层不另造键。
  --   ⚠️ **点击派发改用「认领者」（B2，用户 2026-10-05 拍板 ✓）**：一个 id 只有一个引擎控件、
  --      只有一次绑定，所以只能派发**一份**事件 ⇒ "选哪一份"就是"这颗按钮是什么意思"的决定。
  --      适配层取 `event_claim[id]` = **第一个**给这个控件写 event 的规划节点（**先写的赢**），
  --      不再是"最后写的那个"（`event_latest` 已降级为**纯诊断记录**）。
  --      对 `action.back` 而言 = `topbar` 的那一份 = **`back_confirm`**（「返回菜单」）
  --      ⇒ **鼠标点它和点左上 ↰ 图标走同一条路：先弹 ✓/✗**
  --      （`ui_controller.lua:854` `a == "back_confirm"` ⇒ `self.pending = { action = "back" }`）。
  --      为什么：改之前是"最后写的赢" = `right` 的 `back` ⇒ **鼠标直接跳列表**，而 ↰ 图标
  --      却是 `back_confirm` **先弹 ✓/✗** ⇒ 同一颗按钮两种语义（自相矛盾 ✗）。
  --      三条硬证据与完整理由见 `lua/engine_adapter_qianxing.lua` 的 `Adapter.new`
  --      `self.event_claim` 那段（那里是这条规则的**唯一权威**）。
  local node_seq = {}
  local function node_key(n)
    local base = tostring(n.id) .. "\1" .. tostring(n.parent)
    local seq = (node_seq[base] or 0) + 1
    node_seq[base] = seq
    return base .. "\1" .. tostring(seq)
  end
  -- 控件离开计划时，把它名下**所有**计划节点的账本一起扔掉（前缀匹配，见上面的键格式）。
  local function drop_props_of(id)
    local pre = tostring(id) .. "\1"
    local stale = nil
    for k in pairs(self._props) do
      if type(k) == "string" and k:sub(1, #pre) == pre then
        stale = stale or {}
        stale[#stale + 1] = k
      end
    end
    if stale ~= nil then
      for i = 1, #stale do self._props[stale[i]] = nil end
    end
  end

  for i = 1, #nodes do
    local n = nodes[i]
    local nkey = node_key(n)
    if not self._created[n.id] then
      -- create_control 也包一层：它内部会 `find` 控件树，真机上"某个节点不提供方法"
      -- 这种事本项目已经踩过（`GetChildren` 那个坑）。建不出来只该少一样东西，
      -- **不该让整帧渲染停在这里**。
      local ok_c, err_c = pcall(function() adapter:create_control(n) end)
      if not ok_c then
        self:_grid_log("create_err:" .. tostring(n.id), "创建控件失败（已跳过这一条，不再每帧刷）：`"
          .. tostring(n.id) .. "` ← " .. tostring(err_c))
      end
      self._created[n.id] = true     -- 记上：免得每帧重试 + 重刷日志
      -- ★ 新的一生 ⇒ 补发额度也归零（见下面「认输」那段）。
      --   不清的话，"被销毁后又重建回来"的控件会**继承上一次的失败次数**，
      --   第一次没写进去就直接认输 —— 那就把这一轮修的毛病又放回来了。
      if self._prop_retry ~= nil then
        local pre = tostring(n.id) .. "\1"
        local stale = {}
        for rk in pairs(self._prop_retry) do
          if rk:sub(1, #pre) == pre then stale[#stale + 1] = rk end
        end
        for j = 1, #stale do self._prop_retry[stale[j]] = nil end
      end
    end
    -- ⚠️ 账本**必须在这里兜底建出来**（不能再放在上面 `if not self._created` 里面）：
    --    第二个同 id 节点永远不会进那个分支（`_created[id]` 已经是 true），
    --    照旧写法它的 `last` 就是 nil ⇒ 每个键都"变了" ⇒ 每帧重发，等于没修。
    local last = self._props[nkey]
    if last == nil then
      last = {}
      self._props[nkey] = last
    end
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
          -- ★★★★★ 2026-10-05 **只有"真的写进去了"才记账** —— 修"第一次进关画得少、第二次正常"。
          --
          --   真机证据（用户实测）：首次进关卡时门/墙 `visible` 读到 true 却**没画出来**，
          --   第二次进同一关（同样的数据）就正常了 —— 这正是"首关限定"的形状。
          --
          --   机制：适配层在 `find(id) == nil` 时是**静默 no-op**（不报错、也不写），
          --   而这里原来是**无条件** `last[k] = v` ⇒ 首次没送达的属性被记成"已下发"
          --   ⇒ **本关内永不重试** ⇒ 只有等下一关（控制器重建、`_props` 清空）才补上。
          --
          --   ⚠️ 但不能无脑每帧重试：规划里有 ~105 个"本关还没建"的控件（日志里那句
          --      「这些控件还没建」），无脑重试 = 每帧白跑 + 噪音 ⇒ **同一个 id.键 最多试
          --      N 次**，超了就认输（记账、不再试），既补上"晚一帧就绪"的控件，
          --      又不会变成性能回退。
          --   ⚠️ **适配器没有 `find` 时一律当作"存在"**（=退回旧行为）：
          --      假适配器（离线测试）就没有 find —— 把"查不了"当成"不存在"会让
          --      每个属性每帧都重写一遍（board_bg 立刻从 28/0 变 0/1 就是这条）。
          --      **查不了就别改变行为**是这里的唯一正确语义。
          local exists = true
          if type(adapter.find) == "function" then
            local e2, r2 = pcall(function() return adapter:find(n.id) end)
            if e2 then exists = (r2 ~= nil) end
          end
          -- ★★★★★ 2026-10-05 **"控件不在"时连 `set_property` 都不用发**。
          --
          --   理由（可证）：适配层 `set_property` 的第一步也是 `self:find(id)`，
          --   拿到 nil 就直接 `return false`（既不写、也不抛）—— 和上面这次探测
          --   **是同一个调用、同一个结果**（中间没有任何东西改控件树）。
          --   少发一次 = 少一遍**深度优先搜控件树**（真机上每个节点一次 pcall + 读 name）。
          --   实测（`tests/grid_cost.lua`，两个同名 `action.back` 规划节点 + 深树）：
          --   一次 render 从 20 次搜空（9360 次 `GetChildren`）降到 10 次（约 4700 次）。
          local ok = exists and self:_set_prop(adapter, n.id, k, v, nkey)
          if ok and exists then
            last[k] = v
            retry_clear(n.id, k)
          elseif not exists then
            -- ★★★★★ 2026-10-05 **控件根本不在本关 ⇒ 立即记账、绝不补发**。
            --
            --   真机实测（v066，用户报"进试玩加载慢了 10 倍不止、后续选关明显卡顿"）：
            --     属性补发 10 次仍未送达，已停止补发：`select.pos_runtime` / `select.visible` /
            --       `select.parent` / `select.kind` / `select.__rect`（控件一直没找到（find 返回 nil））
            --   ⇒ 规划里那 ~105 个"本关还没建"的控件，**每个属性都白补发了 10 次** ✗
            --     每次还要在深树里按名字搜一遍（adapter:find）⇒ 5000+ 次无效调用
            --     ⇒ 加载慢十倍 + 切屏卡顿。这是**我们的补发逻辑自己造成的**，必须掐掉。
            --   ⇒ 两种失败必须分开：
            --       · `exists == false`（控件不在）⇒ **记账、不补发** ✓（本行）
            --       · `exists == true` 但 `ok == false`（控件在，子控件没就绪/句柄失效）
            --         ⇒ 才补发 ✓（下面那支）—— 这才是"第一次进关画得少"要治的
            last[k] = v
          else
            -- 两种失败要**分开报**（下一份真机日志就靠这句区分假设）：
            --   · `exists == false` ⇒ 控件这次根本不在树上（首帧没就绪 / 本关没建）；
            --   · `exists == true` 但 `ok == false` ⇒ 控件在，是**里面那一步**没成
            --     （按钮的 label 子控件没就绪 / 墙门的 wall.* 子控件取不到）。
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            -- ★ 2026-10-05：**把 `exists` 传下去** ✗✓ —— `retry_more` 据此选额度：
            --   · `exists == false` ⇒ 控件不在 ⇒ 老规矩 3 次认输 ✓（性能红线 ✗ 不放宽）
            --   · `exists == true`  ⇒ 控件在、只是子控件没就绪 ✗ ⇒ **给它 2.5 秒等** ✓
            --     ★ 这正是"第一次进关（格子本次新建）画得少、之后再进正常"的治法 ✓
            if retry_more(n.id, k, why, exists) == false then
              last[k] = v          -- 认输：记账，免得每帧再看见它
            end
          end
        end
      end
    end
    local lr = last.__rect
    if force or not lr or lr.x ~= n.rect.x or lr.y ~= n.rect.y or lr.w ~= n.rect.w or lr.h ~= n.rect.h then
      -- ★★★ 2026-09-30：**「这个控件的位置由脚本说了算」**。
      --
      --   背景：适配器有 `respect_editor_rect`（**编辑器几何优先**）—— 只要是存档里
      --   已有的控件，脚本就不碰它的位置（这样你在编辑器里调的位置不会被覆盖）。
      --   例外只有"运行时实例化"的控件（`self.instantiated[id]`）。
      --
      --   而**房间名标签**（`room.label.*`）需要在运行时按每个房间的外框摆 ——
      --   它是存档里的控件（`sync_plan` 建进去的），但**位置必须每帧由脚本算**。
      --   原来的下场：三个标签全被按在存档里那一份几何上，**中心完全重叠**（都是 503,738），
      --   真机上就是三个字叠在一起。
      --
      --   ⚠️⚠️ 用 `runtime_rect`（**只跳过位置检查**），**不要**用 `adapter.instantiated`！
      --   我第一版复用了 `instantiated` —— 那个标记还管着"允不允许销毁控件"，
      --   于是房间标签/选卡色块在某次渲染里短暂不可见时被**真销毁**，再也回不来
      --   （表现为"测试里可见色块 0 块，单独探针却看到 3 块"）。
      if n.pos_runtime then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      end
      -- ★ 位置也一样：**写成功才记账**（和上面那段属性同一个道理）。
      --   ⚠️ `respect_editor_rect` 打开时适配层会**故意跳过**位置 —— 那属于"故意的空操作"，
      --      它返回 true ⇒ 不会变成每帧重发。
      --
      -- ★★★★★ 2026-10-05 **这里是 v067 漏掉的第二半**（真机实测：v067 之后仍然"没回归原速"）。
      --   日志只剩这一种补发：
      --     属性补发 10 次仍未送达，已停止补发：`select.__rect` /
      --       `obj.carpet.__rect` / `obj.shelf.__rect` / `obj.desk.__rect` / `obj.case.__rect`
      --   ⇒ 那 ~105 个"本关还没建"的控件，**每帧**都要重跑一次 `find`（深树按名搜）+ 写入 ✗
      --     ⇒ 持续卡顿、选关卡顿 —— 和逐属性那条是同一个病，只是走的是另一个分支。
      --   ⇒ 同样按 `exists` 分开：控件不在本关 ⇒ **立即记账、不补发** ✓
      local rect_exists = true
      if type(adapter.find) == "function" then
        local e3, r3 = pcall(function() return adapter:find(n.id) end)
        if e3 then rect_exists = (r3 ~= nil) end
      end
      -- ★ 与逐属性那条同一个道理（见上面那段注释）：控件不在 ⇒ 连 `set_property`
      --   都不发（它第一步也是 `find`，结果必然一样是 nil）。
      local rok = rect_exists and self:_set_prop(adapter, n.id, "rect", n.rect, nkey)
      if rok then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
        retry_clear(n.id, "__rect")
      elseif not rect_exists then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
      elseif retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
      end
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      if stale_legacy(id) then
        -- ★ 切换帧：这个 id 是上一帧按老路径建的，而这一帧网格视窗已经接管。
        --   **只清账本、不销毁** —— 那个名字现在归网格视窗的列表项所有，
        --   `destroy_control` 会按名字反查并把控件 `SetVisible(false)`（甚至在
        --   `instantiated` 名单里时**真销毁**）⇒ 等于把网格里的线索卡关掉/毁掉。
        self._created[id] = nil
        drop_props_of(id)
      else
        pcall(function() adapter:destroy_control(id) end)
        self._created[id] = nil
        drop_props_of(id)
      end
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    -- ⚠️ 动效也走 pcall + 跳过老线索目标：`play_effect` 第一步同样是 `find(id)`，
    --    命中已回收的列表项时后面的 `read_pose`/`Tween` 都会在**渲染途中**抛错。
    if not stale_legacy(e.target) then
      pcall(function() adapter:play_effect(e.target, e.kind, e) end)
    end
  end
  self.effects = {}
  self.dirty = false
end

return M

end

__M["engine_adapter"] = function()
--[[----------------------------------------------------------------------------
  engine_adapter.lua —— 引擎适配层（接口 + 离线桩实现）

  这是整个工程唯一的「引擎边界」。上层（ui_controller / murdoku_core）不认识千星，
  下层（engine_adapter_qianxing.lua）才认识千星。7.1 的脚本 API 若与预期不同，
  只需要改 engine_adapter_qianxing.lua 一个文件。

  接口清单（适配层必须实现）
  ⚠️ 以下**全部是方法**：调用方必须用冒号语法 `adapter:method(...)`。
     用点号 `adapter.method(...)` 会把第一个实参当成 self —— 这个坑已经踩过一次
     （render 崩在 create_control：node 变成 nil）。
    log(msg)
    create_control(node)                 -- 按 node.id 幂等创建/复用控件
    destroy_control(id)
    set_property(id, key, value)         -- key: rect/text/image/style/visible/enabled/...
    play_effect(id, effect_name, params) -- 动画/特效，不支持可以空实现
    bind_input(id, event_table)          -- 声明该控件的点击回传事件
    now() -> seconds
    after(seconds, fn) -> handle         -- 定时器（补间/动画序列/计时用）
    cancel(handle)
    save(key, value) / load(key)         -- 局内存档
    signal_emit(name, payload)           -- 向节点图/服务器发信号
    signal_on(name, handler)             -- 收外部信号
    random_int(a, b)
----------------------------------------------------------------------------]]--

local M = {}
M.interface = {
  "log", "create_control", "destroy_control", "set_property", "play_effect",
  "bind_input", "now", "after", "cancel", "save", "load",
  "signal_emit", "signal_on", "random_int",
}

----------------------------------------------------------------------------
-- 离线桩：纯 Lua，可脱离游戏跑通整个操作框架
-- 用法：
--   local stub = __require("engine_adapter").new_stub()
--   -- 桩会把 create_control/set_property 记录到 stub.log_lines，便于自检
----------------------------------------------------------------------------

local Stub = {}
Stub.__index = Stub

function M.new_stub(opts)
  opts = opts or {}
  local self = setmetatable({}, Stub)
  self.log_lines = {}
  self.controls = {}     -- id -> node
  self.props = {}        -- id -> {key=value}
  self.effects = {}
  self.input_handlers = {}  -- id -> event table
  self.timers = {}
  self.storage = {}
  self.signals = {}
  self.verbose = opts.verbose == true
  self.clock = 0
  return self
end

function Stub:log(msg)
  self.log_lines[#self.log_lines + 1] = tostring(msg)
  if self.verbose then print("[adapter] " .. tostring(msg)) end
  -- 最多留 2000 行，避免长时间运行爆内存
  if #self.log_lines > 2000 then table.remove(self.log_lines, 1) end
end

function Stub:create_control(node)
  local existed = self.controls[node.id]
  self.controls[node.id] = node
  if existed and existed ~= false then return end
  self.props[node.id] = self.props[node.id] or {}
  if node.event then self:bind_input(node.id, node.event) end
  self:log("create " .. node.id .. " (" .. tostring(node.kind) .. ")")
end

function Stub:destroy_control(id)
  self.controls[id] = false
  self.props[id] = nil
  self.input_handlers[id] = nil
  self:log("destroy " .. tostring(id))
end

function Stub:set_property(id, key, value)
  self.props[id] = self.props[id] or {}
  self.props[id][key] = value
end

function Stub:play_effect(id, effect_name, params)
  self.effects[#self.effects + 1] = { id = id, kind = effect_name, params = params }
  self:log(string.format("fx %s <- %s", tostring(effect_name), tostring(id)))
end

function Stub:bind_input(id, event_table)
  self.input_handlers[id] = event_table
  self:log("bind " .. tostring(id) .. " -> " .. tostring(event_table and event_table.action))
end

function Stub:now() return self.clock end

function Stub:after(seconds, fn)
  local h = { at = self.clock + (seconds or 0), fn = fn }
  self.timers[#self.timers + 1] = h
  return h
end

function Stub:cancel(handle)
  for i = 1, #self.timers do
    if self.timers[i] == handle then table.remove(self.timers, i) return true end
  end
  return false
end

-- 桩的“时间推进”，自检时手动调用
function Stub:advance(seconds)
  self.clock = self.clock + (seconds or 0)
  local due = {}
  for i = #self.timers, 1, -1 do
    if self.timers[i].at <= self.clock then
      due[#due + 1] = self.timers[i]
      table.remove(self.timers, i)
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
end

function Stub:save(key, value) self.storage[key] = value return true end
function Stub:load(key) return self.storage[key] end

function Stub:signal_emit(name, payload)
  self:log(string.format("signal_emit %s %s", tostring(name), tostring(payload)))
  local list = self.signals[name]
  if list then
    for i = 1, #list do list[i](payload) end
  end
end

function Stub:signal_on(name, handler)
  self.signals[name] = self.signals[name] or {}
  table.insert(self.signals[name], handler)
end

function Stub:random_int(a, b)
  a, b = a or 1, b or 1
  if b < a then a, b = b, a end
  return a + math.random(0, b - a)
end

-- 自检辅助：模拟点击某个控件
function Stub:click(id)
  local evt = self.input_handlers[id]
  if not evt then
    self:log("click " .. tostring(id) .. " (没有绑定事件)")
    return nil
  end
  return evt
end

return M

end

__M["engine_adapter_qianxing"] = function()
--[[----------------------------------------------------------------------------
  engine_adapter_qianxing.lua —— 千星奇域 7.1 客户端脚本绑定层（按官方 API 实现）

  依据：官方《客户端控件API文档》 mhtakr07vej4 与《客户端控件和客户端脚本》 mhbgxf0nynww
        速查见 docs/7.1-脚本API速查.md

  交互约定（重要）：官方**只有** CursorDown/Up/Click/Drag，**没有长按事件**。
  本工程因此不用长按，改为「**单击 = 铅笔笔记 / 双击 = 放置**」：
    · 适配层只负责把 CursorClick 转成 {action="click"} 事件
    · 双击判定与"待定单击延后落地"由 ui_controller 用累加时钟处理
  这样也省掉了自造长按阈值带来的手感问题。

  与官方 API 的对应关系（全部是文档里存在的接口，没有猜的名字）：
    控件查找   game.GetClientUIRoots() + ctrl:GetChildren()/GetChild(name)
    动态创建   game.InstantiateClientUIControl(prefabIndex, parent)
    销毁       game.DestroyClientUIControl(ctrl)
    文本       textBox.text = "..."
    图片       img:SetImage(img.imageSource, imageId)   -- 沿用编辑器里配的来源
    显隐       ctrl:SetVisible(bool) / SetActive(bool)
    可用       button.interactable = bool
    点击       button:AddCursorEventListener(Enum.CursorEventType.CursorClick, cb)
    动画       game.Tween(ctrl, {localScaleX=…, localScaleY=…}, 时长):Play()
    发信号     game.ServerSignal(name) → AddInt/AddString/AddBool → SendSignal()
    收信号     script:RegisterServerSignalHandler(name, cb)
    计时       OnUpdate(dt) 自行累加（沙箱没有 os 库）
    音效       game.PlayAudio2D(id)      本地化  game.GetText(textMapId)

  控件命名约定（编辑器里照这个命名，脚本按名字找）：
    root / topbar / left / tray / clues / legend / board / actions / right / modal / intro
    cell.<行>.<列>   及可选子控件：face / note / x / wall.up|down|left|right / door.up|down|left|right
    tray.<角色id>    clue.<序号>    action.* / tool.* / action.q.*
    hud.title / hud.subtitle / hud.timer / hud.violations / hud.toast / hud.share
--]]--

local M = {}

M.VERSION = "1.0.0"

-- 框架约定的信号名（节点图侧按同名接线）
M.SIGNALS = {
  READY      = "murdoku/ready",
  PLACE      = "murdoku/place",
  CLEAR      = "murdoku/clear",
  SUBMIT     = "murdoku/submit",
  ACCUSE     = "murdoku/accuse",
  SOLVED     = "murdoku/solved",
  SAVE       = "murdoku/save",
  RESTORE    = "murdoku/restore",
  SYNC_STATE = "murdoku/sync",
  -- ★★★★★ 2026-10-09 **补 `SETTLE`（「存档并结算」）** ✗✓
  --   ★ 为什么必须有 ✓：`main.lua:218` 的 `on_settle` 调
  --     `adapter:signal_emit(Qianxing.SIGNALS.SETTLE, { tostring(level.id) })` ✓
  --   ★ 之前没有这一条会怎样 ✗：`SIGNALS.SETTLE` 求值为 **nil** ⇒
  --     `signal_emit(nil, …)` ⇒ ★ 被 `pcall` 吞掉 ⇒ **一个错都不报** ✗
  --     ⇒ ★ 玩家点「存档并结算」时：**本地存档照做、结算信号永远发不出去** ✓
  --     —— ★ 正是本项目最常见的那种「静默失效」✓（不报错、只是不生效 ✓）
  --   ★ 出处 ✓：`docs/弹窗-线索汇总.md` §7 第 1 步列的 5 块补丁里，
  --     其余 4 块（入口分支 / 三动作 / 渲染分支 / DECOR）都已恢复，
  --     **只有"适配器 SIGNALS"这一块漏了** ✓ ⇒ 本次补上 ✓
  --   ⚠️ 节点图侧要按这个名字接线；该信号名**此前在任何文档里都查不到** ✓
  --     ⇒ 已同步写进 `docs/节点图接线与素材清单.md` ✓
  SETTLE     = "murdoku/settle",
}

-- 信号参数按顺序添加；这里给出"信号名 → 字段顺序"，收信号时按它还原成字典
M.SIGNAL_SCHEMA = {
  [M.SIGNALS.READY]      = { "level_id", "rows", "cols", "piece_count" },
  [M.SIGNALS.PLACE]      = { "who", "r", "c" },
  [M.SIGNALS.CLEAR]      = { "who" },
  [M.SIGNALS.SUBMIT]     = { "ok" },
  [M.SIGNALS.ACCUSE]     = { "thief", "has_accomplice", "correct" },
  [M.SIGNALS.SOLVED]     = { "level_id", "elapsed", "moves", "failed_accusations" },
  [M.SIGNALS.SAVE]       = { "level_id", "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.RESTORE]    = { "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.SYNC_STATE] = { "who", "r", "c" },
  -- ★ 2026-10-09 随 `M.SIGNALS.SETTLE` 一起补 ✓ 参数按序 = 关卡 id（`main.lua:218` 只传这一个 ✓）
  [M.SIGNALS.SETTLE]     = { "level_id" },
}

----------------------------------------------------------------------------
-- 官方枚举的安全取值（缺失时返回 nil，调用点全部降级而不是崩）
----------------------------------------------------------------------------

local function E(path, default)
  local cur = Enum
  if cur == nil then return default end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return default end
  end
  if cur == nil then return default end
  return cur
end

----------------------------------------------------------------------------
-- 适配器
----------------------------------------------------------------------------

local Adapter = {}
Adapter.__index = Adapter
M.Adapter = Adapter

function M.new(cfg)
  cfg = cfg or {}
  -- ★★ 防呆：把 `cfg.cells.<调试开关>` 上提到顶层。
  --
  -- 2026-09-27 踩过：`debug_key` / `debug_image` 被加进了 `cfg.cells = {…}` 里
  -- （挨着本来就属于 cells 的 `debug_signal`），而读取处写的是 `self.cfg.debug_key`
  -- → 永远 nil → **诊断一行都不打，白白多跑了一轮真机**。
  -- 这类"开关加了但没生效"的错最难查（日志里什么都没有，看着像功能没触发）。
  -- 所以这里统一兜一层：cells 里有、顶层没有的就上提；再把生效值打出来。
  if type(cfg.cells) == "table" then
    for _, k in ipairs({ "debug_key", "debug_image", "debug_event" }) do
      if cfg[k] == nil and cfg.cells[k] ~= nil then cfg[k] = cfg.cells[k] end
    end
  end
  local self = setmetatable({}, Adapter)
  self.cfg = cfg
  if print then
    -- ⚠️ 这里必须用字面量：`PREFIX` 是在**本函数之后**才 `local` 的，
    --    在这里引用它拿到的是全局 nil，`nil .. str` 会抛错。
    print("[murdoku] 调试开关：debug_key=" .. tostring(cfg.debug_key)
      .. " debug_image=" .. tostring(cfg.debug_image)
      .. " debug_event=" .. tostring(cfg.debug_event)
      .. " debug_click=" .. tostring(cfg.debug_click)
      .. "（nil = 关；debug_event/debug_click 为 nil 时按「开」处理）")
  end
  self.signals = M.SIGNALS
  if cfg.signals then
    for k, v in pairs(cfg.signals) do self.signals[k] = v end
  end
  self.controls = {}       -- 节点 id -> 引擎控件（**只记命中**，见 find）
  -- ★★★★★ 2026-10-05 **未命中也要记**（负缓存）—— 见 `Adapter:find` 上面那段大注释。
  --   实测（`tests/grid_cost.lua`）：不记未命中时，**本关根本没有的名字**每帧都要重走一遍
  --   深树 ⇒ 300 帧里 `action.back` 白跑 3000 次（每次约 470 个 `GetChildren`）。
  --   这里只放"这一代确实不在树上"的名字；任何"树变了"的事件都会整代作废
  --   （`Adapter:invalidate_lookups`）。
  self._misses = nil       -- name -> 过期时间戳（self.clock）｜ false = 本代内不再重搜
  self._lookup_hits = 0    -- 累计"真的搜到过东西"的次数（= 树已经有控件了；见 find 里的启动期规则）
  self._lookup_gen = 0     -- 第几代（只用于日志/诊断）
  -- ★★★ `enforce_hidden_subtrees` 的开关：**事件驱动**，不再每帧跑。
  --   第一帧必须跑一次（那时树刚就绪，模板子控件可能还没实例化出来）。
  self._subtree_dirty = true
  -- ★★★★★ 2026-10-05 `enable_raycast` 的**收敛/放弃**账（第 (3) 条每帧成本）。
  --   见 `Adapter:enable_raycast` 上面那段注释：它原来每 20 帧无条件整树 walk 一遍，
  --   实测 300 帧 = 15 趟 = 7020 次 `GetChildren`（23.4/帧），而这件事是**幂等**的。
  self._ray = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
  self.handlers = {}       -- 控件 id -> **规划节点**（只做 parent/rect 反查；一个 id = 一个引擎控件）
  -- ★★★★★ 2026-10-05 **事件表按「规划节点」记，不按控件 id。**
  --
  --   为什么（可复现，`tests/_wip/probe_event_table.lua`）：
  --     `build_layout` 里**同一个 id 会出现在两个节点上**（最典型：`action.back` ——
  --     一个挂 `topbar`（「返回菜单」/ `back_confirm`）、一个挂 `right`（「返回列表」/ `back`），
  --     见 ui_controller 的 L1759 与 L2411）。
  --     而事件表原来是 `self.handlers[id]`、`set_property` 的 event 分支直接
  --     `h.event = value` ⇒ **一份表、两个节点轮流写** ⇒ 后写的把先写的吃掉：
  --     实测两个节点都发过（`back_confirm` → `back`），表里最后只剩 `back`，
  --     `topbar` 那一份**静默丢失**（不报错、看不出来）✗
  --   ⇒ 键改用**规划节点**（`id \1 父容器 \1 同(id,父容器)的第几次出现`）——
  --     这就是 `ui_controller` 属性账本**已经在用的同一把 `node_key`**（见那里的
  --     `local function node_key(n)`），由渲染循环算好后传进来，**不在这里另造一套**。
  --     「一条规则两个权威」是本项目刚在 BOM 上栽过的坑。
  --   ⚠️ `self.handlers`（按 id 的节点登记表）**保持不变**：`rect` 分支要用
  --      `handlers[pid]` 反查**父控件**（`pid` 是控件 id，不是规划节点键），
  --      那里本来就该按 id —— 一个 id 只有一个引擎控件。
  self.events = {}         -- 规划节点键 -> 事件表
  -- ★★★★★ 2026-10-05 **B2（用户拍板 ✓）：派发改用「认领者」** ——
  --   控件 id -> **第一个**为这个 id 写 event 的规划节点键（= 这颗控件的语义归属者）。
  --
  --   为什么不是"最后写的那个赢"（三条硬证据，全部在同一份源码里，可现场核对 ✓）：
  --     · `ui_controller.lua:1389` 左上那颗 ↰ 图标按钮（`hex.back`）声明的是 `back_confirm`
  --       ⇒ 点它 **先弹 ✓/✗**（`ui_controller.lua:854`：`a == "back_confirm"` ⇒
  --       `self.pending = { action = "back" }` ⇒ 进确认状态机）。
  --     · `ui_controller.lua:1761` **topbar** 节点声明的同样是 `back_confirm`（「返回菜单」↰）。
  --     · `ui_controller.lua:2412` **right** 节点声明的是 `back`（「返回列表」，`tab` 样式）。
  --   ⇒ 现状**自相矛盾** ✗：左上那颗 ↰ 图标（`hex.back`）**先弹 ✓/✗**，
  --     而这颗 `action.back` 按钮却**直接跳列表**（因为派发取的是"最后写的"= `right` 的 `back`）
  --     ⇒ **同 id 的两颗按钮两种语义**，差别只取决于你点的是哪一颗。
  --     ⚠️ 别把键盘那条混进来：`KB_ACTIONS` 里 Key42 → `"back"`，走的是
  --        `close_modal` / `level_list`（`ui_controller.lua:766-771`），**不是** `back_confirm`。
  --   ⇒ B2：派发给**认领这颗控件的那个节点**（先写的那个 = `topbar`）⇒ **点击与 ↰ 一致**（都先弹 ✓/✗）。
  --
  --   ⚠️ 规则：**只认第一次**（见 `set_property` 的 `key == "event"` 分支里那行 `== nil` 判断）
  --      ⇒ 后续任何节点再写都不换人 ⇒ 派发**稳定、可预测**，不受"这一帧谁后渲染"影响。
  --   ⚠️ `forget_events_of(id)` 必须**连它一起清**：控件销毁重建后，新控件要能重新认领
  --      （否则会认领到那个**已经不存在**的旧规划节点 ⇒ 派发读到 nil）。
  self.event_claim = {}
  -- ⚠️⚠️ `event_latest` **保留，但已不是派发依据**（**纯诊断记录** ✓）：
  --   id -> **最近一次**写 event 的节点键。留着它是为了排查"这颗控件上谁后写过事件"
  --   （例如回答"属性/文字实际是哪个节点的"—— `right` 与 `topbar` 写的是**同一个控件**）。
  --   ★ **任何人都不许再拿它做派发** ✗ —— 那正是 B2 要修掉的行为（"最后写的赢"）。
  self.event_latest = {}
  self.subs = {}           -- "id.child" -> 子控件（或 false）
  self.timers = {}
  self.clock = 0
  self.state = {}          -- 脚本内本地状态（跨场景要靠信号+服务器）
  self.warned = {}
  self.on_input = nil
  self.apply_rect = cfg.apply_rect == true   -- 默认不动位置（布局在编辑器里定）
  return self
end

----------------------------------------------------------------------------
-- 日志
----------------------------------------------------------------------------

local PREFIX = "[murdoku] "

function Adapter:log(msg)
  if print then print(PREFIX .. tostring(msg)) end
end

function Adapter:err(msg)
  if printerr then printerr(PREFIX .. tostring(msg)) end
end

function Adapter:warn_once(key, msg)
  if self.warned[key] then return end
  self.warned[key] = true
  self:err(msg)
end

-- ════════════════════════════════════════════════════════════════════════
-- 「控件未找到」—— 收集 + **分组汇总**，不再逐个刷屏
--
-- 为什么改：真机首次开局会缺 80+ 个控件（界面还没搭完），原来每个控件打一行，
-- 结果 80 多行把真正有用的信息（**缺的是哪几类**）淹没了，而且每行都是同一句话。
-- 2026-09-26 12:20 的真机日志就是这么一大坨。
--
-- 现在：缺谁只记账，等第一次渲染完由 `report_missing()` 打一次分组汇总，例如
--   [murdoku] 这些控件还没建（共 86 个，按类分组）：
--   [murdoku]   cell.*       ×24   cell.1.2 / cell.1.3 …
--   [murdoku]   clue.N       ×7    clue.1 / clue.2 …
-- 完整名单与坐标在 docs/控件坐标表-1600x900.md，日志里不必重复 150 行。
-- ════════════════════════════════════════════════════════════════════════

function Adapter:_note_missing(id)
  if id == nil then return end
  self.missing = self.missing or {}
  if self.missing[id] == nil then
    self.missing[id] = true
    self.missing_count = (self.missing_count or 0) + 1
  end
end

-- 把一个控件 id 归到"类"：cell.1.2 → cell.* ／ clue.7 → clue.N ／ hud.title → hud.*
local function missing_group(id)
  local s = tostring(id)
  if s:match("^cell%.[%d]+%.[%d]+$")  then return "cell.*"  end
  if s:match("^clue%.[%d]+$")         then return "clue.N"  end
  if s:match("^tray%.[%w_]+$")        then return "tray.*"  end
  if s:match("^ruler%.[cr]%.[%d]+$")  then return "ruler.*" end
  if s:match("^modal%.")              then return "modal.*" end
  if s:match("^intro%.")              then return "intro.*" end
  if s:match("^action%.")             then return "action.*"
  end
  local head = s:match("^([%w_]+)%.")
  if head ~= nil then return head .. ".*" end
  return s
end

-- 打一次分组汇总。`force=true` 可以再打一次（清单有变化时用）。
function Adapter:report_missing(force)
  if self.missing == nil then return 0 end
  if self.missing_reported and not force then return 0 end
  self.missing_reported = true

  local groups, order = {}, {}
  for id in pairs(self.missing) do
    local g = missing_group(id)
    if groups[g] == nil then
      groups[g] = { n = 0, sample = {} }
      order[#order + 1] = g
    end
    groups[g].n = groups[g].n + 1
    if #groups[g].sample < 3 then groups[g].sample[#groups[g].sample + 1] = id end
  end
  table.sort(order, function(a, b)
    if groups[a].n ~= groups[b].n then return groups[a].n > groups[b].n end
    return a < b
  end)

  if printerr then
    printerr("[murdoku] 这些控件还没建（共 " .. tostring(self.missing_count or 0)
      .. " 个，按类分组）：")
    for i = 1, #order do
      local g = order[i]
      local gd = groups[g]
      local samp = table.concat(gd.sample, " ")
      if gd.n > #gd.sample then samp = samp .. " …" end
      printerr("[murdoku]   " .. g .. "  ×" .. gd.n .. "   " .. samp)
    end
    printerr("[murdoku] 完整 150 个控件的名字/坐标/父子关系：docs/控件坐标表-1600x900.md")
  end
  return self.missing_count or 0
end

----------------------------------------------------------------------------
-- 控件查找（只用文档里的接口）
----------------------------------------------------------------------------

local function find_in(ctrl, name, depth)
  if ctrl == nil or depth > 16 then return nil end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname == name then return ctrl end
  -- ⚠️ GetChildren 一定要包 pcall：真机上万一某个节点不提供这个方法，
  --    不包的话 find 会整个抛错，被上层 pcall 吞掉后表现成"控件未找到" ——
  --    那种误判极难查（明明建了却说找不到）。
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do
      local hit = find_in(children[i], name, depth + 1)
      if hit then return hit end
    end
  end
  return nil
end

-- 收集"名字差一点"的候选。
-- 用途：真机上最常见的失败是名字不完全一致（多一个 `(1)` 后缀、大小写不同、
-- 前后有空格）。光说"找不到"没用，把这个名字的近似者列出来就一目了然了。
local function collect_names_in(ctrl, depth, out, limit)
  if ctrl == nil or depth > 16 or #out >= limit then return end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and type(cname) == "string" and cname ~= "" then out[#out + 1] = cname end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do collect_names_in(children[i], depth + 1, out, limit) end
  end
end

local function norm_name(s)
  s = tostring(s or ""):lower()
  s = s:gsub("%s+", "")
  return s
end

-- 返回与 name "近似"的现有控件名（去掉空格/大小写后相等，或互为子串）
function Adapter:near_names(name, limit)
  limit = limit or 8
  local out = {}
  if game == nil or game.GetClientUIRoots == nil then return out end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then return out end
  local all = {}
  for i = 1, #roots do collect_names_in(roots[i], 0, all, 2000) end
  local want = norm_name(name)
  if want == "" then return out end
  for i = 1, #all do
    local have = norm_name(all[i])
    if have == want or have:find(want, 1, true) or want:find(have, 1, true) then
      out[#out + 1] = all[i]
      if #out >= limit then break end
    end
  end
  return out
end

-- 兜底一：按"结构路径"找控件（当编辑器里改不了控件名称时用）
--   路径写法：从 UI 根算起的一串 1-based 子节点序号，例如 "1/2/3"
--             = 第 1 个根 → 它的第 2 个子控件 → 再它的第 3 个子控件
local function control_by_path(roots, path)
  local idx = {}
  for seg in tostring(path):gmatch("%d+") do idx[#idx + 1] = tonumber(seg) end
  if #idx == 0 then return nil end
  local cur = roots[idx[1]]
  for i = 2, #idx do
    if cur == nil then return nil end
    local kids = cur:GetChildren()
    if kids == nil then return nil end
    cur = kids[idx[i]]
  end
  return cur
end

-- ════════════════════════════════════════════════════════════════════════
-- ★★★★★ 2026-10-05 **控件名缓存的两半**：命中缓存（`self.controls`）+ **未命中缓存**（`self._misses`）
--
--   为什么要加"未命中"这一半（不是猜的，是量出来的）：
--     `tests/grid_cost.lua` 在**关卡里 300 帧**（dt=1/60，网格视窗在跑）测到：
--       · `GetChildren` 被访问 **1,565,043** 次 ≈ **5217/帧**
--       · 其中 `action.back` 一个名字就占 **280,800** 次 = **936/帧**（搜空×10/帧）
--       · 另外 9 个"本关根本没建"的容器名（board/left/right/topbar/tray/actions/
--         intro/modal/select）各 468 次/帧 —— 全是**每帧重走一遍深树**换来的同一个 nil
--     ⇒ 一次搜空的代价 = 把整棵控件树（真机约 150 个控件）走完，而结果**永远是 nil**，
--       下一帧还会一模一样地再走一遍。这正是用户说的"对比之前还是略有卡顿"里
--       占比最大的那一项（`tests/grid_cost.lua` 的 [E] 口径）。
--
--   为什么以前不敢缓存未命中：`main.lua` / `entry_client_script.lua` 里写着
--     「`find` 未命中会**永久缓存 false** ⇒ 万一此刻树还没就绪，就把后面那条路也一起弄死」
--     —— 那是**真的**（旧实现把 false 写进 `self.controls`）。所以这里三条规矩缺一不可：
--       ① **命中缓存优先**：任何 `self.controls[name] = ctrl`（新建/改名/找回）都天然
--          让这个名字的负缓存失效 —— 不需要调用方记得去清。
--       ② **树还没"见过活控件"就一律不记负缓存**：`self._lookup_hits == 0` 时
--          （OnInit/OnStart 阶段树是空的，这是真机日志里写明的正常现象）
--          未命中**照旧每帧重搜** —— 启动期那条"等控件就绪再开局"的重试一个字都不变。
--          代价为零：树是空的时候，搜空本来就几乎不花时间。
--       ③ **未命中会自己过期一次**：第一次记下 `clock + ttl`，过了这一刻若还没出现，
--          再真搜一次；还是不在 ⇒ 记成 `false`（本代内不再重搜，直到事件作废）。
--          ⇒ 即使"树是分两批加载的"这种没被我们观测到的情况发生了，
--            最多晚 `ttl`（默认 1 秒）也能自己恢复，**不可能永久卡死**。
--   ③ 的账：每个缺失名字每代最多多走 **1** 遍树（≈470 个节点），
--          对比现在**每帧** 5217 个节点 —— 三个数量级的差别。
--
--   什么时候整代作废：`Adapter:invalidate_lookups(why)` —— 切屏 / 换关 / 新建或销毁控件 /
--     网格视窗 RefreshItems（引擎那时才实例化列表项）。和第 2 项改造
--     （`enforce_hidden_subtrees`）共用**同一批事件**，一处定义、处处触发。
-- ════════════════════════════════════════════════════════════════════════

-- 把"这一代的名字缓存"整代扔掉（含负缓存），并让兜底隐藏重跑一次。
-- 触发时机全都是**控件树真的变了**的事件，不是每帧。
function Adapter:invalidate_lookups(why)
  self._misses = nil
  -- ★★★★★ 2026-10-08 **命中缓存也要一起清** ✗✓（★ 成员第 4 轮 H8：陈旧句柄 ✓ 机制已逐行核对 ✓）
  --   ★ 依据（官方）✓：★「玩家传送、断线重连时，**所有客户端控件都会被销毁**然后回到初始状态」✓
  --     ★「客户端容器控件**隐藏或销毁**时，客户端控件**销毁**」✓
  --   ★ 而旧实现只清 `_misses` ✗ ⇒ ★ **`find` 命中缓存后从不校验句柄是否还活着** ✗
  --     ⇒ ★ 一旦控件被销毁重建 ⇒ ★ 缓存的 `root` 成了**陈旧句柄** ⇒ ★ `GetChild("assets")`=nil ✗
  --       ★ **`GetChildren()`=空** ✗ —— ★ **两个症状一次解释** ✓✓（★ 且编辑器侧无需任何异常 ✓）
  --   ★ 所以 ✓：★ **作废时连命中缓存一起清** ✓ ⇒ ★ 下次 `find` 会真的重新深搜 ✓
  self.controls = {}
  self._subtree_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1
  if self.cfg and self.cfg.debug_lookup and print then
    print(PREFIX .. "控件名缓存作废（第 " .. tostring(self._lookup_gen) .. " 代）："
      .. tostring(why))
  end
end

-- 只扔一个名字的两半缓存（改名/换绑这种"一个控件换了身份"的场合）
function Adapter:drop_lookup(name)
  if name == nil then return end
  self.controls[name] = nil
  if self._misses ~= nil then self._misses[name] = nil end
end

function Adapter:find(name)
  local hit0 = self.controls[name]
  if hit0 ~= nil then return hit0 end
  -- ★ 负缓存命中：这一代里已经确认"不在树上" ⇒ 直接返回 nil，**不再走深树**。
  local miss = self._misses
  if miss ~= nil then
    local stamp = miss[name]
    if stamp ~= nil then
      -- `false` = 已经重搜过一次还是不在（本代内不再重搜）；
      -- 数字 = 过期时刻，没到点就认账。
      if stamp == false or self.clock < stamp then return nil end
    end
  end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    -- 主路径：按「控件名称」深度优先搜索
    for i = 1, #roots do
      local hit = find_in(roots[i], name, 0)
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    end
    -- 兜底：cfg.path_map[name] = "1/2/3"
    local pm = self.cfg.path_map
    local path = pm and pm[name]
    if path then
      local hit = control_by_path(roots, path)
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    end
  end
  -- ★ 搜空 ⇒ 记进负缓存（规矩 ②：树还没"见过活控件"时一律不记 —— 启动期的重试不能被打断）
  if self._lookup_hits > 0 then
    if self._misses == nil then self._misses = {} end
    local ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil then
      self._misses[name] = self.clock + ttl     -- 第一次：给一次"过一会儿再看"的机会
    elseif old ~= false and self.clock >= old then
      self._misses[name] = false                -- 已经重搜过还是不在 ⇒ 本代内不再重搜
    end
  end
  return nil
end

-- 搜到东西之后的两件小事（都很便宜，别省）：
--   ① 记下"树里已经有控件了" ⇒ 从这一刻起未命中才允许进负缓存（见 find 的规矩 ②）。
--   ② **安全网**：如果这个名字在"应当被隐藏"的名单里 ⇒ 它刚刚才进树
--      ⇒ 兜底隐藏必须重跑一次（原来靠每帧扫一遍才发现，现在靠这一下）。
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty = true
  end
end

-- 子控件（cell.1.1 下的 face / note / x / door.up ...）
--
-- ★ 2026-09-25 修正：**只缓存命中，绝不缓存未命中**。
--   旧实现在查不到时写 self.subs[key] = false，于是"UI 就绪前查过一次"就会
--   让这个子控件**永远取不到** —— 直接导致 image / notes / x_mark 这些表现层
--   静默失效（我们为此排查了一整天）。现在未命中只返回 nil，下次还会重试。
function Adapter:sub(parent_id, child_name)
  -- ★ 2026-09-26 扩展：支持「子控件装在一个中间容器里」的配法。
  --
  -- 为什么需要：官方《预设按钮的功能》写着
  --   「预设按钮可以**引用子层级中的客户端控件，作为不同状态节点的外显样式**」，
  --   也就是**预设按钮自己的图不显示，显示的是状态节点引用的那些子控件**（真机也印证过：
  --   "只改按钮自己的图片/尺寸，画面上完全看不出来"）。
  --   而脚本**既读不到也改不了状态节点的引用关系** ——
  --   `ClientUIPresetButtonControl` 在官方 API 里只有 3 个字段
  --   （`interactable` / `clickAudioId` / `raycastTarget`），**没有任何 *ChildId**。
  --
  --   所以最省事的配法是：**「默认」状态只引用一个容器**（例如 `content`），
  --   所有可见元素（face/note/x/wall.*/door.*/obj）都装在那个容器里 ——
  --   引用一次就够，**不用赌"一个状态节点能不能引用多个控件"**。
  --
  --   代价是脚本要能按 `cell.content.face` 找到东西，所以这里三级尝试：
  --     ① 直接子控件（扁平配法，零成本）
  --     ② cfg.cells.sub_roots（默认 content/root/body）下面的同名子控件
  --     ③ 官方 `FindChild(path)`（文档：「按路径查找子控件」）
  --   两种布局都能用，**不用改配置**。
  local key = parent_id .. "." .. child_name
  local cached = self.subs[key]
  if cached ~= nil and cached ~= false then return cached end
  local parent = self:find(parent_id)
  if parent == nil then return nil end

  local hit = nil
  if parent.GetChild ~= nil then
    pcall(function() hit = parent:GetChild(child_name) end)
  end

  local roots = (self.cfg.cells and self.cfg.cells.sub_roots)
    or { "content", "root", "body" }

  if hit == nil then
    for i = 1, #roots do
      local mid = nil
      if parent.GetChild ~= nil then
        pcall(function() mid = parent:GetChild(tostring(roots[i])) end)
      end
      if mid ~= nil and mid.GetChild ~= nil then
        pcall(function() hit = mid:GetChild(child_name) end)
        if hit ~= nil then break end
      end
    end
  end

  if hit == nil and parent.FindChild ~= nil then
    for i = 1, #roots do
      for _, sep in ipairs({ "/", "." }) do
        local p = tostring(roots[i]) .. sep .. tostring(child_name)
        pcall(function() hit = parent:FindChild(p) end)
        if hit ~= nil then break end
      end
      if hit ~= nil then break end
    end
  end

  if hit ~= nil then self.subs[key] = hit end
  return hit
end

----------------------------------------------------------------------------
-- 控件生命周期
----------------------------------------------------------------------------

function Adapter:create_control(node)
  -- ★★★★★ 2026-10-05 **这里登记的是「这个引擎控件是谁建的」，不是「事件表」。**
  --
  --   为什么仍然按 `node.id`：一个 id 只对应**一个**引擎控件（`_created[id]` 保证
  --   `create_control` 只跑一次），而后面 `rect` 分支要用 `handlers[pid]` 反查
  --   **父控件**的 `rect` —— `pid` 是**控件 id**，那里只能按 id 查。
  --   ⚠️ 事件**不在这里**：它已经搬到 `self.events[规划节点键]`（见 `set_property` 的
  --      `key == "event"` 分支）。旧写法把"节点登记"和"事件表"挤在同一张表上，
  --      于是第二个同 id 节点一写就把第一个的事件吃掉了 ✗
  --      （这就是 `handlers[node.id] = node` 那一行曾经的病根；登记本身没错，兼任才有错）。
  self.handlers[node.id] = node
  local ctrl = self:find(node.id)

  -- ★★★★★ 2026-10-02 **重建之后：所有界面控件都由脚本创建**。
  --
  --   背景：用户把编辑器里的 `select`/`board`/`left`/`right`/`topbar`/`toolbar`/
  --   `modal`/`intro`/`assets` **全部删掉**（只留 `home` + `stage` + 三个模板引用），
  --   于是 `ui_controller` 里规划的那些控件**全都不存在了**（真机日志：
  --   "这些控件还没建（共 108 个，按类分组）"）。
  --
  --   ⇒ 这里加一条**按 kind 自动选模板**的规则，把"显式 prefab_of"变成可选：
  --       · 容器类 kind  → 容器模板 `cfg.stage.prefab`（1073742330）
  --       · 其它 kind    → 通用控件模板 `cfg.cells.prefab`（1073741876，带 face/text 子控件）
  --     父级仍按 `cfg.parent_of[id]`（没有就用 `stage`）。
  --
  --   ⚠️ 与 `ensure_cells` / `ensure_widgets` 同一套路：改名 + 读回核对 + 记录 + 允许销毁。
  local AUTO_CONTAINER_KINDS = {
    container = true, panel = true, layer = true, list = true, box = true,
  }
  local function auto_prefab(ad, nd)
    if AUTO_CONTAINER_KINDS[nd.kind] then
      return ad.cfg.stage and ad.cfg.stage.prefab
    end
    -- ★ 2026-10-03 **图标用专用模板**（用户提供的干净客户端模板 `cfg.prefab_icon`）。
    --   原来七个 hex.* 走的是 `cells.prefab`（格子模板），那会**连带一整套格子子控件**
    --   （content / wall.* / door.* / note / x）⇒ 真机表现：画面上多出 7 个"迷你格子"
    --   把棋盘搅乱，而且 SetImage 打不到图片节点（只能落到 content 容器上）。
    if nd.icon_template == true and ad.cfg.prefab_icon ~= nil then
      return ad.cfg.prefab_icon
    end
    return ad.cfg.cells and ad.cfg.cells.prefab
  end
  -- ★★★★★ 2026-10-09 **白名单 `cfg.auto_create_only` 已删除**（那 14 个控件搬进存档了 ✓）
  --
  --   历史 ✓：`auto_create = false` 是**全局**开关，一关就全关 ——
  --     连新加的七个 `hex.*` 图标也一起被挡在外面（真机日志里它们出现在"这些控件还没建 ×7"✓）
  --     但**不能**改回 true：那会一次性去建规划里缺的 96 个控件
  --     （`clue.*` `ruler.*` `room.*` `obj.*` …）⇒ 又变成"一堆白块盖住界面" ✗
  --     ⇒ 当时的折中是加一层**按 id 的白名单**，只放行 `hex.*` / `hit.*` ✓
  --
  --   ★ 现在白名单**整段删掉**了 ✓（用户 2026-10-09：「同意搬 1」✓）
  --     · 搬法：`tools/gil/gen_icons.mjs` ⇒ 产物 `230-图标搬进存档.gil` ✓
  --     · 实测印证 ✓：`check_names` 的「🟢 脚本会自动建」**14 → 0** ✓
  --     · 而且下面这段本来就"**先找、找不到才建**"（`ctrl == nil`）✓
  --       ⇒ 存档里有了 ⇒ 永远走"找到"这一支 ⇒ 白名单确实成了死配置 ✓
  --   ⇒ `auto_create`（全局）**保留** ✓ —— 它是"绝不让脚本按 kind 造白块"的底线 ✓
  --     本改动**只删白名单**，不动那条底线 ✓
  local allow_auto = (self.cfg.auto_create == true)
  if ctrl == nil and allow_auto and game and game.InstantiateClientUIControl then
    local prefab = (self.cfg.prefab_of and self.cfg.prefab_of[node.id]) or nil
    if prefab == nil then prefab = auto_prefab(self, node) end
    if prefab ~= nil then
      local pname = (self.cfg.parent_of and self.cfg.parent_of[node.id]) or "stage"
      local parent = self:find(pname)
      if parent == nil and pname ~= "stage" then parent = self:find("stage") end
      if parent == nil then parent = self:find("root") end
      if parent then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = node.id end)
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= node.id then
            self:warn_once("auto:name:" .. tostring(node.id),
              "自动创建的控件改名没生效：想要 `" .. tostring(node.id) .. "`，读回来 `" .. tostring(got) .. "`。")
          end
          ctrl = obj
          self.controls[node.id] = ctrl
          self.instantiated = self.instantiated or {}
          -- ★★★★★ 2026-10-05 **新控件进树 = 控件名缓存作废 + 兜底隐藏重跑一次。**
          --   两件事必须同时做（见 `Adapter:invalidate_lookups` 与 `find` 的两段注释）：
          --     · 名字缓存：这一代里"没搜到"的判定不再成立（树多了一个节点）；
          --     · 兜底隐藏：新控件挂在**被隐藏的容器**下面时，它自己是 visible=true 的
          --       （模板带的），必须靠 enforce_hidden_subtrees 压下去 ——
          --       原来靠每帧扫一遍才发现，现在靠这个事件。
          self:invalidate_lookups("create:" .. tostring(node.id))
          -- ★★★★★ 2026-10-05 **新控件 = 重新武装射线开关那一趟**（每帧成本第 (3) 条）。
          --
          --   为什么必须补这一条：`enable_raycast` 收敛/放弃之后**不再整树重扫**了，
          --   而"新控件"完全可能是**按钮**（有 `raycastTarget` 字段）—— 漏掉它
          --   ⇒ 新按钮**点不动**（这个项目里"点不动"是反复发作的头号病）。
          --   ⚠️ "重新武装"**不等于"立刻扫"**：扫描本身仍被 `main.lua` 的
          --      "每 20 帧最多一趟"限着（见 `Adapter:enable_raycast` 那段注释）。
          --   ⚠️ 而且**只在这里**重新武装，**不挂进 `invalidate_lookups`** ——
          --      那个函数还被"网格滚动重进回调"调用（`tests/grid_cost.lua` 专门有一段
          --      `reenter()` 模拟"引擎每帧重进"）⇒ 挂那儿等于每帧重扫，白跑比改之前还多。
          --   ⚠️ 建控件的次数是**有界**的（`_created` 记过就不再建）⇒ 不会退化成每帧负载。
          self:rearm_raycast("create:" .. tostring(node.id))

          -- ★★★★★ 2026-10-03 **把规划里的 `image_id` 真正设到控件上**。
          --
          --   为什么必须在这里做：在这之前，整个适配器**没有任何一处消费 `node.image_id`**
          --   （我 grep 过 `.image_id`，结果为空）。而 `build_layout` 里一直有节点带着
          --   `image_id`（`obj.shelf` 那批 OBJECT_PALETTE，以及本轮新加的七个 `hex.*` 图标）
          --   ⇒ **控件建出来了、却是没有图的空白** ⇒ 真机表现就是**"控件不可见"**。
          --   这也正是 `obj.*` 自始至终没出现过的原因。
          --
          --   做法照抄已经跑通的格子那条路（`_cells_stamp`）：
          --   先看控件自己有没有 SetImage，没有就往下找第一个带 SetImage 的子控件
          --   （客户端控件模板通常把图片放在 `img` / `icon` / `face` 这类子节点上）。
          if node.image_id ~= nil then
            -- ★ 2026-10-03 **递归找**：真机日志证明"只找直接子控件"是不够的 ——
            --   `ClientUIPresetButtonControl`（格子模板建出来的那个）的直接子控件只有一个
            --   `content`，而图片 `face` 在 `content` 的**里面**（日志原文：
            --   `格子子控件实况（cell.1.1）：content(vis=true,124x124,img=nil)`）。
            --   所以这里往下递归最多 4 层：先按常见名字（face/img/icon/bg/image/content）钻，
            --   再兜底遍历全部子控件。
            local function has_setimage(c)
              local has = false
              pcall(function() has = (c.SetImage ~= nil) end)
              return has
            end
            local found_name = nil
            local function find_target(c, depth)
              if c == nil or depth > 4 then return nil end
              -- ★★ 2026-10-03 **顺序很关键**：先"按名字往下钻"，**钻完再考虑自己**。
              --
              --   上一轮我把"自己有没有 SetImage"放在最前面，结果首个命中就是 `content`
              --   （它是中间容器，也有 SetImage）⇒ 把图设到了容器上，并把 7 个用格子模板
              --   建出来的图标控件变成了"迷你格子"（自带 wall.* / door.* / face），
              --   真机表现就是**棋盘跟着一起变样/不见**。
              --
              --   而格子自己的做法是给 **`content/face`** 设图（日志：
              --   `子控件 face 存在（visible=true）imageId=106053`）⇒ **face 才是图片控件**。
              for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
                local kid = nil
                pcall(function() kid = c:GetChild(cn) end)
                if kid ~= nil then
                  local r = find_target(kid, depth + 1)
                  if r ~= nil then found_name = cn return r end
                end
              end
              if has_setimage(c) then return c end
              local n = 0
              pcall(function() n = c:GetChildCount() end)
              for i = 0, n - 1 do
                local kid = nil
                pcall(function() kid = c:GetChild(i) end)
                if kid ~= nil then
                  local r = find_target(kid, depth + 1)
                  if r ~= nil then return r end
                end
              end
              return nil
            end
            local target = find_target(ctrl, 0)

            if target ~= nil then
              local src = nil
              pcall(function() src = target.imageSource end)
              local ok2 = pcall(function() target:SetImage(src, node.image_id) end)
              if not ok2 then pcall(function() target:SetImage(node.image_id) end) end
              if node.imageColor ~= nil then
                pcall(function() target.imageColor = node.imageColor end)
              end
              if node.imageType ~= nil then
                pcall(function() target.imageType = node.imageType end)
              end
              pcall(function() target:SetVisible(true) end)
              local readback = "?"
              pcall(function() readback = tostring(target.imageId) end)
              if print then
                print("[murdoku] 图标设图 " .. tostring(node.id)
                  .. "  imageId=" .. tostring(node.image_id)
                  .. " → 回读 " .. readback
                  .. "  经 " .. tostring(found_name or "子控件")
                  .. "  调用成功=" .. tostring(ok2))
              end
            else
              -- 一个都没找到：把子控件清单打出来，方便下一次直接看出结构
              local desc = {}
              local n = 0
              pcall(function() n = ctrl:GetChildCount() end)
              for i = 0, n - 1 do
                local kid = nil
                pcall(function() kid = ctrl:GetChild(i) end)
                if kid ~= nil then
                  local nm, cnt = "?", 0
                  pcall(function() nm = tostring(kid.name) end)
                  pcall(function() cnt = kid:GetChildCount() end)
                  desc[#desc + 1] = nm .. "(" .. cnt .. ")"
                end
              end
              self:warn_once("icon:target:" .. tostring(node.id),
                "控件 `" .. tostring(node.id) .. "` 建好了，但递归 4 层也没找到带 SetImage 的控件。"
                .. "它的子控件：" .. (table.concat(desc, " ") ~= "" and table.concat(desc, " ") or "（一个都没有）"))
            end
          end
          -- ★★★★★ 2026-10-04 **再走一遍 `_cells_paint`** —— 这条才是**真能渲染出来**的那条路。
          --
          --   上面那段"递归找带 SetImage 的子控件"只做了两件事：设图 + SetVisible(true)，
          --   **没设尺寸**。而格子模板建出来的 `face` **默认尺寸是 0** ⇒ 图设上了、
          --   `visible=true`，**画面上什么都没有** —— 真机日志"图标设图 … 调用成功=true"
          --   却看不见，就是这个。
          --   对照证据：v044（纯图片模板）下同样这段代码是**看得见**的，因为纯图片模板的
          --   图片子节点自带尺寸；v045 换成格子模板后就消失了。

          --   `_cells_paint` 是 25 个格子正在用的那条路（`格子底图已点亮：25 个 face`），
          --   它多做两件事：`face:SetSizeDelta(size)` + `face:SetAnchoredPosition(0,0)`。
          --   第 4 个参数传该图标自己的素材；`size` 传 nil ⇒ 它按控件实际尺寸算。
          pcall(function() self:_cells_paint(ctrl, nil, node.id, node.image_id) end)

          self.instantiated[node.id] = true
          self._auto_made = (self._auto_made or 0) + 1
        else
          self:warn_once("auto:fail:" .. tostring(node.id),
            "自动创建 `" .. tostring(node.id) .. "` 失败（模板 " .. tostring(prefab) .. "）"
            .. "err=" .. tostring(obj))
        end
      end
    end
  end

  if ctrl == nil then
    self:_note_missing(node.id)
    return nil
  end

  -- ★★★★ 2026-10-01 **真机"卡死"修复：全屏容器必须关掉射线。**
  --
  --   症状（用户实测）：点「选关」能进去，但**退不出来、进不了关卡，
  --   连奇域本身的退出按钮都点不动** —— 整个界面像卡死。
  --
  --   根因：我为了修"界面空白"把 `home` / `select` 两个容器从 150x150
  --   改成了**铺满整屏 1600x900**（inherit_pos_runtime 那一轮）。
  --   容器一旦铺满 + 又吃射线（`raycastTarget` 默认就是 true），
  --   它就**把整个屏幕盖住** —— 包括**游戏自己的 UI**（退出按钮）。
  --   => "退出按钮点不了"正是这个，不是脚本自己的按钮坏了。
  --      （我第一反应怀疑 `seal_containers` —— 翻了一眼实现，
  --        它只把 `disableKeyEventPassthrough` 设 true，点击那条早就设成 false 了，
  --        所以不是它。**先看代码再下结论**，这次差点又误判。）
  --
  --   => 容器**本来就不需要被点到**（要点的永远是里面的按钮），
  --      所以给这两个全屏容器显式关掉射线。
  if node.id == "home" or node.id == "select" then
    -- 真机上才问清楚的事实：日志打出
    --   容器 home 关射线：原=nil  字段写=没有这个字段  passthru字段存在
    -- => 这个引擎**根本没有 raycastTarget 字段**，我前两版都在改一个不存在的属性。
    -- 真正存在的是 disableCursorEventPassthrough（项目里 open_click_passthrough
    -- 就是靠它让格子的点击到达按钮）。这里把相关字段全列一遍、并回读，一次问清。
    local has = {}
    for _, k in ipairs({ "raycastTarget", "disableCursorEventPassthrough",
                          "disableKeyEventPassthrough", "interactable",
                          "blockRaycast", "showCursor" }) do
      local v = nil
      pcall(function() v = ctrl[k] end)
      has[#has + 1] = k .. "=" .. tostring(v)
    end
    print("[murdoku] 容器 " .. node.id .. " 字段： " .. table.concat(has, "  "))
    if ctrl.disableCursorEventPassthrough ~= nil then
      local o1 = pcall(function() ctrl.disableCursorEventPassthrough = false end)
      local r1 = "?"
      pcall(function() r1 = tostring(ctrl.disableCursorEventPassthrough) end)
      print("[murdoku]   容器 " .. node.id .. " 写 disableCursorEventPassthrough=false 成功="
        .. tostring(o1) .. " 回读=" .. r1)
    end  end
  -- ★ 2026-09-26 修的严重 bug：bind_input 以前**定义了但从没被调用**，
  --   于是没有任何控件挂上光标监听 —— 整个界面点哪儿都没反应（模拟器和真机一样）。
  --   绑定放在这里（每个 id 只 create 一次），并让 bind_input 自己防重复。
  --
  -- 只给「按钮 / 光标检测区域」绑：文本框即使带了 event 也不支持光标事件，
  -- 硬绑只会刷一屏「不支持光标事件」。
  if node.event ~= nil and (node.kind == "button" or node.kind == "cursor") then
    self:bind_input(node.id, node)
  end
  return ctrl
end

----------------------------------------------------------------------------
-- 运行时光栅：用「控件模板索引」批量生成 cell.<r>.<c>
--
-- 为什么需要它：编辑器的「位置」是两套规则混用的（官方 API 文档 1317~1322 行）——
--   · 无父层级：以**画布左下角**为原点的绝对坐标
--   · 有父层级：与**父层级中心**的相对偏移
-- 手摆 25 格既枯燥、又很容易把两套规则搞混导致错位。
-- 这里只要求你在编辑器里把 **1 个** 格子做对，另存为模板后把「控件模板索引」
-- 填进 cfg.cells.prefab，剩下 24 个交给运行时生成 —— 以后换 6×6 / 7×7 关卡也不用重摆。
--
-- cfg.cells = {
--   prefab   = 1073741961,   -- 控件模板索引（编辑器里点客户端控件可以看到）
--   parent   = "board",      -- 生成到哪个控件下
--   size     = 124,          -- 格子边长
--   pitch    = 132,          -- 相邻格子的步距（边长 + 间距）
--   margin   = 14,           -- 左上角距父级的边距
--   parent_w = 680,          -- 父控件宽（用来算"相对父级中心"的偏移）
--   parent_h = 680,          -- 父控件高
-- }
----------------------------------------------------------------------------

function Adapter:cell_id(r, c) return string.format("cell.%d.%d", r, c) end

-- 算格子的几何。**优先用父控件的实际尺寸**，这样 5×5 / 6×6 / 7×7 自动适配 ——
-- 编辑器只要按**最大的 N** 把格子建够，小棋盘多出来的格子由界面层隐藏、
-- 大小与位置由这里在运行时摆正，不需要为每个尺寸重摆一次布局。
-- 拿不到实际尺寸时退回 cfg.cells 里的固定值（老行为，保持兼容）。
--
-- 返回 size, pitch, margin, pw, ph
function Adapter:cell_geometry(n)
  local g = self.cfg.cells or {}
  n = math.max(1, tonumber(n) or 5)

  local pw = g.parent_w or 733
  local ph = g.parent_h or 733
  local parent = self:find(g.parent or "board")
  if parent ~= nil and parent.GetSizeDelta ~= nil then
    local ok, w, h = pcall(function() return parent:GetSizeDelta() end)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      pw, ph = w, h
    end
  end

  local avail = math.min(pw, ph)
  -- ★★★★★ 2026-10-04 **`ruler` 是"边框"，两边都有** —— 原来只扣一边（`avail - ruler`）是错的。
  --
  --   判据是 `docs/布局图-关卡内-v3.png` 的逐像素测量（1600×900，已经是画布空间）：
  --     棋盘外框 584×584，**边框四边均匀 12px**
  --     内区 = 584 − 2×12 = **560**
  --     图上画的是 **6×6**：pitch = 560/6 = **93.33**（实测格心间距 93/94 交替）
  --                       格 = pitch − 4 = **89.33**（实测 89/90 交替）
  --     ⇒ 同一个公式换成本项目在用的 N=5：pitch = 560/5 = **112**、格 = **108** ✅
  --   ⇒ 所以"棋盘外框固定、格子按关卡 N 自适应"这条设计是成立的，
  --     错的只是**边框只扣了一边**，导致格子偏右下一格。
  local ruler = g.ruler or math.floor(avail * 0.06)     -- 边框厚度（左/右、上/下各一份）
  local area  = avail - 2 * ruler
  local pitch = math.floor(area / n)
  local gap   = g.gap or math.max(2, math.floor(pitch * 0.03))
  local size  = math.max(8, pitch - gap)
  -- 居中：格子区域在"扣掉两边边框之后"的区域里居中
  local margin = ruler + math.floor((area - (n * pitch - gap)) / 2)

  -- 显式配置优先（想钉死某个值时用；不写就自动算）
  if g.size   then size   = g.size   end
  if g.pitch  then pitch  = g.pitch  end
  if g.margin then margin = g.margin end
  return size, pitch, margin, pw, ph
end

-- 第 (r,c) 格的中心相对「父控件中心」的偏移（Y 向上，跟官方嵌套控件的 SetAnchoredPosition 一致）
-- n 不传就用 g.rows/g.cols，再不行按 max(r,c) 兜底
function Adapter:cell_offset(r, c, n)
  local g = self.cfg.cells
  if g == nil then return nil end
  n = n or g.rows or g.cols or math.max(r, c)
  local size, pitch, margin, pw, ph = self:cell_geometry(n)
  -- x：从父级左边量 margin，第 c 格再加 (c-1)*pitch，取中心后减去父级中心
  local x = margin + (c - 1) * pitch + size / 2 - pw / 2
  -- y：第 1 行在最上面，所以从父级上边往下走，最后减父级中心
  local y = ph - margin - (r - 1) * pitch - size + size / 2 - ph / 2
  return x, y
end

-- ★★★★★ 2026-10-04 **「这张图到底该设在哪个控件上」** —— 从 `ensure_widgets` 里那段
--   已经跑通的 `find_target` 原样抽出来，供别处复用（目前是 main.lua 的棋盘底板）。
--
--   为什么必须抽出来：真机日志（2026-10-04 14:18）证明
--       `棋盘底板：board.bg 建=true 设图=false imageId=0`
--   ——**运行时新建的客户端控件，在"根节点"上 `SetImage` 直接返回 false、`imageId` 一直是 0**。
--   而同一批模板建出来的七个图标走「子控件」那条路就成功了
--   （日志：`图标设图 hex.back imageId=100109 → 回读 100109  经 子控件  调用成功=true`）。
--   ⇒ 结论：**图片挂在子控件上，模板的根只是个容器** —— 设图必须往下钻，不能设在根上。
--
--   ★ 顺序很关键（这条是上一轮踩出来的，不能改）：
--     **先按名字往下钻，钻完再考虑自己。**
--     反过来会让 `content` 这种"中间容器"抢先命中，把图设到容器上，
--     真机表现是控件变成"迷你格子"或整体不见。
--
--   ★ 2026-10-04 增加的判据：优先选 **`imageSource` 非 nil** 的那个控件。
--     原因：真机上 `SetImage(nil, id)` 会失败，而 `target:SetImage(src, id)`（src 取自
--     `target.imageSource`）才是验证过能成功的形式 ⇒ 没有 imageSource 的控件设不进图。
--     所以"有 SetImage"只是及格线，"有 SetImage 且 imageSource 非 nil"才算合格。
--
--   返回：target（找不到就是 nil）、命中的子控件名（自己命中时为 nil，调用方显示"根"）
function Adapter:image_target(ctrl)
  if ctrl == nil then return nil end
  local found_name = nil

  local function has_setimage(c)
    local has = false
    pcall(function() has = (c.SetImage ~= nil) end)
    return has
  end
  -- 「合格」= 有 SetImage 且 imageSource 读得到（否则 SetImage 会失败）
  local function usable(c)
    if c == nil or not has_setimage(c) then return false end
    local src = nil
    pcall(function() src = c.imageSource end)
    return src ~= nil
  end

  local function dive(c, depth)
    if c == nil or depth > 4 then return nil end
    -- ① 按名字往下钻（face/img/icon/... 是官方模板给图片子节点起的常见名字）
    for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
      local kid = nil
      pcall(function() kid = c:GetChild(cn) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then found_name = cn return r end
      end
    end
    -- ② 自己：先看"合格"的，再看"只是有 SetImage"的（保持与旧行为一致，只是更好）
    if usable(c) then return c end
    if has_setimage(c) then return c end
    -- ③ 兜底：遍历全部子控件（模板里的图片节点不一定用上面那六个名字）
    local n = 0
    pcall(function() n = c:GetChildCount() end)
    for i = 0, n - 1 do
      local kid = nil
      pcall(function() kid = c:GetChild(i) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then return r end
      end
    end
    return nil
  end

  local t = dive(ctrl, 0)
  return t, found_name
end

-- 把图设到 `image_target` 找到的那个控件上，并把**回读**打出来。
--
--   为什么回读必须打：这个工程反复吃亏在"调了 API 就当成功了"。
--   真机上 `SetImage` 有的重载**静默失败**，只有 `imageId` 回读才能证明图真的设进去了。
--
--   image_type：一般给 "Stretch"（底板类素材才支持拉伸）。
--   image_color：32 位整数 ARGB（`Color()` 全局函数在真机上不存在，所以只能直接写整数）。
--                传 nil 就不动颜色。**乘算着色**：素材是白模时，染成什么色就是什么色。
--   label：日志前缀（传 nil 就不打日志）。
--
--   返回：hit(布尔：回读等于要设的 id 才算真成功)、命中描述(字符串)、回读 imageId(字符串)、
--         tint_ok(布尔/nil：没要求染色时是 nil；要求了就看回读**是不是真变成了那个色**)
--
--   ★★ 为什么要回读颜色而不是"调了就算成功"（2026-10-04）：
--     用户点名要"把底板换成**纯色图形**"，而官方素材库里**所有形状/底板都是白模**
--     （`100001` 纯白方块、`106xxx` 单色底板全是白的）⇒ 想要纯色就**必须靠染色**。
--     而 `imageColor` 能不能用**整数**写进去，本项目**至今没有真机证据**
--     （文档里只有"离线冒烟"验过 `face.imageColor.r=10`，真机只验过"没有全局函数 `Color`"）。
--     ⇒ 所以这里把"染色到底成没成"变成一个**可判定的事实**，调用方据此决定要不要回退。
function Adapter:set_image_deep(ctrl, image_id, image_type, image_color, label)
  if ctrl == nil then return false, "没有控件", "?" end
  local target, found = self:image_target(ctrl)
  if target == nil then
    return false, "找不到可设图的子控件", "?"
  end
  -- ★ 先试 (src, id) 两参形式 —— 这条路在真机上验通过；失败再试单参形式。
  local okcall = false
  local src = nil
  pcall(function() src = target.imageSource end)
  okcall = pcall(function() target:SetImage(src, image_id) end)
  if not okcall then
    okcall = pcall(function() target:SetImage(image_id) end)
  end
  if image_type  ~= nil then pcall(function() target.imageType  = image_type  end) end
  if image_color ~= nil then pcall(function() target.imageColor = image_color end) end

  local rid, rcol = "?", "?"
  pcall(function() rid  = tostring(target.imageId)   end)
  -- ★ 颜色回读**分两种形态**处理：真机 `fontColor` 读出来是整数，但 `imageColor`
  --   官方类型是 `ColorValue` ⇒ 也可能是"有 r/g/b/a 字段的对象"。两种都认。
  local tint_ok = nil
  if image_color ~= nil then
    local want = tonumber(image_color) or 0
    local wr = math.floor(want / 65536) % 256
    local wg = math.floor(want / 256) % 256
    local wb = want % 256
    local wa = math.floor(want / 16777216) % 256
    tint_ok = false
    local v = nil
    pcall(function() v = target.imageColor end)
    if type(v) == "number" then
      -- 形态①：整数（按 ARGB 解）
      local gr = math.floor(v / 65536) % 256
      local gg = math.floor(v / 256) % 256
      local gb = v % 256
      tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
      rcol = tostring(v)
    elseif v ~= nil then
      -- 形态②：ColorValue 对象（读 r/g/b/a 字段）
      local gr, gg, gb, ga = nil, nil, nil, nil
      pcall(function() gr = v.r end)
      pcall(function() gg = v.g end)
      pcall(function() gb = v.b end)
      pcall(function() ga = v.a end)
      rcol = "(" .. tostring(gr) .. "," .. tostring(gg) .. "," .. tostring(gb)
        .. "," .. tostring(ga) .. ")"
      if type(gr) == "number" and type(gg) == "number" and type(gb) == "number" then
        tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
        if type(ga) == "number" and math.abs(ga - wa) > 2 then tint_ok = false end
      end
    else
      rcol = "nil（读不到 imageColor）"
    end
  else
    pcall(function() rcol = tostring(target.imageColor) end)
  end
  local hit = (rid == tostring(image_id))
  if print and label ~= nil then
    print("[murdoku] 设图 " .. tostring(label)
      .. "  imageId=" .. tostring(image_id)
      .. " → 回读 " .. rid
      .. "  imageColor 回读 " .. rcol
      .. "  染色成功=" .. tostring(tint_ok)
      .. "  经 " .. tostring(found or "根")
      .. "  调用成功=" .. tostring(okcall)
      .. "  真的设上了=" .. tostring(hit))
  end
  return hit, (found or "根"), rid, tint_ok
end

-- 「不用日志也能看出结果」的诊断信号。
-- 找一个"改了外观就会变"的控件，把它的边长设成 v（正方形），肉眼即可读数。
--
-- ★ 2026-09-25 血泪教训：**别改预设按钮本身**！
--   预设按钮的外观来自它「状态节点」引用的**子控件**，改按钮的 sizeDelta 在画面上
--   完全看不出来（我们为此白测了一整天）。一定要改**子控件**，比如 cell.1.1 的 `face`。
-- ★ 另一个坑：`Adapter:sub()` 未命中会**永久缓存 false**，UI 就绪前查过一次就再也拿不到。
--   所以这里**绕开 sub()**，直接用 GetChild 现查。
function Adapter:_cells_signal(v)
  local targets = {}
  local c = self:find("cell.1.1")
  if c ~= nil then
    if c.GetChild ~= nil then
      local ok, f = pcall(function() return c:GetChild("face") end)
      if ok and f ~= nil then targets[#targets + 1] = f end      -- ★ 首选：子控件（看得见）
    end
    targets[#targets + 1] = c                                     -- 兜底：按钮本身（多半看不见）
  end
  local t = self:find("tray.A")
  if t ~= nil and t.GetChild ~= nil then
    local ok, f = pcall(function() return t:GetChild("face") end)
    if ok and f ~= nil then targets[#targets + 1] = f end
  end
  if game ~= nil and game.GetClientUIRoots ~= nil then
    local ok, roots = pcall(game.GetClientUIRoots)
    if ok and type(roots) == "table" and roots[1] ~= nil then
      targets[#targets + 1] = roots[1]
    end
  end
  for i = 1, #targets do
    local x = targets[i]
    if x.SetSizeDelta ~= nil then
      local ok = pcall(function() x:SetSizeDelta(v, v) end)
      if ok then return true end
    end
  end
  return false
end

-- 逐格自检：把 `board` 的**真实子控件**摊出来。
--
-- 为什么需要它：真机 2026-09-26 17:56 的日志出现了**对不上账**的情况 ——
--   缺 25 格 → 按理是"试造 1 + 循环 24 = 25 个新建"，可日志写的是**新建 23 个**，
--   而「25 / 25 存在」又说齐了。差的那 1 格既不是脚本建的、也不在预期路径上。
--   同时用户报告 **第一个格子的缺口仍在**。
--
-- 光靠"存在/不存在"这种二值信息已经查不下去了，所以这里直接摊开**实测数据**：
--   · `board` 在树上**实际**有哪些子控件（不走 find 的名字缓存，直接走树）；
--   · 每个格子的名字 / 屏幕位置 / 尺寸 / visible / active / 是不是脚本建的；
--   · 被"挪出画布"的那些引用控件现在在哪（用来确认它们真的挪走了）。
--
-- 读不到就打印 `?`，不猜。
function Adapter:diagnose_grid(rows, cols)
  if print == nil then return end
  local g = self.cfg.cells or {}
  local print_ = print

  print_("[murdoku] ===== 逐格自检（实测，不猜）=====")

  -- ① board 在树上到底有哪些子控件
  local parent = self:find(g.parent or "board")
  if parent == nil then
    print_("[murdoku] 找不到父控件 " .. tostring(g.parent or "board") .. " —— 后面的都查不了")
    print_("[murdoku] ===== 逐格自检结束 =====")
    return
  end
  local kids = nil
  pcall(function() kids = parent:GetChildren() end)
  local on_tree = {}
  local kid_names = {}
  if type(kids) == "table" then
    for i = 1, #kids do
      local nm = "?"
      pcall(function() nm = tostring(kids[i].name) end)
      on_tree[nm] = kids[i]
      kid_names[#kid_names + 1] = nm
    end
  end
  print_("[murdoku] " .. tostring(g.parent or "board") .. " 树上实际有 "
    .. #kid_names .. " 个子控件：" .. table.concat(kid_names, " "))

  -- ② 逐格：名字 / 位置 / 尺寸 / 可见 / 激活 / 来源
  local missing_on_tree, missing_as_ctrl = {}, {}
  local n_new, n_edit = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = on_tree[id]
      if ctrl == nil then
        missing_on_tree[#missing_on_tree + 1] = id
      end
      local via_find = self:find(id)
      if via_find == nil then missing_as_ctrl[#missing_as_ctrl + 1] = id end
      if self.instantiated and self.instantiated[id] then n_new = n_new + 1
      elseif ctrl ~= nil then n_edit = n_edit + 1 end
    end
  end

  -- 只列"有问题的"和第一行 —— 25 行全铺太吵
  local function describe(id)
    local ctrl = on_tree[id]
    local pos, size, vis, act = "?", "?", "?", "?"
    if ctrl ~= nil then
      -- ★ 读位置：官方给**控件**的接口是 `GetAnchoredPosition()` → x, y
      --   （`GetUIPos()` 在官方文档里**只属于 `CursorEventData`**，不是控件方法 ——
      --    我照着模拟器的方法表写成 `ctrl:GetUIPos()`，真机上必然读不到，日志里就是 `位置=?`。
      --    这是"模拟器有、文档没有"的案例之一。）
      --   兜底再试 `anchoredPositionX/Y` 字段。
      pcall(function()
        local a, b = ctrl:GetAnchoredPosition()
        if type(a) == "table" then pos = string.format("(%.0f,%.0f)", a.x or 0, a.y or 0)
        elseif a ~= nil then pos = string.format("(%.0f,%.0f)", a, b or 0) end
      end)
      if pos == "?" then
        pcall(function()
          local ax, ay = ctrl.anchoredPositionX, ctrl.anchoredPositionY
          if ax ~= nil then pos = string.format("(%.0f,%.0f)", ax, ay or 0) end
        end)
      end
      pcall(function()
        local w, h = ctrl:GetSizeDelta()
        if type(w) == "table" then size = string.format("%.0fx%.0f", w.x or 0, w.y or 0)
        elseif w ~= nil then size = string.format("%.0fx%.0f", w, h or 0) end
      end)
      pcall(function() vis = tostring(ctrl.visible) end)
      pcall(function() act = tostring(ctrl.active) end)
    end
    local origin = (self.instantiated and self.instantiated[id]) and "脚本建的" or "编辑器摆的"
    return "  " .. id .. "  " .. origin
      .. "  位置=" .. pos .. "  尺寸=" .. size
      .. "  visible=" .. vis .. "  active=" .. act
      .. (on_tree[id] == nil and "   ← **不在 " .. tostring(g.parent or "board") .. " 下**" or "")
  end

  if #missing_on_tree > 0 then
    print_("[murdoku] ⚠️ 这些格子在 " .. tostring(g.parent or "board") .. " 下**根本找不到**：" .. table.concat(missing_on_tree, " "))
  end
  if #missing_as_ctrl > 0 then
    print_("[murdoku] ⚠️ 这些格子 `find` 也取不到：" .. table.concat(missing_as_ctrl, " "))
  end
  print_("[murdoku] 来源统计：脚本建的 " .. n_new .. " 个，编辑器摆的 " .. n_edit
    .. " 个（合计 " .. (n_new + n_edit) .. " / " .. (rows * cols) .. "）")
  print_("[murdoku] 第一行逐格：")
  for c = 1, cols do print_(describe(self:cell_id(1, c))) end
  if #missing_on_tree > 0 or #missing_as_ctrl > 0 then
    print_("[murdoku] 其余有问题的格子：")
    local listed = {}
    for _, id in ipairs(missing_on_tree) do
      if not listed[id] then listed[id] = true; print_(describe(id)) end
    end
    for _, id in ipairs(missing_as_ctrl) do
      if not listed[id] then listed[id] = true; print_(describe(id)) end
    end
  end

  -- ③b ★ 子控件清单：把格子（含中间容器）里的东西**逐个摊出来**
  --
  -- 为什么需要：用户 2026-09-27 04:08 报告"只有部分东西可见，且只有两行"，
  --   而当时日志里**看不到格子里到底配了什么**（有几个子控件？叫什么？
  --   visible 是什么？图片类型是基础还是拉伸？）。
  --   特别是「**静态引用大多不支持拉伸**」这条 —— 只有把每个图片子控件的
  --   `imageType` / `imageId` 打出来，才能一眼看出谁被拉伸、谁只能按原样画。
  do
    local want = {
      -- ⚠️ 2026-09-27：`text` 原来**不在这个清单里**，于是真机日志的"子控件清单"
      --    里看不到它 —— 而格子文字恰恰靠它（预设按钮没有 text 属性，
      --    `set_property(id,"text")` 只能走 `sub(id,"text")` 这条回退路径）。
      --    清单漏项会让人误判"text 没配好"，所以补进来。
      "face", "text", "note", "x", "obj",
      "wall.up", "wall.down", "wall.left", "wall.right",
      "door.up", "door.down", "door.left", "door.right",
    }
    -- ★★★★★ 2026-10-05 **内部格也必须列一遍，不能只看 cell.1.1**。
    --
    --   为什么：`cell.1.1` 是**角格** —— 按 core 的 `view()`
    --     `walls.up = (r == 1)`、`walls.left = (c == 1)` **本来就为真**
    --   ⇒ 日志里"up/left 亮着"既可能是**脚本下发的**、也可能是**模板默认**、
    --     甚至是上一关留下的状态 —— **这个格子分辨不了**，而用户的症状恰恰是
    --     "第一次进关墙/门没画出来、第二次正常"（要判的就是"脚本设的"有没有生效）。
    --   内部格（`cell.2.2`）四个方向都有邻居 ⇒ 四面墙该不该亮**只可能来自脚本**
    --   ⇒ 只有把两个格子并排看（角格亮 / 内部格不亮 = 脚本那条 `walls` 没送达），
    --     结论才站得住。
    local function list_cell(probe, why)
      local have, miss = {}, {}
      for i = 1, #want do
        local s = self:sub(probe, want[i])
        if s ~= nil then have[#have + 1] = s else miss[#miss + 1] = want[i] end
      end
      print_("[murdoku] --- 格子里的子控件清单（" .. probe .. "，" .. why .. "）---")
      if #have == 0 then
        print_("[murdoku]   ⚠️ 一个都没找到。若你把它们装进了中间容器，容器名必须是 "
          .. "content / root / body 之一（配置项 cfg.cells.sub_roots）。")
      end
      for i = 1, #have do
        local s = have[i]
        local nm, vis, it, iid = "?", "?", "?", "?"
        pcall(function() nm = tostring(s.name) end)
        pcall(function() vis = tostring(s.visible) end)
        pcall(function() it = tostring(s.imageType) end)
        pcall(function() iid = tostring(s.imageId) end)
        print_("  " .. string.format("%-12s", nm)
          .. " visible=" .. string.format("%-5s", vis)
          .. " imageType=" .. string.format("%-26s", it)
          .. " imageId=" .. iid)
      end
      if #miss > 0 then
        print_("[murdoku]   没有配的：" .. table.concat(miss, " "))
      end
    end
    list_cell("cell.1.1", "角格：up/left 本来就该亮，分不清是谁设的")
    if rows >= 2 and cols >= 2 then
      list_cell("cell.2.2", "内部格：四邻都有 ⇒ 四面墙只可能来自脚本")
    else
      print_("[murdoku]   （本关只有 " .. rows .. "×" .. cols .. " 格，没有内部格可对照 —— "
        .. "角格分不清「脚本设的」和「模板默认」，这一条判不了。）")
    end
    print_("[murdoku]   （**静态引用大多不支持拉伸** —— 需要拉伸的地方请选「底板」类素材；"
      .. "imageType 显示 Stretch 才说明这个素材支持，Basic 就只能按原样铺。）")

    -- ★★★★★ 2026-10-05 **层序 / 锚点实测 —— 判「白色 face 把墙盖住了」这个假设**。
    --
    --   为什么要单独读这一组数：
    --     引擎的层序规则是「**兄弟索引大的画在上面**」（见 `enforce_layers` 那段注释），
    --     而脚本的层序是**倒序逐个 `SetAsFirstSibling()`** 排出来的 —— 也就是
    --     "最后一次 SetAsFirstSibling 的那个，索引最小 = 最下面"。
    --     这一串有没有真的生效，光看 `visible` 是看不出来的：
    --     墙 `visible=true` 也可能**被上面的 face 挡住**（用户看到的就是"墙没画出来"）。
    --   ⇒ 所以直接把 `face` 和 `wall.up` 的**实测兄弟索引**并排打出来：
    --        face 索引 **大于** wall.up ⇒ face 盖住墙（就是被遮挡，不是没设）。
    --     顺带把 `wall.up` 的锚点/位置/尺寸打出来 —— "墙被贴到画布外面去了"这一假设
    --     （`_apply_edges` 里那段按 `cell_geometry` 算的贴边代码）也一并可判。
    do
      local probe = (rows >= 2 and cols >= 2) and "cell.2.2" or "cell.1.1"
      local function idx_of(c)
        local v = "?"
        if c ~= nil then pcall(function() v = c:GetSiblingIndex() end) end
        return tostring(v)
      end
      local function f0(v) return (type(v) == "number") and string.format("%.0f", v) or "?" end
      local function geom_of(c)
        if c == nil then return "（取不到这个子控件）" end
        local ax, ay, bx, by, x, y, w, h = nil, nil, nil, nil, nil, nil, nil, nil
        pcall(function() ax, ay = c.anchorMinX, c.anchorMinY end)
        pcall(function() bx, by = c.anchorMaxX, c.anchorMaxY end)
        pcall(function() x, y = c.anchoredPositionX, c.anchoredPositionY end)
        pcall(function() w, h = c.sizeDeltaX, c.sizeDeltaY end)
        if w == nil then pcall(function() w, h = c:GetSizeDelta() end) end
        if x == nil then
          pcall(function()
            local a, b = c:GetAnchoredPosition()
            if type(a) == "table" then x, y = a.x, a.y else x, y = a, b end
          end)
        end
        return "anchorMin=(" .. f0(ax) .. "," .. f0(ay) .. ")"
          .. " anchorMax=(" .. f0(bx) .. "," .. f0(by) .. ")"
          .. " 位置=(" .. f0(x) .. "," .. f0(y) .. ")"
          .. " 尺寸=" .. f0(w) .. "x" .. f0(h)
      end
      local face = self:sub(probe, "face")
      local wu = self:sub(probe, "wall.up")
      print_("[murdoku] --- 层序/锚点实测（" .. probe .. "，判「白色 face 是否盖住墙」）---")
      print_("[murdoku]   face     兄弟索引=" .. idx_of(face) .. "  " .. geom_of(face))
      print_("[murdoku]   wall.up  兄弟索引=" .. idx_of(wu) .. "  " .. geom_of(wu))
      print_("[murdoku]   （判读：引擎是「**索引大的画在上面**」⇒ face 的索引 **大于** wall.up"
        .. " ⇒ 白色 face 把墙**盖住**了（不是没设上）；若 wall.up 取不到或位置/尺寸是 0，"
        .. "则是墙**根本没摆上去**。两种症状长得一样，只能靠这三行分开。）")
    end

    -- ★★ 对账：**本关需要哪些边** vs **模板里配了哪些子控件**
    --
    -- 用户 2026-09-27 04:26 的实际场景：关卡 wall_set 里有 `v:4:3` / `v:5:3`（竖墙），
    --   但模板只配了 `wall.up` → 那两面竖墙**画不出来**，而日志当时什么都没说。
    --   这类"数据要、素材没有"的缺口必须自己报出来，不该靠人看截图发现。
    if type(self.edges_needed) == "table" then
      local lack = {}
      for edge in pairs(self.edges_needed) do
        if self:sub("cell.1.1", edge) == nil then lack[#lack + 1] = edge end
      end
      table.sort(lack)
      if #lack > 0 then
        print_("[murdoku] ⚠️ **本关需要这些边，但模板里没有对应的子控件**（所以画不出来）："
          .. table.concat(lack, " "))
        print_("[murdoku]    补法：在模板的 `content` 里加同名图片子控件（"
          .. "`wall.up`/`wall.down`/`wall.left`/`wall.right`、`door.*`），"
          .. "**四个方向的墙要各自一个子控件**，不能只配一个。")
      else
        local need = {}
        for edge in pairs(self.edges_needed) do need[#need + 1] = edge end
        table.sort(need)
        print_("[murdoku] ✅ 本关需要的墙/门边，模板里都配了对应子控件：" .. table.concat(need, " "))
      end
    end
  end

  -- ③ 被挪走的引用控件现在在哪（确认"挪出画布"真的生效了）
  --
  -- ★ 2026-10-05 账本按**控件身份**去重（见 `_note_parked`），所以这段**每关只打一次**。
  --   真机 v062 的日志里它是 1 行 → 2 行 → 3 行（同一个 `tpl.cell`），
  --   很容易被读成"每次进关多出一个模板引用控件"—— 离线探针实测：控件始终只有 1 个。
  --   重复登记的次数在这里明说，免得下次又看错。
  local parked = self.cells_parked
  if type(parked) == "table" and #parked > 0 then
    print_("[murdoku] 已挪出画布的引用控件（确认位置真的到 200000 了吗）：")
    for i = 1, #parked do print_(describe(parked[i])) end
    local again = self.cells_parked_again or 0
    if again > 0 then
      print_("[murdoku]   （另有 " .. again .. " 次「同一个控件」的重复登记，已按控件身份去重 —— "
        .. "进 N 次关卡不会多出 N 行，也**不会**多出控件）")
    end
  end



  print_("[murdoku] ===== 逐格自检结束 =====")
end

-- 按钮专用信标：改**预设按钮自身**的尺寸。
-- 按钮自己不一定画东西，但它的子控件（居中锚点）会**跟着位移** —— 这个位移
-- 在 2026-09-25 实测是肉眼可辨的（最小探针就是靠它证明脚本在跑）。
function Adapter:_cells_beacon_button(v)
  local names = { "cell.1.1", "tray.A", "board" }
  for i = 1, #names do
    local c = self:find(names[i])
    if c ~= nil and c.SetSizeDelta ~= nil then
      local ok = pcall(function() c:SetSizeDelta(v, v) end)
      if ok then return true end
    end
  end
  return false
end

-- 兼容旧名
function Adapter:_cells_report(code)
  local map = { [1] = 80, [3] = 100, [4] = 40, [5] = 60 }
  self:_cells_signal(map[code] or (120 + code * 10))
end

-- 读一个控件的「引用控件模板索引」。
--
-- ★ 2026-09-26 用户纠正：`prefabIndex` 是**基类**字段（控件模板索引，即「这个控件本身
--   是哪个模板的实例」），而**模板引用控件**引用的是另一个字段
--   `referencedPrefabIndex`（官方原文：「引用控件模板索引」，只读）。
--   我一开始只读 `prefabIndex`，把 `tpl.cell` 的 `prefabIndex=1073741885` 误当成
--   "另一张模板的索引" —— 那其实是**控件自身的索引**。
--   所以判断"模板引用控件引用了哪张模板"必须优先读这个字段。
function Adapter:_ref_index_of(ctrl)
  if ctrl == nil then return nil end
  local r = nil
  pcall(function() r = ctrl.referencedPrefabIndex end)
  if type(r) == "number" and r > 0 then return r end
  return nil
end

-- 把控件「停到屏幕外」。
--
-- 为什么需要它：模板引用控件在棋盘上会占着一个格子位置，而真机上它渲染不出格子副本，
-- 于是那一格看着是空的。`SetVisible(false)` 不一定够 ——
-- 官方文档写着 `active` **只读**，且「true 时控件可见」，也就是**可见性由 active 参与决定**，
-- 脚本改不了 active。所以最稳的办法是**把它挪出画布**：不管可见性语义怎么算，
-- 它都不可能在屏幕上盖住任何东西。

-- 把"这个控件已经挪出画布了"记进诊断账本。
--
-- ★★★★★ 2026-10-05 **账本必须按控件身份去重**（真机 v062 日志的"每次进关多一行 tpl.cell"）。
--
--   现象（用户日志）：一次游玩里进 3 次关卡，`diagnose_grid` 那块打印的是
--       1 行 → 2 行 → 3 行，三行**一模一样**（都是 `tpl.cell  编辑器摆的 … 不在 stage 下`），
--     看着像"每进一次关就多出一个模板引用控件（ClientUIReferenceControl）"。
--
--   实测（离线探针进 3 次关卡，照 196-网格视窗兜底.gil 的树形：`tpl.cell` 挂在 `root` 下）：
--       · `root` 下名叫 `tpl.cell` 的子控件**始终是 1 个**；
--       · 账本里所有条目指向的是**同一个控件对象**；
--       · 它每次都停在 (200000,200000) —— `_park_control` 是幂等的。
--   ⇒ 多出来的**不是控件，是这本流水账**：`ensure_cells` 每次进关都会把同一个控件再登记一遍
--     （`hide_names` 那段每关都跑，而 `tpl.cell` 的名字不改，所以每关都命中）。
--
--   ⇒ 所以这里按**控件身份**去重（拿不到控件对象时才退回按名字），重复登记只累加计数，
--     由 `diagnose_grid` 用一句话说明"重复了几次" —— 账本仍然回答得了
--     "现在有哪些东西被挪走了"，但不会再让同一样东西看起来有 N 份。
function Adapter:_note_parked(name, ctrl)
  if name == nil then return false end
  self.cells_parked = self.cells_parked or {}
  self.cells_parked_seen = self.cells_parked_seen or {}
  local key = ctrl or name      -- ★ 有控件就用控件身份当键（"是不是同一个控件"才是这里的问题）
  if self.cells_parked_seen[key] then
    self.cells_parked_again = (self.cells_parked_again or 0) + 1
    return false
  end
  self.cells_parked_seen[key] = true
  self.cells_parked[#self.cells_parked + 1] = name
  return true
end

function Adapter:_park_control(ctrl)
  if ctrl == nil then return false end
  local ok = false
  -- ① 挪到画布外（画布 1600×900，挪到 200000 足够远）
  if ctrl.SetAnchoredPosition ~= nil then
    if pcall(function() ctrl:SetAnchoredPosition(200000, 200000) end) then ok = true end
  end
  -- ② 顺手缩成 0 尺寸（双保险；有些布局下位移会被锚点约束拉回来）
  if ctrl.SetSizeDelta ~= nil then
    pcall(function() ctrl:SetSizeDelta(0, 0) end)
  end
  -- ③ 再试一次隐藏
  if ctrl.SetVisible ~= nil then
    pcall(function() ctrl:SetVisible(false) end)
  end
  return ok
end

-- 取模板索引**候选列表**（按优先级）。
--
-- 官方 API：`prefabIndex` = 控件模板索引，只读（文档 1200~1203）。
--
-- ★ 为什么是"列表"而不是"一个索引"：
--   真机实测（2026-09-26）：`cell.1.1.prefabIndex` 读出来是 **1073741848**，
--   那是**「预设按钮」这个基础模板**的索引 —— 读得到，但拿去
--   `InstantiateClientUIControl` 会**静默返回 nil**（不报错）。
--   所以"读到就用"是错的，必须**真的试着造一个**才知道能不能用。
--
--   于是这里把所有能想到的来源排成候选，由 ensure_cells 逐个实测，
--   第一个造得出东西的才算数。这样你**不用把索引数字抄进代码**：
--   只要在编辑器里「另存为模板」，再从那个模板**新建一个控件**、命名为
--   `tpl.cell`（或保留已有的 cell.1.1），脚本就能自己找到可用索引。
--
--   候选来源（按顺序、自动去重）：
--     ① cfg.cells.prefab        —— 显式指定的数字，最优先
--     ② cfg.cells.probe         —— 默认 "cell.1.1"
--     ③ tpl.cell / cell.tpl / cell.prefab —— 约定名：从「另存为模板」新建的那个控件
--     ④ auto_scan（默认开）—— **扫全树**，把所有"与参照格子不同的 prefabIndex"
--        也当候选。为什么加这个：真机 15:46 日志里，用户新存的模板索引是 1073741876，
--        而 `tpl.cell` 还是**上一次**从旧模板建的（索引仍是 1073741864），
--        于是新索引没有任何控件引用它 → 脚本读不到 → 显式配置之外只能靠扫。
--        扫出来的候选排在最后，且**仍然逐个真试**，所以不会误用。
function Adapter:_cells_prefabs(g)
  local out, seen = {}, {}
  local function add(idx, from)
    if type(idx) ~= "number" or idx <= 0 then return end
    if seen[idx] then return end
    seen[idx] = true
    out[#out + 1] = { index = idx, from = from }
  end

  add(g.prefab, "cfg.cells.prefab")

  -- ★ 基准索引**只从「参照格子」(probe) 取**，不能从"第一个找到的控件"推。
  --
  -- 为什么：支持**纯模板模式** —— 编辑器里一个真格子都不建，只在 board 下放一个
  -- `tpl.cell`（模板引用控件）。这时 probe（默认 cell.1.1）不存在，
  -- 若还按"第一个找到的"当基准，基准就会变成 `tpl.cell` 自己的索引，
  -- 于是后面的判断变成"和它自己不同才算可用" → 恒为假 → 又打出
  -- "没有可用的自定义模板"那种误导结论。
  --
  -- probe 不存在时基准保持 nil，任何能读到正整数的候选都算"可能可用"。
  local probe_id = g.probe or "cell.1.1"
  local base_idx = nil
  do
    local c = self:find(probe_id)
    if c ~= nil then
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok and type(p) == "number" and p > 0 then base_idx = p end
    end
  end
  -- ★ 把"这一刻参照格子在不在"**记下来**，给体检用。
  --
  -- 为什么必须记：`_cells_prefabs` 是在**生成之前**跑的，那时纯模板模式下
  -- 参照格子确实不存在；而体检（diagnose_template）是在**生成之后**跑的 ——
  -- 那时 `cell.1.1` 已经被脚本造出来了，现场再查就查得到，于是"纯模板模式"
  -- 这个事实会被**生成的副作用掩盖掉**，报不出来。
  -- 教训同前：要报**当时记录的实测事实**，不要过后现场重推。
  self.cells_probe_missing = (base_idx == nil)

  local names = g.prefab_from
    or { probe_id, "tpl.cell", "cell.tpl", "cell.prefab" }
  for i = 1, #names do
    local c = self:find(tostring(names[i]))
    if c ~= nil then
      -- ★ 先读「引用控件模板索引」—— 模板引用控件引用的是它，不是 prefabIndex。
      --   两者都加进来（referenced 优先），因为：
      --     · 模板引用控件：referencedPrefabIndex 才是被引用的模板；
      --     · 普通控件 / 脚本生成的副本：只有 prefabIndex 可读。
      local r = self:_ref_index_of(c)
      if r ~= nil then add(r, tostring(names[i]) .. ".referencedPrefabIndex") end
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok then add(p, tostring(names[i])) end
    end
  end

  -- ④ 扫全树
  if g.auto_scan ~= false and game ~= nil and game.GetClientUIRoots ~= nil then
    local found = {}
    local ok, roots = pcall(game.GetClientUIRoots)
    if ok and type(roots) == "table" then
      local function walk(c, depth)
        if c == nil or depth > 8 or #found > 400 then return end
        local p = nil
        pcall(function() p = c.prefabIndex end)
        if type(p) == "number" and p > 0 and p ~= base_idx and not seen[p] then
          local nm = "?"
          pcall(function() nm = tostring(c.name) end)
          found[#found + 1] = { index = p, name = nm }
        end
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do walk(kids[i], depth + 1) end
        end
      end
      for i = 1, #roots do walk(roots[i], 0) end
    end
    for i = 1, #found do
      add(found[i].index, "扫描到 " .. found[i].name)
    end
  end

  return out
end

-- 兼容旧名（别处还在用）
function Adapter:_cells_prefab(g)
  local list = self:_cells_prefabs(g)
  if list[1] ~= nil then return list[1].index end
  return nil
end

-- ★★★★★ 2026-10-02 **给脚本生成的格子"上底图"**（纯模板模式专用，不依赖参照格子）。
--
--   真机症状（用户 16:51）：格子在树上 `visible=true`、位置尺寸都对，但画面上
--   **只有两条细边框**（`wall.up` / `wall.left`），看起来像"棋盘没出现"。
--   日志里 `face visible=false` ⇒ 底图是关的。
--
--   为什么关着：`_cells_stamp` 需要**参照格子**才能"照抄图片"；重建后是纯模板模式
--   （没有 `cell.1.1`）⇒ 那条路不执行 ⇒ 副本保留模板快照的状态（模板里 `face` 就是关的）。
--
--   ⇒ 这里自己来：打开 `face`、按格子几何铺满、塞一张底图（默认 106053 白色底）。
--     每一步都 pcall + 可选日志，失败也不会中断生成。
function Adapter:_cells_paint(ctrl, size, cell_id, img)
  if ctrl == nil then return false end
  -- ★★★★★ 2026-10-02 **必须用 `self:sub()`，不能用裸 `GetChild("face")`**。
  --
  --   真机日志自己写着：「ℹ️ 子控件装在中间容器 `content` 里（方案 A）—— 按路径查找」。
  --   也就是说 `face` **不是格子的直接子控件**，而是 `cell.content.face`。
  --   `GetChild("face")` 直接返回 nil ⇒ 我的第一版 `_cells_paint` 什么都没做、
  --   连日志都没打（因为提前 return 了）⇒ 17:05 / 17:24 两次都没生效。
  --   项目自己的 `sub()` 会依次尝试：直接子控件 → `content`/`root`/`body` → 深一层。
  local face = nil
  if cell_id ~= nil then
    pcall(function() face = self:sub(cell_id, "face") end)
  end
  if face == nil and ctrl.GetChild ~= nil then
    pcall(function() face = ctrl:GetChild("face") end)      -- 兜底：扁平配法
  end
  if face == nil then return false end
  if face.SetVisible then pcall(function() face:SetVisible(true) end) end


  -- ★★★★★ 2026-10-05 **每帧重放墙/门的可见性** ✗✓ —— 这是本轮的定案修法 ✓
  --
  --   真机日志给出的对照（同一份日志里 ✓）：
  --     · 「格子底图已点亮：25 个 face（**每帧保持**）」✓ —— ★ `face` 走的就是这条路 ✓
  --     · 而墙/门只在属性下发那趟设一次 ✗ ⇒ ★★ 被覆盖后**没人救**✗ ⇒ 看不见 ✓
  --     · 而那一刻读回 `wall.up(vis=true)` ✓ ⇒ ★★ 读回 true 与屏幕空白**同时成立** ✓✓
  --   ⇒ 在这里（每帧都会跑 ✓）把 `_apply_edges` 记下的意图重放一遍 ✓
  --   ⚠️ 只重放**已经记录过**的格子 ✗ —— 没下发过就什么都不做（不越权 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 性能待办 ★ 标签 **PERF-1**（★ 2026-10-06 标记 ✓ **先不动** ✗ 等框架稳定再回来 ✓）
  --
  --   ★ 用户 2026-10-06 指示：★「3 标记好字段位置，先不动，★ 等框架稳定了再回来弄」✓
  --
  --   ★ **三处字段（★ 改这里要一起看 ✓）**：
  --     · **记录**：`_apply_edges` 写 `self._edge_want[id][prefix.."."..side] = want`
  --       ⇒ ★ 本文件 **L3798~3800**（★ 另有一份同类写在 **L3775~3777** ✓）
  --     · **重放**：★ 就是下面 `for name, want in pairs(w)` 那段 ✓
  --       ⇒ ★ 每帧约 **200 次**「缓存查表 `self:sub` + `SetVisible`」✗
  --     · **触发**：`_cells_paint` 由 ★ **L2071** 每帧调用 ✓（★ 同一条路还负责点亮 `face` ✓）
  --     · **事件驱动那份**：★ 对称恢复分支 —— 本文件 **L4267** 读 `_edge_want` ✓
  --
  --   ★ 为什么当初要每帧重放 ✗：★ `hide_kids`（★ **L4230** ✓）会**递归藏子树** ✗
  --     且**只藏不显** ✗ ⇒ ★ 必须有东西**每帧把"该亮的"重新点亮** ✓
  --     ★ 否则真机症状：★「第一关的墙/门永远不画」✓（★ 那个 bug 的根因 ✓）
  --   ⇒ ★★ **要省成本，正确顺序** ✓：
  --     ★ ① 先确认 `L4267` 那条**对称恢复覆盖了所有 hide 路径** ✓
  --     ★ ② 再把这里从"每帧"改成"**脏标记驱动**" ✗
  --     ★ ③ ★ **不能直接删** ✗ —— ★ 删了会退回那个 bug ✓
  --   ★ 测量入口 ✓：`tests/grid_cost.lua`（13 项 ✓）· `tests/_wip/probe_*` 里那几条计数 ✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  if cell_id ~= nil and self._edge_want ~= nil then
    local w = self._edge_want[cell_id]
    if w ~= nil then
      for name, want in pairs(w) do
        local s2 = self:sub(cell_id, name)
        if s2 ~= nil and s2.SetVisible ~= nil then
          pcall(function() s2:SetVisible(want) end)
        end
      end
    end
  end
  -- 铺满格子（子控件默认可能比格子小，**甚至尺寸是 0** —— 两种都会让它"看不见"）
  --
  -- ★★★★★ 2026-10-04 **`size` 允许省略：不给就按控件自己的实际尺寸算。**
  --   为什么加这条：七个 `hex.*` 图标是**运行时按规划尺寸**建出来的，
  --   调用点手上没有"格子边长"这个量；但控件的 `sizeDelta` 就是答案。
  --   真机证据（17:02→17:31 两版对比）：同一条"深层设图"路径在 v044（纯图片模板）
  --   下图标是**看得见**的，换成格子模板后就看不见了 —— 差异正是**尺寸**：
  --   纯图片模板的图片子节点自带尺寸，格子模板的 `face` 默认尺寸是 0。
  if size == nil and ctrl.GetSizeDelta ~= nil then
    local w, h = nil, nil
    pcall(function() w, h = ctrl:GetSizeDelta() end)
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      size = math.min(w, h)
    end
  end
  if size ~= nil and face.SetSizeDelta then
    pcall(function() face:SetSizeDelta(size, size) end)
  end
  if face.SetAnchoredPosition then pcall(function() face:SetAnchoredPosition(0, 0) end) end
  -- 图片：第 4 个参数优先（七个图标各用各的素材），否则用格子的默认底图
  local use_img = img or (self.cfg.cells and self.cfg.cells.face_image) or 106053
  if face.SetImage then
    local ok = pcall(function() face:SetImage(nil, use_img) end)
    if not ok then pcall(function() face:SetImage(use_img) end) end      -- 两种签名都试
  end
  -- 读回，把结果说出来（否则又是"改了没生效"却看不出来）
  local vis, iid = "?", "?"
  pcall(function() vis = tostring(face.visible) end)
  pcall(function() iid = tostring(face.imageId) end)
  if self.cfg.cells and self.cfg.cells.debug_paint ~= false then
    self:warn_once("cells:paint",
      "格子底图已设置：face(visible=" .. vis .. ", imageId=" .. iid .. ")"
      .. "（如果画面上棋盘还是不出现，就把这行贴给我）")
  end
  return true
end

-- 把参照格子的 face 图片「盖章」到目标格子上。
-- 为什么要这一步：「另存为模板」存的是**当时的快照**。如果之后又给格子加了底图，
-- 用旧模板生成出来的副本会全是透明的（看起来像"没生成"）。
-- 图片控件的 imageSource / imageId 是只读可读的（API 文档 1427~1434），
-- SetImage(imageSource, imageId) 是写接口（1503），所以可以直接照抄。
function Adapter:_cells_stamp(target, ref)
  if target == nil or ref == nil then return false end
  if target.GetChild == nil or ref.GetChild == nil then return false end
  local my_face, ref_face
  pcall(function() my_face  = target:GetChild("face") end)
  pcall(function() ref_face = ref:GetChild("face") end)
  if my_face == nil or ref_face == nil then return false end
  if my_face.SetImage == nil then return false end

  local src, id, col
  pcall(function() src = ref_face.imageSource end)
  pcall(function() id  = ref_face.imageId end)
  if id == nil then return false end
  local ok = pcall(function() my_face:SetImage(src, id) end)
  pcall(function() col = ref_face.imageColor end)
  if col ~= nil then pcall(function() my_face.imageColor = col end) end
  return ok
end

-- 确保 board 下有全部 cell.<r>.<c>：编辑器里已摆好的不动，缺的按模板生成。
-- 返回"新建了几个"。没有配置 cfg.cells 时直接返回 0（不影响纯手摆的用法）。
-- ★★★★★ 2026-10-02 **用"脚本创建"重做选关按钮**（用户指定的另一条路线）。
--
--   为什么：真机证明**只有脚本创建的控件能收到点击** ——
--     关卡里的 25 个格子（脚本用 `game.InstantiateClientUIControl` 建）**能点**；
--     而编辑器里摆的 `select.card.*` / `select.back` **点了没反应**。
--   用户决定：**先用脚本创建把选关页做出来**，成功后再回头查"编辑器控件为什么不行"。
--
--   实现要点（照抄 `ensure_cells` 那条**已验证可行**的路）：
--     · 用**同一个模板索引** `cfg.cells.prefab`（真机验证过它能实例化）
--     · 父级挂在 **`board`** 下 —— 因为真机证明"`board` 下的脚本控件能收到点击"
--     · 改名 + **读回核对**（改名不生效会让 `find` 找不到，这个坑格子那轮踩过）
--     · 记进 `self.instantiated`（只有脚本生成的才允许销毁）
--
--   按钮 id：`selbtn.1` … `selbtn.N`（N = 关卡数，由调用方传）
function Adapter:ensure_widgets(count)
  count = count or 8
  if game == nil or game.InstantiateClientUIControl == nil then
    return 0, "环境没有 game.InstantiateClientUIControl"
  end
  -- ① 先建**容器**：容器模板来自 cfg.stage.prefab（用户 2026-10-02 给的 1073742330）
  local bar = self:find("selbar")
  if bar == nil then
    local cprefab = self.cfg.stage and self.cfg.stage.prefab
    if cprefab == nil then return 0, "没有 cfg.stage.prefab（没有容器模板）" end
    local cparent = self:find("stage")
    if cparent == nil then return 0, "找不到父容器 stage" end
    local ok, obj = pcall(game.InstantiateClientUIControl, cprefab, cparent)
    if not ok or obj == nil then
      return 0, "容器模板 " .. tostring(cprefab) .. " 实例化失败（它可能不是「客户端控件模板」）"
    end
    pcall(function() obj.name = "selbar" end)
    self.controls["selbar"] = obj
    self.instantiated = self.instantiated or {}
    self.instantiated["selbar"] = true
    bar = obj
  end
  -- ② 再在容器下建**按钮**（cell 模板 —— 真机验证过能实例化、能收到点击）
  local prefab = self.cfg.cells and self.cfg.cells.prefab
  if prefab == nil then return 0, "没有 cfg.cells.prefab（没有按钮模板）" end
  local made, existed = 0, 0
  for i = 1, count do
    local id = "selbtn." .. tostring(i)
    if self:find(id) ~= nil then
      existed = existed + 1
    else
      local ok, obj = pcall(game.InstantiateClientUIControl, prefab, bar)
      if ok and obj then
        pcall(function() obj.name = id end)
        local got = nil
        pcall(function() got = tostring(obj.name) end)
        if got ~= id then
          self:warn_once("selbtn:name:" .. id,
            "选关按钮改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。")
        end
        self.controls[id] = obj
        self.instantiated = self.instantiated or {}
        self.instantiated[id] = true
        made = made + 1
      end
    end
  end
  -- ★★★★★ 2026-10-03 **源头修 bug**：创建完 `selbar` 与 `selbtn.*` 后**立刻按当前屏幕设可见性**。
  --
  --   背景（真机 22:14 日志）：关卡界面里 `selbar`(1500x700) + 4 个 `selbtn.*` **一直可见**，
  --   压在棋盘第二行上；而 `selbtn` 绑的是 `pick_level` ⇒ 玩家点到就"返回选关"。
  --   我在 `main.lua` 的每帧同步里压过，但**压不住** ⇒ 说明源头（这里）每次开局都把它们
  --   设成可见，而且时机在我的同步之后 ⇒ 必须**在创建处**就设对。
  --
  --   ⚠️ 这里读不到 `Murdoku` 的 screen 状态（适配层不该依赖上层），
  --      所以用一个简单约定：**建好后一律先隐藏**；真正的显隐由 `main.lua` 的
  --      `apply_screen_hide` / 每帧同步按屏幕打开。若某处需要"建完就显示"，它会自己再打开。
  local hide_selbar = function(c)
    if c == nil then return end
    pcall(function() c:SetVisible(false) end)
  end
  if bar ~= nil then hide_selbar(bar) end
  for i = 1, count do
    local c = nil
    pcall(function() c = self:find("selbtn." .. tostring(i)) end)
    hide_selbar(c)
  end
  -- 诊断（每局一次）：把这三组的实际可见性读回来，方便真机核对
  if print then
    local rb = "?"
    pcall(function() rb = tostring(bar and bar.visible) end)
    local r1 = "?"
    pcall(function() local c = self:find("selbtn.1") if c then r1 = tostring(c.visible) end end)
    local rt = "?"
    pcall(function() local c = self:find("tpl-container") if c then rt = tostring(c.visible) end end)
    print("[murdoku] 选关条创建后已隐藏：selbar=" .. rb .. "  selbtn.1=" .. r1 .. "  tpl-container=" .. rt)
  end
  return made, nil, existed
end
function Adapter:ensure_cells(rows, cols)
  local g = self.cfg.cells
  if g == nil then return 0 end

  -- ★ 先把"实测结果"记成**失败**，后面任何一条成功路径再改写它。
  --
  -- 为什么在开头设：`ensure_cells` 有好几个早退分支（找不到父控件 / 没有 API /
  -- 没有索引 / 全部实例化失败），它们都是 `return 0`。若只在末尾的成功路径里写，
  -- 早退时 `self.cells_ok` 会停在 nil → `diagnose_template` 只能退回**猜**，
  -- 于是又会出现"生成失败了、体检却说可能是可用的"这种误导
  -- （2026-09-26 真机日志里就是这么被坑的）。
  self.cells_ok, self.cells_made, self.cells_total = false, 0, rows * cols
  -- 记下当前关卡的棋盘尺寸：逐格自检（diagnose_grid）要用它，
  -- 而且它比 cfg.cells.rows/cols 里那个"兜底值"准。
  self.cells_rows, self.cells_cols = rows, cols

  local parent = self:find(g.parent or "board")
  if parent == nil then
    self:warn_once("cells:parent",
      "生成格子失败：找不到父控件 " .. tostring(g.parent or "board"))
    self:_cells_report(5)
    return 0
  end

  -- ══════════════════════════════════════════════════════════════════════
  -- ★ 先把"占着格子名字的模板引用控件"请走
  --
  -- 真机 17:17 / 17:23 两张截图 + 日志：`cell.1.1` 的 `prefabIndex` **正好等于**
  -- `cfg.cells.prefab` —— 说明它**就是那个模板引用控件本身**，不是格子。
  -- 于是：
  --   · 它被算成"已存在" → missing 少 1 → **那一格永远不会被生成**；
  --   · 引用控件渲染不出格子副本 → 截图里 (1,1) 看着是空的（"第一个格子没造出来"）。
  --
  -- 用户提的解法方向对（"在那一格再生成一个覆盖它"），但**不能同名** ——
  -- 两个控件都叫 cell.1.1 的话 `find` 会取到编辑器那个，点击/渲染全打到错的对象上。
  -- 所以这里**先把它改名让位**，再由下面的循环在那一格**真的生成一个副本**。
  --
  -- ⚠️ 只改**编辑器里手摆的**（`self.instantiated` 里没有记录的），
  --    否则第二次调用（切关/重开）会把**脚本自己生成的**格子也改名重造，来回churn。
  -- ══════════════════════════════════════════════════════════════════════
  local moved = 0
  if type(g.prefab) == "number" and g.prefab > 0 then
    for r = 1, rows do
      for c = 1, cols do
        local id = self:cell_id(r, c)
        local ctrl = self:find(id)
        if ctrl ~= nil and not (self.instantiated and self.instantiated[id]) then
          -- 判定"它就是模板引用控件"：引用索引或自身索引命中配置的模板索引
          local hit = (self:_ref_index_of(ctrl) == g.prefab)
          if not hit then
            local p = nil
            pcall(function() p = ctrl.prefabIndex end)
            hit = (p == g.prefab)
          end
          if hit then
            local newname = "__tpl_ref_" .. id
            local ok = pcall(function() ctrl.name = newname end)
            if ok then
              self:drop_lookup(id)             -- 清掉旧名字的两半缓存，find 会重新走树
              self.controls[newname] = ctrl
              self:_park_control(ctrl)         -- ★ 挪出画布（不依赖 visible/active 语义）
              self:_note_parked(newname, ctrl) -- ★ 记账（按控件身份去重，进 N 次关也只记一次）
              moved = moved + 1
            end
          end
        end
      end
    end
  end
  if moved > 0 and print then
    print("[murdoku] 有 " .. moved .. " 个格子位置的控件其实是**模板引用控件本身**"
      .. "（索引 == cfg.cells.prefab）→ 已改名让位（__tpl_ref_*）并隐藏，"
      .. "脚本会在这些位置**真的生成格子副本**")
  end

  -- ★ 模板引用控件**不该出现在棋盘上**（它是"模板的引用"，不是格子）。
  --
  -- 为什么不只靠 `hide_unlisted`：那个函数只扫**受管容器的直接子控件**
  -- （MANAGED 列表里那 10 个）。真机截图显示 `tpl.cell` 仍然占着一个位置 ——
  -- 它可能不在受管容器的直接子层、或 `SetVisible` 对它没生效。这里**显式再藏一遍**，
  -- 按名字点名（`prefab_from` 里那些约定名 + 上面改名出来的 `__tpl_ref_*`）。
  do
    local hide_names = {}
    if type(g.prefab_from) == "table" then
      for i = 1, #g.prefab_from do hide_names[#hide_names + 1] = tostring(g.prefab_from[i]) end
    end
    -- 默认约定名（cfg.prefab_from 没配时也能生效）
    for _, n in ipairs({ "tpl.cell", "cell.tpl", "cell.prefab" }) do
      hide_names[#hide_names + 1] = n
    end
    local hid = 0
    for i = 1, #hide_names do
      local n = hide_names[i]
      if n ~= (g.probe or "cell.1.1") then          -- 别把真格子（参照格子）藏了
        local c = self:find(n)
        if c ~= nil then
          -- ★ 用 _park_control（挪出画布 + 缩 0 + 隐藏），不只用 SetVisible：
          --   真机截图证明 `tpl.cell` 仍然占着一个格子位置。
          if self:_park_control(c) then
            self:_note_parked(n, c)      -- ★ 记账（同一个控件进 N 次关也只登记一次）
            hid = hid + 1
          end
        end
      end
    end
    if hid > 0 and print then
      print("[murdoku] 已把 " .. hid .. " 个模板引用控件**挪出画布**"
        .. "（它们只是模板的引用，不该出现在棋盘上）")
    end
  end

  -- 先数一遍：**编辑器里已经摆好的格子根本不需要模板**。
  -- （旧实现无条件先要模板索引，导致「25 格都手摆好了」也直接 return，
  --   连摆正都不做 —— 2026-09-26 修。）
  --
  -- ★ 顺便记下"**生成前就存在**"的格子 —— 体检用它解释很容易看错的现象。
  local missing = 0
  self.cells_preexisting = {}
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      if self:find(id) == nil then
        missing = missing + 1
      else
        self.cells_preexisting[id] = true
      end
    end
  end

  if missing == 0 then
    -- 一格不缺 → 没生成也算"成功"，把这个实测结果记下来给体检用
    self.cells_ok = true
    self.cells_index = nil
    self.cells_made = 0
    self.cells_total = rows * cols
  end

  local prefab = nil
  local prefab_from = nil
  local tried = {}
  if missing > 0 then
    if game == nil or game.InstantiateClientUIControl == nil then
      self:_cells_report(4)          -- 没有那个 API
      return 0
    end
    -- ★ 候选 + **实测**：读到索引不算数，真的造得出一个才算数。
    --   基础模板（「预设按钮」那个 1073741848）读得到但实例化返回 nil，
    --   所以这里挨个试，第一个成功的就拿下 —— 你不需要抄任何数字。
    local cands = self:_cells_prefabs(g)
    if #cands == 0 then
      self:warn_once("cells:prefab",
        "缺 " .. missing .. " 个格子，但读不到任何控件模板索引。\n"
        .. "       两个办法任选：\n"
        .. "       ① 在编辑器里右键 cell.1.1 →【另存为模板】，"
        .. "再从那个模板**新建一个控件**放到 board 下、改名 `tpl.cell`（位置随意，脚本会藏起来）；\n"
        .. "       ② 照 docs/控件坐标表-1600x900.md 把格子手动摆齐（脚本就不再生成）。")
      self:_cells_report(1)          -- 读不到模板索引
      return 0
    end
    for i = 1, #cands do
      local c = cands[i]
      local ok, obj = pcall(game.InstantiateClientUIControl, c.index, parent)
      tried[#tried + 1] = tostring(c.index) .. "(" .. c.from .. ")"
      if ok and obj ~= nil then
        prefab, prefab_from = c.index, c.from
        -- ══════════════════════════════════════════════════════════════════
        -- ★★ 探针**用完立刻销毁，绝不复用**。
        --
        -- 曾经这里有个"聪明"的优化：既然为了验证索引已经造出来一个，那就别浪费，
        -- 直接把它改名成第一个缺的格子收下。
        --
        -- **真机 2026-09-26 18:13 的逐格自检证明这个优化是错的**：
        --   board 树上实际有 25 个子控件：tpl.cell cell.1.2 … cell.5.5
        --   ⚠️ 这些格子在树上根本找不到：**cell.1.1**
        -- 也就是——**循环里正常 Instantiate 出来的 24 个全都在树上**（尺寸 135×135、
        -- visible/active 都对），**唯独那个"试造"出来的没有**。
        -- 它虽然被改了名、也进了名字缓存（所以 `find` 找得到、计数说 25/25 齐全），
        -- 但**它不是 board 的子控件**，引擎不会画它、`GetChildren()` 也列不出它。
        --
        -- 教训：**引擎返回的对象未必已经挂到 parent 上** —— 至少"第一个/最早那个"
        -- 在真机上有这个差异。所以别对它做任何假设，验证完就销毁，让每个格子
        -- 都走**同一条**正常路径。
        -- ══════════════════════════════════════════════════════════════════
        if game.DestroyClientUIControl ~= nil then
          local dok = pcall(game.DestroyClientUIControl, obj)
          if print then
            print("[murdoku] 模板索引 " .. tostring(c.index) .. " 验证通过（试造成功），"
              .. "探针已" .. (dok and "销毁" or "**销毁失败**（不影响生成）")
              .. " —— 25 个格子都会走同一条正常路径")
          end
        end
        break
      end
    end
    if prefab == nil then
      self:warn_once("cells:inst",
        "有 " .. missing .. " 个格子还没建，试过 " .. #cands .. " 个模板索引"
        .. "（" .. table.concat(tried, "、") .. "）**全部实例化失败**（返回 nil）。\n"
        .. "       ⚠️ 注意：**右键「另存为模板」存出来的索引不算数**。\n"
        .. "       官方硬约束：除「客户端控件容器画布中的控件」和「**客户端控件模板**中的控件」外，\n"
        .. "       其他控件都是**服务器控件**，其模板索引**无法被客户端脚本调用**。\n"
        .. "       正确入口：界面控件组管理 → 界面控件组库 → **客户端控件模板**\n"
        .. "                 →【添加客户端控件】→ 加一个预设按钮、配好子控件 → **存为模板**\n"
        .. "       然后二选一：\n"
        .. "         ① 把该模板的「控件模板索引 ID」填进 cfg.cells.prefab（最稳，脚本会最先试它）；\n"
        .. "         ② 或把该模板放进容器画布、改名 tpl.cell（脚本会扫到它的索引）。")
      self:_cells_report(1)
      return 0
    end
    if print then
      print("[murdoku] 格子模板索引 " .. tostring(prefab)
        .. "（来自 " .. tostring(prefab_from) .. "）可用；缺 " .. missing .. " 个格子，开始补建")
    end
  end

  local first_err = nil
  local made = 0
  local ref = self:find(g.probe or "cell.1.1")   -- 参照格子：章它的图片
  if ref == nil and made > 0 then
    -- 纯模板模式下没有参照格子，`_cells_stamp` 这条"补图"保险就失效了 ——
    -- 生成的格子会**完全依赖模板快照里的美术**。这件事必须说出来：
    -- 否则以后副本透明，会不知道是"没生成"还是"生成时模板就没配图"。
    self:warn_once("cells:noref",
      "没有参照格子（" .. tostring(g.probe or "cell.1.1") .. "），"
      .. "所以**不做图片盖章** —— 生成的格子外观**完全取自模板快照**。\n"
      .. "       这是纯模板模式的正常代价。如果副本看不见，去模板里补底图后**重存一次模板**。")
  end
  local n = math.max(rows, cols)
  local cell_size = self:cell_geometry(n)
  -- ★ 图层顺序那一趟的实测账：排过几个格子、一共排上几个子控件（见 1889 行附近的说明）。
  local layer_cells, layer_subs = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = self:find(id)
      if ctrl == nil then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = id end)
          -- ★ 改完名要**读回来核对**。
          --   18:13 那次就是"改了名 + 进了名字缓存"骗过了所有检查（find 找得到、
          --   计数 25/25 齐全），可树上其实没有它。所以这里显式读回一次，
          --   不一致就记一笔 —— 这样下次出问题在日志里立刻能看见。
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= id then
            self:warn_once("cells:name:" .. id,
              "改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。\n"
              .. "       这个副本会**找不到**（也会挡住后面的同名格子），记下这一条备用。")
          end
          self.controls[id] = obj
          -- 同上面的"试造"：记下来这是我们生成的（改名让位那段靠它区分）
          self.instantiated = self.instantiated or {}
          self.instantiated[id] = true
          ctrl = obj
          made = made + 1
          self:_cells_stamp(ctrl, ref)     -- ★ 把参照格子的图片盖上去
          -- ★★★★★ 2026-10-02 **纯模板模式下必须自己给格子上底图** —— 这就是
          --   "棋盘没出现 / 只有一行一列"的真正原因。
          --
          --   真机日志（用户 16:51）：
          --       cell.1.1  visible=true  位置=(-237,237) 124x124    ← 格子本身可见
          --         face      visible=**false**  imageType=Stretch  imageId=106053
          --         wall.up   visible=true     ← 只有这两条边框是亮的
          --         wall.left visible=true
          --   ⇒ 格子"存在且可见"，但**底图 `face` 是关的** ⇒ 画面上只有两条细边框。
          --
          --   根因：`_cells_stamp` 只在**有参照格子**（`cell.1.1`）时才能"盖章"，
          --   而重建后是**纯模板模式**（没有参照格子）⇒ 整条补图路径不执行 ⇒
          --   副本的 `face` 保持"模板快照里的状态"（模板里它就是关的）。
          --
          --   ⇒ 所以这里**不依赖参照格子**，直接自己打开 `face` 并塞一张底图。
          --     图片 id 取 `cfg.cells.face_image`（默认 106053 —— 项目里已知的白色底），
          --     尺寸用格子自己算好的几何，保证铺满。
          self:_cells_paint(ctrl, cell_size, id)
        elseif first_err == nil then
          first_err = tostring(obj)
        end
      elseif g.stamp_existing == true then
        self:_cells_stamp(ctrl, ref)       -- 连编辑器里已摆的也一起盖章
      end

      -- force_position ~= false 时，把每个格子的锚点/中心/尺寸/位置都摆正。
      -- 这样棋盘永远是对的，不依赖编辑器里那个「位置」填得准不准，
      -- 也不再依赖 cfg 里的固定尺寸 —— 5×5 / 6×6 共用同一套编辑器控件。
      if ctrl ~= nil and g.force_position ~= false then
        -- ★ 先把中间容器的「屏蔽区域内点击事件穿透」关掉 ——
        --   否则点击到不了按钮，表现为"点格子没反应"而体检全绿。
        self:open_click_passthrough(id)
        -- ★ 再把图层顺序排定 —— 官方 `SetSiblingIndex`「数值越大越靠上」。
        --   用户提醒：层级**按模板里的位置**决定、不看生成顺序，且会互相覆盖，
        --   所以必须规划 + 显式排一遍（`cfg.cells.layer_order`，从下到上）。
        --
        -- ★★★★★ 2026-10-05 **返回值现在不当废物丢掉了**：它 = 这个格子里**真的排上了
        --   几个子控件**（`SetAsFirstSibling` 成功次数）。以前 `self:enforce_layers(id)`
        --   的结果没人看，于是"层序到底排没排上"在日志里**一个字都没有** ——
        --   而"白色 face 压住墙"（层序问题）和"墙根本没设"（属性问题）在画面上**长得一模一样**。
        --     · 每格 ≈ `#layer_order` ⇒ 层序确实排过；
        --     · =0 ⇒ 这个格子里**没有任何** `layer_order` 里的子控件名（模板没配/名字不同）
        --             ⇒ 层序**完全没动过**，遮挡就出在这里。
        --   累加后在关卡末尾**打一行**（放循环里会刷 25 行）。
        local n_layer = self:enforce_layers(id)
        layer_cells = layer_cells + 1
        layer_subs = layer_subs + (tonumber(n_layer) or 0)
        if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
        if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
        if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
        if ctrl.SetSizeDelta then
          pcall(function() ctrl:SetSizeDelta(cell_size, cell_size) end)
        end
        local x, y = self:cell_offset(r, c, n)
        if ctrl.SetAnchoredPosition and x ~= nil then
          pcall(function() ctrl:SetAnchoredPosition(x, y) end)
        end
        -- 格子里的 face/note/x 跟着格子一起缩放
        local kids = { "face", "x" }
        for i = 1, #kids do
          local k = self:sub(id, kids[i])
          if k ~= nil then
            if k.SetSizeDelta then pcall(function() k:SetSizeDelta(cell_size, cell_size) end) end
            if k.SetAnchoredPosition then pcall(function() k:SetAnchoredPosition(0, 0) end) end
            if k.SetPivot then pcall(function() k:SetPivot(0.5, 0.5) end) end
          end
        end
        local note = self:sub(id, "note")
        -- ★★★★★ 2026-10-07 **这里就是"谁把 note 改成 100×30"的元凶** ✗✓（用户怀疑对了 ✓）
    --   ★ 原式：`math.max(8, cell_size - 8)` × `math.max(8, math.floor(cell_size * 0.28))`
    --     ⇒ ★ `cell_size = 108` ⇒ **100 × 30** ✓✓ —— ★ 与真机探针读到的 `100.0x30.0` 一字不差 ✓
    --   ★ 而 24 号字的**行高 ≈ 36** ⇒ ★ **30 高装不下一行 ⇒ 整行被裁 ⇒ 一个字都不画** ✓
    --     ⇒ ★ 这就是"编辑器改了也不生效、字母时有时无"的**真正机制** ✓（★ 不是引擎默认 ✓）
    --   ★ 现在：★ 高改成 `max(40, cell_size × 0.40)` ⇒ ★ `108` 时 = **43** ✓ 一行稳稳装下 ✓
    if note ~= nil and note.SetSizeDelta then
          pcall(function() note:SetSizeDelta(math.max(8, cell_size - 8), math.max(40, math.floor(cell_size * 0.40))) end)
          if note.SetAnchoredPosition then pcall(function() note:SetAnchoredPosition(0, 0) end) end
        end
      end
    end
  end

  if made == 0 and first_err ~= nil then    -- ★ 2026-09-26 真机实测：`cell.1.1.prefabIndex` 返回的往往是**「预设按钮」这个基础
    --   控件的索引**（这台机器上是 1073741848），拿它去 InstantiateClientUIControl
    --   会**返回 nil**（不报错，静默失败）—— 基础模板不允许这样实例化。
    --   所以这里要把"下一步做什么"讲清楚，否则只会看到一句没头没脑的 nil。
    self:warn_once("cells:inst",
      "有 " .. missing .. " 个格子还没建，想自动生成但失败了"
      .. "（模板索引 " .. tostring(prefab) .. "，接口返回 " .. first_err .. "）。\n"
      .. "       这通常是因为那个索引**不是客户端控件模板**，不能直接实例化。正确做法：\n"
      .. "       ① 界面控件组管理 → 界面控件组库 → **客户端控件模板** →【添加客户端控件】\n"
      .. "          → 加一个预设按钮、配好子控件 → **存为模板**；\n"
      .. "       ② **关键一步**：在容器画布里新建一个「**模板引用控件**」去**引用**那张模板\n"
      .. "          （**不能**用模板直接新建控件，那不算）；\n"
      .. "       ③ 把它的 `referencedPrefabIndex`（不是 `prefabIndex`！）填进\n"
      .. "          lua/entry_client_script.lua 的 cfg.cells.prefab，重新打包同步。\n"
      .. "       （也可以照 docs/控件坐标表-1600x900.md 把格子手动摆齐，脚本就不再生成。）")
    self:_cells_signal(100)        -- Instantiate 失败 → 100
  elseif g.debug_signal ~= false then
    -- ★ 无条件回报"到底建了几个"：边长 = 40 + made*8
    --   made=0  → 40（很小）        → 循环一次都没创建
    --   made=24 → 232（明显变大）   → 24 个都建了（若还看不见，就是副本没外观）
    if not self:_cells_signal(40 + made * 8) then
      self:warn_once("cells:signal", "诊断信号写入失败：一个可改尺寸的控件都没找到")
    end
  end
  -- ★ 唯一可靠的「到底成了没有」信号。
  --   副本可能因为**模板快照里没配美术**而完全透明 —— 光看画面根本分不出
  --   "没生成" 和 "生成了但看不见"。所以把实际存在数打进日志，一眼可判。
  if print then
    local have = 0
    for r = 1, rows do
      for c = 1, cols do
        if self:find(self:cell_id(r, c)) ~= nil then have = have + 1 end
      end
    end
    print("[murdoku] 棋盘格子：" .. have .. " / " .. (rows * cols) .. " 存在"
      .. "（本次新建 " .. made .. " 个，模板索引 " .. tostring(prefab) .. "）")
    -- 把**实测结果**存下来给 diagnose_template 用 —— 它必须报实际结果，
    -- 不能靠"索引看起来不同"猜（真机 16:07 就是这么被误导的）。
    self.cells_ok = (have >= rows * cols)
    self.cells_index = prefab
    self.cells_made = made
    self.cells_total = rows * cols
  end

  -- ★★★★★ 2026-10-05 **格子重建之后，必须清掉 `subs` 里的死句柄** ✗✓
  --
  --   这是"第一次进关墙/门不画、进别的关再回来就正常"的**真凶** ✓
  --   （★ 与素材无关 ✗ —— 素材是静态的，不会因为切一次关而变 ✓
  --     这条判据用户提过，我一度绕回素材，是错的 ✓）
  --
  --   机制（`Adapter:sub` 在 L502-504 ✓）：
  --     · 缓存键是 `parent_id .. "." .. child_name` ✓ —— ★ 键里有格子 id ✓
  --       ⇒ ★ 不跨格串号 ✓（这条先排除掉 ✓）
  --     · 但 `if cached ~= nil and cached ~= false then return cached end` ✗
  --       ⇒ ★★ **命中就永远返回旧句柄，从不失效、从不重查** ✗✓
  --     · 而 `ensure_widgets` 每次进关都会**把 25 个格子重新建一遍** ✗
  --       （真机日志：「本次新建 25 个」✓）
  --       ⇒ ★★ 旧格子对象已被销毁 ✗ 而 `self.subs` 里【还存着它们的子控件句柄】✓✓
  --       ⇒ ★★★ `SetVisible(true)` 调在死句柄上 ⇒ **静默 no-op** ⇒ 屏幕上不画 ✓
  --
  --   ★★ 这也解释了那个一直对不上的矛盾 ✓：
  --     · 我读回的 `sub.visible` = **true** ✗
  --       ⇒ ★ 因为我读的是**缓存里那个旧对象**的属性 ✓✓
  --       ⇒ ★★ "读回 true 但屏幕没有" 到此闭环 ✓
  --     · 而「进别的关再回来就正常」✓
  --       ⇒ ★ 因为那一趟 `find` 把键重新命中到**新建后的**子控件上 ✓
  --
  --   ★ 为什么在"重建完"这里清、而不是在 `sub` 里验活句柄 ✗：
  --     验活要每帧多一次探测 ✗ —— 移动端不划算 ✓
  --     建格是【每关一次】✓ 这里清 = 零常态开销 ✓
  do
    local cleared = 0
    for k in pairs(self.subs) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then
        self.subs[k] = nil
        cleared = cleared + 1
      end
    end
  end

  -- ★★★★★ 2026-10-05 **图层顺序这一趟的实测结果 —— 每关一行**。
  --
  --   为什么必须打：`enforce_layers` 的返回值（= 真的排上了几个子控件）以前**被直接丢掉**，
  --   于是"层序到底动没动过"在日志里一个字都没有。而真机上"墙没画出来"有两个长得
  --   一模一样的成因：① 属性没送达；② 送达到了但**被上面的白色 face 盖住**（层序）。
  --   这一行 + 上面那两行"兄弟索引"合起来才能把 ① 和 ② 分开。
  --
  --   判读：
  --     · 每格 ≈ `#layer_order`（默认 12）⇒ 层序确实排过，遮挡不在这一步；
  --     · 平均 = 0 ⇒ 每个格子里都**没有任何** `layer_order` 里的子控件名
  --         ⇒ 层序**完全没动过**（`face` 就可能压在 `wall.*` 上面）；
  --     · 格子数 = 0 ⇒ 这一趟**根本没跑**（`cfg.cells.force_position = false`）。
  if print then
    if layer_cells == 0 then
      print("[murdoku] 图层顺序：本次进关**没有排过层序**（cfg.cells.force_position=false，"
        .. "或者这一关一个格子都没有）")
    elseif layer_subs == 0 then
      print("[murdoku] 图层顺序：对 " .. layer_cells .. " 个格子排过层序，"
        .. "但**一个子控件都没排上**（layer_order 里的名字一个都取不到）"
        .. " ⇒ 层序等于没动过，「白色 face 压住墙」这类遮挡就会长这样")
    else
      print(string.format("[murdoku] 图层顺序：对 %d 个格子排过层序，子控件成功置底 %d 个（平均 %.1f/格）",
        layer_cells, layer_subs, layer_subs / layer_cells))
    end
  end
  return made
end

-- 「把用不到的控件藏起来」。
--
-- 为什么必须在**适配层**做，而不是在界面层按 layout_plan 做：
--   编辑器里的控件是照着**所有关卡的最大并集**建的（6×6 关卡要 36 个格子、
--   角色多的一关要 tray.F），而界面层运行时只知道**当前这一关**的布局，
--   它压根不知道还有 cell.6.6 / clue.12 这些东西存在 —— 于是那些控件会一直
--   显示着别的关卡残留的文案和空格子。
--   所以这里直接在控件树上扫：**容器 → 直接子控件**，名字不在 keep 里的就藏。
--
-- 只扫一层是刻意的：face / note / x / text / bg 这些子控件在更深一层，
-- 它们不是界面层排布的，不能被误伤。
-- ★★★★★ 2026-10-02 **真机"点不动"的根因就在这里**：名单漏了 `home` / `select`。
--
--   引擎的点击派发条件是（见下面 `enable_cursor` 的注释）：
--     for i = t; i; i = i.parent do
--       if i.kind == "container" and i.showCursor then return true end
--     end
--   —— 一个控件要收到点击，**祖先链上必须有一个 kind=="container" 且 showCursor==true 的容器**。
--
--   脚本靠这份 `MANAGED` 名单去开那个开关（真机日志：`已由脚本打开 9 个容器的显示常驻光标`）。
--   而 **`home` / `select` 不在名单里** ⇒ 它们的子控件（主页四键 / 选关卡片 / 返回键）
--   全部落在门控②之外 ⇒ **点不动**。
--   这也解释了那个一直没解释的不对称：`home.*` 在主页能点（`root` 那条链当时是通的），
--   一切到选关就全废。
--
--   ⚠️ 这是本项目反复吃亏的"**门控②**"（docs/环境问题-诊断记录.md）：
--      加一个新容器就**必须**同步加进这份名单 —— 我加 `home`/`select` 时漏了。
-- ★★★★★ 2026-10-08 **内层装饰控件一律不参与 `hide_unlisted`**（★ 从提交 295 删掉的原文照抄恢复 ✓）
--   ★ 真机症状（用户实测 ✓）：★ **弹窗四键空壳但可点** ✓ ★ **`clues` 头像卡 208 起就没显示过** ✓
--   ★ 机制 ✓：★ `hide_unlisted` 遍历 `MANAGED`，把"不在计划里的直接子控件"逐个隐藏 ✗ ——
--     ★ 而计划里只有**外层**名字（`clues.bg` / `tray.A` / `modal.exit`…）⇒
--     ★ **内层装饰名**（`face` `backrop1` `badge` `letter` `what` `who`…）**永远不在计划里** ✗
--     ⇒ ★ 每次都被当成"多余的旧控件"藏掉 ⇒ ★ 用户看到的就是"图片被藏住了" ✓✓
--   ★ 规则 ✓：★ **这些内层名字一律跳过**（★ 它们的主人=父控件，显隐由父控件/状态决定 ✓）
--     ★ 以后加新控件若用了别的内层名 ⇒ **一并加到这里** ✓
local DECOR = {
  label = true, bg = true, pic = true, icon = true,
  face = true, note = true, x = true, obj = true, text = true, portrait = true,
  backrop1 = true, backrop2 = true, badge = true, letter = true, what = true, who = true,
  frame = true, card = true, art = true, image = true, img = true,
}

local MANAGED = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal", "intro",
}

-- ★ 只有"开常驻光标"这件事需要额外覆盖 `home` / `select`。
--   `hide_unlisted` 用的是上面那份 MANAGED，语义不同，**不要混用**。
--   （第一版我直接加进 MANAGED，play_test 立刻从 3 红变 4 红。）
--   两份名单**分开**：MANAGED = "脚本托管的关卡内容器"；
--   CURSOR_CONTAINERS = "需要打开「显示常驻光标」的容器"（**必须包含每个屏幕容器**）。
local CURSOR_CONTAINERS = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal", "intro",
  "home", "select",
}

function Adapter:hide_unlisted(keep)
  local hidden = 0
  for i = 1, #MANAGED do
    local parent = self:find(MANAGED[i])
    if parent ~= nil and parent.GetChildren ~= nil then
      local ok, kids = pcall(function() return parent:GetChildren() end)
      if ok and type(kids) == "table" then
        for k = 1, #kids do
          local child = kids[k]
          local name = nil
          pcall(function() name = child.name end)
          if name ~= nil and name ~= "" and not keep[name] and not DECOR[name] then
            if child.SetVisible ~= nil then
              local ok2 = pcall(function() child:SetVisible(false) end)
              if ok2 then hidden = hidden + 1 end
            end
          end
        end
      end
    end
  end
  return hidden
end

-- ════════════════════════════════════════════════════════════════════════
-- 头像卡归一化（只负责「应用」，几何由 ui_controller 算）
--
-- 为什么需要：头像卡的**列数按人数自适应**（保证永远只占 2 行，见 ui_controller），
-- 于是 5 人关是 3 列、7 人关是 4 列 —— 同一张 `tray.A` 在不同关卡里
-- **位置和尺寸都不一样**。但编辑器每个控件只能有一套几何，
-- 所有关卡共用一张界面布局。
--
-- 解决办法和棋盘格子一样：**编辑器按"最挤的情况"静态摆好，运行时由脚本按
-- 本关实际人数重新摆正**，一套布局通吃 5/6/7/8 人。
--
-- layout 由 `Controller:tray_layout_canvas()` 给出（画布绝对坐标），
-- 这里换算成「相对父级中心的偏移」（官方嵌套控件语义）再写下去。
-- ════════════════════════════════════════════════════════════════════════

-- ★★ 2026-09-28：**样式的缩放值只在这里定义一处**。
--
--   起因：用户报"已放置头像卡没有变小（0.72）"。查下来是 `style` 分支设了缩放，
--   但 `apply_tray_layout`（头像卡重排）随后把姿态重置了 ⇒ **设了又被覆盖**。
--   这和本工程里反复出现的"同一件事两处实现"是同一类问题
--   （前面吃过：`erases` 动效、运行时上色 vs 存档静态图、自动 ✗ 的三处还原）。
--   ⇒ 这次直接把缩放表抽成一个函数，**style 分支和重排函数都调它**，从根上不可能不一致。
function Adapter:scale_of_style(value)
  if value == "portrait" then return 0.86            -- 默认：比选中略小
  elseif value == "portrait.selected" then return 1.08
  elseif value == "portrait.placed" then return 0.72  -- 已放置：最小
  elseif value == "clue.focus" then return 1.03
  elseif value == "tab.active" then return 1.04 end
  return nil
end

-- ★★★ 2026-09-30：**样式的文字颜色也只在这里定义一处**（和 `scale_of_style` 同一套路）。
--
--   用途：参考《派蒙的执律庭实习》的线索卡 —— **人名/关键字是红色**、正文是白色。
--   官方**没有富文本**（查过 API 缓存），也没有文字宽度测量 ⇒ 一行里没法给某几个字换色，
--   只能"拆成两个控件"（`lua/ui_controller.lua` 的线索卡就是这么做的：
--   名字占固定宽度的第一列，正文从固定 x 起）。
--
--   ⚠️ 颜色是 **32 位整数**（真机日志 `fontColor=4294967295`），**没有 `Color()` 全局函数**
--   —— 所以这里直接写整数字面量。
--   ⚠️ `RED` 用的是**真机实测过的那个红**（就是 ✗ 标记用的 `4290453793`），
--   不自己调一个新色 —— 免得又变成"只在模拟器里好看"。
function Adapter:color_of_style(value)
  local WHITE = 4294967295            -- 0xFFFFFFFF：不透明白
  local RED   = 4290453793            -- 真机实测红（✗ 标记同款素材色）
  if value == "clue.who" then return RED end
  if value == "clue.what" or value == "clue" or value == "clue.ok" or value == "clue.focus" then
    return WHITE
  end
  return nil                          -- 其它样式不管颜色（保住各自现状）
end
-- 「按钮底图上色（运行时）」—— **顶层 helper**，由 `apply_tray_layout` 在末尾调用。
--
-- ⚠️ 2026-10-05 Round 45：它原来是 `apply_tray_layout` 函数体末尾的一整段循环。
--   为什么非搬出来不可：那段用 `names` / `done, miss`（`apply_tray_layout` 的局部变量），
--   而**两个本该顶层的方法**（`apply_ruler_layout` / `diagnose_overlap`）又必须在
--   `apply_tray_layout` **外面** ⇒ 只有把这段移出去，才可能让 `apply_tray_layout`
--   在方法**之前** `end` 掉 ⇒ 那两个方法才会在**加载时**就存在 ✓
--   （不搬的后果就是本 bug：方法被吞成子闭包 ⇒ `main.lua` 的 `~= nil` 守卫恒假
--     ⇒ 行标/列标对齐、相交诊断**从来没跑过**、零报错 ✗）
--
-- 等价性（与搬移前逐条对齐）：
--   · 同一段代码、同样顺序、同样计数、同样 `pcall` 兜底；
--   · 仍然只在 `cfg.btn_art == true` 时执行（由调用点判断，与搬移前的 `if` 一致 ✓）；
--   · 返回值与原来一致：`moved`（搬移前 `apply_tray_layout` 返回的就是搬移后的 `moved` ✓）；
--   · `names` / `done, miss` 改成**参数传入** —— 它们原来就在同一作用域，
--     直接传进来即可，**不读全局**（不传会 `#nil` 抛错 ✗）。
function Adapter:_tray_btn_art(moved, names, done, miss)
  names = names or {}
  done, miss = done or 0, miss or 0
  print("[murdoku] --- 按钮底图上色（运行时）---")
  for i = 1, #names do
    local cid = names[i]
    local c = self:find(cid)
    local bg = nil
    if c ~= nil then pcall(function() bg = self:sub(cid, "bg") end) end
    if bg ~= nil then
      if bg.SetAsLastSibling then pcall(function() bg:SetAsLastSibling() end) end
      local src = nil
      pcall(function() src = bg.imageSource end)
      -- ⚠️ 这个色号必须和**写进 .gil 的那个**一致！
      --   踩过的坑：我在 .gil 里把底图改成了浅蓝 100108，
      --   却忘了改这里硬编码的 100001 —— 于是**运行时又把它覆盖回深紫**。
      --   模拟器验证（tools/sim/verify_art.mjs）一眼看出来：`bg imageId=100001`。
      --   ⇒ 同一件事有两处实现，就必须同时改；这次靠"交付前验证外观"兜住了。
      local ok, err = pcall(function() bg:SetImage(src, self.cfg.bg_image_id or 100108) end)
      if ok then done = done + 1 else
        miss = miss + 1
        self:warn_once("bgset:" .. cid, "底图 SetImage 失败：" .. tostring(err))
      end
      if bg.SetVisible then pcall(function() bg:SetVisible(true) end) end
      if i <= 3 then
        local it, iid = "?", "?"
        pcall(function() it = tostring(bg.imageType) end)
        pcall(function() iid = tostring(bg.imageId) end)
        print(string.format("  %-16s bg：imageType=%s imageId=%s", cid, it, iid))
      end
      moved = moved + 1
    else
      miss = miss + 1
    end
  end
  print(string.format("  SetImage 成功 %d 个，缺失/失败 %d 个", done, miss))
  print("[murdoku] --- 按钮底图上色结束 ---")
  return moved
end

function Adapter:apply_tray_layout(layout)
  if layout == nil or layout.items == nil then return 0 end
  local parent = self:find(self.cfg.tray_parent or "tray")
  if parent == nil then
    self:warn_once("tray:parent", "找不到头像卡容器（cfg.tray_parent，默认 tray）")
    return 0
  end
  local moved = 0
  for i = 1, #layout.items do
    local it = layout.items[i]
    local ctrl = self:find(it.id)
    if ctrl ~= nil then
      local ox = it.cx - layout.tray_cx
      local oy = it.cy - layout.tray_cy
      if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
      if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
      if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
      if ctrl.SetSizeDelta then pcall(function() ctrl:SetSizeDelta(it.w, it.h) end) end
      if ctrl.SetAnchoredPosition then pcall(function() ctrl:SetAnchoredPosition(ox, oy) end) end
      -- ★★ 2026-09-28：**重排后必须把样式缩放重新施加一遍**。
      --
      --   这一行就是"已放置头像卡没变小"的修复点：
      --   原来 `style` 分支设了 0.72，但重排的 `SetSizeDelta`/`SetAnchoredPosition`
      --   会把姿态重置回 1.0，而重排发生在其后 ⇒ 玩家永远看不到那一档。
      --   缩放值取自 `scale_of_style`（与 style 分支**同一处定义**，不可能不一致）。
      local sty = self._style and self._style[it.id] or nil
      local sc2 = sty ~= nil and self:scale_of_style(sty) or nil
      if sc2 ~= nil and ctrl.SetLocalScale ~= nil then
        pcall(function() ctrl:SetLocalScale(sc2, sc2, 1) end)
      end
      -- 卡片里的 face / text 跟着一起变
      local kids = { "face", "text" }
      for k = 1, #kids do
        local sub = self:sub(it.id, kids[k])
        if sub ~= nil then
          if sub.SetSizeDelta then pcall(function() sub:SetSizeDelta(it.w, it.h) end) end
          if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(0, 0) end) end
          if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
        end
      end
      moved = moved + 1
    end
  end

  -- ★ 头像卡体检（2026-09-27 新增）。
  --
  -- 为什么需要：用户问"tray 里的图我是不是也得补"。而按已真机确认的规则 ——
  --   **预设按钮只渲染"四个状态节点引用的"子控件**，未被引用的子控件**不显示**。
  --   用户往 tray.D 加了一个图片子控件，但**没动状态节点**，所以到底显不显示只有真机能答。
  -- 这条诊断把每张卡的"子控件清单 + visible + imageType + imageId"打出来：
  --   · 子控件**不在清单里** → 加子控件这步没生效（或没存进关卡）
  --   · 在清单里但 **visible=false** → 被脚本藏了
  --   · visible=true 但 imageId=nil → 没配图
  --   · 全都正常却看不见 → **就是状态节点没引用**（这条规则得到验证）
  if self.cfg.tray_diag ~= false and print then
    local names = { "A", "B", "C", "D", "E", "F", "V" }
    print("[murdoku] --- 头像卡体检（每张卡的子控件）---")
    for i = 1, #names do
      local cid = (self.cfg.tray_parent or "tray") .. "." .. names[i]
      local c = self:find(cid)
      if c ~= nil then
        local kids = nil
        pcall(function() if c.GetChildren then kids = c:GetChildren() end end)
        local n = (type(kids) == "table") and #kids or 0
        local parts = {}
        for k = 1, n do
          local kk = kids[k]
          local kn, kv, kt, ki = "?", "?", "?", "?"
          pcall(function() kn = tostring(kk.name) end)
          pcall(function() kv = tostring(kk.visible) end)
          pcall(function() kt = tostring(kk.imageType) end)
          pcall(function() ki = tostring(kk.imageId) end)
          parts[#parts + 1] = kn .. "(visible=" .. kv .. " type=" .. kt .. " id=" .. ki .. ")"
        end
        print(string.format("  %-9s 子控件 %d 个  %s", cid, n,
          (#parts > 0) and table.concat(parts, "  ") or "**（没有子控件）**"))
      else
        print(string.format("  %-9s **找不到这个控件**", cid))
      end
    end
    -- ★ 2026-09-28 扩展：**原来只查 7 张头像卡，按钮一个都没查** ——
    --   于是"按钮到底有没有子控件"在真机上完全看不出来，只能靠猜。
    --   按同一套判读法再查一批代表性按钮。
    local btns = { "tool.place", "tool.x", "tool.eraser", "action.submit", "action.undo",
                   "intro.next", "modal.suspect.A" }
    for i = 1, #btns do
      local cid = btns[i]
      local c = self:find(cid)
      if c ~= nil then
        local kids = nil
        pcall(function() if c.GetChildren then kids = c:GetChildren() end end)
        local n = (type(kids) == "table") and #kids or 0
        local parts = {}
        for k = 1, n do
          local kk = kids[k]
          local kn, kv, kt, ki = "?", "?", "?", "?"
          pcall(function() kn = tostring(kk.name) end)
          pcall(function() kv = tostring(kk.visible) end)
          pcall(function() kt = tostring(kk.imageType) end)
          pcall(function() ki = tostring(kk.imageId) end)
          parts[#parts + 1] = kn .. "(visible=" .. kv .. " type=" .. kt .. " id=" .. ki .. ")"
        end
        print(string.format("  %-18s 子控件 %d 个  %s", cid, n,
          (#parts > 0) and table.concat(parts, "  ") or "**（无子控件 → 完全透明看不见）**"))
      else
        print(string.format("  %-18s **找不到**", cid))
      end
    end
    print("[murdoku] --- 体检结束 ---")
  end
  -- ★★ 2026-09-28 新增：**运行时给按钮底图上色 + 提到最上层**。
  --
  -- 为什么必须走运行时：真机日志显示 `bg(visible=true type=Stretch id=100001)` ——
  --   存档里图片 ID **确实改成 100001 了**，但屏幕上**还是白块**。
  --   推断：那些白块是**按钮状态节点自带的白色底板**，盖在我的 `bg` 上面。
  --   ⇒ 两手一起上：
  --     ① 运行时 `SetImage`（这是已被证明能改图的路径）把底图设成有颜色的素材；
  --     ② `bg:SetAsLastSibling()` 把它提到最上层，压住状态节点那块白板。
  -- ★★ 2026-09-28：**改成默认关闭（opt-in）**。
    --
    -- 为什么：`.gil` 里每个按钮的 `bg` 已经带好了正确的 (source, id) 对
    --   （真机读出来 `src=4281536672 id=100108`，和棋盘上的浅蓝横墙一模一样）。
    --   而运行时再 `SetImage(bg.imageSource, 100108)` 反而把它**覆盖成了紫色** ——
    --   说明运行时读到的 `imageSource` 和我写进存档的**不是同一个值**，配错了图集。
    --   ⇒ 既然静态图已经对，就不该再动它。**同一件事有两处实现，就会有两处不一致** ——
    --     这一课我这个项目里已经吃了两次（另一次是 `erases` 动效）。
    --   想再实验运行时上色时，传 `cfg.btn_art = true` 打开。
    if self.cfg.btn_art == true and print then
    -- ⚠️ 名单**不能手写**！第一版我手写了 19 个，而实际有 35 个按钮 → 那 16 个
    --    （`action.q.*`、`modal.level.*` …）**从没被验证过**
    --    （真机日志 `SetImage 成功 19 个` 暴露的）。
    --    改成由调用方传入（`main.lua` 从规划里取 `kind == "button"`），有多少算多少。
    --
    -- ★★★★★ 2026-10-05 **这两个 local 必须提到这里**（Round 35 的结构性修复，最后一步）。
    --   原因：它们被**两个地方**用 —— 本 `btn_art` 块（函数末尾的上色循环，
    --   见下面 `--- 按钮底图上色（运行时）---` 那段），以及**两个彻底独立的功能**
    --   （`apply_ruler_layout` / `diagnose_overlap`，它们已挪到 `apply_tray_layout` 外面）。
    --   代价说明：现在 `cfg.btn_art ~= true` 时也会读一次 `cfg.btn_list`、建两个数 ——
    --   `apply_tray_layout` 只在开局摆一次，这点成本可忽略（不给每帧路径加负担）。
    local names = self.cfg.btn_list or {}
    local done, miss = 0, 0
    -- ★ ★ ★★★ 2026-10-05 **Round 35 收口**：块账在这里收平 ✓
    --
    --   历史（这条 bug 的形状很值得记）：
    --     L2371 的 `if self.cfg.btn_art == true and print then` 原来**一直没被关闭** ✗
    --     ⇒ 后面两个**顶层方法定义**被当成它的语句体吞了进去：
    --       `Adapter:apply_ruler_layout`（原 L2391）与 `Adapter:diagnose_overlap`（原 L2474）
    --     ⇒ Lua **不报错**（`end` 总数平衡），但这两个方法**只在 `apply_tray_layout`
    --       被调用过之后**才存在 ✗
    --     ⇒ `lua/main.lua` 的 `if a.apply_ruler_layout ~= nil then …` / `if diagnose_overlap then …`
    --       守卫**恒为假** ⇒「行标/列标对齐」与「相交诊断」**从来没跑过**（静默，零报错）✗
    --
    --   收口做法：两个方法整段**挪到本函数之后**（真正的文件顶层），
    --   上色循环留在本函数内（默认关闭）⇒ 本行的 `end` 关掉 `btn_art` 块 ✓
    --   ⇒ `node tools/audit/check_nesting.mjs` 的 `[嵌套]` 必须降到 **0 处** ✓
  end
  -- ★★★ 2026-10-05 Round 45：**上色循环已抽成顶层 helper** `Adapter:_tray_btn_art`
  --   （就定义在下面，`apply_tray_layout` **之前**）。
  --   为什么非抽不可：那段循环用 `names` / `done, miss`（本函数局部），
  --   而它**上面**那两个方法又必须在本函数**外面** ⇒ 只能把那段整段移出去 ✓
  --   等价性：同一段代码、同样顺序、同样计数、同样默认关闭（`cfg.btn_art`）✓
  -- ★★★★★ 2026-10-05 Round 48 修：下面这行调用用到了 `names` / `done` / `miss`，
  --   但抽 helper 时它们**没有跟着过来** ✗ ⇒ selene 报三条 `error[undefined_variable]` ✗
  --   （`names` / `done` / `miss` @L2461）⇒ 一旦 `cfg.btn_art = true` 就会**当场崩**（`#nil` 抛错 ✗）。
  --   该路径**默认关闭** ⇒ 离线测试测不到 ✗ ⇒ 只有静态检查能抓 ✓（这正是 selene 的价值 ✓）
  --   ⇒ 修法：在调用前就地声明（与 helper 内部那份等价 ✓ 传参用 ✓）
  local names = self.cfg.btn_list or {}
  local done, miss = 0, 0
  local moved_final = self:_tray_btn_art(moved, names, done, miss)
  -- ⚠️⚠️ 这个 `end` 关的就是 `apply_tray_layout`（`function` 在 2244 行）。
  --   它**必须**在下面两个方法之前 —— 否则那两个方法又会被吞成它的**子闭包**
  --   ⇒ 加载时不存在 ⇒ `main.lua` 的 `~= nil` 守卫恒假
  --   ⇒ 行标/列标对齐、相交诊断**静默失效**（零报错）✗ —— 就是本 bug 的原形。
  --   判据：`node tools/audit/check_nesting.mjs` ⇒ 这两个方法的 `深度` 必须是 **0** ✓
  return moved_final
end

-- 行标 / 列标按**格子的实际位置**对齐（顶层方法，加载时即存在）。
--
-- ⚠️ 曾被吞进 `apply_tray_layout` 体内 ⇒ `main.lua` 的守卫恒假 ⇒ **从未运行过**。
--    挪出来后 `main.lua:75/532` 的守卫才成立：`render()` 每次都调（见「新开销」说明）。
function Adapter:apply_ruler_layout(rows, cols)
  local g = self.cfg.cells or {}
  local ruler = self:find("ruler")
  if ruler == nil then return 0 end
  local rx, ry = nil, nil
  pcall(function() rx, ry = ruler:GetAnchoredPosition() end)
  if type(rx) ~= "number" or type(ry) ~= "number" then
    pcall(function() local p = ruler:GetUIPos() if p then rx, ry = p.x, p.y end end)
  end
  if type(rx) ~= "number" or type(ry) ~= "number" then rx, ry = 0, 0 end

  local moved = 0
  local function cellPos(i, j)
    local c = self:find(string.format("cell.%d.%d", i, j))
    if c == nil then return nil, nil end
    local x, y = nil, nil
    pcall(function() x, y = c:GetAnchoredPosition() end)
    if type(x) ~= "number" then
      pcall(function() local p = c:GetUIPos() if p then x, y = p.x, p.y end end)
    end
    return x, y
  end

  -- 列标：贴着第 1 行格子的横向中心
  for j = 1, math.min(cols or 5, 7) do
    local lbl = self:find("ruler.c." .. j)
    local cx, _ = cellPos(1, j)
    if lbl ~= nil and type(cx) == "number" then
      local lx, ly = nil, nil
      pcall(function() lx, ly = lbl:GetAnchoredPosition() end)
      if type(lx) ~= "number" then pcall(function() local p = lbl:GetUIPos() if p then lx, ly = p.x, p.y end end) end
      if type(lx) == "number" and lbl.SetAnchoredPosition then
        -- ★ 2026-09-28：**先把 pivot 归中**再定位。
        --   上一版只 SetAnchoredPosition，结果还剩 ~25px 的**恒定偏移** ——
        --   那是标签自身 pivot 与格子 pivot 不一致造成的（SetAnchoredPosition 定的是
        --   **锚点**的位置，pivot 不同则视觉中心不同）。
        --   与格子保持同一套 pivot（0.5,0.5），偏移就没了。
        if lbl.SetPivot then pcall(function() lbl:SetPivot(0.5, 0.5) end) end
        pcall(function() lbl:SetAnchoredPosition(cx - rx, ly) end)
        moved = moved + 1
      end
    end
  end
  -- 行标：贴着第 1 列格子的纵向中心
  for i = 1, math.min(rows or 5, 7) do
    local lbl = self:find("ruler.r." .. i)
    local _, cy = cellPos(i, 1)
    if lbl ~= nil and type(cy) == "number" then
      local lx, ly = nil, nil
      pcall(function() lx, ly = lbl:GetAnchoredPosition() end)
      if type(lx) ~= "number" then pcall(function() local p = lbl:GetUIPos() if p then lx, ly = p.x, p.y end end) end
      if type(ly) == "number" and lbl.SetAnchoredPosition then
        if lbl.SetPivot then pcall(function() lbl:SetPivot(0.5, 0.5) end) end
        pcall(function() lbl:SetAnchoredPosition(lx, cy - ry) end)
        moved = moved + 1
      end
    end
  end
  if print then
    -- ★★★★★ 2026-10-05 Round 49 **日志节流：只在"对齐结论真的变了"时才打** ✓
    --
    --   起因：本方法刚被修好（它以前被吞在 `apply_tray_layout` 里、**从未运行过** ✗），
    --   于是这段"无条件打印"第一次真的跑起来 ✗ ⇒ 实测 **2 行/次**，
    --   而调用频率是 **1.10 次/秒**（`main.lua:709` 的 `Murdoku.render` 被
    --   `sec ~= last_tick or controller.dirty` 门控）⇒ **≈2.2 行/秒 ≈ 7900 行/小时** ✗
    --   ⇒ 移动端日志洪水（也会拖慢真机）。**修好一个功能反而引入了负担** ✓ 所以要节流。
    --
    --   做法：把**会被打印出来的那些数**拼成结论串；与上次相同 ⇒ **整段跳过**（连日志都不打）✓
    --   ⚠️ 两个坑（都是踩过的 ✗）：
    --     ① **签名里不能塞"没被打印的数"** ✗ —— 例如 `ly1` / `rx1`（读了但没打），
    --        它们会随引擎抖动 ⇒ 误判"结论变了" ⇒ 白打一遍，节流被击穿 ✓
    --     ② `string.format` 的**占位符不能比参数多** ✗ —— 否则报
    --        `bad argument #N to 'format'`，而它若发生在 `on_start` 的 pcall 里会被**静默吞掉** ✗
    --   反向对照（防"静默阉割"）：把 `cell.1.1` 横移 ⇒ **正好打 2 行** ✓；再连调 20 次 ⇒ **0 行** ✓
    local cx1, cy1 = cellPos(1, 1)
    local l1, r1 = self:find("ruler.c.1"), self:find("ruler.r.1")
    local lx1, ly1 = nil, nil
    if l1 then pcall(function() lx1, ly1 = l1:GetAnchoredPosition() end) end
    local rx1, ry1 = nil, nil
    if r1 then pcall(function() rx1, ry1 = r1:GetAnchoredPosition() end) end
    -- 签名 = **只由下面两行 print 用到的数**构成 ✓（`ly1` / `rx1` 不进来 ✓）
    local sig = string.format("%d|%.1f|%.1f|%.1f|%.1f|%.1f|%.1f",
      moved, rx, ry, cx1 or 0, cy1 or 0, lx1 or 0, ry1 or 0)
    if self._ruler_align_sig ~= sig then
      self._ruler_align_sig = sig
      print(string.format("[murdoku] 行标/列标已按格子实际位置对齐：%d 个（ruler 容器偏移 %.1f, %.1f）",
        moved, rx, ry))
      -- 顺手把"格子位置 vs 标签位置"打出来 —— 下次若还有偏差，
      -- 这两个数一比就知道差在哪一维，不用再靠截图量像素。
      print(string.format("  核对：cell.1.1=(%.1f, %.1f)  ruler.c.1.x=%.1f（应≈%.1f）  ruler.r.1.y=%.1f（应≈%.1f）",
        cx1 or 0, cy1 or 0, lx1 or 0, (cx1 or 0) - rx, ry1 or 0, (cy1 or 0) - ry))
    end
  end
  return moved
end
-- ★★ 2026-09-28 新增：**列出"与棋盘区域相交、且处于显示中"的控件**。
--
-- 为什么需要：用户反复报「棋盘上有白色/紫色方块」「R3/R4 之间粘连」。
--   而我只能靠截图量像素去猜是哪个控件 —— 规划文件是**多状态并集**，
--   光看数据分不清"屏幕上现在到底有谁"。
--   这条诊断直接把答案打出来：名字 + 实际位置 + 尺寸 + 是否显示。
--
-- 用法：开机自动跑一次（cfg.overlap_diag = false 可关），
--       列出的每一条都值得怀疑；空列表 = 棋盘区域是干净的。
function Adapter:diagnose_overlap()
  -- ⚠️ 必须用**绝对坐标**（`GetUIPos`），不能用 `GetAnchoredPosition`！
  --   后者返回的是"**相对各自父控件**"的偏移 —— 拿它去和棋盘的坐标比，
  --   等于拿两套不同原点的数相减。真机日志因此报过 **100 个控件压在棋盘上**（全是误报），
  --   而玩家屏幕上真正看到的只有 2 条。
  --   ⇒ 规矩：**比坐标之前先确认两者在同一坐标系**。拿不到绝对坐标就明说，不要硬比。
  local board = self:find((self.cfg.cells or {}).parent or "board")
  if board == nil then return 0 end
  local bx, by, bw, bh = nil, nil, nil, nil
  pcall(function() local p = board:GetUIPos() if p then bx, by = p.x, p.y end end)
  pcall(function() bw, bh = board:GetSizeDelta() end)
  if type(bx) ~= "number" or type(bw) ~= "number" then
    print("[murdoku] 相交诊断：**本环境拿不到控件的绝对坐标（GetUIPos 不可用）**，跳过 —— "
      .. "不再用相对坐标硬比（那会报出一堆假阳性）。")
    return 0
  end
  local x0, x1 = bx - bw / 2, bx + bw / 2
  local y0, y1 = by - bh / 2, by + bh / 2
  print(string.format("[murdoku] --- 相交诊断：棋盘 x[%.0f,%.0f] y[%.0f,%.0f] ---", x0, x1, y0, y1))

  local hits = 0
  for i = 1, #MANAGED do
    local parent = self:find(MANAGED[i])
    if parent ~= nil then
      local ok, kids = pcall(function() return parent:GetChildren() end)
      if ok and type(kids) == "table" then
        for k = 1, #kids do
          local ch = kids[k]
          local nm, vis, cx, cy, cw, chh = nil, nil, nil, nil, nil, nil
          pcall(function() nm = tostring(ch.name) end)
          pcall(function() vis = ch.visible end)
          pcall(function() local p = ch:GetUIPos() if p then cx, cy = p.x, p.y end end)
          pcall(function() cw, chh = ch:GetSizeDelta() end)
          if type(cx) == "number" and type(cw) == "number" and vis ~= false then
            -- 相交判定（中心落在棋盘内即算，避免把边缘相接的 ruler 也算进来）
            if cx > x0 and cx < x1 and cy > y0 and cy < y1 then
              hits = hits + 1
              if hits <= 24 then
                print(string.format("  ⚠️ %-22s 父=%-10s 中心(%.0f,%.0f) 尺寸%.0fx%.0f",
                  tostring(nm), MANAGED[i], cx, cy, cw, chh or 0))
              end
            end
          end
        end
      end
    end
  end
  print(string.format("  与棋盘相交且显示中的控件：%d 个%s", hits,
    hits == 0 and "（干净）" or "  ← 这些就是压在棋盘上的"))
  print("[murdoku] --- 相交诊断结束 ---")
  return hits
end

-- ⚠️ 2026-10-05 Round 45：这里原来是「按钮底图上色（运行时）」那一整段循环。
--   它已经**整段搬进**上面的顶层 helper `Adapter:_tray_btn_art`（同一个文件，函数体原样）✓
--   搬走的理由：它用 `names` / `done, miss`（`apply_tray_layout` 的局部变量），
--   而那两个方法必须在 `apply_tray_layout` **外面** ⇒ 只有把这段移出去，
--   才可能让 `apply_tray_layout` 在方法**之前** `end` 掉 ✓
--   ⚠️ 别把它搬回来：搬回来 ⇒ `apply_tray_layout` 又要把方法吞进去（本 bug 复发 ✗）。

-- 尝试由**脚本自己**打开容器的「显示常驻光标」(`showCursor`)。
--
-- 背景：真机上"点不动界面"的头号原因就是**控件的祖先容器没打开 showCursor**
-- （模拟器的派发条件是
--   `for i=t; i; i=i.parent do if i.kind=="container" and i.showCursor then return true end end`
--  —— 见 docs/环境问题-诊断记录.md 的门控 ②）。
-- 正常要在编辑器里手勾，但**如果 Lua 侧允许写这个字段**，脚本就能自己搞定，
-- 少一个最容易漏的手工步骤。
--
-- 真机若不开放该字段，pcall 会失败 → 返回 0 → 上层只记一条提示，不影响运行。
function Adapter:enable_cursor()
  local n = 0
  for i = 1, #CURSOR_CONTAINERS do
    -- ⚠️⚠️ 2026-10-02 **这里原来写的是 `MANAGED[i]`** —— 边界用 CURSOR_CONTAINERS（12 项），
    --   取名字却用 MANAGED（只有 10 项）⇒ i=11/12 时 `MANAGED[i]` 是 **nil**
    --   ⇒ `find(nil)` 返回 nil ⇒ **`home` / `select` 从来没被找到过**。
    --   这就是"补了名单却完全没生效"的真正原因 —— **一行索引写错了数组**，
    --   和"调用时机"无关（我昨晚那个"时机"推断是错的）。
    --   回读那段当时也抄了同一个错，所以两边**一致地缺** `home`/`select` ——
    --   反而让日志看起来"自洽"，更不容易发现。
    --   ⇒ 教训：**同一份名单出现在两处时，索引必须指向同一份**。
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(function() ctrl.showCursor = true end)
      if ok then n = n + 1 end
    end
  end
  -- ★ 回读：把每个受管容器的 showCursor 实际值打出来。
  --   门控②（祖先容器 showCursor=true）是"点不动"的头号原因，
  --   而 `pcall` 会**静默吞掉失败** —— 改了必须回读才算数。
  --
  --   ★★ 2026-10-02 追加 `kind`：派发条件是 **`i.kind == "container" and i.showCursor`**，
  --   `showCursor` 已经全 true 了（真机回读证实），而点击依旧不通 ⇒ **剩下的变量就是 `kind`**。
  --   如果 `root`/`home`/`select` 的 `kind` 不是 `"container"`（比如是别的名字），
  --   门控②**永远不满足** ⇒ 点不动 —— 而且能解释探针那句"所有容器都不支持光标事件"。
  local parts = {}
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local sc, kd = "?", "?"
      pcall(function() sc = tostring(ctrl.showCursor) end)
      -- `kind` 可能叫别的名字，多试几个写法，读不到就留 "?"
      pcall(function() kd = tostring(ctrl.kind) end)
      if kd == "nil" then pcall(function() kd = tostring(ctrl.Kind) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.type) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.controlType) end) end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
      -- （类型探测已撤：它每 20 帧打一次，刷屏；结论已记录在 enable_cursor 上方）
    else
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
  -- 只在内容变化时打（`enable_cursor` 现在每 20 帧重试一次，否则会刷屏）
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
  return n
end

-- 把「脚本能看到的客户端控件名字」打出来。
--
-- 用途：真机上最费时间的排查就是「脚本说控件未找到，可你明明建了」——
-- 到底是名字差一个字符、层级放错、还是容器没激活，光看错误信息猜不出来。
-- 这里直接把整棵树的名字按层级列出来，一对照就知道差在哪。
--
-- 只在诊断时调用（默认不跑），输出走 print（普通级日志）。
--
-- `quiet = true` 时**只数不打印**，用来回答"树到底起来了没有"。
-- 为什么要这个：真机上 `OnInit` 阶段控件树**本来就是空的**（约 0.5 秒后才出现），
-- 这不是故障。所以探针必须先量一下再决定"要不要现在就把话说完" ——
-- 树是空的且还有重试机会 → 说一句"稍后重试"就够了，别把三条病因砸给玩家看。
function Adapter:dump_names(max_depth, max_items, quiet)
  max_depth = max_depth or 6
  max_items = max_items or 400
  if game == nil or game.GetClientUIRoots == nil then
    if not quiet then self:err("dump_names：拿不到 game.GetClientUIRoots") end
    return 0
  end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then
    if not quiet then self:err("dump_names：GetClientUIRoots 失败") end
    return 0
  end
  local n = 0
  local lines = {}
  local function walk(c, depth)
    if c == nil or depth > max_depth or n >= max_items then return end
    local name, kind = "?", "?"
    pcall(function() name = tostring(c.name) end)
    pcall(function() kind = tostring(c.kind) end)
    local vis, act, pf = "?", "?", nil
    pcall(function() vis = tostring(c.visible) end)
    pcall(function() act = tostring(c.active) end)
    -- 控件模板索引（只读）。**专门为「另存为模板」那条路加的**：
    -- 真机上"读得到的索引"和"能实例化的索引"不是一回事（基础模板读得到但返回 nil），
    -- 所以排查时必须能一眼看到每个控件的索引，尤其是 tpl.cell 和 cell.1.1 各是多少。
    pcall(function() pf = c.prefabIndex end)
    n = n + 1
    if not quiet then
      local pfstr = ""
      if type(pf) == "number" and pf > 0 then pfstr = " tpl=" .. tostring(pf) end
      lines[#lines + 1] = string.rep("  ", depth) .. "- " .. name
        .. "  [" .. kind .. " vis=" .. vis .. " act=" .. act .. pfstr .. "]"
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  for i = 1, #roots do walk(roots[i], 0) end

  if not quiet and print then
    print("[murdoku] ===== 客户端控件树（脚本能看到的，共 " .. n .. " 个节点）=====")
    for i = 1, #lines do print("[murdoku] " .. lines[i]) end
    print("[murdoku] ===== 控件树结束 =====")
  end
  return n
end

-- 只数不打印：判断"控件树起来了没有"，用于决定诊断话术的轻重。
function Adapter:count_names(max_depth, max_items)
  return self:dump_names(max_depth or 6, max_items or 400, true)
end

-- ════════════════════════════════════════════════════════════════════════
-- 格子**模板候选**体检（配合「另存为模板」那条路）
--
-- 为什么单独报这个：`cell.1.1` 自己的 `prefabIndex` 是「预设按钮」的**基础模板**
-- （读得到，但拿去 InstantiateClientUIControl 会**静默返回 nil**）。
-- 所以必须有一个"**从另存出来的模板新建的**"控件，它的索引才是可实例化的。
--
-- 脚本本身**不关心你是怎么做出 tpl.cell 的** —— 它只看「那个控件的 prefabIndex
-- 能不能真的造出一个格子」。但「能不能造」只有**缺格子时**才会被试到，
-- 而那时日志里已经混了一堆别的东西。这里提前把候选和索引列出来，
-- 让你**试玩之前**就能确认配对了没有。
-- ════════════════════════════════════════════════════════════════════════

function Adapter:diagnose_template()
  local log = print
  if log == nil then return false end
  local g = self.cfg.cells
  if g == nil then return false end

  local base_id = g.probe or "cell.1.1"
  -- 与 _cells_prefabs 同样的规矩：基准**只从参照格子取**。
  -- 纯模板模式下参照格子不存在 → base_idx 保持 nil → `tpl.cell` 会被正确算成"可用候选"。
  --
  -- ⚠️ 但要注意**时机**：本函数跑在 `ensure_cells` **之后**，那时纯模板模式下的
  --    `cell.1.1` 已经被脚本造出来了 —— 现场查一定查得到。所以"纯模板模式"这个事实
  --    要读 `ensure_cells` **当时记下**的 `self.cells_probe_missing`，不能现场重推。
  local base_idx = nil
  local base_ctrl = self:find(base_id)
  if base_ctrl ~= nil then pcall(function() base_idx = base_ctrl.prefabIndex end) end
  if self.cells_probe_missing == true then
    log("[murdoku]   （**纯模板模式**：生成前没有参照格子 " .. base_id
      .. "，格子全部由脚本按模板生成 —— 这是一种合法且推荐的配置）")
  elseif base_idx == nil then
    log("[murdoku]   （没有参照格子 " .. base_id .. "，也读不到它的模板索引）")
  end

  local names = g.prefab_from or { base_id, "tpl.cell", "cell.tpl", "cell.prefab" }
  local found, usable = {}, 0
  log("[murdoku] --- 格子模板候选（用来批量生成其余格子）---")
  if type(g.prefab) == "number" and g.prefab > 0 then
    log("[murdoku]   cfg.cells.prefab = " .. tostring(g.prefab)
      .. "   ← **显式配置**，脚本会最先试它")
  else
    log("[murdoku]   cfg.cells.prefab = (未配置)")
  end
  for i = 1, #names do
    local id = tostring(names[i])
    local c = self:find(id)
    if c == nil then
      log("[murdoku]   " .. id .. "  —— **不存在**")
    else
      local p = nil
      pcall(function() p = c.prefabIndex end)
      -- ★ 两个数字含义不同，都要打出来（用户 2026-09-26 纠正过：
      --   `prefabIndex` 是**控件自身**的模板索引；模板引用控件引用的是
      --   `referencedPrefabIndex`。只打一个会让人把"控件自身索引"误当成"模板索引"。）
      local rf = self:_ref_index_of(c)
      local ref_txt = (rf ~= nil) and ("  ref=" .. tostring(rf) .. "（引用的模板）") or ""
      found[#found + 1] = { id = id, idx = p }
      local tag
      if id == base_id then
        tag = "   ← 参照格子自己"
      elseif type(p) == "number" and p > 0 and p == base_idx then
        tag = "   ← 与 " .. base_id .. " 同一个索引"
      elseif type(p) == "number" and p > 0 then
        tag = "   ← 与 " .. base_id .. " **不同**"
        if rf == nil then tag = tag .. "：可能就是可用的那个" end
        usable = usable + 1
      else
        tag = "   ← 读不到 prefabIndex"
      end
      log("[murdoku]   " .. id .. "  prefabIndex=" .. tostring(p) .. ref_txt .. tag)
    end
  end

  -- ★★ 结论必须报**实际结果**，不能靠"索引看起来不同"来猜。
  --
  -- 真机 16:07 就是这么被误导的：生成**明明成功了**
  -- （`格子模板索引 1073741876 可用；棋盘格子：25 / 25 存在`），
  -- 可这一段却打出「**没有可用的自定义模板** —— 缺格子时生成会失败」。
  -- 原因：`cell.1.1` 现在自己就带着模板索引（它是「模板引用控件」），
  -- 于是 `base_idx` 等于它自己 → "与 base 不同"这个启发式恒为假 → usable=0。
  --
  -- 所以现在：**ensure_cells 跑过就以它的实测结果为准**，启发式只当备注。
  -- ★ 把"生成前就存在的格子"点出来 —— 这是最容易被看错的一件事。
  do
    local pre = self.cells_preexisting
    if pre ~= nil then
      local ids = {}
      for id in pairs(pre) do ids[#ids + 1] = id end
      table.sort(ids)
      if #ids > 0 then
        log("[murdoku]   ℹ️ 生成前**已存在**的格子：" .. table.concat(ids, " "))
        log("[murdoku]     这些是**编辑器里的控件**，脚本只把它们摆正、**不会覆盖** —— "
          .. "所以它们不是模板生成的副本。")
        if pre[base_id] and base_idx ~= nil and g.prefab ~= nil and base_idx == g.prefab then
          log("[murdoku]     ⚠️ **" .. base_id .. " 的索引 == cfg.cells.prefab** —— "
            .. "它**就是那个模板引用控件本身**，不是生成的格子！")
          log("[murdoku]        它的外观由它自己决定，**可能和模板里的格子不一样**"
            .. "（截图里常见表现：只有它看着不对 / 缺一块）。")
          log("[murdoku]        想要「全 25 格都是模板副本」：把它**改名成 `tpl.cell`**（或删掉），"
            .. "让脚本把 " .. base_id .. " 也一起生成。")
        end
      end
    end
  end

  if self.cells_ok ~= nil then
    if self.cells_ok then
      log("[murdoku] 结论（实测）：**生成成功了** —— 用模板索引 "
        .. tostring(self.cells_index) .. " 建了 " .. tostring(self.cells_made)
        .. " 个格子，棋盘 " .. tostring(self.cells_total) .. " 格齐全")
    else
      log("[murdoku] 结论（实测）：**生成失败** —— 试过的索引都不可实例化（见上面的错误行）")
    end
    log("[murdoku] --- 体检结束（模板）---")
    return self.cells_ok
  end

  -- 没跑过 ensure_cells（例如缺格子数为 0）时才用启发式
  if usable > 0 or (type(g.prefab) == "number" and g.prefab > 0) then
    log("[murdoku] 结论（推测）：有**可能是可用模板**的候选 —— "
      .. "缺格子时脚本会挨个**真试着造**，造得出来才用它")
    log("[murdoku] --- 体检结束（模板）---")
    return true
  end

  log("[murdoku] 结论：**没有可用的自定义模板** —— "
    .. "缺格子时生成会失败（日志会打「全部实例化失败」）")
  log("[murdoku]   原因：" .. base_id .. " 自己的 prefabIndex 是「预设按钮」的**基础模板**，"
    .. "读得到但不能实例化；而右键【另存为模板】存出来的索引**也调不动**。")
  log("[murdoku] ⚠️ 正确入口是官方文档里那个（右键另存为模板**不是**它）：")
  log("[murdoku]   ① 界面控件组管理 → 界面控件组库 → **客户端控件模板** → 【添加客户端控件】")
  log("[murdoku]      → 加一个「预设按钮」，配好底图与子控件 → **存为模板**")
  log("[murdoku]   ② 那个模板的**控件模板索引 ID** 才是客户端脚本能调用的")
  log("[murdoku]      （点它就能看到 ID，把数字填进 cfg.cells.prefab 也行）")
  log("[murdoku]   ③ 也可尝试把它放进容器画布后改名 tpl.cell（脚本会自己读它的索引）")
  log("[murdoku] 依据：官方《客户端控件和客户端脚本的定义》——")
  log("[murdoku]   「除客户端控件容器画布中的客户端控件以及客户端控件模板中的控件外，"
    .. "其他控件均为服务器控件，**服务器控件的模板索引无法被客户端脚本调用**」")
  log("[murdoku] --- 体检结束（模板）---")
  return false
end

-- ════════════════════════════════════════════════════════════════════════
-- 参照格子体检（`cell.1.1`）
--
-- 为什么需要：一个格子要能"看得见 + 点得动 + 能当模板"，同时依赖四五项设置：
--   控件类型（必须预设按钮/光标检测区域）、可被光标射线检测、子控件 face/note/x、
--   face 挂到「默认」状态节点、图片类型=拉伸、祖先容器开了「显示常驻光标」。
--   这些**在日志里全都没有痕迹** —— 出问题时只能靠肉眼一个个猜。
--   2026-09-26 的真机日志就是这样：只知道"缺 24 个格子"，不知道手上这个配好没有。
--
-- 这里把上面每一项读出来，逐条给出 ✅/❌ 和"怎么修"，一次性讲完。
-- 每个会话打一次，不刷屏。
-- ════════════════════════════════════════════════════════════════════════

function Adapter:diagnose_cell(id)
  id = id or (self.cfg.cells and self.cfg.cells.probe) or "cell.1.1"
  -- 走 print（**正常级**日志）而不是 printerr：
  -- 这是一份**报告**，不是故障。走 stderr 有两个坏处：
  --   ① 模拟器/排查脚本会把"日志里有没有报错"当成健康判据 → 一份全是 ✅ 的体检
  --      也会被算成错误（本次就是这样挂了 8b/9 两步回归）；
  --   ② 你在日志窗口的「报错」分类里会看到一堆其实是 ✅ 的行。
  local log = print
  if log == nil then return false end

  local c = self:find(id)
  if c == nil then
    -- ⚠️ 纯模板模式（board 下只留一个 `tpl.cell` 模板引用控件、不建任何真格子）下，
    --    参照格子**本来就不存在** —— 这时候报"找不到控件"就是误报（会把人吓一跳）。
    --    改成明确说"这是合法配置，体检跳过"，把判断权交给下面的「模板候选」实测结论。
    local g = self.cfg.cells or {}
    if id == (g.probe or "cell.1.1") and (g.prefab ~= nil or self:find("tpl.cell") ~= nil) then
      log("[murdoku] 格子体检：没有 " .. id .. " —— **纯模板模式**（board 下只放模板引用控件）")
      log("[murdoku]   这是合法配置：格子全部由脚本按模板生成，编辑器里一个真格子都不用建。")
      log("[murdoku]   子控件 face/note/x 与状态节点引用都在**模板里**，不在这里，所以本段体检跳过。")
      log("[murdoku]   → 有没有配对，看紧接着的「格子模板候选」那段的**实测结论**。")
      log("[murdoku] ===== 体检结束 =====")
      return true
    end
    log("[murdoku] 格子体检 " .. id .. "：**找不到这个控件**"
      .. "（名字要一字不差；必须在客户端控件容器里）")
    return false
  end

  local lines, bad = {}, 0
  local function say(s) lines[#lines + 1] = s end
  local function mark(okflag, text, fix)
    if okflag then
      say("  ✅ " .. text)
    else
      bad = bad + 1
      say("  ❌ " .. text .. (fix and ("   → " .. fix) or ""))
    end
    return okflag
  end

  -- ① 类型：只有「预设按钮 / 光标检测区域」才有 AddCursorEventListener
  --    注意：kind 在真机/模拟器上可能读不到（模拟器返回 nil），所以以
  --    **接口是否存在**为准，类型名只作参考 —— 否则会出现"类型 = nil ✅"
  --    这种自相矛盾的行。
  local kind = nil
  pcall(function() kind = c.kind end)
  local kind_s = (kind ~= nil) and tostring(kind) or "读不到"
  if c.AddCursorEventListener ~= nil then
    say("  ✅ 控件类型 = " .. kind_s .. "，且**支持光标事件**（AddCursorEventListener 存在）")
  else
    mark(false, "控件类型 = " .. kind_s .. "，**不支持光标事件**",
      "改成【预设按钮】或【光标检测区域】；用容器/文本框永远点不动")
  end

  -- ② 射线检测 + 可交互
  local ray, ia = nil, nil
  pcall(function() ray = c.raycastTarget end)
  pcall(function() ia  = c.interactable end)
  if ray ~= nil then
    mark(ray == true, "可被光标射线检测 raycastTarget = " .. tostring(ray),
      "在【基础】里打开它，否则点击到不了脚本")
  else
    say("  ⚠️ 读不到 raycastTarget（该实现不暴露这个字段）—— 请到编辑器里确认已打开")
  end
  if ia ~= nil and ia ~= true then
    mark(false, "可交互 interactable = false",
      "脚本会按格子是否可站人切它；常关会让格子一直是灰的")
  end

  -- ③ 模板索引（决定能不能复制出其余格子）
  local pf = nil
  pcall(function() pf = c.prefabIndex end)
  if type(pf) == "number" and pf > 0 then
    say("  ℹ️ 模板索引 prefabIndex = " .. tostring(pf)
      .. "（**能不能实例化以实际生成结果为准** —— 见下面「格子模板候选」那段的实测结论。"
      .. "内置基础模板（例如「预设按钮」的 1073741848）会静默返回 nil；"
      .. "用「**模板引用控件**」引用自定义模板后，这里就会变成可用的模板索引）")
  end

  -- ④ 子控件（脚本按名字找，**支持装在中间容器里的方案 A**）
  --
  -- ⚠️ 这里曾经写死 `c:GetChild(name)`（只查直接子控件），于是用户采用
  --    **方案 A**（子控件装进 `content` 容器）时，体检会**误报「不存在」** ——
  --    而运行时的 `Adapter:sub` 早就支持穿透容器了。**两处查找方式必须一致**，
  --    否则就会变成"体检说没有、其实能用"或反过来，白折腾。
  local via = nil
  do
    local direct = nil
    pcall(function() direct = c:GetChild("face") end)
    if direct == nil then
      for _, rn in ipairs({ "content", "root", "body" }) do
        local mid = nil
        pcall(function() mid = c:GetChild(rn) end)
        if mid ~= nil then via = rn break end
      end
    end
  end
  if via ~= nil then
    say("  ℹ️ 子控件装在中间容器 `" .. via .. "` 里（方案 A）—— 按路径查找")
  end

  local want_children = { { "face", true }, { "note", false }, { "x", false } }
  for i = 1, #want_children do
    local name = want_children[i][1]
    local sub = self:sub(id, name)      -- ★ 与运行时同一套查找
    if sub == nil then
      mark(false, "子控件 " .. name .. " —— 不存在",
        (name == "face" and "没它就换不了格面图（放置角色时看不到人）"
          or "没它这一格的" .. (name == "note" and "铅笔笔记" or "X 标记") .. "显示不出来")
        .. (via ~= nil and "" or "（若你把它装进了中间容器，容器名要在 content/root/body 之一）"))
    else
      local vis = nil
      pcall(function() vis = sub.visible end)
      local extra = ""
      -- face 和 x 都是**图片**控件，把图片来源/类型都读出来。
      -- 为什么连 x 也要读：能立刻发现"X 根本没配图"（imageId 为 nil 就永远不显示），
      -- 也能看到「基础 / 拉伸」实际是哪一个。
      if name == "face" or name == "x" then
        local it, iid = nil, nil
        pcall(function() it = sub.imageType end)
        pcall(function() iid = sub.imageId end)
        extra = "  imageType=" .. tostring(it) .. " imageId=" .. tostring(iid)
        if iid == nil then
          bad = bad + 1
          extra = extra .. "   ← **图片来源没配**！去「图片设置 → 图片源=静态引用 → 引用素材资产」选一张 "
            .. (name == "face" and "格面底图（带圆角/边框的建议用九宫格素材 + 图片类型=拉伸）"
                          or "X 图标（功能图标类即可）")
        end
        -- ⚠️ 这里**只提示、不报错**。
        --
        -- 2026-09-26 真机实验（用户做的）：**基础 也会铺满图片控件本身** ——
        -- 所以"格面不是拉伸"**不会**导致棋盘花掉，格面照样跟着格子缩放。
        --
        -- 「基础 / 拉伸」的真正区别只在**素材是九宫格/三宫格**时才显现：
        --   · 素材图片属性 = 普通   → 基础 和 拉伸 表现**完全一样**（角都形变）
        --   · 素材图片属性 = 三宫格 → 拉伸 保住那一对边，基础 会压扁
        --   · 素材图片属性 = 九宫格 → 拉伸 保住四角，基础 会压扁圆角
        -- 依据：官方《图片控件》那张「**图片属性**」表（注意：它属于**素材**，
        -- 不是「图片类型」的选项）。
        --
        -- 所以这里最多给一句 info，绝不记成 ❌ —— 否则就是在制造误报。
        if name == "face" and it ~= nil then
          local s = tostring(it)
          if not s:find("Stretch") then
            say("  ℹ️ 格面用的是【基础】：**也会铺满格子**，不影响棋盘。"
              .. "只有当你给 face 换了**九宫格/三宫格**素材、想让四角不被压扁时，"
              .. "才需要把图片类型改成【拉伸】")
          end
        end
      end
      say("  ✅ 子控件 " .. name .. " 存在（visible=" .. tostring(vis) .. "）" .. extra)
    end
  end

  -- ⑤ 祖先容器有没有开「显示常驻光标」（门控②）。脚本会自己开，这里只做复核。
  local cur, cursor = c, false
  for _ = 1, 12 do
    if cur == nil then break end
    local sc = nil
    pcall(function() sc = cur.showCursor end)
    if sc == true then cursor = true end
    local p
    pcall(function() p = cur.parent end)
    cur = p
  end
  mark(cursor, "祖先容器已开「显示常驻光标」（门控②）",
    "日志里没看到『已由脚本打开 N 个容器』就得在编辑器里手动勾")

  log("[murdoku] ===== 格子体检：" .. id .. " =====")
  for i = 1, #lines do log("[murdoku]" .. lines[i]) end
  if bad == 0 then
    log("[murdoku] 结论：**这一格配好了**（底图 + face/note/x + 状态节点 + 射线 + 门控②都过）。")
    log("[murdoku]   → 接下来按第 5 节做「客户端控件模板」，再用「**模板引用控件**」引用它，")
    log("[murdoku]     把 referencedPrefabIndex 填进 cfg.cells.prefab（**不是** prefabIndex）就行。")
    log("[murdoku]   → 若这一格是**脚本生成**的副本，说明模板已通，不用再动编辑器。")
  else
    log("[murdoku] 结论：还有 " .. bad .. " 项要处理（见上面 ❌ 行）")
  end
  log("[murdoku] ===== 体检结束 =====")
  return bad == 0
end

-- ★★★★★ 2026-10-05 **销毁/回收一个控件时，把它名下「所有规划节点」的事件一起扔掉。**
--
--   为什么不能只按 id 清一笔：事件表现在按**规划节点**记（`id \1 父容器 \1 序号`），
--   一个 id 可能挂着好几个节点（`action.back` 就挂着 2 个）。
--   控件真的没了 ⇒ 这几个节点的事件**全都作废**：只清掉其中一个会留下**孤儿条目**
--   （那个键再也不会被写、也再也不会被读，纯泄漏）。
--   ⚠️ 前缀匹配是安全的：分隔符 `\1` 不可能出现在控件 id 里（同一条约定见
--      ui_controller 的 `drop_props_of`），所以 `id .. "\1"` 只会命中**这个 id** 的节点键。
--   ★★★★★ 2026-10-05 **B2 追加：`event_claim` 也要一起清**（同一件事，不能只做一半）。
--      `event_claim[id]` 指着"认领这个控件的那把节点键" —— 控件销毁重建后，那把键**已经
--      不存在**（上面刚被清掉）⇒ 不清就会**认领到旧节点** ✗：
--      `live_event()` 读 `self.events[旧键]` = nil ⇒ 静默退回 `node.event`，
--      看起来"还能点"，实际派发的可能不是这颗新控件的语义（而且新节点再也认领不上 ✗）。
function Adapter:forget_events_of(id)
  local pre = tostring(id) .. "\1"
  local stale = nil
  for k in pairs(self.events) do
    if type(k) == "string" and k:sub(1, #pre) == pre then
      stale = stale or {}
      stale[#stale + 1] = k
    end
  end
  if stale ~= nil then
    for i = 1, #stale do self.events[stale[i]] = nil end
  end
  self.event_claim[id] = nil   -- ★ B2：控件没了 ⇒ 认领关系作废（新控件要能重新认领）
  self.event_latest[id] = nil
  self.handlers[id] = nil
end

function Adapter:destroy_control(id)
  local ctrl = self.controls[id]

  -- ★ 2026-09-26 修：以前这里对**编辑器里手摆的控件**也调 DestroyClientUIControl，
  --   于是弹窗一关，modal / modal.suspect.* 就被**真销毁**了 ——
  --   下次再要显示指认面板时，脚本按名字怎么也找不到，面板永远出不来。
  --   只有「脚本用 InstantiateClientUIControl 现生成的」控件才允许销毁；
  --   编辑器手摆的只能藏起来。
  if self.instantiated and self.instantiated[id] then
    if ctrl and game and game.DestroyClientUIControl then
      pcall(function() game.DestroyClientUIControl(ctrl) end)
    end
    self.instantiated[id] = nil
    self.bound[id] = nil
    self.controls[id] = nil
    self:forget_events_of(id)
    -- ★ 控件真的没了 ⇒ 名字缓存整代作废（"不在"的判定和"在"的句柄都可能已经过期）
    self:invalidate_lookups("destroy:" .. tostring(id))
    return
  end

  if ctrl ~= nil then
    if ctrl.SetVisible then
      pcall(function() ctrl:SetVisible(false) end)
    elseif ctrl.SetActive then
      pcall(function() ctrl:SetActive(false) end)
    end
  end
  -- 只清缓存，让下次 create_control 重新 find；控件本身留着（监听也留着）
  self:drop_lookup(id)
  self:forget_events_of(id)
end

----------------------------------------------------------------------------
-- 属性同步
----------------------------------------------------------------------------

----------------------------------------------------------------------------
-- 素材调色板：解决「一个模板怎么给不同格子配不同图」
--
-- 问题本质：`SetImage(imageSource, imageId)` 要的是**整数 imageId**，
--   而 `imageId` / `imageSource` 字段都是**只读**（官方 API），
--   所以脚本没法把"图片名字"直接变成 ID；你也不可能把几十个数字抄进代码。
--
-- 解法：在编辑器里放一个**调色板容器**（默认叫 `assets`），
--   里面每个想要的图各放一个**图片控件**，控件名就是引用键
--   （例如 `room.kitchen`、`floor.wood`、`portrait.A`），图在编辑器里配。
--   脚本运行时**读它们的 `imageSource` + `imageId`**，之后按名字套到任意格子：
--
--     set_property("cell.2.3", "image", "room.kitchen")
--
-- 好处：一个模板 + 一张调色板 = 任意多种外观，**不用为每种外观做模板**；
--       换图只在编辑器里改，**代码一个字都不用动**；不用手抄任何 ID。
--
-- 调色板容器会被 `hide_unlisted` 自动隐藏（它不在关卡布局里），放哪都行。
----------------------------------------------------------------------------
function Adapter:read_palette()
  if self._palette ~= nil then return self._palette end
  local map, names = {}, {}
  local a = self.cfg.assets or {}
  local root = self:find(a.palette or "assets")
  if root ~= nil then
    local kids = nil
    pcall(function() kids = root:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do
        local k = kids[i]
        local nm, src, id = nil, nil, nil
        pcall(function() nm = tostring(k.name) end)
        pcall(function() src = k.imageSource end)
        pcall(function() id = k.imageId end)
        if nm ~= nil and nm ~= "" and type(id) == "number" then
          map[nm] = { source = src, id = id }
          names[#names + 1] = nm
        end
      end
    end
  end
  self._palette = map
  self._palette_names = names
  return map
end

-- 把「素材键」解析成 { source, id }。
-- value 可以是：调色板里的名字（字符串）、或直接的整数 ID。
function Adapter:resolve_asset(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n ~= nil then return { source = nil, id = n } end   -- 直接给数字：来源由调用方沿用
  local map = self:read_palette()
  local hit = map[tostring(value)]
  if hit ~= nil then return hit end
  self:warn_once("asset:missing:" .. tostring(value),
    "调色板里没有素材「" .. tostring(value) .. "」。\n"
    .. "       建法：在编辑器里放一个容器（默认名 `assets`），每个素材放一个**图片控件**，\n"
    .. "       控件名就是引用键（例如 `room.kitchen`），图在编辑器里配好。\n"
    .. "       当前调色板：" .. ((self._palette_names and #self._palette_names > 0)
      and table.concat(self._palette_names, " ") or "（空 —— 找不到 `assets` 容器？）"))
  return nil
end

-- 每格四边的墙 / 门：固定 4 个子控件，按数据开关。
--
-- 为什么这样做：`cd.walls` / `cd.doors` 每格都不同（`{up,down,left,right}` 布尔表），
--   但**一个模板的副本结构是一样的** —— 所以做法是在模板里放 4 个固定的
--   墙位子控件（`wall.up` / `wall.down` / `wall.left` / `wall.right`）
--   与 4 个门位（`door.*`），运行时按数据 `SetVisible(true/false)`。
--   官方依据：`SetVisible(visible)`「仅设置可见性，不改变激活状态」。
-- ★★ 图层顺序：**必须显式规划**，不能听天由命。
--
-- 用户 2026-09-27 提醒：图片/文本之间的层级**由模板里的位置（同级次序）决定**，
-- **不看创建或生成顺序**，而且**图层会互相覆盖**。
--
-- 官方给了控制手段（客户端控件基类）：
--   · `GetSiblingIndex()` → 当前同级索引
--   · `SetSiblingIndex(i)` → 「数值越大通常越靠后、**显示越靠上**」
--   · `SetAsFirstSibling()` / `SetAsLastSibling()`
--
-- 所以这里按 `cfg.cells.layer_order`（**从下到上**）把每个格子的子控件重排一遍 ——
-- 于是最终层叠**不依赖编辑器里的摆放次序**（那个只是默认值）。
--
-- 实现技巧：**倒序**逐个 `SetAsFirstSibling()`。
--   先处理"最上层"的那个 → 它到 0；再处理下一个 → 它到 0、前一个退到 1……
--   全部处理完，列表里**最后一个**就在 0（最底），第一个在最高位 —— 正好是我们要的顺序。
-- ★★★★★ 2026-10-02 **按屏幕排图层**（真机"选关点不动"的根因，用户指出的方向）。
--
--   用户的观察拼出了完整答案：
--     · 「那个全屏按钮还在」            => 屏幕上有个**全屏的东西**在吃点击
--     · 「界面内的按钮并没有被恢复回来」 => 它盖住了那些按钮
--   而 `home` / `select` **都是 1600x900、都在 `root` 下** ——
--   **谁在兄弟列表里靠后，谁就显示在上面**（官方 `SetSiblingIndex`「数值越大越靠上」）。
--
--   => 主页能点，是因为 `home` 恰好在上；
--     选关不能点，是因为 **`select` 显示时 `home` 仍然压在它上面** ——
--     那层 1600x900 的容器把选关页的点击全吃了。
--     （我前几轮一直盯着 `select`，方向错了；**凶手是另一个容器**。）
--
--   => 修法：**不用 visible 开关**（真机证明"由藏变显"会让射线出问题），
--     改成**每帧把当前屏幕的容器排到最上、另一个排到最下**。
--     幂等、便宜、只动顺序。
--
--   ★ 这正是本项目反复吃亏的那一类错：**图层顺序**。
--     （格子子控件排过 `enforce_layers`；这次轮到屏幕容器。）
-- ★★★★★ 2026-10-02 **强制打开「可被光标射线检测」（`raycastTarget`）—— 真机"点不动"的正解**。
--
--   官方文档（docs/api-cache/mhd4fxr5v6la.txt）：
--     「可被光标射线检测：可以检测到光标在控件范围内的悬浮和点击行为」
--   项目自己的排查清单（docs/最小骨架控件清单.md:151 / 真机-cell.1.1-逐步指南.md:67）：
--     「**可被光标射线检测**（raycastTarget）—— 脚本靠 AddCursorEventListener 收点击；**关掉就点不动**」
--     「**界面看得见，但点哪儿都没反应**」= 没开这个开关
--     「点不动卡片 → 选不了人」（本次搭建要求.md:416）
--
--   而官方 API：**预设按钮只有三个自有字段 `interactable` / `clickAudioId` / `raycastTarget`**
--   —— `clickAudioId` 就是"点击音效" ⇒ **"处处有音效但什么也没发生" = 点到了按钮、但它 `raycastTarget=false`**。
--
--   我之前的错误：只对 **容器节点** 试过这个字段（容器没有它 ⇒ 读到 nil）
--   ⇒ 误以为"这个字段在引擎里不存在" ⇒ **从来没对按钮读过/写过它**。
--
--   ⇒ 这里**遍历整棵控件树**，对每个控件尝试写 `raycastTarget = true`，并统计/回读。
--     （只对"支持这个字段的控件"生效，别的控件 pcall 静默失败，无害。）
--
-- ════════════════════════════════════════════════════════════════════════
-- ★★★★★ 2026-10-05 **这一趟不能再"每 20 帧永远重扫"**（这一轮每帧成本第 (3) 条）。
--
--   真机形状：`Murdoku.on_update`（`main.lua` L666）原来每 20 帧**无条件**调一次
--   `enable_raycast()`，而它每次都**从 root 起整棵树 walk**（深度 ≤ 6、每层 ≤ 200 个子控件）。
--   实测（`tests/grid_cost.lua` 口径 [E]，300 帧）：调用 **15 次**、walk 掉
--   **7020 次 `GetChildren`** = **23.4 个节点/帧** —— 而它要做的事
--   （把 `raycastTarget` 打开）**是幂等的**：第一趟扫完就已经全打开了，
--   后面 14 趟是纯白跑。用户那句"没必要留着不必要的负载浪费"说的就是这一笔。
--
--   ⚠️ 但**不能"成功一次就永远不扫"**：本项目有明确的「**控件晚一步才进树**」案例 ——
--      `home` / `select` 这两个屏幕容器是**第一次渲染时**才 `create_control` 的
--      （见 `main.lua` 门控②那段注释：`find("home")` 开局返回 nil ⇒ 永远开不上）。
--      早停会让**后出现的屏幕控件永远开不上 `raycastTarget`**
--      ⇒ 那正是"界面看得见、点哪儿都没反应"的老病。所以三条一起用，各管一件事：
--
--     ① **收敛即停**（省掉绝大多数趟数）：
--        `seen > 0 且 set == 0` = "树里有带这个字段的控件，**而且它们全都已经是 true**"
--        ⇒ 连续 `RAY_IDLE_STOP` 趟都是这样 ⇒ 收工，之后**一次树都不走**。
--        ⚠️ `seen == 0`（树里一个带该字段的控件都没有）**不算收敛** ——
--           那更可能是"树还没就绪"，要继续试（这正是"控件晚一步才进树"要救的情形）。
--     ② **硬上限**（防止"永远试不成功"变成新的每帧负载）：
--        每一代最多 `RAY_MAX_SCANS` 趟（25 趟 × 20 帧 ≈ 8.3 秒），到顶就停，
--        **并且只报一次**（真机上 `seen == 0` 是真问题：按钮没这个字段就点不动）。
--     ③ **换屏 / 换关重新武装**（`Adapter:rearm_raycast`）：那一代会长出新控件
--        （`home` / `select` 以及各屏自己的子控件），必须给它一次机会。
--
--   ⚠️ **不把"重新武装"挂进 `invalidate_lookups`**：那个函数还被 `create_control` /
--      `destroy_control` **每个控件各调一次**（进关时几十次）⇒ 挂在那里等于
--      "每建一个控件就重扫一趟"，白跑比改之前还多。只有 **screen / level 换代**
--      （`ui_controller.render` 里那个块）才重新武装。
--
--   ⇒ 实测收益见 `tests/grid_cost.lua` 口径 [E]：300 帧里 `enable_raycast` 走掉的
--     `GetChildren` 从 **7020** 降到**个位数×一趟**，且**不再随帧数增长**。
-- ════════════════════════════════════════════════════════════════════════
local RAY_IDLE_STOP = 3      -- 连续几趟"树里全都开好了"就收工
local RAY_MAX_SCANS = 25     -- 每一代最多扫几趟（25 × 20 帧 ≈ 8.3 秒）

-- ②/③ 的那一半：换屏 / 换关时**重新武装**（不重置累计值，只重置本代的额度）。
--   为什么需要它：新屏幕的控件是**后来才建**的，早停会让它们开不上 raycastTarget。
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end    -- 本来就没扫过 ⇒ 没什么可武装的
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end

-- ★★★★★ 2026-10-05 **单个控件的 `raycastTarget` 就地打开（O(1)）**。
--
--   给谁用：**引擎在运行时克隆出来的控件** —— 最典型的就是网格视窗的列表项
--   （`RefreshItems` 里由引擎实例化的线索卡）。
--
--   为什么必须补这一条（**这是有意的补偿，不是顺手加的**）：
--     `enable_raycast` 原来**每 20 帧整树重扫**，顺带就把"引擎后来克隆出来的列表项"
--     也扫进去了；收敛/放弃之后不再重扫 ⇒ 那些**晚到**的按钮**没人给它们开这个字段**
--     ⇒ 「卡片点不动」。所以在这一边补上，而且比原来那趟重扫**更强**：
--       · 时机：**绑定的那一刻就开**（原来是"最多晚 20 帧"）；
--       · 成本：**1 次字段读写**（原来是一趟 ≈ 470 个 `GetChildren`）。
--   ⚠️ 三条返回值都有意义：`false` = 这个控件没有该字段（**容器**就是这种，
--      真机上读容器拿到的是 nil）—— 那不是失败，只是"不适用"。
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local before = nil
  pcall(function() before = c.raycastTarget end)
  if before == nil then return false end          -- 没有该字段 ⇒ 不适用
  if before == true then return true end          -- 已经是开的 ⇒ 幂等，不重复写
  local ok = pcall(function() c.raycastTarget = true end)
  return ok == true
end

function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
    self._ray = st
  end
  -- ★① 已经收敛 / 已经放弃 ⇒ **一次树都不走**。这一行就是第 (3) 条的全部收益。
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, samples = 0, 0, {}
  local function walk(c, depth)
    if c == nil or depth > 6 then return end
    local nm = "?"
    pcall(function() nm = tostring(c.name) end)
    -- 先读原值（判断它是不是"有 raycastTarget 的控件"）
    local before = nil
    pcall(function() before = c.raycastTarget end)
    if before ~= nil then
      seen = seen + 1
      if before ~= true then
        local ok = pcall(function() c.raycastTarget = true end)
        if ok then
          set = set + 1
          if #samples < 6 then samples[#samples + 1] = nm .. ":" .. tostring(before) .. "->true" end
        end
      end
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, math.min(#kids, 200) do walk(kids[i], depth + 1) end
    end
  end
  walk(root, 0)
  -- ── 这一趟之后：更新收敛账（见上面 ①② 两条）────────────────────────────
  st.scans = st.scans + 1
  st.seen, st.set = seen, set
  if seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
  if seen > 0 and st.idle >= RAY_IDLE_STOP then
    -- ① 收敛：树里有带该字段的控件，而且它们**全都已经是 true** ⇒ 幂等的事做完了。
    st.done = true
    -- 只报一次（每次换屏都报会变成新的日志噪音，而用户这一轮明确嫌日志多）。
    if print and not st.announced then
      st.announced = true
      self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
        .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
    end
  elseif st.scans >= RAY_MAX_SCANS then
    -- ② 到顶：**放弃**，只报一次。
    st.done = true
    self:warn_once("raycast_giveup",
      "射线开关（raycastTarget）：扫了 " .. tostring(st.scans) .. " 趟，"
      .. "一个「带该字段的控件」都没找到（seen=0）—— 停止重扫。"
      .. "⚠️ 这一条是真问题：按钮没有 raycastTarget 就**点不动**"
      .. "（「界面看得见、点哪儿都没反应」）。请核对控件树是否就绪、"
      .. "控件是不是预设按钮；换屏/换关会自动重扫一次，不必重进游戏。")
  end
  return seen, set, samples
end
function Adapter:enforce_screen_layers(screen)
  local function put(id, idx)
    local c = self:find(id)
    if c == nil then return end
    if c.SetSiblingIndex ~= nil then
      pcall(function() c:SetSiblingIndex(idx) end)
    end
  end
  if screen == "home" then
    put("select", 0)
    put("home", 20)
  elseif screen == "select" then
    put("home", 0)
    put("select", 20)
  else
    -- 关卡内：两个都压到最下面（棋盘/顶栏/线索才该在最上）
    put("home", 0)
    put("select", 1)
  end
end
function Adapter:enforce_layers(cell_id)
  local order = (self.cfg.cells and self.cfg.cells.layer_order)
    or { "face", "obj",
         "wall.up", "wall.down", "wall.left", "wall.right",
         "door.up", "door.down", "door.left", "door.right",
         "x", "note" }
  local done = 0
  for i = #order, 1, -1 do
    local sub = self:sub(cell_id, order[i])
    if sub ~= nil and sub.SetAsFirstSibling ~= nil then
      if pcall(function() sub:SetAsFirstSibling() end) then done = done + 1 end
    end
  end
  return done
end

-- ★★ 打开「点击事件穿透」——**点不动格子的头号原因**。
--
-- 官方 API `ClientUIContainerControl` 的字段里有一个
--     `disableCursorEventPassthrough` —— 「是否屏蔽**区域内点击事件穿透**」
-- 方案 A 下，`content`（容器节点）**整块压在按钮 `cell` 上面**。
-- 只要它屏蔽穿透，鼠标点击就**到不了按钮** → 表现为"点格子完全没反应"，
-- 而体检一切正常（按钮自己的 raycastTarget = true 也照样读得到）。
--
-- 好消息：这个字段是**读写**的，所以脚本可以直接把它关掉 ——
-- 不用你逐个容器去取消勾选。
--
-- 顺带把 `showCursor` 也打开（官方：「CursorEvent 相关方法都需设置该参数为真后
-- 才可正常使用」），与门控②同源；`disableKeyEventPassthrough` 也放开，
-- 免得中间容器把键盘事件也吃掉。
-- ★★★ 2026-09-30：**屏蔽穿透 —— 把 2D 界面和 3D 角色隔开**。
--
--   用户问过"社区里怎么把 2D 操作和后面的 3D 角色模型隔开，是拦截键位还是别的办法"。
--   答案（官方《客户端 Lua UI 脚本公共 API》第 24 节 ClientUIContainerControl）：
--     **不是拦截键位**，而是给**容器**设"屏蔽穿透"字段（均读写）：
--       disableKeyEventPassthrough     是否屏蔽**按键**事件穿透
--       disableCursorEventPassthrough  是否屏蔽**区域内点击**事件穿透
--       isolateNavigation              是否隔离手柄导航
--   一个字段覆盖整棵子树，不需要按键黑名单。
--
--   为什么"拦截"思路走不通：`AddKeyEventListener` **只是监听，没有"消费"语义** ——
--   监听无法阻止引擎把按键交给角色。官方给的解法就是在容器层面屏蔽穿透。
--
--   ⚠️ 本项目里 `open_click_passthrough` 用的是**同一个字段的反方向**
--      （设 false，让点击落到棋子上）—— 所以这不是新机制，只是换个方向用。
--
--   ⚠️ 待真机验证：**屏蔽之后 `AddKeyEventListener` 自己还能不能收到按键**。
--      如果连自己也收不到，就不能对整屏开 —— 所以这里**逐个容器可配**，
--      并打一行日志说明设了几个。
function Adapter:seal_container(id)
  local c = self:find(id)
  if c == nil then return false end
  local n = 0
  -- ① 按键：**屏蔽穿透 = true**（**这才是 2D/3D 隔离的正确开关**）。
  --
  --   ★★★★★ 2026-10-02 **真机 A/B 对比得出的结论，别再改错了**：
  --
  --   官方文档（docs/api-cache/mh3qqq9xc102.txt）：
  --     「**屏蔽按键事件穿透**：容器节点内的按键事件交互**不会穿透到界面外**」
  --   —— 这里的"界面外"指的是 **3D 世界**（不是游戏的原生 UI）。
  --   ⇒ `true` = **按键不会传到 3D 角色**（隔离生效）。
  --
  --   【A/B 实测】
  --     · 设 `true`  + 回调 `return true`  ⇒ Enter 打不开原生对话框（按键被回调标记"已处理"）
  --     · 设 `false` + 回调 `return false` ⇒ **点击/Enter 都通了，但隔离彻底失效**
  --       （真机日志：`按键事件 → KeyboardJumpKeyDown` ⇒ 按跳跃键角色真的跳了）
  --   ⇒ 真相：**"Enter 打不开"是回调 `return true` 造成的，跟这个字段无关**；
  --     而这个字段设 `false` 才会让按键穿到 3D。
  --   ⇒ **正确组合 = 本字段 `true`（隔离）+ 回调 `return false`（不标记已处理）**。
  if c.disableKeyEventPassthrough ~= nil then
    if pcall(function() c.disableKeyEventPassthrough = true end) then n = n + 1 end
  end
  -- ② 点击：**必须放开（false）**！
  --
  --   ⚠️⚠️ 我第一版把这里也设成了 `true`，结果**主页上所有按钮都点不动**
  --   （点了完全没反应，界面像卡死）。本项目 `open_click_passthrough` 的注释早就写明：
  --       `disableCursorEventPassthrough = false` …… **否则点击到不了按钮**
  --   "屏蔽区域内点击事件穿透"的语义是「**点击不再传给这个区域里的控件**」，
  --   **不是**"挡住背后的 3D 世界"。对自己要用鼠标点的界面必须设 `false`，
  --   否则等于把界面锁死。真正要挡的是**按键**落到 3D 角色身上 —— 那是 ① 的职责。
  if c.disableCursorEventPassthrough ~= nil then
    pcall(function() c.disableCursorEventPassthrough = false end)
  end
  -- ③ 手柄导航隔离：社区资料少，**先不动**（等真机验证过再开）。
  return n > 0
end

-- ★★★★★ 2026-10-07 **触摸遮挡层：挡住"全屏拖动 3D 角色"** ✗✓
--
--   背景（★ 用户请人做移动端测试反馈 ✓）：★「★ **屏幕上的每一点都可以拖动**，官方 UI 也能正常点」✓
--     ⇒ ★ 移动端的 3D 角色是吃 **cursor（触摸/拖动）** 事件的 ✓
--   而 `seal_container` 只挡**按键** ✓ ——
--     ★ 它刻意把 `disableCursorEventPassthrough` 留成 `false` ✓
--       （★ 真机教训：设 `true` 会让【该容器内的按钮】全部点不动 ✗ 见那里的注释 ✓）
--     ⇒ ★ **所以触摸这条完全没被挡住** ✓✓
--
--   ★ 解法 ✓：★ **单独做一层"全屏遮挡层"**（控件名 `shield` ✓ 由 `.gil` 建 ✓）
--     · ★ **只对它**设 `disableCursorEventPassthrough = true` ✓
--       ⇒ ★ 落在【空白处】的触摸被它吃掉 ✓ ⇒ ★ 传不到 3D ⇒ **人物不再乱跑** ✓
--     · ★ 它的 Z 序在我们 UI 的**最下面**（★ `root` 的第一个子控件 ✓）
--       ⇒ ★ 落在**我们按钮上**的触摸**先被按钮拿到** ✓ ⇒ ★ **点击照常** ✓✓
--     （★ 与"把整个界面设 true"的关键区别：那一层**不含我们的按钮** ✓ 所以不会锁死界面 ✓）
--
--   ⚠️ 控件不存在时**什么都不做**（安全 ✓）并**只报一次** ⇒ 建好控件即自动生效 ✓
function Adapter:seal_cursor_shield()
  local c = nil
  -- ★ 2026-10-07 用户实际用的是编辑器里那个名叫 `xxx` 的全屏容器 ✓（★ 两个开关都在编辑器里开了 ✓）
  --   ⇒ 这里**先找 `xxx`** ✓ 再兜 `shield`（★ 万一以后改名 ✓）
  pcall(function() c = self:find("xxx") end)
  if c == nil then pcall(function() c = self:find("shield") end) end
  if c == nil then
    self:warn_once("shield:missing",
      "还没建触摸遮挡层控件 `xxx`（全屏容器/光标检测区域，放在 `root` 的**第一个**子控件位）⇒ "
      .. "移动端在空白处拖动仍会让 3D 角色移动。")
    return false
  end
  local n = 0
  if c.disableCursorEventPassthrough ~= nil then
    if pcall(function() c.disableCursorEventPassthrough = true end) then n = n + 1 end
  end
  if c.showCursor ~= nil then pcall(function() c.showCursor = true end) end
  if c.raycastTarget ~= nil then pcall(function() c.raycastTarget = true end) end
  if n > 0 then
    print("[murdoku] 触摸遮挡层 `xxx`：已屏蔽点击穿透（移动端空白处拖动不再带动 3D 角色）")
  end
  return n > 0
end
-- 批量：给一组容器屏蔽穿透。返回成功的个数。
function Adapter:seal_containers(list)
  if list == nil then return 0 end
  local ok = 0
  for i = 1, #list do
    if self:seal_container(list[i]) then ok = ok + 1 end
  end
  return ok
end
function Adapter:open_click_passthrough(cell_id)
  local roots = (self.cfg.cells and self.cfg.cells.sub_roots)
    or { "content", "root", "body" }
  local parent = self:find(cell_id)
  if parent == nil or parent.GetChild == nil then return false end
  local touched = false
  for i = 1, #roots do
    local mid = nil
    pcall(function() mid = parent:GetChild(tostring(roots[i])) end)
    if mid ~= nil then
      if mid.disableCursorEventPassthrough ~= nil then
        pcall(function() mid.disableCursorEventPassthrough = false end)
        touched = true
      else
        -- 没有这个字段（不是容器节点 / 该实现不暴露）→ 只能靠编辑器里手动取消勾选
        self:warn_once("passthru:" .. cell_id,
          "中间容器 `" .. tostring(roots[i]) .. "` 读不到 `disableCursorEventPassthrough`，"
          .. "改不了。请在编辑器里把它的「**屏蔽区域内点击事件穿透**」**取消勾选** ——"
          .. "否则点击到不了按钮，表现为「点格子没反应」而体检却全绿。")
      end
      pcall(function() mid.disableKeyEventPassthrough = false end)
      pcall(function() mid.showCursor = true end)
    end
  end
  return touched
end

function Adapter:_apply_edges(id, prefix, flags)
  -- ⚠️ 返回值 = "**这一趟真的把边下发成功了吗**"（true/false），见下面 `missing_sub` 那段。
  --    没有边要画（flags 不是表）时算成功 —— 没东西要送，不该让上层一直重试。
  if type(flags) ~= "table" then return true end

  -- ★★ 内部边**只画一次** —— 否则同一条边被两格各画一条，屏幕上出现两条平行线。
  --
  -- 为什么：core 的 `view()` 里
  --     walls.up   = (r == 1)    or wall_set[h, r-1, c]
  --     walls.down = (r == rows) or wall_set[h, r,   c]
  --   于是**内部边**（键 `h, r, c`）既是上格的 `down`、也是下格的 `up` ——
  --   同一根墙被重复绘制，两者还隔着 gap 的间距，看着就是**两条线**。
  --
  -- 约定：**每条边由"上/左"的那一格负责画**；`down`/`right` 只在**最后一行/列**（真边框）才画。
  --   up(r=1)=顶边、down(r=rows)=底边、left(c=1)=左边、right(c=cols)=右边。
  local r, c = tostring(id):match("^cell%.(%d+)%.(%d+)$")
  r, c = tonumber(r), tonumber(c)
  local rows = self.cells_rows or (self.cfg.cells and self.cfg.cells.rows)
  local cols = self.cells_cols or (self.cfg.cells and self.cfg.cells.cols)
  local skip = {}
  if r ~= nil and rows ~= nil and r < rows then skip["down"] = true end
  if c ~= nil and cols ~= nil and c < cols then skip["right"] = true end

  -- ★ 记下"本关真的需要哪些边" —— 之后和"模板里配了哪些子控件"对账。
  --   用户 2026-09-27 04:26 的实例：关卡里 `v:4:3` / `v:5:3` 是**竖墙**，
  --   但模板只配了 `wall.up`，于是那两面竖墙**根本画不出来**，
  --   而日志里当时**什么都没说** —— 全靠人看截图才发现。
  self.edges_needed = self.edges_needed or {}
  local sides = { "up", "down", "left", "right" }
  -- ★★★★★ 2026-10-05 **"这一趟到底送出去了没有"要答得上来**（返回值 → `set_property` → 界面层）。
  --
  --   为什么：`self:sub()` 查不到子控件时，下面这段是**静默跳过**的 —— 属性在界面层
  --   看起来"已经下发"，实际**一次 `SetVisible` 都没调用**。而 `sub` 只缓存命中、
  --   不缓存未命中（见它的注释），所以"首帧/首次进关子控件还没就绪"是完全可恢复的：
  --   只要上层**再下发一次**就能补上 —— 这正是用户报的
  --   "第一次进关墙/门没画出来、第二次正常"最可能的形状。
  --   ⇒ 这里把**本关真需要、却取不到子控件**的边记下来，函数返回 false；
  --     界面层按"有限次重试"补发（次数有上限，不会变成每帧死循环）。
  local missing_sub = {}
  for i = 1, #sides do
    local s = sides[i]
    local want = (flags[s] and not skip[s]) and true or false
    if want then self.edges_needed[prefix .. "." .. s] = true end
    local sub = self:sub(id, prefix .. "." .. s)
    if sub == nil then
      if want then missing_sub[#missing_sub + 1] = prefix .. "." .. s end
    elseif sub.SetVisible ~= nil then
      pcall(function() sub:SetVisible(want) end)
    end
  end

  -- ★★★★★ 2026-10-05 **关卡内读回：每个格子只打一次** ✗✓ —— 时机对了才有意义 ✓
  --
  --   为什么要在【这里】打（而不是"逐格自检"那里 ✓）：
  --     · 上一版打在 `逐格自检` 里 ✗ ⇒ 而那一刻 `controller.screen` 还是 `"home"` ✗
  --       （真机日志紧接着就打了 `controller.screen = home` ✓）
  --       ⇒ ★ 读数全是 `vis=false` ✗ —— 而【同一行】的 `clues` 也是 false ✗
  --         可用户实测【线索区是好的】✓ ⇒ ★★ 证明那行读数【不在关卡内】✗✓
  --     · 而 `_apply_edges` 是**每帧渲染**都会走的 ✓ ⇒ ★ 这里才是"关卡内真实状态" ✓
  --
  --   ★ 判据（这次时机是对的 ✓）：
  --     · `vis=true` ✓ 而屏幕上没有 ✗ ⇒ ★ 层序/素材（但 sib/sx 已排除 ✓）
  --     · `vis=false` ✗ ⇒ ★ `SetVisible(want)` 当帧没生效 ⇒ 句柄/引擎 ✓
  --     · `vis` 与 `want` 不一致 ✗ ⇒ ★ 有人在别处覆盖它 ✓
  --   ⚠️ 只读 ✓ 每格只打一次（`self._edge_readback`）✗ 不刷屏 ✓
  -- ★★★★★ 2026-10-05 **去重键必须带 `prefix`** ✗✓ —— 否则读回是假象 ✓
  --
  --   我第一版用 `self._edge_readback[id]` ✗ ⇒ 而 `_apply_edges` 对**同一个格子**
  --   会被调用**两次**（`prefix="wall"` 一次 ✓ `prefix="door"` 一次 ✓）
  --   ⇒ ★★ 只记了第一次 ⇒ 真机日志里**只有 `door.*`** ✗ ⇒ 看起来"只有门没有墙" ✓✓
  --   ⇒ ★ 那是我探针的假象 ✗ —— ★ 离线探针已证明 `wall_set` 有 **7 条** ✓
  --     `view()` 有 **34 条墙边** ✓ ⇒ ★ 数据是对的 ✓
  --   ⚠️ 结论：★ **诊断代码的假象比被测 bug 更能骗人** ✓ —— 这次连吃了两次
  --     （上次是 `print_` ✗ 这次是去重键 ✗）
  -- ★★★★★ 2026-10-05 **把这一刻的"该亮哪些边"记下来** ✗✓ —— 供每帧重放 ✓
  --
  --   为什么必须记：★ `face` 是【每帧】被点亮的 ✓（真机日志：
  --   「格子底图已点亮：25 个 face（每帧保持）」✓ 走的是 `_cells_paint` ✓）
  --   而 `wall.*` / `door.*` 只在**属性下发那一趟**设一次 ✗
  --   ⇒ ★★ 只要之后任何一帧有人把它们覆盖回 false ✗ ⇒ **`face` 会被救回来 ✓ 而墙/门不会** ✗✓
  --     ⇒ ★ 屏幕上看不见 ✓ —— ★ 而我的读回是在**这一刻**读的 ✓ ⇒ 当然读到 true ✓✓
  --       ⇒ ★★ "读回 true 而屏幕没有"的最后一层就在这里 ✓
  --   ⇒ 记下来，在 `_cells_paint`（每帧那条路 ✓）里重放 ✓ —— 与 `face` 同等待遇 ✓
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end

  -- ★★★★★ 2026-10-06 **记下"该亮哪些边"，供每帧重放** ✗✓ —— 对抗 `hide_kids` 的递归藏 ✓
  --
  --   ★★ 这是"墙/门第一次进关不画"的**第二半**（也是真正的凶手 ✓）：
  --     · 适配层 `set_property(…, "visible", false)` 里有一段 ✗：
  --         `if vis == false and id:sub(1,5) == "cell." then hide_kids(ctrl, 0) end`
  --       ⇒ ★ 它把格子的**全部子控件递归设成 false** ✗（`face` / `wall.*` / `door.*` ✓）
  --     · ★ 而它**只在 `vis == false` 时递归** ✗（那段的注释自己说"显示时不递归" ✓）
  --       ⇒ ★★ **单向** ✗ ⇒ `cell.*` 一旦被藏过 ⇒ 子控件永不恢复 ✓✓
  --     · ★ 为什么"第二关正常"✗：★ 第二关【不重建格子】✗
  --       ⇒ `cell.*` 没有 `false → true` 的过程 ✗ ⇒ **从不触发那个分支** ✓
  --       ⇒ 子控件从没被递归藏过 ✓ —— ★★ 这解释了"只有第一关坏" ✓✓
  --   ⇒ ★ 修法：★ **把"该亮"记下来，在每帧都会跑的 `_cells_paint` 里重放** ✓
  --     这与 `face` 的"每帧保持"是**同一个套路** ✓（那段注释也是这么写的 ✓）
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end



  -- ★★ 「图片类型 = 基础」的图**按原尺寸画，不会填充控件** ——
  --    真机 2026-09-27 05:13 实测：同一面墙，素材选「拉伸」时是**满宽蓝条**，
  --    换成「基础」后只剩**左上角一小段**（"显示不完全"）。
  --    而「拉伸」只有**部分资产**支持（官方：「部分图片资产具有拉伸属性」），
  --    所以"大多数素材只能用基础"是常态。
  --
  --    对策：用 `localScaleX/Y`（官方：number、**读写**、Tweenable）把基础图**缩放**到
  --    目标长度。缩放不是"拉伸"（不保角），但对**墙/门这种纯色条**完全够用，
  --    而且**任何素材都能用** —— 这就把可用素材范围打开了。
  --
  --    前提：编辑器里把墙控件的尺寸调成**"正好包住那张图"**（脚本按
  --    目标长度 ÷ 这个尺寸 求缩放比）。控件已经铺满整条边时缩放比≈1，不受影响。
  if self.cfg.cells == nil or self.cfg.cells.edge_fit ~= false then
    -- 格子边长：`cell_geometry(n)` 才是权威算法（它按 board 实际尺寸与行列数算）。
    -- n 用当前关卡的真实行列数（ensure_cells 时记在 self.cells_rows/cols 上）。
    local n = self.cells_rows or (self.cfg.cells and self.cfg.cells.rows) or 5
    local cw = nil
    pcall(function() cw = self:cell_geometry(n) end)
    local ch = cw
    if type(cw) ~= "number" or cw <= 0 then cw, ch = nil, nil end

    -- ★★★★★ 2026-10-05 **"算不出格子边长"必须说出来**（否则这一整段是静默跳过的）。
    --
    --   为什么：下面 `if cw ~= nil then` 一旦为假，**整个几何适配（缩放 + 贴边）都不跑**，
    --   日志里却一个字都没有 —— 而"什么都没做"和"做了但没生效"在画面上完全一样，
    --   排查时会往错的方向找（比如怀疑贴图/层序）。
    if cw == nil and print and not self._edge_no_geo_noted then
      self._edge_no_geo_noted = true
      print("[murdoku] 边缘适配：**算不出格子边长**（cell_geometry(" .. tostring(n)
        .. ") 返回 0/nil）⇒ 墙/门的**缩放与贴边整段跳过**（按编辑器里摆的原样显示）")
    end

    -- 墙/门的**目标厚度**（画布单位）。做成配置项，这样"看起来多粗"是确定的数字，
    -- 而不是"看你素材多大"。
    local thick = (self.cfg.cells and self.cfg.cells.edge_thickness) or 8
    local door_ratio = (self.cfg.cells and self.cfg.cells.door_length_ratio) or 0.45

    if cw ~= nil then
      for i = 1, #sides do
        local s = sides[i]
        local sub = self:sub(id, prefix .. "." .. s)
        if sub ~= nil and flags[s] then
          local w, h = nil, nil
          pcall(function() w, h = sub:GetSizeDelta() end)
          local horiz = (s == "up" or s == "down")
          -- 目标几何：横边 = 长 cw × 厚 thick；竖边 = 厚 thick × 长 ch
          -- 门比墙短一点，看起来才像"门"而不是一整面墙
          local tlen = (prefix == "door") and (cw * door_ratio) or cw
          local tthick = thick
          local base_l = horiz and w or h      -- 基准：编辑器里控件的尺寸
          local base_t = horiz and h or w
          if type(base_l) == "number" and base_l > 0 and type(base_t) == "number" and base_t > 0 then
            local kl = tlen / base_l
            local kt = tthick / base_t
            -- ★ 双向缩放：**长和厚都由脚本定死**，所以最终看到的条一定是
            --   目标长度 × 目标厚度，跟你素材多大无关（前提：控件尺寸 == 素材原尺寸，
            --   即"别手动改尺寸，让编辑器按图自动定"）。
            if kl > 1.001 or kl < 0.999 then
              if horiz then pcall(function() sub.localScaleX = kl end)
              else pcall(function() sub.localScaleY = kl end) end
            end
            if kt > 1.001 or kt < 0.999 then
              if horiz then pcall(function() sub.localScaleY = kt end)
              else pcall(function() sub.localScaleX = kt end) end
            end
            -- 把基准和倍率**打进日志**：这样"正好包住"变成一个可核对的数字，
            -- 而不是一句模糊的话。第一次试玩看一眼就知道该不该调。
            if self.cfg.cells and self.cfg.cells.edge_fit_log ~= false then
              self._edge_fit_seen = self._edge_fit_seen or {}
              if not self._edge_fit_seen[s] then
                self._edge_fit_seen[s] = true
                if print then
                  print(string.format(
                    "[murdoku] 边缘适配 %s.%s：基准 %.0fx%.0f → 目标 %.0fx%.0f（倍率 %.2f / %.2f）",
                    prefix, s, w or 0, h or 0, horiz and tlen or tthick, horiz and tthick or tlen, kl, kt))
                end
              end
            end
          else
            -- ★★★★★ 2026-10-05 **基准读成 0 ⇒ 这一段是"静默跳过"的，必须明说**。
            --
            --   判据：`base_l` / `base_t` 取的是控件自己的 `GetSizeDelta()`（"编辑器里摆的尺寸"），
            --   它是**缩放倍率的分母**。分母是 0 或读不到时，这段（缩放）**整段不执行**，
            --   而下面的"贴边"照旧执行 —— 于是画面上是"墙在正确的位置上，但是原来那么大"
            --   （或者根本看不见），很容易被读成"贴边也没生效"。
            --   ⇒ 直接把读到的原始值打出来：这行和上面那行「基准 …→ 目标 …（倍率 …）」
            --     **互斥**（一个成功一个失败），日志里看到哪一行就知道走了哪条路。
            if self.cfg.cells and self.cfg.cells.edge_fit_log ~= false then
              self._edge_fit_seen = self._edge_fit_seen or {}
              local skip_key = "skip:" .. prefix .. "." .. s
              if not self._edge_fit_seen[skip_key] then
                self._edge_fit_seen[skip_key] = true
                if print then
                  print(string.format(
                    "[murdoku] 边缘适配 %s.%s：**基准读成 0 / 读不到**（w=%s h=%s）"
                    .. "⇒ 缩放这一段整段跳过（贴边照做）；原因通常是子控件尺寸还没定下来，"
                    .. "或编辑器里没给它尺寸",
                    prefix, s, tostring(w), tostring(h)))
                end
              end
            end
          end
          -- 贴到对应边（缩放绕中心，所以位置按"目标厚度"算，不再依赖控件自身尺寸）
          local x, y = 0, 0
          if s == "up" then y = (ch - tthick) / 2
          elseif s == "down" then y = -((ch - tthick) / 2)
          elseif s == "left" then x = -((cw - tthick) / 2)
          elseif s == "right" then x = ((cw - tthick) / 2) end
          if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
          if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(x, y) end) end
        end
      end
    end
  end
  -- ★ 只有"本关真需要的边**全都取到了子控件**"才算下发成功；取不到的交给上层**有限次**重发。
  --   ⚠️ 这里**只对"子控件取不到"负责**：倍率/贴边那两段也有各自静默跳过的情形
  --      （比如基准尺寸读成 0），但那些不是"缺控件"，把它们也算成失败会让每条边都反复重发，
  --      纯粹是噪音 —— 那两种情形已经各自打了日志（见上面两处「边缘适配 …」）。
  return #missing_sub == 0
end

function Adapter:set_property(id, key, value, nkey)
  -- ★★★★★ 2026-10-05 **返回值 = "这次真的送达了吗"**（true/false），界面层据此决定记账 or 重发。
  --
  --   为什么要有返回值：这里在 `find(id) == nil` 时是**静默 no-op**（既不报错也不写），
  --   而界面层原来是**无条件**把属性记成"已下发" ⇒ 首次进关时"控件还没进树"
  --   就把状态记死了 ⇒ 本关内**永不重发**，只能出关重进
  --   ⇒ 用户看到的"第一次进关渲染得比第二次少"。
  --   ⇒ 契约：**true = 该做的都做了（可以记账）；false = 这次没送到（上层可以重发）**。
  --     ⚠️ 只有"确实没送到"才返回 false —— 故意的空操作（如 `respect_editor_rect`
  --     跳过位置）要算 true，否则那些属性会被无意义地反复重发。
  local ctrl = self:find(id)
  if ctrl == nil then return false end

  if key == "text" then
    -- ★★ 2026-09-28：**按钮的文字走 `label` 子控件**。
    --
    -- 起因：我生成了 35 个按钮的 `label` 子控件（真机 `label(visible=true)` ✅），
    --   但**屏幕上一个字都没有**。探明原因后是这么回事：
    --     · 控件的**文字内容根本不存进 `.gil`**！
    --       证据：`hud.title` 里唯一的文本字段内容是 `"hud.title"`（它自己的名字），
    --       而屏幕上那句"框架自检样例（偷窃版）"是**脚本运行时填的**。
    --     · 空文字 = 那个字段**根本不存在**（和"空子控件列表"同一个规律）——
    --       所以往 .gil 里写初值这条路走不通。
    --   ⇒ 结论：**按钮名字必须由脚本在运行时填**。这里把按钮的文字转发到它的 `label` 子控件。
    --
    -- 顺序（先专用后通用）：
    --   ① 按钮自己的 `label` 子控件（我生成的那种）
    --   ② 按钮自己就是文字控件（`ctrl.text` 可写）
    --   ③ 老的 `text` 子控件（兼容）
    local done = false
    do
      local lc = nil
      pcall(function() lc = self:sub(id, "label") end)
      if lc ~= nil and lc.text ~= nil then
        local ok = pcall(function() lc.text = tostring(value) end)
        done = ok
      end
    end
    if not done and ctrl.text ~= nil then
      ctrl.text = tostring(value)
      done = true
    end
    if not done then
      local c = self:sub(id, "text")
      if c and c.text ~= nil then c.text = tostring(value); done = true end
    end
    -- ★ 三条路都走不通（没有 label / 自己不能写字 / 没有 text 子控件）⇒ 这次**没送到**。
    --   真机意义：按钮文案是运行时填的（不进 .gly），首帧"label 子控件还没就绪"时
    --   这里会返回 false，界面层就会**下一帧再补一次** —— 而不是让按钮永远空着。
    return done

  elseif key == "object" then
    -- ★★ 2026-09-28 新增：**物件图标的显隐**。
    --
    -- 背景（用户报「人物头像上有异常遮挡」）：模板里的 `obj` 子控件是给物件图标（书桌/地毯）留的，
    --   `layer_order` 把它排在 `face` **之上**。但我当初克隆它用了**白色占位图**，
    --   **又没有任何代码去关它** ⇒ 它永远是"一块白板压在头像上"：
    --   空格看不出（face 本来就是白图），**一放人就露馅** ——
    --   截图里 C3/R1、C4/R2、C4/R3 那三块白方块就是它。
    --   ⇒ 没物件就**藏起来**；将来配了物件图（调色板 `obj.*`）再按名字换图并显示。
    local o = self:sub(id, "obj")
    if o ~= nil then
      -- `false` 是 ui_controller 约定的"没有物件"哨兵（nil 会让这个键在 `pairs` 里消失）
      if value == false or value == nil then
        if o.SetVisible then pcall(function() o:SetVisible(false) end) end
        return true          -- ★ "藏起来"就是这次要做的全部 ⇒ 算送达（不要重发）
      end
      -- ⚠️ 这里**不要用 `resolve_asset`** —— 它查不到会 `warn_once` 打**报错**，
      --    而"调色板里还没有 obj.* 素材"是**当前阶段的正常状态**（物件美术还没配），
      --    不该污染日志。直接查表，查不到就藏起来。
      local hit = nil
      do
        local map = self:read_palette()
        local key = tostring(value)
        hit = map[key]
      end
      if hit ~= nil and hit.id ~= nil then
        local src = nil
        pcall(function() src = o.imageSource end)
        if hit.source ~= nil then src = hit.source end
        pcall(function() o:SetImage(src, hit.id) end)
        if o.SetVisible then pcall(function() o:SetVisible(true) end) end
      else
        -- 没有物件（或名字解析不出来）→ **必须藏**，否则白板会盖住头像
        if o.SetVisible then pcall(function() o:SetVisible(false) end) end
      end
    end
  elseif key == "imageType" then
    -- ★★★ 2026-10-01：**强制图片的拉伸方式**（Basic = 按原始像素 / Stretch = 填满控件）。
    --
    --   背景（真机日志对比出来的）：
    --     正常工作的：  bg(visible=true type=Enum.ImageType.Stretch id=100108)
    --                   face(visible=true type=Enum.ImageType.Stretch id=106053)
    --     我克隆出来的：action.submit.hex1(visible=false type=Enum.ImageType.Basic id=100001)
    --   **Basic 就是"按原始像素铺"** —— 如果 `100001` 是 1×1，画出来就等于**看不见**。
    --   日志自己也提示过：「静态引用大多不支持拉伸 —— 需要拉伸的地方请选「底板」类素材；
    --   imageType 显示 Stretch 才说明这个素材支持，Basic 就只能按原样铺」。
    --
    -- ★★★★★ 2026-10-09 **下面这条结论【已被证伪】，留在这里当反面教材** ✗✓
    --   ⚠️ 原文（错 ✗）：
    --     「为什么要在脚本里设、而不是写进 `.gil`：`imageType` **不在存档记录里**
    --      （我把 wall.left / wall.right 逐字段比过，只差 id，没有任何 visible/imageType 差异）
    --      ⇒ 它是引擎按素材算出来的默认值 ⇒ 只能运行时改。」
    --   ★ 实测（2026-10-09 ✓，见 `tools/gil/fix_btn_bg_type.mjs`）：
    --     `imageType` **就在存档里** ✓，路径 = **`/505/503/84/504`**（紧挨着 imageSource / imageId ✓）
    --     · `229` 里 44 条带图片描述组的记录中，**5 条**写了它，取值**恒为 `1`**
    --     · 那 5 条**恰好**是本行上面引的那 5 条 `imageId=100108` 的记录 ✓
    --       ⇒ ★ **存档字节与真机日志对上了**（`type=Enum.ImageType.Stretch` ✓）
    --     · 官方枚举 `Basic=0 / Stretch=1`，proto3 省略 0 ⇒ `=1` 就是 `Stretch` ✓
    --   ★ **当年为什么没比出来** ✗：拿来比的是 `wall.left` / `wall.right`，
    --     而那两个**恰好都缺**这个叶子 ⇒ 那次比对**结构上就看不见它** ✓
    --     ⇒ ★ 又一个「抽样看不到 ≠ 不存在」✓（同一类错我在这个项目里犯过好几次 ✓）
    --   ⇒ ★ **两条路都通** ✓：存档能带（`234-四键图片类型拉伸.gil` 就是 ✓），运行时也能设（下面对 ✓）
    --     ⇒ 所以**下面这段保留**当第二道保险 ✓ —— 但**别再**说"只能运行时设"了 ✗
    --
    --   ⚠️⚠️ **2026-10-09 更正**：★ **别把 `imageType` 当成"没图"的原因** ✗
    --     用户实测否掉了：「**功能图标的图片形式就是基础**，而且大多数图片也只有基础一种，
    --     **基础和拉伸绝大多数情况下没有差别**」✓
    --     ⇒ ★ 我犯的是「**把相关当因果**」✗（有 `#504=1` ⇒ 那几条是 Stretch ✓
    --       但**不能**推出"Basic 就画不出来" ✗）✓
    --     ⇒ 四键"没图也没字"的**真因仍待查** ✓（见 `接手待办.md` ✓）
    --
    --   而 `imageType` 是**读写**字段（官方原文 ✓ `docs/api-cache/mhtakr07vej4.txt:1439-1442`），
    --   所以这里直接赋枚举值即可 ✓
    local want = nil
    pcall(function() want = value end)
    if want ~= nil then
      local enum = nil
      pcall(function() enum = Enum.ImageType[tostring(want)] end)
      if enum ~= nil then
        pcall(function() ctrl.imageType = enum end)
        -- 子控件（face/obj）也有 imageType，一起设，免得"设了父级没生效"
        local f = self:sub(id, "face")
        if f ~= nil then pcall(function() f.imageType = enum end) end
      end
    end
  elseif key == "image" then
    -- 头像/格面/物件图标：图片来自子控件 "face"
    --
    -- `value` 可以是两种：
    --   · 整数 ID（老写法，兼容）；
    --   · **调色板里的素材名**（字符串）—— 推荐写法，例如 "room.kitchen"。
    --     整数 ID 的难题（只读字段 + 不能手抄数字）由调色板解决：见 read_palette。
    local target = self:sub(id, "face") or ctrl
    if target ~= nil then
      -- ★★ 2026-09-27 修：**没有图时不要直接把 face 藏掉**。
      --
      -- 旧行为：`value == nil` → `SetVisible(false)`。后果很严重 ——
      --   格子的 `face` 在编辑器里**配了默认底图**（真机日志 `imageId=106053`），
      --   而空格的 view 里 `image = nil`（角色没配 portrait），于是**每次开局
      --   脚本都把底图藏了** → 玩家看到的是"格子什么都没有"。
      --   用户报的"文本图片都没有配备""放置没有视觉反馈"里有一部分就是这个。
      --
      -- 新行为：**记住第一次看到的图（编辑器配的默认图），并只在"我们换过图"之后
      --   才需要还原**。`value == nil` 时：换过 → 还原默认图；没换过 → 什么都不做。
      --   这样既不会留上一张残图，也不会把编辑器配好的底图抹掉。
      self._face_def = self._face_def or {}
      local d = self._face_def[id]
      if d == nil then
        d = { src = nil, id = nil, visible = true }
        pcall(function() d.src = target.imageSource end)
        pcall(function() d.id = target.imageId end)
        pcall(function() d.visible = target.visible end)
        self._face_def[id] = d
      end

      -- ★★ 2026-09-28：`false` 是 ui_controller 约定的「这格没有人」哨兵。
      --   为什么需要它：渲染循环是 `for k, v in pairs(n)`，
      --   **Lua 里 `image = nil` 等于"这个键不存在"** ⇒ 人走了的格子**永远不会下发 image**
      --   ⇒ 旧格的头像**永远不清**（用户报的「换位后头像卡残留」）。
      --   这和 `obj` 白块是**同一个 bug 形状** —— 我在同一个坑里摔了两次，
      --   所以现在两个值都统一用 `false` 当哨兵。
      if value == false then value = nil end
      if value == nil then
        if d.swapped then                       -- 只有"换过图"才需要还原，避免留残图
          if target.SetImage and d.id ~= nil then
            pcall(function() target:SetImage(d.src, d.id) end)
          end
          d.swapped = false
        end
        -- 注意：这里**不再** SetVisible(false) —— 编辑器配的底图要留着
      elseif target.SetImage then
        local src = target.imageSource                 -- 默认沿用编辑器配好的来源
        local hit = self:resolve_asset(value)
        if hit ~= nil then
          if hit.source ~= nil then src = hit.source end   -- 调色板带了来源就用它的
          if hit.id ~= nil then
            local ok, err = pcall(function() target:SetImage(src, hit.id) end)
            if not ok then self:warn_once("setimage", "SetImage 失败：" .. tostring(err)) end
            d.swapped = true
          end
        end
        -- ★ 图片换上了还不够：face 子控件必须可见，否则玩家什么也看不到
        if target.SetVisible then pcall(function() target:SetVisible(true) end) end

        -- ★★ 「SetImage 之后 imageType 会不会变」的验证日志（`docs/未验证清单.md` 第 2 条）：
        --   控件的「图片类型」（基础/拉伸）是**控件级**属性；换上"功能图标"类素材后，
        --   可能保持 Stretch（头像铺满），也可能按新素材退回 Basic（小小一张居中）。
        --   `imageType` 是**读写**字段，所以**直接读回来打印**就行 ——
        --   比让用户盯着屏幕判断"铺满还是小小一张"可靠得多。
        if self.cfg.debug_image then
          local it = nil
          pcall(function() it = tostring(target.imageType) end)
          print(string.format("[murdoku] SetImage 后 `%s` 的 imageType = %s（Basic=按原始像素 / Stretch=填满）",
            tostring(id), tostring(it)))
        end
      end
    end

  -- ★ 每格四边的墙 / 门（靠固定子控件 + SetVisible 开关，不用为每格做模板）
  elseif key == "walls" then
    -- ★ 返回值直达上层：`_apply_edges` 只有在"本关真需要的边全都取到子控件"时才返回 true
    --   （见它内部 `missing_sub` 那段）。首帧子控件没就绪 ⇒ false ⇒ 界面层下一帧补发。
    return self:_apply_edges(id, "wall", value)

  elseif key == "doors" then
    return self:_apply_edges(id, "door", value)

  -- ★ 染色：`imageColor` 官方是 **读写**（ColorValue、Tweenable），
  --   所以"同底图 + 不同颜色区分区域"是零额外素材的做法。
  --   value 用 {r,g,b,a?}（0–255）；官方构造是全局函数 `Color(r,g,b,a?)`。
  elseif key == "tint" then
    local target = self:sub(id, "face") or ctrl
    if target ~= nil and type(value) == "table" then
      local r = tonumber(value.r or value[1]) or 255
      local g = tonumber(value.g or value[2]) or 255
      local b = tonumber(value.b or value[3]) or 255
      local a = value.a or value[4]
      local made = nil
      if type(Color) == "function" then
        if a ~= nil then made = Color(r, g, b, tonumber(a) or 255)
        else made = Color(r, g, b) end
      end
      if made ~= nil then
        local ok = pcall(function() target.imageColor = made end)
        if not ok then
          self:warn_once("tint", "设置 imageColor 失败（可能是 ColorValue 的构造方式不对）")
        end
      else
        -- ⚠️ 没有全局 `Color` **不是错误**，只是这个运行环境不支持染色
        --    （模拟器就没有它）。所以这里用 print 说一次，**不能走 printerr** ——
        --    模拟器有「运行期不得有错误日志」的断言，走 printerr 会把 8b/9 两步打挂。
        if not self._tint_no_color_noted then
          self._tint_no_color_noted = true
          if print then
            print("[murdoku] 环境没有全局函数 `Color`，染色跳过（不影响玩法）。"
              .. "官方文档里 ColorValue 由 `Color(r,g,b,a?)` 创建（0–255，a 可省略）。")
          end
        end
      end
    end

  elseif key == "visible" then
    -- ★★★★★ 2026-10-05 **要显示时，显式补一次 `SetActive(true)`** —— 社区知识给的强候选根因。
    --
    --   来源：作者仓库 `client/lua-runtime/docs/observed-contract.md:7`（**真机**）。
    --   原文要点：`ClientUIBaseControl.active` 的**默认值三方不一致** ——
    --     · 官方加工稿写「默认为 `false`」；
    --     · 真机**未改过**的客户端模板实例为 `true`；明确设 `false` 的实例为 `false`；
    --     · 编辑器新建节点默认 `true`。
    --   ⇒ **手写控件树漏写 `active`，会比编辑器里新建的节点「少一层可见性」**，
    --     看起来就像「我改了 visible 又被改回去」。
    --
    --   我们这一侧的实测（可复现）：
    --     · `lua/ui_controller.lua` 里 `push({` 共 **80 处**，其中写 `active` 的 **0 处** ✗；
    --     · 本文件里 `SetActive` **只有一处**（销毁时的 `SetActive(false)`）⇒ **从不 `SetActive(true)`** ✗。
    --   ⇒ 规划节点是**手写**的（不是编辑器摆的），若被引擎按 `active=false` 处理，
    --     那么 `SetVisible(true)` 也**不显示** —— 这正是「门墙 / 网格列表项渲染不出来」的候选根因。
    --
    --   为什么只补 `value == true`：隐藏方向不需要补，而且 `SetActive(false)` 会**停掉子树脚本**
    --     （另一套语义，本项目已记录）⇒ 只在"要显示"时补，幂等、低风险 ✓
    --   ⚠️ 验收只能靠**真机截图（L3 层）**：离线模拟器不还原 active 的默认值差异 ✗
    if value == true and ctrl.SetActive ~= nil then
      pcall(function() ctrl:SetActive(true) end)
    end
    -- ★★★★ 2026-10-01 **隐藏要连子控件一起藏**（真机"点不动"的根因）。
    --
    --   真机排行榜（从 root 用 GetChildren 递归）显示选关页上还有：
    --        tray 300x182 / legend 300x63 / face 135x135 / content 135x135 x十几
    --   —— 全是**关卡内的东西**，而 content/face 是**格子模板自带的子控件**。
    --
    --   原因：`apply_screen_hide` 只把 `cell.1.1` 这类**格子本身**设成不可见，
    --   格子的子控件（content/face/text/obj/wall…）是**模板实例化**带出来的，
    --   脚本从没设过它们的 visible => 它们一直显示着，铺在棋盘位置上，
    --   而 `cell.*` 自己绑了点击 => **射线被格子接走，选关卡片收不到**。
    --
    --   规则：隐藏时**递归隐藏所有子控件**；显示时同样递归显示
    --   （格子的子控件本来就该跟着格子走，各自显隐由格子状态渲染另行覆盖）。
    --   枚举用 GetChildren()（项目里已验证可用）。
    local vis = value and true or false
    if ctrl.SetVisible then pcall(function() ctrl:SetVisible(vis) end) end
    -- ★ 记一份"当前被隐藏的 id"，交给每帧的 enforce_hidden_subtrees 兜底。
    --   为什么要兜底：渲染**只在属性变化时**才下发（same_value 缓存）
    --   ⇒ `cell.1.1` 的 visible=false 只在第一帧下发过一次，
    --   而格子的子控件（content/face/…）是模板**之后**才实例化出来的
    --   ⇒ 那一次递归隐藏根本没赶上它们（真机排行榜里 face/content 依然可见）。
    self._hidden_ids = self._hidden_ids or {}
    if vis then self._hidden_ids[id] = nil else self._hidden_ids[id] = true end
    -- ★★★★★ 2026-10-05 **可见性真的被脚本改了 ⇒ 兜底隐藏这一帧必须重跑一次。**
    --
    --   这是 `enforce_hidden_subtrees` 从"每帧扫"改成"事件驱动"之后的**主要触发源**
    --   （另外几个：切屏/换关、新建或销毁控件、收到光标事件 —— 见 `invalidate_lookups`
    --   和 `_fire`）。之所以在这里无条件置位而不去读 `ctrl.visible` 比较：
    --   界面层只在**属性值变了**才会走到这里（`same_value` 缓存），所以"进到这个分支"
    --   本身就已经是"可见性变了"的证据；置一个布尔比回读一次引擎属性便宜得多。
    self._subtree_dirty = true
    -- ⚠️ **只在"隐藏"时递归** —— 我第一版连"显示"也递归，结果把各控件
    --   自己藏起来的子控件又显示出来了（play_test 立刻报：
    --   棋盘的弹窗是隐藏的 / 此时没有指认面板 / 从存档点开始进关时 board=true home=true）。
    --   显示时不递归：子控件的显隐各有自己的负责人（格子渲染会逐个设
    --   face/note/x 的 visible），脚本不该越权替它们决定。
    -- ⚠️⚠️ 递归**只对 `cell.` 生效**。
    --   我第一版对所有控件递归隐藏 —— play_test 立刻红了三条
    --   （从存档点开始进关时 board=true home=true、选关页 home 没藏住、
    --     关卡内主页/选关没藏住）。说明"隐藏容器就递归隐藏子控件"会打乱
    --   各控件自己那套显隐责任划分。
    --   而**真正需要递归的只有格子**：`cell.N.M` 的子控件（content/face/text/obj/wall…）
    --   是**模板实例化**带出来的，脚本从不单独设它们的 visible
    --   ⇒ 格子藏了它们还亮着 ⇒ 铺在棋盘位置上 ⇒ 射线被格子接走。
    if vis == false and id:sub(1, 5) == "cell." then
      local function hide_kids(node, depth)
        if node == nil or depth > 4 then return end
        local kids = nil
        pcall(function() kids = node:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil then
              if k.SetVisible then pcall(function() k:SetVisible(false) end) end
              hide_kids(k, depth + 1)
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
    -- ★★★★★ 2026-10-06 **对称：格子重新可见时，把该亮的子控件放回来** ✗✓
    --
    --   ★ 这是用户复盘出来的那条 ✓（原话：「要么 PREFIX 里的 cell. 没重新删掉，
    --     要么合并的有问题」✓ —— **是合并引入了触发器** ✓）：
    --     · 上面那段递归【一直在】✗ —— ★ 但删掉 PREFIX 的 `"cell."` 之后
    --       **没人再写 `cell.* = false`** ✗ ⇒ ★ 它**从不触发** ✓（墙门正常 ✓）
    --     · 而把 `visible = (self.screen == nil)` 加进规划 ✗
    --       ⇒ ★ 主页时规划写 `cell.* = false` ✗ ⇒ **递归被重新触发** ✗
    --       ⇒ ★★ 子控件（`face` / `wall.*` / `door.*`）全灭 ⇒ **墙门又不见了** ✓✓
    --   ⇒ ★ 上面那段**只在隐藏时递归** ✗（它自己的注释也写着"显示时不递归"✓）
    --     ⇒ ★★ **单向** ✗ ⇒ 藏过的子控件**永远回不来** ✓✓
    --   ⇒ ★ 这里补上**对称的那一半** ✓：★ 格子变可见 ⇒
    --     · `face` 点亮 ✓（底图 ✓）
    --     · `wall.*` / `door.*` 按 `_edge_want` 恢复 ✓（★ 就是"该亮哪些边" ✓）
    --   ⚠️ 只在 `vis == true` **且**这一刻确实是格子的根时做 ✗（过渡时一次 ✓ 不是每帧 ✓）
    if vis == true and id:sub(1, 5) == "cell." then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.SetVisible ~= nil then
        pcall(function() face:SetVisible(true) end)
      end
      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil and s2.SetVisible ~= nil then
            pcall(function() s2:SetVisible(want) end)
          end
        end
      end
    end
  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end

  elseif key == "rect" and self.apply_rect then
    if ctrl.SetAnchoredPosition then ctrl:SetAnchoredPosition(value.x, value.y) end
    if ctrl.SetSizeDelta then ctrl:SetSizeDelta(value.w, value.h) end

  elseif key == "event" then
    -- 让增量渲染能把「同一条按钮换了事件」同步下来（配合 bind_input 的现查）
    --
    -- ★★★★★ 2026-10-05 **按「规划节点」记，不按控件 id**（这一条是「同 id 两个节点
    --   互相覆盖」的第二半，见 `Adapter.new` 里 `self.events` 那段）。
    --
    --   ⚠️ 2026-10-05 修：这两行原来用的是 **ASCII 双引号**（`"同 id …` / `互相覆盖"`）✗
    --      ⇒ 被 `tools/lua_quote_scan.ps1`（check_all 步骤 **2g**）判红 ✓
    --      —— 判据很硬：**该行的 ASCII 双引号个数为奇数** ✓（这里是 1 个 ✗）
    --      在 `--` 注释里暂时无害 ✓ 但**同一个写法一旦落进字符串**就会让字符串提前结束 ✗
    --      ⇒ 语法错误，而且**报错行号指向别处** ⇒ 极难一眼看出 ✓（本项目踩过 4 次 ✓）
    --      ⇒ 规矩：中文引号一律用 **「」** ✓ 不要用 ASCII 的英文引号字符 ✗
    --      ⚠️ 连"举反例"都不行 ✓ —— 我第一版修复里为了说明这件事，
    --         在注释里把那个字符**打了出来** ⇒ 扫描器**照样判红** ✗✓
    --         （判据只数"该行 ASCII 双引号是不是奇数"，**不看语境** ✓）
    --         ⇒ 要提它时：**描述**（如"英文引号字符"）✓ 不要**写出它** ✗
    --
    --   旧写法：
    --       local h = self.handlers[id]
    --       if h == nil then h = {}; self.handlers[id] = h end
    --       h.event = value
    --   ⇒ 一份表、两个节点轮流写：`action.back` 的 `topbar` 节点先写 `back_confirm`、
    --     `right` 节点紧接着写 `back` ⇒ **前者静默消失**（不报错）。
    --   ⇒ 现在每个规划节点各占一格；`nkey` 由渲染循环算好传进来（**复用**属性账本那把
    --     `node_key`，不在这里另造）。
    --   ⚠️ `nkey == nil` 时退回按 id —— 兼容旧调用方（例如 `main.lua` 里
    --      `bind_input("selbtn.N", {...})` 那条路，以及离线假适配器/老测试）。
    local k = nkey or id
    self.events[k] = value
    -- ★★★★★ 2026-10-05 **B2（用户拍板 ✓）：认领者赢 —— 只认第一次。**
    --   `event_claim[id]` = **第一个**给这个控件写过事件的规划节点 = 这颗控件的语义归属者
    --   （理由与三条硬证据见 `Adapter.new` 里 `self.event_claim` 那段）。
    --   ⚠️⚠️ 这里**必须是 `== nil` 判断**（"只认第一次"）：后写的节点**不许换人** ✗
    --     —— 一旦写成无条件赋值，就等于退回"最后写的赢"（B2 要修的就是这个 ✗）。
    if self.event_claim[id] == nil then self.event_claim[id] = k end
    -- ⚠️ 诊断用（**不再是派发依据**）：这个控件最近一次被哪个节点写过事件。
    --   `topbar` 与 `right` 写的是**同一个控件**，所以它记的是"最后那份"（`right`）。
    self.event_latest[id] = k

  elseif key == "rect" then
    -- ★★★ 2026-09-29：**编辑器优先 —— 不再覆盖你已经调好的控件几何**。
    --
    --   用户反馈「加入的文本与我调整的布局未完整生效」。
    --   根因：`M.LAYOUT` 里的坐标是我**当初规划时写的**，而用户在编辑器里
    --   把按钮的尺寸/位置都改过（例如 `action.hint` 的 bg 从 90×52 改成 97×43、
    --   label 改成 59×40）。脚本每次渲染都按自己的表把位置尺寸推下去
    --   ⇒ **用户的调整被无声地覆盖**。
    --
    --   新规则：
    --     · **运行时由脚本生成的控件**（格子等）→ 仍由脚本摆位置
    --       （它们本来就不在存档里，没有"编辑器几何"可言）。
    --     · **存档里已有的控件** → 保持编辑器里的几何，脚本不碰。
    --   `cfg.respect_editor_rect = false` 可关掉此行为（回到"布局全由代码说了算"）。
    --
    --   注意：行标/列标、头像卡另有 `apply_ruler_layout` / `apply_tray_layout`
    --   直接写位置，不受这里影响（那两条本来就是运行时重排）。
    --
    -- ★★★ 2026-09-30：`runtime_rect` 是**只影响这一处**的独立标记。
    --
    --   为什么不能复用 `instantiated`：那个标记还管着"**允不允许销毁控件**"
    --   （见隐藏分支：`instantiated[id]` 为真时会调 `DestroyClientUIControl`）。
    --   我第一版复用它 —— 结果房间名标签 / 选卡色块被当成"脚本建的"，
    --   某次渲染里它们短暂不可见 ⇒ 被判为"该隐藏" ⇒ **真销毁了** ⇒ 再也回不来
    --   （测试报"可见色块 0 块"，而单独探针在别的时点看是 3 块 ——
    --     这个"两处看到的不一样"就是销毁的证据）。
    --   ⇒ 挪到独立标记：**只跳过 `respect_editor_rect`，不碰销毁语义**。
    if self.cfg.respect_editor_rect ~= false
       and not (self.instantiated and self.instantiated[id])
       and not (self.runtime_rect and self.runtime_rect[id]) then
      -- ★ 这是**故意的空操作**（"位置归编辑器管"）⇒ 算送达，否则这个属性会被反复重发。
      return true
    end

    -- ⚠️⚠️ 2026-09-28：这一段是**事故后重建**的。
    --   我在加 ruler 漂移检测时误删了函数体，而工程没有 git、没有备份 ——
    --   只能按现有代码里的换算规则重建。**务必以模拟器/真机的实际渲染为准**。
    --
    -- 换算规则（依据：官方「位置」两套规则 + `apply_tray_layout` 里已验证可用的写法）：
    --   · `rect` 是**设计坐标**（1920×1080，**左上原点**，见 ui_controller 的 rect_of）
    --   · 引擎要的是**相对父级中心**的偏移，且 **Y 轴向上**
    --   ⇒ 先设计→画布（乘 scale），再把"左上原点"翻成"Y 向上"，最后减去父级中心
    local sc = self.cfg.scale or (5 / 6)
    -- ⚠️ 必须**取整**：规划里的画布尺寸是 `round(设计 * scale)`（例如 812 → 677），
    --   而我第一版直接留浮点（676.666…）—— 结果 `cell_geometry` 按 676.67 算格子，
    --   比规划少 1px（124.17 而不是 124），选关测试因此报红。
    --   **同一组数字在两处出现就必须用同一种取整**。
    local function R(v) return math.floor((v or 0) + 0.5) end
    local w = R((value.w or 0) * sc)
    local h = R((value.h or 0) * sc)
    local cx = R(((value.x or 0) + (value.w or 0) * 0.5) * sc)
    local cyTop = R(((value.y or 0) + (value.h or 0) * 0.5) * sc)   -- 画布坐标，从上往下
    local ch = self.cfg.canvas_h or 900
    local cy = ch - cyTop                                            -- 翻成 Y 向上

    self.rects = self.rects or {}
    self.rects[id] = { cx = cx, cy = cy, w = w, h = h }

    -- ★★ 父级中心怎么来：**从父节点自己的 `rect` 算**，而不是读"运行时已经摆过没有"。
    --
    --   为什么：`rect` 是**设计绝对坐标**，父级中心可以直接由它的 `rect` 推出 ——
    --   完全不依赖渲染顺序。而"读运行时位置"要求父级**先**被摆过，
    --   一旦顺序不巧（或父级这帧没推 rect），子级就会按画布中心算 ⇒ **整块跑到画布外**。
    --
    --   事故记录：我重建这一段时先用 `cfg.parent_of`（本工程里并不存在这个表）⇒ 取到 nil
    --   ⇒ 所有子控件都相对画布中心摆放 ⇒ **头像卡直接消失**（用户报"你把人物卡弄没了"）。
    --   父节点就在 `self.handlers[pid]` 里（`create_control` 时存下的），它自带 `rect`。
    local h_node = self.handlers and self.handlers[id] or nil
    local pid = (h_node and h_node.parent)
      or (self.cfg.parent_of and self.cfg.parent_of[id]) or nil
    local pcx, pcy = nil, nil
    local p_node = (pid ~= nil and self.handlers ~= nil) and self.handlers[pid] or nil
    if p_node ~= nil and p_node.rect ~= nil then
      local pr = p_node.rect
      pcx = R(((pr.x or 0) + (pr.w or 0) * 0.5) * sc)
      pcy = ch - R(((pr.y or 0) + (pr.h or 0) * 0.5) * sc)
    end
    -- 兜底①：父级还没落过 rect，但已经摆过运行时位置 → 用运行时中心
    if pcx == nil and pid ~= nil and self.rects[pid] ~= nil then
      pcx, pcy = self.rects[pid].cx, self.rects[pid].cy
    end
    -- 兜底②：根级控件（没有父）→ 画布中心
    if pcx == nil then
      pcx = R((self.cfg.canvas_w or 1600) * 0.5)
      pcy = R(ch * 0.5)
    end

    if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
    if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
    if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
    if ctrl.SetSizeDelta then pcall(function() ctrl:SetSizeDelta(w, h) end) end
    if ctrl.SetAnchoredPosition then
      pcall(function() ctrl:SetAnchoredPosition(cx - pcx, cy - pcy) end)
    end
  elseif key == "style" then
    -- 语义化样式：只做最小可感知反馈；正式外观请在编辑器里配控件视觉状态
    --
    -- ★ 已放置头像卡的着色值：`0x80FFFFFF` = **50% 透明白**。
    --   颜色在引擎里就是 **32 位整数**（真机日志 `fontColor=4294967295`），
    --   而 `Color()` 全局函数**不存在** —— 所以直接写整数，不走构造函数。
    --   `imageColor` 是**乘算着色**：乘白=不变色，乘半透明白=整体减淡 ⇒ 正是"减淡+加透明"。
    local PLACED_TINT = 2147483647
    local NORMAL_TINT = 4294967295      -- 0xFFFFFFFF：不透明白 = 还原
    -- ★★ 2026-09-28：缩放值**不再在这里写 if/elseif 链** —— 改查 `scale_of_style`。
    --
    --   为什么：原来这里设了 0.72，而 `apply_tray_layout`（头像卡重排）随后把姿态重置
    --   ⇒ **设了又被覆盖**，用户看到"已放置头像卡没有变小"。
    --   这与本工程反复出现的"同一件事两处实现"是同一类病
    --   （前面吃过：`erases` 动效、运行时上色 vs 存档静态图、自动 ✗ 的三处还原）。
    --   ⇒ 缩放表抽成**一个函数**，style 分支与重排函数共用，从根上不可能不一致。
    self._style = self._style or {}
    self._style[id] = value             -- 记住样式：重排函数要据此**重新施加**缩放
    local scale = self:scale_of_style(value)
    if scale and ctrl.SetLocalScale then ctrl:SetLocalScale(scale, scale, 1) end

    -- ★★★ 2026-09-30：**文字颜色**（线索卡的"人名标红"，见 `color_of_style` 的注释）。
    --   和缩放一样，颜色表也只定义一处 —— 避免"两个地方各写一份必然漂移"。
    local wantColor = self:color_of_style(value)
    if wantColor ~= nil and ctrl.fontColor ~= nil then
      pcall(function() ctrl.fontColor = wantColor end)
    end

    -- ★ 着色：**只有"已放置"才减淡**，其余状态一律还原成不透明白。
    --   不还原的话，取消放置后头像会一直是淡的（"调色"会粘住）。
    --   只对头像卡（`portrait*` 系列样式）做，避免影响线索/标签等其它用 style 的控件。
    if type(value) == "string" and string.sub(value, 1, 8) == "portrait" then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.imageColor ~= nil then
        local want = (value == "portrait.placed") and PLACED_TINT or NORMAL_TINT
        local okc, err = pcall(function() face.imageColor = want end)
        if not okc then
          self:warn_once("tint:" .. tostring(id), "头像卡调色失败（imageColor 可能不是整数）：" .. tostring(err))
        end
      end
    end

  elseif key == "notes" then
    -- ★★★★★ 2026-10-07 **铅笔笔记（清理版 ✓）** ✗✓
    --   ★ 用户已确认：★ **字母在格子中间居中显示** ✓ ⇒ 本轮**删掉所有临时脚本与探针** ✓
    --   ★ 六轮排障的结论（留在这里当知识 ✓ 以后别再重走）：
    --     ① ★ 取源表要取 **核心** `core.notes`（★ 键是徽章字母 ✓）；视图那份键是数字 ⇒ 会写成 `1` ✗
    --     ② ★ 适配器要**数组**（`table.concat`）⇒ 集合必须先转数组 ✗
    --     ③ ★ 要 `SetVisible` **且** `SetActive`（★ 本项目社区结论：少 active 会少一层可见性 ✓）
    --     ④ ★ 子控件被"置底"过 ⇒ **不透明的 `face` 会压住字** ✓ ⇒ 有笔记时提到最上 ✓
    --     ⑤ ★ 模板子控件**运行时尺寸可能为 0** ⇒ 那时引擎不画 ✓
    --        （★ 现已由**编辑器存档**给好尺寸/对齐/字号 ✓ 脚本**不再插手几何** ✓）
    local c = self:sub(id, "note")
    if c ~= nil then
      local txt = table.concat(value or {}, " ")
      if c.text ~= nil then c.text = txt end
      if type(c.SetText) == "function" then pcall(function() c:SetText(txt) end) end
      if c.SetVisible then pcall(function() c:SetVisible(txt ~= "") end) end
      if txt ~= "" then
        if c.SetActive then pcall(function() c:SetActive(true) end) end
        if c.SetAsLastSibling then pcall(function() c:SetAsLastSibling() end) end
        -- ★★★★★ 2026-10-07 **钉住位置 (0,0)（尺寸仍听编辑器）** ✗✓
        --   ★ 实测三次对比（★ 唯一能解释"时有时无"的一条 ✓）：
        --     · 脚本**同时**设了尺寸+位置 ⇒ ★ 字母出现 ✓（108×108 ✓ 108×36 ✓ 两轮都出现 ✓）
        --     · 脚本**只**用存档尺寸、**不设位置** ⇒ ★ 字不出现 ✗（两轮都如此 ✓）
        --   ⇒ ★ 结论：★ **存档里 `note` 的框在运行时【位置上不被沿用】** ✓（★ 飘到格子外 ⇒ 引擎不画 ✓）
        --     ★ 而 `face` 也是靠脚本 `SetAnchoredPosition(0,0)` 才铺满格子的 ✓（项目 L752 ✓）
        --   ⇒ ★ 所以位置【必须由脚本钉住】✓；★ **尺寸交给编辑器**（用户已调好 ✓）
        --     ★ 只有"运行时尺寸为 0"这种模板坑才兜一个中间条 ✓
        -- ★★★★★ 2026-10-07 **恒定设成"格子中间一条"（尺寸 + 位置都设）** ✗✓
        --   ★ 四轮实测收敛出的**唯一稳定解** ✓：
        --     · 存档给 `100×30`、脚本不设 ⇒ ★ **不画** ✗（两次 ✓）
        --     · 脚本设 `108×108` ⇒ ★ **画** ✓   脚本设 `108×36` ⇒ ★ **画且居中** ✓（你确认过 ✓）
        --     · 只钉位置、不设尺寸 ⇒ ★ **不画** ✗（刚验过 ✓）
        --   ⇒ ★ 结论：★ **这个控件必须由脚本给出"够大、穿过格子中部"的框，引擎才画** ✓
        --     （★ 存档里的框/位置在运行时都不被沿用 —— 与 `face` 同一个坑 ✓ 见项目 L745~752 ✓）
        --   ★ 现在：★ 宽 = 格子宽 ✓ 高 = 格子高 ÷ 3（下限 30）✓ 位置 (0,0) ✓
        --     ⇒ ★ 框正好穿过格子中间 ✓ **字号/对齐仍由编辑器决定** ✓
        local fw, fh = nil, nil
        pcall(function()
          local f = self:sub(id, "face")
          if f ~= nil then fw, fh = f:GetSizeDelta() end
        end)
        if fw ~= nil and fh ~= nil and fw > 1 and fh > 1 then
          local hbox = math.max(30, fh / 3)
          -- ★★★★★ 2026-10-07 **二次修正：脚本必须自己把框设回来** ✗✓
          --   ★ 用户的关键观察（★ 一针见血 ✓）：★ 运行时读到的 `100×30`
          --     ★ **和编辑器的任何一版都不一致**（★ 用户说旧值也是 `124×37` ✓）
          --     ⇒ ★ **说明有"第三方"在改这个文本框的尺寸**（★ 目前还没找到是谁 ✓）
          --   ⇒ ★ 结论：★ **不能指望编辑器 ✓ 也不能只设一次** ✓ ——
          --     ★ **脚本每次都把框设回"格子中间一条"** ✓（★ 这就是"二次修正"✓）
          --   ★ 值 ✓：★ 宽 = 格子宽 ✓ 高 = max(30, 格子高÷3) ✓ 位置 (0,0) ✓
          --     （★ 24 号字的行高 ≈ 36 ✓ 所以下限 30 时我按 36 给 ✓ 保证一行能装下 ✓）

        end
      end
    end
  elseif key == "x_mark" then
    local c = self:sub(id, "x")
    if c and c.SetVisible then c:SetVisible(value and true or false) end

  elseif key == "walls" or key == "doors" then
    local prefix = (key == "walls") and "wall." or "door."
    local dirs = { "up", "down", "left", "right" }
    for i = 1, #dirs do
      local c = self:sub(id, prefix .. dirs[i])
      if c and c.SetVisible then c:SetVisible((value and value[dirs[i]]) and true or false) end
    end
  end

  -- ★★★★★ 2026-10-05 **默认"送达成功"** —— 这条 `return true` 是上面那条契约的另一半：
  --   只有明确知道"没送到"的分支（`ctrl == nil`、文字无处可写、墙/门缺子控件）才返回 false，
  --   其余分支（tint / style / visible / image …）照旧一律算成功，**行为与改动前完全一致**。
  return true
end

----------------------------------------------------------------------------
-- 输入：只绑 CursorClick（双击由上层判定）
----------------------------------------------------------------------------

function Adapter:_fire(event, phase, data, src_id)
  -- ★★★★★ 2026-10-05 **收到光标事件 ⇒ 兜底隐藏重跑一次。**
  --
  --   为什么把"点击"也算成"树可能变了"：预设按钮的**状态节点**会引用子控件当外显样式
  --   （见 `Adapter:sub` 里那段官方文档引用）—— 按下/抬起会让引擎自己把某个子控件
  --   显示出来，而这件事**不经过脚本的 `set_property`**。
  --   原来靠每帧扫一遍兜住它；现在挂在输入事件上（人的手速，一帧最多几次，布尔赋值）。
  --   ⚠️ 这是"每帧扫"被去掉之后，**唯一**能兜住"引擎自己改显隐"的触发点，
  --      所以宁可多置一次位（一次 enforce ≈ 几百个节点），也不能漏。
  self._subtree_dirty = true
  if self.on_input == nil then return end
  local evt = {}
  for k, v in pairs(event) do evt[k] = v end
  evt.phase = phase
  if data and data.GetUIPos then
    local ok, x, y = pcall(function() return data:GetUIPos() end)
    if ok then evt.x, evt.y = x, y end
  end
  -- ★★★★★ 2026-10-05 **补格子坐标 `r` / `c`** —— 修「点了格子没反应」✗
  --
  --   根因（实测锁定 ✓）：界面层收事件的入口是
  --     · `ui_controller.lua:818-823`  `elseif a == "click" then self:on_cell_click(event.r, event.c)`
  --     · `ui_controller.lua:562-565`  `function Controller:on_cell_click(r, c) … core.grid[r][c]`
  --   ⇒ **界面层认格子靠的是 `event.r` / `event.c`，不是 x/y** ✗
  --   而 `_fire` 原来只做三件事：复制 `event` ✓ · 补 `phase` ✓ · 补 `x`/`y` ✓
  --   ⇒ ★ **从不补 `r`/`c`** ✗ ✓ 计划里也没有（`layout-plan.json` 实测 `"r"` / `"c"` 各 **0** 次 ✓）
  --   ⇒ 于是 `on_cell_click(nil, nil)` ⇒ `core.grid[nil]` ⇒
  --     **既不记笔记、也不放置、步数不动** ✗（模拟器实测：`8/13` 的 #2–#8 #13 + `13/13` 唯一红 ✓）
  --
  --   ★ 为什么在这里补：**`bind_input(id, node)` 本来就知道 `id`** ✓（L4405 ✓）
  --     而格子控件的命名就是 `cell.<行>.<列>` ✓ ⇒ 从 `id` 里解析出来 ✓
  --   ⚠️ **必须是数字** ✗ —— `core.grid[r][c]` 用字符串下标会拿到 nil ✗ ⇒ 用 `tonumber` ✓
  --   ⚠️ **不覆盖已有的 `r`/`c`** ✗ —— 若 `event` 自己带了（或将来引擎直接给 ✓）就以它为准 ✓
  --   ⚠️ **只认 `cell.<数字>.<数字>`** ✓ —— 其它控件（按钮/热区/线索卡 ✓）一律不碰 ✓
  if src_id ~= nil and evt.r == nil then
    local R, C = tostring(src_id):match("^cell%.(%d+)%.(%d+)$")
    if R ~= nil then
      evt.r = tonumber(R)
      evt.c = tonumber(C)
    end
  end
  self.on_input(evt)
end

----------------------------------------------------------------------------
-- 输入绑定：2D 平面操作，**同一套界面同时吃 PC 键鼠和移动端触碰**
--
-- 官方只有这几个光标事件（没有长按、没有右键）：
--   CursorDown / CursorUp / CursorClick / CursorEnter / CursorExit
--   CursorBeginDrag / CursorDrag / CursorEndDrag
--
-- 触摸屏上"点一下"同样会派发 Down→Up→Click，所以**鼠标点**和**手指点**
-- 走的是同一条路，不需要两套代码。这里额外绑 Down/Up 是为了：
--   · 自己合成**长按**（移动端比双击好按，双击还要担心系统双触缩放）
--   · 用"按下→抬起之间有没有移动"来区分"点"和"划"
--
-- 键盘（PC）用 AddKeyEventListener，属于**加分项**：
-- 取不到枚举时只是不绑定，鼠标照样能玩，不影响可用性。
----------------------------------------------------------------------------

local function make_cursor_data(x, y, press_x, press_y)
  return {
    x = x, y = y, pressX = press_x, pressY = press_y,
    GetUIPos = function() return x, y end,
    GetPressUIPos = function() return press_x, press_y end,
  }
end

-- 平台/设备：KeyboardAndMouse | Mobile | Controller | MobileController
function Adapter:device()
  if self._device ~= nil then return self._device end
  local name = "unknown"
  pcall(function()
    if game ~= nil and game.GetDevice ~= nil then
      local d = game.GetDevice()
      if d ~= nil then
        name = tostring(d.Name or d.FullName or d)
      end
    end
  end)
  self._device = name
  return name
end

-- 归一化成三种"操作档"，界面层按它决定提示文案
function Adapter:input_profile()
  local d = self:device()
  if d == "Mobile" or d == "MobileController" then return "touch" end
  if d == "Controller" then return "gamepad" end
  return "pc"        -- KeyboardAndMouse，以及拿不到设备时的兜底
end

function Adapter:bind_input(id, node)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if ctrl.AddCursorEventListener == nil then
    self:warn_once("nocursor:" .. tostring(id),
      "控件 " .. tostring(id) .. " 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）")
    return
  end
  self.bound = self.bound or {}
  if self.bound[id] then return end          -- 防重复绑定
  local click = E("CursorEventType.CursorClick")
  if click == nil then
    self:warn_once("noenum", "Enum.CursorEventType.CursorClick 缺失，无法绑定点击")
    return
  end
  self.bound[id] = true

  -- ★ 绑定自检（2026-09-27）：把"这条控件绑到了什么事件"打出来。
  --   起因：真机上点 `tray.V` 三次都毫无效果，而事件链路代码看着是通的。
  --   有了这行就能直接区分两种可能：
  --     · 事件 = suspect/V  → 事件绑对了，问题在逻辑层
  --     · 事件 = click/-    → 绑的是兜底事件（fallback），根本没拿到 node.event
  if self.cfg.debug_event ~= false then
    self._bind_seen = (self._bind_seen or 0) + 1
    if self._bind_seen <= 16 and print then
      local ev = node.event
      local what = "-"
      if ev ~= nil then
        if ev.id ~= nil then what = tostring(ev.id)
        elseif ev.r ~= nil then what = tostring(ev.r) .. "," .. tostring(ev.c)
        elseif ev.mode ~= nil then what = tostring(ev.mode) end
      end
      print("[murdoku] 绑定输入 `" .. tostring(id) .. "`  事件="
        .. (ev and tostring(ev.action) or "nil") .. "/" .. what)
    end
  end

  -- ★★ 关键：**事件要现查**，不要在绑定时捕获进闭包。
  --   同一条预设按钮在不同弹窗状态下要发不同事件（指认盗窃者 → 同伙是谁），
  --   而控件只创建/绑定一次；捕获写法会让第二次点谁都还在发旧事件。
  local function live_event()
    -- ★★★★★ 2026-10-05 **事件表搬到 `self.events[规划节点键]` 之后，现查要跟着改。**
    --
    --   旧写法读 `self.handlers[id].event`（那张表兼任事件表，已于本轮拆开）。
    --   照旧写会读到一个**再也不会被更新的**创建期快照 ⇒ 点了不对（静默）。
    --
    --   ★★ **取谁：`self.event_claim[id]` = 认领这颗控件的那个规划节点（第一个写的）** ★★
    --      —— **这就是 B2 的核心一行**（用户 2026-10-05 拍板 ✓）。
    --
    --      为什么不是 `self.event_latest[id]`（"最后写的"）：一个 id 只有一个引擎控件、
    --      只有一次绑定（`create_control` 按 id 建）⇒ **只能派发一份事件** ——
    --      所以"选哪一份"就是**这颗按钮到底是什么意思**的决定。
    --      计划里 `action.back` 有两个节点：`topbar`（「返回菜单」/ `back_confirm`，先写）
    --      与 `right`（「返回列表」/ `back`，后写）。取"最后写的" ⇒ 派发 `back` ⇒
    --      **鼠标点这颗按钮直接跳列表**，而左上那颗 ↰ 图标按 `back_confirm` **先弹 ✓/✗** ✗
    --      ⇒ 同一颗按钮、两种语义，差别只取决于"点的哪一颗"（`action.back` 还是 `hex.back`）
    --      ⇒ 这是**自相矛盾**，不是设计（三条硬证据见 `Adapter.new` 里 `self.event_claim`）。
    --      取"认领者" ⇒ 派发 `back_confirm` ⇒ **点击与 ↰ 一致，都先弹 ✓/✗** ✓
    --      （`ui_controller.lua:854` 收到 `back_confirm` ⇒ `self.pending = { action = "back" }`）。
    --
    --   ⚠️ 兜底顺序**保持不变**：认领者的那一份 → 绑定时的 `node.event` → `{ action = "click" }`。
    --      （认领者还没有时 —— 例如控件刚建出来、渲染还没轮到它 —— 仍按老路兜底 ✓）
    local k = self.event_claim[id]
    local cur = nil
    if k ~= nil then cur = self.events[k] end
    return cur or node.event or { action = "click" }
  end

  ctrl:AddCursorEventListener(click, function(data)
    -- ★ 「点击到底有没有到达脚本」必须能判定。
    --
    -- 用户 2026-09-27 报告"点击无反馈"，而当时日志里**完全看不出点击有没有到达脚本** ——
    -- 排查死角。这里在搭界面阶段把前几次点击打出来：
    --   · **看到**这行 → 点击到达了脚本，问题在后面（笔记/文本渲染、或游戏逻辑）
    --   · **看不到**这行 → 点击根本没到 → 查中间容器的
    --     「屏蔽区域内点击事件穿透」（`disableCursorEventPassthrough`）
    if self.cfg.debug_click ~= false then
      self._click_seen = (self._click_seen or 0) + 1
      if self._click_seen <= 8 and print then
        -- ★ 连**点击坐标**一起打（`CursorEventData:GetUIPos()`，官方：
        --   「以画布左下角为原点，获取当前屏幕 UI 坐标」）。
        --   为什么必须打：用户 2026-09-27 05:59 点的是"第2行第2列"，
        --   而事件报的是 `cell.2.4` —— 差了 2 列。有了坐标就能直接判断
        --   是"点错了"还是"命中矩形和画出来的位置不一致"。
        local xy = ""
        pcall(function()
          if data ~= nil and data.GetUIPos ~= nil then
            local x, y = data:GetUIPos()
            if type(x) == "number" then
              xy = string.format("  点击坐标=(%.0f, %.0f)", x, y)
            end
          end
        end)
        print("[murdoku] 收到点击 → 控件 `" .. tostring(id) .. "`（第 "
          .. self._click_seen .. " 次）" .. xy
          -- ★ 把**实际派发的事件**一起打（2026-09-27）：光知道"点击到了"不够，
          --   还要知道"派发的是什么事件" —— 因为 live_event() 有兜底
          --   `{action="click"}`，一旦没拿到 node.event 就会静默变成格子点击。
          .. "  事件=" .. tostring((live_event() or {}).action or "nil"))
      elseif self._click_seen == 9 and print then
        print("[murdoku] （点击日志到此为止，后面不再刷；cfg.debug_click = false 可关）")
      end
    end
    -- ★ 2026-10-05 **把控件 id 传下去** ✓ —— 格子点击要靠它解析出 `r`/`c`（见 `_fire` 里那段）✓
    --   `id` 是 `bind_input(id, node)` 的形参 ✓ 就在本闭包作用域里 ✓ 不需要额外查表 ✓
    self:_fire(live_event(), "click", data, id)
  end)

  -- 按下 / 抬起：界面层据此自己合成"长按"
  --
  -- ★★★★★ 2026-10-05 **必须把 `id` 一起传下去** ✗ —— 否则**长按抬起会崩** ✓
  --
  --   与 `click`（上面那条）是**同一个病**：界面层认格子靠的是 `event.r` / `event.c`
  --   （`ui_controller.lua:810/814` → `on_cell_down/on_cell_up(event.r, event.c, …)`），
  --   而 `_fire` 里**只有拿到 `src_id` 才**从 `cell.<行>.<列>` 解析出 `r`/`c` ✓。
  --
  --   不传 `id` 的实测反事实：`live_event()` 落到兜底 `{ action = "click" }` 时，
  --   down/up 两边的 `_press` 都成了 `{ r = nil, c = nil }` ⇒ `on_cell_down` 存进去、
  --   `on_cell_up` 取出来比 `dt` ⇒ **崩**：
  --     `murdoku_core.lua:1917: attempt to compare nil with number`
  --   （`_press.r`/`_press.c` 是 nil，长按判定那一步拿 nil 去比数字。）
  --
  --   `id` 就在 `bind_input(id, node)` 的形参作用域里 ✓（同一闭包，见上面 `click` 那条注释 ✓）。
  local down = E("CursorEventType.CursorDown")
  if down ~= nil then
    ctrl:AddCursorEventListener(down, function(data)
      self:_fire(live_event(), "down", data, id)
    end)
  end
  local up = E("CursorEventType.CursorUp")
  if up ~= nil then
    ctrl:AddCursorEventListener(up, function(data)
      self:_fire(live_event(), "up", data, id)
    end)
  end

  -- 拖动：按住期间移动。用它**当场**取消待判定的长按，不用等到抬起 ——
  -- 移动端上"按住想微调、结果落子了"就是这条救回来的。
  --
  -- ⚠️ 只绑 CursorDrag，**不绑 CursorBeginDrag**：
  --    官方枚举里确实有 BeginDrag / Drag / EndDrag 三个，但 BeginDrag 的语义是
  --    "开始可能成为拖动"，有些实现**一按下就发**。把它接成"取消长按"会让
  --    真机上长按彻底失效（而且模拟器发不出 drag，这个错查不出来）。
  --    CursorDrag 才是"已经在移动"，安全。EndDrag 与 Up 重复，不需要。
  --
  -- 界面层还会再比一次坐标位移（见 Controller:on_cell_drag），所以就算某个实现
  -- 在同一点狂发 Drag，也不会误取消。
  --
  -- ★★★★★ 2026-10-05 **`drag` 也要传 `id`** ✓ —— 和 down/up 同一条理由 ✓。
  --
  --   不传会**静默**丢掉这个功能（不崩，但等于没做 ✓）：
  --     `_fire` 拿不到 `src_id` ⇒ `evt.r`/`evt.c` 恒为 nil ✗
  --     ⇒ `on_input`（`ui_controller.lua:818`）转给 `on_cell_drag(nil, nil, x, y)` ✗
  --     ⇒ 函数第一句 `local p = self._press` 之后、`p.r ~= r or p.c ~= c` 那一比就
  --       **直接 return false** ⇒ 位移容差那几行**永远跑不到** ✗
  --     ⇒ 长按期间手抖/滑动**不会取消** ⇒ 移动端"按住想微调、结果落子了"又回来了 ✗
  --   （上面那段注释写的就是"这条救回来的"那个功能 —— 不传 id 等于把它悄悄删掉。）
  --   ⇒ ★ 传 `id` 之后 `r`/`c` 才解析得出来，位移判断才真的生效 ✓
  local drag = E("CursorEventType.CursorDrag")
  if drag ~= nil then
    ctrl:AddCursorEventListener(drag, function(data)
      self:_fire(live_event(), "drag", data, id)
    end)
  end
end

-- PC 键盘快捷键（可选）。绑定失败就算了，不影响鼠标/触摸。
--
-- ⚠️ 键位监听是**控件**的接口，不是 `script` 的：
--     `ctrl:AddKeyEventListener(key, cb)`（`RemoveKeyEventListener` / `RemoveKeyEventListeners` 同族）。
--     一开始我绑到 `script` 上了，结果永远绑不上（模拟器实测：
--     控件的方法表里有 AddKeyEventListener，Script 的方法表里没有）。
--     现在绑在 `cfg.key_control`（默认 "root"）上。
--
-- 键名的取法有三种可能（不同版本实现不一样），逐个试：
--   ① Enum.KeyboardKeyCode.<Name>   ② Enum.KeyCode.<Name>   ③ 直接传字符串
-- 一个都取不到就用字符串兜底；控件不支持就整体跳过（不是故障，记 info）。
--
-- 参数可以是：
--   · 数组 { "Up", "Space", "Return", ... }      —— 键名就是全部信息
--   · 或表 { Up = { action = "..." }, ... }      —— 需要为每个键带不同事件时用
function Adapter:bind_keys(spec, control_id)
  self.keymap = self.keymap or {}
  if game == nil then return 0, "没有 game 环境" end

  -- ── 候选控件：可以给一个名字，也可以给一串 ──────────────────────────────
  --
  -- ★ 2026-09-26 13:12 真机日志：补绑**还是**失败，而旧代码两种病因
  --   （"控件找不到" / "控件不支持按键事件"）打的是**同一句**被 warn_once 去重过的
  --   日志，所以第二次尝试完全静默 —— 只知道"没绑上"，不知道为什么。
  --
  --   而且真机上「容器节点到底支不支持 AddKeyEventListener」我们**没验过**
  --   （模拟器里所有控件都有这个方法，验不出来）。所以现在列一串候选：
  --   找到第一个**既能找到、又支持按键事件**的控件就用它。
  local names = {}
  local src = control_id or self.cfg.key_control or "root"
  if type(src) == "table" then
    for i = 1, #src do names[#names + 1] = tostring(src[i]) end
  else
    names[1] = tostring(src)
  end
  local extra = self.cfg.key_control_fallbacks
  if type(extra) == "table" then
    for i = 1, #extra do names[#names + 1] = tostring(extra[i]) end
  end

  local ctrl, used, why = nil, nil, {}
  for i = 1, #names do
    local c = self:find(names[i])
    if c == nil then
      why[#why + 1] = names[i] .. "=找不到"
    elseif c.AddKeyEventListener == nil then
      why[#why + 1] = names[i] .. "=不支持按键事件"
    else
      ctrl, used = c, names[i]
      break
    end
  end

  if ctrl == nil then
    -- **不在这里打印**：OnInit 阶段树是空的，绑不上属正常，在这里报就是误报
    -- （和 §9.2 那个"空树报成故障"是同一类错误）。
    -- 把原因返回给调用方，由它按阶段决定话术（entry 里 OnInit 说"稍后补绑"）。
    return 0, "候选控件都不中用：" .. table.concat(why, "；")
  end

  local list = {}
  if type(spec) == "table" then
    if #spec > 0 then
      for i = 1, #spec do list[#list + 1] = { tostring(spec[i]), {} } end
    else
      for k, v in pairs(spec) do list[#list + 1] = { tostring(k), v or {} } end
    end
  end

  local n, failed, unresolved = 0, 0, {}
  for i = 1, #list do
    local key_name, event = list[i][1], list[i][2]
    if self.keymap[key_name] == nil then
      -- ★★ 2026-09-26 真机日志查出来的**真 bug**：
      --   官方签名是 `AddKeyEventListener(eventType, callback)`，第一个参数是
      --   **`Enum.KeyEventType` 事件类型**（例如 `KeyboardCraftspersonKey1Down`
      --   = "键鼠：奇匠按键1（按下）"），**不是键码**。
      --   旧实现传的是 `Enum.KeyboardKeyCode.<名字>` / `Enum.KeyCode.<名字>` /
      --   裸字符串 —— 三者都不是合法的 eventType，于是**30 个调用全部抛错**，
      --   日志表现成"绑在 root 上，成功 0 个，失败 30 个"。
      --
      --   而且**取不到枚举时绝不能硬绑**（拿字符串当枚举必然抛），
      --   所以这里单独计一个 unresolved，并把它报出来。
      local et = E("KeyEventType." .. key_name)
      if et == nil then
        unresolved[#unresolved + 1] = key_name
      else
        -- ★ 2026-09-27：真机日志显示 **24/24 绑定成功，但按了 15 个键一行回调都没有**。
        --   为排除"看着像枚举、其实是字符串"（拿字符串硬绑也可能不抛错），
        --   把解析结果的**类型与值**打出来：真枚举应是 userdata/table，不是 string。
        if self.cfg.debug_key and print then
          self._key_dbg = (self._key_dbg or 0) + 1
          if self._key_dbg <= 4 then
            print("[murdoku] KeyEventType 解析：" .. key_name
              .. " -> type=" .. type(et) .. " 值=" .. tostring(et))
          end
        end
        local ok = pcall(function()
          ctrl:AddKeyEventListener(et, function()
            -- ★ 物理键映射验证用的日志（`docs/未验证清单.md` 第 1 条）：
            --   官方只给了「奇匠按键36 = ↑」这种说法，而**物理键到底触发哪个事件**
            --   只有真机能验，而且「奇匠按键」是可被玩家重映射的槽位。
            --   所以把**实际收到的键名**打出来 —— 这样验证就变成"按键 + 读日志"，
            --   不用靠"看棋盘上有没有高亮框"这种主观判断。
            if self.cfg.debug_key then
              print("[murdoku] 按键事件 → " .. tostring(key_name))
            end
            -- ★★★ 2026-09-30：**输入隔离的自检结论** —— 只在**第一次**按键时打一行，
            --   而且**不依赖 debug_key**（这条是验收结论，不是调试信息）。
            --
            --   为什么需要它：目标 ⑦ 要回答的是
            --   「给容器设了 `disableKeyEventPassthrough = true` 之后，
            --     脚本自己的 `AddKeyEventListener` 还收不收得到按键？」
            --   这个问题**只有真机能回答**（模拟器里这些字段根本不生效）。
            --   ⇒ 把验证做成"按一个快捷键 + 看日志"，而不是靠主观判断：
            --     看到这一行 ⇒ 屏蔽**没有**影响脚本自身的监听（最坏情况被排除）；
            --     看不到     ⇒ 屏蔽把键盘也挡住了 ⇒ 去掉 `main.lua` 里的 `seal_containers`，
            --                  或缩小到只用 `disableCursorEventPassthrough`（都是一行）。
            if not self._key_first_seen then
              self._key_first_seen = true
              if print then
                print("[murdoku] ✅ 键盘事件仍能收到（第一个键：" .. tostring(key_name)
                  .. "）—— 「屏蔽按键事件穿透」没有影响脚本自身的监听，目标⑦的疑问到此处排除。")
              end
            end
            if self.on_input ~= nil then
              local evt = {}
              for k, v in pairs(event) do evt[k] = v end
              evt.phase = "key"
              evt.key = key_name      -- 界面层按 `Enum.KeyEventType` 的**名字**分派
              self.on_input(evt)
            end
            -- ★★★★★ 2026-10-02 **不能返回 `true`**。
            --
            --   官方文档（docs/api-cache/mhtakr07vej4.txt:1379）：
            --     「AddKeyEventListener(eventType, callback) …… 回调返回 boolean；
            --       **同一个容器中，如果交互按键事件被 lua 回调响应，并标记为已处理，
            --       容器内的其他按键不会也响应此次按键事件**」
            --   ⇒ 返回 `true` = **把这次按键标记成"已处理"** ⇒ 后面的人收不到。
            --   而这里的监听绑在 **`root`** 上（日志：`绑在 root 上，成功 24 个`）——
            --   `root` 是**所有 UI 的祖先** ⇒ 它标记已处理之后，**游戏自己的功能收不到这个键**
            --   （用户实测：**原神自带的对话框按 Enter 打不开**，而且**首页就不行**）。
            --
            --   ⇒ 改成 `return false`：**"我没处理，请继续传"**。
            --     返回值只表示"是否已处理"，**不影响脚本自己收到事件**
            --     （日志里「✅ 键盘事件仍能收到」照样会出现）。
            return false
          end)
        end)
        if ok then n = n + 1 else failed = failed + 1 end
      end
    end
    self.keymap[key_name] = event
  end

  local note = "绑在 " .. tostring(used) .. " 上，成功 " .. n .. " 个"
  if failed > 0 then note = note .. "，失败 " .. failed .. " 个" end
  if #unresolved > 0 then
    note = note .. "；" .. #unresolved .. " 个键名取不到 Enum.KeyEventType："
      .. table.concat(unresolved, ", ")
  end
  return n, note
end

-- 键盘是否真的可用（要么绑成功过，要么收到过键盘事件）
function Adapter:keyboard_ready()
  if self.keymap ~= nil and next(self.keymap) ~= nil then return true end
  return false
end

----------------------------------------------------------------------------
-- 动效（TweenSequence 关键帧）+ 音效
--
-- 官方接口（已按实现核对）：
--   game.Tween(控件, {字段=值,...}, 时长) → Tween
--        :SetEase(Enum.EaseType.X) :SetRelative(bool) :SetLoops(n)
--        :Play() :Pause() :Resume() :Restart() :Complete() :Kill(bool)
--        :SetOnComplete(fn) :SetOnStepComplete(fn)
--   game.TweenSequence() → Seq
--        :Append(tween) :Join(tween) :AppendInterval(秒) :AppendCallback(fn)
--        :Insert(秒, tween) :InsertCallback(秒, fn) :Play() …
--
-- **可动的字段只有这些**（真机实现里的白名单，写别的没用）：
--   anchoredPositionX/Y、sizeDeltaX/Y、anchorMinX/Y、anchorMaxX/Y、
--   pivotX/Y、localScaleX/Y/Z、localRotationX/Y/Z
--
-- 所以：
--   · 缩放类 → localScaleX/Y
--   · 抖动类 → anchoredPositionX/Y（要**先记下基准值**，用绝对值做关键帧，
--     不能用 SetRelative 连续叠，否则一轮下来会累积偏移）
--   · 旋转类 → localRotationZ
----------------------------------------------------------------------------

-- 每个语义动效 = 一条关键帧时间线。
--   dur  总时长（秒）
--   ease Enum.EaseType 的名字（取不到就退回 Linear）
--   ch   通道：scale（默认）| pos_x | rot
--   keys { {t, v}, ... }，t 是 0..1 的归一化时间，v 是**绝对目标值**
--        （scale 的 1.0 = 原始大小；pos_x 的 0 = 原始位置）
local EFFECTS = {
  -- 落子：从小弹到略大再收回，最有"啪"的一声感
  pop_tile     = { dur = 0.26, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.62 }, { 0.55, 1.06 }, { 1.00, 1.00 } } },
  -- 铅笔笔记：轻轻一跳
  note_pop     = { dur = 0.14, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 0.90 }, { 1.00, 1.00 } } },
  -- X 标记 / 提示：脉冲
  pulse        = { dur = 0.18, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.50, 1.14 }, { 1.00, 1.00 } } },
  -- 选中头像卡：放大 + 一点点光晕感（用缩放近似）
  sel_pop_glow = { dur = 0.30, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.45, 1.12 }, { 0.70, 1.03 }, { 1.00, 1.00 } } },
  -- 撤销：闪一下
  undo_flash   = { dur = 0.16, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.05 }, { 1.00, 1.00 } } },
  -- 提交：顶一下
  submit_nudge = { dur = 0.28, ease = "OutCubic", ch = "scale",
                   keys = { { 0.00, 1.000 }, { 0.40, 1.035 }, { 1.00, 1.000 } } },
  -- 线索卡刷出来
  clue_box_pop = { dur = 0.22, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.82 }, { 0.60, 1.03 }, { 1.00, 1.00 } } },
  -- 破案：整块闪一下
  solved_flash = { dur = 0.36, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.40, 1.12 }, { 1.00, 1.00 } } },
  -- 擦除：缩到 0
  vanish       = { dur = 0.20, ease = "InQuad",   ch = "scale",
                   keys = { { 0.00, 1.00 }, { 1.00, 0.00 } } },
  -- 区域墙：轻微一缩（表示"这里隔断"）
  roomwall     = { dur = 0.14, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 0.98 }, { 1.00, 1.00 } } },
  -- 拒绝 / 错误：左右摇头
  shake        = { dur = 0.30, ease = "Linear",   ch = "pos_x",
                   keys = { { 0.00, 0 }, { 0.20, -8 }, { 0.45, 8 },
                            { 0.70, -5 }, { 1.00, 0 } } },
  -- 受害者头像从下往上"顶"出来（结算/揭示用）
  -- ⚠️ 这条曾经是**空转**的：ui_controller 里 M.EFFECTS.VICTIM = "portrait_slide_up"，
  --    但 EFFECTS 表里没有同名条目 → play_effect 第一行 spec==nil 就 return，
  --    不动也不报错。补上条目，同时给时间线加了 pos_y 通道（原先只有 pos_x）。
  portrait_slide_up = { dur = 0.34, ease = "OutBack", ch = "pos_y",
                   keys = { { 0.00, -34 }, { 0.70, 4 }, { 1.00, 0 } } },
}

-- 语义动效 → 音频 id。
-- ⚠️ 这些 id 是**占位**：音频 id 得在编辑器里查（音效资源），
--   查到之后直接改这张表即可，不用动别处。留 nil = 该动作不发声。
M.SOUNDS = {
  pop_tile     = nil,
  note_pop     = nil,
  pulse        = nil,
  sel_pop_glow = nil,
  undo_flash   = nil,
  submit_nudge = nil,
  clue_box_pop = nil,
  solved_flash = nil,
  vanish       = nil,
  roomwall     = nil,
  shake        = nil,
  portrait_slide_up = nil,
}

function Adapter:ease_of(name)
  if name == nil then return nil end
  local e = E("EaseType." .. tostring(name))
  if e == nil then e = E("EaseType.Linear") end
  return e
end

-- 读一个控件当前的缩放/位置，作为动效的基准
local function read_pose(ctrl)
  local pose = { sx = 1, sy = 1, ax = 0, ay = 0, rz = 0 }
  if ctrl == nil then return pose end
  pcall(function() if ctrl.localScaleX then pose.sx = ctrl.localScaleX end end)
  pcall(function() if ctrl.localScaleY then pose.sy = ctrl.localScaleY end end)
  pcall(function() if ctrl.anchoredPositionX then pose.ax = ctrl.anchoredPositionX end end)
  pcall(function() if ctrl.anchoredPositionY then pose.ay = ctrl.anchoredPositionY end end)
  pcall(function() if ctrl.localRotationZ then pose.rz = ctrl.localRotationZ end end)
  return pose
end

-- 把一条关键帧时间线变成一串 Tween，接进 Sequence
local function build_timeline(adapter, ctrl, spec, base)
  local keys = spec.keys
  local n = #keys
  if n < 2 then return {} end
  local ease = adapter:ease_of(spec.ease)
  local ch = spec.ch or "scale"
  local list = {}
  for i = 1, n - 1 do
    local t0, v0 = keys[i][1], keys[i][2]
    local t1, v1 = keys[i + 1][1], keys[i + 1][2]
    local seg = (t1 - t0) * spec.dur
    if seg <= 0 then seg = 0.01 end
    local props
    if ch == "pos_x" then
      props = { anchoredPositionX = base.ax + v1 }
    elseif ch == "pos_y" then
      -- 画布空间 Y 向上，v1 为"相对基准位置的纵向偏移"，正数 = 往上
      props = { anchoredPositionY = base.ay + v1 }
    elseif ch == "rot" then
      props = { localRotationZ = base.rz + v1 }
    else
      props = { localScaleX = v1, localScaleY = v1 }
    end
    list[#list + 1] = { props = props, seg = seg, ease = ease }
  end
  return list
end

function Adapter:play_effect(id, effect_name, params)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if game == nil or game.Tween == nil then return end
  local spec = EFFECTS[effect_name]
  if spec == nil then
    -- 不要静默返回：语义名写错或漏配时必须看得出来。
    -- portrait_slide_up 就是这么"空转"了很久 —— 界面层在调、适配器当没听见。
    self:warn_once("nomotion:" .. tostring(effect_name),
      "没有这条动效定义：" .. tostring(effect_name)
      .. "（核对 EFFECTS 表与 ui_controller 里 M.EFFECTS 的名字）")
    return
  end

  local base = read_pose(ctrl)
  local segs = build_timeline(self, ctrl, spec, base)

  -- ① 优先用 TweenSequence：关键帧**按顺序**播（旧实现是同时起 3 个 tween，全叠在一起）
  local ok = pcall(function()
    local seq = game.TweenSequence and game.TweenSequence()
    if seq == nil or seq.Append == nil then error("no sequence") end
    local added = 0
    for i = 1, #segs do
      local t = game.Tween(ctrl, segs[i].props, segs[i].seg)
      if t ~= nil then
        if t.SetEase and segs[i].ease then pcall(function() t:SetEase(segs[i].ease) end) end
        seq:Append(t)
        added = added + 1
      end
    end
    if added == 0 then error("no tween") end
    seq:Play()
    -- 动完把姿态还原（vanish 那种会缩到 0，不还原下次就"消失"了）
    if seq.SetOnComplete then
      pcall(function()
        seq:SetOnComplete(function()
          pcall(function()
            ctrl.localScaleX, ctrl.localScaleY = base.sx, base.sy
            ctrl.anchoredPositionX, ctrl.anchoredPositionY = base.ax, base.ay
            ctrl.localRotationZ = base.rz
          end)
        end)
      end)
    end
  end)

  -- ② 退化路径：没有 TweenSequence 就只播"最像"的那一段（至少有个反馈）
  if not ok and #segs > 0 then
    local pick = segs[1]
    for i = 1, #segs do
      if segs[i].props.localScaleX and segs[i].props.localScaleX ~= 1 then pick = segs[i] end
    end
    pcall(function()
      local t = game.Tween(ctrl, pick.props, pick.seg)
      if t ~= nil then
        if t.SetEase and pick.ease then pcall(function() t:SetEase(pick.ease) end) end
        t:Play()
      end
    end)
  end

  -- ③ 音效：语义动效名 → 音频 id（M.SOUNDS 里配，没配就不响）
  local aid = self.cfg.sounds and self.cfg.sounds[effect_name]
  if aid == nil and M.SOUNDS then aid = M.SOUNDS[effect_name] end
  if aid ~= nil then self:play_audio(aid) end
end

----------------------------------------------------------------------------
-- 计时器（没有 os 库，全部靠 OnUpdate 的 dt 累加）
----------------------------------------------------------------------------

function Adapter:now() return self.clock end

function Adapter:after(seconds, fn)
  local h = { at = self.clock + (seconds or 0), fn = fn }
  self.timers[#self.timers + 1] = h
  return h
end

function Adapter:cancel(handle)
  for i = 1, #self.timers do
    if self.timers[i] == handle then table.remove(self.timers, i) return true end
  end
  return false
end

-- 由客户端 OnUpdate(dt) 驱动
-- ★★★★ 2026-10-02 **兜底：把"被隐藏的控件"的整棵子树也压下去。**
--
--   真机排行榜证明：`face` / `content`（格子模板自带的子控件）在主页和选关页上
--   **依然可见** —— 它们铺在棋盘位置上，而 `cell.*` 自己绑了点击
--   ⇒ 射线被格子接走 ⇒ 选关卡片点不到 ⇒ 用户报"点不动"。
--
--   为什么不能只靠 visible 分支里的递归：渲染**只在属性值变化时**下发
--   （`same_value` 缓存），`cell.1.1` 的 visible=false 只在第一帧下发过一次，
--   而格子的子控件是模板**之后**才实例化出来的 —— 那一脚没赶上。
--   ⇒ 扫一遍"被标记为隐藏的控件"，幂等地把子树压下去。
--
-- ★★★★★ 2026-10-05 **它不再由 `on_tick` 每帧调用** —— 改成"树可能变了"才跑一次
--   （`self._subtree_dirty`，触发点见 `on_tick` 里那段注释）。
--   本函数自己负责把欠账标记清掉：**不管谁调它**（`on_tick` / 诊断 / 测试），
--   跑完这一趟账就算还了，不会再被下一帧重复触发。
function Adapter:enforce_hidden_subtrees()
  self._subtree_dirty = false
  local hid = self._hidden_ids
  if hid == nil then return end
  -- ★★★★★ 2026-10-09 **这里【漏了 `DECOR` 豁免】—— 这正是「四键有壳没图文」的真因** ✗✓✓
  --
  --   ★ 真机证据（用户 19:01 那份日志 ✓ 探针打印的）：
  --     ① 开局（`on_start` 之后立刻）：`bg visible=true   label visible=true`  ✓ **是好的** ✓
  --     ② 之后每次弹窗：           `bg visible=false  label visible=false` ✗ **被关掉了** ✓
  --     `GetSiblingIndex` 正常（`bg=0 label=1` ✓）⇒ ★ **不是被盖住，是被 SetVisible(false) 关的** ✓
  --
  --   ★ 机制（本函数 ✓）：对 `_hidden_ids` 里每个控件，把它的**直接子控件**和**孙子**
  --     **一律 `SetVisible(false)`** ✗ —— ★ **它只会隐藏，从不恢复** ✓
  --     ⇒ 四键（`modal.exit` 等）在弹窗关着时被记进 `_hidden_ids` ✓
  --       ⇒ 弹窗**打开**时父控件被显示 ✓ 但它的 `bg`/`label` **已经被这个函数关掉** ✗
  --       ⇒ ★ **只剩一个能点的空壳** —— 正是用户看到的现象 ✓✓
  --
  --   ★ 为什么是漏的 ✓：它的**姊妹函数** `hide_unlisted` **有** `DECOR` 豁免 ✓
  --     （L2320-2327 那段注释写得明明白白：★「**内层装饰控件一律不参与 `hide_unlisted`**」
  --       ★ 理由：「计划里只有**外层**名字 ⇒ 内层装饰名（`face`/`bg`/`label`/`backrop1`…）
  --         **永远不在计划里** ⇒ 每次都被当成'多余的旧控件'藏掉 ⇒ 用户看到'图片被藏住了'」✓）
  --     ⇒ ★ 而本函数是**同一件事的兜底版**，却**没把那条规则抄过来** ✗✓
  --       ⇒ 于是"内层装饰"照样被藏 ⇒ **`hide_unlisted` 那一侧的豁免形同虚设** ✓
  --
  --   ⇒ ★ 修法 = **把 `DECOR` 规则补到这一侧** ✓（与 L2326 的既定规则一致 ✓ 不是新发明）
  --   ⚠️ 只跳**内层装饰名** ✓ —— 其余子控件（真正该藏的旧控件）**照旧隐藏** ✓
  local function decor(nm)
    if nm == nil or nm == "" then return false end
    return DECOR[nm] == true
  end
  local function nameOf(c)
    local nm = nil
    pcall(function() nm = c.name end)
    return nm
  end
  for id in pairs(hid) do
    if true then   -- ★ 对所有"被隐藏的控件"都兜底（原来只对 cell. 生效，范围开小了）
      local c = self:find(id)
      if c ~= nil then
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              -- ★ 内层装饰（`bg`/`label`/`face`…）**不参与兜底隐藏** ✓
              if not decor(nameOf(k)) then
                pcall(function() k:SetVisible(false) end)
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                if type(kk) == "table" then
                  for j = 1, math.min(#kk, 32) do
                    if kk[j] ~= nil and kk[j].SetVisible and not decor(nameOf(kk[j])) then
                      pcall(function() kk[j]:SetVisible(false) end)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)
  local due = {}
  for i = #self.timers, 1, -1 do
    if self.timers[i].at <= self.clock then
      due[#due + 1] = self.timers[i]
      table.remove(self.timers, i)
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
  -- ★★★★★ 2026-10-05 **兜底隐藏改成"事件驱动"，不再每帧扫一遍。**
  --
  --   改之前（每帧无条件跑）：`tests/grid_cost.lua` 量到每一帧都要
  --     · 关卡内：`enforce_hidden_subtrees` 本身 39 次 `find` + 78 个 `GetChildren`；
  --     · 选关页 60 帧：`SetVisible` 15,660 次（**261 次/帧**）、`GetChildren` 6186 次/帧。
  --   而这一趟在所查的状态**没有任何变化**时是纯白跑 —— 它做的事是幂等的
  --   （把"已知该隐藏的容器"的子控件再压一次 false）。
  --   ⇒ 只在**树真的可能变了**的时候跑一次；触发点见 `_subtree_dirty` 的**五处**写法：
  --       · 脚本改了某个控件的 visible（`set_property` 的 visible 分支）
  --       · 切屏 / 换关 / 网格视窗 RefreshItems（`ui_controller` 调 `invalidate_lookups`）
  --       · 新建 / 销毁控件（`create_control` / `destroy_control`）
  --       · 收到光标事件（`_fire`：预设按钮的状态切换可能让引擎自己把子控件显示出来）
  --       · 「本该隐藏的名字」刚刚才被搜到（`_note_lookup_hit`，原来靠每帧扫才发现）
  --   安全性：它防的是"隐藏容器后来才实例化出来的子控件仍然可见"——这些子控件
  --   要么来自我们自己的实例化（create_control 触发），要么来自引擎在 RefreshItems
  --   里实例化列表项（sync_clue_grid 触发），要么来自引擎的状态切换（_fire 触发）。
  --   另外 `find` 一搜到"该隐藏的名字"就置位（`_note_lookup_hit`）—— 兜底不会漏。
  if self._subtree_dirty then
    pcall(function() self:enforce_hidden_subtrees() end)
  end
  return self.clock
end

----------------------------------------------------------------------------
-- 本地状态 / 存档
--   客户端脚本没有本地持久化接口；跨场景只能走 信号 → 服务器 → 局内存档
----------------------------------------------------------------------------

function Adapter:state(key, value)
  if value ~= nil then
    self.state[key] = value
    return value
  end
  local v = self.state[key]
  if v == nil and script and script.GetParam then
    v = script:GetParam(key)          -- 退回到编辑器里配置的脚本变量
  end
  return v
end

function Adapter:_save_params(value)
  if type(value) ~= "table" then return { tostring(value) } end
  return {
    tostring(value.level_id or ""),
    tostring(value.state_code or ""),
    tonumber(value.moves) or 0,
    tonumber(value.elapsed) or 0,
    value.solved and true or false,
  }
end

function Adapter:save(key, value)
  self.state[key] = value
  self:signal_emit(self.signals.SAVE, self:_save_params(value))
  return true
end

function Adapter:load(key)
  return self.state[key]
end

----------------------------------------------------------------------------
-- 信号
----------------------------------------------------------------------------

function Adapter:signal_emit(name, params)
  if game == nil or game.ServerSignal == nil then return false end
  local sig = game.ServerSignal(name)
  if sig == nil then return false end
  params = params or {}
  for i = 1, #params do
    local v = params[i]
    local tv = type(v)
    if tv == "number" then
      if v == math.floor(v) then sig:AddInt(v) else sig:AddFloat(v) end
    elseif tv == "string" then
      sig:AddString(v)
    elseif tv == "boolean" then
      sig:AddBool(v)
    else
      sig:AddString(tostring(v))
    end
  end
  sig:SendSignal()
  return true
end

function Adapter:signal_on(name, handler)
  if script == nil or script.RegisterServerSignalHandler == nil then return false end
  local schema = M.SIGNAL_SCHEMA[name]
  script:RegisterServerSignalHandler(name, function(sigName, params)
    local payload
    if schema and params then
      payload = {}
      for i = 1, #schema do payload[schema[i]] = params[i] end
    else
      payload = params or {}
    end
    handler(payload)
  end)
  return true
end

----------------------------------------------------------------------------
-- 其他
----------------------------------------------------------------------------

function Adapter:random_int(a, b)
  a, b = a or 1, b or 1
  if b < a then a, b = b, a end
  if math.random == nil then return a end
  return a + math.random(0, b - a)
end

function Adapter:play_audio(audio_id)
  if game and game.PlayAudio2D then return game.PlayAudio2D(audio_id) end
  return nil
end

function Adapter:get_text(text_map_id)
  if game and game.GetText then return game.GetText(text_map_id) end
  return tostring(text_map_id)
end

----------------------------------------------------------------------------
-- 运行时能力自检
----------------------------------------------------------------------------

function M.capabilities()
  local has_game = (type(game) == "table")
  local has_script = (type(script) == "table")
  local rows, missing = {}, {}

  local function check(label, ok)
    rows[#rows + 1] = string.format("%-36s %s", label, ok and "OK" or "缺失")
    if not ok then missing[#missing + 1] = label end
  end

  check("game 全局表", has_game)
  check("game.GetClientUIRoots", has_game and type(game.GetClientUIRoots) == "function")
  check("game.FindClientUIRoot", has_game and type(game.FindClientUIRoot) == "function")
  check("game.GetClientUIControl", has_game and type(game.GetClientUIControl) == "function")
  check("game.InstantiateClientUIControl", has_game and type(game.InstantiateClientUIControl) == "function")
  check("game.Tween", has_game and type(game.Tween) == "function")
  check("game.TweenSequence", has_game and type(game.TweenSequence) == "function")
  check("game.ServerSignal", has_game and type(game.ServerSignal) == "function")
  check("game.PlayAudio2D", has_game and type(game.PlayAudio2D) == "function")
  check("game.GetText", has_game and type(game.GetText) == "function")
  check("game.GetUICanvasSize", has_game and type(game.GetUICanvasSize) == "function")
  check("Enum.CursorEventType.CursorClick", E("CursorEventType.CursorClick") ~= nil)
  check("Enum.ImageSource", E("ImageSource") ~= nil)
  check("script（当前脚本实例）", has_script)
  check("script:RegisterServerSignalHandler", has_script and type(script.RegisterServerSignalHandler) == "function")
  check("script:GetParam", has_script and type(script.GetParam) == "function")
  check("script:EnableUpdate", has_script and type(script.EnableUpdate) == "function")

  local text = "千星适配层运行时能力自检：\n" .. table.concat(rows, "\n")
  if #missing > 0 then text = text .. "\n\n缺失项：" .. table.concat(missing, "、") end
  return text, missing
end

-- ★★ 2026-09-28：`apply_button_labels` **放到文件最末尾**重新定义。
--
--   为什么搬：原来它定义在中段，语法上看是顶层，但实测
--   `M.Adapter.apply_button_labels == nil`（而同一位置的 `set_property` 存在）——
--   说明它被包在了某个 `do`/`local function` 里，**永远不会被赋值到 Adapter 上**。
--   放到 `return M` 前一行，**不可能再有嵌套**。
--
--   ⚠️ 现在它**没有调用方**（main.lua 走已验证的 `set_property` 路径），
--      保留它只为将来需要"批量重写按钮文字 + 读回校验"时有个现成入口。
function Adapter:apply_button_labels(labels)
  if labels == nil or print == nil then return 0 end
  local okN, miss, bad, shown = 0, 0, 0, 0
  local ids = {}
  for id in pairs(labels) do ids[#ids + 1] = id end
  table.sort(ids)
  for i = 1, #ids do
    local id, want = ids[i], labels[ids[i]]
    if type(want) == "string" and want ~= "" then
      local lb = nil
      pcall(function() lb = self:sub(id, "label") end)
      if lb == nil then
        miss = miss + 1
      else
        local wrote = pcall(function() lb.text = want end)
        local back = nil
        pcall(function() back = lb.text end)
        if wrote and back == want then okN = okN + 1 else bad = bad + 1 end
        if shown < 8 then
          print(string.format("  %s：想要 %q → 读回 %s", id, want, tostring(back)))
          shown = shown + 1
        end
      end
    end
  end
  print(string.format("[murdoku] 按钮文字：成功 %d，读回不一致 %d，找不到 label %d", okN, bad, miss))
  return okN
end

return M

end

__M["main"] = function()
--[[----------------------------------------------------------------------------
  main.lua —— 奇域入口：把 引擎核心 / 操作框架 / 适配层 串起来  v1.0.0

  入口由 lua/entry_client_script.lua 的官方生命周期回调调用：
    OnInit()      → Murdoku.prepare(adapter)
    OnStart()     → Murdoku.on_start(level_id, opts)
    OnUpdate(dt)  → Murdoku.on_update(dt)
    OnDestroy()   → Murdoku.on_destroy()

  信号参数采用**有序数组**（官方 ServerSignal 要求按顺序 Add*），
  收信号时按 engine_adapter_qianxing.SIGNAL_SCHEMA 还原成字典。
--]]--

local Core      = __require("murdoku_core")
local UIC       = __require("ui_controller")
local Adapters  = __require("engine_adapter")
local Qianxing  = __require("engine_adapter_qianxing")

local Levels = __require("levels.init")

local Murdoku = {}
Murdoku.__index = Murdoku
Murdoku.VERSION = "1.0.0"

local current = nil            -- 当前会话
local prepared_adapter = nil   -- OnInit 里建好的适配器
local signals_registered = false

-- ★★★★★ 2026-10-05 **「按屏同步运行时控件可见性」的三个记忆变量** —— 必须是
--   **文件级 local**（既不是全局 ✗，也不能声明在 `on_update` 里 ✗）。
--
--   为什么不能是全局（Round 67 那条 selene 告警是对的 ✓）：
--     真机/模拟器**共享同一张全局表** ⇒ 全局变量可能被别的脚本看到、也可能被踩。
--
--   为什么不能声明在 `on_update` **里面**（⚠️ 这里踩过一次）：
--     `on_update` 每帧被调用一次，函数内的 `local` **每次都重新初始化** ⇒
--     `murdoku_vis_key` 每帧都是 `nil` ⇒ `key ~= nil` **恒真**
--     ⇒ **强压窗口每帧重新开一次** ⇒ `forcing` 恒为 `true` ⇒
--     **稳态退化成"每帧无条件写 33 笔"**（实测 41.8 笔/帧，比改之前还差 ✗）。
--     ⇒ 「记忆」必须活在**两次调用之间**，所以只能放在文件级。
local murdoku_vis_memo = {}      -- 控件名 → 上次真的写下去的值
local murdoku_vis_force_to = 0   -- 强压窗口的截止帧号（> 当前帧 = 窗口内）
local murdoku_vis_key = nil      -- 上次的 "(屏, 关卡)" 键（一变就重新开窗）

-- ★★★★★ 2026-10-05 **网格视窗（官方「网格视窗」列表控件）—— 线索卡列表的正路**
--
--   用户已经在编辑器里把这块摆好了（核对存档 `193.1.gil`，事实如下，不再重复推导）：
--     · 网格视窗   id **1073742420**、名字 `clues.grid`、父 `clues`、400×544、局部 (20,20)
--     · 列表项模板 id **1073742421**（名 `clue`）、360×96，
--       子控件名 `clue.1.who` / `clue.1.what` / `clue.1.letter` / `clue.1.face` / `clue.1.backrop1/2`
--
--   ⇒ 界面层（ui_controller）负责"找控件 + 填内容 + 收点击 + 显隐"，
--     这里只提供**两个开关/索引**（数字与策略的唯一来源写在 main.lua，
--     界面层从 `adapter.cfg` 读 —— 两处各写一份必然漂移，本项目为此踩过多次）。
Murdoku.USE_GRID = true                  -- 默认开；false = 完全回到手写滚动（老路径）
Murdoku.GRID_ITEM_PREFAB = 1073742421    -- 列表项模板索引（存档核对：名 `clue`、360×96）

-- ★★★★★ 2026-10-04 **棋盘容器（`stage`）的几何 —— 全工程只此一处定义。**
--
--   依据：逐像素量 `docs/布局图-关卡内-v3.png`（1600×900，已经是画布空间）——
--     棋盘外框 x 608..1191 / y 138..721 ⇒ **584 × 584**，中心 (900, 470)（自下往上）
--   相对屏幕中心 (800, 450) 的偏移 = (900−800, 470−450) = **(100, 20)**。
--
--   ⚠️ 这两组数有**两处**要用：① 建控件**之前**（否则 `cell_geometry` 会读到 .gil 里的
--      1600×900，算出格子 171 —— 真机日志 `边缘适配 wall.up：目标 171x8` 就是这么来的）；
--      ② on_update 里每帧兜底。抽成常量就不会漂。
local BOARD_W, BOARD_H = 584, 584
local BOARD_X, BOARD_Y = 100, 20

function Murdoku.prepare(adapter)
  prepared_adapter = adapter
  return adapter
end

function Murdoku.current() return current end

-- ★★ 2026-09-28 新增：**统一渲染入口** —— 渲染完必然重做一次"行标/列标对齐"。
--
-- 为什么不能只在开机做一次：
--   `controller:render()` 会把 ruler 标签按**规划里的静态坐标**推下去
--   （那是设计期算的，和运行时 `cell_geometry` 算出的格子位置本来就对不上）。
--   所以每次渲染都会**把我对齐好的位置覆盖回去** ——
--   开机那一次对齐只在一瞬间有效，下一次状态变化就白做了。
--   ⇒ 把"渲染 + 对齐"绑成一个动作，就不会漏。
--
-- 证据：真机日志里开机那次 `核对：Δ=0` 是对的，而模拟器在若干次渲染后测出 Δ=16。
function Murdoku.render(force)
  if current == nil then return end
  current.controller:render(current.adapter, force)
  local a = current.adapter
  if a ~= nil and a.apply_ruler_layout ~= nil then
    local core = current.controller.core
    a:apply_ruler_layout((core and core.rows) or 5, (core and core.cols) or 5)
  end
end

----------------------------------------------------------------------------
-- 开局
----------------------------------------------------------------------------

function Murdoku.start(level_id, opts)
  opts = opts or {}
  local level = Levels.get(level_id or Levels.current_id())
  if not level then
    local msg = "找不到关卡：" .. tostring(level_id)
    if printerr then printerr("[murdoku] " .. msg) end
    return nil, msg
  end

  local core, errors = Core.new(level)
  if not core then
    local msg = "关卡数据有误：" .. table.concat(errors or {}, " / ")
    if printerr then printerr("[murdoku] " .. msg) end
    return nil, msg
  end

  local adapter = opts.adapter or prepared_adapter or Qianxing.new()
  prepared_adapter = adapter

  -- ★★★★★ 2026-10-05 **把网格视窗的配置写进适配器的 `cfg`**（界面层只读它）。
  --
  --   为什么不写进 `entry_client_script.lua` 的 `build_adapter()`：那一份是**打包入口**的
  --   静态配置表，而这两个值属于"本轮的界面策略"；写在这里还有个好处 ——
  --   测试/离线脚本只要走 `Murdoku.start` 就自动带上，不用各自复制一遍。
  --
  --   · `cfg.use_grid`         —— 开关（默认 true）。false ⇒ 界面层完全不碰网格视窗，
  --                               继续用现在这套手写滚动（▲▼ + 滚动条 + clue.N 卡片）。
  --   · `cfg.clues_grid_prefab` —— 列表项模板索引。界面层**不写死这个数字**，
  --                               取不到就当作"没配置"、悄悄走老路径。
  do
    local c = adapter.cfg
    if c ~= nil then
      if c.use_grid == nil then c.use_grid = Murdoku.USE_GRID end
      if c.clues_grid_prefab == nil then c.clues_grid_prefab = Murdoku.GRID_ITEM_PREFAB end
    end
  end

  -- 关卡清单交给界面层（界面层不认识 Levels 模块，只认这份数据）
  --
  -- ★★★ 2026-09-30：**改调 `Levels.ui_list()` —— 这份清单只能有一处定义**。
  --
  --   原来这里和 `tools/dump_layout.lua` **各写了一份**（都只复制 id/name/difficulty），
  --   后果有两个：
  --     · 选关卡片要显示「NxN　M名嫌疑人+1名受害人」（参考《派蒙的执律庭实习》）时
  --       **拿不到 size/suspects** ⇒ 界面上只剩关名
  --     · 两边各写一份 ⇒ **必然漂移**（本项目已因此踩过多次，这是同一类错误的第 N 次）
  --   ⇒ 统一到 `Levels.ui_list()`：卡片要 size/suspects，缩略图要 rooms/objects。
  --     界面层仍然"不认识 Levels"，只是拿一份摘要。
  local level_list = Levels.ui_list()

  -- ⚠️ 先声明再赋值：下面几个回调要在闭包里引用 controller 自己，
  --    而 `local x = f(...)` 里的 x 在构造器内还不存在（会变成全局 nil）。
  local controller

  -- 切到别的关卡：**不要再放一遍开屏教程**（玩家已经在游戏里了）
  local function start_other(id, why)
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.skip_intro = true
    o.debug = opts.debug
    -- ★★★ 2026-09-30：**切关必须清掉屏幕状态**。
    --
    --   上面那句 `for k, v in pairs(opts)` 会把 `opts.screen`（入口传的是 `"home"`）
    --   一并复制过来 ⇒ 新控制器带着 `screen = "home"` ⇒ **游戏界面被屏幕分支整片隐藏**
    --   ⇒ 表现成"切关之后指认面板弹不出来 / 点了像没反应"。
    --   我在探针里看到 `toast` 说提交成功、`modal` 却是 false，查了很久才定位到这里。
    --   ⇒ 规则：**"进入某个关卡" = 屏幕状态为空**，必须显式清掉，不能依赖默认值。
    o.screen = nil
    o.start_in_level = true
    local ok = Murdoku.start(id, o)
    if not ok then
      controller.toast = "切关失败：" .. tostring(why or id)
      controller.dirty = true
      Murdoku.flush_effects()
    end
    return ok
  end

  -- ★★★ 2026-09-29：**屏幕状态**（"home" 主页 / "select" 选关 / nil = 在关卡里）
  --
  --   ⚠️⚠️ 这一轮最大的教训，写在这里免得以后再犯：
  --     **官方生命周期 `OnStart()` 不接受参数**，入口是自己造 opts 表的
  --     （见 `entry_client_script.lua` 的 `Murdoku.on_start(FORCE_LEVEL, {...})`）。
  --     所以我最初想"让测试/调用方传 `start_in_level` 压过主页"是**完全无效的** ——
  --     参数根本到不了这里。表现是：模拟器里所有关卡内测试都被送进主页，
  --     而主页分支会连 `modal` 一起藏 ⇒ 症状伪装成"提交后不弹指认面板"，
  --     我为此改了三轮（`and/or` 陷阱、默认值、优先级）全是白费功夫。
  --   ⇒ **不要把力气花在"绕过主页"上，而是让测试真的走一遍主页流程**
  --     （`tools/sim/kit.mjs` 的 `enterLevel()`）。
  -- ★★★★★ 2026-10-05 **这一处已【回滚】** ✗✓ —— 我上一版把构造时的 `screen` 强制成 `nil`，
  --   结果★【打断了开局流程】✗：游戏一进来【直接就在第一关】✓（用户实测 ✓），
  --   而不是「主页 → 选关 → 关卡」✗ —— 所以回滚 ✓。
  --
  --   为什么当时那么改（以及它治错了什么）：
  --     · 症状：第一次进关时 `clues(vis=false)` ✗ ⇒ 线索区整片不显示 ✓
  --     · 原因：`screen` 判错成 `"home"` ✗ ⇒ `apply_screen_hide` 的 HIDE 名单生效 ✓
  --     · 我当时的改法：构造时不给 `screen` ✗ ⇒ `nil` = 【在关卡里】✗
  --       ⇒ ★ 治好了线索区 ✓ 但把"开局该在主页"这件事【一起跳过了】✗✗
  --   ⇒ ★ 教训：★ `screen` 只有【一个权威来源】✗ —— 谁真的切屏，谁才改它 ✓
  --     ★ 构造参数【不该】替玩家决定"现在在哪一屏"✗（那是流程的事 ✓）
  --     ★ 而"真的进了关卡 ⇒ screen = nil"这个兜底，**已经在下面两处**✓：
  --        · `on_pick_level` 里 `id ~= level.id` 那支（`start_other` 之后 ✓）
  --        · 同函数 `else` 那支（点的是当前这一关 ✓）
  --       ⇒ ★ 两条进关路径都置了 `nil` ✓ ⇒ 线索区不会再被藏 ✓✓
  local want_screen = nil
  if opts.screen ~= nil then want_screen = opts.screen end
  controller = UIC.new(core, {
    debug = opts.debug,
    skip_intro = (opts.skip_intro ~= false),   -- ★ 2026-10-08 恢复：**默认跳过开屏**（★ 显式传 false 仍可放开场 ✓）
    -- ★ 2026-10-08 **退出菜单要的两个回调**（★ 从提交 295 删掉的原文照抄恢复 ✓ adapter 只在这一层拿得到 ✓）
    --   ★ `on_save` ⇒ `Murdoku.save_now()` ✓ ★ `on_settle` ⇒ 先存档、再发 `SETTLE` 信号（带 level.id ✓）
    on_save = function()
      if Murdoku ~= nil and Murdoku.save_now ~= nil then pcall(function() Murdoku.save_now() end) end
    end,
    on_settle = function()
      if Murdoku ~= nil and Murdoku.save_now ~= nil then pcall(function() Murdoku.save_now() end) end
      if adapter ~= nil and adapter.signal_emit ~= nil then
        pcall(function() adapter:signal_emit(Qianxing.SIGNALS.SETTLE, { tostring(level.id) }) end)
      end
    end,
    levels = level_list,
    screen = want_screen,
    -- ★★★★★ 2026-10-05 **"格子要不要推 text"这一个开关**（每帧成本第 (4) 条）。
    --
    --   默认 **false = 不推**：真机日志原话「没有配的：**text** obj」——
    --   格子上根本没有文字子控件 ⇒ 每次写都必然失败 ⇒ 每关白跑 25 次 `find` +
    --   75 次 `set_property`，还把「属性补发…已停止补发」的前 5 条日志占满。
    --   （证据与取舍写在 `ui_controller.layout_plan` 里那条 `text = …` 上面。）
    --
    --   ⚠️ 留这个口的唯一目的：**将来给格子配了文字子控件时不用改代码** ——
    --      在 `entry_client_script.lua` 的 `cfg.cells` 里加一行 `push_text = true` 即可。
    --      取配置的规矩和别处一样：`cfg.cells.<名字>`（引擎适配层会把 `cfg.cells`
    --      里的调试开关上提到顶层，这里也照 `cfg.cells` 优先读）。
    push_cell_text = (adapter.cfg and adapter.cfg.cells
      and adapter.cfg.cells.push_text == true) or false,
    -- ★★★ 2026-09-30：**选关卡片要看的两样东西**（之前漏了，卡片永远显示"未开始"）
    --   · progress(id) —— 这一关打过没有 / 破了没有
    --   · last_level() —— 「从存档点开始」要接续的那一关
    --   两者都读局内存档，取不到就返回 nil，卡片只显示关名 —— **不编数据**。
    progress = function(lid) return Murdoku.progress_of(lid) end,
    last_level = function() return Murdoku.last_played() end,
    -- ★★★ 2026-09-30：**界面要知道"现在跑的是哪一关"** —— 棋盘上的**房间名标签**
    --   要按当前关卡的房间框来摆（房间框由 `Levels.ui_list()` 算好）。
    --   只传 id（字符串），界面层自己去那份 list 里找 —— 不把整个关卡表塞过去。
    current_level = tostring(level.id),
    -- 选关：直接从面板跳过去
    on_pick_level = function(id)
      -- ★ 记下"最近游玩"，供主页的「从存档点开始」用（要落盘，跨会话有效）
      Murdoku.remember_level(id)
      if id ~= level.id then
        start_other(id)
        -- ★★★★★ 2026-10-05 **重建出来的控制器必须【纠正屏幕状态】** ✗✓
        --
        --   症状（用户实测 + 两张截图 + 引擎侧体检读数 ✓）：
        --     · 在关卡里点【别的】关卡卡片 ⇒ ★ 回到棋盘时【只剩棋盘】✗
        --       线索区整片不见（`clues(vis=false)` 而 `clues.bg/grid(vis=true)` ✗）
        --     · 退出重进没用 ✗；点过一次别的关卡【之后】才正常 ✓
        --
        --   为什么：`start_other(id)` 会**重建控制器** ✗ ⇒ 新控制器从
        --     `UIC.new(..., { screen = want_screen })`（见上面 L190-196）拿到
        --     ★ `screen = opts.screen` = **入口传的 `"home"`** ✗✓
        --     ⇒ `apply_screen_hide(nodes, "home")` ⇒ HIDE 名单生效 ⇒
        --       ★ `clues` 被藏 ✗（`clues.bg` / `clues.grid` 自己是对的 ✓ 但父级藏了 ✗）
        --     ⇒ 而"进关卡后该显示"的那条路【永远走不到】✗（screen 一直是 "home" ✓）
        --
        --   ★ 所以这里必须补一句 —— 与下面"点的是当前这一关"那支（L228）**同一套写法** ✓
        --     （"同一件事两处实现必然漂移"是本项目反复踩到的病 ⇒ 两支都要写 ✓）
        if controller ~= nil then controller.screen = nil end
      else
        -- 点的是当前这一关：只是退出选关界面，不用重开
        controller.screen = nil
        controller.modal = nil
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    -- 返回列表：打开选关面板
    on_back = function()
      controller.modal = { kind = "levelselect" }
      controller.dirty = true
      Murdoku.flush_effects()
    end,
    on_next_level = opts.on_next_level or function()
      local nxt = Levels.next(level.id)
      if nxt then
        start_other(nxt)
      else
        -- 已经是最后一关：给个提示而不是静默无反应
        controller.toast = "已经是最后一关了"
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_solved = function(vm)
      -- 破案：把结算数据发给服务器（节点图侧接 关卡结算/排行榜）
      adapter:signal_emit(Qianxing.SIGNALS.SOLVED, {
        tostring(level.id),
        math.floor(vm.hud.time or 0),
        0,
        vm.hud.failed_accusations or 0,
      })
      -- ★★★ 2026-09-30：**记下"这一关破了"** —— 选关卡片要显示「★ 已破案」。
      --   之前只发了信号、没落盘 ⇒ 卡片永远显示"未开始"，
      --   玩家看不出自己打过哪几关（这正是「参考原作卡片选关」要看的信息）。
      Murdoku.mark_cleared(level.id)
    end,
  })

  local self = setmetatable({}, Murdoku)
  self.core = core
  self.level = level
  self.adapter = adapter
  self.controller = controller
  self.options = opts
  self.last_tick = 0
  -- 挂在模块上：离线测试（tests/entry_smoke.lua）要直接驱动适配层
  -- 验调色板/染色/墙门。生产环境无副作用，排查时也有用。
  Murdoku.__last = self

  -- 适配层的输入交给控制器，控制器产出特效后原地渲染
  adapter.on_input = function(event)
    controller:on_input(event)
    Murdoku.flush_effects()
  end

  -- 服务器信号（只注册一次）
  if not signals_registered then
    signals_registered = true
    adapter:signal_on(Qianxing.SIGNALS.RESTORE, function(payload)
      Murdoku.restore(payload)
    end)
    adapter:signal_on(Qianxing.SIGNALS.SYNC_STATE, function(payload)
      Murdoku.on_signal("murdoku/sync", payload)
    end)
  end

  -- 读档（本场景内缓存；跨场景由服务器把存档发回来）
  if opts.restore_save then
    local save = adapter:load("murdoku/save/" .. tostring(level.id))
    if type(save) == "table" then
      if save.state_code then
        core:decode_state(save.state_code)
      elseif save.cells then
        core:deserialize(save)
      end
      core:set_elapsed(save.elapsed or 0)
    end
  end

  current = self

  -- ① 先试着由脚本自己打开容器的「显示常驻光标」（门控 ②）。
  --    真机不开放这个字段时会静默失败，届时仍需在编辑器里手勾一次。
  if adapter.enable_cursor then
    local cur = adapter:enable_cursor()
    if cur > 0 and print then
      print("[murdoku] 已由脚本打开 " .. cur .. " 个容器的「显示常驻光标」")
    end
  end

  -- ★★★★★ 2026-10-04 **建控件之前，先把 `stage` 摆成棋盘尺寸。**
  --
  --   为什么必须在这里（而不是等 on_update）：`ensure_widgets` → `cell_geometry(n)`
  --   读的是**父级 `stage` 的实时尺寸**，而 `stage` 在 `.gil` 里是 **1600×900**。
  --   于是那一刻算出来的是：
  --       avail = min(1600,900) = 900 → area = 900−24 = 876 → pitch 175 → **格子 171**
  --   真机日志（16:35，v041）两条实证：
  --       `边缘适配 wall.up：基准 80x20 → 目标 171x8`      ← 墙按 171 的格子算
  --       占用排行里 25 个 `face 171x171`                    ← 底图也按 171 铺
  --   而 main.lua 把 stage 缩成 584 是在**之后的 on_update** 里 ⇒ 那一次算出来的
  --   格子/墙/底图尺寸**全是 171 系的**，只有格子控件自己的 sizeDelta 后来被改对了。
  --   ⇒ 在这里先摆好，on_update 里那份保留（当每帧兜底）。
  --
  --   ⚠️ 这里**故意不用 `adapter:find("stage")`**：`find` 未命中会**永久缓存 false**
  --      （适配器里早写明了这个坑），万一此刻树还没就绪，就会把 on_update 那条路也一起弄死。
  --      走 `root:GetChild("stage")` 现查，不带缓存。
  do
    local root = nil
    pcall(function() root = adapter:find("root") end)
    local s = nil
    if root ~= nil then pcall(function() s = root:GetChild("stage") end) end
    if s ~= nil then
      pcall(function() s:SetSizeDelta(BOARD_W, BOARD_H) end)
      pcall(function() s:SetAnchoredPosition(BOARD_X, BOARD_Y) end)
      if print then
        local w, h = nil, nil
        pcall(function() w, h = s:GetSizeDelta() end)
        print("[murdoku] 建控件前先摆好 stage：" .. tostring(w) .. "x" .. tostring(h)
          .. "（这样 cell_geometry 读到的就是 " .. tostring(BOARD_W) .. "）")
      end
    elseif print then
      print("[murdoku] ⚠️ 建控件前没找到 stage（root 底下没有）—— 格子几何会退回默认尺寸")
    end
  end

  -- ★★★★★ 2026-10-02 **用"脚本创建"重做选关按钮**（用户指定的路线）。
  --   真机证明只有脚本创建的控件能收到点击（关卡里的格子 ✅、编辑器摆的卡片 ❌）
  --   ⇒ 选关页改为用**同一个模板**在 `board` 下建按钮，点击走和格子一模一样的代码路径。
  --   数量取关卡数（不确定就按 8 个建，多余的藏起来）。
  do
    local n_levels = 8
    if Levels ~= nil and type(Levels.all) == "function" then
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    -- ★ 先无条件把"这个方法在不在"打出来 —— 上一版整段被 `if adapter.ensure_widgets then` 跳过、
    --   连一行日志都没有，害我又猜了一轮。**先把存在性打出来，再调用。**
    print("[murdoku] ensure_widgets 存在性：type=" .. type(adapter.ensure_widgets)
      .. "，n_levels=" .. tostring(n_levels))
    if adapter.ensure_widgets and not (adapter.cfg and adapter.cfg.widgets == false) then
      local made, err, existed = adapter:ensure_widgets(n_levels)
      print("[murdoku] 选关按钮（脚本创建）：新建 " .. tostring(made)
        .. " 个，已存在 " .. tostring(existed or 0) .. " 个"
        .. (err and ("　⚠️ " .. tostring(err)) or ""))
      -- 逐个绑点击 → ★ 用**和现有卡片一模一样**的事件写法：
      --     event = { action = "pick_level", id = <关卡 id> }
      --   上一版我编了个 `event = "pick/1"`（字符串）⇒ 日志里 `事件=nil/-`
      --   —— `bind_input` 读的是 `node.event.action`，字段名错了就整条绑成兜底事件。
      local ok_all, all = pcall(Levels.all)
      for i = 1, n_levels do
        local lv_id = nil
        if ok_all and type(all) == "table" and all[i] ~= nil then
          lv_id = all[i].id
        end
        adapter:bind_input("selbtn." .. tostring(i), {
          id = "selbtn." .. tostring(i),
          event = { action = "pick_level", id = lv_id },
        })
      end
    end
  end
  -- ② 用模板批量补齐棋盘格子（编辑器里已摆好的不会被动；没配 cfg.cells 就什么都不做）
  if adapter.ensure_cells then
    local made = adapter:ensure_cells(core.rows, core.cols)
    if made > 0 and print then
      print("[murdoku] 运行时生成了 " .. made .. " 个格子")
    end
  end

  -- ★ 2026-09-28：**上色名单从规划里取，不再手写**。
  --
  -- 第一版我在适配器里手写了 19 个按钮名，而实际有 35 个 —— 真机日志
  -- `SetImage 成功 19 个` 把这件事暴露出来了：另外 16 个（`action.q.*`、`modal.level.*` …）
  -- **从来没被验证过**。手写名单迟早漏，直接从 `build_layout()` 里筛 `kind == "button"`。
  --
  -- ⚠️ 必须在上面的 `apply_tray_layout` **之前**设好 —— 上色代码目前挂在那个函数里。
  local labels = {}
  do
    local ok, nodes = pcall(function() return controller:build_layout() end)
    if ok and type(nodes) == "table" then
      local list = {}
      for i = 1, #nodes do
        local nd = nodes[i]
        local id = nd.id
        if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") then
          list[#list + 1] = id
        end
      end
      adapter.cfg.btn_list = list
      if print then print("[murdoku] 上色名单（来自规划）：" .. #list .. " 个按钮") end
      -- ★ 顺手把所有按钮的**名字**也收集起来（规划里的 `text`），开机直接写下去。
      --   为什么不信渲染那条路：用户反复反馈名字没配上，而文字**只能靠脚本写**
      --   （存档里不存文字，已用 `ruler.c.1` 验证）。这里走一条**明确、可读回验证**的路径。
      labels = labels or {}
      for i = 1, #nodes do
        local nd = nodes[i]
        if nd.kind == "button" and type(nd.id) == "string" and type(nd.text) == "string"
           and nd.text ~= "" and not nd.id:match("^cell%.") then
          labels[nd.id] = nd.text
        end
      end
    end
  end

  -- ★★ 2026-09-28：**用已证明可用的接口直接给按钮写名字**。
  --
  -- 为什么不用 `adapter:apply_button_labels`：我加了那个方法，真机/模拟器日志却显示
  --   `适配器支持 = false`（方法没挂到实例上），而我没在当轮查清原因。
  --   与其赌一个没验证过的入口，不如走 `set_property` —— **那是渲染一直在用、
  --   已经被真机反复验证过的路径**。
  --
  -- 同时把**写回结果读出来**：这样下一次日志能直接告诉我们卡在哪一环
  --   （读到文字 → 写入成功，问题在渲染；读回 nil/空 → 写不进去）。
  if print then
    local ids2 = {}
    for id in pairs(labels) do ids2[#ids2 + 1] = id end
    table.sort(ids2)
    local okN, badN = 0, 0
    local shown = 0
    for i = 1, #ids2 do
      local id, want = ids2[i], labels[ids2[i]]
      adapter:set_property(id, "text", want)
      local back, fs, fc, vv = nil, nil, nil, nil
      -- ★★ 2026-09-29：**`label` 找不到就退回 `text`**。
      --
      --   为什么：真机日志一直报「写入后读回一致 8 个，**不一致 5 个**」，
      --   看着像出错，其实那 5 个是**头像卡**（`tray.*`）——
      --   它们的文字子控件叫 `text` 而不是 `label`（见体检输出）。
      --   统计口径把"正常的另一种结构"算成了失败，误导排查。
      --   ⇒ 两个都试，并且**分开报数**，日志才说真话。
      local via = nil
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
          if lb == nil then lb = adapter:sub(id, "text"); via = "text" else via = "label" end
          if lb then
            back = lb.text
            fs = lb.fontSize
            fc = lb.fontColor
            vv = lb.visible
          end
        end)
      end
      -- ★★ 2026-09-28：**显式设字号**。
      --
      --   真机日志已经证明 `label.text` **写进去了**（读回 "返回列表" ✅）却看不见 ⇒
      --   问题不在"写"，在"画不出来"。而文本控件最典型的"隐形"原因就是 **fontSize = 0**
      --   （克隆出来的 label 很可能没带字号）。
      --   顺手把 fontSize / fontColor / visible 一起打出来 —— 下一次日志就能确认这个判断，
      --   而不是又靠猜。
      -- ★★ 2026-09-28：**把 label 提到最上层**。
      --
      --   真机日志已经把所有属性都排除干净了：
      --     `读回 返回列表   fontSize=20 fontColor=4294967295(白/不透明) visible=true`
      --   —— 文字、字号、颜色、可见性**全部正确**，屏幕上却一个字都没有。
      --   ⇒ 只可能是**被 `bg` 压住了**。
      --   层级 = 同级子控件的先后顺序，而 `bg` 是我先加、`label` 是后加，
      --   到底谁在上面取决于引擎把"先"解释成上层还是下层 —— 我**不想再赌语义**，
      --   直接用 `SetAsLastSibling()`（官方文档：「数值越大显示层级越高」）**强制** label 到顶。
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
          -- ★★★ 2026-09-28 —— **根因是用户自己找出来的，我前面全查错了方向**：
          --   我给 label 建的高度只有 **20px**，而字号也是 20px
          --   ⇒ **文本框装不下自己的字** ⇒ 文字"存在、可见、颜色正确"却一个像素都画不出来。
          --   我前面查了写入、层级、颜色、图集、克隆体状态 ——
          --   **唯独没想到"容器够不够大"** 这个最朴素的原因。
          --
          --   用户实测：高度改 40、字号缩到 10 就显示了；他建议**加大高度**而不是缩小字号。
          --   这里采纳：高度给 40，字号保持 18（能看清）。
          if lb ~= nil then
            local bw = nil
            pcall(function()
              local b = adapter:find(id)
              if b ~= nil and b.GetSizeDelta ~= nil then
                local a1 = nil
                a1 = select(1, b:GetSizeDelta())
                bw = a1
              end
            end)
            -- ★★★ 2026-09-29：**不再强制 label 的尺寸/字号/位置**。
            --
            --   用户在编辑器里**自己给按钮配好了居中文本**
            --   （例如 `action.hint` 的 bg 97×43、label 59×40），
            --   而我之前每次都按自己的算法把 label 改成 (按钮宽, 28) 并设 fontSize=24
            --   ⇒ **把用户调好的东西覆盖掉**，这正是他说的"未完整生效"。
            --
            --   现在脚本只负责**写文字内容**（文字不存进 .gil，只能运行时写），
            --   几何与字号一律听编辑器的。
            --   （如果将来发现某类按钮字号偏小，用 cfg.label_font_size 单独指定，
            --     不要再无条件覆盖。）
            if adapter.cfg.label_font_size ~= nil and lb.fontSize ~= nil then
              lb.fontSize = adapter.cfg.label_font_size
            end
          end
        end)
      end
      if back == want then okN = okN + 1 else badN = badN + 1 end
      if shown < 8 then
        print(string.format("  %-18s 想要 %q → 读回 %s   fontSize=%s fontColor=%s visible=%s",
          id, want, tostring(back), tostring(fs), tostring(fc), tostring(vv)))
        shown = shown + 1
      end
    end
    print(string.format("[murdoku] 按钮名字：成功 %d 个；另有 %d 个走 `text` 子控件（头像卡，正常）或写入未回读（共 %d）", okN, badN, #ids2))
  end

  -- 头像卡按本关实际人数重新摆正（列数会随人数变，编辑器那套只是"最挤的情况"）
  if adapter.apply_tray_layout and controller.tray_layout_canvas then
    local moved = adapter:apply_tray_layout(controller:tray_layout_canvas())
    if moved > 0 and print then
      print("[murdoku] 头像卡已按 " .. moved .. " 人重新排布")
    end
  end

  -- ★ 2026-09-28 新增：**行标 / 列标按格子的实际位置对齐**。
  --
  -- 用户报"列标和行标没与棋盘对齐"。根因是 ruler 标签的位置在**规划时**用设计空间几何算过一遍，
  -- 而格子是**运行时**用 `cell_geometry` 算的 —— 两套数必然对不上。
  -- 这里用格子的真实锚点位置反推标签位置，只信一份数据。
  if adapter.apply_ruler_layout then
    -- ⚠️ 行列数在 `controller.core` 里（控制器自己没有 rows/cols 字段）——
    --    第一版写成 `controller.rows`，取到 nil，靠 `or 5` 兜住了，5×5 恰好蒙对、
    --    但 6×6 / 7×7 就会少摆几个标签。取真实值，别用兜底。
    local core = controller.core
    adapter:apply_ruler_layout((core and core.rows) or 5, (core and core.cols) or 5)
  end

  -- ★ 相交诊断：把"与棋盘相交且显示中"的控件列出来。
  --   用户反复报棋盘上有方块，而我从规划数据分不清"此刻屏幕上是谁" —— 让日志直接说。
  --   ⚠️ 用 `adapter.cfg` 而不是 `cfg` —— 这个位置的 `cfg` 是**后面才声明的 local**，
  --      在这里取到的是 nil（真机/模拟器会报 `attempt to index a nil value (global 'cfg')`）。
  if adapter.diagnose_overlap and adapter.cfg.overlap_diag ~= false then
    adapter:diagnose_overlap()
  end
  -- ③ 参照格子体检：把「cell.1.1 到底配好了没有」一次性讲清楚。
  --    原因：格子能不能看见/点得动，取决于类型、射线、子控件、状态节点、图片类型好几项，
  --    而这些在日志里**原本一点痕迹都没有**，出问题只能靠肉眼猜。
  --    搭界面阶段默认开（cfg.diagnose_cell = false 可关），每个会话只打一次。
  if adapter.diagnose_cell ~= nil and not adapter._cell_diagnosed
     and not (adapter.cfg and adapter.cfg.diagnose_cell == false) then
    adapter._cell_diagnosed = true
    pcall(function() adapter:diagnose_cell() end)
    -- 跟着报一段「模板候选」：cell.1.1 自己的 prefabIndex 是**基础模板**，不能用来
    -- 生成格子；必须有「从另存出来的模板**新建**的」那个控件（约定名 tpl.cell）。
    -- 提前报出来，试玩前就知道配没配对，而不是等一句"全部实例化失败"。
    pcall(function() adapter:diagnose_template() end)
  end

  Murdoku.render(true)

  -- ★★★ 2026-09-30：**把主页/选关和 3D 角色的输入隔开**（用户明确要求）。
  --
  --   做法见适配器 `seal_container` 的注释：给容器设「屏蔽按键事件穿透」
  --   （`disableKeyEventPassthrough`）等字段 —— **不是拦截键位**
  --   （`AddKeyEventListener` 只有"监听"、没有"消费"语义，拦不住）。
  --   控件已经在 .gil 里，这里是运行时给它们上锁。
  --
  --   ⚠️ 待真机验证：**屏蔽之后 `AddKeyEventListener` 自己还能不能收到按键**。
  --      如果连自己也收不到，就缩小范围（只用 `disableCursorEventPassthrough`）。
  --      这条日志打出"设了几个"，方便对照。
  if adapter.seal_containers ~= nil then
    -- ★★★★★ 2026-10-07 **改由编辑器里的容器 `xxx` 代劳** ✗✓（用户要求 ✓ 实测可行 ✓）
    --   ★ `xxx` = 你在图层**最底部**加的全屏容器 ✓ 编辑器里开了
    --     **「屏蔽按键」+「屏蔽光标事件」两个开关** ✓ ⇒ ★ **键盘与触摸两件事它一起管** ✓✓
    --   ⇒ ★ 脚本这条"逐个容器设 `disableKeyEventPassthrough`"就**不需要了** ✓ 停用 ✓
    --     ★ 好处 ✓：★ 少一层脚本介入 ✓ 且**编辑器里看得见、可随时调** ✓
    --   ⚠️ **回退只需一行** ✓：把下面那行注释取消即可 ✓
    -- local sealed = adapter:seal_containers({ "home", "select" })
    local sealed = 0
    -- ★ 2026-10-07 **触摸遮挡层**（★ 移动端：全屏拖动会带动 3D 角色 ✓ 用户实测反馈 ✓）
    --   与上面"屏蔽按键"是**两条独立的链** ✓ 键盘归那条 ✓ 触摸归这条 ✓（★ 见适配器 `seal_cursor_shield` ✓）
    if adapter.seal_cursor_shield ~= nil then
      -- ★ 2026-10-08 **已撤** ✓（★ 用户新方案：★ `xxx` 在客户端容器之外 ⇒ 脚本碰不到 ⇒ 也不用兜底 ✓）
      -- pcall(function() adapter:seal_cursor_shield() end)
    end
    if print then
      print(string.format("[murdoku] 2D/3D 输入隔离：主页/选关容器已屏蔽穿透 %d 个", sealed))
      -- ★★★ 2026-09-30：**把验收方法直接写进日志**（目标⑦）。
      --
      --   「屏蔽之后脚本自己还收不收得到按键」只有真机能回答。与其等你来问，
      --   不如启动时就说清楚**怎么确认**：
      --     按任一键盘快捷键 → 看到 `✅ 键盘事件仍能收到` ⇒ 隔离没有副作用
      --                       看不到 ⇒ 屏蔽把键盘也挡住了
      --   （那条 ✅ 在 engine_adapter 的按键回调里，**只在第一次按键时打一次**，
      --     且不依赖 debug_key。）
      print("[murdoku]   验收：在关卡里按任一键盘快捷键 —— 出现「✅ 键盘事件仍能收到」"
        .. "即说明隔离没有副作用；若没有，去掉 main.lua 里的 seal_containers 即可（一行）。")
    end
  end

  -- ★ 逐格自检 + 子控件清单放在**首次渲染之后**。
  --
  -- 为什么必须放到渲染后：格子上的墙/门/图片是**渲染时**由 `set_property` 落下去的
  -- （`controller:render` 才推 `walls`/`doors`/`image`/`tint`）。放在渲染前，
  -- 清单里读到的全是**编辑器初始值** —— 用户 2026-09-27 04:26 的日志里
  -- `wall.up visible=false` 但**屏幕上明明有蓝线**，就是这么来的（误导性输出）。
  if adapter.diagnose_cell ~= nil and adapter._cell_diagnosed and adapter.diagnose_grid ~= nil
     and adapter.cfg and adapter.cfg.diagnose_grid ~= false then
    local rows = adapter.cells_rows or (adapter.cfg.cells and adapter.cfg.cells.rows) or 5
    local cols = adapter.cells_cols or (adapter.cfg.cells and adapter.cfg.cells.cols) or 5
  if Murdoku.DIAG then pcall(function() adapter:diagnose_grid(rows, cols) end) end   -- ★ 闸 ✓
  end

  adapter:signal_emit(Qianxing.SIGNALS.READY, {
    tostring(level.id), core.rows, core.cols, core:piece_count(),
  })

  return self
end

-- 官方生命周期包装
function Murdoku.on_start(level_id, opts)
  -- 控件可能还没就绪：先把必要控件探一遍，找不到就返回 nil 让上层重试
  local adapter = (opts and opts.adapter) or prepared_adapter
  if adapter then
    -- ★★★★★ 2026-10-02 **这里原来写死了 `board` / `cell.1.1`** ——
    --   重建时这两个控件被删掉了 ⇒ **判据永远为假** ⇒ `on_start` **永远返回 nil**
    --   ⇒ 上层每帧重试、`started` 一直 false ⇒ 主页设置在 `on_start` 里 ⇒
    --   **主页消失 + 隔断失效**（用户 13:5x 实测）。
    --
    --   ⚠️ 同一个判据在 `entry_client_script.lua` 的 `probe_or_dump()` 里**也有一份**
    --   （那处上一轮已改）—— **两处必须一致**，这就是"判据写死旧名字"第三次咬人的地方。
    --
    --   新判据（按"重建后什么一定存在"）：
    --     ① 旧结构：board / cell.1.1 任一
    --     ② 新结构：stage / home 任一
    --     ③ 兜底：root 存在且已有 >3 个子控件
    local ready = false
    pcall(function()
      -- ★ 2026-10-06 残留清理 ✗✓：★ 删掉 `"board"` 这个**死引用** ✓
      --   ★ `board` 在真机与模拟器**都找不到** ✓（★ 两边日志原文：「`board` → **找不到控件**」✓）
      --   ⇒ ★ 它在 OR 里**恒为假** ✗ ⇒ ★ 这一半是**纯噪音** ✓
      --   ★ 真正起作用的是 `cell.1.1` ✓ ⇒ ★ 保留 ✓（★ 行为不变 ✓）
      if adapter:find("cell.1.1") ~= nil then
        ready = true
      elseif adapter:find("stage") ~= nil or adapter:find("home") ~= nil then
        ready = true
      else
        local rt = adapter:find("root")
        if rt ~= nil and rt.GetChildren ~= nil then
          local kids = nil
          pcall(function() kids = rt:GetChildren() end)
          if type(kids) == "table" and #kids > 3 then ready = true end
        end
      end
    end)
    if not ready then return nil end
  end
  local self, err = Murdoku.start(level_id, opts)
  if not self and printerr then printerr("[murdoku] 开局失败：" .. tostring(err)) end
  return self
end

function Murdoku.on_update(dt)
  if not current then return end
  -- ★★★★★ 2026-10-09 **四键胶囊底图：真正修好（原来那段【一次都没跑过】）** ✗✓
  --
  --   ★ 真机症状 ✓：四键**能点**（`收到点击 → 控件 modal.save 事件=exit_menu_save` ✓）
  --     但**没有图文** ✗，日志里只有渲染分支那句 `★ 胶囊底图：到守卫 adapter=false 闩锁=nil` ✓
  --
  --   ★ 根因（两个，都得修）✗：
  --     ① ★ **`adapter` 在这个作用域里是 nil** ✗✓
  --        本文件里 `adapter` **只在 `Murdoku.start`（L117）和 `Murdoku.on_start`（L685）里是 local** ✓
  --        而那段代码在**另一个函数**里 ⇒ 它读到的是**全局 `adapter`** ⇒ **恒为 nil** ✗
  --        ⇒ `adapter ~= nil` **永远为假** ⇒ **整段静默跳过** ✓（所以真机日志里一行都没有 ✓）
  --        ★ 本文件里拿适配器的正确写法是 **`current.adapter`** ✓（L312 `self.adapter = adapter` ✓
  --          上面的四键探针 L732/L738 用的就是它 ✓）
  --     ② ★ 它被**两层无关的门**关着 ✗：`if n > 0 and current._face_on ~= n then`（只在
  --        **face 数量变化那一帧**才进 ✓）＋ `if print then` ✓
  --        ⇒ 即使 ① 修了，也只是"恰好在某帧碰上了"才设得上 ✗ 不可靠 ✓
  --
  --   ★ 修法 ✓：搬到 `on_update` 的**最前面**（每帧都跑到 ✓），自己用闩锁保证只做一次 ✓
  --     ⇒ 稳态**零成本** ✓（一次 set + 一个布尔判断 ✓）
  --     ⚠️ 用 `current.adapter` ✓ **不要**再用裸 `adapter` ✓
  if (not Murdoku._exit_art_done) and current.adapter ~= nil then
    Murdoku._exit_art_done = true
    for _, _bid in ipairs({ "modal.exit", "modal.save", "modal.settle", "modal.cancel" }) do
      local _bg = nil
      pcall(function() _bg = current.adapter:sub(_bid, "bg") end)
      if _bg ~= nil then
        local _src = nil
        pcall(function() _src = _bg.imageSource end)
        pcall(function() _bg:SetImage(_src or 4294967295, 107179) end)
        local _rb = nil
        pcall(function() _rb = tostring(_bg.imageId) end)
        if print then
          print("[murdoku] ★ 胶囊底图(入口层)：bid=" .. tostring(_bid) .. "  回读=" .. tostring(_rb))
        end
      else
        if print then
          print("[murdoku] ★ 胶囊底图(入口层)：bid=" .. tostring(_bid) .. "  **bg 取不到**")
        end
      end
    end
  end
  -- ★★★★★ 2026-10-08 **四键探针（真·每帧入口 ＋ adapter 在手 ✓）** ✗✓
  --   ★ 为什么这里能读 ✓：★ 本函数是 `Murdoku.on_update`（★ 入口脚本 L853 的 `OnUpdate` 调它 ✓
  --     ★ 且 `script:EnableUpdate(true)` 已开 ✓）★ 而 `current.adapter` **就在这里** ✓✓
  --   ★ 触发条件 ✓：★ 渲染分支刚记录过"弹窗开着"（★ `current._modal_seen` 在涨 ✓）
  --     ★ 那一侧拿不到 adapter ✗ ⇒ ★ **两边拼起来**：★ 一边报"开着" ✓ ★ 一边读控件 ✓
  -- ★★★★★ 2026-10-09 **修好这条探针 —— 它【从来没触发过】** ✗✓
  --   ★ 症状 ✓：真机日志里**一次都没有** `★ 四键探针2` ✗
  --   ★ 根因（两处对不上 ✗）：
  --     · `ui_controller.lua:3028` 是把计数器加在 **控制器** 上：`self._modal_seen = …`
  --     · 而这里读的是 **会话**：`current._modal_seen` ✗ —— **两个不同的对象** ✓
  --     ⇒ `current._modal_seen` **恒为 nil** ⇒ `_seen = 0` ⇒ 那个 `>` 判断**永远不成立** ✓
  --   ⇒ ★ 修法：从**控制器**上读（`current.controller` ✓ 与 L794 的 `current.controller:tick` 同一个 ✓）
  --   ★ 顺带把资料员要的那两个数打出来 ✓（它建议的"最大的分叉"那条 ✓）：
  --     `bg` / `label` 的 **同级排序索引**（官方 `GetSiblingIndex()` ✓ 语义：**数值越大越靠上** ✓）
  --     ⇒ 一行就能分清"**根本没画**"还是"**画了被盖住**" ✓
  if current ~= nil and current.adapter ~= nil then
    local _ctl = current.controller
    local _seen = (_ctl and _ctl._modal_seen) or 0
    if _seen > (Murdoku._probe_seen or 0) and (Murdoku._probe_n or 0) < 12 then
      Murdoku._probe_seen = _seen
      Murdoku._probe_n = (Murdoku._probe_n or 0) + 1
      local _k = nil
      pcall(function() _k = current.adapter:sub("modal", "modal.exit") end)
      if _k == nil then pcall(function() _k = current.adapter:find("modal.exit") end) end
      local _b = nil
      if _k ~= nil then pcall(function() _b = current.adapter:sub("modal.exit", "bg") end) end
      local _id, _src, _vis, _sz = "?", "?", "?", "?"
      if _b ~= nil then
        pcall(function() _id = tostring(_b.imageId) end)
        pcall(function() _src = tostring(_b.imageSource) end)
        pcall(function() _vis = tostring(_b.visible) end)
        pcall(function() _sz = tostring(_b.sizeDelta and (_b.sizeDelta.x .. "x" .. _b.sizeDelta.y) or "无") end)
      end
      -- ★★★ 2026-10-09 **资料员建议的那两个数（最大的分叉就在这一行 ✓）**
      --   官方语义（`docs/api-cache/mhtakr07vej4.txt:1300-1311` ✓）：
      --     `GetSiblingIndex()` ⇒ 同级排序索引 ✓ **数值越大越靠上** ✓
      --   读法 ✓：
      --     · `bg` 的索引 **>** `label` 的 ⇒ ★ **底图压在文字上面** ⇒ 图文一起看不见 ✓
      --     · 两者都**读不出来**（nil） ⇒ 接口不适用，改看别的 ✓
      --     · 索引正常（`label` 更大）而画面上还是空 ⇒ ★ **压根没画**（不是被盖住）✓
      --   ⇒ ★ 这一条能一次分清「没画」还是「被盖住」✓ —— 那是当前最大的分叉 ✓
      local _bi, _li = "?", "?"
      local _lb = nil
      if _k ~= nil then pcall(function() _lb = current.adapter:sub("modal.exit", "label") end) end
      if _b ~= nil then pcall(function() _bi = tostring(_b:GetSiblingIndex()) end) end
      if _lb ~= nil then pcall(function() _li = tostring(_lb:GetSiblingIndex()) end) end
      print("[murdoku] ★ 四键探针2：exit=" .. tostring(_k ~= nil) .. "  bg=" .. tostring(_b ~= nil)
        .. "  imageId=" .. _id .. "  source=" .. _src .. "  visible=" .. _vis .. "  size=" .. _sz)
      print("[murdoku] ★ 四键探针3（谁在上面）：bg 的 GetSiblingIndex=" .. _bi
        .. "   label 的 GetSiblingIndex=" .. _li
        .. "   （官方：**数值越大越靠上** ✓ ⇒ bg > label 就是底图压在字上面 ✗）"
        .. "  label=" .. tostring(_lb ~= nil)
        .. "  label.visible=" .. (function() local v = "?" pcall(function() v = tostring(_lb.visible) end) return v end)())
    end
  end
  current.adapter:on_tick(dt)
  current.controller:tick(dt)

  -- ★★★★★ 2026-10-02 **门控②必须反复重试，不能只在开局做一次**。
  --
  --   真机日志把原因暴露得很清楚：
  --     常驻光标回读（门控②）：root=true topbar=true left=true ... intro=true
  --     已由脚本打开 9 个容器的「显示常驻光标」     ← **还是 9 个，home/select 不在里面**
  --   而 `enable_cursor` 只在 `Murdoku.start` 里调**一次** —— 那时 `home` / `select`
  --   这两个**屏幕容器还没被 create_control**（它们是第一次渲染时才建的），
  --   `find("home")` 返回 nil ⇒ 直接跳过 ⇒ **永远开不上** ⇒ 它们的子控件全部落在门控②之外。
  --
  --   ⇒ 改成每 20 帧重试一次（幂等、便宜），直到所有受管容器都拿得到为止。
  if current.adapter.enable_cursor and ((current.frames or 0) % 20 == 0) then
    local before = Murdoku._cursor_ok or 0
    local n = current.adapter:enable_cursor()
    Murdoku._cursor_ok = n
    if n ~= before and print then
      print("[murdoku] 门控②重试：已打开 " .. tostring(n) .. " 个容器的「显示常驻光标」")
    end
  end

  -- ★★★★★ 2026-10-02 **强制打开「可被光标射线检测」（`raycastTarget`）** —— 真机"点不动"的正解。
  --
  --   官方文档：预设按钮只有三个自有字段 `interactable` / `clickAudioId` / `raycastTarget`；
  --   项目自己的清单写着：「关掉就点不动」「**界面看得见，但点哪儿都没反应**」。
  --   而 `clickAudioId` 就是点击音效 ⇒ "处处有音效但什么也没发生" = 点到了按钮、但它 `raycastTarget=false`。
  --   我之前只对容器试过这个字段（容器没有它）⇒ 误判成"引擎里不存在"⇒ 从没对按钮读过写过。
  -- ★★★★★ 2026-10-05 **收敛/放弃之后连调用都不再发**（这一轮每帧成本第 (3) 条的最后一步）。
  --
  --   适配层 `enable_raycast` 自己也会在 `_ray.done` 时立刻返回（**一次树都不走**）；
  --   这里再挡一道，是为了连"函数调用 + 三次返回值"都不产生。
  --   每 20 帧一次本身不算什么，但这一轮的规矩是"没必要就不做"
  --   （用户原话：「没必要留着不必要的负载浪费，我们后面本来也还需要整体优化」）。
  --
  --   ⚠️ 判据只在适配层一处定义（`Adapter:enable_raycast` 上面那段大注释：
  --      ① 收敛即停 ② 每代硬上限 25 趟 ③ 换屏/换关由 `Adapter:rearm_raycast` 重新武装）
  --      —— 这里只读它的结论，**不复制规则**，免得两处各改一半。
  local ray_st = current.adapter._ray
  if current.adapter.enable_raycast and ((current.frames or 0) % 20 == 0)
     and not (ray_st ~= nil and ray_st.done) then
    local seen, set, samples = current.adapter:enable_raycast()
    local key = tostring(seen) .. "/" .. tostring(set)
    if key ~= Murdoku._ray_key and print then
      Murdoku._ray_key = key
      print("[murdoku] 射线开关（raycastTarget）：有该字段的控件 " .. tostring(seen)
        .. " 个，其中被打开 " .. tostring(set) .. " 个")
      if type(samples) == "table" and #samples > 0 then
        print("[murdoku]   本次打开的例子：" .. table.concat(samples, "  "))
      end
    end
  end
  -- 时间只在整秒变化时重绘（省性能），但**任何其它状态变化也必须立刻重绘**：
  -- 单击落成铅笔笔记是在 tick 里做的（要等双击窗口），如果只按整秒重绘，
  -- 笔记要等到下一个整秒才画出来 —— 手感上就是"点了没反应"。
  local sec = math.floor(current.core.elapsed or 0)
  if sec ~= current.last_tick or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end

  -- ★★★ 2026-10-01：**开局后的一次性"屏幕上到底有什么"诊断**。
  --
  --   为什么加：用户在真机上反馈"界面一片空白"，而日志里该建的东西都建了、
  --   没有任何报错 —— 光靠现有日志**分不清**是
  --     (a) 脚本把控件设成了隐藏，还是 (b) 控件坐标跑到屏幕外，还是
  --     (c) 控件根本不存在（名字对不上）。
  --   ⇒ 这里在第 90 帧（约 1.5 秒，足够跑完开局渲染）打一次**实际读回来**的状态：
  --     能不能找到、visible / active 是多少、坐标尺寸是多少。
  --   只打一次，不影响性能，也不依赖 debug_* 开关（这是验收信息，不是调试噪音）。
  -- ★★★★ 2026-10-01 改成"每次切屏都打一次"（原来只在第 90 帧打一次，只看到主页）。
  --   起因：用户报"选关界面上所有按钮都无效"，而诊断只在主页打过 => 看不到选关页真实状态。
    -- ★★★★★ 2026-10-03 **删掉"手动显形（分家后）"整段**。
    --   它是我 019 版从切屏诊断块里"分家"出来的，当时误判成"修主页按钮不显示"的功能代码；
    --   实际它只是诊断用的"手动试试能不能显示"。搬到块外后变成**每帧**把 `home.select`
    --   与 `home` 容器强制设成 `SetVisible(true)` ⇒ **覆盖了所有按屏幕隐藏的逻辑** ⇒
    --   真机表现就是"关卡里棋盘上压着返回菜单按钮、点了回选关"（22:45 日志）。
    --   ⇒ 删掉。隐藏逻辑回归 `apply_screen_hide` + 下面那段按屏幕同步。

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **给这几大块诊断加开关，默认【关】** ✗✓ —— 这就是"开局卡一下"的真凶 ✓
  --
  --   ★ 起因（★ 用户实测 ✓）：★「试玩开始时启动游戏前的最后一下偶尔会卡一下」✗
  --     ★★ 而★ 这份日志里，同一时刻**连着跑五套诊断** ✗：
  --       ★「开局诊断」✓「屏幕占用排行」✓「客户端 UI 根清单」✓「对照组」✓「切屏对比」✓
  --       ★ 另外适配器里还有一整套「逐格自检」✓
  --     ★★★ 每一块的代价 ✓：★ **遍历全部控件（★ 80~150 个 ✓）× 逐个取字段
  --       （★ name/visible/active/position/size ✓）× 拼字符串 × `print`** ✗✗
  --       ★ 「切屏对比」最贵 ✓：★ **两份全树快照 + 逐项比较 + 格式化上百行** ✗
  --     ★★★★ ⇒ ★ **它们集中在一个时刻跑 ⇒ 那一下就是卡顿** ✓✓
  --
  --   ★ 而下面 L772 那句注释写着 ✓：
  --     ★「**不依赖 `debug_*` 开关**（★ 这是**验收信息**，不是调试噪音）」✗
  --     ★★ 当年是对的 ✓ —— ★ 那时要靠它定位"界面一片空白" ✓
  --       ★★★ 而**现在** ✗：★ 界面已经能用 ✓ ★ 它变成**每次都跑的负担** ✓✓
  --         ★ ⇒ ★ 该给它一个开关 ✓（★ 需要排查时打开 ✓ 平时关着 ✓）
  --
  --   ★★ 用法 ✓：★ 在 `cfg` 或这里把 `Murdoku.DIAG` 设成 `true` 即可恢复全部诊断 ✓
  --     判据 ✓：★ 关掉之后开局**不该再卡** ✓ 而★ 界面功能**一模一样** ✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  Murdoku.DIAG = Murdoku.DIAG or false      -- ★ 默认关：★ 要排查时改 true ✓

  -- ★★★★★ 2026-10-06 **带闸的打印（全局）** ✗✓ —— 给"在正常重绘 if 里"的诊断用 ✓
  --   ★ 为什么需要 ✓：★「客户端 UI 根清单」和「对照组」都在
  --     `if sec ~= current.last_tick or current.controller.dirty then` 里 ✗
  --     ⇒ ★ 挡住那个 `if` 会连【正常重绘】一起挡掉 ✗ ⇒ 只能逐条 `print` 上闸 ✓
  --   ★ 全局（无 local）✓ ⇒ 它下面两千行都能用 ✓ ★ 闸关着时【一个字符都不拼】✓
  function dprint(...)
    if Murdoku.DIAG then print(...) end
  end

  local scr_now = current.controller and current.controller.screen or "level"
  if Murdoku.DIAG
     and ((current.frames or 0) >= 90 or scr_now ~= Murdoku._last_screen)
     and scr_now ~= Murdoku._dump_done_for then
    Murdoku._dump_done_for = scr_now
    local ad = current.adapter
    print("[murdoku] ===== 开局诊断：屏幕上到底有什么（第 90 帧实测）=====")
    print("[murdoku]   controller.screen = " .. tostring(current.controller.screen))
    -- ★★★★★ 2026-10-06 **名单已按真机实测修正** ✗✓
    --
    --   旧名单里有 7 个**根本不存在的名字** ✗（真机日志逐条报"找不到控件" ✓）：
    --     `select.back` `select.title` `select.card.1` `select.card.2`
    --     `select` `board` `action.undo`
    --     ★ 而且 `select.card.2` 还**写了两遍** ✗
    --   ⇒ ★ 诊断的意义是"发现名字对不上"✗ —— ★ 但它自己就带着一堆假名字 ✓
    --     ⇒ ★★ 每帧刷 7 行"找不到"✗ ⇒ **真问题会被淹掉** ✓
    --   ⇒ 改成真机确认存在的那些 ✓（★ 依 2026-10-05/06 的真机日志 ✓）：
    local ids = {
      "root", "home", "home.title", "home.select", "home.continue", "home.shop", "home.bag",
      "selbar", "selbtn.1", "tpl-container",
      "stage", "board.bg", "cell.1.1",
      "topbar", "toolbar", "right",
      "clues", "clues.bg", "clues.grid",
      "hud.title", "hud.subtitle", "hud.timer", "hud.progress",
      "action.back",
    }
    for i = 1, #ids do
      local id = ids[i]
      local c = nil
      pcall(function() c = ad:find(id) end)
      if c == nil then
        print("[murdoku]   " .. id .. "  → **找不到控件**（名字对不上 / .gil 里没有）")
      else
        -- ⚠️ 读坐标**必须用 GetAnchoredPosition / GetSizeDelta 这两个方法** ——
        --   我第一版写 `c.positionX` / `c.width`，真机上**全读成 nil**
        --   （适配器里那段"逐格自检"就是这么踩过并改对的，我照抄了错的那半）。
        local v, a, pos, size = nil, nil, "?", "?"
        pcall(function() v = c.visible end)
        pcall(function() a = c.active end)
        pcall(function()
          local px, py = c:GetAnchoredPosition()
          if type(px) == "table" then pos = string.format("(%.0f,%.0f)", px.x or 0, px.y or 0)
          elseif px ~= nil then pos = string.format("(%.0f,%.0f)", px, py or 0) end
        end)
        pcall(function()
          local w, h = c:GetSizeDelta()
          if type(w) == "table" then size = string.format("%.0fx%.0f", w.x or 0, w.y or 0)
          elseif w ~= nil then size = string.format("%.0fx%.0f", w, h or 0) end
        end)
        local bnd = false
        pcall(function() bnd = (current.adapter.bound and current.adapter.bound[id]) or false end)
        print(string.format("[murdoku]   %-16s visible=%-5s active=%-5s 位置=%-14s 尺寸=%-12s bind=%s",
          id, tostring(v), tostring(a), pos, size, tostring(bnd)))
      end
    end
    print("[murdoku] ===== 开局诊断结束 =====")
    -- ★★★★ 2026-10-01 **列出本屏所有"可见"控件、按面积从大到小**。
    --
    --   起因：诊断已经证明选关页上 `select.back` / `select.card.*` 的
    --   visible=true、坐标在屏内、bind=true —— **一切正常却点不动**
    --   ⇒ 只剩一种可能：**有别的东西盖在它们上面**（射线被上层控件接走）。
    --   而原来只打了 12 个固定 id，看不到"谁盖住了谁"。
    --   ⇒ 这里从 root 递归走一遍真实控件树，把所有 visible=true 的按面积排序打出来：
    --     排在最前面的那几个大控件，就是"疑犯"。
    -- ★★★★★ 2026-10-02 **去掉 visible=true 这个过滤条件**（用户三条答案指出的"眼罩"）。
    --
    --   用户观察：那个拦截层**全透明、不消失、Esc 无反应** ⇒ 是一个**隐形输入层**。
    --   而这一版之前所有排行榜都写着 `if v == true then`（只看可见控件）
    --   ⇒ **一个 visible=false 但仍在拦截点击的控件，一次都没被列出来过**。
    --   脚本用的是 `SetVisible()` —— 关掉的是**渲染**；诊断里所有控件的 `active`
    --   都是 true ⇒ **不可见但仍然 active 的控件，很可能照样参与射线**。
    --   ⇒ 改成"一律列出"，并把 visible / active **都打出来**，大的一律标 ★。
    print("[murdoku] ===== 屏幕占用排行（**不管可见不可见**，按面积）=====")
    do
      local list = {}
      local function walk(c, depth)
        if c == nil or depth > 6 then return end
        local v, al, w, h, nm = nil, nil, nil, nil, "?"
        pcall(function() v = c.visible end)
        pcall(function() al = c.active end)
        pcall(function() nm = tostring(c.name) end)
        pcall(function()
          local a, b = c:GetSizeDelta()
          if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
        end)
        local area = (w or 0) * (h or 0)
        -- 只列"大"的；阈值降到 20000（原来的 1000 会刷一屏小控件）
        if area > 20000 then
          list[#list + 1] = { id = nm, w = w or 0, h = h or 0, area = area,
                              vis = tostring(v), act = tostring(al) }
        end
        -- ⚠️ 这里原来用 `c.childCount` + `c:GetChild(i-1)` —— **走不进子树**
        --   （排行榜只报出 root 一个，而诊断里明明有一堆 visible=true 的控件）。
        --   项目里能用的枚举是 `ctrl:GetChildren()`（见适配器 L235/L295/L612 等处）。
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 200) do
            if kids[i] ~= nil then walk(kids[i], depth + 1) end
          end
        end
      end
      local rt = nil
      pcall(function() rt = ad:find("root") end)
      walk(rt, 0)
      table.sort(list, function(x, y) return x.area > y.area end)
      for i = 1, math.min(#list, 26) do
        local e = list[i]
        print(string.format("[murdoku]   %2d. %-22s %6.0fx%-6.0f 可见=%-5s active=%-5s 面积=%d",
          i, e.id, e.w, e.h, e.vis, e.act, math.floor(e.area)))
      end
      print("[murdoku]   （共 " .. tostring(#list) .. " 个面积>20000 的控件 —— **含不可见的**）")
      print("[murdoku]   ★ 找那个「全屏 + 可见=false + active=true」的 —— 它就是隐形拦截层")
    end
    print("[murdoku] ===== 排行榜结束 =====")

    -- ★★★★ 2026-10-01 **第二段诊断（真机仍看不见时用）**：
    --   容器尺寸/可见性/坐标全都对，但屏幕上还是没有 ⇒ 说明"卡在哪一层"还没查出来。
    --   这一段做三件事：
    --     ① 把 `home.select` 的**父级链逐层**读出来（哪一层被关掉了，一眼就看见）
    --     ② 读**透明度/缩放**这类"看起来在、其实画不出来"的属性
    --     ③ **手动 `SetVisible(true)` / `SetActive(true)` 之后再读一遍** ——
    --        如果"手动设完就能看见"，说明是脚本下发的属性没生效（写法问题）；
    --        如果"设完还是看不见"，说明是渲染层/图层的问题（另一条路）。
    print("[murdoku] ===== 诊断二：父级链 + 透明度 + 手动显形 =====")
    local leaf = nil
    pcall(function() leaf = ad:find("home.select") end)
    if leaf == nil then
      print("[murdoku]   home.select 找不到，跳过")
    else
      -- ① 父级链
      local chain, cur, guard = {}, leaf, 0
      while cur ~= nil and guard < 8 do
        local nm, vv, aa = "?", "?", "?"
        pcall(function() nm = tostring(cur.name) end)
        pcall(function() vv = tostring(cur.visible) end)
        pcall(function() aa = tostring(cur.active) end)
        chain[#chain + 1] = nm .. "(visible=" .. vv .. ",active=" .. aa .. ")"
        local up = nil
        pcall(function() up = cur.parent end)
        if up == nil then pcall(function() up = cur:GetParent() end) end
        cur = up
        guard = guard + 1
      end
      print("[murdoku]   父级链（从 home.select 往上）：")
      for i = 1, #chain do print("[murdoku]     " .. i .. ". " .. chain[i]) end
      -- ② 透明度 / 缩放
      local al, sc = "?", "?"
      pcall(function() al = tostring(leaf.alpha) end)
      pcall(function() sc = tostring(leaf.scale) end)
      print("[murdoku]   home.select alpha=" .. al .. " scale=" .. sc)
      -- ③ 手动显形 + 回读
      local okv, oka = true, true   -- 已由块外那段负责，这里只用于打印
      -- ★ 2026-10-03 **分家**：`leaf:SetVisible(true)` / `leaf:SetActive(true)` 两行
      --   已经搬到本 if 块**外面**无条件执行（见上面那段「手动显形（分家后）」），
      --   这里只保留回读与打印（方案 A：只搬不删）。
      -- ★ 2026-10-05 Round 43 修：`v2` / `a2` **原来漏写 `local`** ✗
      --   后果有两层（都由 selene 静态检查抓出，`tools/lua_tooling/` 里的配置）：
      --     ① 它们**泄漏成引擎全局变量**（`_G.v2` / `_G.a2`）—— 污染全局表，
      --        而真机/模拟器**共享同一张全局表** ⇒ 可能被别的脚本看到 ✗；
      --     ② 更直接：下面 L876 用 `.. v2 ..` / `.. a2 ..` **直接拼接**，
      --        而这两个 pcall 一旦失败（`leaf.visible` 抛错、leaf 是特殊控件…），
      --        变量就是 **nil** ⇒ Lua 里**拼接 nil 会抛错** ✗ ⇒ **打断整帧**。
      --   ⇒ 修法：声明成局部变量并给**兜底默认值 `"?"`** ✓（只影响日志显示，不影响任何逻辑 ✓）
      local v2, a2 = "?", "?"
      pcall(function() v2 = tostring(leaf.visible) end)
      pcall(function() a2 = tostring(leaf.active) end)
      print("[murdoku]   手动 SetVisible=" .. tostring(okv) .. " SetActive=" .. tostring(oka)
        .. "  ⇒ 回读 visible=" .. v2 .. " active=" .. a2)
      -- 顺手把 home 容器也显形（它要是被关了，子控件画不出来）
      local hm = nil
      pcall(function() hm = ad:find("home") end)
      if hm ~= nil then
        -- ★ 分家：hm:SetVisible(true) 已搬到块外（见「手动显形（分家后）」）
        -- ★ 分家：hm:SetActive(true) 已搬到块外
        print("[murdoku]   已对 home 容器也调了一次 SetVisible/SetActive")
      end
    end
    print("[murdoku] ===== 诊断二结束 =====")
    -- ★ 诊断三（运行时新建控件做对照）已经在用户实测中完成使命：
    --   **运行时新建的控件可见，编辑器里已有的不可见** —— 结论直接指向
    --   `respect_editor_rect` 那一条（见 ui_controller 的 `inherit_pos_runtime`）。
    --   那个探针控件就是用户看到的"白块"，已删除，不再创建。

  end
  -- ★★★★ 2026-10-01 **射线落点探针**：给几个"容器/弹窗"也绑上点击。
  --
  --   为什么：选关页上 `select.back` / `select.card.*` 的 visible/坐标/bind 全对，
  --   而用户"所有位置都点了一遍"却**零点击日志**。可 `select` 容器自己**没绑点击**
  --   => "没日志"并不能区分"射线被别人吃了"和"射线落在没绑事件的控件上"。
  --   => 给容器们绑一遍：**谁收到日志，射线就落在谁身上**。
  --      容器能收到 => 射线到得了这一层，子控件却没收到 => 子控件的射线被谁挡住/顺序不对
  --      容器也收不到 => 更上层还有东西（游戏自己的 UI 层）
  if not Murdoku._ray_probe_done and (current.frames or 0) >= 100 then
    Murdoku._ray_probe_done = true
    local ad3 = current.adapter
    -- ★★★★★ 2026-10-06 **名单按真机实测修正** ✗✓
    --   旧的 7 个里 `select` / `intro` / `toast` / `modal` / `board` **都不存在** ✗
    --   ⇒ ★ 每次刷 7 行「射线探针：X 找不到或不支持光标事件」✗
    --     ★ 而 `root` / `home` **其实存在** ✓ 只是不支持光标事件 ✓
    --     ⇒ ★★ 那句话把两种完全不同的情况混成一句 ✗ ⇒ 读起来像"控件没了" ✓
    --   ⇒ 只探**真机确认存在**的容器 ✓（★ 依 2026-10-05/06 真机日志 ✓）
    local probe_ids = { "root", "home", "stage", "clues", "topbar", "toolbar", "right", "board.bg" }
    for i = 1, #probe_ids do
      local pid = probe_ids[i]
      local c = nil
      pcall(function() c = ad3:find(pid) end)
      local clickEnum = nil
      pcall(function() clickEnum = Enum.CursorEventType.CursorClick end)
      if clickEnum == nil then
        pcall(function() clickEnum = Enum.CursorEventType.CursorClickDown end)
      end
      if c ~= nil and c.AddCursorEventListener ~= nil and clickEnum ~= nil then
        local okb = pcall(function()
          c:AddCursorEventListener(clickEnum, function()
            print("[murdoku] RAY-HIT = " .. pid .. " （射线落在这个容器上）")
          end)
        end)
        print("[murdoku] 射线探针：" .. pid .. " 绑定=" .. tostring(okb))
      elseif clickEnum == nil then
        print("[murdoku] 射线探针：读不到 Enum.CursorEventType.CursorClick，跳过")
        break
      else
        print("[murdoku] 射线探针：" .. pid .. " 找不到或不支持光标事件")
      end
    end
    -- ★★★★★ 2026-10-02 **打印所有客户端 UI 根**。
    --
    --   为什么：用户的观察把范围压到了最后一格 ——
    --     · 把 `home`/`select` 缩成 1x1 之后，**选关页该有的按钮消失了**（被父级裁剪）
    --     · 而**"处处有音效"依旧** ⇒ 那个吃点击的全屏按钮**不是** home/select
    --     · 排行榜里只有 `root` 一个全屏 ⇒ **它不在 root 的子树里**
    --   ⇒ 结论：**它在另一个客户端 UI 根上**。
    --   适配器注释里写着查找用的是 `game.GetClientUIRoots()`（**复数**），
    --   而脚本从头到尾只用了一个 `root`。把这些根全部列出来，那个全屏按钮就会现形。
    dprint("[murdoku] ===== 客户端 UI 根清单 =====")
    do
      local roots = nil
      pcall(function() roots = game.GetClientUIRoots() end)
      if type(roots) ~= "table" then
        dprint("[murdoku]   读不到 game.GetClientUIRoots()（或返回非表）")
      else
        dprint("[murdoku]   共 " .. tostring(#roots) .. " 个根")
        for i = 1, math.min(#roots, 12) do
          local r = roots[i]
          local nm, v, w, h = "?", "?", 0, 0
          pcall(function() nm = tostring(r.name) end)
          pcall(function() v = tostring(r.visible) end)
          pcall(function()
            local a, b = r:GetSizeDelta()
            if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
          end)
          local kids = nil
          pcall(function() kids = r:GetChildren() end)
          local nk = (type(kids) == "table") and #kids or -1
          dprint(string.format("[murdoku]     %d. %-18s visible=%-5s %6.0fx%-6.0f 子控件=%d",
            i, nm, v, w or 0, h or 0, nk))
          -- 根下面直接可见的大控件 —— 那个全屏按钮多半就在这一层
          if type(kids) == "table" then
            for k = 1, math.min(nk, 20) do
              local c = kids[k]
              if c ~= nil then
                local cn, cv, cw, ch, hasCur = "?", "?", 0, 0, false
                pcall(function() cn = tostring(c.name) end)
                pcall(function() cv = tostring(c.visible) end)
                pcall(function()
                  local a, b = c:GetSizeDelta()
                  if type(a) == "table" then cw, ch = a.x, a.y else cw, ch = a, b end
                end)
                pcall(function() hasCur = (c.AddCursorEventListener ~= nil) end)
                if (cw or 0) * (ch or 0) > 20000 then
                  dprint(string.format("[murdoku]        └ %-20s visible=%-5s %6.0fx%-6.0f 可接收光标=%s",
                    cn, cv, cw or 0, ch or 0, tostring(hasCur)))
                end
              end
            end
          end
        end
      end
    end
    dprint("[murdoku] ===== 根清单结束 =====")
    -- ★★★★★ 2026-10-02 **对照组诊断**：把"能点的样本"和"不能点的样本"逐一对比。
    --
    --   ⚠️ 第一版这里全部报「找不到」—— 因为直接用了 `ad:find(id)`，
    --   而同一份日志里「诊断二」用**同一个调用**却能拿到 `home.select`。
    --   ⇒ 不再依赖 `find`：**自己从 `root` 遍历整棵树建一张 name→控件 的表**，
    --     然后从表里取。这样"取不到"只可能是名字真不在树里。
    dprint("[murdoku] ===== 对照组：能点 vs 不能点 =====")
    do
      local rootC = nil
      -- ★★★★★ 2026-10-05 **第一遍代码体检修**：这里原来写 `ad:find("root")`，
      --   而 `local ad = current.adapter` 在 **734 行**、它所在的 if 块 **892 行就结束了**
      --   ⇒ 这一句在块外读的是一个**不存在的全局 `ad`**（= nil）
      --   ⇒ `attempt to index a nil value (global 'ad')` 被 pcall **静默吞掉**，
      --     一个错误都不报（症状与这一轮修掉的 `screen` 恒真 bug 同一类）。
      --   本块内的适配器变量叫 **`ad3`**（见 903 行）。
      pcall(function() rootC = ad3:find("root") end)
      -- 兜底：从 GetClientUIRoots 拿
      if rootC == nil then
        local rs = nil
        pcall(function() rs = game.GetClientUIRoots() end)
        if type(rs) == "table" and rs[1] ~= nil then rootC = rs[1] end
      end
      local map, count = {}, 0
      if rootC ~= nil then
        local function walk(c, depth)
          if c == nil or depth > 6 then return end
          local nm = nil
          pcall(function() nm = c.name end)
          if nm ~= nil and nm ~= "" and map[nm] == nil then map[nm] = c count = count + 1 end
          local kids = nil
          pcall(function() kids = c:GetChildren() end)
          if type(kids) == "table" then
            for k = 1, math.min(#kids, 200) do walk(kids[k], depth + 1) end
          end
        end
        walk(rootC, 0)
      end
      dprint("[murdoku]   树里共收集 " .. tostring(count) .. " 个具名控件（root=" .. tostring(rootC ~= nil) .. "）")
      local fields = { "visible", "active", "showCursor", "interactable", "raycastTarget",
                       "clickAudioId", "disableCursorEventPassthrough", "disableKeyEventPassthrough",
                       "isolateNavigation", "alpha", "index", "zIndex", "sortingOrder",
                       "enable", "enabled", "blockRaycast", "grayed", "isEnabled" }
      -- ★★★★★ 2026-10-06 **名单按真机实测修正** ✗✓（旧名单里 3 个名字不存在 ✗：
      --   `select.card.1` `select.back` `board` ⇒ ★ 每次都刷 3 行"树里没有这个名字" ✓
      --   ⇒ ★ 这一段是「能点 vs 不能点」的对照组 ✗ ⇒ ★ 拿不存在的名字对照毫无意义 ✓）
      local samples = { "home.select", "cell.1.1", "selbtn.1", "selbtn.2",
                        "action.back", "hex.submit", "hit.submit",
                        "clues.bg", "clues.grid", "tpl-container", "board.bg", "home" }
      for s = 1, #samples do
        local id = samples[s]
        local c = map[id]
        if c == nil then
          dprint("[murdoku]   " .. id .. "  —— **树里没有这个名字**")
        else
          local parts = {}
          for f = 1, #fields do
            local v = "?"
            pcall(function() v = tostring(c[fields[f]]) end)
            if v ~= "nil" then parts[#parts + 1] = fields[f] .. "=" .. v end
          end
          local chain, cur, guard = {}, c, 0
          while cur ~= nil and guard < 8 do
            local nm, sc, vv = "?", "?", "?"
            pcall(function() nm = tostring(cur.name) end)
            pcall(function() sc = tostring(cur.showCursor) end)
            pcall(function() vv = tostring(cur.visible) end)
            chain[#chain + 1] = nm .. "(vis=" .. vv .. ",cur=" .. sc .. ")"
            local up = nil
            pcall(function() up = cur.parent end)
            if up == nil then pcall(function() up = cur:GetParent() end) end
            cur = up
            guard = guard + 1
          end
          dprint("[murdoku]   " .. id .. "  " .. table.concat(parts, "  "))
          dprint("[murdoku]       祖先链：" .. table.concat(chain, " ← "))
        end
      end
    end
    dprint("[murdoku] ===== 对照组结束 =====")
    print("[murdoku] 射线探针装好了 —— 之后点任何地方，只要射线落在这些容器上就会打日志")
  end
  -- ★★★★ 2026-10-02 **按用户建议做的对比：主页 ⇄ 选关，"切换后到底改了什么"**。
  --
  --   用户原话：「我认为应该好好对比一下首页和选关切换后到底改了什么」
  --   —— 这条方法是对的。我前面 9 轮都在猜机制（raycastTarget / childCount / 递归隐藏…），
  --   而**事实是两份排行榜摆在那里**：
  --     主页可见：root / home / home.title / home.*四键 / face / content / obj / bg×4 / label×4
  --     选关可见：root / select / select.title / card.1~4 / back / face / content
  --   ⇒ **交集只有 root + face + content** —— 后两个正是**格子模板的子控件（135x135）**，
  --     也是我所有"隐藏"都没碰到的东西。
  --   ⇒ 但它们只有一块 135x135，解释不了"所有位置都点不动" ⇒ **必须知道它们在屏幕的哪**。
  --   ⇒ 这里拍两份快照（切屏前 / 切屏后），**带屏幕坐标**，并打印**差集**。
  local function snap_visible()
    local out = {}
    local rt = nil
    -- ★★★★★ 2026-10-05 **第一遍代码体检修**：原来写 `ad:find("root")` ——
    --   但 `ad` 是**上一个 if 块里的局部变量**（734 行声明、892 行出作用域），
    --   在这里读到的是全局 nil ⇒ 抛错被 pcall 吞掉 ⇒ `rt == nil`
    --   ⇒ 下面 `if rt == nil then return out end` **每次都直接返回空表**
    --   ⇒ 这段"切屏对比"永远打印「没有多出来的 / 没有消失的 / 没有共同项」——
    --     **一段专门用来抓"隐形拦截层"的诊断，一直是空转 + 报平安**。
    --   这里用**当前适配器**（与同文件其它处一致，如 1158/1165 行的 `current.adapter`）。
    pcall(function() rt = current.adapter:find("root") end)
    if rt == nil then return out end
    local function walk(c, ox, oy, depth)
      if c == nil or depth > 6 then return end
      local v = nil
      pcall(function() v = c.visible end)
      -- ★★★★★ 2026-10-02 **去掉 visible 过滤**（用户三条答案指出的"眼罩"）。
      --
      --   用户观察：那个拦截层**全透明、不消失、Esc 无反应** ⇒ 是一个**隐形输入层**。
      --   而我之前所有排行榜都写着 `if v == true then`（只看 visible=true）
      --   ⇒ **一个 visible=false 但仍在拦截点击的控件，我一次都没列出来过**。
      --
      --   而脚本用的是 `SetVisible()` —— 关掉的是**渲染**；诊断里所有控件的
      --   `active` 都是 true ⇒ **不可见但仍然 active 的控件很可能照样参与射线**。
      --   ⇒ 改成：**不管 visible，一律列出来**，并把 visible / active 都打出来。
      local al = nil
      pcall(function() al = c.active end)
      if true then
        local nm, w, h, ax, ay = "?", 0, 0, 0, 0
        pcall(function() nm = tostring(c.name) end)
        pcall(function()
          local a, b = c:GetSizeDelta()
          if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
        end)
        pcall(function()
          local a, b = c:GetAnchoredPosition()
          if type(a) == "table" then ax, ay = a.x, a.y else ax, ay = a, b end
        end)
        if (w or 0) * (h or 0) > 1000 then
          -- 屏幕坐标 = 父级屏幕位置 + 自身偏移（Y 向上）；根级以画布中心为原点
          local sx = (ox or 0) + (ax or 0)
          local sy = (oy or 0) + (ay or 0)
          -- ★★★★★ 2026-10-05 **第一遍代码体检修（第 2 处，也是被第 1 处掩盖住的那处）**：
          --   这里原来是 `"%dx%d @屏幕(%.0f,%.0f)"` —— **`%d` 收到带小数的数会抛错**
          --   （Lua 5.3：`bad argument #2 to 'format' (number has no integer representation)`）。
          --   而 `w`/`h` 直接来自引擎的 `GetSizeDelta()`，真机上就是浮点。
          --   证据：把上面那个幻影变量 `ad` 修好、这段**第一次真的跑起来**之后，
          --     `tools/_probe_pcall_err.lua` 立刻抓到
          --     `./dist/client_script.lua:13368: bad argument #2 to 'format' (number has no integer representation)`
          --     而且它抛在 `walk()` 里、**外面没有 pcall** ⇒ 整帧 `on_update` 被打断
          --     ⇒ `tests/grid_cost.lua` 的 J2（换屏后 40 帧重扫射线）当场从 13/0 变 12/1。
          --   ⇒ 两个 bug 是**叠在一起**的：幻影 `ad` 让它永不执行，从而**掩盖**了这个 `%d`。
          --     只修前一个 = 把"静默空转"换成"每帧抛错"。所以必须一起修。
          --   改法：`%d` → `%.0f`（同文件上面那段"屏幕占用排行"用的就是 `%6.0f`，一致）。
          out[nm] = string.format("%.0fx%.0f @屏幕(%.0f,%.0f)", w or 0, h or 0, sx + 800, sy + 450)
        end
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 120) do
            walk(kids[i], (ox or 0) + (ax or 0), (oy or 0) + (ay or 0), depth + 1)
          end
        end
      end
    end
    walk(rt, 0, 0, 0)
    return out
  end
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **给「切屏对比」加闸** ✗✓ —— ★ 它是剩下的诊断里【最贵】的一块 ✓
  --
  --   ★ 起因（★ 真机日志实证 ✓）：★ 254 只关住了「开局诊断」那【一块】✗
  --     ★★ 而★ 日志里这几块**照旧打印** ✗：
  --       ★「===== 切屏对比：home → select」✓ ·「===== 切屏对比：select → level」✓
  --       ★「客户端 UI 根清单」✓ ·「对照组：能点 vs 不能点」✓ ·「逐格自检」✓
  --     ★★★ ⇒ ★ **"关了诊断但卡顿还在"就是这么来的** ✓✓
  --   ★ 为什么这块最贵 ✓：★ **两份全树快照（★ 80+ 控件 ✓）+ 逐项比较 + 格式化上百行** ✗
  --     ★★ 而★ 开局必经 **主页 → 选关 → 进关** ✗ ⇒ ★ **它一次开局跑两趟** ✓✓
  --   ★★ 判据（★ 干净可验 ✓）：★ **日志里【不该再出现】「===== 切屏对比」** ✓✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  if Murdoku.DIAG and (Murdoku._snap == nil or scr_now ~= Murdoku._snap_screen) then
    local now = snap_visible()
    if Murdoku._snap ~= nil then
      dprint("[murdoku] ===== 切屏对比：" .. tostring(Murdoku._snap_screen) .. " → " .. tostring(scr_now) .. " =====")
      dprint("[murdoku]   【切过去之后**多出来**的可见控件】（嫌疑最大）")
      local n_add = 0
      for k, v in pairs(now) do
        if Murdoku._snap[k] == nil then print("[murdoku]     + " .. k .. "  " .. v); n_add = n_add + 1 end
      end
      if n_add == 0 then print("[murdoku]     （没有多出来的）") end
      dprint("[murdoku]   【切过去之后**消失**的可见控件】")
      local n_del = 0
      for k, v in pairs(Murdoku._snap) do
        if now[k] == nil then print("[murdoku]     - " .. k .. "  " .. v); n_del = n_del + 1 end
      end
      if n_del == 0 then print("[murdoku]     （没有消失的）") end
      dprint("[murdoku]   【**两个页面都在**的可见控件】—— 这些不随切屏变化，最可能是「挡在中间」的")
      for k, v in pairs(now) do
        if Murdoku._snap[k] ~= nil then print("[murdoku]     = " .. k .. "  " .. v .. "   （切屏前 " .. Murdoku._snap[k] .. "）") end
      end
      dprint("[murdoku] ===== 对比结束 =====")
    end
    Murdoku._snap = now
    Murdoku._snap_screen = scr_now
  end
  -- ★★★ 2026-10-02 **撤掉每帧的图层排序**（`enforce_screen_layers`）。
  --
  --   为什么撤：新版「对照组诊断」证明 `home` 与 `select` 的**容器设置完全一致**
  --   （showCursor / disableCursorEventPassthrough / disableKeyEventPassthrough 都一样），
  --   子控件的 interactable / raycastTarget / clickAudioId 也一致 ⇒
  --   **"home 压住 select"这个当初的假设从来不是问题** ⇒ 这个排序没被证明有用，
  --   却可能有害（它把 select 排到最后 = 最上）。
  --   真机现象是"主页能点、选关不能点"，而主页时 select 被排到最下 ⇒ 排序**恰好与现象相关**
  --   ⇒ 撤掉，做一次单一变量的真机实验。
  --   （`Adapter:enforce_screen_layers` 本体留在适配器里，随时可以再开。）
  -- ★★★★★ 2026-10-02 **选关按钮的每帧排布**（脚本创建的控件）。
  --   选关页：4 个一行摆在屏幕中上部（棋子大小用格子的几何，视觉一致）；
  --   其它屏：全部隐藏（避免抢射线）。
  --   同时把编辑器摆的旧卡片/返回键**藏起来** —— 它们收不到点击，留着只会挡路。
  do
    local n_levels = 8
    do
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
    -- ★★★★★ 2026-10-02 重建后的显隐：`stage` 与它下面的 `selbar` / `selbtn.*`。
    --   旧代码里那段"把 board 设为可见"已经没意义 —— `board` 在重建时被删了。
    --   现在链条是：root → stage（脚本容器的家）→ selbar（脚本创建的容器）→ selbtn.N（脚本创建的按钮）
    do
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
        -- ★★★★★ 2026-10-05 Round 77 **读回再决定写不写** ✓（原来是无条件每帧写 ✗）
        --
        --   实测（`tests/_wip/probe_throttle_cost.lua` 第 [7] 节，稳态 30 帧）：
        --     `stage` 被写 **30 笔 = 1.00 笔/帧** ✗ —— 就是这一行造成的。
        --   而 `stage` 本来就该**一直可见** ✓ ⇒ 一旦读到 `visible == true` 就**永不重写** ✓✓
        --   本项目自己在 L1278 附近就写着「显隐只在关卡内为真，且**只在状态变化时**调
        --   `SetVisible`（不再每帧写）」✗ —— 这次是**把它做完** ✓
        --   ⚠️ 读不到 `visible`（引擎没这字段）时**仍然写** ✓ —— 不许因为读不到就不摆 ✓
        local sv = nil
        pcall(function() sv = s.visible end)
        if sv ~= true then pcall(function() s:SetVisible(true) end) end
        -- ★★★★★ 2026-10-02 **`stage` 要按"棋盘容器"的尺寸摆**，不能让它保持全屏。
        --
        --   为什么：格子的几何是**按父容器尺寸算**的（`cell_geometry` 读父级 sizeDelta）。
        --   父级从旧 `board`（677x677）换成 `stage`（1600x900）之后：
        --     旧：`边缘适配 wall.up：基准 80x20 → 目标 125x8`
        --     新：`边缘适配 wall.up：基准 80x20 → 目标 167x8`   ← 格子被放大了 33%
        --   ⇒ 棋盘虽然"存在且可见"，但布局跟设计对不上（用户："还没有棋盘出现"）。
        --   ⇒ 这里把 `stage` 恢复成棋盘应有的尺寸并居中；`selbar`（选关条）自己另有尺寸。
        -- ★★★★★ 2026-10-04 **棋盘几何全部按规划图 v3 重来**（投影法量到像素，见 ui_controller 的 LAYOUT.board）。
        --
        --   规划图（1600×900，已经是画布空间）量出来：
        --     棋盘外框 584×584、中心 (900, 470)（自下往上）
        --     边框四边均匀 14px；内区 556 ⇒ 5 格 × 108 + 4 条 × 4px 缝
        --   旧值是 677×677 @ (0,0)：**大了 93px 且位置偏**（中心 764,451 vs 900,470）
        --   —— 用户原话「底板大小可以调一下，溢出边框了」「棋盘也没有位移」。
        pcall(function() s:SetSizeDelta(BOARD_W, BOARD_H) end)
        pcall(function() s:SetAnchoredPosition(BOARD_X, BOARD_Y) end)
      end
      local bar = nil
      pcall(function() bar = current.adapter:find("selbar") end)
      if bar ~= nil then
        -- ★★★★★ 2026-10-05 Round 74 **删掉这里的 `bar:SetVisible(on_select)`** ✗
        --
        --   为什么删：它**每帧无条件写** ✗ —— 实测（`tests/_wip/probe_throttle_cost.lua`，
        --   稳态 600 帧）它一个人就写了 **603 笔** ✓ ⇒ 而**下面那段**（`setv("selbar", in_select)`）
        --   已经**每帧**在维护同一个控件 ✓，而且做得更好：
        --     · **读回真实 `visible`** ⇒ 已经等于目标就**一笔都不写** ✓
        --     · **写值记忆** + **进关/换屏后 60 帧强压窗口** ✓
        --   两处都在写同一个控件 ⇒ **一条规则两个权威** ✗ ⇒ 必然互相抵消、白烧引擎写 ✗
        --   （本项目刚在 BOM 规则上踩过同一个坑：两条相反规则互相拆台 ✗）
        --
        --   ⚠️ 下面 `if on_select then … 摆位置/尺寸 … end` **必须保留** ✓
        --      —— 那是**布局**逻辑 ✓ 与"可见性归谁管"无关 ✓
        --   验收：`probe_throttle_cost.lua` 第 [2] 段「稳态每帧写次数」应从 8.7 → 0 ✓
        if on_select then
          pcall(function() bar:SetAnchoredPosition(0, 0) end)
          pcall(function() bar:SetSizeDelta(1500, 700) end)
        end
      end
    end
    -- ★★★★★ 2026-10-04 **棋盘底板：这一轮修掉用户报的三个问题。**
    --
    --   目标（不变）：`cfg.cells.gap = 6`（格子 size = 129 < pitch = 135）⇒ 格子之间留 6px 缝，
    --   缝里露出**一块更深色的底** ⇒ 天然网格线。**1 个额外控件**，移动端无负担。
    --
    --   用户 2026-10-04 报的三个现象 + 真机日志给出的真凶：
    --     ① 三个界面都出现   ← 这段**每帧无条件** `SetVisible(true)`
    --     ② 图层在棋盘之上   ← 运行时新建的控件**追加**在父级子列表**末尾** = 最上
    --     ③ 没有配图         ← 在**根节点**上调 `SetImage` 静默失败（`imageId` 恒为 0）
    --
    --   ★★ 而且日志里 `棋盘底板：board.bg 建=true 设图=false imageId=0` **重复了上百次**
    --      ⇒ 这段**每帧都在新建一块底板**。原因：`Adapter:find()` 未命中会**永久缓存 false**
    --      （适配器里早写明了这个坑），所以 `find("board.bg")` 永远是 nil
    --      ⇒ 每帧 `bg == nil` ⇒ 每帧再造一个 677×677 的空白控件叠上去。
    --      上百块白板压在棋盘上，正好同时解释三个现象。
    --
    --   ⇒ 四条修法（一一对应）：
    --     · 引用走 `adapter.controls["board.bg"]` 直接引用，**不再用 `find`**（并加"只建一次"的语义）
    --     · 建完立刻 `SetSiblingIndex(0)` 把它压到**最底层**（盖不住 25 个格子）
    --     · 配图走**子控件**：`Adapter:set_image_deep()`（根上设图无效，已验证）
    --     · 显隐只在**关卡内**为真，且**只在状态变化时**调 `SetVisible`（不再每帧写）
    --
    --   ⚠️ 染色：真机**没有全局函数 `Color`** ⇒ `imageColor` 只能直接写 32 位整数，
    --      且 `imageColor` 是**乘算**（乘白=不变色、乘深色=压暗，**压不出比素材更亮的颜色**）。
    --      ⇒ 首选**本身就深**的官方底板素材（改 `STAGE_BG_ID`），不到万不得已不染色。
    do
      -- ① 首选：**纯色图形 + 染色**（用户 2026-10-04 22:53 点名要的）
      --
      --   `106053` = 96x96 **纯白**底板（格子 `face` 用的就是它 ⇒ 颜色在截图里是白的）
      --   ⇒ 白模 × 染色 = **想要什么色就是什么色**，这就是"纯色图形"。
      --   挑它而不是 `100001`（256x256 纯白方块）：两者都是白模，但 `100001` 属于
      --   「基础形状」类，而 `106053` 属于「底板」类 —— **底板类已在本机验证过 `Stretch`**
      --   （格子 face 就是 96x96 拉伸到 129 显示的）⇒ 风险最低。
      local STAGE_BG_ID   = 106053
      local STAGE_BG_TINT = 0xFF2C2820   -- 暖黑 #2C2820（ARGB）；乘算：白模 × 此色 = 目标色
      -- ② 回退：染色万一不生效，就用**本身就深色**的官方底板（2026-10-04 全量实测选出来的）
      local STAGE_BG_FALLBACK_ID = 107003
      local in_level = (scr_now == "level")
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      -- ★ 只有**棋盘界面（关卡内）**要底板。主页 / 选关页一律收起。
      if s ~= nil and not in_level then
        -- 离开关卡（或从没进过关卡）：把底板藏起来。
        --
        -- ★★★★★ 2026-10-04 **不能再只依赖 `controls["board.bg"]` 那个缓存引用。**
        --
        --   真机日志（16:40，v042）：**三屏都是 `board.bg 可见=true`** ——
        --   用户报「底板在首页和选关界面的显示没有关掉」。
        --   原因：`board.bg` 是**在编辑器里摆的**，它自带 `visible=true`；
        --   而认领它只发生在**进过关卡**之后（下面那个 `elseif`）。
        --   所以「首页 → 选关」这条路上 `controls["board.bg"]` 一直是 nil ⇒
        --   这段 `if old ~= nil` 直接跳过 ⇒ 底板保持编辑器里的可见，而在选关页
        --   `stage` 是可见的（脚本每帧强制打开）⇒ **底板就露在选关页上**。
        --   ⇒ 这里改成：缓存没有就**去活树上按名字现查一次**（`GetChild` 不吃 find 的缓存）。
        local old = (current.adapter.controls and current.adapter.controls["board.bg"]) or nil
        if old == nil then
          pcall(function() old = s:GetChild("board.bg") end)
        end
        if old ~= nil then
          if current._board_bg_vis ~= false then
            pcall(function() old:SetVisible(false) end)
            current._board_bg_vis = false
          end
          pcall(function() current.adapter.controls["board.bg"] = nil end)
        end
      elseif s ~= nil then
        -- ★★★★★ 2026-10-03 **实测结论：`stage` 不是图片控件** ——
        --   真机日志（23:12）：`stage 设图 106053 → 回读 imageId=nil；okcol=false`
        --   ⇒ `SetImage` / `imageColor` 对它都被忽略 ⇒ "给 stage 铺底"走不通。
        --   ⇒ 改用**客户端图片模板**（`cfg.prefab_icon`）另建一个铺满棋盘的控件
        --     `board.bg`，放进 `stage` 当底板。
        --
        --   ★ 2026-10-04：**这段必须"只建一次"**。旧代码用 `find("board.bg")` 判存在，
        --     而 `find` 未命中会永久缓存 false ⇒ 每帧都判成"不存在" ⇒ 每帧新建一块。
        --     现在改成先读 `controls["board.bg"]`（直接引用），必要时再查活树。
        local bg = (current.adapter.controls and current.adapter.controls["board.bg"]) or nil
        if bg == nil then
          -- 活树查询（`GetChild` 直连，不吃 find 的名字缓存）
          pcall(function() bg = s:GetChild("board.bg") end)
          if bg ~= nil then
            current.adapter.controls = current.adapter.controls or {}
            current.adapter.controls["board.bg"] = bg
          end
        end
        local just_built = false
        if bg == nil and game ~= nil and game.InstantiateClientUIControl ~= nil then
          local ip = current.adapter.cfg and current.adapter.cfg.prefab_icon
          if ip ~= nil then
            local okb, ob = pcall(game.InstantiateClientUIControl, ip, s)
            if okb and ob ~= nil then
              pcall(function() ob.name = "board.bg" end)
              pcall(function() ob:SetSizeDelta(677, 677) end)
              pcall(function() ob:SetAnchoredPosition(0, 0) end)
              -- ★★ 图层：运行时新建的控件会被**追加**到父级子列表末尾 = 显示在**最上**。
              --    不排一下，底板就会盖住 25 个格子（用户报的"图层在棋盘之上"）。
              --    官方：`SetSiblingIndex` 数值越大越靠上 ⇒ 0 = 最底。
              --
              --    ★ 两个 API **都调**，不二选一：`SetSiblingIndex` 在本项目**没有真机验证过**
              --      （`enforce_screen_layers` 里那条被注释掉了，当时代码注释写的是"撤掉做单一变量实验"），
              --      而 `SetAsFirstSibling` 是 `enforce_layers` 一直在用的。
              --      只调一次、两条腿都走，比赌一个 API 靠谱；回读的兄弟序号会告诉我们到底有没有生效。
              local layered = {}
              if ob.SetSiblingIndex ~= nil then
                if pcall(function() ob:SetSiblingIndex(0) end) then layered[#layered + 1] = "SetSiblingIndex(0)" end
              end
              if ob.SetAsFirstSibling ~= nil then
                if pcall(function() ob:SetAsFirstSibling() end) then layered[#layered + 1] = "SetAsFirstSibling()" end
              end
              if #layered == 0 then layered[#layered + 1] = "没排（两个 API 都没有）" end
              -- 回读兄弟序号：`pcall` 为真只说明"没报错"，序号才说明**真的排上了**
              -- （0 = 最底 ⇒ 底板在 25 个格子下面）
              local sib = "?"
              pcall(function() sib = tostring(ob:GetSiblingIndex()) end)
              -- ★★ 配图：**根节点设图无效**（真机 `设图=false imageId=0`），
              --    必须走子控件 ⇒ 用适配器里那条已经跑通的路（`Adapter:set_image_deep`）。
              --
              --    ★ 2026-10-04 **两条路：先试"纯色图形"，不成就回退**。
              --      用户点名要"底板换成纯色图形"，而官方素材库里**形状/底板全是白模**
              --      ⇒ 纯色只能靠 `imageColor` 染出来。而"染色能不能用整数写进去"在本项目
              --      **没有真机证据** ⇒ 这里**不信"调用了就算成功"**：回读颜色，真变了才认；
              --      没变就换成 `107003`（自带深色、上一轮真机已验过出图正常）。
              --      这样无论染色能不能用，**棋盘都不会退回"看不出网格线"**。
              local okimg, via, rid, tint_ok = current.adapter:set_image_deep(
                ob, STAGE_BG_ID, "Stretch", STAGE_BG_TINT, "board.bg(纯色图形)")
              local used_mode = "纯色图形+染色"
              if tint_ok ~= true then
                local ok2, via2, rid2 = current.adapter:set_image_deep(
                  ob, STAGE_BG_FALLBACK_ID, "Stretch", nil, "board.bg(回退：自带深色)")
                used_mode = "回退：自带深色底板（染色不生效）"
                okimg, via, rid = ok2, via2, rid2
              end
              if print then
                print("[murdoku] 棋盘底板：新建 board.bg  用法=" .. used_mode
                  .. "  染色判定=" .. tostring(tint_ok)
                  .. "  设图成功=" .. tostring(okimg)
                  .. "  imageId 回读=" .. tostring(rid)
                  .. "  经 " .. tostring(via)
                  .. "  图层=" .. table.concat(layered, "+")
                  .. "  兄弟序号回读=" .. tostring(sib) .. "（0=最底）"
                  .. "  —— 这一行**只应出现一次**；若重复出现说明「只建一次」没生效")
              end
              current.adapter.controls = current.adapter.controls or {}
              current.adapter.controls["board.bg"] = ob
              bg = ob
              just_built = true
            end
          end
        end
        if bg ~= nil and just_built then
          -- 新建的控件默认可见，但我们要的是"关卡内可见"的统一口径 ⇒ 交给下面的状态同步
          current._board_bg_vis = nil
        end
        -- ★★★★★ 2026-10-04 **把底板撑成棋盘大小** —— 修"底板溢出棋盘"。
        --
        --   真机日志（16:35，v041）：`board.bg 677x677 可见=true` 而 `stage 584x584`
        --   ⇒ 底板比棋盘**大 93px**（每边多 46.5）⇒ 就是用户说的"底板还是溢出了棋盘"。
        --
        --   为什么：`board.bg` 是**你在编辑器里摆的**（当初我让你按 677×677 摆，
        --   那是按没量过的 812 推出来的尺寸）。脚本这边只认领、从不动它的几何 ⇒
        --   棋盘缩到 584 之后，它还是 677。
        --   ⇒ 现在让它**跟着 stage 走**：尺寸 = stage 的实时尺寸，位置 (0,0) 对齐中心。
        --     只在尺寸变化时写一次（移动端：不做每帧 SetSizeDelta）。
        if bg ~= nil and s ~= nil then
          local sw, sh = nil, nil
          pcall(function() sw, sh = s:GetSizeDelta() end)
          if type(sw) == "number" and type(sh) == "number" and sw > 0 and sh > 0 then
            if current._board_bg_size ~= sw then
              pcall(function() bg:SetSizeDelta(sw, sh) end)
              pcall(function() bg:SetAnchoredPosition(0, 0) end)
              current._board_bg_size = sw
              local rw, rh = nil, nil
              pcall(function() rw, rh = bg:GetSizeDelta() end)
              if print then
                print("[murdoku] 底板对齐棋盘：stage " .. tostring(sw) .. "x" .. tostring(sh)
                  .. " → board.bg 回读 " .. tostring(rw) .. "x" .. tostring(rh))
              end
            end
          end
        end
        -- ★ 显隐：**只在状态变化时**写一次（不再每帧 SetVisible ⇒ 省一次跨引擎调用）
        if bg ~= nil then
          local want = true
          if current._board_bg_vis ~= want then
            pcall(function() bg:SetVisible(want) end)
            current._board_bg_vis = want
          end
        end
      end
    end
    -- ★★★★★ 2026-10-02 **这是"四个按钮看不见"的原因**：
    --   `selbtn.*` 的父级是 **`board`**，而 `board` 在选关页是 `visible=false`
    --   ⇒ **父级不可见，子控件跟着不可见** ⇒ 脚本再怎么 `SetVisible(true)` 都白搭。
    --   ⇒ 选关页把 `board` 也设为可见（棋盘格 `cell.*` 本来就是藏着的，不会露出来）。
    -- （旧的 "board 在选关页可见" 已删：重建后 board 不存在了）
    for i = 1, n_levels do
      local c = nil
      pcall(function() c = current.adapter:find("selbtn." .. tostring(i)) end)
      if c ~= nil then
        -- ★★★★★ 2026-10-05 Round 74 **同样删掉这里的 `c:SetVisible(on_select)`** ✗
        --   与上面 `selbar` 那处同一个理由 ✓：它对 6 个 `selbtn.*` **每帧无条件写** ✗，
        --   而下面那段（`setv("selbtn."..i, in_select)`）已经每帧在维护同一批控件 ✓
        --   且**只在值真的变了时才写** ✓ ⇒ 两处同时写 = 白烧引擎写 ✗ + 互相抵消 ✗
        --   ⚠️ 下面的摆位置/尺寸**保留** ✓（布局逻辑 ✓）
        if on_select then
          -- 一行摆开：间距 200，起点居中
          local x = (i - (n_levels + 1) / 2) * 200
          pcall(function() c:SetAnchoredPosition(x, 120) end)
          pcall(function() c:SetSizeDelta(160, 160) end)
        end
      end
    end
    -- ★★★★★ 2026-10-02 **删掉"把旧卡片/返回键藏起来"那段** —— 它就是你截图里
    --   "选关界面的按钮没了"的元凶。
    --
    --   那是我 10-02 早上为了做"脚本创建选关按钮"的对照实验加的：
    --       -- 旧卡片/返回键：选关页也不显示（它们点不动）
    --       for i = 1, 8 do ... select.card.i : SetVisible(false) end
    --       select.back : SetVisible(false)
    --   它**每帧无条件执行**，于是：
    --       · 「选择关卡」标题还在（那是 text 类型，脚本没动它）
    --       · 4 张卡片 + 「返回」全没了（按钮类型，被这段藏了）
    --   —— 用户给的两张截图正好对上：10-01 23:18（这段还不存在）里有按钮，
    --      10-02 09:42（这段存在）里只剩标题。
    --
    --   ⇒ 现在删掉。可见性重新交给 `ui_controller` 的按屏规则（选关页显示 `select.*`）。
    --      上半段 `selbtn.*` 的循环也只在 `widgets = true` 时才让 `on_select` 为真，
    --      默认配置下它什么都不做，不会干扰 93 里原有的卡片。
  end
  -- ★★★★★ 2026-10-04 **整块删掉"把 topbar / right 锚点归零"** —— 它是错的，两半都是。
  --
  --   历史：2026-10-02 为了让"子控件不再双重偏移"加了这段
  --   （当时真机日志：`right` pos=(575,-23)，子控件 `hud.progress` pos=(508,-283)
  --     ⇒ 800+575+508 = 1883 跑出屏幕）。2026-10-04 先把 `topbar` 从名单里去掉（v039），
  --   现在把 `right` 也去掉 —— **因为真正决定位置的不是存档里的几何**。
  --
  --   ★★ 机制（2026-10-04 全量核对 324 个规划节点 vs 93 条记录，确认）：
  --     运行时会把**规划里的几何重新下发**：`root` 带 `pos_runtime=true`，
  --     `inherit_pos_runtime` 沿树传播 ⇒ 每个规划内的控件都被
  --       `SetAnchor(0.5)/SetPivot(0.5)` + `SetSizeDelta(规划)` +
  --       **`SetAnchoredPosition(规划中心 − 规划父级中心)`**
  --     推一遍。而 `anchoredPosition` 是**相对真实父级中心**解释的
  --     ⇒ **父级的实际中心必须等于规划里的父级中心**，否则整支子树整体偏移。
  --
  --   ⇒ 于是"把容器锚点归零"= 人为把父级中心从「规划中心」搬到「屏幕中心」，
  --     **恰好毁掉上面那个不变式**，子控件就整支偏掉：
  --        `topbar` 规划中心 y=857，归零后 450 ⇒ 子控件**下移 407px**
  --          （`hud.title` 画在 y=457，规划要 864 ← 用户截图对得上）
  --        `right`  规划中心 x=1375，归零后 800 ⇒ 子控件**左移 575px、下移 23px**
  --          （`hud.progress` / `action.hint`；这两个**至今没修**）
  --
  --   ⇒ 正确做法：**不动容器**，让运行时把规划几何推下去。
  --     存档里那 19 个规划内控件的几何值**本来就不上屏**，所以也不用去改 `.gil`。
  --
  --   ⚠️ 连带修正：`action.redo` 的**规划父级是 `root`、存档父级是 `topbar`**。
  --     归零时代两者中心都是屏幕中心 ⇒ 这个不一致**碰巧无害**；
  --     一旦归还 `topbar` 的偏移，它就会高出 407px ⇒ 已把规划父级改成 `topbar`
  --     （见 `ui_controller` 里 `btn("action.redo", ...)`）。
  -- ★★★★★ 2026-10-02 **UI 容器定位诊断**：真机"right/topbar 可见=true 但看不到"，
  --   所以把它们的**位置/尺寸/透明度/同级顺序**全打出来，一次看清问题在哪。
  -- ★ 2026-10-03 删除「容器 UI定位」诊断块（纯只读 + print）。整块删掉，不保留 if false。
  -- ★★★★★ 2026-10-03 **六边形素材：直接测实例化**（第一组接入的诊断）
  --
  --   真机日志（16:13）里，`action.hint.hexbg` / `action.redo.hexbg` 出现在
  --   "这些控件还没建"清单里 ⇒ **它们压根没被创建**，不是"位置不对"。
  --   按"先看输出、再解释现象"的规矩，这里**直接调一次实例化并把返回值打出来**：
  --     · 返回非 nil ⇒ 实例化这条路是通的，问题在"我们没让它建"（计划/配置）
  --     · 返回 nil   ⇒ 这条路本身不通（索引不对 / 该模板不是客户端控件模板）
  -- ★ 2026-10-03 删除「六边形素材实例化探针」：它每 300 帧真的调 InstantiateClientUIControl 建两个控件再销毁，是"棋盘出现慢"的主因。纯诊断（只操作它自己建的临时对象 + print）⇒ 整块删掉，而不是 if false 关掉。
  -- ★ 每 300 帧打印一次"第一个格子的屏幕坐标" —— 一眼看出棋盘在屏幕哪、有没有跑出去。
  if (current.frames or 0) % 300 == 0 then   -- 还原（原条件）
    local c1 = nil
    pcall(function() c1 = current.adapter:find("cell.1.1") end)
    if c1 ~= nil then
      local ax, ay, w, h = 0, 0, 0, 0
      pcall(function()
        local a, b = c1:GetAnchoredPosition()
        if type(a) == "table" then ax, ay = a.x, a.y else ax, ay = a, b end
      end)
      pcall(function()
        local a, b = c1:GetSizeDelta()
        if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
      end)
      -- stage 自己的位置（父级中心在画布里的偏移）
      local sx, sy = 0, 0
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
        pcall(function()
          local a, b = s:GetAnchoredPosition()
          if type(a) == "table" then sx, sy = a.x, a.y else sx, sy = a, b end
        end)
      end
        -- ★★★★★ 2026-10-03 **删掉每帧打印的「格子定位」**（原 L1193~1196）。
        --   它是**每帧**执行的 `string.format` + `print`，真机日志里同一行连续出现十几次，
        --   是当前脚本**最大的单点开销**。整块只有打印，没有功能 ⇒ 直接删掉。
        --   需要恢复时：git 上取本提交之前的版本，或看向导里的 `versions\019`。
        --   ⚠️ 下面「每帧点亮 face」那段是**功能**（SetVisible），保留不动。
    end
    -- ★★★★★ 2026-10-02 **每帧把格子的底图 `face` 点亮（只在关卡内）**。
    --
    --   真机证据（用户 17:05 日志，同一个 face 前后矛盾）：
    --       ✅ 子控件 face 存在（**visible=true**）   ← 体检时（`_cells_paint` 刚设完）
    --       …后面「格子里的子控件清单」…
    --       face  visible=**false**                  ← 每帧再读就变回 false 了
    --   ⇒ 中间有别的"格子外观下发"把 `face` 又设回 false（那套逻辑按状态设
    --     `note`/`x`/`wall.*`，但它**不知道 `face` 应该一直亮着**）。
    --   ⇒ 与其去改那套逻辑的每一处（容易漏、容易再引入新问题），**在这里每帧重新点亮**：
    --     这段每帧最后执行，顺序上必然赢。只在关卡内做（选关页不需要棋盘）。
    -- ★★★★★ 2026-10-02 **注意：`scr_now` 永远不会是 nil！**
    --   L620 写的是 `…controller.screen or "level"` —— 关卡内 controller.screen 是 nil，
    --   但这行把 nil 变成了字符串 "level"。所以我前两版写的 `if scr_now == nil then`
    --   **永远为假** ⇒ 这段每帧代码从来没跑过（连我加的诊断打印都没出现，原因就是这个）。
    -- ★★★★★ 2026-10-03 **移动端负载优化**：下面这段"每帧点亮 25 个 face"原本**每帧**都跑，
    --   每帧约 25×(字符串拼接 + find + GetSizeDelta + GetChildren + 若干 tostring + 约 6 次 SetXXX)
    --   ≈ **375 次 pcall**，60fps 下就是 22500 次/秒 —— PC 无感，**移动端就是掉帧/发热/耗电**。
    --   而写进去的值绝大多数与上一帧完全相同（幂等）⇒ 纯浪费。
    --   ⇒ 改成**每 30 帧跑一次**（每秒 2 次），开销降到约 1/30。
    --     正确性：引擎若在状态变化后关掉 `face`，**最多 0.5 秒后会被这段自动点亮**，视觉无感。
    --   ⚠️ 想调频率只改下面的 `30`；想恢复原行为就改成 `1`（= 每帧）。
    --   ★ 实现方式：**只改这个 if 的条件，不新增 if** —— 避免上次"新增 if 导致 end 配对错位"的坑。
    -- ★★★★★ 2026-10-03 **按屏幕同步"运行时创建的控件"的可见性**。
    --
    --   真机 bug（22:00 / 22:07 日志）：关卡界面里 `selbar`(1500x700) 和它的 4 个 `selbtn.*`
    --   **一直可见**，压在棋盘第二行上；而 `selbtn` 绑的是 `pick_level` ⇒ 玩家点到就回选关。
    --   还有 `tpl-container`(模板引用控件) 也没藏。
    --
    --   **为什么 `apply_screen_hide` 管不到它们**：那个函数只遍历**规划表 `nodes`** 里的控件，
    --   而这三组是**运行时由 `ensure_widgets` 现建的**，根本不在 `nodes` 里 ⇒ 加 HIDE/PREFIX 无效。
    --
    --   ⇒ 所以在这里按"当前屏幕"直接改它们的可见性。挂在**每 30 帧**的节流位上，开销可忽略。
    -- ★ 2026-10-03 **改成每帧**（原来是每 30 帧）：`tpl-container` 用每 30 帧就够（没人跟它抢），
    --   但真机日志（22:14）显示 `selbar` 仍为 `可见=true` —— 它会被 `ensure_widgets` 在开局时
    --   设回 true，而我的同步每 30 帧才轮到一次 ⇒ 必须**每帧压住**才稳。
    --   代价：7 个控件的 find+SetVisible ≈ 14 次 pcall/帧，相比原来 375 次可忽略。
    do
      local ad_vis = current.adapter
      if ad_vis ~= nil then
        local in_level = (scr_now == "level")
        local in_select = (scr_now == "select")
        local function setv(nm, want)
          -- ★★★★★ 2026-10-03 **改用 `adapter.controls` 直接取引用，不再依赖 `find`**。
          --
          --   真机证据链（22:33 日志）：
          --     · `ensure_widgets` 里用**局部变量 `bar`** 调 `SetVisible(false)` ⇒ **成功**
          --       （诊断行：`选关条创建后已隐藏：selbar=false  selbtn.1=false`）
          --     · 但 `main.lua` 里所有"先 `adapter:find("selbar")` 拿句柄再设"的地方 ⇒ **全都无效**
          --       （进关卡后日志仍是 `selbar 可见=true`）
          --   ⇒ 结论：**`find` 拿不到这些运行时创建/改过名的控件**
          --     （项目注释早写过「`Adapter:sub()` 未命中会**永久缓存 false**」）
          --   ⇒ 走 `controls` 里那份**直接引用**；拿不到再退回 `find` 兜底。
          local c = nil
          if ad_vis.controls ~= nil then c = ad_vis.controls[nm] end
          if c == nil then pcall(function() c = ad_vis:find(nm) end) end
          if c ~= nil then pcall(function() c:SetVisible(want) end) end
        end
        -- 选关按钮条：**只在选关页可见**
        setv("selbar", in_select)
        for i = 1, 6 do setv("selbtn." .. tostring(i), in_select) end
        -- 模板引用控件：**哪个页面都不该显示**（它只是模板的引用）
        setv("tpl-container", false)
        -- 关卡内的棋盘格子：只在关卡内可见
        if in_level then
          for r = 1, 5 do for c = 1, 5 do setv("cell." .. r .. "." .. c, true) end end
        end
      end
    end
  end
  -- ★★★★★ 2026-10-05 **在这里关掉上面那个 `% 300 == 0` 的 `if`**（它的 `end` 原本在
  --   下面"每 30 帧点亮 face"整段之后 ⇒ 把 `%30` 套进了 `%300` 里，实际每 300 帧才跑一次）。
  --   判据：`luac -p lua/main.lua` 必须 exit 0；`tools/audit/check_nesting.mjs` 的
  --         `[节流嵌套]` 必须 0 处、块深度不平衡 0 个文件。
  --   ⚠️ 这里只动**配对**，下面 `%30` 那个数字**保持 30 不变**。
  --   ※ 本行缩进 2 空格（与它关掉的那个 `if` 对齐）；下面 `%30` 块保留原来的缩进。
  -- ★★★★★ 2026-10-05 **「每帧压住」改成「强压窗口 + 写值记忆」**（用户定的口径）。
  --
  --   改之前：这 33 个控件（selbar / selbtn.1..6 / tpl-container / 25 个 cell）
  --   每帧无条件 `SetVisible` ⇒ **33 次引擎写/帧**，60fps = 1980 次/秒。
  --   PC 无感，**移动端不可接受**（和上面"每帧点亮 25 个 face"同一类问题）；
  --   而写进去的值稳态下与上一帧完全相同（幂等）⇒ 纯浪费。
  --
  --   ⇒ 现在两段式：
  --     ① **强压窗口**：进关 / 换屏 / 换关（= `(scr_now, level_id)` 变了）之后，
  --        连续 **60 帧（1 秒）**每帧照写 —— 覆盖 `ensure_widgets` 在开局之后
  --        把 `selbar` 设回 `true` 的那段时序（那个老 bug 就是它引回来的）。
  --     ② **稳态**：只在该控件"目标可见性 ≠ 上次真的写下去的值"时才写
  --        ⇒ **稳态 0 次写/帧**。
  --
  --   ⚠️ 为什么不能只留 ②：`ensure_widgets` 会在我们写完很久之后把 `selbar` 设回 `true`，
  --      而我们的记忆里还是 `false` ⇒ 再也不会重写 ⇒ 玩家点到棋盘就回选关。
  --      所以 ① 那个窗口是拿掉这个老 bug 的**唯一保险**，不能删；
  --      换屏/换关时 `(scr_now, level_id)` 一变就重新开窗 ⇒ 每次开局都被重新压住。
  --
  --   ⚠️ 本段现在**每帧**执行（原来挂在 `%300` 那个节流位上）：
  --      稳态下每帧只有 33 次表查找 + 33 次比较，**0 次引擎写**。
  --  ★★★★★ 2026-10-05 Round 67 修：**这两个缓存必须是 `local`** ✗
  --    症状（由 selene 静态检查抓出 ✓）：`murdoku_vis_memo` / `murdoku_vis_force_to`
  --      在下面被读写但**从未声明** ⇒ 它们是**全局变量** ✗ ⇒ **泄进引擎的全局表** ✗✓
  --      （真机/模拟器**共享同一张全局表** ⇒ 可能被别的脚本看到、也可能被别的脚本踩 ✓）
  --    这与我在 Round 43 修的 `v2` / `a2` 是**同一类坑** ✓（那次的后果更重：拼接 nil 会抛错 ✗）
  --    ⚠️⚠️ **但声明不能放在这里！**（2026-10-05 实测踩到 ✓）
  --       `on_update` **每帧被调用一次**，函数内的 `local` 每次都重新初始化 ⇒
  --       `murdoku_vis_key` 每帧都是 `nil` ⇒ `key ~= murdoku_vis_key` **恒真**
  --       ⇒ **强压窗口每帧重新开一次** ⇒ `forcing` 恒为 `true`
  --       ⇒ 稳态退化成"每帧无条件写 33 笔"（实测 **41.8 笔/帧**，比改之前还差 ✗）。
  --    ⇒ 正确位置：**文件级 local**（见文件顶部 `local murdoku_vis_memo = {}` 那三行）——
  --      既能被本函数与闭包看见 ✓，又**活在两次调用之间** ✓，且不污染全局表 ✓。
  if murdoku_vis_memo == nil then murdoku_vis_memo = {} end
  do
    local lev = current.level
    local lid = (lev ~= nil) and (lev.id or lev.key or lev.name) or nil
    local key = tostring(scr_now) .. "|" .. tostring(lid)
    if key ~= murdoku_vis_key then
      murdoku_vis_key = key
      murdoku_vis_force_to = (tonumber(rawget(current, "frames")) or 0) + 60
    end
  end
  do
    local ad_vis = current.adapter
    if ad_vis ~= nil then
      local in_level = (scr_now == "level")
      local in_select = (scr_now == "select")
      local fnow = tonumber(rawget(current, "frames")) or 0
      local forcing = (fnow < (murdoku_vis_force_to or 0))
      local wrote = 0
      local function setv(nm, want)
        -- ★★★★★ 2026-10-03 **改用 `adapter.controls` 直接取引用，不再依赖 `find`**。
        --
        --   真机证据链（22:33 日志）：
        --     · `ensure_widgets` 里用**局部变量 `bar`** 调 `SetVisible(false)` ⇒ **成功**
        --       （诊断行：`选关条创建后已隐藏：selbar=false  selbtn.1=false`）
        --     · 但 `main.lua` 里所有"先 `adapter:find("selbar")` 拿句柄再设"的地方 ⇒ **全都无效**
        --       （进关卡后日志仍是 `selbar 可见=true`）
        --   ⇒ 结论：**`find` 拿不到这些运行时创建/改过名的控件**
        --     （项目注释早写过「`Adapter:sub()` 未命中会**永久缓存 false**」）
        --   ⇒ 走 `controls` 里那份**直接引用**；拿不到再退回 `find` 兜底。
        local c = nil
        if ad_vis.controls ~= nil then c = ad_vis.controls[nm] end
        if c == nil then pcall(function() c = ad_vis:find(nm) end) end
        if c == nil then return end
        -- ① **读回当前值**（读便宜、写贵 —— 要省掉的是引擎侧的 `SetVisible`）。
        --    已经等于目标 ⇒ **一笔都不写**，直接返回。
        --
        --    ⚠️ 为什么光靠"写值记忆"到不了 0 笔/帧（实测 2026-10-05）：
        --       `main.lua` 里**另一处**（渲染那段的 `bar:SetVisible(on_select)`）也在写
        --       同一个 `selbar`，而且它**每帧无条件写** ⇒ 我们记的"上次写下去的值"
        --       和引擎里的真实值**会分叉** ⇒ 光看记忆每帧都会重写一遍
        --       （实测稳态 602 笔/600 帧 —— 就是这一条造成的）。
        --       读回真实值之后：只要引擎里已经是目标值，无论谁写过的，我们都不再动它。
        --       这一读还顺带把"外部把值抢回去了"这件事变成**当帧就看得见**，
        --       比"只在换屏时开窗"更稳。
        --    ⚠️ 读不到 `visible`（引擎不提供这个字段）时**退回写**，不许因为读不到就不压。
        local cur_vis = nil
        pcall(function() cur_vis = c.visible end)
        if not forcing and cur_vis == want then
          murdoku_vis_memo[nm] = want
          return
        end
        -- ② 写值记忆：目标与"上次真的写下去的值"相同、而读回又读不到时，仍然只写一次。
        --    ⚠️ 写失败（pcall 返回 false）时不记这笔 ⇒ 下一帧还会重试。
        if (not forcing) and murdoku_vis_memo[nm] == want and cur_vis == nil then return end
        local okw = pcall(function() c:SetVisible(want) end)
        if okw then
          murdoku_vis_memo[nm] = want
          wrote = wrote + 1
        end
      end
      -- 选关按钮条：**只在选关页可见**
      setv("selbar", in_select)
      for i = 1, 6 do setv("selbtn." .. tostring(i), in_select) end
      -- 模板引用控件：**哪个页面都不该显示**（它只是模板的引用）
      setv("tpl-container", false)
      -- 关卡内的棋盘格子：只在关卡内可见
      if in_level then
        for r = 1, 5 do for c = 1, 5 do setv("cell." .. r .. "." .. c, true) end end
      end
      -- ★ 每帧把"这一帧写了几笔"记在 `current` 上（纯记账，给离线探针/真机日志量成本用）。
      current._vis_wrote = wrote
      current._vis_forcing = forcing
      current._vis_frames = fnow
      current._vis_until = murdoku_vis_force_to
      -- ★ 2026-10-05 Round 70 修：这里原来写的是 `_vis_key` ✗ —— **少写了前缀** ⇒
      --   `_vis_key` 从未声明 ⇒ 它是**全局 nil** ✗ ⇒ 这个诊断字段永远镜像成 nil ✗。
      --   正确变量是上面 L1627 声明的局部 `murdoku_vis_key` ✓
      --   （作用域已核对：它在**本函数顶层**声明 ✓，这里在更深的 `do` 块里 ⇒ 可见 ✓）
      --   判据来源：selene 的 `error[undefined_variable]: _vis_key is not defined @1702` ✓
      current._vis_keynow = murdoku_vis_key
    end
  end
    if scr_now == "level" and ((current.frames or 0) % 30) == 0 then
      local rows, cols = 5, 5
      pcall(function()
        local cfg = current.adapter and current.adapter.cfg
        if cfg and cfg.cells then
          rows = cfg.cells.rows or rows
          cols = cfg.cells.cols or cols
        end
      end)
      local n = 0
      for r = 1, rows do
        for c = 1, cols do
          -- ★★★★★ 2026-10-02 这里**不能用 `adapter:sub()`** —— 项目自己的注释写着：
          --     「`Adapter:sub()` 未命中会**永久缓存 false**，UI 就绪前查过一次就再也拿不到。」
          --   我在 `_cells_paint` 里早查过一次（那时子控件还没完全就绪）⇒ 缓存了未命中
          --   ⇒ 之后每帧 `sub()` 全部返回 nil ⇒ 这段的 n 恒为 0（所以"格子底图已点亮"没打印）。
          --   ⇒ 改成**直接遍历子控件**（含 `content` 中间容器一层），完全不碰缓存。
          local cid = "cell." .. r .. "." .. c
          local cell = nil
          pcall(function() cell = current.adapter:find(cid) end)
          -- 格子自己的实际尺寸 —— 用它去缩放 content / face / x（模板里这几个是 135×135，
          -- 而格子可能只有 124×124 ⇒ 不缩放就会溢出、把格子间的缝隙填满）
          local cw, ch = 124, 124
          if cell ~= nil then
            pcall(function()
              local a, b = cell:GetSizeDelta()
              if type(a) == "table" then cw, ch = a.x, a.y else cw, ch = a, b end
            end)
          end
          local face = nil
          if cell ~= nil and cell.GetChildren ~= nil then
            local kids = nil
            pcall(function() kids = cell:GetChildren() end)
            for _, k in ipairs(kids or {}) do
              local kn = nil
              pcall(function() kn = tostring(k.name) end)
              -- ★★★★★ 2026-10-02 **只点亮两样：中间容器 `content` 和底图 `face`**。
              --
              --   真机截图（18:51）证据：棋盘出来了，但**每个格子都亮着红色 ✗ 和深蓝色墙线**
              --   —— 那些是"该隐藏的图层"。
              --   根因就是我上一版图省事写了"把格子的**所有**子控件统统点亮"：
              --       pcall(function() k:SetVisible(true) end)          -- ← 把 x / wall.* / note 也点亮了
              --       pcall(function() c2:SetVisible(true) end)
              --   ⇒ `x`（划掉标记）/ `wall.*` / `door.*` / `note` / `obj` 的显隐**是玩法状态**，
              --     由脚本的状态逻辑负责。**我不能替它做决定。**
              --
              --   ⇒ 现在只点亮这两样：
              --        · `content` —— 中间容器，不亮则里面全看不见（父级不可见 ⇒ 子不可见）
              --        · `face`    —— 格子底图，应该常亮
              --     其余（x / note / wall.* / door.* / obj / text）一律**不碰**。
              if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                -- ★★★★★ 2026-10-05 Round 81 **读回再决定写不写** ✓（原来是无条件写 ✗）
                --
                --   实测（`tests/_wip/probe_throttle_cost.lua` 第 [7] 节，稳态 30 帧）：
                --     `content` 被写 **25 笔 = 0.83 笔/帧** ✗ —— 就是这一行造成的
                --     （本段每 30 帧跑一轮 × 25 个格子 ✓）。
                --   而 `content` 本来就该**一直可见** ✓ ⇒ 读到 `true` 就**永不重写** ✓✓
                --   ★ 这与本文件 L1707 那段自己写的道理一致：「**读便宜、写贵** ——
                --     要省掉的是引擎侧的 `SetVisible`」✓
                --   ⚠️ 读不到 `visible`（引擎没这字段 / 控件特殊）时**仍然写** ✓
                --     —— 不许因为读不到就不点亮 ✓（否则格子会黑 ✓）
                local cv = nil
                pcall(function() cv = k.visible end)
                if cv ~= true then pcall(function() k:SetVisible(true) end) end
                -- ★★★★★ 2026-10-02 **中间容器要跟格子同尺寸**。
                --   真机截图（19:19）：棋盘成了一整块白 —— **格子之间没有空隙**。
                --   原因：模板里 `content` 是 **135×135**，而格子只有 **124×124**
                --   ⇒ 内容**溢出到相邻格子**、把缝隙填满了。
                --   （`face` 我上一版已经设成 124，但 `content` 和里面的 `x` 没管。）
                pcall(function() k:SetSizeDelta(cw, ch) end)
                pcall(function() k:SetAnchoredPosition(0, 0) end)
              end
              if kn == "face" then
                -- ★★★★★ 2026-10-05 Round 82 **读回再决定写不写** ✓（原来无条件写 ✗）
                --   实测（探针第 [7] 节）：`face` 是**最后一个**每帧写者 ⇒ **1.67 笔/帧** ✗
                --   （本段每 30 帧一轮 × 25 格 × 2 处 ✓）。
                --   `face` 本来就该常亮 ⇒ 读到 `true` 就永不重写 ✓ 与 `content` 那处同一口径 ✓
                --   ⚠️ 读不到就照写 ✓（不许因为读不到而让格子黑掉 ✗）
                local fv = nil
                pcall(function() fv = k.visible end)
                if fv ~= true then pcall(function() k:SetVisible(true) end) end
                pcall(function() k:SetSizeDelta(cw, ch) end)
                pcall(function() k:SetAnchoredPosition(0, 0) end)
                face = k
              end
              -- ★ 划掉标记 `x`：**别顶满格子**（用户："x 也太大了"）。
              --   模板里它也是 135×135；这里按格子边长的 70% 摆。
              if kn == "x" then
                pcall(function() k:SetSizeDelta(cw * 0.7, ch * 0.7) end)
                pcall(function() k:SetAnchoredPosition(0, 0) end)
              end
              if face == nil and k.GetChildren ~= nil then
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                for _, c2 in ipairs(kk or {}) do
                  local cn = nil
                  pcall(function() cn = tostring(c2.name) end)
                  if cn == "face" then
                    -- ★★★★★ 2026-10-05 Round 82 同上：**读回再决定写不写** ✓
                    --   这是 `face` 的**第二处**写法（孙控件路径 ✓ —— 只有 `face == nil` 时才走到 ✓）
                    --   ⇒ 两处都加守卫 ⇒ `face` 的 1.67 笔/帧应降到 ~0 ✓
                    local gv = nil
                    pcall(function() gv = c2.visible end)
                    if gv ~= true then pcall(function() c2:SetVisible(true) end) end   -- 只点亮 face，别的孙子不动
                    pcall(function() c2:SetSizeDelta(cw, ch) end)
                    pcall(function() c2:SetAnchoredPosition(0, 0) end)
                    face = c2
                  elseif cn == "x" then
                    pcall(function() c2:SetSizeDelta(cw * 0.7, ch * 0.7) end)
                    pcall(function() c2:SetAnchoredPosition(0, 0) end)
                  end
                end
              end
            end
          end
          if face ~= nil then
            pcall(function() face:SetVisible(true) end)
            n = n + 1
          end
        end
      end
      if n > 0 and current._face_on ~= n then
        current._face_on = n
        if print then
          -- ★ 2026-10-09：**这里原来那段胶囊底图已【上移到 `on_update` 开头】** ✓
          --   原因见那边的长注释 ✓ 一句话：`adapter` 在本作用域是全局 nil ✗ ＋ 被
          --   `_face_on ~= n` / `print` 两层门关着 ⇒ **一次都没跑过** ✓
          print("[murdoku] 格子底图已点亮：" .. tostring(n) .. " 个 face（每帧保持）")
        end
      end
    end
  -- ★★★★★ 2026-10-02 **格子底图探针**：用户看到"只有一行一列"，日志显示只有
  --   `wall.up`(上边) / `wall.left`(左边) 是 visible=true，而**格子底图 `face` 是 false**。
  --   ⇒ 这一版把 `face` 的真实情况打出来（尺寸 / 图片 / 是否被脚本设过），
  --     这样"底图为什么没铺开"就不用猜了。
  -- ★ 2026-10-03 删除「关卡内定位」诊断块（纯只读 + print）。注意：**「每帧点亮 face」那段在它外面**，不受影响。
  Murdoku._last_screen = scr_now
  current.frames = (current.frames or 0) + 1
end

function Murdoku.on_destroy()
  if not current then return end
  Murdoku.save_now()
  current = nil
end

-- 兼容旧名
Murdoku.on_ready = Murdoku.on_start
Murdoku.on_tick = Murdoku.on_update

function Murdoku.flush_effects()
  if not current then return end
  if current.controller.dirty then
    Murdoku.render()
  end
  -- 渲染一趟之后，「控件未找到」的账已经记全了 → 打一次**分组汇总**。
  -- 放在这里而不是 create_control 里逐个打，是因为逐个打会刷 80+ 行同义句，
  -- 把"缺的是哪几类"这个真正有用的信息淹掉（report_missing 自己只打一次）。
  if current.adapter.report_missing ~= nil then
    pcall(function() current.adapter:report_missing() end)
  end
end

function Murdoku.on_input(event)
  if not current then return end
  current.controller:on_input(event)
  Murdoku.flush_effects()
end

-- 服务器/节点图发来的信号
function Murdoku.on_signal(name, payload)
  if not current then return end
  local S = Qianxing.SIGNALS
  if name == S.RESTORE then
    Murdoku.restore(payload)
  elseif name == S.SYNC_STATE then
    if payload and payload.who and payload.r and payload.c then
      current.core:select_suspect(payload.who)
      current.core:tap_cell(payload.r, payload.c)
      Murdoku.render()
    end
  elseif name == "murdoku/next_level" then
    local nxt = Levels.next(current.level.id)
    if nxt then Murdoku.start(nxt, current.options) end
  end
end

-- 把服务器推回来的存档还原到棋盘
function Murdoku.restore(payload)
  if not current or type(payload) ~= "table" then return false, "没有存档" end
  if payload.state_code then
    local ok, err = current.core:decode_state(payload.state_code)
    if not ok then
      if printerr then printerr("[murdoku] 读档失败：" .. tostring(err)) end
      return false, err
    end
  elseif payload.cells then
    current.core:deserialize(payload)
  end
  current.core:set_elapsed(payload.elapsed or 0)
  Murdoku.render(true)
  return true
end

-- 主动存档：压成分享码字符串 + 三个整数（局内存档不支持结构体/字典）
-- ═══════════════════════════════════════════════════════════════════════════
-- 主页 / 选关要用的小状态（2026-09-30）
--
--   · `remember_level` / `last_played` —— 「从存档点开始」接续**最近游玩记录**
--   · `progress_of`                     —— 选关卡片显示「未开始 / 进行中 / ★ 已破案」
--   · `mark_cleared`                    —— 破案时落盘（否则卡片永远是"未开始"）
--
--   存在**局内存档**里（走适配器的 `save`/`load`），所以跨会话有效 ——
--   这正是"从存档点开始"的意义：玩家这次进来能接着上次那关。
--   取不到就是 nil：卡片只显示关名，**不编假的进度**。
-- ═══════════════════════════════════════════════════════════════════════════
local SAVE_RECENT   = "murdoku/recent"
local SAVE_PROGRESS = "murdoku/progress"

local function store()
  return prepared_adapter
end

function Murdoku.remember_level(id)
  if id == nil then return end
  local a = store()
  if a == nil or a.save == nil then return end
  pcall(function() a:save(SAVE_RECENT, tostring(id)) end)
  pcall(function()
    local p = a:load(SAVE_PROGRESS)
    if type(p) ~= "table" then p = {} end
    local cur = p[tostring(id)]
    if type(cur) ~= "table" then cur = {} end
    if not cur.cleared then cur.started = true end
    p[tostring(id)] = cur
    a:save(SAVE_PROGRESS, p)
  end)
end

function Murdoku.last_played()
  local a = store()
  if a == nil or a.load == nil then return nil end
  local v = nil
  pcall(function() v = a:load(SAVE_RECENT) end)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

function Murdoku.mark_cleared(id)
  if id == nil then return end
  local a = store()
  if a == nil or a.save == nil then return end
  pcall(function()
    local p = a:load(SAVE_PROGRESS)
    if type(p) ~= "table" then p = {} end
    local cur = p[tostring(id)]
    if type(cur) ~= "table" then cur = {} end
    cur.cleared = true
    cur.started = true
    p[tostring(id)] = cur
    a:save(SAVE_PROGRESS, p)
  end)
end

function Murdoku.progress_of(id)
  local a = store()
  if a == nil or a.load == nil then return nil end
  local p = nil
  pcall(function() p = a:load(SAVE_PROGRESS) end)
  if type(p) ~= "table" then return nil end
  return p[tostring(id)]
end

function Murdoku.save_now()
  if not current then return false end
  local core = current.core
  local payload = {
    level_id   = tostring(current.level.id),
    state_code = core:encode_state(),
    moves      = 0,
    elapsed    = math.floor(core.elapsed or 0),
    solved     = (core.status == Core.STATUS_SOLVED),
  }
  current.adapter:save("murdoku/save/" .. tostring(current.level.id), payload)
  return true
end

----------------------------------------------------------------------------
-- 关卡批量校验（调试用；在编辑器里也可以挂个按钮调用）
----------------------------------------------------------------------------

function Murdoku.validate_all()
  local lines = {}
  for _, level in ipairs(Levels.all()) do
    local ok, errors = Core.validate_level(level)
    if ok then
      lines[#lines + 1] = string.format("[OK]   %s", tostring(level.id))
    else
      lines[#lines + 1] = string.format("[FAIL] %s\n    %s", tostring(level.id), table.concat(errors, "\n    "))
    end
  end
  local text = table.concat(lines, "\n")
  if print then print(text) end
  return text
end

return Murdoku

end

__M["levels.init"] = function()
--[[----------------------------------------------------------------------------
  levels/init.lua —— 关卡注册表

  加关卡只要两步：
    1. 复制 levels/template.lua 改成 levels/<你的id>.lua
    2. 在下面的 LIST 里加一行

  关卡顺序就是 LIST 的顺序，Murdoku 的“下一关”按它走。

  ⚠️ 加载失败不会被静默吞掉：失败信息收集在 M.load_errors() 里，
     tools/validate_levels.lua 会把它们当作错误报出来。
----------------------------------------------------------------------------]]--

local RoomMap = __require("room_map")

local M = {}

-- 按顺序登记你的关卡；游戏里默认从第一个开始
local LIST = {
  "levels.demo_selftest",     -- 框架自检样例（不需要就删掉这一行）
  "levels.case_001",          -- 案件 001 · 夜盗独行（5×5，k=1，无同伙）
  "levels.case_002",          -- 案件 002 · 双影（6×6，k=2，必有同伙）
  "levels.case_003",          -- 案件 003 · 第三方（7×7，k=3，必有同伙 + 假话不告知）
}

M._errors = {}

local function note_error(module_name, err)
  M._errors[#M._errors + 1] = { module = module_name, error = tostring(err) }
end

function M.all()
  M._errors = {}
  local out = {}
  for i = 1, #LIST do
    local ok, lv = pcall(__require, LIST[i])
    if ok and type(lv) == "table" then
      out[#out + 1] = lv
    else
      note_error(LIST[i], lv)
    end
  end
  return out
end

-- 上一次 all() 期间失败的关卡模块（{ module =, error = }）
function M.load_errors() return M._errors end

function M.get(level_id)
  for _, lv in ipairs(M.all()) do
    if lv.id == level_id then return lv end
  end
  -- 直接按文件名兜底
  for i = 1, #LIST do
    if LIST[i] == level_id or LIST[i]:match("%.([^%.]+)$") == level_id then
      local ok, lv = pcall(__require, LIST[i])
      if ok and type(lv) == "table" then return lv end
    end
  end
  return nil
end

function M.current_id()
  local lv = M.all()[1]
  return lv and lv.id or nil
end

function M.next(level_id)
  local list = M.all()
  for i = 1, #list do
    if list[i].id == level_id then
      local nxt = list[i + 1]
      return nxt and nxt.id or nil
    end
  end
  return nil
end

function M.index_of(level_id)
  local list = M.all()
  for i = 1, #list do
    if list[i].id == level_id then return i end
  end
  return nil
end

-- ★★★ 2026-09-30：**界面层要用的关卡摘要** —— 只有这一处定义。
--
--   为什么要收拢：`main.lua`（真机）和 `tools/dump_layout.lua`（生成模拟器的布局计划）
--   **各自造了一份清单**，而且都只复制 `id/name/difficulty`。于是选关卡片要显示
--   「NxN　M名嫌疑人+1名受害人」（参考《派蒙的执律庭实习》）时**拿不到数据**，
--   界面上只剩关名；更糟的是两边各写一份 ⇒ **必然漂移**（本项目已因此踩过多次）。
--   ⇒ 统一放这里，两边都调它。
--
--   只带"界面真要用的"：卡片要 `size`/`suspects`，缩略图要 `rooms`/`objects`。
--   界面层不该知道规则细节（`rules`/`clues`/`solution` 一律不给）。
function M.ui_list()
  local out = {}
  local list = M.all()
  for i = 1, #list do
    local lv = list[i]
    out[i] = {
      id = lv.id, name = lv.name, difficulty = lv.difficulty,
      size = lv.size, suspects = lv.suspects, victim = lv.victim,
      rooms = lv.rooms, objects = lv.objects,
      -- ★ 缩略图要的**房间外框**（`{ {r1,c1,r2,c2,cells}, ... }`）。
      --   算法来自 `lua/room_map.lua`（和游戏内房间判定**同一份实现**，不会漂移）。
      room_boxes = RoomMap.boxes(lv),
      -- 关卡里**可选**写的房间名（`room_names = { "餐厅", "厨房", ... }`）。
      --   没写就是 nil ⇒ 界面显示中性的「区域 N」（**不编名字**）。
      room_names = lv.room_names,
    }
  end
  return out
end

return M

end

__M["levels.demo_selftest"] = function()
--[[----------------------------------------------------------------------------
  levels/demo_selftest.lua —— 框架自检样例（偷窃版规则，不是关卡内容）

  这是一个**完全合法**的最小局，用来验证 v0.3 引擎的每一条新规则：
    · 5×5，5 枚棋子（4 名嫌疑人 + 1 名受害者，受害者也要摆）
    · 三个区域：R_A(第1-3行)、R_B(第4-5行左3列)、R_C(第4-5行右2列)
    · 门径：R_A↔R_B、R_B↔R_C（所以受害者所在区域 R_B 的相邻区域 = {R_A, R_C}）
    · 受害者 V 与 A 同在 R_B → k=2 → 必有同伙
    · 盗窃者 D 与同伙 C 都在 R_A；R_A 无辜人数 1 > R_C 的 0
      → 满足"挑无辜人数最多的相邻区域"
    · 线索共 7 条，第 7 条是**声明好的那句假话**

  你设计正式关卡时把这个文件删掉即可。
----------------------------------------------------------------------------]]--

return {
  id = "selftest_theft_5x5",
  name = "框架自检样例（偷窃版）",
  subtitle = "仅用于验证引擎与界面绑定",
  difficulty = "selftest",

  size = { rows = 5, cols = 5 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",   -- 相邻区域无辜人数不允许并列；特殊关卡可写 "allow"
  },

  -- 墙 = 区域边界
  walls = {
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 },   -- R_A | R_B
    { "h", 3, 4 }, { "h", 3, 5 },                  -- R_A | R_C
    { "v", 4, 3 }, { "v", 5, 3 },                  -- R_B | R_C
  },

  -- 门径 = 跨区域的可达通道（同样开在格边上；不改变区域划分）
  doors = {
    { "h", 3, 1 },   -- R_A ↔ R_B： (3,1) 与 (4,1) 之间
    { "v", 4, 3 },   -- R_B ↔ R_C： (4,3) 与 (4,4) 之间
  },

  -- ⚠️ Lua 的标识符只能是 ASCII，所以中文家具名必须写成 ["名"] = {...} 这种字符串键
  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["书桌"] = { cells = { { r = 1, c = 5 } }, occupiable = false, kind = "desk"   },
    ["地毯"] = { cells = { { r = 2, c = 1 }, { r = 2, c = 2 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "管家", portrait = "portrait.A" },
    { id = "B", name = "医生", portrait = "portrait.B" },
    { id = "C", name = "歌女", portrait = "portrait.C" },
    { id = "D", name = "伯爵", portrait = "portrait.D" },
    { id = "V", name = "老宅主", portrait = "portrait.V", is_victim = true },
  },

  victim = { id = "V", name = "老宅主" },

  -- 角色归属（答案的一部分）
  roles = {
    thief = "D",
    accomplice = "C",     -- 不写 = 本案没有同伙
  },

  -- 线索里至多一句假话；这里声明是第 7 条
  meta = {
    false_clue = 7,
    announce   = "one",   -- none | one | unknown（unknown = 不告诉玩家）
  },

  solution = {
    A = { r = 5, c = 3 },   -- 与受害者同区（R_B）
    B = { r = 3, c = 2 },   -- R_A
    C = { r = 2, c = 5 },   -- R_A（同伙）
    D = { r = 1, c = 4 },   -- R_A（盗窃者）
    V = { r = 4, c = 1 },   -- R_B（受害者）
  },

  clues = {
    { type = "at",     who = "B", r = 3, c = 2 },        -- 真
    { type = "at",     who = "A", r = 5, c = 3 },        -- 真
    { type = "at",     who = "V", r = 4, c = 1 },        -- 真
    { type = "at",     who = "D", r = 1, c = 4 },        -- 真
    { type = "in_row", who = "@thief", r = 1 },          -- 真（角色别名：盗窃者在第 1 行）
    { type = "in_col", who = "@accomplice", c = 5 },     -- 真（同伙在第 5 列）
    { type = "in_col", who = "B", c = 1 },               -- ★ 第 7 条：假话（B 实际在第 2 列）
  },
}

end

__M["levels.case_001"] = function()
--[[----------------------------------------------------------------------------
  levels/case_001.lua —— 案件 001《夜盗·独行》

  主题：深夜盗窃案。5×5，5 枚棋子（4 名嫌疑人 + 1 名受害者）。
  教学点：**受害者独处一区（k=1）→ 本案没有同伙**，盗窃者单独作案。
          玩家必须自己推断出"没有同伙"，而不是被直接告知。

  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_A = 第 1-3 行 × 第 1-3 列（9 格）            ← 盗窃者藏在这里
    R_B = 右侧 L 形：(1,4)(1,5)(2,4)(2,5)(3,4)(3,5)(4,5)(5,5)（8 格）
                                                    ← 受害者所在区域
    R_C = 第 4-5 行 × 第 1-4 列（8 格）

    墙： v,1..3,3（R_A|R_B）、h,3,1..3（R_A|R_C）、h,3,4（R_B|R_C）、
         v,4,4 与 v,5,4（R_C|R_B）
    门： v,2,3（R_A↔R_B）、h,3,2（R_A↔R_C）、h,3,4（R_B↔R_C）

    所以 Adj(R_B) = {R_A, R_C} —— **两个**候选区域，R3 才是真约束。

  ── 为什么这样摆（R3/R4 的自洽性）──────────────────────────────────────
    受害者 V 在 (5,5)，R_B 内只有它一人 → k=1 → 同伙可有可无。
    四名嫌疑人分布：R_A 三人（含盗窃者）、R_C 一人。
      inno(R_A) = 2（除盗窃者外的两人）
      inno(R_C) = 1
    → 唯一最大是 R_A，所以盗窃者必在 R_A  ✔（R3）
    → 若硬说有同伙：同伙在 R_A 会让 inno 变成 1，与 R_C 并列（tie_policy=forbid 直接非法）；
      同伙在 R_C 又违反"同伙与盗窃者同区"。**结构本身就排除了同伙** ✔（R4）

  ── 每行每列恰好一人 ────────────────────────────────────────────────────
    列：R_A 占 1/2/3，R_C 占 4，受害者占 5 → 行 1..5 各一人。

  线索设计（8 条，第 8 条是那句假话）：
    · 全开线索指向 @thief（角色别名）→ 身份靠推理而不是靠报名字
    · 第 8 条故意说错的列，玩家要么把它当假话，要么就得推翻别的线索
  本关只用了 8 条，也不是由 find_clues.lua 生成的（那个工具是暴力搜索，很慢，
  留给"怎么都想不出来"的时候当兜底用）。
----------------------------------------------------------------------------]]--

return {
  id = "case_001",
  name = "案件 001 · 夜盗独行",
  subtitle = "保险库内室只留下一个人的痕迹 —— 是独自作案，还是有人替他望风？",
  difficulty = "easy",

  size = { rows = 5, cols = 5 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",   -- 相邻区域无辜人数不允许并列
  },

  -- 墙 = 区域边界
  walls = {
    { "v", 1, 3 }, { "v", 2, 3 }, { "v", 3, 3 },   -- R_A | R_B
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 },   -- R_A | R_C
    { "h", 3, 4 },                                 -- R_B | R_C
    { "v", 4, 4 }, { "v", 5, 4 },                  -- R_C | R_B
  },

  -- 门径 = 跨区域通道（与墙同粒度；不改变区域划分）
  doors = {
    { "v", 2, 3 },   -- R_A ↔ R_B：(2,3) 与 (2,4)
    { "h", 3, 2 },   -- R_A ↔ R_C：(3,2) 与 (4,2)
    { "h", 3, 4 },   -- R_B ↔ R_C：(3,4) 与 (4,4)
  },

  -- ⚠️ Lua 标识符只能是 ASCII，中文家具名必须写成 ["名"] = {...}
  objects = {
    -- ★ 2026-09-30：物件多了个**可选**的 `kind` —— **家具图标的素材键**。
    --   界面层会把它翻成 `obj.shelf` / `obj.case` / `obj.carpet`，
    --   去 `assets` 调色板里查图（见 `ui_controller.object_key_of`）。
    --   不写 kind 也能跑（退回中文名 `obj.书架`），只是素材名不好管理。
    --   等家具素材配好，在 assets 里放 obj.shelf / obj.case / obj.carpet 即可显示。
    ["书架"]   = { cells = { { r = 5, c = 1 } }, occupiable = false, kind = "shelf"  },
    ["展示柜"] = { cells = { { r = 5, c = 3 } }, occupiable = false, kind = "case"   },
    ["地毯"]   = { cells = { { r = 4, c = 2 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "值班保安", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "前台姑娘", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "夜班清洁工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "旧识古董商", portrait = "portrait.D", gender = "male" },
    { id = "V", name = "收藏家", portrait = "portrait.V",     is_victim = true },
  },

  victim = { id = "V", name = "收藏家" },

  -- 答案的一半：角色归属（不写 accomplice = 本案没有同伙）
  roles = {
    thief = "D",
  },

  -- 至多一句假话；announce = "unknown" → 不告诉玩家本关有没有假话，让他自己推
  meta = {
    false_clue = 8,
    announce   = "unknown",
  },

  solution = {
    D = { r = 1, c = 3 },   -- R_A（盗窃者）
    A = { r = 3, c = 1 },   -- R_A
    B = { r = 2, c = 2 },   -- R_A
    C = { r = 5, c = 4 },   -- R_C
    V = { r = 4, c = 5 },   -- R_B（受害者，独处一区）
  },

  clues = {
    { type = "at",         who = "V",       r = 4, c = 5 },   -- 受害者就在保险库内室
    { type = "in_col",     who = "@thief",  c = 3 },          -- 盗窃者在第 3 列
    { type = "in_row",     who = "@thief",  r = 1 },          -- 盗窃者在第 1 行
    { type = "in_row",     who = "C",       r = 5 },          -- 清洁工在第 5 行
    { type = "in_col",     who = "B",       c = 2 },          -- 前台姑娘在第 2 列
    { type = "same_room",  a = "A", b = "B" },                -- 保安与前台在同一区
    { type = "in_row",     who = "A",       r = 3 },          -- 保安在第 3 行
    { type = "in_col",     who = "A",       c = 4 },          -- ★ 第 8 条：假话（保安实际在第 1 列）
  },
}

end

__M["levels.case_002"] = function()
--[[----------------------------------------------------------------------------
  levels/case_002.lua —— 案件 002《双影》

  主题：6×6，6 枚棋子（4 名嫌疑人 + 1 名受害者 + 1 名同伙）。
  教学点：**受害者与他人同区（k≥2）→ 必然有且只有一个同伙**，
          而且同伙一定和盗窃者待在同一个区域。

  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_T = 第 1-4 行 × 第 1-4 列（16 格）        ← 盗窃者与同伙都藏在这里
    R_V = 第 5-6 列 × 第 1-6 行（12 格）        ← 受害者所在区域
    R_C = 第 5-6 行 × 第 1-4 列（8 格）         ← 另一条通往 R_V 的路（答案里是空的）

    墙： v,1..6,4（第 4 列与第 5 列之间）、h,4,1..4（第 4 行与第 5 行之间）
    门： v,2,4（R_T↔R_V）、v,5,4（R_C↔R_V）、h,4,1（R_T↔R_C）

    Adj(R_V) = {R_T, R_C} —— 两个候选区域，R3 才是真约束。

  ── 为什么这样摆（R3/R4 的自洽性）──────────────────────────────────────
    受害者 V 与随行记者 E 同在 R_V → k=2 → **必有同伙** ✔（R4）
    六枚棋子分布：R_T 四人（盗窃者 D + 同伙 C + 两名无辜 A/B）、R_V 两人、R_C 零人。
      inno(R_T) = 2
      inno(R_C) = 0        （R_C 空着 —— "那个区没人"本身就是有用的观察）
    → 唯一最大是 R_T，所以盗窃者与同伙必在 R_T ✔（R3）

  ── 每行每列恰好一人 ────────────────────────────────────────────────────
    答案：D(1,1) C(2,4) A(3,3) B(4,2) V(5,6) E(6,5)
          行 1..6 各一次、列 1..6 各一次。

  线索 15 条，第 15 条是那句假话；announce = "one"（告诉玩家本关有一句假话）。
----------------------------------------------------------------------------]]--

return {
  id = "case_002",
  name = "案件 002 · 双影",
  subtitle = "内室里留下了两个人的痕迹 —— 这一次，他身边还有别人。",
  difficulty = "normal",

  size = { rows = 6, cols = 6 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },

  -- 墙 = 区域边界
  walls = {
    { "v", 1, 4 }, { "v", 2, 4 }, { "v", 3, 4 },   -- R_T | R_V
    { "v", 4, 4 }, { "v", 5, 4 }, { "v", 6, 4 },   -- R_C | R_V
    { "h", 4, 1 }, { "h", 4, 2 }, { "h", 4, 3 }, { "h", 4, 4 },  -- R_T | R_C
  },

  -- 门径
  doors = {
    { "v", 2, 4 },   -- R_T ↔ R_V：(2,4) 与 (2,5)
    { "v", 5, 4 },   -- R_C ↔ R_V：(5,4) 与 (5,5)
    { "h", 4, 1 },   -- R_T ↔ R_C：(4,1) 与 (5,1)
  },

  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["书架"]   = { cells = { { r = 5, c = 1 }, { r = 6, c = 1 } }, occupiable = false, kind = "shelf"  },
    ["展示柜"] = { cells = { { r = 5, c = 4 } }, occupiable = false, kind = "case"   },
    ["地毯"]   = { cells = { { r = 6, c = 3 }, { r = 6, c = 4 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "夜班门卫", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "画廊助理", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "临时搬运工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "鉴定师", portrait = "portrait.D",     gender = "male" },
    { id = "E", name = "随行记者", portrait = "portrait.E",   gender = "female" },
    { id = "V", name = "馆长", portrait = "portrait.V",       is_victim = true },
  },

  victim = { id = "V", name = "馆长" },

  -- 角色归属：盗窃者 + 同伙（本案必有同伙，因为 k=2）
  roles = {
    thief      = "D",
    accomplice = "C",
  },

  meta = {
    false_clue = 15,
    announce   = "one",
  },

  solution = {
    D = { r = 1, c = 1 },   -- R_T（盗窃者）
    C = { r = 2, c = 4 },   -- R_T（同伙，与盗窃者同区）
    A = { r = 3, c = 3 },   -- R_T
    B = { r = 4, c = 2 },   -- R_T
    V = { r = 5, c = 6 },   -- R_V（受害者）
    E = { r = 6, c = 5 },   -- R_V（与受害者同区 → k=2 → 必有同伙）
  },

  --[[ 线索全部是**关系型**的（"谁在谁的东边几列 / 南边几行 / 谁和谁独处一室"），
       而不是直接报坐标 —— 这样玩家是在做空间推理，不是在抄格子。

       用到的原子：abs_col_from（倒数第 N 列）、abs_row_from（倒数第 N 行）、
                   col_offset / row_offset（在谁东/西边几列、南/北边几行）、
                   alone_with（与谁独处一室）、not_role（身份排除）。 ]]
  clues = {
    { type = "abs_col_from", who = "V",  n = 1, from = "right" },   -- 馆长在倒数第 1 列
    { type = "abs_row_from", who = "V",  n = 2, from = "bottom" },  -- 馆长在倒数第 2 行
    { type = "alone_with",   a = "V", b = "E" },                    -- 馆长只和随行记者待在同一间

    { type = "col_offset", who = "E", other = "V", d = -1 },        -- 记者在馆长西边 1 列
    { type = "row_offset", who = "E", other = "V", d = 1 },         -- 记者在馆长南边 1 行

    { type = "abs_col_from", who = "@thief", n = 1 },               -- 盗窃者在第 1 列
    { type = "abs_row_from", who = "@thief", n = 1 },               -- 盗窃者在第 1 行

    { type = "col_offset", who = "@accomplice", other = "@thief", d = 3 },  -- 同伙在盗窃者东边 3 列
    { type = "row_offset", who = "@accomplice", other = "@thief", d = 1 },  -- 同伙在盗窃者南边 1 行

    { type = "col_offset", who = "A", other = "V", d = -3 },        -- 门卫在馆长西边 3 列
    { type = "row_offset", who = "A", other = "V", d = -2 },        -- 门卫在馆长北边 2 行

    { type = "col_offset", who = "B", other = "A", d = -1 },        -- 助理在门卫西边 1 列
    { type = "row_offset", who = "B", other = "A", d = 1 },         -- 助理在门卫南边 1 行

    -- ★ 这条是**必需的**，别删：没有它，D 与 C 的**位置和身份可以整体互换**
    --   （线索 6~9 只说"盗窃者/同伙在哪一格"，没说"谁"），而互换后的解
    --   只多违反"假话那一条"，仍满足"至多一条假话"。
    --   实测：少了这条，求解器会找到 2 个解（D/C 与 C/D 互为镜像）。
    { type = "not_role", who = "D", role = "accomplice" },          -- 鉴定师不是同伙

    { type = "abs_col_from", who = "C", n = 1, from = "right" },    -- ★ 第 15 条：假话（搬运工实际在第 4 列）
  },

  --[[ 设计备注：为什么不用 left_of / right_of / above / below
       这四种线索的判定是「**同一行**且列更小 / **同一列**且行更小」
       （见 murdoku_core.lua 的 ctx.is_left_of / ctx.is_above）。
       本工程开了 one_per_row + one_per_col，任意两人**不可能同行同列**，
       所以这四个线索在本作里**永远为假**。
       要表达"谁在谁左边"请用 col_offset / row_offset（它们不要求同行同列）。 ]]
}


end

__M["levels.case_003"] = function()
--[[----------------------------------------------------------------------------
  levels/case_003.lua —— 案件 003《第三方》

  主题：7×7，7 枚棋子（5 名嫌疑人 + 1 名受害者 + 1 名同伙）。**目前最大的一关**，
  也是第一关用来自证"棋盘是自适应的"（格子边长 = 可用边长 ÷ 7 ≈ 97px，编辑器不用重摆）。

  教学点：把前面两条合起来用 ——
    · k=3（受害者身边有两个人）→ **必有同伙**（R4）
    · 假话**不告知**（announce="unknown"），玩家连"有没有假话"都要自己判断

  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_T = 第 1-4 行 × 第 1-4 列（16 格，容量 min(4,4)=4）
    R_V = 第 5-7 列 × 第 1-7 行（21 格，容量 min(7,3)=3）  ← 受害者所在区域
    R_C = 第 5-7 行 × 第 1-4 列（12 格，容量 min(3,4)=3）  ← 答案里是空的

    墙： v,1..7,4（第 4 列与第 5 列之间）、h,4,1..4（第 4 行与第 5 行之间）
    门： v,2,4（R_T↔R_V）、v,5,4（R_C↔R_V）、h,4,1（R_T↔R_C）

    Adj(R_V) = {R_T, R_C} —— 两个候选区域，R3 才是真约束。

  ── 计数验算（见 docs/关卡设计手册.md 第二节）────────────────────────────
    无辜总数 = 7 − 1(受害者) − 1(盗窃者) − 1(同伙) = 4
    a(在 R_V) + b(在 R_T) + c(在 R_C) = 4，要求 a ≥ 1 且 b > c
    取 a=2、b=2、c=0：
      R_V：受害者 + 2 名无辜 = 3 人（容量 3，正好放满）
      R_T：盗窃者 + 同伙 + 2 名无辜 = 4 人（容量 4，正好放满）
      R_C：0 人
    → inno(R_T)=2 > inno(R_C)=0，唯一最大 ✔（R3）

  ── 行列 ────────────────────────────────────────────────────────────────
    答案：D(1,1) C(2,4) A(3,2) B(4,3) V(5,6) E(6,5) F(7,7)
          行 1..7、列 1..7 各一次。

  线索 18 条，第 18 条是那句假话（且**不告诉玩家**本关有假话）。
----------------------------------------------------------------------------]]--

return {
  id = "case_003",
  name = "案件 003 · 第三方",
  subtitle = "内室里挤了三个人 —— 谁是被害者，谁只是恰好路过？",
  difficulty = "hard",

  size = { rows = 7, cols = 7 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },

  -- 墙 = 区域边界
  walls = {
    { "v", 1, 4 }, { "v", 2, 4 }, { "v", 3, 4 }, { "v", 4, 4 },   -- R_T | R_V
    { "v", 5, 4 }, { "v", 6, 4 }, { "v", 7, 4 },                  -- R_C | R_V
    { "h", 4, 1 }, { "h", 4, 2 }, { "h", 4, 3 }, { "h", 4, 4 },   -- R_T | R_C
  },

  -- 门径
  doors = {
    { "v", 2, 4 },   -- R_T ↔ R_V：(2,4) 与 (2,5)
    { "v", 5, 4 },   -- R_C ↔ R_V：(5,4) 与 (5,5)
    { "h", 4, 1 },   -- R_T ↔ R_C：(4,1) 与 (5,1)
  },

  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["书架"]   = { cells = { { r = 6, c = 1 }, { r = 7, c = 1 } }, occupiable = false, kind = "shelf"  },
    ["展示柜"] = { cells = { { r = 5, c = 4 } }, occupiable = false, kind = "case"   },
    ["地毯"]   = { cells = { { r = 6, c = 3 }, { r = 7, c = 3 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "值夜保安", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "布展助理", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "外聘搬运工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "首席鉴定师", portrait = "portrait.D", gender = "male" },
    { id = "E", name = "跟拍记者", portrait = "portrait.E",   gender = "female" },
    -- F 的图已由用户补上（portrait.F / id=112011）
    { id = "F", name = "赞助人", portrait = "portrait.F",     gender = "male" },
    { id = "V", name = "老馆员", portrait = "portrait.V",     is_victim = true },
  },

  victim = { id = "V", name = "老馆员" },

  roles = {
    thief      = "D",
    accomplice = "C",
  },

  -- 不告诉玩家本关有没有假话 —— 让他自己从矛盾里推
  meta = {
    false_clue = 18,
    announce   = "unknown",
  },

  solution = {
    D = { r = 1, c = 1 },   -- R_T（盗窃者）
    C = { r = 2, c = 4 },   -- R_T（同伙）
    A = { r = 3, c = 2 },   -- R_T
    B = { r = 4, c = 3 },   -- R_T
    V = { r = 5, c = 6 },   -- R_V（受害者）
    E = { r = 6, c = 5 },   -- R_V
    F = { r = 7, c = 7 },   -- R_V
  },

  --[[ 线索：全部关系型。前两条 same_room 是**故意**给玩家算 k 用的 ——
       它告诉玩家"馆长、记者、赞助人在同一间"，于是 k=3 ≥ 2 → 必有同伙。 ]]
  clues = {
    { type = "same_room", a = "V", b = "E" },                        -- 馆长与记者同区
    { type = "same_room", a = "V", b = "F" },                        -- 馆长与赞助人同区

    { type = "abs_col_from", who = "V", n = 2, from = "right" },     -- 馆长在倒数第 2 列
    { type = "abs_row_from", who = "V", n = 3, from = "bottom" },    -- 馆长在倒数第 3 行

    { type = "col_offset", who = "E", other = "V", d = -1 },         -- 记者在馆长西边 1 列
    { type = "row_offset", who = "E", other = "V", d = 1 },          -- 记者在馆长南边 1 行

    { type = "col_offset", who = "F", other = "V", d = 1 },          -- 赞助人在馆长东边 1 列
    { type = "row_offset", who = "F", other = "V", d = 2 },          -- 赞助人在馆长南边 2 行

    { type = "abs_col_from", who = "@thief", n = 1 },                -- 盗窃者在第 1 列
    { type = "abs_row_from", who = "@thief", n = 1 },                -- 盗窃者在第 1 行

    { type = "col_offset", who = "@accomplice", other = "@thief", d = 3 },  -- 同伙在盗窃者东边 3 列
    { type = "row_offset", who = "@accomplice", other = "@thief", d = 1 },  -- 同伙在盗窃者南边 1 行

    { type = "col_offset", who = "A", other = "V", d = -4 },         -- 保安在馆长西边 4 列
    { type = "row_offset", who = "A", other = "V", d = -2 },         -- 保安在馆长北边 2 行

    { type = "col_offset", who = "B", other = "A", d = 1 },          -- 助理在保安东边 1 列
    { type = "row_offset", who = "B", other = "A", d = 1 },          -- 助理在保安南边 1 行

    -- ★ 防"身份镜像"：只写"盗窃者/同伙在哪一格"的话，D 与 C 可以对调。
    { type = "not_role", who = "D", role = "accomplice" },           -- 鉴定师不是同伙

    { type = "abs_row_from", who = "C", n = 1, from = "bottom" },    -- ★ 第 18 条：假话（搬运工实际在第 2 行）
  },

  --[[ 设计备注：为什么不用 left_of / right_of / above / below
       这四种要求"同一行/同一列"才能成立（见 murdoku_core.lua 的 ctx.is_left_of /
       is_above），而本作开了 one_per_row + one_per_col，所以它们**永远为假**。
       要表达相对位置用 col_offset / row_offset。 ]]
}

end

-- ==== 入口：官方生命周期回调（OnInit / OnStart / OnUpdate / ...）==== --
--[[----------------------------------------------------------------------------
  entry_client_script.lua —— 客户端脚本入口（挂到客户端控件上的那个文件）

  用法：在「千星沙箱 → 客户端脚本资源管理器」里新建脚本映射，
        把它关联到本文件；然后在客户端控件（例如 root 容器）的
        「脚本」页签 → 添加脚本，选中这个映射。

  官方生命周期（运行时按固定名字查找并调用）：
    OnInit() / OnStart() / OnEnable() / OnDisable()
    OnUpdate(dt)       逐帧，**不受关卡时停影响**
    OnLevelUpdate(dt)  关卡逐帧，受关卡时停影响
    OnDestroy()

  注意：客户端控件必须挂在一个**处于激活且可见的「客户端控件容器」**里，
        否则控件找不到、脚本逻辑也不跑（官方文档明确说明）。

  ────────────────────────────────────────────────────────────────────────
  ★ 2026-09-26 **真机第一次跑通**（日志里出现 `[murdoku] 控件未找到…` /
    `started:` / `destroyed` 就说明脚本真的在执行了）。这条路走通靠三件事：

      ① `script:EnableUpdate(true)` —— 不打开的话 OnUpdate 一次都不执行
         （客户端脚本默认不参与逐帧更新）
      ② 容器的「显示常驻光标」—— 不打开的话所有点击都到不了脚本；
         本文件会尝试用 `Adapter:enable_cursor()` 自己打开它
      ③ 界面布局必须被「职业」引用一次，否则游玩时什么都没有

  ★★ 同一次事故的教训（务必别重犯）：
     `check_canvas` 里用 `%d` 去格式化 `game.GetUICanvasSize()` 的返回值，
     而真机返回的是**浮点数** → Lua 5.3 抛
     `bad argument #2 to 'format' (number has no integer representation)`
     → 因为没包 pcall，**整个 OnInit 被打断** → 适配器没建起来、配置全没生效，
     日志上表现成一大串「找不到头像卡容器 / 控件未找到」，看着像界面没搭好。

     所以本文件现在守两条纪律：
       · 打引擎给回来的数字，一律 `%s` / `%.2f`，**不用 `%d`**；
       · OnInit 里**任何诊断都不许有能力中断启动**（adapter 先建、诊断各自 pcall）。
  ────────────────────────────────────────────────────────────────────────
--]]--

-- ===== 开局关卡 =====
-- 留 nil = 用关卡注册表（levels/init.lua 的 LIST）里的第一关。
-- 打包时可以钉死：lua tools/bundle_client_script.lua --level=case_002
--   ⚠️ 正式发布不要带 --level，让它走注册表顺序。
local FORCE_LEVEL = nil

-- ===== 加载（失败也不让整个 chunk 崩掉）=====
local Murdoku, Qianxing
local LOAD_ERR = nil

local ok1 = pcall(function() Murdoku = __require("main") end)
if not ok1 then LOAD_ERR = "main" end

if LOAD_ERR == nil then
  local ok2 = pcall(function() Qianxing = __require("engine_adapter_qianxing") end)
  if not ok2 then LOAD_ERR = "adapter" end
end

local adapter   = nil
local started   = false
local tree_dumped = false

local RETRY_INTERVAL = 0.5
local RETRY_LIMIT    = 60      -- 最多重试 30 秒
local retry_elapsed  = 0
local retry_tries    = 0

-- ===== 不依赖任何模块的原始探针 =====
-- 找一个叫 cell.1.1 / tray.A / board 的控件，把它的边长设成 v（正方形）。
-- 改"预设按钮自身"的尺寸时，它的子控件（居中锚点）会跟着位移 —— 肉眼可辨。
local function raw_mark(v)
  if game == nil or game.GetClientUIRoots == nil then return false end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then return false end

  local function walk(c, d, want)
    if c == nil or d > 12 then return nil end
    local n
    pcall(function() n = c.name end)
    if n == want then return c end
    local kids
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do
        local hit = walk(kids[i], d + 1, want)
        if hit ~= nil then return hit end
      end
    end
    return nil
  end

  local names = { "cell.1.1", "tray.A", "board" }
  for i = 1, #names do
    for k = 1, #roots do
      local t = walk(roots[k], 1, names[i])
      if t ~= nil and t.SetSizeDelta ~= nil then
        if pcall(function() t:SetSizeDelta(v, v) end) then return true end
      end
    end
  end
  return false
end

-- ===== 启动信标（默认关闭）=====
local BEACON = { OnInit = 300, OnStart = 380 }

local function beacon(a, v)
  if a == nil then return end
  if a.cells_beacon == false then return end
  if a._cells_beacon_button ~= nil then
    pcall(function() a:_cells_beacon_button(v) end)
  end
  if a._cells_signal ~= nil then
    pcall(function() a:_cells_signal(v) end)
  end
end

-- ===== 逐帧更新开关 =====
-- ★★ 客户端脚本（Script 对象）**默认不参与逐帧更新**（updateEnabled = false），
--    运行时会直接跳过它的 OnUpdate。必须显式打开：script:EnableUpdate(true)
--    不打开的后果非常隐蔽 —— OnInit / OnStart 都正常跑、日志也正常，
--    但 OnUpdate 一次都不执行：计时不动、单击的铅笔笔记永远落不了格
--    （要等双击窗口）、等待控件就绪的惰性重试也不会发生。
local function enable_update()
  if script == nil then
    if printerr then printerr("[murdoku] 拿不到 script 对象，OnUpdate 可能不会被调用") end
    return false
  end
  local fn = script.EnableUpdate
  if fn == nil then
    if printerr then printerr("[murdoku] script:EnableUpdate 不存在，OnUpdate 可能不会被调用") end
    return false
  end
  local ok = pcall(function() script:EnableUpdate(true) end)
  if not ok then
    if printerr then printerr("[murdoku] script:EnableUpdate 失败，OnUpdate 可能不会被调用") end
    return false
  end
  return true
end

-- ===== 画布尺寸自检 =====
-- 整套界面坐标是按**画布 1600×900**（原点左下）算的。真机如果不是这个尺寸，
-- 所有位置都会偏 —— 与其让玩家看着错位的界面猜，不如在日志里直说。
--
-- ⚠️ 这里就是那次真机事故的现场：原来用 `%d`，真机返回浮点 → 抛错 → OnInit 中断。
--    现在一律用 num()（%.0f / %.2f），外层再包一层 pcall。
local CANVAS_EXPECT = { w = 1600, h = 900 }
local canvas_checked = false

local function num(v)
  if type(v) ~= "number" then return tostring(v) end
  if v == math.floor(v) then return string.format("%.0f", v) end
  return string.format("%.2f", v)
end

local function check_canvas()
  if canvas_checked then return end
  canvas_checked = true
  pcall(function()
    if game == nil or game.GetUICanvasSize == nil then return end
    local ok, w, h = pcall(game.GetUICanvasSize)
    if not ok or type(w) ~= "number" or type(h) ~= "number" then
      if print then print("[murdoku] 拿不到画布尺寸：" .. tostring(w) .. " / " .. tostring(h)) end
      return
    end
    local same = (math.abs(w - CANVAS_EXPECT.w) < 0.6) and (math.abs(h - CANVAS_EXPECT.h) < 0.6)
    if same then
      -- ★★★★★ 2026-10-03 **版本标记**：日志**第一行**就自报"我是哪一版"。
      --
      --   起因：改完代码、真机跑了一遍，贴回来的日志**时间戳还是上一轮的**，
      --   里面既没有新打印、`cell` 尺寸也还是旧值 ⇒ 我误以为"改动没生效"，
      --   实际是**贴了旧日志**。加这一行后，一看首行就能确认跑的是哪一版。
      --
      -- ★★★★★ 2026-10-09 **标记从 v076 直接跳到 v093 —— 中间 17 轮全丢了** ✗✓
      --   ★ 症状 ✓：`PLAN.md` D2 记的「十几次安装后无法从日志分辨版本」——
      --     标记停在 **v076**（10-05），而 `versions/` 已经到
      --     **`134-弹窗四键成型-v092`** ⇒ 中间每一轮的日志首行**都是 v076** ✓
      --     ⇒ 贴回来的日志到底对应哪一版，**根本看不出来** ✓（正是当初加标记要解决的问题 ✗）
      --   ★ 本次动作 ✓：**只把标记本身补上**（v093 = 紧随 versions/ 的 v092 ✓）
      --     —— **没有**顺手加自动化：那要改 `tools/install_script_to_sandbox.ps1`，
      --     而本文件对 BOM **极敏感**（历史事故：用 `Set-Content` 写它会加 BOM ⇒
      --     打包后 Lua 5.3 报 `unexpected symbol near '<\239>'` ⇒ `check_all` 2c 永久变红 ✓）
      --     ⇒ ★ 规则：**本文件只许用 `edit` 工具改，改完必跑 `node tools/check_encoding.mjs`** ✓
      --   ⇒ ★ 待办（`接手待办.md` P1）：把"递增标记"并进安装脚本或 `archive_version.mjs`，
      --     由工具强制递增，而不是靠人记得 ✓
      if print then
        print("[murdoku] ===== 构建标记 v102 / 2026-10-09 / 加网格几何探针(读引擎自己算的 itemSize/spacing/padding/GetContentLength/scrollProgress)以定'填到不该有的地方'的真因 =====")
      end
      if print then print("[murdoku] 画布 " .. num(w) .. "×" .. num(h) .. "，与设计一致") end
    else
      if printerr then
        printerr("[murdoku] 画布是 " .. num(w) .. "×" .. num(h)
          .. "，但界面坐标按 " .. num(CANVAS_EXPECT.w) .. "×" .. num(CANVAS_EXPECT.h)
          .. " 设计 —— 位置会偏。请按实际画布重算 docs/控件坐标表-1600x900.md，"
          .. "或改 ui_controller.lua 的 M.CANVAS / M.SCALE。")
      end
    end
  end)
end

-- ===== 适配器构造（OnInit 和 OnStart 都会用到）=====
-- 抽成函数是为了**可重入**：万一某次 OnInit 出问题，OnStart 还能自己补建一个，
-- 而不是带着 nil 往下跑（那会表现成"配置全没生效"的一大串控件未找到）。
local function build_adapter()
  if LOAD_ERR ~= nil then error("模块加载失败：" .. tostring(LOAD_ERR)) end
  adapter = Qianxing.new({
    -- 布局坐标是否由脚本接管：默认 false（推荐在编辑器里摆好位置）
    apply_rect = false,
    verbose    = false,

    -- ★★★ 2026-10-01：**从「外部资产」转存进来的图片素材**（用户给的模板索引）。
    --
    --   流程：在 https://qx.070077.xyz 用基础图元画好 → 导出 .gia → **原样**放进
    --     C:\Users\...\BeyondLocal\Beyond_Local_Export
    --   → 游戏里「导入外部资产 → 选中 → 转存所选资产」→ 进素材库
    --   → 用户把它的**控件模板索引**告诉我（下面这些数字）。
    --
    --   用法：`cfg.prefab_of[节点id] = 模板索引` + `cfg.parent_of[节点id] = 父节点`，
    --   然后 `ui_controller` 只要 push 一个同 id 的节点，适配器就会
    --   `game.InstantiateClientUIControl(索引, 父控件)` 把它造出来
    --   （这条路和「脚本生成棋盘格子」是同一条，已经跑熟了）。
    --
    --   ⚠️ **改美术要改 scene JSON**（tools/qx/scenes/*.json）再重新导出转存，
    --      **不要手改导出的 .gia** —— 我改过一次资产类型号，把一个能用的文件
    --      改成了导入会卡住的（教训记在 docs/外部资产-怎么用与我做了什么.md）。
    -- ★★★★★ 2026-10-03 **第一组改动：给三个动作键挂上「六边形按钮」素材**。
    --
    --   索引来源：用户走完「导入外部资产 → 转存所选资产」后给的 `124，含资产.gil`，
    --   用 `tools/gil/diff_ids.mjs` 比对出来（新增 1073742333~1073742354 共 22 条记录）：
    --       1073742333  murdoku-btn-hex      ← 六边形按钮（三个键共用）
    --       1073742337  murdoku-card-frame   ← 深色卡框
    --       1073742341  murdoku-cell         ← 格子
    --       1073742345  murdoku-clue-row     ← 线索条
    --       1073742349  murdoku-panel        ← 面板
    --       1073742352  murdoku-tape         ← 胶带
    --
    --   ⚠️ 原来这里写的是**猜的值** `1073742321`（第一次转存失败的那个），而且把
    --      `1073742333` 当成了"线索条" —— 两边错位。现在一律以"从 .gil 读出的真实索引"为准。
    --
    --   ★ 这一类**不进 `.gil`**（`sync_plan.mjs` 里也专门跳过 `.hexbg`）：
    --     它们由脚本按模板索引 `InstantiateClientUIControl` 现场创建。
    --     一旦 .gil 里也有同名控件，适配器 `find()` 会先找到那个"编辑器里的空控件"，
    --     于是永远不走实例化 ⇒ 画面上是一块空白。
    prefab_of = {
      -- 六边形按钮底图（三个动作键共用一张素材）
      ["action.back.hexbg"] = 1073742333,
      ["action.redo.hexbg"] = 1073742333,
      ["action.hint.hexbg"] = 1073742333,
      -- 深色卡框（主页 / 选关的背景大板）—— 下一组再启用
      ["home.panel"]   = 1073742337,
      ["select.panel"] = 1073742337,
    },
    parent_of = {
      ["action.back.hexbg"] = "action.back",
      -- ★ 已删：action.redo / action.hint 的底图（父控件本身已从存档里清掉）

      -- ★★★★★ 2026-10-04 **14 个 id 全部显式挂 `root`** —— 修"位置还不对"。
      --
      --   真机日志的**点击坐标**两轮几乎一样（v050 与 v051），说明改规划父级无效：
      --       hit.hint 点击 (1573,195)（规划 1483,171）⇒ +90,+24
      --       hit.undo 点击 (1585,638)（规划 1483,625）⇒ +102,+13
      --   而 `stage` 的偏移正是 (+100,+20) ⇒ **运行时以 `root` 为参照**，
      --   真实父级 `stage` 又叠了一层 ⇒ 必须让**真实父级也是 `root`**，两层才抵消。
      --   ⚠️ 早前"挂 root 就看不见"的判断是错的：那时图标用格子模板（face 尺寸 0）；
      --      现在贴图走纯图片模板，挂 root 既可见、位置又对。
      ["hex.back"]   = "root",
      ["hex.submit"] = "root",
      ["hex.redo"]   = "root",
      ["hex.undo"]   = "root",
      ["hex.hint"]   = "root",
      ["hex.ok"]     = "root",
      ["hex.no"]     = "root",
      ["hit.back"]   = "root",
      ["hit.submit"] = "root",
      ["hit.redo"]   = "root",
      ["hit.undo"]   = "root",
      ["hit.hint"]   = "root",
      ["hit.ok"]     = "root",
      ["hit.no"]     = "root",
      ["home.panel"]   = "home",
      ["select.panel"] = "select",
    },

    -- 诊断信标：正式游玩保持 false（会改控件尺寸，肉眼可见）
    cells_beacon = false,

    -- ★ 运行时光栅：格子都在编辑器里摆好了 → 完全不需要模板，
    --   脚本只做「把每格摆正」，缺格子时才去找模板索引。
    --
    --   ⚠️ 模板索引指向的是**「另存为模板」那一刻**的快照。之后又给格子加了
    --   底图/子控件的话，必须**重新另存一次**，否则副本全是透明的。
    --
    --   ★ size / pitch / margin 不写死：运行时读 board 的实际尺寸算出来，
    --     所以 5×5 / 6×6 / 7×7 共用同一套编辑器控件。
    -- ★★★★ 2026-10-02 **容器模板**（用户在编辑器里新建并给了索引 1073742330）。
    --
    --   有了它，脚本就能**自己创建容器**（而不只是按钮）—— 这是"重建"的关键：
    --   编辑器里只留 `home` + `stage` + 三个模板引用，其余界面**全部由脚本在 `stage` 下创建**。
    --   `stage` 本身是空的、干净的，没有任何历史包袱（旧容器 `select`/`board`/… 已全部删除）。
    -- ★★★★★ 2026-10-02 **回滚开关**：恢复 93 的布局时，把脚本自动创建关掉。
    --
    --   背景：重建期间编辑器控件被删，脚本只能用"按 kind 选模板"临时把 108 个控件造出来，
    --   但脚本只有两个模板 ⇒ 造出来全是白块，而且把用户精心摆的界面（含素材）盖掉了。
    --   现在改成**以 93.gil 为基底**（它有全部控件和素材）+ 把 97 的 stage 三条搬回来，
    --   ⇒ 界面控件重新由编辑器提供 ⇒ **自动创建必须关掉**，否则又是一堆白块。
    auto_create = false,   -- true 才让 create_control 按 kind 自动实例化（全局开关，保持关）
    -- ★★★★★ 2026-10-09 **白名单整段删掉** —— 那 14 个控件已经**搬进存档**了 ✓
    --
    --   用户 2026-10-09 拍板：「**同意搬 1，然后 2，3 保持脚本**」✓
    --     · 搬 1 = `hex.*` ×7 ＋ `hit.*` ×7（**固定不变** ⇒ 该进存档 ✓）
    --     · 留 2 = `selbtn.*`（随关卡数变 ⇒ 脚本建 ✓）
    --     · 留 3 = `cell.*`（引擎按索引克隆 ⇒ 脚本建 ✓）
    --   搬法见 `tools/gil/gen_icons.mjs` ✓ 产物 `230-图标搬进存档.gil` ✓
    --     · `hex.*` ← 克隆 `cell.1.1.content.face`（**纯图片**，能渲染、收不到光标事件 ✓）
    --     · `hit.*` ← 克隆 `home.select` 且**不建 bg/label**（点击照收、什么都不画 ✓）
    --     · **顺序**：hex 先、hit 后 ⇒ 热区在上，射线不会被图片控件吞掉 ✓
    --
    --   ⇒ ★ 所以这份 `auto_create_only` 白名单**已经没有用了** ✓
    --     实测印证：`check_names` 报的「🟢 脚本会自动建」从 **14 → 0** ✓
    --     而且适配器那段本来就"**先找、找不到才建**" ⇒ 存档里有了就只走"找到" ✓
    --   ⇒ ★ 删掉它 = 少一处会漂移的配置，也少一条"脚本偷偷造控件"的路 ✓
    --     （`auto_create = false` **保留** ✓ —— 那条全局开关还有意义：
    --      它是"绝不让脚本按 kind 造一堆白块盖住界面"的底线 ✓）

    -- ★★★★★ 2026-10-03 **图标专用模板**（用户 20:45 提供索引 **1073742356**）
    --
    --   为什么要换掉格子的模板：`cfg.cells.prefab = 1073741876` 建出来的控件
    --   **自带一整套格子子控件**（`content` / `wall.up` / `wall.left` / `note` / `x` …）。
    --   真机日志的证据有两条：
    --     · 七个 `hex.*` 建出来后，各自的 `wall.up` / `wall.left` 都是 visible=true
    --       ⇒ 画面上多出 7 个"迷你格子"，**把棋盘搅乱**（用户报"棋盘也没出现"）；
    --     · 「图片控件」`face` 在格子的体检里是**直接子控件**，但在 `hex.*` 这棵树上钻不到
    --       ⇒ `SetImage` 只能落到 `content`（中间容器）上 ⇒ 回读正确但不显示。
    --
    --   ⇒ 用这个干净的客户端模板（里面只有图片节点、**用户没做静态引用**），
    --     由脚本 `SetImage` 把官方素材打上去（适配器里那段递归找图 + SetImage）。
    --
    --   ⚠️ 索引将来变了只改这一行。
    --   ⚠️⚠️ **2026-10-03 20:48 真机实测：这个索引用不了。**
    --     日志：`自动创建 hex.back 失败（模板 1073742356）err=nil`（七行全失败）
    --     ⇒ `pcall` 成功、`InstantiateClientUIControl` **返回 nil**
    --     ⇒ 它和 `m` 的 `1073742380` 一样，是**服务器控件模板**，
    --        官方明说「服务器控件的模板索引无法被客户端脚本调用」（见
    --        docs/客户端控件vs服务器控件.md）。
    --
    --   ⇒ 要用脚本创建，模板**必须**在
    --       「界面控件组管理 → 界面控件组库 → **客户端控件模板** → 添加客户端控件 → 存为模板」
    --      那条路里做（格子的 1073741876 就是这么来的）。
    --     做出来之后把索引填到这里，并把下面那行 `prefab_icon = nil` 改成索引即可。
    --   ★ 2026-10-03 20:57 **用户提供的可用索引 = 1073742357**（模板名就叫 `hex`，纯图片、空壳）
    --     它是在**客户端控件容器里**另存的 ⇒ 属于「客户端控件模板」⇒ 脚本能实例化。
    --     （1073742356 是在 root 下另存的 ⇒ 服务器模板 ⇒ 返回 nil，已作废。）
    prefab_icon = 1073742357,
    widgets     = true,    -- ★ 打开：启动时创建并显示 selbtn.1..N（102 验证过"能完成选关"的那四个方块）
    stage = {
      prefab = 1073742330,   -- 「容器节点」模板（用户 2026-10-02 提供）
      parent = "stage",
      selbar = "selbar",     -- 脚本创建的第一个容器：选关条
    },
    cells = {
      --
      --   2026-09-26 15:46 真机：`cell.1.1` 另存出来的模板索引 = **1073741876**。
      --   注意它**不一定就是可用**的 —— 要看它属于哪套资产体系：
      --   官方硬约束是「只有**客户端控件模板**里的控件，其模板索引才能被客户端脚本调用」。
      --
      --   所以这里填上以后，日志里会看到脚本**先试这个数字**；
      --   如果仍然 `全部实例化失败`，说明它不是客户端控件模板 → 去
      --   界面控件组管理 → 界面控件组库 →「客户端控件模板」→ 添加客户端控件 → 存为模板，
      --   再用那个新索引替换这一行。
      prefab   = 1073741876,

      -- ★★★★★ 2026-10-04 **棋盘几何全部改成"规划图 v3 量出来的显式值"。**
      --
      --   之前的推导链有个**根本错误**：一直拿 `M.LAYOUT.board = 812` 当基准，
      --   而 812 是**当初按"812÷5=162.4"推出来的，并不是量出来的** ——
      --   实际去量 `docs/布局图-关卡内-v3.png`（1600×900，已经是画布空间）：
      --     外框 x 608..1191、y 138..721  ⇒ **584 × 584**（比 812 设计 = 676.7 画布**小 93px**）
      --     边框四边**均匀 14px**
      --     内区 584−28 = 556 ⇒ `5c + 4×4 = 556` ⇒ **格 108、缝 4** ⇒ **pitch 112**
      --   ⇒ 这就是用户说的「**底板溢出边框了**」—— 677 的底板套 584 的框，当然溢出。
      --
      --   ★★ 2026-10-04 追加纠正（逐像素测量）：图上棋盘画的是 **6×6**，不是 5×5！
      --     外框 584 固定、**边框四边均匀 12px**（我第一版量成 14，因为把内侧那条 2px
      --     网格线算进边框了）、内区 = 584−24 = **560**、缝 **4px**：
      --       N=6：pitch = 560/6 = **93.33**（图上实测 93/94 交替）、格 = 89.33（实测 89/90）✅
      --       N=5：pitch = 560/5 = **112**、格 = **108** ← 本项目现在跑的就是这个 ✅
      --     ⇒ **"棋盘外框固定、格子按关卡实际 N 自适应"这条设计成立**
      --       （`cell_geometry` 本来就是按 N 算的）—— 所以**不要**把 pitch/size 写死，
      --       否则 6×6 / 7×7 的关卡会排错。只有 `ruler`(边框) 和 `gap`(缝) 是常量。
      --
      --   ⇒ 最终就两项显式值：
      ruler    = 12,           -- 边框厚度（画布空间）—— ★ 注意 `cell_geometry` 现在**两边各扣一份**
      gap      = 4,            -- 格子之间的缝（= 图上 4px 网格线）
      --
      --   （pitch / size / margin 故意**不写**：让 `cell_geometry` 按关卡 N 自动算。）
      --
      -- ★★★★★ 2026-10-03 "A 方案：留缝做网格线"（用户 22:54 提出并确认）—— **思路保留，数值已作废**。
      --
      --   思路（仍然成立）：`size` 比 `pitch` 小一点，露出的缝由 `stage` 的深色底板填
      --   ⇒ **天然网格线，0 个额外控件**，移动端无负担。
      --
      --   ⚠️ 但那一轮的数字（pitch 135 / gap 6 / size 129 / 底板 677）是**按没量过的 812 推的**，
      --      2026-10-04 去量了 `docs/布局图-关卡内-v3.png` 之后全部作废 ⇒
      --      改成上面那组显式值（pitch 112 / size 108 / gap 4 / margin 14 / 底板 584）。
      --
      --   ★ 这里原本还有一行 `gap = 6` —— **已删**。它和上面新写的 `gap = 4` 是**同一个表的重复键**，
      --     而 Lua 是"后写的赢" ⇒ 不删的话新值会被它静默覆盖（这个坑本项目已经踩过一次：
      --     当年的 `ruler = 0` 就是这样被 `ruler = 37` 吃掉的）。

      -- ★★★★★ 2026-10-04 **格子底图（`face` 的素材）= `100001`「基础形状·正四边形」。**
      --
      --   用户 2026-10-04 说：「我把格子换成了正四边形，已经存入模板了」，并给了新存档 `165.gil`。
      --   我把那份存档和上一版 `完整界面165-底板修正.gil` **逐控件按 id 对字段**，
      --   结果是 **94 条记录里只有 1 个控件的字段变了**：
      --       `id=1073741882  name=face`（格子 `content` 里的图片控件）
      --       `imageId`：**106053 → 100001**
      --   ⇒ 用户换的就是这张图。`100001` 属于「基础形状」类，是 **256x256 纯白满方块**
      --     （实测：覆盖率 1.000、色彩标准差 0、全不透明）—— 这就是"正四边形"。
      --
      --   ★★ **但在编辑器里换是不生效的**：`_cells_paint` 每次生成格子都会
      --      `face:SetImage(nil, cfg.cells.face_image or 106053)` —— **脚本会把编辑器里的选择覆盖掉**。
      --      所以必须在这里显式写 `face_image = 100001`，否则跑起来还是 106053（圆角白牌）。
      --
      --   ★ 顺带一个好消息：格子 `face` 的 `imageType` 是 `Stretch`（模板里设的），
      --     所以这也能**顺便验证 `100001` 能不能拉伸** —— 能拉伸的话，底板将来也能换它。
      face_image = 100001,

      -- prefab 为 nil 时才会看这里：从参照格子（下面的 probe）自己的 prefabIndex 读。
      --
      -- ★ **纯模板模式**下 probe 可以不存在 —— 编辑器里一个真格子都不建，
      --   只在 board 下放一个 `tpl.cell`（模板引用控件）。这时：
      --     · 缺格子数 = rows×cols（全部由脚本生成）
      --     · 参照格子为 nil → 不做图片盖章，副本外观**完全取自模板快照**
      --     · 体检会明确说"纯模板模式"而不是报"找不到控件"
      probe    = "cell.1.1",
      -- ★★★★★ 2026-10-02 **必须是 "stage"，不能是 "board"**（我上一轮改错了）。
      --
      --   103.gil（= 能点的那个干净底座）的 root 子级只有：
      --       `tpl.cell  tpl.stage  stage  home`   —— **没有 `board`**（重建时被删了）
      --   我为了"回滚到 93 布局"把这里改成 "board"，而当时导入的是 103 结构
      --   ⇒ 真机日志："生成格子失败：找不到父控件 board"（16:11 那份）。
      --   ⇒ 改回 `stage`（103 里存在，且是脚本创建的容器的家）。
      --
      --   注：93 那套"把编辑器容器全搬回来"的做法**已经被证明会让人点不动**
      --   （root 子级从 4 个变成 37 个 ⇒ 那批全屏容器把射线抢走了）。
      parent   = "stage",
      -- ★★★★★ 2026-10-04 **这一格原本还有一行 `ruler = 37` —— 已上移到「棋盘定型」那段，只留一处。**
      --
      --   原来 `ruler` 在这个表里**被赋值两次**（上面的 `ruler = 0` 和这里的 `ruler = 37`），
      --   而 **Lua 表构造器是"后写的赢"** ⇒ 生效的其实一直是 `37`，
      --   上面那行 `ruler = 0` 是**死配置**。现在删掉了错的那行（0），把 37 提到上面去，
      --   并把"为什么是 37 而不是 0"的判据写在那一处（结论：**37**，因为要跟
      --   `ui_controller` 的 `avail = board.w - ruler` 对齐）。
      --
      --   量出来的证据也在上面那段：截图实测 pitch 127.5 / 格子 123 / 左边框 43 / 右边框 2，
      --   与 `ruler = 37` 的预测**四项全中** ⇒ 布局图的设计值就是现在这样，不是 bug。
      --
      --   ⚠️ 教训：**同一个表里别重复写同一个键**。这两行互相矛盾、后写的静默获胜，
      --      让人以为"代码写的是 0"，实际跑的是 37 —— 排查几何问题时极容易看错方向。
      -- ⚠️ 不要写死 gap：它由 `max(2, ⌊pitch*0.03⌋)` 算出来，和 ui_controller
      --    里那套是同一个公式；写死会让两处差 1~2px。
      rows     = 5,            -- 只在读不到父控件尺寸时才用到的兜底
      cols     = 5,
      debug_signal = false,
      -- 扫全树：把所有"与参照格子不同的 prefabIndex"也当候选（排在最后，逐个真试）
      auto_scan = true,

      -- ★★ 墙 / 门的**目标厚度**（画布单位）—— 让"多粗"变成一个确定数字。
      --
      -- 为什么需要：真机实测「图片类型 = 基础」的图**按原尺寸画、不填充控件**，
      -- 而「拉伸」只有部分素材支持。所以脚本改用 `localScaleX/Y` 缩放来适配。
      -- 这里给出**目标几何**，脚本按 `目标 ÷ 基准` 双向求倍率 ——
      -- 于是最终看到的墙一定是「格子边长 × 本厚度」，跟你素材多大无关。
      --
      -- 前提：墙/门控件的尺寸**别手动改**，让编辑器按素材自动定（= 素材原尺寸）。
      -- 脚本第一次试玩会把基准与倍率打进日志，可以核对：
      --   [murdoku] 边缘适配 wall.up：基准 24x8 → 目标 135x8（倍率 5.63 / 1.00）
      edge_thickness = 8,
      -- 门比墙短一点（占格子边长的比例），看起来才像"门"
      door_length_ratio = 0.45,
      -- 边缘适配的日志每个方向只打一次（调完可设 false 关掉）
      edge_fit_log = true,

      -- ★★ 图层顺序（**从下到上**）。
      --
      -- 用户 2026-09-27 提醒：图片/文本之间的层级**由模板里的位置（同级次序）决定**，
      -- **不看创建或生成顺序**，而且**图层会互相覆盖** —— 所以必须规划。
      --
      -- 官方给了控制手段（客户端控件基类）：`SetSiblingIndex(i)`「数值越大通常越靠后、
      -- **显示越靠上**」、`SetAsFirstSibling()`、`SetAsLastSibling()`。
      -- 脚本按下面这份列表**从下往上**重排一遍，于是最终层叠**不依赖编辑器里的摆放次序**
      -- （那个仍然作为默认值；顺序改这里就行，不用回编辑器调）。
      --
      -- 规划理由：
      --   face  最底 —— 它是格面底图，也是"放置角色"时被换图的那张
      --   obj   在底图之上 —— 家具图标要能看见
      --   wall  压住底图 —— 墙贴在格子边上，必须显出来
      --   door  压住墙 —— 同一段边可能既是墙又是门，门要在墙上面
      --   x     划掉标记压住一切装饰
      --   note  铅笔笔记最上 —— 玩家写的信息永远可读，不能被图挡
      layer_order = {
        "face",
        "obj",
        "wall.up", "wall.down", "wall.left", "wall.right",
        "door.up", "door.down", "door.left", "door.right",
        "x",
        "note",
      },
    },

    -- ★★ 调试开关（**必须放在 cfg 顶层**，不能放进 cfg.cells 里！）
    --
    -- ★★★ 2026-09-29：**编辑器布局优先**（放在 cfg 顶层，与 cells 平级）。
    --   默认 true ⇒ 存档里已有的控件保持**你在编辑器里调的几何**，
    --   脚本只摆"自己运行时生成的控件"（格子等）。
    --   想回到"布局全由代码说了算"：改成 false。
    respect_editor_rect = true,

    -- 2026-09-27 踩过：我一开始把它们加在 `cells = { … }` 里（挨着 `debug_signal`），
    -- 而 adapter 读的是 `self.cfg.debug_key` → **永远 nil** → 诊断一行都不打，
    -- 白白多跑了一轮真机才查出来。
    -- 教训：`cfg.cells.<名>` 与 `cfg.<名>` 是**两张表**，加开关时先确认读取处写的是哪个。
    debug_key   = false,   -- 打出 KeyEventType 解析结果的类型 + 实际收到的按键名
    debug_image = false,   -- 打出 SetImage 之后 face 的 imageType
    debug_event = false,   -- 打出每条控件绑定到了什么事件 + 点击时实际派发的事件

    -- ★ 头像卡按人数自适应列数：编辑器按"最挤的情况"摆好，
    --   运行时由 Adapter:apply_tray_layout 用 ui_controller 算好的几何摆正。
    tray_parent = "tray",

    -- ★ 键盘绑在哪个控件上。
    --   真机实测（2026-09-26）：`root`（容器节点）**不一定支持** `AddKeyEventListener` ——
    --   模拟器里所有控件都有这个方法，所以这件事离线验不出来。
    --   这里给一串候选：找到第一个"既找得到、又支持按键事件"的控件就用它。
    key_control = "root",
    key_control_fallbacks = { "board", "cell.1.1", "topbar" },

    -- ★ 参照格子体检（cell.1.1）：把"类型/射线/子控件/图片来源/光标门控"逐条读出来
    --   并给 ✅/❌ 与修法。搭界面阶段非常有用，**每个会话只打一次**。
    --   界面搭完、验收通过之后可以改成 false 让日志干净些。
    diagnose_cell = true,
  })

  -- ★ 线索卡底条：每条线索一个（最多 18 条），索引 1073742333（murdoku-clue-row）。
  --   用循环补，免得手抄 18 行 —— 这也是"一处定义"的做法。
  do
    local c = adapter.cfg
    c.prefab_of = c.prefab_of or {}
    c.parent_of = c.parent_of or {}
    for i = 1, 18 do
      local id = "clue." .. i .. ".bg"
      c.prefab_of[id] = 1073742333
      c.parent_of[id] = "clues"
    end
  end
  Murdoku.prepare(adapter)
  -- 离线测试钩子：让 tests/entry_smoke.lua 能直接驱动适配层
  -- （验调色板 / 染色 / 墙门这些需要构造场景的东西）。
  -- 生产环境无副作用：只是一个可读的全局引用，名字够独特不会撞上游戏自己的全局。
  __murdoku_debug = { adapter = adapter, Murdoku = Murdoku }
  return adapter
end

-- ===== 开局前的控件探针 =====
-- 找不到关键控件时，把**客户端控件树整个打出来**，并按"树是空的 / 树里有东西但名字不对"
-- 两种情况给**不同的**处置建议 —— 真机上这两类的病因完全不一样。
--
-- ★ 2026-09-26 12:20 真机日志暴露的问题：**OnInit 阶段树本来就是空的**
--   （约 0.5 秒后才出现，这是实测事实），可是这份诊断在 OnInit 就把
--   "树是空的 + 三条可能原因"全砸出来了 → 看着像出了大故障，其实一切正常。
--
--   所以现在分轻重：
--     · 树是空的、**还有重试机会**（final=false）→ 只说一句"稍后重试"，不打树、不打病因；
--     · 树是空的、**已经放弃重试**（final=true）→ 打完整诊断（三条原因）；
--     · 树里**有节点**但没有 board/cell.1.1 → 立刻打（这是真的名字/层级问题，等也没用）。
-- ★★★★★ 2026-10-02 **安全调用 `on_start`：把失败原因打出来**。
--
--   真机现象（用户 13:45 日志）：日志在"键盘快捷键已绑定"之后**直接 destroyed** ——
--   没有 `started:`、没有"放弃自动开局"、什么错都没有。
--   ⇒ 说明 `Murdoku.on_start` **被调用了但返回 nil（或抛错被引擎吞掉）**，
--     于是 `started` 一直 false ⇒ 每帧重试 ⇒ 而重试时不再打印（已 dump 过）⇒ **完全静默**。
--   ⇒ 这里用 pcall 包住 + 把"抛错"和"返回 nil"这两种情况**都打成正常日志**。
local function safe_on_start(tag)
  local f = Murdoku.on_start
  if f == nil then
    if printerr then printerr("[murdoku] on_start 不存在（模块没加载完整）") end
    return nil
  end
  local retry_screen = "home"
  if FORCE_LEVEL ~= nil then retry_screen = nil end
  local ok, a, b = pcall(f, FORCE_LEVEL, {
    adapter      = adapter,
    restore_save = (FORCE_LEVEL == nil),
    screen       = retry_screen,
  })
  if not ok then
    if printerr then
      printerr("[murdoku] ⚠️ on_start 抛错了（" .. tostring(tag) .. "）：" .. tostring(a))
    end
    return nil
  end
  local self = a
  if self == nil then
    if printerr then
      printerr("[murdoku] ⚠️ on_start 返回 nil（" .. tostring(tag)
        .. "）—— 没有抛错，说明它内部主动放弃了。"
        .. "常见原因：控件树缺关键控件（比如棋盘容器 / 参照格子）时就 return nil。")
    end
    return nil
  end
  if print then
    print("[murdoku] ✅ on_start 成功（" .. tostring(tag) .. "）：level="
      .. tostring(self.level and self.level.id) .. "  screen=" .. tostring(self.screen or "(关卡内)"))
  end
  return self
end
local function probe_or_dump(final)
  if adapter == nil then return false end
  -- ★★★★★ 2026-10-02 **就绪判据不能写死 `board` / `cell.1.1`**。
  --
  --   真机后果（用户 13:31 日志）：重建时这两个控件被删了 ⇒ 判据**永远为假**
  --   ⇒ 一直重试到上限 ⇒ 打印"放弃自动开局" ⇒ **`Murdoku.on_start` 从未真正执行**
  --   ⇒ 于是：
  --        · `home` 停在 `vis=false` ⇒ **主页整个消失**（子控件都是 true，父级不显示）
  --        · `seal_containers` 没跑到 ⇒ **2D/3D 隔离失效**
  --   ⇒ 症状看着是两件事，**根因是同一个**。
  --
  --   新判据（按"重建后什么才一定存在"来写）：
  --     ① 旧结构：`board` / `cell.1.1` 任一存在（向后兼容老存档）
  --     ② 新结构：`stage` / `home` 任一存在（重建后一定有）
  --     ③ 兜底：`root` 存在且已经有 >3 个子控件 ⇒ 树就绪
  local ready = false
  pcall(function()
    if adapter:find("board") ~= nil or adapter:find("cell.1.1") ~= nil then
      ready = true
    elseif adapter:find("stage") ~= nil or adapter:find("home") ~= nil then
      ready = true
    else
      local rt = adapter:find("root")
      if rt ~= nil and rt.GetChildren ~= nil then
        local kids = nil
        pcall(function() kids = rt:GetChildren() end)
        if type(kids) == "table" and #kids > 3 then ready = true end
      end
    end
  end)
  if ready then return true end
  if tree_dumped then return false end

  -- 先量一下树有多大（只数不打印），据此决定话术的轻重
  local n = 0
  if adapter.count_names ~= nil then
    pcall(function() n = adapter:count_names(6, 400) or 0 end)
  end

  if n == 0 and not final then
    if print then
      print("[murdoku] 控件树还没就绪（OnInit/OnStart 阶段是空的，属正常）→ 稍后重试")
    end
    return false
  end

  tree_dumped = true

  if printerr then
    printerr("[murdoku] 就绪判据未满足（board/cell.1.1/stage/home 都不在），下面把「脚本能看到的客户端控件」全列出来")
  end

  if adapter.dump_names ~= nil then
    pcall(function() n = adapter:dump_names(6, 400) or 0 end)
  elseif game ~= nil and game.PrintClientUITree ~= nil then
    pcall(game.PrintClientUITree)
    n = -1     -- 不知道数量
  end

  if printerr then
    if n == 0 then
      -- ★ 这是最要命的一类：树压根是空的。控件"建了"也没用 —— 根本没被创建出来。
      printerr("[murdoku] 客户端控件树是**空的**（0 个节点）。控件没被创建出来，"
        .. "最可能是下面三条之一：")
      printerr("[murdoku]   ① 界面布局没被【职业】引用 —— 官方硬性要求，"
        .. "入口：战斗预设 → 职业 → 选择布局；或 界面控件组管理 → 界面布局 → 参数配置 → 【打开玩家编辑】")
      printerr("[murdoku]   ② 控件做在了【界面控件组库】里 —— 官方原话："
        .. "界面控件组库中制作的元件实际游玩时并不显示，必须【添加至界面布局】")
      printerr("[murdoku]   ③ 控件没放进【客户端控件容器】里面（或容器没勾【激活】/【可见】）")
    elseif n > 0 then
      printerr("[murdoku] 树里有 " .. tostring(n) .. " 个节点，但里面没有 board / cell.1.1。"
        .. "对照上面那份名单看名字差在哪（脚本是**精确匹配**的：大小写、空格、自动后缀都算不一样）。")
      -- 把"差一点"的名字直接点出来 —— 真机上最常见的就是 (1) 后缀 / 大小写 / 空格
      if adapter.near_names ~= nil then
        for _, want in ipairs({ "root", "board", "cell.1.1" }) do
          local near = nil
          pcall(function() near = adapter:near_names(want, 5) end)
          if type(near) == "table" and #near > 0 then
            printerr("[murdoku]   近似 " .. want .. " 的名字有："
              .. table.concat(near, " / ") .. "  ← 注意大小写、空格、括号后缀")
          end
        end
      end
    else
      printerr("[murdoku] 已把客户端控件树打到日志里，对照 docs/控件坐标表-1600x900.md 看名字。")
    end
  end
  return false
end

-- ===== PC 键盘快捷键（可重试）=====
--
-- ★ 2026-09-26 12:20 真机日志暴露的真 bug：
--   旧实现只在 `OnInit` 里绑一次，而 **OnInit 阶段控件树是空的** ——
--   于是日志打出「键盘绑定跳过：找不到可接收按键的控件（root）」
--   和「键盘快捷键没绑上（不影响鼠标/触摸操作）」，
--   而后者听起来无关紧要，很容易放过 —— **实际上真机上 PC 键盘从来没生效过**。
--
--   现在做成"可以补绑"：OnInit 试一次，等控件树就绪（OnStart/OnUpdate 重试）
--   之后再试一次；绑成功就记下来不再重复。
local keyboard_bound = false
-- ⚠️ 这里是 **`Enum.KeyEventType` 的名字**，不是物理键名！
--    官方签名：`AddKeyEventListener(eventType, callback)`，第一个参数是**语义事件**
--    （「设备 + 语义 + 按下/抬起」的组合）。下面注释里括号内是该事件的**默认物理键**，
--    而「奇匠按键」是**可被玩家重映射**的槽位，不能假定玩家按的确实是那个物理键。
--
--    官方**没有** Return / Enter / Escape 事件，所以：
--      · 放置       → 改用「拾取/交互」（默认 F）
--      · 关弹窗/选关 → 改用奇匠按键42（默认 Backspace）
local KEY_SPEC = {
  -- 方向：奇匠按键36..39（默认 ↑ ↓ ← →）
  "KeyboardCraftspersonKey36Down", "KeyboardCraftspersonKey37Down",
  "KeyboardCraftspersonKey38Down", "KeyboardCraftspersonKey39Down",
  -- 选角色 1..10：奇匠按键1..10（默认 1..9 与 0）
  "KeyboardCraftspersonKey1Down",  "KeyboardCraftspersonKey2Down",
  "KeyboardCraftspersonKey3Down",  "KeyboardCraftspersonKey4Down",
  "KeyboardCraftspersonKey5Down",  "KeyboardCraftspersonKey6Down",
  "KeyboardCraftspersonKey7Down",  "KeyboardCraftspersonKey8Down",
  "KeyboardCraftspersonKey9Down",  "KeyboardCraftspersonKey10Down",
  -- 主要动作
  "KeyboardInteractKeyDown",       -- 拾取/交互（F）  = 放置
  "KeyboardJumpKeyDown",           -- 跳跃（Space）  = 铅笔笔记
  "KeyboardDropKeyDown",           -- 落下（X）      = 划掉这格
  "KeyboardCraftspersonKey42Down", -- Backspace     = 关弹窗 / 选关
  -- 工具与命令
  "KeyboardOpenShortcutWheelKeyDown", -- 快捷轮盘（Tab）= 循环换工具
  "KeyboardCharacterSkill1KeyDown",   -- 角色技能1（E） = 橡皮擦
  "KeyboardCharacterSkill3KeyDown",   -- 角色技能3（R） = 提交
  "KeyboardCraftspersonKey12Down",    -- Z = 撤销
  "KeyboardCraftspersonKey13Down",    -- Y = 重做
  "KeyboardCraftspersonKey15Down",    -- H = 提示
}

local function bind_keyboard_once(where)
  if adapter == nil or keyboard_bound then return false end
  local ok = pcall(function()
    local n, note = adapter:bind_keys(KEY_SPEC)
    if n > 0 then
      keyboard_bound = true
      if print then
        print("[murdoku] 键盘快捷键已绑定 " .. n .. " 个键（PC 可用，移动端忽略）"
          .. "　[" .. tostring(note) .. "]"
          .. (where and where ~= "OnInit" and ("　via " .. where) or ""))
      end
    elseif where == "OnInit" then
      -- OnInit 时树是空的，绑不上是**预期的**，不要吓人
      if print then
        print("[murdoku] 键盘快捷键暂未绑定（OnInit 时控件树还没就绪，稍后会自动补绑）")
      end
    else
      -- 补绑也失败了 → 把**原因**说出来（哪几个候选控件、各自为什么不中用）
      if print then
        print("[murdoku] 键盘快捷键没绑上（不影响鼠标/触摸操作）：" .. tostring(note))
        print("[murdoku]   → 想用键盘的话：在 cfg.key_control / key_control_fallbacks 里"
          .. "换一个控件名（必须是**预设按钮**这类支持按键事件的控件）")
      end
    end
  end)
  return ok and keyboard_bound
end

-- ===== 官方生命周期 =====

function OnInit()
  -- ① 逐帧更新开关（OnUpdate 全靠它）—— 内部已 pcall
  pcall(enable_update)

  -- ② 先把适配器建起来并交给 main，再谈其它诊断。
  --    顺序很关键：只要它建成了，后面就算有诊断炸掉，游戏逻辑照样能跑。
  local ok, err = pcall(build_adapter)
  if not ok then
    if printerr then
      printerr("[murdoku] OnInit 在【创建适配器】这一步失败：" .. tostring(err)
        .. " —— 游戏逻辑不会启动（脚本本身是跑起来了，问题在这一步）")
    end
    if LOAD_ERR == "main" then raw_mark(250)
    elseif LOAD_ERR ~= nil then raw_mark(260) end
    return
  end

  -- ③ 诊断：只报不改，各自 pcall
  pcall(check_canvas)
  pcall(function() beacon(adapter, BEACON.OnInit) end)

  -- ④ PC 键盘（可能绑不上，之后会自动补绑）
  bind_keyboard_once("OnInit")

  -- ⑤ 汇总：看到这句说明 OnInit 完整走完了
  if print then print("[murdoku] OnInit done（适配器已就绪，等 OnStart 开局）") end
end

function OnStart()
  if LOAD_ERR ~= nil or Murdoku == nil then return end

  -- 万一 OnInit 没能建起适配器，这里补一个（可重入）
  if adapter == nil then
    if printerr then printerr("[murdoku] OnStart 发现适配器为空，补建一个") end
    pcall(build_adapter)
  end

  pcall(function() beacon(adapter, BEACON.OnStart) end)

  -- 开局前探一下关键控件；找不到就把控件树打出来，省得靠猜
  if not probe_or_dump(false) then
    -- 这次先不开局：让 OnUpdate 的惰性重试去等控件就绪
    if print then print("[murdoku] 控件还没就绪，交给 OnUpdate 重试") end
    return
  end

  -- 控件树已就绪 → 把 OnInit 没绑上的键盘补绑一次（OnInit 时树是空的，必定失败）
  bind_keyboard_once("OnStart")

  -- 钉死了关卡就**不要**恢复存档（存档是别的关的，读进来会串味）
  --
  -- ★★★ 2026-09-29：**开局进主页**（用户要求的主页选关流程）。
  --
  --   ⚠️ 必须用显式 if 算，**不能用 `and/or` 三元式**：
  --     我写过 `FORCE_LEVEL and nil or "home"` —— Lua 里 `x and nil` 恒为 nil，
  --     于是 `nil or "home"` 永远是 "home"，条件等于没写。
  --     凡"某个分支是 nil/false"，就必须写成 if。
  --
  --   ⚠️ 另一个大教训：**`OnStart()` 不接受参数**，入口自己造 opts 表 ——
  --     所以"从外面传个 flag 绕过主页"是做不到的。测试请走主页流程
  --     （`tools/sim/kit.mjs` 的 `enterLevel()`）；钉死关卡（测试模式）则直接进关。
  local start_screen = "home"
  if FORCE_LEVEL ~= nil then start_screen = nil end
  local self = safe_on_start("首次")
  if self then
    started = true
    if print then print("[murdoku] started: " .. tostring(self.level and self.level.id)) end
  end
end

function OnEnable() end
function OnDisable() end

function OnUpdate(dt)
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  if not started then
    -- 惰性重试：等客户端控件容器/控件就绪后再开局
    retry_elapsed = retry_elapsed + (dt or 0)
    if retry_elapsed >= RETRY_INTERVAL then
      retry_elapsed = 0
      retry_tries = retry_tries + 1
      if retry_tries > RETRY_LIMIT then
        -- 放弃了 → 这时候"树还是空的"才是真的故障，把完整诊断和三条病因打出来
        probe_or_dump(true)
        if printerr then
          printerr("[murdoku] 等不到客户端控件，放弃自动开局"
            .. "（检查客户端控件容器是否【激活且可见】、界面布局是否被【职业】引用）")
        end
        started = true      -- 停止重试，避免刷屏
      else
        if adapter == nil then pcall(build_adapter) end
        if probe_or_dump(false) then
          -- 控件树就绪了 → 补绑键盘（OnInit 时绑不上，那时树是空的）
          bind_keyboard_once("重试")
          -- 与 OnStart 那条保持一致。
          -- ⚠️ 写成显式 if —— 我在这里第一次就是顺手写成
          --    `(FORCE_LEVEL ~= nil) and nil or "home"`，
          --    而 `x and nil` 恒为 nil ⇒ 永远落到 "home"，{==} 我又踩了同一个坑 {==}。
          --    所以：**只要三元式里有一个分支是 nil/false，就必须写 if**。
          local retry_screen = "home"
          if FORCE_LEVEL ~= nil then retry_screen = nil end
          local self = safe_on_start("重试")
          if self then
            started = true
            if print then print("[murdoku] started (retry " .. retry_tries .. ")") end
          end
        end
      end
    end
    return
  end
  Murdoku.on_update(dt)
end

-- 需要跟随关卡时停的表现可以放这里；本框架的 UI 计时走 OnUpdate
function OnLevelUpdate(dt) end

function OnDestroy()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  Murdoku.on_destroy()
  if print then print("[murdoku] destroyed") end
end
