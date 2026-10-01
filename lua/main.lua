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
    print("[murdoku] ===== 屏幕占用排行（所有 visible=true 的控件，按面积）=====")
    do
      local list = {}
      local function walk(c, depth)
        if c == nil or depth > 6 then return end
        local v, w, h, nm = nil, nil, nil, "?"
        pcall(function() v = c.visible end)
        pcall(function() nm = tostring(c.name) end)
        if v == true then
          pcall(function()
            local a, b = c:GetSizeDelta()
            if type(a) == "table" then w, h = a.x, a.y else w, h = a, b end
          end)
          local area = (w or 0) * (h or 0)
          if area > 1000 then
            list[#list + 1] = { id = nm, w = w or 0, h = h or 0, area = area }
          end
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
      for i = 1, math.min(#list, 22) do
        local e = list[i]
        print(string.format("[murdoku]   %2d. %-22s %6.0fx%-6.0f  面积=%d",
          i, e.id, e.w, e.h, math.floor(e.area)))
      end
      print("[murdoku]   （共 " .. tostring(#list) .. " 个面积>1000 的可见控件）")
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
      local okv, oka = false, false
      pcall(function() if leaf.SetVisible then leaf:SetVisible(true) okv = true end end)
      pcall(function() if leaf.SetActive then leaf:SetActive(true) oka = true end end)
      local v2, a2 = "?", "?"
      pcall(function() v2 = tostring(leaf.visible) end)
      pcall(function() a2 = tostring(leaf.active) end)
      print("[murdoku]   手动 SetVisible=" .. tostring(okv) .. " SetActive=" .. tostring(oka)
        .. "  ⇒ 回读 visible=" .. v2 .. " active=" .. a2)
      -- 顺手把 home 容器也显形（它要是被关了，子控件画不出来）
      local hm = nil
      pcall(function() hm = ad:find("home") end)
      if hm ~= nil then
        pcall(function() if hm.SetVisible then hm:SetVisible(true) end end)
        pcall(function() if hm.SetActive then hm:SetActive(true) end end)
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
      if v == true then
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
