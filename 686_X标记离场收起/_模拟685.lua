
local ctrls = {}
for r = 1, 8 do for c = 1, 8 do
  local base = "art685.mark." .. r .. "." .. c
  for _, nm in ipairs({base, base..".stroke.0", base..".stroke.1"}) do
    ctrls[nm] = { name=nm, visible=false,
      SetVisible=function(self,v) self.visible = (v == true) end }
  end
end end
local Adapter = {}
Adapter.__index = Adapter
function Adapter:find(n) return ctrls[n] end
function Adapter:_mark_set_visible(rc, on)
  local base = "art685.mark." .. rc
  local names = { base, base .. ".stroke.0", base .. ".stroke.1" }
  for i = 1, #names do
    local c = self:find(names[i])
    if c ~= nil and c.SetVisible then pcall(function() c:SetVisible(on) end) end
  end
end

local a = setmetatable({}, Adapter)
local LIT = { "2.2", "2.4", "4.1", "5.5" }
local function shown()
  local n = 0
  for r = 1, 8 do for c = 1, 8 do
    local base = "art685.mark." .. r .. "." .. c
    for _, nm in ipairs({base, base..".stroke.0", base..".stroke.1"}) do
      if ctrls[nm].visible then n = n + 1 end
    end
  end end
  return n
end
-- 关卡内：点亮 4 组 X
for i = 1, #LIT do a:_mark_set_visible(LIT[i], true) end
local in_level_shown = shown()
-- 离开关卡：等价于 visible_stage / hide_unlisted 钩子调用 _mark_hide_all()
-- 685 无 _mark_hide_all，也无门控：父容器隐藏不级联
local after_leave = shown()
-- 切屏瞬间抢先下发 x_mark=true
a:_mark_set_visible("3.3", true)
local after_race = shown()
print(string.format('%d %d %d', in_level_shown, after_leave, after_race))
