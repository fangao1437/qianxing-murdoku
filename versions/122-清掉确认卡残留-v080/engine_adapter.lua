--[[----------------------------------------------------------------------------
  engine_adapter.lua —— 引擎适配层（接口 + 离线桩实现）

  这是整个工程唯一的「引擎边界」。上层（ui_controller / murdoku_core）不认识千星，
  下层（engine_adapter_qianxing.lua）才认识千星。7.1 的脚本 API 若与预期不同，
  只需要改 engine_adapter_qianxing.lua 一个文件。

  接口清单（适配层必须实现）
  ⚠️ 以下**全部是方法**：调用方必须用冒号语法 `adapter:method(...)`。
     用点号 `adapter.method(...)` 会把第一个实参当成 self —— 这个坑已经踩过一次
     （render 崩在 create_control：node 变成 nil）。
    log(msg)
    create_control(node)                 -- 按 node.id 幂等创建/复用控件
    destroy_control(id)
    set_property(id, key, value)         -- key: rect/text/image/style/visible/enabled/...
    play_effect(id, effect_name, params) -- 动画/特效，不支持可以空实现
    bind_input(id, event_table)          -- 声明该控件的点击回传事件
    now() -> seconds
    after(seconds, fn) -> handle         -- 定时器（补间/动画序列/计时用）
    cancel(handle)
    save(key, value) / load(key)         -- 局内存档
    signal_emit(name, payload)           -- 向节点图/服务器发信号
    signal_on(name, handler)             -- 收外部信号
    random_int(a, b)
----------------------------------------------------------------------------]]--

local M = {}
M.interface = {
  "log", "create_control", "destroy_control", "set_property", "play_effect",
  "bind_input", "now", "after", "cancel", "save", "load",
  "signal_emit", "signal_on", "random_int",
}

----------------------------------------------------------------------------
-- 离线桩：纯 Lua，可脱离游戏跑通整个操作框架
-- 用法：
--   local stub = require("engine_adapter").new_stub()
--   -- 桩会把 create_control/set_property 记录到 stub.log_lines，便于自检
----------------------------------------------------------------------------

local Stub = {}
Stub.__index = Stub

function M.new_stub(opts)
  opts = opts or {}
  local self = setmetatable({}, Stub)
  self.log_lines = {}
  self.controls = {}     -- id -> node
  self.props = {}        -- id -> {key=value}
  self.effects = {}
  self.input_handlers = {}  -- id -> event table
  self.timers = {}
  self.storage = {}
  self.signals = {}
  self.verbose = opts.verbose == true
  self.clock = 0
  return self
end

function Stub:log(msg)
  self.log_lines[#self.log_lines + 1] = tostring(msg)
  if self.verbose then print("[adapter] " .. tostring(msg)) end
  -- 最多留 2000 行，避免长时间运行爆内存
  if #self.log_lines > 2000 then table.remove(self.log_lines, 1) end
end

function Stub:create_control(node)
  local existed = self.controls[node.id]
  self.controls[node.id] = node
  if existed and existed ~= false then return end
  self.props[node.id] = self.props[node.id] or {}
  if node.event then self:bind_input(node.id, node.event) end
  self:log("create " .. node.id .. " (" .. tostring(node.kind) .. ")")
end

function Stub:destroy_control(id)
  self.controls[id] = false
  self.props[id] = nil
  self.input_handlers[id] = nil
  self:log("destroy " .. tostring(id))
end

function Stub:set_property(id, key, value)
  self.props[id] = self.props[id] or {}
  self.props[id][key] = value
end

function Stub:play_effect(id, effect_name, params)
  self.effects[#self.effects + 1] = { id = id, kind = effect_name, params = params }
  self:log(string.format("fx %s <- %s", tostring(effect_name), tostring(id)))
end

function Stub:bind_input(id, event_table)
  self.input_handlers[id] = event_table
  self:log("bind " .. tostring(id) .. " -> " .. tostring(event_table and event_table.action))
end

function Stub:now() return self.clock end

function Stub:after(seconds, fn)
  local h = { at = self.clock + (seconds or 0), fn = fn }
  self.timers[#self.timers + 1] = h
  return h
end

function Stub:cancel(handle)
  for i = 1, #self.timers do
    if self.timers[i] == handle then table.remove(self.timers, i) return true end
  end
  return false
end

-- 桩的“时间推进”，自检时手动调用
function Stub:advance(seconds)
  self.clock = self.clock + (seconds or 0)
  local due = {}
  for i = #self.timers, 1, -1 do
    if self.timers[i].at <= self.clock then
      due[#due + 1] = self.timers[i]
      table.remove(self.timers, i)
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
end

function Stub:save(key, value) self.storage[key] = value return true end
function Stub:load(key) return self.storage[key] end

function Stub:signal_emit(name, payload)
  self:log(string.format("signal_emit %s %s", tostring(name), tostring(payload)))
  local list = self.signals[name]
  if list then
    for i = 1, #list do list[i](payload) end
  end
end

function Stub:signal_on(name, handler)
  self.signals[name] = self.signals[name] or {}
  table.insert(self.signals[name], handler)
end

function Stub:random_int(a, b)
  a, b = a or 1, b or 1
  if b < a then a, b = b, a end
  return a + math.random(0, b - a)
end

-- 自检辅助：模拟点击某个控件
function Stub:click(id)
  local evt = self.input_handlers[id]
  if not evt then
    self:log("click " .. tostring(id) .. " (没有绑定事件)")
    return nil
  end
  return evt
end

return M
