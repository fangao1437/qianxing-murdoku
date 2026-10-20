--[[----------------------------------------------------------------------------
  lua/tutorial_ui.lua —— 玩法说明（教程）浮层 · v284

  ★ 控件来源：`478-教程UI并入-v284.gil`
    由 `tools/gil/gen_tutorial_into.mjs` 把 `477-教程UI骨架-独立号段.gil` 的
    **场景层**并入主档，**全部加了 `tut.` 前缀**（骨架原名 `hud.title` / `bg` / `label`
    会和主档同名控件撞名），`tut.app.root` 撑成 1600×900 满画布（骨架里是 0×0，
    引擎按父级矩形裁剪 ⇒ 0×0 会把整片教程裁没）。

  ★ 控件表（都按名字取，改名要同步这里）：
      tut.app.root        根容器（满画布）
      └ tut.screen.demo   浮层主体
        ├ tut.hud.title   标题
        ├ tut.hud.pager   页码「第 N / 3 页」
        ├ tut.tab.p1..p3  三个页签（选中态子控件 state.sel / state.off）
        ├ tut.btn.prev / tut.btn.next / tut.btn.reset / tut.btn.close
        └ tut.page.p1..p3 三页内容（子控件 tut.bg 底 + tut.label 正文）

  ★ 约定（与主工程一致）：
    · 引擎调用一律 **点号** `game.X(...)`；控件方法用**冒号**；
    · 全流程 `pcall` 兜住：任何一个控件缺失都只降级（少一块），**不许整条链崩**；
    · `.gil` **存不下文字** ⇒ 三页正文由本模块在运行时写进去；
    · 不创建任何控件（用户明确要求：脚本里不要有创建控件这种操作）。
----------------------------------------------------------------------------]]--

local M = {}

M.PAGES = {
  {
    title = "目标",
    body = "把 4 名嫌疑人和 1 名受害者摆进棋盘：每行、每列各一人。\n"
      .. "线索全部为真（至多一句假话，界面会提示）。推理出谁是小偷后提交。",
  },
  {
    title = "操作",
    body = "点空格子 = 放下当前选中的人；再点一次 = 取消。\n"
      .. "左侧线索卡点一下，棋盘上会点亮「这条线索允许出现的位置」。\n"
      .. "底部按钮：提交 / 重做 / 撤销。",
  },
  {
    title = "区域与门窗",
    body = "墙把棋盘切成几个区域，门连接相邻区域。\n"
      .. "受害者所在区域里的人数决定了「有没有同伙」，这是破案的关键。",
  },
}

local ROOT_NAME = "tut.app.root"
local SCREEN_NAME = "tut.screen.demo"

function M.new(adapter)
  local self = {
    adapter = adapter,
    page = 1,
    open = false,
    bound = {},          -- 控件对象 → true（防双绑；★ 不按 id 记，见适配器里的同款教训）
    inited = false,
    log = {},
  }
  return setmetatable(self, { __index = M })
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

function M:_set_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  local ok = true
  pcall(function() ctrl:SetVisible(want and true or false) end)
  if want then pcall(function() ctrl:SetActive(true) end) end
  return ok
end

function M:_set_text(name, text)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  local done = false
  pcall(function() ctrl.text = text; done = true end)
  if done then
    -- 写进去还要读回来（本项目的老规矩：调用成功 ≠ 生效）
    local got = nil
    pcall(function() got = ctrl.text end)
    if tostring(got) ~= tostring(text) and ctrl.SetText ~= nil then
      pcall(function() ctrl:SetText(text) end)
    end
  else
    pcall(function() ctrl:SetText(text) end)
  end
  return true
end

-- 点一下（只绑一次；控件换代后对象变了会重新绑，与适配器的 bound 语义一致）
function M:_bind(name, fn)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  if ctrl.AddCursorEventListener == nil then
    self:_note("控件 " .. name .. " 不支持光标事件（需要「预设按钮」/「光标检测区域」）")
    return false
  end
  if self.bound[ctrl] then return true end
  self.bound[ctrl] = true
  local ok = pcall(function()
    local ev = (Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick) or nil
    if ev == nil then error("Enum.CursorEventType 不可用") end
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  if not ok then self:_note("绑定 " .. name .. " 失败") end
  return ok
end

-- 页签选中态：sel 亮 / off 灭；其余页签反过来
function M:_paint_tabs()
  for i = 1, #M.PAGES do
    local tab = "tut.tab.p" .. i
    local sel = nil
    pcall(function() sel = self.adapter:sub(tab, "state.sel") end)
    local off = nil
    pcall(function() off = self.adapter:sub(tab, "state.off") end)
    if sel ~= nil then pcall(function() sel:SetVisible(i == self.page) end) end
    if off ~= nil then pcall(function() off:SetVisible(i ~= self.page) end) end
  end
end

-- 把当前页刷到界面上
function M:refresh()
  for i = 1, #M.PAGES do
    self:_set_visible("tut.page.p" .. i, i == self.page)
  end
  self:_set_text("tut.hud.title", M.PAGES[self.page] and M.PAGES[self.page].title or "")
  self:_set_text("tut.hud.pager", "第 " .. self.page .. " / " .. #M.PAGES .. " 页")
  -- ★ 正文写在页片的 `label` 子控件上：用 `sub(父名, 子名)` 取（与页签的 state.* 同一种取法），
  --   不写成 "tut.page.p1.label" 这种点号全名 —— 子控件名重复度高（label 有 27 个），按父级限定更稳
  do
    local label = nil
    pcall(function() label = self.adapter:sub("tut.page.p" .. self.page, "label") end)
    local body = M.PAGES[self.page] and M.PAGES[self.page].body or ""
    if label ~= nil then
      local done = pcall(function() label.text = body end)
      if not done and label.SetText ~= nil then pcall(function() label:SetText(body) end) end
    end
  end
  self:_paint_tabs()
end

function M:go_page(page)
  local n = tonumber(page) or 1
  if n < 1 then n = 1 end
  if n > #M.PAGES then n = #M.PAGES end
  self.page = n
  self:refresh()
end

function M:next() self:go_page(self.page + 1) end
function M:prev() self:go_page(self.page - 1) end
function M:reset() self:go_page(1) end

function M:open_ui()
  self.open = true
  self:go_page(self.page)
  self:_set_visible(ROOT_NAME, true)
  self:_note("打开（第 " .. self.page .. " 页）")
end

function M:close()
  self.open = false
  self:_set_visible(ROOT_NAME, false)
  self:_note("关闭")
end

function M:toggle()
  if self.open then self:close() else self:open_ui() end
end

-- 首次初始化：绑按钮、刷一页、藏起来
function M:init()
  if self.inited then return self end
  local root = self:_find(ROOT_NAME)
  if root == nil then
    -- 还没有就等下一帧（控件可能晚一帧才进树）
    return self
  end
  self.inited = true
  self:_bind("tut.btn.prev", function() self:prev() end)
  self:_bind("tut.btn.next", function() self:next() end)
  self:_bind("tut.btn.reset", function() self:reset() end)
  self:_bind("tut.btn.close", function() self:close() end)
  for i = 1, #M.PAGES do
    self:_bind("tut.tab.p" .. i, function() self:go_page(i) end)
  end
  self:refresh()
  self:close()                      -- 默认收起
  self:_note("init 完成")
  return self
end

return M
