--[[----------------------------------------------------------------------------
  tests/_wip/render_cost.lua —— 【探针】量**一次 render 的引擎调用数**（输入尖峰的成本）

  ★ 背景（为什么要量 render ✗）：
     `Murdoku.render` 的触发门是 `main.lua` 的
        `if sec ~= current.last_tick or current.controller.dirty then`
     ⇒ ★ 稳态 **≈1 次/秒** ✓ **但每次输入（点/拖/按键）都会置 `dirty`** ✗
       ⇒ ★★ **拖动时按事件率触发** ✓ ⇒ 那是**尖峰**，不是稳态 ✓✓
     ★ 项目自测记过：`core:view()`（整视图重建）**0.235 ms/次** ✓
       ⇒ 若一次 render 里有多次 `view()` / 大量表分配 ⇒ 那就是尖峰的主因 ✓

  ★ 量什么：
     [1] 一次 render 里的**引擎调用数**（按方法 × 按控件）
     [2] render 期间 `core:view()` 被调几次（★ 计划重建的次数 ✓）
     [3] `build_layout` 被调几次 ＋ 产出多少个节点
     [4] 一次 render 的**纯 Lua 耗时**（`os.clock()` ✓ 本机可用 ✓）

  ★ 口径 ✓（吸取 ruler 那次的教训 ✓）：
     **启动之后**包装**产线自己那棵树** ✓ ⇒ 产线之后拿到的都是同一批对象 ✓ 必然被计到 ✓

  跑法：lua tests/_wip/render_cost.lua [产物路径]
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/render_cost.lua"
local root = here:gsub("tests[/\\]_wip[/\\]render_cost%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do
  local function sink(...) end
  _G.print = sink
  _G.printerr = sink
end

local CNT = { by_method = {}, by_name = {}, total = 0 }
local METHODS = {
  "GetChildren", "GetChild", "GetChildCount", "GetParent", "GetSizeDelta",
  "GetAnchoredPosition", "SetSizeDelta", "SetAnchoredPosition", "SetVisible",
  "SetPivot", "SetImage", "SetText", "AddCursorEventListener", "GetSiblingIndex",
  "SetSiblingIndex", "SetAsFirstSibling", "GetUIPos", "GetItemIndex",
}
local function record(name, method)
  CNT.total = CNT.total + 1
  CNT.by_method[method] = (CNT.by_method[method] or 0) + 1
  local k = name .. " . " .. method
  CNT.by_name[k] = (CNT.by_name[k] or 0) + 1
end
local function reset() CNT.by_method, CNT.by_name, CNT.total = {}, {}, 0 end

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
                __kids = {}, pivotX = 0.5, pivotY = 0.5, w = 0, h = 0, ax = 0, ay = 0 }
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
  def("SetItemIndex", function() end)
  def("GetItemIndex", function() return 0 end)
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
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
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

-- 包装产线树
local n_ctrl = 0
local function wrap_tree(c, depth)
  if c == nil or depth > 12 then return end
  n_ctrl = n_ctrl + 1
  local nm = "?"; pcall(function() nm = tostring(c.name) end)
  for i = 1, #METHODS do
    local m = METHODS[i]
    local f = nil; pcall(function() f = c[m] end)
    if type(f) == "function" then
      c[m] = function(_, ...) record(nm, m) return f(c, ...) end
    end
  end
  local kids = nil; pcall(function() kids = c:GetChildren() end)
  if type(kids) == "table" then for i = 1, #kids do wrap_tree(kids[i], depth + 1) end end
end
for i = 1, #tree do wrap_tree(tree[i], 0) end
out(string.format("  已包装产线树：%d 个控件", n_ctrl))
out("")

-- 先跑几帧预热
for _ = 1, 10 do pcall(OnUpdate, 1 / 60) end

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 计一次 render 的引擎调用
--   ★★ 关键 ✓：**必须预热** ✗ —— 冷账本（`_props` 空）第一次 render 会把**所有**属性
--      当"变了"全部下发一遍 ✓ 那是**必然且正确**的 ✓ 不是浪费 ✓
--      我第一版没预热 ⇒ 量到的是"冷启动那一趟" ⇒ **数字全错** ✗（已更正 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 一次 `Murdoku.render()` 的引擎调用（★ 稳态：预热后 ✓）==")
local N = 5
-- 先预热 3 趟：让账本进入稳态 ✓（这 3 趟不计入 ✓）
for _ = 1, 3 do pcall(function() cur.controller:render(cur.adapter, true) end) end
local totals = {}
reset()
for i = 1, N do
  local t0 = os.clock()
  pcall(function() cur.controller:render(cur.adapter, true) end)
  local dt = os.clock() - t0
  totals[#totals + 1] = { calls = CNT.total, ms = dt * 1000 }
  reset()
end
local sumCalls, sumMs = 0, 0
for i = 1, N do sumCalls = sumCalls + totals[i].calls; sumMs = sumMs + totals[i].ms end
out(string.format("  %d 次 render：平均 **%.1f 次引擎调用**，纯 Lua 耗时 **%.3f ms**",
  N, sumCalls / N, sumMs / N))
out("")

-- [2] 明细
out("== [2] 一次 render 的明细（按方法 / 按控件前 15）==")
reset()
pcall(function() cur.controller:render(cur.adapter, true) end)
do
  local keys = {}
  for k, v in pairs(CNT.by_method) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return CNT.by_method[a] > CNT.by_method[b2] end)
  for _, k in ipairs(keys) do
    out(string.format("      %-24s %6d 次", k, CNT.by_method[k]))
  end
end
out("  --- 按控件 ---")
do
  local keys = {}
  for k, v in pairs(CNT.by_name) do keys[#keys + 1] = v end
  local kk = {}
  for k, v in pairs(CNT.by_name) do kk[#kk + 1] = k end
  table.sort(kk, function(a, b2) return CNT.by_name[a] > CNT.by_name[b2] end)
  for i = 1, math.min(#kk, 15) do
    out(string.format("      %-42s %6d 次", kk[i], CNT.by_name[kk[i]]))
  end
end
out("")

-- [3] view() / build_layout 次数
out("== [3] 关键子步骤的调用次数（一次 render）==")
do
  local core = ctrl.core
  local viewN, layoutN = 0, 0
  local ov = core.view
  core.view = function(self2, ...) viewN = viewN + 1 return ov(self2, ...) end
  local ob = ctrl.build_layout
  ctrl.build_layout = function(self2, ...)
    layoutN = layoutN + 1
    local r = ob(self2, ...)
    if type(r) == "table" then ctrl._last_nodes = #r end
    return r
  end
  reset()
  pcall(function() ctrl:render(cur.adapter, true) end)
  out(string.format("  `core:view()` 被调 **%d** 次；`build_layout()` 被调 **%d** 次（产出 %s 个节点）",
    viewN, layoutN, tostring(ctrl._last_nodes)))
  out(string.format("  本次共 %d 次引擎调用", CNT.total))
end

-- [4] ★ 定位 `GetChild` 的真凶：记录**调用栈**（按栈首行聚合 ✓）
out("")
out("== [4] `GetChild` 的真凶（按调用点聚合）==")
do
  local TRACE = {}
  local hits = 0
  local function trace_key()
    local tb = debug.traceback("", 3)
    for line in tb:gmatch("[^\n]+") do
      local n = line:match("client_script%.lua:(%d+)")
      if n ~= nil then return "client_script.lua:" .. n end
    end
    return "?"
  end
  for i = 1, #tree do
    local function rec(c, depth)
      if c == nil or depth > 12 then return end
      local cur_f = nil; pcall(function() cur_f = c.GetChild end)
      if type(cur_f) == "function" then
        c.GetChild = function(_, key)
          TRACE[trace_key()] = (TRACE[trace_key()] or 0) + 1
          hits = hits + 1
          return cur_f(c, key)
        end
      end
      local kids = nil; pcall(function() kids = c:GetChildren() end)
      if type(kids) == "table" then for j = 1, #kids do rec(kids[j], depth + 1) end end
    end
    rec(tree[i], 0)
  end
  reset()
  pcall(function() ctrl:render(cur.adapter, true) end)
  out(string.format("  一次 render 里 `GetChild` 共 %d 次；按调用点：", hits))
  local keys = {}
  for k in pairs(TRACE) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return TRACE[a] > TRACE[b2] end)
  for i = 1, math.min(#keys, 12) do
    out(string.format("      %-32s %6d 次", keys[i], TRACE[keys[i]]))
  end
end

-- [4b] ★★ 全方法 × 调用点 的栈聚合（找"还漏了哪"的唯一可靠办法 ✓）
out("")
out("== [4b] 剩余调用的**调用点**（全方法 × 栈聚合，一次 render）==")
do
  local TR = {}
  local function tk(m)
    local tb = debug.traceback("", 3)
    for line in tb:gmatch("[^\n]+") do
      local n = line:match("client_script%.lua:(%d+)")
      if n ~= nil then return n .. " [" .. m .. "]" end
    end
    return "? [" .. m .. "]"
  end
  local ALL = { "GetChildren", "GetChild", "GetChildCount", "GetParent", "GetSizeDelta",
    "GetAnchoredPosition", "SetSizeDelta", "SetAnchoredPosition", "SetVisible",
    "SetPivot", "SetImage", "SetText", "AddCursorEventListener", "GetSiblingIndex",
    "SetSiblingIndex", "SetAsFirstSibling", "GetUIPos", "GetItemIndex" }
  local function rec(c, d)
    if c == nil or d > 12 then return end
    for _, m in ipairs(ALL) do
      local f = nil; pcall(function() f = c[m] end)
      if type(f) == "function" then
        c[m] = function(_, ...)
          local k = tk(m)
          TR[k] = (TR[k] or 0) + 1
          return f(c, ...)
        end
      end
    end
    local kids = nil; pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then for j = 1, #kids do rec(kids[j], d + 1) end end
  end
  for i = 1, #tree do rec(tree[i], 0) end
  reset()
  pcall(function() ctrl:render(cur.adapter, true) end)
  local ks = {}
  for k in pairs(TR) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b2) return TR[a] > TR[b2] end)
  for i = 1, math.min(#ks, 22) do
    out(string.format("      bundle:%-38s %5d 次", ks[i], TR[ks[i]]))
  end
end

-- [4c] ★★ `set_property` 被反复下发的**是哪个 key**（找"账本为什么没挡住"✗）
out("")
out("== [4c] 一次 render 里 `set_property` 的 (id, key) 分布 ==")
do
  local ad = cur.adapter
  local SP = { n = 0, by_key = {}, by_idkey = {} }
  local osp = ad.set_property
  ad.set_property = function(self2, id, key, value, ...)
    SP.n = SP.n + 1
    SP.by_key[tostring(key)] = (SP.by_key[tostring(key)] or 0) + 1
    local ik = tostring(id) .. " . " .. tostring(key)
    SP.by_idkey[ik] = (SP.by_idkey[ik] or 0) + 1
    return osp(self2, id, key, value, ...)
  end
  reset()
  pcall(function() ctrl:render(cur.adapter, true) end)
  out(string.format("  `set_property` 共 **%d** 次；按 key：", SP.n))
  local ks = {}
  for k in pairs(SP.by_key) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b2) return SP.by_key[a] > SP.by_key[b2] end)
  for i = 1, math.min(#ks, 12) do
    out(string.format("      %-20s %5d 次", ks[i], SP.by_key[ks[i]]))
  end
  out("  --- 前 12 个 (id, key) ---")
  local k2 = {}
  for k in pairs(SP.by_idkey) do k2[#k2 + 1] = k end
  table.sort(k2, function(a, b2) return SP.by_idkey[a] > SP.by_idkey[b2] end)
  for i = 1, math.min(#k2, 12) do
    out(string.format("      %-44s %5d 次", k2[i], SP.by_idkey[k2[i]]))
  end
end

-- [4d] ★★ `rect` 到底**变没变**（★ 决定"加值守卫"有没有用 ✓）
out("")
out("== [4d] 连续两次 render 的 `rect` 是否相同（决定守卫有没有用）==")
do
  local ad = cur.adapter
  local seen = {}
  local order = {}
  local n_call = 0
  local osp = ad.set_property
  ad.set_property = function(self2, id, key, value, ...)
    if key == "rect" and type(value) == "table" then
      n_call = n_call + 1
      local sig = string.format("%s|%s|%s|%s|%s",
        tostring(value.x), tostring(value.y), tostring(value.w), tostring(value.h))
      local k = tostring(id) .. " # " .. sig
      if seen[k] == nil then seen[k] = 0; order[#order + 1] = k end
      seen[k] = seen[k] + 1
    end
    return osp(self2, id, key, value, ...)
  end
  -- 跑 4 次 render，看同一个 id 的 rect 签名是否稳定
  local per = {}
  for pass = 1, 4 do
    local before = {}
    for k in pairs(seen) do before[k] = true end
    pcall(function() ctrl:render(cur.adapter, true) end)
    per[pass] = {}
    for k in pairs(seen) do if not before[k] then per[pass][#per[pass] + 1] = k end end
    table.sort(per[pass])
  end
  local function same(a, b2)
    if #a ~= #b2 then return false end
    for i = 1, #a do if a[i] ~= b2[i] then return false end end
    return true
  end
  out(string.format("  4 趟 render 各自的 `rect` 签名集合大小：%d / %d / %d / %d",
    #per[1], #per[2], #per[3], #per[4]))
  out(string.format("  ★ 第 2 趟与第 1 趟是否**完全相同** ⇒ **%s**",
    tostring(same(per[1], per[2]))))
  out(string.format("  ★ 第 3 趟与第 2 趟是否**完全相同** ⇒ **%s**",
    tostring(same(per[2], per[3]))))
  -- 打印每个 id 出现过几种不同签名（>1 就是真的在变 ✓）
  local byid = {}
  for k in pairs(seen) do
    local id = k:match("^(.-) # ")
    if id ~= nil then byid[id] = (byid[id] or 0) + 1 end
  end
  local varying, stable = 0, 0
  for _, cnt in pairs(byid) do if cnt > 1 then varying = varying + 1 else stable = stable + 1 end end
  out(string.format("  ★ 有 rect 下发的控件里：**签名恒定 %d 个** ✓ / **签名会变 %d 个** ✗",
    stable, varying))
  out(string.format("  （[4d] 期间 `set_property(rect)` 总调用 = %d 次）", n_call))
  -- ★ 直接打几个真实样本（★ 先确认"我到底收到了什么" ✗ 别急着算签名 ✓）
  out("  --- 前 5 个真实样本（id / 值类型 / 值） ---")
  do
    local got = {}
    local osp2 = ad.set_property
    ad.set_property = function(self2, id, key, value, ...)
      if key == "rect" and #got < 5 then
        local vt = type(value)
        local desc
        if vt == "table" then
          local parts = {}
          for kk, vv in pairs(value) do parts[#parts + 1] = tostring(kk) .. "=" .. tostring(vv) end
          table.sort(parts)
          desc = "{" .. table.concat(parts, ",") .. "}"
        else
          desc = tostring(value)
        end
        got[#got + 1] = tostring(id) .. " | " .. vt .. " | " .. desc
      end
      return osp2(self2, id, key, value, ...)
    end
    pcall(function() ctrl:render(cur.adapter, true) end)
    ad.set_property = osp2
    for i = 1, #got do out("      " .. got[i]) end
  end
end

-- [4e] ★★★ 决定性一问：稳态 render 里那 111 笔几何写**是不是幂等的** ✗✓
--   ★ 口径 ✓：包装**产线控件**的 `SetPivot`/`SetSizeDelta`/`SetAnchoredPosition`，
--     写之前先读它当前的值 ⇒ **相同 = 纯浪费** ✓（★ 与 geo_write_count.lua 同口径 ✓）

-- ★ [4e0] 先把"到底写了几笔"数干净（按方法 × 冷/热）✓
out("")
out("== [4e0] 几何写笔数（按方法 × 冷/热）==")
do
  local N = { cold = {}, warm = {} }
  local ALLM = { "SetPivot", "SetSizeDelta", "SetAnchoredPosition" }
  local function wrap(c, d)
    if c == nil or d > 12 then return end
    for _, m in ipairs(ALLM) do
      local f = nil; pcall(function() f = c[m] end)
      if type(f) == "function" then
        c[m] = function(_, ...)
          cur.__cnt = cur.__cnt or {}
          cur.__cnt[m] = (cur.__cnt[m] or 0) + 1
          return f(c, ...)
        end
      end
    end
    local kids = nil; pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then for j = 1, #kids do wrap(kids[j], d + 1) end end
  end
  for i = 1, #tree do wrap(tree[i], 0) end
  -- 冷：直接量 1 趟
  cur.__cnt = {}
  pcall(function() ctrl:render(cur.adapter, true) end)
  local cold = cur.__cnt
  -- 热：先预热 3 趟，再量 1 趟
  for _ = 1, 3 do pcall(function() ctrl:render(cur.adapter, true) end) end
  cur.__cnt = {}
  pcall(function() ctrl:render(cur.adapter, true) end)
  local warm = cur.__cnt
  local function show(tag, t)
    local tot = 0
    for _, v in pairs(t) do tot = tot + v end
    out(string.format("  %s：合计 %d 笔", tag, tot))
    for _, m in ipairs(ALLM) do
      out(string.format("      %-22s %4d", m, t[m] or 0))
    end
  end
  show("冷（账本空，第 1 趟）", cold)
  show("热（预热 3 趟之后）", warm)
end
out("")
out("== [4e] 稳态 render 的几何写：幂等 vs 真变 ==")
do
  local IA = { same = 0, diff = 0, unknown = 0, samples = {} }
  local function rec(c, d)
    if c == nil or d > 12 then return end
    local nm = "?"; pcall(function() nm = tostring(c.name) end)
    -- SetSizeDelta
    local f1 = nil; pcall(function() f1 = c.SetSizeDelta end)
    if type(f1) == "function" then
      c.SetSizeDelta = function(_, w, h)
        local ow, oh = nil, nil
        pcall(function() ow, oh = c.w, c.h end)
        if ow == w and oh == h then
          IA.same = IA.same + 1
          if #IA.samples < 6 then IA.samples[#IA.samples + 1] = nm .. " SetSizeDelta 同值 " .. tostring(w) .. "x" .. tostring(h) end
        elseif ow == nil then IA.unknown = IA.unknown + 1
        else IA.diff = IA.diff + 1 end
        return f1(c, w, h)
      end
    end
    -- SetAnchoredPosition
    local f2 = nil; pcall(function() f2 = c.SetAnchoredPosition end)
    if type(f2) == "function" then
      c.SetAnchoredPosition = function(_, x, y)
        local ox, oy = nil, nil
        pcall(function() ox, oy = c.ax, c.ay end)
        if ox == x and oy == y then
          IA.same = IA.same + 1
          if #IA.samples < 6 then IA.samples[#IA.samples + 1] = nm .. " SetAnchoredPosition 同值 " .. tostring(x) .. "," .. tostring(y) end
        elseif ox == nil then IA.unknown = IA.unknown + 1
        else IA.diff = IA.diff + 1 end
        return f2(c, x, y)
      end
    end
    -- SetPivot
    local f3 = nil; pcall(function() f3 = c.SetPivot end)
    if type(f3) == "function" then
      c.SetPivot = function(_, x, y)
        local ox, oy = nil, nil
        pcall(function() ox, oy = c.pivotX, c.pivotY end)
        if ox == x and oy == y then
          IA.same = IA.same + 1
          if #IA.samples < 6 then IA.samples[#IA.samples + 1] = nm .. " SetPivot 同值 " .. tostring(x) .. "," .. tostring(y) end
        elseif ox == nil then IA.unknown = IA.unknown + 1
        else IA.diff = IA.diff + 1 end
        return f3(c, x, y)
      end
    end
    local kids = nil; pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then for j = 1, #kids do rec(kids[j], d + 1) end end
  end
  for i = 1, #tree do rec(tree[i], 0) end
  -- 预热后量 20 趟 ✓（账本已稳态 ✓）
  for _ = 1, 3 do pcall(function() ctrl:render(cur.adapter, true) end) end
  IA.same, IA.diff, IA.unknown = 0, 0, 0
  local PASS = 20
  for _ = 1, PASS do pcall(function() ctrl:render(cur.adapter, true) end) end
  out(string.format("  %d 趟 render 的几何写：**幂等 %d 笔** ✗ / 真变 %d 笔 ✓ / 读不到原值 %d 笔",
    PASS, IA.same, IA.diff, IA.unknown))
  out(string.format("  平均每趟：幂等 **%.1f** 笔 ✗，真变 %.1f 笔", IA.same / PASS, IA.diff / PASS))
  if IA.same > 0 then
    out("  --- 幂等样本（写进去的值与原来完全相同 ⇒ 可省 ✓） ---")
    for i = 1, #IA.samples do out("      " .. IA.samples[i]) end
  end
end

-- [5] ★ 谁在调 `Adapter:sub` / `Controller:_palette_child`（次数 + 命中率）out("")
out("== [5] `Adapter:sub` / `_palette_child` 的调用次数与命中率（一次 render）==")
do
  local ad = cur.adapter
  local SUB = { n = 0, miss = 0, bykey = {} }
  local os_sub = ad.sub
  ad.sub = function(self2, pid, cname)
    SUB.n = SUB.n + 1
    local k = tostring(pid) .. "." .. tostring(cname)
    SUB.bykey[k] = (SUB.bykey[k] or 0) + 1
    local cached = nil
    pcall(function() cached = self2.subs[k] end)
    if cached == nil or cached == false then SUB.miss = SUB.miss + 1 end
    return os_sub(self2, pid, cname)
  end
  local PC = { n = 0, byarg = {} }
  local opc = ctrl._palette_child
  ctrl._palette_child = function(self2, nm)
    PC.n = PC.n + 1
    PC.byarg[tostring(nm)] = (PC.byarg[tostring(nm)] or 0) + 1
    return opc(self2, nm)
  end
  reset()
  pcall(function() ctrl:render(cur.adapter, true) end)
  out(string.format("  `Adapter:sub` 调了 **%d** 次（其中**未命中缓存** %d 次）", SUB.n, SUB.miss))
  out(string.format("  `_palette_child` 调了 **%d** 次", PC.n))
  local keys = {}
  for k in pairs(SUB.bykey) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b2) return SUB.bykey[a] > SUB.bykey[b2] end)
  out("  --- sub 的键（前 12） ---")
  for i = 1, math.min(#keys, 12) do
    out(string.format("      %-40s %5d 次", keys[i], SUB.bykey[keys[i]]))
  end
end
out("")
out("== 说明 ==")
out("  · 量的是**调用次数**与**纯 Lua 耗时**（`os.clock` ✓）；真机毫秒只有实机能给 ✓")
out("  · ★ 触发门是 `sec ~= last_tick or dirty` ⇒ 稳态 ≈1 次/秒，**但每次输入都会 render** ✓")
out("  · 产线源码未改 ✓（只在内存里包方法 ✓）")
