local M = {}
local function same_value(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end
M.DESIGN = { width = 1920, height = 1080 }
M.FURN_BAKED = false
M.FURN_TPL = true
local FurnArt = require("furn_art")
local FurnRecords = require("furn_art_records")
M.CANVAS = { width = 1600, height = 900 }
M.SCALE  = M.CANVAS.width / M.DESIGN.width     
local function round(v) return math.floor(v + 0.5) end
function M.to_canvas(r)
  local s = M.SCALE
  return {
    cx = round((r.x + r.w / 2) * s),
    cy = round((M.DESIGN.height - r.y - r.h / 2) * s),
    w  = round(r.w * s),
    h  = round(r.h * s),
  }
end
M.SHOW_TOOL_BUTTONS = false
M.TOAST_SECONDS = 2.5
M.HOME_TITLE = "侦探推理 · 摆位谜题"
M.LAYOUT = {
  topbar = { x = 0, y = 0, w = 1920, h = 104 },
  title  = { x = 70, y = 156, w = 540, h = 56 },    
  left   = { x = 24, y = 128, w = 392, h = 880 },
  tray   = { x = 40, y = 148, w = 360, h = 218 },    
  tray_item_h = 104,                                 
  tray_gap_x = 12,
  tray_gap_y = 10,
  tray_per_row = 3,                                  
  clues  = { x = 36, y = 275.4, w = 480, h = 652.8 },   
  clue_row_h = 127.2,        
  clue_max_visible = 18,     
  clue_rows = 5,             
  legend = { x = 40, y = 916, w = 360, h = 76 },    
  board  = { x = 730, y = 166, w = 701, h = 701 },    
  ruler  = 14,
  right  = { x = 1420, y = 128, w = 460, h = 880 },
  modal = { w = 760, h = 720 },    
  side_key = { size = 110, gap = 40, top = 26, right_edge = 1904 },
  progress = { y = 900, h = 60, num_w = 150, icon_gap = 24 },
}
M.EFFECTS = {
  SELECT    = "sel_pop_glow",
  PLACE     = "pop_tile",
  NOTE      = "note_pop",
  XMARK     = "pulse",
  VICTIM    = "portrait_slide_up",
  ERASE     = "vanish",
  UNDO      = "undo_flash",
  SUBMIT    = "submit_nudge",
  SOLVED    = "solved_flash",
  CLUE_IN   = "clue_box_pop",
  FAIL      = "shake",
}
local Controller = {}
Controller.__index = Controller
M.Controller = Controller
Controller._row_letter = {}
Controller._row_face = {}
Controller._row_text = {}
function M.new(core, opts)
  opts = opts or {}
  local self = setmetatable({}, Controller)
  self.core = core
  self.opts = opts
  self.effects = {}
  self.dirty = true
  self.toast = nil
  self.toast_until = nil
  self.now = 0
  self.modal = nil           
  self.screen = opts.screen
  self.select_page = M.SELECT_PAGE or 1
  self.share_code = nil
  self._created = {}
  self._props = {}
  self._gesture_snapshot = nil
  self.debug = opts.debug == true
  self.kb = { r = 1, c = 1 }
  self.kb_active = false
  return self
end
function Controller:fx(target, kind, params)
  local e = { target = target, kind = kind }
  if params then for k, v in pairs(params) do e[k] = v end end
  self.effects[#self.effects + 1] = e
  return e
end
function Controller:_reset_row_maps_if_level_changed()
  local lv = self.core and self.core.level
  local sig = (lv and lv.id) or "?"
  if self._row_map_sig ~= sig then
    self._row_map_sig = sig
    Controller._row_letter = {}
    Controller._row_face = {}
    Controller._row_text = {}
    self._grid_text = nil
    Controller._piece_core = nil
    Controller._piece_id_cache = nil
  end
end
local function mark_list_of(set, vm, resolve)
  if type(set) ~= "table" then return nil end
  local out = {}
  for kk, vv in pairs(set) do
    if vv then
      local id = tostring(kk)
      local letter = nil
      if resolve ~= nil then letter = resolve(vm, id) end
      out[#out + 1] = (letter ~= nil and tostring(letter) ~= "") and tostring(letter) or id
    end
  end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end
function Controller:cell_id(r, c) return string.format("cell.%d.%d", r, c) end
function Controller:finish_accuse(thief, has_acc, acc)
  local core = self.core
  local res
  if has_acc == nil then
    res = core:accuse(thief)
  else
    res = core:accuse_verdict(thief, has_acc, acc)
  end
  self.toast = res.message
  self.toast_until = self.now + M.TOAST_SECONDS    
  if res.solved then
    local okv, v2 = pcall(function() return core:view() end)
    if okv and type(v2) == "table" and type(v2.hud) == "table" then
      self.result_seconds = v2.hud.time
    end
    self.modal = { kind = "result", win = true, message = res.message }
    self:fx("modal", M.EFFECTS.SOLVED)
    local vid = core.victim_id
    if vid ~= nil then self:fx("tray." .. tostring(vid), M.EFFECTS.VICTIM) end
    if self.opts.on_solved then self.opts.on_solved(core:view()) end
  else
    self.modal = nil
    self.result_seconds = nil
    self:fx("modal", M.EFFECTS.FAIL)
  end
  self.dirty = true
  return res
end
function Controller:sync_confirm()
  local want = (self.pending ~= nil)
  self._confirm_shown = want
  self.dirty = true
  return want
end
M.VERDICT_RING_SECONDS = 0.4
M.VERDICT_RING_GAP     = 0.15
function Controller:_placement_snapshot()
  local core = self.core
  local pieces = core and core.pieces
  local snapshot = { n = pieces and #pieces or 0 }
  for i = 1, snapshot.n do
    local id = pieces[i].id
    local p = core.pos and core.pos[id]
    local k = (i - 1) * 4
    snapshot[k + 1], snapshot[k + 2] = id, not not p
    snapshot[k + 3], snapshot[k + 4] = p and p.r, p and p.c
  end
  return snapshot
end
function Controller:_placement_matches(snapshot)
  local core = self.core
  local pieces = core and core.pieces
  if pieces == nil then return snapshot.n == 0 end
  if #pieces ~= snapshot.n then return false end
  for i = 1, #pieces do
    local k = (i - 1) * 4
    local id = pieces[i].id
    local p = core.pos and core.pos[id]
    if id ~= snapshot[k + 1] or (not not p) ~= snapshot[k + 2]
        or (p and p.r) ~= snapshot[k + 3] or (p and p.c) ~= snapshot[k + 4] then
      return false
    end
  end
  return true
end
function Controller:_start_verdict()
  local core = self.core
  if core == nil or core.solution == nil or next(core.solution) == nil or core.pieces == nil then return nil end
  local list, wrong = {}, 0
  for i = 1, #core.pieces do
    local id = core.pieces[i].id
    local p = core.pos and core.pos[id]
    local s = core.solution[id]
    if p ~= nil and s ~= nil then
      local ok = (p.r == s.r and p.c == s.c)
      if not ok then wrong = wrong + 1 end
      list[#list + 1] = { id = id, cell = self:cell_id(p.r, p.c), ok = ok }
    end
  end
  if #list == 0 then return nil end
  self:_clear_verdict()
  self._verdict = {
    list = list, wrong = wrong, t0 = self.now or 0, snapshot = self:_placement_snapshot(),
    level = core.level and core.level.id, done = false, last = {},
  }
  return wrong
end
function Controller:_clear_verdict()
  self._press = nil
  self:_clear_hold_progress()
  self._verdict = nil
  local ad = self._last_adapter
  if ad ~= nil and ad.clear_verdict_rings ~= nil then pcall(function() ad:clear_verdict_rings() end) end
end
function Controller:_verdict_step()
  local v = self._verdict
  if v == nil then return end
  local core = self.core
  local lv = core and core.level and core.level.id
  if core == nil or self.screen ~= nil or lv ~= v.level or not self:_placement_matches(v.snapshot) then
    self:_clear_verdict()
    return
  end
  if v.done and v.animation_complete then return end
  local el = (self.now or 0) - v.t0
  local dur, gap = M.VERDICT_RING_SECONDS, M.VERDICT_RING_GAP
  local ad = self._last_adapter
  local animation_complete = true
  for i = 1, #v.list do
    local a = (el - (i - 1) * (dur + gap)) / dur
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if a < 1 then animation_complete = false end
    if v.last[i] ~= a then
      v.last[i] = a
      if ad ~= nil and ad.set_verdict_ring ~= nil then
        pcall(function() ad:set_verdict_ring(v.list[i].cell, v.list[i].ok, a) end)
      end
    end
  end
  v.animation_complete = animation_complete
  if not v.done and el >= (#v.list - 1) * (dur + gap) + dur then
    v.done = true
    local thief_ok = self:_verdict_thief_ok(v)
    if v.wrong == 0 then
      self:_settle_by_roles()
      self:_mark_outcome("perfect")
    elseif thief_ok == true then
      self:_settle_by_roles()
      self:_mark_outcome("success")
    elseif thief_ok == false then
      self:_show_fail()
    end
    self.dirty = true
  end
end
function Controller:_verdict_thief_ok(v)
  local core = self.core
  local thief = core and core.roles and core.roles.thief
  if thief == nil or v == nil then return nil end
  for i = 1, #v.list do
    if v.list[i].id == thief then return v.list[i].ok == true end
  end
  return nil
end
function Controller:_mark_outcome(kind)
  if self.modal ~= nil and self.modal.kind == "result" and self.modal.win then
    self.modal.outcome = kind
    if self.opts.on_result then
      self.opts.on_result(kind, (self._verdict and self._verdict.wrong) or 0, self.result_seconds or self.core.elapsed or 0)
    end
  end
end
function Controller:_show_fail()
  local core = self.core
  local okv, v2 = pcall(function() return core:view() end)
  self.result_seconds = (okv and type(v2) == "table" and type(v2.hud) == "table") and v2.hud.time or nil
  local got, total = core:score()
  self.modal = { kind = "result", win = false, outcome = "fail",
                 message = string.format("盗窃者没有找对（%d/%d 位置正确）", got, total) }
  self:fx("modal", M.EFFECTS.FAIL)
end
function Controller:_settle_by_roles()
  local core = self.core
  local roles = core.roles or {}
  if roles.thief ~= nil then
    self:finish_accuse(roles.thief, roles.accomplice ~= nil, roles.accomplice)
  else
    self.toast = "本关没配 roles.thief，无法结算（关卡数据问题）"
  end
end
function Controller:do_submit()
  local core = self.core
  if core == nil or core.submit == nil then return end
  local res = core:submit()
  self:fx("hex.submit", M.EFFECTS.SUBMIT)
  self.toast = res and res.message or nil
  self.toast_until = self.now + M.TOAST_SECONDS    
  if res ~= nil and res.ok then
    local wrong = self:_start_verdict()
    if wrong == nil then
      self:_settle_by_roles()
    elseif wrong > 0 then
      local got, total = core:score()
      self.toast = string.format("摆对了 %d / %d 个，红圈是摆错的位置", got, total)
      self.toast_until = self.now + M.TOAST_SECONDS
    end
  end
  self.dirty = true
end
function Controller:do_restart()
  self.core.hint635_used=nil
  self.hint635=nil
  self:_clear_verdict()
  local core = self.core
  if core ~= nil and core.reset ~= nil then core:reset() end
  self._clue_sel_key, self._clue_sel_pos = nil, nil
  self.focused_clue = nil
  self._grid_focus_item, self._grid_focus_orig = nil, nil
  self._grid_focus_idx, self._grid_focus_pos = nil, nil
  self._grid_refill_pending = true
  self.modal = nil
  self.toast = nil
  self.toast_until = nil     
  self.dirty = true
end
function Controller:do_back()
  self:_clear_verdict()
  self.screen = "select"
  self.modal = nil
  self.dirty = true
  if self.opts.on_back then self.opts.on_back() end
end
function Controller:format_time(sec)
  sec = math.max(0, math.floor(sec or 0))
  return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end
local DOUBLE_CLICK_SECONDS = 0.35
local HIGHLIGHT_TINT = 4294956107
local CARD_MAT  = 106053
local CARD_TINT = { r = 250, g = 244, b = 232, a = 0 }    
local LONG_PRESS_SECONDS = 0.28
local HOLD_RING_DELAY = 0.20
local TAP_MOVE_TOLERANCE = 24
M.TEST_CLOCK = nil
local function gesture_now(self)
  local t = rawget(M, "TEST_CLOCK")
  if type(t) == "number" then return t end           
  local ok, c = pcall(os.clock)
  if ok and type(c) == "number" then return c end
  return (self and rawget(self, "now")) or 0
end
local function press_seconds(self)
  local p = rawget(self, "_press")
  if p ~= nil and type(p.dt) == "number" then return p.dt end
  if p ~= nil and type(p.t) == "number" then return gesture_now(self) - p.t end
  return nil
end
M.press_seconds = press_seconds
function Controller:snapshot()
  self._gesture_snapshot = self.core:serialize()
end
function Controller:_refuse(r, c, why)
  if why == nil then return end
  self:fx(self:cell_id(r, c), M.EFFECTS.FAIL)
  self._refuse_seen = self._refuse_seen or {}
  local n = self._refuse_seen[why] or 0
  if n >= 3 then return end
  self._refuse_seen[why] = n + 1
  if print then
    print("[murdoku] 点 (第" .. tostring(r) .. "行 第" .. tostring(c) .. "列) 没生效："
      .. tostring(why) .. "  当前工具=" .. tostring(self.core and self.core.mode)
      .. "  已选=" .. tostring(self.core and self.core.selected)
      .. "（同类提示最多打 3 次）")
  end
end
function Controller:do_place(r, c)
  local core = self.core
  self.last_click = nil
  local who = core.selected
  local _sel_before = core.selected
  local _notes_before = 0
  pcall(function()
    for rr, row in pairs(core.notes or {}) do for cc, set in pairs(row) do
      for id, v in pairs(set) do if v then _notes_before = _notes_before + 1 end end
    end end
  end)
  local ok, why = core:hold_cell(r, c)
  if ok then
    local _notes_after, _n2 = 0, 0
    pcall(function()
      for rr, row in pairs(core.notes or {}) do for cc, set in pairs(row) do
        for id, v in pairs(set) do if v then _notes_after = _notes_after + 1 end end
      end end
    end)
    if (_sel_before ~= nil) and core.placed and core.placed[_sel_before] then _n2 = 1 end
    print("[murdoku] ★ 放置分辨：走的=【正式放置 hold_cell】 人=" .. tostring(_sel_before)
      .. "  笔记 " .. tostring(_notes_before) .. " ⇒ " .. tostring(_notes_after)
      .. "  放后选中=" .. tostring(core.selected) .. "  placed=" .. tostring(_n2 == 1))
  end
  local _pi, _pix, _ppx = self._grid_focus_item, self._grid_focus_idx, self._grid_focus_pos
  if _pi ~= nil then
    local _pc = nil
    pcall(function() _pc = self:_grid_item_child_cached(_pi, _pix or 0, _ppx or 0, "backrop1") end)
    if _pc ~= nil and self._grid_focus_orig ~= nil then
      pcall(function() _pc.imageColor = self._grid_focus_orig end)
    end
    self._grid_focus_item, self._grid_focus_orig = nil, nil
  end
  self.focused_clue = nil
  self.dirty = true
  if ok then
  self._grid_refill_pending = true
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end
function Controller:do_pre_place(r, c)
  local core = self.core
  self.last_click = nil
  local who = core.selected
  local _sel_b2 = core.selected
  local ok, why = core:pre_place(r, c)
  if ok then
    print("[murdoku] ★ 放置分辨：走的=【预放置 pre_place】 人=" .. tostring(_sel_b2)
      .. "  放后选中=" .. tostring(core.selected) .. "（★ 应仍是 " .. tostring(_sel_b2) .. " ✓）")
  end
  if ok then
  self._grid_refill_pending = true
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end
function Controller:_clear_hold_progress()
  local ad = self._last_adapter
  if ad and ad.clear_hold_ring then ad:clear_hold_ring() end
end
function Controller:_hold_progress(p)
  if self.screen ~= nil or self.modal ~= nil or self.pending ~= nil then
    self._press = nil
    self:_clear_hold_progress()
    return
  end
  local ad = self._last_adapter
  if p and p.r and p.c and self.core and self.core.selected and ad and ad.set_hold_ring then
    if (p.dt or 0) < HOLD_RING_DELAY then return end
    ad:set_hold_ring(self:cell_id(p.r, p.c), math.min(1, ((p.dt or 0)-HOLD_RING_DELAY) / (LONG_PRESS_SECONDS-HOLD_RING_DELAY)))
  else
    self:_clear_hold_progress()
  end
end
function Controller:on_cell_down(r, c, x, y)
  self:_clear_hold_progress()
  self._press = { r = r, c = c, dt = 0, t = gesture_now(self), x = x, y = y }
  self:_hold_progress(self._press)
  return false
end
function Controller:on_cell_up(r, c, x, y)
  local p = self._press
  local dt = press_seconds(self)
  self._press = nil
  self:_clear_hold_progress()
  if p == nil then return false end
  if p.r ~= r or p.c ~= c then return false end           
  if dt == nil then return false end
  if dt < LONG_PRESS_SECONDS then return false end          
  if p.x ~= nil and x ~= nil then
    local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
    if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then return false end
  end
  local ok = self:do_place(r, c)
  print("[murdoku] ★ 放置分辨：抬起被判定为【长按】✓ 时长=" .. string.format("%.2f", dt))
  do
    local _s = rawget(self, "_lp_stat")
    if _s == nil then _s = { n = 0, sum = 0, min = nil, max = nil, half = {} }; self._lp_stat = _s end
    _s.n = _s.n + 1
    _s.sum = _s.sum + dt
    if _s.min == nil or dt < _s.min then _s.min = dt end
    if _s.max == nil or dt > _s.max then _s.max = dt end
    if _s.n <= 4 then _s.half[1] = (_s.half[1] or 0) + dt else _s.half[2] = (_s.half[2] or 0) + dt end
    if _s.n == 8 and type(print) == "function" then
      local h1 = (_s.half[1] or 0) / 4
      local h2 = (_s.half[2] or 0) / 4
      print(string.format(
        "[murdoku] ★ 长按时长统计（前 8 次）：最小=%.2f 最大=%.2f 平均=%.2f"
        .. "　★ 前 4 次均=%.2f / 后 4 次均=%.2f ⇒ ★ %s",
        _s.min, _s.max, _s.sum / _s.n, h1, h2,
        (h2 > h1 * 1.5) and "**后一半明显更大 ⇒ 还在漂移** ✗（把这两行发我）"
          or "前后差不多 ⇒ ★ 已经好了 ✓（剩下的浮动是【手的时长】✓ 不是漂移 ✓）"))
    end
  end
  if ok then
    self._suppress_click = true      
  end
  return ok
end
function Controller:on_cell_drag(r, c, x, y)
  local p = self._press
  if p == nil then return false end
  if p.x == nil or x == nil then return false end
  local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
  if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then
    self._press = nil
    self:_clear_hold_progress()
    return true
  end
  return false
end
function Controller:on_cell_click(r, c)
  if r == nil or c == nil then return end
  local core = self.core
  self.now = self.now or 0
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode
  if (not occupied) and mode == "place" then
    local last = self.last_click
    if last and last.r == r and last.c == c and (gesture_now(self) - last.t) <= DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      if last.did == "x" then
        core:toggle_x(r, c)              
        self.dirty = true
      elseif last.did == "pre" then
        core:undo()                      
        self.dirty = true
      end
      self:do_pre_place(r, c)
      return
    end
  end
  local had = core.grid[r][c]
  local had_selected = core.selected           
  local ok, why = core:tap_cell(r, c)
  if ok then
    if had then
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
      self._grid_refill_pending = true
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = gesture_now(self),
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = gesture_now(self), did = "none" }
    end
    self:_refuse(r, c, why)
  end
end
local KB_ACTIONS = {
  KeyboardCraftspersonKey36Down = "up",
  KeyboardCraftspersonKey37Down = "down",
  KeyboardCraftspersonKey38Down = "left",
  KeyboardCraftspersonKey39Down = "right",
  KeyboardCraftspersonKey1Down  = "pick1",
  KeyboardCraftspersonKey2Down  = "pick2",
  KeyboardCraftspersonKey3Down  = "pick3",
  KeyboardCraftspersonKey4Down  = "pick4",
  KeyboardCraftspersonKey5Down  = "pick5",
  KeyboardCraftspersonKey6Down  = "pick6",
  KeyboardCraftspersonKey7Down  = "pick7",
  KeyboardCraftspersonKey8Down  = "pick8",
  KeyboardCraftspersonKey9Down  = "pick9",
  KeyboardCraftspersonKey10Down = "pick10",
  KeyboardInteractKeyDown       = "place",    
  KeyboardJumpKeyDown           = "note",     
  KeyboardDropKeyDown           = "xmark",    
  KeyboardCraftspersonKey42Down = "back",      
  KeyboardOpenShortcutWheelKeyDown = "tool",     
  KeyboardCharacterSkill1KeyDown   = "eraser",   
  KeyboardCharacterSkill3KeyDown   = "submit",   
  KeyboardCraftspersonKey12Down    = "undo",     
  KeyboardCraftspersonKey13Down    = "redo",     
  KeyboardCraftspersonKey15Down    = "hint",     
}
local KB_DELTA = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }
local KB_TOOL_CYCLE = { "place", "note", "x", "eraser" }
function Controller:kb_move(dr, dc)
  local kb = self.kb or { r = 1, c = 1 }
  local r = math.min(self.core.rows, math.max(1, kb.r + dr))
  local c = math.min(self.core.cols, math.max(1, kb.c + dc))
  if r ~= kb.r or c ~= kb.c or not self.kb_active then
    self.kb_active = true
    self.dirty = true
  end
  self.kb = { r = r, c = c }
end
local function kb_action_of(event)
  return KB_ACTIONS[tostring(event.key or "")]
end
function Controller:on_key(event)
  local core = self.core
  local act = kb_action_of(event)
  if act == nil then return false end
  local d = KB_DELTA[act]
  if d ~= nil then
    self:kb_move(d[1], d[2])
    return true
  end
  local n = act:match("^pick(%d+)$")
  if n ~= nil then
    local i = tonumber(n)
    local vm = core:view()
    if i >= 1 and i <= #vm.tray then
      self:on_input({ action = "suspect", id = vm.tray[i].id })
      return true
    end
    return false
  end
  if act == "note" then
    local kb = self.kb
    if kb ~= nil then
      self.kb_active = true
      self:on_cell_click(kb.r, kb.c)
      return true
    end
    return false
  end
  if act == "place" then
    local kb = self.kb
    if kb ~= nil then
      self.kb_active = true
      self:do_place(kb.r, kb.c)
      return true
    end
    return false
  end
  if act == "tool" then
    local mode = core.mode or "place"
    local idx = 1
    for i = 1, #KB_TOOL_CYCLE do if KB_TOOL_CYCLE[i] == mode then idx = i end end
    self:on_input({ action = "tool", mode = KB_TOOL_CYCLE[idx % #KB_TOOL_CYCLE + 1] })
    return true
  end
  if act == "xmark"  then self:on_input({ action = "tool", mode = "x" });      return true end
  if act == "eraser" then self:on_input({ action = "tool", mode = "eraser" }); return true end
  if act == "undo"   then self:on_input({ action = "undo" });                  return true end
  if act == "redo"   then self:on_input({ action = "redo" });                  return true end
  if act == "hint"   then self:on_input({ action = "hint" });                  return true end
  if act == "submit" then self:on_input({ action = "submit" });                return true end
  if act == "back" then
    if self.modal ~= nil then self:on_input({ action = "close_modal" })
    else self:on_input({ action = "level_list" }) end
    return true
  end
  return false
end
function Controller:hint635_action(action)
  if self.screen ~= nil or self.modal ~= nil then return end
  local core=self.core
  core.hint635_used=core.hint635_used or {position=0,clue=0}
  local used=core.hint635_used
  local function message(text, timed)
    self.hint635={kind="message",text=text,until_time=timed and ((self.now or 0)+3) or nil}
  end
  if action=="close" then self.hint635=nil;return end
  if action=="toggle" then
    if self.hint635 then
      self.hint635=nil
    elseif not core.selected and self.general_focus~=true then
      message("请先选中一条线索卡",true)
    else
      self.hint635={kind="menu"}
    end
    return
  end
  if not self.hint635 or self.hint635.kind~="menu" then return end
  if action=="position" then
    if used.position>=1 then message("本关揭示位置次数已用完",true);return end
    local ok,msg=core:hint()
    if not ok then message(msg,true);return end
    used.position=used.position+1
    self.hint635=nil
    self:_clear_verdict();self._grid_refill_pending=true
    self._clue_sel_key,self._clue_sel_pos=nil,nil;self.focused_clue=nil
    self.dirty=true;self:fx("hex.hint",M.EFFECTS.SELECT)
  elseif action=="clue" then
    if used.clue>=2 then message("本关验证线索次数已用完",true);return end
    self:_sync_clue_focus()
    local general=self.general_focus==true
    local index=general and 1 or self.focused_clue
    if not index or (not general and not core.selected) then message("请先选中一条线索卡",true);return end
    local truth=core:answer_clue(index,general)
    if truth==nil then message("请先选中一条线索卡",true);return end
    used.clue=used.clue+1
    message(truth and "该线索为真" or "该线索为假",false)
  end
end
function Controller:on_input(event)
  local core = self.core
  local a = event.action
  if event.phase == "key" then
    self:on_key(event)
    return self.effects
  end
  if event.phase == "down" then
    if a == "click" then self:on_cell_down(event.r, event.c, event.x, event.y) end
    return self.effects
  end
  if event.phase == "up" then
    if a == "click" then self:on_cell_up(event.r, event.c, event.x, event.y) end
    return self.effects
  end
  if event.phase == "drag" then
    if a == "click" then self:on_cell_drag(event.r, event.c, event.x, event.y) end
    return self.effects
  end
  if a == "suspect" then
    core:tap_suspect(event.id)
    local vm = core:view()
    if vm.hud.selected == event.id then
      self:fx("tray." .. tostring(event.id), M.EFFECTS.SELECT)
    end
    if self.modal and self.modal.kind == "accuse" then
      self.modal = { kind = "accuse" }    
    end
  elseif a == "gesture_begin" then
    self:snapshot()
  elseif a == "gesture_rollback" then
    if self._gesture_snapshot then
      core:deserialize(self._gesture_snapshot)
      self.toast = "已回滚本次操作"
      self.toast_until = self.now + M.TOAST_SECONDS    
      self:fx("board", M.EFFECTS.UNDO)
    end
  elseif a == "click" then
    if self._suppress_click then
      self._suppress_click = nil
    else
      self:on_cell_click(event.r, event.c)
    end
  elseif a == "cell_right" then
    if core:toggle_x(event.r, event.c) then
      self:fx(self:cell_id(event.r, event.c), M.EFFECTS.XMARK)
    end
  elseif a == "tool" then
    if print then
      self._tool_log = (self._tool_log or 0) + 1
      if self._tool_log <= 12 then
        print("[murdoku] 切换工具 → " .. tostring(event.mode)
          .. "（之前是 " .. tostring(core.mode) .. "）")
      end
    end
    core:set_mode(event.mode)
  elseif a == "back_confirm" then
    self.modal = { kind = "exit_menu" }    
    self.dirty = true
    self:sync_confirm()
    self:fx("hex.back", M.EFFECTS.SELECT)
  elseif a == "submit" then
    self.pending = { action = "submit" }
    self:sync_confirm()
    self:fx("hex.submit", M.EFFECTS.SELECT)
  elseif a == "restart" then
    self.pending = { action = "restart" }
    self:sync_confirm()
    self:fx("hex.redo", M.EFFECTS.SELECT)
  elseif a == "confirm_no" then
    self.pending = nil
    self:sync_confirm()
    self.toast = "已取消"
    self.toast_until = self.now + M.TOAST_SECONDS    
  elseif a == "confirm_yes" then
    local p = self.pending
    self.pending = nil
    self:sync_confirm()
    if p ~= nil then
      if p.action == "submit" then
        self:do_submit()
      elseif p.action == "restart" then
        self:do_restart()
      elseif p.action == "back" then
        self:do_back()
      end
    end
  elseif a == "undo" then
    self:fx("hex.undo", M.EFFECTS.SELECT)
    if core:undo() then
      self:fx("hex.undo", M.EFFECTS.UNDO)
      self._grid_refill_pending = true
      self.dirty = true
    end
  elseif a == "redo" then
    if core:redo() then
      self:fx("hex.redo", M.EFFECTS.UNDO)
      self._grid_refill_pending = true
      self.dirty = true
    end
  elseif a == "hint" then
    self:hint635_action("toggle")
  elseif a == "reveal" then
    core:reset()
    self._clue_sel_key, self._clue_sel_pos = nil, nil
    self.focused_clue = nil
    for id, p in pairs(core.solution) do
      core:select_suspect(id)
      core:hold_cell(p.r, p.c)
    end
    self.toast = "已揭示答案"
    self.toast_until = self.now + M.TOAST_SECONDS    
  elseif a == "accuse" then
    local code = core:encode_state()
    self.share_code = code
    self.modal = { kind = "share", code = code }
    if self.opts.on_share then self.opts.on_share(code) end
  elseif a == "howto" then
    self.modal = { kind = "howto" }
  elseif a == "close_modal" then
    self:_clear_verdict()
    self.modal = nil
  elseif a == "exit_menu_go" then
    self.modal = nil
    self.screen = "select"
    self.dirty = true
    if self.opts.on_back then self.opts.on_back() end
  elseif a == "exit_menu_save" then
    if self.opts.on_save then self.opts.on_save() end
    self.modal = nil
    self.dirty = true
  elseif a == "exit_menu_settle" then
    if not self:can_settle() then return end
    if self.opts.on_save then self.opts.on_save() end
    if self.opts.on_settle then self.opts.on_settle() end
    self.dirty = true
  elseif a == "level_list" then
    self.modal = { kind = "levelselect" }
  elseif a == "select_page" then
      self.select_page = (tonumber(self.select_page) or 1) + (tonumber(event.delta) or 0)
      if self.select_page < 1 then self.select_page = 1 end
      M.SELECT_PAGE = self.select_page
      self.dirty = true
  elseif a == "settle_only" then
    if not self:can_settle() then return end
    if self.opts.on_settle_only then self.opts.on_settle_only() end
    elseif a == "pick_level" then
    if self.opts.on_pick_level then
      self.modal = nil
      self.opts.on_pick_level(event.id)
      self.screen = nil               
    end
  elseif a == "home" then
    self.screen = "home"; self.modal = nil; self.dirty = true
  elseif a == "replay" then
    self.result_seconds = nil
    self:do_restart()
  elseif a == "levelselect" then
    self.screen = "select"; self.modal = nil; self.dirty = true; self.select_page = 1; M.SELECT_PAGE = 1
  elseif a == "continue" then
    local last = self.opts.last_level and self.opts.last_level() or nil
    if last and self.opts.on_pick_level then
      self.screen = nil
      self._continue_requested = true
      self.opts.on_pick_level(last)
      self._continue_requested = nil
    else
      self.toast = "还没有游玩记录，先从「选关」开始吧"
      self.toast_until = self.now + M.TOAST_SECONDS    
      self.screen = "select"
    end
    self.dirty = true
  elseif a == "shop" or a == "bag" then
    self.toast = (a == "shop") and "商城：美术资源就绪后开放" or "背包：美术资源就绪后开放"
    self.toast_until = self.now + M.TOAST_SECONDS    
    self.dirty = true
  elseif a == "clue_up" or a == "clue_down" then
    local rows = M.LAYOUT.clue_rows or 9
    local shown = math.min(#self.core:view().clues, M.LAYOUT.clue_max_visible)
    local maxscroll = math.max(0, shown - rows)
    local s = self.clue_scroll or 0
    if a == "clue_up" then s = s - 1 else s = s + 1 end
    if s < 0 then s = 0 end
    if s > maxscroll then s = maxscroll end
    self.clue_scroll = s
    self.dirty = true
  elseif a == "focus_general" then
    pcall(function()
      if self.core ~= nil and type(self.core.clue_hint_general) == "function" then
        self.general_focus = true           
        self.general_hint = self.core:clue_hint_general(1)
      end
    end)
  elseif a == "focus_clue" then
    self.general_focus = nil              
    local ci = event.index
    if ci ~= nil then
      self:fx("clue." .. tostring(ci), M.EFFECTS.CLUE_IN)
    end
  elseif a == "back" then
    self.screen = "select"
    self.modal = nil
    self.dirty = true
    if self.opts.on_back then self.opts.on_back() end
  elseif a == "next_level" and self.opts.on_next_level then
    self.opts.on_next_level()
  end
  self:_sync_clue_focus()
  self.dirty = true
  return self.effects
end
function Controller:can_settle()
  local session = self.opts and self.opts.settle_session
  if self.core.status == "solved" then
    if session then session.unlocked = true else self._settle_unlocked = true end
    return true
  end
  return (session and session.unlocked == true) or self._settle_unlocked == true
end
function Controller:settle_seconds_left()
  if self:can_settle() then return 0 end
  local session = self.opts and self.opts.settle_session
  return math.max(1, math.ceil(60 - (session and session.elapsed or self._settle_elapsed or 0)))
end
function Controller:tick(dt)
  if not (self.opts and self.opts.settle_session) and not self._settle_unlocked then
    self._settle_elapsed = math.min(60, (self._settle_elapsed or 0) + math.max(0, dt or 0))
    if self._settle_elapsed >= 60 then self._settle_unlocked = true end
  end
  local remaining = self:settle_seconds_left()
  if self._settle_display_second ~= remaining then
    self._settle_display_second = remaining
    if self.screen == "home" or self.screen == "select" or
       (self.modal and (self.modal.kind == "result" or self.modal.kind == "exit_menu")) then
      self.dirty = true
    end
  end
  self.now = (self.now or 0) + (dt or 0)
  if self.hint635 and (self.screen~=nil or self.modal~=nil or
      (self.hint635.until_time and self.now>=self.hint635.until_time)) then self.hint635=nil end
  self._frame_n = (self._frame_n or 0) + 1    
  if self._verdict ~= nil then pcall(self._verdict_step, self) end    
  do
    local p = rawget(self, "_press")
    if p ~= nil then
      p.dt = (p.dt or 0) + (dt or 0)
      self:_hold_progress(p)
      p = self._press
    end
    if p ~= nil and p.fired ~= true and p.dt >= LONG_PRESS_SECONDS then
      p.fired = true
      pcall(function()
        if p.r ~= nil and p.c ~= nil then
          self:fx(self:cell_id(p.r, p.c) .. ".face", M.EFFECTS.SELECT)
          self.dirty = true
        end
      end)
    end
  end
  if self.toast ~= nil and self.toast_until ~= nil and self.now >= self.toast_until then
    self.toast = nil
    self.toast_until = nil
    self.dirty = true
  end
  local elapsed = (self.core.elapsed or 0) + (dt or 0)
  self.core:set_elapsed(elapsed)
  if #self.effects > 0 then self.dirty = true end
end
local function rect_of(t) return { x = t.x, y = t.y, w = t.w, h = t.h } end
local function is_legacy_clue_id(id)
  if type(id) ~= "string" then return false end
  if id:sub(1, 5) == "clue." then return true end
  return id == "clues.up" or id == "clues.down" or id == "clues.track"
      or id == "clues.knob" or id == "clues.count" or id == "clues.more"
      or id == "clues.bar"
end
local function apply_screen_hide(nodes, screen)
  if nodes == nil then return end
  local HIDE, PREFIX = {}, {}
  if screen == nil then
    PREFIX = { "home", "select" }
  else
    HIDE = {
      topbar = true, toolbar = true, left = true, board = true, right = true,
      toast = true, modal = true, intro = true, clues = true,
      ["action.redo"] = true, ["action.hint"] = true,
      ["action.undo"] = true, ["action.submit"] = true, ["action.reveal"] = true,
    }
    HIDE["selbar"] = true
    HIDE["tpl-container"] = true
    for _, id in ipairs({ "hit.back", "hit.submit", "hit.redo", "hit.undo",
                          "hit.hint", "hit.ok", "hit.no" }) do
      HIDE[id] = true
    end
    PREFIX = { "clue.", "hud.", "room.label.", "tray.", "action.", "hex.",
               "selbtn.", "tpl.",
               (screen == "home") and "select." or "home." }
  end
  for i = 1, #nodes do
    local id = nodes[i].id
    local hide = HIDE[id] == true
    if not hide then
      for k = 1, #PREFIX do
        if id:sub(1, #PREFIX[k]) == PREFIX[k] then hide = true break end
      end
    end
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    if hide then nodes[i].visible = false end
  end
end
local function split_by_name(vm, txt)
  if type(vm) ~= "table" or type(vm.tray) ~= "table" then return nil, txt, nil, nil, nil end
  local best, bestIt = nil, nil
  for _, it in ipairs(vm.tray) do
    local nm = tostring(it.name or it.short or it.id or "")
    if nm ~= "" and txt:find(nm, 1, true) then
      if best == nil or #nm > #best then best, bestIt = nm, it end
    end
  end
  if best == nil then return nil, txt, nil, nil, nil end
  local at = txt:find(best, 1, true)
  local pre, post = txt:sub(1, at - 1), txt:sub(at + #best)
  return best, pre, post, bestIt and tostring(bestIt.id) or nil, bestIt and bestIt.portrait or nil
end
function Controller:toast_text()
  local t = self.toast
  if t == nil then return nil end
  t = tostring(t)
  if t == "" then return nil end
  return t
end
function Controller:build_layout(ui_adapter)
  local vm = self.core:view()
  local L = M.LAYOUT
  local nodes = {}
  local furn_art = nil
  local furn_recs = nil
  local furn_tpl, furn_span, furn_offset = {}, {}, {}
  local level_id = nil         
  do
    local keys = {}
    for r = 1, vm.rows do
      keys[r] = {}
      for c = 1, vm.cols do
        keys[r][c] = Controller.object_key_of(vm, vm.cells[r][c]) or false
      end
    end
    local cur_lv = nil
    do
      local lv_list = self.opts.levels
      local arr = {}
      if type(lv_list) == "function" then arr = lv_list() or {}
      elseif type(lv_list) == "table" then arr = lv_list end
      local want = tostring(self.opts.current_level or "")
      for i = 1, #arr do
        if tostring(arr[i].id) == want then cur_lv = arr[i] break end
      end
    end
    furn_art = FurnArt.layout(vm, keys, cur_lv and cur_lv.room_names or nil)
    furn_art.kind_of = {}
    for r = 1, vm.rows do
      furn_art.kind_of[r] = {}
      for c = 1, vm.cols do
        local k = keys[r] and keys[r][c]
        furn_art.kind_of[r][c] = k and (k:match("^obj%.(.+)$") or k) or nil
      end
    end
    level_id = cur_lv and cur_lv.id or nil
    local TPL_KEY = {
      chair = "furn.chair", plant = tostring(level_id) == "case_001" and "furn.plant.2" or "furn.plant", statue = "furn.statue",
      shelf = "furn.shelf",
      table = { ["1"] = "furn.table", h2 = "furn.table.h2", v2 = "furn.table.v2" },
      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3",
                 L3a = "furn.rug.4", L3b = "furn.rug.5" },
    }
    for r = 1, vm.rows do
      furn_tpl[r], furn_span[r], furn_offset[r] = {}, {}, {}
      for c = 1, vm.cols do furn_tpl[r][c], furn_span[r][c], furn_offset[r][c] = false, false, false end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if p.anchor ~= nil then    
        local variant = "1"
        if kind == "carpet" and (p.variant == "L3a" or p.variant == "L3b") then
          variant = p.variant
        elseif (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end
        local tk = TPL_KEY[kind]
        if type(tk) == "table" then tk = tk[variant] end
        if tk ~= nil then
          local b = p.box or { r1 = p.anchor.r, r2 = p.anchor.r, c1 = p.anchor.c, c2 = p.anchor.c }
          furn_tpl[p.anchor.r][p.anchor.c] = tk
          furn_span[p.anchor.r][p.anchor.c] = { r = p.span_r or 1, c = p.span_c or 1 }
          furn_offset[p.anchor.r][p.anchor.c] = {
            dx = (b.c1 + b.c2) * 0.5 - p.anchor.c,
            dy = (b.r1 + b.r2) * 0.5 - p.anchor.r,
          }
        end
      end
    end
    furn_recs = {}
    for r = 1, vm.rows do
      furn_recs[r] = {}
      for c = 1, vm.cols do furn_recs[r][c] = nil end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if M.FURN_BAKED then break end    
      if false then
        local list = FurnRecords and FurnRecords[kind]
        if list ~= nil then
          local b = p.box
          local span_r = b.r2 - b.r1 + 1
          local span_c = b.c2 - b.c1 + 1
          local variant = "1"
          if span_c > 1 then variant = "h2"
          elseif span_r > 1 then variant = "v2" end
          local recs = list[variant]
          if recs ~= nil then
            local anchor = p.anchor
            local ox = (b.c1 + b.c2) * 0.5 - anchor.c    
            local oy = (b.r1 + b.r2) * 0.5 - anchor.r
            local out = {}
            for i = 1, #recs do
              local e = recs[i]
              out[i] = { e[1], e[2], e[3], e[4] + ox, e[5] + oy, e[6], e[7] }
            end
            furn_recs[anchor.r][anchor.c] = out
          end
        end
      end
    end
  end
  nodes[#nodes + 1] = {
    id = "root", kind = "container", parent = nil, visible = true,
    rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height },
    furn_level = (level_id and self.screen == nil) or false,
    baked_level = (M.FURN_BAKED and level_id and self.screen == nil) or false,
    pos_runtime = true,
  }
    local OBJECT_PALETTE_DISABLED = nil    
    local K = 6 / 5                                     
    local function D(v) return math.floor(v * K + 0.5) end
    local ICON_ASSETS = {
      { "hex.back",   100109,   60,   48,  62,  62, "back_confirm" },   
      { "hex.submit", 100110, 1448,   48,  70,  70, "submit"       },   
      { "hex.redo",   100126, 1448,  144,  70,  70, "restart"      },   
      { "hex.undo",   100127, 1448,  240,  70,  70, "undo"         },   
      { "hex.hint",   100120, 1448,  694,  70,  70, "hint"         },   
      { "hex.ok",     100102,  438,   52,  54,  54, "confirm_yes"  },   
      { "hex.no",     100101,  500,   52,  54,  54, "confirm_no"   },   
    }
    local CONFIRM_GAP = 8
    local CONFIRM_ANCHOR = {
      back    = { x = 347 + CONFIRM_GAP,                            y = 48  },   
      submit  = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 48  },   
      restart = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 144 },   
    }
    local pend_action = (self.pending and self.pending.action) or nil
    local function key_box_canvas(action)
      local id = (action == "submit" and "hex.submit")
        or (action == "restart" and "hex.redo")
        or (action == "back" and "hex.back") or nil
      if id == nil or ui_adapter == nil or type(ui_adapter.find) ~= "function" then return nil end
      local ctrl = nil
      pcall(function() ctrl = ui_adapter:find(id) end)
      if ctrl == nil or ctrl.GetSizeDelta == nil or ctrl.GetAnchoredPosition == nil then return nil end
      local w, h, ax, ay = nil, nil, nil, nil
      pcall(function() w, h = ctrl:GetSizeDelta() end)
      pcall(function() ax, ay = ctrl:GetAnchoredPosition() end)
      if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
      if type(ax) ~= "number" or type(ay) ~= "number" then return nil end
      local cfg = ui_adapter.cfg or {}
      local cw = cfg.canvas_w or 1600
      local ch = cfg.canvas_h or 900
      local cx = cw * 0.5 + ax           
      local cy = ch * 0.5 + ay           
      return { x = cx - w * 0.5, y = (ch - cy) - h * 0.5, w = w, h = h }
    end
    local anchor = CONFIRM_ANCHOR[pend_action] or CONFIRM_ANCHOR.back
    do
      local kb = key_box_canvas(pend_action)
      if kb ~= nil then
        local cy2 = kb.y + (kb.h - 54) * 0.5
        if pend_action == "back" then
          anchor = { x = kb.x + kb.w + CONFIRM_GAP, y = cy2 }
        else
          anchor = { x = kb.x - CONFIRM_GAP - 54 - CONFIRM_GAP - 54, y = cy2 }
        end
      end
    end
    local icon_pending_on = (self.pending ~= nil)
    for i = 1, #ICON_ASSETS do
      local a = ICON_ASSETS[i]
      local is_confirm = (a[1] == "hex.ok" or a[1] == "hex.no")
      local ax, ay = a[3], a[4]
      if a[1] == "hex.ok" then ax, ay = anchor.x, anchor.y end
      if a[1] == "hex.no" then ax, ay = anchor.x + 54 + CONFIRM_GAP, anchor.y end
      local is_confirm_icon = (a[1] == "hex.ok" or a[1] == "hex.no")
      local vis = (not is_confirm) or icon_pending_on
      local rect = { x = D(ax), y = D(ay), w = D(a[5]), h = D(a[6]) }
      nodes[#nodes + 1] = {
        id = a[1], kind = "button", parent = "root",
        visible = vis,
        image_id = a[2],
        imageType = "Stretch",
        icon_template = true,           
        rect = rect,
        pos_runtime = is_confirm_icon or nil,
      }
      local is_confirm_hit = (a[1] == "hex.ok" or a[1] == "hex.no")
      nodes[#nodes + 1] = {
        id = "hit." .. a[1]:sub(5), kind = "button", parent = "root",
        visible = vis,
        event = { action = a[7] },
        icon_template = false,          
        rect = rect,
        pos_runtime = is_confirm_hit or nil,
      }
    end
  local function push(n)
    if n.visible == nil then n.visible = true end
    nodes[#nodes + 1] = n
    return n
  end
  local function btn(id, parent, r, text, event, style, enabled)
    return push({ id = id, kind = "button", parent = parent, rect = r, text = text,
                  style = style or "stamp", enabled = (enabled ~= false), event = event,
                  settle_shift = (id == "modal.cancel") and 0 or nil })
  end
  local function push_settle_countdowns()
    local remaining = self:settle_seconds_left()
    local gate_text = tostring(remaining) .. "秒后可结算"
    for _, spec in ipairs({
      {"settle.btn.countdown", "root", (self.screen == "home" or self.screen == "select")},
      {"result.settle.countdown", "modal", self.modal and self.modal.kind == "result"},
      {"modal.settle.countdown", "modal", self.modal and self.modal.kind == "exit_menu"},
    }) do
      push({id=spec[1], kind="text", parent=spec[2], visible=spec[3] and remaining > 0 or false,
            text=gate_text, rect={x=0,y=0,w=240,h=40}})
    end
  end
  push({ id = "root", kind = "container", rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }, style = "screen" })
  push({ id = "stage", kind = "container", parent = "root", rect = rect_of(L.board), style = "stage" })
  push({ id = "topbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "topbar" })
  push({ id = "hud.title", kind = "text", parent = "topbar", rect = rect_of(L.title), text = vm.title, style = "title" })
  local function tool(id, label, mode, x)
    return push({ id = id, kind = "button", parent = "toolbar",
                  rect = { x = x, y = 26, w = 130, h = 52 }, text = label,
                  style = (vm.hud.mode == mode) and "tab.active" or "tab",
                  visible = (M.SHOW_TOOL_BUTTONS == true),
                  event = { action = "tool", mode = mode } })
  end
  if M.SHOW_TOOL_BUTTONS then
    tool("tool.place",  "放置",  "place",  840)
    tool("tool.x",      "X 标记", "x",      978)
    tool("tool.eraser", "橡皮擦", "eraser", 1116)
  end
  local RB = L.side_key.right_edge
  local PG = L.progress
  push({ id = "hud.progress", kind = "text", parent = "right",
         rect = { x = RB - 110 - PG.icon_gap - PG.num_w, y = PG.y, w = PG.num_w, h = PG.h },
         text = string.format("%d / %d", self:placed_count(vm), vm.piece_count),
         style = "stat" })
  push({ id = "hud.timer", kind = "text", parent = "topbar",
         rect = { x = 72, y = 216, w = 340, h = 56 },
         text = self:format_time(vm.hud.time), style = "stat" })
  push({ id = "clues", kind = "container", parent = "root", rect = rect_of(L.clues),
         style = "panel" })
  push({ id = "clues.bg", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         visible = (self.screen == nil) })
  push({ id = "clues.grid", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         visible = (self._grid_state ~= "off"),
         })
  local grid_on = (self._grid_state == "on")
  if grid_on then
    self:_grid_log("giveway", "网格视窗：老的一套线索控件**整段不进规划**（不建 / 不摆 / 不点亮 / "
      .. "连动效都不排队）—— 只藏起来不够：`clue.N.*` 这个名字会被按名字抓到已回收的列表项")
  end    
  if grid_on then
    local dropped, kept = 0, 0
    for i = 1, #nodes do
      if is_legacy_clue_id(nodes[i].id) then
        dropped = dropped + 1
      else
        kept = kept + 1
        nodes[kept] = nodes[i]
      end
    end
    for i = #nodes, kept + 1, -1 do nodes[i] = nil end
    self._grid_gave_way = dropped
    if dropped > 0 then
      self:_grid_log("giveway_leak", "网格视窗：**守卫之外**还漏发了 " .. tostring(dropped)
        .. " 个老线索控件，已在收口处剔除（查一下是不是新加了 `clue.*` 的 push）")
    end
  end
  local legend_text =
    "单击空格=划掉这格（再点取消）\n"
    .. "选中头像后单击=假设他在这里\n"
    .. "双击/长按=正式放置　单击已放的格=拿起"
  if self.input_profile == "touch" then
    legend_text =
      "轻触空格=划掉这格（再点取消）\n"
      .. "选中头像后轻触=假设他在这里\n"
      .. "长按=正式放置　轻触已放的格=拿起"
  elseif self.input_profile == "pc" then
    legend_text = legend_text .. "\n"
      .. "键盘(默认键)：方向键移动　F放置　空格笔记　Tab换工具　数字选人\n"
      .. "（键位可在按键设置里改，以你实际的为准）"
  elseif self.input_profile == "gamepad" then
    legend_text = "确认=笔记　按住=放置　肩键切换工具\n（手柄为兜底方案，推荐用键鼠或触屏）"
  end
  local n = math.max(vm.rows, vm.cols)
  local avail_w = L.board.w - 2 * L.ruler      
  local avail_h = L.board.h - 2 * L.ruler
  local pitch = math.floor(math.min(avail_w, avail_h) / n)
  local gap   = math.max(2, math.floor(pitch * 0.03))
  local cell  = pitch - gap
  local ruler = L.ruler
  local grid_w = n * pitch - gap
  local grid_h = n * pitch - gap
  local gx = L.board.x + ruler + math.floor((avail_w - grid_w) / 2)
  local gy = L.board.y + ruler + math.floor((avail_h - grid_h) / 2)
  if n > 0 then
    local lv_list = {}
    local opt_lv = self.opts.levels
    if type(opt_lv) == "function" then lv_list = opt_lv() or {}
    elseif type(opt_lv) == "table" then lv_list = opt_lv end
    local cur = nil
    local want = tostring(self.opts.current_level or "")
    for i = 1, #lv_list do
      if tostring(lv_list[i].id) == want then cur = lv_list[i] break end
    end
  end    
  local hint_set = nil
  do
    local fci = self.focused_clue
    if fci ~= nil and fci > 0 and self.core ~= nil
       and (self.core.clues == nil or fci > #self.core.clues) then
      pcall(function()
        local _gh = self.core:clue_hint_general(1)
        local _cnt = 0
        if _gh ~= nil and _gh.set ~= nil then for _ in pairs(_gh.set) do _cnt = _cnt + 1 end end
        if _cnt > 0 then hint_set = _gh.set end
      end)
      fci = nil
    end
    if fci == 0 and self.core ~= nil and type(self.core.clue_hint_general) == "function" then
      pcall(function()
        local _g0 = self.core:clue_hint_general(1)    
        if _g0 ~= nil and _g0.set ~= nil and next(_g0.set) ~= nil then hint_set = _g0.set end
      end)
    end
    if fci ~= nil and fci > 0 and self.core ~= nil and self.core.clue_hint ~= nil then
      local h = self.core:clue_hint(fci)
      if h ~= nil and h.set ~= nil and next(h.set) ~= nil then hint_set = h.set end
    end
  end
  for r = 1, vm.rows do
    for c = 1, vm.cols do
      local cd = vm.cells[r][c]
      local _note_val = nil
      local _note_src = nil
      local _resolve = Controller.letter_of
      if _note_val == nil then
        _note_val = mark_list_of((self.core and self.core.notes and self.core.notes[r]
          and self.core.notes[r][c]) or cd.notes, vm, _resolve)
        if _note_val ~= nil then _note_src = "标记(letter)" end
      end
      local _cnt = (cd.suspect ~= nil and 1 or 0) + (_note_val ~= nil and 1 or 0)
      self._note_src_sum = (self._note_src_sum or 0) + _cnt
      if (cd.suspect ~= nil or _note_val ~= nil) and (self._note_src_log or 0) < 12 and print then
        self._note_src_log = (self._note_src_log or 0) + 1
        local _shown = ""
        if type(_note_val) == "table" then _shown = table.concat(_note_val, " ")
        elseif _note_val ~= nil then _shown = tostring(_note_val) end
        if cd.suspect == nil then
          print("[murdoku] ★ 棋盘格下发：cell(" .. tostring(r) .. "," .. tostring(c)
            .. ") 【空格子·标记】note=" .. _shown
            .. "（★ 标记列表 = " .. tostring(_note_src or "无")
            .. " ✓ —— ★ 打的是人 ✓ 显示的是那个人的 `letter` ✓）")
        else
          print("[murdoku] ★ 棋盘格下发：cell(" .. tostring(r) .. "," .. tostring(c)
            .. ") suspect=" .. tostring(cd.suspect)
            .. " src=" .. tostring(_note_src or "无") .. " 值=" .. _shown)
        end
      end
      local style = "cell"
      if cd.state == "blocked" then style = "cell.blocked"
      elseif cd.state == "victim" then style = "cell.victim"
      elseif cd.state == "hint" then style = "cell.hint"
      elseif cd.state == "wrong" then style = "cell.wrong" end
      if cd.x then style = "cell.x" end
      if self.kb_active and self.kb ~= nil and self.kb.r == r and self.kb.c == c then
        style = "cell.cursor"
      end
      push({
        id = self:cell_id(r, c),
        kind = "button",
        parent = "stage",
        rect = { x = gx + (c - 1) * (cell + gap), y = gy + (r - 1) * (cell + gap), w = cell, h = cell },
        style = style,
        visible = (self.screen == nil),
        text = (self.opts.push_cell_text == true and (cd.name or "")) or nil,
        image = cd.suspect and Controller.portrait_of(vm, cd.suspect) or false,
        notes = _note_val or false,
        room = cd.room,
        furn = (function()
          local info = furn_art.cell[r] and furn_art.cell[r][c]
          if info == nil or info.els == nil then return false end
          if M.FURN_BAKED then
            local k = furn_art.kind_of and furn_art.kind_of[r] and furn_art.kind_of[r][c]
            if k ~= "table" and k ~= "shelf" and k ~= "carpet" then return false end
          end
          return info.els
        end)(),
        furn_anchor = (furn_art.cell[r] and furn_art.cell[r][c] and furn_art.cell[r][c].anchor) or false,
        furn_art = (furn_recs and furn_recs[r] and furn_recs[r][c]) or false,
        furn_tpl = (furn_tpl and furn_tpl[r] and furn_tpl[r][c]) or false,
        furn_span = (furn_span and furn_span[r] and furn_span[r][c]) or false,
        furn_offset = (furn_offset and furn_offset[r] and furn_offset[r][c]) or false,
        walls = cd.walls,
        doors = cd.doors,
        tint = Controller.room_color(cd.room),
      hint = (hint_set ~= nil and hint_set[r .. ":" .. c] == true),
        fit = math.floor(cell * M.SCALE + 0.5),
        occupiable = cd.occupiable,
        x_mark = cd.x,
        enabled = true,    
        event = { action = "click", r = r, c = c },
      })
    end
  end
  do
    push({ id = "labels", kind = "container", parent = "root", pos_runtime = true,
           rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height } })
    local in_level = (self.screen == nil or self.screen == "level")
    for i = 1, 7 do
      local lb = (in_level and furn_art.labels) and furn_art.labels[i] or nil
      local node = {
        id = "label." .. i,
        kind = "textbox",
        parent = "labels",
        pos_runtime = true,
        visible = (lb ~= nil),
        text = (lb ~= nil) and lb.text or "",
      }
      local rx, ry, rw, rh = 0, 0, 1, 1
      if lb ~= nil then
        local ac = lb.cell or { r = lb.box.r2, c = lb.box.c1 }
        rw, rh = math.floor(cell * 2.2), math.floor(cell * 0.40)
        rx = math.floor(gx + (ac.c - 1) * pitch + cell * 0.5 - rw * 0.5)
        ry = math.floor(gy + (ac.r - 1) * pitch + cell * 0.5 - rh * 0.5)
      end
      node.rect = { x = rx, y = ry, w = rw, h = rh }
      push(node)
    end
  end
  push({ id = "right", kind = "container", parent = "root", rect = rect_of(L.right), style = "panel.right" })
  local rx = L.right.x + 20
  local modal = self.modal
  if modal then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    push({ id = "modal", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })
    if modal.kind == "result" then
      push({ id = "result.bg", kind = "image", parent = "modal",
             rect = { x = mx, y = my, w = mw, h = mh }, image_id = 100001 })
      local got, total = self.core:score()
      local body = modal.message or ""
      if modal.win then body = body:gsub("^破案！", "") end
      local outcome = modal.outcome or (modal.win and "perfect" or "fail")
      local oi = (outcome == "perfect" and 1) or (outcome == "success" and 2) or 3
      local title_rect = { x = mx + 30, y = my + 40, w = mw - 60, h = 90 }
      push({ id = "modal.title", kind = "text", parent = "modal", rect = title_rect,
             text = " ", style = "modal.title" })
      local TITLES = { "恭喜完美破案", "恭喜成功破案", "破案失败" }
      for i = 1, 3 do
        push({ id = "result.title." .. i, kind = "text", parent = "modal", rect = title_rect,
               visible = (oi == i), text = TITLES[i], style = "modal.title" })
      end
      local win_n, win_idx = 4, nil
      do
        local lv = self.opts.levels
        if type(lv) == "function" then lv = lv() end
        if type(lv) == "table" and #lv > 0 then win_n = #lv end
        local want = tostring(self.opts.current_level or "")
        if type(lv) == "table" then
          for i = 1, #lv do
            if tostring(lv[i].id) == want then win_idx = i break end
          end
        end
      end
      local win_rect = { x = mx + 30, y = my + 140, w = mw - 60, h = 110 }
      push({ id = "win", kind = "container", parent = "modal", rect = win_rect })
      for i = 1, win_n do
        push({ id = "win." .. i, kind = "text", parent = "win", rect = win_rect,
               visible = false,
               text = (win_idx == i) and body or nil,
               style = "modal.body" })
      end
      local MSGS = { [1] = "全部当事人的位置均已摆对，完美通关！", [2] = "盗窃者已被抓获，但仍有位置摆错\n全部摆对，才算完美通关",
                     [3] = "盗窃者没有找对\n看看红圈的位置，再玩一次吧" }
      for i = 1, 3 do
        push({ id = "result.msg." .. i, kind = "text", parent = "modal", rect = win_rect,
               visible = (oi == i), text = MSGS[i], style = "modal.body" })
      end
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 140, w = mw - 60, h = 110 },
             visible = false, style = "modal.body" })
      local result_text = ""
      local result_time = self:format_time(self.result_seconds or vm.hud.time)
      if outcome == "perfect" then
        result_text = "完美 · " .. result_time
      elseif outcome == "success" then
        result_text = string.format("成功 · 误判%d人 · %s", (self._verdict and self._verdict.wrong) or math.max(0, total - got), result_time)
      end
      push({ id = "win.result", kind = "text", parent = "win",
             rect = { x = mx + 30, y = my + 262, w = mw - 60, h = 44 },
             visible = outcome ~= "fail", text = result_text, style = "muted" })
      push({ id = "modal.stats", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 262, w = mw - 60, h = 44 },
             visible = false, text = "", style = "muted" })
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("result.next", "modal", { x = kx, y = my + 350, w = kw, h = kh },
          "下一关", { action = "next_level" }, "stamp.primary")
      btn("result.exit", "modal", { x = kx, y = my + 446, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("result.home", "modal", { x = kx, y = my + 542, w = kw, h = kh },
          "再玩一次", { action = "replay" }, "stamp")
      btn("result.settle", "modal", { x = kx, y = my + 638, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary", self:can_settle())
      if (not self._result_art) and self.adapter ~= nil then
        self._result_art = true
        for _, bid in ipairs({ "result.next", "result.exit", "result.home", "result.settle" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          if bg == nil then pcall(function() bg = self.adapter:find(bid .. ".bg") end) end
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
          end
        end
      end
    elseif modal.kind == "exit_menu" then
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("modal.exit", "modal", { x = kx, y = my + 50, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("modal.save", "modal", { x = kx, y = my + 146, w = kw, h = kh },
          "仅存档", { action = "exit_menu_save" }, "stamp")
      btn("modal.settle", "modal", { x = kx, y = my + 242, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary", self:can_settle())
      local cancel = btn("modal.cancel", "modal", { x = kx, y = my + 338, w = kw, h = kh },
          "取消", { action = "close_modal" }, "tab")
      cancel.settle_shift = (self:settle_seconds_left() > 0) and 30 or 0
      if (not self._exit_menu_art) and self.adapter ~= nil then
        self._exit_menu_art = true
        for _, bid in ipairs({ "modal.exit", "modal.save", "modal.settle", "modal.cancel" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
          end
        end
      end
    elseif modal.kind == "share" then
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 30, w = mw - 60, h = 56 }, text = "分享棋局", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 110, w = mw - 60, h = 200 },
             text = "把这个码发给别人，对方可以还原你的棋盘：\n\n" .. tostring(modal.code), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "关闭",
          { action = "close_modal" }, "tab")
    elseif modal.kind == "levelselect" then
      local list = self.opts.levels or {}
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 24, w = mw - 60, h = 56 },
             text = "选择关卡", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 84, w = mw - 60, h = 34 },
             text = string.format("已登记 %d 关 · 当前：%s", #list, tostring(vm.title or "")),
             style = "muted" })
      local per = 2
      local col_w = math.floor((mw - 100) / per)
      for i = 1, math.min(#list, 8) do
        local it = list[i]
        local col = (i - 1) % per
        local row = math.floor((i - 1) / per)
        local cur = (tostring(it.id) == tostring(self.core.level and self.core.level.id))
        btn("modal.level." .. tostring(it.id), "modal",
            { x = mx + 40 + col * (col_w + 20), y = my + 126 + row * 82, w = col_w, h = 68 },
            string.format("%s%s", cur and "▶ " or "", tostring(it.name or it.id)),
            { action = "pick_level", id = it.id },
            cur and "stamp.primary" or "stamp")
      end
      if #list > 8 then
        push({ id = "modal.body", kind = "text", parent = "modal",
               rect = { x = mx + 30, y = my + 126 + 4 * 82, w = mw - 60, h = 34 },
               text = string.format("（这里只列出前 8 关，共 %d 关）", #list), style = "muted" })
      end
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "关闭",
          { action = "close_modal" }, "tab")
    elseif modal.kind == "howto" then
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 26, w = mw - 60, h = 56 }, text = "玩法", style = "modal.title" })
      local text = {}
      text[#text + 1] = "玩法：把每个角色放到正确的位置上；摆满后点「提交」校验，通过即可指认凶手。"
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 100, w = mw - 60, h = 280 },
             text = table.concat(text, "\n\n"), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "知道了",
          { action = "close_modal" }, "tab")
    end
  end
    local FULL = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }
  push({ id = "home", kind = "container", parent = "root", rect = FULL,
         visible = (self.screen == "home"), pos_runtime = true })
  if self.screen ~= nil then
    if self.screen == "home" then
      push({ id = "home.title", kind = "text", parent = "root", visible = true,
             text = self:toast_text() or M.HOME_TITLE,
             rect = { x = 460, y = 140, w = 1000, h = 110 } })
      local HOME_BTNS = {
        { "home.select",   "选关",         "levelselect", 360 },
        { "home.continue", "从存档点开始", "continue",    480 },
        { "home.shop",     "商城",         "shop",        600 },
        { "home.bag",      "背包",         "bag",         720 },
      }
      for i = 1, #HOME_BTNS do
        local b = HOME_BTNS[i]
        push({ id = b[1], kind = "button", parent = "root", visible = true,
               rect = { x = 730, y = b[4], w = 460, h = 88 },
               text = b[2], event = { action = b[3] } })
      end
    elseif self.screen == "select" then
      push({ id = "select.thumb.pool", kind = "container", parent = "root", visible = true,
             rect = FULL, pos_runtime = true })
        local list = {}
        local lv = self.opts.levels
        if type(lv) == "function" then list = lv() or {}
        elseif type(lv) == "table" then list = lv end
        local PER = 4
        local total = #list
        local pages = math.max(1, math.ceil(total / PER))
        local page = tonumber(self.select_page) or 1
        if page < 1 then page = 1 end
        if page > pages then page = pages end
        self.select_page = page           
        local lst_base = (page - 1) * PER
        push({ id = "select.title", kind = "text", parent = "root", visible = true, text = "选择关卡",
             rect = { x = 460, y = 80, w = 1000, h = 90 } })
      local BACK_RECT = { x = 60, y = 48, w = 62, h = 62 }
      push({ id = "select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT })
      push({ id = "hit.select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT,
             event = { action = "home" } })
        local ARROW = 62
        local PG_Y  = math.floor((1080 - ARROW) / 2)       
        local PR = { x = 60, y = PG_Y, w = ARROW, h = ARROW }
        local NX = { x = 1920 - 60 - ARROW, y = PG_Y, w = ARROW, h = ARROW }
        local NORMAL_TINT, DIM_TINT = 4294967295, 2147483647
        push({ id = "hit.select.prev", kind = "button", parent = "root", visible = true,
               rect = PR, event = { action = "select_page", delta = -1 } })
        push({ id = "hit.select.next", kind = "button", parent = "root", visible = true,
               rect = NX, event = { action = "select_page", delta = 1 } })
        push({ id = "select.page", kind = "text", parent = "root", visible = true,
               text = string.format("第 %d / %d 页", page, pages),
               rect = { x = 895, y = 952, w = 130, h = 70 } })
      local list = {}
      local lv = self.opts.levels
      if type(lv) == "function" then list = lv() or {}
      elseif type(lv) == "table" then list = lv end
        local CARD_W, CARD_H = 279, 388.8
        local CARD_GAP        = 54                          
        local CARD_STEP       = CARD_W + CARD_GAP           
        local CARD_X0         = 250                         
        local CARD_Y0         = 330
        for i = 1, PER do
          local it = list[lst_base + i]
        local r = { x = CARD_X0 + ((i - 1) % PER) * CARD_STEP, y = CARD_Y0,
                    w = CARD_W, h = CARD_H }
        r = self:editor_card_box(ui_adapter, "select.card." .. i, r)
        if it ~= nil then
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, image = CARD_MAT, tint = CARD_TINT })
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, event = { action = "pick_level", id = it.id } })
          local t = self:level_card_parts(it)
          push({ id = "select.card." .. i .. ".title", kind = "text", parent = "root",
                 visible = false, text = "", style = "card.title",
                 rect = { x = r.x + 16, y = r.y + 10, w = r.w - 32, h = 34 },
                 pos_runtime = true })
          -- 710：标题来自当前关卡数据；存档静态文本不能覆盖关卡名。
          push({ id = "select.card." .. i .. ".info", kind = "text", parent = "root",
                 visible = true, text = t.short, style = "card.name",
                 rect = { x = r.x + r.w * 0.045, y = r.y + r.h * 0.835,
                          w = r.w * 0.91, h = r.h * 0.15 },
                 pos_runtime = true })
          push({ id = "select.card." .. i .. ".result", kind = "text", parent = "root",
                 visible = t.result ~= "", text = t.result,
                 rect = { x = r.x, y = r.y + r.h + 10, w = math.max(r.w, 220), h = 72 } })
          self:push_room_thumb(push, "select.card." .. i, it, r, "select.thumb.pool", ui_adapter and ui_adapter.cfg and ui_adapter.cfg.scale)
        else
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          for _, suf in ipairs({ ".title", ".info", ".result" }) do
            push({ id = "select.card." .. i .. suf, kind = "text", parent = "root", visible = false,
                   rect = { x = r.x, y = r.y, w = 1, h = 1 }, pos_runtime = true })
          end
          self:push_room_thumb(push, "select.card." .. i, nil, r, "select.thumb.pool")
        end
      end
    end
    local show_settle = (self.screen == "home" or self.screen == "select")
    push({ id = "settle.btn", kind = "button", parent = "root",
           visible = show_settle,
           rect = { x = 1744.6, y = 298.8, w = 84, h = 84 },
           raycast = show_settle, enabled = self:can_settle(),
           event = { action = "settle_only" } })
    push_settle_countdowns()
    apply_screen_hide(nodes, self.screen)
    return nodes
  end
  push_settle_countdowns()
  apply_screen_hide(nodes, self.screen)
  return nodes
end
function Controller:level_card_parts(it)
  local title = tostring(it.name or it.id)
  local bits = {}
  local sz = it.size
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local total = type(it.suspects) == "table" and #it.suspects or nil
  if rows and cols and total and total >= 2 then
    bits[#bits + 1] = string.format("%dx%d　%d名嫌疑人+1名受害人", cols, rows, total - 1)
  elseif rows and cols then
    bits[#bits + 1] = string.format("%dx%d", cols, rows)
  end
  local p = self.opts.progress and self.opts.progress(it.id) or nil
  local result = ""
  if type(p) == "table" and (p.outcome == "perfect" or p.outcome == "success") then
    local secs = math.max(0, math.floor(tonumber(p.seconds) or 0))
    local time = string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
    if p.outcome == "perfect" then result = "完美\n耗时 " .. time
    else result = string.format("成功 · 误判%d人\n耗时 %s", p.wrong or 0, time) end
  end
  -- UTF-8 的中点必须整体匹配，不能放进按字节匹配的字符集合。
  local short = title
  local first = string.find(title, "·", 1, true)
  if first then
    short = string.sub(title, first + #"·")
    local next_sep = string.find(short, "·", 1, true)
    if next_sep then short = string.sub(short, 1, next_sep - 1) end
    short = string.gsub(short, "^%s+", "")
  end
  short = string.gsub(short, "%s+$", "")
  return { title = title, short = short, info = table.concat(bits, "　"), result = result }
end
Controller.THUMB_POOL = {
  ".boardbg",
  ".cell.1.1",
  ".cell.1.2",
  ".cell.1.3",
  ".cell.1.4",
  ".cell.1.5",
  ".cell.1.6",
  ".cell.1.7",
  ".cell.2.1",
  ".cell.2.2",
  ".cell.2.3",
  ".cell.2.4",
  ".cell.2.5",
  ".cell.2.6",
  ".cell.2.7",
  ".cell.3.1",
  ".cell.3.2",
  ".cell.3.3",
  ".cell.3.4",
  ".cell.3.5",
  ".cell.3.6",
  ".cell.3.7",
  ".cell.4.1",
  ".cell.4.2",
  ".cell.4.3",
  ".cell.4.4",
  ".cell.4.5",
  ".cell.4.6",
  ".cell.4.7",
  ".cell.5.1",
  ".cell.5.2",
  ".cell.5.3",
  ".cell.5.4",
  ".cell.5.5",
  ".cell.5.6",
  ".cell.5.7",
  ".cell.6.1",
  ".cell.6.2",
  ".cell.6.3",
  ".cell.6.4",
  ".cell.6.5",
  ".cell.6.6",
  ".cell.6.7",
  ".cell.7.1",
  ".cell.7.2",
  ".cell.7.3",
  ".cell.7.4",
  ".cell.7.5",
  ".cell.7.6",
  ".cell.7.7",
  ".wall.1",
  ".wall.2",
  ".wall.3",
  ".wall.4",
  ".wall.5",
  ".wall.6",
  ".wall.7",
  ".wall.8",
  ".wall.9",
  ".wall.10",
  ".wall.11",
  ".wall.12",
  ".wall.13",
  ".wall.14",
  ".wall.15",
  ".wall.16",
  ".wall.17",
  ".door.1",
  ".door.2",
  ".door.3",
  ".door.4",
  ".door.5",
}
local ROOM_MAX = 6           
local WHITE_MAT = 100001     -- 703：cell 模板原有的无缺口纯色矩形     
function Controller:editor_card_box(a, id, plan_r)
  if a == nil or type(a.find) ~= "function" then return plan_r end
  local ctrl = nil
  -- 705：select.card.N 是旧点击区域；实际白框由 art647 的 paper 绘制。
  -- 先用可见白框，迟到时暂用旧区域；每次布局重新读取，不缓存回退位置。
  local slot = id:match("^select%.card%.(%d+)$")
  local visual = slot and ("art647.select.card." .. slot .. ".paper") or nil
  if visual then pcall(function() ctrl = a:find(visual) end) end
  local is_visual = ctrl ~= nil
  if ctrl == nil then pcall(function() ctrl = a:find(id) end) end
  if ctrl == nil or ctrl.GetSizeDelta == nil or ctrl.GetAnchoredPosition == nil then return plan_r end
  local w, h, ax, ay = nil, nil, nil, nil
  pcall(function() w, h = ctrl:GetSizeDelta() end)
  pcall(function() ax, ay = ctrl:GetAnchoredPosition() end)
  if print then
    self._ecb_seen = self._ecb_seen or {}
    if not self._ecb_seen[id] then
      self._ecb_seen[id] = true
      local function sh(v)
        if type(v) == "table" then return "表[" .. tostring(v[1]) .. "," .. tostring(v[2]) .. "]"
        elseif type(v) == "number" then return string.format("%.1f", v)
        else return type(v) end
      end
      print("[murdoku] 选关卡框 " .. tostring(id) .. "：w=" .. sh(w) .. " h=" .. sh(h)
        .. " pos=(" .. sh(ax) .. "," .. sh(ay) .. ")")
    end
  end
  local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
  if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return plan_r end
  if not finite(ax) or not finite(ay) then return plan_r end
  if is_visual then
    -- 这些容器使用中心锚点和轴心；按真实父链从内到外合成位置和缩放。
    for _, name in ipairs({ "grp653.static.1.art642.select.frames", "art642.select.frames", "art641.select" }) do
      local parent, x, y, sx, sy = nil, nil, nil, 1, 1
      pcall(function() parent = a:find(name) end)
      if parent == nil then return plan_r end
      pcall(function() x, y = parent:GetAnchoredPosition() end)
      if parent.GetLocalScale then pcall(function() sx, sy = parent:GetLocalScale() end) end
      if not finite(x) or not finite(y) or not finite(sx) or not finite(sy) or sx <= 0 or sy <= 0 then return plan_r end
      ax, ay, w, h = x + ax * sx, y + ay * sy, w * sx, h * sy
    end
  end
  local cfg = a.cfg or {}
  local sc = cfg.scale or (5 / 6)
  local cw = cfg.canvas_w or 1600
  local ch = cfg.canvas_h or 900
  local cx = cw * 0.5 + ax
  local cy = ch * 0.5 + ay
  local dw = w / sc
  local dh = h / sc
  return { x = cx / sc - dw * 0.5, y = (ch - cy) / sc - dh * 0.5, w = dw, h = dh }
end
function Controller:push_room_thumb(push, cardId, it, cardRect, parent, canvas_scale)
  -- 696：选关卡片棕色区域 = 棋盘缩略图（每格房间底色 + 墙 + 门），家具省略。
  -- 关卡名由 build_layout 的 .info 节点放在下方白色边缘。
  local area = { x = cardRect.x + cardRect.w * 0.069,
                 y = cardRect.y + cardRect.h * 0.164,
                 w = cardRect.w * 0.861, h = cardRect.h * 0.783 }
  local sz = it and it.size or nil
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local grid = it and it.room_grid or nil
  local walls = it and it.walls or nil
  local doors = it and it.doors or nil
  -- 旧版 6 个房间大色块全部收起，避免与缩略图叠色
  for j = 1, ROOM_MAX do
    push({ id = cardId .. ".room." .. j, kind = "button", parent = parent,
           visible = false, rect = { x = area.x, y = area.y, w = 1, h = 1 },
           pos_runtime = true })
  end
  local emit, used = push, {}
  push = function(n)
    used[n.id] = true
    n.raycast = false
    emit(n)
  end
  local function hide_unused()
    for _, suffix in ipairs(Controller.THUMB_POOL or {}) do
      local id = cardId .. suffix
      if not used[id] then
        emit({ id = id, kind = "image", parent = parent, visible = false,
          raycast = false, rect = { x = area.x, y = area.y, w = 1, h = 1 }, pos_runtime = true })
      end
    end
  end
  if not rows or not cols or rows < 1 or cols < 1 then hide_unused(); return end
  -- 704：先在最终画布上确定整数格宽与固定格缝，再反算设计坐标。
  -- 卡框本身有小数中心；保留这个共同偏移，不逐格独立取整。
  local sc = tonumber(canvas_scale) or M.SCALE
  if sc ~= sc or sc <= 0 or sc == math.huge then sc = M.SCALE end
  local gap_px = 2
  local count = math.max(rows, cols)
  local target_px = cardRect.w * sc * 0.78
  local cell_px = math.max(1, math.floor((target_px - (count - 1) * gap_px) / count + 0.5))
  local pitch = (cell_px + gap_px) / sc
  local cw, ch = cell_px / sc, cell_px / sc
  local width, height = (cols * cell_px + (cols - 1) * gap_px) / sc,
                        (rows * cell_px + (rows - 1) * gap_px) / sc
  local side = math.max(width, height)
  local rim = math.max(4, math.floor(cardRect.w * sc * 0.022 + 0.5)) / sc
  local center_x, center_y = cardRect.x + cardRect.w * 0.5, cardRect.y + cardRect.h * 0.5
  local gx, gy = center_x - width * 0.5, center_y - height * 0.5
  push({ id = cardId .. ".boardbg", kind = "image", parent = parent,
         visible = true, rect = { x = center_x - side * 0.5 - rim, y = center_y - side * 0.5 - rim,
           w = side + rim * 2, h = side + rim * 2 },
         image = WHITE_MAT, tint = 4281871675, pos_runtime = true })
  -- ① 每格底色（按房间编号取 ROOM_COLORS），不画任何家具
  for r = 1, rows do
    for c = 1, cols do
      local rn = (type(grid) == "table" and type(grid[r]) == "table")
                 and tonumber(grid[r][c]) or nil
      local tint = Controller.room_color(rn) or Controller.ROOM_COLORS[((r + c) % #Controller.ROOM_COLORS) + 1]
      push({ id = cardId .. ".cell." .. r .. "." .. c, kind = "button", parent = parent,
             visible = true,
             rect = { x = gx + (c - 1) * pitch, y = gy + (r - 1) * pitch,
                      w = cw, h = ch },
             image = WHITE_MAT, tint = tint, pos_runtime = true })
    end
  end
  -- ② 墙、门共用格缝中心线。厚度直接以画布像素指定，不再二次舍入。
  local INK  = { r = 32, g = 38, b = 44 }
  local GOLD = { r = 220, g = 91, b = 41 }
  local wall_width, door_width = 5 / sc, 5 / sc
  local door_len = math.max(8, math.floor(cell_px * 0.44 + 0.5)) / sc
  local gap = gap_px / sc
  local function seg(kind, r, c)
    if kind == "v" then
      return gx + c * pitch - gap * 0.5 - wall_width * 0.5,
             gy + (r - 1) * pitch - gap * 0.5, wall_width, pitch
    end
    return gx + (c - 1) * pitch - gap * 0.5,
           gy + r * pitch - gap * 0.5 - wall_width * 0.5, pitch, wall_width
  end
  local function line(suffix, x, y, w, h, tint)
    push({ id = cardId .. suffix, kind = "button", parent = parent, visible = true,
           rect = { x = x, y = y, w = math.max(1, w), h = math.max(1, h) },
           image = WHITE_MAT, tint = tint, pos_runtime = true })
  end
  local k = 0
  for n = 1, (type(walls) == "table" and #walls or 0) do
    local w = walls[n]
    if type(w) == "table" and (w[1] == "v" or w[1] == "h") then
      k = k + 1
      local x, y, ww, hh = seg(w[1], tonumber(w[2]) or 0, tonumber(w[3]) or 0)
      line(".wall." .. k, x, y, ww, hh, INK)
    end
  end
  local d = 0
  for n = 1, (type(doors) == "table" and #doors or 0) do
    local o = doors[n]
    if type(o) == "table" and (o[1] == "v" or o[1] == "h") then
      d = d + 1
      local x, y, ww, hh = seg(o[1], tonumber(o[2]) or 0, tonumber(o[3]) or 0)
      if o[1] == "v" then
        line(".door." .. d, x + (ww - door_width) * 0.5, y + (hh - door_len) * 0.5,
             door_width, door_len, GOLD)
      else
        line(".door." .. d, x + (ww - door_len) * 0.5, y + (hh - door_width) * 0.5,
             door_len, door_width, GOLD)
      end
    end
  end
  hide_unused()
end
function Controller.object_key_of(vm, cd)
  if cd == nil or cd.object == nil or cd.object == false or cd.object == "" then return nil end
  local name = tostring(cd.object)
  local kind = nil
  local list = vm and vm.object_defs
  if type(list) == "table" then
    local def = list[name]
    if type(def) == "table" then kind = def.kind end
  end
  if type(kind) == "string" and kind ~= "" then return "obj." .. kind end
  return "obj." .. name
end
function Controller:layout_plan()
  local saved_modal = self.modal    
  local saved_screen = self.screen
  local vm0 = self.core:view()
  local first_id = vm0.tray[1] and vm0.tray[1].id
  local states = {
    { name = "home",              intro = 99, modal = nil, screen = "home" },
    { name = "select",            intro = 99, modal = nil, screen = "select" },
    { name = "board",             intro = 99, modal = nil, screen = nil },
    { name = "result",            intro = 99,
      modal = { kind = "result", win = true, message = "（结果文案）" }, screen = nil },
    { name = "share",             intro = 99,
      modal = { kind = "share", code = "（分享码）" }, screen = nil },
    { name = "howto",             intro = 99, modal = { kind = "howto" }, screen = nil },
    { name = "levelselect",       intro = 99,
      modal = { kind = "levelselect" }, screen = nil },
    { name = "exit_menu",         intro = 99, modal = { kind = "exit_menu" }, screen = nil },
  }
  local order, byId = {}, {}
  for si = 1, #states do
    local st = states[si]
    self.modal = st.modal
    self.screen = st.screen
    local nodes = self:build_layout()
    for i = 1, #nodes do
      local n = nodes[i]
      local cv = M.to_canvas(n.rect)
      local prev = byId[n.id]
      if prev == nil then
        prev = {
          id = n.id, kind = n.kind, parent = n.parent, style = n.style,
          cx = cv.cx, cy = cv.cy, w = cv.w, h = cv.h,
          text = n.text, visible = (n.visible ~= false),
          states = {},
            image_id = n.image_id, imageColor = n.imageColor, rot = n.rot,
            action = n.event and n.event.action or nil,
            event = n.event,
        }
        byId[n.id] = prev
        order[#order + 1] = prev
      end
      prev.states[#prev.states + 1] = st.name
      if (n.visible ~= false) and prev.visible == false then
        prev.text = n.text
        prev.visible = true
      end
    end
  end
  self.modal, self.screen = saved_modal, saved_screen
  for i = 1, #order do
    local it = order[i]
    local in_board = false
    for k = 1, #it.states do
      if it.states[k] == "board" or it.states[k] == "result"
         or it.states[k] == "share" or it.states[k] == "howto" then in_board = true end
    end
    it.visible = in_board and it.visible
  end
  return order
end
function Controller:placed_count(vm)
  local n = 0
  for i = 1, #vm.tray do if vm.tray[i].placed then n = n + 1 end end
  return n
end
Controller.ROOM_COLORS = {
  { r = 217, g = 205, b = 180 },    
  { r = 195, g = 205, b = 212 },    
  { r = 212, g = 200, b = 188 },    
  { r = 190, g = 207, b = 176 },    
  { r = 224, g = 200, b = 176 },    
  { r = 198, g = 198, b = 210 },    
}
function Controller.room_color(room)
  if type(room) ~= "number" then return nil end
  local t = Controller.ROOM_COLORS
  if type(t) ~= "table" or #t == 0 then return nil end
  return t[((room - 1) % #t) + 1]
end
function Controller._piece_at_row(core, n)
  if core == nil or n == nil then return nil end
  n = tonumber(n)
  if n == nil then return nil end
  local pcs = core.pieces
  if type(pcs) ~= "table" then return nil end
  local c = Controller._piece_id_cache
  if c == nil or c.core ~= core then
    c = { core = core, ids = {} }
    for i = 1, #pcs do
      if pcs[i] ~= nil and pcs[i].id ~= nil then c.ids[i] = tostring(pcs[i].id) end
    end
    Controller._piece_id_cache = c
  end
  return c.ids[n]
end
function Controller._pos_of_piece(core, id)
  if core == nil or id == nil then return nil end
  local want = tostring(id)
  local pcs = core.pieces
  if type(pcs) ~= "table" then return nil end
  local c = Controller._piece_id_cache
  if c == nil or c.core ~= core then
    c = { core = core, ids = {} }
    for i = 1, #pcs do
      if pcs[i] ~= nil and pcs[i].id ~= nil then c.ids[i] = tostring(pcs[i].id) end
    end
    Controller._piece_id_cache = c
  end
  for i = 1, #pcs do
    if c.ids[i] == want then return i end
  end
  return nil
end
function Controller.portrait_of(vm, id)
  local _m = Controller._row_face
  if _m ~= nil then
    local _hit = _m[tostring(id)]
    if _hit ~= nil then return _hit end
    local n = Controller._pos_of_piece(Controller._piece_core, id)
    if n ~= nil then
      local _h2 = _m[n] or _m[tostring(n)]
      if _h2 ~= nil then return _h2 end
    end
  end
  if vm ~= nil and type(vm.tray) == "table" then
    for i = 1, #vm.tray do
      if vm.tray[i].id == id then return vm.tray[i].portrait end
    end
  end
  return nil
end
function Controller.letter_of(vm, id)
  local m = Controller._row_letter
  if m == nil then return nil end
  local hit = m[tostring(id)]
  if hit ~= nil then return hit end
  local n = Controller._pos_of_piece(Controller._piece_core, id)
  if n == nil then return nil end
  return m[n] or m[tostring(n)]
end
local function enum_at(path)
  local cur = Enum
  if cur == nil then return nil end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return nil end
  end
  return cur
end
local function write_control_text(ctrl, txt)
  if ctrl == nil then return false end
  local expected = tostring(txt or "")
  local ok = pcall(function() ctrl.text = expected end)
  if not ok then pcall(function() ctrl:SetText(expected) end) end
  local read_ok, actual = pcall(function() return ctrl.text end)
  return read_ok and actual == expected
end
function Controller:_grid_log(key, msg)
  self._grid_logged = self._grid_logged or {}
  if self._grid_logged[key] then return end
  self._grid_logged[key] = true
  if print then print("[murdoku] " .. tostring(msg)) end
end
function Controller:_dump_row_letter_map(lv_no, n)
  if type(print) ~= "function" then return false end
  if self._row_map_dumped == true then return true end
  local RT = rawget(Controller, "_row_text")
  local by = (type(RT) == "table") and RT[tostring(lv_no)] or nil
  if type(by) ~= "table" then return false end
  local ready = false
  for _, slot in pairs(by) do
    if type(slot) == "table" and slot.letter ~= nil and tostring(slot.letter) ~= "" then ready = true break end
  end
  if not ready then return false end
  self._row_map_dumped = true
  print("[murdoku] ★ 行 → 棋子 → 字母 对照表（★ 关卡 " .. tostring(lv_no)
    .. "；★ 棋盘上每一格显示的就是它那一行的 `letter` ✓）：")
  local nrow = tonumber(n) or 0
  for pos = 1, math.max(nrow, 1) do
    local slot = by[pos]
    local pid = Controller._piece_at_row(self.core, pos)
    print("    ★ 第 " .. tostring(pos) .. " 行  ⇒  棋子=" .. tostring(pid)
      .. "    letter=`" .. tostring(slot and slot.letter) .. "`"
      .. "    who=`" .. tostring(slot and slot.who) .. "`")
  end
  print("[murdoku] ★ 若某行的 `letter` 不是你想让它显示的那个字 ⇒ ★ **去编辑器改那一行** ✓"
    .. "（★ 脚本只照你配的显示 ✓ ★ 它没法知道「你想要哪个」✗）")
  return true
end
function Controller:_grid_fail(why)
  if self._grid_broken then return end
  self._grid_broken = true           
  self._grid_state = nil
  self.dirty = true                  
  self:_grid_log("fail", "网格视窗：失败（" .. tostring(why)
    .. "）⇒ 退回老路径（手写滚动：▲▼ + 滚动条 + clue.N 卡片）")
end
function Controller:sync_clue_grid(adapter)
  if adapter == nil or adapter.find == nil then return end
  self:_reset_row_maps_if_level_changed()
  local cfg = adapter.cfg
  if cfg ~= nil and cfg.use_grid == false then
    if self._grid_state == nil then
      self._grid_state = "off"
      self:_grid_log("off_cfg", "网格视窗：cfg.use_grid=false ⇒ 按配置走老路径（手写滚动）")
    end
    return
  end
  if self.screen == nil and self._grid_last_screen ~= nil then
    self._grid_broken = nil
    self._grid_tries = 0
    self._grid_state = nil
    self._grid = nil
  end
  self._grid_last_screen = self.screen  if self.screen ~= nil then return end
  self:_reset_row_maps_if_level_changed()
  if self._grid_broken then return end
  local grid = self._grid
  if grid == nil then
    if (self._grid_tries or 0) >= 120 then return end
    self._grid_tries = (self._grid_tries or 0) + 1
    pcall(function() grid = adapter:find("clues.grid") end)
    if grid == nil then
      pcall(function() grid = adapter:find("网格视窗") end)
    end
    if grid == nil then
      self:_grid_log("missing", "网格视窗：找不到 `clues.grid`（也试过中文名「网格视窗」，"
        .. "已经试了 " .. tostring(self._grid_tries) .. " 次）⇒ 继续走老路径（手写滚动）")
      if self._grid_tries >= 120 then
        self._grid_state = "off"
        self:_grid_log("missing_final", "网格视窗：试满 120 次仍拿不到控件 ⇒ 判定不可用，"
          .. "`clues.grid` 由脚本按不可见处理，老路径（手写滚动）接管")
      end
      return
    end
    self._grid = grid
  end
  local prefab = cfg and cfg.clues_grid_prefab
  if type(prefab) ~= "number" or prefab <= 0 then
    if not self._grid_no_prefab then
      self._grid_no_prefab = true
      self._grid_state = "off"
      self:_grid_log("noprefab", "网格视窗：cfg.clues_grid_prefab 没有配置 ⇒ 不启用"
        .. "（继续走老路径；模板索引请填在 main.lua）")
    end
    return
  end
  local n = 0
  do
    local core = self.core
    if core ~= nil and type(core.clues) == "table" then
      n = #core.clues + ((type(core.general_clues) == "table" and #core.general_clues > 0) and 1 or 0)    
    else
      local lv = core and core.level
      n = #((lv and lv.clues) or {})
    end
  end
  self._grid_blank_total = n
  local sig = tostring(n)
  if self._grid_refill_pending then
    self._grid_refill_pending = nil
    local _rn = self:_grid_refill_now(adapter, grid)
    if _rn > 0 then
      self._grid_refill_n = (self._grid_refill_n or 0) + 1
    end
  end
  if self._grid_state == "on" and self._grid_sig == sig then return end
  local ok_set, set_err = pcall(function() grid.itemPrefabIndex = prefab end)
  if not ok_set then
    self:_grid_fail("设 itemPrefabIndex 失败：" .. tostring(set_err))
    return
  end
  local back = nil
  pcall(function() back = grid.itemPrefabIndex end)
  self._grid_calls = 0           
  self._grid_in_refresh = true
  local ok_ref, ref_err = pcall(function()
    grid:RefreshItems(n, function(item, index)
      local ok_cb, cb_err = pcall(function() self:_fill_grid_item(adapter, grid, item, index) end)
      if not ok_cb then self._grid_cb_err = tostring(cb_err) end
    end)
  end)
  self._grid_in_refresh = false
  pcall(function() self:_dump_row_letter_map(self:_level_ordinal(), n) end)
  local calls = self._grid_calls or 0
  if (not ok_ref) or (calls == 0 and n > 0) then
    self:_grid_fail("RefreshItems " .. ((not ok_ref) and ("抛错：" .. tostring(ref_err))
      or ("一次回调都没进来（n=" .. tostring(n) .. "）")))
    return
  end
  self._grid_sig = sig
  if not self._tpl_logged and print then
    self._tpl_logged = true
    for _, nm in ipairs({ "clue", "clues.grid", "clues" }) do
      local c = nil
      pcall(function() c = self:_find_by_name(nm) end)
    end
  end
  self._grid_state = "on"
  do
    local cg = grid
    if cg == nil then
      pcall(function() cg = adapter:find("clues.grid") end)
    end
    if cg ~= nil then
      local ok_v, r_v = pcall(function() cg:SetVisible(true) end)
      local ok_a, r_a = pcall(function() cg:SetActive(true) end)
      local back = nil
      pcall(function() back = cg.visible end)
    end
  end
  if adapter ~= nil and adapter.invalidate_lookups ~= nil then
    pcall(function() adapter:invalidate_lookups("grid_refresh:n=" .. tostring(n)) end)
  end
  if self._grid_cb_err ~= nil then
    self:_grid_log("cberr", "网格视窗：列表项填充回调抛过异常（" .. tostring(self._grid_cb_err)
      .. "）—— 已按「这一次没填上」处理；反复出现就把 cfg.use_grid 改回 false")
  end
  self:_grid_log("summary", string.format(
    "网格视窗：找到 clues.grid ✓ itemPrefabIndex=%s（回读 %s） n=%d RefreshItems 回调 %d 次；"
    .. "索引基准=%s；列表项点击=%s；★ 绑定次数=%s",
    tostring(prefab), tostring(back), n, calls,
    (self._grid_base == nil) and "?" or tostring(self._grid_base),
    (self._grid_click_ok == true) and "支持（用 GetItemIndex 反查索引）"
      or "不支持（列表项收不到光标事件 ⇒ 只能用老卡片的点击，聚焦仍可用）",
    tostring(self._grid_bind_n or 0)))
end
function Controller:_grid_item_child(item, index, pos, suffix)
  if item == nil or item.GetChild == nil then return nil, 0 end
  local names = {
    "clue." .. tostring(index) .. "." .. suffix,
    "clue." .. tostring(pos) .. "." .. suffix,
    "clue.1." .. suffix,
    tostring(suffix),
  }
  for i = 1, #names do
    local hit = nil
    pcall(function() hit = item:GetChild(names[i]) end)
    if hit ~= nil then return hit, i end
  end
  return nil, 0
end
function Controller:_grid_item_rec(item, index)
  if item == nil then return nil end
  local cache = self._grid_kids
  if cache == nil then
    cache = setmetatable({}, { __mode = "k" })       
    self._grid_kids = cache
  end
  local rec = cache[item]
  if rec == nil then
    rec = { idx = index, hit = {}, variant = {} }
    cache[item] = rec
  end
  return rec
end
function Controller:_find_image_holder(root)
  if root == nil then return nil end
  local function canImg(c)
    if c == nil then return false end
    local a, b = false, false
    pcall(function() if type(c.SetImage) == "function" then a = true end end)
    pcall(function() if c.imageId ~= nil then b = true end end)
    return a or b
  end
  if canImg(root) then return root end
  local q = { root }
  local seen = 0
  local qi = 1
  while qi <= #q do
    if seen > 60 then break end
    local ks = nil
    pcall(function() ks = q[qi]:GetChildren() end)
    if type(ks) == "table" then
      for ki = 1, #ks do
        local kk = ks[ki]
        seen = seen + 1
        if canImg(kk) then return kk end
        if #q < 200 then q[#q + 1] = kk end
      end
    end
    qi = qi + 1
  end
  return nil
end
function Controller:_read_control_text(root, slot)
  if root == nil then return nil end
  local function ownText(c)
    if c == nil then return nil end
    local t = nil
    pcall(function() t = c.text end)
    if t == nil then return nil end
    t = tostring(t)
    if t == "" then return nil end
    return t
  end
  local t1 = ownText(root)
  if t1 ~= nil then return t1 end
  if type(slot) == "string" and slot ~= "" then
    local sub = nil
    pcall(function() sub = root:FindChild(slot) end)
    local t2 = ownText(sub)
    if t2 ~= nil then return t2 end
  end
  local q = { root }
  local seen = 0
  local qi = 1
  while qi <= #q do
    if seen > 60 then break end
    local ks = nil
    pcall(function() ks = q[qi]:GetChildren() end)
    if type(ks) == "table" then
      for ki = 1, #ks do
        local kk = ks[ki]
        seen = seen + 1
        local t = ownText(kk)
        if t ~= nil then return t end
        if #q < 200 then q[#q + 1] = kk end
      end
    end
    qi = qi + 1
  end
  return nil
end
function Controller:_find_by_name(name)
  if name == nil then return nil end
  local hit = nil
  -- 655: 先复用 adapter 的精确路径/名字索引与缓存，避免另起一趟全树 DFS。
  if self.adapter ~= nil and self.adapter.find ~= nil then
    pcall(function() hit = self.adapter:find(name) end)
    if hit ~= nil then return hit end
  end
  local search = nil
  search = function(x, d)
    if hit ~= nil or x == nil or d > 6 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == name then hit = x return end
    local ks = nil
    pcall(function() ks = x:GetChildren() end)
    if ks ~= nil then
      local n = 0
      pcall(function() n = #ks end)
      for i = 1, n do search(ks[i], d + 1) end
    end
  end
  local roots = nil
  pcall(function() roots = game.GetClientUIRoots() end)
  if roots ~= nil then
    local rn = 0
    pcall(function() rn = #roots end)
    for i = 1, rn do search(roots[i], 0) end
  end
  return hit
end
function Controller:_palette_child(name)
  if name == nil then return nil end
  local fk = self._frame_n
  if type(fk) == "number" and fk > 0 then
    local pc = self._palette_frame
    if pc == nil or pc.clock ~= fk then
      pc = { clock = fk, map = self:_palette_assets_map() }
      self._palette_frame = pc
    end
    if pc.map == nil then return nil end        
    return pc.map[name]
  end
  return self:_palette_child_walk(name)
end
function Controller:_palette_assets_map()
  -- 655: assets 子树为静态，按查找代数缓存；句柄失效（客户端重建）时自动重建。
  local _ad655 = self.adapter
  local _gen655 = _ad655 and (_ad655._lookup_gen or 0) or -1
  local _cache655 = self._palette_assets_cache655
  if _cache655 ~= nil and _cache655.gen == _gen655 then
    local _ok655, _nm655 = pcall(function() return _cache655.assets.name end)
    if _ok655 and _nm655 == "assets" then return _cache655.map end
  end
  local assets = nil
  local search = nil
  search = function(x, d)
    if assets ~= nil or x == nil or d > 4 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == "assets" then assets = x return end
    local ks = nil
    pcall(function() ks = x:GetChildren() end)
    if ks ~= nil then
      local n = 0
      pcall(function() n = #ks end)
      for i = 1, n do search(ks[i], d + 1) end
    end
  end
  local roots = nil
  pcall(function() roots = game.GetClientUIRoots() end)
  if roots ~= nil then
    local rn = 0
    pcall(function() rn = #roots end)
    for i = 1, rn do
      local nm = nil
      pcall(function() nm = roots[i].name end)
      if nm == "root" then
        local direct = nil
        pcall(function() direct = roots[i]:GetChild("assets") end)
        local valid = false
        pcall(function() valid = direct ~= nil and direct.name == "assets" end)
        if valid then assets = direct; break end
      end
    end
    if assets == nil then
      for i = 1, rn do search(roots[i], 0) end
    end
  end
  if assets == nil then
    local r0 = nil
    pcall(function() r0 = self.adapter:find("root") end)
    if r0 ~= nil then search(r0, 0) end
  end
  if assets == nil then return nil end
  local ks = nil
  pcall(function() ks = assets:GetChildren() end)
  if ks == nil then return {} end
  local n = 0
  pcall(function() n = #ks end)
  local map = {}
  for i = 1, n do
    local nm = nil
    pcall(function() nm = tostring(ks[i].name) end)
    if nm ~= nil then map[nm] = ks[i] end
  end
  self._palette_assets_cache655 = { gen = _gen655, assets = assets, map = map }
  return map
end
function Controller:_palette_child_walk(name)
  if name == nil then return nil end
  local assets = nil
  local search = nil
  search = function(x, d)
    if assets ~= nil or x == nil or d > 4 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == "assets" then assets = x return end
    local ks = nil
    pcall(function() ks = x:GetChildren() end)
    if ks ~= nil then
      local n = 0
      pcall(function() n = #ks end)
      for i = 1, n do search(ks[i], d + 1) end
    end
  end
  local roots = nil
  pcall(function() roots = game.GetClientUIRoots() end)
  if roots ~= nil then
    local rn = 0
    pcall(function() rn = #roots end)
    for i = 1, rn do
      local nm = nil
      pcall(function() nm = roots[i].name end)
      if nm == "root" then
        local direct = nil
        pcall(function() direct = roots[i]:GetChild("assets") end)
        local valid = false
        pcall(function() valid = direct ~= nil and direct.name == "assets" end)
        if valid then assets = direct; break end
      end
    end
    if assets == nil then
      for i = 1, rn do search(roots[i], 0) end
    end
  end
  if assets == nil then
    local r0 = nil
    pcall(function() r0 = self.adapter:find("root") end)
    if r0 ~= nil then search(r0, 0) end
  end
  if assets == nil then
    return nil
  end
  local ks = nil
  pcall(function() ks = assets:GetChildren() end)
  if ks == nil then return nil end
  local n = 0
  pcall(function() n = #ks end)
  local seen = {}
  local hit = nil
  for i = 1, n do
    local nm = nil
    pcall(function() nm = tostring(ks[i].name) end)
    if nm ~= nil then
      seen[#seen + 1] = nm
      if nm == name then hit = ks[i] end
    end
  end
  return hit
end
function Controller:_level_ordinal()
  local lv = self.core and self.core.level
  if lv == nil then return nil end
  local id = lv.id
  if id == nil then return nil end
  local ok, n = pcall(function()
    local L = require("levels.init")
    if type(L) ~= "table" then return nil end
    if type(L.index_of) == "function" then return L.index_of(id) end
    if type(L.indexOf) == "function" then return L.indexOf(id) end
    if type(L.list) == "table" then
      for i = 1, #L.list do if L.list[i].id == id then return i end end
    end
    return nil
  end)
  if ok and type(n) == "number" then return n end
  return nil
end
function Controller:_grid_item_child_cached(item, index, pos, suffix)
  local rec = self:_grid_item_rec(item, index)
  if rec == nil then return nil end
  local c = rec.hit[suffix]
  if c ~= nil and (rec.idx == index or (rec.variant[suffix] or 0) >= 3) then
    return c                                        
  end
  local hit, variant = self:_grid_item_child(item, index, pos, suffix)
  rec.idx = index
  rec.hit[suffix] = hit                             
  rec.variant[suffix] = variant
  return hit
end
function Controller:_grid_text_payload()
  local core = self.core
  Controller._piece_core = core
  local lv = core and core.level
  local list = core and core.clues
  local n = #(list or {})
  local p = self._grid_text
  if p ~= nil and p.level == lv and p.n == n then return p end
  local vm = core:view() or {}
  local row_text = nil
  do
    local lvno = self:_level_ordinal()
    if lvno ~= nil then
      local m = rawget(Controller, "_row_text")
      row_text = m and m[tostring(lvno)] or nil
    end
  end
  local items = {}
  for i = 1, #(vm.clues or {}) do
    local cl = vm.clues[i]
    local who, pre, post, wid, wportrait = split_by_name(vm, tostring(cl.text or ""))
    local rt = row_text and row_text[i] or nil
    -- 710修正版：who 是发言人，不能从证词提到的人名反推；what 保留设计卡面。
    local person = lv and lv.suspects and lv.suspects[i]
    local pid = (rt and rt.letter) or (person and person.id)
    if lv and type(lv.suspects) == "table" then
      for _, candidate in ipairs(lv.suspects) do
        if tostring(candidate.id) == tostring(pid) then person = candidate break end
      end
    end
    items[i] = {
      who    = (person and person.name) or (rt and rt.who) or who or "",
      what   = (rt and rt.what) or tostring(cl.text or ""),
      letter = (person and tostring(person.id)) or tostring(pid or ""),
      portrait = (person and person.portrait) or wportrait or (rt and rt.face),
      id     = person and person.id or i,
    }
  end
  p = { level = lv, n = n, items = items }
  self._grid_text = p
  return p
end
function Controller:_grid_visible_count(grid)
  if self._grid_vis_n ~= nil then return self._grid_vis_n end
  if grid == nil then return nil end
  local iw, ih = nil, nil
  local sx, sy = nil, nil
  local pt, pb = nil, nil
  local vh = nil
  pcall(function() iw, ih = grid:GetItemSize() end)
  pcall(function() sx, sy = grid:GetItemSpacing() end)
  pcall(function() pt, pb = grid:GetPadding() end)
  pcall(function() vh = grid.sizeDeltaY end)
  if ih == nil or vh == nil then return nil end
  local per = ih + (sy or 0)
  if per <= 0 or vh <= 0 then return nil end
  local n = 0
  while (pt or 0) + n * per + ih <= vh and n < 512 do n = n + 1 end
  if n < 1 then n = 1 end
  self._grid_vis_n = n
  self._grid_band_h = vh / 2
  self._grid_item_h = ih
  self._grid_vis_why = "项高=" .. tostring(ih) .. " 纵间距=" .. tostring(sy)
    .. " 上边距=" .. tostring(pt) .. " 下边距=" .. tostring(pb)
    .. " 视窗高=" .. tostring(vh)
  return n
end
function Controller:_grid_refill_now(adapter, grid)
  if grid == nil then return 0 end
  local seen = self._grid_seen
  if seen == nil then return 0 end
  local n = 0
  self._grid_in_refresh = false           
  for item, idx in pairs(seen) do
    pcall(function() self:_fill_grid_item(adapter, grid, item, idx) end)
    n = n + 1
  end
  self._grid_in_refresh = false
  return n
end
function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then return true end
  if rec ~= nil then rec.gray_noray = true end
  if cg.raycastTarget ~= nil then pcall(function() cg.raycastTarget = false end) end
  if cg.blockRaycast ~= nil then pcall(function() cg.blockRaycast = false end) end
  if cg.interactable ~= nil then pcall(function() cg.interactable = false end) end
  return true
end
function Controller:_has_general_clue()
  local lv = nil
  pcall(function() lv = self:_level_ordinal() end)
  if lv ~= nil then
    local rc = nil
    pcall(function() rc = self:_palette_child("row." .. tostring(lv) .. ".clue") end)
    if rc ~= nil then return true end
  end
  local ok = false
  pcall(function()
    ok = (self.core ~= nil and type(self.core.general_clues) == "table"
          and #self.core.general_clues > 0)
  end)
  return ok
end
function Controller:_fill_general_item(adapter, item, index, pos)
  self._general_item = item
  do
    local _lv = self:_level_ordinal()
    if _lv ~= nil then
      local _txt = nil
      local _rc = nil
      pcall(function() _rc = self:_palette_child("row." .. tostring(_lv) .. ".clue") end)
      if _rc ~= nil then
        local _src = nil
        pcall(function() _src = _rc:FindChild("clue." .. tostring(_lv) .. ".1") end)
        if _src ~= nil then pcall(function() _txt = _src.text end) end
      end
      if (_txt == nil or _txt == "") and self.core ~= nil then
        pcall(function()
          local rows = self.core:general_clue_results()
          local texts = {}
          for _, row in ipairs(rows or {}) do texts[#texts + 1] = row.text end
          _txt = table.concat(texts, "；")
        end)
      end
      if _txt ~= nil and _txt ~= "" then
        local _dst = nil
        pcall(function() _dst = item:FindChild("gen.body") end)
        if _dst ~= nil then pcall(function() write_control_text(_dst, _txt) end) end
      end
    end
  end
  local function child(nm)
    local c = nil
    pcall(function() c = self:_grid_item_child_cached(item, index, pos, nm) end)
    return c
  end
  for _, nm in ipairs({ "who", "what", "letter", "face" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(false) end) end
  end
  for _, nm in ipairs({ "gen.backrop", "gen.title", "gen.body", "gen691.base", "gen691.hi", "gen691.trap", "gen691.lo", "gen691.mid1", "gen691.mid2", "gen691.corner" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(true) end) end
  end   
  do
    local _cp = nil
    pcall(function() _cp = item:FindChild("gen.backrop") end)
    if _cp ~= nil then
      if self._gen_hl_orig == nil then
        pcall(function() self._gen_hl_orig = _cp.imageColor end)
      end
      local _want = (self.general_focus ~= nil)
      local _target = _want and HIGHLIGHT_TINT or self._gen_hl_orig
      if _target ~= nil then pcall(function() _cp.imageColor = _target end) end
    end
  end
end
function Controller:_fill_grid_item(adapter, grid, item, index)
  self._grid_calls = (self._grid_calls or 0) + 1
  if item == nil then return end
  pcall(function() self:_grid_bind_item_click(adapter, grid, item) end)
  pcall(function() self:_grid_disable_gray_raycast(item, index, nil) end)
  if not self._grid_in_refresh then
    self._grid_scroll_cbs = (self._grid_scroll_cbs or 0) + 1
    self:_grid_log("scroll_cb", "网格视窗：滚动时引擎**会**重进 RefreshItems 回调 ✓（第 "
      .. tostring(self._grid_scroll_cbs) .. " 次）⇒ 列表项内容按 index 现算，滚动不会串内容")
    local hits = self._grid_scroll_cbs
  end
  if self._grid_base == nil then
    local fi = tonumber(index)
    if fi ~= nil then
      self._grid_base = fi
    else
      self._grid_base = 0         
    end
    if print then
      print("[murdoku] 网格视窗：**索引基准定为 " .. tostring(self._grid_base)
        .. "**（第一次回调交来的 index = " .. tostring(index)
        .. "）⇒ 之后 `pos = index − " .. tostring(self._grid_base) .. " + 1`")
    end
  end
  local pos = (tonumber(index) or self._grid_base) - self._grid_base + 1
  local _has_gen = false
  pcall(function() _has_gen = self:_has_general_clue() end)
  if _has_gen then
    if pos == 1 then
      pcall(function() self:_fill_general_item(adapter, item, index, pos) end)
      return
    end
    pos = pos - 1
    if self._general_item == item then self._general_item = nil end    
    for _, _nm in ipairs({ "gen.backrop", "gen.title", "gen.body", "gen691.base", "gen691.hi", "gen691.trap", "gen691.lo", "gen691.mid1", "gen691.mid2", "gen691.corner" }) do
      pcall(function()
        local _cc = self:_grid_item_child_cached(item, index, pos, _nm)
        if _cc ~= nil then pcall(function() _cc:SetVisible(false) end) end
      end)
    end
  end
  self._grid_seen = self._grid_seen or {}
  self._grid_seen[item] = index
  if print and (self._grid_fill_pos_log or 0) < 6 then
    self._grid_fill_pos_log = (self._grid_fill_pos_log or 0) + 1
    print("[murdoku] ★ 填充定位 ✓：引擎交来 index=" .. tostring(index)
      .. "（基准 " .. tostring(self._grid_base) .. "）⇒ 填到 pos=" .. tostring(pos))
  end
  local _row_need = (self._grid_in_refresh == true)
  if not _row_need then
    local m0 = rawget(Controller, "_row_letter")
    _row_need = (type(m0) ~= "table") or (m0[pos] == nil)
  end
  if _row_need then
    local lv_no = self:_level_ordinal()
    if lv_no ~= nil then
      local rc = self:_palette_child("row." .. tostring(lv_no) .. "." .. tostring(pos))
      if rc ~= nil then
        local wrote = 0
        local kids = nil
        pcall(function() kids = rc:GetChildren() end)
        do
          local have = {}
          if type(kids) == "table" then
            for ci = 1, #kids do
              local kn = nil
              pcall(function() kn = tostring(kids[ci].name) end)
              if kn ~= nil then have[kn] = true end
            end
          end
          local want = { "who", "what", "letter", "face" }
          for wi = 1, #want do
            local full = want[wi] .. "." .. tostring(lv_no) .. "." .. tostring(pos)
            if have[full] ~= true then
              local extra = self:_find_by_name(full)
              if extra ~= nil then
                if type(kids) ~= "table" then kids = {} end
                kids[#kids + 1] = extra
                if (self._row_find_log or 0) < 6 and print then
                  self._row_find_log = (self._row_find_log or 0) + 1
                  print("[murdoku] ★ 单射兜底：`" .. full .. "` 不在 #503 里 ✗ ⇒ **按名全树找到** ✓")
                end
              end
            end
          end
        end
        if type(kids) == "table" then
          for ci = 1, #kids do
            local k = kids[ci]
            local kn = nil
            pcall(function() kn = tostring(k.name) end)
            local slot = kn
            if slot ~= nil then slot = string.match(slot, "^[^%.]+") end
            local _rowno = pos
            if slot ~= nil and slot ~= "" then
              local dst = nil
              local full = "clue." .. tostring(pos) .. "." .. tostring(slot)
              pcall(function() dst = item:FindChild(full) end)
              if dst == nil then
                pcall(function() dst = item:FindChild(slot) end)
              end
              if dst == nil then
                dst = self:_grid_item_child_cached(item, index, pos, slot)
              end
              if dst ~= nil then
                local okT, okI = false, false
                pcall(function() local _ = dst.text okT = true end)
                pcall(function() local _ = dst.imageId okI = true end)
                if not okT and not okI then
                  dst = nil
                end
              end
              if dst ~= nil then
                local txt = nil
                pcall(function() txt = k.text end)
                local _slot_txt = self:_read_control_text(k, slot)
                if _slot_txt ~= nil then
                  local _lvn = self:_level_ordinal()
                  if _lvn ~= nil then
                    Controller._row_text = Controller._row_text or {}
                    local _by_lv = Controller._row_text[tostring(_lvn)]
                    if _by_lv == nil then _by_lv = {}; Controller._row_text[tostring(_lvn)] = _by_lv end
                    local _by_pos = _by_lv[pos]
                    if _by_pos == nil then _by_pos = {}; _by_lv[pos] = _by_pos end
                    if _by_pos[slot] == nil then _by_pos[slot] = tostring(_slot_txt) end
                    self._grid_text = nil
                  end
                end
                if slot == "letter" then
                  local _lt = self:_read_control_text(k, slot)
                  if _lt ~= nil then
                    local _pid = _rowno
                    if _pid ~= nil then
                      Controller._row_letter = Controller._row_letter or {}
                      local _old = Controller._row_letter[_pid]
                      if _old ~= nil and tostring(_old) ~= tostring(_lt) then
                        if (self._row_letter_dup or 0) < 6 and print then
                          self._row_letter_dup = (self._row_letter_dup or 0) + 1
                          print("[murdoku] ★ 同一行（`row." .. tostring(lv_no) .. "." .. tostring(pos)
                            .. "`）配了两个不同的 `letter` ✗：已记=`" .. tostring(_old)
                            .. "` 这次=`" .. tostring(_lt) .. "` ⇒ ★ **用这次读到的** ✓"
                            .. "（★ 行号才是键 ✓ 后读到的就是这个槽位的真值 ✓）")
                        end
                      end
                      Controller._row_letter[_pid] = tostring(_lt)
                      if (self._row_letter_log or 0) < 6 and print then
                        self._row_letter_log = (self._row_letter_log or 0) + 1
                        print("[murdoku] ★ 标记来源记下 ✓：`row." .. tostring(lv_no) .. "."
                          .. tostring(pos) .. "` ⇒ who=`" .. tostring(_pid)
                          .. "` letter=`" .. tostring(_lt) .. "`")
                      end
                    end
                  elseif (self._row_letter_miss or 0) < 6 and print then
                    self._row_letter_miss = (self._row_letter_miss or 0) + 1
                    print("[murdoku] ★ `letter` 读不到文字 ✗：`" .. tostring(kn)
                      .. "`（★ 自有 `.text` / `FindChild(" .. tostring(slot)
                      .. ")` / 子孙 三条路都空 ✓ ⇒ 这一段标记会落回旧铅笔笔记 ✓）")
                  end
                end
              if dst ~= nil then
                local _hasT = false
                pcall(function() if dst.text ~= nil then _hasT = true end end)
                if not _hasT then
                  local _q = { dst }
                  local _found = nil
                  for _qi = 1, #_q do
                    local _ks = nil
                    pcall(function() _ks = _q[_qi]:GetChildren() end)
                    if type(_ks) == "table" then
                      for _ki = 1, #_ks do
                        local _kk = _ks[_ki]
                        local _ht = false
                        pcall(function() if _kk.text ~= nil then _ht = true end end)
                        if _ht then _found = _kk break end
                        _q[#_q + 1] = _kk
                      end
                    end
                    if _found ~= nil then break end
                  end
                  if _found ~= nil then
                    dst = _found
                  else
                  end
                end
              end
              if type(txt) == "string" then
                    pcall(function() if dst.text ~= nil then dst.text = txt end end)
                    if type(dst.SetText) == "function" then pcall(function() dst:SetText(txt) end) end
                  wrote = wrote + 1
                end
                local _kimg = self:_find_image_holder(k)
                if _kimg == nil then _kimg = k end
                local iid = nil
                pcall(function() iid = _kimg.imageId end)
                if iid ~= nil then
                  local _key_face = _rowno
                  if _key_face ~= nil then
                    Controller._row_face = Controller._row_face or {}
                    Controller._row_face[_key_face] = iid
                  end
                end
                if iid ~= nil then
                  local src = nil
                  pcall(function() src = k.imageSource end)
                  local _dimg = self:_find_image_holder(dst)
                  if _dimg ~= nil then dst = _dimg end
                  local _okImg = false
                  if src ~= nil then pcall(function() dst:SetImage(src, iid) _okImg = true end) end
                  if not _okImg then pcall(function() dst:SetImage(iid) _okImg = true end) end
                  if not _okImg then
                    pcall(function() if src ~= nil then dst.imageSource = src end end)
                    pcall(function() dst.imageId = iid end)
                  end
                  wrote = wrote + 1
                end
              end
            end
          end
        end
        if (self._row_log or 0) < 6 and print then
          self._row_log = (self._row_log or 0) + 1
          print("[murdoku] ★ 单射命中：`row." .. tostring(lv_no) .. "." .. tostring(pos)
            .. "` ⇒ 写了 " .. tostring(wrote) .. " 个槽位 ✓（★ 内容【由你在编辑器里定】✓）")
        end
        self._row_wrote = self._row_wrote or {}
        if wrote > 0 then self._row_wrote[pos] = true end
      end
    end
  end
  self._grid_idx_seen = self._grid_idx_seen or {}
  if self._grid_idx_seen[pos] == nil then
    self._grid_idx_seen[pos] = 0
    self._grid_idx_n = (self._grid_idx_n or 0) + 1
  end
  self._grid_idx_seen[pos] = self._grid_idx_seen[pos] + 1
  self._grid_cb_total = (self._grid_cb_total or 0) + 1
  local pay = self:_grid_text_payload()
  local cl = pay.items[pos]
  if cl == nil then
    cl = { who = "", what = "", letter = "", id = nil, portrait = nil }
  end
  local t_who, t_what, t_letter = cl.who, cl.what, cl.letter
  local _pid = cl.id
  if type(_pid) == "string" then
    if _pid == "" or #_pid > 2 then _pid = nil end
    if _pid ~= nil and _pid:sub(1, 1) == "@" then _pid = nil end
  end
  if _pid == nil then _pid = cl.who end
  if type(_pid) == "string" then
    if _pid == "" or #_pid > 2 or _pid:sub(1, 1) == "@" then _pid = nil end
  end
  if _pid ~= nil then
    local _as_piece = Controller._piece_at_row(self.core, tonumber(_pid))
    if _as_piece ~= nil then _pid = _as_piece end
    if type(_pid) == "string" and #_pid > 2 then _pid = nil end
  end
  local _placed_now = (_pid ~= nil) and self.core ~= nil and self.core.placed ~= nil
    and self.core.placed[_pid] == true
  local _cgray = self:_grid_item_child_cached(item, index, pos, "gray")
  local _pal = nil
  if _cgray ~= nil then
    local _rg = self:_grid_item_rec(item, index)
    if _rg ~= nil and _rg.gray ~= _placed_now then
      _rg.gray = _placed_now
      if _cgray.SetVisible then pcall(function() _cgray:SetVisible(_placed_now) end) end
      if _cgray.SetActive then pcall(function() _cgray:SetActive(_placed_now) end) end
    end
  end
  local c_who    = self:_grid_item_child_cached(item, index, pos, "who")
  local c_what   = self:_grid_item_child_cached(item, index, pos, "what")
  local c_letter = self:_grid_item_child_cached(item, index, pos, "letter")
  local c_backrop1 = self:_grid_item_child_cached(item, index, pos, "backrop1")
  local rec = self:_grid_item_rec(item, index)
  local tv = rec and rec.text
  if tv == nil or tv.idx ~= index then
    tv = { idx = index }
    if rec ~= nil then rec.text = tv end
  end
  if tv ~= nil then
    local function sync_text(key, ctrl, value)
      if ctrl == nil then tv[key] = nil; return end
      local expected = tostring(value or "")
      local ok, actual = pcall(function() return ctrl.text end)
      -- row.* 复制及列表项复用会覆盖旧值，不能只比较缓存。
      if not ok or actual ~= expected then
        if not write_control_text(ctrl, expected) then tv[key] = nil; return end
      end
      tv[key] = expected
    end
    sync_text("who", c_who, t_who)
    sync_text("what", c_what, t_what)
    sync_text("letter", c_letter, t_letter)
  end
  if c_who == nil or c_what == nil or c_letter == nil then
    self:_grid_log("childmiss", "网格视窗：列表项子控件 who/what/letter = "
      .. ((c_who ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_what ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_letter ~= nil) and "有" or "**缺**")
      .. "（模板 1073742421 里应叫 `clue.1.who` / `clue.1.what` / `clue.1.letter`）")
  end
  self._grid_bind_n = (self._grid_bind_n or 0) + 1
  self:_grid_paint_highlight(item, index, pos, c_backrop1)
end
function Controller:_grid_paint_highlight(item, index, pos, c_backrop1)
  if item == nil then return false end
  local cp = c_backrop1
  if cp == nil then
    pcall(function() cp = self:_grid_item_child_cached(item, index, pos, "backrop1") end)
  end
  if cp == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec == nil then return false end
  local sel = self.core and self.core.selected or nil
  local want = nil
  if sel ~= nil then want = self:_clue_pos_of_person(sel) end
  local want_on = ((want ~= nil) and want == pos)
  if rec.hl_pos == pos and rec.hl_on == want_on then return true end
  if rec.hl_orig == nil or rec.hl_idx ~= index then
    local cur = nil
    pcall(function() cur = cp.imageColor end)
    rec.hl_orig = cur
    rec.hl_idx = index
  end
  local target = want_on and HIGHLIGHT_TINT or rec.hl_orig
  if target ~= nil then pcall(function() cp.imageColor = target end) end
  if print and (self._grid_hl_log or 0) < 6 then
    self._grid_hl_log = (self._grid_hl_log or 0) + 1
    local back = nil
    pcall(function() back = cp.imageColor end)
    local isLeaf = (select(1, pcall(function() local _ = cp.GetChild end)) == true)
    print("[murdoku] ★ 卡片高亮（真机这条）✓ pos=" .. tostring(pos)
      .. " 选中=" .. tostring(sel) .. " ⇒ " .. (want_on and "**亮**" or "灭")
      .. "　写了 " .. tostring(target) .. " 回读=" .. tostring(back)
      .. "　有 GetChild=" .. tostring(isLeaf) .. "　orig=" .. tostring(rec.hl_orig))
  end
  rec.hl_pos, rec.hl_on = pos, want_on
  return true
end
function Controller:_grid_bind_item_click(adapter, grid, item)
  if item == nil or item.AddCursorEventListener == nil then
    return
  end
  if adapter ~= nil and adapter.ensure_raycast ~= nil then
    pcall(function() adapter:ensure_raycast(item) end)
  end
  self._grid_bound = self._grid_bound
    or setmetatable({}, { __mode = "k" })           
  if self._grid_bound[item] then
    self._grid_click_ok = true
    return
  end
  local click = enum_at("CursorEventType.CursorClick")
  if click == nil then return end                   
  local ok = pcall(function()
    item:AddCursorEventListener(click, function()
      pcall(function() self:_on_grid_item_click(adapter, grid, item) end)
    end)
  end)
  if ok then
    self._grid_bound[item] = true
    self._grid_click_ok = true
  end
end
function Controller:_grid_pos_of_item(grid, item)
  if item == nil then return nil end
  local raw = nil
  local seen = self._grid_seen
  if type(seen) == "table" then
    raw = seen[item]
    if raw ~= nil then
      local base = self._grid_base or 0
      local pos = tonumber(raw)
      if pos ~= nil then return pos - base + 1 end
    end
  end
  local idx = nil
  pcall(function() idx = grid:GetItemIndex(item) end)
  if type(idx) == "number" then return idx - (self._grid_base or 0) + 1 end
  return nil
end
function Controller:_on_grid_item_click(adapter, grid, item)
  do
    self._gic_in = (self._gic_in or 0) + 1
    if print and self._gic_in <= 6 then
      local _idx_dbg = nil
      pcall(function() _idx_dbg = grid:GetItemIndex(item) end)
      print("[murdoku] ★ 卡片点击**进来了** ✓（第 " .. tostring(self._gic_in)
        .. " 次）GetItemIndex=" .. tostring(_idx_dbg)
        .. "  索引基准=" .. tostring(self._grid_base))
    end
  end
  do
    local now = nil
    pcall(function() now = os.clock() end)
    if now ~= nil then
      local last = self._grid_click_at
      if last ~= nil and (now - last) < 0.05 then
        self._grid_click_dup = (self._grid_click_dup or 0) + 1
        if (self._grid_click_dup_log or 0) < 3 and print then
          self._grid_click_dup_log = (self._grid_click_dup_log or 0) + 1
          print("[murdoku] ★ 同一次点击的**后续项已忽略** ✓（累计 "
            .. tostring(self._grid_click_dup) .. " 次）"
            .. "　⇒ ★ 来源：**多个列表项叠在同一位置** ⇒ 一次射线命中全部 ✗")
        end
        return
      end
      self._grid_click_at = now
    end
  end
  if item ~= nil and self._general_item == item then
    if self.general_focus ~= nil then
      self.general_focus = nil
      self.focused_clue = nil
      self.general_hint = nil
      self.dirty = true
      self._grid_sig = nil
      return
    end
    local _ncl = 0
    pcall(function() local _v = self.core:view(); _ncl = #_v.clues end)
    self.focused_clue = _ncl + 1
    self.general_focus = true
    pcall(function() self.general_hint = self.core:clue_hint_general(1) end)
    self.dirty = true
    self._grid_sig = nil
    return
  end
  local pos = self:_grid_pos_of_item(grid, item)
  do
    local _hg = false
    pcall(function() _hg = self:_has_general_clue() end)
    if _hg and pos ~= nil then
      pos = pos - 1                 
    end
  end
  if type(pos) ~= "number" then
    self:_grid_log("noindex", "网格视窗：这一项属于哪一条读不到（填充记录与 GetItemIndex 都空）"
      .. " ⇒ 这一次点击忽略（不改焦点）")
    return
  end
  if print and (self._grid_pos_log or 0) < 6 then
    self._grid_pos_log = (self._grid_pos_log or 0) + 1
    local raw = nil
    pcall(function() raw = self._grid_seen and self._grid_seen[item] end)
    print("[murdoku] ★ 点卡片定位 ✓：填充时 index=" .. tostring(raw)
      .. "（基准 " .. tostring(self._grid_base) .. "）⇒ pos=" .. tostring(pos))
  end
  self._grid_refill_pending = true
  local n = #((self.core and self.core.clues) or {})
  if pos < 1 or pos > n then return end
  local _sel_ok, _sel_err = pcall(function()
    local v2 = self.core:view() or {}
    local cl = (v2.clues or {})[pos]
    if print and (self._grid_pick_log or 0) < 6 then
      self._grid_pick_log = (self._grid_pick_log or 0) + 1
      local _dbg_pid = nil
      pcall(function() _dbg_pid = self:_person_id_for_pos(pos) end)
      local _rt, _names_n = nil, 0
      pcall(function()
        local m = rawget(Controller, "_row_text")
        if type(m) == "table" then
          local lvno = self:_level_ordinal()
          local by = (lvno ~= nil) and m[tostring(lvno)] or nil
          local slot = by and by[pos] or nil
          _rt = slot and slot.who or nil
          if _rt == nil then
            for _, v in pairs(m) do
              local s2 = v[pos]
              if s2 ~= nil and s2.who ~= nil then _rt = s2.who break end
            end
          end
        end
        if type(self.core.names) == "table" then
          for _ in pairs(self.core.names) do _names_n = _names_n + 1 end
        end
      end)
      print("[murdoku] ★ 选人这一步：pos=" .. tostring(pos)
        .. "  cl=" .. (cl ~= nil and "有" or "**nil**")
        .. "  解析出的人=" .. tostring(_dbg_pid)
        .. "　★ 读到的 who=「" .. tostring(_rt) .. "」"
        .. "  names 表 " .. tostring(_names_n) .. " 条")
    end
    if cl ~= nil then
      local pid = self:_person_id_for_pos(pos)
      if pid == nil then
        pid = cl.who or cl.person or cl.who_id or cl.id
        if type(pid) == "string" and pid:sub(1, 1) == "@" then pid = nil end
        if pid == nil then
          local pn = cl.portrait or cl.face or cl.asset
          if pn ~= nil then pid = tostring(pn):gsub("^portrait%.", "") end
        end
      end
      if pid ~= nil then
        local is_him = (tostring(self.core.selected or "") == tostring(pid))
        if is_him then
          self.core:select_suspect(pid)
        else
          self.core:select_suspect(pid)
        end
        self._grid_refill_pending = true
        self.dirty = true
      end
    end
  end)
  if (not _sel_ok) and print then
    self._sel_err_log = (self._sel_err_log or 0) + 1
    if self._sel_err_log <= 3 then
      print("[murdoku] ⚠️ 点卡片**选人那一步抛了异常** ⇒ 这一步整段没生效（第 "
        .. tostring(self._sel_err_log) .. " 次，最多报 3 次）：" .. tostring(_sel_err))
    end
  end
local ev = { action = "focus_clue", index = pos, phase = "click" }
  if self._general_click then
    ev = { action = "focus_general", phase = "click" }
    self._general_click = nil             
  end
  pcall(function()
    if item ~= nil and self._general_item == item then
      ev = { action = "focus_general", phase = "click" }
    elseif pos == 1 and self:_has_general_clue() then
      ev = { action = "focus_general", phase = "click" }
    elseif pos == 1 and self.core ~= nil and type(self.core.general_clues) == "table"
       and #self.core.general_clues > 0 then
      ev = { action = "focus_general", phase = "click" }
    end
  end)
  if adapter ~= nil and type(adapter.on_input) == "function" then
    adapter.on_input(ev)
  else
    self:on_input(ev)
  end
end
function Controller:_person_id_for_pos(pos)
  local core = self.core
  if core == nil or pos == nil then return nil end
  local id = Controller._piece_at_row(core, pos)
  if id ~= nil then return id end
  local vm = nil
  pcall(function() vm = core:view() end)
  local cl = (vm and vm.clues or {})[pos]
  if cl ~= nil then
    local pid = cl.who
    if type(pid) == "string" and pid:sub(1, 1) == "@" then pid = nil end
    if pid ~= nil then return tostring(pid) end
  end
  return nil
end
function Controller:_clue_pos_of_person(id)
  if id == nil then return nil end
  local core = self.core
  if core == nil then return nil end
  local pos = Controller._pos_of_piece(core, id)
  if pos == nil then return nil end
  local back = Controller._piece_at_row(core, pos)
  if back == nil or tostring(back) ~= tostring(id) then return nil end
  return pos
end
function Controller:_sync_clue_focus()
  local core = self.core
  local sel = core and core.selected or nil
  local key = (sel == nil) and "\0none" or tostring(sel)
  if rawget(self, "_clue_sel_key") == key then return false end
  self._clue_sel_key = key
  local pos = (sel == nil) and nil or self:_clue_pos_of_person(sel)
  local want = ((pos ~= nil) and pos > 0) and pos or nil
  if rawget(self, "_clue_sel_pos") == want then return false end
  self._clue_sel_pos = want
  local changed = (rawget(self, "focused_clue") ~= want)
  if changed then
    self._grid_focus_item, self._grid_focus_orig = nil, nil
    self._grid_focus_idx, self._grid_focus_pos = nil, nil
    self.focused_clue = want
    self._grid_refill_pending = true
    self.dirty = true
  end
  return changed
end
function Controller:_set_prop(adapter, id, key, value, nkey)
  local ok, res = pcall(function() return adapter:set_property(id, key, value, nkey) end)
  if not ok then
    local k = tostring(id) .. "." .. tostring(key)
    self._prop_err_seen = self._prop_err_seen or {}
    if not self._prop_err_seen[k] then
      self._prop_err_seen[k] = true
      self._prop_err_n = (self._prop_err_n or 0) + 1
      if self._prop_err_n <= 8 then
        self:_grid_log("prop_err:" .. k, "属性下发失败（已跳过这一条，不再每帧刷）：`"
          .. k .. "` ← " .. tostring(res))
      elseif self._prop_err_n == 9 then
        self:_grid_log("prop_err_more", "属性下发失败：已经列了前 8 条，后面的不再逐条打印"
          .. "（同一类【句柄失效】，只影响个别控件，**不会再打断整帧渲染**）")
      end
    end
  end
  return ok and (res ~= false)
end
function Controller:render(adapter, force)
  if adapter ~= nil then self._last_adapter = adapter end    
  local batched = false
  if adapter ~= nil and adapter.begin_furn_batch ~= nil then
    batched = pcall(function() adapter:begin_furn_batch() end)
  end
  local ok, err = pcall(self._render_impl, self, adapter, force)
  if batched then pcall(function() adapter:end_furn_batch() end) end
  if not ok then error(err, 0) end
end
function Controller:_render_impl(adapter, force)
  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter and adapter.clear_board_portraits then adapter:clear_board_portraits() end
      self._props = {}  
      if adapter ~= nil and adapter.invalidate_lookups ~= nil then
        pcall(function()
          adapter:invalidate_lookups("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      if adapter ~= nil and adapter.rearm_raycast ~= nil then
        pcall(function()
          adapter:rearm_raycast("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      if adapter ~= nil and adapter.rearm_cursor ~= nil then
        pcall(function()
          adapter:rearm_cursor("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
    end
  end
  self:sync_clue_grid(adapter)
  local nodes = self:build_layout(adapter)
  local grid_on = (self._grid_state == "on")
  local function stale_legacy(id) return grid_on and is_legacy_clue_id(id) end
  if self.input_profile == nil then
    self.input_profile = "pc"
    if adapter ~= nil and adapter.input_profile ~= nil then
      pcall(function() self.input_profile = adapter:input_profile() end)
    end
  end
  local seen = {}
  for i = 1, #nodes do seen[nodes[i].id] = true end
  local function forget_visible(id)
    if self._props == nil then return end
    local pre = tostring(id) .. "\1"
    for k, rec in pairs(self._props) do
      if type(k) == "string" and k:sub(1, #pre) == pre and type(rec) == "table" then
        rec.visible = nil
      end
    end
  end
  if self._shown == nil then
    local all = self:layout_plan()
    if adapter.prefetch then
      local names = {}
      for i = 1, #all do names[#names+1] = all[i].id end
      adapter:prefetch(names)
    end
    for i = 1, #all do
      if not seen[all[i].id] and not stale_legacy(all[i].id) then
        self:_set_prop(adapter, all[i].id, "visible", false)
        forget_visible(all[i].id)           
      end
    end
    if adapter.hide_unlisted ~= nil then
      adapter:hide_unlisted(seen)
    end
  else
    for id in pairs(self._shown) do
      if not seen[id] and not stale_legacy(id) then
        self:_set_prop(adapter, id, "visible", false)
        forget_visible(id)                
      end
    end
  end
  self._shown = seen           
  local PROP_RETRY = 3
  local function retry_clear(id, key)
    if self._prop_retry ~= nil then
      self._prop_retry[tostring(id) .. "\1" .. tostring(key)] = nil
    end
  end
  local SUB_READY_SECONDS = 2.5    
  local function retry_more(id, key, why, exists)
    local rk = tostring(id) .. "\1" .. tostring(key)
    self._prop_retry = self._prop_retry or {}
    local n_try = (self._prop_retry[rk] or 0) + 1
    self._prop_retry[rk] = n_try
    if n_try == 1 then
      self._prop_retry_t0 = self._prop_retry_t0 or {}
      self._prop_retry_t0[rk] = self.now or 0
    end
    if exists == true and (key == "walls" or key == "doors") then
      local t0 = (self._prop_retry_t0 or {})[rk] or (self.now or 0)
      if (self.now or 0) - t0 < SUB_READY_SECONDS then return true end
    else
      if n_try < PROP_RETRY then return true end
    end
    self._prop_giveup_n = (self._prop_giveup_n or 0) + 1
    if self._prop_giveup_n <= 5 then
      self:_grid_log("prop_giveup:" .. rk,
        "属性补发 " .. n_try .. " 次仍未送达，已停止补发：`"
        .. tostring(id) .. "." .. tostring(key) .. "`（" .. tostring(why) .. "）"
        .. (exists == true and "　★ 注意：**控件是存在的** ✗ —— 这条属于「子控件一直没就绪」"
            or "　（控件本身不存在，属正常）"))
    elseif self._prop_giveup_n == 6 then
      self:_grid_log("prop_giveup_more",
        "属性补发失败：已经列了前 5 条，后面的不再逐条打印"
        .. "（脚本里「本关还没建」的控件本来就有 ~105 个，它们都会走到这里；"
        .. "具体是哪些见上面那句「这些控件还没建」）")
    end
    return false
  end
  local node_seq = {}
  local function node_key(n)
    local base = tostring(n.id) .. "\1" .. tostring(n.parent)
    local seq = (node_seq[base] or 0) + 1
    node_seq[base] = seq
    return base .. "\1" .. tostring(seq)
  end
  local function drop_props_of(id)
    local pre = tostring(id) .. "\1"
    local stale = nil
    for k in pairs(self._props) do
      if type(k) == "string" and k:sub(1, #pre) == pre then
        stale = stale or {}
        stale[#stale + 1] = k
      end
    end
    if stale ~= nil then
      for i = 1, #stale do self._props[stale[i]] = nil end
    end
  end
  for i = 1, #nodes do
    local n = nodes[i]
    local nkey = node_key(n)
    -- 701：选关静态控件会迟到或重建；未找到不能当作已经下发。
    local select_content = n.id == "select.thumb.pool"
      or n.id:match("^select%.card%.%d+%.") ~= nil
      or n.id:match("^hit%.select%.card%.%d+$") ~= nil
    local select_ctrl = nil
    if select_content and type(adapter.find) == "function" then
      pcall(function() select_ctrl = adapter:find(n.id) end)
      self._select_handles = self._select_handles or {}
      if self._select_handles[n.id] ~= select_ctrl then
        drop_props_of(n.id)
        self._created[n.id] = nil
        self._select_handles[n.id] = select_ctrl
      end
    end
    if not self._created[n.id] then
      local ok_c, err_c = pcall(function() adapter:create_control(n) end)
      if not ok_c then
        self:_grid_log("create_err:" .. tostring(n.id), "创建控件失败（已跳过这一条，不再每帧刷）：`"
          .. tostring(n.id) .. "` ← " .. tostring(err_c))
      end
      self._created[n.id] = (not select_content) or select_ctrl ~= nil
      if self._prop_retry ~= nil then
        local pre = tostring(n.id) .. "\1"
        local stale = {}
        for rk in pairs(self._prop_retry) do
          if rk:sub(1, #pre) == pre then stale[#stale + 1] = rk end
        end
        for j = 1, #stale do self._prop_retry[stale[j]] = nil end
      end
    end
    local last = self._props[nkey]
    if last == nil then
      last = {}
      self._props[nkey] = last
    end
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
          local exists = true
          if type(adapter.find) == "function" then
            local e2, r2 = pcall(function() return adapter:find(n.id) end)
            if e2 then exists = (r2 ~= nil) end
          end
          local ok = exists and self:_set_prop(adapter, n.id, k, v, nkey)
          if ok and exists then
            last[k] = v
            retry_clear(n.id, k)
          elseif not exists then
            if not select_content then last[k] = v end
          else
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            if not select_content and retry_more(n.id, k, why, exists) == false then
              last[k] = v           
            end
          end
        end
      end
    end
    local lr = last.__rect
    if force or not lr or lr.x ~= n.rect.x or lr.y ~= n.rect.y or lr.w ~= n.rect.w or lr.h ~= n.rect.h then
      if adapter.instantiated and adapter.instantiated[n.id] then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      elseif n.pos_runtime == true then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      end
      local rect_exists = true
      if type(adapter.find) == "function" then
        local e3, r3 = pcall(function() return adapter:find(n.id) end)
        if e3 then rect_exists = (r3 ~= nil) end
      end
      local rok = rect_exists and self:_set_prop(adapter, n.id, "rect", n.rect, nkey)
      if rok then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
        retry_clear(n.id, "__rect")
      elseif not rect_exists then
        if not select_content then
          last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
        end
      elseif not select_content and retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
      end
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      if stale_legacy(id) then
        self._created[id] = nil
        drop_props_of(id)
      else
        pcall(function() adapter:destroy_control(id) end)
        self._created[id] = nil
        drop_props_of(id)
      end
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    if not stale_legacy(e.target) then
      pcall(function() adapter:play_effect(e.target, e.kind, e) end)
    end
  end
  self.effects = {}
  self.dirty = false
end
return M
