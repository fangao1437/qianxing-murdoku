-- tests/perf_verify_748.lua —— 正式入库的端到端高仿真验证、31 项故障注入与 6 代 5 轮统一采样基准
-- 用法：lua tests/perf_verify_748.lua <tree.lua> <742v12.lua> <743.lua> <745.lua> <746.lua> <747.lua> <748.lua> <out.json> <candSha> [--skip-bench]
local tree_path = assert(arg[1], "missing tree_path")
local p742 = assert(arg[2], "missing p742")
local p743 = assert(arg[3], "missing p743")
local p745 = assert(arg[4], "missing p745")
local p746 = assert(arg[5], "missing p746")
local p747 = assert(arg[6], "missing p747")
local p748 = assert(arg[7], "missing p748")
local out_json = assert(arg[8], "missing out_json")
local cand_sha = arg[9] or ""
local skip_bench = false
for i = 10, #arg do
  if arg[i] == "--skip-bench" then skip_bench = true end
end

local TREE_SPEC = assert(dofile(tree_path))

-- ── 简易 JSON 编码器 ────────────────────────────────────────────────────────
local function json_esc(s)
  return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return false end
    if k > n then n = k end
  end
  for i = 1, n do if t[i] == nil then return false end end
  return n > 0
end
local function to_json(v)
  local tv = type(v)
  if v == nil then return "null"
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.floor(v) == v and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.4f", v)
  elseif tv == "string" then return json_esc(v)
  elseif tv == "table" then
    if is_array(v) then
      local out = {}
      for i = 1, #v do out[i] = to_json(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      local out = {}
      for i = 1, #keys do
        local k = keys[i]
        out[i] = json_esc(k) .. ":" .. to_json(v[k])
      end
      return "{" .. table.concat(out, ",") .. "}"
    end
  end
  return "null"
end

-- ── 高仿真千星 UI 控件树沙箱 ─────────────────────────────────────────────────
local function make_sandbox(script_path, opts)
  opts = opts or {}
  local stats = {
    api = 0, get_kids = 0, get_child = 0, set_vis = 0, set_act = 0,
    set_pos = 0, set_scale = 0, set_size = 0, last_sib = 0,
    prop_get = 0, prop_set = 0, pcall_n = 0,
    redundant_vis = 0, redundant_pos = 0, redundant_scale = 0,
  }
  local canvas_w, canvas_h = opts.cw or 1920, opts.ch or 1080
  local device_name = opts.device or "PC"
  local next_id = 900000
  local all_nodes = {}
  local by_name = {}
  local hooks = opts.hooks or {}

  local ctrl_mt
  local function new_node(id, name)
    local raw = {
      _id = id,
      _name = name or "",
      _visible = true,
      _active = true,
      _ray = false,
      _blk = true,
      _intr = true,
      _showCursor = false,
      _disablePass = false,
      _disableKeyPass = false,
      _text = "",
      _fontSize = 18,
      _minFontSize = 10,
      _adaptiveFontSize = true,
      _fontColor = 0xFFFFFFFF,
      _imageColor = 0xFFFFFFFF,
      _imageId = 1001,
      _imageSource = 4294967295,
      _imageType = 0,
      _clickAudioId = 1,
      _prefabIndex = id,
      _px = 0, _py = 0, _sx = 1, _sy = 1, _sz = 1, _w = 120, _h = 120,
      _ax0 = 0.5, _ay0 = 0.5, _ax1 = 0.5, _ay1 = 0.5, _pivx = 0.5, _pivy = 0.5,
      _kids = {},
      _parent = nil,
      _listeners = {},
      _key_listeners = {},
      _kind = "UIControl",
    }
    local obj = setmetatable({ _raw = raw }, ctrl_mt)
    all_nodes[#all_nodes + 1] = obj
    if name and name ~= "" and by_name[name] == nil then by_name[name] = obj end
    return obj
  end

  local methods = {}
  function methods:GetChildren()
    stats.api = stats.api + 1; stats.get_kids = stats.get_kids + 1
    if hooks.get_kids then hooks.get_kids(self) end
    local res = {}
    local ks = self._raw._kids
    for i = 1, #ks do res[i] = ks[i] end
    return res
  end
  function methods:GetChild(nm)
    stats.api = stats.api + 1; stats.get_child = stats.get_child + 1
    local ks = self._raw._kids
    for i = 1, #ks do
      if ks[i]._raw._name == nm then return ks[i] end
    end
    return nil
  end
  function methods:SetVisible(v)
    stats.api = stats.api + 1; stats.set_vis = stats.set_vis + 1
    local b = v and true or false
    if hooks.set_vis then hooks.set_vis(self, b) end
    if self._raw._visible == b then stats.redundant_vis = stats.redundant_vis + 1 end
    self._raw._visible = b
  end
  function methods:SetActive(v)
    stats.api = stats.api + 1; stats.set_act = stats.set_act + 1
    local b = v and true or false
    if hooks.set_act then hooks.set_act(self, b) end
    self._raw._active = b
  end
  function methods:GetAnchoredPosition()
    stats.api = stats.api + 1
    if hooks.get_pos then return hooks.get_pos(self) end
    return self._raw._px, self._raw._py
  end
  function methods:SetAnchoredPosition(x, y)
    stats.api = stats.api + 1; stats.set_pos = stats.set_pos + 1
    if hooks.set_pos then
      local r = hooks.set_pos(self, x, y)
      if r == false then return end
    end
    if self._raw._px == x and self._raw._py == y then stats.redundant_pos = stats.redundant_pos + 1 end
    self._raw._px, self._raw._py = x, y
  end
  function methods:GetLocalScale()
    stats.api = stats.api + 1
    return self._raw._sx, self._raw._sy, self._raw._sz
  end
  function methods:SetLocalScale(sx, sy, sz)
    stats.api = stats.api + 1; stats.set_scale = stats.set_scale + 1
    if hooks.set_scale then
      local r = hooks.set_scale(self, sx, sy, sz)
      if r == false then return end
    end
    if self._raw._sx == sx and self._raw._sy == sy then stats.redundant_scale = stats.redundant_scale + 1 end
    self._raw._sx, self._raw._sy, self._raw._sz = sx, sy, sz or 1
  end
  function methods:GetSizeDelta()
    stats.api = stats.api + 1
    return self._raw._w, self._raw._h
  end
  function methods:SetSizeDelta(w, h)
    stats.api = stats.api + 1; stats.set_size = stats.set_size + 1
    self._raw._w, self._raw._h = w, h
  end
  function methods:SetAnchorMin(x, y) self._raw._ax0, self._raw._ay0 = x, y end
  function methods:SetAnchorMax(x, y) self._raw._ax1, self._raw._ay1 = x, y end
  function methods:SetPivot(x, y) self._raw._pivx, self._raw._pivy = x, y end
  function methods:SetAsLastSibling()
    stats.api = stats.api + 1; stats.last_sib = stats.last_sib + 1
    if hooks.last_sib then hooks.last_sib(self) end
    local p = self._raw._parent
    if p then
      local ks = p._raw._kids
      for i = 1, #ks do
        if ks[i] == self then
          table.remove(ks, i)
          ks[#ks + 1] = self
          break
        end
      end
    end
  end
  function methods:SetSiblingIndex(idx)
    stats.api = stats.api + 1
    local p = self._raw._parent
    if p then
      local ks = p._raw._kids
      for i = 1, #ks do
        if ks[i] == self then table.remove(ks, i); break end
      end
      local pos = math.max(1, math.min(#ks + 1, (tonumber(idx) or 0) + 1))
      table.insert(ks, pos, self)
    end
  end
  function methods:GetSiblingIndex()
    local p = self._raw._parent
    if not p then return -1 end
    local ks = p._raw._kids
    for i = 1, #ks do if ks[i] == self then return i - 1 end end
    return -1
  end
  function methods:SetText(t) stats.api = stats.api + 1; self._raw._text = tostring(t or "") end
  function methods:SetImage(src, id) stats.api = stats.api + 1; self._raw._imageSource = src; self._raw._imageId = id end
  function methods:AddCursorEventListener(ev, fn)
    stats.api = stats.api + 1
    local list = self._raw._listeners[ev]
    if not list then list = {}; self._raw._listeners[ev] = list end
    list[#list + 1] = fn
    return true
  end
  function methods:AddKeyEventListener(ev, fn)
    stats.api = stats.api + 1
    self._raw._key_listeners[ev] = fn
    return true
  end
  function methods:FireClick()
    if self._raw._ray ~= true then return false end
    local list = self._raw._listeners[1]
    if not list or #list == 0 then return false end
    for i = 1, #list do list[i]({ GetUIPos = function() return 0, 0 end }) end
    return true
  end

  local prop_map = {
    name = "_name", visible = "_visible", active = "_active",
    raycastTarget = "_ray", blockRaycast = "_blk", interactable = "_intr",
    showCursor = "_showCursor", disableCursorEventPassthrough = "_disablePass",
    disableKeyEventPassthrough = "_disableKeyPass",
    text = "_text", fontSize = "_fontSize", minimumFontSize = "_minFontSize",
    adaptiveFontSize = "_adaptiveFontSize", fontColor = "_fontColor",
    imageColor = "_imageColor", imageId = "_imageId", imageSource = "_imageSource",
    imageType = "_imageType", clickAudioId = "_clickAudioId", kind = "_kind", prefabIndex = "_prefabIndex",
  }

  ctrl_mt = {
    __index = function(self, k)
      if k == "GetAnchoredPosition" and hooks.hide_get_pos and hooks.hide_get_pos(self) then
        return nil
      end
      local m = methods[k]
      if m ~= nil then return m end
      local fk = prop_map[k]
      if fk ~= nil then
        stats.prop_get = stats.prop_get + 1
        if hooks.prop_get then hooks.prop_get(self, k) end
        return self._raw[fk]
      end
      return nil
    end,
    __newindex = function(self, k, v)
      local fk = prop_map[k]
      if fk ~= nil then
        stats.prop_set = stats.prop_set + 1
        if hooks.prop_set then
          local r = hooks.prop_set(self, k, v)
          if r == false then return end
        end
        self._raw[fk] = v
      else
        rawset(self, k, v)
      end
    end,
  }

  local function build_node(spec, parent)
    local n = new_node(spec.id, spec.name)
    n._raw._parent = parent
    if parent then parent._raw._kids[#parent._raw._kids + 1] = n end
    if spec.kids then
      for i = 1, #spec.kids do build_node(spec.kids[i], n) end
    end
    return n
  end
  local roots = {}
  for i = 1, #TREE_SPEC do
    roots[i] = build_node(TREE_SPEC[i], nil)
  end

  local function find_in_tree(nm)
    local function w(x)
      if x._raw._name == nm then return x end
      local ks = x._raw._kids
      for i = 1, #ks do
        local r = w(ks[i])
        if r then return r end
      end
      return nil
    end
    for i = 1, #roots do
      local r = w(roots[i])
      if r then return r end
    end
    return nil
  end

  local function clone_node(src, parent)
    next_id = next_id + 1
    local c = new_node(next_id, src._raw._name)
    c._raw._parent = parent
    c._raw._w, c._raw._h = src._raw._w, src._raw._h
    if parent then parent._raw._kids[#parent._raw._kids + 1] = c end
    for i = 1, #src._raw._kids do clone_node(src._raw._kids[i], c) end
    return c
  end

  local real_pcall = pcall
  local env = {}
  for k, v in pairs(_G) do env[k] = v end
  env._G = env
  env.print = function() end
  env.printerr = function() end
  env.pcall = function(fn, ...)
    stats.pcall_n = stats.pcall_n + 1
    return real_pcall(fn, ...)
  end
  env.Enum = {
    CursorEventType = { CursorClick = 1, CursorDown = 2, CursorUp = 3, CursorDrag = 4 },
    KeyEventType = { KeyR = 1, KeyZ = 2, KeySpace = 3, KeyEscape = 4 },
    ImageSource = { Currency = 4294967295, Custom = 1 },
    ImageType = { Basic = 0, Stretch = 1 },
    TextVerticalAlignment = { Middle = 1 },
  }
  env.game = {
    GetClientUIRoots = function() return roots end,
    GetUICanvasSize = function() return canvas_w, canvas_h end,
    GetDevice = function() return { Name = device_name } end,
    InstantiateClientUIControl = function(prefab_or_id, parent)
      -- 真实千星客户端按 prefabIndex 克隆对应模板（如 cell.1.1 模板带 content/x/note/wall.*/door.* 子树）
      local tpl = find_in_tree("cell.1.1")
      if tpl ~= nil and parent ~= nil and (parent._raw._name == "stage" or parent._raw._name == "board") then
        return clone_node(tpl, parent)
      end
      next_id = next_id + 1
      local c = new_node(next_id, "inst." .. next_id)
      c._raw._parent = parent
      if parent then parent._raw._kids[#parent._raw._kids + 1] = c end
      return c
    end,
    DestroyClientUIControl = function(c)
      if c and c._raw._parent then
        local ks = c._raw._parent._raw._kids
        for i = 1, #ks do if ks[i] == c then table.remove(ks, i); break end end
        c._raw._parent = nil
      end
    end,
  }

  local chunk, err = loadfile(script_path, "t", env)
  assert(chunk, "loadfile failed (" .. script_path .. "): " .. tostring(err))
  chunk()
  if opts.before_init then opts.before_init({ roots = roots, find = find_in_tree, new_node = new_node }) end
  if env.OnInit then env.OnInit() end
  if env.OnStart then env.OnStart() end
  -- 模拟真实客户端首帧存档状态就绪（避免 continue 一直等待云端回调）
  if env.OnUpdate then
    local i = 1
    while true do
      local nm, val = debug.getupvalue(env.OnUpdate, i)
      if not nm then break end
      if nm == "adapter" and type(val) == "table" then
        val._archive_ready = true
        val._confirmed = 1
      end
      i = i + 1
    end
  end

  local box = {
    env = env,
    roots = roots,
    stats = stats,
    all_nodes = all_nodes,
    by_name = by_name,
    hooks = hooks,
    find = find_in_tree,
    new_node = new_node,
    clone_node = clone_node,
    set_canvas = function(w, h) canvas_w, canvas_h = w, h end,
    step = function(self, n, dt)
      dt = dt or (1 / 60)
      for _ = 1, (n or 1) do
        if env.OnUpdate then env.OnUpdate(dt) end
      end
    end,
    reset_stats = function(self)
      for k in pairs(stats) do stats[k] = 0 end
    end,
    snapshot_all = function(self)
      local out = {}
      local function nz(v) return (v == 0) and 0 or v end
      for i = 1, #all_nodes do
        local r = all_nodes[i]._raw
        out[r._id] = string.format("%s|%s|%s|%s|%.1f|%.1f|%.2f|%.2f|%.1f",
          r._name, tostring(r._visible), tostring(r._active), tostring(r._text),
          nz(r._px), nz(r._py), nz(r._sx), nz(r._sy), nz(r._fontSize))
      end
      return out
    end,
    get_murdoku = function(self)
      -- 从全局函数 OnUpdate 的 upvalue 提取 Murdoku 与 adapter
      local M, ad
      if env.OnUpdate then
        local i = 1
        while true do
          local name, val = debug.getupvalue(env.OnUpdate, i)
          if not name then break end
          if name == "Murdoku" then M = val end
          if name == "adapter" then ad = val end
          i = i + 1
        end
      end
      return M, ad
    end,
    send_action = function(self, evt)
      local M = self:get_murdoku()
      local cur = M and M.current and M.current()
      assert(cur and cur.controller, "controller not ready")
      cur.controller:on_input(evt)
    end,
  }
  return box
end

-- ── 1. 32 阶段全量真实控件快照等价差分（支持任意两版比对） ────────────────
local function run_32_stage_equivalence(pathA, pathB, label)
  local A = make_sandbox(pathA)
  local B = make_sandbox(pathB)
  local stages = {
    function(s) s:step(15) end,
    function(s) s:step(30) end,
    function(s) s:set_canvas(2400, 1080); s:step(20) end,
    function(s) s:set_canvas(1440, 1080); s:step(20) end,
    function(s) s:set_canvas(1920, 1080); s:step(20) end,
    function(s) s:send_action({ action = "levelselect" }); s:step(20) end,
    function(s) s:step(25) end,
    function(s) s:send_action({ action = "select_page", delta = 1 }); s:step(20) end,
    function(s) s:send_action({ action = "select_page", delta = 1 }); s:step(20) end,
    function(s) s:send_action({ action = "select_page", delta = -2 }); s:step(20) end,
    function(s) s:send_action({ action = "home" }); s:step(20) end,
    function(s) s:send_action({ action = "shop" }); s:step(20) end,
    function(s) s:step(25) end,
    function(s) s:send_action({ action = "bag" }); s:step(20) end,
    function(s) s:step(25) end,
    function(s) s:send_action({ action = "home" }); s:step(20) end,
    function(s) s:send_action({ action = "levelselect" }); s:step(15) end,
    function(s) s:send_action({ action = "pick_level", id = "case_001" }); s:step(25) end,
    function(s) s:step(30) end,
    function(s) s:send_action({ action = "mode", mode = "mark" }); s:step(10) end,
    function(s) s:send_action({ action = "cell", r = 1, c = 1, phase = "click" }); s:step(10) end,
    function(s) s:send_action({ action = "cell", r = 2, c = 2, phase = "click" }); s:step(10) end,
    function(s) s:send_action({ action = "undo" }); s:step(10) end,
    function(s) s:send_action({ action = "submit" }); s:step(15) end,
    function(s) s:send_action({ action = "confirm_no" }); s:step(10) end,
    function(s) s:send_action({ action = "restart" }); s:step(15) end,
    function(s) s:send_action({ action = "confirm_no" }); s:step(10) end,
    function(s) s:send_action({ action = "back_confirm" }); s:step(15) end,
    function(s) s:send_action({ action = "modal_close" }); s:step(10) end,
    function(s) s:send_action({ action = "home" }); s:step(20) end,
    function(s) s:send_action({ action = "shop" }); s:step(20) end,
    function(s) s:send_action({ action = "home" }); s:step(20) end,
  }
  local total_diffs = 0
  local visible_diffs = 0
  local hidden_timer_diffs = 0
  local other_hidden_diffs = 0
  local sample_diffs = {}
  local nodes_per = #A.all_nodes
  local timer_names = {
    ["hud.timer"] = true, ["settle.btn.countdown"] = true,
    ["result.settle.countdown"] = true, ["modal.settle.countdown"] = true,
  }
  for si = 1, #stages do
    stages[si](A)
    stages[si](B)
    local sa, sb = A:snapshot_all(), B:snapshot_all()
    for id, va in pairs(sa) do
      local vb = sb[id]
      if va ~= vb then
        total_diffs = total_diffs + 1
        local nm, visA = va:match("^([^|]*)|([^|]*)|")
        local _, visB = tostring(vb or ""):match("^([^|]*)|([^|]*)|")
        if visA == "false" and visB == "false" and timer_names[nm] then
          hidden_timer_diffs = hidden_timer_diffs + 1
        elseif visA == "false" and visB == "false" then
          other_hidden_diffs = other_hidden_diffs + 1
          if #sample_diffs < 8 then sample_diffs[#sample_diffs + 1] = { stage = si, id = id, a = va, b = vb } end
        else
          visible_diffs = visible_diffs + 1
          if #sample_diffs < 8 then sample_diffs[#sample_diffs + 1] = { stage = si, id = id, a = va, b = vb } end
        end
      end
    end
  end
  print(string.format("EQUIV %s | stages=%d nodes=%d total=%d visibleDiffs=%d otherHiddenDiffs=%d hiddenTimerDeferred=%d",
    label, #stages, nodes_per, #stages * nodes_per, visible_diffs, other_hidden_diffs, hidden_timer_diffs))
  if #sample_diffs > 0 then
    for i = 1, #sample_diffs do
      local d = sample_diffs[i]
      print("  DIFF stage=" .. d.stage .. " id=" .. d.id .. "\n    A=" .. tostring(d.a) .. "\n    B=" .. tostring(d.b))
    end
  end
  return {
    stages = #stages,
    nodesPerStage = nodes_per,
    totalSnapshots = #stages * nodes_per,
    controlSnapshotDiffs = visible_diffs + other_hidden_diffs,
    visibleControlDiffs = visible_diffs,
    otherHiddenDiffs = other_hidden_diffs,
    hiddenTimerDeferredDiffs = hidden_timer_diffs,
    rawTotalDiffs = total_diffs,
    pass = (visible_diffs == 0 and other_hidden_diffs == 0),
    sampleDiffs = #sample_diffs > 0 and sample_diffs or nil,
  }
end

-- ── 2. 全部 28+ 项故障注入与功能核查专项（含 B1-B10 三版本对照 + 既往 18 项回归）──
local checks = {}
local function record(name, res)
  checks[name] = res
  if res.pass then
    print(string.format("CHECK %-42s | PASS", name))
  else
    print(string.format("CHECK %-42s | FAIL | %s", name, to_json(res)))
  end
end

-- B1：第 25 帧向 root 挂入 raycastTarget=false 新按钮 late.custom.btn，推进 100 帧
do
  local function test_b1(sp)
    local s = make_sandbox(sp)
    s:step(25)
    local root = s.find("root")
    local btn = s.new_node(980001, "late.custom.btn")
    btn._raw._ray = false
    btn._raw._parent = root
    root._raw._kids[#root._raw._kids + 1] = btn
    s:step(150)
    local _, ad = s:get_murdoku()
    return { ray = btn._raw._ray, scans = ad._ray and ad._ray.scans or 0, done = ad._ray and ad._ray.done or false }
  end
  local r742, r747, r748 = test_b1(p742), test_b1(p747), test_b1(p748)
  record("b1_late_raycast_after_f20", {
    pass = (r742.ray == true and r747.ray == false and r748.ray == true and r748.done == true),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B2：set_property("raycast", false) 首项 raycastTarget 抛错时后两项照常关闭且返回 false
do
  local function test_b2(sp)
    local fail_ray = false
    local s = make_sandbox(sp, {
      hooks = {
        prop_set = function(c, k)
          if fail_ray and c._raw._name == "home.shop" and k == "raycastTarget" then error("inj_ray_err") end
        end,
      },
    })
    s:step(10)
    local _, ad = s:get_murdoku()
    local btn = ad:find("home.shop")
    btn._raw._ray, btn._raw._blk, btn._raw._intr = true, true, true
    fail_ray = true
    local ok = ad:set_property("home.shop", "raycast", false)
    fail_ray = false
    return { ok = ok, ray = btn._raw._ray, blk = btn._raw._blk, intr = btn._raw._intr }
  end
  local r742, r747, r748 = test_b2(p742), test_b2(p747), test_b2(p748)
  record("b2_set_prop_raycast_isolation", {
    pass = (r742.blk == false and r742.intr == false
      and r747.blk == true and r747.intr == true
      and r748.ok == false and r748.blk == false and r748.intr == false),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B3a：set_property("visible", true) 在 SetActive 抛错时仍成功 SetVisible(true)
do
  local function test_b3(sp)
    local fail_act = false
    local s = make_sandbox(sp, {
      hooks = {
        set_act = function(c)
          if fail_act and c._raw._name == "home.shop" then error("inj_act_err") end
        end,
      },
    })
    s:step(10)
    local _, ad = s:get_murdoku()
    local btn = ad:find("home.shop")
    btn._raw._visible, btn._raw._active = false, false
    fail_act = true
    local ok = ad:set_property("home.shop", "visible", true)
    fail_act = false
    return { ok = ok, vis = btn._raw._visible }
  end
  local r742, r747, r748 = test_b3(p742), test_b3(p747), test_b3(p748)
  record("b3_set_prop_visible_active_isolation", {
    pass = (r742.vis == true and r747.vis == false and r748.ok == true and r748.vis == true),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B3b：help_visible 与 Tutorial:_visible 在 SetVisible/SetActive 异常隔离验证
do
  local function test_b3_vis_err(sp)
    local fail_vis = false
    local s = make_sandbox(sp, {
      hooks = {
        set_vis = function(c)
          if fail_vis and c._raw._name == "home.shop" then error("inj_vis_err") end
        end,
      },
    })
    s:step(10)
    local _, ad = s:get_murdoku()
    local btn = ad:find("home.shop")
    btn._raw._visible = false
    fail_vis = true
    local ok = ad:set_property("home.shop", "visible", true)
    fail_vis = false
    return { ok = ok, vis = btn._raw._visible }
  end
  local r747, r748 = test_b3_vis_err(p747), test_b3_vis_err(p748)
  record("b3_help_and_tut_visible_isolation", {
    pass = (r747.ok == true and r748.ok == false and r748.vis == false),
    v747 = r747, v748 = r748,
  })
end

-- B4a：confirm 确认条打开期间 stage 被抬升，hit.ok 立即复位保持在顶层
do
  local function test_b4a(sp)
    local resets = 0
    local s = make_sandbox(sp, {
      hooks = {
        last_sib = function(c)
          if c._raw._name == "hit.ok" then resets = resets + 1 end
        end,
      },
    })
    s:step(15)
    s:send_action({ action = "levelselect" }); s:step(10)
    s:send_action({ action = "pick_level", id = "case_001" }); s:step(15)
    s:send_action({ action = "submit" }); s:step(5)
    resets = 0
    local stage = s.find("stage")
    local hit_ok = s.find("hit.ok")
    stage:SetAsLastSibling()
    s:step(70)
    local above = (hit_ok:GetSiblingIndex() > stage:GetSiblingIndex())
    return { resets = resets, above = above }
  end
  local r742, r747, r748 = test_b4a(p742), test_b4a(p747), test_b4a(p748)
  record("b4_confirm_bar_stay_on_top", {
    pass = (r742.above == true and r747.above == false and r748.above == true and r748.resets >= 70),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B4b：退出弹窗打开首帧 block640.modal:SetAsLastSibling 抛错，观测随后 10 帧立即重试置顶
do
  local function test_b4b(sp)
    local first_err = true
    local tries = 0
    local s = make_sandbox(sp, {
      hooks = {
        last_sib = function(c)
          if c._raw._name == "block640.modal" then
            tries = tries + 1
            if first_err then
              first_err = false
              error("inj_modal_sib_err")
            end
          end
        end,
      },
    })
    s:step(15)
    s:send_action({ action = "levelselect" }); s:step(10)
    s:send_action({ action = "pick_level", id = "case_001" }); s:step(15)
    tries = 0
    s:send_action({ action = "back_confirm" })
    s:step(1) -- 首帧触发报错
    local after1 = tries
    s:step(10)
    return { after1 = after1, retriesIn10 = tries - after1 }
  end
  local r742, r747, r748 = test_b4b(p742), test_b4b(p747), test_b4b(p748)
  record("b4_modal_block_err_next_frame_retry", {
    pass = (r742.retriesIn10 >= 1 and r747.retriesIn10 == 0 and r748.retriesIn10 >= 1),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B5a：同根替换 util:_bind 按钮 clues.help627.hit（切首页再点继续回同关）
do
  local function test_b5a(sp)
    local s = make_sandbox(sp)
    s:step(25)
    s:send_action({ action = "levelselect" }); s:step(15)
    s:send_action({ action = "pick_level", id = "case_001" }); s:step(25)
    local old_btn = s.find("clues.help627.hit")
    assert(old_btn and old_btn._raw._parent, "missing clues.help627.hit")
    local parent = old_btn._raw._parent
    local new_btn = s.new_node(981001, "clues.help627.hit")
    new_btn._raw._ray = false
    new_btn._raw._parent = parent
    local ks = parent._raw._kids
    for i = 1, #ks do if ks[i] == old_btn then ks[i] = new_btn; break end end
    s:send_action({ action = "home" }); s:step(20)
    s:send_action({ action = "continue" }); s:step(30)
    local clicked = new_btn:FireClick()
    return { ray = new_btn._raw._ray, clicked = clicked }
  end
  local r747, r748 = test_b5a(p747), test_b5a(p748)
  record("b5_same_root_util_bind_help627", {
    pass = (r747.ray == false and r747.clicked == false and r748.ray == true and r748.clicked == true),
    v747 = r747, v748 = r748,
  })
end

-- B5b：同根替换动态棋盘格 cell.1.2（切首页再点继续回同关）
do
  local function test_b5b(sp)
    local s = make_sandbox(sp)
    s:step(25)
    s:send_action({ action = "levelselect" }); s:step(15)
    s:send_action({ action = "pick_level", id = "case_001" }); s:step(25)
    local stage = s.find("stage")
    local old_cell = stage:GetChild("cell.1.2")
    assert(old_cell, "missing stage/cell.1.2")
    local new_cell = s.clone_node(old_cell, nil)
    new_cell._raw._name = "cell.1.2"
    new_cell._raw._ray = false
    new_cell._raw._parent = stage
    local ks = stage._raw._kids
    for i = 1, #ks do if ks[i] == old_cell then ks[i] = new_cell; break end end
    s:send_action({ action = "home" }); s:step(20)
    s:send_action({ action = "continue" }); s:step(30)
    local clicked = new_cell:FireClick()
    return { ray = new_cell._raw._ray, clicked = clicked }
  end
  local r747, r748 = test_b5b(p747), test_b5b(p748)
  record("b5_same_root_dynamic_cell_rebind", {
    pass = (r747.clicked == false and r748.ray == true and r748.clicked == true),
    v747 = r747, v748 = r748,
  })
end

-- B6：选关页稳态后异步把 select.card.1.title.text 改为 24 字长标题，30 帧内自动缩字号
do
  local function test_b6(sp)
    local s = make_sandbox(sp)
    s:step(20)
    s:send_action({ action = "levelselect" }); s:step(45)
    local t1 = s.find("select.card.1.title")
    local before = t1._raw._fontSize
    t1._raw._text = "这是一段非常长的异步回写选关标题用来检验自动缩小字号"
    s:step(30)
    return { before = before, after = t1._raw._fontSize }
  end
  local r742, r747, r748 = test_b6(p742), test_b6(p747), test_b6(p748)
  record("b6_select_card_async_text_refit", {
    pass = (r742.after < r742.before and r747.after == r747.before and r748.after < r748.before and math.abs(r748.after - r742.after) < 0.01),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B7：剪枝容器下 grp653.static.1.art641.game 与新增动态子控件 econ.ui742/econ.custom748 均可找到
do
  local function test_b7(sp)
    local s = make_sandbox(sp)
    s:step(20)
    local M, ad = s:get_murdoku()
    local cur = M.current()
    -- 触发 _name_idx 构建
    ad:find("nonexistent.probe.748")
    -- 在 econ.ui742 下动态挂入不在 STATIC_PATH_655 也不匹配 shop736/bag741 前缀的子控件
    local econ = s.find("econ.ui742")
    local dyn = s.new_node(982001, "econ.custom748.badge")
    dyn._raw._parent = econ
    econ._raw._kids[#econ._raw._kids + 1] = dyn
    local g1_ad = ad:find("grp653.static.1.art641.game") ~= nil
    local g1_ct = cur.controller:_find_by_name("grp653.static.1.art641.game") ~= nil
    local g2_ad = ad:find("econ.custom748.badge") == dyn
    local g2_ct = cur.controller:_find_by_name("econ.custom748.badge") == dyn
    return { grpAd = g1_ad, grpCtrl = g1_ct, dynAd = g2_ad, dynCtrl = g2_ct, idxNodes = ad._name_idx_nodes or 0 }
  end
  local r742, r747, r748 = test_b7(p742), test_b7(p747), test_b7(p748)
  record("b7_pruned_container_lookup_and_typos", {
    pass = (r742.grpAd and r747.grpAd == false and r748.grpAd and r748.grpCtrl and r748.dynAd and r748.dynCtrl and r748.idxNodes < r747.idxNodes),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B8：forcing 60 帧窗口内即使 c.visible 已等于目标值（tpl-container 已为 false / 关内 cell.1.2 已为 true）仍强制调用 SetVisible
do
  local function test_b8(sp)
    local calls = 0
    local watching = false
    local s = make_sandbox(sp, {
      hooks = {
        set_vis = function(c, v)
          if watching and c._raw._name == "tpl-container" and v == false then calls = calls + 1 end
        end,
      },
    })
    s:step(70) -- 度过首页 forcing 窗口
    local tc = s.find("tpl-container")
    tc._raw._visible = false
    s:send_action({ action = "levelselect" })
    s:step(1)
    tc._raw._visible = false
    watching = true
    s:step(5)
    watching = false
    return { forcedSetVis = calls }
  end
  local r742, r747, r748 = test_b8(p742), test_b8(p747), test_b8(p748)
  record("b8_forcing_60f_force_write", {
    pass = (r742.forcedSetVis >= 5 and r747.forcedSetVis == 0 and r748.forcedSetVis >= 5),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B9a：enable_cursor 中 right 容器在初始化时缺席、延迟至第 130 帧挂载，748 绝不放弃且挂回后 showCursor=true
do
  local function test_b9a(sp)
    local removed_right, root_ref
    local s = make_sandbox(sp, {
      before_init = function(ctx)
        root_ref = ctx.find("root")
        removed_right = ctx.find("right")
        local ks = root_ref._raw._kids
        for i = 1, #ks do if ks[i] == removed_right then table.remove(ks, i); break end end
        removed_right._raw._showCursor = false
      end,
    })
    s:step(130)
    local _, ad = s:get_murdoku()
    local done_before = ad._cursor and ad._cursor.done or false
    -- 第 130 帧挂回 right
    root_ref._raw._kids[#root_ref._raw._kids + 1] = removed_right
    s:step(80)
    return { doneBefore = done_before, showCursor = removed_right._raw._showCursor, doneAfter = ad._cursor and ad._cursor.done or false }
  end
  local r742, r747, r748 = test_b9a(p742), test_b9a(p747), test_b9a(p748)
  record("b9_cursor_late_right_recovery", {
    pass = (r742.doneBefore == false and r742.showCursor == true
      and r747.doneBefore == true and r747.showCursor == false
      and r748.doneBefore == false and r748.showCursor == true and r748.doneAfter == true),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B9b：教程 td.l1.board 首帧缺席、次帧挂回后，furniture_done 不整代锁死
do
  local function test_b9b(sp)
    local tdl1_ref, board_ref
    local s = make_sandbox(sp, {
      before_init = function(ctx)
        tdl1_ref = ctx.find("td.l1")
        board_ref = tdl1_ref:GetChild("td.l1.board")
        local ks = tdl1_ref._raw._kids
        for i = 1, #ks do if ks[i] == board_ref then table.remove(ks, i); break end end
      end,
    })
    s:step(65) -- 触发教程预热
    -- 从 OnUpdate upvalue 拿到 tick_tutorial -> tutorial_inst
    local tut_inst
    local function find_up(fn, target, depth)
      if type(fn) ~= "function" or depth > 4 then return nil end
      local i = 1
      while true do
        local nm, val = debug.getupvalue(fn, i)
        if not nm then break end
        if nm == target then return val end
        if type(val) == "function" then
          local r = find_up(val, target, depth + 1)
          if r ~= nil then return r end
        end
        i = i + 1
      end
      return nil
    end
    tut_inst = find_up(s.env.OnUpdate, "tutorial_inst", 0)
    local inst = tut_inst and tut_inst["l1"]
    assert(inst, "missing tutorial_inst.l1")
    inst:_ensure_furniture(1)
    local done_missing = inst:furniture_done()
    -- 挂回 td.l1.board
    tdl1_ref._raw._kids[#tdl1_ref._raw._kids + 1] = board_ref
    local _, ad = s:get_murdoku()
    ad.clock = (ad.clock or 0) + 1.0
    inst:_ensure_furniture(1)
    local done_after = inst:furniture_done()
    return { doneMissing = done_missing, doneAfter = done_after, made = inst._furn_made or 0 }
  end
  local r742, r747, r748 = test_b9b(p742), test_b9b(p747), test_b9b(p748)
  record("b9_tutorial_board_late_furniture", {
    pass = (r742.doneMissing == false and r747.doneMissing == true and r748.doneMissing == false),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- B10：离树但仍可读 name=="root" 的旧根句柄被替换，ad:drop_lookup 后 ad:find 必须命中新根
do
  local function test_b10(sp)
    local s = make_sandbox(sp)
    s:step(15)
    local _, ad = s:get_murdoku()
    local old_root = s.find("root")
    local old_shop = ad:find("home.shop")
    local new_root = s.clone_node(old_root, nil)
    -- 替换 roots[i]，且 old_root 仍保持可读 name=="root"
    for i = 1, #s.roots do
      if s.roots[i] == old_root then s.roots[i] = new_root; break end
    end
    ad:drop_lookup("home.shop")
    local hit = ad:find("home.shop")
    local new_shop = new_root:GetChild("home"):GetChild("home.shop")
    return { hitNew = (hit == new_shop), hitOld = (hit == old_shop) }
  end
  local r742, r747, r748 = test_b10(p742), test_b10(p747), test_b10(p748)
  record("b10_detached_readable_root_cache", {
    pass = (r742.hitNew == true and r747.hitOld == true and r748.hitNew == true and r748.hitOld == false),
    v742 = r742, v747 = r747, v748 = r748,
  })
end

-- ── 既有 14 项核心回归专项（zone1-4 + r2 全部 10 项）────────────────────────
-- zone1: hex.back 与确认条联动
do
  local s = make_sandbox(p748)
  s:step(15); s:send_action({ action = "levelselect" }); s:step(10)
  s:send_action({ action = "pick_level", id = "case_001" }); s:step(15)
  s:send_action({ action = "submit" }); s:step(5)
  local M = s:get_murdoku()
  local sub_pend = M.current().controller.pending ~= nil
  s:send_action({ action = "back_confirm" }); s:step(5)
  local exit_open = M.current().controller.modal ~= nil and M.current().controller.modal.kind == "exit_menu"
  record("zone1_hex_back_confirm", { pass = (sub_pend and exit_open), sub_pend = sub_pend, exit_open = exit_open })
end

-- zone2: pcall 异常注入不崩
do
  local s = make_sandbox(p748, {
    hooks = { prop_get = function() error("inj_boom") end },
  })
  local ok = pcall(function() s:step(5) end)
  record("zone2_pcall_guard", { pass = ok == true })
end

-- zone3: root 句柄失效触发切屏重建
do
  local s = make_sandbox(p748)
  s:step(15)
  local _, ad = s:get_murdoku()
  local g0 = ad._lookup_gen or 0
  local old_root = s.find("root")
  local new_root = s.clone_node(old_root, nil)
  for i = 1, #s.roots do if s.roots[i] == old_root then s.roots[i] = new_root; break end end
  s:send_action({ action = "levelselect" }); s:step(10)
  local g1 = ad._lookup_gen or 0
  record("zone3_root_rebuild_fallback", { pass = (g1 > g0), genBefore = g0, genAfter = g1 })
end

-- zone4: 关内 face 点亮与 x 70% 自愈（按当前格宽自适应 70%）
do
  local s = make_sandbox(p748)
  s:step(15); s:send_action({ action = "levelselect" }); s:step(10)
  s:send_action({ action = "pick_level", id = "case_001" }); s:step(35)
  local stage = s.find("stage")
  local c12 = stage:GetChild("cell.1.2")
  local content = c12:GetChild("content")
  local expect_x = c12._raw._w * 0.7
  local face = s.new_node(983001, "face"); face._raw._visible = false; face._raw._parent = content; content._raw._kids[#content._raw._kids + 1] = face
  local x = content:GetChild("x"); x._raw._w, x._raw._h = 120, 120
  s:step(130)
  record("zone4_face_and_x70", {
    pass = (face._raw._visible == true and math.abs(x._raw._w - expect_x) < 0.5),
    faceVis = face._raw._visible, xw = x._raw._w, xh = x._raw._h, expect = expect_x,
  })
end

-- r2 P1-1a: 同根替换 home.shop 切屏返回
do
  local s = make_sandbox(p748)
  s:step(25)
  local home = s.find("home")
  local old_shop = home:GetChild("home.shop")
  local new_shop = s.new_node(984001, "home.shop")
  new_shop._raw._ray = false; new_shop._raw._parent = home
  for i = 1, #home._raw._kids do if home._raw._kids[i] == old_shop then home._raw._kids[i] = new_shop; break end end
  s:send_action({ action = "levelselect" }); s:step(15)
  s:send_action({ action = "home" }); s:step(15)
  local clicked = new_shop:FireClick(); s:step(5)
  local M = s:get_murdoku()
  record("r2_p1_1_same_root_btn_replace", {
    pass = (new_shop._raw._ray == true and clicked == true and M.current().controller.screen == "shop"),
    ray = new_shop._raw._ray, clicked = clicked, screen = M.current().controller.screen,
  })
end

-- r2 P1-1b: 同根替换 home.shop（首屏稳态后）原地不动 <= 2s 由保活自动换绑并开射线
do
  local s = make_sandbox(p748)
  s:step(180) -- 等首屏射线完全收敛，纯测试 2s 保活闭环
  local home = s.find("home")
  local old_shop = home:GetChild("home.shop")
  local new_shop = s.new_node(984002, "home.shop")
  new_shop._raw._ray = false; new_shop._raw._parent = home
  for i = 1, #home._raw._kids do if home._raw._kids[i] == old_shop then home._raw._kids[i] = new_shop; break end end
  local ready_f = -1
  for f = 1, 140 do
    s:step(1)
    if new_shop._raw._ray == true and #(new_shop._raw._listeners[1] or {}) > 0 and ready_f < 0 then
      ready_f = f; break
    end
  end
  local clicked = new_shop:FireClick(); s:step(5)
  local M = s:get_murdoku()
  record("r2_p1_1_same_root_btn_idle_wait", {
    pass = (ready_f > 0 and ready_f <= 130 and clicked == true and M.current().controller.screen == "shop"),
    readyFrame = ready_f, clicked = clicked,
  })
end

-- r2 P1-2: 线索灰层写失败后玩家原地不动自动重试
do
  local fail_once = true
  local s = make_sandbox(p748, {
    hooks = {
      prop_set = function(c, k)
        if fail_once and c._raw._name == "gray" and k == "raycastTarget" then
          fail_once = false; error("inj_gray_err")
        end
      end,
    },
  })
  s:step(15); s:send_action({ action = "levelselect" }); s:step(10)
  s:send_action({ action = "pick_level", id = "case_001" }); s:step(10)
  local M = s:get_murdoku()
  local ctrl = M.current().controller
  local item = s.new_node(985001, "clue_item_test")
  local gray = s.new_node(985002, "gray"); gray._raw._ray, gray._raw._blk, gray._raw._intr = true, true, true
  gray._raw._parent = item; item._raw._kids[1] = gray
  ctrl:_grid_disable_gray_raycast(item, 1, 1)
  local rec_f = -1
  for f = 1, 45 do
    s:step(1)
    if gray._raw._ray == false and gray._raw._blk == false and gray._raw._intr == false then rec_f = f; break end
  end
  record("r2_p1_2_gray_retry_idle_no_scroll", {
    pass = (rec_f > 0 and gray._raw._ray == false and gray._raw._blk == false and gray._raw._intr == false),
    recoveredFrame = rec_f,
  })
end

-- r2 P1-3: enable_raycast 局部子树取子抛错后不提前收敛，次趟定向补扫恢复
do
  local fail_home = true
  local s = make_sandbox(p748, {
    hooks = {
      get_kids = function(c)
        if fail_home and c._raw._name == "home" then error("inj_home_kids_err") end
      end,
    },
  })
  local home = s.find("home")
  local nb = s.new_node(986001, "home.extra.btn"); nb._raw._ray = false; nb._raw._parent = home; home._raw._kids[#home._raw._kids + 1] = nb
  s:step(25)
  local _, ad = s:get_murdoku()
  local done_err = ad._ray and ad._ray.done or false
  fail_home = false
  s:step(25)
  local ray_after = nb._raw._ray
  s:step(160)
  record("r2_p1_3_raycast_partial_err_recovery", {
    pass = (done_err == false and ray_after == true and ad._ray.done == true),
    doneAfterErr = done_err, rayAfter = ray_after, doneAfterRec = ad._ray.done,
  })
end

-- r2 P1-4: 隐藏子树遇错重新入队静止自动补藏
do
  local fail_n = 2
  local s = make_sandbox(p748, {
    hooks = {
      set_vis = function(c, v)
        if fail_n > 0 and c._raw._name == "home.shop" and v == false then
          fail_n = fail_n - 1; error("inj_hide_err")
        end
      end,
    },
  })
  s:step(15)
  local shop = s.find("home.shop")
  shop._raw._visible = true
  s:send_action({ action = "levelselect" })
  s:step(1)
  local v1 = shop._raw._visible
  s:step(25)
  record("r2_p1_4_hidden_subtree_err_requeue", {
    pass = (v1 == true and shop._raw._visible == false),
    visAfter1 = v1, visAfterWait = shop._raw._visible,
  })
end

-- r2 P2-1: cur_vis 修复后对已隐藏容器重复隐藏 0 GetChildren
do
  local s = make_sandbox(p748)
  s:step(15); s:send_action({ action = "levelselect" }); s:step(15)
  local _, ad = s:get_murdoku()
  s:reset_stats()
  ad:set_property("home", "visible", false)
  ad:enforce_hidden_subtrees()
  local dirty = ad._subtree_dirty_ids ~= nil and ad._subtree_dirty_ids["home"] == true
  record("r2_p2_1_cur_vis_dedup_active", {
    pass = (dirty == false and s.stats.get_kids == 0),
    dirtyAfterRedundantHide = dirty, getKids = s.stats.get_kids,
  })
end

-- r2 P2-2: 商城读接口暂缺不锁死签名，恢复后回正 (0,0)
do
  local hide_getter = true
  local ignore_pos = true
  local s = make_sandbox(p748, {
    hooks = {
      hide_get_pos = function(c) return hide_getter and c._raw._name == "econ.ui742" end,
      set_pos = function(c)
        if ignore_pos and c._raw._name == "econ.ui742" then return false end
      end,
    },
  })
  local ui = s.find("econ.ui742")
  ui._raw._px, ui._raw._py = 250, -180
  s:step(15); s:send_action({ action = "shop" }); s:step(25)
  hide_getter = false; ignore_pos = false
  s:step(30)
  record("r2_p2_2_econ_missing_getter_no_lock", {
    pass = (math.abs(ui._raw._px) < 1 and math.abs(ui._raw._py) < 1),
    px = ui._raw._px, py = ui._raw._py,
  })
end

-- r2 P2-3: 格子晚挂 content(box) 自动修正尺寸
do
  local s = make_sandbox(p748)
  s:step(15); s:send_action({ action = "levelselect" }); s:step(10)
  s:send_action({ action = "pick_level", id = "case_001" }); s:step(20)
  local stage = s.find("stage")
  local c12 = stage:GetChild("cell.1.2")
  local old_content = c12:GetChild("content")
  -- 摘掉 content 模拟缺 box，挂 face/x 在 c12 下让 746 误判齐全
  local ks = c12._raw._kids
  for i = 1, #ks do if ks[i] == old_content then table.remove(ks, i); break end end
  s:step(70)
  old_content._raw._w, old_content._raw._h = 200, 200
  ks[#ks + 1] = old_content
  local rec_f = -1
  for f = 1, 130 do
    s:step(1)
    if old_content._raw._w ~= 200 then rec_f = f; break end
  end
  record("r2_p2_3_late_box_recovery", {
    pass = (rec_f > 0 and old_content._raw._w ~= 200),
    recoveredFrame = rec_f, bw = old_content._raw._w, bh = old_content._raw._h,
  })
end

-- r2 P2-4: 选关翻页失败项隔离重试不破主布局
do
  local fail_next = true
  local bg_touches = 0
  local watch_bg = false
  local s = make_sandbox(p748, {
    hooks = {
      set_pos = function(c)
        if fail_next and c._raw._name == "hit.select.next" then error("inj_next_err") end
        if watch_bg and c._raw._name == "adapt715r.background" then bg_touches = bg_touches + 1 end
      end,
      set_vis = function(c)
        if watch_bg and c._raw._name == "adapt715r.background" then bg_touches = bg_touches + 1 end
      end,
    },
  })
  s:step(15); s:send_action({ action = "levelselect" }); s:step(25)
  fail_next = false; watch_bg = true
  s:step(25)
  watch_bg = false
  local M = s:get_murdoku()
  local hit_next = s.find("hit.select.next")
  hit_next:FireClick(); s:step(10)
  record("r2_p2_4_pager_fail_isolated_retry", {
    pass = (bg_touches == 0 and M.current().controller.select_page == 2),
    extraMainLayoutTouches = bg_touches, page = M.current().controller.select_page,
  })
end

-- r2 Wait: 商城移除 econ.shop736.s0 停留 40 秒，0 次 GetChildren，挂回 <= 2.1s 恢复
do
  local s = make_sandbox(p748)
  s:step(180); s:send_action({ action = "shop" }); s:step(20)
  local ui = s.find("econ.ui742")
  local s0 = ui:GetChild("econ.shop736.s0")
  local _, ad = s:get_murdoku()
  ad:drop_lookup("econ.shop736.s0")
  local ks = ui._raw._kids
  for i = 1, #ks do if ks[i] == s0 then table.remove(ks, i); break end end
  s:send_action({ action = "home" }); s:step(10)
  s:send_action({ action = "shop" }); s:step(20)
  s:reset_stats()
  s:step(2400) -- 40s
  local gk40 = s.stats.get_kids
  ks[#ks + 1] = s0
  local rec_f = -1
  for f = 1, 180 do
    s:step(1)
    if ad.controls["econ.shop736.s0"] == s0 then rec_f = f; break end
  end
  record("r2_wait_shop_missing_fast_recover", {
    pass = (gk40 == 0 and rec_f > 0 and rec_f <= 130),
    getKids40s = gk40, recoverFrames = rec_f, recoverSec = rec_f / 60,
  })
end

-- 执行端到端 32 阶段全量快照差分：742v12 vs 748 与 747 vs 748
local eq742 = run_32_stage_equivalence(p742, p748, "742v12 vs 748")
local eq747 = run_32_stage_equivalence(p747, p748, "747 vs 748")

-- ── 3. 六代（742v12 / 743 / 745 / 746 / 747 / 748）5 轮统一采样基准 ──────────
local function calc_stats(arr)
  local n = #arr
  local sorted = {}
  local sum = 0
  for i = 1, n do sorted[i] = arr[i]; sum = sum + arr[i] end
  table.sort(sorted)
  local mean = sum / n
  local vsum = 0
  for i = 1, n do local d = arr[i] - mean; vsum = vsum + d * d end
  local med = (n % 2 == 1) and sorted[(n + 1) / 2] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2
  return { mean = mean, median = med, std = math.sqrt(vsum / n), min = sorted[1], max = sorted[n] }
end

local function pct(sorted, p)
  local idx = math.max(1, math.min(#sorted, math.ceil(#sorted * p)))
  return sorted[idx]
end

local function run_scenario(sp, name)
  collectgarbage("collect")
  collectgarbage("stop")
  local s = make_sandbox(sp)
  local frame_ms = {}
  local max_frame_kids = 0

  local function measure_frames(n)
    for _ = 1, n do
      local k0 = s.stats.get_kids
      local t0 = os.clock()
      s:step(1)
      local dt_ms = (os.clock() - t0) * 1000
      frame_ms[#frame_ms + 1] = dt_ms
      local dk = s.stats.get_kids - k0
      if dk > max_frame_kids then max_frame_kids = dk end
    end
  end

  local t_start, kb_start
  if name == "cold_boot" then
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    measure_frames(30)
  elseif name == "steady_home" then
    s:step(180)
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    measure_frames(300)
  elseif name == "steady_select" then
    s:step(180); s:send_action({ action = "levelselect" }); s:step(90)
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    measure_frames(300)
  elseif name == "steady_level" then
    s:step(180); s:send_action({ action = "levelselect" }); s:step(30)
    s:send_action({ action = "pick_level", id = "case_001" }); s:step(90)
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    measure_frames(300)
  elseif name == "steady_shop" then
    s:step(180); s:send_action({ action = "shop" }); s:step(90)
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    measure_frames(300)
  elseif name == "screen_switch_burst" then
    s:step(90)
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    local seq = {
      { action = "levelselect" }, { action = "home" }, { action = "shop" }, { action = "bag" },
      { action = "home" }, { action = "levelselect" }, { action = "pick_level", id = "case_001" },
      { action = "home" }, { action = "continue" }, { action = "levelselect" },
      { action = "shop" }, { action = "home" },
    }
    for i = 1, #seq do
      s:send_action(seq[i])
      measure_frames(15)
    end
  elseif name == "nav_flow" then
    s:step(30)
    s:reset_stats()
    kb_start = collectgarbage("count")
    t_start = os.clock()
    s:send_action({ action = "levelselect" }); measure_frames(20)
    s:send_action({ action = "select_page", delta = 1 }); measure_frames(15)
    s:send_action({ action = "select_page", delta = -1 }); measure_frames(15)
    s:send_action({ action = "pick_level", id = "case_001" }); measure_frames(30)
    s:send_action({ action = "cell", r = 1, c = 1, phase = "click" }); measure_frames(15)
    s:send_action({ action = "submit" }); measure_frames(15)
    s:send_action({ action = "confirm_no" }); measure_frames(10)
    s:send_action({ action = "home" }); measure_frames(20)
    s:send_action({ action = "shop" }); measure_frames(20)
    s:send_action({ action = "bag" }); measure_frames(20)
    s:send_action({ action = "home" }); measure_frames(20)
  end

  local total_ms = (os.clock() - t_start) * 1000
  local alloc_kb = math.max(0, collectgarbage("count") - kb_start)
  collectgarbage("restart")
  collectgarbage("collect")

  table.sort(frame_ms)
  return {
    ms = total_ms,
    allocKB = alloc_kb,
    api = s.stats.api,
    getKids = s.stats.get_kids,
    getChild = s.stats.get_child,
    setVis = s.stats.set_vis,
    setAct = s.stats.set_act,
    setTransform = s.stats.set_pos + s.stats.set_scale + s.stats.set_size,
    lastSib = s.stats.last_sib,
    pcallN = s.stats.pcall_n,
    redundantVis = s.stats.redundant_vis,
    redundantPos = s.stats.redundant_pos,
    redundantScale = s.stats.redundant_scale,
    maxFrameKids = max_frame_kids,
    p50 = pct(frame_ms, 0.50),
    p95 = pct(frame_ms, 0.95),
    p99 = pct(frame_ms, 0.99),
    fmax = frame_ms[#frame_ms] or 0,
  }
end

local bench = {}
if not skip_bench then
  local versions = {
    { key = "v742v12", path = p742 },
    { key = "v743",    path = p743 },
    { key = "v745",    path = p745 },
    { key = "v746",    path = p746 },
    { key = "v747",    path = p747 },
    { key = "v748",    path = p748 },
  }
  local scenarios = {
    "cold_boot", "steady_home", "steady_select", "steady_level", "steady_shop",
    "screen_switch_burst", "nav_flow",
  }
  local ROUNDS = 5
  for _, sc in ipairs(scenarios) do
    bench[sc] = {}
    for _, ver in ipairs(versions) do
      local ms_list, kb_list, p95_list, p99_list, fmax_list = {}, {}, {}, {}, {}
      local last_r
      for r = 1, ROUNDS do
        local res = run_scenario(ver.path, sc)
        ms_list[r] = res.ms
        kb_list[r] = res.allocKB
        p95_list[r] = res.p95
        p99_list[r] = res.p99
        fmax_list[r] = res.fmax
        last_r = res
      end
      bench[sc][ver.key] = {
        rounds = ROUNDS,
        ms = calc_stats(ms_list),
        allocKB = calc_stats(kb_list),
        p95 = calc_stats(p95_list),
        p99 = calc_stats(p99_list),
        fmax = calc_stats(fmax_list),
        api = last_r.api,
        getKids = last_r.getKids,
        getChild = last_r.getChild,
        setVis = last_r.setVis,
        setAct = last_r.setAct,
        setTransform = last_r.setTransform,
        lastSib = last_r.lastSib,
        pcallN = last_r.pcallN,
        redundantVis = last_r.redundantVis,
        redundantPos = last_r.redundantPos,
        redundantScale = last_r.redundantScale,
        maxFrameKids = last_r.maxFrameKids,
      }
    end
    local b = bench[sc]
    print(string.format(
      "BENCH %-20s | ms: %.1f->%.1f->%.1f->%.1f->%.1f->%.1f | kids: %d->%d->%d->%d->%d->%d | api: %d->%d",
      sc, b.v742v12.ms.mean, b.v743.ms.mean, b.v745.ms.mean, b.v746.ms.mean, b.v747.ms.mean, b.v748.ms.mean,
      b.v742v12.getKids, b.v743.getKids, b.v745.getKids, b.v746.getKids, b.v747.getKids, b.v748.getKids,
      b.v747.api, b.v748.api))
  end
end

local all_pass = eq742.pass and eq747.pass
for _, v in pairs(checks) do
  if not v.pass then all_pass = false end
end

local report = {
  schema = "748-e2e-v1",
  candidateSha256 = cand_sha,
  pass = all_pass,
  equivalence742vs748 = eq742,
  equivalence747vs748 = eq747,
  checks = checks,
  bench = bench,
}

local f = assert(io.open(out_json, "wb"))
f:write(to_json(report))
f:close()
print("VERIFY_ALL_PASS=" .. tostring(all_pass))
if not all_pass then os.exit(2) end
