--[[----------------------------------------------------------------------------
  tests/confirm_card_anchor.lua —— ★ 判据：确认卡（✓/✗）**跟着"刚按下的那颗键"走**，
                                   且**看得见的那颗（hex.*）与能点的那颗（hit.*）必须同框**

  ★★★ 为什么要单独立这条用例（2026-10-16 · v250 ✓ 用户真机回报逼出来的）：
    ★ 用户原话两句 ✓：
      · 「**勾叉确认卡用的是旧规划的位置，没到新位置的旁边**」✗
      · 「**它们的功能也丢失了，现在点不动**」✗
    ★ 真因两个，**各自都能红** ✓：
      ① 锚点原来是**写死的设计坐标**（`CONFIRM_ANCHOR`，照**规划图**推的 ✓）
         ⇒ ★ 那颗键在编辑器里一挪（★ 现在键也归编辑器了 ✓）⇒ ★ 卡**不跟** ✗
      ② v249 只把**图标**（`hex.ok/hex.no`）交回脚本 ⇒ ★ **热区仍在原地** ✗
         ⇒ ★ 看得见的 ✓/✗ 与能点的 ✓/✗ **分了家** ⇒ 点不动 ✗✓

  ★ 本用例钉三条（★ 每条都能红 ✓）：
    ① ★ **图标与热区逐字段同一个 rect** ✓ ＋ ★ 两者 `pos_runtime == true` ✓
       （★ 破坏性验证：把热区那条 `pos_runtime = is_confirm_hit or nil` 删掉 ⇒ 本段红 ✓）
    ② ★★ **键挪了 ⇒ 确认卡必须跟着挪**（★ 同一动作、两种键位，取两次规划比 delta ✓）
       （★ 破坏性验证：把 `key_box_design` 那段删掉 ⇒ 卡两次都在同一处 ⇒ 本段红 ✓✓）
    ③ ★ 读不到那颗键 ⇒ **仍然有 rect**（退回写死的表 ✓ 不许因此不摆 ✓）

  ★ ⚠️ 只比 **delta**、不写死绝对像素 ✓ —— ★ 因为 `rect` 走的是 `D()`（设计→画布 ✓），
    写死绝对数会把"单位"也钉进去 ⇒ 换个画布尺寸就假红 ✓

  ★ 只读：本文件**不改任何生产源码** ✓
  ★ 跑法：lua tests/confirm_card_anchor.lua
------------------------------------------------------------------------------]]--

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local Fx   = require("tests.fixtures")

local out = print
do local function sink(...) end _G.print = sink _G.printerr = sink end   -- 静音生产日志

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

local CANVAS_W, CANVAS_H, SC = 1600, 900, 5 / 6

-- ★ 假适配器：★ 只提供本用例要用的三样（`find` / `cfg` / 那颗键的几何 ✓）
--   ★ 键的"运行时"矩形按**引擎口径**给：画布中心为原点、y 向上（= `GetAnchoredPosition` ✓）
local function fake_adapter(keys)
  local A = { cfg = { scale = SC, canvas_w = CANVAS_W, canvas_h = CANVAS_H } }
  A.find = function(_, id)
    local r = keys[id]
    if r == nil then return nil end
    return {
      GetSizeDelta = function() return r.w, r.h end,
      GetAnchoredPosition = function() return r.ax, r.ay end,
    }
  end
  return A
end

-- ★ 「画布 px（左上原点）」→ 引擎的 anchored（与适配器 `rect` 分支同源 ✓ 手算一遍 ✓）
local function to_anchored(cx0, cy0, w, h)
  return { w = w, h = h, ax = (cx0 + w * 0.5) - CANVAS_W / 2, ay = CANVAS_H / 2 - (cy0 + h * 0.5) }
end

-- ★ 生产里那份转换 ✓：`D(v) = floor(v × 6/5 + 0.5)`（画布 → 设计 ✓ 见 `ui_controller` 的 `local K = 6/5`）
local function D(v) return math.floor(v * 6 / 5 + 0.5) end

local levels = { { id = "a", name = "A", size = { rows = 5, cols = 5 }, suspects = {} } }
local function plan_with(keys, action)
  -- ★ 关卡内（`screen == nil`）才会 push 那 7 个 `hex.*` ✓
  local c = UIC.new(Core.new(Fx.clue_level_5x5()), { skip_intro = true, levels = levels, screen = nil })
  c.screen = nil
  c.pending = { action = action }
  local nodes = c:build_layout(fake_adapter(keys))
  local by = {}
  for i = 1, #nodes do by[nodes[i].id] = nodes[i] end   -- ★ 同名取**最后**一条（与渲染同口径 ✓）
  return by
end

local function rect_str(n) return n and n.rect and ("(" .. n.rect.x .. "," .. n.rect.y .. ") " .. n.rect.w .. "×" .. n.rect.h) or "—" end
local function near(a, b, tol) return a ~= nil and b ~= nil and math.abs(a - b) <= (tol or 1) end

out("== 1. ★ 图标与热区必须同框，且两者都归脚本 ==")
do
  local by = plan_with({ ["hex.submit"] = to_anchored(1448, 48, 70, 70) }, "submit")
  local i1, h1 = by["hex.ok"], by["hit.ok"]
  ok(i1 ~= nil and h1 ~= nil, "确认卡的两颗（图标 hex.ok + 热区 hit.ok）都在规划里 ✓",
    "图标=" .. tostring(i1 ~= nil) .. "　热区=" .. tostring(h1 ~= nil))
  ok(i1 and h1 and i1.rect.x == h1.rect.x and i1.rect.y == h1.rect.y
     and i1.rect.w == h1.rect.w and i1.rect.h == h1.rect.h,
    "★ ①-a 图标与热区**逐字段同一个 rect** ✓", "图标 " .. rect_str(i1) .. "　热区 " .. rect_str(h1))
  ok(i1 and i1.pos_runtime == true and h1 and h1.pos_runtime == true,
    "★ ①-b 两者 `pos_runtime` 都是 true（= 位置归脚本 ✓）",
    "图标=" .. tostring(i1 and i1.pos_runtime) .. "　热区=" .. tostring(h1 and h1.pos_runtime))
  local i2, h2 = by["hex.no"], by["hit.no"]
  ok(i2 and h2 and i2.rect.x == h2.rect.x and i2.rect.y == h2.rect.y
     and i2.pos_runtime == true and h2.pos_runtime == true,
    "★ ①-c 叉那一对（hex.no / hit.no）同样同框且归脚本 ✓", "叉 " .. rect_str(i2) .. "　热区 " .. rect_str(h2))
end

out("== 2. ★★ 那颗键挪走 ⇒ 确认卡必须跟着挪（这条就是用户报的那件事）==")
do
  -- ★ 键在**规划原位**（画布 1448,48 70×70 ✓ = `ICON_ASSETS` 那一行 ✓）
  local A = plan_with({ ["hex.submit"] = to_anchored(1448, 48, 70, 70) }, "submit")
  -- ★ 键被挪到画布 (900,300)（= 用户"在编辑器里把键挪过" ✓）
  local B = plan_with({ ["hex.submit"] = to_anchored(900, 300, 70, 70) }, "submit")
  local ia, ib = A["hex.ok"], B["hex.ok"]
  ok(ia ~= nil and ib ~= nil, "两次都有 hex.ok ✓")
  -- ★ 期望值直接按规则算 ✓：★ 卡 = 键左侧（右侧那两颗放左边 ✓）＋ 纵向居中 ✓ 再经 `D()` 转设计 ✓
  local wantA = { x = D(1448 - 8 - 54 - 8 - 54), y = D(48 + (70 - 54) * 0.5) }
  local wantB = { x = D(900 - 8 - 54 - 8 - 54), y = D(300 + (70 - 54) * 0.5) }
  ok(ia and near(ia.rect.x, wantA.x) and near(ia.rect.y, wantA.y),
    "★ 键在规划原位时：卡在它**左侧、纵向居中**（尺寸取画布 54 ✓ 再转设计 ✓）",
    rect_str(ia) .. "　期望 (" .. wantA.x .. "," .. wantA.y .. ")")
  ok(ib and near(ib.rect.x, wantB.x) and near(ib.rect.y, wantB.y),
    "★★ 键挪到画布 (900,300) 时：卡**跟着挪**（★ 这条就是用户报的那件事 ✓）",
    rect_str(ib) .. "　期望 (" .. wantB.x .. "," .. wantB.y .. ")")
  ok(ia and ib and (ib.rect.x < ia.rect.x - 50) and (ib.rect.y > ia.rect.y + 50),
    "★ 位移方向正确（左移 + 下移 ✓）",
    "Δ = (" .. ((ib and ib.rect.x or 0) - (ia and ia.rect.x or 0)) .. ","
      .. ((ib and ib.rect.y or 0) - (ia and ia.rect.y or 0)) .. ")")
end

out("== 3. ★ 返回菜单那颗在左边 ⇒ 卡放【右侧】且紧贴 ==")
do
  local by = plan_with({ ["hex.back"] = to_anchored(60, 48, 62, 62) }, "back")
  local i1 = by["hex.ok"]
  local want = { x = D(60 + 62 + 8), y = D(48 + (62 - 54) * 0.5) }
  ok(i1 and near(i1.rect.x, want.x) and near(i1.rect.y, want.y),
    "★ 卡 = 键的**右缘 + 8**、纵向居中（画布 130,52 → 设计 " .. want.x .. "," .. want.y .. " ✓）",
    rect_str(i1) .. "　期望 (" .. want.x .. "," .. want.y .. ")")
end

out("== 4. ★ 读不到那颗键 ⇒ 仍然有 rect（退回写死的表 ✓）==")
do
  local by = plan_with({}, "submit")            -- ★ 一颗都读不到 ✓
  local i1 = by["hex.ok"]
  ok(i1 ~= nil and i1.rect ~= nil, "仍然有 rect（★ 不许因为读不到就不摆 ✓）", rect_str(i1))
  -- ★ 旧表：`submit = { x = 1448 - 8 - 54 - 8 - 54, y = 48 }` ✓（画布 ✓ 再经 D ✓）
  ok(i1 and near(i1.rect.x, D(1324)) and near(i1.rect.y, D(48)),
    "退回的正是旧表那一份（画布 1324,48 → 设计 " .. D(1324) .. "," .. D(48) .. " ✓）", rect_str(i1))
end

out("")
out("confirm_card_anchor: " .. pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
