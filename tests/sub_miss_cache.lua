--[[----------------------------------------------------------------------------
  tests/sub_miss_cache.lua —— `Adapter:sub` 的"按代记忆未命中"契约

  ★ 为什么要这个文件（★ 这是我本轮最容易把老 bug 弄回来的地方 ✗）：
     2026-09-25 那个 bug ✗：`sub` 查不到时写 `self.subs[key] = false`
       ⇒ **跨代永久负缓存** ⇒ UI 就绪之后**再也取不到** ⇒ 表现层静默失效 ✓
       （项目为此排查了一整天 ✓ 所以 `sub` 的注释第一句就是"只缓存命中" ✓）

     2026-10-12 性能优化 ✓：未命中**仍然返回 nil** ✓ 但记下**代数戳**
       ⇒ 同一代内不再重复三级尝试 ✓（实测：一次 render 的 `GetChild` 840 → 0 ✓）
       ⚠️ 代价是**又出现了"记住取不到"**这种形状 ✗ ⇒ ★ 必须钉死它**不跨代** ✓✓

  ★ 本文件钉的契约（4 条 ✓）：
     [1] 未命中**第一次**会走三级尝试（返回 nil ✓）
     [2] 同一代内**第二次**查同一个键 ⇒ **不再走引擎**（`GetChild` 不再被调 ✓）
     [3] ★★ **换代之后必须重试** ✗✓ —— 这是防"当年那个 bug 回来"的**核心断言** ✓
     [4] 子控件**真的存在**时 ⇒ 照旧返回它 ✓ 且走命中缓存 ✓（优化不影响正常路径 ✓）

  跑法：lua tests/sub_miss_cache.lua
  前置：lua tools/bundle_client_script.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/sub_miss_cache.lua"
local root = here:gsub("tests[/\\]sub_miss_cache%.lua$", "")
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
    out("  [PASS] " .. label .. (detail and ("   " .. detail) or ""))
  else
    fail = fail + 1
    out("  [FAIL] " .. label .. (detail and ("   " .. detail) or ""))
  end
end

-- ── 假引擎 ──────────────────────────────────────────────────────────────────
local CNT = { getchild = 0 }
local attach, make_ctrl
do
  attach = function(parent, c)
    parent.__kids = parent.__kids or {}
    parent.__kids[#parent.__kids + 1] = c
    c.__parent = parent
    return c
  end
  local PROTO = {}
  make_ctrl = function(name, kind)
    local c = { name = name, kind = kind or "container", visible = true, active = true,
                __kids = {}, pivotX = 0.5, pivotY = 0.5, w = 0, h = 0, ax = 0, ay = 0 }
    return setmetatable(c, { __index = function(_, k) return PROTO[k] end })
  end
  local function def(nm, fn) PROTO[nm] = fn end
  def("GetChildren", function(self) return self.__kids end)
  def("GetChild", function(self, key)
    CNT.getchild = CNT.getchild + 1          -- ★ 记账点：走引擎按名取子控件
    if type(key) == "number" then return self.__kids[key + 1] end
    for _, k in ipairs(self.__kids) do if k.name == key then return k end end
    return nil
  end)
  def("GetChildCount", function(self) return #self.__kids end)
  def("GetParent", function(self) return self.__parent end)
  def("FindChild", function(self, p)
    CNT.getchild = CNT.getchild + 1
    local head, tail = tostring(p):match("^([^%./]+)[%./](.+)$")
    if head == nil then return nil end
    local mid = nil
    for _, k in ipairs(self.__kids) do if k.name == head then mid = k break end end
    if mid == nil then return nil end
    for _, k in ipairs(mid.__kids or {}) do if k.name == tail then return k end end
    return nil
  end)
  def("SetVisible", function(self, v) self.visible = v end)
  def("SetActive", function(self, v) self.active = v end)
  def("SetSizeDelta", function(self, w, h) self.w, self.h = w, h end)
  def("GetSizeDelta", function(self) return self.w or 0, self.h or 0 end)
  def("SetAnchoredPosition", function(self, x, y) self.ax, self.ay = x, y end)
  def("GetAnchoredPosition", function(self) return self.ax or 0, self.ay or 0 end)
  def("SetPivot", function(self, x, y) self.pivotX, self.pivotY = x, y end)
  def("SetAnchorMin", function() end)
  def("SetAnchorMax", function() end)
  def("SetLocalScale", function() end)
  def("SetAlpha", function() end)
  def("AddCursorEventListener", function() end)
  def("SetImage", function() return false end)
  def("SetSiblingIndex", function() return true end)
  def("GetSiblingIndex", function() return 0 end)
  def("SetAsFirstSibling", function() return true end)
  def("GetUIPos", function(self) return self.ax or 0, self.ay or 0 end)
  def("SetText", function() end)
end

-- ★ 树里**只有** `content`，**没有** `wall.up` ⇒ 用它钉"未命中" ✓
local tree, cell11
do
  local rt = make_ctrl("root")
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right", "actions", "modal", "intro" }) do
    attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage"))
  local cell = make_ctrl("cell.1.1", "button")
  cell11 = cell
  local content = make_ctrl("content")
  attach(content, make_ctrl("face"))       -- ★ content 下**只**有 face（没有 wall.* ✓）
  attach(cell, content)
  attach(st, cell)
  attach(st, make_ctrl("selbar"))
  local board = attach(rt, make_ctrl("board"))
  attach(board, make_ctrl("board.bg"))
  local cl = attach(rt, make_ctrl("clues"))
  attach(cl, make_ctrl("clues.bg"))
  tree = { rt }
end

local function b(_) end
_G.game = {
  GetUICanvasSize = function() return 1600.0, 900.0 end,
  GetClientUIRoots = function() return tree end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = make_ctrl("(未命名)", "button"); c.prefabIndex = prefab
    attach(parent, c); return c
  end,
  DestroyClientUIControl = b, GetCursorUIPos = function() return 0, 0 end,
  GetDevice = function() return "KeyboardAndMouse" end, PrintClientUITree = b,
  ServerSignal = function() local s = {} s.AddInt=b s.AddFloat=b s.AddString=b s.AddBool=b s.SendSignal=b return s end,
  PlayAudio2D = b, GetText = function() return "" end,
}
_G.script = { EnableUpdate=b, RegisterServerSignalHandler=b,
  RegisterCustomVariableChangedHandler=b, Invoke=b, GetParam = function() return nil end }
_G.Enum = {
  CursorEventType = { CursorClick="CursorClick", CursorClickDown="CursorClickDown",
    CursorClickUp="CursorClickUp", CursorDrag="CursorDrag" },
  KeyEventType = { KeyDown="KeyDown", KeyUp="KeyUp" },
}

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
if not pcall(chunk) then out("  执行产物抛错"); os.exit(1) end
pcall(OnInit); pcall(OnStart)
local dbg = _G.__murdoku_debug
local cur = dbg and dbg.Murdoku and dbg.Murdoku.current()
if cur == nil then out("  开局没成功"); os.exit(2) end
local ad = cur.adapter

-- 产物自检：这个特性在不在（★ 否则量的是旧产物 ⇒ 假绿 ✗）
do
  local fh = io.open(SCRIPT_PATH, "rb"); local body = fh:read("a"); fh:close()
  if body:find("_sub_miss", 1, true) == nil then
    out("  ✗ 产物里没有 `_sub_miss` ⇒ 旧产物 ⇒ 直接退出（不伪造结论）")
    os.exit(1)
  end
  out("  产物已含 `_sub_miss`（按代记忆未命中 ✓）")
end
out("")

local GEN0 = ad._lookup_gen
out(string.format("  起始代数 `_lookup_gen` = %s", tostring(GEN0)))
out("")

-- ════════════════════════════════════════════════════════════════════════════
-- [1] 未命中的第一次：走三级尝试
--   ⚠️ ★ 用一个**冷键** ✓ —— 启动过程本身就会查一批 `cell.*.wall.*` 并记下未命中 ✗
--      ⇒ 若用 `wall.up` 量"第一次"，它**已经被开机那一趟记过了** ⇒ 计数会是 0 ✓
--        （★ 这不是 bug ✗ 而是本特性生效的**证据** ✓ —— 实测里那 840 笔正是这么省掉的 ✓）
--      ⇒ 所以先**换代**把记忆清掉 ✓ 再量 ✓
-- ════════════════════════════════════════════════════════════════════════════
out("== [1] 查一个**不存在**的子控件（`cell.1.1` 的 `door.up`，冷键）==")
ad:invalidate_lookups("测试：清掉开机那趟的记忆，好量'第一次'")
local GEN0b = ad._lookup_gen
CNT.getchild = 0
local r1 = ad:sub("cell.1.1", "door.up")
local n1 = CNT.getchild
ok(r1 == nil, "第 1 次：返回 nil（★ 「下次还会重试」这条语义不变 ✓）", "返回 " .. tostring(r1))
ok(n1 > 0, "第 1 次：确实走了引擎（三级尝试 ✓）", "GetChild 被调 " .. tostring(n1) .. " 次")

-- ════════════════════════════════════════════════════════════════════════════
-- [2] 同一代内第二次：不再走引擎
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [2] 同一代内**再查一次**同一个键 ==")
CNT.getchild = 0
local r2 = ad:sub("cell.1.1", "door.up")
local n2 = CNT.getchild
ok(r2 == nil, "第 2 次：仍然返回 nil（语义不变 ✓）", "返回 " .. tostring(r2))
ok(n2 == 0, "★★ 第 2 次：**一次引擎调用都没有**（按代记住了 ✓ 这就是省下来的那 840 笔 ✓）",
  "GetChild 被调 " .. tostring(n2) .. " 次")

-- 连查 50 次也不该有引擎调用
CNT.getchild = 0
for _ = 1, 50 do ad:sub("cell.1.1", "door.up") end
ok(CNT.getchild == 0, "★ 连查 50 次：依然 0 次引擎调用", "GetChild 被调 " .. tostring(CNT.getchild) .. " 次")

-- ════════════════════════════════════════════════════════════════════════════
-- [3] ★★★ 核心断言：换代之后**必须重试**（防当年那个 bug 回来 ✗）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [3] ★★★ 换代（`invalidate_lookups`）之后**必须重新尝试** ==")
ad:invalidate_lookups("测试：模拟切屏/换关")
local GEN1 = ad._lookup_gen
ok(GEN1 ~= GEN0b, "换代确实推进了 `_lookup_gen`", tostring(GEN0b) .. " → " .. tostring(GEN1))

-- ★ 关键场景：换代之后，那个子控件**出现了** ⇒ 必须能取到 ✓
--   （当年那个 bug 的表现正是：它出现了，却因为"记住取不到"而永远拿不到 ✓）
do
  local content = nil
  for _, k in ipairs(cell11.__kids) do if k.name == "content" then content = k end end
  attach(content, make_ctrl("door.up"))          -- ★ 现在它存在了 ✓
  CNT.getchild = 0
  local r3 = ad:sub("cell.1.1", "door.up")
  ok(r3 ~= nil,
    "★★★ 换代后**立刻能取到**新出现的子控件（★ 这条一红 ⇒ 「永久负缓存」回来了 ✗）",
    r3 and ("取到 " .. tostring(r3.name)) or "仍然是 nil ✗")
  ok(CNT.getchild > 0, "★ 换代后确实**重新走了引擎**（没有被旧记忆挡住 ✓）",
    "GetChild 被调 " .. tostring(CNT.getchild) .. " 次")
end

-- ════════════════════════════════════════════════════════════════════════════
-- [4] 存在的子控件照旧（走命中缓存 ✓）
-- ════════════════════════════════════════════════════════════════════════════
out("")
out("== [4] 存在的子控件照旧取得到 ==")
do
  -- ⚠️ 必须用**树里真的存在**的那个 ✓ —— [3] 里把 `door.up` 加进 `content` 了 ✓
  --   （我第一次这里写的是 `wall.up` ✗ ⇒ 它本来就不存在 ⇒ 两次都是 nil ✗
  --    而 `a ~= nil and b2 ~= nil and a == b2` 对"两个都是 nil"**也成立** ✗
  --    ⇒ 断言形状选错了 ✓ 现在改成"先钉存在、再钉同一个" ✓）
  local a = ad:sub("cell.1.1", "door.up")
  ok(a ~= nil, "★ 存在的子控件取得到 ✓", tostring(a and a.name))
  CNT.getchild = 0
  local b2 = ad:sub("cell.1.1", "door.up")
  ok(a ~= nil and b2 ~= nil and rawequal(a, b2),
    "两次拿到**同一个**对象 ✓（走 `self.subs` 命中 ✓）", tostring(rawequal(a, b2)))
  ok(CNT.getchild == 0, "第二次 0 次引擎调用（命中缓存 ✓）", tostring(CNT.getchild) .. " 次")
  -- 中间容器那一层也照旧（content/face ✓）
  ok(ad:sub("cell.1.1", "face") ~= nil, "中间容器里的 `face` 照旧取得到 ✓（三级尝试的第 ② 级 ✓）")
end

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
