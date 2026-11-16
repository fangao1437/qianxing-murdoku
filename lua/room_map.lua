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
