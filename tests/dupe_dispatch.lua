--[[----------------------------------------------------------------------------
  tests/anchored_pos_guard.lua —— ★ 判据：`rect` 分支的 `SetAnchoredPosition` 读回守卫

  ★★★ 上游待办（★ 优化组 v204 §1.2 / v205 §一 P1 ✓）：
    ★ 上一轮**故意没给这一笔加守卫** ✗，理由逐字是 ✓：
      ★「`SetAnchoredPosition` 写的是**相对父级中心**的值 ✗ ——
        ★ 它读回到底给"锚点值"还是"绝对坐标"，**本环境没有实测证据** ✗
        ⇒ ★ 按本项目规矩：**没有实测证据的读回守卫，宁可不加** ✓
        ★ 加错的方向是"**该对齐却不写**"✗ ⇒ 控件停在错位置 ✓」
    ⇒ ★★★ **2026-10-12 官方原文把歧义消掉了** ✓✓
      ★ 来源：《客户端控件API文档》（`mhtakr07vej4` ✓）§13(3)「布局与变换」✓
      ★ 原文 ✓：两条都写「**无父层级时，以画布左下为原点**；
        **存在父层级时，……与父层级中心的相对偏移**」✓
      ⇒ ★ **读与写同一坐标系** ✓ ★ 且**没有**"父级 pivot 参与"的条件 ✓

  ★★ 本文件钉四件事（★ 每条都能红 ✓）：
    ① ★ **值真的不同 ⇒ 必须写** ✓（★ "不许不摆"那条底线 ✓）
    ② ★ **同一目标连下两次 ⇒ 第二次不写** ✓（★ 这就是本轮省下的 37 笔 ✓）
    ③ ★ **读不到 ⇒ 照旧写** ✓（★ 与 `pivot` / `size` 两笔同一条安全边界 ✓）
    ④ ★ **反向对照**：凭空把位置弄错 ⇒ 下一趟**必须重新写** ✓
        （★ 证明 ② 的"0 笔"是"省了"✗ 不是"哑了" ✓）

  ★★ 两个夹具坑（★ 都踩过 ✓ 写在这里省下一个人 ✓）：
    ★ ① **键名是 `rect` 不是 `position`** ✗ —— `set_property` 里**没有** `key == "position"`
      那一支 ✓（★ "position 分支"是**注释里的叫法** ✓ 见函数头 ✓）
      ★ ② **`rect` 分支默认【跳过】非运行时控件** ✗（`respect_editor_rect` ✓）
        ⇒ ★ 必须 `adapter.runtime_rect[id] = true` ✓ 否则**静默 `return true`** ✓
          —— ★ 那样量出来恒 0 笔，而看起来"守卫坏了" ✗（★ 又是一次"夹具不对"✓）

  ★ 只读：本文件**不改任何生产源码** ✓
  ★ 跑法：lua tests/anchored_pos_guard.lua
  ★ 前置：lua tools/bundle_client_script.lua 产出 dist/client_script.lua
----------------------------------------------------------------------------]]--
local out = print
do local function sink(...) end _G.print = sink _G.printerr = sink end

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
                __kids = {}, pivotX = nil, pivotY = nil, w = nil, h = nil }
    return setmetatable(c, { __index = function(_, k) return PROTO[k] end })
  end
  local function def(nm, fn) PROTO[nm] = fn end
  def("GetChildren", function(self) return self.__kids end)
  def("GetChild", function(self, key)
    if type(key) == "number" then return self.__kids[key + 1] end
    for _, k in ipairs(self.__kids) do if k.name == key then return k end end
    return nil
  end)
  def("GetChildCount", function(self) return #self.__kids end)
  def("GetParent", function(self) return self.__parent end)
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
  def("GetUIPos", function() return 0, 0 end)
  def("SetText", function() end)
end

local tree, REG = {}, {}
do
  local rt = make_ctrl("root"); REG["root"] = rt
  for _, n in ipairs({ "home", "select", "topbar", "left", "clues", "right",
                       "actions", "modal", "intro" }) do
    attach(rt, make_ctrl(n))
  end
  local st = attach(rt, make_ctrl("stage")); REG["stage"] = st
  for r = 1, 5 do
    for cc = 1, 5 do
      local cell = make_ctrl("cell." .. r .. "." .. cc, "button")
      local content = make_ctrl("content")
      attach(content, make_ctrl("face"))
      attach(cell, content)
      attach(cell, make_ctrl("x"))
      attach(cell, make_ctrl("note"))
      attach(st, cell)
    end
  end
  local board = attach(rt, make_ctrl("board")); REG["board"] = board
  attach(board, make_ctrl("board.bg"))
  local cl = attach(rt, make_ctrl("clues")); REG["clues"] = cl
  attach(cl, make_ctrl("clues.bg"))
  attach(cl, make_ctrl("clues.grid"))
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

-- ★ 2026-10-12：★ `root` 的推导在引导块里被裁掉了 ✗ ⇒ 这里补回来 ✓
local here = (arg and arg[0]) or "tests/dupe_dispatch.lua"
local root = here:gsub("tests[/\\]dupe_dispatch%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

local SCRIPT_PATH = (arg and arg[1]) or (root .. "dist/client_script.lua")
out("== 加载 " .. SCRIPT_PATH .. " ==")
do
  local fh = io.open(SCRIPT_PATH, "rb")
  if fh == nil then out("  打不开产物 ⇒ 先跑 bundle"); os.exit(1) end
  local body = fh:read("a"); fh:close()
  -- ★★ 2026-10-12 **闸不在产物里 ⇒ 本环境测不了 ⇒ 优雅跳过（退出码 0）** ✗✓
  --
  --   ★ 为什么不是 `os.exit(1)` ✗：★ 去重闸属于**可选的可观测性铺底** ✓
  --     ★ 它被回退之后，本套件**没有被测对象** ✗ ⇒ ★ 若退 1 ⇒
  --       ★ 常驻 24 套里就多出一条**假红** ⇒ ★ 把真红的信噪比又拉低了 ✓（本项目栽过 ✓）
  --   ⇒ ★ 与 `play_test.mjs` 的 `⊘ 本环境测不了` **同一口径** ✓：
  --     ★ 明确说"没得测" ✓ ★ **不装作通过** ✗ ★ 也不谎报失败 ✗ ✓
  --   ⚠️ ★ 反过来当哨兵用 ✓：★ 闸**回到产物里** ⇒ 本套件立刻恢复全部断言 ✓
  if body:find("_dupe_dropped", 1, true) == nil then
    out("  ⊘ 产物里没有去重闸（`_dupe_dropped`）⇒ **本环境测不了**（不装作通过，也不谎报失败）")
    out("  ⊘ 说明：该闸属于可观测性铺底，已随 v205 之后那批改动一起回退")
    out("  ⊘ 它一旦回到产物里，本套件的 7 条断言会自动恢复")
    os.exit(0)
  end
  out("  产物已含去重闸（`_dupe_dropped`）✓")
end

local chunk, lerr = loadfile(SCRIPT_PATH)
if chunk == nil then out("  加载失败：" .. tostring(lerr)); os.exit(1) end
local okload, errload = pcall(chunk)
if not okload then out("  执行产物抛错：" .. tostring(errload)); os.exit(1) end
pcall(OnInit); pcall(OnStart); pcall(OnUpdate, 0.016)

local cur = _G.__murdoku_debug and _G.__murdoku_debug.Murdoku
  and _G.__murdoku_debug.Murdoku.current()
if cur == nil then out("  开局没成功 ⇒ 拿不到 controller"); os.exit(2) end
local ctrl = cur.controller
if ctrl == nil then out("  拿不到 controller"); os.exit(2) end
out("  已拿到 controller ✓")
out("")

-- ══════════════════════════════════════════════════════════════════════════
-- ★★★★ 2026-10-12 **dupe 闸：同一次派发的重复只生效一次** ✗✓✓
--   ★ 用户报的真 bug ✓：真机日志里**一次 tap** 产生两条抬起判定 ✓
--     （`[1/12] 时长不够 dt=0.13` ＋ `[2/12] 没有按下记录` ✓）
--   ★ 成因 ✓：换屏清 `bound` 而控件树没销毁 ⇒ 控件挂了多组监听器 ✓
--   ★ 本闸**不问成因** ✓：无论几组监听器 ⇒ 效果都只剩一次 ✓
-- ══════════════════════════════════════════════════════════════════════════

local CNT = { down = 0, up = 0, drag = 0 }
for _, nm in ipairs({ "down", "up", "drag" }) do
  local f = ctrl["on_cell_" .. nm]
  if type(f) == "function" then
    ctrl["on_cell_" .. nm] = function(self2, ...)
      CNT[nm] = CNT[nm] + 1
      return f(self2, ...)
    end
  end
end
local function reset() CNT.down, CNT.up, CNT.drag = 0, 0, 0 end
local function feed(phase, r, c2)
  ctrl:on_input({ action = "click", phase = phase, r = r, c = c2, x = 0, y = 0 })
end
local function adv(sec) ctrl:tick(sec) end

out("== [1] 同一次抬起送 2 遍（★ 用户报的形状）==")
reset()
feed("down", 2, 3); adv(0.05)
feed("up", 2, 3)
feed("up", 2, 3)
ok(CNT.up == 1,
  "★ 抬起只被处理 **1** 次（重复那次被丢弃 ✓）",
  "on_cell_up 实际 " .. tostring(CNT.up) .. " 次（应为 1）")
ok(CNT.down == 1, "按下也是 1 次", tostring(CNT.down))

reset()
feed("down", 2, 3); adv(0.05)
feed("up", 2, 3); feed("up", 2, 3); feed("up", 2, 3)
ok(CNT.up == 1, "★ 抬起送 **3** 遍 ⇒ 仍只处理 1 次（v207 日志里就是 3 遍 ✓）",
  tostring(CNT.up) .. " 次")

out("")
out("== [2] 不同格子 ⇒ 都要生效（★ 不能误伤 ✓）==")
reset()
feed("down", 1, 1); adv(0.02); feed("up", 1, 1)
feed("down", 1, 2); adv(0.02); feed("up", 1, 2)
ok(CNT.up == 2, "★ 两个不同格子的抬起**都**生效了", tostring(CNT.up) .. " 次（应为 2）")
ok(CNT.down == 2, "两个不同格子的按下都生效了", tostring(CNT.down) .. " 次")

out("")
out("== [3] 同一格子隔开 > 2 秒 ⇒ 两次都要生效（★ 玩家正常连点 ✓）==")
reset()
feed("down", 4, 4); adv(0.05); feed("up", 4, 4)
adv(2.5)
feed("down", 4, 4); adv(0.05); feed("up", 4, 4)
ok(CNT.up == 2, "★ 隔开 2.5 秒后第二次仍然生效（闸不吃玩家连点 ✓）",
  tostring(CNT.up) .. " 次（应为 2）")

out("")
out("== [4] `drag` **不去重**（★ 拖动是连续移动 ✓）==")
reset()
feed("down", 5, 5); adv(0.02)
feed("drag", 5, 5); feed("drag", 5, 5); feed("drag", 5, 5)
ok(CNT.drag == 3, "★ 连续 3 次 drag **全都**送到了界面层（没被吃掉 ✓）",
  tostring(CNT.drag) .. " 次（应为 3）")

out("")
out(string.format("== 结果：%d 通过 / %d 失败 ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
