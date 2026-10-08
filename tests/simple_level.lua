--[[----------------------------------------------------------------------------
  tests/simple_level.lua —— `levels/simple.lua`（直白摆放表）的自检

  为什么需要它：这个模块是"用户只写 `board`，其余自动派生"的**唯一入口** ✓
  派生错一格，整关就错了 —— 而错法是**静默**的（关卡照样能加载 ✓）✗
  ⇒ 所以这里把"派生出来的东西"逐项钉住 ✓

  跑法：lua tests/simple_level.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/simple_level.lua"
local root = here:gsub("tests[/\\]simple_level%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end
package.path = root .. "?.lua;" .. root .. "lua/?.lua;" .. package.path

local pass, fail = 0, 0
local function ok(cond, label, detail)
  if cond then pass = pass + 1 print("  [PASS] " .. label .. (detail and ("   " .. tostring(detail)) or ""))
  else fail = fail + 1 print("  [FAIL] " .. label .. (detail and ("   " .. tostring(detail)) or "")) end
end

local S = require("levels.simple")

print("== 1. demo：只写 board，其余派生 ==")
local lv = S.demo()
ok(lv.id == "demo_simple", "id 透传", lv.id)
ok(lv.size and lv.size.rows == 4 and lv.size.cols == 4, "size 派生自 rows/cols",
  lv.size and (lv.size.rows .. "×" .. lv.size.cols))
ok(lv.board == nil, "`board` 是输入格式，**不进引擎**", tostring(lv.board))

print("\n== 2. solution 直接来自 board ==")
ok(lv.solution.D and lv.solution.D.r == 1 and lv.solution.D.c == 2, "D → (1,2)",
  lv.solution.D and (lv.solution.D.r .. "," .. lv.solution.D.c))
ok(lv.solution.V and lv.solution.V.r == 4 and lv.solution.V.c == 3, "V → (4,3)",
  lv.solution.V and (lv.solution.V.r .. "," .. lv.solution.V.c))
local n = 0
for _ in pairs(lv.solution) do n = n + 1 end
ok(n == 4, "solution 恰好 4 个人", n)

print("\n== 3. suspects 从 board 派生、名字来自 people ==")
ok(#lv.suspects == 4, "suspects 4 条", #lv.suspects)
local by = {}
for i = 1, #lv.suspects do by[lv.suspects[i].id] = lv.suspects[i] end
ok(by.A and by.A.name == "值班保安", "A 的名字来自 people", by.A and by.A.name)
ok(by.V and by.V.is_victim == true, "V 被标成受害者", by.V and tostring(by.V.is_victim))
ok(by.D and by.D.is_victim ~= true, "D 不是受害者")
ok(by.D and by.D.portrait == "portrait.D", "头像名缺省 = portrait.<id>", by.D and by.D.portrait)

print("\n== 4. 受害者与盗窃者 ==")
ok(lv.victim and lv.victim.id == "V", "victim 派生", lv.victim and lv.victim.id)
ok(lv.roles and lv.roles.thief == "D", "roles.thief 透传", lv.roles and lv.roles.thief)

print("\n== 5. 线索：没写就自动生成位置型（只是起点）==")
ok(type(lv.clues) == "table" and #lv.clues == 8, "4 人 × 2 条 = 8 条", #lv.clues)
local kinds = {}
for i = 1, #lv.clues do kinds[lv.clues[i].type] = true end
ok(kinds.in_row and kinds.in_col, "只有 in_row / in_col", (kinds.in_row and "in_row " or "") .. (kinds.in_col and "in_col" or ""))

print("\n== 6. 只给行、且只剩一个空列 ⇒ 自动推（真能推的情形）==")
-- ⚠️ 我第一版这里写错了 ✗：只给一个人一行、而 4 列全空 ⇒ **本就该报错** ✓
--    那是第 7 节的用例 ✓ 第 6 节要测的是"**确实只剩一个空列**"时能推对 ✓
local lv6 = S.expand {
  id = "t_one", name = "只剩一列",
  rows = 3, cols = 3,
  board = {
    { r = 1, c = 1, who = "D" },
    { r = 2, c = 2, who = "A" },
    { r = 3, who = "B" },            -- 只剩第 3 列 ⇒ 应推成 c=3
  },
}
ok(lv6.solution.B and lv6.solution.B.c == 3, "B 被推到第 3 列", lv6.solution.B and lv6.solution.B.c)

print("\n== 7. 推不出来时必须报错，不许瞎填 ==")
local okc, err = pcall(S.expand, {
  id = "t_amb", name = "歧义",
  rows = 4, cols = 4,
  board = {
    { r = 1, who = "D" },
    { r = 2, who = "A" },
  },
})
ok(okc == false, "两个人都只给行 ⇒ 报错", tostring(err):sub(1, 46))
ok(tostring(err):find("推不出来", 1, true) ~= nil, "错误信息说清了原因", tostring(err):sub(1, 60))

print("\n== 8. 极端：一个人一行、全空 ⇒ 也必须报错 ==")
local oke, erre = pcall(S.expand, {
  id = "t_all", name = "全歧义", rows = 4, cols = 4,
  board = { { r = 1, who = "D" } },
})
ok(oke == false, "全空列 ⇒ 报错（不许瞎填第 1 列）", tostring(erre):sub(1, 46))

print("\n== 9. 同一人写两次必须报错 ==")
local okd, errd = pcall(S.expand, {
  id = "t_dup", name = "重复", rows = 3, cols = 3,
  board = { { r = 1, c = 1, who = "D" }, { r = 2, c = 2, who = "D" } },
})
ok(okd == false, "重复的人 ⇒ 报错", tostring(errd):sub(1, 50))

print("\n== 10. 引擎那边的接口没变（旧写法不受影响）==")
local core = require("murdoku_core")
ok(type(core) == "table", "murdoku_core 仍能加载")
local c1 = require("levels.case_001")
ok(c1.solution and c1.solution.D and c1.solution.D.r == 1, "旧写法 case_001 一个字没动",
  c1.solution and (c1.solution.D.r .. "," .. c1.solution.D.c))

print(string.format("\n结果：%d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
