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
local RoomMap = require("room_map")
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
