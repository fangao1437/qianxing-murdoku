 



 

 
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
pcall(function() require = __require end)    

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
  validate = function(ctx, cl) return ctx.is_above(ctx.pos(cl.b), ctx.pos(cl.a)) end,
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
  if record then push_history(self, { kind = "clear", r = r, c = c, prev = prev, prior_formal = prior_formal }) end
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
  local _, move_from = move_piece_if_needed(self, who, r, c)
  local ok, why = do_place(self, r, c, who, true, { clear_notes = true })
   
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
  local _, move_from = move_piece_if_needed(self, self.selected, r, c)
  local ok, why = do_place(self, r, c, self.selected, true, { clear_notes = false })
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
       
      local note_ok = not self.blocked[cell_key(r, c)]
      if tok == "X" then
        self.x_marks[r][c] = true
      elseif tok == "-" then
         
      elseif tok:sub(1, 1) == "!" then
        local body = tok:sub(2, -2)
        if note_ok then
          for k = 1, #body do
            local id = symbol_to_id[string.upper(body:sub(k, k))]
            if id then self.notes[r][c][id] = true end
          end
        end
      elseif tok:match("^%l$") then
        local id = symbol_to_id[string.upper(tok)]
        if id and note_ok then self.notes[r][c][id] = true end
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
  if action.kind == "place" then
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

function Core:deserialize(save)
  if type(save) ~= "table" or type(save.cells) ~= "table" then return false, "存档格式不对" end
  if save.level_id ~= nil and self.level.id ~= nil and save.level_id ~= self.level.id then
    return false, "存档属于其它关卡"
  end
  self:reset()
  for i = 1, #save.cells do
    local e = save.cells[i]
    if e.id then
      do_place(self, e.r, e.c, e.id, false)
    elseif e.notes or e.x then
       
       
       
       
      local k = cell_key(e.r, e.c)
      local blocked = self.blocked[k] == true
      if e.x then
        self.x_marks[e.r][e.c] = true
        self.notes[e.r][e.c] = {}
      elseif not blocked then
        for j = 1, #(e.notes or {}) do self.notes[e.r][e.c][e.notes[j]] = true end
      end
    end
  end
  self.elapsed = save.elapsed or 0
  self.accused = save.accused
  self.failed_accusations = save.failed_accusations or 0
  if save.status == M.STATUS_SOLVED then self.status = M.STATUS_SOLVED end
  return true
end

function Core:set_elapsed(seconds) self.elapsed = seconds end

 
 
 

function Core:view()
  local wrong = {}
  if self.last_result then
    for _, w in ipairs(self.last_result.wrong_cells or {}) do wrong[cell_key(w.r, w.c)] = true end
  end

  local victim_pos = self.victim_fixed
  if self.victim_id then victim_pos = self.pos[self.victim_id] end

   
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

 
function F.rug_cell_els(bbox, r, c)
  local els = {}
  local function slice_rect(inset, color)
    local xa, xb = bbox.c1 - 0.5 + inset, bbox.c2 + 0.5 - inset
    local ya, yb = bbox.r1 - 0.5 + inset, bbox.r2 + 0.5 - inset
    local w, dx = slice_axis(xa, xb, c)
    local h, dy = slice_axis(ya, yb, r)
    if w == nil or h == nil then return nil end
    return { id = IMG.rect, color = color, w = w + 0.04, h = h + 0.04, dx = dx, dy = dy }
  end
  els[#els + 1] = { id = IMG.rect, color = C.rug_rim, w = 1.0, h = 1.0 }
  local inner = slice_rect(F.RUG_INSET, C.rug_in)
  if inner ~= nil then els[#els + 1] = inner end
  local line = slice_rect(F.RUG_LINE, C.rug_mid)
  if line ~= nil then els[#els + 1] = line end
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
      for _, cell in ipairs(p.cells) do
        res.cell[cell[1]][cell[2]].els = F.rug_cell_els(b, cell[1], cell[2])
      end
       
      res.pieces = res.pieces or {}
      res.pieces[#res.pieces + 1] = {
        kind = kind, box = b, anchor = anchor_of(b), variant = "1",
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
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
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
  end
  self.dirty = true
end

 
function Controller:do_restart()
  self.core.hint635_used=nil
  self.hint635=nil
   
  self:_clear_verdict()
  local core = self.core
  if core ~= nil and core.reset ~= nil then core:reset() end
   
   
   
   
   
   
   
   
   
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
  if self.screen ~= nil or self.modal ~= nil or self.pending ~= nil then
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

 
function Controller:on_cell_click(r, c)
   
   
   
   
   
   
   
   
   
  if r == nil or c == nil then return end
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  local core = self.core
  self.now = self.now or 0
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode

   
   
   
   
   
   
   
   
   
   
   
   
   
   
  if (not occupied) and mode == "place" then
    local last = self.last_click
     
    if last and last.r == r and last.c == c and (gesture_now(self) - last.t) <= DOUBLE_CLICK_SECONDS then
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
    if had then
       
       
       
       
       
       
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
       
       
       
       
       
       
       
       
       
       
       
       
      self._grid_refill_pending = true
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
     
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = gesture_now(self),
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
     
     
     
     
     
     
     
     
     
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = gesture_now(self), did = "none" }
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

 
function Controller:hint635_action(action)
  if self.screen ~= nil or self.modal ~= nil then return end
  local core=self.core
  core.hint635_used=core.hint635_used or {position=0,clue=0}
  local used=core.hint635_used
  local function message(text, timed)
    self.hint635={kind="message",text=text,until_time=timed and ((self.now or 0)+3) or nil}
  end
  if action=="close" then self.hint635=nil;return end
  if action=="toggle" then
    if self.hint635 then
      self.hint635=nil
    elseif not core.selected and self.general_focus~=true then
      message("请先选中一条线索卡",true)
    else
      self.hint635={kind="menu"}
    end
    return
  end
  if not self.hint635 or self.hint635.kind~="menu" then return end
  if action=="position" then
    if used.position>=1 then message("本关揭示位置次数已用完",true);return end
    local ok,msg=core:hint()
    if not ok then message(msg,true);return end
    used.position=used.position+1
    self.hint635=nil
    self:_clear_verdict();self._grid_refill_pending=true
    self._clue_sel_key,self._clue_sel_pos=nil,nil;self.focused_clue=nil
    self.dirty=true;self:fx("hex.hint",M.EFFECTS.SELECT)
  elseif action=="clue" then
    if used.clue>=2 then message("本关验证线索次数已用完",true);return end
    self:_sync_clue_focus()
    local general=self.general_focus==true
    local index=general and 1 or self.focused_clue
    if not index or (not general and not core.selected) then message("请先选中一条线索卡",true);return end
    local truth=core:answer_clue(index,general)
    if truth==nil then message("请先选中一条线索卡",true);return end
    used.clue=used.clue+1
    message(truth and "该线索为真" or "该线索为假",false)
  end
end

function Controller:on_input(event)
  local core = self.core
  local a = event.action

   
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
    core:set_mode(event.mode)

   
   
   
   
   
   
   
   
   
  elseif a == "back_confirm" then
     
    self.modal = { kind = "exit_menu" }    
    self.dirty = true
    self:sync_confirm()
     
     
     
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
      self:fx("hex.undo", M.EFFECTS.UNDO)
       
       
       
      self._grid_refill_pending = true
      self.dirty = true
    end

  elseif a == "redo" then
    if core:redo() then
      self:fx("hex.redo", M.EFFECTS.UNDO)
       
      self._grid_refill_pending = true
      self.dirty = true
    end

  elseif a == "hint" then
    self:hint635_action("toggle")

  elseif a == "reveal" then
     
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
    if self.opts.on_save then self.opts.on_save() end
    if self.opts.on_settle then self.opts.on_settle() end
    self.dirty = true

  elseif a == "level_list" then
     
    self.modal = { kind = "levelselect" }

  elseif a == "select_page" then
       
      self.select_page = (tonumber(self.select_page) or 1) + (tonumber(event.delta) or 0)
      if self.select_page < 1 then self.select_page = 1 end
      self.dirty = true

   
   
   
   
   
   
  elseif a == "settle_only" then
    if not self:can_settle() then return end
    if self.opts.on_settle_only then self.opts.on_settle_only() end

    elseif a == "pick_level" then
    if self.opts.on_pick_level then
      self.modal = nil
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
      self.opts.on_pick_level(event.id)
      self.screen = nil               
    end

   
  elseif a == "home" then
    self.screen = "home"; self.modal = nil; self.dirty = true

   
  elseif a == "replay" then
    self.result_seconds = nil
    self:do_restart()

  elseif a == "levelselect" then
    self.screen = "select"; self.modal = nil; self.dirty = true; self.select_page = 1

  elseif a == "continue" then
     
    local last = self.opts.last_level and self.opts.last_level() or nil
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
     
     
    self.toast = (a == "shop") and "商城：美术资源就绪后开放" or "背包：美术资源就绪后开放"
    self.toast_until = self.now + M.TOAST_SECONDS    
    self.dirty = true

  elseif a == "clue_up" or a == "clue_down" then
     
     
     
     
     
     
     
     
     
     
    local rows = M.LAYOUT.clue_rows or 9
    local shown = math.min(#self.core:view().clues, M.LAYOUT.clue_max_visible)
    local maxscroll = math.max(0, shown - rows)
    local s = self.clue_scroll or 0
    if a == "clue_up" then s = s - 1 else s = s + 1 end
    if s < 0 then s = 0 end
    if s > maxscroll then s = maxscroll end
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

   
   
   
   
   
   
   
   
   
   
   
  self:_sync_clue_focus()

  self.dirty = true
  return self.effects
end

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
function Controller:can_settle()
  local session = self.opts and self.opts.settle_session
  if self.core.status == "solved" then
    if session then session.unlocked = true else self._settle_unlocked = true end
    return true
  end
  return (session and session.unlocked == true) or self._settle_unlocked == true
end

function Controller:settle_seconds_left()
  if self:can_settle() then return 0 end
  local session = self.opts and self.opts.settle_session
  return math.max(1, math.ceil(60 - (session and session.elapsed or self._settle_elapsed or 0)))
end

function Controller:tick(dt)
  if not (self.opts and self.opts.settle_session) and not self._settle_unlocked then
    self._settle_elapsed = math.min(60, (self._settle_elapsed or 0) + math.max(0, dt or 0))
    if self._settle_elapsed >= 60 then self._settle_unlocked = true end
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

 
 
 
 
 
 
 
 
 
 
 
 
 
local function apply_screen_hide(nodes, screen)
  if nodes == nil then return end
  local HIDE, PREFIX = {}, {}
  if screen == nil then
     
     
     
     
     
     
     
     
     
     
     
     
     
    PREFIX = { "home", "select" }
  else
    HIDE = {
      topbar = true, toolbar = true, left = true, board = true, right = true,
      toast = true, modal = true, intro = true, clues = true,
       
      ["action.redo"] = true, ["action.hint"] = true,
      ["action.undo"] = true, ["action.submit"] = true, ["action.reveal"] = true,
    }
     
     
     
     
     
     
     
     
     
     
     
     
    HIDE["selbar"] = true
    HIDE["tpl-container"] = true
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    for _, id in ipairs({ "hit.back", "hit.submit", "hit.redo", "hit.undo",
                          "hit.hint", "hit.ok", "hit.no" }) do
      HIDE[id] = true
    end
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    PREFIX = { "clue.", "hud.", "room.label.", "tray.", "action.", "hex.",
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
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    if hide then nodes[i].visible = false end
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
       
       
      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3" },
    }
     
     
    for r = 1, vm.rows do
      furn_tpl[r], furn_span[r], furn_offset[r] = {}, {}, {}
      for c = 1, vm.cols do furn_tpl[r][c], furn_span[r][c], furn_offset[r][c] = false, false, false end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if p.anchor ~= nil then    
        local variant = "1"
        if (p.span_c or 1) > 1 then variant = "h2"
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
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    local ICON_ASSETS = {
       
      { "hex.back",   100109,   60,   48,  62,  62, "back_confirm" },   
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
        rect = rect,
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
    elseif self.screen == "select" then
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
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
      local BACK_RECT = { x = 60, y = 48, w = 62, h = 62 }
      push({ id = "select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT })
      push({ id = "hit.select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT,
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
           
           
           
           
           
           
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, image = CARD_MAT, tint = CARD_TINT })
           
           
           
           
           
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, event = { action = "pick_level", id = it.id } })
          local t = self:level_card_parts(it)
           
           
           
           
           
           
           
           
           
          push({ id = "select.card." .. i .. ".title", kind = "text", parent = "root",
                 visible = true, text = t.title, style = "card.title",
                 rect = { x = r.x + 16, y = r.y + 10, w = r.w - 32, h = 34 },
                 pos_runtime = true })
          push({ id = "select.card." .. i .. ".info", kind = "text", parent = "root",
                 visible = true, text = t.info, style = "muted",
                 rect = { x = r.x + 16, y = r.y + r.h - 42, w = r.w - 32, h = 32 },
                 pos_runtime = true })
          push({ id = "select.card." .. i .. ".result", kind = "text", parent = "root",
                 visible = t.result ~= "", text = t.result,
                 rect = { x = r.x, y = r.y + r.h + 10, w = math.max(r.w, 220), h = 72 } })
          self:push_room_thumb(push, "select.card." .. i, it, r, "select")
        else
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
           
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
           
           
          for _, suf in ipairs({ ".title", ".info", ".result" }) do
            push({ id = "select.card." .. i .. suf, kind = "text", parent = "root", visible = false,
                   rect = { x = r.x, y = r.y, w = 1, h = 1 }, pos_runtime = true })
          end
          self:push_room_thumb(push, "select.card." .. i, nil, r, "select")
        end
      end
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
  return { title = title, info = table.concat(bits, "　"), result = result }
end

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
local ROOM_MAX = 6           
local WHITE_MAT = 106053     

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
function Controller:editor_card_box(a, id, plan_r)
  if a == nil or type(a.find) ~= "function" then return plan_r end
  local ctrl = nil
  pcall(function() ctrl = a:find(id) end)
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
  if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return plan_r end
  if type(ax) ~= "number" or type(ay) ~= "number" then return plan_r end
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

function Controller:push_room_thumb(push, cardId, it, cardRect, parent)
   
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
       
      local cw = area.w / cols
      local ch = area.h / rows
      local x = area.x + math.floor((b.c1 - 1) * cw)
      local y = area.y + math.floor((b.r1 - 1) * ch)
      local w = math.max(2, math.floor((b.c2 - b.c1 + 1) * cw))
      local h = math.max(2, math.floor((b.r2 - b.r1 + 1) * ch))
       
       
       
       
       
       
      local colors = Controller.ROOM_COLORS
      local tint = (type(colors) == "table" and #colors > 0)
        and colors[((j - 1) % #colors) + 1] or nil
      push({ id = id, kind = "button", parent = parent, visible = true,
             rect = { x = x, y = y, w = w, h = h },
             image = WHITE_MAT, tint = tint, pos_runtime = true })
    else
       
       
       
      push({ id = id, kind = "button", parent = parent, visible = false,
             rect = { x = area.x, y = area.y, w = math.max(2, math.floor(area.w / 4)),
                      h = math.max(2, math.floor(area.h / 4)) }, pos_runtime = true })
    end
  end
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
  { r = 217, g = 205, b = 180 },    
  { r = 195, g = 205, b = 212 },    
  { r = 212, g = 200, b = 188 },    
  { r = 190, g = 207, b = 176 },    
  { r = 224, g = 200, b = 176 },    
  { r = 198, g = 198, b = 210 },    
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
  if ctrl == nil or ctrl.text == nil then return false end
  local ok = pcall(function() ctrl.text = tostring(txt or "") end)
  return ok
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
   
   
   
   
   
   
   
   
  if not self._tpl_logged and print then
    self._tpl_logged = true
    for _, nm in ipairs({ "clue", "clues.grid", "clues" }) do
      local c = nil
      pcall(function() c = self:_find_by_name(nm) end)
   
    end
  end
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
function Controller:_find_by_name(name)
  if name == nil then return nil end
  local hit = nil
  local search = nil
  search = function(x, d)
    if hit ~= nil or x == nil or d > 6 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == name then hit = x return end
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
    for i = 1, rn do search(roots[i], 0) end
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
    items[i] = {
      who    = (rt and rt.who) or ((who ~= nil) and (tostring(pre or "") .. tostring(who)) or ""),
      what   = (rt and rt.what) or ((who ~= nil) and tostring(post or "") or tostring(pre or "")),
      letter = (rt and rt.letter) or tostring(wid or ""),
       
       
      portrait = (rt and rt.face) or wportrait,
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
      id     = i,
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

 
   

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
function Controller:_grid_refill_now(adapter, grid)
  if grid == nil then return 0 end
  local seen = self._grid_seen
  if seen == nil then return 0 end
  local n = 0
  self._grid_in_refresh = false           
  for item, idx in pairs(seen) do
    pcall(function() self:_fill_grid_item(adapter, grid, item, idx) end)
    n = n + 1
  end
  self._grid_in_refresh = false
  return n
end

 
 
 
 
 
 
 
 
 
 
 
function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then return true end
  if rec ~= nil then rec.gray_noray = true end
  if cg.raycastTarget ~= nil then pcall(function() cg.raycastTarget = false end) end
  if cg.blockRaycast ~= nil then pcall(function() cg.blockRaycast = false end) end
  if cg.interactable ~= nil then pcall(function() cg.interactable = false end) end
  return true
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
  for _, nm in ipairs({ "who", "what", "letter", "face" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(false) end) end
  end
  for _, nm in ipairs({ "gen.backrop", "gen.title", "gen.body" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(true) end) end
  end   
   
   
   
   
  do
    local _cp = nil
    pcall(function() _cp = item:FindChild("backrop1") end)
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
   
   
   
   
   
   
   
  local _has_gen = false
  pcall(function() _has_gen = self:_has_general_clue() end)
  if _has_gen then
    if pos == 1 then
      pcall(function() self:_fill_general_item(adapter, item, index, pos) end)
      return
    end
    pos = pos - 1
     
     
     
     
     
    if self._general_item == item then self._general_item = nil end    
     
    for _, _nm in ipairs({ "gen.backrop", "gen.title", "gen.body" }) do
      pcall(function()
        local _cc = self:_grid_item_child_cached(item, index, pos, _nm)
        if _cc ~= nil then pcall(function() _cc:SetVisible(false) end) end
      end)
    end
  end
   
   
   
  self._grid_seen = self._grid_seen or {}
  self._grid_seen[item] = index

   
   
   
   
   
   
   
   
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
  local ok = pcall(function()
    item:AddCursorEventListener(click, function()
       
      pcall(function() self:_on_grid_item_click(adapter, grid, item) end)
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
    local now = nil
    pcall(function() now = os.clock() end)
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
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        local is_him = (tostring(self.core.selected or "") == tostring(pid))
        if is_him then
           
           
          self.core:select_suspect(pid)
        else
           
           
          self.core:select_suspect(pid)
        end
         
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
   
  if self._general_click then
    ev = { action = "focus_general", phase = "click" }
    self._general_click = nil             
  end
   
  pcall(function()
    if item ~= nil and self._general_item == item then
       
      ev = { action = "focus_general", phase = "click" }
    elseif pos == 1 and self:_has_general_clue() then
      ev = { action = "focus_general", phase = "click" }
    elseif pos == 1 and self.core ~= nil and type(self.core.general_clues) == "table"
       and #self.core.general_clues > 0 then
      ev = { action = "focus_general", phase = "click" }
    end
  end)
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
  if adapter ~= nil then self._last_adapter = adapter end    
  local batched = false
  if adapter ~= nil and adapter.begin_furn_batch ~= nil then
    batched = pcall(function() adapter:begin_furn_batch() end)
  end
  local ok, err = pcall(self._render_impl, self, adapter, force)
  if batched then pcall(function() adapter:end_furn_batch() end) end
  if not ok then error(err, 0) end
end

function Controller:_render_impl(adapter, force)
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter and adapter.clear_board_portraits then adapter:clear_board_portraits() end
      self._props = {}  
      if adapter ~= nil and adapter.invalidate_lookups ~= nil then
        pcall(function()
          adapter:invalidate_lookups("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
       
       
       
       
       
       
       
       
       
       
      if adapter ~= nil and adapter.rearm_raycast ~= nil then
        pcall(function()
          adapter:rearm_raycast("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
       
       
       
       
       
       
       
       
       
       
      if adapter ~= nil and adapter.rearm_cursor ~= nil then
        pcall(function()
          adapter:rearm_cursor("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
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
       
       
       
      local ok_c, err_c = pcall(function() adapter:create_control(n) end)
      if not ok_c then
        self:_grid_log("create_err:" .. tostring(n.id), "创建控件失败（已跳过这一条，不再每帧刷）：`"
          .. tostring(n.id) .. "` ← " .. tostring(err_c))
      end
      self._created[n.id] = true      
       
       
       
      if self._prop_retry ~= nil then
        local pre = tostring(n.id) .. "\1"
        local stale = {}
        for rk in pairs(self._prop_retry) do
          if rk:sub(1, #pre) == pre then stale[#stale + 1] = rk end
        end
        for j = 1, #stale do self._prop_retry[stale[j]] = nil end
      end
    end
     
     
     
    local last = self._props[nkey]
    if last == nil then
      last = {}
      self._props[nkey] = last
    end
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
           
           
           
           
           
           
           
           
           
           
           
           
           
           
           
           
           
          local exists = true
          if type(adapter.find) == "function" then
            local e2, r2 = pcall(function() return adapter:find(n.id) end)
            if e2 then exists = (r2 ~= nil) end
          end
           
           
           
           
           
           
           
           
          local ok = exists and self:_set_prop(adapter, n.id, k, v, nkey)
          if ok and exists then
            last[k] = v
            retry_clear(n.id, k)
          elseif not exists then
             
             
             
             
             
             
             
             
             
             
             
             
            last[k] = v
          else
             
             
             
             
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
             
             
             
             
            if retry_more(n.id, k, why, exists) == false then
              last[k] = v           
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
       
       
       
       
       
       
       
       
       
       
       
      local rect_exists = true
      if type(adapter.find) == "function" then
        local e3, r3 = pcall(function() return adapter:find(n.id) end)
        if e3 then rect_exists = (r3 ~= nil) end
      end
       
       
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
  [M.SIGNALS.RESTORE]    = { "state_code", "moves", "elapsed", "solved" },
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

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._floor_slots = nil
  self._floor_faces = nil
  self._floor_layout = nil
   
   
   
   
   
   
   
  self.controls = {}
  self._subtree_dirty = true
   
   
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
end

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname ~= nil and idx[cname] == nil then idx[cname] = ctrl end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end

local STATIC_PATH_653 = {
  ["root"] = {"root"},
  ["art641.home"] = {"root","art641.home"},
  ["art647.home.settle.shadow"] = {"root","art641.home","art647.home.settle.shadow"},
  ["art647.home.settle.yellow.shadow"] = {"root","art641.home","art647.home.settle.yellow.shadow"},
  ["art647.home.settle.yellow.edge"] = {"root","art641.home","art647.home.settle.yellow.edge"},
  ["art647.home.settle.yellow"] = {"root","art641.home","art647.home.settle.yellow"},
  ["art647.home.settle.outline"] = {"root","art641.home","art647.home.settle.outline"},
  ["art647.home.settle.outline.tri.top"] = {"root","art641.home","art647.home.settle.outline.tri.top"},
  ["art647.home.settle.outline.tri.bottom"] = {"root","art641.home","art647.home.settle.outline.tri.bottom"},
  ["art647.home.settle.ribbon"] = {"root","art641.home","art647.home.settle.ribbon"},
  ["art647.home.settle.ribbon.tri.top"] = {"root","art641.home","art647.home.settle.ribbon.tri.top"},
  ["art647.home.settle.ribbon.tri.bottom"] = {"root","art641.home","art647.home.settle.ribbon.tri.bottom"},
  ["art641.select"] = {"root","art641.select"},
  ["art642.select.buttons"] = {"root","art641.select","art642.select.buttons"},
  ["art647.select.settle.shadow"] = {"root","art641.select","art642.select.buttons","art647.select.settle.shadow"},
  ["art647.select.settle.yellow.shadow"] = {"root","art641.select","art642.select.buttons","art647.select.settle.yellow.shadow"},
  ["art647.select.settle.yellow.edge"] = {"root","art641.select","art642.select.buttons","art647.select.settle.yellow.edge"},
  ["art647.select.settle.yellow"] = {"root","art641.select","art642.select.buttons","art647.select.settle.yellow"},
  ["art647.select.settle.outline"] = {"root","art641.select","art642.select.buttons","art647.select.settle.outline"},
  ["art647.select.settle.outline.tri.top"] = {"root","art641.select","art642.select.buttons","art647.select.settle.outline.tri.top"},
  ["art647.select.settle.outline.tri.bottom"] = {"root","art641.select","art642.select.buttons","art647.select.settle.outline.tri.bottom"},
  ["art647.select.settle.ribbon"] = {"root","art641.select","art642.select.buttons","art647.select.settle.ribbon"},
  ["art647.select.settle.ribbon.tri.top"] = {"root","art641.select","art642.select.buttons","art647.select.settle.ribbon.tri.top"},
  ["art647.select.settle.ribbon.tri.bottom"] = {"root","art641.select","art642.select.buttons","art647.select.settle.ribbon.tri.bottom"},
  ["art647.select.diamond.left"] = {"root","art641.select","art642.select.buttons","art647.select.diamond.left"},
  ["art647.select.diamond.right"] = {"root","art641.select","art642.select.buttons","art647.select.diamond.right"},
  ["art641.game"] = {"root","art641.game"},
  ["settle.btn"] = {"root","settle.btn"},
  ["tpl.ruler"] = {"root","tpl.ruler"},
  ["assets"] = {"root","assets"},
  ["row.1.1"] = {"root","assets","row.1.1"},
  ["row.1.2"] = {"root","assets","row.1.2"},
  ["row.1.3"] = {"root","assets","row.1.3"},
  ["row.1.4"] = {"root","assets","row.1.4"},
  ["row.1.5"] = {"root","assets","row.1.5"},
  ["row.2.clue"] = {"root","assets","row.2.clue"},
  ["row.2.1"] = {"root","assets","row.2.1"},
  ["row.2.2"] = {"root","assets","row.2.2"},
  ["row.2.3"] = {"root","assets","row.2.3"},
  ["row.2.4"] = {"root","assets","row.2.4"},
  ["row.2.5"] = {"root","assets","row.2.5"},
  ["row.2.6"] = {"root","assets","row.2.6"},
  ["row.3.1"] = {"root","assets","row.3.1"},
  ["row.3.2"] = {"root","assets","row.3.2"},
  ["row.3.3"] = {"root","assets","row.3.3"},
  ["row.3.4"] = {"root","assets","row.3.4"},
  ["row.3.5"] = {"root","assets","row.3.5"},
  ["row.3.6"] = {"root","assets","row.3.6"},
  ["row.4.1"] = {"root","assets","row.4.1"},
  ["row.4.2"] = {"root","assets","row.4.2"},
  ["row.4.3"] = {"root","assets","row.4.3"},
  ["row.4.4"] = {"root","assets","row.4.4"},
  ["row.4.5"] = {"root","assets","row.4.5"},
  ["row.4.6"] = {"root","assets","row.4.6"},
  ["clues"] = {"root","clues"},
  ["clues.bg"] = {"root","clues","clues.bg"},
  ["clues.grid"] = {"root","clues","clues.grid"},
  ["tpl.cell.face"] = {"root","tpl.cell.face"},
  ["tpl.cell"] = {"root","tpl.cell"},
  ["tpl.stage"] = {"root","tpl.stage"},
  ["stage"] = {"root","stage"},
  ["board.bg"] = {"root","stage","board.bg"},
  ["board.floors"] = {"root","stage","board.floors"},
  ["board.rugs"] = {"root","stage","board.rugs"},
  ["labels"] = {"root","labels"},
  ["fart.tpl"] = {"root","fart.tpl"},
  ["home"] = {"root","home"},
  ["home.title"] = {"root","home","home.title"},
  ["home.select"] = {"root","home","home.select"},
  ["home.continue"] = {"root","home","home.continue"},
  ["home.shop"] = {"root","home","home.shop"},
  ["home.bag"] = {"root","home","home.bag"},
  ["home.tutorial627.bg"] = {"root","home","home.tutorial627.bg"},
  ["home.tutorial627.ring"] = {"root","home","home.tutorial627.ring"},
  ["home.tutorial627.label"] = {"root","home","home.tutorial627.label"},
  ["home.tutorial627.hit"] = {"root","home","home.tutorial627.hit"},
  ["topbar"] = {"root","topbar"},
  ["hud.title"] = {"root","topbar","hud.title"},
  ["hud.timer"] = {"root","topbar","hud.timer"},
  ["right"] = {"root","right"},
  ["hud.progress"] = {"root","right","hud.progress"},
  ["modal"] = {"root","modal"},
  ["result.bg"] = {"root","modal","result.bg"},
  ["modal.exit"] = {"root","modal","modal.exit"},
  ["modal.save"] = {"root","modal","modal.save"},
  ["modal.settle"] = {"root","modal","modal.settle"},
  ["modal.cancel"] = {"root","modal","modal.cancel"},
  ["modal.title"] = {"root","modal","modal.title"},
  ["modal.body"] = {"root","modal","modal.body"},
  ["modal.stats"] = {"root","modal","modal.stats"},
  ["result.next"] = {"root","modal","result.next"},
  ["result.exit"] = {"root","modal","result.exit"},
  ["result.home"] = {"root","modal","result.home"},
  ["result.settle"] = {"root","modal","result.settle"},
  ["win"] = {"root","modal","win"},
  ["win.1"] = {"root","modal","win","win.1"},
  ["win.2"] = {"root","modal","win","win.2"},
  ["win.3"] = {"root","modal","win","win.3"},
  ["win.4"] = {"root","modal","win","win.4"},
  ["win.result"] = {"root","modal","win","win.result"},
  ["result.title.1"] = {"root","modal","result.title.1"},
  ["result.title.2"] = {"root","modal","result.title.2"},
  ["result.title.3"] = {"root","modal","result.title.3"},
  ["result.msg.1"] = {"root","modal","result.msg.1"},
  ["result.msg.2"] = {"root","modal","result.msg.2"},
  ["result.msg.3"] = {"root","modal","result.msg.3"},
  ["result.settle.countdown"] = {"root","modal","result.settle.countdown"},
  ["modal.settle.countdown"] = {"root","modal","modal.settle.countdown"},
  ["hex.back"] = {"root","hex.back"},
  ["hex.submit"] = {"root","hex.submit"},
  ["hex.redo"] = {"root","hex.redo"},
  ["hex.undo"] = {"root","hex.undo"},
  ["hex.hint"] = {"root","hex.hint"},
  ["hex.ok"] = {"root","hex.ok"},
  ["hex.no"] = {"root","hex.no"},
  ["hit.back"] = {"root","hit.back"},
  ["hit.submit"] = {"root","hit.submit"},
  ["hit.redo"] = {"root","hit.redo"},
  ["hit.undo"] = {"root","hit.undo"},
  ["hit.hint"] = {"root","hit.hint"},
  ["hit.ok"] = {"root","hit.ok"},
  ["hit.no"] = {"root","hit.no"},
  ["select.back"] = {"root","select.back"},
  ["select.card.1"] = {"root","select.card.1"},
  ["select.card.2"] = {"root","select.card.2"},
  ["select.card.3"] = {"root","select.card.3"},
  ["select.card.4"] = {"root","select.card.4"},
  ["select.card.1.info"] = {"root","select.card.1.info"},
  ["select.card.1.room.1"] = {"root","select.card.1.room.1"},
  ["select.card.1.room.2"] = {"root","select.card.1.room.2"},
  ["select.card.1.room.3"] = {"root","select.card.1.room.3"},
  ["select.card.1.room.4"] = {"root","select.card.1.room.4"},
  ["select.card.1.room.5"] = {"root","select.card.1.room.5"},
  ["select.card.1.room.6"] = {"root","select.card.1.room.6"},
  ["select.card.1.title"] = {"root","select.card.1.title"},
  ["select.card.2.info"] = {"root","select.card.2.info"},
  ["select.card.2.room.1"] = {"root","select.card.2.room.1"},
  ["select.card.2.room.2"] = {"root","select.card.2.room.2"},
  ["select.card.2.room.3"] = {"root","select.card.2.room.3"},
  ["select.card.2.room.4"] = {"root","select.card.2.room.4"},
  ["select.card.2.room.5"] = {"root","select.card.2.room.5"},
  ["select.card.2.room.6"] = {"root","select.card.2.room.6"},
  ["select.card.2.title"] = {"root","select.card.2.title"},
  ["select.card.3.info"] = {"root","select.card.3.info"},
  ["select.card.3.room.1"] = {"root","select.card.3.room.1"},
  ["select.card.3.room.2"] = {"root","select.card.3.room.2"},
  ["select.card.3.room.3"] = {"root","select.card.3.room.3"},
  ["select.card.3.room.4"] = {"root","select.card.3.room.4"},
  ["select.card.3.room.5"] = {"root","select.card.3.room.5"},
  ["select.card.3.room.6"] = {"root","select.card.3.room.6"},
  ["select.card.3.title"] = {"root","select.card.3.title"},
  ["select.card.4.info"] = {"root","select.card.4.info"},
  ["select.card.4.room.1"] = {"root","select.card.4.room.1"},
  ["select.card.4.room.2"] = {"root","select.card.4.room.2"},
  ["select.card.4.room.3"] = {"root","select.card.4.room.3"},
  ["select.card.4.room.4"] = {"root","select.card.4.room.4"},
  ["select.card.4.room.5"] = {"root","select.card.4.room.5"},
  ["select.card.4.room.6"] = {"root","select.card.4.room.6"},
  ["select.card.4.title"] = {"root","select.card.4.title"},
  ["select.page"] = {"root","select.page"},
  ["select.title"] = {"root","select.title"},
  ["hit.select.back"] = {"root","hit.select.back"},
  ["hit.select.prev"] = {"root","hit.select.prev"},
  ["hit.select.next"] = {"root","hit.select.next"},
  ["hit.select.card.1"] = {"root","hit.select.card.1"},
  ["hit.select.card.2"] = {"root","hit.select.card.2"},
  ["hit.select.card.3"] = {"root","hit.select.card.3"},
  ["hit.select.card.4"] = {"root","hit.select.card.4"},
  ["things"] = {"root","things"},
  ["furn.chair"] = {"root","things","furn.chair"},
  ["furn.plant"] = {"root","things","furn.plant"},
  ["furn.statue"] = {"root","things","furn.statue"},
  ["furn.table.h2"] = {"root","things","furn.table.h2"},
  ["furn.table.v2"] = {"root","things","furn.table.v2"},
  ["furn.shelf"] = {"root","things","furn.shelf"},
  ["furn.rug"] = {"root","things","furn.rug"},
  ["furn.rug.2"] = {"root","things","furn.rug.2"},
  ["furn.rug.3"] = {"root","things","furn.rug.3"},
  ["furn.plant.2"] = {"root","things","furn.plant.2"},
  ["select.card.1.result"] = {"root","select.card.1.result"},
  ["select.card.2.result"] = {"root","select.card.2.result"},
  ["select.card.3.result"] = {"root","select.card.3.result"},
  ["select.card.4.result"] = {"root","select.card.4.result"},
  ["settle.btn.countdown"] = {"root","settle.btn.countdown"},
  ["clues.help617"] = {"root","clues.help617"},
  ["clues.help627.hit"] = {"root","clues.help627.hit"},
  ["td.home"] = {"root","td.home"},
  ["td.home.page.1"] = {"root","td.home","td.home.page.1"},
  ["td.l1"] = {"root","td.l1"},
  ["td.l1.page.1"] = {"root","td.l1","td.l1.page.1"},
  ["td.l1.page.2"] = {"root","td.l1","td.l1.page.2"},
  ["td.l1.page.3"] = {"root","td.l1","td.l1.page.3"},
  ["td.l1.page.4"] = {"root","td.l1","td.l1.page.4"},
  ["td.l1.page.5"] = {"root","td.l1","td.l1.page.5"},
  ["td.l1.page.6"] = {"root","td.l1","td.l1.page.6"},
  ["td.l1.page.7"] = {"root","td.l1","td.l1.page.7"},
  ["td.l1.page.8"] = {"root","td.l1","td.l1.page.8"},
  ["td.l2"] = {"root","td.l2"},
  ["td.l2.page.1"] = {"root","td.l2","td.l2.page.1"},
  ["td.l2.page.2"] = {"root","td.l2","td.l2.page.2"},
  ["td.l2.page.3"] = {"root","td.l2","td.l2.page.3"},
  ["td.l2.page.4"] = {"root","td.l2","td.l2.page.4"},
  ["help617"] = {"root","help617"},
  ["help617.bg"] = {"root","help617","help617.bg"},
  ["help617.title"] = {"root","help617","help617.title"},
  ["help617.body"] = {"root","help617","help617.body"},
  ["help617.close"] = {"root","help617","help617.close"},
  ["help617.close.hit"] = {"root","help617","help617.close.hit"},
  ["hint635.menu"] = {"root","hint635.menu"},
  ["hint635.menu.bg"] = {"root","hint635.menu","hint635.menu.bg"},
  ["hint635.menu.title"] = {"root","hint635.menu","hint635.menu.title"},
  ["hint635.menu.position"] = {"root","hint635.menu","hint635.menu.position"},
  ["hint635.menu.clue"] = {"root","hint635.menu","hint635.menu.clue"},
  ["hint635.menu.close"] = {"root","hint635.menu","hint635.menu.close"},
  ["hint635.menu.position.hit"] = {"root","hint635.menu","hint635.menu.position.hit"},
  ["hint635.menu.clue.hit"] = {"root","hint635.menu","hint635.menu.clue.hit"},
  ["hint635.menu.close.hit"] = {"root","hint635.menu","hint635.menu.close.hit"},
  ["hint635.result"] = {"root","hint635.result"},
  ["hint635.result.bg"] = {"root","hint635.result","hint635.result.bg"},
  ["hint635.result.body"] = {"root","hint635.result","hint635.result.body"},
  ["hint635.result.close"] = {"root","hint635.result","hint635.result.close"},
  ["hint635.result.close.hit"] = {"root","hint635.result","hint635.result.close.hit"},
  ["block640.modal"] = {"root","block640.modal"},
  ["block640.confirm"] = {"root","block640.confirm"},
  ["block640.home"] = {"root","block640.home"},
  ["block640.l1"] = {"root","block640.l1"},
  ["block640.l2"] = {"root","block640.l2"},
}
local function path_lookup_653(roots, name)
  local route = STATIC_PATH_653[name]
  if route == nil then return nil end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(function() return cur.name end)
    if ok and rn == route[1] then
      for k = 2, #route do
        local parent = cur
        local good, child = pcall(function() return parent:GetChild(route[k]) end)
        if not good or child == nil then cur = nil; break end
        cur = child
      end
      if cur ~= nil then
        local good, actual = pcall(function() return cur.name end)
        if good and actual == name then return cur end
      end
    end
  end
  return nil
end

function Adapter:_build_name_index(roots)
  local idx = {}
  local n = 0
  for i = 1, #roots do n = index_in(roots[i], 0, idx, n) end
  self._name_idx = idx
  self._name_idx_clock = self.clock
  self._name_idx_gen = self._lookup_gen
  self._name_idx_builds = (self._name_idx_builds or 0) + 1
  self._name_idx_nodes = n
  return idx
end

 
 
 
 
 
function Adapter:_index_lookup(name, roots)
  local idx = self._name_idx
  local walked = false
  if idx == nil or self._name_idx_gen ~= self._lookup_gen or self._name_idx_clock ~= self.clock then
    idx = self:_build_name_index(roots); walked = true
  end
  local hit = idx[name]
  if hit ~= nil then
    local ok, got = pcall(function() return hit.name end)
    if ok and got == name then return hit end
  end
  if walked or self._idx_trust then return nil end
  idx = self:_build_name_index(roots)
  return idx[name]
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
      local hit = path_lookup_653(roots, name)
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
    local ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil then
      self._misses[name] = self.clock + ttl      
    elseif old ~= false and self.clock >= old then
      self._misses[name] = false                 
    end
  end
  return nil
end

 
 
 
 
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty = true
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
   
   
  self.cells_rows, self.cells_cols = rows, cols
   
  for rr=1,6 do for cc=1,6 do
    if rr>rows or cc>cols then
      local id=self:cell_id(rr,cc)
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
  return made
end

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
local DECOR = {
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
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal",
  "home", "select",
}

 
 
 
 
 
 
local SELF_MANAGED_TOP = {
  ["art641.home"] = true, ["art641.select"] = true, ["art641.game"] = true,
  help617 = true,
  ["block640.modal"] = true, ["block640.confirm"] = true,
  ["block640.home"] = true, ["block640.l1"] = true, ["block640.l2"] = true,
}

function Adapter:hide_unlisted(keep)
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
   
   
  self:prefetch(CURSOR_CONTAINERS)
  for i = 1, #CURSOR_CONTAINERS do
     
     
     
     
     
     
     
     
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(function() if ctrl.showCursor ~= true then ctrl.showCursor = true end end)
      if ok then n = n + 1 end
    end
  end
   
   
   
   
   
   
   
   
  local parts = {}
  local found, all_true = 0, true           
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      found = found + 1
      local sc, kd = "?", "?"
      pcall(function() sc = tostring(ctrl.showCursor) end)
      if sc ~= "true" then all_true = false end
       
      pcall(function() kd = tostring(ctrl.kind) end)
      if kd == "nil" then pcall(function() kd = tostring(ctrl.Kind) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.type) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.controlType) end) end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
       
    else
      all_true = false
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
   
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
   
   
  st.n = n
  if found >= #CURSOR_CONTAINERS and all_true then
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
  end
  return n
end

 
 
 
 
 
 
function Adapter:rearm_cursor(why)
  local st = self._cursor
  if st == nil then return end
  if not st.done and st.idle == 0 and st.n == 0 then return end    
  st.idle, st.done = 0, false
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
    if ctrl.SetVisible then
      pcall(function() ctrl:SetVisible(false) end)
    elseif ctrl.SetActive then
      pcall(function() ctrl:SetActive(false) end)
    end
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

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
local RAY_IDLE_STOP = 3       
local RAY_MAX_SCANS = 25      

 
 
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end     
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end

 
 
 
 
 
 
 
 
 
 
 
 
 
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local before = nil
  pcall(function() before = c.raycastTarget end)
  if before == nil then return false end           
  if before == true then return true end           
  local ok = pcall(function() c.raycastTarget = true end)
  return ok == true
end

function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
    self._ray = st
  end
   
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, samples = 0, 0, {}
  local function walk(c, depth)
    if c == nil or depth > 6 then return end
    local nm = "?"
    pcall(function() nm = tostring(c.name) end)
     
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
   
  st.scans = st.scans + 1
  st.seen, st.set = seen, set
  if seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
  if seen > 0 and st.idle >= RAY_IDLE_STOP then
     
    st.done = true
     
    if print and not st.announced then
      st.announced = true
      self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
        .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
    end
  elseif st.scans >= RAY_MAX_SCANS then
     
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
  local skip = {}
  if r ~= nil and rows ~= nil and r < rows then skip["down"] = true end
  if c ~= nil and cols ~= nil and c < cols then skip["right"] = true end

   
   
   
   
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
    print("[murdoku] 模板化家具：本轮补造 " .. tostring(n) .. " 格（缓存里共 "
      .. tostring(n) .. " 格有家具）")
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
    if not ok or not obj then return false end
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
  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3" then
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
      print("[murdoku] 家具模板：cell=" .. tostring(cell_id) .. " ← " .. sn
        .. "（prefab=" .. tostring(prefab) .. "，格子=" .. tostring(math.floor(cw)) .. "px"
        .. "，父控件=" .. tostring(parent ~= nil and parent.name or "nil") .. "）")
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
  local root = self:find("root")
  self._baked_state = self._baked_state or {}
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
      print(string.format("[murdoku] 烘焙容器 %s：找到=%s 目标=%s 子控件=%d（复述）",
        lv, tostring(box ~= nil), show and "显示" or "隐藏", touched))
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

function Adapter:set_property(id, key, value, nkey)
   
   
   
   
   
   
   
   
   
  local ctrl = self:find(id)
  if ctrl == nil then return false end

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
    if value == true and ctrl ~= nil and ctrl.SetAsLastSibling ~= nil then
      local ok = pcall(function() ctrl:SetAsLastSibling() end)
      if not ok then return false end
      self._furn_anchors = self._furn_anchors or {}
      self._furn_anchors[id] = true
    end
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
         
        if target.SetVisible then pcall(function() target:SetVisible(true) end) end

         
         
         
         
         
        if self.cfg.debug_image then
          local it = nil
          pcall(function() it = tostring(target.imageType) end)
          print(string.format("[murdoku] SetImage 后 `%s` 的 imageType = %s（Basic=按原始像素 / Stretch=填满）",
            tostring(id), tostring(it)))
        end
      end
    end

   
  elseif key == "walls" then
     
     
    return self:_apply_edges(id, "wall", value)

  elseif key == "doors" then
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
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    if value == true and ctrl.SetActive ~= nil then
      pcall(function() ctrl:SetActive(true) end)
    end
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    local vis = value and true or false
    if ctrl.SetVisible then pcall(function() ctrl:SetVisible(vis) end) end
     
     
     
     
     
    self._hidden_ids = self._hidden_ids or {}
    if vis then self._hidden_ids[id] = nil else self._hidden_ids[id] = true end
     
     
     
     
     
     
     
     
     
     
    if vis and id:sub(1, 5) == "cell." then
      self._overlay_dirty = true
    end
     
     
     
     
     
     
     
    self._subtree_dirty = true
     
     
     
     
     
     
     
     
     
     
     
     
     
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
               
              local nm = nil
              pcall(function() nm = k.name end)
              if nm ~= "furn" and nm ~= "rug_layer" and nm ~= "board.floors" and nm ~= "board.rugs" and nm ~= "x" then hide_kids(k, depth + 1) end  
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
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
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  elseif key == "raycast" then
    local want = value and true or false
    if ctrl.raycastTarget ~= nil then
      pcall(function() ctrl.raycastTarget = want end)
    end
    if ctrl.blockRaycast ~= nil then
      pcall(function() ctrl.blockRaycast = want end)
    end
    if ctrl.interactable ~= nil then
      pcall(function() ctrl.interactable = want end)
    end
  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
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
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    if self.cfg.respect_editor_rect ~= false
       and not (self.instantiated and self.instantiated[id])
       and not (self.runtime_rect and self.runtime_rect[id]) then
       
      return true
    end

     
     
     
     
     
     
     
     
    local sc = self.cfg.scale or (5 / 6)
     
     
     
     
    local function R(v) return math.floor((v or 0) + 0.5) end
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
  self.bound = self.bound or {}
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  local prev = rawget(self.bound, id)
  if prev == ctrl then return end             
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  self._bound_ctrl = self._bound_ctrl or setmetatable({}, { __mode = "k" })
  if self._bound_ctrl[ctrl] then
     
    self.bound[id] = ctrl
    return
  end
  local click = E("CursorEventType.CursorClick")
  if click == nil then
    self:warn_once("noenum", "Enum.CursorEventType.CursorClick 缺失，无法绑定点击")
    return
  end
  self.bound[id] = ctrl                       
  self._bound_ctrl[ctrl] = true                

   
   
   
   
   
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

   
   
   
  local function live_event()
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    local k = self.event_claim[id]
    local cur = nil
    if k ~= nil then cur = self.events[k] end
    return cur or node.event or { action = "click" }
  end

  ctrl:AddCursorEventListener(click, function(data)
     
     
     
     
     
     
     
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

   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  local drag = E("CursorEventType.CursorDrag")
  if drag ~= nil then
    ctrl:AddCursorEventListener(drag, function(data)
      self:_fire(live_event(), "drag", data, id)
    end)
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
        local ok = pcall(function()
          ctrl:AddKeyEventListener(et, function()
             
             
             
             
             
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
  self._subtree_dirty = false
  local hid = self._hidden_ids
  if hid == nil then return end
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
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
    if true then    
      local c = self:find(id)
      if c ~= nil then
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
               
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
   
  if self._furn_batch then self._furn_batch = false end
  if self._furn_try_pending or self._furn_dirty ~= nil then self:flush_furn_pending() end
   
   
   
  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
    if (self._furn_resync_at or -1) <= self.clock then
      self._furn_resync_at = self.clock + 0.5
      pcall(function() self:_furn_resync() end)
    end
  end
  local due = {}
  for i = #self.timers, 1, -1 do
    if self.timers[i].at <= self.clock then
      due[#due + 1] = self.timers[i]
      table.remove(self.timers, i)
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  if self._subtree_dirty then
    pcall(function() self:enforce_hidden_subtrees() end)
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
    self:signal_emit(self.signals.SAVE, self:_save_params(value))
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
function Murdoku.advance_settle_session(dt)
  if not settle_session.unlocked then
    settle_session.elapsed = math.min(60, settle_session.elapsed + math.max(0, tonumber(dt) or 0))
    if settle_session.elapsed >= 60 then settle_session.unlocked = true end
  end
end
function Murdoku.get_settle_session() return settle_session end
Murdoku.__index = Murdoku
Murdoku.VERSION = "1.0.0"

local current = nil             
local prepared_adapter = nil    
local signals_registered = false

 
 
 
 
 
 
 
 
 
 
 
 
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

 
 
 
local function murdoku_build_vis_ids(scr_now, rows)
   
   
   
   
   
   
   
   
   
   
   
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
      for c = 1, n do ids[#ids + 1] = "cell." .. r .. "." .. c end
    end
  end
  return ids
end

 
 
local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = nil
  if ad.controls ~= nil then c = ad.controls[nm] end
  if c == nil then pcall(function() c = ad:find(nm) end) end
  if c == nil then return 0 end
   
  local cur_vis = nil
  pcall(function() cur_vis = c.visible end)
  if not forcing and cur_vis == want then
    memo[nm] = want
    return 0
  end
   
  if (not forcing) and memo[nm] == want and cur_vis == nil then return 0 end
  local okw = pcall(function() c:SetVisible(want) end)
  if okw then
    memo[nm] = want
    return 1
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
      if Murdoku ~= nil and Murdoku.save_now ~= nil then pcall(function() Murdoku.save_now() end) end
    end,
    on_settle = function()
      if Murdoku ~= nil and Murdoku.save_now ~= nil then pcall(function() Murdoku.save_now() end) end
      if adapter ~= nil and adapter.signal_emit ~= nil then
        pcall(function() adapter:signal_emit(Qianxing.SIGNALS.SETTLE, { tostring(level.id) }) end)
      end
    end,
     
     
     
     
     
     
     
     
     
     
    on_settle_only = function()
      if adapter ~= nil and adapter.signal_emit ~= nil then
        pcall(function() adapter:signal_emit(Qianxing.SIGNALS.SETTLE, { tostring(level.id) }) end)
      end
    end,
    levels = level_list,
    screen = want_screen,
     
     
     
     
     
     
     
     
     
     
     
    push_cell_text = (adapter.cfg and adapter.cfg.cells
      and adapter.cfg.cells.push_text == true) or false,
     
     
     
     
    progress = function(lid) return Murdoku.progress_of(lid) end,
    on_result = function(kind, wrong, seconds) Murdoku.record_result(level.id, kind, wrong, seconds) end,
    last_level = function() return Murdoku.last_played() end,
     
     
     
    current_level = tostring(level.id),
     
    on_pick_level = function(id)
       
      Murdoku.remember_level(id)
      if id ~= level.id then
        start_other(id)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if controller ~= nil then controller.screen = nil end
      else
         
        if not controller._continue_requested then controller:do_restart() end
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
        start_other(nxt)
      else
         
        controller.toast = "已经是最后一关了"
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_solved = function(vm)
       
      adapter:signal_emit(Qianxing.SIGNALS.SOLVED, {
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

   
  adapter.on_input = function(event)
    controller:on_input(event)
    Murdoku.flush_effects()
  end

   
  if not signals_registered then
    signals_registered = true
    adapter:signal_on(Qianxing.SIGNALS.RESTORE, function(payload)
      Murdoku.restore(payload)
    end)
    adapter:signal_on(Qianxing.SIGNALS.SYNC_STATE, function(payload)
      Murdoku.on_signal("murdoku/sync", payload)
    end)
  end

   
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

   
  if current and current.controller then current.controller:_clear_verdict() end
  if adapter.clear_verdict_rings then adapter:clear_verdict_rings() end
  current = self

   
   
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
        if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") then
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
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
  if (not Murdoku._exit_art_done) and current.adapter ~= nil then
    Murdoku._exit_art_done = true
    for _, _bid in ipairs({
      "modal.exit", "modal.save", "modal.settle", "modal.cancel",
      "home.select", "home.continue", "home.shop", "home.bag",
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
  if sec ~= current.last_tick or current.controller.dirty then
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
    local n_levels = 8
    do
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
     
     
     
    do
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
         
         
         
         
         
         
         
         
        local sv = nil
        pcall(function() sv = s.visible end)
        if sv ~= true then pcall(function() s:SetVisible(true) end) end
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        local sw0, sh0 = nil, nil
         
         
         
         
         
         
         
         
        if s ~= nil and print and current._stage_rb_logged ~= true then
           
           
          current._stage_rb_logged = true
          pcall(function() sw0, sh0 = s:GetSizeDelta() end)
          print("[murdoku] ★ 棋盘容器 stage 回读 " .. tostring(sw0) .. "x" .. tostring(sh0)
            .. "（★ 归编辑器 ✓ 脚本不再写它 ✓）")
        end
      end
      local bar = nil
       
       
      if on_select then pcall(function() bar = current.adapter:find("selbar") end) end
      if bar ~= nil then
         
         
         
         
         
         
         
         
         
         
         
         
         
        if on_select then
          pcall(function() bar:SetAnchoredPosition(0, 0) end)
          pcall(function() bar:SetSizeDelta(1500, 700) end)
        end
      end
    end
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    do
       
       
       
       
       
       
       
      local STAGE_BG_ID   = 106053
      local STAGE_BG_TINT = 0xFF2C2820    
       
      local STAGE_BG_FALLBACK_ID = 107003
      local in_level = (scr_now == "level")
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
       
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
              pcall(function() ob:SetSizeDelta(677, 677) end)
              pcall(function() ob:SetAnchoredPosition(0, 0) end)
               
               
               
               
               
               
               
               
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
    local ids_key = tostring(scr_now) .. "|" .. tostring(lid0) .. "|" .. tostring(r0)
    if ids_key ~= murdoku_vis_ids_key or murdoku_vis_ids == nil then
      murdoku_vis_ids_key = ids_key
      murdoku_vis_ids = murdoku_build_vis_ids(scr_now, r0)
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
      if vis_ids ~= nil then
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
    if scr_now == "level" and ((current.frames or 0) % 30) == 0 then
      local rows, cols = 5, 5
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
      pcall(function()
        local a = current.adapter
        if a ~= nil then
          rows = a.cells_rows or (a.cfg and a.cfg.cells and a.cfg.cells.rows) or rows
          cols = a.cells_cols or (a.cfg and a.cfg.cells and a.cfg.cells.cols) or cols
        end
      end)
      local n = 0
      for r = 1, rows do
        for c = 1, cols do
           
           
           
           
           
          local cid = "cell." .. r .. "." .. c
          local cell = nil
          pcall(function() cell = current.adapter:find(cid) end)
           
           
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
               
               
               
               
               
               
               
               
               
               
               
               
               
               
              if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                local cv = nil
                pcall(function() cv = k.visible end)
                if cv ~= true then pcall(function() k:SetVisible(true) end) end
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                local cgw, cgh = nil, nil
                pcall(function() cgw, cgh = k:GetSizeDelta() end)
                if not (cgw == cw and cgh == ch) then
                  pcall(function() k:SetSizeDelta(cw, ch) end)
                end
                local cgx, cgy = nil, nil
                pcall(function() cgx, cgy = k:GetAnchoredPosition() end)
                if not (cgx == 0 and cgy == 0) then
                  pcall(function() k:SetAnchoredPosition(0, 0) end)
                end
              end
              if kn == "face" then
                 
                 
                 
                 
                 
                local fv = nil
                pcall(function() fv = k.visible end)
                if fv ~= true then pcall(function() k:SetVisible(true) end) end
                 
                local fgw, fgh = nil, nil
                pcall(function() fgw, fgh = k:GetSizeDelta() end)
                if not (fgw == cw and fgh == ch) then
                  pcall(function() k:SetSizeDelta(cw, ch) end)
                end
                local fgx, fgy = nil, nil
                pcall(function() fgx, fgy = k:GetAnchoredPosition() end)
                if not (fgx == 0 and fgy == 0) then
                  pcall(function() k:SetAnchoredPosition(0, 0) end)
                end
                face = k
              end
               
               
     
     
     
     
     
     
     
     
     
     
     
    if kn == "x" then
      local xw, xh = nil, nil
      pcall(function() xw, xh = k:GetSizeDelta() end)
      if not (xw == cw * 0.7 and xh == ch * 0.7) then
        pcall(function() k:SetSizeDelta(cw * 0.7, ch * 0.7) end)
      end
      local xx, xy = nil, nil
      pcall(function() xx, xy = k:GetAnchoredPosition() end)
      if not (xx == 0 and xy == 0) then
        pcall(function() k:SetAnchoredPosition(0, 0) end)
      end
    end
              if face == nil and k.GetChildren ~= nil then
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                for _, c2 in ipairs(kk or {}) do
                  local cn = nil
                  pcall(function() cn = tostring(c2.name) end)
                  if cn == "face" then
                     
                     
                     
                    local gv = nil
                    pcall(function() gv = c2.visible end)
                    if gv ~= true then pcall(function() c2:SetVisible(true) end) end    
                     
                    local ggw, ggh = nil, nil
                    pcall(function() ggw, ggh = c2:GetSizeDelta() end)
                    if not (ggw == cw and ggh == ch) then
                      pcall(function() c2:SetSizeDelta(cw, ch) end)
                    end
                    local ggx, ggy = nil, nil
                    pcall(function() ggx, ggy = c2:GetAnchoredPosition() end)
                    if not (ggx == 0 and ggy == 0) then
                      pcall(function() c2:SetAnchoredPosition(0, 0) end)
                    end
                    face = c2
    elseif cn == "x" then
      local zxw, zxh = nil, nil
      pcall(function() zxw, zxh = c2:GetSizeDelta() end)
      if not (zxw == cw * 0.7 and zxh == ch * 0.7) then
        pcall(function() c2:SetSizeDelta(cw * 0.7, ch * 0.7) end)
      end
      local zxx, zxy = nil, nil
      pcall(function() zxx, zxy = c2:GetAnchoredPosition() end)
      if not (zxx == 0 and zxy == 0) then
        pcall(function() c2:SetAnchoredPosition(0, 0) end)
      end
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
           
           
           
          print("[murdoku] 格子底图已点亮：" .. tostring(n) .. " 个 face（每帧保持）")
        end
      end
    end
   
   
   
   
   
  Murdoku._last_screen = scr_now
  current.frames = (current.frames or 0) + 1
end

function Murdoku.on_destroy()
  if not current then return end
  current.controller:_clear_verdict()
  Murdoku.save_now()
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
  local parent = self:_find(self.root_name .. ".board")
  if parent == nil then
    self:_note("家具实例化跳过 tag=" .. self.tag .. "：找不到 " .. self.root_name .. ".board")
    return
  end
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
  return setmetatable({
    adapter = adapter,
    tag = tostring(opts.tag or "?"),
    root_name = tostring(opts.root or ("td." .. tostring(opts.tag or "?"))),
    pages = tonumber(opts.pages) or 1,
    page = 1,
    open = false,
    inited = false,
    eager_furniture = (opts.eager_furniture == true),
    bound = {},
    log = {},
  }, { __index = M })
end

function M:_note(msg)
  self.log[#self.log + 1] = msg
  if print then print("[tutorial] " .. msg) end
end

function M:_find(name)
  local ctrl = nil
  pcall(function() ctrl = self.adapter:find(name) end)
  return ctrl
end

function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(function() ctrl:SetVisible(want and true or false) end)
  if want then pcall(function() ctrl:SetActive(true) end) end
  return true
end

function M:_bind(name, fn, resolved)
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
  if ok then self.bound[ctrl] = true end
  return ok
end

 
function M:_bind_steps()
  if self.pages < 2 then return end
  self._steps_bound = self._steps_bound or {}
  if self._steps_bound[self.page] then return end
  local prefix = self.root_name .. ".page." .. tostring(self.page)
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
  if self.open then self:_bind_steps() end
  for i = 1, self.pages do
    self:_visible(self.root_name .. ".page." .. tostring(i), i == self.page)
  end
  self:_visible(self.root_name .. ".btn.prev", self.page > 1)
  self:_visible(self.root_name .. ".btn.next", true)
  return self
end

function M:init()
  if self.inited then return self end
  if self:_find(self.root_name) == nil then return self end
  self.inited = true

  self:_bind(self.root_name .. ".btn.prev", function() self:prev() end)
  self:_bind(self.root_name .. ".btn.next", function() self:next() end)
  self:_bind(self.root_name .. ".btn.close", function() self:close() end)
  self:_bind(self.root_name .. ".btn.skip", function() self:close() end)
  self.page = 1
  self:_paint()
   
  if self.eager_furniture then self:_ensure_furniture() end
  self:_visible(self.root_name, false)
  self:_note("静态教程 init 完成 tag=" .. self.tag .. " pages=" .. tostring(self.pages))
  return self
end

function M:open_ui()
  self.open = true
  self:_visible(self.root_name, true)
  self:_ensure_furniture()
  self:_paint()
  self:_note("打开 tag=" .. self.tag .. " 第 " .. tostring(self.page) .. " 页")
  return self
end

function M:close()
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
    out[i] = {
      id = lv.id, name = lv.name, difficulty = lv.difficulty,
      size = lv.size, suspects = lv.suspects, victim = lv.victim,
      rooms = lv.rooms, objects = lv.objects,
       
       
      room_boxes = RoomMap.boxes(lv),
       
       
      room_names = lv.room_names,
    }
  end
  return out
end

return M

end

__M["levels.case_001"] = function()
 





 
 return {
  id = "case_001",
  name = "案件 001 · 夜盗独行",
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
    { id = "A", name = "值班保安", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "前台姑娘", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "夜班清洁工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "旧识古董商", portrait = "portrait.D", gender = "male" },
    { id = "V", name = "收藏家", portrait = "portrait.V",     is_victim = true },
  },

  victim = { id = "V", name = "收藏家" },

   
  roles = {
    thief = "D",
  },

   
  clues = {
    { type = "in_col",         who = "V", c = 5 },                 
    { type = "beside_object",  who = "D", object = "植物" },        
    { type = "only_on_object", who = "A", object = "地毯" },        
    { type = "on_object",      who = "C", object = "椅子" },        
    { type = "beside_object",  who = "B", object = "桌子" },        
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
  name = "案件 002 · 双影",
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
    { id = "A", name = "夜班门卫", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "画廊助理", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "临时搬运工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "鉴定师", portrait = "portrait.D",     gender = "male" },
    { id = "E", name = "随行记者", portrait = "portrait.E",   gender = "female" },
    { id = "V", name = "馆长", portrait = "portrait.V",       is_victim = true },
  },

  victim = { id = "V", name = "馆长" },

   
  roles = {
    thief = "D",
  },

   
  clues = {
    { type = "beside_object", who = "B", object = "桌子" },                   
    { type = "n_on_object",   object = "椅子", n = 2 },                       
    { type = "beside_object", who = "A", object = "书架" },                   
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
 
return {["id"] = "case_003", ["name"] = "案件 003", ["difficulty"] = "hard", ["size"] = {["rows"] = 6, ["cols"] = 6}, ["room_names"] = {"R1", "R2", "R3", "R4"}, ["rules"] = {["one_per_row"] = true, ["one_per_col"] = true, ["one_per_room"] = false, ["place_all"] = true, ["tie_policy"] = "forbid"}, ["walls"] = {{"v", 1, 4}, {"v", 2, 4}, {"h", 2, 4}, {"v", 3, 3}, {"h", 3, 3}, {"v", 3, 4}, {"h", 4, 1}, {"v", 4, 2}, {"h", 4, 2}, {"v", 4, 4}, {"h", 4, 5}, {"h", 4, 6}, {"v", 5, 2}, {"h", 5, 3}, {"h", 5, 4}, {"h", 5, 5}, {"v", 6, 5}}, ["doors"] = {{"v", 2, 4}, {"h", 3, 3}, {"h", 4, 2}, {"h", 4, 5}, {"h", 5, 4}}, ["objects"] = {["桌子"] = {["cells"] = {{["r"] = 6, ["c"] = 4}, {["r"] = 4, ["c"] = 4}}, ["occupiable"] = false, ["kind"] = "table"}, ["植物"] = {["cells"] = {{["r"] = 1, ["c"] = 1}}, ["occupiable"] = false, ["kind"] = "plant"}, ["椅子"] = {["cells"] = {{["r"] = 2, ["c"] = 1}, {["r"] = 2, ["c"] = 4}}, ["occupiable"] = true, ["kind"] = "chair"}, ["地毯"] = {["cells"] = {{["r"] = 3, ["c"] = 3}, {["r"] = 4, ["c"] = 2}}, ["occupiable"] = true, ["kind"] = "carpet"}}, ["blocked"] = {}, ["water"] = {}, ["suspects"] = {{["id"] = "A", ["name"] = "A", ["portrait"] = "portrait.A"}, {["id"] = "B", ["name"] = "B", ["portrait"] = "portrait.B"}, {["id"] = "C", ["name"] = "C", ["portrait"] = "portrait.C"}, {["id"] = "D", ["name"] = "D", ["portrait"] = "portrait.D"}, {["id"] = "E", ["name"] = "E", ["portrait"] = "portrait.E"}, {["id"] = "V", ["name"] = "V", ["portrait"] = "portrait.V", ["is_victim"] = true}}, ["victim"] = {["id"] = "V", ["name"] = "V"}, ["roles"] = {["thief"] = "A"}, ["clues"] = {{["type"] = "beside_object", ["who"] = "A", ["object"] = "植物"}, {["type"] = "in_room", ["who"] = "E", ["room"] = 4}, {["type"] = "in_room", ["who"] = "D", ["room"] = 3}, {["type"] = "on_object", ["who"] = "B", ["object"] = "椅子"}, {["type"] = "beside_object", ["who"] = "B", ["object"] = "植物"}, {["type"] = "all_of", ["clauses"] = {{["type"] = "only_on_object", ["who"] = "C", ["object"] = "地毯"}, {["type"] = "in_room", ["who"] = "V", ["room"] = 2}}}}, ["general_clues"] = {}, ["meta"] = {["announce"] = "unknown"}, ["solution"] = {["A"] = {["r"] = 1, ["c"] = 2}, ["B"] = {["r"] = 2, ["c"] = 1}, ["C"] = {["r"] = 3, ["c"] = 3}, ["D"] = {["r"] = 5, ["c"] = 4}, ["E"] = {["r"] = 6, ["c"] = 5}, ["V"] = {["r"] = 4, ["c"] = 6}}}

end

__M["levels.case_004"] = function()
 
return {["id"] = "case_004", ["name"] = "案件 004", ["difficulty"] = "hard", ["size"] = {["rows"] = 6, ["cols"] = 6}, ["room_names"] = {"R1", "R2", "R3", "R4"}, ["rules"] = {["one_per_row"] = true, ["one_per_col"] = true, ["one_per_room"] = false, ["place_all"] = true, ["tie_policy"] = "forbid"}, ["walls"] = {{"v", 1, 3}, {"v", 2, 3}, {"v", 3, 3}, {"h", 3, 3}, {"h", 3, 4}, {"h", 3, 5}, {"h", 3, 6}, {"h", 4, 1}, {"v", 4, 2}, {"h", 4, 2}, {"v", 5, 2}, {"v", 6, 2}}, ["doors"] = {{"v", 2, 3}, {"v", 4, 2}, {"h", 4, 2}, {"h", 3, 5}, {"v", 6, 2}}, ["objects"] = {["植物"] = {["cells"] = {{["r"] = 5, ["c"] = 6}}, ["occupiable"] = false, ["kind"] = "plant"}, ["椅子"] = {["cells"] = {{["r"] = 1, ["c"] = 2}, {["r"] = 6, ["c"] = 5}}, ["occupiable"] = true, ["kind"] = "chair"}, ["地毯"] = {["cells"] = {{["r"] = 2, ["c"] = 3}, {["r"] = 6, ["c"] = 2}}, ["occupiable"] = true, ["kind"] = "carpet"}}, ["blocked"] = {}, ["water"] = {}, ["suspects"] = {{["id"] = "A", ["name"] = "A", ["portrait"] = "portrait.A"}, {["id"] = "B", ["name"] = "B", ["portrait"] = "portrait.B"}, {["id"] = "C", ["name"] = "C", ["portrait"] = "portrait.C"}, {["id"] = "D", ["name"] = "D", ["portrait"] = "portrait.D"}, {["id"] = "E", ["name"] = "E", ["portrait"] = "portrait.E"}, {["id"] = "V", ["name"] = "V", ["portrait"] = "portrait.V", ["is_victim"] = true}}, ["victim"] = {["id"] = "V", ["name"] = "V"}, ["roles"] = {["thief"] = "E"}, ["clues"] = {{["type"] = "same_room", ["a"] = "A", ["b"] = "D"}, {["type"] = "all_of", ["clauses"] = {{["type"] = "on_object", ["who"] = "D", ["object"] = "椅子"}, {["type"] = "beside_object", ["who"] = "V", ["object"] = "植物"}}}, {["type"] = "on_object", ["who"] = "B", ["object"] = "椅子"}, {["type"] = "row_offset", ["who"] = "E", ["other"] = "C", ["d"] = 1}, {["type"] = "on_object", ["who"] = "E", ["object"] = "椅子"}, {["type"] = "only_on_object", ["who"] = "C", ["object"] = "地毯"}}, ["general_clues"] = {}, ["meta"] = {["announce"] = "unknown", ["false_clue"] = 5}, ["solution"] = {["E"] = {["r"] = 3, ["c"] = 1}, ["B"] = {["r"] = 1, ["c"] = 2}, ["C"] = {["r"] = 2, ["c"] = 3}, ["D"] = {["r"] = 6, ["c"] = 5}, ["A"] = {["r"] = 5, ["c"] = 4}, ["V"] = {["r"] = 4, ["c"] = 6}}}

end

 
 




































 

 
 
 
 
local FORCE_LEVEL = nil

 
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
        print("[murdoku] ===== 构建标记 v635 / 2026-11-05 / 正式版635：选中人物揭示与线索验证 =====")
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
       
       
       
       
       
       
       
       
       
       
       
       
       
       
       
      rows     = 5,             
      cols     = 5,
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
    },
    furn_parent = "fart.furn",    
    furn_tpl_base = 108,
     
    furn_scale = 0.93,
    furn_scale_by_kind = { rug = 0.82, rug_2 = 0.82, rug_3 = 0.82, statue = 0.85 },
     
    furn_scale_axis_by_kind = {
      rug_2 = { x = 0.93, y = 0.762 },
      rug_3 = { x = 0.762, y = 0.93 },
    },
     
     
    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 }, table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },

     
     
     
     
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
    key_control_fallbacks = { "board", "cell.1.1", "topbar" },

     
     
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
    local n, note = adapter:bind_keys(KEY_SPEC)
    if n > 0 then
      keyboard_bound = true
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
local tutorial_seen = {}          



 
 
local TUT_SETS = {
  home = { tag = "home", root = "td.home", text = "td.home", pages = 1 },
  l1   = { tag = "l1",   root = "td.l1",   text = "td.l1",   pages = 8 },
  l2   = { tag = "l2",   root = "td.l2",   text = "td.l2",   pages = 4 },
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
    return mod.new(adapter, { tag = spec.tag, root = spec.root, text = spec.text, pages = spec.pages, content = content })
  end)
  if not ok or type(made) ~= "table" then
    if printerr then printerr("[murdoku] 教程实例建不出来（" .. tostring(spec.tag) .. "）：" .. tostring(made)) end
    return nil
  end
  tutorial_inst[spec.tag] = made
  return made
end

 




















 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
local function tut_visible(name)
  if adapter == nil or name == nil then return false end
  local c = nil
  pcall(function() c = adapter:find(name) end)
  if c == nil then return false end
  local v = nil
  pcall(function() v = c.visible end)
  return v == true
end

local function tutorial_home_visible()
  return tut_visible("home")
end

local TUT_PROBE_NAMES = { "home", "select.card.1", "select.title", "clues", "board" }    
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

 
 
 
local function tut_key_and_probe()
  local cur = nil
  pcall(function()
    if Murdoku ~= nil and Murdoku.current ~= nil then cur = Murdoku.current() end
  end)

   
   
  if adapter ~= nil and adapter.prefetch ~= nil then
    pcall(function() adapter:prefetch(TUT_PROBE_NAMES) end)
  end
  local home  = tut_visible("home")
  local card1 = tut_visible("select.card.1")
  if not card1 then card1 = tut_visible("select.title") end    
  local clues = tut_visible("clues")
  local board = tut_visible("board")

  local scr, id = nil, nil
  if cur ~= nil then
    pcall(function() scr = cur.screen end)
    pcall(function() id = cur.level and cur.level.id end)
  end

  local key = nil
  if cur ~= nil then
    if home then
      key = "home"                        
    elseif card1 then
      key = nil                           
    elseif clues or board then
      if id ~= nil then key = tostring(id) end    
    end
     
  end

  return key, { home = home, card1 = card1, clues = clues, board = board, scr = scr, id = id }
end

 
 
 
local tut_last_probe = nil
local function current_tut_key()
  local key, probe = tut_key_and_probe()
  tut_last_probe = probe
  return key
end

 
local help617 = { bound = false, entry_bound = false, close_bound = false, open = false, overlay = false }
local function help_visible(c, v)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c.visible end)
  if actual ~= v then
    pcall(function() if c.SetVisible then c:SetVisible(v) else c.visible = v end end)
  end
  if v then
    local active = nil
    pcall(function() active = c.active end)
    if active ~= true then pcall(function() if c.SetActive then c:SetActive(true) end end) end
  end
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
    help617.close_bound = util:_bind("help617.close.hit", close, c["help617.close.hit"])
  end
  if not help617.entry_bound and c["clues.help627.hit"] ~= nil then
    help_visible(c["clues.help617"], true)
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
          tutorial_seen[tag] = true
          inst:go(1)
          inst:open_ui()

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
      help_write(c["help617.body"], "可站人的家具：" .. (#yes > 0 and table.concat(yes, "、") or "本关未配置") .. "。\n\n不可站人的家具：" .. (#no > 0 and table.concat(no, "、") or "本关未配置") .. "。\n\n普通可站空格也可放人；墙体、禁用格及水域不能站人。\n具体家具以本关配置为准。")
      help617.level = id
      help617.open = true
      help_visible(c["help617"], true)

    end, c["clues.help627.hit"])
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
        tutorial_seen.home = true
        inst:go(1)
        inst:open_ui()
      end
    end, c["home.tutorial627.hit"])
  end
  help617.bound = help617.entry_bound and help617.close_bound
end

 
local hint635_ui={}
local function tick_hint635()
  if not adapter then return end
  local util=tutorial_instance(TUT_SETS.l1)
  if not util then return end
  local gen=adapter._lookup_gen or 0
  if hint635_ui.generation~=gen then hint635_ui={generation=gen,controls={},bound={}} end
  local h=hint635_ui
  local names={"hint635.menu","hint635.result","hint635.menu.bg","hint635.menu.title",
    "hint635.menu.position","hint635.menu.clue","hint635.menu.close",
    "hint635.result.bg","hint635.result.body","hint635.result.close",
    "hint635.menu.position.hit","hint635.menu.clue.hit","hint635.menu.close.hit","hint635.result.close.hit"}
  for _,name in ipairs(names) do
    if not h.controls[name] then
      h.controls[name]=adapter:find(name)
      if h.controls[name] then help_visible(h.controls[name],name~="hint635.menu" and name~="hint635.result") end
    end
  end
  local cur=Murdoku.current()
  local ctrl=cur and cur.controller
  local actions={["hint635.menu.position.hit"]="position",["hint635.menu.clue.hit"]="clue",
    ["hint635.menu.close.hit"]="close",["hint635.result.close.hit"]="close"}
  for name,action in pairs(actions) do
    if not h.bound[name] and h.controls[name] then
      local chosen=action
      h.bound[name]=util:_bind(name,function()
        local c=Murdoku.current()
        if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
      end,h.controls[name])
    end
  end
  if ctrl and (ctrl.screen~=nil or ctrl.modal~=nil or overlay_open()) then ctrl.hint635=nil end
  local state=ctrl and ctrl.hint635
  local signature=state and (state.kind..":"..(state.text or "")) or "closed"
  local used=ctrl and ctrl.core and ctrl.core.hint635_used or {position=0,clue=0}
  signature=signature..":"..tostring(used.position)..":"..tostring(used.clue)
  if h.signature~=signature or h.controller~=ctrl then
    h.signature=signature;h.controller=ctrl
    help_visible(h.controls["hint635.menu"],state~=nil and state.kind=="menu")
    help_visible(h.controls["hint635.result"],state~=nil and state.kind=="message")
    help_write(h.controls["hint635.menu.position"],"揭示选中人物的所在位置（"..tostring(1-used.position).."/1）")
    help_write(h.controls["hint635.menu.clue"],"验证选中线索的真假（"..tostring(2-used.clue).."/2）")
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
  local help_want = key ~= nil and key ~= "home" and help_cur ~= nil
    and help_cur.controller ~= nil and help_cur.controller.modal == nil and not overlay_open()
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
  if key ~= nil and tut_key_frames >= TUT_STABLE_NEED then want_tag = TUT_TRIGGER[key] end
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
           
          if tut_shown_frames >= TUT_KEEP_NEED then tutorial_seen[tag] = true end
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
local function sync_block640()
  if not adapter then return end
  local util = tutorial_instance(TUT_SETS.l1)
  if not util then return end
  local cur = Murdoku.current()
  local ctrl = cur and cur.controller
  for _, spec in ipairs(BLOCK640) do
    local want = false
    if spec.tag == "modal" then
      want = ctrl ~= nil and ctrl.modal ~= nil
      -- 654: 兼容旧退出状态；独立选关页不启用旧式选关遮罩。
      if want and ctrl.modal.kind == "levelselect" and (ctrl.screen == "select" or ctrl.screen == "home") then want = false end
    elseif spec.tag == "confirm" then want = ctrl ~= nil and ctrl.pending ~= nil
    else local inst = tutorial_inst[spec.tag]; want = inst ~= nil and inst.open == true end
    local name = "block640." .. spec.tag
    local panel, hit = adapter:find(name), adapter:find(name .. ".hit")
    -- 子级保持自身显示，父级负责整树门控；新句柄第一次绑定时初始化。
    if hit ~= nil and not util.bound[hit] then help_visible(hit, true) end
    util:_bind(name .. ".hit", function() end, hit)
    -- 654: 父级统一控制整树显隐，子级保持可命中，避免与射线补扫互相覆盖。
    want = not not want
    if hit ~= nil then
      pcall(function() if hit.clickAudioId ~= 0 then hit.clickAudioId = 0 end end)
    end
    help_visible(panel, want)
    if want then
      pcall(function() panel.showCursor = true end)
      pcall(function() panel.disableCursorEventPassthrough = true end)
      pcall(function() panel:SetAsLastSibling() end)
      for _, target in ipairs(spec.targets) do
        local c = adapter:find(target)
        if c then pcall(function() c:SetAsLastSibling() end) end
      end
    end
  end
end

 
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
local function write_art_color650(c, key, want)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c[key] end)
  if actual ~= want then pcall(function() c[key] = want end) end
end
local art647_tint_key = nil
local function sync_art647()
  local cur = Murdoku.current()
  local ad = cur and cur.adapter
  local ctrl = cur and cur.controller
  if not ad or not ctrl then return end
  local cd = ad:find("settle.btn.countdown")
  write_art_color650(cd, "textColor", 0x00FFFFFF)
  local ready = ctrl:can_settle()
  local key = (ready and "1" or "0") .. "|" .. tostring(ctrl.screen or "")
  art647_tint_key = key
  for _, e in ipairs(SETTLE_ART_TINT) do
    local c = ad:find(e[1])
    write_art_color650(c, "imageColor", ready and e[2] or e[3])
  end
end

 
 
 
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
  local dl = ad:find("art647.select.diamond.left")
  local dr = ad:find("art647.select.diamond.right")
  local NORMAL, DIM = 0xFFFFFFFF, 0x7FFFFFFF
  write_art_color650(dl, "imageColor", (page > 1) and NORMAL or DIM)
  write_art_color650(dr, "imageColor", (page < pages) and NORMAL or DIM)
end


function OnInit()
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

function OnUpdate(dt)
  Murdoku.advance_settle_session(dt)





















  if LOAD_ERR ~= nil or Murdoku == nil then return end
   
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
end

 
function OnLevelUpdate(dt) end

function OnDestroy()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  Murdoku.on_destroy()
  if print then print("[murdoku] destroyed") end
end

