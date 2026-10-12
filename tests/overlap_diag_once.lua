--[[----------------------------------------------------------------------------
  tests/overlap_diag_once.lua —— ★ 判据：`相交诊断` 拿不到绝对坐标时"**探一次就记住结论**"

  ★★★ 起因（用户交由本轮处理的待办 ✓ 优化组 v205 交接 §一 P2 ✓）：
    ★ 真机日志每次都白跑一趟 ✗：
      「`本环境拿不到控件的绝对坐标（GetUIPos 不可用）`，跳过」✓
      ★ 而 `GetUIPos` 在**这个环境**永远拿不到 ⇒ ★ 这一趟**永远没有产出** ✓

  ★★★ 用户当年为什么要它 ✓（★ 不能删 ✗）：★ 用户反复报「**棋盘上有白色/紫色方块**」✓
    ★ 而规划文件是**多状态并集** ⇒ ★ 光看数据分不清"此刻屏幕上到底有谁" ✗
    ⇒ ★ 这条诊断是**唯一**能把"谁压在棋盘上"直接说出来的东西 ✓
    ★ 所以本轮选择"**探一次就记住结论**" ✓ —— ★ 不是删掉它 ✗✓

  ★★ 本文件钉三件事（★ 每一条都有反向对照 ✓）：
    ① 拿不到绝对坐标 ⇒ ★ 结论被记住（带**代数戳** ✓）
    ② **同一代内再调 ⇒ 不再重跑**（★ 判据 = `GetSizeDelta` 的调用次数不涨 ✓
       —— ★ 不读内部字段，**数引擎侧真的被调了几次** ✓ 无法自欺 ✓）
    ③ **换代之后 ⇒ 会再探一次** ✓（★ 防"永久缓存"→ 那正是本项目 `subs=false` 那个老 bug ✓）
       ＋ 反面：★ 换代前后**不能**把已有结论误当"还能用" ✗

  ★ 只读：本文件**不改任何生产源码** ✓
  ★ 跑法：lua tests/overlap_diag_once.lua
  ★ 前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/overlap_diag_once.lua"
local root = here:gsub("tests[/\\]overlap_diag_once%.lua$", "")
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

-- ── 记账点：引擎侧 `GetSizeDelta` 真的被调了几次（★ 唯一可信来源 ✓）────────────
local SIZE_READS = 0

local function attach(parent, c)
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end

local function make_ctrl(name)
  local c = {
    name = name, visible = true, active = true, __kids = {},
    interactable = true, raycastTarget = false,
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
  -- ★★ 记账点 ✓：本文件全部判据都建在它上面（★ 不读内部字段 ✓）
  c.GetSizeDelta = function() SIZE_READS = SIZE_READS + 1 return c.w or 0, c.h or 0 end
  c.SetAnchoredPosition = function(_, x, y) c.ax, c.ay = x, y end
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
  -- ★★★ 刻意**不**给 `GetUIPos` ✗ —— 这就是"本环境拿不到绝对坐标"那一条 ✓
  --   （★ 而 `board` 与它下面的子控件都拿不到 ⇒ 走 `return 0` 那一支 ✓）
  return c
end

local tree, REG = {}, {}
do
  local rt = make_ctrl("root")
  REG["root"] = rt
  -- ★ 名字对齐生产规划 ✓：★ `cfg.cells.parent` 实测 = **`stage`** ✗（★ 不是 `board` ✓）
  --   （★ `board` 是 `stage` 里的棋盘背景 ✓ 见 `ui_controller` 的 `push` ✓）
  --   ⚠️ 我第一版按 `board` 建树 ⇒ ★ `find("stage")` 落空 ⇒ **恒走 `return 0`** ✗
  --      而 `return 0` **不带标记** ✓ ⇒ ★ 套件红得"看起来像功能坏了"，其实是**夹具不对** ✓
  --      ⇒ ★ 教训与项目那份交接文同型 ✓：**夹具要先对齐生产** ✗✓
  for _, n in ipairs({ "topbar", "left", "tray", "clues", "board", "right",
                       "actions", "modal", "intro", "home", "select", "stage" }) do
    REG[n] = attach(rt, make_ctrl(n))
  end
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
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
  CursorEventType = {
    CursorClick = "CursorClick", CursorClickDown = "CursorClickDown",
    CursorClickUp = "CursorClickUp", CursorDrag = "CursorDrag",
  },
  KeyEventType = { KeyDown = "KeyDown", KeyUp = "KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
-- ★★★ 2026-10-12 **环境闸**（★ 与 `tests/bound_rearm.lua` / `dupe_dispatch.lua` 同一口径 ✓）
--   ★ 本项（相交诊断"探一次就记住结论" ✓）属于「v205 之后那批改动」✓ ⇒ ★ 已随 v212 回退 ✗
--   ★★ 没得测时 ✓：★ **明确说"没得测"** ✓ ★ 既不假绿 ✗ 也不假红 ✗
--   ★★★ 哨兵 ✓：★ 该项一旦被再引入 ⇒ 本套件**自动恢复全部 10 条断言** ✓
do
  local fh = io.open(SCRIPT_PATH, "rb")
  if fh == nil then out("  打不开产物 ⇒ 先跑 bundle"); os.exit(1) end
  local body = fh:read("a"); fh:close()
  if body:find("_overlap_diag_no_abs_gen", 1, true) == nil then
    out("  ⊘ 产物里没有「探一次就记住结论」（`_overlap_diag_no_abs_gen`）⇒ **本环境测不了**")
    out("  ⊘ 说明：该改动属于「v205 之后那批改动」⇒ 已随 v212 回退 ⇒ **当前没得测**")
    out("  ⊘ 它一旦被再引入，本套件的 10 条断言会自动恢复")
    os.exit(0)
  end
  out("  产物已含「探一次就记住结论」（`_overlap_diag_no_abs_gen` ✓）")
end

local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart)

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local adapter = cur.adapter
if adapter == nil or type(adapter.diagnose_overlap) ~= "function" then
  out("  adapter:diagnose_overlap 不在 ⇒ 量不到"); os.exit(2)
end
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 第一次探：真的去探了（读了一次棋盘尺寸）＋ 结论被记住
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 第一次 `diagnose_overlap()` ⇒ 真的探一次，并把结论记住 ==")
local gen0 = adapter._lookup_gen
do
  SIZE_READS = 0
  local r = nil
  pcall(function() r = adapter:diagnose_overlap() end)
  ok(SIZE_READS > 0, "第一次 ⇒ 真的去读了棋盘尺寸（探过了 ✓）",
    "GetSizeDelta 读了 " .. tostring(SIZE_READS) .. " 次")
  ok(r == 0, "拿不到绝对坐标 ⇒ 返回 0（★ 不硬比 ⇒ 不报假阳性 ✓）", "返回 " .. tostring(r))
  ok(adapter._overlap_diag_no_abs_gen == gen0,
    "★ 结论被记住，且**带着当前代数戳** ✓",
    "记的代号 = " .. tostring(adapter._overlap_diag_no_abs_gen) .. "（当前第 " .. tostring(gen0) .. " 代）")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [2] 同一代内再调 ⇒ ★ 不再重跑（判据 = 引擎侧读数不涨 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] 同一代里再调 ⇒ 必须【早退】（不再白跑 ✓）==")
do
  SIZE_READS = 0
  local r = nil
  pcall(function() r = adapter:diagnose_overlap() end)
  ok(SIZE_READS == 0, "★★ 同一代里第二次 ⇒ **一次引擎读都没有** ✓（白跑那趟被挡住了 ✓）",
    "GetSizeDelta 读了 " .. tostring(SIZE_READS) .. " 次（应为 0）")
  ok(r == 0, "★ 早退也返回 0（★ 与真跑那次的返回值一致 ⇒ 调用方看不出来变化 ✓）",
    "返回 " .. tostring(r))
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] 换一整代 ⇒ ★ 必须再探一次（防"永久缓存"✗ —— 那正是本项目老 bug 的形状 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] 换代之后 ⇒ 必须【再探一次】（★ 不许变成永久缓存 ✗）==")
do
  pcall(function() adapter:invalidate_lookups("screen=level test") end)
  local gen1 = adapter._lookup_gen
  ok(gen1 ~= gen0, "换代真的发生了（代数涨了 ✓）",
    "第 " .. tostring(gen0) .. " 代 ⇒ 第 " .. tostring(gen1) .. " 代")
  SIZE_READS = 0
  pcall(function() adapter:diagnose_overlap() end)
  ok(SIZE_READS > 0, "★★ 换代后**重新探了一次** ✓（★ 不是永久记住「拿不到」✗）",
    "GetSizeDelta 读了 " .. tostring(SIZE_READS) .. " 次（应 > 0）")
  ok(adapter._overlap_diag_no_abs_gen == gen1, "★ 结论的代数戳跟着更新 ✓",
    "记的代号 = " .. tostring(adapter._overlap_diag_no_abs_gen))
end

-- ════════════════════════════════════════════════════════════════════════════
-- [4] 正向对照：★ 一旦绝对坐标**能拿到** ⇒ 诊断必须真的跑起来 ✗
--     （★ 这条是"不许把功能档掉"的证明 ✓ —— 只记住"拿不到"、不记住"拿不到是因为坏了" ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [4] 正向对照：绝对坐标能拿到时，诊断必须真的跑（★ 不许把功能档掉 ✗）==")
do
  -- ★ 用**生产真正找的那个 id** ✓（`cfg.cells.parent` = `stage` ✓ 不写死 ✗）
  local parent_id = (adapter.cfg and adapter.cfg.cells and adapter.cfg.cells.parent) or "board"
  local board = REG[parent_id]
  ok(board ~= nil, "★ 夹具里能找到 `" .. tostring(parent_id) .. "`（★ 夹具对齐生产 ✓）",
    "REG['" .. tostring(parent_id) .. "'] = " .. tostring(board ~= nil))
  pcall(function() adapter:invalidate_lookups("screen=level again") end)   -- 新的一代
  -- ★ 现在把 `GetUIPos` 补上 ⇒ 模拟"换到一个能拿到绝对坐标的实现"
  board.GetUIPos = function() return { x = 800, y = 450 } end
  for _, k in ipairs(board.__kids) do
    k.GetUIPos = function() return { x = 805, y = 455 } end
  end
  local r = nil
  do
    local saved = _G.print
    _G.print = function() end
    pcall(function() r = adapter:diagnose_overlap() end)
    _G.print = saved
  end
  ok(r ~= nil and r >= 1,
    "★★ 拿得到绝对坐标 ⇒ **诊断真的跑了并数出相交控件** ✓（★ 功能没被档掉 ✓）",
    "返回 " .. tostring(r) .. " 个相交控件（应 ≥ 1）")
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
