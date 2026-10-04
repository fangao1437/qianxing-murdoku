--[[----------------------------------------------------------------------------
  tests/board_bg.lua —— 离线验「棋盘底板 board.bg」那一段（2026-10-04 真机事故）

  真机现场（v034）：日志行
      [murdoku] 棋盘底板：board.bg 建=true 设图=false imageId=0
  重复了**上百次**。用户报的三个现象 + 日志给出的真凶：
    ① 底盘被**每帧新建**一块（旧代码用 `Adapter:find("board.bg")` 判存在，
       而这条查找在真机上永远拿不到东西）⇒ 上百块 677×677 的白板叠在棋盘上；
    ② `SetVisible(true)` **每帧无条件**调用 ⇒ 主页 / 选关页也看得到；
    ③ `SetImage` 打在**实例根**上 ⇒ 静默失败（`imageId` 恒为 0）⇒ 没有配图；
    ④ 运行时新建的控件**追加**在父级子列表**末尾** ⇒ 底板盖在 25 个格子**上面**。

  这个测试用**假游戏环境**把真机入口完整跑一遍（和 tests/entry_smoke.lua 同一套路），
  然后按「关卡 → 选关 → 主页 → 关卡」切屏，逐条断言上面四条都被修掉：

    [1] 关卡内连跑 20 帧，底板**只建 1 块**（不是 20 块）；
    [2] 建完被压到**最底层**（SetSiblingIndex(0) / SetAsFirstSibling 真的调了，
        且它确实是父级子列表的第 1 个 —— 25 个格子都在它上面）；
    [3] 图设到了**子控件**上（不是实例根），且 `imageId` 回读 == 请求的 id；
    [4] 选关页 / 主页上 `visible=false`，回到关卡内 `visible=true`；
    [5] 全程没有 `printerr` 级的 `attempt to ... / nil value / bad argument`。

  ⚠️ 关于 [1] 的诚实说明（离线能测到哪一步，实测结论）：
    真机"每帧新建"的**直接原因**是引擎侧那条 `find` 拿不到刚建出来的控件
    （项目自己的真机日志也印证过：`InstantiateClientUIControl` 造出来的对象
     **没有落到 parent 上**，见 tests/entry_smoke.lua 6b 的注释）。
    而假环境里控件树是一张规规矩矩的 Lua 表：`find` 一定找得到
    （先命中旧代码自己写的 `controls["board.bg"] = ob`，再不行也能按名字搜到）
    ⇒ **在假环境里，旧代码不会真的每帧新建控件**，实测旧版这一条是 1 块（通过）。
    ⇒ 所以 [1] 拆成**两个口径**，各自抓住不同的东西：
        · 口径 A（控件身份 / 活控件个数）—— 用户真正看到的东西，**回归防线**：
          谁把"只建一次"改坏了，它立刻变红；但它抓不住旧版（假环境的 find 太乖）。
        · 口径 B（日志行数）—— 直接对上真机那行重复上百次的日志：
          旧版**每帧**都会走完这条路径并打一行 ⇒ 20 帧 20 行，**实测旧版必红**。
      两个口径都留着：A 说"控件有没有堆起来"，B 说"这段代码有没有每帧跑"。
      真机上两者会同时红；离线只有 B 红 —— 这一点如实写在测试输出里。

  实测（同一份测试文件）：
    · 当前工作树：26 passed, 0 failed（exit 0）
    · 修复前版本（v034）：19 passed, 7 failed（exit 1）
      红的是：[1]日志口径 20 次、[2]×2、[3]×2、[4]×2（选关/主页仍然可见）

  跑法：lua tests/board_bg.lua
  前置：先 `lua tools/bundle_client_script.lua` 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/board_bg.lua"
local root = here:gsub("tests[/\\]board_bg%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

-- ⚠️ 下面要劫持全局 print/printerr 去收集「被测试代码」的日志，
--    所以先把真正的输出函数留下来：测试自己的进度一律用 out()。
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

-- ── 假游戏环境：日志收集 ──────────────────────────────────────────────────
local logs = {}
local function collect(level, ...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  logs[#logs + 1] = { level = level, text = table.concat(t, " ") }
end
_G.print = function(...) collect("info", ...) end
_G.printerr = function(...) collect("error", ...) end

local function has(pat)
  for i = 1, #logs do if logs[i].text:find(pat, 1, true) then return logs[i].text end end
  return nil
end
-- 「底板被（新建/处理）」的那一行日志出现了几次 —— 口径 B。
-- ⚠️ 措辞故意放宽：只要一行同时提到 board.bg 和"建"这件事就算一次。
--    旧版是 `棋盘底板：board.bg 建=true 设图=false imageId=0`，
--    修好后是 `棋盘底板：新建 board.bg（素材 …）…`；两版都能被数到，
--    而`设图 board.bg imageId=…`（诊断行，不含"建"）不会被误算。
local BUILD_MARKS = { "新建", "建=", "创建", "建出", "built", "create" }
local function count_plate_build_lines()
  local n = 0
  for i = 1, #logs do
    local t = logs[i].text
    if t:find("board.bg", 1, true) then
      for _, m in ipairs(BUILD_MARKS) do
        if t:find(m, 1, true) then n = n + 1 break end
      end
    end
  end
  return n
end
local function first_plate_build_line()
  for i = 1, #logs do
    local t = logs[i].text
    if t:find("board.bg", 1, true) then
      for _, m in ipairs(BUILD_MARKS) do
        if t:find(m, 1, true) then return t end
      end
    end
  end
  return nil
end

-- ── 假控件 ────────────────────────────────────────────────────────────────
--
-- ★ 真机语义（这一段是测"能不能分辨根和子控件"的关键，不能省）：
--     · 运行时新建控件的**根**上 `SetImage` **静默失败**（返回 false、`imageId` 不变）
--       —— 真机日志 `设图=false imageId=0` 就是它；
--     · 图片必须设在**子节点**上（这里按官方的图片模板造：根 → content → face）；
--     · 新建的控件**追加**在父级子列表末尾（= 显示在最上层）；
--     · `SetSiblingIndex(0)` **真的**把它挪到子列表第 1 位（0 = 最底）。
local img_calls = {}    -- 每次 SetImage 的记录：{ target=, id=, src=, ok= }
local inst_log  = {}    -- 每次 InstantiateClientUIControl 的记录：{ ctrl=, prefab=, parent= }

local function attach(parent, c)
  if parent == nil then return end
  parent.__kids = parent.__kids or {}
  parent.__kids[#parent.__kids + 1] = c      -- ★ 追加在末尾 = 最上层（真机语义）
  c.__parent = parent
end

-- 容器 / 实例根：SetImage 无效（真机上静默失败）
local function make_ctrl(name)
  local c = { name = name, kind = "container", visible = true, active = true, __kids = {} }
  c.GetChildren = function() return c.__kids end
  -- ⚠️ 两种调用形式都要支持：适配器里 `GetChild("face")`（按名字，见 image_target）
  --    和 `GetChild(i)`（0-based 序号，见 image_target 的兜底分支）。
  c.GetChild = function(_, key)
    if type(key) == "number" then return c.__kids[key + 1] end
    for _, k in ipairs(c.__kids) do if k.name == key then return k end end
    return nil
  end
  c.GetChildCount = function() return #c.__kids end
  c.GetParent = function() return c.__parent end
  c.SetVisible = function(_, v)
    c.visible = v
    c.__vis_calls = (c.__vis_calls or 0) + 1
    c.__vis_log = c.__vis_log or {}
    c.__vis_log[#c.__vis_log + 1] = v
  end
  c.SetActive = function(_, v) c.active = v end
  c.SetSizeDelta = function(_, w, h) c.w, c.h = w, h end
  c.GetSizeDelta = function() return c.w or 0, c.h or 0 end
  -- 记录锚点位置：`_park_control`（把"模板引用控件"挪出画布）靠它生效
  c.SetAnchoredPosition = function(_, x, y) c.ax, c.ay = x, y end
  c.GetAnchoredPosition = function() return c.ax or 0, c.ay or 0 end
  c.SetAnchorMin = function() end
  c.SetAnchorMax = function() end
  c.SetPivot = function() end
  c.SetLocalScale = function() end
  c.AddCursorEventListener = function() end
  c.SetImage = function(_, a, b)
    local want = b
    if want == nil and type(a) == "number" then want = a end
    img_calls[#img_calls + 1] = { target = c, id = want, src = a, ok = false,
                                  via = "容器/实例根（真机上静默失败）" }
    return false                    -- ← 静默失败：imageId 一个字节都不动
  end
  -- 图层：官方「数值越大越靠上」⇒ 0 = 最底。这里**真的**改父级子列表顺序，
  -- 于是"底板有没有被压到 25 个格子下面"可以用**位置**验证，而不只是看调用记录。
  c.SetSiblingIndex = function(_, i)
    c.__sib_calls = c.__sib_calls or {}
    c.__sib_calls[#c.__sib_calls + 1] = i
    local p = c.__parent
    if p == nil or p.__kids == nil then return false end
    for k = #p.__kids, 1, -1 do if p.__kids[k] == c then table.remove(p.__kids, k) end end
    local at = math.floor(tonumber(i) or 0) + 1
    if at < 1 then at = 1 end
    if at > #p.__kids + 1 then at = #p.__kids + 1 end
    table.insert(p.__kids, at, c)
    return true
  end
  c.GetSiblingIndex = function()
    local p = c.__parent
    if p == nil or p.__kids == nil then return -1 end
    for i = 1, #p.__kids do if p.__kids[i] == c then return i - 1 end end
    return -1
  end
  c.SetAsFirstSibling = function(self)
    self.__first_calls = (self.__first_calls or 0) + 1
    -- 官方语义同样是"排到子列表第一个"，所以这里也**真的**挪位置
    local p = self.__parent
    if p ~= nil and p.__kids ~= nil then
      for k = #p.__kids, 1, -1 do if p.__kids[k] == self then table.remove(p.__kids, k) end end
      table.insert(p.__kids, 1, self)
    end
    return true
  end
  return c
end

-- 图片节点：SetImage **真的能设上**（真机上图片挂在子节点里）
local function make_image_child(name, src, id)
  local c = make_ctrl(name)
  c.imageSource = src
  c.imageId = id
  c.SetImage = function(_, a, b)
    local want, newsrc = b, a
    if want == nil and type(a) == "number" then want, newsrc = a, nil end
    if want == nil then
      img_calls[#img_calls + 1] = { target = c, id = nil, src = a, ok = false, via = "图片节点（没给 id）" }
      return false
    end
    if newsrc ~= nil then c.imageSource = newsrc end
    c.imageId = want
    img_calls[#img_calls + 1] = { target = c, id = want, src = a, ok = true, via = "图片节点" }
    return true
  end
  return c
end

-- ── 假控件树：root → home / stage，stage 下摆好 25 个格子 ──────────────────
--   `stage` 是脚本创建容器的家（cfg.stage.parent / cfg.cells.parent 都是 "stage"），
--   格子与底板**同父** ⇒ 才谈得上"底板要压在格子下面"。
local canvas = { w = 1600.0, h = 900.0 }
local tree, home_ctrl, stage_ctrl

local function build_tree()
  local rt = make_ctrl("root")
  local hm = make_ctrl("home")
  local st = make_ctrl("stage")
  for r = 1, 5 do
    for cc = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. cc)
      cell.kind = "button"
      local content = make_ctrl("content")
      local face = make_image_child("face", "StaticReference", 106053)   -- 格子底图（白色底板）
      attach(content, face)
      attach(cell, content)
      attach(st, cell)
    end
  end
  attach(rt, hm)
  attach(rt, st)
  return rt, hm, st
end

-- ⚠️ `game.GetClientUIRoots()` 返回的是**根控件数组**（适配器里是 `for i = 1, #roots`），
--    所以这里必须是 `{ root控件 }`，不能直接给 root 控件本身 —— 给错了的话
--    适配器会认为"控件树是空的"（踩过：OnStart 直接报"控件还没就绪"）。
do
  local rt, hm, st = build_tree()
  tree = { rt }
  home_ctrl, stage_ctrl = hm, st
end

-- 底板模板索引由入口配置决定（cfg.prefab_icon），测试里不写死数字：
-- 建控件时现读，用来核对"建出来的东西是不是图片模板"。
local function icon_prefab()
  local dbg = _G.__murdoku_debug
  local ad = dbg and dbg.adapter
  local cfg = ad and ad.cfg
  return cfg and cfg.prefab_icon
end

_G.game = {
  GetUICanvasSize = function() return canvas.w, canvas.h end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    -- ★ 官方图片模板的形状：根（设图无效）→ content（中间容器）→ face（图片节点）
    local c = make_ctrl("(未命名)")
    c.kind = "button"
    c.prefabIndex = prefab
    c.imageId = 0                       -- 真机：实例根上 imageId 恒为 0
    c.imageSource = nil
    local content = make_ctrl("content")
    local face = make_image_child("face", "StaticReference", nil)
    attach(content, face)
    attach(c, content)
    attach(parent, c)                   -- ★ 追加在末尾 = 最上层
    inst_log[#inst_log + 1] = { ctrl = c, prefab = prefab, parent = parent }
    return c
  end,
  DestroyClientUIControl = function(c)
    local p = c and c.__parent
    if p == nil or p.__kids == nil then return end
    for i = #p.__kids, 1, -1 do if p.__kids[i] == c then table.remove(p.__kids, i) end end
  end,
  GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end,
  PrintClientUITree = function() collect("info", "[game] PrintClientUITree") end,
  ServerSignal = function(name)
    collect("info", "[game] ServerSignal " .. tostring(name))
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
_G.Enum = nil          -- 故意不给：适配层全是 nil-safe 的降级路径

-- ── 底板观测小工具 ────────────────────────────────────────────────────────
local seen_plate = {}      -- 见过的底板对象（按身份去重）
local plate_events = {}    -- 每一次"底板上出现了新的一块"：{ ctrl=, phase= }

local function plates_under(container)
  local list = {}
  for _, k in ipairs((container and container.__kids) or {}) do
    if k.name == "board.bg" then list[#list + 1] = k end
  end
  return list
end
local function scan_plates(phase)
  local added = 0
  for _, k in ipairs(plates_under(stage_ctrl)) do
    if not seen_plate[k] then
      seen_plate[k] = true
      plate_events[#plate_events + 1] = { ctrl = k, phase = phase }
      added = added + 1
    end
  end
  return added
end
local function is_descendant(anc, c)
  local p = c and c.__parent
  local guard = 0
  while p ~= nil and guard < 16 do
    if p == anc then return true end
    p = p.__parent
    guard = guard + 1
  end
  return false
end
local function kids_of_stage_named_board_bg()
  return #plates_under(stage_ctrl)
end

-- ── 加载入口（真机加载的那个单文件产物）──────────────────────────────────
out("== 加载 dist/client_script.lua ==")
local bundle_path = root .. "dist/client_script.lua"
local chunk, lerr = loadfile(bundle_path)
-- ⚠️ 这里**不能**写 `chunk and nil or 提示` —— Lua 的 `x and nil` 恒为 nil，
--    三元式里只要有 nil/false 分支就必须写成 if（本项目在这上面踩过好几次）。
local load_detail = nil
if chunk == nil then
  load_detail = tostring(lerr) .. "　→ 先跑 `lua tools/bundle_client_script.lua` 产出它"
end
ok(chunk ~= nil, "单文件产物能加载（Lua 编译通过）", load_detail)
if not chunk then
  out(string.format("\n%d passed, %d failed", pass, fail))
  os.exit(1)
end
local okrun, rerr = pcall(chunk)
ok(okrun, "顶层 chunk 执行到底", rerr)
if not okrun then
  out(string.format("\n%d passed, %d failed", pass, fail))
  os.exit(1)
end

-- ── 1. OnInit / OnStart ───────────────────────────────────────────────────
out("\n== 1. OnInit + OnStart（假环境：root → home / stage，stage 下 25 个格子）==")
logs = {}
local ok1, err1 = pcall(OnInit)
ok(ok1, "OnInit 不抛错", err1)
local ok2, err2 = pcall(OnStart)
ok(ok2, "OnStart 不抛错", err2)
ok(has("started") ~= nil, "开局成功（日志里有 started）", has("started"))

local dbg = _G.__murdoku_debug
local Murdoku = dbg and dbg.Murdoku
local cur = (Murdoku ~= nil and Murdoku.current ~= nil) and Murdoku.current() or nil
local ctrl = cur and cur.controller or nil
ok(ctrl ~= nil, "拿得到 current.controller（切屏靠它：真实机器上关卡内 screen 是 nil）")
ok(dbg ~= nil and dbg.adapter ~= nil and dbg.adapter.cfg ~= nil
   and dbg.adapter.cfg.prefab_icon ~= nil,
   "cfg.prefab_icon（底板模板索引）配置存在 —— 否则底板根本建不出来，下面全是空转",
   dbg and dbg.adapter and dbg.adapter.cfg and tostring(dbg.adapter.cfg.prefab_icon))
-- ★ 假环境自检：`find("stage")` 是底板那段的**前提**。如果这里拿不到，
--   那一段整个不会跑，后面的断言就会"因为空转"而全绿 —— 假测试最怕这个。
local find_stage, find_home = nil, nil
if dbg ~= nil and dbg.adapter ~= nil and dbg.adapter.find ~= nil then
  pcall(function() find_stage = dbg.adapter:find("stage") end)
  pcall(function() find_home  = dbg.adapter:find("home") end)
end
ok(find_stage == stage_ctrl and find_home == home_ctrl,
   "假环境自检：适配器按名字能找到我们造的 stage / home（底板那段的前提）",
   "stage 命中=" .. tostring(find_stage == stage_ctrl)
   .. "，home 命中=" .. tostring(find_home == home_ctrl))

-- 早期失败时把"被测试代码"最后几行日志摊出来 —— 否则只看到一句 FAIL，还得重跑复现。
local function dump_tail(n, title)
  out("  ---- " .. title .. "（最后 " .. tostring(n) .. " 行）----")
  local from = #logs - n + 1
  if from < 1 then from = 1 end
  for i = from, #logs do
    out("  " .. (logs[i].level == "error" and "[err] " or "[   ] ") .. logs[i].text)
  end
  out("  ---- 日志结束 ----")
end

if ctrl == nil then
  out("\n拿不到 controller，后面的帧驱动无法进行。")
  dump_tail(30, "被测试代码的日志")
  out(string.format("\n%d passed, %d failed", pass, fail))
  os.exit(1)
end

-- ── 2. 关卡内连跑 20 帧：底板只该被建一次 ─────────────────────────────────
--
-- ★ 为什么两个口径都断言（而不是二选一）：
--     · 口径 A「stage 的子控件里新出现的 board.bg」= **控件身份**：
--       它才是用户真正看到的东西（叠 20 块白板 ⇒ 棋盘被压住），而且完全不依赖
--       日志措辞 ⇒ 适合当**回归防线**。但它抓不住旧版：假环境的控件树是普通 Lua 表，
--       旧代码自己写的 `controls["board.bg"] = ob` 会让下一帧的 `find` 命中
--       （真机上 `find` 拿不到刚建的对象，才会有"每帧一块"）。
--     · 口径 B「日志里'建 board.bg'这行出现几次」= **代码路径跑了几次**：
--       旧版这段每帧无脑跑完并打一行 ⇒ 20 帧 20 行（真机日志重复上百次就是它），
--       修好后只在新建那一次打 ⇒ 1 行。**实测：旧版离线就是这一条红。**
--    ⇒ 两条都留着：A 管"控件有没有堆起来"，B 管"这段代码有没有每帧跑"。
out("\n== 2. 关卡内 20 帧：底板只建一次 ==")
-- ★ 真机语义：**关卡内 `controller.screen` 是 nil**，main.lua 里 `… or "level"` 把它归一成 "level"。
ctrl.screen = nil
ctrl.dirty = true
local build_lines_before = count_plate_build_lines()
local lvl_events = 0
local ok3, err3 = pcall(function()
  for _ = 1, 20 do
    OnUpdate(0.5)
    lvl_events = lvl_events + scan_plates("level")
  end
end)
ok(ok3, "关卡内 20 帧 OnUpdate 不抛错", err3)

ok(lvl_events == 1,
   "[1] 口径A：关卡内 20 帧只**新建 1 块**底板（stage 下新出现的 board.bg 个数）",
   "实际新建 " .. tostring(lvl_events) .. " 块（若「只建一次」被改坏，这里会是 20 块）")

local plate_build_lines = count_plate_build_lines() - build_lines_before
ok(plate_build_lines == 1,
   "[1] 口径B：关卡内「建 board.bg」的日志只出现 1 次（旧版每帧都跑 ⇒ 20 次）",
   "出现 " .. tostring(plate_build_lines) .. " 次；原样：" .. tostring(first_plate_build_line()))

local plates_now = plates_under(stage_ctrl)
ok(#plates_now == 1,
   "[1] 口径A：stage 下名为 board.bg 的**活控件只有 1 个**（没有叠一堆）",
   "实际 " .. tostring(#plates_now) .. " 个")

local plate = plate_events[1] and plate_events[1].ctrl or nil
-- 诊断信息：这一段驱动期间到底实例化了多少控件（用来区分"没建"和"建了但没挂上"）
local inst_total, inst_under_stage = 0, 0
for i = 1, #inst_log do
  inst_total = inst_total + 1
  if inst_log[i].parent == stage_ctrl then inst_under_stage = inst_under_stage + 1 end
end
ok(plate ~= nil, "找得到底板控件本身（后面几条断言都要用它）",
   plate and ("名字=" .. tostring(plate.name) .. " 尺寸=" .. tostring(plate.w) .. "x" .. tostring(plate.h)
              .. "；期间实例化 " .. inst_total .. " 个控件（stage 下 " .. inst_under_stage .. " 个）")
        or ("没找到（期间实例化 " .. inst_total .. " 个控件，stage 下 " .. inst_under_stage .. " 个）"))

if plate == nil then
  out("\n底板没被建出来，剩下的断言没法做 —— 先看上面 [1] 的失败原因。")
  out(string.format("\n%d passed, %d failed", pass, fail))
  os.exit(1)
end

-- ── 3. 压到最底层（否则它盖住 25 个格子）─────────────────────────────────
out("\n== 3. 底板必须被压到最底层 ==")
local sib_calls = plate.__sib_calls or {}
local to_bottom = false
for i = 1, #sib_calls do if sib_calls[i] == 0 then to_bottom = true end end
ok(to_bottom or (plate.__first_calls or 0) > 0,
   "[2] 建完被明确要求去最底层（SetSiblingIndex(0) 或 SetAsFirstSibling）",
   "SetSiblingIndex 调用 " .. tostring(#sib_calls) .. " 次"
   .. (sib_calls[1] ~= nil and ("（首个参数 " .. tostring(sib_calls[1]) .. "）") or "")
   .. "，SetAsFirstSibling 调用 " .. tostring(plate.__first_calls or 0) .. " 次")

-- 位置口径：父级子列表里排第 1 ⇒ 在 25 个格子**下面**（官方：数值越大越靠上）
local idx = nil
for i = 1, #stage_ctrl.__kids do if stage_ctrl.__kids[i] == plate then idx = i end end
ok(idx == 1,
   "[2] 底板确实是 stage 的第 1 个子控件（25 个格子都压在它上面）",
   "实际序号 " .. tostring(idx) .. "（stage 共 " .. tostring(#stage_ctrl.__kids) .. " 个子控件）")

-- ── 4. 图必须设在子控件上 ─────────────────────────────────────────────────
out("\n== 4. 配图必须落在子控件上（实例根上设图在真机上静默失败）==")
-- 顺带核对：底板必须是用**图片模板**（cfg.prefab_icon）建的。
-- 用格子模板（cfg.cells.prefab）建出来的东西自带一整套格子子控件
-- （content/wall.*/note/x）⇒ 画面上是"迷你格子"，而且设图打不到图片节点。
local plate_prefab = nil
for i = 1, #inst_log do if inst_log[i].ctrl == plate then plate_prefab = inst_log[i].prefab end end
local ip = icon_prefab()
ok(ip ~= nil and plate_prefab == ip,
   "[3] 底板是用图片模板建的（cfg.prefab_icon），不是格子模板",
   "实际用的模板=" .. tostring(plate_prefab) .. "，cfg.prefab_icon=" .. tostring(ip))

local desc_calls, root_calls, good = {}, {}, nil
for i = 1, #img_calls do
  local call = img_calls[i]
  if call.target == plate then
    root_calls[#root_calls + 1] = call
  elseif is_descendant(plate, call.target) then
    desc_calls[#desc_calls + 1] = call
    if call.ok and call.id ~= nil and call.target.imageId == call.id then good = call end
  end
end
ok(#desc_calls > 0,
   "[3] SetImage 打在了**底板的子控件**上（不是实例根）",
   "子控件上的调用 " .. tostring(#desc_calls) .. " 次；实例根上的调用 " .. tostring(#root_calls) .. " 次")

ok(good ~= nil,
   "[3] 子控件真的设上了图：imageId 回读 == 请求的 id",
   good
     and ("请求 " .. tostring(good.id) .. " → 回读 " .. tostring(good.target.imageId)
          .. "（经子控件 " .. tostring(good.target.name) .. "）")
     or ("没有任何子控件设图成功；实例根回读 imageId=" .. tostring(plate.imageId)
         .. "（真机旧日志就是 设图=false imageId=0）"))

-- ── 5. 切到选关页 ────────────────────────────────────────────────────────
out("\n== 5. 切到选关页：底板必须收起 ==")
ctrl.screen = "select"
ctrl.dirty = true
local ok5, err5 = pcall(function() for _ = 1, 3 do OnUpdate(0.5) end end)
ok(ok5, "选关页 3 帧 OnUpdate 不抛错", err5)
ok(plate.visible == false, "[4] 选关页上底板 visible=false",
   "visible=" .. tostring(plate.visible) .. "（SetVisible 共被调用 "
   .. tostring(plate.__vis_calls or 0) .. " 次）")

-- ── 6. 切到主页 ──────────────────────────────────────────────────────────
out("\n== 6. 切到主页：底板必须仍然收起 ==")
ctrl.screen = "home"
ctrl.dirty = true
local ok6, err6 = pcall(function() for _ = 1, 3 do OnUpdate(0.5) end end)
ok(ok6, "主页 3 帧 OnUpdate 不抛错", err6)
ok(plate.visible == false, "[4] 主页上底板 visible=false",
   "visible=" .. tostring(plate.visible))

-- ── 7. 回到关卡：重新可见，但**不许重建** ────────────────────────────────
out("\n== 7. 回到关卡内：重新可见，且沿用原来那一块（不重建）==")
ctrl.screen = nil
ctrl.dirty = true
local back_events = 0
local ok7, err7 = pcall(function()
  for _ = 1, 3 do
    OnUpdate(0.5)
    back_events = back_events + scan_plates("level-again")
  end
end)
ok(ok7, "回到关卡后 3 帧 OnUpdate 不抛错", err7)
ok(plate.visible == true, "[4] 回到关卡内底板重新可见 visible=true",
   "visible=" .. tostring(plate.visible))
ok(back_events == 0, "[1] 回到关卡内**没有重建**底板（沿用原来那块）",
   "这 3 帧新建 " .. tostring(back_events) .. " 块")

-- 整场汇总：一轮切屏下来，底板总共只该建过 1 块、活着的也只有 1 个
ok(#plate_events == 1, "[1] 整场（关卡→选关→主页→关卡）总共只建过 1 块底板",
   "共 " .. tostring(#plate_events) .. " 块："
   .. table.concat((function()
        local t = {}
        for i = 1, #plate_events do t[i] = plate_events[i].phase end
        return t
      end)(), " / "))
ok(kids_of_stage_named_board_bg() == 1, "[1] 一轮切屏之后 stage 下仍只有 1 块底板",
   "实际 " .. tostring(kids_of_stage_named_board_bg()) .. " 块")

-- ── 8. 不许有运行时报错（防"修出来的新 bug"）─────────────────────────────
out("\n== 8. 全程没有运行时报错 ==")
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
ok(#bad == 0, "[5] 没有 printerr 级的 attempt to / nil value / bad argument",
   #bad == 0 and "(0 条)" or ("第一条：" .. tostring(bad[1])))

out(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
