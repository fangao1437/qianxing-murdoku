--[[----------------------------------------------------------------------------
  tests/entry_smoke.lua —— 离线跑「真机入口」，专抓那种把 OnInit 打崩的 bug

  为什么需要它（2026-09-26 真机事故）：
    入口里的 `check_canvas()` 用 `%d` 去格式化 `game.GetUICanvasSize()` 的返回值，
    而真机返回的是**浮点数**。Lua 5.3 的 `string.format("%d", 1600.0)` 直接抛
      bad argument #2 to 'format' (number has no integer representation)
    因为没包 pcall，**整个 OnInit 被打断** —— 适配器没建起来、配置全没生效，
    真机日志上表现成一大串「找不到头像卡容器 / 控件未找到」，
    看起来像"界面没搭好"，实际是被一行日志打崩的。

  这个测试用**假游戏环境**（画布尺寸故意返回浮点）把入口完整跑一遍：
    OnInit → OnStart → OnUpdate（含惰性重试到放弃）→ OnDestroy
  只要有任何一步抛错、或者没走到 "OnInit done"，它就失败。

  跑法：lua tests/entry_smoke.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/entry_smoke.lua"
local root = here:gsub("tests[/\\]entry_smoke%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

-- ⚠️ 下面要劫持全局 print/printerr 去收集「被测试代码」的日志，
--    所以先把真正的输出函数留下来：测试自己的进度一律用 out()。
--    （必须定义在 ok() 之前，否则 ok 闭包里的 out 会是 nil —— 踩过。）
local out = print

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

-- ── 假游戏环境 ────────────────────────────────────────────────────────────
local logs = {}
local function collect(level, ...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
end
local function joined()
  local t = {}
  for i = 1, #logs do t[i] = logs[i].text end
  return table.concat(t, "\n")
end
local function has(pat)
  for i = 1, #logs do if logs[i].text:find(pat, 1, true) then return logs[i].text end end
  return nil
end

-- ⚠️ 下面要劫持全局 print 去收集"被测试代码"的日志，
_G.print = function(...) collect("info", ...) end
_G.printerr = function(...) collect("error", ...) end

-- ★ 画布尺寸故意返回**浮点**（真机就是这么返回的，正是它触发了那个 bug）
local canvas = { w = 1600.0, h = 900.0 }
local roots = {}          -- 默认：一棵空树（模拟"控件还没搭"）

local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true }
  c.GetChildren = function() return c.__kids or {} end
  c.GetChild = function(_, n)
    for _, k in ipairs(c.__kids or {}) do if k.name == n then return k end end
    return nil
  end
  c.SetVisible = function() end
  c.SetActive = function() end
  c.SetSizeDelta = function() end
  -- 记录锚点位置：用来断言"引用控件被挪出了画布"（_park_control 靠它生效）
  c.SetAnchoredPosition = function(_, x, y) c.ax, c.ay = x, y end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() end
  c.SetLocalScale = function() end
  c.AddCursorEventListener = function() end
  -- 层级：记录 SetAsFirstSibling 的调用顺序，用来断言图层规划生效
  c.SetAsFirstSibling = function(self) self.__first_calls = (self.__first_calls or 0) + 1 return true end
  return c
end

-- ★★★★★ 2026-10-09 **按"真机现在的树形"建树：`root` → `stage` → 格子** ✗✓
--
--   ★ 为什么必须补这个helper（★ 这是 §6/§6b/§6c/§6d **15 条红的唯一根因**）✗✓
--
--   ★ 症状 ✓：这四段一共 15 条断言全红，而**断言文案其实都是对的** ——
--     我一度以为是"日志文案过期"（因为 `探针已销毁` / `缺 25 个格子` 在源码里 `grep` 不到），
--     **但那是 grep 的错觉** ✗：那两句在源码里是**拼接**出来的
--     （`"探针已" .. (dok and "销毁" or "**销毁失败**…")`，`engine_adapter_qianxing.lua:2030`；
--       `"有 " .. missing .. " 个格子还没建"`，同文件 `:2039`）⇒ grep 当然找不到 ✓
--
--   ★ 真因（★ 我插了一段临时 dump 把日志全打出来才看见 ✓）✗✓：
--        [murdoku] ⚠️ 建控件前没找到 stage（root 底下没有）
--        [murdoku] 生成格子失败：找不到父控件 stage
--     ⇒ ★ `ensure_cells` **第一句就返回了** ✗ ⇒ 这四段想验的东西
--       （模板引用控件让位 / 逐格自检 / 中间容器穿透）**一次都没被执行到** ✓✓
--
--   ★ 为什么树形变了 ✓：本项目在 2026-10 把格子从 `board` 挪到了 **`stage`**
--     （提交 `234` 的记录：真机日志 `stage` 有 27 个子控件，而 `board` **两边都找不到**；
--      `ui_controller` 的规划里也早就 `push({ id = "stage", … })` ✓）
--     —— 而本测试的假树**还停在旧的 `board`** ✗ ⇒ 结构性过期，不是文案过期 ✓
--
--   ⚠️ 以后树形再变，**要改的是这里**，不是去改断言文案 ✓
local function tree_root(kids)
  local root = make_ctrl("root")
  local stage = make_ctrl("stage")
  stage.__kids = kids or {}
  root.__kids = { stage }
  return root, stage
end

-- ★ 官方 Color(r,g,b,a?) 创建 ColorValue（0-255，a 可省略）—— 染色的 imageColor 就是它。
--   冒烟环境要提供，否则 tint 那条只会打「拿不到 Color」。
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = (a == nil) and 255 or a } end

local sent_signals = {}
-- ★ 让 instantiate **真的能造出东西**：以前这里返回 nil，于是"生成格子"这条路
--   在冒烟测试里**从来没被走过** —— 真机上那堆生成相关的 bug 全靠试玩才发现。
--   现在造出来的假控件会挂到 parent 的 __kids 上（模拟真机的挂载），
--   并且 DestroyClientUIControl 会真的把它摘掉。
local instantiated_log = {}
local function destroy_ctrl(c)
  local p = c and c.__parent
  if p == nil or p.__kids == nil then return end
  for i = #p.__kids, 1, -1 do
    if p.__kids[i] == c then table.remove(p.__kids, i) end
  end
end
_G.game = {
  GetUICanvasSize = function() return canvas.w, canvas.h end,
  GetClientUIRoots = function() return roots end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)")
    c.kind = "button"
    c.prefabIndex = prefab
    c.__parent = parent
    if parent ~= nil then
      parent.__kids = parent.__kids or {}
      parent.__kids[#parent.__kids + 1] = c
    end
    instantiated_log[#instantiated_log + 1] = c
    return c
  end,
  DestroyClientUIControl = function(c) destroy_ctrl(c) end,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end,
  PrintClientUITree = function() collect("info", "[game] PrintClientUITree") end,
  ServerSignal = function(name)
    sent_signals[#sent_signals + 1] = name
    local s = {}
    s.AddInt = function() end
    s.AddFloat = function() end
    s.AddString = function() end
    s.AddBool = function() end
    s.SendSignal = function() end
    return s
  end,
  PlayAudio2D = function() end,
  GetText = function() return "" end,
}
_G.script = {
  EnableUpdate = function(_, v) _G.__update_enabled = v end,
  RegisterServerSignalHandler = function() end,
  RegisterCustomVariableChangedHandler = function() end,
  Invoke = function() end,
  GetParam = function() return nil end,
}
_G.Enum = nil      -- 故意不给：适配层全是 nil-safe 的降级路径

-- ── 加载入口（就是真机加载的那个单文件产物）──────────────────────────────
out("== 加载 dist/client_script.lua ==")
local bundle_path = root .. "dist/client_script.lua"
local chunk, lerr = loadfile(bundle_path)
ok(chunk ~= nil, "单文件产物能加载（Lua 5.3 编译通过）", lerr)
if not chunk then
  out(string.format("\n结果：%d 通过 / %d 失败", pass, fail))
  os.exit(1)
end
local okrun, rerr = pcall(chunk)
ok(okrun, "顶层 chunk 执行到底", rerr)
if not okrun then
  out(string.format("\n结果：%d 通过 / %d 失败", pass, fail))
  os.exit(1)
end
ok(type(OnInit) == "function" and type(OnStart) == "function"
  and type(OnUpdate) == "function" and type(OnDestroy) == "function",
  "四个生命周期函数都在（OnInit / OnStart / OnUpdate / OnDestroy）")

-- ── 1. OnInit：浮点画布尺寸 + 空控件树 ───────────────────────────────────
out("\n== 1. OnInit（画布尺寸是浮点 1600.0×900.0 —— 就是崩过的那一种）==")
local ok1, err1 = pcall(OnInit)
ok(ok1, "OnInit 不抛错", err1)
ok(has("OnInit done") ~= nil, "走到了 OnInit done", has("OnInit done"))
ok(_G.__update_enabled == true, "script:EnableUpdate(true) 被调用（门控 ③）")

local canvas_line = has("画布")
ok(canvas_line ~= nil, "画布尺寸这行日志打出来了（%d 崩掉时就看不到它）", canvas_line)
-- 整数 1600.0 应当被打成 "1600" 而不是报错
ok(canvas_line ~= nil and canvas_line:find("1600", 1, true) ~= nil,
  "浮点 1600.0 被安全格式化成 1600")

-- ── 2. 非整数画布也要能打出来 ─────────────────────────────────────────────
out("\n== 2. 画布尺寸是非整数（例如 1600.5）时也不能崩 ==")
-- 重新加载一份干净的入口来复测（check_canvas 只会跑一次）
canvas.w, canvas.h = 1920.5, 1080.25
logs = {}
roots = {}
local chunk2 = loadfile(bundle_path)
local ok2a, err2a = pcall(chunk2)
ok(ok2a, "重新加载产物", err2a)
local ok2b, err2b = pcall(OnInit)
ok(ok2b, "OnInit 在非整数画布下也不抛错", err2b)
local line2 = has("画布")
ok(line2 ~= nil, "打出了画布尺寸", line2)
ok(line2 ~= nil and line2:find("1920.50", 1, true) ~= nil,
  "非整数被保留两位小数打出来（1920.50）", line2)

-- ── 3. OnStart：控件还没搭 → 不许崩；**但这时不该把控件树打出来** ────────
--
-- 2026-09-26 12:20 真机日志暴露的问题：OnStart 阶段控件树本来就是空的
-- （约 0.5 秒后才出现，实测），旧实现却在这里就打出「树是空的 + 三条病因」，
-- 看着像出了大故障。现在分轻重：
--   还有重试机会 → 只说一句"还没就绪"；放弃重试时才打完整诊断。
out("\n== 3. OnStart（控件树是空的，模拟「还没搭界面」）==")
logs = {}
local ok3, err3 = pcall(OnStart)
ok(ok3, "OnStart 不抛错", err3)
ok(has("控件还没就绪") ~= nil, "识别出「控件还没就绪」并交给 OnUpdate 重试",
  has("控件还没就绪"))
ok(has("客户端控件树") == nil,
  "**没有**在这一步打控件树（此时树是空的属正常，不该报成故障）",
  has("客户端控件树"))
ok(has("界面布局没被") == nil,
  "也没有把「三条病因」砸出来（那是放弃重试时的话术）")

-- ── 4. OnUpdate 惰性重试直到放弃：**这时**才该给出完整诊断 ────────────────
out("\n== 4. OnUpdate 惰性重试（空控件树 → 最终放弃且给出完整诊断）==")
logs = {}
local ok4, err4 = pcall(function()
  for _ = 1, 70 do OnUpdate(1.0) end
end)
ok(ok4, "OnUpdate 反复调用不抛错", err4)
ok(has("等不到客户端控件") ~= nil, "到达上限后明确报告放弃",
  has("等不到客户端控件"))
ok(has("放弃自动开局") ~= nil and has("职业") ~= nil,
  "放弃信息里提示了要检查的两件事（容器激活可见 / 布局被职业引用）")
ok(has("客户端控件树") ~= nil,
  "放弃时把控件树打了出来（排查靠它）", has("客户端控件树"))
ok(has("界面布局没被") ~= nil or has("客户端控件容器") ~= nil,
  "放弃时给出了三条病因（现在是真故障了）")

-- ── 5. 控件齐了：OnStart 应当真的开局 ────────────────────────────────────
out("\n== 5. 控件就绪后 OnStart 能开局（浮点画布也不影响）==")
logs = {}
sent_signals = {}
canvas.w, canvas.h = 1600.0, 900.0
local chunk3 = loadfile(bundle_path)
pcall(chunk3)
-- 造一棵"至少有 board 和 cell.1.1"的树，让探针通过
local board = make_ctrl("board")
local cell = make_ctrl("cell.1.1")
board.__kids = { cell }
roots = { board }
local ok5, err5 = pcall(function()
  OnInit()
  OnStart()
end)
ok(ok5, "OnInit + OnStart 不抛错", err5)
ok(has("started:") ~= nil, "开局成功（日志里有 started:）", has("started:"))
ok(#sent_signals > 0, "向服务器发了信号（节点图侧有东西可接）",
  sent_signals[1] or "(没发)")

-- ── 6. ★ 纯模板模式：board 下**只有 tpl.cell**，没有任何真格子 ──────────────
--
-- 用户的设计（2026-09-26）：编辑器里一个真格子都不建，只放一个「模板引用控件」
-- `tpl.cell` 引用客户端控件模板，格子全部由脚本生成 —— 控件的数量最省。
--
-- 这个模式会踩到三处把 `cell.1.1` 当锚点的代码：
--   ① 候选索引的"基准值"曾从"第一个找到的控件"推 → 会推成 tpl.cell 自己 → 误判"没有可用模板"
--   ② 格子体检找不到 cell.1.1 时会报"找不到这个控件" → 误报
--   ③ 没有参照格子 → 图片盖章失效（这条是**正常代价**，但必须说出来）
-- 本段就是这三条的回归防线。
out("\n== 6. 纯模板模式（只有 tpl.cell，没有 cell.1.1）==")
logs = {}
sent_signals = {}
canvas.w, canvas.h = 1600.0, 900.0
local chunk4 = loadfile(bundle_path)
pcall(chunk4)
local tplc = make_ctrl("tpl.cell")
tplc.kind = "button"
tplc.prefabIndex = 1073741876          -- 模拟"模板引用控件"带的可用模板索引
-- ★ 2026-10-09：改挂到 `stage` 下（见 `tree_root` 的长注释 ✓）
local root6 = tree_root({ tplc })
roots = { root6 }
local ok6, err6 = pcall(function()
  OnInit()
  OnStart()
  -- 跑几帧，让 ensure_cells / 体检 / 渲染都走到
  for _ = 1, 5 do OnUpdate(0.5) end
end)
ok(ok6, "纯模板模式不抛错", err6)
ok(has("started") ~= nil, "纯模板模式下也能开局", has("started"))
ok(has("纯模板模式") ~= nil, "明确识别为**纯模板模式**（而不是报「找不到控件」）",
  has("纯模板模式"))
ok(has("体检结束") ~= nil, "体检正常跑完")
-- 反例：绝不能再出现"找不到这个控件"这种误报
ok(has("格子体检 cell.1.1：**找不到这个控件**") == nil,
  "**没有**把「没有 cell.1.1」报成「找不到控件」（误报回归）")
ok(has("参照格子") ~= nil, "说明了「没有参照格子 → 不做图片盖章」这条正常代价")

-- ── 6b. ★ 引用控件占着 `cell.1.1` 这个名字 ────────────────────────────────
--
-- 真机 17:17 / 17:23 的截图 + 日志：`cell.1.1` 的 prefabIndex **正好等于**
-- cfg.cells.prefab → 它**就是模板引用控件本身**。于是它被算成"已存在"，
-- 那一格永远不会被生成，而引用控件渲染不出格子副本 → 截图里 (1,1) 是空的。
--
-- 期望行为：脚本先把它**改名让位**（__tpl_ref_cell.1.1）+ 隐藏，
-- 于是 `cell.1.1` 变成"缺"，脚本会在那一格真的生成副本。
out("\n== 6b. 引用控件占着 cell.1.1 这个名字（真机踩过的坑）==")
logs = {}
sent_signals = {}
canvas.w, canvas.h = 1600.0, 900.0
local chunk5 = loadfile(bundle_path)
pcall(chunk5)
-- ★★★★★ 2026-10-09 **逐格自检现在有一道闸，验它之前必须先开闸** ✗✓
--   ★ 闸在哪 ✓：`main.lua:672` 是 `if Murdoku.DIAG then pcall(function() adapter:diagnose_grid(...) end) end`
--   ★ 默认值 ✓：`main.lua:853` 写着 `Murdoku.DIAG = Murdoku.DIAG or false` ⇒ **默认关** ✓
--     （关得有道理 ✓：诊断会刷屏，而本项目对每帧成本敏感 ✓ 用法注释在同文件 `:850` ✓）
--   ⇒ ★ 本段要验的三条（`逐格自检` / `树上实际有` / `来源统计`）**本来就只在开闸时才打** ✓
--     ⇒ ★ 不开闸 = 在测"闸关着"，不是"自检查不出来" ✗ —— 那是**假红** ✓
--   ⚠️⚠️ **不能直接写 `Murdoku.DIAG = true`** ✗ —— 我第一版就是这么写的，**静默无效** ✓
--     实测（临时打印）：本测试的全局环境里 **`Murdoku = nil`** ✗
--     （打包器把模块裹进了作用域 ✓ —— `entry_client_script.lua:50` 那个赋值
--       在本测试的 `_G` 里**看不到** ✓）
--   ★ 正确的把手 ✓：`entry_client_script.lua:573` 导出了
--     **`_G.__murdoku_debug = { adapter = adapter, Murdoku = Murdoku }`** ✓
--   ⚠️ 时机 ✓：`__murdoku_debug` 是 **`OnInit` 里**才建的 ✓
--     ⇒ 只能在 `OnInit()` **之后**、`OnStart()` **之前**设 ✓
--     （`diagnose_grid` 在 `Murdoku.start` 里跑 ✓ 而 `start` 是 `OnStart` 调的 ✓ 来得及 ✓）
local squat = make_ctrl("cell.1.1")
squat.kind = "button"
squat.prefabIndex = 1073741876        -- ★ 与 cfg.cells.prefab 相同 → 它就是引用控件
-- ★ 2026-10-09：**格子必须挂在 `stage` 下**，否则 `ensure_cells` 第一句就返回（见 `tree_root`）
local root6b = tree_root({ squat })
roots = { root6b }
local ok6b, err6b = pcall(function()
  OnInit()
  -- ★ 开闸的**唯一正确时机**：`__murdoku_debug` 刚由 OnInit 建好，而 `diagnose_grid`
  --   要等 OnStart→Murdoku.start 才跑（详见上面那段长注释 ✓）
  if _G.__murdoku_debug ~= nil and _G.__murdoku_debug.Murdoku ~= nil then
    _G.__murdoku_debug.Murdoku.DIAG = true
  end
  OnStart()
  for _ = 1, 5 do OnUpdate(0.5) end
end)
ok(ok6b, "不抛错", err6b)
ok(has("其实是**模板引用控件本身**") ~= nil,
  "识别出「cell.1.1 就是模板引用控件本身」并让它让位",
  has("其实是**模板引用控件本身**"))
ok(squat.name == "__tpl_ref_cell.1.1",
  "占位控件被改名让位（现在叫 " .. tostring(squat.name) .. "）")
ok(has("缺 25 个格子") ~= nil or has("有 25 个格子还没建") ~= nil,
  "让位后**缺 25 格**（而不是 24）—— 说明 cell.1.1 这一格也会被生成",
  has("缺 25 个格子") or has("有 25 个格子还没建"))
-- ★ 逐格自检必须真的跑起来（17:56 日志"新建 23 个 / 25 格齐全"对不上账，
--   就是靠它把 board 的真实子控件摊出来的）
ok(has("逐格自检") ~= nil, "打出了逐格自检", has("树上实际有"))
ok(has("树上实际有") ~= nil, "逐格自检列出了 board 树上的真实子控件", has("树上实际有"))
ok(has("来源统计") ~= nil, "逐格自检统计了「脚本建的 / 编辑器摆的」", has("来源统计"))
-- ★ 探针必须被销毁、**不许复用**：
--   18:13 真机逐格自检证明"试造出来的那个对象"没有落到 parent 上
--   （树上 24 格，唯独 cell.1.1 不在），所以它不能再被当成第一个格子收下。
ok(has("试造成功") ~= nil, "试造成功后明确报告了（探针路径在跑）", has("试造成功"))
ok(has("探针已销毁") ~= nil or has("探针已**销毁失败**") ~= nil,
  "探针被销毁、没有复用", has("探针已销毁") or has("探针已**销毁失败**"))
-- ★ 占位控件必须被**挪出画布**（不能只靠 SetVisible）：真机上 active 只读、
--   且「true 时控件可见」，脚本改不了 active，只能把它挪走才不会盖住格子。
ok(squat.ax == 200000 and squat.ay == 200000,
  "占位控件被挪出画布（锚点位置 = " .. tostring(squat.ax) .. "," .. tostring(squat.ay) .. "）")

-- ── 6c. ★ 靠 `referencedPrefabIndex` 认模板引用控件 ─────────────────────
--
-- 用户 2026-09-26 纠正：`prefabIndex` 是**控件自身**的索引；
-- 模板引用控件引用的是另一个字段 `referencedPrefabIndex`。
-- 这里模拟"自身索引是 1073741885（不是模板），引用的是 1073741876（模板）"，
-- 脚本应当**按 referencedPrefabIndex 认出它**并让它让位。
out("\n== 6c. 按 referencedPrefabIndex 认模板引用控件（字段语义纠正）==")
logs = {}
sent_signals = {}
canvas.w, canvas.h = 1600.0, 900.0
local chunk6 = loadfile(bundle_path)
pcall(chunk6)
local refc = make_ctrl("cell.1.1")
refc.kind = "button"
refc.prefabIndex = 1073741885            -- ← 控件**自身**的索引（不是模板）
refc.referencedPrefabIndex = 1073741876  -- ← 引用的**模板**索引（== cfg.cells.prefab）
-- ★ 2026-10-09：同 6b，格子挂 `stage` 下（见 `tree_root`）
local root6c = tree_root({ refc })
roots = { root6c }
local ok6c, err6c = pcall(function()
  OnInit()
  OnStart()
  for _ = 1, 5 do OnUpdate(0.5) end
end)
ok(ok6c, "不抛错", err6c)
ok(refc.name == "__tpl_ref_cell.1.1",
  "按 referencedPrefabIndex 认出来了（现在叫 " .. tostring(refc.name) .. "）")
ok(has("缺 25 个格子") ~= nil or has("有 25 个格子还没建") ~= nil,
  "它让位后缺 25 格 —— 那一格会由脚本生成",
  has("缺 25 个格子") or has("有 25 个格子还没建"))

-- ── 6d. ★ 一个模板怎么给不同格子配不同图：调色板 + 染色 + 墙门 ──────────────
--
-- 这是用户提的架构问题：格子都由同一个模板生成，怎么配不同美术？
-- 三条机制（全部有官方依据）：
--   ① 换图  —— SetImage(source, id)，id 从**调色板控件**读出来（不用手抄数字）
--   ② 染色  —— imageColor 是读写字段，同底图不同色区分房间（零额外素材）
--   ③ 墙/门 —— 模板里放固定的 wall.up/down/left/right 与 door.*，靠 SetVisible 开关
out("\n== 6d. 调色板 / 染色 / 墙门（一个模板配多种美术）==")
logs = {}
canvas.w, canvas.h = 1600.0, 900.0
local chunk7 = loadfile(bundle_path)
pcall(chunk7)
-- 造一棵树：stage + 调色板 assets(room.kitchen) + 一个格子（带 face / wall.up / door.left）
-- ★ 2026-10-09：格子从 `board` 改挂 `stage`（见 `tree_root`）——
--   否则 `open_click_passthrough`（`engine_adapter_qianxing.lua:3771`）
--   根本不会被调用 ⇒ 那条「中间容器穿透被关掉」的断言必然假红 ✓
local pal = make_ctrl("assets")
local pal_img = make_ctrl("room.kitchen")
pal_img.imageSource = "StaticReference"
pal_img.imageId = 424242
pal.__kids = { pal_img }
local cellc = make_ctrl("cell.1.1")
cellc.kind = "button"
cellc.__kids = {}
local face = make_ctrl("face"); face.imageSource = "StaticReference"; face.imageId = 106053
face.__visible = true
face.SetVisible = function(_, v) face.__visible = v end
-- 假控件也要有 SetImage（适配层会调它把调色板里的 id 套上来）
face.SetImage = function(_, src, id) face.imageSource = src; face.imageId = id end
local wallup = make_ctrl("wall.up"); wallup.__visible = true
wallup.SetVisible = function(_, v) wallup.__visible = v end
local doorl = make_ctrl("door.left"); doorl.__visible = true
doorl.SetVisible = function(_, v) doorl.__visible = v end
local content = make_ctrl("content")
content.disableCursorEventPassthrough = true     -- 故意开着：脚本必须把它关掉
content.disableKeyEventPassthrough = true
content.__kids = { face, wallup, doorl }
cellc.__kids = { content }
local root6d = tree_root({ cellc })
roots = { root6d, pal }
local ok6d, err6d = pcall(function()
  OnInit()
  OnStart()
  local dbg = __murdoku_debug
  local ad = dbg and dbg.adapter
  if ad == nil then return end
  -- ① 调色板读出来了
  local pmap = ad:read_palette()
  if pmap["room.kitchen"] == nil then error("调色板没读到 room.kitchen") end
  -- ② 按名字换图（SetImage 收到的是调色板里的整数 id）
  ad:set_property("cell.1.1", "image", "room.kitchen")
  -- ③ 染色
  ad:set_property("cell.1.1", "tint", { r = 10, g = 20, b = 30 })
  -- ④ 墙 / 门 开关
  ad:set_property("cell.1.1", "walls", { up = false, down = true, left = true, right = false })
  ad:set_property("cell.1.1", "doors", { left = false, right = true })
end)
ok(ok6d, "调色板/染色/墙门 不抛错", err6d)
if __murdoku_debug ~= nil and __murdoku_debug.adapter ~= nil then
  ok(face.imageId == 424242, "① 按素材名换图成功（face.imageId = " .. tostring(face.imageId) .. "）")
  ok(wallup.__visible == false, "③ wall.up 按数据关掉了（visible=" .. tostring(wallup.__visible) .. "）")
  ok(doorl.__visible == false, "③ door.left 按数据关掉了（visible=" .. tostring(doorl.__visible) .. "）")
  ok(content.disableCursorEventPassthrough == false,
  "★ 中间容器的「屏蔽区域内点击事件穿透」被脚本关掉了（"
  .. tostring(content.disableCursorEventPassthrough) .. "）")
  -- ★★★★★★★★ 2026-10-15 **断言换成"打包整数"** ✗✓（旧断言读的是 `imageColor.r` ✗）
  --
  --   ★ 为什么必须换 ✗：★ 染色那条路**改契约了** ✓ ——
  --     ★ 旧写法：`Color(r,g,b)`（若环境里有这个全局函数）⇒ `imageColor` 是**表** ✓
  --     ★★ 真机实测：★ **`Color()` 根本不存在** ✗ ⇒ 表那条路**永远拿不到值** ✓
  --       ⇒ ★★ 于是"卡片一直纯白、缩略图一直没颜色" ✓（用户 2026-10-15 截图 ✓）
  --     ★ 新写法：★ 一律打包成 **`0xAARRGGBB` 整数** ✓ 直接写 `imageColor` ✓
  --       （★ 真机已证明整数可用 ✓：`PLACED_TINT` / `HIGHLIGHT_TINT` 都是整数 ✓）
  --   ★ 判据一并升级 ✓：★ 不只断言"有值"，而是断言**那个整数逐位对** ✓
  --     `{r=10,g=20,b=30}` + a=255 ⇒ `0xFF0A141E` = 4278850590 ✓
  local TINT_WANT = 4278850590
  ok(face.imageColor == TINT_WANT,
    "② 染色落到了 face.imageColor（0xAARRGGBB = " .. tostring(face.imageColor)
    .. "，期望 " .. tostring(TINT_WANT) .. "）")
else
  ok(false, "拿不到适配器实例（__murdoku_debug.adapter）")
end

-- ── 7. OnDestroy ─────────────────────────────────────────────────────────
out("\n== 7. OnDestroy ==")
logs = {}
local ok7, err7 = pcall(OnDestroy)
ok(ok7, "OnDestroy 不抛错", err7)
ok(has("destroyed") ~= nil, "正常收尾", has("destroyed"))

print(string.format("\n结果：%d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
