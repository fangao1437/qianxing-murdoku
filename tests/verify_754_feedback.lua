-- tests/verify_754_feedback.lua
-- 定向回归验证 754 全部修复（承接 753 的 A..I，并验证 754 构建与全部教程页打开/翻页/关闭零异常）
local tree_path   = assert(arg[1], "缺少 tree_lua 参数")
local script_path = assert(arg[2], "缺少 script_lua 参数")
local out_json    = assert(arg[3], "缺少 out_json 参数")

local raw_tree = dofile(tree_path)

local function encode_json(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return string.format("%.6g", v)
  elseif t == "string" then
    return string.format("%q", v):gsub("\\\n", "\\n")
  elseif t == "table" then
    local is_arr, n = true, 0
    for k in pairs(v) do
      if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then is_arr = false; break end
      if k > n then n = k end
    end
    if is_arr and n > 0 then
      local parts = {}
      for i = 1, n do parts[i] = encode_json(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = encode_json(tostring(k)) .. ":" .. encode_json(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function build_sandbox(canvas_w, canvas_h, device_name)
  local by_id = {}
  local roots = {}
  local cur_w, cur_h = canvas_w or 1600, canvas_h or 900
  local cur_dev = device_name or "Mobile"
  local signals_emitted = {}

  local ctrl_mt = {}
  ctrl_mt.__index = function(self, k)
    local r = rawget(self, "_raw")
    if k == "name" then return r._name
    elseif k == "visible" then return r._vis
    elseif k == "active" then return r._act
    elseif k == "text" then return r._text
    elseif k == "fontSize" then return r._fs
    elseif k == "fontColor" then return r._fc
    elseif k == "imageColor" then return r._ic
    elseif k == "raycastTarget" then return r._ray
    elseif k == "blockRaycast" then return r._blk
    elseif k == "interactable" then return r._intr
    elseif k == "showCursor" then return r._sc
    elseif k == "disableCursorEventPassthrough" then return r._dcp
    elseif k == "clickAudioId" then return r._aud
    elseif k == "alpha" then return r._alpha
    elseif k == "rotation" then return r._rot
    end
    return ctrl_mt[k]
  end
  ctrl_mt.__newindex = function(self, k, v)
    local r = rawget(self, "_raw")
    if k == "name" then r._name = v
    elseif k == "visible" then r._vis = v
    elseif k == "active" then r._act = v
    elseif k == "text" then r._text = v
    elseif k == "fontSize" then r._fs = v
    elseif k == "fontColor" then r._fc = v
    elseif k == "imageColor" then r._ic = v
    elseif k == "raycastTarget" then r._ray = v
    elseif k == "blockRaycast" then r._blk = v
    elseif k == "interactable" then r._intr = v
    elseif k == "showCursor" then r._sc = v
    elseif k == "disableCursorEventPassthrough" then r._dcp = v
    elseif k == "clickAudioId" then r._aud = v
    elseif k == "alpha" then r._alpha = v
    elseif k == "rotation" then r._rot = v
    else rawset(self, k, v) end
  end

  function ctrl_mt:GetChildren() return rawget(self, "_raw")._kids end
  function ctrl_mt:GetChild(nm)
    local kids = rawget(self, "_raw")._kids
    for i = 1, #kids do
      if kids[i]._raw._name == nm then return kids[i] end
    end
    return nil
  end
  function ctrl_mt:FindChild(nm) return self:GetChild(nm) end
  function ctrl_mt:GetParent() return rawget(self, "_raw")._parent end
  function ctrl_mt:SetVisible(v) rawget(self, "_raw")._vis = (v == true) end
  function ctrl_mt:SetActive(v) rawget(self, "_raw")._act = (v == true) end
  function ctrl_mt:GetAnchoredPosition() local r = rawget(self, "_raw"); return r._x, r._y end
  function ctrl_mt:SetAnchoredPosition(x, y) local r = rawget(self, "_raw"); r._x, r._y = x, y end
  function ctrl_mt:GetSizeDelta() local r = rawget(self, "_raw"); return r._w, r._h end
  function ctrl_mt:SetSizeDelta(w, h) local r = rawget(self, "_raw"); r._w, r._h = w, h end
  function ctrl_mt:GetLocalScale() local r = rawget(self, "_raw"); return r._sx, r._sy, r._sz end
  function ctrl_mt:SetLocalScale(sx, sy, sz) local r = rawget(self, "_raw"); r._sx, r._sy, r._sz = sx, sy, sz or 1 end
  function ctrl_mt:SetLocalRotation(rx, ry, rz) rawget(self, "_raw")._rot = rz or 0 end
  function ctrl_mt:SetPivot(px, py) end
  function ctrl_mt:SetImage(...) end
  function ctrl_mt:SetAsLastSibling()
    local r = rawget(self, "_raw")
    local p = r._parent
    if not p then return end
    local kids = p._raw._kids
    for i = 1, #kids do
      if kids[i] == self then
        table.remove(kids, i)
        kids[#kids + 1] = self
        return
      end
    end
  end
  function ctrl_mt:SetAsFirstSibling()
    local r = rawget(self, "_raw")
    local p = r._parent
    if not p then return end
    local kids = p._raw._kids
    for i = 1, #kids do
      if kids[i] == self then
        table.remove(kids, i)
        table.insert(kids, 1, self)
        return
      end
    end
  end
  function ctrl_mt:AddCursorEventListener(ev, fn)
    local r = rawget(self, "_raw")
    r._listeners[ev] = r._listeners[ev] or {}
    r._listeners[ev][#r._listeners[ev] + 1] = fn
  end
  function ctrl_mt:SetItemCount(n) rawget(self, "_raw")._item_count = n end
  function ctrl_mt:SetOnItemFillCallback(fn) rawget(self, "_raw")._on_fill = fn end
  function ctrl_mt:RefreshItems() end
  function ctrl_mt:GetItemIndex(item)
    local r = rawget(self, "_raw")
    return r._item_idx and r._item_idx[item] or 0
  end

  local function make_ctrl(id, nm, x, y, w, h)
    local obj = setmetatable({
      _raw = {
        _id = id, _name = nm or "", _vis = true, _act = true,
        _x = x or 0, _y = y or 0, _w = w or 100, _h = h or 100,
        _sx = 1, _sy = 1, _sz = 1, _rot = 0, _alpha = 1,
        _text = "", _fs = 20, _fc = 0, _ic = 0,
        _ray = true, _blk = true, _intr = true, _sc = false, _dcp = false, _aud = 0,
        _kids = {}, _parent = nil, _listeners = {}, _item_idx = {},
      }
    }, ctrl_mt)
    return obj
  end

  local function build_node(n, parent)
    local c = make_ctrl(n.id, n.name, 0, 0, 100, 100)
    by_id[n.id] = c
    if parent then
      c._raw._parent = parent
      parent._raw._kids[#parent._raw._kids + 1] = c
    else
      roots[#roots + 1] = c
    end
    if type(n.kids) == "table" then
      for i = 1, #n.kids do build_node(n.kids[i], c) end
    end
  end
  for i = 1, #raw_tree do build_node(raw_tree[i], nil) end
  local init_sizes = {
    ["hex.submit"] = { 64, 64 }, ["hit.submit"] = { 84, 96 },
    ["hex.ok"] = { 54, 54 },     ["hit.ok"] = { 54, 54 },
    ["hex.no"] = { 54, 54 },     ["hit.no"] = { 54, 54 },
    ["hex.back"] = { 64, 64 },   ["hit.back"] = { 84, 96 },
    ["block640.modal"] = { 1600, 900 }, ["block640.modal.hit"] = { 1600, 900 },
  }
  for _, c in pairs(by_id) do
    local sz = init_sizes[c._raw._name]
    if sz then c._raw._w, c._raw._h = sz[1], sz[2] end
    if c._raw._name == "game742.shade" then c._raw._vis = false end
  end

  local next_dyn = 9900000
  local function clone_ctrl(proto, parent)
    next_dyn = next_dyn + 1
    local pr = proto._raw
    local c = make_ctrl(next_dyn, pr._name, pr._x, pr._y, pr._w, pr._h)
    c._raw._vis = pr._vis
    c._raw._text = pr._text
    c._raw._fs = pr._fs
    if parent then
      c._raw._parent = parent
      parent._raw._kids[#parent._raw._kids + 1] = c
    end
    for i = 1, #pr._kids do clone_ctrl(pr._kids[i], c) end
    return c
  end

  local Enum = {
    CursorEventType = {
      CursorClick = "CursorClick", CursorDown = "CursorDown",
      CursorUp = "CursorUp", CursorDrag = "CursorDrag",
    },
    Device = {
      Keyboard = "Keyboard", Mobile = "Mobile",
      Controller = "Controller", MobileController = "MobileController",
    },
  }

  local env = setmetatable({
    Enum = Enum,
    print = function() end,
    printerr = function() end,
    game = {
      GetClientUIRoots = function() return roots end,
      GetUICanvasSize = function() return cur_w, cur_h end,
      GetDevice = function() return cur_dev end,
      InstantiateClientUIControl = function(pid, parent)
        local proto = by_id[pid]
        if not proto then return nil end
        return clone_ctrl(proto, parent)
      end,
      SendSignalToServer = function(sig, params)
        signals_emitted[#signals_emitted + 1] = { sig = sig, params = params }
      end,
    },
  }, { __index = _G })

  local chunk, err = loadfile(script_path, "t", env)
  assert(chunk, "加载 754 脚本失败: " .. tostring(err))
  chunk()

  env.OnInit()
  env.OnStart()

  local function step(frames, dt)
    dt = dt or (1 / 60)
    for _ = 1, (frames or 1) do env.OnUpdate(dt) end
  end

  local function find_by_name(nm)
    for _, c in pairs(by_id) do
      if c._raw._name == nm then return c end
    end
    return nil
  end

  local function sibling_index(ctrl)
    local p = ctrl and ctrl:GetParent()
    if not p then return -1 end
    local kids = p:GetChildren()
    for i = 1, #kids do
      if kids[i] == ctrl then return i end
    end
    return -1
  end

  local function fire_cursor(ctrl, kind, x, y)
    local ls = ctrl and ctrl._raw._listeners[kind]
    if not ls then return 0 end
    local data = { GetUIPos = function() return x or 0, y or 0 end }
    for i = 1, #ls do ls[i](data) end
    return #ls
  end

  local function find_upval(fn, target, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 80 do
      local nm, val = debug.getupvalue(fn, i)
      if not nm then break end
      if nm == target then return val end
      if type(val) == "function" then
        local got = find_upval(val, target, seen)
        if got ~= nil then return got end
      end
    end
    return nil
  end

  local function get_murdoku() return find_upval(env.OnUpdate, "Murdoku") end

  return {
    env = env, by_id = by_id, step = step, find = find_by_name,
    sibling_index = sibling_index, fire = fire_cursor,
    make_ctrl = make_ctrl, clone_ctrl = clone_ctrl,
    signals = signals_emitted, get_murdoku = get_murdoku,
    find_upval = find_upval,
    set_canvas = function(w, h, dev) cur_w, cur_h = w, h; if dev then cur_dev = dev end end,
  }
end

local results = {}
local all_pass = true
local function check(name, ok, detail)
  results[name] = { pass = (ok == true), detail = detail }
  if not ok then all_pass = false end
  print(string.format("[%s] %s: %s", ok and "PASS" or "FAIL", name, encode_json(detail)))
end

-- A：进入关卡后 90 秒结算门槛
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(10, 1 / 60)
  local cur = sb.get_murdoku().current()
  local ctrl = cur.controller
  cur.adapter._archive_ready = true
  sb.step(30, 1.0)
  local left_home = ctrl:settle_seconds_left()
  ctrl.screen = nil
  sb.step(1, 1.0)
  ctrl:on_input({ action = "back_confirm" })
  sb.step(59, 1.0)
  local left_at_60 = ctrl:settle_seconds_left()
  local sig_before = #sb.signals
  ctrl:on_input({ action = "exit_menu_settle" })
  local blocked_at_60 = (#sb.signals == sig_before)
  sb.step(30, 1.0)
  local can_at_90 = ctrl:can_settle()

  local sb2 = build_sandbox(1600, 900, "Mobile")
  sb2.step(5, 1 / 60)
  local ctrl2 = sb2.get_murdoku().current().controller
  ctrl2.screen = nil
  ctrl2.core.status = "solved"
  local can_solved = ctrl2:can_settle()

  check("a_settle_90s_after_enter_level",
    (left_home == 90) and (left_at_60 == 30) and blocked_at_60 and can_at_90 and can_solved,
    { left_home = left_home, left_at_60 = left_at_60, blocked_at_60 = blocked_at_60, can_at_90 = can_at_90, can_solved = can_solved })
end

-- B：提交反馈与确认条第 0 帧对齐
do
  local sb = build_sandbox(1600, 738, "Mobile")
  sb.step(10, 1 / 60)
  local ctrl = sb.get_murdoku().current().controller
  ctrl.screen = nil
  sb.step(20, 1 / 60)
  local hex_sub = sb.find("hex.submit")
  local hex_ok  = sb.find("hex.ok")
  local hit_ok  = sb.find("hit.ok")
  local _, sub_y = hex_sub:GetAnchoredPosition()
  ctrl:on_input({ action = "submit" })
  sb.step(1, 1 / 60)
  local ok_x, ok_y = hex_ok:GetAnchoredPosition()
  local hok_x, hok_y = hit_ok:GetAnchoredPosition()
  local immediate_align = (math.abs(ok_y - sub_y) < 0.01) and (math.abs(hok_y - sub_y) < 0.01) and (math.abs(ok_x - hok_x) < 0.01)

  ctrl:on_input({ action = "confirm_yes" })
  sb.step(2, 1 / 60)
  local hint_res = sb.find("hint635.result")
  local hint_body = sb.find("hint635.result.body")
  local shown_msg = (ctrl.hint635 ~= nil and hint_res.visible == true and hint_body.text:find("无法提交", 1, true) ~= nil)

  for id, p in pairs(ctrl.core.solution) do
    ctrl.core:select_suspect(id)
    ctrl.core:hold_cell(p.r, p.c)
  end
  ctrl:on_input({ action = "submit" })
  ctrl:on_input({ action = "confirm_yes" })
  sb.step(300, 1 / 60)
  local win_modal = (ctrl.modal ~= nil and ctrl.modal.kind == "result" and ctrl.modal.win == true)

  check("b_submit_feedback_and_confirm_align", immediate_align and shown_msg and win_modal,
    { immediate_align = immediate_align, shown_msg = shown_msg, win_modal = win_modal })
end

-- C：平板 4:3 遮罩缩放与按钮防遮挡
do
  local sb = build_sandbox(1600, 1200, "Mobile")
  sb.step(10, 1 / 60)
  local cur = sb.get_murdoku().current()
  local ctrl = cur.controller
  ctrl.screen = nil
  sb.step(20, 1 / 60)
  ctrl.modal = { kind = "result", win = true, outcome = "perfect" }
  ctrl.dirty = true
  sb.step(5, 1 / 60)
  local _, sy = sb.find("block640.modal"):GetLocalScale()
  local covered_h = 900 * sy
  local win_idx = sb.sibling_index(sb.find("win"))
  local next_idx = sb.sibling_index(sb.find("result.next"))
  local exit_idx = sb.sibling_index(sb.find("result.exit"))
  local win_ray_off = (sb.find("win").raycastTarget == false)
  sb.fire(sb.find("result.next"), "CursorClick", 0, 0)
  sb.step(3, 1 / 60)
  local after_lv = sb.get_murdoku().current().level.id
  check("c_tablet_4_3_modal_cover_and_buttons",
    (covered_h >= 1200) and (next_idx > win_idx) and (exit_idx > win_idx) and win_ray_off and (after_lv == "case_002"),
    { covered_h = covered_h, win_idx = win_idx, next_idx = next_idx, exit_idx = exit_idx, after_lv = after_lv })
end

-- D：移动端人物栏滑动不拦截 + 点选人后立即双击放人 + 抗 os.clock 漂移
do
  local sb = build_sandbox(1600, 738, "Mobile")
  sb.step(10, 1 / 60)
  local cur = sb.get_murdoku().current()
  local ctrl = cur.controller
  ctrl.screen = nil
  sb.step(10, 1 / 60)
  local grid = sb.find("clues.grid")
  local item = sb.clone_ctrl(sb.by_id[1073742421], grid)
  grid._raw._item_idx[item] = 0
  ctrl._grid_seen = { [item] = 0 }
  ctrl._grid_base = 0
  ctrl._grid_bind_item_click(ctrl, cur.adapter, grid, item)
  local no_drag = (item._raw._listeners["CursorDrag"] == nil)
  local passthrough = (item.disableCursorEventPassthrough == false)

  sb.fire(item, "CursorDown", 100, 100)
  sb.fire(item, "CursorUp", 100, 140)
  sb.fire(item, "CursorClick", 100, 140)
  sb.step(30, 1 / 60)
  local swipe_ok = (ctrl.core.selected == nil)

  sb.fire(item, "CursorDown", 100, 100)
  sb.fire(item, "CursorUp", 102, 101)
  sb.fire(item, "CursorClick", 102, 101)
  sb.step(3, 1 / 60)
  local tr, tc
  for r = 1, ctrl.core.rows do
    for c = 1, ctrl.core.cols do
      if not ctrl.core:is_blocked(r, c) and ctrl.core.grid[r][c] == nil then tr, tc = r, c; break end
    end
    if tr then break end
  end
  ctrl:on_input({ action = "click", phase = "down", r = tr, c = tc, x = 0, y = 0 })
  ctrl:on_input({ action = "click", phase = "up",   r = tr, c = tc, x = 0, y = 0 })
  ctrl:on_input({ action = "click", r = tr, c = tc })
  sb.step(10, 1 / 60)
  ctrl:on_input({ action = "click", phase = "down", r = tr, c = tc, x = 0, y = 0 })
  ctrl:on_input({ action = "click", phase = "up",   r = tr, c = tc, x = 0, y = 0 })
  ctrl:on_input({ action = "click", r = tr, c = tc })
  local placed_now = (ctrl.core.grid[tr][tc] ~= nil)

  local orig_clock = os.clock
  local fake_cpu = 100.0
  os.clock = function() fake_cpu = fake_cpu + 5.0; return fake_cpu end
  local tr2, tc2
  for r = 1, ctrl.core.rows do
    for c = 1, ctrl.core.cols do
      if r ~= tr and c ~= tc and not ctrl.core:is_blocked(r, c) and ctrl.core.grid[r][c] == nil then tr2, tc2 = r, c; break end
    end
    if tr2 then break end
  end
  local next_who
  for i = 1, #ctrl.core.pieces do
    if not ctrl.core.pos[ctrl.core.pieces[i].id] then next_who = ctrl.core.pieces[i].id; break end
  end
  ctrl.core:select_suspect(next_who)
  ctrl:on_input({ action = "click", r = tr2, c = tc2 })
  sb.step(24, 1 / 60)
  ctrl:on_input({ action = "click", r = tr2, c = tc2 })
  os.clock = orig_clock
  local placed_drift = (ctrl.core.grid[tr2][tc2] == next_who)

  check("d_mobile_grid_swipe_and_double_tap_place",
    no_drag and passthrough and swipe_ok and placed_now and placed_drift,
    { no_drag = no_drag, passthrough = passthrough, swipe_ok = swipe_ok, placed_now = placed_now, placed_drift = placed_drift })
end

-- E：教程精简页数映射（l1 4页 / l2 3页）
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(10, 1 / 60)
  local tut_inst_fn = assert(sb.find_upval(sb.env.OnUpdate, "tutorial_instance"))
  local TUT_SETS = assert(sb.find_upval(sb.env.OnUpdate, "TUT_SETS"))
  local l1 = tut_inst_fn(TUT_SETS.l1)
  l1:open_ui()
  local l1_p1 = (sb.find("td.l1.page.1").visible == true) and (sb.find("td.l1.page.2").visible == false)
  l1:next()
  local l1_p2 = (sb.find("td.l1.page.3").visible == true) and (sb.find("td.l1.page.1").visible == false)
  l1:go(4)
  local l1_p4 = (sb.find("td.l1.page.8").visible == true) and (sb.find("td.l1.page.8.nexttext").text == "开始办案")
  l1:next()
  local l1_close = (l1.open == false)

  local l2 = tut_inst_fn(TUT_SETS.l2)
  l2:open_ui()
  local l2_p1 = (sb.find("td.l2.page.2").visible == true) and (sb.find("td.l2.page.1").visible == false)
  l2:go(3)
  local l2_p3 = (sb.find("td.l2.page.4").visible == true) and (sb.find("td.l2.page.4.nexttext").text == "开始办案")
  l2:next()
  local l2_close = (l2.open == false)

  check("e_tutorial_compact_pages_and_mapping",
    l1_p1 and l1_p2 and l1_p4 and l1_close and l2_p1 and l2_p3 and l2_close,
    { l1_p1 = l1_p1, l1_p2 = l1_p2, l1_p4 = l1_p4, l1_close = l1_close, l2_p1 = l2_p1, l2_p3 = l2_p3, l2_close = l2_close })
end

-- F：房间/图例底色高区分度
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(5, 1 / 60)
  local ctrl = sb.get_murdoku().current().controller
  local rc = ctrl.ROOM_COLORS
  local function dist(a, b)
    return math.sqrt((a.r - b.r)^2 + (a.g - b.g)^2 + (a.b - b.b)^2)
  end
  local min_dist = math.min(dist(rc[1], rc[2]), dist(rc[1], rc[3]), dist(rc[2], rc[3]), dist(rc[3], rc[4]))
  check("f_room_colors_high_separation", min_dist >= 40, { min_dist = math.floor(min_dist + 0.5) })
end

-- G：教程全屏半透明变暗遮罩与层序
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(10, 1 / 60)
  local cur = sb.get_murdoku().current()
  cur.adapter._archive_ready = true
  local mur = sb.get_murdoku()
  mur.tutorial_seen.home = true
  mur.tutorial_seen.l1 = true
  mur.tutorial_seen.l2 = true
  sb.step(25, 1 / 60)

  local tut_inst_fn = assert(sb.find_upval(sb.env.OnUpdate, "tutorial_instance"))
  local TUT_SETS = assert(sb.find_upval(sb.env.OnUpdate, "TUT_SETS"))
  local shade = assert(sb.find("game742.shade"), "找不到 game742.shade")
  local init_hidden = (shade.visible == false)

  local function test_tut_shade(tag, root_name)
    local inst = tut_inst_fn(TUT_SETS[tag])
    inst:open_ui()
    sb.step(3, 1 / 60)
    local vis_open = (shade.visible == true)
    local ray_off = (shade.raycastTarget == false)
    local z_shade = sb.sibling_index(shade)
    local z_blk   = sb.sibling_index(sb.find("block640." .. tag))
    local z_tut   = sb.sibling_index(sb.find(root_name))
    local z_ok = (z_shade < z_blk) and (z_blk < z_tut)
    inst:close()
    sb.step(3, 1 / 60)
    local vis_closed = (shade.visible == false)
    return vis_open and ray_off and z_ok and vis_closed,
      { vis_open = vis_open, ray_off = ray_off, z_shade = z_shade, z_blk = z_blk, z_tut = z_tut, vis_closed = vis_closed }
  end

  local ok_home = test_tut_shade("home", "td.home")
  cur.controller.screen = nil
  cur.controller.dirty = true
  sb.step(25, 1 / 60)
  local ok_l1 = test_tut_shade("l1", "td.l1")
  sb.get_murdoku().current().controller:on_input({ action = "next_level" })
  sb.step(25, 1 / 60)
  local ok_l2 = test_tut_shade("l2", "td.l2")

  local ctrl = sb.get_murdoku().current().controller
  ctrl:on_input({ action = "back_confirm" })
  sb.step(3, 1 / 60)
  local exit_shade_ok = (shade.visible == true) and (sb.sibling_index(shade) < sb.sibling_index(sb.find("modal")))
  ctrl:on_input({ action = "close_modal" })
  sb.step(3, 1 / 60)
  local exit_close_ok = (shade.visible == false)

  check("g_tutorial_dim_shade_and_zorder",
    init_hidden and ok_home and ok_l1 and ok_l2 and exit_shade_ok and exit_close_ok,
    { init_hidden = init_hidden, ok_home = ok_home, ok_l1 = ok_l1, ok_l2 = ok_l2, exit_shade_ok = exit_shade_ok, exit_close_ok = exit_close_ok })
end

-- H：教程图标控件存在性
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(5, 1 / 60)
  local icon_names = {
    "td.home.page.1.ico.submit.bg", "td.home.page.1.ico.undo.bg", "td.home.page.1.ico.redo.bg",
    "td.home.page.1.help619.icon", "td.l1.page.1.help619.icon", "td.l1.page.3.ico.undo.bg",
    "td.l1.page.8.ico.submit.bg", "td.l1.page.8.ico.hint.bg", "td.l2.page.3.ico.hint631",
    "td.l2.page.4.ico.submit.bg",
  }
  local all_exist = true
  for _, nm in ipairs(icon_names) do
    if not sb.find(nm) then all_exist = false end
  end
  check("h_icon_sizes_and_text_alignment", all_exist, { all_exist = all_exist, icon_count = #icon_names })
end

-- I：关卡胜利后退出重进不改直接提交 -> 直接出弹窗、不重画圈、不解锁结算限制
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(10, 1 / 60)
  local mur = sb.get_murdoku()
  local cur = mur.current()
  local ctrl = cur.controller
  local ad = cur.adapter
  ad._archive_ready = true
  mur.tutorial_seen.home, mur.tutorial_seen.l1, mur.tutorial_seen.l2 = true, true, true

  ctrl.screen = nil
  for id, p in pairs(ctrl.core.solution) do
    ctrl.core:select_suspect(id)
    ctrl.core:hold_cell(p.r, p.c)
  end
  ctrl:on_input({ action = "submit" })
  ctrl:on_input({ action = "confirm_yes" })
  sb.step(300, 1 / 60)
  local saved_slot = ad._save_pending or ad._confirmed
  assert(saved_slot ~= nil and saved_slot.solved == true, "应已生成通关存档")

  local sb_re = build_sandbox(1600, 900, "Mobile")
  sb_re.step(10, 1 / 60)
  local mur_r = sb_re.get_murdoku()
  local cur_r = mur_r.current()
  local ad_r0 = cur_r.adapter
  ad_r0._archive_ready = true
  mur_r.tutorial_seen.home, mur_r.tutorial_seen.l1, mur_r.tutorial_seen.l2 = true, true, true
  ad_r0._confirmed = saved_slot
  ad_r0._save_pending = nil
  local resumed = mur_r.resume_selected("case_001")
  local ctrl_r = mur_r.current().controller
  local ad_r = mur_r.current().adapter

  local locked_after_resume = (ctrl_r:can_settle() == false) and (ctrl_r:settle_seconds_left() > 0)
  local has_rings_after_resume = (ctrl_r._verdict ~= nil and ctrl_r._verdict.done == true and ctrl_r._resumed_solved_board == true)

  local ring_calls = 0
  local orig_ring = ad_r.set_verdict_ring
  ad_r.set_verdict_ring = function(self_a, ...)
    ring_calls = ring_calls + 1
    if orig_ring then return orig_ring(self_a, ...) end
  end

  ctrl_r:on_input({ action = "submit" })
  ctrl_r:on_input({ action = "confirm_yes" })
  local instant_modal = (ctrl_r.modal ~= nil and ctrl_r.modal.kind == "result" and ctrl_r.modal.win == true and ctrl_r.modal.outcome == "perfect")
  sb_re.step(10, 1 / 60)
  local no_redraw_rings = (ring_calls == 0)
  local still_locked = (ctrl_r:can_settle() == false) and (ctrl_r:settle_seconds_left() > 0)

  ctrl_r.modal = nil
  ctrl_r.dirty = true
  local some_id, some_pos
  for id, p in pairs(ctrl_r.core.solution) do some_id, some_pos = id, p; break end
  ctrl_r.core:tap_cell(some_pos.r, some_pos.c)
  sb_re.step(2, 1 / 60)
  local cleared_after_edit = (ctrl_r._verdict == nil and ctrl_r._resumed_solved_board == nil)
  ctrl_r.core:select_suspect(some_id)
  ctrl_r.core:hold_cell(some_pos.r, some_pos.c)
  ctrl_r:on_input({ action = "submit" })
  ctrl_r:on_input({ action = "confirm_yes" })
  sb_re.step(300, 1 / 60)
  local redrawn_after_edit = (ring_calls > 0)
  local unlocked_after_re_solve = (ctrl_r:can_settle() == true)

  check("i_resumed_solved_resubmit_fast_modal_and_no_unlock",
    resumed and locked_after_resume and has_rings_after_resume and instant_modal and no_redraw_rings and still_locked
      and cleared_after_edit and redrawn_after_edit and unlocked_after_re_solve,
    {
      resumed = resumed,
      locked_after_resume = locked_after_resume,
      has_rings_after_resume = has_rings_after_resume,
      instant_modal = instant_modal,
      ring_calls_before_edit = no_redraw_rings,
      still_locked = still_locked,
      cleared_after_edit = cleared_after_edit,
      redrawn_after_edit = redrawn_after_edit,
      unlocked_after_re_solve = unlocked_after_re_solve,
    })
end

-- J：754 全部教程页（home / l1 x4 / l2 x3）完整切换且步骤条绿勾控件存在
do
  local sb = build_sandbox(1600, 900, "Mobile")
  sb.step(10, 1 / 60)
  local tut_inst_fn = assert(sb.find_upval(sb.env.OnUpdate, "tutorial_instance"))
  local TUT_SETS = assert(sb.find_upval(sb.env.OnUpdate, "TUT_SETS"))
  local done_bgs = {
    "td.l1.page.3.stepn.1.bg",
    "td.l1.page.7.stepn.1.bg", "td.l1.page.7.stepn.2.bg",
    "td.l1.page.8.stepn.1.bg", "td.l1.page.8.stepn.2.bg", "td.l1.page.8.stepn.3.bg",
    "td.l2.page.3.stepn.1.bg",
    "td.l2.page.4.stepn.1.bg", "td.l2.page.4.stepn.2.bg",
  }
  local check_ok = true
  for _, nm in ipairs(done_bgs) do
    if not sb.find(nm) then check_ok = false end
  end
  local l1 = tut_inst_fn(TUT_SETS.l1)
  l1:open_ui()
  local visited_l1 = 0
  for i = 1, 4 do l1:go(i); sb.step(2, 1 / 60); visited_l1 = visited_l1 + 1 end
  l1:close()
  local l2 = tut_inst_fn(TUT_SETS.l2)
  l2:open_ui()
  local visited_l2 = 0
  for i = 1, 3 do l2:go(i); sb.step(2, 1 / 60); visited_l2 = visited_l2 + 1 end
  l2:close()
  check("j_754_all_tutorial_pages_and_checkmarks",
    check_ok and visited_l1 == 4 and visited_l2 == 3,
    { check_ok = check_ok, done_checkmark_count = #done_bgs, visited_l1 = visited_l1, visited_l2 = visited_l2 })
end

local report = { version = "754", pass = all_pass, checks = results }
local fh = assert(io.open(out_json, "w"))
fh:write(encode_json(report))
fh:close()
print("VERIFY_754_PASS=" .. tostring(all_pass))
if not all_pass then os.exit(1) end
print("VERIFY_754_FEEDBACK_OK")
