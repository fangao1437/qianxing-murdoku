local M = {}
M.VERSION = "1.0.0"
M.SIGNALS = {
  READY      = "murdoku/ready",
  PLACE      = "murdoku/place",
  CLEAR      = "murdoku/clear",
  SUBMIT     = "murdoku/submit",
  ACCUSE     = "murdoku/accuse",
  SOLVED     = "murdoku/solved",
  SAVE       = "murdoku/save",
  RESTORE    = "murdoku/restore",
  SYNC_STATE = "murdoku/sync",
  SETTLE     = "murdoku/settle",
}
M.SIGNAL_SCHEMA = {
  [M.SIGNALS.READY]      = { "level_id", "rows", "cols", "piece_count" },
  [M.SIGNALS.PLACE]      = { "who", "r", "c" },
  [M.SIGNALS.CLEAR]      = { "who" },
  [M.SIGNALS.SUBMIT]     = { "ok" },
  [M.SIGNALS.ACCUSE]     = { "thief", "has_accomplice", "correct" },
  [M.SIGNALS.SOLVED]     = { "level_id", "elapsed", "moves", "failed_accusations" },
  [M.SIGNALS.SAVE]       = { "level_id", "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.RESTORE]    = { "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.SYNC_STATE] = { "who", "r", "c" },
  [M.SIGNALS.SETTLE]     = { "level_id" },
}
local function E(path, default)
  local cur = Enum
  if cur == nil then return default end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return default end
  end
  if cur == nil then return default end
  return cur
end
local Adapter = {}
Adapter.__index = Adapter
M.Adapter = Adapter
function M.pack_color(r, g, b, a)
  local function c(v)
    v = tonumber(v)
    if v == nil then v = 0 end
    v = math.floor(v + 0.5)
    if v < 0 then v = 0 end
    if v > 255 then v = 255 end
    return v
  end
  if a == nil then a = 255 end
  return c(a) * 16777216 + c(r) * 65536 + c(g) * 256 + c(b)
end
local function size_of(ctrl)
  if ctrl == nil then return nil, nil end
  local a, b = nil, nil
  if ctrl.GetSizeDelta ~= nil then
    pcall(function() a, b = ctrl:GetSizeDelta() end)
  end
  if type(a) == "table" then return tonumber(a[1]), tonumber(a[2]) end
  if type(a) == "number" then return tonumber(a), tonumber(b) end
  local px, py = nil, nil
  pcall(function() px = ctrl.sizeDeltaX end)
  pcall(function() py = ctrl.sizeDeltaY end)
  return tonumber(px), tonumber(py)
end
function M.new(cfg)
  cfg = cfg or {}
  if type(cfg.cells) == "table" then
    for _, k in ipairs({ "debug_key", "debug_image", "debug_event" }) do
      if cfg[k] == nil and cfg.cells[k] ~= nil then cfg[k] = cfg.cells[k] end
    end
  end
  local self = setmetatable({}, Adapter)
  self.cfg = cfg
  if print then
    print("[murdoku] 调试开关：debug_key=" .. tostring(cfg.debug_key)
      .. " debug_image=" .. tostring(cfg.debug_image)
      .. " debug_event=" .. tostring(cfg.debug_event)
      .. " debug_click=" .. tostring(cfg.debug_click)
      .. "（nil = 关；debug_event/debug_click 为 nil 时按「开」处理）")
  end
  self.signals = M.SIGNALS
  if cfg.signals then
    for k, v in pairs(cfg.signals) do self.signals[k] = v end
  end
  self.controls = {}        
  self._misses = nil        
  self._lookup_hits = 0     
  self._lookup_gen = 0      
  self._subtree_dirty = true
  self._ray = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
  self.handlers = {}        
  self.events = {}          
  self.event_claim = {}
  self.event_latest = {}
  self.subs = {}            
  self._sub_miss = {}
  self.timers = {}
  self.clock = 0
  self.state = {}           
  self.warned = {}
  self.on_input = nil
  self.apply_rect = cfg.apply_rect == true    
  self.text_editor_first = {}
  do
    local list = cfg.text_editor_first
    if type(list) == "table" then
      for i = 1, #list do
        if type(list[i]) == "string" then self.text_editor_first[list[i]] = true end
      end
    end
  end
  return self
end
local PREFIX = "[murdoku] "
function Adapter:log(msg)
  if print then print(PREFIX .. tostring(msg)) end
end
function Adapter:err(msg)
  if printerr then printerr(PREFIX .. tostring(msg)) end
end
function Adapter:warn_once(key, msg)
  if self.warned[key] then return end
  self.warned[key] = true
  self:err(msg)
end
function Adapter:_note_missing(id)
  if id == nil then return end
  self.missing = self.missing or {}
  if self.missing[id] == nil then
    self.missing[id] = true
    self.missing_count = (self.missing_count or 0) + 1
  end
end
local function missing_group(id)
  local s = tostring(id)
  if s:match("^cell%.[%d]+%.[%d]+$")  then return "cell.*"  end
  if s:match("^clue%.[%d]+$")         then return "clue.N"  end
  if s:match("^tray%.[%w_]+$")        then return "tray.*"  end
  if s:match("^modal%.")              then return "modal.*" end
  if s:match("^action%.")             then return "action.*"
  end
  local head = s:match("^([%w_]+)%.")
  if head ~= nil then return head .. ".*" end
  return s
end
function Adapter:report_missing(force)
  if self.missing == nil then return 0 end
  if self.missing_reported and not force then return 0 end
  self.missing_reported = true
  local KNOWN_ABSENT = {
    "clue.",    
    "clues.",   
    "board",    
    "left",     
    "legend",   
    "tray",     
    "room.",    
    "obj.",     
  }
  local function known_absent(id)
    for i = 1, #KNOWN_ABSENT do
      local p = KNOWN_ABSENT[i]
      if id == p or id:sub(1, #p) == p then return true end
    end
    return false
  end
  local unknown, known_n = {}, 0
  for id in pairs(self.missing) do
    if known_absent(id) then known_n = known_n + 1 else unknown[#unknown + 1] = id end
  end
  table.sort(unknown)
  local groups, order = {}, {}
  for i = 1, #unknown do
    local id = unknown[i]
    local g = missing_group(id)
    if groups[g] == nil then
      groups[g] = { n = 0, sample = {} }
      order[#order + 1] = g
    end
    groups[g].n = groups[g].n + 1
    if #groups[g].sample < 3 then groups[g].sample[#groups[g].sample + 1] = id end
  end
  table.sort(order, function(a, b)
    if groups[a].n ~= groups[b].n then return groups[a].n > groups[b].n end
    return a < b
  end)
  if print and known_n > 0 then
    print("[murdoku] 规划里有 " .. tostring(known_n) .. " 个控件是【已知不需要】的"
      .. "（旧线索卡 / 旧滚动条 / board / left / legend / select / tray / room.* / obj.*）"
      .. " —— 按 info 打，不再当错误（名单见 adapter 的 KNOWN_ABSENT）")
  end
  if printerr and #unknown > 0 then
    printerr("[murdoku] ⚠️ 有 " .. tostring(#unknown)
      .. " 个控件【计划有、存档没有、又没有创建路】—— 这是**真问题**，去补计划或补存档：")
    for i = 1, #order do
      local g = order[i]
      local gd = groups[g]
      local samp = table.concat(gd.sample, " ")
      if gd.n > #gd.sample then samp = samp .. " …" end
      printerr("[murdoku]   " .. g .. "  ×" .. gd.n .. "   " .. samp)
    end
    printerr("[murdoku] （全部缺失项见 `node tools/gil/check_names.mjs` 的 🔴 那一组）")
  end
  return self.missing_count or 0
end
local function find_in(ctrl, name, depth)
  if ctrl == nil or depth > 16 then return nil end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname == name then return ctrl end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do
      local hit = find_in(children[i], name, depth + 1)
      if hit then return hit end
    end
  end
  return nil
end
local function collect_names_in(ctrl, depth, out, limit)
  if ctrl == nil or depth > 16 or #out >= limit then return end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and type(cname) == "string" and cname ~= "" then out[#out + 1] = cname end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do collect_names_in(children[i], depth + 1, out, limit) end
  end
end
local function norm_name(s)
  s = tostring(s or ""):lower()
  s = s:gsub("%s+", "")
  return s
end
function Adapter:near_names(name, limit)
  limit = limit or 8
  local out = {}
  if game == nil or game.GetClientUIRoots == nil then return out end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then return out end
  local all = {}
  for i = 1, #roots do collect_names_in(roots[i], 0, all, 2000) end
  local want = norm_name(name)
  if want == "" then return out end
  for i = 1, #all do
    local have = norm_name(all[i])
    if have == want or have:find(want, 1, true) or want:find(have, 1, true) then
      out[#out + 1] = all[i]
      if #out >= limit then break end
    end
  end
  return out
end
local function control_by_path(roots, path)
  local idx = {}
  for seg in tostring(path):gmatch("%d+") do idx[#idx + 1] = tonumber(seg) end
  if #idx == 0 then return nil end
  local cur = roots[idx[1]]
  for i = 2, #idx do
    if cur == nil then return nil end
    local kids = cur:GetChildren()
    if kids == nil then return nil end
    cur = kids[idx[i]]
  end
  return cur
end
function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._floor_slots = nil
  self._floor_faces = nil
  self._floor_layout = nil
  self.controls = {}
  self._subtree_dirty = true
  self._baked_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1
  if self.cfg and self.cfg.debug_lookup and print then
    print(PREFIX .. "控件名缓存作废（第 " .. tostring(self._lookup_gen) .. " 代）："
      .. tostring(why))
  end
end
function Adapter:drop_lookup(name)
  if name == nil then return end
  self.controls[name] = nil
  if self._misses ~= nil then self._misses[name] = nil end
end
local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname ~= nil and idx[cname] == nil then idx[cname] = ctrl end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end
local STATIC_PATH_655 = {
  ["root"] = "root",
  ["art641.home"] = "root/art641.home",
  ["art647.home.settle.shadow"] = "root/art641.home/art647.home.settle.shadow",
  ["art647.home.settle.yellow.shadow"] = "root/art641.home/art647.home.settle.yellow.shadow",
  ["art647.home.settle.yellow.edge"] = "root/art641.home/art647.home.settle.yellow.edge",
  ["art647.home.settle.yellow"] = "root/art641.home/art647.home.settle.yellow",
  ["art647.home.settle.outline"] = "root/art641.home/art647.home.settle.outline",
  ["art647.home.settle.outline.tri.top"] = "root/art641.home/art647.home.settle.outline.tri.top",
  ["art647.home.settle.outline.tri.bottom"] = "root/art641.home/art647.home.settle.outline.tri.bottom",
  ["art647.home.settle.ribbon"] = "root/art641.home/art647.home.settle.ribbon",
  ["art647.home.settle.ribbon.tri.top"] = "root/art641.home/art647.home.settle.ribbon.tri.top",
  ["art647.home.settle.ribbon.tri.bottom"] = "root/art641.home/art647.home.settle.ribbon.tri.bottom",
  ["art641.select"] = "root/art641.select",
  ["art642.select.buttons"] = "root/art641.select/art642.select.buttons",
  ["art647.select.settle.shadow"] = "root/art641.select/art642.select.buttons/art647.select.settle.shadow",
  ["art647.select.settle.yellow.shadow"] = "root/art641.select/art642.select.buttons/art647.select.settle.yellow.shadow",
  ["art647.select.settle.yellow.edge"] = "root/art641.select/art642.select.buttons/art647.select.settle.yellow.edge",
  ["art647.select.settle.yellow"] = "root/art641.select/art642.select.buttons/art647.select.settle.yellow",
  ["art647.select.settle.outline"] = "root/art641.select/art642.select.buttons/art647.select.settle.outline",
  ["art647.select.settle.outline.tri.top"] = "root/art641.select/art642.select.buttons/art647.select.settle.outline.tri.top",
  ["art647.select.settle.outline.tri.bottom"] = "root/art641.select/art642.select.buttons/art647.select.settle.outline.tri.bottom",
  ["art647.select.settle.ribbon"] = "root/art641.select/art642.select.buttons/art647.select.settle.ribbon",
  ["art647.select.settle.ribbon.tri.top"] = "root/art641.select/art642.select.buttons/art647.select.settle.ribbon.tri.top",
  ["art647.select.settle.ribbon.tri.bottom"] = "root/art641.select/art642.select.buttons/art647.select.settle.ribbon.tri.bottom",
  ["art647.select.diamond.left"] = "root/art641.select/art642.select.buttons/art647.select.diamond.left",
  ["art647.select.diamond.right"] = "root/art641.select/art642.select.buttons/art647.select.diamond.right",
  ["art641.game"] = "root/art641.game",
  ["settle.btn"] = "root/settle.btn",
  ["tpl.ruler"] = "root/tpl.ruler",
  ["assets"] = "root/assets",
  ["row.1.1"] = "root/assets/row.1.1",
  ["row.1.2"] = "root/assets/row.1.2",
  ["row.1.3"] = "root/assets/row.1.3",
  ["row.1.4"] = "root/assets/row.1.4",
  ["row.1.5"] = "root/assets/row.1.5",
  ["row.2.clue"] = "root/assets/row.2.clue",
  ["row.2.1"] = "root/assets/row.2.1",
  ["row.2.2"] = "root/assets/row.2.2",
  ["row.2.3"] = "root/assets/row.2.3",
  ["row.2.4"] = "root/assets/row.2.4",
  ["row.2.5"] = "root/assets/row.2.5",
  ["row.2.6"] = "root/assets/row.2.6",
  ["row.3.1"] = "root/assets/row.3.1",
  ["row.3.2"] = "root/assets/row.3.2",
  ["row.3.3"] = "root/assets/row.3.3",
  ["row.3.4"] = "root/assets/row.3.4",
  ["row.3.5"] = "root/assets/row.3.5",
  ["row.3.6"] = "root/assets/row.3.6",
  ["row.4.1"] = "root/assets/row.4.1",
  ["row.4.2"] = "root/assets/row.4.2",
  ["row.4.3"] = "root/assets/row.4.3",
  ["row.4.4"] = "root/assets/row.4.4",
  ["row.4.5"] = "root/assets/row.4.5",
  ["row.4.6"] = "root/assets/row.4.6",
  ["clues"] = "root/clues",
  ["clues.bg"] = "root/clues/clues.bg",
  ["clues.grid"] = "root/clues/clues.grid",
  ["tpl.cell.face"] = "root/tpl.cell.face",
  ["tpl.cell"] = "root/tpl.cell",
  ["tpl.stage"] = "root/tpl.stage",
  ["stage"] = "root/stage",
  ["board.bg"] = "root/stage/board.bg",
  ["board.floors"] = "root/stage/board.floors",
  ["floor.cell.1.1"] = "root/stage/board.floors/floor.cell.1.1",
  ["floor.cell.1.2"] = "root/stage/board.floors/floor.cell.1.2",
  ["floor.cell.1.3"] = "root/stage/board.floors/floor.cell.1.3",
  ["floor.cell.1.4"] = "root/stage/board.floors/floor.cell.1.4",
  ["floor.cell.1.5"] = "root/stage/board.floors/floor.cell.1.5",
  ["floor.cell.1.6"] = "root/stage/board.floors/floor.cell.1.6",
  ["floor.cell.2.1"] = "root/stage/board.floors/floor.cell.2.1",
  ["floor.cell.2.2"] = "root/stage/board.floors/floor.cell.2.2",
  ["floor.cell.2.3"] = "root/stage/board.floors/floor.cell.2.3",
  ["floor.cell.2.4"] = "root/stage/board.floors/floor.cell.2.4",
  ["floor.cell.2.5"] = "root/stage/board.floors/floor.cell.2.5",
  ["floor.cell.2.6"] = "root/stage/board.floors/floor.cell.2.6",
  ["floor.cell.3.1"] = "root/stage/board.floors/floor.cell.3.1",
  ["floor.cell.3.2"] = "root/stage/board.floors/floor.cell.3.2",
  ["floor.cell.3.3"] = "root/stage/board.floors/floor.cell.3.3",
  ["floor.cell.3.4"] = "root/stage/board.floors/floor.cell.3.4",
  ["floor.cell.3.5"] = "root/stage/board.floors/floor.cell.3.5",
  ["floor.cell.3.6"] = "root/stage/board.floors/floor.cell.3.6",
  ["floor.cell.4.1"] = "root/stage/board.floors/floor.cell.4.1",
  ["floor.cell.4.2"] = "root/stage/board.floors/floor.cell.4.2",
  ["floor.cell.4.3"] = "root/stage/board.floors/floor.cell.4.3",
  ["floor.cell.4.4"] = "root/stage/board.floors/floor.cell.4.4",
  ["floor.cell.4.5"] = "root/stage/board.floors/floor.cell.4.5",
  ["floor.cell.4.6"] = "root/stage/board.floors/floor.cell.4.6",
  ["floor.cell.5.1"] = "root/stage/board.floors/floor.cell.5.1",
  ["floor.cell.5.2"] = "root/stage/board.floors/floor.cell.5.2",
  ["floor.cell.5.3"] = "root/stage/board.floors/floor.cell.5.3",
  ["floor.cell.5.4"] = "root/stage/board.floors/floor.cell.5.4",
  ["floor.cell.5.5"] = "root/stage/board.floors/floor.cell.5.5",
  ["floor.cell.5.6"] = "root/stage/board.floors/floor.cell.5.6",
  ["floor.cell.6.1"] = "root/stage/board.floors/floor.cell.6.1",
  ["floor.cell.6.2"] = "root/stage/board.floors/floor.cell.6.2",
  ["floor.cell.6.3"] = "root/stage/board.floors/floor.cell.6.3",
  ["floor.cell.6.4"] = "root/stage/board.floors/floor.cell.6.4",
  ["floor.cell.6.5"] = "root/stage/board.floors/floor.cell.6.5",
  ["floor.cell.6.6"] = "root/stage/board.floors/floor.cell.6.6",
  ["floor.cell.1.7"] = "root/stage/board.floors/floor.cell.1.7",
  ["floor.cell.2.7"] = "root/stage/board.floors/floor.cell.2.7",
  ["floor.cell.3.7"] = "root/stage/board.floors/floor.cell.3.7",
  ["floor.cell.4.7"] = "root/stage/board.floors/floor.cell.4.7",
  ["floor.cell.5.7"] = "root/stage/board.floors/floor.cell.5.7",
  ["floor.cell.6.7"] = "root/stage/board.floors/floor.cell.6.7",
  ["floor.cell.7.1"] = "root/stage/board.floors/floor.cell.7.1",
  ["floor.cell.7.2"] = "root/stage/board.floors/floor.cell.7.2",
  ["floor.cell.7.3"] = "root/stage/board.floors/floor.cell.7.3",
  ["floor.cell.7.4"] = "root/stage/board.floors/floor.cell.7.4",
  ["floor.cell.7.5"] = "root/stage/board.floors/floor.cell.7.5",
  ["floor.cell.7.6"] = "root/stage/board.floors/floor.cell.7.6",
  ["floor.cell.7.7"] = "root/stage/board.floors/floor.cell.7.7",
  ["board.rugs"] = "root/stage/board.rugs",
  ["labels"] = "root/labels",
  ["label.1"] = "root/labels/grp653.static.1.labels/label.1",
  ["label.2"] = "root/labels/grp653.static.1.labels/label.2",
  ["label.3"] = "root/labels/grp653.static.1.labels/label.3",
  ["label.4"] = "root/labels/grp653.static.1.labels/label.4",
  ["label.5"] = "root/labels/grp653.static.1.labels/label.5",
  ["label.6"] = "root/labels/grp653.static.1.labels/label.6",
  ["label.7"] = "root/labels/grp653.static.1.labels/label.7",
  ["fart.tpl"] = "root/fart.tpl",
  ["home"] = "root/home",
  ["home.title"] = "root/home/home.title",
  ["home.select"] = "root/home/home.select",
  ["home.continue"] = "root/home/home.continue",
  ["home.shop"] = "root/home/home.shop",
  ["home.bag"] = "root/home/home.bag",
  ["home.tutorial627.bg"] = "root/home/home.tutorial627.bg",
  ["home.tutorial627.ring"] = "root/home/home.tutorial627.ring",
  ["home.tutorial627.label"] = "root/home/home.tutorial627.label",
  ["home.tutorial627.hit"] = "root/home/home.tutorial627.hit",
  ["topbar"] = "root/topbar",
  ["hud.title"] = "root/topbar/hud.title",
  ["hud.timer"] = "root/topbar/hud.timer",
  ["right"] = "root/right",
  ["hud.progress"] = "root/right/hud.progress",
  ["modal"] = "root/modal",
  ["result.bg"] = "root/modal/result.bg",
  ["modal.exit"] = "root/modal/modal.exit",
  ["modal.save"] = "root/modal/modal.save",
  ["modal.settle"] = "root/modal/modal.settle",
  ["modal.cancel"] = "root/modal/modal.cancel",
  ["modal.title"] = "root/modal/modal.title",
  ["modal.body"] = "root/modal/modal.body",
  ["modal.stats"] = "root/modal/modal.stats",
  ["modal.level.selftest_theft_5x5"] = "root/modal/modal.level.selftest_theft_5x5",
  ["modal.level.case_001"] = "root/modal/modal.level.case_001",
  ["modal.level.case_002"] = "root/modal/modal.level.case_002",
  ["modal.level.case_003"] = "root/modal/modal.level.case_003",
  ["result.next"] = "root/modal/result.next",
  ["result.exit"] = "root/modal/result.exit",
  ["result.home"] = "root/modal/result.home",
  ["result.settle"] = "root/modal/result.settle",
  ["win"] = "root/modal/win",
  ["win.1"] = "root/modal/win/win.1",
  ["win.2"] = "root/modal/win/win.2",
  ["win.3"] = "root/modal/win/win.3",
  ["win.4"] = "root/modal/win/win.4",
  ["win.result"] = "root/modal/win/win.result",
  ["result.title.1"] = "root/modal/result.title.1",
  ["result.title.2"] = "root/modal/result.title.2",
  ["result.title.3"] = "root/modal/result.title.3",
  ["result.msg.1"] = "root/modal/result.msg.1",
  ["result.msg.2"] = "root/modal/result.msg.2",
  ["result.msg.3"] = "root/modal/result.msg.3",
  ["result.settle.countdown"] = "root/modal/result.settle.countdown",
  ["modal.settle.countdown"] = "root/modal/modal.settle.countdown",
  ["hex.back"] = "root/hex.back",
  ["hex.submit"] = "root/hex.submit",
  ["hex.redo"] = "root/hex.redo",
  ["hex.undo"] = "root/hex.undo",
  ["hex.hint"] = "root/hex.hint",
  ["hex.ok"] = "root/hex.ok",
  ["hex.no"] = "root/hex.no",
  ["hit.back"] = "root/hit.back",
  ["hit.submit"] = "root/hit.submit",
  ["hit.redo"] = "root/hit.redo",
  ["hit.undo"] = "root/hit.undo",
  ["hit.hint"] = "root/hit.hint",
  ["hit.ok"] = "root/hit.ok",
  ["hit.no"] = "root/hit.no",
  ["select.back"] = "root/select.back",
  ["select.card.1"] = "root/select.card.1",
  ["select.card.2"] = "root/select.card.2",
  ["select.card.3"] = "root/select.card.3",
  ["select.card.4"] = "root/select.card.4",
  ["select.card.1.info"] = "root/select.card.1.info",
  ["select.card.1.room.1"] = "root/select.card.1.room.1",
  ["select.card.1.room.2"] = "root/select.card.1.room.2",
  ["select.card.1.room.3"] = "root/select.card.1.room.3",
  ["select.card.1.room.4"] = "root/select.card.1.room.4",
  ["select.card.1.room.5"] = "root/select.card.1.room.5",
  ["select.card.1.room.6"] = "root/select.card.1.room.6",
  ["select.card.1.title"] = "root/select.card.1.title",
  ["select.card.2.info"] = "root/select.card.2.info",
  ["select.card.2.room.1"] = "root/select.card.2.room.1",
  ["select.card.2.room.2"] = "root/select.card.2.room.2",
  ["select.card.2.room.3"] = "root/select.card.2.room.3",
  ["select.card.2.room.4"] = "root/select.card.2.room.4",
  ["select.card.2.room.5"] = "root/select.card.2.room.5",
  ["select.card.2.room.6"] = "root/select.card.2.room.6",
  ["select.card.2.title"] = "root/select.card.2.title",
  ["select.card.3.info"] = "root/select.card.3.info",
  ["select.card.3.room.1"] = "root/select.card.3.room.1",
  ["select.card.3.room.2"] = "root/select.card.3.room.2",
  ["select.card.3.room.3"] = "root/select.card.3.room.3",
  ["select.card.3.room.4"] = "root/select.card.3.room.4",
  ["select.card.3.room.5"] = "root/select.card.3.room.5",
  ["select.card.3.room.6"] = "root/select.card.3.room.6",
  ["select.card.3.title"] = "root/select.card.3.title",
  ["select.card.4.info"] = "root/select.card.4.info",
  ["select.card.4.room.1"] = "root/select.card.4.room.1",
  ["select.card.4.room.2"] = "root/select.card.4.room.2",
  ["select.card.4.room.3"] = "root/select.card.4.room.3",
  ["select.card.4.room.4"] = "root/select.card.4.room.4",
  ["select.card.4.room.5"] = "root/select.card.4.room.5",
  ["select.card.4.room.6"] = "root/select.card.4.room.6",
  ["select.card.4.title"] = "root/select.card.4.title",
  ["select.page"] = "root/select.page",
  ["select.title"] = "root/select.title",
  ["hit.select.back"] = "root/hit.select.back",
  ["hit.select.prev"] = "root/hit.select.prev",
  ["hit.select.next"] = "root/hit.select.next",
  ["hit.select.card.1"] = "root/hit.select.card.1",
  ["hit.select.card.2"] = "root/hit.select.card.2",
  ["hit.select.card.3"] = "root/hit.select.card.3",
  ["hit.select.card.4"] = "root/hit.select.card.4",
  ["things"] = "root/things",
  ["furn.chair"] = "root/things/furn.chair",
  ["furn.plant"] = "root/things/furn.plant",
  ["furn.statue"] = "root/things/furn.statue",
  ["furn.table.h2"] = "root/things/furn.table.h2",
  ["furn.table.v2"] = "root/things/furn.table.v2",
  ["furn.shelf"] = "root/things/furn.shelf",
  ["furn.rug"] = "root/things/furn.rug",
  ["furn.rug.2"] = "root/things/furn.rug.2",
  ["furn.rug.3"] = "root/things/furn.rug.3",
  ["furn.rug.4"] = "root/things/furn.rug.4",
  ["furn.rug.5"] = "root/things/furn.rug.5",
  ["furn.plant.2"] = "root/things/furn.plant.2",
  ["select.card.1.result"] = "root/select.card.1.result",
  ["select.card.2.result"] = "root/select.card.2.result",
  ["select.card.3.result"] = "root/select.card.3.result",
  ["select.card.4.result"] = "root/select.card.4.result",
  ["settle.btn.countdown"] = "root/settle.btn.countdown",
  ["clues.help617"] = "root/clues.help617",
  ["clues.help627.hit"] = "root/clues.help627.hit",
  ["td.home"] = "root/td.home",
  ["td.home.page.1"] = "root/td.home/td.home.page.1",
  ["td.l1"] = "root/td.l1",
  ["td.l1.page.1"] = "root/td.l1/td.l1.page.1",
  ["td.l1.page.2"] = "root/td.l1/td.l1.page.2",
  ["td.l1.page.3"] = "root/td.l1/td.l1.page.3",
  ["td.l1.page.4"] = "root/td.l1/td.l1.page.4",
  ["td.l1.page.5"] = "root/td.l1/td.l1.page.5",
  ["td.l1.page.6"] = "root/td.l1/td.l1.page.6",
  ["td.l1.page.7"] = "root/td.l1/td.l1.page.7",
  ["td.l1.page.8"] = "root/td.l1/td.l1.page.8",
  ["td.l2"] = "root/td.l2",
  ["td.l2.page.1"] = "root/td.l2/td.l2.page.1",
  ["td.l2.page.2"] = "root/td.l2/td.l2.page.2",
  ["td.l2.page.3"] = "root/td.l2/td.l2.page.3",
  ["td.l2.page.4"] = "root/td.l2/td.l2.page.4",
  ["help617"] = "root/help617",
  ["help617.bg"] = "root/help617/help617.bg",
  ["help617.title"] = "root/help617/help617.title",
  ["help617.body"] = "root/help617/help617.body",
  ["help617.close"] = "root/help617/help617.close",
  ["help617.close.hit"] = "root/help617/help617.close.hit",
  ["hint635.menu"] = "root/hint635.menu",
  ["hint635.menu.bg"] = "root/hint635.menu/hint635.menu.bg",
  ["hint635.menu.title"] = "root/hint635.menu/hint635.menu.title",
  ["hint635.menu.position"] = "root/hint635.menu/hint635.menu.position",
  ["hint635.menu.clue"] = "root/hint635.menu/hint635.menu.clue",
  ["hint635.menu.close"] = "root/hint635.menu/hint635.menu.close",
  ["hint635.menu.position.hit"] = "root/hint635.menu/hint635.menu.position.hit",
  ["hint635.menu.clue.hit"] = "root/hint635.menu/hint635.menu.clue.hit",
  ["hint635.menu.close.hit"] = "root/hint635.menu/hint635.menu.close.hit",
  ["hint635.result"] = "root/hint635.result",
  ["hint635.result.bg"] = "root/hint635.result/hint635.result.bg",
  ["hint635.result.body"] = "root/hint635.result/hint635.result.body",
  ["hint635.result.close"] = "root/hint635.result/hint635.result.close",
  ["hint635.result.close.hit"] = "root/hint635.result/hint635.result.close.hit",
  ["block640.modal"] = "root/block640.modal",
  ["block640.modal.hit"] = "root/block640.modal/block640.modal.hit",
  ["block640.confirm"] = "root/block640.confirm",
  ["block640.confirm.hit"] = "root/block640.confirm/block640.confirm.hit",
  ["block640.home"] = "root/block640.home",
  ["block640.home.hit"] = "root/block640.home/block640.home.hit",
  ["block640.l1"] = "root/block640.l1",
  ["block640.l1.hit"] = "root/block640.l1/block640.l1.hit",
  ["block640.l2"] = "root/block640.l2",
  ["block640.l2.hit"] = "root/block640.l2/block640.l2.hit",
}
local function path_lookup_655(roots, name)
  local route = STATIC_PATH_655[name]
  if route == nil then
    if name == "art641.select" then
      route = "root/art641.select"
    elseif name == "art642.select.frames" then
      route = "root/art641.select/art642.select.frames"
    elseif name == "grp653.static.1.art642.select.frames" then
      route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames"
    elseif name:match("^art647%.select%.card%.%d+%.paper$") then
      route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames/" .. name
    elseif name == "select.thumb.pool" then
      route = "root/select.thumb.pool"
    elseif name:match("^select%.card%.%d+%.boardbg$")
        or name:match("^select%.card%.%d+%.cell%.")
        or name:match("^select%.card%.%d+%.wall%.")
        or name:match("^select%.card%.%d+%.door%.") then
      route = "root/select.thumb.pool/" .. name
    else
      return nil
    end
    STATIC_PATH_655[name] = route
  end
  -- 首次使用时把紧凑字符串路径拆成数组并回写，后续查找不再解析。
  if type(route) == "string" then
    local parts = {}
    for seg in route:gmatch("[^/]+") do parts[#parts + 1] = seg end
    STATIC_PATH_655[name] = parts
    route = parts
  end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(function() return cur.name end)
    if ok and rn == route[1] then
      for k = 2, #route do
        local parent = cur
        local good, child = pcall(function() return parent:GetChild(route[k]) end)
        if not good or child == nil then cur = nil; break end
        cur = child
      end
      if cur ~= nil then
        local good, actual = pcall(function() return cur.name end)
        if good and actual == name then return cur end
      end
    end
  end
  return nil
end
function Adapter:_build_name_index(roots)
  local idx = {}
  local n = 0
  for i = 1, #roots do n = index_in(roots[i], 0, idx, n) end
  self._name_idx = idx
  self._name_idx_at = self.clock
  self._name_idx_gen = self._lookup_gen
  self._name_idx_builds = (self._name_idx_builds or 0) + 1
  self._name_idx_nodes = n
  return idx
end
function Adapter:_index_lookup(name, roots)
  local idx = self._name_idx
  local walked = false
  -- 655: 结构代数变化立即重建；同一代数内最多每 1.0 秒复核一次，
  -- 既消除逐帧全树 DFS，又保留客户端迟到控件/自行重建的自愈能力。
  local stale = idx == nil or self._name_idx_gen ~= self._lookup_gen
    or self._name_idx_at == nil or (self.clock - self._name_idx_at) >= 1.0
  if stale then
    idx = self:_build_name_index(roots); walked = true
  end
  local hit = idx[name]
  if hit ~= nil then
    local ok, got = pcall(function() return hit.name end)
    if ok and got == name then return hit end
  end
  -- 698：有效索引中的缺项也是有效结果；不为每个缺失名字重新扫描。
  -- TTL/结构代数负责刷新，失效句柄则单独重建一次。
  if hit ~= nil and not walked then
    idx = self:_build_name_index(roots)
    return idx[name]
  end
  return nil
end
function Adapter:prefetch(names)
  if type(names) ~= "table" or #names == 0 then return 0 end
  if self.cfg and (self.cfg.find_index == false or self.cfg.prefetch == false) then return 0 end
  if game == nil or game.GetClientUIRoots == nil then return 0 end
  local need = false
  local miss = self._misses
  for i = 1, #names do
    local nm = names[i]
    if nm ~= nil and self.controls[nm] == nil then
      local st = miss and miss[nm]
      if st == nil or (st ~= false and self.clock >= st) then need = true; break end
    end
  end
  if not need then return 0 end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or not roots then return 0 end
  self._idx_trust = true
  for i = 1, #names do
    if names[i] ~= nil then pcall(self.find, self, names[i]) end
  end
  self._idx_trust = false
  return 1
end
function Adapter:find(name)
  local hit0 = self.controls[name]
  if hit0 ~= nil then return hit0 end
  local miss = self._misses
  if miss ~= nil then
    local stamp = miss[name]
    if stamp ~= nil then
      if stamp == false or self.clock < stamp then return nil end
    end
  end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    if self.cfg == nil or self.cfg.find_index ~= false then
      local hit = path_lookup_655(roots, name)
      if hit == nil then hit = self:_index_lookup(name, roots) end
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    else
      for i = 1, #roots do
        local hit = find_in(roots[i], name, 0)
        if hit then
          self.controls[name] = hit
          self:_note_lookup_hit(name)
          return hit
        end
      end
    end
    local pm = self.cfg.path_map
    local path = pm and pm[name]
    if path then
      local hit = control_by_path(roots, path)
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    end
  end
  if self._lookup_hits > 0 then
    if self._misses == nil then self._misses = {} end
    local ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil then
      self._misses[name] = self.clock + ttl      
    elseif old == false or self.clock >= old then
      self._misses[name] = self.clock + ttl                 
    end
  end
  return nil
end
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty = true
  end
end
function Adapter:sub(parent_id, child_name)
  if child_name=="face" and parent_id:match("^cell%.%d+%.%d+$") then
    local slot=self:_floor_slot(parent_id)
    if slot then return self:_fixed_floor_face(parent_id, slot) end
  end
  do
    local miss = self._sub_miss
    if miss ~= nil then
      local mk = parent_id .. "." .. child_name
      if miss[mk] == self._lookup_gen then return nil end
    end
  end
  local key = parent_id .. "." .. child_name
  local cached = self.subs[key]
  if cached ~= nil and cached ~= false then return cached end
  local parent = self:find(parent_id)
  if parent == nil then return nil end
  local hit = nil
  if parent.GetChild ~= nil then
    pcall(function() hit = parent:GetChild(child_name) end)
  end
  local roots = (self.cfg.cells and self.cfg.cells.sub_roots)
    or { "content", "root", "body" }
  if hit == nil then
    for i = 1, #roots do
      local mid = nil
      if parent.GetChild ~= nil then
        pcall(function() mid = parent:GetChild(tostring(roots[i])) end)
      end
      if mid ~= nil and mid.GetChild ~= nil then
        pcall(function() hit = mid:GetChild(child_name) end)
        if hit ~= nil then break end
      end
    end
  end
  if hit == nil and parent.FindChild ~= nil then
    for i = 1, #roots do
      for _, sep in ipairs({ "/", "." }) do
        local p = tostring(roots[i]) .. sep .. tostring(child_name)
        pcall(function() hit = parent:FindChild(p) end)
        if hit ~= nil then break end
      end
      if hit ~= nil then break end
    end
  end
  if hit == nil and child_name == "face" and type(parent_id) == "string"
     and parent_id:match("^cell%.") ~= nil and self._ensure_cell_face ~= nil then
    pcall(function() hit = self:_ensure_cell_face(parent_id, parent) end)
  end
  if hit ~= nil then
    self.subs[key] = hit
  else
    if self._lookup_gen ~= nil then
      self._sub_miss = self._sub_miss or {}
      self._sub_miss[key] = self._lookup_gen
    end
  end
  return hit
end
function Adapter:create_control(node)
  self.handlers[node.id] = node
  local ctrl = self:find(node.id)
  local AUTO_CONTAINER_KINDS = {
    container = true, panel = true, layer = true, list = true, box = true,
  }
  local function auto_prefab(ad, nd)
    if AUTO_CONTAINER_KINDS[nd.kind] then
      return ad.cfg.stage and ad.cfg.stage.prefab
    end
    if nd.icon_template == true and ad.cfg.prefab_icon ~= nil then
      return ad.cfg.prefab_icon
    end
    return ad.cfg.cells and ad.cfg.cells.prefab
  end
  local allow_auto = (self.cfg.auto_create == true)
  if ctrl == nil and allow_auto and game and game.InstantiateClientUIControl then
    local prefab = (self.cfg.prefab_of and self.cfg.prefab_of[node.id]) or nil
    if prefab == nil then prefab = auto_prefab(self, node) end
    if prefab ~= nil then
      local pname = (self.cfg.parent_of and self.cfg.parent_of[node.id]) or "stage"
      local parent = self:find(pname)
      if parent == nil and pname ~= "stage" then parent = self:find("stage") end
      if parent == nil then parent = self:find("root") end
      if parent then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = node.id end)
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= node.id then
            self:warn_once("auto:name:" .. tostring(node.id),
              "自动创建的控件改名没生效：想要 `" .. tostring(node.id) .. "`，读回来 `" .. tostring(got) .. "`。")
          end
          ctrl = obj
          self.controls[node.id] = ctrl
          self.instantiated = self.instantiated or {}
          self:invalidate_lookups("create:" .. tostring(node.id))
          self:rearm_raycast("create:" .. tostring(node.id))
          if node.image_id ~= nil then
            local function has_setimage(c)
              local has = false
              pcall(function() has = (c.SetImage ~= nil) end)
              return has
            end
            local found_name = nil
            local function find_target(c, depth)
              if c == nil or depth > 4 then return nil end
              for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
                local kid = nil
                pcall(function() kid = c:GetChild(cn) end)
                if kid ~= nil then
                  local r = find_target(kid, depth + 1)
                  if r ~= nil then found_name = cn return r end
                end
              end
              if has_setimage(c) then return c end
              local n = 0
              pcall(function() n = c:GetChildCount() end)
              for i = 0, n - 1 do
                local kid = nil
                pcall(function() kid = c:GetChild(i) end)
                if kid ~= nil then
                  local r = find_target(kid, depth + 1)
                  if r ~= nil then return r end
                end
              end
              return nil
            end
            local target = find_target(ctrl, 0)
            if target ~= nil then
              local src = nil
              pcall(function() src = target.imageSource end)
              local ok2 = pcall(function() target:SetImage(src, node.image_id) end)
              if not ok2 then pcall(function() target:SetImage(node.image_id) end) end
              if node.imageColor ~= nil then
                pcall(function() target.imageColor = node.imageColor end)
              end
              if node.imageType ~= nil then
                pcall(function() target.imageType = node.imageType end)
              end
              pcall(function() target:SetVisible(true) end)
              local readback = "?"
              pcall(function() readback = tostring(target.imageId) end)
              if print then
                print("[murdoku] 图标设图 " .. tostring(node.id)
                  .. "  imageId=" .. tostring(node.image_id)
                  .. " → 回读 " .. readback
                  .. "  经 " .. tostring(found_name or "子控件")
                  .. "  调用成功=" .. tostring(ok2))
              end
            else
              local desc = {}
              local n = 0
              pcall(function() n = ctrl:GetChildCount() end)
              for i = 0, n - 1 do
                local kid = nil
                pcall(function() kid = ctrl:GetChild(i) end)
                if kid ~= nil then
                  local nm, cnt = "?", 0
                  pcall(function() nm = tostring(kid.name) end)
                  pcall(function() cnt = kid:GetChildCount() end)
                  desc[#desc + 1] = nm .. "(" .. cnt .. ")"
                end
              end
              self:warn_once("icon:target:" .. tostring(node.id),
                "控件 `" .. tostring(node.id) .. "` 建好了，但递归 4 层也没找到带 SetImage 的控件。"
                .. "它的子控件：" .. (table.concat(desc, " ") ~= "" and table.concat(desc, " ") or "（一个都没有）"))
            end
          end
          pcall(function() self:_cells_paint(ctrl, nil, node.id, node.image_id) end)
          self.instantiated[node.id] = true
          self._auto_made = (self._auto_made or 0) + 1
        else
          self:warn_once("auto:fail:" .. tostring(node.id),
            "自动创建 `" .. tostring(node.id) .. "` 失败（模板 " .. tostring(prefab) .. "）"
            .. "err=" .. tostring(obj))
        end
      end
    end
  end
  if ctrl == nil then
    self:_note_missing(node.id)
    return nil
  end
  if node.id == "home" or node.id == "select" then
    local has = {}
    for _, k in ipairs({ "raycastTarget", "disableCursorEventPassthrough",
                          "disableKeyEventPassthrough", "interactable",
                          "blockRaycast", "showCursor" }) do
      local v = nil
      pcall(function() v = ctrl[k] end)
      has[#has + 1] = k .. "=" .. tostring(v)
    end
    print("[murdoku] 容器 " .. node.id .. " 字段： " .. table.concat(has, "  "))
    if ctrl.disableCursorEventPassthrough ~= nil then
      local o1 = pcall(function() ctrl.disableCursorEventPassthrough = false end)
      local r1 = "?"
      pcall(function() r1 = tostring(ctrl.disableCursorEventPassthrough) end)
      print("[murdoku]   容器 " .. node.id .. " 写 disableCursorEventPassthrough=false 成功="
        .. tostring(o1) .. " 回读=" .. r1)
    end  end
  if node.event ~= nil and (node.kind == "button" or node.kind == "cursor") then
    self:bind_input(node.id, node)
  end
  return ctrl
end
function Adapter:cell_id(r, c) return string.format("cell.%d.%d", r, c) end
function Adapter:cell_geometry(n)
  local g = self.cfg.cells or {}
  n = math.max(1, tonumber(n) or 5)
  local pw = g.parent_w or 733
  local ph = g.parent_h or 733
  local parent = self:find(g.parent or "board")
  if parent ~= nil and parent.GetSizeDelta ~= nil then
    local ok, w, h = pcall(function() return parent:GetSizeDelta() end)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      pw, ph = w, h
    end
  end
  local avail = math.min(pw, ph)
  local ruler = g.ruler or math.floor(avail * 0.06)      
  local area  = avail - 2 * ruler
  local pitch = math.floor(area / n)
  local gap   = g.gap or math.max(2, math.floor(pitch * 0.03))
  local size  = math.max(8, pitch - gap)
  local margin = ruler + math.floor((area - (n * pitch - gap)) / 2)
  if g.size   then size   = g.size   end
  if g.pitch  then pitch  = g.pitch  end
  if g.margin then margin = g.margin end
  return size, pitch, margin, pw, ph
end
function Adapter:cell_offset(r, c, n)
  local g = self.cfg.cells
  if g == nil then return nil end
  n = n or g.rows or g.cols or math.max(r, c)
  local size, pitch, margin, pw, ph = self:cell_geometry(n)
  local x = margin + (c - 1) * pitch + size / 2 - pw / 2
  local y = ph - margin - (r - 1) * pitch - size + size / 2 - ph / 2
  return x, y
end
function Adapter:image_target(ctrl)
  if ctrl == nil then return nil end
  local found_name = nil
  local function has_setimage(c)
    local has = false
    pcall(function() has = (c.SetImage ~= nil) end)
    return has
  end
  local function usable(c)
    if c == nil or not has_setimage(c) then return false end
    local src = nil
    pcall(function() src = c.imageSource end)
    return src ~= nil
  end
  local function dive(c, depth)
    if c == nil or depth > 4 then return nil end
    for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
      local kid = nil
      pcall(function() kid = c:GetChild(cn) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then found_name = cn return r end
      end
    end
    if usable(c) then return c end
    if has_setimage(c) then return c end
    local n = 0
    pcall(function() n = c:GetChildCount() end)
    for i = 0, n - 1 do
      local kid = nil
      pcall(function() kid = c:GetChild(i) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then return r end
      end
    end
    return nil
  end
  local t = dive(ctrl, 0)
  return t, found_name
end
function Adapter:set_image_deep(ctrl, image_id, image_type, image_color, label)
  if ctrl == nil then return false, "没有控件", "?" end
  local target, found = self:image_target(ctrl)
  if target == nil then
    return false, "找不到可设图的子控件", "?"
  end
  local okcall = false
  local src = nil
  pcall(function() src = target.imageSource end)
  okcall = pcall(function() target:SetImage(src, image_id) end)
  if not okcall then
    okcall = pcall(function() target:SetImage(image_id) end)
  end
  if image_type  ~= nil then pcall(function() target.imageType  = image_type  end) end
  if image_color ~= nil then pcall(function() target.imageColor = image_color end) end
  local rid, rcol = "?", "?"
  pcall(function() rid  = tostring(target.imageId)   end)
  local tint_ok = nil
  if image_color ~= nil then
    local want = tonumber(image_color) or 0
    local wr = math.floor(want / 65536) % 256
    local wg = math.floor(want / 256) % 256
    local wb = want % 256
    local wa = math.floor(want / 16777216) % 256
    tint_ok = false
    local v = nil
    pcall(function() v = target.imageColor end)
    if type(v) == "number" then
      local gr = math.floor(v / 65536) % 256
      local gg = math.floor(v / 256) % 256
      local gb = v % 256
      tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
      rcol = tostring(v)
    elseif v ~= nil then
      local gr, gg, gb, ga = nil, nil, nil, nil
      pcall(function() gr = v.r end)
      pcall(function() gg = v.g end)
      pcall(function() gb = v.b end)
      pcall(function() ga = v.a end)
      rcol = "(" .. tostring(gr) .. "," .. tostring(gg) .. "," .. tostring(gb)
        .. "," .. tostring(ga) .. ")"
      if type(gr) == "number" and type(gg) == "number" and type(gb) == "number" then
        tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
        if type(ga) == "number" and math.abs(ga - wa) > 2 then tint_ok = false end
      end
    else
      rcol = "nil（读不到 imageColor）"
    end
  else
    pcall(function() rcol = tostring(target.imageColor) end)
  end
  local hit = (rid == tostring(image_id))
  if print and label ~= nil then
    print("[murdoku] 设图 " .. tostring(label)
      .. "  imageId=" .. tostring(image_id)
      .. " → 回读 " .. rid
      .. "  imageColor 回读 " .. rcol
      .. "  染色成功=" .. tostring(tint_ok)
      .. "  经 " .. tostring(found or "根")
      .. "  调用成功=" .. tostring(okcall)
      .. "  真的设上了=" .. tostring(hit))
  end
  return hit, (found or "根"), rid, tint_ok
end
function Adapter:_cells_signal(v)
  local targets = {}
  local c = self:find("cell.1.1")
  if c ~= nil then
    if c.GetChild ~= nil then
      local ok, f = pcall(function() return c:GetChild("face") end)
      if ok and f ~= nil then targets[#targets + 1] = f end       
    end
    targets[#targets + 1] = c                                      
  end
  local t = self:find("tray.A")
  if t ~= nil and t.GetChild ~= nil then
    local ok, f = pcall(function() return t:GetChild("face") end)
    if ok and f ~= nil then targets[#targets + 1] = f end
  end
  if game ~= nil and game.GetClientUIRoots ~= nil then
    local ok, roots = pcall(game.GetClientUIRoots)
    if ok and type(roots) == "table" and roots[1] ~= nil then
      targets[#targets + 1] = roots[1]
    end
  end
  for i = 1, #targets do
    local x = targets[i]
    if x.SetSizeDelta ~= nil then
      local ok = pcall(function() x:SetSizeDelta(v, v) end)
      if ok then return true end
    end
  end
  return false
end
function Adapter:diagnose_grid(rows, cols)
  if print == nil then return end
  local g = self.cfg.cells or {}
  local print_ = print
  print_("[murdoku] ===== 逐格自检（实测，不猜）=====")
  local parent = self:find(g.parent or "board")
  if parent == nil then
    print_("[murdoku] 找不到父控件 " .. tostring(g.parent or "board") .. " —— 后面的都查不了")
    print_("[murdoku] ===== 逐格自检结束 =====")
    return
  end
  local kids = nil
  pcall(function() kids = parent:GetChildren() end)
  local on_tree = {}
  local kid_names = {}
  if type(kids) == "table" then
    for i = 1, #kids do
      local nm = "?"
      pcall(function() nm = tostring(kids[i].name) end)
      on_tree[nm] = kids[i]
      kid_names[#kid_names + 1] = nm
    end
  end
  print_("[murdoku] " .. tostring(g.parent or "board") .. " 树上实际有 "
    .. #kid_names .. " 个子控件：" .. table.concat(kid_names, " "))
  local missing_on_tree, missing_as_ctrl = {}, {}
  local n_new, n_edit = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = on_tree[id]
      if ctrl == nil then
        missing_on_tree[#missing_on_tree + 1] = id
      end
      local via_find = self:find(id)
      if via_find == nil then missing_as_ctrl[#missing_as_ctrl + 1] = id end
      if self.instantiated and self.instantiated[id] then n_new = n_new + 1
      elseif ctrl ~= nil then n_edit = n_edit + 1 end
    end
  end
  local function describe(id)
    local ctrl = on_tree[id]
    local pos, size, vis, act = "?", "?", "?", "?"
    if ctrl ~= nil then
      pcall(function()
        local a, b = ctrl:GetAnchoredPosition()
        if type(a) == "table" then pos = string.format("(%.0f,%.0f)", a.x or 0, a.y or 0)
        elseif a ~= nil then pos = string.format("(%.0f,%.0f)", a, b or 0) end
      end)
      if pos == "?" then
        pcall(function()
          local ax, ay = ctrl.anchoredPositionX, ctrl.anchoredPositionY
          if ax ~= nil then pos = string.format("(%.0f,%.0f)", ax, ay or 0) end
        end)
      end
      pcall(function()
        local w, h = ctrl:GetSizeDelta()
        if type(w) == "table" then size = string.format("%.0fx%.0f", w.x or 0, w.y or 0)
        elseif w ~= nil then size = string.format("%.0fx%.0f", w, h or 0) end
      end)
      pcall(function() vis = tostring(ctrl.visible) end)
      pcall(function() act = tostring(ctrl.active) end)
    end
    local origin = (self.instantiated and self.instantiated[id]) and "脚本建的" or "编辑器摆的"
    return "  " .. id .. "  " .. origin
      .. "  位置=" .. pos .. "  尺寸=" .. size
      .. "  visible=" .. vis .. "  active=" .. act
      .. (on_tree[id] == nil and "   ← **不在 " .. tostring(g.parent or "board") .. " 下**" or "")
  end
  if #missing_on_tree > 0 then
    print_("[murdoku] ⚠️ 这些格子在 " .. tostring(g.parent or "board") .. " 下**根本找不到**：" .. table.concat(missing_on_tree, " "))
  end
  if #missing_as_ctrl > 0 then
    print_("[murdoku] ⚠️ 这些格子 `find` 也取不到：" .. table.concat(missing_as_ctrl, " "))
  end
  print_("[murdoku] 来源统计：脚本建的 " .. n_new .. " 个，编辑器摆的 " .. n_edit
    .. " 个（合计 " .. (n_new + n_edit) .. " / " .. (rows * cols) .. "）")
  print_("[murdoku] 第一行逐格：")
  for c = 1, cols do print_(describe(self:cell_id(1, c))) end
  if #missing_on_tree > 0 or #missing_as_ctrl > 0 then
    print_("[murdoku] 其余有问题的格子：")
    local listed = {}
    for _, id in ipairs(missing_on_tree) do
      if not listed[id] then listed[id] = true; print_(describe(id)) end
    end
    for _, id in ipairs(missing_as_ctrl) do
      if not listed[id] then listed[id] = true; print_(describe(id)) end
    end
  end
  do
    local want = {
      "face", "text", "note", "x", "obj",
      "wall.up", "wall.down", "wall.left", "wall.right",
      "door.up", "door.down", "door.left", "door.right",
    }
    local function list_cell(probe, why)
      local have, miss = {}, {}
      for i = 1, #want do
        local s = self:sub(probe, want[i])
        if s ~= nil then have[#have + 1] = s else miss[#miss + 1] = want[i] end
      end
      print_("[murdoku] --- 格子里的子控件清单（" .. probe .. "，" .. why .. "）---")
      if #have == 0 then
        print_("[murdoku]   ⚠️ 一个都没找到。若你把它们装进了中间容器，容器名必须是 "
          .. "content / root / body 之一（配置项 cfg.cells.sub_roots）。")
      end
      for i = 1, #have do
        local s = have[i]
        local nm, vis, it, iid = "?", "?", "?", "?"
        pcall(function() nm = tostring(s.name) end)
        pcall(function() vis = tostring(s.visible) end)
        pcall(function() it = tostring(s.imageType) end)
        pcall(function() iid = tostring(s.imageId) end)
        print_("  " .. string.format("%-12s", nm)
          .. " visible=" .. string.format("%-5s", vis)
          .. " imageType=" .. string.format("%-26s", it)
          .. " imageId=" .. iid)
      end
      if #miss > 0 then
        print_("[murdoku]   没有配的：" .. table.concat(miss, " "))
      end
    end
    list_cell("cell.1.1", "角格：up/left 本来就该亮，分不清是谁设的")
    if rows >= 2 and cols >= 2 then
      list_cell("cell.2.2", "内部格：四邻都有 ⇒ 四面墙只可能来自脚本")
    else
      print_("[murdoku]   （本关只有 " .. rows .. "×" .. cols .. " 格，没有内部格可对照 —— "
        .. "角格分不清「脚本设的」和「模板默认」，这一条判不了。）")
    end
    print_("[murdoku]   （**静态引用大多不支持拉伸** —— 需要拉伸的地方请选「底板」类素材；"
      .. "imageType 显示 Stretch 才说明这个素材支持，Basic 就只能按原样铺。）")
    do
      local probe = (rows >= 2 and cols >= 2) and "cell.2.2" or "cell.1.1"
      local function idx_of(c)
        local v = "?"
        if c ~= nil then pcall(function() v = c:GetSiblingIndex() end) end
        return tostring(v)
      end
      local function f0(v) return (type(v) == "number") and string.format("%.0f", v) or "?" end
      local function geom_of(c)
        if c == nil then return "（取不到这个子控件）" end
        local ax, ay, bx, by, x, y, w, h = nil, nil, nil, nil, nil, nil, nil, nil
        pcall(function() ax, ay = c.anchorMinX, c.anchorMinY end)
        pcall(function() bx, by = c.anchorMaxX, c.anchorMaxY end)
        pcall(function() x, y = c.anchoredPositionX, c.anchoredPositionY end)
        pcall(function() w, h = c.sizeDeltaX, c.sizeDeltaY end)
        if w == nil then pcall(function() w, h = c:GetSizeDelta() end) end
        if x == nil then
          pcall(function()
            local a, b = c:GetAnchoredPosition()
            if type(a) == "table" then x, y = a.x, a.y else x, y = a, b end
          end)
        end
        return "anchorMin=(" .. f0(ax) .. "," .. f0(ay) .. ")"
          .. " anchorMax=(" .. f0(bx) .. "," .. f0(by) .. ")"
          .. " 位置=(" .. f0(x) .. "," .. f0(y) .. ")"
          .. " 尺寸=" .. f0(w) .. "x" .. f0(h)
      end
      local face = self:sub(probe, "face")
      local wu = self:sub(probe, "wall.up")
      print_("[murdoku] --- 层序/锚点实测（" .. probe .. "，判「白色 face 是否盖住墙」）---")
      print_("[murdoku]   face     兄弟索引=" .. idx_of(face) .. "  " .. geom_of(face))
      print_("[murdoku]   wall.up  兄弟索引=" .. idx_of(wu) .. "  " .. geom_of(wu))
      print_("[murdoku]   （判读：引擎是「**索引大的画在上面**」⇒ face 的索引 **大于** wall.up"
        .. " ⇒ 白色 face 把墙**盖住**了（不是没设上）；若 wall.up 取不到或位置/尺寸是 0，"
        .. "则是墙**根本没摆上去**。两种症状长得一样，只能靠这三行分开。）")
    end
    if type(self.edges_needed) == "table" then
      local lack = {}
      for edge in pairs(self.edges_needed) do
        if self:sub("cell.1.1", edge) == nil then lack[#lack + 1] = edge end
      end
      table.sort(lack)
      if #lack > 0 then
        print_("[murdoku] ⚠️ **本关需要这些边，但模板里没有对应的子控件**（所以画不出来）："
          .. table.concat(lack, " "))
        print_("[murdoku]    补法：在模板的 `content` 里加同名图片子控件（"
          .. "`wall.up`/`wall.down`/`wall.left`/`wall.right`、`door.*`），"
          .. "**四个方向的墙要各自一个子控件**，不能只配一个。")
      else
        local need = {}
        for edge in pairs(self.edges_needed) do need[#need + 1] = edge end
        table.sort(need)
        print_("[murdoku] ✅ 本关需要的墙/门边，模板里都配了对应子控件：" .. table.concat(need, " "))
      end
    end
  end
  local parked = self.cells_parked
  if type(parked) == "table" and #parked > 0 then
    print_("[murdoku] 已挪出画布的引用控件（确认位置真的到 200000 了吗）：")
    for i = 1, #parked do print_(describe(parked[i])) end
    local again = self.cells_parked_again or 0
    if again > 0 then
      print_("[murdoku]   （另有 " .. again .. " 次「同一个控件」的重复登记，已按控件身份去重 —— "
        .. "进 N 次关卡不会多出 N 行，也**不会**多出控件）")
    end
  end
  print_("[murdoku] ===== 逐格自检结束 =====")
end
function Adapter:_cells_beacon_button(v)
  local names = { "cell.1.1", "tray.A", "board" }
  for i = 1, #names do
    local c = self:find(names[i])
    if c ~= nil and c.SetSizeDelta ~= nil then
      local ok = pcall(function() c:SetSizeDelta(v, v) end)
      if ok then return true end
    end
  end
  return false
end
function Adapter:_cells_report(code)
  local map = { [1] = 80, [3] = 100, [4] = 40, [5] = 60 }
  self:_cells_signal(map[code] or (120 + code * 10))
end
function Adapter:_ref_index_of(ctrl)
  if ctrl == nil then return nil end
  local r = nil
  pcall(function() r = ctrl.referencedPrefabIndex end)
  if type(r) == "number" and r > 0 then return r end
  return nil
end
function Adapter:_note_parked(name, ctrl)
  if name == nil then return false end
  self.cells_parked = self.cells_parked or {}
  self.cells_parked_seen = self.cells_parked_seen or {}
  local key = ctrl or name       
  if self.cells_parked_seen[key] then
    self.cells_parked_again = (self.cells_parked_again or 0) + 1
    return false
  end
  self.cells_parked_seen[key] = true
  self.cells_parked[#self.cells_parked + 1] = name
  return true
end
function Adapter:_park_control(ctrl)
  if ctrl == nil then return false end
  local ok = false
  if ctrl.SetAnchoredPosition ~= nil then
    if pcall(function() ctrl:SetAnchoredPosition(200000, 200000) end) then ok = true end
  end
  if ctrl.SetSizeDelta ~= nil then
    pcall(function() ctrl:SetSizeDelta(0, 0) end)
  end
  if ctrl.SetVisible ~= nil then
    pcall(function() ctrl:SetVisible(false) end)
  end
  return ok
end
function Adapter:_cells_prefabs(g)
  local out, seen = {}, {}
  local function add(idx, from)
    if type(idx) ~= "number" or idx <= 0 then return end
    if seen[idx] then return end
    seen[idx] = true
    out[#out + 1] = { index = idx, from = from }
  end
  add(g.prefab, "cfg.cells.prefab")
  local probe_id = g.probe or "cell.1.1"
  local base_idx = nil
  do
    local c = self:find(probe_id)
    if c ~= nil then
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok and type(p) == "number" and p > 0 then base_idx = p end
    end
  end
  self.cells_probe_missing = (base_idx == nil)
  local names = g.prefab_from
    or { probe_id, "tpl.cell", "cell.tpl", "cell.prefab" }
  for i = 1, #names do
    local c = self:find(tostring(names[i]))
    if c ~= nil then
      local r = self:_ref_index_of(c)
      if r ~= nil then add(r, tostring(names[i]) .. ".referencedPrefabIndex") end
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok then add(p, tostring(names[i])) end
    end
  end
  if g.auto_scan ~= false and game ~= nil and game.GetClientUIRoots ~= nil then
    local found = {}
    local ok, roots = pcall(game.GetClientUIRoots)
    if ok and type(roots) == "table" then
      local function walk(c, depth)
        if c == nil or depth > 8 or #found > 400 then return end
        local p = nil
        pcall(function() p = c.prefabIndex end)
        if type(p) == "number" and p > 0 and p ~= base_idx and not seen[p] then
          local nm = "?"
          pcall(function() nm = tostring(c.name) end)
          found[#found + 1] = { index = p, name = nm }
        end
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do walk(kids[i], depth + 1) end
        end
      end
      for i = 1, #roots do walk(roots[i], 0) end
    end
    for i = 1, #found do
      add(found[i].index, "扫描到 " .. found[i].name)
    end
  end
  return out
end
function Adapter:_cells_paint(ctrl, size, cell_id, img)
  if ctrl == nil then return false end
  local face = nil
  if cell_id ~= nil then
    pcall(function() face = self:sub(cell_id, "face") end)
  end
  if face == nil and ctrl.GetChild ~= nil then
    pcall(function() face = ctrl:GetChild("face") end)       
  end
  if face == nil then return false end
  if face.SetVisible then pcall(function() face:SetVisible(true) end) end
  if cell_id ~= nil then
    self:_repaint_cell_overlays(cell_id)
  end
  if size == nil and ctrl.GetSizeDelta ~= nil then
    local w, h = nil, nil
    pcall(function() w, h = ctrl:GetSizeDelta() end)
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      size = math.min(w, h)
    end
  end
  if size ~= nil and face.SetSizeDelta then
    pcall(function() face:SetSizeDelta(size, size) end)
  end
  if face.SetAnchoredPosition then pcall(function() face:SetAnchoredPosition(0, 0) end) end
  local use_img = img or (self.cfg.cells and self.cfg.cells.face_image) or 106053
  if face.SetImage then
    local ok = pcall(function() face:SetImage(nil, use_img) end)
    if not ok then pcall(function() face:SetImage(use_img) end) end       
  end
  local vis, iid = "?", "?"
  pcall(function() vis = tostring(face.visible) end)
  pcall(function() iid = tostring(face.imageId) end)
  if self.cfg.cells and self.cfg.cells.debug_paint ~= false then
    self:warn_once("cells:paint",
      "格子底图已设置：face(visible=" .. vis .. ", imageId=" .. iid .. ")"
      .. "（如果画面上棋盘还是不出现，就把这行贴给我）")
  end
  return true
end
function Adapter:_cells_stamp(target, ref)
  if target == nil or ref == nil then return false end
  if target.GetChild == nil or ref.GetChild == nil then return false end
  local my_face, ref_face
  pcall(function() my_face  = target:GetChild("face") end)
  pcall(function() ref_face = ref:GetChild("face") end)
  if my_face == nil or ref_face == nil then return false end
  if my_face.SetImage == nil then return false end
  local src, id, col
  pcall(function() src = ref_face.imageSource end)
  pcall(function() id  = ref_face.imageId end)
  if id == nil then return false end
  local ok = pcall(function() my_face:SetImage(src, id) end)
  pcall(function() col = ref_face.imageColor end)
  if col ~= nil then pcall(function() my_face.imageColor = col end) end
  return ok
end
function Adapter:ensure_widgets(count)
  count = count or 8
  if game == nil or game.InstantiateClientUIControl == nil then
    return 0, "环境没有 game.InstantiateClientUIControl"
  end
  local bar = self:find("selbar")
  if bar == nil then
    local cprefab = self.cfg.stage and self.cfg.stage.prefab
    if cprefab == nil then return 0, "没有 cfg.stage.prefab（没有容器模板）" end
    local cparent = self:find("stage")
    if cparent == nil then return 0, "找不到父容器 stage" end
    local ok, obj = pcall(game.InstantiateClientUIControl, cprefab, cparent)
    if not ok or obj == nil then
      return 0, "容器模板 " .. tostring(cprefab) .. " 实例化失败（它可能不是「客户端控件模板」）"
    end
    pcall(function() obj.name = "selbar" end)
    self.controls["selbar"] = obj
    self.instantiated = self.instantiated or {}
    self.instantiated["selbar"] = true
    bar = obj
  end
  local prefab = self.cfg.cells and self.cfg.cells.prefab
  if prefab == nil then return 0, "没有 cfg.cells.prefab（没有按钮模板）" end
  local made, existed = 0, 0
  for i = 1, count do
    local id = "selbtn." .. tostring(i)
    if self:find(id) ~= nil then
      existed = existed + 1
    else
      local ok, obj = pcall(game.InstantiateClientUIControl, prefab, bar)
      if ok and obj then
        pcall(function() obj.name = id end)
        local got = nil
        pcall(function() got = tostring(obj.name) end)
        if got ~= id then
          self:warn_once("selbtn:name:" .. id,
            "选关按钮改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。")
        end
        self.controls[id] = obj
        self.instantiated = self.instantiated or {}
        self.instantiated[id] = true
        made = made + 1
      end
    end
  end
  local hide_selbar = function(c)
    if c == nil then return end
    pcall(function() c:SetVisible(false) end)
  end
  if bar ~= nil then hide_selbar(bar) end
  for i = 1, count do
    local c = nil
    pcall(function() c = self:find("selbtn." .. tostring(i)) end)
    hide_selbar(c)
  end
  if print then
    local rb = "?"
    pcall(function() rb = tostring(bar and bar.visible) end)
    local r1 = "?"
    pcall(function() local c = self:find("selbtn.1") if c then r1 = tostring(c.visible) end end)
    local rt = "?"
    pcall(function() local c = self:find("tpl-container") if c then rt = tostring(c.visible) end end)
    print("[murdoku] 选关条创建后已隐藏：selbar=" .. rb .. "  selbtn.1=" .. r1 .. "  tpl-container=" .. rt)
  end
  return made, nil, existed
end
function Adapter:ensure_cells(rows, cols)
  local g = self.cfg.cells
  if g == nil then return 0 end
  self.cells_ok, self.cells_made, self.cells_total = false, 0, rows * cols
  self.cells_rows, self.cells_cols = rows, cols
  for rr=1,math.max(8,rows,cols) do for cc=1,math.max(8,rows,cols) do
    if rr>rows or cc>cols then
      local id=self:cell_id(rr,cc)
      local slot=self:_floor_slot(id)
      if slot then slot:SetVisible(false) end
      if self._floor_layout then self._floor_layout[id]=nil end
    end
  end end
  local parent = self:find(g.parent or "board")
  if parent == nil then
    self:warn_once("cells:parent",
      "生成格子失败：找不到父控件 " .. tostring(g.parent or "board"))
    self:_cells_report(5)
    return 0
  end
  do
    local names = {}
    for r = 1, rows do
      for c = 1, cols do names[#names + 1] = self:cell_id(r, c) end
    end
    names[#names + 1] = "tpl.cell"; names[#names + 1] = "cell.tpl"; names[#names + 1] = "cell.prefab"
    self:prefetch(names)
  end
  local moved = 0
  if type(g.prefab) == "number" and g.prefab > 0 then
    for r = 1, rows do
      for c = 1, cols do
        local id = self:cell_id(r, c)
        local ctrl = self:find(id)
        if ctrl ~= nil and not (self.instantiated and self.instantiated[id]) then
          local hit = (self:_ref_index_of(ctrl) == g.prefab)
          if not hit then
            local p = nil
            pcall(function() p = ctrl.prefabIndex end)
            hit = (p == g.prefab)
          end
          if hit then
            local newname = "__tpl_ref_" .. id
            local ok = pcall(function() ctrl.name = newname end)
            if ok then
              self:drop_lookup(id)              
              self.controls[newname] = ctrl
              self:_park_control(ctrl)          
              self:_note_parked(newname, ctrl)  
              moved = moved + 1
            end
          end
        end
      end
    end
  end
  if moved > 0 and print then
    print("[murdoku] 有 " .. moved .. " 个格子位置的控件其实是**模板引用控件本身**"
      .. "（索引 == cfg.cells.prefab）→ 已改名让位（__tpl_ref_*）并隐藏，"
      .. "脚本会在这些位置**真的生成格子副本**")
  end
  do
    local hide_names = {}
    if type(g.prefab_from) == "table" then
      for i = 1, #g.prefab_from do hide_names[#hide_names + 1] = tostring(g.prefab_from[i]) end
    end
    for _, n in ipairs({ "tpl.cell", "cell.tpl", "cell.prefab" }) do
      hide_names[#hide_names + 1] = n
    end
    local hid = 0
    for i = 1, #hide_names do
      local n = hide_names[i]
      if n ~= (g.probe or "cell.1.1") then           
        local c = self:find(n)
        if c ~= nil then
          if self:_park_control(c) then
            self:_note_parked(n, c)       
            hid = hid + 1
          end
        end
      end
    end
    if hid > 0 and print then
      print("[murdoku] 已把 " .. hid .. " 个模板引用控件**挪出画布**"
        .. "（它们只是模板的引用，不该出现在棋盘上）")
    end
  end
  local missing = 0
  self.cells_preexisting = {}
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      if self:find(id) == nil then
        missing = missing + 1
      else
        self.cells_preexisting[id] = true
      end
    end
  end
  if missing == 0 then
    self.cells_ok = true
    self.cells_index = nil
    self.cells_made = 0
    self.cells_total = rows * cols
  end
  local prefab = nil
  local prefab_from = nil
  local tried = {}
  if missing > 0 then
    if game == nil or game.InstantiateClientUIControl == nil then
      self:_cells_report(4)           
      return 0
    end
    local cands = self:_cells_prefabs(g)
    if #cands == 0 then
      self:warn_once("cells:prefab",
        "缺 " .. missing .. " 个格子，但读不到任何控件模板索引。\n"
        .. "       两个办法任选：\n"
        .. "       ① 在编辑器里右键 cell.1.1 →【另存为模板】，"
        .. "再从那个模板**新建一个控件**放到 board 下、改名 `tpl.cell`（位置随意，脚本会藏起来）；\n"
        .. "       ② 照 docs/控件坐标表-1600x900.md 把格子手动摆齐（脚本就不再生成）。")
      self:_cells_report(1)           
      return 0
    end
    for i = 1, #cands do
      local c = cands[i]
      local ok, obj = pcall(game.InstantiateClientUIControl, c.index, parent)
      tried[#tried + 1] = tostring(c.index) .. "(" .. c.from .. ")"
      if ok and obj ~= nil then
        prefab, prefab_from = c.index, c.from
        if game.DestroyClientUIControl ~= nil then
          local dok = pcall(game.DestroyClientUIControl, obj)
          if print then
            print("[murdoku] 模板索引 " .. tostring(c.index) .. " 验证通过（试造成功），"
              .. "探针已" .. (dok and "销毁" or "**销毁失败**（不影响生成）")
              .. " —— 25 个格子都会走同一条正常路径")
          end
        end
        break
      end
    end
    if prefab == nil then
      self:warn_once("cells:inst",
        "有 " .. missing .. " 个格子还没建，试过 " .. #cands .. " 个模板索引"
        .. "（" .. table.concat(tried, "、") .. "）**全部实例化失败**（返回 nil）。\n"
        .. "       ⚠️ 注意：**右键「另存为模板」存出来的索引不算数**。\n"
        .. "       官方硬约束：除「客户端控件容器画布中的控件」和「**客户端控件模板**中的控件」外，\n"
        .. "       其他控件都是**服务器控件**，其模板索引**无法被客户端脚本调用**。\n"
        .. "       正确入口：界面控件组管理 → 界面控件组库 → **客户端控件模板**\n"
        .. "                 →【添加客户端控件】→ 加一个预设按钮、配好子控件 → **存为模板**\n"
        .. "       然后二选一：\n"
        .. "         ① 把该模板的「控件模板索引 ID」填进 cfg.cells.prefab（最稳，脚本会最先试它）；\n"
        .. "         ② 或把该模板放进容器画布、改名 tpl.cell（脚本会扫到它的索引）。")
      self:_cells_report(1)
      return 0
    end
    if print then
      print("[murdoku] 格子模板索引 " .. tostring(prefab)
        .. "（来自 " .. tostring(prefab_from) .. "）可用；缺 " .. missing .. " 个格子，开始补建")
    end
  end
  local first_err = nil
  local made = 0
  local ref = self:find(g.probe or "cell.1.1")    
  if ref == nil and made > 0 then
    self:warn_once("cells:noref",
      "没有参照格子（" .. tostring(g.probe or "cell.1.1") .. "），"
      .. "所以**不做图片盖章** —— 生成的格子外观**完全取自模板快照**。\n"
      .. "       这是纯模板模式的正常代价。如果副本看不见，去模板里补底图后**重存一次模板**。")
  end
  local n = math.max(rows, cols)
  local cell_size = self:cell_geometry(n)
  local layer_cells, layer_subs = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = self:find(id)
      if ctrl == nil then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = id end)
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= id then
            self:warn_once("cells:name:" .. id,
              "改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。\n"
              .. "       这个副本会**找不到**（也会挡住后面的同名格子），记下这一条备用。")
          end
          self.controls[id] = obj
          self.instantiated = self.instantiated or {}
          self.instantiated[id] = true
          ctrl = obj
          made = made + 1
          self:_cells_stamp(ctrl, ref)      
          self:_cells_paint(ctrl, cell_size, id)
        elseif first_err == nil then
          first_err = tostring(obj)
        end
      elseif g.stamp_existing == true then
        self:_cells_stamp(ctrl, ref)        
      end
      if ctrl ~= nil and g.force_position ~= false then
        self:open_click_passthrough(id)
        local n_layer = self:enforce_layers(id)
        layer_cells = layer_cells + 1
        layer_subs = layer_subs + (tonumber(n_layer) or 0)
        if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
        if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
        if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
        if ctrl.SetSizeDelta then
          pcall(function() ctrl:SetSizeDelta(cell_size, cell_size) end)
        end
        local x, y = self:cell_offset(r, c, n)
        if ctrl.SetAnchoredPosition and x ~= nil then
          pcall(function() ctrl:SetAnchoredPosition(x, y) end)
          self:_sync_floor(id,ctrl)
        end
        -- ★ 685：记下本格中心，标记层复用同一组数值（与 n / 家具尺寸无关）
        self._cell_pos = self._cell_pos or {}
        self._cell_pos[id] = { x, y, cell_size }
        self._board_n = n
        local kids = { "face", "x" }
        for i = 1, #kids do
          local k = self:sub(id, kids[i])
          if k ~= nil then
            if k.SetSizeDelta then pcall(function() k:SetSizeDelta(cell_size, cell_size) end) end
            if k.SetAnchoredPosition then pcall(function() k:SetAnchoredPosition(0, 0) end) end
            if k.SetPivot then pcall(function() k:SetPivot(0.5, 0.5) end) end
          end
        end
      end
    end
  end
  if made == 0 and first_err ~= nil then     
    self:warn_once("cells:inst",
      "有 " .. missing .. " 个格子还没建，想自动生成但失败了"
      .. "（模板索引 " .. tostring(prefab) .. "，接口返回 " .. first_err .. "）。\n"
      .. "       这通常是因为那个索引**不是客户端控件模板**，不能直接实例化。正确做法：\n"
      .. "       ① 界面控件组管理 → 界面控件组库 → **客户端控件模板** →【添加客户端控件】\n"
      .. "          → 加一个预设按钮、配好子控件 → **存为模板**；\n"
      .. "       ② **关键一步**：在容器画布里新建一个「**模板引用控件**」去**引用**那张模板\n"
      .. "          （**不能**用模板直接新建控件，那不算）；\n"
      .. "       ③ 把它的 `referencedPrefabIndex`（不是 `prefabIndex`！）填进\n"
      .. "          lua/entry_client_script.lua 的 cfg.cells.prefab，重新打包同步。\n"
      .. "       （也可以照 docs/控件坐标表-1600x900.md 把格子手动摆齐，脚本就不再生成。）")
    self:_cells_signal(100)         
  elseif g.debug_signal ~= false then
    if not self:_cells_signal(40 + made * 8) then
      self:warn_once("cells:signal", "诊断信号写入失败：一个可改尺寸的控件都没找到")
    end
  end
  if print then
    local have = 0
    for r = 1, rows do
      for c = 1, cols do
        if self:find(self:cell_id(r, c)) ~= nil then have = have + 1 end
      end
    end
    print("[murdoku] 棋盘格子：" .. have .. " / " .. (rows * cols) .. " 存在"
      .. "（本次新建 " .. made .. " 个，模板索引 " .. tostring(prefab) .. "）")
    self.cells_ok = (have >= rows * cols)
    self.cells_index = prefab
    self.cells_made = made
    self.cells_total = rows * cols
  end
  do
    local cleared = 0
    for k in pairs(self.subs) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then
        self.subs[k] = nil
        cleared = cleared + 1
      end
    end
    if self._sub_miss ~= nil then
      for k in pairs(self._sub_miss) do
        if type(k) == "string" and k:sub(1, 5) == "cell." then
          self._sub_miss[k] = nil
        end
      end
    end
  end
  if print then
    if layer_cells == 0 then
      print("[murdoku] 图层顺序：本次进关**没有排过层序**（cfg.cells.force_position=false，"
        .. "或者这一关一个格子都没有）")
    elseif layer_subs == 0 then
      print("[murdoku] 图层顺序：对 " .. layer_cells .. " 个格子排过层序，"
        .. "但**一个子控件都没排上**（layer_order 里的名字一个都取不到）"
        .. " ⇒ 层序等于没动过，「白色 face 压住墙」这类遮挡就会长这样")
    else
      print(string.format("[murdoku] 图层顺序：对 %d 个格子排过层序，子控件成功置底 %d 个（平均 %.1f/格）",
        layer_cells, layer_subs, layer_subs / layer_cells))
    end
  end
  pcall(function()
    for r = 1, rows do
      for c = 1, cols do
        local cid = self:cell_id(r, c)
        local ctrl2 = self:find(cid)
        if ctrl2 ~= nil then self:_ensure_cell_face(cid, ctrl2) end
      end
    end
  end)
  pcall(function()
    if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
      self._furn_prefabs = self:_furn_prefab_map()
      self._furn_tpl_ok = (self._furn_prefabs ~= nil and next(self._furn_prefabs) ~= nil)
      self:_furn_try_all()
    end
  end)
  -- ★ 685：建格完成后立刻把标记层复位到 stage 末尾
  self:_mark_layer_raise()
  return made
end
local DECOR = {
  ["home.tutorial627.bg"] = true,
  ["home.tutorial627.ring"] = true,
  ["home.tutorial627.label"] = true,
  ["home.tutorial627.hit"] = true,
  ["clues.help617"] = true,
  ["clues.help627.hit"] = true,
  ["board.floors"] = true, ["board.rugs"] = true,
  label = true, bg = true, pic = true, icon = true,
  face = true, note = true, x = true, obj = true, text = true, portrait = true,
  backrop1 = true, backrop2 = true, badge = true, letter = true, what = true, who = true,
  frame = true, card = true, art = true, image = true, img = true,
}
local MANAGED = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal",
}
local CURSOR_CONTAINERS = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal",
  "home", "select",
}
local SELF_MANAGED_TOP = {
  ["art641.home"] = true, ["art641.select"] = true, ["art641.game"] = true,
  help617 = true,
  ["block640.modal"] = true, ["block640.confirm"] = true,
  ["block640.home"] = true, ["block640.l1"] = true, ["block640.l2"] = true,
}
function Adapter:hide_unlisted(keep)
  -- ★ 686：keep = layout_plan 的 seen 集合；没有任何 cell.* ⇒ 当前不在关卡内，
  --   逐层收起 192 个标记控件，兜住首帧 / _shown 重建等没有 cell visible 下发的路径。
  do
    local in_level = false
    for k in pairs(keep or {}) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then in_level = true; break end
    end
    if not in_level then self:_mark_hide_all() else self._mark_screen_on = true end
  end
  local hidden = 0
  local skipped_self = 0
  for i = 1, #MANAGED do
    local parent = self:find(MANAGED[i])
    if parent ~= nil and parent.GetChildren ~= nil then
      local ok, kids = pcall(function() return parent:GetChildren() end)
      if ok and type(kids) == "table" then
        for k = 1, #kids do
          local child = kids[k]
          local name = nil
          pcall(function() name = child.name end)
          if name ~= nil and name ~= "" and not keep[name] and not DECOR[name] then
            if SELF_MANAGED_TOP[name] then
              skipped_self = skipped_self + 1
            elseif child.SetVisible ~= nil then
              local ok2 = pcall(function() child:SetVisible(false) end)
              if ok2 then hidden = hidden + 1 end
            end
          end
        end
      end
    end
  end
  if skipped_self > 0 and not self._said_self_managed and print then
    self._said_self_managed = true
    print("[murdoku] hide_unlisted：跳过 " .. skipped_self
      .. " 个**脚本自管的顶层容器**（teach，教程浮层 —— 显隐由 tutorial_ui 决定）")
  end
  return hidden
end
function Adapter:scale_of_style(value)
  if value == "portrait" then return 0.86             
  elseif value == "portrait.selected" then return 1.08
  elseif value == "portrait.placed" then return 0.72   
  elseif value == "clue.focus" then return 1.03
  elseif value == "tab.active" then return 1.04 end
  return nil
end
function Adapter:color_of_style(value)
  local WHITE = 4294967295             
  local RED   = 4290453793             
  if value == "card.name" then return 0xFF4A2E1C end   -- 696：白纸边缘的关卡名用深棕
  if value == "clue.who" then return RED end
  if value == "clue.what" or value == "clue" or value == "clue.ok" or value == "clue.focus" then
    return WHITE
  end
  return nil                           
end
function Adapter:_tray_btn_art(moved, names, done, miss)
  names = names or {}
  done, miss = done or 0, miss or 0
  print("[murdoku] --- 按钮底图上色（运行时）---")
  for i = 1, #names do
    local cid = names[i]
    local c = self:find(cid)
    local bg = nil
    if c ~= nil then pcall(function() bg = self:sub(cid, "bg") end) end
    if bg ~= nil then
      if bg.SetAsLastSibling then pcall(function() bg:SetAsLastSibling() end) end
      local src = nil
      pcall(function() src = bg.imageSource end)
      local ok, err = pcall(function() bg:SetImage(src, self.cfg.bg_image_id or 100108) end)
      if ok then done = done + 1 else
        miss = miss + 1
        self:warn_once("bgset:" .. cid, "底图 SetImage 失败：" .. tostring(err))
      end
      if bg.SetVisible then pcall(function() bg:SetVisible(true) end) end
      if i <= 3 then
        local it, iid = "?", "?"
        pcall(function() it = tostring(bg.imageType) end)
        pcall(function() iid = tostring(bg.imageId) end)
        print(string.format("  %-16s bg：imageType=%s imageId=%s", cid, it, iid))
      end
      moved = moved + 1
    else
      miss = miss + 1
    end
  end
  print(string.format("  SetImage 成功 %d 个，缺失/失败 %d 个", done, miss))
  print("[murdoku] --- 按钮底图上色结束 ---")
  return moved
end
function Adapter:apply_btn_art()
  if self.cfg.btn_art ~= true or print == nil then return 0 end
  local names = self.cfg.btn_list or {}
  local done, miss = 0, 0
  return self:_tray_btn_art(0, names, done, miss)
end
function Adapter:diagnose_overlap()
  local board = self:find((self.cfg.cells or {}).parent or "board")
  if board == nil then return 0 end
  local bx, by, bw, bh = nil, nil, nil, nil
  pcall(function() local p = board:GetUIPos() if p then bx, by = p.x, p.y end end)
  pcall(function() bw, bh = board:GetSizeDelta() end)
  if type(bx) ~= "number" or type(bw) ~= "number" then
    print("[murdoku] 相交诊断：**本环境拿不到控件的绝对坐标（GetUIPos 不可用）**，跳过 —— "
      .. "不再用相对坐标硬比（那会报出一堆假阳性）。")
    return 0
  end
  local x0, x1 = bx - bw / 2, bx + bw / 2
  local y0, y1 = by - bh / 2, by + bh / 2
  print(string.format("[murdoku] --- 相交诊断：棋盘 x[%.0f,%.0f] y[%.0f,%.0f] ---", x0, x1, y0, y1))
  local hits = 0
  for i = 1, #MANAGED do
    local parent = self:find(MANAGED[i])
    if parent ~= nil then
      local ok, kids = pcall(function() return parent:GetChildren() end)
      if ok and type(kids) == "table" then
        for k = 1, #kids do
          local ch = kids[k]
          local nm, vis, cx, cy, cw, chh = nil, nil, nil, nil, nil, nil
          pcall(function() nm = tostring(ch.name) end)
          pcall(function() vis = ch.visible end)
          pcall(function() local p = ch:GetUIPos() if p then cx, cy = p.x, p.y end end)
          pcall(function() cw, chh = ch:GetSizeDelta() end)
          if type(cx) == "number" and type(cw) == "number" and vis ~= false then
            if cx > x0 and cx < x1 and cy > y0 and cy < y1 then
              hits = hits + 1
              if hits <= 24 then
                print(string.format("  ⚠️ %-22s 父=%-10s 中心(%.0f,%.0f) 尺寸%.0fx%.0f",
                  tostring(nm), MANAGED[i], cx, cy, cw, chh or 0))
              end
            end
          end
        end
      end
    end
  end
  print(string.format("  与棋盘相交且显示中的控件：%d 个%s", hits,
    hits == 0 and "（干净）" or "  ← 这些就是压在棋盘上的"))
  print("[murdoku] --- 相交诊断结束 ---")
  return hits
end
function Adapter:enable_cursor()
  local n = 0
  if self._cursor ~= nil and self._cursor.done then
    return self._cursor.n or 0           
  end
  local st = self._cursor
  if st == nil then
    st = { idle = 0, done = false, n = 0 }
    self._cursor = st
  end
  self:prefetch(CURSOR_CONTAINERS)
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(function() if ctrl.showCursor ~= true then ctrl.showCursor = true end end)
      if ok then n = n + 1 end
    end
  end
  local parts = {}
  local found, all_true = 0, true           
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      found = found + 1
      local sc, kd = "?", "?"
      pcall(function() sc = tostring(ctrl.showCursor) end)
      if sc ~= "true" then all_true = false end
      pcall(function() kd = tostring(ctrl.kind) end)
      if kd == "nil" then pcall(function() kd = tostring(ctrl.Kind) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.type) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.controlType) end) end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
    else
      all_true = false
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
  st.n = n
  if found >= #CURSOR_CONTAINERS and all_true then
    st.idle = st.idle + 1
    if st.idle >= 3 then
      st.done = true
      if print and not self._cursor_done_logged then
        self._cursor_done_logged = true
        print(PREFIX .. "常驻光标：已收敛（" .. tostring(found) .. " 个容器 showCursor 全为 true）"
          .. " ⇒ 不再每 20 帧重扫；换屏/换关会重新武装")
      end
    end
  else
    st.idle = 0                             
  end
  return n
end
function Adapter:rearm_cursor(why)
  local st = self._cursor
  if st == nil then return end
  if not st.done and st.idle == 0 and st.n == 0 then return end    
  st.idle, st.done = 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "常驻光标：重新开始扫描（" .. tostring(why) .. "）")
  end
end
function Adapter:dump_names(max_depth, max_items, quiet)
  max_depth = max_depth or 6
  max_items = max_items or 400
  if game == nil or game.GetClientUIRoots == nil then
    if not quiet then self:err("dump_names：拿不到 game.GetClientUIRoots") end
    return 0
  end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then
    if not quiet then self:err("dump_names：GetClientUIRoots 失败") end
    return 0
  end
  local n = 0
  local lines = {}
  local function walk(c, depth)
    if c == nil or depth > max_depth or n >= max_items then return end
    local name, kind = "?", "?"
    pcall(function() name = tostring(c.name) end)
    pcall(function() kind = tostring(c.kind) end)
    local vis, act, pf = "?", "?", nil
    pcall(function() vis = tostring(c.visible) end)
    pcall(function() act = tostring(c.active) end)
    pcall(function() pf = c.prefabIndex end)
    n = n + 1
    if not quiet then
      local pfstr = ""
      if type(pf) == "number" and pf > 0 then pfstr = " tpl=" .. tostring(pf) end
      lines[#lines + 1] = string.rep("  ", depth) .. "- " .. name
        .. "  [" .. kind .. " vis=" .. vis .. " act=" .. act .. pfstr .. "]"
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  for i = 1, #roots do walk(roots[i], 0) end
  if not quiet and print then
    print("[murdoku] ===== 客户端控件树（脚本能看到的，共 " .. n .. " 个节点）=====")
    for i = 1, #lines do print("[murdoku] " .. lines[i]) end
    print("[murdoku] ===== 控件树结束 =====")
  end
  return n
end
function Adapter:count_names(max_depth, max_items)
  return self:dump_names(max_depth or 6, max_items or 400, true)
end
function Adapter:forget_events_of(id)
  local pre = tostring(id) .. "\1"
  local stale = nil
  for k in pairs(self.events) do
    if type(k) == "string" and k:sub(1, #pre) == pre then
      stale = stale or {}
      stale[#stale + 1] = k
    end
  end
  if stale ~= nil then
    for i = 1, #stale do self.events[stale[i]] = nil end
  end
  self.event_claim[id] = nil    
  self.event_latest[id] = nil
  self.handlers[id] = nil
end
function Adapter:destroy_control(id)
  local ctrl = self.controls[id]
  if self.instantiated and self.instantiated[id] then
    if ctrl and game and game.DestroyClientUIControl then
      pcall(function() game.DestroyClientUIControl(ctrl) end)
    end
    self.instantiated[id] = nil
    self.bound[id] = nil
    self.controls[id] = nil
    self:forget_events_of(id)
    self:invalidate_lookups("destroy:" .. tostring(id))
    return
  end
  if ctrl ~= nil then
    if ctrl.SetVisible then
      pcall(function() ctrl:SetVisible(false) end)
    elseif ctrl.SetActive then
      pcall(function() ctrl:SetActive(false) end)
    end
  end
  self:drop_lookup(id)
  self:forget_events_of(id)
end
function Adapter:read_palette()
  if self._palette ~= nil then return self._palette end
  local map, names = {}, {}
  local a = self.cfg.assets or {}
  local roots = { a.palette or "assets", a.things or "things" }
  for ri = 1, #roots do
    local root = self:find(roots[ri])
    if root ~= nil then
      local kids = nil
      pcall(function() kids = root:GetChildren() end)
      if type(kids) == "table" then
        for i = 1, #kids do
          local k = kids[i]
          local nm, src, id, col = nil, nil, nil, nil
          pcall(function() nm = tostring(k.name) end)
          pcall(function() src = k.imageSource end)
          pcall(function() id = k.imageId end)
          pcall(function() col = k.imageColor end)
          if nm ~= nil and nm ~= "" and type(id) == "number" and id > 0 then
            map[nm] = { source = src, id = id, color = col, from = roots[ri] }
            names[#names + 1] = nm
          end
        end
      end
    end
  end
  local oa = self.cfg.obj_art
  if type(oa) == "table" then
    for k, v in pairs(oa) do
      local kind = tostring(k)
      local pref = kind:match("^(obj%d*)%.") 
      if pref ~= nil then kind = kind:sub(#pref + 2) end
      local layers = nil
      if type(v) == "table" and type(v.id) == "number" then
        layers = { v }                                    
      elseif type(v) == "table" and #v > 0 then
        layers = v                                        
      end
      if layers ~= nil then
        for i = 1, #layers do
          local L = layers[i]
          local key = (i == 1 and ("obj.") or ("obj" .. i .. ".")) .. kind
          if type(L) == "table" and type(L.id) == "number" then
            local e = map[key]
            if e == nil then
              map[key] = {
                source = L.source or "StaticReference",
                id = L.id,
                color = L.color,
                w = L.w, h = L.h, dx = L.dx, dy = L.dy,
                layer = i,
                from = "cfg.obj_art",
              }
              names[#names + 1] = key
            else
              if e.w == nil then e.w = L.w end
              if e.h == nil then e.h = L.h end
              if e.dx == nil then e.dx = L.dx end
              if e.dy == nil then e.dy = L.dy end
              if e.layer == nil then e.layer = i end
            end
          end
        end
      end
    end
  end
  if next(map) ~= nil then
    self._palette = map
    self._palette_names = names
  end
  return map
end
function Adapter:resolve_asset(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n ~= nil then return { source = nil, id = n } end    
  local map = self:read_palette()
  local hit = map[tostring(value)]
  if hit ~= nil then return hit end
  self:warn_once("asset:missing:" .. tostring(value),
    "调色板里没有素材「" .. tostring(value) .. "」。\n"
    .. "       建法：在编辑器里放一个容器（默认名 `assets`），每个素材放一个**图片控件**，\n"
    .. "       控件名就是引用键（例如 `room.kitchen`），图在编辑器里配好。\n"
    .. "       当前调色板：" .. ((self._palette_names and #self._palette_names > 0)
      and table.concat(self._palette_names, " ") or "（空 —— 找不到 `assets` 容器？）"))
  return nil
end
local RAY_IDLE_STOP = 3       
local RAY_MAX_SCANS = 25      
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end     
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local before = nil
  pcall(function() before = c.raycastTarget end)
  if before == nil then return false end           
  if before == true then return true end           
  local ok = pcall(function() c.raycastTarget = true end)
  return ok == true
end
function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
    self._ray = st
  end
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, samples = 0, 0, {}
  local visited = {}
  local function walk(c, depth)
    if c == nil or depth > 20 or visited[c] then return end
    visited[c] = true
    -- 699：显式关闭的装饰层射线不能被全局扫描重新打开。
    local want = not (self._ray_want and self._ray_want[c] == false)
    local before = nil
    pcall(function() before = c.raycastTarget end)
    if before ~= nil then
      seen = seen + 1
      if before ~= want then
        local ok = pcall(function() c.raycastTarget = want end)
        if ok then
          set = set + 1
          if #samples < 6 then
            local nm = "?"
            pcall(function() nm = tostring(c.name) end)
            samples[#samples + 1] = nm .. ":" .. tostring(before) .. "->true"
          end
        end
      end
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  walk(root, 0)
  st.scans = st.scans + 1
  st.seen, st.set = seen, set
  if seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
  if seen > 0 and st.idle >= RAY_IDLE_STOP then
    st.done = true
    if print and not st.announced then
      st.announced = true
      self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
        .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
    end
  elseif st.scans >= RAY_MAX_SCANS then
    st.done = true
    self:warn_once("raycast_giveup",
      "射线开关（raycastTarget）：扫了 " .. tostring(st.scans) .. " 趟，"
      .. "一个「带该字段的控件」都没找到（seen=0）—— 停止重扫。"
      .. "⚠️ 这一条是真问题：按钮没有 raycastTarget 就**点不动**"
      .. "（「界面看得见、点哪儿都没反应」）。请核对控件树是否就绪、"
      .. "控件是不是预设按钮；换屏/换关会自动重扫一次，不必重进游戏。")
  end
  return seen, set, samples
end
function Adapter:enforce_screen_layers(screen)
  local function put(id, idx)
    local c = self:find(id)
    if c == nil then return end
    if c.SetSiblingIndex ~= nil then
      pcall(function() c:SetSiblingIndex(idx) end)
    end
  end
  if screen == "home" then
    put("select", 0)
    put("home", 20)
  elseif screen == "select" then
    put("home", 0)
    put("select", 20)
  else
    put("home", 0)
    put("select", 1)
  end
end
-- ═══════════════════════════════════════════════════════════════════════
-- ★ 685「多格家具通用构造法」：三层不变式
--   stage 内 = 格子层（cell.*）；跨格家具实例挂在各格 content/furn，尺寸 = span × 格，
--   允许越出格线；furn_anchor 把锚点格 SetAsLastSibling 抬到 stage 内最上。
--   症状：被抬高的整格连同越界家具压到邻格之上，把邻格 content/x 一起盖掉（地毯/桌子都出现过）。
--   不变式：art685.mark.overlay 恒为 stage 的最后一个子控件，X 标记全部画在它里面，
--           抬格只能发生在 stage 内部 ⇒ 结构上不存在「家具盖住 X」的绘制顺序。
--   通用性：与 kind / span_r×span_c / 缩放 / 层数 / 将来新增多少种家具完全无关；
--           新增家具照常下发 furn_tpl / furn_span / furn_offset 即可，不必再改层序表。
-- ═══════════════════════════════════════════════════════════════════════
function Adapter:_mark_layer_raise()
  local m = self._mark_layer
  if m == nil then
    m = self:find("art685.mark.overlay")
    if m == nil then return end
    self._mark_layer = m
  end
  if m.SetAsLastSibling ~= nil then
    -- 689：缓存闭包，避免每帧新建函数对象；685「每帧复位」不变式完全保留
    if self._mark_raise_target ~= m then
      self._mark_raise_target = m
      self._mark_raise_fn = function() m:SetAsLastSibling() end
    end
    pcall(self._mark_raise_fn)
  end
end
function Adapter:_mark_layer_guard()
  if self._mark_guard_done then return end
  if self:find("art685.mark.overlay") == nil then
    if self.warn_once then self:warn_once("mark:missing",
      "685 通用标记层缺失：多格家具会再次盖住 X。请把 art685.mark.overlay 挂在 stage 末尾。") end
    return
  end
  self._mark_guard_done = true
end
-- cell.<r>.<c> → art685.mark.<r>.<c>；位置/尺寸直接复用建格时记下的同一组数值
-- ═══════════════════════════════════════════════════════════════════════
-- ★ 686「X 标记离场收起」：父容器隐藏不级联，必须逐层关灯
--   685 误判：以为 stage 在 home/select 被整体隐藏时，挂在它下面的标记层会跟着消失。
--   真机反证（v308 已记录）：父容器 SetVisible 不保证级联到子控件 ⇒ 关卡内点亮的
--   X 标记会残留在新界面上。且标记层控件不在 layout_plan 的 nodes 表里，Controller 的
--   _shown 差异下发 / hide_unlisted 都不会给它们下发 visible=false ⇒ 永远没人关灯。
--   ⇒ 按项目既有范式（visible 分支里显式切 board.floors / board.rugs）逐层收起。
-- ═══════════════════════════════════════════════════════════════════════
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
function Adapter:_mark_ctrl(id)
  local rc = tostring(id):match("^cell%.(.+)$")
  if rc == nil then return nil, nil end
  local m = self:find("art685.mark." .. rc)
  if m == nil then return nil, nil end
  local p = self._cell_pos and self._cell_pos[id]
  local x, y, sz = nil, nil, nil
  if p ~= nil then
    x, y, sz = p[1], p[2], p[3]
  else
    local r, c = rc:match("^(%d+)%.(%d+)$")
    if r ~= nil then
      local n = self._board_n or math.max(tonumber(r) or 1, tonumber(c) or 1)
      x, y = self:cell_offset(tonumber(r), tonumber(c), n)
      sz = select(1, self:cell_geometry(n))
    end
  end
  if x ~= nil and m.SetAnchoredPosition ~= nil then
    pcall(function() m:SetAnchoredPosition(x, y) end)
  end
  if sz ~= nil and m.SetSizeDelta ~= nil then
    pcall(function() m:SetSizeDelta(sz, sz) end)
  end
  return m, rc
end
-- 真机父容器 SetVisible 不保证级联到子控件（v308 教训）⇒ 容器 + 两枚笔画逐层开关
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
-- 关卡切换：收起超出当前棋盘 n 的标记，避免上一关的 X 残留
function Adapter:_mark_scope()
  local n = self._board_n or 0
  if n <= 0 or n == self._mark_scope_n then return end
  self._mark_scope_n = n
  for r = 1, 8 do
    for c = 1, 8 do
      if r > n or c > n then
        self:_mark_set_visible(string.format("%d.%d", r, c), false)
      end
    end
  end
end
function Adapter:enforce_layers(cell_id)
  return 0
end
function Adapter:seal_container(id)
  local c = self:find(id)
  if c == nil then return false end
  local n = 0
  if c.disableKeyEventPassthrough ~= nil then
    if pcall(function() c.disableKeyEventPassthrough = true end) then n = n + 1 end
  end
  if c.disableCursorEventPassthrough ~= nil then
    pcall(function() c.disableCursorEventPassthrough = false end)
  end
  return n > 0
end
function Adapter:seal_cursor_shield()
  local c = nil
  pcall(function() c = self:find("xxx") end)
  if c == nil then pcall(function() c = self:find("shield") end) end
  if c == nil then
    self:warn_once("shield:missing",
      "还没建触摸遮挡层控件 `xxx`（全屏容器/光标检测区域，放在 `root` 的**第一个**子控件位）⇒ "
      .. "移动端在空白处拖动仍会让 3D 角色移动。")
    return false
  end
  local n = 0
  if c.disableCursorEventPassthrough ~= nil then
    if pcall(function() c.disableCursorEventPassthrough = true end) then n = n + 1 end
  end
  if c.showCursor ~= nil then pcall(function() c.showCursor = true end) end
  if c.raycastTarget ~= nil then pcall(function() c.raycastTarget = true end) end
  if n > 0 then
    print("[murdoku] 触摸遮挡层 `xxx`：已屏蔽点击穿透（移动端空白处拖动不再带动 3D 角色）")
  end
  return n > 0
end
function Adapter:seal_containers(list)
  if list == nil then return 0 end
  local ok = 0
  for i = 1, #list do
    if self:seal_container(list[i]) then ok = ok + 1 end
  end
  return ok
end
function Adapter:open_click_passthrough(cell_id)
  local roots = (self.cfg.cells and self.cfg.cells.sub_roots)
    or { "content", "root", "body" }
  local parent = self:find(cell_id)
  if parent == nil or parent.GetChild == nil then return false end
  local touched = false
  for i = 1, #roots do
    local mid = nil
    pcall(function() mid = parent:GetChild(tostring(roots[i])) end)
    if mid ~= nil then
      if mid.disableCursorEventPassthrough ~= nil then
        pcall(function() mid.disableCursorEventPassthrough = false end)
        touched = true
      else
        self:warn_once("passthru:" .. cell_id,
          "中间容器 `" .. tostring(roots[i]) .. "` 读不到 `disableCursorEventPassthrough`，"
          .. "改不了。请在编辑器里把它的「**屏蔽区域内点击事件穿透**」**取消勾选** ——"
          .. "否则点击到不了按钮，表现为「点格子没反应」而体检却全绿。")
      end
      pcall(function() mid.disableKeyEventPassthrough = false end)
      pcall(function() mid.showCursor = true end)
    end
  end
  return touched
end
function Adapter:_apply_edges(id, prefix, flags)
  if type(flags) ~= "table" then return true end
  local r, c = tostring(id):match("^cell%.(%d+)%.(%d+)$")
  r, c = tonumber(r), tonumber(c)
  local rows = self.cells_rows or (self.cfg.cells and self.cfg.cells.rows)
  local cols = self.cells_cols or (self.cfg.cells and self.cfg.cells.cols)
  local skip = { down = true, right = true }
  self.edges_needed = self.edges_needed or {}
  local sides = { "up", "down", "left", "right" }
  local missing_sub = {}
  local geo_n = self.cells_rows or self.cells_cols
    or (self.cfg.cells and (self.cfg.cells.rows or self.cfg.cells.cols)) or 5
  local cw, pitch = nil, nil
  pcall(function() cw, pitch = self:cell_geometry(geo_n) end)
  if type(cw) ~= "number" or cw <= 0 then cw, pitch = nil, nil end
  local ch = cw
  if cw ~= nil and (type(pitch) ~= "number" or pitch <= 0 or pitch < cw) then pitch = cw end
  if cw == nil and print and not self._edge_no_geo_noted then
    self._edge_no_geo_noted = true
    print("[murdoku] 边缘适配：**算不出格子边长**（cell_geometry(" .. tostring(geo_n)
      .. ") 返回 0/nil）⇒ 墙/门的**缩放与贴边整段跳过**（按编辑器里摆的原样显示）")
  end
      do
        local content = nil
        pcall(function() content = self:sub(id, "content") end)
        if content ~= nil then
          if content.SetAnchorMin then pcall(function() content:SetAnchorMin(0.5, 0.5) end) end
          if content.SetAnchorMax then pcall(function() content:SetAnchorMax(0.5, 0.5) end) end
          if content.SetPivot then pcall(function() content:SetPivot(0.5, 0.5) end) end
          if content.SetSizeDelta and cw ~= nil then
            pcall(function() content:SetSizeDelta(cw, ch) end)
          end
          if content.SetAnchoredPosition then pcall(function() content:SetAnchoredPosition(0, 0) end) end
        end
      end
  for i = 1, #sides do
    local s = sides[i]
    local want = (flags[s] and not skip[s]) and true or false
    if want then self.edges_needed[prefix .. "." .. s] = true end
    local sub = self:sub(id, prefix .. "." .. s)
    if sub == nil then
      if want then missing_sub[#missing_sub + 1] = prefix .. "." .. s end
    elseif sub.SetVisible ~= nil then
      pcall(function() sub:SetVisible(want) end)
    end
  end
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end
  if self.cfg.cells == nil or self.cfg.cells.edge_fit ~= false then
    local thick = (self.cfg.cells and self.cfg.cells.edge_thickness) or 8
    local door_ratio = (self.cfg.cells and self.cfg.cells.door_length_ratio) or 0.45
  local overlap = (self.cfg.cells and self.cfg.cells.edge_overlap) or 4
  local extra_len = (self.cfg.cells and self.cfg.cells.edge_extra_len) or 0
    if cw ~= nil then
      for i = 1, #sides do
        local s = sides[i]
        local sub = self:sub(id, prefix .. "." .. s)
        if sub ~= nil and flags[s] then
          local w, h = size_of(sub)
          local horiz = (s == "up" or s == "down")
          local outer = (s == "down" or s == "right")
          if s == "up" then outer = (r == nil or r <= 1) end
          if s == "left" then outer = (c == nil or c <= 1) end
          local tlen
          if prefix == "door" then
            tlen = cw * door_ratio + extra_len
          elseif outer then
            tlen = cw + thick + 4           
          else
            tlen = cw + overlap + extra_len
          end
          local tthick = thick
          local base_l = horiz and w or h       
          local base_t = horiz and h or w
          if type(base_l) == "number" and base_l > 0 and type(base_t) == "number" and base_t > 0 then
            local kl = tlen / base_l
            local kt = tthick / base_t
            if kl > 1.001 or kl < 0.999 then
              if horiz then pcall(function() sub.localScaleX = kl end)
              else pcall(function() sub.localScaleY = kl end) end
            end
            if kt > 1.001 or kt < 0.999 then
              if horiz then pcall(function() sub.localScaleY = kt end)
              else pcall(function() sub.localScaleX = kt end) end
            end
            if self.cfg.cells and self.cfg.cells.edge_fit_log ~= false then
              self._edge_fit_seen = self._edge_fit_seen or {}
              if not self._edge_fit_seen[s] then
                self._edge_fit_seen[s] = true
                if print then
                  print(string.format(
                    "[murdoku] 边缘适配 %s.%s：基准 %.0fx%.0f → 目标 %.0fx%.0f（倍率 %.2f / %.2f）",
                    prefix, s, w or 0, h or 0, horiz and tlen or tthick, horiz and tthick or tlen, kl, kt))
                end
              end
            end
          else
            if self.cfg.cells and self.cfg.cells.edge_fit_log ~= false then
              self._edge_fit_seen = self._edge_fit_seen or {}
              local skip_key = "skip:" .. prefix .. "." .. s
              if not self._edge_fit_seen[skip_key] then
                self._edge_fit_seen[skip_key] = true
                if print then
                  print(string.format(
                    "[murdoku] 边缘适配 %s.%s：**基准读成 0 / 读不到**（w=%s h=%s）"
                    .. "⇒ 缩放这一段整段跳过（贴边照做）；原因通常是子控件尺寸还没定下来，"
                    .. "或编辑器里没给它尺寸",
                    prefix, s, tostring(w), tostring(h)))
                end
              end
            end
          end
          local d = outer and (cw / 2) or (pitch / 2)
          local x, y = 0, 0
          if s == "up" then y = d
          elseif s == "down" then y = -d
          elseif s == "left" then x = -d
          else x = d end
          if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
          if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(x, y) end) end
        end
      end
    end
  end
  return #missing_sub == 0
end
local function is_cell_id(id)
  return type(id) == "string" and id:match("^cell%.%d+%.%d+$") ~= nil
end
Adapter._is_cell_id = is_cell_id
function Adapter:_fit_child_to_cell(ctrl, sub, cell_id)
  if ctrl == nil or sub == nil then return end
  if cell_id ~= nil and not is_cell_id(cell_id) then return end
  local w, h = size_of(ctrl)
  if (type(w) ~= "number" or w <= 1) and cell_id ~= nil and self.rects ~= nil then
    local r = self.rects[cell_id]
    if type(r) == "table" then w, h = r.w, r.h end
  end
  if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then return end
  self:_fit_child_sized(sub, w, h)
end
function Adapter:_fit_child_sized(sub, w, h)
  if sub == nil then return end
  if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then return end
  local marks = self._fit_marks
  if marks == nil then
    marks = setmetatable({}, { __mode = "k" })    
    self._fit_marks = marks
  end
  local m = marks[sub]
  if m ~= nil and math.abs(m.w - w) < 0.5 and math.abs(m.h - h) < 0.5 then return end
  marks[sub] = { w = w, h = h }
  if print and (self._fit_log or 0) < 10 then
    self._fit_log = (self._fit_log or 0) + 1
    print("[murdoku] 图层贴格：" .. tostring(sub.name) .. " ← 格子 " ..
      tostring(w) .. "×" .. tostring(h))
  end
  if sub.SetAnchorMin then pcall(function() sub:SetAnchorMin(0.5, 0.5) end) end
  if sub.SetAnchorMax then pcall(function() sub:SetAnchorMax(0.5, 0.5) end) end
  if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
  if sub.SetSizeDelta then pcall(function() sub:SetSizeDelta(w, h) end) end
  if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(0, 0) end) end
end
local OBJ_LAYER_SUBS = {
  "obj", "obj2", "obj3", "obj4", "obj5", "obj6",
  "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",
}    
function Adapter:obj_layers_of(want)
  if want == false or want == nil or type(want) ~= "table" then return {} end
  local out = {}
  if type(want.layers) == "table" then
    for i = 1, math.min(#want.layers, #OBJ_LAYER_SUBS) do
      local L = want.layers[i]
      if type(L) == "table" and L.id ~= nil then
        out[#out + 1] = {
          sub = OBJ_LAYER_SUBS[i],
          key = L.key or (want.key .. "#" .. i),
          src = L.src, id = L.id, color = L.color,
          w = L.w, h = L.h, dx = L.dx, dy = L.dy,
        }
      end
    end
  elseif want.id ~= nil then
    out[1] = { sub = "obj", key = want.key, src = want.src, id = want.id, color = want.color }
  end
  return out
end
function Adapter:_cell_size_of(ctrl, cell_id)
  if cell_id ~= nil and self.rects ~= nil then
    local r = self.rects[cell_id]
    if type(r) == "table" and tonumber(r.w) and tonumber(r.h) and r.w > 1 and r.h > 1 then
      local sw, sh = size_of(ctrl)
      if type(sw) == "number" and sw > 1 and math.abs(sw - r.w) > 0.5 then
        self._cellsize_logged = self._cellsize_logged or {}
        local k = tostring(cell_id)
        if not self._cellsize_logged[k] then
          self._cellsize_logged[k] = true
          if print then
            print(string.format("[murdoku] 格子尺寸：cell=%s rects=%.1f,%.1f sizeDelta=%.1f,%.1f（用 rects ✓）",
              k, r.w, r.h, sw, sh))
          end
        end
      end
      return r.w, r.h
    end
  end
  local w, h = size_of(ctrl)
  if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then return nil, nil end
  return w, h
end
function Adapter:_fit_obj_layer(sub, cw, ch, L)
  if sub == nil or cw == nil or ch == nil then return end
  local fw = tonumber(L and L.w) or 1
  local fh = tonumber(L and L.h) or 1
  local dx = tonumber(L and L.dx) or 0
  local dy = tonumber(L and L.dy) or 0
  if sub.SetAnchorMin then pcall(function() sub:SetAnchorMin(0.5, 0.5) end) end
  if sub.SetAnchorMax then pcall(function() sub:SetAnchorMax(0.5, 0.5) end) end
  if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
  if sub.SetSizeDelta then pcall(function() sub:SetSizeDelta(cw * fw, ch * fh) end) end
  if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(dx * cw, -(dy * ch)) end) end
end
function Adapter:_paint_obj(cell_id, ctrl, want, force)
  if cell_id == nil then return false end
  local layers = self:obj_layers_of(want)
  local marks = self._obj_marks
  if marks == nil then
    marks = setmetatable({}, { __mode = "k" })    
    self._obj_marks = marks
  end
  local cw, ch = nil, nil
  local all_ready = true
  for i = 1, #OBJ_LAYER_SUBS do
    local sub = self:sub(cell_id, OBJ_LAYER_SUBS[i])
    local L = layers[i]
    if sub == nil then
      if L ~= nil then all_ready = false end
    elseif L == nil then
      if sub.SetVisible then pcall(function() sub:SetVisible(false) end) end
      marks[sub] = nil
    else
      local m = marks[sub]
      local need = (force == true) or m == nil
        or m.key ~= L.key or m.id ~= L.id or m.color ~= L.color
        or m.w ~= L.w or m.h ~= L.h or m.dx ~= L.dx or m.dy ~= L.dy
      if need then
        if cw == nil and ctrl ~= nil then cw, ch = self:_cell_size_of(ctrl, cell_id) end
        if cw ~= nil then self:_fit_obj_layer(sub, cw, ch, L) end
        local src = nil
        pcall(function() src = sub.imageSource end)
        if L.src ~= nil then src = L.src end
        pcall(function() sub:SetImage(src, L.id) end)
        if L.color ~= nil then pcall(function() sub.imageColor = L.color end) end
        marks[sub] = { key = L.key, id = L.id, color = L.color,
                       w = L.w, h = L.h, dx = L.dx, dy = L.dy }
        if sub.SetActive then pcall(function() sub:SetActive(true) end) end
      end
      if sub.SetVisible then pcall(function() sub:SetVisible(true) end) end    
    end
  end
  return all_ready
end
local FURN_ART_CAP_DEFAULT = 260    
function Adapter:_furn_prefab_id()
  local cfg = self.cfg or {}
  local id = cfg.furn_prim_prefab
  if type(id) == "number" and id > 0 then return id end
  local hit = self:find("tpl.prim")
  if hit ~= nil then
    local v = nil
    pcall(function() v = hit.prefabIndex end)
    if type(v) == "number" and v > 0 then return v end
    pcall(function() v = hit.referencedPrefabIndex end)
    if type(v) == "number" and v > 0 then return v end
  end
  return nil
end
local function _num(v, d) local n = tonumber(v) return n or d end
function Adapter:_furn_destroy(ctrl)
  if ctrl == nil then return end
  if game ~= nil and game.DestroyClientUIControl ~= nil then
    pcall(game.DestroyClientUIControl, ctrl)
  elseif ctrl.Destroy ~= nil then
    pcall(function() ctrl:Destroy() end)
  end
end
local function _furn_key_of(name)
  if type(name) ~= "string" then return nil end
  local k = name:gsub(",", ".")
  k = k:gsub("^furn%.", "")
  k = k:gsub("%.", "_")
  if k == "table_1" then k = "table" end
  return k
end
function Adapter:_furn_prefab_map()
  local map = {}
  local things = self:find((self.cfg and self.cfg.furn_things_parent) or "things")
  if things ~= nil and things.GetChildren ~= nil then
    local ks = nil
    pcall(function() ks = things:GetChildren() end)
    if type(ks) == "table" then
      for i = 1, #ks do
        local ch = ks[i]
        local nm, prefab = nil, nil
        pcall(function() nm = ch.name end)
        pcall(function() prefab = ch.referencedPrefabIndex end)
        local key = _furn_key_of(nm)
        if key ~= nil and type(prefab) == "number" and prefab > 0 then
          map[key] = prefab
        end
      end
    end
  end
  local cfg_map = self.cfg and self.cfg.furn_tpl_prefab
  if type(cfg_map) == "table" then
    for k, v in pairs(cfg_map) do
      if map[k] == nil and type(v) == "number" and v > 0 then map[k] = v end
    end
  end
  return map
end
function Adapter:_face_prefab()
  local cfg = self.cfg or {}
  if type(cfg.face_tpl_prefab) == "number" and cfg.face_tpl_prefab > 0 then
    return cfg.face_tpl_prefab
  end
  local ref = self:find(cfg.face_tpl_ref or "tpl.cell.face")
  if ref ~= nil then
    local v = nil
    pcall(function() v = ref.referencedPrefabIndex end)
    if type(v) == "number" and v > 0 then return v end
  end
  return tonumber(cfg.face_tpl_fallback) or 1073747145
end
function Adapter:_ensure_cell_face(cell_id, ctrl)
  if cell_id == nil then return nil end
  local slot = self:_floor_slot(cell_id)
  if slot ~= nil then
    self:_sync_floor(cell_id, ctrl)
    return self:_fixed_floor_face(cell_id, slot)
  end
  if self:find("board.floors") ~= nil then return nil end
  self._face_guard = self._face_guard or {}
  if self._face_guard[cell_id] then return nil end
  self._face_guard[cell_id] = true
  local existing = nil
  local content0 = nil
  pcall(function() content0 = self:sub(cell_id, "content") end)
  if content0 ~= nil and content0.GetChild ~= nil then
    pcall(function() existing = content0:GetChild("face") end)
  end
  if existing ~= nil then
    self._face_guard[cell_id] = nil
    return existing
  end
  local prefab = self:_face_prefab()
  if prefab == nil or game == nil or game.InstantiateClientUIControl == nil then return nil end
  local content = nil
  pcall(function() content = self:sub(cell_id, "content") end)
  if content == nil then content = ctrl end
  if content == nil then return nil end
  local ok, obj = pcall(game.InstantiateClientUIControl, prefab, content)
  if not ok or obj == nil then
    self:warn_once("face:inst", "face 模板实例化失败（prefab=" .. tostring(prefab)
      .. " cell=" .. tostring(cell_id) .. "）⇒ 本格没有地板图，其余逻辑继续")
    self._face_guard[cell_id] = nil
    return nil
  end
  pcall(function() obj.name = "face" end)
  local cw, ch = self:_cell_size_of(ctrl, cell_id)
  pcall(function()
    if obj.SetAnchorMin then obj:SetAnchorMin(0.5, 0.5) end
    if obj.SetAnchorMax then obj:SetAnchorMax(0.5, 0.5) end
    if obj.SetPivot then obj:SetPivot(0.5, 0.5) end
    if obj.SetSizeDelta and cw ~= nil then obj:SetSizeDelta(cw, ch) end
    if obj.SetAnchoredPosition then obj:SetAnchoredPosition(0, 0) end
    if obj.SetSiblingIndex then obj:SetSiblingIndex(0) end    
    if obj.SetVisible then obj:SetVisible(true) end
  end)
  self._face_inst = self._face_inst or {}
  self._face_inst[cell_id] = obj
  self._face_guard[cell_id] = nil
  if print then
    print("[murdoku] 面层：cell=" .. tostring(cell_id) .. " 实例化 face（prefab="
      .. tostring(prefab) .. "，尺寸=" .. tostring(cw) .. "px）")
  end
  return obj
end
M.RING_IMAGE_ID = 100006
M.RING_GREEN = 0xFF4FAE5A
M.RING_RED   = 0xFFE0483A
function Adapter:_ensure_cell_ring(cell_id)
  if cell_id == nil then return nil end
  self._ring_inst = self._ring_inst or {}
  local content = nil
  pcall(function() content = self:sub(cell_id, "content") end)
  if content == nil then pcall(function() content = self:find(cell_id) end) end
  if content == nil then return nil end
  local obj = self._ring_inst[cell_id]
  if obj ~= nil and obj ~= false then
    local alive = false
    pcall(function() alive = (obj.name ~= nil) end)
    if alive then return obj end
    self._ring_inst[cell_id] = nil
  end
  obj = nil
  if content.GetChild ~= nil then
    pcall(function() obj = content:GetChild("verdict_ring") end)
    if obj ~= nil then
      self._ring_inst[cell_id] = obj
      self._ring_active = self._ring_active or {}
      self._ring_active[obj] = true
      return obj
    end
  end
  local prefab = self:_face_prefab()
  if prefab == nil or game == nil or game.InstantiateClientUIControl == nil then return nil end
  local ok, inst = pcall(game.InstantiateClientUIControl, prefab, content)
  if not ok or inst == nil then
    self:warn_once("ring:inst", "判定圈实例化失败（prefab=" .. tostring(prefab) .. "）⇒ 本关不显示红绿圈，其余逻辑继续")
    return nil
  end
  pcall(function() inst.name = "verdict_ring" end)
  local cw, ch = self:_cell_size_of(nil, cell_id)
  if cw == nil then cw, ch = 100, 100 end
  local d = math.floor(math.min(cw, ch or cw) * 0.9 + 0.5)
  pcall(function()
    if inst.SetAnchorMin then inst:SetAnchorMin(0.5, 0.5) end
    if inst.SetAnchorMax then inst:SetAnchorMax(0.5, 0.5) end
    if inst.SetPivot then inst:SetPivot(0.5, 0.5) end
    if inst.SetSizeDelta then inst:SetSizeDelta(d, d) end
    if inst.SetAnchoredPosition then inst:SetAnchoredPosition(0, 0) end
    local src = nil
    pcall(function() src = inst.imageSource end)
    if inst.SetImage then inst:SetImage(src, M.RING_IMAGE_ID) end
    if inst.SetVisible then inst:SetVisible(false) end
  end)
  pcall(function() inst.raycastTarget = false end)
  self._ring_inst[cell_id] = inst
  return inst
end
function Adapter:_paint_progress_ring(obj, amount, color)
  self._progress_ring_state = self._progress_ring_state or setmetatable({}, {__mode="k"})
  local states = self._progress_ring_state
  local st = states[obj]
  if st == nil then
    st = {}; states[obj] = st
    local ok, err = pcall(function()
      obj:SetVisible(false)
      local top = E("ImageFillRadialType.Top", nil)
      local radial = E("ImageFillType.Radial360", nil)
      local basic = E("ImageType.Basic", nil)
      assert(top ~= nil and radial ~= nil and basic ~= nil, "missing image fill enum")
      obj.imageType = basic
      obj.enableMask = true
      obj.reverseMaskArea = false
      obj.enableSoftEdge = false
      obj:SetFillRadial360(top, 0)
      obj.fillType = radial
      obj.fillRadialType = top
      obj.fillAmount = 0
      assert(obj.fillType == radial and obj.fillAmount == 0, "radial initialization readback mismatch")
    end)
    st.ready = ok
    if ok then st.radial = E("ImageFillType.Radial360", nil) end
    if not ok then self:warn_once("ring605:init", "环形填充初始化失败，已隐藏圆圈：" .. tostring(err)) end
  elseif st.ready and st.amount == nil then
    local same = false
    pcall(function() same = (st.radial ~= nil and obj.fillType == st.radial
      and obj.imageType == E("ImageType.Basic", nil)
      and obj.enableMask == true and obj.reverseMaskArea == false
      and obj.enableSoftEdge == false and obj.fillRadialType == E("ImageFillRadialType.Top", nil)) end)
    if not same then
      states[obj] = nil
      return self:_paint_progress_ring(obj, amount, color)
    end
  end
  if not st.ready then return false end
  local ok, err = pcall(function()
    if st.amount ~= amount then
      obj.fillAmount = amount
      assert(math.abs(obj.fillAmount - amount) < 0.0001, "fillAmount readback mismatch")
      st.amount = amount
    end
    if st.color ~= color then obj.imageColor = color; st.color = color end
    local visible = amount > 0
    if st.visible ~= visible then obj:SetVisible(visible); st.visible = visible end
  end)
  if not ok then
    st.ready = false
    pcall(function() obj:SetVisible(false) end)
    self:warn_once("ring605:update", "环形填充更新失败，已隐藏圆圈：" .. tostring(err))
  end
  return ok
end
function Adapter:set_verdict_ring(cell_id, ok, amount)
  local obj = self:_ensure_cell_ring(cell_id)
  if obj == nil then return nil end
  local a = tonumber(amount) or 0
  if a < 0 then a = 0 elseif a > 1 then a = 1 end
  local col = ok and M.RING_GREEN or M.RING_RED
  local used_fill = self:_paint_progress_ring(obj, a, col)
  self._ring_active = self._ring_active or {}
  self._ring_active[obj] = true
  self._ring_used_fill = used_fill
  return used_fill
end
function Adapter:_ensure_hold_ring(cell_id)
  if cell_id == nil then return nil end
  self._hold_ring_inst = self._hold_ring_inst or {}
  local content = nil
  pcall(function() content = self:sub(cell_id, "content") end)
  if content == nil then pcall(function() content = self:find(cell_id) end) end
  if content == nil then return nil end
  local obj = self._hold_ring_inst[cell_id]
  if obj ~= nil and obj ~= false then
    local alive = false
    pcall(function() alive = (obj.name ~= nil) end)
    if alive then return obj end
    self._hold_ring_inst[cell_id] = nil
  end
  obj = nil
  if content.GetChild ~= nil then
    pcall(function() obj = content:GetChild("hold_ring") end)
    if obj ~= nil then self._hold_ring_inst[cell_id] = obj; return obj end
  end
  local prefab = self:_face_prefab()
  if prefab == nil or game == nil or game.InstantiateClientUIControl == nil then return nil end
  local ok, inst = pcall(game.InstantiateClientUIControl, prefab, content)
  if not ok or inst == nil then
    self:warn_once("hold:inst", "长按圈实例化失败（prefab=" .. tostring(prefab) .. "）⇒ 本关不显示长按圈，其余逻辑继续")
    return nil
  end
  pcall(function() inst.name = "hold_ring" end)
  local cw, ch = self:_cell_size_of(nil, cell_id)
  if cw == nil then cw, ch = 100, 100 end
  local d = math.floor(math.min(cw, ch or cw) * 0.9 + 0.5)
  pcall(function()
    if inst.SetAnchorMin then inst:SetAnchorMin(0.5, 0.5) end
    if inst.SetAnchorMax then inst:SetAnchorMax(0.5, 0.5) end
    if inst.SetPivot then inst:SetPivot(0.5, 0.5) end
    if inst.SetSizeDelta then inst:SetSizeDelta(d, d) end
    if inst.SetAnchoredPosition then inst:SetAnchoredPosition(0, 0) end
    local src = nil
    pcall(function() src = inst.imageSource end)
    if inst.SetImage then inst:SetImage(src, M.RING_IMAGE_ID) end
    if inst.SetVisible then inst:SetVisible(false) end
  end)
  pcall(function() inst.raycastTarget = false end)
  self._hold_ring_inst[cell_id] = inst
  return inst
end
function Adapter:set_hold_ring(cell_id, amount)
  if self._hold_active_cell == cell_id and self._hold_amount == amount then return self._hold_used_fill end
  if self._hold_active_cell ~= cell_id then self:clear_hold_ring() end
  local obj = self:_ensure_hold_ring(cell_id)
  if obj == nil then return nil end
  local a = tonumber(amount) or 0
  if a < 0 then a = 0 elseif a > 1 then a = 1 end
  local col = 0xFFF2C94C
  local used_fill = self:_paint_progress_ring(obj, a, col)
  self._hold_active_cell, self._hold_amount = cell_id, amount
  self._hold_used_fill = used_fill
  return used_fill
end
function Adapter:clear_hold_ring()
  local id = self._hold_active_cell
  if id == nil then return end
  local obj = self._hold_ring_inst and self._hold_ring_inst[id]
  self._hold_active_cell, self._hold_amount = nil, nil
  if obj then
    self:_reset_ring_state(obj)
    pcall(function() if obj.SetVisible then obj:SetVisible(false) end end)
    pcall(function() obj.imageColor = 0 end)
  end
end
function Adapter:_reset_ring_state(obj)
  local states = self._progress_ring_state
  if not states then return end
  local st = states[obj]
  if st == nil then return end
  if st.ready then
    st.amount, st.color, st.visible = nil, nil, nil
  else
    states[obj] = nil
  end
end
function Adapter:clear_verdict_rings()
  self:clear_hold_ring()
  local active = self._ring_active
  for obj in pairs(active or {}) do
    if obj and obj ~= false then
      self:_reset_ring_state(obj)
      local hidden = pcall(function() if obj.SetVisible then obj:SetVisible(false) end end)
      local colored = pcall(function() obj.imageColor = 0 end)
      local reset = pcall(function()
        local top = E("ImageFillRadialType.Top", nil)
        if obj.SetFillRadial360 and top then obj:SetFillRadial360(top, 0) end
      end)
      if hidden and colored and reset then active[obj] = nil end
    end
  end
end
function Adapter:_apply_furn_level()
  if self._furn_inst ~= nil then
    for _, v in pairs(self._furn_inst) do self:_furn_destroy(v) end
  end
  self._furn_inst = {}
  self._furn_scaled = {}
  self._furn_ok_n = 0       
  self._furn_fail_n = 0     
  self._furn_keys = {}      
  self._furn_retry_n = 0    
  self._furn_last_try = -1
  local c = self:find((self.cfg and self.cfg.furn_parent) or "board")
  self._furn_prefabs = self:_furn_prefab_map()
  if self._furn_arch_new == nil then
    local things = self:find((self.cfg and self.cfg.furn_things_parent) or "things")
    self._furn_arch_new = (things ~= nil) or (self.cfg and self.cfg.furn_arch_new == true) or false
  end
  self._furn_tpl_ok = (self._furn_prefabs ~= nil and next(self._furn_prefabs) ~= nil)
  if print then
    local ks = {}
    for k in pairs(self._furn_prefabs or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    print("[murdoku] 家具模板映射：things 找到="
      .. tostring(self:find((self.cfg and self.cfg.furn_things_parent) or "things") ~= nil)
      .. "　条目=" .. tostring(#ks) .. "　keys={" .. table.concat(ks, ",") .. "}"
      .. "　已缓存的请求格=" .. tostring(self._furn_want ~= nil and next(self._furn_want) ~= nil))
  end
  if self._furn_tpl_ok and self._furn_level ~= false then
    if self._furn_batch then
      self._furn_try_pending = true
    else
      pcall(function() self:_furn_try_all() end)    
    end
  end
  pcall(function()
    for _, id in pairs(self.cells or {}) do
      local ctrl = self:find(id)
      if ctrl ~= nil then self:_ensure_cell_face(id, ctrl) end
    end
  end)
  if print then
    print("[murdoku] 模板化家具：关卡=" .. tostring(self._furn_level) .. "（实例缓存已清）")
  end
  return true
end
function Adapter:begin_furn_batch()
  if self.cfg and self.cfg.furn_batch == false then return end
  self._furn_batch = true
end
function Adapter:end_furn_batch()
  self._furn_batch = false
  return self:flush_furn_pending()
end
function Adapter:flush_furn_pending()
  local dirty = self._furn_dirty
  self._furn_dirty = nil
  local all = self._furn_try_pending
  self._furn_try_pending = false
  if not self._furn_tpl_ok or self._furn_level == false then return 0 end
  local n = 0
  if all then
    pcall(function() n = self:_furn_try_all() end)
  elseif dirty ~= nil then
    for id in pairs(dirty) do
      local want = self._furn_want and self._furn_want[id]
      if type(want) == "string" then
        pcall(function()
          local ctrl = self:find(id)
          if ctrl ~= nil and self:_spawn_furn_tpl(id, ctrl, want) then n = n + 1 end
        end)
      end
    end
  end
  return n
end
local function furn_mark_dirty(self, id)
  self._furn_dirty = self._furn_dirty or {}
  self._furn_dirty[id] = true
end
function Adapter:_furn_try_all()
  if not self._furn_tpl_ok then return 0 end
  if self._furn_want == nil then return 0 end
  local n = 0
  for cell_id, name in pairs(self._furn_want) do
    if type(name) == "string" then
      local ctrl = self:find(cell_id)
      if ctrl ~= nil then
        pcall(function() self:_spawn_furn_tpl(cell_id, ctrl, name) end)
        n = n + 1
      end
    end
  end
  if n > 0 and print then
    print("[murdoku] 模板化家具：本轮补造 " .. tostring(n) .. " 格（缓存里共 "
      .. tostring(n) .. " 格有家具）")
  end
  return n
end
local function _furn_cfg_key(name)
  if type(name) ~= "string" then return nil end
  local k = name:gsub("^furn%.", "")
  k = k:gsub("%.", "_")           
  if k == "table_1" then k = "table" end    
  return k
end
function Adapter:_prepare_furn_layer(cell_id, layer_name, cw, ch, force)
  local layer = self:sub(cell_id, layer_name)
  if layer == nil then return nil end
  self._furn_layer_state = self._furn_layer_state or {}
  local key = cell_id .. ":" .. layer_name
  local old = self._furn_layer_state[key]
  if force or old == nil or old.obj ~= layer or old.w ~= cw or old.h ~= ch then
    if layer.SetAnchorMin then pcall(function() layer:SetAnchorMin(0.5, 0.5) end) end
    if layer.SetAnchorMax then pcall(function() layer:SetAnchorMax(0.5, 0.5) end) end
    if layer.SetPivot then pcall(function() layer:SetPivot(0.5, 0.5) end) end
    if layer.SetSizeDelta then pcall(function() layer:SetSizeDelta(cw, ch) end) end
    if layer.SetAnchoredPosition then pcall(function() layer:SetAnchoredPosition(0, 0) end) end
    if layer.SetVisible then pcall(function() layer:SetVisible(true) end) end
    if layer.SetActive then pcall(function() layer:SetActive(true) end) end
    self._furn_layer_state[key] = {obj=layer, w=cw, h=ch}
  end
  return layer
end
function Adapter:_floor_slot(id)
  local r,c=id:match("^cell%.(%d+)%.(%d+)$")
  if not r then return nil end
  self._floor_slots=self._floor_slots or {}
  local slot=self._floor_slots[id]
  if slot then return slot end
  slot=self:find("floor.cell."..r.."."..c)
  if slot then self._floor_slots[id]=slot end
  return slot
end
function Adapter:_fixed_floor_face(id,slot)
  self._floor_faces=self._floor_faces or {}
  local cached=self._floor_faces[id]
  if cached and cached.slot==slot then return cached.face end
  local face=slot:GetChild("face")
  if face then self._floor_faces[id]={slot=slot,face=face} end
  return face
end
function Adapter:_sync_floor(id,ctrl,show)
  local slot=self:_floor_slot(id)
  if not slot or not ctrl then return end
  local x,y=ctrl:GetAnchoredPosition()
  local w,h=ctrl:GetSizeDelta()
  self._floor_layout=self._floor_layout or {}
  local old=self._floor_layout[id]
  local visible=show
  if visible==nil then visible=old and old.show end
  if visible==nil then visible=true end
  local face=self:_fixed_floor_face(id,slot)
  if not old or old.x~=x or old.y~=y or old.w~=w or old.h~=h then
    slot:SetAnchoredPosition(x,y);slot:SetSizeDelta(w,h)
  end
  if face and (not old or old.face~=face or old.w~=w or old.h~=h) then
    self:_fit_child_sized(face,w,h)
  end
  if not old or old.show~=visible or old.face~=face then
    slot:SetVisible(visible)
    if visible and slot.SetActive then slot:SetActive(true) end
    if face then
      face:SetVisible(visible)
      if visible and face.SetActive then face:SetActive(true) end
    end
  end
  old=old or {}
  old.x,old.y,old.w,old.h,old.show,old.face=x,y,w,h,visible,face
  self._floor_layout[id]=old
end
function Adapter:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,span,off)
  local parent=self:find("board.rugs")
  if not parent then return false end
  local gap=(self.cfg.cells or {}).gap or 4
  local sr,sc=_num(span.r,1),_num(span.c,1)
  local px,py=cw+gap,ch+gap
  local x,y=ctrl:GetAnchoredPosition()
  x=x+_num(off.dx,0)*px;y=y-_num(off.dy,0)*py
  local w,h=cw+(sc-1)*px,ch+(sr-1)*py
  local key=cell_id.."|"..ckey
  self._furn_inst=self._furn_inst or {}
  self._whole_rug_applied=self._whole_rug_applied or {}
  local obj=self._furn_inst[key]
  local old=self._whole_rug_applied[key]
  local show=self._furn_level~=false
  local same_values=old and old.x==x and old.y==y and old.w==w and old.h==h
  local sig=same_values and old.sig or table.concat({x,y,w,h},":")
  if obj and old and old.sig==sig and old.show==show then
    old.x,old.y,old.w,old.h=x,y,w,h
    return true
  end
  if not obj then
    old=nil
    local ok;ok,obj=pcall(game.InstantiateClientUIControl,prefab,parent)
    if not ok or not obj then
      -- 695：原型注册失败时留一条可检索日志，便于真机定位 prefab / parent。
      if print then print("[murdoku] 地毯模板实例化失败：ckey="..tostring(ckey)
        .." prefab="..tostring(prefab).." ok="..tostring(ok)
        .." parent="..tostring(parent ~= nil and parent.name or "nil")) end
      return false
    end
    obj.name="rug."..cell_id
    self._furn_inst[key]=obj
  end
  if not old or old.sig~=sig then
    local cv=(self.cfg.furn_tpl_canvas or {})[ckey] or (ckey=="rug_2" and {216,108} or ckey=="rug_3" and {108,216} or {108,108})
    local k=_num(self.cfg.furn_scale,1)*_num((self.cfg.furn_scale_by_kind or {})[ckey],1)
    local ax=(self.cfg.furn_scale_axis_by_kind or {})[ckey]
    local sx,sy=k,k
    if ax then sx,sy=_num(ax.x,1),_num(ax.y,1) end
    self:_furn_scale_layers(obj,w/cv[1]*sx,h/cv[2]*sy)
    obj:SetAnchorMin(0.5,0.5);obj:SetAnchorMax(0.5,0.5);obj:SetPivot(0.5,0.5)
    obj:SetSizeDelta(w,h);obj:SetAnchoredPosition(x,y)
  end
  obj:SetVisible(show);if obj.SetActive then obj:SetActive(show) end
  old=old or {}
  old.sig,old.show,old.x,old.y,old.w,old.h=sig,show,x,y,w,h
  self._whole_rug_applied[key]=old
  return true
end
function Adapter:_spawn_furn_tpl(cell_id, ctrl, name)
  if cell_id == nil or type(name) ~= "string" then return false end
  local cfg = self.cfg or {}
  local prefabs = self._furn_prefabs or self:_furn_prefab_map()
  local ckey = _furn_cfg_key(name)
  local prefab = ckey ~= nil and prefabs[ckey] or nil
  if prefab == nil then
    self._furn_prefabs = self:_furn_prefab_map()
    prefabs = self._furn_prefabs
    prefab = ckey ~= nil and prefabs[ckey] or nil
  end
  if prefab == nil then
    self._furn_fail_n = (self._furn_fail_n or 0) + 1
    local key = "furnmiss:" .. tostring(ckey)
    if print then
      local once = self._furn_miss_logged or {}
      self._furn_miss_logged = once
      if not once[key] then
        once[key] = true
        local names = {}
        for k in pairs(prefabs or {}) do names[#names + 1] = k end
        table.sort(names)
        print("[murdoku] 家具模板缺映射：模板键=" .. tostring(name) .. " → 归一化键=" .. tostring(ckey)
          .. "　当前映射 keys={" .. table.concat(names, ",") .. "}"
          .. "　things 找到=" .. tostring(self:find((self.cfg and self.cfg.furn_things_parent) or "things") ~= nil))
      end
    end
    return false
  end
  if game == nil or game.InstantiateClientUIControl == nil then
    self._furn_tpl_ok = false
    self._furn_fail_n = (self._furn_fail_n or 0) + 1
    if print then
      print("[murdoku] 家具模板：环境没有 InstantiateClientUIControl（cell=" .. tostring(cell_id) .. "）")
    end
    return false
  end
  local cw, ch = self:_cell_size_of(ctrl, cell_id)
  if cw == nil then return false end           
  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3"
     or ckey=="rug_4" or ckey=="rug_5" then
    -- 694：恢复整块地毯模板实例化（688/689/690 真机可显示路径）。
    -- 三格 L 形用独立新建的 furn.rug.4/.5（216×216，边框只沿外围），
    -- 与桌椅/书架/植物/雕塑完全相同的一条素材引用路线，不复用、不拉伸。
    return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,
      (self._furn_span and self._furn_span[cell_id]) or {r=1,c=1},
      (self._furn_off and self._furn_off[cell_id]) or {dx=0,dy=0})
  end
  self._furn_inst = self._furn_inst or {}
  local inst_key = tostring(cell_id) .. "|" .. tostring(ckey)
  local inst = self._furn_inst[inst_key]
  local rescale = false
  do
    local want_span = (self._furn_span and self._furn_span[cell_id]) or { r = 1, c = 1 }
    local want_off = (self._furn_off and self._furn_off[cell_id]) or { dx = 0, dy = 0 }
    if inst ~= nil then
      local a = (self._furn_applied and self._furn_applied[inst_key]) or inst.__murdoku_applied
      local same = (a ~= nil)
        and a.span ~= nil and _num(a.span.r, 1) == _num(want_span.r, 1) and _num(a.span.c, 1) == _num(want_span.c, 1)
        and a.off ~= nil and math.abs(_num(a.off.dx, 0) - _num(want_off.dx, 0)) < 1e-6
        and math.abs(_num(a.off.dy, 0) - _num(want_off.dy, 0)) < 1e-6
        and a.cw ~= nil and math.abs(_num(a.cw, 0) - _num(cw, 0)) < 0.5
        and a.ch ~= nil and math.abs(_num(a.ch, 0) - _num(ch, 0)) < 0.5
      if not same then
        if a ~= nil and a.ckey == ckey and not (self.cfg and self.cfg.furn_rebuild_on_resize == true) then
          rescale = true
        else
          self:_furn_destroy(inst)
          self._furn_inst[inst_key] = nil
          if self._furn_applied then self._furn_applied[inst_key] = nil end
          inst = nil
        end
      end
    end
  end
  local function apply_scale(target)
    local span0 = self._furn_span and self._furn_span[cell_id] or { r = 1, c = 1 }
    local cv = (self.cfg and self.cfg.furn_tpl_canvas and self.cfg.furn_tpl_canvas[ckey]) or { 108, 108 }
    local fx = (cw * _num(span0.c, 1)) / _num(cv[1], 108)
    local fy = (ch * _num(span0.r, 1)) / _num(cv[2], 108)
    local k = _num(self.cfg and self.cfg.furn_scale, 1)
    local kb = self.cfg and self.cfg.furn_scale_by_kind
    if type(kb) == "table" then
      local kv = kb[ckey]
      if type(kv) ~= "number" then kv = kb["*"] end
      if type(kv) == "number" then k = k * kv end
    end
    local ax = self.cfg and self.cfg.furn_scale_axis_by_kind
    if type(ax) == "table" and type(ax[ckey]) == "table" then
      local t = ax[ckey]
      if type(t.x) == "number" then fx = fx * t.x end
      if type(t.y) == "number" then fy = fy * t.y end
    elseif k ~= 1 then
      fx, fy = fx * k, fy * k
    end
    self:_furn_scale_layers(target, fx, fy)
  end
  local is_rug = ckey == "rug" or ckey == "rug_2" or ckey == "rug_3"
                 or ckey == "rug_4" or ckey == "rug_5"
  local fixed_parent = self:_prepare_furn_layer(cell_id, is_rug and "rug_layer" or "furn", cw, ch)
  if rescale then apply_scale(inst) end
  if inst == nil then
    local parent = fixed_parent or self:sub(cell_id, "content") or ctrl
    local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
    if not ok or obj == nil then
      self._furn_tpl_ok = false
      self._furn_fail_n = (self._furn_fail_n or 0) + 1
      if print then
        print("[murdoku] 家具模板实例化失败：cell=" .. tostring(cell_id)
          .. " 模板键=" .. tostring(name) .. " prefab=" .. tostring(prefab)
          .. " 父控件=" .. tostring(parent ~= nil and parent.name or "nil")
          .. " ok=" .. tostring(ok) .. " obj=" .. tostring(obj))
      end
      return false
    end
    pcall(function() obj.name = "furni." .. cell_id end)
    inst = obj
    self._furn_inst[inst_key] = inst
    self.instantiated = self.instantiated or {}
    self.instantiated["furni." .. cell_id] = true
    apply_scale(inst)
    self._furn_ok_n = (self._furn_ok_n or 0) + 1
    self._furn_keys = self._furn_keys or {}
    self._furn_keys[name] = (self._furn_keys[name] or 0) + 1
    if print then
      local sn = tostring(name)
      print("[murdoku] 家具模板：cell=" .. tostring(cell_id) .. " ← " .. sn
        .. "（prefab=" .. tostring(prefab) .. "，格子=" .. tostring(math.floor(cw)) .. "px"
        .. "，父控件=" .. tostring(parent ~= nil and parent.name or "nil") .. "）")
    end
  end
  local span = (self._furn_span and self._furn_span[cell_id]) or { r = 1, c = 1 }
  local off = (self._furn_off and self._furn_off[cell_id]) or { dx = 0, dy = 0 }
  pcall(function()
    if inst.SetAnchorMin then inst:SetAnchorMin(0.5, 0.5) end
    if inst.SetAnchorMax then inst:SetAnchorMax(0.5, 0.5) end
    if inst.SetPivot then inst:SetPivot(0.5, 0.5) end
    if inst.SetSizeDelta then
      inst:SetSizeDelta(cw * _num(span.c, 1), ch * _num(span.r, 1))
    end
    if inst.SetAnchoredPosition then
      inst:SetAnchoredPosition(_num(off.dx, 0) * cw, -(_num(off.dy, 0) * ch))
    end
    self._furn_applied = self._furn_applied or {}
    self._furn_applied[inst_key] = {
      span = { r = _num(span.r, 1), c = _num(span.c, 1) },
      off = { dx = _num(off.dx, 0), dy = _num(off.dy, 0) },
      cw = _num(cw, 0), ch = _num(ch, 0),
      ckey = ckey,
    }
    if inst.SetVisible then inst:SetVisible(self._furn_level ~= false) end
    if inst.SetActive then inst:SetActive(self._furn_level ~= false) end
  end)
  return true
end
function Adapter:_furn_resync()
  local want = self._furn_want
  if want == nil then return 0 end
  local n = 0
  for id, tpl in pairs(want) do
    if type(tpl) == "string" then
      local ctrl = self:find(id)
      if ctrl ~= nil and self:_spawn_furn_tpl(id, ctrl, tpl) then n = n + 1 end
    end
  end
  return n
end
function Adapter:_furn_scale_layers(inst, fx, fy)
  if fy == nil then fy = fx end
  if inst == nil or fx == nil or fy == nil or fx <= 0 or fy <= 0 then return 0, 0 end
  local how = nil
  local ok = false
  if inst.SetLocalScale ~= nil then
    ok = pcall(function() inst:SetLocalScale(fx, fy, 1) end)
    if ok then how = "SetLocalScale" end
  end
  if not ok then
    ok = pcall(function() inst.localScaleX = fx; inst.localScaleY = fy; inst.localScaleZ = 1 end)
    if ok then how = "localScale 字段" end
  end
  if not ok then
    local kids = nil
    if inst.GetChildren ~= nil then pcall(function() kids = inst:GetChildren() end) end
    if type(kids) == "table" and #kids == 1 then
      local rt = kids[1]
      if rt ~= nil and rt.SetLocalScale ~= nil then
        ok = pcall(function() rt:SetLocalScale(fx, fy, 1) end)
        if ok then how = "内容根 SetLocalScale" end
      end
    end
  end
  if print then
    self._furn_scale_logged = self._furn_scale_logged or {}
    local key = tostring(how or "失败")
    if not self._furn_scale_logged[key] then
      self._furn_scale_logged[key] = true
      print(string.format("[murdoku] 家具缩放：比例=%.3f,%.3f 方式=%s%s",
        fx, fy, key, ok and "" or "（三种写法都不行 ⇒ 家具会偏大，请回传这行）"))
    end
  end
  if ok then return 1, 0 end
  return 0, 1
end
function Adapter:_furn_scale_children(inst, fx, fy)
  if fy == nil then fy = fx end
  if fx == nil or fx <= 0 or fy == nil or fy <= 0 then return 0, 0 end
  local kids = nil
  if inst.GetChildren ~= nil then pcall(function() kids = inst:GetChildren() end) end
  if type(kids) ~= "table" then return 0, 0 end
  local scaled, failed = 0, 0
  self._furn_base_vals = self._furn_base_vals or setmetatable({}, { __mode = "k" })
  self._furn_scale_n = (self._furn_scale_n or 0) + 1
  for i = 1, #kids do
    local ch = kids[i]
    if ch ~= nil then
      local w0, h0, dx0, dy0 = nil, nil, nil, nil
      if ch.GetSizeDelta ~= nil then
        pcall(function() local a, b = ch.GetSizeDelta(ch) w0, h0 = a, b end)
      end
      if w0 == nil then
        pcall(function() w0, h0 = ch.sizeDeltaX, ch.sizeDeltaY end)
      end
      if ch.GetAnchoredPosition ~= nil then
        pcall(function() local a, b = ch.GetAnchoredPosition(ch) dx0, dy0 = a, b end)
      end
      if dx0 == nil then
        pcall(function() dx0, dy0 = ch.anchoredPositionX, ch.anchoredPositionY end)
      end
      local key = tostring(i)
      local memo = self._furn_base_vals[inst]
      if memo == nil then memo = {} self._furn_base_vals[inst] = memo end
      if memo[key] == nil then
        if w0 ~= nil and h0 ~= nil then
          memo[key] = { w = w0, h = h0, dx = dx0 or 0, dy = dy0 or 0, fx = 1, fy = 1 }
        else
          memo[key] = { w = nil, h = nil, dx = dx0 or 0, dy = dy0 or 0, fx = 1, fy = 1, bad = true }
          failed = failed + 1
        end
      end
      local b = memo[key]
      if b ~= nil then
        if b.w ~= nil and b.h ~= nil then
          local changed = math.abs((b.fx or 1) - fx) > 0.001 or math.abs((b.fy or 1) - fy) > 0.001
          if changed then
            pcall(function()
              if ch.SetSizeDelta then
                ch:SetSizeDelta(b.w * fx, b.h * fy)
              else
                ch.sizeDeltaX, ch.sizeDeltaY = b.w * fx, b.h * fy
              end
              if b.dx ~= nil or b.dy ~= nil then
                if ch.SetAnchoredPosition then
                  ch:SetAnchoredPosition((b.dx or 0) * fx, (b.dy or 0) * fy)
                else
                  ch.anchoredPositionX = (b.dx or 0) * fx
                  ch.anchoredPositionY = (b.dy or 0) * fy
                end
              end
            end)
            b.fx, b.fy = fx, fy
            scaled = scaled + 1
          end
        else
          local avg = math.sqrt(fx * fy)
          if ch.SetLocalScale ~= nil then
            pcall(function() ch:SetLocalScale(avg, avg, 1) end)
          else
            pcall(function() ch.localScaleX = avg; ch.localScaleY = avg end)
          end
        end
      end
    end
  end
  if print and self._furn_scale_n <= 3 then
    print(string.format("[murdoku] 家具层缩放（兜底路径）：子层=%d 缩放=%.3f,%.3f 成功=%d 基值读不到=%d",
      #kids, fx, fy, scaled, failed))
  end
  return scaled, failed
end
function Adapter:_paint_furn_art(cell_id, ctrl, want, force)
  if cell_id == nil then return false end
  local state = self._furn_art_state
  if state == nil then state = {}; self._furn_art_state = state end
  local st = state[cell_id]
  if st == nil then st = { kids = {} }; state[cell_id] = st end
  local recs = want
  local n = (type(recs) == "table") and #recs or 0
  local cap = (self.cfg and self.cfg.furn_prim_cap) or FURN_ART_CAP_DEFAULT
  if n > cap then n = cap end
  if n == 0 then
    for i = 1, #st.kids do
      local k = st.kids[i]
      if k ~= nil and k.SetVisible ~= nil then pcall(function() k:SetVisible(false) end) end
    end
    st.shown = 0
    return true
  end
  local parent = self:sub(cell_id, "furn")
  if parent == nil then parent = ctrl or self:find(cell_id) end
  if parent == nil then return false end
  local prefab = self:_furn_prefab_id()
  if prefab == nil then
    if not self._furn_prefab_warned then
      self._furn_prefab_warned = true
      if printerr then
        printerr("[murdoku] 图元拼法家具画不出来：拿不到「控件模板索引」——"
          .. "请在存档里放一个『仅存为模板』的图片控件 tpl.prim，或填 cfg.furn_prim_prefab")
      end
    end
    return false
  end
  local cw, ch = self:_cell_size_of(ctrl, cell_id)
  if cw == nil or cw <= 0 then cw, ch = 108, 108 end
  local all_ok = true
  for i = 1, n do
    local e = recs[i]
    local k = st.kids[i]
    if k == nil then
      local okc, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
      if okc and obj ~= nil then
        k = obj
        st.kids[i] = k
        if k.SetAnchorMin ~= nil then pcall(function() k:SetAnchorMin(0.5, 0.5) end) end
        if k.SetAnchorMax ~= nil then pcall(function() k:SetAnchorMax(0.5, 0.5) end) end
        if k.SetPivot ~= nil then pcall(function() k:SetPivot(0.5, 0.5) end) end
        pcall(function() k.imageType = Enum.ImageType.Stretch end)
      else
        all_ok = false
      end
    end
    if k ~= nil then
      if e ~= nil then
        if k.SetImage ~= nil then
          pcall(function() k:SetImage(Enum.ImageSource.StaticReference, e[1]) end)
        end
        pcall(function() k.imageColor = e[7] end)    
        if k.SetSizeDelta ~= nil then pcall(function() k:SetSizeDelta(e[2] * cw, e[3] * ch) end) end
        if k.SetAnchoredPosition ~= nil then
          pcall(function() k:SetAnchoredPosition(e[4] * cw, -(e[5] * ch)) end)
        end
        local rot = e[6] or 0
        if rot ~= 0 and k.SetLocalRotation ~= nil then
          pcall(function() k:SetLocalRotation(0, 0, rot) end)
        end
        if k.SetActive ~= nil then pcall(function() k:SetActive(true) end) end
        if k.SetVisible ~= nil then pcall(function() k:SetVisible(true) end) end
      end
    end
  end
  for i = n + 1, #st.kids do
    local k = st.kids[i]
    if k ~= nil and k.SetVisible ~= nil then pcall(function() k:SetVisible(false) end) end
  end
  st.shown = n
  return all_ok
end
function Adapter:clear_board_portraits()
  for id in pairs(self._portrait_want or {}) do
    self._portrait_want[id] = false
    self:_paint_portrait(id, nil, false, true)
  end
  self._portrait_marks = nil
end
function Adapter:_paint_portrait(cell_id, ctrl, want, force)
  if cell_id == nil then return false end
  local p = self:sub(cell_id, "portrait")
  if p == nil then
    return false
  end
  if want == false or want == nil then
    if p.SetVisible then pcall(function() p:SetVisible(false) end) end
    return true
  end
  local marks = self._portrait_marks
  if marks == nil then
    marks = setmetatable({}, { __mode = "k" })    
    self._portrait_marks = marks
  end
  local m = marks[p]
  if force == true or m == nil or m.key ~= want.key or m.id ~= want.id then
    if ctrl ~= nil then self:_fit_child_to_cell(ctrl, p, cell_id) end
    local src = want.src
    if src == nil then pcall(function() src = p.imageSource end) end
    pcall(function() p:SetImage(src, want.id) end)
    pcall(function() p.imageColor = 4294967295 end)
    marks[p] = { key = want.key, id = want.id }
    if p.SetActive then pcall(function() p:SetActive(true) end) end
  end
  if p.SetVisible then pcall(function() p:SetVisible(true) end) end
  return true
end
function Adapter:_set_visible_deep(ctrl, show)
  local n = 0
  if ctrl == nil or ctrl.GetChildren == nil then return 0 end
  local kids = nil
  pcall(function() kids = ctrl:GetChildren() end)
  if type(kids) ~= "table" then return 0 end
  for i = 1, #kids do
    local ch = kids[i]
    if ch ~= nil and ch.SetVisible ~= nil then
      pcall(function() ch:SetVisible(show) end)
      n = n + 1
      n = n + self:_set_visible_deep(ch, show)
    end
  end
  return n
end
function Adapter:_apply_baked(want_log)
  local want = self._baked_level or false
  local levels = (self.cfg and self.cfg.baked_levels) or { "case_001", "case_002" }
  local root = self:find("root")
  self._baked_state = self._baked_state or {}
  for i = 1, #levels do
    local lv = levels[i]
    local box = self:find("fart." .. lv)
    if box == nil and root ~= nil and root.GetChildren ~= nil then
      local kids = nil
      pcall(function() kids = root:GetChildren() end)
      if type(kids) == "table" then
        for k = 1, #kids do
          local ch = kids[k]
          local nm = nil
          pcall(function() nm = ch.name end)           
          if type(nm) == "string" and nm:find("fart", 1, true) and nm:find(lv, 1, true) then
            box = ch
            break
          end
        end
      end
    end
    local show = (want == lv)
    local touched = 0
    if box ~= nil then
      if box.SetVisible then pcall(function() box:SetVisible(show) end) end
      if box.SetActive then pcall(function() box:SetActive(show) end) end
      -- 保留旧版首次点亮后代的语义，以后只控制父容器。
      self._baked_prepared652 = self._baked_prepared652 or setmetatable({}, { __mode = "k" })
      if show and not self._baked_prepared652[box] then
        touched = self:_set_visible_deep(box, true)
        self._baked_prepared652[box] = true
      end
    end
    local st = self._baked_state[lv]
    if st == nil or st.found ~= (box ~= nil) or st.show ~= show then
      self._baked_state[lv] = { found = (box ~= nil), show = show }
      if print then
        print(string.format("[murdoku] 烘焙容器 %s：找到=%s 目标=%s 子控件=%d",
          lv, tostring(box ~= nil), show and "显示" or "隐藏", touched))
      end
    elseif want_log == true and print then
      print(string.format("[murdoku] 烘焙容器 %s：找到=%s 目标=%s 子控件=%d（复述）",
        lv, tostring(box ~= nil), show and "显示" or "隐藏", touched))
    end
  end
  do
    local lab = self:find("labels")
    if lab ~= nil and lab.SetSiblingIndex ~= nil and root ~= nil and root.GetChildren ~= nil then
      local kids, maxi = nil, nil
      pcall(function() kids = root:GetChildren() end)
      if type(kids) == "table" then
        for i = 1, #kids do
          local nm = nil
          pcall(function() nm = kids[i].name end)
          if type(nm) == "string" and nm:find("fart.", 1, true) then maxi = i end
        end
        if maxi ~= nil and (maxi + 1) <= #kids then
          pcall(function() lab:SetSiblingIndex(maxi + 1) end)
        end
      end
    end
  end
  return true
end
-- 702：选关动态内容必须具备有限变换；只校正内容，不改卡框/点击层和其它页面。
local function select_render_content(id)
  return id == "select.thumb.pool"
    or id:match("^select%.card%.%d+%.info$") ~= nil
    or id:match("^select%.card%.%d+%.title$") ~= nil
    or id:match("^select%.card%.%d+%.result$") ~= nil
    or id:match("^select%.card%.%d+%.boardbg$") ~= nil
    or id:match("^select%.card%.%d+%.cell%.") ~= nil
    or id:match("^select%.card%.%d+%.wall%.") ~= nil
    or id:match("^select%.card%.%d+%.door%.") ~= nil
end
local function finite_number(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
local function read_pair(ctrl, method)
  local ok, x, y = pcall(function() return ctrl[method](ctrl) end)
  if not ok then return nil, nil end
  if type(x) == "table" then return x.x or x[1], x.y or x[2] end
  return x, y
end
function Adapter:set_property(id, key, value, nkey)
  local ctrl = self:find(id)
  if ctrl == nil then return false end
  if key == "settle_shift" then
    local base = self._settle_shift_base
    if base == nil or base.ctrl ~= ctrl then
      local ok, x, y = pcall(function() return ctrl:GetAnchoredPosition() end)
      if not ok or type(x) ~= "number" or type(y) ~= "number" then return false end
      base = { ctrl = ctrl, x = x, y = y, shift = 0 }
      self._settle_shift_base = base
    end
    local shift = tonumber(value) or 0
    local ok = pcall(function() ctrl:SetAnchoredPosition(base.x, base.y - shift) end)
    if ok then base.shift = shift end
    return ok
  end
  if key == "text" then
    if id:match("^select%.card%.%d+%.info$") or id:match("^select%.card%.%d+%.title$") then
      -- 原生文本控件初始空值也必须尝试写入，并以读回决定是否完成。
      local expected = tostring(value or "")
      local units = 0
      for ch in expected:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        units = units + (#ch == 1 and 0.55 or 1)
      end
      local width = size_of(ctrl)
      local size = math.min(18, math.max(10, math.floor(((width or 184) - 6) / math.max(1, units))))
      local ok = pcall(function()
        ctrl.adaptiveFontSize = false
        ctrl.minimumFontSize = size
        ctrl.fontSize = size
        ctrl.fontColor = 0xFF4A2E1C
        ctrl.text = expected
        if Enum and Enum.TextHorizontalAlignment and Enum.TextVerticalAlignment then
          ctrl.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
          ctrl.verticalAlignment = Enum.TextVerticalAlignment.Middle
        end
      end)
      local read_ok, actual = pcall(function() return ctrl.text end)
      return ok and read_ok and actual == expected
    end
    if id:match("%.settle%.countdown$") or id == "settle.btn.countdown"
       or id:match("^select%.card%.%d+%.result$") then
      local expected = tostring(value or "")
      local size = id:match("%.result$") and 16 or 14
      local ok = pcall(function()
        ctrl.adaptiveFontSize = false
        ctrl.minimumFontSize = size
        ctrl.fontSize = size
        ctrl.fontColor = 0xFFF9F2E9
        ctrl.text = expected
      end)
      if not ok then return false end
      local read_ok, actual = pcall(function() return ctrl.text end)
      return read_ok and actual == expected
    end
    local tef_target = nil
    do
      if self.text_editor_first and self.text_editor_first[id] then
        local lc = nil
        pcall(function() lc = self:sub(id, "label") end)
        if lc ~= nil and lc.text ~= nil then tef_target = lc
        elseif ctrl.text ~= nil then tef_target = ctrl
        else
          local tc = self:sub(id, "text")
          if tc ~= nil and tc.text ~= nil then tef_target = tc end
        end
        if tef_target ~= nil then
          local cur = nil
          pcall(function() cur = tef_target.text end)
          if cur ~= nil and tostring(cur) ~= "" then
            return true       
          end
        end
      end
    end
    local done = false
    do
      local lc = nil
      pcall(function() lc = self:sub(id, "label") end)
      if lc ~= nil and lc.text ~= nil then
        local ok = pcall(function() lc.text = tostring(value) end)
        done = ok
      end
    end
    if not done and ctrl.text ~= nil then
      ctrl.text = tostring(value)
      done = true
    end
    if not done then
      local c = self:sub(id, "text")
      if c and c.text ~= nil then c.text = tostring(value); done = true end
    end
    return done
  elseif key == "baked_level" then
    self._baked_level = value or false
    return self:_apply_baked(true)
  elseif key == "furn_level" then
    self._furn_level = value or false
    return self:_apply_furn_level()
  elseif key == "furn_tpl" then
    self._furn_want = self._furn_want or {}
    self._furn_want[id] = type(value) == "string" and value or false
    if type(value) == "string" then
      if self._furn_inst ~= nil then
        local want_key = _furn_cfg_key(value)
        local prefix = tostring(id) .. "|"
        for k, v in pairs(self._furn_inst) do
          if type(k) == "string" and k:sub(1, #prefix) == prefix then
            local kk = k:sub(#prefix + 1)
            if want_key == nil or kk ~= tostring(want_key) then
              self:_furn_destroy(v)
              self._furn_inst[k] = nil
              if self._furn_applied then self._furn_applied[k] = nil end
            end
          end
        end
      end
      if self._furn_tpl_ok and self._furn_level ~= false then
        if self._furn_batch then furn_mark_dirty(self, id) else self:_spawn_furn_tpl(id, ctrl, value) end
      end
    else
      if self._furn_inst ~= nil then
        local prefix = tostring(id) .. "|"
        for k, v in pairs(self._furn_inst) do
          if type(k) == "string" and k:sub(1, #prefix) == prefix then
            self:_furn_destroy(v)
            self._furn_inst[k] = nil
            if self._furn_applied then self._furn_applied[k] = nil end
          end
        end
      end
    end
    return true
  elseif key == "furn_span" then
    self._furn_span = self._furn_span or {}
    self._furn_span[id] = (type(value) == "table") and value or false
    if self._furn_tpl_ok and self._furn_want and self._furn_want[id] and self._furn_level ~= false then    
      if self._furn_batch then furn_mark_dirty(self, id) else self:_spawn_furn_tpl(id, ctrl, self._furn_want[id]) end
    end
    return true
  elseif key == "furn_offset" then
    self._furn_off = self._furn_off or {}
    self._furn_off[id] = (type(value) == "table") and value or false
    if self._furn_tpl_ok and self._furn_want and self._furn_want[id] and self._furn_level ~= false then    
      if self._furn_batch then furn_mark_dirty(self, id) else self:_spawn_furn_tpl(id, ctrl, self._furn_want[id]) end
    end
    return true
  elseif key == "furn_art" then
    self._furn_art_want = self._furn_art_want or {}
    self._furn_art_want[id] = (type(value) == "table") and value or false
    return self:_paint_furn_art(id, ctrl, value, true)
  elseif key == "furn" then
    if self._furn_tpl_ok then return true end
    if self._furn_arch_new then
      self:warn_once("furn:newarch",
        "新架构（things/无 obj 层）⇒ 手搭层（地毯）本轮跳过；需要地毯请让 integrator 在 things 加 `furn.rug` 模板。")
      return true
    end
    local layers = {}
    if type(value) == "table" then
      for i = 1, math.min(#value, #OBJ_LAYER_SUBS) do
        local e = value[i]
        if type(e) == "table" and type(e.id) == "number" then
          layers[#layers + 1] = {
            key = "furn." .. i,
            id = e.id,
            color = e.color,
            w = e.w, h = e.h, dx = e.dx, dy = e.dy,
          }
        end
      end
    end
    local want = false
    if #layers > 0 then want = { key = "furn", layers = layers } end
    self._obj_want = self._obj_want or {}
    self._obj_want[id] = want
    return self:_paint_obj(id, ctrl, want, true)
  elseif key == "furn_anchor" then
    -- ★ 685 通用构造法：抬格只发生在 stage 内部；之后立刻把标记层复位，
    --   无论将来新增什么 kind / span 的多格家具，X 都不会被盖住。
    self:_mark_layer_guard()
    if value == true and ctrl ~= nil and ctrl.SetAsLastSibling ~= nil then
      local ok = pcall(function() ctrl:SetAsLastSibling() end)
      if not ok then return false end
      self._furn_anchors = self._furn_anchors or {}
      self._furn_anchors[id] = true
    end
    self:_mark_layer_raise()
    return true
  elseif key == "object" then
    local want = false
    if not (value == false or value == nil) then
      local vkey = tostring(value)
      local kind = vkey:match("^obj%.(.+)$") or vkey
      local map = self:read_palette()
      local layers = {}
      for li = 1, #OBJ_LAYER_SUBS do
        local k = (li == 1 and ("obj.") or ("obj" .. li .. ".")) .. kind
        local hit = map[k]
        if type(hit) == "table" and type(hit.id) == "number" then
          layers[#layers + 1] = {
            key = k, src = hit.source, id = hit.id, color = hit.color,
            w = hit.w, h = hit.h, dx = hit.dx, dy = hit.dy,
          }
        end
      end
      if #layers > 0 then
        want = { key = vkey, layers = layers }
      end
    end
    self._obj_want = self._obj_want or {}
    self._obj_want[id] = want
    self:_paint_obj(id, ctrl, want, true)
  elseif key == "hint" then
    local h = self:sub(id, "hint")
    if h == nil then
      self:warn_once("hint:missing", "模板里没有 `hint` 子控件（线索位置提示画不出来）"
        .. " —— 2026-10-17 的存档里它在 `cell` 的 `content` 下")
      return true
    end
    self:_fit_child_to_cell(ctrl, h, id)
    local on = (value == true)
    if h.SetVisible then pcall(function() h:SetVisible(on) end) end
    if on then
    end
    if on and h.SetActive then pcall(function() h:SetActive(true) end) end
    return true
  elseif key == "fit" then
    local n = tonumber(value)
    if n ~= nil and n > 1 then
      for _, nm in ipairs({ "face", "hint", "obj", "portrait" }) do
        local s2 = self:sub(id, nm)
        if s2 ~= nil then self:_fit_child_sized(s2, n, n) end
      end
    end
    return true
  elseif key == "imageType" then
    local want = nil
    pcall(function() want = value end)
    if want ~= nil then
      local enum = nil
      pcall(function() enum = Enum.ImageType[tostring(want)] end)
      if enum ~= nil then
        pcall(function() ctrl.imageType = enum end)
        local f = self:sub(id, "face")
        if f ~= nil then pcall(function() f.imageType = enum end) end
      end
    end
  elseif key == "image" then
    if is_cell_id(id) then
      local want = false
      if value ~= nil and value ~= false then
        local hit = self:resolve_asset(value)
        if hit ~= nil and hit.id ~= nil then
          want = { key = tostring(value), id = hit.id, src = hit.source }
        end
      end
      self._portrait_want = self._portrait_want or {}
      self._portrait_want[id] = want
      return self:_paint_portrait(id, ctrl, want, true)
    end
    local target = self:sub(id, "face") or ctrl
    if target ~= nil then
      if is_cell_id(id) then self:_fit_child_to_cell(ctrl, target, id) end
      self._face_def = self._face_def or {}
      local d = self._face_def[id]
      if d == nil then
        d = { src = nil, id = nil, visible = true }
        pcall(function() d.src = target.imageSource end)
        pcall(function() d.id = target.imageId end)
        pcall(function() d.visible = target.visible end)
        self._face_def[id] = d
      end
      if value == false then value = nil end
      if value == nil then
        if d.swapped then                        
          if target.SetImage and d.id ~= nil then
            pcall(function() target:SetImage(d.src, d.id) end)
          end
          d.swapped = false
        end
      elseif target.SetImage then
        local src = target.imageSource                  
        local hit = self:resolve_asset(value)
        if hit ~= nil then
          if hit.source ~= nil then src = hit.source end    
          if hit.id ~= nil then
            local ok, err = pcall(function() target:SetImage(src, hit.id) end)
            if not ok then self:warn_once("setimage", "SetImage 失败：" .. tostring(err)) end
            d.swapped = true
          end
        end
        if target.SetVisible then pcall(function() target:SetVisible(true) end) end
        if self.cfg.debug_image then
          local it = nil
          pcall(function() it = tostring(target.imageType) end)
          print(string.format("[murdoku] SetImage 后 `%s` 的 imageType = %s（Basic=按原始像素 / Stretch=填满）",
            tostring(id), tostring(it)))
        end
      end
    end
  elseif key == "walls" then
    return self:_apply_edges(id, "wall", value)
  elseif key == "doors" then
    return self:_apply_edges(id, "door", value)
  elseif key == "tint" then
    local target = self:sub(id, "face") or ctrl
    if target ~= nil then
      if is_cell_id(id) then self:_fit_child_to_cell(ctrl, target) end
      local made = nil
      if type(value) == "number" then
        made = value
      elseif type(value) == "table" then
        local r = tonumber(value.r or value[1]) or 255
        local g = tonumber(value.g or value[2]) or 255
        local b = tonumber(value.b or value[3]) or 255
        local a = tonumber(value.a or value[4]) or 255
        made = M.pack_color(r, g, b, a)
      end
      if made ~= nil then
        local ok = pcall(function() target.imageColor = made end)
        if not ok then
          self:warn_once("tint", "设置 imageColor 失败（imageColor 可能不是整数）")
        end
      end
    end
  elseif key == "visible" then
    -- ★ 686：stage 被隐藏时整层收起（父容器隐藏不级联子控件）
    if id == ((self.cfg.cells or {}).parent or "board") and value ~= true then
      self:_mark_hide_all()
    end
    if id == ((self.cfg.cells or {}).parent or "board") then
      for _,name in ipairs({"board.floors","board.rugs"}) do
        local layer=self:find(name)
        if layer then
          layer:SetVisible(value==true)
          if value==true and layer.SetActive then layer:SetActive(true) end
        end
      end
    end
    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl,value==true) end
    -- ★ 686：cell 的 visible 随 self.screen 变化（离开关卡 = false）。标记层不在
    --   layout_plan 节点表里，没人给它关灯 ⇒ 这里逐组收起并置屏幕门控。
    do
      local rc = tostring(id):match("^cell%.(.+)$")
      if rc ~= nil then
        if value == true then
          self._mark_screen_on = true
        else
          self._mark_screen_on = false
          self:_mark_set_visible(rc, false)
        end
      end
    end
    if value == true and ctrl.SetActive ~= nil then
      pcall(function() ctrl:SetActive(true) end)
    end
    local vis = value and true or false
    if ctrl.SetVisible then pcall(function() ctrl:SetVisible(vis) end) end
    self._hidden_ids = self._hidden_ids or {}
    if vis then self._hidden_ids[id] = nil else self._hidden_ids[id] = true end
    if vis and id:sub(1, 5) == "cell." then
      self._overlay_dirty = true
    end
    self._subtree_dirty = true
    if vis == false and id:sub(1, 5) == "cell." then
      local function hide_kids(node, depth)
        if node == nil or depth > 4 then return end
        local kids = nil
        pcall(function() kids = node:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil then
              if k.SetVisible then pcall(function() k:SetVisible(false) end) end
              local nm = nil
              pcall(function() nm = k.name end)
              if nm ~= "furn" and nm ~= "rug_layer" and nm ~= "board.floors" and nm ~= "board.rugs" and nm ~= "x" then hide_kids(k, depth + 1) end  
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
    if vis == true and id:sub(1, 5) == "cell." then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.SetVisible ~= nil then
        pcall(function() face:SetVisible(true) end)
      end
      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil and s2.SetVisible ~= nil then
            pcall(function() s2:SetVisible(want) end)
          end
        end
      end
    end
  elseif key == "raycast" then
    local want = value and true or false
    self._ray_want = self._ray_want or setmetatable({}, { __mode = "k" })
    self._ray_want[ctrl] = want
    if ctrl.raycastTarget ~= nil then
      pcall(function() ctrl.raycastTarget = want end)
    end
    if ctrl.blockRaycast ~= nil then
      pcall(function() ctrl.blockRaycast = want end)
    end
    if ctrl.interactable ~= nil then
      pcall(function() ctrl.interactable = want end)
    end
  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
      -- ★ 687：682/683 把胶囊与描边收进名为 art 的 DECOR 容器后，bg 子层已不存在，
      --   上面的染色够不到按钮 ⇒ 未启用结算时不再变灰。这里沿 art 容器逐层恢复/置灰。
      --   颜色口径：启用 outline=#FF6C402E / capsule=#FFFCECD4；禁用统一 #FF686B70。
      local art = self:sub(id, "art")
      if art ~= nil then
        local kids = nil
        pcall(function() kids = art:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do
            local k = kids[i]
            if k ~= nil then
              local nm = nil
              pcall(function() nm = k.name end)
              local outline = (type(nm) == "string" and nm:find("outline") ~= nil)
              pcall(function()
                if k.imageColor ~= nil then
                  k.imageColor = value and (outline and 0xFF6C402E or 0xFFFCECD4) or 0xFF686B70
                end
              end)
            end
          end
        end
      end
    end
  elseif key == "rect" and self.apply_rect then
    if ctrl.SetAnchoredPosition then ctrl:SetAnchoredPosition(value.x, value.y) end
    if ctrl.SetSizeDelta then ctrl:SetSizeDelta(value.w, value.h) end
    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl) end
  elseif key == "event" then
    local k = nkey or id
    self.events[k] = value
    if self.event_claim[id] == nil then self.event_claim[id] = k end
    self.event_latest[id] = k
  elseif key == "rect" then
    if self.cfg.respect_editor_rect ~= false
       and not (self.instantiated and self.instantiated[id])
       and not (self.runtime_rect and self.runtime_rect[id]) then
      return true
    end
    local sc = self.cfg.scale or (5 / 6)
    -- 704：选关图元的格宽/格缝已在画布上量化；保留共同小数中心。
    -- 分别取整中心和尺寸会把相邻格缝改成 0/1/2 像素。
    local exact_select = select_render_content(id)
    local function R(v)
      if exact_select then return v or 0 end
      return math.floor((v or 0) + 0.5)
    end
    local w = R((value.w or 0) * sc)
    local h = R((value.h or 0) * sc)
    local cx = R(((value.x or 0) + (value.w or 0) * 0.5) * sc)
    local cyTop = R(((value.y or 0) + (value.h or 0) * 0.5) * sc)    
    local ch = self.cfg.canvas_h or 900
    local cy = ch - cyTop                                             
    self.rects = self.rects or {}
    self.rects[id] = { cx = cx, cy = cy, w = w, h = h }
    if w ~= nil and h ~= nil and type(id) == "string" and id:match("^cell%.%d+%.%d+$") then
      for _, nm in ipairs({ "face", "hint", "obj", "portrait" }) do
        local sub3 = self:sub(id, nm)
        if sub3 ~= nil then self:_fit_child_sized(sub3, w, h) end
      end
    end
    local h_node = self.handlers and self.handlers[id] or nil
    local pid = (h_node and h_node.parent)
      or (self.cfg.parent_of and self.cfg.parent_of[id]) or nil
    local pcx, pcy = nil, nil
    local p_node = (pid ~= nil and self.handlers ~= nil) and self.handlers[pid] or nil
    if p_node ~= nil and p_node.rect ~= nil then
      local pr = p_node.rect
      pcx = R(((pr.x or 0) + (pr.w or 0) * 0.5) * sc)
      pcy = ch - R(((pr.y or 0) + (pr.h or 0) * 0.5) * sc)
    end
    if pcx == nil and pid ~= nil and self.rects[pid] ~= nil then
      pcx, pcy = self.rects[pid].cx, self.rects[pid].cy
    end
    if pcx == nil then
      pcx = R((self.cfg.canvas_w or 1600) * 0.5)
      pcy = R(ch * 0.5)
    end
    if select_render_content(id) then
      -- 原型可能带 NaN 缩放，写 text/size 不会修复它。所有 setter 都必须成功。
      if not (finite_number(w) and finite_number(h) and finite_number(cx)
          and finite_number(cy) and finite_number(pcx) and finite_number(pcy)) then return false end
      local ok, err = pcall(function()
        ctrl:SetLocalScale(1, 1, 1)
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(cx - pcx, cy - pcy)
      end)
      if not ok then
        self:warn_once("select_rect:" .. id, "选关内容变换写入未完成，保留重试：" .. id .. " / " .. tostring(err))
        return false
      end
      local function near(a, b) return finite_number(a) and math.abs(a - b) < 0.01 end
      local rw, rh = read_pair(ctrl, "GetSizeDelta")
      local rx, ry = read_pair(ctrl, "GetAnchoredPosition")
      local sx, sy = read_pair(ctrl, "GetLocalScale")
      local aminx, aminy = read_pair(ctrl, "GetAnchorMin")
      local amaxx, amaxy = read_pair(ctrl, "GetAnchorMax")
      local px, py = read_pair(ctrl, "GetPivot")
      local ready = near(rw, w) and near(rh, h) and near(rx, cx - pcx) and near(ry, cy - pcy)
        and near(sx, 1) and near(sy, 1)
        and near(aminx, 0.5) and near(aminy, 0.5) and near(amaxx, 0.5) and near(amaxy, 0.5)
        and near(px, 0.5) and near(py, 0.5)
      if not ready then
        self:warn_once("select_readback:" .. id, "选关内容变换回读不符，保留重试：" .. id)
        return false
      end
      return true
    end
    if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
    if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
    if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
    if ctrl.SetSizeDelta then pcall(function() ctrl:SetSizeDelta(w, h) end) end
    if ctrl.SetAnchoredPosition then
      pcall(function() ctrl:SetAnchoredPosition(cx - pcx, cy - pcy) end)
    end
    if id:match("^cell%.%d+%.%d+$") then self:_sync_floor(id,ctrl) end
  elseif key == "style" then
    local PLACED_TINT = 2147483647
    local NORMAL_TINT = 4294967295       
    self._style = self._style or {}
    self._style[id] = value              
    local scale = self:scale_of_style(value)
    if scale and ctrl.SetLocalScale then ctrl:SetLocalScale(scale, scale, 1) end
    local wantColor = self:color_of_style(value)
    if wantColor ~= nil and ctrl.fontColor ~= nil then
      pcall(function() ctrl.fontColor = wantColor end)
    end
    if type(value) == "string" and string.sub(value, 1, 8) == "portrait" then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.imageColor ~= nil then
        local want = (value == "portrait.placed") and PLACED_TINT or NORMAL_TINT
        local okc, err = pcall(function() face.imageColor = want end)
        if not okc then
          self:warn_once("tint:" .. tostring(id), "头像卡调色失败（imageColor 可能不是整数）：" .. tostring(err))
        end
      end
    end
  elseif key == "notes" then
    local c = self:sub(id, "note")
    if c ~= nil then
      local txt = nil
      if type(value) == "table" then
        txt = table.concat(value, " ")
      elseif value == false or value == nil then
        txt = ""
      else
        txt = tostring(value)
      end
      if c.text ~= nil then c.text = txt end
      if type(c.SetText) == "function" then pcall(function() c:SetText(txt) end) end
      if c.SetVisible then pcall(function() c:SetVisible(txt ~= "") end) end
      if txt ~= "" then
        if c.SetActive then pcall(function() c:SetActive(true) end) end
        if c.SetAsLastSibling then pcall(function() c:SetAsLastSibling() end) end
        local fw, fh = nil, nil
        pcall(function()
          local f = self:sub(id, "face")
          if f ~= nil then fw, fh = f:GetSizeDelta() end
        end)
        if fw ~= nil and fh ~= nil and fw > 1 and fh > 1 then
        end
      end
    end
  elseif key == "x_mark" then
    local c = self:sub(id, "x")
    if c and c.SetVisible then c:SetVisible(value and true or false) end
    -- ★ 685：镜像到 stage 末尾的标记层（格内 x 保留作兜底，同位同色叠加不可见）
    local m, rc = self:_mark_ctrl(id)
    if rc ~= nil then self:_mark_set_visible(rc, value and true or false) end
    self:_mark_scope()
    self:_mark_layer_raise()
  end
  return true
end
function Adapter:_fire(event, phase, data, src_id)
  self._subtree_dirty = true
  if self.on_input == nil then return end
  local evt = {}
  for k, v in pairs(event) do evt[k] = v end
  evt.phase = phase
  if data and data.GetUIPos then
    local ok, x, y = pcall(function() return data:GetUIPos() end)
    if ok then evt.x, evt.y = x, y end
  end
  if src_id ~= nil and evt.r == nil then
    local R, C = tostring(src_id):match("^cell%.(%d+)%.(%d+)$")
    if R ~= nil then
      evt.r = tonumber(R)
      evt.c = tonumber(C)
    end
  end
  self.on_input(evt)
end
function Adapter:device()
  if self._device ~= nil then return self._device end
  local name = "unknown"
  pcall(function()
    if game ~= nil and game.GetDevice ~= nil then
      local d = game.GetDevice()
      if d ~= nil then
        name = tostring(d.Name or d.FullName or d)
      end
    end
  end)
  self._device = name
  return name
end
function Adapter:input_profile()
  local d = self:device()
  if d == "Mobile" or d == "MobileController" then return "touch" end
  if d == "Controller" then return "gamepad" end
  return "pc"         
end
function Adapter:bind_input(id, node)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if ctrl.AddCursorEventListener == nil then
    self:warn_once("nocursor:" .. tostring(id),
      "控件 " .. tostring(id) .. " 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）")
    return
  end
  self.bound = self.bound or {}
  local prev = rawget(self.bound, id)
  if prev == ctrl then return end             
  self._bound_ctrl = self._bound_ctrl or setmetatable({}, { __mode = "k" })
  if self._bound_ctrl[ctrl] then
    self.bound[id] = ctrl
    return
  end
  local click = E("CursorEventType.CursorClick")
  if click == nil then
    self:warn_once("noenum", "Enum.CursorEventType.CursorClick 缺失，无法绑定点击")
    return
  end
  self.bound[id] = ctrl                       
  self._bound_ctrl[ctrl] = true                
  if self.cfg.debug_event ~= false then
    self._bind_seen = (self._bind_seen or 0) + 1
    if self._bind_seen <= 16 and print then
      local ev = node.event
      local what = "-"
      if ev ~= nil then
        if ev.id ~= nil then what = tostring(ev.id)
        elseif ev.r ~= nil then what = tostring(ev.r) .. "," .. tostring(ev.c)
        elseif ev.mode ~= nil then what = tostring(ev.mode) end
      end
      print("[murdoku] 绑定输入 `" .. tostring(id) .. "`  事件="
        .. (ev and tostring(ev.action) or "nil") .. "/" .. what)
    end
  end
  local function live_event()
    local k = self.event_claim[id]
    local cur = nil
    if k ~= nil then cur = self.events[k] end
    return cur or node.event or { action = "click" }
  end
  ctrl:AddCursorEventListener(click, function(data)
    if self.cfg.debug_click ~= false then
      self._click_seen = (self._click_seen or 0) + 1
      if self._click_seen <= 8 and print then
        local xy = ""
        pcall(function()
          if data ~= nil and data.GetUIPos ~= nil then
            local x, y = data:GetUIPos()
            if type(x) == "number" then
              xy = string.format("  点击坐标=(%.0f, %.0f)", x, y)
            end
          end
        end)
        print("[murdoku] 收到点击 → 控件 `" .. tostring(id) .. "`（第 "
          .. self._click_seen .. " 次）" .. xy
          .. "  事件=" .. tostring((live_event() or {}).action or "nil"))
      elseif self._click_seen == 9 and print then
        print("[murdoku] （点击日志到此为止，后面不再刷；cfg.debug_click = false 可关）")
      end
    end
    self:_fire(live_event(), "click", data, id)
  end)
  local down = E("CursorEventType.CursorDown")
  if down ~= nil then
    ctrl:AddCursorEventListener(down, function(data)
      self:_fire(live_event(), "down", data, id)
    end)
  end
  local up = E("CursorEventType.CursorUp")
  if up ~= nil then
    ctrl:AddCursorEventListener(up, function(data)
      self:_fire(live_event(), "up", data, id)
    end)
  end
  local drag = E("CursorEventType.CursorDrag")
  if drag ~= nil then
    ctrl:AddCursorEventListener(drag, function(data)
      self:_fire(live_event(), "drag", data, id)
    end)
  end
end
function Adapter:bind_keys(spec, control_id)
  self.keymap = self.keymap or {}
  if game == nil then return 0, "没有 game 环境" end
  local names = {}
  local src = control_id or self.cfg.key_control or "root"
  if type(src) == "table" then
    for i = 1, #src do names[#names + 1] = tostring(src[i]) end
  else
    names[1] = tostring(src)
  end
  local extra = self.cfg.key_control_fallbacks
  if type(extra) == "table" then
    for i = 1, #extra do names[#names + 1] = tostring(extra[i]) end
  end
  local ctrl, used, why = nil, nil, {}
  for i = 1, #names do
    local c = self:find(names[i])
    if c == nil then
      why[#why + 1] = names[i] .. "=找不到"
    elseif c.AddKeyEventListener == nil then
      why[#why + 1] = names[i] .. "=不支持按键事件"
    else
      ctrl, used = c, names[i]
      break
    end
  end
  if ctrl == nil then
    return 0, "候选控件都不中用：" .. table.concat(why, "；")
  end
  local list = {}
  if type(spec) == "table" then
    if #spec > 0 then
      for i = 1, #spec do list[#list + 1] = { tostring(spec[i]), {} } end
    else
      for k, v in pairs(spec) do list[#list + 1] = { tostring(k), v or {} } end
    end
  end
  local n, failed, unresolved = 0, 0, {}
  for i = 1, #list do
    local key_name, event = list[i][1], list[i][2]
    if self.keymap[key_name] == nil then
      local et = E("KeyEventType." .. key_name)
      if et == nil then
        unresolved[#unresolved + 1] = key_name
      else
        if self.cfg.debug_key and print then
          self._key_dbg = (self._key_dbg or 0) + 1
          if self._key_dbg <= 4 then
            print("[murdoku] KeyEventType 解析：" .. key_name
              .. " -> type=" .. type(et) .. " 值=" .. tostring(et))
          end
        end
        local ok = pcall(function()
          ctrl:AddKeyEventListener(et, function()
            if self.cfg.debug_key then
              print("[murdoku] 按键事件 → " .. tostring(key_name))
            end
            if not self._key_first_seen then
              self._key_first_seen = true
              if print then
                print("[murdoku] ✅ 键盘事件仍能收到（第一个键：" .. tostring(key_name)
                  .. "）—— 「屏蔽按键事件穿透」没有影响脚本自身的监听，目标⑦的疑问到此处排除。")
              end
            end
            if self.on_input ~= nil then
              local evt = {}
              for k, v in pairs(event) do evt[k] = v end
              evt.phase = "key"
              evt.key = key_name       
              self.on_input(evt)
            end
            return false
          end)
        end)
        if ok then n = n + 1 else failed = failed + 1 end
      end
    end
    self.keymap[key_name] = event
  end
  local note = "绑在 " .. tostring(used) .. " 上，成功 " .. n .. " 个"
  if failed > 0 then note = note .. "，失败 " .. failed .. " 个" end
  if #unresolved > 0 then
    note = note .. "；" .. #unresolved .. " 个键名取不到 Enum.KeyEventType："
      .. table.concat(unresolved, ", ")
  end
  return n, note
end
local EFFECTS = {
  pop_tile     = { dur = 0.26, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.62 }, { 0.55, 1.06 }, { 1.00, 1.00 } } },
  note_pop     = { dur = 0.14, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 0.90 }, { 1.00, 1.00 } } },
  pulse        = { dur = 0.18, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.50, 1.14 }, { 1.00, 1.00 } } },
  sel_pop_glow = { dur = 0.30, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.45, 1.12 }, { 0.70, 1.03 }, { 1.00, 1.00 } } },
  undo_flash   = { dur = 0.16, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.05 }, { 1.00, 1.00 } } },
  submit_nudge = { dur = 0.28, ease = "OutCubic", ch = "scale",
                   keys = { { 0.00, 1.000 }, { 0.40, 1.035 }, { 1.00, 1.000 } } },
  clue_box_pop = { dur = 0.22, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.82 }, { 0.60, 1.03 }, { 1.00, 1.00 } } },
  solved_flash = { dur = 0.36, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.40, 1.12 }, { 1.00, 1.00 } } },
  vanish       = { dur = 0.20, ease = "InQuad",   ch = "scale",
                   keys = { { 0.00, 1.00 }, { 1.00, 0.00 } } },
  shake        = { dur = 0.30, ease = "Linear",   ch = "pos_x",
                   keys = { { 0.00, 0 }, { 0.20, -8 }, { 0.45, 8 },
                            { 0.70, -5 }, { 1.00, 0 } } },
  portrait_slide_up = { dur = 0.34, ease = "OutBack", ch = "pos_y",
                   keys = { { 0.00, -34 }, { 0.70, 4 }, { 1.00, 0 } } },
}
M.SOUNDS = {
  pop_tile     = nil,
  note_pop     = nil,
  pulse        = nil,
  sel_pop_glow = nil,
  undo_flash   = nil,
  submit_nudge = nil,
  clue_box_pop = nil,
  solved_flash = nil,
  vanish       = nil,
  shake        = nil,
  portrait_slide_up = nil,
}
function Adapter:ease_of(name)
  if name == nil then return nil end
  local e = E("EaseType." .. tostring(name))
  if e == nil then e = E("EaseType.Linear") end
  return e
end
local function read_pose(ctrl)
  local pose = { sx = 1, sy = 1, ax = 0, ay = 0, rz = 0 }
  if ctrl == nil then return pose end
  pcall(function() if ctrl.localScaleX then pose.sx = ctrl.localScaleX end end)
  pcall(function() if ctrl.localScaleY then pose.sy = ctrl.localScaleY end end)
  pcall(function() if ctrl.anchoredPositionX then pose.ax = ctrl.anchoredPositionX end end)
  pcall(function() if ctrl.anchoredPositionY then pose.ay = ctrl.anchoredPositionY end end)
  pcall(function() if ctrl.localRotationZ then pose.rz = ctrl.localRotationZ end end)
  return pose
end
local function build_timeline(adapter, ctrl, spec, base)
  local keys = spec.keys
  local n = #keys
  if n < 2 then return {} end
  local ease = adapter:ease_of(spec.ease)
  local ch = spec.ch or "scale"
  local list = {}
  for i = 1, n - 1 do
    local t0, v0 = keys[i][1], keys[i][2]
    local t1, v1 = keys[i + 1][1], keys[i + 1][2]
    local seg = (t1 - t0) * spec.dur
    if seg <= 0 then seg = 0.01 end
    local props
    if ch == "pos_x" then
      props = { anchoredPositionX = base.ax + v1 }
    elseif ch == "pos_y" then
      props = { anchoredPositionY = base.ay + v1 }
    elseif ch == "rot" then
      props = { localRotationZ = base.rz + v1 }
    else
      props = { localScaleX = v1, localScaleY = v1 }
    end
    list[#list + 1] = { props = props, seg = seg, ease = ease }
  end
  return list
end
function Adapter:play_effect(id, effect_name, params)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if game == nil or game.Tween == nil then return end
  local spec = EFFECTS[effect_name]
  if spec == nil then
    self:warn_once("nomotion:" .. tostring(effect_name),
      "没有这条动效定义：" .. tostring(effect_name)
      .. "（核对 EFFECTS 表与 ui_controller 里 M.EFFECTS 的名字）")
    return
  end
  local base = read_pose(ctrl)
  local segs = build_timeline(self, ctrl, spec, base)
  local ok = pcall(function()
    local seq = game.TweenSequence and game.TweenSequence()
    if seq == nil or seq.Append == nil then error("no sequence") end
    local added = 0
    for i = 1, #segs do
      local t = game.Tween(ctrl, segs[i].props, segs[i].seg)
      if t ~= nil then
        if t.SetEase and segs[i].ease then pcall(function() t:SetEase(segs[i].ease) end) end
        seq:Append(t)
        added = added + 1
      end
    end
    if added == 0 then error("no tween") end
    seq:Play()
    if seq.SetOnComplete then
      pcall(function()
        seq:SetOnComplete(function()
          pcall(function()
            ctrl.localScaleX, ctrl.localScaleY = base.sx, base.sy
            ctrl.anchoredPositionX, ctrl.anchoredPositionY = base.ax, base.ay
            ctrl.localRotationZ = base.rz
          end)
        end)
      end)
    end
  end)
  if not ok and #segs > 0 then
    local pick = segs[1]
    for i = 1, #segs do
      if segs[i].props.localScaleX and segs[i].props.localScaleX ~= 1 then pick = segs[i] end
    end
    pcall(function()
      local t = game.Tween(ctrl, pick.props, pick.seg)
      if t ~= nil then
        if t.SetEase and pick.ease then pcall(function() t:SetEase(pick.ease) end) end
        t:Play()
      end
    end)
  end
  local aid = self.cfg.sounds and self.cfg.sounds[effect_name]
  if aid == nil and M.SOUNDS then aid = M.SOUNDS[effect_name] end
  if aid ~= nil then self:play_audio(aid) end
end
function Adapter:now() return self.clock end
function Adapter:after(seconds, fn)
  local h = { at = self.clock + (seconds or 0), fn = fn }
  self.timers[#self.timers + 1] = h
  return h
end
function Adapter:cancel(handle)
  for i = 1, #self.timers do
    if self.timers[i] == handle then table.remove(self.timers, i) return true end
  end
  return false
end
function Adapter:enforce_hidden_subtrees()
  self._subtree_dirty = false
  local hid = self._hidden_ids
  if hid == nil then return end
  local function decor(nm)
    if nm == nil or nm == "" then return false end
    return DECOR[nm] == true
  end
  local function nameOf(c)
    local nm = nil
    pcall(function() nm = c.name end)
    return nm
  end
  for id in pairs(hid) do
    if true then    
      local c = self:find(id)
      if c ~= nil then
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              if not decor(nameOf(k)) then
                pcall(function() k:SetVisible(false) end)
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                if type(kk) == "table" then
                  for j = 1, math.min(#kk, 32) do
                    if kk[j] ~= nil and kk[j].SetVisible and not decor(nameOf(kk[j])) then
                      pcall(function() kk[j]:SetVisible(false) end)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
function Adapter:_repaint_cell_overlays(cell_id)
  if cell_id == nil then return end
  if self._furn_level ~= false and self._furn_layer_state then
    for _, name in ipairs({"rug_layer", "furn"}) do
      local st = self._furn_layer_state[cell_id .. ":" .. name]
      if st then self:_prepare_furn_layer(cell_id, name, st.w, st.h, true) end
    end
  end
  local w = self._edge_want
  if w ~= nil then
    local e = w[cell_id]
    if e ~= nil then
      for name, want in pairs(e) do
        local s2 = self:sub(cell_id, name)
        if s2 ~= nil and s2.SetVisible ~= nil then
          pcall(function() s2:SetVisible(want) end)
        end
      end
    end
  end
  local o = self._obj_want
  if o ~= nil then
    local want = o[cell_id]
    if want ~= nil then
      self:_paint_obj(cell_id, nil, want, false)
    end
  end
  local pp = self._portrait_want
  if pp ~= nil then
    local want = pp[cell_id]
    if want ~= nil then
      self:_paint_portrait(cell_id, nil, want, false)
    end
  end
  local fa = self._furn_art_want
  if fa ~= nil then
    local want = fa[cell_id]
    if want ~= nil then
      self:_paint_furn_art(cell_id, nil, want, false)
    end
  end
end
function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)
  -- ★ 685：每帧复位标记层 ⇒ 未来任何新的抬格代码都自动被覆盖，无需再改层序
  self:_mark_layer_raise()
  if self._furn_batch then self._furn_batch = false end
  if self._furn_try_pending or self._furn_dirty ~= nil then self:flush_furn_pending() end
  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
    if (self._furn_resync_at or -1) <= self.clock then
      self._furn_resync_at = self.clock + 0.5
      pcall(function() self:_furn_resync() end)
    end
  end
  -- 689：定时器为空时不分配空表（688 在该分支本就什么都不做）
  if #self.timers > 0 then
    local due = {}
    for i = #self.timers, 1, -1 do
      if self.timers[i].at <= self.clock then
        due[#due + 1] = self.timers[i]
        table.remove(self.timers, i)
      end
    end
    for i = #due, 1, -1 do due[i].fn() end
  end
  if self._subtree_dirty then
    pcall(function() self:enforce_hidden_subtrees() end)
  end
  if self._overlay_dirty then
    self._overlay_dirty = false
    local seen = {}
    local function repaint_all(t)
      if type(t) ~= "table" then return end
      for cid in pairs(t) do
        if not seen[cid] then
          seen[cid] = true
          pcall(function() self:_repaint_cell_overlays(cid) end)
        end
      end
    end
    repaint_all(self._edge_want)
    repaint_all(self._obj_want)
  end
  if self._baked_dirty then
    self._baked_dirty = false
    pcall(function() self:_apply_baked(false) end)
  end
  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false
     and (self._furn_retry_n or 0) < 12 then
    self._furn_last_try = self._furn_last_try or -1
    if self.clock - self._furn_last_try >= 1.0 then
      self._furn_last_try = self.clock
      self._furn_retry_n = (self._furn_retry_n or 0) + 1
      pcall(function()
        self._furn_prefabs = self:_furn_prefab_map()
        self._furn_tpl_ok = (self._furn_prefabs ~= nil and next(self._furn_prefabs) ~= nil)
        self:_furn_try_all()
      end)
    end
  end
  return self.clock
end
function Adapter:state(key, value)
  if value ~= nil then
    self.state[key] = value
    return value
  end
  local v = self.state[key]
  if v == nil and script and script.GetParam then
    v = script:GetParam(key)           
  end
  return v
end
function Adapter:_save_params(value)
  if type(value) ~= "table" then return { tostring(value) } end
  return {
    tostring(value.level_id or ""),
    tostring(value.state_code or ""),
    tonumber(value.moves) or 0,
    tonumber(value.elapsed) or 0,
    value.solved and true or false,
  }
end
function Adapter:save(key, value, opts)
  self.state[key] = value
  if not (type(opts) == "table" and opts.no_signal) then
    self:signal_emit(self.signals.SAVE, self:_save_params(value))
  end
  return true
end
function Adapter:load(key)
  return self.state[key]
end
function Adapter:signal_emit(name, params)
  if game == nil or game.ServerSignal == nil then return false end
  local sig = game.ServerSignal(name)
  if sig == nil then return false end
  params = params or {}
  for i = 1, #params do
    local v = params[i]
    local tv = type(v)
    if tv == "number" then
      if v == math.floor(v) then sig:AddInt(v) else sig:AddFloat(v) end
    elseif tv == "string" then
      sig:AddString(v)
    elseif tv == "boolean" then
      sig:AddBool(v)
    else
      sig:AddString(tostring(v))
    end
  end
  sig:SendSignal()
  return true
end
function Adapter:signal_on(name, handler)
  if script == nil or script.RegisterServerSignalHandler == nil then return false end
  local schema = M.SIGNAL_SCHEMA[name]
  script:RegisterServerSignalHandler(name, function(sigName, params)
    local payload
    if schema and params then
      payload = {}
      for i = 1, #schema do payload[schema[i]] = params[i] end
    else
      payload = params or {}
    end
    handler(payload)
  end)
  return true
end
function Adapter:random_int(a, b)
  a, b = a or 1, b or 1
  if b < a then a, b = b, a end
  if math.random == nil then return a end
  return a + math.random(0, b - a)
end
function Adapter:play_audio(audio_id)
  if game and game.PlayAudio2D then return game.PlayAudio2D(audio_id) end
  return nil
end
return M
