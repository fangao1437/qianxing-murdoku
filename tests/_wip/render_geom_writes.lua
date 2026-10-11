--[[----------------------------------------------------------------------------
  tests/_wip/render_geom_writes.lua —— 【探针】一次 render 的几何写：几笔？幂等几笔？

  ★ 为什么单独开一个文件 ✗（教训 ✓）：
     我把它塞进 `render_cost.lua` 的 [4e] ⇒ 那个文件前面已经有 4 层包装 ✗
     ⇒ 后加的那层**永远排在别人后面** ⇒ 计数恒 0 ⇒ ★ 我拿到了**自相矛盾的两个数**
       （[1] 说 37 笔 ✗ / [4e] 说 0 笔 ✗）✓
     ⇒ ★★ 教训 ✓：**一个探针只量一件事** ✗ —— ★ 多层包装会互相挡 ✓✓

  ★ 量什么（**一次干净启动** ✓ 只包一层 ✓）：
     [1] 冷启动那 1 趟：几何写几笔（账本空 ⇒ 该写 ✓）
     [2] 预热 3 趟之后，再量 1 趟：几何写几笔（★ 稳态 ✓ 这是**优化要打的数** ✓）
     [3] 那几笔里**幂等**（写进去的值 == 原本的值）几笔 ✗ / 真变几笔 ✓
     [4] 逐控件列出（谁在被反复写同一组值 ✓）

  跑法：lua tests/_wip/render_geom_writes.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/render_geom_writes.lua"
local root = here:gsub("tests[/\\]_wip[/\\]render_geom_writes%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do local function sink(...) end _G.print = sink _G.printerr = sink end

local attach, make_ctrl
do
  attach = function(parent, c)
    parent.__kids = parent.__kids or {}
    parent.__kids[#parent.__kids + 1] = c
    c.__parent = parent
    return c
  end
  local PROTO = {}
  make_ctrl = function(name, kind)
    local c = { name = name, kind = kind or "container", visible = true, active = true,
                __kids = {}, pivotX = nil, pivotY = nil, w = nil, h = nil, ax = nil, ay = nil }
    return setmetatable(c, { __index = function(_, k) return PROTO[k] end })
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
  def("SetText", function() end)
end

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
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(cell, make_ctrl("note"))
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  local board = attach(rt, make_ctrl("board"))
  attach(board, make_ctrl("board.bg"))
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
    local c = make_ctrl("(未命名)", "button"); c.prefabIndex = prefab
    attach(parent, c); return c
  end,
  DestroyClientUIControl = b, GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end, PrintClientUITree = b,
  ServerSignal = function() local s = {} s.AddInt=b s.AddFloat=b s.AddString=b s.AddBool=b s.SendSignal=b return s end,
  PlayAudio2D = b, GetText = function() return "" end,
}
_G.script = { EnableUpdate=b, RegisterServerSignalHandler=b,
  RegisterCustomVariableChangedHandler=b, Invoke=b, GetParam = function() return nil end }
_G.Enum = {
  CursorEventType = { CursorClick="CursorClick", CursorClickDown="CursorClickDown",
    CursorClickUp="CursorClickUp", CursorDrag="CursorDrag" },
  KeyEventType = { KeyDown="KeyDown", KeyUp="KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
if not pcall(chunk) then out("  执行产物抛错"); os.exit(1) end
pcall(OnInit); pcall(OnStart)
local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功"); os.exit(2) end
local ctrl = cur.controller

-- ── ★ 只包这一层（几何三兄弟）✓ 先读原值 ⇒ 判幂等 ✓ ────────────────────────
local CNT = { n = 0, same = 0, diff = 0, unknown = 0, by = {}, idem = {} }
local function reset() CNT.n, CNT.same, CNT.diff, CNT.unknown, CNT.by, CNT.idem = 0, 0, 0, 0, {}, {} end

local function wrap(c, d)
  if c == nil or d > 12 then return end
  local nm = "?"; pcall(function() nm = tostring(c.name) end)

  local fSize = nil; pcall(function() fSize = c.SetSizeDelta end)
  if type(fSize) == "function" then
    c.SetSizeDelta = function(_, w, h)
      CNT.n = CNT.n + 1
      local ow, oh = c.w, c.h
      local key = nm .. " SetSizeDelta"
      if ow ~= nil and ow == w and oh == h then
        CNT.same = CNT.same + 1
        CNT.idem[key] = (CNT.idem[key] or 0) + 1
      elseif ow == nil then CNT.unknown = CNT.unknown + 1
      else CNT.diff = CNT.diff + 1 end
      CNT.by[key] = (CNT.by[key] or 0) + 1
      return fSize(c, w, h)
    end
  end

  local fPos = nil; pcall(function() fPos = c.SetAnchoredPosition end)
  if type(fPos) == "function" then
    c.SetAnchoredPosition = function(_, x, y)
      CNT.n = CNT.n + 1
      local ox, oy = c.ax, c.ay
      local key = nm .. " SetAnchoredPosition"
      if ox ~= nil and ox == x and oy == y then
        CNT.same = CNT.same + 1
        CNT.idem[key] = (CNT.idem[key] or 0) + 1
      elseif ox == nil then CNT.unknown = CNT.unknown + 1
      else CNT.diff = CNT.diff + 1 end
      CNT.by[key] = (CNT.by[key] or 0) + 1
      return fPos(c, x, y)
    end
  end

  local fPiv = nil; pcall(function() fPiv = c.SetPivot end)
  if type(fPiv) == "function" then
    c.SetPivot = function(_, x, y)
      CNT.n = CNT.n + 1
      local ox, oy = c.pivotX, c.pivotY
      local key = nm .. " SetPivot"
      if ox ~= nil and ox == x and oy == y then
        CNT.same = CNT.same + 1
        CNT.idem[key] = (CNT.idem[key] or 0) + 1
      elseif ox == nil then CNT.unknown = CNT.unknown + 1
      else CNT.diff = CNT.diff + 1 end
      CNT.by[key] = (CNT.by[key] or 0) + 1
      return fPiv(c, x, y)
    end
  end

  local kids = nil; pcall(function() kids = c:GetChildren() end)
  if type(kids) == "table" then for j = 1, #kids do wrap(kids[j], d + 1) end end
end
for i = 1, #tree do wrap(tree[i], 0) end
out("  已包一层几何计数（读原值判幂等 ✓）")
out("")

local function report(tag)
  out(string.format("  【%s】几何写 **%d 笔**：幂等 **%d** ✗ / 真变 **%d** ✓ / 首写(原值读不到) **%d**",
    tag, CNT.n, CNT.same, CNT.diff, CNT.unknown))
end

-- [1] 冷：账本空 ⇒ 该写 ✓
reset()
pcall(function() ctrl:render(cur.adapter, true) end)
out("== [1] 冷启动第 1 趟（`_props` 账本空 ⇒ 全部该写 ✓）==")
report("冷")
out("")

-- [2] 热：预热 3 趟 ⇒ 稳态 ✓
for _ = 1, 3 do pcall(function() ctrl:render(cur.adapter, true) end) end
reset()
pcall(function() ctrl:render(cur.adapter, true) end)
out("== [2] 稳态（预热 3 趟之后，再量 1 趟）★ 这是优化要打的数 ==")
report("热")
out(string.format("  ⇒ ★ 稳态每趟 render 的几何写 = **%d 笔**（幂等 %d / 真变 %d / 首写 %d）",
  CNT.n, CNT.same, CNT.diff, CNT.unknown))
out("")

-- [3] 逐控件
out("== [3] 明细（写 >= 2 笔的控件）==")
do
  local keys = {}
  for k in pairs(CNT.by) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return CNT.by[a] > CNT.by[b2] end)
  for i = 1, math.min(#keys, 18) do
    local k = keys[i]
    out(string.format("      %-42s %3d 笔（幂等 %d）", k, CNT.by[k], CNT.idem[k] or 0))
  end
end
out("")
out("== 说明 ==")
out("  · 只包**一层** ✓ —— 上一版层层叠加 ⇒ 后包的被先包的挡住 ⇒ 数出 0 ✗（已改 ✓）")
out("  · 幂等 = 写进去的值与写之前**相同** ✓ ⇒ ★ 那一笔**可以靠读回守卫省掉** ✓")
