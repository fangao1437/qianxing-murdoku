--[[----------------------------------------------------------------------------
  entry_client_script.lua —— 客户端脚本入口（挂到客户端控件上的那个文件）

  用法：在「千星沙箱 → 客户端脚本资源管理器」里新建脚本映射，
        把它关联到本文件；然后在客户端控件（例如 root 容器）的
        「脚本」页签 → 添加脚本，选中这个映射。

  官方生命周期（运行时按固定名字查找并调用）：
    OnInit() / OnStart() / OnEnable() / OnDisable()
    OnUpdate(dt)       逐帧，**不受关卡时停影响**
    OnLevelUpdate(dt)  关卡逐帧，受关卡时停影响
    OnDestroy()

  注意：客户端控件必须挂在一个**处于激活且可见的「客户端控件容器」**里，
        否则控件找不到、脚本逻辑也不跑（官方文档明确说明）。

  ────────────────────────────────────────────────────────────────────────
  ★ 2026-09-26 **真机第一次跑通**（日志里出现 `[murdoku] 控件未找到…` /
    `started:` / `destroyed` 就说明脚本真的在执行了）。这条路走通靠三件事：

      ① `script:EnableUpdate(true)` —— 不打开的话 OnUpdate 一次都不执行
         （客户端脚本默认不参与逐帧更新）
      ② 容器的「显示常驻光标」—— 不打开的话所有点击都到不了脚本；
         本文件会尝试用 `Adapter:enable_cursor()` 自己打开它
      ③ 界面布局必须被「职业」引用一次，否则游玩时什么都没有

  ★★ 同一次事故的教训（务必别重犯）：
     `check_canvas` 里用 `%d` 去格式化 `game.GetUICanvasSize()` 的返回值，
     而真机返回的是**浮点数** → Lua 5.3 抛
     `bad argument #2 to 'format' (number has no integer representation)`
     → 因为没包 pcall，**整个 OnInit 被打断** → 适配器没建起来、配置全没生效，
     日志上表现成一大串「找不到头像卡容器 / 控件未找到」，看着像界面没搭好。

     所以本文件现在守两条纪律：
       · 打引擎给回来的数字，一律 `%s` / `%.2f`，**不用 `%d`**；
       · OnInit 里**任何诊断都不许有能力中断启动**（adapter 先建、诊断各自 pcall）。
  ────────────────────────────────────────────────────────────────────────
--]]--

-- ===== 开局关卡 =====
-- 留 nil = 用关卡注册表（levels/init.lua 的 LIST）里的第一关。
-- 打包时可以钉死：lua tools/bundle_client_script.lua --level=case_002
--   ⚠️ 正式发布不要带 --level，让它走注册表顺序。
local FORCE_LEVEL = nil

-- ===== 加载（失败也不让整个 chunk 崩掉）=====
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
local RETRY_LIMIT    = 60      -- 最多重试 30 秒
local retry_elapsed  = 0
local retry_tries    = 0

-- ===== 不依赖任何模块的原始探针 =====
-- 找一个叫 cell.1.1 / tray.A / board 的控件，把它的边长设成 v（正方形）。
-- 改"预设按钮自身"的尺寸时，它的子控件（居中锚点）会跟着位移 —— 肉眼可辨。
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

-- ===== 启动信标（默认关闭）=====
local BEACON = { OnInit = 300, OnStart = 380 }

local function beacon(a, v)
  if a == nil then return end
  -- ★ 2026-10-18 修（优化组 · 缺陷 3）：**开关在 `a.cfg.cells_beacon`**（见下面 CONFIG，
  --   经 `Qianxing.new(CONFIG)` 变成 `adapter.cfg`），而这里原来只读 `a.cells_beacon`
  --   ⇒ 恒为 nil ⇒ `nil == false` 为假 ⇒ **早退从不生效** ⇒ 信标在"默认关闭"下照样跑
  --   （它会改 `cell.1.1` 的尺寸 ⇒ 肉眼可见，CONFIG 注释写的就是"正式游玩保持 false"）。
  --   两处都认：老路径 `a.cells_beacon` 保留，任一为 false 即关 —— 这样离线夹具
  --   （直接往 adapter 上挂字段的那种）不会被误伤。
  if a.cells_beacon == false then return end
  if a.cfg ~= nil and a.cfg.cells_beacon == false then return end
  if a._cells_beacon_button ~= nil then
    pcall(function() a:_cells_beacon_button(v) end)
  end
  if a._cells_signal ~= nil then
    pcall(function() a:_cells_signal(v) end)
  end
end

-- ===== 逐帧更新开关 =====
-- ★★ 客户端脚本（Script 对象）**默认不参与逐帧更新**（updateEnabled = false），
--    运行时会直接跳过它的 OnUpdate。必须显式打开：script:EnableUpdate(true)
--    不打开的后果非常隐蔽 —— OnInit / OnStart 都正常跑、日志也正常，
--    但 OnUpdate 一次都不执行：计时不动、单击的铅笔笔记永远落不了格
--    （要等双击窗口）、等待控件就绪的惰性重试也不会发生。
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

-- ===== 画布尺寸自检 =====
-- 整套界面坐标是按**画布 1600×900**（原点左下）算的。真机如果不是这个尺寸，
-- 所有位置都会偏 —— 与其让玩家看着错位的界面猜，不如在日志里直说。
--
-- ⚠️ 这里就是那次真机事故的现场：原来用 `%d`，真机返回浮点 → 抛错 → OnInit 中断。
--    现在一律用 num()（%.0f / %.2f），外层再包一层 pcall。
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
      -- ★★★★★ 2026-10-03 **版本标记**：日志**第一行**就自报"我是哪一版"。
      --
      --   起因：改完代码、真机跑了一遍，贴回来的日志**时间戳还是上一轮的**，
      --   里面既没有新打印、`cell` 尺寸也还是旧值 ⇒ 我误以为"改动没生效"，
      --   实际是**贴了旧日志**。加这一行后，一看首行就能确认跑的是哪一版。
      --
      -- ★★★★★ 2026-10-09 **标记从 v076 直接跳到 v093 —— 中间 17 轮全丢了** ✗✓
      --   ★ 症状 ✓：`PLAN.md` D2 记的「十几次安装后无法从日志分辨版本」——
      --     标记停在 **v076**（10-05），而 `versions/` 已经到
      --     **`134-弹窗四键成型-v092`** ⇒ 中间每一轮的日志首行**都是 v076** ✓
      --     ⇒ 贴回来的日志到底对应哪一版，**根本看不出来** ✓（正是当初加标记要解决的问题 ✗）
      --   ★ 本次动作 ✓：**只把标记本身补上**（v093 = 紧随 versions/ 的 v092 ✓）
      --     —— **没有**顺手加自动化：那要改 `tools/install_script_to_sandbox.ps1`，
      --     而本文件对 BOM **极敏感**（历史事故：用 `Set-Content` 写它会加 BOM ⇒
      --     打包后 Lua 5.3 报 `unexpected symbol near '<\239>'` ⇒ `check_all` 2c 永久变红 ✓）
      --     ⇒ ★ 规则：**本文件只许用 `edit` 工具改，改完必跑 `node tools/check_encoding.mjs`** ✓
      --   ⇒ ★ 待办（`接手待办.md` P1）：把"递增标记"并进安装脚本或 `archive_version.mjs`，
      --     由工具强制递增，而不是靠人记得 ✓
      if print then
        print("[murdoku] ===== 构建标记 v321 / 2026-10-23 / 桌子换富图元 + 横竖桌缩放修正（第二关错位） =====")
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

-- ===== 适配器构造（OnInit 和 OnStart 都会用到）=====
-- 抽成函数是为了**可重入**：万一某次 OnInit 出问题，OnStart 还能自己补建一个，
-- 而不是带着 nil 往下跑（那会表现成"配置全没生效"的一大串控件未找到）。
local function build_adapter()
  if LOAD_ERR ~= nil then error("模块加载失败：" .. tostring(LOAD_ERR)) end
  adapter = Qianxing.new({
    -- 布局坐标是否由脚本接管：默认 false（推荐在编辑器里摆好位置）
    apply_rect = false,
    verbose    = false,

    -- ★★★ 2026-10-01：**从「外部资产」转存进来的图片素材**（用户给的模板索引）。
    --
    --   流程：在 https://qx.070077.xyz 用基础图元画好 → 导出 .gia → **原样**放进
    --     C:\Users\...\BeyondLocal\Beyond_Local_Export
    --   → 游戏里「导入外部资产 → 选中 → 转存所选资产」→ 进素材库
    --   → 用户把它的**控件模板索引**告诉我（下面这些数字）。
    --
    --   用法：`cfg.prefab_of[节点id] = 模板索引` + `cfg.parent_of[节点id] = 父节点`，
    --   然后 `ui_controller` 只要 push 一个同 id 的节点，适配器就会
    --   `game.InstantiateClientUIControl(索引, 父控件)` 把它造出来
    --   （这条路和「脚本生成棋盘格子」是同一条，已经跑熟了）。
    --
    --   ⚠️ **改美术要改 scene JSON**（tools/qx/scenes/*.json）再重新导出转存，
    --      **不要手改导出的 .gia** —— 我改过一次资产类型号，把一个能用的文件
    --      改成了导入会卡住的（教训记在 docs/外部资产-怎么用与我做了什么.md）。
    -- ★★★★★ 2026-10-03 **第一组改动：给三个动作键挂上「六边形按钮」素材**。
    --
    --   索引来源：用户走完「导入外部资产 → 转存所选资产」后给的 `124，含资产.gil`，
    --   用 `tools/gil/diff_ids.mjs` 比对出来（新增 1073742333~1073742354 共 22 条记录）：
    --       1073742333  murdoku-btn-hex      ← 六边形按钮（三个键共用）
    --       1073742337  murdoku-card-frame   ← 深色卡框
    --       1073742341  murdoku-cell         ← 格子
    --       1073742345  murdoku-clue-row     ← 线索条
    --       1073742349  murdoku-panel        ← 面板
    --       1073742352  murdoku-tape         ← 胶带
    --
    --   ⚠️ 原来这里写的是**猜的值** `1073742321`（第一次转存失败的那个），而且把
    --      `1073742333` 当成了"线索条" —— 两边错位。现在一律以"从 .gil 读出的真实索引"为准。
    --
    --   ★ 这一类**不进 `.gil`**（`sync_plan.mjs` 里也专门跳过 `.hexbg`）：
    --     它们由脚本按模板索引 `InstantiateClientUIControl` 现场创建。
    --     一旦 .gil 里也有同名控件，适配器 `find()` 会先找到那个"编辑器里的空控件"，
    --     于是永远不走实例化 ⇒ 画面上是一块空白。
    prefab_of = {
      -- 六边形按钮底图（三个动作键共用一张素材）
      ["action.back.hexbg"] = 1073742333,
      ["action.redo.hexbg"] = 1073742333,
      ["action.hint.hexbg"] = 1073742333,
      -- 深色卡框（主页 / 选关的背景大板）—— 下一组再启用
      ["home.panel"]   = 1073742337,
      ["select.panel"] = 1073742337,
    },
    parent_of = {
      ["action.back.hexbg"] = "action.back",
      -- ★ 已删：action.redo / action.hint 的底图（父控件本身已从存档里清掉）

      -- ★★★★★ 2026-10-04 **14 个 id 全部显式挂 `root`** —— 修"位置还不对"。
      --
      --   真机日志的**点击坐标**两轮几乎一样（v050 与 v051），说明改规划父级无效：
      --       hit.hint 点击 (1573,195)（规划 1483,171）⇒ +90,+24
      --       hit.undo 点击 (1585,638)（规划 1483,625）⇒ +102,+13
      --   而 `stage` 的偏移正是 (+100,+20) ⇒ **运行时以 `root` 为参照**，
      --   真实父级 `stage` 又叠了一层 ⇒ 必须让**真实父级也是 `root`**，两层才抵消。
      --   ⚠️ 早前"挂 root 就看不见"的判断是错的：那时图标用格子模板（face 尺寸 0）；
      --      现在贴图走纯图片模板，挂 root 既可见、位置又对。
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

    -- 诊断信标：正式游玩保持 false（会改控件尺寸，肉眼可见）
    cells_beacon = false,

    -- ★ 运行时光栅：格子都在编辑器里摆好了 → 完全不需要模板，
    --   脚本只做「把每格摆正」，缺格子时才去找模板索引。
    --
    --   ⚠️ 模板索引指向的是**「另存为模板」那一刻**的快照。之后又给格子加了
    --   底图/子控件的话，必须**重新另存一次**，否则副本全是透明的。
    --
    --   ★ size / pitch / margin 不写死：运行时读 board 的实际尺寸算出来，
    --     所以 5×5 / 6×6 / 7×7 共用同一套编辑器控件。
    -- ★★★★ 2026-10-02 **容器模板**（用户在编辑器里新建并给了索引 1073742330）。
    --
    --   有了它，脚本就能**自己创建容器**（而不只是按钮）—— 这是"重建"的关键：
    --   编辑器里只留 `home` + `stage` + 三个模板引用，其余界面**全部由脚本在 `stage` 下创建**。
    --   `stage` 本身是空的、干净的，没有任何历史包袱（旧容器 `select`/`board`/… 已全部删除）。
    -- ★★★★★ 2026-10-02 **回滚开关**：恢复 93 的布局时，把脚本自动创建关掉。
    --
    --   背景：重建期间编辑器控件被删，脚本只能用"按 kind 选模板"临时把 108 个控件造出来，
    --   但脚本只有两个模板 ⇒ 造出来全是白块，而且把用户精心摆的界面（含素材）盖掉了。
    --   现在改成**以 93.gil 为基底**（它有全部控件和素材）+ 把 97 的 stage 三条搬回来，
    --   ⇒ 界面控件重新由编辑器提供 ⇒ **自动创建必须关掉**，否则又是一堆白块。
    auto_create = false,   -- true 才让 create_control 按 kind 自动实例化（全局开关，保持关）
    -- ★★★★★ 2026-10-09 **白名单整段删掉** —— 那 14 个控件已经**搬进存档**了 ✓
    --
    --   用户 2026-10-09 拍板：「**同意搬 1，然后 2，3 保持脚本**」✓
    --     · 搬 1 = `hex.*` ×7 ＋ `hit.*` ×7（**固定不变** ⇒ 该进存档 ✓）
    --     · 留 2 = `selbtn.*`（随关卡数变 ⇒ 脚本建 ✓）
    --     · 留 3 = `cell.*`（引擎按索引克隆 ⇒ 脚本建 ✓）
    --   搬法见 `tools/gil/gen_icons.mjs` ✓ 产物 `230-图标搬进存档.gil` ✓
    --     · `hex.*` ← 克隆 `cell.1.1.content.face`（**纯图片**，能渲染、收不到光标事件 ✓）
    --     · `hit.*` ← 克隆 `home.select` 且**不建 bg/label**（点击照收、什么都不画 ✓）
    --     · **顺序**：hex 先、hit 后 ⇒ 热区在上，射线不会被图片控件吞掉 ✓
    --
    --   ⇒ ★ 所以这份 `auto_create_only` 白名单**已经没有用了** ✓
    --     实测印证：`check_names` 报的「🟢 脚本会自动建」从 **14 → 0** ✓
    --     而且适配器那段本来就"**先找、找不到才建**" ⇒ 存档里有了就只走"找到" ✓
    --   ⇒ ★ 删掉它 = 少一处会漂移的配置，也少一条"脚本偷偷造控件"的路 ✓
    --     （`auto_create = false` **保留** ✓ —— 那条全局开关还有意义：
    --      它是"绝不让脚本按 kind 造一堆白块盖住界面"的底线 ✓）

    -- ★★★★★ 2026-10-03 **图标专用模板**（用户 20:45 提供索引 **1073742356**）
    --
    --   为什么要换掉格子的模板：`cfg.cells.prefab = 1073741876` 建出来的控件
    --   **自带一整套格子子控件**（`content` / `wall.up` / `wall.left` / `note` / `x` …）。
    --   真机日志的证据有两条：
    --     · 七个 `hex.*` 建出来后，各自的 `wall.up` / `wall.left` 都是 visible=true
    --       ⇒ 画面上多出 7 个"迷你格子"，**把棋盘搅乱**（用户报"棋盘也没出现"）；
    --     · 「图片控件」`face` 在格子的体检里是**直接子控件**，但在 `hex.*` 这棵树上钻不到
    --       ⇒ `SetImage` 只能落到 `content`（中间容器）上 ⇒ 回读正确但不显示。
    --
    --   ⇒ 用这个干净的客户端模板（里面只有图片节点、**用户没做静态引用**），
    --     由脚本 `SetImage` 把官方素材打上去（适配器里那段递归找图 + SetImage）。
    --
    --   ⚠️ 索引将来变了只改这一行。
    --   ⚠️⚠️ **2026-10-03 20:48 真机实测：这个索引用不了。**
    --     日志：`自动创建 hex.back 失败（模板 1073742356）err=nil`（七行全失败）
    --     ⇒ `pcall` 成功、`InstantiateClientUIControl` **返回 nil**
    --     ⇒ 它和 `m` 的 `1073742380` 一样，是**服务器控件模板**，
    --        官方明说「服务器控件的模板索引无法被客户端脚本调用」（见
    --        docs/客户端控件vs服务器控件.md）。
    --
    --   ⇒ 要用脚本创建，模板**必须**在
    --       「界面控件组管理 → 界面控件组库 → **客户端控件模板** → 添加客户端控件 → 存为模板」
    --      那条路里做（格子的 1073741876 就是这么来的）。
    --     做出来之后把索引填到这里，并把下面那行 `prefab_icon = nil` 改成索引即可。
    --   ★ 2026-10-03 20:57 **用户提供的可用索引 = 1073742357**（模板名就叫 `hex`，纯图片、空壳）
    --     它是在**客户端控件容器里**另存的 ⇒ 属于「客户端控件模板」⇒ 脚本能实例化。
    --     （1073742356 是在 root 下另存的 ⇒ 服务器模板 ⇒ 返回 nil，已作废。）
    prefab_icon = 1073742357,
    -- ★★★★★★★★ 2026-10-16 **`geom_by_editor`：把位置/尺寸交回编辑器** ✗✓✓
    --   ★ 用户原话 ✓：「★ **把我调整过的东西那里的相关位置大小调整脚本关掉，交由编辑器决定**」✓
    --   ★ `true` ⇒ ★ 脚本**不再抢**这些几何 ✓：
    --     · `stage`（棋盘容器）—— ★ 建控件前那段 ＋ `on_update` 每帧兜底那段，**两处都跳过** ✓
    --       ⇒ ★ 编辑器里把 stage 调多大，棋盘就是多大 ✓（★ 格子尺寸是按 stage 尺寸算的 ✓）
    --     · `settle.btn`（结算按钮）—— ★ 那一段（含探针）**整段跳过** ✓
    --   ★ `false` ⇒ 恢复旧行为（强制 584×584 @ (100,20) ／ 结算按钮那两个数 ✓）
    --   ⚠️ ★ **这是"把权威交出去"的开关，不是"关掉功能"** ✓：★ 几何仍在，只是改由**编辑器**给 ✓
    --     ⇒ ★ 你在编辑器里调一次就永久生效，脚本之后再也不会覆盖 ✓
    --   ★★★★★★★★ 2026-10-16 **v248：这个开关现在【真的】管住了全部四条路** ✗✓✓
    --     ★ 上一版（v246/v247）只覆盖 `main.lua` 的四处 ✓ —— ★ 而**真正在覆盖的是
    --       规划侧那条**（`ui_controller` 的 `rect` ＋ `pos_runtime` ⇒ `adapter.runtime_rect`）✗
    --     ⇒ ★ 模拟器实测：`select.card.1` 编辑器 `208.98×291.6` ⇒ 运行时 **`233×324`** ✗
    --       （= 规划里那份 100% 的卡 ✓）；`clues.grid` 编辑器 `360×490` ⇒ 运行时 `400×544` ✗
    --     ⇒ ★ v248 起：★ **继承来的 `pos_runtime` 一律不受理** ✓（显式 `true` 仍然受理 ✓
    --       例如房间名标签、缩略图色块、脚本自己建的格子 ✓）
    --     ★ 同时修掉一个 Lua 语义错 ✓：`inherit_pos_runtime` 里原来用 `not n.pos_runtime`
    --       判"没表态" ✗ —— ★ **`not false` 也是 `true`** ⇒ ★ 显式写 `false` **拦不住继承** ✗
    --       （`clues` / `clue.*` 就是这么被接管的 ✓ 用户原话「网格视窗的大小我已经改了」✗）
    -- ★★★★★★★★ 2026-10-16 **v253：`geom_by_editor` 这个开关【已删除】** ✗✓✓
    --   ★ 用户指令 ✓：「把所有失效的几何/文字脚本代码从脚本中删除」✓
    --   ★ 它为什么失效 ✗：★ `render` 现在**只看两件事** ——
    --     ① 控件是不是脚本建的 ✓ ② 有没有**显式**写 `pos_runtime = true` ✓
    --     ⇒ ★ "归编辑器"已经成了**默认** ✓ ⇒ 不再需要这个开关去"关掉接管" ✓
    --   ★ 位置/尺寸从哪来 ✓：★ **全部以 `.gil` 为准** ✓
    --     ★ 适配层的 `respect_editor_rect = true`（见下 ✓）是第二道闸 ✓
    --   ★ 仍然由脚本摆的那几类 ✓（★ 别当死代码删 ✓）：
    --     ★ 房间名标签 / 选卡文字与附件 / 房间缩略图 / 确认卡与其热区 / 脚本实例化的 `cell.*` ✓
    -- ★★★★★★★★ 2026-10-16 **v252：这些控件的文案"编辑器优先"** ✗✓✓
    --   ★ 用户原话 ✓：「★ **让所有按钮的文本内容也交由编辑器** ✓
    --     ★ **你如果能直接填内容进控件你就填，不能就把位置告诉我**」✓
    --   ★★ 答复（先说结论 ✓）：★ **`.gil` 存不下控件的文字** ✗ ——
    --     ★ 只读实测：`node tools/gil/_probe_texts.mjs 393.gil` ⇒
    --       ★ **338 条记录里，一条"非名字文本"都没有** ✓（与项目 2026-09-28 的结论一致 ✓）
    --     ⇒ ★ **填不了** ✗ ⇒ ★ 只能**在编辑器里逐颗填** ✓（★ 要填哪些：见本名单 ✓
    --       ＋ 回执 §〇·补5 那张表 ✓ —— ★ 你已经填好的 **主页四键** 就在名单里 ✓）
    --   ★ 语义 ✓：★ 名单里的控件 ⇒ ★ 脚本**只在它当前是空的时候**才写 ✓
    --     ⇒ ★ 你填过 ⇒ 脚本一个字都不动 ✓✓；★ 没填 ⇒ 仍然有字（兜底 ✓ 界面不会空 ✓）
    --   ⚠️ **不在名单里的**（★ 这类**必须**由脚本写 ✓ 别加进来 ✗）：
    --     ★ `select.card.*.title` / `.info`（每关现算 ✓ 会随翻页变 ✓）
    --     ★ `clues.*` 的计数、`hud.timer` / `hud.progress`（每秒在变 ✓）
    --     ★ `clue.N.*` 的字母（分级现算 ✓）、`modal.stats`（用时/步数 ✓）
    --     ★ `modal.title`（"恭喜破案" / "没能找齐所有人" **两态** ✓ —— ★ 编辑器只能存一份 ✗）
    text_editor_first = {
      -- ★ 首页四键（★ 你 2026-10-16 已经填好了 ✓）
      "home.select", "home.continue", "home.shop", "home.bag",
      -- ★ 结算键
      "settle.btn",
      -- ★ 返回弹窗四键
      "modal.exit", "modal.save", "modal.settle", "modal.cancel",
      -- ★ 通关弹窗四键
      "result.next", "result.exit", "result.home", "result.settle",
      -- ★ 线索区上下箭头（老路径，留着）
      "clues.up", "clues.down",
      -- ★ 通关弹窗的**分析标语区**（★ 每关一颗 ✓ 你要填的就是这四颗 ✓）
      --   ★ 父级 `win`、子控件 `win.1..win.4`（= 第 1..4 关 ✓ 顺序与关卡注册表一致 ✓）
      --   ★ 脚本只在"它是空的"时候写兜底 ✓ ⇒ ★ 你填了就以你的为准 ✓
      "win.1", "win.2", "win.3", "win.4",
    },
    widgets     = false,   -- ★★★★★★★★ 2026-10-15 **关掉：四个方块删掉** ✗✓✓
    --
    --   ★★★ 用户原话 ✓：「**把原来四个方块删掉**」✓（★ 功能已通过的下一句 ✓）
    --
    --   ★ 那四个方块是什么 ✓：★ 脚本**运行时**用容器模板现建的
    --     `selbar`（容器）＋ `selbtn.1..4`（四个按钮）✓
    --     ★ 它们是"卡片还点不动"那段时间**唯一能完成选关的路** ✓
    --       （★ 102 那轮验证过"能完成选关" ✓ 见旧注释 ✓）
    --   ★★ 为什么现在可以删 ✓：★ **选关卡片已经能点了** ✓
    --     （★ 用户真机确认「功能通过了」✓ —— 命中层被 `"hit."` 前缀藏掉那件事修好之后 ✓）
    --     ⇒ ★ 两套入口并存 ⇒ ★ 玩家会看到**重复的四块白方块**压在卡片上 ✓
    --
    --   ★★ 关掉这一个开关 = **两件事一起停** ✓（main.lua 里两处都读它 ✓）：
    --     · `main.lua:560` ⇒ **不再调 `ensure_widgets`** ✓ ⇒ `selbar`/`selbtn.*` **根本不建** ✓
    --     · `main.lua:1524` ⇒ `on_select` 恒假 ⇒ **不再每帧同步它们的显隐** ✓（省下每帧的 find+写 ✓）
    --   ★ 判据 ✓：`tests/perframe_throttle.lua` §A 已改成
    --     「**`selbar` 压根不该存在，也不该有一笔同步**」✓（★ 跟着**意图**改 ✓ 不是放宽 ✓）
    --   ⚠️ 要回退 ✓：★ 把这一行改回 `true` 即可 ✓（脚本一个字都不用动 ✓）
    --
    --   ★ 顺带 ✓：★ `selbtn.*` **从来不在 `.gil` 里** ✓（实测 `list_names 370 | sel` 里没有 ✓）
    --     ⇒ ★ 所以"删掉"就是"不再创建" ✓ ★ **不需要动存档** ✓✓

    stage = {
      prefab = 1073742330,   -- 「容器节点」模板（用户 2026-10-02 提供）
      parent = "stage",
      selbar = "selbar",     -- 脚本创建的第一个容器：选关条
    },
    cells = {
      --
      --   2026-09-26 15:46 真机：`cell.1.1` 另存出来的模板索引 = **1073741876**。
      --   注意它**不一定就是可用**的 —— 要看它属于哪套资产体系：
      --   官方硬约束是「只有**客户端控件模板**里的控件，其模板索引才能被客户端脚本调用」。
      --
      --   所以这里填上以后，日志里会看到脚本**先试这个数字**；
      --   如果仍然 `全部实例化失败`，说明它不是客户端控件模板 → 去
      --   界面控件组管理 → 界面控件组库 →「客户端控件模板」→ 添加客户端控件 → 存为模板，
      --   再用那个新索引替换这一行。
      prefab   = 1073741876,

      -- ★★★★★ 2026-10-04 **棋盘几何全部改成"规划图 v3 量出来的显式值"。**
      --
      --   之前的推导链有个**根本错误**：一直拿 `M.LAYOUT.board = 812` 当基准，
      --   而 812 是**当初按"812÷5=162.4"推出来的，并不是量出来的** ——
      --   实际去量 `docs/布局图-关卡内-v3.png`（1600×900，已经是画布空间）：
      --     外框 x 608..1191、y 138..721  ⇒ **584 × 584**（比 812 设计 = 676.7 画布**小 93px**）
      --     边框四边**均匀 14px**
      --     内区 584−28 = 556 ⇒ `5c + 4×4 = 556` ⇒ **格 108、缝 4** ⇒ **pitch 112**
      --   ⇒ 这就是用户说的「**底板溢出边框了**」—— 677 的底板套 584 的框，当然溢出。
      --
      --   ★★ 2026-10-04 追加纠正（逐像素测量）：图上棋盘画的是 **6×6**，不是 5×5！
      --     外框 584 固定、**边框四边均匀 12px**（我第一版量成 14，因为把内侧那条 2px
      --     网格线算进边框了）、内区 = 584−24 = **560**、缝 **4px**：
      --       N=6：pitch = 560/6 = **93.33**（图上实测 93/94 交替）、格 = 89.33（实测 89/90）✅
      --       N=5：pitch = 560/5 = **112**、格 = **108** ← 本项目现在跑的就是这个 ✅
      --     ⇒ **"棋盘外框固定、格子按关卡实际 N 自适应"这条设计成立**
      --       （`cell_geometry` 本来就是按 N 算的）—— 所以**不要**把 pitch/size 写死，
      --       否则 6×6 / 7×7 的关卡会排错。只有 `ruler`(边框) 和 `gap`(缝) 是常量。
      --
      --   ⇒ 最终就两项显式值：
      ruler    = 12,           -- 边框厚度（画布空间）—— ★ 注意 `cell_geometry` 现在**两边各扣一份**
      gap      = 4,            -- 格子之间的缝（= 图上 4px 网格线）
      --
      --   （pitch / size / margin 故意**不写**：让 `cell_geometry` 按关卡 N 自动算。）
      --
      -- ★★★★★ 2026-10-03 "A 方案：留缝做网格线"（用户 22:54 提出并确认）—— **思路保留，数值已作废**。
      --
      --   思路（仍然成立）：`size` 比 `pitch` 小一点，露出的缝由 `stage` 的深色底板填
      --   ⇒ **天然网格线，0 个额外控件**，移动端无负担。
      --
      --   ⚠️ 但那一轮的数字（pitch 135 / gap 6 / size 129 / 底板 677）是**按没量过的 812 推的**，
      --      2026-10-04 去量了 `docs/布局图-关卡内-v3.png` 之后全部作废 ⇒
      --      改成上面那组显式值（pitch 112 / size 108 / gap 4 / margin 14 / 底板 584）。
      --
      --   ★ 这里原本还有一行 `gap = 6` —— **已删**。它和上面新写的 `gap = 4` 是**同一个表的重复键**，
      --     而 Lua 是"后写的赢" ⇒ 不删的话新值会被它静默覆盖（这个坑本项目已经踩过一次：
      --     当年的 `ruler = 0` 就是这样被 `ruler = 37` 吃掉的）。

      -- ★★★★★ 2026-10-04 **格子底图（`face` 的素材）= `100001`「基础形状·正四边形」。**
      --
      --   用户 2026-10-04 说：「我把格子换成了正四边形，已经存入模板了」，并给了新存档 `165.gil`。
      --   我把那份存档和上一版 `完整界面165-底板修正.gil` **逐控件按 id 对字段**，
      --   结果是 **94 条记录里只有 1 个控件的字段变了**：
      --       `id=1073741882  name=face`（格子 `content` 里的图片控件）
      --       `imageId`：**106053 → 100001**
      --   ⇒ 用户换的就是这张图。`100001` 属于「基础形状」类，是 **256x256 纯白满方块**
      --     （实测：覆盖率 1.000、色彩标准差 0、全不透明）—— 这就是"正四边形"。
      --
      --   ★★ **但在编辑器里换是不生效的**：`_cells_paint` 每次生成格子都会
      --      `face:SetImage(nil, cfg.cells.face_image or 106053)` —— **脚本会把编辑器里的选择覆盖掉**。
      --      所以必须在这里显式写 `face_image = 100001`，否则跑起来还是 106053（圆角白牌）。
      --
      --   ★ 顺带一个好消息：格子 `face` 的 `imageType` 是 `Stretch`（模板里设的），
      --     所以这也能**顺便验证 `100001` 能不能拉伸** —— 能拉伸的话，底板将来也能换它。
      face_image = 100001,

      -- prefab 为 nil 时才会看这里：从参照格子（下面的 probe）自己的 prefabIndex 读。
      --
      -- ★ **纯模板模式**下 probe 可以不存在 —— 编辑器里一个真格子都不建，
      --   只在 board 下放一个 `tpl.cell`（模板引用控件）。这时：
      --     · 缺格子数 = rows×cols（全部由脚本生成）
      --     · 参照格子为 nil → 不做图片盖章，副本外观**完全取自模板快照**
      --     · 体检会明确说"纯模板模式"而不是报"找不到控件"
      probe    = "cell.1.1",
      -- ★★★★★ 2026-10-02 **必须是 "stage"，不能是 "board"**（我上一轮改错了）。
      --
      --   103.gil（= 能点的那个干净底座）的 root 子级只有：
      --       `tpl.cell  tpl.stage  stage  home`   —— **没有 `board`**（重建时被删了）
      --   我为了"回滚到 93 布局"把这里改成 "board"，而当时导入的是 103 结构
      --   ⇒ 真机日志："生成格子失败：找不到父控件 board"（16:11 那份）。
      --   ⇒ 改回 `stage`（103 里存在，且是脚本创建的容器的家）。
      --
      --   注：93 那套"把编辑器容器全搬回来"的做法**已经被证明会让人点不动**
      --   （root 子级从 4 个变成 37 个 ⇒ 那批全屏容器把射线抢走了）。
      parent   = "stage",
      -- ★★★★★ 2026-10-04 **这一格原本还有一行 `ruler = 37` —— 已上移到「棋盘定型」那段，只留一处。**
      --
      --   原来 `ruler` 在这个表里**被赋值两次**（上面的 `ruler = 0` 和这里的 `ruler = 37`），
      --   而 **Lua 表构造器是"后写的赢"** ⇒ 生效的其实一直是 `37`，
      --   上面那行 `ruler = 0` 是**死配置**。现在删掉了错的那行（0），把 37 提到上面去，
      --   并把"为什么是 37 而不是 0"的判据写在那一处（结论：**37**，因为要跟
      --   `ui_controller` 的 `avail = board.w - ruler` 对齐）。
      --
      --   量出来的证据也在上面那段：截图实测 pitch 127.5 / 格子 123 / 左边框 43 / 右边框 2，
      --   与 `ruler = 37` 的预测**四项全中** ⇒ 布局图的设计值就是现在这样，不是 bug。
      --
      --   ⚠️ 教训：**同一个表里别重复写同一个键**。这两行互相矛盾、后写的静默获胜，
      --      让人以为"代码写的是 0"，实际跑的是 37 —— 排查几何问题时极容易看错方向。
      -- ⚠️ 不要写死 gap：它由 `max(2, ⌊pitch*0.03⌋)` 算出来，和 ui_controller
      --    里那套是同一个公式；写死会让两处差 1~2px。
      rows     = 5,            -- 只在读不到父控件尺寸时才用到的兜底
      cols     = 5,
      debug_signal = false,
      -- 扫全树：把所有"与参照格子不同的 prefabIndex"也当候选（排在最后，逐个真试）
      auto_scan = true,

      -- ★★ 墙 / 门的**目标厚度**（画布单位）—— 让"多粗"变成一个确定数字。
      --
      -- 为什么需要：真机实测「图片类型 = 基础」的图**按原尺寸画、不填充控件**，
      -- 而「拉伸」只有部分素材支持。所以脚本改用 `localScaleX/Y` 缩放来适配。
      -- 这里给出**目标几何**，脚本按 `目标 ÷ 基准` 双向求倍率 ——
      -- 于是最终看到的墙一定是「格子边长 × 本厚度」，跟你素材多大无关。
      --
      -- 前提：墙/门控件的尺寸**别手动改**，让编辑器按素材自动定（= 素材原尺寸）。
      -- 脚本第一次试玩会把基准与倍率打进日志，可以核对：
      --   [murdoku] 边缘适配 wall.up：基准 80x20 → 目标 99x10（倍率 1.24 / 0.50）
      --
      -- ★★★★★ 2026-10-18（v266）用户原话：「**位置对了，再把门墙加粗 2 加长 4**」
      --   ⇒ 这一版的四个数就是全部真相（改观感只动这四个，不用碰脚本逻辑）：
      --       厚：8 → **10**（thickness，墙门同厚 ✓）
      --       长：墙 = 格子 + 缝补 4 + **额外 4** = **格子 + 8**；门 = 格子×0.30 + **额外 4**
      --   实机一旦再调，只改下面 4 行；`tests/wall_overlap.lua` §③ 钉着这组数 ✓
      edge_thickness = 10,
      -- 门比墙短一点（占格子边长的比例），看起来才像"门"
      -- ★ 2026-10-17：0.45 → **0.30**（对齐设计图：门只是墙线上的**一小段**橙标 ✓）
      -- ★ 2026-10-18（v266）用户原话：「**门也改 0.44**」⇒ 0.30 → **0.44**（设计图实测 44.1–44.5%×格）
      door_length_ratio = 0.44,
      -- ★ 缝补：墙在"格子边长"之外多出的长度（相邻两格在角上重叠，填掉缝）
      --   ★ 2026-10-18 之前是 4；v266 墙再加长 4 是通过下面的 `edge_extra_len` 实现的 ⇒ 这里保持 4
      edge_overlap = 4,
      -- ★ v266 用户要的「加长 4」：**墙和门一起** +4 画布 px（墙最终 = 格子 + 4 + 4；门 = 格子×0.30 + 4）
      --   ⚠️ 不要把它并进 `edge_overlap` —— 那个只作用于墙，并进去门就加不长了 ✓
      edge_extra_len = 4,
      -- 边缘适配的日志每个方向只打一次（调完可设 false 关掉）
      edge_fit_log = true,

      -- ★★ 图层顺序（**从下到上**）。
      --
      -- 用户 2026-09-27 提醒：图片/文本之间的层级**由模板里的位置（同级次序）决定**，
      -- **不看创建或生成顺序**，而且**图层会互相覆盖** —— 所以必须规划。
      --
      -- 官方给了控制手段（客户端控件基类）：`SetSiblingIndex(i)`「数值越大通常越靠后、
      -- **显示越靠上**」、`SetAsFirstSibling()`、`SetAsLastSibling()`。
      -- 脚本按下面这份列表**从下往上**重排一遍，于是最终层叠**不依赖编辑器里的摆放次序**
      -- （那个仍然作为默认值；顺序改这里就行，不用回编辑器调）。
      --
      -- 规划理由：
      --   face  最底 —— 它是格面底图，也是"放置角色"时被换图的那张
      --   ★ hint 2026-10-17 新增 —— 线索位置提示的**半透明底色**：压在格面之上、
      --     **在家具图标之下**（用户要求"家具不要被提示盖住"✓ 颜色归编辑器 ✓）
      --   obj   在底图之上 —— 家具图标要能看见
      --   wall  压住底图 —— 墙贴在格子边上，必须显出来
      --   door  压住墙 —— 同一段边可能既是墙又是门，门要在墙上面
      --   x     划掉标记压住一切装饰
      --   note  铅笔笔记最上 —— 玩家写的信息永远可读，不能被图挡
      layer_order = {
        "face",
        "hint",
        "obj",
        -- ★★★★★★★★ 2026-10-22（v301）**家具 = 最多 12 层**（第三轮美术）✗✓
        --   第一轮 3 层（用户打回"像色块 / 跨格被拆开"）→ 第二轮 6 层 → 本轮按原作部件表逐件照搭。
        --   用户原话：「其它家具的细节保留（包括阴影），**横桌竖桌明显需要分开做**；图层3是肯定不够了，
        --   **你可以任意添加**」⇒ 层数上限一次给到 **12**（模板 `obj`…`obj12`）。
        --   件数：桌 7（另有横放 h2 / 竖放 v2 两套独立美术）/ 椅 9 / 书架 12 / 植物 12 / 雕塑 8。
        --   数据在 `lua/furn_art.lua`；12 层控件由存档模板给（`tools/gil/gen_art_containers.mjs` 的 v2 版）。
        --   ⚠️ 老存档只有 3/6 层时，`_paint_obj` 拿到 nil 会当"还没就绪"逐帧重放（幂等，不报错）。
        "obj2", "obj3", "obj4", "obj5", "obj6",
        "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",
        -- ★★★★★ 2026-10-20（v283）**新增 `portrait` 层：放置的头像画在这里** ✗✓
        --   用户原话：「现在家具图层会盖在放置的头像上，把这个问题解决」
        --   · 旧：头像走 `image` 落在 **face（最底）** ⇒ 家具 `obj` 压在上面 ✗
        --   · 新：头像落在 `portrait`，位置 = **obj 之上、wall 之下** ⇒ 头像压住家具、又不压墙 ✓
        --   房间色仍留在 face（`tint` 写），所以格子底色不会丢 ✓
        --   ⚠️ 这一层在存档里是**新加的控件**（克隆自 face，两份 content 各一份，
        --      id 1073743800 / 1073743801，见 `tools/gil/gen_portrait_layer.mjs`）✓
        "portrait",
        "wall.up", "wall.down", "wall.left", "wall.right",
        "door.up", "door.down", "door.left", "door.right",
        "x",
        "note",
      },
    },

    -- ★★ 调试开关（**必须放在 cfg 顶层**，不能放进 cfg.cells 里！）
    --
    -- ★★★ 2026-09-29：**编辑器布局优先**（放在 cfg 顶层，与 cells 平级）。
    --   默认 true ⇒ 存档里已有的控件保持**你在编辑器里调的几何**，
    --   脚本只摆"自己运行时生成的控件"（格子等）。
    --   想回到"布局全由代码说了算"：改成 false。
    respect_editor_rect = true,

    -- ★★★★★★★★ 2026-10-22（v302，第四轮）**图元拼法家具的运行时模板** ✗✓
    --
    --   用户原话：「桌子椅子植物依然没有达到参考效果，仓库里有一个能兼容千星的外部图片网站，
    --     **你先用他把参考拼出来，再按结果文件拆解出正确拼法导入存档**」
    --   ⇒ 用「千星奇域拼图工具」把原作图标拟合成图元（每件 151~200 条，含旋转 + 逐图元 RGBA），
    --      结果文件由 `_work/art-tools/gen_art_records.py` 拆成 `lua/furn_art_records.lua`，
    --      游戏里由适配层 `_paint_furn_art` **逐条运行时实例化**图片控件来画。
    --   · `furn_prim_prefab` = 存档里「仅存为模板」的图片控件 **tpl.prim 的模板源 GUID**
    --     （integrator 交付的 `502-一二关美术-容器-v3.gil`：模板源 #1073746302 / 母本 #1073746303 / 族 78）。
    --     适配层优先用这个值；为 0/nil 时回退到"按名字找 tpl.prim 再读 prefabIndex"。
    --   · `furn_prim_cap` = 每格最多几条图元（防止极端情况把帧率拖死；超出的截掉）。
    --   · 宿容器 = 格子 `content` 下的 `furn`（502 新增，位置在 obj12 与 x 之间 ⇒
    --     家具压住地板、但仍在墙/门/笔记/头像之下）。
    furn_prim_prefab = 1073746302,
    furn_prim_cap = 260,

    -- ★★★★★★★★ 2026-10-22（v310，第十三轮）**家具模板（客户端控件模板）** ✗✓
    --   用户：「采用模板来手搭构建，模板里放多少层都可以（一个模板引用控件只算一层），
    --   然后像 cell 一样把模板创建出来」。
    --   键与 `FurnArt.layout().pieces` 对齐：chair / plant / statue / shelf 单格；table 有 1/h2/v2。
    -- ★ v316：换成 524 里"用户编辑器建的空模板"真实源 GUID（integrator 524 回执）
    --   主路径是从 `root/things` 的引用控件读 `referencedPrefabIndex`；这张表只作回退。
    furn_tpl_prefab = {
      chair    = 1073747134,
      plant    = 1073747135,
      statue   = 1073747136,
      table    = 1073747137,
      table_h2 = 1073747138,
      table_v2 = 1073747139,
      shelf    = 1073747140,
      rug      = 1073747149,
      rug_2    = 1073748252,
    },
    furn_parent = "fart.furn",   -- 实例挂载容器（root 下，默认隐藏；关卡内由脚本打开）
    furn_tpl_base = 108,
    -- ★ v320：模板 content 画布尺寸（键 = 归一化家具键）。缺省 108×108；
    --   多格地毯模板是 216×108，竖放时实例 108×216 ⇒ 子层按 fx/fy 各向异性缩放。
    furn_tpl_canvas = { rug_2 = { 216, 108 }, table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },

    -- ★ 2026-10-22（v311）**模板探针**：只回答两个问题，结果全在日志（前缀 `[tplprobe]`）
    --   ① 模板里的模板引用控件（第二层）能不能正常展开；
    --   ② 客户端脚本能不能在运行时改引用控件引用的模板。
    --   测试存档里把 tpl_probe 改 true；GUID 由 integrator 的 516 存档给出后填。
    tpl_probe = false,
    tpl_probe_ref_name = "furn",      -- 要摸的模板引用控件名（cell.1.1/content/furn）
    tpl_probe_plant_src = 1073747081,   -- furn.plant 的**源** GUID（integrator 516 实测：引用值指向源）
    tpl_probe_nest_src = 1073747096,    -- furn.nest 的源 GUID
    tpl_probe_parent = "board",         -- 模板层基准画布像素（1 格 = 108px）

    -- ★★★★★★★★ 2026-10-18 **家具/障碍物素材：直接写在脚本里，不新建控件** ✗✓✓
    --
    --   用户实测（关键判据）：「**395 是没错的**」「错误从 **396** 就存在」
    --   —— 396 正是我第一次在**存档里新建** `things` 素材区（7 个新控件）的那一版 ✗
    --   ⇒ 只要**不新增控件**，编辑器就不会报 "GUID 重复" ✓
    --
    --   ★ 家具图标本来只需要「一张图 + 一个颜色」两件事 ✓ ⇒ 放脚本里足够了 ✓
    --   · `id`  = 官方素材 id（100001 = 白色矩形，着色后就是干净色块）
    --   · `color` = 0xAARRGGBB（与 `imageColor` 同格式，乘算）
    --   ★ 优先级：编辑器里若**真有** `things` / `assets` 下的同名控件，**以控件为准** ✓
    --     （见 `Adapter:read_palette`：控件先扫，这里只补缺 ✓）
    --   ★ 换真素材：把 `id` 换成编辑器素材库里的图即可（不用动存档）✓
    -- ★★★★★★★★ 2026-10-22（v299）**家具 = 多层拼装（复刻原作的双层剪影美术）** ✗✓
    --
    --   原作 Murdoku 的家具是「base 剪影 染 obj_color_base ＋ overlay 剪影 染 obj_color_overlay」，
    --   两色叠出体积感。官方素材库里没有俯视家具 ⇒ 我们用「官方基础形状 × 3 层」拼：
    --     L1 = 深色外形（充当描边/木框）  L2 = 主体  L3 = 细节
    --   层控件由存档模板给（`obj` / `obj2` / `obj3`，见 `tools/gil/gen_obj_art.mjs`）。
    --
    --   字段：`id` 官方素材 id；`color` = 0xAARRGGBB（**与素材乘算**，白色底板才上得去亮色）；
    --        `w/h` = 相对格子边长的比例（缺省 1 = 铺满）；`dx/dy` = 相对格子边长的偏移
    --        （**dy 正 = 向下**）。
    --   ★ 第 1 层的图/色仍可在编辑器里改（`things/obj.<kind>` 优先），几何以本表为准。
    obj_art = {
      table = {   -- 桌子
        { id = 100001, color = 0xFF4A3524, w = 0.9, h = 0.64 },
        { id = 100001, color = 0xFFD4CCA0, w = 0.82, h = 0.56 },
        { id = 100001, color = 0xFFE8E2C0, w = 0.72, h = 0.46 },
      },
      chair = {   -- 椅子
        { id = 106053, color = 0xFF4A3A2A, w = 0.74, h = 0.76, dy = 0.04 },
        { id = 106053, color = 0xFFF2EBD4, w = 0.66, h = 0.5, dy = 0.13 },
        { id = 100001, color = 0xFFCBBE97, w = 0.62, h = 0.2, dy = -0.16 },
      },
      carpet = {   -- 地毯
        { id = 100001, color = 0xFF9C8A63, w = 0.92, h = 0.92 },
        { id = 100001, color = 0xFFDCCBAA, w = 0.84, h = 0.84 },
      },
      plant = {   -- 植物
        { id = 100002, color = 0xFF3E7D3A, w = 0.64, h = 0.52, dy = -0.08 },
        { id = 106053, color = 0xFF8A6A48, w = 0.32, h = 0.24, dy = 0.26 },
        { id = 100002, color = 0xFF58A046, w = 0.34, h = 0.26, dy = -0.2 },
      },
      shelf = {   -- 书架
        { id = 100001, color = 0xFF4A3524, w = 0.82, h = 0.66 },
        { id = 100001, color = 0xFFB4874F, w = 0.76, h = 0.6 },
        { id = 100001, color = 0xFF4A2E17, w = 0.68, h = 0.07, dy = -0.05 },
      },
      statue = {   -- 雕塑
        { id = 100001, color = 0xFF4E4E56, w = 0.54, h = 0.24, dy = 0.28 },
        { id = 105090, color = 0xFFC9C9D2, w = 0.6, h = 0.5, dy = 0.02 },
        { id = 100002, color = 0xFFE2E2E8, w = 0.14, h = 0.1, dy = -0.22 },
      },
    },

    -- 2026-09-27 踩过：我一开始把它们加在 `cells = { … }` 里（挨着 `debug_signal`），
    -- 而 adapter 读的是 `self.cfg.debug_key` → **永远 nil** → 诊断一行都不打，
    -- 白白多跑了一轮真机才查出来。
    -- 教训：`cfg.cells.<名>` 与 `cfg.<名>` 是**两张表**，加开关时先确认读取处写的是哪个。
    debug_key   = false,   -- 打出 KeyEventType 解析结果的类型 + 实际收到的按键名
    debug_image = false,   -- 打出 SetImage 之后 face 的 imageType
    debug_event = false,   -- 打出每条控件绑定到了什么事件 + 点击时实际派发的事件

    -- ★ 头像卡按人数自适应列数：编辑器按"最挤的情况"摆好，
    --   运行时由 Adapter:apply_tray_layout 用 ui_controller 算好的几何摆正。
    tray_parent = "tray",

    -- ★ 键盘绑在哪个控件上。
    --   真机实测（2026-09-26）：`root`（容器节点）**不一定支持** `AddKeyEventListener` ——
    --   模拟器里所有控件都有这个方法，所以这件事离线验不出来。
    --   这里给一串候选：找到第一个"既找得到、又支持按键事件"的控件就用它。
    key_control = "root",
    key_control_fallbacks = { "board", "cell.1.1", "topbar" },

    -- ★ 2026-10-18（优化组 · B 类清理）：`diagnose_cell` 配置项**已删除**
    --   （配套的适配层体检函数与 main 的调用一起删；结案证据见真机日志「这一格配好了」）
  })

  -- ★ 线索卡底条：每条线索一个（最多 18 条），索引 1073742333（murdoku-clue-row）。
  --   用循环补，免得手抄 18 行 —— 这也是"一处定义"的做法。
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
  -- 离线测试钩子：让 tests/entry_smoke.lua 能直接驱动适配层
  -- （验调色板 / 染色 / 墙门这些需要构造场景的东西）。
  -- 生产环境无副作用：只是一个可读的全局引用，名字够独特不会撞上游戏自己的全局。
  __murdoku_debug = { adapter = adapter, Murdoku = Murdoku, beacon = beacon }
  -- ★ 2026-10-18（优化组 · 缺陷 3）：把 `beacon` 也挂上，供 `tests/optin_gates.lua` 做**双向**断言 ——
  --   `beacon` 是**文件局部函数**，不挂出来就只能靠"跑一次 OnInit 看尺寸有没有变"间接观察，
  --   那样测不到"打开开关后仍然会跑"这一半。挂一个**只读引用**，生产行为零变化。
  return adapter
end

-- ===== 开局前的控件探针 =====
-- 找不到关键控件时，把**客户端控件树整个打出来**，并按"树是空的 / 树里有东西但名字不对"
-- 两种情况给**不同的**处置建议 —— 真机上这两类的病因完全不一样。
--
-- ★ 2026-09-26 12:20 真机日志暴露的问题：**OnInit 阶段树本来就是空的**
--   （约 0.5 秒后才出现，这是实测事实），可是这份诊断在 OnInit 就把
--   "树是空的 + 三条可能原因"全砸出来了 → 看着像出了大故障，其实一切正常。
--
--   所以现在分轻重：
--     · 树是空的、**还有重试机会**（final=false）→ 只说一句"稍后重试"，不打树、不打病因；
--     · 树是空的、**已经放弃重试**（final=true）→ 打完整诊断（三条原因）；
--     · 树里**有节点**但没有 board/cell.1.1 → 立刻打（这是真的名字/层级问题，等也没用）。
-- ★★★★★ 2026-10-02 **安全调用 `on_start`：把失败原因打出来**。
--
--   真机现象（用户 13:45 日志）：日志在"键盘快捷键已绑定"之后**直接 destroyed** ——
--   没有 `started:`、没有"放弃自动开局"、什么错都没有。
--   ⇒ 说明 `Murdoku.on_start` **被调用了但返回 nil（或抛错被引擎吞掉）**，
--     于是 `started` 一直 false ⇒ 每帧重试 ⇒ 而重试时不再打印（已 dump 过）⇒ **完全静默**。
--   ⇒ 这里用 pcall 包住 + 把"抛错"和"返回 nil"这两种情况**都打成正常日志**。
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
  -- ★★★★★ 2026-10-02 **就绪判据不能写死 `board` / `cell.1.1`**。
  --
  --   真机后果（用户 13:31 日志）：重建时这两个控件被删了 ⇒ 判据**永远为假**
  --   ⇒ 一直重试到上限 ⇒ 打印"放弃自动开局" ⇒ **`Murdoku.on_start` 从未真正执行**
  --   ⇒ 于是：
  --        · `home` 停在 `vis=false` ⇒ **主页整个消失**（子控件都是 true，父级不显示）
  --        · `seal_containers` 没跑到 ⇒ **2D/3D 隔离失效**
  --   ⇒ 症状看着是两件事，**根因是同一个**。
  --
  --   新判据（按"重建后什么才一定存在"来写）：
  --     ① 旧结构：`board` / `cell.1.1` 任一存在（向后兼容老存档）
  --     ② 新结构：`stage` / `home` 任一存在（重建后一定有）
  --     ③ 兜底：`root` 存在且已经有 >3 个子控件 ⇒ 树就绪
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

  -- 先量一下树有多大（只数不打印），据此决定话术的轻重
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
    n = -1     -- 不知道数量
  end

  if printerr then
    if n == 0 then
      -- ★ 这是最要命的一类：树压根是空的。控件"建了"也没用 —— 根本没被创建出来。
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
      -- 把"差一点"的名字直接点出来 —— 真机上最常见的就是 (1) 后缀 / 大小写 / 空格
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

-- ===== PC 键盘快捷键（可重试）=====
--
-- ★ 2026-09-26 12:20 真机日志暴露的真 bug：
--   旧实现只在 `OnInit` 里绑一次，而 **OnInit 阶段控件树是空的** ——
--   于是日志打出「键盘绑定跳过：找不到可接收按键的控件（root）」
--   和「键盘快捷键没绑上（不影响鼠标/触摸操作）」，
--   而后者听起来无关紧要，很容易放过 —— **实际上真机上 PC 键盘从来没生效过**。
--
--   现在做成"可以补绑"：OnInit 试一次，等控件树就绪（OnStart/OnUpdate 重试）
--   之后再试一次；绑成功就记下来不再重复。
local keyboard_bound = false
-- ⚠️ 这里是 **`Enum.KeyEventType` 的名字**，不是物理键名！
--    官方签名：`AddKeyEventListener(eventType, callback)`，第一个参数是**语义事件**
--    （「设备 + 语义 + 按下/抬起」的组合）。下面注释里括号内是该事件的**默认物理键**，
--    而「奇匠按键」是**可被玩家重映射**的槽位，不能假定玩家按的确实是那个物理键。
--
--    官方**没有** Return / Enter / Escape 事件，所以：
--      · 放置       → 改用「拾取/交互」（默认 F）
--      · 关弹窗/选关 → 改用奇匠按键42（默认 Backspace）
local KEY_SPEC = {
  -- 方向：奇匠按键36..39（默认 ↑ ↓ ← →）
  "KeyboardCraftspersonKey36Down", "KeyboardCraftspersonKey37Down",
  "KeyboardCraftspersonKey38Down", "KeyboardCraftspersonKey39Down",
  -- 选角色 1..10：奇匠按键1..10（默认 1..9 与 0）
  "KeyboardCraftspersonKey1Down",  "KeyboardCraftspersonKey2Down",
  "KeyboardCraftspersonKey3Down",  "KeyboardCraftspersonKey4Down",
  "KeyboardCraftspersonKey5Down",  "KeyboardCraftspersonKey6Down",
  "KeyboardCraftspersonKey7Down",  "KeyboardCraftspersonKey8Down",
  "KeyboardCraftspersonKey9Down",  "KeyboardCraftspersonKey10Down",
  -- 主要动作
  "KeyboardInteractKeyDown",       -- 拾取/交互（F）  = 放置
  "KeyboardJumpKeyDown",           -- 跳跃（Space）  = 铅笔笔记
  "KeyboardDropKeyDown",           -- 落下（X）      = 划掉这格
  "KeyboardCraftspersonKey42Down", -- Backspace     = 关弹窗 / 选关
  -- 工具与命令
  "KeyboardOpenShortcutWheelKeyDown", -- 快捷轮盘（Tab）= 循环换工具
  "KeyboardCharacterSkill1KeyDown",   -- 角色技能1（E） = 橡皮擦
  "KeyboardCharacterSkill3KeyDown",   -- 角色技能3（R） = 提交
  "KeyboardCraftspersonKey12Down",    -- Z = 撤销
  "KeyboardCraftspersonKey13Down",    -- Y = 重做
  "KeyboardCraftspersonKey15Down",    -- H = 提示
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
      -- OnInit 时树是空的，绑不上是**预期的**，不要吓人
      if print then
        print("[murdoku] 键盘快捷键暂未绑定（OnInit 时控件树还没就绪，稍后会自动补绑）")
      end
    else
      -- 补绑也失败了 → 把**原因**说出来（哪几个候选控件、各自为什么不中用）
      if print then
        print("[murdoku] 键盘快捷键没绑上（不影响鼠标/触摸操作）：" .. tostring(note))
        print("[murdoku]   → 想用键盘的话：在 cfg.key_control / key_control_fallbacks 里"
          .. "换一个控件名（必须是**预设按钮**这类支持按键事件的控件）")
      end
    end
  end)
  return ok and keyboard_bound
end

-- ===== 官方生命周期 =====

-- ★★★★★★★★ 2026-10-21（v287）**教程浮层（`teach.*`）的接线：第一关 / 第二关各一套** ✗✓✓
--
--   控件在存档里（`teach.*`，工具 `tools/gil/gen_tutorial_teach.mjs`，**仍然全部从主档母本克隆**）：
--     · `teach.l1` / `teach.l2`  两关各一套面板（页面本体 + 上一页 / 下一页 / 关闭；**没有页签**）
--     · `teach.text.l1` / `teach.text.l2`  文本区域（标题 / 三页正文 / 按钮字）
--   ★ 文字**全部由编辑器填**（`.gil` 存不下文字，工作约定见 `docs/交接报告.md`）⇒ **本处一个字都不写**，
--     只做显隐与绑定。**本处也一个控件都不创建**（用户明确的规矩）。
--   ★ 两关**各自一个实例、各自一段配置**（`TUT_LEVELS`）：内容以后会分叉，不许共用一套。
--
--   这里做四件事：懒加载模块 → 两套实例都 init（先各自藏起来）→ 进到哪一关就弹哪一套 → 各跑一次自检。
--   ★ 自检：`lua/tut_verify.lua` 把"控件在不在 / 重名 / 父对不对 / 尺寸 0"打进日志首屏：
--       通过 `[tut] 自检 OK N/N`；失败 `[tut] 自检 FAIL N 项: 名字=缺失; …`（只读，不改任何状态）
--
--   ⚠️ 为什么放在 OnUpdate 里懒初始化：`OnInit` 时控件树还是空的（本项目反复验证过），
--      在 OnInit 里 init 必定拿到 nil，然后**再也不会重试**。
local tutorial_mod_state = nil   -- nil = 还没试 / false = 加载失败 / table = 模块
local tutorial_inst = {}         -- tag → 实例（每关一个，互不影响）
local tutorial_seen = {}         -- 关卡 id → 这一局已经弹过
local tutorial_checked = {}      -- tag → 已经跑过自检
local tutorial_wait = {}         -- tag → 等了多少帧

-- ★ v289：**三套各自独立**（用户 2026-10-21 晚：首页那套保留，第一关再单独接一套，第二关本来就是自己一套）
--   每条 = 一个实例 + 一段配置；以后哪一套要改内容/页数，只改自己那一段。
local TUT_SETS = {
  home = { tag = "home", root = "teach.home", text = "teach.text.home", pages = 3 },
  l1   = { tag = "l1",   root = "teach.l1",   text = "teach.text.l1",   pages = 3 },
  l2   = { tag = "l2",   root = "teach.l2",   text = "teach.text.l2",   pages = 3 },
}

-- 触发键 → 用哪一套：`home` = 首页；`case_001` / `case_002` = 关卡内
-- ★ 关键：`Murdoku.current().screen == nil` 才算"真的进了关卡"；首页时 screen = "home"。
--   v287 那版只看 level.id ⇒ 首页时 level 已经是 case_001 ⇒ 首页就把第一关那套弹掉了，
--   真进第一关反而"已经弹过"不再弹（用户实测：首页有、第一关没有）。
local TUT_TRIGGER = { home = "home", case_001 = "l1", case_002 = "l2" }

-- ⚠️ 这里原来还有**另一份** `current_tut_key()`（v289 的"只看 cur.screen"版）。
--   ★ v298 删掉它：`local function` 后定义者会**盖掉**先定义者 ⇒ 它是一份**死代码**，
--     但谁要是照着它的位置改（它排在上面），改完**运行时一点效果都没有** ——
--     这正是"连续两版改错方向"的现成陷阱。**这个文件里 current_tut_key 只允许有一处定义**（见下方 v298 版）。

local function tutorial_module()
  if tutorial_mod_state ~= nil then
    if tutorial_mod_state == false then return nil end
    return tutorial_mod_state
  end
  local ok, mod = pcall(require, "tutorial_ui")
  if not ok or type(mod) ~= "table" or type(mod.new) ~= "function" then
    if printerr then printerr("[murdoku] 教程模块没加载上：" .. tostring(mod)) end
    tutorial_mod_state = false     -- 记"试过了"，避免每帧重试刷屏
    return nil
  end
  tutorial_mod_state = mod
  return mod
end

-- 取某一关的实例（第一次调用时创建；控件没进树时 init 自己会早退，下次再来）
local function tutorial_instance(spec)
  if spec == nil then return nil end
  local inst = tutorial_inst[spec.tag]
  if inst ~= nil then return inst end
  local mod = tutorial_module()
  if mod == nil or adapter == nil then return nil end
  local ok, made = pcall(function()
    return mod.new(adapter, { tag = spec.tag, root = spec.root, text = spec.text, pages = spec.pages })
  end)
  if not ok or type(made) ~= "table" then
    if printerr then printerr("[murdoku] 教程实例建不出来（" .. tostring(spec.tag) .. "）：" .. tostring(made)) end
    return nil
  end
  tutorial_inst[spec.tag] = made
  return made
end

-- 教程控件自检（每关一次；全程 pcall，失败只影响"日志少一行"，绝不影响游戏）
local function verify_tutorial_once(tag)
  if tutorial_checked[tag] then return end
  tutorial_checked[tag] = true
  pcall(function()
    local ok, mod = pcall(require, "tut_verify")
    if not ok or type(mod) ~= "table" or type(mod.check) ~= "function" then
      if printerr then printerr("[murdoku] 自检模块没加载上：" .. tostring(mod)) end
      return
    end
    mod.check({
      find = function(n) return adapter:find(n) end,
      -- 注入根表 ⇒ 自检能查全树的"同名多条"（不注入就只能查同级，会在日志里降级说明）
      roots = function()
        if game == nil or game.GetClientUIRoots == nil then return nil end
        return game.GetClientUIRoots()
      end,
    })
  end)
end

-- ★ v292：**"现在到底在哪一屏"以【看得见的控件】为准**
--
--   真机实测（用户 2026-10-21 04:59 日志）：开局那条 `on_start` 之后 `cur.screen` 是 nil，
--   但屏幕上其实还是**首页**（随后玩家点了 `home.select` 进选关）。
--   ⇒ v289 直接信 `cur.screen == nil` ⇒ 在首页就把第一关那套弹了一次（然后立刻关掉），
--     等真进第一关时它已经"弹过" ⇒ 第一关永远看不到教程。
--   修法：首页判据改成"**`home` 控件可见**"（这是渲染事实，不依赖状态字段的时序），
--        再叠加"触发键稳定 N 帧才动手"，两道一起挡住过渡期。
--
-- ★★★ v298（2026-10-21 22:31 真机日志的证据，用户要求）：**board/stage 不能当"进了关卡"的判据** ✗
--   · 日志开头**首页阶段**就有 `★ 几何归编辑器：stage 回读 584.0x584.0`
--     ⇒ `board` / `stage` 是**全屏常驻容器**，首页 / 选关页也**存在** ⇒ "存在即可见"⇒ 一律误判成关卡内
--   · 选关页时：`cur.screen` 仍是 **nil**、`home` **已隐藏**
--     ⇒ 所以既不能靠 screen，也不能靠 home 的否定面来判"在哪一屏"
--   · 选关页**独有**、且**读得到**的是 `select.card.1`（日志里有 `选关卡框 select.card.1：w=209.0 …`）
--     ⚠️ 而容器名 `select` 本身 `find` 不到（项目自己的诊断也印 `select=**找不到**`）⇒ 只能判**子控件**
--   ⇒ v298 判据（顺序即优先级，全部以"**可见**"为准，取不到一律按不可见）：
--       ① `home` 可见                     ⇒ "home"
--       ② `select.card.1`（退而 `select.title`）可见 ⇒ **选关页 ⇒ nil（不弹）**
--       ③ `clues` 或 `board` 可见          ⇒ 才认为在关卡里 ⇒ `tostring(cur.level.id)`
--       ④ 其它                            ⇒ nil
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

local TUT_STABLE_NEED = 20   -- 触发键连续稳定 20 帧（≈0.67s）才弹，躲开切屏过渡
local TUT_KEEP_NEED = 10     -- 面板出现后还要稳 10 帧才算"真的弹成了"（才记 seen）
local tut_key_prev = nil
local tut_key_frames = 0
local tut_shown_frames = 0
local tut_key_logged = false -- v298：触发键诊断日志是否已经打过（首帧那行也要打）
local tut_miss_frames = {}   -- tag -> 连续不该弹的帧数（>=10 才关，抗抖动）

-- 当前触发键 + 一份**判据快照**（诊断日志用）。
--   ★ 同一帧只读一次可见性 ⇒ "日志里看到的值"和"实际用来判的值"**一定是同一份**（不做二次读）。
--   ★ 返回 `(key, probe)`；`key == nil` = 现在不该弹任何一套。
local function tut_key_and_probe()
  local cur = nil
  pcall(function()
    if Murdoku ~= nil and Murdoku.current ~= nil then cur = Murdoku.current() end
  end)

  -- 三个判据各读一次（`tut_visible` 内部全 pcall，取不到 = false）
  local home  = tut_visible("home")
  local card1 = tut_visible("select.card.1")
  if not card1 then card1 = tut_visible("select.title") end   -- 兜底：选关页标题，同样是选关页独有
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
      key = "home"                       -- ① 首页
    elseif card1 then
      key = nil                          -- ② 选关页：**不弹**（log 里 card1=true 一眼能看出来）
    elseif clues or board then
      if id ~= nil then key = tostring(id) end   -- ③ 关卡内
    end
    -- ④ 其它（过渡态 / 未知屏）：key 保持 nil
  end

  return key, { home = home, card1 = card1, clues = clues, board = board, scr = scr, id = id }
end

-- 当前触发键（拿不到返回 nil）—— 对外保持这个名字：本文件里**只有这一处定义**。
--   ★ 判据快照随手存进 `tut_last_probe`：调用方要打诊断日志就读它，
--     **不要为日志再读一次可见性**（否则"日志里的值"和"实际判的值"可能不是同一帧的）。
local tut_last_probe = nil
local function current_tut_key()
  local key, probe = tut_key_and_probe()
  tut_last_probe = probe
  return key
end

local function tick_tutorial()
  if adapter == nil then return end
  if tutorial_module() == nil then return end

  -- ① 三套实例都做惰性 init：谁先就绪谁先被藏起来（避免教程面板在别的界面露出来）
  for _, spec in pairs(TUT_SETS) do
    local inst = tutorial_instance(spec)
    if inst ~= nil and not inst.inited then
      pcall(function() inst:init() end)
      if not inst.inited then
        -- ★ 兜底：根容器迟迟没进树 ⇒ 这条失败路径原来是纯静默的；约 2 秒后照样跑一次自检
        tutorial_wait[spec.tag] = (tutorial_wait[spec.tag] or 0) + 1
        if tutorial_wait[spec.tag] >= 120 then verify_tutorial_once(spec.tag) end
      else
        verify_tutorial_once(spec.tag)
      end
    end
  end

  -- ② 只在"该出现的那一屏"弹对应那一套；离开就收起
  --   ★ v292：**触发键稳定 20 帧才动手**，并且**面板稳 10 帧才记 seen**
  --     真机实测：开局 `cur.screen` 会短暂为 nil 而屏幕其实还是首页 ⇒ 旧逻辑在那一刻就把 l1 弹掉并记 seen，
  --     真进第一关时反而"已弹过"，第一关永远看不到教程。
  local key, probe = nil, nil
  if started then
    key = current_tut_key()          -- ★ 唯一入口：判据在 `tut_key_and_probe` 里
    probe = tut_last_probe           -- ★ 同一帧的那份快照（诊断日志用，不二次读）
  end
  local key_changed = (key ~= tut_key_prev)
  if not key_changed then
    tut_key_frames = tut_key_frames + 1
  else
    tut_key_prev = key
    tut_key_frames = 0
    tut_shown_frames = 0
  end
  -- ★★★ v298 诊断（用户要求"一行定位"）：触发键**一变**就打一行；**首次评估**（就算结果是 nil）也打一行。
  --   值全部来自这一帧**运行时读到的**可见性/字段（`probe` 与"实际用来判的"是同一份，不二次读）。
  --   真机日志里看到的样子：
  --     [tutorial] 触发键 -> home  (home=true card1=false clues=false board=false scr=nil)
  --     [tutorial] 触发键 -> nil   (home=false card1=true clues=false board=false scr=nil)   ← 选关页：不弹
  --     [tutorial] 触发键 -> case_001  (home=false card1=false clues=true board=true scr=nil)  ← 关卡内
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
        -- ★ v293：**只有"还没弹过"才自动打开** —— 否则玩家点了关闭，下一帧又被自动打开（真机实测：关不掉）
        if not tutorial_seen[tag] then
          if not inst.open then
            pcall(function() inst:open_ui() end)
          end
          tut_shown_frames = tut_shown_frames + 1
          -- 面板真的稳住了才记"已弹过"（弹一下就被关不记账 —— 那是 v291 第一关丢失的形态）
          if tut_shown_frames >= TUT_KEEP_NEED then tutorial_seen[tag] = true end
        end
      else
        -- ★ v293：**抗抖动**：连续 10 帧都不是这一套才关；单帧闪烁不关
        tut_miss_frames[tag] = (tut_miss_frames[tag] or 0) + 1
        if inst.open and tut_miss_frames[tag] >= TUT_KEEP_NEED then
          pcall(function() inst:close() end)
          tut_miss_frames[tag] = 0
        end
      end
    end
  end
end

local TPL_PROBE_DONE = false   -- v311 模板探针只跑一次

function OnInit()
  -- ① 逐帧更新开关（OnUpdate 全靠它）—— 内部已 pcall
  pcall(enable_update)

  -- ② 先把适配器建起来并交给 main，再谈其它诊断。
  --    顺序很关键：只要它建成了，后面就算有诊断炸掉，游戏逻辑照样能跑。
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

  -- ③ 诊断：只报不改，各自 pcall
  pcall(check_canvas)
  pcall(function() beacon(adapter, BEACON.OnInit) end)

  -- ④ PC 键盘（可能绑不上，之后会自动补绑）
  bind_keyboard_once("OnInit")

  -- ⑤ 汇总：看到这句说明 OnInit 完整走完了
  if print then print("[murdoku] OnInit done（适配器已就绪，等 OnStart 开局）") end
end

function OnStart()
  if LOAD_ERR ~= nil or Murdoku == nil then return end

  -- 万一 OnInit 没能建起适配器，这里补一个（可重入）
  if adapter == nil then
    if printerr then printerr("[murdoku] OnStart 发现适配器为空，补建一个") end
    pcall(build_adapter)
  end

  pcall(function() beacon(adapter, BEACON.OnStart) end)

  -- 开局前探一下关键控件；找不到就把控件树打出来，省得靠猜
  if not probe_or_dump(false) then
    -- 这次先不开局：让 OnUpdate 的惰性重试去等控件就绪
    if print then print("[murdoku] 控件还没就绪，交给 OnUpdate 重试") end
    return
  end

  -- 控件树已就绪 → 把 OnInit 没绑上的键盘补绑一次（OnInit 时树是空的，必定失败）
  bind_keyboard_once("OnStart")

  -- 钉死了关卡就**不要**恢复存档（存档是别的关的，读进来会串味）
  --
  -- ★★★ 2026-09-29：**开局进主页**（用户要求的主页选关流程）。
  --
  --   ⚠️ 必须用显式 if 算，**不能用 `and/or` 三元式**：
  --     我写过 `FORCE_LEVEL and nil or "home"` —— Lua 里 `x and nil` 恒为 nil，
  --     于是 `nil or "home"` 永远是 "home"，条件等于没写。
  --     凡"某个分支是 nil/false"，就必须写成 if。
  --
  --   ⚠️ 另一个大教训：**`OnStart()` 不接受参数**，入口自己造 opts 表 ——
  --     所以"从外面传个 flag 绕过主页"是做不到的。测试请走主页流程
  --     （`tools/sim/kit.mjs` 的 `enterLevel()`）；钉死关卡（测试模式）则直接进关。
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
  -- ★ 2026-10-22（v311/v312）**模板探针**：等格子实例建出来之后跑一次（OnInit 时格子还没建）。
  --   结果只在日志（前缀 `[tplprobe]`）；配置项在 build_adapter 的 cfg 表里（`adapter.cfg`）。
  if not TPL_PROBE_DONE and adapter ~= nil then
    local acfg = adapter.cfg
    if acfg ~= nil and acfg.tpl_probe then
      local cell = nil
      pcall(function() cell = adapter:find("cell.1.1") end)
      if cell ~= nil then
        TPL_PROBE_DONE = true
        pcall(function()
          local okp, probe = pcall(require, "tpl_probe")
          if okp and probe ~= nil and probe.run ~= nil then
            pcall(probe.run, acfg)
          elseif print then
            print("[tplprobe] 载入失败：" .. tostring(probe))
          end
        end)
      end
    end
  end

  if LOAD_ERR ~= nil or Murdoku == nil then return end
  -- ★ v284：教程浮层的懒初始化 / 首次弹出（内部全程 pcall，失败只影响教程）
  pcall(tick_tutorial)
  if not started then
    -- 惰性重试：等客户端控件容器/控件就绪后再开局
    retry_elapsed = retry_elapsed + (dt or 0)
    if retry_elapsed >= RETRY_INTERVAL then
      retry_elapsed = 0
      retry_tries = retry_tries + 1
      if retry_tries > RETRY_LIMIT then
        -- 放弃了 → 这时候"树还是空的"才是真的故障，把完整诊断和三条病因打出来
        probe_or_dump(true)
        if printerr then
          printerr("[murdoku] 等不到客户端控件，放弃自动开局"
            .. "（检查客户端控件容器是否【激活且可见】、界面布局是否被【职业】引用）")
        end
        started = true      -- 停止重试，避免刷屏
      else
        if adapter == nil then pcall(build_adapter) end
        if probe_or_dump(false) then
          -- 控件树就绪了 → 补绑键盘（OnInit 时绑不上，那时树是空的）
          bind_keyboard_once("重试")
          -- 与 OnStart 那条保持一致。
          -- ⚠️ 写成显式 if —— 我在这里第一次就是顺手写成
          --    `(FORCE_LEVEL ~= nil) and nil or "home"`，
          --    而 `x and nil` 恒为 nil ⇒ 永远落到 "home"，{==} 我又踩了同一个坑 {==}。
          --    所以：**只要三元式里有一个分支是 nil/false，就必须写 if**。
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
end

-- 需要跟随关卡时停的表现可以放这里；本框架的 UI 计时走 OnUpdate
function OnLevelUpdate(dt) end

function OnDestroy()
  if LOAD_ERR ~= nil or Murdoku == nil then return end
  Murdoku.on_destroy()
  if print then print("[murdoku] destroyed") end
end

