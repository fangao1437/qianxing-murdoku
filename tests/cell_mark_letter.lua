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
--   ★★ 2026-10-11 **补上 `imageId`** ✗✓（★ 复核者建议的"第二哨兵"逼出来的 ✓）
--     ★ 原来这个假控件**只认 `text`** ✗ ⇒ ★ 任何 `{ imageId = … }` 都被**静默丢掉** ✓
--     ★★ 后果 ✓：★ `_find_image_holder` 找不到图 ⇒ `_row_face` 恒空 ✓
--       ⇒ ★ "头像链"在这一套件里**根本测不了** ✗（★ 会假红 ✓ —— 我第一版就踩了 ✓）
local function ctrl(name, opts)
  opts = opts or {}
  local c = { name = name }
  if opts.text ~= nil then c.text = opts.text end
  if opts.imageId ~= nil then c.imageId = opts.imageId end
  if opts.imageSource ~= nil then c.imageSource = opts.imageSource end
  local kids = opts.kids or {}
  c.GetChildren = function() return kids end
  c.GetChild = function(_, n) for i = 1, #kids do if kids[i].name == n then return kids[i] end end return nil end
  c.FindChild = function(_, n) for i = 1, #kids do if kids[i].name == n then return kids[i] end end return nil end
  return c
end

-- ── 假 `assets/row.1.*` ──────────────────────────────────────────────────
--   ★ `letters` 里写什么，那一行就配什么 ✓（★ nil = 没配 ✓）
--   ★ 槽位控件自己**不带 `.text`** ✗ —— 复现"引用控件读不到"那条真机现象 ✓
--
-- ★★★★★★ 2026-10-11 **键 = 那一行的 `who` 文本** ✗✓✓（★ 用户定案 ✓）
--   ★★★ 用户原话 ✓：「★ **前面的模式不是已经说明了 `who` 不参与棋盘线吗** ✓
--     ★ **怎么又开始纠结这个无关量了**」✓✓
--   ★★ 真实契约 ✓：★「★ **就是按旧逻辑** ✓ ★ **只需要换素材来源** ✓
--     ★ **后面的逻辑一切照旧**」✓ ⇒ ★ 旧逻辑的键 = `cl.who` ✓
--     ★★ 新模型下 = ★ **那一行的 `who` 槽文本** ✓✓
--   ⇒ ★ 所以这里**必须给每一行填一个真的 `who`** ✗（★ 原来一律填 `"x"` ⇒ 全行同键 ⇒ 假红 ✓）
--     ★★ 而且键**必须各不相同** ✓（★ 否则后面按行点格子会互相覆盖 ✓）
local function make_world(letters, whos)
  local rows = {}
  for pos = 1, #letters do
    local inner = {}
    if letters[pos] ~= nil then inner = { ctrl("letter", { text = letters[pos] }) } end
    local w = (whos and whos[pos]) or ("w" .. pos)
    rows[#rows + 1] = ctrl("row.1." .. pos, { kids = {
      ctrl("who.1." .. pos,    { kids = { ctrl("who",    { text = w }) } }),
      ctrl("letter.1." .. pos, { kids = inner }),
      ctrl("what.1." .. pos,   { kids = { ctrl("what",   { text = "x" }) } }),
      ctrl("face.1." .. pos,   { kids = { ctrl("face",   { kids = { ctrl("img", { imageId = 111 }) } }) } }),
    } })
  end
  return { ctrl("root", { kids = { ctrl("assets", { kids = rows }) } }) }
end

-- ── 建控制器 ＋ 跑单射（把 `_row_letter` 建起来）────────────────────────
--   ★ 返回的三样里多一个 `whos` ✓ —— ★ 它就是"每行的键" ✓ 后面打标记要用它 ✓
local function boot(letters, whos)
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  -- ★★★ 2026-10-11 **键必须是【核心真实棋子 id】** ✗✓（★ 实测约束 ✓ 不是我的选择 ✓）
  --   ★ `Core:select_suspect`（core L1694 ✓）：`if not self.piece_by_id[id] then return false end`
  --     ★★ 而 `tap_cell` 要"先选中"才打标记 ✓ ⇒ ★ **键不是真实棋子 ⇒ 标记根本打不上** ✓✓
  --   ★ 实测 ✓：★ `select_suspect("乙")` / `("管家")` / `("w1")` **全 false** ✓
  --     ★ 只有 `("A")`/`("B")`… 才 true ✓
  --   ⇒ ★ 所以测试用**真实棋子 id** ✓ ★ 而"行 → 棋子"的对应就用第 pos 个棋子 ✓
  local keys = {}
  for pos = 1, #letters do
    keys[pos] = (whos and whos[pos]) or (core.pieces[pos] and core.pieces[pos].id) or ("w" .. pos)
  end
  _G.game = { GetClientUIRoots = function() return make_world(letters, keys) end }
  c._grid_in_refresh = true
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
-- 1. ★★★ 核心判据：打标记 ⇒ 格子显示【letter】而不是那个键
--
--   ★★★ 2026-10-11 **标记的键改成"那一行的 `who`"了** ✗✓（★ 用户定案 ✓）
--     ★ 用户原话 ✓：「★ **`who` 不参与棋盘线** ✓ ★ **别纠结这个无关量**」✓
--     ★ 真实契约 ✓：★「★ **就是按旧逻辑** ✓ ★ **只需要换素材来源** ✓
--       ★ **后面的逻辑一切照旧**」✓
--     ★★ 旧逻辑的键 = `cl.who` ✓ ⇒ ★ 新模型下 = ★ **那一行 `who` 槽的文本** ✓✓
--   ⇒ ★ 所以本节的"人"不再是 `B`/`A`/`V` ✗ ⇒ ★ 改成**第 1/2/3 行的键** ✓
--------------------------------------------------------------------------------
do
  -- ★ 故意用**小写**字母 ⇒ ★ 一眼分得出"显示的是 letter 还是那个键" ✓✓
  local letters = { "a", "b", "c" }
  local core, c, keys = boot(letters)
  -- ★ 用户的手势 ✓：选那一行 ⇒ 单击格子 ⇒ 打一个标记 ✓
  core:select_suspect(keys[1]); core:tap_cell(1, 1)
  core:select_suspect(keys[2]); core:tap_cell(2, 1)
  core:select_suspect(keys[3]); core:tap_cell(3, 1)

  -- ★ 数据层必须是**【那个键】** ✓ —— ★ 这一条不许被改掉 ✗
  local ids = {}
  for k in pairs(core.notes[1][1] or {}) do ids[#ids + 1] = tostring(k) end
  ok(#ids == 1 and ids[1] == keys[1], "数据层存的仍然是那个键（★ 不许改成存 letter ✗）")

  local n1 = plan_notes(c, 1, 1)
  local n2 = plan_notes(c, 2, 1)
  local n3 = plan_notes(c, 3, 1)
  local function joined(t)
    if type(t) ~= "table" then return tostring(t) end
    return table.concat(t, " ")
  end
  ok(joined(n1) == "a", "格子(1,1) 打的是第 1 行 ⇒ 显示那一行的 letter = a（实测：" .. joined(n1) .. "）")
  ok(joined(n2) == "b", "格子(2,1) 打的是第 2 行 ⇒ 显示 = b（实测：" .. joined(n2) .. "）")
  ok(joined(n3) == "c", "格子(3,1) 打的是第 3 行 ⇒ 显示 = c（实测：" .. joined(n3) .. "）")
  -- ★★★★★★★★ 2026-10-11 **下发的 `notes` 必须是【表】** ✗✓✓（★ 真机红字的哨兵 ✓）
  --
  --   ★★★ 真机日志 ✓（★ 用户 v183 原文 ✓）：
  --     `属性下发失败：`cell.3.4.notes` ← bad argument #1 to 'concat' (table expected)` ✗
  --     `属性补发 3 次仍未送达，已停止补发：`cell.3.4.notes`` ✗
  --     ⇒ ★★ **那一格的字一个都没下去** ✓✓
  --   ★ 根因 ✓：★ 适配层那条路是 **`table.concat(value or {}, " ")`** ✓
  --     ★★ 而"放棋子"那条路传的是 **一个字符串** ✗ ⇒ ★ `concat("D")` **抛错** ✓
  --       ★ 而"打标记"那条路传的是**表** ✓ ⇒ ★ **两条路类型不一致** ✓✓
  --   ★ 判据 ✓：★ **两条路都必须给表** ✓ —— ★ 因为写进的是**同一个 `notes` 字段** ✓
  --   ★★ 这一条同时钉住"以后别再改回字符串" ✗（★ 那是**两个模块之间的契约** ✓）
  ok(type(n1) == "table", "★ `notes` 必须是【表】（适配层 table.concat 要求 ✓）实测：" .. type(n1))
  -- ★ 放棋子那条路也要给表 ✓（★ 它才是真机报错的那一条 ✓）
  local core2 = Core.new(lv)
  local c2 = UIC.new(core2, { skip_intro = true })
  core2:select_suspect(core2.pieces[1].id)
  core2:hold_cell(5, 5)
  local nn = plan_notes(c2, 5, 5)
  ok(type(nn) == "table",
    "★ 【放棋子】那条路的 `notes` 也必须是表（★ 真机报错就是它 ✗）实测：" .. type(nn))
  print("  [PASS] 打标记 ⇒ 显示 letter（★ 不是那个键 ✓）＋ `notes` 类型是表 ✓")
end

--------------------------------------------------------------------------------
-- 2. ★ 没配 `letter` 的行 ⇒ 回退那个键（★ 不许突然空白 ✓）
--------------------------------------------------------------------------------
do
  -- ★ 只给 3 行配 letter ✓ ★ 而键取**前 3 个真实棋子** ✓ ⇒ 第 4 个棋子天然没配 ✓
  local letters = { "a", "b", "c" }
  local core, c, keys = boot(letters)
  local k4 = nil
  for i = 1, #core.pieces do if keys[i] == nil then k4 = core.pieces[i].id break end end
  ok(k4 ~= nil, "前提：找得到一个【没配 letter】的真实棋子")
  ok(UIC.Controller._row_letter[k4] == nil, "前提：那个棋子没有配 letter")
  core:select_suspect(k4); core:tap_cell(4, 2)
  local n = plan_notes(c, 4, 2)
  local s = (type(n) == "table") and table.concat(n, " ") or tostring(n)
  ok(s == k4, "没配 letter ⇒ 回退那个键（实测：" .. tostring(s) .. " 该是 " .. tostring(k4) .. "）")
  print("  [PASS] 没配 letter 时回退那个键（★ 不会空白 ✓）")
end

--------------------------------------------------------------------------------
-- 3. ★ 一格多个标记 ⇒ 多个 letter 并列（★ 排序稳定 ✓）
--------------------------------------------------------------------------------
do
  local letters = { "a", "b", "c" }
  local core, c, keys = boot(letters)
  core:select_suspect(keys[2]); core:tap_cell(2, 3)   -- 第 2 行 ⇒ letter b
  core:select_suspect(keys[3]); core:tap_cell(2, 3)   -- 第 3 行 ⇒ letter c
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
  local core, c, keys = boot(letters)
  core:select_suspect(keys[1]); core:tap_cell(1, 1)
  core:tap_cell(1, 1)                              -- ★ 第二次 = 取消 ✓
  local n = plan_notes(c, 1, 1)
  ok(n == false, "取消标记后该格下发 false（★ 适配器才会 SetVisible(false) ✓）实测：" .. tostring(n))
  print("  [PASS] 取消标记 ⇒ 下发 false")
end

--------------------------------------------------------------------------------
-- 5. ★★★ **头像那条链**（`face` ⇒ 计划的 `image`）★ 第二个哨兵 ✗✓
--
--   ★★★ 为什么必须在这里也钉一份 ✗（★ 独立复核者的发现 ✓）：
--     ★ 复核者做了五类破坏实验 ✓ ★ 结论是：
--       ★★ **只有 `tests/board_wiring_e2e.lua` 能抓到 `face` / `portrait_of` 的错** ✗
--         ★ 而 `clue_slots`（54 条断言）对这条链**全盲** ✓
--     ⇒ ★★ **一条链只挂在一个哨兵上**是脆的 ✓ —— ★ 将来谁动了那个文件就没人拦 ✓
--   ⇒ ★ 这一节把 `face` 这条链**再钉一遍** ✓ ——
--     ★ 复用本文件已有的 `boot()`（★ 它直接驱动 `_fill_grid_item` ✓
--       ★ **不依赖网格视窗** ✓ ⇒ 与 `board_wiring_e2e` 的路径**不同源** ✓✓）
--------------------------------------------------------------------------------
do
  -- ★ 本文件的老夹具把 `face` 造成 `{ kids = { img{imageId=111} } }` ✓
  --   ★ 但那条链**读不到**图号 ✓（实测落兜底 ⇒ 报 `portrait.A` ✗）
  --   ★★ 所以这一节**自己搭一个最小世界** ✗ —— ★ 不依赖老夹具的形状 ✓
  --     ★ 而且正好与 `board_wiring_e2e` 的搭法**各自独立** ✓（★ 两个哨兵不同源 ✓）
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  local FACE_ID = 901
  local rows = {}
  for pos = 1, 3 do
    rows[#rows + 1] = ctrl("row.1." .. pos, { kids = {
      ctrl("who.1." .. pos,    { kids = { ctrl("who",    { text = "乱码" .. pos }) } }),
      ctrl("what.1." .. pos,   { kids = { ctrl("what",   { text = "正文" .. pos }) } }),
      ctrl("letter.1." .. pos, { kids = { ctrl("letter", { text = "字" .. pos }) } }),
      ctrl("face.1." .. pos,   { kids = { ctrl("face",   { kids = { ctrl("img", { imageId = FACE_ID }) } }) } }),
    } })
  end
  _G.game = {
    GetClientUIRoots = function()
      local rt = ctrl("root", { kids = { ctrl("assets", { kids = rows }) } })
      return { rt }
    end,
  }
  c._grid_in_refresh = true
  c._grid_base = 1
  for pos = 1, 3 do
    local card = {}
    for _, nm in ipairs({ "who", "letter", "what", "face" }) do
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = { ctrl(nm, {}) } })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  -- ★ 关序要能对上（`boot` 里设过一次 ✓ 这里再设一次免得依赖顺序 ✓）
  package.loaded["levels.init"] = {
    index_of = function(id) if id == lv.id then return 1 end return nil end,
  }
  local keys2 = {}
  for i = 1, #core.pieces do keys2[i] = core.pieces[i].id end
  core:select_suspect(keys2[1])
  core:hold_cell(1, 1)
  local nodes = c:build_layout()
  local node = nil
  for i = 1, #(nodes or {}) do
    if nodes[i] ~= nil and nodes[i].id == "cell.1.1" then node = nodes[i] break end
  end
  ok(node ~= nil, "★ 找得到 cell.1.1 的规划节点")
  ok(node ~= nil and node.image == FACE_ID,
    "★ 放棋子 ⇒ 格子 `image` == 那一行 `face` 的图号（实测 " .. tostring(node and node.image) .. "）")
  -- ★★ 反向 ✓：★ **没人的格子必须是 `false`** ✗（★ 不是 nil ✗ ——
  --   ★ 本项目踩过：`nil` 等于"这个键不存在" ⇒ **旧头像永远不清** ✓）
  local empty = nil
  for i = 1, #(nodes or {}) do
    if nodes[i] ~= nil and nodes[i].id == "cell.5.5" then empty = nodes[i] break end
  end
  ok(empty ~= nil and empty.image == false,
    "★ 空格子 ⇒ `image == false`（★ 明确「清空」✓ 不是 nil ✗）实测：" ..
      tostring(empty and empty.image))
  print("  [PASS] 头像链（`face` → 计划 `image`）第二哨兵")
end

--------------------------------------------------------------------------------
print(string.format("\ncell_mark_letter: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
