--[[----------------------------------------------------------------------------
  tests/_wip/_key_stability_probe.lua —— 临时量尺：**计划节点键跨状态稳不稳**。

  为什么必须先量这个（只读，不改任何东西）：
    本轮要把「事件」也按计划节点的键（`id \1 父容器 \1 序号`）分槽存。
    分槽之后，**绑定的那条监听**要按"当初认领这条控件的那个键"去查事件 ——
    如果同一个 id 的键在不同屏幕/弹窗状态之间**会变**（父容器换了、或同一父容器下
    出现次数变了），那么"绑定时记下的键"就会指向一个过期槽 ✗。

  判据：对每个 id，把它在 10 个状态里的键集合收集起来，看是否**只有一种**。

  跑法：lua tests/_wip/_key_stability_probe.lua
----------------------------------------------------------------------------]]--]]

local here = (arg and arg[0]) or "tests/_wip/_key_stability_probe.lua"
local root = here:gsub("tests[/\\]_wip[/\\]_key_stability_probe%.lua$", "")
if root == "" then root = "./" end
if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")
local UIC = require("ui_controller")
local Levels = require("levels.init")

local STATES = {
  { name = "home",              intro = 99, modal = nil,                            screen = "home" },
  { name = "select",            intro = 99, modal = nil,                            screen = "select" },
  { name = "intro",             intro = 1,  modal = nil,                            screen = nil },
  { name = "board",             intro = 99, modal = nil,                            screen = nil },
  { name = "accuse_thief",      intro = 99, modal = { kind = "accuse_thief" },      screen = nil },
  { name = "accuse_accomplice", intro = 99, modal = { kind = "accuse_accomplice" }, screen = nil },
  { name = "result",            intro = 99, modal = { kind = "result", win = true, message = "x" }, screen = nil },
  { name = "share",             intro = 99, modal = { kind = "share", code = "x" }, screen = nil },
  { name = "howto",             intro = 99, modal = { kind = "howto" },             screen = nil },
  { name = "levelselect",       intro = 99, modal = { kind = "levelselect" },       screen = nil },
}

local all = Levels.all()
-- id -> key -> { 状态名 }
local per_id = {}
-- 只关心"带事件的节点"（事件分槽只服务它们）
local ev_ids = {}
local n_nodes, n_ev_nodes = 0, 0

for li = 1, #all do
  local lv = all[li]
  local core = Core.new(lv)
  local ctl = UIC.new(core, {})
  for si = 1, #STATES do
    local st = STATES[si]
    ctl.intro_page = st.intro
    ctl.modal = st.modal
    ctl.screen = st.screen
    local ok, nodes = pcall(function() return ctl:build_layout() end)
    if not ok then
      print("  [" .. st.name .. "] build_layout 抛错：" .. tostring(nodes))
    else
      local seq = {}
      for i = 1, #nodes do
        local n = nodes[i]
        local base = tostring(n.id) .. "\1" .. tostring(n.parent)
        seq[base] = (seq[base] or 0) + 1
        local key = base .. "\1" .. tostring(seq[base])   -- 与 render 的 node_key 同一格式
        per_id[n.id] = per_id[n.id] or {}
        per_id[n.id][key] = per_id[n.id][key] or {}
        per_id[n.id][key][st.name] = true
        n_nodes = n_nodes + 1
        if n.event ~= nil then
          ev_ids[n.id] = true
          n_ev_nodes = n_ev_nodes + 1
        end
      end
    end
  end
end

print("=== 计划节点键的跨状态稳定性（" .. tostring(#all) .. " 关 × " .. tostring(#STATES) .. " 状态）===")
print(string.format("节点 %d 个，其中带 event 的 %d 个", n_nodes, n_ev_nodes))

local unstable = {}
for id, keys in pairs(per_id) do
  local n = 0
  for _ in pairs(keys) do n = n + 1 end
  if n > 1 then
    unstable[#unstable + 1] = { id = id, keys = keys, n = n }
  end
end
table.sort(unstable, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)

if #unstable == 0 then
  print("★ 每个 id 的键集合**跨全部状态只有一种**（按节点分槽是安全的）")
else
  print("⚠️ 有 " .. tostring(#unstable) .. " 个 id 的键**跨状态会变**：")
  for i = 1, #unstable do
    local u = unstable[i]
    print("  · `" .. u.id .. "` 共 " .. tostring(u.n) .. " 种键" .. (ev_ids[u.id] and "  ← **带 event**" or ""))
    local list = {}
    for k, sts in pairs(u.keys) do
      local s = {}
      for sname in pairs(sts) do s[#s + 1] = sname end
      table.sort(s)
      list[#list + 1] = string.format("      %s   （状态：%s）", k:gsub("\1", " | "), table.concat(s, ","))
    end
    table.sort(list)
    for j = 1, #list do print(list[j]) end
  end
end
