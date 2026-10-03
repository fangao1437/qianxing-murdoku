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
  --
  -- ★★★ 2026-09-30：**改调 `Levels.ui_list()` —— 这份清单只能有一处定义**。
  --
  --   原来这里和 `tools/dump_layout.lua` **各写了一份**（都只复制 id/name/difficulty），
  --   后果有两个：
  --     · 选关卡片要显示「NxN　M名嫌疑人+1名受害人」（参考《派蒙的执律庭实习》）时
  --       **拿不到 size/suspects** ⇒ 界面上只剩关名
  --     · 两边各写一份 ⇒ **必然漂移**（本项目已因此踩过多次，这是同一类错误的第 N 次）
  --   ⇒ 统一到 `Levels.ui_list()`：卡片要 size/suspects，缩略图要 rooms/objects。
  --     界面层仍然"不认识 Levels"，只是拿一份摘要。
  local level_list = Levels.ui_list()

  -- ⚠️ 先声明再赋值：下面几个回调要在闭包里引用 controller 自己，
  --    而 `local x = f(...)` 里的 x 在构造器内还不存在（会变成全局 nil）。
  local controller

  -- 切到别的关卡：**不要再放一遍开屏教程**（玩家已经在游戏里了）
  local function start_other(id, why)
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.skip_intro = true
    o.debug = opts.debug
    -- ★★★ 2026-09-30：**切关必须清掉屏幕状态**。
    --
    --   上面那句 `for k, v in pairs(opts)` 会把 `opts.screen`（入口传的是 `"home"`）
    --   一并复制过来 ⇒ 新控制器带着 `screen = "home"` ⇒ **游戏界面被屏幕分支整片隐藏**
    --   ⇒ 表现成"切关之后指认面板弹不出来 / 点了像没反应"。
    --   我在探针里看到 `toast` 说提交成功、`modal` 却是 false，查了很久才定位到这里。
    --   ⇒ 规则：**"进入某个关卡" = 屏幕状态为空**，必须显式清掉，不能依赖默认值。
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

  -- ★★★ 2026-09-29：**屏幕状态**（"home" 主页 / "select" 选关 / nil = 在关卡里）
  --
  --   ⚠️⚠️ 这一轮最大的教训，写在这里免得以后再犯：
  --     **官方生命周期 `OnStart()` 不接受参数**，入口是自己造 opts 表的
  --     （见 `entry_client_script.lua` 的 `Murdoku.on_start(FORCE_LEVEL, {...})`）。
  --     所以我最初想"让测试/调用方传 `start_in_level` 压过主页"是**完全无效的** ——
  --     参数根本到不了这里。表现是：模拟器里所有关卡内测试都被送进主页，
  --     而主页分支会连 `modal` 一起藏 ⇒ 症状伪装成"提交后不弹指认面板"，
  --     我为此改了三轮（`and/or` 陷阱、默认值、优先级）全是白费功夫。
  --   ⇒ **不要把力气花在"绕过主页"上，而是让测试真的走一遍主页流程**
  --     （`tools/sim/kit.mjs` 的 `enterLevel()`）。
  local want_screen = nil
  if opts.screen ~= nil then want_screen = opts.screen end
  controller = UIC.new(core, {
    debug = opts.debug,
    skip_intro = opts.skip_intro,
    levels = level_list,
    screen = want_screen,
    -- ★★★ 2026-09-30：**选关卡片要看的两样东西**（之前漏了，卡片永远显示"未开始"）
    --   · progress(id) —— 这一关打过没有 / 破了没有
    --   · last_level() —— 「从存档点开始」要接续的那一关
    --   两者都读局内存档，取不到就返回 nil，卡片只显示关名 —— **不编数据**。
    progress = function(lid) return Murdoku.progress_of(lid) end,
    last_level = function() return Murdoku.last_played() end,
    -- ★★★ 2026-09-30：**界面要知道"现在跑的是哪一关"** —— 棋盘上的**房间名标签**
    --   要按当前关卡的房间框来摆（房间框由 `Levels.ui_list()` 算好）。
    --   只传 id（字符串），界面层自己去那份 list 里找 —— 不把整个关卡表塞过去。
    current_level = tostring(level.id),
    -- 选关：直接从面板跳过去
    on_pick_level = function(id)
      -- ★ 记下"最近游玩"，供主页的「从存档点开始」用（要落盘，跨会话有效）
      Murdoku.remember_level(id)
      if id ~= level.id then
        start_other(id)
      else
        -- 点的是当前这一关：只是退出选关界面，不用重开
        controller.screen = nil
        controller.modal = nil
        controller.dirty = true
        Murdoku.flush_effects()
      end
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
      -- ★★★ 2026-09-30：**记下"这一关破了"** —— 选关卡片要显示「★ 已破案」。
      --   之前只发了信号、没落盘 ⇒ 卡片永远显示"未开始"，
      --   玩家看不出自己打过哪几关（这正是「参考原作卡片选关」要看的信息）。
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

  -- ★★★★★ 2026-10-02 **用"脚本创建"重做选关按钮**（用户指定的路线）。
  --   真机证明只有脚本创建的控件能收到点击（关卡里的格子 ✅、编辑器摆的卡片 ❌）
  --   ⇒ 选关页改为用**同一个模板**在 `board` 下建按钮，点击走和格子一模一样的代码路径。
  --   数量取关卡数（不确定就按 8 个建，多余的藏起来）。
  do
    local n_levels = 8
    if Levels ~= nil and type(Levels.all) == "function" then
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    -- ★ 先无条件把"这个方法在不在"打出来 —— 上一版整段被 `if adapter.ensure_widgets then` 跳过、
    --   连一行日志都没有，害我又猜了一轮。**先把存在性打出来，再调用。**
    print("[murdoku] ensure_widgets 存在性：type=" .. type(adapter.ensure_widgets)
      .. "，n_levels=" .. tostring(n_levels))
    if adapter.ensure_widgets and not (adapter.cfg and adapter.cfg.widgets == false) then
      local made, err, existed = adapter:ensure_widgets(n_levels)
      print("[murdoku] 选关按钮（脚本创建）：新建 " .. tostring(made)
        .. " 个，已存在 " .. tostring(existed or 0) .. " 个"
        .. (err and ("　⚠️ " .. tostring(err)) or ""))
      -- 逐个绑点击 → ★ 用**和现有卡片一模一样**的事件写法：
      --     event = { action = "pick_level", id = <关卡 id> }
      --   上一版我编了个 `event = "pick/1"`（字符串）⇒ 日志里 `事件=nil/-`
      --   —— `bind_input` 读的是 `node.event.action`，字段名错了就整条绑成兜底事件。
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
      -- ★★ 2026-09-29：**`label` 找不到就退回 `text`**。
      --
      --   为什么：真机日志一直报「写入后读回一致 8 个，**不一致 5 个**」，
      --   看着像出错，其实那 5 个是**头像卡**（`tray.*`）——
      --   它们的文字子控件叫 `text` 而不是 `label`（见体检输出）。
      --   统计口径把"正常的另一种结构"算成了失败，误导排查。
      --   ⇒ 两个都试，并且**分开报数**，日志才说真话。
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
            -- ★★★ 2026-09-29：**不再强制 label 的尺寸/字号/位置**。
            --
            --   用户在编辑器里**自己给按钮配好了居中文本**
            --   （例如 `action.hint` 的 bg 97×43、label 59×40），
            --   而我之前每次都按自己的算法把 label 改成 (按钮宽, 28) 并设 fontSize=24
            --   ⇒ **把用户调好的东西覆盖掉**，这正是他说的"未完整生效"。
            --
            --   现在脚本只负责**写文字内容**（文字不存进 .gil，只能运行时写），
            --   几何与字号一律听编辑器的。
            --   （如果将来发现某类按钮字号偏小，用 cfg.label_font_size 单独指定，
            --     不要再无条件覆盖。）
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

  -- ★★★ 2026-09-30：**把主页/选关和 3D 角色的输入隔开**（用户明确要求）。
  --
  --   做法见适配器 `seal_container` 的注释：给容器设「屏蔽按键事件穿透」
  --   （`disableKeyEventPassthrough`）等字段 —— **不是拦截键位**
  --   （`AddKeyEventListener` 只有"监听"、没有"消费"语义，拦不住）。
  --   控件已经在 .gil 里，这里是运行时给它们上锁。
  --
  --   ⚠️ 待真机验证：**屏蔽之后 `AddKeyEventListener` 自己还能不能收到按键**。
  --      如果连自己也收不到，就缩小范围（只用 `disableCursorEventPassthrough`）。
  --      这条日志打出"设了几个"，方便对照。
  if adapter.seal_containers ~= nil then
    local sealed = adapter:seal_containers({ "home", "select" })
    if print then
      print(string.format("[murdoku] 2D/3D 输入隔离：主页/选关容器已屏蔽穿透 %d 个", sealed))
      -- ★★★ 2026-09-30：**把验收方法直接写进日志**（目标⑦）。
      --
      --   「屏蔽之后脚本自己还收不收得到按键」只有真机能回答。与其等你来问，
      --   不如启动时就说清楚**怎么确认**：
      --     按任一键盘快捷键 → 看到 `✅ 键盘事件仍能收到` ⇒ 隔离没有副作用
      --                       看不到 ⇒ 屏蔽把键盘也挡住了
      --   （那条 ✅ 在 engine_adapter 的按键回调里，**只在第一次按键时打一次**，
      --     且不依赖 debug_key。）
      print("[murdoku]   验收：在关卡里按任一键盘快捷键 —— 出现「✅ 键盘事件仍能收到」"
        .. "即说明隔离没有副作用；若没有，去掉 main.lua 里的 seal_containers 即可（一行）。")
    end
  end

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
    -- ★★★★★ 2026-10-02 **这里原来写死了 `board` / `cell.1.1`** ——
    --   重建时这两个控件被删掉了 ⇒ **判据永远为假** ⇒ `on_start` **永远返回 nil**
    --   ⇒ 上层每帧重试、`started` 一直 false ⇒ 主页设置在 `on_start` 里 ⇒
    --   **主页消失 + 隔断失效**（用户 13:5x 实测）。
    --
    --   ⚠️ 同一个判据在 `entry_client_script.lua` 的 `probe_or_dump()` 里**也有一份**
    --   （那处上一轮已改）—— **两处必须一致**，这就是"判据写死旧名字"第三次咬人的地方。
    --
    --   新判据（按"重建后什么一定存在"）：
    --     ① 旧结构：board / cell.1.1 任一
    --     ② 新结构：stage / home 任一
    --     ③ 兜底：root 存在且已有 >3 个子控件
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
    if not ready then return nil end
  end
  local self, err = Murdoku.start(level_id, opts)
  if not self and printerr then printerr("[murdoku] 开局失败：" .. tostring(err)) end
  return self
end

function Murdoku.on_update(dt)
  if not current then return end
  current.adapter:on_tick(dt)
  current.controller:tick(dt)

  -- ★★★★★ 2026-10-02 **门控②必须反复重试，不能只在开局做一次**。
  --
  --   真机日志把原因暴露得很清楚：
  --     常驻光标回读（门控②）：root=true topbar=true left=true ... intro=true
  --     已由脚本打开 9 个容器的「显示常驻光标」     ← **还是 9 个，home/select 不在里面**
  --   而 `enable_cursor` 只在 `Murdoku.start` 里调**一次** —— 那时 `home` / `select`
  --   这两个**屏幕容器还没被 create_control**（它们是第一次渲染时才建的），
  --   `find("home")` 返回 nil ⇒ 直接跳过 ⇒ **永远开不上** ⇒ 它们的子控件全部落在门控②之外。
  --
  --   ⇒ 改成每 20 帧重试一次（幂等、便宜），直到所有受管容器都拿得到为止。
  if current.adapter.enable_cursor and ((current.frames or 0) % 20 == 0) then
    local before = Murdoku._cursor_ok or 0
    local n = current.adapter:enable_cursor()
    Murdoku._cursor_ok = n
    if n ~= before and print then
      print("[murdoku] 门控②重试：已打开 " .. tostring(n) .. " 个容器的「显示常驻光标」")
    end
  end

  -- ★★★★★ 2026-10-02 **强制打开「可被光标射线检测」（`raycastTarget`）** —— 真机"点不动"的正解。
  --
  --   官方文档：预设按钮只有三个自有字段 `interactable` / `clickAudioId` / `raycastTarget`；
  --   项目自己的清单写着：「关掉就点不动」「**界面看得见，但点哪儿都没反应**」。
  --   而 `clickAudioId` 就是点击音效 ⇒ "处处有音效但什么也没发生" = 点到了按钮、但它 `raycastTarget=false`。
  --   我之前只对容器试过这个字段（容器没有它）⇒ 误判成"引擎里不存在"⇒ 从没对按钮读过写过。
  if current.adapter.enable_raycast and ((current.frames or 0) % 20 == 0) then
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
  -- 时间只在整秒变化时重绘（省性能），但**任何其它状态变化也必须立刻重绘**：
  -- 单击落成铅笔笔记是在 tick 里做的（要等双击窗口），如果只按整秒重绘，
  -- 笔记要等到下一个整秒才画出来 —— 手感上就是"点了没反应"。
  local sec = math.floor(current.core.elapsed or 0)
  if sec ~= current.last_tick or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end

  -- ★★★ 2026-10-01：**开局后的一次性"屏幕上到底有什么"诊断**。
  --
  --   为什么加：用户在真机上反馈"界面一片空白"，而日志里该建的东西都建了、
  --   没有任何报错 —— 光靠现有日志**分不清**是
  --     (a) 脚本把控件设成了隐藏，还是 (b) 控件坐标跑到屏幕外，还是
  --     (c) 控件根本不存在（名字对不上）。
  --   ⇒ 这里在第 90 帧（约 1.5 秒，足够跑完开局渲染）打一次**实际读回来**的状态：
  --     能不能找到、visible / active 是多少、坐标尺寸是多少。
  --   只打一次，不影响性能，也不依赖 debug_* 开关（这是验收信息，不是调试噪音）。
  -- ★★★★ 2026-10-01 改成"每次切屏都打一次"（原来只在第 90 帧打一次，只看到主页）。
  --   起因：用户报"选关界面上所有按钮都无效"，而诊断只在主页打过 => 看不到选关页真实状态。
  -- ★★★★★ 2026-10-03 **手动显形（分家后）** —— 从下面那个"诊断块"里搬出来的**功能代码**。
  --
  --   为什么要搬：原来这两句藏在 `if (frames >= 90 or 切屏) … then` 的诊断块里，
  --   注释写着"不影响性能、是验收信息"，但实际它每次切屏都会**强制**把
  --   `home.select` 和 `home` 容器设成可见 —— 这是当初为了修"主页按钮不显示"加的，
  --   属于**功能**，不是诊断。
  --   ⇒ 一旦整块删掉诊断，主页按钮就会再次消失（和 009 那次同类事故）。
  --   ⇒ 所以按《安全瘦身规程》第 ① 步：**先把功能搬到诊断块外面无条件执行**，
  --     本轮**只搬不删**；确认无误后下一轮才删那个诊断块。
  do
    local ad0 = current.adapter
    if ad0 ~= nil then
      local leaf0 = nil
      pcall(function() leaf0 = ad0:find("home.select") end)
      if leaf0 ~= nil then
        pcall(function() if leaf0.SetVisible then leaf0:SetVisible(true) end end)
        pcall(function() if leaf0.SetActive  then leaf0:SetActive(true)  end end)
      end
      local hm0 = nil
      pcall(function() hm0 = ad0:find("home") end)
      if hm0 ~= nil then
        pcall(function() if hm0.SetVisible then hm0:SetVisible(true) end end)
        pcall(function() if hm0.SetActive  then hm0:SetActive(true)  end end)
      end
    end
  end

  local scr_now = current.controller and current.controller.screen or "level"
  if ((current.frames or 0) >= 90 or scr_now ~= Murdoku._last_screen)
     and scr_now ~= Murdoku._dump_done_for then
    Murdoku._dump_done_for = scr_now
    local ad = current.adapter
    print("[murdoku] ===== 开局诊断：屏幕上到底有什么（第 90 帧实测）=====")
    print("[murdoku]   controller.screen = " .. tostring(current.controller.screen))
    local ids = {
      "root", "home", "home.title", "home.select", "home.continue", "home.shop", "home.bag",
      "select.back", "select.title", "select.card.1", "select.card.2",
      "select", "select.card.2",
      "board", "cell.1.1", "topbar", "clues", "action.undo", "hud.title",
    }
    for i = 1, #ids do
      local id = ids[i]
      local c = nil
      pcall(function() c = ad:find(id) end)
      if c == nil then
        print("[murdoku]   " .. id .. "  → **找不到控件**（名字对不上 / .gil 里没有）")
      else
        -- ⚠️ 读坐标**必须用 GetAnchoredPosition / GetSizeDelta 这两个方法** ——
        --   我第一版写 `c.positionX` / `c.width`，真机上**全读成 nil**
        --   （适配器里那段"逐格自检"就是这么踩过并改对的，我照抄了错的那半）。
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
    -- ★★★★ 2026-10-01 **列出本屏所有"可见"控件、按面积从大到小**。
    --
    --   起因：诊断已经证明选关页上 `select.back` / `select.card.*` 的
    --   visible=true、坐标在屏内、bind=true —— **一切正常却点不动**
    --   ⇒ 只剩一种可能：**有别的东西盖在它们上面**（射线被上层控件接走）。
    --   而原来只打了 12 个固定 id，看不到"谁盖住了谁"。
    --   ⇒ 这里从 root 递归走一遍真实控件树，把所有 visible=true 的按面积排序打出来：
    --     排在最前面的那几个大控件，就是"疑犯"。
    -- ★★★★★ 2026-10-02 **去掉 visible=true 这个过滤条件**（用户三条答案指出的"眼罩"）。
    --
    --   用户观察：那个拦截层**全透明、不消失、Esc 无反应** ⇒ 是一个**隐形输入层**。
    --   而这一版之前所有排行榜都写着 `if v == true then`（只看可见控件）
    --   ⇒ **一个 visible=false 但仍在拦截点击的控件，一次都没被列出来过**。
    --   脚本用的是 `SetVisible()` —— 关掉的是**渲染**；诊断里所有控件的 `active`
    --   都是 true ⇒ **不可见但仍然 active 的控件，很可能照样参与射线**。
    --   ⇒ 改成"一律列出"，并把 visible / active **都打出来**，大的一律标 ★。
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
        -- 只列"大"的；阈值降到 20000（原来的 1000 会刷一屏小控件）
        if area > 20000 then
          list[#list + 1] = { id = nm, w = w or 0, h = h or 0, area = area,
                              vis = tostring(v), act = tostring(al) }
        end
        -- ⚠️ 这里原来用 `c.childCount` + `c:GetChild(i-1)` —— **走不进子树**
        --   （排行榜只报出 root 一个，而诊断里明明有一堆 visible=true 的控件）。
        --   项目里能用的枚举是 `ctrl:GetChildren()`（见适配器 L235/L295/L612 等处）。
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

    -- ★★★★ 2026-10-01 **第二段诊断（真机仍看不见时用）**：
    --   容器尺寸/可见性/坐标全都对，但屏幕上还是没有 ⇒ 说明"卡在哪一层"还没查出来。
    --   这一段做三件事：
    --     ① 把 `home.select` 的**父级链逐层**读出来（哪一层被关掉了，一眼就看见）
    --     ② 读**透明度/缩放**这类"看起来在、其实画不出来"的属性
    --     ③ **手动 `SetVisible(true)` / `SetActive(true)` 之后再读一遍** ——
    --        如果"手动设完就能看见"，说明是脚本下发的属性没生效（写法问题）；
    --        如果"设完还是看不见"，说明是渲染层/图层的问题（另一条路）。
    print("[murdoku] ===== 诊断二：父级链 + 透明度 + 手动显形 =====")
    local leaf = nil
    pcall(function() leaf = ad:find("home.select") end)
    if leaf == nil then
      print("[murdoku]   home.select 找不到，跳过")
    else
      -- ① 父级链
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
      -- ② 透明度 / 缩放
      local al, sc = "?", "?"
      pcall(function() al = tostring(leaf.alpha) end)
      pcall(function() sc = tostring(leaf.scale) end)
      print("[murdoku]   home.select alpha=" .. al .. " scale=" .. sc)
      -- ③ 手动显形 + 回读
      local okv, oka = true, true   -- 已由块外那段负责，这里只用于打印
      -- ★ 2026-10-03 **分家**：`leaf:SetVisible(true)` / `leaf:SetActive(true)` 两行
      --   已经搬到本 if 块**外面**无条件执行（见上面那段「手动显形（分家后）」），
      --   这里只保留回读与打印（方案 A：只搬不删）。
      pcall(function() v2 = tostring(leaf.visible) end)
      pcall(function() a2 = tostring(leaf.active) end)
      print("[murdoku]   手动 SetVisible=" .. tostring(okv) .. " SetActive=" .. tostring(oka)
        .. "  ⇒ 回读 visible=" .. v2 .. " active=" .. a2)
      -- 顺手把 home 容器也显形（它要是被关了，子控件画不出来）
      local hm = nil
      pcall(function() hm = ad:find("home") end)
      if hm ~= nil then
        -- ★ 分家：hm:SetVisible(true) 已搬到块外（见「手动显形（分家后）」）
        -- ★ 分家：hm:SetActive(true) 已搬到块外
        print("[murdoku]   已对 home 容器也调了一次 SetVisible/SetActive")
      end
    end
    print("[murdoku] ===== 诊断二结束 =====")
    -- ★ 诊断三（运行时新建控件做对照）已经在用户实测中完成使命：
    --   **运行时新建的控件可见，编辑器里已有的不可见** —— 结论直接指向
    --   `respect_editor_rect` 那一条（见 ui_controller 的 `inherit_pos_runtime`）。
    --   那个探针控件就是用户看到的"白块"，已删除，不再创建。

  end
  -- ★★★★ 2026-10-01 **射线落点探针**：给几个"容器/弹窗"也绑上点击。
  --
  --   为什么：选关页上 `select.back` / `select.card.*` 的 visible/坐标/bind 全对，
  --   而用户"所有位置都点了一遍"却**零点击日志**。可 `select` 容器自己**没绑点击**
  --   => "没日志"并不能区分"射线被别人吃了"和"射线落在没绑事件的控件上"。
  --   => 给容器们绑一遍：**谁收到日志，射线就落在谁身上**。
  --      容器能收到 => 射线到得了这一层，子控件却没收到 => 子控件的射线被谁挡住/顺序不对
  --      容器也收不到 => 更上层还有东西（游戏自己的 UI 层）
  if not Murdoku._ray_probe_done and (current.frames or 0) >= 100 then
    Murdoku._ray_probe_done = true
    local ad3 = current.adapter
    local probe_ids = { "root", "home", "select", "intro", "toast", "modal", "board" }
    for i = 1, #probe_ids do
      local pid = probe_ids[i]
      local c = nil
      pcall(function() c = ad3:find(pid) end)
      local clickEnum = nil
      pcall(function() clickEnum = Enum.CursorEventType.CursorClick end)
      if clickEnum == nil then
        pcall(function() clickEnum = Enum.CursorEventType.CursorClickDown end)
      end
      if c ~= nil and c.AddCursorEventListener ~= nil and clickEnum ~= nil then
        local okb = pcall(function()
          c:AddCursorEventListener(clickEnum, function()
            print("[murdoku] RAY-HIT = " .. pid .. " （射线落在这个容器上）")
          end)
        end)
        print("[murdoku] 射线探针：" .. pid .. " 绑定=" .. tostring(okb))
      elseif clickEnum == nil then
        print("[murdoku] 射线探针：读不到 Enum.CursorEventType.CursorClick，跳过")
        break
      else
        print("[murdoku] 射线探针：" .. pid .. " 找不到或不支持光标事件")
      end
    end
    -- ★★★★★ 2026-10-02 **打印所有客户端 UI 根**。
    --
    --   为什么：用户的观察把范围压到了最后一格 ——
    --     · 把 `home`/`select` 缩成 1x1 之后，**选关页该有的按钮消失了**（被父级裁剪）
    --     · 而**"处处有音效"依旧** ⇒ 那个吃点击的全屏按钮**不是** home/select
    --     · 排行榜里只有 `root` 一个全屏 ⇒ **它不在 root 的子树里**
    --   ⇒ 结论：**它在另一个客户端 UI 根上**。
    --   适配器注释里写着查找用的是 `game.GetClientUIRoots()`（**复数**），
    --   而脚本从头到尾只用了一个 `root`。把这些根全部列出来，那个全屏按钮就会现形。
    print("[murdoku] ===== 客户端 UI 根清单 =====")
    do
      local roots = nil
      pcall(function() roots = game.GetClientUIRoots() end)
      if type(roots) ~= "table" then
        print("[murdoku]   读不到 game.GetClientUIRoots()（或返回非表）")
      else
        print("[murdoku]   共 " .. tostring(#roots) .. " 个根")
        for i = 1, math.min(#roots, 12) do
          local r = roots[i]
          local nm, v, w, h = "?", "?", 0, 0
          pcall(function() nm = tostring(r.name) end)
          pcall(function() v = tostring(r.visible) end)
          pcall(function()
            local a, b = r:GetSizeDelta()
            if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
          end)
          local kids = nil
          pcall(function() kids = r:GetChildren() end)
          local nk = (type(kids) == "table") and #kids or -1
          print(string.format("[murdoku]     %d. %-18s visible=%-5s %6.0fx%-6.0f 子控件=%d",
            i, nm, v, w or 0, h or 0, nk))
          -- 根下面直接可见的大控件 —— 那个全屏按钮多半就在这一层
          if type(kids) == "table" then
            for k = 1, math.min(nk, 20) do
              local c = kids[k]
              if c ~= nil then
                local cn, cv, cw, ch, hasCur = "?", "?", 0, 0, false
                pcall(function() cn = tostring(c.name) end)
                pcall(function() cv = tostring(c.visible) end)
                pcall(function()
                  local a, b = c:GetSizeDelta()
                  if type(a) == "table" then cw, ch = a.x, a.y else cw, ch = a, b end
                end)
                pcall(function() hasCur = (c.AddCursorEventListener ~= nil) end)
                if (cw or 0) * (ch or 0) > 20000 then
                  print(string.format("[murdoku]        └ %-20s visible=%-5s %6.0fx%-6.0f 可接收光标=%s",
                    cn, cv, cw or 0, ch or 0, tostring(hasCur)))
                end
              end
            end
          end
        end
      end
    end
    print("[murdoku] ===== 根清单结束 =====")
    -- ★★★★★ 2026-10-02 **对照组诊断**：把"能点的样本"和"不能点的样本"逐一对比。
    --
    --   ⚠️ 第一版这里全部报「找不到」—— 因为直接用了 `ad:find(id)`，
    --   而同一份日志里「诊断二」用**同一个调用**却能拿到 `home.select`。
    --   ⇒ 不再依赖 `find`：**自己从 `root` 遍历整棵树建一张 name→控件 的表**，
    --     然后从表里取。这样"取不到"只可能是名字真不在树里。
    print("[murdoku] ===== 对照组：能点 vs 不能点 =====")
    do
      local rootC = nil
      pcall(function() rootC = ad:find("root") end)
      -- 兜底：从 GetClientUIRoots 拿
      if rootC == nil then
        local rs = nil
        pcall(function() rs = game.GetClientUIRoots() end)
        if type(rs) == "table" and rs[1] ~= nil then rootC = rs[1] end
      end
      local map, count = {}, 0
      if rootC ~= nil then
        local function walk(c, depth)
          if c == nil or depth > 6 then return end
          local nm = nil
          pcall(function() nm = c.name end)
          if nm ~= nil and nm ~= "" and map[nm] == nil then map[nm] = c count = count + 1 end
          local kids = nil
          pcall(function() kids = c:GetChildren() end)
          if type(kids) == "table" then
            for k = 1, math.min(#kids, 200) do walk(kids[k], depth + 1) end
          end
        end
        walk(rootC, 0)
      end
      print("[murdoku]   树里共收集 " .. tostring(count) .. " 个具名控件（root=" .. tostring(rootC ~= nil) .. "）")
      local fields = { "visible", "active", "showCursor", "interactable", "raycastTarget",
                       "clickAudioId", "disableCursorEventPassthrough", "disableKeyEventPassthrough",
                       "isolateNavigation", "alpha", "index", "zIndex", "sortingOrder",
                       "enable", "enabled", "blockRaycast", "grayed", "isEnabled" }
      local samples = { "home.select", "select.card.1", "select.back", "cell.1.1", "selbtn.1", "selbtn.2", "board", "select", "home" }
      for s = 1, #samples do
        local id = samples[s]
        local c = map[id]
        if c == nil then
          print("[murdoku]   " .. id .. "  —— **树里没有这个名字**")
        else
          local parts = {}
          for f = 1, #fields do
            local v = "?"
            pcall(function() v = tostring(c[fields[f]]) end)
            if v ~= "nil" then parts[#parts + 1] = fields[f] .. "=" .. v end
          end
          local chain, cur, guard = {}, c, 0
          while cur ~= nil and guard < 8 do
            local nm, sc, vv = "?", "?", "?"
            pcall(function() nm = tostring(cur.name) end)
            pcall(function() sc = tostring(cur.showCursor) end)
            pcall(function() vv = tostring(cur.visible) end)
            chain[#chain + 1] = nm .. "(vis=" .. vv .. ",cur=" .. sc .. ")"
            local up = nil
            pcall(function() up = cur.parent end)
            if up == nil then pcall(function() up = cur:GetParent() end) end
            cur = up
            guard = guard + 1
          end
          print("[murdoku]   " .. id .. "  " .. table.concat(parts, "  "))
          print("[murdoku]       祖先链：" .. table.concat(chain, " ← "))
        end
      end
    end
    print("[murdoku] ===== 对照组结束 =====")
    print("[murdoku] 射线探针装好了 —— 之后点任何地方，只要射线落在这些容器上就会打日志")
  end
  -- ★★★★ 2026-10-02 **按用户建议做的对比：主页 ⇄ 选关，"切换后到底改了什么"**。
  --
  --   用户原话：「我认为应该好好对比一下首页和选关切换后到底改了什么」
  --   —— 这条方法是对的。我前面 9 轮都在猜机制（raycastTarget / childCount / 递归隐藏…），
  --   而**事实是两份排行榜摆在那里**：
  --     主页可见：root / home / home.title / home.*四键 / face / content / obj / bg×4 / label×4
  --     选关可见：root / select / select.title / card.1~4 / back / face / content
  --   ⇒ **交集只有 root + face + content** —— 后两个正是**格子模板的子控件（135x135）**，
  --     也是我所有"隐藏"都没碰到的东西。
  --   ⇒ 但它们只有一块 135x135，解释不了"所有位置都点不动" ⇒ **必须知道它们在屏幕的哪**。
  --   ⇒ 这里拍两份快照（切屏前 / 切屏后），**带屏幕坐标**，并打印**差集**。
  local function snap_visible()
    local out = {}
    local rt = nil
    pcall(function() rt = ad:find("root") end)
    if rt == nil then return out end
    local function walk(c, ox, oy, depth)
      if c == nil or depth > 6 then return end
      local v = nil
      pcall(function() v = c.visible end)
      -- ★★★★★ 2026-10-02 **去掉 visible 过滤**（用户三条答案指出的"眼罩"）。
      --
      --   用户观察：那个拦截层**全透明、不消失、Esc 无反应** ⇒ 是一个**隐形输入层**。
      --   而我之前所有排行榜都写着 `if v == true then`（只看 visible=true）
      --   ⇒ **一个 visible=false 但仍在拦截点击的控件，我一次都没列出来过**。
      --
      --   而脚本用的是 `SetVisible()` —— 关掉的是**渲染**；诊断里所有控件的
      --   `active` 都是 true ⇒ **不可见但仍然 active 的控件很可能照样参与射线**。
      --   ⇒ 改成：**不管 visible，一律列出来**，并把 visible / active 都打出来。
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
          -- 屏幕坐标 = 父级屏幕位置 + 自身偏移（Y 向上）；根级以画布中心为原点
          local sx = (ox or 0) + (ax or 0)
          local sy = (oy or 0) + (ay or 0)
          out[nm] = string.format("%dx%d @屏幕(%.0f,%.0f)", w or 0, h or 0, sx + 800, sy + 450)
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
  if Murdoku._snap == nil or scr_now ~= Murdoku._snap_screen then
    local now = snap_visible()
    if Murdoku._snap ~= nil then
      print("[murdoku] ===== 切屏对比：" .. tostring(Murdoku._snap_screen) .. " → " .. tostring(scr_now) .. " =====")
      print("[murdoku]   【切过去之后**多出来**的可见控件】（嫌疑最大）")
      local n_add = 0
      for k, v in pairs(now) do
        if Murdoku._snap[k] == nil then print("[murdoku]     + " .. k .. "  " .. v); n_add = n_add + 1 end
      end
      if n_add == 0 then print("[murdoku]     （没有多出来的）") end
      print("[murdoku]   【切过去之后**消失**的可见控件】")
      local n_del = 0
      for k, v in pairs(Murdoku._snap) do
        if now[k] == nil then print("[murdoku]     - " .. k .. "  " .. v); n_del = n_del + 1 end
      end
      if n_del == 0 then print("[murdoku]     （没有消失的）") end
      print("[murdoku]   【**两个页面都在**的可见控件】—— 这些不随切屏变化，最可能是「挡在中间」的")
      for k, v in pairs(now) do
        if Murdoku._snap[k] ~= nil then print("[murdoku]     = " .. k .. "  " .. v .. "   （切屏前 " .. Murdoku._snap[k] .. "）") end
      end
      print("[murdoku] ===== 对比结束 =====")
    end
    Murdoku._snap = now
    Murdoku._snap_screen = scr_now
  end
  -- ★★★ 2026-10-02 **撤掉每帧的图层排序**（`enforce_screen_layers`）。
  --
  --   为什么撤：新版「对照组诊断」证明 `home` 与 `select` 的**容器设置完全一致**
  --   （showCursor / disableCursorEventPassthrough / disableKeyEventPassthrough 都一样），
  --   子控件的 interactable / raycastTarget / clickAudioId 也一致 ⇒
  --   **"home 压住 select"这个当初的假设从来不是问题** ⇒ 这个排序没被证明有用，
  --   却可能有害（它把 select 排到最后 = 最上）。
  --   真机现象是"主页能点、选关不能点"，而主页时 select 被排到最下 ⇒ 排序**恰好与现象相关**
  --   ⇒ 撤掉，做一次单一变量的真机实验。
  --   （`Adapter:enforce_screen_layers` 本体留在适配器里，随时可以再开。）
  -- ★★★★★ 2026-10-02 **选关按钮的每帧排布**（脚本创建的控件）。
  --   选关页：4 个一行摆在屏幕中上部（棋子大小用格子的几何，视觉一致）；
  --   其它屏：全部隐藏（避免抢射线）。
  --   同时把编辑器摆的旧卡片/返回键**藏起来** —— 它们收不到点击，留着只会挡路。
  do
    local n_levels = 8
    do
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
    -- ★★★★★ 2026-10-02 重建后的显隐：`stage` 与它下面的 `selbar` / `selbtn.*`。
    --   旧代码里那段"把 board 设为可见"已经没意义 —— `board` 在重建时被删了。
    --   现在链条是：root → stage（脚本容器的家）→ selbar（脚本创建的容器）→ selbtn.N（脚本创建的按钮）
    do
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
        pcall(function() s:SetVisible(true) end)
        -- ★★★★★ 2026-10-02 **`stage` 要按"棋盘容器"的尺寸摆**，不能让它保持全屏。
        --
        --   为什么：格子的几何是**按父容器尺寸算**的（`cell_geometry` 读父级 sizeDelta）。
        --   父级从旧 `board`（677x677）换成 `stage`（1600x900）之后：
        --     旧：`边缘适配 wall.up：基准 80x20 → 目标 125x8`
        --     新：`边缘适配 wall.up：基准 80x20 → 目标 167x8`   ← 格子被放大了 33%
        --   ⇒ 棋盘虽然"存在且可见"，但布局跟设计对不上（用户："还没有棋盘出现"）。
        --   ⇒ 这里把 `stage` 恢复成棋盘应有的尺寸并居中；`selbar`（选关条）自己另有尺寸。
        pcall(function() s:SetSizeDelta(677, 677) end)
        pcall(function() s:SetAnchoredPosition(0, 0) end)
      end
      local bar = nil
      pcall(function() bar = current.adapter:find("selbar") end)
      if bar ~= nil then
        pcall(function() bar:SetVisible(on_select) end)
        if on_select then
          pcall(function() bar:SetAnchoredPosition(0, 0) end)
          pcall(function() bar:SetSizeDelta(1500, 700) end)
        end
      end
    end
    -- ★★★★★ 2026-10-02 **这是"四个按钮看不见"的原因**：
    --   `selbtn.*` 的父级是 **`board`**，而 `board` 在选关页是 `visible=false`
    --   ⇒ **父级不可见，子控件跟着不可见** ⇒ 脚本再怎么 `SetVisible(true)` 都白搭。
    --   ⇒ 选关页把 `board` 也设为可见（棋盘格 `cell.*` 本来就是藏着的，不会露出来）。
    -- （旧的 "board 在选关页可见" 已删：重建后 board 不存在了）
    for i = 1, n_levels do
      local c = nil
      pcall(function() c = current.adapter:find("selbtn." .. tostring(i)) end)
      if c ~= nil then
        pcall(function() c:SetVisible(on_select) end)
        if on_select then
          -- 一行摆开：间距 200，起点居中
          local x = (i - (n_levels + 1) / 2) * 200
          pcall(function() c:SetAnchoredPosition(x, 120) end)
          pcall(function() c:SetSizeDelta(160, 160) end)
        end
      end
    end
    -- ★★★★★ 2026-10-02 **删掉"把旧卡片/返回键藏起来"那段** —— 它就是你截图里
    --   "选关界面的按钮没了"的元凶。
    --
    --   那是我 10-02 早上为了做"脚本创建选关按钮"的对照实验加的：
    --       -- 旧卡片/返回键：选关页也不显示（它们点不动）
    --       for i = 1, 8 do ... select.card.i : SetVisible(false) end
    --       select.back : SetVisible(false)
    --   它**每帧无条件执行**，于是：
    --       · 「选择关卡」标题还在（那是 text 类型，脚本没动它）
    --       · 4 张卡片 + 「返回」全没了（按钮类型，被这段藏了）
    --   —— 用户给的两张截图正好对上：10-01 23:18（这段还不存在）里有按钮，
    --      10-02 09:42（这段存在）里只剩标题。
    --
    --   ⇒ 现在删掉。可见性重新交给 `ui_controller` 的按屏规则（选关页显示 `select.*`）。
    --      上半段 `selbtn.*` 的循环也只在 `widgets = true` 时才让 `on_select` 为真，
    --      默认配置下它什么都不做，不会干扰 93 里原有的卡片。
  end
  -- ★★★★★ 2026-10-02 **把 topbar / right 的锚点归零** —— 修"子控件双重偏移"。
  --
  --   真机日志（20:03，关卡内）：
  --       UI定位 right：pos=(575,-23)            ← right 自己靠右（对）
  --         子控件 hud.progress：pos=(508,-283)  ← ★ 相对 right 又偏 508
  --       ⇒ 实际 X = 800 + 575 + 508 = **1883** ⇒ 超出 1600 宽的画布 ⇒ **跑到屏幕外**
  --   原因：从 93 领养来的这批子控件，坐标是**相对屏幕中心**的绝对值（编辑器里摆的），
  --   而它们现在的父级 `right` 自己也有偏移 ⇒ **父级偏移 + 子控件绝对坐标 = 双重偏移**。
  --   ⇒ 对策：把这两个容器的锚点设成 (0,0)（居中）⇒ 子控件的相对坐标就等于绝对坐标，
  --     位置立刻回到编辑器里摆的地方。
  for _, nm in ipairs({ "topbar", "right" }) do
    local c = nil
    pcall(function() c = current.adapter:find(nm) end)
    if c ~= nil then
      pcall(function() c:SetAnchoredPosition(0, 0) end)
    end
  end
  -- ★★★★★ 2026-10-02 **UI 容器定位诊断**：真机"right/topbar 可见=true 但看不到"，
  --   所以把它们的**位置/尺寸/透明度/同级顺序**全打出来，一次看清问题在哪。
  -- ★ 2026-10-03 删除「容器 UI定位」诊断块（纯只读 + print）。整块删掉，不保留 if false。
  -- ★★★★★ 2026-10-03 **六边形素材：直接测实例化**（第一组接入的诊断）
  --
  --   真机日志（16:13）里，`action.hint.hexbg` / `action.redo.hexbg` 出现在
  --   "这些控件还没建"清单里 ⇒ **它们压根没被创建**，不是"位置不对"。
  --   按"先看输出、再解释现象"的规矩，这里**直接调一次实例化并把返回值打出来**：
  --     · 返回非 nil ⇒ 实例化这条路是通的，问题在"我们没让它建"（计划/配置）
  --     · 返回 nil   ⇒ 这条路本身不通（索引不对 / 该模板不是客户端控件模板）
  -- ★ 2026-10-03 删除「六边形素材实例化探针」：它每 300 帧真的调 InstantiateClientUIControl 建两个控件再销毁，是"棋盘出现慢"的主因。纯诊断（只操作它自己建的临时对象 + print）⇒ 整块删掉，而不是 if false 关掉。
  -- ★ 每 300 帧打印一次"第一个格子的屏幕坐标" —— 一眼看出棋盘在屏幕哪、有没有跑出去。
  if (current.frames or 0) % 300 == 0 then   -- 还原（原条件）
    local c1 = nil
    pcall(function() c1 = current.adapter:find("cell.1.1") end)
    if c1 ~= nil then
      local ax, ay, w, h = 0, 0, 0, 0
      pcall(function()
        local a, b = c1:GetAnchoredPosition()
        if type(a) == "table" then ax, ay = a.x, a.y else ax, ay = a, b end
      end)
      pcall(function()
        local a, b = c1:GetSizeDelta()
        if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
      end)
      -- stage 自己的位置（父级中心在画布里的偏移）
      local sx, sy = 0, 0
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
        pcall(function()
          local a, b = s:GetAnchoredPosition()
          if type(a) == "table" then sx, sy = a.x, a.y else sx, sy = a, b end
        end)
      end
        -- ★★★★★ 2026-10-03 **删掉每帧打印的「格子定位」**（原 L1193~1196）。
        --   它是**每帧**执行的 `string.format` + `print`，真机日志里同一行连续出现十几次，
        --   是当前脚本**最大的单点开销**。整块只有打印，没有功能 ⇒ 直接删掉。
        --   需要恢复时：git 上取本提交之前的版本，或看向导里的 `versions\019`。
        --   ⚠️ 下面「每帧点亮 face」那段是**功能**（SetVisible），保留不动。
    end
    -- ★★★★★ 2026-10-02 **每帧把格子的底图 `face` 点亮（只在关卡内）**。
    --
    --   真机证据（用户 17:05 日志，同一个 face 前后矛盾）：
    --       ✅ 子控件 face 存在（**visible=true**）   ← 体检时（`_cells_paint` 刚设完）
    --       …后面「格子里的子控件清单」…
    --       face  visible=**false**                  ← 每帧再读就变回 false 了
    --   ⇒ 中间有别的"格子外观下发"把 `face` 又设回 false（那套逻辑按状态设
    --     `note`/`x`/`wall.*`，但它**不知道 `face` 应该一直亮着**）。
    --   ⇒ 与其去改那套逻辑的每一处（容易漏、容易再引入新问题），**在这里每帧重新点亮**：
    --     这段每帧最后执行，顺序上必然赢。只在关卡内做（选关页不需要棋盘）。
    -- ★★★★★ 2026-10-02 **注意：`scr_now` 永远不会是 nil！**
    --   L620 写的是 `…controller.screen or "level"` —— 关卡内 controller.screen 是 nil，
    --   但这行把 nil 变成了字符串 "level"。所以我前两版写的 `if scr_now == nil then`
    --   **永远为假** ⇒ 这段每帧代码从来没跑过（连我加的诊断打印都没出现，原因就是这个）。
    -- ★★★★★ 2026-10-03 **移动端负载优化**：下面这段"每帧点亮 25 个 face"原本**每帧**都跑，
    --   每帧约 25×(字符串拼接 + find + GetSizeDelta + GetChildren + 若干 tostring + 约 6 次 SetXXX)
    --   ≈ **375 次 pcall**，60fps 下就是 22500 次/秒 —— PC 无感，**移动端就是掉帧/发热/耗电**。
    --   而写进去的值绝大多数与上一帧完全相同（幂等）⇒ 纯浪费。
    --   ⇒ 改成**每 30 帧跑一次**（每秒 2 次），开销降到约 1/30。
    --     正确性：引擎若在状态变化后关掉 `face`，**最多 0.5 秒后会被这段自动点亮**，视觉无感。
    --   ⚠️ 想调频率只改下面的 `30`；想恢复原行为就改成 `1`（= 每帧）。
    --   ★ 实现方式：**只改这个 if 的条件，不新增 if** —— 避免上次"新增 if 导致 end 配对错位"的坑。
    if scr_now == "level" and ((current.frames or 0) % 30) == 0 then
      local rows, cols = 5, 5
      pcall(function()
        local cfg = current.adapter and current.adapter.cfg
        if cfg and cfg.cells then
          rows = cfg.cells.rows or rows
          cols = cfg.cells.cols or cols
        end
      end)
      local n = 0
      for r = 1, rows do
        for c = 1, cols do
          -- ★★★★★ 2026-10-02 这里**不能用 `adapter:sub()`** —— 项目自己的注释写着：
          --     「`Adapter:sub()` 未命中会**永久缓存 false**，UI 就绪前查过一次就再也拿不到。」
          --   我在 `_cells_paint` 里早查过一次（那时子控件还没完全就绪）⇒ 缓存了未命中
          --   ⇒ 之后每帧 `sub()` 全部返回 nil ⇒ 这段的 n 恒为 0（所以"格子底图已点亮"没打印）。
          --   ⇒ 改成**直接遍历子控件**（含 `content` 中间容器一层），完全不碰缓存。
          local cid = "cell." .. r .. "." .. c
          local cell = nil
          pcall(function() cell = current.adapter:find(cid) end)
          -- 格子自己的实际尺寸 —— 用它去缩放 content / face / x（模板里这几个是 135×135，
          -- 而格子可能只有 124×124 ⇒ 不缩放就会溢出、把格子间的缝隙填满）
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
              -- ★★★★★ 2026-10-02 **只点亮两样：中间容器 `content` 和底图 `face`**。
              --
              --   真机截图（18:51）证据：棋盘出来了，但**每个格子都亮着红色 ✗ 和深蓝色墙线**
              --   —— 那些是"该隐藏的图层"。
              --   根因就是我上一版图省事写了"把格子的**所有**子控件统统点亮"：
              --       pcall(function() k:SetVisible(true) end)          -- ← 把 x / wall.* / note 也点亮了
              --       pcall(function() c2:SetVisible(true) end)
              --   ⇒ `x`（划掉标记）/ `wall.*` / `door.*` / `note` / `obj` 的显隐**是玩法状态**，
              --     由脚本的状态逻辑负责。**我不能替它做决定。**
              --
              --   ⇒ 现在只点亮这两样：
              --        · `content` —— 中间容器，不亮则里面全看不见（父级不可见 ⇒ 子不可见）
              --        · `face`    —— 格子底图，应该常亮
              --     其余（x / note / wall.* / door.* / obj / text）一律**不碰**。
              if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                pcall(function() k:SetVisible(true) end)
                -- ★★★★★ 2026-10-02 **中间容器要跟格子同尺寸**。
                --   真机截图（19:19）：棋盘成了一整块白 —— **格子之间没有空隙**。
                --   原因：模板里 `content` 是 **135×135**，而格子只有 **124×124**
                --   ⇒ 内容**溢出到相邻格子**、把缝隙填满了。
                --   （`face` 我上一版已经设成 124，但 `content` 和里面的 `x` 没管。）
                pcall(function() k:SetSizeDelta(cw, ch) end)
                pcall(function() k:SetAnchoredPosition(0, 0) end)
              end
              if kn == "face" then
                pcall(function() k:SetVisible(true) end)
                pcall(function() k:SetSizeDelta(cw, ch) end)
                pcall(function() k:SetAnchoredPosition(0, 0) end)
                face = k
              end
              -- ★ 划掉标记 `x`：**别顶满格子**（用户："x 也太大了"）。
              --   模板里它也是 135×135；这里按格子边长的 70% 摆。
              if kn == "x" then
                pcall(function() k:SetSizeDelta(cw * 0.7, ch * 0.7) end)
                pcall(function() k:SetAnchoredPosition(0, 0) end)
              end
              if face == nil and k.GetChildren ~= nil then
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                for _, c2 in ipairs(kk or {}) do
                  local cn = nil
                  pcall(function() cn = tostring(c2.name) end)
                  if cn == "face" then
                    pcall(function() c2:SetVisible(true) end)     -- 只点亮 face，别的孙子不动
                    pcall(function() c2:SetSizeDelta(cw, ch) end)
                    pcall(function() c2:SetAnchoredPosition(0, 0) end)
                    face = c2
                  elseif cn == "x" then
                    pcall(function() c2:SetSizeDelta(cw * 0.7, ch * 0.7) end)
                    pcall(function() c2:SetAnchoredPosition(0, 0) end)
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
  end
  -- ★★★★★ 2026-10-02 **格子底图探针**：用户看到"只有一行一列"，日志显示只有
  --   `wall.up`(上边) / `wall.left`(左边) 是 visible=true，而**格子底图 `face` 是 false**。
  --   ⇒ 这一版把 `face` 的真实情况打出来（尺寸 / 图片 / 是否被脚本设过），
  --     这样"底图为什么没铺开"就不用猜了。
  -- ★ 2026-10-03 删除「关卡内定位」诊断块（纯只读 + print）。注意：**「每帧点亮 face」那段在它外面**，不受影响。
  Murdoku._last_screen = scr_now
  current.frames = (current.frames or 0) + 1
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
-- ═══════════════════════════════════════════════════════════════════════════
-- 主页 / 选关要用的小状态（2026-09-30）
--
--   · `remember_level` / `last_played` —— 「从存档点开始」接续**最近游玩记录**
--   · `progress_of`                     —— 选关卡片显示「未开始 / 进行中 / ★ 已破案」
--   · `mark_cleared`                    —— 破案时落盘（否则卡片永远是"未开始"）
--
--   存在**局内存档**里（走适配器的 `save`/`load`），所以跨会话有效 ——
--   这正是"从存档点开始"的意义：玩家这次进来能接着上次那关。
--   取不到就是 nil：卡片只显示关名，**不编假的进度**。
-- ═══════════════════════════════════════════════════════════════════════════
local SAVE_RECENT   = "murdoku/recent"
local SAVE_PROGRESS = "murdoku/progress"

local function store()
  return prepared_adapter
end

function Murdoku.remember_level(id)
  if id == nil then return end
  local a = store()
  if a == nil or a.save == nil then return end
  pcall(function() a:save(SAVE_RECENT, tostring(id)) end)
  pcall(function()
    local p = a:load(SAVE_PROGRESS)
    if type(p) ~= "table" then p = {} end
    local cur = p[tostring(id)]
    if type(cur) ~= "table" then cur = {} end
    if not cur.cleared then cur.started = true end
    p[tostring(id)] = cur
    a:save(SAVE_PROGRESS, p)
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
    a:save(SAVE_PROGRESS, p)
  end)
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
