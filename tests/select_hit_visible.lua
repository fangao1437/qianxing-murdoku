--[[----------------------------------------------------------------------------
  tests/select_hit_visible.lua —— 选关屏的**命中层**与**翻页箭头**（2026-10-15 真机那两件事）

  为什么要有它（用户 2026-10-15 真机截图 + 原话）：
    ★「**左右箭头没加上去，功能也没换绑到新的方块上**」✗
    ★ 截图里 4 张卡在**正确的位置**（几何已经修好了 ✓）但**点了没反应** ✓

  ★★ 根因 ①（点不动 ✓）：`ui_controller.lua` 的 `apply_screen_hide` 里，
    主页/选关那一支的 `PREFIX` 名单含 **`"hit."`** ✗ ——
    ★ 那条前缀本来是给**关卡内**那七颗 `hit.*` 用的 ✓
    　 ⇒ ★ 它**同时命中选关屏自己的 `hit.select.*`** ✗✗
    　 ⇒ ★★ 选关屏**每帧**把这 7 个命中层设成 `visible = false` ✓
    　 ⇒ ★★★ **可视层（白卡）在、命中层被藏 ⇒ 点哪儿都没反应** ✓✓
    ★ 为什么一直没被发现 ✗：★ 命中层**本来就是隐形的** ✓
    　 ⇒ ★ "被藏了"与"正常隐藏"在屏幕上**长得一模一样** ✓
    　 ⇒ ★ 只有"点击没反应"这一个可观察差异 ✓（用户正是这么报的 ✓）

  ★★ 根因 ②（箭头看不到 ✓）：★ 脚本是「四关一页」✓ 而当时**只有 4 关** ✓
     ⇒ `pages = 1` ⇒ 旧写法 `pg_visible = (pages > 1)` ⇒ **整组隐藏** ✗
     ⇒ ★ 玩家看到的选关屏**没有左右箭头** ✓（用户就是这么报的 ✓）
     ⇒ ★ 新写法：★ **可见性 = 这一屏有没有**（永远有 ✓）·
        ★ **可用性 = 这个方向能不能翻**（不能翻就**变暗** ✓）

  跑法：lua tests/select_hit_visible.lua
------------------------------------------------------------------------------]]--

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local Core     = require("murdoku_core")
local UIC      = require("ui_controller")
local Qianxing = require("engine_adapter_qianxing")
local Fx       = require("tests.fixtures")

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

local NORMAL_TINT, DIM_TINT = 4294967295, 2147483647

-- 关卡清单：★ 4 关 = 一页（正是用户当时的处境 ✓）；5 关 = 两页（用来验"能翻" ✓）
local function level_entry(id, name)
  return { id = id, name = name, size = { rows = 5, cols = 5 }, suspects = {} }
end
local FOUR = { level_entry("a", "案件 A"), level_entry("b", "案件 B"),
               level_entry("c", "案件 C"), level_entry("d", "案件 D") }
local FIVE = { level_entry("a", "案件 A"), level_entry("b", "案件 B"),
               level_entry("c", "案件 C"), level_entry("d", "案件 D"),
               level_entry("e", "案件 E") }

local function plan_of(screen, levels)
  local c = UIC.new(Core.new(Fx.clue_level_5x5()), {
    skip_intro = true, levels = levels, screen = screen,
    on_pick_level = function() end,
  })
  local nodes = c:build_layout()
  local by = {}
  for i = 1, #nodes do by[nodes[i].id] = nodes[i] end
  return by
end

local HITS_SELECT = { "hit.select.back", "hit.select.prev", "hit.select.next",
                      "hit.select.card.1", "hit.select.card.2",
                      "hit.select.card.3", "hit.select.card.4" }
local HITS_LEVEL  = { "hit.back", "hit.submit", "hit.redo", "hit.undo",
                      "hit.hint", "hit.ok", "hit.no" }

----------------------------------------------------------------------------
print("== 1. 选关屏：7 个命中层必须【可见】（不可见 = 点不动 ✓）==")
do
  local by = plan_of("select", FOUR)
  local hidden = {}
  for _, id in ipairs(HITS_SELECT) do
    if by[id] == nil then
      ok(false, id .. " 在规划里存在", "★ 规划里没有它 ⇒ 连藏不藏都谈不上")
    else
      ok(by[id].visible == true, id .. " visible = true", "实测 = " .. tostring(by[id].visible))
      if by[id].visible ~= true then hidden[#hidden + 1] = id end
    end
  end
  if #hidden > 0 then
    print("      ★ 被藏住的命中层：" .. table.concat(hidden, " "))
    print("      ★ 这就是『卡片看得见、点了没反应』的直接原因 ✓")
  end
end

----------------------------------------------------------------------------
print("")
print("== 2. 选关屏：可视层仍然可见（别把可视层一起修没了 ✓）==")
do
  local by = plan_of("select", FOUR)
  for _, id in ipairs({ "select.card.1", "select.card.2", "select.card.3",
                        "select.card.4", "select.back", "select.title" }) do
    if by[id] ~= nil then
      ok(by[id].visible == true, id .. " visible = true", "实测 = " .. tostring(by[id].visible))
    end
  end
end

----------------------------------------------------------------------------
print("")
print("== 3. 关卡内那七颗 hit.* 仍必须在主页/选关被藏（改写前缀不许把它们漏出来 ✓）==")
do
  local by = plan_of("home", FOUR)
  for _, id in ipairs(HITS_LEVEL) do
    if by[id] ~= nil then
      ok(by[id].visible ~= true, id .. " 在主页被藏", "实测 = " .. tostring(by[id].visible))
    end
  end
  -- 选关屏上它们也要被藏（那是关卡内的东西 ✓）
  local sel = plan_of("select", FOUR)
  for _, id in ipairs(HITS_LEVEL) do
    if sel[id] ~= nil then
      ok(sel[id].visible ~= true, id .. " 在选关屏也被藏", "实测 = " .. tostring(sel[id].visible))
    end
  end
end

----------------------------------------------------------------------------
print("")
print("== 4. 翻页箭头：★ 只有一页时【也要看得见】，只是**变暗** ==")
do
  local by = plan_of("select", FOUR)          -- 4 关 ⇒ pages = 1
  ok(by["select.prev"] ~= nil and by["select.prev"].visible == true,
    "一页时 select.prev 仍然可见", by["select.prev"] and ("实测 = " .. tostring(by["select.prev"].visible)))
  ok(by["select.next"] ~= nil and by["select.next"].visible == true,
    "一页时 select.next 仍然可见", by["select.next"] and ("实测 = " .. tostring(by["select.next"].visible)))
  ok(by["select.prev"] and by["select.prev"].tint == DIM_TINT,
    "一页时 select.prev **变暗**（0x7FFFFFFF）", by["select.prev"] and ("实测 = " .. tostring(by["select.prev"].tint)))
  ok(by["select.next"] and by["select.next"].tint == DIM_TINT,
    "一页时 select.next **变暗**（0x7FFFFFFF）", by["select.next"] and ("实测 = " .. tostring(by["select.next"].tint)))
  ok(by["hit.select.prev"] and by["hit.select.prev"].visible == true, "一页时命中层仍可见（点了夹紧、不越界）")
  ok(by["select.page"] ~= nil and by["select.page"].visible == true
     and by["select.page"].text == "第 1 / 1 页",
    "页码显示「第 1 / 1 页」—— 正好解释箭头为什么是暗的",
    by["select.page"] and ("实测 = " .. tostring(by["select.page"].text)))
end

----------------------------------------------------------------------------
print("")
print("== 5. 翻页箭头：★ 有两页时【左边暗、右边亮】，且命中层绑着事件 ==")
do
  local by = plan_of("select", FIVE)          -- 5 关 ⇒ pages = 2
  ok(by["select.prev"] and by["select.prev"].tint == DIM_TINT, "第 1 页：prev 变暗")
  ok(by["select.next"] and by["select.next"].tint == NORMAL_TINT, "第 1 页：next 亮（可翻）")
  ok(by["select.page"] and by["select.page"].text == "第 1 / 2 页", "页码 = 第 1 / 2 页",
    by["select.page"] and by["select.page"].text)
  local ev = by["hit.select.next"] and by["hit.select.next"].event or nil
  ok(ev ~= nil and ev.action == "select_page" and tonumber(ev.delta) == 1,
    "命中层 hit.select.next 绑着 select_page +1", ev and ("实测 = " .. tostring(ev.action)))
  local ev2 = by["hit.select.prev"] and by["hit.select.prev"].event or nil
  ok(ev2 ~= nil and tonumber(ev2.delta) == -1, "命中层 hit.select.prev 绑着 select_page -1")
end

----------------------------------------------------------------------------
print("")
print("== 6. 染色：★ `{r,g,b,a}` 能自己打包成引擎认的整数（真机没有全局 Color ✓）==")
do
  ok(Qianxing.pack_color(250, 244, 232) == 4294636776,
    "米色 #FAF4E8 → 0xFFFAF4E8（不给 a = 不透明 ✓）", "实测 = " .. tostring(Qianxing.pack_color(250, 244, 232)))
  ok(Qianxing.pack_color(255, 255, 255) == NORMAL_TINT, "白 → 0xFFFFFFFF（原色 ✓）",
    "实测 = " .. tostring(Qianxing.pack_color(255, 255, 255)))
  ok(Qianxing.pack_color(255, 255, 255, 127) == DIM_TINT, "白 + a=127 → 0x7FFFFFFF（减淡 ✓）",
    "实测 = " .. tostring(Qianxing.pack_color(255, 255, 255, 127)))
  -- 越界要夹住（不然整数会溢出成别的颜色 ✓）
  ok(Qianxing.pack_color(300, -5, 999, 300) == 4294902015, "越界夹到 0..255（A→255 R→255 G→0 B→255 = 0xFFFF00FF）",
    "实测 = " .. tostring(Qianxing.pack_color(300, -5, 999, 300)))
end

print("")
print(string.format("select_hit_visible: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
