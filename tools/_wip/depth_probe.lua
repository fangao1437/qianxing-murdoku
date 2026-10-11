-- tools/_wip/depth_probe.lua —— 只读：算 lua/main.lua 里 on_update 的块深度
-- 用法：lua tools/_wip/depth_probe.lua <file> <from> <to>
local file = arg[1] or "lua/main.lua"
local from = tonumber(arg[2]) or 1
local to   = tonumber(arg[3]) or 1e9

local lines = {}
for line in io.open(file):lines() do lines[#lines + 1] = line end

local Q = string.char(34)   -- "
local SQ = string.char(39)  -- '

local function strip(s)
  local o, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "-" and s:sub(i, i + 1) == "--" then
      break
    elseif c == Q or c == SQ then
      local q = c
      i = i + 1
      while i <= n and s:sub(i, i) ~= q do
        if s:sub(i, i) == "\\" then i = i + 1 end
        i = i + 1
      end
      o[#o + 1] = " "
    else
      o[#o + 1] = c
    end
    i = i + 1
  end
  return table.concat(o)
end

local opens = { ["function"] = 1, ["if"] = 1, ["for"] = 1, ["while"] = 1, ["do"] = 1, ["repeat"] = 1 }
local depth = 0
for n = 1, #lines do
  local s = strip(lines[n])
  local ind = #(s:match("^%s*") or "")
  local op, cl = 0, 0
  for w in s:gmatch("%a+") do
    if opens[w] then op = op + 1 end
    if w == "end" then cl = cl + 1 end
  end
  local before = depth
  depth = depth + op - cl
  if n >= from and n <= to then
    print(string.format("%5d  d%02d->%02d  ind=%2d  %s", n, before, depth, ind, s:sub(1, 76)))
  end
end
print("final depth = " .. depth)
