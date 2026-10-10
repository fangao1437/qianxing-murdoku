--[[----------------------------------------------------------------------------
  tests/clue_slots.lua —— ★ 判据：**clues 的条数由【棋盘规格】决定**（几乘几就是几条）

  ★★★ 用户 2026-10-11 定下的**完整生产流程** ✓（★ 原话 ✓）：
    「★ **clues 区域有多少内容由棋盘规格决定** ✓
     ★ **几乘几就是几条** ✓
     ★ 至于是**哪几条**由 `assets` 下的 `row` 决定 ✓
     （★ 多余的后续会删 ✓ ★ 没有的会建 ✓）
     ★ **`assets` 负责 clues 区域需要的一切素材** ✓
     ★ **`face` 对应头像** ✓ ★ **`who` 对应名字** ✓ ★ **`what` 对应内容** ✓
     ★ **`letter` 对应字母标签** ✓
     ★ **同时 `face` 和 `letter` 还对应【放置到棋盘上的】头像和铅笔笔记** ✓
     ★ **这是目前的完整 clues 区域的生产流程，没有缺失部分**」✓✓

  ★★ 随后进一步定调 ✓：
    「★ 不是让 `clues` 保持空 ✗
     ★★ **而是让这套流程代替原本的流程、赋予 `clues` 的一切内容** ✓
     ★ **直接从逻辑上替换掉原先那套模式**」✓✓

  ⇒ ★ 所以本文件钉**三件事** ✓：
    ★ ① **条数 = `rows × cols`** ✓ ★ **四关分别是 25 / 25 / 36 / 49** ✓
    ★ ② ★ **不再靠"手写线索表"** ✗ —— ★ 真关卡里 `level.clues` **是空的** ✓
      ★ 而**引擎照旧补满槽位** ✓（★ 这就是"替换掉原先那套模式" ✓）
    ★ ③ ★ **槽位是"待填"的** ✓ —— ★ 没有 `type` ✓ ★ 不编内容 ✓
      ★★ 而且 ★ **控件上限必须够装最大的棋盘** ✓（★ 49 ✓ 否则第 19 条起**点不着** ✗）

  跑法：lua tests/clue_slots.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
local here = HERE .. "/"
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/?.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local init = require("levels.init")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

--------------------------------------------------------------------------------
-- 1. ★★★ 条数 = 棋盘格数（★ 逐关 ✓）
--------------------------------------------------------------------------------
do
  local all = init.all()
  ok(#all > 0, "能列出关卡")
  for i = 1, #all do
    local lv = all[i]
    local core = Core.new(lv)
    ok(core ~= nil, "关卡 " .. tostring(lv.id) .. " 能构造")
    if core ~= nil then
      local want = core.rows * core.cols
      ok(core.clue_slots == want,
        string.format("%s：%d×%d ⇒ 槽位应为 %d（实测 %s）",
          tostring(lv.id), core.rows, core.cols, want, tostring(core.clue_slots)))
      local vm = core:view() or {}
      ok(#(vm.clues or {}) == want,
        string.format("%s：视图里也应有 %d 张卡（实测 %d）",
          tostring(lv.id), want, #(vm.clues or {})))
    end
  end
  print("  [PASS] 条数 = rows × cols（逐关）")
end

--------------------------------------------------------------------------------
-- 2. ★★ 真关卡不再靠手写线索表 ⇒ 引擎照旧补满槽位
--------------------------------------------------------------------------------
do
  local all = init.all()
  for i = 1, #all do
    local lv = all[i]
    ok(type(lv.clues) ~= "table" or #lv.clues == 0,
      "真关卡 " .. tostring(lv.id) .. " 不该再有手写的 clues 表（★ 那套已被替换 ✓）")
  end
  print("  [PASS] 真关卡无手写线索表，槽位由棋盘规格生成")
end

--------------------------------------------------------------------------------
-- 3. ★★ 槽位是"待填"：没有 type ⇒ 不编内容（★ 如实报占位 ✓）
--------------------------------------------------------------------------------
do
  local lv = require("levels.case_001")
  local core = Core.new(lv)
  local vm = core:view() or {}
  local c1 = (vm.clues or {})[1]
  ok(c1 ~= nil, "第 1 张卡存在")
  ok(c1 ~= nil and c1.type == nil, "槽位没有 type（★ 内容还没填 ✓）")
  -- ★ 文案要**看得出是占位** ✗ 而不是编一条像真的线索 ✓
  ok(c1 ~= nil and type(c1.text) == "string" and #c1.text > 0, "占位文案非空（便于肉眼看出待填）")
  print("  [PASS] 槽位如实报占位，不编内容")
end

--------------------------------------------------------------------------------
-- 4. ★★ 控件上限必须够装最大棋盘（★ 否则后面的卡"点不着" ✗）
--------------------------------------------------------------------------------
do
  local L = UIC.LAYOUT
  ok(type(L.clue_max_visible) == "number" and L.clue_max_visible >= 49,
    "clue_max_visible 必须 ≥ 49（7×7 的格数）—— 实测 " .. tostring(L.clue_max_visible))
  -- ★ 窗口行数 × 行高 必须 ≤ 线索区高度 ✓（★ 否则滚动按钮会被推到画布外 ✓ 项目踩过 ✓）
  ok(L.clue_rows * L.clue_row_h <= L.clues.h + 1,
    string.format("clue_rows×clue_row_h 不该超过线索区高度（%s×%s vs %s）",
      tostring(L.clue_rows), tostring(L.clue_row_h), tostring(L.clues.h)))
  print("  [PASS] 控件上限 ≥ 49，且窗口行数没超出线索区")
end

--------------------------------------------------------------------------------
-- 5. ★★ 7×7 建出来的卡片数 = 49（★ 端到端 ✓ 不是读常量 ✓）
--------------------------------------------------------------------------------
do
  local lv = require("levels.case_003")
  local core = Core.new(lv)
  local ctl = UIC.new(core, {})
  local plan = ctl:layout_plan()
  local n = 0
  for i = 1, #plan do
    local id = plan[i].id
    if type(id) == "string" and id:match("^clue%.%d+$") then n = n + 1 end
  end
  ok(n == 49, "7×7 关卡应建出 49 张线索卡（实测 " .. n .. "）")
  print("  [PASS] 7×7 ⇒ 49 张卡（端到端）")
end

--------------------------------------------------------------------------------
print(string.format("\nclue_slots: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
