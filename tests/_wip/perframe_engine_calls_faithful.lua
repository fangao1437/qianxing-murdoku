--[[----------------------------------------------------------------------------
  tests/_wip/perframe_engine_calls.lua —— 【探针】量**每帧真实引擎调用数**（按控件 × 方法）

  ★ 为什么要新写一个 ✗（教训 ✓）：
     ruler 那次我用"自己造的假控件"记账 ⇒ 产线写的是**它自己树里的对象** ✗
     ⇒ 计数恒 0 ⇒ 我白绕了三圈 ✓
   ⇒ ★ 本探针的口径 ✓：**启动之后**，遍历**产线自己那棵树**
     （`game.GetClientUIRoots()` ⇒ `GetChildren` 递归 ✓），
     给**每一颗产线控件**的方法包上计数器 ✓
     ⇒ ★ 产线之后无论拿哪个句柄、走 `controls` 还是 `find`，**都是同一批对象** ⇒ 必然被计到 ✓✓

  ★ 量什么：
     [1] 稳态 N 帧的**总引擎调用数 / 每帧**
     [2] 按**方法**分：`GetSizeDelta` / `GetAnchoredPosition` / `GetChildren` /
         `SetSizeDelta` / `SetAnchoredPosition` / `SetVisible` / `GetChild` …
     [3] 按**控件名**分：谁最贵 ✓（★ 优化要先知道打哪 ✗）
     [4] 写 vs 读 的比例 ✓（★ "读便宜写贵" ✓ ⇒ 我们要省的是写 ✓）

  ★ 口径说明：
     · 统计的是**引擎原语被调用的次数** ✓，不是毫秒（本机没有引擎时钟 ✓）
     · **幂等写**（写进去的值与原来相同）也算一笔 ✗ —— 这正是我们要找的浪费 ✓
     · 只读：本文件**不改任何生产源码** ✓（只在内存里给控件对象包方法 ✓）

  跑法：lua tests/_wip/perframe_engine_calls.lua [产物路径] [帧数]
----------------------------------------------------------------------------]]--

-- ★★★★★ 忠实树探针（2026-10-13）✗✓ —— `perframe_engine_calls.lua` 的忠实树变体
--
-- 为什么必须另开一个文件 ✗：原探针的**手搭假树漏了**真存档里**确实存在**的 8 个边控件
--   （`wall.up/down/left/right`、`door.up/down/left/right`，父控件全部 = `content`，
--    见 `347.gil` 实证：`node tools/gil/list_names.mjs 347.gil wall|door`）✓
--   ⇒ 每次 `sub(cell,"wall.up")` 都**注定未命中** ⇒ 凭空造出每帧 `GetChild` 的差 ✗
-- 本文件做的两件事 ✓：① 给每个格子的 `content` 补上那 8 个边控件；
--                     ② 去掉假树**反向假造**的 10 个控件（`ruler.c.*` / `ruler.r.*`，存档里没有）✓
-- 补忠实之后的实测 ✓：`GetChild`/帧 **两版都是 1.00**；每帧总数 v192 100.5 → v213 42.0（60 帧窗）、
--                     40.3 → 28.4（300 帧窗），差额**全在 `GetChildren`**（整树遍历）✓
--
-- ★★★ 规矩（新增第 ④ 条）✗：**探针的树必须与存档对账** ——
--     "探针包了产线遍历的那棵树" ≠ "那棵树是真的" ✓✓
--
-- 用法 ✓：lua <本文件> <产物路径> [帧数]      # 帧数默认 60；建议 60 与 300 各跑一次
--   依据 ✓：`审计-性能-v192对213.md`（-project 仓）§0 更正声明
--
local here = (arg and arg[0]) or "tests/_wip/perframe_engine_calls_faithful.lua"
local root = here:gsub("tests[/\\]_wip[/\\][^/\\]*%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do
  local function sink(...) end
  _G.print = sink
  _G.printerr = sink
end

-- ── 计数表 ──────────────────────────────────────────────────────────────────
local CNT = { by_method = {}, by_name = {}, total = 0, writes = 0, reads = 0 }
local READ_METHODS = {
  GetSizeDelta = true, GetAnchoredPosition = true, GetChildren = true, GetChild = true,
  GetChildCount = true, GetParent = true, GetSiblingIndex = true, GetUIPos = true,
  GetPressUIPos = true, GetVisible = true, GetText = true, GetItemIndex = true,
}
local WRITE_METHODS = {
  SetSizeDelta = true, SetAnchoredPosition = true, SetVisible = true, SetPivot = true,
  SetImage = true, SetText = true, SetSiblingIndex = true, SetAsFirstSibling = true,
  SetActive = true, SetAlpha = true, SetLocalScale = true, SetAnchorMin = true,
  SetAnchorMax = true, AddCursorEventListener = true, SetItemIndex = true,
}

local function record(name, method)
  CNT.total = CNT.total + 1
  CNT.by_method[method] = (CNT.by_method[method] or 0) + 1
  local k = name .. " . " .. method
  CNT.by_name[k] = (CNT.by_name[k] or 0) + 1
  if WRITE_METHODS[method] then CNT.writes = CNT.writes + 1
  elseif READ_METHODS[method] then CNT.reads = CNT.reads + 1 end
end
local function reset()
  CNT.by_method, CNT.by_name, CNT.total, CNT.writes, CNT.reads = {}, {}, 0, 0, 0
end

-- ── 假引擎的控件工厂 ────────────────────────────────────────────────────────
local attach, make_ctrl
do
  attach = function(parent, c)
    parent.__kids = parent.__kids or {}
    parent.__kids[#parent.__kids + 1] = c
    c.__parent = parent
    return c
  end
  local PROTO = {}          -- 每个新控件从这张表取方法（**包一次就够** ✓）
  make_ctrl = function(name, kind)
    local c = {
      name = name, kind = kind or "container", visible = true, active = true,
      __kids = {}, pivotX = 0.5, pivotY = 0.5, w = 0, h = 0, ax = 0, ay = 0,
      __proto = PROTO,
    }
    return setmetatable(c, {
      -- ★ 方法走**原型表** ⇒ 一个控件一份函数，包起来干净 ✓
      __index = function(t, k)
        if PROTO[k] ~= nil then return PROTO[k] end
        return nil
      end,
    })
  end
  local function def(nm, fn) PROTO[nm] = fn end
  def("GetChildren", function(self) return self.__kids end)
  def("GetChild", function(self, key)
    if type(key) == "number" then return self.__kids[key + 1] end
    for _, k in ipairs(self.__kids) do if k.name == key then return k end end
    return nil
  end)
  def("GetChildCount", function(self) return #self.__kids end)
  def("GetParent", function(self) return self.__parent end)
  def("SetVisible", function(self, v) self.visible = v end)
  def("GetVisible", function(self) return self.visible end)
  def("SetActive", function(self, v) self.active = v end)
  def("SetSizeDelta", function(self, w, h) self.w, self.h = w, h end)
  def("GetSizeDelta", function(self) return self.w or 0, self.h or 0 end)
  def("SetAnchoredPosition", function(self, x, y) self.ax, self.ay = x, y end)
  def("GetAnchoredPosition", function(self) return self.ax or 0, self.ay or 0 end)
  def("SetPivot", function(self, x, y) self.pivotX, self.pivotY = x, y end)
  def("SetAnchorMin", function() end)
  def("SetAnchorMax", function() end)
  def("SetLocalScale", function() end)
  def("SetAlpha", function() end)
  def("AddCursorEventListener", function() end)
  def("SetImage", function() return false end)
  def("SetSiblingIndex", function() return true end)
  def("GetSiblingIndex", function() return 0 end)
  def("SetAsFirstSibling", function() return true end)
  def("GetUIPos", function(self) return self.ax or 0, self.ay or 0 end)
end

-- ── 假树（与真机同构：root → stage → 25 cells / selbar / selbtn.* ）──────────
local tree
do
  local rt = make_ctrl("root")
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right", "actions", "modal", "intro" }) do
    attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage"))
  for r = 1, 5 do
    for cc = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. cc, "button")
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))
      -- ★★★★★ 忠实化补丁（用户指正 + `tools/gil/list_names.mjs 347.gil wall|door` 实证）✗✓
      --   真存档的 `content` 下**有**这 8 个边控件（父全部 = `content`）：
      --     wall.up/down/left/right、door.up/down/left/right ✓
      --   旧假树漏了它们 ⇒ `sub(cell,"wall.up")` 次次注定未命中 ⇒ 凭空造出 840 笔 GetChild ✗
      for _, e in ipairs({ "wall.up", "wall.down", "wall.left", "wall.right",
                           "door.up", "door.down", "door.left", "door.right" }) do
        attach(content, make_ctrl(e, "image"))
      end
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(cell, make_ctrl("note"))
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
  local board = attach(rt, make_ctrl("board"))
  attach(board, make_ctrl("board.bg"))
  -- ★★ 忠实化补丁 ②：真存档（347.gil）里**没有** `ruler.c.*` / `ruler.r.*`
  --    （实测只有 `ruler` ×2 与 `tpl.ruler`）⇒ 旧假树造的这 10 个标签控件也是假的 ✗
  --    保留 `ruler` 本体（存档里确有该名字的控件），去掉它那 10 个子标签 ✓
  attach(board, make_ctrl("ruler"))
  local cl = attach(rt, make_ctrl("clues"))
  attach(cl, make_ctrl("clues.bg"))
  attach(cl, make_ctrl("clues.grid"))
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)", "button")
    c.prefabIndex = prefab
    attach(parent, c)
    return c
  end,
  DestroyClientUIControl = b,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end,
  PrintClientUITree = b,
  ServerSignal = function()
    local s = {}
    s.AddInt = b; s.AddFloat = b; s.AddString = b; s.AddBool = b; s.SendSignal = b
    return s
  end,
  PlayAudio2D = b,
  GetText = function() return "" end,
}
_G.script = { EnableUpdate = b, RegisterServerSignalHandler = b,
  RegisterCustomVariableChangedHandler = b, Invoke = b, GetParam = function() return nil end }
_G.Enum = {
  CursorEventType = { CursorClick = "CursorClick", CursorClickDown = "CursorClickDown",
    CursorClickUp = "CursorClickUp", CursorDrag = "CursorDrag" },
  KeyEventType = { KeyDown = "KeyDown", KeyUp = "KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
local FRAMES = tonumber(arg and arg[2]) or 60
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
if not pcall(chunk) then out("  执行产物抛错"); os.exit(1) end
pcall(OnInit); pcall(OnStart)

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end

-- ★★★★ 关键一步 ✓：**启动之后**，把**产线自己那棵树**上的方法全部包上计数器 ✓
local wrapped, n_ctrl = {}, 0
local function wrap_tree(c, depth)
  if c == nil or depth > 12 then return end
  n_ctrl = n_ctrl + 1
  local nm = "?"
  pcall(function() nm = tostring(c.name) end)
  for method in pairs(READ_METHODS) do
    local f = nil
    pcall(function() f = c[method] end)
    if type(f) == "function" then
      wrapped[#wrapped + 1] = { obj = c, m = method, orig = f }
      c[method] = function(_, ...) record(nm, method) return f(c, ...) end
    end
  end
  for method in pairs(WRITE_METHODS) do
    local f = nil
    pcall(function() f = c[method] end)
    if type(f) == "function" then
      wrapped[#wrapped + 1] = { obj = c, m = method, orig = f }
      c[method] = function(_, ...) record(nm, method) return f(c, ...) end
    end
  end
  local kids = nil
  pcall(function() kids = c:GetChildren() end)
  if type(kids) == "table" then
    for i = 1, #kids do wrap_tree(kids[i], depth + 1) end
  end
end
for i = 1, #tree do wrap_tree(tree[i], 0) end
out(string.format("  已包装产线树：%d 个控件，%d 个方法", n_ctrl, #wrapped))
out("")

-- 先跑 30 帧预热（把 20 帧/30 帧的节流位错开 ✓）
for _ = 1, 30 do pcall(OnUpdate, 1 / 60) end

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 稳态量测
-- ════════════════════════════════════════════════════════════════════════════
out(string.format("== [1] 稳态 %d 帧的引擎调用（含 20/30 帧节流位）==", FRAMES))
reset()
for _ = 1, FRAMES do pcall(OnUpdate, 1 / 60) end
local per = CNT.total / FRAMES
out(string.format("  总计 %d 次 ⇒ **每帧 %.1f 次**（读 %d / 写 %d）",
  CNT.total, per, CNT.reads, CNT.writes))
out(string.format("  其中：读 %.1f 次/帧，写 %.1f 次/帧", CNT.reads / FRAMES, CNT.writes / FRAMES))
out("")

-- [2] 按方法
out("== [2] 按方法（每帧）==")
do
  local keys = {}
  for k, v in pairs(CNT.by_method) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return CNT.by_method[a] > CNT.by_method[b2] end)
  for _, k in ipairs(keys) do
    out(string.format("      %-24s %8.2f 次/帧   （合计 %d）", k, CNT.by_method[k] / FRAMES, CNT.by_method[k]))
  end
end
out("")

-- [3] 按控件
out("== [3] 最贵的控件（前 20，每帧）==")
do
  local keys = {}
  for k, v in pairs(CNT.by_name) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return CNT.by_name[a] > CNT.by_name[b2] end)
  for i = 1, math.min(#keys, 20) do
    local k = keys[i]
    out(string.format("      %-40s %8.2f 次/帧   （合计 %d）", k, CNT.by_name[k] / FRAMES, CNT.by_name[k]))
  end
end
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [4] 幂等写专项：`SetSizeDelta`/`SetAnchoredPosition` 写进去的是不是同一个值
--     ★ 这是"无条件写"的直接证据 ✓（要省的就是这些 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("== [4] 幂等写专项（写进去的值与原来相同 = 纯浪费）==")
do
  local IA = { same = 0, diff = 0, by_name = {} }
  local origSet = {}
  for i = 1, #wrapped do
    local w = wrapped[i]
    if w.m == "SetSizeDelta" or w.m == "SetAnchoredPosition" then
      origSet[#origSet + 1] = w
    end
  end
  -- 换一层计数：先读旧值，再比
  for _, w in ipairs(origSet) do
    local obj, m, f = w.obj, w.m, w.orig
    obj[m] = function(_, a, b2)
      local oa, ob = nil, nil
      if m == "SetSizeDelta" then
        pcall(function() oa, ob = obj.w, obj.h end)
      else
        pcall(function() oa, ob = obj.ax, obj.ay end)
      end
      if oa == a and ob == b2 then
        IA.same = IA.same + 1
        local nm = "?"; pcall(function() nm = tostring(obj.name) end)
        IA.by_name[nm .. " . " .. m] = (IA.by_name[nm .. " . " .. m] or 0) + 1
      else
        IA.diff = IA.diff + 1
      end
      return f(obj, a, b2)
    end
  end
  local before = CNT.total
  for _ = 1, FRAMES do pcall(OnUpdate, 1 / 60) end
  out(string.format("  这 %d 帧里几何写共 %d 笔：**幂等 %d 笔** ✗ / 真变 %d 笔 ✓",
    FRAMES, CNT.total - before, IA.same, IA.diff))
  local keys = {}
  for k in pairs(IA.by_name) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return IA.by_name[a] > IA.by_name[b2] end)
  for i = 1, math.min(#keys, 12) do
    out(string.format("      幂等：%-42s %d 笔", keys[i], IA.by_name[keys[i]]))
  end
end

out("")
out("== 说明 ==")
out("  · 本探针量的是**引擎原语的调用次数**，不是毫秒（本机无引擎时钟 ✓）")
out("  · \"幂等写\"= 写进去的值与写之前相同 ⇒ 那一笔**可以靠读回守卫省掉** ✓")
out("  · 包装只在内存里做，产线源码未改 ✓；进程退出即失效 ✓")
