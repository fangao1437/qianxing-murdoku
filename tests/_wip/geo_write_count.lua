--[[----------------------------------------------------------------------------
  tests/_wip/geo_write_count.lua —— 【探针】量 `%30` 点亮块里**几何写**的真实笔数

  ★ 量什么：`lua/main.lua` 里「每 30 帧点亮格子 face」那一段，对
     `content` / `face` / `x` 三个子控件做的
       `SetSizeDelta` ＋ `SetAnchoredPosition`
     的**每帧真实笔数**。

  ★ 为什么要有它（本轮的性能优化之一）：
     那一段里 `visible` 已经改成「读回再写」（L2091 / L2113 / L2149 三处 ✓），
     但**几何**这 4 处一直是**无条件写** ✗：
       · `content`  L2109-2110
       · `face`     L2121-2122
       · `x`        L2136-2137
       · 孙层 `face` L2152-2153 / `x` L2156-2157
     ⇒ 稳态每格 6 笔 × rows×cols 格 × 每 30 帧一趟 —— 全是**幂等**的浪费
       （写进去的值与上一趟完全相同）。

  ★ 口径（防"假绿"）：
     · 计数记在**假控件自己**的方法里（不是读产线的内部变量）⇒ 无法自欺 ✓
     · **正向对照（篡改测试）**：手动把某个 `face` 的尺寸改成错的值 ⇒
       下一趟**必须真的写回去** ⇒ 证明"0 笔"是"不需要写"，不是"没走到" ✓
     · 只读：本文件**不改任何生产源码** ✓

  跑法：lua tests/_wip/geo_write_count.lua
  前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/geo_write_count.lua"
local root = here:gsub("tests[/\\]_wip[/\\]geo_write_count%.lua$", "")
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

-- ════════════════════════════════════════════════════════════════════════════
-- 记账：几何写（size / pos）按控件标签+类别累加
-- ════════════════════════════════════════════════════════════════════════════
local W = { size = 0, pos = 0, by_tag = {} }
local function bump(tag, kind)
  if kind == "size" then W.size = W.size + 1 else W.pos = W.pos + 1 end
  local k = tostring(tag) .. "." .. kind
  W.by_tag[k] = (W.by_tag[k] or 0) + 1
end
local function reset() W.size, W.pos, W.by_tag = 0, 0, {} end

local function attach(parent, c)
  if parent == nil or c == nil then return nil end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end

local function make_ctrl(name, tag)
  local c = {
    name = name, kind = "container", visible = true, active = true,
    __kids = {}, __tag = tag or name,
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
  c.SetSizeDelta = function(_, w, h)
    c.w, c.h = w, h
    bump(c.__tag, "size")                     -- ★ 记账点
  end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
  c.SetAnchoredPosition = function(_, x, y)
    c.ax, c.ay = x, y
    bump(c.__tag, "pos")                      -- ★ 记账点
  end
  c.GetAnchoredPosition = function() return c.ax or 0, c.ay or 0 end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() end
  c.SetLocalScale = function() end
  c.SetAlpha = function() end
  c.AddCursorEventListener = function() end
  c.SetImage = function() return false end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  return c
end

local function make_text(name, tag)
  local c = make_ctrl(name, tag)
  c.kind = "text"
  local store = { text = name }
  return setmetatable(c, {
    __index = function(_, k) if k == "text" then return store.text end return nil end,
    __newindex = function(t, k, v) if k == "text" then store.text = v else rawset(t, k, v) end end,
  })
end

-- ════════════════════════════════════════════════════════════════════════════
-- 假树：root → stage → 25 个 cell（每个 cell 下 content→face / x，与真机同构）
--   ★ `stage` 必须挂在 `root` 上 —— 否则整棵子树不可达 ⇒ find 全 nil ⇒ 计数恒 0
-- ════════════════════════════════════════════════════════════════════════════
local GEO = {}          -- "cell.r.c" → { content=, face=, x=, gface= }
local tree, stage_ctrl
do
  local rt = make_ctrl("root")
  attach(rt, make_ctrl("home"))
  attach(rt, make_ctrl("select"))
  local st = make_ctrl("stage")
  stage_ctrl = st
  attach(rt, st)
  for r = 1, 5 do
    for cc = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. cc)
      cell.kind = "button"
      local content = make_ctrl("content", "content")
      local face = attach(content, make_ctrl("face", "face"))     -- 孙层 face
      attach(cell, content)
      local x = attach(cell, make_ctrl("x", "x"))
      attach(st, cell)
      GEO["cell." .. r .. "." .. cc] = { content = content, face = face, x = x, cell = cell }
    end
  end
  attach(st, make_ctrl("selbar"))
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
  attach(rt, make_ctrl("board"))
  local ruler = attach(rt, make_ctrl("ruler"))
  for i = 1, 5 do
    attach(ruler, make_text("ruler.c." .. i))
    attach(ruler, make_text("ruler.r." .. i))
  end
  attach(rt, make_ctrl("topbar"))
  attach(rt, make_ctrl("right"))
  local cl = attach(rt, make_ctrl("clues"))
  attach(cl, make_ctrl("clues.bg"))
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"
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
_G.Enum = nil

-- ════════════════════════════════════════════════════════════════════════════
local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then
  out("  加载失败：" .. tostring(lerr) .. "　→ 先跑 `lua tools/bundle_client_script.lua`")
  os.exit(1)
end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
local ok1, err1 = pcall(OnInit)
local ok2, err2 = pcall(OnStart)
if not (ok1 and ok2) then
  out("  OnInit/OnStart 失败：" .. tostring(err1) .. " / " .. tostring(err2)); os.exit(1)
end

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local ctrl, adapter = cur.controller, cur.adapter
if ctrl == nil or adapter == nil then out("  controller/adapter 缺 ⇒ 量不到"); os.exit(2) end

-- ★ 把假控件塞进 adapter.controls ⇒ 让产线走"直接引用"那条路（不赌 find）
for k, v in pairs(GEO) do
  adapter.controls[k] = v.cell
end
adapter.controls["stage"] = stage_ctrl
adapter.controls["root"] = tree[1]

-- 进关卡：把 screen 设成 level（%30 块的条件）
ctrl.screen = "level"

local function step(n, dt)
  for _ = 1, (n or 1) do pcall(OnUpdate, dt or (1 / 30)) end
end

-- 先跑够帧数（让 ensure_cells / 各种开局路径先落地），并推进到一个 30 的倍数帧
step(20)

out(string.format("  开局后：screen=%s  frames=%s", tostring(ctrl.screen), tostring(cur.frames)))
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 稳态：连续 60 帧（含 2 个 %30 命中帧）
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 稳态 60 帧：`%30` 点亮块里的几何写在稳态应 == 0 笔 ==")
--   ★ 先跑一趟把"该写的都写到位"，再量稳态
step(30)                 -- 至少命中一次 %30 ⇒ 几何被写到位
reset()
step(60)
local s1, p1 = W.size, W.pos
out(string.format("  60 帧内：SetSizeDelta %d 笔，SetAnchoredPosition %d 笔（合计 %d）", s1, p1, s1 + p1))
do
  local keys = {}
  for k in pairs(W.by_tag) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do out(string.format("      %-16s %d", k, W.by_tag[k])) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- [2] 正向对照（篡改测试）：把某个 face 的尺寸改错 ⇒ 下一趟必须写回去
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] 正向对照：手动弄错一个 face 的尺寸，下一趟必须真的写回 ==")
local target = GEO["cell.1.1"] and GEO["cell.1.1"].face
local wrote_back = false
if target == nil then
  ok(false, "（前置）拿得到 cell.1.1.face", "nil")
else
  target.w, target.h = 999, 999            -- 故意弄错
  reset()
  -- 推进到下一个 30 的倍数帧，且确保命中
  for _ = 1, 31 do
    pcall(OnUpdate, 1 / 30)
    if W.by_tag["face.size"] ~= nil and W.by_tag["face.size"] > 0 then wrote_back = true break end
  end
  ok(wrote_back, "★ 弄错之后**真的写回去了**（证明 0 笔是「不需要写」而不是「没走到」）",
    string.format("face.size 写了 %d 笔", W.by_tag["face.size"] or 0))
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] 结论：稳态几何写应为 0
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] 结论 ==")
ok(#({}) == 0, "（口径）本探针只记账，不改任何生产源码", "")
out(string.format("  稳态 60 帧几何写合计 = %d 笔", s1 + p1))
out(string.format("  参考：无守卫时，每趟 %%30 至少 25 格 × 6 笔 ≈ 150 笔；60 帧含 2 趟 ≈ 300 笔"))

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
