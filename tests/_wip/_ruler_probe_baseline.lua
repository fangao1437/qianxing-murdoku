-- tests/_wip/_ruler_probe_baseline.lua —— 临时：确认 v192 基线里 apply_ruler_layout 到底写不写
local here = "tests/_wip/ruler_write_count.lua"
local root = "./"

local out = print
local logs = {}
do
  local function sink(...) end
  _G.print = function(...) end
  _G.printerr = function(...) end
end

local W = { pivot = 0, pos = 0, calls = {} }
local function attach(parent, c)
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end
local function make_ctrl(name, kind)
  local c = { name = name, kind = kind or "container", visible = true, active = true,
              __kids = {}, pivotX = 0.5, pivotY = 0.5, w = 0, h = 0, ax = 0, ay = 0 }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function() end
  c.SetActive = function() end
  c.SetSizeDelta = function(_, w, h) c.w, c.h = w, h end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
  c.SetAnchoredPosition = function(_, x, y)
    c.ax, c.ay = x, y
    W.pos = W.pos + 1
    local tb = debug.traceback("", 2)
    local first = (tb:gsub("^[^\n]*\n", "")):match("^[^\n]*") or "?"
    W.calls[#W.calls + 1] = name .. " -> (" .. tostring(x) .. "," .. tostring(y) .. ")  @ " .. first:gsub("^%s+", "")
  end
  c.GetAnchoredPosition = function() return c.ax or 0, c.ay or 0 end
  c.SetPivot = function(_, x, y) c.pivotX, c.pivotY = x, y; W.pivot = W.pivot + 1 end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetLocalScale = function() end
  c.SetAlpha = function() end
  c.AddCursorEventListener = function() end
  c.SetImage = function() return false end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  return c
end
local function make_text(name) return make_ctrl(name, "text") end

local RULER, tree = {}, nil
do
  local rt = make_ctrl("root")
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right", "actions", "modal", "intro" }) do
    attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage"))
  for r = 1, 5 do
    for cc = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. cc, "button")
      cell.ax, cell.ay = (cc - 3) * 120, (3 - r) * 120
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  local board = attach(rt, make_ctrl("board"))
  local ruler = attach(board, make_ctrl("ruler"))
  ruler.ax, ruler.ay = 10, 20
  for j = 1, 5 do
    local t = attach(ruler, make_text("ruler.c." .. j))
    t.ax, t.ay = 500 + j, 700 + j        -- 明显错位 ⇒ 基线应当写
    t.pivotX, t.pivotY = 0.3, 0.7
    RULER["ruler.c." .. j] = t
  end
  for i = 1, 5 do
    local t = attach(ruler, make_text("ruler.r." .. i))
    t.ax, t.ay = 900 + i, 300 + i
    t.pivotX, t.pivotY = 0.25, 0.75
    RULER["ruler.r." .. i] = t
  end
  attach(rt, make_ctrl("clues"))
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(p, par) local c = make_ctrl("(未命名)", "button"); attach(par, c); return c end,
  DestroyClientUIControl = b, GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end, PrintClientUITree = b,
  ServerSignal = function() local s = {} s.AddInt=b s.AddFloat=b s.AddString=b s.AddBool=b s.SendSignal=b return s end,
  PlayAudio2D = b, GetText = function() return "" end,
}
_G.script = { EnableUpdate=b, RegisterServerSignalHandler=b,
  RegisterCustomVariableChangedHandler=b, Invoke=b, GetParam = function() return nil end }
_G.Enum = { CursorEventType = { CursorClick="CursorClick" }, KeyEventType = { KeyDown="KeyDown" } }

local SCRIPT_PATH = arg[1] or "dist/client_script.lua"
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("load fail: " .. tostring(lerr)); os.exit(1) end
assert(pcall(chunk))
pcall(OnInit); pcall(OnStart)
local dbg = _G.__murdoku_debug
local cur = dbg.Murdoku.current()
local adapter = cur.adapter

for i = 1, 5 do
  adapter.controls["ruler.c." .. i] = RULER["ruler.c." .. i]
  adapter.controls["ruler.r." .. i] = RULER["ruler.r." .. i]
end
do
  local st = nil
  for _, k in ipairs(tree[1].__kids) do if k.name == "stage" then st = k end end
  for _, k in ipairs(st.__kids or {}) do
    if k.name:sub(1, 5) == "cell." then adapter.controls[k.name] = k end
  end
  local ruler = RULER["ruler.c.1"].__parent
  adapter.controls["ruler"] = ruler
  adapter.controls["board"] = ruler.__parent
end

out("PROBE: " .. SCRIPT_PATH)
-- ★★ 关键更正（我第一次就是错在这里 ✗）：
--   `adapter.controls["ruler.c.1"]` 里塞进去的对象**不是产线实际写的那个** ✗
--   —— `apply_ruler_layout` 用 `self:find(name)` ✓，而 `find` 命中 `controls` 才用缓存；
--     命中不了就**走树** ⇒ 拿到**树里那份**（产线在 OnInit/OnStart 里自己建的 ✓）
--   ⇒ 所以要在**产线实际持有的对象**上包计数器 ✓ 而不是在我自己造的对象上 ✓
local ruler_prod = adapter:find("ruler")
local prod_labels = {}
if ruler_prod ~= nil and ruler_prod.GetChildren ~= nil then
  local kids = ruler_prod:GetChildren()
  for _, k in ipairs(kids or {}) do prod_labels[k.name] = k end
end
out(string.format("  find(ruler)=%s  它的子控件：%d 个", tostring(ruler_prod ~= nil),
  (function() local n = 0 for _ in pairs(prod_labels) do n = n + 1 end return n end)()))
do
  local names = {}
  for k in pairs(prod_labels) do names[#names + 1] = k end
  table.sort(names)
  out("       " .. table.concat(names, "  "))
end
-- 在**产线对象**上包计数器 ✓（保存原方法，量完不需要还原 —— 本进程用完即弃 ✓）
W.pos, W.pivot, W.calls = 0, 0, {}
for nm, obj in pairs(prod_labels) do
  if type(obj.GetAnchoredPosition) == "function" then
    local oldpos = obj.SetAnchoredPosition
    obj.SetAnchoredPosition = function(self, x, y)
      W.pos = W.pos + 1
      W.calls[#W.calls + 1] = nm .. " -> (" .. tostring(x) .. "," .. tostring(y) .. ")"
      if oldpos then return oldpos(self, x, y) end
    end
  end
  if type(obj.SetPivot) == "function" then
    local oldpiv = obj.SetPivot
    obj.SetPivot = function(self, x, y)
      W.pivot = W.pivot + 1
      if oldpiv then return oldpiv(self, x, y) end
    end
  end
end

W.pos, W.pivot, W.calls = 0, 0, {}
local moved = adapter:apply_ruler_layout(5, 5)
out(string.format("  PASS1: moved=%s  pos=%d pivot=%d", tostring(moved), W.pos, W.pivot))
for i = 1, math.min(#W.calls, 6) do out("      " .. W.calls[i]) end

W.pos, W.pivot, W.calls = 0, 0, {}
local moved2 = adapter:apply_ruler_layout(5, 5)
out(string.format("  PASS2: moved=%s  pos=%d pivot=%d", tostring(moved2), W.pos, W.pivot))
for i = 1, math.min(#W.calls, 6) do out("      " .. W.calls[i]) end
