--[[----------------------------------------------------------------------------
  tests/anchored_pos_guard.lua —— ★ 判据：`rect` 分支的 `SetAnchoredPosition` 读回守卫

  ★★★ 上游待办（★ 优化组 v204 §1.2 / v205 §一 P1 ✓）：
    ★ 上一轮**故意没给这一笔加守卫** ✗，理由逐字是 ✓：
      ★「`SetAnchoredPosition` 写的是**相对父级中心**的值 ✗ ——
        ★ 它读回到底给"锚点值"还是"绝对坐标"，**本环境没有实测证据** ✗
        ⇒ ★ 按本项目规矩：**没有实测证据的读回守卫，宁可不加** ✓
        ★ 加错的方向是"**该对齐却不写**"✗ ⇒ 控件停在错位置 ✓」
    ⇒ ★★★ **2026-10-12 官方原文把歧义消掉了** ✓✓
      ★ 来源：《客户端控件API文档》（`mhtakr07vej4` ✓）§13(3)「布局与变换」✓
      ★ 原文 ✓：两条都写「**无父层级时，以画布左下为原点**；
        **存在父层级时，……与父层级中心的相对偏移**」✓
      ⇒ ★ **读与写同一坐标系** ✓ ★ 且**没有**"父级 pivot 参与"的条件 ✓

  ★★ 本文件钉四件事（★ 每条都能红 ✓）：
    ① ★ **值真的不同 ⇒ 必须写** ✓（★ "不许不摆"那条底线 ✓）
    ② ★ **同一目标连下两次 ⇒ 第二次不写** ✓（★ 这就是本轮省下的 37 笔 ✓）
    ③ ★ **读不到 ⇒ 照旧写** ✓（★ 与 `pivot` / `size` 两笔同一条安全边界 ✓）
    ④ ★ **反向对照**：凭空把位置弄错 ⇒ 下一趟**必须重新写** ✓
        （★ 证明 ② 的"0 笔"是"省了"✗ 不是"哑了" ✓）

  ★★ 两个夹具坑（★ 都踩过 ✓ 写在这里省下一个人 ✓）：
    ★ ① **键名是 `rect` 不是 `position`** ✗ —— `set_property` 里**没有** `key == "position"`
      那一支 ✓（★ "position 分支"是**注释里的叫法** ✓ 见函数头 ✓）
      ★ ② **`rect` 分支默认【跳过】非运行时控件** ✗（`respect_editor_rect` ✓）
        ⇒ ★ 必须 `adapter.runtime_rect[id] = true` ✓ 否则**静默 `return true`** ✓
          —— ★ 那样量出来恒 0 笔，而看起来"守卫坏了" ✗（★ 又是一次"夹具不对"✓）

  ★ 只读：本文件**不改任何生产源码** ✓
  ★ 跑法：lua tests/anchored_pos_guard.lua
  ★ 前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/anchored_pos_guard.lua"
local root = here:gsub("tests[/\\]anchored_pos_guard%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do local function sink(...) end _G.print = sink _G.printerr = sink end

local pass, fail = 0, 0
local function ok(cond, label, detail)
  if cond then
    pass = pass + 1
    out("  [PASS] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  else
    fail = fail + 1
    out("  [FAIL] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  end
end

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
                __kids = {}, pivotX = nil, pivotY = nil, w = nil, h = nil }
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
  def("GetUIPos", function() return 0, 0 end)
  def("SetText", function() end)
end

local tree, REG = {}, {}
do
  local rt = make_ctrl("root"); REG["root"] = rt
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right",
                       "actions", "modal", "intro" }) do
    attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage")); REG["stage"] = st
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
  local board = attach(rt, make_ctrl("board")); REG["board"] = board
  attach(board, make_ctrl("board.bg"))
  local cl = attach(rt, make_ctrl("clues")); REG["clues"] = cl
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
do
  local fh = io.open(SCRIPT_PATH, "rb")
  if fh == nil then out("  打不开产物 ⇒ 先跑 bundle"); os.exit(1) end
  local body = fh:read("a"); fh:close()
  if body:find("want_x, want_y = R(cx - pcx), R(cy - pcy)", 1, true) == nil then
    out("  ✗ 产物里没有那个守卫 ⇒ 旧产物 ⇒ 量不到（不伪造数字）")
    os.exit(1)
  end
  out("  产物已含 `SetAnchoredPosition` 的读回守卫 ✓")
end

local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart); pcall(OnUpdate, 0.016)

local cur = _G.__murdoku_debug and _G.__murdoku_debug.Murdoku
  and _G.__murdoku_debug.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local adapter = cur.adapter
out("")

-- ★ 记账点：包在**适配器自己解析出来的那个句柄**上 ✓
--   （★ 第一版只包了"我自己 REG 里那一份" ⇒ ★ `set_property` 走 `self:find(id)` ⇒
--     ★ 拿到的可能是**没包过的那个对象** ⇒ 计数恒 0 ⇒ **假红** ✓ 已修 ✓）
local WRITES, READS = 0, 0
local function instrument(ctrl)
  if ctrl == nil or ctrl.__probe_installed then return ctrl end
  local real_set = ctrl.SetAnchoredPosition
  local real_get = ctrl.GetAnchoredPosition
  if real_set == nil or real_get == nil then return ctrl end
  ctrl.SetAnchoredPosition = function(self, x, y) WRITES = WRITES + 1 real_set(self, x, y) end
  ctrl.GetAnchoredPosition = function(self) READS = READS + 1 return real_get(self) end
  ctrl.__probe_installed = true
  return ctrl
end

-- ★ 用适配器自己的 `find` 取句柄 ⇒ 保证"它用的"与"我包的"是同一个对象 ✓
local function H(id)
  local c = adapter:find(id)
  if c ~= nil then instrument(c) end
  return c
end

local board = H("board")
local clues = H("clues")
if board == nil or clues == nil then out("  取不到夹具句柄 ⇒ 量不到"); os.exit(2) end

-- ★★ 必须把目标标成"运行时控件" ✗ —— 否则 `rect` 分支**静默 `return true`** ✓（见文件头坑②）
adapter.runtime_rect = adapter.runtime_rect or {}
adapter.runtime_rect["board"] = true
adapter.runtime_rect["clues"] = true

local RECT_A = { x = 400, y = 300, w = 700, h = 700 }
local RECT_B = { x = 402, y = 302, w = 700, h = 700 }

-- ════════════════════════════════════════════════════════════════════════════
-- [1] ★ 底线：值真的不同 ⇒ 必须写
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] ★ 底线：位置真的不同 ⇒ **必须写**（不许因为读回就不摆 ✗）==")
do
  board.ax, board.ay = 1, 1
  WRITES, READS = 0, 0
  local ret = adapter:set_property("board", "rect", RECT_A)
  ok(WRITES == 1, "★★ 读回与目标不同 ⇒ **写了** ✓（底线守住 ✓）",
    "SetAnchoredPosition 被调 " .. tostring(WRITES) .. " 次（应为 1）；set_property 返回 "
      .. tostring(ret))
  ok(board.ax ~= nil and board.ax ~= 1,
    "★ 并且控件真的被摆到了新位置 ✓",
    "ax: 1 → " .. tostring(board.ax))
end

-- ════════════════════════════════════════════════════════════════════════════
-- [2] ★ 收益：同一目标连下两次 ⇒ 第二次不写
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] ★ 收益：同一个 `rect` 再下一次 ⇒ **不写**（省下的就是这 37 笔 ✓）==")
do
  WRITES, READS = 0, 0
  adapter:set_property("board", "rect", RECT_A)
  ok(WRITES == 0,
    "★★ 同值 ⇒ **一笔都不写** ✓（★ 37 → 0 ✓ 读回守卫真的生效 ✓）",
    "写了 " .. tostring(WRITES) .. " 笔，读了 " .. tostring(READS) .. " 次"
      .. "（★ 读是必须的 ✓ —— 读回守卫的代价就是一读 ✓）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] ★ 反向对照：位置被弄错 ⇒ 下一趟必须重新写
--   （★ 证明 [2] 的"0 笔"是"省了"✗ 不是"哑了" ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] ★ 反向对照：凭空把位置弄错 ⇒ **必须重新写**（证明不是哑了 ✓）==")
do
  board.ax, board.ay = 9999, 9999
  WRITES, READS = 0, 0
  adapter:set_property("board", "rect", RECT_A)
  ok(WRITES == 1,
    "★★ 现值被弄错 ⇒ 照旧**重新写** ✓（★ 守卫是「该省才省」✗ 不是「永远不写」✓）",
    "写了 " .. tostring(WRITES) .. " 笔（应为 1）")
  -- ★ 顺带：目标真的变了 ⇒ 也必须写 ✓（★ 不能把"同值早退"写成"只写第一次" ✓）
  WRITES, READS = 0, 0
  adapter:set_property("board", "rect", RECT_B)
  ok(WRITES == 1,
    "★★ 目标**真的变了** ⇒ 也必须写 ✓（★ 不是「只写第一次」✗）",
    "写了 " .. tostring(WRITES) .. " 笔（应为 1）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [4] ★ 读不到 ⇒ 照旧写（★ 与 pivot / size 两笔同一条安全边界 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [4] ★ 读不到 ⇒ **照旧写**（★ 不许因为读不到就不摆 ✗）==")
do
  local saved = clues.GetAnchoredPosition
  clues.GetAnchoredPosition = function() error("no such method", 0) end
  WRITES, READS = 0, 0
  adapter:set_property("clues", "rect", { x = 123, y = 456, w = 480, h = 650 })
  ok(WRITES == 1,
    "★★ 读回抛错（读不到）⇒ **照旧写** ✓（★ 安全侧 ✓）",
    "写了 " .. tostring(WRITES) .. " 笔（应为 1）")
  clues.GetAnchoredPosition = saved
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
