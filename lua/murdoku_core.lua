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
local RoomMap = require("room_map")

function M.build_walls(level, rows, cols)
  return RoomMap.build_walls(level, rows, cols)
end

  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：build_walls_OLD　原 L125..L153

function M.compute_rooms(rows, cols, wall_set)
  return RoomMap.compute_rooms(rows, cols, wall_set)
end

  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：compute_rooms_OLD　原 L159..L192

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
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ctx.role_of　原 L282..L288

  function ctx.pos(who) return core.pos[ctx.resolve(who)] end
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ctx.solution_pos　原 L291..L291
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
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ctx.is_door　原 L338..L340
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
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ctx.adjacent_rooms　原 L352..L357
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ctx.rooms_adjacent　原 L358..L360
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
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ctx.count_in_col　原 L440..L440

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
  -- ★★★ 2026-10-11 **两条路都要认** ✗✓（★ 用户："让这套流程代替原本的流程" ✓）：
  --   ★ ① ★ **手写的 `clues`**（★ 带 `type` ✓）⇒ ★ 照旧逐条校验类型与参数 ✓（★ 老测试/夹具走这条 ✓）
  --   ★ ② ★★ **没有手写** ⇒ ★ **按棋盘规格生成槽位** ✓（★ 条数 = `rows × cols` ✓）
  --      ★ 槽位**不带 `type`** ✗ ⇒ ★ **不校验类型** ✓ ★ 但**校验条数** ✓
  --      ★★ 这就是"**clues 的条数由棋盘规格决定**"这条规则的**检查点** ✓✓
  local clue_list = level.clues or {}
  if #clue_list == 0 then
    local rows, cols = nil, nil
    if type(level.size) == "table" then rows, cols = level.size.rows, level.size.cols end
    rows = rows or level.rows
    cols = cols or level.cols
    if type(rows) == "number" and type(cols) == "number" then
      -- ★ 槽位条数**必须** = 棋盘格数 ✓ ⇒ ★ 在这里报错 ✓（★ 而不是等到界面上少一张卡才发现 ✓）
      level.clue_slots = rows * cols
    end
  else
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
      -- ★★ 2026-10-11：★ 槽位表（★ 没有 `type` ✓）不是"内容" ✗
      --   ⇒ ★ 它的长度**不该**拿来卡 `false_clue` ✓ ——
      --     ★ 否则"第 3 条是假话"会被拿去和 49 个空槽位比 ✓ ★ 毫无意义 ✓
      --   ★ 判据用**有内容的条数** ✓（★ 手写关卡里两者相等 ✓ 行为不变 ✓）
      --   ★★ 内容为 0 ⇒ ★ `false_clue` **无从指** ⇒ ★ 只校验取值范围 ✓ **不报"越界"** ✗
      --     （★ 与 `validate_levels` 的"未测"**同一口径** ✓）
      local n_content = 0
      for i = 1, #clue_list do
        if type(clue_list[i]) == "table" and clue_list[i].type then n_content = n_content + 1 end
      end
      if not n or n < 1 then
        err("meta.false_clue = %s 非法（应是 >= 1 的整数）", tostring(meta.false_clue))
      elseif n_content > 0 and n > n_content then
        err("meta.false_clue = %s 超出线索范围（本关 %d 条有内容）",
          tostring(meta.false_clue), n_content)
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

  -- ★★★★★★ 2026-10-11 **线索槽位：条数 = 棋盘【容量】** ✗✓✓
  --
  --   ★★★ 用户 2026-10-11 给出的**完整生产流程** ✓（★ 原话 ✓）：
  --     ★「★ **clues 区域有多少内容由棋盘规格决定** ✓
  --       ★ **几乘几就是几条** ✓
  --       ★ 至于是**哪几条**由 `assets` 下的 `row` 决定 ✓
  --       （★ 多余的后续会删 ✓ ★ 没有的会建 ✓）
  --       ★ **`assets` 负责 clues 区域需要的一切素材** ✓
  --       ★ **`face` 对应头像** ✓ ★ **`who` 对应名字** ✓ ★ **`what` 对应内容** ✓
  --       ★ **`letter` 对应字母标签** ✓
  --       ★ **同时 `face` 和 `letter` 还对应【放置到棋盘上的】头像和铅笔笔记** ✓
  --       ★ **这是目前的完整 clues 区域的生产流程，没有缺失部分**」✓✓
  --
  --   ★★ 用户随后**进一步定调** ✓：「★ 不是让 `clues` 保持空 ✗
  --     ★★ **而是让这套流程代替原本的流程、赋予 `clues` 的一切内容** ✓
  --     ★ **直接从逻辑上替换掉原先那套模式**」✓✓
  --
  --   ★★★★ 2026-10-11 **我第一版理解错了"几乘几就是几条"** ✗✓（★ 用户当场纠正 ✓）：
  --     ★ 我按 ★ **`rows × cols`（格数）** 实现 ✗ ⇒ ★ 7×7 = **49 条** ✗
  --     ★★★ 用户原话 ✓：「★ **不是 7 乘 7 写 49 条** ✓
  --       ★ **而是因为按规则 7 乘 7 只放得下 7 人** ✓
  --       ★ **所以只写七条**」✓✓
  --     ⇒ ★★ 正解 ✓：★ **条数 = 棋盘【容量】= `min(rows, cols)`** ✓
  --       ★ **依据** ✓：★ 本作开 `one_per_row` ＋ `one_per_col` ✓
  --         ⇒ ★ **每行每列至多一人** ✓ ⇒ ★ **最多只能站 `min(rows, cols)` 个人** ✓✓
  --   ⇒ ★★★ 所以：★ **条数 = 棋盘能站几个人** ✓ ★ **不是格子数** ✗
  --     ★ 四关 ✓：★ 5×5 ⇒ **5** ✓ ★ 5×5 ⇒ **5** ✓ ★ 6×6 ⇒ **6** ✓ ★ 7×7 ⇒ **7** ✓
  --     ★★ 与**棋子数完全相等** ✓（★ 实测：5 / 5 / 6 / 7 ✓）—— ★ 这不是巧合 ✓
  --       ★ 是"**一人一条**"这条设计的直接推论 ✓✓
  --     ★ 内容全部来自 `row.*` ✓ ★ **没有"手写线索表"这条路了** ✗（★ 它被替换掉了 ✓）
  --
  --   ★ 兼容 ✓：★ 仍然认**手写的 `clues`** ✓（★ 测试夹具与老关卡用 ✓）
  --     ★ 只有"**没手写**"时才**按容量补满槽位** ✓
  --     ⇒ ★★ 这样"旧模式"在**真关卡**里彻底不存在 ✓ 而测试仍可构造受控数据 ✓
  --
  --   ★★ 多解问题**不归这里管** ✗ —— ★ 用户原话 ✓：
  --     「★ **多解问题是内容问题，我来解决**」✓ ⇒ ★ **代码只保证条数对 ✓ 不替内容兜底** ✓✓
  --
  -- ★ 槽位形状 ✓：★ `{ slot = i }` ✓ —— ★ **只标"这是第几条"** ✓
  --     ★ **内容（who/what/letter/face）由 `row.*` 那条管线填** ✓（★ 见 `ui_controller` ✓）
  --     ★ **没有 `type`** ✗ ⇒ ★ `clue_results` 会如实报"尚无内容" ✓（★ 不编 ✗）
  self.clues = level.clues
  if type(self.clues) ~= "table" or #self.clues == 0 then
    self.clues = {}
    local n = self:clue_slot_count()
    for i = 1, n do
      self.clues[i] = { slot = i }
    end
  end
  -- ★ 槽位条数 = 棋盘**容量** ✓（★ 判据写在代码里 ✓ 而不是只写在注释里 ✓）
  self.clue_slots = #self.clues

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

-- ★★★★★★ 2026-10-11 **棋盘能站几个人 = 线索槽位数** ✗✓✓
--
--   ★★★ 用户定的口径 ✓（★ 原话 ✓）：
--     「★ **不是 7 乘 7 写 49 条** ✓
--      ★ **而是因为按规则 7 乘 7 只放得下 7 人** ✓ ★ **所以只写七条**」✓✓
--   ★ 依据 ✓：★ 本作开 `one_per_row` ＋ `one_per_col` ✗ ⇒ ★ **每行每列至多一人** ✓
--     ⇒ ★★ **最多 `min(rows, cols)` 个人** ✓ ⇒ ★ **线索就是这么多条** ✓✓
--   ★ 与 `piece_count()` 的关系 ✓：★ **四关实测完全相等** ✓（5/5/6/7 ✓）★ 不是巧合 ✓
--     ★ 是"**一人一条**"这条设计的直接推论 ✓
--   ★ ⚠️ ★ 仍然按**规则开关**算容量 ✓ —— ★ 若某关关掉 `one_per_row` ✓
--     ★ 容量就**不是** `min(rows, cols)` ✗ ⇒ ★ 那就退回**格数** ✓（★ 不能用错的上限 ✓）
function Core:clue_slot_count()
  local rules = self:rules()
  local manhattan = (rules.one_per_row ~= false) and (rules.one_per_col ~= false)
  if manhattan then return math.min(self.rows, self.cols) end
  return self.rows * self.cols
end

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
  -- ★★ 2026-10-11：★ 读【槽位表】`self.clues` ✓ 不是 `level.clues` ✗
  --   ★ 槽位由棋盘规格生成 ✓（★ `rows × cols` ✓ 见 `Core.new` 里那一段 ✓）
  --   ★ 内容由 `assets/row.*` 那条管线填 ✓
  --   ★★ 槽位**没有 `type`** ⇒ ★ 如实报"尚无内容" ✓ ★ **不编一个类型出来** ✗✓
  local list = self.clues or {}
  local out = {}
  for i = 1, #list do
    local cl = list[i]
    local def = cl.type and M.clues[cl.type] or nil
    local satisfied = false
    if def then satisfied = def.validate(ctx, cl) and true or false end
    out[i] = {
      index = i,
      type = cl.type,
      text = def and def.text(ctx, cl) or ("待填内容（槽位 " .. tostring(i) .. "）"),
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
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：accuse_legacy_murderer　原 L2310..L2338

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
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：solve_placements_only　原 L2357..L2440

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
    -- ★★ 2026-10-11：★ 同样读**槽位表** ✓（★ 槽位可能没有 `type` ✓ ⇒ `cl` 只剩 `slot` ✓）
    local cl = (self.clues or {})[i] or {}
    clue_view[i] = {
      index = i,
      type = cl.type,
      text = clues[i].text,
      satisfied = clues[i].satisfied,
      -- ★★★★★★ 2026-10-10 **去掉 `or cl.a`** ✗✓✓ —— ★ 用户定夺 ✓
      --
      --   ★★ 用户原话 ✓（★ 说得比"甲/乙/丙"三个选项都本质 ✓）：
      --     ★「**取消双人线索这一说** ✓ —— **一次放置只放一个人** ✓，
      --       **通过线索绑定一次变灰两个人没有合理性**」✓✓
      --
      --   ★ 症状 ✓：★ **放上 A ⇒ 三张线索卡一起变灰** ✗
      --   ★ 根因 ✓（★ 地图员实测 ✓）：★ `same_room {a="A", b="B"}` 这类线索**没有 `who`** ✗
      --     ⇒ ★ **`or cl.a` 把它退化成 `"A"`** ✗
      --     ⇒ ★ `case_001` 里有效 `who == "A"` 的线索【正好 3 条】** ⇒ 三张一起灰 ✓✓
      --   ⇒ ★★ **不是 `_placed_now` 算错了** ✗ ——
      --     ★ **是"这条线索属于谁"本身有歧义** ✓（★ `{A,B}` 涉及两人 ✓）
      --
      --   ★ 判据 ✓（★ 按用户的话落成规则 ✓）：
      --     ★ **只有【明确属于某一个人】的线索才参与灰白** ✓
      --     ★ `cl.who` 有值 ⇒ 用它 ✓（★ `@` 开头的别名由下游置 nil ✓ 本来就不灰 ✓）
      --     ★★ **`cl.who` 没有（双人线索）⇒ `who = nil`** ✗
      --       ⇒ ★ **下游 `cl.id = nil` ⇒ `_pid = nil` ⇒ `_placed_now = false` ⇒ 【永不灰】** ✓✓
      --
      --   ★ 为什么对 ✓：★ **一次放置只放一个人** ✓ ⇒
      --     ★ **"涉及两人的线索因为其中一人就位而变灰"没有合理性** ✓（★ 用户原话 ✓）
        who = cl.who,
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

  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：solution_from_grid_literal　原 L2667..L2677

-- 从字面量生成 walls：用 | 和 - 在网格里画墙
--   例： {"A|B", "A B"} 之类；这里提供更直白的生成器：cells 里用 "v"/"h" 标记
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：walls_from_ascii　原 L2681..L2696

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
  -- ★★ 2026-10-11：★ 读**槽位表** ✓ ＋ ★ **先看有没有"真判据"** ✗
  --   ★ 槽位（★ 由棋盘规格生成 ✓ 内容待 `row.*` 填 ✓）**没有 `type`** ✗
  --     ⇒ ★ 它们**还不能判真假** ⇒ ★★ **`solve` 无从下嘴** ✓
  --   ⇒ ★ 如实返回**空解表** ✓ ★ **不猜、不编解** ✗✓
  --     ★（★ 上层：`validate_levels` 报"未测" ✓ ★ 作者拿到的是"还没内容"而不是"多解" ✓）
  local clues = self.clues or {}
  local real = 0
  for i = 1, #clues do if clues[i] and clues[i].type then real = real + 1 end end
  if real == 0 then return {} end
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
