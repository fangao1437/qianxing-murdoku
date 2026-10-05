-- [[----------------------------------------------------------------------------
--   tests/_wip/probe_click_path.lua —— ★ 判 B 段 vs C 段（**不占模拟器** ✓）
--
--   背景：`13/13 probe_cursor` 唯一红「双击放置生效」`0 / 5` ✗（`8/13` #2–#8 #13 同类 ✓）
--   ★ 已确凿两层：
--     ① 格子点击**没带 `r`/`c`** ✗ ⇒ 已在 `_fire` 里补（提交 `6f04c64` ✓ 离线探针过 ✓）
--     ② `action` vs `event` 字段名不对上 ✗ ⇒ `node.event` 恒 nil ⇒ `live_event()` 静默回落
--        `{action="click"}` ✓（★ 对格子而言**恰好是对的** ✓）
--   ★ 而 `tests/input_logic.lua`（**39/0** ✓）已证明 **C 段（逻辑）是好的** ✓：
--     它直接调 `on_cell_down/up` ⇒ 长按能放置 ✓ 越界/抖动/时长不够都不放置 ✓
--     ⚠️ 但它**直接调 `on_cell_down/up`** ✗ —— **绕过了 `on_input`** ✗
--
--   ⇒ ★★ 本探针补的正是那个缺口：**走 `on_input({action="click", …})`** ✓
--     （= 模拟器那次点击**理论上**走到的入口 ✓ 见 `ui_controller.lua:776` → `:818` → `:562`）
--
--   ★ 判定：
--     · **放置数 = 1** ✓ ⇒ ★ B 段（路由）与 C 段（逻辑）**都通** ⇒ 断点在 **A 段（事件层）** ✗✓
--     · **放置数 = 0** ✗ ⇒ ★ 断点在 **B 段**（`on_input` 的 click 分支 / `_suppress_click` / 双击窗口 ✗）
--   ★ 跑法：`lua tests/_wip/probe_click_path.lua`
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

local function placed_count(core)
  local n = 0
  for _, p in pairs(core.pos or {}) do if p ~= nil then n = n + 1 end end
  return n
end

local function new_controller()
  local core, errs = Core.new(lv)
  if core == nil then
    print("  [FAIL] 关卡建不起来：" .. tostring(errs and errs[1]))
    failed = failed + 1
    return nil, nil
  end
  return core, UIC.new(core, { skip_intro = true })
end

--------------------------------------------------------------------------------
print("== 0. 前置：选一个嫌疑人（放置的前提 ✓）==")
local core, c = new_controller()
if core == nil then os.exit(1) end
core:select_suspect("A")
ok(core.selected == "A", "选中了 A（`core.selected` ✓）", core.selected)

--------------------------------------------------------------------------------
print("\n== 1. ★ C 段对照：直接调 on_cell_click（绕开 on_input）==")
-- ★ 这一次是**对照组**：证明"控制器 + 核心"本身能放置 ✓
--   （`input_logic.lua` 已用 on_cell_down/up 证过 ✓ 这里用 click 的入口再证一次 ✓）
core:reset(); core:select_suspect("A")
local before = placed_count(core)
c:on_cell_click(3, 1)
c:on_cell_click(3, 1)          -- 双击窗口内 ⇒ 放置 ✓
local after = placed_count(core)
ok(after == before + 1, "★ 直接调 on_cell_click 两次 ⇒ 放置成功（C 段好的 ✓）",
   "放置数 " .. before .. " -> " .. after)

--------------------------------------------------------------------------------
print("\n== 2. ★★ B 段实测：走 on_input({action='click', …})（= 模拟器那条路的入口 ✓）==")
core:reset(); core:select_suspect("A")
local b0 = placed_count(core)
c:on_input({ action = "click", r = 3, c = 1, phase = "click" })
c:on_input({ action = "click", r = 3, c = 1, phase = "click" })
local b1 = placed_count(core)
print(string.format("  放置数 %d -> %d   (_suppress_click=%s  now=%.3f)",
  b0, b1, tostring(c._suppress_click), tonumber(c.now) or -1))
ok(b1 == b0 + 1, "★★ 走 on_input 的 click 两次 ⇒ 放置成功（B 段也通 ✓）", "放置数 " .. b0 .. " -> " .. b1)

--------------------------------------------------------------------------------
print("\n== 3. ★ 两个嫌疑各测一次 ==")
-- 3a：`r`/`c` 为 nil（= 修复前的样子 ✗）⇒ 应当**不放置**（且不该崩 ✓）
core:reset(); core:select_suspect("A")
local n0 = placed_count(core)
local okc = pcall(function()
  c:on_input({ action = "click", phase = "click" })          -- r/c 全 nil ✗
  c:on_input({ action = "click", phase = "click" })
end)
print("  r/c 为 nil 时：pcall ok=" .. tostring(okc) .. "  放置数=" .. placed_count(core))
ok(okc == true, "r/c 为 nil **不该崩**（pcall 应成功 ✓）")
ok(placed_count(core) == n0, "r/c 为 nil ⇒ **不放置** ✓（= 修复前的症状 ✓）")

-- 3b：两次点击的模拟时间间隔 —— 试推进 tick 让 now 前进 ✓
core:reset(); core:select_suspect("A")
local t0 = placed_count(core)
c:on_input({ action = "click", r = 2, c = 2, phase = "click" })
c:tick(0.05)                                                  -- 推进 0.05s ✓ < 0.35 ✓
c:on_input({ action = "click", r = 2, c = 2, phase = "click" })
print(string.format("  间隔 0.05s（窗口内 ✓）：放置数 %d -> %d  now=%.3f",
  t0, placed_count(core), tonumber(c.now) or -1))
ok(placed_count(core) == t0 + 1, "★ 间隔 0.05s（< 0.35s 窗口）⇒ 算双击 ⇒ 放置 ✓")

core:reset(); core:select_suspect("A")
local s0 = placed_count(core)
c:on_input({ action = "click", r = 4, c = 4, phase = "click" })
c:tick(0.50)                                                  -- 推进 0.50s ✗ > 0.35 ✗
c:on_input({ action = "click", r = 4, c = 4, phase = "click" })
print(string.format("  间隔 0.50s（窗口外 ✗）：放置数 %d -> %d",
  s0, placed_count(core)))
ok(placed_count(core) == s0, "★ 间隔 0.50s（> 0.35s 窗口）⇒ **不算双击** ⇒ 不放置 ✓（两次单击=两次笔记 ✓）")

--------------------------------------------------------------------------------
print(string.format("\n════════ 结果：%d 通过 / %d 失败 ════════", passed, failed))
os.exit(failed == 0 and 0 or 1)
