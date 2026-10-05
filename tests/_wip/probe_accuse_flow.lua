--[[----------------------------------------------------------------------------
  tests/_wip/probe_accuse_flow.lua —— 只读探针：两段式指认的**真实通路** + 结算弹窗里没有分享按钮

  跑法：
    lua tests/_wip/probe_accuse_flow.lua              -- 用本仓库 lua/
    lua tests/_wip/probe_accuse_flow.lua <别的root>   -- 用别的 root（用来对改前的版本跑出"红"）

  它证明什么（2026-10-05，用户指令「补 accuse_thief，去掉分享」）：
    ① `accuse_thief` 有分发分支了 ⇒ 点了嫌疑人，状态真的推进到"问同伙"，且 `modal.thief` 记下了是谁；
    ② 第二阶段真的把被指认者从名单里排除（`modal.suspect.D` 不在计划里）；
    ③ 接着发 `accuse_pick_accomplice` ⇒ 能一路走到**破案**（`core.status == SOLVED`）；
    ④ 结算弹窗的计划里**没有** `modal.share` 节点（「分享棋局」按钮已删）。
    ⑤ 反向保险：`reveal` 不再顺手弹出"那同伙是谁？"（这是老 bug 的第二个后果）。

  ⚠️ 按 `tests/_wip/README.md` 的规矩：`_wip` 里的东西**不算回归防线、也不算常备证据**。
     本探针的定位是**这一次改动的证据** —— 能红能绿：对**改前**的 `ui_controller.lua`
     跑会红（①③④都挂），对改后的跑才绿。跑完请连同结论一起看，不要把它当成长期断言。
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/probe_accuse_flow.lua"
local root = (arg and arg[1]) or here:gsub("tests[/\\]_wip[/\\][^/\\]*$", "")
-- 显式传进来的 root 可能是 "C:\...\repo"（结尾没有分隔符）⇒ 补一个，否则会拼成
-- "...repolua/murdoku_core.lua" 那种找不到模块的路径（第一次跑就踩了这个）。
if root ~= "" and not root:match("[/\\]$") then root = root .. "/" end

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

-- 把答案摆上棋盘（与 tests/selftest.lua 同一手法）
local function place_answer(core)
  core:reset()
  for id, p in pairs(core.solution) do
    core:select_suspect(id)
    core:hold_cell(p.r, p.c)
  end
end

-- 取 `build_layout()` 计划里的全部 id（**只读**：不动任何状态）
local function plan_ids(ctrl)
  local ids, n = {}, 0
  for _, node in ipairs(ctrl:build_layout()) do
    ids[node.id] = true
    n = n + 1
  end
  return ids, n
end

-- ── 真实通路：摆满 → 提交 → ✓ → 谁是盗窃者 → 同伙 → 破案 ────────────────────
print("== 1. 两段式指认的真实通路 ==")
local core = assert(Core.new(Level))
local ctrl = UIC.new(core, { skip_intro = true })
place_answer(core)

ctrl:on_input({ action = "submit" })
ctrl:on_input({ action = "confirm_yes" })   -- ★ 提交现在要 ✓ 确认（✓/✗ 状态机，2026-10-02 定稿）
check("提交 + ✓ 之后弹出「谁是盗窃者？」",
      ctrl.modal ~= nil and ctrl.modal.kind == "accuse_thief",
      ctrl.modal and ctrl.modal.kind)

local ids, n0 = plan_ids(ctrl)
check("第一阶段计划里**有**全部嫌疑人按钮（含 D）",
      ids["modal.suspect.D"] == true and n0 > 0,
      "节点 " .. tostring(n0) .. " 个")

-- ★ 核心：这一发就是弹窗里点嫌疑人卡发出的那条事件
ctrl:on_input({ action = "accuse_thief", id = "D" })
check("★ 发 `accuse_thief(id=D)` ⇒ 状态推进到「问同伙」",
      ctrl.modal ~= nil and ctrl.modal.kind == "accuse_accomplice",
      ctrl.modal and ctrl.modal.kind)
check("★ `modal.thief == D`（被指认的人被记下来了）",
      ctrl.modal ~= nil and ctrl.modal.thief == "D",
      ctrl.modal and tostring(ctrl.modal.thief))

ids = plan_ids(ctrl)
check("第二阶段计划里**排除了 D**（同伙名单不该出现盗窃者本人）",
      ids["modal.suspect.D"] == nil and ids["modal.suspect.C"] == true,
      "D=" .. tostring(ids["modal.suspect.D"]) .. " C=" .. tostring(ids["modal.suspect.C"]))
check("第二阶段有「他独自作案（没有同伙）」按钮", ids["modal.no_accomplice"] == true)

ctrl:on_input({ action = "accuse_pick_accomplice", id = "C" })
check("★ 发 `accuse_pick_accomplice(id=C)` ⇒ **破案**（core.status == SOLVED）",
      core.status == Core.STATUS_SOLVED, tostring(core.status))
check("结算弹窗出现且是「赢」的那份",
      ctrl.modal ~= nil and ctrl.modal.kind == "result" and ctrl.modal.win == true,
      ctrl.modal and tostring(ctrl.modal.kind))

-- ── 结算弹窗：分享按钮必须消失，again / next 必须还在 ────────────────────────
print("== 2. 结算弹窗的计划（分享按钮已删）==")
ids, n0 = plan_ids(ctrl)
check("★ 结算计划里**没有** `modal.share` 节点",
      ids["modal.share"] == nil, "modal.share=" .. tostring(ids["modal.share"]))
check("`modal.again` 还在（删按钮没有误伤邻居）", ids["modal.again"] == true)
check("`modal.next` 还在（删按钮没有误伤邻居）", ids["modal.next"] == true)
check("结算弹窗的标题/正文/统计还在",
      ids["modal.title"] == true and ids["modal.body"] == true and ids["modal.stats"] == true,
      "节点 " .. tostring(n0) .. " 个")

-- 渲染层再确认一次（假引擎）：没有建出 modal.share 控件
local stub = Adapters.new_stub()
ctrl:render(stub, true)
check("渲染层也没有建出 `modal.share` 控件", stub.controls["modal.share"] == nil)
check("渲染层确实建出了 `modal.next`（证明上一条不是「什么都没建」）",
      stub.controls["modal.next"] ~= nil)

-- ── 反向保险：reveal 不再弹出"那同伙是谁？"（老 bug 的第二个后果）────────────
print("== 3. 反向保险：reveal 的副作用已消失 ==")
local core3 = assert(Core.new(Level))
local ctrl3 = UIC.new(core3, { skip_intro = true })
place_answer(core3)
ctrl3:on_input({ action = "reveal" })
check("★ 「揭示答案」**不再**顺手弹出「那同伙是谁？」",
      ctrl3.modal == nil or ctrl3.modal.kind ~= "accuse_accomplice",
      ctrl3.modal and ctrl3.modal.kind)

-- ── 规格对照：说"没有同伙"仍然不成立（selftest 的行为规格）──────────────────
print("== 4. 规格对照：指认 D 但说没有同伙 ==")
place_answer(core)
ctrl:on_input({ action = "submit" })
ctrl:on_input({ action = "confirm_yes" })
ctrl:on_input({ action = "accuse_thief", id = "D" })
ctrl:on_input({ action = "accuse_no_accomplice" })
check("说不存在同伙 ⇒ 不成立、且弹窗关闭（status == FAILED）",
      core.status == Core.STATUS_FAILED and ctrl.modal == nil,
      tostring(core.status) .. " / modal=" .. tostring(ctrl.modal and ctrl.modal.kind))

print("")
print(string.format("探针结果：%d 通过 / %d 失败", pass, fail))
if fail > 0 then os.exit(1) end
