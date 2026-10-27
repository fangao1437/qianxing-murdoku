--[[----------------------------------------------------------------------------
  lua/tutorial_ui.lua —— 13 页教程逐页静态复刻控制器（v352）

  设计稿中的所有文字、颜色、棋盘家具、墙门、棋子、候选和标记都已预建为：
    td.<tag>.page.<n>.*
  本模块只负责显隐与按钮，不写文字、不改颜色、不创建或销毁控件。
----------------------------------------------------------------------------]]--
local M = {}

function M.new(adapter, opts)
  if type(opts) ~= "table" then opts = {} end
  return setmetatable({
    adapter = adapter,
    tag = tostring(opts.tag or "?"),
    root_name = tostring(opts.root or ("td." .. tostring(opts.tag or "?"))),
    pages = tonumber(opts.pages) or 1,
    page = 1,
    open = false,
    inited = false,
    bound = {},
    log = {},
  }, { __index = M })
end

function M:_note(msg)
  self.log[#self.log + 1] = msg
  if print then print("[tutorial] " .. msg) end
end

function M:_find(name)
  local ctrl = nil
  pcall(function() ctrl = self.adapter:find(name) end)
  return ctrl
end

function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(function() ctrl:SetVisible(want and true or false) end)
  if want then pcall(function() ctrl:SetActive(true) end) end
  return true
end

function M:_bind(name, fn)
  local ctrl = self:_find(name)
  if ctrl == nil or self.bound[ctrl] then return ctrl ~= nil end
  if ctrl.AddCursorEventListener == nil then return false end
  self.bound[ctrl] = true
  local ok = pcall(function()
    local ev = Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick
    if ev == nil then error("CursorClick unavailable") end
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  return ok
end

function M:_paint()
  for i = 1, self.pages do
    self:_visible(self.root_name .. ".page." .. tostring(i), i == self.page)
  end
  self:_visible(self.root_name .. ".btn.prev", self.page > 1)
  self:_visible(self.root_name .. ".btn.next", true)
  return self
end

function M:init()
  if self.inited then return self end
  if self:_find(self.root_name) == nil then return self end
  self.inited = true
  self:_visible("teach", false)
  self:_visible("teach.text", false)
  self:_bind(self.root_name .. ".btn.prev", function() self:prev() end)
  self:_bind(self.root_name .. ".btn.next", function() self:next() end)
  self:_bind(self.root_name .. ".btn.close", function() self:close() end)
  self:_bind(self.root_name .. ".btn.skip", function() self:close() end)
  self.page = 1
  self:_paint()
  self:_visible(self.root_name, false)
  self:_note("静态教程 init 完成 tag=" .. self.tag .. " pages=" .. tostring(self.pages))
  return self
end

function M:open_ui()
  self.open = true
  self:_visible(self.root_name, true)
  self:_paint()
  self:_note("打开 tag=" .. self.tag .. " 第 " .. tostring(self.page) .. " 页")
  return self
end

function M:close()
  self.open = false
  self:_visible(self.root_name, false)
  return self
end

function M:go(n)
  local p = tonumber(n) or 1
  if p < 1 then p = 1 end
  if p > self.pages then p = self.pages end
  self.page = p
  self:_paint()
  return self
end

function M:next()
  if self.page >= self.pages then return self:close() end
  return self:go(self.page + 1)
end
function M:prev() return self:go(self.page - 1) end
M["goto"] = M.go

return M
