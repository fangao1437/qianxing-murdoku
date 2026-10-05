--[[----------------------------------------------------------------------------
  tests/_wip/vis_write_count.lua —— 【探针】量「按屏同步运行时控件可见性」的**真实写次数**

  ★ 这个文件只做一件事：把 `lua/main.lua` 里那段**每帧**跑的
    「按屏同步运行时控件可见性」（`selbar` / `selbtn.1..6` / `tpl-container` / 25 个 `cell.*`）
    的**每帧 SetVisible 笔数**量出来，分三段：
      [1] 进关后 60 帧（强压窗口 `forcing`）—— 期望 **> 0**（每帧 33 笔）
      [2] 窗口结束后的稳态            —— 期望 **= 0**
      [3] 切屏后是否**重新武装**       —— 期望 **是**（重新出现写入）
    外加：`current._vis_keynow` 在切屏前后**跟着变**（核对 Round 70 那个笔误修复）。

  ── 为什么能直接读账本（而不是自己搭假引擎去数）────────────────────────────
    产线自己在 L1734–1743（该版本行号）把那一段的账记在 `current` 上：
        current._vis_wrote   = wrote     -- ★ 这一帧【真的写了几笔】（SetVisible 成功次数）
        current._vis_forcing = forcing   -- 这一帧是否在强压窗口内
        current._vis_frames  = fnow      -- 账本对应的帧号（★ 用它判"账本是不是这一帧的"）
        current._vis_until   = murdoku_vis_force_to
        current._vis_keynow  = murdoku_vis_key
    ⇒ 本探针**读账本**为主，**同时**用假控件自己的 `SetVisible` 计数器做**交叉验证**：
      两边的数字必须对得上，否则说明"账本记的不是这台假引擎"（口径无效）。

  ── 前两次探针栽的坑（本文件怎么绕开）──────────────────────────────────────
    ① `tests/perframe_throttle.lua` 的 A/B 两节：假树 32 个节点、`stage` 没挂到 `root` ⇒
       `find("cell.1.1")` 恒 nil ⇒ **根本走不到写** ⇒ 计数必然是 0 ✗（不能当证据）。
    ② 本探针**不赌 `find`**：把假控件**直接塞进 `adapter.controls`** ——
       产线 `setv()` 是**先读 `adapter.controls[nm]`（直接引用）、拿不到才退回 `find`** ✓
       ⇒ 只要塞进去，就一定走得到写 ✓。
       而且 `Adapter:find()` 自己也是**命中缓存优先**（`self.controls[name]`）⇒
       塞进 `controls` 之后 `find` 也会返回**同一个对象** ✓（这就是"双保险"）。
       两条路都验一遍（含"把缓存挖掉、看树能不能兜住"的负向对照）✓。

  ── 口径自检（防"假绿"，本文件的硬要求）────────────────────────────────────
    · **账本新鲜度**：每帧必须 `_vis_frames == 调用 OnUpdate 前的 current.frames`
      （产线在帧末才自增）；不新鲜 ⇒ 那一帧的 `_vis_wrote` **作废**，不当证据 ✓
    · **正向对照（篡改测试）**：稳态里手动把某个控件改成**错的值** ⇒ 下一帧必须
      **真的写回去** ⇒ 证明"稳态 0 笔"是"不需要写"，**不是"这条路根本没走到"** ✓
    · **切屏重新武装的判据**：先回到一个"所有目标值都已经满足"的状态，
      再回关卡 —— 此时**按值算一笔都不用写**；若仍出现 33 笔/帧 ⇒
      那只能是强压窗口重新开窗（`forcing`）干的 ✓✓

  跑法：lua tests/_wip/vis_write_count.lua
  前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
  只读：本文件**不改任何生产源码** ✓（只改运行期内存里的假引擎与适配器缓存）
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/vis_write_count.lua"
local root = here:gsub("tests[/\\]_wip[/\\]vis_write_count%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local out = print            -- 探针自己的输出（被测试代码的 print 会被劫持）

-- ── 劫持日志（只为了最后查"有没有运行时报错"，不改行为）────────────────────
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

-- ════════════════════════════════════════════════════════════════════════════
-- 假控件：每个都带 `visible` 字段 + `SetVisible`（★ 在里面计数、并更新 visible）
-- ════════════════════════════════════════════════════════════════════════════
local C = { vis = {}, traces = {}, trace_on = false }

local function bump(key, c)
  C.vis[key] = (C.vis[key] or 0) + 1
  if C.trace_on and debug and debug.traceback then
    local tb = debug.traceback("", 2)
    local got = {}
    for line in tb:gmatch("[^\n]+") do
      if line:find("client_script.lua", 1, true) then
        got[#got + 1] = (line:gsub("^%s+", ""))
        if #got >= 3 then break end
      end
    end
    if #got > 0 then
      local k = tostring(key) .. "  ←  " .. table.concat(got, " | ")
      C.traces[k] = (C.traces[k] or 0) + 1
    end
  end
end

local function attach(parent, c)
  if parent == nil or c == nil then return nil end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end

-- `__tag`（不可变的名字标签）用来记账：产线可能给控件改名，
-- 但"这一笔算在哪个名字上"要跟着我们登记的名字走 ✓
local function make_ctrl(name)
  local c = {
    name = name, kind = "container", visible = true, active = true,
    __kids = {}, __tag = name, __writes = 0,
  }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v)
    c.visible = v                       -- ★ 真值跟着写走（产线会**读回**这个字段）
    c.__writes = c.__writes + 1
    bump(c.__tag or tostring(c.name), c)
  end
  c.SetActive = function(_, v) c.active = v end
  c.SetSizeDelta = function(_, w, h) c.w, c.h = w, h end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
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

-- ── 假树（★ 与真机同构的那一层：`root → stage → 那 33 个控件`）──────────────
--    ★ 关键点：`stage` **必须挂到 `root` 上**（perframe_throttle 就是漏了这一行，
--      于是整棵子树在 root 上不可达 ⇒ find 全 nil ⇒ 计数恒 0 ✗）。
local REG = {}            -- 名字 → 本探针认定的那份控件（= 注入后 adapter.controls 里那一份）
local tree, stage_ctrl
do
  local rt = make_ctrl("root")
  attach(rt, make_ctrl("home"))
  attach(rt, make_ctrl("select"))
  local st = make_ctrl("stage")
  stage_ctrl = st
  attach(rt, st)          -- ★★ 这一行是"能不能走到写"的前提
  REG["root"] = rt
  REG["stage"] = st
  for r = 1, 5 do
    for c = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. c)
      cell.kind = "button"
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(st, cell)
      REG["cell." .. r .. "." .. c] = cell
    end
  end
  REG["selbar"] = attach(st, make_ctrl("selbar"))
  for i = 1, 6 do REG["selbtn." .. i] = attach(st, make_ctrl("selbtn." .. i)) end
  REG["tpl-container"] = attach(st, make_ctrl("tpl-container"))
  -- 其它常用容器：让渲染/诊断那条路也走得通（它们不是本次计量的对象）
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

-- ── 假引擎（与既有探针同一套，逐字照抄 + 少量补充）─────────────────────────
local instantiated = 0
local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    instantiated = instantiated + 1
    local c = make_ctrl("(未命名)")
    c.__tag = nil                      -- 还没名字 ⇒ 记账跟着"当时读到的新名字"走
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
  EnableUpdate = b,
  RegisterServerSignalHandler = b,
  RegisterCustomVariableChangedHandler = b,
  Invoke = b,
  GetParam = function() return nil end,
}
_G.Enum = nil

-- ════════════════════════════════════════════════════════════════════════════
-- ① 加载产物（先验"账本字段在不在"——否则量的是旧产物）
-- ════════════════════════════════════════════════════════════════════════════
local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")

local function count_plain(s, pat)
  local n, i = 0, 1
  while true do
    local a, e = s:find(pat, i, true)
    if a == nil then break end
    n = n + 1
    i = e + 1
  end
  return n
end

do
  local fh = io.open(SCRIPT_PATH, "rb")
  if fh == nil then
    out("  打不开产物 ⇒ 先跑 `lua tools/bundle_client_script.lua`"); os.exit(1)
  end
  local body = fh:read("a"); fh:close()
  local a1, e1 = body:find("current._vis_wrote", 1, true)
  out(string.format("  产物字节数 = %d，`current._vis_wrote` 出现 %d 次（首个偏移 %s）",
    #body, count_plain(body, "current._vis_wrote"), tostring(a1)))
  out(string.format("  `_vis_keynow` %d 次，`%% 300 == 0` %d 次（旧节流位；它只管「老的那一段」）",
    count_plain(body, "_vis_keynow"), count_plain(body, "% 300 == 0")))
  if a1 == nil then
    out("  ✗ 产物里没有 `_vis_wrote` 账本 ⇒ 这是旧产物，量不到 ⇒ 直接退出（不伪造数字）")
    os.exit(1)
  end
end

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
if cur == nil then
  out("  `Murdoku.current()` 是 nil ⇒ 开局没成功 ⇒ 量不到 ⇒ 直接退出（不伪造数字）")
  os.exit(2)
end
local ctrl, adapter = cur.controller, cur.adapter
if ctrl == nil or adapter == nil or type(adapter.controls) ~= "table" then
  out("  controller / adapter / adapter.controls 缺一个 ⇒ 量不到 ⇒ 直接退出")
  os.exit(2)
end
out(string.format("  开局后：level=%s  screen=%s  frames=%s  adapter.controls 里已有 %d 个名字",
  tostring(cur.level and (cur.level.id or cur.level.key or cur.level.name)),
  tostring(ctrl.screen), tostring(cur.frames), (function()
    local n = 0
    for _ in pairs(adapter.controls) do n = n + 1 end
    return n
  end)()))

-- ════════════════════════════════════════════════════════════════════════════
-- ② 口径核心：把假控件塞进 `adapter.controls`（+ `find` 双保险）
-- ════════════════════════════════════════════════════════════════════════════
out("\n== 0. 口径：假控件塞进 adapter.controls（产线先读它，读不到才退回 find）==")
local NEED = { "selbar" }
for i = 1, 6 do NEED[#NEED + 1] = "selbtn." .. tostring(i) end
NEED[#NEED + 1] = "tpl-container"
for r = 1, 5 do for c = 1, 5 do NEED[#NEED + 1] = "cell." .. r .. "." .. c end end
out(string.format("  这一段的控件名清单：%d 个（selbar + selbtn.1..6 + tpl-container + 25 个 cell）", #NEED))

local took_mine, already = 0, 0
for i = 1, #NEED do
  local nm = NEED[i]
  local obj = adapter.controls[nm]
  if obj == nil then
    obj = REG[nm]
    adapter.controls[nm] = obj       -- ★★ 这一句就是"走得到写"的关键
    took_mine = took_mine + 1
  else
    already = already + 1
  end
  REG[nm] = obj
end
out(string.format("  注入：%d 个是我塞进去的，%d 个是产线在 OnInit/OnStart 阶段自己建的（都保留产线那份）",
  took_mine, already))

local bad_ctrl, bad_find, bad_vis = {}, {}, {}
for i = 1, #NEED do
  local nm = NEED[i]
  if adapter.controls[nm] ~= REG[nm] then bad_ctrl[#bad_ctrl + 1] = nm end
  local viaFind = nil
  pcall(function() viaFind = adapter:find(nm) end)
  if viaFind ~= REG[nm] then bad_find[#bad_find + 1] = nm end
  local vok = pcall(function() return REG[nm].visible end)
  if not vok then bad_vis[#bad_vis + 1] = nm end
end
ok(#bad_ctrl == 0, "★ 33 个控件都在 `adapter.controls` 里、且就是我登记的那一份（直接引用这条路通）",
  #bad_ctrl == 0 and "(33/33)" or ("不符 " .. #bad_ctrl .. " 个：" .. table.concat(bad_ctrl, "/")))
ok(#bad_find == 0, "★ `adapter:find(nm)` 也返回**同一个对象**（命中缓存优先 ⇒ 双保险成立）",
  #bad_find == 0 and "(33/33)" or ("不符 " .. #bad_find .. " 个：" .. table.concat(bad_find, "/")))
ok(#bad_vis == 0, "★ 33 个控件的 `visible` 都读得到（产线「读回真值」那条分支在本口径下真的会执行）",
  #bad_vis == 0 and "(33/33)" or ("读不到 " .. #bad_vis .. " 个"))

-- 负向对照：把 controls 里的缓存挖掉，看**树**能不能兜住（证明"双保险"不是靠一句空话）
do
  local probe_names = { "tpl-container", "cell.3.3" }
  for i = 1, #probe_names do
    local nm = probe_names[i]
    local saved = adapter.controls[nm]
    adapter.controls[nm] = nil
    local via_tree = nil
    pcall(function() via_tree = adapter:find(nm) end)
    adapter.controls[nm] = saved
    out(string.format("  [双保险对照] 挖掉 controls['%s'] 后 find 仍返回同一对象？ %s（树兜底）",
      nm, tostring(via_tree == REG[nm])))
  end
end

-- ── 帧推进器：★ 每帧做"账本新鲜度"核对 ─────────────────────────────────────
--  ★★ 同时记一笔「按值算需不需要写」：调用 OnUpdate **之前**数一遍
--     "有多少个控件的 visible 已经 ≠ 当前屏幕的目标值"。
--     于是每一帧都能判：这一帧的写入是**值驱动**（本来就该写）还是**窗口驱动**（forcing）。
local RECS = {}
local errs = {}
local CUR_TARGET, CUR_TARGET_NAME = nil, "?"
local function need_now()
  if CUR_TARGET == nil then return -1 end
  local n = 0
  for i = 1, #NEED do
    local c = REG[NEED[i]]
    local want = CUR_TARGET[NEED[i]]
    -- want == nil ⇒ 这一屏的同步名单里**没有**这个控件（例如主页不管那 25 个 cell）⇒ 不计
    if c ~= nil and want ~= nil and c.visible ~= want then n = n + 1 end
  end
  return n
end
local function step1(tag)
  local f_before = cur.frames or 0
  local need = need_now()
  local okk, e = pcall(OnUpdate, 1 / 60)
  local rec = {
    tag = tag, f = f_before, f_after = cur.frames or 0,
    wrote = cur._vis_wrote, forcing = cur._vis_forcing,
    lf = cur._vis_frames, until_ = cur._vis_until, key = cur._vis_keynow,
    need = need, tgt = CUR_TARGET_NAME,
    err = (not okk) and tostring(e) or nil,
  }
  -- ★ 账本新鲜度：产线在**帧末**才自增 frames ⇒ 这一帧的账本号必须等于调用前的帧号
  rec.fresh = (rec.lf == f_before) and (rec.f_after == f_before + 1)
  if not okk then errs[#errs + 1] = tostring(e) end
  RECS[#RECS + 1] = rec
  return rec
end
local function step(n, tag)
  local last = nil
  for _ = 1, n do last = step1(tag) end
  return last
end

-- 开局探针：先确认 OnUpdate **真的**在推进（entry 的 `started` 若为 false，OnUpdate 会提前 return）
CUR_TARGET, CUR_TARGET_NAME = HOME_TARGET, "home"     -- 开局屏就是主页（OnStart 里 screen="home"）
do
  local f0 = cur.frames or 0
  local r = step1("boot")
  if (cur.frames or 0) == f0 then
    out("  ✗ 口径无效：OnUpdate 没有推进 `current.frames`（entry 的 `started` 还是 false）⇒ 退出")
    os.exit(3)
  end
  out(string.format("  开机探针：OnUpdate 一帧 frames %d → %d ✓ 这一帧账本=%s（_vis_forcing=%s）",
    f0, cur.frames, tostring(r.wrote), tostring(r.forcing)))
end

-- ── 统计与打印 ─────────────────────────────────────────────────────────────
local function pick(tag)
  local t = {}
  for i = 1, #RECS do if RECS[i].tag == tag then t[#t + 1] = RECS[i] end end
  return t
end
local function stat(t)
  local st = { n = #t, min = nil, max = nil, sum = 0, nz = 0, forcing = 0, fresh = 0, freq = {}, w = {} }
  for i = 1, st.n do
    local r = t[i]
    local w = tonumber(r.wrote)
    st.w[i] = w
    if w ~= nil then
      if st.min == nil or w < st.min then st.min = w end
      if st.max == nil or w > st.max then st.max = w end
      st.sum = st.sum + w
      if w ~= 0 then st.nz = st.nz + 1 end
      st.freq[w] = (st.freq[w] or 0) + 1
    end
    if r.forcing == true then st.forcing = st.forcing + 1 end
    if r.fresh then st.fresh = st.fresh + 1 end
  end
  st.avg = (st.n > 0) and (st.sum / st.n) or 0
  return st
end
local function fmt_st(st)
  return string.format("帧=%d  最小=%s  最大=%s  均值=%.3f  非零帧=%d/%d  窗口内帧=%d 账本新鲜=%d",
    st.n, tostring(st.min), tostring(st.max), st.avg, st.nz, st.n, st.forcing, st.fresh)
end
local function dist(st)
  local keys = {}
  for k in pairs(st.freq) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for i = 1, #keys do parts[#parts + 1] = tostring(keys[i]) .. "笔×" .. tostring(st.freq[keys[i]]) end
  return table.concat(parts, "  ")
end
local function snap_cnts()
  local t = {}
  for k, v in pairs(C.vis) do t[k] = v end
  return t
end
local function diff_cnts(a)
  local list = {}
  for k, v in pairs(C.vis) do
    local d = v - (a[k] or 0)
    if d ~= 0 then list[#list + 1] = { k = k, d = d } end
  end
  table.sort(list, function(x, y) return x.d > y.d end)
  return list
end
local function show_counts(a, topn, label)
  local list = diff_cnts(a)
  local total = 0
  local parts = {}
  for i = 1, #list do
    total = total + list[i].d
    if i <= (topn or 8) then parts[#parts + 1] = list[i].k .. "=" .. list[i].d end
  end
  out(string.format("  [假控件计数] %s：合计 %d 笔；前几个：%s", label, total, table.concat(parts, "  ")))
  return total
end
local function keyof(recs, which)
  local r = recs[which or 1]
  return r and tostring(r.key) or "(无)"
end

-- ── 关卡目标值表（判"按值算需不需要写"用）──────────────────────────────────
local LEVEL_TARGET = {}
LEVEL_TARGET["selbar"] = false
for i = 1, 6 do LEVEL_TARGET["selbtn." .. i] = false end
LEVEL_TARGET["tpl-container"] = false
for r = 1, 5 do for c = 1, 5 do LEVEL_TARGET["cell." .. r .. "." .. c] = true end end

-- 主页的目标值：`in_level = false` ⇒ 关卡内的 25 个 cell 这一屏**根本不在同步名单里**
--   （产线只在 `in_level` 时才 setv 那 25 个）⇒ 判"按值需不需要写"时它们不计入。
local HOME_TARGET = {}
HOME_TARGET["selbar"] = false
for i = 1, 6 do HOME_TARGET["selbtn." .. i] = false end
HOME_TARGET["tpl-container"] = false
HOME_TARGET.__skip_cells = true

local function need_by_value(target)
  local n, names = 0, {}
  for i = 1, #NEED do
    local nm = NEED[i]
    local c = REG[nm]
    local want = target[nm]
    if c ~= nil and want ~= nil and c.visible ~= want then
      n = n + 1
      if #names < 6 then names[#names + 1] = nm .. "=" .. tostring(c.visible) end
    end
  end
  return n, table.concat(names, "  ")
end

-- ★ 归因：这一帧的写入到底是"值驱动"还是"窗口驱动"
--   need0_wrote = 「按值算一个都不用写」却仍然发生写入的帧（⇒ 只能是 forcing 干的）
local function mix(recs)
  local m = { n = #recs, need0_wrote = 0, need0_wrote_sum = 0, needpos = 0, quiet = 0, sum = 0 }
  for i = 1, m.n do
    local r = recs[i]
    local w = tonumber(r.wrote) or 0
    m.sum = m.sum + w
    if r.need == 0 then
      if w > 0 then
        m.need0_wrote = m.need0_wrote + 1
        m.need0_wrote_sum = m.need0_wrote_sum + w
      else
        m.quiet = m.quiet + 1
      end
    elseif (r.need or 0) > 0 then
      m.needpos = m.needpos + 1
    end
  end
  return m
end
local function fmt_mix(m)
  return string.format("其中「按值算 0 需要写、却仍写了」%d 帧（%d 笔）；「按值算确实需要写」%d 帧；「0 需要写且 0 笔」%d 帧",
    m.need0_wrote, m.need0_wrote_sum, m.needpos, m.quiet)
end

-- ════════════════════════════════════════════════════════════════════════════
-- ③ 分段跑帧
-- ════════════════════════════════════════════════════════════════════════════

-- 预备：在主页热身（让渲染/快照那条路先走顺）
out("\n== 预备：主页热身 12 帧（这一段的数字只用于对照）==")
ctrl.screen = "home"
ctrl.dirty = true
do
  local c0 = snap_cnts()
  step(12, "home.warm")
  local st = stat(pick("home.warm"))
  out("  " .. fmt_st(st) .. "（主页：屏幕上没有 25 个 cell，只有 selbar/selbtn/tpl 共 8 个目标）")
  out("      _vis_wrote 分布：" .. dist(st))
  out("      " .. fmt_mix(mix(pick("home.warm"))))
  show_counts(c0, 6, "主页热身")
end

-----------------------------------------------------------------------------
out("\n== [1] 进关（scr_now = level）→ 头 60 帧：强压窗口 forcing ==")
local before_level = snap_cnts()
CUR_TARGET, CUR_TARGET_NAME = LEVEL_TARGET, "level"
do
  local n_need, sample = need_by_value(LEVEL_TARGET)
  out(string.format("  进关前快照：按值算「需要写」的控件 = %d / %d %s",
    n_need, #NEED, (n_need > 0) and ("（样例：" .. sample .. "）") or "（全部已达目标值 ✓）"))
end
ctrl.screen = nil
ctrl.dirty = true
local r0 = step(1, "level.win")            -- ★ 第 1 帧也算窗口内
local win_until = r0.until_
out(string.format("  进关第一帧：frames=%s  _vis_wrote=%s  _vis_forcing=%s  _vis_until=%s  key=%s",
  tostring(r0.f), tostring(r0.wrote), tostring(r0.forcing), tostring(r0.until_), tostring(r0.key)))
step(59, "level.win")                      -- 窗口共 60 帧
step(60, "level.steady")                   -- 窗口之后的稳态
do
  local win = stat(pick("level.win"))
  local st = stat(pick("level.steady"))
  local lvl_all = pick("level.win")
  local srecs = pick("level.steady")
  for i = 1, #srecs do lvl_all[#lvl_all + 1] = srecs[i] end
  out("\n  ── 窗口内（应 = 进关后第 1..60 帧）──")
  out("  " .. fmt_st(win))
  out("      _vis_wrote 分布：" .. dist(win))
  out("      " .. fmt_mix(mix(pick("level.win"))))
  out("      前 8 帧逐帧：" .. (function()
    local p = {}
    for i = 1, math.min(8, #lvl_all) do
      p[#p + 1] = string.format("f%s→%s", tostring(lvl_all[i].f), tostring(lvl_all[i].wrote))
    end
    return table.concat(p, "  ")
  end)())
  out("      边界 4 帧（窗口尾/稳态头）：" .. (function()
    local p = {}
    for i = 57, math.min(64, #lvl_all) do
      p[#p + 1] = string.format("f%s→%s(forcing=%s)", tostring(lvl_all[i].f),
        tostring(lvl_all[i].wrote), tostring(lvl_all[i].forcing))
    end
    return table.concat(p, "  ")
  end)())
  out("\n  ── 稳态（窗口后的 60 帧）──")
  out("  " .. fmt_st(st))
  out("      _vis_wrote 分布：" .. dist(st))
  out("      " .. fmt_mix(mix(pick("level.steady"))))
  out("  假控件侧交叉验证：" .. tostring(show_counts(before_level, 6, "进关 120 帧合计")))
  local m_win = mix(pick("level.win"))
  ok(m_win.need0_wrote >= 50,
    "★★ 窗口里绝大多数帧是「按值算一个都不用写、却仍然写了」（⇒ 写入是**窗口驱动**，不是值驱动）",
    string.format("%d/60 帧，合计 %d 笔", m_win.need0_wrote, m_win.need0_wrote_sum))
  ok(win.fresh == win.n, "★ 账本新鲜度：窗口内每一帧的 `_vis_frames` 都等于该帧帧号（账本是这一帧的）",
    string.format("%d/%d", win.fresh, win.n))
  ok(st.fresh == st.n, "★ 账本新鲜度：稳态每一帧也新鲜", string.format("%d/%d", st.fresh, st.n))
  ok(win.min ~= nil and win.min > 0,
    "【验收 1】强压窗口内每帧 `_vis_wrote` > 0（范围/典型值见上表）",
    string.format("min=%s max=%s 均值=%.3f（33 个控件 ⇒ 满额 33 笔/帧）",
      tostring(win.min), tostring(win.max), win.avg))
  ok(win.forcing == win.n, "★ 窗口内 `_vis_forcing` 恒为 true",
    string.format("%d/%d", win.forcing, win.n))
  ok(st.max == 0, "【验收 2】稳态每帧 `_vis_wrote` = 0",
    string.format("60 帧合计 %d 笔；max=%s", (function()
      local s = 0
      for i = 1, st.n do s = s + (st.w[i] or 0) end
      return s
    end)(), tostring(st.max)))
  ok(st.forcing == 0, "★ 稳态 `_vis_forcing` 恒为 false", string.format("窗口外 %d/%d", st.n - st.forcing, st.n))
  out(string.format("  [窗口账] _vis_until=%s ⇒ 窗口覆盖到帧 %s（进关第 1 帧是 %s）",
    tostring(win_until), tostring(win_until), tostring(r0.f)))
end

-----------------------------------------------------------------------------
out("\n== [2] 正向对照（防「假绿」）：稳态里手动把值改错 ⇒ 下一帧必须真的写回去 ==")
do
  -- ⚠️ 避开 `%300 == 0` 那一帧（旧的那一段也会写这几组控件，会干扰归因）
  if ((cur.frames or 0) % 300) == 0 then step(1, "skip300") end
  local function tamper(nm, wrong)
    REG[nm].visible = wrong
    local f_before = cur.frames or 0
    local r = step1("tamper")
    local now = REG[nm].visible
    out(string.format("  篡改 %s → %s；下一帧（f=%s，%s300）_vis_wrote=%s，回读 visible=%s",
      nm, tostring(wrong), tostring(f_before), ((f_before % 300) == 0) and "★是" or "非",
      tostring(r.wrote), tostring(now)))
    return r, now
  end
  local r1, v1 = tamper("tpl-container", true)     -- 目标 false
  ok(tonumber(r1.wrote) ~= nil and tonumber(r1.wrote) >= 1 and v1 == false,
    "★ 篡改 `tpl-container`（目标 false）后 1 帧内被写回 false",
    string.format("_vis_wrote=%s visible=%s", tostring(r1.wrote), tostring(v1)))
  local r2, v2 = tamper("cell.1.1", false)         -- 目标 true（关卡内）
  ok(tonumber(r2.wrote) ~= nil and tonumber(r2.wrote) >= 1 and v2 == true,
    "★ 篡改 `cell.1.1`（目标 true）后 1 帧内被写回 true",
    string.format("_vis_wrote=%s visible=%s", tostring(r2.wrote), tostring(v2)))
  local r3, v3 = tamper("selbar", true)            -- 目标 false（关卡内）
  ok(tonumber(r3.wrote) ~= nil and tonumber(r3.wrote) >= 1 and v3 == false,
    "★ 篡改 `selbar`（目标 false）后 1 帧内被写回 false",
    string.format("_vis_wrote=%s visible=%s", tostring(r3.wrote), tostring(v3)))
  -- 复原后再跑几帧：必须回到 0（否则"稳态 0 笔"这句话就不成立）
  step(10, "after.tamper")
  local st = stat(pick("after.tamper"))
  out("  篡改复原后再跑 10 帧： " .. fmt_st(st))
  ok(st.max == 0, "★ 篡改复原后立刻回到稳态 0 笔/帧（稳态 0 是「不需要写」，不是「走不到」）",
    "max=" .. tostring(st.max))
end

-----------------------------------------------------------------------------
out("\n== [3] 切屏：换到主页（会重新开窗）→ 再回关卡 ==")
do
  -- 换屏前先算一次：主页这一屏的目标值，此刻是不是**全都已经满足**了 ✓
  local n_need, sample = need_by_value(HOME_TARGET)
  out(string.format("  切到主页前快照：按值算「需要写」的控件 = %d / 8 %s",
    n_need, (n_need > 0) and ("（样例：" .. sample .. "）") or "（全部已达目标值 ✓ ⇒ 这一屏本该一笔都不写）"))
end
CUR_TARGET, CUR_TARGET_NAME = HOME_TARGET, "home"
ctrl.screen = "home"
ctrl.dirty = true
local r_home = step(1, "home.2")           -- ★ 第 1 帧也算窗口内
out(string.format("  切到主页第一帧：frames=%s _vis_wrote=%s _vis_forcing=%s _vis_until=%s key=%s",
  tostring(r_home.f), tostring(r_home.wrote), tostring(r_home.forcing),
  tostring(r_home.until_), tostring(r_home.key)))
step(69, "home.2")
do
  local st = stat(pick("home.2"))
  local m = mix(pick("home.2"))
  out("  主页 70 帧： " .. fmt_st(st))
  out("      _vis_wrote 分布：" .. dist(st))
  out("      " .. fmt_mix(m))
  ok(r_home.forcing == true, "★ 切屏（level → home）后重新开窗（forcing=true）",
    "第一帧 forcing=" .. tostring(r_home.forcing))
  ok(tonumber(r_home.wrote) ~= nil and tonumber(r_home.wrote) > 0,
    "★ 切屏后立刻出现写入", "第一帧 _vis_wrote=" .. tostring(r_home.wrote))
  ok(m.need0_wrote >= 50,
    "★★ 主页窗口里绝大多数帧是「按值算 0 需要写、却仍然写」⇒ 这些写入**只能是重新开窗带来的**",
    string.format("%d/70 帧，合计 %d 笔（8 个控件 × 60 帧 ≈ 480 为满额）",
      m.need0_wrote, m.need0_wrote_sum))
  local steady_home = {}
  local recs = pick("home.2")
  for i = 61, #recs do steady_home[#steady_home + 1] = recs[i] end
  local sh = stat(steady_home)
  ok(sh.n > 0 and sh.max == 0, "★ 主页稳态（窗口之后的那些帧）也是 0 笔/帧", "max=" .. tostring(sh.max))
  out(string.format("  [key] 主页 key = %s（关卡 key = %s）", keyof(pick("home.2")), tostring(r0.key)))
end

-- ★★ 决定性一测：回关卡那一刻，先把"按值算需不需要写"逐帧记下来（`need`），
--    再看每一帧实际写了几笔 —— 两者一比，就知道这些写入是**值**逼出来的还是**窗口**逼出来的。
out("\n== [4] 回关卡（决定性）：逐帧把「按值算需不需要写」和「实际写了几笔」并排量 ==")
do
  local n_need, sample = need_by_value(LEVEL_TARGET)
  out(string.format("  回关卡前快照：按值算「需要写」的控件 = %d / %d %s",
    n_need, #NEED, (n_need > 0) and ("（样例：" .. sample .. "）") or "（全部已达目标值 ✓）"))
  local before_rearm = snap_cnts()
  CUR_TARGET, CUR_TARGET_NAME = LEVEL_TARGET, "level"
  ctrl.screen = nil
  ctrl.dirty = true
  local r = step(1, "level.rearm")          -- ★ 第 1 帧也算窗口内
  out(string.format("  回关卡第一帧：frames=%s _vis_wrote=%s _vis_forcing=%s _vis_until=%s key=%s",
    tostring(r.f), tostring(r.wrote), tostring(r.forcing), tostring(r.until_), tostring(r.key)))
  step(59, "level.rearm")
  step(60, "level.rearm.steady")
  local win = stat(pick("level.rearm"))
  local st = stat(pick("level.rearm.steady"))
  out("  ── 回关卡后 60 帧（窗口）──")
  out("  " .. fmt_st(win))
  out("      _vis_wrote 分布：" .. dist(win))
  out("      " .. fmt_mix(mix(pick("level.rearm"))))
  out("  ── 之后的稳态 60 帧 ──")
  out("  " .. fmt_st(st))
  out("      _vis_wrote 分布：" .. dist(st))
  out("      " .. fmt_mix(mix(pick("level.rearm.steady"))))
  show_counts(before_rearm, 6, "回关卡 120 帧合计")
  local m = mix(pick("level.rearm"))
  out(string.format("  [逐帧对照] 回关卡前按值算需要写 %d 个；窗口里「按值算 0 需要写」的帧仍有 %d 帧在写（共 %d 笔）",
    n_need, m.need0_wrote, m.need0_wrote_sum))
  ok(m.need0_wrote >= 50,
    "★★ 回关卡窗口里绝大多数帧是「按值算 0 需要写、却仍然写」⇒ 只能是强压窗口重新武装（不是值逼出来的）",
    string.format("%d/60 帧，合计 %d 笔（回关卡前按值算需要写 = %d 个，只够解释第 1 帧）",
      m.need0_wrote, m.need0_wrote_sum, n_need))
  ok(win.min ~= nil and win.min > 0,
    "【验收 3】切屏回来后**重新武装**：窗口内照旧每帧写（哪怕值早已正确）",
    string.format("min=%s max=%s 均值=%.3f", tostring(win.min), tostring(win.max), win.avg))
  ok(win.forcing == win.n, "★ 回关卡窗口内 `_vis_forcing` 恒 true", string.format("%d/%d", win.forcing, win.n))
  ok(st.max == 0, "★ 回关卡稳态又回到 0 笔/帧", "max=" .. tostring(st.max))
end

-----------------------------------------------------------------------------
out("\n== [5] `current._vis_keynow` 是否跟着切屏变（核对 Round 70 的笔误修复）==")
do
  local keys, order = {}, {}
  for i = 1, #RECS do
    local k = tostring(RECS[i].key)
    if keys[k] == nil then
      keys[k] = { n = 0, first = RECS[i].f, tag = RECS[i].tag }
      order[#order + 1] = k
    end
    keys[k].n = keys[k].n + 1
  end
  out("  出现过的 key（按首次出现）：")
  for i = 1, #order do
    local k = order[i]
    out(string.format("    %-14s 共 %4d 帧，首次在 f=%s（tag=%s）",
      "[" .. k .. "]", keys[k].n, tostring(keys[k].first), tostring(keys[k].tag)))
  end
  local n_nil = 0
  for i = 1, #RECS do if RECS[i].key == nil then n_nil = n_nil + 1 end end
  ok(n_nil == 0, "★ `_vis_keynow` **从不为 nil**（若它是 nil ⇒ Round 70 的笔误还在）",
    string.format("nil 帧 = %d / %d", n_nil, #RECS))
  ok(keys["level|nil"] ~= nil or keys["level|"] ~= nil or (function()
      for k in pairs(keys) do if k:sub(1, 5) == "level" then return true end end
      return false
    end)(), "★ 关卡内的 key 以 `level|` 开头", "")
  local has_home, has_select = false, false
  for k in pairs(keys) do
    if k:sub(1, 4) == "home" then has_home = true end
    if k:sub(1, 6) == "select" then has_select = true end
  end
  ok(has_home, "★ 主页的 key 以 `home|` 开头（说明 key 跟着 (屏幕|关卡) 走）", "")
  out("  ⇒ 结论：key 在 level / home 之间**确实跟着变**（本轮没测 select 屏，因为不必要）")
end

-----------------------------------------------------------------------------
out("\n== [6] 交叉验证：账本笔数 vs 假控件自己数到的笔数 ==")
do
  -- 稳态（level.steady / after.tamper / level.rearm.steady 之外）不写 ⇒ 两边都该是 0；
  -- 窗口内两边都必须 = 33 笔/帧 × 帧数（假控件那边还包含"别人写的"，所以只做上界核对）
  local f0 = nil
  for i = 1, #RECS do
    if RECS[i].tag == "level.win" then f0 = i; break end
  end
  if f0 ~= nil then
    local ledger = 0
    for i = f0, f0 + 59 do ledger = ledger + (tonumber(RECS[i].wrote) or 0) end
    out(string.format("  进关头 60 帧：账本合计 %d 笔（33×60 = 1980 为满额）", ledger))
  end
  local stale = 0
  for i = 1, #RECS do if not RECS[i].fresh then stale = stale + 1 end end
  ok(stale == 0, "★★ 全程没有一帧的账本是「陈旧」的（否则那些 0 都不能当证据）",
    string.format("陈旧帧 = %d / %d", stale, #RECS))
end

-----------------------------------------------------------------------------
out("\n== [7] 稳态里「还有没有别人在写」（归因，顺手量）==")
do
  C.traces = {}
  C.trace_on = true
  local c0 = snap_cnts()
  local before = #RECS
  step(60, "trace")
  C.trace_on = false
  local total = show_counts(c0, 8, "稳态 60 帧（含所有写入者）")
  out(string.format("  其中产线账本 `_vis_wrote` 合计 = %d 笔", (function()
    local s = 0
    for i = before + 1, #RECS do s = s + (tonumber(RECS[i].wrote) or 0) end
    return s
  end)()))
  if total == 0 then
    out("  ⇒ 稳态 60 帧里**整棵假树上一次 SetVisible 都没有**（不只是那 33 个）")
  else
    local list = {}
    for k, v in pairs(C.traces) do list[#list + 1] = { k = k, v = v } end
    table.sort(list, function(a, b) return a.v > b.v end)
    for i = 1, math.min(6, #list) do
      out(string.format("    ×%-4d %s", list[i].v, list[i].k))
    end
  end
end

-----------------------------------------------------------------------------
out("\n== [8] 不许有运行时报错 ==")
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
  ok(#errs == 0, "OnUpdate 每一次调用都没抛错",
    #errs == 0 and string.format("(0 次 / 共 %d 帧)", #RECS) or ("第一次：" .. tostring(errs[1])))
  out(string.format("  （假引擎侧：InstantiateClientUIControl 被调用 %d 次）", instantiated))
end

-----------------------------------------------------------------------------
-- 结论表
-----------------------------------------------------------------------------
out("\n================ 结论表 ================")
do
  local win = stat(pick("level.win"))
  local st = stat(pick("level.steady"))
  local rw = stat(pick("level.rearm"))
  local rs = stat(pick("level.rearm.steady"))
  local hw = stat(pick("home.2"))
  local function line(label, stt)
    out(string.format("  %-34s %s", label, fmt_st(stt)))
    out(string.format("  %-34s 分布：%s", "", dist(stt)))
  end
  out("  【1】进关头 60 帧（强压窗口）")
  line("      账本 _vis_wrote", win)
  out("          " .. fmt_mix(mix(pick("level.win"))))
  out("  【2】窗口之后稳态 60 帧")
  line("      账本 _vis_wrote", st)
  out("          " .. fmt_mix(mix(pick("level.steady"))))
  out("  【3】切屏(→主页)：重新武装（主页这一屏的 8 个目标值本来就已经满足）")
  line("      账本 _vis_wrote（70 帧）", hw)
  out("          " .. fmt_mix(mix(pick("home.2"))))
  out("  【3b】再回关卡：又武装一次")
  line("      窗口 60 帧", rw)
  line("      之后稳态 60 帧", rs)
  out("          " .. fmt_mix(mix(pick("level.rearm"))))
  out(string.format("  _vis_keynow 全程 %d 帧，取值：%s", #RECS, (function()
    local seen, p = {}, {}
    for i = 1, #RECS do
      local k = tostring(RECS[i].key)
      if not seen[k] then seen[k] = true; p[#p + 1] = k end
    end
    return table.concat(p, "  |  ")
  end)()))
  out("========================================")
end

out(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
  out("⚠️ 有断言不成立 ⇒ 上面的数字就是实测值，**不要**为了让它变绿去改口径。")
end
os.exit(fail == 0 and 0 or 1)
