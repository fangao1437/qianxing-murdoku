--[[----------------------------------------------------------------------------
  tests/board_wiring_e2e.lua —— ★★★ **棋盘接线端到端**（本轮的验收判据）

  用户要的只有一件事（★ 原话）：
    「★ **clues 区域的素材路线已经通了** ✓
     ★ **我要的仅仅是棋盘接线这一步** ✓
     ★ **`note` 填 `letter` 内容** ✓ ★ **头像能正常放置** ✓」

  ⇒ 本文件就测这**两步**，从 `assets/row.<关>.<行>` 一路走到**棋盘计划里那一格**：
    ★ ① `letter.<关>.<行>` 的**文本** ⇒ 落到 `cell.r.c` 计划的 **`notes`**（就是 `note` 控件 ✓）
    ★ ② `face.<关>.<行>` 的**图号** ⇒ 落到 `cell.r.c` 计划的 **`image`**（就是 `face` 控件 ✓）

  ★★★ 身份 = **行号**（★ 用户 2026-10-11 定稿 ✓）：
    「★ **如果非要这个机制，就把 `id` 设为 `letter`，或者 `row.i.j`** ✓
     ★ **如果不是必要机制就删了** ✓ ★ **`who` 已经干扰了很多次了**」✓
    ⇒ ★ 所以本文件**故意让 `who` 填成毫无意义的乱码** ✗
      ★ 判据仍然必须全过 ✓ ⇒ ★ 这一条**结构上证明 `who` 不参与棋盘线** ✓✓

  跑法：lua tests/board_wiring_e2e.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local UIC  = require("ui_controller")
local Core = require("murdoku_core")
local lv   = require("tests.fixtures").clue_level_case001()

-- ★ 关序 1 = 自检关 ✓（与 `_level_ordinal()` 的 `LIST` 序号一致 ✓）
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
  if opts.imageId ~= nil then c.imageId = opts.imageId end
  if opts.imageSource ~= nil then c.imageSource = opts.imageSource end
  local kids = opts.kids or {}
  c.GetChildren = function() return kids end
  c.GetChild = function(_, n) for i = 1, #kids do if kids[i].name == n then return kids[i] end end return nil end
  c.FindChild = c.GetChild
  return c
end

-- ── 假 `assets/row.1.*` ──────────────────────────────────────────────────
--   ★ 槽位控件**自己不带 `.text`/`imageId`** ✗ —— 复现"引用控件读不到"那条真机现象 ✓
--   ★★ `who` 故意填**乱码** ✗✓ ← 这一条就是"`who` 不参与棋盘线"的**结构性证据** ✓
local NROWS = 5
local LETTERS = { "甲", "乙", "丙", "丁", "戊" }        -- ★ 故意**不是**棋子 id ✓
local FACES   = { 7001, 7002, 7003, 7004, 7005 }        -- ★ 故意用**互不相同**的图号 ✓
local WHO_JUNK = { "!!乱码1", "??乱码2", "@@乱码3", "##乱码4", "$$乱码5" }

local function make_world()
  local rows = {}
  for pos = 1, NROWS do
    rows[#rows + 1] = ctrl("row.1." .. pos, { kids = {
      ctrl("who.1." .. pos,    { kids = { ctrl("who",    { text = WHO_JUNK[pos] }) } }),
      ctrl("what.1." .. pos,   { kids = { ctrl("what",   { text = "正文" .. pos }) } }),
      ctrl("letter.1." .. pos, { kids = { ctrl("letter", { text = LETTERS[pos] }) } }),
      ctrl("face.1." .. pos,   { kids = { ctrl("face",   { kids = { ctrl("img", { imageId = FACES[pos] }) } }) } }),
    } })
  end
  return { ctrl("root", { kids = { ctrl("assets", { kids = rows }) } }) }
end

-- ── 跑一遍单射（把两张表建起来）────────────────────────────────────────
local function boot()
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  _G.game = { GetClientUIRoots = function() return make_world() end }
  c._grid_in_refresh = true
  c._grid_base = 1
  for pos = 1, NROWS do
    local card = {}
    for _, nm in ipairs({ "who", "letter", "what", "face" }) do
      -- ★ 卡片侧的内容**故意留空** ✗ ⇒ 卡片不会污染判据 ✓（我们只测"row → 棋盘" ✓）
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = { ctrl(nm, {}) } })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  return core, c
end

-- ── 从**下发计划**里取某一格（★ 只读 ✓ 不碰引擎 ✓）────────────────────
--   ★ 为什么要走 `build_layout` ✗：★ 那正是**真正下发到 `cell.*` 控件**的那份计划 ✓
--     ★（而 `note` / `face` 两个子控件就是适配层按这两个字段去写的 ✓）
local function cell_of(c, r, cc)
  local nodes = c:build_layout()
  local want = string.format("cell.%d.%d", r, cc)
  for i = 1, #(nodes or {}) do
    local n = nodes[i]
    if n ~= nil and n.id == want then return n end
  end
  return nil
end
local function joined(t)
  if t == nil then return "<nil>" end
  if t == false then return "<false>" end
  if type(t) ~= "table" then return tostring(t) end
  return table.concat(t, " ")
end

--------------------------------------------------------------------------------
-- 1. ★★★ 放棋子 ⇒ **只出头像，不出字母**（★ 用户 2026-10-11 明确要求 ✓）
--
--   ★★★ 用户原话 ✓：「★ **放置头像的时候把 `letter` 也放下了，这个不用**」✓✓
--   ★★ 判据 ✓：★ **放人那一格的 `notes` 必须是 `false`** ✓
--     ★ `false` = "明确要清空" ✓ ⇒ ★ 适配器 `SetVisible(false)` ⇒ ★ **note 不显示** ✓✓
--   ★ 字母**只在"打标记"那条路出现** ✓ —— ★ 见判据④ ✓
--   ⚠️ ★ 别把它改回 `LETTERS[k]` ✗ —— ★ 那是 2026-10-10 的旧口径 ✓
--     ★（★ "让 `letter` 取代铅笔笔记" 说的是**标记** ✓ 不是"放人也发字母" ✗）
--------------------------------------------------------------------------------
do
  local core, c = boot()
  local allok, detail = true, {}
  for k = 1, NROWS do
    local pid = core.pieces[k].id
    core:select_suspect(pid)
    core:hold_cell(k, k)                  -- ★ 第 k 行第 k 列（避开家具格 ✓）
    local node = cell_of(c, k, k)
    -- ⚠️ ★★ **不能用 `node and node.notes or "…"`** ✗✓（★ 我第一版就踩了 ✓）
    --   ★ 因为"放人 ⇒ 不发字母"之后 `notes` 是 **`false`** ✓
    --     ⇒ ★ `node and false or "<没有这一格>"` ⇒ ★ **求出那个字符串** ✗✓
    --       ⇒ ★ 判据看到的是"没有这一格" ⇒ ★ **把"正确"报成"错"** ✓
    --   ★★ 本项目已经吃过同一个坑 ✓（★ 见 `grid_cost` 里 `visible=false` 那条注释 ✓）
    --     ⇒ ★ **`false` 必须原样取出** ✗
    local got = nil
    if node == nil then got = "<没有这一格>" else got = node.notes end
    -- ★ 必须是 false ✗；★ 若它**等于那一行的 letter** ⇒ ★ 说明"又给放人加字母了" ✗
    if got ~= false then
      allok = false
      detail[#detail + 1] = string.format("棋%s@(%d,%d) notes=%s（★ 应当是 false ✗；★ 若=%s 就是又发了字母 ✗）",
        tostring(pid), k, k, tostring(got), tostring(LETTERS[k]))
    end
  end
  ok(allok, "★ 放棋子 ⇒ `notes == false`（★ 只要头像 ✓ 不要字母 ✓）" .. table.concat(detail, " ｜ "))
  print("  [判据①] 放棋子 ⇒ 只有头像、没有字母：" .. (allok and "5/5 ✓" or "有错 ✗"))
end

--------------------------------------------------------------------------------
-- 2. ★★★ 放棋子 ⇒ 那一格显示**那一行的 `face` 图号**
--------------------------------------------------------------------------------
do
  local core, c = boot()
  local allok, detail = true, {}
  for k = 1, NROWS do
    local pid = core.pieces[k].id
    core:select_suspect(pid)
    -- ★ 用 `(k, k)` —— ★ 与判据①同一组坐标 ✓
    --   ★ 为什么不用"反对角线"✗：★ `case_001` 的 (5,1) 是【家具格】✓
    --     ★ `书架` 就在 (5,1) 且 `occupiable = false` ⇒ ★ `do_place` **正当地拒绝** ✓
    --       ⇒ ★ 那时"格子上没有头像"是**内容规则**，不是接线坏了 ✗
    --     ★★ 判据只该测"接线"，不该测"这一关能不能放"✓
    core:hold_cell(k, k)
    local node = cell_of(c, k, k)
    local got = node and node.image or "<没有这一格>"
    if got ~= FACES[k] then
      allok = false
      detail[#detail + 1] = string.format("棋%s@(%d,%d) 得到 %s 想要 %s",
        tostring(pid), k, k, tostring(got), tostring(FACES[k]))
    end
  end
  ok(allok, "★ 放棋子 ⇒ `image` == 那一行的 `face` ✗ " .. table.concat(detail, " ｜ "))
  print("  [判据②] 棋子 → 行号 → `face`：" .. (allok and "5/5 ✓" or "有错 ✗"))
end

--------------------------------------------------------------------------------
-- 3. ★★★ `who` 是**乱码**，上面两条照样全过 ⇒ ★ 结构性证明它不参与棋盘线
--
--   ★★ 用**打标记**来验 ✗（★ 不是放人 ✓）—— ★ 因为"放人只出头像"之后
--     ★ 字母只在标记那条路上出现 ✓（★ 见判据④ ✓）
--------------------------------------------------------------------------------
do
  local core, c = boot()
  -- ★① 头像那条：★ 放人 ⇒ 头像必须对 ✓（★ 而 `who` 是乱码 ✗）
  core:select_suspect(core.pieces[2].id)
  core:hold_cell(1, 5)
  local node = cell_of(c, 1, 5)
  -- ★ 先证明 `who` 那串**确实被读到了**（否则"乱码也能过"就只是因为"什么都没读到"✗）
  local rt = UIC.Controller._row_text
  local who_read = rt and rt["1"] and rt["1"][2] and rt["1"][2].who or nil
  ok(who_read == WHO_JUNK[2],
    "前提：`who` 的乱码**确实被读进来了**（实测 " .. tostring(who_read) .. "）⇒ 它只是不被棋盘线用 ✓")
  ok(node ~= nil and node.image == FACES[2],
    "★ `who` 是乱码也不影响**头像**（实测 " .. tostring(node and node.image) .. "）")
  ok(node ~= nil and node.notes == false,
    "★ 放人 ⇒ 只有头像、没有字母（实测 notes=" .. tostring(node and node.notes) .. "）")
  -- ★② 字母那条：★ 打标记 ⇒ 必须显示那一行的 `letter` ✓（★ 而 `who` 仍是乱码 ✗）
  local core2, c2 = boot()
  core2:select_suspect(core2.pieces[2].id)
  core2:tap_cell(3, 3)
  local n2 = cell_of(c2, 3, 3)
  ok(n2 ~= nil and joined(n2.notes) == LETTERS[2],
    "★ `who` 是乱码也不影响**标记的字母**（实测 "
    .. tostring(n2 and joined(n2.notes)) .. " 想要 " .. LETTERS[2] .. "）")
  print("  [判据③] `who` 乱码 ⇒ 头像与标记字母都照常 ✓（它已被移出棋盘线）")
end

--------------------------------------------------------------------------------
-- 4. ★★ 打标记（铅笔笔记）那条路也走同一张表 ⇒ 显示 `letter` 而不是棋子 id
--------------------------------------------------------------------------------
do
  local core, c = boot()
  core:select_suspect(core.pieces[3].id)
  core:tap_cell(2, 2)                     -- ★ 单击 = 打标记（★ 数据层是 {棋子id=true} ✓）
  local node = cell_of(c, 2, 2)
  ok(node ~= nil and joined(node.notes) == LETTERS[3],
    "★ 打标记 ⇒ 显示那一行的 `letter`（实测 " .. (node and joined(node.notes) or "?") .. "）")
  print("  [判据④] 打标记 → 同一张表 → 同一个 `letter` ✓")
end

--------------------------------------------------------------------------------
-- 5. ★ 换关 ⇒ 那两张表必须清（★ 否则第 2 关显示第 1 关的字/图）
--------------------------------------------------------------------------------
do
  local core, c = boot()
  -- ★★ 用**打标记**验"表里有东西" ✗ —— ★ 放人已经不发字母了 ✓（★ 见判据① ✓）
  core:select_suspect(core.pieces[1].id)
  core:tap_cell(1, 1)
  local n1 = cell_of(c, 1, 1)
  ok(n1 ~= nil and joined(n1.notes) == LETTERS[1], "前提：第一关的表已经建好（标记显示 " ..
    tostring(n1 and joined(n1.notes)) .. "）")
  -- ★ 换关 ⇒ 清表 ✓
  c._row_map_sig = nil
  c:_reset_row_maps_if_level_changed()
  ok(next(UIC.Controller._row_letter) == nil and next(UIC.Controller._row_face) == nil,
    "★ 换关 ⇒ 两张表清空（★ 防跨关串字/串图）")
  print("  [判据⑤] 换关清表 ✓")
end

--------------------------------------------------------------------------------
-- 6. ★★★ **换关后棋子顺序变了** ⇒ 不许用上一关的顺序（★ 独立复核者指出的静默错值）
--
--   ★★★ 为什么必须单独测 ✗（★ 复核者的实测 ✓）：
--     ★ `Controller._piece_core` 是**模块级**的 ✓（★ 静态函数要读 ✓）
--     ★★ 如果换关时**不清**它 ✗ ⇒ ★ 它会拿着**上一关的 `core`** 去算"棋子 → 行号" ✓
--       ⇒ ★★ 而它**不报错、也不返 nil** ✗ —— ★ **它给一个错的答案** ✓✓
--   ★ 今天为什么不发作 ✗：★ 四关的 `pieces` 顺序**都是** `A,B,C,D(,E)(,F),V` ✓
--     ⇒ ★ 同一个 id 在每一关的行号**处处相同** ✓ ⇒ 拿错了也看不出差别 ✓
--   ★★★ 所以判据必须**自己造一关顺序不同的** ✗✓ —— ★ 否则这条永远测不出来 ✓
--
--   ★ 做法 ✓：★ 克隆 `case_001` 但把 `suspects` **整个倒过来** ✓
--     ★ 同时**保持 `id` 不变** ✓ ⇒ ★ 关序仍是 1 ⇒ `row.1.*` 照样能读到 ✓
--     ★★ 这样"行号 → 棋子"就**必然不同** ✓ ⇒ ★ 用上一关的表就一定错 ✓✓
--------------------------------------------------------------------------------
do
  local base = require("levels.case_001")
  local flipped = {}
  for k, v in pairs(base) do flipped[k] = v end
  local sus = {}
  for i = #base.suspects, 1, -1 do sus[#sus + 1] = base.suspects[i] end
  flipped.suspects = sus
  -- ★ 受害者按 id 找 ✓（★ 顺序变了，但 id 没变 ✓）
  flipped.victim = base.victim
  -- ★ `id` 保持不变 ⇒ `_level_ordinal()` 仍然回 1 ⇒ `row.1.<行>` 读得到 ✓
  flipped.id = base.id

  package.loaded["levels.case_001"] = flipped
  local core = Core.new(require("levels.case_001"))
  local c = UIC.new(core, { skip_intro = true })
  -- ★★★ **走真实的那条路** ✗✓：★ 先让"上一关"的状态成立 ✓，再让换关清一次 ✓
  --   ★ 步骤 ✓：
  --     ① 塞一个**顺序不同的** `core` 当"上一关" ✓
  --     ② 让 `_row_map_sig` 与**本关不同** ✓ ⇒ ★ `_reset_row_maps_if_level_changed`
  --        这一次会**真的执行清理** ✓（★ 而不是被签名挡住 ✓）
  --     ③ 调它 ✓ ⇒ ★ 修好的代码会清掉 `_piece_core` ✓；★ 没修就会留着上一关的 ✗
  --   ★★ 于是判据**能真的抓到这个 bug** ✓（★ 我第一版只塞了不来清 ⇒ 抓不到 ✗ 复核者指出 ✓）
  local stale = Core.new(lv)                       -- ★ "上一关"的 core（顺序 = A,B,C,D,V）
  UIC.Controller._piece_core = stale
  UIC.Controller._piece_id_cache = { core = stale, ids = { "A", "B", "C", "D", "V" } }
  UIC.Controller._row_letter = {}
  UIC.Controller._row_face = {}
  c._row_map_sig = "上一关的id"                    -- ★ 保证这次会真的清 ✓
  c:_reset_row_maps_if_level_changed()
  local flipped_first = core.pieces[1].id          -- ★ 倒过来之后第 1 个是谁 ✓
  local flipped_second = core.pieces[2].id
  ok(flipped_second ~= "B",
    "前提：本关的棋子顺序**真的不同**（第 2 个 = " .. tostring(flipped_second) .. "，不是 B）")
  ok(UIC.Controller._piece_core == nil,
    "★ 换关清表把 `_piece_core` 也清掉（实测 " .. tostring(UIC.Controller._piece_core) .. "）")
  -- ★ `boot()` 的搭法在这里不能用（它固定吃 `lv`）⇒ 手工搭一遍 ✓
  _G.game = { GetClientUIRoots = function() return make_world() end }
  c._grid_in_refresh = true
  c._grid_base = 1
  for pos = 1, NROWS do
    local card = {}
    for _, nm in ipairs({ "who", "letter", "what", "face" }) do
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = { ctrl(nm, {}) } })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  package.loaded["levels.case_001"] = nil          -- ★ 立刻还原 ✓

  -- ★★ 判据 ✓：★ **第 2 个棋子打标记 ⇒ 必须拿到第 2 行的 `letter`** ✓
  --   ★ 若还拿上一关的顺序 ⇒ ★ 第 2 个棋子会被算成别的行 ⇒ ★ 拿到别的字母 ✗
  --   ★（★ 用**打标记**验 ✗ —— ★ 放人已经不发字母了 ✓ 见判据① ✓）
  local node = nil
  core:select_suspect(flipped_second)
  core:tap_cell(2, 2)
  local nodes = c:build_layout()
  for i = 1, #(nodes or {}) do
    if nodes[i] ~= nil and nodes[i].id == "cell.2.2" then node = nodes[i] break end
  end
  local got = (node ~= nil) and joined(node.notes) or "<没有这一格>"
  ok(got == LETTERS[2],
    "★ 换关后棋子顺序变了 ⇒ 仍然按**本关**的顺序取（第 1 个=" .. tostring(flipped_first) ..
    " 第 2 个=" .. tostring(flipped_second) .. "）实测 " .. got .. " 想要 " .. LETTERS[2])
  print("  [判据⑥] 换关 + 棋子顺序变化 ⇒ 用本关的表 ✓（静默错值被抓）")
end

--------------------------------------------------------------------------------
-- 7. ★★★ **就地重填那条路也要落账**（★ `_grid_in_refresh == false` ✓）
--
--   ★★★ 为什么必须测 ✗（★ 独立复核者指出的"删除带来的唯一收窄" ✓）：
--     ★ 删掉"第二趟单射"之前 ✓ ★ 那一趟是**无条件**跑的（`if true` ✓）
--       ⇒ ★ 它把 `_grid_refill_now`（就地重填 ✓ `_grid_in_refresh == false` ✓）
--         那条路也覆盖了 ✓
--     ★★ 删掉之后 ✗ ⇒ ★ 那条路**只剩算法** ✓ ⇒ ★ `row.*` 的四个槽位就没人落了 ✓
--   ★ 今天为什么不发作 ✗：★ `row.*` 是**静态内容** ✓ ⇒ ★ 进关那次 `RefreshItems`
--     已经把表建好了 ✓ ★ 而 `do_place` 只改棋盘、不改 `row.*` ✓
--   ★★ 但"**换关** ＋ 第一趟没跑成"就会空 ✗ ⇒ ★ 那是真实可发生的顺序 ✓
--   ⇒ ★ 判据 ✓：★ **把表清空 ＋ `_grid_in_refresh = false`** ⇒ ★ 仍必须落账 ✓
--     ★ 而且**逐行判** ✓ —— ★ "行 1 落过、行 2 没落"时也要补上行 2 ✓
--------------------------------------------------------------------------------
do
  local core, c = boot()
  -- ★ 先制造"只落了一行"的状态 ✓（★ 这才测得出"按行判"而不是"整张表判" ✓）
  UIC.Controller._row_letter = {}
  UIC.Controller._row_face = {}
  c._grid_in_refresh = false                      -- ★ 模拟 `_grid_refill_now` ✓
  UIC.Controller._row_letter[1] = "旧值"          -- ★ 第 1 行已经有值（且是错的）✓
  local card = {}
  for _, nm in ipairs({ "who", "letter", "what", "face" }) do
    card[#card + 1] = ctrl("clue." .. 2 .. "." .. nm, { kids = { ctrl(nm, {}) } })
  end
  c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), 2)
  ok(UIC.Controller._row_letter[2] == LETTERS[2],
    "★ `_grid_in_refresh=false`（就地重填）时，**缺的那一行也要补上**（实测 " ..
      tostring(UIC.Controller._row_letter[2]) .. "）")
  ok(UIC.Controller._row_letter[1] == "旧值",
    "★ 已有值的那一行**不许被覆盖**（★ 先到先得 ✓ 实测 " ..
      tostring(UIC.Controller._row_letter[1]) .. "）")
  print("  [判据⑦] 就地重填补缺行 ✓（★ 删除带来的收窄已堵上）")
end

--------------------------------------------------------------------------------
print(string.format("\nboard_wiring_e2e: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
