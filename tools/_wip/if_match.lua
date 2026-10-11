-- tools/_wip/if_match.lua —— 只读：列出指定范围内 if / for / while / do / function 的配对
-- 用法：lua tools/_wip/if_match.lua <file> <from> <to> [keyword]
local file = arg[1] or "lua/main.lua"
local from = tonumber(arg[2]) or 1
local to   = tonumber(arg[3]) or 1e9
local want = arg[4]                     -- 只看含该子串的开块行

local lines = {}
for line in io.open(file):lines() do lines[#lines + 1] = line end

local Q, SQ = string.char(34), string.char(39)
local function strip(s)
  local o, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "-" and s:sub(i, i + 1) == "--" then break
    elseif c == Q or c == SQ then
      local q = c; i = i + 1
      while i <= n and s:sub(i, i) ~= q do
        if s:sub(i, i) == "\\" then i = i + 1 end
        i = i + 1
      end
      o[#o + 1] = " "
    else o[#o + 1] = c end
    i = i + 1
  end
  return table.concat(o)
end

-- 简化词法：按 token 扫描，维护块栈
local stack = {}          -- { {kw=, line=, text=} }
local opens = { ["function"]=true, ["if"]=true, ["for"]=true, ["while"]=true, ["do"]=true }
local results = {}

for n = 1, #lines do
  local s = strip(lines[n])
  -- 同一行内顺序扫描 token（够用：本项目一行最多一个块关键字）
  for w in s:gmatch("[%a_]+") do
    if opens[w] then
      stack[#stack + 1] = { kw = w, line = n, text = lines[n]:sub(1, 70) }
    elseif w == "end" then
      local top = table.remove(stack)
      if top ~= nil and top.kw ~= "do" and top.kw ~= "function" then
        -- 记录 if/for/while 的配对
        if top.line >= from and top.line <= to then
          if want == nil or lines[top.line]:find(want, 1, true) then
            results[#results + 1] = string.format("  %-8s L%-5d -> end L%-5d  | %s",
              top.kw, top.line, n, top.text)
          end
        end
      elseif top ~= nil and top.kw == "function" then
        if top.line >= from and top.line <= to then
          if want == nil or lines[top.line]:find(want, 1, true) then
            results[#results + 1] = string.format("  %-8s L%-5d -> end L%-5d  | %s",
              "function", top.line, n, top.text)
          end
        end
      end
    end
  end
end

for _, r in ipairs(results) do print(r) end
print("#blocks listed = " .. #results .. "  (stack left = " .. #stack .. ")")
if #stack > 0 then
  for i = 1, math.min(#stack, 8) do
    local s = stack[i]
    print(string.format("  LEFT OPEN: %s L%d | %s", s.kw, s.line, s.text))
  end
end
