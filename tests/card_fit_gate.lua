--[[----------------------------------------------------------------------------
  tests/card_fit_gate.lua —— ★「选关四张卡塌成一张」的回归断言（2026-10-18 · v262）

  用户定位（原话）：「选关渲染问题的出现在 397 之后」

  真因（本轮查到）：
    v255（397）给 `tint` 分支加了「顺手把 face 钉成格子大小」这一行，
    而 v256 又在 `image` 分支加了同一句。两句的写法都是
        local target = self:sub(id, "face") or ctrl
        self:_fit_child_to_cell(ctrl, target, id)
    —— `select.card.N` **没有 `face` 子控件** ⇒ `target` 落到 **ctrl 本身** ⇒
       `_fit_child_sized(ctrl, w, h)` 对**卡片自己**执行 `SetAnchoredPosition(0,0)` ⇒
       **四张卡各自被钉到父级中心** ⇒ 叠在一起 ⇒「只渲染出一张卡片」✓

  本用例钉四条（双向）：
    ① 卡片下发 `image` ⇒ **位置/尺寸一个都不许动**（这就是塌陷）
    ② 卡片下发 `tint`  ⇒ 同上（另一条触发路径）
    ③ 反向：`cell.<行>.<列>` 的 `face` **仍然要被钉成格子大小并居中**（别把功能修没了）
    ④ 卡片自身的 `imageColor` 仍要写进去（颜色归脚本，几何归编辑器）

  跑法：lua tests/card_fit_gate.lua
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

-- ── 假控件（只实现适配层用到的那些，与 tests/things_wiring.lua 同一套写法）──
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

-- ── 一棵与真机存档同构的小树 ──────────────────────────────────────────────
-- 格子：cell.1.1 → content → face（**有** face ⇒ 贴格该生效）
local cellFace = ctrl("face", {}, { imageId = 100001, imageColor = 4294967295 })
local cellContent = ctrl("content", { cellFace })
local cell = ctrl("cell.1.1", { cellContent })
cell.kind = "button"
cell.sizeDeltaX, cell.sizeDeltaY = 108, 108
cell.anchoredPositionX, cell.anchoredPositionY = 40, -20

-- 选关卡片：select.card.1 → { text, bg, label }（**没有** face ⇒ 贴格必须不生效）
local cardText = ctrl("text", {}, {})
local cardBg = ctrl("bg", {}, { imageId = 100108 })
local cardLabel = ctrl("label", {}, {})
local CARD_X, CARD_Y, CARD_W, CARD_H = -374.2, -4.5, 209, 291.6
local card = ctrl("select.card.1", { cardText, cardBg, cardLabel })
card.kind = "button"
card.sizeDeltaX, card.sizeDeltaY = CARD_W, CARD_H
card.anchoredPositionX, card.anchoredPositionY = CARD_X, CARD_Y

local rootCtl = ctrl("root", { cell, card })
_G.game = { GetClientUIRoots = function() return { rootCtl } end }

local a = Ad.new({ cells = { rows = 5, cols = 5 } })

local function card_geom()
  return card.anchoredPositionX, card.anchoredPositionY, card.sizeDeltaX, card.sizeDeltaY
end
local function card_untouched(tag)
  local x, y, w, h = card_geom()
  ok(x == CARD_X and y == CARD_Y,
    tag .. "：卡片位置没被改（仍 " .. tostring(x) .. "," .. tostring(y) .. "）")
  ok(w == CARD_W and h == CARD_H,
    tag .. "：卡片尺寸没被改（仍 " .. tostring(w) .. "×" .. tostring(h) .. "）")
end

--------------------------------------------------------------------------------
-- ① 卡片下发 `image` ⇒ 几何一个都不许动（v256 那条路径）
--------------------------------------------------------------------------------
a:set_property("select.card.1", "image", 106053)
card_untouched("image")

--------------------------------------------------------------------------------
-- ② 卡片下发 `tint` ⇒ 同上（v255 那条路径，也就是 397 之后塌陷的入口）
--------------------------------------------------------------------------------
a:set_property("select.card.1", "tint", { r = 250, g = 244, b = 232 })
card_untouched("tint")

--------------------------------------------------------------------------------
-- ③ 反向：格子的 face **仍然**被钉成格子大小、居中（别把功能修没了）
--------------------------------------------------------------------------------
a:set_property("cell.1.1", "image", 106053)
ok(cellFace.sizeDeltaX == 108 and cellFace.sizeDeltaY == 108,
  "格子 face 仍被钉成 108×108（实测 " .. tostring(cellFace.sizeDeltaX) .. "×" .. tostring(cellFace.sizeDeltaY) .. "）")
ok(cellFace.anchoredPositionX == 0 and cellFace.anchoredPositionY == 0,
  "格子 face 仍被居中到 (0,0)（实测 " .. tostring(cellFace.anchoredPositionX) .. "," .. tostring(cellFace.anchoredPositionY) .. "）")
-- 格子自己不能被当成子控件钉 —— 它自己的位置也不该被改
ok(cell.anchoredPositionX == 40 and cell.anchoredPositionY == -20,
  "格子自身位置没被改（仍是 40,-20）")

--------------------------------------------------------------------------------
-- ④ 卡片自身的染色仍要写进去（颜色归脚本、几何归编辑器）
--------------------------------------------------------------------------------
local want = 0xFFFAF4E8   -- r=250 g=244 b=232 a=255
ok(card.imageColor == want,
  "卡片 imageColor 写进去了（实测 " .. tostring(card.imageColor) .. "，期望 " .. tostring(want) .. "）")

print(string.format("\ncard_fit_gate: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
