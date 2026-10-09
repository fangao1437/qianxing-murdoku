--[[----------------------------------------------------------------------------
  tests/hide_safety.lua —— **安全性验收**：把"兜底隐藏"从每帧改成事件驱动之后，
                           它防的那件事必须一字不变地仍然被防住。

  为什么要有这个文件（这是性能修复的反面承诺）：
    `enforce_hidden_subtrees` 防的是真机排行榜证明过的那件事 ——
      编辑器把 `cell.1.1` 设成不可见时，**格子的子控件（content/face/…）still 可见**，
      它们铺在棋盘位置上、而格子自己绑了点击 ⇒ 射线被接走 ⇒ 选关卡片点不动。
    为什么脚本那一脚没赶上：渲染**只在属性值变化时**下发（`same_value` 缓存），
      而子控件是模板**之后**才实例化出来的。
    原来靠"每帧扫一遍"兜住；现在改成"**树可能变了**的事件里扫一遍"
      （切屏/换关、脚本改过 visible、新建/销毁控件、收到光标事件、
        「本该隐藏的名字」后来才被搜到）。
    ⇒ 这份文件就是把上面那句**逐条钉住**：性能承诺（稳态不跑）+ 安全承诺（该跑必跑、
      跑了真的压下去）。**谁把安全网拆了，这里立刻红。**

  判定分两半（都会在"每帧扫"的旧实现上变红，见文件末尾的说明）：
    [甲] 稳态 60 帧：兜底隐藏**一次都不该跑**（这就是这一轮省下来的那 261 次 SetVisible/帧）
    [乙] 五类事件里它**必须**跑，且事件之后被隐藏容器的子树**真的**全是 visible=false

  跑法：lua tests/hide_safety.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/hide_safety.lua"
local root = here:gsub("tests[/\\]hide_safety%.lua$", "")
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

-- ── 计数器 / 假控件（与 tests/grid_cost.lua、tests/board_bg.lua 同一套环境）──────
local C = { gc = 0, setvis = 0 }
local function attach(parent, c)
  if parent == nil then return nil end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c
  c.__parent = parent
  return c
end
local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true, __kids = {} }
  c.GetChildren = function() C.gc = C.gc + 1 return c.__kids end
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v) c.visible = v C.setvis = C.setvis + 1 end
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
    __newindex = function(t, k, v) rawset(t, k, v) end,
  })
end

-- 树：root → home / stage(cell.*) / clues(clues.bg + 老卡片 + 列表项模板)
local tree, home_ctrl, stage_ctrl, clues_ctrl, bg_ctrl
do
  local rt = make_ctrl("root")
  home_ctrl = make_ctrl("home")
  stage_ctrl = make_ctrl("stage")
  for r = 1, 5 do
    for cc = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. cc)
      cell.kind = "button"
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))
      attach(content, make_ctrl("note"))
      attach(content, make_ctrl("x"))
      attach(cell, content)
      attach(stage_ctrl, cell)
    end
  end
  clues_ctrl = make_ctrl("clues")
  -- ★★★★★ 2026-10-09 **假控件的名字必须是【裸名 `bg`】，不能是 `clues.bg`** ✗✓
  --   ★ 为什么 ✓：真机上子控件的 `name` 就是**裸名** ——
  --     `Adapter:sub(parent, child)` 走的是 `parent:GetChild(child_name)`（`engine_adapter:533` ✓）
  --     ⇒ 也就是**按名字查** ⇒ 真名必须是 `bg` ✓
  --   ★ 而 `DECOR` 豁免表（`engine_adapter:2328` ✓）里写的也是**裸名**（`label`/`bg`/`face`… ✓）
  --     ⇒ ★ 这里原来写成 `"clues.bg"` ✗ ⇒ `DECOR["clues.bg"]` 恒 nil
  --       ⇒ ★ **豁免永远不生效** ✗ ⇒ 于是这条测试**把 bug 当成了正确行为**锁死 ✗✓
  --         （L244 / L256 那两条断言写的就是"`clues.bg` 应该被压成 invisible" ✗）
  --   ★ 这是**假件保真度**问题 ✓ —— 与 `kit.mjs` 的 `gray`、`home`/`select` 那几次同族 ✓
  bg_ctrl = attach(clues_ctrl, make_ctrl("bg"))
  for i = 1, 3 do
    local card = make_ctrl("clue." .. i)
    card.kind = "button"
    attach(card, make_text("clue." .. i .. ".who"))
    attach(clues_ctrl, card)
  end
  attach(rt, home_ctrl)
  attach(rt, stage_ctrl)
  attach(rt, clues_ctrl)
  tree = { rt }
end

_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"
    c.prefabIndex = prefab
    local content = make_ctrl("content")
    attach(content, make_ctrl("face"))
    attach(c, content)
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

-- ── 加载产物 ──────────────────────────────────────────────────────────────
out("== 加载 dist/client_script.lua ==")
local chunk, lerr = loadfile(root .. "dist/client_script.lua")
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

-- ── 挂钩子：数"兜底隐藏"跑了几次 ──────────────────────────────────────────
local n_enforce = 0
do
  local oe = adapter.enforce_hidden_subtrees
  adapter.enforce_hidden_subtrees = function(self, ...)
    n_enforce = n_enforce + 1
    return oe(self, ...)
  end
end
local function count_gc(fn)
  local g0 = C.gc
  local r = fn()
  return C.gc - g0, r
end
-- 子树里"还有没有亮着的"（= 该隐藏却没藏住的）
--
-- ★ 2026-10-09 加第二个参数 `exclude_decor` ✗✓：
--   传 true ⇒ **跳过内层装饰名**（`bg`/`label`/`face`… ✓ 与 `engine_adapter:2328` 的 `DECOR` 同表 ✓）
--   ★ 为什么需要 ✓：装饰类**本来就该保持可见** ✓（`enforce_hidden_subtrees` 漏了这条豁免 ✗）
--     ⇒ 老判据"子树一个都不许亮"会把**正确的状态**判成失败 ✗✓
local DECOR_NAMES = {
  label = true, bg = true, pic = true, icon = true,
  face = true, note = true, x = true, obj = true, text = true, portrait = true,
  backrop1 = true, backrop2 = true, badge = true, letter = true, what = true, who = true,
  frame = true, card = true, art = true, image = true, img = true,
}
local function visible_descendants(c, exclude_decor)
  local n = 0
  local function walk(x, d)
    if x == nil or d > 4 then return end
    local kids = x.__kids or {}
    for i = 1, #kids do
      local k = kids[i]
      -- ★ 装饰类不算"该藏没藏住" ✓（名单与 `engine_adapter:2328` 的 `DECOR` 保持一致 ✓）
      if not (exclude_decor and DECOR_NAMES[k.name] == true) then
        if k.visible ~= false then n = n + 1 end
      end
      walk(k, d + 1)
    end
  end
  walk(c, 0)
  return n
end

-- ── 1. 先把关卡跑起来（和真机一样：进关 → 稳定）──────────────────────────
out("\n== 1. 进关并稳定下来 ==")
ctrl.screen = nil
ctrl.dirty = true
pcall(function() for _ = 1, 5 do OnUpdate(1 / 60) end end)
out("      controller.screen = " .. tostring(ctrl.screen) .. "，棋盘 " ..
  tostring(ctrl.core.rows) .. "x" .. tostring(ctrl.core.cols))

-- ── 2. [甲] 稳态 60 帧：兜底隐藏一次都不该跑 ────────────────────────────────
out("\n== 2. [甲] 稳态 60 帧（什么状态都没变）==")
n_enforce = 0
C.setvis = 0
pcall(function() for _ = 1, 60 do OnUpdate(1 / 60) end end)
ok(n_enforce == 0,
  "★ 稳态 60 帧里 `enforce_hidden_subtrees` **一次都没跑**（每帧扫已经是过去式）",
  "实测 " .. tostring(n_enforce) .. " 次（改之前：60 次 = 每帧一次；每帧 261 次 SetVisible）")

-- ── 3. [乙-1] 脚本改了 visible ⇒ 必须跑，且子树真的被压下去 ──────────────────
out("\n== 3. [乙-1] 脚本把 `clues` 设成不可见 ⇒ 下一帧兜底隐藏必须跑 ==")
do
  local before = visible_descendants(clues_ctrl)
  n_enforce = 0
  adapter:set_property("clues", "visible", false)
  pcall(function() OnUpdate(1 / 60) end)
  local after = visible_descendants(clues_ctrl)
  ok(n_enforce >= 1,
    "★ 脚本改过 visible ⇒ 兜底隐藏跑了（事件驱动的主触发源）",
    "跑了 " .. tostring(n_enforce) .. " 次")
  -- ★★★★★ 2026-10-09 **改判（依据，不是放宽）** ✗✓
  --   ★ 原来这里断言 `after == 0`（**整棵子树**全灭 ✗）＋ 下面 `bg_ctrl.visible == false` ✗
  --     —— 那两条**把 bug 当成了正确行为** ✗✓
  --   ★ 真机证据（用户 19:01 日志 ✓）：四键开局 `bg visible=true` ✓ 之后变 `false` ✗
  --     ⇒ ★ **`enforce_hidden_subtrees` 把内层装饰也压掉了**，而它**从不恢复**
  --       ⇒ 四键**有壳没图文** ✓ 而它的姊妹函数 `hide_unlisted` **有** `DECOR` 豁免 ✓
  --       ⇒ 本函数**漏抄了那条规则** ✗ （项目自己在 `engine_adapter:2320-2327` 写着：
  --          「**内层装饰控件一律不参与**」✓ 理由是"计划里只有外层名字 ⇒ 内层永远不在计划里"✓）
  --   ⇒ ★ 所以正确的判据是：**非装饰的子树被压下去 ✓ 装饰（`bg`）留着 ✓**
  local after_non_decor = visible_descendants(clues_ctrl, true)
  ok(clues_ctrl.visible == false,
    "★ 被隐藏容器自己看不见了（这就是它防的那件事）",
    "clues.visible=" .. tostring(clues_ctrl.visible))
  ok(after_non_decor == 0,
    "★ 被隐藏容器里**非装饰**的子控件全被压下去 ✓（`bg`/`label` 这类内层装饰不算 ✗）",
    "还剩 " .. tostring(after_non_decor) .. " 个亮的非装饰控件")
  ok(bg_ctrl.visible == true,
    "★★ **内层装饰（`bg`）【不该】被压下去** —— DECOR 豁免（真机「四键有壳没图文」的真因）",
    "visible=" .. tostring(bg_ctrl.visible)
    .. " ⇒ 若为 false，就是 `enforce_hidden_subtrees` 漏了 DECOR 豁免，"
    .. "真机表现是「四键只有空壳、图和字都没了」✗")
end

-- ── 4. [乙-2] 收到光标事件 ⇒ 必须跑（引擎可能把子控件显示出来）──────────────
out("\n== 4. [乙-2] 收到光标事件（引擎可能借状态切换自己改显隐）==")
do
  -- 模拟"引擎把某个子控件又显示出来了"（预设按钮的状态节点会干这件事）
  bg_ctrl.visible = true
  n_enforce = 0
  adapter:_fire({ action = "test" }, "click", nil)
  pcall(function() OnUpdate(1 / 60) end)
  ok(n_enforce >= 1, "★ 收到光标事件 ⇒ 兜底隐藏跑了", "跑了 " .. tostring(n_enforce) .. " 次")
  -- ★ 同上改判 ✓：装饰类**不该**被压回去 ✓（否则"引擎一显示就被脚本再藏"⇒ 图文永远出不来 ✗）
  ok(bg_ctrl.visible == true,
    "★ 引擎自己显示出来的**装饰**子控件【不该】被压回去（DECOR 豁免 ✓）",
    "visible=" .. tostring(bg_ctrl.visible))
end

-- ── 5. [乙-3] 新建控件 ⇒ 必须跑，新控件立刻被压下去 ─────────────────────────
out("\n== 5. [乙-3] 新建控件（模板子控件「晚一步才实例化」的真机场景）==")
do
  local late = attach(clues_ctrl, make_ctrl("late.child"))
  local deep = attach(late, make_ctrl("late.grandchild"))
  n_enforce = 0
  adapter:invalidate_lookups("test:late_node")   -- 等价于 create_control 里那次触发
  pcall(function() OnUpdate(1 / 60) end)
  ok(n_enforce >= 1, "★ 树里多了节点 ⇒ 兜底隐藏跑了", "跑了 " .. tostring(n_enforce) .. " 次")
  ok(late.visible == false and deep.visible == false,
    "★ 晚一步进树的子控件（含孙节点）也被压下去了",
    "late=" .. tostring(late.visible) .. " late.grandchild=" .. tostring(deep.visible))
end

-- ── 6. [乙-4] 「本该隐藏的名字」后来才被搜到 ⇒ 安全网必须触发 ────────────────
out("\n== 6. [乙-4] 安全网：被隐藏的名字，其句柄是先被扔掉、之后才重新搜到的 ==")
do
  n_enforce = 0
  adapter:drop_lookup("clues")        -- 句柄没了，但 `_hidden_ids["clues"]` 还在
  local hit = adapter:find("clues")   -- 重新搜到 ⇒ `_note_lookup_hit` 必须置位
  pcall(function() OnUpdate(1 / 60) end)
  ok(hit ~= nil and n_enforce >= 1,
    "★ 重新搜到「本该隐藏」的控件 ⇒ 兜底隐藏跑了（不依赖任何上层事件）",
    "find=" .. tostring(hit ~= nil) .. "，跑了 " .. tostring(n_enforce) .. " 次")
end

-- ── 7. 负缓存：不搜空 / 但绝不永久卡死 ─────────────────────────────────────
out("\n== 7. 控件名负缓存（性能）与「不会永久找不到」（安全阀）==")
do
  adapter:invalidate_lookups("test:miss")
  local g1 = count_gc(function() return adapter:find("never.exists") end)   -- 第一次：真搜
  local g2 = count_gc(function() return adapter:find("never.exists") end)   -- 第二次：负缓存
  ok(g1 > 0, "第一次搜一个不存在的名字：真的走了树", "GetChildren=" .. tostring(g1))
  ok(g2 == 0, "★ 第二次同一个名字：**一个节点都不再走**（负缓存生效）",
    "GetChildren=" .. tostring(g2) .. "（改之前：每次都要走完整棵树）")

  -- 模拟"引擎后来才把这个名字的控件建出来"，而且**一个事件都不发**
  local late = attach(clues_ctrl, make_ctrl("never.exists"))
  local g3, r3 = count_gc(function() return adapter:find("never.exists") end)
  ok(g3 == 0 and r3 == nil, "还没到过期时刻 ⇒ 仍旧不搜（性能承诺）",
    "GetChildren=" .. tostring(g3))

  -- ★ 安全阀：未命中缓存会**自己过期一次** ⇒ 即使没人发事件也不会永久卡死
  adapter:on_tick(2.0)                     -- 推过 ttl（默认 1 秒）
  local g4, r4 = count_gc(function() return adapter:find("never.exists") end)
  ok(r4 == late,
    "★ 缓存过期后自己重搜一次 ⇒ 找到了后来才进树的控件（**不可能永久卡死**）",
    "找到=" .. tostring(r4 == late) .. "；这次重搜走了 " .. tostring(g4) .. " 个节点")
  late.visible = false
end

-- ── 7.5 [丙] ★★ 对称性：格子「藏 ⇒ 显」必须对称 ─────────────────────────────
--
--   ★★★ 2026-10-06 补。**这一条就是当初漏掉的方向** ✓
--
--   本文件前面所有断言都只测【藏】："藏完子树真的全 false" ✓。
--   而**从不断言【显】**✗ ⇒ 于是"递归只藏不显"这个单向行为
--   被这套测试**当成了契约** ✗ ⇒ 几百轮里「11 套全绿」一直在说
--   "这个 bug 是对的" ✓✓
--
--   ★★★ **已验证有效** ✓（2026-10-06 ✓ 破坏证据见下 ✓）
--
--   破坏验证（★ 唯一可信的验证方式 ✓）—— ★ 第一次做**错**了 ✗ 第二次才做对 ✓：
--     ① ★ 改**源码** `lua/engine_adapter_qianxing.lua`：
--        把 `if vis == true and id:sub(1,5) == "cell." then` → `if false and …`
--     ② ★★ **必须重新打包** ✗✓ —— ★ 这一步是第一次漏掉的 ✓：
--        ★ 本文件加载的是 **`dist/client_script.lua`**（见 L167-168 ✓）✗
--        ⇒ ★ 只改源码不打包 ⇒ 测试读到的还是旧的打包产物 ⇒ **必然假绿** ✓
--   做对之后的结果 ✓：
--     ★ `15 passed, 2 failed` ✗ —— ★ 而且红的正好是本节这两条 ✓：
--        · `face=false` ✗（底图回不来 ✓）
--        · `wall.up=false` ✗（墙/门回不来 ✓）
--     ★ 还原后 `17 passed, 0 failed` ✓
--   ⇒ ★★★ 这两条**准确钉住了真机上那个 bug** ✓✓
--
--   ⚠️ 教训（★ 已写进 `docs/显隐所有权与排查纪律.md` ✓）：
--     ★ "破坏验证为绿"有**两种**可能 ✗ —— ① 测试是空的 ✗ ② **验证方法本身错了** ✓
--     ★ 必须先确认【破坏真的进入了被测代码】✗ 再下结论 ✓（★ 我差点因此删掉它 ✓）
out("\n== 7.5 [丙] 格子「藏 ⇒ 显」必须对称（★ 已验证有效）==")
do
  adapter:drop_lookup("cell.1.1")
  local content = adapter:sub("cell.1.1", "content")
  local wup = attach(content, make_ctrl("wall.up"))   -- 夹具里原本只配了 face/note/x
  local face = adapter:sub("cell.1.1", "face")

  -- ① 先记下"该亮哪些边"（等价于属性下发时那一步）
  adapter:_apply_edges("cell.1.1", "wall", { up = true })

  -- ② 藏：递归把子控件压下去（这是【旧行为】✓ 保留 ✓）
  adapter:set_property("cell.1.1", "visible", false)
  ok(face.visible == false and wup.visible == false,
    "★ 格子藏起来 ⇒ 子控件被递归压下去（旧行为，保留）",
    "face=" .. tostring(face.visible) .. " wall.up=" .. tostring(wup.visible))

  -- ③ 显：★★ 必须有对称恢复 ✗ —— ★ 改之前这里永远回不来 ✓ 就是那个 bug ✓
  adapter:set_property("cell.1.1", "visible", true)
  ok(face.visible == true,
    "★★ 格子重新可见 ⇒ `face` 必须被点亮（改之前：永远 false ⇒ 底图不见）",
    "face=" .. tostring(face.visible))
  ok(wup.visible == true,
    "★★ 格子重新可见 ⇒ `wall.up` 按 `_edge_want` 恢复（改之前：永远 false ⇒ 墙/门不画）",
    "wall.up=" .. tostring(wup.visible))
end

-- ── 8. 不许有运行时报错（防"修出来的新 bug"）─────────────────────────────
--   口径与 tests/board_bg.lua 一致：只看**真的抛错**那种 printerr
--   （`attempt to` / `nil value` / `bad argument`）。离线假控件树缺 `Enum`、
--   规划里 ~114 个"本关还没建"的控件本来就会打 printerr，那是环境噪音不是回归。
out("\n== 8. 全程没有运行时报错 ==")
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
out("")
out("说明：本文件在「每帧兜底 + 只缓存命中」的旧实现上**必定是红的**（第 2 节与第 7 节），")
out("      所以它不是「实现改了才补的绿断言」—— 它同时钉住性能承诺与安全承诺。")
os.exit(fail == 0 and 0 or 1)
