--[[----------------------------------------------------------------------------
  tests/_wip/probe_throttle_cost.lua —— 【本轮验收探针】量「强压窗口 + 写值记忆」的真实成本

  ★ 为什么需要这个文件（而不是用 tests/perframe_throttle.lua 的 A/B 两节）：
    那两节的假树**结构无效** —— `local st = make_ctrl("stage")` 之后**没有** `attach(rt, st)`，
    ⇒ `stage` 从来不是 `root` 的孩子（`stage.__parent == nil`）；而 `selbar` / `selbtn.*` /
    `tpl-container` / 25 个 `cell.*` **全都挂在 stage 下面** ⇒ 它们整棵子树在 `root` 上不可达。
    后果（实测，非推断）：
      · `adapter:find("stage")` = false ⇒ `ensure_widgets` 在"找不到父容器 stage"处提前返回
        ⇒ `selbar` / `selbtn.*` **从未被创建**（`adapter.controls["selbar"] == nil`）
      · `adapter:find("cell.1.1")` = false ⇒ `setv()` 拿不到任何控件
    ⇒ 那两节断言里的计数**被结构钉死在 0，和 `%30`/`%300` 门一点关系都没有**。
    本文件**只做一件事**：把 `attach(rt, st)` 这**一行**补上（其余逐字照抄），
    让那棵树与真机同构，然后量真实数字。
    ⚠️ 没有放松任何断言 —— 这里量的是**成本**（写次数），不是把红改绿。

  量什么：
    [1] 进关后头 60 帧（强压窗口）的实际写次数
    [2] 窗口结束后的**稳态**每帧写次数 —— 目标 = **0**
    [3] 换屏（level → select）后是否重新开窗、又写了几笔
    [4] 换关（level_id 变）后是否重新开窗
    [5] `%30` 那个"点亮 face"节流位现在真的每 30 帧跑一次了吗（旧 bug：被 `%300` 套住）
    [6] 对照：**改之前**的行为（每帧无条件写）= 每帧 33 次，写在这个文件里当基线

  跑法：lua tests/_wip/probe_throttle_cost.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/probe_throttle_cost.lua"
local root = here:gsub("tests[/\\]_wip[/\\]probe_throttle_cost%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print
local logs = {}
do
  local function collect(level, ...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
  end
  _G.print = function(...) collect("info", ...) end
  _G.printerr = function(...) collect("error", ...) end
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

-- ── 假控件（逐字照抄 perframe_throttle，只加了按名字记账）────────────────────
local C = { vis = {}, byname = {}, traces = {}, objs = {} }
local TRACE_ON = false
local function bump(name)
  C.vis[name] = (C.vis[name] or 0) + 1
  if TRACE_ON and name == "selbar" then
    local tb = debug.traceback("", 2)
    local frames = {}
    for line in tb:gmatch("[^\n]+") do
      if not line:find("probe_throttle_cost", 1, true) or line:find("pcall", 1, true) then
        frames[#frames + 1] = line:gsub("^%s+", "")
      end
      if #frames >= 4 then break end
    end
    local key = table.concat(frames, " ← ")
    C.traces[key] = (C.traces[key] or 0) + 1
  end
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
  c.SetVisible = function(_, v) c.visible = v; bump(name) end
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
      attach(content, make_ctrl("face"))
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(st, cell)
    end
  end
  attach(st, make_ctrl("selbar"))
  for i = 1, 6 do attach(st, make_ctrl("selbtn." .. i)) end
  attach(st, make_ctrl("tpl-container"))
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
  -- ★★★★★ 本文件与 perframe_throttle 的**唯一差异**就是这一行：
  attach(rt, st)
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

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
assert(pcall(chunk))
local ok1, err1 = pcall(OnInit)
local ok2, err2 = pcall(OnStart)
if not (ok1 and ok2) then
  out("  OnInit/OnStart 失败：" .. tostring(err1) .. " / " .. tostring(err2)); os.exit(1)
end

local dbg = _G.__murdoku_debug
local cur = dbg.Murdoku.current()
local ctrl, adapter = cur.controller, cur.adapter

out("\n== 前置：这棵树和 perframe_throttle 的差别到底有没有效 ==")
out(string.format("  find('stage')   = %s   （perframe_throttle 里恒为 false）",
  tostring(adapter:find("stage") ~= nil)))
out(string.format("  controls['selbar'] = %s   controls['cell.1.1'] = %s",
  tostring(adapter.controls and adapter.controls["selbar"] ~= nil),
  tostring(adapter.controls and adapter.controls["cell.1.1"] ~= nil)))

local function vis_of(name) return C.vis[name] or 0 end
local function total_vis()
  local n = 0
  for _, v in pairs(C.vis) do n = n + v end
  return n
end
local function step(n)
  for _ = 1, n do pcall(OnUpdate, 1 / 60) end
end

-- 进关卡（screen = nil ⇒ scr_now = "level"）
ctrl.screen = nil
ctrl.dirty = true

out("\n== [1] 进关后头 60 帧：强压窗口的实际写次数 ==")
local before_frames = cur.frames or 0
local b_cell, b_bar, b_btn, b_tpl = vis_of("cell.1.1"), vis_of("selbar"),
  vis_of("selbtn.1"), vis_of("tpl-container")
local b_all = total_vis()
-- ★ 逐帧记账：`_vis_wrote` = **本段**这一帧真正写了几笔；
--   SetVisible 总数之差 = 本段 + 渲染那一段（`bar:SetVisible(on_select)` 等）的总和。
local acc_mine, acc_all = 0, 0
local per_frame = {}
for i = 1, 60 do
  local t0 = total_vis()
  pcall(OnUpdate, 1 / 60)
  local mine = tonumber(cur._vis_wrote) or 0
  local all = total_vis() - t0
  acc_mine = acc_mine + mine
  acc_all = acc_all + all
  if i <= 3 or i == 59 or i == 60 then
    per_frame[#per_frame + 1] = string.format("      第 %.0f 帧：本段 %.0f 笔，本帧合计 %.0f 笔", i, mine, all)
  end
end
for _, L in ipairs(per_frame) do out(L) end
out(string.format("  ⚠️ 注意：`step(60)` 之前探针已经走过 60 帧（进关），所以下面的“窗口”从第 61 帧算起。"))
local w_cell = vis_of("cell.1.1") - b_cell
local w_bar = vis_of("selbar") - b_bar
local w_btn = vis_of("selbtn.1") - b_btn
local w_tpl = vis_of("tpl-container") - b_tpl
local w_all = total_vis() - b_all
out(string.format("  帧号 %.0f → %.0f", before_frames, cur.frames or 0))
out(string.format("  写入：cell.1.1=%.0f  selbar=%.0f  selbtn.1=%.0f  tpl-container=%.0f", w_cell, w_bar, w_btn, w_tpl))
out(string.format("  **合计 %.0f 笔 / 60 帧 = %.2f 笔/帧**（33 个控件 × 60 帧 = 1980 笔为上限）",
  w_all, w_all / 60))
out(string.format("  ★ 其中**本段**（按屏同步）写了 %.0f 笔 = %.2f 笔/帧（窗口内就是每帧写一遍 33 个 ⇒ 期望 1980）",
  acc_mine, acc_mine / 60))
out(string.format("  ★ 另外 %.0f 笔来自**渲染那一段**的既有写（不在本次范围）", acc_all - acc_mine))
ok(w_cell >= 55, "★ 强压窗口里 cell.1.1 被真的压住（≥55/60 帧）", "实测 " .. w_cell .. " 笔")
ok(w_bar >= 55, "★ 强压窗口里 selbar 被真的压住（≥55/60 帧）", "实测 " .. w_bar .. " 笔")
ok(w_tpl >= 55, "★ 强压窗口里 tpl-container 被真的压住", "实测 " .. w_tpl .. " 笔")

out("\n== [2] 窗口结束后的稳态：每帧写次数（目标 = 0）==")
step(60)   -- 越过窗口
-- ★ 先做一次"身份核对"：拿到写入的那些对象，到底是不是 adapter.controls 里缓存的那几个？
do
  local function walk(c, d, found)
    if c == nil or d > 6 then return end
    if c.name == "cell.1.1" then found[#found + 1] = c end
    for _, k in ipairs(c.__kids or {}) do walk(k, d + 1, found) end
  end
  local found = {}
  walk(tree[1], 0, found)
  out(string.format("  [身份核对] 树里叫 'cell.1.1' 的控件有 %.0f 个", #found))
  for i = 1, #found do
    out(string.format("     第 %.0f 个：visible=%s  __parent=%s  ==controls['cell.1.1']? %s",
      i, tostring(found[i].visible), tostring(found[i].__parent and found[i].__parent.name),
      tostring(found[i] == (adapter.controls and adapter.controls["cell.1.1"]))))
  end
  local bar = nil
  local function walkbar(c, d)
    if c == nil or d > 6 then return end
    if c.name == "selbar" then bar = c end
    for _, k in ipairs(c.__kids or {}) do walkbar(k, d + 1) end
  end
  walkbar(tree[1], 0)
  out(string.format("  [身份核对] 树里 'selbar'：visible=%s  ==controls['selbar']? %s  controls.visible=%s",
    tostring(bar and bar.visible), tostring(bar == (adapter.controls and adapter.controls["selbar"])),
    tostring(adapter.controls and adapter.controls["selbar"] and adapter.controls["selbar"].visible)))
end
local s_before = total_vis()
local s_cell0, s_bar0 = vis_of("cell.1.1"), vis_of("selbar")
out(string.format("  [稳态第一帧账本] _vis_wrote=%s  _vis_forcing=%s  _vis_frames=%s  _vis_until=%s  key=%s",
  tostring(cur._vis_wrote), tostring(cur._vis_forcing), tostring(cur._vis_frames),
  tostring(cur._vis_until), tostring(cur._vis_keynow)))
pcall(OnUpdate, 1 / 60)
out(string.format("  [再走一帧] _vis_wrote=%s  _vis_forcing=%s  _vis_frames=%s  _vis_until=%s  key=%s",
  tostring(cur._vis_wrote), tostring(cur._vis_forcing), tostring(cur._vis_frames),
  tostring(cur._vis_until), tostring(cur._vis_keynow)))
out(string.format("  [控件真实值] controls['cell.1.1'].visible=%s  controls['selbar'].visible=%s",
  tostring(adapter.controls["cell.1.1"] and adapter.controls["cell.1.1"].visible),
  tostring(adapter.controls["selbar"] and adapter.controls["selbar"].visible)))
-- ★ 打开栈追踪：稳态里到底是谁在写 selbar
C.traces = {}
TRACE_ON = true
step(60)
TRACE_ON = false
out("  ---- 稳态 60 帧里 selbar 的写入来源（栈，取前 4 层）----")
local tl = {}
for k, v in pairs(C.traces) do tl[#tl + 1] = { k = k, v = v } end
table.sort(tl, function(a, b) return a.v > b.v end)
for i = 1, math.min(6, #tl) do
  out(string.format("  ×%.0f %s", tl[i].v, tl[i].k))
end
out(string.format("  （这 60 帧 selbar 共写 %.0f 笔）", vis_of("selbar") - s_bar0))
step(540)  -- 再走完剩下的稳态
local s_cell = vis_of("cell.1.1") - s_cell0
local s_bar = vis_of("selbar") - s_bar0
local s_all = total_vis() - s_before
out(string.format("  稳态 600 帧：cell.1.1=%.0f  selbar=%.0f  **全部控件合计 %.0f 笔**（= %.4f 笔/帧）",
  s_cell, s_bar, s_all, s_all / 600))
ok(s_all == 0, "★★ 稳态每帧 SetVisible 写次数 = 0（硬指标）",
  string.format("实测 600 帧 %.0f 笔 ⇒ %.4f 笔/帧（改之前：33 笔/帧 = 19800 笔/600 帧）", s_all, s_all / 600))
ok(cur._vis_wrote == 0, "★ 上一帧账本 current._vis_wrote 也应为 0", "实测 " .. tostring(cur._vis_wrote))

out("\n== [3] 换屏（level → select）：必须重新开窗，把 selbar 压出来 ==")
ctrl.screen = "select"
ctrl.dirty = true
local t_bar0 = vis_of("selbar")
step(3)
local t_bar = vis_of("selbar") - t_bar0
out(string.format("  换屏后 3 帧：selbar 写 %.0f 笔（选关页目标 = 可见）", t_bar))
ok(t_bar >= 1, "★ 换屏后立刻开窗（selbar 被重新写）", "实测 " .. t_bar .. " 笔")
ok(adapter.controls["selbar"] ~= nil and adapter.controls["selbar"].visible == true,
  "★ 换屏后 selbar 真的变成 visible=true（选关页该显示）",
  "实测 visible=" .. tostring(adapter.controls["selbar"] and adapter.controls["selbar"].visible))
-- 再回关卡：窗口必须重新开 ⇒ selbar 必须被压回 false（这就是那个老 bug 的防线）
ctrl.screen = nil
ctrl.dirty = true
step(3)
ok(adapter.controls["selbar"].visible == false,
  "★★ 回关卡后 selbar 被压回 visible=false（**这正是 ensure_widgets 会抢的那个值**）",
  "实测 visible=" .. tostring(adapter.controls["selbar"].visible))

out("\n== [4] 模拟 ensure_widgets 抢值：换屏那一刻它把 selbar 设回 true ==")
-- 这是那个老 bug 的真实形状：别人在我们写完很久之后改回 true。
-- 我们靠"换屏 = 重新开窗"把它压回去。
ctrl.screen = "home"
ctrl.dirty = true
step(2)
adapter.controls["selbar"]:SetVisible(true)     -- ← 外部（ensure_widgets）抢值
local grabbed = adapter.controls["selbar"].visible
ctrl.screen = nil
ctrl.dirty = true
step(2)
out(string.format("  外部抢成 true 之后，换屏回来 2 帧内 selbar = %s（目标 false）",
  tostring(adapter.controls["selbar"].visible)))
ok(grabbed == true and adapter.controls["selbar"].visible == false,
  "★★ 外部抢过的值，在换屏（= 开新窗口）后被我们压回目标值",
  "抢值=" .. tostring(grabbed) .. " → 压回=" .. tostring(adapter.controls["selbar"].visible))

out("\n== [5] `%30` 节流位：现在真的每 30 帧跑一次了吗（旧 bug 是每 300 帧）==")
-- 用"格子底图已点亮"那条日志当探针：它只在 n>0 且 n 变化时打印，
-- 所以换成数 face 的 SetVisible 更直接 —— 数 90 帧里 face 被点亮的次数。
local face0 = vis_of("face")
step(90)
local face_n = vis_of("face") - face0
out(string.format("  90 帧里子控件 face 的 SetVisible = %.0f 笔", face_n))
out("  （改之前 `%30` 被 `%300` 套住 ⇒ 90 帧里最多 0～1 次；" ..
    "现在每 30 帧一轮 ⇒ 3 轮）")
ok(face_n >= 2, "★ `%30` 节流位已脱离 `%300`（90 帧里跑了多轮，不再是 0）",
  "实测 " .. face_n .. " 笔 face 写入 / 90 帧")

out("\n== [6] 对照基线（改之前的行为，写在注释里，不靠跑旧版本）==")
out("  改之前：33 个控件 × 每帧无条件写 = **33 笔/帧** = 1980 笔/秒（60fps）")
out(string.format("  改之后：强压窗口 %.0f 笔/60 帧，稳态 **%.2f 笔/帧**（其中**本段 0 笔**）",
  w_all, s_all / 600))

out("\n== [7] 稳态里剩余的写到底是谁（**本段之外**的既有代码）==")
do
  -- 稳态 30 帧，按控件名统计
  local d0 = {}
  for k, v in pairs(C.vis) do d0[k] = v end
  step(30)
  local delta = {}
  for k, v in pairs(C.vis) do delta[k] = v - (d0[k] or 0) end
  local tl = {}
  for k, v in pairs(delta) do if v > 0 then tl[#tl + 1] = { k = k, v = v } end end
  table.sort(tl, function(a, b) return a.v > b.v end)
  local tot = 0
  for _, t in ipairs(tl) do tot = tot + t.v end
  out(string.format("  稳态 30 帧共 %.0f 笔（%.2f 笔/帧），按控件：", tot, tot / 30))  for i = 1, math.min(10, #tl) do
    out(string.format("     %-16s %.0f 笔（%.2f 笔/帧）", tl[i].k, tl[i].v, tl[i].v / 30))
  end
  out("  ★ 本段（按屏同步）在这些帧里的写入 = **0**（见上面的 _vis_wrote=0）；")
  out("    剩下的是**渲染那一段**里 `bar:SetVisible(on_select)` 那处**既有的**每帧无条件写 ——")
  out("    它不在本次改造范围内（本次只改「按屏同步」这一段），但值得单独收一笔。")
end

out("\n== D. 不许有运行时报错 ==")
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

out(string.format("\n%.0f passed, %.0f failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
