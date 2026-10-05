--[[----------------------------------------------------------------------------
  tools/_audit_globals.lua —— 「读了一个不存在的变量」这一类坑的**探测器**。

  为什么要有它（第一遍代码体检，2026-10-05）：
    这一轮连续暴露的坑里最阴的一类是「**恒真/恒假判据**」，而它的共同成因是
      · `ui_controller.build_layout` 里内联隐藏判据读了不存在的局部 `screen`
        ⇒ `screen ~= "home"` 退化成 `nil ~= "home"` ⇒ **恒真** ⇒ 每帧翻面。
    Lua 的语义决定了这种坑**不报错**：读不到局部就去找全局，全局没有就是 nil，
    比较照样有结果 —— 于是"判据永远为真"，只在真机上表现成诡异行为。

  做法（**动态**，不是静态猜测）：
    给 `_G` 装一个 `__index` 元方法。Lua 只在**键不存在**时才走 `__index`
    ⇒ 每一次触发都精确对应「读了一个当前不存在的全局」。
    在元方法里用 `debug.getinfo(2, "Sl")` 取回**读取点的源文件与行号**，
    按 (源文件, 行号, 名字) 去重后打印。

  用法：  lua tools/_audit_globals.lua [测试文件...]
          默认跑：selftest / ui_math / board_bg / grid_cost / hide_safety /
                  prop_ledger / effects_wiring / input_logic / entry_smoke

  读结果：**白名单外**的每一条都是一个候选「幻影变量」。
    · 真机上确实由编辑器注入的脚本变量（FORCE_LEVEL / Murdoku …）在白名单里；
    · 真正的候选要看它**出现在哪个判断里** —— 见输出的源码行。
  退出码恒为 0（这是探测器，不是断言）。
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tools/_audit_globals.lua"
local root = here:gsub("tools[/\\]_audit_globals%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print

-- 这些名字**允许**是 nil（编辑器注入的脚本变量、引擎全局、测试自己造的钩子）
local WHITELIST = {
  -- 编辑器「脚本变量」里配的（官方：入口脚本拿得到，没配就是 nil）
  FORCE_LEVEL = true, SCRIPT_ID = true, DEBUG_UI = true,
  -- 引擎/沙箱全局
  game = true, script = true, print = true, printerr = true, Color = true,
  ColorValue = true, Vector2 = true, Vector3 = true, Enum = true,
  math = true, table = true, string = true, os = true, io = true, debug = true,
  coroutine = true, utf8 = true, _G = true, _VERSION = true, arg = true,
  tostring = true, tonumber = true, type = true, pairs = true, ipairs = true,
  pcall = true, xpcall = true, error = true, assert = true, select = true,
  next = true, rawget = true, rawset = true, rawequal = true, rawlen = true,
  setmetatable = true, getmetatable = true, unpack = true, load = true,
  loadstring = true, require = true, collectgarbage = true, dofile = true,
  loadfile = true, setfenv = true, getfenv = true, module = true, newproxy = true,
  -- 测试脚手架自己造的
  T = true, KIT = true, HARNESS = true, PASS = true, FAIL = true,
}

local hits, order = {}, {}
local in_hook = false

setmetatable(_G, {
  __index = function(_, k)
    -- 防递归：元方法里自己也会读全局
    if in_hook then return nil end
    in_hook = true
    local key = tostring(k)
    if not WHITELIST[key] then
      local info = debug.getinfo(2, "Sl")
      local src = (info and info.short_src) or "?"
      local line = (info and info.currentline) or -1
      local id = src .. ":" .. tostring(line) .. "  " .. key
      if hits[id] == nil then
        hits[id] = { n = 0 }
        order[#order + 1] = id
      end
      hits[id].n = hits[id].n + 1
    end
    in_hook = false
    return nil
  end,
})

local files = {}
for i = 1, #arg do files[#files + 1] = arg[i] end
if #files == 0 then
  files = {
    "tests/selftest.lua", "tests/ui_math.lua", "tests/board_bg.lua",
    "tests/grid_cost.lua", "tests/hide_safety.lua", "tests/prop_ledger.lua",
    "tests/effects_wiring.lua", "tests/input_logic.lua", "tests/entry_smoke.lua",
  }
end

out("=== 幻影变量探测（读一个不存在的全局）===")
for i = 1, #files do
  local f = files[i]
  out("--- 跑 " .. f)
  local chunk, err = loadfile(root .. f)
  if chunk == nil then
    out("    跳过（loadfile 失败：" .. tostring(err) .. "）")
  else
    -- ⚠️ 测试文件普遍用 `arg[0]` 反推工程根目录（`gsub("tests[/\\]xxx%.lua$","")`）。
    --    被 loadfile 进来时 `arg[0]` 仍然是**本探测器**的路径 ⇒ 它会算错根目录
    --    （实测：board_bg 去开 `tools/_audit_globals.lua/dist/client_script.lua`）。
    --    ⇒ 跑每个测试前把 `arg[0]` 换成"它自己的路径"，跑完还原。
    --
    -- ⚠️ 另一半：测试跑完会调 `os.exit(code)`（selftest 就这样）—— 那会**直接杀掉
    --    本探测器**，后面的测试一个都跑不到（实测只跑到 selftest 就没了）。
    --    ⇒ 临时把 `os.exit` 换成"抛一个带标记的错误"，外层 pcall 接住，继续下一个。
    local saved0 = arg and arg[0]
    local saved_exit = os.exit
    if arg then arg[0] = root .. f end
    os.exit = function(code, close) error({ __audit_exit = true, code = code }, 0) end
    local ok, e = pcall(chunk)
    os.exit = saved_exit
    if arg then arg[0] = saved0 end
  end
end

out("")
out("=== 命中（白名单外，按出现次数降序）===")
if #order == 0 then
  out("  （无）")
else
  local rows = {}
  for i = 1, #order do rows[#rows + 1] = { id = order[i], n = hits[order[i]].n } end
  table.sort(rows, function(a, b) return a.n > b.n end)
  for i = 1, #rows do
    out(string.format("  %6d 次   %s", rows[i].n, rows[i].id))
  end
end
out("")
out("提示：把命中行的源码调出来看 —— 它出现在哪个判断里，就是哪一条「恒真/恒假」候选。")
out("      `tests/` 里的命中多半是测试脚手架自己的可选钩子，重点看 `lua/` 与 `dist/` 的行。")
