local FORCE_LEVEL = nil
if print then print("[murdoku] ===== 构建标记 v731 / 2026-11-17 / 全线索保留复核与第四五七关修订 =====") end
local Murdoku, Qianxing
local LOAD_ERR = nil
local ok1 = pcall(function() Murdoku = require("main") end)
if not ok1 then LOAD_ERR = "main" end
if LOAD_ERR == nil then
  local ok2 = pcall(function() Qianxing = require("engine_adapter_qianxing") end)
  if not ok2 then LOAD_ERR = "adapter" end
end
local adapter   = nil
local started   = false
local tree_dumped = false
local RETRY_INTERVAL = 0.5
local RETRY_LIMIT    = 60       
local retry_elapsed  = 0
local retry_tries    = 0
local function raw_mark(v)
  if game == nil or game.GetClientUIRoots == nil then return false end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then return false end
  local function walk(c, d, want)
    if c == nil or d > 12 then return nil end
    local n
    pcall(function() n = c.name end)
    if n == want then return c end
    local kids
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do
        local hit = walk(kids[i], d + 1, want)
        if hit ~= nil then return hit end
      end
    end
    return nil
  end
  local names = { "cell.1.1", "tray.A", "board" }
  for i = 1, #names do
    for k = 1, #roots do
      local t = walk(roots[k], 1, names[i])
      if t ~= nil and t.SetSizeDelta ~= nil then
        if pcall(function() t:SetSizeDelta(v, v) end) then return true end
      end
    end
  end
  return false
end
local BEACON = { OnInit = 300, OnStart = 380 }
local function beacon(a, v)
  if a == nil then return end
  if a.cells_beacon == false then return end
  if a.cfg ~= nil and a.cfg.cells_beacon == false then return end
  if a._cells_beacon_button ~= nil then
    pcall(function() a:_cells_beacon_button(v) end)
  end
  if a._cells_signal ~= nil then
    pcall(function() a:_cells_signal(v) end)
  end
end
local function enable_update()
  if script == nil then
    if printerr then printerr("[murdoku] 拿不到 script 对象，OnUpdate 可能不会被调用") end
    return false
  end
  local fn = script.EnableUpdate
  if fn == nil then
    if printerr then printerr("[murdoku] script:EnableUpdate 不存在，OnUpdate 可能不会被调用") end
    return false
  end
  local ok = pcall(function() script:EnableUpdate(true) end)
  if not ok then
    if printerr then printerr("[murdoku] script:EnableUpdate 失败，OnUpdate 可能不会被调用") end
    return false
  end
  return true
end
local CANVAS_EXPECT = { w = 1600, h = 900 }
local canvas_checked = false
local function num(v)
  if type(v) ~= "number" then return tostring(v) end
  if v == math.floor(v) then return string.format("%.0f", v) end
  return string.format("%.2f", v)
end
local function check_canvas()
  if canvas_checked then return end
  canvas_checked = true
  pcall(function()
    if game == nil or game.GetUICanvasSize == nil then return end
    local ok, w, h = pcall(game.GetUICanvasSize)
    if not ok or type(w) ~= "number" or type(h) ~= "number" then
      if print then print("[murdoku] 拿不到画布尺寸：" .. tostring(w) .. " / " .. tostring(h)) end
      return
    end
    local same = (math.abs(w - CANVAS_EXPECT.w) < 0.6) and (math.abs(h - CANVAS_EXPECT.h) < 0.6)
    if same then
      if print then
        print("[murdoku] ===== 构建标记 v731 / 2026-11-17 / 全线索保留复核与第四五七关修订 =====")
      end
      if print then print("[murdoku] 画布 " .. num(w) .. "×" .. num(h) .. "，与设计一致") end
    else
      if printerr then
        printerr("[murdoku] 画布是 " .. num(w) .. "×" .. num(h)
          .. "，但界面坐标按 " .. num(CANVAS_EXPECT.w) .. "×" .. num(CANVAS_EXPECT.h)
          .. " 设计 —— 位置会偏。请按实际画布重算 docs/控件坐标表-1600x900.md，"
          .. "或改 ui_controller.lua 的 M.CANVAS / M.SCALE。")
      end
    end
  end)
end
local function build_adapter()
  if LOAD_ERR ~= nil then error("模块加载失败：" .. tostring(LOAD_ERR)) end
  adapter = Qianxing.new({
    apply_rect = false,
    verbose    = false,
    prefab_of = {
      ["action.back.hexbg"] = 1073742333,
      ["action.redo.hexbg"] = 1073742333,
      ["action.hint.hexbg"] = 1073742333,
      ["home.panel"]   = 1073742337,
      ["select.panel"] = 1073742337,
    },
    parent_of = {
      ["action.back.hexbg"] = "action.back",
      ["hex.back"]   = "root",
      ["hex.submit"] = "root",
      ["hex.redo"]   = "root",
      ["hex.undo"]   = "root",
      ["hex.hint"]   = "root",
      ["hex.ok"]     = "root",
      ["hex.no"]     = "root",
      ["hit.back"]   = "root",
      ["hit.submit"] = "root",
      ["hit.redo"]   = "root",
      ["hit.undo"]   = "root",
      ["hit.hint"]   = "root",
      ["hit.ok"]     = "root",
      ["hit.no"]     = "root",
      ["home.panel"]   = "home",
      ["select.panel"] = "select",
    },
    cells_beacon = false,
    auto_create = false,    
    prefab_icon = 1073742357,
    text_editor_first = {
      "home.select", "home.continue", "home.shop", "home.bag",
      "econ.shop.title", "econ.shop.wallet", "econ.shop.currency_id", "econ.shop.item", "econ.shop.price", "econ.shop.status",
      "econ.bag.title", "econ.bag.wallet", "econ.bag.currency_id", "econ.bag.item", "econ.bag.price", "econ.bag.status",
      "econ.shop.buy", "econ.shop.back", "econ.bag.back",
      "settle.btn",
      "modal.exit", "modal.save", "modal.settle", "modal.cancel",
      "result.next", "result.exit", "result.home", "result.settle",
      "clues.up", "clues.down",
      "win.1", "win.2", "win.3", "win.4",
      "result.title.1", "result.title.2", "result.title.3",
      "result.msg.1", "result.msg.2", "result.msg.3",
    },
    widgets     = false,    
    stage = {
      prefab = 1073742330,    
      parent = "stage",
      selbar = "selbar",      
    },
    cells = {
      prefab   = 1073741876,
      ruler    = 12,            
      gap      = 4,             
      face_image = 100001,
      probe    = "cell.1.1",
      parent   = "stage",
      rows     = 7,             
      cols     = 7,
      debug_signal = false,
      auto_scan = true,
      edge_thickness = 10,
      door_length_ratio = 0.44,
      edge_overlap = 4,
      edge_extra_len = 4,
      edge_fit_log = true,
      layer_order = {
        "face",
        "hint",
        "obj",
        "obj2", "obj3", "obj4", "obj5", "obj6",
        "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",
        "rug_layer", "furn",
        "portrait",
        "wall.up", "wall.down", "wall.left", "wall.right",
        "door.up", "door.down", "door.left", "door.right",
        "x",
        "note",
      },
    },
    respect_editor_rect = true,
    furn_prim_prefab = 1073746302,
    furn_prim_cap = 260,
    furn_tpl_prefab = {
      chair    = 1073747134,
      plant    = 1073747135,
      plant_2  = 1073753953,  
      statue   = 1073747136,
      table    = 1073747137,
      table_h2 = 1073747138,
      table_v2 = 1073747139,
      shelf    = 1073747140,
      rug      = 1073747149,
      rug_2    = 1073748252,
      rug_3    = 1073749968,
      rug_4    = 1073760711,
      rug_5    = 1073760734,
    },
    furn_parent = "fart.furn",    
    furn_tpl_base = 108,
    furn_scale = 0.93,
    furn_scale_by_kind = { rug = 0.82, rug_2 = 0.82, rug_3 = 0.82, statue = 0.85 },
    furn_scale_axis_by_kind = {
      rug_2 = { x = 0.93, y = 0.762 },
      rug_3 = { x = 0.762, y = 0.93 },
      rug_4 = { x = 1, y = 1 },
      rug_5 = { x = 1, y = 1 },
    },
    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 },
                       rug_4 = { 216, 216 }, rug_5 = { 216, 216 },
                       table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },
    tpl_probe = false,
    tpl_probe_ref_name = "furn",       
    tpl_probe_plant_src = 1073747081,    
    tpl_probe_nest_src = 1073747096,     
    tpl_probe_parent = "board",          
    obj_art = {
      table = {    
        { id = 100001, color = 0xFF4A3524, w = 0.9, h = 0.64 },
        { id = 100001, color = 0xFFD4CCA0, w = 0.82, h = 0.56 },
        { id = 100001, color = 0xFFE8E2C0, w = 0.72, h = 0.46 },
      },
      chair = {    
        { id = 106053, color = 0xFF4A3A2A, w = 0.74, h = 0.76, dy = 0.04 },
        { id = 106053, color = 0xFFF2EBD4, w = 0.66, h = 0.5, dy = 0.13 },
        { id = 100001, color = 0xFFCBBE97, w = 0.62, h = 0.2, dy = -0.16 },
      },
      carpet = {    
        { id = 100001, color = 0xFF9C8A63, w = 0.92, h = 0.92 },
        { id = 100001, color = 0xFFDCCBAA, w = 0.84, h = 0.84 },
      },
      plant = {    
        { id = 100002, color = 0xFF3E7D3A, w = 0.64, h = 0.52, dy = -0.08 },
        { id = 106053, color = 0xFF8A6A48, w = 0.32, h = 0.24, dy = 0.26 },
        { id = 100002, color = 0xFF58A046, w = 0.34, h = 0.26, dy = -0.2 },
      },
      shelf = {    
        { id = 100001, color = 0xFF4A3524, w = 0.82, h = 0.66 },
        { id = 100001, color = 0xFFB4874F, w = 0.76, h = 0.6 },
        { id = 100001, color = 0xFF4A2E17, w = 0.68, h = 0.07, dy = -0.05 },
      },
      statue = {    
        { id = 100001, color = 0xFF4E4E56, w = 0.54, h = 0.24, dy = 0.28 },
        { id = 105090, color = 0xFFC9C9D2, w = 0.6, h = 0.5, dy = 0.02 },
        { id = 100002, color = 0xFFE2E2E8, w = 0.14, h = 0.1, dy = -0.22 },
      },
    },
    debug_key   = false,    
    debug_image = false,    
    debug_event = false,    
    tray_parent = "tray",
    key_control = "root",
    key_control_fallbacks = { "board", "cell.1.1", "topbar" },
  })
  do
    local c = adapter.cfg
    c.prefab_of = c.prefab_of or {}
    c.parent_of = c.parent_of or {}
    for i = 1, 18 do
      local id = "clue." .. i .. ".bg"
      c.prefab_of[id] = 1073742333
      c.parent_of[id] = "clues"
    end
  end
  Murdoku.prepare(adapter)
  __murdoku_debug = { adapter = adapter, Murdoku = Murdoku, beacon = beacon }
  return adapter
end
local function safe_on_start(tag)
  local f = Murdoku.on_start
  if f == nil then
    if printerr then printerr("[murdoku] on_start 不存在（模块没加载完整）") end
    return nil
  end
  local retry_screen = "home"
  if FORCE_LEVEL ~= nil then retry_screen = nil end
  local ok, a, b = pcall(f, FORCE_LEVEL, {
    adapter      = adapter,
    restore_save = (FORCE_LEVEL == nil),
    screen       = retry_screen,
  })
  if not ok then
    if printerr then
      printerr("[murdoku] ⚠️ on_start 抛错了（" .. tostring(tag) .. "）：" .. tostring(a))
    end
    return nil
  end
  local self = a
  if self == nil then
    if printerr then
      printerr("[murdoku] ⚠️ on_start 返回 nil（" .. tostring(tag)
        .. "）—— 没有抛错，说明它内部主动放弃了。"
        .. "常见原因：控件树缺关键控件（比如棋盘容器 / 参照格子）时就 return nil。")
    end
    return nil
  end
  if print then
    print("[murdoku] ✅ on_start 成功（" .. tostring(tag) .. "）：level="
      .. tostring(self.level and self.level.id) .. "  screen=" .. tostring(self.screen or "(关卡内)"))
  end
  return self
end
local function probe_or_dump(final)
  if adapter == nil then return false end
  local ready = false
  pcall(function()
    if adapter:find("board") ~= nil or adapter:find("cell.1.1") ~= nil then
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
  if ready then return true end
  if tree_dumped then return false end
  local n = 0
  if adapter.count_names ~= nil then
    pcall(function() n = adapter:count_names(6, 400) or 0 end)
  end
  if n == 0 and not final then
    if print then
      print("[murdoku] 控件树还没就绪（OnInit/OnStart 阶段是空的，属正常）→ 稍后重试")
    end
    return false
  end
  tree_dumped = true
  if printerr then
    printerr("[murdoku] 就绪判据未满足（board/cell.1.1/stage/home 都不在），下面把「脚本能看到的客户端控件」全列出来")
  end
  if adapter.dump_names ~= nil then
    pcall(function() n = adapter:dump_names(6, 400) or 0 end)
  elseif game ~= nil and game.PrintClientUITree ~= nil then
    pcall(game.PrintClientUITree)
    n = -1      
  end
  if printerr then
    if n == 0 then
      printerr("[murdoku] 客户端控件树是**空的**（0 个节点）。控件没被创建出来，"
        .. "最可能是下面三条之一：")
      printerr("[murdoku]   ① 界面布局没被【职业】引用 —— 官方硬性要求，"
        .. "入口：战斗预设 → 职业 → 选择布局；或 界面控件组管理 → 界面布局 → 参数配置 → 【打开玩家编辑】")
      printerr("[murdoku]   ② 控件做在了【界面控件组库】里 —— 官方原话："
        .. "界面控件组库中制作的元件实际游玩时并不显示，必须【添加至界面布局】")
      printerr("[murdoku]   ③ 控件没放进【客户端控件容器】里面（或容器没勾【激活】/【可见】）")
    elseif n > 0 then
      printerr("[murdoku] 树里有 " .. tostring(n) .. " 个节点，但里面没有 board / cell.1.1。"
        .. "对照上面那份名单看名字差在哪（脚本是**精确匹配**的：大小写、空格、自动后缀都算不一样）。")
      if adapter.near_names ~= nil then
        for _, want in ipairs({ "root", "board", "cell.1.1" }) do
          local near = nil
          pcall(function() near = adapter:near_names(want, 5) end)
          if type(near) == "table" and #near > 0 then
            printerr("[murdoku]   近似 " .. want .. " 的名字有："
              .. table.concat(near, " / ") .. "  ← 注意大小写、空格、括号后缀")
          end
        end
      end
    else
      printerr("[murdoku] 已把客户端控件树打到日志里，对照 docs/控件坐标表-1600x900.md 看名字。")
    end
  end
  return false
end
local keyboard_bound = false
local KEY_SPEC = {
  "KeyboardCraftspersonKey36Down", "KeyboardCraftspersonKey37Down",
  "KeyboardCraftspersonKey38Down", "KeyboardCraftspersonKey39Down",
  "KeyboardCraftspersonKey1Down",  "KeyboardCraftspersonKey2Down",
  "KeyboardCraftspersonKey3Down",  "KeyboardCraftspersonKey4Down",
  "KeyboardCraftspersonKey5Down",  "KeyboardCraftspersonKey6Down",
  "KeyboardCraftspersonKey7Down",  "KeyboardCraftspersonKey8Down",
  "KeyboardCraftspersonKey9Down",  "KeyboardCraftspersonKey10Down",
  "KeyboardInteractKeyDown",        
  "KeyboardJumpKeyDown",            
  "KeyboardDropKeyDown",            
  "KeyboardCraftspersonKey42Down",  
  "KeyboardOpenShortcutWheelKeyDown",  
  "KeyboardCharacterSkill1KeyDown",    
  "KeyboardCharacterSkill3KeyDown",    
  "KeyboardCraftspersonKey12Down",     
  "KeyboardCraftspersonKey13Down",     
  "KeyboardCraftspersonKey15Down",     
}
local function bind_keyboard_once(where)
  if adapter == nil or keyboard_bound then return false end
  local ok = pcall(function()
    local n, note = adapter:bind_keys(KEY_SPEC)
    if n > 0 then
      keyboard_bound = true
      if print then
        print("[murdoku] 键盘快捷键已绑定 " .. n .. " 个键（PC 可用，移动端忽略）"
          .. "　[" .. tostring(note) .. "]"
          .. (where and where ~= "OnInit" and ("　via " .. where) or ""))
      end
    elseif where == "OnInit" then
      if print then
        print("[murdoku] 键盘快捷键暂未绑定（OnInit 时控件树还没就绪，稍后会自动补绑）")
      end
    else
      if print then
        print("[murdoku] 键盘快捷键没绑上（不影响鼠标/触摸操作）：" .. tostring(note))
        print("[murdoku]   → 想用键盘的话：在 cfg.key_control / key_control_fallbacks 里"
          .. "换一个控件名（必须是**预设按钮**这类支持按键事件的控件）")
      end
    end
  end)
  return ok and keyboard_bound
end
local tutorial_mod_state = nil    
local tutorial_inst = {}          
local tutorial_seen = {}          
local TUT_MASK_BITS = { home = 1, l1 = 2, l2 = 4 }
local function tutorial_mask()
  local mask = 0
  for tag, bit in pairs(TUT_MASK_BITS) do
    if tutorial_seen[tag] then mask = mask + bit end
  end
  return mask
end
local function apply_tutorial_mask(mask)
  mask = tonumber(mask) or 0
  for tag, bit in pairs(TUT_MASK_BITS) do tutorial_seen[tag] = (mask % (bit * 2)) >= bit end
end
local TUT_SETS = {
  home = { tag = "home", root = "td.home", text = "td.home", pages = 1 },
  l1   = { tag = "l1",   root = "td.l1",   text = "td.l1",   pages = 8 },
  l2   = { tag = "l2",   root = "td.l2",   text = "td.l2",   pages = 4 },
}
local TUT_TRIGGER = { home = "home", case_001 = "l1", case_002 = "l2" }
if Murdoku ~= nil then
  Murdoku.get_tutorial_mask = tutorial_mask
  Murdoku.read_tutorial_mask = tutorial_mask
  Murdoku.apply_tutorial_mask = apply_tutorial_mask
end
local function tutorial_module()
  if tutorial_mod_state ~= nil then
    if tutorial_mod_state == false then return nil end
    return tutorial_mod_state
  end
  local ok, mod = pcall(require, "tutorial_ui")
  if not ok or type(mod) ~= "table" or type(mod.new) ~= "function" then
    if printerr then printerr("[murdoku] 教程模块没加载上：" .. tostring(mod)) end
    tutorial_mod_state = false      
    return nil
  end
  tutorial_mod_state = mod
  return mod
end
local function tutorial_instance(spec)
  if spec == nil then return nil end
  local inst = tutorial_inst[spec.tag]
  if inst ~= nil then return inst end
  local mod = tutorial_module()
  if mod == nil or adapter == nil then return nil end
  local ok, made = pcall(function()
    local content = (type(mod.CONTENT) == "table") and mod.CONTENT[spec.tag] or nil
    return mod.new(adapter, { tag = spec.tag, root = spec.root, text = spec.text, pages = spec.pages, content = content })
  end)
  if not ok or type(made) ~= "table" then
    if printerr then printerr("[murdoku] 教程实例建不出来（" .. tostring(spec.tag) .. "）：" .. tostring(made)) end
    return nil
  end
  tutorial_inst[spec.tag] = made
  return made
end
local function tut_visible(name)
  if adapter == nil or name == nil then return false end
  local c = nil
  pcall(function() c = adapter:find(name) end)
  if c == nil then return false end
  local v = nil
  pcall(function() v = c.visible end)
  return v == true
end
local function tutorial_home_visible()
  return tut_visible("home")
end
local TUT_PROBE_NAMES = { "home", "select.card.1", "select.title", "clues", "board" }    
local TUT_PREWARM_AFTER = 60  
local tut_prewarm_frames = 0
local tut_prewarm_done = false
local TUT_STABLE_NEED = 20    
local TUT_KEEP_NEED = 10      
local tut_key_prev = nil
local tut_key_frames = 0
local tut_shown_frames = 0
local tut_key_logged = false  
local tut_miss_frames = {}    
local function tut_key_and_probe()
  local cur = nil
  pcall(function()
    if Murdoku ~= nil and Murdoku.current ~= nil then cur = Murdoku.current() end
  end)
  if adapter ~= nil and adapter.prefetch ~= nil then
    pcall(function() adapter:prefetch(TUT_PROBE_NAMES) end)
  end
  local home  = tut_visible("home")
  local card1 = tut_visible("select.card.1")
  if not card1 then card1 = tut_visible("select.title") end    
  local clues = tut_visible("clues")
  local board = tut_visible("board")
  local scr, id = nil, nil
  if cur ~= nil then
    pcall(function() scr = cur.screen end)
    pcall(function() id = cur.level and cur.level.id end)
  end
  local key = nil
  if cur ~= nil then
    if home then
      key = "home"                        
    elseif card1 then
      key = nil                           
    elseif clues or board then
      if id ~= nil then key = tostring(id) end    
    end
  end
  return key, { home = home, card1 = card1, clues = clues, board = board, scr = scr, id = id }
end
local tut_last_probe = nil
local function current_tut_key()
  local key, probe = tut_key_and_probe()
  tut_last_probe = probe
  return key
end
local help617 = { bound = false, entry_bound = false, close_bound = false, open = false, overlay = false }
local function help_visible(c, v)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c.visible end)
  if actual ~= v then
    pcall(function() if c.SetVisible then c:SetVisible(v) else c.visible = v end end)
  end
  if v then
    local active = nil
    pcall(function() active = c.active end)
    if active ~= true then pcall(function() if c.SetActive then c:SetActive(true) end end) end
  end
end
local function help_write(c, v)
  if c == nil then return end
  pcall(function() if c.SetText then c:SetText(v) else c.text = v end end)
end
local function overlay_open()
  for _, spec in pairs(TUT_SETS) do
    local inst = tutorial_inst[spec.tag]
    if inst ~= nil and inst.open then return true end
  end
  return help617.open == true
end
local HOME_TUTORIAL_CONTROLS = { "home.tutorial627.bg", "home.tutorial627.ring", "home.tutorial627.label", "home.tutorial627.hit" }
local function sync_home_tutorial628(want)
  local c = help617.controls or {}
  local complete = true
  for _, name in ipairs(HOME_TUTORIAL_CONTROLS) do
    if c[name] == nil then c[name] = adapter:find(name) end
    if c[name] == nil then complete = false else help_visible(c[name], want) end
  end
  help617.controls = c
  help617.home_visible = complete and want or nil
end
local function bind_help617()
  if adapter == nil then return end
  local generation = adapter._lookup_gen or 0
  if help617.generation ~= generation then
    if help617.close then help617.close() end
    help617.generation = generation
    help617.bound, help617.entry_bound, help617.close_bound = false, false, false
    help617.controls = {}
    help617.initialized, help617.entry_visible = false, nil
    help617.home_bound, help617.home_visible = false, nil
  end
  if help617.bound and help617.home_bound then return end
  local util = tutorial_instance(TUT_SETS.l1)
  if util == nil then return end
  help617.controls = help617.controls or {}
  local c = help617.controls
  for _, name in ipairs({ "clues.help617", "clues.help627.hit", "home.tutorial627.hit", "help617", "help617.title", "help617.body", "help617.close", "help617.close.hit", "help617.bg" }) do
    if c[name] == nil then c[name] = adapter:find(name) end
  end
  local function close()
    help_visible(c["help617"], false)
    help617.open = false
  end
  help617.close = close
  if not help617.initialized and c["help617"] ~= nil then
    help617.initialized = true
    close()
    for _, name in ipairs({ "help617.title", "help617.body", "help617.close", "help617.close.hit", "help617.bg" }) do help_visible(c[name], true) end
    pcall(function() c["help617"].showCursor = true end)
    pcall(function() c["help617"].disableCursorEventPassthrough = true end)
    pcall(function() c["help617"].disableKeyEventPassthrough = true end)
  end
  if not help617.close_bound and c["help617.close.hit"] ~= nil then
    help617.close_bound = util:_bind("help617.close.hit", close, c["help617.close.hit"])
  end
  if not help617.entry_bound and c["clues.help627.hit"] ~= nil then
    help_visible(c["clues.help617"], true)
    help617.entry_bound = util:_bind("clues.help627.hit", function()
      local cur = Murdoku.current()
      local id = cur and cur.level and cur.level.id
      if not cur or not cur.controller or not id or cur.controller.modal ~= nil or overlay_open() then return end
      if current_tut_key() ~= tostring(id) then return end
      local tag = TUT_TRIGGER[id]
      if tag then
        local inst = tutorial_instance(TUT_SETS[tag])
        if inst then
          inst:init()
          tutorial_seen[tag] = true
          inst:go(1)
          inst:open_ui()
        end
        return
      end
      if c["help617"] == nil or c["help617.body"] == nil then return end
      local yes, no = {}, {}
      for name, obj in pairs((cur.level and cur.level.objects) or {}) do
        local target = obj.occupiable and yes or no
        target[#target + 1] = tostring(name)
      end
      table.sort(yes); table.sort(no)
      help_write(c["help617.title"], (cur.level and cur.level.name or "本关") .. " · 注释")
      help_write(c["help617.body"], "可站人的家具：" .. (#yes > 0 and table.concat(yes, "、") or "本关未配置") .. "。\n\n不可站人的家具：" .. (#no > 0 and table.concat(no, "、") or "本关未配置") .. "。\n\n普通可站空格也可放人；墙体、禁用格及水域不能站人。\n具体家具以本关配置为准。")
      if id == "case_006" then
        help_write(c["help617.body"], "本关七条线索均为真。每行、每列各一人。\n\n先用全部线索求候选格，不预设身份或套人数规则。\n盗窃者说真话时，必须仍有多个可选位置。\n\n盗窃者在老师房间的门相邻房间中；排除盗窃者后，\n该房间的无辜人数必须唯一最多。\n\n椅子、地毯和空格可站；桌子、书架、植物、雕塑不可站。\n旁边指同房间四邻格；上方不要求同列。")
      end
      help617.level = id
      help617.open = true
      help_visible(c["help617"], true)
    end, c["clues.help627.hit"])
  end
  if help617.entry_bound and help617.logged_generation ~= generation then
    help617.logged_generation = generation
  end
  if not help617.home_bound and c["home.tutorial627.hit"] ~= nil then
    help617.home_bound = util:_bind("home.tutorial627.hit", function()
      local cur = Murdoku.current()
      if current_tut_key() ~= "home" or overlay_open() or (cur and cur.controller and cur.controller.modal ~= nil) then return end
      local inst = tutorial_instance(TUT_SETS.home)
      if inst then
        inst:init()
        tutorial_seen.home = true
        inst:go(1)
        inst:open_ui()
      end
    end, c["home.tutorial627.hit"])
  end
  help617.bound = help617.entry_bound and help617.close_bound
end
local hint635_ui={}
local function tick_hint635()
  if not adapter then return end
  local util=tutorial_instance(TUT_SETS.l1)
  if not util then return end
  local gen=adapter._lookup_gen or 0
  if hint635_ui.generation~=gen then hint635_ui={generation=gen,controls={},bound={}} end
  local h=hint635_ui
  local names={"hint635.menu","hint635.result","hint635.menu.bg","hint635.menu.title",
    "hint635.menu.position","hint635.menu.clue","hint635.menu.close",
    "hint635.result.bg","hint635.result.body","hint635.result.close",
    "hint635.menu.position.hit","hint635.menu.clue.hit","hint635.menu.close.hit","hint635.result.close.hit"}
  for _,name in ipairs(names) do
    if not h.controls[name] then
      h.controls[name]=adapter:find(name)
      if h.controls[name] then help_visible(h.controls[name],name~="hint635.menu" and name~="hint635.result") end
    end
  end
  local cur=Murdoku.current()
  local ctrl=cur and cur.controller
  local actions={["hint635.menu.position.hit"]="position",["hint635.menu.clue.hit"]="clue",
    ["hint635.menu.close.hit"]="close",["hint635.result.close.hit"]="close"}
  for name,action in pairs(actions) do
    if not h.bound[name] and h.controls[name] then
      local chosen=action
      h.bound[name]=util:_bind(name,function()
        local c=Murdoku.current()
        if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
      end,h.controls[name])
    end
  end
  if ctrl and (ctrl.screen~=nil or ctrl.modal~=nil or overlay_open()) then ctrl.hint635=nil end
  local state=ctrl and ctrl.hint635
  local signature=state and (state.kind..":"..(state.text or "")) or "closed"
  local used=ctrl and ctrl.core and ctrl.core.hint635_used or {position=0,clue=0}
  signature=signature..":"..tostring(used.position)..":"..tostring(used.clue)
  if h.signature~=signature or h.controller~=ctrl then
    h.signature=signature;h.controller=ctrl
    help_visible(h.controls["hint635.menu"],state~=nil and state.kind=="menu")
    help_visible(h.controls["hint635.result"],state~=nil and state.kind=="message")
    help_write(h.controls["hint635.menu.position"],"揭示选中人物的所在位置（"..tostring(1-used.position).."/1）")
    help_write(h.controls["hint635.menu.clue"],"验证选中线索的真假（"..tostring(2-used.clue).."/2）")
    help_write(h.controls["hint635.result.body"],state and state.text or "")
  end
end
local function tick_tutorial()
  tick_hint635()
  bind_help617()
  if help617.open then
    local cur = Murdoku.current()
    if not cur or not cur.controller or cur.controller.screen ~= nil or cur.controller.modal ~= nil or not cur.level or cur.level.id ~= help617.level then help617.close() end
  end
  if adapter == nil then return end
  if tutorial_module() == nil then return end
  for _, spec in pairs(TUT_SETS) do
    local inst = tutorial_instance(spec)
    if inst ~= nil and not inst.inited then
      pcall(function() inst:init() end)
    end
  end
  local key, probe = nil, nil
  if started then
    key = current_tut_key()           
    probe = tut_last_probe            
  end
  local help_cur = Murdoku.current()
  local help_want = key ~= nil and key ~= "home" and help_cur ~= nil
    and help_cur.controller ~= nil and help_cur.controller.modal == nil and not overlay_open()
  if help617.entry_visible ~= help_want and help617.controls and help617.controls["clues.help617"] then
    help_visible(help617.controls["clues.help617"], help_want)
    help_visible(help617.controls["clues.help627.hit"], help_want)
    help617.entry_visible = help_want
  end
  local home_want = key == "home" and not overlay_open()
    and not (help_cur and help_cur.controller and help_cur.controller.modal ~= nil)
  if help617.home_visible ~= home_want then
    sync_home_tutorial628(home_want)
  end
  local key_changed = (key ~= tut_key_prev)
  if not key_changed then
    tut_key_frames = tut_key_frames + 1
  else
    tut_key_prev = key
    tut_key_frames = 0
    tut_shown_frames = 0
  end
  if print and probe ~= nil and (key_changed or not tut_key_logged) then
    tut_key_logged = true
    print("[tutorial] 触发键 -> " .. tostring(key)
      .. "  (home=" .. tostring(probe.home)
      .. " card1=" .. tostring(probe.card1)
      .. " clues=" .. tostring(probe.clues)
      .. " board=" .. tostring(probe.board)
      .. " scr=" .. tostring(probe.scr) .. ")")
  end
  local want_tag = nil
  if key ~= nil and tut_key_frames >= TUT_STABLE_NEED then want_tag = TUT_TRIGGER[key] end
  for tag, spec in pairs(TUT_SETS) do
    local inst = tutorial_inst[spec.tag]
    if inst ~= nil and inst.inited then
      if want_tag == tag then
        tut_miss_frames[tag] = 0
        if not tutorial_seen[tag] then
          if not inst.open then
            pcall(function() inst:open_ui() end)
          end
          tut_shown_frames = tut_shown_frames + 1
          if tut_shown_frames >= TUT_KEEP_NEED then tutorial_seen[tag] = true end
        end
      else
        tut_miss_frames[tag] = (tut_miss_frames[tag] or 0) + 1
        if inst.open and tut_miss_frames[tag] >= TUT_KEEP_NEED then
          pcall(function() inst:close() end)
          tut_miss_frames[tag] = 0
        end
      end
    end
  end
  if started then
    tut_prewarm_frames = tut_prewarm_frames + 1
    if tut_prewarm_frames >= TUT_PREWARM_AFTER and not key_changed and not tut_prewarm_done then
      local all_done = true
      for _, spec in pairs(TUT_SETS) do
        local inst = tutorial_inst[spec.tag]
        if inst ~= nil and inst.inited and inst.prewarm ~= nil and not inst.open then
          local ok, done = pcall(function() return inst:prewarm(1) end)
          if not (ok and done) then all_done = false; break end
        elseif inst == nil or not inst.inited then
          all_done = false
        end
      end
      tut_prewarm_done = all_done
    end
  end
end
local BLOCK640 = {
  { tag = "confirm", targets = { "hex.ok", "hex.no", "hit.ok", "hit.no" } },
  { tag = "modal", targets = { "modal" } },
  { tag = "home", targets = { "td.home" } },
  { tag = "l1", targets = { "td.l1" } },
  { tag = "l2", targets = { "td.l2" } },
}
local block640_silent655 = setmetatable({}, { __mode = "k" })
local block640_silent_gen655 = -1
-- 689：控件句柄随 _lookup_gen 缓存；只要有一项没找到就退回 688 的逐帧查找，
--       保证首帧 / 控件树重建时绑定不丢失。每帧的显隐、静音、抬层逻辑逐行保持。
local block640_cache = nil
local block640_cache_gen = -1
local function sync_block640()
  if not adapter then return end
  local util = tutorial_instance(TUT_SETS.l1)
  if not util then return end
  local cur = Murdoku.current()
  local ctrl = cur and cur.controller
  local gen = adapter._lookup_gen or 0
  if block640_cache == nil or block640_cache_gen ~= gen then
    local tmp, complete = {}, true
    for _, spec in ipairs(BLOCK640) do
      local name = "block640." .. spec.tag
      local panel, hit = adapter:find(name), adapter:find(name .. ".hit")
      tmp[#tmp + 1] = { spec = spec, name = name, panel = panel, hit = hit }
      if panel == nil or hit == nil then complete = false end
    end
    if complete then block640_cache, block640_cache_gen = tmp, gen
    else block640_cache, block640_cache_gen = nil, gen end
  end
  local cache = block640_cache
  if cache == nil then
    cache = {}
    for _, spec in ipairs(BLOCK640) do
      local name = "block640." .. spec.tag
      cache[#cache + 1] = { spec = spec, name = name,
        panel = adapter:find(name), hit = adapter:find(name .. ".hit") }
    end
  end
  for _, e in ipairs(cache) do
    local spec, name, panel, hit = e.spec, e.name, e.panel, e.hit
    local want = false
    if spec.tag == "modal" then
      want = ctrl ~= nil and ctrl.modal ~= nil
      -- 654: 兼容旧退出状态；独立选关页不启用旧式选关遮罩。
      if want and ctrl.modal.kind == "levelselect" and (ctrl.screen == "select" or ctrl.screen == "home") then want = false end
    elseif spec.tag == "confirm" then want = ctrl ~= nil and ctrl.pending ~= nil
    else local inst = tutorial_inst[spec.tag]; want = inst ~= nil and inst.open == true end
    -- 689：_bind 内部首行即「已绑定则立即返回」，收进未绑定分支后行为等价，
    --       但稳态帧不再创建 5 个空闭包、也不再重复调用。
    if hit ~= nil and not util.bound[hit] then
      help_visible(hit, true)
      util:_bind(name .. ".hit", function() end, hit)
    end
    want = not not want
    if hit ~= nil then
      local _g655 = adapter._lookup_gen or 0
      if block640_silent_gen655 ~= _g655 then
        block640_silent655 = setmetatable({}, { __mode = "k" })
        block640_silent_gen655 = _g655
      end
      if not block640_silent655[hit] then
        pcall(function() if hit.clickAudioId ~= 0 then hit.clickAudioId = 0 end end)
        block640_silent655[hit] = true
      end
    end
    help_visible(panel, want)
    if want then
      pcall(function() panel.showCursor = true end)
      pcall(function() panel.disableCursorEventPassthrough = true end)
      pcall(function() panel:SetAsLastSibling() end)
      for _, target in ipairs(spec.targets) do
        local c = adapter:find(target)
        if c then pcall(function() c:SetAsLastSibling() end) end
      end
    end
  end
end
local art641_cache = nil
local art641_gen = nil
local art641_screen = false
local function sync_art641()
  if not adapter then return end
  local cur = Murdoku.current()
  local ctrl = cur and cur.controller
  if not ctrl then return end
  local screen = ctrl.screen or "game"
  local gen = adapter._lookup_gen or 0
  if art641_cache == nil or art641_gen ~= gen then
    art641_cache = {}
    for _, key in ipairs({"home", "select", "game"}) do
      art641_cache[key] = adapter:find("art641." .. key)
    end
    art641_gen = gen
    art641_screen = false
  end
  if art641_screen ~= screen then
    for _, key in ipairs({"home", "select", "game"}) do
      help_visible(art641_cache[key], screen == key)
    end
    art641_screen = screen
    do
      local gp = adapter:find("art657.grid.reuse")
      if gp ~= nil then
        help_visible(gp, screen == "home" or screen == "game")
        -- ★ 687：art657.grid.reuse 一套 48 层被 home / game 两屏共享。680 为让关卡内
        --   网格纸跟随棋盘下移，把全部子层各 -30 ⇒ 首页被连带额外下移（656 设计位 -5 → 686 -45.5）。
        --   静态层保持不动（game 屏位置不变），只给 home/select 的父容器 +40.5 把首页抬回设计位；
        --   game 分支 (105,46) 逐字不动 ⇒ 两处真正分开调整。
        local dx, dy = 0, 40.5
        if screen == "game" then dx, dy = 105, 46 end
        pcall(function() gp:SetAnchoredPosition(dx, dy) end)
      end
    end
  end
end
local SETTLE_ART_TINT = {
  {"art647.select.settle.shadow", 0x66000000, 0x66000000},
  {"art647.select.settle.yellow.shadow", 0x66000000, 0x66000000},
  {"art647.select.settle.yellow.edge", 0xff6b2b12, 0xff2c1208},
  {"art647.select.settle.yellow", 0xffffd133, 0xff685816},
  {"art647.select.settle.outline", 0xff1e1210, 0xff0c0807},
  {"art647.select.settle.outline.tri.top", 0xff1e1210, 0xff0c0807},
  {"art647.select.settle.outline.tri.bottom", 0xff1e1210, 0xff0c0807},
  {"art647.select.settle.ribbon", 0xff825447, 0xff35231f},
  {"art647.select.settle.ribbon.tri.top", 0xff825447, 0xff35231f},
  {"art647.select.settle.ribbon.tri.bottom", 0xff825447, 0xff35231f},
  {"art647.home.settle.shadow", 0x66000000, 0x66000000},
  {"art647.home.settle.yellow.shadow", 0x66000000, 0x66000000},
  {"art647.home.settle.yellow.edge", 0xff6b2b12, 0xff2c1208},
  {"art647.home.settle.yellow", 0xffffd133, 0xff685816},
  {"art647.home.settle.outline", 0xff1e1210, 0xff0c0807},
  {"art647.home.settle.outline.tri.top", 0xff1e1210, 0xff0c0807},
  {"art647.home.settle.outline.tri.bottom", 0xff1e1210, 0xff0c0807},
  {"art647.home.settle.ribbon", 0xff825447, 0xff35231f},
  {"art647.home.settle.ribbon.tri.top", 0xff825447, 0xff35231f},
  {"art647.home.settle.ribbon.tri.bottom", 0xff825447, 0xff35231f},
}
local art_color_cache655 = setmetatable({}, { __mode = "k" })
local art_color_gen655 = -1
local function write_art_color650(c, key, want)
  if c == nil then return end
  local gen = (adapter and adapter._lookup_gen) or 0
  if art_color_gen655 ~= gen then
    art_color_cache655 = setmetatable({}, { __mode = "k" })
    art_color_gen655 = gen
  end
  local slot = art_color_cache655[c]
  if slot == nil then slot = {}; art_color_cache655[c] = slot end
  if slot[key] == want then return end
  local actual = nil
  pcall(function() actual = c[key] end)
  if actual ~= want then pcall(function() c[key] = want end) end
  slot[key] = want
end
local art647_tint_key = nil
local art647_last_key, art647_last_gen = nil, -1
local function sync_art647()
  local cur = Murdoku.current()
  local ad = cur and cur.adapter
  local ctrl = cur and cur.controller
  if not ad or not ctrl then return end
  -- 689：can_settle 有解锁副作用，必须逐帧调用；状态未变且控件树未重建时跳过染色。
  --       仅当 21 个控件全部找到并完成染色后才固化，首帧 / 重建帧不会漏染。
  local ready = ctrl:can_settle()
  local gen = ad._lookup_gen or 0
  local key = (ready and "1" or "0") .. "|" .. tostring(ctrl.screen or "")
  art647_tint_key = key
  if key == art647_last_key and gen == art647_last_gen then return end
  local cd = ad:find("settle.btn.countdown")
  write_art_color650(cd, "textColor", 0x00FFFFFF)
  local complete = cd ~= nil
  for _, e in ipairs(SETTLE_ART_TINT) do
    local c = ad:find(e[1])
    if c == nil then complete = false end
    write_art_color650(c, "imageColor", ready and e[2] or e[3])
  end
  if complete then art647_last_key, art647_last_gen = key, gen end
end
local art649_last_key = nil
local art649_ready = false
local function sync_art649_page()
  local cur = Murdoku.current()
  local ad = cur and cur.adapter
  local ctrl = cur and cur.controller
  if not ad or not ctrl then return end
  local lv = ctrl.opts and ctrl.opts.levels
  local list = {}
  if type(lv) == "function" then list = lv() or {}
  elseif type(lv) == "table" then list = lv end
  local pages = math.max(1, math.ceil(#list / 4))
  local page = tonumber(ctrl.select_page) or 1
  if page < 1 then page = 1 end
  if page > pages then page = pages end
  -- 689：页态 + 控件树代数未变且控件已就绪时跳过重复染色；翻页立即重算。
  local key = pages .. "|" .. page .. "|" .. tostring(ad._lookup_gen or 0)
  if key == art649_last_key and art649_ready then return end
  local dl = ad:find("art647.select.diamond.left")
  local dr = ad:find("art647.select.diamond.right")
  local NORMAL, DIM = 0xFFFFFFFF, 0x7FFFFFFF
  write_art_color650(dl, "imageColor", (page > 1) and NORMAL or DIM)
  write_art_color650(dr, "imageColor", (page < pages) and NORMAL or DIM)
  art649_last_key = key
  art649_ready = dl ~= nil and dr ~= nil
end
function OnInit()
  Murdoku.reset_settle_session()
  pcall(enable_update)
  local ok, err = pcall(build_adapter)
  if not ok then
    if printerr then
      printerr("[murdoku] OnInit 在【创建适配器】这一步失败：" .. tostring(err)
        .. " —— 游戏逻辑不会启动（脚本本身是跑起来了，问题在这一步）")
    end
    if LOAD_ERR == "main" then raw_mark(250)
    elseif LOAD_ERR ~= nil then raw_mark(260) end
    return
  end
  pcall(check_canvas)
  pcall(function() beacon(adapter, BEACON.OnInit) end)
  bind_keyboard_once("OnInit")
  if print then print("[murdoku] OnInit done（适配器已就绪，等 OnStart 开局）") end
end
function OnStart()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  if adapter == nil then
    if printerr then printerr("[murdoku] OnStart 发现适配器为空，补建一个") end
    pcall(build_adapter)
  end
  pcall(function() beacon(adapter, BEACON.OnStart) end)
  if not probe_or_dump(false) then
    if print then print("[murdoku] 控件还没就绪，交给 OnUpdate 重试") end
    return
  end
  bind_keyboard_once("OnStart")
  local start_screen = "home"
  if FORCE_LEVEL ~= nil then start_screen = nil end
  local self = safe_on_start("首次")
  if self then
    started = true
    if print then print("[murdoku] started: " .. tostring(self.level and self.level.id)) end
  end
end
function OnEnable() end
function OnDisable() end
function OnUpdate(dt)
  Murdoku.advance_settle_session(dt)
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  pcall(tick_tutorial)
  if not started then
    retry_elapsed = retry_elapsed + (dt or 0)
    if retry_elapsed >= RETRY_INTERVAL then
      retry_elapsed = 0
      retry_tries = retry_tries + 1
      if retry_tries > RETRY_LIMIT then
        probe_or_dump(true)
        if printerr then
          printerr("[murdoku] 等不到客户端控件，放弃自动开局"
            .. "（检查客户端控件容器是否【激活且可见】、界面布局是否被【职业】引用）")
        end
        started = true       
      else
        if adapter == nil then pcall(build_adapter) end
        if probe_or_dump(false) then
          bind_keyboard_once("重试")
          local retry_screen = "home"
          if FORCE_LEVEL ~= nil then retry_screen = nil end
          local self = safe_on_start("重试")
          if self then
            started = true
            if print then print("[murdoku] started (retry " .. retry_tries .. ")") end
          end
        end
      end
    end
    return
  end
  Murdoku.on_update(dt)
  sync_art641()
  sync_art647()
  sync_art649_page()
  sync_block640()
end
function OnLevelUpdate(dt) end
function OnDestroy()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  Murdoku.on_destroy()
  if print then print("[murdoku] destroyed") end
end