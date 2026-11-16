local RoomMap = require("room_map")
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
function M.all()
  M._errors = {}
  local out = {}
  for i = 1, #LIST do
    local ok, lv = pcall(require, LIST[i])
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
      local ok, lv = pcall(require, LIST[i])
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
