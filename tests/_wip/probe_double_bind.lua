--[[----------------------------------------------------------------------------
  tests/_wip/probe_double_bind.lua —— ★ 探针：**同一个控件对象会不会被绑上多组监听器**

  ★★★ 要回答的问题（★ 优化组的疑点 ✓ 未验证 ✗）：
    ★ 他们说 ✓：★「`destroy_control` / 换屏那两处作废**没有** `keep_bindings` ✗
      　 ⇒ `self.bound = {}` **整表替换** ⇒ 只销毁一个控件、**其余全部控件的"已绑"记录一起丢** ✓
      　 ⇒ ★ 那些控件**永远不会再走 `bind_input`**（`_created[id]` 已是 true ✓）⇒ **点不动** ✓」
    ★★ 但**他们的结论自相矛盾** ✗（★ 我读出来的 ✓）：
      　 ★ 若"不会再走 `bind_input`" ⇒ ★ **那也不会双绑** ✗
      　 ⇒ ★ 而"单击变放置"**需要**双绑才能解释 ✓✓
      ⇒ ★★ 所以**真正的问题**是 ✓：★ **存在某条路径 ⇒ `bind_input` 在【同一个活控件】上跑了第二遍** ✓

  ★★★ 本探针怎么答 ✓（★ 不读 `bound` 这个布尔 ✗ —— ★ 数**引擎侧真的注册了几次** ✓）：
    ★ 在假引擎上**包住 `AddCursorEventListener`** ✓（★ 那是"引擎侧真的挂了监听器"的唯一凭证 ✓）
    ★ 然后 ★ **进关卡 → 退出 → 再进另一关** ✓
    ★ 判据 ✓：★ **同一个控件对象的注册次数** ✓
      　 · ★ 每个控件 **3 次**（click/down/up ✓）＝ ★ 正常 ✓
      　 · ★ 某控件 **6 次** ＝ ★★ **双绑** ✗✓（★ 这就是"单击变放置"的机制 ✓）

  ★ 口径 ✓：★ 一个探针只量这一件事 ✓（★ 本项目规矩 ✓）
  ★ 只读 ✓：不改生产源码 ✓
  ★ 跑法：lua tests/_wip/probe_double_bind.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/probe_double_bind.lua"
local root = here:gsub("tests[/\\]_wip[/\\]probe_double_bind%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do local function sink(...) end _G.print = sink _G.printerr = sink end

-- ── 记账点：引擎侧每个控件被注册了几次监听器 ───────────────────────────────
local REG = {}          -- name -> 次数
local OBJ = {}          -- 对象 -> name（用于"同一个对象"判定）
local _objid = 0

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
    _objid = _objid + 1
    local c = { name = name, kind = kind or "container", visible = true, active = true,
                __kids = {}, __oid = _objid, interactable = true, raycastTarget = false }
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
  -- ★★★ 记账点 ✓ —— 唯一可信的"引擎侧真的挂了监听器"的证据 ✓
  def("AddCursorEventListener", function(self)
    local nm = tostring(self.name)
    REG[nm] = (REG[nm] or 0) + 1
    OBJ[self] = nm
    self.__regs = (self.__regs or 0) + 1
  end)
  -- ★ 顺便把"摘监听器"也记上 ★ 看有没有人真的调用它 ✓
  def("RemoveCursorEventListener", function(self) self.__removed = (self.__removed or 0) + 1 end)
  def("RemoveAllCursorEventListeners", function(self) self.__removedAll = (self.__removedAll or 0) + 1 end)
  def("SetImage", function() return false end)
  def("SetSiblingIndex", function() return true end)
  def("GetSiblingIndex", function() return 0 end)
  def("SetAsFirstSibling", function() return true end)
  def("GetUIPos", function() return 0, 0 end)
  def("SetText", function() end)
end

local tree, REGN = {}, {}
do
  local rt = make_ctrl("root"); REGN["root"] = rt
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right",
                       "actions", "modal", "intro", "tray" }) do
    REGN[n] = attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage")); REGN["stage"] = st
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
  DestroyClientUIControl = function(ctrl)
    -- ★ 记下"真的销毁了谁" ✓（★ 用于判断"换屏是否真的重建了控件树"✓）
    if ctrl ~= nil then ctrl.__destroyed = true end
  end,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end, PrintClientUITree = b,
  ServerSignal = function() local s={} s.AddInt=b s.AddFloat=b s.AddString=b s.AddBool=b s.SendSignal=b return s end,
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
local ok, err = pcall(chunk)
if not ok then out("  执行抛错：" .. tostring(err)); os.exit(1) end
pcall(OnInit); pcall(OnStart); pcall(OnUpdate, 0.016)

local dbg = _G.__murdoku_debug
local Mu = dbg and dbg.Murdoku
if Mu == nil then out("  开局失败"); os.exit(2) end

local function snap(tag)
  local cur = Mu.current()
  local ad = cur and cur.adapter
  local bound_n = 0
  if ad and ad.bound then for _ in pairs(ad.bound) do bound_n = bound_n + 1 end end
  out(string.format("  [%s] bound条目=%d  _lookup_gen=%s  已注册控件数=%d",
    tag, bound_n, tostring(ad and ad._lookup_gen), (function() local n=0 for _ in pairs(REG) do n=n+1 end return n end)()))
end

out("")
out("=== [1] 第一次进关（关卡1）===")
pcall(function() Mu.start("selftest_theft_5x5") end)
for i = 1, 20 do pcall(OnUpdate, 0.016) end
snap("进关1后")

local reg_after_1 = {}
for k, v in pairs(REG) do reg_after_1[k] = v end

out("")
out("=== [2] 退出到选关，再进关卡2（★ 这正是「二次进关」✓）===")
pcall(function() Mu.start("case_001") end)
for i = 1, 20 do pcall(OnUpdate, 0.016) end
snap("进关2后")

out("")
out("=== [3] 判据：每个控件的注册次数 ===")
out("  （★ 正常 = 每个控件 3 次：click/down/up ✓；★ 6 次 = 双绑 ✗）")
local over, total = {}, 0
for k, v in pairs(REG) do
  total = total + 1
  if v > 3 then over[#over + 1] = { k, v } end
end
table.sort(over, function(a, b) return a[2] > b[2] end)
out(string.format("  被注册过的控件名共 %d 个", total))
if #over == 0 then
  out("  ★★ 没有任何控件超过 3 次 ⇒ **本路径下没有双绑** ✓")
else
  out(string.format("  ★★★ 有 %d 个控件被注册了 > 3 次 ⇒ **双绑** ✗✓", #over))
  for i = 1, math.min(20, #over) do
    out(string.format("      %-22s %d 次", over[i][1], over[i][2]))
  end
end

out("")
out("=== [4] 每个控件对象的注册次数（★ 同一对象才算双绑 ✓）===")
local obj_over = {}
for obj, nm in pairs(OBJ) do
  if (obj.__regs or 0) > 3 then obj_over[#obj_over + 1] = { nm, obj.__regs, obj.__oid } end
end
if #obj_over == 0 then
  out("  ★★ 没有任何【单个控件对象】被注册 > 3 次 ⇒ **没有双绑** ✓")
else
  out(string.format("  ★★★ %d 个控件对象被注册 > 3 次：", #obj_over))
  for i = 1, math.min(20, #obj_over) do
    out(string.format("      %-22s 对象#%d  %d 次", obj_over[i][1], obj_over[i][3], obj_over[i][2]))
  end
end

out("")
out("=== [5] 顺带：有没有人调用过「摘监听器」 ===")
local removed = 0
for obj in pairs(OBJ) do
  removed = removed + (obj.__removed or 0) + (obj.__removedAll or 0)
end
out("  摘监听器调用总次数 = " .. tostring(removed) .. "（★ 0 = 没人摘过 ✓）")
