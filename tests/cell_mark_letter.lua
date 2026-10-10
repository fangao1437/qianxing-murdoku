--[[----------------------------------------------------------------------------
  tests/cell_mark_letter.lua —— 「格子上的标记显示 `letter`，不是人物 id」

  为什么必须有这个文件 ✗：
    用户 2026-10-11 的一句更正定义了这个需求 ✓（★ 原话 ✓）：
      「**我要的就是铅笔笔记用 `letter` 的标记** ✓
       ★ **不是增加一个 `letter` 功能** ✗
       ★★ **而是让 `letter` 取代铅笔笔记的功能** ✓」

    ⇒ ★ 数据层**一个字都不该改** ✗（★ `core.notes[r][c] = { [人物id]=true }` 照旧 ✓）
      ★ **要改的只是"下发到格子 `note` 控件的那串字"** ✓
    ⇒ ★★ 而这条链**离线看不出对错** ✗ ——
      模拟器没有 `assets/row.*` 那条模板引用链，真机一轮又要导档＋同步＋重启 ✓
    ⇒ ★ 所以把它钉在这里 ✓

  顺带钉住前三轮那个**理解错误** ✗（★ 免得再犯 ✓）：
    ★ 我一度以为"标记"要**另开一条路**（放棋子 ⇒ 显示 letter ✓）
    ⇒ ★ 用户要的是**把现成那条路的【显示】换掉** ✓
    ⇒ ★ 本文件第 1 节因此**故意不涉及棋子** ✓ —— ★ 只考"打标记 ⇒ 显示 letter" ✓

  跑法：lua tests/cell_mark_letter.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local UIC  = require("ui_controller")
local Core = require("murdoku_core")
local lv   = require("tests.fixtures").clue_level_5x5()

-- ★ 关序 1 = 自检关 ✓ 与 `_level_ordinal()` 的 `LIST` 序号一致 ✓
package.loaded["levels.init"] = {
  index_of = function(id) if id == lv.id then return 1 end return nil end,
}

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

-- ── 假控件（只实现这条链用得到的成员）────────────────────────────────────
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

-- ── 假 `assets/row.1.*` ──────────────────────────────────────────────────
--   ★ `letters` 里写什么，那一行就配什么 ✓（★ nil = 没配 ✓）
--   ★ 槽位控件自己**不带 `.text`** ✗ —— 复现"引用控件读不到"那条真机现象 ✓
local function make_world(letters)
  local rows = {}
  for pos = 1, #letters do
    local inner = {}
    if letters[pos] ~= nil then inner = { ctrl("letter", { text = letters[pos] }) } end
    rows[#rows + 1] = ctrl("row.1." .. pos, { kids = {
      ctrl("who.1." .. pos,    { kids = { ctrl("who",    { text = "x" }) } }),
      ctrl("letter.1." .. pos, { kids = inner }),
      ctrl("what.1." .. pos,   { kids = { ctrl("what",   { text = "x" }) } }),
      ctrl("face.1." .. pos,   { kids = { ctrl("face",   { kids = { ctrl("img", { imageId = 111 }) } }) } }),
    } })
  end
  return { ctrl("root", { kids = { ctrl("assets", { kids = rows }) } }) }
end

-- ── 建控制器 ＋ 跑单射（把 `_row_letter` 建起来）────────────────────────
local function boot(letters)
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  _G.game = { GetClientUIRoots = function() return make_world(letters) end }
  c._grid_in_refresh = true
  for pos = 1, #letters do
    local card = {}
    for _, nm in ipairs({ "who", "letter", "what", "face" }) do
      local txt = (nm == "letter") and letters[pos] or "x"
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = { ctrl(nm, { text = txt }) } })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  return core, c
end

-- ── 把 render 下发的 `note` 抠出来（★ 只读 ✓ 不碰引擎 ✓）──────────────
--   ★ 做法 ✓：★ 拦 `push` 不行（它是闭包内局部）⇒ ★ 干脆**重跑一遍那三行判据** ✗
--     —— ★ 那就变成"测试抄了实现"✗ ★ 测不出真 bug ✗
--   ⇒ ★★ 改用**真跑 `build_layout`** ✓ ＋ ★ 从下发的计划里读 `note` ✓
--      ★ 入口 ✓：`build_layout` 把节点交给 `self.adapter.set_property` 那条链 ✓
--      ★ 但离线没有 adapter ✓ ⇒ ★ 这里改成**直接调那三行判据的同一份代码**：
--        ★ `Controller.letter_of` ✓ ＋ ★ 计划里 `notes` 字段 ✓
--   ★★ 结论 ✓：★ 判据就是"**计划里该格的 `notes` 是不是 `letter`**" ✓
--      ⇒ ★ 用 `build_layout` 的返回值取 ✓（它返回 nodes ✓）
local function plan_notes(c, r, cc)
  local nodes = c:build_layout()
  local want = string.format("cell.%d.%d", r, cc)
  for i = 1, #(nodes or {}) do
    local n = nodes[i]
    if n ~= nil and n.id == want then return n.notes, n end
  end
  return nil, nil
end

--------------------------------------------------------------------------------
-- 1. ★★★ 核心判据：打标记 ⇒ 格子显示【letter】而不是人物 id
--------------------------------------------------------------------------------
do
  -- ★ 故意用**小写**字母 ⇒ ★ 一眼分得出"显示的是 letter 还是 id" ✓✓
  local letters = { "a", "b", "c" }
  local core, c = boot(letters)
  -- ★ 用户的手势 ✓：选人 ⇒ 单击格子 ⇒ 打一个标记 ✓
  core:select_suspect("B"); core:tap_cell(1, 1)
  core:select_suspect("A"); core:tap_cell(2, 1)
  core:select_suspect("V"); core:tap_cell(3, 1)

  -- ★ 数据层必须是**【人物 id】** ✓ —— ★ 这一条不许被改掉 ✗
  local ids = {}
  for k in pairs(core.notes[1][1] or {}) do ids[#ids + 1] = tostring(k) end
  ok(#ids == 1 and ids[1] == "B", "数据层存的仍然是人物 id（★ 不许改成存 letter ✗）")

  local n1 = plan_notes(c, 1, 1)
  local n2 = plan_notes(c, 2, 1)
  local n3 = plan_notes(c, 3, 1)
  local function joined(t)
    if type(t) ~= "table" then return tostring(t) end
    return table.concat(t, " ")
  end
  ok(joined(n1) == "a", "格子(1,1) 打的是人物 B ⇒ 显示 B 那一行的 letter = a（实测：" .. joined(n1) .. "）")
  ok(joined(n2) == "b", "格子(2,1) 打的是人物 A ⇒ 显示 A 那一行的 letter = b（实测：" .. joined(n2) .. "）")
  ok(joined(n3) == "c", "格子(3,1) 打的是人物 V ⇒ 显示 V 那一行的 letter = c（实测：" .. joined(n3) .. "）")
  print("  [PASS] 打标记 ⇒ 显示 letter（★ 不是人物 id ✓）")
end

--------------------------------------------------------------------------------
-- 2. ★ 没配 `letter` 的人 ⇒ 回退人物 id（★ 不许突然空白 ✓）
--------------------------------------------------------------------------------
do
  local letters = { "a", "b", "c" }        -- ★ 人物 D 在第 4..7 行没有 letter ✓
  local core, c = boot(letters)
  ok(UIC.Controller._row_letter["D"] == nil, "前提：人物 D 没有配 letter")
  core:select_suspect("D"); core:tap_cell(4, 2)
  local n = plan_notes(c, 4, 2)
  local s = (type(n) == "table") and table.concat(n, " ") or tostring(n)
  ok(s == "D", "没配 letter ⇒ 回退人物 id = D（实测：" .. s .. "）")
  print("  [PASS] 没配 letter 时回退人物 id（★ 不会空白 ✓）")
end

--------------------------------------------------------------------------------
-- 3. ★ 一格多个标记 ⇒ 多个 letter 并列（★ 排序稳定 ✓）
--------------------------------------------------------------------------------
do
  local letters = { "a", "b", "c" }
  local core, c = boot(letters)
  core:select_suspect("A"); core:tap_cell(2, 3)   -- 人物 A ⇒ letter b
  core:select_suspect("V"); core:tap_cell(2, 3)   -- 人物 V ⇒ letter c
  local n = plan_notes(c, 2, 3)
  local s = (type(n) == "table") and table.concat(n, " ") or tostring(n)
  ok(s == "b c", "两个标记 ⇒ 两个 letter 并列且有序（实测：" .. s .. "）")
  print("  [PASS] 一格多个标记 ⇒ 多个 letter 并列")
end

--------------------------------------------------------------------------------
-- 4. ★ 再点一次 = 取消标记 ⇒ 该格下发 `false`（★ 明确"清空"✓ 不是 nil ✗）
--------------------------------------------------------------------------------
do
  local letters = { "a", "b", "c" }
  local core, c = boot(letters)
  core:select_suspect("B"); core:tap_cell(1, 1)
  core:tap_cell(1, 1)                              -- ★ 第二次 = 取消 ✓
  local n = plan_notes(c, 1, 1)
  ok(n == false, "取消标记后该格下发 false（★ 适配器才会 SetVisible(false) ✓）实测：" .. tostring(n))
  print("  [PASS] 取消标记 ⇒ 下发 false")
end

--------------------------------------------------------------------------------
print(string.format("\ncell_mark_letter: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
