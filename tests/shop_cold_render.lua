-- 输入是待测 .gil 中提取的原始 Lua。使用包内控制器、关卡和离线适配器。
assert(load(io.read('*a'), '@archive.lua'))()
local levels = require('levels.init')
local level = assert(levels.all()[1])
local core = assert(require('murdoku_core').new(level))
local ui = require('ui_controller').new(core, {
  screen='home', levels=levels.ui_list(), current_level=level.id,
  wallet=function() return 12, 1, '', nil, 0 end
})
local adapter = require('engine_adapter').new_stub()
-- 预制控件在界面退出后仍在画布上，保留最后一次下发的可见性。
local handles = {}
function adapter:find(id)
  if not handles[id] then handles[id] = {} end
  return handles[id]
end
function adapter:destroy_control(id) self.input_handlers[id] = nil end
local writes = 0
local set = adapter.set_property
function adapter:set_property(id, key, value)
  writes = writes + 1
  set(self, id, key, value)
  return true
end
local function visible(id)
  local p = adapter.props[id]
  return p and p.visible
end
local function render(page, modal)
  ui.screen, ui.modal = page, modal
  ui:render(adapter, true)
end
render('home') -- 首次 render 会遍历其它页面，再隐藏不属于首页的控件。
assert(ui.screen == 'home' and ui._shown)
assert(visible('econ.shop736.s0') == false)
for i=1,3 do assert(visible('result.title.'..i) == false) end
local cold = writes
render('select')
render('shop')
assert(visible('econ.shop736.s0') == true)
for _, item in ipairs({'clue','position'}) do
  ui.econ_pick = item
  ui.shop_confirm = true
  render('shop')
  assert(visible('econ.shop736.hit.yes') and visible('econ.shop736.hit.leave') == false)
  ui.shop_confirm = false
  render('shop')
  assert(visible('econ.shop736.hit.yes') == false and visible('econ.shop736.hit.leave'))
end
render('bag')
assert(visible('econ.shop736.s0') == false)
for i, outcome in ipairs({'perfect','success','fail'}) do
  render(nil, {kind='result', win=i<3, outcome=outcome, message='测试'})
  for j=1,3 do assert(visible('result.title.'..j) == (i==j)) end
end
render('home')
for i=1,3 do assert(visible('result.title.'..i) == false) end
assert(visible('econ.shop736.s0') == false)
print(('COLD=%d WRITES=%d'):format(cold,writes))
