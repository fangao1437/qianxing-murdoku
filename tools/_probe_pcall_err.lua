--[[----------------------------------------------------------------------------
  tools/_probe_pcall_err.lua —— 抓「被 pcall 吞掉的错误」。

  用途（第一遍代码体检）：某个测试从绿变红，而**测试自己把 OnUpdate 包在 pcall 里**
  ⇒ 真正的报错信息一个字都看不到，只能看到"某断言没过"。
  这个探针把全局 `pcall` 换成一个**记账版**：照常执行、照常返回，
  但把每一个失败的错误串去重记下来，最后统一打印。

  为什么不能直接改测试：那条红线（E5）不让动断言/测试；
  而且"改测试让它闭嘴"正是本项目反复吃亏的模式。探针是**外部仪器**，不动被测物。

  用法：lua tools/_probe_pcall_err.lua <测试文件>       默认 tests/grid_cost.lua
----------------------------------------------------------------------------]]--

local target = (arg and arg[1]) or "tests/grid_cost.lua"
local here = (arg and arg[0]) or "tools/_probe_pcall_err.lua"
local root = here:gsub("tools[/\\]_probe_pcall_err%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local realpcall = pcall
local seen, order, total = {}, {}, 0

_G.pcall = function(f, ...)
  local r = table.pack(realpcall(f, ...))
  if not r[1] then
    total = total + 1
    local msg = tostring(r[2])
    if seen[msg] == nil then
      seen[msg] = { n = 0 }
      order[#order + 1] = msg
    end
    seen[msg].n = seen[msg].n + 1
  end
  return table.unpack(r, 1, r.n)
end

-- ⚠️ 被探测的测试用 `arg[0]` 反推工程根目录 ⇒ 必须伪装成"它自己的路径"。
if arg then arg[0] = root .. target end
local chunk, err = loadfile(root .. target)
if chunk == nil then
  print("loadfile 失败：" .. tostring(err))
  os.exit(2)
end
local ok, e = realpcall(chunk)

print("")
print("================ 被 pcall 吞掉的错误（去重）================")
print("失败总数 " .. tostring(total) .. "，去重后 " .. tostring(#order) .. " 种")
table.sort(order, function(a, b) return seen[a].n > seen[b].n end)
for i = 1, #order do
  print(string.format("  %6d 次  %s", seen[order[i]].n, order[i]))
end
print("（测试自身结果见上方输出；本探针不改任何断言）")
if not ok then print("外层：chunk 抛错 " .. tostring(e)) end
os.exit(0)
