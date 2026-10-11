--[[----------------------------------------------------------------------------
  tests/_wip/cursor_latch_count.lua —— 【探针】量 `enable_cursor` 的收敛闩锁

  ★ 量什么（2026-10-11 性能优化）：
     `Adapter:enable_cursor` 原来被 `main.lua` 的 `% 20 == 0` **每 20 帧调一次、永不停止** ✗
       每趟成本：12 次 `find` ＋ **12 笔无条件 `showCursor = true` 引擎写** ✗
                 ＋ 回读那段 12 次 `find` ＋ 每容器最多 4 次 `pcall` 属性读 ＋ `table.concat` ✓
     ⇒ 约 **3 趟/秒，烧到关服** ✓
     ★ 现在照抄 `enable_raycast` 那套：**收敛即停**（`_cursor.done`）＋
       **换屏/换关重新武装**（`Adapter:rearm_cursor`）✓

  ★ 口径（防"假绿"）：
     · 记账记在**假控件自己**的元表上（不是读产线内部变量）⇒ 无法自欺 ✓
     · **正向对照**：收敛之后再**弄坏一个容器的 showCursor** ⇒
       必须**重新武装**并写回去 ⇒ 证明"0 笔"是"不需要写"，不是"没走到" ✓
     · 只读：本文件**不改任何生产源码** ✓

  跑法：lua tests/_wip/cursor_latch_count.lua
  前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/cursor_latch_count.lua"
local root = here:gsub("tests[/\\]_wip[/\\]cursor_latch_count%.lua$", "")
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

-- ── 记账：`showCursor` 的**引擎写**次数（只在值真的变化时算一笔真写）──────────
local W = { writes = 0, by_name = {}, reads = 0 }
local function attach(parent, c)
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
  c.SetVisible = function(_, v) c.visible = v end
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
  -- ★ `showCursor` 走元表 ⇒ **能数出"产线真的写了几笔"** ✓
  --   ⚠️ 必须区分"写同一个值"与"写不同的值"：
  --     产线现在是**无条件写**（`ctrl.showCursor = true`）✗
  --     ⇒ 收敛前每趟 12 笔 ✓；收敛后**一笔都不该有**（因为函数在入口就 return 了 ✓）
  local store = { showCursor = false }
  return setmetatable(c, {
    __index = function(_, k)
      if k == "showCursor" then W.reads = W.reads + 1 return store.showCursor end
      return nil
    end,
    __newindex = function(t, k, v)
      if k == "showCursor" then
        store.showCursor = v
        W.writes = W.writes + 1
        W.by_name[t.name] = (W.by_name[t.name] or 0) + 1
      else
        rawset(t, k, v)
      end
    end,
  })
end

-- ════════════════════════════════════════════════════════════════════════════
-- 假树：把 CURSOR_CONTAINERS 那 12 个名字**全部**建出来（否则永远不收敛 ✓）
-- ════════════════════════════════════════════════════════════════════════════
local NAMES = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal", "intro", "home", "select",
}
local REG, tree = {}, {}
do
  local rt = make_ctrl("root")
  REG["root"] = rt
  for i = 2, #NAMES do
    REG[NAMES[i]] = attach(rt, make_ctrl(NAMES[i]))
  end
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"; c.prefabIndex = prefab
    attach(parent, c); return c
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

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then
  out("  加载失败：" .. tostring(lerr) .. "　→ 先跑 `lua tools/bundle_client_script.lua`")
  os.exit(1)
end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart)

local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 量不到"); os.exit(2) end
local adapter = cur.adapter
if adapter == nil or type(adapter.enable_cursor) ~= "function" then
  out("  adapter:enable_cursor 不在 ⇒ 量不到"); os.exit(2)
end

-- ★ 把 12 个假容器塞进 `adapter.controls` ⇒ 让 `find` 直接命中（不赌树遍历 ✓）
for i = 1, #NAMES do adapter.controls[NAMES[i]] = REG[NAMES[i]] end

-- 先验"闩锁字段在不在"——否则量的是旧产物
do
  local fh = io.open(SCRIPT_PATH, "rb"); local body = fh:read("a"); fh:close()
  if body:find("_cursor", 1, true) == nil or body:find("rearm_cursor", 1, true) == nil then
    out("  ✗ 产物里没有 `_cursor` / `rearm_cursor` ⇒ 这是旧产物 ⇒ 量不到（不伪造数字）")
    os.exit(1)
  end
  out("  产物已含收敛闩锁（`_cursor` / `rearm_cursor` 都在 ✓）")
end
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 收敛：连调 6 趟，之后应"一笔不写"
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 连调 6 趟：前 3 趟写、之后收敛（一笔不写）==")
local per = {}
for k = 1, 6 do
  local before = W.writes
  pcall(function() adapter:enable_cursor() end)
  per[k] = W.writes - before
  out(string.format("  第 %d 趟：showCursor 写 %d 笔", k, per[k]))
end
ok(per[1] >= 12, "第 1 趟把 12 个容器都打开了", "写 " .. tostring(per[1]) .. " 笔")
ok(per[4] == 0 and per[5] == 0 and per[6] == 0,
  "★★ 连记 3 趟后**收敛**：第 4~6 趟**【一笔都不写】**（原来每 20 帧烧 12 笔）",
  string.format("第4=%d 第5=%d 第6=%d", per[4], per[5], per[6]))

-- ════════════════════════════════════════════════════════════════════════════
-- [2] 收敛后**零成本**：再调 20 趟也不写、且不读控件
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] 收敛后再调 20 趟：应当零写 + 零读（入口就 return）==")
do
  local w0, r0 = W.writes, W.reads
  for _ = 1, 20 do pcall(function() adapter:enable_cursor() end) end
  local dw, dr = W.writes - w0, W.reads - r0
  out(string.format("  20 趟合计：写 %d 笔，读 %d 次", dw, dr))
  ok(dw == 0, "★ 收敛后 20 趟【零写】", "写 " .. tostring(dw) .. " 笔")
  ok(dr == 0, "★★ 收敛后 20 趟【零读】⇒ 一次树都不走（这是与 enable_raycast 同一档的早停）",
    "读 " .. tostring(dr) .. " 次")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [3] 正向对照：弄坏一个容器的 showCursor + 重新武装 ⇒ 必须写回去
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] 正向对照：弄坏 `home` 的 showCursor + `rearm_cursor` ⇒ 必须重新写 ==")
do
  -- 把 home 的 showCursor 直接改回 false（绕过记账 ⇒ 模拟"引擎把它重置了"）
  rawset(REG["home"], "showCursor", false)
  local w0 = W.writes
  pcall(function() adapter:enable_cursor() end)
  local still_zero = (W.writes - w0) == 0
  ok(still_zero,
    "★ 先证明「闩锁真的闩住了」：不重新武装的话，弄坏了也**不会**写（早停 ✓）",
    "写 " .. tostring(W.writes - w0) .. " 笔")

  -- 重新武装（换屏/换关时会走这条）
  local okr = pcall(function() adapter:rearm_cursor("探针：换屏") end)
  ok(okr, "`rearm_cursor` 可调用（换屏/换关那条路）", "")
  local w1 = W.writes
  pcall(function() adapter:enable_cursor() end)
  local wrote = W.writes - w1
  ok(wrote > 0,
    "★★ 重新武装之后**真的重新写了**（⇒ 收敛不会让「新长出来的容器」漏掉 showCursor）",
    "写 " .. tostring(wrote) .. " 笔")
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
