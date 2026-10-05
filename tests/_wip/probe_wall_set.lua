local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "tests/_wip"
local root = HERE .. "/../.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/?.lua;" .. package.path
local Core = require("murdoku_core")
local RoomMap = require("room_map")
local lv = require("levels.demo_selftest")
print("原始 level.walls 条数 = " .. tostring(#(lv.walls or {})))
print("原始 level.doors 条数 = " .. tostring(#(lv.doors or {})))
local set = RoomMap.build_walls(lv, 5, 5)
local n, sample = 0, {}
for k in pairs(set) do n = n + 1; if n <= 8 then sample[#sample+1] = k end end
print("RoomMap.build_walls 产出 = " .. n .. " 条   样例: " .. table.concat(sample, "  "))
local core = Core.new(lv)
if core ~= nil then
  pcall(function() core:reset() end)
  local n2 = 0
  for _ in pairs(core.wall_set or {}) do n2 = n2 + 1 end
  print("core.wall_set = " .. n2 .. " 条")
  local v = core:view()
  local withwall, wt, dt = 0, 0, 0
  for r = 1, core.rows do for c = 1, core.cols do
    local cd = v.cells[r][c]; local wc = 0
    for _, s in ipairs({"up","down","left","right"}) do
      if cd.walls[s] == true then wt = wt + 1; wc = wc + 1 end
      if cd.doors[s] == true then dt = dt + 1 end
    end
    if wc > 0 then withwall = withwall + 1 end
  end end
  print("view(): 有墙格子 = " .. withwall .. " / " .. (core.rows*core.cols) .. " ，墙边 = " .. wt .. " ，门边 = " .. dt)
  local c22 = v.cells[2][2]
  print("cell.2.2 walls: up=" .. tostring(c22.walls.up) .. " down=" .. tostring(c22.walls.down) .. " left=" .. tostring(c22.walls.left) .. " right=" .. tostring(c22.walls.right))
else print("Core.new 失败") end
