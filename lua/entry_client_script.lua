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
  if a.cells_beacon == false then return end
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
        print("[murdoku] ===== 构建标记 v166 / 2026-10-11 / 恢复main.lua的x几何(70%⇒别顶满格子,用户当年要求的);我第4轮删反了 =====")
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
    widgets     = true,    -- ★ 打开：启动时创建并显示 selbtn.1..N（102 验证过"能完成选关"的那四个方块）
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
      --   [murdoku] 边缘适配 wall.up：基准 24x8 → 目标 135x8（倍率 5.63 / 1.00）
      edge_thickness = 8,
      -- 门比墙短一点（占格子边长的比例），看起来才像"门"
      door_length_ratio = 0.45,
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
      --   obj   在底图之上 —— 家具图标要能看见
      --   wall  压住底图 —— 墙贴在格子边上，必须显出来
      --   door  压住墙 —— 同一段边可能既是墙又是门，门要在墙上面
      --   x     划掉标记压住一切装饰
      --   note  铅笔笔记最上 —— 玩家写的信息永远可读，不能被图挡
      layer_order = {
        "face",
        "obj",
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

    -- ★ 参照格子体检（cell.1.1）：把"类型/射线/子控件/图片来源/光标门控"逐条读出来
    --   并给 ✅/❌ 与修法。搭界面阶段非常有用，**每个会话只打一次**。
    --   界面搭完、验收通过之后可以改成 false 让日志干净些。
    diagnose_cell = true,
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
  __murdoku_debug = { adapter = adapter, Murdoku = Murdoku }
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
  if LOAD_ERR ~= nil or Murdoku == nil then return end
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
