--[[----------------------------------------------------------------------------
  tests/clue_hint.lua —— 「选中线索卡 ⇒ 棋盘高亮这条线索允许出现的位置」

  规则来源（设计定稿，不是本测试发明的）：
    · murdoku-内容设计-两关布局图/线索卡-位置提示表.md §三 / §四
    · murdoku-内容设计-两关布局图/案件00{1,2}-线索卡高亮提示.png
    · 原型：Temp/qxmurdoku/design/clue_hint.lua（按线索类型算集合）

  本文件钉死五件事：
    ① 两关的线索表**按卡序**排列（卡 i ↔ 线索 i ↔ 第 i 枚棋子），类型顺序写进断言；
    ② 第一关 5 张卡的高亮格**逐格**等于设计表；
    ③ 第二关 a/b/c/e 四张卡逐格等于设计表；d、v 是人对人线索 ⇒ **一条格都不给**；
    ④ 高亮只落在**可站人的格**上（家具占的不可站格永不出现）；
    ⑤ 界面：`focused_clue` 有值时那些格下发 **半透明浅蓝**，取消选中后回到原色。

  跑法：lua tests/clue_hint.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path,
}, ";")

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local L1   = require("tests.old_case_001")   -- ★ 冻结夹具（不随已交付内容漂 ✓）
local L2   = require("tests.old_case_002")   -- ★ 冻结夹具

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL  " .. msg)
  end
end

-- 设计表里的写法 "(1,5) (2,5)" → 我们的规范串 "1,5 2,5"（按行、列升序）
local function design_list(s)
  local out = {}
  for r, c in tostring(s):gmatch("%((%d+)%s*,%s*(%d+)%)") do
    out[#out + 1] = tonumber(r) .. "," .. tonumber(c)
  end
  table.sort(out, function(a, b)
    local ar, ac = a:match("^(%d+),(%d+)$")
    local br, bc = b:match("^(%d+),(%d+)$")
    ar, ac, br, bc = tonumber(ar), tonumber(ac), tonumber(br), tonumber(bc)
    if ar ~= br then return ar < br end
    return ac < bc
  end)
  return table.concat(out, " ")
end

-- 引擎给回来的结果 → 同一种规范串
local function engine_list(hint)
  if hint == nil then return "<nil>" end
  local out = {}
  for _, p in ipairs(hint.cells or {}) do
    out[#out + 1] = p.r .. "," .. p.c
  end
  table.sort(out, function(a, b)
    local ar, ac = a:match("^(%d+),(%d+)$")
    local br, bc = b:match("^(%d+),(%d+)$")
    ar, ac, br, bc = tonumber(ar), tonumber(ac), tonumber(br), tonumber(bc)
    if ar ~= br then return ar < br end
    return ac < bc
  end)
  return table.concat(out, " ")
end

local function new_core(lv)
  local core, errs = Core.new(lv)
  ok(core ~= nil, "关卡能构建：" .. tostring(lv and lv.id) .. " " .. table.concat(errs or {}, "/"))
  return core
end

-- ★ 功能没实现时也要能跑完（给出红色断言，而不是「attempt to call a nil value」）：
--   Red 必须是"目标行为缺失"，不是"测试自己崩了"。
local function clue_hint(core, i)
  if core == nil or core.clue_hint == nil then return nil end
  return core:clue_hint(i)
end
local function clue_hint_general(core, i)
  if core == nil or core.clue_hint_general == nil then return nil end
  return core:clue_hint_general(i)
end

--------------------------------------------------------------------------------
-- 1. 关卡数据：卡序 = 线索序（写死在断言里，防止有人把顺序改回去）
--------------------------------------------------------------------------------
do
  local core1 = new_core(L1)
  ok(#core1.clues == 5, "第一关线索 5 条（按卡序）")
  local want1 = { "in_col", "beside_object", "only_on_object", "on_object", "beside_object" }
  for i = 1, 5 do
    ok(core1.clues[i] and core1.clues[i].type == want1[i],
      "第一关卡 " .. i .. " 的类型 = " .. want1[i] .. "（实际 " ..
      tostring(core1.clues[i] and core1.clues[i].type) .. "）")
  end
  -- 第一关卡序（设计 §三.1）：卡1 A 说 v / 卡2 B 说 d / 卡3 C 说 a / 卡4 D 说 c / 卡5 V 说 b
  local want1who = { "V", "D", "A", "C", "B" }
  for i = 1, 5 do
    ok(core1.clues[i] and core1.clues[i].who == want1who[i],
      "第一关卡 " .. i .. " 说的是 " .. want1who[i] .. " 的位置（实际 " ..
      tostring(core1.clues[i] and core1.clues[i].who) .. "）")
  end
  ok(core1.room_count == 3, "第一关 3 个区域（实际 " .. tostring(core1.room_count) .. "）")

  local core2 = new_core(L2)
  ok(#core2.clues == 6, "第二关线索 6 条（六张卡）")
  local want2 = { "beside_object", "n_on_object", "beside_object", "above", "only_beside",
                  "alone_and_below_in_other_room" }
  for i = 1, 6 do
    ok(core2.clues[i] and core2.clues[i].type == want2[i],
      "第二关卡 " .. i .. " 的类型 = " .. want2[i] .. "（实际 " ..
      tostring(core2.clues[i] and core2.clues[i].type) .. "）")
  end
  -- 第二关定稿：四个区域、全场一扇门（R1↔R2），R3/R4 与谁都不相邻
  ok(core2.room_count == 4, "第二关 4 个区域（实际 " .. tostring(core2.room_count) .. "）")
  local adj = {}
  for room = 1, core2.room_count do
    local n = 0
    for _ in pairs(core2.adjacency[room] or {}) do n = n + 1 end
    adj[room] = n
  end
  -- ★ 2026-10-18：用户指定补了两扇门（`h,3,1` = R1↔R3；`v,4,3` = R3↔R4）
  --   ⇒ 相邻数从「1,1,0,0」变成「2,1,2,1」✓
  --   ★ 设计判据**没变**：受害者所在区域 R2 **依然只有 1 扇门**（仍只能与 R1 相邻 ✓）
  ok(adj[1] == 2 and adj[2] == 1 and adj[3] == 2 and adj[4] == 1,
    "第二关门相邻：R1↔{2,3} R2↔{1} R3↔{1,4} R4↔{3}（实际 " ..
    table.concat({ adj[1], adj[2], adj[3], adj[4] }, ",") .. "）")
  ok(adj[2] == 1, "★ 受害者区域 R2 仍然只有 1 扇门（唯一出入口 —— 设计判据保住了）")
  ok(#(core2.general_clues or {}) == 1, "第二关有 1 条通用线索（不是任何人的卡）")
  ok(core2.general_clues and core2.general_clues[1]
     and core2.general_clues[1].type == "nobody_on_object",
    "通用线索类型 = nobody_on_object")
end

--------------------------------------------------------------------------------
-- 2. 第一关：五张卡的高亮格逐格等于设计表
--------------------------------------------------------------------------------
do
  local core = new_core(L1)
  local design = {
    [1] = "(1,5) (2,5) (3,5) (4,5) (5,5)",                    -- 收藏家 在第 5 列
    [2] = "(1,3) (2,2) (4,1) (4,3) (5,2) (5,4)",              -- 旧识古董商 在 植物 旁边
    [3] = "(2,4) (2,5) (3,1) (3,2)",                          -- 只有 值班保安 站在 地毯 上
    [4] = "(4,2) (5,4)",                                      -- 夜班清洁工 站在 椅子 上
    [5] = "(2,2) (3,1)",                                      -- 前台姑娘 在 桌子 旁边
  }
  for i = 1, 5 do
    local hint = clue_hint(core, i)
    ok(hint ~= nil, "第一关卡 " .. i .. " 有位置提示（不是 nil）")
    ok(engine_list(hint) == design_list(design[i]),
      "第一关卡 " .. i .. " 高亮格 = " .. design_list(design[i])
      .. "（实际 " .. engine_list(hint) .. "）")
    ok(hint ~= nil and (hint.rule == nil or type(hint.rule) == "string"),
      "第一关卡 " .. i .. " 带规则说明（给界面/日志用）")
  end
end

--------------------------------------------------------------------------------
-- 3. 第二关：a/b/c/e 逐格等于设计表；d、v 不给位置提示
--------------------------------------------------------------------------------
do
  local core = new_core(L2)
  local design = {
    [1] = "(1,1) (1,4) (2,2) (2,3) (5,5) (6,6)",     -- a：画廊助理 在 桌子 旁边
    [2] = "(1,1) (2,4)",                              -- b：有两人坐在椅子上
    [3] = "(5,2) (6,1) (6,3)",                        -- c：夜班门卫 在 书架 旁边
    [5] = "(2,2) (3,1) (3,3) (4,4) (5,5) (6,3)",     -- e：只有 随行记者 在 植物 旁边
  }
  for i = 1, 6 do
    local hint = clue_hint(core, i)
    if design[i] ~= nil then
      ok(engine_list(hint) == design_list(design[i]),
        "第二关卡 " .. i .. " 高亮格 = " .. design_list(design[i])
        .. "（实际 " .. engine_list(hint) .. "）")
    else
      -- ★ 双向断言：既不给格，也不是"给了一张空表"以外的形状
      ok(hint == nil, "第二关卡 " .. i .. " 是人对人线索 ⇒ 不做位置提示（实际 " ..
        engine_list(hint) .. "）")
    end
  end
  -- 通用线索也要能算（它不上卡，但设计表里有 5 格）
  local g = clue_hint_general(core, 1)
  ok(engine_list(g) == design_list("(1,4) (3,3) (3,4) (5,1) (6,1)"),
    "第二关通用线索（地毯上没有人）高亮 = 地毯自身 5 格（实际 " .. engine_list(g) .. "）")

  -- ★ 通用线索**没有卡可以看** ⇒ 类型拼错必须在校验期就报出来（否则永远静默失效）
  ok(Core.validate_level(L2) == true, "第二关（含通用线索）能通过格式校验")
  local broken = {}
  for k, v in pairs(L2) do broken[k] = v end
  broken.general_clues = { { type = "nobody_on_object_TYPO", object = "地毯" } }
  broken.id = "case_002_typo"
  local okv, errs = Core.validate_level(broken)
  ok(okv == false, "通用线索类型拼错 ⇒ 格式校验必须失败")
  local hit = false
  for i = 1, #(errs or {}) do
    if tostring(errs[i]):find("通用线索", 1, true) then hit = true end
  end
  ok(hit, "错误信息里点明是**通用线索**（实际：" .. table.concat(errs or {}, " / ") .. "）")
end

--------------------------------------------------------------------------------
-- 4. 只高亮「可站人的格」：家具占住的不可站格一个都不能出现
--------------------------------------------------------------------------------
do
  local function check_level(lv, label)
    local core = new_core(lv)
    local all = {}
    local function add(h)
      for _, p in ipairs((h and h.cells) or {}) do
        all[p.r .. "," .. p.c] = true
      end
    end
    for i = 1, #core.clues do add(clue_hint(core, i)) end
    for i = 1, #(core.general_clues or {}) do add(clue_hint_general(core, i)) end

    local bad = {}
    for k in pairs(all) do
      local r, c = k:match("^(%d+),(%d+)$")
      if core:is_blocked(tonumber(r), tonumber(c)) then bad[#bad + 1] = k end
    end
    ok(#bad == 0, label .. "：高亮格里没有不可站人格（越界 " .. #bad .. " 个）")

    -- 反向：非可站人的家具格**不该**出现（桌子/植物/书架/雕塑）
    local blocked_in_objects = 0
    for name, cells in pairs(lv.objects or {}) do
      if cells.occupiable == false then
        local list = cells.cells or {}
        local single = (list.r ~= nil) and { list } or list
        for _, p in ipairs(single) do
          blocked_in_objects = blocked_in_objects + 1
          ok(not all[p.r .. "," .. p.c],
            label .. "：不可站人的 " .. tostring(name) .. "(" .. p.r .. "," .. p.c ..
            ") 不该被高亮")
        end
      end
    end
    ok(blocked_in_objects > 0, label .. " 至少有一件不可站人的家具（反向断言才有意义）")
  end
  check_level(L1, "第一关")
  check_level(L2, "第二关")
end

--------------------------------------------------------------------------------
-- 5. 界面：focused_clue ⇒ 那些格把 `hint` 打开；取消选中 ⇒ 全关
--
--   ★★ 2026-10-17 口径变了 ✗✓：**颜色归编辑器** ——
--     模板 `cell` → `content` → `hint`（135×135，颜色 0x7F0063D5，用户已调好）
--     ⇒ 脚本只发 `hint = true/false`，不再染 `face`（染它会把头像/房间色一起染蓝 ✗）
--     ⇒ 本段因此断言**布尔**，并**反向**断言 `tint` 与提示无关（免得有人又把它接回颜色）
--------------------------------------------------------------------------------
do
  local core = new_core(L1)
  local ctl = UIC.new(core, { skip_intro = true })

  local function cell_field(ctl_, r, cc, key)
    local nodes = ctl_:build_layout()
    local want_id = string.format("cell.%d.%d", r, cc)
    for i = 1, #(nodes or {}) do
      local n = nodes[i]
      if n ~= nil and n.id == want_id then return n[key], n end
    end
    return nil, nil
  end
  local function cell_hint(ctl_, r, cc) return (cell_field(ctl_, r, cc, "hint")) end

  local function count_hints(ctl_)
    local on, missing = 0, 0
    for r = 1, core.rows do
      for cc = 1, core.cols do
        local v = cell_hint(ctl_, r, cc)
        if v == nil then missing = missing + 1 elseif v == true then on = on + 1 end
      end
    end
    return on, missing
  end

  -- ① 每格都必须显式下发布尔（nil 会让"关掉"变成没有下发 ⇒ 上一批残留）
  local on0, missing0 = count_hints(ctl)
  ok(missing0 == 0, "每格都显式带 `hint`（缺失 " .. missing0 .. " 格）")
  ok(on0 == 0, "没选中时没有一格亮（实际 " .. on0 .. " 格）")

  -- ② 选中 V（第一关第 5 张卡的那位）⇒ focused_clue = 5 ⇒ 卡 5 的两格亮
  local base22 = cell_field(ctl, 2, 2, "tint")
  core:select_suspect("V")
  ctl:_sync_clue_focus()
  ok(ctl.focused_clue == 5, "选中 V ⇒ focused_clue = 5（实际 " .. tostring(ctl.focused_clue) .. "）")
  ok(cell_hint(ctl, 2, 2) == true, "卡 5 的 (2,2) 打开 `hint`")
  ok(cell_hint(ctl, 3, 1) == true, "卡 5 的 (3,1) 打开 `hint`")
  ok(cell_hint(ctl, 1, 5) == false, "非本卡的 (1,5) 保持关闭")
  local on1 = count_hints(ctl)
  ok(on1 == 2, "选中 V 时**正好 2 格**亮（实际 " .. on1 .. "）")
  -- ★ 反向：提示不再靠 `tint` ⇒ (2,2) 的颜色必须还是原来的房间色
  ok(cell_field(ctl, 2, 2, "tint") == base22,
    "提示格的 `tint` 没被改（颜色只归编辑器 ✓）")

  -- ③ 换 D（卡 4：两把椅子）⇒ 上一批灭、这一批亮
  core:select_suspect("D")
  ctl:_sync_clue_focus()
  ok(ctl.focused_clue == 4, "选中 D ⇒ focused_clue = 4（实际 " .. tostring(ctl.focused_clue) .. "）")
  ok(cell_hint(ctl, 4, 2) == true and cell_hint(ctl, 5, 4) == true, "卡 4 的两把椅子都亮")
  ok(cell_hint(ctl, 2, 2) == false, "换卡之后上一张卡的格**灭掉**（不会残留）")
  local on2 = count_hints(ctl)
  ok(on2 == 2, "选中 D 时正好 2 格亮（实际 " .. on2 .. "）")

  -- ④ 取消选中 ⇒ 全灭
  core:select_suspect("D")
  ctl:_sync_clue_focus()
  ok(ctl.focused_clue == nil, "取消选中 ⇒ focused_clue = nil")
  local on3 = count_hints(ctl)
  ok(on3 == 0, "取消选中后一格都不亮（实际 " .. on3 .. "）")

  -- ⑤ 第二关：人对人线索（卡 4 d / 卡 6 v）选中时**一格都不该亮**
  local core2 = new_core(L2)
  local ctl2 = UIC.new(core2, { skip_intro = true })
  -- 第二关棋子序：A B C D E V ⇒ 选中 D = 第 4 张卡（d = above，纯人对人）
  core2:select_suspect("D")
  ctl2:_sync_clue_focus()
  ok(ctl2.focused_clue == 4, "第二关选中 D ⇒ focused_clue = 4")
  local on4 = 0
  for r = 1, core2.rows do
    for cc = 1, core2.cols do
      local nodes = ctl2:build_layout()
      local want_id = string.format("cell.%d.%d", r, cc)
      for i = 1, #(nodes or {}) do
        if nodes[i] ~= nil and nodes[i].id == want_id and nodes[i].hint == true then on4 = on4 + 1 end
      end
    end
  end
  ok(on4 == 0, "人对人线索（卡 4 d）选中时一格都不亮（实际 " .. on4 .. "）")
end

--------------------------------------------------------------------------------
print(string.format("\n结果：%d 通过 / %d 失败", passed, failed))
if failed > 0 then os.exit(1) end
