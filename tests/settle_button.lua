--[[----------------------------------------------------------------------------
  tests/settle_button.lua —— 主页/选关左下角那颗「结算」（2026-10-15 用户要求）

  ★★ 用户原话 ✓：
    「**把原来四个方块删掉，然后在首页和选关界面左下角也加一个结算按钮，
      不接存档线，只接结算**」✓

  本用例钉住三件事（★ 每一条都能红 ✓）：
    ① ★ **主页**与**选关**两屏的规划里都要有 `settle.btn` ✓（★ 关卡内**不许有** ✗）
    ② ★ 它的事件必须是 **`settle_only`** ✗ —— ★ 不是 `exit_menu_settle`（那颗会先存档 ✓）
    ③ ★★ **"不接存档线"** = ★ 触发它**只**调 `on_settle_only` ✓
       ★ **绝不调 `on_save`** ✗（★ 这一条是用户明确排除的东西 ✓）

  ★ 为什么要单独一条用例 ✗：★ "只结算、不存档"这件事**在屏幕上完全看不出来** ✓
    （★ 点了都有反应 ✓ 差别只在**存档有没有被写** ✓）
    ⇒ ★ 没有用例守着 ⇒ 将来谁把两个分支合并了，**没人会发现** ✓（本项目的老形状 ✓）

  跑法：lua tests/settle_button.lua
------------------------------------------------------------------------------]]--

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local Fx   = require("tests.fixtures")

local pass, fail = 0, 0
local function ok(cond, label, detail)
  if cond then
    pass = pass + 1
    print("  [PASS] " .. label .. (detail and ("   " .. detail) or ""))
  else
    fail = fail + 1
    print("  [FAIL] " .. label .. (detail and ("   " .. detail) or ""))
  end
end

local levels = {
  { id = "a", name = "案件 A", size = { rows = 5, cols = 5 }, suspects = {} },
  { id = "b", name = "案件 B", size = { rows = 5, cols = 5 }, suspects = {} },
}

local function make(screen, opts)
  opts = opts or {}
  opts.skip_intro = true
  opts.levels = levels
  opts.screen = screen
  return UIC.new(Core.new(Fx.clue_level_5x5()), opts)
end

local function plan_of(c, screen)
  c.screen = screen
  local nodes = c:build_layout()
  local by = {}
  for i = 1, #nodes do by[nodes[i].id] = nodes[i] end
  return by
end

----------------------------------------------------------------------------
print("== 1. 两个屏幕都要有「结算」，关卡内不许有 ==")
do
  local byHome = plan_of(make("home"), "home")
  local bySel  = plan_of(make("select"), "select")
  local byLvl  = plan_of(make(nil), nil)

  ok(byHome["settle.btn"] ~= nil and byHome["settle.btn"].visible == true,
    "主页有 settle.btn 且可见",
    byHome["settle.btn"] and ("visible = " .. tostring(byHome["settle.btn"].visible)) or "规划里没有")
  ok(bySel["settle.btn"] ~= nil and bySel["settle.btn"].visible == true,
    "选关屏有 settle.btn 且可见",
    bySel["settle.btn"] and ("visible = " .. tostring(bySel["settle.btn"].visible)) or "规划里没有")
  ok(byLvl["settle.btn"] == nil,
    "★ 关卡内**不进规划**（由 render 的差集收口藏掉 ✓）",
    byLvl["settle.btn"] and "★ 关卡内也在规划里 ✗" or "规划里没有 ✓")

  -- ★ 左下角 ✓（设计空间 1920×1080、左上原点 ✓）
  local n = byHome["settle.btn"]
  if n ~= nil then
    -- ★ 2026-10-16：几何改成**与 `hex.hint`（提示）同款同位置** ✓（用户指令① ✓）
    --   存档口径 pos[683,−279] size[70×70] ⇒ 反算设计空间 (1744.6, 298.8) 84×84 ✓
    ok(math.abs(n.rect.x - 1744.6) < 0.5 and math.abs(n.rect.y - 298.8) < 0.5
       and math.abs(n.rect.w - 84) < 0.5 and math.abs(n.rect.h - 84) < 0.5,
      "★ 与「提示」(hex.hint) 同一个位置与同款尺寸（1744.6, 298.8, 84×84 ✓）",
      string.format("实测 %.1f,%.1f %.1f×%.1f", n.rect.x, n.rect.y, n.rect.w, n.rect.h))
    ok(n.text == "结算", "按钮文字 = 结算", tostring(n.text))
    ok(n.kind == "button", "kind = button（★ 走预设按钮原生点击那条路 ✓ 不需要命中层 ✓）",
      tostring(n.kind))
    ok(n.parent == "root", "父级 = root", tostring(n.parent))
  end
end

----------------------------------------------------------------------------
print("")
print("== 2. 事件必须是 settle_only（不是 exit_menu_settle）==")
do
  local bySel = plan_of(make("select"), "select")
  local ev = bySel["settle.btn"] and bySel["settle.btn"].event or nil
  ok(ev ~= nil and ev.action == "settle_only",
    "settle.btn 绑的是 settle_only", ev and ("实测 = " .. tostring(ev.action)) or "没有 event")
  ok(ev == nil or ev.action ~= "exit_menu_settle",
    "★ 不是 `exit_menu_settle`（那颗会**先存档**再结算 ✗）")
end

----------------------------------------------------------------------------
print("")
print("== 3. ★★「不接存档线」：触发它只结算、绝不存档 ==")
do
  local calls = { save = 0, settle = 0, settle_only = 0 }
  local c = make("home", {
    on_save        = function() calls.save = calls.save + 1 end,
    on_settle      = function() calls.settle = calls.settle + 1 end,
    on_settle_only = function() calls.settle_only = calls.settle_only + 1 end,
  })
  c:on_input({ action = "settle_only" })
  ok(calls.settle_only == 1, "① on_settle_only 被调了 1 次", "实测 " .. calls.settle_only)
  ok(calls.save == 0, "② ★★ on_save **一次都没被调**（= 不接存档线 ✓）", "实测 " .. calls.save)
  ok(calls.settle == 0, "③ 也没走「存档＋结算」那一个回调（两者语义不同 ✓）", "实测 " .. calls.settle)
end

----------------------------------------------------------------------------
print("")
print("== 4. 对照：弹窗里那颗「结算」**仍然是先存档再结算**（没被改坏 ✓）==")
do
  local calls = { save = 0, settle = 0 }
  local c = make("home", {
    on_save   = function() calls.save = calls.save + 1 end,
    on_settle = function() calls.settle = calls.settle + 1 end,
  })
  c:on_input({ action = "exit_menu_settle" })
  ok(calls.save == 1 and calls.settle == 1,
    "exit_menu_settle ⇒ on_save 1 次 ＋ on_settle 1 次",
    "实测 save=" .. calls.save .. " settle=" .. calls.settle)
end

----------------------------------------------------------------------------
print("")
print("== 5. 没有回调时：静默不做事（不留半截副作用 ✓）==")
do
  local c = make("home", {})            -- 三个回调都不给
  local okc, err = pcall(function() c:on_input({ action = "settle_only" }) end)
  ok(okc, "没有 on_settle_only 也不抛错", tostring(err))
end

----------------------------------------------------------------------------
print("")
print("== 6. ★★ 主页那颗「选关」按钮【一个字没动】（用户 2026-10-15 明确担心过这一点 ✓）==")
--
--   ★★★ 为什么单独一节 ✗（★ 这是用户的**原话** ✓）：
--     「**我是让你在主页和选关界面左下角加按钮，不是让你把选关按钮换掉**」✓
--   ★ 背景 ✓：★ 上一轮把脚本运行时建的 `selbar`/`selbtn.1..4` **停掉了** ✓
--     （★ 用户随后确认：「**删的就是 selbtn 那四个 —— 卡片留着当选关入口**」✓）
--     ⇒ ★ 但"主页那颗「选关」"是**另一颗控件** ✓（`home.select`，存档里就有 ✓）
--     ⇒ ★★ 两件事**必须分开钉死** ✗ —— 否则下次谁再动 `widgets` 或加按钮时，
--        ★ **把主页那颗顺手写坏/盖住，没有任何检查会响** ✓
do
  local by = plan_of(make("home"), "home")
  local sel = by["home.select"]
  ok(sel ~= nil, "`home.select`（主页「选关」）仍在规划里 ✓")
  if sel ~= nil then
    ok(sel.visible == true, "它仍然可见 ✓", "visible = " .. tostring(sel.visible))
    ok(sel.text == "选关", "文字仍是「选关」✓", tostring(sel.text))
    ok(sel.event ~= nil and sel.event.action == "levelselect",
      "事件仍是 `levelselect` ✓（点它还能进选关 ✓）",
      sel.event and ("实测 = " .. tostring(sel.event.action)) or "没有 event")
    -- ★ 新增的那颗**不许压住**它 ✓（位置/大小将来谁改了，这里立刻响 ✓）
    local b = by["settle.btn"]
    if b ~= nil then
      local a1x, a1y, a2x, a2y = sel.rect.x, sel.rect.y, sel.rect.x + sel.rect.w, sel.rect.y + sel.rect.h
      local b1x, b1y, b2x, b2y = b.rect.x, b.rect.y, b.rect.x + b.rect.w, b.rect.y + b.rect.h
      local overlap = not (a2x <= b1x or b2x <= a1x or a2y <= b1y or b2y <= a1y)
      ok(not overlap,
        "★ 「结算」按钮**没有压住**「选关」（右上角 vs 中列 ✓）",
        string.format("home.select=%.0f,%.0f %.0f×%.0f  settle.btn=%.1f,%.1f %.1f×%.1f",
          sel.rect.x, sel.rect.y, sel.rect.w, sel.rect.h, b.rect.x, b.rect.y, b.rect.w, b.rect.h))
    end
  end
end

---------------------------------------------------------------------------
-- ★★★★★★★★ 2026-10-15 **§7：那一条"看不出来"的判据 —— 不在本屏时必须交出射线** ✗✓✓
--
--   ★★ 为什么必须有用例（这一条**在屏幕上看不出来** ✗）：
--     · `settle.btn` 是**存档里的实体按钮** ✓ ⇒ 只要没人关它，它**每一帧都能被点到** ✓
--     · 而这份规划**只在主页/选关包含它** ✓ ⇒ 关卡内它**根本不进 `nodes`** ✓
--       ⇒ ★ 屏幕层 `apply_screen_hide` 也**看不到它** ✗ ⇒ **没有任何人负责关掉它的交互** ✓
--     · ★★ 用户报的现象（原话）：「**全屏都被一个能触发结算的东西占满了**」✓
--       我在模拟器上复现到同一件事：点 (91,79) 与 (1200,700) **都命中 `settle.btn`** ✓
--     ⇒ ★ "它该不该吃这一帧的点击"这件事，**只有规划里那个 `raycast` 字段说得清** ✓
--
--   ★★★★ 2026-10-16 **本段按用户那句话重写** ✓（原话 ✓）：
--     「**其实应该算一颗，它们位置一样，功能一样，没有必要建两颗还要分别隐藏，
--       建一颗只在进入关卡后隐藏就行了**」✓✓
--   ⇒ ★ 所以判据也换成**用户那句话的形状** ✓：
--     ★ ① 任何屏幕上，`settle.btn` **只许出现一次** ✓（不许 `if/else` 各 push 一条 ✗）
--     ★ ② 主页/选关 ⇒ `visible = true` ＋ `raycast = true` ✓（整个开着 ✓）
--     ★ ③ 其它任何屏 ⇒ **两个都 false** ✓（★ 不再靠"不在规划里"这种间接说法 ✓）
print("")
print("== 7. ★ 一颗按钮、一个开关：进关卡就整个关掉（用户 2026-10-16 定形）==")
do
  local screens = { "home", "select", nil, "board", "result", "exit_menu", "howto", "intro", "share" }
  local bad_on = {}      -- 该开着却没开
  local bad_off = {}     -- 该关着却没关
  local multi = {}       -- 一帧出现多条
  for _, scr in ipairs(screens) do
    c = make(scr)
    c.screen = scr
    local nodes = c:build_layout()
    local n, cnt = nil, 0
    for i = 1, #nodes do
      if nodes[i].id == "settle.btn" then cnt = cnt + 1; n = nodes[i] end
    end
    local tag = tostring(scr)
    if cnt == 0 then
      bad_on[#bad_on + 1] = tag .. "(一条都没有)"
    elseif cnt > 1 then
      multi[#multi + 1] = tag .. " x" .. cnt
    elseif scr == "home" or scr == "select" then
      if not (n.visible == true and n.raycast == true) then
        bad_on[#bad_on + 1] = tag .. "(visible=" .. tostring(n.visible) .. " raycast=" .. tostring(n.raycast) .. ")"
      end
    else
      if not (n.visible == false and n.raycast == false) then
        bad_off[#bad_off + 1] = tag .. "(visible=" .. tostring(n.visible) .. " raycast=" .. tostring(n.raycast) .. ")"
      end
    end
  end
  ok(#multi == 0,
    "★ 每个屏幕上它**只许出现一次** ✓（一帧两条节点 = 两套显隐 = 必然漂移 ✗）",
    #multi == 0 and "全过 ✓" or ("这几屏重了：" .. table.concat(multi, " ")))
  ok(#bad_on == 0,
    "主页/选关：`visible` 与 `raycast` **都开着** ✓",
    #bad_on == 0 and "全过 ✓" or ("这几屏没开：" .. table.concat(bad_on, " ")))
  ok(#bad_off == 0,
    '★ 其它 7 个屏（含关卡内 `nil`）：**两个都关掉** ✓（绝不留下「看不见却吃点击」的洞 ✓）',
    #bad_off == 0 and "全过 ✓" or ("这几屏漏了：" .. table.concat(bad_off, " ")))
end

print("")
print(string.format("settle_button: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
