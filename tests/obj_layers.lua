--[[----------------------------------------------------------------------------
  tests/obj_layers.lua —— 家具「三层拼装」（v299）的离线断言

  ★ 为什么要这一套（2026-10-22）：
    原作 Murdoku 的家具 = **base 剪影 + overlay 剪影 + 两个颜色**（见
    `_work/art-ref/原作美术参考.md`）。官方素材库里没有俯视家具，所以家具改成
    「模板里 3 层图片子控件（`obj` / `obj2` / `obj3`）+ 每层各自 id/色/几何」拼出来。
    这条链路有三处最容易坏，全部由本用例钉住：

      ① 调色板：`cfg.obj_art` 的**多层写法**要能登记成 `obj.<kind>` / `obj2.<kind>` /
         `obj3.<kind>` 三个键，且**老的单层写法一个字节都不许变**（向后兼容）
      ② 画法：`_paint_obj` 要按层画图/上色 + 按 `w/h/dx/dy` 摆几何；
         **没有物件的格子三层都要藏**（白板压头像的老 bug）
      ③ 层序：`layer_order` 里 `obj < obj2 < obj3 < portrait`（头像要压在家具上）

  跑法：lua tests/obj_layers.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path,
}, ";")

local Ad = require("engine_adapter_qianxing")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

-- ── 假控件（与 tests/things_wiring.lua 同一套写法）────────────────────────────
local function ctrl(name, kids, fields)
  local x = { name = name, _kids = kids or {} }
  for k, v in pairs(fields or {}) do x[k] = v end
  x.GetChildren = function() return x._kids end
  x.GetChild = function(_, n)
    for _, k in ipairs(x._kids) do if k.name == n then return k end end
    return nil
  end
  x.FindChild = x.GetChild
  x.SetVisible = function(_, v) x.visible = v end
  x.SetActive = function(_, v) x.active = v end
  x.SetImage = function(_, src, id) x.imageSource = src; x.imageId = id end
  x.SetLocalScale = function() end
  x.GetSizeDelta = function() return x.sizeDeltaX, x.sizeDeltaY end
  x.SetSizeDelta = function(_, w, h) x.sizeDeltaX, x.sizeDeltaY = w, h end
  x.SetAnchoredPosition = function(_, px, py) x.anchoredPositionX, x.anchoredPositionY = px, py end
  x.SetAnchorMin = function(_, ax, ay) x.anchorMinX, x.anchorMinY = ax, ay end
  x.SetAnchorMax = function(_, ax, ay) x.anchorMaxX, x.anchorMaxY = ax, ay end
  x.SetPivot = function(_, px, py) x.pivotX, x.pivotY = px, py end
  if x.visible == nil then x.visible = true end
  if x.active == nil then x.active = true end
  return x
end

local CELL = 108     -- 5×5 关的格子边长（画布 px）
local face     = ctrl("face", {}, { imageId = 100001, imageColor = 4294967295 })
local hint     = ctrl("hint", {}, { imageId = 100001, imageColor = 2130731989 })
local obj1     = ctrl("obj",  {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local obj2     = ctrl("obj2", {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local obj3     = ctrl("obj3", {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local portrait = ctrl("portrait", {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local wallUp   = ctrl("wall.up", {}, { imageId = 107092, imageColor = 4281019187, visible = false })
local content  = ctrl("content", { face, hint, obj1, obj2, obj3, portrait, wallUp })
local cell     = ctrl("cell.1.1", { content })
cell.kind = "button"
cell.sizeDeltaX, cell.sizeDeltaY = CELL, CELL

-- `things` 调色板：编辑器里配的两层图（这里用 100001 白块 + 可分辨的颜色代替）
local things = ctrl("things", {
  ctrl("obj.chair",  {}, { imageId = 100001, imageColor = 0xFF8A6A48, imageSource = "StaticReference" }),
  ctrl("obj2.chair", {}, { imageId = 100001, imageColor = 0xFFE3D2AE, imageSource = "StaticReference" }),
  -- ⚠️ 故意不给 `obj3.chair` —— 验证"只有两层"时第三层必须被藏掉
})
local rootCtl = ctrl("root", { cell, things })
_G.game = { GetClientUIRoots = function() return { rootCtl } end }

local a = Ad.new({
  cells = {
    rows = 5, cols = 5,
    layer_order = {
      "face", "hint", "obj", "obj2", "obj3", "portrait",
      "wall.up", "x", "note",
    },
  },
  -- 脚本侧的兜底写法：**table/statue 走多层**，**plant 走单层**（向后兼容）
  obj_art = {
    table = {
      { id = 106053, color = 0xFF8B5E3C, w = 0.86, h = 0.62 },
      { id = 106053, color = 0xFFD2A86A, w = 0.74, h = 0.50, dx = 0.04, dy = 0.02 },
    },
    plant = { id = 105135, color = 4294967295 },
  },
})

--------------------------------------------------------------------------------
-- A 调色板：多层写法登记成三个键；老的单层写法完全兼容
--------------------------------------------------------------------------------
local pal = a:read_palette()
print("== A 调色板 ==")
ok(pal["obj.chair"] ~= nil, "A1 控件 obj.chair 登记进调色板（第 1 层）")
ok(pal["obj2.chair"] ~= nil, "A2 控件 obj2.chair 登记进调色板（第 2 层）")
ok(pal["obj3.chair"] == nil, "A3 没有 obj3.chair 控件时第 3 层不存在（不凭空造）")
ok(pal["obj.chair"].color == 0xFF8A6A48, "A4 第 1 层颜色取控件里的 0xFF8A6A48")
ok(pal["obj2.chair"].color == 0xFFE3D2AE, "A5 第 2 层颜色取控件里的 0xFFE3D2AE")

ok(pal["obj.table"] ~= nil and pal["obj.table"].id == 106053, "A6 cfg 多层写法的第 1 层 = obj.table（106053）")
ok(pal["obj2.table"] ~= nil and pal["obj2.table"].id == 106053, "A7 cfg 多层写法的第 2 层 = obj2.table")
local t2 = pal["obj2.table"] or {}
ok(t2.w == 0.74 and t2.h == 0.50, "A8 第 2 层几何 w/h 带出来了（0.74/0.50）")
ok(t2.dx == 0.04 and t2.dy == 0.02, "A9 第 2 层偏移 dx/dy 带出来了（0.04/0.02）")
ok(pal["obj3.table"] == nil, "A10 只写两层时不会凭空多出第 3 层")

ok(pal["obj.plant"] ~= nil and pal["obj.plant"].id == 105135, "A11 单层老写法仍登记成 obj.plant")
ok(pal["obj.plant"].from == "cfg.obj_art", "A12 来源标记仍是 cfg.obj_art（排障用）")
ok(pal["obj2.plant"] == nil, "A13 单层老写法不会多出 obj2.plant")

--------------------------------------------------------------------------------
-- B 画法：两层控件 → 两层都画；第三层被藏
--------------------------------------------------------------------------------
print("== B 两层家具 ==")
local r1 = a:set_property("cell.1.1", "object", "obj.chair")
ok(r1 == true, "B1 set_property(cell,'object','obj.chair') 返回 true")
ok(obj1.visible == true, "B2 第 1 层可见")
ok(obj2.visible == true, "B3 第 2 层可见")
ok(obj3.visible == false, "B4 没有第 3 层 ⇒ obj3 必须藏着（白板不许露出来）")
ok(obj1.imageColor == 0xFF8A6A48, "B5 第 1 层颜色 = 0xFF8A6A48")
ok(obj2.imageColor == 0xFFE3D2AE, "B6 第 2 层颜色 = 0xFFE3D2AE")
ok(obj1.sizeDeltaX == CELL and obj1.sizeDeltaY == CELL, "B7 第 1 层铺满格子（108×108）")
ok(obj2.sizeDeltaX == CELL and obj2.sizeDeltaY == CELL, "B8 控件来源的两层几何缺省 = 铺满格子")

--------------------------------------------------------------------------------
-- C 画法：cfg 多层写法的几何（w/h/dx/dy）要真的落到控件上
--------------------------------------------------------------------------------
print("== C 几何 ==")
a:set_property("cell.1.1", "object", "obj.table")
ok(math.abs(obj1.sizeDeltaX - CELL * 0.86) < 0.01, "C1 第 1 层宽 = 108×0.86 = 92.88")
ok(math.abs(obj1.sizeDeltaY - CELL * 0.62) < 0.01, "C2 第 1 层高 = 108×0.62 = 66.96")
ok(math.abs(obj2.sizeDeltaX - CELL * 0.74) < 0.01, "C3 第 2 层宽 = 108×0.74 = 79.92")
ok(math.abs(obj2.anchoredPositionX - CELL * 0.04) < 0.01, "C4 第 2 层 x 偏移 = 108×0.04（向右）")
ok(math.abs(obj2.anchoredPositionY - (-(CELL * 0.02))) < 0.01, "C5 dy 正 = 向下 ⇒ anchoredPosition.y = −108×0.02")
ok(obj3.visible == false, "C6 仍然只有两层 ⇒ 第三层藏着")

--------------------------------------------------------------------------------
-- D 没有物件：三层都必须藏（老 bug：白板压头像）
--------------------------------------------------------------------------------
print("== D 空格子 ==")
a:set_property("cell.1.1", "object", false)
ok(obj1.visible == false, "D1 没有物件 ⇒ obj 藏")
ok(obj2.visible == false, "D2 没有物件 ⇒ obj2 藏")
ok(obj3.visible == false, "D3 没有物件 ⇒ obj3 藏")

--------------------------------------------------------------------------------
-- E 单层家具（老写法）：obj 画、obj2/obj3 藏
--------------------------------------------------------------------------------
print("== E 单层家具 ==")
a:set_property("cell.1.1", "object", "obj.plant")
ok(obj1.visible == true, "E1 单层家具的 obj 可见")
ok(obj1.imageId == 105135, "E2 单层家具的图 = 105135（cfg 兜底）")
ok(obj1.imageColor == 4294967295, "E3 单层家具的色 = 白色（原图不动）")
ok(obj2.visible == false, "E4 单层家具不许点亮 obj2")
ok(obj3.visible == false, "E5 单层家具不许点亮 obj3")

--------------------------------------------------------------------------------
-- F 重复下发幂等：同一意图再来一次，图不会变、可见性仍然对
--------------------------------------------------------------------------------
print("== F 幂等 ==")
local before = obj1.imageId
a:set_property("cell.1.1", "object", "obj.plant")
ok(obj1.imageId == before and obj1.visible == true, "F1 同一件家具重复下发，结果不变（幂等）")

--------------------------------------------------------------------------------
print(string.format("\nobj_layers: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
