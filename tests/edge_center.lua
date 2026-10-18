--[[----------------------------------------------------------------------------
  tests/edge_center.lua —— ★「门墙要落在**格子之间**的格线上」（v265）的回归断言

  用户实机截图实测（`records/shot-2026-10-18-doorwall.png`，1600×900 画布）：
    · 格线（格子之间的 3px 缝）中心：
        竖线 x = 715 / 808 / 901.5 / 994.5 / 1088；横线 y = 300.5 / 394 / 487.5 / 580.5 / 674
    · 墙条 #29282B 是 7×92（画布 px），**整条都在格线的一侧**：
        竖墙中心 x = 1001（格线 994.5 ⇒ **+6.5**）
        横墙中心 y = 494（格线 487.5 ⇒ **+6.5**）
    · 门条 #DC5B28 同样 **+6.5**（不是只有门偏；墙也一样偏）

  ⇒ 根因：`_apply_edges` 把条子摆成「**贴格子内侧边**」：
       up:  y = +(cw - 厚)/2   ⇒ 条子外沿 = 格子边，条形整条在格子内
     而格子之间还有 **gap**（缝），格线在「格子边 + gap/2」处
     ⇒ 条形中心离格线 = 厚/2 + gap/2 ≈ 5.5 画布 px（再叠加取整误差即实测 ~6.5）✓

  ⇒ 本合同：**每条边都居中在它自己的格线上**：
       · 内部边（两格之间）= 两格中心的中点 ⇒ 距本格中心 **pitch/2**
       · 外框边（棋盘最外圈）= 格线本身 ⇒ 距本格中心 **size/2**
     墙和门**共用**同一条边的位置（门压在墙上，两者的中心必须相等）。

  跑法：lua tests/edge_center.lua
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
local function near(a, b, eps)
  return type(a) == "number" and math.abs(a - b) <= (eps or 0.5)
end
local function fmt(v) return string.format("%.2f", tonumber(v) or -9999) end

-- 假控件（与 tests/wall_overlap.lua 同一套写法）
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
  x.SetAnchorMin = function(_, a, b) x.anchorMinX, x.anchorMinY = a, b end
  x.SetAnchorMax = function(_, a, b) x.anchorMaxX, x.anchorMaxY = a, b end
  x.SetPivot = function(_, a, b) x.pivotX, x.pivotY = a, b end
  if x.visible == nil then x.visible = true end
  if x.active == nil then x.active = true end
  return x
end

-- 一格：content 下挂 4 面墙 + 4 扇门（父级 = content，与真机一致）
local function make_cell(name)
  local base_l, base_t = 24, 8          -- 编辑器里的基准：横条 24×8 / 竖条 8×24
  local kids = {}
  for _, s in ipairs({ "up", "down", "left", "right" }) do
    local horiz = (s == "up" or s == "down")
    kids[#kids + 1] = ctrl("wall." .. s, {}, {
      imageId = 107092, visible = false,
      sizeDeltaX = horiz and base_l or base_t,
      sizeDeltaY = horiz and base_t or base_l,
    })
  end
  for _, s in ipairs({ "up", "down", "left", "right" }) do
    kids[#kids + 1] = ctrl("door." .. s, {}, {
      imageId = 107092, visible = false,
      sizeDeltaX = 80, sizeDeltaY = 80,          -- 存档里 door.* 的实际尺寸
    })
  end
  local content = ctrl("content", kids)
  local cell = ctrl(name, { content }, { kind = "button" })
  cell.sizeDeltaX, cell.sizeDeltaY = 91, 91
  return cell, content
end

local c11, k11 = make_cell("cell.1.1")
local c22, k22 = make_cell("cell.2.2")
local c66, k66 = make_cell("cell.6.6")
-- 真机存档里 stage 是 584×584（= 设计 701 × 5/6）；cell_geometry 从它推格子
local stage = ctrl("stage", { c11, c22, c66 }, { sizeDeltaX = 584, sizeDeltaY = 584 })
local rootCtl = ctrl("root", { stage })
_G.game = { GetClientUIRoots = function() return { rootCtl } end }

local a = Ad.new({
  cells = {
    rows = 6, cols = 6, parent = "stage", ruler = 12,
    edge_thickness = 10, edge_overlap = 4, door_length_ratio = 0.30,
    edge_fit_log = false,
  },
})

local SIZE, PITCH = a:cell_geometry(6)
ok(type(SIZE) == "number" and SIZE > 0, "cell_geometry 读到格子边长（" .. tostring(SIZE) .. "）")
ok(type(PITCH) == "number" and PITCH > SIZE,
  "pitch > size（有缝才会出现「墙在格子里面」的偏移；实测 size=" .. fmt(SIZE) .. " pitch=" .. fmt(PITCH) .. "）")

local THICK = 10
local UP, LEFT, DOWN, RIGHT = "up", "left", "down", "right"

-------------------------------------------------------------------------------
-- ① 内部边（cell.2.2 的 up / left）：中心必须在**两格之间的格线**上 ⇒ ±pitch/2
-------------------------------------------------------------------------------
a:set_property("cell.2.2", "walls", { up = true, down = false, left = true, right = false })
local wu = k22.GetChild(k22, "wall.up")
local wl = k22.GetChild(k22, "wall.left")
ok(near(wu.anchoredPositionY, PITCH / 2),
  "内部上墙居中在格线：y 应为 pitch/2 = " .. fmt(PITCH / 2) .. "（实测 " .. fmt(wu.anchoredPositionY) .. "）")
ok(near(wl.anchoredPositionX, -PITCH / 2),
  "内部左墙居中在格线：x 应为 -pitch/2 = " .. fmt(-PITCH / 2) .. "（实测 " .. fmt(wl.anchoredPositionX) .. "）")

-- 双向：条子必须**跨**格线两侧（不是压在格子内侧）
ok(wu.anchoredPositionY - THICK / 2 < PITCH / 2 and wu.anchoredPositionY + THICK / 2 > PITCH / 2,
  "上墙的厚度跨过格线（外沿 " .. fmt(wu.anchoredPositionY + THICK / 2)
  .. " > 格线 " .. fmt(PITCH / 2) .. "）")

-------------------------------------------------------------------------------
-- ② 门和墙在同一条边上必须**共线**（门压在墙上）
-------------------------------------------------------------------------------
a:set_property("cell.2.2", "doors", { up = true, down = false, left = true, right = false })
local du = k22.GetChild(k22, "door.up")
local dl = k22.GetChild(k22, "door.left")
ok(near(du.anchoredPositionY, wu.anchoredPositionY, 0.01),
  "门上墙与墙上墙共线：门 " .. fmt(du.anchoredPositionY) .. " vs 墙 " .. fmt(wu.anchoredPositionY))
ok(near(dl.anchoredPositionX, wl.anchoredPositionX, 0.01),
  "门左墙与墙左墙共线：门 " .. fmt(dl.anchoredPositionX) .. " vs 墙 " .. fmt(wl.anchoredPositionX))
-- 双向：门**没有**额外的偏心补偿（旧版 door_nudge=6 会把它推离格线）
ok(math.abs(du.anchoredPositionY - PITCH / 2) < 0.5,
  "门没有被额外的 nudge 推离格线（实测 " .. fmt(du.anchoredPositionY) .. "）")

-------------------------------------------------------------------------------
-- ③ 外框边（cell.1.1 的 up/left、cell.6.6 的 down/right）：**也骑格线**（v267，用户要"外圈贴边"）⇒ ±size/2
-------------------------------------------------------------------------------
a:set_property("cell.1.1", "walls", { up = true, down = false, left = true, right = false })
ok(near(k11.GetChild(k11, "wall.up").anchoredPositionY, SIZE / 2),
  "外框上墙也骑格线（v267）：y 应为 size/2 = " .. fmt(SIZE / 2)
  .. "（实测 " .. fmt(k11.GetChild(k11, "wall.up").anchoredPositionY) .. "）")
ok(near(k11.GetChild(k11, "wall.left").anchoredPositionX, -(SIZE / 2)),
  "外框左墙也骑格线（v267）：x 应为 -size/2 = " .. fmt(-(SIZE / 2))
  .. "（实测 " .. fmt(k11.GetChild(k11, "wall.left").anchoredPositionX) .. "）")

a:set_property("cell.6.6", "walls", { up = false, down = true, left = false, right = true })
ok(near(k66.GetChild(k66, "wall.down").anchoredPositionY, -(SIZE / 2)),
  "外框下墙也骑格线（v267）：y 应为 -size/2（实测 "
  .. fmt(k66.GetChild(k66, "wall.down").anchoredPositionY) .. "）")
ok(near(k66.GetChild(k66, "wall.right").anchoredPositionX, SIZE / 2),
  "外框右墙也骑格线（v267）：x 应为 size/2（实测 "
  .. fmt(k66.GetChild(k66, "wall.right").anchoredPositionX) .. "）")

-------------------------------------------------------------------------------
-- ④ content 必须被钉成「锚点居中、尺寸=格子、位置=0」—— 边的坐标基准靠它
-------------------------------------------------------------------------------
ok(near(k22.anchorMinX, 0.5) and near(k22.anchorMinY, 0.5), "content 锚点居中（min）")
ok(near(k22.anchorMaxX, 0.5) and near(k22.anchorMaxY, 0.5), "content 锚点居中（max）")
ok(near(k22.sizeDeltaX, SIZE) and near(k22.sizeDeltaY, SIZE), "content 尺寸 = 格子边长")
ok(near(k22.anchoredPositionX, 0) and near(k22.anchoredPositionY, 0), "content 位置 = 0（居中）")

-------------------------------------------------------------------------------
-- ⑤ 5×5 也要成立（pitch/size 都由 cell_geometry 按 N 算，不许写死）
-------------------------------------------------------------------------------
local a5 = Ad.new({
  cells = {
    rows = 5, cols = 5, parent = "stage", ruler = 12,
    edge_thickness = 10, edge_overlap = 4, door_length_ratio = 0.30,
    edge_fit_log = false,
  },
})
local S5, P5 = a5:cell_geometry(5)
local c55, k55 = make_cell("cell.2.3")
stage._kids[#stage._kids + 1] = c55
a5:set_property("cell.2.3", "walls", { up = true, down = false, left = true, right = false })
ok(near(k55.GetChild(k55, "wall.up").anchoredPositionY, P5 / 2),
  "5×5 的上墙也居中在格线：y 应为 pitch/2 = " .. fmt(P5 / 2)
  .. "（实测 " .. fmt(k55.GetChild(k55, "wall.up").anchoredPositionY) .. "）")
ok(near(k55.GetChild(k55, "wall.left").anchoredPositionX, -P5 / 2),
  "5×5 的左墙也居中在格线：x 应为 -pitch/2 = " .. fmt(-P5 / 2)
  .. "（实测 " .. fmt(k55.GetChild(k55, "wall.left").anchoredPositionX) .. "）")
ok(P5 > S5, "5×5 也有缝（size=" .. fmt(S5) .. " pitch=" .. fmt(P5) .. "）")

-------------------------------------------------------------------------------
-- ⑥ 外框墙的长度 = **cw + 厚**（v268）
--
--   外圈向外移了 厚/2 = 5px（为了贴住外框），端头必须正好多出这 5px，否则每个角短 1px
--   ⇒ 用户实机看到的那级"小台阶" ✓
--   ⚠️ 这条**不受** overlap / extra 影响 —— 外框没有"相邻格子要填缝"的问题，只要直角干净
-------------------------------------------------------------------------------
local BASE_L = 24                                     -- make_cell 里横墙的基准长度
local len_outer = (k11.GetChild(k11, "wall.up").localScaleX or 1) * BASE_L
local len_inner = (k22.GetChild(k22, "wall.up").localScaleX or 1) * BASE_L
ok(near(len_outer, SIZE + THICK + 4, 0.01),
  "外框墙长 = cw + 厚 + 4（两端各 厚/2+2，转角必重叠）= " .. fmt(SIZE + THICK + 4) .. "（实测 " .. fmt(len_outer) .. "）")
ok(near(len_inner, SIZE + 4, 0.01),
  "内部墙长 = cw + overlap(4) = " .. fmt(SIZE + 4) .. "（实测 " .. fmt(len_inner) .. "）")

print(string.format("\nedge_center: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
