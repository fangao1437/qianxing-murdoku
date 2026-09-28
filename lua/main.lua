--[[----------------------------------------------------------------------------
  main.lua —— 奇域入口：把 引擎核心 / 操作框架 / 适配层 串起来  v1.0.0

  入口由 lua/entry_client_script.lua 的官方生命周期回调调用：
    OnInit()      → Murdoku.prepare(adapter)
    OnStart()     → Murdoku.on_start(level_id, opts)
    OnUpdate(dt)  → Murdoku.on_update(dt)
    OnDestroy()   → Murdoku.on_destroy()

  信号参数采用**有序数组**（官方 ServerSignal 要求按顺序 Add*），
  收信号时按 engine_adapter_qianxing.SIGNAL_SCHEMA 还原成字典。
--]]--

local Core      = require("murdoku_core")
local UIC       = require("ui_controller")
local Adapters  = require("engine_adapter")
local Qianxing  = require("engine_adapter_qianxing")

local Levels = require("levels.init")

local Murdoku = {}
Murdoku.__index = Murdoku
Murdoku.VERSION = "1.0.0"

local current = nil            -- 当前会话
local prepared_adapter = nil   -- OnInit 里建好的适配器
local signals_registered = false

function Murdoku.prepare(adapter)
  prepared_adapter = adapter
  return adapter
end

function Murdoku.current() return current end

-- ★★ 2026-09-28 新增：**统一渲染入口** —— 渲染完必然重做一次"行标/列标对齐"。
--
-- 为什么不能只在开机做一次：
--   `controller:render()` 会把 ruler 标签按**规划里的静态坐标**推下去
--   （那是设计期算的，和运行时 `cell_geometry` 算出的格子位置本来就对不上）。
--   所以每次渲染都会**把我对齐好的位置覆盖回去** ——
--   开机那一次对齐只在一瞬间有效，下一次状态变化就白做了。
--   ⇒ 把"渲染 + 对齐"绑成一个动作，就不会漏。
--
-- 证据：真机日志里开机那次 `核对：Δ=0` 是对的，而模拟器在若干次渲染后测出 Δ=16。
function Murdoku.render(force)
  if current == nil then return end
  current.controller:render(current.adapter, force)
  local a = current.adapter
  if a ~= nil and a.apply_ruler_layout ~= nil then
    local core = current.controller.core
    a:apply_ruler_layout((core and core.rows) or 5, (core and core.cols) or 5)
  end
end

----------------------------------------------------------------------------
-- 开局
----------------------------------------------------------------------------

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

  -- 关卡清单交给界面层（界面层不认识 Levels 模块，只认这份数据）
  local level_list = {}
  for _, lv in ipairs(Levels.all()) do
    level_list[#level_list + 1] = {
      id = lv.id, name = lv.name, difficulty = lv.difficulty,
    }
  end

  -- ⚠️ 先声明再赋值：下面几个回调要在闭包里引用 controller 自己，
  --    而 `local x = f(...)` 里的 x 在构造器内还不存在（会变成全局 nil）。
  local controller

  -- 切到别的关卡：**不要再放一遍开屏教程**（玩家已经在游戏里了）
  local function start_other(id, why)
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.skip_intro = true
    o.debug = opts.debug
    local ok = Murdoku.start(id, o)
    if not ok then
      controller.toast = "切关失败：" .. tostring(why or id)
      controller.dirty = true
      Murdoku.flush_effects()
    end
    return ok
  end

  controller = UIC.new(core, {
    debug = opts.debug,
    skip_intro = opts.skip_intro,
    levels = level_list,
    -- 选关：直接从面板跳过去
    on_pick_level = function(id)
      if id ~= level.id then start_other(id) end
    end,
    -- 返回列表：打开选关面板
    on_back = function()
      controller.modal = { kind = "levelselect" }
      controller.dirty = true
      Murdoku.flush_effects()
    end,
    on_next_level = opts.on_next_level or function()
      local nxt = Levels.next(level.id)
      if nxt then
        start_other(nxt)
      else
        -- 已经是最后一关：给个提示而不是静默无反应
        controller.toast = "已经是最后一关了"
        controller.dirty = true
        Murdoku.flush_effects()
      end
    end,
    on_solved = function(vm)
      -- 破案：把结算数据发给服务器（节点图侧接 关卡结算/排行榜）
      adapter:signal_emit(Qianxing.SIGNALS.SOLVED, {
        tostring(level.id),
        math.floor(vm.hud.time or 0),
        vm.hud.moves or 0,
        vm.hud.failed_accusations or 0,
      })
    end,
  })

  local self = setmetatable({}, Murdoku)
  self.core = core
  self.level = level
  self.adapter = adapter
  self.controller = controller
  self.options = opts
  self.last_tick = 0
  -- 挂在模块上：离线测试（tests/entry_smoke.lua）要直接驱动适配层
  -- 验调色板/染色/墙门。生产环境无副作用，排查时也有用。
  Murdoku.__last = self

  -- 适配层的输入交给控制器，控制器产出特效后原地渲染
  adapter.on_input = function(event)
    controller:on_input(event)
    Murdoku.flush_effects()
  end

  -- 服务器信号（只注册一次）
  if not signals_registered then
    signals_registered = true
    adapter:signal_on(Qianxing.SIGNALS.RESTORE, function(payload)
      Murdoku.restore(payload)
    end)
    adapter:signal_on(Qianxing.SIGNALS.SYNC_STATE, function(payload)
      Murdoku.on_signal("murdoku/sync", payload)
    end)
  end

  -- 读档（本场景内缓存；跨场景由服务器把存档发回来）
  if opts.restore_save then
    local save = adapter:load("murdoku/save/" .. tostring(level.id))
    if type(save) == "table" then
      if save.state_code then
        core:decode_state(save.state_code)
      elseif save.cells then
        core:deserialize(save)
      end
      core:set_elapsed(save.elapsed or 0)
    end
  end

  current = self

  -- ① 先试着由脚本自己打开容器的「显示常驻光标」（门控 ②）。
  --    真机不开放这个字段时会静默失败，届时仍需在编辑器里手勾一次。
  if adapter.enable_cursor then
    local cur = adapter:enable_cursor()
    if cur > 0 and print then
      print("[murdoku] 已由脚本打开 " .. cur .. " 个容器的「显示常驻光标」")
    end
  end

  -- ② 用模板批量补齐棋盘格子（编辑器里已摆好的不会被动；没配 cfg.cells 就什么都不做）
  if adapter.ensure_cells then
    local made = adapter:ensure_cells(core.rows, core.cols)
    if made > 0 and print then
      print("[murdoku] 运行时生成了 " .. made .. " 个格子")
    end
  end

  -- ★ 2026-09-28：**上色名单从规划里取，不再手写**。
  --
  -- 第一版我在适配器里手写了 19 个按钮名，而实际有 35 个 —— 真机日志
  -- `SetImage 成功 19 个` 把这件事暴露出来了：另外 16 个（`action.q.*`、`modal.level.*` …）
  -- **从来没被验证过**。手写名单迟早漏，直接从 `build_layout()` 里筛 `kind == "button"`。
  --
  -- ⚠️ 必须在上面的 `apply_tray_layout` **之前**设好 —— 上色代码目前挂在那个函数里。
  local labels = {}
  do
    local ok, nodes = pcall(function() return controller:build_layout() end)
    if ok and type(nodes) == "table" then
      local list = {}
      for i = 1, #nodes do
        local nd = nodes[i]
        local id = nd.id
        if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") then
          list[#list + 1] = id
        end
      end
      adapter.cfg.btn_list = list
      if print then print("[murdoku] 上色名单（来自规划）：" .. #list .. " 个按钮") end
      -- ★ 顺手把所有按钮的**名字**也收集起来（规划里的 `text`），开机直接写下去。
      --   为什么不信渲染那条路：用户反复反馈名字没配上，而文字**只能靠脚本写**
      --   （存档里不存文字，已用 `ruler.c.1` 验证）。这里走一条**明确、可读回验证**的路径。
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

  -- ★★ 2026-09-28：**用已证明可用的接口直接给按钮写名字**。
  --
  -- 为什么不用 `adapter:apply_button_labels`：我加了那个方法，真机/模拟器日志却显示
  --   `适配器支持 = false`（方法没挂到实例上），而我没在当轮查清原因。
  --   与其赌一个没验证过的入口，不如走 `set_property` —— **那是渲染一直在用、
  --   已经被真机反复验证过的路径**。
  --
  -- 同时把**写回结果读出来**：这样下一次日志能直接告诉我们卡在哪一环
  --   （读到文字 → 写入成功，问题在渲染；读回 nil/空 → 写不进去）。
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
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
          if lb then
            back = lb.text
            fs = lb.fontSize
            fc = lb.fontColor
            vv = lb.visible
          end
        end)
      end
      -- ★★ 2026-09-28：**显式设字号**。
      --
      --   真机日志已经证明 `label.text` **写进去了**（读回 "返回列表" ✅）却看不见 ⇒
      --   问题不在"写"，在"画不出来"。而文本控件最典型的"隐形"原因就是 **fontSize = 0**
      --   （克隆出来的 label 很可能没带字号）。
      --   顺手把 fontSize / fontColor / visible 一起打出来 —— 下一次日志就能确认这个判断，
      --   而不是又靠猜。
      -- ★★ 2026-09-28：**把 label 提到最上层**。
      --
      --   真机日志已经把所有属性都排除干净了：
      --     `读回 返回列表   fontSize=20 fontColor=4294967295(白/不透明) visible=true`
      --   —— 文字、字号、颜色、可见性**全部正确**，屏幕上却一个字都没有。
      --   ⇒ 只可能是**被 `bg` 压住了**。
      --   层级 = 同级子控件的先后顺序，而 `bg` 是我先加、`label` 是后加，
      --   到底谁在上面取决于引擎把"先"解释成上层还是下层 —— 我**不想再赌语义**，
      --   直接用 `SetAsLastSibling()`（官方文档：「数值越大显示层级越高」）**强制** label 到顶。
      if adapter.sub ~= nil then
        pcall(function()
          local lb = adapter:sub(id, "label")
          -- ★★★ 2026-09-28 —— **根因是用户自己找出来的，我前面全查错了方向**：
          --   我给 label 建的高度只有 **20px**，而字号也是 20px
          --   ⇒ **文本框装不下自己的字** ⇒ 文字"存在、可见、颜色正确"却一个像素都画不出来。
          --   我前面查了写入、层级、颜色、图集、克隆体状态 ——
          --   **唯独没想到"容器够不够大"** 这个最朴素的原因。
          --
          --   用户实测：高度改 40、字号缩到 10 就显示了；他建议**加大高度**而不是缩小字号。
          --   这里采纳：高度给 40，字号保持 18（能看清）。
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
            if lb.SetSizeDelta ~= nil then
              pcall(function() lb:SetSizeDelta(bw or 100, 40) end)
            end
            if lb.fontSize ~= nil then lb.fontSize = 18 end
            if lb.SetAsLastSibling ~= nil then pcall(function() lb:SetAsLastSibling() end) end
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
    print(string.format("[murdoku] 按钮名字：写入后读回一致 %d 个，不一致 %d 个（共 %d）", okN, badN, #ids2))
  end

  -- 头像卡按本关实际人数重新摆正（列数会随人数变，编辑器那套只是"最挤的情况"）
  if adapter.apply_tray_layout and controller.tray_layout_canvas then
    local moved = adapter:apply_tray_layout(controller:tray_layout_canvas())
    if moved > 0 and print then
      print("[murdoku] 头像卡已按 " .. moved .. " 人重新排布")
    end
  end

  -- ★ 2026-09-28 新增：**行标 / 列标按格子的实际位置对齐**。
  --
  -- 用户报"列标和行标没与棋盘对齐"。根因是 ruler 标签的位置在**规划时**用设计空间几何算过一遍，
  -- 而格子是**运行时**用 `cell_geometry` 算的 —— 两套数必然对不上。
  -- 这里用格子的真实锚点位置反推标签位置，只信一份数据。
  if adapter.apply_ruler_layout then
    -- ⚠️ 行列数在 `controller.core` 里（控制器自己没有 rows/cols 字段）——
    --    第一版写成 `controller.rows`，取到 nil，靠 `or 5` 兜住了，5×5 恰好蒙对、
    --    但 6×6 / 7×7 就会少摆几个标签。取真实值，别用兜底。
    local core = controller.core
    adapter:apply_ruler_layout((core and core.rows) or 5, (core and core.cols) or 5)
  end

  -- ★ 相交诊断：把"与棋盘相交且显示中"的控件列出来。
  --   用户反复报棋盘上有方块，而我从规划数据分不清"此刻屏幕上是谁" —— 让日志直接说。
  --   ⚠️ 用 `adapter.cfg` 而不是 `cfg` —— 这个位置的 `cfg` 是**后面才声明的 local**，
  --      在这里取到的是 nil（真机/模拟器会报 `attempt to index a nil value (global 'cfg')`）。
  if adapter.diagnose_overlap and adapter.cfg.overlap_diag ~= false then
    adapter:diagnose_overlap()
  end
  -- ③ 参照格子体检：把「cell.1.1 到底配好了没有」一次性讲清楚。
  --    原因：格子能不能看见/点得动，取决于类型、射线、子控件、状态节点、图片类型好几项，
  --    而这些在日志里**原本一点痕迹都没有**，出问题只能靠肉眼猜。
  --    搭界面阶段默认开（cfg.diagnose_cell = false 可关），每个会话只打一次。
  if adapter.diagnose_cell ~= nil and not adapter._cell_diagnosed
     and not (adapter.cfg and adapter.cfg.diagnose_cell == false) then
    adapter._cell_diagnosed = true
    pcall(function() adapter:diagnose_cell() end)
    -- 跟着报一段「模板候选」：cell.1.1 自己的 prefabIndex 是**基础模板**，不能用来
    -- 生成格子；必须有「从另存出来的模板**新建**的」那个控件（约定名 tpl.cell）。
    -- 提前报出来，试玩前就知道配没配对，而不是等一句"全部实例化失败"。
    pcall(function() adapter:diagnose_template() end)
  end

  Murdoku.render(true)

  -- ★ 逐格自检 + 子控件清单放在**首次渲染之后**。
  --
  -- 为什么必须放到渲染后：格子上的墙/门/图片是**渲染时**由 `set_property` 落下去的
  -- （`controller:render` 才推 `walls`/`doors`/`image`/`tint`）。放在渲染前，
  -- 清单里读到的全是**编辑器初始值** —— 用户 2026-09-27 04:26 的日志里
  -- `wall.up visible=false` 但**屏幕上明明有蓝线**，就是这么来的（误导性输出）。
  if adapter.diagnose_cell ~= nil and adapter._cell_diagnosed and adapter.diagnose_grid ~= nil
     and adapter.cfg and adapter.cfg.diagnose_grid ~= false then
    local rows = adapter.cells_rows or (adapter.cfg.cells and adapter.cfg.cells.rows) or 5
    local cols = adapter.cells_cols or (adapter.cfg.cells and adapter.cfg.cells.cols) or 5
    pcall(function() adapter:diagnose_grid(rows, cols) end)
  end

  adapter:signal_emit(Qianxing.SIGNALS.READY, {
    tostring(level.id), core.rows, core.cols, core:piece_count(),
  })

  return self
end

-- 官方生命周期包装
function Murdoku.on_start(level_id, opts)
  -- 控件可能还没就绪：先把必要控件探一遍，找不到就返回 nil 让上层重试
  local adapter = (opts and opts.adapter) or prepared_adapter
  if adapter then
    local probe = adapter:find("board") or adapter:find("cell.1.1")
    if probe == nil then return nil end
  end
  local self, err = Murdoku.start(level_id, opts)
  if not self and printerr then printerr("[murdoku] 开局失败：" .. tostring(err)) end
  return self
end

function Murdoku.on_update(dt)
  if not current then return end
  current.adapter:on_tick(dt)
  current.controller:tick(dt)
  -- 时间只在整秒变化时重绘（省性能），但**任何其它状态变化也必须立刻重绘**：
  -- 单击落成铅笔笔记是在 tick 里做的（要等双击窗口），如果只按整秒重绘，
  -- 笔记要等到下一个整秒才画出来 —— 手感上就是"点了没反应"。
  local sec = math.floor(current.core.elapsed or 0)
  if sec ~= current.last_tick or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end
end

function Murdoku.on_destroy()
  if not current then return end
  Murdoku.save_now()
  current = nil
end

-- 兼容旧名
Murdoku.on_ready = Murdoku.on_start
Murdoku.on_tick = Murdoku.on_update

function Murdoku.flush_effects()
  if not current then return end
  if current.controller.dirty then
    Murdoku.render()
  end
  -- 渲染一趟之后，「控件未找到」的账已经记全了 → 打一次**分组汇总**。
  -- 放在这里而不是 create_control 里逐个打，是因为逐个打会刷 80+ 行同义句，
  -- 把"缺的是哪几类"这个真正有用的信息淹掉（report_missing 自己只打一次）。
  if current.adapter.report_missing ~= nil then
    pcall(function() current.adapter:report_missing() end)
  end
end

function Murdoku.on_input(event)
  if not current then return end
  current.controller:on_input(event)
  Murdoku.flush_effects()
end

-- 服务器/节点图发来的信号
function Murdoku.on_signal(name, payload)
  if not current then return end
  local S = Qianxing.SIGNALS
  if name == S.RESTORE then
    Murdoku.restore(payload)
  elseif name == S.SYNC_STATE then
    if payload and payload.who and payload.r and payload.c then
      current.core:select_suspect(payload.who)
      current.core:tap_cell(payload.r, payload.c)
      Murdoku.render()
    end
  elseif name == "murdoku/next_level" then
    local nxt = Levels.next(current.level.id)
    if nxt then Murdoku.start(nxt, current.options) end
  end
end

-- 把服务器推回来的存档还原到棋盘
function Murdoku.restore(payload)
  if not current or type(payload) ~= "table" then return false, "没有存档" end
  if payload.state_code then
    local ok, err = current.core:decode_state(payload.state_code)
    if not ok then
      if printerr then printerr("[murdoku] 读档失败：" .. tostring(err)) end
      return false, err
    end
  elseif payload.cells then
    current.core:deserialize(payload)
  end
  current.core:set_elapsed(payload.elapsed or 0)
  Murdoku.render(true)
  return true
end

-- 主动存档：压成分享码字符串 + 三个整数（局内存档不支持结构体/字典）
function Murdoku.save_now()
  if not current then return false end
  local core = current.core
  local payload = {
    level_id   = tostring(current.level.id),
    state_code = core:encode_state(),
    moves      = core.moves or 0,
    elapsed    = math.floor(core.elapsed or 0),
    solved     = (core.status == Core.STATUS_SOLVED),
  }
  current.adapter:save("murdoku/save/" .. tostring(current.level.id), payload)
  return true
end

----------------------------------------------------------------------------
-- 关卡批量校验（调试用；在编辑器里也可以挂个按钮调用）
----------------------------------------------------------------------------

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
