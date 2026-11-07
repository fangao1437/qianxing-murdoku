--[[----------------------------------------------------------------------------
  tests/portrait_layer.lua —— ★「家具不许盖住放置的头像」的回归断言（v283）

  用户原话：「**现在家具图层会盖在放置的头像上，把这个问题解决**」

  根因：格子 `content` 的层序是  face → hint → **obj（家具）** → wall → door → x → note，
        而"放置的头像"走 `image` 键落在 **face（最底层）** ⇒ 家具压在上面 ✗
  修法：存档给模板补一层 `portrait`（克隆自 face），层序放在 **obj 之上、wall 之下**；
        格子的 `image` 改画到 `portrait` —— 房间色仍留在 face（`tint` 写）✓

  钉六件事（双向）：
    ① 格子的头像落到 **portrait**，不是 face    ② face 的图**不许**被换（房间色要留）
    ③ 家具层 obj 不被头像影响                    ④ 人拿走后 portrait **要藏起来**
    ⑤ 非格子（线索卡等）**仍走 face**（别把老路改坏）
    ⑥ 重放：`_repaint_cell_overlays` 能把头像救回来（与家具/门墙同一条纪律）
    ⑦ 配置：`layer_order` 里必须是 obj → portrait → wall

  跑法：lua tests/portrait_layer.lua
  复现 Red（v283 之前）：把旧适配器放到一个目录里，用环境变量指过去
      MURDOKU_OLD_ADAPTER=<目录> lua tests/portrait_layer.lua
      → 旧代码没有 portrait 概念 ⇒ ①②④⑥ 全红（这是有效的 Red，不是环境问题）
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
local OLD = os.getenv("MURDOKU_OLD_ADAPTER")
if OLD ~= nil and OLD ~= "" then root = OLD end
package.path = table.concat({
  root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path,
}, ";")

local Ad = require("engine_adapter_qianxing")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

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
  x.SetAnchorMin = function() end
  x.SetAnchorMax = function() end
  x.SetPivot = function() end
  if x.visible == nil then x.visible = true end
  if x.active == nil then x.active = true end
  return x
end

-- 调色板：assets 容器 → portrait.A（与真机存档同构）
local palA = ctrl("portrait.A", {}, { imageSource = "StaticReference", imageId = 100109,
                                      imageColor = 4294967295 })
local assets = ctrl("assets", { palA })

-- 一格：content → face（房间色板）/ obj（家具）/ portrait（头像层，v283）/ x（叉）
local cellFace = ctrl("face", {}, { imageId = 100001, imageColor = 4294967295, visible = true })
local cellObj = ctrl("obj", {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local cellPortrait = ctrl("portrait", {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local cellX = ctrl("x", {}, { imageId = 100101, imageColor = 4294959249, visible = false })
local content = ctrl("content", { cellFace, cellObj, cellPortrait, cellX })
local cell = ctrl("cell.2.2", { content })
cell.kind = "button"
cell.sizeDeltaX, cell.sizeDeltaY = 108, 108

-- 一张线索卡（**非格子**）：clue.1 → face —— 老路必须还在
local clueFace = ctrl("face", {}, { imageId = 100001 })
local clue = ctrl("clue.1", { clueFace })

local rootCtl = ctrl("root", { assets, cell, clue })
_G.game = { GetClientUIRoots = function() return { rootCtl } end }

local a = Ad.new({ cells = { rows = 5, cols = 5, parent = "root", edge_fit_log = false } })

-------------------------------------------------------------------------------
-- ① 格子的头像 → portrait（不是 face）；② face 的图不许被换；③ obj 不受影响
-------------------------------------------------------------------------------
local r1 = a:set_property("cell.2.2", "image", "portrait.A")
ok(r1 == true, "下发成功（返回 true，实测 " .. tostring(r1) .. "）")
ok(cellPortrait.imageId == 100109,
  "头像落在 portrait 层（实测 imageId=" .. tostring(cellPortrait.imageId) .. "，期望 100109）")
ok(cellPortrait.visible == true, "portrait 可见（实测 " .. tostring(cellPortrait.visible) .. "）")
ok(cellFace.imageId == 100001,
  "face 仍是房间色板、没被头像换掉（实测 " .. tostring(cellFace.imageId) .. "）")
ok(cellObj.visible == false, "家具层没被这次下发点亮（实测 " .. tostring(cellObj.visible) .. "）")
ok(cellPortrait.imageColor == 4294967295,
  "portrait 是原色（房间色只在 face 上，实测 " .. tostring(cellPortrait.imageColor) .. "）")

-------------------------------------------------------------------------------
-- ④ 人拿走（`false` 哨兵）⇒ portrait 必须藏起来
-------------------------------------------------------------------------------
a:set_property("cell.2.2", "image", false)
ok(cellPortrait.visible == false,
  "人走后 portrait 藏起来（实测 " .. tostring(cellPortrait.visible) .. "）")
ok(cellFace.imageId == 100001, "人走后 face 仍是色板（实测 " .. tostring(cellFace.imageId) .. "）")

-------------------------------------------------------------------------------
-- ⑤ 非格子仍走 face（线索卡/选关卡/托盘卡：别把老路改坏）
-------------------------------------------------------------------------------
a:set_property("clue.1", "image", "portrait.A")
ok(clueFace.imageId == 100109,
  "非格子仍画在 face 上（实测 imageId=" .. tostring(clueFace.imageId) .. "，期望 100109）")

-------------------------------------------------------------------------------
-- ⑥ 重放：藏过之后 `_repaint_cell_overlays` 能把头像救回来
-------------------------------------------------------------------------------
a:set_property("cell.2.2", "image", "portrait.A")
cellPortrait.visible = false            -- 模拟"被 hide_kids 递归藏过"
a:_repaint_cell_overlays("cell.2.2")
ok(cellPortrait.visible == true,
  "重放后 portrait 又亮了（实测 " .. tostring(cellPortrait.visible) .. "）")

-------------------------------------------------------------------------------
-- ⑦ 配置：layer_order 必须是 obj → portrait → wall（层序是这条修复的本体）
-------------------------------------------------------------------------------
do
  local f = io.open(root .. "/lua/entry_client_script.lua", "r")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  local order = text:match("layer_order%s*=%s*(%b{})")
  order = order or ""
  local iObj = order:find('"obj"', 1, true)
  local iPor = order:find('"portrait"', 1, true)
  local iWall = order:find('"wall.up"', 1, true)
  ok(iObj ~= nil and iPor ~= nil and iWall ~= nil,
    "layer_order 里三个键都在（obj/portrait/wall.up）")
  ok(iObj ~= nil and iPor ~= nil and iWall ~= nil and iObj < iPor and iPor < iWall,
    "层序 obj → portrait → wall（实测位置 obj=" .. tostring(iObj)
    .. " portrait=" .. tostring(iPor) .. " wall=" .. tostring(iWall) .. "）")
end

print(string.format("\nportrait_layer: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
