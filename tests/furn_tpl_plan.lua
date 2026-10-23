--[[----------------------------------------------------------------------------
  tests/furn_tpl_plan.lua —— ★「家具模板键必须进规划」的回归断言（v319）

  真机症状（日志_2026/10/23_20:08:47，构建 v318）：
    家具一件都不出现；`家具模板映射：things 找到=true 条目=8` 全对、`模板化家具：关卡=true` 也有，
    却**一条 `家具模板：cell=…` 都没有** —— 适配层从没收到模板键。

  根因（本条用例就是它的守卫）：
    `furn_tpl / furn_span / furn_offset` 三个表原来声明在 `build_layout` 内部的 `do ... end` 里，
    而格子节点是在那个 `do` 之外 push 的 ⇒ push 处这三个名字解析成**全局 nil**
    ⇒ 每格都下发 `false` ⇒ 家具永远不实例化 ✗（Lua 不报错，只静默变全局）

  钉三件事：
    ① 规划的格子节点里 `furn_tpl` 非 false 的个数 == 该关家具件数（FurnArt.layout 算出来的）
    ② 每个有模板键的格子都同时有 `furn_span` 与 `furn_offset`（适配层摆位要用）
    ③ 抽查两关各一个已知锚点（改关卡数据时这里会红，是提醒不是噪音）

  跑法：lua tests/furn_tpl_plan.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = HERE .. "/../lua/?.lua;" .. HERE .. "/../?.lua;" .. package.path

local Core   = require("murdoku_core")
local UIC    = require("ui_controller")
local Levels = require("levels.init")
local FurnArt = require("furn_art")

-- 万能假适配器：build_layout 只用它查调色板，返回 nil 即可
local stub = setmetatable({}, { __index = function() return function() return nil end end })

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

local function plan_of(level_id)
  local lv = Levels.get(level_id)
  if lv == nil then return nil, nil end
  local core = Core.new(lv)
  local c = UIC.new(core, { levels = Levels.ui_list() })
  c.opts = c.opts or {}
  c.opts.current_level = level_id
  c.screen = nil
  local nodes = c:build_layout(stub)

  -- 期望件数：用同一条链自己算（object_key_of → FurnArt.layout）
  local vm = core:view()
  local keys = {}
  for r = 1, vm.rows do
    keys[r] = {}
    for cc = 1, vm.cols do keys[r][cc] = UIC.Controller.object_key_of(vm, vm.cells[r][cc]) or false end
  end
  local art = FurnArt.layout(vm, keys, lv.room_names)
  return nodes, art.pieces or {}
end

-------------------------------------------------------------------------------
-- ① / ② 逐关：模板键个数 == 件数；span / offset 配套
-------------------------------------------------------------------------------
for _, id in ipairs({ "case_001", "case_002" }) do
  local nodes, pieces = plan_of(id)
  if nodes == nil then
    ok(false, id .. "：取不到关卡（levels.init 没注册？）")
  else
    local cells, n_tpl, n_bad = {}, 0, 0
    for _, n in ipairs(nodes) do
      if type(n.id) == "string" and n.id:match("^cell%.") then
        cells[#cells + 1] = n
        if n.furn_tpl and n.furn_tpl ~= false then
          n_tpl = n_tpl + 1
          if (n.furn_span == nil or n.furn_span == false) or (n.furn_offset == nil or n.furn_offset == false) then
            n_bad = n_bad + 1
          end
        end
      end
    end
    ok(n_tpl == #pieces,
      string.format("%s：格子节点里 furn_tpl 非 false 的个数 %d == 家具件数 %d", id, n_tpl, #pieces))
    ok(n_tpl > 0, id .. "：家具模板键不能是 0（= 又变成全局 nil 了）")
    ok(n_bad == 0, id .. "：每个有模板键的格子都必须同时有 furn_span / furn_offset（异常 " .. n_bad .. " 个）")
  end
end

-------------------------------------------------------------------------------
-- ③ 抽查已知锚点（第一关 1,2 是植物；第二关 6,2 是书架）
-------------------------------------------------------------------------------
do
  local nodes = plan_of("case_001")
  local hit = nil
  for _, n in ipairs(nodes or {}) do if n.id == "cell.1.2" then hit = n end end
  ok(hit ~= nil and hit.furn_tpl == "furn.plant",
    "case_001 cell.1.2 应是 furn.plant（实测 " .. tostring(hit and hit.furn_tpl) .. "）")
end
do
  local nodes = plan_of("case_002")
  local hit = nil
  for _, n in ipairs(nodes or {}) do if n.id == "cell.6.2" then hit = n end end
  ok(hit ~= nil and hit.furn_tpl == "furn.shelf",
    "case_002 cell.6.2 应是 furn.shelf（实测 " .. tostring(hit and hit.furn_tpl) .. "）")
end

print(string.format("\nfurn_tpl_plan: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
