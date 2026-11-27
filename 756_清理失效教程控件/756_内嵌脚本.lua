--[[----------------------------------------------------------------------------
  client_script.lua —— 千星奇域客户端脚本（单文件构建产物）
  由 tools/bundle_client_script.lua 生成，**不要手改**：改 lua/ 下的源文件后重新打包。
  运行环境：Lua 5.3（官方文档）；io.* / coroutine.* 不可用，os.* 只剩 time/date/clock/difftime。
----------------------------------------------------------------------------]]--

-- ==== 模块加载器（把多文件合并成一个文件后仍能互相引用）==== --
local SHOP_PRICE = {clue=3, position=6}
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
local M = {}
local function wall_key(kind, r, c)
  return kind .. ":" .. tostring(r) .. ":" .. tostring(c)
end
M.wall_key = wall_key
function M.build_walls(level, rows, cols)    
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
  local list = {}
  for id = 1, n do if out[id] then list[#list + 1] = out[id] end end
  return list
end
return M

end

__M["murdoku_core"] = function()
local M = {}
M.VERSION = "0.3.0"
M.ROLE_ALIASES = {
  ["@thief"]      = "thief",
  ["@accomplice"] = "accomplice",
  ["@victim"]     = "victim",
}
M.TIE_FORBID = "forbid"    
M.TIE_ALLOW  = "allow"     
M.CELL_EMPTY   = "empty"
M.CELL_FILLED  = "filled"
M.CELL_WRONG   = "wrong"     
M.CELL_HINT    = "hint"      
M.CELL_BLOCKED = "blocked"   
M.CELL_VICTIM  = "victim"    
M.STATUS_PLAYING  = "playing"
M.STATUS_FILLED   = "filled"     
M.STATUS_SOLVED   = "solved"     
M.STATUS_FAILED   = "failed"     
M.MODE_PLACE = "place"    
M.MODE_NOTE  = "note"     
M.MODE_X     = "x"        
M.MODE_ERASE = "eraser"   
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
local RoomMap = __require("room_map")
function M.build_walls(level, rows, cols)
  return RoomMap.build_walls(level, rows, cols)
end
function M.compute_rooms(rows, cols, wall_set)
  return RoomMap.compute_rooms(rows, cols, wall_set)
end
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
function M.compute_room_adjacency(rows, cols, room, door_set)
  local adj = {}
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
  function ctx.resolve(who)
    if type(who) ~= "string" then return who end
    local role = M.ROLE_ALIASES[who]
    if role then return roles[role] end
    return who
  end
  function ctx.pos(who) return core.pos[ctx.resolve(who)] end
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
  function ctx.is_room_corner(r, c)
    local up    = (r == 1) or core.wall_set[wall_key("h", r - 1, c)]
    local down  = (r == ctx.rows) or core.wall_set[wall_key("h", r, c)]
    local left  = (c == 1) or core.wall_set[wall_key("v", r, c - 1)]
    local right = (c == ctx.cols) or core.wall_set[wall_key("v", r, c)]
    return (up or down) and (left or right)
  end
  function ctx.is_border(r, c)
    return r == 1 or r == ctx.rows or c == 1 or c == ctx.cols
  end
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
  function ctx.is_water(r, c)
    for i = 1, #core.water do
      if core.water[i].r == r and core.water[i].c == c then return true end
    end
    return false
  end
  function ctx.room_is_empty(room_id)
    return ctx.count_in_room(room_id) == 0
  end
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
  function ctx.is_neighbor(a, b)
    if not a or not b then return false end
    return math.abs(a.r - b.r) + math.abs(a.c - b.c) == 1
  end
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
M.make_context = make_context
local function unregistered_text(ctx, clue)
  return "（未注册的线索类型：" .. tostring(clue.type) .. "）"
end
local function reg(type_name, def)
  def.type = type_name
  def.text = def.text or unregistered_text
  M.clues[type_name] = def
  return def
end
reg("all_of", {
  params = { "clauses" },
  validate = function(ctx, cl)
    if type(cl.clauses) ~= "table" or #cl.clauses == 0 then return false end
    for _, part in ipairs(cl.clauses) do
      local def = M.clues[part.type]
      if not def or not def.validate(ctx, part) then return false end
    end
    return true
  end,
  text = function(ctx, cl)
    local texts = {}
    for _, part in ipairs(cl.clauses or {}) do
      local def = M.clues[part.type]
      texts[#texts + 1] = def and def.text(ctx, part) or unregistered_text(ctx, part)
    end
    return table.concat(texts, "；")
  end,
})
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
  validate = function(ctx, cl)
    if cl.same_row == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
      return a ~= nil and b ~= nil and a.c < b.c end
    return ctx.is_left_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 左边（同一行）", ctx.name(cl.a), ctx.name(cl.b)) end,
})
reg("right_of", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    if cl.same_row == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
      return a ~= nil and b ~= nil and a.c > b.c end
    return ctx.is_left_of(ctx.pos(cl.b), ctx.pos(cl.a)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 右边（同一行）", ctx.name(cl.a), ctx.name(cl.b)) end,
})
reg("above", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if cl.same_column == false then return a ~= nil and b ~= nil and a.r < b.r end
    return ctx.is_above(a, b)
  end,
  text = function(ctx, cl)
    if cl.same_column == false then return string.format("%s 在 %s 的上方（不要求同列）", ctx.name(cl.a), ctx.name(cl.b)) end
    return string.format("%s 在 %s 北边（同一列）", ctx.name(cl.a), ctx.name(cl.b))
  end,
})
reg("below", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    if cl.same_column == false then local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
      return a ~= nil and b ~= nil and a.r > b.r end
    return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,
  text = function(ctx, cl) return string.format("%s 在 %s 南边（同一列）", ctx.name(cl.a), ctx.name(cl.b)) end,
})
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
reg("alone_in_room", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    return ctx.count_in_room(ctx.room_of(p.r, p.c)) == 1
  end,
  text = function(ctx, cl) return string.format("%s 独自待在一个房间", ctx.name(cl.who)) end,
})
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
  text = function(ctx, cl) return string.format(cl.object == "椅子" and "%s 坐在 %s 上" or "%s 站在 %s 上", ctx.name(cl.who), cl.object) end,
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
reg("with", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.same_room(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl) return string.format("%s 与 %s 在一起", ctx.name(cl.a), ctx.name(cl.b)) end,
})
reg("not_with", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    return a ~= nil and b ~= nil and not ctx.same_room(a, b)
  end,
  text = function(ctx, cl) return string.format("%s 与 %s 不在同一房间", ctx.name(cl.a), ctx.name(cl.b)) end,
})
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
reg("alone", {
  params = { "who" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    return ctx.count_in_room(ctx.room_of(p.r, p.c)) == 1
  end,
  text = function(ctx, cl) return string.format("%s 独自一人", ctx.name(cl.who)) end,
})
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
reg("nobody_on_object", {
  params = { "object" },
  validate = function(ctx, cl) return ctx.count_on_object(cl.object) == 0 end,
  text = function(ctx, cl) return string.format("%s 上没有人", cl.object) end,
})
reg("below_in_other_room", {
  params = { "a", "b" },
  validate = function(ctx, cl)
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    if a.r <= b.r then return false end
    return not ctx.same_room(a, b)
  end,
  text = function(ctx, cl)
    return string.format("%s 在 %s 下方的不同区域中", ctx.name(cl.a), ctx.name(cl.b))
  end,
})
reg("alone_and_below_in_other_room", {
  params = { "who", "a", "b" },
  validate = function(ctx, cl)
    local p = ctx.pos(cl.who)
    if not p then return false end
    if ctx.count_in_room(ctx.room_of(p.r, p.c)) ~= 1 then return false end
    local a, b = ctx.pos(cl.a), ctx.pos(cl.b)
    if not a or not b then return false end
    if a.r <= b.r then return false end
    return not ctx.same_room(a, b)
  end,
  text = function(ctx, cl)
    return string.format("%s 独自一人，且 %s 在 %s 下方的不同区域中",
      ctx.name(cl.who), ctx.name(cl.a), ctx.name(cl.b))
  end,
})
reg("in_front_of", {
  params = { "a", "b" },
  validate = function(ctx, cl) return ctx.is_front_of(ctx.pos(cl.a), ctx.pos(cl.b)) end,
  text = function(ctx, cl)
    return string.format("%s 与 %s 站在同一扇门的两侧", ctx.name(cl.a), ctx.name(cl.b))
  end,
})
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
function M.validate_level(level)
  local errors = {}
  local function err(fmt, ...) errors[#errors + 1] = string.format(fmt, ...) end
  if type(level) ~= "table" then return false, { "关卡不是一个 table" } end
  local rows, cols = resolve_size(level)
  if rows < 2 or cols < 2 then err("棋盘尺寸过小：%dx%d", rows, cols) end
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
  local v = level.victim
  if v ~= nil then
    if type(v) == "table" and v.id then
      if not ids[v.id] then err("victim.id = %s 不在 suspects 列表里", tostring(v.id)) end
    elseif as_pos(v) == nil then
      err("victim 格式不对（应为 {id=...} 或 {r=,c=}）")
    end
  end
  if level.murderer ~= nil and not ids[level.murderer] then
    err("murderer = %s 不在 suspects 列表里", tostring(level.murderer))
  end
  local blocked = level.blocked or {}
  for i = 1, #blocked do
    if as_pos(blocked[i]) == nil then err("blocked[%d] 坐标格式不对", i) end
  end
  local objects = level.objects or {}
  for name, cells in pairs(objects) do
    if type(cells) ~= "table" then
      err("objects.%s 不是 table", tostring(name))
    else
      local single = as_pos(cells)
      if single then
      else
        for i = 1, #cells do
          if as_pos(cells[i]) == nil then err("objects.%s[%d] 坐标格式不对", tostring(name), i) end
        end
      end
    end
  end
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
  local clue_list = level.clues or {}
  if #clue_list == 0 then
    local rows, cols = nil, nil
    if type(level.size) == "table" then rows, cols = level.size.rows, level.size.cols end
    rows = rows or level.rows
    cols = cols or level.cols
    if type(rows) == "number" and type(cols) == "number" then
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
  local g_list = level.general_clues or {}
  for i = 1, #g_list do
    local cl = g_list[i]
    if type(cl) ~= "table" or not cl.type then
      err("第 %d 条通用线索缺少 type", i)
    else
      local def = M.clues[cl.type]
      if not def then
        err("第 %d 条通用线索类型未注册：%s", i, tostring(cl.type))
      else
        for _, p in ipairs(def.params or {}) do
          if cl[p] == nil then err("第 %d 条通用线索(%s)缺少参数 %s", i, cl.type, p) end
        end
      end
    end
  end
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
  local meta = level.meta
  if type(meta) == "table" then
    if meta.false_clue ~= nil then
      local n = tonumber(meta.false_clue)
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
  self.blocked = {}
  for i = 1, #(level.blocked or {}) do
    local p = as_pos(level.blocked[i])
    if p then self.blocked[cell_key(p.r, p.c)] = true end
  end
  self.water = {}
  for i = 1, #(level.water or {}) do
    local p = as_pos(level.water[i])
    if p then self.water[#self.water + 1] = p end
  end
  self.door_set = M.build_doors(level, self.rows, self.cols)
  self.adjacency = M.compute_room_adjacency(self.rows, self.cols, self.room, self.door_set)
  self.roles = {}
  if type(level.roles) == "table" then
    self.roles.thief = level.roles.thief
    self.roles.accomplice = level.roles.accomplice
  end
  if self.victim_id then self.roles.victim = self.victim_id end
  self.meta = {
    false_clue = nil,
    announce = "unknown",
  }
  if type(level.meta) == "table" then
    self.meta.false_clue = level.meta.false_clue
    self.meta.announce = level.meta.announce or self.meta.announce
  end
  self.allowed_false = self.meta.false_clue and 1 or 0
  self.clues = level.clues
  if type(self.clues) ~= "table" or #self.clues == 0 then
    self.clues = {}
    local n = self:clue_slot_count()
    for i = 1, n do
      self.clues[i] = { slot = i }
    end
  end
  self.clue_slots = #self.clues
  self.general_clues = {}
  if type(level.general_clues) == "table" then
    for i = 1, #level.general_clues do
      local g = level.general_clues[i]
      if type(g) == "table" and g.type ~= nil then
        self.general_clues[#self.general_clues + 1] = g
      end
    end
  end
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
    if type(def) == "table" and def.occupiable == false then
      for i = 1, #list do
        self.blocked[cell_key(list[i].r, list[i].c)] = true
      end
    end
  end
  self.pieces = {}
  self.piece_by_id = {}
  self.names = {}
  local declared = level.suspects or level.pieces or {}
  for i = 1, #declared do
    local s = deep_copy(declared[i])
    s.index = i
    s.symbol = s.symbol or string.upper(string.sub(tostring(s.id), 1, 1))
    self.pieces[i] = s
    self.piece_by_id[s.id] = s
    self.names[s.id] = s.name or tostring(s.id)
  end
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
function Core:clue_slot_count()
  local rules = self:rules()
  local manhattan = (rules.one_per_row ~= false) and (rules.one_per_col ~= false)
  if manhattan then return math.min(self.rows, self.cols) end
  return self.rows * self.cols
end
function Core:is_blocked(r, c) return self.blocked[cell_key(r, c)] == true end
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
function Core:general_clue_results()
  local ctx = make_context(self)
  local list = self.general_clues or {}
  local out = {}
  for i = 1, #list do
    local cl = list[i]
    local def = cl.type and M.clues[cl.type] or nil
    out[i] = {
      index = i,
      type = cl.type,
      text = def and def.text(ctx, cl) or ("待填内容（通用线索 " .. tostring(i) .. "）"),
      satisfied = (def ~= nil) and (def.validate(ctx, cl) and true or false),
    }
  end
  return out
end
local function standable(self, r, c)
  if r == nil or c == nil then return false end
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false end
  return not self:is_blocked(r, c)
end
local function cells_sorted(set)
  local list = {}
  for k in pairs(set or {}) do
    local sr, sc = tostring(k):match("^(%d+):(%d+)$")
    if sr ~= nil then list[#list + 1] = { r = tonumber(sr), c = tonumber(sc) } end
  end
  table.sort(list, function(a, b)
    if a.r ~= b.r then return a.r < b.r end
    return a.c < b.c
  end)
  return list
end
local HINT_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function object_own_cells(self, name)
  local set = {}
  local cells = self.objects[name] or {}
  for i = 1, #cells do
    local p = cells[i]
    if standable(self, p.r, p.c) then set[cell_key(p.r, p.c)] = true end
  end
  return set
end
local function object_beside_cells(self, name)
  local set = {}
  local cells = self.objects[name] or {}
  for i = 1, #cells do
    local p = cells[i]
    local room = (self.room[p.r] ~= nil) and self.room[p.r][p.c] or nil
    for d = 1, #HINT_DIRS do
      local rr = p.r + HINT_DIRS[d][1]
      local cc = p.c + HINT_DIRS[d][2]
      if standable(self, rr, cc)
         and self.room[rr] ~= nil and self.room[rr][cc] == room then
        set[cell_key(rr, cc)] = true
      end
    end
  end
  return set
end
local function col_cells(self, col)
  local set = {}
  local c = tonumber(col)
  if c == nil then return set end
  for r = 1, self.rows do
    if standable(self, r, c) then set[cell_key(r, c)] = true end
  end
  return set
end
local function row_cells(self, row)
  local set = {}
  local r = tonumber(row)
  if r == nil then return set end
  for c = 1, self.cols do
    if standable(self, r, c) then set[cell_key(r, c)] = true end
  end
  return set
end
local function hint_for(self, cl)
  if type(cl) ~= "table" or cl.type == nil then return nil end
  local t = cl.type
  if t == "on_object" or t == "only_on_object" or t == "one_on_object"
     or t == "n_on_object" or t == "nobody_on_object" then
    return object_own_cells(self, cl.object), "该家具自己的格子"
  elseif t == "beside_object" or t == "only_beside" or t == "not_beside_object" then
    return object_beside_cells(self, cl.object), "该家具四邻、同区域、可站人的格"
  elseif t == "in_col" then
    return col_cells(self, cl.c), "第 " .. tostring(cl.c) .. " 列的可站格"
  elseif t == "in_row" then
    return row_cells(self, cl.r), "第 " .. tostring(cl.r) .. " 行的可站格"
  elseif t == "at" then
    local set = {}
    if standable(self, cl.r, cl.c) then set[cell_key(cl.r, cl.c)] = true end
    return set, "这一格本身"
  end
  return nil
end
local function hint_result(self, cl, index, kind)
  local set, rule = hint_for(self, cl)
  if set == nil then return nil end
  local list = cells_sorted(set)
  return {
    index = index,
    kind = kind,         
    type = cl.type,
    rule = rule,
    cells = list,        
    set = set,           
    count = #list,
  }
end
function Core:clue_hint(index)
  return hint_result(self, (self.clues or {})[index], index, "card")
end
function Core:clue_hint_general(index)
  return hint_result(self, (self.general_clues or {})[index], index, "general")
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
function Core:row_col_conflict(r, c, id)
  local rules = self:rules()
  if rules.one_per_row then
    for cc = 1, self.cols do
      if cc ~= c then
        local other = self.grid[r][cc]
        if other ~= nil and other ~= id then
          return {
            kind = "row", index = r, other = other,
            text = string.format("第%d行已经有%s了，同一行只能站一个人",
                                 r, self.names[other] or tostring(other)),
          }
        end
      end
    end
  end
  if rules.one_per_col then
    for rr = 1, self.rows do
      if rr ~= r then
        local other = self.grid[rr][c]
        if other ~= nil and other ~= id then
          return {
            kind = "col", index = c, other = other,
            text = string.format("第%d列已经有%s了，同一列只能站一个人",
                                 c, self.names[other] or tostring(other)),
          }
        end
      end
    end
  end
  return nil
end
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
local function push_history(self, action, counts)
  self.history[#self.history + 1] = action
  self.future = {}
end
local function copy_board_value(v)
  if type(v) ~= 'table' then return v end
  local out = {}; for k,item in pairs(v) do out[k]=copy_board_value(item) end
  return out
end
local function placement_snapshot(self)
  local snap={}
  for _,k in ipairs({'grid','pos','notes','placed','x_marks','hint_cells','row_count','col_count'}) do snap[k]=copy_board_value(self[k]) end
  return snap
end
local function exchange_placement(self,action)
  local previous=action.board_before
  action.board_before=placement_snapshot(self)
  for k,v in pairs(previous) do self[k]=v end
end
local function do_place(self, r, c, id, record, opts)
  opts = opts or {}
  if self.blocked[cell_key(r, c)] then return false, "这个格子站不了人" end
  local prev = self.grid[r][c]
  if prev == id and (opts.clear_notes == false or (self.placed and self.placed[id])) then return false, "这个人已经站在这里了" end
  local prior_formal = self.placed and self.placed[id] or false
  if prev then
    self.pos[prev] = nil
    if self.placed then self.placed[prev] = nil end
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
  local auto = { x = {}, notes = {}, x_notes = {} }
  local function auto_x(rr, cc)
    if self.grid[rr][cc] or self.x_marks[rr][cc] then return end
    self.x_marks[rr][cc] = true
    auto.x[#auto.x + 1] = { r = rr, c = cc }
    local cur = self.notes[rr][cc]
    if cur ~= nil and next(cur) ~= nil then
      local had = {}
      for k in pairs(cur) do had[k] = true end
      self.notes[rr][cc] = {}
      auto.x_notes[#auto.x_notes + 1] = { r = rr, c = cc, had = had }
    end
  end
  for cc = 1, self.cols do
    if cc ~= c then auto_x(r, cc) end
  end
  for rr = 1, self.rows do
    if rr ~= r then auto_x(rr, c) end
  end
  if opts.clear_notes ~= false then
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
    push_history(self, { kind = "place", r = r, c = c, id = id, prev = prev, auto = auto, formal = opts.clear_notes ~= false, prior_formal = prior_formal })
  end
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end
local function revert_auto(self, auto)
  if auto == nil then return false end
  for i = 1, #(auto.x or {}) do
    local a = auto.x[i]
    self.x_marks[a.r][a.c] = false
  end
  for i = 1, #(auto.x_notes or {}) do
    local e = auto.x_notes[i]
    if self.x_marks[e.r][e.c] == false then
      local restored = {}
      for k in pairs(e.had or {}) do restored[k] = true end
      self.notes[e.r][e.c] = restored
    end
  end
  return true
end
local function do_clear(self, r, c, record)
  local prev = self.grid[r][c]
  if not prev then return false end
  local before = record and placement_snapshot(self)
  local prior_formal = self.placed and self.placed[prev] or false
  self.grid[r][c] = nil
  self.pos[prev] = nil
  if self.placed then self.placed[prev] = nil end
  if self.history ~= nil then
    for i = #self.history, 1, -1 do
      local a = self.history[i]
      if a.kind == "place" and a.id == prev then
        revert_auto(self, a.auto)
        break
      end
    end
  end
  self.row_count[r] = self.row_count[r] - 1
  self.col_count[c] = self.col_count[c] - 1
  self.hint_cells[cell_key(r, c)] = nil
  if record then push_history(self, { kind = "clear", r = r, c = c, prev = prev, prior_formal = prior_formal, board_before = before }) end
  if self.status ~= M.STATUS_SOLVED then self.status = M.STATUS_PLAYING end
  return true
end
local function restore_auto_of(self, id)
  for i = #self.history, 1, -1 do
    local a = self.history[i]
    if a.kind == "place" and a.id == id then
      local au = a.auto
      if au then
        revert_auto(self, au)
      end
      return true
    end
  end
  return false
end
local function move_piece_if_needed(self, id, r, c)
  local old = self.pos[id]
  if old == nil or (old.r == r and old.c == c) then return false, nil end
  restore_auto_of(self, id)
  do_clear(self, old.r, old.c, false)
  return true, { r = old.r, c = old.c }
end
local function toggle_note(self, r, c, id)
  if not id then return false end
  if self.grid[r][c] then return false, "这格已经有人了" end
  if self.blocked[cell_key(r, c)] then
    return false, "这格是障碍物，站不了人，也不能打笔记"
  end
  if self.placed and self.placed[id] then
    return false, "这个人已正式放置，不能再打笔记"
  end
  local was_x = (self.x_marks[r][c] == true)
  if was_x then self.x_marks[r][c] = false end
  local cell = self.notes[r][c]
  if cell[id] then cell[id] = nil else cell[id] = true end
  push_history(self, {
    kind = "note", r = r, c = c, id = id,
    on = (cell[id] == true),         
    was_x = was_x,                   
  }, false)
  return true
end
function Core:tap_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then
    return false, "越界"
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
    return toggle_note(self, r, c, self.selected)
  end
  if self.grid[r][c] then
    return do_clear(self, r, c, true), nil
  end
  if not self.selected then
    return self:toggle_x(r, c), nil
  end
  return toggle_note(self, r, c, self.selected)
end
function Core:hold_cell(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false, "越界" end
  if self:is_blocked(r, c) then return false, "这个格子站不了人" end
  if not self.selected then return false, "先点一个头像" end
  local who = self.selected
  local was_formal = self.placed and self.placed[who] or false
  local conflict = self:row_col_conflict(r, c, who)
  if conflict then return false, conflict.text end
  local before = placement_snapshot(self)
  local _, move_from = move_piece_if_needed(self, who, r, c)
  local ok, why = do_place(self, r, c, who, true, { clear_notes = true })
  if ok then self.history[#self.history].board_before=before end
  if ok and move_from ~= nil and self.history[#self.history] ~= nil then
    self.history[#self.history].move_from = move_from
  end
  if ok then
    self.placed = self.placed or {}
    self.placed[who] = true
    self.history[#self.history].prior_formal = was_formal
    self.selected = nil
  end
  return ok, why
end
function Core:pre_place(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false, "越界" end
  if self:is_blocked(r, c) then return false, "这个格子站不了人" end
  if not self.selected then return false, "先点一个头像" end
  local was_formal = self.placed and self.placed[self.selected] or false
  local conflict = self:row_col_conflict(r, c, self.selected)
  if conflict then return false, conflict.text end
  local before = placement_snapshot(self)
  local _, move_from = move_piece_if_needed(self, self.selected, r, c)
  local ok, why = do_place(self, r, c, self.selected, true, { clear_notes = false })
  if ok then self.history[#self.history].board_before=before end
  if ok and move_from ~= nil and self.history[#self.history] ~= nil then
    self.history[#self.history].move_from = move_from
  end
  if ok then self.history[#self.history].prior_formal = was_formal end
  return ok, why
end
function Core:toggle_x(r, c)
  if r < 1 or r > self.rows or c < 1 or c > self.cols then return false end
  if self.grid[r][c] then return false end
  local on = not self.x_marks[r][c]
  self.x_marks[r][c] = on
  local prev_notes = nil
  if on then
    local cur = self.notes[r][c]
    if cur ~= nil and next(cur) ~= nil then
      prev_notes = {}
      for k in pairs(cur) do prev_notes[k] = true end
    end
    self.notes[r][c] = {}
  end
  push_history(self, { kind = "x", r = r, c = c, on = on, prev_notes = prev_notes }, false)
  return true
end
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
    push_history(self, { kind = "x", r = r, c = c, on = false })
    changed = true
  end
  return changed
end
function Core:tap_suspect(id) return self:select_suspect(id) end
function Core:score()
  local total = self:piece_count()
  local correct = 0
  for id, p in pairs(self.solution) do
    local cur = self.pos[id]
    if cur and cur.r == p.r and cur.c == p.c then correct = correct + 1 end
  end
  return correct, total
end
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
  local capacity = self.rows*self.cols
  if type(code) ~= 'string' or #code == 0 or #code > capacity*(#self.pieces+6) then return false,'分享码长度无效' end
  local ids, cells = {}, {}
  for _,p in ipairs(self.pieces) do ids[self:symbol_of(p.id)] = p.id end
  local i, used = 1, 0
  while i <= #code do
    local n = 0
    local first = i
    while code:sub(i,i):match('%d') do
      n = n*10 + tonumber(code:sub(i,i)); i=i+1
      if n > capacity-used then return false,'分享码超出棋盘' end
    end
    if i == first then n=1 end
    if n==0 or n>capacity-used then return false,'分享码计数无效' end
    local ch=code:sub(i,i); i=i+1
    local notes,id,x
    if ch=='X' then x=true
    elseif ch=='-' then
    elseif ids[ch] then id=ids[ch]
    else
      local body=ch
      if ch=='!' then
        local close=code:find('?',i,true)
        if not close then return false,'笔记缺损' end
        body=code:sub(i,close-1); i=close+1
      end
      if not body:match('^%l+$') then return false,'分享码符号无效' end
      notes={}
      for k=1,#body do
        local who=ids[body:sub(k,k):upper()]; if not who then return false,'笔记人物无效' end
        notes[#notes+1]=who
      end
    end
    for k=1,n do
      if ch~='-' then cells[#cells+1]={r=math.floor(used/self.cols)+1,c=used%self.cols+1,id=id,x=x,notes=notes} end
      used=used+1
    end
  end
  if used~=capacity then return false,'分享码格数不符' end
  return self:deserialize({cells=cells})
end
function Core:undo()
  local action = table.remove(self.history)
  if not action then return false end
  if action.board_before then
    exchange_placement(self,action)
  elseif action.kind == "place" then
    do_clear(self, action.r, action.c, false)
    if action.move_from then
      do_place(self, action.move_from.r, action.move_from.c, action.id, false)
    elseif action.prev then
      do_place(self, action.r, action.c, action.prev, false)
    end
    revert_auto(self, action.auto)
    if action.move_from or action.prev == action.id then self.placed[action.id] = action.prior_formal or nil end
  elseif action.kind == "clear" then
    do_place(self, action.r, action.c, action.prev, false)
    self.placed[action.prev] = action.prior_formal or nil
  elseif action.kind == "note" then
    local cell = self.notes[action.r][action.c]
    if action.on ~= nil then
      if action.on then cell[action.id] = nil else cell[action.id] = true end
    else
      if cell[action.id] then cell[action.id] = nil else cell[action.id] = true end
    end
    if action.was_x then self.x_marks[action.r][action.c] = true end
  elseif action.kind == "x" then
    local on = action.on
    if on == nil then
      self.x_marks[action.r][action.c] = not self.x_marks[action.r][action.c]    
    else
      self.x_marks[action.r][action.c] = not on
      if on then
        if action.prev_notes ~= nil then
          local restored = {}
          for k in pairs(action.prev_notes) do restored[k] = true end
          self.notes[action.r][action.c] = restored
        end
      else
        self.notes[action.r][action.c] = {}
      end
    end
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
  if action.board_before then
    exchange_placement(self,action)
  elseif action.kind == "place" then
    move_piece_if_needed(self, action.id, action.r, action.c)
    do_place(self, action.r, action.c, action.id, false, {clear_notes=action.formal ~= false})
    self.placed[action.id] = action.formal and true or nil
  elseif action.kind == "clear" then
    do_clear(self, action.r, action.c, false)
  elseif action.kind == "note" then
    local cell = self.notes[action.r][action.c]
    if action.on ~= nil then
      if action.on then cell[action.id] = true else cell[action.id] = nil end
    else
      if cell[action.id] then cell[action.id] = nil else cell[action.id] = true end
    end
    if action.was_x then
      self.x_marks[action.r][action.c] = false
    end
  elseif action.kind == "x" then
    local on = action.on
    if on == nil then
      self.x_marks[action.r][action.c] = not self.x_marks[action.r][action.c]
    else
      self.x_marks[action.r][action.c] = on
      if on then
        self.notes[action.r][action.c] = {}
      elseif action.prev_notes ~= nil then
        local restored = {}
        for k in pairs(action.prev_notes) do restored[k] = true end
        self.notes[action.r][action.c] = restored
      end
    end
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
  self.mode = mode         
  return true
end
function Core:answer_clue(index, general)
  local list=general and self.general_clues or self.clues
  local cl=list and list[index]
  if not cl or not cl.type or not M.clues[cl.type] then return nil end
  local answer=M.new(self.level)
  answer.clues=self.clues
  answer.general_clues=self.general_clues
  answer.roles=self.roles
  answer.pos={}; answer.grid={}; answer.row_count={}; answer.col_count={}
  for r=1,self.rows do answer.grid[r]={};answer.row_count[r]=0 end
  for c=1,self.cols do answer.col_count[c]=0 end
  for id,p in pairs(self.solution) do
    answer.pos[id]={r=p.r,c=p.c};answer.grid[p.r][p.c]=id
    answer.row_count[p.r]=answer.row_count[p.r]+1;answer.col_count[p.c]=answer.col_count[p.c]+1
  end
  return M.clues[cl.type].validate(make_context(answer,self.roles),cl) and true or false
end
function Core:preview_ticket_hint()
  local trial=setmetatable({},getmetatable(self))
  for k,v in pairs(self) do trial[k]=v end
  for k,v in pairs(placement_snapshot(self)) do trial[k]=v end
  trial.history={};for i,v in ipairs(self.history) do trial.history[i]=v end
  trial.redo_stack={}
  local ok,msg=trial:hint()
  if not ok then return nil,msg end
  return trial
end
function Core:hint()
  local id=self.selected
  if not id or not self.solution[id] then return false,"请先选中一张人物卡" end
  local p=self.solution[id]
  if self:is_blocked(p.r,p.c) then return false,"该人物位置不可揭示" end
  local cur=self.pos[id]
  if cur and cur.r==p.r and cur.c==p.c and self.placed[id] then return false,"该人物已在正确位置" end
  local rules=self:rules()
  for r=1,self.rows do for c=1,self.cols do
    local who=self.grid[r][c]
    if who and who~=id and ((r==p.r and c==p.c) or (rules.one_per_row and r==p.r) or (rules.one_per_col and c==p.c)) then
      do_clear(self,r,c,true)
    end
  end end
  self.selected=id
  local ok,why=self:hold_cell(p.r,p.c)
  if not ok then return false,why end
  self.hint_cells[cell_key(p.r,p.c)]=true
  return true,string.format("提示：%s 在 第%d行第%d列",self.names[id] or id,p.r,p.c)
end
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
  local ok = (#violations == 0) and (not place_all or #missing == 0)
  local result = {
    ok = ok,
    solved = false,
    violations = violations,
    missing = missing,
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
function Core:accuse(id)
  local roles = self.roles or {}
  return self:accuse_verdict(id, roles.accomplice ~= nil, roles.accomplice)
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
local function nonnegative(n)
  return type(n)=='number' and n>=0 and n<math.huge
end
local function array_length(t,limit)
  if type(t)~='table' then return nil end
  local n=0
  for k in pairs(t) do
    if not nonnegative(k) or k<1 or k>limit or k%1~=0 then return nil end
    n=n+1
  end
  for k=1,n do if t[k]==nil then return nil end end
  return n
end
function Core:deserialize(save)
  if type(save)~='table' or (save.level_id~=nil and save.level_id~=self.level.id) then return false,'关卡不符' end
  local count=array_length(save.cells,self.rows*self.cols)
  if not count or not nonnegative(save.elapsed or 0) or not nonnegative(save.failed_accusations or 0) then return false,'存档格式无效' end
  local tmp=setmetatable({rows=self.rows,cols=self.cols},Core); tmp:reset()
  local seen={}
  for i=1,count do
    local e=save.cells[i]; if type(e)~='table' then return false,'格子无效' end
    local r,c=e.r,e.c
    if not nonnegative(r) or not nonnegative(c) or r%1~=0 or c%1~=0 or r<1 or c<1 or r>self.rows or c>self.cols then return false,'坐标无效' end
    local key=cell_key(r,c); if seen[key] then return false,'格子重复' end; seen[key]=true
    local n=array_length(e.notes or {},#self.pieces)
    if not n or (e.x~=nil and type(e.x)~='boolean') then return false,'标记无效' end
    if e.id~=nil then
      if not self.piece_by_id[e.id] or tmp.pos[e.id] or self.blocked[key] or e.x or n>0 then return false,'人物落点无效' end
      tmp.grid[r][c]=e.id; tmp.pos[e.id]={r=r,c=c}; tmp.row_count[r]=tmp.row_count[r]+1; tmp.col_count[c]=tmp.col_count[c]+1
    elseif e.x then
      if n>0 then return false,'标记冲突' end
      tmp.x_marks[r][c]=true
    else
      for j=1,n do
        local who=e.notes[j]; if self.blocked[key] or not self.piece_by_id[who] or tmp.notes[r][c][who] then return false,'笔记无效' end
        tmp.notes[r][c][who]=true
      end
    end
  end
  self:reset()
  for k,v in pairs(tmp) do self[k]=v end
  self.elapsed=save.elapsed or 0; self.failed_accusations=save.failed_accusations or 0; self.accused=save.accused
  if save.status==M.STATUS_SOLVED then self.status=M.STATUS_SOLVED end
  return true
end
function Core:restore_save(save)
  if type(save)~='table' or (save.level_id~=nil and save.level_id~=self.level.id) or not nonnegative(save.elapsed or 0) then return false,'存档无效' end
  if save.state_code==nil then return self:deserialize(save) end
  local ok,err=self:decode_state(save.state_code)
  if ok then self.elapsed=save.elapsed or 0 end
  return ok,err
end
function Core:set_elapsed(seconds) self.elapsed = seconds end
function Core:view()
  local wrong = {}
  if self.last_result then
    for _, w in ipairs(self.last_result.wrong_cells or {}) do wrong[cell_key(w.r, w.c)] = true end
  end
  local victim_pos = self.victim_fixed
  if self.victim_id then victim_pos = self.pos[self.victim_id] end
  -- 仅复用坐标键。墙、门、笔记和棋子仍从本次棋盘状态读取。
  local keys = self._view_keys720
  if not keys or keys.rows ~= self.rows or keys.cols ~= self.cols then
    keys = { rows = self.rows, cols = self.cols }
    for r = 1, self.rows do
      keys[r] = {}
      for c = 1, self.cols do
        keys[r][c] = { cell = cell_key(r,c), up = wall_key("h",r-1,c),
          down = wall_key("h",r,c), left = wall_key("v",r,c-1), right = wall_key("v",r,c) }
      end
    end
    self._view_keys720 = keys
  end
  local ctx = make_context(self)
  local cells = {}
  for r = 1, self.rows do
    cells[r] = {}
    for c = 1, self.cols do
      local key = keys[r][c]
      local blocked = self.blocked[key.cell] == true
      local id = self.grid[r][c]
      local state = M.CELL_EMPTY
      if blocked then
        state = M.CELL_BLOCKED
      elseif id then
        state = M.CELL_FILLED
        if id == self.victim_id then state = M.CELL_VICTIM end
      end
      if wrong[key.cell] then state = M.CELL_WRONG end
      if self.hint_cells[key.cell] then state = M.CELL_HINT end
      cells[r][c] = {
        r = r, c = c,
        suspect = id,
        name = id and (self.names[id] or id) or nil,
        is_victim = (id ~= nil and id == self.victim_id) or false,
        notes = sorted_keys(self.notes[r][c]),
        x = self.x_marks[r][c] == true,
        occupiable = not blocked,
        state = state,
        room = self.room[r][c],
        object = ctx.object_at(r, c),
        walls = {
          up    = (r == 1) or self.wall_set[key.up] or false,
          down  = (r == self.rows) or self.wall_set[key.down] or false,
          left  = (c == 1) or self.wall_set[key.left] or false,
          right = (c == self.cols) or self.wall_set[key.right] or false,
        },
        doors = {
          up    = self.door_set[key.up] or false,
          down  = self.door_set[key.down] or false,
          left  = self.door_set[key.left] or false,
          right = self.door_set[key.right] or false,
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
    local cl = (self.clues or {})[i] or {}
    clue_view[i] = {
      index = i,
      type = cl.type,
      text = clues[i].text,
      satisfied = clues[i].satisfied,
        who = cl.who,
      raw = cl,
    }
  end
  local general_view = self:general_clue_results()
  local structure = {
    ok = true,
    errors = {},
    victim_room = nil,
    adjacent = nil,
    innocent_counts = nil,
    best = nil,
    best_rooms = nil,
    k = nil,
    thief_room = nil,
    has_accomplice = (self.roles and self.roles.accomplice ~= nil) or false,
    must_have_accomplice = false,
  }
  local hud = {
    time = self.elapsed or 0,
    tie_policy = (self:rules().tie_policy or M.TIE_FORBID),
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
    object_defs = self.level.objects,
    cell_count = self.rows * self.cols,
    piece_count = self:piece_count(),
    victim_pos = victim_pos,
    murderer_hint_available = (self.level.murderer ~= nil),
    cells = cells,
    tray = tray,
    clues = clue_view,
    general_clues = general_view,
    violations = self:violations(),
    hud = hud,
    last_message = self.last_result and self.last_result.message or nil,
  }
end
return M

end

__M["furn_art"] = function()
local F = {}
F.MAX_LAYERS = 12
local C = {
  ink      = 0xFF1F1A14,
  ink_soft = 0xFF3A322A,
  table    = 0xFFAD9C67,    
  table_dk = 0xFF8C7F52,    
  table_hi = 0xFFEFE3A0,
  leg      = 0xFFA08F5C,    
  chair    = 0xFFFEF7E4,
  chair_dk = 0xFFE9D9B2,    
  chair_hi = 0xFFFBF2DA,    
  chair_ov = 0xFFFBD592,    
  chair_ln = 0xFFD9C08A,    
  shelf    = 0xFFD0B0D9,
  shelf_hi = 0xFFE4CBE9,    
  shelf_ln = 0xFFB49CC0,    
  book_a   = 0xFFB2DBEB,    
  book_b   = 0xFF9CCFE6,
  book_c   = 0xFFC7E7F2,
  pot      = 0xFFFCA161,
  pot_hi   = 0xFFFFB782,
  pot_dk   = 0xFFD97F3F,
  leaf     = 0xFF79CFA1,
  leaf_dk  = 0xFF5FB884,
  leaf_hi  = 0xFFA8E6C4,
  leaf_ink = 0xFF1E2A18,    
  stone    = 0xFFC9C9D2,
  stone_hi = 0xFFE2E2E8,
  stone_dk = 0xFF8E8E9A,
  stone_ink= 0xFF3E3E48,
  rug_rim  = 0xFFB89A62,
  rug_in   = 0xFFDCC684,
  rug_mid  = 0xFFC9B072,
  shadow   = 0x9A000000,    
}
local IMG = {
  rect   = 100001,    
  circle = 100002,    
  plate  = 100001,    
  round  = 107102,    
  soft   = 106056,    
}
F.ART = {
  table = {
    ["1"] = {
      { id = IMG.soft,  color = C.shadow,   w = 0.73, h = 0.96, dy =  0.22 },    
      { id = IMG.round, color = C.ink,      w = 0.730, h = 0.700, dy = -0.068 },  
      { id = IMG.round, color = C.table,    w = 0.680, h = 0.650, dy = -0.068 },  
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.028, dy =  0.272 },  
      { id = IMG.rect,  color = C.table_dk, w = 0.680, h = 0.055, dy =  0.309 },  
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.022, dy =  0.348 },  
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.235, dy = 0.375 },  
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.235, dy = 0.375 },  
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.235, dy = 0.375 },  
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.235, dy = 0.375 },  
    },
    ["h2"] = {
      { id = IMG.soft,  color = C.shadow,   w = 1.68, h = 1.10, dy =  0.26 },
      { id = IMG.round, color = C.ink,      w = 1.672, h = 0.700, dy = -0.068 },
      { id = IMG.round, color = C.table,    w = 1.622, h = 0.650, dy = -0.068 },
      { id = IMG.rect,  color = C.ink,      w = 1.622, h = 0.028, dy =  0.272 },
      { id = IMG.rect,  color = C.table_dk, w = 1.622, h = 0.055, dy =  0.309 },
      { id = IMG.rect,  color = C.ink,      w = 1.622, h = 0.022, dy =  0.348 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.600, dy = 0.375 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.600, dy = 0.375 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.600, dy = 0.375 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.600, dy = 0.375 },
    },
    ["v2"] = {
      { id = IMG.soft,  color = C.shadow,   w = 0.73, h = 1.76, dy =  0.22 },
      { id = IMG.round, color = C.ink,      w = 0.730, h = 1.672 },
      { id = IMG.round, color = C.table,    w = 0.680, h = 1.622 },
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.028, dy =  0.700 },
      { id = IMG.rect,  color = C.table_dk, w = 0.680, h = 0.055, dy =  0.737 },
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.022, dy =  0.776 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.235, dy = 0.800 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.235, dy = 0.800 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.235, dy = 0.800 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.235, dy = 0.800 },
    },
  },
  chair = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.74, h = 0.80, dy =  0.06 },    
      { id = IMG.round,  color = C.chair_ln, w = 0.66, h = 0.74, dy =  0.00 },    
      { id = IMG.round,  color = C.chair,    w = 0.60, h = 0.68, dy =  0.00 },    
      { id = IMG.circle, color = C.chair_dk, w = 0.42, h = 0.22, dy = -0.21 },    
      { id = IMG.round,  color = C.chair_ov, w = 0.46, h = 0.11, dy = -0.29 },    
      { id = IMG.round,  color = C.chair_hi, w = 0.38, h = 0.20, dy =  0.09 },    
      { id = IMG.round,  color = C.chair_dk, w = 0.48, h = 0.10, dy =  0.29 },    
      { id = IMG.round,  color = C.chair_dk, w = 0.10, h = 0.26, dx = -0.27, dy = 0.00 },  
      { id = IMG.round,  color = C.chair_dk, w = 0.10, h = 0.26, dx =  0.27, dy = 0.00 },  
    },
  },
  shelf = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.90, h = 0.50, dy =  0.42 },    
      { id = IMG.rect,   color = C.ink,      w = 0.92, h = 0.86 },                
      { id = IMG.rect,   color = C.shelf,    w = 0.82, h = 0.76, dy = -0.01 },    
      { id = IMG.rect,   color = C.shelf_hi, w = 0.80, h = 0.10, dy = -0.35 },    
      { id = IMG.rect,   color = C.ink,      w = 0.70, h = 0.56, dy = -0.01 },    
      { id = IMG.rect,   color = C.shelf_hi, w = 0.72, h = 0.06, dy = -0.06 },    
      { id = IMG.rect,   color = C.shelf_hi, w = 0.72, h = 0.06, dy =  0.24 },    
      { id = IMG.rect,   color = C.book_a,   w = 0.08, h = 0.20, dx = -0.26, dy = -0.20 },  
      { id = IMG.rect,   color = C.book_b,   w = 0.08, h = 0.15, dx = -0.16, dy = -0.18 },  
      { id = IMG.rect,   color = C.book_c,   w = 0.08, h = 0.18, dx = -0.06, dy = -0.19 },  
      { id = IMG.rect,   color = C.book_a,   w = 0.08, h = 0.14, dx = -0.22, dy =  0.06 },  
      { id = IMG.rect,   color = C.book_b,   w = 0.08, h = 0.17, dx = -0.12, dy =  0.05 },  
    },
  },
  plant = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.56, h = 0.56, dy =  0.24 },    
      { id = IMG.circle, color = C.leaf_ink, w = 0.34, h = 0.24, dy = -0.04 },    
      { id = IMG.circle, color = C.leaf_ink, w = 0.12, h = 0.34, dx = -0.20, dy = -0.10 },  
      { id = IMG.circle, color = C.leaf,     w = 0.08, h = 0.28, dx = -0.20, dy = -0.11 },  
      { id = IMG.circle, color = C.leaf_ink, w = 0.12, h = 0.34, dx =  0.20, dy = -0.10 },  
      { id = IMG.circle, color = C.leaf,     w = 0.08, h = 0.28, dx =  0.20, dy = -0.11 },  
      { id = IMG.circle, color = C.leaf_ink, w = 0.13, h = 0.40, dx = -0.04, dy = -0.14 },  
      { id = IMG.circle, color = C.leaf_hi,  w = 0.09, h = 0.32, dx = -0.04, dy = -0.15 },  
      { id = IMG.rect,   color = C.pot_hi,   w = 0.40, h = 0.09, dy =  0.17 },    
      { id = IMG.rect,   color = C.pot,      w = 0.32, h = 0.22, dy =  0.29 },    
    },
  },
  statue = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.62, h = 0.62, dy =  0.34 },    
      { id = IMG.rect,   color = C.stone_ink,w = 0.62, h = 0.14, dy =  0.42 },    
      { id = IMG.rect,   color = C.stone_dk,w = 0.56, h = 0.09, dy =  0.41 },     
      { id = IMG.rect,   color = C.stone_dk,w = 0.44, h = 0.09, dy =  0.30 },     
      { id = IMG.circle, color = C.stone,   w = 0.32, h = 0.44, dy =  0.03 },     
      { id = IMG.circle, color = C.stone_dk,w = 0.22, h = 0.36, dx =  0.05, dy = 0.04 },  
      { id = IMG.circle, color = C.stone,   w = 0.38, h = 0.20, dy = -0.06 },     
      { id = IMG.circle, color = C.stone_hi,w = 0.18, h = 0.16, dy = -0.23 },     
      { id = IMG.rect,   color = C.stone,   w = 0.12, h = 0.05, dy = -0.31 },     
      { id = IMG.rect,   color = C.stone_dk,w = 0.26, h = 0.10, dy =  0.18 },     
    },
  },
}
F.RUG_INSET = 0.12    
F.RUG_LINE  = 0.20    
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
local function slice_axis(a, b, i)
  local lo = math.max(a, i - 0.5)
  local hi = math.min(b, i + 0.5)
  if hi <= lo then return nil, nil end
  local w = hi - lo
  local center = (lo + hi) * 0.5
  return w, center - i
end
function F.rug_cell_els(bbox, r, c, cellset)
  local els = {}
  local function has(rr, cc) return cellset and cellset[rr] and cellset[rr][cc] end
  -- 与相邻地毯格共享的边「开放」，不内缩 ⇒ 内部不留格线；
  -- 其余边（含 L 形内凹的外围边）内缩 ⇒ 深色边框沿整块外围一圈。
  local openL, openR = has(r, c - 1), has(r, c + 1)
  local openU, openD = has(r - 1, c), has(r + 1, c)
  local function band(inset, color)
    local l  = c - 0.5 + (openL and 0 or inset)
    local rr = c + 0.5 - (openR and 0 or inset)
    local t  = r - 0.5 + (openU and 0 or inset)
    local b  = r + 0.5 - (openD and 0 or inset)
    return { id = IMG.rect, color = color,
             w = (rr - l) + 0.04, h = (b - t) + 0.04,
             dx = (l + rr) * 0.5 - c, dy = (t + b) * 0.5 - r }
  end
  els[#els + 1] = { id = IMG.rect, color = C.rug_rim, w = 1.0, h = 1.0 }
  els[#els + 1] = band(F.RUG_INSET, C.rug_in)
  els[#els + 1] = band(F.RUG_LINE, C.rug_mid)
  return els
end
local COMBINE = { table = true, carpet = true }
local function anchor_of(bbox)
  return { r = bbox.r2, c = bbox.c2 }
end
local function pick_label_cell(box, keys)
  for c = box.c1, box.c2 do
    if not (keys and keys[box.r2] and keys[box.r2][c]) then
      return { r = box.r2, c = c }
    end
  end
  for r = box.r2, box.r1, -1 do
    for c = box.c1, box.c2 do
      if not (keys and keys[r] and keys[r][c]) then
        return { r = r, c = c }
      end
    end
  end
  return { r = box.r2, c = box.c1 }
end
function F.variant(kind, span_r, span_c)
  local set = F.ART[kind]
  if type(set) ~= "table" then return nil, nil end
  if span_r > 1 and span_c > 1 then
    return set["h2"] or set["1"], "h2"
  elseif span_c > 1 then
    return set["h2"] or set["1"], "h2"
  elseif span_r > 1 then
    return set["v2"] or set["1"], "v2"
  end
  return set["1"], "1"
end
local function to_anchor(els, bbox, anchor)
  local out = {}
  local bcx = (bbox.c1 + bbox.c2) * 0.5
  local bcy = (bbox.r1 + bbox.r2) * 0.5
  for i = 1, #els do
    local e = els[i]
    out[#out + 1] = {
      id = e.id,
      color = e.color,
      w = e.w or 1,
      h = e.h or 1,
      dx = (bcx + (e.dx or 0)) - anchor.c,
      dy = (bcy + (e.dy or 0)) - anchor.r,
    }
  end
  return out
end
function F.layout(vm, keys, room_names)
  local res = { cell = {}, boxes = {}, labels = {} }
  if vm == nil or vm.cells == nil then return res end
  local rows, cols = vm.rows or 0, vm.cols or 0
  for r = 1, rows do
    res.cell[r] = {}
    for c = 1, cols do res.cell[r][c] = { els = false, anchor = false } end
  end
  local seen = {}
  local pieces = {}
  local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
  for r = 1, rows do
    for c = 1, cols do
      local key = keys and keys[r] and keys[r][c] or false
      if key and not seen[r .. ":" .. c] then
        local kind = key:match("^obj%.(.+)$") or key
        local group, r1, r2, c1, c2 = {}, r, r, c, c
        if COMBINE[kind] then
          local stack = { { r, c } }
          seen[r .. ":" .. c] = true
          while #stack > 0 do
            local p = table.remove(stack)
            group[#group + 1] = p
            if p[1] < r1 then r1 = p[1] end
            if p[1] > r2 then r2 = p[1] end
            if p[2] < c1 then c1 = p[2] end
            if p[2] > c2 then c2 = p[2] end
            for i = 1, #dirs do
              local nr, nc = p[1] + dirs[i][1], p[2] + dirs[i][2]
              if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
                and not seen[nr .. ":" .. nc]
                and keys and keys[nr] and keys[nr][nc] == key then
                seen[nr .. ":" .. nc] = true
                stack[#stack + 1] = { nr, nc }
              end
            end
          end
        else
          seen[r .. ":" .. c] = true
          group[1] = { r, c }
        end
        pieces[#pieces + 1] = {
          key = key, kind = kind, cells = group,
          box = { r1 = r1, r2 = r2, c1 = c1, c2 = c2 },
        }
      end
    end
  end
  local chosen = {}
  for _, p in ipairs(pieces) do
    local b = p.box
    local kind = p.kind
    local span_r, span_c = b.r2 - b.r1 + 1, b.c2 - b.c1 + 1
    if kind == "carpet" then
      local tri = nil
      if #p.cells == 3 and span_r == 2 and span_c == 2 then
        local has = {}
        for _, cell in ipairs(p.cells) do
          has[(cell[1] - b.r1) .. ":" .. (cell[2] - b.c1)] = true
        end
        if not has["1:1"] then tri = "L3a"           -- 缺右下：第3关
        elseif not has["1:0"] then tri = "L3b" end   -- 缺左下：第7关
      end
      -- 694：地毯只走整块模板（_spawn_whole_rug）。逐格手搭层全部关闭，
      -- 既避免与模板双绘，也不再出现「三张单格地毯拼接」的观感。
      res.pieces = res.pieces or {}
      res.pieces[#res.pieces + 1] = {
        kind = kind, box = b, anchor = anchor_of(b), variant = tri or "1",
        cells = p.cells, span_r = span_r, span_c = span_c,
      }
    else
      local els, variant = F.variant(kind, span_r, span_c)
      if els ~= nil then
        local anchor = anchor_of(b)
        local info = res.cell[anchor.r][anchor.c]
        info.els = to_anchor(els, b, anchor)
        info.anchor = (span_r > 1 or span_c > 1)
        chosen[#chosen + 1] = string.format("%s@%d,%d[%s]", kind, anchor.r, anchor.c, variant)
        res.pieces = res.pieces or {}
        res.pieces[#res.pieces + 1] = {
          kind = kind, box = b, anchor = anchor, variant = variant,
          cells = p.cells, span_r = span_r, span_c = span_c,
        }
      end
    end
  end
  res.chosen = chosen    
  for r = 1, rows do
    for c = 1, cols do
      local cd = vm.cells[r] and vm.cells[r][c]
      local room = cd and cd.room
      if type(room) == "number" then
        local box = res.boxes[room]
        if box == nil then
          box = { r1 = r, r2 = r, c1 = c, c2 = c, n = 0 }
          res.boxes[room] = box
        end
        if r < box.r1 then box.r1 = r end
        if r > box.r2 then box.r2 = r end
        if c < box.c1 then box.c1 = c end
        if c > box.c2 then box.c2 = c end
        box.n = box.n + 1
      end
    end
  end
  local rooms = {}
  for room in pairs(res.boxes) do rooms[#rooms + 1] = room end
  table.sort(rooms)
  for _, room in ipairs(rooms) do
    local box = res.boxes[room]
    local name = nil
    if type(room_names) == "table" then name = room_names[room] end
    if type(name) ~= "string" or name == "" then name = "区域 " .. tostring(room) end
    res.labels[#res.labels + 1] = {
      room = room, text = name, box = box,
      cell = pick_label_cell(box, keys),
    }
  end
  return res
end
return F

end

__M["furn_art_records"] = function()
return {
  chair = {
    ["1"] = {
      {100002,0.8400,0.8600,0.0000,0.0200,0.00,0xFFD9C08A},
      {100002,0.7600,0.7900,0.0000,0.0200,0.00,0xFFFEF7E4},
      {100002,0.2761,0.4435,0.0033,-0.1642,-87.42,0xC6E6E6D6},
      {100002,0.2594,0.3810,0.0028,0.1246,-261.05,0xE6E6E0D0},
      {100002,0.4994,0.0692,0.0155,0.3213,-178.98,0xB3E6E6DC},
      {100002,0.1054,0.3215,-0.3255,0.2431,-163.87,0xB1C4A56E},
      {100002,0.0902,0.3262,-0.3388,0.2633,-330.65,0xA0AE9464},
      {100002,0.2580,0.0970,-0.2428,0.0711,-89.64,0xA5E6E6E0},
      {100002,0.2208,0.0834,0.3160,0.2614,-289.09,0xBBA68C5E},
      {100002,0.0851,0.2251,-0.1706,-0.2976,-38.89,0xA8CFBC98},
      {100002,0.0894,0.1691,0.2535,0.1200,-0.65,0xD3E6E2D2},
      {100002,0.0737,0.2062,-0.3156,0.3080,-334.48,0xC7AF9466},
      {100002,0.1000,0.1438,0.1751,-0.1342,-187.58,0xCAE6DECD},
      {100002,0.1035,0.1361,0.1323,0.1895,-385.87,0xBBE6DFCE},
      {100002,0.0991,0.1035,-0.1610,-0.1119,-342.12,0xFFE5DECD},
      {100002,0.1943,0.0879,0.2584,0.0043,-282.89,0x99E6E6D5},
      {100002,0.1098,0.1531,0.0318,-0.2532,-88.68,0x97E6DFCE},
      {100002,0.1925,0.0917,0.0987,-0.0749,-10.48,0x8EE6DFCF},
      {100002,0.0561,0.1844,0.3234,0.2223,-355.62,0xECAF9466},
      {100002,0.1097,0.0905,0.1364,0.0433,31.32,0xEDE5DECD},
      {100002,0.2189,0.0622,0.0980,-0.3454,-22.12,0xA2E6E6DD},
      {100002,0.1310,0.0825,-0.2337,0.2869,-52.81,0xC2E6E6DA},
      {100002,0.0718,0.1820,0.1786,0.3182,-264.24,0x9EE6E2D0},
      {100002,0.3338,0.0612,0.0249,0.3863,-0.42,0x60C2A568},
      {100002,0.0719,0.1681,0.2088,-0.2909,-145.46,0x96E4CFA6},
      {100002,0.1323,0.0700,0.1601,-0.0768,-139.31,0xBEE6E3D3},
      {100002,0.1017,0.0880,-0.2459,0.1617,-228.45,0xC3E6DFCC},
      {100002,0.0622,0.1862,0.3000,0.3333,-45.92,0x96B59866},
      {100002,0.1925,0.0448,-0.3301,0.1636,-105.22,0xC5AE9260},
      {100002,0.0250,0.4290,-0.3043,0.1527,-181.16,0x9EAF9465},
      {100002,0.0916,0.1132,-0.2429,-0.0095,-11.16,0x9DE6E0CE},
      {100002,0.1318,0.0721,-0.0988,0.2222,0.91,0xA9E6DFCE},
      {100002,0.0677,0.0998,0.2476,0.2729,-36.42,0xE8E6E0D0},
      {100002,0.0855,0.1074,0.2548,0.0488,-149.07,0xA8E6DFCF},
      {100002,0.2162,0.0489,-0.0200,-0.3550,12.86,0x91E6E6DA},
      {100002,0.0743,0.0799,-0.1397,0.2178,-394.21,0xFDE5DECD},
      {100002,0.0762,0.0749,0.2580,0.1683,-71.96,0xFFE5DECD},
      {100002,0.0893,0.0653,-0.1381,-0.0623,-179.72,0xF3E6DFCE},
      {100002,0.0989,0.0779,-0.1363,0.0398,51.02,0xB8E6E3D3},
      {100002,0.2499,0.0425,-0.1853,0.3766,-177.02,0x84AF9464},
      {100002,0.0840,0.0970,0.1477,0.2120,-160.98,0xA8E6E6D7},
      {100002,0.0510,0.1570,-0.3158,0.1700,7.72,0xABAD9263},
      {100002,0.0494,0.1976,-0.1241,-0.3276,-56.82,0x82E6E6E6},
      {100002,0.0868,0.1041,-0.2002,0.3115,-274.20,0x8CE6E2D0},
      {100002,0.0607,0.0996,-0.0063,-0.3633,-105.12,0xCFE6DFCE},
      {100002,0.0866,0.1110,0.2549,-0.0106,-19.02,0x82E6E0D0},
      {100002,0.3037,0.0427,0.2745,-0.1474,-255.08,0x60201100},
      {100002,0.6289,0.0202,0.0082,0.4163,-181.40,0x605B3200},
      {100002,0.1103,0.1132,0.2615,-0.0072,-276.27,0x60E6E6D1},
      {100002,0.2374,0.0365,-0.2294,-0.1805,-274.55,0x85947139},
      {100002,0.1356,0.0562,0.2231,0.2888,-296.75,0x91E6DECE},
      {100002,0.0300,0.2423,-0.0010,0.2730,-270.30,0x979B783B},
      {100002,0.0430,0.1282,0.2507,0.3623,-246.93,0xC2AF9465},
      {100002,0.0199,0.3462,-0.1875,0.1221,-359.69,0x92A4834C},
      {100002,0.2373,0.0298,-0.3077,0.1116,-95.31,0x8AAA9060},
      {100002,0.0625,0.0990,-0.2102,0.3769,-282.21,0x9CB09462},
      {100002,0.0579,0.0644,0.2448,-0.0369,-71.79,0xFFE5DDCC},
      {100002,0.2122,0.0292,0.2119,0.2412,-154.71,0x96AF9361},
      {100002,0.0236,0.3525,0.0224,-0.0141,-89.86,0x6F885C13},
      {100002,0.0620,0.1043,0.0679,-0.3589,-262.76,0x8FE6DFCE},
      {100002,0.0674,0.0552,-0.2594,-0.0330,-397.32,0xF1E5DECD},
      {100002,0.1693,0.0418,-0.2263,-0.1441,-88.13,0x75B19869},
      {100002,0.0422,0.1606,0.2427,-0.1302,-175.79,0x74997539},
      {100002,0.1700,0.0326,0.3231,0.1081,-80.97,0x888D7142},
      {100002,0.0850,0.0574,0.2500,0.2704,-74.18,0x97E6E2D2},
      {100002,0.0301,0.1828,0.2427,-0.1637,-176.92,0x81AF9362},
      {100002,0.0488,0.0605,-0.2317,-0.0358,-247.55,0xEEE6DFCD},
      {100002,0.0451,0.1107,-0.1347,-0.3191,-253.93,0x8BE6E6D4},
      {100002,0.0639,0.0797,0.2953,0.3364,-74.64,0x87AF9466},
      {100002,0.0389,0.1062,0.1939,0.3733,-89.67,0xA2AE905C},
      {100002,0.0429,0.1134,0.1891,-0.2954,-320.47,0x87E6E3D6},
      {100002,0.0742,0.0518,-0.2277,0.2650,-59.26,0xA9E6DFCD},
      {100002,0.0962,0.0695,0.1182,-0.3609,-227.28,0x60E6E0C2},
      {100002,0.1450,0.0300,-0.2307,-0.2127,-96.92,0x93B59A69},
      {100002,0.0328,0.1176,-0.1054,-0.2620,-56.84,0xA5E6DFCF},
      {100002,0.1950,0.0268,0.2927,0.2166,-176.98,0x79AD9260},
      {100002,0.0459,0.1162,-0.2832,-0.0439,-202.30,0x75C4AB7D},
      {100002,0.0262,0.1999,0.0582,-0.3118,-278.10,0x77A07D41},
      {100002,0.1550,0.0236,-0.2626,0.2152,-188.60,0xA8A68A57},
      {100002,0.1958,0.0214,-0.0276,-0.4030,-349.40,0x86B09460},
      {100002,0.1524,0.0272,0.1996,0.0215,-90.51,0x859C783B},
      {100002,0.1202,0.0334,0.0891,0.2399,3.93,0x87E6E6DC},
      {100002,0.1329,0.0400,-0.2658,-0.1297,-103.21,0x60000000},
      {100002,0.1310,0.0259,0.2058,-0.0534,-125.84,0x95A68650},
      {100002,0.0909,0.0303,-0.1835,-0.2745,-315.51,0xB0E6E6D5},
      {100002,0.0873,0.0354,0.2539,0.2613,-324.75,0x9BE6DECD},
      {100002,0.0279,0.1555,-0.2090,-0.0673,-143.54,0x6E8B6830},
      {100002,0.0294,0.1129,0.1718,-0.2953,-292.80,0x8BE6E6DF},
      {100002,0.1777,0.0269,0.2012,0.1839,-88.89,0x60804E00},
      {100002,0.0737,0.0393,0.2361,-0.2079,-61.10,0x9CB49661},
      {100002,0.0426,0.0470,0.3186,0.1114,-13.60,0xDEB19768},
      {100002,0.0727,0.0530,-0.1964,0.2249,-77.64,0x739A7536},
      {100002,0.1021,0.0243,0.2767,-0.0754,-39.08,0xAEAD8E57},
      {100002,0.0409,0.1096,0.2784,-0.1332,-169.76,0x60000000},
      {100002,0.0173,0.1729,0.1985,0.1908,-186.78,0x90AE9363},
      {100002,0.0322,0.0994,-0.2416,-0.0933,-227.93,0x86B59966},
      {100002,0.1272,0.0170,-0.1303,-0.0172,-533.29,0xC5B09567},
      {100002,0.0241,0.1636,-0.0802,-0.3001,-68.90,0x6C956F2F},
      {100002,0.1235,0.0208,-0.2468,0.3492,-220.29,0xA4AD9262},
      {100002,0.0248,0.1050,-0.1341,0.2692,-271.15,0xA1A3834C},
      {100002,0.1115,0.0249,0.2157,-0.3171,-44.02,0x90B29562},
      {100002,0.0791,0.0210,0.2236,0.2100,-22.56,0xD9AF9464},
      {100002,0.0201,0.1333,-0.1564,0.2921,-272.49,0x85E6E6DA},
      {100002,0.1345,0.0177,0.1470,-0.2816,-213.08,0x95A68853},
      {100002,0.0192,0.1285,0.1429,0.2706,-78.41,0x8FAD9161},
      {100002,0.0218,0.1144,-0.1057,0.2710,-263.63,0x8DAD9262},
      {100002,0.1361,0.0214,0.1971,0.1054,-270.72,0x78A88B57},
      {100002,0.1131,0.0239,0.0905,-0.3965,-13.35,0x7FB89B68},
      {100002,0.0140,0.1787,-0.1839,0.0537,0.42,0x88AA8C5A},
      {100002,0.0347,0.0716,0.2522,-0.0855,-291.25,0x87AB8F5F},
      {100002,0.1179,0.0224,0.1952,-0.3421,-40.74,0x7EA38247},
      {100002,0.1131,0.0238,0.1359,0.2699,-184.87,0x789D7B41},
      {100002,0.1260,0.0202,-0.0097,-0.3184,-353.16,0x7FA68855},
      {100002,0.0197,0.0866,-0.0857,0.0083,-82.65,0xB1E6E4D4},
      {100002,0.0301,0.1042,-0.2584,-0.1342,-184.48,0x60000000},
      {100002,0.0291,0.0900,-0.1737,-0.3365,-231.39,0x72BDA475},
      {100002,0.0831,0.0278,-0.1491,-0.0144,-179.98,0x81A5854E},
      {100002,0.0215,0.0774,0.1728,-0.0205,-245.79,0xA7AE9363},
      {100002,0.0220,0.1008,0.1689,-0.3603,-122.42,0x7AB09463},
      {100002,0.1133,0.0174,-0.1750,-0.2498,-137.99,0x859C7B44},
      {100002,0.0186,0.1023,0.2538,-0.2284,-180.63,0x88BC9E65},
      {100002,0.0309,0.0378,0.2439,-0.2717,-367.43,0xD0AE9362},
      {100002,0.0901,0.0202,0.3053,-0.0355,-78.02,0x7EB89459},
      {100002,0.0257,0.0595,-0.1926,-0.3209,-39.75,0x94AF966A},
      {100002,0.0159,0.1245,-0.3059,0.0228,-190.39,0x66624516},
      {100002,0.0240,0.0673,-0.1890,-0.3241,-46.65,0x7BD3AF70},
      {100002,0.1119,0.0152,0.1203,0.4077,-356.25,0x71BCA06B},
      {100002,0.0307,0.0629,-0.2684,-0.1094,-221.15,0x60000000},
      {100002,0.0138,0.0825,0.2076,-0.2351,-126.80,0x7DA0814B},
      {100002,0.0138,0.0701,-0.2695,-0.0822,-57.39,0x81BB9D67},
      {100002,0.0893,0.0145,0.0955,-0.4180,-208.41,0x60000000},
      {100002,0.0289,0.0384,0.0971,-0.4072,-118.10,0x663C2500},
      {100002,0.0403,0.0167,0.0003,-0.4180,-280.04,0x84957742},
      {100002,0.0339,0.0167,-0.0398,-0.4180,-62.34,0x605C3600},
    },
  },
  table = {
    ["1"] = {
      {100001,0.6800,0.6500,0.0000,-0.0700,0.00,0xFFAD9C67},
      {100002,0.1559,0.1594,-0.2511,-0.3133,-212.60,0xFBAD9C67},
      {100002,0.0889,0.3275,-0.1542,0.1292,-92.55,0xCCAE9D68},
      {100002,0.1833,0.1023,0.2373,0.1145,-202.29,0xF8AD9C67},
      {100002,0.2841,0.1058,0.1519,0.1178,-369.44,0x88B4A26B},
      {100002,0.2966,0.0678,-0.0410,0.3150,-189.17,0xAD7B6E49},
      {100002,0.1192,0.1180,-0.2696,0.1173,205.81,0xEEAE9D68},
      {100002,0.0829,0.2038,-0.2679,-0.1954,-388.92,0xAEAD9C67},
      {100002,0.0823,0.1471,0.2727,-0.2665,-147.13,0xF0AD9C67},
      {100002,0.1125,0.1072,0.1268,0.1202,-179.72,0xE9AD9C67},
      {100002,0.0608,0.1974,0.2934,0.0778,-174.29,0xDDB09F69},
      {100002,0.0469,0.3691,-0.0291,0.2246,-92.31,0x8DA1905F},
      {100002,0.0967,0.1599,0.2731,-0.0002,-378.71,0x95B09F69},
      {100002,0.0983,0.0957,0.2769,-0.1838,41.02,0xEEAD9C67},
      {100002,0.1515,0.1016,-0.2723,-0.2184,-423.84,0x91B3A26B},
      {100002,0.0822,0.1114,-0.2863,-0.3371,-374.23,0xF2AD9C67},
      {100002,0.1012,0.1044,0.2344,-0.3405,-36.10,0xCDAD9C67},
      {100002,0.1809,0.0721,0.1763,-0.3411,-26.26,0xA2AD9C67},
      {100002,0.1637,0.0912,0.2772,-0.3124,-256.90,0x8AC3B074},
      {100002,0.1526,0.0847,-0.2795,0.0343,-112.88,0x9CAD9C67},
      {100002,0.2648,0.0524,-0.1918,0.2231,-178.79,0x8782754E},
      {100002,0.0475,0.3058,0.1564,0.2233,-273.35,0x80897B52},
      {100002,0.0514,0.2442,0.3527,0.1864,-354.43,0x8B000000},
      {100002,0.3780,0.0316,-0.0020,0.2908,0.70,0x8D8A7C52},
      {100002,0.0766,0.1318,0.0644,0.1307,-67.39,0x9CAC9B66},
      {100002,0.1954,0.1397,0.2587,0.1559,-89.24,0x39FFEE9C},
      {100002,0.1128,0.0839,-0.2825,-0.0769,-55.91,0x94AC9B67},
      {100002,0.0219,0.4301,-0.0369,0.1862,-269.84,0x84000000},
      {100002,0.1417,0.0492,0.2980,0.0152,-259.68,0xB2AE9D67},
      {100002,0.0506,0.1558,-0.2565,0.2227,-270.04,0x93B09E69},
      {100002,0.1241,0.0632,-0.2077,0.1379,18.25,0x91AF9E68},
      {100002,0.1954,0.0420,0.2221,0.2227,-350.40,0x887B6F4A},
      {100002,0.1130,0.0514,0.2439,0.3405,-91.89,0xBB918256},
      {100002,0.0664,0.1021,0.2915,-0.0815,-163.87,0x95AE9D67},
      {100002,0.0974,0.0662,-0.1494,0.3150,-127.60,0x967F724C},
      {100002,0.1732,0.0419,0.2375,0.2216,-352.68,0x85A59362},
      {100002,0.0245,0.2650,-0.3181,0.2573,-101.80,0x92000000},
      {100002,0.2153,0.0320,-0.1061,0.2333,0.17,0x8980734C},
      {100002,0.2747,0.0217,0.1383,0.1860,-357.66,0x8D000000},
      {100002,0.0507,0.1046,-0.2401,0.3407,-359.04,0x9EA39261},
      {100002,0.0548,0.1081,-0.2816,0.1173,-56.27,0x8DAC9B66},
      {100002,0.3064,0.0213,0.2697,0.1844,-181.52,0x80000000},
      {100002,0.1388,0.0426,-0.3484,-0.3302,-87.12,0x8A010201},
      {100002,0.0962,0.0700,0.1545,0.3113,-293.48,0x79786C48},
      {100002,0.1570,0.0358,0.2442,0.1874,-2.47,0x91000000},
      {100002,0.2228,0.0297,-0.2776,0.3606,-269.42,0x77000000},
      {100002,0.0842,0.0525,-0.1597,0.3145,-75.64,0xAC7E724B},
      {100002,0.0456,0.1111,-0.2370,0.3374,16.39,0x9080734C},
      {100002,0.0945,0.0537,0.2970,-0.3471,-73.96,0x8AB09F69},
      {100002,0.0471,0.0907,-0.3132,0.3148,-168.96,0xA08B7D53},
      {100002,0.0335,0.1547,0.1149,0.2979,-256.87,0x827E724C},
      {100002,0.0308,0.1710,0.1047,0.1565,-265.05,0x7FB9A86E},
      {100002,0.1149,0.0429,0.2780,-0.3511,-147.96,0x84B1A06A},
      {100002,0.1102,0.0434,0.1356,0.3241,-211.46,0x88796C48},
      {100002,0.0774,0.0480,-0.2937,-0.3608,-212.78,0xAFB1A069},
      {100002,0.1379,0.0382,-0.3503,0.2509,-100.99,0x79000000},
      {100002,0.0268,0.1935,0.2040,0.2667,-273.03,0x7B000000},
      {100002,0.1542,0.0258,-0.2249,0.2629,-175.54,0x9F000000},
      {100002,0.0241,0.2357,0.0267,0.2105,-270.96,0x6F847750},
      {100002,0.0521,0.0799,-0.2392,0.3204,-193.92,0x977F724C},
      {100002,0.0251,0.1476,-0.2787,0.3345,-0.23,0xA9000000},
      {100002,0.0547,0.0941,-0.1747,-0.3613,-111.64,0x77B4A26B},
      {100002,0.1393,0.0284,-0.3123,0.0021,-264.53,0x98BFAD72},
      {100002,0.0444,0.0807,0.1652,0.3203,-155.84,0xA380734C},
      {100002,0.1971,0.0239,0.2836,0.3217,-93.00,0x79000000},
      {100002,0.1582,0.0268,0.2041,0.3494,-272.08,0x80000000},
      {100002,0.0422,0.0671,0.3230,0.3295,-196.90,0xB680734C},
      {100002,0.1583,0.0207,0.1348,0.1858,-364.59,0x9C000000},
      {100002,0.0877,0.0396,0.2456,0.3533,-63.11,0x8B85784F},
      {100002,0.0627,0.0365,-0.3002,0.1499,-145.01,0xD2B2A069},
      {100002,0.0240,0.1318,-0.2000,0.3212,-185.05,0x97000000},
      {100002,0.0749,0.0387,-0.2430,0.3569,-293.28,0x9680734C},
      {100002,0.2329,0.0172,-0.0827,0.2630,4.32,0x6B000000},
      {100002,0.1249,0.0228,0.2049,0.3404,-277.56,0x96000000},
      {100002,0.0246,0.1420,0.3311,0.1843,-270.21,0x78000000},
      {100002,0.1681,0.0212,0.3248,0.2611,-347.86,0x75000000},
      {100002,0.1322,0.0196,0.0515,0.1861,-186.59,0x9F000000},
      {100002,0.0462,0.0712,-0.3113,0.3315,-51.47,0x7DA39261},
      {100002,0.0242,0.1249,0.1352,0.3405,-280.21,0x877D704B},
      {100002,0.0447,0.0619,-0.3215,0.3029,-168.17,0x8F80734D},
      {100002,0.0225,0.1492,0.2821,0.3358,-2.98,0x75000000},
      {100002,0.1135,0.0312,0.2364,0.3984,-1.46,0x6E000000},
      {100002,0.0421,0.0383,-0.3214,0.3148,20.05,0xF07E714B},
      {100002,0.0447,0.0586,-0.3033,0.2223,-397.68,0x92857750},
      {100002,0.1134,0.0269,0.0569,0.2618,0.25,0x7C000000},
      {100002,0.0216,0.1290,0.2812,0.3335,-358.72,0x87000000},
      {100002,0.0709,0.0261,0.2056,0.3749,-276.45,0xC7000000},
      {100002,0.1110,0.0192,0.2892,-0.4007,-359.56,0xAC000000},
      {100002,0.1408,0.0166,-0.2039,-0.4000,-179.90,0x9C000000},
      {100002,0.0443,0.0340,0.3084,0.2275,-65.44,0xF27E714B},
      {100002,0.0846,0.0363,0.3202,0.3206,-246.23,0x75CCB87A},
      {100002,0.0234,0.0770,-0.3138,0.1384,-195.54,0xBEAB9A65},
      {100002,0.1046,0.0225,-0.0441,-0.3810,-177.24,0x8FB09F69},
      {100002,0.0306,0.0813,0.3128,0.3144,-185.99,0x7C81744D},
      {100002,0.0779,0.0298,-0.3119,0.3094,-115.03,0x8384764E},
      {100002,0.0207,0.1112,0.1868,0.2088,-265.20,0x84867851},
      {100002,0.0404,0.0554,0.3216,0.2957,-328.92,0x84857750},
      {100002,0.0717,0.0309,0.3436,0.2382,-77.27,0x85000000},
      {100002,0.0208,0.0820,0.2025,0.3128,-354.44,0xA8000000},
      {100002,0.0753,0.0238,-0.2526,0.4028,-355.63,0xA0000000},
      {100002,0.0926,0.0185,0.2750,0.1628,-172.86,0x94BDAA70},
      {100002,0.0790,0.0219,0.2423,0.4013,-183.29,0x8E000000},
      {100002,0.0557,0.0278,0.3039,0.2175,-143.45,0x9A7F724C},
      {100002,0.0891,0.0204,0.1359,0.2608,-8.97,0x82000000},
      {100002,0.0192,0.1000,-0.1969,0.3371,-2.30,0x79000000},
      {100002,0.0528,0.0329,0.2400,0.3698,39.12,0x84867850},
      {100002,0.0728,0.0179,-0.2519,0.2767,-182.63,0xAA000000},
      {100002,0.0216,0.0902,0.3266,0.3174,-344.18,0x717C6F4A},
      {100002,0.0239,0.0663,0.3281,0.3043,-198.88,0x8780734D},
      {100002,0.0188,0.1015,-0.3055,0.1888,-270.89,0x6F000000},
      {100002,0.0772,0.0195,0.3103,0.1354,-252.77,0x8BB2A16A},
      {100002,0.0947,0.0168,0.2629,0.3300,-267.72,0x80867850},
      {100002,0.0211,0.0646,-0.3274,0.2653,-93.66,0x87010103},
      {100002,0.0226,0.0454,-0.2091,0.4002,-96.37,0xAC030303},
      {100002,0.0425,0.0251,0.2572,0.3048,-288.28,0xA583764E},
      {100002,0.0394,0.0310,-0.1694,0.3413,-153.20,0x8D7F734C},
      {100002,0.0248,0.0593,0.3392,-0.3028,-19.09,0x75000000},
      {100002,0.0204,0.0494,0.2884,0.1857,-70.30,0xA4000000},
      {100002,0.0210,0.0568,0.2993,0.2382,-83.51,0x84BAA66E},
      {100002,0.0204,0.0501,0.2817,0.2874,32.57,0x89000000},
      {100002,0.0193,0.0560,-0.3055,0.2409,-268.11,0x787E724B},
      {100002,0.0274,0.0245,0.3082,0.3464,-285.36,0xC080734D},
      {100002,0.0423,0.0197,-0.3228,0.3476,-173.03,0x877E724C},
      {100002,0.0166,0.0273,-0.3348,0.2855,-353.18,0x8882754F},
    },
    ["h2"] = {
      {100001,1.3990,0.6500,0.0000,-0.0700,0.00,0xFFAD9C67},
      {100002,0.3208,0.1594,-0.5167,-0.3133,-212.60,0xFBAD9C67},
      {100002,0.1828,0.3275,-0.3173,0.1292,-92.55,0xCCAE9D68},
      {100002,0.3771,0.1023,0.4882,0.1145,-202.29,0xF8AD9C67},
      {100002,0.5845,0.1058,0.3125,0.1178,-369.44,0x88B4A26B},
      {100002,0.6102,0.0678,-0.0844,0.3150,-189.17,0xAD7B6E49},
      {100002,0.2452,0.1180,-0.5546,0.1173,205.81,0xEEAE9D68},
      {100002,0.1705,0.2038,-0.5513,-0.1954,-388.92,0xAEAD9C67},
      {100002,0.1693,0.1471,0.5610,-0.2665,-147.13,0xF0AD9C67},
      {100002,0.2314,0.1072,0.2609,0.1202,-179.72,0xE9AD9C67},
      {100002,0.1251,0.1974,0.6037,0.0778,-174.29,0xDDB09F69},
      {100002,0.0965,0.3691,-0.0598,0.2246,-92.31,0x8DA1905F},
      {100002,0.1989,0.1599,0.5619,-0.0002,-378.71,0x95B09F69},
      {100002,0.2023,0.0957,0.5697,-0.1838,41.02,0xEEAD9C67},
      {100002,0.3117,0.1016,-0.5602,-0.2184,-423.84,0x91B3A26B},
      {100002,0.1690,0.1114,-0.5891,-0.3371,-374.23,0xF2AD9C67},
      {100002,0.2081,0.1044,0.4822,-0.3405,-36.10,0xCDAD9C67},
      {100002,0.3721,0.0721,0.3627,-0.3411,-26.26,0xA2AD9C67},
      {100002,0.3369,0.0912,0.5703,-0.3124,-256.90,0x8AC3B074},
      {100002,0.3140,0.0847,-0.5751,0.0343,-112.88,0x9CAD9C67},
      {100002,0.5448,0.0524,-0.3947,0.2231,-178.79,0x8782754E},
      {100002,0.0977,0.3058,0.3217,0.2233,-273.35,0x80897B52},
      {100002,0.1059,0.2442,0.7256,0.1864,-354.43,0x8B000000},
      {100002,0.7777,0.0316,-0.0040,0.2908,0.70,0x8D8A7C52},
      {100002,0.1576,0.1318,0.1326,0.1307,-67.39,0x9CAC9B66},
      {100002,0.4020,0.1397,0.5323,0.1559,-89.24,0x39FFEE9C},
      {100002,0.2320,0.0839,-0.5813,-0.0769,-55.91,0x94AC9B67},
      {100002,0.0450,0.4301,-0.0760,0.1862,-269.84,0x84000000},
      {100002,0.2915,0.0492,0.6132,0.0152,-259.68,0xB2AE9D67},
      {100002,0.1041,0.1558,-0.5278,0.2227,-270.04,0x93B09E69},
      {100002,0.2553,0.0632,-0.4273,0.1379,18.25,0x91AF9E68},
      {100002,0.4021,0.0420,0.4569,0.2227,-350.40,0x887B6F4A},
      {100002,0.2324,0.0514,0.5018,0.3405,-91.89,0xBB918256},
      {100002,0.1366,0.1021,0.5997,-0.0815,-163.87,0x95AE9D67},
      {100002,0.2003,0.0662,-0.3074,0.3150,-127.60,0x967F724C},
      {100002,0.3564,0.0419,0.4887,0.2216,-352.68,0x85A59362},
      {100002,0.0503,0.2650,-0.6544,0.2573,-101.80,0x92000000},
      {100002,0.4430,0.0320,-0.2183,0.2333,0.17,0x8980734C},
      {100002,0.5653,0.0217,0.2846,0.1860,-357.66,0x8D000000},
      {100002,0.1044,0.1046,-0.4940,0.3407,-359.04,0x9EA39261},
      {100002,0.1128,0.1081,-0.5794,0.1173,-56.27,0x8DAC9B66},
      {100002,0.6304,0.0213,0.5548,0.1844,-181.52,0x80000000},
      {100002,0.2855,0.0426,-0.7168,-0.3302,-87.12,0x8A010201},
      {100002,0.1980,0.0700,0.3178,0.3113,-293.48,0x79786C48},
      {100002,0.3230,0.0358,0.5025,0.1874,-2.47,0x91000000},
      {100002,0.4583,0.0297,-0.5711,0.3606,-269.42,0x77000000},
      {100002,0.1733,0.0525,-0.3287,0.3145,-75.64,0xAC7E724B},
      {100002,0.0938,0.1111,-0.4877,0.3374,16.39,0x9080734C},
      {100002,0.1944,0.0537,0.6110,-0.3471,-73.96,0x8AB09F69},
      {100002,0.0968,0.0907,-0.6443,0.3148,-168.96,0xA08B7D53},
      {100002,0.0689,0.1547,0.2364,0.2979,-256.87,0x827E724C},
      {100002,0.0634,0.1710,0.2153,0.1565,-265.05,0x7FB9A86E},
      {100002,0.2364,0.0429,0.5719,-0.3511,-147.96,0x84B1A06A},
      {100002,0.2268,0.0434,0.2791,0.3241,-211.46,0x88796C48},
      {100002,0.1592,0.0480,-0.6043,-0.3608,-212.78,0xAFB1A069},
      {100002,0.2837,0.0382,-0.7208,0.2509,-100.99,0x79000000},
      {100002,0.0550,0.1935,0.4196,0.2667,-273.03,0x7B000000},
      {100002,0.3172,0.0258,-0.4628,0.2629,-175.54,0x9F000000},
      {100002,0.0496,0.2357,0.0549,0.2105,-270.96,0x6F847750},
      {100002,0.1071,0.0799,-0.4921,0.3204,-193.92,0x977F724C},
      {100002,0.0517,0.1476,-0.5733,0.3345,-0.23,0xA9000000},
      {100002,0.1126,0.0941,-0.3594,-0.3613,-111.64,0x77B4A26B},
      {100002,0.2867,0.0284,-0.6426,0.0021,-264.53,0x98BFAD72},
      {100002,0.0914,0.0807,0.3398,0.3203,-155.84,0xA380734C},
      {100002,0.4054,0.0239,0.5836,0.3217,-93.00,0x79000000},
      {100002,0.3255,0.0268,0.4199,0.3494,-272.08,0x80000000},
      {100002,0.0868,0.0671,0.6645,0.3295,-196.90,0xB680734C},
      {100002,0.3257,0.0207,0.2774,0.1858,-364.59,0x9C000000},
      {100002,0.1803,0.0396,0.5052,0.3533,-63.11,0x8B85784F},
      {100002,0.1289,0.0365,-0.6177,0.1499,-145.01,0xD2B2A069},
      {100002,0.0494,0.1318,-0.4115,0.3212,-185.05,0x97000000},
      {100002,0.1540,0.0387,-0.5001,0.3569,-293.28,0x9680734C},
      {100002,0.4791,0.0172,-0.1702,0.2630,4.32,0x6B000000},
      {100002,0.2569,0.0228,0.4215,0.3404,-277.56,0x96000000},
      {100002,0.0505,0.1420,0.6812,0.1843,-270.21,0x78000000},
      {100002,0.3459,0.0212,0.6683,0.2611,-347.86,0x75000000},
      {100002,0.2720,0.0196,0.1060,0.1861,-186.59,0x9F000000},
      {100002,0.0950,0.0712,-0.6406,0.3315,-51.47,0x7DA39261},
      {100002,0.0498,0.1249,0.2782,0.3405,-280.21,0x877D704B},
      {100002,0.0920,0.0619,-0.6616,0.3029,-168.17,0x8F80734D},
      {100002,0.0463,0.1492,0.5804,0.3358,-2.98,0x75000000},
      {100002,0.2336,0.0312,0.4863,0.3984,-1.46,0x6E000000},
      {100002,0.0866,0.0383,-0.6613,0.3148,20.05,0xF07E714B},
      {100002,0.0921,0.0586,-0.6240,0.2223,-397.68,0x92857750},
      {100002,0.2334,0.0269,0.1170,0.2618,0.25,0x7C000000},
      {100002,0.0445,0.1290,0.5785,0.3335,-358.72,0x87000000},
      {100002,0.1458,0.0261,0.4230,0.3749,-276.45,0xC7000000},
      {100002,0.2284,0.0192,0.5951,-0.4007,-359.56,0xAC000000},
      {100002,0.2897,0.0166,-0.4195,-0.4000,-179.90,0x9C000000},
      {100002,0.0911,0.0340,0.6346,0.2275,-65.44,0xF27E714B},
      {100002,0.1740,0.0363,0.6589,0.3206,-246.23,0x75CCB87A},
      {100002,0.0481,0.0770,-0.6457,0.1384,-195.54,0xBEAB9A65},
      {100002,0.2152,0.0225,-0.0907,-0.3810,-177.24,0x8FB09F69},
      {100002,0.0630,0.0813,0.6435,0.3144,-185.99,0x7C81744D},
      {100002,0.1603,0.0298,-0.6416,0.3094,-115.03,0x8384764E},
      {100002,0.0426,0.1112,0.3844,0.2088,-265.20,0x84867851},
      {100002,0.0830,0.0554,0.6617,0.2957,-328.92,0x84857750},
      {100002,0.1475,0.0309,0.7070,0.2382,-77.27,0x85000000},
      {100002,0.0429,0.0820,0.4167,0.3128,-354.44,0xA8000000},
      {100002,0.1548,0.0238,-0.5198,0.4028,-355.63,0xA0000000},
      {100002,0.1906,0.0185,0.5659,0.1628,-172.86,0x94BDAA70},
      {100002,0.1625,0.0219,0.4985,0.4013,-183.29,0x8E000000},
      {100002,0.1147,0.0278,0.6252,0.2175,-143.45,0x9A7F724C},
      {100002,0.1834,0.0204,0.2796,0.2608,-8.97,0x82000000},
      {100002,0.0396,0.1000,-0.4052,0.3371,-2.30,0x79000000},
      {100002,0.1086,0.0329,0.4938,0.3698,39.12,0x84867850},
      {100002,0.1497,0.0179,-0.5184,0.2767,-182.63,0xAA000000},
      {100002,0.0444,0.0902,0.6719,0.3174,-344.18,0x717C6F4A},
      {100002,0.0493,0.0663,0.6750,0.3043,-198.88,0x8780734D},
      {100002,0.0387,0.1015,-0.6285,0.1888,-270.89,0x6F000000},
      {100002,0.1589,0.0195,0.6384,0.1354,-252.77,0x8BB2A16A},
      {100002,0.1949,0.0168,0.5409,0.3300,-267.72,0x80867850},
      {100002,0.0435,0.0646,-0.6736,0.2653,-93.66,0x87010103},
      {100002,0.0465,0.0454,-0.4302,0.4002,-96.37,0xAC030303},
      {100002,0.0874,0.0251,0.5293,0.3048,-288.28,0xA583764E},
      {100002,0.0810,0.0310,-0.3485,0.3413,-153.20,0x8D7F734C},
      {100002,0.0510,0.0593,0.6978,-0.3028,-19.09,0x75000000},
      {100002,0.0419,0.0494,0.5934,0.1857,-70.30,0xA4000000},
      {100002,0.0433,0.0568,0.6158,0.2382,-83.51,0x84BAA66E},
      {100002,0.0419,0.0501,0.5796,0.2874,32.57,0x89000000},
      {100002,0.0397,0.0560,-0.6285,0.2409,-268.11,0x787E724B},
      {100002,0.0563,0.0245,0.6341,0.3464,-285.36,0xC080734D},
      {100002,0.0869,0.0197,-0.6642,0.3476,-173.03,0x877E724C},
      {100002,0.0342,0.0273,-0.6889,0.2855,-353.18,0x8882754F},
    },
    ["v2"] = {
      {100001,0.6800,1.3373,0.0000,-0.1440,0.00,0xFFAD9C67},
      {100002,0.1559,0.3279,-0.2511,-0.6446,-212.60,0xFBAD9C67},
      {100002,0.0889,0.6738,-0.1542,0.2658,-92.55,0xCCAE9D68},
      {100002,0.1833,0.2105,0.2373,0.2357,-202.29,0xF8AD9C67},
      {100002,0.2841,0.2176,0.1519,0.2424,-369.44,0x88B4A26B},
      {100002,0.2966,0.1394,-0.0410,0.6481,-189.17,0xAD7B6E49},
      {100002,0.1192,0.2428,-0.2696,0.2413,205.81,0xEEAE9D68},
      {100002,0.0829,0.4192,-0.2679,-0.4020,-388.92,0xAEAD9C67},
      {100002,0.0823,0.3027,0.2727,-0.5484,-147.13,0xF0AD9C67},
      {100002,0.1125,0.2205,0.1268,0.2472,-179.72,0xE9AD9C67},
      {100002,0.0608,0.4062,0.2934,0.1601,-174.29,0xDDB09F69},
      {100002,0.0469,0.7594,-0.0291,0.4621,-92.31,0x8DA1905F},
      {100002,0.0967,0.3291,0.2731,-0.0004,-378.71,0x95B09F69},
      {100002,0.0983,0.1969,0.2769,-0.3781,41.02,0xEEAD9C67},
      {100002,0.1515,0.2090,-0.2723,-0.4493,-423.84,0x91B3A26B},
      {100002,0.0822,0.2293,-0.2863,-0.6936,-374.23,0xF2AD9C67},
      {100002,0.1012,0.2148,0.2344,-0.7005,-36.10,0xCDAD9C67},
      {100002,0.1809,0.1482,0.1763,-0.7018,-26.26,0xA2AD9C67},
      {100002,0.1637,0.1877,0.2772,-0.6427,-256.90,0x8AC3B074},
      {100002,0.1526,0.1743,-0.2795,0.0707,-112.88,0x9CAD9C67},
      {100002,0.2648,0.1078,-0.1918,0.4590,-178.79,0x8782754E},
      {100002,0.0475,0.6292,0.1564,0.4595,-273.35,0x80897B52},
      {100002,0.0514,0.5025,0.3527,0.3835,-354.43,0x8B000000},
      {100002,0.3780,0.0651,-0.0020,0.5983,0.70,0x8D8A7C52},
      {100002,0.0766,0.2713,0.0644,0.2689,-67.39,0x9CAC9B66},
      {100002,0.1954,0.2875,0.2587,0.3209,-89.24,0x39FFEE9C},
      {100002,0.1128,0.1725,-0.2825,-0.1581,-55.91,0x94AC9B67},
      {100002,0.0219,0.8849,-0.0369,0.3832,-269.84,0x84000000},
      {100002,0.1417,0.1013,0.2980,0.0314,-259.68,0xB2AE9D67},
      {100002,0.0506,0.3205,-0.2565,0.4582,-270.04,0x93B09E69},
      {100002,0.1241,0.1301,-0.2077,0.2837,18.25,0x91AF9E68},
      {100002,0.1954,0.0864,0.2221,0.4581,-350.40,0x887B6F4A},
      {100002,0.1130,0.1057,0.2439,0.7005,-91.89,0xBB918256},
      {100002,0.0664,0.2100,0.2915,-0.1677,-163.87,0x95AE9D67},
      {100002,0.0974,0.1362,-0.1494,0.6480,-127.60,0x967F724C},
      {100002,0.1732,0.0861,0.2375,0.4559,-352.68,0x85A59362},
      {100002,0.0245,0.5452,-0.3181,0.5294,-101.80,0x92000000},
      {100002,0.2153,0.0659,-0.1061,0.4799,0.17,0x8980734C},
      {100002,0.2747,0.0446,0.1383,0.3827,-357.66,0x8D000000},
      {100002,0.0507,0.2151,-0.2401,0.7010,-359.04,0x9EA39261},
      {100002,0.0548,0.2223,-0.2816,0.2414,-56.27,0x8DAC9B66},
      {100002,0.3064,0.0438,0.2697,0.3795,-181.52,0x80000000},
      {100002,0.1388,0.0876,-0.3484,-0.6794,-87.12,0x8A010201},
      {100002,0.0962,0.1440,0.1545,0.6405,-293.48,0x79786C48},
      {100002,0.1570,0.0736,0.2442,0.3855,-2.47,0x91000000},
      {100002,0.2228,0.0612,-0.2776,0.7418,-269.42,0x77000000},
      {100002,0.0842,0.1079,-0.1597,0.6471,-75.64,0xAC7E724B},
      {100002,0.0456,0.2285,-0.2370,0.6941,16.39,0x9080734C},
      {100002,0.0945,0.1104,0.2970,-0.7141,-73.96,0x8AB09F69},
      {100002,0.0471,0.1867,-0.3132,0.6477,-168.96,0xA08B7D53},
      {100002,0.0335,0.3182,0.1149,0.6129,-256.87,0x827E724C},
      {100002,0.0308,0.3518,0.1047,0.3221,-265.05,0x7FB9A86E},
      {100002,0.1149,0.0883,0.2780,-0.7224,-147.96,0x84B1A06A},
      {100002,0.1102,0.0893,0.1356,0.6667,-211.46,0x88796C48},
      {100002,0.0774,0.0987,-0.2937,-0.7424,-212.78,0xAFB1A069},
      {100002,0.1379,0.0787,-0.3503,0.5162,-100.99,0x79000000},
      {100002,0.0268,0.3982,0.2040,0.5486,-273.03,0x7B000000},
      {100002,0.1542,0.0530,-0.2249,0.5409,-175.54,0x9F000000},
      {100002,0.0241,0.4849,0.0267,0.4330,-270.96,0x6F847750},
      {100002,0.0521,0.1643,-0.2392,0.6592,-193.92,0x977F724C},
      {100002,0.0251,0.3037,-0.2787,0.6883,-0.23,0xA9000000},
      {100002,0.0547,0.1936,-0.1747,-0.7433,-111.64,0x77B4A26B},
      {100002,0.1393,0.0584,-0.3123,0.0043,-264.53,0x98BFAD72},
      {100002,0.0444,0.1660,0.1652,0.6591,-155.84,0xA380734C},
      {100002,0.1971,0.0491,0.2836,0.6618,-93.00,0x79000000},
      {100002,0.1582,0.0550,0.2041,0.7188,-272.08,0x80000000},
      {100002,0.0422,0.1381,0.3230,0.6779,-196.90,0xB680734C},
      {100002,0.1583,0.0426,0.1348,0.3822,-364.59,0x9C000000},
      {100002,0.0877,0.0814,0.2456,0.7270,-63.11,0x8B85784F},
      {100002,0.0627,0.0752,-0.3002,0.3083,-145.01,0xD2B2A069},
      {100002,0.0240,0.2712,-0.2000,0.6608,-185.05,0x97000000},
      {100002,0.0749,0.0797,-0.2430,0.7342,-293.28,0x9680734C},
      {100002,0.2329,0.0354,-0.0827,0.5412,4.32,0x6B000000},
      {100002,0.1249,0.0469,0.2049,0.7003,-277.56,0x96000000},
      {100002,0.0246,0.2922,0.3311,0.3792,-270.21,0x78000000},
      {100002,0.1681,0.0436,0.3248,0.5372,-347.86,0x75000000},
      {100002,0.1322,0.0403,0.0515,0.3830,-186.59,0x9F000000},
      {100002,0.0462,0.1465,-0.3113,0.6820,-51.47,0x7DA39261},
      {100002,0.0242,0.2569,0.1352,0.7006,-280.21,0x877D704B},
      {100002,0.0447,0.1274,-0.3215,0.6232,-168.17,0x8F80734D},
      {100002,0.0225,0.3071,0.2821,0.6908,-2.98,0x75000000},
      {100002,0.1135,0.0641,0.2364,0.8197,-1.46,0x6E000000},
      {100002,0.0421,0.0789,-0.3214,0.6477,20.05,0xF07E714B},
      {100002,0.0447,0.1206,-0.3033,0.4573,-397.68,0x92857750},
      {100002,0.1134,0.0553,0.0569,0.5387,0.25,0x7C000000},
      {100002,0.0216,0.2655,0.2812,0.6861,-358.72,0x87000000},
      {100002,0.0709,0.0537,0.2056,0.7714,-276.45,0xC7000000},
      {100002,0.1110,0.0395,0.2892,-0.8244,-359.56,0xAC000000},
      {100002,0.1408,0.0342,-0.2039,-0.8229,-179.90,0x9C000000},
      {100002,0.0443,0.0701,0.3084,0.4681,-65.44,0xF27E714B},
      {100002,0.0846,0.0746,0.3202,0.6596,-246.23,0x75CCB87A},
      {100002,0.0234,0.1585,-0.3138,0.2848,-195.54,0xBEAB9A65},
      {100002,0.1046,0.0463,-0.0441,-0.7839,-177.24,0x8FB09F69},
      {100002,0.0306,0.1673,0.3128,0.6469,-185.99,0x7C81744D},
      {100002,0.0779,0.0613,-0.3119,0.6365,-115.03,0x8384764E},
      {100002,0.0207,0.2289,0.1868,0.4296,-265.20,0x84867851},
      {100002,0.0404,0.1141,0.3216,0.6084,-328.92,0x84857750},
      {100002,0.0717,0.0635,0.3436,0.4901,-77.27,0x85000000},
      {100002,0.0208,0.1688,0.2025,0.6436,-354.44,0xA8000000},
      {100002,0.0753,0.0490,-0.2526,0.8287,-355.63,0xA0000000},
      {100002,0.0926,0.0380,0.2750,0.3349,-172.86,0x94BDAA70},
      {100002,0.0790,0.0450,0.2423,0.8256,-183.29,0x8E000000},
      {100002,0.0557,0.0572,0.3039,0.4475,-143.45,0x9A7F724C},
      {100002,0.0891,0.0421,0.1359,0.5366,-8.97,0x82000000},
      {100002,0.0192,0.2058,-0.1969,0.6936,-2.30,0x79000000},
      {100002,0.0528,0.0677,0.2400,0.7608,39.12,0x84867850},
      {100002,0.0728,0.0368,-0.2519,0.5692,-182.63,0xAA000000},
      {100002,0.0216,0.1855,0.3266,0.6530,-344.18,0x717C6F4A},
      {100002,0.0239,0.1363,0.3281,0.6261,-198.88,0x8780734D},
      {100002,0.0188,0.2088,-0.3055,0.3884,-270.89,0x6F000000},
      {100002,0.0772,0.0401,0.3103,0.2786,-252.77,0x8BB2A16A},
      {100002,0.0947,0.0347,0.2629,0.6789,-267.72,0x80867850},
      {100002,0.0211,0.1329,-0.3274,0.5459,-93.66,0x87010103},
      {100002,0.0226,0.0934,-0.2091,0.8234,-96.37,0xAC030303},
      {100002,0.0425,0.0517,0.2572,0.6271,-288.28,0xA583764E},
      {100002,0.0394,0.0638,-0.1694,0.7021,-153.20,0x8D7F734C},
      {100002,0.0248,0.1220,0.3392,-0.6230,-19.09,0x75000000},
      {100002,0.0204,0.1017,0.2884,0.3821,-70.30,0xA4000000},
      {100002,0.0210,0.1169,0.2993,0.4900,-83.51,0x84BAA66E},
      {100002,0.0204,0.1031,0.2817,0.5914,32.57,0x89000000},
      {100002,0.0193,0.1153,-0.3055,0.4956,-268.11,0x787E724B},
      {100002,0.0274,0.0504,0.3082,0.7126,-285.36,0xC080734D},
      {100002,0.0423,0.0405,-0.3228,0.7152,-173.03,0x877E724C},
      {100002,0.0166,0.0562,-0.3348,0.5874,-353.18,0x8882754F},
    },
  },
  plant = {
    ["1"] = {
      {100002,0.7000,0.5600,0.0000,-0.1000,0.00,0xFF1E2A18},
      {100002,0.6200,0.4800,0.0000,-0.1000,0.00,0xFF79CFA1},
      {100001,0.4200,0.2600,0.0000,0.2400,0.00,0xFFFCA161},
      {100002,0.1539,0.2731,0.0022,0.2403,-264.66,0xDAFF9D5D},
      {100002,0.2034,0.0871,-0.0042,0.2583,-368.71,0xC6FFA463},
      {100002,0.1582,0.1494,0.2035,-0.0267,14.78,0x890B251F},
      {100002,0.3145,0.0500,0.0025,-0.1840,-267.86,0xC77BE0B0},
      {100002,0.0710,0.3472,-0.0630,-0.0615,-346.60,0x7E7FFFD6},
      {100002,0.1621,0.1176,0.0655,0.0871,-205.16,0xA1642C16},
      {100002,0.0776,0.1696,0.2028,-0.1812,-86.48,0xD12B4F3E},
      {100002,0.1888,0.0717,-0.1188,0.1827,-83.12,0xBBFF9C5B},
      {100002,0.0665,0.1741,-0.1434,-0.2526,-156.44,0xC0549B7A},
      {100002,0.2401,0.0585,0.0907,-0.1706,-111.39,0x967CF7C5},
      {100002,0.1080,0.0878,0.1028,0.1994,-291.61,0xCEFFA463},
      {100002,0.0446,0.2771,-0.2493,0.0583,-220.91,0x9D6ECFA3},
      {100002,0.0561,0.1544,-0.2162,-0.1658,-344.14,0xDC3F7058},
      {100002,0.0726,0.0934,-0.0396,0.1692,-188.77,0xF4324635},
      {100002,0.0631,0.1253,0.1175,0.1616,-171.30,0xC3F99456},
      {100002,0.1560,0.0553,-0.1163,0.2039,-66.91,0xAAFFA363},
      {100002,0.1599,0.0586,0.0019,-0.1648,-91.24,0x9C7CD7A8},
      {100002,0.0759,0.0896,0.0267,0.2074,-292.64,0xCCFFA262},
      {100002,0.2533,0.0329,-0.1072,0.0207,-160.27,0xA10A0B08},
      {100002,0.0584,0.1348,0.0618,-0.0328,-15.43,0xA478E5B5},
      {100002,0.1774,0.0864,-0.2176,0.0996,-205.41,0x51000000},
      {100002,0.0710,0.0926,0.1872,-0.2203,-330.89,0xB1071310},
      {100002,0.0907,0.0621,-0.0898,-0.1561,-88.99,0xBF7AD3A3},
      {100002,0.0501,0.0960,-0.1069,-0.1951,-353.89,0xDE7BD2A3},
      {100002,0.0615,0.1115,-0.0431,0.0645,-172.06,0x9A76CB9D},
      {100002,0.1966,0.0426,0.0802,-0.1019,-280.50,0x7E85E5B3},
      {100002,0.1025,0.0716,0.1732,-0.0112,-406.91,0x8D000000},
      {100002,0.0446,0.1585,-0.1854,-0.1324,-138.82,0x8D94FFD8},
      {100002,0.1927,0.0628,0.1104,-0.2895,-356.69,0x52000000},
      {100002,0.1047,0.0430,0.0010,-0.2543,-88.30,0xDA79CEA0},
      {100002,0.0406,0.1567,0.2023,-0.0700,-306.46,0x9885ECB8},
      {100002,0.2003,0.0343,-0.1614,-0.2033,-253.91,0x8C000000},
      {100002,0.1464,0.1028,-0.0698,-0.2732,-73.12,0x3C000000},
      {100002,0.0204,0.2163,0.1252,-0.1418,-198.74,0xC7000000},
      {100002,0.1144,0.0477,-0.1377,-0.2507,-242.36,0x9F8DF1BB},
      {100002,0.1140,0.0584,-0.0664,-0.0988,-271.27,0x8186EBB3},
      {100002,0.0521,0.1167,-0.1605,-0.0972,-315.05,0x8375E1AD},
      {100002,0.0835,0.0605,-0.0357,0.0310,35.61,0x9A7DDEAB},
      {100002,0.0524,0.0917,-0.1458,-0.0107,-296.42,0xA174DBAD},
      {100002,0.0520,0.1048,-0.1890,-0.0043,-52.57,0x8C7CDAAA},
      {100002,0.1303,0.0504,0.1716,0.0835,-248.56,0x7389FFEB},
      {100002,0.1915,0.0255,0.1418,0.1089,-55.88,0x9A000000},
      {100002,0.0350,0.1453,0.1297,-0.0686,-17.07,0x9172DEAE},
      {100002,0.0483,0.1136,0.1515,0.0516,-129.16,0x8271DBA5},
      {100002,0.1555,0.0312,-0.0746,-0.2265,-56.39,0x90000000},
      {100002,0.2722,0.0340,0.0515,-0.2278,-275.21,0x4B000000},
      {100002,0.0567,0.0880,-0.1682,-0.0083,-57.36,0x8B71C399},
      {100002,0.0383,0.1532,0.1886,-0.1464,-55.00,0x7596FFDF},
      {100002,0.1004,0.0564,0.1514,0.0543,-49.88,0x796EBE93},
      {100002,0.0532,0.1399,0.2084,0.0203,-176.57,0x5C000000},
      {100002,0.1223,0.0370,0.0727,-0.1439,-284.75,0x957ED7A7},
      {100002,0.0314,0.1640,-0.0493,0.1178,-171.01,0x818BFFD2},
      {100002,0.2145,0.0384,0.0303,-0.3202,-233.16,0x4F000000},
      {100002,0.0530,0.0692,0.0585,-0.0067,-156.12,0xA46DBE94},
      {100002,0.0215,0.2007,-0.0110,0.1223,-11.08,0x88000000},
      {100002,0.0659,0.1035,-0.2131,-0.0728,-356.57,0x54000000},
      {100002,0.0510,0.0556,-0.1291,-0.2342,-363.33,0xC978CEA1},
      {100002,0.0624,0.0450,-0.0967,0.1780,-52.69,0xCAFFA362},
      {100002,0.0421,0.0597,0.1274,-0.2400,-11.23,0xE078CEA0},
      {100002,0.1535,0.0301,0.2137,-0.1283,-136.94,0x77000000},
      {100002,0.1128,0.0322,-0.2399,0.0480,-294.71,0x8E9CFFD1},
      {100002,0.1795,0.0162,-0.0725,0.1254,-263.10,0xAF000000},
      {100002,0.0185,0.1659,0.0010,0.0688,-13.27,0x9D000000},
      {100002,0.0440,0.0493,0.1945,-0.0299,-127.13,0xDB000000},
      {100002,0.0396,0.0721,0.1345,-0.0824,-211.76,0xA576CB9E},
      {100002,0.1733,0.0221,0.2651,-0.1720,-325.78,0x79000000},
      {100002,0.0186,0.1317,-0.0407,-0.1606,-164.15,0xBD000000},
      {100002,0.1365,0.0199,0.1012,0.0149,-334.20,0xA8000001},
      {100002,0.0552,0.0512,-0.0192,0.0216,1.46,0xA070C196},
      {100002,0.0333,0.1377,-0.1690,0.1737,-173.85,0x62000000},
      {100002,0.1065,0.0299,0.0445,0.1343,-168.34,0x8DFFC673},
      {100002,0.0994,0.0336,-0.0014,-0.0071,-240.02,0x86000206},
      {100002,0.1166,0.0195,0.1471,-0.1522,-141.58,0xC4000000},
      {100002,0.0269,0.1234,0.0819,0.1226,-251.28,0x86FFB36D},
      {100002,0.0167,0.1462,-0.1288,0.0783,-306.11,0xB4050000},
      {100002,0.0810,0.0421,0.0428,-0.0090,-261.29,0x8062B28C},
      {100002,0.1219,0.0281,0.1181,-0.2774,-322.21,0x7B000000},
      {100002,0.0212,0.1091,-0.1464,-0.0467,-101.92,0xB6000001},
      {100002,0.0922,0.0392,0.1669,0.1724,-86.45,0x74000000},
      {100002,0.0228,0.1212,0.2112,-0.1642,-243.79,0x9788EBB0},
      {100002,0.0339,0.0787,-0.0700,-0.0289,-199.32,0x9A6BBB90},
      {100002,0.1049,0.0260,-0.0007,-0.3007,-256.19,0x9684E2B1},
      {100002,0.0343,0.0801,0.1428,-0.2625,-226.15,0x9294FFCB},
      {100002,0.0201,0.1240,0.1702,-0.2505,-22.02,0xA1000000},
      {100002,0.0320,0.0942,-0.1338,0.1563,-148.92,0x84FFBD71},
      {100002,0.1002,0.0235,-0.1386,-0.3060,-224.95,0xA8000000},
      {100002,0.0439,0.1025,-0.1628,-0.1783,-133.46,0x57000000},
      {100002,0.1068,0.0316,0.1739,-0.1265,-309.46,0x746CC596},
      {100002,0.0214,0.1569,-0.2520,0.0133,-208.92,0x74000000},
      {100002,0.1525,0.0254,-0.0332,-0.3042,-99.76,0x64000000},
      {100002,0.0182,0.1220,0.0394,0.1580,-258.40,0xAD000000},
      {100002,0.0465,0.0740,-0.0454,-0.2049,-196.78,0x6F000000},
      {100002,0.0608,0.1421,0.0578,-0.2615,-4.38,0x2A000000},
      {100002,0.0869,0.0312,0.0036,-0.0622,-268.18,0x846BBA92},
      {100002,0.0997,0.0260,-0.1544,-0.2680,-253.94,0x897ED6A6},
      {100002,0.1512,0.0405,-0.1788,0.2020,-62.34,0x3A000000},
      {100002,0.0209,0.0901,-0.1751,0.0351,-250.58,0xBB040C09},
      {100002,0.0850,0.0344,0.1778,0.1150,-66.72,0x7871CA97},
      {100002,0.0335,0.0778,0.2360,-0.0478,-318.61,0x8693F6BF},
      {100002,0.1698,0.0164,0.2435,-0.0785,-56.05,0x7D000000},
      {100002,0.0150,0.1632,-0.0327,-0.1291,-345.49,0x8C000000},
      {100002,0.0180,0.1220,-0.1971,-0.1963,-144.25,0x98000000},
      {100002,0.0207,0.1127,-0.0959,-0.0047,-157.12,0x8F000000},
      {100002,0.0342,0.0967,-0.2129,-0.1012,-156.34,0x63000000},
      {100002,0.1180,0.0220,-0.1964,-0.1938,-55.53,0x7E000000},
      {100002,0.0342,0.0573,0.1239,0.1528,-239.04,0xA4FFA463},
      {100002,0.0215,0.1109,0.1564,0.2116,-15.29,0x85000000},
      {100002,0.0192,0.1006,0.0624,-0.2105,-36.29,0xA2000000},
      {100002,0.0690,0.0343,-0.0478,0.1014,-235.31,0x847BE2AE},
      {100002,0.0559,0.0323,0.0371,0.0628,-342.15,0xAAFFA562},
      {100002,0.0297,0.0456,0.0138,0.1375,-246.56,0xDCFF9E5F},
      {100002,0.0169,0.0947,-0.1585,0.1961,-352.61,0xB7000000},
      {100002,0.0173,0.1260,-0.1181,-0.1087,-343.08,0x86000000},
      {100002,0.0195,0.0951,-0.1488,0.0827,-132.13,0x9AFF9F5B},
      {100002,0.0342,0.0332,0.1874,0.1348,-293.02,0xF870C196},
      {100002,0.0217,0.0985,-0.2373,0.0592,-34.21,0x837EDDA8},
      {100002,0.0374,0.0522,0.1967,-0.0703,-112.13,0x8E81DBAA},
      {100002,0.0869,0.0206,-0.2265,-0.1303,-242.13,0x9B000000},
      {100002,0.1344,0.0134,0.0662,0.0762,-340.47,0x98000000},
      {100002,0.1537,0.0183,0.0848,0.3023,-332.95,0x61100200},
      {100002,0.0952,0.0161,0.2408,-0.2038,-177.44,0xAE000000},
      {100002,0.0178,0.1035,-0.0659,0.1601,-173.04,0x8F000000},
      {100002,0.0131,0.1463,0.0571,0.1054,-259.45,0x89000000},
      {100002,0.1300,0.0145,-0.1047,0.1380,-29.50,0x89000000},
      {100002,0.0631,0.0475,-0.2039,0.0715,-99.43,0x55000000},
      {100002,0.0202,0.0824,0.0785,0.1040,-250.79,0x97000000},
      {100002,0.1005,0.0180,-0.1316,-0.2958,-54.89,0x8A000000},
      {100002,0.0124,0.1318,-0.0224,-0.0638,-358.78,0x98000000},
      {100002,0.0181,0.0896,-0.1466,-0.2825,-153.72,0x997DD5A5},
      {100002,0.0192,0.1565,0.2131,0.0798,-361.81,0x52000000},
      {100002,0.0407,0.0424,0.0399,0.0591,-281.78,0x8CC77E4C},
      {100002,0.0739,0.0177,-0.2265,-0.0178,-133.49,0xB8000000},
      {100002,0.0581,0.0299,-0.1079,0.1155,-37.88,0x8AFF9B5B},
      {100002,0.0818,0.0203,-0.1257,-0.1156,-235.66,0x8F000000},
      {100002,0.0612,0.0465,0.2082,-0.1103,-168.47,0x53000000},
      {100002,0.0213,0.1351,-0.2359,0.0991,-251.40,0x51000000},
      {100002,0.0787,0.0216,0.1023,0.0507,-44.11,0x89000000},
      {100002,0.0326,0.0290,-0.2313,-0.2262,-152.08,0xF5010201},
      {100002,0.0144,0.1198,0.0979,-0.0335,-190.12,0x86000000},
      {100002,0.0398,0.0227,0.1849,-0.0683,-149.10,0xFA75C89C},
      {100002,0.0995,0.0384,-0.2084,-0.0488,-170.61,0x3A000000},
      {100002,0.0172,0.0948,0.0656,0.2961,-68.64,0x88FB9E5F},
      {100002,0.0675,0.0183,-0.1461,0.0913,-227.39,0xB0FFA160},
      {100002,0.1231,0.0144,0.1531,-0.0562,-300.35,0x76000000},
      {100002,0.0127,0.1264,0.1316,0.2655,-216.95,0x82000000},
      {100002,0.1000,0.0165,0.0387,-0.1096,-91.98,0x7B000000},
      {100002,0.0892,0.0158,-0.2735,0.0700,-280.15,0x90000000},
      {100002,0.0129,0.0973,-0.0539,0.3190,-103.62,0xA0000000},
      {100002,0.0135,0.1105,0.0541,0.0945,-250.20,0x86FFC374},
      {100002,0.0183,0.0574,-0.0263,0.1897,-32.46,0xBC020000},
      {100002,0.0963,0.0169,-0.1692,0.0893,-224.83,0x79000000},
      {100002,0.0159,0.0804,-0.2555,0.0202,-33.09,0x98000000},
      {100002,0.0438,0.0218,-0.0806,0.1113,-233.38,0xC8000000},
      {100002,0.0559,0.0255,0.1476,-0.2606,-289.25,0x8483E5B2},
      {100002,0.0137,0.1092,0.0934,-0.0055,-187.66,0x7D000000},
      {100002,0.0179,0.0840,0.0014,-0.3208,-339.10,0x7D6DB58E},
      {100002,0.1006,0.0147,0.0441,0.3183,-169.36,0x7C000000},
      {100002,0.0736,0.0201,0.0292,0.1584,-346.90,0x7B000000},
      {100002,0.0140,0.1036,-0.1432,-0.1090,-320.07,0x7D76D6A6},
      {100002,0.0944,0.0161,0.0571,0.0930,-341.56,0x76FE9459},
      {100002,0.0137,0.0824,0.1707,-0.1965,-40.14,0x9F9FFFD3},
      {100002,0.0661,0.0229,0.1661,-0.1947,-133.24,0x758DF6BA},
      {100002,0.0188,0.0720,-0.1044,-0.0382,-353.77,0x81000000},
      {100002,0.0161,0.0759,-0.1814,-0.2986,-366.72,0x8C000000},
      {100002,0.1012,0.0280,0.0357,-0.2791,-65.25,0x3C000000},
      {100002,0.0183,0.1329,0.2196,0.0975,-194.54,0x43000000},
      {100002,0.0192,0.0656,0.1549,-0.2680,-223.74,0x7E79D0A2},
      {100002,0.0902,0.0161,0.0050,0.3252,-175.19,0x6C000000},
      {100002,0.0191,0.0695,0.1793,-0.2940,-170.40,0x760A0F0C},
      {100002,0.0414,0.0255,0.0262,0.0327,-2.52,0x90000000},
      {100002,0.0226,0.0594,0.0570,0.0583,-253.78,0x71FFA764},
      {100002,0.0552,0.0177,0.2119,-0.2203,-275.55,0x99000000},
      {100002,0.0914,0.0136,-0.1464,0.2611,-43.29,0x77000000},
      {100002,0.0861,0.0129,-0.1170,0.2899,-217.64,0x80000000},
      {100002,0.0251,0.0320,-0.2265,-0.1931,22.61,0xB18BECB5},
      {100002,0.1023,0.0136,0.2365,-0.0113,-177.57,0x65000000},
      {100002,0.0134,0.0782,0.0328,-0.2228,-174.00,0x80000000},
      {100002,0.0142,0.0773,0.1044,0.2942,-55.30,0x74030302},
      {100002,0.0143,0.0671,-0.0217,-0.0352,-190.39,0x7F000000},
      {100002,0.0332,0.0219,-0.0987,0.0445,-18.09,0x92FF884B},
      {100002,0.0131,0.0384,-0.1097,0.0585,-298.62,0xCA060000},
      {100002,0.0124,0.0502,-0.0689,0.0151,-27.08,0xA2000000},
      {100002,0.0454,0.0188,0.2006,0.1556,-122.94,0x6A000000},
      {100002,0.0456,0.0141,0.0358,-0.0764,-86.02,0x84000000},
    },
  },
  statue = {
    ["1"] = {
      {100001,0.6200,0.1600,0.0000,0.3600,0.00,0xFF3E3E48},
      {100002,0.3400,0.5200,0.0000,0.0200,0.00,0xFFC9C9D2},
      {100002,0.2000,0.1800,0.0000,-0.2000,0.00,0xFFE2E2E8},
      {100002,0.1816,0.1513,0.0209,-0.3721,-357.46,0xCF3A3F4F},
      {100002,0.1380,0.1734,-0.1888,0.2656,-360.40,0xA0727291},
      {100002,0.3142,0.0569,0.2793,0.3088,-89.25,0xC3050201},
      {100002,0.1834,0.1262,0.1905,0.2697,-92.94,0x6C7F7EA0},
      {100002,0.2962,0.1026,-0.0305,0.2728,-4.63,0x44000000},
      {100002,0.2884,0.0414,-0.0744,0.0437,-294.88,0x8F010000},
      {100002,0.0399,0.2666,0.0999,0.1141,-177.51,0x91000000},
      {100002,0.3197,0.0370,-0.1091,0.3346,-363.14,0x7A757595},
      {100002,0.1284,0.0925,-0.1655,0.2314,-35.40,0x745E617B},
      {100002,0.0892,0.0751,0.1082,0.2607,-276.45,0xC5111013},
      {100002,0.1390,0.0561,0.2230,0.2808,-80.83,0xA5646480},
      {100002,0.0550,0.1918,0.0341,-0.2016,-197.81,0x787E90B6},
      {100002,0.2232,0.0491,0.1351,0.3999,-4.93,0x725F6884},
      {100002,0.1404,0.0659,0.0181,0.1943,-210.60,0x837C8EB2},
      {100002,0.1108,0.0853,-0.2154,0.2351,-255.86,0x746C6B89},
      {100002,0.0624,0.1155,0.0494,-0.0480,-93.47,0x987987AA},
      {100002,0.1269,0.0665,0.1874,0.2102,-1.51,0x7E727291},
      {100002,0.2930,0.0293,-0.0984,0.1862,-85.88,0x79000000},
      {100002,0.0272,0.2796,0.1642,0.1659,-270.32,0x87000000},
      {100002,0.2033,0.0318,0.1123,-0.0686,-81.07,0x9A000000},
      {100002,0.1131,0.0652,0.0279,-0.3858,-207.87,0x857586AA},
      {100002,0.0421,0.2110,0.1184,0.3311,-261.08,0x6D646782},
      {100002,0.0515,0.0912,-0.0749,0.0960,-105.45,0xCB121012},
      {100002,0.1997,0.0429,-0.0313,-0.2831,-71.32,0x66000000},
      {100002,0.2925,0.0178,-0.0507,0.1846,-75.00,0xA0070504},
      {100002,0.1246,0.0557,-0.0125,0.1703,-230.98,0x74626C89},
      {100002,0.0314,0.2083,-0.0215,0.3015,-270.44,0x7A000000},
      {100002,0.0677,0.0759,-0.1484,0.3157,-171.86,0x99595B74},
      {100002,0.1276,0.0375,0.1016,0.0292,-305.42,0xA40D0909},
      {100002,0.0546,0.0605,-0.2253,0.3283,-252.64,0xED62627C},
      {100002,0.0419,0.1117,0.1206,-0.2430,-171.36,0xA31E1F25},
      {100002,0.0294,0.1643,-0.1900,0.1659,-91.25,0x9D000000},
      {100002,0.0963,0.0498,0.0103,-0.3854,-210.68,0x9C5A6580},
      {100002,0.0427,0.1269,-0.0212,-0.2528,-225.00,0x89000000},
      {100002,0.0476,0.0620,0.0365,-0.4065,-292.98,0xF85A6580},
      {100002,0.0568,0.0909,0.2248,0.3142,-346.57,0x896E6E8B},
      {100002,0.0477,0.0986,0.0306,-0.2341,-204.11,0x8F616C8A},
      {100002,0.0473,0.0965,-0.2079,0.4049,-260.55,0x934C5167},
      {100002,0.0454,0.0626,0.0815,-0.0466,2.48,0xE35E6883},
      {100002,0.0496,0.0964,0.0419,0.2147,-87.37,0x85616C88},
      {100002,0.2701,0.0151,-0.2014,0.3654,1.21,0x9B010000},
      {100002,0.0385,0.1234,-0.0008,-0.1223,-232.00,0x835C6682},
      {100002,0.0507,0.0477,-0.1400,0.2059,-256.37,0xFF63637E},
      {100002,0.0282,0.1616,-0.1457,0.3410,-92.03,0x866B6A86},
      {100002,0.2111,0.0246,-0.0683,0.1984,-259.14,0x745A627B},
      {100002,0.1138,0.0358,0.0687,-0.4380,-210.25,0x93000000},
      {100002,0.1008,0.0422,0.0924,-0.3009,-291.85,0x8B050100},
      {100002,0.0241,0.1862,0.1898,0.1682,-271.41,0x830B0706},
      {100002,0.0247,0.2091,0.1167,-0.1664,-189.82,0x71000000},
      {100002,0.0231,0.1594,0.0170,-0.1002,-222.86,0x9D070302},
      {100002,0.2286,0.0177,-0.1006,0.0370,-275.42,0x8E080402},
      {100002,0.0720,0.0527,0.1531,0.2096,-46.08,0x97656580},
      {100002,0.0338,0.1177,-0.0902,0.0317,-352.24,0x8F0B0808},
      {100002,0.0311,0.1342,-0.0816,-0.0809,-208.65,0x88000000},
      {100002,0.0530,0.0421,0.2301,0.2053,-476.92,0xFD62627D},
      {100002,0.0376,0.1408,-0.0998,0.1843,-173.23,0x6A050000},
      {100002,0.0182,0.1985,0.0169,0.0424,-116.82,0x99020000},
      {100002,0.0250,0.1455,-0.0389,-0.0901,-40.42,0x927180A2},
      {100002,0.2054,0.0222,0.0266,-0.3455,-23.48,0x6F000000},
      {100002,0.0300,0.1015,0.0573,0.2716,-82.64,0xA3555C74},
      {100002,0.1938,0.0272,0.1058,0.3422,-359.17,0x5E8C8BB0},
      {100002,0.0321,0.1318,-0.0154,0.0855,-311.38,0x748999BF},
      {100002,0.0358,0.0924,0.1138,-0.0141,-201.62,0x900C0909},
      {100002,0.0983,0.0348,0.1159,0.2349,-238.58,0x8A090605},
      {100002,0.0894,0.0375,-0.0479,-0.3777,-92.46,0x8C040000},
      {100002,0.0366,0.0837,-0.0580,-0.1454,-165.28,0x99010000},
      {100002,0.0428,0.0456,0.2303,0.3957,-299.38,0xEE4A4F64},
      {100002,0.1089,0.0306,-0.0280,-0.4335,-129.16,0x8A000000},
      {100002,0.0397,0.0853,0.2729,0.1953,-169.74,0x870D0A0B},
      {100002,0.0414,0.0449,0.0944,-0.3678,-353.02,0xF0474C60},
      {100002,0.0255,0.1400,0.0687,0.3042,-257.37,0x7C060301},
      {100002,0.0340,0.0887,-0.0280,0.1590,-330.97,0x926B7796},
      {100002,0.1084,0.0307,-0.2406,0.2821,-90.97,0x8164647F},
      {100002,0.0898,0.0330,0.0137,-0.0405,-350.84,0x8D606A85},
      {100002,0.0736,0.0365,0.1235,-0.3765,-267.81,0x9B110F11},
      {100002,0.0298,0.1051,0.1008,-0.1469,-21.38,0x82050000},
      {100002,0.0277,0.0864,-0.0023,-0.3266,-307.09,0xA96A7694},
      {100002,0.0462,0.0706,-0.0443,-0.0207,-12.21,0x7B0F0C0B},
      {100002,0.0130,0.2169,-0.0618,0.1513,-165.49,0x8A0C0A0B},
      {100002,0.0557,0.0324,-0.0619,0.2434,-69.60,0xD84A4F64},
      {100002,0.0396,0.0768,0.0500,-0.2420,-19.29,0x805C6884},
      {100002,0.0424,0.0625,-0.0271,-0.1831,-13.16,0x8F66718E},
      {100002,0.1473,0.0165,0.0795,-0.2245,-279.03,0x9A040100},
      {100002,0.2094,0.0203,-0.0644,-0.1758,-275.17,0x57000000},
      {100002,0.0493,0.0592,-0.2294,0.2056,-318.87,0x7E696884},
      {100002,0.0365,0.0806,0.0696,-0.0272,-258.33,0x7B606985},
      {100002,0.0188,0.1446,-0.0104,0.1233,-125.79,0x83080504},
      {100002,0.0132,0.1950,0.0388,-0.2883,-102.41,0x890E0A0B},
      {100002,0.0352,0.0700,-0.0103,-0.2862,-312.42,0x8C0A0605},
      {100002,0.0374,0.0686,0.0615,0.0239,-75.16,0x85717FA1},
      {100002,0.0947,0.0291,0.0314,0.0727,-203.55,0x7B55596F},
      {100002,0.0447,0.0403,-0.0334,-0.1915,-121.68,0xB75B657F},
      {100002,0.0284,0.1038,-0.0722,0.2999,-109.71,0x6F030000},
      {100002,0.0697,0.0301,0.0636,0.1311,-191.83,0x9B7B88AC},
      {100002,0.0806,0.0258,0.1011,-0.2164,-279.08,0x997686AA},
      {100002,0.1247,0.0245,0.1133,-0.2825,-62.90,0x67090504},
      {100002,0.0433,0.0337,0.0647,0.1641,6.15,0xC70E0C0E},
      {100002,0.0604,0.0285,0.1655,0.2847,-309.31,0xA7444B5F},
      {100002,0.1327,0.0139,-0.0069,-0.0145,-193.81,0x980B0809},
      {100002,0.1221,0.0158,0.0409,-0.0026,-184.68,0x92070300},
      {100002,0.0888,0.0229,0.1111,-0.3357,-127.61,0x830A0707},
      {100002,0.0640,0.0307,-0.0531,-0.3404,-81.10,0x86100D0D},
      {100002,0.0156,0.1112,0.0598,-0.3358,-95.94,0x8E050000},
      {100002,0.0802,0.0258,0.0500,-0.3064,1.25,0x77555971},
      {100002,0.0998,0.0192,-0.0185,0.3112,-351.92,0x7F0C0907},
      {100002,0.0217,0.1064,0.0126,0.3474,-268.80,0x6765647C},
      {100002,0.0221,0.0635,-0.0074,0.2612,-317.17,0xA2535971},
      {100002,0.0493,0.0344,-0.0269,-0.1813,-312.87,0x828898BF},
      {100002,0.0171,0.0959,0.0006,0.1523,-310.32,0x865E6882},
      {100002,0.0174,0.0911,0.0045,0.0123,-295.28,0x887281A4},
      {100002,0.0746,0.0215,0.1205,-0.4026,-65.33,0x86090505},
      {100002,0.1098,0.0160,0.0575,-0.0857,-182.30,0x78030000},
      {100002,0.0245,0.0709,-0.0541,0.2572,-153.58,0x78555C74},
      {100002,0.0882,0.0200,0.0473,0.2494,-186.22,0x75000000},
      {100002,0.0186,0.0803,0.0204,0.1427,-292.67,0x89000000},
      {100002,0.0444,0.0297,0.0280,0.0207,-205.72,0x9B5D6884},
      {100002,0.0928,0.0164,-0.0222,0.2199,-43.45,0x86000000},
      {100002,0.0173,0.0840,0.0016,-0.0302,-290.42,0x886B7695},
      {100002,0.0366,0.0246,-0.0215,-0.3279,-209.19,0xD9606A86},
      {100002,0.0488,0.0283,-0.0418,-0.1348,-196.34,0x8C0E0A07},
      {100002,0.0198,0.0657,0.0090,0.2604,-290.11,0x92535A71},
      {100002,0.0903,0.0155,0.0136,-0.3476,-30.11,0x80050000},
      {100002,0.0176,0.0601,0.0644,-0.1630,-209.34,0x92070302},
      {100002,0.0802,0.0144,-0.0443,0.0667,-57.04,0x80687492},
      {100002,0.0553,0.0154,0.1009,-0.2559,-266.38,0xA75B6681},
      {100002,0.0443,0.0259,-0.0689,0.2627,-293.21,0x75646C89},
      {100002,0.0329,0.0234,0.0887,-0.1032,-276.43,0xAE0B0909},
      {100002,0.0290,0.0223,0.0739,0.1902,12.34,0xC4606B86},
      {100002,0.0184,0.0429,0.0676,0.1050,-93.29,0x9A1C1912},
      {100002,0.0142,0.0665,0.0718,-0.4200,-174.31,0x80070301},
      {100002,0.0419,0.0241,0.0292,0.1187,14.79,0x746A7694},
      {100002,0.0246,0.0519,0.0669,-0.1116,8.44,0x556F7594},
      {100002,0.0171,0.0366,-0.0777,-0.0196,-170.37,0x8F7282A5},
      {100002,0.0158,0.0422,0.1854,0.2569,-124.23,0x3B07090A},
      {100002,0.0289,0.0141,0.1876,0.2657,-271.86,0x33000100},
    },
  },
}

end

__M["ui_controller"] = function()
local M = {}
local function same_value(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    local bv = b[k]
    if bv ~= v then
      if type(v) ~= "table" or type(bv) ~= "table" or not same_value(v, bv) then return false end
    end
  end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
M.DESIGN = { width = 1920, height = 1080 }
M.FURN_BAKED = false
M.FURN_TPL = true
local FurnArt = __require("furn_art")
local FurnRecords = __require("furn_art_records")
M.CANVAS = { width = 1600, height = 900 }
M.SCALE  = M.CANVAS.width / M.DESIGN.width     
local function round(v) return math.floor(v + 0.5) end
function M.to_canvas(r)
  local s = M.SCALE
  return {
    cx = round((r.x + r.w / 2) * s),
    cy = round((M.DESIGN.height - r.y - r.h / 2) * s),
    w  = round(r.w * s),
    h  = round(r.h * s),
  }
end
M.SHOW_TOOL_BUTTONS = false
M.TOAST_SECONDS = 2.5
M.HOME_TITLE = "侦探推理 · 摆位谜题"
M.LAYOUT = {
  topbar = { x = 0, y = 0, w = 1920, h = 104 },
  title  = { x = 70, y = 156, w = 540, h = 56 },    
  left   = { x = 24, y = 128, w = 392, h = 880 },
  tray   = { x = 40, y = 148, w = 360, h = 218 },    
  tray_item_h = 104,                                 
  tray_gap_x = 12,
  tray_gap_y = 10,
  tray_per_row = 3,                                  
  clues  = { x = 36, y = 275.4, w = 480, h = 652.8 },   
  clue_row_h = 127.2,        
  clue_max_visible = 18,     
  clue_rows = 5,             
  legend = { x = 40, y = 916, w = 360, h = 76 },    
  board  = { x = 730, y = 166, w = 701, h = 701 },    
  ruler  = 14,
  right  = { x = 1420, y = 128, w = 460, h = 880 },
  modal = { w = 760, h = 720 },    
  side_key = { size = 110, gap = 40, top = 26, right_edge = 1904 },
  progress = { y = 900, h = 60, num_w = 150, icon_gap = 24 },
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
}
local Controller = {}
Controller.__index = Controller
M.Controller = Controller
Controller._row_letter = {}
Controller._row_face = {}
Controller._row_text = {}
function M.new(core, opts)
  opts = opts or {}
  local self = setmetatable({}, Controller)
  self.core = core
  self.opts = opts
  self.effects = {}
  self.dirty = true
  self.toast = nil
  self.toast_until = nil
  self.now = 0
  self.modal = nil           
  self.screen = opts.screen
  self.select_page = M.SELECT_PAGE or 1
  for index, entry in ipairs(type(opts.levels) == 'table' and opts.levels or {}) do
    if tostring(entry.id) == opts.current_level then
      self.select_page = math.ceil(index / 4)
      M.SELECT_PAGE = self.select_page
      break
    end
  end
  self.share_code = nil
  self._created = {}
  self._props = {}
  self._gesture_snapshot = nil
  self.debug = opts.debug == true
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
function Controller:_reset_row_maps_if_level_changed()
  local lv = self.core and self.core.level
  local sig = (lv and lv.id) or "?"
  if self._row_map_sig ~= sig then
    self._row_map_sig = sig
    Controller._row_letter = {}
    Controller._row_face = {}
    Controller._row_text = {}
    self._grid_text = nil
    Controller._piece_core = nil
    Controller._piece_id_cache = nil
  end
end
local function mark_list_of(set, vm, resolve)
  if type(set) ~= "table" then return nil end
  local out = {}
  for kk, vv in pairs(set) do
    if vv then
      local id = tostring(kk)
      local letter = nil
      if resolve ~= nil then letter = resolve(vm, id) end
      out[#out + 1] = (letter ~= nil and tostring(letter) ~= "") and tostring(letter) or id
    end
  end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end
function Controller:cell_id(r, c) return string.format("cell.%d.%d", r, c) end
function Controller:finish_accuse(thief, has_acc, acc)
  local core = self.core
  local res
  if has_acc == nil then
    res = core:accuse(thief)
  else
    res = core:accuse_verdict(thief, has_acc, acc)
  end
  self.toast = res.message
  self.toast_until = self.now + M.TOAST_SECONDS    
  if res.solved then
    local okv, v2 = pcall(function() return core:view() end)
    if okv and type(v2) == "table" and type(v2.hud) == "table" then
      self.result_seconds = v2.hud.time
    end
    self.modal = { kind = "result", win = true, message = res.message }
    self:fx("modal", M.EFFECTS.SOLVED)
    local vid = core.victim_id
    if vid ~= nil then self:fx("tray." .. tostring(vid), M.EFFECTS.VICTIM) end
    if self.opts.on_solved then self.opts.on_solved(core:view()) end
  else
    self.modal = nil
    self.result_seconds = nil
    self:fx("modal", M.EFFECTS.FAIL)
  end
  self.dirty = true
  return res
end
function Controller:dismiss_action_confirm()
  local p = self.pending
  if p and (p.action == "submit" or p.action == "restart") then
    self.pending = nil
    self:sync_confirm()
  end
end
function Controller:sync_confirm()
  local want = (self.pending ~= nil)
  self._confirm_shown = want
  self.dirty = true
  return want
end
M.VERDICT_RING_SECONDS = 0.4
M.VERDICT_RING_GAP     = 0.15
function Controller:_placement_snapshot()
  local core = self.core
  local pieces = core and core.pieces
  local snapshot = { n = pieces and #pieces or 0 }
  for i = 1, snapshot.n do
    local id = pieces[i].id
    local p = core.pos and core.pos[id]
    local k = (i - 1) * 4
    snapshot[k + 1], snapshot[k + 2] = id, not not p
    snapshot[k + 3], snapshot[k + 4] = p and p.r, p and p.c
  end
  return snapshot
end
function Controller:_placement_matches(snapshot)
  local core = self.core
  local pieces = core and core.pieces
  if pieces == nil then return snapshot.n == 0 end
  if #pieces ~= snapshot.n then return false end
  for i = 1, #pieces do
    local k = (i - 1) * 4
    local id = pieces[i].id
    local p = core.pos and core.pos[id]
    if id ~= snapshot[k + 1] or (not not p) ~= snapshot[k + 2]
        or (p and p.r) ~= snapshot[k + 3] or (p and p.c) ~= snapshot[k + 4] then
      return false
    end
  end
  return true
end
function Controller:_start_verdict()
  local core = self.core
  if core == nil or core.solution == nil or next(core.solution) == nil or core.pieces == nil then return nil end
  local list, wrong = {}, 0
  for i = 1, #core.pieces do
    local id = core.pieces[i].id
    local p = core.pos and core.pos[id]
    local s = core.solution[id]
    if p ~= nil and s ~= nil then
      local ok = (p.r == s.r and p.c == s.c)
      if not ok then wrong = wrong + 1 end
      list[#list + 1] = { id = id, cell = self:cell_id(p.r, p.c), ok = ok }
    end
  end
  if #list == 0 then return nil end
  self:_clear_verdict()
  self._verdict = {
    list = list, wrong = wrong, t0 = self.now or 0, snapshot = self:_placement_snapshot(),
    level = core.level and core.level.id, done = false, last = {},
  }
  return wrong
end
function Controller:_clear_verdict()
  self._press = nil
  self:_clear_hold_progress()
  self._verdict = nil
  self._resumed_solved_board = nil
  local ad = self._last_adapter
  if ad ~= nil and ad.clear_verdict_rings ~= nil then pcall(function() ad:clear_verdict_rings() end) end
end
function Controller:_verdict_step()
  local v = self._verdict
  if v == nil then return end
  local core = self.core
  local lv = core and core.level and core.level.id
  if core == nil or self.screen ~= nil or lv ~= v.level or not self:_placement_matches(v.snapshot) then
    self:_clear_verdict()
    return
  end
  if v.done and v.animation_complete then return end
  local el = (self.now or 0) - v.t0
  local dur, gap = M.VERDICT_RING_SECONDS, M.VERDICT_RING_GAP
  local ad = self._last_adapter
  local animation_complete = true
  for i = 1, #v.list do
    local a = (el - (i - 1) * (dur + gap)) / dur
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if a < 1 then animation_complete = false end
    if v.last[i] ~= a then
      v.last[i] = a
      if ad ~= nil and ad.set_verdict_ring ~= nil then
        pcall(function() ad:set_verdict_ring(v.list[i].cell, v.list[i].ok, a) end)
      end
    end
  end
  v.animation_complete = animation_complete
  if not v.done and el >= (#v.list - 1) * (dur + gap) + dur then
    v.done = true
    local thief_ok = self:_verdict_thief_ok(v)
    if v.wrong == 0 then
      self:_settle_by_roles()
      self:_mark_outcome("perfect")
    elseif thief_ok == true then
      self:_settle_by_roles()
      self:_mark_outcome("success")
    elseif thief_ok == false then
      self:_show_fail()
    end
    self.dirty = true
  end
end
function Controller:_verdict_thief_ok(v)
  local core = self.core
  local thief = core and core.roles and core.roles.thief
  if thief == nil or v == nil then return nil end
  for i = 1, #v.list do
    if v.list[i].id == thief then return v.list[i].ok == true end
  end
  return nil
end
function Controller:_mark_outcome(kind)
  if self.modal ~= nil and self.modal.kind == "result" and self.modal.win then
    self.modal.outcome = kind
    if self.opts.on_result then
      self.opts.on_result(kind, (self._verdict and self._verdict.wrong) or 0, self.result_seconds or self.core.elapsed or 0)
    end
  end
end
function Controller:_show_fail()
  local core = self.core
  local okv, v2 = pcall(function() return core:view() end)
  self.result_seconds = (okv and type(v2) == "table" and type(v2.hud) == "table") and v2.hud.time or nil
  local got, total = core:score()
  self.modal = { kind = "result", win = false, outcome = "fail",
                 message = string.format("盗窃者没有找对（%d/%d 位置正确）", got, total) }
  self:fx("modal", M.EFFECTS.FAIL)
end
function Controller:_settle_by_roles()
  local core = self.core
  local roles = core.roles or {}
  if roles.thief ~= nil then
    self:finish_accuse(roles.thief, roles.accomplice ~= nil, roles.accomplice)
  else
    self.toast = "本关没配 roles.thief，无法结算（关卡数据问题）"
  end
end
function Controller:do_submit()
  local core = self.core
  if core == nil or core.submit == nil then return end
  -- 753(额外1)：关卡胜利后退出重进未修改（仍保留已画好的红绿圈 _verdict.done + 快照未变），直接弹结果弹窗，不重新画圈，也不解锁结算限制。
  local v = self._verdict
  local lv = core.level and core.level.id
  if self._resumed_solved_board and v ~= nil and v.done and v.animation_complete
      and v.level == lv and self:_placement_matches(v.snapshot) then
    local thief_ok = self:_verdict_thief_ok(v)
    if v.wrong == 0 or thief_ok == true then
      self:fx("hex.submit", M.EFFECTS.SUBMIT)
      local outcome = (v.wrong == 0) and "perfect" or "success"
      self.modal = { kind = "result", win = true, outcome = outcome }
      self:fx("modal", M.EFFECTS.SOLVED)
      self.dirty = true
      return
    end
  end
  self._resumed_solved_board = nil
  local res = core:submit()
  self:fx("hex.submit", M.EFFECTS.SUBMIT)
  self.toast = res and res.message or nil
  self.toast_until = self.now + M.TOAST_SECONDS    
  if res ~= nil and res.ok then
    local wrong = self:_start_verdict()
    if wrong == nil then
      self:_settle_by_roles()
    elseif wrong > 0 then
      local got, total = core:score()
      self.toast = string.format("摆对了 %d / %d 个，红圈是摆错的位置", got, total)
      self.toast_until = self.now + M.TOAST_SECONDS
    end
  else
    -- 751(b)：关内无 toast 文本框，未摆满/冲突无法提交时借用现成 hint635.result 给出清晰提示。
    local msg = (res and res.message) or "还有人物未摆放到棋盘上"
    self.hint635 = { kind = "message", text = "无法提交：" .. tostring(msg), until_time = (self.now or 0) + 3.5 }
  end
  self.dirty = true
end
function Controller:do_restart()
  if self.opts.on_ticket_restart then self.opts.on_ticket_restart() end
  self.core.hint635_used=nil
  self.hint635=nil
  self:_clear_verdict()
  local core = self.core
  if core ~= nil and core.reset ~= nil then core:reset() end
  self._clue_tap,self._false_clues,self._grid_click_at=nil,nil,nil
  self._clue_sel_key, self._clue_sel_pos = nil, nil
  self.focused_clue = nil
  self._grid_focus_item, self._grid_focus_orig = nil, nil
  self._grid_focus_idx, self._grid_focus_pos = nil, nil
  self._grid_refill_pending = true
  self.modal = nil
  self.toast = nil
  self.toast_until = nil     
  self.dirty = true
end
function Controller:do_back()
  self:_clear_verdict()
  self.screen = "select"
  self.modal = nil
  self.dirty = true
  if self.opts.on_back then self.opts.on_back() end
end
function Controller:format_time(sec)
  sec = math.max(0, math.floor(sec or 0))
  return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end
local DOUBLE_CLICK_SECONDS = 0.35
local CELL_DOUBLE_CLICK_SECONDS = 0.45
local HIGHLIGHT_TINT = 4294956107
local CARD_MAT  = 106053
local CARD_TINT = { r = 250, g = 244, b = 232, a = 0 }    
local LONG_PRESS_SECONDS = 0.28
local HOLD_RING_DELAY = 0.20
local TAP_MOVE_TOLERANCE = 24
M.TEST_CLOCK = nil
local function gesture_now(self)
  local t = rawget(M, "TEST_CLOCK")
  if type(t) == "number" then return t end           
  local ok, c = pcall(os.clock)
  if ok and type(c) == "number" then return c end
  return (self and rawget(self, "now")) or 0
end
local function press_seconds(self)
  local p = rawget(self, "_press")
  if p ~= nil and type(p.dt) == "number" then return p.dt end
  if p ~= nil and type(p.t) == "number" then return gesture_now(self) - p.t end
  return nil
end
M.press_seconds = press_seconds
function Controller:snapshot()
  self._gesture_snapshot = self.core:serialize()
end
function Controller:_refuse(r, c, why)
  if why == nil then return end
  self:fx(self:cell_id(r, c), M.EFFECTS.FAIL)
  self._refuse_seen = self._refuse_seen or {}
  local n = self._refuse_seen[why] or 0
  if n >= 3 then return end
  self._refuse_seen[why] = n + 1
  if print then
    print("[murdoku] 点 (第" .. tostring(r) .. "行 第" .. tostring(c) .. "列) 没生效："
      .. tostring(why) .. "  当前工具=" .. tostring(self.core and self.core.mode)
      .. "  已选=" .. tostring(self.core and self.core.selected)
      .. "（同类提示最多打 3 次）")
  end
end
function Controller:do_place(r, c)
  local core = self.core
  self.last_click = nil
  local who = core.selected
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
    self:dismiss_action_confirm()
  self._grid_refill_pending = true
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end
function Controller:do_pre_place(r, c)
  local core = self.core
  self.last_click = nil
  local who = core.selected
  local _sel_b2 = core.selected
  local ok, why = core:pre_place(r, c)
  if ok then
    print("[murdoku] ★ 放置分辨：走的=【预放置 pre_place】 人=" .. tostring(_sel_b2)
      .. "  放后选中=" .. tostring(core.selected) .. "（★ 应仍是 " .. tostring(_sel_b2) .. " ✓）")
  end
  if ok then
    self:dismiss_action_confirm()
  self._grid_refill_pending = true
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end
function Controller:_clear_hold_progress()
  local ad = self._last_adapter
  if ad and ad.clear_hold_ring then ad:clear_hold_ring() end
end
function Controller:_hold_progress(p)
  if self.screen ~= nil or self.modal ~= nil then
    self._press = nil
    self:_clear_hold_progress()
    return
  end
  local ad = self._last_adapter
  if p and p.r and p.c and self.core and self.core.selected and ad and ad.set_hold_ring then
    if (p.dt or 0) < HOLD_RING_DELAY then return end
    ad:set_hold_ring(self:cell_id(p.r, p.c), math.min(1, ((p.dt or 0)-HOLD_RING_DELAY) / (LONG_PRESS_SECONDS-HOLD_RING_DELAY)))
  else
    self:_clear_hold_progress()
  end
end
function Controller:on_cell_down(r, c, x, y)
  self:_clear_hold_progress()
  self._press = { r = r, c = c, dt = 0, t = gesture_now(self), x = x, y = y }
  self:_hold_progress(self._press)
  return false
end
function Controller:on_cell_up(r, c, x, y)
  local p = self._press
  local dt = press_seconds(self)
  self._press = nil
  self:_clear_hold_progress()
  if p == nil then return false end
  if p.r ~= r or p.c ~= c then return false end           
  if dt == nil then return false end
  if dt < LONG_PRESS_SECONDS then return false end          
  if p.x ~= nil and x ~= nil then
    local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
    if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then return false end
  end
  local ok = self:do_place(r, c)
  print("[murdoku] ★ 放置分辨：抬起被判定为【长按】✓ 时长=" .. string.format("%.2f", dt))
  do
    local _s = rawget(self, "_lp_stat")
    if _s == nil then _s = { n = 0, sum = 0, min = nil, max = nil, half = {} }; self._lp_stat = _s end
    _s.n = _s.n + 1
    _s.sum = _s.sum + dt
    if _s.min == nil or dt < _s.min then _s.min = dt end
    if _s.max == nil or dt > _s.max then _s.max = dt end
    if _s.n <= 4 then _s.half[1] = (_s.half[1] or 0) + dt else _s.half[2] = (_s.half[2] or 0) + dt end
    if _s.n == 8 and type(print) == "function" then
      local h1 = (_s.half[1] or 0) / 4
      local h2 = (_s.half[2] or 0) / 4
      print(string.format(
        "[murdoku] ★ 长按时长统计（前 8 次）：最小=%.2f 最大=%.2f 平均=%.2f"
        .. "　★ 前 4 次均=%.2f / 后 4 次均=%.2f ⇒ ★ %s",
        _s.min, _s.max, _s.sum / _s.n, h1, h2,
        (h2 > h1 * 1.5) and "**后一半明显更大 ⇒ 还在漂移** ✗（把这两行发我）"
          or "前后差不多 ⇒ ★ 已经好了 ✓（剩下的浮动是【手的时长】✓ 不是漂移 ✓）"))
    end
  end
  if ok then
    self._suppress_click = true      
  end
  return ok
end
function Controller:on_cell_drag(r, c, x, y)
  local p = self._press
  if p == nil then return false end
  if p.x == nil or x == nil then return false end
  local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
  if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then
    self._press = nil
    self:_clear_hold_progress()
    return true
  end
  return false
end
local function cell_click_now(self)
  local t = rawget(M, "TEST_CLOCK")
  if type(t) == "number" then return t end
  return (self and rawget(self, "now")) or 0
end
function Controller:on_cell_click(r, c)
  if r == nil or c == nil then return end
  self:_flush_clue_tap()
  local core = self.core
  self.now = self.now or 0
  local now_t = cell_click_now(self)
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode
  if (not occupied) and mode == "place" then
    local last = self.last_click
    if last and last.r == r and last.c == c and (now_t - last.t) <= CELL_DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      if last.did == "x" then
        core:toggle_x(r, c)              
        self.dirty = true
      elseif last.did == "pre" then
        core:undo()                      
        self.dirty = true
      end
      self:do_pre_place(r, c)
      return
    end
  end
  local had = core.grid[r][c]
  local had_selected = core.selected           
  local ok, why = core:tap_cell(r, c)
  if ok then
    self:dismiss_action_confirm()
    if had then
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
      self._grid_refill_pending = true
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = now_t,
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = now_t, did = "none" }
    end
    self:_refuse(r, c, why)
  end
end
local KB_ACTIONS = {
  KeyboardCraftspersonKey36Down = "up",
  KeyboardCraftspersonKey37Down = "down",
  KeyboardCraftspersonKey38Down = "left",
  KeyboardCraftspersonKey39Down = "right",
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
  KeyboardInteractKeyDown       = "place",    
  KeyboardJumpKeyDown           = "note",     
  KeyboardDropKeyDown           = "xmark",    
  KeyboardCraftspersonKey42Down = "back",      
  KeyboardOpenShortcutWheelKeyDown = "tool",     
  KeyboardCharacterSkill1KeyDown   = "eraser",   
  KeyboardCharacterSkill3KeyDown   = "submit",   
  KeyboardCraftspersonKey12Down    = "undo",     
  KeyboardCraftspersonKey13Down    = "redo",     
  KeyboardCraftspersonKey15Down    = "hint",     
}
local KB_DELTA = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }
local KB_TOOL_CYCLE = { "place", "note", "x", "eraser" }
function Controller:kb_move(dr, dc)
  local kb = self.kb or { r = 1, c = 1 }
  local r = math.min(self.core.rows, math.max(1, kb.r + dr))
  local c = math.min(self.core.cols, math.max(1, kb.c + dc))
  if r ~= kb.r or c ~= kb.c or not self.kb_active then
    self:dismiss_action_confirm()
    self.kb_active = true
    self.dirty = true
  end
  self.kb = { r = r, c = c }
end
local function kb_action_of(event)
  return KB_ACTIONS[tostring(event.key or "")]
end
function Controller:on_key(event)
  local core = self.core
  local act = kb_action_of(event)
  if act == nil then return false end
  local d = KB_DELTA[act]
  if d ~= nil then
    self:kb_move(d[1], d[2])
    return true
  end
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
    local kb = self.kb
    if kb ~= nil then
      self.kb_active = true
      self:on_cell_click(kb.r, kb.c)
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
    if self.modal ~= nil then self:on_input({ action = "close_modal" })
    else self:on_input({ action = "level_list" }) end
    return true
  end
  return false
end
function Controller:finish_position_hint()
    self.hint635=nil
    self:_clear_verdict();self._grid_refill_pending=true
    self._clue_sel_key,self._clue_sel_pos=nil,nil;self.focused_clue=nil
    self.dirty=true;self:fx("hex.hint",M.EFFECTS.SELECT)
end
function Controller:hint635_action(action)
  if self.screen ~= nil or self.modal ~= nil then return end
  local core=self.core
  core.hint635_used=core.hint635_used or {position=0,clue=0}
  local used=core.hint635_used
  local function message(text, timed)
    self.hint635={kind="message",text=text,until_time=timed and ((self.now or 0)+3) or nil}
  end
  if action=="close" then if self.hint635 then self:dismiss_action_confirm() end;self.hint635=nil;return end
  if action=="toggle" then
    if self.hint635 then
    self:dismiss_action_confirm()
      self.hint635=nil
    elseif not core.selected and self.general_focus~=true then
      message("请先选中一条线索卡",true)
    else
    self:dismiss_action_confirm()
      self.hint635={kind="menu"}
    end
    return
  end
  if not self.hint635 or self.hint635.kind~="menu" then return end
  if action=="position" then
    if used.position>=1 then
      message('正在核对交易',false)
      local ok,msg=self.opts.trade('position')
      if not ok then message(msg,true) end
      return
    end
    local ok,msg=core:hint()
    if not ok then message(msg,true);return end
    self:dismiss_action_confirm()
    used.position=used.position+1
    if self.opts.on_hint_saved then self.opts.on_hint_saved() end
    self:finish_position_hint()
  elseif action=="clue" then

    self:_sync_clue_focus()
    local general=self.general_focus==true
    local index=general and 1 or self.focused_clue
    if not index or (not general and not core.selected) then message("请先选中一条线索卡",true);return end
    if used.clue>=2 then
      message('正在核对交易',false)
      local ok,msg=self.opts.trade('use')
      if not ok then message(msg,true) end
      return
    end
    local truth=core:answer_clue(index,general)
    if truth==nil then message("请先选中一条线索卡",true);return end
    self:dismiss_action_confirm()
    used.clue=used.clue+1
    if self.opts.on_hint_saved then self.opts.on_hint_saved() end
    message(truth and "该线索为真" or "该线索为假",false)
  end
end
function Controller:on_input(event)
  local core = self.core
  local a = event.action
  local old_modal, old_screen = self.modal, self.screen
  if self.screen=='shop' then
    if event.phase=='down' or event.phase=='up' or event.phase=='drag' then return self.effects end
    if self.shop_confirm then
      if a=='store_no' then self.shop_confirm=false
      elseif a=='store_yes' and self.econ_pick then
        local ok,msg=self.opts.trade('buy',self.econ_pick)
        self.shop_confirm=false; self.econ_status=msg
      end
    elseif a=='store_leave' then self.screen='home';self.econ_pick=nil;self.econ_status=nil
    elseif a=='store_clear' then self.econ_pick=nil;self.econ_status=nil
    elseif a=='store_clue' or a=='store_position' then self.econ_pick=a=='store_clue' and 'clue' or 'position';self.econ_status=nil
    elseif a=='store_purchase' then
      local coins,_,pending=self.opts.wallet()
      if not self.econ_pick then self.econ_status='请先选择道具'
      elseif pending and pending~='' then self.econ_status=pending
      elseif not coins or coins<SHOP_PRICE[self.econ_pick] then self.econ_status='调查币不足'
      else self.shop_confirm=true end
    end
    self.dirty=true;return self.effects
  end
  if self.screen=='bag' then
    if event.phase=='down' or event.phase=='up' or event.phase=='drag' then return self.effects end
    if a=='econ_back' then
      self.screen='home'; self.econ_pick=nil; self.econ_status=nil
    elseif a=='econ_clue' or a=='econ_position' then
      local _,clues,_,_,positions=self.opts.wallet()
      local target=a=='econ_clue' and 'clue' or 'position'
      if (target=='clue' and (clues or 0)>0) or (target=='position' and (positions or 0)>0) then self.econ_pick=target end
    else return self.effects end
    self.dirty=true; return self.effects
  end
  if event.phase == "key" then
    self:on_key(event)
    return self.effects
  end
  if event.phase == "down" then
    if a == "click" then
      self:_flush_clue_tap()
      self:on_cell_down(event.r, event.c, event.x, event.y)
    end
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
    if core:tap_suspect(event.id) then self:dismiss_action_confirm() end
    local vm = core:view()
    if vm.hud.selected == event.id then
      self:fx("tray." .. tostring(event.id), M.EFFECTS.SELECT)
    end
    if self.modal and self.modal.kind == "accuse" then
      self.modal = { kind = "accuse" }    
    end
  elseif a == "gesture_begin" then
    self:snapshot()
  elseif a == "gesture_rollback" then
    if self._gesture_snapshot then
      core:deserialize(self._gesture_snapshot)
      self.toast = "已回滚本次操作"
      self.toast_until = self.now + M.TOAST_SECONDS    
      self:fx("board", M.EFFECTS.UNDO)
    end
  elseif a == "click" then
    if self._suppress_click then
      self._suppress_click = nil
    else
      self:on_cell_click(event.r, event.c)
    end
  elseif a == "cell_right" then
    if core:toggle_x(event.r, event.c) then
    self:dismiss_action_confirm()
      self:fx(self:cell_id(event.r, event.c), M.EFFECTS.XMARK)
    end
  elseif a == "tool" then
    if print then
      self._tool_log = (self._tool_log or 0) + 1
      if self._tool_log <= 12 then
        print("[murdoku] 切换工具 → " .. tostring(event.mode)
          .. "（之前是 " .. tostring(core.mode) .. "）")
      end
    end
    local old_mode, old_selected = core.mode, core.selected
    if core:set_mode(event.mode) and (old_mode ~= core.mode or old_selected ~= core.selected) then self:dismiss_action_confirm() end
  elseif a == "back_confirm" then
    self:dismiss_action_confirm()
    self.modal = { kind = "exit_menu" }    
    self.dirty = true
    self:sync_confirm()
    self:fx("hex.back", M.EFFECTS.SELECT)
  elseif a == "submit" then
    self:_flush_clue_tap()
    self.last_click, self._press = nil, nil
    self:_clear_hold_progress()
    self.pending = { action = "submit" }
    self:sync_confirm()
    self:fx("hex.submit", M.EFFECTS.SELECT)
  elseif a == "restart" then
    self:_flush_clue_tap()
    self.last_click, self._press = nil, nil
    self:_clear_hold_progress()
    self.pending = { action = "restart" }
    self:sync_confirm()
    self:fx("hex.redo", M.EFFECTS.SELECT)
  elseif a == "confirm_no" then
    self.pending = nil
    self:sync_confirm()
    self.toast = "已取消"
    self.toast_until = self.now + M.TOAST_SECONDS    
  elseif a == "confirm_yes" then
    local p = self.pending
    self.pending = nil
    self:sync_confirm()
    if p ~= nil then
      if p.action == "submit" then
        self:do_submit()
      elseif p.action == "restart" then
        self:do_restart()
      elseif p.action == "back" then
        self:do_back()
      end
    end
  elseif a == "undo" then
    self:fx("hex.undo", M.EFFECTS.SELECT)
    if core:undo() then
    self:dismiss_action_confirm()
      self:fx("hex.undo", M.EFFECTS.UNDO)
      self._grid_refill_pending = true
      self.dirty = true
    end
  elseif a == "redo" then
    if core:redo() then
    self:dismiss_action_confirm()
      self:fx("hex.redo", M.EFFECTS.UNDO)
      self._grid_refill_pending = true
      self.dirty = true
    end
  elseif a == "hint" then
    self:hint635_action("toggle")
  elseif a == "reveal" then
    self:dismiss_action_confirm()
    core:reset()
    self._clue_sel_key, self._clue_sel_pos = nil, nil
    self.focused_clue = nil
    for id, p in pairs(core.solution) do
      core:select_suspect(id)
      core:hold_cell(p.r, p.c)
    end
    self.toast = "已揭示答案"
    self.toast_until = self.now + M.TOAST_SECONDS    
  elseif a == "accuse" then
    local code = core:encode_state()
    self.share_code = code
    self.modal = { kind = "share", code = code }
    if self.opts.on_share then self.opts.on_share(code) end
  elseif a == "howto" then
    self.modal = { kind = "howto" }
  elseif a == "close_modal" then
    self:_clear_verdict()
    self.modal = nil
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
    if not self:can_settle() then return end
    if self.opts.on_settle then self.opts.on_settle() end
    self.dirty = true
  elseif a == "level_list" then
    self.modal = { kind = "levelselect" }
  elseif a == "select_page" then
      self.select_page = (tonumber(self.select_page) or 1) + (tonumber(event.delta) or 0)
      if self.select_page < 1 then self.select_page = 1 end
      M.SELECT_PAGE = self.select_page
      self.dirty = true
  elseif a == "settle_only" then
    if not self:can_settle() then return end
    if self.opts.on_settle_only then self.opts.on_settle_only() end
    elseif a == "pick_level" then
    if self.opts.on_pick_level then
      self.modal = nil
      self.opts.on_pick_level(event.id)               
    end
  elseif a == "home" then
    self._waiting_continue = nil
    self._waiting_card = nil
    self.screen = "home"; self.modal = nil; self.dirty = true
  elseif a == "replay" then
    self.result_seconds = nil
    self:do_restart()
  elseif a == "levelselect" then
    self._waiting_continue = nil
    self.screen = "select"; self.modal = nil; self.dirty = true; self.select_page = M.SELECT_PAGE or 1
  elseif a == "continue" then
    if self.opts.archive_ready and not self.opts.archive_ready() then
      self._waiting_continue = true
      self.toast = '正在读取最近保存的关卡…'
      self.toast_until = self.now + 3
      self.dirty = true
      return self.effects
    end
    local last = self.opts.last_level and self.opts.last_level() or nil
    print('[727] 首页继续 '..tostring(last))
    if last and self.opts.on_pick_level then
      self.screen = nil
      self._continue_requested = true
      self.opts.on_pick_level(last)
      self._continue_requested = nil
    else
      self.toast = "还没有游玩记录，先从「选关」开始吧"
      self.toast_until = self.now + M.TOAST_SECONDS    
      self.screen = "select"
    end
    self.dirty = true
  elseif a == "shop" or a == "bag" then
    if self.screen == 'home' then self.screen=a; self.econ_pick=nil; self.econ_status=nil; self.dirty=true end
  elseif a == "clue_up" or a == "clue_down" then
    local rows = M.LAYOUT.clue_rows or 9
    local shown = math.min(#self.core:view().clues, M.LAYOUT.clue_max_visible)
    local maxscroll = math.max(0, shown - rows)
    local s = self.clue_scroll or 0
    if a == "clue_up" then s = s - 1 else s = s + 1 end
    if s < 0 then s = 0 end
    if s > maxscroll then s = maxscroll end
    if s ~= (self.clue_scroll or 0) then self:dismiss_action_confirm() end
    self.clue_scroll = s
    self.dirty = true
  elseif a == "focus_general" then
    pcall(function()
      if self.core ~= nil and type(self.core.clue_hint_general) == "function" then
        self.general_focus = true           
        self.general_hint = self.core:clue_hint_general(1)
      end
    end)
  elseif a == "focus_clue" then
    self.general_focus = nil              
    local ci = event.index
    if ci ~= nil then
      self:fx("clue." .. tostring(ci), M.EFFECTS.CLUE_IN)
    end
  elseif a == "back" then
    self.screen = "select"
    self.modal = nil
    self.dirty = true
    if self.opts.on_back then self.opts.on_back() end
  elseif a == "next_level" and self.opts.on_next_level then
    self.opts.on_next_level()
  end
  if self.modal ~= old_modal or self.screen ~= old_screen then self:dismiss_action_confirm() end
  self:_sync_clue_focus()
  self.dirty = true
  return self.effects
end
function Controller:can_settle()
  local session = self.opts and self.opts.settle_session
  -- 753(额外1)：若本关是重进历史已通存档且尚未改动重推（_resumed_solved_board），不算本局新通关，不解开 90 秒结算限制。
  if self.core.status == "solved" and not self._resumed_solved_board then
    if session then session.unlocked = true else self._settle_unlocked = true end
    return true
  end
  return (session and session.unlocked == true) or self._settle_unlocked == true
end
function Controller:settle_seconds_left()
  if self:can_settle() then return 0 end
  local session = self.opts and self.opts.settle_session
  return math.max(1, math.ceil(90 - (session and session.elapsed or self._settle_elapsed or 0)))
end
function Controller:tick(dt)
  if not (self.opts and self.opts.settle_session) and not self._settle_unlocked then
    if not self._settle_entered and self.screen == nil then self._settle_entered = true end
    if self._settle_entered then
      self._settle_elapsed = math.min(90, (self._settle_elapsed or 0) + math.max(0, dt or 0))
      if self._settle_elapsed >= 90 then self._settle_unlocked = true end
    end
  end
  local remaining = self:settle_seconds_left()
  if self._settle_display_second ~= remaining then
    self._settle_display_second = remaining
    if self.screen == "home" or self.screen == "select" or
       (self.modal and (self.modal.kind == "result" or self.modal.kind == "exit_menu")) then
      self.dirty = true
    end
  end
  self.now = (self.now or 0) + (dt or 0)
  if self.screen or self.modal then self._clue_tap=nil
  elseif self._clue_tap and self.now-self._clue_tap.time>DOUBLE_CLICK_SECONDS then self:_flush_clue_tap() end
  if self.hint635 and (self.screen~=nil or self.modal~=nil or
      (self.hint635.until_time and self.now>=self.hint635.until_time)) then self.hint635=nil end
  self._frame_n = (self._frame_n or 0) + 1    
  if self._verdict ~= nil then pcall(self._verdict_step, self) end    
  do
    local p = rawget(self, "_press")
    if p ~= nil then
      p.dt = (p.dt or 0) + (dt or 0)
      self:_hold_progress(p)
      p = self._press
    end
    if p ~= nil and p.fired ~= true and p.dt >= LONG_PRESS_SECONDS then
      p.fired = true
      pcall(function()
        if p.r ~= nil and p.c ~= nil then
          self:fx(self:cell_id(p.r, p.c) .. ".face", M.EFFECTS.SELECT)
          self.dirty = true
        end
      end)
    end
  end
  if self.toast ~= nil and self.toast_until ~= nil and self.now >= self.toast_until then
    self.toast = nil
    self.toast_until = nil
    self.dirty = true
  end
  -- 747（P1-2）：若存在灰层禁用曾写失败的网格项，玩家原地不动也会按 0.25→0.5→1.0s 自动重试直至全关；正常成功时表为 nil（0 开销）。
  if self._grid_gray_retry747 ~= nil and self.screen == nil then
    local now747 = self.now or 0
    local due_items = nil
    for item_r, ent in pairs(self._grid_gray_retry747) do
      if ent ~= nil and now747 >= (ent.next_t or 0) then
        due_items = due_items or {}
        due_items[#due_items + 1] = { item_r, ent.index, ent.pos }
      end
    end
    if due_items ~= nil then
      for i = 1, #due_items do
        local d = due_items[i]
        pcall(self._grid_disable_gray_raycast, self, d[1], d[2], d[3])
      end
    end
  end
  local elapsed = (self.core.elapsed or 0) + (dt or 0)
  self.core:set_elapsed(elapsed)
  if #self.effects > 0 then self.dirty = true end
end
local function rect_of(t) return { x = t.x, y = t.y, w = t.w, h = t.h } end
local function is_legacy_clue_id(id)
  if type(id) ~= "string" then return false end
  if id:sub(1, 5) == "clue." then return true end
  return id == "clues.up" or id == "clues.down" or id == "clues.track"
      or id == "clues.knob" or id == "clues.count" or id == "clues.more"
      or id == "clues.bar"
end
local hide_exact = {
  topbar=true, toolbar=true, left=true, board=true, right=true, toast=true,
  modal=true, intro=true, clues=true, selbar=true, ["tpl-container"]=true,
  ["hit.back"]=true, ["hit.submit"]=true, ["hit.redo"]=true, ["hit.undo"]=true,
  ["hit.hint"]=true, ["hit.ok"]=true, ["hit.no"]=true,
}
local hide_group = {clue=true, hud=true, tray=true, action=true, hex=true, selbtn=true, tpl=true}
local function apply_screen_hide(nodes, screen)
  if nodes == nil then return end
  local other = screen == "home" and "select" or "home"
  for i = 1, #nodes do
    local id = nodes[i].id
    local hide
    if screen == nil then
      hide = id:sub(1,4) == "home" or id:sub(1,6) == "select"
    else
      local dot = id:find(".", 1, true)
      local group = (dot and dot > 1) and id:sub(1, dot - 1) or nil
      hide = hide_exact[id] or hide_group[group] or group == other
          or (group == "room" and id:sub(1,11) == "room.label.")
    end
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    -- v6：显隐必须双向收口；旧版只写 false，返回当前页时不会恢复。
    local declared = nodes[i]._declared_visible
    if declared == nil then declared = nodes[i].visible ~= false end
    nodes[i]._declared_visible = declared
    nodes[i].visible = (not hide) and declared or false
  end
end
local function split_by_name(vm, txt)
  if type(vm) ~= "table" or type(vm.tray) ~= "table" then return nil, txt, nil, nil, nil end
  local best, bestIt = nil, nil
  for _, it in ipairs(vm.tray) do
    local nm = tostring(it.name or it.short or it.id or "")
    if nm ~= "" and txt:find(nm, 1, true) then
      if best == nil or #nm > #best then best, bestIt = nm, it end
    end
  end
  if best == nil then return nil, txt, nil, nil, nil end
  local at = txt:find(best, 1, true)
  local pre, post = txt:sub(1, at - 1), txt:sub(at + #best)
  return best, pre, post, bestIt and tostring(bestIt.id) or nil, bestIt and bestIt.portrait or nil
end
function Controller:toast_text()
  local t = self.toast
  if t == nil then return nil end
  t = tostring(t)
  if t == "" then return nil end
  return t
end
    local ICON_ASSETS = {
      { "hex.back",   100109, 63.6, 30, 64, 64, "back_confirm" },   
      { "hex.submit", 100110, 1448,   48,  70,  70, "submit"       },   
      { "hex.redo",   100126, 1448,  144,  70,  70, "restart"      },   
      { "hex.undo",   100127, 1448,  240,  70,  70, "undo"         },   
      { "hex.hint",   100120, 1448,  694,  70,  70, "hint"         },   
      { "hex.ok",     100102,  438,   52,  54,  54, "confirm_yes"  },   
      { "hex.no",     100101,  500,   52,  54,  54, "confirm_no"   },   
    }
    local CONFIRM_GAP = 8
    local CONFIRM_ANCHOR = {
      back    = { x = 347 + CONFIRM_GAP,                            y = 48  },   
      submit  = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 48  },   
      restart = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 144 },   
    }
function Controller:build_layout(ui_adapter)
  local vm = self.core:view()
  local L = M.LAYOUT
  local nodes = {}
  local furn_art = nil
  local furn_recs = nil
  local furn_tpl, furn_span, furn_offset = {}, {}, {}
  local level_id = nil         
  do
    local keys = {}
    for r = 1, vm.rows do
      keys[r] = {}
      for c = 1, vm.cols do
        keys[r][c] = Controller.object_key_of(vm, vm.cells[r][c]) or false
      end
    end
    local cur_lv = nil
    do
      local lv_list = self.opts.levels
      local arr = {}
      if type(lv_list) == "function" then arr = lv_list() or {}
      elseif type(lv_list) == "table" then arr = lv_list end
      local want = tostring(self.opts.current_level or "")
      for i = 1, #arr do
        if tostring(arr[i].id) == want then cur_lv = arr[i] break end
      end
    end
    furn_art = FurnArt.layout(vm, keys, cur_lv and cur_lv.room_names or nil)
    furn_art.kind_of = {}
    for r = 1, vm.rows do
      furn_art.kind_of[r] = {}
      for c = 1, vm.cols do
        local k = keys[r] and keys[r][c]
        furn_art.kind_of[r][c] = k and (k:match("^obj%.(.+)$") or k) or nil
      end
    end
    level_id = cur_lv and cur_lv.id or nil
    local TPL_KEY = {
      chair = "furn.chair", plant = tostring(level_id) == "case_001" and "furn.plant.2" or "furn.plant", statue = "furn.statue",
      shelf = "furn.shelf",
      table = { ["1"] = "furn.table", h2 = "furn.table.h2", v2 = "furn.table.v2" },
      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3",
                 L3a = "furn.rug.4", L3b = "furn.rug.5" },
    }
    for r = 1, vm.rows do
      furn_tpl[r], furn_span[r], furn_offset[r] = {}, {}, {}
      for c = 1, vm.cols do furn_tpl[r][c], furn_span[r][c], furn_offset[r][c] = false, false, false end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if p.anchor ~= nil then    
        local variant = "1"
        if kind == "carpet" and (p.variant == "L3a" or p.variant == "L3b") then
          variant = p.variant
        elseif (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end
        local tk = TPL_KEY[kind]
        if type(tk) == "table" then tk = tk[variant] end
        if tk ~= nil then
          local b = p.box or { r1 = p.anchor.r, r2 = p.anchor.r, c1 = p.anchor.c, c2 = p.anchor.c }
          furn_tpl[p.anchor.r][p.anchor.c] = tk
          furn_span[p.anchor.r][p.anchor.c] = { r = p.span_r or 1, c = p.span_c or 1 }
          furn_offset[p.anchor.r][p.anchor.c] = {
            dx = (b.c1 + b.c2) * 0.5 - p.anchor.c,
            dy = (b.r1 + b.r2) * 0.5 - p.anchor.r,
          }
        end
      end
    end
    furn_recs = {}
    for r = 1, vm.rows do
      furn_recs[r] = {}
      for c = 1, vm.cols do furn_recs[r][c] = nil end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if M.FURN_BAKED then break end    
      if false then
        local list = FurnRecords and FurnRecords[kind]
        if list ~= nil then
          local b = p.box
          local span_r = b.r2 - b.r1 + 1
          local span_c = b.c2 - b.c1 + 1
          local variant = "1"
          if span_c > 1 then variant = "h2"
          elseif span_r > 1 then variant = "v2" end
          local recs = list[variant]
          if recs ~= nil then
            local anchor = p.anchor
            local ox = (b.c1 + b.c2) * 0.5 - anchor.c    
            local oy = (b.r1 + b.r2) * 0.5 - anchor.r
            local out = {}
            for i = 1, #recs do
              local e = recs[i]
              out[i] = { e[1], e[2], e[3], e[4] + ox, e[5] + oy, e[6], e[7] }
            end
            furn_recs[anchor.r][anchor.c] = out
          end
        end
      end
    end
  end
  nodes[#nodes + 1] = {
    id = "root", kind = "container", parent = nil, visible = true,
    rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height },
    furn_level = (level_id and self.screen == nil) or false,
    baked_level = (M.FURN_BAKED and level_id and self.screen == nil) or false,
    pos_runtime = true,
  }
    local OBJECT_PALETTE_DISABLED = nil    
    local K = 6 / 5                                     
    local function D(v) return math.floor(v * K + 0.5) end
    local pend_action = (self.pending and self.pending.action) or nil
    local function key_box_canvas(action)
      local id = (action == "submit" and "hex.submit")
        or (action == "restart" and "hex.redo")
        or (action == "back" and "hex.back") or nil
      if id == nil or ui_adapter == nil or type(ui_adapter.find) ~= "function" then return nil end
      local ctrl = nil
      pcall(function() ctrl = ui_adapter:find(id) end)
      if ctrl == nil or ctrl.GetSizeDelta == nil or ctrl.GetAnchoredPosition == nil then return nil end
      local w, h, ax, ay = nil, nil, nil, nil
      pcall(function() w, h = ctrl:GetSizeDelta() end)
      pcall(function() ax, ay = ctrl:GetAnchoredPosition() end)
      if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
      if type(ax) ~= "number" or type(ay) ~= "number" then return nil end
      local cfg = ui_adapter.cfg or {}
      local cw = cfg.canvas_w or 1600
      local ch = cfg.canvas_h or 900
      local cx = cw * 0.5 + ax           
      local cy = ch * 0.5 + ay           
      return { x = cx - w * 0.5, y = (ch - cy) - h * 0.5, w = w, h = h }
    end
    local anchor = CONFIRM_ANCHOR[pend_action] or CONFIRM_ANCHOR.back
    do
      local kb = key_box_canvas(pend_action)
      if kb ~= nil then
        local cy2 = kb.y + (kb.h - 54) * 0.5
        if pend_action == "back" then
          anchor = { x = kb.x + kb.w + CONFIRM_GAP, y = cy2 }
        else
          anchor = { x = kb.x - CONFIRM_GAP - 54 - CONFIRM_GAP - 54, y = cy2 }
        end
      end
    end
    local icon_pending_on = (self.pending ~= nil)
    for i = 1, #ICON_ASSETS do
      local a = ICON_ASSETS[i]
      local is_confirm = (a[1] == "hex.ok" or a[1] == "hex.no")
      local ax, ay = a[3], a[4]
      if a[1] == "hex.ok" then ax, ay = anchor.x, anchor.y end
      if a[1] == "hex.no" then ax, ay = anchor.x + 54 + CONFIRM_GAP, anchor.y end
      local is_confirm_icon = (a[1] == "hex.ok" or a[1] == "hex.no")
      local vis = (not is_confirm) or icon_pending_on
      local rect = { x = D(ax), y = D(ay), w = D(a[5]), h = D(a[6]) }
      nodes[#nodes + 1] = {
        id = a[1], kind = "button", parent = "root",
        visible = vis,
        image_id = a[2],
        imageType = "Stretch",
        icon_template = true,           
        rect = rect,
        pos_runtime = is_confirm_icon or nil,
      }
      local is_confirm_hit = (a[1] == "hex.ok" or a[1] == "hex.no")
      nodes[#nodes + 1] = {
        id = "hit." .. a[1]:sub(5), kind = "button", parent = "root",
        visible = vis,
        event = { action = a[7] },
        icon_template = false,          
        rect = a[1]=='hex.back' and { x = 64, y = 17, w = 101, h = 115 } or rect,
        pos_runtime = is_confirm_hit or nil,
      }
    end
  local function push(n)
    if n.visible == nil then n.visible = true end
    nodes[#nodes + 1] = n
    return n
  end
  local function btn(id, parent, r, text, event, style, enabled)
    return push({ id = id, kind = "button", parent = parent, rect = r, text = text,
                  style = style or "stamp", enabled = (enabled ~= false), event = event,
                  settle_shift = (id == "modal.cancel") and 0 or nil })
  end
  local function push_settle_countdowns()
    local remaining = self:settle_seconds_left()
    local gate_text = tostring(remaining) .. "秒后可结算"
    for _, spec in ipairs({
      {"settle.btn.countdown", "root", (self.screen == "home" or self.screen == "select")},
      {"result.settle.countdown", "modal", self.modal and self.modal.kind == "result"},
      {"modal.settle.countdown", "modal", self.modal and self.modal.kind == "exit_menu"},
    }) do
      push({id=spec[1], kind="text", parent=spec[2], visible=spec[3] and remaining > 0 or false,
            text=gate_text, rect={x=0,y=0,w=240,h=40}})
    end
  end
  push({ id = "root", kind = "container", rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }, style = "screen" })
  push({ id = "stage", kind = "container", parent = "root", rect = rect_of(L.board), style = "stage" })
  push({ id = "topbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "topbar" })
  push({ id = "hud.title", kind = "text", parent = "topbar", rect = rect_of(L.title), text = vm.title, style = "title" })
  local function tool(id, label, mode, x)
    return push({ id = id, kind = "button", parent = "toolbar",
                  rect = { x = x, y = 26, w = 130, h = 52 }, text = label,
                  style = (vm.hud.mode == mode) and "tab.active" or "tab",
                  visible = (M.SHOW_TOOL_BUTTONS == true),
                  event = { action = "tool", mode = mode } })
  end
  if M.SHOW_TOOL_BUTTONS then
    tool("tool.place",  "放置",  "place",  840)
    tool("tool.x",      "X 标记", "x",      978)
    tool("tool.eraser", "橡皮擦", "eraser", 1116)
  end
  local RB = L.side_key.right_edge
  local PG = L.progress
  push({ id = "hud.progress", kind = "text", parent = "right",
         rect = { x = RB - 110 - PG.icon_gap - PG.num_w, y = PG.y, w = PG.num_w, h = PG.h },
         text = string.format("%d / %d", self:placed_count(vm), vm.piece_count),
         style = "stat" })
  push({ id = "hud.timer", kind = "text", parent = "topbar",
         rect = { x = 72, y = 216, w = 340, h = 56 },
         text = self:format_time(vm.hud.time), style = "stat" })
  push({ id = "clues", kind = "container", parent = "root", rect = rect_of(L.clues),
         style = "panel" })
  push({ id = "clues.bg", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         visible = (self.screen == nil) })
  push({ id = "clues.grid", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         visible = (self._grid_state ~= "off"),
         })
  local grid_on = (self._grid_state == "on")
  if grid_on then
    self:_grid_log("giveway", "网格视窗：老的一套线索控件**整段不进规划**（不建 / 不摆 / 不点亮 / "
      .. "连动效都不排队）—— 只藏起来不够：`clue.N.*` 这个名字会被按名字抓到已回收的列表项")
  end    
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
      .. "键盘(默认键)：方向键移动　F放置　空格笔记　Tab换工具　数字选人\n"
      .. "（键位可在按键设置里改，以你实际的为准）"
  elseif self.input_profile == "gamepad" then
    legend_text = "确认=笔记　按住=放置　肩键切换工具\n（手柄为兜底方案，推荐用键鼠或触屏）"
  end
  local n = math.max(vm.rows, vm.cols)
  local avail_w = L.board.w - 2 * L.ruler      
  local avail_h = L.board.h - 2 * L.ruler
  local pitch = math.floor(math.min(avail_w, avail_h) / n)
  local gap   = math.max(2, math.floor(pitch * 0.03))
  local cell  = pitch - gap
  local ruler = L.ruler
  local grid_w = n * pitch - gap
  local grid_h = n * pitch - gap
  local gx = L.board.x + ruler + math.floor((avail_w - grid_w) / 2)
  local gy = L.board.y + ruler + math.floor((avail_h - grid_h) / 2)
  if n > 0 then
    local lv_list = {}
    local opt_lv = self.opts.levels
    if type(opt_lv) == "function" then lv_list = opt_lv() or {}
    elseif type(opt_lv) == "table" then lv_list = opt_lv end
    local cur = nil
    local want = tostring(self.opts.current_level or "")
    for i = 1, #lv_list do
      if tostring(lv_list[i].id) == want then cur = lv_list[i] break end
    end
  end    
  local hint_set = nil
  do
    local fci = self.focused_clue
    if fci ~= nil and fci > 0 and self.core ~= nil
       and (self.core.clues == nil or fci > #self.core.clues) then
      pcall(function()
        local _gh = self.core:clue_hint_general(1)
        local _cnt = 0
        if _gh ~= nil and _gh.set ~= nil then for _ in pairs(_gh.set) do _cnt = _cnt + 1 end end
        if _cnt > 0 then hint_set = _gh.set end
      end)
      fci = nil
    end
    if fci == 0 and self.core ~= nil and type(self.core.clue_hint_general) == "function" then
      pcall(function()
        local _g0 = self.core:clue_hint_general(1)    
        if _g0 ~= nil and _g0.set ~= nil and next(_g0.set) ~= nil then hint_set = _g0.set end
      end)
    end
    if fci ~= nil and fci > 0 and self.core ~= nil and self.core.clue_hint ~= nil then
      local h = self.core:clue_hint(fci)
      if h ~= nil and h.set ~= nil and next(h.set) ~= nil then hint_set = h.set end
    end
  end
  for r = 1, vm.rows do
    for c = 1, vm.cols do
      local cd = vm.cells[r][c]
      local _note_val = nil
      local _note_src = nil
      local _resolve = Controller.letter_of
      if _note_val == nil then
        _note_val = mark_list_of((self.core and self.core.notes and self.core.notes[r]
          and self.core.notes[r][c]) or cd.notes, vm, _resolve)
        if _note_val ~= nil then _note_src = "标记(letter)" end
      end
      local _cnt = (cd.suspect ~= nil and 1 or 0) + (_note_val ~= nil and 1 or 0)
      self._note_src_sum = (self._note_src_sum or 0) + _cnt
      if (cd.suspect ~= nil or _note_val ~= nil) and (self._note_src_log or 0) < 12 and print then
        self._note_src_log = (self._note_src_log or 0) + 1
        local _shown = ""
        if type(_note_val) == "table" then _shown = table.concat(_note_val, " ")
        elseif _note_val ~= nil then _shown = tostring(_note_val) end
        if cd.suspect == nil then
          print("[murdoku] ★ 棋盘格下发：cell(" .. tostring(r) .. "," .. tostring(c)
            .. ") 【空格子·标记】note=" .. _shown
            .. "（★ 标记列表 = " .. tostring(_note_src or "无")
            .. " ✓ —— ★ 打的是人 ✓ 显示的是那个人的 `letter` ✓）")
        else
          print("[murdoku] ★ 棋盘格下发：cell(" .. tostring(r) .. "," .. tostring(c)
            .. ") suspect=" .. tostring(cd.suspect)
            .. " src=" .. tostring(_note_src or "无") .. " 值=" .. _shown)
        end
      end
      local style = "cell"
      if cd.state == "blocked" then style = "cell.blocked"
      elseif cd.state == "victim" then style = "cell.victim"
      elseif cd.state == "hint" then style = "cell.hint"
      elseif cd.state == "wrong" then style = "cell.wrong" end
      if cd.x then style = "cell.x" end
      if self.kb_active and self.kb ~= nil and self.kb.r == r and self.kb.c == c then
        style = "cell.cursor"
      end
      push({
        id = self:cell_id(r, c),
        kind = "button",
        parent = "stage",
        rect = { x = gx + (c - 1) * (cell + gap), y = gy + (r - 1) * (cell + gap), w = cell, h = cell },
        style = style,
        visible = (self.screen == nil),
        text = (self.opts.push_cell_text == true and (cd.name or "")) or nil,
        image = cd.suspect and Controller.portrait_of(vm, cd.suspect) or false,
        notes = _note_val or false,
        room = cd.room,
        furn = (function()
          local info = furn_art.cell[r] and furn_art.cell[r][c]
          if info == nil or info.els == nil then return false end
          if M.FURN_BAKED then
            local k = furn_art.kind_of and furn_art.kind_of[r] and furn_art.kind_of[r][c]
            if k ~= "table" and k ~= "shelf" and k ~= "carpet" then return false end
          end
          return info.els
        end)(),
        furn_anchor = (furn_art.cell[r] and furn_art.cell[r][c] and furn_art.cell[r][c].anchor) or false,
        furn_art = (furn_recs and furn_recs[r] and furn_recs[r][c]) or false,
        furn_tpl = (furn_tpl and furn_tpl[r] and furn_tpl[r][c]) or false,
        furn_span = (furn_span and furn_span[r] and furn_span[r][c]) or false,
        furn_offset = (furn_offset and furn_offset[r] and furn_offset[r][c]) or false,
        walls = cd.walls,
        doors = cd.doors,
        tint = Controller.room_color(cd.room),
      hint = (hint_set ~= nil and hint_set[r .. ":" .. c] == true),
        fit = math.floor(cell * M.SCALE + 0.5),
        occupiable = cd.occupiable,
        x_mark = cd.x,
        enabled = true,    
        event = { action = "click", r = r, c = c },
      })
    end
  end
  do
    push({ id = "labels", kind = "container", parent = "root", pos_runtime = true,
           rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height } })
    local in_level = (self.screen == nil or self.screen == "level")
    for i = 1, 7 do
      local lb = (in_level and furn_art.labels) and furn_art.labels[i] or nil
      local node = {
        id = "label." .. i,
        kind = "textbox",
        parent = "labels",
        pos_runtime = true,
        visible = (lb ~= nil),
        text = (lb ~= nil) and lb.text or "",
      }
      local rx, ry, rw, rh = 0, 0, 1, 1
      if lb ~= nil then
        local ac = lb.cell or { r = lb.box.r2, c = lb.box.c1 }
        rw, rh = math.floor(cell * 2.2), math.floor(cell * 0.40)
        rx = math.floor(gx + (ac.c - 1) * pitch + cell * 0.5 - rw * 0.5)
        ry = math.floor(gy + (ac.r - 1) * pitch + cell * 0.5 - rh * 0.5)
      end
      node.rect = { x = rx, y = ry, w = rw, h = rh }
      push(node)
    end
  end
  push({ id = "right", kind = "container", parent = "root", rect = rect_of(L.right), style = "panel.right" })
  local rx = L.right.x + 20
  local modal = self.modal
  if modal then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    push({ id = "game742.shade", parent = "root", kind = "image", rect = {x=-1920,y=-1080,w=5760,h=3240},
           visible = modal.kind == "exit_menu" or (modal.kind == "result" and modal.win == true) })
    push({ id = "modal", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })
    if modal.kind == "result" then
      push({ id = "result.bg", kind = "image", parent = "modal",
             rect = { x = mx, y = my, w = mw, h = mh }, image_id = 100001 })
      local got, total = self.core:score()
      local body = modal.message or ""
      if modal.win then body = body:gsub("^破案！", "") end
      local outcome = modal.outcome or (modal.win and "perfect" or "fail")
      local oi = (outcome == "perfect" and 1) or (outcome == "success" and 2) or 3
      local title_rect = { x = mx + 30, y = my + 40, w = mw - 60, h = 90 }
      push({ id = "modal.title", kind = "text", parent = "modal", rect = title_rect,
             text = " ", style = "modal.title" })
      local TITLES = { "恭喜完美破案", "恭喜成功破案", "破案失败" }
      for i = 1, 3 do
        push({ id = "result.title." .. i, kind = "text", parent = "modal", rect = title_rect,
               visible = (oi == i), text = TITLES[i], style = "modal.title" })
      end
      local win_n, win_idx = 4, nil
      do
        local lv = self.opts.levels
        if type(lv) == "function" then lv = lv() end
        if type(lv) == "table" and #lv > 0 then win_n = #lv end
        local want = tostring(self.opts.current_level or "")
        if type(lv) == "table" then
          for i = 1, #lv do
            if tostring(lv[i].id) == want then win_idx = i break end
          end
        end
      end
      local win_rect = { x = mx + 30, y = my + 140, w = mw - 60, h = 110 }
      push({ id = "win", kind = "container", parent = "modal", rect = win_rect })
      for i = 1, win_n do
        push({ id = "win." .. i, kind = "text", parent = "win", rect = win_rect,
               visible = false,
               text = (win_idx == i) and body or nil,
               style = "modal.body" })
      end
      local MSGS = { [1] = "全部当事人的位置均已摆对，完美通关！", [2] = "盗窃者已被抓获，但仍有位置摆错\n全部摆对，才算完美通关",
                     [3] = "盗窃者没有找对\n看看红圈的位置，再玩一次吧" }
      for i = 1, 3 do
        push({ id = "result.msg." .. i, kind = "text", parent = "modal", rect = win_rect,
               visible = (oi == i), text = MSGS[i], style = "modal.body" })
      end
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 140, w = mw - 60, h = 110 },
             visible = false, style = "modal.body" })
      local result_text = ""
      local result_time = self:format_time(self.result_seconds or vm.hud.time)
      if outcome == "perfect" then
        result_text = "完美 · " .. result_time
      elseif outcome == "success" then
        result_text = string.format("成功 · 误判%d人 · %s", (self._verdict and self._verdict.wrong) or math.max(0, total - got), result_time)
      end
      push({ id = "win.result", kind = "text", parent = "win",
             rect = { x = mx + 30, y = my + 262, w = mw - 60, h = 44 },
             visible = outcome ~= "fail", text = result_text, style = "muted" })
      push({ id = "modal.stats", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 262, w = mw - 60, h = 44 },
             visible = false, text = "", style = "muted" })
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("result.next", "modal", { x = kx, y = my + 350, w = kw, h = kh },
          "下一关", { action = "next_level" }, "stamp.primary")
      btn("result.exit", "modal", { x = kx, y = my + 446, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("result.home", "modal", { x = kx, y = my + 542, w = kw, h = kh },
          "再玩一次", { action = "replay" }, "stamp")
      btn("result.settle", "modal", { x = kx, y = my + 638, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary", self:can_settle())
      if (not self._result_art) and self.adapter ~= nil then
        self._result_art = true
        for _, bid in ipairs({ "result.next", "result.exit", "result.home", "result.settle" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          if bg == nil then pcall(function() bg = self.adapter:find(bid .. ".bg") end) end
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
          end
        end
      end
    elseif modal.kind == "exit_menu" then
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("modal.exit", "modal", { x = kx, y = my + 50, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("modal.save", "modal", { x = kx, y = my + 146, w = kw, h = kh },
          "仅存档", { action = "exit_menu_save" }, "stamp")
      btn("modal.settle", "modal", { x = kx, y = my + 242, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary", self:can_settle())
      local cancel = btn("modal.cancel", "modal", { x = kx, y = my + 338, w = kw, h = kh },
          "取消", { action = "close_modal" }, "tab")
      cancel.settle_shift = (self:settle_seconds_left() > 0) and 30 or 0
      if (not self._exit_menu_art) and self.adapter ~= nil then
        self._exit_menu_art = true
        for _, bid in ipairs({ "modal.exit", "modal.save", "modal.settle", "modal.cancel" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
          end
        end
      end
    elseif modal.kind == "share" then
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 30, w = mw - 60, h = 56 }, text = "分享棋局", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 110, w = mw - 60, h = 200 },
             text = "把这个码发给别人，对方可以还原你的棋盘：\n\n" .. tostring(modal.code), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "关闭",
          { action = "close_modal" }, "tab")
    elseif modal.kind == "levelselect" then
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
      text[#text + 1] = "玩法：把每个角色放到正确的位置上；摆满后点「提交」校验，通过即可指认凶手。"
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 100, w = mw - 60, h = 280 },
             text = table.concat(text, "\n\n"), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "知道了",
          { action = "close_modal" }, "tab")
    end
  end
    local FULL = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }
  push({ id = "home", kind = "container", parent = "root", rect = FULL,
         visible = (self.screen == "home"), pos_runtime = true })
  if self.screen ~= nil then
    if self.screen == "home" then
      push({ id = "home.title", kind = "text", parent = "root", visible = true,
             text = self:toast_text() or M.HOME_TITLE,
             rect = { x = 460, y = 140, w = 1000, h = 110 } })
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
    elseif self.screen == 'shop' then
      local pick=self.econ_pick
      local confirm=self.shop_confirm==true and pick~=nil
      local coins,clues,pending,_,positions=self.opts.wallet()
      pending=pending or ''
      local pos=pick=='position'
      local name=pick and (pos and '位置揭示券' or '线索核验券')
      local qty=pos and positions or clues
      local function count(v) return v==nil and '读取中' or tostring(v) end
      push({id='econ.ui742',parent='root',kind='container',rect={x=0,y=0,w=1920,h=1080},visible=true})
      push({id='econ.shop736.s0',parent='econ.ui742',kind='image',rect={x=-1920,y=-1080,w=5760,h=3240},visible=true})
      push({id='econ.shop736.s1',parent='econ.ui742',kind='image',rect={x=57,y=96,w=1807,h=938},visible=true})
      push({id='econ.shop736.s3',parent='econ.ui742',kind='image',rect={x=570,y=52,w=780,h=54},visible=true})
      push({id='econ.shop736.s39',parent='econ.ui742',kind='image',rect={x=536.0588745030457,y=66.05887450304571,w=67.88225099390857,h=67.88225099390857},visible=true})
      push({id='econ.shop736.s40',parent='econ.ui742',kind='image',rect={x=1316.0588745030457,y=66.05887450304571,w=67.88225099390857,h=67.88225099390857},visible=true})
      push({id='econ.shop736.s41',parent='econ.ui742',kind='image',rect={x=538.0588745030457,y=71.05887450304571,w=67.88225099390857,h=67.88225099390857},visible=true})
      push({id='econ.shop736.s42',parent='econ.ui742',kind='image',rect={x=1314.0588745030457,y=71.05887450304571,w=67.88225099390857,h=67.88225099390857},visible=true})
      push({id='econ.shop736.s4',parent='econ.ui742',kind='image',rect={x=572,y=57,w=776,h=50},visible=true})
      push({id='econ.shop736.s2',parent='econ.ui742',kind='image',rect={x=62,y=101,w=1797,h=928},visible=true})
      push({id='econ.shop736.s6',parent='econ.ui742',kind='image',rect={x=113,y=173,w=1039,h=802},visible=true})
      push({id='econ.shop736.s7',parent='econ.ui742',kind='image',rect={x=118,y=178,w=1029,h=792},visible=true})
      push({id='econ.shop736.s8',parent='econ.ui742',kind='image',rect={x=1187,y=173,w=622,h=802},visible=true})
      push({id='econ.shop736.s9',parent='econ.ui742',kind='image',rect={x=1192,y=178,w=612,h=792},visible=true})
      push({id='econ.shop736.s10',parent='econ.ui742',kind='image',rect={x=145,y=203,w=966,h=731},visible=true})
      push({id='econ.shop736.s11',parent='econ.ui742',kind='image',rect={x=150,y=208,w=956,h=721},visible=true})
      push({id='econ.shop736.s12',parent='econ.ui742',kind='image',rect={x=150,y=208,w=13,h=721},visible=true})
      push({id='econ.shop736.s13',parent='econ.ui742',kind='image',rect={x=479,y=208,w=13,h=721},visible=true})
      push({id='econ.shop736.s14',parent='econ.ui742',kind='image',rect={x=808,y=208,w=13,h=721},visible=true})
      push({id='econ.shop736.s15',parent='econ.ui742',kind='image',rect={x=145,y=427,w=966,h=32},visible=true})
      push({id='econ.shop736.s16',parent='econ.ui742',kind='image',rect={x=145,y=678,w=966,h=32},visible=true})
      push({id='econ.shop736.s17',parent='econ.ui742',kind='image',rect={x=448,y=203,w=31,h=731},visible=true})
      push({id='econ.shop736.s18',parent='econ.ui742',kind='image',rect={x=777,y=203,w=31,h=731},visible=true})
      push({id='econ.shop736.s19',parent='econ.ui742',kind='image',rect={x=145,y=432,w=966,h=22},visible=true})
      push({id='econ.shop736.s20',parent='econ.ui742',kind='image',rect={x=145,y=683,w=966,h=22},visible=true})
      push({id='econ.shop736.s21',parent='econ.ui742',kind='image',rect={x=453,y=203,w=21,h=731},visible=true})
      push({id='econ.shop736.s22',parent='econ.ui742',kind='image',rect={x=782,y=203,w=21,h=731},visible=true})
      push({id='econ.shop736.s108',parent='econ.ui742',kind='image',rect={x=150,y=208,w=298,h=219},visible=pick=='position'})
      push({id='econ.shop736.s109',parent='econ.ui742',kind='image',rect={x=150,y=208,w=13,h=219},visible=pick=='position'})
      push({id='econ.shop736.s123',parent='econ.ui742',kind='image',rect={x=479,y=208,w=298,h=219},visible=pick=='clue'})
      push({id='econ.shop736.s124',parent='econ.ui742',kind='image',rect={x=479,y=208,w=13,h=219},visible=pick=='clue'})
      push({id='econ.shop736.s37',parent='econ.ui742',kind='image',rect={x=1254,y=124,w=488,h=96},visible=true})
      push({id='econ.shop736.s38',parent='econ.ui742',kind='image',rect={x=1259,y=129,w=478,h=86},visible=true})
      push({id='econ.shop736.s43',parent='econ.ui742',kind='image',rect={x=1280,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s44',parent='econ.ui742',kind='image',rect={x=1280,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s45',parent='econ.ui742',kind='image',rect={x=1330.222,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s46',parent='econ.ui742',kind='image',rect={x=1330.222,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s47',parent='econ.ui742',kind='image',rect={x=1380.444,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s48',parent='econ.ui742',kind='image',rect={x=1380.444,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s49',parent='econ.ui742',kind='image',rect={x=1430.667,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s50',parent='econ.ui742',kind='image',rect={x=1430.667,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s51',parent='econ.ui742',kind='image',rect={x=1480.889,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s52',parent='econ.ui742',kind='image',rect={x=1480.889,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s53',parent='econ.ui742',kind='image',rect={x=1531.111,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s54',parent='econ.ui742',kind='image',rect={x=1531.111,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s55',parent='econ.ui742',kind='image',rect={x=1581.333,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s56',parent='econ.ui742',kind='image',rect={x=1581.333,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s57',parent='econ.ui742',kind='image',rect={x=1631.556,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s58',parent='econ.ui742',kind='image',rect={x=1631.556,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s59',parent='econ.ui742',kind='image',rect={x=1681.778,y=138.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s60',parent='econ.ui742',kind='image',rect={x=1681.778,y=202.5,w=34.222,h=3},visible=true})
      push({id='econ.shop736.s61',parent='econ.ui742',kind='image',rect={x=1270.5,y=148,w=3,h=16},visible=true})
      push({id='econ.shop736.s62',parent='econ.ui742',kind='image',rect={x=1722.5,y=148,w=3,h=16},visible=true})
      push({id='econ.shop736.s63',parent='econ.ui742',kind='image',rect={x=1270.5,y=180,w=3,h=16},visible=true})
      push({id='econ.shop736.s64',parent='econ.ui742',kind='image',rect={x=1722.5,y=180,w=3,h=16},visible=true})
      push({id='econ.shop736.anim.sheet',parent='econ.ui742',kind='container',rect={x=1212,y=244.8,w=561.6,h=636},visible=true})
      push({id='econ.shop736.card.border',parent='econ.shop736.anim.sheet',kind='image',rect={x=1209.6,y=242.4,w=566.4,h=640.8},visible=true})
      push({id='econ.shop736.card.face',parent='econ.shop736.anim.sheet',kind='image',rect={x=1212,y=244.8,w=561.6,h=636},visible=true})
      push({id='econ.shop736.anim.ptop',parent='econ.shop736.anim.sheet',kind='container',rect={x=1252.8,y=501.4,w=480,h=19.2},visible=true})
      push({id='econ.shop736.anim.pbot',parent='econ.shop736.anim.sheet',kind='container',rect={x=1252.8,y=836.4,w=480,h=19.2},visible=true})
      push({id='econ.shop736.anim.top',parent='econ.shop736.anim.sheet',kind='container',rect={x=1228.8,y=259.2,w=528,h=204},visible=true})
      push({id='econ.shop736.anim.bot',parent='econ.shop736.anim.sheet',kind='container',rect={x=1234.8,y=510,w=516,h=336},visible=true})
      push({id='econ.shop736.s65',parent='econ.shop736.anim.top',kind='image',rect={x=1239,y=268,w=214,h=187},visible=true})
      push({id='econ.shop736.s66',parent='econ.shop736.anim.sheet',kind='image',rect={x=1244,y=495,w=495,h=367},visible=true})
      push({id='econ.shop736.s67',parent='econ.shop736.anim.ptop',kind='image',rect={x=1255,y=506,w=10,h=10},visible=true})
      push({id='econ.shop736.s68',parent='econ.shop736.anim.pbot',kind='image',rect={x=1255,y=841,w=10,h=10},visible=true})
      push({id='econ.shop736.s69',parent='econ.shop736.anim.ptop',kind='image',rect={x=1717,y=506,w=10,h=10},visible=true})
      push({id='econ.shop736.s70',parent='econ.shop736.anim.pbot',kind='image',rect={x=1717,y=841,w=10,h=10},visible=true})
      push({id='econ.shop736.s71',parent='econ.ui742',kind='image',rect={x=1237,y=902,w=211,h=87},visible=true})
      push({id='econ.shop736.s72',parent='econ.ui742',kind='image',rect={x=1242,y=907,w=201,h=77},visible=true})
      push({id='econ.shop736.s73',parent='econ.ui742',kind='image',rect={x=1530,y=902,w=211,h=87},visible=true})
      push({id='econ.shop736.s74',parent='econ.ui742',kind='image',rect={x=1535,y=907,w=201,h=77},visible=true})
      push({id='econ.shop736.s75',parent='econ.ui742',kind='image',rect={x=1508,y=42,w=313,h=62},visible=true})
      push({id='econ.shop736.s76',parent='econ.ui742',kind='image',rect={x=1513,y=47,w=303,h=52},visible=true})
      push({id='econ.shop736.s77',parent='econ.ui742',kind='image',rect={x=1474.5,y=42,w=62,h=62},visible=true})
      push({id='econ.shop736.s78',parent='econ.ui742',kind='image',rect={x=1479.5,y=47,w=52,h=52},visible=true})
      push({id='econ.shop736.currency',parent='econ.ui742',kind='image',rect={x=1465,y=33,w=81,h=81},visible=true,shop_currency=true})
      push({id='econ.shop736.flag.shadow',parent='econ.ui742',kind='image',visible=true,rect={x=37.400001525878906,y=42.39999771118164,w=139.1999969482422,h=84.20000457763672}})
      push({id='econ.shop736.flag.outline',parent='econ.ui742',kind='image',visible=true,rect={x=31.549964904785156,y=31.60000228881836,w=152.6999969482422,h=90.79999542236328}})
      push({id='econ.shop736.flag.outline.tri.top',parent='econ.ui742',kind='image',visible=true,rect={x=145.29998779296875,y=31.50001335144043,w=78,h=45.39999771118164}})
      push({id='econ.shop736.flag.outline.tri.bottom',parent='econ.ui742',kind='image',visible=true,rect={x=145.29998779296875,y=76.9999828338623,w=78,h=45.39999771118164}})
      push({id='econ.shop736.flag.ribbon',parent='econ.ui742',kind='image',visible=true,rect={x=37.400001525878906,y=37.39999771118164,w=139.1999969482422,h=79.20000457763672}})
      push({id='econ.shop736.flag.ribbon.tri.top',parent='econ.ui742',kind='image',visible=true,rect={x=142.5999755859375,y=37.40001106262207,w=68,h=39.60000228881836}})
      push({id='econ.shop736.flag.ribbon.tri.bottom',parent='econ.ui742',kind='image',visible=true,rect={x=142.5999755859375,y=76.89998054504395,w=68,h=39.60000228881836}})
      push({id='econ.shop736.s82',parent='econ.ui742',kind='image',rect={x=76,y=45,w=64,h=64},visible=true})
      push({id='econ.shop736.shopname',parent='econ.ui742',kind='text',rect={x=645,y=64,w=630,h=84},visible=true,text='调查商城'})
      push({id='econ.shop736.s85',parent='econ.ui742',kind='image',rect={x=235.4,y=235,w=117.6,h=156},visible=true})
      push({id='econ.shop736.s86',parent='econ.ui742',kind='image',rect={x=240.2,y=229,w=116.39999999999999,h=163.2},visible=true})
      push({id='econ.shop736.s87',parent='econ.ui742',kind='image',rect={x=254.6,y=256.6,w=55.199999999999996,h=3.5999999999999996},visible=true})
      push({id='econ.shop736.s88',parent='econ.ui742',kind='image',rect={x=254.6,y=268.6,w=75.6,h=3.5999999999999996},visible=true})
      push({id='econ.shop736.s89',parent='econ.ui742',kind='image',rect={x=261.8,y=289,w=38.4,h=3.5999999999999996},visible=true})
      push({id='econ.shop736.s90',parent='econ.ui742',kind='image',rect={x=253.4,y=344.2,w=51.6,h=3.5999999999999996},visible=true})
      push({id='econ.shop736.s91',parent='econ.ui742',kind='image',rect={x=254.6,y=357.4,w=74.39999999999999,h=3.5999999999999996},visible=true})
      push({id='econ.shop736.s92',parent='econ.ui742',kind='image',rect={x=254.6,y=370.6,w=36,h=3.5999999999999996},visible=true})
      push({id='econ.shop736.s93',parent='econ.ui742',kind='image',rect={x=297.8,y=229,w=6,h=163.2},visible=true})
      push({id='econ.shop736.s94.edge',parent='econ.ui742',kind='image',rect={x=238.49999999999997,y=307.2,w=119.8,h=8},visible=true})
      push({id='econ.shop736.s94',parent='econ.ui742',kind='image',rect={x=238.99999999999997,y=308.59999999999997,w=118.8,h=5.2},visible=true})
      push({id='econ.shop736.s95',parent='econ.ui742',kind='image',rect={x=299,y=296.2,w=27.599999999999998,h=14.399999999999999},visible=true})
      push({id='econ.shop736.s96',parent='econ.ui742',kind='image',rect={x=302.6,y=298.6,w=18,h=7.199999999999999},visible=true})
      push({id='econ.shop736.s97.edge',parent='econ.ui742',kind='image',rect={x=302.1,y=310.8,w=29.8,h=6.8},visible=true})
      push({id='econ.shop736.s97',parent='econ.ui742',kind='image',rect={x=302.6,y=312.2,w=28.8,h=4},visible=true})
      push({id='econ.shop736.s98',parent='econ.ui742',kind='image',rect={x=564.4,y=229,w=126,h=170.4},visible=true})
      push({id='econ.shop736.s99',parent='econ.ui742',kind='image',rect={x=571.6,y=376.6,w=114,h=18},visible=true})
      push({id='econ.shop736.s100',parent='econ.ui742',kind='image',rect={x=565.6,y=230.2,w=120,h=148.79999999999998},visible=true})
      push({id='econ.shop736.s101',parent='econ.ui742',kind='image',rect={x=575.2,y=239.8,w=98.39999999999999,h=128.4},visible=true})
      push({id='econ.shop736.s102',parent='econ.ui742',kind='image',rect={x=578.8,y=243.4,w=91.2,h=121.19999999999999},visible=true})
      push({id='econ.shop736.s103',parent='econ.ui742',kind='image',rect={x=582.4,y=243.4,w=3.5999999999999996,h=121.19999999999999},visible=true})
      push({id='econ.shop736.s104',parent='econ.ui742',kind='image',rect={x=682,y=266,w=18,h=19.2},visible=true})
      push({id='econ.shop736.s104.top',parent='econ.ui742',kind='image',rect={x=691.6,y=266,w=16.8,h=9.6},visible=true})
      push({id='econ.shop736.s104.bottom',parent='econ.ui742',kind='image',rect={x=691.6,y=275.6,w=16.8,h=9.6},visible=true})
      push({id='econ.shop736.s105',parent='econ.ui742',kind='image',rect={x=592,y=264,w=76,h=76},visible=true})
      push({id='econ.shop736.s110',parent='econ.shop736.anim.top',kind='image',rect={x=1291.41,y=295.05,w=100.94,h=133.9},visible=pick=='position'})
      push({id='econ.shop736.s111',parent='econ.shop736.anim.top',kind='image',rect={x=1295.53,y=289.9,w=99.91,h=140.08},visible=pick=='position'})
      push({id='econ.shop736.s112',parent='econ.shop736.anim.top',kind='image',rect={x=1307.89,y=313.59,w=47.38,h=3.09},visible=pick=='position'})
      push({id='econ.shop736.s113',parent='econ.shop736.anim.top',kind='image',rect={x=1307.89,y=323.89,w=64.89,h=3.09},visible=pick=='position'})
      push({id='econ.shop736.s114',parent='econ.shop736.anim.top',kind='image',rect={x=1314.07,y=341.4,w=32.96,h=3.09},visible=pick=='position'})
      push({id='econ.shop736.s115',parent='econ.shop736.anim.top',kind='image',rect={x=1306.86,y=388.78,w=44.29,h=3.09},visible=pick=='position'})
      push({id='econ.shop736.s116',parent='econ.shop736.anim.top',kind='image',rect={x=1307.89,y=400.11,w=63.86,h=3.09},visible=pick=='position'})
      push({id='econ.shop736.s117',parent='econ.shop736.anim.top',kind='image',rect={x=1307.89,y=411.44,w=30.900000000000002,h=3.09},visible=pick=='position'})
      push({id='econ.shop736.s118',parent='econ.shop736.anim.top',kind='image',rect={x=1344.97,y=289.9,w=5.15,h=140.08},visible=pick=='position'})
      push({id='econ.shop736.s119.edge',parent='econ.shop736.anim.top',kind='image',rect={x=1294,y=356.88,w=102.97,h=7.15},visible=pick=='position'})
      push({id='econ.shop736.s119',parent='econ.shop736.anim.top',kind='image',rect={x=1294.5,y=358.28,w=101.97,h=4.3500000000000005},visible=pick=='position'})
      push({id='econ.shop736.s120',parent='econ.shop736.anim.top',kind='image',rect={x=1346,y=347.58,w=23.69,h=12.36},visible=pick=='position'})
      push({id='econ.shop736.s121',parent='econ.shop736.anim.top',kind='image',rect={x=1349.09,y=349.64,w=15.450000000000001,h=6.18},visible=pick=='position'})
      push({id='econ.shop736.s122.edge',parent='econ.shop736.anim.top',kind='image',rect={x=1348.5900000000001,y=359.96999999999997,w=25.72,h=6.12},visible=pick=='position'})
      push({id='econ.shop736.s122',parent='econ.shop736.anim.top',kind='image',rect={x=1349.0900000000001,y=361.36999999999995,w=24.72,h=3.3200000000000003},visible=pick=='position'})
      push({id='econ.shop736.s125',parent='econ.shop736.anim.top',kind='image',rect={x=1291.41,y=289.9,w=108.15,h=146.26},visible=pick=='clue'})
      push({id='econ.shop736.s126',parent='econ.shop736.anim.top',kind='image',rect={x=1297.59,y=416.59000000000003,w=97.85000000000001,h=15.450000000000001},visible=pick=='clue'})
      push({id='econ.shop736.s127',parent='econ.shop736.anim.top',kind='image',rect={x=1292.44,y=290.93,w=103,h=127.72},visible=pick=='clue'})
      push({id='econ.shop736.s128',parent='econ.shop736.anim.top',kind='image',rect={x=1300.68,y=299.17,w=84.46000000000001,h=110.21000000000001},visible=pick=='clue'})
      push({id='econ.shop736.s129',parent='econ.shop736.anim.top',kind='image',rect={x=1303.77,y=302.26,w=78.28,h=104.03},visible=pick=='clue'})
      push({id='econ.shop736.s130',parent='econ.shop736.anim.top',kind='image',rect={x=1306.86,y=302.26,w=3.09,h=104.03},visible=pick=='clue'})
      push({id='econ.shop736.s131',parent='econ.shop736.anim.top',kind='image',rect={x=1392.35,y=321.86,w=15.450000000000001,h=16.48},visible=pick=='clue'})
      push({id='econ.shop736.s131.top',parent='econ.shop736.anim.top',kind='image',rect={x=1400.59,y=321.86,w=14.42,h=8.24},visible=pick=='clue'})
      push({id='econ.shop736.s131.bottom',parent='econ.shop736.anim.top',kind='image',rect={x=1400.59,y=330.1,w=14.42,h=8.24},visible=pick=='clue'})
      push({id='econ.shop736.s132',parent='econ.shop736.anim.top',kind='image',rect={x=1316,y=321,w=65,h=65},visible=pick=='clue'})
      push({id='econ.shop736.wallet',parent='econ.ui742',kind='text',rect={x=1548,y=35,w=246,h=76},visible=true,text=count(coins)})
      push({id='econ.shop736.name',parent='econ.ui742',kind='text',rect={x=1269,y=131.5,w=459,h=80},visible=true,text=name or '道具名称'})
      push({id='econ.shop736.price',parent='econ.shop736.anim.top',kind='text',rect={x=1468,y=280,w=255,h=65},visible=true,text=pick and (SHOP_PRICE[pick]..' 调查币') or ''})
      push({id='econ.shop736.owned',parent='econ.shop736.anim.top',kind='text',rect={x=1468,y=356,w=255,h=62},visible=true,text=pick and ('持有 '..count(qty)..' 张') or ''})
      push({id='econ.shop736.desc',parent='econ.shop736.anim.bot',kind='text',rect={x=1262,y=535,w=461,h=197},visible=true,text=pick and (pos and '选中一名人物，将其棋子摆到正确位置。' or '选中一条线索，核验其真假。') or '选择左侧的道具查看用途。'})
      push({id='econ.shop736.status',parent='econ.shop736.anim.bot',kind='text',rect={x=1262,y=726,w=461,h=116},visible=true,text=(pending~='' and pending) or self.econ_status or (pick and '本案免费提示用完后可使用。' or '')})
      push({id='econ.shop736.cancel',parent='econ.ui742',kind='text',rect={x=1247,y=914,w=191,h=60},visible=true,text='取消'})
      push({id='econ.shop736.purchase',parent='econ.ui742',kind='text',rect={x=1540,y=914,w=191,h=60},visible=true,text='购买'})
      push({id='econ.shop736.hit.position',parent='econ.ui742',kind='cursor',rect={x=145,y=203,w=308,h=229},visible=not confirm,event={action='store_position'}})
      push({id='econ.shop736.hit.clue',parent='econ.ui742',kind='cursor',rect={x=474,y=203,w=308,h=229},visible=not confirm,event={action='store_clue'}})
      push({id='econ.shop736.hit.leave',parent='econ.ui742',kind='cursor',rect={x=29,y=30,w=198,h=100},visible=not confirm,event={action='store_leave'}})
      push({id='econ.shop736.hit.clear',parent='econ.ui742',kind='cursor',rect={x=1237,y=902,w=211,h=87},visible=not confirm,event={action='store_clear'}})
      push({id='econ.shop736.hit.purchase',parent='econ.ui742',kind='cursor',rect={x=1530,y=902,w=211,h=87},visible=not confirm,event={action='store_purchase'}})
      push({id='econ.shop736.s148',parent='econ.ui742',kind='image',rect={x=-1920,y=-1080,w=5760,h=3240},visible=confirm})
      push({id='econ.shop736.s149',parent='econ.ui742',kind='image',rect={x=551,y=322,w=818,h=430},visible=confirm})
      push({id='econ.shop736.s150',parent='econ.ui742',kind='image',rect={x=556,y=327,w=808,h=420},visible=confirm})
      push({id='econ.shop736.question',parent='econ.ui742',kind='text',rect={x=598,y=370,w=724,h=85},visible=confirm,text='购买'..(name or '')..'？'})
      push({id='econ.shop736.amount',parent='econ.ui742',kind='text',rect={x=608,y=472,w=704,h=61},visible=confirm,text=pick and ('花费 '..SHOP_PRICE[pick]..' 调查币　·　购买 1 张') or ''})
      push({id='econ.shop736.s153',parent='econ.ui742',kind='image',rect={x=641,y=596,w=276,h=81},visible=confirm})
      push({id='econ.shop736.s154',parent='econ.ui742',kind='image',rect={x=646,y=601,w=266,h=71},visible=confirm})
      push({id='econ.shop736.s155',parent='econ.ui742',kind='image',rect={x=1003,y=596,w=276,h=81},visible=confirm})
      push({id='econ.shop736.s156',parent='econ.ui742',kind='image',rect={x=1008,y=601,w=266,h=71},visible=confirm})
      push({id='econ.shop736.no',parent='econ.ui742',kind='text',rect={x=651,y=608,w=256,h=54},visible=confirm,text='我再想想'})
      push({id='econ.shop736.yes',parent='econ.ui742',kind='text',rect={x=1013,y=608,w=256,h=54},visible=confirm,text='确认购买'})
      push({id='econ.shop736.hit.no',parent='econ.ui742',kind='cursor',rect={x=641,y=596,w=276,h=81},visible=confirm,event={action='store_no'}})
      push({id='econ.shop736.hit.yes',parent='econ.ui742',kind='cursor',rect={x=1003,y=596,w=276,h=81},visible=confirm,event={action='store_yes'}})
    elseif self.screen == 'bag' then
      local coins,clues,pending,last,positions,pos_last,posFirst=self.opts.wallet()
      pending=pending or ''
      local hasClue,hasPos=(clues or 0)>0,(positions or 0)>0
      local slotOf={}
      local nextSlot=0
      local function put(key,owned)
        if owned then slotOf[key]=nextSlot; nextSlot=nextSlot+1 end
      end
      if posFirst then put('position',hasPos); put('clue',hasClue)
      else put('clue',hasClue); put('position',hasPos) end
      local function cellX(key) return 186+(slotOf[key] or 0)*330 end
      local function cellY(key) return 222 end
      local function cellWidth(key) return 272 end
      local pick=(hasClue and self.econ_pick=='clue' and 'clue') or (hasPos and self.econ_pick=='position' and 'position') or nil
      local history=''
      if pick~='clue' and pos_last and pos_last~='-' then
        local c,id,r,col=pos_last:match('^case_00(%d):([^:]+):(%d+):(%d+)$')
        if c then history='上次揭示：案件 '..c..' · '..id..' 第'..r..'行第'..col..'列' end
      end
      if history=='' and pick~='position' and last and last~='-' then history='上次线索核验：'..(last:sub(-1)=='1' and '真' or '假') end



























































      push({id='econ.ui742',parent='root',kind='container',rect={x=0,y=0,w=1920,h=1080},visible=true})
      push({id='econ.bag741.desk',parent='econ.ui742',kind='image',rect={x=-1920,y=-1080,w=5760,h=3240},visible=true})
      push({id='econ.bag741.desk.left',parent='econ.ui742',kind='image',rect={x=1167.946,y=399.032,w=1470,h=732},visible=true})
      push({id='econ.bag741.desk.left.face',parent='econ.ui742',kind='image',rect={x=1172.946,y=404.032,w=1460,h=722},visible=true})
      push({id='econ.bag741.desk.lower',parent='econ.ui742',kind='image',rect={x=-19.464,y=253.864,w=1232,h=686},visible=true})
      push({id='econ.bag741.desk.gold.upper',parent='econ.ui742',kind='image',rect={x=-14.464,y=258.864,w=1222,h=676},visible=true})
      push({id='econ.bag741.desk.gold.lower',parent='econ.ui742',kind='image',rect={x=-34.241,y=260.278,w=1222,h=398},visible=true})
      push({id='econ.bag741.desk.gold.end',parent='econ.ui742',kind='image',rect={x=-38.414,y=290.222,w=1165,h=3},visible=true})
      push({id='econ.bag741.desk.gold.fold',parent='econ.ui742',kind='image',rect={x=7.97,y=612.905,w=1165,h=3},visible=true})
      push({id='econ.bag741.desk.right',parent='econ.ui742',kind='image',rect={x=-9.311,y=371.23,w=3,h=329},visible=true})
      push({id='econ.bag741.desk.right.face',parent='econ.ui742',kind='image',rect={x=1138.804,y=177.044,w=3,h=358},visible=true})
      push({id='econ.bag741.lid.edge',parent='econ.ui742',kind='image',rect={x=-149,y=-193,w=588,h=362},visible=true})
      push({id='econ.bag741.lid.leather',parent='econ.ui742',kind='image',rect={x=1481,y=-193,w=588,h=362},visible=true})
      push({id='econ.bag741.lid.lining',parent='econ.ui742',kind='image',rect={x=145,y=-193,w=1630,h=362},visible=true})
      push({id='econ.bag741.lid.toplight',parent='econ.ui742',kind='image',rect={x=-131,y=-186,w=548,h=339},visible=true})
      push({id='econ.bag741.lid.seam',parent='econ.ui742',kind='image',rect={x=1503,y=-186,w=548,h=339},visible=true})
      push({id='econ.bag741.lid.innerlip',parent='econ.ui742',kind='image',rect={x=143,y=-186,w=1634,h=339},visible=true})
      push({id='econ.bag741.lid.joint',parent='econ.ui742',kind='image',rect={x=-88,y=-167,w=484,h=312},visible=true})
      push({id='econ.bag741.lid.hinge0',parent='econ.ui742',kind='image',rect={x=1524,y=-167,w=484,h=312},visible=true})
      push({id='econ.bag741.lid.hingelight0',parent='econ.ui742',kind='image',rect={x=154,y=-167,w=1612,h=312},visible=true})
      push({id='econ.bag741.lid.hinge1',parent='econ.ui742',kind='image',rect={x=-72,y=-162,w=464,h=299},visible=true})
      push({id='econ.bag741.lid.hingelight1',parent='econ.ui742',kind='image',rect={x=1525,y=-162,w=450,h=299},visible=true})
      push({id='econ.bag741.case.middle',parent='econ.ui742',kind='image',rect={x=160,y=-162,w=1590,h=299},visible=true})
      push({id='econ.bag741.case.cross',parent='econ.ui742',kind='image',rect={x=163,y=-150,w=164,h=283},visible=true})
      push({id='econ.bag741.case.corner0',parent='econ.ui742',kind='image',rect={x=1593,y=-150,w=164,h=283},visible=true})
      push({id='econ.bag741.case.corner1',parent='econ.ui742',kind='image',rect={x=245,y=-150,w=1430,h=283},visible=true})
      push({id='econ.bag741.case.corner2',parent='econ.ui742',kind='image',rect={x=174,y=-144,w=160,h=268},visible=true})
      push({id='econ.bag741.case.corner3',parent='econ.ui742',kind='image',rect={x=1586,y=-144,w=160,h=268},visible=true})
      push({id='econ.bag741.leather.middle',parent='econ.ui742',kind='image',rect={x=254,y=-144,w=1412,h=268},visible=true})
      push({id='econ.bag741.leather.cross',parent='econ.ui742',kind='image',rect={x=155,y=139,w=28,h=14},visible=true})
      push({id='econ.bag741.leather.corner0',parent='econ.ui742',kind='image',rect={x=1737,y=139,w=28,h=14},visible=true})
      push({id='econ.bag741.leather.corner1',parent='econ.ui742',kind='image',rect={x=169,y=139,w=1582,h=14},visible=true})
      push({id='econ.bag741.leather.corner2',parent='econ.ui742',kind='image',rect={x=162,y=139,w=14,h=5},visible=true})
      push({id='econ.bag741.leather.corner3',parent='econ.ui742',kind='image',rect={x=1744,y=139,w=14,h=5},visible=true})
      push({id='econ.bag741.inner.seam',parent='econ.ui742',kind='image',rect={x=169,y=139,w=1582,h=5},visible=true})
      push({id='econ.bag741.left.wall',parent='econ.ui742',kind='image',rect={x=425,y=143,w=8,h=25},visible=true})
      push({id='econ.bag741.right.wall',parent='econ.ui742',kind='image',rect={x=551,y=143,w=8,h=25},visible=true})
      push({id='econ.bag741.center.edge',parent='econ.ui742',kind='image',rect={x=429,y=143,w=126,h=25},visible=true})
      push({id='econ.bag741.center.lip',parent='econ.ui742',kind='image',rect={x=431,y=149,w=122,h=11},visible=true})
      push({id='econ.bag741.slot.0.0.shadow',parent='econ.ui742',kind='image',rect={x=434,y=148,w=30,h=12},visible=true})
      push({id='econ.bag741.slot.0.0.floor',parent='econ.ui742',kind='image',rect={x=436,y=149,w=26,h=3},visible=true})
      push({id='econ.bag741.slot.0.1.shadow',parent='econ.ui742',kind='image',rect={x=468,y=148,w=48,h=12},visible=true})
      push({id='econ.bag741.slot.0.1.floor',parent='econ.ui742',kind='image',rect={x=470,y=149,w=44,h=3},visible=true})
      push({id='econ.bag741.slot.0.2.shadow',parent='econ.ui742',kind='image',rect={x=520,y=148,w=30,h=12},visible=true})
      push({id='econ.bag741.slot.0.2.floor',parent='econ.ui742',kind='image',rect={x=522,y=149,w=26,h=3},visible=true})
      push({id='econ.bag741.slot.1.0.shadow',parent='econ.ui742',kind='image',rect={x=1361,y=143,w=8,h=25},visible=true})
      push({id='econ.bag741.slot.1.0.floor',parent='econ.ui742',kind='image',rect={x=1487,y=143,w=8,h=25},visible=true})
      push({id='econ.bag741.slot.1.1.shadow',parent='econ.ui742',kind='image',rect={x=1365,y=143,w=126,h=25},visible=true})
      push({id='econ.bag741.slot.1.1.floor',parent='econ.ui742',kind='image',rect={x=1367,y=149,w=122,h=11},visible=true})
      push({id='econ.bag741.slot.1.2.shadow',parent='econ.ui742',kind='image',rect={x=1370,y=148,w=30,h=12},visible=true})
      push({id='econ.bag741.slot.1.2.floor',parent='econ.ui742',kind='image',rect={x=1372,y=149,w=26,h=3},visible=true})
      push({id='econ.bag741.slot.0.1.selected',parent='econ.ui742',kind='image',rect={x=1404,y=148,w=48,h=12},visible=true})
      push({id='econ.bag741.slot.0.2.selected',parent='econ.ui742',kind='image',rect={x=1406,y=149,w=44,h=3},visible=true})
      push({id='econ.bag741.right.floor',parent='econ.ui742',kind='image',rect={x=1456,y=148,w=30,h=12},visible=true})
      push({id='econ.bag741.clasp.0.edge',parent='econ.ui742',kind='image',rect={x=1458,y=149,w=26,h=3},visible=true})
      push({id='econ.bag741.clasp.0.strap',parent='econ.ui742',kind='image',rect={x=139,y=172,w=1642,h=774},visible=true})
      push({id='econ.bag741.clasp.0.stud',parent='econ.ui742',kind='image',rect={x=151,y=160,w=1618,h=12},visible=true})
      push({id='econ.bag741.clasp.1.edge',parent='econ.ui742',kind='image',rect={x=139,y=160,w=24,h=24},visible=true})
      push({id='econ.bag741.clasp.1.strap',parent='econ.ui742',kind='image',rect={x=1757,y=160,w=24,h=24},visible=true})
      push({id='econ.bag741.clasp.1.stud',parent='econ.ui742',kind='image',rect={x=245,y=946,w=1430,h=106},visible=true})
      push({id='econ.bag741.art742.shell.b0',parent='econ.ui742',kind='image',rect={x=139,y=840,w=212,h=212},visible=true})
      push({id='econ.bag741.art742.shell.b1',parent='econ.ui742',kind='image',rect={x=1569,y=840,w=212,h=212},visible=true})
      push({id='econ.bag741.art742.hide.body',parent='econ.ui742',kind='image',rect={x=146,y=175,w=1628,h=770},visible=true})
      push({id='econ.bag741.art742.hide.t',parent='econ.ui742',kind='image',rect={x=154,y=167,w=1612,h=8},visible=true})
      push({id='econ.bag741.art742.hide.t0',parent='econ.ui742',kind='image',rect={x=146,y=167,w=16,h=16},visible=true})
      push({id='econ.bag741.art742.hide.t1',parent='econ.ui742',kind='image',rect={x=1758,y=167,w=16,h=16},visible=true})
      push({id='econ.bag741.art742.hide.b',parent='econ.ui742',kind='image',rect={x=245,y=945,w=1430,h=99},visible=true})
      push({id='econ.bag741.art742.hide.b0',parent='econ.ui742',kind='image',rect={x=146,y=846,w=198,h=198},visible=true})
      push({id='econ.bag741.art742.hide.b1',parent='econ.ui742',kind='image',rect={x=1576,y=846,w=198,h=198},visible=true})
      push({id='econ.bag741.art742.inner.body',parent='econ.ui742',kind='image',rect={x=153,y=180,w=1610,h=753},visible=true})
      push({id='econ.bag741.art742.inner.t',parent='econ.ui742',kind='image',rect={x=160,y=173,w=1596,h=7},visible=true})
      push({id='econ.bag741.art742.inner.t0',parent='econ.ui742',kind='image',rect={x=153,y=173,w=14,h=14},visible=true})
      push({id='econ.bag741.art742.inner.t1',parent='econ.ui742',kind='image',rect={x=1749,y=173,w=14,h=14},visible=true})
      push({id='econ.bag741.art742.inner.b',parent='econ.ui742',kind='image',rect={x=209,y=933,w=1498,h=56},visible=true})
      push({id='econ.bag741.art742.inner.b0',parent='econ.ui742',kind='image',rect={x=153,y=877,w=112,h=112},visible=true})
      push({id='econ.bag741.art742.inner.b1',parent='econ.ui742',kind='image',rect={x=1651,y=877,w=112,h=112},visible=true})
      push({id='econ.bag741.art742.wall.body',parent='econ.ui742',kind='image',rect={x=160,y=184,w=1596,h=747},visible=true})
      push({id='econ.bag741.art742.wall.t',parent='econ.ui742',kind='image',rect={x=164,y=180,w=1588,h=4},visible=true})
      push({id='econ.bag741.art742.wall.t0',parent='econ.ui742',kind='image',rect={x=160,y=180,w=8,h=8},visible=true})
      push({id='econ.bag741.art742.wall.t1',parent='econ.ui742',kind='image',rect={x=1748,y=180,w=8,h=8},visible=true})
      push({id='econ.bag741.art742.wall.b',parent='econ.ui742',kind='image',rect={x=211,y=931,w=1494,h=51},visible=true})
      push({id='econ.bag741.art742.wall.b0',parent='econ.ui742',kind='image',rect={x=160,y=880,w=102,h=102},visible=true})
      push({id='econ.bag741.art742.wall.b1',parent='econ.ui742',kind='image',rect={x=1654,y=880,w=102,h=102},visible=true})
      push({id='econ.bag741.art742.slot00.side',parent='econ.ui742',kind='image',rect={x=160,y=180,w=27,h=361},visible=true})
      push({id='econ.bag741.art742.slot00.back.l',parent='econ.ui742',kind='image',rect={x=160,y=180,w=52,h=42},visible=true})
      push({id='econ.bag741.art742.slot00.back',parent='econ.ui742',kind='image',rect={x=186,y=180,w=272,h=42},visible=true})
      push({id='econ.bag741.art742.slot00.crease',parent='econ.ui742',kind='image',rect={x=186,y=219,w=272,h=4},visible=true})
      push({id='econ.bag741.art742.slot00.floor',parent='econ.ui742',kind='image',rect={x=186,y=222,w=272,h=319},visible=true})
      push({id='econ.bag741.art742.slot00.select.edge',parent='econ.ui742',kind='image',rect={x=186,y=222,w=272,h=319},visible=pick~=nil and slotOf[pick]==0})
      push({id='econ.bag741.art742.slot00.select.brass',parent='econ.ui742',kind='image',rect={x=191,y=227,w=262,h=309},visible=pick~=nil and slotOf[pick]==0})
      push({id='econ.bag741.art742.slot00.select.face',parent='econ.ui742',kind='image',rect={x=195,y=231,w=254,h=301},visible=pick~=nil and slotOf[pick]==0})
      push({id='econ.bag741.art742.slot01.side',parent='econ.ui742',kind='image',rect={x=490,y=180,w=27,h=361},visible=true})
      push({id='econ.bag741.art742.slot01.back.l',parent='econ.ui742',kind='image',rect={x=490,y=180,w=52,h=42},visible=true})
      push({id='econ.bag741.art742.slot01.back',parent='econ.ui742',kind='image',rect={x=516,y=180,w=272,h=42},visible=true})
      push({id='econ.bag741.art742.slot01.crease',parent='econ.ui742',kind='image',rect={x=516,y=219,w=272,h=4},visible=true})
      push({id='econ.bag741.art742.slot01.floor',parent='econ.ui742',kind='image',rect={x=516,y=222,w=272,h=319},visible=true})
      push({id='econ.bag741.art742.slot01.select.edge',parent='econ.ui742',kind='image',rect={x=516,y=222,w=272,h=319},visible=pick~=nil and slotOf[pick]==1})
      push({id='econ.bag741.art742.slot01.select.brass',parent='econ.ui742',kind='image',rect={x=521,y=227,w=262,h=309},visible=pick~=nil and slotOf[pick]==1})
      push({id='econ.bag741.art742.slot01.select.face',parent='econ.ui742',kind='image',rect={x=525,y=231,w=254,h=301},visible=pick~=nil and slotOf[pick]==1})
      push({id='econ.bag741.art742.slot02.side',parent='econ.ui742',kind='image',rect={x=820,y=180,w=27,h=361},visible=true})
      push({id='econ.bag741.art742.slot02.back.l',parent='econ.ui742',kind='image',rect={x=820,y=180,w=52,h=42},visible=true})
      push({id='econ.bag741.art742.slot02.back',parent='econ.ui742',kind='image',rect={x=846,y=180,w=272,h=42},visible=true})
      push({id='econ.bag741.art742.slot02.crease',parent='econ.ui742',kind='image',rect={x=846,y=219,w=272,h=4},visible=true})
      push({id='econ.bag741.art742.slot02.floor',parent='econ.ui742',kind='image',rect={x=846,y=222,w=272,h=319},visible=true})
      push({id='econ.bag741.art742.slot10.side',parent='econ.ui742',kind='image',rect={x=160,y=576,w=27,h=370},visible=true})
      push({id='econ.bag741.art742.slot10.back.l',parent='econ.ui742',kind='image',rect={x=160,y=576,w=52,h=42},visible=true})
      push({id='econ.bag741.art742.slot10.back',parent='econ.ui742',kind='image',rect={x=186,y=576,w=272,h=42},visible=true})
      push({id='econ.bag741.art742.slot10.crease',parent='econ.ui742',kind='image',rect={x=186,y=615,w=272,h=4},visible=true})
      push({id='econ.bag741.art742.slot10.corner',parent='econ.ui742',kind='image',rect={x=186,y=910,w=72,h=72},visible=true})
      push({id='econ.bag741.art742.slot10.lower',parent='econ.ui742',kind='image',rect={x=222,y=945,w=236,h=37},visible=true})
      push({id='econ.bag741.art742.slot10.floor',parent='econ.ui742',kind='image',rect={x=186,y=618,w=272,h=328},visible=true})
      push({id='econ.bag741.art742.slot11.side',parent='econ.ui742',kind='image',rect={x=490,y=576,w=27,h=406},visible=true})
      push({id='econ.bag741.art742.slot11.back.l',parent='econ.ui742',kind='image',rect={x=490,y=576,w=52,h=42},visible=true})
      push({id='econ.bag741.art742.slot11.back',parent='econ.ui742',kind='image',rect={x=516,y=576,w=272,h=42},visible=true})
      push({id='econ.bag741.art742.slot11.crease',parent='econ.ui742',kind='image',rect={x=516,y=615,w=272,h=4},visible=true})
      push({id='econ.bag741.art742.slot11.floor',parent='econ.ui742',kind='image',rect={x=516,y=618,w=272,h=364},visible=true})
      push({id='econ.bag741.art742.slot12.side',parent='econ.ui742',kind='image',rect={x=820,y=576,w=27,h=406},visible=true})
      push({id='econ.bag741.art742.slot12.back.l',parent='econ.ui742',kind='image',rect={x=820,y=576,w=52,h=42},visible=true})
      push({id='econ.bag741.art742.slot12.back',parent='econ.ui742',kind='image',rect={x=846,y=576,w=272,h=42},visible=true})
      push({id='econ.bag741.art742.slot12.crease',parent='econ.ui742',kind='image',rect={x=846,y=615,w=272,h=4},visible=true})
      push({id='econ.bag741.art742.slot12.floor',parent='econ.ui742',kind='image',rect={x=846,y=618,w=272,h=364},visible=true})
      push({id='econ.bag741.art742.shelf.edge',parent='econ.ui742',kind='image',rect={x=153,y=541,w=997,h=35},visible=true})
      push({id='econ.bag741.art742.shelf.face',parent='econ.ui742',kind='image',rect={x=160,y=548,w=982,h=20},visible=true})
      push({id='econ.bag741.art742.rib0',parent='econ.ui742',kind='image',rect={x=458,y=180,w=32,h=802},visible=true})
      push({id='econ.bag741.art742.rib0.leather',parent='econ.ui742',kind='image',rect={x=465,y=180,w=17,h=802},visible=true})
      push({id='econ.bag741.art742.rib1',parent='econ.ui742',kind='image',rect={x=788,y=180,w=32,h=802},visible=true})
      push({id='econ.bag741.art742.rib1.leather',parent='econ.ui742',kind='image',rect={x=795,y=180,w=17,h=802},visible=true})
      push({id='econ.bag741.art742.rib2',parent='econ.ui742',kind='image',rect={x=1118,y=180,w=32,h=802},visible=true})
      push({id='econ.bag741.art742.rib2.leather',parent='econ.ui742',kind='image',rect={x=1125,y=180,w=17,h=802},visible=true})
      push({id='econ.bag741.art742.bin.back',parent='econ.ui742',kind='image',rect={x=1150,y=180,w=605,h=29},visible=true})
      push({id='econ.bag741.art742.bin.left',parent='econ.ui742',kind='image',rect={x=1150,y=180,w=19,h=802},visible=true})
      push({id='econ.bag741.art742.bin.floor',parent='econ.ui742',kind='image',rect={x=1169,y=211,w=527,h=771},visible=true})
      push({id='econ.bag741.art742.tab0.body',parent='econ.ui742',kind='image',rect={x=428,y=994,w=118,h=43},visible=true})
      push({id='econ.bag741.art742.tab0.t',parent='econ.ui742',kind='image',rect={x=433,y=989,w=108,h=5},visible=true})
      push({id='econ.bag741.art742.tab0.t0',parent='econ.ui742',kind='image',rect={x=428,y=989,w=10,h=10},visible=true})
      push({id='econ.bag741.art742.tab0.t1',parent='econ.ui742',kind='image',rect={x=536,y=989,w=10,h=10},visible=true})
      push({id='econ.bag741.art742.tab0.b',parent='econ.ui742',kind='image',rect={x=435,y=1037,w=104,h=7},visible=true})
      push({id='econ.bag741.art742.tab0.b0',parent='econ.ui742',kind='image',rect={x=428,y=1030,w=14,h=14},visible=true})
      push({id='econ.bag741.art742.tab0.b1',parent='econ.ui742',kind='image',rect={x=532,y=1030,w=14,h=14},visible=true})
      push({id='econ.bag741.art742.tab0.skin.body',parent='econ.ui742',kind='image',rect={x=433,y=992,w=108,h=46},visible=true})
      push({id='econ.bag741.art742.tab0.skin.t',parent='econ.ui742',kind='image',rect={x=436,y=989,w=102,h=3},visible=true})
      push({id='econ.bag741.art742.tab0.skin.t0',parent='econ.ui742',kind='image',rect={x=433,y=989,w=6,h=6},visible=true})
      push({id='econ.bag741.art742.tab0.skin.t1',parent='econ.ui742',kind='image',rect={x=535,y=989,w=6,h=6},visible=true})
      push({id='econ.bag741.art742.tab0.skin.b',parent='econ.ui742',kind='image',rect={x=439,y=1038,w=96,h=6},visible=true})
      push({id='econ.bag741.art742.tab0.skin.b0',parent='econ.ui742',kind='image',rect={x=433,y=1032,w=12,h=12},visible=true})
      push({id='econ.bag741.art742.tab0.skin.b1',parent='econ.ui742',kind='image',rect={x=529,y=1032,w=12,h=12},visible=true})
      push({id='econ.bag741.art742.tab0.hole',parent='econ.ui742',kind='image',rect={x=476,y=1006,w=22,h=22},visible=true})
      push({id='econ.bag741.art742.tab1.body',parent='econ.ui742',kind='image',rect={x=1374,y=994,w=118,h=43},visible=true})
      push({id='econ.bag741.art742.tab1.t',parent='econ.ui742',kind='image',rect={x=1379,y=989,w=108,h=5},visible=true})
      push({id='econ.bag741.art742.tab1.t0',parent='econ.ui742',kind='image',rect={x=1374,y=989,w=10,h=10},visible=true})
      push({id='econ.bag741.art742.tab1.t1',parent='econ.ui742',kind='image',rect={x=1482,y=989,w=10,h=10},visible=true})
      push({id='econ.bag741.art742.tab1.b',parent='econ.ui742',kind='image',rect={x=1381,y=1037,w=104,h=7},visible=true})
      push({id='econ.bag741.art742.tab1.b0',parent='econ.ui742',kind='image',rect={x=1374,y=1030,w=14,h=14},visible=true})
      push({id='econ.bag741.art742.tab1.b1',parent='econ.ui742',kind='image',rect={x=1478,y=1030,w=14,h=14},visible=true})
      push({id='econ.bag741.art742.tab1.skin.body',parent='econ.ui742',kind='image',rect={x=1379,y=992,w=108,h=46},visible=true})
      push({id='econ.bag741.art742.tab1.skin.t',parent='econ.ui742',kind='image',rect={x=1382,y=989,w=102,h=3},visible=true})
      push({id='econ.bag741.art742.tab1.skin.t0',parent='econ.ui742',kind='image',rect={x=1379,y=989,w=6,h=6},visible=true})
      push({id='econ.bag741.art742.tab1.skin.t1',parent='econ.ui742',kind='image',rect={x=1481,y=989,w=6,h=6},visible=true})
      push({id='econ.bag741.art742.tab1.skin.b',parent='econ.ui742',kind='image',rect={x=1385,y=1038,w=96,h=6},visible=true})
      push({id='econ.bag741.art742.tab1.skin.b0',parent='econ.ui742',kind='image',rect={x=1379,y=1032,w=12,h=12},visible=true})
      push({id='econ.bag741.art742.tab1.skin.b1',parent='econ.ui742',kind='image',rect={x=1475,y=1032,w=12,h=12},visible=true})
      push({id='econ.bag741.art742.tab1.hole',parent='econ.ui742',kind='image',rect={x=1422,y=1006,w=22,h=22},visible=true})
      push({id='econ.bag741.paper.under',parent='econ.ui742',kind='image',rect={x=1189.6,y=210.4,w=490.5,h=739},visible=true})
      push({id='econ.bag741.anim.sheet',parent='econ.ui742',kind='container',rect={x=1189.7,y=223,w=490.2,h=739.6},visible=true})
      push({id='econ.bag741.paper.top',parent='econ.bag741.anim.sheet',kind='image',rect={x=1189.7,y=223,w=490.2,h=739.6},visible=true})
      push({id='econ.bag741.anim.ptop',parent='econ.bag741.anim.sheet',kind='container',rect={x=1242.8,y=502.4,w=384,h=19.2},visible=true})
      push({id='econ.bag741.anim.pbot',parent='econ.bag741.anim.sheet',kind='container',rect={x=1242.8,y=899.4,w=384,h=19.2},visible=true})
      push({id='econ.bag741.anim.top',parent='econ.bag741.anim.sheet',kind='container',rect={x=1206.8,y=251.4,w=456,h=222},visible=true})
      push({id='econ.bag741.anim.bot',parent='econ.bag741.anim.sheet',kind='container',rect={x=1230.8,y=513,w=408,h=396},visible=true})
      push({id='econ.bag741.paper.label',parent='econ.bag741.anim.sheet',kind='image',rect={x=1239,y=270,w=382,h=94},visible=true})
      push({id='econ.bag741.paper.body',parent='econ.bag741.anim.sheet',kind='image',rect={x=1241,y=498,w=385,h=426},visible=true})
      push({id='econ.bag741.paper.pin0',parent='econ.bag741.anim.ptop',kind='image',rect={x=1249,y=506,w=12,h=12},visible=true})
      push({id='econ.bag741.paper.pin1',parent='econ.bag741.anim.ptop',kind='image',rect={x=1606,y=506,w=12,h=12},visible=true})
      push({id='econ.bag741.paper.pin2',parent='econ.bag741.anim.pbot',kind='image',rect={x=1249,y=903,w=12,h=12},visible=true})
      push({id='econ.bag741.paper.pin3',parent='econ.bag741.anim.pbot',kind='image',rect={x=1606,y=903,w=12,h=12},visible=true})
      push({id='econ.bag741.return.flag.shadow',parent='econ.ui742',kind='image',rect={x=37.4,y=42.4,w=139.2,h=84.2},visible=true})
      push({id='econ.bag741.return.flag.outline',parent='econ.ui742',kind='image',rect={x=31.55,y=31.6,w=152.7,h=90.8},visible=true})
      push({id='econ.bag741.return.flag.outline.tri.top',parent='econ.ui742',kind='image',rect={x=145.3,y=31.5,w=78,h=45.4},visible=true})
      push({id='econ.bag741.return.flag.outline.tri.bottom',parent='econ.ui742',kind='image',rect={x=145.3,y=77,w=78,h=45.4},visible=true})
      push({id='econ.bag741.return.flag.ribbon',parent='econ.ui742',kind='image',rect={x=37.4,y=37.4,w=139.2,h=79.2},visible=true})
      push({id='econ.bag741.return.flag.ribbon.tri.top',parent='econ.ui742',kind='image',rect={x=142.6,y=37.4,w=68,h=39.6},visible=true})
      push({id='econ.bag741.return.flag.ribbon.tri.bottom',parent='econ.ui742',kind='image',rect={x=142.6,y=76.9,w=68,h=39.6},visible=true})
      push({id='econ.bag741.return.s82',parent='econ.ui742',kind='image',rect={x=76,y=45,w=64,h=64},visible=true})
      push({id='econ.bag741.item.s85',parent='econ.ui742',kind='image',rect={x=cellX('position')+(58.148)*(cellWidth('position')/308),y=cellY('position')+159.5+(-127.46)*(cellWidth('position')/308),w=184.632*(cellWidth('position')/308),h=244.92*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s86',parent='econ.ui742',kind='image',rect={x=cellX('position')+(65.684)*(cellWidth('position')/308),y=cellY('position')+159.5+(-136.88)*(cellWidth('position')/308),w=182.748*(cellWidth('position')/308),h=256.224*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s87',parent='econ.ui742',kind='image',rect={x=cellX('position')+(88.292)*(cellWidth('position')/308),y=cellY('position')+159.5+(-93.548)*(cellWidth('position')/308),w=86.664*(cellWidth('position')/308),h=5.652*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s88',parent='econ.ui742',kind='image',rect={x=cellX('position')+(88.292)*(cellWidth('position')/308),y=cellY('position')+159.5+(-74.708)*(cellWidth('position')/308),w=118.692*(cellWidth('position')/308),h=5.652*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s89',parent='econ.ui742',kind='image',rect={x=cellX('position')+(99.596)*(cellWidth('position')/308),y=cellY('position')+159.5+(-42.68)*(cellWidth('position')/308),w=60.288*(cellWidth('position')/308),h=5.652*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s90',parent='econ.ui742',kind='image',rect={x=cellX('position')+(86.408)*(cellWidth('position')/308),y=cellY('position')+159.5+(43.984)*(cellWidth('position')/308),w=81.012*(cellWidth('position')/308),h=5.652*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s91',parent='econ.ui742',kind='image',rect={x=cellX('position')+(88.292)*(cellWidth('position')/308),y=cellY('position')+159.5+(64.708)*(cellWidth('position')/308),w=116.808*(cellWidth('position')/308),h=5.652*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s92',parent='econ.ui742',kind='image',rect={x=cellX('position')+(88.292)*(cellWidth('position')/308),y=cellY('position')+159.5+(85.432)*(cellWidth('position')/308),w=56.52*(cellWidth('position')/308),h=5.652*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s93',parent='econ.ui742',kind='image',rect={x=cellX('position')+(156.116)*(cellWidth('position')/308),y=cellY('position')+159.5+(-136.88)*(cellWidth('position')/308),w=9.42*(cellWidth('position')/308),h=256.224*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s94.edge',parent='econ.ui742',kind='image',rect={x=cellX('position')+(63.015)*(cellWidth('position')/308),y=cellY('position')+159.5+(-14.106)*(cellWidth('position')/308),w=188.086*(cellWidth('position')/308),h=12.56*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s94',parent='econ.ui742',kind='image',rect={x=cellX('position')+(63.8)*(cellWidth('position')/308),y=cellY('position')+159.5+(-11.908)*(cellWidth('position')/308),w=186.516*(cellWidth('position')/308),h=8.164*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s95',parent='econ.ui742',kind='image',rect={x=cellX('position')+(158)*(cellWidth('position')/308),y=cellY('position')+159.5+(-31.376)*(cellWidth('position')/308),w=43.332*(cellWidth('position')/308),h=22.608*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s96',parent='econ.ui742',kind='image',rect={x=cellX('position')+(163.652)*(cellWidth('position')/308),y=cellY('position')+159.5+(-27.608)*(cellWidth('position')/308),w=28.26*(cellWidth('position')/308),h=11.304*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s97.edge',parent='econ.ui742',kind='image',rect={x=cellX('position')+(162.867)*(cellWidth('position')/308),y=cellY('position')+159.5+(-8.454)*(cellWidth('position')/308),w=46.786*(cellWidth('position')/308),h=10.676*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s97',parent='econ.ui742',kind='image',rect={x=cellX('position')+(163.652)*(cellWidth('position')/308),y=cellY('position')+159.5+(-6.256)*(cellWidth('position')/308),w=45.216*(cellWidth('position')/308),h=6.28*(cellWidth('position')/308)},visible=hasPos})
      push({id='econ.bag741.item.s98',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(58.148)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-136.88)*(cellWidth('clue')/308),w=197.82*(cellWidth('clue')/308),h=267.528*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s99',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(69.452)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(94.852)*(cellWidth('clue')/308),w=178.98*(cellWidth('clue')/308),h=28.26*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s100',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(60.032)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-134.996)*(cellWidth('clue')/308),w=188.4*(cellWidth('clue')/308),h=233.616*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s101',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(75.104)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-119.924)*(cellWidth('clue')/308),w=154.488*(cellWidth('clue')/308),h=201.588*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s102',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(80.756)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-114.272)*(cellWidth('clue')/308),w=143.184*(cellWidth('clue')/308),h=190.284*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s103',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(86.408)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-114.272)*(cellWidth('clue')/308),w=5.652*(cellWidth('clue')/308),h=190.284*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s104',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(242.78)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-78.79)*(cellWidth('clue')/308),w=28.26*(cellWidth('clue')/308),h=30.144*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s104.top',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(257.852)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-78.79)*(cellWidth('clue')/308),w=26.376*(cellWidth('clue')/308),h=15.072*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s104.bottom',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(257.852)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-63.718)*(cellWidth('clue')/308),w=26.376*(cellWidth('clue')/308),h=15.072*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.item.s105',parent='econ.ui742',kind='image',rect={x=cellX('clue')+(101.48)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(-81.93)*(cellWidth('clue')/308),w=119.32*(cellWidth('clue')/308),h=119.32*(cellWidth('clue')/308)},visible=hasClue})
      push({id='econ.bag741.title',parent='econ.bag741.anim.top',kind='text',rect={x=1239,y=268,w=382,h=100},visible=true,text=pick and (pick=='clue' and '线索核验券' or '位置揭示券') or '调查背包'})
      push({id='econ.bag741.meta',parent='econ.bag741.anim.top',kind='text',rect={x=1214,y=376,w=442,h=93},visible=true,text=pick and ('持有 '..tostring(pick=='clue' and clues or positions)..' 张') or ('调查币　'..(coins==nil and '读取中' or tostring(coins)))})
      push({id='econ.bag741.desc',parent='econ.bag741.anim.bot',kind='text',rect={x=1261,y=539,w=345,h=163},visible=true,text=pick=='clue' and '选中一条线索，核验其真假。' or pick=='position' and '选中一名人物，将其棋子摆到正确位置。' or (pending~='' and pending) or (clues==nil or positions==nil) and '正在读取背包…' or (hasClue or hasPos) and '选择左侧的道具查看用途。' or '背包为空，可到调查商城购买道具。'})
      push({id='econ.bag741.usage',parent='econ.bag741.anim.bot',kind='text',rect={x=1261,y=701,w=345,h=117},visible=pick~=nil,text=pick and '本案免费提示用完后，可在提示菜单中用券。' or ''})
      push({id='econ.bag741.history',parent='econ.bag741.anim.bot',kind='text',rect={x=1261,y=820,w=345,h=77},visible=history~='',text=history})
      push({id='econ.bag741.qty.clue',parent='econ.ui742',kind='text',rect={x=cellX('clue')+(193)*(cellWidth('clue')/308),y=cellY('clue')+159.5+(119)*(cellWidth('clue')/308),w=102*(cellWidth('clue')/308),h=62*(cellWidth('clue')/308)},visible=hasClue,text='×'..tostring(clues or 0)})
      push({id='econ.bag741.hit.clue',parent='econ.ui742',kind='cursor',rect={x=cellX('clue'),y=cellY('clue'),w=cellWidth('clue'),h=319},visible=hasClue,event={action='econ_clue'}})
      push({id='econ.bag741.qty.position',parent='econ.ui742',kind='text',rect={x=cellX('position')+(193)*(cellWidth('position')/308),y=cellY('position')+159.5+(119)*(cellWidth('position')/308),w=102*(cellWidth('position')/308),h=62*(cellWidth('position')/308)},visible=hasPos,text='×'..tostring(positions or 0)})
      push({id='econ.bag741.hit.position',parent='econ.ui742',kind='cursor',rect={x=cellX('position'),y=cellY('position'),w=cellWidth('position'),h=319},visible=hasPos,event={action='econ_position'}})
      push({id='econ.bag741.hit.return',parent='econ.ui742',kind='cursor',rect={x=29,y=30,w=198,h=100},visible=true,event={action='econ_back'}})
    elseif self.screen == "select" then
      push({ id = "select.thumb.pool", kind = "container", parent = "root", visible = true,
             rect = FULL, pos_runtime = true })
        local list = {}
        local lv = self.opts.levels
        if type(lv) == "function" then list = lv() or {}
        elseif type(lv) == "table" then list = lv end
        local PER = 4
        local total = #list
        local pages = math.max(1, math.ceil(total / PER))
        local page = tonumber(self.select_page) or 1
        if page < 1 then page = 1 end
        if page > pages then page = pages end
        self.select_page = page           
        local lst_base = (page - 1) * PER
        push({ id = "select.title", kind = "text", parent = "root", visible = true, text = "选择关卡",
             rect = { x = 460, y = 80, w = 1000, h = 90 } })
      local BACK_RECT = { x = 76, y = 36, w = 77, h = 77 }
      push({ id = "select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT })
      push({ id = "hit.select.back", kind = "button", parent = "root", visible = true,
             rect = { x = 64, y = 17, w = 101, h = 115 },
             event = { action = "home" } })
        local ARROW = 62
        local PG_Y  = math.floor((1080 - ARROW) / 2)       
        local PR = { x = 60, y = PG_Y, w = ARROW, h = ARROW }
        local NX = { x = 1920 - 60 - ARROW, y = PG_Y, w = ARROW, h = ARROW }
        local NORMAL_TINT, DIM_TINT = 4294967295, 2147483647
        push({ id = "hit.select.prev", kind = "button", parent = "root", visible = true,
               rect = PR, event = { action = "select_page", delta = -1 } })
        push({ id = "hit.select.next", kind = "button", parent = "root", visible = true,
               rect = NX, event = { action = "select_page", delta = 1 } })
        push({ id = "select.page", kind = "text", parent = "root", visible = true,
               text = string.format("第 %d / %d 页", page, pages),
               rect = { x = 895, y = 952, w = 130, h = 70 } })
      local list = {}
      local lv = self.opts.levels
      if type(lv) == "function" then list = lv() or {}
      elseif type(lv) == "table" then list = lv end
        local CARD_W, CARD_H = 279, 388.8
        local CARD_GAP        = 54                          
        local CARD_STEP       = CARD_W + CARD_GAP           
        local CARD_X0         = 250                         
        local CARD_Y0         = 330
        for i = 1, PER do
          local it = list[lst_base + i]
        local r = { x = CARD_X0 + ((i - 1) % PER) * CARD_STEP, y = CARD_Y0,
                    w = CARD_W, h = CARD_H }
        r = self:editor_card_box(ui_adapter, "select.card." .. i, r)
        if it ~= nil then
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = true, pos_runtime = true,
                 rect = r, image = CARD_MAT, tint = CARD_TINT })
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, pos_runtime = true, event = { action = "pick_level", id = it.id } })
          local t = self:level_card_parts(it)
          push({ id = "select.card." .. i .. ".title", kind = "text", parent = "root",
                 visible = false, text = "", style = "card.title",
                 rect = { x = r.x + 16, y = r.y + 10, w = r.w - 32, h = 34 },
                 pos_runtime = true })
          -- 710：标题来自当前关卡数据；存档静态文本不能覆盖关卡名。
          push({ id = "select.card." .. i .. ".info", kind = "text", parent = "root",
                 visible = true, text = t.short, style = "card.name",
                 rect = { x = r.x + r.w * 0.045, y = r.y + r.h * 0.835,
                          w = r.w * 0.91, h = r.h * 0.15 },
                 pos_runtime = true })
          push({ id = "select.card." .. i .. ".result", kind = "text", parent = "root",
                 visible = t.result ~= "", text = t.result, pos_runtime = true,
                 rect = { x = r.x, y = r.y + r.h + 10 * (ui_adapter and ui_adapter._select715_scale or 1), w = math.max(r.w, 220 * (ui_adapter and ui_adapter._select715_scale or 1)), h = 72 * (ui_adapter and ui_adapter._select715_scale or 1) } })
          self:push_room_thumb(push, "select.card." .. i, it, r, "select.thumb.pool", ui_adapter and ui_adapter.cfg and ui_adapter.cfg.scale, ui_adapter and ui_adapter._select715_scale)
        else
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          for _, suf in ipairs({ ".title", ".info", ".result" }) do
            push({ id = "select.card." .. i .. suf, kind = "text", parent = "root", visible = false,
                   rect = { x = r.x, y = r.y, w = 1, h = 1 }, pos_runtime = true })
          end
          self:push_room_thumb(push, "select.card." .. i, nil, r, "select.thumb.pool")
        end
      end
    end
    for _, node in ipairs(nodes) do
      if node.id:match("^econ%.") then node.raycast = node.visible~=false and node.event ~= nil; if not node.id:match("%.anim%.") then node.pos_runtime=true end end
    end
    local show_settle = (self.screen == "home" or self.screen == "select")
    push({ id = "settle.btn", kind = "button", parent = "root",
           visible = show_settle,
           rect = { x = 1744.6, y = 298.8, w = 84, h = 84 },
           raycast = show_settle, enabled = self:can_settle(),
           event = { action = "settle_only" } })
    push_settle_countdowns()
    apply_screen_hide(nodes, self.screen)
    return nodes
  end
  push_settle_countdowns()
  apply_screen_hide(nodes, self.screen)
  return nodes
end
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
  local result = ""
  if type(p) == "table" and (p.outcome == "perfect" or p.outcome == "success") then
    local secs = math.max(0, math.floor(tonumber(p.seconds) or 0))
    local time = string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
    if p.outcome == "perfect" then result = "完美\n耗时 " .. time
    else result = string.format("成功 · 误判%d人\n耗时 %s", p.wrong or 0, time) end
  end
  -- UTF-8 的中点必须整体匹配，不能放进按字节匹配的字符集合。
  local short = title
  local first = string.find(title, "·", 1, true)
  if first then
    short = string.sub(title, first + #"·")
    local next_sep = string.find(short, "·", 1, true)
    if next_sep then short = string.sub(short, 1, next_sep - 1) end
    short = string.gsub(short, "^%s+", "")
  end
  short = string.gsub(short, "%s+$", "")
  return { title = title, short = short, info = table.concat(bits, "　"), result = result }
end
Controller.THUMB_POOL = {
  ".boardbg",
  ".cell.1.1",
  ".cell.1.2",
  ".cell.1.3",
  ".cell.1.4",
  ".cell.1.5",
  ".cell.1.6",
  ".cell.1.7",
  ".cell.2.1",
  ".cell.2.2",
  ".cell.2.3",
  ".cell.2.4",
  ".cell.2.5",
  ".cell.2.6",
  ".cell.2.7",
  ".cell.3.1",
  ".cell.3.2",
  ".cell.3.3",
  ".cell.3.4",
  ".cell.3.5",
  ".cell.3.6",
  ".cell.3.7",
  ".cell.4.1",
  ".cell.4.2",
  ".cell.4.3",
  ".cell.4.4",
  ".cell.4.5",
  ".cell.4.6",
  ".cell.4.7",
  ".cell.5.1",
  ".cell.5.2",
  ".cell.5.3",
  ".cell.5.4",
  ".cell.5.5",
  ".cell.5.6",
  ".cell.5.7",
  ".cell.6.1",
  ".cell.6.2",
  ".cell.6.3",
  ".cell.6.4",
  ".cell.6.5",
  ".cell.6.6",
  ".cell.6.7",
  ".cell.7.1",
  ".cell.7.2",
  ".cell.7.3",
  ".cell.7.4",
  ".cell.7.5",
  ".cell.7.6",
  ".cell.7.7",
  ".wall.1",
  ".wall.2",
  ".wall.3",
  ".wall.4",
  ".wall.5",
  ".wall.6",
  ".wall.7",
  ".wall.8",
  ".wall.9",
  ".wall.10",
  ".wall.11",
  ".wall.12",
  ".wall.13",
  ".wall.14",
  ".wall.15",
  ".wall.16",
  ".wall.17",
  ".door.1",
  ".door.2",
  ".door.3",
  ".door.4",
  ".door.5",
}
local ROOM_MAX = 6           
local WHITE_MAT = 100001     -- 703：cell 模板原有的无缺口纯色矩形     
function Controller:editor_card_box(a, id, plan_r)
  if a == nil or type(a.find) ~= "function" then return plan_r end
  local ctrl = nil
  -- 705：select.card.N 是旧点击区域；实际白框由 art647 的 paper 绘制。
  -- 先用可见白框，迟到时暂用旧区域；每次布局重新读取，不缓存回退位置。
  local slot = id:match("^select%.card%.(%d+)$")
  local visual = slot and ("art647.select.card." .. slot .. ".paper") or nil
  if visual then pcall(function() ctrl = a:find(visual) end) end
  local is_visual = ctrl ~= nil
  if ctrl == nil then pcall(function() ctrl = a:find(id) end) end
  if ctrl == nil or ctrl.GetSizeDelta == nil or ctrl.GetAnchoredPosition == nil then return plan_r end
  local w, h, ax, ay = nil, nil, nil, nil
  pcall(function() w, h = ctrl:GetSizeDelta() end)
  pcall(function() ax, ay = ctrl:GetAnchoredPosition() end)
  if print then
    self._ecb_seen = self._ecb_seen or {}
    if not self._ecb_seen[id] then
      self._ecb_seen[id] = true
      local function sh(v)
        if type(v) == "table" then return "表[" .. tostring(v[1]) .. "," .. tostring(v[2]) .. "]"
        elseif type(v) == "number" then return string.format("%.1f", v)
        else return type(v) end
      end
      print("[murdoku] 选关卡框 " .. tostring(id) .. "：w=" .. sh(w) .. " h=" .. sh(h)
        .. " pos=(" .. sh(ax) .. "," .. sh(ay) .. ")")
    end
  end
  local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
  if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return plan_r end
  if not finite(ax) or not finite(ay) then return plan_r end
  if is_visual then
    -- 这些容器使用中心锚点和轴心；按真实父链从内到外合成位置和缩放。
    for _, name in ipairs({ "grp653.static.1.art642.select.frames", "art642.select.frames", "art641.select" }) do
      local parent, x, y, sx, sy = nil, nil, nil, 1, 1
      pcall(function() parent = a:find(name) end)
      if parent == nil then return plan_r end
      pcall(function() x, y = parent:GetAnchoredPosition() end)
      if parent.GetLocalScale then pcall(function() sx, sy = parent:GetLocalScale() end) end
      if not finite(x) or not finite(y) or not finite(sx) or not finite(sy) or sx <= 0 or sy <= 0 then return plan_r end
      ax, ay, w, h = x + ax * sx, y + ay * sy, w * sx, h * sy
    end
  end
  local cfg = a.cfg or {}
  local sc = cfg.scale or (5 / 6)
  local cw = cfg.canvas_w or 1600
  local ch = cfg.canvas_h or 900
  local cx = cw * 0.5 + ax
  local cy = ch * 0.5 + ay
  local dw = w / sc
  local dh = h / sc
  return { x = cx / sc - dw * 0.5, y = (ch - cy) / sc - dh * 0.5, w = dw, h = dh }
end
function Controller:push_room_thumb(push, cardId, it, cardRect, parent, canvas_scale, card_scale)
  -- 696：选关卡片棕色区域 = 棋盘缩略图（每格房间底色 + 墙 + 门），家具省略。
  -- 关卡名由 build_layout 的 .info 节点放在下方白色边缘。
  local area = { x = cardRect.x + cardRect.w * 0.069,
                 y = cardRect.y + cardRect.h * 0.164,
                 w = cardRect.w * 0.861, h = cardRect.h * 0.783 }
  local sz = it and it.size or nil
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local grid = it and it.room_grid or nil
  local walls = it and it.walls or nil
  local doors = it and it.doors or nil
  -- 旧版 6 个房间大色块全部收起，避免与缩略图叠色
  for j = 1, ROOM_MAX do
    push({ id = cardId .. ".room." .. j, kind = "button", parent = parent,
           visible = false, rect = { x = area.x, y = area.y, w = 1, h = 1 },
           pos_runtime = true })
  end
  local emit, used = push, {}
  push = function(n)
    used[n.id] = true
    n.raycast = false
    emit(n)
  end
  local function hide_unused()
    for _, suffix in ipairs(Controller.THUMB_POOL or {}) do
      local id = cardId .. suffix
      if not used[id] then
        emit({ id = id, kind = "image", parent = parent, visible = false,
          raycast = false, rect = { x = area.x, y = area.y, w = 1, h = 1 }, pos_runtime = true })
      end
    end
  end
  if not rows or not cols or rows < 1 or cols < 1 then hide_unused(); return end
  -- 704：先在最终画布上确定整数格宽与固定格缝，再反算设计坐标。
  -- 卡框本身有小数中心；保留这个共同偏移，不逐格独立取整。
  local sc = tonumber(canvas_scale) or M.SCALE
  if sc ~= sc or sc <= 0 or sc == math.huge then sc = M.SCALE end
  local unit = tonumber(card_scale) or 1
  if unit <= 0 or unit ~= unit or unit == math.huge then unit = 1 end
  local gap_px = 2 * unit
  local count = math.max(rows, cols)
  local target_px = cardRect.w * sc * 0.78
  local cell_px = math.max(1, math.floor((target_px - (count - 1) * gap_px) / count + 0.5))
  local pitch = (cell_px + gap_px) / sc
  local cw, ch = cell_px / sc, cell_px / sc
  local width, height = (cols * cell_px + (cols - 1) * gap_px) / sc,
                        (rows * cell_px + (rows - 1) * gap_px) / sc
  local side = math.max(width, height)
  local rim = math.max(4 * unit, math.floor(cardRect.w * sc * 0.022 + 0.5)) / sc
  local center_x, center_y = cardRect.x + cardRect.w * 0.5, cardRect.y + cardRect.h * 0.5
  local gx, gy = center_x - width * 0.5, center_y - height * 0.5
  push({ id = cardId .. ".boardbg", kind = "image", parent = parent,
         visible = true, rect = { x = center_x - side * 0.5 - rim, y = center_y - side * 0.5 - rim,
           w = side + rim * 2, h = side + rim * 2 },
         image = WHITE_MAT, tint = 4281871675, pos_runtime = true })
  -- ① 每格底色（按房间编号取 ROOM_COLORS），不画任何家具
  for r = 1, rows do
    for c = 1, cols do
      local rn = (type(grid) == "table" and type(grid[r]) == "table")
                 and tonumber(grid[r][c]) or nil
      local tint = Controller.room_color(rn) or Controller.ROOM_COLORS[((r + c) % #Controller.ROOM_COLORS) + 1]
      push({ id = cardId .. ".cell." .. r .. "." .. c, kind = "button", parent = parent,
             visible = true,
             rect = { x = gx + (c - 1) * pitch, y = gy + (r - 1) * pitch,
                      w = cw, h = ch },
             image = WHITE_MAT, tint = tint, pos_runtime = true })
    end
  end
  -- ② 墙、门共用格缝中心线。厚度直接以画布像素指定，不再二次舍入。
  local INK  = { r = 32, g = 38, b = 44 }
  local GOLD = { r = 220, g = 91, b = 41 }
  local wall_width, door_width = 5 * unit / sc, 5 * unit / sc
  local door_len = math.max(8 * unit, math.floor(cell_px * 0.44 + 0.5)) / sc
  local gap = gap_px / sc
  local function seg(kind, r, c)
    if kind == "v" then
      return gx + c * pitch - gap * 0.5 - wall_width * 0.5,
             gy + (r - 1) * pitch - gap * 0.5, wall_width, pitch
    end
    return gx + (c - 1) * pitch - gap * 0.5,
           gy + r * pitch - gap * 0.5 - wall_width * 0.5, pitch, wall_width
  end
  local function line(suffix, x, y, w, h, tint)
    push({ id = cardId .. suffix, kind = "button", parent = parent, visible = true,
           rect = { x = x, y = y, w = math.max(1, w), h = math.max(1, h) },
           image = WHITE_MAT, tint = tint, pos_runtime = true })
  end
  local k = 0
  for n = 1, (type(walls) == "table" and #walls or 0) do
    local w = walls[n]
    if type(w) == "table" and (w[1] == "v" or w[1] == "h") then
      k = k + 1
      local x, y, ww, hh = seg(w[1], tonumber(w[2]) or 0, tonumber(w[3]) or 0)
      line(".wall." .. k, x, y, ww, hh, INK)
    end
  end
  local d = 0
  for n = 1, (type(doors) == "table" and #doors or 0) do
    local o = doors[n]
    if type(o) == "table" and (o[1] == "v" or o[1] == "h") then
      d = d + 1
      local x, y, ww, hh = seg(o[1], tonumber(o[2]) or 0, tonumber(o[3]) or 0)
      if o[1] == "v" then
        line(".door." .. d, x + (ww - door_width) * 0.5, y + (hh - door_len) * 0.5,
             door_width, door_len, GOLD)
      else
        line(".door." .. d, x + (ww - door_len) * 0.5, y + (hh - door_width) * 0.5,
             door_len, door_width, GOLD)
      end
    end
  end
  hide_unused()
end
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
function Controller:layout_plan()
  local saved_modal = self.modal    
  local saved_screen = self.screen
  local vm0 = self.core:view()
  local first_id = vm0.tray[1] and vm0.tray[1].id
  local states = {
    { name = "home",              intro = 99, modal = nil, screen = "home" },
    { name = "shop", intro=99, screen="shop" },
    { name = "bag", intro=99, screen="bag" },
    { name = "select",            intro = 99, modal = nil, screen = "select" },
    { name = "board",             intro = 99, modal = nil, screen = nil },
    { name = "result",            intro = 99,
      modal = { kind = "result", win = true, message = "（结果文案）" }, screen = nil },
    { name = "share",             intro = 99,
      modal = { kind = "share", code = "（分享码）" }, screen = nil },
    { name = "howto",             intro = 99, modal = { kind = "howto" }, screen = nil },
    { name = "levelselect",       intro = 99,
      modal = { kind = "levelselect" }, screen = nil },
    { name = "exit_menu",         intro = 99, modal = { kind = "exit_menu" }, screen = nil },
  }
  local order, byId = {}, {}
  for si = 1, #states do
    local st = states[si]
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
            image_id = n.image_id, imageColor = n.imageColor, rot = n.rot,
            action = n.event and n.event.action or nil,
            event = n.event,
        }
        byId[n.id] = prev
        order[#order + 1] = prev
      end
      prev.states[#prev.states + 1] = st.name
      if (n.visible ~= false) and prev.visible == false then
        prev.text = n.text
        prev.visible = true
      end
    end
  end
  self.modal, self.screen = saved_modal, saved_screen
  for i = 1, #order do
    local it = order[i]
    local in_board = false
    for k = 1, #it.states do
      if it.states[k] == "board" or it.states[k] == "result"
         or it.states[k] == "share" or it.states[k] == "howto" then in_board = true end
    end
    it.visible = in_board and it.visible
  end
  return order
end
function Controller:placed_count(vm)
  local n = 0
  for i = 1, #vm.tray do if vm.tray[i].placed then n = n + 1 end end
  return n
end
Controller.ROOM_COLORS = {
  { r = 234, g = 214, b = 168 },
  { r = 182, g = 205, b = 224 },
  { r = 186, g = 213, b = 180 },
  { r = 210, g = 192, b = 220 },
  { r = 228, g = 194, b = 178 },
  { r = 176, g = 213, b = 208 },
}
function Controller.room_color(room)
  if type(room) ~= "number" then return nil end
  local t = Controller.ROOM_COLORS
  if type(t) ~= "table" or #t == 0 then return nil end
  return t[((room - 1) % #t) + 1]
end
function Controller._piece_at_row(core, n)
  if core == nil or n == nil then return nil end
  n = tonumber(n)
  if n == nil then return nil end
  local pcs = core.pieces
  if type(pcs) ~= "table" then return nil end
  local c = Controller._piece_id_cache
  if c == nil or c.core ~= core then
    c = { core = core, ids = {} }
    for i = 1, #pcs do
      if pcs[i] ~= nil and pcs[i].id ~= nil then c.ids[i] = tostring(pcs[i].id) end
    end
    Controller._piece_id_cache = c
  end
  return c.ids[n]
end
function Controller._pos_of_piece(core, id)
  if core == nil or id == nil then return nil end
  local want = tostring(id)
  local pcs = core.pieces
  if type(pcs) ~= "table" then return nil end
  local c = Controller._piece_id_cache
  if c == nil or c.core ~= core then
    c = { core = core, ids = {} }
    for i = 1, #pcs do
      if pcs[i] ~= nil and pcs[i].id ~= nil then c.ids[i] = tostring(pcs[i].id) end
    end
    Controller._piece_id_cache = c
  end
  for i = 1, #pcs do
    if c.ids[i] == want then return i end
  end
  return nil
end
function Controller.portrait_of(vm, id)
  local _m = Controller._row_face
  if _m ~= nil then
    local _hit = _m[tostring(id)]
    if _hit ~= nil then return _hit end
    local n = Controller._pos_of_piece(Controller._piece_core, id)
    if n ~= nil then
      local _h2 = _m[n] or _m[tostring(n)]
      if _h2 ~= nil then return _h2 end
    end
  end
  if vm ~= nil and type(vm.tray) == "table" then
    for i = 1, #vm.tray do
      if vm.tray[i].id == id then return vm.tray[i].portrait end
    end
  end
  return nil
end
function Controller.letter_of(vm, id)
  local m = Controller._row_letter
  if m == nil then return nil end
  local hit = m[tostring(id)]
  if hit ~= nil then return hit end
  local n = Controller._pos_of_piece(Controller._piece_core, id)
  if n == nil then return nil end
  return m[n] or m[tostring(n)]
end
local function enum_at(path)
  local cur = Enum
  if cur == nil then return nil end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return nil end
  end
  return cur
end
local function write_control_text(ctrl, txt)
  if ctrl == nil then return false end
  local expected = tostring(txt or "")
  local ok = pcall(function() ctrl.text = expected end)
  if not ok then pcall(function() ctrl:SetText(expected) end) end
  local read_ok, actual = pcall(function() return ctrl.text end)
  return read_ok and actual == expected
end
function Controller:_grid_log(key, msg)
  self._grid_logged = self._grid_logged or {}
  if self._grid_logged[key] then return end
  self._grid_logged[key] = true
  if print then print("[murdoku] " .. tostring(msg)) end
end
function Controller:_dump_row_letter_map(lv_no, n)
  if type(print) ~= "function" then return false end
  if self._row_map_dumped == true then return true end
  local RT = rawget(Controller, "_row_text")
  local by = (type(RT) == "table") and RT[tostring(lv_no)] or nil
  if type(by) ~= "table" then return false end
  local ready = false
  for _, slot in pairs(by) do
    if type(slot) == "table" and slot.letter ~= nil and tostring(slot.letter) ~= "" then ready = true break end
  end
  if not ready then return false end
  self._row_map_dumped = true
  print("[murdoku] ★ 行 → 棋子 → 字母 对照表（★ 关卡 " .. tostring(lv_no)
    .. "；★ 棋盘上每一格显示的就是它那一行的 `letter` ✓）：")
  local nrow = tonumber(n) or 0
  for pos = 1, math.max(nrow, 1) do
    local slot = by[pos]
    local pid = Controller._piece_at_row(self.core, pos)
    print("    ★ 第 " .. tostring(pos) .. " 行  ⇒  棋子=" .. tostring(pid)
      .. "    letter=`" .. tostring(slot and slot.letter) .. "`"
      .. "    who=`" .. tostring(slot and slot.who) .. "`")
  end
  print("[murdoku] ★ 若某行的 `letter` 不是你想让它显示的那个字 ⇒ ★ **去编辑器改那一行** ✓"
    .. "（★ 脚本只照你配的显示 ✓ ★ 它没法知道「你想要哪个」✗）")
  return true
end
function Controller:_grid_fail(why)
  if self._grid_broken then return end
  self._grid_broken = true           
  self._grid_state = nil
  self.dirty = true                  
  self:_grid_log("fail", "网格视窗：失败（" .. tostring(why)
    .. "）⇒ 退回老路径（手写滚动：▲▼ + 滚动条 + clue.N 卡片）")
end
function Controller:sync_clue_grid(adapter)
  if adapter == nil or adapter.find == nil then return end
  self:_reset_row_maps_if_level_changed()
  local cfg = adapter.cfg
  if cfg ~= nil and cfg.use_grid == false then
    if self._grid_state == nil then
      self._grid_state = "off"
      self:_grid_log("off_cfg", "网格视窗：cfg.use_grid=false ⇒ 按配置走老路径（手写滚动）")
    end
    return
  end
  if self.screen == nil and self._grid_last_screen ~= nil then
    self._grid_broken = nil
    self._grid_tries = 0
    self._grid_state = nil
    self._grid = nil
  end
  self._grid_last_screen = self.screen  if self.screen ~= nil then return end
  self:_reset_row_maps_if_level_changed()
  if self._grid_broken then return end
  local grid = self._grid
  if grid == nil then
    if (self._grid_tries or 0) >= 120 then return end
    self._grid_tries = (self._grid_tries or 0) + 1
    pcall(function() grid = adapter:find("clues.grid") end)
    if grid == nil then
      pcall(function() grid = adapter:find("网格视窗") end)
    end
    if grid == nil then
      self:_grid_log("missing", "网格视窗：找不到 `clues.grid`（也试过中文名「网格视窗」，"
        .. "已经试了 " .. tostring(self._grid_tries) .. " 次）⇒ 继续走老路径（手写滚动）")
      if self._grid_tries >= 120 then
        self._grid_state = "off"
        self:_grid_log("missing_final", "网格视窗：试满 120 次仍拿不到控件 ⇒ 判定不可用，"
          .. "`clues.grid` 由脚本按不可见处理，老路径（手写滚动）接管")
      end
      return
    end
    self._grid = grid
  end
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
  local n = 0
  do
    local core = self.core
    if core ~= nil and type(core.clues) == "table" then
      n = #core.clues + ((type(core.general_clues) == "table" and #core.general_clues > 0) and 1 or 0)    
    else
      local lv = core and core.level
      n = #((lv and lv.clues) or {})
    end
  end
  self._grid_blank_total = n
  local sig = tostring(n)
  if self._grid_refill_pending then
    self._grid_refill_pending = nil
    local _rn = self:_grid_refill_now(adapter, grid)
    if _rn > 0 then
      self._grid_refill_n = (self._grid_refill_n or 0) + 1
    end
  end
  if self._grid_state == "on" and self._grid_sig == sig then return end
  local ok_set, set_err = pcall(function() grid.itemPrefabIndex = prefab end)
  if not ok_set then
    self:_grid_fail("设 itemPrefabIndex 失败：" .. tostring(set_err))
    return
  end
  local back = nil
  pcall(function() back = grid.itemPrefabIndex end)
  self._grid_calls = 0           
  self._grid_in_refresh = true
  local ok_ref, ref_err = pcall(function()
    grid:RefreshItems(n, function(item, index)
      local ok_cb, cb_err = pcall(function() self:_fill_grid_item(adapter, grid, item, index) end)
      if not ok_cb then self._grid_cb_err = tostring(cb_err) end
    end)
  end)
  self._grid_in_refresh = false
  pcall(function() self:_dump_row_letter_map(self:_level_ordinal(), n) end)
  local calls = self._grid_calls or 0
  if (not ok_ref) or (calls == 0 and n > 0) then
    self:_grid_fail("RefreshItems " .. ((not ok_ref) and ("抛错：" .. tostring(ref_err))
      or ("一次回调都没进来（n=" .. tostring(n) .. "）")))
    return
  end
  self._grid_sig = sig
  self._tpl_logged = true
  self._grid_state = "on"
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
    end
  end
  if adapter ~= nil and adapter.invalidate_lookups ~= nil then
    pcall(function() adapter:invalidate_lookups("grid_refresh:n=" .. tostring(n)) end)
  end
  if self._grid_cb_err ~= nil then
    self:_grid_log("cberr", "网格视窗：列表项填充回调抛过异常（" .. tostring(self._grid_cb_err)
      .. "）—— 已按「这一次没填上」处理；反复出现就把 cfg.use_grid 改回 false")
  end
  self:_grid_log("summary", string.format(
    "网格视窗：找到 clues.grid ✓ itemPrefabIndex=%s（回读 %s） n=%d RefreshItems 回调 %d 次；"
    .. "索引基准=%s；列表项点击=%s；★ 绑定次数=%s",
    tostring(prefab), tostring(back), n, calls,
    (self._grid_base == nil) and "?" or tostring(self._grid_base),
    (self._grid_click_ok == true) and "支持（用 GetItemIndex 反查索引）"
      or "不支持（列表项收不到光标事件 ⇒ 只能用老卡片的点击，聚焦仍可用）",
    tostring(self._grid_bind_n or 0)))
end
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
function Controller:_grid_item_rec(item, index)
  if item == nil then return nil end
  local cache = self._grid_kids
  if cache == nil then
    cache = setmetatable({}, { __mode = "k" })       
    self._grid_kids = cache
  end
  local rec = cache[item]
  if rec == nil then
    rec = { idx = index, hit = {}, variant = {} }
    cache[item] = rec
  end
  return rec
end
function Controller:_find_image_holder(root)
  if root == nil then return nil end
  local function canImg(c)
    if c == nil then return false end
    local a, b = false, false
    pcall(function() if type(c.SetImage) == "function" then a = true end end)
    pcall(function() if c.imageId ~= nil then b = true end end)
    return a or b
  end
  if canImg(root) then return root end
  local q = { root }
  local seen = 0
  local qi = 1
  while qi <= #q do
    if seen > 60 then break end
    local ks = nil
    pcall(function() ks = q[qi]:GetChildren() end)
    if type(ks) == "table" then
      for ki = 1, #ks do
        local kk = ks[ki]
        seen = seen + 1
        if canImg(kk) then return kk end
        if #q < 200 then q[#q + 1] = kk end
      end
    end
    qi = qi + 1
  end
  return nil
end
function Controller:_read_control_text(root, slot)
  if root == nil then return nil end
  local function ownText(c)
    if c == nil then return nil end
    local t = nil
    pcall(function() t = c.text end)
    if t == nil then return nil end
    t = tostring(t)
    if t == "" then return nil end
    return t
  end
  local t1 = ownText(root)
  if t1 ~= nil then return t1 end
  if type(slot) == "string" and slot ~= "" then
    local sub = nil
    pcall(function() sub = root:FindChild(slot) end)
    local t2 = ownText(sub)
    if t2 ~= nil then return t2 end
  end
  local q = { root }
  local seen = 0
  local qi = 1
  while qi <= #q do
    if seen > 60 then break end
    local ks = nil
    pcall(function() ks = q[qi]:GetChildren() end)
    if type(ks) == "table" then
      for ki = 1, #ks do
        local kk = ks[ki]
        seen = seen + 1
        local t = ownText(kk)
        if t ~= nil then return t end
        if #q < 200 then q[#q + 1] = kk end
      end
    end
    qi = qi + 1
  end
  return nil
end
local function c745_name(x) return x.name end
local function c745_kids(x) return x:GetChildren() end
function Controller:_find_by_name(name)
  if name == nil then return nil end
  local ad = self.adapter
  if ad ~= nil and ad.find ~= nil then
    local ok, hit = pcall(ad.find, ad, name)
    if ok and hit ~= nil then return hit end
    -- 745：若适配器本代数全树索引有效且已建立，缺项即为不存在，不再重复跑 9,788 节点裸 DFS。
    if ad._name_idx ~= nil and ad._name_idx_gen == ad._lookup_gen and (ad._name_idx_nodes or 0) > 0 then
      return nil
    end
  end
  local hit = nil
  local function search(x, d)
    if hit ~= nil or x == nil or d > 6 then return end
    local ok_n, nm = pcall(c745_name, x)
    if ok_n and nm == name then hit = x return end
    local ok_k, ks = pcall(c745_kids, x)
    if ok_k and type(ks) == "table" then
      for i = 1, #ks do search(ks[i], d + 1) end
    end
  end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if ok_r and type(roots) == "table" then
    for i = 1, #roots do search(roots[i], 0) end
  end
  return hit
end
function Controller:_palette_child(name)
  if name == nil then return nil end
  local fk = self._frame_n
  if type(fk) == "number" and fk > 0 then
    local pc = self._palette_frame
    if pc == nil or pc.clock ~= fk then
      pc = { clock = fk, map = self:_palette_assets_map() }
      self._palette_frame = pc
    end
    if pc.map == nil then return nil end        
    return pc.map[name]
  end
  return self:_palette_child_walk(name)
end
function Controller:_palette_assets_map()
  -- 655: assets 子树为静态，按查找代数缓存；句柄失效（客户端重建）时自动重建。
  local _ad655 = self.adapter
  local _gen655 = _ad655 and (_ad655._lookup_gen or 0) or -1
  local _cache655 = self._palette_assets_cache655
  if _cache655 ~= nil and _cache655.gen == _gen655 then
    local _ok655, _nm655 = pcall(function() return _cache655.assets.name end)
    if _ok655 and _nm655 == "assets" then return _cache655.map end
  end
  local assets = nil
  local search = nil
  search = function(x, d)
    if assets ~= nil or x == nil or d > 4 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == "assets" then assets = x return end
    local ks = nil
    pcall(function() ks = x:GetChildren() end)
    if ks ~= nil then
      local n = 0
      pcall(function() n = #ks end)
      for i = 1, n do search(ks[i], d + 1) end
    end
  end
  local roots = nil
  pcall(function() roots = game.GetClientUIRoots() end)
  if roots ~= nil then
    local rn = 0
    pcall(function() rn = #roots end)
    for i = 1, rn do
      local nm = nil
      pcall(function() nm = roots[i].name end)
      if nm == "root" then
        local direct = nil
        pcall(function() direct = roots[i]:GetChild("assets") end)
        local valid = false
        pcall(function() valid = direct ~= nil and direct.name == "assets" end)
        if valid then assets = direct; break end
      end
    end
    if assets == nil then
      for i = 1, rn do search(roots[i], 0) end
    end
  end
  if assets == nil then
    local r0 = nil
    pcall(function() r0 = self.adapter:find("root") end)
    if r0 ~= nil then search(r0, 0) end
  end
  if assets == nil then return nil end
  local ks = nil
  pcall(function() ks = assets:GetChildren() end)
  if ks == nil then return {} end
  local n = 0
  pcall(function() n = #ks end)
  local map = {}
  for i = 1, n do
    local nm = nil
    pcall(function() nm = tostring(ks[i].name) end)
    if nm ~= nil then map[nm] = ks[i] end
  end
  self._palette_assets_cache655 = { gen = _gen655, assets = assets, map = map }
  return map
end
function Controller:_palette_child_walk(name)
  if name == nil then return nil end
  local assets = nil
  local search = nil
  search = function(x, d)
    if assets ~= nil or x == nil or d > 4 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == "assets" then assets = x return end
    local ks = nil
    pcall(function() ks = x:GetChildren() end)
    if ks ~= nil then
      local n = 0
      pcall(function() n = #ks end)
      for i = 1, n do search(ks[i], d + 1) end
    end
  end
  local roots = nil
  pcall(function() roots = game.GetClientUIRoots() end)
  if roots ~= nil then
    local rn = 0
    pcall(function() rn = #roots end)
    for i = 1, rn do
      local nm = nil
      pcall(function() nm = roots[i].name end)
      if nm == "root" then
        local direct = nil
        pcall(function() direct = roots[i]:GetChild("assets") end)
        local valid = false
        pcall(function() valid = direct ~= nil and direct.name == "assets" end)
        if valid then assets = direct; break end
      end
    end
    if assets == nil then
      for i = 1, rn do search(roots[i], 0) end
    end
  end
  if assets == nil then
    local r0 = nil
    pcall(function() r0 = self.adapter:find("root") end)
    if r0 ~= nil then search(r0, 0) end
  end
  if assets == nil then
    return nil
  end
  local ks = nil
  pcall(function() ks = assets:GetChildren() end)
  if ks == nil then return nil end
  local n = 0
  pcall(function() n = #ks end)
  local seen = {}
  local hit = nil
  for i = 1, n do
    local nm = nil
    pcall(function() nm = tostring(ks[i].name) end)
    if nm ~= nil then
      seen[#seen + 1] = nm
      if nm == name then hit = ks[i] end
    end
  end
  return hit
end
function Controller:_level_ordinal()
  local lv = self.core and self.core.level
  if lv == nil then return nil end
  local id = lv.id
  if id == nil then return nil end
  local ok, n = pcall(function()
    local L = __require("levels.init")
    if type(L) ~= "table" then return nil end
    if type(L.index_of) == "function" then return L.index_of(id) end
    if type(L.indexOf) == "function" then return L.indexOf(id) end
    if type(L.list) == "table" then
      for i = 1, #L.list do if L.list[i].id == id then return i end end
    end
    return nil
  end)
  if ok and type(n) == "number" then return n end
  return nil
end
function Controller:_grid_item_child_cached(item, index, pos, suffix)
  local rec = self:_grid_item_rec(item, index)
  if rec == nil then return nil end
  local c = rec.hit[suffix]
  if c ~= nil and (rec.idx == index or (rec.variant[suffix] or 0) >= 3) then
    return c                                        
  end
  local hit, variant = self:_grid_item_child(item, index, pos, suffix)
  rec.idx = index
  rec.hit[suffix] = hit                             
  rec.variant[suffix] = variant
  return hit
end
function Controller:_grid_text_payload()
  local core = self.core
  Controller._piece_core = core
  local lv = core and core.level
  local list = core and core.clues
  local n = #(list or {})
  local p = self._grid_text
  if p ~= nil and p.level == lv and p.n == n then return p end
  local vm = core:view() or {}
  local row_text = nil
  do
    local lvno = self:_level_ordinal()
    if lvno ~= nil then
      local m = rawget(Controller, "_row_text")
      row_text = m and m[tostring(lvno)] or nil
    end
  end
  local items = {}
  for i = 1, #(vm.clues or {}) do
    local cl = vm.clues[i]
    local who, pre, post, wid, wportrait = split_by_name(vm, tostring(cl.text or ""))
    local rt = row_text and row_text[i] or nil
    -- 710修正版：who 是发言人，不能从证词提到的人名反推；what 保留设计卡面。
    local person = lv and lv.suspects and lv.suspects[i]
    local pid = (rt and rt.letter) or (person and person.id)
    if lv and type(lv.suspects) == "table" then
      for _, candidate in ipairs(lv.suspects) do
        if tostring(candidate.id) == tostring(pid) then person = candidate break end
      end
    end
    items[i] = {
      who    = (person and person.name) or (rt and rt.who) or who or "",
      what   = (rt and rt.what) or tostring(cl.text or ""),
      letter = (person and tostring(person.id)) or tostring(pid or ""),
      portrait = (person and person.portrait) or wportrait or (rt and rt.face),
      id     = person and person.id or i,
    }
  end
  p = { level = lv, n = n, items = items }
  self._grid_text = p
  return p
end
function Controller:_grid_visible_count(grid)
  if self._grid_vis_n ~= nil then return self._grid_vis_n end
  if grid == nil then return nil end
  local iw, ih = nil, nil
  local sx, sy = nil, nil
  local pt, pb = nil, nil
  local vh = nil
  pcall(function() iw, ih = grid:GetItemSize() end)
  pcall(function() sx, sy = grid:GetItemSpacing() end)
  pcall(function() pt, pb = grid:GetPadding() end)
  pcall(function() vh = grid.sizeDeltaY end)
  if ih == nil or vh == nil then return nil end
  local per = ih + (sy or 0)
  if per <= 0 or vh <= 0 then return nil end
  local n = 0
  while (pt or 0) + n * per + ih <= vh and n < 512 do n = n + 1 end
  if n < 1 then n = 1 end
  self._grid_vis_n = n
  self._grid_band_h = vh / 2
  self._grid_item_h = ih
  self._grid_vis_why = "项高=" .. tostring(ih) .. " 纵间距=" .. tostring(sy)
    .. " 上边距=" .. tostring(pt) .. " 下边距=" .. tostring(pb)
    .. " 视窗高=" .. tostring(vh)
  return n
end
local function c746_disable_prop(cg, key)
  local v = cg[key]
  if v == nil then return true end
  if v ~= false then
    cg[key] = false
    return cg[key] == false
  end
  return true
end
function Controller:_grid_refill_now(adapter, grid)
  if grid == nil then return 0 end
  local seen = self._grid_seen
  if seen == nil then return 0 end
  local n = 0
  self._grid_in_refresh = false
  for item, idx in pairs(seen) do
    pcall(self._fill_grid_item, self, adapter, grid, item, idx)
    n = n + 1
  end
  self._grid_in_refresh = false
  return n
end
function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then
    if self._grid_gray_retry747 ~= nil then
      self._grid_gray_retry747[item] = nil
      if next(self._grid_gray_retry747) == nil then self._grid_gray_retry747 = nil end
    end
    return true
  end
  -- 746+747（P1-2）：逐属性独立受保护写入并读回确认；失败项登记到 _grid_gray_retry747，由 tick 原地自动重试，不依赖玩家滚动或手动重刷。
  local ok1, d1 = pcall(c746_disable_prop, cg, "raycastTarget")
  local ok2, d2 = pcall(c746_disable_prop, cg, "blockRaycast")
  local ok3, d3 = pcall(c746_disable_prop, cg, "interactable")
  local all_done = (ok1 and d1 == true) and (ok2 and d2 == true) and (ok3 and d3 == true)
  if all_done then
    if rec ~= nil then rec.gray_noray = true end
    if self._grid_gray_retry747 ~= nil then
      self._grid_gray_retry747[item] = nil
      if next(self._grid_gray_retry747) == nil then self._grid_gray_retry747 = nil end
    end
  elseif item ~= nil then
    local q = self._grid_gray_retry747
    if q == nil then q = setmetatable({}, { __mode = "k" }); self._grid_gray_retry747 = q end
    local prev = q[item]
    local tries = (prev and prev.tries or 0) + 1
    local gap = (tries <= 2) and 0.25 or ((tries <= 5) and 0.5 or 1.0)
    q[item] = { index = index, pos = pos, tries = tries, next_t = (self.now or 0) + gap }
  end
  return all_done
end
function Controller:_has_general_clue()
  local lv = nil
  pcall(function() lv = self:_level_ordinal() end)
  if lv ~= nil then
    local rc = nil
    pcall(function() rc = self:_palette_child("row." .. tostring(lv) .. ".clue") end)
    if rc ~= nil then return true end
  end
  local ok = false
  pcall(function()
    ok = (self.core ~= nil and type(self.core.general_clues) == "table"
          and #self.core.general_clues > 0)
  end)
  return ok
end
function Controller:_fill_general_item(adapter, item, index, pos)
  self._general_item = item
  do
    local _lv = self:_level_ordinal()
    if _lv ~= nil then
      local _txt = nil
      local _rc = nil
      pcall(function() _rc = self:_palette_child("row." .. tostring(_lv) .. ".clue") end)
      if _rc ~= nil then
        local _src = nil
        pcall(function() _src = _rc:FindChild("clue." .. tostring(_lv) .. ".1") end)
        if _src ~= nil then pcall(function() _txt = _src.text end) end
      end
      if (_txt == nil or _txt == "") and self.core ~= nil then
        pcall(function()
          local rows = self.core:general_clue_results()
          local texts = {}
          for _, row in ipairs(rows or {}) do texts[#texts + 1] = row.text end
          _txt = table.concat(texts, "；")
        end)
      end
      if _txt ~= nil and _txt ~= "" then
        local _dst = nil
        pcall(function() _dst = item:FindChild("gen.body") end)
        if _dst ~= nil then pcall(function() write_control_text(_dst, _txt) end) end
      end
    end
  end
  local function child(nm)
    local c = nil
    pcall(function() c = self:_grid_item_child_cached(item, index, pos, nm) end)
    return c
  end
  for _, nm in ipairs({ "who", "what", "letter", "face", "false718" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(false) end) end
  end
  for _, nm in ipairs({ "gen.backrop", "gen.title", "gen.body", "gen691.base", "gen691.hi", "gen691.trap", "gen691.lo", "gen691.mid1", "gen691.mid2", "gen691.corner" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(true) end) end
  end   
  do
    local _cp = nil
    pcall(function() _cp = item:FindChild("gen.backrop") end)
    if _cp ~= nil then
      if self._gen_hl_orig == nil then
        pcall(function() self._gen_hl_orig = _cp.imageColor end)
      end
      local _want = (self.general_focus ~= nil)
      local _target = _want and HIGHLIGHT_TINT or self._gen_hl_orig
      if _target ~= nil then pcall(function() _cp.imageColor = _target end) end
    end
  end
end
function Controller:_fill_grid_item(adapter, grid, item, index)
  self._grid_calls = (self._grid_calls or 0) + 1
  if item == nil then return end
  pcall(function() self:_grid_bind_item_click(adapter, grid, item) end)
  pcall(function() self:_grid_disable_gray_raycast(item, index, nil) end)
  if not self._grid_in_refresh then
    self._grid_scroll_cbs = (self._grid_scroll_cbs or 0) + 1
    self:_grid_log("scroll_cb", "网格视窗：滚动时引擎**会**重进 RefreshItems 回调 ✓（第 "
      .. tostring(self._grid_scroll_cbs) .. " 次）⇒ 列表项内容按 index 现算，滚动不会串内容")
    local hits = self._grid_scroll_cbs
  end
  if self._grid_base == nil then
    local fi = tonumber(index)
    if fi ~= nil then
      self._grid_base = fi
    else
      self._grid_base = 0         
    end
    if print then
      print("[murdoku] 网格视窗：**索引基准定为 " .. tostring(self._grid_base)
        .. "**（第一次回调交来的 index = " .. tostring(index)
        .. "）⇒ 之后 `pos = index − " .. tostring(self._grid_base) .. " + 1`")
    end
  end
  local pos = (tonumber(index) or self._grid_base) - self._grid_base + 1
  self._grid_seen=self._grid_seen or {}
  self._grid_seen[item]=index
  local _has_gen = false
  pcall(function() _has_gen = self:_has_general_clue() end)
  if _has_gen then
    if pos == 1 then
      pcall(function() self:_fill_general_item(adapter, item, index, pos) end)
      return
    end
    pos = pos - 1
    if self._general_item == item then self._general_item = nil end    
    for _, _nm in ipairs({ "gen.backrop", "gen.title", "gen.body", "gen691.base", "gen691.hi", "gen691.trap", "gen691.lo", "gen691.mid1", "gen691.mid2", "gen691.corner" }) do
      pcall(function()
        local _cc = self:_grid_item_child_cached(item, index, pos, _nm)
        if _cc ~= nil then pcall(function() _cc:SetVisible(false) end) end
      end)
    end
  end
  for _,nm in ipairs({"who","what","letter","face"}) do
    local c=self:_grid_item_child_cached(item,index,pos,nm)
    if c then pcall(function() c:SetVisible(true) end) end
  end
  if print and (self._grid_fill_pos_log or 0) < 6 then
    self._grid_fill_pos_log = (self._grid_fill_pos_log or 0) + 1
    print("[murdoku] ★ 填充定位 ✓：引擎交来 index=" .. tostring(index)
      .. "（基准 " .. tostring(self._grid_base) .. "）⇒ 填到 pos=" .. tostring(pos))
  end
  local _row_need = (self._grid_in_refresh == true)
  if not _row_need then
    local m0 = rawget(Controller, "_row_letter")
    _row_need = (type(m0) ~= "table") or (m0[pos] == nil)
  end
  if _row_need then
    local lv_no = self:_level_ordinal()
    if lv_no ~= nil then
      local rc = self:_palette_child("row." .. tostring(lv_no) .. "." .. tostring(pos))
      if rc ~= nil then
        local wrote = 0
        local kids = nil
        pcall(function() kids = rc:GetChildren() end)
        do
          local have = {}
          if type(kids) == "table" then
            for ci = 1, #kids do
              local kn = nil
              pcall(function() kn = tostring(kids[ci].name) end)
              if kn ~= nil then have[kn] = true end
            end
          end
          local want = { "who", "what", "letter", "face" }
          for wi = 1, #want do
            local full = want[wi] .. "." .. tostring(lv_no) .. "." .. tostring(pos)
            if have[full] ~= true then
              local extra = self:_find_by_name(full)
              if extra ~= nil then
                if type(kids) ~= "table" then kids = {} end
                kids[#kids + 1] = extra
                if (self._row_find_log or 0) < 6 and print then
                  self._row_find_log = (self._row_find_log or 0) + 1
                  print("[murdoku] ★ 单射兜底：`" .. full .. "` 不在 #503 里 ✗ ⇒ **按名全树找到** ✓")
                end
              end
            end
          end
        end
        if type(kids) == "table" then
          for ci = 1, #kids do
            local k = kids[ci]
            local kn = nil
            pcall(function() kn = tostring(k.name) end)
            local slot = kn
            if slot ~= nil then slot = string.match(slot, "^[^%.]+") end
            local _rowno = pos
            if slot ~= nil and slot ~= "" then
              local dst = nil
              local full = "clue." .. tostring(pos) .. "." .. tostring(slot)
              pcall(function() dst = item:FindChild(full) end)
              if dst == nil then
                pcall(function() dst = item:FindChild(slot) end)
              end
              if dst == nil then
                dst = self:_grid_item_child_cached(item, index, pos, slot)
              end
              if dst ~= nil then
                local okT, okI = false, false
                pcall(function() local _ = dst.text okT = true end)
                pcall(function() local _ = dst.imageId okI = true end)
                if not okT and not okI then
                  dst = nil
                end
              end
              if dst ~= nil then
                local txt = nil
                pcall(function() txt = k.text end)
                local _slot_txt = self:_read_control_text(k, slot)
                if _slot_txt ~= nil then
                  local _lvn = self:_level_ordinal()
                  if _lvn ~= nil then
                    Controller._row_text = Controller._row_text or {}
                    local _by_lv = Controller._row_text[tostring(_lvn)]
                    if _by_lv == nil then _by_lv = {}; Controller._row_text[tostring(_lvn)] = _by_lv end
                    local _by_pos = _by_lv[pos]
                    if _by_pos == nil then _by_pos = {}; _by_lv[pos] = _by_pos end
                    if _by_pos[slot] == nil then _by_pos[slot] = tostring(_slot_txt) end
                    self._grid_text = nil
                  end
                end
                if slot == "letter" then
                  local _lt = self:_read_control_text(k, slot)
                  if _lt ~= nil then
                    local _pid = _rowno
                    if _pid ~= nil then
                      Controller._row_letter = Controller._row_letter or {}
                      local _old = Controller._row_letter[_pid]
                      if _old ~= nil and tostring(_old) ~= tostring(_lt) then
                        if (self._row_letter_dup or 0) < 6 and print then
                          self._row_letter_dup = (self._row_letter_dup or 0) + 1
                          print("[murdoku] ★ 同一行（`row." .. tostring(lv_no) .. "." .. tostring(pos)
                            .. "`）配了两个不同的 `letter` ✗：已记=`" .. tostring(_old)
                            .. "` 这次=`" .. tostring(_lt) .. "` ⇒ ★ **用这次读到的** ✓"
                            .. "（★ 行号才是键 ✓ 后读到的就是这个槽位的真值 ✓）")
                        end
                      end
                      Controller._row_letter[_pid] = tostring(_lt)
                      if (self._row_letter_log or 0) < 6 and print then
                        self._row_letter_log = (self._row_letter_log or 0) + 1
                        print("[murdoku] ★ 标记来源记下 ✓：`row." .. tostring(lv_no) .. "."
                          .. tostring(pos) .. "` ⇒ who=`" .. tostring(_pid)
                          .. "` letter=`" .. tostring(_lt) .. "`")
                      end
                    end
                  elseif (self._row_letter_miss or 0) < 6 and print then
                    self._row_letter_miss = (self._row_letter_miss or 0) + 1
                    print("[murdoku] ★ `letter` 读不到文字 ✗：`" .. tostring(kn)
                      .. "`（★ 自有 `.text` / `FindChild(" .. tostring(slot)
                      .. ")` / 子孙 三条路都空 ✓ ⇒ 这一段标记会落回旧铅笔笔记 ✓）")
                  end
                end
              if dst ~= nil then
                local _hasT = false
                pcall(function() if dst.text ~= nil then _hasT = true end end)
                if not _hasT then
                  local _q = { dst }
                  local _found = nil
                  for _qi = 1, #_q do
                    local _ks = nil
                    pcall(function() _ks = _q[_qi]:GetChildren() end)
                    if type(_ks) == "table" then
                      for _ki = 1, #_ks do
                        local _kk = _ks[_ki]
                        local _ht = false
                        pcall(function() if _kk.text ~= nil then _ht = true end end)
                        if _ht then _found = _kk break end
                        _q[#_q + 1] = _kk
                      end
                    end
                    if _found ~= nil then break end
                  end
                  if _found ~= nil then
                    dst = _found
                  else
                  end
                end
              end
              if type(txt) == "string" then
                    pcall(function() if dst.text ~= nil then dst.text = txt end end)
                    if type(dst.SetText) == "function" then pcall(function() dst:SetText(txt) end) end
                  wrote = wrote + 1
                end
                local _kimg = self:_find_image_holder(k)
                if _kimg == nil then _kimg = k end
                local iid = nil
                pcall(function() iid = _kimg.imageId end)
                if iid ~= nil then
                  local _key_face = _rowno
                  if _key_face ~= nil then
                    Controller._row_face = Controller._row_face or {}
                    Controller._row_face[_key_face] = iid
                  end
                end
                if iid ~= nil then
                  local src = nil
                  pcall(function() src = k.imageSource end)
                  local _dimg = self:_find_image_holder(dst)
                  if _dimg ~= nil then dst = _dimg end
                  local _okImg = false
                  if src ~= nil then pcall(function() dst:SetImage(src, iid) _okImg = true end) end
                  if not _okImg then pcall(function() dst:SetImage(iid) _okImg = true end) end
                  if not _okImg then
                    pcall(function() if src ~= nil then dst.imageSource = src end end)
                    pcall(function() dst.imageId = iid end)
                  end
                  wrote = wrote + 1
                end
              end
            end
          end
        end
        if (self._row_log or 0) < 6 and print then
          self._row_log = (self._row_log or 0) + 1
          print("[murdoku] ★ 单射命中：`row." .. tostring(lv_no) .. "." .. tostring(pos)
            .. "` ⇒ 写了 " .. tostring(wrote) .. " 个槽位 ✓（★ 内容【由你在编辑器里定】✓）")
        end
        self._row_wrote = self._row_wrote or {}
        if wrote > 0 then self._row_wrote[pos] = true end
      end
    end
  end
  self._grid_idx_seen = self._grid_idx_seen or {}
  if self._grid_idx_seen[pos] == nil then
    self._grid_idx_seen[pos] = 0
    self._grid_idx_n = (self._grid_idx_n or 0) + 1
  end
  self._grid_idx_seen[pos] = self._grid_idx_seen[pos] + 1
  self._grid_cb_total = (self._grid_cb_total or 0) + 1
  local pay = self:_grid_text_payload()
  local cl = pay.items[pos]
  if cl == nil then
    cl = { who = "", what = "", letter = "", id = nil, portrait = nil }
  end
  local t_who, t_what, t_letter = cl.who, cl.what, cl.letter
  local _pid = cl.id
  if type(_pid) == "string" then
    if _pid == "" or #_pid > 2 then _pid = nil end
    if _pid ~= nil and _pid:sub(1, 1) == "@" then _pid = nil end
  end
  if _pid == nil then _pid = cl.who end
  if type(_pid) == "string" then
    if _pid == "" or #_pid > 2 or _pid:sub(1, 1) == "@" then _pid = nil end
  end
  if _pid ~= nil then
    local _as_piece = Controller._piece_at_row(self.core, tonumber(_pid))
    if _as_piece ~= nil then _pid = _as_piece end
    if type(_pid) == "string" and #_pid > 2 then _pid = nil end
  end
  local _placed_now = (_pid ~= nil) and self.core ~= nil and self.core.placed ~= nil
    and self.core.placed[_pid] == true
  local _cgray = self:_grid_item_child_cached(item, index, pos, "gray")
  local _pal = nil
  if _cgray ~= nil then
    local _rg = self:_grid_item_rec(item, index)
    if _rg ~= nil and _rg.gray ~= _placed_now then
      _rg.gray = _placed_now
      if _cgray.SetVisible then pcall(function() _cgray:SetVisible(_placed_now) end) end
      if _cgray.SetActive then pcall(function() _cgray:SetActive(_placed_now) end) end
    end
  end
  local c_who    = self:_grid_item_child_cached(item, index, pos, "who")
  local c_what   = self:_grid_item_child_cached(item, index, pos, "what")
  local c_letter = self:_grid_item_child_cached(item, index, pos, "letter")
  local c_backrop1 = self:_grid_item_child_cached(item, index, pos, "backrop1")
  local rec = self:_grid_item_rec(item, index)
  local tv = rec and rec.text
  if tv == nil or tv.idx ~= index then
    tv = { idx = index }
    if rec ~= nil then rec.text = tv end
  end
  if tv ~= nil then
    local function sync_text(key, ctrl, value)
      if ctrl == nil then tv[key] = nil; return end
      local expected = tostring(value or "")
      local ok, actual = pcall(function() return ctrl.text end)
      -- row.* 复制及列表项复用会覆盖旧值，不能只比较缓存。
      if not ok or actual ~= expected then
        if not write_control_text(ctrl, expected) then tv[key] = nil; return end
      end
      tv[key] = expected
    end
    sync_text("who", c_who, t_who)
    sync_text("what", c_what, t_what)
    sync_text("letter", c_letter, t_letter)
    local marker=self:_grid_item_child_cached(item,index,pos,"false718")
    sync_text("false718",marker,self._false_clues and self._false_clues[pos] and "假" or "")
    if marker then marker:SetVisible(self._false_clues~=nil and self._false_clues[pos]==true) end
  end
  if c_who == nil or c_what == nil or c_letter == nil then
    self:_grid_log("childmiss", "网格视窗：列表项子控件 who/what/letter = "
      .. ((c_who ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_what ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_letter ~= nil) and "有" or "**缺**")
      .. "（模板 1073742421 里应叫 `clue.1.who` / `clue.1.what` / `clue.1.letter`）")
  end
  self._grid_bind_n = (self._grid_bind_n or 0) + 1
  self:_grid_paint_highlight(item, index, pos, c_backrop1)
end
function Controller:_grid_paint_highlight(item, index, pos, c_backrop1)
  if item == nil then return false end
  local cp = c_backrop1
  if cp == nil then
    pcall(function() cp = self:_grid_item_child_cached(item, index, pos, "backrop1") end)
  end
  if cp == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec == nil then return false end
  local sel = self.core and self.core.selected or nil
  local want = nil
  if sel ~= nil then want = self:_clue_pos_of_person(sel) end
  local want_on = ((want ~= nil) and want == pos)
  if rec.hl_pos == pos and rec.hl_on == want_on then return true end
  if rec.hl_orig == nil or rec.hl_idx ~= index then
    local cur = nil
    pcall(function() cur = cp.imageColor end)
    rec.hl_orig = cur
    rec.hl_idx = index
  end
  local target = want_on and HIGHLIGHT_TINT or rec.hl_orig
  if target ~= nil then pcall(function() cp.imageColor = target end) end
  if print and (self._grid_hl_log or 0) < 6 then
    self._grid_hl_log = (self._grid_hl_log or 0) + 1
    local back = nil
    pcall(function() back = cp.imageColor end)
    local isLeaf = (select(1, pcall(function() local _ = cp.GetChild end)) == true)
    print("[murdoku] ★ 卡片高亮（真机这条）✓ pos=" .. tostring(pos)
      .. " 选中=" .. tostring(sel) .. " ⇒ " .. (want_on and "**亮**" or "灭")
      .. "　写了 " .. tostring(target) .. " 回读=" .. tostring(back)
      .. "　有 GetChild=" .. tostring(isLeaf) .. "　orig=" .. tostring(rec.hl_orig))
  end
  rec.hl_pos, rec.hl_on = pos, want_on
  return true
end
function Controller:_grid_bind_item_click(adapter, grid, item)
  if item == nil or item.AddCursorEventListener == nil then
    return
  end
  if adapter ~= nil and adapter.ensure_raycast ~= nil then
    pcall(function() adapter:ensure_raycast(item) end)
  end
  self._grid_bound = self._grid_bound
    or setmetatable({}, { __mode = "k" })           
  if self._grid_bound[item] then
    self._grid_click_ok = true
    return
  end
  local click = enum_at("CursorEventType.CursorClick")
  if click == nil then return end                   
  pcall(function() item.disableCursorEventPassthrough = false end)
  local pressed,ox,oy,dragged,drag_at
  local function listen(kind,fn)
    local e=enum_at("CursorEventType."..kind)
    if e then pcall(function() item:AddCursorEventListener(e,fn) end) end
  end
  local function xy(data)
    if data and data.GetUIPos then return data:GetUIPos() end
  end
  local function moved(data)
    local x,y=xy(data)
    if type(x)=="number" and type(ox)=="number" and ((x-ox)^2+(y-oy)^2)>TAP_MOVE_TOLERANCE^2 then
      dragged=true
      drag_at=self.now or 0
    end
    if dragged then self._clue_tap=nil end
  end
  listen("CursorDown",function(data) pressed=self:_grid_pos_of_item(grid,item); ox,oy=xy(data); dragged=false; drag_at=nil end)
  -- Native grid owns dragging. Compare down/up positions to reject swipe clicks.
  listen("CursorUp",moved)
  local ok=pcall(function()
    item:AddCursorEventListener(click,function()
      if adapter._clue_owner and adapter._clue_owner~=self then return end
      local recent_drag = dragged and (drag_at == nil or ((self.now or 0) - drag_at) < 0.5)
      if self.screen or self.modal or recent_drag or (pressed and pressed~=self:_grid_pos_of_item(grid,item)) then
        self._clue_tap=nil
      else self:_on_grid_item_click(adapter,grid,item) end
      pressed,ox,oy,dragged,drag_at=nil,nil,nil,false,nil
    end)
  end)
  if ok then
    self._grid_bound[item] = true
    self._grid_click_ok = true
  end
end
function Controller:_grid_pos_of_item(grid, item)
  if item == nil then return nil end
  local raw = nil
  local seen = self._grid_seen
  if type(seen) == "table" then
    raw = seen[item]
    if raw ~= nil then
      local base = self._grid_base or 0
      local pos = tonumber(raw)
      if pos ~= nil then return pos - base + 1 end
    end
  end
  local idx = nil
  pcall(function() idx = grid:GetItemIndex(item) end)
  if type(idx) == "number" then return idx - (self._grid_base or 0) + 1 end
  return nil
end
function Controller:_on_grid_item_click(adapter, grid, item)
  do
    self._gic_in = (self._gic_in or 0) + 1
    if print and self._gic_in <= 6 then
      local _idx_dbg = nil
      pcall(function() _idx_dbg = grid:GetItemIndex(item) end)
      print("[murdoku] ★ 卡片点击**进来了** ✓（第 " .. tostring(self._gic_in)
        .. " 次）GetItemIndex=" .. tostring(_idx_dbg)
        .. "  索引基准=" .. tostring(self._grid_base))
    end
  end
  do
    local now = self.now or 0
    if now ~= nil then
      local last = self._grid_click_at
      if last ~= nil and (now - last) < 0.05 then
        self._grid_click_dup = (self._grid_click_dup or 0) + 1
        if (self._grid_click_dup_log or 0) < 3 and print then
          self._grid_click_dup_log = (self._grid_click_dup_log or 0) + 1
          print("[murdoku] ★ 同一次点击的**后续项已忽略** ✓（累计 "
            .. tostring(self._grid_click_dup) .. " 次）"
            .. "　⇒ ★ 来源：**多个列表项叠在同一位置** ⇒ 一次射线命中全部 ✗")
        end
        return
      end
      self._grid_click_at = now
    end
  end
  if item ~= nil and self._general_item == item then
    self:_flush_clue_tap()
    self:dismiss_action_confirm()
    if self.general_focus ~= nil then
      self.general_focus = nil
      self.focused_clue = nil
      self.general_hint = nil
      self.dirty = true
      self._grid_sig = nil
      return
    end
    local _ncl = 0
    pcall(function() local _v = self.core:view(); _ncl = #_v.clues end)
    self.focused_clue = _ncl + 1
    self.general_focus = true
    pcall(function() self.general_hint = self.core:clue_hint_general(1) end)
    self.dirty = true
    self._grid_sig = nil
    return
  end
  local pos = self:_grid_pos_of_item(grid, item)
  do
    local _hg = false
    pcall(function() _hg = self:_has_general_clue() end)
    if _hg and pos ~= nil then
      pos = pos - 1                 
    end
  end
  if type(pos) ~= "number" then
    self:_grid_log("noindex", "网格视窗：这一项属于哪一条读不到（填充记录与 GetItemIndex 都空）"
      .. " ⇒ 这一次点击忽略（不改焦点）")
    return
  end
  if print and (self._grid_pos_log or 0) < 6 then
    self._grid_pos_log = (self._grid_pos_log or 0) + 1
    local raw = nil
    pcall(function() raw = self._grid_seen and self._grid_seen[item] end)
    print("[murdoku] ★ 点卡片定位 ✓：填充时 index=" .. tostring(raw)
      .. "（基准 " .. tostring(self._grid_base) .. "）⇒ pos=" .. tostring(pos))
  end
  self._grid_refill_pending = true
  local n = #((self.core and self.core.clues) or {})
  if pos < 1 or pos > n then return end
  local tap=self._clue_tap
  local now=self.now or 0
  if tap and tap.pos==pos and now-tap.time<=DOUBLE_CLICK_SECONDS then
    self._clue_tap=nil
    self:dismiss_action_confirm()
    self._false_clues=self._false_clues or {}
    self._false_clues[pos]=not self._false_clues[pos] or nil
    self._grid_refill_pending=true
    self.dirty=true
    return
  end
  self:_flush_clue_tap()
  self._clue_tap={time=now,pos=pos,adapter=adapter}
end
function Controller:_flush_clue_tap()
  local tap=self._clue_tap
  self._clue_tap=nil
  if not tap or self.screen or self.modal then return end
  local pos,adapter=tap.pos,tap.adapter
  local _sel_ok, _sel_err = pcall(function()
    local v2 = self.core:view() or {}
    local cl = (v2.clues or {})[pos]
    if print and (self._grid_pick_log or 0) < 6 then
      self._grid_pick_log = (self._grid_pick_log or 0) + 1
      local _dbg_pid = nil
      pcall(function() _dbg_pid = self:_person_id_for_pos(pos) end)
      local _rt, _names_n = nil, 0
      pcall(function()
        local m = rawget(Controller, "_row_text")
        if type(m) == "table" then
          local lvno = self:_level_ordinal()
          local by = (lvno ~= nil) and m[tostring(lvno)] or nil
          local slot = by and by[pos] or nil
          _rt = slot and slot.who or nil
          if _rt == nil then
            for _, v in pairs(m) do
              local s2 = v[pos]
              if s2 ~= nil and s2.who ~= nil then _rt = s2.who break end
            end
          end
        end
        if type(self.core.names) == "table" then
          for _ in pairs(self.core.names) do _names_n = _names_n + 1 end
        end
      end)
      print("[murdoku] ★ 选人这一步：pos=" .. tostring(pos)
        .. "  cl=" .. (cl ~= nil and "有" or "**nil**")
        .. "  解析出的人=" .. tostring(_dbg_pid)
        .. "　★ 读到的 who=「" .. tostring(_rt) .. "」"
        .. "  names 表 " .. tostring(_names_n) .. " 条")
    end
    if cl ~= nil then
      local pid = self:_person_id_for_pos(pos)
      if pid == nil then
        pid = cl.who or cl.person or cl.who_id or cl.id
        if type(pid) == "string" and pid:sub(1, 1) == "@" then pid = nil end
        if pid == nil then
          local pn = cl.portrait or cl.face or cl.asset
          if pn ~= nil then pid = tostring(pn):gsub("^portrait%.", "") end
        end
      end
      if pid ~= nil then
        if self.core:select_suspect(pid) then self:dismiss_action_confirm() end
        self._grid_refill_pending = true
        self.dirty = true
      end
    end
  end)
  if (not _sel_ok) and print then
    self._sel_err_log = (self._sel_err_log or 0) + 1
    if self._sel_err_log <= 3 then
      print("[murdoku] ⚠️ 点卡片**选人那一步抛了异常** ⇒ 这一步整段没生效（第 "
        .. tostring(self._sel_err_log) .. " 次，最多报 3 次）：" .. tostring(_sel_err))
    end
  end
  local ev = { action = "focus_clue", index = pos, phase = "click" }
  if adapter ~= nil and type(adapter.on_input) == "function" then
    adapter.on_input(ev)
  else
    self:on_input(ev)
  end
end
function Controller:_person_id_for_pos(pos)
  local core = self.core
  if core == nil or pos == nil then return nil end
  local id = Controller._piece_at_row(core, pos)
  if id ~= nil then return id end
  local vm = nil
  pcall(function() vm = core:view() end)
  local cl = (vm and vm.clues or {})[pos]
  if cl ~= nil then
    local pid = cl.who
    if type(pid) == "string" and pid:sub(1, 1) == "@" then pid = nil end
    if pid ~= nil then return tostring(pid) end
  end
  return nil
end
function Controller:_clue_pos_of_person(id)
  if id == nil then return nil end
  local core = self.core
  if core == nil then return nil end
  local pos = Controller._pos_of_piece(core, id)
  if pos == nil then return nil end
  local back = Controller._piece_at_row(core, pos)
  if back == nil or tostring(back) ~= tostring(id) then return nil end
  return pos
end
function Controller:_sync_clue_focus()
  local core = self.core
  local sel = core and core.selected or nil
  local key = (sel == nil) and "\0none" or tostring(sel)
  if rawget(self, "_clue_sel_key") == key then return false end
  self._clue_sel_key = key
  local pos = (sel == nil) and nil or self:_clue_pos_of_person(sel)
  local want = ((pos ~= nil) and pos > 0) and pos or nil
  if rawget(self, "_clue_sel_pos") == want then return false end
  self._clue_sel_pos = want
  local changed = (rawget(self, "focused_clue") ~= want)
  if changed then
    self._grid_focus_item, self._grid_focus_orig = nil, nil
    self._grid_focus_idx, self._grid_focus_pos = nil, nil
    self.focused_clue = want
    self._grid_refill_pending = true
    self.dirty = true
  end
  return changed
end
function Controller:_set_prop(adapter, id, key, value, nkey)
  local ok, res = pcall(adapter.set_property, adapter, id, key, value, nkey)
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
  if adapter ~= nil then self._last_adapter = adapter end    
  local batched = false
  if adapter ~= nil and adapter.begin_furn_batch ~= nil then
    batched = pcall(adapter.begin_furn_batch, adapter)
  end
  local ok, err = pcall(self._render_impl, self, adapter, force)
  if batched then pcall(adapter.end_furn_batch, adapter) end
  if not ok then error(err, 0) end
  if adapter and adapter.sync_ruler721 then adapter:sync_ruler721(self) end
end
local function render_exists743(adapter, id, found)
  if found or type(adapter.find) ~= "function" then return true, found end
  local ok, handle = pcall(adapter.find, adapter, id)
  found = ok and handle ~= nil
  return found or not ok, found
end
local function rect_record743(last, rect)
  local saved = last.__rect
  if saved == nil then saved = {}; last.__rect = saved end
  saved.x, saved.y, saved.w, saved.h = rect.x, rect.y, rect.w, rect.h
end
local function is_select_content744(id)
  local b = id:byte(1)
  if b == 101 then return id:sub(1, 5) == "econ." end
  if b == 115 then
    return id == "select.thumb.pool" or (id:sub(1, 12) == "select.card." and id:match("^select%.card%.%d+%.") ~= nil)
  end
  if b == 104 then
    return id:sub(1, 16) == "hit.select.card." and id:match("^hit%.select%.card%.%d+$") ~= nil
  end
  return false
end
function Controller:_render_impl(adapter, force)
  self._pending_retry744 = false
  self._pending_retry_ids746 = nil
  local screen_switched747 = false
  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      screen_switched747 = true
      local level_changed745 = (self._tree_level ~= lv_id)
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter and adapter.clear_board_portraits then pcall(adapter.clear_board_portraits, adapter) end
      self._props = {}
      local why745 = "screen=" .. tostring(self.screen) .. " level=" .. tostring(lv_id)
      -- 745（解禁禁区3）：同关普通切屏先 O(1) 探活当前 root 句柄；仅在关卡变更或 root 句柄确实失效重建时才全量清缓存并重扫射线/光标。
      local tree_alive745 = false
      if not level_changed745 and adapter ~= nil and adapter._root_alive745 ~= nil then
        local ok_a, alive = pcall(adapter._root_alive745, adapter)
        tree_alive745 = (ok_a and alive == true)
      end
      if not tree_alive745 then
        if adapter ~= nil and adapter.invalidate_lookups ~= nil then
          pcall(adapter.invalidate_lookups, adapter, why745)
        end
        if adapter ~= nil and adapter.rearm_raycast ~= nil then
          pcall(adapter.rearm_raycast, adapter, why745)
        end
        if adapter ~= nil and adapter.rearm_cursor ~= nil then
          pcall(adapter.rearm_cursor, adapter, why745)
        end
      else
        -- 746：树未重建时，仅清掉与当前目标页相关的未命中节流；非关内切屏保留 cell.* 缺项退避，
        -- 避免首页/选关/商店/背包互切时因 cell.1.2 缺项触发 8,578 节点全树索引重建；进关时完整清零。
        if self.screen == nil or self.screen == "level" then
          adapter._misses = nil
          adapter._miss_streak = nil
        elseif adapter._misses ~= nil then
          for mk in pairs(adapter._misses) do
            if type(mk) ~= "string" or mk:sub(1, 5) ~= "cell." then
              adapter._misses[mk] = nil
              if adapter._miss_streak ~= nil then adapter._miss_streak[mk] = nil end
            end
          end
        end
        adapter._mark_layer_dirty745 = true
        -- 748（B5/U7）：同关切屏当帧对当前页全部已绑交互控件（含 Adapter:bind_input、util:_bind 与 cell.*）执行一次 O(1) 句柄换绑检查。
        if adapter.check_watched_handles748 ~= nil then
          pcall(adapter.check_watched_handles748, adapter, self.screen, self)
        end
      end
    end
  end
  self:sync_clue_grid(adapter)
  local nodes = self:build_layout(adapter)
  local grid_on = (self._grid_state == "on")
  local function stale_legacy(id) return grid_on and is_legacy_clue_id(id) end
  if self.input_profile == nil then
    self.input_profile = "pc"
    if adapter ~= nil and adapter.input_profile ~= nil then
      pcall(function() self.input_profile = adapter:input_profile() end)
    end
  end
  local seen = {}
  for i = 1, #nodes do seen[nodes[i].id] = true end
  local function forget_visible(id)
    local bucket = self._props[id]
    if bucket then
      for _, rec in pairs(bucket) do
        rec.visible = nil
      end
    end
  end
  if self._shown == nil then
    local all = self:layout_plan()
    if adapter.prefetch then
      local names = {}
      for i = 1, #all do names[#names+1] = all[i].id end
      adapter:prefetch(names)
    end
    for i = 1, #all do
      if not seen[all[i].id] and not stale_legacy(all[i].id) then
        self:_set_prop(adapter, all[i].id, "visible", false)
        forget_visible(all[i].id)           
      end
    end
    if adapter.hide_unlisted ~= nil then
      adapter:hide_unlisted(seen)
    end
  else
    for id in pairs(self._shown) do
      if not seen[id] and not stale_legacy(id) then
        self:_set_prop(adapter, id, "visible", false)
        forget_visible(id)                
      end
    end
  end
  self._shown = seen           
  local PROP_RETRY = 3
  local function retry_clear(id, key)
    if self._prop_retry ~= nil then
      self._prop_retry[tostring(id) .. "\1" .. tostring(key)] = nil
    end
  end
  local SUB_READY_SECONDS = 2.5    
  local function retry_more(id, key, why, exists)
    local rk = tostring(id) .. "\1" .. tostring(key)
    self._prop_retry = self._prop_retry or {}
    local n_try = (self._prop_retry[rk] or 0) + 1
    self._prop_retry[rk] = n_try
    if n_try == 1 then
      self._prop_retry_t0 = self._prop_retry_t0 or {}
      self._prop_retry_t0[rk] = self.now or 0
    end
    if exists == true and (key == "walls" or key == "doors") then
      local t0 = (self._prop_retry_t0 or {})[rk] or (self.now or 0)
      if (self.now or 0) - t0 < SUB_READY_SECONDS then return true end
    else
      if n_try < PROP_RETRY then return true end
    end
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
  local node_seq = {}
  local function node_key(n)
    local base = tostring(n.id) .. "\1" .. tostring(n.parent)
    local seq = (node_seq[base] or 0) + 1
    node_seq[base] = seq
    return base .. "\1" .. tostring(seq)
  end
  local function drop_props_of(id)
    self._props[id] = nil
  end
  for i = 1, #nodes do
    local n = nodes[i]
    local nkey = node_key(n)
    -- 701：选关静态控件会迟到或重建；未找到不能当作已经下发。
    local select_content = is_select_content744(n.id)
    local was_created743 = self._created[n.id]
    local select_ctrl = nil
    if select_content and type(adapter.find) == "function" then
      local ok_f, res_f = pcall(adapter.find, adapter, n.id)
      if ok_f then select_ctrl = res_f end
      self._select_handles = self._select_handles or {}
      if self._select_handles[n.id] ~= select_ctrl then
        drop_props_of(n.id)
        self._created[n.id] = nil
        self._select_handles[n.id] = select_ctrl
      end
    end
    if n.event ~= nil and adapter ~= nil and adapter.rebind_if_replaced747 ~= nil
       and (screen_switched747 or not self._created[n.id]) then
      local ok_rb, replaced = pcall(adapter.rebind_if_replaced747, adapter, n.id, n)
      if ok_rb and replaced == true then
        drop_props_of(n.id)
        self._created[n.id] = true
      end
    end
    if not self._created[n.id] then
      local ok_c, err_c = pcall(adapter.create_control, adapter, n)
      if not ok_c then
        self:_grid_log("create_err:" .. tostring(n.id), "创建控件失败（已跳过这一条，不再每帧刷）：`"
          .. tostring(n.id) .. "` ← " .. tostring(err_c))
      end
      self._created[n.id] = (not select_content) or select_ctrl ~= nil
      if self._prop_retry ~= nil then
        local pre = tostring(n.id) .. "\1"
        local stale = {}
        for rk in pairs(self._prop_retry) do
          if rk:sub(1, #pre) == pre then stale[#stale + 1] = rk end
        end
        for j = 1, #stale do self._prop_retry[stale[j]] = nil end
      end
    end
    local found = was_created743 and self._created[n.id] and select_ctrl ~= nil or false
    local bucket = self._props[n.id]
    if not bucket then
      bucket = {}
      self._props[n.id] = bucket
    end
    local last = bucket[nkey]
    if last == nil then
      last = {}
      bucket[nkey] = last
    end
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
          local exists
          exists, found = render_exists743(adapter, n.id, found)
          local ok = exists and self:_set_prop(adapter, n.id, k, v, nkey)
          if not ok then found = false end
          if ok and exists then
            last[k] = v
            retry_clear(n.id, k)
          elseif not exists then
            if not select_content then
              last[k] = v
            else
              self._pending_retry744 = true
              self._pending_retry_ids746 = self._pending_retry_ids746 or {}
              self._pending_retry_ids746[n.id] = "missing"
            end
          else
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            if not select_content and retry_more(n.id, k, why, exists) == false then
              last[k] = v
            else
              self._pending_retry744 = true
              self._pending_retry_ids746 = self._pending_retry_ids746 or {}
              self._pending_retry_ids746[n.id] = "write"
            end
          end
        end
      end
    end
    local lr = last.__rect
    if force or not lr or lr.x ~= n.rect.x or lr.y ~= n.rect.y or lr.w ~= n.rect.w or lr.h ~= n.rect.h then
      if adapter.instantiated and adapter.instantiated[n.id] then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      elseif n.pos_runtime == true then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      end
      local rect_exists
      rect_exists, found = render_exists743(adapter, n.id, found)
      local rok = rect_exists and self:_set_prop(adapter, n.id, "rect", n.rect, nkey)
      if rok then
        rect_record743(last, n.rect)
        retry_clear(n.id, "__rect")
      elseif not rect_exists then
        if not select_content then
          rect_record743(last, n.rect)
        else
          self._pending_retry744 = true
          self._pending_retry_ids746 = self._pending_retry_ids746 or {}
          if self._pending_retry_ids746[n.id] == nil then self._pending_retry_ids746[n.id] = "missing" end
        end
      elseif not select_content and retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        rect_record743(last, n.rect)
      else
        self._pending_retry744 = true
        self._pending_retry_ids746 = self._pending_retry_ids746 or {}
        self._pending_retry_ids746[n.id] = "write"
      end
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      if stale_legacy(id) then
        self._created[id] = nil
        drop_props_of(id)
      else
        pcall(adapter.destroy_control, adapter, id)
        self._created[id] = nil
        drop_props_of(id)
      end
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    if not stale_legacy(e.target) then
      pcall(adapter.play_effect, adapter, e.target, e.kind, e)
    end
  end
  self.effects = {}
  self.dirty = false
end
return M

end

__M["engine_adapter"] = function()
local M = {}
M.interface = {
  "log", "create_control", "destroy_control", "set_property", "play_effect",
  "bind_input", "now", "after", "cancel", "save", "load",
  "signal_emit", "signal_on", "random_int",
}
local Stub = {}
Stub.__index = Stub
function M.new_stub(opts)
  opts = opts or {}
  local self = setmetatable({}, Stub)
  self.log_lines = {}
  self.controls = {}      
  self.props = {}         
  self.effects = {}
  self.input_handlers = {}   
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
function Stub:save(key, value, opts) self.storage[key] = value return true end
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
local M = {}
M.VERSION = "1.0.0"
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
  SETTLE     = "murdoku/settle",
}
M.SIGNAL_SCHEMA = {
  [M.SIGNALS.READY]      = { "level_id", "rows", "cols", "piece_count" },
  [M.SIGNALS.PLACE]      = { "who", "r", "c" },
  [M.SIGNALS.CLEAR]      = { "who" },
  [M.SIGNALS.SUBMIT]     = { "ok" },
  [M.SIGNALS.ACCUSE]     = { "thief", "has_accomplice", "correct" },
  [M.SIGNALS.SOLVED]     = { "level_id", "elapsed", "moves", "failed_accusations" },
  [M.SIGNALS.SAVE]       = { "level_id", "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.RESTORE]    = { "state_code", "moves", "elapsed", "solved", "level_id" },
  [M.SIGNALS.SYNC_STATE] = { "who", "r", "c" },
  [M.SIGNALS.SETTLE]     = { "level_id" },
}
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
local Adapter = {}
Adapter.__index = Adapter
M.Adapter = Adapter
function M.pack_color(r, g, b, a)
  local function c(v)
    v = tonumber(v)
    if v == nil then v = 0 end
    v = math.floor(v + 0.5)
    if v < 0 then v = 0 end
    if v > 255 then v = 255 end
    return v
  end
  if a == nil then a = 255 end
  return c(a) * 16777216 + c(r) * 65536 + c(g) * 256 + c(b)
end
local function size_of(ctrl)
  if ctrl == nil then return nil, nil end
  local a, b = nil, nil
  if ctrl.GetSizeDelta ~= nil then
    pcall(function() a, b = ctrl:GetSizeDelta() end)
  end
  if type(a) == "table" then return tonumber(a[1]), tonumber(a[2]) end
  if type(a) == "number" then return tonumber(a), tonumber(b) end
  local px, py = nil, nil
  pcall(function() px = ctrl.sizeDeltaX end)
  pcall(function() py = ctrl.sizeDeltaY end)
  return tonumber(px), tonumber(py)
end
function M.new(cfg)
  cfg = cfg or {}
  if type(cfg.cells) == "table" then
    for _, k in ipairs({ "debug_key", "debug_image", "debug_event" }) do
      if cfg[k] == nil and cfg.cells[k] ~= nil then cfg[k] = cfg.cells[k] end
    end
  end
  local self = setmetatable({}, Adapter)
  self.cfg = cfg
  if print then
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
  self.controls = {}        
  self._misses = nil        
  self._lookup_hits = 0     
  self._lookup_gen = 0      
  self._subtree_dirty = true
  self._ray = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
  self.handlers = {}        
  self.events = {}          
  self.event_claim = {}
  self.event_latest = {}
  self.subs = {}            
  self._sub_miss = {}
  self.timers = {}
  self.clock = 0
  self.state = {}           
  self.warned = {}
  self.on_input = nil
  self.apply_rect = cfg.apply_rect == true    
  self.text_editor_first = {}
  do
    local list = cfg.text_editor_first
    if type(list) == "table" then
      for i = 1, #list do
        if type(list[i]) == "string" then self.text_editor_first[list[i]] = true end
      end
    end
  end
  return self
end
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
function Adapter:_note_missing(id)
  if id == nil then return end
  self.missing = self.missing or {}
  if self.missing[id] == nil then
    self.missing[id] = true
    self.missing_count = (self.missing_count or 0) + 1
  end
end
local function missing_group(id)
  local s = tostring(id)
  if s:match("^cell%.[%d]+%.[%d]+$")  then return "cell.*"  end
  if s:match("^clue%.[%d]+$")         then return "clue.N"  end
  if s:match("^tray%.[%w_]+$")        then return "tray.*"  end
  if s:match("^modal%.")              then return "modal.*" end
  if s:match("^action%.")             then return "action.*"
  end
  local head = s:match("^([%w_]+)%.")
  if head ~= nil then return head .. ".*" end
  return s
end
function Adapter:report_missing(force)
  if self.missing == nil then return 0 end
  if self.missing_reported and not force then return 0 end
  self.missing_reported = true
  local KNOWN_ABSENT = {
    "clue.",    
    "clues.",   
    "board",    
    "left",     
    "legend",   
    "tray",     
    "room.",    
    "obj.",     
  }
  local function known_absent(id)
    for i = 1, #KNOWN_ABSENT do
      local p = KNOWN_ABSENT[i]
      if id == p or id:sub(1, #p) == p then return true end
    end
    return false
  end
  local unknown, known_n = {}, 0
  for id in pairs(self.missing) do
    if known_absent(id) then known_n = known_n + 1 else unknown[#unknown + 1] = id end
  end
  table.sort(unknown)
  local groups, order = {}, {}
  for i = 1, #unknown do
    local id = unknown[i]
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
  if print and known_n > 0 then
    print("[murdoku] 规划里有 " .. tostring(known_n) .. " 个控件是【已知不需要】的"
      .. "（旧线索卡 / 旧滚动条 / board / left / legend / select / tray / room.* / obj.*）"
      .. " —— 按 info 打，不再当错误（名单见 adapter 的 KNOWN_ABSENT）")
  end
  if printerr and #unknown > 0 then
    printerr("[murdoku] ⚠️ 有 " .. tostring(#unknown)
      .. " 个控件【计划有、存档没有、又没有创建路】—— 这是**真问题**，去补计划或补存档：")
    for i = 1, #order do
      local g = order[i]
      local gd = groups[g]
      local samp = table.concat(gd.sample, " ")
      if gd.n > #gd.sample then samp = samp .. " …" end
      printerr("[murdoku]   " .. g .. "  ×" .. gd.n .. "   " .. samp)
    end
    printerr("[murdoku] （全部缺失项见 `node tools/gil/check_names.mjs` 的 🔴 那一组）")
  end
  return self.missing_count or 0
end
local function find_in(ctrl, name, depth)
  if ctrl == nil or depth > 16 then return nil end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname == name then return ctrl end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do
      local hit = find_in(children[i], name, depth + 1)
      if hit then return hit end
    end
  end
  return nil
end
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
local function p744_name(c) return c.name end
local function p744_kids(c) return c:GetChildren() end
local function p744_child(c, k) return c:GetChild(k) end
local function p744_vis(c) return c.visible end
local function p744_set_vis(c, v) c:SetVisible(v) end
local function p744_ray_get(c) return c.raycastTarget end
local function p744_ray_set(c, v) c.raycastTarget = v end
local function p744_cur_set(c) if c.showCursor ~= true then c.showCursor = true end end
local function p744_field(c, k) return c[k] end
-- 748（B2/B3/U6）：全脚本统一使用单操作顶层无闭包静态 helper，同时保证 0 闭包分配与严格单属性异常隔离。
local function p748_set_active_true(c)
  if c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
end
local function p748_set_vis_if(c, want)
  local prev_vis = c.visible
  if c.SetVisible ~= nil and prev_vis ~= want then c:SetVisible(want) end
  return prev_vis
end
local function p745_set_vis_guard(c, want)
  if want then pcall(p748_set_active_true, c) end
  local ok_v, prev_vis = pcall(p748_set_vis_if, c, want)
  return ok_v, prev_vis
end
local function p748_set_bool_prop(c, key, want)
  local cur = c[key]
  if cur ~= nil and cur ~= want then c[key] = want end
end
local function p745_set_vis_false(c)
  if c.SetVisible ~= nil then
    if c.visible ~= false then c:SetVisible(false) end
  elseif c.SetActive ~= nil then
    if c.active ~= false then c:SetActive(false) end
  end
end
local function p745_last_sib(c) c:SetAsLastSibling() end
local function p745_index_node(c) return c.name, c:GetChildren() end
local function p745_ray_step(c, want)
  local before = c.raycastTarget
  local did = false
  if before ~= nil and before ~= want then
    c.raycastTarget = want
    did = true
  end
  return before, did, c:GetChildren()
end
local function p748_ray_leaf_step(c, want)
  local before = c.raycastTarget
  local did = false
  if before ~= nil and before ~= want then
    c.raycastTarget = want
    did = true
  end
  return before, did
end
function Adapter:_root_alive745()
  local r = self.controls and self.controls["root"]
  if r == nil then return false end
  local ok_n, nm = pcall(p744_name, r)
  if not ok_n or nm ~= "root" then return false end
  if game == nil or game.GetClientUIRoots == nil then return true end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if not ok_r or type(roots) ~= "table" then return false end
  for i = 1, #roots do
    if roots[i] == r then return true end
  end
  return false
end
function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._miss_streak = nil
  self._name_idx_stable = 0
  self._floor_slots = nil
  self._floor_faces = nil
  self._floor_layout = nil
  self.controls = {}
  self.subs = {}
  self._sub_miss = nil
  self._mark_layer = nil
  self._mark_ctl_cache = nil
  self._mark_layer_dirty745 = true
  self._ray_done_gen745 = nil
  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._subtree_retry_at747 = nil
  self._subtree_urgent747 = false
  self._hidden_enforced746 = nil
  self._bound_nodes747 = nil
  self._watch_handles748 = nil
  self._name_idx_pruned748 = nil
  self._root_cache748 = nil
  self._baked_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1
  if self.cfg and self.cfg.debug_lookup and print then
    print(PREFIX .. "控件名缓存作废（第 " .. tostring(self._lookup_gen) .. " 代）："
      .. tostring(why))
  end
end
function Adapter:drop_lookup(name)
  if name == nil then return end
  self.controls[name] = nil
  if self._misses ~= nil then self._misses[name] = nil end
  if self._miss_streak ~= nil then self._miss_streak[name] = nil end
end
-- 747（Perf-1）：纯美术画片/撕边/静态背景大容器及其碎片均由 STATIC_PATH_655 O(1) 直查或专用组 GetChildren 访问，
-- 构建全树名称索引时登记容器本身但不钻入数千静态画片碎片，将 _build_name_index 节点数从 8,578 压降至 ~720。
-- 748（B7/U8）：修正 747 的 TL.25/BL.26 拼写错误为真实控件名 TR.25/BR.26（构建期已与 .gil 树自动断言一致）；
-- 同时将跳过展开的容器记入 pruned 表，供命名空间定向补查使用，保证被剪枝容器内动态子控件绝不失明。
local INDEX_PRUNE748 = {
  ["adapt715r.background"] = true,
  ["adapt715r.TR.23"] = true, ["adapt715r.TR.24"] = true,
  ["adapt715r.TR.25"] = true, ["adapt715r.BR.26"] = true,
  ["adapt715r.BR.27"] = true, ["adapt715r.BR.28"] = true,
  ["adapt715r.WAX.12"] = true,
  ["art641.game"] = true,
  ["art642.select.backdrop"] = true,
  ["select.thumb.pool"] = true,
  ["econ.ui742"] = true,
  ["art685.mark.overlay"] = true,
  ["police-v19"] = true,
}
local function should_prune_index747(cname, depth)
  if type(cname) ~= "string" then return false end
  if INDEX_PRUNE748[cname] then return true end
  if depth == 0 and cname:sub(1, 5) == "furn." then return true end
  if cname:sub(1, 3) == "td." and cname:find("%.page%.%d+$") ~= nil then return true end
  return false
end
local function index_in(ctrl, depth, idx, n, pruned)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok_n, cname = pcall(p744_name, ctrl)
  if ok_n and cname ~= nil then
    if idx[cname] == nil then idx[cname] = ctrl end
    if should_prune_index747(cname, depth) then
      if pruned ~= nil and pruned[cname] == nil then pruned[cname] = ctrl end
      return n
    end
  end
  local okc, children = pcall(p744_kids, ctrl)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n, pruned) end
  end
  return n
end
local STATIC_PATH_655 = {}
do
  local function add(parent, names)
    for name in names:gmatch("[^\n]+") do STATIC_PATH_655[name] = parent end
  end
  add("", [=[root]=])
  add("root", [=[art641.home
art641.select
art641.game
settle.btn
tpl.ruler
assets
clues
tpl.cell.face
tpl.cell
tpl.stage
stage
labels
fart.tpl
home
topbar
right
modal
hex.back
hex.submit
hex.redo
hex.undo
hex.hint
hex.ok
hex.no
hit.back
hit.submit
hit.redo
hit.undo
hit.hint
hit.ok
hit.no
select.back
select.card.1
select.card.2
select.card.3
select.card.4
select.card.1.info
select.card.1.room.1
select.card.1.room.2
select.card.1.room.3
select.card.1.room.4
select.card.1.room.5
select.card.1.room.6
select.card.1.title
select.card.2.info
select.card.2.room.1
select.card.2.room.2
select.card.2.room.3
select.card.2.room.4
select.card.2.room.5
select.card.2.room.6
select.card.2.title
select.card.3.info
select.card.3.room.1
select.card.3.room.2
select.card.3.room.3
select.card.3.room.4
select.card.3.room.5
select.card.3.room.6
select.card.3.title
select.card.4.info
select.card.4.room.1
select.card.4.room.2
select.card.4.room.3
select.card.4.room.4
select.card.4.room.5
select.card.4.room.6
select.card.4.title
select.page
select.title
hit.select.back
hit.select.prev
hit.select.next
hit.select.card.1
hit.select.card.2
hit.select.card.3
hit.select.card.4
things
select.card.1.result
select.card.2.result
select.card.3.result
select.card.4.result
settle.btn.countdown
clues.help617
clues.help627.hit
td.home
td.l1
td.l2
help617
hint635.menu
hint635.result
block640.modal
block640.confirm
block640.home
block640.l1
block640.l2
game742.shade
art647.select.bg.base
adapt715r.background
adapt715r.background.fill]=])
  add("root/art641.home/adapt715r.BR.17", [=[art647.home.settle.shadow
art647.home.settle.yellow.shadow
art647.home.settle.yellow.edge
art647.home.settle.yellow
art647.home.settle.outline
art647.home.settle.outline.tri.top
art647.home.settle.outline.tri.bottom
art647.home.settle.ribbon
art647.home.settle.ribbon.tri.top
art647.home.settle.ribbon.tri.bottom
art647.home.settle.text]=])
  add("root/art641.select", [=[art642.select.buttons
art642.select.backdrop
art642.select.board
art642.select.paper
art642.select.thread
art642.select.frames
art642.select.lighting
adapt715r.TR.23
adapt715r.TR.24
adapt715r.TR.25
adapt715r.BR.26
adapt715r.BR.27
adapt715r.BR.28]=])
  add("root/art641.select/art642.select.buttons/adapt715r.BR.18", [=[art647.select.settle.shadow
art647.select.settle.yellow.shadow
art647.select.settle.yellow.edge
art647.select.settle.yellow
art647.select.settle.outline
art647.select.settle.outline.tri.top
art647.select.settle.outline.tri.bottom
art647.select.settle.ribbon
art647.select.settle.ribbon.tri.top
art647.select.settle.ribbon.tri.bottom
art647.select.settle.text]=])
  add("root/art641.select/art642.select.buttons/adapt715r.LM.19", [=[art647.select.diamond.left]=])
  add("root/art641.select/art642.select.buttons/adapt715r.RM.20", [=[art647.select.diamond.right]=])
  add("root/stage", [=[ruler.r.1
ruler.r.2
ruler.r.3
ruler.r.4
ruler.r.5
ruler.r.6
ruler.r.7
ruler.r.8
ruler.c.1
ruler.c.2
ruler.c.3
ruler.c.4
ruler.c.5
ruler.c.6
ruler.c.7
ruler.c.8
board.bg
board.floors
board.rugs]=])
  add("root/assets", [=[row.1.1
row.1.2
row.1.3
row.1.4
row.1.5
row.2.clue
row.2.1
row.2.2
row.2.3
row.2.4
row.2.5
row.2.6
row.3.1
row.3.2
row.3.3
row.3.4
row.3.5
row.3.6
row.4.1
row.4.2
row.4.3
row.4.4
row.4.5
row.4.6]=])
  add("root/clues", [=[clues.bg
clues.grid]=])
  add("root/stage/board.floors", [=[floor.cell.1.1
floor.cell.1.2
floor.cell.1.3
floor.cell.1.4
floor.cell.1.5
floor.cell.1.6
floor.cell.2.1
floor.cell.2.2
floor.cell.2.3
floor.cell.2.4
floor.cell.2.5
floor.cell.2.6
floor.cell.3.1
floor.cell.3.2
floor.cell.3.3
floor.cell.3.4
floor.cell.3.5
floor.cell.3.6
floor.cell.4.1
floor.cell.4.2
floor.cell.4.3
floor.cell.4.4
floor.cell.4.5
floor.cell.4.6
floor.cell.5.1
floor.cell.5.2
floor.cell.5.3
floor.cell.5.4
floor.cell.5.5
floor.cell.5.6
floor.cell.6.1
floor.cell.6.2
floor.cell.6.3
floor.cell.6.4
floor.cell.6.5
floor.cell.6.6
floor.cell.1.7
floor.cell.2.7
floor.cell.3.7
floor.cell.4.7
floor.cell.5.7
floor.cell.6.7
floor.cell.7.1
floor.cell.7.2
floor.cell.7.3
floor.cell.7.4
floor.cell.7.5
floor.cell.7.6
floor.cell.7.7]=])
  add("root/labels/grp653.static.1.labels", [=[label.1
label.2
label.3
label.4
label.5
label.6
label.7]=])
  add("root/home", [=[home.title
home.select
home.continue
home.shop
home.bag
adapt715r.LM.22]=])
  add("root/home/adapt715r.LM.22", [=[home.tutorial627.bg
home.tutorial627.ring
home.tutorial627.label
home.tutorial627.hit
home.tutorial627.mid]=])
  add("root/topbar", [=[hud.title
hud.timer]=])
  add("root/right", [=[hud.progress]=])
  add("root/modal", [=[result.bg
modal.exit
modal.save
modal.settle
modal.cancel
modal.title
modal.body
modal.stats
modal.level.selftest_theft_5x5
modal.level.case_001
modal.level.case_002
modal.level.case_003
result.next
result.exit
result.home
result.settle
win
result.title.1
result.title.2
result.title.3
result.msg.1
result.msg.2
result.msg.3
result.settle.countdown
modal.settle.countdown]=])
  add("root/modal/win", [=[win.1
win.2
win.3
win.4
win.result]=])
  add("root/things", [=[furn.chair
furn.plant
furn.statue
furn.table.h2
furn.table.v2
furn.shelf
furn.rug
furn.rug.2
furn.rug.3
furn.rug.4
furn.rug.5
furn.plant.2]=])
  add("root/td.home", [=[td.home.page.1]=])
  add("root/td.l1", [=[td.l1.page.1
td.l1.page.3
td.l1.page.7
td.l1.page.8]=])
  add("root/td.l2", [=[td.l2.page.2
td.l2.page.3
td.l2.page.4]=])
  add("root/help617", [=[help617.bg
help617.title
help617.body
help617.close
help617.close.hit]=])
  add("root/hint635.menu", [=[hint635.menu.bg
hint635.menu.title
hint635.menu.position
hint635.menu.clue
hint635.menu.close
hint635.menu.position.hit
hint635.menu.clue.hit
hint635.menu.close.hit]=])
  add("root/hint635.result", [=[hint635.result.bg
hint635.result.body
hint635.result.close
hint635.result.close.hit]=])
  add("root/block640.modal", [=[block640.modal.hit]=])
  add("root/block640.confirm", [=[block640.confirm.hit]=])
  add("root/block640.home", [=[block640.home.hit]=])
  add("root/block640.l1", [=[block640.l1.hit]=])
  add("root/block640.l2", [=[block640.l2.hit]=])
  add("root/art641.home/grp653.static.1.art641.home/adapt715r.LM.15", [=[art641.home.camera.body
art656.home.camera.side.l
art656.home.camera.side.r
art656.home.camera.seam
art656.home.camera.bottom
art656.home.camera.cap.slope
art656.home.camera.cap.high
art656.home.camera.bump0
art656.home.camera.bump1
art641.home.camera.top
art641.home.camera.window
art641.home.camera.dot0
art641.home.camera.dot1]=])
  add("root/art641.home/grp653.static.1.art641.home/adapt715r.RM.16", [=[art656.home.note.band0
art656.home.note.band1
art656.home.note.band2
art656.home.note.band3
art656.home.note.tape
art656.home.wave.upper.0
art656.home.wave.upper.1
art656.home.wave.upper.2
art656.home.wave.upper.3
art656.home.wave.upper.4
art656.home.wave.upper.5
art656.home.wave.upper.6
art656.home.wave.upper.7
art656.home.wave.upper.8
art656.home.wave.upper.9
art656.home.wave.upper.10
art656.home.wave.upper.11
art656.home.wave.dot.0
art656.home.wave.lower.0
art656.home.wave.lower.1
art656.home.wave.lower.2
art656.home.wave.lower.3
art656.home.wave.lower.4
art656.home.wave.lower.5
art656.home.wave.lower.6
art656.home.wave.lower.7
art656.home.wave.lower.8
art656.home.wave.lower.9
art656.home.wave.lower.10
art656.home.wave.lower.11
art656.home.wave.lower.12
art656.home.wave.lower.13
art656.home.wave.lower.14
art656.home.wave.lower.15]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.LM.1", [=[art661.clues.grid.paper
art661.clues.grid.v1
art661.clues.grid.v2
art661.clues.grid.v3
art661.clues.grid.v4
art661.clues.grid.v5
art661.clues.grid.v6
art661.clues.grid.v7
art661.clues.grid.v8
art661.clues.grid.v9
art661.clues.grid.v10
art661.clues.grid.v11
art661.clues.grid.v12
art661.clues.grid.v13
art661.clues.grid.v14
art661.clues.grid.v15
art661.clues.grid.v16
art661.clues.grid.v17
art661.clues.grid.v18
art661.clues.grid.v19
art661.clues.grid.v20
art661.clues.grid.v21
art661.clues.grid.v22
art661.clues.grid.v23
art661.clues.grid.v24
art661.clues.grid.v25
art661.clues.grid.h1
art661.clues.grid.h2
art661.clues.grid.h3
art661.clues.grid.h4
art661.clues.grid.h5
art661.clues.grid.h6
art661.clues.grid.h7
art661.clues.grid.h8
art661.clues.grid.h9
art661.clues.grid.h10
art661.clues.grid.h11
art661.clues.grid.h12
art661.clues.grid.h13
art661.clues.grid.h14
art661.clues.grid.h15
art661.clues.grid.h16
art661.clues.cover
art661.clues.cover.dash.top1
art661.clues.cover.dash.top2
art661.clues.cover.dash.top3
art661.clues.cover.dash.top4
art661.clues.cover.dash.top5
art661.clues.cover.dash.top6
art661.clues.cover.dash.top7
art661.clues.cover.dash.top8
art661.clues.cover.dash.top9
art661.clues.cover.dash.top10
art661.clues.cover.dash.top11
art661.clues.cover.dash.top12
art661.clues.cover.dash.right1
art661.clues.cover.dash.right2
art661.clues.cover.dash.right3
art661.clues.cover.dash.right4
art661.clues.cover.dash.right5
art661.clues.cover.dash.right6
art661.clues.cover.dash.right7
art661.clues.cover.dash.right8
art661.clues.cover.dash.right9
art661.clues.cover.dash.right10
art661.clues.cover.dash.right11
art661.clues.cover.dash.right12
art661.clues.cover.dash.right13
art661.clues.cover.dash.right14
art661.clues.cover.dash.bottom1
art661.clues.cover.dash.bottom2
art661.clues.cover.dash.bottom3
art661.clues.cover.dash.bottom4
art661.clues.cover.dash.bottom5
art661.clues.cover.dash.bottom6
art661.clues.cover.dash.bottom7
art661.clues.cover.dash.bottom8
art661.clues.cover.dash.bottom9
art661.clues.cover.dash.bottom10
art661.clues.cover.dash.bottom11
art661.clues.cover.dash.bottom12
art661.clues.frame.edge]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.TL.2", [=[art657.game.flag.back.shadow
art657.game.flag.back.outline
art657.game.flag.back.outline.tri.top
art657.game.flag.back.outline.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.TR.3", [=[art657.game.flag.submit.shadow
art657.game.flag.submit.outline
art657.game.flag.submit.outline.tri.top
art657.game.flag.submit.outline.tri.bottom
art657.game.flag.redo.shadow
art657.game.flag.redo.outline
art657.game.flag.redo.outline.tri.top
art657.game.flag.redo.outline.tri.bottom
art657.game.flag.undo.shadow
art657.game.flag.undo.outline
art657.game.flag.undo.outline.tri.top
art657.game.flag.undo.outline.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.BR.4", [=[art657.game.flag.hint.shadow
art657.game.flag.hint.outline
art657.game.flag.hint.outline.tri.top
art657.game.flag.hint.outline.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.TL.5", [=[art641.game.flag.back]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.TR.6", [=[art641.game.flag.submit
art641.game.flag.redo
art641.game.flag.undo]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.BR.7", [=[art641.game.flag.hint]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.LM.8", [=[art657.game.notebook.frame
art658.clues.binding
art657.game.notebook.ribbon
art657.game.notebook.ribbon.tri.top
art657.game.notebook.ribbon.tri.bottom
art676.binding.mid
art677.ring.1.holeOuter
art677.ring.1.holeInner
art677.ring.1.outer
art677.ring.1.mid
art677.ring.1.lit
art677.ring.1.low
art677.ring.1.top
art677.ring.1.tip
art677.ring.2.holeOuter
art677.ring.2.holeInner
art677.ring.2.outer
art677.ring.2.mid
art677.ring.2.lit
art677.ring.2.low
art677.ring.2.top
art677.ring.2.tip
art677.ring.3.holeOuter
art677.ring.3.holeInner
art677.ring.3.outer
art677.ring.3.mid
art677.ring.3.lit
art677.ring.3.low
art677.ring.3.top
art677.ring.3.tip
art677.ring.4.holeOuter
art677.ring.4.holeInner
art677.ring.4.outer
art677.ring.4.mid
art677.ring.4.lit
art677.ring.4.low
art677.ring.4.top
art677.ring.4.tip
art677.ring.5.holeOuter
art677.ring.5.holeInner
art677.ring.5.outer
art677.ring.5.mid
art677.ring.5.lit
art677.ring.5.low
art677.ring.5.top
art677.ring.5.tip
art677.ring.6.holeOuter
art677.ring.6.holeInner
art677.ring.6.outer
art677.ring.6.mid
art677.ring.6.lit
art677.ring.6.low
art677.ring.6.top
art677.ring.6.tip
art677.ring.7.holeOuter
art677.ring.7.holeInner
art677.ring.7.outer
art677.ring.7.mid
art677.ring.7.lit
art677.ring.7.low
art677.ring.7.top
art677.ring.7.tip
art677.ring.8.holeOuter
art677.ring.8.holeInner
art677.ring.8.outer
art677.ring.8.mid
art677.ring.8.lit
art677.ring.8.low
art677.ring.8.top
art677.ring.8.tip]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.TL.9", [=[art657.game.flag.back.ribbon.tri.top
art657.game.flag.back.ribbon.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.TR.10", [=[art657.game.flag.submit.ribbon.tri.top
art657.game.flag.submit.ribbon.tri.bottom
art657.game.flag.redo.ribbon.tri.top
art657.game.flag.redo.ribbon.tri.bottom
art657.game.flag.undo.ribbon.tri.top
art657.game.flag.undo.ribbon.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.BR.11", [=[art657.game.flag.hint.ribbon.tri.top]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.WAX.12", [=[art675.wax.fit000
art675.wax.fit001
art675.wax.fit002
art675.wax.fit003
art675.wax.fit004
art675.wax.fit005
art675.wax.fit006
art675.wax.fit007
art675.wax.fit008
art675.wax.fit009
art675.wax.fit010
art675.wax.fit011
art675.wax.fit012
art675.wax.fit013
art675.wax.fit014
art675.wax.fit015
art675.wax.fit016
art675.wax.fit017
art675.wax.fit018
art675.wax.fit019
art675.wax.fit020
art675.wax.fit021
art675.wax.fit022
art675.wax.fit023
art675.wax.fit024
art675.wax.fit025
art675.wax.fit026
art675.wax.fit027
art675.wax.fit028
art675.wax.fit029
art675.wax.fit030
art675.wax.fit031
art675.wax.fit032
art675.wax.fit033
art675.wax.fit034
art675.wax.fit035
art675.wax.fit036
art675.wax.fit037
art675.wax.fit038
art675.wax.fit039
art675.wax.fit040
art675.wax.fit041
art675.wax.fit042
art675.wax.fit043
art675.wax.fit044
art675.wax.fit045
art675.wax.fit046
art675.wax.fit047
art675.wax.fit048
art675.wax.fit049
art675.wax.fit050
art675.wax.fit051
art675.wax.fit052
art675.wax.fit053
art675.wax.fit054
art675.wax.fit055
art675.wax.fit056
art675.wax.fit057
art675.wax.fit058
art675.wax.fit059
art675.wax.fit060
art675.wax.fit061
art675.wax.fit062
art675.wax.fit063
art675.wax.fit064
art675.wax.fit065
art675.wax.fit066
art675.wax.fit067
art675.wax.fit068
art675.wax.fit069
art675.wax.fit070
art675.wax.fit071
art675.wax.fit072
art675.wax.fit073
art675.wax.fit074
art675.wax.fit075
art675.wax.fit076
art675.wax.fit077
art675.wax.fit078
art675.wax.fit079
art675.wax.fit080
art675.wax.fit081
art675.wax.fit082
art675.wax.fit083
art675.wax.fit084
art675.wax.fit085
art675.wax.fit086
art675.wax.fit087
art675.wax.fit088
art675.wax.fit089
art675.wax.fit090
art675.wax.fit091
art675.wax.fit092
art675.wax.fit093
art675.wax.fit094
art675.wax.fit095
art675.wax.fit096
art675.wax.fit097
art675.wax.fit098
art675.wax.fit099
art675.wax.fit100
art675.wax.fit101
art675.wax.fit102
art675.wax.fit103
art675.wax.fit104
art675.wax.fit105
art675.wax.fit106
art675.wax.fit107
art675.wax.fit108
art675.wax.fit109
art675.wax.fit110
art675.wax.fit111
art675.wax.fit112
art675.wax.fit113
art675.wax.fit114
art675.wax.fit115
art675.wax.fit116
art675.wax.fit117
art675.wax.fit118
art675.wax.fit119
art675.wax.fit120
art675.wax.fit121
art675.wax.fit122
art675.wax.fit123
art675.wax.fit124
art675.wax.fit125
art675.wax.fit126
art675.wax.fit127
art675.wax.fit128
art675.wax.fit129
art675.wax.fit130
art675.wax.fit131
art675.wax.fit132
art675.wax.fit133
art675.wax.fit134
art675.wax.fit135
art675.wax.fit136
art675.wax.fit137
art675.wax.fit138
art675.wax.fit139
art675.wax.fit140
art675.wax.fit141
art675.wax.fit142
art675.wax.fit143
art675.wax.fit144
art675.wax.fit145
art675.wax.fit146
art675.wax.fit147
art675.wax.fit148
art675.wax.fit149
art675.wax.fit150
art675.wax.fit151
art675.wax.fit152
art675.wax.fit153
art675.wax.fit154
art675.wax.fit155
art675.wax.fit156
art675.wax.fit157
art675.wax.fit158
art675.wax.fit159
art675.wax.fit160
art675.wax.fit161
art675.wax.fit162
art675.wax.fit163
art675.wax.fit164
art675.wax.fit165
art675.wax.fit166
art675.wax.fit167
art675.wax.fit168
art675.wax.fit169
art675.wax.fit170
art675.wax.fit171
art675.wax.fit172
art675.wax.fit173
art675.wax.fit174
art675.wax.fit175
art675.wax.fit176
art675.wax.fit177
art675.wax.fit178
art675.wax.fit179
art675.wax.fit180
art675.wax.fit181
art675.wax.fit182
art675.wax.fit183
art675.wax.fit184
art675.wax.fit185
art675.wax.fit186
art675.wax.fit187
art675.wax.fit188
art675.wax.fit189
art675.wax.fit190
art675.wax.fit191
art675.wax.fit192
art675.wax.fit193
art675.wax.fit194
art675.wax.fit195
art675.wax.fit196
art675.wax.fit197
art675.wax.fit198
art675.wax.fit199
art675.wax.fit200
art675.wax.fit201
art675.wax.fit202
art675.wax.fit203
art675.wax.fit204
art675.wax.fit205
art675.wax.fit206
art675.wax.fit207
art675.wax.fit208
art675.wax.fit209
art675.wax.fit210
art675.wax.fit211
art675.wax.fit212
art675.wax.fit213
art675.wax.fit214
art675.wax.fit215
art675.wax.fit216
art675.wax.fit217
art675.wax.fit218
art675.wax.fit219
art675.wax.fit220
art675.wax.fit221
art675.wax.fit222
art675.wax.fit223
art675.wax.fit224
art675.wax.fit225
art675.wax.fit226
art675.wax.fit227
art675.wax.fit228
art675.wax.fit229
art675.wax.fit230
art675.wax.fit231
art675.wax.fit232
art675.wax.fit233
art675.wax.fit234
art675.wax.fit235
art675.wax.fit236
art675.wax.fit237
art675.wax.fit238
art675.wax.fit239]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.BR.13", [=[art657.game.flag.hint.ribbon.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game/adapt715r.LM.14", [=[art658.help.tab.clip
art658.ribbon.clip
art661.tab.outline
art678.tab.outline.l1.rect
art678.tab.outline.l1.tri
art678.tab.outline.l2.rect
art678.tab.outline.l2.tri
art678.tab.outline.l3.rect
art678.tab.outline.l3.tri
art678.tab.outline.r1.rect
art678.tab.outline.r1.tri
art678.tab.outline.r2.rect
art678.tab.outline.r2.tri
art678.tab.outline.r3.rect
art678.tab.outline.r3.tri
art641.game.help.tab
art678.tab.main.l1.rect
art678.tab.main.l1.tri
art678.tab.main.l2.rect
art678.tab.main.l2.tri
art678.tab.main.l3.rect
art678.tab.main.l3.tri
art678.tab.main.r1.rect
art678.tab.main.r1.tri
art678.tab.main.r2.rect
art678.tab.main.r2.tri
art678.tab.main.r3.rect
art678.tab.main.r3.tri
art664.tab.mid.fit01
art664.tab.mid.fit02
art664.tab.mid.fit03
art664.tab.mid.fit04
art664.tab.mid.fit05
art664.tab.mid.fit06
art664.tab.mid.fit07
art664.tab.mid.fit08
art664.tab.mid.fit09
art664.tab.mid.fit10
art664.tab.mid.fit11
art664.tab.mid.fit12
art664.tab.mid.fit13
art664.tab.mid.fit14
art664.tab.hi.fit15
art664.tab.hi.fit16
art664.tab.hi.fit17
art664.tab.hi.fit18
art664.tab.hi.fit19
art664.tab.hi.fit20
art664.tab.hi.fit21
art664.tab.hi.fit22
art664.tab.hi.fit23
art661.ribbon.mid.rect
art661.ribbon.mid.tri
art661.ribbon.mid.patch2
art661.ribbon.mid.patch3
art661.ribbon.mid.patch4
art661.ribbon.dark.rect
art661.ribbon.dark.tri
art661.ribbon.dark.patch2
art661.ribbon.dark.patch3
art661.ribbon.dark.patch4
art661.ribbon.dark.patch5]=])
  add("root/art641.select/adapt715r.TR.23", [=[art651.select.tear.tr.paper.0
art651.select.tear.tr.paper.1
art651.select.tear.tr.paper.2
art651.select.tear.tr.paper.3
art651.select.tear.tr.paper.4
art651.select.tear.tr.paper.5
art651.select.tear.tr.paper.6
art651.select.tear.tr.paper.7
art651.select.tear.tr.paper.8
art651.select.tear.tr.paper.9
art651.select.tear.tr.paper.10
art651.select.tear.tr.paper.11
art651.select.tear.tr.paper.12
art651.select.tear.tr.paper.13
art651.select.tear.tr.paper.14
art651.select.tear.tr.paper.15
art651.select.tear.tr.paper.16
art651.select.tear.tr.paper.17
art651.select.tear.tr.paper.18
art651.select.tear.tr.paper.19
art651.select.tear.tr.paper.20
art651.select.tear.tr.paper.21
art651.select.tear.tr.paper.22
art651.select.tear.tr.paper.23
art651.select.tear.tr.paper.24
art651.select.tear.tr.paper.25
art651.select.tear.tr.paper.26
art651.select.tear.tr.paper.27
art651.select.tear.tr.paper.28
art651.select.tear.tr.paper.29
art651.select.tear.tr.paper.30
art651.select.tear.tr.paper.31
art651.select.tear.tr.paper.32
art651.select.tear.tr.paper.33
art651.select.tear.tr.paper.34
art651.select.tear.tr.paper.35
art651.select.tear.tr.paper.36
art651.select.tear.tr.paper.37
art651.select.tear.tr.paper.38
art651.select.tear.tr.paper.39
art651.select.tear.tr.paper.40
art651.select.tear.tr.paper.41
art651.select.tear.tr.paper.42
art651.select.tear.tr.paper.43
art651.select.tear.tr.paper.44
art651.select.tear.tr.paper.45
art651.select.tear.tr.paper.46
art651.select.tear.tr.paper.47
art651.select.tear.tr.paper.48
art651.select.tear.tr.paper.49
art651.select.tear.tr.paper.50
art651.select.tear.tr.paper.51
art651.select.tear.tr.paper.52
art651.select.tear.tr.paper.53
art651.select.tear.tr.paper.54
art651.select.tear.tr.paper.55
art651.select.tear.tr.paper.56
art651.select.tear.tr.paper.57
art651.select.tear.tr.paper.58
art651.select.tear.tr.paper.59
art651.select.tear.tr.paper.60
art651.select.tear.tr.paper.61
art651.select.tear.tr.paper.62
art651.select.tear.tr.paper.63
art651.select.tear.tr.paper.64
art651.select.tear.tr.paper.65
art651.select.tear.tr.paper.66
art651.select.tear.tr.paper.67
art651.select.tear.tr.paper.68
art651.select.tear.tr.paper.69
art651.select.tear.tr.paper.70
art651.select.tear.tr.paper.71
art651.select.tear.tr.paper.72
art651.select.tear.tr.paper.73
art651.select.tear.tr.paper.74
art651.select.tear.tr.paper.75
art651.select.tear.tr.paper.76
art651.select.tear.tr.paper.77
art651.select.tear.tr.paper.78
art651.select.tear.tr.paper.79
art651.select.tear.tr.paper.80
art651.select.tear.tr.paper.81
art651.select.tear.tr.paper.82
art651.select.tear.tr.paper.83
art651.select.tear.tr.paper.84
art651.select.tear.tr.paper.85
art651.select.tear.tr.paper.86
art651.select.tear.tr.paper.87
art651.select.tear.tr.paper.88
art651.select.tear.tr.paper.89
art651.select.tear.tr.paper.90
art651.select.tear.tr.paper.91
art651.select.tear.tr.paper.92
art651.select.tear.tr.paper.93
art651.select.tear.tr.paper.94
art651.select.tear.tr.paper.95
art651.select.tear.tr.paper.96
art651.select.tear.tr.paper.97
art651.select.tear.tr.paper.98
art651.select.tear.tr.paper.99
art651.select.tear.tr.paper.100
art651.select.tear.tr.paper.101
art651.select.tear.tr.paper.102
art651.select.tear.tr.paper.103
art651.select.tear.tr.paper.104
art651.select.tear.tr.paper.105
art651.select.tear.tr.paper.106
art651.select.tear.tr.paper.107
art651.select.tear.tr.paper.108
art651.select.tear.tr.paper.109
art651.select.tear.tr.paper.110
art651.select.tear.tr.paper.111
art651.select.tear.tr.paper.112
art651.select.tear.tr.paper.113
art651.select.tear.tr.paper.114
art651.select.tear.tr.paper.115
art651.select.tear.tr.paper.116
art651.select.tear.tr.paper.117
art651.select.tear.tr.paper.118
art651.select.tear.tr.paper.119
art651.select.tear.tr.paper.120
art651.select.tear.tr.paper.121
art651.select.tear.tr.paper.122
art651.select.tear.tr.paper.123
art651.select.tear.tr.paper.124
art651.select.tear.tr.paper.125
art651.select.tear.tr.paper.126
art651.select.tear.tr.paper.127
art651.select.tear.tr.paper.128
art651.select.tear.tr.paper.129
art651.select.tear.tr.paper.130
art651.select.tear.tr.paper.131
art651.select.tear.tr.paper.132
art651.select.tear.tr.paper.133
art651.select.tear.tr.paper.134
art651.select.tear.tr.paper.135
art651.select.tear.tr.paper.136
art651.select.tear.tr.paper.137
art651.select.tear.tr.paper.138
art651.select.tear.tr.paper.139
art651.select.tear.tr.paper.140]=])
  add("root/art641.select/adapt715r.BR.26", [=[art651.select.tear.bl.paper.2
art651.select.tear.bl.paper.3
art651.select.tear.bl.paper.4
art651.select.tear.bl.paper.5
art651.select.tear.bl.paper.6
art651.select.tear.bl.paper.7
art651.select.tear.bl.paper.8
art651.select.tear.bl.paper.9
art651.select.tear.bl.paper.10
art651.select.tear.bl.paper.11
art651.select.tear.bl.paper.12
art651.select.tear.bl.paper.13
art651.select.tear.bl.paper.14
art651.select.tear.bl.paper.15
art651.select.tear.bl.paper.16
art651.select.tear.bl.paper.17
art651.select.tear.bl.paper.18
art651.select.tear.bl.paper.19
art651.select.tear.bl.paper.20
art651.select.tear.bl.paper.21
art651.select.tear.bl.paper.22
art651.select.tear.bl.paper.23
art651.select.tear.bl.paper.24
art651.select.tear.bl.paper.25
art651.select.tear.bl.paper.26
art651.select.tear.bl.paper.27
art651.select.tear.bl.paper.28
art651.select.tear.bl.paper.29
art651.select.tear.bl.paper.30
art651.select.tear.bl.paper.31
art651.select.tear.bl.paper.32
art651.select.tear.bl.paper.33
art651.select.tear.bl.paper.34
art651.select.tear.bl.paper.35
art651.select.tear.bl.paper.36
art651.select.tear.bl.paper.37
art651.select.tear.bl.paper.38
art651.select.tear.bl.paper.39
art651.select.tear.bl.paper.40
art651.select.tear.bl.paper.41
art651.select.tear.bl.paper.42
art651.select.tear.bl.paper.43
art651.select.tear.bl.paper.44
art651.select.tear.bl.paper.45
art651.select.tear.bl.paper.46
art651.select.tear.bl.paper.47
art651.select.tear.bl.paper.48
art651.select.tear.bl.paper.49
art651.select.tear.bl.paper.50
art651.select.tear.bl.paper.51
art651.select.tear.bl.paper.52
art651.select.tear.bl.paper.53
art651.select.tear.bl.paper.54
art651.select.tear.bl.paper.55
art651.select.tear.bl.paper.56
art651.select.tear.bl.paper.57
art651.select.tear.bl.paper.58
art651.select.tear.bl.paper.59
art651.select.tear.bl.paper.60
art651.select.tear.bl.paper.61
art651.select.tear.bl.paper.62
art651.select.tear.bl.paper.63
art651.select.tear.bl.paper.64
art651.select.tear.bl.paper.65
art651.select.tear.bl.paper.66
art651.select.tear.bl.paper.67
art651.select.tear.bl.paper.68
art651.select.tear.bl.paper.69
art651.select.tear.bl.paper.70
art651.select.tear.bl.paper.71
art651.select.tear.bl.paper.72
art651.select.tear.bl.paper.73
art651.select.tear.bl.paper.74
art651.select.tear.bl.paper.75
art651.select.tear.bl.paper.76
art651.select.tear.bl.paper.77
art651.select.tear.bl.paper.78
art651.select.tear.bl.paper.79
art651.select.tear.bl.paper.80]=])
  add("root/art641.select/adapt715r.TR.24", [=[art651.select.tear.tr.white.0
art651.select.tear.tr.white.1
art651.select.tear.tr.white.2
art651.select.tear.tr.white.3
art651.select.tear.tr.white.4
art651.select.tear.tr.white.5
art651.select.tear.tr.white.6
art651.select.tear.tr.white.7
art651.select.tear.tr.white.8
art651.select.tear.tr.white.9
art651.select.tear.tr.white.10
art651.select.tear.tr.white.11
art651.select.tear.tr.white.12
art651.select.tear.tr.white.13
art651.select.tear.tr.white.14
art651.select.tear.tr.white.15
art651.select.tear.tr.white.16
art651.select.tear.tr.white.17
art651.select.tear.tr.white.18
art651.select.tear.tr.white.19
art651.select.tear.tr.white.20
art651.select.tear.tr.white.21
art651.select.tear.tr.white.22
art651.select.tear.tr.white.23
art651.select.tear.tr.white.24
art651.select.tear.tr.white.25
art651.select.tear.tr.white.26
art651.select.tear.tr.white.27
art651.select.tear.tr.white.28
art651.select.tear.tr.white.29
art651.select.tear.tr.white.30
art651.select.tear.tr.white.31
art651.select.tear.tr.white.32
art651.select.tear.tr.white.33
art651.select.tear.tr.white.34
art651.select.tear.tr.white.35
art651.select.tear.tr.white.36
art651.select.tear.tr.white.37
art651.select.tear.tr.white.38
art651.select.tear.tr.white.39
art651.select.tear.tr.white.40
art651.select.tear.tr.white.41
art651.select.tear.tr.white.42
art651.select.tear.tr.white.43
art651.select.tear.tr.white.44
art651.select.tear.tr.white.45
art651.select.tear.tr.white.46
art651.select.tear.tr.white.47
art651.select.tear.tr.white.48
art651.select.tear.tr.white.49
art651.select.tear.tr.white.50
art651.select.tear.tr.white.51
art651.select.tear.tr.white.52
art651.select.tear.tr.white.53
art651.select.tear.tr.white.54
art651.select.tear.tr.white.55
art651.select.tear.tr.white.56
art651.select.tear.tr.white.57
art651.select.tear.tr.white.58
art651.select.tear.tr.white.59
art651.select.tear.tr.white.60
art651.select.tear.tr.white.61
art651.select.tear.tr.white.62
art651.select.tear.tr.white.63
art651.select.tear.tr.white.64
art651.select.tear.tr.white.65
art651.select.tear.tr.white.66
art651.select.tear.tr.white.67
art651.select.tear.tr.white.68
art651.select.tear.tr.white.69
art651.select.tear.tr.white.70
art651.select.tear.tr.white.71
art651.select.tear.tr.white.72
art651.select.tear.tr.white.73
art651.select.tear.tr.white.74
art651.select.tear.tr.white.75
art651.select.tear.tr.white.76
art651.select.tear.tr.white.77
art651.select.tear.tr.white.78
art651.select.tear.tr.white.79
art651.select.tear.tr.white.80
art651.select.tear.tr.white.81
art651.select.tear.tr.white.82
art651.select.tear.tr.white.83
art651.select.tear.tr.white.84
art651.select.tear.tr.white.85
art651.select.tear.tr.white.86
art651.select.tear.tr.white.87
art651.select.tear.tr.white.88
art651.select.tear.tr.white.89
art651.select.tear.tr.white.90
art651.select.tear.tr.white.91
art651.select.tear.tr.white.92
art651.select.tear.tr.white.93
art651.select.tear.tr.white.94
art651.select.tear.tr.white.95
art651.select.tear.tr.white.96
art651.select.tear.tr.white.97
art651.select.tear.tr.white.98
art651.select.tear.tr.white.99
art651.select.tear.tr.white.100
art651.select.tear.tr.white.101
art651.select.tear.tr.white.102
art651.select.tear.tr.white.103
art651.select.tear.tr.white.104
art651.select.tear.tr.white.105
art651.select.tear.tr.white.106
art651.select.tear.tr.white.107
art651.select.tear.tr.white.108
art651.select.tear.tr.white.109
art651.select.tear.tr.white.110
art651.select.tear.tr.white.111
art651.select.tear.tr.white.112
art651.select.tear.tr.white.113
art651.select.tear.tr.white.114
art651.select.tear.tr.white.115
art651.select.tear.tr.white.116
art651.select.tear.tr.white.117
art651.select.tear.tr.white.118
art651.select.tear.tr.white.119
art651.select.tear.tr.white.120
art651.select.tear.tr.white.121
art651.select.tear.tr.white.122
art651.select.tear.tr.white.123
art651.select.tear.tr.white.124
art651.select.tear.tr.white.125
art651.select.tear.tr.white.126
art651.select.tear.tr.white.127
art651.select.tear.tr.white.128
art651.select.tear.tr.white.129
art651.select.tear.tr.white.130
art651.select.tear.tr.white.131
art651.select.tear.tr.white.132
art651.select.tear.tr.white.133
art651.select.tear.tr.white.134
art651.select.tear.tr.white.135
art651.select.tear.tr.white.136
art651.select.tear.tr.white.137
art651.select.tear.tr.white.138
art651.select.tear.tr.white.139
art651.select.tear.tr.white.140
art651.select.tear.tr.white.141
art651.select.tear.tr.white.142
art651.select.tear.tr.white.143
art651.select.tear.tr.white.144
art651.select.tear.tr.white.145
art651.select.tear.tr.white.146
art651.select.tear.tr.white.147
art651.select.tear.tr.white.148
art651.select.tear.tr.white.149
art651.select.tear.tr.white.150
art651.select.tear.tr.white.151
art651.select.tear.tr.white.152
art651.select.tear.tr.white.153
art651.select.tear.tr.white.154
art651.select.tear.tr.white.155
art651.select.tear.tr.white.156
art651.select.tear.tr.white.157
art651.select.tear.tr.white.158
art651.select.tear.tr.white.159
art651.select.tear.tr.white.160
art651.select.tear.tr.white.161
art651.select.tear.tr.white.162
art651.select.tear.tr.white.163
art651.select.tear.tr.white.164
art651.select.tear.tr.white.165
art651.select.tear.tr.white.166
art651.select.tear.tr.white.167
art651.select.tear.tr.white.168
art651.select.tear.tr.white.169
art651.select.tear.tr.white.170
art651.select.tear.tr.white.171
art651.select.tear.tr.white.172
art651.select.tear.tr.white.173
art651.select.tear.tr.white.174
art651.select.tear.tr.white.175
art651.select.tear.tr.white.176
art651.select.tear.tr.white.177
art651.select.tear.tr.white.178
art651.select.tear.tr.white.179
art651.select.tear.tr.white.180
art651.select.tear.tr.white.181
art651.select.tear.tr.white.182]=])
  add("root/art641.select/adapt715r.TR.25", [=[art651.select.tear.tr.joint.0
art651.select.tear.tr.joint.34
art651.select.tear.tr.joint.53
art651.select.tear.tr.joint.55
art651.select.tear.tr.joint.64
art651.select.tear.tr.joint.82
art651.select.tear.tr.joint.83
art651.select.tear.tr.joint.85
art651.select.tear.tr.joint.102
art651.select.tear.tr.joint.118
art651.select.tear.tr.joint.122
art651.select.tear.tr.joint.123
art651.select.tear.tr.joint.133
art651.select.tear.tr.joint.134
art651.select.tear.tr.joint.135
art651.select.tear.tr.joint.143
art651.select.tear.tr.joint.183]=])
  add("root/art641.select/adapt715r.BR.27", [=[art651.select.tear.bl.white.0
art651.select.tear.bl.white.1
art651.select.tear.bl.white.2
art651.select.tear.bl.white.3
art651.select.tear.bl.white.4
art651.select.tear.bl.white.5
art651.select.tear.bl.white.6
art651.select.tear.bl.white.7
art651.select.tear.bl.white.8
art651.select.tear.bl.white.9
art651.select.tear.bl.white.10
art651.select.tear.bl.white.11
art651.select.tear.bl.white.13
art651.select.tear.bl.white.14
art651.select.tear.bl.white.15
art651.select.tear.bl.white.16
art651.select.tear.bl.white.17
art651.select.tear.bl.white.18
art651.select.tear.bl.white.19
art651.select.tear.bl.white.20
art651.select.tear.bl.white.21
art651.select.tear.bl.white.22
art651.select.tear.bl.white.23
art651.select.tear.bl.white.24
art651.select.tear.bl.white.25
art651.select.tear.bl.white.26
art651.select.tear.bl.white.27
art651.select.tear.bl.white.28
art651.select.tear.bl.white.29
art651.select.tear.bl.white.30
art651.select.tear.bl.white.31
art651.select.tear.bl.white.32
art651.select.tear.bl.white.33
art651.select.tear.bl.white.34
art651.select.tear.bl.white.35
art651.select.tear.bl.white.36
art651.select.tear.bl.white.37
art651.select.tear.bl.white.38
art651.select.tear.bl.white.39
art651.select.tear.bl.white.40
art651.select.tear.bl.white.41
art651.select.tear.bl.white.42
art651.select.tear.bl.white.43
art651.select.tear.bl.white.44
art651.select.tear.bl.white.45
art651.select.tear.bl.white.46
art651.select.tear.bl.white.47
art651.select.tear.bl.white.48
art651.select.tear.bl.white.49
art651.select.tear.bl.white.50
art651.select.tear.bl.white.51
art651.select.tear.bl.white.52
art651.select.tear.bl.white.53
art651.select.tear.bl.white.54
art651.select.tear.bl.white.55
art651.select.tear.bl.white.56
art651.select.tear.bl.white.57
art651.select.tear.bl.white.58
art651.select.tear.bl.white.59
art651.select.tear.bl.white.60
art651.select.tear.bl.white.61
art651.select.tear.bl.white.62
art651.select.tear.bl.white.63
art651.select.tear.bl.white.64
art651.select.tear.bl.white.65
art651.select.tear.bl.white.66
art651.select.tear.bl.white.67
art651.select.tear.bl.white.68
art651.select.tear.bl.white.69
art651.select.tear.bl.white.70
art651.select.tear.bl.white.71
art651.select.tear.bl.white.72
art651.select.tear.bl.white.73
art651.select.tear.bl.white.74
art651.select.tear.bl.white.75
art651.select.tear.bl.white.76
art651.select.tear.bl.white.77
art651.select.tear.bl.white.78
art651.select.tear.bl.white.79
art651.select.tear.bl.white.80
art651.select.tear.bl.white.81
art651.select.tear.bl.white.82
art651.select.tear.bl.white.83
art651.select.tear.bl.white.84
art651.select.tear.bl.white.85
art651.select.tear.bl.white.86
art651.select.tear.bl.white.87
art651.select.tear.bl.white.88
art651.select.tear.bl.white.89
art651.select.tear.bl.white.90
art651.select.tear.bl.white.91
art651.select.tear.bl.white.92
art651.select.tear.bl.white.93
art651.select.tear.bl.white.94
art651.select.tear.bl.white.95
art651.select.tear.bl.white.96
art651.select.tear.bl.white.97
art651.select.tear.bl.white.98
art651.select.tear.bl.white.99
art651.select.tear.bl.white.100
art651.select.tear.bl.white.101
art651.select.tear.bl.white.102
art651.select.tear.bl.white.103
art651.select.tear.bl.white.104
art651.select.tear.bl.white.105
art651.select.tear.bl.white.106
art651.select.tear.bl.white.107
art651.select.tear.bl.white.108
art651.select.tear.bl.white.109
art651.select.tear.bl.white.110
art651.select.tear.bl.white.111
art651.select.tear.bl.white.112
art651.select.tear.bl.white.113
art651.select.tear.bl.white.114
art651.select.tear.bl.white.115
art651.select.tear.bl.white.116
art651.select.tear.bl.white.117
art651.select.tear.bl.white.118
art651.select.tear.bl.white.119
art651.select.tear.bl.white.120
art651.select.tear.bl.white.121
art651.select.tear.bl.white.122
art651.select.tear.bl.white.123
art651.select.tear.bl.white.124
art651.select.tear.bl.white.125
art651.select.tear.bl.white.126
art651.select.tear.bl.white.127
art651.select.tear.bl.white.128
art651.select.tear.bl.white.129
art651.select.tear.bl.white.130
art651.select.tear.bl.white.131
art651.select.tear.bl.white.132
art651.select.tear.bl.white.133
art651.select.tear.bl.white.134
art651.select.tear.bl.white.135
art651.select.tear.bl.white.136
art651.select.tear.bl.white.137
art651.select.tear.bl.white.138
art651.select.tear.bl.white.139
art651.select.tear.bl.white.140
art651.select.tear.bl.white.141
art651.select.tear.bl.white.142
art651.select.tear.bl.white.143
art651.select.tear.bl.white.144
art651.select.tear.bl.white.145
art651.select.tear.bl.white.146
art651.select.tear.bl.white.147
art651.select.tear.bl.white.148
art651.select.tear.bl.white.149
art651.select.tear.bl.white.150]=])
  add("root/art641.select/adapt715r.BR.28", [=[art651.select.tear.bl.joint.0
art651.select.tear.bl.joint.9
art651.select.tear.bl.joint.12
art651.select.tear.bl.joint.15
art651.select.tear.bl.joint.18
art651.select.tear.bl.joint.26
art651.select.tear.bl.joint.31
art651.select.tear.bl.joint.37
art651.select.tear.bl.joint.55
art651.select.tear.bl.joint.61
art651.select.tear.bl.joint.69
art651.select.tear.bl.joint.84
art651.select.tear.bl.joint.85
art651.select.tear.bl.joint.91
art651.select.tear.bl.joint.92
art651.select.tear.bl.joint.103
art651.select.tear.bl.joint.104
art651.select.tear.bl.joint.105
art651.select.tear.bl.joint.106
art651.select.tear.bl.joint.107
art651.select.tear.bl.joint.151]=])
  add("root/art641.select/art642.select.buttons/grp653.static.1.art642.select.buttons/adapt715r.TL.21", [=[art647.select.back.shadow
art647.select.back.outline
art647.select.back.outline.tri.top
art647.select.back.outline.tri.bottom
art647.select.back.ribbon
art647.select.back.ribbon.tri.top
art647.select.back.ribbon.tri.bottom]=])
  add("root/art641.game/grp653.static.1.art641.game", [=[adapt715r.LM.1
adapt715r.TL.2
adapt715r.TR.3
adapt715r.BR.4
adapt715r.TL.5
adapt715r.TR.6
adapt715r.BR.7
adapt715r.LM.8
adapt715r.TL.9
adapt715r.TR.10
adapt715r.BR.11
adapt715r.WAX.12
adapt715r.BR.13
adapt715r.LM.14]=])
  add("root/art641.home/grp653.static.1.art641.home", [=[adapt715r.LM.15
adapt715r.RM.16]=])
  add("root/art641.home", [=[adapt715r.BR.17]=])
  add("root/art641.select/art642.select.buttons", [=[adapt715r.BR.18
adapt715r.LM.19
adapt715r.RM.20]=])
  add("root/art641.select/art642.select.buttons/grp653.static.1.art642.select.buttons", [=[adapt715r.TL.21]=])
  add("root/adapt715r.background", [=[adapt715r.background.part.1
adapt715r.background.part.2
adapt715r.background.part.3
adapt715r.background.part.4
adapt715r.background.part.5
adapt715r.background.part.6
adapt715r.background.part.7
adapt715r.background.part.8
adapt715r.background.part.9
adapt715r.background.part.10
adapt715r.background.part.11
adapt715r.background.part.12
adapt715r.background.part.13
adapt715r.background.part.14
adapt715r.background.part.15
adapt715r.background.part.16
adapt715r.background.part.17
adapt715r.background.part.18
adapt715r.background.part.19
adapt715r.background.part.20
adapt715r.background.part.21
adapt715r.background.part.22
adapt715r.background.part.23
adapt715r.background.part.24
adapt715r.background.part.25
adapt715r.background.part.26
adapt715r.background.part.27
adapt715r.background.part.28
adapt715r.background.part.29
adapt715r.background.part.30
adapt715r.background.part.31
adapt715r.background.part.32
adapt715r.background.part.33
adapt715r.background.part.34
adapt715r.background.part.35
adapt715r.background.part.36
adapt715r.background.part.37
adapt715r.background.part.38
adapt715r.background.part.39
adapt715r.background.part.40
adapt715r.background.part.41
adapt715r.background.part.42
adapt715r.background.part.43
adapt715r.background.part.44
adapt715r.background.part.45
adapt715r.background.part.46
adapt715r.background.part.47
adapt715r.background.part.48
adapt715r.background.part.49
adapt715r.background.part.50
adapt715r.background.part.51
adapt715r.background.part.52
adapt715r.background.part.53
adapt715r.background.part.54
adapt715r.background.part.55
adapt715r.background.part.56
adapt715r.background.part.57
adapt715r.background.part.58
adapt715r.background.part.59
adapt715r.background.part.60
adapt715r.background.part.61
adapt715r.background.part.62
adapt715r.background.part.63
adapt715r.background.part.64
adapt715r.background.part.65
adapt715r.background.part.66
adapt715r.background.part.67
adapt715r.background.part.68
adapt715r.background.part.69
adapt715r.background.part.70
adapt715r.background.part.71
adapt715r.background.part.72
adapt715r.background.part.73
adapt715r.background.part.74
adapt715r.background.part.75
adapt715r.background.part.76
adapt715r.background.part.77
adapt715r.background.part.78
adapt715r.background.part.79
adapt715r.background.part.80
adapt715r.background.part.81
adapt715r.background.part.82
adapt715r.background.part.83
adapt715r.background.part.84
adapt715r.background.part.85
adapt715r.background.part.86
adapt715r.background.part.87
adapt715r.background.part.88
adapt715r.background.part.89
adapt715r.background.part.90
adapt715r.background.part.91
adapt715r.background.part.92
adapt715r.background.part.93
adapt715r.background.part.94
adapt715r.background.part.95
adapt715r.background.part.96
adapt715r.background.part.97
adapt715r.background.part.98
adapt715r.background.part.99
adapt715r.background.part.100
adapt715r.background.part.101
adapt715r.background.part.102
adapt715r.background.part.103
adapt715r.background.part.104
adapt715r.background.part.105
adapt715r.background.part.106
adapt715r.background.part.107
adapt715r.background.part.108
adapt715r.background.part.109
adapt715r.background.part.110
adapt715r.background.part.111
adapt715r.background.part.112
adapt715r.background.part.113
adapt715r.background.part.114
adapt715r.background.part.115
adapt715r.background.part.116
adapt715r.background.part.117
adapt715r.background.part.118
adapt715r.background.part.119
adapt715r.background.part.120
adapt715r.background.part.121
adapt715r.background.part.122
adapt715r.background.part.123
adapt715r.background.part.124
adapt715r.background.part.125
adapt715r.background.part.126
adapt715r.background.part.127
adapt715r.background.part.128
adapt715r.background.part.129
adapt715r.background.part.130
adapt715r.background.part.131
adapt715r.background.part.132
adapt715r.background.part.133
adapt715r.background.part.134
adapt715r.background.part.135
adapt715r.background.part.136
adapt715r.background.part.137
adapt715r.background.part.138
adapt715r.background.part.139
adapt715r.background.part.140
adapt715r.background.part.141
adapt715r.background.part.142
adapt715r.background.part.143
adapt715r.background.part.144
adapt715r.background.part.145
adapt715r.background.part.146
adapt715r.background.part.147
adapt715r.background.part.148
adapt715r.background.part.149
adapt715r.background.part.150
adapt715r.background.part.151
adapt715r.background.part.152
adapt715r.background.part.153
adapt715r.background.part.154
adapt715r.background.part.155
adapt715r.background.part.156
adapt715r.background.part.157
adapt715r.background.part.158
adapt715r.background.part.159
adapt715r.background.part.160
adapt715r.background.part.161
adapt715r.background.part.162
adapt715r.background.part.163
adapt715r.background.part.164
adapt715r.background.part.165
adapt715r.background.part.166
adapt715r.background.part.167
adapt715r.background.part.168
adapt715r.background.part.169
adapt715r.background.part.170
adapt715r.background.part.171
adapt715r.background.part.172
adapt715r.background.part.173
adapt715r.background.part.174
adapt715r.background.part.175
adapt715r.background.part.176
adapt715r.background.part.177
adapt715r.background.part.178
adapt715r.background.part.179
adapt715r.background.part.180
adapt715r.background.part.181
adapt715r.background.part.182
adapt715r.background.part.183
adapt715r.background.part.184
adapt715r.background.part.185
adapt715r.background.part.186
adapt715r.background.part.187
adapt715r.background.part.188
adapt715r.background.part.189
adapt715r.background.part.190
adapt715r.background.part.191
adapt715r.background.part.192
adapt715r.background.part.193
adapt715r.background.part.194
adapt715r.background.part.195
adapt715r.background.part.196
adapt715r.background.part.197
adapt715r.background.part.198
adapt715r.background.part.199
adapt715r.background.part.200
adapt715r.background.part.201
adapt715r.background.part.202
adapt715r.background.part.203
adapt715r.background.part.204
adapt715r.background.part.205
adapt715r.background.part.206
adapt715r.background.part.207
adapt715r.background.part.208
adapt715r.background.part.209
adapt715r.background.part.210
adapt715r.background.part.211
adapt715r.background.part.212
adapt715r.background.part.213
adapt715r.background.part.214
adapt715r.background.part.215
adapt715r.background.part.216
adapt715r.background.part.217
adapt715r.background.part.218
adapt715r.background.part.219
adapt715r.background.part.220
adapt715r.background.part.221
adapt715r.background.part.222
adapt715r.background.part.223
adapt715r.background.part.224
adapt715r.background.part.225
adapt715r.background.part.226
adapt715r.background.part.227
adapt715r.background.part.228
adapt715r.background.part.229
adapt715r.background.part.230
adapt715r.background.part.231
adapt715r.background.part.232
adapt715r.background.part.233
adapt715r.background.part.234
adapt715r.background.part.235
adapt715r.background.part.236
adapt715r.background.part.237
adapt715r.background.part.238
adapt715r.background.part.239
adapt715r.background.part.240
adapt715r.background.part.241
adapt715r.background.part.242
adapt715r.background.part.243
adapt715r.background.part.244
adapt715r.background.part.245
adapt715r.background.part.246
adapt715r.background.part.247
adapt715r.background.part.248
adapt715r.background.part.249
adapt715r.background.part.250
adapt715r.background.part.251
adapt715r.background.part.252
adapt715r.background.part.253
adapt715r.background.part.254
adapt715r.background.part.255
adapt715r.background.part.256
adapt715r.background.part.257
adapt715r.background.part.258
adapt715r.background.part.259
adapt715r.background.part.260
adapt715r.background.part.261
adapt715r.background.part.262
adapt715r.background.part.263
adapt715r.background.part.264
adapt715r.background.part.265
adapt715r.background.part.266
adapt715r.background.part.267
adapt715r.background.part.268
adapt715r.background.part.269
adapt715r.background.part.270
adapt715r.background.part.271
adapt715r.background.part.272
adapt715r.background.part.273
adapt715r.background.part.274
adapt715r.background.part.275
adapt715r.background.part.276
adapt715r.background.part.277
adapt715r.background.part.278
adapt715r.background.part.279
adapt715r.background.part.280
adapt715r.background.part.281
adapt715r.background.part.282
adapt715r.background.part.283
adapt715r.background.part.284
adapt715r.background.part.285
adapt715r.background.part.286
adapt715r.background.part.287
adapt715r.background.part.288
adapt715r.background.part.289
adapt715r.background.part.290
adapt715r.background.part.291
adapt715r.background.part.292
adapt715r.background.part.293
adapt715r.background.part.294
adapt715r.background.part.295
adapt715r.background.part.296
adapt715r.background.part.297
adapt715r.background.part.298
adapt715r.background.part.299
adapt715r.background.part.300
adapt715r.background.part.301
adapt715r.background.part.302
adapt715r.background.part.303
adapt715r.background.part.304
adapt715r.background.part.305
adapt715r.background.part.306
adapt715r.background.part.307
adapt715r.background.part.308
adapt715r.background.part.309
adapt715r.background.part.310
adapt715r.background.part.311
adapt715r.background.part.312
adapt715r.background.part.313
adapt715r.background.part.314
adapt715r.background.part.315
adapt715r.background.part.316
adapt715r.background.part.317
adapt715r.background.part.318
adapt715r.background.part.319
adapt715r.background.part.320
adapt715r.background.part.321
adapt715r.background.part.322
adapt715r.background.part.323
adapt715r.background.part.324
adapt715r.background.part.325
adapt715r.background.part.326
adapt715r.background.part.327
adapt715r.background.part.328
adapt715r.background.part.329
adapt715r.background.part.330
adapt715r.background.part.331
adapt715r.background.part.332
adapt715r.background.part.333
adapt715r.background.part.334
adapt715r.background.part.335
adapt715r.background.part.336
adapt715r.background.part.337
adapt715r.background.part.338
adapt715r.background.part.339
adapt715r.background.part.340
adapt715r.background.part.341
adapt715r.background.part.342
adapt715r.background.part.343
adapt715r.background.part.344
adapt715r.background.part.345
adapt715r.background.part.346
adapt715r.background.part.347
adapt715r.background.part.348
adapt715r.background.part.349
adapt715r.background.part.350
adapt715r.background.part.351
adapt715r.background.part.352
adapt715r.background.part.353
adapt715r.background.part.354
adapt715r.background.part.355
adapt715r.background.part.356
adapt715r.background.part.357
adapt715r.background.part.358
adapt715r.background.part.359
adapt715r.background.part.360
adapt715r.background.part.361
adapt715r.background.part.362
adapt715r.background.part.363
adapt715r.background.part.364
adapt715r.background.part.365
adapt715r.background.part.366
adapt715r.background.part.367
adapt715r.background.part.368
adapt715r.background.part.369
adapt715r.background.part.370
adapt715r.background.part.371
adapt715r.background.part.372
adapt715r.background.part.373
adapt715r.background.part.374
adapt715r.background.part.375
adapt715r.background.part.376
adapt715r.background.part.377
adapt715r.background.part.378
adapt715r.background.part.379
adapt715r.background.part.380
adapt715r.background.part.381
adapt715r.background.part.382
adapt715r.background.part.383
adapt715r.background.part.384
adapt715r.background.part.385
adapt715r.background.part.386
adapt715r.background.part.387
adapt715r.background.part.388
adapt715r.background.part.389
adapt715r.background.part.390
adapt715r.background.part.391
adapt715r.background.part.392
adapt715r.background.part.393
adapt715r.background.part.394
adapt715r.background.part.395
adapt715r.background.part.396
adapt715r.background.part.397
adapt715r.background.part.398
adapt715r.background.part.399
adapt715r.background.part.400
adapt715r.background.part.401
adapt715r.background.part.402
adapt715r.background.part.403
adapt715r.background.part.404
adapt715r.background.part.405
adapt715r.background.part.406
adapt715r.background.part.407
adapt715r.background.part.408
adapt715r.background.part.409
adapt715r.background.part.410
adapt715r.background.part.411
adapt715r.background.part.412
adapt715r.background.part.413
adapt715r.background.part.414
adapt715r.background.part.415
adapt715r.background.part.416
adapt715r.background.part.417
adapt715r.background.part.418
adapt715r.background.part.419
adapt715r.background.part.420
adapt715r.background.part.421
adapt715r.background.part.422
adapt715r.background.part.423
adapt715r.background.part.424
adapt715r.background.part.425
adapt715r.background.part.426
adapt715r.background.part.427
adapt715r.background.part.428
adapt715r.background.part.429
adapt715r.background.part.430
adapt715r.background.part.431
adapt715r.background.part.432
adapt715r.background.part.433
adapt715r.background.part.434
adapt715r.background.part.435
adapt715r.background.part.436
adapt715r.background.part.437
adapt715r.background.part.438
adapt715r.background.part.439
adapt715r.background.part.440
adapt715r.background.part.441
adapt715r.background.part.442
adapt715r.background.part.443
adapt715r.background.part.444
adapt715r.background.part.445
adapt715r.background.part.446
adapt715r.background.part.447
adapt715r.background.part.448
adapt715r.background.part.449
adapt715r.background.part.450
adapt715r.background.part.451
adapt715r.background.part.452
adapt715r.background.part.453
adapt715r.background.part.454
adapt715r.background.part.455
adapt715r.background.part.456
adapt715r.background.part.457
adapt715r.background.part.458
adapt715r.background.part.459
adapt715r.background.part.460
adapt715r.background.part.461
adapt715r.background.part.462
adapt715r.background.part.463
adapt715r.background.part.464
adapt715r.background.part.465
adapt715r.background.part.466
adapt715r.background.part.467
adapt715r.background.part.468
adapt715r.background.part.469
adapt715r.background.part.470
adapt715r.background.part.471
adapt715r.background.part.472
adapt715r.background.part.473
adapt715r.background.part.474
adapt715r.background.part.475
adapt715r.background.part.476
adapt715r.background.part.477
adapt715r.background.part.478
adapt715r.background.part.479
adapt715r.background.part.480
adapt715r.background.part.481
adapt715r.background.part.482
adapt715r.background.part.483
adapt715r.background.part.484
adapt715r.background.part.485
adapt715r.background.part.486
adapt715r.background.part.487
adapt715r.background.part.488
adapt715r.background.part.489
adapt715r.background.part.490
adapt715r.background.part.491
adapt715r.background.part.492
adapt715r.background.part.493
adapt715r.background.part.494
adapt715r.background.part.495
adapt715r.background.part.496
adapt715r.background.part.497
adapt715r.background.part.498
adapt715r.background.part.499
adapt715r.background.part.500
adapt715r.background.part.501
adapt715r.background.part.502
adapt715r.background.part.503
adapt715r.background.part.504
adapt715r.background.part.505
adapt715r.background.part.506
adapt715r.background.part.507
adapt715r.background.part.508
adapt715r.background.part.509
adapt715r.background.part.510
adapt715r.background.part.511
adapt715r.background.part.512
adapt715r.background.part.513
adapt715r.background.part.514
adapt715r.background.part.515
adapt715r.background.part.516
adapt715r.background.part.517
adapt715r.background.part.518
adapt715r.background.part.519
adapt715r.background.part.520
adapt715r.background.part.521
adapt715r.background.part.522
adapt715r.background.part.523
adapt715r.background.part.524
adapt715r.background.part.525
adapt715r.background.part.526
adapt715r.background.part.527
adapt715r.background.part.528
adapt715r.background.part.529
adapt715r.background.part.530
adapt715r.background.part.531
adapt715r.background.part.532
adapt715r.background.part.533
adapt715r.background.part.534
adapt715r.background.part.535
adapt715r.background.part.536
adapt715r.background.part.537
adapt715r.background.part.538
adapt715r.background.part.539
adapt715r.background.part.540
adapt715r.background.part.541
adapt715r.background.part.542
adapt715r.background.part.543
adapt715r.background.part.544
adapt715r.background.part.545
adapt715r.background.part.546
adapt715r.background.part.547
adapt715r.background.part.548
adapt715r.background.part.549
adapt715r.background.part.550
adapt715r.background.part.551
adapt715r.background.part.552
adapt715r.background.part.553
adapt715r.background.part.554
adapt715r.background.part.555
adapt715r.background.part.556
adapt715r.background.part.557
adapt715r.background.part.558
adapt715r.background.part.559
adapt715r.background.part.560
adapt715r.background.part.561
adapt715r.background.part.562
adapt715r.background.part.563
adapt715r.background.part.564
adapt715r.background.part.565
adapt715r.background.part.566
adapt715r.background.part.567
adapt715r.background.part.568
adapt715r.background.part.569
adapt715r.background.part.570
adapt715r.background.part.571
adapt715r.background.part.572
adapt715r.background.part.573
adapt715r.background.part.574
adapt715r.background.part.575
adapt715r.background.part.576
adapt715r.background.part.577
adapt715r.background.part.578
adapt715r.background.part.579
adapt715r.background.part.580
adapt715r.background.part.581
adapt715r.background.part.582
adapt715r.background.part.583
adapt715r.background.part.584
adapt715r.background.part.585
adapt715r.background.part.586
adapt715r.background.part.587
adapt715r.background.part.588
adapt715r.background.part.589
adapt715r.background.part.590
adapt715r.background.part.591
adapt715r.background.part.592
adapt715r.background.part.593
adapt715r.background.part.594
adapt715r.background.part.595
adapt715r.background.part.596
adapt715r.background.part.597
adapt715r.background.part.598
adapt715r.background.part.599
adapt715r.background.part.600
adapt715r.background.part.604
adapt715r.background.part.605
adapt715r.background.part.606
adapt715r.background.part.607
adapt715r.background.part.608
adapt715r.background.part.609
adapt715r.background.part.610
adapt715r.background.part.611
adapt715r.background.part.612
adapt715r.background.part.613
adapt715r.background.part.614
adapt715r.background.part.615
adapt715r.background.part.616
adapt715r.background.part.617
adapt715r.background.part.618
adapt715r.background.part.619
adapt715r.background.part.620
adapt715r.background.part.621
adapt715r.background.part.622
adapt715r.background.part.623
adapt715r.background.part.624
adapt715r.background.part.625
adapt715r.background.part.626
adapt715r.background.part.627
adapt715r.background.part.628
adapt715r.background.part.629
adapt715r.background.part.630
adapt715r.background.part.631
adapt715r.background.part.632
adapt715r.background.part.633
adapt715r.background.part.634
adapt715r.background.part.635
adapt715r.background.part.636
adapt715r.background.part.637
adapt715r.background.part.638
adapt715r.background.part.639
adapt715r.background.part.640
adapt715r.background.part.641
adapt715r.background.part.642
adapt715r.background.part.643
adapt715r.background.part.644
adapt715r.background.part.645
adapt715r.background.part.646
adapt715r.background.part.647
adapt715r.background.part.648
adapt715r.background.part.649]=])
  add("root/econ.ui742", [=[econ.shop736.anim.under
econ.shop736.anim.sheet
econ.bag741.anim.under
econ.bag741.anim.sheet]=])
  add("root/econ.ui742/econ.shop736.anim.sheet", [=[econ.shop736.card.border
econ.shop736.card.face
econ.shop736.s66
econ.shop736.anim.bend
econ.shop736.anim.ptop
econ.shop736.anim.pbot
econ.shop736.anim.top
econ.shop736.anim.bot]=])
  add("root/econ.ui742/econ.shop736.anim.sheet/econ.shop736.anim.bend", [=[econ.shop736.anim.b.br1
econ.shop736.anim.b.br2
econ.shop736.anim.b.br3
econ.shop736.anim.b.br4
econ.shop736.anim.b.br5
econ.shop736.anim.b.br6
econ.shop736.anim.b.br7
econ.shop736.anim.b.br8
econ.shop736.anim.b.br9
econ.shop736.anim.b.br10
econ.shop736.anim.b.br11
econ.shop736.anim.b.br12
econ.shop736.anim.b.br13
econ.shop736.anim.b.br14
econ.shop736.anim.b.br15
econ.shop736.anim.b.br16
econ.shop736.anim.b.fc1
econ.shop736.anim.b.fc2
econ.shop736.anim.b.fc3
econ.shop736.anim.b.fc4
econ.shop736.anim.b.fc5
econ.shop736.anim.b.fc6
econ.shop736.anim.b.fc7
econ.shop736.anim.b.fc8
econ.shop736.anim.b.fc9
econ.shop736.anim.b.fc10
econ.shop736.anim.b.fc11
econ.shop736.anim.b.fc12
econ.shop736.anim.b.fc13
econ.shop736.anim.b.fc14
econ.shop736.anim.b.fc15
econ.shop736.anim.b.fc16
econ.shop736.anim.b.in1
econ.shop736.anim.b.in2
econ.shop736.anim.b.in3
econ.shop736.anim.b.in4
econ.shop736.anim.b.in5
econ.shop736.anim.b.in6
econ.shop736.anim.b.in7
econ.shop736.anim.b.in8
econ.shop736.anim.b.in9
econ.shop736.anim.b.in10]=])
  add("root/econ.ui742/econ.shop736.anim.sheet/econ.shop736.anim.ptop", [=[econ.shop736.s67
econ.shop736.s69]=])
  add("root/econ.ui742/econ.shop736.anim.sheet/econ.shop736.anim.pbot", [=[econ.shop736.s68
econ.shop736.s70]=])
  add("root/econ.ui742/econ.shop736.anim.sheet/econ.shop736.anim.top", [=[econ.shop736.s65
econ.shop736.s110
econ.shop736.s111
econ.shop736.s112
econ.shop736.s113
econ.shop736.s114
econ.shop736.s115
econ.shop736.s116
econ.shop736.s117
econ.shop736.s118
econ.shop736.s119.edge
econ.shop736.s119
econ.shop736.s120
econ.shop736.s121
econ.shop736.s122.edge
econ.shop736.s122
econ.shop736.s125
econ.shop736.s126
econ.shop736.s127
econ.shop736.s128
econ.shop736.s129
econ.shop736.s130
econ.shop736.s131
econ.shop736.s131.top
econ.shop736.s131.bottom
econ.shop736.s132
econ.shop736.price
econ.shop736.owned]=])
  add("root/econ.ui742/econ.shop736.anim.sheet/econ.shop736.anim.bot", [=[econ.shop736.desc
econ.shop736.status]=])
  add("root/econ.ui742/econ.shop736.anim.under", [=[econ.shop736.anim.u.card.border
econ.shop736.anim.u.card.face
econ.shop736.anim.u.s66
econ.shop736.anim.u.s67
econ.shop736.anim.u.s69
econ.shop736.anim.u.s68
econ.shop736.anim.u.s70
econ.shop736.anim.u.s65
econ.shop736.anim.u.s110
econ.shop736.anim.u.s111
econ.shop736.anim.u.s112
econ.shop736.anim.u.s113
econ.shop736.anim.u.s114
econ.shop736.anim.u.s115
econ.shop736.anim.u.s116
econ.shop736.anim.u.s117
econ.shop736.anim.u.s118
econ.shop736.anim.u.s119.edge
econ.shop736.anim.u.s119
econ.shop736.anim.u.s120
econ.shop736.anim.u.s121
econ.shop736.anim.u.s122.edge
econ.shop736.anim.u.s122
econ.shop736.anim.u.s125
econ.shop736.anim.u.s126
econ.shop736.anim.u.s127
econ.shop736.anim.u.s128
econ.shop736.anim.u.s129
econ.shop736.anim.u.s130
econ.shop736.anim.u.s131
econ.shop736.anim.u.s131.top
econ.shop736.anim.u.s131.bottom
econ.shop736.anim.u.s132
econ.shop736.anim.u.price
econ.shop736.anim.u.owned
econ.shop736.anim.u.desc
econ.shop736.anim.u.status]=])
  add("root/econ.ui742/econ.bag741.anim.sheet", [=[econ.bag741.paper.top
econ.bag741.paper.label
econ.bag741.paper.body
econ.bag741.anim.bend
econ.bag741.anim.ptop
econ.bag741.anim.pbot
econ.bag741.anim.top
econ.bag741.anim.bot]=])
  add("root/econ.ui742/econ.bag741.anim.sheet/econ.bag741.anim.bend", [=[econ.bag741.anim.b.br1
econ.bag741.anim.b.br2
econ.bag741.anim.b.br3
econ.bag741.anim.b.br4
econ.bag741.anim.b.br5
econ.bag741.anim.b.br6
econ.bag741.anim.b.br7
econ.bag741.anim.b.br8
econ.bag741.anim.b.br9
econ.bag741.anim.b.br10
econ.bag741.anim.b.br11
econ.bag741.anim.b.br12
econ.bag741.anim.b.br13
econ.bag741.anim.b.br14
econ.bag741.anim.b.br15
econ.bag741.anim.b.br16
econ.bag741.anim.b.fc1
econ.bag741.anim.b.fc2
econ.bag741.anim.b.fc3
econ.bag741.anim.b.fc4
econ.bag741.anim.b.fc5
econ.bag741.anim.b.fc6
econ.bag741.anim.b.fc7
econ.bag741.anim.b.fc8
econ.bag741.anim.b.fc9
econ.bag741.anim.b.fc10
econ.bag741.anim.b.fc11
econ.bag741.anim.b.fc12
econ.bag741.anim.b.fc13
econ.bag741.anim.b.fc14
econ.bag741.anim.b.fc15
econ.bag741.anim.b.fc16
econ.bag741.anim.b.in1
econ.bag741.anim.b.in2
econ.bag741.anim.b.in3
econ.bag741.anim.b.in4
econ.bag741.anim.b.in5
econ.bag741.anim.b.in6
econ.bag741.anim.b.in7
econ.bag741.anim.b.in8
econ.bag741.anim.b.in9
econ.bag741.anim.b.in10
econ.bag741.anim.b.in11
econ.bag741.anim.b.in12
econ.bag741.anim.b.in13
econ.bag741.anim.b.in14]=])
  add("root/econ.ui742/econ.bag741.anim.sheet/econ.bag741.anim.ptop", [=[econ.bag741.paper.pin0
econ.bag741.paper.pin1]=])
  add("root/econ.ui742/econ.bag741.anim.sheet/econ.bag741.anim.pbot", [=[econ.bag741.paper.pin2
econ.bag741.paper.pin3]=])
  add("root/econ.ui742/econ.bag741.anim.sheet/econ.bag741.anim.top", [=[econ.bag741.title
econ.bag741.meta]=])
  add("root/econ.ui742/econ.bag741.anim.sheet/econ.bag741.anim.bot", [=[econ.bag741.desc
econ.bag741.usage
econ.bag741.history]=])
  add("root/econ.ui742/econ.bag741.anim.under", [=[econ.bag741.anim.u.paper.top
econ.bag741.anim.u.paper.label
econ.bag741.anim.u.paper.body
econ.bag741.anim.u.paper.pin0
econ.bag741.anim.u.paper.pin1
econ.bag741.anim.u.paper.pin2
econ.bag741.anim.u.paper.pin3
econ.bag741.anim.u.title
econ.bag741.anim.u.meta
econ.bag741.anim.u.desc
econ.bag741.anim.u.usage
econ.bag741.anim.u.history]=])
end

local function walk_route748(start, r, want)
  local cur = start
  for k = 2, #r do
    cur = cur:GetChild(r[k])
    if cur == nil then return nil end
  end
  if cur ~= nil and cur.name == want then return cur end
  return nil
end
local function path_lookup_655(roots, name, root_cache)
  local route = STATIC_PATH_655[name]
  if type(route) == "string" then
    route = route == "" and name or (route .. "/" .. name)
  end
  if route == nil then
    local b = type(name) == "string" and name:byte(1) or 0
    if b == 101 and name:sub(1, 5) == "econ." then
      route = (name:sub(1, 13) == "econ.shop736." or name:sub(1, 12) == "econ.bag741.") and "root/econ.ui742/" .. name or "root/" .. name
    elseif b == 97 then
      if name == "art641.select" then
        route = "root/art641.select"
      elseif name == "art642.select.frames" then
        route = "root/art641.select/art642.select.frames"
      elseif name:sub(1, 19) == "art647.select.card." and name:match("^art647%.select%.card%.%d+%.paper$") then
        route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames/" .. name
      elseif name == "art685.mark.overlay" then
        route = "root/stage/art685.mark.overlay"
      elseif name:sub(1, 12) == "art685.mark." then
        local base_m = name:match("^(art685%.mark%.%d+%.%d+)%.stroke%.%d+$")
        if base_m ~= nil then
          route = "root/stage/art685.mark.overlay/" .. base_m .. "/" .. name
        elseif name:match("^art685%.mark%.%d+%.%d+$") then
          route = "root/stage/art685.mark.overlay/" .. name
        else
          return nil
        end
      else
        return nil
      end
    elseif b == 103 then
      if name == "grp653.static.1.art642.select.frames" then
        route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames"
      elseif name == "grp653.static.1.art641.game" then
        route = "root/art641.game/grp653.static.1.art641.game"
      elseif name == "grp653.static.1.art642.select.backdrop" then
        route = "root/art641.select/art642.select.backdrop/grp653.static.1.art642.select.backdrop"
      else
        return nil
      end
    elseif b == 115 then
      if name == "select.thumb.pool" then
        route = "root/select.thumb.pool"
      elseif name:sub(1, 12) == "select.card." and (name:match("^select%.card%.%d+%.boardbg$")
          or name:match("^select%.card%.%d+%.cell%.")
          or name:match("^select%.card%.%d+%.wall%.")
          or name:match("^select%.card%.%d+%.door%.")) then
        route = "root/select.thumb.pool/" .. name
      else
        return nil
      end
    else
      return nil
    end
    STATIC_PATH_655[name] = route
  end
  -- 首次使用时把紧凑字符串路径拆成数组并回写，后续查找不再解析。
  if type(route) == "string" then
    local parts = {}
    for seg in route:gmatch("[^/]+") do parts[#parts + 1] = seg end
    STATIC_PATH_655[name] = parts
    route = parts
  end
  -- 748（B10/U12）：根缓存挂在 Adapter 实例（不再用模块级共享表），通过 roots[idx] == ctrl 做 O(1) 在树验证；
  -- 即使旧根句柄尚未销毁仍可读 name，只要已被替换离树立刻淘汰重查；若存在同名多根且首根未命中则继续查其余同名根。
  local r0_name = route[1]
  local ent = root_cache ~= nil and root_cache[r0_name] or nil
  if ent ~= nil and roots[ent.idx] == ent.ctrl then
    local ok_c, hit_c = pcall(walk_route748, ent.ctrl, route, name)
    if ok_c and hit_c ~= nil then return hit_c end
    if not ent.multi then
      return nil
    end
  elseif ent ~= nil and root_cache ~= nil then
    root_cache[r0_name] = nil
  end
  local first_hit_root, first_hit_idx, match_count = nil, nil, 0
  local found_ctrl = nil
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(p744_name, cur)
    if ok and rn == r0_name then
      match_count = match_count + 1
      if first_hit_root == nil then first_hit_root, first_hit_idx = cur, i end
      if found_ctrl == nil then
        local ok_w, hit = pcall(walk_route748, cur, route, name)
        if ok_w and hit ~= nil then
          found_ctrl = hit
          if root_cache ~= nil then
            root_cache[r0_name] = { ctrl = cur, idx = i, multi = (match_count > 1) }
          end
        end
      end
    end
  end
  if root_cache ~= nil and first_hit_root ~= nil then
    local prev = root_cache[r0_name]
    if prev == nil then
      root_cache[r0_name] = { ctrl = first_hit_root, idx = first_hit_idx, multi = (match_count > 1) }
    elseif match_count > 1 then
      prev.multi = true
    end
  end
  return found_ctrl
end
function Adapter:_build_name_index(roots)
  local prev_gen = self._name_idx_gen
  local prev_n = self._name_idx_nodes
  local idx = {}
  local pruned = {}
  local n = 0
  for i = 1, #roots do n = index_in(roots[i], 0, idx, n, pruned) end
  self._name_idx = idx
  self._name_idx_pruned748 = pruned
  self._name_idx_at = self.clock
  self._name_idx_gen = self._lookup_gen
  self._name_idx_builds = (self._name_idx_builds or 0) + 1
  self._name_idx_nodes = n
  -- 744：同一结构代数下若两次全树扫描节点数一致且非空，树已稳态，按 1→2→4→8→16s 退避复核；
  -- 代数变更或句柄失效立即归零恢复 1s 敏感度，兼顾稳态零抖动与迟到自愈。
  if prev_gen == self._lookup_gen and prev_n == n and n > 0 then
    self._name_idx_stable = math.min(4, (self._name_idx_stable or 0) + 1)
  else
    self._name_idx_stable = 0
  end
  return idx
end
-- 748（B7/U8）：当按名查找命中已知剪枝容器命名空间且未在静态路由/主索引命中时，仅定向下钻对应 1 个被剪容器；
-- 常规缺失名（如 cell.* / fart.* / board）完全不触发，兼顾全剪枝性能与剪枝容器动态子控件可达性。
function Adapter:_pruned_container_for748(name)
  if type(name) ~= "string" then return nil end
  local pruned = self._name_idx_pruned748
  if pruned == nil then return nil end
  local b = name:byte(1) or 0
  if b == 101 and name:sub(1, 5) == "econ." then
    -- econ.shop736.* / econ.bag741.* 已由 path_lookup_655 做过 O(1) econ.ui742:GetChild 直查，缺失时不再重复枚举 econ.ui742
    if name:sub(1, 13) == "econ.shop736." or name:sub(1, 12) == "econ.bag741." then return nil end
    return pruned["econ.ui742"]
  end
  if b == 103 and name:sub(1, 16) == "grp653.static.1." then
    local tail = name:sub(17)
    return pruned[tail]
  end
  if b == 97 then
    if name:sub(1, 12) == "art641.game." then return pruned["art641.game"] end
    if name:sub(1, 23) == "art642.select.backdrop." then return pruned["art642.select.backdrop"] end
    if name:sub(1, 12) == "art685.mark." then return pruned["art685.mark.overlay"] end
    if name:sub(1, 10) == "adapt715r." then
      if name:sub(1, 21) == "adapt715r.background." then return pruned["adapt715r.background"] end
      return pruned["art641.game"]
    end
    if name:sub(1, 11) == "art675.wax." then return pruned["adapt715r.WAX.12"] end
    if name:sub(1, 19) == "art651.select.tear." then
      local side = name:sub(20, 21)
      if side == "tr" then return pruned["adapt715r.TR.23"], pruned["adapt715r.TR.24"], pruned["adapt715r.TR.25"] end
      if side == "bl" then return pruned["adapt715r.BR.26"], pruned["adapt715r.BR.27"], pruned["adapt715r.BR.28"] end
    end
    if name:sub(1, 14) == "art647.select." then return pruned["art642.select.backdrop"] end
  elseif b == 116 and name:sub(1, 3) == "td." then
    local page_box = name:match("^(td%.[^%.]+%.page%.%d+)%.")
    if page_box ~= nil then return pruned[page_box] end
  elseif b == 115 and name:sub(1, 12) == "select.card." then
    return pruned["select.thumb.pool"]
  end
  return nil
end
function Adapter:_index_lookup(name, roots)
  local idx = self._name_idx
  local walked = false
  local idx_ttl = (self._name_idx_gen == self._lookup_gen)
    and math.min(16.0, 2 ^ (self._name_idx_stable or 0))
    or 1.0
  local stale = idx == nil or self._name_idx_gen ~= self._lookup_gen
    or self._name_idx_at == nil or (self.clock - self._name_idx_at) >= idx_ttl
  if stale then
    idx = self:_build_name_index(roots); walked = true
  end
  local hit = idx[name]
  if hit ~= nil then
    local ok, got = pcall(p744_name, hit)
    if ok and got == name then return hit end
  end
  -- 698：有效索引中的缺项也是有效结果；不为每个缺失名字重新扫描。
  -- TTL/结构代数负责刷新，失效句柄则单独重建一次并复位稳态退避。
  if hit ~= nil and not walked then
    self._name_idx_stable = 0
    idx = self:_build_name_index(roots)
    hit = idx[name]
    if hit ~= nil then return hit end
  end
  -- 748（B7）：仅当 name 属于已知被剪容器命名空间时，做单容器定向查找（0 全树成本）。
  local c1, c2, c3 = self:_pruned_container_for748(name)
  if c1 ~= nil then
    local found = find_in(c1, name, 0)
    if found == nil and c2 ~= nil then found = find_in(c2, name, 0) end
    if found == nil and c3 ~= nil then found = find_in(c3, name, 0) end
    if found ~= nil then
      idx[name] = found
      return found
    end
  end
  return nil
end
function Adapter:prefetch(names)
  if type(names) ~= "table" or #names == 0 then return 0 end
  if self.cfg and (self.cfg.find_index == false or self.cfg.prefetch == false) then return 0 end
  if game == nil or game.GetClientUIRoots == nil then return 0 end
  local need = false
  local miss = self._misses
  for i = 1, #names do
    local nm = names[i]
    if nm ~= nil and self.controls[nm] == nil then
      local st = miss and miss[nm]
      if st == nil or (st ~= false and self.clock >= st) then need = true; break end
    end
  end
  if not need then return 0 end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or not roots then return 0 end
  self._idx_trust = true
  for i = 1, #names do
    if names[i] ~= nil then pcall(self.find, self, names[i]) end
  end
  self._idx_trust = false
  return 1
end
function Adapter:has_static_route747(name)
  if type(name) ~= "string" then return false end
  if STATIC_PATH_655[name] ~= nil then return true end
  local b = name:byte(1) or 0
  if b == 101 and name:sub(1, 5) == "econ." then return true end
  if b == 97 and (name == "art641.select" or name == "art642.select.frames" or name == "art685.mark.overlay"
      or name:sub(1, 19) == "art647.select.card." or name:sub(1, 12) == "art685.mark.") then return true end
  if b == 103 and (name == "grp653.static.1.art642.select.frames"
      or name == "grp653.static.1.art641.game"
      or name == "grp653.static.1.art642.select.backdrop") then return true end
  if b == 115 and (name == "select.thumb.pool" or name:sub(1, 12) == "select.card.") then return true end
  return false
end
function Adapter:probe_static747(name, roots_opt)
  local roots = roots_opt
  if roots == nil then
    if game == nil or game.GetClientUIRoots == nil then return nil end
    local ok_r; ok_r, roots = pcall(game.GetClientUIRoots)
    if not ok_r or not roots then return nil end
  end
  local rc = self._root_cache748
  if rc == nil then rc = {}; self._root_cache748 = rc end
  local hit = path_lookup_655(roots, name, rc)
  if hit ~= nil then return hit end
  local pm = self.cfg and self.cfg.path_map
  local p = pm and pm[name]
  if p ~= nil then return control_by_path(roots, p) end
  return nil
end
-- 748（B5/U7）：统一交互控件句柄看护管理器，同时覆盖 Adapter:bind_input 静态按钮、util:_bind（help617/hint635/tutorial/block640）
-- 与动态棋盘格 cell.*，全部走 O(1) 路径或直属父容器 GetChild 比对（0 次 GetChildren）。
function Adapter:register_watch_handle748(id, ctrl, kind, payload, owner, sync_tbl)
  if id == nil or ctrl == nil then return end
  local w = self._watch_handles748
  if w == nil then w = {}; self._watch_handles748 = w end
  w[id] = { id = id, ctrl = ctrl, kind = kind, payload = payload, owner = owner, sync_tbl = sync_tbl }
end
function Adapter:probe_live_handle748(id, roots_opt)
  if type(id) ~= "string" then return nil end
  if self:has_static_route747(id) then
    return self:probe_static747(id, roots_opt)
  end
  if id:sub(1, 5) == "cell." then
    local host = (self.controls and (self.controls["board"] or self.controls["stage"])) or self:probe_static747("stage", roots_opt)
    if host ~= nil and host.GetChild ~= nil then
      local ok_g, child = pcall(p744_child, host, id)
      if ok_g and child ~= nil then return child end
    end
    return nil
  end
  if id:sub(1, 3) == "td." then
    local rname = id:match("^(td%.[^%.]+)%.")
    if rname ~= nil then
      local host = (self.controls and self.controls[rname]) or self:probe_static747(rname, roots_opt)
      if host ~= nil and host.GetChild ~= nil then
        local ok_g, child = pcall(p744_child, host, id)
        if ok_g and child ~= nil then return child end
      end
    end
  end
  return nil
end
function Adapter:_swap_live_handle748(id, live)
  self.controls[id] = live
  self:_note_lookup_hit(id)
  if self._misses ~= nil then self._misses[id] = nil end
  if self._hidden_enforced746 ~= nil then self._hidden_enforced746[id] = nil end
  local pre = tostring(id) .. "."
  if self.subs ~= nil then
    for sk in pairs(self.subs) do
      if type(sk) == "string" and sk:sub(1, #pre) == pre then self.subs[sk] = nil end
    end
  end
  if self._sub_miss ~= nil then
    for sk in pairs(self._sub_miss) do
      if type(sk) == "string" and sk:sub(1, #pre) == pre then self._sub_miss[sk] = nil end
    end
  end
  if self.ensure_raycast ~= nil and not (self._ray_want and self._ray_want[live] == false) then
    pcall(self.ensure_raycast, self, live)
  end
end
function Adapter:rebind_if_replaced747(id, node, roots_opt)
  if id == nil then return false end
  local cur_ctrl = self.controls[id]
  local live = self:probe_live_handle748(id, roots_opt)
  if live == nil or live == cur_ctrl then return false end
  self:_swap_live_handle748(id, live)
  local ent = self._watch_handles748 and self._watch_handles748[id] or nil
  if ent ~= nil then
    ent.ctrl = live
    if ent.sync_tbl ~= nil then ent.sync_tbl[id] = live end
  end
  local bnode = node or (ent and ent.kind == "adapter" and ent.payload) or (self._bound_nodes747 and self._bound_nodes747[id]) or (self.handlers and self.handlers[id])
  if bnode ~= nil and bnode.event ~= nil and (bnode.kind == "button" or bnode.kind == "cursor") then
    pcall(self.bind_input, self, id, bnode)
  elseif ent ~= nil and ent.kind == "util" and ent.owner ~= nil and ent.payload ~= nil then
    pcall(ent.owner._bind, ent.owner, id, ent.payload, live, ent.sync_tbl)
  end
  return true
end
function Adapter:_watch_relevant748(id, screen)
  if type(id) ~= "string" then return false end
  if screen == "home" then
    return id:sub(1, 5) == "home." or id:sub(1, 8) == "td.home." or id:sub(1, 9) == "block640."
  elseif screen == "select" then
    return id:sub(1, 7) == "select." or id:sub(1, 11) == "hit.select." or id:sub(1, 6) == "modal." or id:sub(1, 9) == "block640."
  elseif screen == "shop" or screen == "bag" then
    return id:sub(1, 5) == "econ." or id:sub(1, 9) == "block640."
  else
    -- 关内（screen == nil 或 "level"）：排除首页/选关/商城专用按钮，覆盖 clues.*/hint635.*/help617.*/hex.*/hit.*/cell.*/td.l1/l2/modal/result
    local b = id:byte(1) or 0
    if (b == 104 and id:sub(1, 5) == "home.") or (b == 115 and id:sub(1, 7) == "select.")
       or (b == 104 and id:sub(1, 11) == "hit.select.") or (b == 101 and id:sub(1, 5) == "econ.") then
      return false
    end
    return true
  end
end
function Adapter:check_watched_handles748(screen, ctrl_opt)
  local w = self._watch_handles748
  if w == nil then return false end
  if game == nil or game.GetClientUIRoots == nil then return false end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if not ok_r or type(roots) ~= "table" then return false end
  local hid = self._hidden_ids
  local any_rebound = false
  for bid, ent in pairs(w) do
    if self:_watch_relevant748(bid, screen) and (hid == nil or not hid[bid]) then
      local live = self:probe_live_handle748(bid, roots)
      if live ~= nil and live ~= ent.ctrl then
        self:_swap_live_handle748(bid, live)
        ent.ctrl = live
        if ent.sync_tbl ~= nil then ent.sync_tbl[bid] = live end
        if ent.kind == "adapter" then
          local bnode = ent.payload or (self.handlers and self.handlers[bid])
          if bnode ~= nil then pcall(self.bind_input, self, bid, bnode) end
          if ctrl_opt ~= nil and ctrl_opt._props ~= nil then ctrl_opt._props[bid] = nil end
          any_rebound = true
        elseif ent.kind == "util" and ent.owner ~= nil and ent.payload ~= nil then
          pcall(ent.owner._bind, ent.owner, bid, ent.payload, live, ent.sync_tbl)
          any_rebound = true
        end
      end
    end
  end
  if any_rebound and ctrl_opt ~= nil then ctrl_opt.dirty = true end
  return any_rebound
end
function Adapter:find(name)
  local hit0 = self.controls[name]
  if hit0 ~= nil then return hit0 end
  local miss = self._misses
  if miss ~= nil then
    local stamp = miss[name]
    if stamp ~= nil then
      if stamp == false or self.clock < stamp then return nil end
    end
  end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    if self.cfg == nil or self.cfg.find_index ~= false then
      local rc = self._root_cache748
      if rc == nil then rc = {}; self._root_cache748 = rc end
      local hit = path_lookup_655(roots, name, rc)
      if hit == nil then hit = self:_index_lookup(name, roots) end
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    else
      for i = 1, #roots do
        local hit = find_in(roots[i], name, 0)
        if hit then
          self.controls[name] = hit
          self:_note_lookup_hit(name)
          return hit
        end
      end
    end
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
  if self._lookup_hits > 0 then
    if self._misses == nil then self._misses = {} end
    local base_ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil or old == false or self.clock >= old then
      local streaks = self._miss_streak
      if streaks == nil then streaks = {}; self._miss_streak = streaks end
      local st = math.min(6, (streaks[name] or 0) + 1)
      streaks[name] = st
      local shift = (st > 2) and (st - 2) or 0
      local eff_ttl = math.min(math.max(base_ttl, 16.0), base_ttl * (2 ^ shift))
      self._misses[name] = self.clock + eff_ttl
    end
  end
  return nil
end
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._miss_streak ~= nil then self._miss_streak[name] = nil end
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty_ids = self._subtree_dirty_ids or {}
    self._subtree_dirty_ids[name] = true
  end
end
function Adapter:sub(parent_id, child_name)
  if child_name=="face" and parent_id:match("^cell%.%d+%.%d+$") then
    local slot=self:_floor_slot(parent_id)
    if slot then return self:_fixed_floor_face(parent_id, slot) end
  end
  do
    local miss = self._sub_miss
    if miss ~= nil then
      local mk = parent_id .. "." .. child_name
      if miss[mk] == self._lookup_gen then return nil end
    end
  end
  local key = parent_id .. "." .. child_name
  local cached = self.subs[key]
  if cached ~= nil and cached ~= false then return cached end
  local parent = self:find(parent_id)
  if parent == nil then return nil end
  local hit = nil
  if parent.GetChild ~= nil then
    local ok_g, res_g = pcall(p744_child, parent, child_name)
    if ok_g then hit = res_g end
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
  if hit == nil and child_name == "face" and type(parent_id) == "string"
     and parent_id:match("^cell%.") ~= nil and self._ensure_cell_face ~= nil then
    pcall(function() hit = self:_ensure_cell_face(parent_id, parent) end)
  end
  if hit ~= nil then
    self.subs[key] = hit
  else
    if self._lookup_gen ~= nil then
      self._sub_miss = self._sub_miss or {}
      self._sub_miss[key] = self._lookup_gen
    end
  end
  return hit
end
function Adapter:create_control(node)
  self.handlers[node.id] = node
  local ctrl = self:find(node.id)
  local AUTO_CONTAINER_KINDS = {
    container = true, panel = true, layer = true, list = true, box = true,
  }
  local function auto_prefab(ad, nd)
    if AUTO_CONTAINER_KINDS[nd.kind] then
      return ad.cfg.stage and ad.cfg.stage.prefab
    end
    if nd.icon_template == true and ad.cfg.prefab_icon ~= nil then
      return ad.cfg.prefab_icon
    end
    return ad.cfg.cells and ad.cfg.cells.prefab
  end
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
          self:invalidate_lookups("create:" .. tostring(node.id))
          self:rearm_raycast("create:" .. tostring(node.id))
          if node.image_id ~= nil then
            local function has_setimage(c)
              local has = false
              pcall(function() has = (c.SetImage ~= nil) end)
              return has
            end
            local found_name = nil
            local function find_target(c, depth)
              if c == nil or depth > 4 then return nil end
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
  if node.id == "home" or node.id == "select" then
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
  if node.event ~= nil and (node.kind == "button" or node.kind == "cursor") then
    self:bind_input(node.id, node)
  end
  return ctrl
end
function Adapter:cell_id(r, c) return string.format("cell.%d.%d", r, c) end
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
  local ruler = g.ruler or math.floor(avail * 0.06)      
  local area  = avail - 2 * ruler
  local pitch = math.floor(area / n)
  local gap   = g.gap or math.max(2, math.floor(pitch * 0.03))
  local size  = math.max(8, pitch - gap)
  local margin = ruler + math.floor((area - (n * pitch - gap)) / 2)
  if g.size   then size   = g.size   end
  if g.pitch  then pitch  = g.pitch  end
  if g.margin then margin = g.margin end
  return size, pitch, margin, pw, ph
end
function Adapter:sync_ruler721(controller)
  local playing = controller.screen == nil or controller.screen == 'level'
  local rows = playing and controller.core.rows or 0
  local cols = playing and controller.core.cols or 0
  local cells = self._cell_pos or {}
  local first = cells['cell.1.1']
  local last = cells['cell.' .. rows .. '.' .. cols]
  if playing and (not first or not last) then rows, cols = 0, 0 end
  local prev = self._ruler721
  if prev and prev.controller == controller and prev.rows == rows and prev.cols == cols
     and prev.first == first and prev.last == last then return end
  local complete = true
  for i = 1, 8 do
    for _, axis in ipairs({'r', 'c'}) do
      local row = axis == 'r'
      local on = i <= (row and rows or cols)
      local label = self:find('ruler.' .. axis .. '.' .. i)
      if label then
        if on then
          local p = cells[row and ('cell.' .. i .. '.1') or ('cell.1.' .. i)]
          if p then
            local x = row and (first[1] - first[3]/2 - 15) or p[1]
            local y = row and p[2] or (first[2] + first[3]/2 + 17)
            label:SetAnchoredPosition(x, y)
          else on, complete = false, false end
        end
        if label.SetActive then label:SetActive(on) end
        label:SetVisible(on)
      else complete = false end
    end
  end
  self._ruler721 = complete and {controller=controller, rows=rows, cols=cols, first=first, last=last} or nil
end
function Adapter:cell_offset(r, c, n)
  local g = self.cfg.cells
  if g == nil then return nil end
  n = n or g.rows or g.cols or math.max(r, c)
  local size, pitch, margin, pw, ph = self:cell_geometry(n)
  local x = margin + (c - 1) * pitch + size / 2 - pw / 2
  local y = ph - margin - (r - 1) * pitch - size + size / 2 - ph / 2
  return x, y
end
function Adapter:image_target(ctrl)
  if ctrl == nil then return nil end
  local found_name = nil
  local function has_setimage(c)
    local has = false
    pcall(function() has = (c.SetImage ~= nil) end)
    return has
  end
  local function usable(c)
    if c == nil or not has_setimage(c) then return false end
    local src = nil
    pcall(function() src = c.imageSource end)
    return src ~= nil
  end
  local function dive(c, depth)
    if c == nil or depth > 4 then return nil end
    for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
      local kid = nil
      pcall(function() kid = c:GetChild(cn) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then found_name = cn return r end
      end
    end
    if usable(c) then return c end
    if has_setimage(c) then return c end
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
function Adapter:set_image_deep(ctrl, image_id, image_type, image_color, label)
  if ctrl == nil then return false, "没有控件", "?" end
  local target, found = self:image_target(ctrl)
  if target == nil then
    return false, "找不到可设图的子控件", "?"
  end
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
      local gr = math.floor(v / 65536) % 256
      local gg = math.floor(v / 256) % 256
      local gb = v % 256
      tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
      rcol = tostring(v)
    elseif v ~= nil then
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
function Adapter:_cells_signal(v)
  local targets = {}
  local c = self:find("cell.1.1")
  if c ~= nil then
    if c.GetChild ~= nil then
      local ok, f = pcall(function() return c:GetChild("face") end)
      if ok and f ~= nil then targets[#targets + 1] = f end       
    end
    targets[#targets + 1] = c                                      
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
function Adapter:diagnose_grid(rows, cols)
  if print == nil then return end
  local g = self.cfg.cells or {}
  local print_ = print
  print_("[murdoku] ===== 逐格自检（实测，不猜）=====")
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
  local function describe(id)
    local ctrl = on_tree[id]
    local pos, size, vis, act = "?", "?", "?", "?"
    if ctrl ~= nil then
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
  do
    local want = {
      "face", "text", "note", "x", "obj",
      "wall.up", "wall.down", "wall.left", "wall.right",
      "door.up", "door.down", "door.left", "door.right",
    }
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
function Adapter:_cells_report(code)
  local map = { [1] = 80, [3] = 100, [4] = 40, [5] = 60 }
  self:_cells_signal(map[code] or (120 + code * 10))
end
function Adapter:_ref_index_of(ctrl)
  if ctrl == nil then return nil end
  local r = nil
  pcall(function() r = ctrl.referencedPrefabIndex end)
  if type(r) == "number" and r > 0 then return r end
  return nil
end
function Adapter:_note_parked(name, ctrl)
  if name == nil then return false end
  self.cells_parked = self.cells_parked or {}
  self.cells_parked_seen = self.cells_parked_seen or {}
  local key = ctrl or name       
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
  if ctrl.SetAnchoredPosition ~= nil then
    if pcall(function() ctrl:SetAnchoredPosition(200000, 200000) end) then ok = true end
  end
  if ctrl.SetSizeDelta ~= nil then
    pcall(function() ctrl:SetSizeDelta(0, 0) end)
  end
  if ctrl.SetVisible ~= nil then
    pcall(function() ctrl:SetVisible(false) end)
  end
  return ok
end
function Adapter:_cells_prefabs(g)
  local out, seen = {}, {}
  local function add(idx, from)
    if type(idx) ~= "number" or idx <= 0 then return end
    if seen[idx] then return end
    seen[idx] = true
    out[#out + 1] = { index = idx, from = from }
  end
  add(g.prefab, "cfg.cells.prefab")
  local probe_id = g.probe or "cell.1.1"
  local base_idx = nil
  do
    local c = self:find(probe_id)
    if c ~= nil then
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok and type(p) == "number" and p > 0 then base_idx = p end
    end
  end
  self.cells_probe_missing = (base_idx == nil)
  local names = g.prefab_from
    or { probe_id, "tpl.cell", "cell.tpl", "cell.prefab" }
  for i = 1, #names do
    local c = self:find(tostring(names[i]))
    if c ~= nil then
      local r = self:_ref_index_of(c)
      if r ~= nil then add(r, tostring(names[i]) .. ".referencedPrefabIndex") end
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok then add(p, tostring(names[i])) end
    end
  end
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
function Adapter:_cells_paint(ctrl, size, cell_id, img)
  if ctrl == nil then return false end
  local face = nil
  if cell_id ~= nil then
    pcall(function() face = self:sub(cell_id, "face") end)
  end
  if face == nil and ctrl.GetChild ~= nil then
    pcall(function() face = ctrl:GetChild("face") end)       
  end
  if face == nil then return false end
  if face.SetVisible then pcall(function() face:SetVisible(true) end) end
  if cell_id ~= nil then
    self:_repaint_cell_overlays(cell_id)
  end
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
  local use_img = img or (self.cfg.cells and self.cfg.cells.face_image) or 106053
  if face.SetImage then
    local ok = pcall(function() face:SetImage(nil, use_img) end)
    if not ok then pcall(function() face:SetImage(use_img) end) end       
  end
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
function Adapter:ensure_widgets(count)
  count = count or 8
  if game == nil or game.InstantiateClientUIControl == nil then
    return 0, "环境没有 game.InstantiateClientUIControl"
  end
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
  self.cells_ok, self.cells_made, self.cells_total = false, 0, rows * cols
  local max_rows = math.max(8, rows, self.cells_rows or 0)
  local max_cols = math.max(8, cols, self.cells_cols or 0)
  self.cells_rows, self.cells_cols = rows, cols
  self._edge_want = {}
  for rr=1,max_rows do for cc=1,max_cols do
    if rr>rows or cc>cols then
      local id=self:cell_id(rr,cc)
      -- Cell instances and the stage-level X strokes have separate visibility.
      local old = self.controls[id] or (self._cell_pos and self._cell_pos[id] and self:find(id))
      if old then
        if old.SetVisible then old:SetVisible(false) end
        if old.SetActive then old:SetActive(false) end
      end
      self:_mark_set_visible(rr .. "." .. cc, false)
      if self._cell_pos then self._cell_pos[id] = nil end
      local slot=self:_floor_slot(id)
      if slot then slot:SetVisible(false) end
      if self._floor_layout then self._floor_layout[id]=nil end
    end
  end end
  local parent = self:find(g.parent or "board")
  if parent == nil then
    self:warn_once("cells:parent",
      "生成格子失败：找不到父控件 " .. tostring(g.parent or "board"))
    self:_cells_report(5)
    return 0
  end
  do
    local names = {}
    for r = 1, rows do
      for c = 1, cols do names[#names + 1] = self:cell_id(r, c) end
    end
    names[#names + 1] = "tpl.cell"; names[#names + 1] = "cell.tpl"; names[#names + 1] = "cell.prefab"
    self:prefetch(names)
  end
  local moved = 0
  if type(g.prefab) == "number" and g.prefab > 0 then
    for r = 1, rows do
      for c = 1, cols do
        local id = self:cell_id(r, c)
        local ctrl = self:find(id)
        if ctrl ~= nil and not (self.instantiated and self.instantiated[id]) then
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
              self:drop_lookup(id)              
              self.controls[newname] = ctrl
              self:_park_control(ctrl)          
              self:_note_parked(newname, ctrl)  
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
  do
    local hide_names = {}
    if type(g.prefab_from) == "table" then
      for i = 1, #g.prefab_from do hide_names[#hide_names + 1] = tostring(g.prefab_from[i]) end
    end
    for _, n in ipairs({ "tpl.cell", "cell.tpl", "cell.prefab" }) do
      hide_names[#hide_names + 1] = n
    end
    local hid = 0
    for i = 1, #hide_names do
      local n = hide_names[i]
      if n ~= (g.probe or "cell.1.1") then           
        local c = self:find(n)
        if c ~= nil then
          if self:_park_control(c) then
            self:_note_parked(n, c)       
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
      self:_cells_report(4)           
      return 0
    end
    local cands = self:_cells_prefabs(g)
    if #cands == 0 then
      self:warn_once("cells:prefab",
        "缺 " .. missing .. " 个格子，但读不到任何控件模板索引。\n"
        .. "       两个办法任选：\n"
        .. "       ① 在编辑器里右键 cell.1.1 →【另存为模板】，"
        .. "再从那个模板**新建一个控件**放到 board 下、改名 `tpl.cell`（位置随意，脚本会藏起来）；\n"
        .. "       ② 照 docs/控件坐标表-1600x900.md 把格子手动摆齐（脚本就不再生成）。")
      self:_cells_report(1)           
      return 0
    end
    for i = 1, #cands do
      local c = cands[i]
      local ok, obj = pcall(game.InstantiateClientUIControl, c.index, parent)
      tried[#tried + 1] = tostring(c.index) .. "(" .. c.from .. ")"
      if ok and obj ~= nil then
        prefab, prefab_from = c.index, c.from
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
  local ref = self:find(g.probe or "cell.1.1")    
  if ref == nil and made > 0 then
    self:warn_once("cells:noref",
      "没有参照格子（" .. tostring(g.probe or "cell.1.1") .. "），"
      .. "所以**不做图片盖章** —— 生成的格子外观**完全取自模板快照**。\n"
      .. "       这是纯模板模式的正常代价。如果副本看不见，去模板里补底图后**重存一次模板**。")
  end
  local n = math.max(rows, cols)
  local cell_size = self:cell_geometry(n)
  local layer_cells, layer_subs = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = self:find(id)
      if ctrl == nil then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = id end)
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= id then
            self:warn_once("cells:name:" .. id,
              "改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。\n"
              .. "       这个副本会**找不到**（也会挡住后面的同名格子），记下这一条备用。")
          end
          self.controls[id] = obj
          self.instantiated = self.instantiated or {}
          self.instantiated[id] = true
          ctrl = obj
          made = made + 1
          self:_cells_stamp(ctrl, ref)      
          self:_cells_paint(ctrl, cell_size, id)
        elseif first_err == nil then
          first_err = tostring(obj)
        end
      elseif g.stamp_existing == true then
        self:_cells_stamp(ctrl, ref)        
      end
      if ctrl ~= nil and g.force_position ~= false then
        self:open_click_passthrough(id)
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
          self:_sync_floor(id,ctrl)
        end
        -- ★ 685：记下本格中心，标记层复用同一组数值（与 n / 家具尺寸无关）
        self._cell_pos = self._cell_pos or {}
        self._cell_pos[id] = { x, y, cell_size }
        self._board_n = n
        local kids = { "face", "x" }
        for i = 1, #kids do
          local k = self:sub(id, kids[i])
          if k ~= nil then
            if k.SetSizeDelta then pcall(function() k:SetSizeDelta(cell_size, cell_size) end) end
            if k.SetAnchoredPosition then pcall(function() k:SetAnchoredPosition(0, 0) end) end
            if k.SetPivot then pcall(function() k:SetPivot(0.5, 0.5) end) end
          end
        end
      end
    end
  end
  if made == 0 and first_err ~= nil then     
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
    self:_cells_signal(100)         
  elseif g.debug_signal ~= false then
    if not self:_cells_signal(40 + made * 8) then
      self:warn_once("cells:signal", "诊断信号写入失败：一个可改尺寸的控件都没找到")
    end
  end
  if print then
    local have = 0
    for r = 1, rows do
      for c = 1, cols do
        if self:find(self:cell_id(r, c)) ~= nil then have = have + 1 end
      end
    end
    print("[murdoku] 棋盘格子：" .. have .. " / " .. (rows * cols) .. " 存在"
      .. "（本次新建 " .. made .. " 个，模板索引 " .. tostring(prefab) .. "）")
    self.cells_ok = (have >= rows * cols)
    self.cells_index = prefab
    self.cells_made = made
    self.cells_total = rows * cols
  end
  do
    local cleared = 0
    for k in pairs(self.subs) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then
        self.subs[k] = nil
        cleared = cleared + 1
      end
    end
    if self._sub_miss ~= nil then
      for k in pairs(self._sub_miss) do
        if type(k) == "string" and k:sub(1, 5) == "cell." then
          self._sub_miss[k] = nil
        end
      end
    end
  end
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
  pcall(function()
    for r = 1, rows do
      for c = 1, cols do
        local cid = self:cell_id(r, c)
        local ctrl2 = self:find(cid)
        if ctrl2 ~= nil then self:_ensure_cell_face(cid, ctrl2) end
      end
    end
  end)
  pcall(function()
    if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
      self._furn_prefabs = self:_furn_prefab_map()
      self._furn_tpl_ok = (self._furn_prefabs ~= nil and next(self._furn_prefabs) ~= nil)
      self:_furn_try_all()
    end
  end)
  -- ★ 685：建格完成后立刻把标记层复位到 stage 末尾
  self:_mark_layer_raise()
  return made
end
local DECOR = {
  ["adapt715r.LM.22"] = true,
  ["adapt715r.background"] = true,
  ["adapt715r.background.fill"] = true,
  ["art647.select.bg.base"] = true,
  ["home.tutorial627.bg"] = true,
  ["home.tutorial627.ring"] = true,
  ["home.tutorial627.label"] = true,
  ["home.tutorial627.hit"] = true,
  ["clues.help617"] = true,
  ["clues.help627.hit"] = true,
  ["board.floors"] = true, ["board.rugs"] = true,
  label = true, bg = true, pic = true, icon = true,
  face = true, note = true, x = true, obj = true, text = true, portrait = true,
  backrop1 = true, backrop2 = true, badge = true, letter = true, what = true, who = true,
  frame = true, card = true, art = true, image = true, img = true,
}
local MANAGED = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal",
}
local CURSOR_CONTAINERS = {
  "root", "topbar", "clues",
  "right", "modal", "home",
}
local SELF_MANAGED_TOP = {
  ["art641.home"] = true, ["art641.select"] = true, ["art641.game"] = true,
  help617 = true,
  ["block640.modal"] = true, ["block640.confirm"] = true,
  ["block640.home"] = true, ["block640.l1"] = true, ["block640.l2"] = true,
}
function Adapter:hide_unlisted(keep)
  self._ruler721 = nil
  -- ★ 686：keep = layout_plan 的 seen 集合；没有任何 cell.* ⇒ 当前不在关卡内，
  --   逐层收起 192 个标记控件，兜住首帧 / _shown 重建等没有 cell visible 下发的路径。
  do
    local in_level = false
    for k in pairs(keep or {}) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then in_level = true; break end
    end
    if not in_level then self:_mark_hide_all() else self._mark_screen_on = true end
  end
  local hidden = 0
  local skipped_self = 0
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
            if SELF_MANAGED_TOP[name] then
              skipped_self = skipped_self + 1
            elseif child.SetVisible ~= nil then
              local ok2 = pcall(function() child:SetVisible(false) end)
              if ok2 then hidden = hidden + 1 end
            end
          end
        end
      end
    end
  end
  if skipped_self > 0 and not self._said_self_managed and print then
    self._said_self_managed = true
    print("[murdoku] hide_unlisted：跳过 " .. skipped_self
      .. " 个**脚本自管的顶层容器**（teach，教程浮层 —— 显隐由 tutorial_ui 决定）")
  end
  return hidden
end
function Adapter:scale_of_style(value)
  if value == "portrait" then return 0.86             
  elseif value == "portrait.selected" then return 1.08
  elseif value == "portrait.placed" then return 0.72   
  elseif value == "clue.focus" then return 1.03
  elseif value == "tab.active" then return 1.04 end
  return nil
end
function Adapter:color_of_style(value)
  local WHITE = 4294967295             
  local RED   = 4290453793             
  if value == "card.name" then return 0xFF4A2E1C end   -- 696：白纸边缘的关卡名用深棕
  if value == "clue.who" then return RED end
  if value == "clue.what" or value == "clue" or value == "clue.ok" or value == "clue.focus" then
    return WHITE
  end
  return nil                           
end
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
function Adapter:apply_btn_art()
  if self.cfg.btn_art ~= true or print == nil then return 0 end
  local names = self.cfg.btn_list or {}
  local done, miss = 0, 0
  return self:_tray_btn_art(0, names, done, miss)
end
function Adapter:diagnose_overlap()
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
function Adapter:enable_cursor()
  local n = 0
  if self._cursor ~= nil and self._cursor.done then
    return self._cursor.n or 0           
  end
  local st = self._cursor
  if st == nil then
    st = { idle = 0, done = false, n = 0 }
    self._cursor = st
  end
  -- 748（B9）：若前次仅差少数晚挂容器，在退避间隔内直接返回，到期只做 O(1) probe_static747（0 次 GetChildren）。
  if st.missing748 ~= nil and #st.missing748 > 0 then
    st.miss_tick748 = (st.miss_tick748 or 0) + 1
    if st.miss_tick748 < (st.miss_wait748 or 1) then
      return st.n or 0
    end
    st.miss_tick748 = 0
    local any_new = false
    for i = 1, #st.missing748 do
      local mname = st.missing748[i]
      local live = self:probe_static747(mname)
      if live ~= nil then
        self.controls[mname] = live
        self:_note_lookup_hit(mname)
        if self._misses ~= nil then self._misses[mname] = nil end
        any_new = true
      end
    end
    if not any_new then
      st.miss_polls748 = (st.miss_polls748 or 0) + 1
      st.miss_wait748 = (st.miss_polls748 <= 3) and 1 or ((st.miss_polls748 <= 8) and 2 or 3)
      return st.n or 0
    end
  end
  self:prefetch(CURSOR_CONTAINERS)
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(p744_cur_set, ctrl)
      if ok then n = n + 1 end
    end
  end
  local parts = {}
  local found, present_all_true = 0, true
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      found = found + 1
      local ok_sc, v_sc = pcall(p744_field, ctrl, "showCursor")
      local sc = ok_sc and tostring(v_sc) or "?"
      if sc ~= "true" then present_all_true = false end
      local ok_k, v_k = pcall(p744_field, ctrl, "kind")
      local kd = ok_k and tostring(v_k) or "?"
      if kd == "nil" then ok_k, v_k = pcall(p744_field, ctrl, "Kind"); if ok_k then kd = tostring(v_k) end end
      if kd == "nil" then ok_k, v_k = pcall(p744_field, ctrl, "type"); if ok_k then kd = tostring(v_k) end end
      if kd == "nil" then ok_k, v_k = pcall(p744_field, ctrl, "controlType"); if ok_k then kd = tostring(v_k) end end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
    else
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
  st.n = n
  -- 748（B9）：CURSOR_CONTAINERS 全部 6 个容器在真实 .gil 均存在且走 O(1) 静态路由；
  -- 仅在全部齐备且连续 3 趟 showCursor==true 时才收敛，缺项绝不永久放弃（改按 20→40→60 帧仅 O(1) 探活缺失项）。
  if found >= #CURSOR_CONTAINERS and present_all_true then
    st.missing748 = nil
    st.miss_wait748 = 0
    st.idle = st.idle + 1
    if st.idle >= 3 then
      st.done = true
      if print and not self._cursor_done_logged then
        self._cursor_done_logged = true
        print(PREFIX .. "常驻光标：已收敛（" .. tostring(found) .. " 个容器 showCursor 全为 true）"
          .. " ⇒ 不再每 20 帧重扫；换屏/换关会重新武装")
      end
    end
  else
    st.idle = 0
    local miss_list = nil
    for i = 1, #CURSOR_CONTAINERS do
      if self.controls[CURSOR_CONTAINERS[i]] == nil then
        miss_list = miss_list or {}
        miss_list[#miss_list + 1] = CURSOR_CONTAINERS[i]
      end
    end
    st.missing748 = miss_list
    st.miss_polls748 = (st.miss_polls748 or 0) + 1
    st.miss_wait748 = (st.miss_polls748 <= 3) and 1 or ((st.miss_polls748 <= 8) and 2 or 3)
  end
  return n
end
function Adapter:rearm_cursor(why)
  local st = self._cursor
  if st == nil then return end
  if not st.done and st.idle == 0 and st.n == 0 and st.missing748 == nil then return end
  st.idle, st.done, st.missing748, st.miss_polls748, st.miss_wait748 = 0, false, nil, 0, 0
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "常驻光标：重新开始扫描（" .. tostring(why) .. "）")
  end
end
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
function Adapter:count_names(max_depth, max_items)
  return self:dump_names(max_depth or 6, max_items or 400, true)
end
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
  self.event_claim[id] = nil    
  self.event_latest[id] = nil
  self.handlers[id] = nil
end
function Adapter:destroy_control(id)
  local ctrl = self.controls[id]
  if self.instantiated and self.instantiated[id] then
    if ctrl and game and game.DestroyClientUIControl then
      pcall(function() game.DestroyClientUIControl(ctrl) end)
    end
    self.instantiated[id] = nil
    self.bound[id] = nil
    self.controls[id] = nil
    self:forget_events_of(id)
    self:invalidate_lookups("destroy:" .. tostring(id))
    return
  end
  if ctrl ~= nil then
    pcall(p745_set_vis_false, ctrl)
  end
  self:drop_lookup(id)
  self:forget_events_of(id)
end
function Adapter:read_palette()
  if self._palette ~= nil then return self._palette end
  local map, names = {}, {}
  local a = self.cfg.assets or {}
  local roots = { a.palette or "assets", a.things or "things" }
  for ri = 1, #roots do
    local root = self:find(roots[ri])
    if root ~= nil then
      local kids = nil
      pcall(function() kids = root:GetChildren() end)
      if type(kids) == "table" then
        for i = 1, #kids do
          local k = kids[i]
          local nm, src, id, col = nil, nil, nil, nil
          pcall(function() nm = tostring(k.name) end)
          pcall(function() src = k.imageSource end)
          pcall(function() id = k.imageId end)
          pcall(function() col = k.imageColor end)
          if nm ~= nil and nm ~= "" and type(id) == "number" and id > 0 then
            map[nm] = { source = src, id = id, color = col, from = roots[ri] }
            names[#names + 1] = nm
          end
        end
      end
    end
  end
  local oa = self.cfg.obj_art
  if type(oa) == "table" then
    for k, v in pairs(oa) do
      local kind = tostring(k)
      local pref = kind:match("^(obj%d*)%.") 
      if pref ~= nil then kind = kind:sub(#pref + 2) end
      local layers = nil
      if type(v) == "table" and type(v.id) == "number" then
        layers = { v }                                    
      elseif type(v) == "table" and #v > 0 then
        layers = v                                        
      end
      if layers ~= nil then
        for i = 1, #layers do
          local L = layers[i]
          local key = (i == 1 and ("obj.") or ("obj" .. i .. ".")) .. kind
          if type(L) == "table" and type(L.id) == "number" then
            local e = map[key]
            if e == nil then
              map[key] = {
                source = L.source or "StaticReference",
                id = L.id,
                color = L.color,
                w = L.w, h = L.h, dx = L.dx, dy = L.dy,
                layer = i,
                from = "cfg.obj_art",
              }
              names[#names + 1] = key
            else
              if e.w == nil then e.w = L.w end
              if e.h == nil then e.h = L.h end
              if e.dx == nil then e.dx = L.dx end
              if e.dy == nil then e.dy = L.dy end
              if e.layer == nil then e.layer = i end
            end
          end
        end
      end
    end
  end
  if next(map) ~= nil then
    self._palette = map
    self._palette_names = names
  end
  return map
end
function Adapter:resolve_asset(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n ~= nil then return { source = nil, id = n } end    
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
-- 748（B1）：恢复 RAY_IDLE_STOP = 3 且移除 scans==1 / was_retry_pass 早停，确保首屏后晚挂入任何业务容器的新按钮均能被自动开启射线；
-- 首趟全树扫描完毕后，后续确认趟仅跳过已扫清的纯静态只读画片叶容器（不含 root/home/select/stage/clues/modal/econ/td），
-- 兼顾 742v12 等价的 3 趟安全观察窗与低冷启/零稳态负载。
local RAY_IDLE_STOP = 3
local RAY_MAX_SCANS = 25
local RAY_STATIC_DECOR748 = {
  ["adapt715r.background"] = true,
  ["adapt715r.TR.23"] = true, ["adapt715r.TR.24"] = true,
  ["adapt715r.TR.25"] = true, ["adapt715r.BR.26"] = true,
  ["adapt715r.BR.27"] = true, ["adapt715r.BR.28"] = true,
  ["adapt715r.WAX.12"] = true,
  ["art642.select.backdrop"] = true,
  ["select.thumb.pool"] = true,
  ["art685.mark.overlay"] = true,
  ["police-v19"] = true,
  ["econ.shop736.anim.under"] = true,
  ["econ.shop736.anim.bend"] = true,
  ["econ.bag741.anim.under"] = true,
  ["econ.bag741.anim.bend"] = true,
}
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done and st.retry_nodes == nil then return end
  -- 748（B1 零额外负载优化）：仅在根句柄变更或冷启时才重扫纯静态美术画片大容器；同根下新增业务控件只需复扫动态业务容器。
  st.scans, st.idle, st.done, st.retry_nodes = 0, 0, false, nil
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local ok_b, before = pcall(p744_ray_get, c)
  if not ok_b or before == nil then return false end
  if before == true then return true end
  local ok = pcall(p744_ray_set, c, true)
  return ok == true
end
function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false, full_done748 = false }
    self._ray = st
  end
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, errs, samples = 0, 0, 0, {}
  local failed_nodes = nil
  local visited = {}
  local ray_want = self._ray_want
  if st.last_root748 ~= root then
    st.full_done748 = false
    st.leaf_ok748 = setmetatable({}, { __mode = "k" })
    st.last_root748 = root
  end
  local leaf_ok = st.leaf_ok748
  if leaf_ok == nil then
    leaf_ok = setmetatable({}, { __mode = "k" })
    st.leaf_ok748 = leaf_ok
  end
  local skip_decor = (st.full_done748 == true)
  local function walk(c, depth)
    if c == nil or depth > 20 or visited[c] then return end
    visited[c] = true
    local want = not (ray_want and ray_want[c] == false)
    if skip_decor and depth > 0 then
      if leaf_ok[c] == want then
        local ok_l, before_l, did_l = pcall(p748_ray_leaf_step, c, want)
        if ok_l and before_l ~= nil then
          seen = seen + 1
          if did_l then set = set + 1 end
          return
        end
        leaf_ok[c] = nil
      end
      local ok_dn, dnm = pcall(p744_name, c)
      if ok_dn and type(dnm) == "string" and (RAY_STATIC_DECOR748[dnm]
          or dnm:sub(1, 16) == "grp653.static.1."
          or (dnm:sub(1, 3) == "td." and dnm:find("%.page%.%d+$") ~= nil)) then
        local ok_b, before = pcall(p744_ray_get, c)
        if ok_b and before ~= nil then
          seen = seen + 1
          if before ~= want then
            if pcall(p744_ray_set, c, want) == true then set = set + 1 end
          end
        end
        return
      end
    end
    local ok, before, did, kids = pcall(p745_ray_step, c, want)
    if not ok then
      local node_err = false
      local ok_b; ok_b, before = pcall(p744_ray_get, c)
      if not ok_b then before = nil; node_err = true end
      did = false
      if before ~= nil and before ~= want then
        did = pcall(p744_ray_set, c, want) == true
        if not did then node_err = true end
      end
      local ok_k; ok_k, kids = pcall(p744_kids, c)
      if not ok_k then kids = nil; node_err = true end
      if node_err then
        errs = errs + 1
        failed_nodes = failed_nodes or {}
        failed_nodes[#failed_nodes + 1] = c
      end
    elseif depth > 0 and type(kids) == "table" and #kids == 0 and before ~= nil then
      -- 首趟确认是终端空叶节点（无子控件、无报错），后续确认趟省去空 GetChildren() 分配，仍核查自身 raycastTarget。
      leaf_ok[c] = want
    end
    if before ~= nil then
      seen = seen + 1
      if did then
        set = set + 1
        if #samples < 6 then
          local ok_n, nm = pcall(p744_name, c)
          samples[#samples + 1] = (ok_n and tostring(nm) or "?") .. ":" .. tostring(before) .. "->true"
        end
      end
    end
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  local was_retry_pass = (type(st.retry_nodes) == "table" and #st.retry_nodes > 0)
  if was_retry_pass then
    for i = 1, #st.retry_nodes do walk(st.retry_nodes[i], 0) end
  else
    walk(root, 0)
  end
  st.scans = st.scans + 1
  if not was_retry_pass then st.seen = seen end
  st.set = set
  st.errs = errs
  if errs > 0 then
    st.retry_nodes = failed_nodes
    st.idle = 0
  else
    st.retry_nodes = nil
    if not was_retry_pass and seen > 0 then st.full_done748 = true end
    local eff_seen = was_retry_pass and math.max(seen, st.seen or 0) or seen
    if eff_seen > 0 and set == 0 and not was_retry_pass then st.idle = st.idle + 1 else st.idle = 0 end
    if eff_seen > 0 and st.idle >= RAY_IDLE_STOP then
      st.done = true
      if print and not st.announced then
        st.announced = true
        self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
          .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
      end
    end
  end
  if not st.done and st.scans >= RAY_MAX_SCANS then
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
    put("home", 0)
    put("select", 1)
  end
end
-- ═══════════════════════════════════════════════════════════════════════
-- ★ 685「多格家具通用构造法」：三层不变式
--   stage 内 = 格子层（cell.*）；跨格家具实例挂在各格 content/furn，尺寸 = span × 格，
--   允许越出格线；furn_anchor 把锚点格 SetAsLastSibling 抬到 stage 内最上。
--   症状：被抬高的整格连同越界家具压到邻格之上，把邻格 content/x 一起盖掉（地毯/桌子都出现过）。
--   不变式：art685.mark.overlay 恒为 stage 的最后一个子控件，X 标记全部画在它里面，
--           抬格只能发生在 stage 内部 ⇒ 结构上不存在「家具盖住 X」的绘制顺序。
--   通用性：与 kind / span_r×span_c / 缩放 / 层数 / 将来新增多少种家具完全无关；
--           新增家具照常下发 furn_tpl / furn_span / furn_offset 即可，不必再改层序表。
-- ═══════════════════════════════════════════════════════════════════════
function Adapter:_mark_layer_raise(force)
  local m = self._mark_layer
  if m == nil then
    m = self:find("art685.mark.overlay")
    if m == nil then return end
    self._mark_layer = m
    self._mark_layer_dirty745 = true
  end
  if force == false and not self._mark_layer_dirty745 then return end
  self._mark_layer_dirty745 = false
  if m.SetAsLastSibling ~= nil then
    pcall(p745_last_sib, m)
  end
end
function Adapter:_mark_layer_guard()
  if self._mark_guard_done then return end
  if self:find("art685.mark.overlay") == nil then
    if self.warn_once then self:warn_once("mark:missing",
      "685 通用标记层缺失：多格家具会再次盖住 X。请把 art685.mark.overlay 挂在 stage 末尾。") end
    return
  end
  self._mark_guard_done = true
end
-- cell.<r>.<c> → art685.mark.<r>.<c>；位置/尺寸直接复用建格时记下的同一组数值
-- ═══════════════════════════════════════════════════════════════════════
-- ★ 686「X 标记离场收起」：父容器隐藏不级联，必须逐层关灯
--   685 误判：以为 stage 在 home/select 被整体隐藏时，挂在它下面的标记层会跟着消失。
--   真机反证（v308 已记录）：父容器 SetVisible 不保证级联到子控件 ⇒ 关卡内点亮的
--   X 标记会残留在新界面上。且标记层控件不在 layout_plan 的 nodes 表里，Controller 的
--   _shown 差异下发 / hide_unlisted 都不会给它们下发 visible=false ⇒ 永远没人关灯。
--   ⇒ 按项目既有范式（visible 分支里显式切 board.floors / board.rugs）逐层收起。
-- ═══════════════════════════════════════════════════════════════════════
function Adapter:_mark_all_ctrls()
  if self._mark_ctl_cache ~= nil then return self._mark_ctl_cache end
  local t = {}
  for r = 1, 8 do
    for c = 1, 8 do
      local base = "art685.mark." .. r .. "." .. c
      local names = { base, base .. ".stroke.0", base .. ".stroke.1" }
      for i = 1, #names do
        local q = self:find(names[i])
        if q ~= nil then t[#t + 1] = q end
      end
    end
  end
  if #t >= 192 then self._mark_ctl_cache = t end   -- 748(U11)：由构建期从 .gil 真实树自动推导
  return t
end
function Adapter:_mark_hide_all()
  if self._mark_screen_on == false and self._mark_all_hidden_gen745 == self._lookup_gen then return end
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    pcall(p745_set_vis_false, t[i])
  end
  self._mark_screen_on = false
  if #t >= 192 then self._mark_all_hidden_gen745 = self._lookup_gen end
end
function Adapter:_mark_ctrl(id)
  local rc = tostring(id):match("^cell%.(.+)$")
  if rc == nil then return nil, nil end
  local m = self:find("art685.mark." .. rc)
  if m == nil then return nil, nil end
  local p = self._cell_pos and self._cell_pos[id]
  local x, y, sz = nil, nil, nil
  if p ~= nil then
    x, y, sz = p[1], p[2], p[3]
  else
    local r, c = rc:match("^(%d+)%.(%d+)$")
    if r ~= nil then
      local n = self._board_n or math.max(tonumber(r) or 1, tonumber(c) or 1)
      x, y = self:cell_offset(tonumber(r), tonumber(c), n)
      sz = select(1, self:cell_geometry(n))
    end
  end
  if x ~= nil and m.SetAnchoredPosition ~= nil then
    pcall(function() m:SetAnchoredPosition(x, y) end)
  end
  if sz ~= nil and m.SetSizeDelta ~= nil then
    pcall(function() m:SetSizeDelta(sz, sz) end)
  end
  return m, rc
end
-- 真机父容器 SetVisible 不保证级联到子控件（v308 教训）⇒ 容器 + 两枚笔画逐层开关
function Adapter:_mark_set_visible(rc, on)
  -- ★ 686：关卡外一律不点亮（防止切屏瞬间 x_mark 抢先下发把 X 又打开）
  if on == true and self._mark_screen_on == false then on = false end
  if on then self._mark_all_hidden_gen745 = nil end
  local base = "art685.mark." .. rc
  local c0 = self:find(base); if c0 ~= nil then p745_set_vis_guard(c0, on) end
  local c1 = self:find(base .. ".stroke.0"); if c1 ~= nil then p745_set_vis_guard(c1, on) end
  local c2 = self:find(base .. ".stroke.1"); if c2 ~= nil then p745_set_vis_guard(c2, on) end
end
-- 关卡切换：收起超出当前棋盘 n 的标记，避免上一关的 X 残留
function Adapter:_mark_scope()
  local n = self._board_n or 0
  if n <= 0 or n == self._mark_scope_n then return end
  self._mark_scope_n = n
  for r = 1, 8 do
    for c = 1, 8 do
      if r > n or c > n then
        self:_mark_set_visible(string.format("%d.%d", r, c), false)
      end
    end
  end
end
function Adapter:enforce_layers(cell_id)
  return 0
end
function Adapter:seal_container(id)
  local c = self:find(id)
  if c == nil then return false end
  local n = 0
  if c.disableKeyEventPassthrough ~= nil then
    if pcall(function() c.disableKeyEventPassthrough = true end) then n = n + 1 end
  end
  if c.disableCursorEventPassthrough ~= nil then
    pcall(function() c.disableCursorEventPassthrough = false end)
  end
  return n > 0
end
function Adapter:seal_cursor_shield()
  local c = nil
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
  if type(flags) ~= "table" then return true end
  local r, c = tostring(id):match("^cell%.(%d+)%.(%d+)$")
  r, c = tonumber(r), tonumber(c)
  local rows = self.cells_rows or (self.cfg.cells and self.cfg.cells.rows)
  local cols = self.cells_cols or (self.cfg.cells and self.cfg.cells.cols)
  local skip = { down = true, right = true }
  self.edges_needed = self.edges_needed or {}
  local sides = { "up", "down", "left", "right" }
  local missing_sub = {}
  local geo_n = self.cells_rows or self.cells_cols
    or (self.cfg.cells and (self.cfg.cells.rows or self.cfg.cells.cols)) or 5
  local cw, pitch = nil, nil
  pcall(function() cw, pitch = self:cell_geometry(geo_n) end)
  if type(cw) ~= "number" or cw <= 0 then cw, pitch = nil, nil end
  local ch = cw
  if cw ~= nil and (type(pitch) ~= "number" or pitch <= 0 or pitch < cw) then pitch = cw end
  if cw == nil and print and not self._edge_no_geo_noted then
    self._edge_no_geo_noted = true
    print("[murdoku] 边缘适配：**算不出格子边长**（cell_geometry(" .. tostring(geo_n)
      .. ") 返回 0/nil）⇒ 墙/门的**缩放与贴边整段跳过**（按编辑器里摆的原样显示）")
  end
      do
        local content = nil
        pcall(function() content = self:sub(id, "content") end)
        if content ~= nil then
          if content.SetAnchorMin then pcall(function() content:SetAnchorMin(0.5, 0.5) end) end
          if content.SetAnchorMax then pcall(function() content:SetAnchorMax(0.5, 0.5) end) end
          if content.SetPivot then pcall(function() content:SetPivot(0.5, 0.5) end) end
          if content.SetSizeDelta and cw ~= nil then
            pcall(function() content:SetSizeDelta(cw, ch) end)
          end
          if content.SetAnchoredPosition then pcall(function() content:SetAnchoredPosition(0, 0) end) end
        end
      end
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
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end
  if self.cfg.cells == nil or self.cfg.cells.edge_fit ~= false then
    local thick = (self.cfg.cells and self.cfg.cells.edge_thickness) or 8
    local door_ratio = (self.cfg.cells and self.cfg.cells.door_length_ratio) or 0.45
  local overlap = (self.cfg.cells and self.cfg.cells.edge_overlap) or 4
  local extra_len = (self.cfg.cells and self.cfg.cells.edge_extra_len) or 0
    if cw ~= nil then
      for i = 1, #sides do
        local s = sides[i]
        local sub = self:sub(id, prefix .. "." .. s)
        if sub ~= nil and flags[s] then
          local w, h = size_of(sub)
          local horiz = (s == "up" or s == "down")
          local outer = (s == "down" or s == "right")
          if s == "up" then outer = (r == nil or r <= 1) end
          if s == "left" then outer = (c == nil or c <= 1) end
          local tlen
          if prefix == "door" then
            tlen = cw * door_ratio + extra_len
          elseif outer then
            tlen = cw + thick + 4           
          else
            tlen = cw + overlap + extra_len
          end
          local tthick = thick
          local base_l = horiz and w or h       
          local base_t = horiz and h or w
          if type(base_l) == "number" and base_l > 0 and type(base_t) == "number" and base_t > 0 then
            local kl = tlen / base_l
            local kt = tthick / base_t
            if kl > 1.001 or kl < 0.999 then
              if horiz then pcall(function() sub.localScaleX = kl end)
              else pcall(function() sub.localScaleY = kl end) end
            end
            if kt > 1.001 or kt < 0.999 then
              if horiz then pcall(function() sub.localScaleY = kt end)
              else pcall(function() sub.localScaleX = kt end) end
            end
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
          local d = outer and (cw / 2) or (pitch / 2)
          local x, y = 0, 0
          if s == "up" then y = d
          elseif s == "down" then y = -d
          elseif s == "left" then x = -d
          else x = d end
          if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
          if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(x, y) end) end
        end
      end
    end
  end
  return #missing_sub == 0
end
local function is_cell_id(id)
  return type(id) == "string" and id:match("^cell%.%d+%.%d+$") ~= nil
end
Adapter._is_cell_id = is_cell_id
function Adapter:_fit_child_to_cell(ctrl, sub, cell_id)
  if ctrl == nil or sub == nil then return end
  if cell_id ~= nil and not is_cell_id(cell_id) then return end
  local w, h = size_of(ctrl)
  if (type(w) ~= "number" or w <= 1) and cell_id ~= nil and self.rects ~= nil then
    local r = self.rects[cell_id]
    if type(r) == "table" then w, h = r.w, r.h end
  end
  if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then return end
  self:_fit_child_sized(sub, w, h)
end
function Adapter:_fit_child_sized(sub, w, h)
  if sub == nil then return end
  if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then return end
  local marks = self._fit_marks
  if marks == nil then
    marks = setmetatable({}, { __mode = "k" })    
    self._fit_marks = marks
  end
  local m = marks[sub]
  if m ~= nil and math.abs(m.w - w) < 0.5 and math.abs(m.h - h) < 0.5 then return end
  marks[sub] = { w = w, h = h }
  if print and (self._fit_log or 0) < 10 then
    self._fit_log = (self._fit_log or 0) + 1
    print("[murdoku] 图层贴格：" .. tostring(sub.name) .. " ← 格子 " ..
      tostring(w) .. "×" .. tostring(h))
  end
  if sub.SetAnchorMin then pcall(function() sub:SetAnchorMin(0.5, 0.5) end) end
  if sub.SetAnchorMax then pcall(function() sub:SetAnchorMax(0.5, 0.5) end) end
  if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
  if sub.SetSizeDelta then pcall(function() sub:SetSizeDelta(w, h) end) end
  if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(0, 0) end) end
end
local OBJ_LAYER_SUBS = {
  "obj", "obj2", "obj3", "obj4", "obj5", "obj6",
  "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",
}    
function Adapter:obj_layers_of(want)
  if want == false or want == nil or type(want) ~= "table" then return {} end
  local out = {}
  if type(want.layers) == "table" then
    for i = 1, math.min(#want.layers, #OBJ_LAYER_SUBS) do
      local L = want.layers[i]
      if type(L) == "table" and L.id ~= nil then
        out[#out + 1] = {
          sub = OBJ_LAYER_SUBS[i],
          key = L.key or (want.key .. "#" .. i),
          src = L.src, id = L.id, color = L.color,
          w = L.w, h = L.h, dx = L.dx, dy = L.dy,
        }
      end
    end
  elseif want.id ~= nil then
    out[1] = { sub = "obj", key = want.key, src = want.src, id = want.id, color = want.color }
  end
  return out
end
function Adapter:_cell_size_of(ctrl, cell_id)
  if cell_id ~= nil and self.rects ~= nil then
    local r = self.rects[cell_id]
    if type(r) == "table" and tonumber(r.w) and tonumber(r.h) and r.w > 1 and r.h > 1 then
      local sw, sh = size_of(ctrl)
      if type(sw) == "number" and sw > 1 and math.abs(sw - r.w) > 0.5 then
        self._cellsize_logged = self._cellsize_logged or {}
        local k = tostring(cell_id)
        if not self._cellsize_logged[k] then
          self._cellsize_logged[k] = true
          if print then
            print(string.format("[murdoku] 格子尺寸：cell=%s rects=%.1f,%.1f sizeDelta=%.1f,%.1f（用 rects ✓）",
              k, r.w, r.h, sw, sh))
          end
        end
      end
      return r.w, r.h
    end
  end
  local w, h = size_of(ctrl)
  if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then return nil, nil end
  return w, h
end
function Adapter:_fit_obj_layer(sub, cw, ch, L)
  if sub == nil or cw == nil or ch == nil then return end
  local fw = tonumber(L and L.w) or 1
  local fh = tonumber(L and L.h) or 1
  local dx = tonumber(L and L.dx) or 0
  local dy = tonumber(L and L.dy) or 0
  if sub.SetAnchorMin then pcall(function() sub:SetAnchorMin(0.5, 0.5) end) end
  if sub.SetAnchorMax then pcall(function() sub:SetAnchorMax(0.5, 0.5) end) end
  if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
  if sub.SetSizeDelta then pcall(function() sub:SetSizeDelta(cw * fw, ch * fh) end) end
  if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(dx * cw, -(dy * ch)) end) end
end
function Adapter:_paint_obj(cell_id, ctrl, want, force)
  if cell_id == nil then return false end
  local layers = self:obj_layers_of(want)
  local marks = self._obj_marks
  if marks == nil then
    marks = setmetatable({}, { __mode = "k" })    
    self._obj_marks = marks
  end
  local cw, ch = nil, nil
  local all_ready = true
  for i = 1, #OBJ_LAYER_SUBS do
    local sub = self:sub(cell_id, OBJ_LAYER_SUBS[i])
    local L = layers[i]
    if sub == nil then
      if L ~= nil then all_ready = false end
    elseif L == nil then
      if sub.SetVisible then pcall(function() sub:SetVisible(false) end) end
      marks[sub] = nil
    else
      local m = marks[sub]
      local need = (force == true) or m == nil
        or m.key ~= L.key or m.id ~= L.id or m.color ~= L.color
        or m.w ~= L.w or m.h ~= L.h or m.dx ~= L.dx or m.dy ~= L.dy
      if need then
        if cw == nil and ctrl ~= nil then cw, ch = self:_cell_size_of(ctrl, cell_id) end
        if cw ~= nil then self:_fit_obj_layer(sub, cw, ch, L) end
        local src = nil
        pcall(function() src = sub.imageSource end)
        if L.src ~= nil then src = L.src end
        pcall(function() sub:SetImage(src, L.id) end)
        if L.color ~= nil then pcall(function() sub.imageColor = L.color end) end
        marks[sub] = { key = L.key, id = L.id, color = L.color,
                       w = L.w, h = L.h, dx = L.dx, dy = L.dy }
        if sub.SetActive then pcall(function() sub:SetActive(true) end) end
      end
      if sub.SetVisible then pcall(function() sub:SetVisible(true) end) end    
    end
  end
  return all_ready
end
local FURN_ART_CAP_DEFAULT = 260    
function Adapter:_furn_prefab_id()
  local cfg = self.cfg or {}
  local id = cfg.furn_prim_prefab
  if type(id) == "number" and id > 0 then return id end
  local hit = self:find("tpl.prim")
  if hit ~= nil then
    local v = nil
    pcall(function() v = hit.prefabIndex end)
    if type(v) == "number" and v > 0 then return v end
    pcall(function() v = hit.referencedPrefabIndex end)
    if type(v) == "number" and v > 0 then return v end
  end
  return nil
end
local function _num(v, d) local n = tonumber(v) return n or d end
function Adapter:_furn_destroy(ctrl)
  if ctrl == nil then return end
  if game ~= nil and game.DestroyClientUIControl ~= nil then
    pcall(game.DestroyClientUIControl, ctrl)
  elseif ctrl.Destroy ~= nil then
    pcall(function() ctrl:Destroy() end)
  end
end
local function _furn_key_of(name)
  if type(name) ~= "string" then return nil end
  local k = name:gsub(",", ".")
  k = k:gsub("^furn%.", "")
  k = k:gsub("%.", "_")
  if k == "table_1" then k = "table" end
  return k
end
function Adapter:_furn_prefab_map()
  local map = {}
  local things = self:find((self.cfg and self.cfg.furn_things_parent) or "things")
  if things ~= nil and things.GetChildren ~= nil then
    local ks = nil
    pcall(function() ks = things:GetChildren() end)
    if type(ks) == "table" then
      for i = 1, #ks do
        local ch = ks[i]
        local nm, prefab = nil, nil
        pcall(function() nm = ch.name end)
        pcall(function() prefab = ch.referencedPrefabIndex end)
        local key = _furn_key_of(nm)
        if key ~= nil and type(prefab) == "number" and prefab > 0 then
          map[key] = prefab
        end
      end
    end
  end
  local cfg_map = self.cfg and self.cfg.furn_tpl_prefab
  if type(cfg_map) == "table" then
    for k, v in pairs(cfg_map) do
      if map[k] == nil and type(v) == "number" and v > 0 then map[k] = v end
    end
  end
  return map
end
function Adapter:_face_prefab()
  local cfg = self.cfg or {}
  if type(cfg.face_tpl_prefab) == "number" and cfg.face_tpl_prefab > 0 then
    return cfg.face_tpl_prefab
  end
  local ref = self:find(cfg.face_tpl_ref or "tpl.cell.face")
  if ref ~= nil then
    local v = nil
    pcall(function() v = ref.referencedPrefabIndex end)
    if type(v) == "number" and v > 0 then return v end
  end
  return tonumber(cfg.face_tpl_fallback) or 1073747145
end
function Adapter:_ensure_cell_face(cell_id, ctrl)
  if cell_id == nil then return nil end
  local slot = self:_floor_slot(cell_id)
  if slot ~= nil then
    self:_sync_floor(cell_id, ctrl)
    return self:_fixed_floor_face(cell_id, slot)
  end
  if self:find("board.floors") ~= nil then return nil end
  self._face_guard = self._face_guard or {}
  if self._face_guard[cell_id] then return nil end
  self._face_guard[cell_id] = true
  local existing = nil
  local content0 = nil
  pcall(function() content0 = self:sub(cell_id, "content") end)
  if content0 ~= nil and content0.GetChild ~= nil then
    pcall(function() existing = content0:GetChild("face") end)
  end
  if existing ~= nil then
    self._face_guard[cell_id] = nil
    return existing
  end
  local prefab = self:_face_prefab()
  if prefab == nil or game == nil or game.InstantiateClientUIControl == nil then return nil end
  local content = nil
  pcall(function() content = self:sub(cell_id, "content") end)
  if content == nil then content = ctrl end
  if content == nil then return nil end
  local ok, obj = pcall(game.InstantiateClientUIControl, prefab, content)
  if not ok or obj == nil then
    self:warn_once("face:inst", "face 模板实例化失败（prefab=" .. tostring(prefab)
      .. " cell=" .. tostring(cell_id) .. "）⇒ 本格没有地板图，其余逻辑继续")
    self._face_guard[cell_id] = nil
    return nil
  end
  pcall(function() obj.name = "face" end)
  local cw, ch = self:_cell_size_of(ctrl, cell_id)
  pcall(function()
    if obj.SetAnchorMin then obj:SetAnchorMin(0.5, 0.5) end
    if obj.SetAnchorMax then obj:SetAnchorMax(0.5, 0.5) end
    if obj.SetPivot then obj:SetPivot(0.5, 0.5) end
    if obj.SetSizeDelta and cw ~= nil then obj:SetSizeDelta(cw, ch) end
    if obj.SetAnchoredPosition then obj:SetAnchoredPosition(0, 0) end
    if obj.SetSiblingIndex then obj:SetSiblingIndex(0) end    
    if obj.SetVisible then obj:SetVisible(true) end
  end)
  self._face_inst = self._face_inst or {}
  self._face_inst[cell_id] = obj
  self._face_guard[cell_id] = nil
  if print then
    print("[murdoku] 面层：cell=" .. tostring(cell_id) .. " 实例化 face（prefab="
      .. tostring(prefab) .. "，尺寸=" .. tostring(cw) .. "px）")
  end
  return obj
end
M.RING_IMAGE_ID = 100006
M.RING_GREEN = 0xFF4FAE5A
M.RING_RED   = 0xFFE0483A
function Adapter:_ensure_cell_ring(cell_id)
  if cell_id == nil then return nil end
  self._ring_inst = self._ring_inst or {}
  local content = nil
  pcall(function() content = self:sub(cell_id, "content") end)
  if content == nil then pcall(function() content = self:find(cell_id) end) end
  if content == nil then return nil end
  local obj = self._ring_inst[cell_id]
  if obj ~= nil and obj ~= false then
    local alive = false
    pcall(function() alive = (obj.name ~= nil) end)
    if alive then return obj end
    self._ring_inst[cell_id] = nil
  end
  obj = nil
  if content.GetChild ~= nil then
    pcall(function() obj = content:GetChild("verdict_ring") end)
    if obj ~= nil then
      self._ring_inst[cell_id] = obj
      self._ring_active = self._ring_active or {}
      self._ring_active[obj] = true
      return obj
    end
  end
  local prefab = self:_face_prefab()
  if prefab == nil or game == nil or game.InstantiateClientUIControl == nil then return nil end
  local ok, inst = pcall(game.InstantiateClientUIControl, prefab, content)
  if not ok or inst == nil then
    self:warn_once("ring:inst", "判定圈实例化失败（prefab=" .. tostring(prefab) .. "）⇒ 本关不显示红绿圈，其余逻辑继续")
    return nil
  end
  pcall(function() inst.name = "verdict_ring" end)
  local cw, ch = self:_cell_size_of(nil, cell_id)
  if cw == nil then cw, ch = 100, 100 end
  local d = math.floor(math.min(cw, ch or cw) * 0.9 + 0.5)
  pcall(function()
    if inst.SetAnchorMin then inst:SetAnchorMin(0.5, 0.5) end
    if inst.SetAnchorMax then inst:SetAnchorMax(0.5, 0.5) end
    if inst.SetPivot then inst:SetPivot(0.5, 0.5) end
    if inst.SetSizeDelta then inst:SetSizeDelta(d, d) end
    if inst.SetAnchoredPosition then inst:SetAnchoredPosition(0, 0) end
    local src = nil
    pcall(function() src = inst.imageSource end)
    if inst.SetImage then inst:SetImage(src, M.RING_IMAGE_ID) end
    if inst.SetVisible then inst:SetVisible(false) end
  end)
  pcall(function() inst.raycastTarget = false end)
  self._ring_inst[cell_id] = inst
  return inst
end
function Adapter:_paint_progress_ring(obj, amount, color)
  self._progress_ring_state = self._progress_ring_state or setmetatable({}, {__mode="k"})
  local states = self._progress_ring_state
  local st = states[obj]
  if st == nil then
    st = {}; states[obj] = st
    local ok, err = pcall(function()
      obj:SetVisible(false)
      local top = E("ImageFillRadialType.Top", nil)
      local radial = E("ImageFillType.Radial360", nil)
      local basic = E("ImageType.Basic", nil)
      assert(top ~= nil and radial ~= nil and basic ~= nil, "missing image fill enum")
      obj.imageType = basic
      obj.enableMask = true
      obj.reverseMaskArea = false
      obj.enableSoftEdge = false
      obj:SetFillRadial360(top, 0)
      obj.fillType = radial
      obj.fillRadialType = top
      obj.fillAmount = 0
      assert(obj.fillType == radial and obj.fillAmount == 0, "radial initialization readback mismatch")
    end)
    st.ready = ok
    if ok then st.radial = E("ImageFillType.Radial360", nil) end
    if not ok then self:warn_once("ring605:init", "环形填充初始化失败，已隐藏圆圈：" .. tostring(err)) end
  elseif st.ready and st.amount == nil then
    local same = false
    pcall(function() same = (st.radial ~= nil and obj.fillType == st.radial
      and obj.imageType == E("ImageType.Basic", nil)
      and obj.enableMask == true and obj.reverseMaskArea == false
      and obj.enableSoftEdge == false and obj.fillRadialType == E("ImageFillRadialType.Top", nil)) end)
    if not same then
      states[obj] = nil
      return self:_paint_progress_ring(obj, amount, color)
    end
  end
  if not st.ready then return false end
  local ok, err = pcall(function()
    if st.amount ~= amount then
      obj.fillAmount = amount
      assert(math.abs(obj.fillAmount - amount) < 0.0001, "fillAmount readback mismatch")
      st.amount = amount
    end
    if st.color ~= color then obj.imageColor = color; st.color = color end
    local visible = amount > 0
    if st.visible ~= visible then obj:SetVisible(visible); st.visible = visible end
  end)
  if not ok then
    st.ready = false
    pcall(function() obj:SetVisible(false) end)
    self:warn_once("ring605:update", "环形填充更新失败，已隐藏圆圈：" .. tostring(err))
  end
  return ok
end
function Adapter:set_verdict_ring(cell_id, ok, amount)
  local obj = self:_ensure_cell_ring(cell_id)
  if obj == nil then return nil end
  local a = tonumber(amount) or 0
  if a < 0 then a = 0 elseif a > 1 then a = 1 end
  local col = ok and M.RING_GREEN or M.RING_RED
  local used_fill = self:_paint_progress_ring(obj, a, col)
  self._ring_active = self._ring_active or {}
  self._ring_active[obj] = true
  self._ring_used_fill = used_fill
  return used_fill
end
function Adapter:_ensure_hold_ring(cell_id)
  if cell_id == nil then return nil end
  self._hold_ring_inst = self._hold_ring_inst or {}
  local content = nil
  pcall(function() content = self:sub(cell_id, "content") end)
  if content == nil then pcall(function() content = self:find(cell_id) end) end
  if content == nil then return nil end
  local obj = self._hold_ring_inst[cell_id]
  if obj ~= nil and obj ~= false then
    local alive = false
    pcall(function() alive = (obj.name ~= nil) end)
    if alive then return obj end
    self._hold_ring_inst[cell_id] = nil
  end
  obj = nil
  if content.GetChild ~= nil then
    pcall(function() obj = content:GetChild("hold_ring") end)
    if obj ~= nil then self._hold_ring_inst[cell_id] = obj; return obj end
  end
  local prefab = self:_face_prefab()
  if prefab == nil or game == nil or game.InstantiateClientUIControl == nil then return nil end
  local ok, inst = pcall(game.InstantiateClientUIControl, prefab, content)
  if not ok or inst == nil then
    self:warn_once("hold:inst", "长按圈实例化失败（prefab=" .. tostring(prefab) .. "）⇒ 本关不显示长按圈，其余逻辑继续")
    return nil
  end
  pcall(function() inst.name = "hold_ring" end)
  local cw, ch = self:_cell_size_of(nil, cell_id)
  if cw == nil then cw, ch = 100, 100 end
  local d = math.floor(math.min(cw, ch or cw) * 0.9 + 0.5)
  pcall(function()
    if inst.SetAnchorMin then inst:SetAnchorMin(0.5, 0.5) end
    if inst.SetAnchorMax then inst:SetAnchorMax(0.5, 0.5) end
    if inst.SetPivot then inst:SetPivot(0.5, 0.5) end
    if inst.SetSizeDelta then inst:SetSizeDelta(d, d) end
    if inst.SetAnchoredPosition then inst:SetAnchoredPosition(0, 0) end
    local src = nil
    pcall(function() src = inst.imageSource end)
    if inst.SetImage then inst:SetImage(src, M.RING_IMAGE_ID) end
    if inst.SetVisible then inst:SetVisible(false) end
  end)
  pcall(function() inst.raycastTarget = false end)
  self._hold_ring_inst[cell_id] = inst
  return inst
end
function Adapter:set_hold_ring(cell_id, amount)
  if self._hold_active_cell == cell_id and self._hold_amount == amount then return self._hold_used_fill end
  if self._hold_active_cell ~= cell_id then self:clear_hold_ring() end
  local obj = self:_ensure_hold_ring(cell_id)
  if obj == nil then return nil end
  local a = tonumber(amount) or 0
  if a < 0 then a = 0 elseif a > 1 then a = 1 end
  local col = 0xFFF2C94C
  local used_fill = self:_paint_progress_ring(obj, a, col)
  self._hold_active_cell, self._hold_amount = cell_id, amount
  self._hold_used_fill = used_fill
  return used_fill
end
function Adapter:clear_hold_ring()
  local id = self._hold_active_cell
  if id == nil then return end
  local obj = self._hold_ring_inst and self._hold_ring_inst[id]
  self._hold_active_cell, self._hold_amount = nil, nil
  if obj then
    self:_reset_ring_state(obj)
    pcall(function() if obj.SetVisible then obj:SetVisible(false) end end)
    pcall(function() obj.imageColor = 0 end)
  end
end
function Adapter:_reset_ring_state(obj)
  local states = self._progress_ring_state
  if not states then return end
  local st = states[obj]
  if st == nil then return end
  if st.ready then
    st.amount, st.color, st.visible = nil, nil, nil
  else
    states[obj] = nil
  end
end
function Adapter:clear_verdict_rings()
  self:clear_hold_ring()
  local active = self._ring_active
  for obj in pairs(active or {}) do
    if obj and obj ~= false then
      self:_reset_ring_state(obj)
      local hidden = pcall(function() if obj.SetVisible then obj:SetVisible(false) end end)
      local colored = pcall(function() obj.imageColor = 0 end)
      local reset = pcall(function()
        local top = E("ImageFillRadialType.Top", nil)
        if obj.SetFillRadial360 and top then obj:SetFillRadial360(top, 0) end
      end)
      if hidden and colored and reset then active[obj] = nil end
    end
  end
end
function Adapter:_apply_furn_level()
  if self._furn_inst ~= nil then
    for _, v in pairs(self._furn_inst) do self:_furn_destroy(v) end
  end
  self._furn_inst = {}
  self._furn_scaled = {}
  self._furn_ok_n = 0
  self._furn_fail_n = 0
  self._furn_keys = {}
  self._furn_retry_n = 0
  self._furn_last_try = -1
  -- 746：非关内（_furn_level == false）无需重查缺失家具容器或重建家具模板，直接返回，消除切屏触发的 8,578 节点全树 DFS 尖峰！
  if self._furn_level == false then
    return true
  end
  local c = self:find((self.cfg and self.cfg.furn_parent) or "board")
  self._furn_prefabs = self:_furn_prefab_map()
  if self._furn_arch_new == nil then
    local things = self:find((self.cfg and self.cfg.furn_things_parent) or "things")
    self._furn_arch_new = (things ~= nil) or (self.cfg and self.cfg.furn_arch_new == true) or false
  end
  self._furn_tpl_ok = (self._furn_prefabs ~= nil and next(self._furn_prefabs) ~= nil)
  if print then
    local ks = {}
    for k in pairs(self._furn_prefabs or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    print("[murdoku] 家具模板映射：things 找到="
      .. tostring(self:find((self.cfg and self.cfg.furn_things_parent) or "things") ~= nil)
      .. "　条目=" .. tostring(#ks) .. "　keys={" .. table.concat(ks, ",") .. "}"
      .. "　已缓存的请求格=" .. tostring(self._furn_want ~= nil and next(self._furn_want) ~= nil))
  end
  if self._furn_tpl_ok and self._furn_level ~= false then
    if self._furn_batch then
      self._furn_try_pending = true
    else
      pcall(function() self:_furn_try_all() end)    
    end
  end
  pcall(function()
    for _, id in pairs(self.cells or {}) do
      local ctrl = self:find(id)
      if ctrl ~= nil then self:_ensure_cell_face(id, ctrl) end
    end
  end)
  if print then
    print("[murdoku] 模板化家具：关卡=" .. tostring(self._furn_level) .. "（实例缓存已清）")
  end
  return true
end
function Adapter:begin_furn_batch()
  if self.cfg and self.cfg.furn_batch == false then return end
  self._furn_batch = true
end
function Adapter:end_furn_batch()
  self._furn_batch = false
  return self:flush_furn_pending()
end
function Adapter:flush_furn_pending()
  local dirty = self._furn_dirty
  self._furn_dirty = nil
  local all = self._furn_try_pending
  self._furn_try_pending = false
  if not self._furn_tpl_ok or self._furn_level == false then return 0 end
  local n = 0
  if all then
    pcall(function() n = self:_furn_try_all() end)
  elseif dirty ~= nil then
    for id in pairs(dirty) do
      local want = self._furn_want and self._furn_want[id]
      if type(want) == "string" then
        pcall(function()
          local ctrl = self:find(id)
          if ctrl ~= nil and self:_spawn_furn_tpl(id, ctrl, want) then n = n + 1 end
        end)
      end
    end
  end
  return n
end
local function furn_mark_dirty(self, id)
  self._furn_dirty = self._furn_dirty or {}
  self._furn_dirty[id] = true
end
function Adapter:_furn_try_all()
  if not self._furn_tpl_ok then return 0 end
  if self._furn_want == nil then return 0 end
  local n = 0
  for cell_id, name in pairs(self._furn_want) do
    if type(name) == "string" then
      local ctrl = self:find(cell_id)
      if ctrl ~= nil then
        pcall(function() self:_spawn_furn_tpl(cell_id, ctrl, name) end)
        n = n + 1
      end
    end
  end
  if n > 0 and print then
    local key = tostring(self._furn_level) .. "/" .. tostring(n)
    if self._furn_batch_log_key ~= key then
      self._furn_batch_log_key = key
      print("[murdoku] 模板化家具：本轮补造 " .. tostring(n) .. " 格（缓存里共 "
        .. tostring(n) .. " 格有家具）")
    end
  end
  return n
end
local function _furn_cfg_key(name)
  if type(name) ~= "string" then return nil end
  local k = name:gsub("^furn%.", "")
  k = k:gsub("%.", "_")           
  if k == "table_1" then k = "table" end    
  return k
end
function Adapter:_prepare_furn_layer(cell_id, layer_name, cw, ch, force)
  local layer = self:sub(cell_id, layer_name)
  if layer == nil then return nil end
  self._furn_layer_state = self._furn_layer_state or {}
  local key = cell_id .. ":" .. layer_name
  local old = self._furn_layer_state[key]
  if force or old == nil or old.obj ~= layer or old.w ~= cw or old.h ~= ch then
    if layer.SetAnchorMin then pcall(function() layer:SetAnchorMin(0.5, 0.5) end) end
    if layer.SetAnchorMax then pcall(function() layer:SetAnchorMax(0.5, 0.5) end) end
    if layer.SetPivot then pcall(function() layer:SetPivot(0.5, 0.5) end) end
    if layer.SetSizeDelta then pcall(function() layer:SetSizeDelta(cw, ch) end) end
    if layer.SetAnchoredPosition then pcall(function() layer:SetAnchoredPosition(0, 0) end) end
    if layer.SetVisible then pcall(function() layer:SetVisible(true) end) end
    if layer.SetActive then pcall(function() layer:SetActive(true) end) end
    self._furn_layer_state[key] = {obj=layer, w=cw, h=ch}
  end
  return layer
end
function Adapter:_floor_slot(id)
  local r,c=id:match("^cell%.(%d+)%.(%d+)$")
  if not r then return nil end
  self._floor_slots=self._floor_slots or {}
  local slot=self._floor_slots[id]
  if slot then return slot end
  slot=self:find("floor.cell."..r.."."..c)
  if slot then self._floor_slots[id]=slot end
  return slot
end
function Adapter:_fixed_floor_face(id,slot)
  self._floor_faces=self._floor_faces or {}
  local cached=self._floor_faces[id]
  if cached and cached.slot==slot then return cached.face end
  local face=slot:GetChild("face")
  if face then self._floor_faces[id]={slot=slot,face=face} end
  return face
end
function Adapter:_sync_floor(id,ctrl,show)
  local slot=self:_floor_slot(id)
  if not slot or not ctrl then return end
  local x,y=ctrl:GetAnchoredPosition()
  local w,h=ctrl:GetSizeDelta()
  self._floor_layout=self._floor_layout or {}
  local old=self._floor_layout[id]
  local visible=show
  if visible==nil then visible=old and old.show end
  if visible==nil then visible=true end
  local face=self:_fixed_floor_face(id,slot)
  if not old or old.x~=x or old.y~=y or old.w~=w or old.h~=h then
    slot:SetAnchoredPosition(x,y);slot:SetSizeDelta(w,h)
  end
  if face and (not old or old.face~=face or old.w~=w or old.h~=h) then
    self:_fit_child_sized(face,w,h)
  end
  if not old or old.show~=visible or old.face~=face then
    slot:SetVisible(visible)
    if visible and slot.SetActive then slot:SetActive(true) end
    if face then
      face:SetVisible(visible)
      if visible and face.SetActive then face:SetActive(true) end
    end
  end
  old=old or {}
  old.x,old.y,old.w,old.h,old.show,old.face=x,y,w,h,visible,face
  self._floor_layout[id]=old
end
function Adapter:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,span,off)
  local parent=self:find("board.rugs")
  if not parent then return false end
  local gap=(self.cfg.cells or {}).gap or 4
  local sr,sc=_num(span.r,1),_num(span.c,1)
  local px,py=cw+gap,ch+gap
  local x,y=ctrl:GetAnchoredPosition()
  x=x+_num(off.dx,0)*px;y=y-_num(off.dy,0)*py
  local w,h=cw+(sc-1)*px,ch+(sr-1)*py
  local key=cell_id.."|"..ckey
  self._furn_inst=self._furn_inst or {}
  self._whole_rug_applied=self._whole_rug_applied or {}
  local obj=self._furn_inst[key]
  local old=self._whole_rug_applied[key]
  local show=self._furn_level~=false
  local same_values=old and old.x==x and old.y==y and old.w==w and old.h==h
  local sig=same_values and old.sig or table.concat({x,y,w,h},":")
  if obj and old and old.sig==sig and old.show==show then
    old.x,old.y,old.w,old.h=x,y,w,h
    return true
  end
  if not obj then
    old=nil
    local ok;ok,obj=pcall(game.InstantiateClientUIControl,prefab,parent)
    if not ok or not obj then
      -- 695：原型注册失败时留一条可检索日志，便于真机定位 prefab / parent。
      if print then print("[murdoku] 地毯模板实例化失败：ckey="..tostring(ckey)
        .." prefab="..tostring(prefab).." ok="..tostring(ok)
        .." parent="..tostring(parent ~= nil and parent.name or "nil")) end
      return false
    end
    obj.name="rug."..cell_id
    self._furn_inst[key]=obj
  end
  if not old or old.sig~=sig then
    local cv=(self.cfg.furn_tpl_canvas or {})[ckey] or (ckey=="rug_2" and {216,108} or ckey=="rug_3" and {108,216} or {108,108})
    local k=_num(self.cfg.furn_scale,1)*_num((self.cfg.furn_scale_by_kind or {})[ckey],1)
    local ax=(self.cfg.furn_scale_axis_by_kind or {})[ckey]
    local sx,sy=k,k
    if ax then sx,sy=_num(ax.x,1),_num(ax.y,1) end
    self:_furn_scale_layers(obj,w/cv[1]*sx,h/cv[2]*sy)
    obj:SetAnchorMin(0.5,0.5);obj:SetAnchorMax(0.5,0.5);obj:SetPivot(0.5,0.5)
    obj:SetSizeDelta(w,h);obj:SetAnchoredPosition(x,y)
  end
  obj:SetVisible(show);if obj.SetActive then obj:SetActive(show) end
  old=old or {}
  old.sig,old.show,old.x,old.y,old.w,old.h=sig,show,x,y,w,h
  self._whole_rug_applied[key]=old
  return true
end
function Adapter:_spawn_furn_tpl(cell_id, ctrl, name)
  if cell_id == nil or type(name) ~= "string" then return false end
  local cfg = self.cfg or {}
  local prefabs = self._furn_prefabs or self:_furn_prefab_map()
  local ckey = _furn_cfg_key(name)
  local prefab = ckey ~= nil and prefabs[ckey] or nil
  if prefab == nil then
    self._furn_prefabs = self:_furn_prefab_map()
    prefabs = self._furn_prefabs
    prefab = ckey ~= nil and prefabs[ckey] or nil
  end
  if prefab == nil then
    self._furn_fail_n = (self._furn_fail_n or 0) + 1
    local key = "furnmiss:" .. tostring(ckey)
    if print then
      local once = self._furn_miss_logged or {}
      self._furn_miss_logged = once
      if not once[key] then
        once[key] = true
        local names = {}
        for k in pairs(prefabs or {}) do names[#names + 1] = k end
        table.sort(names)
        print("[murdoku] 家具模板缺映射：模板键=" .. tostring(name) .. " → 归一化键=" .. tostring(ckey)
          .. "　当前映射 keys={" .. table.concat(names, ",") .. "}"
          .. "　things 找到=" .. tostring(self:find((self.cfg and self.cfg.furn_things_parent) or "things") ~= nil))
      end
    end
    return false
  end
  if game == nil or game.InstantiateClientUIControl == nil then
    self._furn_tpl_ok = false
    self._furn_fail_n = (self._furn_fail_n or 0) + 1
    if print then
      print("[murdoku] 家具模板：环境没有 InstantiateClientUIControl（cell=" .. tostring(cell_id) .. "）")
    end
    return false
  end
  local cw, ch = self:_cell_size_of(ctrl, cell_id)
  if cw == nil then return false end           
  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3"
     or ckey=="rug_4" or ckey=="rug_5" then
    -- 694：恢复整块地毯模板实例化（688/689/690 真机可显示路径）。
    -- 三格 L 形用独立新建的 furn.rug.4/.5（216×216，边框只沿外围），
    -- 与桌椅/书架/植物/雕塑完全相同的一条素材引用路线，不复用、不拉伸。
    return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,
      (self._furn_span and self._furn_span[cell_id]) or {r=1,c=1},
      (self._furn_off and self._furn_off[cell_id]) or {dx=0,dy=0})
  end
  self._furn_inst = self._furn_inst or {}
  local inst_key = tostring(cell_id) .. "|" .. tostring(ckey)
  local inst = self._furn_inst[inst_key]
  local rescale = false
  do
    local want_span = (self._furn_span and self._furn_span[cell_id]) or { r = 1, c = 1 }
    local want_off = (self._furn_off and self._furn_off[cell_id]) or { dx = 0, dy = 0 }
    if inst ~= nil then
      local a = (self._furn_applied and self._furn_applied[inst_key]) or inst.__murdoku_applied
      local same = (a ~= nil)
        and a.span ~= nil and _num(a.span.r, 1) == _num(want_span.r, 1) and _num(a.span.c, 1) == _num(want_span.c, 1)
        and a.off ~= nil and math.abs(_num(a.off.dx, 0) - _num(want_off.dx, 0)) < 1e-6
        and math.abs(_num(a.off.dy, 0) - _num(want_off.dy, 0)) < 1e-6
        and a.cw ~= nil and math.abs(_num(a.cw, 0) - _num(cw, 0)) < 0.5
        and a.ch ~= nil and math.abs(_num(a.ch, 0) - _num(ch, 0)) < 0.5
      if not same then
        if a ~= nil and a.ckey == ckey and not (self.cfg and self.cfg.furn_rebuild_on_resize == true) then
          rescale = true
        else
          self:_furn_destroy(inst)
          self._furn_inst[inst_key] = nil
          if self._furn_applied then self._furn_applied[inst_key] = nil end
          inst = nil
        end
      end
    end
  end
  local function apply_scale(target)
    local span0 = self._furn_span and self._furn_span[cell_id] or { r = 1, c = 1 }
    local cv = (self.cfg and self.cfg.furn_tpl_canvas and self.cfg.furn_tpl_canvas[ckey]) or { 108, 108 }
    local fx = (cw * _num(span0.c, 1)) / _num(cv[1], 108)
    local fy = (ch * _num(span0.r, 1)) / _num(cv[2], 108)
    local k = _num(self.cfg and self.cfg.furn_scale, 1)
    local kb = self.cfg and self.cfg.furn_scale_by_kind
    if type(kb) == "table" then
      local kv = kb[ckey]
      if type(kv) ~= "number" then kv = kb["*"] end
      if type(kv) == "number" then k = k * kv end
    end
    local ax = self.cfg and self.cfg.furn_scale_axis_by_kind
    if type(ax) == "table" and type(ax[ckey]) == "table" then
      local t = ax[ckey]
      if type(t.x) == "number" then fx = fx * t.x end
      if type(t.y) == "number" then fy = fy * t.y end
    elseif k ~= 1 then
      fx, fy = fx * k, fy * k
    end
    self:_furn_scale_layers(target, fx, fy)
  end
  local is_rug = ckey == "rug" or ckey == "rug_2" or ckey == "rug_3"
                 or ckey == "rug_4" or ckey == "rug_5"
  local fixed_parent = self:_prepare_furn_layer(cell_id, is_rug and "rug_layer" or "furn", cw, ch)
  if rescale then apply_scale(inst) end
  if inst == nil then
    local parent = fixed_parent or self:sub(cell_id, "content") or ctrl
    local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
    if not ok or obj == nil then
      self._furn_tpl_ok = false
      self._furn_fail_n = (self._furn_fail_n or 0) + 1
      if print then
        print("[murdoku] 家具模板实例化失败：cell=" .. tostring(cell_id)
          .. " 模板键=" .. tostring(name) .. " prefab=" .. tostring(prefab)
          .. " 父控件=" .. tostring(parent ~= nil and parent.name or "nil")
          .. " ok=" .. tostring(ok) .. " obj=" .. tostring(obj))
      end
      return false
    end
    pcall(function() obj.name = "furni." .. cell_id end)
    inst = obj
    self._furn_inst[inst_key] = inst
    self.instantiated = self.instantiated or {}
    self.instantiated["furni." .. cell_id] = true
    apply_scale(inst)
    self._furn_ok_n = (self._furn_ok_n or 0) + 1
    self._furn_keys = self._furn_keys or {}
    self._furn_keys[name] = (self._furn_keys[name] or 0) + 1
    if print then
      local sn = tostring(name)
      self._furn_log_seen = self._furn_log_seen or {}
      local log_key = tostring(cell_id) .. "/" .. sn .. "/" .. tostring(prefab) .. "/"
        .. tostring(math.floor(cw)) .. "/" .. tostring(parent ~= nil and parent.name or "nil")
      if not self._furn_log_seen[log_key] then
        self._furn_log_seen[log_key] = true
        print("[murdoku] 家具模板：cell=" .. tostring(cell_id) .. " ← " .. sn
          .. "（prefab=" .. tostring(prefab) .. "，格子=" .. tostring(math.floor(cw)) .. "px"
          .. "，父控件=" .. tostring(parent ~= nil and parent.name or "nil") .. "）")
      end
    end
  end
  local span = (self._furn_span and self._furn_span[cell_id]) or { r = 1, c = 1 }
  local off = (self._furn_off and self._furn_off[cell_id]) or { dx = 0, dy = 0 }
  pcall(function()
    if inst.SetAnchorMin then inst:SetAnchorMin(0.5, 0.5) end
    if inst.SetAnchorMax then inst:SetAnchorMax(0.5, 0.5) end
    if inst.SetPivot then inst:SetPivot(0.5, 0.5) end
    if inst.SetSizeDelta then
      inst:SetSizeDelta(cw * _num(span.c, 1), ch * _num(span.r, 1))
    end
    if inst.SetAnchoredPosition then
      inst:SetAnchoredPosition(_num(off.dx, 0) * cw, -(_num(off.dy, 0) * ch))
    end
    self._furn_applied = self._furn_applied or {}
    self._furn_applied[inst_key] = {
      span = { r = _num(span.r, 1), c = _num(span.c, 1) },
      off = { dx = _num(off.dx, 0), dy = _num(off.dy, 0) },
      cw = _num(cw, 0), ch = _num(ch, 0),
      ckey = ckey,
    }
    if inst.SetVisible then inst:SetVisible(self._furn_level ~= false) end
    if inst.SetActive then inst:SetActive(self._furn_level ~= false) end
  end)
  return true
end
function Adapter:_furn_resync()
  local want = self._furn_want
  if want == nil then return 0 end
  local n = 0
  for id, tpl in pairs(want) do
    if type(tpl) == "string" then
      local ctrl = self:find(id)
      if ctrl ~= nil and self:_spawn_furn_tpl(id, ctrl, tpl) then n = n + 1 end
    end
  end
  return n
end
function Adapter:_furn_scale_layers(inst, fx, fy)
  if fy == nil then fy = fx end
  if inst == nil or fx == nil or fy == nil or fx <= 0 or fy <= 0 then return 0, 0 end
  local how = nil
  local ok = false
  if inst.SetLocalScale ~= nil then
    ok = pcall(function() inst:SetLocalScale(fx, fy, 1) end)
    if ok then how = "SetLocalScale" end
  end
  if not ok then
    ok = pcall(function() inst.localScaleX = fx; inst.localScaleY = fy; inst.localScaleZ = 1 end)
    if ok then how = "localScale 字段" end
  end
  if not ok then
    local kids = nil
    if inst.GetChildren ~= nil then pcall(function() kids = inst:GetChildren() end) end
    if type(kids) == "table" and #kids == 1 then
      local rt = kids[1]
      if rt ~= nil and rt.SetLocalScale ~= nil then
        ok = pcall(function() rt:SetLocalScale(fx, fy, 1) end)
        if ok then how = "内容根 SetLocalScale" end
      end
    end
  end
  if print then
    self._furn_scale_logged = self._furn_scale_logged or {}
    local key = tostring(how or "失败")
    if not self._furn_scale_logged[key] then
      self._furn_scale_logged[key] = true
      print(string.format("[murdoku] 家具缩放：比例=%.3f,%.3f 方式=%s%s",
        fx, fy, key, ok and "" or "（三种写法都不行 ⇒ 家具会偏大，请回传这行）"))
    end
  end
  if ok then return 1, 0 end
  return 0, 1
end
function Adapter:_furn_scale_children(inst, fx, fy)
  if fy == nil then fy = fx end
  if fx == nil or fx <= 0 or fy == nil or fy <= 0 then return 0, 0 end
  local kids = nil
  if inst.GetChildren ~= nil then pcall(function() kids = inst:GetChildren() end) end
  if type(kids) ~= "table" then return 0, 0 end
  local scaled, failed = 0, 0
  self._furn_base_vals = self._furn_base_vals or setmetatable({}, { __mode = "k" })
  self._furn_scale_n = (self._furn_scale_n or 0) + 1
  for i = 1, #kids do
    local ch = kids[i]
    if ch ~= nil then
      local w0, h0, dx0, dy0 = nil, nil, nil, nil
      if ch.GetSizeDelta ~= nil then
        pcall(function() local a, b = ch.GetSizeDelta(ch) w0, h0 = a, b end)
      end
      if w0 == nil then
        pcall(function() w0, h0 = ch.sizeDeltaX, ch.sizeDeltaY end)
      end
      if ch.GetAnchoredPosition ~= nil then
        pcall(function() local a, b = ch.GetAnchoredPosition(ch) dx0, dy0 = a, b end)
      end
      if dx0 == nil then
        pcall(function() dx0, dy0 = ch.anchoredPositionX, ch.anchoredPositionY end)
      end
      local key = tostring(i)
      local memo = self._furn_base_vals[inst]
      if memo == nil then memo = {} self._furn_base_vals[inst] = memo end
      if memo[key] == nil then
        if w0 ~= nil and h0 ~= nil then
          memo[key] = { w = w0, h = h0, dx = dx0 or 0, dy = dy0 or 0, fx = 1, fy = 1 }
        else
          memo[key] = { w = nil, h = nil, dx = dx0 or 0, dy = dy0 or 0, fx = 1, fy = 1, bad = true }
          failed = failed + 1
        end
      end
      local b = memo[key]
      if b ~= nil then
        if b.w ~= nil and b.h ~= nil then
          local changed = math.abs((b.fx or 1) - fx) > 0.001 or math.abs((b.fy or 1) - fy) > 0.001
          if changed then
            pcall(function()
              if ch.SetSizeDelta then
                ch:SetSizeDelta(b.w * fx, b.h * fy)
              else
                ch.sizeDeltaX, ch.sizeDeltaY = b.w * fx, b.h * fy
              end
              if b.dx ~= nil or b.dy ~= nil then
                if ch.SetAnchoredPosition then
                  ch:SetAnchoredPosition((b.dx or 0) * fx, (b.dy or 0) * fy)
                else
                  ch.anchoredPositionX = (b.dx or 0) * fx
                  ch.anchoredPositionY = (b.dy or 0) * fy
                end
              end
            end)
            b.fx, b.fy = fx, fy
            scaled = scaled + 1
          end
        else
          local avg = math.sqrt(fx * fy)
          if ch.SetLocalScale ~= nil then
            pcall(function() ch:SetLocalScale(avg, avg, 1) end)
          else
            pcall(function() ch.localScaleX = avg; ch.localScaleY = avg end)
          end
        end
      end
    end
  end
  if print and self._furn_scale_n <= 3 then
    print(string.format("[murdoku] 家具层缩放（兜底路径）：子层=%d 缩放=%.3f,%.3f 成功=%d 基值读不到=%d",
      #kids, fx, fy, scaled, failed))
  end
  return scaled, failed
end
function Adapter:_paint_furn_art(cell_id, ctrl, want, force)
  if cell_id == nil then return false end
  local state = self._furn_art_state
  if state == nil then state = {}; self._furn_art_state = state end
  local st = state[cell_id]
  if st == nil then st = { kids = {} }; state[cell_id] = st end
  local recs = want
  local n = (type(recs) == "table") and #recs or 0
  local cap = (self.cfg and self.cfg.furn_prim_cap) or FURN_ART_CAP_DEFAULT
  if n > cap then n = cap end
  if n == 0 then
    for i = 1, #st.kids do
      local k = st.kids[i]
      if k ~= nil and k.SetVisible ~= nil then pcall(function() k:SetVisible(false) end) end
    end
    st.shown = 0
    return true
  end
  local parent = self:sub(cell_id, "furn")
  if parent == nil then parent = ctrl or self:find(cell_id) end
  if parent == nil then return false end
  local prefab = self:_furn_prefab_id()
  if prefab == nil then
    if not self._furn_prefab_warned then
      self._furn_prefab_warned = true
      if printerr then
        printerr("[murdoku] 图元拼法家具画不出来：拿不到「控件模板索引」——"
          .. "请在存档里放一个『仅存为模板』的图片控件 tpl.prim，或填 cfg.furn_prim_prefab")
      end
    end
    return false
  end
  local cw, ch = self:_cell_size_of(ctrl, cell_id)
  if cw == nil or cw <= 0 then cw, ch = 108, 108 end
  local all_ok = true
  for i = 1, n do
    local e = recs[i]
    local k = st.kids[i]
    if k == nil then
      local okc, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
      if okc and obj ~= nil then
        k = obj
        st.kids[i] = k
        if k.SetAnchorMin ~= nil then pcall(function() k:SetAnchorMin(0.5, 0.5) end) end
        if k.SetAnchorMax ~= nil then pcall(function() k:SetAnchorMax(0.5, 0.5) end) end
        if k.SetPivot ~= nil then pcall(function() k:SetPivot(0.5, 0.5) end) end
        pcall(function() k.imageType = Enum.ImageType.Stretch end)
      else
        all_ok = false
      end
    end
    if k ~= nil then
      if e ~= nil then
        if k.SetImage ~= nil then
          pcall(function() k:SetImage(Enum.ImageSource.StaticReference, e[1]) end)
        end
        pcall(function() k.imageColor = e[7] end)    
        if k.SetSizeDelta ~= nil then pcall(function() k:SetSizeDelta(e[2] * cw, e[3] * ch) end) end
        if k.SetAnchoredPosition ~= nil then
          pcall(function() k:SetAnchoredPosition(e[4] * cw, -(e[5] * ch)) end)
        end
        local rot = e[6] or 0
        if rot ~= 0 and k.SetLocalRotation ~= nil then
          pcall(function() k:SetLocalRotation(0, 0, rot) end)
        end
        if k.SetActive ~= nil then pcall(function() k:SetActive(true) end) end
        if k.SetVisible ~= nil then pcall(function() k:SetVisible(true) end) end
      end
    end
  end
  for i = n + 1, #st.kids do
    local k = st.kids[i]
    if k ~= nil and k.SetVisible ~= nil then pcall(function() k:SetVisible(false) end) end
  end
  st.shown = n
  return all_ok
end
function Adapter:clear_board_portraits()
  for id in pairs(self._portrait_want or {}) do
    self._portrait_want[id] = false
    self:_paint_portrait(id, nil, false, true)
  end
  self._portrait_marks = nil
end
function Adapter:_paint_portrait(cell_id, ctrl, want, force)
  if cell_id == nil then return false end
  local p = self:sub(cell_id, "portrait")
  if p == nil then
    return false
  end
  if want == false or want == nil then
    if p.SetVisible then pcall(function() p:SetVisible(false) end) end
    return true
  end
  local marks = self._portrait_marks
  if marks == nil then
    marks = setmetatable({}, { __mode = "k" })    
    self._portrait_marks = marks
  end
  local m = marks[p]
  if force == true or m == nil or m.key ~= want.key or m.id ~= want.id then
    if ctrl ~= nil then self:_fit_child_to_cell(ctrl, p, cell_id) end
    local src = want.src
    if src == nil then pcall(function() src = p.imageSource end) end
    pcall(function() p:SetImage(src, want.id) end)
    pcall(function() p.imageColor = 4294967295 end)
    marks[p] = { key = want.key, id = want.id }
    if p.SetActive then pcall(function() p:SetActive(true) end) end
  end
  if p.SetVisible then pcall(function() p:SetVisible(true) end) end
  return true
end
function Adapter:_set_visible_deep(ctrl, show)
  local n = 0
  if ctrl == nil or ctrl.GetChildren == nil then return 0 end
  local kids = nil
  pcall(function() kids = ctrl:GetChildren() end)
  if type(kids) ~= "table" then return 0 end
  for i = 1, #kids do
    local ch = kids[i]
    if ch ~= nil and ch.SetVisible ~= nil then
      pcall(function() ch:SetVisible(show) end)
      n = n + 1
      n = n + self:_set_visible_deep(ch, show)
    end
  end
  return n
end
function Adapter:_apply_baked(want_log)
  local want = self._baked_level or false
  local levels = (self.cfg and self.cfg.baked_levels) or { "case_001", "case_002" }
  self._baked_state = self._baked_state or {}
  -- 746：非关内（want == false）且先前从未找到/显示过对应烘焙盒时，跳过缺失的 fart.* 查找与 root:GetChildren 兜底，
  -- 彻底消除同关切屏时因 fart.case_001 缺项触发的 8,578 节点全树索引重建！
  if want == false then
    local any_known = false
    for i = 1, #levels do
      local lv = levels[i]
      local st = self._baked_state[lv]
      if st == nil or st.found or st.show or self.controls["fart." .. lv] ~= nil then
        any_known = true
        break
      end
    end
    if not any_known then return true end
  end
  local root = self:find("root")
  for i = 1, #levels do
    local lv = levels[i]
    local box = self:find("fart." .. lv)
    if box == nil and root ~= nil and root.GetChildren ~= nil then
      local kids = nil
      pcall(function() kids = root:GetChildren() end)
      if type(kids) == "table" then
        for k = 1, #kids do
          local ch = kids[k]
          local nm = nil
          pcall(function() nm = ch.name end)           
          if type(nm) == "string" and nm:find("fart", 1, true) and nm:find(lv, 1, true) then
            box = ch
            break
          end
        end
      end
    end
    local show = (want == lv)
    local touched = 0
    if box ~= nil then
      if box.SetVisible then pcall(function() box:SetVisible(show) end) end
      if box.SetActive then pcall(function() box:SetActive(show) end) end
      -- 保留旧版首次点亮后代的语义，以后只控制父容器。
      self._baked_prepared652 = self._baked_prepared652 or setmetatable({}, { __mode = "k" })
      if show and not self._baked_prepared652[box] then
        touched = self:_set_visible_deep(box, true)
        self._baked_prepared652[box] = true
      end
    end
    local st = self._baked_state[lv]
    if st == nil or st.found ~= (box ~= nil) or st.show ~= show then
      self._baked_state[lv] = { found = (box ~= nil), show = show }
      if print then
        print(string.format("[murdoku] 烘焙容器 %s：找到=%s 目标=%s 子控件=%d",
          lv, tostring(box ~= nil), show and "显示" or "隐藏", touched))
      end
    elseif want_log == true and print then
      -- 状态未变化时不重复复述，首次状态已在上面的分支记录。
    end
  end
  do
    local lab = self:find("labels")
    if lab ~= nil and lab.SetSiblingIndex ~= nil and root ~= nil and root.GetChildren ~= nil then
      local kids, maxi = nil, nil
      pcall(function() kids = root:GetChildren() end)
      if type(kids) == "table" then
        for i = 1, #kids do
          local nm = nil
          pcall(function() nm = kids[i].name end)
          if type(nm) == "string" and nm:find("fart.", 1, true) then maxi = i end
        end
        if maxi ~= nil and (maxi + 1) <= #kids then
          pcall(function() lab:SetSiblingIndex(maxi + 1) end)
        end
      end
    end
  end
  return true
end
-- 702：选关动态内容必须具备有限变换；只校正内容，不改卡框/点击层和其它页面。
local function select_render_content(id)
  return id == "select.thumb.pool"
    or id:match("^select%.card%.%d+$") ~= nil
    or id:match("^hit%.select%.card%.%d+$") ~= nil
    or id:match("^select%.card%.%d+%.info$") ~= nil
    or id:match("^select%.card%.%d+%.title$") ~= nil
    or id:match("^select%.card%.%d+%.result$") ~= nil
    or id:match("^select%.card%.%d+%.boardbg$") ~= nil
    or id:match("^select%.card%.%d+%.cell%.") ~= nil
    or id:match("^select%.card%.%d+%.wall%.") ~= nil
    or id:match("^select%.card%.%d+%.door%.") ~= nil
end
local function finite_number(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
local function p745_read_pair(ctrl, method)
  local x, y = ctrl[method](ctrl)
  if type(x) == "table" then return x.x or x[1], x.y or x[2] end
  return x, y
end
local function read_pair(ctrl, method)
  local ok, x, y = pcall(p745_read_pair, ctrl, method)
  if not ok then return nil, nil end
  return x, y
end
function Adapter:set_property(id, key, value, nkey)
  local ctrl = self:find(id)
  if ctrl == nil then return false end
  if key=='shop_currency' and id=='econ.shop736.currency' then
    local src=E('ImageSource.Currency')
    if src==nil then return false end
    local ok=pcall(function() ctrl:SetImage(src,1115684865) end)
    return ok
  end
  if key == "settle_shift" then
    local base = self._settle_shift_base
    if base == nil or base.ctrl ~= ctrl then
      local ok, x, y = pcall(function() return ctrl:GetAnchoredPosition() end)
      if not ok or type(x) ~= "number" or type(y) ~= "number" then return false end
      base = { ctrl = ctrl, x = x, y = y, shift = 0 }
      self._settle_shift_base = base
    end
    local shift = tonumber(value) or 0
    local ok = pcall(function() ctrl:SetAnchoredPosition(base.x, base.y - shift) end)
    if ok then base.shift = shift end
    return ok
  end
  if key == "text" then
    if id:match('^econ%.') then
      local target = ctrl
      if id:match('%.back$') or id:match('%.buy$') then
        target = self:sub(id, 'label')
        if not target then return false end
        pcall(function() target.raycastTarget = false end)
        self._ray_want = self._ray_want or {}
        self._ray_want[target] = false
      end
      local expected = tostring(value or '')
      local ok = pcall(function() target.text = expected end)
      if not ok then pcall(function() target:SetText(expected) end) end
      local read, actual = pcall(function() return target.text end)
      return read and actual == expected
    end
    if id:match("^select%.card%.%d+%.info$") or id:match("^select%.card%.%d+%.title$") then
      -- 原生文本控件初始空值也必须尝试写入，并以读回决定是否完成。
      local expected = tostring(value or "")
      local units = 0
      for ch in expected:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        units = units + (#ch == 1 and 0.55 or 1)
      end
      local width = size_of(ctrl)
      local size = math.min(18, math.max(10, math.floor(((width or 184) - 6) / math.max(1, units))))
      -- 文字是必要写入；个别样式属性不可写时，不应中断正文更新。
      local ok = pcall(function() ctrl.text = expected end)
      if not ok then ok = pcall(function() ctrl:SetText(expected) end) end
      pcall(function() ctrl.adaptiveFontSize = false end)
      pcall(function() ctrl.minimumFontSize = size end)
      pcall(function() ctrl.fontSize = size end)
      pcall(function() ctrl.fontColor = 0xFF4A2E1C end)
      if Enum and Enum.TextHorizontalAlignment and Enum.TextVerticalAlignment then
        pcall(function() ctrl.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
        pcall(function() ctrl.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
      end
      local read_ok, actual = pcall(function() return ctrl.text end)
      return ok and read_ok and actual == expected
    end
    if id:match("%.settle%.countdown$") or id == "settle.btn.countdown"
       or id:match("^select%.card%.%d+%.result$") then
      local expected = tostring(value or "")
      local size = id:match("%.result$") and 16 or 14
      local ok = pcall(function()
        ctrl.adaptiveFontSize = false
        ctrl.minimumFontSize = size
        ctrl.fontSize = size
        ctrl.fontColor = 0xFFF9F2E9
        ctrl.text = expected
      end)
      if not ok then return false end
      local read_ok, actual = pcall(function() return ctrl.text end)
      return read_ok and actual == expected
    end
    local tef_target = nil
    do
      if self.text_editor_first and self.text_editor_first[id] then
        local lc = nil
        pcall(function() lc = self:sub(id, "label") end)
        if lc ~= nil and lc.text ~= nil then tef_target = lc
        elseif ctrl.text ~= nil then tef_target = ctrl
        else
          local tc = self:sub(id, "text")
          if tc ~= nil and tc.text ~= nil then tef_target = tc end
        end
        if tef_target ~= nil then
          local cur = nil
          pcall(function() cur = tef_target.text end)
          if cur ~= nil and tostring(cur) ~= "" then
            return true       
          end
        end
      end
    end
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
    return done
  elseif key == "baked_level" then
    self._baked_level = value or false
    return self:_apply_baked(true)
  elseif key == "furn_level" then
    self._furn_level = value or false
    return self:_apply_furn_level()
  elseif key == "furn_tpl" then
    self._furn_want = self._furn_want or {}
    self._furn_want[id] = type(value) == "string" and value or false
    if type(value) == "string" then
      if self._furn_inst ~= nil then
        local want_key = _furn_cfg_key(value)
        local prefix = tostring(id) .. "|"
        for k, v in pairs(self._furn_inst) do
          if type(k) == "string" and k:sub(1, #prefix) == prefix then
            local kk = k:sub(#prefix + 1)
            if want_key == nil or kk ~= tostring(want_key) then
              self:_furn_destroy(v)
              self._furn_inst[k] = nil
              if self._furn_applied then self._furn_applied[k] = nil end
            end
          end
        end
      end
      if self._furn_tpl_ok and self._furn_level ~= false then
        if self._furn_batch then furn_mark_dirty(self, id) else self:_spawn_furn_tpl(id, ctrl, value) end
      end
    else
      if self._furn_inst ~= nil then
        local prefix = tostring(id) .. "|"
        for k, v in pairs(self._furn_inst) do
          if type(k) == "string" and k:sub(1, #prefix) == prefix then
            self:_furn_destroy(v)
            self._furn_inst[k] = nil
            if self._furn_applied then self._furn_applied[k] = nil end
          end
        end
      end
    end
    return true
  elseif key == "furn_span" then
    self._furn_span = self._furn_span or {}
    self._furn_span[id] = (type(value) == "table") and value or false
    if self._furn_tpl_ok and self._furn_want and self._furn_want[id] and self._furn_level ~= false then    
      if self._furn_batch then furn_mark_dirty(self, id) else self:_spawn_furn_tpl(id, ctrl, self._furn_want[id]) end
    end
    return true
  elseif key == "furn_offset" then
    self._furn_off = self._furn_off or {}
    self._furn_off[id] = (type(value) == "table") and value or false
    if self._furn_tpl_ok and self._furn_want and self._furn_want[id] and self._furn_level ~= false then    
      if self._furn_batch then furn_mark_dirty(self, id) else self:_spawn_furn_tpl(id, ctrl, self._furn_want[id]) end
    end
    return true
  elseif key == "furn_art" then
    self._furn_art_want = self._furn_art_want or {}
    self._furn_art_want[id] = (type(value) == "table") and value or false
    return self:_paint_furn_art(id, ctrl, value, true)
  elseif key == "furn" then
    if self._furn_tpl_ok then return true end
    if self._furn_arch_new then
      self:warn_once("furn:newarch",
        "新架构（things/无 obj 层）⇒ 手搭层（地毯）本轮跳过；需要地毯请让 integrator 在 things 加 `furn.rug` 模板。")
      return true
    end
    local layers = {}
    if type(value) == "table" then
      for i = 1, math.min(#value, #OBJ_LAYER_SUBS) do
        local e = value[i]
        if type(e) == "table" and type(e.id) == "number" then
          layers[#layers + 1] = {
            key = "furn." .. i,
            id = e.id,
            color = e.color,
            w = e.w, h = e.h, dx = e.dx, dy = e.dy,
          }
        end
      end
    end
    local want = false
    if #layers > 0 then want = { key = "furn", layers = layers } end
    self._obj_want = self._obj_want or {}
    self._obj_want[id] = want
    return self:_paint_obj(id, ctrl, want, true)
  elseif key == "furn_anchor" then
    -- ★ 685 通用构造法：抬格只发生在 stage 内部；之后立刻把标记层复位，
    --   无论将来新增什么 kind / span 的多格家具，X 都不会被盖住。
    self:_mark_layer_guard()
    if value == true and ctrl ~= nil and ctrl.SetAsLastSibling ~= nil then
      local ok = pcall(function() ctrl:SetAsLastSibling() end)
      if not ok then return false end
      self._furn_anchors = self._furn_anchors or {}
      self._furn_anchors[id] = true
    end
    self:_mark_layer_raise()
    return true
  elseif key == "object" then
    local want = false
    if not (value == false or value == nil) then
      local vkey = tostring(value)
      local kind = vkey:match("^obj%.(.+)$") or vkey
      local map = self:read_palette()
      local layers = {}
      for li = 1, #OBJ_LAYER_SUBS do
        local k = (li == 1 and ("obj.") or ("obj" .. li .. ".")) .. kind
        local hit = map[k]
        if type(hit) == "table" and type(hit.id) == "number" then
          layers[#layers + 1] = {
            key = k, src = hit.source, id = hit.id, color = hit.color,
            w = hit.w, h = hit.h, dx = hit.dx, dy = hit.dy,
          }
        end
      end
      if #layers > 0 then
        want = { key = vkey, layers = layers }
      end
    end
    self._obj_want = self._obj_want or {}
    self._obj_want[id] = want
    self:_paint_obj(id, ctrl, want, true)
  elseif key == "hint" then
    local h = self:sub(id, "hint")
    if h == nil then
      self:warn_once("hint:missing", "模板里没有 `hint` 子控件（线索位置提示画不出来）"
        .. " —— 2026-10-17 的存档里它在 `cell` 的 `content` 下")
      return true
    end
    self:_fit_child_to_cell(ctrl, h, id)
    local on = (value == true)
    if h.SetVisible then pcall(function() h:SetVisible(on) end) end
    if on then
    end
    if on and h.SetActive then pcall(function() h:SetActive(true) end) end
    return true
  elseif key == "fit" then
    local n = tonumber(value)
    if n ~= nil and n > 1 then
      for _, nm in ipairs({ "face", "hint", "obj", "portrait" }) do
        local s2 = self:sub(id, nm)
        if s2 ~= nil then self:_fit_child_sized(s2, n, n) end
      end
    end
    return true
  elseif key == "imageType" then
    local want = nil
    pcall(function() want = value end)
    if want ~= nil then
      local enum = nil
      pcall(function() enum = Enum.ImageType[tostring(want)] end)
      if enum ~= nil then
        pcall(function() ctrl.imageType = enum end)
        local f = self:sub(id, "face")
        if f ~= nil then pcall(function() f.imageType = enum end) end
      end
    end
  elseif key == "image" then
    if is_cell_id(id) then
      local want = false
      if value ~= nil and value ~= false then
        local hit = self:resolve_asset(value)
        if hit ~= nil and hit.id ~= nil then
          want = { key = tostring(value), id = hit.id, src = hit.source }
        end
      end
      self._portrait_want = self._portrait_want or {}
      self._portrait_want[id] = want
      return self:_paint_portrait(id, ctrl, want, true)
    end
    local target = self:sub(id, "face") or ctrl
    if target ~= nil then
      if is_cell_id(id) then self:_fit_child_to_cell(ctrl, target, id) end
      self._face_def = self._face_def or {}
      local d = self._face_def[id]
      if d == nil then
        d = { src = nil, id = nil, visible = true }
        pcall(function() d.src = target.imageSource end)
        pcall(function() d.id = target.imageId end)
        pcall(function() d.visible = target.visible end)
        self._face_def[id] = d
      end
      if value == false then value = nil end
      if value == nil then
        if d.swapped then                        
          if target.SetImage and d.id ~= nil then
            pcall(function() target:SetImage(d.src, d.id) end)
          end
          d.swapped = false
        end
      elseif target.SetImage then
        local src = target.imageSource                  
        local hit = self:resolve_asset(value)
        if hit ~= nil then
          if hit.source ~= nil then src = hit.source end    
          if hit.id ~= nil then
            local ok, err = pcall(function() target:SetImage(src, hit.id) end)
            if not ok then self:warn_once("setimage", "SetImage 失败：" .. tostring(err)) end
            d.swapped = true
          end
        end
        p745_set_vis_guard(target, true)
        if self.cfg.debug_image then
          local it = nil
          pcall(function() it = tostring(target.imageType) end)
          print(string.format("[murdoku] SetImage 后 `%s` 的 imageType = %s（Basic=按原始像素 / Stretch=填满）",
            tostring(id), tostring(it)))
        end
      end
    end
  elseif key == "walls" then
    if self._hidden_ids ~= nil and self._hidden_ids[id] and self._hidden_enforced746 ~= nil then
      self._hidden_enforced746[id] = nil
      self._subtree_dirty_ids = self._subtree_dirty_ids or {}
      self._subtree_dirty_ids[id] = true
      self._subtree_urgent747 = true
    end
    return self:_apply_edges(id, "wall", value)
  elseif key == "doors" then
    if self._hidden_ids ~= nil and self._hidden_ids[id] and self._hidden_enforced746 ~= nil then
      self._hidden_enforced746[id] = nil
      self._subtree_dirty_ids = self._subtree_dirty_ids or {}
      self._subtree_dirty_ids[id] = true
      self._subtree_urgent747 = true
    end
    return self:_apply_edges(id, "door", value)
  elseif key == "tint" then
    local target = self:sub(id, "face") or ctrl
    if target ~= nil then
      if is_cell_id(id) then self:_fit_child_to_cell(ctrl, target) end
      local made = nil
      if type(value) == "number" then
        made = value
      elseif type(value) == "table" then
        local r = tonumber(value.r or value[1]) or 255
        local g = tonumber(value.g or value[2]) or 255
        local b = tonumber(value.b or value[3]) or 255
        local a = tonumber(value.a or value[4]) or 255
        made = M.pack_color(r, g, b, a)
      end
      if made ~= nil then
        local ok = pcall(function() target.imageColor = made end)
        if not ok then
          self:warn_once("tint", "设置 imageColor 失败（imageColor 可能不是整数）")
        end
      end
    end
  elseif key == "visible" then
    -- ★ 686：stage 被隐藏时整层收起（父容器隐藏不级联子控件）
    if id == ((self.cfg.cells or {}).parent or "board") and value ~= true then
      self:_mark_hide_all()
    end
    if id == ((self.cfg.cells or {}).parent or "board") then
      for _,name in ipairs({"board.floors","board.rugs"}) do
        local layer=self:find(name)
        if layer then
          layer:SetVisible(value==true)
          if value==true and layer.SetActive then layer:SetActive(true) end
        end
      end
    end
    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl,value==true) end
    -- ★ 686：cell 的 visible 随 self.screen 变化（离开关卡 = false）。标记层不在
    --   layout_plan 节点表里，没人给它关灯 ⇒ 这里逐组收起并置屏幕门控。
    do
      local rc = tostring(id):match("^cell%.(.+)$")
      if rc ~= nil then
        if value == true then
          self._mark_screen_on = true
        else
          self._mark_screen_on = false
          self:_mark_set_visible(rc, false)
        end
      end
    end
    local vis = value and true or false
    if vis then pcall(p748_set_active_true, ctrl) end
    local ok_vg747, prev_vis747 = pcall(p748_set_vis_if, ctrl, vis)
    self._hidden_ids = self._hidden_ids or {}
    if vis then
      self._hidden_ids[id] = nil
      if self._subtree_dirty_ids ~= nil then self._subtree_dirty_ids[id] = nil end
      if self._hidden_enforced746 ~= nil then self._hidden_enforced746[id] = nil end
      -- 若显示的是某隐藏容器下的命名子项（如 clues.grid 之于 clues），失效该父容器的已藏缓存确保子树重新收起。
      local pfx = type(id) == "string" and id:match("^([^%.]+)%.") or nil
      if pfx ~= nil and self._hidden_ids[pfx] then
        if self._hidden_enforced746 ~= nil then self._hidden_enforced746[pfx] = nil end
        self._subtree_dirty_ids = self._subtree_dirty_ids or {}
        self._subtree_dirty_ids[pfx] = true
        self._subtree_urgent747 = true
      end
    else
      self._hidden_ids[id] = true
      -- 747（P2-1）：用写前回读 prev_vis747 替代未定义 cur_vis，使已隐藏子树的幂等去重真正生效。
      if not (self._hidden_enforced746 ~= nil and self._hidden_enforced746[id] == true and ok_vg747 and prev_vis747 == false) then
        self._subtree_dirty_ids = self._subtree_dirty_ids or {}
        self._subtree_dirty_ids[id] = true
        self._subtree_urgent747 = true
      end
    end
    if vis and id:sub(1, 5) == "cell." then
      self._overlay_dirty = true
    end
    if vis == false and id:sub(1, 5) == "cell." then
      local function hide_kids(node, depth)
        if node == nil or depth > 4 then return end
        local ok_k, kids = pcall(p744_kids, node)
        if ok_k and type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil then
              pcall(p745_set_vis_false, k)
              local ok_n, nm = pcall(p744_name, k)
              if not ok_n or (nm ~= "furn" and nm ~= "rug_layer" and nm ~= "board.floors" and nm ~= "board.rugs" and nm ~= "x") then
                hide_kids(k, depth + 1)
              end
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
    if vis == true and id:sub(1, 5) == "cell." then
      local ok_f, face = pcall(self.sub, self, id, "face")
      if ok_f and face ~= nil then p745_set_vis_guard(face, true) end
      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil then p745_set_vis_guard(s2, want) end
        end
      end
    end
    if not ok_vg747 then return false end
  elseif key == "raycast" then
    local want = value and true or false
    self._ray_want = self._ray_want or setmetatable({}, { __mode = "k" })
    self._ray_want[ctrl] = want
    -- 748（B2/U6）：三项属性各自独立无闭包 pcall，首项抛错绝不跳过后两项，且任一失败返回 false 阻止 _props 锁死缓存。
    local ok1 = pcall(p748_set_bool_prop, ctrl, "raycastTarget", want)
    local ok2 = pcall(p748_set_bool_prop, ctrl, "blockRaycast", want)
    local ok3 = pcall(p748_set_bool_prop, ctrl, "interactable", want)
    if not (ok1 and ok2 and ok3) then return false end
  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
      -- ★ 687：682/683 把胶囊与描边收进名为 art 的 DECOR 容器后，bg 子层已不存在，
      --   上面的染色够不到按钮 ⇒ 未启用结算时不再变灰。这里沿 art 容器逐层恢复/置灰。
      --   颜色口径：启用 outline=#FF6C402E / capsule=#FFFCECD4；禁用统一 #FF686B70。
      local art = self:sub(id, "art")
      if art ~= nil then
        local kids = nil
        pcall(function() kids = art:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do
            local k = kids[i]
            if k ~= nil then
              local nm = nil
              pcall(function() nm = k.name end)
              local outline = (type(nm) == "string" and nm:find("outline") ~= nil)
              pcall(function()
                if k.imageColor ~= nil then
                  k.imageColor = value and (outline and 0xFF6C402E or 0xFFFCECD4) or 0xFF686B70
                end
              end)
            end
          end
        end
      end
    end
  elseif key == "rect" and self.apply_rect then
    if ctrl.SetAnchoredPosition then ctrl:SetAnchoredPosition(value.x, value.y) end
    if ctrl.SetSizeDelta then ctrl:SetSizeDelta(value.w, value.h) end
    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl) end
  elseif key == "event" then
    local k = nkey or id
    self.events[k] = value
    if self.event_claim[id] == nil then self.event_claim[id] = k end
    self.event_latest[id] = k
  elseif key == "rect" then
    -- v13: 根保持存档中的四边拉伸，子控件继续使用原设计坐标。
    if id == "root" then return true end
    if self.cfg.respect_editor_rect ~= false
       and not (self.instantiated and self.instantiated[id])
       and not (self.runtime_rect and self.runtime_rect[id]) then
      return true
    end
    local sc = self.cfg.scale or (5 / 6)
    -- 704：选关图元的格宽/格缝已在画布上量化；保留共同小数中心。
    -- 分别取整中心和尺寸会把相邻格缝改成 0/1/2 像素。
    local exact_select = select_render_content(id)
    local function R(v)
      if exact_select then return v or 0 end
      return math.floor((v or 0) + 0.5)
    end
    local w = R((value.w or 0) * sc)
    local h = R((value.h or 0) * sc)
    local cx = R(((value.x or 0) + (value.w or 0) * 0.5) * sc)
    local cyTop = R(((value.y or 0) + (value.h or 0) * 0.5) * sc)    
    local ch = self.cfg.canvas_h or 900
    local cy = ch - cyTop                                             
    self.rects = self.rects or {}
    self.rects[id] = { cx = cx, cy = cy, w = w, h = h }
    if w ~= nil and h ~= nil and type(id) == "string" and id:match("^cell%.%d+%.%d+$") then
      for _, nm in ipairs({ "face", "hint", "obj", "portrait" }) do
        local sub3 = self:sub(id, nm)
        if sub3 ~= nil then self:_fit_child_sized(sub3, w, h) end
      end
    end
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
    if pcx == nil and pid ~= nil and self.rects[pid] ~= nil then
      pcx, pcy = self.rects[pid].cx, self.rects[pid].cy
    end
    if pcx == nil then
      pcx = R((self.cfg.canvas_w or 1600) * 0.5)
      pcy = R(ch * 0.5)
    end
    if select_render_content(id) then
      -- 原型可能带 NaN 缩放，写 text/size 不会修复它。所有 setter 都必须成功。
      if not (finite_number(w) and finite_number(h) and finite_number(cx)
          and finite_number(cy) and finite_number(pcx) and finite_number(pcy)) then return false end
      local function near0(a, b) return finite_number(a) and math.abs(a - b) < 0.01 end
      local rw0, rh0 = read_pair(ctrl, "GetSizeDelta")
      local rx0, ry0 = read_pair(ctrl, "GetAnchoredPosition")
      local sx0, sy0 = read_pair(ctrl, "GetLocalScale")
      if near0(rw0, w) and near0(rh0, h) and near0(rx0, cx - pcx) and near0(ry0, cy - pcy)
         and near0(sx0, 1) and near0(sy0, 1) then
        local aminx0, aminy0 = read_pair(ctrl, "GetAnchorMin")
        local amaxx0, amaxy0 = read_pair(ctrl, "GetAnchorMax")
        local px0, py0 = read_pair(ctrl, "GetPivot")
        if near0(aminx0, 0.5) and near0(aminy0, 0.5) and near0(amaxx0, 0.5) and near0(amaxy0, 0.5)
           and near0(px0, 0.5) and near0(py0, 0.5) then
          return true
        end
      end
      local ok, err = pcall(function()
        ctrl:SetLocalScale(1, 1, 1)
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(cx - pcx, cy - pcy)
      end)
      if not ok then
        self:warn_once("select_rect:" .. id, "选关内容变换写入未完成，保留重试：" .. id .. " / " .. tostring(err))
        return false
      end
      local function near(a, b) return finite_number(a) and math.abs(a - b) < 0.01 end
      local rw, rh = read_pair(ctrl, "GetSizeDelta")
      local rx, ry = read_pair(ctrl, "GetAnchoredPosition")
      local sx, sy = read_pair(ctrl, "GetLocalScale")
      local aminx, aminy = read_pair(ctrl, "GetAnchorMin")
      local amaxx, amaxy = read_pair(ctrl, "GetAnchorMax")
      local px, py = read_pair(ctrl, "GetPivot")
      local ready = near(rw, w) and near(rh, h) and near(rx, cx - pcx) and near(ry, cy - pcy)
        and near(sx, 1) and near(sy, 1)
        and near(aminx, 0.5) and near(aminy, 0.5) and near(amaxx, 0.5) and near(amaxy, 0.5)
        and near(px, 0.5) and near(py, 0.5)
      if not ready then
        self:warn_once("select_readback:" .. id, "选关内容变换回读不符，保留重试：" .. id)
        return false
      end
      return true
    end
    if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
    if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
    if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
    if ctrl.SetSizeDelta then pcall(function() ctrl:SetSizeDelta(w, h) end) end
    if ctrl.SetAnchoredPosition then
      pcall(function() ctrl:SetAnchoredPosition(cx - pcx, cy - pcy) end)
    end
    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl) end
  elseif key == "style" then
    local PLACED_TINT = 2147483647
    local NORMAL_TINT = 4294967295       
    self._style = self._style or {}
    self._style[id] = value              
    local scale = self:scale_of_style(value)
    if scale and ctrl.SetLocalScale then ctrl:SetLocalScale(scale, scale, 1) end
    local wantColor = self:color_of_style(value)
    if wantColor ~= nil and ctrl.fontColor ~= nil then
      pcall(function() ctrl.fontColor = wantColor end)
    end
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
    local c = self:sub(id, "note")
    if c ~= nil then
      local txt = nil
      if type(value) == "table" then
        txt = table.concat(value, " ")
      elseif value == false or value == nil then
        txt = ""
      else
        txt = tostring(value)
      end
      if c.text ~= nil then c.text = txt end
      if type(c.SetText) == "function" then pcall(function() c:SetText(txt) end) end
      if c.SetVisible then pcall(function() c:SetVisible(txt ~= "") end) end
      if txt ~= "" then
        if c.SetActive then pcall(function() c:SetActive(true) end) end
        if c.SetAsLastSibling then pcall(function() c:SetAsLastSibling() end) end
        local fw, fh = nil, nil
        pcall(function()
          local f = self:sub(id, "face")
          if f ~= nil then fw, fh = f:GetSizeDelta() end
        end)
        if fw ~= nil and fh ~= nil and fw > 1 and fh > 1 then
        end
      end
    end
  elseif key == "x_mark" then
    local c = self:sub(id, "x")
    if c and c.SetVisible then c:SetVisible(value and true or false) end
    -- ★ 685：镜像到 stage 末尾的标记层（格内 x 保留作兜底，同位同色叠加不可见）
    local m, rc = self:_mark_ctrl(id)
    if rc ~= nil then self:_mark_set_visible(rc, value and true or false) end
    self:_mark_scope()
    self:_mark_layer_raise()
  end
  return true
end
function Adapter:_fire(event, phase, data, src_id)
  self._subtree_dirty = true
  if self.on_input == nil then return end
  local evt = {}
  for k, v in pairs(event) do evt[k] = v end
  evt.phase = phase
  if data and data.GetUIPos then
    local ok, x, y = pcall(function() return data:GetUIPos() end)
    if ok then evt.x, evt.y = x, y end
  end
  if src_id ~= nil and evt.r == nil then
    local R, C = tostring(src_id):match("^cell%.(%d+)%.(%d+)$")
    if R ~= nil then
      evt.r = tonumber(R)
      evt.c = tonumber(C)
    end
  end
  self.on_input(evt)
end
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
function Adapter:input_profile()
  local d = self:device()
  if d == "Mobile" or d == "MobileController" then return "touch" end
  if d == "Controller" then return "gamepad" end
  return "pc"         
end
function Adapter:bind_input(id, node)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if ctrl.AddCursorEventListener == nil then
    self:warn_once("nocursor:" .. tostring(id),
      "控件 " .. tostring(id) .. " 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）")
    return
  end
  self._listeners = self._listeners or setmetatable({}, {__mode='k'})
  local was_bound747 = (self._listeners[ctrl] ~= nil)
  local done=self._listeners[ctrl] or {}; self._listeners[ctrl]=done
  if not was_bound747 and self.ensure_raycast ~= nil and not (self._ray_want and self._ray_want[ctrl] == false)
     and (self:has_static_route747(id) or (type(id) == "string" and id:sub(1, 5) == "cell.")) then
    pcall(self.ensure_raycast, self, ctrl)
  end
  local pending=false
  local function listen(kind,callback)
    if done[kind] then return end
    local ok,result=pcall(ctrl.AddCursorEventListener,ctrl,kind,callback)
    if ok and result~=false then done[kind]=true else pending=true end
  end
  local click = E("CursorEventType.CursorClick")
  if click == nil then
    self:warn_once("noenum", "Enum.CursorEventType.CursorClick 缺失，无法绑定点击")
    return
  end
  --                       
  --                
  if self.cfg.debug_event == true then
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
  local function live_event()
    local k = self.event_claim[id]
    local cur = nil
    if k ~= nil then cur = self.events[k] end
    return cur or node.event or { action = "click" }
  end
  listen(click, function(data)
    if self.cfg.debug_click ~= false then
      self._click_seen = (self._click_seen or 0) + 1
      if self._click_seen <= 8 and print then
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
          .. "  事件=" .. tostring((live_event() or {}).action or "nil"))
      elseif self._click_seen == 9 and print then
        print("[murdoku] （点击日志到此为止，后面不再刷；cfg.debug_click = false 可关）")
      end
    end
    self:_fire(live_event(), "click", data, id)
  end)
  local down = E("CursorEventType.CursorDown")
  if down ~= nil then
    listen(down, function(data)
      self:_fire(live_event(), "down", data, id)
    end)
  end
  local up = E("CursorEventType.CursorUp")
  if up ~= nil then
    listen(up, function(data)
      self:_fire(live_event(), "up", data, id)
    end)
  end
  local drag = E("CursorEventType.CursorDrag")
  if drag ~= nil then
    listen(drag, function(data)
      self:_fire(live_event(), "drag", data, id)
    end)
  end
  self._retry_input=self._retry_input or {}
  if pending then self._retry_input[id]=node else self._retry_input[id]=nil end
  if self:has_static_route747(id) or (type(id) == "string" and id:sub(1, 5) == "cell.") then
    self:register_watch_handle748(id, ctrl, "adapter", node, nil, nil)
  end
end
function Adapter:bind_keys(spec, control_id)
  self.keymap = self.keymap or {}
  if game == nil then return 0, "没有 game 环境" end
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
      local et = E("KeyEventType." .. key_name)
      if et == nil then
        unresolved[#unresolved + 1] = key_name
      else
        if self.cfg.debug_key and print then
          self._key_dbg = (self._key_dbg or 0) + 1
          if self._key_dbg <= 4 then
            print("[murdoku] KeyEventType 解析：" .. key_name
              .. " -> type=" .. type(et) .. " 值=" .. tostring(et))
          end
        end
        local ok,result = pcall(function()
          return ctrl:AddKeyEventListener(et, function()
            if self.cfg.debug_key then
              print("[murdoku] 按键事件 → " .. tostring(key_name))
            end
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
              evt.key = key_name       
              self.on_input(evt)
            end
            return false
          end)
        end)
        if ok and result~=false then self.keymap[key_name]=event; n = n + 1 else failed = failed + 1 end
      end
    end
  end
  local note = "绑在 " .. tostring(used) .. " 上，成功 " .. n .. " 个"
  if failed > 0 then note = note .. "，失败 " .. failed .. " 个" end
  if #unresolved > 0 then
    note = note .. "；" .. #unresolved .. " 个键名取不到 Enum.KeyEventType："
      .. table.concat(unresolved, ", ")
  end
  return n, note, failed==0 and #unresolved==0
end
local EFFECTS = {
  pop_tile     = { dur = 0.26, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.62 }, { 0.55, 1.06 }, { 1.00, 1.00 } } },
  note_pop     = { dur = 0.14, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 0.90 }, { 1.00, 1.00 } } },
  pulse        = { dur = 0.18, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.50, 1.14 }, { 1.00, 1.00 } } },
  sel_pop_glow = { dur = 0.30, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.45, 1.12 }, { 0.70, 1.03 }, { 1.00, 1.00 } } },
  undo_flash   = { dur = 0.16, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.05 }, { 1.00, 1.00 } } },
  submit_nudge = { dur = 0.28, ease = "OutCubic", ch = "scale",
                   keys = { { 0.00, 1.000 }, { 0.40, 1.035 }, { 1.00, 1.000 } } },
  clue_box_pop = { dur = 0.22, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.82 }, { 0.60, 1.03 }, { 1.00, 1.00 } } },
  solved_flash = { dur = 0.36, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.40, 1.12 }, { 1.00, 1.00 } } },
  vanish       = { dur = 0.20, ease = "InQuad",   ch = "scale",
                   keys = { { 0.00, 1.00 }, { 1.00, 0.00 } } },
  shake        = { dur = 0.30, ease = "Linear",   ch = "pos_x",
                   keys = { { 0.00, 0 }, { 0.20, -8 }, { 0.45, 8 },
                            { 0.70, -5 }, { 1.00, 0 } } },
  portrait_slide_up = { dur = 0.34, ease = "OutBack", ch = "pos_y",
                   keys = { { 0.00, -34 }, { 0.70, 4 }, { 1.00, 0 } } },
}
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
  shake        = nil,
  portrait_slide_up = nil,
}
function Adapter:ease_of(name)
  if name == nil then return nil end
  local e = E("EaseType." .. tostring(name))
  if e == nil then e = E("EaseType.Linear") end
  return e
end
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
    self:warn_once("nomotion:" .. tostring(effect_name),
      "没有这条动效定义：" .. tostring(effect_name)
      .. "（核对 EFFECTS 表与 ui_controller 里 M.EFFECTS 的名字）")
    return
  end
  local base = read_pose(ctrl)
  local segs = build_timeline(self, ctrl, spec, base)
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
  local aid = self.cfg.sounds and self.cfg.sounds[effect_name]
  if aid == nil and M.SOUNDS then aid = M.SOUNDS[effect_name] end
  if aid ~= nil then self:play_audio(aid) end
end
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
function Adapter:enforce_hidden_subtrees()
  local full = self._subtree_dirty
  self._subtree_dirty = false
  self._subtree_urgent747 = false
  local pending = self._subtree_dirty_ids
  self._subtree_dirty_ids = nil
  local hid = self._hidden_ids
  if hid == nil then self._subtree_retry_at747 = nil; return end
  local targets = full and hid or pending
  if targets == nil then self._subtree_retry_at747 = nil; return end
  if full then self._hidden_enforced746 = {} end
  local done_map = self._hidden_enforced746
  if done_map == nil then done_map = {}; self._hidden_enforced746 = done_map end
  local function hide_one746(node)
    local nm = node.name
    if nm ~= nil and nm ~= "" and DECOR[nm] == true then return false, nil end
    if node.visible ~= false then node:SetVisible(false) end
    return true, node:GetChildren()
  end
  local function hide_leaf746(node)
    local nm = node.name
    if nm ~= nil and nm ~= "" and DECOR[nm] == true then return end
    if node.visible ~= false then node:SetVisible(false) end
  end
  local retry_ids = nil
  for id in pairs(targets) do
    if hid[id] then
      local c = self:find(id)
      local ok_done = false
      if c ~= nil then
        local ok_k, kids = pcall(p744_kids, c)
        if ok_k and type(kids) == "table" then
          local all_ok = true
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              local ok1, cont, kk = pcall(hide_one746, k)
              if not ok1 then
                all_ok = false
              elseif cont and type(kk) == "table" then
                for j = 1, math.min(#kk, 32) do
                  local k2 = kk[j]
                  if k2 ~= nil and k2.SetVisible then
                    if not pcall(hide_leaf746, k2) then all_ok = false end
                  end
                end
              end
            end
          end
          if all_ok then
            done_map[id] = true
            ok_done = true
          end
        end
      end
      -- 747（P1-4）：控件暂不可达、取子节点或隐藏任一子节点失败时，重新放回待办队列，0.25s 后自动重试，不丢旧页隐藏待办。
      if not ok_done then
        retry_ids = retry_ids or {}
        retry_ids[id] = true
      end
    end
  end
  if retry_ids ~= nil then
    self._subtree_dirty_ids = self._subtree_dirty_ids or {}
    for rid in pairs(retry_ids) do
      if hid[rid] then self._subtree_dirty_ids[rid] = true end
    end
    self._subtree_retry_at747 = (self.clock or 0) + 0.25
  else
    self._subtree_retry_at747 = nil
  end
end
function Adapter:_repaint_cell_overlays(cell_id)
  if cell_id == nil then return end
  if self._furn_level ~= false and self._furn_layer_state then
    for _, name in ipairs({"rug_layer", "furn"}) do
      local st = self._furn_layer_state[cell_id .. ":" .. name]
      if st then self:_prepare_furn_layer(cell_id, name, st.w, st.h, true) end
    end
  end
  local w = self._edge_want
  if w ~= nil then
    local e = w[cell_id]
    if e ~= nil then
      for name, want in pairs(e) do
        local s2 = self:sub(cell_id, name)
        if s2 ~= nil and s2.SetVisible ~= nil then
          pcall(function() s2:SetVisible(want) end)
        end
      end
    end
  end
  local o = self._obj_want
  if o ~= nil then
    local want = o[cell_id]
    if want ~= nil then
      self:_paint_obj(cell_id, nil, want, false)
    end
  end
  local pp = self._portrait_want
  if pp ~= nil then
    local want = pp[cell_id]
    if want ~= nil then
      self:_paint_portrait(cell_id, nil, want, false)
    end
  end
  local fa = self._furn_art_want
  if fa ~= nil then
    local want = fa[cell_id]
    if want ~= nil then
      self:_paint_furn_art(cell_id, nil, want, false)
    end
  end
end
function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)
  -- 745：事件驱动复位标记层（抬格/建格/重建时已即时置顶）；关内每 60 帧兜底复核一次，非关内 0 次。
  self._mark_tick745 = (self._mark_tick745 or 0) + 1
  if self._mark_layer_dirty745 or (self._mark_screen_on == true and (self._mark_tick745 % 60 == 0)) then
    self:_mark_layer_raise(true)
  end
  if self._furn_batch then self._furn_batch = false end
  if self._furn_try_pending or self._furn_dirty ~= nil then self:flush_furn_pending() end
  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
    if (self._furn_resync_at or -1) <= self.clock then
      local fs = math.min(4, (self._furn_resync_streak745 or 0) + 1)
      self._furn_resync_streak745 = fs
      self._furn_resync_at = self.clock + (fs >= 3 and 4.0 or 0.5)
      pcall(self._furn_resync, self)
    end
  end
  -- 689：定时器为空时不分配空表（688 在该分支本就什么都不做）
  if #self.timers > 0 then
    local due = {}
    for i = #self.timers, 1, -1 do
      if self.timers[i].at <= self.clock then
        due[#due + 1] = self.timers[i]
        table.remove(self.timers, i)
      end
    end
    for i = #due, 1, -1 do due[i].fn() end
  end
  if self._subtree_dirty or (self._subtree_dirty_ids ~= nil and next(self._subtree_dirty_ids) ~= nil
     and (self._subtree_urgent747 or self._subtree_retry_at747 == nil or (self.clock or 0) >= self._subtree_retry_at747)) then
    pcall(self.enforce_hidden_subtrees, self)
  end
  if self._overlay_dirty then
    self._overlay_dirty = false
    local seen = {}
    local function repaint_all(t)
      if type(t) ~= "table" then return end
      for cid in pairs(t) do
        if not seen[cid] then
          seen[cid] = true
          pcall(function() self:_repaint_cell_overlays(cid) end)
        end
      end
    end
    repaint_all(self._edge_want)
    repaint_all(self._obj_want)
  end
  if self._baked_dirty then
    self._baked_dirty = false
    pcall(function() self:_apply_baked(false) end)
  end
  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false
     and (self._furn_retry_n or 0) < 12 then
    self._furn_last_try = self._furn_last_try or -1
    if self.clock - self._furn_last_try >= 1.0 then
      self._furn_last_try = self.clock
      self._furn_retry_n = (self._furn_retry_n or 0) + 1
      pcall(function()
        self._furn_prefabs = self:_furn_prefab_map()
        self._furn_tpl_ok = (self._furn_prefabs ~= nil and next(self._furn_prefabs) ~= nil)
        self:_furn_try_all()
      end)
    end
  end
  return self.clock
end
function Adapter:state(key, value)
  if value ~= nil then
    self.state[key] = value
    return value
  end
  local v = self.state[key]
  if v == nil and script and script.GetParam then
    v = script:GetParam(key)           
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
function Adapter:save(key, value, opts)
  self.state[key] = value
  if not (type(opts) == "table" and opts.no_signal) then
    return self:signal_emit(self.signals.SAVE, self:_save_params(value))
  end
  return true
end
function Adapter:load(key)
  return self.state[key]
end
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
  local result=script:RegisterServerSignalHandler(name, function(sigName, params)
    local payload
    if schema and params then
      payload = {}
      for i = 1, #schema do payload[schema[i]] = params[i] end
    else
      payload = params or {}
    end
    handler(payload)
  end)
  return result~=false
end
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
return M

end

__M["main"] = function()
local Core      = __require("murdoku_core")
local UIC       = __require("ui_controller")
local Adapters  = __require("engine_adapter")
local Qianxing  = __require("engine_adapter_qianxing")
local Levels = __require("levels.init")
local Murdoku = {}
local settle_session = { elapsed = 0, unlocked = false }
function Murdoku.reset_settle_session()
  settle_session = { elapsed = 0, unlocked = false }
end
local SETTLE_PLAY_SECONDS751 = 90
function Murdoku.advance_settle_session(dt)
  if not settle_session.unlocked then
    -- 751(a)：进入关卡后开始 90 秒倒计时（不加弹窗/切屏等额外限制）；首页未进关前不推进计时。
    if not settle_session.entered_level then
      local cur = Murdoku.current and Murdoku.current() or nil
      local ctrl = cur and cur.controller
      if ctrl ~= nil and ctrl.screen == nil then
        settle_session.entered_level = true
      end
    end
    if settle_session.entered_level then
      settle_session.elapsed = math.min(SETTLE_PLAY_SECONDS751, settle_session.elapsed + math.max(0, tonumber(dt) or 0))
      if settle_session.elapsed >= SETTLE_PLAY_SECONDS751 then settle_session.unlocked = true end
    end
  end
end
function Murdoku.get_settle_session() return settle_session end
Murdoku.__index = Murdoku
Murdoku.VERSION = "1.0.0"
local current = nil             
local prepared_adapter = nil    

local murdoku_vis_memo = {}       
local murdoku_vis_force_to = 0    
local murdoku_vis_key = nil       
function dprint(...)
  if Murdoku.DIAG then print(...) end
end
local function snap_visible()
  local out = {}
  local rt = nil
  pcall(function() rt = current.adapter:find("root") end)
  if rt == nil then return out end
  local function walk(c, ox, oy, depth)
    if c == nil or depth > 6 then return end
    local v = nil
    pcall(function() v = c.visible end)
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
        local sx = (ox or 0) + (ax or 0)
        local sy = (oy or 0) + (ay or 0)
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
local murdoku_vis_ids = nil
local murdoku_vis_ids_key = nil
local function murdoku_build_vis_ids(scr_now, rows, cols)
  local wid_on = not (current ~= nil and current.adapter ~= nil and current.adapter.cfg ~= nil
                      and current.adapter.cfg.widgets == false)
  local ids = { "tpl-container" }
  if wid_on then
    ids[#ids + 1] = "selbar"
    for i = 1, 6 do ids[#ids + 1] = "selbtn." .. tostring(i) end
  end
  if scr_now == "level" then
    local n = tonumber(rows) or 5
    for r = 1, n do
      for c = 1, tonumber(cols) or n do ids[#ids + 1] = "cell." .. r .. "." .. c end
    end
  end
  return ids
end
local function m744_vis_get(c) return c.visible end
local function m744_vis_set(c, v) c:SetVisible(v) end
local function m745_vis_sync(c, want)
  if c.visible == want then return false end
  c:SetVisible(want)
  return true
end
local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = ad.controls and ad.controls[nm] or nil
  if c == nil then
    -- 748（B8）：稳态（非 forcing）查找 cell.* 时先 O(1) 定位 board/stage（含 stage 静态路由兜底），
    -- 主容器已就绪时直接 GetChild，仅当主容器尚不存在时才回退 ad:find，既防漏管又避免全树索引重建。
    if not forcing and type(nm) == "string" and nm:sub(1, 5) == "cell." then
      local host = (ad.controls and (ad.controls["board"] or ad.controls["stage"])) or nil
      if host == nil and ad.probe_static747 ~= nil then
        host = ad:probe_static747("stage")
        if host ~= nil and ad.controls ~= nil then ad.controls["stage"] = host end
      end
      if host ~= nil and host.GetChild ~= nil then
        local ok_g, child = pcall(host.GetChild, host, nm)
        if ok_g and child ~= nil then
          ad.controls[nm] = child
          c = child
        end
      end
      if c == nil and host ~= nil then return 0 end
    end
    if c == nil then
      local misses = ad._misses
      if misses ~= nil then
        local stamp = misses[nm]
        if stamp == false or (type(stamp) == "number" and (ad.clock or 0) < stamp) then return 0 end
      end
      local ok_f, res_f = pcall(ad.find, ad, nm)
      if ok_f then c = res_f end
    end
  end
  if c == nil then return 0 end
  -- 748（B8）：forcing（切屏 60 帧窗口）严格恢复 742v12 无视回读强写 SetVisible 语义，对抗引擎属性/渲染脱节；
  -- 稳态（forcing == false）仍走 m745_vis_sync 读回守卫，0 无效写。
  if forcing then
    if pcall(m744_vis_set, c, want) then
      memo[nm] = want
      return 1
    end
    return 0
  end
  local ok_w, did = pcall(m745_vis_sync, c, want)
  if ok_w then
    memo[nm] = want
    return did and 1 or 0
  end
  return 0
end
Murdoku.USE_GRID = true                   
Murdoku.GRID_ITEM_PREFAB = 1073742421     
local BOARD_W, BOARD_H = 584, 584
local BOARD_X, BOARD_Y = 100, 20
function Murdoku.prepare(adapter)
  prepared_adapter = adapter
  return adapter
end
function Murdoku.current() return current end
function Murdoku.render(force)
  if current == nil then return end
  current.controller:render(current.adapter, force)
end
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
  do
    local c = adapter.cfg
    if c ~= nil then
      if c.use_grid == nil then c.use_grid = Murdoku.USE_GRID end
      if c.clues_grid_prefab == nil then c.clues_grid_prefab = Murdoku.GRID_ITEM_PREFAB end
    end
  end
  local level_list = Levels.ui_list()
  local controller
  local function start_other(id, why)
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.skip_intro = true
    o.debug = opts.debug
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
  local want_screen = nil
  if opts.screen ~= nil then want_screen = opts.screen end
  controller = UIC.new(core, {
    settle_session = settle_session,
    debug = opts.debug,
    skip_intro = (opts.skip_intro ~= false),    
    on_save = function()
      adapter._manual_save=true
      local ok,saved=pcall(Murdoku.save_now)
      if not ok or not saved then
        adapter._manual_save=nil
        controller.toast='存档尚未确认，请稍后重试'
        print('[727] 手动保存未完成 '..tostring(saved))
      elseif adapter._manual_save then
        controller.toast='正在确认存档'
      end
      controller.toast_until=(controller.now or 0)+4
      controller.dirty=true
    end,
    on_settle = function() Murdoku.save_now(true) end,
    on_settle_only = function()
      Murdoku.settle_from_screen()
    end,
    on_ticket_restart = Murdoku.begin_ticket_visit,
    on_hint_saved = function() Murdoku.save_now() end,
    wallet = function() return Murdoku.wallet() end,
    trade = function(op,target) return Murdoku.trade(op,target) end,
    archive_ready = function() return adapter._archive_ready end,
    levels = level_list,
    screen = want_screen,
    push_cell_text = (adapter.cfg and adapter.cfg.cells
      and adapter.cfg.cells.push_text == true) or false,
    progress = function(lid) return Murdoku.progress_of(lid) end,
    on_result = function(kind, wrong, seconds) Murdoku.record_result(level.id, kind, wrong, seconds) end,
    last_level = function() return Murdoku.last_played() end,
    current_level = tostring(level.id),
    on_pick_level = function(id, queried)
      local a = current.adapter
      if a._archive_ready and not queried and not a._confirmed and not a._save_pending then
        controller._waiting_card = id
        controller.screen = 'select'
        controller.dirty = true
        a._archive_ready = false
        a._archive_request_at = (a._archive_clock or 0) + 2
        print('[724选关] 重新读取玩家槽 '..tostring(id))
        pcall(a.signal_emit, a, 'murdoku/load', {})
        return
      end
      if not current.adapter._archive_ready then
        controller._waiting_card = id
        controller.screen = 'select'
        controller.toast = '正在读取玩家存档…'
        controller.toast_until = controller.now + 2
        controller.dirty = true
        return
      end
      if Murdoku.resume_selected(id) then return end
      Murdoku.remember_level(id)
      if id ~= level.id then
        start_other(id)
        if controller ~= nil then controller.screen = nil end
      else
        if controller._continue_requested then Murdoku.begin_ticket_visit() else controller:do_restart() end
        controller.screen = nil
        controller.modal = nil
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_back = function()
      -- 654: 退出至独立选关页，不能重新打开旧式选关弹窗。
      controller.screen = "select"
      controller.modal = nil
      controller.pending = nil
      controller:sync_confirm()
      controller.dirty = true
      Murdoku.flush_effects()
    end,
    on_next_level = opts.on_next_level or function()
      local nxt = Levels.next(level.id)
      if nxt then
        if Murdoku.resume_selected(nxt) then return end
        start_other(nxt)
      else
        controller.toast = "已经是最后一关了"
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_solved = function(vm)
      pcall(adapter.signal_emit, adapter, Qianxing.SIGNALS.SOLVED, {
        tostring(level.id),
        math.floor(vm.hud.time or 0),
        0,
        vm.hud.failed_accusations or 0,
      })
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
  Murdoku.__last = self
  adapter._clue_owner = controller
  adapter.on_input = function(event)
    controller:on_input(event)
    Murdoku.flush_effects()
  end
  local function subscribe(name,handler)
    adapter._signal_done=adapter._signal_done or {}
    if adapter._signal_done[name] then return end
    local ok,result=pcall(adapter.signal_on,adapter,name,handler)
    if ok and result~=false then adapter._signal_done[name]=true end
  end
  self.retry_signals=function()
    subscribe(Qianxing.SIGNALS.RESTORE,Murdoku.restore)
    subscribe(Qianxing.SIGNALS.SYNC_STATE,function(payload) Murdoku.on_signal(Qianxing.SIGNALS.SYNC_STATE,payload) end)
  end
  self.retry_signals()
  if opts.restore_save then
    local save = adapter:load("murdoku/save/" .. tostring(level.id))
    if type(save) == "table" then
      core:restore_save(save)
    end
  end
  if current and current.controller then current.controller:_clear_verdict() end
  if adapter.clear_verdict_rings then adapter:clear_verdict_rings() end
  if not current or current.level.id~=level.id then
    adapter._furn_want=nil
    adapter._furn_art_want=nil
    adapter._furn_dirty=nil
    adapter._furn_try_pending=false
    adapter._furn_batch_log_key=nil
  end
  current = self
  if not controller.screen then Murdoku.begin_ticket_visit() end
  if adapter.enable_cursor then
    local cur = adapter:enable_cursor()
    if cur > 0 and print then
      print("[murdoku] 已由脚本打开 " .. cur .. " 个容器的「显示常驻光标」")
    end
  end
  do
    local root = nil
    pcall(function() root = adapter:find("root") end)
    local s = nil
    if root ~= nil then pcall(function() s = root:GetChild("stage") end) end
    local s2 = nil
    do
      local root2 = nil
      pcall(function() root2 = adapter:find("root") end)
      if root2 ~= nil then pcall(function() s2 = root2:GetChild("stage") end) end
    end
    if print and s2 ~= nil then
      local ew, eh = nil, nil
      pcall(function() ew, eh = s2:GetSizeDelta() end)
      print("[murdoku] ★ 几何归编辑器：stage **回读** " .. tostring(ew) .. "x" .. tostring(eh)
        .. "（★ 这才是实际生效的尺寸 ✓ 脚本常量 BOARD_W/H=" .. tostring(BOARD_W) .. "x" .. tostring(BOARD_H) .. " 不参与）")
    end
  end
  do
    local n_levels = 8
    if Levels ~= nil and type(Levels.all) == "function" then
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    print("[murdoku] ensure_widgets 存在性：type=" .. type(adapter.ensure_widgets)
      .. "，n_levels=" .. tostring(n_levels))
    if adapter.ensure_widgets and not (adapter.cfg and adapter.cfg.widgets == false) then
      local made, err, existed = adapter:ensure_widgets(n_levels)
      print("[murdoku] 选关按钮（脚本创建）：新建 " .. tostring(made)
        .. " 个，已存在 " .. tostring(existed or 0) .. " 个"
        .. (err and ("　⚠️ " .. tostring(err)) or ""))
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
  if adapter.ensure_cells then
    local made = adapter:ensure_cells(core.rows, core.cols)
    if made > 0 and print then
      print("[murdoku] 运行时生成了 " .. made .. " 个格子")
    end
  end
  local labels = {}
  do
    local ok, nodes = pcall(function() return controller:build_layout() end)
    if ok and type(nodes) == "table" then
      local list = {}
      for i = 1, #nodes do
        local nd = nodes[i]
        local id = nd.id
        if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") and not id:match("^home%.") then
          list[#list + 1] = id
        end
      end
      adapter.cfg.btn_list = list
      if print then print("[murdoku] 上色名单（来自规划）：" .. #list .. " 个按钮") end
      pcall(function() if adapter.apply_btn_art then adapter:apply_btn_art() end end)
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
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
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
  if adapter.diagnose_overlap and adapter.cfg.overlap_diag ~= false then
    adapter:diagnose_overlap()
  end
  Murdoku.render(true)
  if adapter.seal_containers ~= nil then
    local sealed = 0
    if adapter.seal_cursor_shield ~= nil then
    end
    if print then
      print(string.format("[murdoku] 2D/3D 输入隔离：主页/选关容器已屏蔽穿透 %d 个", sealed))
      print("[murdoku]   验收：在关卡里按任一键盘快捷键 —— 出现「✅ 键盘事件仍能收到」"
        .. "即说明隔离没有副作用；若没有，去掉 main.lua 里的 seal_containers 即可（一行）。")
    end
  end
  if adapter.diagnose_grid ~= nil and adapter.cfg and adapter.cfg.diagnose_grid ~= false then
    local rows = adapter.cells_rows or (adapter.cfg.cells and adapter.cfg.cells.rows) or 5
    local cols = adapter.cells_cols or (adapter.cfg.cells and adapter.cfg.cells.cols) or 5
  if Murdoku.DIAG then pcall(function() adapter:diagnose_grid(rows, cols) end) end    
  end
  adapter:signal_emit(Qianxing.SIGNALS.READY, {
    tostring(level.id), core.rows, core.cols, core:piece_count(),
  })
  return self
end
function Murdoku.on_start(level_id, opts)
  local adapter = (opts and opts.adapter) or prepared_adapter
  if adapter then
    local ready = false
    pcall(function()
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
  local a=current.adapter
  a._archive_clock=(a._archive_clock or 0)+math.max(0,tonumber(dt) or 0)
  Murdoku.poll_save(a)
  if not a._archive_ready then
    if a._signal_done and a._signal_done[Qianxing.SIGNALS.RESTORE] and
       a._archive_clock >= (a._archive_request_at or 0) then
      a._archive_request_at=a._archive_clock+2
      pcall(a.signal_emit,a,"murdoku/load",{})
    end
  elseif current.controller.screen==nil and a._archive_clock >= (a._archive_save_at or 0) then
    a._archive_save_at=a._archive_clock+3
    if not a._settle_after and not a._settle_sent then
      local ok,err=pcall(Murdoku.save_now,false,false,true)
      if not ok then print('[727] 自动保存失败 '..tostring(err)) end
    end
  end
  if (not Murdoku._exit_art_done) and current.adapter ~= nil then
    Murdoku._exit_art_done = true
    for _, _bid in ipairs({
      "modal.exit", "modal.save", "modal.settle", "modal.cancel",
    }) do
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
  current.adapter:on_tick(dt)
  current.controller:tick(dt)
  if current.adapter.enable_cursor and ((current.frames or 0) % 20 == 0) then
    local before = Murdoku._cursor_ok or 0
    local n = current.adapter:enable_cursor()
    Murdoku._cursor_ok = n
    if n ~= before and print then
      print("[murdoku] 门控②重试：已打开 " .. tostring(n) .. " 个容器的「显示常驻光标」")
    end
  end
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
  local sec = math.floor(current.core.elapsed or 0)
  local need_sec_render = false
  if sec ~= current.last_tick then
    if current.controller.screen == nil then
      need_sec_render = true
    elseif current.controller._pending_retry744 == true then
      -- 746（P2-3）：非关内仅在写失败项或缺失项到达其 adapter._misses 探测期限时才探活；
      -- 若仅因控件缺失且探测仍未找到，则不触发整页 build_layout / render()。
      local pids = current.controller._pending_retry_ids746
      local ad_r = current.adapter
      if pids == nil or ad_r == nil then
        need_sec_render = true
      else
        local miss_tbl = ad_r._misses
        local clk = ad_r.clock or 0
        for id, kind in pairs(pids) do
          if kind == "write" then
            need_sec_render = true
            break
          else
            local stamp = miss_tbl and miss_tbl[id]
            if ad_r.controls[id] ~= nil then
              need_sec_render = true
              break
            elseif ad_r.has_static_route747 ~= nil and ad_r:has_static_route747(id) then
              -- 747：静态路径控件（如 econ.shop736.*）用 O(1) path_lookup 每 2.0s 轻量探活（0 次 GetChildren、0 次 build_layout），
              -- 挂回后等待时间从 13.6s 压缩至 <= 2.0s。
              local ptab = current.controller._static_probe_at747
              if ptab == nil then ptab = {}; current.controller._static_probe_at747 = ptab end
              local next_at = ptab[id] or 0
              if clk >= next_at then
                ptab[id] = clk + 1.9
                local ok_s, found_s = pcall(ad_r.probe_static747, ad_r, id)
                if ok_s and found_s ~= nil then
                  ad_r.controls[id] = found_s
                  if miss_tbl ~= nil then miss_tbl[id] = nil end
                  if ad_r._miss_streak ~= nil then ad_r._miss_streak[id] = nil end
                  ptab[id] = nil
                  need_sec_render = true
                  break
                end
              end
            elseif stamp == nil or (stamp ~= false and clk >= stamp) then
              local ok_p, found_p = pcall(ad_r.find, ad_r, id)
              if ok_p and found_p ~= nil then
                need_sec_render = true
                break
              end
            end
          end
        end
      end
      if not need_sec_render then current.last_tick = sec end
    end
  end
  if need_sec_render or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end
  Murdoku.DIAG = Murdoku.DIAG or false       
  local scr_now = current.controller and current.controller.screen or "level"
  if Murdoku.DIAG
     and ((current.frames or 0) >= 90 or scr_now ~= Murdoku._last_screen)
     and scr_now ~= Murdoku._dump_done_for then
    Murdoku._dump_done_for = scr_now
    local ad = current.adapter
    print("[murdoku] ===== 开局诊断：屏幕上到底有什么（第 90 帧实测）=====")
    print("[murdoku]   controller.screen = " .. tostring(current.controller.screen))
    local ids = {
      "root", "home", "home.title", "home.select", "home.continue", "home.shop", "home.bag",
      "selbar", "selbtn.1", "tpl-container",
      "stage", "board.bg", "cell.1.1",
      "topbar", "toolbar", "right",
      "clues", "clues.bg", "clues.grid",
      "hud.title", "hud.timer", "hud.progress",
    }
    for i = 1, #ids do
      local id = ids[i]
      local c = nil
      pcall(function() c = ad:find(id) end)
      if c == nil then
        print("[murdoku]   " .. id .. "  → **找不到控件**（名字对不上 / .gil 里没有）")
      else
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
        if area > 20000 then
          list[#list + 1] = { id = nm, w = w or 0, h = h or 0, area = area,
                              vis = tostring(v), act = tostring(al) }
        end
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
    print("[murdoku] ===== 诊断二：父级链 + 透明度 + 手动显形 =====")
    local leaf = nil
    pcall(function() leaf = ad:find("home.select") end)
    if leaf == nil then
      print("[murdoku]   home.select 找不到，跳过")
    else
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
      local al, sc = "?", "?"
      pcall(function() al = tostring(leaf.alpha) end)
      pcall(function() sc = tostring(leaf.scale) end)
      print("[murdoku]   home.select alpha=" .. al .. " scale=" .. sc)
      local okv, oka = true, true    
      local v2, a2 = "?", "?"
      pcall(function() v2 = tostring(leaf.visible) end)
      pcall(function() a2 = tostring(leaf.active) end)
      print("[murdoku]   手动 SetVisible=" .. tostring(okv) .. " SetActive=" .. tostring(oka)
        .. "  ⇒ 回读 visible=" .. v2 .. " active=" .. a2)
      local hm = nil
      pcall(function() hm = ad:find("home") end)
      if hm ~= nil then
        print("[murdoku]   已对 home 容器也调了一次 SetVisible/SetActive")
      end
    end
    print("[murdoku] ===== 诊断二结束 =====")
  end
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
  do
    local n_levels = Murdoku._n_levels745
    if n_levels == nil then
      n_levels = 8
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
      Murdoku._n_levels745 = n_levels
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
    do
      local ad0 = current.adapter
      local s = ad0.controls and ad0.controls["stage"] or nil
      if s == nil then
        local ok_s, res_s = pcall(ad0.find, ad0, "stage")
        if ok_s then s = res_s end
      end
      if s ~= nil then
        local ok_sv, sv = pcall(m744_vis_get, s)
        if not ok_sv or sv ~= true then pcall(m744_vis_set, s, true) end
        if print and current._stage_rb_logged ~= true then
          current._stage_rb_logged = true
          local sw0, sh0 = nil, nil
          pcall(function() sw0, sh0 = s:GetSizeDelta() end)
          print("[murdoku] ★ 棋盘容器 stage 回读 " .. tostring(sw0) .. "x" .. tostring(sh0)
            .. "（★ 归编辑器 ✓ 脚本不再写它 ✓）")
        end
      end
      local bar = nil
      if on_select then
        local ok_b, res_b = pcall(ad0.find, ad0, "selbar")
        if ok_b then bar = res_b end
      end
      if bar ~= nil and on_select then
        pcall(function() bar:SetAnchoredPosition(0, 0) end)
        pcall(function() bar:SetSizeDelta(1500, 700) end)
      end
    end
    do
      local STAGE_BG_ID   = 106053
      local STAGE_BG_TINT = 0xFF2C2820    
      local STAGE_BG_FALLBACK_ID = 107003
      local in_level = (scr_now == "level")
      local ad1 = current.adapter
      local s = ad1.controls and ad1.controls["stage"] or nil
      if s == nil then
        local ok_s1, res_s1 = pcall(ad1.find, ad1, "stage")
        if ok_s1 then s = res_s1 end
      end
      if s ~= nil and not in_level then
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
        local bg = (current.adapter.controls and current.adapter.controls["board.bg"]) or nil
        if bg == nil then
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
              pcall(function() ob:SetSizeDelta(614, 626) end)
              pcall(function() ob:SetAnchoredPosition(0, 2) end)
              local layered = {}
              if ob.SetSiblingIndex ~= nil then
                if pcall(function() ob:SetSiblingIndex(0) end) then layered[#layered + 1] = "SetSiblingIndex(0)" end
              end
              if ob.SetAsFirstSibling ~= nil then
                if pcall(function() ob:SetAsFirstSibling() end) then layered[#layered + 1] = "SetAsFirstSibling()" end
              end
              if #layered == 0 then layered[#layered + 1] = "没排（两个 API 都没有）" end
              local sib = "?"
              pcall(function() sib = tostring(ob:GetSiblingIndex()) end)
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
          current._board_bg_vis = nil
        end
        if bg ~= nil then
          local want = true
          if current._board_bg_vis ~= want then
            pcall(function() bg:SetVisible(want) end)
            current._board_bg_vis = want
          end
        end
      end
    end
    for i = 1, (on_select and n_levels or 0) do
      local c = nil
      pcall(function() c = current.adapter:find("selbtn." .. tostring(i)) end)
      if c ~= nil then
        if on_select then
          local x = (i - (n_levels + 1) / 2) * 200
          pcall(function() c:SetAnchoredPosition(x, 120) end)
          pcall(function() c:SetSizeDelta(160, 160) end)
        end
      end
    end
  end
  do
    if not Murdoku._settle_probe_done then
      Murdoku._settle_probe_done = true
      local sb0 = nil
      pcall(function() sb0 = current.adapter:find("settle.btn") end)
      if sb0 ~= nil and print then
        local rw, rh, rx, ry, rvis, rray = "?", "?", "?", "?", "?", "?"
        pcall(function() rw, rh = sb0:GetSizeDelta() end)
        pcall(function() rx, ry = sb0:GetAnchoredPosition() end)
        pcall(function() rvis = tostring(sb0.visible) end)
        pcall(function() rray = tostring(sb0.raycastTarget) end)
        print("[murdoku] ★ 结算按钮（归编辑器 ✓ 脚本一个字都不写）：回读 size=("
          .. tostring(rw) .. "," .. tostring(rh) .. ") pos=(" .. tostring(rx) .. "," .. tostring(ry)
          .. ") visible=" .. rvis .. " raycastTarget=" .. rray)
      end
    end
  end
  if murdoku_vis_memo == nil then murdoku_vis_memo = {} end
  do
    local lev0 = current.level
    local lid0 = (lev0 ~= nil) and (lev0.id or lev0.key or lev0.name) or nil
    local r0 = (current.adapter ~= nil) and current.adapter.cells_rows or nil
    local c0 = current.adapter and current.adapter.cells_cols
    local ids_key = tostring(c0) .. "|" .. tostring(scr_now) .. "|" .. tostring(lid0) .. "|" .. tostring(r0)
    if ids_key ~= murdoku_vis_ids_key or murdoku_vis_ids == nil then
      murdoku_vis_ids_key = ids_key
      murdoku_vis_ids = murdoku_build_vis_ids(scr_now, r0, c0)
    end
  end
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
      local vis_ids = murdoku_vis_ids
      -- 745：换屏窗口内每帧检查，稳态后每 30 帧兜底复核一次，消除每帧 32 次冗余遍历。
      if vis_ids ~= nil and (forcing or (fnow % 30 == 0)) then
        for i = 1, #vis_ids do
          local nm = vis_ids[i]
          local want
          if nm == "tpl-container" then
            want = false
          elseif nm:sub(1, 5) == "cell." then
            want = true
          else
            want = in_select
          end
          wrote = wrote + murdoku_set_vis(ad_vis, nm, want, forcing, murdoku_vis_memo)
        end
      end
      current._vis_wrote = wrote
      current._vis_forcing = forcing
      current._vis_frames = fnow
      current._vis_until = murdoku_vis_force_to
      current._vis_keynow = murdoku_vis_key
    end
  end
    if scr_now == "level" then
      local f745 = current.frames or 0
      local ad745 = current.adapter
      local gen745 = (ad745 and ad745._lookup_gen) or 0
      local fc745 = current._face_cache745
      if fc745 == nil or fc745.gen ~= gen745 then
        fc745 = { gen = gen745, stable = 0, cells = {} }
        current._face_cache745 = fc745
      end
      -- 746+747（P1-1 & P2-3）：已齐全（box/face/x 三者均就绪）格子保持 120 帧稳态巡检零重枚举；
      -- 任一格子缺少 box、face 或 x 时，仅对该缺项格子按退避周期（前 2 次 30 帧，之后 60 帧，常驻 120 帧）重查，绝不封死晚挂控件恢复。
      local step745 = (fc745.stable >= 2) and 120 or 30
      local due_incomplete746 = (fc745.has_incomplete == true) and ((f745 % 60) == 0)
      if (f745 % step745) == 0 or due_incomplete746 then
        local full_pass746 = ((f745 % step745) == 0)
        local rows, cols = 5, 5
        if ad745 ~= nil then
          rows = ad745.cells_rows or (ad745.cfg and ad745.cfg.cells and ad745.cfg.cells.rows) or rows
          cols = ad745.cells_cols or (ad745.cfg and ad745.cfg.cells and ad745.cfg.cells.cols) or cols
        end
        local function read_xy745(obj, method)
          local a, b = obj[method](obj)
          if type(a) == "table" then return a.x, a.y end
          return a, b
        end
        local function fit_box745(obj, want_vis, tw, th)
          local fixed = false
          if want_vis and obj.visible ~= true then obj:SetVisible(true); fixed = true end
          local gw, gh = read_xy745(obj, "GetSizeDelta")
          if gw ~= tw or gh ~= th then obj:SetSizeDelta(tw, th); fixed = true end
          local gx, gy = read_xy745(obj, "GetAnchoredPosition")
          if gx ~= 0 or gy ~= 0 then obj:SetAnchoredPosition(0, 0); fixed = true end
          return fixed
        end
        local function sync_cell745(rec)
          local cell = rec.cell
          local cw, ch = read_xy745(cell, "GetSizeDelta")
          cw, ch = cw or 124, ch or 124
          local fixed = false
          if rec.box ~= nil then
            local _ = rec.box.name
            if fit_box745(rec.box, true, cw, ch) then fixed = true end
          end
          if rec.face ~= nil then
            local _ = rec.face.name
            if fit_box745(rec.face, true, cw, ch) then fixed = true end
          end
          if rec.x ~= nil then
            local _ = rec.x.name
            if fit_box745(rec.x, false, cw * 0.7, ch * 0.7) then fixed = true end
          end
          return rec.face ~= nil, fixed
        end
        local function scan_cell_kids746(cell, rec)
          local kids = cell.GetChildren and cell:GetChildren() or nil
          if type(kids) == "table" then
            for _, k in ipairs(kids) do
              local kn = tostring(k.name)
              if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                rec.box = k
              elseif kn == "face" then
                rec.face = k
              elseif kn == "x" then
                rec.x = k
              end
              if (rec.face == nil or rec.x == nil) and k.GetChildren ~= nil then
                local kk = k:GetChildren()
                if type(kk) == "table" then
                  for _, c2 in ipairs(kk) do
                    local cn = tostring(c2.name)
                    if cn == "face" then rec.face = c2
                    elseif cn == "x" then rec.x = c2 end
                  end
                end
              end
            end
          end
        end
        local n, any_fixed, all_ready, any_incomplete = 0, false, true, false
        for r = 1, rows do
          for c = 1, cols do
            local cid = "cell." .. r .. "." .. c
            local rec = fc745.cells[cid]
            local rec_complete = (rec ~= nil and rec.box ~= nil and rec.face ~= nil and rec.x ~= nil)
            if full_pass746 or not rec_complete then
              local cell = ad745 and ad745.controls and ad745.controls[cid] or nil
              if cell == nil and ad745 ~= nil then
                -- 747（Perf-2 配套）：格子巡检优先 O(1) 查 board/stage 直接子节点，避免缺格反复触发全树索引重建。
                local host747 = ad745.controls and (ad745.controls["board"] or ad745.controls["stage"]) or nil
                if host747 ~= nil and host747.GetChild ~= nil then
                  local ok_c, ch_c = pcall(host747.GetChild, host747, cid)
                  if ok_c and ch_c ~= nil then
                    ad745.controls[cid] = ch_c
                    cell = ch_c
                  end
                end
                if cell == nil and fc745.stable == 0 then
                  local ok_f, res_f = pcall(ad745.find, ad745, cid)
                  if ok_f then cell = res_f end
                end
              end
              if cell ~= nil then
                local need_scan = (rec == nil or rec.cell ~= cell)
                if not need_scan and not rec_complete then
                  local next_f = rec.next_probe746 or 0
                  if f745 >= next_f then need_scan = true end
                end
                if need_scan then
                  local probes = (rec ~= nil and rec.cell == cell) and ((rec.probe746 or 0) + 1) or 1
                  rec = { cell = cell, probe746 = probes }
                  pcall(scan_cell_kids746, cell, rec)
                  local got_all = (rec.box ~= nil and rec.face ~= nil and rec.x ~= nil)
                  if not got_all then
                    -- 前 2 次间隔 30 帧，3~6 次间隔 60 帧，之后保持 120 帧低频复查，绝不永久放弃晚挂子控件。
                    local gap = (probes <= 2) and 30 or ((probes <= 6) and 60 or 120)
                    rec.next_probe746 = f745 + gap
                  else
                    rec.next_probe746 = nil
                  end
                  fc745.cells[cid] = rec
                  rec_complete = got_all
                end
                if not rec_complete then any_incomplete = true end
                local ok_s, has_face, did_fix = pcall(sync_cell745, rec)
                if not ok_s then
                  fc745.cells[cid] = nil
                  all_ready = false
                  any_incomplete = true
                else
                  if has_face then n = n + 1 end
                  if did_fix then any_fixed = true end
                end
              else
                all_ready = false
                any_incomplete = true
              end
            else
              if rec.face ~= nil then n = n + 1 end
            end
          end
        end
        fc745.has_incomplete = any_incomplete
        if full_pass746 then
          if all_ready and not any_fixed then
            fc745.stable = math.min(4, fc745.stable + 1)
          else
            fc745.stable = 0
          end
        elseif any_fixed then
          fc745.stable = 0
        end
        if n > 0 and current._face_on ~= n then
          current._face_on = n
          if print then
            print("[murdoku] 格子底图已点亮：" .. tostring(n) .. " 个 face（每帧保持）")
          end
        end
      end
    end
  Murdoku._last_screen = scr_now
  current.frames = (current.frames or 0) + 1
end
function Murdoku.on_destroy()
  if not current then return end
  current.controller:_clear_verdict()
  if current.controller.screen==nil then Murdoku.save_now() end
  current = nil
end
Murdoku.on_ready = Murdoku.on_start
Murdoku.on_tick = Murdoku.on_update
function Murdoku.flush_effects()
  if not current then return end
  if current.controller.dirty then
    Murdoku.render()
  end
  if current.adapter.report_missing ~= nil then
    pcall(function() current.adapter:report_missing() end)
  end
end
function Murdoku.on_input(event)
  if not current then return end
  current.controller:on_input(event)
  Murdoku.flush_effects()
end
function Murdoku.on_signal(name, payload)
  if not current then return end
  local S = Qianxing.SIGNALS
  if name == S.RESTORE then
    Murdoku.restore(payload)
  elseif name == S.SYNC_STATE then
    if payload and payload.who and payload.r and payload.c then
      current.core:select_suspect(payload.who)
      local ok_sync, why_sync = current.core:tap_cell(payload.r, payload.c)
      if (not ok_sync) and current.controller ~= nil
        and current.controller._refuse ~= nil then
        pcall(function()
          current.controller:_refuse(payload.r, payload.c, why_sync)
        end)
      end
      Murdoku.render()
    end
  elseif name == "murdoku/next_level" then
    local nxt = Levels.next(current.level.id)
    if nxt then Murdoku.start(nxt, current.options) end
  end
end
-- v723: parse completely into a fresh Core before switching the live session.
Murdoku.tutorial_seen = {}
local tutorial_bits = {home=1,l1=2,l2=4}
local function tutorial_mask()
  local mask=0
  for tag,bit in pairs(tutorial_bits) do if Murdoku.tutorial_seen[tag] then mask=mask+bit end end
  return mask
end
local function merge_tutorial(mask)
  for tag,bit in pairs(tutorial_bits) do
    if math.floor(mask/bit)%2==1 then Murdoku.tutorial_seen[tag]=true end
  end
end
function Murdoku.record_tutorial(tag)
  if not tutorial_bits[tag] or Murdoku.tutorial_seen[tag] then return end
  Murdoku.tutorial_seen[tag]=true
  if not current then return end
  local a=current.adapter
  if not a._archive_ready or a._settle_after then return end
  Murdoku.save_now(false,current.controller.screen~=nil)
end
local ARCHIVE_VERSION = "M740"
local LEGACY_PRICE=6
local function case_bit(id)
  local n=tonumber(tostring(id):match('^case_00([1-7])$'))
  return n and 2^(n-1)
end
local function claim(e,id,outcome)
  local bit=case_bit(id)
  if not bit or (outcome~='success' and outcome~='perfect') then return end
  local ordinary=e.ordinary or 0
  if math.floor(e.mask/bit)%2==0 then
    e.mask=e.mask+bit
    if outcome=='success' then e.ordinary=ordinary+bit end
  elseif outcome=='perfect' and math.floor(ordinary/bit)%2==1 then
    e.ordinary=ordinary-bit
  end
end
local function funds(e)
  local earned=0
  for i=0,6 do earned=earned+10*(math.floor(e.mask/2^i)%2)-5*(math.floor((e.ordinary or 0)/2^i)%2) end
  return earned-e.old_clues*LEGACY_PRICE-(e.bought-e.old_clues)*SHOP_PRICE.clue-e.pos_bought*SHOP_PRICE.position,e.bought-e.used,e.pos_bought-e.pos_used
end
local function purse(archive)
  if not archive.econ then
    archive.econ={old_clues=0,mask=0,bought=0,used=0,pos_bought=0,pos_used=0,last='-',pos_last='-'}
    for id,r in pairs(archive.records) do if r.solved then claim(archive.econ,id,'perfect') end end
  end
  return archive.econ
end
local function checkpoint_code(session)
  local core=session.core
  local formal,marks={},{}
  for _,p in ipairs(core.pieces) do
    if core.placed and core.placed[p.id] then formal[#formal+1]=core:symbol_of(p.id) end
  end
  for i=1,#(session.level.clues or {}) do
    if session.controller._false_clues and session.controller._false_clues[i] then marks[#marks+1]=tostring(i) end
  end
  local accused=""
  if core.accused then accused=core:symbol_of(core.accused) end
  local hints=core.hint635_used or {position=0,clue=0}
  return table.concat({"M723",core:encode_state(),table.concat(formal),table.concat(marks,","),
    tostring((core._saved_moves or 0)+#(core.history or {})),tostring(core.failed_accusations or 0),accused, string.format("H%d%d",hints.position,hints.clue)},"|")
end
local function split_archive(code)
  local out={}
  for part in (tostring(code).."~"):gmatch("(.-)~") do out[#out+1]=part end
  return out
end
local function archive_decode(payload)
  if type(payload)~="table" or type(payload.state_code)~="string" then return nil,"存档格式无效" end
  local code=payload.state_code
  local legacy_mask=tonumber(code:match('|T([0-7])$')) or 0
  if code:sub(1,4)=="M723" then
    return {version="M723",mask=legacy_mask,records={[
      tostring(payload.level_id)]={level_id=tostring(payload.level_id),solved=payload.solved==true,
        elapsed=tonumber(payload.elapsed) or 0,moves=tonumber(payload.moves) or 0,failed=0,
        outcome=payload.solved and "success" or "",wrong=0,seconds=tonumber(payload.elapsed) or 0,
        checkpoint=code:gsub('|T[0-7]$','')}}}
  end
  local parts=split_archive(code)
  if parts[1]~=ARCHIVE_VERSION and parts[1]~="M735" and parts[1]~="M734" and parts[1]~="M730" and parts[1]~="M725" and parts[1]~="M724" then return nil,"存档版本无效" end
  local mask=tostring(parts[2] or ""):match('^T([0-7])$')
  if not mask then return nil,"存档教程标记无效" end
  local records={}
  local first=parts[1]=='M724' and 3 or 4
  local econ
  if parts[1]==ARCHIVE_VERSION or parts[1]=='M735' or parts[1]=='M734' or parts[1]=='M730' then
    local mask,bought,used,last,pb,pu,pl,old_clues
    local ordinary=0
    if parts[1]=='M730' then
      mask,bought,used,last=tostring(parts[4]):match('^E(%d+),(%d+),(%d+),([%w_:%-]+)$')
      pb,pu,pl='0','0','-'
    elseif parts[1]==ARCHIVE_VERSION then
      local field=tostring(parts[4])
      if field:sub(-1)=='P' then field=field:sub(1,-2) end
      ordinary=tonumber(field:match('N(%d+)$')) or 0
      field=field:gsub('N%d+$','')
      mask,bought,used,last,pb,pu,pl,old_clues=field:match('^E(%d+),(%d+),(%d+),([%w_:%-]+),(%d+),(%d+),([%w_:%-]+),(%d+)$')
    else
      mask,bought,used,last,pb,pu,pl=tostring(parts[4]):match('^E(%d+),(%d+),(%d+),([%w_:%-]+),(%d+),(%d+),([%w_:%-]+)$')
    end
    econ={ordinary=ordinary,pos_first=parts[1]==ARCHIVE_VERSION and tostring(parts[4]):sub(-1)=='P',old_clues=tonumber(old_clues or bought),mask=tonumber(mask),bought=tonumber(bought),used=tonumber(used),last=last,pos_bought=tonumber(pb),pos_used=tonumber(pu),pos_last=pl}
    if ordinary>127 then return nil,'经济记录无效' end
    for i=0,6 do if mask and math.floor(ordinary/2^i)%2>math.floor(econ.mask/2^i)%2 then return nil,'经济记录无效' end end
    if not mask or econ.mask>127 or econ.old_clues>econ.bought or econ.bought+econ.pos_bought>23 or econ.used>econ.bought or econ.pos_used>econ.pos_bought or funds(econ)<0 or
      (econ.used==0 and last~='-') or (econ.used>0 and not last:match('^case_00[1-7]:[gn]:%d+:[01]$')) or
      (econ.pos_used==0 and pl~='-') or (econ.pos_used>0 and not pl:match('^case_00[1-7]:[%w_]+:%d+:%d+$')) then return nil,'经济记录无效' end
    first=5
  end
  for i=first,#parts do
    local id,solved,elapsed,moves,failed,outcome,wrong,seconds,checkpoint=parts[i]:match('^([^%^]+)%^([01])%^(%d+)%^(%d+)%^(%d+)%^([^%^]*)%^(%d*)%^(%d*)%^(.*)$')
    if id==nil then
      id,solved,elapsed,moves,failed,checkpoint=parts[i]:match('^([^%^]+)%^([01])%^(%d+)%^(%d+)%^(%d+)%^(.+)$')
      outcome,wrong,seconds="",0,elapsed
    end
    if id==nil or checkpoint==nil or checkpoint=="" then return nil,"多关存档记录无效" end
    if records[id]~=nil then return nil,"多关存档重复关卡" end
    records[id]={level_id=id,solved=solved=="1",elapsed=tonumber(elapsed),moves=tonumber(moves),failed=tonumber(failed),outcome=outcome or "",wrong=tonumber(wrong) or 0,seconds=tonumber(seconds) or tonumber(elapsed) or 0,checkpoint=checkpoint}
  end
  return {version=ARCHIVE_VERSION,mask=tonumber(mask),recent=parts[1]~="M724" and parts[3] or payload.level_id,records=records,econ=econ}
end
local function archive_encode(archive)
  local ids={}
  for id in pairs(archive.records or {}) do ids[#ids+1]=id end
  table.sort(ids)
  local out={ARCHIVE_VERSION,"T"..tostring(math.max(0,math.min(7,tonumber(archive.mask) or 0))), archive.recent or "@tutorial"}
  local e=purse(archive)
  out[#out+1]=string.format('E%d,%d,%d,%s,%d,%d,%s,%d',e.mask,e.bought,e.used,e.last,e.pos_bought,e.pos_used,e.pos_last,e.old_clues)..((e.ordinary or 0)>0 and ('N'..string.format('%d',e.ordinary)) or '')..(e.pos_first and 'P' or '')
  for _,id in ipairs(ids) do
    local r=archive.records[id]
    out[#out+1]=table.concat({tostring(r.level_id),r.solved and "1" or "0",tostring(math.max(0,math.floor(r.elapsed or 0))),
      tostring(math.max(0,math.floor(r.moves or 0))),tostring(math.max(0,math.floor(r.failed or 0))),tostring(r.outcome or ""),
      tostring(math.max(0,math.floor(r.wrong or 0))),tostring(math.max(0,math.floor(r.seconds or r.elapsed or 0))),tostring(r.checkpoint)},"^")
  end
  return table.concat(out,"~")
end
local function archive_record_payload(payload,id)
  local archive,err=archive_decode(payload)
  if not archive then return nil,err end
  local r=archive.records[tostring(id)]
  if not r then return nil,"没有该关卡存档" end
  return {level_id=r.level_id,state_code=r.checkpoint.."|T"..tostring(archive.mask),moves=r.moves,
    elapsed=r.elapsed,solved=r.solved,archive_outcome=r.outcome,archive_wrong=r.wrong,archive_seconds=r.seconds},archive,r
end
local function checkpoint_parse(payload,level)
  if type(payload.state_code)~="string" or #payload.state_code>1800 or
     type(payload.elapsed)~="number" or payload.elapsed<0 or payload.elapsed%1~=0 or payload.elapsed>2147483647 or
     type(payload.solved)~="boolean" then return nil,"存档格式无效" end
  local bare=payload.state_code:gsub('|T[0-7]$','')
  local parts={}
  for p in (bare.."|"):gmatch("(.-)|") do parts[#parts+1]=p end
  if (#parts~=7 and #parts~=8) or parts[1]~="M723" then return nil,"存档版本无效" end
  local core=Core.new(level)
  if not core then return nil,"关卡无效" end
  local moves,failed=tonumber(parts[5]),tonumber(parts[6])
  if not moves or moves<0 or moves%1~=0 or moves>2147483647 or not failed or failed<0 or failed%1~=0 or failed>2147483647 then return nil,"计数无效" end
  local ok,err=core:decode_state(parts[2]);if not ok then return nil,err end
  local ids={};for _,p in ipairs(core.pieces) do ids[core:symbol_of(p.id)]=p.id end
  core.placed={}
  for i=1,#parts[3] do
    local id=ids[parts[3]:sub(i,i)]
    if not id or not core.pos[id] or core.placed[id] then return nil,"落子状态无效" end
    core.placed[id]=true
  end
  local marks={}
  if parts[4]~="" then
    for token in (parts[4]..","):gmatch("(.-),") do
      local n=tonumber(token)
      if not n or n%1~=0 or n<1 or n>#(level.clues or {}) or marks[n] then return nil,"线索标记无效" end
      marks[n]=true
    end
  end
  if parts[7]~="" then
    core.accused=ids[parts[7]];if not core.accused then return nil,"指认无效" end
  end
  core.elapsed=payload.elapsed;core.failed_accusations=failed
  if parts[8] then
    local pos,clue=parts[8]:match('^H([01])([012])$')
    if not pos then return nil,'提示次数无效' end
    core.hint635_used={position=tonumber(pos),clue=tonumber(clue)}
  end
  core._saved_moves=moves
  if payload.solved then core.status=Core.STATUS_SOLVED end
  return core,marks
end
function Murdoku.resume_selected(id)
  local a=current.adapter
  local slot=a._save_pending or a._confirmed
  if not slot then return false end
  local entry,archive,record=archive_record_payload(slot,id)
  if not entry then return false end
  local level=Levels.get(id)
  if not level then return false end
  local restored,marks=checkpoint_parse(entry,level)
  if not restored then return false end
  if tostring(current.level.id)~=tostring(id) then
    local opts={}; for k,v in pairs(current.options or {}) do opts[k]=v end
    opts.adapter=a; opts.restore_save=false; opts.start_in_level=true; opts.skip_intro=true; opts.screen=nil
    if not Murdoku.start(id,opts) then return false end
  end
  local c=current.controller
  c:_clear_verdict(); c.pending=nil; c.modal=nil; c.screen=nil
  current.core=restored; c.core=restored; c._false_clues=marks
  Murdoku.begin_ticket_visit()
  c._grid_sig=nil; c._grid_refill_pending=true; c.dirty=true
  current._result_record=record.solved and record or nil
  a.state['murdoku/recent']=tostring(id)
  if record.solved then c._resumed_solved_board = true else c._resumed_solved_board = nil end
  Murdoku.render(true)
  if record.solved and c:_start_verdict()~=nil then
    local v=c._verdict
    v.done=true; v.animation_complete=true
    c._resumed_solved_board=true
    c.result_seconds=record.seconds
    for i,item in ipairs(v.list) do
      v.last[i]=1
      a:set_verdict_ring(item.cell,item.ok,1)
    end
  end
  print('[727] 已恢复 '..id..(record.solved and ' 通关终态' or ' 进行中'))
  return true
end
local function normalize_slot(p)
  local b=p.solved
  if b==1 or b=='true' or b=='1' then b=true elseif b==0 or b=='false' or b=='0' then b=false end
  return {level_id=p.level_id,state_code=p.state_code,moves=tonumber(p.moves),elapsed=tonumber(p.elapsed),solved=b}
end
-- The M725 archive includes recent level, moves, elapsed and solved per level.
-- Compare the complete persistent field. The transport's scalar copies may be defaults.
local function matches_slot(p, reply)
  return p and reply and type(p.state_code)=='string' and p.state_code~='' and p.state_code==reply.state_code
end
local function save_notice(text,seconds)
  local c=current and current.controller
  if not c then return end
  c.toast=text
  c.toast_until=(c.now or 0)+(seconds or 4)
  c.dirty=true
end
local function wait_settle(a)
  a._settle_after=true
  a._settle_deadline=(a._archive_clock or 0)+12
  save_notice('正在确认存档，确认后结算',12)
end
local function slot_tag(p)
  local code=p.state_code or ''
  local sum=0
  for i=1,#code do sum=(sum*31+code:byte(i))%65521 end
  return tostring(p.level_id)..' 步数='..tostring(p.moves)..' 通关='..tostring(p.solved)..' 长度='..#code..' 校验='..sum
end
local function send_write(a,p)
  a._save_pending=p
  a._logged_old_reply=nil
  a._check_at=(a._archive_clock or 0)+0.4
  a._checks=0
  print('[727] 请求保存 '..slot_tag(p))
  local ok,sent=pcall(function() return a:signal_emit(Qianxing.SIGNALS.SAVE,a:_save_params(p)) end)
  if not ok or sent==false then print('[727] 写入未发出 '..p.level_id..' '..tostring(sent)) end
end
function Murdoku.begin_ticket_visit()
  local a=current.adapter
  current.ticket_entry=nil
  if not a._archive_ready then return end
  local slot=a._save_pending or a._confirmed
  local archive={records={}}
  if slot then archive=archive_decode(slot) end
  if not archive then return end
  local e=purse(archive)
  local _,clues,positions=funds(e)
  current.ticket_entry={clues=clues,positions=positions,used=e.used,pos_used=e.pos_used}
end
function Murdoku.wallet()
  local a=current and current.adapter
  if not a or not a._archive_ready then return nil,nil,'读取存档中' end
  local slot=a._confirmed
  local archive
  if slot then archive=archive_decode(slot) else archive={records={}} end
  if not archive then return nil,nil,'存档读取失败' end
  local e=purse(archive)
  local coins,tickets,positions=funds(e)
  return coins,tickets,a._save_pending and '核对存档中' or '',e.last,positions,e.pos_last,e.pos_first,e.used,e.pos_used
end
local function board_entry(session,id,solved,result)
    local core=session.core
    return {level_id=id, elapsed=math.floor(core.elapsed or 0), moves=(core._saved_moves or 0)+#(core.history or {}),failed=core.failed_accusations or 0,
      solved=solved,outcome=result and result.outcome or (solved and 'success' or ''), wrong=result and result.wrong or 0, seconds=result and result.seconds or math.floor(core.elapsed or 0),checkpoint=checkpoint_code(session)}
end
function Murdoku.trade(op,target)
  local a=current and current.adapter
  if not a or not a._archive_ready or a._save_pending or a._settle_after or a._settle_sent then return false,'请等待存档确认' end
  local slot=a._confirmed
  local archive
  if slot then archive=archive_decode(slot) else archive={records={}} end
  if not archive then return false,'存档读取失败' end
  local e=purse(archive)
  local coins,tickets,positions=funds(e)
  local c=current.controller
  if op~='buy' and not current.ticket_entry then Murdoku.begin_ticket_visit() end
  if op=='buy' then
    if c.screen~='shop' or c.econ_pick~=target or (target~='position' and target~='clue') then return false,'请先确认商品' end
    if coins<SHOP_PRICE[target] then return false,'调查币不足' end
    if target=='position' and positions==0 then e.pos_first=tickets==0
    elseif target=='clue' and tickets==0 then e.pos_first=positions>0 end
    if target=='position' then e.pos_bought=e.pos_bought+1 else e.bought=e.bought+1 end
  elseif op=='position' then
    local core=current.core
    if c.screen or c.modal or core.status~=Core.STATUS_PLAYING or not case_bit(current.level.id) then return false,'当前不能用券' end
    if not core.hint635_used or core.hint635_used.position<1 then return false,'请先使用免费揭示' end
    if e.pos_bought<=e.pos_used then return false,'位置揭示券不足' end
    local id=core.selected
    local p=id and core.solution[id]
    if not p or core:is_blocked(p.r,p.c) then return false,'请先选中可揭示的人物' end
    local cur=core.pos[id]
    if cur and core.placed[id] and cur.r==p.r and cur.c==p.c then return false,'该人物已在正确位置' end
    local trial,msg=core:preview_ticket_hint()
    if not trial then return false,msg end
    local level_id=current.level.id
    archive.records[level_id]=board_entry({core=trial,level=current.level,controller=c},level_id,false,nil)
    archive.recent=level_id
    e.pos_last=table.concat({current.level.id,id,p.r,p.c},':')
    e.pos_used=e.pos_used+1
  elseif op=='use' then
    if c.screen or c.modal or current.core.status~=Core.STATUS_PLAYING or not case_bit(current.level.id) then return false,'当前不能用券' end
    if tickets<1 then return false,'核验券不足' end
    local general=c.general_focus==true
    local index=general and 1 or c.focused_clue
    if (not general and not current.core.selected) or not index or not current.core.hint635_used or current.core.hint635_used.clue<2 then return false,'请先选中有效线索并用完免费次数' end
    local truth=current.core:answer_clue(index,general)
    if truth==nil then return false,'该线索不能核验' end
    e.last=table.concat({current.level.id,general and 'g' or 'n',index,truth and '1' or '0'},':')
    e.used=e.used+1
  else return false,'未知操作' end
  local code=archive_encode(archive)
  if #code>1800 then return false,'存档空间不足' end
  local p={level_id=archive.recent or (slot and slot.level_id) or '@tutorial',state_code=code,moves=slot and slot.moves or 0,elapsed=slot and slot.elapsed or 0,solved=slot and slot.solved or false}
  if op=='position' then
    local ok,msg=current.core:hint()
    if not ok then return false,msg end
    local entry=archive.records[archive.recent]
    p.moves,p.elapsed,p.solved=entry.moves,entry.elapsed,entry.solved
    c:dismiss_action_confirm()
    c:finish_position_hint()
  end
  a._trade730={controller=c,op=op,target=target,last=op=='position' and e.pos_last or e.last}
  send_write(a,p)
  return true,'正在核对交易'
end
local function finish_settle(a,id)
  if a._settle_sent then return end
  print('[727] 发起结算 '..tostring(id))
  a._settle_sent=true
  local ok,sent=pcall(a.signal_emit,a,Qianxing.SIGNALS.SETTLE,{id})
  if not ok or sent==false then
    a._settle_sent=nil
    save_notice('结算未发出，请重试')
    print('[727] 结算未发出，可重试')
  end
end
function Murdoku.restore(payload)
  if not current or type(payload)~='table' then return false end
  local a=current.adapter
  payload=normalize_slot(payload)
  if a._archive_ready then
    local p=a._save_pending
    if matches_slot(p,payload) then
      print('[727] 玩家槽确认 '..slot_tag(p))
      a._confirmed=p; a._save_pending=nil
      current.controller.dirty=true
      local tx=a._trade730
      a._trade730=nil
      if tx and tx.controller==current.controller then
        local c=current.controller
        if tx.op=='buy' and c.screen=='shop' then c.econ_status=(tx.target=='position' and '位置揭示券' or '线索核验券')..'已入包'

        elseif tx.op=='use' and not c.screen and not c.modal and c.hint635 and c.hint635.kind=='message' then
          c.hint635={kind='message',text=tx.last:sub(-1)=='1' and '该线索为真' or '该线索为假'}
        end
        c.dirty=true
      end
      if a._settle_after then
        a._settle_after=nil
        a._settle_deadline=nil
        finish_settle(a,p.level_id)
      elseif a._manual_save then
        save_notice('存档已确认')
      end
      a._manual_save=nil
    elseif p and not a._logged_old_reply then
      a._logged_old_reply=true
      print('[727] 收到其他快照，等待最新局面码。回读 '..slot_tag(payload)..'，当前 '..slot_tag(p))
    end
    return true
  end
  local code=payload.state_code
  if code=='' and (payload.level_id or '')=='' then
    print('[727] 入场读回 空槽')
  elseif type(code)=='string' and code:match('^T724|T[0-7]$') then
    merge_tutorial(tonumber(code:sub(-1)))
  else
    local archive,err=archive_decode(payload)
    if not archive then print('[727] 读取玩家槽失败 '..tostring(err));return false end
    merge_tutorial(archive.mask)
    local id=archive.recent or payload.level_id
    if id and archive.records[id] then a.state['murdoku/recent']=id end
    print('[727] 入场读回 '..slot_tag(payload)..' 最近关卡='..tostring(id))
    a._confirmed=payload
  end
  a._archive_ready=true
  if not current.controller.screen and not current.ticket_entry then Murdoku.begin_ticket_visit() end
  local c=current.controller
  c.dirty=true
  if c._waiting_continue and c.screen=='home' then
    c._waiting_continue=nil
    c:on_input({action='continue'})
    return true
  end
  local id=c._waiting_card; c._waiting_card=nil
  if id and c.screen=='select' then c.opts.on_pick_level(id,true) end
  return true
end
local SAVE_RECENT   = "murdoku/recent"
local SAVE_PROGRESS = "murdoku/progress"
local function store()
  return prepared_adapter
end
function Murdoku.remember_level(id)
  if id == nil then return end
  local a = store()
  if a == nil or a.save == nil then return end
  pcall(function() a:save(SAVE_RECENT, tostring(id), { no_signal = true }) end)
  pcall(function()
    local p = a:load(SAVE_PROGRESS)
    if type(p) ~= "table" then p = {} end
    local cur = p[tostring(id)]
    if type(cur) ~= "table" then cur = {} end
    if not cur.cleared then cur.started = true end
    p[tostring(id)] = cur
    a:save(SAVE_PROGRESS, p, { no_signal = true })
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
    a:save(SAVE_PROGRESS, p, { no_signal = true })
  end)
end
function Murdoku.record_result(id, outcome, wrong, seconds)
  if id == nil or (outcome ~= "success" and outcome ~= "perfect") then return false end
  local a = store()
  if not a or not a.save or not a.load then return false end
  wrong = math.max(0, math.floor(tonumber(wrong) or 0))
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if outcome == "perfect" then wrong = 0 end
  local p = a:load(SAVE_PROGRESS)
  if type(p) ~= "table" then p = {} end
  local cur = p[tostring(id)]
  if type(cur) ~= "table" then cur = {} end
  local rank = { success = 1, perfect = 2 }
  if current and tostring(current.level.id)==tostring(id) and current.core.status==Core.STATUS_SOLVED then
    current._result_record={outcome=outcome,wrong=wrong,seconds=seconds}
    Murdoku.save_now()
  end
  local oldrank = rank[cur.outcome] or 0
  local better = rank[outcome] > oldrank or (rank[outcome] == oldrank and
    (wrong < (cur.wrong or math.huge) or (wrong == cur.wrong and seconds < (cur.seconds or math.huge))))
  if not better then return false end
  cur.cleared, cur.started = true, true
  cur.outcome, cur.wrong, cur.seconds = outcome, wrong, seconds
  p[tostring(id)] = cur
  a:save(SAVE_PROGRESS, p, {no_signal = true})
  return true
end
function Murdoku.progress_of(id)
  local a = store()
  if a == nil or a.load == nil then return nil end
  local p = nil
  pcall(function() p = a:load(SAVE_PROGRESS) end)
  local local_progress=type(p)=='table' and p[tostring(id)] or nil
  if local_progress and local_progress.cleared then return local_progress end
  local slot=a._save_pending or a._confirmed
  local archive=slot and archive_decode(slot)
  local r=archive and archive.records[tostring(id)]
  if r then return {started=true,cleared=r.solved,outcome=r.outcome,wrong=r.wrong,seconds=r.seconds} end
  return local_progress
end
function Murdoku.save_now(settle,tutorial_only,periodic)
  if not current then return false end
  local a=current.adapter
  if not a._archive_ready then
    if not periodic then save_notice('正在读取玩家存档，请稍后重试') end
    return false
  end
  if a._settle_sent then return false end
  if a._settle_after then return settle==true end
  local prior=a._save_pending or a._confirmed
  local archive=prior and archive_decode(prior) or nil
  if prior and not archive then return false end
  archive=archive or {records={}}
  local wallet=purse(archive)
  archive.mask=tutorial_mask()
  local id=tostring(current.level.id)
  if tutorial_only then
    id=archive.recent or (prior and prior.level_id) or '@tutorial'
  else
    local core=current.core
    local solved=core.status==Core.STATUS_SOLVED
    local result=solved and current._result_record or nil
    local entry=board_entry(current,id,solved,result)
    local previous=archive.records[id]
    if periodic then
      if not previous and #core.history==0 and not next(current.controller._false_clues or {}) then return true end
      if previous and previous.checkpoint==entry.checkpoint and previous.solved==entry.solved then return true end
    end
    if result then claim(wallet,id,result.outcome) end
    archive.records[id]=entry
  end
  archive.recent=id
  local r=archive.records[id] or {}
  local p={level_id=id,state_code=archive_encode(archive),elapsed=r.elapsed or 0,moves=r.moves or 0,solved=r.solved or false}
  if #p.state_code>1800 then print('[727] 存档超出容量 '..#p.state_code);return false end
  if settle then wait_settle(a) end
  if not a._save_pending and matches_slot(a._confirmed,p) then
    if settle then
      a._settle_after=nil
      a._settle_deadline=nil
      finish_settle(a,id)
    elseif a._manual_save then
      a._manual_save=nil
      save_notice('存档已确认')
    end
  elseif not matches_slot(a._save_pending,p) then
    -- Built from the newest pending archive, including every other level.
    send_write(a,p)
  elseif not periodic then
    a._checks=0
    a._check_at=(a._archive_clock or 0)+0.4
    pcall(function() a:signal_emit(Qianxing.SIGNALS.SAVE,a:_save_params(p)) end)
  end
  return true
end
function Murdoku.settle_from_screen()
  if not current then return end
  local a=current.adapter
  if not a._archive_ready or a._settle_sent then return end
  if current.controller.screen==nil then return Murdoku.save_now(true) end
  local latest=a._save_pending or a._confirmed
  if a._save_pending then
    if not a._settle_after then wait_settle(a); a._checks=0; a._check_at=a._archive_clock or 0 end
    return
  end
  finish_settle(a,(latest and latest.level_id~='@tutorial' and latest.level_id) or tostring(current.level.id))
end
function Murdoku.poll_save(a)
  local p=a._save_pending
  if a._settle_after and a._archive_clock >= a._settle_deadline then
    a._settle_after=nil
    a._settle_deadline=nil
    a._manual_save=nil
    save_notice('存档尚未确认，已保留棋盘，请重试',6)
    print('[727] 存档确认超时，可重试 '..slot_tag(p))
  end
  if not p or a._archive_clock<(a._check_at or 0) then return end
  a._checks=(a._checks or 0)+1
  a._check_at=a._archive_clock+math.min(4,1+a._checks)
  if a._checks==2 or a._checks==5 then print('[727] 等待玩家槽确认 '..slot_tag(p)) end
  if a._checks%2==0 then
    pcall(function() a:signal_emit(Qianxing.SIGNALS.SAVE,a:_save_params(p)) end)
  end
  pcall(a.signal_emit,a,'murdoku/load',{})
end
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

__M["tutorial_ui"] = function()
local M = {}
local FURN = {
  home = {
    { "plant_2",0,0,96,96,108,108,258.412689,139.758377 },
    { "table_h2",0,0,216,108,216,108,148.783066,66.671959 },
    { "chair",0,0,108,108,108,108,404.585541,-6.414462 },
    { "rug",0,0,108,108,108,108,185.326279,-152.587296 },
  },
  l1 = {
    { "table_v2",676,262,108,216,108,216 }, { "plant_2",788,206,108,108,108,108 },
    { "plant_2",676,654,108,108,108,108 }, { "plant_2",900,654,108,108,108,108 },
    { "rug_2",732,430,216,108,216,108 }, { "rug_2",1068,318,216,108,216,108 },
    { "chair",788,542,108,108,108,108 }, { "chair",1012,654,108,108,108,108 },
  },
  l2 = {
    { "chair",667.5,197.5,89,89,108,108 }, { "table_h2",807,197.5,178,89,216,108 },
    { "rug",946.5,197.5,89,89,108,108 }, { "statue",1132.5,197.5,89,89,108,108 },
    { "chair",946.5,290.5,89,89,108,108 }, { "plant",760.5,383.5,89,89,108,108 },
    { "rug_2",900,383.5,178,89,216,108 }, { "rug_3",667.5,616,89,178,108,216 },
    { "plant",946.5,569.5,89,89,108,108 }, { "shelf",760.5,662.5,89,89,108,108 },
    { "plant",946.5,662.5,89,89,108,108 }, { "table",1039.5,662.5,89,89,108,108 },
  },
}
local SCALE = 1480 / 2268
local BOARD_X = 60 + (1256 - 36) * SCALE + 620 * SCALE / 2
local BOARD_Y = 121 + (302 - 36) * SCALE + 620 * SCALE / 2
function M:furniture_done()
  local spec = FURN[self.tag]
  if spec == nil then return true end
  if self.furniture == nil then return false end
  for i = 1, #spec do if self.furniture[i] == nil then return false end end
  return true
end
function M:_ensure_furniture(limit)
  local spec = FURN[self.tag]
  if spec == nil or game == nil or game.InstantiateClientUIControl == nil then return end
  local ad = self.adapter
  local now = (ad and ad.clock) or 0
  local bname = self.root_name .. ".board"
  local parent = nil
  if self._furn_retry_at748 ~= nil and now < self._furn_retry_at748 then
    -- 748（B9）：board 暂缺时不整代锁死，若已通过 O(1) 静态路由挂回则立刻继续，未挂回则跳过本帧开销。
    if ad ~= nil and ad.probe_static747 ~= nil then
      parent = ad:probe_static747(bname)
      if parent ~= nil then ad.controls[bname] = parent end
    end
    if parent == nil then return end
  end
  if parent == nil then parent = self:_find(bname) end
  if parent == nil then
    local tries = (self._furn_miss_tries748 or 0) + 1
    self._furn_miss_tries748 = tries
    local gap = (tries <= 2) and 0.25 or ((tries <= 5) and 0.5 or 1.0)
    self._furn_retry_at748 = now + gap
    if not self._furn_skip_logged745 then
      self._furn_skip_logged745 = true
      self:_note("家具实例化等待 tag=" .. self.tag .. "：暂找不到 " .. bname .. "（退避重试）")
    end
    return
  end
  self._furn_retry_at748 = nil
  self._furn_miss_tries748 = 0
  local prefabs = nil
  pcall(function() prefabs = self.adapter:_furn_prefab_map() end)
  if type(prefabs) ~= "table" then
    self:_note("家具实例化跳过 tag=" .. self.tag .. "：things 模板映射为空")
    return
  end
  self.furniture = self.furniture or {}
  local order = {}
  for pass = 1, 2 do
    for i, f in ipairs(spec) do
      local is_rug = tostring(f[1]):find("rug", 1, true) ~= nil
      if (pass == 1) == is_rug then order[#order + 1] = i end
    end
  end
  local made = 0
  for _, i in ipairs(order) do
    local f = spec[i]
    if limit ~= nil and made >= limit then break end
    if self.furniture[i] == nil and prefabs[f[1]] ~= nil then
      local ok, obj = pcall(game.InstantiateClientUIControl, prefabs[f[1]], parent)
      if ok and obj ~= nil then
        self.furniture[i] = obj
        local w, h = f[4] * SCALE, f[5] * SCALE
        local x = BOARD_X - 656 * SCALE / 2 + (f[2] - 572) * SCALE - 800
        local y = 450 - (BOARD_Y - 656 * SCALE / 2 + (f[3] - 102) * SCALE)
        pcall(function() if obj.SetAnchorMin then obj:SetAnchorMin(0.5, 0.5) end end)
        pcall(function() if obj.SetAnchorMax then obj:SetAnchorMax(0.5, 0.5) end end)
        pcall(function() if obj.SetPivot then obj:SetPivot(0.5, 0.5) end end)
        pcall(function() if obj.SetSizeDelta then obj:SetSizeDelta(w, h) end end)
        pcall(function() if obj.SetAnchoredPosition then obj:SetAnchoredPosition(x, y) end end)
        if f[8] ~= nil then
          pcall(function() obj:SetAnchoredPosition(f[8], f[9]) end)
        end
        local scaled = false
        pcall(function()
          if self.adapter._furn_scale_layers ~= nil then
            self.adapter:_furn_scale_layers(obj, w / f[6], h / f[7]); scaled = true
          end
        end)
        if not scaled then pcall(function() if obj.SetLocalScale then obj:SetLocalScale(w / f[6], h / f[7], 1) end end) end
        pcall(function()
          if obj.SetAsLastSibling ~= nil then
            obj:SetAsLastSibling()
          elseif obj.SetSiblingIndex ~= nil and parent.GetChildren ~= nil then
            local kids = nil
            pcall(function() kids = parent:GetChildren() end)
            if type(kids) == "table" and #kids > 0 then obj:SetSiblingIndex(#kids - 1) end
          end
        end)
        pcall(function() obj:SetVisible(true); obj:SetActive(true) end)
        made = made + 1
      end
    end
  end
  self._furn_made = (self._furn_made or 0) + made
  if self._furn_made > 0 and not self._furn_logged and self:furniture_done() then
    self._furn_logged = true
    self:_note("家具实例化 tag=" .. self.tag .. " 新建=" .. self._furn_made)
  end
end
function M:prewarm(n)
  if self:furniture_done() then return true end
  if not self.inited then return false end
  self:_ensure_furniture(n or 1)
  return self:furniture_done()
end
function M.new(adapter, opts)
  if type(opts) ~= "table" then opts = {} end
  local pmap = type(opts.page_map) == "table" and opts.page_map or nil
  local pages = pmap and #pmap or (tonumber(opts.pages) or 1)
  local raw_pages = tonumber(opts.raw_pages) or pages
  if pmap then
    for i = 1, #pmap do
      if pmap[i] > raw_pages then raw_pages = pmap[i] end
    end
  end
  return setmetatable({
    adapter = adapter,
    tag = tostring(opts.tag or "?"),
    root_name = tostring(opts.root or ("td." .. tostring(opts.tag or "?"))),
    pages = pages,
    raw_pages = raw_pages,
    page_map = pmap,
    page = 1,
    open = false,
    inited = false,
    eager_furniture = (opts.eager_furniture == true),
    bound = {},
    log = {},
  }, { __index = M })
end
function M:_raw_page(logical_idx)
  local pm = self.page_map
  if pm ~= nil then return pm[logical_idx] or logical_idx end
  return logical_idx
end
function M:_note(msg)
  self.log[#self.log + 1] = msg
  if print then print("[tutorial] " .. msg) end
end
local function t745_find_in_root(root, name)
  local c = root:GetChild(name)
  if c ~= nil then return c end
  local kids = root:GetChildren()
  if type(kids) == "table" then
    for i = 1, #kids do
      local child = kids[i]
      if child ~= nil and child.name == name then return child end
    end
  end
  return nil
end
local function t748_set_vis_only(ctrl, want)
  if ctrl.visible ~= want then ctrl:SetVisible(want) end
end
local function t748_set_act_true(ctrl)
  if ctrl.active ~= true then ctrl:SetActive(true) end
end
function M:_find(name)
  local ad = self.adapter
  if ad == nil or name == nil then return nil end
  local ctrl = ad.controls and ad.controls[name] or nil
  if ctrl == nil then
    local ok, res = pcall(ad.find, ad, name)
    if ok then ctrl = res end
  end
  -- 700：名称索引可能早于教程子控件挂入；在已知根容器内补查。
  if ctrl == nil and name ~= self.root_name then
    local root = ad.controls and ad.controls[self.root_name] or nil
    if root == nil then
      local ok_r, r = pcall(ad.find, ad, self.root_name)
      if ok_r then root = r end
    end
    if root ~= nil then
      local ok_c, c = pcall(t745_find_in_root, root, name)
      if ok_c then ctrl = c end
    end
  end
  return ctrl
end
function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  local w = want and true or false
  local ok_v = pcall(t748_set_vis_only, ctrl, w)
  if w then pcall(t748_set_act_true, ctrl) end
  return ok_v == true
end
function M:_bind(name, fn, resolved, sync_tbl)
  local ctrl = resolved or self:_find(name)
  if ctrl == nil or self.bound[ctrl] then return ctrl ~= nil end
  if ctrl.AddCursorEventListener == nil then return false end
  local ok = pcall(function()
    local ev = Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick
    if ev == nil then error("CursorClick unavailable") end
    pcall(function() ctrl.raycastTarget = true end)
    pcall(function() ctrl.interactable = true end)
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  if ok then
    self.bound[ctrl] = true
    if self.adapter ~= nil and self.adapter.register_watch_handle748 ~= nil then
      self.adapter:register_watch_handle748(name, ctrl, "util", fn, self, sync_tbl)
    end
  end
  return ok
end
function M:_bind_steps()
  if self.pages < 2 then return end
  self._steps_bound = self._steps_bound or {}
  if self._steps_bound[self.page] then return end
  local raw_p = self:_raw_page(self.page)
  local prefix = self.root_name .. ".page." .. tostring(raw_p)
  local complete = true
  local controls = {}
  local page_ctrl = self:_find(prefix)
  local kids = nil
  if page_ctrl and page_ctrl.GetChildren then pcall(function() kids = page_ctrl:GetChildren() end) end
  if type(kids) == "table" then
    for _, child in ipairs(kids) do
      local name = nil
      pcall(function() name = child.name end)
      if name then controls[name] = child end
    end
  end
  local function bind(name, fn)
    if type(kids) == "table" and controls[name] == nil then return false end
    return self:_bind(name, fn, controls[name])
  end
  for i = 1, self.pages do
    local target = i
    local fn = function() if self.open then self:go(target) end end
    if not bind(prefix .. ".stephit." .. tostring(i), fn) then complete = false end
  end
  if complete then self._steps_bound[self.page] = true end
end
function M:_paint()
  local cur_raw = self:_raw_page(self.page)
  if (self.tag == "l1" or self.tag == "l2") and self.page == self.pages then
    local label = self:_find(self.root_name .. ".page." .. tostring(cur_raw) .. ".nexttext")
    if label ~= nil then pcall(function() label.text = "开始办案" end) end
  end
  if self.open then self:_bind_steps() end
  if self.page_map ~= nil then
    for i = 1, #self.page_map do
      local r = self.page_map[i]
      self:_visible(self.root_name .. ".page." .. tostring(r), r == cur_raw)
    end
  else
    local total_raw = self.raw_pages or self.pages
    for r = 1, total_raw do
      self:_visible(self.root_name .. ".page." .. tostring(r), r == cur_raw)
    end
  end
  self:_visible(self.root_name .. ".btn.prev", self.page > 1)
  self:_visible(self.root_name .. ".btn.next", true)
  return self
end
function M:init()
  if self.inited then return self end
  if self:_find(self.root_name) == nil then return self end
  -- 根节点可见不代表按钮已加载完；只在必需的事件绑定齐全后提交就绪。
  local prev = self:_bind(self.root_name .. ".btn.prev", function() self:prev() end)
  local next_bound = self:_bind(self.root_name .. ".btn.next", function() self:next() end)
  local close_bound = self:_bind(self.root_name .. ".btn.close", function() self:close() end)
  self:_bind(self.root_name .. ".btn.skip", function() self:close() end)
  if not next_bound or not close_bound or (self.pages > 1 and not prev) then
    self:_visible(self.root_name, false)
    if not self._waiting_logged then
      self._waiting_logged = true
      self:_note("等待教程按钮就绪 tag=" .. self.tag)
    end
    return self
  end
  self.inited = true
  self.page = 1
  self:_paint()
  if self.eager_furniture then self:_ensure_furniture() end
  self:_visible(self.root_name, false)
  self:_note("静态教程 init 完成 tag=" .. self.tag .. " pages=" .. tostring(self.pages) .. " 必需按钮已绑定")
  return self
end
function M:open_ui()
  self:init()
  if not self.inited then return self end
  self.open = true
  self:_visible(self.root_name, true)
  self:_ensure_furniture()
  self:_paint()
  self:_note("打开 tag=" .. self.tag .. " 第 " .. tostring(self.page) .. " 页")
  return self
end
function M:close()
  if self.open then self:_note("关闭 tag=" .. self.tag) end
  self.open = false
  self:_visible(self.root_name, false)
  return self
end
function M:go(n)
  local p = tonumber(n) or 1
  if p < 1 then p = 1 end
  if p > self.pages then p = self.pages end
  self.page = p
  self:_paint()
  return self
end
function M:next()
  if self.page >= self.pages then return self:close() end
  return self:go(self.page + 1)
end
function M:prev() return self:go(self.page - 1) end
M["goto"] = M.go
return M

end

__M["levels.init"] = function()
local RoomMap = __require("room_map")
local M = {}
local LIST = {
  "levels.case_001",
  "levels.case_002",
  "levels.case_003",
  "levels.case_004",
  "levels.case_005",
  "levels.case_006",
  "levels.case_007",
}
M._errors = {}
local function note_error(module_name, err)
  M._errors[#M._errors + 1] = { module = module_name, error = tostring(err) }
end
local _all_cache745 = nil
function M.all()
  if _all_cache745 ~= nil then return _all_cache745 end
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
  if #out == #LIST then _all_cache745 = out end
  return out
end
function M.load_errors() return M._errors end
function M.get(level_id)
  for _, lv in ipairs(M.all()) do
    if lv.id == level_id then return lv end
  end
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
function M.ui_list()
  local out = {}
  local list = M.all()
  for i = 1, #list do
    local lv = list[i]
    local sz = lv.size
    local rows = type(sz) == "table" and tonumber(sz.rows) or nil
    local cols = type(sz) == "table" and tonumber(sz.cols) or nil
    local room_grid = nil
    if rows and cols then
      local ok, grid = pcall(function()
        return RoomMap.compute_rooms(rows, cols, RoomMap.build_walls(lv, rows, cols))
      end)
      if ok then room_grid = grid end
    end
    out[i] = {
      id = lv.id, name = lv.name, difficulty = lv.difficulty,
      size = lv.size, suspects = lv.suspects, victim = lv.victim,
      rooms = lv.rooms, objects = lv.objects,
      room_boxes = RoomMap.boxes(lv),
      room_names = lv.room_names,
      -- 696：选关卡片棋盘缩略图用（底色 + 门墙，家具省略）
      walls = lv.walls, doors = lv.doors, room_grid = room_grid,
    }
  end
  return out
end
return M

end

__M["levels.case_001"] = function()
 return {
  id = "case_001",
  name = "案件 001 · 独行夜盗",
  subtitle = "保险库内室只留下一个人的痕迹 —— 是独自作案，还是有人替他望风？",
  difficulty = "easy",
  size = { rows = 5, cols = 5 },
  room_names = { [1] = "大屋", [2] = "内室", [3] = "外间" },
  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",    
  },
  walls = {
    { "v", 1, 3 }, { "v", 2, 3 }, { "v", 3, 3 },    
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 },    
    { "h", 3, 4 },                                  
    { "v", 4, 4 }, { "v", 5, 4 },                   
  },
  doors = {
    { "v", 2, 3 },    
    { "h", 3, 2 },    
    { "h", 3, 4 },    
  },
  objects = {
    ["桌子"] = { cells = { { r = 1, c = 1 }, { r = 2, c = 1 } },
                 occupiable = false, kind = "table"  },
    ["植物"] = { cells = { { r = 1, c = 2 }, { r = 5, c = 1 }, { r = 5, c = 3 } },
                 occupiable = false, kind = "plant"  },
    ["地毯"] = { cells = { { r = 3, c = 1 }, { r = 3, c = 2 }, { r = 2, c = 4 }, { r = 2, c = 5 } },
                 occupiable = true,  kind = "carpet" },
    ["椅子"] = { cells = { { r = 4, c = 2 }, { r = 5, c = 4 } },
                 occupiable = true,  kind = "chair"  },
  },
  blocked = {},
  water   = {},
  suspects = {
    { id = "A", name = "保安", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "前台小姐", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "快递员", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "顾客", portrait = "portrait.D", gender = "male" },
    { id = "V", name = "店长", portrait = "portrait.V",     is_victim = true },
  },
  victim = { id = "V", name = "店长" },
  roles = {
    thief = "D",
  },
  clues = {
    { type = "only_on_object", who = "A", object = "地毯" },        
    { type = "beside_object",  who = "B", object = "桌子" },        
    { type = "on_object",      who = "C", object = "椅子" },        
    { type = "beside_object",  who = "D", object = "植物" },        
    { type = "in_col",         who = "V", c = 5 },                 
  },
  meta = {
    false_clue = nil,
    announce   = "none",
  },
  solution = {
    D = { r = 1, c = 3 },    
    A = { r = 3, c = 1 },    
    B = { r = 2, c = 2 },    
    C = { r = 5, c = 4 },    
    V = { r = 4, c = 5 },    
  },
}

end

__M["levels.case_002"] = function()
return {
  id = "case_002",
  name = "案件 002 · 双影疑云",
  subtitle = "侧廊只留一个人的痕迹，大厅里却站着两位 —— 谁在说谎？",
  difficulty = "normal",
  size = { rows = 6, cols = 6 },
  room_names = { [1] = "大厅", [2] = "侧廊", [3] = "库房", [4] = "内室" },
  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },
  walls = {
    { "v", 1, 4 }, { "v", 2, 4 }, { "v", 3, 4 },    
    { "v", 4, 5 },                                  
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 }, { "h", 3, 4 }, { "h", 3, 5 },   
    { "h", 4, 6 },                                  
    { "v", 4, 3 }, { "v", 5, 3 },                   
    { "v", 6, 4 },                                  
    { "h", 5, 4 },                                  
  },
  doors = {
    { "v", 2, 4 },    
    { "h", 3, 1 },    
    { "v", 4, 3 },    
  },
  objects = {
    ["椅子"] = { cells = { { r = 1, c = 1 }, { r = 2, c = 4 } }, occupiable = true,  kind = "chair"  },
    ["地毯"] = { cells = { { r = 1, c = 4 }, { r = 3, c = 3 }, { r = 3, c = 4 },
                           { r = 5, c = 1 }, { r = 6, c = 1 } }, occupiable = true,  kind = "carpet" },
    ["桌子"] = { cells = { { r = 1, c = 2 }, { r = 1, c = 3 }, { r = 6, c = 5 } },
                 occupiable = false, kind = "table" },
    ["植物"] = { cells = { { r = 3, c = 2 }, { r = 5, c = 4 }, { r = 6, c = 4 } },
                 occupiable = false, kind = "plant" },
    ["书架"] = { cells = { { r = 6, c = 2 } }, occupiable = false, kind = "shelf" },
    ["雕塑"] = { cells = { { r = 1, c = 6 } }, occupiable = false, kind = "statue" },
  },
  blocked = {},
  water   = {},
  suspects = {
    { id = "A", name = "服务员", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "收银员", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "厨师", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "快递员", portrait = "portrait.D",     gender = "male" },
    { id = "E", name = "顾客", portrait = "portrait.E",   gender = "female" },
    { id = "V", name = "经理", portrait = "portrait.V",       is_victim = true },
  },
  victim = { id = "V", name = "经理" },
  roles = {
    thief = "D",
  },
  clues = {
    { type = "beside_object", who = "A", object = "书架" },                   
    { type = "beside_object", who = "B", object = "桌子" },                   
    { type = "n_on_object",   object = "椅子", n = 2 },                       
    { type = "above",         a = "E", b = "A", same_column = false },                             
    { type = "only_beside",   who = "E", object = "植物" },                   
    { type = "alone_and_below_in_other_room", who = "V", a = "C", b = "V" },  
  },
  general_clues = {
    { type = "nobody_on_object", object = "地毯" },
  },
  meta = {
    false_clue = 4,
    announce   = "unknown",
  },
  solution = {
    B = { r = 1, c = 1 },    
    D = { r = 2, c = 4 },    
    V = { r = 3, c = 6 },    
    C = { r = 4, c = 5 },    
    A = { r = 5, c = 2 },    
    E = { r = 6, c = 3 },    
  },
}

end

__M["levels.case_003"] = function()
return {["blocked"]={},["clues"]={{["a"]="A",["b"]="B",["same_column"]=false,["type"]="above"},{["object"]="植物",["type"]="beside_object",["who"]="B"},{["type"]="same_room",["a"]="B",["b"]="C"},{["object"]="桌子",["type"]="beside_object",["who"]="D"},{["a"]="D",["b"]="E",["same_column"]=false,["type"]="above"},{["object"]="桌子",["type"]="beside_object",["who"]="C"}},["difficulty"]="easy",["doors"]={{"v",2,4},{"h",3,3},{"h",4,2},{"h",4,5},{"h",5,4}},["general_clues"]={},["hint_preview"]={{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={"1:2","2:1"},["count"]=2,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={"1:3","2:2","2:4","3:3","3:4","4:3","5:4","6:3","6:5"},["count"]=9,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={"1:3","2:2","2:4","3:3","3:4","4:3","5:4","6:3","6:5"},["count"]=9,["rule"]="该家具四邻、同区域、可站人的格"}},["id"]="case_003",["meta"]={["announce"]="unknown"},["name"]="案件 003 · 明室谜踪",["objects"]={["书架"]={["cells"]={{["c"]=5,["r"]=1}},["kind"]="shelf",["occupiable"]=false},["地毯"]={["cells"]={{["c"]=2,["r"]=3},{["c"]=3,["r"]=3},{["c"]=2,["r"]=4}},["kind"]="carpet",["occupiable"]=true},["桌子"]={["cells"]={{["c"]=4,["r"]=6},{["c"]=4,["r"]=4},{["c"]=3,["r"]=2}},["kind"]="table",["occupiable"]=false},["椅子"]={["cells"]={{["c"]=1,["r"]=2},{["c"]=4,["r"]=2}},["kind"]="chair",["occupiable"]=true},["植物"]={["cells"]={{["c"]=1,["r"]=1}},["kind"]="plant",["occupiable"]=false},["雕塑"]={["cells"]={{["c"]=6,["r"]=2}},["kind"]="statue",["occupiable"]=false}},["roles"]={["thief"]="A"},["room_names"]={"R1","R2","R3","R4"},["rules"]={["one_per_col"]=true,["one_per_room"]=false,["one_per_row"]=true,["place_all"]=true,["tie_policy"]="forbid"},["size"]={["cols"]=6,["rows"]=6},["solution"]={["A"]={["c"]=2,["r"]=1},["B"]={["c"]=1,["r"]=2},["C"]={["c"]=3,["r"]=3},["D"]={["c"]=4,["r"]=5},["E"]={["c"]=5,["r"]=6},["V"]={["c"]=6,["r"]=4}},["suspects"]={{["id"]="A",["name"]="摄影师",["portrait"]="portrait.A"},{["id"]="B",["name"]="导游",["portrait"]="portrait.B"},{["id"]="C",["name"]="游客",["portrait"]="portrait.C"},{["id"]="D",["name"]="雕刻家",["portrait"]="portrait.D"},{["id"]="E",["name"]="清洁工",["portrait"]="portrait.E"},{["id"]="V",["is_victim"]=true,["name"]="馆长",["portrait"]="portrait.V"}},["victim"]={["id"]="V",["name"]="馆长"},["visual_theme"]={["accent"]="#bb513c",["door"]="#e38636",["key"]="reference",["name"]="原作明亮俯视（沿用 v12/v13）",["palette"]={["INK"]="#010101"},["room_colors"]={"#e3eef7","#f9ead0","#e3f0e4","#eee4f5"},["wall"]="#27333c"},["walls"]={{"v",1,4},{"v",2,4},{"h",2,4},{"v",3,3},{"h",3,3},{"v",3,4},{"h",4,1},{"v",4,2},{"h",4,2},{"v",4,4},{"h",4,5},{"h",4,6},{"v",5,2},{"h",5,3},{"h",5,4},{"h",5,5},{"v",6,5}},["water"]={}}
end

__M["levels.case_004"] = function()
return {["blocked"]={},["clues"]={{["type"]="same_room",["a"]="A",["b"]="V"},{["type"]="beside_object",["who"]="B",["object"]="桌子"},{["object"]="地毯",["type"]="on_object",["who"]="C"},{["object"]="椅子",["type"]="on_object",["who"]="D"},{["type"]="on_object",["who"]="A",["object"]="地毯"},{["type"]="above",["a"]="V",["b"]="A",["same_column"]=false}},["difficulty"]="normal",["doors"]={{"v",2,3},{"v",4,2},{"h",4,2},{"h",3,5},{"v",6,2}},["general_clues"]={},["hint_preview"]={{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={"1:2","2:1"},["count"]=2,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={"2:2","2:3","6:1","6:2"},["count"]=4,["rule"]="该家具自己的格子"},{["cells"]={"1:2","6:5"},["count"]=2,["rule"]="该家具自己的格子"},{["cells"]={"2:2","2:3","6:1","6:2"},["count"]=4,["rule"]="该家具自己的格子"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"}},["id"]="case_004",["meta"]={["announce"]="unknown",["false_clue"]=5},["name"]="案件 004 · 米纸谜案",["objects"]={["书架"]={["cells"]={{["c"]=5,["r"]=2}},["kind"]="shelf",["occupiable"]=false},["地毯"]={["cells"]={{["c"]=2,["r"]=2},{["c"]=3,["r"]=2},{["c"]=1,["r"]=6},{["c"]=2,["r"]=6}},["kind"]="carpet",["occupiable"]=true},["桌子"]={["cells"]={{["c"]=1,["r"]=1}},["kind"]="table",["occupiable"]=false},["椅子"]={["cells"]={{["c"]=2,["r"]=1},{["c"]=5,["r"]=6}},["kind"]="chair",["occupiable"]=true},["植物"]={["cells"]={{["c"]=6,["r"]=5},{["c"]=6,["r"]=2}},["kind"]="plant",["occupiable"]=false}},["roles"]={["thief"]="E"},["room_names"]={"R1","R2","R3","R4"},["rules"]={["one_per_col"]=true,["one_per_room"]=false,["one_per_row"]=true,["place_all"]=true,["tie_policy"]="forbid"},["size"]={["cols"]=6,["rows"]=6},["solution"]={["A"]={["c"]=4,["r"]=5},["B"]={["c"]=2,["r"]=1},["C"]={["c"]=3,["r"]=2},["D"]={["c"]=5,["r"]=6},["E"]={["c"]=1,["r"]=3},["V"]={["c"]=6,["r"]=4}},["suspects"]={{["id"]="A",["name"]="印刷工",["portrait"]="portrait.A"},{["id"]="B",["name"]="编辑",["portrait"]="portrait.B"},{["id"]="C",["name"]="装订工",["portrait"]="portrait.C"},{["id"]="D",["name"]="快递员",["portrait"]="portrait.D"},{["id"]="E",["name"]="校对员",["portrait"]="portrait.E"},{["id"]="V",["is_victim"]=true,["name"]="老板",["portrait"]="portrait.V"}},["victim"]={["id"]="V",["name"]="老板"},["visual_theme"]={["accent"]="#A8391B",["door"]="#C9A961",["key"]="archive-light",["name"]="档案卷宗 · 米纸浅色（美术调研 variant）",["note"]="6 色低饱和档案纸；粗墙深棕墨、门改铜色；家具走差异化命名",["palette"]={["BED_BASE"]="#EDE2C9",["BED_OVL"]="#C7A46A",["CARPET"]="#D9C08A",["CARPET_EDGE"]="#5A4634",["CHAIR_BASE"]="#E3D5B8",["CHAIR_LIGHT"]="#F0E6D0",["CHAIR_OVL"]="#B08A55",["GOLD"]="#C9A961",["GRAY"]="#B9AC97",["GRAY_DARK"]="#8A7A66",["INK"]="#3F2A1E",["INK_SOFT"]="#6B4A34",["PAPER"]="#EFE4CE",["PLANT_BASE"]="#C08A5E",["PLANT_LEAF_DARK"]="#5E6E58",["PLANT_OVL"]="#84977A",["ROOM_TINT"]="#E6DAC0",["SEAL"]="#A8391B",["SHADOW"]="#241812",["SHELF_BASE"]="#C8BBA0",["SHELF_OVL"]="#8FA3AE",["TABLE_BASE"]="#D9C7A3",["TABLE_EDGE"]="#8A6B45",["TAG"]="#7A8FA0",["TREE_BASE"]="#B6A88E",["TREE_DARK"]="#4F5C45",["TREE_LIGHT"]="#9BA98A",["TREE_OVL"]="#7C8A6A",["TV_BASE"]="#9AA4A6",["TV_DARK"]="#3A3B3C",["WHITE"]="#F8F1E2"},["room_colors"]={"#E6DAC0","#D9CEC0","#C9D6CE","#D6D9E2"},["wall"]="#3F2A1E"},["walls"]={{"v",1,3},{"v",2,3},{"v",3,3},{"h",3,3},{"h",3,4},{"h",3,5},{"h",3,6},{"h",4,1},{"v",4,2},{"h",4,2},{"v",5,2},{"v",6,2}},["water"]={}}
end

__M["levels.case_005"] = function()
return {["blocked"]={},["clues"]={{["object"]="椅子",["type"]="on_object",["who"]="A"},{["type"]="left_of",["a"]="C",["b"]="A",["same_row"]=false},{["type"]="above",["a"]="C",["b"]="V",["same_column"]=false},{["object"]="植物",["type"]="beside_object",["who"]="D"},{["object"]="地毯",["type"]="only_on_object",["who"]="E"},{["type"]="not_with",["a"]="B",["b"]="C"}},["difficulty"]="hard",["doors"]={{"v",6,3},{"v",3,4},{"h",2,5},{"h",3,2},{"v",1,4}},["general_clues"]={},["hint_preview"]={{["cells"]={"1:2","6:5"},["count"]=2,["rule"]="该家具自己的格子"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={"5:6","6:5"},["count"]=2,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={"1:5","5:4","5:5"},["count"]=3,["rule"]="该家具自己的格子"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"}},["id"]="case_005",["meta"]={["announce"]="unknown",["false_clue"]=2},["name"]="案件 005 · 火漆失窃",["objects"]={["书架"]={["cells"]={{["r"]=4,["c"]=1}},["kind"]="shelf",["occupiable"]=false},["地毯"]={["cells"]={{["c"]=5,["r"]=1},{["c"]=4,["r"]=5},{["c"]=5,["r"]=5}},["kind"]="carpet",["occupiable"]=true},["桌子"]={["cells"]={{["c"]=3,["r"]=3}},["kind"]="table",["occupiable"]=false},["椅子"]={["cells"]={{["c"]=2,["r"]=1},{["c"]=5,["r"]=6}},["kind"]="chair",["occupiable"]=true},["植物"]={["cells"]={{["c"]=6,["r"]=6}},["kind"]="plant",["occupiable"]=false},["雕塑"]={["cells"]={{["c"]=3,["r"]=4}},["kind"]="statue",["occupiable"]=false}},["roles"]={["thief"]="B"},["room_names"]={"大厅","侧廊","库房","内室"},["rules"]={["one_per_col"]=true,["one_per_room"]=false,["one_per_row"]=true,["place_all"]=true,["tie_policy"]="forbid"},["size"]={["cols"]=6,["rows"]=6},["solution"]={["A"]={["c"]=2,["r"]=1},["B"]={["c"]=6,["r"]=4},["C"]={["c"]=3,["r"]=2},["D"]={["c"]=5,["r"]=6},["E"]={["c"]=4,["r"]=5},["V"]={["c"]=1,["r"]=3}},["suspects"]={{["id"]="A",["name"]="保安",["portrait"]="portrait.A"},{["id"]="B",["name"]="值班员",["portrait"]="portrait.B"},{["id"]="C",["name"]="鉴定师",["portrait"]="portrait.C"},{["id"]="D",["name"]="摄影师",["portrait"]="portrait.D"},{["id"]="E",["name"]="管理员",["portrait"]="portrait.E"},{["id"]="V",["is_victim"]=true,["name"]="馆长",["portrait"]="portrait.V"}},["victim"]={["id"]="V",["name"]="馆长"},["visual_theme"]={["accent"]="#7A2A16",["door"]="#A8391B",["key"]="archive-dark",["name"]="夜勘卷宗 · 深棕墨 / 火漆红",["note"]="与第4关同色系但更暗，火漆红门；门墙结构、家具、人物 id 均改动",["palette"]={["BED_BASE"]="#EDE2C9",["BED_OVL"]="#C7A46A",["CARPET"]="#D9C08A",["CARPET_EDGE"]="#5A4634",["CHAIR_BASE"]="#E3D5B8",["CHAIR_LIGHT"]="#F0E6D0",["CHAIR_OVL"]="#B08A55",["GOLD"]="#C9A961",["GRAY"]="#B9AC97",["GRAY_DARK"]="#8A7A66",["INK"]="#3F2A1E",["INK_SOFT"]="#6B4A34",["PAPER"]="#EFE4CE",["PLANT_BASE"]="#C08A5E",["PLANT_LEAF_DARK"]="#5E6E58",["PLANT_OVL"]="#84977A",["ROOM_TINT"]="#E6DAC0",["SEAL"]="#A8391B",["SHADOW"]="#241812",["SHELF_BASE"]="#C8BBA0",["SHELF_OVL"]="#8FA3AE",["TABLE_BASE"]="#D9C7A3",["TABLE_EDGE"]="#8A6B45",["TAG"]="#7A8FA0",["TREE_BASE"]="#B6A88E",["TREE_DARK"]="#4F5C45",["TREE_LIGHT"]="#9BA98A",["TREE_OVL"]="#7C8A6A",["TV_BASE"]="#9AA4A6",["TV_DARK"]="#3A3B3C",["WHITE"]="#F8F1E2"},["room_colors"]={"#D8CBB0","#C9BCA6","#B8C6BE","#C4C8D2"},["wall"]="#241812"},["walls"]={{"v",6,3},{"v",5,3},{"h",4,3},{"v",4,3},{"h",3,4},{"v",4,2},{"h",3,2},{"h",3,1},{"h",2,6},{"v",3,4},{"h",2,5},{"v",2,4},{"v",1,4}},["water"]={}}
end

__M["levels.case_006"] = function()
return {["blocked"]={},["clues"]={{["object"]="椅子",["type"]="on_object",["who"]="A"},{["a"]="D",["b"]="E",["same_column"]=false,["type"]="above"},{["object"]="地毯",["type"]="on_object",["who"]="C"},{["object"]="桌子",["type"]="beside_object",["who"]="D"},{["object"]="雕塑",["type"]="beside_object",["who"]="E"},{["object"]="椅子",["type"]="beside_object",["who"]="F"},{["type"]="same_room",["a"]="D",["b"]="F"}},["difficulty"]="normal",["doors"]={{"h",3,3},{"v",3,4},{"h",3,5},{"h",4,1},{"v",7,2}},["general_clues"]={},["hint_preview"]={{["cells"]={"3:2","5:4"},["count"]=2,["rule"]="该家具自己的格子"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"},{["cells"]={"2:6","5:6"},["count"]=2,["rule"]="该家具自己的格子"},{["cells"]={"1:2","1:4","2:1","2:6","3:2","3:7","4:1","4:5","5:4","5:6","6:1","6:4","7:2","7:5"},["count"]=14,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={"6:3","7:4"},["count"]=2,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={"3:3","4:2","4:4","5:3","6:4"},["count"]=5,["rule"]="该家具四邻、同区域、可站人的格"},{["cells"]={},["count"]=0,["rule"]="不做位置提示"}},["id"]="case_006",["meta"]={["announce"]="unknown"},["name"]="案件 006 · 蓝图迷局",["objects"]={["书架"]={["cells"]={{["c"]=6,["r"]=1},{["c"]=7,["r"]=7}},["kind"]="shelf",["occupiable"]=false},["地毯"]={["cells"]={{["c"]=6,["r"]=2},{["c"]=6,["r"]=5}},["kind"]="carpet",["occupiable"]=true},["桌子"]={["cells"]={{["c"]=3,["r"]=1},{["c"]=7,["r"]=1},{["c"]=2,["r"]=2},{["c"]=7,["r"]=2},{["c"]=1,["r"]=3},{["c"]=5,["r"]=5},{["c"]=5,["r"]=6},{["c"]=1,["r"]=7},{["c"]=6,["r"]=7}},["kind"]="table",["occupiable"]=false},["椅子"]={["cells"]={{["c"]=2,["r"]=3},{["c"]=4,["r"]=5}},["kind"]="chair",["occupiable"]=true},["植物"]={["cells"]={{["c"]=3,["r"]=2},{["c"]=6,["r"]=6}},["kind"]="plant",["occupiable"]=false},["雕塑"]={["cells"]={{["c"]=3,["r"]=7}},["kind"]="statue",["occupiable"]=false}},["roles"]={["thief"]="B"},["room_names"]={"大厅","侧廊","库房","内室"},["rules"]={["one_per_col"]=true,["one_per_room"]=false,["one_per_row"]=true,["place_all"]=true,["tie_policy"]="forbid"},["size"]={["cols"]=7,["rows"]=7},["solution"]={["A"]={["c"]=2,["r"]=3},["B"]={["c"]=7,["r"]=6},["C"]={["c"]=6,["r"]=2},["D"]={["c"]=5,["r"]=4},["E"]={["c"]=4,["r"]=7},["F"]={["c"]=3,["r"]=5},["V"]={["c"]=1,["r"]=1}},["suspects"]={{["id"]="A",["name"]="绘图员",["portrait"]="portrait.A"},{["id"]="B",["name"]="设计师",["portrait"]="portrait.B"},{["id"]="C",["name"]="测绘员",["portrait"]="portrait.C"},{["id"]="D",["name"]="工程师",["portrait"]="portrait.D"},{["id"]="E",["name"]="管理员",["portrait"]="portrait.E"},{["id"]="F",["name"]="施工员",["portrait"]="portrait.F"},{["id"]="V",["is_victim"]=true,["name"]="老师",["portrait"]="portrait.V"}},["victim"]={["id"]="V",["name"]="老师"},["visual_theme"]={["accent"]="#B4412C",["door"]="#C3563B",["key"]="blueprint",["name"]="蓝晒图 · 靛青网格 / 朱红批注（7×7 专属）",["room_colors"]={"#DCE7EF","#CBDDEA","#BFD2E4","#E1E7EC"},["wall"]="#1B3A56"},["walls"]={{"v",1,4},{"v",2,4},{"h",3,3},{"v",3,4},{"h",3,4},{"h",3,5},{"h",3,6},{"h",3,7},{"h",4,1},{"v",4,2},{"h",4,2},{"v",5,2},{"v",6,2},{"v",7,2}},["water"]={}}
end

__M["levels.case_007"] = function()
return {["blocked"]={},["clues"]={{["type"]="beside_object",["who"]="C",["object"]="桌子"},{["type"]="above",["a"]="C",["b"]="B",["same_column"]=false},{["type"]="same_room",["a"]="B",["b"]="C"},{["object"]="桌子",["type"]="beside_object",["who"]="D"},{["type"]="left_of",["a"]="E",["b"]="D",["same_row"]=false},{["type"]="on_object",["who"]="B",["object"]="椅子"}},["difficulty"]="hard",["doors"]={{"h",4,5},{"v",3,3},{"v",2,2},{"v",5,2},{"v",4,1}},["general_clues"]={{["n"]=2,["object"]="椅子",["type"]="n_on_object"}},["hint_preview"]={{["rule"]="该家具四邻、同区域、可站人的格",["cells"]={"2:5","3:1","3:3","3:4","4:2","4:5","5:1"},["count"]=7},{["rule"]="不做位置提示",["cells"]={},["count"]=0},{["rule"]="不做位置提示",["cells"]={},["count"]=0},{["rule"]="该家具四邻、同区域、可站人的格",["cells"]={"2:5","3:1","3:3","3:4","4:2","4:5","5:1"},["count"]=7},{["rule"]="不做位置提示",["cells"]={},["count"]=0},{["rule"]="该家具自己的格子",["cells"]={"1:5","4:5","5:1","6:6"},["count"]=4}},["id"]="case_007",["meta"]={["announce"]="unknown",["false_clue"]=2},["name"]="案件 007 · 藏卷回声",["objects"]={["地毯"]={["cells"]={{["c"]=4,["r"]=2},{["c"]=4,["r"]=3},{["c"]=3,["r"]=2}},["kind"]="carpet",["occupiable"]=true},["桌子"]={["cells"]={{["c"]=1,["r"]=4},{["c"]=3,["r"]=4},{["c"]=5,["r"]=3}},["kind"]="table",["occupiable"]=false},["椅子"]={["cells"]={{["c"]=6,["r"]=6},{["c"]=5,["r"]=4},{["c"]=1,["r"]=5},{["c"]=5,["r"]=1}},["kind"]="chair",["occupiable"]=true},["植物"]={["cells"]={{["c"]=6,["r"]=3}},["kind"]="plant",["occupiable"]=false}},["roles"]={["thief"]="B"},["room_names"]={"R1","R2","R3","R4"},["rules"]={["one_per_col"]=true,["one_per_room"]=false,["one_per_row"]=true,["place_all"]=true,["tie_policy"]="forbid"},["size"]={["cols"]=6,["rows"]=6},["solution"]={["A"]={["c"]=6,["r"]=2},["B"]={["c"]=5,["r"]=1},["C"]={["c"]=4,["r"]=3},["D"]={["c"]=2,["r"]=4},["E"]={["c"]=1,["r"]=5},["V"]={["c"]=3,["r"]=6}},["suspects"]={{["id"]="A",["name"]="管理员",["portrait"]="portrait.A"},{["id"]="B",["name"]="读者",["portrait"]="portrait.B"},{["id"]="C",["name"]="作家",["portrait"]="portrait.C"},{["id"]="D",["name"]="编辑",["portrait"]="portrait.D"},{["id"]="E",["name"]="清洁工",["portrait"]="portrait.E"},{["id"]="V",["is_victim"]=true,["name"]="馆长",["portrait"]="portrait.V"}},["victim"]={["id"]="V",["name"]="馆长"},["visual_theme"]={["accent"]="#7C5A22",["door"]="#B9913F",["key"]="sepia-rotated",["name"]="旋转档案 · 深墨绿/铜金",["room_colors"]={"#DDE4D5","#CFD9C8","#D8D3BE","#C6D2D2"},["wall"]="#20342C"},["walls"]={{"v",1,2},{"v",2,2},{"h",2,2},{"h",2,3},{"v",3,1},{"v",3,3},{"v",4,1},{"h",4,3},{"v",4,3},{"h",4,4},{"h",4,5},{"h",4,6},{"v",5,1},{"h",5,1},{"v",5,2},{"v",6,2}},["water"]={}}
end

-- ==== 入口：官方生命周期回调（OnInit / OnStart / OnUpdate / ...）==== --
local FORCE_LEVEL = nil
if print then print("[murdoku] ===== 构建标记 v756 / 清理失效教程控件 =====") end
local Murdoku, Qianxing
local LOAD_ERR = nil
local ok1,err1 = pcall(function() Murdoku = __require("main") end)
if not ok1 then LOAD_ERR = "main: "..tostring(err1) end
if LOAD_ERR == nil then
  local ok2,err2 = pcall(function() Qianxing = __require("engine_adapter_qianxing") end)
  if not ok2 then LOAD_ERR = "adapter: "..tostring(err2) end
end
local adapter   = nil
local started   = false
local tree_dumped = false
local RETRY_INTERVAL = 0.5
local RETRY_LIMIT    = 60       
local retry_elapsed  = 0
local retry_tries    = 0
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
local BEACON = { OnInit = 300, OnStart = 380 }
local function beacon(a, v)
  if a == nil then return end
  if a.cells_beacon == false then return end
  if a.cfg ~= nil and a.cfg.cells_beacon == false then return end
  if a._cells_beacon_button ~= nil then
    pcall(function() a:_cells_beacon_button(v) end)
  end
  if a._cells_signal ~= nil then
    pcall(function() a:_cells_signal(v) end)
  end
end
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
      if print then
        print("[murdoku] ===== 构建标记 v756 / 清理失效教程控件 =====")
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
local function build_adapter()
  if LOAD_ERR ~= nil then error("模块加载失败：" .. tostring(LOAD_ERR)) end
  adapter = Qianxing.new({
    apply_rect = false,
    verbose    = false,
    prefab_of = {
      ["action.back.hexbg"] = 1073742333,
      ["action.redo.hexbg"] = 1073742333,
      ["action.hint.hexbg"] = 1073742333,
      ["home.panel"]   = 1073742337,
      ["select.panel"] = 1073742337,
    },
    parent_of = {
      ["action.back.hexbg"] = "action.back",
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
    cells_beacon = false,
    auto_create = false,    
    prefab_icon = 1073742357,
    text_editor_first = {
      "home.select", "home.continue", "home.shop", "home.bag",
      "settle.btn",
      "modal.exit", "modal.save", "modal.settle", "modal.cancel",
      "result.next", "result.exit", "result.home", "result.settle",
      "clues.up", "clues.down",
      "win.1", "win.2", "win.3", "win.4",
      "result.title.1", "result.title.2", "result.title.3",
      "result.msg.1", "result.msg.2", "result.msg.3",
    },
    widgets     = false,    
    stage = {
      prefab = 1073742330,    
      parent = "stage",
      selbar = "selbar",      
    },
    cells = {
      prefab   = 1073741876,
      ruler    = 12,            
      gap      = 4,             
      face_image = 100001,
      probe    = "cell.1.1",
      parent   = "stage",
      rows     = 7,             
      cols     = 7,
      debug_signal = false,
      auto_scan = true,
      edge_thickness = 10,
      door_length_ratio = 0.44,
      edge_overlap = 4,
      edge_extra_len = 4,
      edge_fit_log = true,
      layer_order = {
        "face",
        "hint",
        "obj",
        "obj2", "obj3", "obj4", "obj5", "obj6",
        "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",
        "rug_layer", "furn",
        "portrait",
        "wall.up", "wall.down", "wall.left", "wall.right",
        "door.up", "door.down", "door.left", "door.right",
        "x",
        "note",
      },
    },
    respect_editor_rect = true,
    furn_prim_prefab = 1073746302,
    furn_prim_cap = 260,
    furn_tpl_prefab = {
      chair    = 1073747134,
      plant    = 1073747135,
      plant_2  = 1073753953,  
      statue   = 1073747136,
      table    = 1073747137,
      table_h2 = 1073747138,
      table_v2 = 1073747139,
      shelf    = 1073747140,
      rug      = 1073747149,
      rug_2    = 1073748252,
      rug_3    = 1073749968,
      rug_4    = 1073760711,
      rug_5    = 1073760734,
    },
    furn_parent = "fart.furn",    
    furn_tpl_base = 108,
    furn_scale = 0.93,
    furn_scale_by_kind = { rug = 0.82, rug_2 = 0.82, rug_3 = 0.82, statue = 0.85 },
    furn_scale_axis_by_kind = {
      rug_2 = { x = 0.93, y = 0.762 },
      rug_3 = { x = 0.762, y = 0.93 },
      rug_4 = { x = 1, y = 1 },
      rug_5 = { x = 1, y = 1 },
    },
    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 },
                       rug_4 = { 216, 216 }, rug_5 = { 216, 216 },
                       table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },
    tpl_probe = false,
    tpl_probe_ref_name = "furn",       
    tpl_probe_plant_src = 1073747081,    
    tpl_probe_nest_src = 1073747096,     
    tpl_probe_parent = "board",          
    obj_art = {
      table = {    
        { id = 100001, color = 0xFF4A3524, w = 0.9, h = 0.64 },
        { id = 100001, color = 0xFFD4CCA0, w = 0.82, h = 0.56 },
        { id = 100001, color = 0xFFE8E2C0, w = 0.72, h = 0.46 },
      },
      chair = {    
        { id = 106053, color = 0xFF4A3A2A, w = 0.74, h = 0.76, dy = 0.04 },
        { id = 106053, color = 0xFFF2EBD4, w = 0.66, h = 0.5, dy = 0.13 },
        { id = 100001, color = 0xFFCBBE97, w = 0.62, h = 0.2, dy = -0.16 },
      },
      carpet = {    
        { id = 100001, color = 0xFF9C8A63, w = 0.92, h = 0.92 },
        { id = 100001, color = 0xFFDCCBAA, w = 0.84, h = 0.84 },
      },
      plant = {    
        { id = 100002, color = 0xFF3E7D3A, w = 0.64, h = 0.52, dy = -0.08 },
        { id = 106053, color = 0xFF8A6A48, w = 0.32, h = 0.24, dy = 0.26 },
        { id = 100002, color = 0xFF58A046, w = 0.34, h = 0.26, dy = -0.2 },
      },
      shelf = {    
        { id = 100001, color = 0xFF4A3524, w = 0.82, h = 0.66 },
        { id = 100001, color = 0xFFB4874F, w = 0.76, h = 0.6 },
        { id = 100001, color = 0xFF4A2E17, w = 0.68, h = 0.07, dy = -0.05 },
      },
      statue = {    
        { id = 100001, color = 0xFF4E4E56, w = 0.54, h = 0.24, dy = 0.28 },
        { id = 105090, color = 0xFFC9C9D2, w = 0.6, h = 0.5, dy = 0.02 },
        { id = 100002, color = 0xFFE2E2E8, w = 0.14, h = 0.1, dy = -0.22 },
      },
    },
    debug_key   = false,    
    debug_image = false,    
    debug_event = false,    
    tray_parent = "tray",
    key_control = "root",
    key_control_fallbacks = { "stage", "cell.1.1", "topbar" },
  })
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
  __murdoku_debug = { adapter = adapter, Murdoku = Murdoku, beacon = beacon }
  return adapter
end
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
    n = -1      
  end
  if printerr then
    if n == 0 then
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
local keyboard_bound = false
local KEY_SPEC = {
  "KeyboardCraftspersonKey36Down", "KeyboardCraftspersonKey37Down",
  "KeyboardCraftspersonKey38Down", "KeyboardCraftspersonKey39Down",
  "KeyboardCraftspersonKey1Down",  "KeyboardCraftspersonKey2Down",
  "KeyboardCraftspersonKey3Down",  "KeyboardCraftspersonKey4Down",
  "KeyboardCraftspersonKey5Down",  "KeyboardCraftspersonKey6Down",
  "KeyboardCraftspersonKey7Down",  "KeyboardCraftspersonKey8Down",
  "KeyboardCraftspersonKey9Down",  "KeyboardCraftspersonKey10Down",
  "KeyboardInteractKeyDown",        
  "KeyboardJumpKeyDown",            
  "KeyboardDropKeyDown",            
  "KeyboardCraftspersonKey42Down",  
  "KeyboardOpenShortcutWheelKeyDown",  
  "KeyboardCharacterSkill1KeyDown",    
  "KeyboardCharacterSkill3KeyDown",    
  "KeyboardCraftspersonKey12Down",     
  "KeyboardCraftspersonKey13Down",     
  "KeyboardCraftspersonKey15Down",     
}
local function bind_keyboard_once(where)
  if adapter == nil or keyboard_bound then return false end
  local ok = pcall(function()
    local n, note, complete = adapter:bind_keys(KEY_SPEC)
    keyboard_bound=complete==true
    if n > 0 then
      if print then
        print("[murdoku] 键盘快捷键已绑定 " .. n .. " 个键（PC 可用，移动端忽略）"
          .. "　[" .. tostring(note) .. "]"
          .. (where and where ~= "OnInit" and ("　via " .. where) or ""))
      end
    elseif where == "OnInit" then
      if print then
        print("[murdoku] 键盘快捷键暂未绑定（OnInit 时控件树还没就绪，稍后会自动补绑）")
      end
    else
      if print then
        print("[murdoku] 键盘快捷键没绑上（不影响鼠标/触摸操作）：" .. tostring(note))
        print("[murdoku]   → 想用键盘的话：在 cfg.key_control / key_control_fallbacks 里"
          .. "换一个控件名（必须是**预设按钮**这类支持按键事件的控件）")
      end
    end
  end)
  return ok and keyboard_bound
end
local tutorial_mod_state = nil    
local tutorial_inst = {}          
local tutorial_seen = Murdoku.tutorial_seen          
local TUT_SETS = {
  home = { tag = "home", root = "td.home", text = "td.home", pages = 1, raw_pages = 1 },
  l1   = { tag = "l1",   root = "td.l1",   text = "td.l1",   pages = 4, raw_pages = 8, page_map = { 1, 3, 7, 8 } },
  l2   = { tag = "l2",   root = "td.l2",   text = "td.l2",   pages = 3, raw_pages = 4, page_map = { 2, 3, 4 } },
}
local TUT_TRIGGER = { home = "home", case_001 = "l1", case_002 = "l2" }
local function tutorial_module()
  if tutorial_mod_state ~= nil then
    if tutorial_mod_state == false then return nil end
    return tutorial_mod_state
  end
  local ok, mod = pcall(__require, "tutorial_ui")
  if not ok or type(mod) ~= "table" or type(mod.new) ~= "function" then
    if printerr then printerr("[murdoku] 教程模块没加载上：" .. tostring(mod)) end
    tutorial_mod_state = false      
    return nil
  end
  tutorial_mod_state = mod
  return mod
end
local function tutorial_instance(spec)
  if spec == nil then return nil end
  local inst = tutorial_inst[spec.tag]
  if inst ~= nil then return inst end
  local mod = tutorial_module()
  if mod == nil or adapter == nil then return nil end
  local ok, made = pcall(function()
    local content = (type(mod.CONTENT) == "table") and mod.CONTENT[spec.tag] or nil
    return mod.new(adapter, { tag = spec.tag, root = spec.root, text = spec.text, pages = spec.pages, raw_pages = spec.raw_pages, page_map = spec.page_map, content = content })
  end)
  if not ok or type(made) ~= "table" then
    if printerr then printerr("[murdoku] 教程实例建不出来（" .. tostring(spec.tag) .. "）：" .. tostring(made)) end
    return nil
  end
  tutorial_inst[spec.tag] = made
  return made
end
local function e744_vis(c) return c.visible end
local function e744_act(c) return c.active end
local function e744_set_vis(c, v) if c.SetVisible then c:SetVisible(v) else c.visible = v end end
local function e744_set_act(c, v) if c.SetActive then c:SetActive(v) end end
local function e744_last_sib(c) c:SetAsLastSibling() end
local function e744_get_kids(c) return c:GetChildren() end
local function e744_get_k(c, k) return c[k] end
local function e744_set_k(c, k, v) c[k] = v end
local function e748_help_vis_only(c, v)
  if c.visible ~= v then
    if c.SetVisible then c:SetVisible(v) else c.visible = v end
  end
end
local function e748_help_act_true(c)
  if c.active ~= true and c.SetActive then c:SetActive(true) end
end
local function e745_set_vis_pair(c, want)
  local a, v = c.active, c.visible
  if (a == want or v == want) and a ~= not want and v ~= not want then return true end
  local wrote = false
  if c.SetVisible and v ~= want then c:SetVisible(want); wrote = true end
  local a1 = c.active
  if c.SetActive and a1 ~= want then c:SetActive(want); wrote = true end
  local a2, v2 = c.active, c.visible
  return wrote and (a2 == want or v2 == want) and a2 ~= not want and v2 ~= not want
end
local function e745_pair(c, method)
  local x, y = c[method](c)
  if type(x) == "number" and type(y) == "number" then return x, y end
  if x ~= nil then return x.x or x.X, x.y or x.Y end
  return nil, nil
end
local function e745_transform(c, x, y, s, tol)
  local sx, sy = e745_pair(c, "GetLocalScale")
  local px, py = e745_pair(c, "GetAnchoredPosition")
  if sx and sy and px and py and math.abs(sx - s) < tol and math.abs(sy - s) < tol
     and math.abs(px - x) < tol and math.abs(py - y) < tol then
    return true
  end
  if not px or not py or math.abs(px - x) >= tol or math.abs(py - y) >= tol then c:SetAnchoredPosition(x, y) end
  if not sx or not sy or math.abs(sx - s) >= tol or math.abs(sy - s) >= tol then c:SetLocalScale(s, s, 1) end
  local a, b = e745_pair(c, "GetLocalScale")
  local rx, ry = e745_pair(c, "GetAnchoredPosition")
  return a and b and rx and ry and math.abs(a - s) < .002 and math.abs(b - s) < .002
     and math.abs(rx - x) < .002 and math.abs(ry - y) < .002
end
local function e745_set_pos(c, x, y) c:SetAnchoredPosition(x, y) end
local function e745_set_font(c, size) c.adaptiveFontSize = false; c.minimumFontSize = size; c.fontSize = size end
local function tut_visible(name)
  if adapter == nil or name == nil then return false end
  local c = adapter.controls and adapter.controls[name] or nil
  if c == nil then
    local ok_f, res_f = pcall(adapter.find, adapter, name)
    if not ok_f or res_f == nil then return false end
    c = res_f
  end
  local ok_v, v = pcall(e744_vis, c)
  return ok_v and v == true
end
local function tutorial_home_visible()
  return tut_visible("home")
end
-- 745：移除存档中已废弃不存在的 "board"（由 clues / stage 覆盖），根治每 1~16s 因永远 miss 触发的 8,578 节点全树重扫！
local TUT_PROBE_NAMES = { "home", "select.card.1", "select.title", "clues", "stage" }
local TUT_PREWARM_AFTER = 60  
local tut_prewarm_frames = 0
local tut_prewarm_done = false
local TUT_STABLE_NEED = 20    
local TUT_KEEP_NEED = 10      
local tut_key_prev = nil
local tut_key_frames = 0
local tut_shown_frames = 0
local tut_key_logged = false  
local tut_miss_frames = {}    
local tut_probe_buf745 = {}
local function tut_key_and_probe()
  local cur = (Murdoku ~= nil and Murdoku.current ~= nil) and Murdoku.current() or nil
  local home  = tut_visible("home")
  local card1 = tut_visible("select.card.1")
  if not card1 then card1 = tut_visible("select.title") end
  local clues = tut_visible("clues")
  local board = false
  local scr, id = nil, nil
  if cur ~= nil then
    scr = cur.screen
    local lv = cur.level
    if lv ~= nil then id = lv.id end
  end
  local key = nil
  if cur ~= nil then
    if home then
      key = "home"
    elseif card1 then
      key = nil
    elseif clues then
      if id ~= nil then key = tostring(id) end
    end
  end
  local p = tut_probe_buf745
  p.home, p.card1, p.clues, p.board, p.scr, p.id = home, card1, clues, board, scr, id
  return key, p
end
local tut_last_probe = nil
local function current_tut_key()
  local key, probe = tut_key_and_probe()
  tut_last_probe = probe
  return key
end
local help617 = { bound = false, entry_bound = false, close_bound = false, open = false, overlay = false }
local function help_visible(c, v)
  if c == nil then return false end
  local w = v and true or false
  local ok_v = pcall(e748_help_vis_only, c, w)
  if w then pcall(e748_help_act_true, c) end
  return ok_v == true
end
local function help_write(c, v)
  if c == nil then return end
  pcall(function() if c.SetText then c:SetText(v) else c.text = v end end)
end
local function overlay_open()
  for _, spec in pairs(TUT_SETS) do
    local inst = tutorial_inst[spec.tag]
    if inst ~= nil and inst.open then return true end
  end
  return help617.open == true
end
local HOME_TUTORIAL_CONTROLS = { "home.tutorial627.bg", "home.tutorial627.ring", "home.tutorial627.label", "home.tutorial627.hit" }
local function sync_home_tutorial628(want)
  local c = help617.controls or {}
  local complete = true
  for _, name in ipairs(HOME_TUTORIAL_CONTROLS) do
    if c[name] == nil then c[name] = adapter:find(name) end
    if c[name] == nil then complete = false else help_visible(c[name], want) end
  end
  help617.controls = c
  help617.home_visible = complete and want or nil
end
local function bind_help617()
  if adapter == nil then return end
  local generation = adapter._lookup_gen or 0
  if help617.generation ~= generation then
    if help617.close then help617.close() end
    help617.generation = generation
    help617.bound, help617.entry_bound, help617.close_bound = false, false, false
    help617.controls = {}
    help617.initialized, help617.entry_visible = false, nil
    help617.home_bound, help617.home_visible = false, nil
  end
  if help617.bound and help617.home_bound then return end
  local util = tutorial_instance(TUT_SETS.l1)
  if util == nil then return end
  help617.controls = help617.controls or {}
  local c = help617.controls
  for _, name in ipairs({ "clues.help617", "clues.help627.hit", "home.tutorial627.hit", "help617", "help617.title", "help617.body", "help617.close", "help617.close.hit", "help617.bg" }) do
    if c[name] == nil then c[name] = adapter:find(name) end
  end
  local function close()
    help_visible(c["help617"], false)
    help617.open = false
  end
  help617.close = close
  if not help617.initialized and c["help617"] ~= nil then
    help617.initialized = true
    close()
    for _, name in ipairs({ "help617.title", "help617.body", "help617.close", "help617.close.hit", "help617.bg" }) do help_visible(c[name], true) end
    pcall(function() c["help617"].showCursor = true end)
    pcall(function() c["help617"].disableCursorEventPassthrough = true end)
    pcall(function() c["help617"].disableKeyEventPassthrough = true end)
  end
  if not help617.close_bound and c["help617.close.hit"] ~= nil then
    help617.close_bound = util:_bind("help617.close.hit", close, c["help617.close.hit"], c)
  end
  if not help617.entry_bound and c["clues.help627.hit"] ~= nil then
    help617.entry_visible = nil
    help617.entry_bound = util:_bind("clues.help627.hit", function()
      local cur = Murdoku.current()
      local id = cur and cur.level and cur.level.id
      if not cur or not cur.controller or not id or cur.controller.modal ~= nil or overlay_open() then return end
      if current_tut_key() ~= tostring(id) then return end
      local tag = TUT_TRIGGER[id]
      if tag then
        local inst = tutorial_instance(TUT_SETS[tag])
        if inst then
          inst:init()
          Murdoku.record_tutorial(tag)
          inst:go(1)
          inst:open_ui()
          if inst.open then cur.controller:dismiss_action_confirm() end
        end
        return
      end
      if c["help617"] == nil or c["help617.body"] == nil then return end
      local yes, no = {}, {}
      for name, obj in pairs((cur.level and cur.level.objects) or {}) do
        local target = obj.occupiable and yes or no
        target[#target + 1] = tostring(name)
      end
      table.sort(yes); table.sort(no)
      help_write(c["help617.title"], (cur.level and cur.level.name or "本关") .. " · 注释")
      help_write(c["help617.body"], "可站人的家具：" .. (#yes > 0 and table.concat(yes, "、") or "无") .. "。\n\n不可站人的家具：" .. (#no > 0 and table.concat(no, "、") or "无") .. "。")
      help617.level = id
      help617.open = true
      cur.controller:dismiss_action_confirm()
      help_visible(c["help617"], true)
    end, c["clues.help627.hit"], c)
  end
  if help617.entry_bound and help617.logged_generation ~= generation then
    help617.logged_generation = generation
  end
  if not help617.home_bound and c["home.tutorial627.hit"] ~= nil then
    help617.home_bound = util:_bind("home.tutorial627.hit", function()
      local cur = Murdoku.current()
      if current_tut_key() ~= "home" or overlay_open() or (cur and cur.controller and cur.controller.modal ~= nil) then return end
      local inst = tutorial_instance(TUT_SETS.home)
      if inst then
        inst:init()
        Murdoku.record_tutorial('home')
        inst:go(1)
        inst:open_ui()
      end
    end, c["home.tutorial627.hit"], c)
  end
  help617.bound = help617.entry_bound and help617.close_bound
end
local HINT635_NAMES={"hint635.menu","hint635.result","hint635.menu.bg","hint635.menu.title",
  "hint635.menu.position","hint635.menu.clue","hint635.menu.close",
  "hint635.result.bg","hint635.result.body","hint635.result.close",
  "hint635.menu.position.hit","hint635.menu.clue.hit","hint635.menu.close.hit","hint635.result.close.hit"}
local HINT635_ACTIONS={["hint635.menu.position.hit"]="position",["hint635.menu.clue.hit"]="clue",
  ["hint635.menu.close.hit"]="close",["hint635.result.close.hit"]="close"}
local HINT635_ZERO_USED={position=0,clue=0}
local hint635_ui={}
local function tick_hint635()
  if not adapter then return end
  local gen=adapter._lookup_gen or 0
  if hint635_ui.generation~=gen then hint635_ui={generation=gen,controls={},bound={},all_ready=false} end
  local h=hint635_ui
  if not h.all_ready then
    local util=tutorial_instance(TUT_SETS.l1)
    if not util then return end
    local ready=true
    for i=1,#HINT635_NAMES do
      local name=HINT635_NAMES[i]
      if not h.controls[name] then
        h.controls[name]=adapter:find(name)
        if h.controls[name] then help_visible(h.controls[name],name~="hint635.menu" and name~="hint635.result") else ready=false end
      end
    end
    for name,action in pairs(HINT635_ACTIONS) do
      if not h.bound[name] then
        if h.controls[name] then
          local chosen=action
          h.bound[name]=util:_bind(name,function()
            local c=Murdoku.current()
            if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
          end,h.controls[name],h.controls)
        end
        if not h.bound[name] then ready=false end
      end
    end
    h.all_ready=ready
  end
  local cur=Murdoku.current()
  local ctrl=cur and cur.controller
  if ctrl and (ctrl.screen~=nil or ctrl.modal~=nil or overlay_open()) then ctrl.hint635=nil end
  local state=ctrl and ctrl.hint635
  local used=ctrl and ctrl.core and ctrl.core.hint635_used or HINT635_ZERO_USED
  -- 745：关闭态且上次已同步为同控制器关闭态时零分配早退。
  if state==nil and h.closed_ok==true and h.controller==ctrl and h.closed_pos==used.position and h.closed_clue==used.clue then
    return
  end
  local signature=state and (state.kind..":"..(state.text or "")) or "closed"
  signature=signature..":"..tostring(used.position)..":"..tostring(used.clue)
  local function stock(totalUsed,entryUsed,total)
    if totalUsed==nil or entryUsed==nil then return '（…/…）' end
    return '（'..math.max(0,totalUsed-entryUsed)..'/'..total..'）'
  end
  if state and state.kind=='menu' and (used.clue>=2 or used.position>=1) then
    local a=cur.adapter
    if not cur.ticket_entry then Murdoku.begin_ticket_visit() end
    local entry=cur.ticket_entry
    if not h.stockClue or h.stockSlot~=a._confirmed or h.stockEntry~=entry or h.stockReady~=a._archive_ready then
      local _,_,_,_,_,_,_,usedClues,usedPositions=Murdoku.wallet()
      h.stockClue=stock(usedClues,entry and entry.used,entry and entry.clues)
      h.stockPosition=stock(usedPositions,entry and entry.pos_used,entry and entry.positions)
      h.stockSlot=a._confirmed; h.stockReady=a._archive_ready; h.stockEntry=entry
    end
    signature=signature..h.stockClue..h.stockPosition
  end
  local title="提示"
  if h.signature~=signature or h.controller~=ctrl then
    h.signature=signature;h.controller=ctrl
    h.closed_ok=(state==nil); h.closed_pos=used.position; h.closed_clue=used.clue
    help_visible(h.controls["hint635.menu"],state~=nil and state.kind=="menu")
    help_write(h.controls["hint635.menu.title"],title)
    help_visible(h.controls["hint635.result"],state~=nil and state.kind=="message")
    help_write(h.controls["hint635.menu.position"],used.position>=1 and ("使用位置揭示券"..(h.stockPosition or "（…/…）")) or "揭示选中人物的所在位置（1/1）")
    help_write(h.controls["hint635.menu.clue"],(used.clue>=2 and ("使用核验券"..(h.stockClue or "（…/…）")) or nil) or "验证选中线索的真假（"..tostring(2-used.clue).."/2）")
    help_write(h.controls["hint635.result.body"],state and state.text or "")
  end
end
local function tick_tutorial()
  tick_hint635()
  bind_help617()
  if help617.open then
    local cur = Murdoku.current()
    if not cur or not cur.controller or cur.controller.screen ~= nil or cur.controller.modal ~= nil or not cur.level or cur.level.id ~= help617.level then help617.close() end
  end
  if adapter == nil then return end
  if tutorial_module() == nil then return end
  for _, spec in pairs(TUT_SETS) do
    local inst = tutorial_instance(spec)
    if inst ~= nil and not inst.inited then
      pcall(function() inst:init() end)
    end
  end
  local key, probe = nil, nil
  if started then
    key = current_tut_key()           
    probe = tut_last_probe            
  end
  local help_cur = Murdoku.current()
  local help_want = started and help_cur ~= nil and help_cur.level ~= nil and help_cur.level.id ~= nil
    and help_cur.controller ~= nil and help_cur.controller.screen == nil
  if help617.entry_visible ~= help_want and help617.controls and help617.controls["clues.help617"] then
    help_visible(help617.controls["clues.help617"], help_want)
    help_visible(help617.controls["clues.help627.hit"], help_want)
    help617.entry_visible = help_want
  end
  local home_want = key == "home" and not overlay_open()
    and not (help_cur and help_cur.controller and help_cur.controller.modal ~= nil)
  if help617.home_visible ~= home_want then
    sync_home_tutorial628(home_want)
  end
  local key_changed = (key ~= tut_key_prev)
  if not key_changed then
    tut_key_frames = tut_key_frames + 1
  else
    tut_key_prev = key
    tut_key_frames = 0
    tut_shown_frames = 0
  end
  if print and probe ~= nil and (key_changed or not tut_key_logged) then
    tut_key_logged = true
    print("[tutorial] 触发键 -> " .. tostring(key)
      .. "  (home=" .. tostring(probe.home)
      .. " card1=" .. tostring(probe.card1)
      .. " clues=" .. tostring(probe.clues)
      .. " board=" .. tostring(probe.board)
      .. " scr=" .. tostring(probe.scr) .. ")")
  end
  local want_tag = nil
  if adapter and adapter._archive_ready and key ~= nil and tut_key_frames >= TUT_STABLE_NEED then want_tag = TUT_TRIGGER[key] end
  for tag, spec in pairs(TUT_SETS) do
    local inst = tutorial_inst[spec.tag]
    if inst ~= nil and inst.inited then
      if want_tag == tag then
        tut_miss_frames[tag] = 0
        if not tutorial_seen[tag] then
          if not inst.open then
            pcall(function() inst:open_ui() end)
          end
          tut_shown_frames = tut_shown_frames + 1
          if inst.open then Murdoku.record_tutorial(tag) end
        end
      else
        tut_miss_frames[tag] = (tut_miss_frames[tag] or 0) + 1
        if inst.open and tut_miss_frames[tag] >= TUT_KEEP_NEED then
          pcall(function() inst:close() end)
          tut_miss_frames[tag] = 0
        end
      end
    end
  end
  if started then
    tut_prewarm_frames = tut_prewarm_frames + 1
    if tut_prewarm_frames >= TUT_PREWARM_AFTER and not key_changed and not tut_prewarm_done then
      local all_done = true
      for _, spec in pairs(TUT_SETS) do
        local inst = tutorial_inst[spec.tag]
        if inst ~= nil and inst.inited and inst.prewarm ~= nil and not inst.open then
          local ok, done = pcall(function() return inst:prewarm(1) end)
          if not (ok and done) then all_done = false; break end
        elseif inst == nil or not inst.inited then
          all_done = false
        end
      end
      tut_prewarm_done = all_done
    end
  end
end
local BLOCK640 = {
  { tag = "confirm", targets = { "hex.ok", "hex.no", "hit.ok", "hit.no" } },
  { tag = "modal", targets = { "modal" } },
  { tag = "home", targets = { "td.home" } },
  { tag = "l1", targets = { "td.l1" } },
  { tag = "l2", targets = { "td.l2" } },
}
local block640_silent655 = setmetatable({}, { __mode = "k" })
local block640_silent_gen655 = -1
-- 689：控件句柄随 _lookup_gen 缓存；只要有一项没找到就退回 688 的逐帧查找，
--       保证首帧 / 控件树重建时绑定不丢失。每帧的显隐、静音、抬层逻辑逐行保持。
local function e748_set_bool_if(panel, k, want)
  if panel[k] ~= want then panel[k] = want end
end
local function e748_set_k_block640(panel)
  local ok1 = pcall(e748_set_bool_if, panel, "showCursor", true)
  local ok2 = pcall(e748_set_bool_if, panel, "disableCursorEventPassthrough", true)
  local ok3 = pcall(e744_last_sib, panel)
  return ok1 and ok2 and ok3
end
local block640_cache = nil
local block640_cache_gen = -1
local function sync_block640()
  if not adapter then return end
  local util = tutorial_instance(TUT_SETS.l1)
  if not util then return end
  local cur = Murdoku.current()
  local ctrl = cur and cur.controller
  local gen = adapter._lookup_gen or 0
  if block640_cache == nil or block640_cache_gen ~= gen then
    block640_cache = {}
    block640_cache_gen = gen
    for i, spec in ipairs(BLOCK640) do
      block640_cache[i] = { spec = spec, name = "block640." .. spec.tag }
    end
  end
  local cache = block640_cache
  if not cache.complete then
    local ready = true
    for _, e in ipairs(cache) do
      e.panel = e.panel or adapter:find(e.name)
      e.hit = e.hit or adapter:find(e.name .. ".hit")
      if not e.panel or not e.hit then ready = false end
    end
    cache.shade = cache.shade or adapter:find("game742.shade")
    if not cache.shade then ready = false end
    cache.complete = ready
  end
  local shade_raised751 = false
  local shade751 = cache.shade
  if shade751 ~= nil then
    local tut_open751 = false
    for _, tag in ipairs({ "home", "l1", "l2" }) do
      local ti = tutorial_inst[tag]
      if ti ~= nil and ti.open == true then tut_open751 = true; break end
    end
    local modal_shade751 = (ctrl ~= nil and ctrl.modal ~= nil
      and (ctrl.modal.kind == "exit_menu" or (ctrl.modal.kind == "result" and ctrl.modal.win == true)))
    local want_shade751 = tut_open751 or modal_shade751
    local stick = (cache.shade_tick751 or 0) + 1
    cache.shade_tick751 = stick
    local cur_vis751 = cache.last_shade751
    if want_shade751 or cache.last_shade751 then
      pcall(function() cur_vis751 = (shade751.visible == true) end)
    end
    if cache.last_shade751 ~= want_shade751 or cur_vis751 ~= want_shade751 or (want_shade751 and (stick % 60 == 0)) then
      local ok_sh = help_visible(shade751, want_shade751)
      if want_shade751 then
        pcall(e748_set_bool_if, shade751, "raycastTarget", false)
        if pcall(e744_last_sib, shade751) then
          shade_raised751 = true
        else
          ok_sh = false
        end
      end
      cache.last_shade751 = ok_sh and want_shade751 or nil
    end
  end
  for _, e in ipairs(cache) do
    local spec, name, panel, hit = e.spec, e.name, e.panel, e.hit
    local want = false
    if spec.tag == "modal" then
      want = ctrl ~= nil and ctrl.modal ~= nil
      -- 654: 兼容旧退出状态；独立选关页不启用旧式选关遮罩。
      if want and ctrl.modal.kind == "levelselect" and (ctrl.screen == "select" or ctrl.screen == "home") then want = false end
    elseif spec.tag == "confirm" then
      want = false
      local pend = ctrl and ctrl.pending or nil
      if e.hit_hidden745 ~= hit then
        if help_visible(hit, false) then e.hit_hidden745 = hit end
      end
      -- 748（B4/U10）：确认条仅在玩家打开确认条（pend~=nil）的 1~3 秒内活跃且仅 4 个按钮；
      -- 关闭态（pend==nil）严格 0 开销，打开态每帧用缓存句柄置顶，杜绝确认键被压在底层。
      if pend ~= nil then
        e.target_ctrls748 = e.target_ctrls748 or {}
        for ti = 1, #spec.targets do
          local button = e.target_ctrls748[ti]
          if button == nil then
            button = adapter:find(spec.targets[ti])
            e.target_ctrls748[ti] = button
          end
          if button then
            if not pcall(e744_last_sib, button) then
              e.target_ctrls748[ti] = nil
            end
          end
        end
      end
      e.last_pend745 = pend
    else local inst = tutorial_inst[spec.tag]; want = inst ~= nil and inst.open == true end
    -- 689：_bind 内部首行即「已绑定则立即返回」，收进未绑定分支后行为等价，
    --       但稳态帧不再创建 5 个空闭包、也不再重复调用。
    if spec.tag ~= "confirm" and hit ~= nil and not util.bound[hit] then
      help_visible(hit, true)
      util:_bind(name .. ".hit", function() end, hit)
    end
    want = not not want
    if hit ~= nil then
      local _g655 = adapter._lookup_gen or 0
      if block640_silent_gen655 ~= _g655 then
        block640_silent655 = setmetatable({}, { __mode = "k" })
        block640_silent_gen655 = _g655
      end
      if not block640_silent655[hit] then
        pcall(function() if hit.clickAudioId ~= 0 then hit.clickAudioId = 0 end end)
        block640_silent655[hit] = true
      end
    end
    if want and panel and (spec.tag == 'l1' or spec.tag == 'l2' or spec.tag == 'home' or spec.tag == 'modal') then
      local ok, width, height = pcall(function() return game.GetUICanvasSize() end)
      if ok and type(width)=='number' and type(height)=='number' and width>0 and height>0 then
        if spec.tag == 'modal' then
          local sy = math.max(1, (1600 * height / width + 8) / 900)
          local sx = 1608 / 1600
          if e.coverY ~= sy then
            if pcall(function() panel:SetLocalScale(sx, sy, 1) end) then e.coverY = sy end
          end
        else
          local sy = (1600*height/width+8)/4096
          if e.coverY ~= sy then
            if pcall(function() panel:SetLocalScale(1608/2048,sy,1) end) then e.coverY=sy end
          end
        end
      end
    elseif not want then e.coverY=nil end
    local btick = (e.tick745 or 0) + 1
    e.tick745 = btick
    if e.last_want745 ~= want or (want and shade_raised751) or (btick % 60 == 0) then
      local ok_all = (panel == nil) or help_visible(panel, want)
      if want and panel then
        if not e748_set_k_block640(panel) then ok_all = false end
        e.target_ctrls748 = e.target_ctrls748 or {}
        for ti = 1, #spec.targets do
          local c = e.target_ctrls748[ti]
          if c == nil then
            c = adapter:find(spec.targets[ti])
            e.target_ctrls748[ti] = c
          end
          if c then
            if not pcall(e744_last_sib, c) then
              ok_all = false
              e.target_ctrls748[ti] = nil
            end
          else
            ok_all = false
          end
        end
      end
      if want and spec.tag == 'modal' then
        local win_c = adapter:find('win')
        if win_c ~= nil then
          pcall(function() win_c.raycastTarget = false; win_c.blockRaycast = false end)
        end
        for _, bnm in ipairs({'result.next','result.exit','result.home','result.settle','modal.exit','modal.save','modal.settle','modal.cancel'}) do
          local bc = adapter:find(bnm)
          if bc ~= nil then pcall(e744_last_sib, bc) end
        end
      end
      e.last_want745 = ok_all and want or nil
    end
  end
end
-- ADAPT715R BEGIN
local ADAPT715R_HOME_COLOR = 4290136608
local ADAPT715R_SELECT_COLOR = 4279438859
-- 746（P2-1）：记录每组撕边在存档中的真实子叶数（合计 591 叶），避免首批不完整快照被提前缓存为稳态。
-- 748（U11）：由 build_748.mjs 在构建期从真实 .gil 树自动推导写入，消除手写魔数。
local ADAPT715R_TEARS = {{name="adapt715r.TR.23",side="tr",expect=141},{name="adapt715r.TR.24",side="tr",expect=183},{name="adapt715r.TR.25",side="tr",expect=17},{name="adapt715r.BR.26",side="bl",expect=79},{name="adapt715r.BR.27",side="bl",expect=150},{name="adapt715r.BR.28",side="bl",expect=21}}
local ADAPT715R_BG_LEAVES = 649
local ADAPT715R_TARGETS = {
  {name="adapt715r.LM.1",kind="LM",ax=0,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.TL.2",kind="TL",ax=0,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.TR.3",kind="TR",ax=1,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.BR.4",kind="BR",ax=1,ay=0,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.TL.5",kind="TL",ax=0,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.TR.6",kind="TR",ax=1,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.BR.7",kind="BR",ax=1,ay=0,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.LM.8",kind="LM",ax=0,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.TL.9",kind="TL",ax=0,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.TR.10",kind="TR",ax=1,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.BR.11",kind="BR",ax=1,ay=0,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.WAX.12",kind="WAX",ax=0.5,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.BR.13",kind="BR",ax=1,ay=0,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.LM.14",kind="LM",ax=0,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.LM.15",kind="LM",ax=0,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.RM.16",kind="RM",ax=1,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.BR.17",kind="BR",ax=1,ay=0,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.BR.18",kind="BR",ax=1,ay=0,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.LM.19",kind="LM",ax=0,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.RM.20",kind="RM",ax=1,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="adapt715r.TL.21",kind="TL",ax=0,ay=1,base={[0]={0,0},[1]={0,-20},[2]={0,0},[3]={0,-20}}},
  {name="adapt715r.LM.22",kind="LM",ax=0,ay=0.5,base={[0]={0,0},[1]={0,0},[2]={0,0},[3]={0,0}}},
  {name="clues",kind="LM",ax=0,ay=0.5,base={[0]={-570,-61.099998474121094},[1]={-570,-61.099998474121094},[2]={-570,-61.099998474121094},[3]={-570,-61.099998474121094}}},
  {name="topbar",kind="LM",ax=0,ay=0.5,base={[0]={0,230.40011596679688},[1]={0,230.40011596679688},[2]={0,230.40011596679688},[3]={0,230.40011596679688}}},
  {name="clues.help617",kind="LM",ax=0,ay=0.5,base={[0]={-416,239},[1]={-416,239},[2]={-416,239},[3]={-416,239}}},
  {name="clues.help627.hit",kind="LM",ax=0,ay=0.5,base={[0]={-416,239},[1]={-416,239},[2]={-416,239},[3]={-416,239}}},
  {name="settle.btn",kind="BR",ax=1,ay=0,base={[0]={683,-279},[1]={683,-279},[2]={683,-279},[3]={683,-279}}},
  {name="settle.btn.countdown",kind="BR",ax=1,ay=0,base={[0]={683,-339},[1]={683,-339},[2]={683,-339},[3]={683,-339}}},
  {name="select.back",kind="TL",ax=0,ay=1,base={[0]={-704.4000244140625,298},[1]={-704.4000244140625,278},[2]={-704.4000244140625,298},[3]={-704.4000244140625,278}}},
  {name="hit.select.back",kind="TL",ax=0,ay=1,base={[0]={-704.4000244140625,298},[1]={-704.4000244140625,278},[2]={-704.4000244140625,298},[3]={-704.4000244140625,278}}},
  {name="hit.select.prev",kind="LM",ax=0,ay=0.5,base={[0]={-738,3},[1]={-738,3},[2]={-738,3},[3]={-738,3}}},
  {name="hit.select.next",kind="RM",ax=1,ay=0.5,base={[0]={726,-2},[1]={726,-2},[2]={726,-2},[3]={726,-2}}},
  {name="hex.back",kind="TL",ax=0,ay=1,base={[0]={-704.4000244140625,298},[1]={-704.4000244140625,278},[2]={-704.4000244140625,298},[3]={-704.4000244140625,278}}},
  {name="hex.submit",kind="TR",ax=1,ay=1,base={[0]={704.4000244140625,298},[1]={704.4000244140625,278},[2]={704.4000244140625,298},[3]={704.4000244140625,278}}},
  {name="hex.redo",kind="TR",ax=1,ay=1,base={[0]={704.4000244140625,203},[1]={704.4000244140625,183},[2]={704.4000244140625,203},[3]={704.4000244140625,183}}},
  {name="hex.undo",kind="TR",ax=1,ay=1,base={[0]={704.4000244140625,108},[1]={704.4000244140625,88},[2]={704.4000244140625,108},[3]={704.4000244140625,88}}},
  {name="hex.hint",kind="BR",ax=1,ay=0,base={[0]={704.4000244140625,-282.1000061035156},[1]={704.4000244140625,-282.1000061035156},[2]={704.4000244140625,-282.1000061035156},[3]={704.4000244140625,-282.1000061035156}}},
  {name="hit.back",kind="TL",ax=0,ay=1,base={[0]={-704.4000244140625,298},[1]={-704.4000244140625,278},[2]={-704.4000244140625,298},[3]={-704.4000244140625,278}}},
  {name="hit.submit",kind="TR",ax=1,ay=1,base={[0]={704.4000244140625,298},[1]={704.4000244140625,278},[2]={704.4000244140625,298},[3]={704.4000244140625,278}}},
  {name="hit.redo",kind="TR",ax=1,ay=1,base={[0]={704.4000244140625,203},[1]={704.4000244140625,183},[2]={704.4000244140625,203},[3]={704.4000244140625,183}}},
  {name="hit.undo",kind="TR",ax=1,ay=1,base={[0]={704.4000244140625,108},[1]={704.4000244140625,88},[2]={704.4000244140625,108},[3]={704.4000244140625,88}}},
  {name="hit.hint",kind="BR",ax=1,ay=0,base={[0]={704.4000244140625,-282.1000061035156},[1]={704.4000244140625,-282.1000061035156},[2]={704.4000244140625,-282.1000061035156},[3]={704.4000244140625,-282.1000061035156}}},
  {name="select.title",kind="EDGE",ax=0.5,ay=1,base={[0]={0,256},[1]={0,256},[2]={0,256},[3]={0,256}}},
  {name="select.page",kind="EDGE",ax=0.5,ay=0,base={[0]={0,-282},[1]={0,-282},[2]={0,-282},[3]={0,-282}}},
}

local function adapt715r_pair(c,method)
  if c==nil then return nil end
  local ok,x,y=pcall(e745_pair,c,method)
  if not ok then return nil end
  return x,y
end
local function adapt715r_device()
  local ok,d=pcall(function() return game.GetDevice() end)
  if not ok or d==nil then return nil,'unavailable' end
  local name=tostring(d)
  pcall(function() name=tostring(d.Name or d.FullName or d) end)
  local low=string.lower(name)
  if low:find('mobilecontroller',1,true) or low:find('controller_mobile',1,true) then return 3,name end
  if low:find('mobile',1,true) or low:find('touch',1,true) then return 1,name end
  if low:find('controller',1,true) or low:find('gamepad',1,true) then return 2,name end
  if low:find('keyboard',1,true) or low=='pc' then return 0,name end
  local found=nil
  pcall(function()
    for _,v in ipairs({{'Keyboard',0},{'Mobile',1},{'Controller',2},{'MobileController',3}}) do
      if Enum and Enum.Device and d==Enum.Device[v[1]] then found=v[2] end
    end
  end)
  return found,name
end
local ADAPT715R_PROFILES = {
  [0] = {{name='PC 16:9',ratio=16/9},{name='PC 21:9',ratio=21/9}},
  [1] = {{name='触屏 16:9',ratio=16/9},{name='触屏 19.5:9',ratio=19.5/9},{name='触屏 4:3',ratio=4/3}},
  [2] = {{name='主机手柄 16:9',ratio=16/9},{name='主机手柄 21:9',ratio=21/9}},
  [3] = {{name='移动手柄 16:9',ratio=16/9},{name='移动手柄 19.5:9',ratio=19.5/9},{name='移动手柄 4:3',ratio=4/3}},
}
local function adapt715r_profile(slot,cw,ch)
  local list=ADAPT715R_PROFILES[slot] or ADAPT715R_PROFILES[0]
  local ratio=cw/ch
  local best,bestd=list[1],math.huge
  for _,p in ipairs(list) do local d=math.abs(ratio-p.ratio);if d<bestd then best,bestd=p,d end end
  return best.name,ratio
end
local ADAPT715R_SELECT_CARDS={'art642.select.paper','art642.select.thread','art642.select.lighting','art642.select.frames'}
local adapt715r={elapsed=1,handles={}}
-- v14：以下函数在适配刷新时被调用，所有长度使用 1600 宽设计空间。
local function adapt14_background(w,h,transform,slot)
  -- 原画 y=45..862 为有效区域。各边保留两个设计单位的采样余量。
  local scene=math.max((w+4)/1600,(h+4)/817)
  local shift=3.5*scene
  transform('adapt715r.background',0,shift,scene)
  if slot==1 or slot==3 then
    local s=math.max((w+4)/1258.5000205039978,(h+4)/795.9999899864197)
    transform('art642.select.backdrop',0.416656494140625*s,-20.833328247070312*s,s)
  else
    transform('art642.select.backdrop',0,0,math.max((w+4)/1600,(h+4)/900))
  end
  return scene,shift
end

local function adapt14_corner(w,h,side)
  local scale=math.min(1.12,w/1600,h/900)
  local sign=side=='tr' and 1 or -1
  local wide=math.min(1,math.max(0,(9*w/h-16)/4))
  local inset=wide*scale
  local ix=side=='tr' and 2 or 16
  local iy=side=='tr' and 12 or 2
  return sign*((w-1600*scale)/2-ix*inset),sign*((h-900*scale)/2-iy*inset),scale
end

local function adapt14_cards(w,h)
  -- 左右各为翻页控件保留 140，另留 16 空隙。四卡实际最外缘距中心 480。
  return math.min(math.max(w/1600,h/900),(w/2-156)/480,h/600)
end
local ADAPT14_PAGER_SPECS747 = {
  {'left','adapt715r.LM.19','hit.select.prev',-1,'lm','prev'},
  {'right','adapt715r.RM.20','hit.select.next',1,'rm','next'},
}
local function adapt14_pagers(find,transform,w,only_keys)
  local failed = nil
  for i=1,#ADAPT14_PAGER_SPECS747 do
    local v = ADAPT14_PAGER_SPECS747[i]
    local want1 = (only_keys == nil or only_keys[v[5]] == true)
    local want2 = (only_keys == nil or only_keys[v[6]] == true)
    if want1 or want2 then
      local art=find('art647.select.diamond.'..v[1])
      local hit=find(v[3])
      local x,y=adapt715r_pair(art,'GetAnchoredPosition')
      local hw,hh=adapt715r_pair(hit,'GetSizeDelta')
      if x and y and hw and hh and hw>0 and hh>0 then
        local center=v[4]*(w/2-12-hw/2)
        if want1 and not transform(v[2],center-x,0,1) then
          failed = failed or {}; failed[v[5]] = true
        end
        if want2 and not transform(v[3],center,y,1) then
          failed = failed or {}; failed[v[6]] = true
        end
      else
        failed = failed or {}
        if want1 then failed[v[5]] = true end
        if want2 then failed[v[6]] = true end
      end
    end
  end
  return failed == nil, failed
end

local function follow_confirm717(find, action)
  local back = action == 'back'
  local key = back and 'hex.back' or action == 'submit' and 'hex.submit' or action == 'restart' and 'hex.redo'
  if not key then return end
  local button = find(key)
  local bx, by = adapt715r_pair(button, 'GetAnchoredPosition')
  local width = adapt715r_pair(button, 'GetSizeDelta')
  local okWidth = adapt715r_pair(find('hex.ok'), 'GetSizeDelta')
  local noWidth = adapt715r_pair(find('hex.no'), 'GetSizeDelta')
  if not bx or not by or not width or width <= 0 or not okWidth or okWidth <= 0 or not noWidth or noWidth <= 0 then return end
  local gap = 8
  local firstLeft = back and bx + width/2 + gap or bx - width/2 - 2*gap - okWidth - noWidth
  local okX = firstLeft + okWidth/2
  local noX = firstLeft + okWidth + gap + noWidth/2
  local function place(name,x)
    local control = find(name)
    local px,py = adapt715r_pair(control,'GetAnchoredPosition')
    if control and (not px or not py or math.abs(px-x) > .002 or math.abs(py-by) > .002) then
      pcall(function() control:SetAnchoredPosition(x,by) end)
    end
  end
  place('hex.ok',okX); place('hit.ok',okX)
  place('hex.no',noX); place('hit.no',noX)
end
local function sync_adapt715r(dt,force)
  if not adapter then return end
  local st=adapt715r
  local gen=adapter._lookup_gen or 0
  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.cardCtrls748={};st.steady_cardScale748=nil;st.page=nil;st.steady_ok745=false;st.main_ok747=false;st.pager_retry747=nil;st.fill_col745=nil end
  local function find(name)
    if not st.handles[name] then st.handles[name]=adapter:find(name) end
    return st.handles[name]
  end
  local cur=Murdoku and Murdoku.current()
  local page=(cur and cur.controller and cur.controller.screen) or 'home'
  local selecting=page=='select'
  local function set_visible(c,want)
    if not c then return false end
    local ok,matched=pcall(e745_set_vis_pair,c,want)
    return ok and matched
  end
  local pageChanged=page~=st.page
  local pending=cur and cur.controller and cur.controller.pending
  local pend_act=pending and pending.action or ''
  local pendChanged=pend_act~=st.steady_pend
  st.elapsed=st.elapsed+(dt or 0)
  -- 751(b)：确认卡打开/切换当帧立即执行 follow_confirm717，不再等待 0.25s 节流（稳态 0 开销）。
  if not force and not pageChanged and not pendChanged and st.elapsed<.25 then return end
  st.elapsed=0
  local ok_sz,cw,ch=pcall(game.GetUICanvasSize)
  local valid_sz=ok_sz and type(cw)=='number' and cw>0 and cw<math.huge and type(ch)=='number' and ch>0 and ch<math.huge
  local slot=valid_sz and adapt715r_device() or nil
  local spage=(selecting and cur and cur.controller and cur.controller.select_page) or 0
  -- 748（B6）：独立极轻量卡片字号同步器：缓存 12 个卡片文本框句柄，仅在选关页做 .text 引用比对（0 字符串拼接、0 布局重跑），
  -- 即使文字由云端/外部异步改写也能在 0.25s 内自动重算字号，非选关页 0 开销。
  local function sync_card_fonts748(cscale, do_force)
    st.cardFont = st.cardFont or {}
    st.cardCtrls748 = st.cardCtrls748 or {}
    local suffixes = { 'info', 'title', 'result' }
    for i = 1, 4 do
      for si = 1, 3 do
        local suffix = suffixes[si]
        local slot_idx = (i - 1) * 3 + si
        local c = st.cardCtrls748[slot_idx]
        if c == nil then
          c = find('select.card.' .. i .. '.' .. suffix)
          st.cardCtrls748[slot_idx] = c
        end
        if c ~= nil then
          local ok_t, txt = pcall(e744_get_k, c, 'text')
          if ok_t then
            local rec = st.cardFont[slot_idx]
            if do_force or rec == nil or rec.txt ~= txt or rec.scale ~= cscale then
              local size = 16 * cscale
              if suffix ~= 'result' then
                local units = 0
                for ch_u in tostring(txt or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do units = units + (#ch_u == 1 and .55 or 1) end
                size = math.min(18, math.max(10, math.floor((182 - 6) / math.max(1, units)))) * cscale
              end
              local ok_fs, cur_fs = pcall(e744_get_k, c, 'fontSize')
              if do_force or not ok_fs or cur_fs ~= size then
                if pcall(e745_set_font, c, size) then
                  st.cardFont[slot_idx] = { txt = txt, scale = cscale, size = size }
                end
              else
                st.cardFont[slot_idx] = { txt = txt, scale = cscale, size = size }
              end
            end
          else
            st.cardCtrls748[slot_idx] = nil
          end
        end
      end
    end
  end
  -- 747+748（P2-4 + B6）：若主布局已稳态且分辨率/页面/槽位/确认条/选关页码均未变：
  --   选关页先执行极轻量 12 文本脏检；无失败翻页项即早退；有失败翻页项仅定向重试失败的 1~4 项。
  if not force and not pageChanged and valid_sz and st.main_ok747==true
     and st.steady_cw==cw and st.steady_ch==ch and st.steady_slot==slot
     and st.steady_pend==pend_act and st.steady_spage==spage then
    if selecting and st.steady_cardScale748 ~= nil then
      sync_card_fonts748(st.steady_cardScale748, false)
    end
    if st.pager_retry747 == nil then
      return
    end
    local function transform_p747(name,x,y,s)
      local c=find(name)
      if not c then return false end
      local ok,matched=pcall(e745_transform,c,x,y,s,1e-5)
      return ok and matched
    end
    local p_ok, p_fail = adapt14_pagers(find, transform_p747, 1600, st.pager_retry747)
    st.pager_retry747 = p_fail
    st.steady_ok745 = (p_ok == true)
    return
  end
  local bg=find('adapt715r.background')
  local fill=find('adapt715r.background.fill')
  local base=find('art647.select.bg.base')
  local visible=set_visible(base,selecting)
  local bgWanted=page=='home' or page=='game'
  visible=set_visible(bg,bgWanted) and visible
  visible=set_visible(fill,page~='shop' and page~='bag') and visible
  if fill then
    local want_col=selecting and ADAPT715R_SELECT_COLOR or ADAPT715R_HOME_COLOR
    if st.fill_col745~=want_col or force then
      if pcall(e744_set_k,fill,'imageColor',want_col) then st.fill_col745=want_col end
    end
  end
  if bg and not st.leaves then
    local ok,children=pcall(e744_get_kids,bg)
    if ok and type(children)=='table' and #children>=ADAPT715R_BG_LEAVES then st.leaves=children;st.leafState=nil end
  end
  local function batch_set_vis747(list, want)
    local all_ok = true
    for i = 1, #list do
      if not e745_set_vis_pair(list[i], want) then all_ok = false end
    end
    return all_ok
  end
  if st.leaves and (st.leafState~=bgWanted or force) then
    local ok_b, done = pcall(batch_set_vis747, st.leaves, bgWanted)
    if not ok_b then
      done = true
      for i = 1, #st.leaves do done = set_visible(st.leaves[i], bgWanted) and done end
    end
    if done then st.leafState=bgWanted end
  end
  st.page=page -- 控件延迟出现时，按 0.25 秒刷新重试。
  if not valid_sz then return end
  local w,h=1600,1600*ch/cw
  if not (type(h)=='number' and h>0 and h<math.huge) then return end
  adapter._adapt715_canvas={physical_w=cw,physical_h=ch,w=w,h=h,unit=1}
  local phys_cw,phys_ch=cw,ch
  cw,ch=w,h
  local fit=math.min(w/1600,h/900)
  local cover=fit -- 同步原版火漆父级与场景，不裁主体。
  local cardScale=adapt14_cards(w,h)
  local eps=.002
  local function transform(name,x,y,s)
    local c=find(name)
    if not c then return false end
    local ok,matched=pcall(e745_transform,c,x,y,s,1e-5)
    return ok and matched
  end
  local scene,shift=adapt14_background(w,h,transform,slot)
  local applied,missing,failed=0,0,0
  if slot~=nil then
    for _,t in ipairs(ADAPT715R_TARGETS) do
      -- 745：WAX.12 与翻页器 4 控件紧随其后由专门公式写入最终位置/缩放，跳过先写旧值再覆盖导致的乒乓抖动与多余 SetPos/SetScale！
      local nm=t.name
      if nm=='adapt715r.WAX.12' or nm=='adapt715r.LM.19' or nm=='adapt715r.RM.20' or nm=='hit.select.prev' or nm=='hit.select.next' then
        if find(nm)==nil then missing=missing+1 else applied=applied+1 end
      else
        local c=find(nm)
        if c==nil then missing=missing+1 else
          local p=t.base[slot] or t.base[0]
          local x,y=p[1]+(t.ax-.5)*(w-1600),p[2]+(t.ay-.5)*(h-720)
          local px,py=adapt715r_pair(c,'GetAnchoredPosition')
          local good=true
          if px==nil or math.abs(px-x)>eps or math.abs(py-y)>eps then
            good=pcall(e745_set_pos,c,x,y)
            px,py=adapt715r_pair(c,'GetAnchoredPosition')
          end
          if good and px and math.abs(px-x)<eps and math.abs(py-y)<eps then applied=applied+1 else failed=failed+1 end
        end
      end
    end
  end
  local wax_ok=transform('adapt715r.WAX.12',0,shift,scene)
  if pending then follow_confirm717(find, pending.action) end
  local pagers_ok, pager_failed747 = adapt14_pagers(find,transform,w,nil)
  local board_ok=transform('art642.select.board',0,0,1)
  local cardsOk=true
  for _,name in ipairs(ADAPT715R_SELECT_CARDS) do
    cardsOk=transform(name,0,0,cardScale) and cardsOk
  end
  -- 撕边组已重挂到art641.select末尾；显隐逐叶处理，不依赖父级级联。
  -- 746（P2-1）：仅当子节点数达到该组预期叶数 v.expect 时才写入缓存 tearKids；未齐组每 0.25s 单独复查，已齐组零重枚举。
  st.tearKids=st.tearKids or {}; st.tearState=st.tearState or {}
  local tears_complete746=true
  for _,v in ipairs(ADAPT715R_TEARS) do
    local group=find(v.name)
    if group then
      local gok=set_visible(group,selecting)
      local kids=st.tearKids[v.name]
      local expect_n=v.expect or 1
      local group_complete=(kids~=nil)
      if not group_complete then
        local good,children=pcall(e744_get_kids,group)
        if good and type(children)=='table' and #children>0 then
          kids=children
          if #children>=expect_n then
            st.tearKids[v.name]=kids
            group_complete=true
          end
        end
      end
      if not group_complete then tears_complete746=false end
      if force or (not group_complete) or st.tearState[v.name]~=selecting then
        if selecting then pcall(e744_last_sib,group) end
        local done=gok
        if kids then
          local ok_t, t_done = pcall(batch_set_vis747, kids, selecting)
          if not ok_t then
            t_done = true
            for i=1,#kids do t_done = set_visible(kids[i],selecting) and t_done end
          end
          done = t_done and done
        else
          done=false
        end
        if done and group_complete then
          st.tearState[v.name]=selecting
        else
          st.tearState[v.name]=nil
        end
      end
    else
      tears_complete746=false
    end
    local tok=transform(v.name,adapt14_corner(w,h,v.side))
    if not tok then tears_complete746=false end
  end
  if cardsOk then
    if adapter._select715_scale~=cardScale or adapter._select715_gen~=gen then
      adapter._select715_scale=cardScale;adapter._select715_gen=gen
      st.cardFont={}
      local cur=Murdoku.current();local controller=cur and cur.controller
      if controller then controller.dirty=true;controller._props={} end
    end
    -- 正文属性可能被翻页重新写入；仅在选关页按文本+缩放与当前字号脏检查重算字号。
    if selecting or force then
      sync_card_fonts748(cardScale, force)
    end
  end

  local tears_done745=tears_complete746
  if tears_done745 then
    for _,v in ipairs(ADAPT715R_TEARS) do
      if st.tearState[v.name]~=selecting then tears_done745=false; break end
    end
  end
  -- 747（P2-4）：主布局（背景/卡片/撕边/WAX/board/目标表）与翻页 4 控件解耦记录；
  -- 主布局就绪时保存稳态基准，仅将未就绪的翻页项挂入 st.pager_retry747 单独重试。
  st.main_ok747=(visible==true and missing==0 and failed==0 and cardsOk==true and wax_ok==true and board_ok==true and st.leafState==bgWanted and tears_done745)
  st.pager_retry747=pager_failed747
  st.steady_ok745=(st.main_ok747 and pagers_ok==true)
  if st.main_ok747 then
    st.steady_cw=phys_cw; st.steady_ch=phys_ch; st.steady_slot=slot
    st.steady_pend=pend_act; st.steady_spage=spage
    st.steady_cardScale748=cardScale
  end
  local signature=table.concat({page,w,h,tostring(slot),tostring(st.leafState),tostring(visible),missing,failed},'/')
  if st.signature~=signature then
    st.signature=signature
    print('[adapt715-v16] '..signature..' scene='..scene..' cards='..cardScale..' leaves='..tostring(st.leaves and #st.leaves or 0))
  end
end

-- ADAPT715R END


-- ECON742 RESPONSIVE BEGIN
local econ742={elapsed=1,page=nil,gen=-1,signature=nil}
local function sync_econ742(dt,force)
  if not adapter then return end
  local cur=Murdoku and Murdoku.current()
  local ctrl=cur and cur.controller
  local page=ctrl and ctrl.screen or 'home'
  local active=page=='shop' or page=='bag'
  local st=econ742
  st.elapsed=st.elapsed+(dt or 0)
  local gen=adapter._lookup_gen or 0
  local pageChanged=page~=st.page or gen~=st.gen
  if not force and not pageChanged and st.elapsed<0.25 then return end
  st.elapsed=0;st.page=page;st.gen=gen
  local group=adapter:find('econ.ui742')
  if not group then return end
  local ok,cw,ch=pcall(function() return game.GetUICanvasSize() end)
  if not ok or type(cw)~='number' or type(ch)~='number' or cw<=0 or ch<=0 then return end
  local logicalW=1600
  local logicalH=logicalW*ch/cw
  -- 16:9 到 20:9 平滑引入上下边距，超宽设备沿用上限，避免按钮持续变小。
  local wide=math.max(0,math.min(1,(cw/ch*9-16)/4))
  local blend=wide*wide*(3-2*wide)
  local scale=math.min(1,logicalH/900)*(1-0.10*blend)
  local signature=table.concat({page,cw,ch,scale,tostring(active)},'/')
  if not force and not pageChanged and st.applied_sig==signature and st.applied_group==group then return end
  -- 747（P2-2）：保持中心锚定并严格回读验证；凡存在写接口就必须能回读确认到目标值，
  -- 若读接口暂缺或返回 nil 一律视作未确认、绝不缓存签名，待接口可用后自动回正。
  local function apply_and_verify_econ747(grp, sc, act)
    local ok_all = true
    if grp.SetLocalScale then
      grp:SetLocalScale(sc,sc,1)
      if not grp.GetLocalScale then
        ok_all = false
      else
        local sx, sy = e745_pair(grp, 'GetLocalScale')
        if not sx or not sy or math.abs(sx - sc) >= 0.002 or math.abs(sy - sc) >= 0.002 then ok_all = false end
      end
    end
    if grp.SetAnchoredPosition then
      grp:SetAnchoredPosition(0,0)
      if not grp.GetAnchoredPosition then
        ok_all = false
      else
        local px, py = e745_pair(grp, 'GetAnchoredPosition')
        if not px or not py or math.abs(px) >= 0.002 or math.abs(py) >= 0.002 then ok_all = false end
      end
    end
    if grp.SetVisible then
      grp:SetVisible(act)
      if grp.visible ~= act then ok_all = false end
    end
    if grp.SetActive then
      grp:SetActive(act)
      if grp.active ~= act then ok_all = false end
    end
    return ok_all
  end
  local ok_e, verified = pcall(apply_and_verify_econ747, group, scale, active)
  if ok_e and verified == true then
    st.applied_sig=signature; st.applied_group=group
    if st.signature~=signature then
      st.signature=signature
      print('[econ742] '..signature)
    end
  else
    st.applied_sig=nil; st.applied_group=nil
  end
end
-- ECON742 RESPONSIVE END

-- ECON749 PAPER ANIM BEGIN
-- 749_v8：基尔霍夫薄板方程双模态解析解 + 不可伸长薄壳积分 + 整纸一体化遮挡（零半透明产物，购买绝不触发，稳态 0 开销）。
local ECON749_DUR = 0.36
local ECON749_N = 16
local ECON749_PI = math.pi
local ECON749_RAD = math.pi / 180
local ECON749_SHOP_POS_ICONS = { "econ.shop736.anim.u.s110", "econ.shop736.anim.u.s111", "econ.shop736.anim.u.s112", "econ.shop736.anim.u.s113", "econ.shop736.anim.u.s114", "econ.shop736.anim.u.s115", "econ.shop736.anim.u.s116", "econ.shop736.anim.u.s117", "econ.shop736.anim.u.s118", "econ.shop736.anim.u.s119.edge", "econ.shop736.anim.u.s119", "econ.shop736.anim.u.s120", "econ.shop736.anim.u.s121", "econ.shop736.anim.u.s122.edge", "econ.shop736.anim.u.s122" }
local ECON749_SHOP_CLUE_ICONS = { "econ.shop736.anim.u.s125", "econ.shop736.anim.u.s126", "econ.shop736.anim.u.s127", "econ.shop736.anim.u.s128", "econ.shop736.anim.u.s129", "econ.shop736.anim.u.s130", "econ.shop736.anim.u.s131", "econ.shop736.anim.u.s131.top", "econ.shop736.anim.u.s131.bottom", "econ.shop736.anim.u.s132" }
local ECON749_CFG = {
  shop = {
    prefix = "econ.shop736.",
    sheet = "econ.shop736.anim.sheet",
    under = "econ.shop736.anim.under",
    bend  = "econ.shop736.anim.bend",
    ptop  = "econ.shop736.anim.ptop",
    pbot  = "econ.shop736.anim.pbot",
    top   = "econ.shop736.anim.top",
    bot   = "econ.shop736.anim.bot",
    staticFaces = { "econ.shop736.card.border", "econ.shop736.card.face", "econ.shop736.s66" },
    underStatics = { "econ.shop736.anim.u.card.border", "econ.shop736.anim.u.card.face", "econ.shop736.anim.u.s66", "econ.shop736.anim.u.s67", "econ.shop736.anim.u.s69", "econ.shop736.anim.u.s68", "econ.shop736.anim.u.s70", "econ.shop736.anim.u.s65" },
    inBoxes = {
      { name="econ.shop736.anim.b.in1", v=0.422248, dx=-1.083, off=-2, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in2", v=0.479953, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in3", v=0.537657, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in4", v=0.595362, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in5", v=0.653066, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in6", v=0.71077, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in7", v=0.768475, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in8", v=0.826179, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in9", v=0.883884, dx=-1.083, off=0, r=231, g=208, b=178 },
      { name="econ.shop736.anim.b.in10", v=0.941588, dx=-1.083, off=2, r=231, g=208, b=178 },
    },
    baseX = 444,
    baseY = -19,
    w = 468,
    h = 530,
    ptopRelX = 0, ptopRelY = 43.2,
    pbotRelX = 0, pbotRelY = -236,
    topRelX  = 0,  topRelY  = 168,
    botRelX  = 0,  botRelY  = -96,
    vPTop = 0.418491, vPBot = 0.945283,
    vTop  = 0.183019,  vBot  = 0.681132,
    -- 商店独立档案纸卡：基尔霍夫薄板方程（悬臂-自由端主模态 + 简支气垫穹拱模态），右手轻放，左上不撞标题、右上光滑无阶梯、左右边 0 拉伸
    headDxA = 20,
    headDxB = 22,
    headDy = 4,
    arcLiftY = 3.5,
    thetaHeadA = 1.15,
    thetaHeadB = 1.25,
    ampKl = 0.25,
    ampAir = 0.055,
    obliqueDeg = 5.6,
    airTwistDeg = 0.35,
    perspF = 4200,
    globalWidthTilt = 0.010,
    faceR = 247, faceG = 240, faceB = 223,
    brR   = 184, brG   = 152, brB   = 114,
    underEndScale = 0.994,
    underEndRot = -0.15,
  },
  bag = {
    prefix = "econ.bag741.",
    sheet = "econ.bag741.anim.sheet",
    under = "econ.bag741.anim.under",
    bend  = "econ.bag741.anim.bend",
    ptop  = "econ.bag741.anim.ptop",
    pbot  = "econ.bag741.anim.pbot",
    top   = "econ.bag741.anim.top",
    bot   = "econ.bag741.anim.bot",
    staticFaces = { "econ.bag741.paper.top", "econ.bag741.paper.label", "econ.bag741.paper.body" },
    underStatics = { "econ.bag741.anim.u.paper.top", "econ.bag741.anim.u.paper.label", "econ.bag741.anim.u.paper.body", "econ.bag741.anim.u.paper.pin0", "econ.bag741.anim.u.paper.pin1", "econ.bag741.anim.u.paper.pin2", "econ.bag741.anim.u.paper.pin3" },
    inBoxes = {
      { name="econ.bag741.anim.b.in1", v=0.08473, dx=-4, off=-2, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in2", v=0.127096, dx=-4, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in3", v=0.169461, dx=-4, off=2, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in4", v=0.398004, dx=-1.083, off=-2, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in5", v=0.450366, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in6", v=0.502729, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in7", v=0.555091, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in8", v=0.607454, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in9", v=0.659816, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in10", v=0.712179, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in11", v=0.764541, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in12", v=0.816903, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in13", v=0.869266, dx=-1.083, off=0, r=232, g=215, b=191 },
      { name="econ.bag741.anim.b.in14", v=0.921628, dx=-1.083, off=2, r=232, g=215, b=191 },
    },
    baseX = 395.6666564941406,
    baseY = -44,
    w = 408.5,
    h = 616.3333129882812,
    ptopRelX = 0, ptopRelY = 67.3,
    pbotRelX = 0, pbotRelY = -263.5,
    topRelX  = 0,  topRelY  = 192,
    botRelX  = 0,  botRelY  = -98.5,
    vPTop = 0.390806, vPBot = 0.927528,
    vTop  = 0.18848,  vBot  = 0.659816,
    -- 背包右侧便签纸：同源基尔霍夫薄板方程双模态解析积分，右上角光滑、严格不可伸长
    headDxA = 19,
    headDxB = 21,
    headDy = 5,
    arcLiftY = 4.0,
    thetaHeadA = 1.10,
    thetaHeadB = 1.20,
    ampKl = 0.26,
    ampAir = 0.055,
    obliqueDeg = 5.6,
    airTwistDeg = 0.35,
    perspF = 4200,
    globalWidthTilt = 0.010,
    faceR = 246, faceG = 231, faceB = 210,
    brR   = 165, brG   = 136, brB   = 104,
    underEndScale = 0.994,
    underEndRot = 0.15,
  },
}
local ECON749_SHOP_PRICE = SHOP_PRICE
local econ749_cx, econ749_cy, econ749_sx, econ749_sy, econ749_rz = {}, {}, {}, {}, {}
local econ749_phi, econ749_w, econ749_ang = {}, {}, {}
local econ749_st = {
  gen = -1,
  activePage = nil,
  shop = { handles = nil, lastKey = nil, lastSnap = nil, animT = nil, flip = false },
  bag  = { handles = nil, lastKey = nil, lastSnap = nil, animT = nil, flip = false },
}

local function e749_set_pos(c, x, y) if c.SetAnchoredPosition then c:SetAnchoredPosition(x, y) end end
local function e749_set_scale(c, sx, sy) if c.SetLocalScale then c:SetLocalScale(sx, sy, 1) end end
local function e749_set_rot(c, rz)
  if c.SetLocalRotation then c:SetLocalRotation(0, 0, rz)
  elseif c.localRotationZ ~= nil then c.localRotationZ = rz end
end
local function e749_set_vis(c, v)
  if v and c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
  if c.SetVisible ~= nil and c.visible ~= v then c:SetVisible(v) end
end
local function e749_set_text(c, txt)
  local s = tostring(txt or "")
  if c.text ~= s then c.text = s end
end
local function e749_pack_opaque(r, g, b, delta)
  local rr = math.floor(r + delta + 0.5); if rr < 0 then rr = 0 elseif rr > 255 then rr = 255 end
  local gg = math.floor(g + delta + 0.5); if gg < 0 then gg = 0 elseif gg > 255 then gg = 255 end
  local bb = math.floor(b + delta + 0.5); if bb < 0 then bb = 0 elseif bb > 255 then bb = 255 end
  return 0xFF000000 + rr * 65536 + gg * 256 + bb
end
local function e749_set_col(c, col)
  if c.imageColor ~= col then c.imageColor = col end
end

local function e749_ensure_handles(page)
  local gen = (adapter and adapter._lookup_gen) or 0
  if econ749_st.gen ~= gen then
    econ749_st.gen = gen
    econ749_st.shop.handles = nil
    econ749_st.bag.handles  = nil
  end
  local st = econ749_st[page]
  if st.handles ~= nil and st.handles.sheet ~= nil and st.handles.under ~= nil then
    return st.handles
  end
  local cfg = ECON749_CFG[page]
  local h = {
    sheet = adapter:find(cfg.sheet),
    under = adapter:find(cfg.under),
    bend  = adapter:find(cfg.bend),
    ptop  = adapter:find(cfg.ptop),
    pbot  = adapter:find(cfg.pbot),
    top   = adapter:find(cfg.top),
    bot   = adapter:find(cfg.bot),
    staticFaces = {},
    u_static = {},
    br = {},
    fc = {},
    inBox = {},
  }
  for i = 1, #cfg.staticFaces do h.staticFaces[i] = adapter:find(cfg.staticFaces[i]) end
  for i = 1, #cfg.underStatics do h.u_static[i] = adapter:find(cfg.underStatics[i]) end
  for i = 1, ECON749_N do
    h.br[i] = adapter:find(cfg.prefix .. "anim.b.br" .. i)
    h.fc[i] = adapter:find(cfg.prefix .. "anim.b.fc" .. i)
  end
  for i = 1, #cfg.inBoxes do
    h.inBox[i] = adapter:find(cfg.inBoxes[i].name)
  end
  if page == "shop" then
    h.u_price  = adapter:find("econ.shop736.anim.u.price")
    h.u_owned  = adapter:find("econ.shop736.anim.u.owned")
    h.u_desc   = adapter:find("econ.shop736.anim.u.desc")
    h.u_status = adapter:find("econ.shop736.anim.u.status")
    h.u_pos_icons = {}
    for i = 1, #ECON749_SHOP_POS_ICONS do h.u_pos_icons[i] = adapter:find(ECON749_SHOP_POS_ICONS[i]) end
    h.u_clue_icons = {}
    for i = 1, #ECON749_SHOP_CLUE_ICONS do h.u_clue_icons[i] = adapter:find(ECON749_SHOP_CLUE_ICONS[i]) end
  else
    h.u_title   = adapter:find("econ.bag741.anim.u.title")
    h.u_meta    = adapter:find("econ.bag741.anim.u.meta")
    h.u_desc    = adapter:find("econ.bag741.anim.u.desc")
    h.u_usage   = adapter:find("econ.bag741.anim.u.usage")
    h.u_history = adapter:find("econ.bag741.anim.u.history")
  end
  st.handles = h
  return h
end

-- 真机容器 SetVisible 不级联，必须逐叶子显式开/关 anim.bend 与 anim.under
local function e749_set_bend_vis(h, on)
  if h.bend ~= nil then pcall(e749_set_vis, h.bend, on) end
  for i = 1, #h.br do local c = h.br[i]; if c ~= nil then pcall(e749_set_vis, c, on) end end
  for i = 1, #h.fc do local c = h.fc[i]; if c ~= nil then pcall(e749_set_vis, c, on) end end
  for i = 1, #h.inBox do local c = h.inBox[i]; if c ~= nil then pcall(e749_set_vis, c, on) end end
end

local function e749_set_under_all_off(page, h)
  for i = 1, #h.u_static do local c = h.u_static[i]; if c ~= nil then pcall(e749_set_vis, c, false) end end
  if page == "shop" then
    if h.u_price  then pcall(e749_set_vis, h.u_price,  false) end
    if h.u_owned  then pcall(e749_set_vis, h.u_owned,  false) end
    if h.u_desc   then pcall(e749_set_vis, h.u_desc,   false) end
    if h.u_status then pcall(e749_set_vis, h.u_status, false) end
    for i = 1, #h.u_pos_icons  do local c = h.u_pos_icons[i];  if c then pcall(e749_set_vis, c, false) end end
    for i = 1, #h.u_clue_icons do local c = h.u_clue_icons[i]; if c then pcall(e749_set_vis, c, false) end end
  else
    if h.u_title   then pcall(e749_set_vis, h.u_title,   false) end
    if h.u_meta    then pcall(e749_set_vis, h.u_meta,    false) end
    if h.u_desc    then pcall(e749_set_vis, h.u_desc,    false) end
    if h.u_usage   then pcall(e749_set_vis, h.u_usage,   false) end
    if h.u_history then pcall(e749_set_vis, h.u_history, false) end
  end
  if h.under ~= nil then
    pcall(e749_set_scale, h.under, 1, 1)
    pcall(e749_set_rot, h.under, 0)
    pcall(e749_set_vis, h.under, false)
  end
end

local function e749_snap_rest(page, clearState)
  local st = econ749_st[page]
  local cfg = ECON749_CFG[page]
  local h = st.handles
  if h == nil and adapter ~= nil then h = e749_ensure_handles(page) end
  if h ~= nil then
    if h.sheet ~= nil then
      pcall(e749_set_pos, h.sheet, cfg.baseX, cfg.baseY)
      pcall(e749_set_scale, h.sheet, 1, 1)
      pcall(e749_set_rot, h.sheet, 0)
    end
    if h.ptop ~= nil then
      pcall(e749_set_pos, h.ptop, cfg.ptopRelX, cfg.ptopRelY)
      pcall(e749_set_scale, h.ptop, 1, 1)
      pcall(e749_set_rot, h.ptop, 0)
    end
    if h.pbot ~= nil then
      pcall(e749_set_pos, h.pbot, cfg.pbotRelX, cfg.pbotRelY)
      pcall(e749_set_scale, h.pbot, 1, 1)
      pcall(e749_set_rot, h.pbot, 0)
    end
    if h.top ~= nil then
      pcall(e749_set_pos, h.top, cfg.topRelX, cfg.topRelY)
      pcall(e749_set_scale, h.top, 1, 1)
      pcall(e749_set_rot, h.top, 0)
    end
    if h.bot ~= nil then
      pcall(e749_set_pos, h.bot, cfg.botRelX, cfg.botRelY)
      pcall(e749_set_scale, h.bot, 1, 1)
      pcall(e749_set_rot, h.bot, 0)
    end
    e749_set_bend_vis(h, false)
    e749_set_under_all_off(page, h)
    -- 仅在仍留本页时恢复静止单底面与静止内框；离页时绝不误点亮防闪烁
    if not clearState then
      for i = 1, #h.staticFaces do
        if h.staticFaces[i] ~= nil then pcall(e749_set_vis, h.staticFaces[i], true) end
      end
    end
  end
  st.animT = nil
  if clearState then
    st.lastKey = nil
    st.lastSnap = nil
  end
end

local function e749_fill_under(page, snap)
  local h = e749_ensure_handles(page)
  if h == nil then return end
  -- 显式点亮旧纸容器及全部底纸/边框/图框/说明框/角钉叶子，确保完整旧纸稳坐底层
  if h.under ~= nil then pcall(e749_set_vis, h.under, true) end
  for i = 1, #h.u_static do
    local c = h.u_static[i]
    if c ~= nil then pcall(e749_set_vis, c, true) end
  end
  if page == "shop" then
    if h.u_price  then pcall(e749_set_text, h.u_price,  snap.price);  pcall(e749_set_vis, h.u_price,  true) end
    if h.u_owned  then pcall(e749_set_text, h.u_owned,  snap.owned);  pcall(e749_set_vis, h.u_owned,  true) end
    if h.u_desc   then pcall(e749_set_text, h.u_desc,   snap.desc);   pcall(e749_set_vis, h.u_desc,   true) end
    if h.u_status then pcall(e749_set_text, h.u_status, snap.status); pcall(e749_set_vis, h.u_status, true) end
    local pk = snap.pick or ""
    local showPos = (pk == "position")
    local showClue = (pk == "clue")
    for i = 1, #h.u_pos_icons do
      local c = h.u_pos_icons[i]
      if c then pcall(e749_set_vis, c, showPos) end
    end
    for i = 1, #h.u_clue_icons do
      local c = h.u_clue_icons[i]
      if c then pcall(e749_set_vis, c, showClue) end
    end
  else
    if h.u_title   then pcall(e749_set_text, h.u_title,   snap.title);   pcall(e749_set_vis, h.u_title,   true) end
    if h.u_meta    then pcall(e749_set_text, h.u_meta,    snap.meta);    pcall(e749_set_vis, h.u_meta,    true) end
    if h.u_desc    then pcall(e749_set_text, h.u_desc,    snap.desc);    pcall(e749_set_vis, h.u_desc,    true) end
    if h.u_usage   then pcall(e749_set_text, h.u_usage,   snap.usage);   pcall(e749_set_vis, h.u_usage,   snap.usageVis) end
    if h.u_history then pcall(e749_set_text, h.u_history, snap.history); pcall(e749_set_vis, h.u_history, snap.historyVis) end
  end
end

local function e749_sample_chain(vTarget)
  local f = vTarget * ECON749_N + 0.5
  local i0 = math.floor(f)
  if i0 < 1 then i0 = 1 elseif i0 > ECON749_N then i0 = ECON749_N end
  local i1 = i0 + 1
  if i1 > ECON749_N then i1 = ECON749_N end
  local t = f - i0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return
    econ749_cx[i0] + (econ749_cx[i1] - econ749_cx[i0]) * t,
    econ749_cy[i0] + (econ749_cy[i1] - econ749_cy[i0]) * t,
    econ749_sx[i0] + (econ749_sx[i1] - econ749_sx[i0]) * t,
    econ749_sy[i0] + (econ749_sy[i1] - econ749_sy[i0]) * t,
    econ749_rz[i0] + (econ749_rz[i1] - econ749_rz[i0]) * t
end

local function e749_apply_frame(page, u)
  local st = econ749_st[page]
  local cfg = ECON749_CFG[page]
  local h = st.handles
  if h == nil or h.sheet == nil then return end

  -- 动画期：静止单底面/刚体说明框保持隐藏，弯曲纸带（含 16 边框 + 16 纸面 + M 同步弯曲内框）逐叶子全亮
  for i = 1, #h.staticFaces do
    if h.staticFaces[i] ~= nil then pcall(e749_set_vis, h.staticFaces[i], false) end
  end
  e749_set_bend_vis(h, true)

  local inv = 1 - u
  -- 基尔霍夫薄板阻尼模态时间包络（u=1 处 C1 平滑落平）
  local remPos = (inv ^ 2.15) * (1 + 0.50 * u)
  if remPos > 1 then remPos = 1 elseif remPos < 0 then remPos = 0 end
  local qKl   = (inv ^ 1.60) * math.exp(-0.50 * u) * (1 + 0.85 * u)
  local qAir  = (inv ^ 1.80) * math.exp(-1.10 * u) * (0.40 + 2.20 * u)
  local qTilt = (inv ^ 1.85) * (1 + 0.40 * u)

  local sinPiU = math.sin(ECON749_PI * u)
  local headDx = (st.flip and cfg.headDxB or cfg.headDxA) * remPos
  local headDy = cfg.headDy * remPos + cfg.arcLiftY * sinPiU * (inv ^ 1.45)
  local thetaHead = (st.flip and cfg.thetaHeadB or cfg.thetaHeadA) * qTilt

  local stripH = cfg.h / ECON749_N
  local klAmp = cfg.ampKl * qKl
  local airAmp = cfg.ampAir * qAir
  local globalWidthScale = 1 - cfg.globalWidthTilt * qKl

  -- 1a. 第一遍：基尔霍夫薄板方程 D*w'''' = q 解析双模态斜率 phi(xi) 与 3D 离面高程 w(xi)
  --   模态1（悬臂-自由端: w(0)=w'(0)=0, M(1)=V(1)=0）：P_kl'(xi)  = (4/3)*(3*xi - 3*xi^2 + xi^3)
  --   模态2（简支气垫穹拱: w(0)=w(1)=0, M(0)=M(1)=0）：P_air'(xi) = (16/5)*(1 - 6*xi^2 + 4*xi^3)
  local wAcc = 0
  local wMax = -1e9
  for i = 1, ECON749_N do
    local xi = (i - 0.5) / ECON749_N
    local xi2 = xi * xi
    local xi3 = xi2 * xi
    local dPKl  = (4 / 3) * (3 * xi - 3 * xi2 + xi3)
    local dPAir = (16 / 5) * (1 - 6 * xi2 + 4 * xi3)
    local slope = klAmp * dPKl + airAmp * dPAir
    local phi = math.atan(slope)
    wAcc = wAcc + stripH * math.sin(phi)
    if wAcc > wMax then wMax = wAcc end

    local ang = thetaHead + cfg.obliqueDeg * (klAmp * dPKl) + cfg.airTwistDeg * qAir * (xi - 0.5)
    econ749_phi[i] = phi
    econ749_w[i] = wAcc
    econ749_ang[i] = ang
  end

  -- 1b. 第二遍：严格不可伸长可展板积分（纯透视平滑宽度 + 外侧零拉长护栏，消除右上角阶梯感）
  local px = headDx
  local py = cfg.h * 0.5 + headDy
  local prevRad = econ749_ang[1] * ECON749_RAD
  local perspF = cfg.perspF
  for i = 1, ECON749_N do
    local phi = econ749_phi[i]
    local ang = econ749_ang[i]
    local rad = ang * ECON749_RAD

    local wDrop = econ749_w[i] - wMax
    local segSx = (perspF / (perspF - wDrop)) * globalWidthScale
    if segSx < 0.95 then segSx = 0.95 elseif segSx > 1 then segSx = 1 end

    local dRad = math.abs(rad - prevRad)
    if i < ECON749_N then
      local dRadNext = math.abs(econ749_ang[i + 1] * ECON749_RAD - rad)
      if dRadNext > dRad then dRad = dRadNext end
    end
    local hw = 0.5 * cfg.w * segSx
    local edgeGuard = 1 - (hw * dRad) / stripH
    local cosPhi = math.cos(phi)
    local segSy = cosPhi < edgeGuard and cosPhi or edgeGuard
    if segSy < 0.86 then segSy = 0.86 elseif segSy > 1 then segSy = 1 end
    prevRad = rad

    local ds = stripH * segSy
    local sa = math.sin(rad)
    local ca = math.cos(rad)
    local nx = px + ds * sa
    local ny = py - ds * ca
    local cx = 0.5 * (px + nx)
    local cy = 0.5 * (py + ny)
    px, py = nx, ny

    econ749_cx[i] = cx
    econ749_cy[i] = cy
    econ749_sx[i] = segSx
    econ749_sy[i] = segSy
    econ749_rz[i] = ang

    -- 3D 离面法向朗伯实色明暗（100% alpha=0xFF，无半透明叠片）
    local ld = 13.0 * math.sin(phi) + 4.0 * (cosPhi - 1)
    if ld > 8 then ld = 8 elseif ld < -8 then ld = -8 end
    local offB = (i == 1 and (-3.0 * segSy)) or (i == ECON749_N and (3.0 * segSy)) or 0
    local offF = (i == 1 and (-4.0 * segSy)) or (i == ECON749_N and (4.0 * segSy)) or 0

    local br = h.br[i]
    if br ~= nil then
      pcall(e749_set_pos, br, cx - offB * sa, cy + offB * ca)
      pcall(e749_set_scale, br, segSx, segSy)
      pcall(e749_set_rot, br, ang)
      pcall(e749_set_col, br, e749_pack_opaque(cfg.brR, cfg.brG, cfg.brB, ld * 0.5))
    end
    local fc = h.fc[i]
    if fc ~= nil then
      pcall(e749_set_pos, fc, cx - offF * sa, cy + offF * ca)
      pcall(e749_set_scale, fc, segSx, segSy)
      pcall(e749_set_rot, fc, ang)
      pcall(e749_set_col, fc, e749_pack_opaque(cfg.faceR, cfg.faceG, cfg.faceB, ld))
    end
  end

  -- 2. 内部浅棕说明框/标题框条带同步弯曲（与外纸面 100% 融为一体，零破边零脱节）
  local inSpecs = cfg.inBoxes
  for j = 1, #inSpecs do
    local c = h.inBox[j]
    if c ~= nil then
      local sp = inSpecs[j]
      local bx, by, bsx, bsy, bang = e749_sample_chain(sp.v)
      local rad = bang * ECON749_RAD
      local sa = math.sin(rad)
      local ca = math.cos(rad)
      local offS = sp.off * bsy
      local dxS = sp.dx * bsx
      pcall(e749_set_pos, c, bx + dxS * ca - offS * sa, by + dxS * sa + offS * ca)
      pcall(e749_set_scale, c, bsx, bsy)
      pcall(e749_set_rot, c, bang)
      local idxPhi = math.floor(sp.v * ECON749_N + 0.5)
      if idxPhi < 1 then idxPhi = 1 elseif idxPhi > ECON749_N then idxPhi = ECON749_N end
      local phiJ = econ749_phi[idxPhi]
      local ld = 13.0 * math.sin(phiJ) + 4.0 * (math.cos(phiJ) - 1)
      if ld > 8 then ld = 8 elseif ld < -8 then ld = -8 end
      pcall(e749_set_col, c, e749_pack_opaque(sp.r, sp.g, sp.b, ld))
    end
  end

  -- 3. 角钉容器（ptop/pbot）与内容容器（top/bot）精准贴合弯曲链对应位置与切线角
  if h.ptop ~= nil then
    local x1, y1, sx1, sy1, rz1 = e749_sample_chain(cfg.vPTop)
    pcall(e749_set_pos, h.ptop, x1, y1); pcall(e749_set_scale, h.ptop, sx1, sy1); pcall(e749_set_rot, h.ptop, rz1)
  end
  if h.pbot ~= nil then
    local x2, y2, sx2, sy2, rz2 = e749_sample_chain(cfg.vPBot)
    pcall(e749_set_pos, h.pbot, x2, y2); pcall(e749_set_scale, h.pbot, sx2, sy2); pcall(e749_set_rot, h.pbot, rz2)
  end
  if h.top ~= nil then
    local tx, ty, tsx, tsy, trz = e749_sample_chain(cfg.vTop)
    pcall(e749_set_pos, h.top, tx, ty); pcall(e749_set_scale, h.top, tsx, tsy); pcall(e749_set_rot, h.top, trz)
  end
  if h.bot ~= nil then
    local bx2, by2, bsx, bsy, brz = e749_sample_chain(cfg.vBot)
    pcall(e749_set_pos, h.bot, bx2, by2); pcall(e749_set_scale, h.bot, bsx, bsy); pcall(e749_set_rot, h.bot, brz)
  end

  -- 4. 下方完整旧纸：随新纸压下产生轻微承接压沉感
  if h.under ~= nil then
    local easeUnder = 1 - inv * inv * inv
    local usc = 1 - (1 - cfg.underEndScale) * easeUnder
    local urz = cfg.underEndRot * easeUnder
    pcall(e749_set_scale, h.under, usc, usc)
    pcall(e749_set_rot, h.under, urz)
  end
end

local function e749_read_shop_snap(ctrl)
  local pick = ctrl.econ_pick
  local coins, clues, pending, _, positions = ctrl.opts.wallet()
  pending = pending or ""
  local pos = (pick == "position")
  local qty = pos and positions or clues
  local qtyStr = (qty == nil) and "读取中" or tostring(qty)
  local price = pick and (tostring(ECON749_SHOP_PRICE[pick]) .. " 调查币") or ""
  local owned = pick and ("持有 " .. qtyStr .. " 张") or ""
  local desc = pick and (pos and "选中一名人物，将其棋子摆到正确位置。" or "选中一条线索，核验其真假。") or "选择左侧的道具查看用途。"
  local status = (pending ~= "" and pending) or ctrl.econ_status or (pick and "本案免费提示用完后可使用。" or "")
  -- 仅以选中商品 pick 作为翻纸触发键：购买商品（确认弹窗、提示文案、持有数+1）绝不触发纸张动画
  local key = pick or ""
  return key, { pick = pick, price = price, owned = owned, desc = desc, status = status }
end

local function e749_read_bag_snap(ctrl)
  local coins, clues, pending, last, positions, pos_last = ctrl.opts.wallet()
  pending = pending or ""
  local hasClue, hasPos = (clues or 0) > 0, (positions or 0) > 0
  local pick = (hasClue and ctrl.econ_pick == "clue" and "clue")
    or (hasPos and ctrl.econ_pick == "position" and "position")
    or nil
  local history = ""
  if pick ~= "clue" and pos_last and pos_last ~= "-" then
    local c, id, r, col = pos_last:match("^case_00(%d):([^:]+):(%d+):(%d+)$")
    if c then history = "上次揭示：案件 " .. c .. " · " .. id .. " 第" .. r .. "行第" .. col .. "列" end
  end
  if history == "" and pick ~= "position" and last and last ~= "-" then
    history = "上次线索核验：" .. (last:sub(-1) == "1" and "真" or "假")
  end
  local title = pick and (pick == "clue" and "线索核验券" or "位置揭示券") or "调查背包"
  local meta = pick and ("持有 " .. tostring(pick == "clue" and clues or positions) .. " 张")
    or ("调查币　" .. (coins == nil and "读取中" or tostring(coins)))
  local desc = (pick == "clue" and "选中一条线索，核验其真假。")
    or (pick == "position" and "选中一名人物，将其棋子摆到正确位置。")
    or (pending ~= "" and pending)
    or ((clues == nil or positions == nil) and "正在读取背包…")
    or ((hasClue or hasPos) and "选择左侧的道具查看用途。")
    or "背包为空，可到调查商城购买道具。"
  local usage = pick and "本案免费提示用完后，可在提示菜单中用券。" or ""
  local usageVis = (pick ~= nil)
  local historyVis = (history ~= "")
  local key = pick or ""
  return key, {
    pick = pick, title = title, meta = meta, desc = desc,
    usage = usage, usageVis = usageVis, history = history, historyVis = historyVis,
  }
end

local function sync_econ_paper_anim749(dt)
  if not adapter then return end
  local cur = Murdoku and Murdoku.current()
  local ctrl = cur and cur.controller
  local page = ctrl and ctrl.screen or "home"
  if page ~= "shop" and page ~= "bag" then
    if econ749_st.activePage ~= nil then
      e749_snap_rest(econ749_st.activePage, true)
      econ749_st.activePage = nil
    end
    return
  end
  if econ749_st.activePage ~= nil and econ749_st.activePage ~= page then
    e749_snap_rest(econ749_st.activePage, true)
  end
  econ749_st.activePage = page

  local st = econ749_st[page]
  local key, snap
  if page == "shop" then key, snap = e749_read_shop_snap(ctrl)
  else key, snap = e749_read_bag_snap(ctrl) end

  if st.lastKey == nil then
    st.lastKey = key
    st.lastSnap = snap
    e749_snap_rest(page, false)
    return
  end

  if key ~= st.lastKey then
    local prevSnap = st.lastSnap
    st.lastKey = key
    st.lastSnap = snap
    local h = e749_ensure_handles(page)
    if h ~= nil and h.sheet ~= nil and h.under ~= nil and prevSnap ~= nil then
      e749_fill_under(page, prevSnap)
      pcall(e749_set_scale, h.under, 1, 1)
      pcall(e749_set_rot, h.under, 0)
      st.flip = not st.flip
      st.animT = 0
      e749_apply_frame(page, 0)
    end
    return
  end

  -- 同一选中对象下（例如购买成功更新持有数或提示文案），仅在稳态刷新快照，绝不触发动画
  if st.animT == nil then
    st.lastSnap = snap
    return
  end

  local stepDt = tonumber(dt) or 0
  if stepDt < 0 then stepDt = 0 elseif stepDt > 0.05 then stepDt = 0.05 end
  local nextT = st.animT + stepDt
  if nextT >= ECON749_DUR then
    e749_snap_rest(page, false)
    st.lastSnap = snap
  else
    st.animT = nextT
    e749_apply_frame(page, nextT / ECON749_DUR)
  end
end
-- ECON749 PAPER ANIM END

local art641_cache = nil
local art641_gen = nil
local art641_screen = false
local function sync_art641()
  if not adapter then return end
  local cur = Murdoku.current()
  local ctrl = cur and cur.controller
  if not ctrl then return end
  local screen = ctrl.screen or "game"
  local gen = adapter._lookup_gen or 0
  if art641_cache == nil or art641_gen ~= gen then
    art641_cache = {}
    for _, key in ipairs({"home", "select", "game"}) do
      art641_cache[key] = adapter:find("art641." .. key)
    end
    art641_gen = gen
    art641_screen = false
  end
  if art641_screen ~= screen then
    for _, key in ipairs({"home", "select", "game"}) do
      help_visible(art641_cache[key], screen == key)
    end
    art641_screen = screen
    do
      local gp = adapter:find("art657.grid.reuse")
      if gp ~= nil then
        local board_page = screen == "game" or screen == "level"
        help_visible(gp, screen == "home" or board_page)
        local scale = board_page and 760/750 or 1
        local dx, dy = 0, 40.5
        if board_page then
          dx, dy = 105 + (scale-1), 46 + 45.5*(scale-1)
        end
        pcall(function() gp:SetLocalScale(scale, scale, 1) end)
        pcall(function() gp:SetAnchoredPosition(dx, dy) end)
      end
    end
  end
end
local SETTLE_ART_TINT = {
  {"art647.select.settle.shadow", 0x66000000, 0x66000000},
  {"art647.select.settle.yellow.shadow", 0x66000000, 0x66000000},
  {"art647.select.settle.yellow.edge", 0xff6b2b12, 0xff2c1208},
  {"art647.select.settle.yellow", 0xffffd133, 0xff685816},
  {"art647.select.settle.outline", 0xff1e1210, 0xff0c0807},
  {"art647.select.settle.outline.tri.top", 0xff1e1210, 0xff0c0807},
  {"art647.select.settle.outline.tri.bottom", 0xff1e1210, 0xff0c0807},
  {"art647.select.settle.ribbon", 0xff825447, 0xff35231f},
  {"art647.select.settle.ribbon.tri.top", 0xff825447, 0xff35231f},
  {"art647.select.settle.ribbon.tri.bottom", 0xff825447, 0xff35231f},
  {"art647.home.settle.shadow", 0x66000000, 0x66000000},
  {"art647.home.settle.yellow.shadow", 0x66000000, 0x66000000},
  {"art647.home.settle.yellow.edge", 0xff6b2b12, 0xff2c1208},
  {"art647.home.settle.yellow", 0xffffd133, 0xff685816},
  {"art647.home.settle.outline", 0xff1e1210, 0xff0c0807},
  {"art647.home.settle.outline.tri.top", 0xff1e1210, 0xff0c0807},
  {"art647.home.settle.outline.tri.bottom", 0xff1e1210, 0xff0c0807},
  {"art647.home.settle.ribbon", 0xff825447, 0xff35231f},
  {"art647.home.settle.ribbon.tri.top", 0xff825447, 0xff35231f},
  {"art647.home.settle.ribbon.tri.bottom", 0xff825447, 0xff35231f},
}
local art_color_cache655 = setmetatable({}, { __mode = "k" })
local art_color_gen655 = -1
local function write_art_color650(c, key, want)
  if c == nil then return end
  local gen = (adapter and adapter._lookup_gen) or 0
  if art_color_gen655 ~= gen then
    art_color_cache655 = setmetatable({}, { __mode = "k" })
    art_color_gen655 = gen
  end
  local slot = art_color_cache655[c]
  if slot == nil then slot = {}; art_color_cache655[c] = slot end
  if slot[key] == want then return end
  local ok_g, actual = pcall(e744_get_k, c, key)
  if not ok_g or actual ~= want then pcall(e744_set_k, c, key, want) end
  slot[key] = want
end
local art647_tint_key = nil
local art647_last_key, art647_last_gen = nil, -1
local function sync_art647()
  local cur = Murdoku.current()
  local ad = cur and cur.adapter
  local ctrl = cur and cur.controller
  if not ad or not ctrl then return end
  -- 689：can_settle 有解锁副作用，必须逐帧调用；状态未变且控件树未重建时跳过染色。
  --       仅当 21 个控件全部找到并完成染色后才固化，首帧 / 重建帧不会漏染。
  local ready = ctrl:can_settle()
  local gen = ad._lookup_gen or 0
  local key = (ready and "1" or "0") .. "|" .. tostring(ctrl.screen or "")
  art647_tint_key = key
  if key == art647_last_key and gen == art647_last_gen then return end
  local cd = ad:find("settle.btn.countdown")
  write_art_color650(cd, "textColor", 0x00FFFFFF)
  local complete = cd ~= nil
  for _, e in ipairs(SETTLE_ART_TINT) do
    local c = ad:find(e[1])
    if c == nil then complete = false end
    write_art_color650(c, "imageColor", ready and e[2] or e[3])
  end
  if complete then art647_last_key, art647_last_gen = key, gen end
end
local art649_last_key = nil
local art649_ready = false
local function sync_art649_page()
  local cur = Murdoku.current()
  local ad = cur and cur.adapter
  local ctrl = cur and cur.controller
  if not ad or not ctrl then return end
  local lv = ctrl.opts and ctrl.opts.levels
  local list = {}
  if type(lv) == "function" then list = lv() or {}
  elseif type(lv) == "table" then list = lv end
  local pages = math.max(1, math.ceil(#list / 4))
  local page = tonumber(ctrl.select_page) or 1
  if page < 1 then page = 1 end
  if page > pages then page = pages end
  -- 689：页态 + 控件树代数未变且控件已就绪时跳过重复染色；翻页立即重算。
  local key = pages .. "|" .. page .. "|" .. tostring(ad._lookup_gen or 0)
  if key == art649_last_key and art649_ready then return end
  local dl = ad:find("art647.select.diamond.left")
  local dr = ad:find("art647.select.diamond.right")
  local NORMAL, DIM = 0xFFFFFFFF, 0x7FFFFFFF
  write_art_color650(dl, "imageColor", (page > 1) and NORMAL or DIM)
  write_art_color650(dr, "imageColor", (page < pages) and NORMAL or DIM)
  art649_last_key = key
  art649_ready = dl ~= nil and dr ~= nil
end
function OnInit()
  if LOAD_ERR then if printerr then printerr(LOAD_ERR) end; return end
  Murdoku.reset_settle_session()
  pcall(enable_update)
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
  pcall(check_canvas)
  sync_adapt715r(0, true)
  pcall(function() beacon(adapter, BEACON.OnInit) end)
  bind_keyboard_once("OnInit")
  if print then print("[murdoku] OnInit done（适配器已就绪，等 OnStart 开局）") end
end
function OnStart()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  if adapter == nil then
    if printerr then printerr("[murdoku] OnStart 发现适配器为空，补建一个") end
    pcall(build_adapter)
  end
  pcall(function() beacon(adapter, BEACON.OnStart) end)
  if not probe_or_dump(false) then
    if print then print("[murdoku] 控件还没就绪，交给 OnUpdate 重试") end
    return
  end
  bind_keyboard_once("OnStart")
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
local registration_clock=0
function OnUpdate(dt)
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  Murdoku.advance_settle_session(dt)
  registration_clock=registration_clock+(dt or 0)
  if started and registration_clock>=2 then
    registration_clock=0
    local session=Murdoku.current()
    if session then session.retry_signals() end
    if adapter then
      if not keyboard_bound then
        local kt = (adapter._kb_retry745 or 0) + 1
        adapter._kb_retry745 = kt
        -- 745：移动端无 AddKeyEventListener 时前 3 次每 2s 重试，之后退避至每 30s 复核一次，避免无意义扫描。
        if kt <= 3 or (kt % 15 == 0) then bind_keyboard_once('重试') end
      end
      local in_lv745 = session and session.controller and (session.controller.screen == nil or session.controller.screen == "level")
      for id,node in pairs(adapter._retry_input or {}) do
        if in_lv745 or (type(id) ~= "string") or id:sub(1, 5) ~= "cell." then
          adapter:bind_input(id,node)
        end
      end
      -- 748（B5/U7）：每 2s 通过统一看护管理器抽检当前页活跃交互控件（覆盖 Adapter:bind_input、util:_bind 与 cell.*，0 次 GetChildren）。
      if adapter._watch_handles748 ~= nil and adapter.check_watched_handles748 ~= nil then
        local ctrl748 = session and session.controller
        pcall(adapter.check_watched_handles748, adapter, ctrl748 and ctrl748.screen or nil, ctrl748)
      end
    end
  end
  pcall(tick_tutorial)
  if not started then
    retry_elapsed = retry_elapsed + (dt or 0)
    if retry_elapsed >= RETRY_INTERVAL then
      retry_elapsed = 0
      retry_tries = retry_tries + 1
      if retry_tries > RETRY_LIMIT then
        probe_or_dump(true)
        if printerr then
          printerr("[murdoku] 等不到客户端控件，放弃自动开局"
            .. "（检查客户端控件容器是否【激活且可见】、界面布局是否被【职业】引用）")
        end
        started = true       
      else
        if adapter == nil then pcall(build_adapter) end
        if probe_or_dump(false) then
          bind_keyboard_once("重试")
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
  sync_art641()
  sync_art647()
  sync_art649_page()
  sync_block640()
  sync_adapt715r(dt, false)
  sync_econ742(dt, false)
  sync_econ_paper_anim749(dt)
end
function OnLevelUpdate(dt) end
function OnDestroy()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  Murdoku.on_destroy()
  if print then print("[murdoku] destroyed") end
end