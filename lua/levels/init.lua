--[[----------------------------------------------------------------------------
  levels/init.lua —— 关卡注册表

  加关卡只要两步：
    1. 复制 levels/template.lua 改成 levels/<你的id>.lua
    2. 在下面的 LIST 里加一行

  关卡顺序就是 LIST 的顺序，Murdoku 的“下一关”按它走。

  ⚠️ 加载失败不会被静默吞掉：失败信息收集在 M.load_errors() 里，
     tools/validate_levels.lua 会把它们当作错误报出来。
----------------------------------------------------------------------------]]--

local RoomMap = require("room_map")

local M = {}

-- 按顺序登记你的关卡；游戏里默认从第一个开始
--
-- ★★★★★★★★ 2026-10-18 **这个 LIST 的顺序【就是】编辑器 `assets/row.<关>.<行>` 的 `<关>` 号** ✗✓✓
--
--   链路：`Controller:_level_ordinal()` → `levels.init.M.index_of(id)` → **本 LIST 的下标** ✓
--   ⇒ 所以「第几关」不是猜的，也不是存档里另存的，**只由下面这几行的先后决定** ✓
--
--   当前的对应关系（★ 改这个 LIST 就等于改 row 编号，必须同步改编辑器里的 row.* ✗）：
--     LIST[1] demo_selftest  → 编辑器的 row.1.1 … row.1.5   （框架自检关，5 枚棋子）
--     LIST[2] case_001       → 编辑器的 row.2.1 … row.2.5   （5 枚棋子）
--     LIST[3] case_002       → 编辑器的 row.3.1 … row.3.6   （6 枚棋子）
--     LIST[4] case_003       → 编辑器的 row.4.*             （本阶段未配内容）
--   ⇒ 通用线索那块也是同一个口径：`row.<关>.clue`
--     （★ 只有"有关卡声明了 general_clues"的那一关才需要它 —— 目前是 case_002 ⇒
--       应是 **row.3.clue**，不是 row.2.clue ✗ 那一格属于 case_001，而 case_001 没有通用线索）
local LIST = {
  "levels.demo_selftest",     -- 第 1 关：框架自检样例（row.1.*）
  "levels.case_001",          -- 第 2 关：案件 001 · 夜盗独行（5×5，k=1，无同伙；row.2.*）
  "levels.case_002",          -- 第 3 关：案件 002 · 双影（6×6，无同伙 ＋ 1 条通用线索；row.3.*）
  "levels.case_003",          -- 第 4 关：案件 003 · 第三方（未配 row 内容）
}

M._errors = {}

local function note_error(module_name, err)
  M._errors[#M._errors + 1] = { module = module_name, error = tostring(err) }
end

function M.all()
  M._errors = {}
  local out = {}
  for i = 1, #LIST do
    local ok, lv = pcall(require, LIST[i])
    if ok and type(lv) == "table" then
      out[#out + 1] = lv
    else
      note_error(LIST[i], lv)
    end
  end
  return out
end

-- 上一次 all() 期间失败的关卡模块（{ module =, error = }）
function M.load_errors() return M._errors end

function M.get(level_id)
  for _, lv in ipairs(M.all()) do
    if lv.id == level_id then return lv end
  end
  -- 直接按文件名兜底
  for i = 1, #LIST do
    if LIST[i] == level_id or LIST[i]:match("%.([^%.]+)$") == level_id then
      local ok, lv = pcall(require, LIST[i])
      if ok and type(lv) == "table" then return lv end
    end
  end
  return nil
end

function M.current_id()
  local lv = M.all()[1]
  return lv and lv.id or nil
end

function M.next(level_id)
  local list = M.all()
  for i = 1, #list do
    if list[i].id == level_id then
      local nxt = list[i + 1]
      return nxt and nxt.id or nil
    end
  end
  return nil
end

function M.index_of(level_id)
  local list = M.all()
  for i = 1, #list do
    if list[i].id == level_id then return i end
  end
  return nil
end

-- ★★★ 2026-09-30：**界面层要用的关卡摘要** —— 只有这一处定义。
--
--   为什么要收拢：`main.lua`（真机）和 `tools/dump_layout.lua`（生成模拟器的布局计划）
--   **各自造了一份清单**，而且都只复制 `id/name/difficulty`。于是选关卡片要显示
--   「NxN　M名嫌疑人+1名受害人」（参考《派蒙的执律庭实习》）时**拿不到数据**，
--   界面上只剩关名；更糟的是两边各写一份 ⇒ **必然漂移**（本项目已因此踩过多次）。
--   ⇒ 统一放这里，两边都调它。
--
--   只带"界面真要用的"：卡片要 `size`/`suspects`，缩略图要 `rooms`/`objects`。
--   界面层不该知道规则细节（`rules`/`clues`/`solution` 一律不给）。
function M.ui_list()
  local out = {}
  local list = M.all()
  for i = 1, #list do
    local lv = list[i]
    out[i] = {
      id = lv.id, name = lv.name, difficulty = lv.difficulty,
      size = lv.size, suspects = lv.suspects, victim = lv.victim,
      rooms = lv.rooms, objects = lv.objects,
      -- ★ 缩略图要的**房间外框**（`{ {r1,c1,r2,c2,cells}, ... }`）。
      --   算法来自 `lua/room_map.lua`（和游戏内房间判定**同一份实现**，不会漂移）。
      room_boxes = RoomMap.boxes(lv),
      -- 关卡里**可选**写的房间名（`room_names = { "餐厅", "厨房", ... }`）。
      --   没写就是 nil ⇒ 界面显示中性的「区域 N」（**不编名字**）。
      room_names = lv.room_names,
    }
  end
  return out
end

return M
