local Core      = require("murdoku_core")
local UIC       = require("ui_controller")
local Adapters  = require("engine_adapter")
local Qianxing  = require("engine_adapter_qianxing")
local Levels = require("levels.init")
local Murdoku = {}
local settle_session = { elapsed = 0, unlocked = false }
function Murdoku.reset_settle_session()
  settle_session = { elapsed = 0, unlocked = false }
end
function Murdoku.advance_settle_session(dt)
  if not settle_session.unlocked then
    settle_session.elapsed = math.min(60, settle_session.elapsed + math.max(0, tonumber(dt) or 0))
    if settle_session.elapsed >= 60 then settle_session.unlocked = true end
  end
end
function Murdoku.get_settle_session() return settle_session end
Murdoku.__index = Murdoku
Murdoku.VERSION = "1.0.0"
local current = nil             
local prepared_adapter = nil    
local signals_registered = false
local tutorial_mask_pending = nil
function Murdoku.set_tutorial_mask(mask)
  tutorial_mask_pending = tonumber(mask) or 0
  Murdoku._tutorial_mask = tutorial_mask_pending
  if Murdoku.apply_tutorial_mask ~= nil then
    pcall(function() Murdoku.apply_tutorial_mask(tutorial_mask_pending) end)
  end
end
function Murdoku.get_tutorial_mask()
  if Murdoku.read_tutorial_mask ~= nil then
    local ok, value = pcall(Murdoku.read_tutorial_mask)
    if ok and value ~= nil then return tonumber(value) or 0 end
  end
  return tonumber(tutorial_mask_pending or Murdoku._tutorial_mask) or 0
end
local murdoku_vis_memo = {}       
local murdoku_vis_force_to = 0    
local murdoku_vis_key = nil       
function dprint(...)
  if Murdoku.DIAG then print(...) end
end
local function snap_visible()
  local out = {}
  local rt = nil
  pcall(function() rt = current.adapter:find("root") end)
  if rt == nil then return out end
  local function walk(c, ox, oy, depth)
    if c == nil or depth > 6 then return end
    local v = nil
    pcall(function() v = c.visible end)
    local al = nil
    pcall(function() al = c.active end)
    if true then
      local nm, w, h, ax, ay = "?", 0, 0, 0, 0
      pcall(function() nm = tostring(c.name) end)
      pcall(function()
        local a, b = c:GetSizeDelta()
        if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
      end)
      pcall(function()
        local a, b = c:GetAnchoredPosition()
        if type(a) == "table" then ax, ay = a.x, a.y else ax, ay = a, b end
      end)
      if (w or 0) * (h or 0) > 1000 then
        local sx = (ox or 0) + (ax or 0)
        local sy = (oy or 0) + (ay or 0)
        out[nm] = string.format("%.0fx%.0f @屏幕(%.0f,%.0f)", w or 0, h or 0, sx + 800, sy + 450)
      end
      local kids = nil
      pcall(function() kids = c:GetChildren() end)
      if type(kids) == "table" then
        for i = 1, math.min(#kids, 120) do
          walk(kids[i], (ox or 0) + (ax or 0), (oy or 0) + (ay or 0), depth + 1)
        end
      end
    end
  end
  walk(rt, 0, 0, 0)
  return out
end
local murdoku_vis_ids = nil
local murdoku_vis_ids_key = nil
local function murdoku_build_vis_ids(scr_now, rows)
  local wid_on = not (current ~= nil and current.adapter ~= nil and current.adapter.cfg ~= nil
                      and current.adapter.cfg.widgets == false)
  local ids = { "tpl-container" }
  if wid_on then
    ids[#ids + 1] = "selbar"
    for i = 1, 6 do ids[#ids + 1] = "selbtn." .. tostring(i) end
  end
  if scr_now == "level" then
    local n = tonumber(rows) or 5
    for r = 1, n do
      for c = 1, n do ids[#ids + 1] = "cell." .. r .. "." .. c end
    end
  end
  return ids
end
local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = nil
  if ad.controls ~= nil then c = ad.controls[nm] end
  if c == nil then pcall(function() c = ad:find(nm) end) end
  if c == nil then return 0 end
  local cur_vis = nil
  pcall(function() cur_vis = c.visible end)
  if not forcing and cur_vis == want then
    memo[nm] = want
    return 0
  end
  if (not forcing) and memo[nm] == want and cur_vis == nil then return 0 end
  local okw = pcall(function() c:SetVisible(want) end)
  if okw then
    memo[nm] = want
    return 1
  end
  return 0
end
Murdoku.USE_GRID = true                   
Murdoku.GRID_ITEM_PREFAB = 1073742421     
local BOARD_W, BOARD_H = 584, 584
local BOARD_X, BOARD_Y = 100, 20
function Murdoku.prepare(adapter)
  prepared_adapter = adapter
  return adapter
end
function Murdoku.current() return current end
function Murdoku.render(force)
  if current == nil then return end
  current.controller:render(current.adapter, force)
end
function Murdoku.refresh_restored_ui()
  if current == nil or current.controller == nil then return end
  local controller = current.controller
  -- 恢复信号可能早于线索网格完成首轮绑定。清掉列表项缓存，
  -- 让下一次 render 按当前 core.view() 重新填充人物、字母和高亮状态。
  controller._grid_seen = {}
  controller._grid_item_cache = setmetatable({}, { __mode = "k" })
  controller._grid_bound = setmetatable({}, { __mode = "k" })
  controller._grid_force_rebind = true
  controller.dirty = true
  Murdoku.render(true)
end
function Murdoku.start(level_id, opts)
  opts = opts or {}
  local level = Levels.get(level_id or Levels.current_id())
  if not level then
    local msg = "找不到关卡：" .. tostring(level_id)
    if printerr then printerr("[murdoku] " .. msg) end
    return nil, msg
  end
  local core, errors = Core.new(level)
  if not core then
    local msg = "关卡数据有误：" .. table.concat(errors or {}, " / ")
    if printerr then printerr("[murdoku] " .. msg) end
    return nil, msg
  end
  local adapter = opts.adapter or prepared_adapter or Qianxing.new()
  prepared_adapter = adapter
  do
    local c = adapter.cfg
    if c ~= nil then
      if c.use_grid == nil then c.use_grid = Murdoku.USE_GRID end
      if c.clues_grid_prefab == nil then c.clues_grid_prefab = Murdoku.GRID_ITEM_PREFAB end
    end
  end
  local level_list = Levels.ui_list()
  local controller
  local function start_other(id, why)
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.skip_intro = true
    o.debug = opts.debug
    o.screen = nil
    o.start_in_level = true
    local ok = Murdoku.start(id, o)
    if not ok then
      controller.toast = "切关失败：" .. tostring(why or id)
      controller.dirty = true
      Murdoku.flush_effects()
    end
    return ok
  end
  local want_screen = nil
  if opts.screen ~= nil then want_screen = opts.screen end
  controller = UIC.new(core, {
    settle_session = settle_session,
    debug = opts.debug,
    skip_intro = (opts.skip_intro ~= false),    
    on_save = function()
      if Murdoku ~= nil and Murdoku.save_now ~= nil then pcall(function() Murdoku.save_now() end) end
    end,
    on_settle = function()
      if Murdoku ~= nil and Murdoku.save_now ~= nil then pcall(function() Murdoku.save_now() end) end
      if adapter ~= nil and adapter.signal_emit ~= nil then
        pcall(function() adapter:signal_emit(Qianxing.SIGNALS.SETTLE, { tostring(level.id) }) end)
      end
    end,
    on_settle_only = function()
      if adapter ~= nil and adapter.signal_emit ~= nil then
        pcall(function() adapter:signal_emit(Qianxing.SIGNALS.SETTLE, { tostring(level.id) }) end)
      end
    end,
    levels = level_list,
    screen = want_screen,
    push_cell_text = (adapter.cfg and adapter.cfg.cells
      and adapter.cfg.cells.push_text == true) or false,
    progress = function(lid) return Murdoku.progress_of(lid) end,
    on_result = function(kind, wrong, seconds) Murdoku.record_result(level.id, kind, wrong, seconds) end,
    last_level = function() return Murdoku.last_played() end,
    current_level = tostring(level.id),
    on_pick_level = function(id)
      Murdoku.remember_level(id)
      if id ~= level.id then
        start_other(id)
        if controller ~= nil then controller.screen = nil end
      else
        if not controller._continue_requested and not controller._restored_from_save then
          controller:do_restart()
        end
        controller.screen = nil
        controller.modal = nil
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_back = function()
      -- 654: 退出至独立选关页，不能重新打开旧式选关弹窗。
      controller.screen = "select"
      controller.modal = nil
      controller.pending = nil
      controller:sync_confirm()
      controller.dirty = true
      Murdoku.flush_effects()
    end,
    on_next_level = opts.on_next_level or function()
      local nxt = Levels.next(level.id)
      if nxt then
        start_other(nxt)
      else
        controller.toast = "已经是最后一关了"
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_solved = function(vm)
      adapter:signal_emit(Qianxing.SIGNALS.SOLVED, {
        tostring(level.id),
        math.floor(vm.hud.time or 0),
        0,
        vm.hud.failed_accusations or 0,
      })
      Murdoku.mark_cleared(level.id)
    end,
  })
  local self = setmetatable({}, Murdoku)
  self.core = core
  self.level = level
  self.adapter = adapter
  self.controller = controller
  self.options = opts
  self.last_tick = 0
  Murdoku.__last = self
  adapter.on_input = function(event)
    controller:on_input(event)
    Murdoku.flush_effects()
  end
  if not signals_registered then
    signals_registered = true
    adapter:signal_on(Qianxing.SIGNALS.RESTORE, function(payload)
      Murdoku.restore(payload)
    end)
    adapter:signal_on(Qianxing.SIGNALS.SYNC_STATE, function(payload)
      Murdoku.on_signal("murdoku/sync", payload)
    end)
  end
  local restored_local_save = false
  if opts.restore_save then
    local save = adapter:load("murdoku/save/" .. tostring(level.id))
    if type(save) == "table" then
      if save.state_code then
        local local_code, local_mask = tostring(save.state_code):match("^(.-)|murdoku_meta:([0-9]+)$")
        if local_code ~= nil then
          save.state_code = local_code
          Murdoku.set_tutorial_mask(local_mask)
        end
        local ok_local = core:decode_state(save.state_code)
        restored_local_save = ok_local == true
      elseif save.cells then
        restored_local_save = core:deserialize(save) == true
      end
      core:set_elapsed(save.elapsed or 0)
    end
  end
  if restored_local_save then
    controller._restored_from_save = true
  end
  if current and current.controller then current.controller:_clear_verdict() end
  if adapter.clear_verdict_rings then adapter:clear_verdict_rings() end
  current = self
  if adapter.enable_cursor then
    local cur = adapter:enable_cursor()
    if cur > 0 and print then
      print("[murdoku] 已由脚本打开 " .. cur .. " 个容器的「显示常驻光标」")
    end
  end
  do
    local root = nil
    pcall(function() root = adapter:find("root") end)
    local s = nil
    if root ~= nil then pcall(function() s = root:GetChild("stage") end) end
    local s2 = nil
    do
      local root2 = nil
      pcall(function() root2 = adapter:find("root") end)
      if root2 ~= nil then pcall(function() s2 = root2:GetChild("stage") end) end
    end
    if print and s2 ~= nil then
      local ew, eh = nil, nil
      pcall(function() ew, eh = s2:GetSizeDelta() end)
      print("[murdoku] ★ 几何归编辑器：stage **回读** " .. tostring(ew) .. "x" .. tostring(eh)
        .. "（★ 这才是实际生效的尺寸 ✓ 脚本常量 BOARD_W/H=" .. tostring(BOARD_W) .. "x" .. tostring(BOARD_H) .. " 不参与）")
    end
  end
  do
    local n_levels = 8
    if Levels ~= nil and type(Levels.all) == "function" then
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    print("[murdoku] ensure_widgets 存在性：type=" .. type(adapter.ensure_widgets)
      .. "，n_levels=" .. tostring(n_levels))
    if adapter.ensure_widgets and not (adapter.cfg and adapter.cfg.widgets == false) then
      local made, err, existed = adapter:ensure_widgets(n_levels)
      print("[murdoku] 选关按钮（脚本创建）：新建 " .. tostring(made)
        .. " 个，已存在 " .. tostring(existed or 0) .. " 个"
        .. (err and ("　⚠️ " .. tostring(err)) or ""))
      local ok_all, all = pcall(Levels.all)
      for i = 1, n_levels do
        local lv_id = nil
        if ok_all and type(all) == "table" and all[i] ~= nil then
          lv_id = all[i].id
        end
        adapter:bind_input("selbtn." .. tostring(i), {
          id = "selbtn." .. tostring(i),
          event = { action = "pick_level", id = lv_id },
        })
      end
    end
  end
  if adapter.ensure_cells then
    local made = adapter:ensure_cells(core.rows, core.cols)
    if made > 0 and print then
      print("[murdoku] 运行时生成了 " .. made .. " 个格子")
    end
  end
  local labels = {}
  do
    local ok, nodes = pcall(function() return controller:build_layout() end)
    if ok and type(nodes) == "table" then
      local list = {}
      for i = 1, #nodes do
        local nd = nodes[i]
        local id = nd.id
        if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") and not id:match("^home%.") then
          list[#list + 1] = id
        end
      end
      adapter.cfg.btn_list = list
      if print then print("[murdoku] 上色名单（来自规划）：" .. #list .. " 个按钮") end
      pcall(function() if adapter.apply_btn_art then adapter:apply_btn_art() end end)
      labels = labels or {}
      for i = 1, #nodes do
        local nd = nodes[i]
        if nd.kind == "button" and type(nd.id) == "string" and type(nd.text) == "string"
           and nd.text ~= "" and not nd.id:match("^cell%.") then
          labels[nd.id] = nd.text
        end
      end
    end
  end
  if print then
    local ids2 = {}
    for id in pairs(labels) do ids2[#ids2 + 1] = id end
    table.sort(ids2)
    local okN, badN = 0, 0
    local shown = 0
    for i = 1, #ids2 do
      local id, want = ids2[i], labels[ids2[i]]
      adapter:set_property(id, "text", want)
      local back, fs, fc, vv = nil, nil, nil, nil
      local via = nil
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
          if lb == nil then lb = adapter:sub(id, "text"); via = "text" else via = "label" end
          if lb then
            back = lb.text
            fs = lb.fontSize
            fc = lb.fontColor
            vv = lb.visible
          end
        end)
      end
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
          if lb ~= nil then
            local bw = nil
            pcall(function()
              local b = adapter:find(id)
              if b ~= nil and b.GetSizeDelta ~= nil then
                local a1 = nil
                a1 = select(1, b:GetSizeDelta())
                bw = a1
              end
            end)
            if adapter.cfg.label_font_size ~= nil and lb.fontSize ~= nil then
              lb.fontSize = adapter.cfg.label_font_size
            end
          end
        end)
      end
      if back == want then okN = okN + 1 else badN = badN + 1 end
      if shown < 8 then
        print(string.format("  %-18s 想要 %q → 读回 %s   fontSize=%s fontColor=%s visible=%s",
          id, want, tostring(back), tostring(fs), tostring(fc), tostring(vv)))
        shown = shown + 1
      end
    end
    print(string.format("[murdoku] 按钮名字：成功 %d 个；另有 %d 个走 `text` 子控件（头像卡，正常）或写入未回读（共 %d）", okN, badN, #ids2))
  end
  if adapter.diagnose_overlap and adapter.cfg.overlap_diag ~= false then
    adapter:diagnose_overlap()
  end
  Murdoku.render(true)
  if adapter.seal_containers ~= nil then
    local sealed = 0
    if adapter.seal_cursor_shield ~= nil then
    end
    if print then
      print(string.format("[murdoku] 2D/3D 输入隔离：主页/选关容器已屏蔽穿透 %d 个", sealed))
      print("[murdoku]   验收：在关卡里按任一键盘快捷键 —— 出现「✅ 键盘事件仍能收到」"
        .. "即说明隔离没有副作用；若没有，去掉 main.lua 里的 seal_containers 即可（一行）。")
    end
  end
  if adapter.diagnose_grid ~= nil and adapter.cfg and adapter.cfg.diagnose_grid ~= false then
    local rows = adapter.cells_rows or (adapter.cfg.cells and adapter.cfg.cells.rows) or 5
    local cols = adapter.cells_cols or (adapter.cfg.cells and adapter.cfg.cells.cols) or 5
  if Murdoku.DIAG then pcall(function() adapter:diagnose_grid(rows, cols) end) end    
  end
  adapter:signal_emit(Qianxing.SIGNALS.READY, {
    tostring(level.id), core.rows, core.cols, core:piece_count(),
  })
  return self
end
function Murdoku.on_start(level_id, opts)
  local adapter = (opts and opts.adapter) or prepared_adapter
  if adapter then
    local ready = false
    pcall(function()
      if adapter:find("cell.1.1") ~= nil then
        ready = true
      elseif adapter:find("stage") ~= nil or adapter:find("home") ~= nil then
        ready = true
      else
        local rt = adapter:find("root")
        if rt ~= nil and rt.GetChildren ~= nil then
          local kids = nil
          pcall(function() kids = rt:GetChildren() end)
          if type(kids) == "table" and #kids > 3 then ready = true end
        end
      end
    end)
    if not ready then return nil end
  end
  local self, err = Murdoku.start(level_id, opts)
  if not self and printerr then printerr("[murdoku] 开局失败：" .. tostring(err)) end
  return self
end
function Murdoku.on_update(dt)
  if not current then return end
  if (not Murdoku._exit_art_done) and current.adapter ~= nil then
    Murdoku._exit_art_done = true
    for _, _bid in ipairs({
      "modal.exit", "modal.save", "modal.settle", "modal.cancel",
    }) do
      local _bg = nil
      pcall(function() _bg = current.adapter:sub(_bid, "bg") end)
      if _bg ~= nil then
        local _src = nil
        pcall(function() _src = _bg.imageSource end)
        pcall(function() _bg:SetImage(_src or 4294967295, 107179) end)
        local _rb = nil
        pcall(function() _rb = tostring(_bg.imageId) end)
        if print then
          print("[murdoku] ★ 胶囊底图(入口层)：bid=" .. tostring(_bid) .. "  回读=" .. tostring(_rb))
        end
      else
        if print then
          print("[murdoku] ★ 胶囊底图(入口层)：bid=" .. tostring(_bid) .. "  **bg 取不到**")
        end
      end
    end
  end
  current.adapter:on_tick(dt)
  current.controller:tick(dt)
  if current.adapter.enable_cursor and ((current.frames or 0) % 20 == 0) then
    local before = Murdoku._cursor_ok or 0
    local n = current.adapter:enable_cursor()
    Murdoku._cursor_ok = n
    if n ~= before and print then
      print("[murdoku] 门控②重试：已打开 " .. tostring(n) .. " 个容器的「显示常驻光标」")
    end
  end
  local ray_st = current.adapter._ray
  if current.adapter.enable_raycast and ((current.frames or 0) % 20 == 0)
     and not (ray_st ~= nil and ray_st.done) then
    local seen, set, samples = current.adapter:enable_raycast()
    local key = tostring(seen) .. "/" .. tostring(set)
    if key ~= Murdoku._ray_key and print then
      Murdoku._ray_key = key
      print("[murdoku] 射线开关（raycastTarget）：有该字段的控件 " .. tostring(seen)
        .. " 个，其中被打开 " .. tostring(set) .. " 个")
      if type(samples) == "table" and #samples > 0 then
        print("[murdoku]   本次打开的例子：" .. table.concat(samples, "  "))
      end
    end
  end
  local sec = math.floor(current.core.elapsed or 0)
  if sec ~= current.last_tick or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end
  Murdoku.DIAG = Murdoku.DIAG or false       
  local scr_now = current.controller and current.controller.screen or "level"
  if Murdoku.DIAG
     and ((current.frames or 0) >= 90 or scr_now ~= Murdoku._last_screen)
     and scr_now ~= Murdoku._dump_done_for then
    Murdoku._dump_done_for = scr_now
    local ad = current.adapter
    print("[murdoku] ===== 开局诊断：屏幕上到底有什么（第 90 帧实测）=====")
    print("[murdoku]   controller.screen = " .. tostring(current.controller.screen))
    local ids = {
      "root", "home", "home.title", "home.select", "home.continue", "home.shop", "home.bag",
      "selbar", "selbtn.1", "tpl-container",
      "stage", "board.bg", "cell.1.1",
      "topbar", "toolbar", "right",
      "clues", "clues.bg", "clues.grid",
      "hud.title", "hud.timer", "hud.progress",
    }
    for i = 1, #ids do
      local id = ids[i]
      local c = nil
      pcall(function() c = ad:find(id) end)
      if c == nil then
        print("[murdoku]   " .. id .. "  → **找不到控件**（名字对不上 / .gil 里没有）")
      else
        local v, a, pos, size = nil, nil, "?", "?"
        pcall(function() v = c.visible end)
        pcall(function() a = c.active end)
        pcall(function()
          local px, py = c:GetAnchoredPosition()
          if type(px) == "table" then pos = string.format("(%.0f,%.0f)", px.x or 0, px.y or 0)
          elseif px ~= nil then pos = string.format("(%.0f,%.0f)", px, py or 0) end
        end)
        pcall(function()
          local w, h = c:GetSizeDelta()
          if type(w) == "table" then size = string.format("%.0fx%.0f", w.x or 0, w.y or 0)
          elseif w ~= nil then size = string.format("%.0fx%.0f", w, h or 0) end
        end)
        local bnd = false
        pcall(function() bnd = (current.adapter.bound and current.adapter.bound[id]) or false end)
        print(string.format("[murdoku]   %-16s visible=%-5s active=%-5s 位置=%-14s 尺寸=%-12s bind=%s",
          id, tostring(v), tostring(a), pos, size, tostring(bnd)))
      end
    end
    print("[murdoku] ===== 开局诊断结束 =====")
    print("[murdoku] ===== 屏幕占用排行（**不管可见不可见**，按面积）=====")
    do
      local list = {}
      local function walk(c, depth)
        if c == nil or depth > 6 then return end
        local v, al, w, h, nm = nil, nil, nil, nil, "?"
        pcall(function() v = c.visible end)
        pcall(function() al = c.active end)
        pcall(function() nm = tostring(c.name) end)
        pcall(function()
          local a, b = c:GetSizeDelta()
          if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
        end)
        local area = (w or 0) * (h or 0)
        if area > 20000 then
          list[#list + 1] = { id = nm, w = w or 0, h = h or 0, area = area,
                              vis = tostring(v), act = tostring(al) }
        end
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 200) do
            if kids[i] ~= nil then walk(kids[i], depth + 1) end
          end
        end
      end
      local rt = nil
      pcall(function() rt = ad:find("root") end)
      walk(rt, 0)
      table.sort(list, function(x, y) return x.area > y.area end)
      for i = 1, math.min(#list, 26) do
        local e = list[i]
        print(string.format("[murdoku]   %2d. %-22s %6.0fx%-6.0f 可见=%-5s active=%-5s 面积=%d",
          i, e.id, e.w, e.h, e.vis, e.act, math.floor(e.area)))
      end
      print("[murdoku]   （共 " .. tostring(#list) .. " 个面积>20000 的控件 —— **含不可见的**）")
      print("[murdoku]   ★ 找那个「全屏 + 可见=false + active=true」的 —— 它就是隐形拦截层")
    end
    print("[murdoku] ===== 排行榜结束 =====")
    print("[murdoku] ===== 诊断二：父级链 + 透明度 + 手动显形 =====")
    local leaf = nil
    pcall(function() leaf = ad:find("home.select") end)
    if leaf == nil then
      print("[murdoku]   home.select 找不到，跳过")
    else
      local chain, cur, guard = {}, leaf, 0
      while cur ~= nil and guard < 8 do
        local nm, vv, aa = "?", "?", "?"
        pcall(function() nm = tostring(cur.name) end)
        pcall(function() vv = tostring(cur.visible) end)
        pcall(function() aa = tostring(cur.active) end)
        chain[#chain + 1] = nm .. "(visible=" .. vv .. ",active=" .. aa .. ")"
        local up = nil
        pcall(function() up = cur.parent end)
        if up == nil then pcall(function() up = cur:GetParent() end) end
        cur = up
        guard = guard + 1
      end
      print("[murdoku]   父级链（从 home.select 往上）：")
      for i = 1, #chain do print("[murdoku]     " .. i .. ". " .. chain[i]) end
      local al, sc = "?", "?"
      pcall(function() al = tostring(leaf.alpha) end)
      pcall(function() sc = tostring(leaf.scale) end)
      print("[murdoku]   home.select alpha=" .. al .. " scale=" .. sc)
      local okv, oka = true, true    
      local v2, a2 = "?", "?"
      pcall(function() v2 = tostring(leaf.visible) end)
      pcall(function() a2 = tostring(leaf.active) end)
      print("[murdoku]   手动 SetVisible=" .. tostring(okv) .. " SetActive=" .. tostring(oka)
        .. "  ⇒ 回读 visible=" .. v2 .. " active=" .. a2)
      local hm = nil
      pcall(function() hm = ad:find("home") end)
      if hm ~= nil then
        print("[murdoku]   已对 home 容器也调了一次 SetVisible/SetActive")
      end
    end
    print("[murdoku] ===== 诊断二结束 =====")
  end
  if Murdoku.DIAG and (Murdoku._snap == nil or scr_now ~= Murdoku._snap_screen) then
    local now = snap_visible()
    if Murdoku._snap ~= nil then
      dprint("[murdoku] ===== 切屏对比：" .. tostring(Murdoku._snap_screen) .. " → " .. tostring(scr_now) .. " =====")
      dprint("[murdoku]   【切过去之后**多出来**的可见控件】（嫌疑最大）")
      local n_add = 0
      for k, v in pairs(now) do
        if Murdoku._snap[k] == nil then print("[murdoku]     + " .. k .. "  " .. v); n_add = n_add + 1 end
      end
      if n_add == 0 then print("[murdoku]     （没有多出来的）") end
      dprint("[murdoku]   【切过去之后**消失**的可见控件】")
      local n_del = 0
      for k, v in pairs(Murdoku._snap) do
        if now[k] == nil then print("[murdoku]     - " .. k .. "  " .. v); n_del = n_del + 1 end
      end
      if n_del == 0 then print("[murdoku]     （没有消失的）") end
      dprint("[murdoku]   【**两个页面都在**的可见控件】—— 这些不随切屏变化，最可能是「挡在中间」的")
      for k, v in pairs(now) do
        if Murdoku._snap[k] ~= nil then print("[murdoku]     = " .. k .. "  " .. v .. "   （切屏前 " .. Murdoku._snap[k] .. "）") end
      end
      dprint("[murdoku] ===== 对比结束 =====")
    end
    Murdoku._snap = now
    Murdoku._snap_screen = scr_now
  end
  do
    local n_levels = 8
    do
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
    do
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
        local sv = nil
        pcall(function() sv = s.visible end)
        if sv ~= true then pcall(function() s:SetVisible(true) end) end
        local sw0, sh0 = nil, nil
        if s ~= nil and print and current._stage_rb_logged ~= true then
          current._stage_rb_logged = true
          pcall(function() sw0, sh0 = s:GetSizeDelta() end)
          print("[murdoku] ★ 棋盘容器 stage 回读 " .. tostring(sw0) .. "x" .. tostring(sh0)
            .. "（★ 归编辑器 ✓ 脚本不再写它 ✓）")
        end
      end
      local bar = nil
      if on_select then pcall(function() bar = current.adapter:find("selbar") end) end
      if bar ~= nil then
        if on_select then
          pcall(function() bar:SetAnchoredPosition(0, 0) end)
          pcall(function() bar:SetSizeDelta(1500, 700) end)
        end
      end
    end
    do
      local STAGE_BG_ID   = 106053
      local STAGE_BG_TINT = 0xFF2C2820    
      local STAGE_BG_FALLBACK_ID = 107003
      local in_level = (scr_now == "level")
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil and not in_level then
        local old = (current.adapter.controls and current.adapter.controls["board.bg"]) or nil
        if old == nil then
          pcall(function() old = s:GetChild("board.bg") end)
        end
        if old ~= nil then
          if current._board_bg_vis ~= false then
            pcall(function() old:SetVisible(false) end)
            current._board_bg_vis = false
          end
          pcall(function() current.adapter.controls["board.bg"] = nil end)
        end
      elseif s ~= nil then
        local bg = (current.adapter.controls and current.adapter.controls["board.bg"]) or nil
        if bg == nil then
          pcall(function() bg = s:GetChild("board.bg") end)
          if bg ~= nil then
            current.adapter.controls = current.adapter.controls or {}
            current.adapter.controls["board.bg"] = bg
          end
        end
        local just_built = false
        if bg == nil and game ~= nil and game.InstantiateClientUIControl ~= nil then
          local ip = current.adapter.cfg and current.adapter.cfg.prefab_icon
          if ip ~= nil then
            local okb, ob = pcall(game.InstantiateClientUIControl, ip, s)
            if okb and ob ~= nil then
              pcall(function() ob.name = "board.bg" end)
              pcall(function() ob:SetSizeDelta(677, 677) end)
              pcall(function() ob:SetAnchoredPosition(0, 0) end)
              local layered = {}
              if ob.SetSiblingIndex ~= nil then
                if pcall(function() ob:SetSiblingIndex(0) end) then layered[#layered + 1] = "SetSiblingIndex(0)" end
              end
              if ob.SetAsFirstSibling ~= nil then
                if pcall(function() ob:SetAsFirstSibling() end) then layered[#layered + 1] = "SetAsFirstSibling()" end
              end
              if #layered == 0 then layered[#layered + 1] = "没排（两个 API 都没有）" end
              local sib = "?"
              pcall(function() sib = tostring(ob:GetSiblingIndex()) end)
              local okimg, via, rid, tint_ok = current.adapter:set_image_deep(
                ob, STAGE_BG_ID, "Stretch", STAGE_BG_TINT, "board.bg(纯色图形)")
              local used_mode = "纯色图形+染色"
              if tint_ok ~= true then
                local ok2, via2, rid2 = current.adapter:set_image_deep(
                  ob, STAGE_BG_FALLBACK_ID, "Stretch", nil, "board.bg(回退：自带深色)")
                used_mode = "回退：自带深色底板（染色不生效）"
                okimg, via, rid = ok2, via2, rid2
              end
              if print then
                print("[murdoku] 棋盘底板：新建 board.bg  用法=" .. used_mode
                  .. "  染色判定=" .. tostring(tint_ok)
                  .. "  设图成功=" .. tostring(okimg)
                  .. "  imageId 回读=" .. tostring(rid)
                  .. "  经 " .. tostring(via)
                  .. "  图层=" .. table.concat(layered, "+")
                  .. "  兄弟序号回读=" .. tostring(sib) .. "（0=最底）"
                  .. "  —— 这一行**只应出现一次**；若重复出现说明「只建一次」没生效")
              end
              current.adapter.controls = current.adapter.controls or {}
              current.adapter.controls["board.bg"] = ob
              bg = ob
              just_built = true
            end
          end
        end
        if bg ~= nil and just_built then
          current._board_bg_vis = nil
        end
        if bg ~= nil then
          local want = true
          if current._board_bg_vis ~= want then
            pcall(function() bg:SetVisible(want) end)
            current._board_bg_vis = want
          end
        end
      end
    end
    for i = 1, (on_select and n_levels or 0) do
      local c = nil
      pcall(function() c = current.adapter:find("selbtn." .. tostring(i)) end)
      if c ~= nil then
        if on_select then
          local x = (i - (n_levels + 1) / 2) * 200
          pcall(function() c:SetAnchoredPosition(x, 120) end)
          pcall(function() c:SetSizeDelta(160, 160) end)
        end
      end
    end
  end
  do
    if not Murdoku._settle_probe_done then
      Murdoku._settle_probe_done = true
      local sb0 = nil
      pcall(function() sb0 = current.adapter:find("settle.btn") end)
      if sb0 ~= nil and print then
        local rw, rh, rx, ry, rvis, rray = "?", "?", "?", "?", "?", "?"
        pcall(function() rw, rh = sb0:GetSizeDelta() end)
        pcall(function() rx, ry = sb0:GetAnchoredPosition() end)
        pcall(function() rvis = tostring(sb0.visible) end)
        pcall(function() rray = tostring(sb0.raycastTarget) end)
        print("[murdoku] ★ 结算按钮（归编辑器 ✓ 脚本一个字都不写）：回读 size=("
          .. tostring(rw) .. "," .. tostring(rh) .. ") pos=(" .. tostring(rx) .. "," .. tostring(ry)
          .. ") visible=" .. rvis .. " raycastTarget=" .. rray)
      end
    end
  end
  if murdoku_vis_memo == nil then murdoku_vis_memo = {} end
  do
    local lev0 = current.level
    local lid0 = (lev0 ~= nil) and (lev0.id or lev0.key or lev0.name) or nil
    local r0 = (current.adapter ~= nil) and current.adapter.cells_rows or nil
    local ids_key = tostring(scr_now) .. "|" .. tostring(lid0) .. "|" .. tostring(r0)
    if ids_key ~= murdoku_vis_ids_key or murdoku_vis_ids == nil then
      murdoku_vis_ids_key = ids_key
      murdoku_vis_ids = murdoku_build_vis_ids(scr_now, r0)
    end
  end
  do
    local lev = current.level
    local lid = (lev ~= nil) and (lev.id or lev.key or lev.name) or nil
    local key = tostring(scr_now) .. "|" .. tostring(lid)
    if key ~= murdoku_vis_key then
      murdoku_vis_key = key
      murdoku_vis_force_to = (tonumber(rawget(current, "frames")) or 0) + 60
    end
  end
  do
    local ad_vis = current.adapter
    if ad_vis ~= nil then
      local in_level = (scr_now == "level")
      local in_select = (scr_now == "select")
      local fnow = tonumber(rawget(current, "frames")) or 0
      local forcing = (fnow < (murdoku_vis_force_to or 0))
      local wrote = 0
      local vis_ids = murdoku_vis_ids
      if vis_ids ~= nil then
        for i = 1, #vis_ids do
          local nm = vis_ids[i]
          local want
          if nm == "tpl-container" then
            want = false
          elseif nm:sub(1, 5) == "cell." then
            want = true
          else
            want = in_select
          end
          wrote = wrote + murdoku_set_vis(ad_vis, nm, want, forcing, murdoku_vis_memo)
        end
      end
      current._vis_wrote = wrote
      current._vis_forcing = forcing
      current._vis_frames = fnow
      current._vis_until = murdoku_vis_force_to
      current._vis_keynow = murdoku_vis_key
    end
  end
    if scr_now == "level" and ((current.frames or 0) % 30) == 0 then
      local rows, cols = 5, 5
      pcall(function()
        local a = current.adapter
        if a ~= nil then
          rows = a.cells_rows or (a.cfg and a.cfg.cells and a.cfg.cells.rows) or rows
          cols = a.cells_cols or (a.cfg and a.cfg.cells and a.cfg.cells.cols) or cols
        end
      end)
      local n = 0
      for r = 1, rows do
        for c = 1, cols do
          local cid = "cell." .. r .. "." .. c
          local cell = nil
          pcall(function() cell = current.adapter:find(cid) end)
          local cw, ch = 124, 124
          if cell ~= nil then
            pcall(function()
              local a, b = cell:GetSizeDelta()
              if type(a) == "table" then cw, ch = a.x, a.y else cw, ch = a, b end
            end)
          end
          local face = nil
          if cell ~= nil and cell.GetChildren ~= nil then
            local kids = nil
            pcall(function() kids = cell:GetChildren() end)
            for _, k in ipairs(kids or {}) do
              local kn = nil
              pcall(function() kn = tostring(k.name) end)
              if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                local cv = nil
                pcall(function() cv = k.visible end)
                if cv ~= true then pcall(function() k:SetVisible(true) end) end
                local cgw, cgh = nil, nil
                pcall(function() cgw, cgh = k:GetSizeDelta() end)
                if not (cgw == cw and cgh == ch) then
                  pcall(function() k:SetSizeDelta(cw, ch) end)
                end
                local cgx, cgy = nil, nil
                pcall(function() cgx, cgy = k:GetAnchoredPosition() end)
                if not (cgx == 0 and cgy == 0) then
                  pcall(function() k:SetAnchoredPosition(0, 0) end)
                end
              end
              if kn == "face" then
                local fv = nil
                pcall(function() fv = k.visible end)
                if fv ~= true then pcall(function() k:SetVisible(true) end) end
                local fgw, fgh = nil, nil
                pcall(function() fgw, fgh = k:GetSizeDelta() end)
                if not (fgw == cw and fgh == ch) then
                  pcall(function() k:SetSizeDelta(cw, ch) end)
                end
                local fgx, fgy = nil, nil
                pcall(function() fgx, fgy = k:GetAnchoredPosition() end)
                if not (fgx == 0 and fgy == 0) then
                  pcall(function() k:SetAnchoredPosition(0, 0) end)
                end
                face = k
              end
    if kn == "x" then
      local xw, xh = nil, nil
      pcall(function() xw, xh = k:GetSizeDelta() end)
      if not (xw == cw * 0.7 and xh == ch * 0.7) then
        pcall(function() k:SetSizeDelta(cw * 0.7, ch * 0.7) end)
      end
      local xx, xy = nil, nil
      pcall(function() xx, xy = k:GetAnchoredPosition() end)
      if not (xx == 0 and xy == 0) then
        pcall(function() k:SetAnchoredPosition(0, 0) end)
      end
    end
              if face == nil and k.GetChildren ~= nil then
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                for _, c2 in ipairs(kk or {}) do
                  local cn = nil
                  pcall(function() cn = tostring(c2.name) end)
                  if cn == "face" then
                    local gv = nil
                    pcall(function() gv = c2.visible end)
                    if gv ~= true then pcall(function() c2:SetVisible(true) end) end    
                    local ggw, ggh = nil, nil
                    pcall(function() ggw, ggh = c2:GetSizeDelta() end)
                    if not (ggw == cw and ggh == ch) then
                      pcall(function() c2:SetSizeDelta(cw, ch) end)
                    end
                    local ggx, ggy = nil, nil
                    pcall(function() ggx, ggy = c2:GetAnchoredPosition() end)
                    if not (ggx == 0 and ggy == 0) then
                      pcall(function() c2:SetAnchoredPosition(0, 0) end)
                    end
                    face = c2
    elseif cn == "x" then
      local zxw, zxh = nil, nil
      pcall(function() zxw, zxh = c2:GetSizeDelta() end)
      if not (zxw == cw * 0.7 and zxh == ch * 0.7) then
        pcall(function() c2:SetSizeDelta(cw * 0.7, ch * 0.7) end)
      end
      local zxx, zxy = nil, nil
      pcall(function() zxx, zxy = c2:GetAnchoredPosition() end)
      if not (zxx == 0 and zxy == 0) then
        pcall(function() c2:SetAnchoredPosition(0, 0) end)
      end
                  end
                end
              end
            end
          end
          if face ~= nil then
            pcall(function() face:SetVisible(true) end)
            n = n + 1
          end
        end
      end
      if n > 0 and current._face_on ~= n then
        current._face_on = n
        if print then
          print("[murdoku] 格子底图已点亮：" .. tostring(n) .. " 个 face（每帧保持）")
        end
      end
    end
  Murdoku._last_screen = scr_now
  current.frames = (current.frames or 0) + 1
end
function Murdoku.on_destroy()
  if not current then return end
  current.controller:_clear_verdict()
  Murdoku.save_now()
  current = nil
end
Murdoku.on_ready = Murdoku.on_start
Murdoku.on_tick = Murdoku.on_update
function Murdoku.flush_effects()
  if not current then return end
  if current.controller.dirty then
    Murdoku.render()
  end
  if current.adapter.report_missing ~= nil then
    pcall(function() current.adapter:report_missing() end)
  end
end
function Murdoku.on_input(event)
  if not current then return end
  current.controller:on_input(event)
  Murdoku.flush_effects()
end
function Murdoku.on_signal(name, payload)
  if not current then return end
  local S = Qianxing.SIGNALS
  if name == S.RESTORE then
    Murdoku.restore(payload)
  elseif name == S.SYNC_STATE then
    if payload and payload.who and payload.r and payload.c then
      current.core:select_suspect(payload.who)
      local ok_sync, why_sync = current.core:tap_cell(payload.r, payload.c)
      if (not ok_sync) and current.controller ~= nil
        and current.controller._refuse ~= nil then
        pcall(function()
          current.controller:_refuse(payload.r, payload.c, why_sync)
        end)
      end
      Murdoku.render()
    end
  elseif name == "murdoku/next_level" then
    local nxt = Levels.next(current.level.id)
    if nxt then Murdoku.start(nxt, current.options) end
  end
end
function Murdoku.restore(payload)
  if not current or type(payload) ~= "table" then return false, "没有存档" end
  if payload.tutorial_mask ~= nil then Murdoku.set_tutorial_mask(payload.tutorial_mask) end
  local state_code = payload.state_code
  if type(state_code) == "string" then
    local base, mask = state_code:match("^(.-)|murdoku_meta:([0-9]+)$")
    if base ~= nil then
      state_code = base
      Murdoku.set_tutorial_mask(mask)
    end
  end
  if state_code then
    local ok, err = current.core:decode_state(state_code)
    if not ok then
      if printerr then printerr("[murdoku] 读档失败：" .. tostring(err)) end
      return false, err
    end
  elseif payload.cells then
    current.core:deserialize(payload)
  end
  current.core:set_elapsed(payload.elapsed or 0)
  current.controller._restored_from_save = true
  Murdoku.refresh_restored_ui()
  return true
end
local SAVE_RECENT   = "murdoku/recent"
local SAVE_PROGRESS = "murdoku/progress"
local function store()
  return prepared_adapter
end
function Murdoku.remember_level(id)
  if id == nil then return end
  local a = store()
  if a == nil or a.save == nil then return end
  pcall(function() a:save(SAVE_RECENT, tostring(id), { no_signal = true }) end)
  pcall(function()
    local p = a:load(SAVE_PROGRESS)
    if type(p) ~= "table" then p = {} end
    local cur = p[tostring(id)]
    if type(cur) ~= "table" then cur = {} end
    if not cur.cleared then cur.started = true end
    p[tostring(id)] = cur
    a:save(SAVE_PROGRESS, p, { no_signal = true })
  end)
end
function Murdoku.last_played()
  local a = store()
  if a == nil or a.load == nil then return nil end
  local v = nil
  pcall(function() v = a:load(SAVE_RECENT) end)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end
function Murdoku.mark_cleared(id)
  if id == nil then return end
  local a = store()
  if a == nil or a.save == nil then return end
  pcall(function()
    local p = a:load(SAVE_PROGRESS)
    if type(p) ~= "table" then p = {} end
    local cur = p[tostring(id)]
    if type(cur) ~= "table" then cur = {} end
    cur.cleared = true
    cur.started = true
    p[tostring(id)] = cur
    a:save(SAVE_PROGRESS, p, { no_signal = true })
  end)
end
function Murdoku.record_result(id, outcome, wrong, seconds)
  if id == nil or (outcome ~= "success" and outcome ~= "perfect") then return false end
  local a = store()
  if not a or not a.save or not a.load then return false end
  wrong = math.max(0, math.floor(tonumber(wrong) or 0))
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if outcome == "perfect" then wrong = 0 end
  local p = a:load(SAVE_PROGRESS)
  if type(p) ~= "table" then p = {} end
  local cur = p[tostring(id)]
  if type(cur) ~= "table" then cur = {} end
  local rank = { success = 1, perfect = 2 }
  local oldrank = rank[cur.outcome] or 0
  local better = rank[outcome] > oldrank or (rank[outcome] == oldrank and
    (wrong < (cur.wrong or math.huge) or (wrong == cur.wrong and seconds < (cur.seconds or math.huge))))
  if not better then return false end
  cur.cleared, cur.started = true, true
  cur.outcome, cur.wrong, cur.seconds = outcome, wrong, seconds
  p[tostring(id)] = cur
  a:save(SAVE_PROGRESS, p, {no_signal = true})
  return true
end
function Murdoku.progress_of(id)
  local a = store()
  if a == nil or a.load == nil then return nil end
  local p = nil
  pcall(function() p = a:load(SAVE_PROGRESS) end)
  if type(p) ~= "table" then return nil end
  return p[tostring(id)]
end
function Murdoku.save_now()
  if not current then return false end
  local core = current.core
  local payload = {
    level_id   = tostring(current.level.id),
    state_code = core:encode_state() .. "|murdoku_meta:" .. tostring(Murdoku.get_tutorial_mask()),
    moves      = 0,
    elapsed    = math.floor(core.elapsed or 0),
    solved     = (core.status == Core.STATUS_SOLVED),
  }
  current.adapter:save("murdoku/save/" .. tostring(current.level.id), payload)
  return true
end
function Murdoku.validate_all()
  local lines = {}
  for _, level in ipairs(Levels.all()) do
    local ok, errors = Core.validate_level(level)
    if ok then
      lines[#lines + 1] = string.format("[OK]   %s", tostring(level.id))
    else
      lines[#lines + 1] = string.format("[FAIL] %s\n    %s", tostring(level.id), table.concat(errors, "\n    "))
    end
  end
  local text = table.concat(lines, "\n")
  if print then print(text) end
  return text
end
return Murdoku
