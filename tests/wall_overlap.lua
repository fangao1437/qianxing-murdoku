--[[----------------------------------------------------------------------------
  tests/wall_overlap.lua —— ★「墙加长 4，填掉格与格之间的缝」（v263）的回归断言

  用户真机回报（原话）：「现在墙稍微有一点缝隙，把墙的长度增加 4，填满现在的空隙即可」

  ⇒ 钉两件事（双向）：
    ① **墙**的目标长度 = 格子边长 + `edge_overlap`（默认 4）⇒ 相邻两格角上重叠
    ② **门**的长度**不受**这个改动影响（仍是 `cw × door_length_ratio`）—— 别把门也拉长了

  跑法：lua tests/wall_overlap.lua
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
local function near(a, b, eps) return type(a) == "number" and math.abs(a - b) <= (eps or 1e-6) end

-- 假控件（与 tests/things_wiring.lua 同一套写法）
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
  x.SetLocalScale = function(_, a, b) x.localScaleX, x.localScaleY = a, b end
  x._scale = function() return x.localScaleX or 1, x.localScaleY or 1 end
  x.GetSizeDelta = function() return x.sizeDeltaX, x.sizeDeltaY end
  x.SetSizeDelta = function(_, w, h) x.sizeDeltaX, x.sizeDeltaY = w, h end
  x.SetAnchoredPosition = function(_, px, py) x.anchoredPositionX, x.anchoredPositionY = px, py end
  x.SetAnchorMin = function() end
  x.SetAnchorMax = function() end
  x.SetPivot = function() end
  if x.visible == nil then x.visible = true end
  if x.active == nil then x.active = true end
  return x
end

-- 编辑器里墙/门的基准尺寸：24×8（横条），竖条则 8×24
local WALL_BASE_L, DOOR_BASE_L = 24, 24
local wallUp = ctrl("wall.up", {}, { imageId = 107092, sizeDeltaX = WALL_BASE_L, sizeDeltaY = 8, visible = false })
local wallLeft = ctrl("wall.left", {}, { imageId = 107092, sizeDeltaX = 8, sizeDeltaY = WALL_BASE_L, visible = false })
local doorUp = ctrl("door.up", {}, { imageId = 107092, sizeDeltaX = DOOR_BASE_L, sizeDeltaY = 8, visible = false })
local content = ctrl("content", { wallUp, wallLeft, doorUp })
local CELL = 108                                   -- 5×5 的格子边长（画布单位）
local cell = ctrl("cell.2.2", { content })   -- ★ 内部格（up/left 都是内部边）
cell.kind = "button"
cell.sizeDeltaX, cell.sizeDeltaY = CELL, CELL
local rootCtl = ctrl("root", { cell })
_G.game = { GetClientUIRoots = function() return { rootCtl } end }

local OVERLAP = 4
local a = Ad.new({ cells = { rows = 5, cols = 5, edge_thickness = 8, edge_overlap = OVERLAP, door_length_ratio = 0.30 } })
-- ★ 墙的目标长度用的是适配器**自己算出来的**格子边长（不是测试里那个 108）
local CW = a:cell_geometry(5)
assert(type(CW) == "number" and CW > 0, "cell_geometry 读不到格子边长")

--------------------------------------------------------------------------------
-- ① 墙：目标长度 = 108 + 4 = 112 ⇒ 横墙的 localScaleX = 112/24
--------------------------------------------------------------------------------
a:set_property("cell.2.2", "walls", { up = true, down = false, left = false, right = false })
local sx, sy = wallUp._scale()
ok(near(sx, (CW + OVERLAP) / WALL_BASE_L, 1e-6),
  "横墙 localScaleX = (" .. tostring(CW) .. "+4)/24 = " .. tostring((CW + OVERLAP) / WALL_BASE_L) .. "（实测 " .. tostring(sx) .. "）")
ok(near(sy, 8 / 8, 1e-6), "横墙厚度倍率不变（实测 " .. tostring(sy) .. "）")
ok(wallUp.visible == true, "墙仍然可见")

-- 竖墙：长边是 Y（基准 8×24）⇒ localScaleY = 112/24
a:set_property("cell.2.2", "walls", { up = false, down = false, left = true, right = false })
local lx, ly = wallLeft._scale()
ok(near(ly, (CW + OVERLAP) / WALL_BASE_L, 1e-6),
  "竖墙 localScaleY = (" .. tostring(CW) .. "+4)/24（实测 " .. tostring(ly) .. "）")

--------------------------------------------------------------------------------
-- ② 门：**不**受 overlap 影响 ⇒ localScaleX = 108×0.30/24 = 1.35
--------------------------------------------------------------------------------
a:set_property("cell.2.2", "doors", { up = true, down = false, left = false, right = false })
local dx = doorUp._scale()
local want = (CW * 0.30) / DOOR_BASE_L
ok(near(dx, want, 1e-6),
  "门长度没被拉长（期望 " .. tostring(want) .. "，实测 " .. tostring(dx) .. "）")
ok(doorUp.visible == true, "门仍然可见")
ok(not near(dx, (CELL + OVERLAP) / DOOR_BASE_L, 1e-6), "门长度 ≠ 墙长度（双向判据）")

-------------------------------------------------------------------------------
-- ③ ★ v266 视觉规格（用户 2026-10-18：「位置对了，再把门墙**加粗 2 加长 4**」＋「**门也改 0.44**」）
--
--   这份规格**只由 4 个配置决定**，脚本逻辑不参与 ⇒ 钉住"配置→目标几何"这条链：
--     厚  = `edge_thickness`  8 → 10（墙门同厚）
--     墙长 = `cw + edge_overlap(4) + edge_extra_len(4)` = **cw + 8**
--     门长 = `cw × door_length_ratio(0.44) + edge_extra_len(4)`
--   ⚠️ `edge_extra_len` 必须对**墙和门都生效**（用户要的是"门墙一起长 4"）✓
-------------------------------------------------------------------------------
local V266 = { rows = 5, cols = 5, edge_thickness = 10, edge_overlap = 4,
               edge_extra_len = 4, door_length_ratio = 0.44 }
local a266 = Ad.new({ cells = V266 })
local CW266 = a266:cell_geometry(5)

a266:set_property("cell.2.2", "walls", { up = true, down = false, left = false, right = false })
local sx2, sy2 = wallUp._scale()
ok(near(sx2, (CW266 + 8) / WALL_BASE_L, 1e-6),
  "v266 墙长 = cw + 4 + 4 = " .. tostring(CW266 + 8) .. "（实测倍率 " .. tostring(sx2) .. "）")
ok(near(sy2, 10 / 8, 1e-6),
  "v266 墙厚 = 10（倍率应为 1.25，实测 " .. tostring(sy2) .. "）")

a266:set_property("cell.2.2", "doors", { up = true, down = false, left = false, right = false })
local dx2, dy2 = doorUp._scale()
ok(near(dx2, (CW266 * 0.44 + 4) / DOOR_BASE_L, 1e-6),
  "v266 门长 = cw×0.44 + 4 = " .. tostring(CW266 * 0.44 + 4) .. "（实测倍率 " .. tostring(dx2) .. "）")
ok(near(dy2, 10 / 8, 1e-6),
  "v266 门厚 = 10（墙门同厚，实测 " .. tostring(dy2) .. "）")
ok(dx2 > (CW266 * 0.44) / DOOR_BASE_L + 1e-6,
  "门比「只按比例」更长：+4 确实加到了门上（比例值 " .. tostring(CW266 * 0.44) .. " → 目标 " .. tostring(CW266 * 0.44 + 4) .. "）")
ok(dx2 < sx2, "门仍然比墙短（门 " .. tostring(CW266 * 0.44 + 4) .. " < 墙 " .. tostring(CW266 + 8) .. "）")

-------------------------------------------------------------------------------
-- ④ ★ v268 外框墙（用户 2026-10-18：「角上还有小台阶」）
--
--   外圈骑在棋盘最外那条格线上 ⇒ 它比格子边**向外多出 厚/2 = 5px**；
--   端头若只多出 (overlap+extra)/2 = 4px ⇒ 每个角短 1px = 小台阶 ✗
--   ⇒ 外框墙长度 = `cw + 厚`（两端各多 厚/2 = 5）✓ 端头正好顶到相邻那段的外沿 ⇒ 角上是个干净直角 ✓
-------------------------------------------------------------------------------
local wUpEdge = ctrl("wall.up", {}, { imageId = 107092, sizeDeltaX = WALL_BASE_L, sizeDeltaY = 8, visible = false })
local wLfEdge = ctrl("wall.left", {}, { imageId = 107092, sizeDeltaX = 8, sizeDeltaY = WALL_BASE_L, visible = false })
local contentEdge = ctrl("content", { wUpEdge, wLfEdge })
local cellEdge = ctrl("cell.1.1", { contentEdge })     -- r=1/c=1 ⇒ up/left 都是外框边
cellEdge.kind = "button"
cellEdge.sizeDeltaX, cellEdge.sizeDeltaY = CELL, CELL
rootCtl._kids[#rootCtl._kids + 1] = cellEdge

a266:set_property("cell.1.1", "walls", { up = true, down = false, left = true, right = false })
local sxE, syE = wUpEdge._scale()
ok(near(sxE, (CW266 + 14) / WALL_BASE_L, 1e-6),
  "v270 外框墙长 = cw + 厚 + 4（两端各 厚/2+2，转角必重叠）= "
  .. tostring(CW266 + 14) .. "（实测倍率 " .. tostring(sxE) .. "）")
ok(near(syE, 10 / 8, 1e-6), "v270 外框墙厚仍是 10")
local _lxE, lyE = wLfEdge._scale()
ok(near(lyE, (CW266 + 14) / WALL_BASE_L, 1e-6),
  "v270 外框竖墙同样向两端多伸（实测倍率 " .. tostring(lyE) .. "）")

print(string.format("\nwall_overlap: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
