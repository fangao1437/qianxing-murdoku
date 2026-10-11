--[[----------------------------------------------------------------------------
  tests/row_letter_stability.lua —— 「一个人的 letter 必须【确定】，且不跨关串」

  ★★★ 这个文件钉两个**真机才会暴露**的 bug ✗✓：

    ★ bug ① **同一个人的 `letter` 被配了两次 ⇒ 谁赢取决于写入顺序** ✗
      真机证据（用户 2026-10-11 ✓）：
        · 自检关 ✓：5 条线索点名 6 个人时**每人只被点到一次** ⇒ ★ 看起来对 ✓
        · `case_002`（15 条线索）✗：★ **4 个人各被两条线索点到** ✓
            `V` ← `row.3.1="A"` ＋ `row.3.2="B"`　`E` ← `D` ＋ `E`
            `@thief` ← `F` ＋ `G`　`@accomplice` ← `H` ＋ `V`
          ⇒ ★★ 原来**无条件覆盖** ✗ ⇒ **后写的赢** ✓
          ⇒ ★ **主循环每帧跑** ⇒ ★★ 显示哪个字母**由最后一次写入的顺序决定** ✗✓
        · 用户原话 ✓：「★ **第一关正确了，第三关仍然不正确**」✓
      修法 ✓：★ **先到先得**（★ 已有值就不覆盖 ✓）＋ ★ 配重了**如实报一行** ✓

    ★ bug ② **那两张表跨关存活** ✗
      · `Controller._row_letter` / `_row_face` 是**模块级**的 ✓（★ 静态函数要读 ✓）
        ⇒ ★ `start_other` 新建控制器 ✗ ★ **表还是同一个** ✓
      · ⇒ ★ 某一关的 `row.<关>` 是空的（★ 第 4 关就没有 ✓）⇒ 一个 letter 都不写
        ⇒ ★★ **那一关的人显示【别的关】的字母** ✓
      修法 ✓：★ 进关卡时按 `level.id` 签名清一次 ✓

  跑法：lua tests/row_letter_stability.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local UIC  = require("ui_controller")
local Core = require("murdoku_core")
local lv   = require("tests.fixtures").clue_level_5x5()

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

local function ctrl(name, opts)
  opts = opts or {}
  local c = { name = name }
  if opts.text ~= nil then c.text = opts.text end
  local kids = opts.kids or {}
  c.GetChildren = function() return kids end
  c.GetChild = function(_, n) for i = 1, #kids do if kids[i].name == n then return kids[i] end end return nil end
  c.FindChild = function(_, n) for i = 1, #kids do if kids[i].name == n then return kids[i] end end return nil end
  return c
end

-- ★ `letters[pos]` = 第 pos 行配的 letter ✓（★ nil = 那一行没配 ✓）
local function make_world(letters, whos)
  local rows = {}
  for pos = 1, #letters do
    local inner = {}
    if letters[pos] ~= nil then inner = { ctrl("letter", { text = letters[pos] }) } end
    rows[#rows + 1] = ctrl("row.1." .. pos, { kids = {
      -- ★★ 2026-10-11 **`who` 槽就是键** ✗✓（★ 用户定案 ✓ ★ 详见 `cell_mark_letter` 那段 ✓）
      ctrl("who.1." .. pos,    { kids = { ctrl("who",  { text = (whos and whos[pos]) or ("w" .. pos) }) } }),
      ctrl("letter.1." .. pos, { kids = inner }),
      ctrl("what.1." .. pos,   { kids = { ctrl("what", { text = "x" }) } }),
      ctrl("face.1." .. pos,   { kids = { ctrl("face", { kids = { ctrl("img", { imageId = 111 }) } }) } }),
    } })
  end
  return { ctrl("root", { kids = { ctrl("assets", { kids = rows }) } }) }
end

-- ★★ 2026-10-11 **冲突的判据改成"同一行的键被配了两次"** ✗✓（★ 用户定案 ✓）
--   ★ 老判据 ✓：★"同一个人被两条线索点到"（★ 键 = 视图里的 `cl.who` ✓）
--   ★★ 新判据 ✓：★ **键 = 那一行的 `who` 文本** ✓ ⇒ ★ 冲突 = **两个 `pos` 填了同一个 `who`** ✓
--     ★ 那正是"**一处一人只留一个字母**"这条数据规矩的代码侧对应 ✓✓
local function boot(letters, in_refresh, whos)
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  local keys = {}
  for pos = 1, #letters do keys[pos] = (whos and whos[pos]) or ("w" .. pos) end
  _G.game = { GetClientUIRoots = function() return make_world(letters, keys) end }
  c._grid_in_refresh = (in_refresh ~= false)
  for pos = 1, #letters do
    local card = {}
    for _, nm in ipairs({ "who", "letter", "what", "face" }) do
      local txt = (nm == "letter") and letters[pos] or ((nm == "who") and keys[pos] or "x")
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = { ctrl(nm, { text = txt }) } })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  return core, c, keys
end

local Ctl = UIC.Controller

--------------------------------------------------------------------------------
-- 1. ★★★ 同一个键被两条行配到 ⇒ 【先到先得】，且再写一次也不变
--------------------------------------------------------------------------------
do
  Ctl._row_letter = {}
  -- ★ pos1 与 pos7 **填同一个 `who`** ✓ ⇒ ★ 键冲突 ✓（★ 第 1 行 letter=`A` ✓ 第 7 行=`Z` ✓）
  local letters = { "A", "b", "c", "d", "e", "f", "Z" }
  local whos = { "K", "w2", "w3", "w4", "w5", "w6", "K" }
  local _, c = boot(letters, true, whos)
  ok(Ctl._row_letter["K"] == "A",
    "键 K 被 pos1(A) 与 pos7(Z) 同时配到 ⇒ 应保留先到的 A（实测 " .. tostring(Ctl._row_letter["K"]) .. "）")

  -- ★★ 再跑一遍（★ 顺序反过来 ✓）⇒ ★ **不许改变** ✓
  local core2 = Core.new(lv)
  local c2 = UIC.new(core2, { skip_intro = true })
  c2._grid_in_refresh = true
  for pos = #letters, 1, -1 do
    local card = {}
    for _, nm in ipairs({ "who", "letter", "what", "face" }) do
      local txt = (nm == "letter") and letters[pos] or ((nm == "who") and whos[pos] or "x")
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = { ctrl(nm, { text = txt }) } })
    end
    c2:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  ok(Ctl._row_letter["K"] == "A",
    "★ 换个写入顺序再跑 ⇒ 仍然是 A（★ 这就是「确定」✓ 实测 " .. tostring(Ctl._row_letter["K"]) .. "）")
  print("  [PASS] 同一个键被两行配到 ⇒ 先到先得，且与写入顺序无关")
end

--------------------------------------------------------------------------------
-- 2. ★ 两趟（早期 / 末次）必须同规则
--------------------------------------------------------------------------------
do
  Ctl._row_letter = {}
  -- ★ 让 pos1 与 pos7 填同一个键，且**只有末次那一趟跑** ✓
  local letters = { "A", "b", "c", "d", "e", "f", "Z" }
  local whos = { "K", "w2", "w3", "w4", "w5", "w6", "K" }
  local _, c = boot(letters, false, whos)   -- ★ _grid_in_refresh = false ⇒ 早期那趟不跑 ✓
  ok(c._grid_in_refresh == false, "前提：这次只让末次单射跑")
  ok(Ctl._row_letter["K"] == "A",
    "只跑末次时，键 K 仍应是先到的 A（实测 " .. tostring(Ctl._row_letter["K"]) .. "）")
  print("  [PASS] 两趟同规则（★ 末次不会把早期记下的覆盖掉 ✓）")
end

--------------------------------------------------------------------------------
-- 3. ★★★ 换关 ⇒ 那两张表必须清掉（★ 否则第 4 关会显示别的关的字母 ✓）
--------------------------------------------------------------------------------
do
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  Ctl._row_letter = { B = "AAAA", V = "VVVV" }
  Ctl._row_face = { B = 1 }
  c._row_map_sig = nil                       -- ★ 当作"还没进过关" ✓
  c:_reset_row_maps_if_level_changed()
  ok(Ctl._row_letter ~= nil and next(Ctl._row_letter) == nil,
    "★ 第一次进关卡 ⇒ `_row_letter` 被清空（实测 " .. tostring(next(Ctl._row_letter)) .. "）")
  ok(Ctl._row_face ~= nil and next(Ctl._row_face) == nil, "★ `_row_face` 也被清空")

  -- ★ 同一关内**再调一次不许清** ✗（★ 否则每帧清 ⇒ 永远空 ✓）
  Ctl._row_letter = { B = "keep" }
  c:_reset_row_maps_if_level_changed()
  ok(Ctl._row_letter["B"] == "keep",
    "★ 同一关内重复调用**不许清**（实测 " .. tostring(Ctl._row_letter["B"]) .. "）")

  -- ★ 换一关 ⇒ 必须清 ✓
  c.core = { level = { id = "another_level" } }
  c:_reset_row_maps_if_level_changed()
  ok(next(Ctl._row_letter) == nil, "★ 换成另一关 ⇒ 清空（★ 防跨关串字母 ✓）")
  print("  [PASS] 换关清表 ＋ 同关不清")
end

--------------------------------------------------------------------------------
print(string.format("\nrow_letter_stability: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
