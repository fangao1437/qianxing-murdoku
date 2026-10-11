--------------------------------------------------------------------------------
-- level3_letter_map：★★ 第三关（7 行 7 棋子）的"行号 → 字母"必须一一对上
--
--   ★★★ 为什么要这一套 ✗（★ 用户 2026-10-11 报"第三关 DEF 的 note 是 AAF" ✓）：
--     ★ 前几套（`row_letter_map` / `board_wiring_e2e`）用的是 **5 关的夹具** ✓
--       ★ 而用户报的是**第三关** ✗ —— ★ 7 行 × 7 棋子 ✓
--     ★★ 而"行号 → 字母"这件事，只有行数与棋子数都到 7 时才暴露边界 ✓
--       （★ 索引越界 / 第 7 行读不到 / 7 个里只填了前 5 个 ✓）
--   ★ 判据 ✓：★ **给每一行配一个各不相同的字母**（`L1..L7` ✓）
--     ⇒ ★ 只要有一处取错行 ⇒ ★ **立刻对不上** ✓✓
--   ★★ 而且故意让**字母 ≠ 棋子 id** ✗（★ `L1` 而不是 `A` ✓）
--     ⇒ ★ 若实现退化成"回退棋子 id" ⇒ ★ 这一套会红 ✓（★ 不会假绿 ✓）
--
--   ⚠️ ★ 本套**不测**"放棋子"那条路 ✗ —— ★ 放人只出头像、不下发字母 ✓
--     （★ 用户 2026-10-11 明确要求 ✓ 见 `board_wiring_e2e` 判据① ✓）
--     ★ 所以这里走的是**打标记**那条 ✓（★ 字母只在这条路上出现 ✓）
--------------------------------------------------------------------------------
package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;" .. package.path

local UIC  = require("ui_controller")
local Core = require("murdoku_core")
local lv   = require("levels.case_003")

package.loaded["levels.init"] = { index_of = function(id) if id == lv.id then return 3 end return nil end }
-- ★ 关卡解析器那条路（`_level_ordinal`）在真机上是 `levels.init` 给的 ✓
pcall(function() package.loaded["levels.init"].index_of = function(id) return (id == lv.id) and 3 or nil end end)

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

-- ── 假控件（★ 保真：`GetChild` 只找直接子级 ✓ `FindChild` 认全名与末段名 ✓）────
local function ctrl(name)
  local c = { name = name, __kids = {} }
  c.GetChildren = function() return c.__kids end
  c.GetChild = function(_, k) for _, x in ipairs(c.__kids) do if x.name == k then return x end end return nil end
  c.FindChild = function(_, p)
    local tail = tostring(p):match("([^%.]+)$") or tostring(p)
    for _, x in ipairs(c.__kids) do if x.name == p or x.name == tail then return x end end
    return nil
  end
  c.SetVisible = function() end
  c.SetActive = function() end
  return c
end
local function attach(p, c) p.__kids[#p.__kids + 1] = c return c end

-- ── ★★ 行夹具：★ 每一行的 `letter` 由 `mk_letter(pos)` 决定 ✓ ──────────────
--   ★ 形状照**真存档** ✓：`row.<关>.<行>` 下四个槽位 ✓
--     槽位外层叫 `letter.3.4` ✓ 里层那个才带文字 ✓（★ 与真机同形 ✓）
local function build_rows(nrow, mk_letter)
  local as = ctrl("assets")
  for pos = 1, nrow do
    local row = ctrl("row.3." .. pos)
    for _, nm in ipairs({ "who", "what", "letter" }) do
      local holder = ctrl(nm .. ".3." .. pos)
      local inner = ctrl(nm)
      inner.text = (nm == "letter") and mk_letter(pos) or ("w" .. pos)
      attach(holder, inner); attach(row, holder)
    end
    local fh = ctrl("face.3." .. pos)
    local fi = ctrl("face"); fi.imageId = 500 + pos
    attach(fh, fi); attach(row, fh)
    attach(as, row)
  end
  local root = ctrl("root"); attach(root, as)
  _G.game = { GetClientUIRoots = function() return { root } end }
  return root
end

local NROW = 7
local function L(pos) return "L" .. pos end

local function boot()
  UIC.Controller._row_letter, UIC.Controller._row_face, UIC.Controller._row_text = nil, nil, nil
  UIC.Controller._piece_core, UIC.Controller._piece_id_cache = nil, nil
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  c._grid_base = 0                    -- ★ 引擎交来 0 起 ⇒ 基准就是第一项那个 index ✓
  c._grid_in_refresh = true
  for pos = 1, NROW do
    local it = ctrl("item")
    for _, nm in ipairs({ "who", "what", "letter" }) do attach(it, ctrl("clue." .. pos .. "." .. nm)) end
    attach(it, ctrl("clue." .. pos .. ".gray"))
    it.__index = pos - 1
    c:_fill_grid_item(nil, nil, it, pos - 1)
  end
  c._grid_in_refresh = false
  return core, c
end

local function cell_notes(c, r, cc)
  local want = string.format("cell.%d.%d", r, cc)
  for _, n in ipairs(c:build_layout() or {}) do
    if n ~= nil and n.id == want then return n.notes end
  end
  return "<没有这一格>"
end

--------------------------------------------------------------------------------
print("\n== 1. ★ 7 行都读到了（★ 不是只读前 5 行）==")
--------------------------------------------------------------------------------
do
  build_rows(NROW, L)
  local _, c = boot()
  local RL = UIC.Controller._row_letter or {}
  local n = 0
  for _ in pairs(RL) do n = n + 1 end
  ok(n == NROW, string.format("★ `_row_letter` 落了 %d 行（★ 期望 %d ✓ 第 7 行也要在 ✓）", n, NROW))
  local allok = true
  for pos = 1, NROW do
    if tostring(RL[pos]) ~= L(pos) then allok = false end
  end
  ok(allok, "★ 每一行落的都是【那一行】的字母（★ 7/7 ✓）")
end

--------------------------------------------------------------------------------
print("\n== 2. ★★ 棋子 → 行号 → 字母（★ 这就是用户报的那件事）==")
--------------------------------------------------------------------------------
do
  build_rows(NROW, L)
  local core, c = boot()
  local bad = {}
  for k = 1, NROW do
    local pid = UIC.Controller._piece_at_row(core, k)
    core:select_suspect(pid)
    core:tap_cell(k, k)                 -- ★ 打标记（★ 字母只在这条路上出现 ✓）
    local got = joined(cell_notes(c, k, k))
    if got ~= L(k) then
      bad[#bad + 1] = string.format("第%d个棋子(%s)@(%d,%d) 得到 %s 想要 %s",
        k, tostring(pid), k, k, got, L(k))
    end
  end
  ok(#bad == 0, "★ 第三关 7 个棋子：标记都显示【自己那一行】的字母 ✓"
    .. (#bad > 0 and ("　✗ " .. table.concat(bad, " ｜ ")) or ""))
  local t = {}
  for k = 1, NROW do
    t[#t + 1] = tostring(UIC.Controller._piece_at_row(core, k)) .. "→" .. L(k)
  end
  print("      实测：" .. table.concat(t, " "))
end

--------------------------------------------------------------------------------
print("\n== 3. ★★★ 行与棋子【故意错开】⇒ 必须跟着【行】走（★ 用户定的键 ✓）==")
--
--   ★ 为什么必须测 ✗：★ 若实现"偷偷按棋子 id 去猜行"✗ ⇒ 这时会给出**另一个答案** ✓
--     ★ 而两个答案在"顺序一致"时**长得一模一样** ✗ ⇒ ★ 只在错开时才分得出来 ✓✓
--------------------------------------------------------------------------------
do
  build_rows(4, function(pos) return "Z" .. pos end)
  local core, c = boot()
  core:select_suspect(UIC.Controller._piece_at_row(core, 1))
  core:tap_cell(1, 1)
  ok(joined(cell_notes(c, 1, 1)) == "Z1",
    "★ 第 1 个棋子打标记 ⇒ 显示第 1 行的 `Z1`（实测 " .. joined(cell_notes(c, 1, 1)) .. "）")
  core:select_suspect(UIC.Controller._piece_at_row(core, 3))
  core:tap_cell(3, 3)
  ok(joined(cell_notes(c, 3, 3)) == "Z3",
    "★ 第 3 个棋子打标记 ⇒ 显示第 3 行的 `Z3`（实测 " .. joined(cell_notes(c, 3, 3)) .. "）")
  -- ★ 第 5 行**没配**字母 ⇒ 落回棋子 id ✓（★ 不许空白 ✓）
  core:select_suspect(UIC.Controller._piece_at_row(core, 5))
  core:tap_cell(5, 5)
  local got5 = joined(cell_notes(c, 5, 5))
  local pid5 = tostring(UIC.Controller._piece_at_row(core, 5))
  ok(got5 == pid5,
    "★ 第 5 行没配 `letter` ⇒ 落回棋子 id `" .. pid5 .. "`（★ 不许空白 ✗ 实测 " .. got5 .. "）")
end

--------------------------------------------------------------------------------
print("\n== 4. ★★ 换关要清干净（★ 别把第三关的字母带到别的关）==")
--------------------------------------------------------------------------------
do
  build_rows(NROW, L)
  local _, c = boot()
  ok(next(UIC.Controller._row_letter or {}) ~= nil, "前提：第三关的表已经建好")
  c._row_map_sig = nil
  c:_reset_row_maps_if_level_changed()
  ok(next(UIC.Controller._row_letter or {}) == nil, "★ 换关 ⇒ `_row_letter` 清空")
end

print(string.format("\nlevel3_letter_map: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
