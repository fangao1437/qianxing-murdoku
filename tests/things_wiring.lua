--[[----------------------------------------------------------------------------
  tests/things_wiring.lua —— 2026-10-17 三条「素材/图层」接线的离线断言

  针对用户这一轮的要求（原话）：
    「模板已经修改了，颜色也已经调好了，你现在只需要管显示就行了，
      顺便把前两关设计图中的门墙渲染，障碍物等都准备好，
      障碍物单独建一个 things 区域用来放它们的美术素材」

  ⇒ 钉三件事（全部用**假控件树**跑真适配器 ✓，不碰引擎）：
    ① `hint`：提示层是模板里的子控件（在 `content` 下），脚本**只开关可见性**、
       **绝不写它的颜色**（颜色归编辑器：0x7F0063D5）
    ② `things`：调色板要能读到 `things/obj.<kind>`（图 + 色）⇒ `cell` 的 `obj` 照抄
    ③ `wall.*` / `door.*`：按 `view().cells[r][c].walls/doors` 开关（穿透 `content` 找）

  跑法：lua tests/things_wiring.lua
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

-- ── 假控件（只实现适配层用到的那些）──────────────────────────────────────
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
  -- ★ 2026-10-17 新增：几何读写（`_fit_child_to_cell` 要用）
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

-- 与 397 存档同构：cell.1.1 → content → { face, hint, obj, wall.*, note, door.* }
local HINT_COLOR = 2130731989      -- 0x7F0063D5（用户调好的半透明蓝）
local face = ctrl("face", {}, { imageId = 100001, imageColor = 4294967295 })
local hint = ctrl("hint", {}, { imageId = 100001, imageColor = HINT_COLOR, visible = true })
local obj  = ctrl("obj",  {}, { imageId = 100001, imageColor = 4294967295, visible = false })
local wallUp = ctrl("wall.up", {}, { imageId = 100108, imageColor = 4281536672, visible = false })
local wallDown = ctrl("wall.down", {}, { imageId = 100108, imageColor = 4281536672, visible = false })
local doorUp = ctrl("door.up", {}, { imageId = 100001, imageColor = 4292271642, visible = false })
local content = ctrl("content", { face, hint, obj, wallUp, wallDown, doorUp })
local cell = ctrl("cell.1.1", { content })
cell.kind = "button"
cell.sizeDeltaX, cell.sizeDeltaY = 108, 108   -- 5×5 关的格子边长（画布）

-- `things` 调色板：名字 = 脚本引用键；色块占位（真图在编辑器里换）
local KINDS = {
  { name = "obj.table",  color = 0xFFB07946 },
  { name = "obj.plant",  color = 0xFF4CAF50 },
  { name = "obj.carpet", color = 0xFFD9C8A6 },
  { name = "obj.chair",  color = 0xFFE0A040 },
  { name = "obj.shelf",  color = 0xFF7A5230 },
  { name = "obj.statue", color = 0xFFB8B8C0 },
}
local thingKids = {}
for _, k in ipairs(KINDS) do
  thingKids[#thingKids + 1] = ctrl(k.name, {}, {
    imageId = 100001, imageColor = k.color, imageSource = "StaticReference",
  })
end
local things = ctrl("things", thingKids)
local assets = ctrl("assets", {})
local rootCtl = ctrl("root", { cell, things, assets })

_G.game = { GetClientUIRoots = function() return { rootCtl } end }

local a = Ad.new({ cells = { rows = 5, cols = 5 } })

--------------------------------------------------------------------------------
-- ① `sub()` 必须**穿透 `content`** 找到 hint / obj / wall.up
--------------------------------------------------------------------------------
ok(a:sub("cell.1.1", "hint") == hint, "sub(cell,'hint') 找到 content/hint")
ok(a:sub("cell.1.1", "obj") == obj, "sub(cell,'obj') 找到 content/obj")
ok(a:sub("cell.1.1", "wall.up") == wallUp, "sub(cell,'wall.up') 找到 content/wall.up")
ok(a:sub("cell.1.1", "door.up") == doorUp, "sub(cell,'door.up') 找到 content/door.up")

--------------------------------------------------------------------------------
-- ② 提示层：只开关可见性，**颜色一个字都不写**
--------------------------------------------------------------------------------
hint.visible = false
local r1 = a:set_property("cell.1.1", "hint", true)
ok(r1 == true, "set_property(cell,'hint',true) 返回 true（算送达）")
ok(hint.visible == true, "hint 打开了（visible=true）")
ok(hint.imageColor == HINT_COLOR, "hint 的颜色没被脚本改（仍是编辑器里的 0x7F0063D5）")
a:set_property("cell.1.1", "hint", false)
ok(hint.visible == false, "hint 关掉了（visible=false）")
-- ★ 反向：单元格上没有 hint 时不该报错/不该重试
local ok_missing = pcall(function() return a:set_property("cell.9.9", "hint", true) end)
ok(ok_missing == true, "没有这一格时 hint 写入不抛错（静默算送达）")

--------------------------------------------------------------------------------
-- ③ `things` 调色板：图 + 色都要读得到，并照抄到格子的 `obj`
--------------------------------------------------------------------------------
local pal = a:read_palette()
ok(type(pal) == "table", "read_palette 返回表")
for _, k in ipairs(KINDS) do
  local hit = pal[k.name]
  ok(hit ~= nil and hit.id == 100001, "调色板里有 " .. k.name .. "（imageId=100001）")
  ok(hit ~= nil and hit.color == k.color,
    "调色板读到 " .. k.name .. " 的颜色 0x" .. string.format("%08X", k.color))
end

obj.visible = false
obj.imageId = 100001
obj.imageColor = 4294967295
a:set_property("cell.1.1", "object", "obj.chair")
ok(obj.visible == true, "有家具 ⇒ obj 显示")
ok(obj.imageId == 100001, "obj 的图来自调色板（imageId=100001）")
ok(obj.imageColor == 0xFFE0A040, "obj 的颜色照抄调色板（0xFFE0A040 = 椅子）")
a:set_property("cell.1.1", "object", false)
ok(obj.visible == false, "没有家具（false）⇒ obj 藏起来（不压头像 ✓）")

--------------------------------------------------------------------------------
-- ④ 门墙：按 flags 开关（内部边只由上一格画 —— 见 `_apply_edges` 的约定）
--------------------------------------------------------------------------------
a:set_property("cell.1.1", "walls", { up = true, down = false, left = false, right = false })
ok(wallUp.visible == true, "walls.up=true ⇒ wall.up 可见")
ok(wallDown.visible == false, "walls.down=false ⇒ wall.down 保持关闭")
a:set_property("cell.1.1", "doors", { up = true, down = false, left = false, right = false })
ok(doorUp.visible == true, "doors.up=true ⇒ door.up 可见")
ok(doorUp.imageColor == 4292271642,
  "门的颜色脚本**一个字不动**（仍是这份假树里的 0xFFD6DE1A）—— 配色归存档 ✓")

--------------------------------------------------------------------------------
-- ⑤ ★ 2026-10-17：三层都"钉成格子大小"，不许溢出（用户真机回报"溢出格子"）
--     · 5×5 的格子 = 108 画布；6×6 = 89 画布（`cell_geometry` 里算的）
--     · `_fit_child_to_cell` 按**格子当前尺寸**写子控件的 sizeDelta / 居中
--------------------------------------------------------------------------------
ok(hint.sizeDeltaX == 108 and hint.sizeDeltaY == 108,
  "hint 被钉成 108×108（= 格子尺寸）—— 实测 " .. tostring(hint.sizeDeltaX) .. "×" .. tostring(hint.sizeDeltaY))
ok(hint.anchoredPositionX == 0 and hint.anchoredPositionY == 0, "hint 居中（anchoredPosition = 0,0）")
a:set_property("cell.1.1", "tint", 4294967295)   -- 房间色下发（每格每关都会发一次）
ok(face.sizeDeltaX == 108 and face.sizeDeltaY == 108, "face 也被钉成 108×108")
ok(obj.sizeDeltaX == 108 and obj.sizeDeltaY == 108, "obj 也被钉成 108×108")

-- 换到 6×6（格子 89）⇒ 三个图层都要跟着缩，不许停在 108（否则 6×6 会溢出一圈）
cell.sizeDeltaX, cell.sizeDeltaY = 89, 89
a:set_property("cell.1.1", "hint", true)
a:set_property("cell.1.1", "object", "obj.chair")
a:set_property("cell.1.1", "tint", 4294967295)
ok(hint.sizeDeltaX == 89 and hint.sizeDeltaY == 89, "6×6（89）⇒ hint 跟着缩到 89")
ok(obj.sizeDeltaX == 89 and obj.sizeDeltaY == 89, "6×6（89）⇒ obj 跟着缩到 89")
ok(face.sizeDeltaX == 89 and face.sizeDeltaY == 89, "6×6（89）⇒ face 跟着缩到 89")
ok(hint.pivotX == 0.5 and hint.anchorMinX == 0.5 and hint.anchorMaxX == 0.5,
  "hint 的锚点/轴心 = 0.5（居中铺满，不靠编辑器那套 135 定值）")
ok(doorUp.imageColor == 4292271642, "door 的颜色是编辑器里那一份（0xFFD6DE1A）")

--------------------------------------------------------------------------------
-- ⑥ ★ 2026-10-18 v258：**存档里没有任何素材控件**时，家具素材由 `cfg.obj_art` 提供
--    背景：用户实测「395 没错 / 错误从 396 起」（396 = 我第一次在**存档里新建** `things` 区）
--    ⇒ 不再新建控件：图 + 色写进脚本配置 ✓（`read_palette`：**控件优先、配置补缺**）
--------------------------------------------------------------------------------
do
  local saved = _G.game
  _G.game = { GetClientUIRoots = function() return { ctrl("root", { cell }) } end }   -- ★ 没有 things / assets
  local a3 = Ad.new({ cells = { rows = 5, cols = 5 },
    obj_art = { chair = { id = 100001, color = 0xFFE0A040 } } })
  local pal3 = a3:read_palette()
  ok(pal3["obj.chair"] ~= nil, "没有素材控件时 cfg.obj_art 仍提供 obj.chair")
  ok(pal3["obj.chair"] ~= nil and pal3["obj.chair"].id == 100001, "cfg.obj_art 的 imageId = 100001")
  ok(pal3["obj.chair"] ~= nil and pal3["obj.chair"].color == 0xFFE0A040, "cfg.obj_art 的 color = 0xFFE0A040")
  ok(pal3["obj.chair"] ~= nil and pal3["obj.chair"].from == "cfg.obj_art", "来源标记 = cfg.obj_art（排障用）")
  _G.game = saved
end

--------------------------------------------------------------------------------
print(string.format("\n结果：%d 通过 / %d 失败", passed, failed))
if failed > 0 then os.exit(1) end
