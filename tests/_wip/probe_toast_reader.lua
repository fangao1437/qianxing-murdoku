--[[----------------------------------------------------------------------------
  tests/_wip/probe_toast_reader.lua —— ★ A8 的**方向性**离线探针：到底有没有人在【读】`self.toast`？

  背景（2026-10-05 实测，证据见 docs/L3基线-模拟器四步失败清单.md §8）：
    · `lua/ui_controller.lua` 里 `self.toast` 有 **10 处写入**（8 处是真消息 · 2 处清空），
      而**一个读它的地方都没有** ✗ ⇒ 玩家看不到任何提示：
      「撤销没反馈 ✗ 取消没反馈 ✗ 揭示没反馈 ✗ 还没有游玩记录 ✗ 商城/背包点了没反应 ✗」。
    · `hud.toast` 这个控件**不在计划里、也不在存档里**
      （实测 `208-补active.gil` 里 `hud.toast` 记录 **0 条**；有计划的那几个 `hud.*` 各 1 条）
      ⇒ 用户批准的**方案甲** = **接一个已存在的出口控件**，一个控件都不加、布局一行不动。

  本探针只判「有没有读者」这一件事，判据**全部来自适配器真收到的属性**
  （`stub.props[id].text` / `.visible` —— 即 `_set_prop` → `set_property` 那条现成通路的结果）。

    [A] `confirm_no`（点 ✗ 取消）会写 toast「已取消」⇒ 出口控件 `hud.subtitle` 收到的
        `text` 里必须出现这句话                      ← ★ **改之前必红**（根本没有读者）
    [B] `tick` 推 1.0 秒（< 超时时长）⇒ 提示语**还在**（不许一闪而过 ✗）
    [C] `tick` 推过超时时长 ⇒ `self.toast` **被清空**、出口文字**变回副标题**（不留残字 ✗）
                                                     ← ★ **改之前必红**（没人清它）
    [D] 第二条路 `reveal`（「已揭示答案」）同样送达 ✓
    [E] 主页出口 `home.title`：「商城 / 背包」是在**主页**点的，而主页上整片 `hud.` 前缀
        被 `apply_screen_hide` 藏掉 ⇒ 那两条提示在主页上只能走 `home.title`
                                                     ← ★ **改之前必红**

  跑法（★ 纯离线：不跑模拟器 `tools/sim/*`、不需要引擎 ✓）：
    lua tests/_wip/probe_toast_reader.lua
    lua tests/_wip/probe_toast_reader.lua <另一份 ui_controller.lua>   # 量「改之前」那一份（对照）
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tests/_wip/probe_toast_reader.lua"
local root = here:gsub("tests[/\\]_wip[/\\]probe_toast_reader%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end

package.path = table.concat({
  package.path,
  root .. "lua/?.lua",
  root .. "lua/?/init.lua",
  root .. "?.lua",
}, ";")

-- ★ 可选参数：拿**同一份断言**去量"改之前"那一份 `ui_controller.lua`（对照实验，
--   和 tests/prop_ledger.lua 用命令行换产物是同一个思路）。
--   ⚠️ 只把这个文件所在的目录**前置**到 package.path —— 其余模块（core / levels）照旧从仓库读。
local OVERRIDE = arg and arg[1] or nil
if OVERRIDE ~= nil then
  local dir = OVERRIDE:match("^(.*)[/\\][^/\\]*$") or "."
  package.path = dir .. "/?.lua;" .. package.path
end

local Core = require("murdoku_core")
local UIC  = require("ui_controller")
local Adapters = require("engine_adapter")
local Level = require("levels.case_001")

local out = print
local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    out("  [PASS] " .. name .. (extra and ("   -> " .. tostring(extra)) or ""))
  else
    fail = fail + 1
    out("  [FAIL] " .. name .. (extra and ("   -> " .. tostring(extra)) or ""))
  end
end

-- 出口控件上**实际收到**的属性（= `set_property` 的结果，不是脚本内部字段 ✓）
local stub
local function prop(id, key)
  local p = stub.props[id]
  return p and p[key] or nil
end
local function text_of(id) return prop(id, "text") end
local function has(s, sub) return type(s) == "string" and s:find(sub, 1, true) ~= nil end

-- 超时时长：从模块读（一处定义）；万一量的是"改之前"那一份（没有这个常量）就用规格值 2.5
local TOAST_S = tonumber(UIC.TOAST_SECONDS) or 2.5

out("==================================================================")
out(" probe_toast_reader —— A8：self.toast 有没有【读者】？")
out(" 量的脚本： " .. tostring(package.searchpath and package.searchpath("ui_controller", package.path) or "ui_controller"))
out(" 超时时长： " .. tostring(TOAST_S) .. " 秒（UIC.TOAST_SECONDS=" .. tostring(UIC.TOAST_SECONDS) .. "）")
out("==================================================================")

local core = assert(Core.new(Level))
stub = Adapters.new_stub()
local c = UIC.new(core, { skip_intro = true })
c:render(stub, true)

------------------------------------------------------------------------------
out("")
out("== 0. 前置 ==")
local subtitle0 = text_of("hud.subtitle")
check("出口控件 hud.subtitle 收到了文字（它确实在计划里 ✓ 真机存档里也有这条记录 ✓）",
  type(subtitle0) == "string" and #subtitle0 > 0, tostring(subtitle0))
check("此刻没有提示语（core.toast == nil）", c.toast == nil, tostring(c.toast))
check("此刻出口上没有「已取消」", not has(subtitle0, "已取消"), tostring(subtitle0))
check("没有新建 `hud.toast` 控件（方案甲 = 不加控件 ✓）", stub.controls["hud.toast"] == nil)

------------------------------------------------------------------------------
out("")
out("== 1. ★ A：写了一个 toast ⇒ 出口控件上要看得到（改之前必红）==")
c:on_input({ action = "confirm_no" })            -- 点 ✓/✗ 里的 ✗ = 取消
check("写入点没被改过：self.toast == 「已取消」", c.toast == "已取消", tostring(c.toast))
c:render(stub)
local t_a = text_of("hud.subtitle")
check("★★ 出口控件 hud.subtitle 的 text 里出现了「已取消」（= 有人读它了 ✓）",
  has(t_a, "已取消"), tostring(t_a))
check("出口控件被强制可见（visible == true）", prop("hud.subtitle", "visible") == true,
  tostring(prop("hud.subtitle", "visible")))

------------------------------------------------------------------------------
out("")
out("== 2. B：超时【之前】不许消失 ==")
c:tick(0.5)
c:tick(0.5)                                       -- 共 1.0s < TOAST_S
check("1.0 秒之后 self.toast 还在（不许秒消失 ✗）", c.toast == "已取消", tostring(c.toast))
c:render(stub)
check("1.0 秒之后出口上仍然是它", has(text_of("hud.subtitle"), "已取消"), tostring(text_of("hud.subtitle")))

------------------------------------------------------------------------------
out("")
out("== 3. ★ C：超过超时时长 ⇒ 清空 + 文字复原（改之前必红）==")
c:tick(TOAST_S - 1.0 + 0.2)                       -- 总计 TOAST_S + 0.2 秒 ⇒ 越过截止时刻
check("★ 超过 " .. TOAST_S .. " 秒 ⇒ self.toast 被清空", c.toast == nil, tostring(c.toast))
c:render(stub)
local t_c = text_of("hud.subtitle")
check("★ 出口文字变回副标题本身（不留残字 ✗）", t_c == subtitle0, tostring(t_c))

------------------------------------------------------------------------------
out("")
out("== 4. D：第二条路（reveal）也走同一个出口 ==")
c:on_input({ action = "reveal" })
check("reveal 写了「已揭示答案」", c.toast == "已揭示答案", tostring(c.toast))
c:render(stub)
check("★ 出口上出现「已揭示答案」", has(text_of("hud.subtitle"), "已揭示答案"),
  tostring(text_of("hud.subtitle")))

------------------------------------------------------------------------------
out("")
out("== 5. ★ E：主页的出口 = `home.title`（「商城 / 背包」是在主页点的）==")
-- 5a：★ 附带性质 —— 提示语是**跨屏**的（它不属于某一个屏幕，过期前走到哪一屏就显示在哪一屏）。
--     第 4 节那条「已揭示答案」现在还是活的 ⇒ 切到主页后，主页出口上应该就是它。
c:on_input({ action = "home" })                   -- 回主页（= 点「返回主页」那条路）
c:render(stub)
check("提示语跨屏：第 4 节那条还活着 ⇒ 主页出口上就是「已揭示答案」",
  text_of("home.title") == "已揭示答案", tostring(text_of("home.title")))

-- 5b：让它自然过期 ⇒ 主页出口必须变回主页标题本身
c:tick(TOAST_S + 0.2)
c:render(stub)
check("过期后回主页：home.title 显示的是主页标题", text_of("home.title") == UIC.HOME_TITLE,
  tostring(text_of("home.title")))
check("主页上 hud.subtitle 上也没有「商城」残留（`hud.` 在主页整片被藏 ✓ 所以主页要有第二个出口）",
  not has(text_of("hud.subtitle"), "商城"), tostring(text_of("hud.subtitle")))

c:on_input({ action = "shop" })
check("shop 写了提示语", has(c.toast, "商城"), tostring(c.toast))
c:render(stub)
check("★★ 主页出口 home.title 的 text 里出现了「商城：美术资源就绪后开放」",
  has(text_of("home.title"), "商城"), tostring(text_of("home.title")))

c:tick(TOAST_S + 0.2)
c:render(stub)
check("主页提示语到点也收（变回主页标题）", text_of("home.title") == UIC.HOME_TITLE,
  tostring(text_of("home.title")))

------------------------------------------------------------------------------
out("")
out(string.format("════════ 结果：%d 通过 / %d 失败 ════════", pass, fail))
os.exit(fail == 0 and 0 or 1)
