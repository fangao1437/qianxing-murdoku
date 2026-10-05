--[[----------------------------------------------------------------------------
  tests/perframe_throttle.lua —— 离线验「每帧节流位」到底节到了哪一档

  为什么要这个测试：`main.lua` 的 `on_update` 里有两段**按帧号节流**的同步：
    · 「按屏幕同步运行时控件的可见性」（`setv("selbar", …)` / 25 个 `cell.*`）
      —— 代码注释写着**改成每帧**（L1522-1525：`selbar` 必须每帧压住才稳）；
    · 「每 30 帧点亮 25 个格子的 content/face」
      —— 代码注释写着**每 30 帧**（L1504-1511：移动端负载优化）。
  而这两段都写在 `if (current.frames or 0) % 300 == 0 then` **里面** ——
  换句话说：注释说"每帧 / 每 30 帧"，代码实际是**每 300 帧**（0.5 fps 时代的一档）。
  这类"注释与代码不一致"正是本项目反复吃亏的形状（症状看着在别处）。

  判据（不依赖任何内部变量，只看**引擎侧被调用的次数**）：
    [A] 关卡内稳态 60 帧（每帧 dt=1/60）：
        · 25 个格子的 `content` 被 `SetVisible` 的次数 —— 每帧同步 ⇒ 应有 60 次/格；
          每 30 帧 ⇒ 2 次/格；每 300 帧 ⇒ 0 次/格。
        · `selbar` 被 `SetVisible` 的次数 —— 同理（每帧 60 次 / 每 300 帧 0 次）。
    [B] 跑到第 300 帧那一帧：上面两段**确实会跑**（证明它们没被删掉，只是节流位错）
        —— 计数必须 > 0。
    [C] `apply_ruler_layout`（每次 `render` 都被调）在稳态 300 帧里
        重复打印「行标/列标已按格子实际位置对齐」的次数 —— 内容没变就不该重复打。

  跑法：lua tests/perframe_throttle.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/perframe_throttle.lua"
local root = here:gsub("tests[/\\]perframe_throttle%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print          -- 测试自己的输出（被测试代码的 print 会被劫持）

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

-- ── 劫持日志：既要能数，也要保住"运行期不得有 error 日志"的口径 ──────────────
local logs = {}
local function collect(level, ...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
end
_G.print = function(...) collect("info", ...) end
_G.printerr = function(...) collect("error", ...) end

-- ── 假控件树 ────────────────────────────────────────────────────────────────
local C = { vis = {} }     -- C.vis[名字] = SetVisible 被调用次数
local function bump(name, v)
  C.vis[name] = (C.vis[name] or 0) + 1
end
local function attach(parent, c)
  if parent == nil then return nil end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end
local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true, __kids = {} }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v) c.visible = v; bump(name, v) end
  c.SetActive = function(_, v) c.active = v end
  c.SetSizeDelta = function(_, w, h) c.w, c.h = w, h end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
  c.SetAnchoredPosition = function(_, x, y) c.ax, c.ay = x, y end
  c.GetAnchoredPosition = function() return c.ax or 0, c.ay or 0 end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() end
  c.SetLocalScale = function() end
  c.AddCursorEventListener = function() end
  c.SetImage = function() return false end
  c.SetSiblingIndex = function() return true end
  c.GetSiblingIndex = function() return 0 end
  c.SetAsFirstSibling = function() return true end
  return c
end
local function make_text(name)
  local c = make_ctrl(name)
  c.kind = "text"
  local store = { text = name }
  return setmetatable(c, {
    __index = function(_, k) if k == "text" then return store.text end return nil end,
    __newindex = function(t, k, v) if k == "text" then store.text = v else rawset(t, k, v) end end,
  })
end

local tree, stage_ctrl
do
  local rt = make_ctrl("root")
  attach(rt, make_ctrl("home"))
  attach(rt, make_ctrl("select"))
  local st = make_ctrl("stage")
  stage_ctrl = st
  for r = 1, 5 do
    for c = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. c)
      cell.kind = "button"
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))          -- face 是孙控件（第二层）
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(st, cell)
    end
  end
  -- 运行时创建的那三样（main.lua 的 setv 名单）
  attach(st, make_ctrl("selbar"))
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
  -- ruler（apply_ruler_layout 要它才不提前 return）
  local board = attach(rt, make_ctrl("board"))
  local ruler = attach(board, make_ctrl("ruler"))
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
    s.AddInt = function() end; s.AddFloat = function() end
    s.AddString = function() end; s.AddBool = function() end; s.SendSignal = function() end
    return s
  end,
  PlayAudio2D = function() end,
  GetText = function() return "" end,
}
_G.script = {
  EnableUpdate = function() end,
  RegisterServerSignalHandler = function() end,
  RegisterCustomVariableChangedHandler = function() end,
  Invoke = function() end,
  GetParam = function() return nil end,
}
_G.Enum = nil

-- ── 加载产物 ────────────────────────────────────────────────────────────────
local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then
  out("  加载失败：" .. tostring(lerr) .. "　→ 先跑 `lua tools/bundle_client_script.lua`")
  os.exit(1)
end
assert(pcall(chunk))
local ok1, err1 = pcall(OnInit)
local ok2, err2 = pcall(OnStart)
if not (ok1 and ok2) then
  out("  OnInit/OnStart 失败：" .. tostring(err1) .. " / " .. tostring(err2)); os.exit(1)
end

local dbg = _G.__murdoku_debug
local cur = dbg.Murdoku.current()
local ctrl, adapter = cur.controller, cur.adapter

-- 挂钩子：数 render / apply_ruler_layout 的调用；并把 OnUpdate 里的异常抓出来
-- （`pcall` 包循环是本项目测试的惯例，但**不能因此吞掉异常** —— 那正是"静默失败"）
local C2 = { render = 0, ruler = 0, ruler_ret = nil, err = nil }
do
  local orr = ctrl.render
  ctrl.render = function(self, ...) C2.render = C2.render + 1 return orr(self, ...) end
  local oar = adapter.apply_ruler_layout
  adapter.apply_ruler_layout = function(self, ...)
    C2.ruler = C2.ruler + 1
    local n = oar(self, ...)
    C2.ruler_ret = n
    return n
  end
end
local function step(n)
  for _ = 1, n do
    local o, e = pcall(OnUpdate, 1 / 60)
    if not o then C2.err = tostring(e) end
  end
end

-- 进关卡内（screen = nil ⇒ main.lua 里 scr_now = "level"）
ctrl.screen = nil
ctrl.dirty = true
step(5)
ok(C2.err == nil, "（前置）进关卡这几帧 OnUpdate 不抛错", tostring(C2.err))

local function frames_now() return cur.frames or 0 end
local function vis_of(name) return C.vis[name] or 0 end
local function count_log(pat)
  local n = 0
  for i = 1, #logs do if logs[i].text:find(pat, 1, true) then n = n + 1 end end
  return n
end

----------------------------------------------------------------------------
out("\n== A. 关卡内稳态 60 帧：节流位到底在哪一档 ==")
local f0 = frames_now()
out(string.format("  起始帧号 = %d（下一次 frames%%300==0 在第 %d 帧）",
  f0, (math.floor(f0 / 300) + 1) * 300))
local base_cell = vis_of("cell.1.1")
local base_bar  = vis_of("selbar")
step(60)
local d_cell = vis_of("cell.1.1") - base_cell
local d_bar  = vis_of("selbar") - base_bar

-- 每帧同步 ⇒ 60 次；每 30 帧 ⇒ 2 次；每 300 帧（当前）⇒ 0 次
ok(d_cell >= 55,
  "★ 关卡内 60 帧里 `cell.*` 被按屏同步（注释：**每帧**压住）",
  "实测 cell.1.1 SetVisible " .. d_cell .. " 次（每帧应为 60；每 30 帧为 2；每 300 帧为 0）")
ok(d_bar >= 55,
  "★ 关卡内 60 帧里 `selbar` 被压住（注释 L1522-1525：**必须每帧压住才稳**）",
  "实测 selbar SetVisible " .. d_bar .. " 次")

----------------------------------------------------------------------------
out("\n== B. 跑到第 300 帧：这两段**确实存在**，只是节流位错 ==")
local need = 300 - frames_now()
if need > 0 then step(need) end
ok(frames_now() == 300, "（先把帧号推到刚好 300）", "frames=" .. tostring(frames_now()))
-- ⚠️ 计数必须在"这一帧"之前取：`current.frames` 是在 on_update **末尾** 自增的，
--    所以帧号 == 300 的那一次 OnUpdate，判据 `frames % 300 == 0` 命中的正是它。
local before = vis_of("cell.1.1")
step(1)
local fired = vis_of("cell.1.1") - before
ok(fired > 0,
  "★ 帧号 == 300 那一帧，`cell.*` 的按屏同步**确实会跑**（证明代码在，只是节流位错）",
  "实测 cell.1.1 SetVisible " .. tostring(fired) .. " 次"
  .. "（若按注释「每帧」节流，60 帧内应为 60 次量级）")

----------------------------------------------------------------------------
out("\n== C. `apply_ruler_layout` 的重复打印（每次 render 都调）==")
-- 先把帧号稳定在"非 300 倍数"的区间，跑 300 帧（约 5 秒）看打印次数
local n_ruler = count_log("行标/列标已按格子实际位置对齐")
local n_check = count_log("核对：cell.1.1=")
out(string.format("  render 调用 = %d 次，apply_ruler_layout 调用 = %d 次（最后一次返回 %s）",
  C2.render, C2.ruler, tostring(C2.ruler_ret)))
out(string.format("  「行标/列标已按格子实际位置对齐」打了 %d 次，「核对：cell.1.1=」打了 %d 次",
  n_ruler, n_check))
-- 内容没变 ⇒ 这两行只该打一次（首次对齐）
ok(n_ruler <= 1,
  "★ 稳态里「行标/列标已按格子实际位置对齐」**不重复打**（内容没变就没有新信息）",
  "实测 " .. tostring(n_ruler) .. " 次 / " .. tostring(C2.ruler) .. " 次调用；"
  .. "每次 render 各打 2 行 ⇒ 会话越长日志越多")

----------------------------------------------------------------------------
out("\n== D. 不许有运行时报错（口径与 tests/prop_ledger.lua 一致）==")
do
  local bad = {}
  for i = 1, #logs do
    local L = logs[i]
    if L.level == "error" then
      if L.text:find("attempt to", 1, true) or L.text:find("nil value", 1, true)
         or L.text:find("bad argument", 1, true) then
        bad[#bad + 1] = L.text
      end
    end
  end
  ok(#bad == 0, "没有 printerr 级的 attempt to / nil value / bad argument",
    #bad == 0 and "(0 条)" or ("第一条：" .. tostring(bad[1])))
end

out(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
