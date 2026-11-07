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
-- ⑦ ★★ 2026-10-20 **"第一次进第一关：家具/障碍物不画"** 的回归（真机 bug）
--
--   用户原话：「第一次进入第一关**障碍物和家具**会渲染不出来，进入第二关后重新回到第一关就有了，
--              这个问题在门墙渲染上曾出现过」
--
--   机制（仓内已有先例，见 `engine_adapter_qianxing.lua` 的 `_edge_want` 长注释 +
--   `set_property` 的 `visible` 分支）：
--     · `visible=false` 且 id 以 `cell.` 开头 ⇒ `hide_kids(ctrl, 0)` **递归**把所有子控件设 false
--     · 而它**只藏不显**（单向）⇒ 子控件必须有人**每帧**把"该亮的"重新点亮
--     · `face` 有（`_cells_paint` 每帧点亮）✓　`wall.*`/`door.*` 有（`_edge_want` 每帧重放）✓
--     · **`obj` 没有** ✗ ⇒ 第一关（格子是这一帧新建的、会走一次 false→true）家具全灭；
--       第二关起**不重建格子** ⇒ 没有 false→true ⇒ 不触发递归藏 ⇒ 家具正常 ✓✓
--   ⇒ 本节的判据就是那句话：**藏过之后，每帧那条路必须把 obj 救回来**。
--------------------------------------------------------------------------------
do
  -- ⑦.1 先把家具画上（记下意图），再模拟 `hide_kids` 递归藏一次
  a:set_property("cell.1.1", "object", "obj.chair")
  ok(obj.visible == true, "⑦.1 前置：家具先正常画出来")
  obj.visible = false                  -- ← `hide_kids` 干的就是这件事
  a:_cells_paint(cell, 108, "cell.1.1")
  ok(obj.visible == true,
    "⑦.1 ★ `hide_kids` 藏过之后，每帧的 `_cells_paint` 必须把 obj 救回来（第一关家具不画的根因）")
  ok(obj.imageColor == 0xFFE0A040, "⑦.1 救回来时颜色仍是调色板里那一份（没被冲掉）")

  -- ⑦.2 反向：**本来就不该有家具**的格子，每帧重放不许把它点亮（防过度修正）
  a:set_property("cell.1.1", "object", false)
  ok(obj.visible == false, "⑦.2 前置：object=false ⇒ obj 藏起来")
  a:_cells_paint(cell, 108, "cell.1.1")
  ok(obj.visible == false, "⑦.2 ★ 没有家具的格子，每帧重放**不许**把它点亮（否则白板压住头像）")

  -- ⑦.3 子控件晚一步就绪：**先记意图，后补画**（首帧 `content/obj` 取不到也要能自愈）
  local face2 = ctrl("face", {}, { imageId = 100001, imageColor = 4294967295 })
  local content2 = ctrl("content", { face2 })          -- ← 此刻还没有 obj
  local cell2 = ctrl("cell.1.2", { content2 })
  cell2.kind = "button"
  cell2.sizeDeltaX, cell2.sizeDeltaY = 108, 108
  rootCtl._kids[#rootCtl._kids + 1] = cell2
  a:invalidate_lookups("test:cell.1.2 新建")
  local r_late = a:set_property("cell.1.2", "object", "obj.table")
  ok(r_late == true, "⑦.3 子控件还没就绪时写入算送达（记下意图，不刷屏重试）")
  -- 子控件随后就绪（引擎侧等价于"这一格被补建/模板实例化晚了一步"）
  local obj2 = ctrl("obj", {}, { imageId = 100001, imageColor = 4294967295, visible = false })
  content2._kids[#content2._kids + 1] = obj2
  a:invalidate_lookups("test:content/obj 就绪")
  a:_cells_paint(cell2, 108, "cell.1.2")
  ok(obj2.visible == true,
    "⑦.3 ★ 子控件晚一步就绪 ⇒ 那条重放路要把它补画出来（不必等玩家再点一次/换关）")
  ok(obj2.imageColor == 0xFFB07946, "⑦.3 补画时颜色来自调色板（0xFFB07946 = 桌子）")

  -- ⑦.4 ★★ **真正的触发路径**：`cell.*` 走一次 `visible=false → true`（第一关开局就是这条）
  --   真机的递归藏是 `hide_kids()` 做的（假树里 `set_property(…, "visible", false)` 会真的调到它），
  --   所以这里**不手动置 false**，让被测代码自己藏 —— 这样才钉得住"谁来救"。
  a:set_property("cell.1.1", "object", "obj.chair")
  a:set_property("cell.1.1", "walls", { up = true, down = false, left = false, right = false })
  ok(obj.visible == true and wallUp.visible == true, "⑦.4 前置：家具与门墙都亮着")
  a:set_property("cell.1.1", "visible", false)      -- ← 这里会触发 hide_kids 递归藏
  ok(obj.visible == false and wallUp.visible == false,
    "⑦.4 前置：递归藏生效（家具与门墙都被压成 false —— 与真机日志同形）")
  a:set_property("cell.1.1", "visible", true)       -- ← 回关卡内（显示方向不递归，这是既有设计）
  a:on_tick(0.016)                                  -- ← 每帧那条路（main.lua 的 on_update 会调它）
  ok(obj.visible == true,
    "⑦.4 ★ cell 由藏转显之后，on_tick 必须把**家具**救回来（第一关的真实触发路径）")
  ok(wallUp.visible == true,
    "⑦.4 ★ 同一趟也要把**门墙**救回来（这条重放原来挂在只会跑一次的 _cells_paint 上，等于没有）")
end

--------------------------------------------------------------------------------
-- ⑧ ★★ 2026-10-20（v282）调色板的两个历史陷阱（与"首关家具不画"同一族：**读得太早**）
--
--   ① `imageId = 0`（= 这张图还没配）的控件**不许进调色板** ——
--      否则它会把好键毒掉（`SetImage(src, 0)` = 没图），而 `cfg.obj_art` 的兜底
--      又因为"键已存在"被跳过 ⇒ 配了脚本素材也不生效，且完全静默。
--   ② **空调色板不许缓存** —— 首帧树还没就绪时读到空表，原来会永久缓存 ⇒ 整局解析不出素材。
--------------------------------------------------------------------------------
do
  local saved = _G.game
  -- ⑧.1 `things/obj.table` 在、但图没配（imageId = 0）⇒ 必须落到 cfg.obj_art
  local badKid = ctrl("obj.table", {}, { imageId = 0, imageColor = 0xFFB07946 })
  _G.game = { GetClientUIRoots = function() return { ctrl("root", { ctrl("things", { badKid }) }) } end }
  local a8 = Ad.new({ cells = { rows = 5, cols = 5 },
    obj_art = { table = { id = 100001, color = 0xFFB07946 } } })
  local pal8 = a8:read_palette()
  ok(pal8["obj.table"] ~= nil and pal8["obj.table"].id == 100001,
    "⑧.1 imageId=0 的控件不进调色板 ⇒ 用 cfg.obj_art 的 100001（不被毒键挡住）",
    pal8["obj.table"] and tostring(pal8["obj.table"].id))
  ok(pal8["obj.table"] ~= nil and pal8["obj.table"].from == "cfg.obj_art",
    "⑧.1 来源标记 = cfg.obj_art（排障用）")

  -- ⑧.2 树里暂时没有 things/assets（也没有 obj_art）⇒ 空表**不缓存**，树就绪后能读到
  _G.game = { GetClientUIRoots = function() return { ctrl("root", { ctrl("cell.1.1", {}) }) } end }
  local a9 = Ad.new({ cells = { rows = 5, cols = 5 } })
  local empty = a9:read_palette()
  ok(type(empty) == "table" and next(empty) == nil, "⑧.2 前置：此刻调色板确实是空的")
  -- 素材区随后就绪（引擎侧等价于"控件后来才实例化出来"）
  _G.game = { GetClientUIRoots = function()
    return { ctrl("root", { ctrl("things", { ctrl("obj.chair", {}, { imageId = 100001, imageColor = 0xFFE0A040 }) }) }) }
  end }
  a9:invalidate_lookups("test:things 就绪")
  local later = a9:read_palette()
  ok(later["obj.chair"] ~= nil and later["obj.chair"].id == 100001,
    "⑧.2 ★ 空表**没有**被永久缓存 ⇒ 素材区就绪后能读到（首帧读太早不再等于整局没有素材）")
  _G.game = saved
end

--------------------------------------------------------------------------------
print(string.format("\n结果：%d 通过 / %d 失败", passed, failed))
if failed > 0 then os.exit(1) end
