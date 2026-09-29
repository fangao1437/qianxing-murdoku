--[[----------------------------------------------------------------------------
  tests/selftest.lua —— 离线自检（偷窃版 v0.3）：不需要游戏、不需要任何引擎 API

  跑法（桌面 Lua 5.4）：
    lua tests/selftest.lua
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/selftest.lua"
local root = here:gsub("tests[/\\]selftest%.lua$", "")
package.path = table.concat({
  package.path,
  root .. "lua/?.lua",
  root .. "lua/?/init.lua",
  root .. "?.lua",
}, ";")

local Core     = require("murdoku_core")
local UIC      = require("ui_controller")
local Adapters = require("engine_adapter")
local Level    = require("levels.demo_selftest")

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print(string.format("  [PASS] %s", name))
  else
    fail = fail + 1
    print(string.format("  [FAIL] %s %s", name, extra and ("-> " .. tostring(extra)) or ""))
  end
end

-- 把答案摆上棋盘
local function place_answer(core)
  core:reset()
  for id, p in pairs(core.solution) do
    core:select_suspect(id)
    core:hold_cell(p.r, p.c)
  end
end

print("== 1. 关卡校验（含偷窃版新字段）==")
local ok, errors = Core.validate_level(Level)
check("关卡格式合法", ok, errors and table.concat(errors, "; "))

print("== 2. 区域与门径 ==")
local core = assert(Core.new(Level))
local vm0 = core:view()
check("门径被解析到格边上", vm0.cells[3][1].doors.down == true, "h(3,1) 应有门")
check("门径也被解析到另一侧", vm0.cells[4][3].doors.right == true, "v(4,3) 应有门")
check("无门处没有门", vm0.cells[1][1].doors.right == false)
check("区域相邻图按门生成", (core.adjacency[core.room[4][1]] or {})[core.room[1][1]] == true)

print("== 3. 结构约束 R3 / R4（在正确答案上）==")
place_answer(core)
local sok, serrs, sinfo = core:structure_report()
check("答案满足结构约束", sok, serrs and table.concat(serrs, "; "))
check("受害者区域内 k=2", sinfo.k == 2, tostring(sinfo.k))
check("受害者区域有 2 个门相邻区域", #sinfo.adjacent == 2, #sinfo.adjacent)
check("盗窃者区域是无辜最多的相邻区域", sinfo.thief_room == sinfo.best_rooms[1],
      string.format("thief_room=%s best=%s", tostring(sinfo.thief_room), tostring(sinfo.best_rooms[1])))
check("无辜人数 1 > 0（无并列）", sinfo.best == 1 and #sinfo.best_rooms == 1,
      tostring(sinfo.best))

print("== 4. 同伙存在性（R4 叠加）==")
local s2, e2 = core:structure_report({ thief = "D", accomplice = nil, victim = "V" })
check("k>=2 时删掉同伙会报错", s2 == false, e2 and table.concat(e2, "; "))
check("报错信息指向同伙规则", (e2 and table.concat(e2, "; "):find("同伙") ~= nil))

print("== 5. 假话规则（至多一句，粒度=整条）==")
local res = core:clue_results()
local failed_idx = {}
for i = 1, #res do
  if not res[i].satisfied then failed_idx[#failed_idx + 1] = i end
end
check("答案上恰好 1 条线索不成立", #failed_idx == 1, #failed_idx)
check("不成立的正是声明的那条（第 7 条）", failed_idx[1] == Level.meta.false_clue,
      tostring(failed_idx[1]))
check("引擎的允许假话条数为 1", core.allowed_false == 1)
check("线上告知策略为 one", core.meta.announce == "one")

print("== 6. 角色别名线索 ==")
local alias_text = nil
for i = 1, #res do
  if res[i].text:find("盗窃者") then alias_text = res[i].text end
end
check("引用 @thief 的线索渲染成“盗窃者”", alias_text ~= nil, alias_text)
local isrole = Core.clues["is_role"]
check("身份线索已注册", isrole ~= nil)

print("== 7. 求解器（摆位 × 角色归属 + 假话容错）==")
local sols = core:solve(3)
check("唯一解", #sols == 1, "#sols=" .. tostring(#sols))
if sols[1] then
  check("解出盗窃者 = D", sols[1].thief == "D", tostring(sols[1].thief))
  check("解出同伙 = C", sols[1].accomplice == "C", tostring(sols[1].accomplice))
end

print("== 8. 提交（不剧透）与指认（两段式）==")
place_answer(core)
local sub = core:submit()
check("摆满后提交通过", sub.ok, sub.message)
check("提交结果不揭晓线索对错", sub.reveal == false and sub.message:find("线索") == nil, sub.message)

check("指认 D + 有同伙 C → 破案", core:accuse_verdict("D", true, "C").solved == true)
place_answer(core)
local wrong1 = core:accuse_verdict("D", false, nil)
check("指认 D 但说没有同伙 → 不成立", wrong1.solved == false, wrong1.message)
place_answer(core)
local wrong2 = core:accuse_verdict("C", true, "D")
check("指认同伙当盗窃者 → 不成立", wrong2.solved == false, wrong2.message)
check("失败原因里点出盗窃者认错", wrong2.message:find("盗窃者") ~= nil, wrong2.message)

print("== 9. 操作框架：单击=笔记 / 双击=放置 ==")
place_answer(core)
local stub = Adapters.new_stub()
local ctrl = UIC.new(core, { skip_intro = true })
ctrl:render(stub, true)
check("棋盘格控件已创建", stub.controls["cell.1.1"] ~= nil)
check("区域推断面板已创建", stub.controls["hud.violations"] ~= nil)
check("告知“有一句假话”显示在副标题", stub.props["hud.subtitle"] ~= nil)

core:reset()
ctrl:on_input({ action = "suspect", id = "A" })
check("头像被选中", core.selected == "A", tostring(core.selected))

-- 单击：先挂起，等过了双击窗口才落成铅笔笔记
ctrl:on_input({ action = "click", r = 1, c = 2 })
check("单击先挂起（不立刻写笔记）", core.notes[1][2]["A"] == nil)
ctrl:tick(0.5)
check("单击落成铅笔笔记", core.notes[1][2]["A"] == true and core.grid[1][2] == nil)
check("写笔记不会清空选中", core.selected == "A", tostring(core.selected))

-- 双击同一格（间隔 0.1s < 窗口 0.35s）→ **预放置**（★ 2026-09-28 语义拆分）
--
-- 旧断言是「放置后清空选中」，但按新设计**双击只是预放置**：只标同行同列 ✗，
-- **不清笔记、不清选中**（那时还在试推，笔记是思考痕迹）。
-- 这里改成同时验证两种放置，比原来只测一种更严：
--   双击 → 预放置：选中留着
--   长按（走 do_place → core:hold_cell）→ 正式放置：清笔记 + 清选中
ctrl:on_input({ action = "click", r = 1, c = 1 })
ctrl:tick(0.1)
ctrl:on_input({ action = "click", r = 1, c = 1 })
check("双击才放置", core.grid[1][1] == "A", tostring(core.grid[1][1]))
check("双击=预放置（**不清空**选中）", core.selected == "A", tostring(core.selected))

-- 正式放置：换一格放（顺带验证"同一个人换位置 = 等效撤销后重放"）
ctrl:do_place(1, 3)
check("长按=正式放置后清空选中", core.selected == nil, tostring(core.selected))
check("正式放置把人挪到了新格（旧格已清）",
      core.grid[1][3] == "A" and core.grid[1][1] == nil,
      tostring(core.grid[1][1]) .. "/" .. tostring(core.grid[1][3]))

-- 单击已放置的格 = 立刻拿起（不需要等双击窗口）
-- （★ 2026-09-28：A 已被上面那条"正式放置"挪到了 (1,3)，所以这里点 (1,3)）
ctrl:on_input({ action = "click", r = 1, c = 3 })
check("单击已放置的格 = 拿起", core.grid[1][3] == nil, tostring(core.grid[1][3]))
check("拿起后自动选中该角色", core.selected == "A", tostring(core.selected))
check("拿起后「已正式放置」标记也清掉（否则该角色会被永久禁止打笔记）",
      core.placed == nil or core.placed["A"] == nil,
      tostring(core.placed and core.placed["A"]))

print("== 10. 提交 → 两段式指认的界面流程 ==")
place_answer(core)
ctrl:on_input({ action = "submit" })
check("提交后弹出“谁是盗窃者”", ctrl.modal and ctrl.modal.kind == "accuse_thief",
      ctrl.modal and ctrl.modal.kind)
ctrl:on_input({ action = "accuse_thief", id = "D" })
check("选了盗窃者后追问同伙", ctrl.modal and ctrl.modal.kind == "accuse_accomplice",
      ctrl.modal and ctrl.modal.kind)
ctrl:on_input({ action = "accuse_no_accomplice" })
check("说没有同伙 → 不成立且关闭弹窗", ctrl.modal == nil and core.status == Core.STATUS_FAILED)
place_answer(core)
ctrl:on_input({ action = "submit" })
ctrl:on_input({ action = "accuse_thief", id = "D" })
ctrl:on_input({ action = "accuse_pick_accomplice", id = "C" })
check("指认 D + 同伙 C → 破案", core.status == Core.STATUS_SOLVED)

print("== 11. X 标记 / 橡皮擦 / 撤销重做 ==")
core:reset()
core:select_suspect("B")
core:hold_cell(3, 2)
check("放置成功", core.grid[3][2] == "B")
ctrl:on_input({ action = "undo" })
check("撤销后为空", core.grid[3][2] == nil)
ctrl:on_input({ action = "redo" })
check("重做后恢复", core.grid[3][2] == "B")
ctrl:on_input({ action = "cell_right", r = 2, c = 1 })
check("X 标记写入", core.x_marks[2][1] == true)

-- ★ 2026-09-28 改：**「双击橡皮擦清空全盘」已从界面层移除**。
--
-- 原因：用户实测报「双击其中一个格子触发了全盘清空」。排查确认全盘清空只有那一条可达路径
--   （`gesture_rollback` 是死代码 —— 适配器从没发过 `gesture_begin`/`gesture_rollback`），
--   而它误触就毁掉整局 —— 收益（省一次点击）远小于风险。
--   「清空全盘」仍可通过「重开」（`action.restart`）做到，功能没丢。
--
-- 这里改成断言「**双击橡皮擦不再清空棋盘**」，把"不许再犯"钉进测试。
core:reset()
core:select_suspect("A"); core:hold_cell(1, 1)
ctrl:on_input({ action = "tool", mode = "eraser" })
ctrl:tick(0.1)
ctrl:on_input({ action = "tool", mode = "eraser" })
check("双击橡皮擦【不再】清空全盘（破坏性快捷键已移除）",
      core.grid[1][1] ~= nil and core.mode == "eraser",
      core.grid[1][1] == nil and "棋盘被清空了 —— 快捷键没删干净" or tostring(core.mode))

print("== 12. 分享码 / 存档往返 ==")
core:reset()
core:select_suspect("A"); core:hold_cell(5, 3)
core:select_suspect("V"); core:hold_cell(4, 1)
core:select_suspect("B"); core:tap_cell(3, 2)
-- (1,5) 是书桌所在格（occupiable=false）：顺便验证"不可站人"这条链路
check("书桌所在格不可站人", core:is_blocked(1, 5))
-- ★★ 2026-09-29 更正：这条断言原来编码的是**我写错的假设**
--   （原文：「不可站人的格子打不了 X」）。
--   用户实测报「R1C5 不能正常做 x 标记」后，语义改成正确的：
--   **`blocked` 只表示"不能站人"，✗ / 笔记是玩家的推理痕迹，任何格子都能打。**
check("不可站人的格子**能**打 X（✗ 与能否站人无关）", core:toggle_x(1, 5) == true)
core.x_marks[1][5] = false      -- 还原，免得影响后面的编码/解码断言
core:toggle_x(2, 4)
local code = core:encode_state()
local c2 = assert(Core.new(Level))
local dok = c2:decode_state(code)
check("分享码可解回", dok == true)
check("摆位还原", c2.grid[5][3] == "A" and c2.grid[4][1] == "V")
check("笔记还原", c2.notes[3][2] and c2.notes[3][2]["B"] == true)
check("X 还原", c2.x_marks[2][4] == true)
local blob = core:serialize()
local c3 = assert(Core.new(Level))
check("存档反序列化", c3:deserialize(blob) == true and c3.grid[5][3] == "A")

print("== 13. 新线索原子 in_front_of（门窗正对的两格）==")
local probe = {
  id = "probe_door", name = "probe", size = { rows = 2, cols = 2 },
  rules = { one_per_row = false, one_per_col = true, place_all = true, tie_policy = "allow" },
  walls = { { "v", 1, 1 }, { "v", 2, 1 } },   -- 左右两个区域
  doors = { { "v", 1, 1 } },                  -- (1,1) 与 (1,2) 之间有门
  suspects = { { id = "P" }, { id = "Q" } },
  roles = { thief = "P" },
  solution = { P = { r = 1, c = 1 }, Q = { r = 1, c = 2 } },
  clues = { { type = "in_front_of", a = "P", b = "Q" } },
}
local pc = assert(Core.new(probe))
pc:select_suspect("P"); pc:hold_cell(1, 1)
pc:select_suspect("Q"); pc:hold_cell(1, 2)
local pres = pc:clue_results()
check("门两侧的两格满足 in_front_of", pres[1].satisfied == true, pres[1].text)

print("")
print(string.format("结果：%d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
