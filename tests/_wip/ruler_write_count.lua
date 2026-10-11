--[[----------------------------------------------------------------------------
  tests/_wip/ruler_write_count.lua —— 【探针】量 `apply_ruler_layout` 的几何写笔数

  ★ 量什么（2026-10-11 性能优化 · 大鱼 2 的第 1 刀）：
     `Adapter:apply_ruler_layout` **每次 render 都被调用**（`Murdoku.render` → 它 ✓），
     稳态 ≈ **1.10 次/秒**（本文件自己记的实测值 ✓）。
     而它对行标/列标做的是：
        `SetPivot(0.5,0.5)` ＋ `SetAnchoredPosition(cx - rx, ly)`
     ——**两个目标值在同一块棋盘上都不变** ✗ ⇒ 稳态**全是幂等白烧** ✓

  ★ 支持 A/B：同一个探针可以跑**任意产物** ⇒ 直接对比"改前 / 改后"的写笔数 ✓
     跑法：lua tests/_wip/ruler_write_count.lua [产物路径]
     默认：dist/client_script.lua
     对照：lua tests/_wip/ruler_write_count.lua _wip/bak-perfopt-20261011-232919/bundle-v192-verified.lua

  ★ 口径：记账记在**假控件自己的方法**里 ✓（不是读产线内部变量 ⇒ 无法自欺 ✓）
     **正向对照**：手动把一个标签挪错 ⇒ 下一趟**必须真的写回去** ✓
                    （证明"0 笔"是"不需要写"，不是"没走到" ✓）
  只读：本文件**不改任何生产源码** ✓
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/ruler_write_count.lua"
local root = here:gsub("tests[/\\]_wip[/\\]ruler_write_count%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
do
  local function sink(...) end
  _G.print = sink
  _G.printerr = sink
end

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

-- ── 记账：pivot 写 / 位置写（按控件名）────────────────────────────────────
local W = { pivot = 0, pos = 0, by_name = {} }
local function bump(nm, kind)
  if kind == "pivot" then W.pivot = W.pivot + 1 else W.pos = W.pos + 1 end
  local k = tostring(nm) .. "." .. kind
  W.by_name[k] = (W.by_name[k] or 0) + 1
end
local function reset() W.pivot, W.pos, W.by_name = 0, 0, {} end

local function attach(parent, c)
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end

-- ★ 关键：`pivotX/pivotY` 要**真的可读**，否则产线会以为"读不到 ⇒ 照写" ✓
--   （这正是"读不到就照写"那条守卫的设计 ✓ —— 本探针让它读得到，才能量出省了多少 ✓）
local function make_ctrl(name, kind)
  local c = {
    name = name, kind = kind or "container", visible = true, active = true,
    __kids = {}, pivotX = 0.5, pivotY = 0.5, w = 0, h = 0, ax = 0, ay = 0,
  }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v) c.visible = v end
  c.SetActive = function(_, v) c.active = v end
  c.SetSizeDelta = function(_, w, h) c.w, c.h = w, h end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
  c.SetAnchoredPosition = function(_, x, y)
    c.ax, c.ay = x, y
    bump(c.name, "pos")
  end
  c.GetAnchoredPosition = function() return c.ax or 0, c.ay or 0 end
  c.SetPivot = function(_, x, y)
    c.pivotX, c.pivotY = x, y
    bump(c.name, "pivot")
  end
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

local function make_text(name)
  local c = make_ctrl(name, "text")
  local store = { text = name }
  return setmetatable(c, {
    __index = function(_, k) if k == "text" then return store.text end return nil end,
    __newindex = function(t, k, v) if k == "text" then store.text = v else rawset(t, k, v) end end,
  })
end

-- 假树：root → stage（25 格）＋ root → board → ruler → 5 列 + 5 行
local RULER = {}
local tree
do
  local rt = make_ctrl("root")
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right", "actions", "modal", "intro" }) do
    attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage"))
  for r = 1, 5 do
    for c = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. c, "button")
      -- 格子位置：每格 120，居中 —— 让 cellPos 读得到数 ✓
      cell.ax, cell.ay = (c - 3) * 120, (3 - r) * 120
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
  local board = attach(rt, make_ctrl("board"))
  local ruler = attach(board, make_ctrl("ruler"))
  ruler.ax, ruler.ay = 10, 20          -- rx / ry
  -- ★★ 关键：行标/列标的**初始位置必须与目标不同** ✗
  --   否则"读回再写"守卫会**直接命中"已等于目标"** ⇒ 两边都 0 笔 ⇒ 量不出差别 ✗
  --   （我第一次就是这么搭的：`ax` 默认 0，而 `cx - rx` 恰好也是 0 ⇒ 探针失去分辨力 ✓）
  --   真机上编辑器摆的标签与"格子中心"总有偏差 ⇒ 这里用一组**明显错位**的初值 ✓
  --   pivot 也用非 0.5 的初值 ⇒ 让"pivot 守卫"同样可分辨 ✓
  for j = 1, 5 do
    local t = attach(ruler, make_text("ruler.c." .. j))
    t.ax, t.ay = 500 + j, 700 + j
    t.pivotX, t.pivotY = 0.3, 0.7
    RULER["ruler.c." .. j] = t
  end
  for i = 1, 5 do
    local t = attach(ruler, make_text("ruler.r." .. i))
    t.ax, t.ay = 900 + i, 300 + i
    t.pivotX, t.pivotY = 0.25, 0.75
    RULER["ruler.r." .. i] = t
  end
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
  DestroyClientUIControl = function() end,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end,
  PrintClientUITree = function() end,
  ServerSignal = function()
    local s = {}
    s.AddInt = b; s.AddFloat = b; s.AddString = b; s.AddBool = b; s.SendSignal = b
    return s
  end,
  PlayAudio2D = b,
  GetText = function() return "" end,
}
_G.script = {
  EnableUpdate = b, RegisterServerSignalHandler = b,
  RegisterCustomVariableChangedHandler = b, Invoke = b,
  GetParam = function() return nil end,
}
_G.Enum = {
  CursorEventType = { CursorClick = "CursorClick", CursorClickDown = "CursorClickDown",
    CursorClickUp = "CursorClickUp", CursorDrag = "CursorDrag" },
  KeyEventType = { KeyDown = "KeyDown", KeyUp = "KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart)

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local adapter, ctrl = cur.adapter, cur.controller
if adapter == nil or type(adapter.apply_ruler_layout) ~= "function" then
  out("  apply_ruler_layout 不在 ⇒ 量不到"); os.exit(2)
end

-- 把假控件塞进 adapter.controls ⇒ `find` 直接命中 ✓
for i = 1, 5 do
  adapter.controls["ruler.c." .. i] = RULER["ruler.c." .. i]
  adapter.controls["ruler.r." .. i] = RULER["ruler.r." .. i]
  adapter.controls["cell.1." .. i] = tree[1].__kids[#tree[1].__kids - 1]  -- 占位，下面会真找
end
-- 真把 cell.* 也塞进去（ruler 定位要读 cell.1.j / cell.i.1 的位置 ✓）
do
  local st = nil
  for _, k in ipairs(tree[1].__kids) do if k.name == "stage" then st = k end end
  for _, k in ipairs(st.__kids or {}) do
    if k.name:sub(1, 5) == "cell." then adapter.controls[k.name] = k end
  end
  adapter.controls["ruler"] = RULER["ruler.c.1"].__parent
  adapter.controls["board"] = RULER["ruler.c.1"].__parent.__parent
end
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 先跑一趟把位置摆对
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 先跑 1 趟把行标/列标摆到位 ==")
reset()
local moved1 = select(2, pcall(function() return adapter:apply_ruler_layout(5, 5) end))
out(string.format("  第 1 趟：pivot 写 %d 笔，pos 写 %d 笔（返回 moved=%s）",
  W.pivot, W.pos, tostring(moved1)))

-- ════════════════════════════════════════════════════════════════════════════
-- [2] 稳态：再跑 10 趟（≈真机 9 秒的 render 次数）—— 改后应为 0 笔
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] 稳态：再跑 10 趟（真机 ≈9 秒，1.10 次/秒）==")
reset()
for _ = 1, 10 do pcall(function() adapter:apply_ruler_layout(5, 5) end) end
out(string.format("  10 趟合计：pivot 写 %d 笔，pos 写 %d 笔", W.pivot, W.pos))
do
  local keys = {}
  for k in pairs(W.by_name) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do out(string.format("      %-16s %d", k, W.by_name[k])) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] 正向对照：把一个标签挪错 ⇒ 必须真的写回去
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] 正向对照：把 ruler.c.1 挪错 ⇒ 下一趟必须写回 ==")
do
  local lbl = RULER["ruler.c.1"]
  lbl.ax = -9999                      -- 故意挪错（绕过记账 ⇒ 模拟"引擎/别人把它挪了"）
  reset()
  pcall(function() adapter:apply_ruler_layout(5, 5) end)
  ok(W.pos > 0, "★ 挪错之后**真的写回去了**（证明 0 笔是「不需要写」而非「没走到」）",
    "pos 写 " .. tostring(W.pos) .. " 笔")
  -- 再跑一趟：又该是 0
  reset()
  pcall(function() adapter:apply_ruler_layout(5, 5) end)
  ok(W.pos == 0, "★ 摆正之后**又回到 0 笔**（幂等 ✓）", "pos 写 " .. tostring(W.pos) .. " 笔")
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
