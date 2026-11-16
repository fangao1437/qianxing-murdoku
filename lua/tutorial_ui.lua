local M = {}
local FURN = {
  home = {
    { "plant_2",0,0,96,96,108,108,258.412689,139.758377 },
    { "table_h2",0,0,216,108,216,108,148.783066,66.671959 },
    { "chair",0,0,108,108,108,108,404.585541,-6.414462 },
    { "rug",0,0,108,108,108,108,185.326279,-152.587296 },
  },
  l1 = {
    { "table_v2",676,262,108,216,108,216 }, { "plant_2",788,206,108,108,108,108 },
    { "plant_2",676,654,108,108,108,108 }, { "plant_2",900,654,108,108,108,108 },
    { "rug_2",732,430,216,108,216,108 }, { "rug_2",1068,318,216,108,216,108 },
    { "chair",788,542,108,108,108,108 }, { "chair",1012,654,108,108,108,108 },
  },
  l2 = {
    { "chair",667.5,197.5,89,89,108,108 }, { "table_h2",807,197.5,178,89,216,108 },
    { "rug",946.5,197.5,89,89,108,108 }, { "statue",1132.5,197.5,89,89,108,108 },
    { "chair",946.5,290.5,89,89,108,108 }, { "plant",760.5,383.5,89,89,108,108 },
    { "rug_2",900,383.5,178,89,216,108 }, { "rug_3",667.5,616,89,178,108,216 },
    { "plant",946.5,569.5,89,89,108,108 }, { "shelf",760.5,662.5,89,89,108,108 },
    { "plant",946.5,662.5,89,89,108,108 }, { "table",1039.5,662.5,89,89,108,108 },
  },
}
local SCALE = 1480 / 2268
local BOARD_X = 60 + (1256 - 36) * SCALE + 620 * SCALE / 2
local BOARD_Y = 121 + (302 - 36) * SCALE + 620 * SCALE / 2
function M:furniture_done()
  local spec = FURN[self.tag]
  if spec == nil then return true end
  if self.furniture == nil then return false end
  for i = 1, #spec do if self.furniture[i] == nil then return false end end
  return true
end
function M:_ensure_furniture(limit)
  local spec = FURN[self.tag]
  if spec == nil or game == nil or game.InstantiateClientUIControl == nil then return end
  local parent = self:_find(self.root_name .. ".board")
  if parent == nil then
    self:_note("家具实例化跳过 tag=" .. self.tag .. "：找不到 " .. self.root_name .. ".board")
    return
  end
  local prefabs = nil
  pcall(function() prefabs = self.adapter:_furn_prefab_map() end)
  if type(prefabs) ~= "table" then
    self:_note("家具实例化跳过 tag=" .. self.tag .. "：things 模板映射为空")
    return
  end
  self.furniture = self.furniture or {}
  local order = {}
  for pass = 1, 2 do
    for i, f in ipairs(spec) do
      local is_rug = tostring(f[1]):find("rug", 1, true) ~= nil
      if (pass == 1) == is_rug then order[#order + 1] = i end
    end
  end
  local made = 0
  for _, i in ipairs(order) do
    local f = spec[i]
    if limit ~= nil and made >= limit then break end
    if self.furniture[i] == nil and prefabs[f[1]] ~= nil then
      local ok, obj = pcall(game.InstantiateClientUIControl, prefabs[f[1]], parent)
      if ok and obj ~= nil then
        self.furniture[i] = obj
        local w, h = f[4] * SCALE, f[5] * SCALE
        local x = BOARD_X - 656 * SCALE / 2 + (f[2] - 572) * SCALE - 800
        local y = 450 - (BOARD_Y - 656 * SCALE / 2 + (f[3] - 102) * SCALE)
        pcall(function() if obj.SetAnchorMin then obj:SetAnchorMin(0.5, 0.5) end end)
        pcall(function() if obj.SetAnchorMax then obj:SetAnchorMax(0.5, 0.5) end end)
        pcall(function() if obj.SetPivot then obj:SetPivot(0.5, 0.5) end end)
        pcall(function() if obj.SetSizeDelta then obj:SetSizeDelta(w, h) end end)
        pcall(function() if obj.SetAnchoredPosition then obj:SetAnchoredPosition(x, y) end end)
        if f[8] ~= nil then
          pcall(function() obj:SetAnchoredPosition(f[8], f[9]) end)
        end
        local scaled = false
        pcall(function()
          if self.adapter._furn_scale_layers ~= nil then
            self.adapter:_furn_scale_layers(obj, w / f[6], h / f[7]); scaled = true
          end
        end)
        if not scaled then pcall(function() if obj.SetLocalScale then obj:SetLocalScale(w / f[6], h / f[7], 1) end end) end
        pcall(function()
          if obj.SetAsLastSibling ~= nil then
            obj:SetAsLastSibling()
          elseif obj.SetSiblingIndex ~= nil and parent.GetChildren ~= nil then
            local kids = nil
            pcall(function() kids = parent:GetChildren() end)
            if type(kids) == "table" and #kids > 0 then obj:SetSiblingIndex(#kids - 1) end
          end
        end)
        pcall(function() obj:SetVisible(true); obj:SetActive(true) end)
        made = made + 1
      end
    end
  end
  self._furn_made = (self._furn_made or 0) + made
  if self._furn_made > 0 and not self._furn_logged and self:furniture_done() then
    self._furn_logged = true
    self:_note("家具实例化 tag=" .. self.tag .. " 新建=" .. self._furn_made)
  end
end
function M:prewarm(n)
  if self:furniture_done() then return true end
  if not self.inited then return false end
  self:_ensure_furniture(n or 1)
  return self:furniture_done()
end
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
    eager_furniture = (opts.eager_furniture == true),
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
  -- 700：名称索引可能早于教程子控件挂入；在已知根容器内补查，
  -- 不因每个迟到按钮重建全局索引，也不等待适配器时钟开始推进。
  if ctrl == nil and name ~= self.root_name then
    local root = nil
    pcall(function() root = self.adapter:find(self.root_name) end)
    if root ~= nil then
      pcall(function() ctrl = root:GetChild(name) end)
      if ctrl == nil then
        local kids = nil
        pcall(function() kids = root:GetChildren() end)
        if type(kids) == "table" then
          for _, child in ipairs(kids) do
            local actual = nil
            pcall(function() actual = child.name end)
            if actual == name then ctrl = child; break end
          end
        end
      end
    end
  end
  return ctrl
end
function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(function() ctrl:SetVisible(want and true or false) end)
  if want then pcall(function() ctrl:SetActive(true) end) end
  return true
end
function M:_bind(name, fn, resolved)
  local ctrl = resolved or self:_find(name)
  if ctrl == nil or self.bound[ctrl] then return ctrl ~= nil end
  if ctrl.AddCursorEventListener == nil then return false end
  local ok = pcall(function()
    local ev = Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick
    if ev == nil then error("CursorClick unavailable") end
    pcall(function() ctrl.raycastTarget = true end)
    pcall(function() ctrl.interactable = true end)
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  if ok then self.bound[ctrl] = true end
  return ok
end
function M:_bind_steps()
  if self.pages < 2 then return end
  self._steps_bound = self._steps_bound or {}
  if self._steps_bound[self.page] then return end
  local prefix = self.root_name .. ".page." .. tostring(self.page)
  local complete = true
  local controls = {}
  local page_ctrl = self:_find(prefix)
  local kids = nil
  if page_ctrl and page_ctrl.GetChildren then pcall(function() kids = page_ctrl:GetChildren() end) end
  if type(kids) == "table" then
    for _, child in ipairs(kids) do
      local name = nil
      pcall(function() name = child.name end)
      if name then controls[name] = child end
    end
  end
  local function bind(name, fn)
    if type(kids) == "table" and controls[name] == nil then return false end
    return self:_bind(name, fn, controls[name])
  end
  for i = 1, self.pages do
    local target = i
    local fn = function() if self.open then self:go(target) end end
    if not bind(prefix .. ".stephit." .. tostring(i), fn) then complete = false end
  end
  if complete then self._steps_bound[self.page] = true end
end
function M:_paint()
  -- 705：两关末页和首页统一文案；控件迟到时下次绘制仍会补写。
  if (self.tag == "l1" or self.tag == "l2") and self.page == self.pages then
    local label = self:_find(self.root_name .. ".page." .. tostring(self.pages) .. ".nexttext")
    if label ~= nil then pcall(function() label.text = "开始办案" end) end
  end
  if self.open then self:_bind_steps() end
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
  -- 根节点可见不代表按钮已加载完；只在必需的事件绑定齐全后提交就绪。
  local prev = self:_bind(self.root_name .. ".btn.prev", function() self:prev() end)
  local next_bound = self:_bind(self.root_name .. ".btn.next", function() self:next() end)
  local close_bound = self:_bind(self.root_name .. ".btn.close", function() self:close() end)
  self:_bind(self.root_name .. ".btn.skip", function() self:close() end)
  if not next_bound or not close_bound or (self.pages > 1 and not prev) then
    self:_visible(self.root_name, false)
    if not self._waiting_logged then
      self._waiting_logged = true
      self:_note("等待教程按钮就绪 tag=" .. self.tag)
    end
    return self
  end
  self.inited = true
  self.page = 1
  self:_paint()
  if self.eager_furniture then self:_ensure_furniture() end
  self:_visible(self.root_name, false)
  self:_note("静态教程 init 完成 tag=" .. self.tag .. " pages=" .. tostring(self.pages) .. " 必需按钮已绑定")
  return self
end
function M:open_ui()
  self:init()
  if not self.inited then return self end
  self.open = true
  self:_visible(self.root_name, true)
  self:_ensure_furniture()
  self:_paint()
  self:_note("打开 tag=" .. self.tag .. " 第 " .. tostring(self.page) .. " 页")
  return self
end
function M:close()
  if self.open then self:_note("关闭 tag=" .. self.tag) end
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
