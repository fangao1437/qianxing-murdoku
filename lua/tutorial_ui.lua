--[[----------------------------------------------------------------------------
  lua/tutorial_ui.lua —— 玩法说明（教程）浮层 · v335（左卡面 + 线索卡 + 结论文本）

  v335（用户 2026-10-25 实机反馈后）：
    · 面板压矮到 560×600（原 820 高），左侧卡面 + 右侧棋盘；
    · 主卡（page）500×150 + 新克隆的线索卡底板（teach.<t>.clue）500×110 + 结论/提示一行；
    · 正文分三段写：body.1 主说明、body.2 线索、body.3 结论/提示（脚本写 text/fontSize/fontColor）。

  控件结构（与存档逐字一致，改存档要同步这里）：
      teach.<t>                         560×600 面板（贴左）
      ├ bg / page(500×150) / page.bg
      ├ clue                            500×110 线索卡底板（v335 克隆）
      ├ btn.prev / next（100×52，贴底）/ close（44×44，右上）
      └ dot.* / btn.click               脚本隐藏
      teach.text.<t>                    title / subtitle / body.1..3 / btn.*

  规矩：不创建/改尺寸/改父级；只做「显隐 + 绑点击 + 写文本三属性」；全程 pcall。
----------------------------------------------------------------------------]]--

local M = {}

local DEFAULT_PAGES = 3

-- ── 文案：三套教程逐页内容（step=页标签 / body=主说明 / clue=线索 / note=结论）──
M.CONTENT = {
  home = {
    title = "玩法总览 · 先摆人，再指认",
    pages = {
      {
        step = "5 条规则",
        body = "① 目标：摆满当事人，再指认。全部摆好后指出盗窃者；受害者屋里还有别人，还要说清有没有同伙。\n"
            .. "② 每行、每列恰好一人。放下一个人，整行整列自动打叉。\n"
            .. "③ 只能站「可站」的格子：椅子、地毯可以站；桌子、植物、书架、雕像不能站。\n"
            .. "④ 「旁边 / 隔壁」只算上下左右贴着的格子：同屋直接算，跨屋必须中间有门，隔着墙不算。",
        clue = "操作：轻点＝笔记　双击＝预放置　长按＝正式放下",
        note = "受害者也在这 5 个人里，别把他落下。",
      },
    },
  },
  l1 = {
    title = "第一关 · 操作与推理",
    pages = {
      {
        step = "第 1 / 8 步 · 认识棋盘",
        body = "左边是线索卡，中间是棋盘，右边是工具。棋盘 5×5，三间屋：大屋、内室、外间；粗线是墙，橙色是门。行号 1–5 从上往下，列号 1–5 从左往右。",
        clue = "棋盘：5×5 · 大屋 / 内室 / 外间 · 三扇门",
        note = "受害者也在这 5 个人里，别把他落下。",
      },
      {
        step = "第 2 / 8 步 · 选人",
        body = "点一张线索卡，就选中卡上那个人。卡上写的是他的口供——说的可能是别人。选中后，话里提到的位置会在棋盘上亮起来；再点一次取消选中。",
        clue = "卡 1（值班保安）：「收藏家 在第 5 列」",
        note = "卡上的人＝要放下的人；卡上的话＝口供，可能说别人。",
      },
      {
        step = "第 3 / 8 步 · 放人",
        body = "轻点格子＝铅笔笔记（不占位）；双击＝预放置（先占位，可反悔）；按住不放、进度环走完＝正式放下。放下后这一行这一列自动打叉。",
        clue = "轻点＝笔记　双击＝预放置　长按＝正式放下",
        note = "放错了：撤销 / 重做 / 重置在右边。",
      },
      {
        step = "第 4 / 8 步 · 推理一",
        body = "卡 3（夜班清洁工）：「只有值班保安站在地毯上」。地毯一共 4 格，所以保安只可能在这 4 格之一——别人踩上地毯就破了这句话。",
        clue = "卡 3（夜班清洁工）：「只有 值班保安 站在 地毯 上」",
        note = "别人踩上地毯就破了这句话。",
      },
      {
        step = "第 5 / 8 步 · 推理二",
        body = "卡 5（收藏家）：「前台姑娘在桌子旁边」。桌子旁只有 (2,2) 和 (3,1)；但 (3,1) 是地毯，站上去就和卡 3 冲突，所以 B=(2,2)。第 2 行、第 2 列被占 ⇒ A 的 (2,4)(2,5)(3,2) 出局 ⇒ A=(3,1)。",
        clue = "卡 5（收藏家）：「前台姑娘 在 桌子 旁边」",
        note = "已确定：B→(2,2)　A→(3,1)",
      },
      {
        step = "第 6 / 8 步 · 推理三",
        body = "卡 4（旧识古董商）：「夜班清洁工站在椅子上」。椅子只有 (4,2) 和 (5,4)；(4,2) 和前台姑娘同列，站不了 ⇒ 清洁工 = (5,4)。",
        clue = "卡 4（旧识古董商）：「夜班清洁工 站在 椅子 上」",
        note = "已确定：C→(5,4)（(4,2) 同列出局）",
      },
      {
        step = "第 7 / 8 步 · 收口",
        body = "卡 1「收藏家在第 5 列」+ 卡 2「古董商在植物旁边」。前三个人已钉死，只剩 D 与 V 互换的两种摆法；把 D 换到外间 (4,3) 时，受害者相邻两屋里「无辜人数最多的那间」不是 D 所在的屋 ⇒ 这种摆法不成立。",
        clue = "卡 1（值班保安）：「收藏家 在 第 5 列」",
        note = "两种摆法 → 只留 D(1,3)、V(4,5)",
      },
      {
        step = "第 8 / 8 步 · 指认",
        body = "摆位定死后回头看：A、B、C 全程各只有 1 个可能格，只有 D 一直留着 2 格——有选择余地的那个就是盗窃者。受害者独处内室 ⇒ 无同伙。",
        clue = "结论：盗窃者 = D　同伙 = 无",
        note = "提交后：先校验摆位，再指认盗窃者、回答有没有同伙。",
      },
    },
  },
  l2 = {
    title = "第二关 · 复述与谎言",
    pages = {
      {
        step = "第 1 / 4 步 · 复习",
        body = "① 每行每列恰好一人 ② 只能站椅子、地毯 ③ 用线索把每个人的可能格收窄 ④ 看门：只有门直接连通的两间才算相邻。这一关的侧廊只有一扇门，所以它只和大厅相邻。",
        clue = "本关场地：6×6 · 四间屋 · 侧廊只有一扇门",
        note = "门只决定「哪两间算相邻」，不改变房间划分。",
      },
      {
        step = "第 2 / 4 步 · 假话",
        body = "线索里最多有一句假话，整条假、不会预告是哪一句；受害者的话也可能落在这一条上。另有一种「通用线索」不算谁的卡，比如本关的「地毯上没有人」——它同样可能为假，但这一句是真的，先把 5 个地毯格划掉。",
        clue = "通用线索（不占卡位）：「地毯上没有人」",
        note = "至多 1 句假话，不会预告是哪一句。",
      },
      {
        step = "第 3 / 4 步 · 抓谎",
        body = "先假设所有线索都为真；如果一种摆法都摆不出来，就说明必有一句假话。再逐条假设它是假、摘掉它，看剩下能不能自洽——能自洽的那一条就是假话。像「某人在某人的同一列上方」这种形状的话天生就假：每列只能站一个人。",
        clue = "恒假句式：「A 在 B 的同一列上方」",
        note = "先假设全真；摆不出 ⇒ 必有假。",
      },
      {
        step = "第 4 / 4 步 · 收口",
        body = "摆满、提交；判题只校验硬冲突（同行同列、踩到家具），不会告诉你是哪一句假、也不会说有几条不成立。找到那句假话之后，说这句话的人就是你要指认的人。",
        clue = "结论：说谎者 = 盗窃者（不点名）",
        note = "判题只报「摆位还没成立」，不揭晓哪句假。",
      },
    },
  },
}

-- ── 样式（脚本写入）：字号 / 颜色（0xAARRGGBB 整数）────────────────────────────
local STYLE = {
  title    = { size = 27, color = 0xFFF3EDE0 },
  subtitle = { size = 17, color = 0xFFFFCB7A },
  body     = { size = 15, color = 0xFFD3CCBD },
  clue     = { size = 14, color = 0xFFE9E2D3 },
  note     = { size = 13, color = 0xFFBDB6A7 },
  btn      = { size = 13, color = 0xFFBDB6A7 },
  legend   = { size = 13, color = 0xFFBDB6A7 },
}

-- 图例（宽版面板右列）
local LEGEND = "图例\n\n大屋 / 内室 / 外间\n墙（深灰）  门（橙）\n棋子＝头像\n候选＝淡圈\n排除＝红叉\n笔记＝铅笔小字\n受害者＝蓝标\n\n坐标＝(行,列)\n行号自上而下\n列号自左而右"

-- ── 缩略棋盘：房间色 + 头像显隐（v339 新增；控件 teach.<t>.board.r.c / teach.<t>.av.X）──
local BOARDS = {
  home = {
    rows = 5, cols = 5,
    colors = { [0] = 0xFFD9CDB4, [1] = 0xFFC3CDD4, [2] = 0xFFD4C8BC },
    grid = { "00011", "00011", "00011", "22221", "22221" },
    avatars = {},
  },
  l1 = {
    rows = 5, cols = 5,
    colors = { [0] = 0xFFD9CDB4, [1] = 0xFFC3CDD4, [2] = 0xFFD4C8BC },
    grid = { "00011", "00011", "00011", "22221", "22221" },
    avatars = { { id = "A", from = 5 }, { id = "B", from = 5 }, { id = "C", from = 6 }, { id = "D", from = 8 }, { id = "V", from = 8 } },
  },
  l2 = {
    rows = 6, cols = 6,
    colors = { [0] = 0xFFD9CDB4, [1] = 0xFFC3CDD4, [2] = 0xFFD4C8BC, [3] = 0xFFBECFB0 },
    grid = { "000011", "000011", "000011", "222331", "222333", "222233" },
    avatars = { { id = "A", from = 4 }, { id = "B", from = 4 }, { id = "C", from = 4 }, { id = "D", from = 4 }, { id = "E", from = 4 }, { id = "V", from = 4 } },
  },
}


-- ── 首页 5 块分区卡（v340）────────────────────────────────────────────────
local HOME_CARDS = {
  { t = "目标：摆满当事人，再指认", b = "每名当事人（含 1 名受害者）各占一格；全部摆好后指出盗窃者；受害者屋里还有别人，还要说清有没有同伙。" },
  { t = "每行、每列恰好一人", b = "放下一个人，整行整列自动打叉。一行不能站两个，一列也不能。" },
  { t = "只能站「可站」的格子", b = "椅子、地毯可以站；桌子、植物、书架、雕像不能站。" },
  { t = "「旁边 / 隔壁」怎么算", b = "只算上下左右贴着的格子：同屋直接算，跨屋必须中间有门，隔着墙不算。" },
  { t = "操作：轻点 / 双击 / 长按", b = "点卡选中人；轻点＝铅笔笔记；双击＝预放置；按住不放、进度环走完＝正式放下。" },
}

-- ── 图例 9 行（图标色 + 文字；v340）──────────────────────────────────────
local LEGEND_ROWS = {
  l1 = {
    { "大屋", 0xFFD9CDB4 }, { "内室", 0xFFC3CDD4 }, { "外间", 0xFFD4C8BC },
    { "墙", 0xFF29282B }, { "门", 0xFFDC5B28 }, { "棋子＝头像", 0xFF8FB4D9 },
    { "候选＝淡圈", 0xFF9A9385 }, { "排除＝红叉", 0xFFD0553F }, { "受害者＝蓝标", 0xFF4C8FA6 },
  },
  l2 = {
    { "大厅", 0xFFD9CDB4 }, { "侧廊", 0xFFC3CDD4 }, { "库房", 0xFFD4C8BC }, { "内室", 0xFFBECFB0 },
    { "墙", 0xFF29282B }, { "门", 0xFFDC5B28 }, { "棋子＝头像", 0xFF8FB4D9 },
    { "候选＝淡圈", 0xFF9A9385 }, { "排除＝红叉", 0xFFD0553F },
  },
  home = {
    { "大屋", 0xFFD9CDB4 }, { "内室", 0xFFC3CDD4 }, { "外间", 0xFFD4C8BC },
    { "墙", 0xFF29282B }, { "门", 0xFFDC5B28 }, { "棋子＝头像", 0xFF8FB4D9 },
    { "候选＝淡圈", 0xFF9A9385 }, { "排除＝红叉", 0xFFD0553F }, { "受害者＝蓝标", 0xFF4C8FA6 },
  },
}

local function _clear(ctrl)
  if ctrl == nil then return false end
  if type(ctrl.SetText) == "function" then
    pcall(function() ctrl:SetText("") end)
  else
    pcall(function() ctrl.text = "" end)
  end
  return true
end

local function _to_color(argb)
  if type(argb) ~= "number" then return argb end
  local a = math.floor(argb / 16777216) % 256
  local r = math.floor(argb / 65536) % 256
  local g = math.floor(argb / 256) % 256
  local b = argb % 256
  if Color ~= nil then
    local ok, c = pcall(Color, r, g, b, a)
    if ok and c ~= nil then return c end
  end
  return argb
end

local function _write(ctrl, txt, size, color)
  if ctrl == nil then return false end
  if type(txt) == "string" and txt ~= "" then
    local ok = false
    if type(ctrl.SetText) == "function" then
      ok = pcall(function() ctrl:SetText(txt) end)
    end
    if not ok then pcall(function() ctrl.text = txt end) end
  end
  if size ~= nil then
    pcall(function() if ctrl.adaptiveFontSize ~= nil then ctrl.adaptiveFontSize = false end end)
    pcall(function() ctrl.fontSize = size end)
  end
  if color ~= nil then
    local c = _to_color(color)
    pcall(function() ctrl.fontColor = c end)
  end
  return true
end

function M.new(adapter, opts)
  if type(opts) ~= "table" then opts = {} end
  local tag = tostring(opts.tag or "?")
  local content = opts.content or nil
  local pages = (content ~= nil and content.pages ~= nil and #content.pages) or tonumber(opts.pages) or DEFAULT_PAGES
  if pages < 1 then pages = 1 end

  local self = {
    adapter   = adapter,
    tag       = tag,
    root_name = tostring(opts.root or "teach"),
    text_name = tostring(opts.text or "teach.text"),
    content   = content,
    pages     = pages,
    page      = 1,
    open      = false,
    inited    = false,
    bound     = {},
    log       = {},
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

function M:_sub(parent_name, child_name)
  local ctrl = nil
  pcall(function() ctrl = self.adapter:sub(parent_name, child_name) end)
  return ctrl
end

function M:_set_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(function() ctrl:SetVisible(want and true or false) end)
  if want then pcall(function() ctrl:SetActive(true) end) end
  return true
end

function M:_bind(ctrl_name, fn)
  local ctrl = self:_find(ctrl_name)
  if ctrl == nil then return false end
  if ctrl.AddCursorEventListener == nil then
    self:_note("控件 " .. ctrl_name .. " 不支持光标事件（需要「预设按钮」）")
    return false
  end
  if self.bound[ctrl] then return true end
  self.bound[ctrl] = true
  local ok = pcall(function()
    local ev = (Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick) or nil
    if ev == nil then error("Enum.CursorEventType 不可用") end
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  if not ok then self:_note("绑定 " .. ctrl_name .. " 失败") end
  return ok
end

function M:_body(i)
  local full = self.text_name .. ".body." .. tostring(i)
  local ctrl = self:_find(full)
  if ctrl == nil then ctrl = self:_sub(self.text_name, full) end
  return ctrl
end

function M:_paint_home()
  if self.tag ~= "home" then return self end
  local T = self.text_name
  self:_set_visible(self.root_name .. ".page", false)
  self:_set_visible(self.root_name .. ".clue", false)
  self:_set_visible(T .. ".body.1", false)
  self:_set_visible(T .. ".body.2", false)
  self:_set_visible(T .. ".body.3", false)
  self:_set_visible(T .. ".body.1b", false)
  for i, card in ipairs(HOME_CARDS) do
    local N = self.root_name .. ".card." .. tostring(i)
    local bg = self:_find(N)
    if bg ~= nil then pcall(function() bg.imageColor = 0xFF1B2230 end) end
    local ctrl = self:_find(N .. ".badge")
    if ctrl ~= nil then pcall(function() ctrl.imageColor = 0xFFE8A23C end) end
    -- 标题/编号框已加大（用户提示：文本框不够大文字不渲染）
    local ttl = self:_find(T .. ".card." .. tostring(i) .. ".title")
    local num = self:_find(T .. ".card." .. tostring(i) .. ".num")
    if ttl ~= nil then pcall(function() ttl:SetVisible(true) end) end
    if num ~= nil then pcall(function() num:SetVisible(true) end) end
    _write(num, tostring(i), 16, 0xFF22180A)
    _write(ttl, card.t, 18, 0xFFF3EDE0)
    _write(self:_find(T .. ".card." .. tostring(i) .. ".body"), card.b, 13, 0xFFD3CCBD)
  end
  return self
end

function M:_paint_legend()
  local rows = LEGEND_ROWS[self.tag]
  if rows == nil then return self end
  -- 行文本框已加大（192×30）
  self:_set_visible(self.text_name .. ".legend", false)
  for i, row in ipairs(rows) do
    local icon = self:_find(self.root_name .. ".legend." .. tostring(i) .. ".icon")
    if icon ~= nil then pcall(function() icon.imageColor = row[2] end) end
    local ctrl = self:_find(self.text_name .. ".legend." .. tostring(i))
    if ctrl ~= nil then pcall(function() ctrl:SetVisible(true) end) end
    _write(ctrl, row[1], 13, 0xFFBDB6A7)
  end
  return self
end

function M:_paint_board()
  local B = BOARDS[self.tag]
  if B == nil then return self end
  for r = 1, B.rows do
    local line = B.grid[r]
    if line ~= nil then
      for c = 1, B.cols do
        local ctrl = self:_find(self.root_name .. ".board." .. tostring(r) .. "." .. tostring(c))
        if ctrl ~= nil then
          local room = tonumber(line:sub(c, c)) or 0
          local col = B.colors[room]
          if col ~= nil then pcall(function() ctrl.imageColor = col end) end
        end
      end
    end
  end
  for _, av in ipairs(B.avatars) do
    self:_set_visible(self.root_name .. ".av." .. tostring(av.id), self.page >= av.from)
  end
  return self
end

function M:_paint()
  if self.content ~= nil then
    local pg = self.content.pages[self.page]
    local T = self.text_name
    -- 标题/页标签先显式显示（防止被旧状态隐藏）
    local c_title = self:_find(T .. ".title")
    if c_title ~= nil then pcall(function() c_title:SetVisible(true) end) end
    local c_sub = self:_find(T .. ".subtitle")
    if c_sub ~= nil then pcall(function() c_sub:SetVisible(true) end) end
    _write(c_title, self.content.title, STYLE.title.size, STYLE.title.color)
    _write(self:_find(T .. ".subtitle"), pg and pg.step or "", STYLE.subtitle.size, STYLE.subtitle.color)
    _write(self:_find(T .. ".legend"), LEGEND, STYLE.legend.size, STYLE.legend.color)
    pcall(function() local b = self:_find(self.root_name .. ".bg"); if b ~= nil then b.imageColor = 0xFF0B0F18 end end)
    pcall(function() local b = self:_find(self.root_name .. ".board"); if b ~= nil then b.imageColor = 0xFF141A26 end end)
    pcall(function() local b = self:_find(self.root_name .. ".clue"); if b ~= nil then b.imageColor = 0xFF1B2230 end end)
    pcall(function() local b = self:_sub(self.root_name .. ".page", "bg"); if b ~= nil then b.imageColor = 0xFF1B2230 end end)
    self:_paint_board()
    -- 主卡拆两段：body.1 = 线索复述（金），body.1b = 推导（灰）
    if self.tag == "home" then
      _write(self:_body(1), "", STYLE.body.size, STYLE.body.color)
      _write(self:_find(T .. ".body.1b"), "", STYLE.body.size, STYLE.body.color)
    else
      _write(self:_body(1), pg and pg.clue or "", STYLE.clue.size, 0xFFFFCB7A)
      _write(self:_find(T .. ".body.1b"), pg and pg.body or "", STYLE.body.size, STYLE.body.color)
    end
    local b1b = self:_find(T .. ".body.1b")
    if b1b ~= nil then pcall(function() b1b:SetVisible(self.tag ~= "home") end) end
    _write(self:_body(2), pg and pg.clue or "", STYLE.clue.size, STYLE.clue.color)
    _write(self:_body(3), pg and pg.note or "", STYLE.note.size, STYLE.note.color)
    for i = 1, 3 do
      local c = self:_body(i)
      if c ~= nil then pcall(function() c:SetVisible(true) end) end
    end
    self:_paint_home()
    self:_paint_legend()
    for i = 1, 3 do
      self:_set_visible(self.root_name .. ".dot." .. tostring(i) .. ".on", false)
      self:_set_visible(self.root_name .. ".dot." .. tostring(i) .. ".off", false)
    end
    self:_set_visible(self.root_name .. ".btn.click", false)
    local multi = self.pages > 1
    self:_set_visible(self.root_name .. ".btn.prev", multi)
    self:_set_visible(self.root_name .. ".btn.next", multi)
    -- 箭头图标隐藏，翻页按钮改文字（用户 2026-10-25：箭头可去掉）
    self:_set_visible(self.root_name .. ".btn.prev.icon", false)
    self:_set_visible(self.root_name .. ".btn.next.icon", false)
    _write(self:_find(T .. ".btn.prev"), "上一步", STYLE.btn.size, STYLE.btn.color)
    _write(self:_find(T .. ".btn.next"), "下一步", STYLE.btn.size, STYLE.btn.color)
    _clear(self:_find(T .. ".btn.close"))
    _clear(self:_find(T .. ".btn.click"))
    if not multi then
      self:_set_visible(T .. ".btn.prev", false)
      self:_set_visible(T .. ".btn.next", false)
    end
    return self
  end
  for i = 1, self.pages do
    local ctrl = self:_body(i)
    if ctrl ~= nil then pcall(function() ctrl:SetVisible(i == self.page) end) end
  end
  for i = 1, self.pages do
    local cur = (i == self.page)
    self:_set_visible(self.root_name .. ".dot." .. tostring(i) .. ".on", cur)
    self:_set_visible(self.root_name .. ".dot." .. tostring(i) .. ".off", not cur)
  end
  return self
end

function M:init()
  if self.inited then return self end
  if self:_find(self.root_name) == nil then
    return self
  end
  self.inited = true
  self:_bind(self.root_name .. ".btn.prev", function() self:prev() end)
  self:_bind(self.root_name .. ".btn.next", function() self:next() end)
  self:_bind(self.root_name .. ".btn.close", function() self:close() end)
  self:_bind(self.root_name .. ".btn.click", function() self:next() end)
  self:_set_visible(self.root_name, false)
  self:_set_visible(self.text_name, false)
  if self:_find(self.text_name) == nil then
    self:_note("文本区域 " .. self.text_name .. " 没找到（只显示面板，正文不会出现）")
  end
  self.page = 1
  self:_note("init 完成 tag=" .. self.tag .. " pages=" .. tostring(self.pages))
  return self
end

function M:open_ui()
  self.open = true
  self:_set_visible(self.root_name, true)
  self:_set_visible(self.text_name, true)
  self:_paint()
  self:_note("打开 tag=" .. self.tag .. "（第 " .. tostring(self.page) .. " / " .. tostring(self.pages) .. " 页）")
  return self
end

function M:close()
  self.open = false
  self:_set_visible(self.root_name, false)
  self:_set_visible(self.text_name, false)
  self:_note("关闭 tag=" .. self.tag)
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

function M:next() return self:go(self.page + 1) end
function M:prev() return self:go(self.page - 1) end

M["goto"] = M.go

return M
