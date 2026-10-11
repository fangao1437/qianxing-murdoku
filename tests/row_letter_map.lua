--[[----------------------------------------------------------------------------
  tests/row_letter_map.lua —— 「线索行的 `letter` ⇒ 棋盘格的 `note`」这条链的回归

  为什么必须有这个文件 ✗：
    真机上"选中 `letter` 为 a 的卡，格子里填的是 b / v / e"这条 bug，
    根因在**子控件循环里的那句清理**上（详见 `ui_controller.lua` 早期单射处注释）。
    而它**离线完全看不出来** —— 模拟器没有 `assets/row.*` 那条模板引用链，
    真机一轮又要用户手动导档 + 同步 + 重启。

    ⇒ 这里把 `game.GetClientUIRoots()` 那一层**假造出来**，直接驱动
      `_fill_grid_item`，把"子控件顺序"当自变量，把 `Controller._row_letter` 当因变量。

  钉死的三件事：
    ① ★ 子控件顺序**任意**（`letter` 在头 / 中间 / 尾）⇒ 落账都要成立
    ② ★ 文字读不到时 ⇒ **不写**（不许用上一个 pos 的残值）
    ③ ★ 引用控件自己没 `.text` 时 ⇒ 靠 `FindChild(槽位名)` / 子孙兜底也要读到

  跑法：lua tests/row_letter_map.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

-- ── 假控件 ────────────────────────────────────────────────────────────────
--   只实现 `_fill_grid_item` 真正用到的那几个成员：
--     name / text / imageId / imageSource / SetText / SetImage / GetChildren / GetChild
local function ctrl(name, opts)
  opts = opts or {}
  local c = { name = name }
  if opts.text ~= nil then c.text = opts.text end
  if opts.imageId ~= nil then c.imageId = opts.imageId end
  if opts.imageSource ~= nil then c.imageSource = opts.imageSource end
  if opts.SetImage ~= nil then c.SetImage = opts.SetImage end
  local kids = opts.kids or {}
  c.GetChildren = function() return kids end
  c.GetChild = function(_, n)
    for i = 1, #kids do if kids[i].name == n then return kids[i] end end
    return nil
  end
  c.FindChild = function(_, n)
    for i = 1, #kids do if kids[i].name == n then return kids[i] end end
    return nil
  end
  return c
end

-- ── 造假树：root → assets → row.<关>.<行> → 四个槽位 ─────────────────────
--   ★ 顺序是**自变量** ✓ —— 真机存档里 20 行有 19 行 `letter` 不在最后 ✓
--
-- ★★★★★★ 2026-10-11 **键改成"那一行的 `who` 文本"了** ✗✓✓（★ 用户定案 ✓）
--   ★★★ 用户原话 ✓：「★ **前面的模式不是已经说明了 `who` 不参与棋盘线吗** ✓
--     ★ **怎么又开始纠结这个无关量了**」✓✓
--   ★★ 真实契约 ✓（★ 他 2026-10-10 就定过 ✓）：
--     ★「★ **就是按旧逻辑** ✓ ★ **`face` 和 `letter` 怎么放是由点击指示的** ✓
--       ★ **等于你只需要换素材来源** ✓ ★ **后面的逻辑一切照旧**」✓
--     ★ 旧逻辑的键 = `cl.who` ✓ ★ 新模型下 = ★ **那一行 `who` 槽里的文本** ✓
--     ★★ 两张表**同一个键** ✓ ⇒ ★ 棋盘要的 `letter` / `face` 天然同键 ✓✓
--   ⇒ ★ 所以假树**必须带 `who` 槽** ✗（★ 原来的假树没带 ⇒ 三套件假红 ✓）
local function make_world(order, letters, whos)
  local rows = {}
  for pos = 1, #order do
    local slot = order[pos]
    local letter_txt = letters[pos]
    local who_txt = whos and whos[pos] or nil
    local kids = {}
    for _, nm in ipairs(slot) do
      -- ★ 槽位控件自己【不带】`.text` ✗ —— 复现"引用控件读不到"那条真机现象 ✓
      -- ★ 空串要造得**跟真机一样** ✓：★ 空文字 ⇒ 那个文本框【没有 text】✗
      --   （★ 不是"有 text 但内容是空串" ✓ —— 后者会被当成"配了空白" ✓）
      local inner = {}
      if nm == "letter" then
        if letter_txt ~= nil and letter_txt ~= "" then inner = { ctrl(nm, { text = letter_txt }) } end
      elseif nm == "who" then
        -- ★★ `who` 槽 ✓ —— ★ **它就是键** ✓ ★ 真机上它一定有值 ✓
        if who_txt ~= nil and who_txt ~= "" then inner = { ctrl(nm, { text = who_txt }) } end
      else
        inner = { ctrl(nm, { text = "x" }) }
      end
      kids[#kids + 1] = ctrl(nm .. ".1." .. pos, { kids = inner })
    end
    rows[#rows + 1] = ctrl("row.1." .. pos, { kids = kids })
  end
  local assets = ctrl("assets", { kids = rows })
  local rt = ctrl("root", { kids = { assets } })
  return { rt }
end

local UIC = require("ui_controller")
local Core = require("murdoku_core")
local lv = require("tests.fixtures").clue_level_case001()

-- ★★★ 注意 ✓：`Controller._row_letter` / `_row_face` 挂在
--   **`M.Controller`**（`ui_controller.lua:276` ✓）上，**不是**模块表自己 ✗
--   ★ 我第一版测试就写成了 `UIC._row_letter` ✓ ⇒ ★ 恒 nil ⇒ 假红一次 ✓（已修 ✓）
local Ctl = UIC.Controller

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL  " .. msg)
  end
end

package.loaded["levels.init"] = {
  index_of = function(id) if id == lv.id then return 1 end return nil end,
}

-- 每个 pos 的 `who`（人物 id）由**关卡视图**决定 ⇒ 从 core 现查，别猜 ✓
local function whos(core)
  local vm = core:view() or {}
  local out = {}
  for i = 1, #(vm.clues or {}) do out[i] = vm.clues[i].who end
  return out
end

-- ★ 一个 `who` 可能被【多条线索】点到（`case_001` 就有 `same_room` 那条没 who ✓，
--   而 7/8 两条都指 A ✓）⇒ ★ 这时 `_row_letter[A]` **本来就该是最后写的那条** ✓
--   ⇒ ★ 断言只对"**who 唯一非空**"的那些 pos 做 ✓（★ 否则是判据错，不是代码错 ✗）
local function unique_want(ws, letters)
  local count = {}
  for i = 1, #ws do
    local w = ws[i]
    if w ~= nil then count[w] = (count[w] or 0) + 1 end
  end
  local want = {}
  for i = 1, #ws do
    local w = ws[i]
    if w ~= nil and count[w] == 1 then want[tostring(w)] = letters[i] end
  end
  return want
end

local function run(order, letters, expected_pos)
  local core = Core.new(lv)
  local c = UIC.new(core, { skip_intro = true })
  local n = #order
  -- ★★★ 2026-10-11 **`who` 槽里要填【真正的键】** ✗✓（★ 用户定案 ✓）
  --   ★ 原来这里填 `true` ✗ —— 那是按**旧模型**（键 = 视图里的 `cl.who` = 人物 id ✓）写的 ✓
  --     ★ 而槽位模型下 `cl.who` 恒 nil ✓ ⇒ ★ 键改由 `row.*.who` 提供 ✓✓
  --   ⇒ ★ 用**这一行自己的 `who` 文本** ✓ ★ 保证每行唯一 ✓ ⇒ ★ 断言可以逐行做 ✓
  local want = {}
  for pos = 1, n do want[pos] = "w" .. pos end
  c._grid_in_refresh = true
  c._grid_base = 1
  -- ★ 每轮从**空表**开始 ✓ —— 落账的表是模块级的 ✓ 不清就会串轮 ✓
  Ctl._row_letter = {}
  _G.game = { GetClientUIRoots = function() return make_world(order, letters, want) end }
  -- adapter 传 nil ⇒ 相关分支自己 pcall 兜住 ✓（本项目就是这么写的 ✓）
  -- ★ 列表项也照卡片模板造 ✓ —— `_fill_grid_item` 第一步就是
  --   `item:FindChild("clue.<pos>.<槽位>")` ✓ 返回 nil 的话整段 `if dst ~= nil` 都不进 ✓
  --   （★ 那样测的就不是我们要测的那条路了 ✗）
  for pos = 1, n do
    local card = {}
    for _, nm in ipairs(order[pos]) do
      -- ★ 卡片侧同理：控件自己不带 `.text` ✗ ⇒ 走 `_read_control_text` 的三层 ✓
      card[#card + 1] = ctrl("clue." .. pos .. "." .. nm, { kids = {
        ctrl(nm, { text = (nm == "letter") and letters[pos] or "x" }),
      } })
    end
    c:_fill_grid_item(nil, nil, ctrl("item", { kids = card }), pos)
  end
  Ctl._row_letter = Ctl._row_letter or {}
  -- ★ 键 = 这一行填的 `who` 文本 ✓（★ 不再从 `core` 反查人物 id ✗）
  local got = {}
  for pos = 1, n do
    got[tostring(want[pos])] = Ctl._row_letter[tostring(want[pos])]
  end
  _G.game = nil
  return got, want
end
--------------------------------------------------------------------------------
-- 1. ★ 三种顺序都要成立（这就是本次 bug 的判据）
--------------------------------------------------------------------------------
do
  local letters = { "a", "b", "c", "d", "e", "f", "g" }
  local cases = {
    { name = "letter 在【最后】", order = {} },
    { name = "letter 在【最前】", order = {} },
    { name = "letter 在【中间】", order = {} },
  }
  for _, cs in ipairs(cases) do
    cs.order = {}
    for pos = 1, 7 do
      local slots = {}
      if cs.name == "letter 在【最前】" then
        slots = { "letter", "who", "what", "face" }
      elseif cs.name == "letter 在【中间】" then
        slots = { "who", "letter", "what", "face" }
      else
        slots = { "who", "what", "face", "letter" }
      end
      cs.order[pos] = slots
    end
  end
  for _, cs in ipairs(cases) do
    local got, ws = run(cs.order, letters)
    local want = unique_want(ws, letters)
    local allok, detail, n = true, {}, 0
    for k, v in pairs(want) do
      n = n + 1
      if got[k] ~= v then
        allok = false
        detail[#detail + 1] = k .. "=" .. tostring(got[k]) .. "(want " .. v .. ")"
      end
    end
    ok(allok and n > 0, cs.name .. " ⇒ 落账不完整 ✗ " .. table.concat(detail, " "))
    print(string.format("  [%s] %s（断言 %d 个 who）", allok and "PASS" or "FAIL", cs.name, n))
  end
end

--------------------------------------------------------------------------------
-- 2. ★ 读不到 ⇒ 不写（不许留上一个 pos 的残值）
--------------------------------------------------------------------------------
do
  Ctl._row_letter = {}
  local order = {}
  for pos = 1, 5 do order[pos] = { "who", "letter", "what", "face" } end
  -- ★ `case_001` 前 5 条的 `who` = V / @thief / @thief / C / B ✓
  --   ⇒ ★ 挑**唯一**的 V（第 1 行 ✓）把它清空 ✓ —— ★ 这样断言不会被"同名 who"污染 ✓
  --     （★ `@thief` 那两条本来就该互相覆盖 ✓ 拿它当判据是判据错 ✗）
  local letters = { "", "b", "c", "s", "t" }
  local _, ws = run(order, letters)
  local w1 = ws[1] and tostring(ws[1]) or nil
  ok(w1 ~= nil and Ctl._row_letter[w1] == nil, "空 `letter` 的行不许落账（防残值）")
  local w4 = ws[4] and tostring(ws[4]) or nil
  ok(w4 ~= nil and Ctl._row_letter[w4] == "s", "后面的行仍然要落账（不是被清空就断了）")
  print("  [PASS] 读不到就不写（残值护栏）")
end

--------------------------------------------------------------------------------
-- 3. ★ 三层读法都要通：自有 .text / FindChild(槽位名) / 子孙兜底
--------------------------------------------------------------------------------
do
  local c = UIC.new(Core.new(lv), { skip_intro = true })
  local c_own = ctrl("letter", { text = "Z" })
  local c_sub = ctrl("letter", { kids = { ctrl("letter", { text = "Y" }) } })
  local c_deep_inner = ctrl("deep", { text = "X" })
  local c_deep_mid = ctrl("inner", { kids = { c_deep_inner } })
  local c_deep = ctrl("letter", { kids = { c_deep_mid } })
  local c_none = ctrl("letter", { kids = {} })
  ok(c:_read_control_text(c_own, "letter") == "Z",
    "① 自有 `.text` 要读得到")
  ok(c:_read_control_text(c_sub, "letter") == "Y",
    "② `FindChild(槽位名)` 要读得到")
  ok(c:_read_control_text(c_deep, "letter") == "X",
    "③ 子孙兜底要读得到")
  ok(c:_read_control_text(c_none, "letter") == nil,
    "④ 三条路都空 ⇒ 必须返回 nil（不许编一个值出来）")
  print("  [PASS] 三层读法 + 全空返回 nil")
end

--------------------------------------------------------------------------------
print(string.format("\nrow_letter_map: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
