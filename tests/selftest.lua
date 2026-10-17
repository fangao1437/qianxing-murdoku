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
local Level    = require("tests.fixtures").clue_level_5x5()

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

-- ★★ 2026-10-13 **过时断言的口径** ✗✓（★ 与项目已有的"本环境测不了"同一套 ✓）
--
--   ★ 为什么需要它 ✗：★ 有些断言测的**功能已被用户明确删除** ✓
--     （★ 例：两步式指认面板 —— ★ 用户原话「确认嫌疑人和同伙那两步我不要，删掉」✓）
--     ⇒ ★ 那种断言**永远不可能再绿** ✗
--     ★★ 但如果让它一直红 ✗ ⇒ ★ 常驻套件里就常驻一条**假红** ✓
--       ⇒ ★ 把真红的信噪比拉低 ✓ ★ 本项目为此栽过不止一次 ✓
--     ★ 也不能直接删掉 ✗ —— ★ 那就把"这里**曾经**有条断言、以及**为什么**没了"一起丢了 ✓
--   ⇒ ★★ 所以记成 `⊘ 已删功能` ✓：★ **不伪装通过** ✗ ★ **也不谎报失败** ✗ ✓
--   ⚠️ ★ 判断标准要严 ✗：★ 只有当**功能真的被删**才用它 ✓
--     ★ 若只是"这条断言写错了" ⇒ ★ **该改断言** ✓（★ 见 §10 ✓ 本文件两种都用了 ✓）
local skipped = 0
local function skip(name, why)
  skipped = skipped + 1
  print(string.format("  [⊘ 已删功能] %s —— %s", name, why))
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

print("== 4. ★ 同伙规则【已废止】（2026-10-18）==")
-- 旧断言（已被规则变更取代）：
--   check("k>=2 时删掉同伙会报错", ...) ／ check("报错信息指向同伙规则", ...)
-- 现在：k 取任何值都不再要求同伙；只有关卡自己在 roles 里声明了 accomplice 才存在同伙。
local s2, e2, i2 = core:structure_report({ thief = "D", accomplice = nil, victim = "V" })
check("k>=2 时没有同伙【不再报错】", s2 == true, e2 and table.concat(e2, "; ") or "")
check("k 仍然被正确数出来", i2 ~= nil and i2.k >= 2, i2 and tostring(i2.k) or "nil")
check("info.has_accomplice 反映传进来的 roles（本例无同伙 ⇒ false）",
      i2 ~= nil and i2.has_accomplice == false, i2 and tostring(i2.has_accomplice) or "nil")
-- 同伙即便被摆到别的区域，也不再报"不在同一个区域"（该条已废止）
local s3, e3 = core:structure_report({ thief = "D", accomplice = "C", victim = "V" })
check("同伙不再被要求与盗窃者同区（本条已废止）",
      (e3 == nil) or (table.concat(e3, "; "):find("不在同一个区域") == nil),
      e3 and table.concat(e3, "; ") or "")

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

print("== 7. ★ 求解器（已搬到设计期工具 tools/design_solve.lua）==")
-- ★★ 2026-10-18：求解器**不再在运行时核心里**（用户要求）。
--   本套件仍然测它，但改成显式 require 那份设计期工具 —— 顺带证明"搬出去之后还能用"。
local Solve = require("tools.design_solve")
check("运行时核心【没有】solve（求解器已移出运行时代码）", Core.solve == nil,
      type(Core.solve))
local sols = Solve.solve(core, 3)
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
-- ★★★★★ 2026-10-05 **这条断言过时了 —— 已按设计反转** ✗✓（用户明确授权修这一条 ✓）
--
--   原来：`check("区域推断面板已创建", stub.controls["hud.violations"] ~= nil)` ✗
--   为什么过时：那个面板**是按参考布局图【故意删掉】的** ✓ 不是漏建 ✗ ——
--     见 `lua/ui_controller.lua:1737`：
--       「★ 删除（参考图里没有）：`action.reveal` 揭示 / `hud.score` / `hud.violations`」
--     以及 `:2419`「它是给 `hud.violations` 用的，没有控件就不必算」✓
--   ⇒ **代码是对的** ✓ 老断言在要求一个**已被设计删掉**的控件 ✗
--
--   ⚠️ **这不是放宽断言** ✗ —— 是**把它反转成更有防线价值的那种** ✓：
--     现在断言「它**确实不在**计划里」⇒ 万一有人又把它加回来 ⇒ **测试立刻红** ✓✓
--     （老写法只能证明"建出来了" ✓ 新写法能守住"按参考图删掉了" ✓）
check("区域推断面板**按参考图删除**（不该再出现）", stub.controls["hud.violations"] == nil,
      tostring(stub.controls["hud.violations"]))
check("告知“有一句假话”显示在副标题", stub.props["hud.subtitle"] ~= nil)

core:reset()
ctrl:on_input({ action = "suspect", id = "A" })
check("头像被选中", core.selected == "A", tostring(core.selected))

-- ★★ 2026-09-29 改：单击**立即生效**，不再"挂起等双击窗口"。
--
--   旧流程（本断言原来编码的）：单击先挂起 0.35 秒，过了窗口才落成笔记。
--   用户报「没选标记按钮、直接单击棋盘做 ✗ 有明显延迟」后改成：
--   **第一击立即生效**；若真来了第二击，先撤销第一击再做预放置。
--   （本工程反复出现的教训：**断言里不要锁死"实现细节"，要锁"用户可感知的行为"**——
--     旧断言锁的是"挂起"这个内部机制，机制一改就红，而用户要的"点了马上有反应"
--     反而从来没被断言过。）
ctrl:on_input({ action = "click", r = 1, c = 2 })
check("单击**立即**生效（不再挂起等双击窗口）",
      core.notes[1][2]["A"] == true and core.grid[1][2] == nil,
      "notes=" .. tostring(core.notes[1][2]["A"]))
ctrl:tick(0.5)
check("等待之后笔记仍在（没有被延迟处理覆盖）", core.notes[1][2]["A"] == true)
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
-- ★★★★★★★★ 2026-10-15 **判据反转（★ 机制改了，不是放宽 ✓ P8 ✓）** ✗✓✓
--
--   ★★★ 原来这里断言 ✓：★「**拿起后自动选中该角色**」⇒ `core.selected == "A"` ✓
--   ★★ 而那条语义**正是用户报的 bug 的根** ✗ —— ★ 用户原话 ✓：
--     「**取消操作确实捆绑选中，也就是我取消 a 放置的同时又重新选了 a，
--       把取消放置和选中的联系切断就行**」✓✓
--   ★ 后果 ✓（★ 与用户报的第一句**逐字对上** ✓）：
--     ★ 放 V ⇒ 选 D ⇒ **拿起 V** ⇒ ★ 那一行把选中从 D 改成 V ✓
--       ⇒ ★ **屏幕还亮着 D** ✗ ★ **再长按放的是 V** ✓✓
--   ⇒ ★★ 现在 ✓：★ **拿起就只是拿起，选中保持不变** ✓
--     ★ 判据 ✓：★ 上面"长按=正式放置后清空选中" ⇒ 拿起之前 `selected` 是 **nil** ✓
--       ⇒ ★ 拿起之后**仍然是 nil** ✓✓
--   ★ 与「正式放置后取消选中」的区别 ✓（★ 那条**保留** ✓）：
--     ★ 放置 = 定案 ⇒ 取消选中合理 ✓　★ 拿起 = 撤回 ⇒ **不该顺手改选中** ✓✓
--   ⚠️ ★ **不许**把这条删掉或放宽 ✗ —— ★ 它现在守的是**新契约** ✓
check("拿起**不改动**选中（★ 取消放置与选中已解耦 ✓）", core.selected == nil,
      tostring(core.selected))
check("拿起后「已正式放置」标记也清掉（否则该角色会被永久禁止打笔记）",
      core.placed == nil or core.placed["A"] == nil,
      tostring(core.placed and core.placed["A"]))

print("== 10. 提交 → **提交通过即结算**（★ 两步式指认面板已删 ✓）==")
-- ★★★★★★ 2026-10-13 **本节按现行设计重写** ✗✓（★ 用户指令 ✓）
--
--   ★ 用户原话 ✓：「**确认嫌疑人和同伙那两步我不要，删掉**」✓
--     ＋ 选项确认：「**提交通过即结算**」✓
--   ★ 依据（★ 代码实证 ✓）：`ui_controller.lua` 的 `do_submit()` ——
--     ★ `res.ok` ⇒ **直接** `finish_accuse(roles.thief, …)` ✓
--     ⇒ ★★ `accuse_thief` / `accuse_accomplice` **再也不会打开** ✓✓
--   ★★ 而**结案判定一个字没动** ✓：★ 仍走 `finish_accuse` ⇒ `Core:accuse_verdict` ✓
--     ⇒ ★ 所以 §8 那三条**判定函数**的断言**照旧有效、照旧绿** ✓（★ 见 105/107/110 ✓）
--
--   ⚠️ 本节原先有 4 条断言，性质**不一样** ✗✓（★ 两种处理 ✓）：
--     · ★「提交后弹出"谁是盗窃者"」✗「选了盗窃者后追问同伙」✗
--       「说没有同伙 → 不成立且关闭弹窗」✗
--       ⇒ ★★ **测的是已删的两个面板** ⇒ ★ **过时** ✓ ⇒ 记 `⊘ 已删功能` ✓
--     · ★「指认 D + 同伙 C → 破案」⇒ ★ 它测的是 `status == SOLVED` ✓
--       ★ 而**那条路仍然存在** ✓（★ 只是入口从"点面板"变成"提交即结算"✓）
--       ⇒ ★★ **不是过时，是入口写错了** ✗ ⇒ ★ **该改断言** ✓✓
--
--   ★ 另一处要一起拉齐 ✓：★ 提交在现行设计里是**两段确认** ✓ ——
--     ★ `submit` 只做 `self.pending = { action = "submit" }` ＋ `sync_confirm()` ✓
--     ⇒ ★ 只发 `submit` 时 **`modal` 不是"指认面板"、而是"确认弹窗"** ✓
--     ⇒ ★ 必须补一次 `confirm_yes` 才真的 `do_submit()` ✓
place_answer(core)
ctrl:on_input({ action = "submit" })
ctrl:on_input({ action = "confirm_yes" })

-- ★★ 核心新契约：★ **提交通过 ⇒ 直接结算，且【不开】任何指认面板** ✓
check("提交通过 ⇒ 直接结算（status=SOLVED）",
      core.status == Core.STATUS_SOLVED, tostring(core.status))
check("★ 两步式指认面板**不再打开**（modal 不是 accuse_thief/accomplice）",
      ctrl.modal == nil
        or (ctrl.modal.kind ~= "accuse_thief" and ctrl.modal.kind ~= "accuse_accomplice"),
      ctrl.modal and ctrl.modal.kind)
check("结算走的是 finish_accuse ⇒ Core:accuse_verdict（判定逻辑未绕开）",
      core:accuse_verdict("D", true, "C").solved == true)

-- ★ 那三条测已删面板的断言 ⇒ 明确记成"已删功能"（★ 不伪装通过、也不谎报失败 ✓）
skip("提交后弹出“谁是盗窃者”", "两步式指认已按用户指令删除（`ui_controller:do_submit` 改为提交即结算）")
skip("选了盗窃者后追问同伙", "同上：`accuse_accomplice` 面板已不存在")
skip("说没有同伙 → 不成立且关闭弹窗", "同上：该面板不存在 ⇒ 这条界面路径无从触发；"
  .. "「说没有同伙 ⇒ 不成立」的判定本身仍由 §8 的 `accuse_verdict(..., false, nil)` 覆盖 ✓")

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
-- ★ 2026-10-13：★ **把 `⊘ 已删功能` 也报出来** ✗✓ —— ★ 与 `play_test.mjs` 的
--   "⊘ 本环境测不了"**同一口径** ✓：★ 它**不算通过** ✗ ★ 但也**不是失败** ✓
--   ★ 报出来才看得见"有几条已经不再测任何东西" ✓（★ 藏起来就等于悄悄少测 ✓）
if skipped > 0 then
  print(string.format("⊘ 另有 %d 条**测的是已删功能**（不算通过 ✓ 也不是失败 ✓）"
    .. " —— 本行出现即说明有断言在测已被用户删掉的界面路径", skipped))
end
if fail > 0 then os.exit(1) end
