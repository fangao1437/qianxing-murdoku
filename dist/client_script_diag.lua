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

function M.build_walls(level, rows, cols)
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
  self.moves = 0
  self.elapsed = 0
  self.status = M.STATUS_PLAYING
  self.mode = M.MODE_PLACE
  self.selected = nil
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

local function push_history(self, action)
  self.history[#self.history + 1] = action
  self.future = {}
  self.moves = self.moves + 1
end

local function do_place(self, r, c, id, record)
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
  if record then push_history(self, { kind = "place", r = r, c = c, id = id, prev = prev }) end
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end

local function do_clear(self, r, c, record)
  local prev = self.grid[r][c]
  if not prev then return false end
  self.grid[r][c] = nil
  self.pos[prev] = nil
  self.row_count[r] = self.row_count[r] - 1
  self.col_count[c] = self.col_count[c] - 1
  self.hint_cells[cell_key(r, c)] = nil
  if record then push_history(self, { kind = "clear", r = r, c = c, prev = prev }) end
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end

local function toggle_note(self, r, c, id)
  if not id or self.blocked[cell_key(r, c)] then return false end
  if self.grid[r][c] then return false end
  local cell = self.notes[r][c]
  if cell[id] then cell[id] = nil else cell[id] = true end
  push_history(self, { kind = "note", r = r, c = c, id = id })
  return true
end

-- 统一点击入口（轻点 = 铅笔笔记；放置请用 hold_cell）
function Core:tap_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then
    return false, "越界"
  end
  if self:is_blocked(r, c) then
    return false, "这个格子站不了人"
  end
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
  -- 放置模式：轻点=笔记（与 murdoku 一致），长按=放置
  if self.grid[r][c] then
    self.selected = self.grid[r][c]
    return do_clear(self, r, c, true), nil
  end
  if not self.selected then return false, "先点一个头像" end
  return toggle_note(self, r, c, self.selected), nil
end

-- 长按入口：放置（murdoku 的核心手感）
function Core:hold_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false, "越界" end
  if self:is_blocked(r, c) then return false, "这个格子站不了人" end
  if not self.selected then return false, "先点一个头像" end
  if self.mode == M.MODE_ERASE then
    -- 长按橡皮擦 = 清空全部
    self:clear_all()
    return true, "已清空全盘"
  end
  local ok = do_place(self, r, c, self.selected, true)
  if ok then self.selected = nil end
  return ok, nil
end

-- X 标记：这格不可能是任何人
function Core:toggle_x(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false end
  if self:is_blocked(r, c) then return false end
  if self.grid[r][c] then return false end
  self.x_marks[r][c] = not self.x_marks[r][c]
  if self.x_marks[r][c] then self.notes[r][c] = {} end
  push_history(self, { kind = "x", r = r, c = c })
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
    if action.prev then do_place(self, action.r, action.c, action.prev, false) end
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
  self.moves = math.max(0, self.moves - 1)
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
  self.moves = self.moves + 1
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
    moves = self.moves,
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
  self.moves = save.moves or 0
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
    moves = self.moves,
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

  local saved = {}
  local function install(grid)
    saved.grid, saved.pos = self.grid, self.pos
    saved.rc, saved.cc = self.row_count, self.col_count
    self.grid = grid
    self.pos = {}
    self.row_count, self.col_count = {}, {}
    for r = 1, self.rows do self.row_count[r] = 0 end
    for c = 1, self.cols do self.col_count[c] = 0 end
    for r = 1, self.rows do
      for c = 1, self.cols do
        local id = grid[r][c]
        if id then
          self.pos[id] = { r = r, c = c }
          self.row_count[r] = self.row_count[r] + 1
          self.col_count[c] = self.col_count[c] + 1
        end
      end
    end
  end
  local function restore()
    self.grid, self.pos = saved.grid, saved.pos
    self.row_count, self.col_count = saved.rc, saved.cc
  end

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

  -- 一个完整摆位 + 一组角色归属是否成立
  local function consider()
    install(grid)
    local stop = false
    for i = 1, #rpairs do
      local roles = {
        thief = rpairs[i].thief,
        accomplice = rpairs[i].accomplice,
        victim = self.victim_id,
      }
      local sok = self:structure_report(roles)
      if sok then
        local ctx = make_context(self, roles)
        local failed = 0
        for ci = 1, #clues do
          local def = M.clues[clues[ci].type]
          if not def or not def.validate(ctx, clues[ci]) then
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
    restore()
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
        local stop = place_at(k + 1)
        grid[p.r][p.c] = nil
        if stop then return true end
      end
    end
    return false
  end

  place_at(1)
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

M.LAYOUT = {
  topbar = { x = 0, y = 0, w = 1920, h = 104 },
  title  = { x = 32, y = 18, w = 520, h = 50 },
  stats  = { x = 1520, y = 26, w = 380, h = 46 },

  -- 左侧面板：头像卡 + 线索卡 + 图例
  left   = { x = 24, y = 128, w = 392, h = 880 },
  tray   = { x = 40, y = 148, w = 360, h = 300 },
  tray_item_w = 176, tray_item_h = 132,
  clues  = { x = 40, y = 470, w = 360, h = 430 },
  clue_row_h = 52,
  clue_max_visible = 8,
  legend = { x = 40, y = 916, w = 360, h = 76 },

  -- 中央棋盘：外圈留出 R1..Rn / C1..Cn 坐标尺
  board  = { x = 480, y = 176, w = 880, h = 880 },
  ruler  = 44,
  cell   = 160,
  cell_gap = 4,
  wall_thickness = 10,

  -- 右侧信息栏
  right  = { x = 1420, y = 128, w = 460, h = 880 },

  -- 底部操作条（放在左侧面板底部与棋盘下方之间）
  actions = { x = 480, y = 940, w = 880, h = 120 },
  action_btn = { w = 168, h = 56, gap = 14 },

  modal = { w = 760, h = 460 },
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
  self.modal = nil          -- nil | {kind="accuse"} | {kind="result",win=bool,message=} | {kind="howto"} | {kind="intro",page=n}
  self.intro_page = opts.skip_intro and (#M.INTRO + 1) or 1
  self.share_code = nil
  self._created = {}
  self._props = {}
  self._gesture_snapshot = nil
  self.debug = opts.debug == true
  return self
end

function Controller:fx(target, kind, params)
  local e = { target = target, kind = kind }
  if params then for k, v in pairs(params) do e[k] = v end end
  self.effects[#self.effects + 1] = e
  return e
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
  if res.solved then
    self.modal = { kind = "result", win = true, message = res.message }
    self:fx("modal", M.EFFECTS.SOLVED)
    if self.opts.on_solved then self.opts.on_solved(core:view()) end
  else
    self.modal = nil
    self:fx("modal", M.EFFECTS.FAIL)
  end
  self.dirty = true
  return res
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

-- 把挂起的单击落成铅笔笔记（等过双击窗口才执行，免得抢在第二次点击前面）
function Controller:flush_pending_note()
  local p = self.pending_click
  if p == nil then return end
  if (self.now or 0) - p.t < DOUBLE_CLICK_SECONDS then return end
  self.pending_click = nil
  if self.core:tap_cell(p.r, p.c) then
    self:fx(self:cell_id(p.r, p.c), M.EFFECTS.NOTE)
    self.dirty = true
  end
end

-- 棋盘格被单击：单击=笔记 / 双击=放置；已放置格、X 模式、橡皮擦模式、只写笔记模式都立即生效
function Controller:on_cell_click(r, c)
  local core = self.core
  self.now = self.now or 0
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode

  -- 双击 → 放置
  if (not occupied) and mode == "place" then
    local last = self.last_click
    if last and last.r == r and last.c == c and (self.now - last.t) <= DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      self.pending_click = nil
      local who = core.selected
      if core:hold_cell(r, c) then
        self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
        if self.opts.on_place then self.opts.on_place(who, r, c) end
      end
      self.dirty = true
      return
    end
    self.last_click = { r = r, c = c, t = self.now }
  end

  -- 这些情况单击立即生效，不需要等双击窗口
  if occupied or mode == "x" or mode == "eraser" or mode == "note" then
    self.pending_click = nil
    local had = core.grid[r][c]
    if core:tap_cell(r, c) then
      if had then
        self:fx(self:cell_id(r, c), M.EFFECTS.ERASE)         -- 单击已放置的格 = 拿起
        if self.opts.on_clear then self.opts.on_clear(had) end
      else
        self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
      end
      self.dirty = true
    end
    return
  end

  -- 放置模式下的空格：先挂起，等过了双击窗口再落成笔记
  self:flush_pending_note()
  self.pending_click = { r = r, c = c, t = self.now }
end

function Controller:on_input(event)
  local core = self.core
  local a = event.action

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
      self:fx("board", M.EFFECTS.UNDO)
    end

  elseif a == "click" then
    self:on_cell_click(event.r, event.c)

  elseif a == "cell_right" then
    if core:toggle_x(event.r, event.c) then
      self:fx(self:cell_id(event.r, event.c), M.EFFECTS.XMARK)
    end

  elseif a == "tool" then
    -- 双击橡皮擦工具 = 清空全盘（替代原来的长按）
    if event.mode == "eraser" and self:is_double("tool.eraser") then
      self.pending_click = nil
      core:clear_all()
      self:fx("board", M.EFFECTS.ERASE)
      self.toast = "已清空全盘"
    else
      core:set_mode(event.mode)
    end

  elseif a == "undo" then
    if core:undo() then self:fx("action.undo", M.EFFECTS.UNDO) end

  elseif a == "redo" then
    if core:redo() then self:fx("action.redo", M.EFFECTS.UNDO) end

  elseif a == "hint" then
    local ok, msg = core:hint()
    self.toast = msg
    if ok then self:fx("action.hint", M.EFFECTS.SELECT) end

  elseif a == "reveal" then
    -- 直接揭示答案（照 murdoku 的 Reveal，用于教学/放弃）
    core:reset()
    for id, p in pairs(core.solution) do
      core:select_suspect(id)
      core:hold_cell(p.r, p.c)
    end
    self.toast = "已揭示答案"

  elseif a == "submit" then
    local res = core:submit()
    self:fx("action.submit", M.EFFECTS.SUBMIT)
    -- 规格 5.3：提交只给硬约束反馈，不揭晓任何线索层面的对错（连条数都不说）
    self.toast = res.message
    if res.ok then
      self.modal = { kind = "accuse_thief" }
    end

  elseif a == "accuse_thief" then
    self.pending_thief = event.id
    self.modal = { kind = "accuse_accomplice", thief = event.id }

  elseif a == "accuse_no_accomplice" then
    self:finish_accuse(self.pending_thief, false, nil)

  elseif a == "accuse_pick_accomplice" then
    self:finish_accuse(self.pending_thief, true, event.id)

  elseif a == "accuse" then
    -- 兼容入口：只给盗窃者，同伙按关卡声明处理
    self:finish_accuse(event.id, nil, nil)

  elseif a == "restart" then
    core:reset()
    self.modal = nil
    self.toast = nil

  elseif a == "share" then
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

  elseif a == "back" and self.opts.on_back then
    self.opts.on_back()

  elseif a == "next_level" and self.opts.on_next_level then
    self.opts.on_next_level()
  end

  self.dirty = true
  return self.effects
end

function Controller:tick(dt)
  self.now = (self.now or 0) + (dt or 0)
  self.core:set_elapsed((self.core.elapsed or 0) + (dt or 0))
  self:flush_pending_note()      -- 挂起的单击到点就落成笔记
  self.dirty = true
end

function Controller:is_intro_active() return (self.intro_page or 1) <= #M.INTRO end

----------------------------------------------------------------------------
-- 布局规格
----------------------------------------------------------------------------

local function rect_of(t) return { x = t.x, y = t.y, w = t.w, h = t.h } end

function Controller:build_layout()
  local vm = self.core:view()
  local L = M.LAYOUT
  local nodes = {}
  local function push(n) nodes[#nodes + 1] = n return n end
  local function btn(id, parent, r, text, event, style, enabled)
    return push({ id = id, kind = "button", parent = parent, rect = r, text = text,
                  style = style or "stamp", enabled = (enabled ~= false), event = event })
  end

  push({ id = "root", kind = "container", rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }, style = "screen" })

  -- ===== 顶部工具条 =====
  push({ id = "topbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "topbar" })
  push({ id = "hud.title", kind = "text", parent = "topbar", rect = rect_of(L.title), text = vm.title, style = "title" })
  local announce_text = ""
  if vm.meta_announce == "one" then
    announce_text = "　※ 线索中有一句假话"
  elseif vm.meta_announce == "none" then
    announce_text = "　※ 线索全部为真"
  end
  push({ id = "hud.subtitle", kind = "text", parent = "topbar",
         rect = { x = L.title.x, y = L.title.y + 48, w = L.title.w + 320, h = 30 },
         text = tostring(vm.subtitle or "") .. announce_text, style = "subtitle",
         visible = (vm.subtitle ~= nil or announce_text ~= "") })

  -- 顶部工具条（1920 宽内排布：标题 32..512 / 计时步数 520..814 / 工具 840..1246 / 动作 1262..1828）
  local function tool(id, label, mode, x)
    return push({ id = id, kind = "button", parent = "topbar",
                  rect = { x = x, y = 26, w = 130, h = 52 }, text = label,
                  style = (vm.hud.mode == mode) and "tab.active" or "tab",
                  event = { action = "tool", mode = mode } })
  end
  tool("tool.place",  "放置",  "place",  840)
  tool("tool.x",      "X 标记", "x",      978)
  tool("tool.eraser", "橡皮擦", "eraser", 1116)

  btn("action.undo", "topbar", { x = 1262, y = 26, w = 90, h = 52 }, "撤销",
      { action = "undo" }, "stamp.sm", vm.hud.can_undo)
  btn("action.redo", "topbar", { x = 1358, y = 26, w = 90, h = 52 }, "重做",
      { action = "redo" }, "stamp.sm", vm.hud.can_redo)
  btn("action.submit", "topbar", { x = 1460, y = 26, w = 190, h = 52 },
      vm.hud.filled and "提交" or "提交（先摆满）", { action = "submit" }, "stamp.primary", vm.hud.filled)
  btn("action.hint", "topbar", { x = 1660, y = 26, w = 80, h = 52 }, "提示",
      { action = "hint" }, "stamp.sm", vm.hud.can_hint)
  btn("action.reveal", "topbar", { x = 1748, y = 26, w = 80, h = 52 }, "揭示",
      { action = "reveal" }, "stamp.sm")

  push({ id = "hud.timer", kind = "text", parent = "topbar",
         rect = { x = 520, y = 30, w = 140, h = 46 },
         text = self:format_time(vm.hud.time), style = "stat" })
  push({ id = "hud.moves", kind = "text", parent = "topbar",
         rect = { x = 664, y = 30, w = 150, h = 46 },
         text = string.format("%d 步", vm.hud.moves), style = "stat" })

  -- ===== 左侧面板：头像卡 + 线索卡 + 图例 =====
  push({ id = "left", kind = "container", parent = "root", rect = rect_of(L.left), style = "panel.left" })
  push({ id = "tray", kind = "container", parent = "left", rect = rect_of(L.tray), style = "tray" })
  local per_row = 2
  for i = 1, #vm.tray do
    local it = vm.tray[i]
    local col = (i - 1) % per_row
    local row = math.floor((i - 1) / per_row)
    push({
      id = "tray." .. tostring(it.id),
      kind = "button",
      parent = "tray",
      rect = { x = L.tray.x + col * (L.tray_item_w + 12),
               y = L.tray.y + row * (L.tray_item_h + 10),
               w = L.tray_item_w, h = L.tray_item_h },
      text = it.name,
      image = it.portrait,
      style = it.selected and "portrait.selected" or (it.placed and "portrait.placed" or "portrait"),
      state = { selected = it.selected, placed = it.placed, is_victim = it.is_victim },
      event = { action = "suspect", id = it.id },
    })
  end

  push({ id = "clues", kind = "container", parent = "left", rect = rect_of(L.clues), style = "panel" })
  local shown = math.min(#vm.clues, L.clue_max_visible)
  for i = 1, shown do
    local cl = vm.clues[i]
    push({
      id = "clue." .. i,
      kind = "text",
      parent = "clues",
      rect = { x = L.clues.x, y = L.clues.y + (i - 1) * L.clue_row_h,
               w = L.clues.w, h = L.clue_row_h - 8 },
      text = cl.text,
      style = cl.satisfied and "clue.ok" or "clue",
      event = { action = "focus_clue", index = i },
    })
  end
  push({ id = "clues.more", kind = "text", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y + shown * L.clue_row_h, w = L.clues.w, h = 30 },
         text = string.format("还有 %d 条线索", math.max(0, #vm.clues - shown)),
         style = "muted", visible = (#vm.clues > shown) })

  push({ id = "legend", kind = "text", parent = "left", rect = rect_of(L.legend),
         text = "单击=铅笔笔记　双击=放置　X工具=划掉这格\n橡皮擦：单击清格，双击清全盘",
         style = "muted" })

  -- ===== 中央棋盘（含坐标尺）=====
  push({ id = "board", kind = "container", parent = "root", rect = rect_of(L.board), style = "board" })
  local cell, gap, ruler = L.cell, L.cell_gap, L.ruler
  local gx = L.board.x + ruler
  local gy = L.board.y + ruler
  -- 列标尺
  for c = 1, vm.cols do
    push({ id = "ruler.c." .. c, kind = "text", parent = "board",
           rect = { x = gx + (c - 1) * (cell + gap), y = L.board.y, w = cell, h = ruler - 6 },
           text = "C" .. c, style = "ruler" })
  end
  -- 行标尺
  for r = 1, vm.rows do
    push({ id = "ruler.r." .. r, kind = "text", parent = "board",
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
      push({
        id = self:cell_id(r, c),
        kind = "button",
        parent = "board",
        rect = { x = gx + (c - 1) * (cell + gap), y = gy + (r - 1) * (cell + gap), w = cell, h = cell },
        style = style,
        text = cd.name or "",
        image = cd.suspect and Controller.portrait_of(vm, cd.suspect) or cd.object or nil,
        notes = cd.notes,
        room = cd.room,
        walls = cd.walls,
        doors = cd.doors,
        occupiable = cd.occupiable,
        x_mark = cd.x,
        enabled = true,   -- 不可站人的格子也要能点（用于打 X / 提示原因）
        event = { action = "click", r = r, c = c },
      })
    end
  end

  -- ===== 右侧信息栏 =====
  push({ id = "right", kind = "container", parent = "root", rect = rect_of(L.right), style = "panel.right" })
  push({ id = "hud.progress", kind = "text", parent = "right",
         rect = { x = L.right.x + 20, y = L.right.y + 20, w = L.right.w - 40, h = 44 },
         text = string.format("已放置 %d / %d", self:placed_count(vm), vm.piece_count),
         style = "stat" })
  local got, total = self.core:score()
  push({ id = "hud.score", kind = "text", parent = "right",
         rect = { x = L.right.x + 20, y = L.right.y + 74, w = L.right.w - 40, h = 44 },
         text = string.format("位置正确 %d / %d", got, total), style = "muted" })
  -- 区域推断面板（偷窃版 R3/R4 的可观测量，玩家自己也能数出来）
  local st = vm.structure or {}
  local st_lines = {}
  if st.victim_room == nil then
    st_lines[#st_lines + 1] = "把受害者摆上棋盘后，这里会显示区域推断"
  else
    st_lines[#st_lines + 1] = string.format("受害者区域 #%d，区内 %d 人（k=%d）",
                                            st.victim_room, st.k or 0, st.k or 0)
    st_lines[#st_lines + 1] = string.format("→ 同伙：%s",
      (st.k or 0) >= 2 and "必然是 1 人" or "可有可无，看线索与假话预算")
    local adj = st.adjacent or {}
    if #adj == 0 then
      st_lines[#st_lines + 1] = "相邻区域：无（关卡非法）"
    else
      local parts = {}
      for i = 1, #adj do
        local room = adj[i]
        parts[#parts + 1] = string.format("#%d 无辜 %d", room, (st.innocent_counts or {})[room] or 0)
      end
      st_lines[#st_lines + 1] = "门相邻区域：" .. table.concat(parts, "、")
      if st.best_rooms and #st.best_rooms == 1 then
        st_lines[#st_lines + 1] = string.format("→ 盗窃者应在 #%d（无辜人数最多）", st.best_rooms[1])
      elseif st.best_rooms and #st.best_rooms > 1 then
        st_lines[#st_lines + 1] = "相邻区域无辜人数并列（本关允许并列）"
      end
    end
  end
  for i = 1, #(vm.violations or {}) do
    st_lines[#st_lines + 1] = "· " .. vm.violations[i].text
  end
  push({ id = "hud.violations", kind = "text", parent = "right",
         rect = { x = L.right.x + 20, y = L.right.y + 132, w = L.right.w - 40, h = 230 },
         text = table.concat(st_lines, "\n"), style = "muted" })
  push({ id = "hud.share", kind = "text", parent = "right",
         rect = { x = L.right.x + 20, y = L.right.y + 360, w = L.right.w - 40, h = 120 },
         text = self.share_code and ("分享码：" .. self.share_code) or "", style = "muted" })
  push({ id = "hud.toast", kind = "text", parent = "right",
         rect = { x = L.right.x + 20, y = L.right.y + 520, w = L.right.w - 40, h = 140 },
         text = self.toast or vm.last_message or "", style = "toast",
         visible = (self.toast ~= nil or vm.last_message ~= nil) })
  -- 顶部放不下的次级操作放这里（1920 内不会溢出）
  local rx = L.right.x + 20
  btn("action.howto", "right", { x = rx, y = L.right.y + 680, w = 100, h = 52 }, "玩法",
      { action = "howto" }, "tab")
  btn("action.share", "right", { x = rx + 108, y = L.right.y + 680, w = 100, h = 52 }, "分享",
      { action = "share" }, "tab")
  btn("action.restart", "right", { x = rx + 216, y = L.right.y + 680, w = 100, h = 52 }, "重开",
      { action = "restart" }, "tab")
  btn("action.back", "right", { x = rx + 324, y = L.right.y + 680, w = 116, h = 52 }, "返回列表",
      { action = "back" }, "tab")

  -- ===== 底部操作条（大按钮，触屏友好）=====
  push({ id = "actions", kind = "container", parent = "root", rect = rect_of(L.actions), style = "actions" })
  local ax, ay = L.actions.x, L.actions.y
  local aw = 150
  local agap = 12
  btn("action.q.place", "actions", { x = ax, y = ay, w = aw, h = L.action_btn.h }, "放置工具",
      { action = "tool", mode = "place" }, (vm.hud.mode == "place") and "tab.active" or "tab")
  btn("action.q.note", "actions", { x = ax + (aw + agap), y = ay, w = aw, h = L.action_btn.h }, "只写笔记",
      { action = "tool", mode = "note" }, (vm.hud.mode == "note") and "tab.active" or "tab")
  btn("action.q.x", "actions", { x = ax + 2 * (aw + agap), y = ay, w = aw, h = L.action_btn.h }, "划掉这格",
      { action = "tool", mode = "x" }, (vm.hud.mode == "x") and "tab.active" or "tab")
  btn("action.q.eraser", "actions", { x = ax + 3 * (aw + agap), y = ay, w = aw, h = L.action_btn.h }, "橡皮擦",
      { action = "tool", mode = "eraser" }, (vm.hud.mode == "eraser") and "tab.active" or "tab")
  btn("action.q.accuse", "actions",
      { x = ax + 4 * (aw + agap), y = ay, w = 200, h = L.action_btn.h },
      "指认凶手", { action = "submit" }, "stamp.primary", vm.hud.filled)

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
             text = string.format("用时 %s · %d 步 · 误指认 %d 次 · 位置 %d/%d",
                                  self:format_time(vm.hud.time), vm.hud.moves, vm.hud.failed_accusations, got, total),
             style = "muted" })
      btn("modal.again", "modal", { x = mx + 40, y = my + mh - 88, w = 180, h = 60 }, "重玩本关",
          { action = "restart" }, "stamp")
      btn("modal.share", "modal", { x = mx + 240, y = my + mh - 88, w = 180, h = 60 }, "分享棋局",
          { action = "share" }, "stamp")
      btn("modal.next", "modal", { x = mx + 440, y = my + mh - 88, w = 200, h = 60 }, "下一关",
          { action = "next_level" }, "stamp.primary")

    elseif modal.kind == "share" then
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 30, w = mw - 60, h = 56 }, text = "分享棋局", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 110, w = mw - 60, h = 200 },
             text = "把这个码发给别人，对方可以还原你的棋盘：\n\n" .. tostring(modal.code), style = "modal.body" })
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

  return nodes
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
-- 增量渲染
----------------------------------------------------------------------------

function Controller:render(adapter, force)
  local nodes = self:build_layout()
  local seen = {}
  for i = 1, #nodes do
    local n = nodes[i]
    seen[n.id] = true
    if not self._created[n.id] then
      adapter:create_control(n)
      self._created[n.id] = true
      self._props[n.id] = {}
    end
    local last = self._props[n.id]
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
          adapter:set_property(n.id, k, v)
          last[k] = v
        end
      end
    end
    local lr = last.__rect
    if force or not lr or lr.x ~= n.rect.x or lr.y ~= n.rect.y or lr.w ~= n.rect.w or lr.h ~= n.rect.h then
      adapter:set_property(n.id, "rect", n.rect)
      last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      adapter:destroy_control(id)
      self._created[id] = nil
      self._props[id] = nil
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    adapter:play_effect(e.target, e.kind, e)
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
    hud.title / hud.subtitle / hud.timer / hud.moves / hud.violations / hud.toast / hud.share
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
  local self = setmetatable({}, Adapter)
  self.cfg = cfg
  self.signals = M.SIGNALS
  if cfg.signals then
    for k, v in pairs(cfg.signals) do self.signals[k] = v end
  end
  self.controls = {}       -- 节点 id -> 引擎控件
  self.handlers = {}       -- 控件 id -> 事件表
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

----------------------------------------------------------------------------
-- 控件查找（只用文档里的接口）
----------------------------------------------------------------------------

local function find_in(ctrl, name, depth)
  if ctrl == nil or depth > 16 then return nil end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname == name then return ctrl end
  local children = ctrl:GetChildren()
  if children then
    for i = 1, #children do
      local hit = find_in(children[i], name, depth + 1)
      if hit then return hit end
    end
  end
  return nil
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

function Adapter:find(name)
  if self.controls[name] ~= nil then return self.controls[name] end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    -- 主路径：按「控件名称」深度优先搜索
    for i = 1, #roots do
      local hit = find_in(roots[i], name, 0)
      if hit then
        self.controls[name] = hit
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
        return hit
      end
    end
  end
  return nil
end

-- 子控件（cell.1.1 下的 face / note / x / door.up ...），带缓存
function Adapter:sub(parent_id, child_name)
  local key = parent_id .. "." .. child_name
  local cached = self.subs[key]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local parent = self:find(parent_id)
  if parent == nil or parent.GetChild == nil then
    self.subs[key] = false
    return nil
  end
  local c = parent:GetChild(child_name)
  self.subs[key] = c or false
  return c
end

----------------------------------------------------------------------------
-- 控件生命周期
----------------------------------------------------------------------------

function Adapter:create_control(node)
  self.handlers[node.id] = node
  local ctrl = self:find(node.id)

  if ctrl == nil and self.cfg.prefab_of and self.cfg.prefab_of[node.id]
     and game and game.InstantiateClientUIControl then
    local parent = self:find((self.cfg.parent_of and self.cfg.parent_of[node.id]) or "root")
    if parent then
      ctrl = game.InstantiateClientUIControl(self.cfg.prefab_of[node.id], parent)
      if ctrl and node.id then ctrl.name = node.id end
      self.controls[node.id] = ctrl
    end
  end

  if ctrl == nil then
    self:warn_once("missing:" .. tostring(node.id),
      "控件未找到：" .. tostring(node.id) .. "（请在客户端控件容器里按此名字创建）")
    return nil
  end
  return ctrl
end

function Adapter:destroy_control(id)
  local ctrl = self.controls[id]
  if ctrl and game and game.DestroyClientUIControl then
    game.DestroyClientUIControl(ctrl)
  end
  self.controls[id] = nil
  self.handlers[id] = nil
end

----------------------------------------------------------------------------
-- 属性同步
----------------------------------------------------------------------------

function Adapter:set_property(id, key, value)
  local ctrl = self:find(id)
  if ctrl == nil then return end

  if key == "text" then
    if ctrl.text ~= nil then
      ctrl.text = tostring(value)
    else
      local c = self:sub(id, "text")
      if c and c.text ~= nil then c.text = tostring(value) end
    end

  elseif key == "image" then
    local target = self:sub(id, "face") or ctrl
    if target and target.SetImage and value ~= nil then
      local src = target.imageSource                 -- 沿用编辑器配好的来源
      local ok, err = pcall(function() target:SetImage(src, value) end)
      if not ok then self:warn_once("setimage", "SetImage 失败：" .. tostring(err)) end
    end

  elseif key == "visible" then
    if ctrl.SetVisible then ctrl:SetVisible(value and true or false) end

  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end

  elseif key == "rect" and self.apply_rect then
    if ctrl.SetAnchoredPosition then ctrl:SetAnchoredPosition(value.x, value.y) end
    if ctrl.SetSizeDelta then ctrl:SetSizeDelta(value.w, value.h) end

  elseif key == "style" then
    -- 语义化样式：只做最小可感知反馈；正式外观请在编辑器里配控件视觉状态
    local scale = nil
    if value == "portrait.selected" then scale = 1.08
    elseif value == "portrait.placed" then scale = 0.96
    elseif value == "tab.active" then scale = 1.04 end
    if scale and ctrl.SetLocalScale then ctrl:SetLocalScale(scale, scale, 1) end

  elseif key == "notes" then
    local c = self:sub(id, "note")
    if c and c.text ~= nil then c.text = table.concat(value or {}, " ") end

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
end

----------------------------------------------------------------------------
-- 输入：只绑 CursorClick（双击由上层判定）
----------------------------------------------------------------------------

function Adapter:_fire(event, phase, data)
  if self.on_input == nil then return end
  local evt = {}
  for k, v in pairs(event) do evt[k] = v end
  evt.phase = phase
  if data and data.GetUIPos then
    local ok, x, y = pcall(function() return data:GetUIPos() end)
    if ok then evt.x, evt.y = x, y end
  end
  self.on_input(evt)
end

function Adapter:bind_input(id, node)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if ctrl.AddCursorEventListener == nil then
    self:warn_once("nocursor:" .. tostring(id),
      "控件 " .. tostring(id) .. " 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）")
    return
  end
  local click = E("CursorEventType.CursorClick")
  if click == nil then
    self:warn_once("noenum", "Enum.CursorEventType.CursorClick 缺失，无法绑定点击")
    return
  end
  local ev = node.event or { action = "click" }
  ctrl:AddCursorEventListener(click, function(data)
    self:_fire(ev, "click", data)
  end)
end

----------------------------------------------------------------------------
-- 动效（Tween 关键帧，全部 nil-safe）
----------------------------------------------------------------------------

local EFFECTS = {
  pop_tile     = { 0.26, { 0.62, 1.06, 1.0 } },
  note_pop     = { 0.14, { 0.90, 1.0 } },
  pulse        = { 0.18, { 1.00, 1.14, 1.0 } },
  sel_pop_glow = { 0.30, { 1.00, 1.12, 1.03, 1.0 } },
  undo_flash   = { 0.16, { 1.05, 1.0 } },
  submit_nudge = { 0.28, { 1.00, 1.035, 1.0 } },
  clue_box_pop = { 0.22, { 0.82, 1.03, 1.0 } },
  solved_flash = { 0.36, { 1.00, 1.12, 1.0 } },
  vanish       = { 0.20, { 1.00, 0.0 } },
  roomwall     = { 0.14, { 0.98, 1.0 } },
  shake        = { 0.30, { 1.00, 0.97, 1.03, 1.0 } },
}

function Adapter:play_effect(id, effect_name, params)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if game == nil or game.Tween == nil then return end
  local spec = EFFECTS[effect_name]
  if spec == nil then return end

  local dur, frames = spec[1], spec[2]
  local seg = dur / (#frames - 1)
  for i = 1, #frames - 1 do
    local to = frames[i + 1]
    local ok, err = pcall(function()
      local t = game.Tween(ctrl, { localScaleX = to, localScaleY = to }, seg)
      if t then t:Play() end
    end)
    if not ok then
      self:warn_once("tween", "Tween 失败：" .. tostring(err))
      return
    end
  end
  self:after(dur, function() end)
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

function Murdoku.prepare(adapter)
  prepared_adapter = adapter
  return adapter
end

function Murdoku.current() return current end

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

  local controller = UIC.new(core, {
    debug = opts.debug,
    skip_intro = opts.skip_intro,
    on_next_level = opts.on_next_level or function()
      local nxt = Levels.next(level.id)
      if nxt then Murdoku.start(nxt, opts) end
    end,
    on_solved = function(vm)
      -- 破案：把结算数据发给服务器（节点图侧接 关卡结算/排行榜）
      adapter:signal_emit(Qianxing.SIGNALS.SOLVED, {
        tostring(level.id),
        math.floor(vm.hud.time or 0),
        vm.hud.moves or 0,
        vm.hud.failed_accusations or 0,
      })
    end,
  })

  local self = setmetatable({}, Murdoku)
  self.core = core
  self.level = level
  self.adapter = adapter
  self.controller = controller
  self.options = opts
  self.last_tick = 0

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

  controller:render(adapter, true)

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
    local probe = adapter:find("board") or adapter:find("cell.1.1")
    if probe == nil then return nil end
  end
  local self, err = Murdoku.start(level_id, opts)
  if not self and printerr then printerr("[murdoku] 开局失败：" .. tostring(err)) end
  return self
end

function Murdoku.on_update(dt)
  if not current then return end
  current.adapter:on_tick(dt)
  current.controller:tick(dt)
  -- 时间只在整秒变化时重渲染，省性能
  local sec = math.floor(current.core.elapsed or 0)
  if sec ~= current.last_tick then
    current.last_tick = sec
    current.controller:render(current.adapter)
  end
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
    current.controller:render(current.adapter)
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
      current.controller:render(current.adapter)
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
  current.controller:render(current.adapter, true)
  return true
end

-- 主动存档：压成分享码字符串 + 三个整数（局内存档不支持结构体/字典）
function Murdoku.save_now()
  if not current then return false end
  local core = current.core
  local payload = {
    level_id   = tostring(current.level.id),
    state_code = core:encode_state(),
    moves      = core.moves or 0,
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

local M = {}

-- 按顺序登记你的关卡；游戏里默认从第一个开始
local LIST = {
  "levels.demo_selftest",     -- 框架自检样例（不需要就删掉这一行）
  -- "levels.case_001",
  -- "levels.case_002",
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
    ["书桌"] = { cells = { { r = 1, c = 5 } }, occupiable = false },
    ["地毯"] = { cells = { { r = 2, c = 1 }, { r = 2, c = 2 } }, occupiable = true },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "管家" },
    { id = "B", name = "医生" },
    { id = "C", name = "歌女" },
    { id = "D", name = "伯爵" },
    { id = "V", name = "老宅主", is_victim = true },
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

-- ==== 入口：官方生命周期回调（OnInit / OnStart / OnUpdate / ...）==== --
--[[----------------------------------------------------------------------------
  entry_client_script.lua —— 客户端脚本入口（挂到客户端控件上的那个文件）

  用法：在「千星沙箱 → 客户端脚本资源管理器」里新建脚本映射，
        把它关联到本文件；然后在客户端控件（例如 cell.1.1 或容器节点）的
        「脚本」页签 → 添加脚本，选中这个映射。

  官方生命周期（运行时按固定名字查找并调用）：
    OnInit() / OnStart() / OnEnable() / OnDisable()
    OnUpdate(dt)       逐帧，**不受关卡时停影响**
    OnLevelUpdate(dt)  关卡逐帧，受关卡时停影响
    OnDestroy()

  注意：客户端控件必须挂在一个**处于激活且可见的「客户端控件容器」**里，
        否则控件找不到、脚本逻辑也不跑（官方文档明确说明）。
--]]--

local Murdoku  = __require("main")
local Qianxing = __require("engine_adapter_qianxing")

local adapter   = nil
local started   = false

local RETRY_INTERVAL = 0.5
local RETRY_LIMIT    = 60      -- 最多重试 30 秒
local retry_elapsed  = 0
local retry_tries    = 0

function OnInit()
  adapter = Qianxing.new({
    -- 布局坐标是否由脚本接管：默认 false（推荐在编辑器里摆好位置）
    apply_rect = false,
    verbose    = false,
  })
  Murdoku.prepare(adapter)
  if print then print("[murdoku] OnInit done") end
end

function OnStart()
  -- 开局：由 Murdoku 负责加载关卡、建控制器、做首次渲染
  local self = Murdoku.on_start(nil, {
    adapter      = adapter,
    restore_save = true,
  })
  if self then
    started = true
    if print then print("[murdoku] started: " .. tostring(self.level and self.level.id)) end
  end
end

function OnEnable() end
function OnDisable() end

function OnUpdate(dt)
  if not started then
    -- 惰性重试：等客户端控件容器/控件就绪后再开局
    retry_elapsed = retry_elapsed + (dt or 0)
    if retry_elapsed >= RETRY_INTERVAL then
      retry_elapsed = 0
      retry_tries = retry_tries + 1
      if retry_tries > RETRY_LIMIT then
        if printerr then
          printerr("[murdoku] 等不到客户端控件，放弃自动开局（检查客户端控件容器是否【激活且可见】）")
        end
        started = true      -- 停止重试，避免刷屏
      else
        local self = Murdoku.on_start(nil, { adapter = adapter, restore_save = true })
        if self then
          started = true
          if print then print("[murdoku] started (retry " .. retry_tries .. ")") end
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
  Murdoku.on_destroy()
  if print then print("[murdoku] destroyed") end
end


--[[----------------------------------------------------------------------------
  hello_probe.lua —— 「存活探针」，被追加在打包产物 dist/client_script.lua 的**末尾**。

  为什么放在末尾：
    它要包装 bundle 里 entry_client_script.lua 已经定义好的 OnInit / OnStart / ...，
    所以必须在它们**之后**执行。

  它回答三个问题：
    Q1 整份脚本有没有被编译并执行到底？   → `[probe] chunk executed to end`
    Q2 生命周期回调有没有被引擎调用？     → `[probe] OnInit called` / `OnStart called`
    Q3 运行时到底有哪些客户端控件？       → 控件树 dump（名字+id）

  ★ 双通道日志：关键行同时用 print（普通级）和 printerr（错误级）写。
    官方文档 157/160 行：print → 普通级别日志，printerr → 错误级别日志。
    如果【日志】窗口只显示错误级别，普通级的 print 会被过滤掉 —— 双写可以排除这个变量。

  ★ 肉眼可见的存活证明（完全不依赖日志）：
    找到 cell.1.1 / board / script.object，把它们放大、移位、改文字。
    试玩时看到按钮变大 / 位置跳到左上 / 文字变成 PROBE-OK，就说明脚本活着。
    OnInit 没触发时也会在前 600 帧里反复重试，所以控件晚出现也能补上。
--]]--

do
  local ok_install, install_err = pcall(function()

    local function emit(level, s)
      local line = "[probe] " .. tostring(s)
      if level == "err" then
        if printerr then printerr(line) end
        if print then print(line) end          -- 双写，保证至少有一条能过过滤
      else
        if print then print(line) end
      end
    end

    local function P(s)  emit("info", s) end
    local function PE(s) emit("err",  s) end   -- 关键里程碑：双通道

    -- ---------- Q1：整份 chunk 执行到底了 ----------
    PE("chunk executed to end")
    P("_VERSION=" .. tostring(_VERSION)
      .. "  os.time=" .. tostring(os and os.time and os.time())
      .. "  game=" .. tostring(game ~= nil)
      .. "  script=" .. tostring(script ~= nil)
      .. "  print=" .. tostring(print ~= nil)
      .. "  printerr=" .. tostring(printerr ~= nil))

    local LIFECYCLE = {
      "OnInit", "OnStart", "OnEnable", "OnDisable",
      "OnUpdate", "OnLevelUpdate", "OnDestroy",
    }

    local env = _ENV or _G

    do
      local have = {}
      for i = 1, #LIFECYCLE do
        if type(env[LIFECYCLE[i]]) == "function" then have[#have + 1] = LIFECYCLE[i] end
      end
      PE("lifecycle defined by bundle: " .. table.concat(have, ", "))
    end

    -- ---------- 控件查找（不依赖 script.object）----------
    local function get_roots()
      if not (game and game.GetClientUIRoots) then return nil end
      local ok, r = pcall(game.GetClientUIRoots)
      if ok and type(r) == "table" then return r end
      return nil
    end

    local function find_in(ctrl, name, depth)
      if ctrl == nil or depth > 16 then return nil end
      local ok, cname = pcall(function() return ctrl.name end)
      if ok and cname == name then return ctrl end
      local kids
      pcall(function() kids = ctrl:GetChildren() end)
      if type(kids) == "table" then
        for i = 1, #kids do
          local hit = find_in(kids[i], name, depth + 1)
          if hit then return hit end
        end
      end
      return nil
    end

    local function find_ctrl(name)
      local r = get_roots()
      if not r then return nil end
      for i = 1, #r do
        local hit = find_in(r[i], name, 0)
        if hit then return hit end
      end
      return nil
    end

    -- ---------- Q3：控件树 dump ----------
    local function dump_tree()
      local roots = get_roots()
      if not roots then P("game.GetClientUIRoots unavailable"); return end
      local n = 0
      for _ = 1, #roots do n = n + 1 end
      P("GetClientUIRoots -> " .. n .. " root(s)")

      local budget = 80
      local function walk(c, depth)
        if c == nil or depth > 3 or budget <= 0 then return end
        budget = budget - 1
        local name, id, vis = "?", "?", "?"
        pcall(function() name = tostring(c.name) end)
        pcall(function() id = tostring(c.id) end)
        pcall(function() vis = tostring(c.visible) .. "/" .. tostring(c.active) end)
        P(string.rep("  ", depth) .. "- name=" .. name .. " id=" .. id .. " vis/act=" .. vis)
        local kids
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do walk(kids[i], depth + 1) end
        end
      end
      for i = 1, #roots do walk(roots[i], 1) end
      if budget <= 0 then P("(tree dump truncated)") end

      if game.PrintClientUITree then
        P("calling game.PrintClientUITree()")
        pcall(game.PrintClientUITree)
      end
    end

    -- ---------- ★ 肉眼可见的存活证明 ----------
    local proved = false
    local function visible_proof(loud)
      local targets = {}
      local c
      c = find_ctrl("cell.1.1");  if c then targets[#targets + 1] = { "cell.1.1", c } end
      c = find_ctrl("board");     if c then targets[#targets + 1] = { "board", c } end
      if script and script.object then
        targets[#targets + 1] = { "script.object", script.object }
      end
      if #targets == 0 then
        if loud then P("visible proof: no target control found yet") end
        return false
      end

      for i = 1, #targets do
        local nm, t = targets[i][1], targets[i][2]
        local did = {}
        if pcall(function() t:SetSizeDelta(420, 420) end)    then did[#did + 1] = "size=420x420" end
        if pcall(function() t:SetAnchoredPosition(30, 120) end) then did[#did + 1] = "pos=(30,120)" end
        if pcall(function() t:SetLocalScale(1.6, 1.6, 1) end) then did[#did + 1] = "scale=1.6" end

        local ntext, nkids = 0, 0
        pcall(function() if t.text ~= nil then t.text = "PROBE-OK"; ntext = ntext + 1 end end)

        -- ★ 不依赖锚点、不依赖文本字段的硬证据：
        --   把每个子控件（例如 cell.1.1 下面那个图片控件）放大到 600x600 并挪到父控件正中。
        --   子控件的大小是它自己的属性，父控件怎么锚定都不影响 —— 那个图标会明显变巨大。
        pcall(function()
          local kids = t:GetChildren()
          if type(kids) == "table" then
            for k = 1, #kids do
              local kid = kids[k]
              nkids = nkids + 1
              pcall(function() kid:SetSizeDelta(600, 600) end)
              pcall(function() kid:SetAnchoredPosition(0, 0) end)
              pcall(function() kid:SetLocalScale(1.0, 1.0, 1) end)
              if kid.text ~= nil then kid.text = "PROBE-OK"; ntext = ntext + 1 end
            end
          end
        end)

        if ntext > 0 then did[#did + 1] = "text x" .. ntext end
        if nkids > 0 then did[#did + 1] = "children resized x" .. nkids end

        PE("VISIBLE PROOF on " .. nm .. ": " ..
           (#did > 0 and table.concat(did, ", ") or "NOTHING WORKED (no Set* / text field)"))
      end
      return true
    end

    -- 先静默试一次（此刻控件可能还没就绪）
    proved = visible_proof(false)
    if proved then PE("visible proof applied at chunk level") end

    -- ---------- Q2：包装生命周期 ----------
    local function get_fn(name)
      local ok, f = pcall(function() return env[name] end)
      if ok and type(f) == "function" then return f end
      return nil
    end

    local function set_fn(name, f)
      local ok = pcall(function() env[name] = f end)
      if not ok then P("cannot wrap " .. name .. " (env is read-only)") end
      return ok
    end

    local function wrap(name, body)
      local orig = get_fn(name)
      set_fn(name, function(...)
        PE(name .. " called")
        if body then body() end
        if orig then return orig(...) end
      end)
    end

    wrap("OnInit", function()
      dump_tree()
      if visible_proof(true) then proved = true end
    end)
    wrap("OnStart")

    do
      local frames = 0
      local orig_update = get_fn("OnUpdate")
      set_fn("OnUpdate", function(dt)
        frames = frames + 1
        if frames == 1 then PE("OnUpdate first frame") end
        -- OnInit 没触发 / 控件晚出现：前 600 帧里持续尝试可见证明
        if not proved and frames % 20 == 0 and frames <= 600 then
          if visible_proof(true) then proved = true end
        end
        if frames == 300 then P("OnUpdate alive: 300 frames") end
        if orig_update then return orig_update(dt) end
      end)
    end

    wrap("OnEnable")
    wrap("OnDisable")
    wrap("OnDestroy")

    PE("probe armed")
  end)

  if not ok_install then
    local msg = "[probe] FAILED to install probe: " .. tostring(install_err)
    if printerr then printerr(msg) end
    if print then print(msg) end
  end
end
