
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
function Adapter:_mark_all_ctrls()
  if self._mark_ctl_cache ~= nil then return self._mark_ctl_cache end
  local t = {}
  for r = 1, 8 do
    for c = 1, 8 do
      local base = "art685.mark." .. r .. "." .. c
      local names = { base, base .. ".stroke.0", base .. ".stroke.1" }
      for i = 1, #names do
        local q = self:find(names[i])
        if q ~= nil then t[#t + 1] = q end
      end
    end
  end
  if #t >= 192 then self._mark_ctl_cache = t end   -- 控件树未就绪时不缓存，下次重建
  return t
end

function Adapter:_mark_hide_all()
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    local q = t[i]
    if q.SetVisible ~= nil then pcall(function() q:SetVisible(false) end) end
  end
  self._mark_screen_on = false
end

function Adapter:_mark_set_visible(rc, on)
  -- ★ 686：关卡外一律不点亮（防止切屏瞬间 x_mark 抢先下发把 X 又打开）
  if on == true and self._mark_screen_on == false then on = false end
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
a:_mark_hide_all()
local after_leave = shown()
-- 切屏瞬间抢先下发 x_mark=true
a:_mark_set_visible("3.3", true)
local after_race = shown()
print(string.format('%d %d %d', in_level_shown, after_leave, after_race))
