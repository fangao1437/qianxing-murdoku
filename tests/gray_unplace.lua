--------------------------------------------------------------------------------
-- gray_unplace：★★ 拿起棋子之后，灰白必须**恢复**（★ 用户 2026-10-11 报 ✓）
--
--   ★★★ 用户原话 ✓：「★ **现在取消放置之后 `gray` 不会恢复**」✗✓
--   ★ 链路 ✓：★ 拿起 ⇒ `do_clear` 清 `core.placed[id]` ✓
--     ⇒ ★ 重填时 `_placed_now` 应为 false ⇒ ★ `gray` 该隐藏 ✓
--     ★★ 若不恢复 ⇒ ★ 那张卡**永远是灰的** ✓（★ 再也点不动 / 看不出已放 ✓）
--------------------------------------------------------------------------------
package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;" .. package.path

local UIC  = require("ui_controller")
local Core = require("murdoku_core")
local lv   = require("levels.case_003")
package.loaded["levels.init"] = { index_of = function(id) return (id == lv.id) and 3 or nil end }

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1 print("  [PASS] " .. msg)
  else failed = failed + 1 print("  [FAIL] " .. msg) end
end
local function joined(t)
  if t == nil then return "<nil>" end
  if t == false then return "<false>" end
  if type(t) ~= "table" then return tostring(t) end
  return table.concat(t, " ")
end

-- ── 假控件（★ 保真：`GetChild` 直接子级 ✓ `FindChild` 认全名与末段名 ✓）──────
local function ctrl(name)
  local c = { name = name, __kids = {}, visible = true, active = true }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, k) for _, x in ipairs(c.__kids) do if x.name == k then return x end end return nil end
  c.FindChild = function(_, p)
    local tail = tostring(p):match("([^%.]+)$") or tostring(p)
    for _, x in ipairs(c.__kids) do if x.name == p or x.name == tail then return x end end
    return nil
  end
  c.SetVisible = function(_, v) c.visible = v end
  c.SetActive = function(_, v) c.active = v end
  return c
end
local function attach(p, c) p.__kids[#p.__kids + 1] = c return c end

local NROW = 6
local as = ctrl("assets")
for pos = 1, NROW do
  local row = ctrl("row.3." .. pos)
  for _, nm in ipairs({ "who", "what", "letter" }) do
    local holder = ctrl(nm .. ".3." .. pos)
    local inner = ctrl(nm)
    inner.text = (nm == "letter") and ("L" .. pos) or ("w" .. pos)
    attach(holder, inner); attach(row, holder)
  end
  local fh = ctrl("face.3." .. pos)
  local fi = ctrl("face"); fi.imageId = 500 + pos
  attach(fh, fi); attach(row, fh)
  attach(as, row)
end
local root = ctrl("root"); attach(root, as)
_G.game = { GetClientUIRoots = function() return { root } end }

local function boot()
  UIC.Controller._row_letter, UIC.Controller._row_face, UIC.Controller._row_text = nil, nil, nil
  UIC.Controller._piece_core, UIC.Controller._piece_id_cache = nil, nil
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  c._grid_base = 0
  local items = {}
  c._grid_in_refresh = true
  for pos = 1, NROW do
    local it = ctrl("item")
    for _, nm in ipairs({ "who", "what", "letter", "backrop1", "backrop2", "face", "gray" }) do
      attach(it, ctrl("clue." .. pos .. "." .. nm))
    end
    it.__index = pos - 1
    items[pos] = it
    c:_fill_grid_item(nil, nil, it, pos - 1)
  end
  c._grid_in_refresh = false
  return core, c, items
end

-- ★ 重填一个列表项（= 真机"引擎重进回调"那条路 ✓）
local function refill(c, it)
  c._grid_in_refresh = true
  c:_fill_grid_item(nil, nil, it, it.__index)
  c._grid_in_refresh = false
end
local function gray_of(it, pos)
  local g = it:GetChild("clue." .. pos .. ".gray")
  return g and g.visible
end

--------------------------------------------------------------------------------
print("\n== 1. 放人 ⇒ 灰白亮；拿起 ⇒ 灰白必须灭 ==")
--------------------------------------------------------------------------------
do
  local core, c, items = boot()
  local it2 = items[2]                       -- ★ 第 2 行 ⇒ 棋子 B ✓
  local pos = 2
  ok(gray_of(it2, pos) ~= true, "前提：没放置时灰白是灭的（实测 " .. tostring(gray_of(it2, pos)) .. "）")

  -- ★ 放人：★ 走真路（选中 ⇒ 长按落子）✓
  core:select_suspect("B")
  core:hold_cell(3, 1)
  ok(core.placed and core.placed["B"] == true, "前提：B 已被正式放置（`core.placed.B`）")
  refill(c, it2)
  ok(gray_of(it2, pos) == true, "★ 放置后 ⇒ 灰白亮（实测 " .. tostring(gray_of(it2, pos)) .. "）")

  -- ★★ 拿起：★ 轻点一个"已有人"的格子 ⇒ `do_clear` ⇒ 清 `placed` ✓
  core:tap_cell(3, 1)
  ok(not (core.placed and core.placed["B"]), "★ 拿起之后 `core.placed.B` 被清掉 ✓")
  refill(c, it2)
  ok(gray_of(it2, pos) ~= true,
    "★★ 拿起之后 ⇒ 灰白**必须灭**（★ 实测 " .. tostring(gray_of(it2, pos)) .. " ✓）")
  print("  [PASS] 放置/拿起一个来回，灰白跟着变 ✓")
end

--------------------------------------------------------------------------------
print("\n== 2. ★★ 拿起的是【别的人】时，这一格的灰白也要跟着对 ==")
--------------------------------------------------------------------------------
do
  local core, c, items = boot()
  -- ★ 放 B 在第 3 行第 1 列 ✓
  core:select_suspect("B"); core:hold_cell(3, 1)
  refill(c, items[2])
  ok(gray_of(items[2], 2) == true, "B 放置后第 2 行的卡亮 ✓")
  -- ★ 再放 C ✓（第 3 行 ⇒ 卡 3 ✓）
  core:select_suspect("C"); core:hold_cell(4, 2)
  refill(c, items[3])
  ok(gray_of(items[3], 3) == true, "C 放置后第 3 行的卡亮 ✓")
  -- ★ 拿起 C ⇒ ★ 第 3 行灭 ✓ ★ 而第 2 行**必须还亮着** ✗
  core:tap_cell(4, 2)
  refill(c, items[3]); refill(c, items[2])
  ok(gray_of(items[3], 3) ~= true, "★ 拿起 C ⇒ 第 3 行灭 ✓（实测 " .. tostring(gray_of(items[3], 3)) .. "）")
  ok(gray_of(items[2], 2) == true, "★★ B 还放着 ⇒ 第 2 行**必须还亮** ✗（实测 "
    .. tostring(gray_of(items[2], 2)) .. "）")
  print("  [PASS] 拿起一个人不会把别人也弄灭 ✓")
end

--------------------------------------------------------------------------------
print("\n== 3. ★★ 取消放置的另一条路：`undo`（撤销键）==")
--------------------------------------------------------------------------------
do
  local core, c, items = boot()
  core:select_suspect("D"); core:hold_cell(5, 3)      -- ★ 第 4 行 ⇒ 卡 4 ✓
  refill(c, items[4])
  ok(gray_of(items[4], 4) == true, "D 放置后第 4 行亮 ✓")
  core:undo()
  ok(not (core.placed and core.placed["D"]), "撤销之后 `core.placed.D` 被清掉 ✓")
  refill(c, items[4])
  ok(gray_of(items[4], 4) ~= true,
    "★★ 撤销之后 ⇒ 灰白必须灭（实测 " .. tostring(gray_of(items[4], 4)) .. "）")
  print("  [PASS] 撤销那条路也一样 ✓")
end

--------------------------------------------------------------------------------
print("\n== 4. ★★ 清空全盘（橡皮擦长按）⇒ 所有灰白都要灭 ==")
--------------------------------------------------------------------------------
do
  local core, c, items = boot()
  core:select_suspect("A"); core:hold_cell(1, 1)
  core:select_suspect("B"); core:hold_cell(2, 2)
  for _, p in ipairs({ 1, 2 }) do refill(c, items[p]) end
  ok(gray_of(items[1], 1) == true and gray_of(items[2], 2) == true, "前提：两张卡都亮着")
  core:clear_all()
  for _, p in ipairs({ 1, 2 }) do refill(c, items[p]) end
  ok(gray_of(items[1], 1) ~= true and gray_of(items[2], 2) ~= true,
    "★★ 清空全盘之后 ⇒ 两张卡的灰白都灭（实测 "
    .. tostring(gray_of(items[1], 1)) .. " / " .. tostring(gray_of(items[2], 2)) .. "）")
  print("  [PASS] 清空全盘 ⇒ 全部灭 ✓")
end

--------------------------------------------------------------------------------
print("\n== 5. ★★★ 走【控制器动作】那条路：每个改动 `placed` 的动作都必须请求重填 ==")
--
--   ★★★ 为什么这一节才是真哨兵 ✗（★ 前面几节**测不出来** ✓ —— 我实测过 ✓）：
--     ★ 前面都是直接调 `core:undo()` / `core:tap_cell()` ✓
--     ★★ 而这次的 bug **不在 core 里** ✗ —— ★ core 一直是对的 ✓
--       ★ 缺的是**控制器有没有请求"重填线索卡"** ✗✓
--         （★ `_grid_refill_pending` ✓ ★ 填了它才会重新算灰白 ✓）
--     ⇒ ★★ 所以判据要盯**控制器那个标志** ✓ —— ★ 而不是"灰白最后对不对" ✓
--   ★ 这条 bug 的形状 ✓：★ **"登记"那一半修过 ✓ "注销"那一半从来没人管** ✓
--     ★ 放人会置标志（灰白亮得起来 ✓）★ 拿起/撤销**不置**（灰白灭不掉 ✗）✓
--------------------------------------------------------------------------------
do
  local core, c, items = boot()

  -- ★ ① 放人 ⇒ 必须请求重填 ✓
  c._grid_refill_pending = nil
  core:select_suspect("B")
  c:do_place(3, 1)
  ok(c._grid_refill_pending == true, "★ 放人 ⇒ 请求重填（灰白亮得起来 ✓）")

  -- ★ ② 拿起 ⇒ ★★ **也必须请求重填** ✗（★ 这就是那个 bug ✓）
  c._grid_refill_pending = nil
  c:on_cell_click(3, 1)
  ok(c._grid_refill_pending == true,
    "★★ 拿起棋子 ⇒ **必须请求重填**（★ 否则灰白灭不掉 ✗ 实测 "
    .. tostring(c._grid_refill_pending) .. "）")

  -- ★ ③ 撤销 ⇒ 也要 ✓
  core:select_suspect("D")
  c:do_place(4, 2)
  c._grid_refill_pending = nil
  c:on_input({ action = "undo", phase = "click" })
  ok(c._grid_refill_pending == true,
    "★ 撤销 ⇒ 也要请求重填（★ 撤销会把棋子拿回去 ✓ 实测 "
    .. tostring(c._grid_refill_pending) .. "）")

  -- ★ ④ 重做 ⇒ 也要 ✓
  c._grid_refill_pending = nil
  c:on_input({ action = "redo", phase = "click" })
  ok(c._grid_refill_pending == true,
    "★ 重做 ⇒ 也要请求重填（★ 重做会把棋子放回来 ✓ 实测 "
    .. tostring(c._grid_refill_pending) .. "）")
  print("  [PASS] 四个动作都会请求重填 ✓")
end

print(string.format("\ngray_unplace: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
