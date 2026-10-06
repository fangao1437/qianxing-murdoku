-- [[----------------------------------------------------------------------------
--   tests/_wip/probe_suspect_entry.lua —— ★★ 证明"选人入口"真的接上了（**离线** ✓）
--
--   ★ 背景（第三轮第 3 项的真因 ✓ 见 `docs/点格子没反应-三段切开结论.md` ✓）：
--     症状是「点格子没反应」= `0 / 5` ✓ 三段切开后 A/B/C **全通** ✓
--     ⇒ ★ 真因是**进入 C 的前置条件不满足**：`core.selected` 恒为 nil ✗
--     ⇒ 因为★【全界面没有任何控件发 `suspect` 事件】✗（计划里实测 `suspect` = **0** ✓）
--     ⇒ `Core:pre_place` 直接返回「先点一个头像」✗ ⇒ 棋盘永远空 ✓
--   ★ 修法（提交 `91aee0d` ✓）：让 `clue.<i>.face`（线索卡上的头像 ✓ 现在全屏唯一的头像 ✓）
--     带 `event = { action = "suspect", id = wid }` ✓
--
--   ★ 本探针【有方向】✓ —— **改前红 / 改后绿** ✓，不是"怎么都过"的空断言 ✓：
--     ① 计划里 `action == "suspect"` 的节点数 **必须 > 0** ✓（改前是 **0** ✗）
--     ② 每个 suspect 事件的 `id` **必须是真角色 id** ✓（不能是空串/数字 ✓）
--     ③ ★ 走**真控制器**发 `{action="suspect", id=…}` ⇒ `core.selected` **必须被设上** ✓
--     ④ ★★ 然后**点两次格子** ⇒ **必须放置成功** ✓✓（= 端到端 ✓ 这一条就是 `13/13` 那条红 ✓）
--     ⑤ 负对照：发一个**不存在**的 id ⇒ `selected` **不许被设上** ✓（判据能红 ✓）
--
--   跑法：`lua tests/_wip/probe_suspect_entry.lua`
--   ★ 边界：★ 本探针**不证明**真机光标命中 ✓ 也不证明模拟器里点得到 ✓
--           —— 它只证明【脚本内部的选人→放置链路】是通的 ✓（见 §8.9 ✓）
--  ----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "tests/_wip"
local root = HERE .. "/../.."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local lv   = require("levels.case_001")

local passed, failed = 0, 0
local function ok(cond, msg, extra)
  if cond then
    passed = passed + 1
    print("  [PASS] " .. msg)
  else
    failed = failed + 1
    print("  [FAIL] " .. msg .. (extra and ("   -> " .. tostring(extra)) or ""))
  end
end
local function placed(core)
  local n = 0
  for _, p in pairs(core.pos or {}) do if p ~= nil then n = n + 1 end end
  return n
end

--------------------------------------------------------------------------------
print("== ① 计划里到底有没有 suspect 事件（改前 = 0 ✗）==")
local plan_path = root .. "/tools/sim/out/layout-plan.json"
local f = io.open(plan_path, "r")
if f == nil then
  print("  [SKIP] 没找到 " .. plan_path .. "（先跑 `lua tools/dump_layout.lua`）")
else
  local raw = f:read("*a"); f:close()
  -- ★★★★★ 2026-10-06 **计数修正：不能数两遍** ✗✓
  --   旧写法 `gmatch('"action"%s*:%s*"suspect"')` ✗ 会**同时命中两处** ✓：
  --     · 规划节点自己的 `"action": "suspect"` ✗（★ 节点级别的 action ✓）
  --     · 以及它里面 `"event": { "action": "suspect" }` ✗（★ 控件真正派发的那个 ✓）
  --   ⇒ ★ 17 个头像被数成 **34** ✗ ⇒ 断言 `n_suspect == n_face` **恒红** ✓
  --     （★ 真机/探针日志原话：`34 vs 17` ✓ —— 这已经是**老问题**了 ✓）
  --   ⇒ ★★ 修法：★ **只数 `event` 里那一份** ✓ —— 它才是"按钮点了会发什么" ✓
  --     ★ 另把总数也打出来便于对照 ✓ 但**不**参与相等断言 ✓
  local n_suspect = 0
  for _ in raw:gmatch('"event"%s*:%s*{%s*"action"%s*:%s*"suspect"') do n_suspect = n_suspect + 1 end
  local n_action_all = 0
  for _ in raw:gmatch('"action"%s*:%s*"suspect"') do n_action_all = n_action_all + 1 end
  local n_face = 0
  for _ in raw:gmatch('"id"%s*:%s*"clue%.[0-9]+%.face"') do n_face = n_face + 1 end
  print(string.format("  计划：suspect 事件 %d 个（节点级共 %d 个）· clue.*.face 节点 %d 个",
    n_suspect, n_action_all, n_face))
  ok(n_suspect > 0, "★★ 计划里有 suspect 事件（改前是 0 ✗ ⇒ 这是红→绿的关键判据）", "实测 " .. n_suspect)
  ok(n_suspect == n_face, "★ suspect 事件数与 clue.*.face 节点数一致（每个头像一个 ✓）",
     string.format("%d vs %d", n_suspect, n_face))
  -- ★ id 不能是空串
  local empty_id = 0
  for _ in raw:gmatch('"event"%s*:%s*{%s*"action"%s*:%s*"suspect"%s*,%s*"id"%s*:%s*""') do empty_id = empty_id + 1 end
  ok(empty_id == 0, "★ suspect 事件的 id 没有空串（`:1889` 同口径：有值才给 ✓）", "空串 " .. empty_id .. " 个")
end

--------------------------------------------------------------------------------
print("\n== ② 走【真控制器】发 suspect ⇒ core.selected 必须被设上 ==")
local core, errs = Core.new(lv)
if core == nil then print("  [FAIL] 关卡建不起来：" .. tostring(errs and errs[1])); os.exit(1) end
local c = UIC.new(core, { skip_intro = true })

-- 找关卡里的真嫌疑人 id（用 core.solution 的键 ✓ 那是权威答案表 ✓）
local ids = {}
for id in pairs(core.solution or {}) do ids[#ids + 1] = tostring(id) end
table.sort(ids)
print("  本关嫌疑人：" .. table.concat(ids, ", "))

core:reset()
ok(core.selected == nil, "起点：没选任何人（`core.selected == nil` ✓）", tostring(core.selected))

local first = ids[1]
c:on_input({ action = "suspect", id = first })
ok(core.selected == first, "★ 发 `{action=suspect, id=" .. first .. "}` ⇒ `selected` 被设上",
   tostring(core.selected))

-- ⑤ 负对照：不存在的 id ⇒ 不许被设上（判据能红 ✓）
core:reset()
c:on_input({ action = "suspect", id = "___no_such_suspect___" })
ok(core.selected == nil, "★ 负对照：发不存在的 id ⇒ `selected` 不被设上（判据能红 ✓）",
   tostring(core.selected))

--------------------------------------------------------------------------------
print("\n== ③ ★★ 端到端：选人 ⇒ 点两次格子 ⇒ 必须放置（= 13/13 那条红 ✓）==")
core:reset()
local before = placed(core)
c:on_input({ action = "suspect", id = first })          -- ★ 选人（修复前这一步做不到 ✓）
ok(core.selected == first, "先选中 " .. first, tostring(core.selected))
c:on_input({ action = "click", r = 2, c = 2, phase = "click" })
c:on_input({ action = "click", r = 2, c = 2, phase = "click" })
local after = placed(core)
print(string.format("  放置数 %d -> %d（grid[2][2]=%s moves=%s）",
  before, after, tostring(core.grid and core.grid[2] and core.grid[2][2]),
  tostring(core.hud and core.hud.moves)))
ok(after == before + 1, "★★ 选人之后双击 ⇒ **放置成功**（全链路通了 ✓✓）",
   "放置数 " .. before .. " -> " .. after)

--------------------------------------------------------------------------------
print("\n== ④ 反证：不选人直接点 ⇒ 不该放置（这才是修前的样子 ✓）==")
core:reset()
local b2 = placed(core)
c:on_input({ action = "click", r = 3, c = 3, phase = "click" })
c:on_input({ action = "click", r = 3, c = 3, phase = "click" })
ok(placed(core) == b2, "★ 没选人 ⇒ 双击**不放置**（与实测 `0/5` 一致 ✓）", "放置数 " .. b2)

print(string.format("\n════════ 结果：%d 通过 / %d 失败 ════════", passed, failed))
os.exit(failed == 0 and 0 or 1)
