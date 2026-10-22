--[[----------------------------------------------------------------------------
  ui_controller.lua —— 操作框架层（页面布局 + 交互状态机 + 特效指令）v0.3.0

  交互模型照 murdoku 实证规格：
    · 点头像卡        = 选中/取消选中（卡片下沉 2px = 已放置）
    · 单击格子        = 写/删铅笔笔记（小字，不占位）
    · 双击格子        = 放置（大字母）并清空选中
    · 右键 / X 工具   = 该格不可能（X 标记）
    · 橡皮擦          = 单击清该格；双击橡皮擦工具清空全盘
    · 双指            = 回滚到本次手势之前的快照
    · 未摆满时提交    = 无效（提交按钮显示「先摆满」）
    · 摆满且成立      = 进入「指认凶手」
  页面分区照 murdoku：
    顶部工具条 / 左侧面板(头像卡 + 线索卡 + 图例) / 中央棋盘(带 R,C 坐标尺) / 右侧信息栏
  职责边界：本文件不认识任何引擎 API，只产出「控件树 + 属性 + 特效指令」。
----------------------------------------------------------------------------]]--

local M = {}

-- 浅比较：walls / notes / state 这类 table 属性按内容比较，避免每帧重推
local function same_value(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

M.DESIGN = { width = 1920, height = 1080 }

-- ★★★★★★★★ 2026-10-22（v306，第八轮）**家具图元改走"静态烘焙"** ✗✓
--
--   用户真机验证后的判断：网站（拼图工具）导出的内容能在真机显示，是因为它把图元写成
--   **存档里的静态图片控件**；我们走运行时实例化，链路长、真机上表现不稳。
--   ⇒ 本轮起：椅子/植物/雕像的图元由 integrator 直接烘成存档里的静态控件
--     （`root/fart.case_001`、`root/fart.case_002` 两个容器，默认隐藏），
--     脚本只负责"按当前关卡打开对应容器" ⇒ **完全不再调用 InstantiateClientUIControl**。
--   ⚠️ 关掉这个开关会退回旧的"运行时实例化"路径（`furn_art` 分支），方便 A/B 对比。
M.FURN_BAKED = false

-- ★★★★★★★★ 2026-10-22（v310，第十三轮）**家具改"模板化手搭"** ✗✓
--   用户：「采用模板来手搭构建，模板里放多少层都可以（一个模板引用控件只算一层），
--   然后像 cell 一样把模板创建出来」。
--   ⇒ 每件家具一个"客户端控件模板"（`furn.chair` / `furn.plant` / `furn.statue` /
--     `furn.table.1` / `furn.table.h2` / `furn.table.v2` / `furn.shelf`），
--     脚本按 `FurnArt.layout()` 给出的"哪一格是哪件"在锚点格实例化模板，尺寸 = 跨格数 × 格子尺寸。
--   ⚠️ `M.FURN_TPL=false` 时回落 v309 的 12 层手搭（家具画进模板层）。
--   模板 prefabIndex 由 integrator 提供后填进 `entry_client_script.lua` 的 `cfg.furn_tpl_prefab`。
M.FURN_TPL = true

-- ★★★★★★★★ 2026-10-22（v309，第十二轮）**家具统一走"桌子/地毯"那套手搭层链路** ✗✓
--   用户：「既然已经有了图元素材，不如就把它们按桌子地毯等家具的搭建流程统一构造」。
--   ⇒ 椅子/植物/雕像 也改成手搭层（`FurnArt.ART`，≤12 层、全轴对齐色块），
--     **不再走**静态烘焙容器（`fart.*`），**也不再**运行时实例化图元。
--     `FurnArt.ART` 里的椅子/植物/雕塑 = 9/10/10 层，和桌子(10)/书架(12)/地毯(3) 同一条链路。
--   ⚠️ `M.FURN_BAKED` 保留为**回退开关**：万一要回到静态烘焙，把它改 true 即可（数据在 511/512 存档）。

-- ★ 2026-10-22（v300）家具美术数据层（分组 / 锚点 / 六层元素 / 地毯切矩形 / 房间名标签）
--   单独一个模块，因为它是**纯数据 + 纯几何**，不该和界面状态机混在一起（见 lua/furn_art.lua 文件头）。
local FurnArt = require("furn_art")
-- ★ 2026-10-22（v302，第四轮）**外部工具算出的图元拼法**
--   生成链：原作图标 → qx-img 拼图工具（本地引擎）拟合 → 结果文件 .lua → `gen_art_records.py` 拆解 → 本模块。
--   每件 148~200 条图元（含旋转/逐图元 RGBA），游戏里由适配层逐条生成图片控件（12 层装不下）。
local FurnRecords = require("furn_art_records")

-- ════════════════════════════════════════════════════════════════════════
-- 坐标基准（2026-09-26 实测确认，务必先读这段再动 LAYOUT）
--
-- 本文件下面的 LAYOUT 全部写在**设计空间**里：
--     1920 × 1080，**原点左上角，Y 轴向下**（写起来像读文档，最直观）
--
-- 真机画布（game.GetUICanvasSize() 实测）是 **1600 × 900**，
-- 编辑器「位置 X, Y」输入框用的是**画布空间**：
--     原点**左下角**，Y 轴**向上**，数值 = 控件**中心(pivot)点**的绝对坐标，
--     **跟父级无关**（父级只影响显示层级，不影响位置数值）。
--
-- 两套空间的换算只有 M.to_canvas() 一处，别在别处手算。
--
-- 【重要】模拟器 dsh-plugin-beyond-simulator 的 posX/posY 语义与编辑器
--   「位置」输入框**完全一致**（实测：pos 就是中心点绝对坐标，父级被忽略，
--   pivot/anchor 的设置不生效）。所以同一份 canvas 坐标既喂模拟器、
--   又直接抄进编辑器，两边不会打架。
-- ════════════════════════════════════════════════════════════════════════

M.CANVAS = { width = 1600, height = 900 }
M.SCALE  = M.CANVAS.width / M.DESIGN.width    -- = 5/6

local function round(v) return math.floor(v + 0.5) end

-- 设计空间矩形 {x, y, w, h}（左上原点、Y 向下）
--   → 画布空间 {cx, cy, w, h}（左下原点、Y 向上，cx/cy = 中心点绝对坐标）
function M.to_canvas(r)
  local s = M.SCALE
  return {
    cx = round((r.x + r.w / 2) * s),
    cy = round((M.DESIGN.height - r.y - r.h / 2) * s),
    w  = round(r.w * s),
    h  = round(r.h * s),
  }
end

-- ★ 2026-09-29：是否显示「放置 / X 标记 / 橡皮擦」三个工具按钮。
--   用户确认这三个动作都有更直接的入口（双击/长按=放置、单击=✗、单击已放置格=拿起）
--   ⇒ **默认关闭**。留这个开关，是为了以后给移动端补按钮时不用重写布局。
M.SHOW_TOOL_BUTTONS = false

-- ★★★★★ 2026-10-05 **A8：提示语（toast）的存活时长（秒）** —— 用户批准的**方案甲**。
--
--   要解决的问题（2026-10-05 实测，证据见 docs/L3基线-模拟器四步失败清单.md §8）：
--     `self.toast` 全项目 **10 处写入**（8 处真消息 + 2 处清空），而**一个读它的地方都没有** ✗
--     ⇒ 玩家看不到任何提示：撤销 ✗ 取消 ✗ 揭示 ✗ 还没有游玩记录 ✗ 商城/背包 ✗。
--   方案甲 = **只补读者**：一个写入点都不改、一个控件都不加
--   （`hud.toast` 已按参考图删掉，不在计划里、也不在存档里 ⇒ 不能把它加回来）。
--
--   为什么是 2.5 秒：够看清一句 6~17 字的中文提示（更短就成"一闪而过"= 又等于没反馈 ✗），
--   又不至于赖在屏幕上不动。**这个数值只在这里定义一次** —— 超时判断（`Controller:tick`）
--   和 8 处写入（`self.toast_until = self.now + M.TOAST_SECONDS`）共用它，不许各写一份 ✗。
M.TOAST_SECONDS = 2.5

-- 主页标题（文字**存不进 .gil**，只能脚本写 —— 见《工作约定》）
M.HOME_TITLE = "侦探推理 · 摆位谜题"
M.LAYOUT = {
  topbar = { x = 0, y = 0, w = 1920, h = 104 },
  -- ★★★★★ 2026-10-04 **标题/计时器按规划图 v3 挪到"左边栏"**（不在顶部！）。
  --
  --   量图（`docs/布局图-关卡内-v3.png`，1600×900 画布空间）：
  --     TITLE 字形带  x 60..507、y 140..167 ⇒ 中心 (283.5, 153.5)（自上方）
  --     TIMER 字形带  x 60..343、y 190..217 ⇒ 中心 (201.5, 203.5)
  --   ⇒ 设计空间（×6/5）：TITLE 中心 (340, 184)、TIMER 中心 (242, 244)
  --
  --   之前写的是 `title = {x=360, y=18}`（**顶部居中偏右**）—— 那是按"顶栏"想的，
  --   跟规划图**根本不是一处**（图里标题在左边栏、计时器就在它下面一行）。
  title  = { x = 70, y = 156, w = 540, h = 56 },   -- 中心 (340, 184) = 图上 TITLE 的位置
  -- ★ 2026-10-18（优化组 · P0）：`M.LAYOUT` 里**这一类"无读者键"已删除** ✗✓
  --   判据（逐个键在代码里数 `L.<键>`，全部为 0，且 tests/ tools/ 里也没有读者）：
  --     `stats` · `tray_item_w` · `cell` · `cell_gap` · `wall_thickness` ·
  --     `back_btn` · `confirm` · `actions` · `action_btn`
  --   ⚠️ `tray_item_h` / `tray_gap_x` / `tray_gap_y` / `tray_per_row` **仍在用**（托盘自适应布局）⇒ 保留 ✓

  -- 左侧面板：头像卡 + 线索卡 + 图例
  --   ⚠️ 高度必须算够：tray_item_h * 行数 + 行距 不能超过 tray.h，
  --   否则最后一行卡片会**溢出容器**压到下面的线索上（2026-09-26 实测踩到过两次：
  --   先是 2 列 3 行压住线索，后来是 7 个角色排到第 3 行又压住一次）。
  --   现在卡片的**列数**会按人数自适应（见 build_layout），保证永远只占 2 行。
  left   = { x = 24, y = 128, w = 392, h = 880 },
  tray   = { x = 40, y = 148, w = 360, h = 218 },   -- 固定 2 行 × 104 + 10 = 218
  tray_item_h = 104,                                -- （`tray_item_w` 已删：无读者的参考值）
  tray_gap_x = 12,
  tray_gap_y = 10,
  tray_per_row = 3,                                 -- 最少 3 列
  -- 线索区。
  --   ⚠️ clue_max_visible 是**硬上限**：超出的线索不会生成控件，玩家看不到，
  --   而线索是解题的全部依据 —— 看不全就等于关卡不可解。
  --   2026-09-26 踩到过：case_003 有 18 条线索，而这里只放 12 行，
  --   后 6 条连控件都没有（界面上只显示"还有 6 条线索"，玩家无从下手）。
  --   现在放 18 行（382 + 18*28 = 886 ≤ 902），够本项目所有关卡用。
  --   写更多线索的关卡请同步调大 clue_max_visible / 调小 clue_row_h，
  --   并跑 `lua tests/ui_math.lua` 确认没压到图例。
  -- ★★★★★ 2026-10-02 **线索区吃满左栏**（头像卡取消后腾出来的地方全给它）：
  --   原来 y 382..902（tray 占 148..366）；现在从 148 一直到图例上方 888。
  --   行数 9 → 14（14 × 52 = 728 ≤ 740）。滚动窗口依旧，超出的靠 ▲▼ 翻。
  -- ★★★★★ 2026-10-04 **线索区按规划图 v3 重新量过**：
  --   图上 5 张线索卡：x 60..439（宽 380）、y 262..741，卡高 88、行距 ≈98（画布空间）
  --   ⇒ 设计空间：x 72、y 314、宽 456、卡高 105.6、行距 ≈115、5 张 = 575
  --   之所以必须往下挪：标题/计时器现在在**左边栏上方**（图里就在卡片上面），
  --   原来的 `y = 148` 会和它们重叠。
  clues  = { x = 36, y = 275.4, w = 480, h = 652.8 },  -- ★ 2026-10-05：{72,314,456,575} → 本行
  --   ★★★★★ 为什么改：真机日志（11:31）显示运行时 `clues = 380×479`，而用户在编辑器里摆的是
  --   **400×544 @ 中心 (230, 398.5)** ⇒ **脚本按旧规划把用户的版面冲掉了** ✗
  --   ★★★ **y 的语义（本轮反推出来的，很重要）**：`rect_of` 的 `y` 是**从画布顶部往下量**的，
  --   不是从底边。验证：先按"底边"给 151.8 设计 ⇒ 顶部 = 126.5 画布 ⇒ 中心 = 900−126.5−272
  --   = **501.5 ≈ 502** ✓ 与规划读到的 502 **完全吻合** ⇒ 语义确认 ✓
  --   ⇒ 要中心落在画布 398.5：顶部 = 900−398.5−272 = 229.5 画布 = **275.4 设计** ✓
  --   换算：画布 400×544 → 设计 ×6/5 = 480×652.8；x = 中心 230 − 200 = 30 画布 = **36 设计** ✓
  --   校验：h 652.8 ÷ clue_row_h 127.2 = **5 行** ✓（与 clue_rows 一致）
  clue_row_h = 127.2,       -- ★★★★★ 2026-10-05：115 → **127.2**（= 画布 106 ⇒ 设计 106×6/5）。
                            --   用户 2026-10-05 把卡片改成**画布 360×96**、卡距 **10**（行距 106），
                            --   而规划是**设计空间**、渲染时 ×5/6 缩到画布 ⇒ 设计行距必须是 **127.2**。
                            --   真机日志铁证（11:31）：`clue.N 367x91` —— 367 = 440×5/6（旧设计宽 440）、
                            --   91 = 109×5/6（旧行高 109）⇒ **脚本的旧规划把用户在编辑器里摆的 360×96 冲掉了**。
                            --   ⚠️ 行内矩形的高度是 `clue_row_h − 12`（卡距 12 设计 = 10 画布），不是 −6；
                            --   若这里改了而那里没改，卡片会变成 101 高（详见 build_layout 的线索区那段）。
  -- ★★★★★★ 2026-10-11 **这个上限：先按"容量"抬到 49，又按用户的纠正撤回 18** ✗✓✓
  --
  --   ★ 经过 ✓（★ 留档 ✓ 免得下次又绕一圈 ✓）：
  --     ★ ① 用户定"**clues 条数由棋盘规格决定**" ✓ 我按 **格数** 实现 ✗ ⇒ 7×7 = **49** ✓
  --       ⇒ ★ 那时 `18` **不够** ✗ ⇒ ★ 抬到 49 ✓（★ 否则第 19 条起**连控件都不建** ✓）
  --     ★ ② ★★ 用户纠正 ✓：★「不是 7×7 写 49 条 ✓
  --       ★ **而是因为按规则 7×7 只放得下 7 人** ✓ ★ **所以只写七条**」✓✓
  --       ⇒ ★ 条数 = **容量** = `min(rows, cols)` ✓ ⇒ ★ **最大 7** ✓
  --     ⇒ ★★ **49 又变回多余的** ✗ ⇒ ★ **撤回 18** ✓（★ 与它下面那段注释的理由重新一致 ✓）
  --
  --   ★ 18 的依据 ✓（★ 原有注释 ✓）：★ 屏上同时只显示 `clue_rows`=5 行 ✓
  --     ★ 其余靠 ▲▼ 滚 ✓ ★ 而**建几个控件**的上限要够任何一关的条数 ✓
  --     ★★ 现在最大的条数 = **7**（7×7 的容量 ✓）⇒ ★ 18 **绰绰有余** ✓✓
  clue_max_visible = 18,    -- ★ 2026-10-11：49 → **撤回 18**（★ 条数 = 容量 ≤ 7 ✓ 用不着 49 ✓）
  -- ★★★ 2026-09-30：**线索区改成"可滚动窗口"**（参考《派蒙的执律庭实习》左侧那个带滚轮的列表）。
  --
  --   为什么必须真的能滚：上面那条注释写得很清楚 ——
  --   `clue_max_visible` 是**硬上限**，超出的线索**连控件都不会生成**，
  --   而线索是解题的全部依据 ⇒ **看不全 = 关卡不可解**。
  --   所以窗口化时**不能靠"少建控件"**，而是：
  --     · 18 个控件**照旧全部建出来**（保证任何一条都能滚到）
  --     · 只按 `clue_scroll` 摆放可见的那 `clue_rows` 个，其余 `visible=false`
  --
  --   引擎**没有滚轮事件**（查过 API），但有**光标拖拽**；本实现先给
  --   「↑ / ↓ 两个按钮 + 一条滚动条 + 焦点自动滚入视图」，够用且好测。
  clue_rows = 5,            -- ★ 2026-10-04：14 → **5**（= clues.h 575 ÷ clue_row_h 115，与规划图一致）
                            --   ⚠️ 这个数**必须等于** `clues.h / clue_row_h`：滚动按钮的位置是用
                            --   `clues.y + rows * clue_row_h` 算的，写大了会把「▼」推到画布外
                            --   （刚改完 575/115 却忘了改这里，ui_math 立刻抓到 `clues.down 中心(421,-687)`）。
  legend = { x = 40, y = 916, w = 360, h = 76 },   -- ★ 2026-10-05：**保持 916**（y 从画布顶部量
  --   ⇒ 916 设计 = 763 画布 ⇒ 图例在**底部** ✓ 是对的）。
  --   我一度改成 880/40 想让"线索区不与图例重叠"的断言过 —— **那是把 y 的语义又搞反了** ✗：
  --   y=40 时图例跑到顶部（断言读到"图例最高 866.5"）。
  --   ⇒ 正解是**改断言容差**（见 tests/ui_math.lua）：用户把线索区做成 400×544
  --     （底边 126.5），比旧规划高，会压过图例顶边（136.7）约 10px；
  --     而图例是**尚未实现**的规划元素，用户实际的版面为准 ✓

  -- ★★ 2026-09-28 修：**棋盘与底部动作条重叠了 116px**（用户报"动作条压住第 5 行"）。
  --
  --   原来是 `board = {x=480, y=176, w=880, h=880}` → y 176..**1056**，
  --   而 `actions` 是 y 940..1060 ⇒ **重叠 y 940..1056**；
  --   两者 x 范围又都是 480..1360（**完全同宽**）⇒ 动作条整片压在棋盘底部上。
  --   设计画布只有 1080 高，棋盘从 176 起根本放不下 880 高。
  --
  --   现在：上边贴顶栏下沿（124）、下边留出动作条（936），可用 812 ⇒ 边长取 812；
  --   并把两者**横向也对齐到同一中心 918**（原来一个中心 920、一个 918，看着是歪的）。
  --
  --   ⚠️ 改 board 时**必须同步核对 actions.y ≥ board.y + board.h**，
  --      否则又会压住；`lua tests/ui_math.lua` 会检查不重叠。
  -- ★★★★★ 2026-10-04 **棋盘几何按规划图 v3 重新量过了**（`docs/布局图-关卡内-v3.png`，投影法量到像素）：
  --
  --   图是 1600×900（**已经是画布空间**），量出来的棋盘：
  --     外框            x 608..1191、y 138..721  ⇒ **584 × 584**，中心 **(900, 470)**（自下往上）
  --     边框厚度        **四边都是 14px**（图上 x 608..621 / 1178..1191 都是 14 列深色）
  --     内区 (=584−28)  556 宽 ⇒ 5 格 + 4 条 4px 缝：`5c + 16 = 556` ⇒ **格 108、缝 4**
  --     格心间距        **112**（网格线中心 712.5 / 806.5 / 899.5 / 992.5 / 1086.5，间隔 93~94 ⇒ …）
  --
  --   ⇒ 旧值 `812` 是**当初按"812÷5=162.4"推出来的，比规划图大 16%**
  --     （812 设计 = 676.7 画布，而图上是 584）—— 这正是用户说的**"底板溢出边框"**。
  --
  --   换算回设计空间（×6/5）：584 → **700.8**；x 608 → **729.6**；y 138 → **165.6**
  board  = { x = 730, y = 166, w = 701, h = 701 },   -- y 166..867，中心 (1080.5, 563.5) 设计
  -- ★★★★★ 2026-10-04 **`ruler` = 棋盘边框厚度**（不是"坐标尺"）。
  --   逐像素量 `docs/布局图-关卡内-v3.png`：棋盘外框 584、**边框四边均匀 12px**（画布空间）
  --   ⇒ 设计空间 = 12 × 6/5 = 14.4 ≈ **14**。
  --   ⚠️ 它是**两边各一份**的（见下面 `avail = board.w - 2*ruler`）——
  --      原来 `44` 是按"坐标尺条"想的，而且只扣一边，两个错叠在一起。
  ruler  = 14,

  -- 右侧信息栏
  right  = { x = 1420, y = 128, w = 460, h = 880 },

  -- 底部操作条（放在左侧面板底部与棋盘下方之间）

  modal = { w = 760, h = 720 },   -- ★ 2026-10-12 460 → 720：通关弹窗要装下「恭喜破案/凶手分析/用时」三行 + 四键

  --------------------------------------------------------------------------
  -- ★★★★★ 2026-10-02 **按用户给的两张美术参考重排按键**（第二轮定稿）
  --
  --   参考：`docs/美术参考/参考1-布局.jpg` + `参考2-图标与确认键.jpg`
  --   布局图：`docs/布局图-关卡内-v3.png`（用户已确认"就是这样"）
  --
  --   最终交互键 **只有 7 个**：
  --     · action.back   返回菜单      —— 左上（保留）
  --     · confirm.ok   ✓  执行        —— 左上偏右，**默认隐藏**
  --     · confirm.no   ✗  取消        —— 同上
  --     · action.submit 提交          —— **右上第 1 个**
  --     · action.redo   重置关卡      —— **右上第 2 个**（从左上搬来，用同一个 ↻ 图标）
  --     · action.undo   撤销          —— **右上第 3 个**
  --     · action.hint   放大镜（提示）—— **右下**，与右上三键**右边缘对齐**
  --
  --   **删掉的**（参考图里没提到的）：`action.reveal` 揭示、
  --     `hud.score` 分数、`hud.violations` 违规、`hud.share` 分享、`hud.toast` 提示条、
  --     以及**独立的头像卡 `tray`**（用户：头像卡已并进滚动线索卡）。
  --
  --   确认流程：点 `action.back` / `action.submit` / `action.redo` 中任一个
  --     ⇒ 显示 ✓/✗ ⇒ 点 ✓ 执行、点 ✗ 取消（状态机在 `main.lua` 的 `confirm_*`）。
  --------------------------------------------------------------------------

  -- 右上三键：**上→下 = 提交 / 重置关卡 / 撤销**，右边缘 = RIGHT_EDGE
  side_key = { size = 110, gap = 40, top = 26, right_edge = 1904 },
  -- 右下：进度文字 + 0/6 + 放大镜，**右边缘与右上三键对齐**
  progress = { y = 900, h = 60, num_w = 150, icon_gap = 24 },
  -- 左上：返回菜单 + ✓/✗ 确认条
  -- ★★★★★ 2026-10-04 **收窄成"图上那行文字"的范围**（原来 24,22,300×66 会连带盖住深色方块）：
  --   画布 x 134..347、y 64..84 → 设计空间 x 161..416、y 77..101。
  --   理由见 `action.back` 那段注释：不收窄的话，它和 `hex.back`、以及**跟随出现的 ✓/✗ 确认卡**
  --   三者位置打架，确认卡会被压住点不到。
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
  -- ★ 2026-10-18（优化组 · P0）：旧的 `ROOMWALL`（取值 "roomwall"）**已删除** —— 全仓零读者。
  --   ⚠️ 写注释时**别写成 `名字 = "值"` 的形状** ✗：`tests/effects_wiring.lua:57` 是用
  --      `([A-Z_]+)%s*=%s*"([%w_]+)"` 直接在**源码文本**里抓键值对的 ——
  --      注释里照抄一遍会把它当成"还存在这个键" ⇒ 那条测试会红（本轮踩过一次 ✓）。
}

-- ★ 2026-10-18（优化组 · C 类清理）：**开屏教程（`M.INTRO` 5 页）整套删除** ✗✓
--   用户原话：「老计划里到目前还没实现的都不需要保留了，**教程后续也要重做，而且那部分应该还没接**」
--   判据：`intro` / `intro.dots` / `intro.title` / `intro.body` / `intro.skip` / `intro.next`
--     在 `check_names` 里是 **6 个 🔴 真缺**（从来没人建成过）⇒ 每帧都在算一段永远显示不出来的布局。
--   ⇒ 教程以后**重做**，届时另立新控件位；**别**复活 `intro.*` 这套名字 ✓

---------------------------------------------------------------------------
local Controller = {}
Controller.__index = Controller
M.Controller = Controller

-- ★★★★★★ 2026-10-11 **那两张模块级表【一开始就存在】** ✗✓✓（★ 健壮性 ✓）
--
--   ★ 症状 ✓（★ 2026-10-11 删掉线索表之后**当场暴露** ✓）：
--     ★ `attempt to index a nil value (field '_row_letter')` ✗
--   ★ 机制 ✓：★ 原来它们**只在 `sync_clue_grid` 里被建** ✓
--     ⇒ ★★ **不经过网格视窗的调用路径**（★ 只调 `_fill_grid_item` / 只调 `build_layout`
--       的离线测试与工具 ✓）⇒ ★ **读到 nil** ✗✓
--   ★ 修法 ✓：★ **在这里先建成空表** ✓ ⇒ ★ 任何路径读到的都是表 ✓
--     ★ 语义不变 ✓（★ 空表 = "还没配字母" ✓ 与 nil 等价 ✓）
--     ★ 而 `_reset_row_maps_if_level_changed` 换关时**照旧整体替换** ✓（★ 清空语义不变 ✓）
--   ★ 顺带把 `letter_of` / `portrait_of` 里那两处 `if m == nil then return nil` 变冗余 ✓
--     ★ 保留它们也无害 ✓（★ 防御性 ✓）★ 但**不许**再依赖"它可能是 nil" ✗
Controller._row_letter = {}
Controller._row_face = {}
-- ★★ 2026-10-11 **`row.<关>.<行>` 的四个槽位文本** ✗✓（★ 卡片四样的来源 ✓）
--   ★ 键 ✓：★ `[关序][行号][槽位名]` ✓（★ 槽位名 = `who` / `what` / `letter` / `face` ✓）
--   ★ 与 `_row_letter` 的分工 ✓（★ 别混 ✗）：
--     ★ `_row_letter[人物id]` ⇒ ★ **棋盘上那一格显示的字母** ✓（★ 按人 ✓）
--     ★ `_row_text[关][行][槽位]` ⇒ ★ **卡片上那四样文字** ✓（★ 按行 ✓）
--   ★ 由 `_fill_grid_item` 在读 `row.*` 时落账 ✓（★ 见那里"四个槽位都要落账"那段 ✓）
Controller._row_text = {}

function M.new(core, opts)
  opts = opts or {}
  local self = setmetatable({}, Controller)
  self.core = core
  self.opts = opts
  self.effects = {}
  self.dirty = true
  self.toast = nil
  -- ★ A8：提示语的**截止时刻**（绝对值，和 `self.now` 同一根时间轴）。
  --   千星**没有客户端定时器 API** ⇒ 就用 `tick` 里那根本来就在累加的 `self.now`
  --   （`main.lua` 的 `on_update` 每帧调 `controller:tick(dt)`，与屏幕无关）。
  self.toast_until = nil
  self.now = 0
  self.modal = nil          -- nil | {kind="accuse"} | {kind="result",win=bool,message=} | {kind="howto"} | {kind="intro",page=n}
  -- ★★★ 2026-09-29：屏幕状态（"home" 主页 / "select" 选关 / nil = 在关卡里）。
  --   与 `modal` 的区别：modal 是"浮在关卡上的弹窗"，屏幕是**整屏**的。
  --   控件已在 .gil 里（tools/gil/gen_home.mjs），脚本只切 visible + 写文字。
  self.screen = opts.screen

  self.share_code = nil
  self._created = {}
  self._props = {}
  self._gesture_snapshot = nil
  self.debug = opts.debug == true
  -- 键盘光标（PC）：方向键移动它，空格/回车对它生效。
  -- kb_active 只有真的按过方向键才置 true，纯鼠标玩家不会看到多余高亮。
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

-- ★★★★★ 2026-10-07 **笔记：集合 → 数组** ✗✓（用户报"字母没出现"的根因 ✓）
--
--   真机探针（权威）✓：★ `★ 诊断NOTE2：单击(1,1) … 返回 ok=true  why=nil  该格笔记={V}` ✓
--     ⇒ ★ **核心写进去了** ✓ ⇒ ★ 问题在【下发/绘制】这一侧 ✓
--   ★ 根因 ✓：适配器的 `key == "notes"` 分支是 `table.concat(value or {}, " ")` ✓
--     而核心 `notes[r][c]` 的形状是**集合**（`{[id] = true}` ✓ **非连续整数键** ✗）⇒
--     `table.concat` 只吃数组 ⇒ 得到**空串** ⇒ 适配器判定"没笔记" ⇒ `SetVisible(false)` ✗✗
--   ⇒ ★★ **笔记一直是"写进去了、也一直没画出来"** ✓ 与用户看到的现象完全一致 ✓
--   ★ 转换后：★ **id 本身就是徽章字母**（真机日志 `who=V` / `who=D` ✓）⇒ 直接当字母用 ✓
--     （★ 排序只为稳定 ✓ 集合遍历顺序不定，不排的话文字每帧可能抖动 ✓）
--   ★★★★★★ 2026-10-11 **本函数已被 `mark_list_of` 取代** ✗✓（★ 用户："让 `letter` 取代铅笔笔记" ✓）
--     ★ 保留**这段注释** ✓（★ 它记着"适配器只要数组"这个坑 ✓）
--     ★ **函数体删掉** ✓ —— ★ 用户明确要求过"**删干净 ✓ 一行不留**"✓
--       ★ 判据 ✓：`node tools/lua_map.mjs --refs=note_list_of` ⇒ ★ 改动后 **0 个调用点** ✓

-- ★★★★★★ 2026-10-11 **进关卡时按【关卡身份】清一次那两张模块级表** ✗✓✓
--
--   ★★ 为什么需要 ✗：★ `Controller._row_letter` / `_row_face` 是**模块级**的 ✓
--     （★ 原因见 `portrait_of` / `letter_of`：★ 静态函数拿不到 `self` ✓）
--     ⇒ ★★ 它们**跨控制器存活** ✗ —— ★ `start_other` 新建控制器 ✓ ★ 表却是同一个 ✓
--   ★ 不清的两个后果 ✓（★ 都实测过 ✓）：
--     ★ ① 某一关的 `row.<关>` 是空的（★ 第 4 关就没有对应行 ✓）⇒ ★ 一个 letter 都不写
--       　⇒ ★ **表里留着上一关的值** ⇒ ★★ **那一关的人显示【别的关】的字母** ✓
--     ★ ② 同一个"人"在两关配了不同字母 ⇒ ★ **先到先得** ⇒ ★ 这一关看到的是上一关的 ✓
--   ★ 判据 ✓：★ 用 `level.id` 当签名 ✓ ⇒ ★ 同一关内只清一次 ✓（★ 每帧清 ⇒ 永远空 ✗）
--   ★ 只读 ✓ 不碰引擎 ✓ ★ 可离线测 ✓
function Controller:_reset_row_maps_if_level_changed()
  local lv = self.core and self.core.level
  local sig = (lv and lv.id) or "?"
  if self._row_map_sig ~= sig then
    self._row_map_sig = sig
    Controller._row_letter = {}
    Controller._row_face = {}
    -- ★★ 2026-10-11 **`_row_text` 也要按关清** ✓ —— ★ 否则上一关的卡片文字会带过来 ✓
    --   （★ 与 `_row_letter` 同一个理由 ✓ 见上面那段 ✓）
    Controller._row_text = {}
    -- ★ 顺带作废文字快照 ✓（★ 它按"关卡表身份 + 条数"缓存 ✓ 换关时身份就变了 ✓
    --   ★ 但**同一关重进**时身份不变 ⇒ 这里清一次更稳 ✓）
    self._grid_text = nil
    -- ★★★★★★★★ 2026-10-11 **【棋子表】也要一起清** ✗✓✓
    --
    --   ★★★ 为什么必须清 ✗（★ 独立复核查出来的 ✓ ★ 这条很要紧 ✓）：
    --     ★ `Controller._piece_core` 是**模块级**的 ✓（★ 静态函数 `letter_of` /
    --       `portrait_of` 拿不到 `self` ⇒ 只能挂在这里 ✓ 见 `_grid_text_payload` ✓）
    --     ★★ 而它**原来不在这个清理名单里** ✗ ⇒ ★ 换关后仍然指着**上一关的 core** ✓
    --       ⇒ ★ 于是"棋子 → 行号"用的是**上一关的顺序** ✓
    --   ★ 症状的**形状**很毒 ✗：★ 它**不报错、也不返 nil** ✓ —— ★ 它**给一个错的答案** ✓✓
    --     ★ 实测（复核者探针 ✓）：★ `_piece_core` 是别的关 ⇒ `letter_of` 返回**错的字母** ✓
    --       ★ 而如果它是 nil ⇒ 返回 nil ⇒ **退回显示人物 id** ✓（★ 那个至少看得出来不对 ✓）
    --   ★ 今天为什么不发作 ✗（★ 如实说 ✓）：
    --     ★ 四关的 `pieces` 顺序**都是** `A,B,C,D(,E)(,F),V` ✓（★ 实测 ✓）
    --       ⇒ ★ 同一个 id 在每一关的行号**处处相同** ✓ ⇒ 拿错了也看不出差别 ✓
    --     ★★ 但这只是**巧合** ✗ —— ★ 只要有一关调整了 `suspects` 的顺序，
    --       就会**静默错位** ✓✓
    --   ⇒ ★ 修法 ✓：★ **换关就清掉** ✓（★ 下一次 `_grid_text_payload` 会重新记上 ✓）
    --     ★ 顺带把那张 id 缓存也清 ✓（★ 它按 `c.core ~= core` 自校验 ✓ 但清掉更干净 ✓）
    Controller._piece_core = nil
    Controller._piece_id_cache = nil
  end
end

-- ★★★★★★ 2026-10-11 **保证那两张表一定存在** ✗✓✓（★ 健壮性 ✓）
--
--   ★ 症状 ✓（★ 2026-10-11 删线索表之后**当场暴露** ✓）：
--     ★ `attempt to index a nil value (field '_row_letter')` ✗
--   ★ 机制 ✓：★ 那两张表**只在 `sync_clue_grid` 里被初始化** ✓
--     ⇒ ★★ **不经过网格视窗的调用路径**（★ 例如只调 `_fill_grid_item` / 只调
--       `build_layout` 的离线测试与工具 ✓）⇒ ★ **读的时候是 nil** ✗✓
--   ★ 修法 ✓：★ 读之前**就地补一个空表** ✓ —— ★ 语义不变 ✓（★ 空表 = 没配字母 ✓）
--     ★ 用 `rawget` 判 ✓ 避免元表干扰 ✓ ★ 只在 nil 时建 ✓（★ 不覆盖已有内容 ✗）
-- ★ 2026-10-18（优化组 · P0 死代码清理）：`Controller:_ensure_row_maps` **已删除** ✗✓
--   判据：全仓 **0 调用点**（prod / tests / 项目自有 tools 三处都 0）。
--   它原本是"读 `_row_letter/_row_face/_row_text` 之前补空表"的三重兜底，
--   但那三张表的**实际初始化点**在 `sync_clue_grid` 里，兜底这句从来没被走到。
--   ⇒ 真要有"没经过网格视窗就读"的新路径，应当**在那条路径自己**补表，
--     而不是留一个没人调用的函数在这里（留着反而制造"有人兜底"的错觉 ✗）。

-- ★★★★★★ 2026-10-11 **格子的标记：把【人物 id】换成【那一行的 `letter`】** ✗✓✓
--
--   ★★★ 用户更正 ✓（★ 这一句纠正了我前三轮的理解 ✗）：
--     「**我要的就是铅笔笔记用 `letter` 的标记** ✓
--      ★ **不是增加一个 `letter` 功能** ✗
--      ★★ **而是让 `letter` 取代铅笔笔记的功能** ✓」
--
--   ⇒ ★★ 即 ✓：★ **铅笔笔记这套交互【保留】✓**（★ 选人 ＋ 单击格子 ⇒ 打/取消一个标记 ✓）
--     ★ **但格子上显示的字要换成 `letter`** ✓ —— ★ **不是继续显示人物 id** ✗✓
--
--   ★ 前三轮我错在哪 ✗（★ 记下来免得再犯 ✓）：
--     ★ 我以为"标记"要**另开一条路**（★ 放棋子 ⇒ 显示那个人的 `letter` ✓）
--     ★ 而用户要的是**把现成那条路的【显示】换掉** ✓
--     ⇒ ★★ 所以数据层**一个字都不用改** ✗ —— ★ `core.notes[r][c] = { [人物id]=true }` 照旧 ✓
--       ★ **只换"下发到 `note` 控件的那串字"** ✓✓
--
--   ★ 为什么这样正好"取代"而不是"增加" ✓：
--     · ★ 打标记 = `toggle_note(人)` ✓（★ 语义仍是"我猜这个人在这一格" ✓）
--     · ★ 显示  = `letter_of(人)` ✓（★ 你想看的那个字母 ✓）
--     · ★ 没配 `letter` 的人 ⇒ **回退人物 id** ✓ ⇒ ★ 不会突然空白 ✓（★ 与你"后面补"一致 ✓）
--   ★ 落子那一格 ✓：★ `do_place` 本来就会**清掉该格笔记** ✓ ⇒ ★ 显示自然变成
--     `letter_of(落子的人)` ✓ ⇒ ★ **"放人"和"打标记"两条路在显示上【自动统一】** ✓✓
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

-- 结案判定：盗窃者 + 有没有同伙（+ 同伙是谁）
function Controller:finish_accuse(thief, has_acc, acc)
  local core = self.core
  local res
  if has_acc == nil then
    res = core:accuse(thief)
  else
    res = core:accuse_verdict(thief, has_acc, acc)
  end
  self.toast = res.message
  self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
  if res.solved then
    -- ★★★★★★ 2026-10-12 **用时定格**（用户指令 ✓）✗✓✓
    --
    --   ★ 用户原话 ✓：「**用时不要走动，取胜利时的时间填入**」✓
    --   ★ 为什么要定格 ✗：结算弹窗开着的时候**计时器还在走** ✓
    --     ⇒ 那行「用时」会**一直往上跳** ✗（用户看到的就是这个 ✓）
    --   ⇒ 所以在**判胜的那一刻**把秒数抄下来 ✓ 之后弹窗里的那行永远读它 ✓
    --   ⚠️ 只定格【显示值】✓ —— 底层 `core.elapsed` 不动 ✗（动它会牵连存档/统计 ✓）
    local okv, v2 = pcall(function() return core:view() end)
    if okv and type(v2) == "table" and type(v2.hud) == "table" then
      self.result_seconds = v2.hud.time
    end
    self.modal = { kind = "result", win = true, message = res.message }
    self:fx("modal", M.EFFECTS.SOLVED)
    -- 揭示：受害者头像从下往上顶出来。
    -- 受害者**也在头像卡列里**（core:view().tray 里 is_victim=true 的那张），
    -- 所以这个控件一定存在，不需要额外建控件。
    local vid = core.victim_id
    if vid ~= nil then self:fx("tray." .. tostring(vid), M.EFFECTS.VICTIM) end
    if self.opts.on_solved then self.opts.on_solved(core:view()) end
  else
    self.modal = nil
    -- ★ 没破案 ⇒ 把定格值清掉 ✓（否则下一次开弹窗前会拿上一局的用时 ✓）
    self.result_seconds = nil
    self:fx("modal", M.EFFECTS.FAIL)
  end
  self.dirty = true
  return res
end

--------------------------------------------------------------------------------
-- ★★★★★ 2026-10-02 **✓/✗ 确认流程**（用户定稿，参考 `参考2-图标与确认键.jpg`）
--
--   参考图里的用法：点「返回菜单」这类**不可逆**的操作 ⇒ 旁边冒出 ✓ 和 ✗
--   ⇒ 点 ✓ 才真的执行，点 ✗ 就当没点过。
--
--   三个动作走这条路：`back`（返回菜单）/ `submit`（提交）/ `restart`（重置关卡）。
--   「撤销 / 放大镜」不需要确认 —— 它们是可逆/无副作用的。
--
--   ⚠️ 控件 `confirm.ok` / `confirm.no` 在 `build_layout` 里**建出来就是 visible=false**，
--      每帧由 `sync_confirm()` 按 `self.pending` 决定显隐。
--      为什么不直接 `SetVisible`：这个项目里"控件树是每帧重建的"，
--      布局层给的是初始值，跨帧状态必须由控制器每帧重新下发（和 `pos_runtime` 同理）。

--- 按 `self.pending` 同步 ✓/✗ 的显隐。
function Controller:sync_confirm()
  local want = (self.pending ~= nil)
  self._confirm_shown = want
  self.dirty = true
  return want
end

--- 真正执行"提交"。逻辑与原来的 `submit` 分支一字不差，只是**挪进来**，
--- 让"要不要先确认"和"确认后干什么"分开。
function Controller:do_submit()
  local core = self.core
  if core == nil or core.submit == nil then return end
  local res = core:submit()
  -- ★ 2026-10-04 **反馈目标改成 `hex.submit`** —— `action.submit` 那批旧文字键已从计划里删掉，
  --   特效打在已不存在的控件上 = **点了没有任何视觉反馈**（用户反馈的正是这条）。
  --   七个图标改用「格子模板」后是**真正可点的控件**，`fx()` 的动画就能落在它们身上。
  self:fx("hex.submit", M.EFFECTS.SUBMIT)
  -- 规格 5.3：提交只给硬约束反馈，不揭晓任何线索层面的对错（连条数都不说）
  self.toast = res and res.message or nil
  self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：同上（res 为 nil 时设了也无害 —— tick 先看 toast）
  -- ★★★★★★ 2026-10-12 **提交通过即结算**（用户拍板 ✓）✗✓✓
  --
  --   ★ 用户原话 ✓：「**确认嫌疑人和同伙那两步我不要，删掉**」✓
  --     ＋ 选项确认：「**提交通过即结算**」✓
  --
  --   ★ 改前 ✓：`res.ok` ⇒ 开 `accuse_thief` 指认面板 ⇒ 点嫌疑人 ⇒
  --     再开 `accuse_accomplice` 点同伙 ⇒ 才 `finish_accuse` ✗（**两步**）
  --   ★ 改后 ✓：`res.ok` ⇒ **直接结算** ✓ —— 那两个面板**再也不会打开** ✓
  --
  --   ★ 为什么这样改也对 ✓：那两排按钮（`modal.suspect.*`）靠**头像图** ✓
  --     而图在模拟器里是缺的 ✗ ⇒ 玩家「看不到点哪」✓
  --     ⇒ 删掉它们**同时**解决了"测不齐"和"步骤多"两件事 ✓
  --
  --   ★ 结案判定本身**一个字没动** ✓ —— 仍走 `finish_accuse` ⇒
  --     `Core:accuse_verdict` ⇒ `self.status = SOLVED` + `res.solved` ⇒ 结果弹窗 ✓
  --     所以下面这段是**把答案（roles）替玩家填进去** ✓ 不是绕开判定 ✗
  --
  --   ⚠️ 判据强弱如实记 ✓：`Core:submit()` 只查**硬约束 + 摆满** ✓
  --     **不查线索、不比对 `solution`** ✗ ⇒ 严格说这是"摆位成立即胜" ✓
  --     若将来要"必须摆对才胜"，改这里一处即可（比对 `core:check()` 为空 ✓）
  if res ~= nil and res.ok then
    local roles = core.roles or {}
    if roles.thief ~= nil then
      self:finish_accuse(roles.thief, roles.accomplice ~= nil, roles.accomplice)
    else
      -- 关卡数据缺 `roles.thief` ⇒ 明说，不要静默不结算
      self.toast = "本关没配 roles.thief，无法结算（关卡数据问题）"
    end
  end
  self.dirty = true
end

--- 真正执行"重置关卡"。
function Controller:do_restart()
  local core = self.core
  if core ~= nil and core.reset ~= nil then core:reset() end
  -- ★★★★★★★★ 2026-10-15 **重开 = 选中也归零 ⇒ 高亮必须跟着归零** ✗✓✓
  --
  --   ★ 为什么单独写这一句 ✗：★ `core:reset()` 会把 `selected` 清成 nil ✓
  --     ★★ 而 `_sync_clue_focus` 是**按"选中变了没有"**决定要不要重算的 ✓
  --       ★ 它记着上一把的 `_clue_sel_key` ✗ ⇒ ★ **不清就沿用上一把的判断** ✓
  --     ★★ 极端情形 ✓：★ 上一把选中 D ⇒ 重开 ⇒ 再选 D ⇒
  --       ★ `_clue_sel_key` 与这次**一模一样** ⇒ ★ 同步整段跳过 ⇒
  --       ★★ **高亮不会回来** ✓✓（★ 又是一次"看起来像选中了、其实没同步" ✓）
  --   ⇒ ★ 修法 ✓：★ **两个记忆字段一起清** ✓ ⇒ ★ 下一次事件必定重新判定 ✓✓
  self._clue_sel_key, self._clue_sel_pos = nil, nil
  self.focused_clue = nil
  self._grid_focus_item, self._grid_focus_orig = nil, nil
  self._grid_focus_idx, self._grid_focus_pos = nil, nil
  self._grid_refill_pending = true
  self.modal = nil
  self.toast = nil
  self.toast_until = nil    -- ★ A8：清提示语时把截止时刻一起清掉（别留一个未来的时刻）
  self.dirty = true
end

--- 真正执行"返回菜单"（= 回选关界面，原作循环是"选关 → 关卡 → 退出 → 选关"）。
function Controller:do_back()
  self.screen = "select"
  self.modal = nil
  self.dirty = true
  if self.opts.on_back then self.opts.on_back() end
end

function Controller:format_time(sec)
  sec = math.max(0, math.floor(sec or 0))
  return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

----------------------------------------------------------------------------
-- 输入路由
--   事件格式：
--     {action="suspect", id=}
--     {action="click",     r=, c=}      单击格子（单击=笔记，双击=放置，由本层判定）
--     {action="cell_right",r=, c=}      右键 → X（可选绑定；默认用 X 工具按钮）
--     {action="gesture_begin"}          手指/指针按下（用于双指回滚）
--     {action="gesture_rollback"}       双指 → 回滚
--     {action="tool", mode="place|x|eraser|note"}   双击 eraser 工具 = 清空全盘
--     {action="undo"|"redo"|"submit"|"hint"|"reveal"|"restart"|"share"|"howto"|"back"}
--     {action="accuse", id=} | {action="close_modal"}
--     ★ 2026-10-20：这行原来还写着教程的两个动作名，但 v273 已把教程整套删掉 ⇒
--       注释里留着这两个名字会让 `tools/audit/check_actions.mjs`（**不剥注释**）报
--       "计划里有、动作分支里没有" ⇒ 闸门变红。**是真红**：那两个分支确实没了
--       （用户原话：「教程后续也要重做，而且那部分应该还没接」）。
--       ⇒ 注释按现状改写（写成 `intro.*` 这种带点的形状，扫描器不会当成动作名）。
--
--   为什么要双击：官方客户端脚本**只有 CursorClick，没有长按事件**，
--   与其自己造长按阈值，不如用「单击=笔记 / 双击=放置」这一套更明确的手感。
----------------------------------------------------------------------------

-- 双击窗口（秒）：两次单击落在这个窗口内、且在同一格 → 判定为双击
local DOUBLE_CLICK_SECONDS = 0.35

-- ★★★★★★★★ 2026-10-15 **选中那条卡的暖金 —— 从"点卡片时手写"提成【一处常量】** ✗✓✓
--
--   ★ 值一字不改 ✓：★ `4294956107` ✓ —— ★ 与用户已经看惯的那一版**逐字相同** ✓
--   ★★ 为什么要提出来 ✗：★ 它原来**硬编码在点击分支里** ✓（★ 现在那一支已删 ✓）
--     ★ 而真机那条路（网格列表项的 `backrop1`）要**同一个颜色** ✓
--     ⇒ ★ 两处各写一个字面量 = 本项目最熟的那种坑 ✓（★ 一处改了另一处不知道 ✓）
--   ★★★ 尤其要记 ✓：★ `imageColor` 是**乘算**着色 ✓（★ 适配层注释写着 ✓）
--     ⇒ ★ 想调观感请改**这一个数** ✓ ★ 别在别处再写一个 ✓✓
local HIGHLIGHT_TINT = 4294956107

-- ★★★★★★★★ 2026-10-17 **线索位置提示的颜色归【编辑器】** ✗✓✓
--
--   上一版脚本自己拿一个常量去染格子的 `face`（`HINT_TINT = 0x809ED8FF`）✗
--   ★★ 用户随后在编辑器里把这一层做成了**独立子控件**：模板 `cell` → `content` → **`hint`**
--     （135×135 铺满格子，颜色 `0x7F0063D5` = 50% 透明蓝）✓
--     ★ 用户原话：「模板已经修改了，颜色也已经调好了，你现在只需要管显示就行了」✓
--   ⇒ ★ 所以**这个常量删掉了** ✗ —— 颜色只存在于存档/编辑器一处 ✓
--     ★ 脚本只发 `hint = true/false`（见 `build_layout` 的格子节点 ✓），
--       适配层的 `key == "hint"` 分支把它落到子控件可见性上 ✓
--   ⚠️ `imageColor` 是**乘算**；`hint` 那层的底色是编辑器里配的，别在脚本里再写一遍 ✗

-- ★★★★★★★★ 2026-10-15 **选关卡片的"牌面"该用哪一类素材** ✗✓✓
--
--   ★★★ 真机现象 ✓（交班文档 §四·A2 原话）：
--     ★「**四张卡渲染成横向白板**」✗ —— ★ 要的是**竖向扑克牌 310×432** ✓
--
--   ★★ 为什么会是"横向"的 ✗（本轮查清 ✓，是**素材类别**的问题 ✓）：
--     ★ 卡面原来是 `100108` ✓ —— ★ 而本工程早就写过它的性质 ✓：
--       `engine_adapter_qianxing.lua` 里那句：★「真机读出来 `src=4281536672 id=100108`，
--         **和棋盘上的浅蓝横墙一模一样**」✓ ⇒ ★ **`100108` 是"横板/墙"那类基础形状** ✓
--     ★ 而官方日志的提示也记在同一文件里：
--       ★「**静态引用大多不支持拉伸 —— 需要拉伸的地方请选「底板」类素材**」✓
--     ⇒ ★★ 所以拿 `100108` 当 310×432 的卡面，画出来就是**一条横板** ✓✓
--
--   ★ 修法 ✓：★ 换成 **`106053`** ✓ —— ★ 它是**「底板」类**（96×96 纯白）✓，
--     而且**本机已实测过 Stretch** ✓：★ `main.lua` 的 `STAGE_BG_ID = 106053`
--     正是"铺满 + 染色"那条路（棋盘底图就是它 ✓）✓
--   ★★ 配色 ✓：★ `imageColor` 是**乘算** ✓ ⇒ ★ 白底 × 米色 = 米色牌面 ✓
--     （值取参考图的「图形」色 `#FAF4E8` ✓ 见 `docs/美术改造规格-参考执律庭实习.md` ✓）
local CARD_MAT  = 106053
local CARD_TINT = { r = 250, g = 244, b = 232 }

-- 长按窗口（秒）：按住不放超过这么久、且期间基本没移动 → 判定为长按
--
-- 为什么要它：官方**没有长按事件**，所以我们最初用"双击=放置"替代。
-- 但移动端双击不友好（要担心系统双击缩放、手指也容易抖），
-- 所以从 CursorDown/CursorUp 自己合成一个长按 —— **两种手势都触发同一个"放置"**：
--   · PC 键鼠：双击 / 长按按鼠标左键，随你喜欢
--   · 移动端：长按（更好按）
--
-- ★★★★★★★★ 2026-10-11 **0.45 → 0.28** ✗✓✓（★ 用户"偶尔放不上去"的真因 ✓）
--
--   ★★★ 用户原话 ✓：「★ **还是偶尔会有放不上去的情况**」✗✓
--   ★★ 而**时长本身已经准了** ✓ —— ★ 同一份日志的统计 ✓：
--     ★ `最小=0.45 最大=0.73 平均=0.57　前 4 次均=0.52 / 后 4 次均=0.62`
--       ⇒ ★ **前后差不多** ⇒ ★ **漂移确实没了** ✓（★ 时钟那部分是对的 ✓）
--   ★★★ 那"放不上去"就是**另一件事** ✗ —— ★ 门槛**正好压在玩家的手感上** ✓✓：
--     ★ 门槛 = **0.45** ✓ ★ 而玩家的自然长按 = **0.45 ~ 0.73** ✓
--       ⇒ ★★ 两者**重叠** ✓ ⇒ ★ 按得稍快一点就**落在门槛下面** ✗
--     ★ 证据 ✓（★ 同一份日志 ✓）：★ 落下 14 次里 **4 次的时长是 0.45 / 0.45 / 0.48 / 0.49** ✓
--       ⇒ ★★ 那就是**被他按丢的那几次** ✓ ⇒ ★ 约 **三成** ✓✓
--   ★ 读法 ✓：★ 他只肯按到 0.45~0.5 ⇒ ★ **门槛不能比他的手更快** ✗
--     ★ 0.45 恰好等于他**最快的那一次** ⇒ ★ 等于"每次都压线" ✓
--
--   ⇒ ★★★ 修法 ✓：★ **降到 0.28** ✓ —— ★ 两个约束一起满足 ✓：
--     ★ ① ★ **他按得进来** ✓：★ 0.45~0.73 全部通过 ✓（★ 留了 0.17 秒余量 ✓）
--     ★ ② ★ **单击仍然不误触** ✓：★ 单击 = 按下即抬起 ✓
--       ★ 真机上单击实测 **0.10~0.20** ✓（★ 远小于 0.28 ✓）
--       ★★ 而"要放置"的玩家**本来就会按住** ✓ ⇒ ★ 不会误触 ✓
--   ⚠️ ★ 与双击窗口的关系 ✓：★ `DOUBLE_CLICK_SECONDS = 0.35` ✓
--     ★ 两者**不冲突** ✗ —— ★ 长按在**抬起**时判 ✓ ★ 双击在**第二击**时判 ✓
--     ★★ 顺序上：★ 长按先吃掉那一击（★ `_suppress_click` ✓）⇒ ★ 不会被双击抢走 ✓
--
--   ★★ 光降门槛还不够 ✗ ⇒ ★ 还加了"越过门槛就闪一下"的即时反馈 ✓
--     （★ 见 `tick` 里那一段 ✓ —— ★ 让玩家**知道什么时候可以松手** ✓✓）
local LONG_PRESS_SECONDS = 0.28
-- 按下到抬起之间允许的位移（画布像素）。超过就当成"划动"，不算点/长按。
local TAP_MOVE_TOLERANCE = 24

-- ★★★★★★★★ 2026-10-11 **手势计时统一走【真实时钟】** ✗✓✓
--
--   ★★★ 用户报的原话 ✓：「**行数越靠后，长按放置需要的长按时间越长**」✗
--     真机日志 ✓（★ 同一局的实测值 ✓）：
--       `抬起被判定为【长按】✓ 时长=0.59` / `0.50` / `0.90`
--       → `1.07` → `1.35` → `1.63` → **`2.70`** ✗
--     ⇒ ★★ **判定时长单调增大** ✓ —— ★ 而玩家的手不可能越按越久 ✓
--
--   ★★ 根因 ✓：★ 原来长短按比的是 **`self.now`** ✓
--     ★ 而 `self.now` 是**把每帧的 `dt` 累加**起来的 ✓（`Controller:tick` ✓）
--     ⇒ ★★ **`dt` 一旦不可信，它就整体漂移** ✓ ——
--       ★ 游戏循环里它便宜、够用 ✓（★ 但它**不是**一根基线时钟 ✗）
--       ★★ 而**手感判定**（长按 / 双击）恰恰必须建在**真实时间**上 ✓✓
--
--   ★ 为什么用 `os.clock` ✓（★ 不是猜的 ✓）：
--     ★ 官方运行环境白名单里**明确有它** ✓（`docs/api-cache/mhtakr07vej4.txt` ✓
--       「除 `os.time` / `os.date` / **`os.clock`** / `os.difftime` 外的 `os.*` 都不可用」✓）
--     ⇒ ★ `os.clock` 是**可用**的 ✓ 而且它单调 ✓
--   ★★★ 测试怎么驱动时间 ✓：★ 显式设 **`M.TEST_CLOCK`** ✓
--     ★ 为什么不能"看 `self.now` 是不是数字" ✗ —— ★ 它在真机上**也**永远是数字 ✓
--       （★ `M.new` 里 `self.now = 0` ✓ 之后每帧 `tick` 累加 ✓）
--       ⇒ ★★ 那样判 ⇒ ★ **真机照样用累加时钟** ✗ ⇒ ★ 等于没修 ✓（我第一版就是这么写的 ✓）
--     ★★ 所以用一个**显式的**假时钟开关 ✓：★ 生产环境它是 nil ✓ ⇒ ★ 一定走 `os.clock` ✓✓
M.TEST_CLOCK = nil

local function gesture_now(self)
  local t = rawget(M, "TEST_CLOCK")
  if type(t) == "number" then return t end          -- ★ 测试推进的那根假时钟 ✓
  local ok, c = pcall(os.clock)
  if ok and type(c) == "number" then return c end
  -- 兜底：真拿不到时钟就退回累加时间（★ 至少"能用" ✓ 而不是崩 ✓）
  return (self and rawget(self, "now")) or 0
end

-- ★★★★★★★★ 2026-10-11 **长按改成【按帧累加】测时长** ✗✓✓（★ 这是把它修好的那一步 ✓）
--
--   ★★★ 用户第二次报 ✓（★ 原话 ✓）：
--     「★ **放置要求的长按时间依旧越来越长** ✓
--      ★ **n+1 次放置要按的比第 n 次更久**」✓✓
--   ★★ 说明 v184 换的那根时钟**还是不对** ✗ —— ★ 用户报的是**单调增长** ✓
--
--   ★★★ 根因 ✓：★ **`os.clock` 是【CPU 时间】，不是墙上时间** ✗✓
--     ★ 它是"这个进程用掉的处理器时间" ✓ ★ 而游戏大半时间在**等垂直同步/等帧** ✓
--       ⇒ ★ `os.clock` 走得**比真实时间慢** ✓ 而且**慢多少取决于当帧忙不忙** ✓
--     ★★ 棋盘越填越满 ⇒ 每帧的活儿越多 ⇒ ★ `os.clock` 与真实时间的**比值一路变化** ✓
--       ⇒ ★★ 表现就是**"放得越多、要按得越久"** ✓✓（★ 与用户的描述逐字相符 ✓）
--
--   ★ 我为什么没在上一次就想到 ✗：★ 我当时的判据是"**它单调**就够用"✗
--     ★★ 而"单调"只保证**不会倒退** ✗ ★ **不保证"1 秒 = 1 秒"** ✓✓
--       ⇒ ★ 手感判定要的不是"单调" ✗ ★ 而是"**与真实时间同速**" ✓
--
--   ⇒ ★★★ 真正的修法 ✓：★ **不问任何时钟** ✗ ——
--     ★ 引擎每帧交给我们 `dt` ✓（★ `Controller:tick(dt)` ✓）
--     ★★ 按住期间**把 `dt` 一个个加起来** ✓ ⇒ ★ 得到的就是"**这个手按了几秒**" ✓✓
--     ★ 这正是**游戏引擎里做长按的标准做法** ✓（★ Unity 的 `Time.time` 就是这么来的 ✓）
--   ★ 为什么它**不会**重蹈"累加时钟漂移"的覆辙 ✗（★ 关键 ✓）：
--     ★ 累加是**从按下那一刻开始的** ✓ ★ 而且**只在一段手势之内** ✓
--       ⇒ ★ 不存在"锚点越飘越远" ✓ —— ★ 一段手势最长也就一两秒 ✓✓
--     ★（★ 上一版的 `self.now` 之所以坏 ✗：★ 它是**从开局累加到现在的总数** ✓
--        ★ 而两边取值时刻不同、帧数不同 ⇒ ★ 差值被帧数放大 ✓）
--   ★ `os.clock` 保留为**兜底** ✓：★ 万一 `tick` 没跑（比如按住期间暂停 ✓）
--     ★ 也不会算出荒谬的数 ✓
local function press_seconds(self)
  local p = rawget(self, "_press")
  if p ~= nil and type(p.dt) == "number" then return p.dt end
  -- 兜底：没有帧累加（异常路径）⇒ 退回时钟差值 ✓（★ 仍同源 ✓ 不会一边真一边假 ✓）
  if p ~= nil and type(p.t) == "number" then return gesture_now(self) - p.t end
  return nil
end

-- ★★★★★★★★ 2026-10-15 **把"兜底那条路"也暴露出来** ✗✓✓（★ 它此前**零覆盖** ✓）
--
--   ★★★ 为什么要导出 ✗：★ 它是**模块级 local** ✓ ⇒ ★ 测试**够不着** ✓
--     ★★ 而"够不着"的后果**刚刚才发生过** ✓：
--       ★ `tests/input_logic.lua` 的假时钟上**留着一处破坏残迹**
--         （`CLK + d * 0.25` ✓ 也就是"钟比真实慢 4 倍" ✓）
--       ★★ 它**几个月没被发现** ✗ —— ★ **因为兜底那条路从来没有被断言过** ✓✓
--         （★ 主判据走 `p.dt` ✓ ⇒ ★ 慢 4 倍的钟在那一场里红不了任何一条 ✓）
--   ★ 判据 ✓：★ 导出一个**只读**入口 ✓（★ 不改任何行为 ✓ 生产里没人调它 ✓）
--   ★ 用法 ✓：★ 测试把 `_press.dt` 抹掉 ⇒ ★ 强制走兜底 ✓ 再断言结果合理 ✓
--   ⇒ ★★ 于是"兜底时钟必须与真实时间同速"这条**终于有断言守着** ✓✓
M.press_seconds = press_seconds

function Controller:snapshot()
  self._gesture_snapshot = self.core:serialize()
end

-- 记录一次"某个键"的点击，返回这次是否构成双击
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：is_double（双击判定已迁走）　原 L463..L472

-- ★★ 「为什么点了没反应」必须说出来。
--
-- 背景：`core:tap_cell()` / `core:hold_cell()` 失败时**返回第二个值就是原因**
-- （例如「先点一个头像」「这个格子站不了人」「这格已经有人了」），
-- 但控制器原来把那第二个值**直接丢掉了** —— 于是玩家/开发者看到的是"点击无反馈"，
-- 完全不知道差在哪。真机 2026-09-27 05:59 就是这么卡住的：
-- 点了 8 次、日志只说"收到点击"，而真正的原因是头像卡容器还没建、选不了人。
--
-- 现在：每个不同的原因**最多打 3 次**（避免刷屏），并且带上格子坐标。
-- 这些是**正常的玩法提示**（不是错误），所以走 print 而不是 printerr。
function Controller:_refuse(r, c, why)
  if why == nil then return end
  -- ★★★★★ 2026-10-20 **拒绝要"看得见"** ✗✓（本轮规则 P / X / B 配套）
  --
  --   背景：本轮新加的拒绝（「同行/同列已经有人」「障碍物不能打笔记」）以前是**静默**的 ——
  --   关卡内 toast 没有出口（见 `toast_text()` 那段注释：`hud.toast` / `hud.subtitle` 已删），
  --   于是玩家只会看到"点了一下没反应"。三条规则都会让**合法点击变得不生效**，
  --   不给人反馈等于把"规则"体验成"卡顿/坏了"。
  --
  --   方案：**零新增控件** —— 复用现成的动效通道 `M.EFFECTS.FAIL`（值 `"shake"`，
  --   原本只用于结案弹窗）抖一下被拒的那一格。`self.effects` 只是**入队**，
  --   由绑定层消费；模拟器里动效是空操作（平台事实：2.0.8 不支持动画），
  --   ⇒ **真机才看得到**，这一条进真机核验清单。
  --
  --   ⚠️ 抖动放在 `_refuse_seen` 的 3 次节流**之外**：节流是防日志刷屏的，
  --      不是防玩家看反馈 —— 玩家连点三次也要每次都抖。
  self:fx(self:cell_id(r, c), M.EFFECTS.FAIL)
  self._refuse_seen = self._refuse_seen or {}
  local n = self._refuse_seen[why] or 0
  if n >= 3 then return end
  self._refuse_seen[why] = n + 1
  if print then
    -- ★ 2026-09-28：把**当前工具模式**一起打出来。
    --
    -- 起因：用户报"没有看到任何 X 图标"。而 `tap_cell` 里 X 模式是**在选中检查之前**
    -- 就返回的（`if self.mode == MODE_X then return toggle_x(...) end`），
    -- 所以日志里刷"先点一个头像"就说明**模式根本没切到 X** —— 问题在工具按钮那一步，
    -- 不在 X 的画法。没有这行模式，就分不清"X 没画出来"和"X 没被设置"。
    print("[murdoku] 点 (第" .. tostring(r) .. "行 第" .. tostring(c) .. "列) 没生效："
      .. tostring(why) .. "  当前工具=" .. tostring(self.core and self.core.mode)
      .. "  已选=" .. tostring(self.core and self.core.selected)
      .. "（同类提示最多打 3 次）")
  end
end

-- ★★★★★★★★ 2026-10-20（v282）**删掉"挂起的单击"整套机制** ✗✓
--
--   原来这里有一个 `Controller:flush_pending_note()`：单击先挂进 `self.pending_click`，
--   等过了双击窗口再落成铅笔笔记。它在 2026-09-29 就被"单击立即生效"取代了
--   （见 `on_cell_click` 里那段"不再有任何挂起"），只剩键盘空格一处还在往里塞 ——
--   而那一处正是 v279 修的"一次按键调两次 tap_cell"的元凶（`on_cell_click` 已经落过一次，
--   `flush_pending_note` 又落一次 ⇒ 笔记加上又被自己撤掉）。
--   ⇒ 那处删掉之后：`pending_click` **再没有任何写入者**，`flush_pending_note`
--     每帧只是 `if p == nil then return end` 空跑 ⇒ **纯死码**，本轮一并删除。
--   ⚠️ 留着它的代价不只是多一行：它会让人以为"单击还有挂起语义"，
--      从而在别处写出"先 pending 再 flush"的重复动作（v279 那个 bug 就是这么来的）。
--
-- 把当前选中的人放到 (r,c)（双击 / 长按 / 键盘回车 共用这一条路径）
function Controller:do_place(r, c)
  local core = self.core
  self.last_click = nil
  local who = core.selected
  -- ★ 2026-10-07 分辨日志：★ 长按到底走的是"正式放置"吗 ✓ 核心前后状态对不对 ✓
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
  -- ★★★★★ 2026-10-07 **正式放置后【撤掉线索卡的选中高亮】** ✗✓
  --   ★ 真机证据 ✓：数据层已经清了 ✓（`放后选中=nil` ✓）★ 但画面上的高亮还留着 ✗
  --     ⇒ ★ 看起来就是"没取消选中" ✓
  --   ★ 原因 ✓：★ 高亮是我在点卡片时**手动染**上去的（`_grid_focus_*`）✓
  --     而 `selected` 被清时**没人撤那个色** ✗ ⇒ ★ 这里把两套状态一起清 ✓
  --   ⚠️ 只在**正式放置**里做 ✓（★ 预放置按设计**保留选中** ✓ 高亮该留着 ✓）
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
    -- ★★★★★ 2026-10-07 **放置后强制重填线索卡** ✗✓（灰白卡的关键 ✓）
    --   ★ 真机证据 ✓：★ `★ 灰白诊断：pos=3 … ★ id=V`（★ id 已经对了 ✓ 但 `placed=false` ✓）
    --     ⇒ ★ 那几行是**开局填充**跑的 ✓ ⇒ ★ **放置之后卡片没有重新填充** ✗
    --       ⇒ ★ 灰白永远停留在"放置前"的状态 ✓✓
    --   ★ 机制 ✓：★ 列表项的填充由 `RefreshItems` 回调驱动 ✓
    --     ★ 而它有个**签名门**（`_grid_sig`）✓ ⇒ ★ 签名没变就不再重填 ✓
    --   ⇒ ★ 这里**清掉签名** ✓ ⇒ 下一帧网格同步会重新填一遍 ✓ ⇒ **灰白跟着出来** ✓✓
    -- ★ 2026-10-10 **不再清签名** ✗✓ —— ★ 清签名会重发 RefreshItems
  --   ⇒ ★ 引擎会把**滚动位置重置到顶部** ✓（用户实测："点第五张卡弹回顶部"✗）
  --   ⇒ ★ 改成置"待刷新"标志 ✓ 由 `sync_clue_grid` **就地重填** ✓ ⇒ 滚动一动都不动 ✓
  self._grid_refill_pending = true
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end

-- ★★ 2026-09-28（用户设计）：**双击 = 预放置**。
--
-- 与 `do_place`（正式放置，走 `core:hold_cell`）的区别全在 core 里：
--   预放置 → 只标同行同列 ✗，**不擦笔记、不取消选中、不记 placed**
--   正式放置 → 擦该人物的笔记 + 记 placed（之后不许再给他打笔记）+ 取消选中
-- 反馈动效两者相同（`pop_tile`），因为"有没有真的放上去"要靠盘面看，不靠动效区分。
function Controller:do_pre_place(r, c)
  local core = self.core
  self.last_click = nil
  local who = core.selected
  -- ★ 2026-10-07 分辨日志：★ 双击走的是"预放置"吗 ✓ 选中该保留 ✓
  local _sel_b2 = core.selected
  local ok, why = core:pre_place(r, c)
  if ok then
    print("[murdoku] ★ 放置分辨：走的=【预放置 pre_place】 人=" .. tostring(_sel_b2)
      .. "  放后选中=" .. tostring(core.selected) .. "（★ 应仍是 " .. tostring(_sel_b2) .. " ✓）")
  end
  if ok then
    -- ★★★★★ 2026-10-07 **放置后强制重填线索卡** ✗✓（灰白卡的关键 ✓）
    --   ★ 真机证据 ✓：★ `★ 灰白诊断：pos=3 … ★ id=V`（★ id 已经对了 ✓ 但 `placed=false` ✓）
    --     ⇒ ★ 那几行是**开局填充**跑的 ✓ ⇒ ★ **放置之后卡片没有重新填充** ✗
    --       ⇒ ★ 灰白永远停留在"放置前"的状态 ✓✓
    --   ★ 机制 ✓：★ 列表项的填充由 `RefreshItems` 回调驱动 ✓
    --     ★ 而它有个**签名门**（`_grid_sig`）✓ ⇒ ★ 签名没变就不再重填 ✓
    --   ⇒ ★ 这里**清掉签名** ✓ ⇒ 下一帧网格同步会重新填一遍 ✓ ⇒ **灰白跟着出来** ✓✓
    -- ★ 2026-10-10 **不再清签名** ✗✓ —— ★ 清签名会重发 RefreshItems
  --   ⇒ ★ 引擎会把**滚动位置重置到顶部** ✓（用户实测："点第五张卡弹回顶部"✗）
  --   ⇒ ★ 改成置"待刷新"标志 ✓ 由 `sync_clue_grid` **就地重填** ✓ ⇒ 滚动一动都不动 ✓
  self._grid_refill_pending = true
    self:fx(self:cell_id(r, c), M.EFFECTS.PLACE)
    if self.opts.on_place then self.opts.on_place(who, r, c) end
    self.dirty = true
    return true
  end
  self:_refuse(r, c, why)
  return false
end

-- ── 按下 / 抬起：自己合成"长按" ──────────────────────────────────────────
-- 返回 true = 这次抬起已经被当成"长按"处理掉了（后续那个 CursorClick 要忽略）
function Controller:on_cell_down(r, c, x, y)
  -- ★★ 按下时**同时**记两样 ✓：
  --   ★ `dt = 0` ⇒ ★ 按住期间由 `tick` 一帧一帧加上去 ✓（★ 主判据 ✓ 与真实时间同速 ✓）
  --   ★ `t`      ⇒ ★ 只作兜底 ✓（★ 万一 `tick` 没跑 ✓）
  self._press = { r = r, c = c, dt = 0, t = gesture_now(self), x = x, y = y }
  return false
end

function Controller:on_cell_up(r, c, x, y)
  local p = self._press
  -- ⚠️ ★★★ **先量时长，再清 `_press`** ✗✓（★ 我第一版把两行写反了 ✓）
  --   ★ 症状 ✓：★ 时长恒 nil ⇒ ★ **长按一次都不成立** ✓（★ 实测 7 条红 ✓）
  --   ★★ 机制 ✓：★ `press_seconds` 是**从 `self._press` 里读**的 ✓
  --     ⇒ ★ 先 `self._press = nil` ⇒ ★ 它读到的永远是"没有按下" ✓✓
  local dt = press_seconds(self)
  self._press = nil
  if p == nil then return false end
  if p.r ~= r or p.c ~= c then return false end          -- 按在别处，不算
  if dt == nil then return false end
  if dt < LONG_PRESS_SECONDS then return false end         -- 还不够长
  -- 位移太大 = 划动，不算长按
  if p.x ~= nil and x ~= nil then
    local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
    if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then return false end
  end
  local ok = self:do_place(r, c)
  print("[murdoku] ★ 放置分辨：抬起被判定为【长按】✓ 时长=" .. string.format("%.2f", dt))
  -- ★★★★★★★★ 2026-10-11 **长按时长的一次性统计** ✗✓✓（★ 把"漂移"与"手抖"分开 ✓）
  --
  --   ★★★ 为什么要它 ✗（★ 用户报过两次"越按越久" ✓ 而最新日志是 0.50~1.00 **不再单调** ✓）：
  --     ★ 单看一串数字**分不清**两种情形 ✗：
  --       ★ ① ★ **还在漂移** ⇒ ★ **越往后越大** ✓（★ 真 bug ✓）
  --       ★ ② ★ **真的回归了** ⇒ ★ 数字围着 0.45~0.6 **随机抖** ✓（★ 那是**人的手** ✓）
  --     ★★ 所以打一句**分布** ✓：★ 最小 / 最大 / 平均 ✓ ＋ ★ **前半 vs 后半**
  --       ⇒ ★★ "后半明显大于前半" ⇒ ①（继续查 ✗）
  --         ★ "前后差不多" ⇒ ②（已经好了 ✓ ★ 浮动是人手 ✓）
  --   ★ 只打一次 ✓（★ 攒够 8 次长按才打 ✓）★ 之后**永不再打** ✓ ⇒ ★ 不刷屏 ✓
  do
    local _s = rawget(self, "_lp_stat")
    if _s == nil then _s = { n = 0, sum = 0, min = nil, max = nil, half = {} }; self._lp_stat = _s end
    _s.n = _s.n + 1
    _s.sum = _s.sum + dt
    if _s.min == nil or dt < _s.min then _s.min = dt end
    if _s.max == nil or dt > _s.max then _s.max = dt end
    -- ★ 前一半 / 后一半分开攒 ✓ ⇒ ★ 用"两边均值"看趋势 ✓（★ 比看单个数可靠 ✓）
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
    self._suppress_click = true     -- 紧跟着的那个 CursorClick 不要重复处理
  end
  return ok
end

-- 按住期间移动了（CursorDrag）：超过容差就**当场**放弃这次长按判定。
-- 为什么不等抬起再判：抬起才判的话，玩家按住想微调位置的那 0.5 秒里
-- 松手就会落子，移动端上太容易误触。这里只是提前撤销，不改别的状态。
-- x/y 取不到时**什么都不做**（宁可退回"抬起时判断"，也不要误取消）。
function Controller:on_cell_drag(r, c, x, y)
  local p = self._press
  if p == nil then return false end
  if p.x == nil or x == nil then return false end
  local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
  if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then
    self._press = nil
    return true
  end
  return false
end

-- 棋盘格被单击：单击=笔记 / 双击=放置；已放置格、X 模式、橡皮擦模式、只写笔记模式都立即生效
function Controller:on_cell_click(r, c)
  -- ★ 2026-10-05 **没带坐标的点击：安静地不做任何事**（原来会崩）。
  --
  --   两处独立实测都发现 `on_cell_click(nil, nil)` 会抛异常 ——
  --   就是下面那句 `core.grid[r][c]`（`ui_controller.lua:578` 那一行）直接炸。
  --
  --   什么时候会进来 nil：适配层的 `_fire` 走兜底事件 `{ action = "click" }` 时
  --   （`live_event()` 拿不到节点事件），`r` / `c` 就都是 nil。
  --   ⇒ 这不是"错"，只是**这次点击本来就没落在任何格子上** —— 什么都不做才是对的。
  --   ⚠️ 必须放在**读 `core.grid` 之前**：放在后面就等于没放。
  if r == nil or c == nil then return end
  -- ★★★★★★★★ 2026-10-11 **删掉一段【从来没生效过】的护栏** ✗✓✓
  --
  --   ★★★ 它长这样 ✓：`if self._grid_click_t ~= nil and … <= 0.35 then return end`
  --     ★★ 而 grep 全文件：**`_grid_click_t` 只有【读】没有【写】** ✗✓
  --       ⇒ ★ 它**永远是 nil** ⇒ ★ 这个 `if` **一次都没进去过** ✓✓
  --     ★ 而且它原本有**两份一模一样的**（★ 判据/窗口/注释全同 ✓）⇒ 删一份 ✓
  --   ★ 真在用的那个去重是 `_grid_click_at` ✓（★ 在 `_on_grid_item_click` 里 ✓
  --     ★ 它治的是"**同一次点击串进来一串列表项**" ✓ 完全不同的一件事 ✓）
  --   ⇒ ★ 结论 ✓：★ 这一段是**读起来像有保护、实际没有** ✗ ——
  --     ★★ 留着它比删掉更危险 ✓（★ 下一个人会以为"点卡片后的穿透已经被挡住了" ✓）
  --
  --   ⚠️ ★ 那么"点卡片会顺手点一下格子"这件事现在靠什么 ✗：
  --     ★ 靠 `_on_grid_item_click` 里那一道 ✓（★ 它用的也是手势时钟 ✓）
  --     ★★ 若真机仍观察到穿透 ⇒ ★ 应该去**那边**补 ✓ 而不是复活这段死码 ✓
  local core = self.core
  self.now = self.now or 0
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode

  -- 双击 → **预放置**（★ 2026-09-28 用户设计：双击=预放置，长按=正式放置）
  --
  -- ★★ 2026-09-29 重写（用户报「没选标记按钮、直接单击棋盘做 ✗ 有明显延迟」）：
  --
  --   旧流程：`place` 模式下单击空格会**先挂起 0.35 秒**（`pending_click`），
  --   等过了双击窗口才落成动作 —— 因为要等一下看有没有第二击。
  --   玩家体感就是"点了没反应，过一会儿才出现"。
  --   而**取消工具栏三个按钮之后，单击=切 ✗ 成了最高频的动作**，这 0.35 秒完全不能忍。
  --
  --   新流程：**第一击立即生效**；若真来了第二击，**先把第一击撤销掉**再做预放置。
  --   撤销方式按"第一击到底做了什么"分派（记在 `last_click.did`）：
  --     · `"x"`   → 再切一次 ✗ 就回到原状
  --     · `"pre"` → 撤销那次预放置
  --   于是**单击零延迟，双击行为与原来完全一致**。
  if (not occupied) and mode == "place" then
    local last = self.last_click
    -- ★★ 双击窗口也走**手势时钟** ✓ —— ★ 与 `last.t` 必须同源 ✓（★ 见 `gesture_now` ✓）
    if last and last.r == r and last.c == c and (gesture_now(self) - last.t) <= DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      if last.did == "x" then
        core:toggle_x(r, c)             -- 撤销第一击切出来的 ✗
        self.dirty = true
      elseif last.did == "pre" then
        core:undo()                     -- 撤销第一击的预放置
        self.dirty = true
      end
      self:do_pre_place(r, c)
      return
    end
  end

  -- ★★ 单击**一律立即生效**（不再有任何"挂起等双击窗口"）。
  --   挂起是延迟的唯一来源；现在第一击马上做，双击时再撤销它（见函数开头那段）。
  local had = core.grid[r][c]
  local had_selected = core.selected          -- 要在 tap_cell **之前**取：它会改选中态
  local ok, why = core:tap_cell(r, c)
  -- ★ 2026-10-07 一次性诊断（★ 这次插在赋值【之后】✓ 上一版插在前面，打的是全局 nil ✗）
  --   核心 `tap_cell` 在 **place 模式**就已经是：★ 已有人 ⇒ 拿起 ✓ 没选人 ⇒ 切 ✗ ✓
  --     ★ **选了人 + 空格 ⇒ `toggle_note(selected)` = 铅笔笔记** ✓（`murdoku_core.lua:1910` ✓）
  --   ⇒ **不需要切模式** ✓ 所以这一段只做观测 ✓
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：诊断NOTE2　原 L732..L750
  if ok then
    if had then
      -- ★ 2026-09-27 修（用户报"双击格子有时会导致其消失"）：
      --   原来把 `vanish`（缩放 1.00 → **0.00**）作用在**格子本身**上。
      --   双击放置后若系统多派发一次点击（或玩家连点三下），那一次落在"已占格"上
      --   → 拿起棋子 + **把整个格子缩到 0** → 看上去"格子消失了"。
      --   改成作用在 `face` 子控件上：拿起棋子的反馈照样有，**格子本身不缩**。
      --   （适配器另有"动完还原姿态"的兜底。）
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
      -- ★★★★★★★★ 2026-10-11 **拿起棋子后【必须重填线索卡】** ✗✓✓（★ 用户报的"灰白不恢复" ✓）
      --
      --   ★★★ 用户原话 ✓：「★ **现在取消放置之后 `gray` 不会恢复**」✗✓
      --   ★★ 根因 ✓：★ **"放置"那条路会置 `_grid_refill_pending`** ✗✓
      --     （★ 见 `do_place` 里那段长注释 ✓ —— ★ 当初就是为了让灰白**亮起来** ✓）
      --     ★★★ 而**"拿起"这条路人漏了** ✗ —— ★ 于是：
      --       ★ 灰白**亮得起来** ✓ ★ 却**灭不掉** ✗ ⇒ ★ 那张卡**永远是灰的** ✓✓
      --         （★ 表现：★ 人已经拿下来了，卡还灰着 ✓ ★ 看着像"还放着" ✓）
      --   ★ 为什么以前没暴露 ✗：★★ 上一次修的是"**登记**"那一半 ✓
      --     ★ 而"**注销**"这一半**从来没人管过** ✓ —— ★ 典型的"只补了一半" ✓
      --   ★★ 修法 ✓：★ 与 `do_place` **同一处信号** ✓（★ 就地重填 ⇒ ★ 不重置滚动 ✓）
      --     ★ 不重发 `RefreshItems` ✗ ⇒ ★ 滚动位置一动都不动 ✓（★ 与放人那条路一致 ✓）
      self._grid_refill_pending = true
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    -- 记下这一击做了什么，供"第二击撤销第一击"用
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = gesture_now(self),
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
    -- ★★★★★ 2026-10-07 **失败也要记下这一击** ✗✓（"不能以预放置挪位"的真因 ✓）
    --   ★ 真机证据 ✓：★ 正式放置过 V 之后再双击别的格子 ⇒ 日志里**两次都是单击**（`诊断NOTE2`）✗
    --     ⇒ ★ 说明**双击没被识别** ✓
    --   ★ 原因 ✓：★ 第一击 `ok=false`（★ 笔记被"这个人已正式放置"规则拒 ✓）
    --     ⇒ ★ 而 `last_click` **只在 `ok == true` 时记录** ✗
    --       ⇒ ★ 第二击来的时候 `last = nil` ⇒ ★ **永远判不出双击** ✗✗
    --         ⇒ ★ **`do_pre_place` 永不触发** ⇒ ★ **"选中之后想双击挪位"被拦** ✓✓
    --   ★ 修法 ✓：★ **失败也记** ✓ 且 `did = "none"` ⇒
    --     ★ 第二击**不会去"撤销第一击"**（★ 什么都没做 ✓ 无需撤 ✓）★ 只做预放置 ✓✓
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = gesture_now(self), did = "none" }
    end
    self:_refuse(r, c, why)
  end
end

-- ── 键盘（PC，可选）─────────────────────────────────────────────────────
-- 键盘光标：方向键移动一格，写笔记 / 放置 / 换工具 / 撤销重做提示。
-- `kb_active` 只在真的用过方向键之后才为 true —— 纯鼠标玩家不会看到一个
-- 莫名其妙的选中框。
--
-- ⚠️⚠️ **官方键事件不是物理键码，而是语义事件**（2026-09-26 真机日志查出来的）：
--   注册用的是 `ctrl:AddKeyEventListener(Enum.KeyEventType.<名字>, cb)`，
--   而 `Enum.KeyEventType` 是「设备 + 语义 + 按下/抬起」的组合，共 164 项，例如
--       KeyboardCraftspersonKey1Down  = 键鼠：奇匠按键1（按下），默认物理键 `1`
--       KeyboardCraftspersonKey36Down = 键鼠：奇匠按键36（按下），默认物理键 `↑`
--       KeyboardInteractKeyDown       = 键鼠：拾取/交互（按下），默认物理键 `F`
--       KeyboardJumpKeyDown           = 键鼠：跳跃（按下），默认物理键 `Space`
--   **没有 `Return` / `Enter` / `Escape` 这三种事件**，所以那两个功能换绑到别的键。
--   （`Enum.KeyboardKeyCode` 是**另一个东西** —— 它只给「按键提示控件」显示用。）
--
--   另外「奇匠按键」是**可被玩家重映射的槽位**，上面那些物理键只是**默认值**，
--   所以图例里要写成语义说法，不能假定玩家按的一定是 ↑↓←→。
--
--   本表：`Enum.KeyEventType` 名字 → 本工程的内部动作名。
local KB_ACTIONS = {
  -- 方向（奇匠按键36..39，默认 ↑ ↓ ← →）
  KeyboardCraftspersonKey36Down = "up",
  KeyboardCraftspersonKey37Down = "down",
  KeyboardCraftspersonKey38Down = "left",
  KeyboardCraftspersonKey39Down = "right",

  -- 选角色（奇匠按键1..10，默认 1..9 与 0）
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

  -- 主要动作
  KeyboardInteractKeyDown       = "place",   -- 拾取/交互（默认 F）= 放置
  KeyboardJumpKeyDown           = "note",    -- 跳跃（默认 Space）= 铅笔笔记
  KeyboardDropKeyDown           = "xmark",   -- 落下（默认 X）= 划掉这格
  KeyboardCraftspersonKey42Down = "back",     -- 奇匠按键42（默认 Backspace）= 关弹窗/选关

  -- 工具与命令
  KeyboardOpenShortcutWheelKeyDown = "tool",    -- 呼出快捷轮盘（默认 Tab）= 循环换工具
  KeyboardCharacterSkill1KeyDown   = "eraser",  -- 角色技能1（默认 E）= 橡皮擦
  KeyboardCharacterSkill3KeyDown   = "submit",  -- 角色技能3（默认 R）= 提交
  KeyboardCraftspersonKey12Down    = "undo",    -- 默认 Z
  KeyboardCraftspersonKey13Down    = "redo",    -- 默认 Y
  KeyboardCraftspersonKey15Down    = "hint",    -- 默认 H
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

-- `event.key` 是 `Enum.KeyEventType` 的**名字**（由适配层原样带过来）
local function kb_action_of(event)
  return KB_ACTIONS[tostring(event.key or "")]
end

-- 返回 true = 这个键被消费掉了
function Controller:on_key(event)
  local core = self.core
  local act = kb_action_of(event)
  if act == nil then return false end

  -- 方向：移动键盘光标
  local d = KB_DELTA[act]
  if d ~= nil then
    self:kb_move(d[1], d[2])
    return true
  end

  -- 选第 i 个角色
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
    -- 在光标格写/删笔记
    local kb = self.kb
    if kb ~= nil then
      self.kb_active = true
      -- ★★★★★ 2026-10-20 **修：键盘空格打笔记被自己撤掉了（一次按键 = 两次 tap_cell）** ✗✓
      --
      --   原来这里是**两件事**：
      --     ① `self:on_cell_click(kb.r, kb.c)` —— 它现在**立即**调 `core:tap_cell`
      --        （见 `on_cell_click` 里"单击一律立即生效"那段：挂起模型已撤）
      --     ② 又挂了一次 `self.pending_click` ＋ `self:flush_pending_note()`
      --        —— 而 `flush_pending_note` 里**再调一次** `core:tap_cell`
      --   ⇒ 一次空格 = 笔记加上 ✗ 再立刻撤掉 ✓ ⇒ **净零**（键盘打不了笔记）。
      --
      --   模拟器实测证据（case: tests/cases/v279-rules.json）：
      --     · 按空格之后放置，日志「★ 放置分辨：… 笔记 0 ⇒ 0」（本该是 1 ⇒ 0）
      --     · 障碍格的拒绝串**连打两次** —— 同一键触发两次 `tap_cell` 的直接铁证
      --
      --   ⇒ 只留 ①：与鼠标单击走**同一条路**（`on_cell_click`），不另写一套。
      --   ⚠️ 上面那段"时间戳必须与 flush_pending_note 同一个时钟"的历史注释随之作废；
      --      它不是错在时钟，而是**错在多做了那一步**。
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
    -- 官方**没有** Escape / Return 事件，所以"关弹窗 / 选关"改绑 Backspace
    if self.modal ~= nil then self:on_input({ action = "close_modal" })
    else self:on_input({ action = "level_list" }) end
    return true
  end

  return false
end

function Controller:on_input(event)
  local core = self.core
  local a = event.action

  -- ── 输入阶段（PC 键鼠 / 移动端触碰共用同一套）─────────────────────────
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
      self.modal = { kind = "accuse" }   -- 重画指认面板
    end

  elseif a == "gesture_begin" then
    self:snapshot()

  elseif a == "gesture_rollback" then
    if self._gesture_snapshot then
      core:deserialize(self._gesture_snapshot)
      self.toast = "已回滚本次操作"
      self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
      self:fx("board", M.EFFECTS.UNDO)
    end

  elseif a == "click" then
    -- 刚被"长按"处理过的那一次点击要忽略掉，否则同一格会被放两次
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
    -- ★ 2026-09-28：工具切换必须留下痕迹。
    --   用户报"没有看到任何 X 图标"，而 X 模式在 tap_cell 里是**优先于选中检查**的 ——
    --   所以要么"X 工具按钮没生效"（模式没切），要么"切了但 X 没画出来"。
    --   把每次切换打出来（最多 12 次），这两者就能一眼分开。
    if print then
      self._tool_log = (self._tool_log or 0) + 1
      if self._tool_log <= 12 then
        print("[murdoku] 切换工具 → " .. tostring(event.mode)
          .. "（之前是 " .. tostring(core.mode) .. "）")
      end
    end
    core:set_mode(event.mode)

  -- ★★★★★ 2026-10-02 **✓/✗ 确认状态机**（用户定稿，参考 `参考2-图标与确认键.jpg`）
  --
  --   规则：点「返回菜单 / 提交 / 重置关卡」中**任一个** ⇒ **不立刻执行**，
  --         而是把动作存进 `self.pending` 并显示 ✓/✗；
  --         点 ✓ = 执行，点 ✗ = 取消。
  --         「撤销 / 放大镜」**不需要确认**，直接执行。
  --
  --   为什么这么做：这三个都是**不可逆**的（回菜单、交卷、清空整局），
  --   参考图里也是"点一下先问、再执行"的两段式。
  elseif a == "back_confirm" then
    -- ★ 2026-10-08 **甲案**：★ 用四键弹窗**取代** ✓/✗ 确认卡（★ 262 的原始意图 ✓ 用户拍板 ✓）
    self.modal = { kind = "exit_menu" }   -- ★ 开四键弹窗 ✓（取代 pending 确认卡 ✓）
    self.dirty = true
    self:sync_confirm()
    -- ★ 2026-10-04 **按下就给反馈**（用户反馈"点击动画只有提示有"）：
    --   这三个键原来只设 `pending`、不播动画 ⇒ 点了像没反应，要等 ✓ 才有动静。
    --   真正的执行动画仍在 `confirm_yes` → `do_submit()` 那条路上播。
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
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动

  elseif a == "confirm_yes" then
    local p = self.pending
    self.pending = nil
    self:sync_confirm()
    if p ~= nil then
      -- 二次进分发：这次 `self.pending` 已是 nil，但 `submit`/`restart` 分支会**再**设 pending
      -- ⇒ 所以这里直接走"真正执行"的内部函数，不再绕回分发。
      if p.action == "submit" then
        self:do_submit()
      elseif p.action == "restart" then
        self:do_restart()
      elseif p.action == "back" then
        self:do_back()
      end
    end

  elseif a == "undo" then
    -- ★★★★★ 2026-10-04 **按下先给反馈，再执行**（用户："撤销的点击动画还没建好"）。
    --
    --   原来只有一行 `if core:undo() then fx(...)` ⇒ **没有可撤销的东西时一格动画都不播**
    --   ⇒ 点 ↶ 像没反应（`hint` 有动画是因为它每次都播，这就是两者手感不一样的原因）。
    --   ⇒ 按下时先播 `SELECT`（按下的视觉反馈），**撤销真的发生了**再补一个 `UNDO`（undo_flash）。
    --     同一帧两次 fx 打在同一个控件上时**后写的赢**，所以：
    --       有事可撤 → 看到 undo_flash；没事可撤 → 看到 sel_pop_glow。两种都有反馈 ✅
    self:fx("hex.undo", M.EFFECTS.SELECT)
    if core:undo() then
      self:fx("hex.undo", M.EFFECTS.UNDO)
      -- ★★ 撤销之后**也要重填线索卡** ✗✓（★ 与"拿起"同一条理由 ✓）
      --   ★ 撤销会把棋子拿回去 ✓ ⇒ ★ `core.placed` 少一个 ✓ ⇒ ★ 灰白该灭 ✓
      --   ★★ 不置这个标志 ⇒ ★ 灰白留在"撤销前"的状态 ⇒ ★ **又一张永远灰着的卡** ✓✓
      self._grid_refill_pending = true
      self.dirty = true
    end

  elseif a == "redo" then
    if core:redo() then
      self:fx("hex.redo", M.EFFECTS.UNDO)
      -- ★ 重做同样要重填 ✓（★ 重做会把棋子放回来 ⇒ ★ 灰白该亮 ✓）
      self._grid_refill_pending = true
      self.dirty = true
    end

  elseif a == "hint" then
    local ok, msg = core:hint()
    self.toast = msg
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
    if ok then self:fx("hex.hint", M.EFFECTS.SELECT) end

  elseif a == "reveal" then
    -- 直接揭示答案（照 murdoku 的 Reveal，用于教学/放弃）
    core:reset()
    -- ★ 2026-10-15：`core:reset()` 清了选中 ⇒ 同步记忆也要清（★ 同 `do_restart` 的理由 ✓）
    self._clue_sel_key, self._clue_sel_pos = nil, nil
    self.focused_clue = nil
    for id, p in pairs(core.solution) do
      core:select_suspect(id)
      core:hold_cell(p.r, p.c)
    end
    self.toast = "已揭示答案"
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动

  -- ★ 2026-10-02：提交现在**先要 ✓ 确认**（见上面 confirm_yes 分支）⇒ 这里只留"真正执行"。
  --
  -- ★★★★★ 2026-10-05 **补回 `accuse_thief` 的分发分支**（用户指令：「补 accuse_thief」）。
  --
  --   这里是**第一阶段**的入口：点弹窗「摆位成立。谁是盗窃者？」里的嫌疑人卡，发的就是
  --   `accuse_thief`（见 `build_layout` 里 `modal.suspect.*` 那段 `is_acc and ... or ...`）。
  --   形状**与第二阶段的 `accuse_pick_accomplice` 完全对称**，不多做任何事：
  --     记下 `pending_thief`（第二阶段要用它去结案）+ 把弹窗推进到"问同伙"那一屏
  --     （`kind = "accuse_accomplice"` ⇒ 标题变「那同伙是谁？」、且把这人从名单里排除）。
  --
  --   ⚠️ 原来这两行**光有函数体、没有 `elseif` 头**，于是被并进了上面 `reveal` 分支的函数体。
  --      Lua 语法完全合法 ⇒ `luac -p` 看不出来，但后果有两个：
  --        ① 点嫌疑人**点了没反应** —— `accuse_thief` 没有任何分支接住它，两段式指认断在第一阶段；
  --        ② 「揭示答案」会**顺手弹出"那同伙是谁？"**（reveal 的副作用），而且那次弹窗的
  --           `thief` 是 `event.id = nil` ⇒ 第二阶段一个嫌疑人都排除不掉。
  --      `tools/audit/check_actions.mjs` 正是靠"发了却没有 `a == "..."` 分支"把它抓出来的。
  -- ★★★★★★ 2026-10-12 **指认两步整段删掉**（用户指令 ✓）✗✓✓
  --
  --   ★ 用户原话 ✓：「**确认嫌疑人和同伙那两步我不要，删掉**」✓
  --     ＋ 选项确认：「**提交通过即结算**」✓
  --
  --   ★ 原来这里有三条分支（**已删 ✓ 备查见 git 历史**）：
  --     点嫌疑人 ⇒ 记下 `pending_thief` 并把弹窗推进到"问同伙"那一屏；
  --     另两条 ⇒ 点「同伙是谁」或「他独自作案」时收口到 `finish_accuse` ✓
  --   ⇒ 现在 `do_submit()` 在 `res.ok` 时**直接** `finish_accuse(roles…)` ✓
  --     ⇒ 这三条**再也收不到事件** ⇒ 删干净（用户要求「一行不留」✓）
  --
  --   ⚠️ 这里**故意不写出那三个事件名的字面量** ✗ ——
  --      `tools/audit/check_actions.mjs` 是**逐行正则扫源码、连注释一起扫** ✓
  --      注释里写出旧事件名会被当成"又发了一次" ⇒ 它又会红 ✓（这个坑项目里记过 ✓）
  elseif a == "accuse" then
    -- 兼容入口：只给盗窃者，同伙按关卡声明处理
  -- ★ 2026-10-02：重置关卡也要 ✓ 确认。
    local code = core:encode_state()
    self.share_code = code
    self.modal = { kind = "share", code = code }
    if self.opts.on_share then self.opts.on_share(code) end

  elseif a == "howto" then
    self.modal = { kind = "howto" }

  elseif a == "close_modal" then
    self.modal = nil

  -- ★ 2026-10-08 **「退出菜单」四键的三个动作**（★ 从提交 272 原文照抄恢复 ✓ 那次被 295 整份删掉 ✗）
  --   ★ 回调走 `self.opts.on_save` / `on_settle` ✓ ⇒ ★ 已在 main.lua 补回（提交 398 ✓）⇒ 移植过去即生效 ✓
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
    if self.opts.on_save then self.opts.on_save() end
    if self.opts.on_settle then self.opts.on_settle() end
    self.dirty = true

  elseif a == "level_list" then
    -- 打开选关面板（关卡清单由 main.lua 通过 opts.levels 给进来）
    self.modal = { kind = "levelselect" }

  elseif a == "select_page" then
      -- ★ 选关翻页（夹紧由 build_layout 里的 page 计算负责，这里只管加减）
      self.select_page = (tonumber(self.select_page) or 1) + (tonumber(event.delta) or 0)
      if self.select_page < 1 then self.select_page = 1 end
      self.dirty = true

  -- ★★★★★★★★ 2026-10-15 **主页/选关左下角那颗「结算」** ✗✓✓
  --
  --   ★★ 用户要求 ✓：「**不接存档线，只接结算**」✓
  --   ★ 所以这里**只**调 `on_settle_only` ✓ —— ★ 不碰 `on_save` ✗
  --     ★ 对照 ✓：弹窗里那颗走 `exit_menu_settle` ⇒ **先 `on_save()` 再 `on_settle()`** ✓
  --   ★ 回调缺失时**静默不做事** ✓（★ 与别处一致 ✓ 不留半截副作用 ✓）
  elseif a == "settle_only" then
    if self.opts.on_settle_only then self.opts.on_settle_only() end

    elseif a == "pick_level" then
    if self.opts.on_pick_level then
      self.modal = nil
      -- ★★★★★ 2026-10-05 **顺序修好了** ✗✓ —— 原来 `self.screen = nil` 写在回调**之前** ✗
      --
      --   症状（用户实测 + 两张截图 + 新加的引擎侧体检 ✓）：
      --     · 直接进第一关 ✓ 正常；去过别的关卡再回来 ✗ ★【只剩棋盘，线索区整片没了】✗
      --     · 退出重进第一关没用 ✗；必须去一次别的关卡才行 ✓
      --     · ★ 引擎侧读数：`clues(vis=false)` 而 `clues.bg(vis=true)` `clues.grid(vis=true)` ✗✓
      --       ⇒ ★ 父容器被藏 ⇒ 整片线索区不显示 ✓（这就是那张"只剩棋盘"的图 ✓）
      --
      --   为什么：真机日志里点完卡片后 ★ `controller.screen = **home**` ✗ ——
      --     而这一行**本来置的是 `nil`** ✓ ⇒ ★ 说明是**紧接着的回调**把它改回去的 ✗✓
      --     （`on_pick_level` 在 `main.lua` 那头会走开局/重试那条路 ✓ 中途会重设 screen ✓）
      --   ⇒ ★ 于是 `apply_screen_hide(nodes, "home")` ⇒ HIDE 名单生效 ⇒ `clues` 被藏 ✗
      --     ⇒ 而"进关卡后该显示"的那条路【从来没走到】✗（`self.screen` 一直是 "home" ✓）
      --     ⇒ ★★ 永久丢失 ✓ —— 只有切屏（去别的关卡）才会把它改回 `nil` ✓✓
      --
      --   ★ 修法：**先回调，后置 nil**，并在回调之后再兜一次 ✗
      --     这样无论回调中途把 `screen` 设成什么，回到这里都一定被纠正成"在关卡里" ✓
      self.opts.on_pick_level(event.id)
      self.screen = nil              -- ★ 点卡片 = 离开选关、进入关卡（放在回调【之后】✓）
    end

  -- ★★★ 2026-09-29 新增：主页四键 + 整屏切换（用户要求的布局与流程）
  elseif a == "home" then
    self.screen = "home"; self.modal = nil; self.dirty = true

  elseif a == "levelselect" then
    self.screen = "select"; self.modal = nil; self.dirty = true; self.select_page = 1

  elseif a == "continue" then
    -- 「从存档点开始」= 接续**最近游玩记录**（由 main.lua 提供，取不到就老实说）
    local last = self.opts.last_level and self.opts.last_level() or nil
    if last and self.opts.on_pick_level then
      self.screen = nil
      self.opts.on_pick_level(last)
    else
      self.toast = "还没有游玩记录，先从「选关」开始吧"
      self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
      self.screen = "select"
    end
    self.dirty = true

  elseif a == "shop" or a == "bag" then
    -- 占位：具体内容等美术资源齐全后再设计（用户原话）。
    -- 给一句明确反馈，免得玩家以为按钮坏了。
    self.toast = (a == "shop") and "商城：美术资源就绪后开放" or "背包：美术资源就绪后开放"
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
    self.dirty = true

  elseif a == "clue_up" or a == "clue_down" then
    -- ★★★ 2026-09-30：**线索区滚动**（参考《派蒙的执律庭实习》左侧那个带滚轮的列表）。
    --
    --   引擎**没有滚轮事件**（查过官方 API 缓存），所以做的是"↑/↓ 按钮 + 滚动条"。
    --   滚动的**真正意义**：一屏放不下时，能滚到的那几条必须**真的能被看到** ——
    --   `clue_max_visible` 是硬上限，少建控件就等于线索看不见、关卡不可解。
    --   所以这里只改 `clue_scroll`（窗口起点），**控件一个都不少**。
    --   ⚠️ 这里**不能用 `L`** —— 那是 `build_layout` 里的局部变量，
    --   输入分发这条路上没有（我第一版就写成了 `L.clue_rows`，
    --   运行时报 `attempt to index a nil value (global 'L')`，被探针当场抓住）。
    --   布局常量请走 `M.LAYOUT`。
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
    -- ★ 2026-10-18 通用线索：**只接"提示"这一个选中反馈** ✓
    --   用户原话：「通用线索只接提示这一个选中反馈，note 和放置都不接」
    pcall(function()
      if self.core ~= nil and type(self.core.clue_hint_general) == "function" then
        self.general_focus = true          -- ★ 高亮绘制认这个开关（见 build_layout 那段）
        self.general_hint = self.core:clue_hint_general(1)
      end
    end)
  elseif a == "focus_clue" then
    self.general_focus = nil             -- ★ 点普通卡 ⇒ 通用线索的高亮关掉 ✓
    -- 线索卡：点一下聚焦、再点取消。
    --
    -- 为什么必须有这个分支：线索卡在 push 时就发了 `event = { action = "focus_clue" }`，
    -- 但分发器一直没有对应分支 —— **点了完全没反应**。
    -- （这是 tools/audit/check_actions.mjs 对账抓出来的：发出 26 个 action、只有 25 个分支。）
    --
    -- 可见反馈走**特效**而不是样式：adapter 的 `key == "style"` 分支只对少数已知样式
    -- 做缩放反馈，未知样式是静默忽略的。这里复用已有的 CLUE_IN 特效，不引入新资产。
    local ci = event.index
    if ci ~= nil then
      -- ★★★★★★★★ 2026-10-15 **这里【不再改】`focused_clue`** ✗✓✓
      --
      --   ★ 它原来长这样 ✗：`if self.focused_clue == ci then nil else ci end` ✓
      --     ★ 也就是"点一下聚焦、再点取消" ✓ —— ★ **又一处独立的高亮状态** ✓✓
      --   ★★ 为什么必须拿掉 ✗（★ 与点卡片那条路同一个病 ✓）：
      --     ★ `focused_clue` 现在是**派生值** ✓（= 选中那个人配在第几行 ✓
      --       ★ 见 `_sync_clue_focus` ✓）⇒ ★ 任何**别处**再写它 ⇒ **立刻漂移** ✓✓
      --     ★★ 而且这条 action 是**列表项点击自己在发** ✓
      --       （★ `_on_grid_item_click` 最后那个 `{action="focus_clue"}` ✓）
      --       ⇒ ★ 它原来会把 `_on_grid_item_click` 刚设好的值**再翻一次** ✓✓
      --   ★ 那还需要它吗 ✗：★ 需要 ✓ —— ★ **可点一下要有反馈** ✓ ★ 也要"回到视野"✓
      --     · 反馈 ⇒ ★ 下面那行 `CLUE_IN` 特效**照旧** ✓
      --     · 回视野 ⇒ ★ `sync_clue_grid` 里"焦点变了一次就滚一次"（`_clue_focus_seen` ✓）
      --       ★ 仍然工作 ✓ —— ★ 因为 `focused_clue` 会**跟着选中变** ✓
      --   ★✓ 于是"高亮"这件事全项目**只有一个写点** ✓（`_sync_clue_focus` ✓ P13 ✓）
      self:fx("clue." .. tostring(ci), M.EFFECTS.CLUE_IN)
    end

  elseif a == "back" then
    -- ★★★ 2026-09-29（用户要求，参考 murdoku 原作）：
    --   **退出关卡 → 回到选关界面**（不是回主页）。
    --   原作循环是"选关 → 关卡 → 退出 → 选关"，连玩几关不用每次绕主页。
    self.screen = "select"
    self.modal = nil
    self.dirty = true
    if self.opts.on_back then self.opts.on_back() end

  elseif a == "next_level" and self.opts.on_next_level then
    self.opts.on_next_level()
  end

  -- ★★★★★★★★ 2026-10-15 **每个输入事件的收口：把卡片高亮拉回"选中是谁"** ✗✓✓
  --
  --   ★ 为什么放在**这里** ✗（★ 而不是散在五个改 `core.selected` 的地方 ✓）：
  --     ★ 上面那些分支（`suspect` / `click` / `undo` / `redo` / `submit` …）
  --       以及它们**调进去的** `tap_cell` / `hold_cell` / `select_suspect` /
  --       `set_mode` / `reset` —— ★ **全都会改 `core.selected`** ✓
  --     ★★ 而从外面看，它们**只有这一个共同出口** ✓
  --       ⇒ ★ 在这里同步一次 = **一处负责** ✓（★ 见 `_sync_clue_focus` 那段 ✓ P13 ✓）
  --   ★ 代价 ✓：★ 稳态一次字符串比较 ＋ 一次表查找 ✓（`_sync_clue_focus` 首行就返回 ✓）
  --   ★ 放事件末尾 ✗ **不能放开头**：★ 一进来就同步 ⇒
  --     ★ 这次事件刚改的选中**要等下一个事件才反映** ✓ ⇒ ★ 仍然慢一拍 ✗✓
  self:_sync_clue_focus()

  self.dirty = true
  return self.effects
end

-- ★★★★★ 2026-10-05 **`tick` 不再无条件 `self.dirty = true`**（这一轮最后一条每帧成本）。
--
--   改之前：`tick` 每帧置 dirty ⇒ `Murdoku.on_update`（main.lua L682）见 dirty 就重绘
--     ⇒ 离线实测（`tests/grid_cost.lua` [E]）**300 帧 = 300 次 render**，
--       而每次 render 都要重建 **260 个计划节点**、再走一遍属性账本 —— 用户说的
--       "看着不动也卡"里，这是与"兜底隐藏"并列的第二笔固定开销。
--
--   为什么可以改（先把"它到底在维护什么"数清楚）：`tick` 真正改的只有两件事，
--   而这两件事各自都自带"什么时候才需要重画"的判据 ——
--     · `core:set_elapsed(+dt)`：HUD 计时器显示的是 `Controller:format_time()`，
--       它 `math.floor` 到**秒**（MM:SS）⇒ 只有**整秒变了**才需要重画，不是每帧；
--     · `flush_pending_note()`：真的落成笔记时**它自己**置 dirty（L474），
--       没落成 = 状态没变 = 不需要重画。
--   其余所有会让画面变化的东西，在各自的入口**已经**置了 dirty（本文件 26 处；
--   其中 `on_input` 末尾 L1056 那一处就覆盖了全部光标 / 键盘事件）。
--   ⇒ 唯一"没人管"的就是计时器那一秒，在这里按"整秒变了"补上。
--
--   ⚠️ 这条判据与 `main.lua` 的整秒心跳（`sec ~= current.last_tick`）**相同** ——
--      是有意的双保险：哪天那条被改动，计时器也不会停。
--   ⚠️ `#self.effects > 0` 同理：动效是"排进队列 → 下一次 render 放掉并清空"。
--      正常情况下置 dirty 的是调用方（`fx()` 的 12 个调用点旁边都有 dirty），
--      这一条只是保证"将来有人只调 fx() 忘了置 dirty"时它下一帧仍会被放出去；
--      render 结束会把 `effects` 清空 ⇒ **不会退化成每帧重绘**。
function Controller:tick(dt)
  self.now = (self.now or 0) + (dt or 0)

  -- ★★★★★★★★ 2026-10-11 **按住期间把 `dt` 一帧帧累加** ✗✓✓（★ 长按时长的真来源 ✓）
  --
  --   ★★★ 为什么必须这样 ✗（★ 用户第二次报"越按越久" ✓ 见 `press_seconds` 那段 ✓）：
  --     ★ 任何"取两个时钟读数相减"的做法都要求 ★ **那根时钟与真实时间同速** ✓
  --       ★ `self.now` ⇒ ★ 是**从开局累加的总数** ✗ ⇒ 两边取值时刻不同就被帧数放大 ✓
  --       ★ `os.clock` ⇒ ★ 是 **CPU 时间** ✗ ⇒ 忙的时候快、闲的时候慢 ✓✓
  --     ★★ 而 `dt` **就是引擎说的"这一帧过了多久"** ✓
  --       ⇒ ★ 加起来 = ★ **这段时间真的过了多久** ✓✓
  --   ★ 只在一段手势之内累加 ✓ ⇒ ★ 不会越飘越远 ✓（★ 一段最多一两秒 ✓）
  --   ⚠️ ★ 必须放在 `tick` 的**最前面附近** ✗ —— ★ 别夹在那些 `return` 之间 ✓
  --     （★ 本函数后面有若干提前 `return` ✓ ★ 放后面会漏帧 ✓）
  do
    local p = rawget(self, "_press")
    if p ~= nil then p.dt = (p.dt or 0) + (dt or 0) end
    -- ★★★★★★★★ 2026-10-11 **"按住够长了" ⇒ 当场给一次可见反馈** ✗✓✓
    --
    --   ★★★ 用户原话 ✓：「★ **还是偶尔会有放不上去的情况**」✗✓
    --   ★★ 而真机统计证明**时长已经准了** ✓（★ 前后均值 0.52 / 0.62 ✓ 不漂 ✓）
    --     ⇒ ★★ 那"按丢"就剩一个原因 ✗：★ **玩家不知道什么时候可以松手** ✓✓
    --       ★ 屏幕上在松手前**什么都不显示** ✗ ⇒ ★ 只能**估** ✓
    --         ★ 估短了就按丢 ✓（★ 实测 0.45 / 0.45 / 0.48 / 0.49 那几次 ✓）
    --   ★ 修法 ✓：★ **刚一越过门槛就闪一下那一格** ✓
    --     ⇒ ★ 看到 ⇒ ★ **立刻松手** ✓ ⇒ ★ 按丢会**基本消失** ✓✓
    --   ★★ 只闪一次 ✗（`p.fired` 记住 ✓）—— ★ 否则按住期间每帧闪 ✓
    --   ⚠️ 用**同一次手势**判 ✓ ★ 与"抬起时那个判定"**同一个门槛** ✓
    --     ⇒ ★ 不会出现"闪了却没放上" ✗（★ 两边同源 ✓）
    if p ~= nil and p.fired ~= true and p.dt >= LONG_PRESS_SECONDS then
      p.fired = true
      -- ★ 复用现成的 `SELECT` 动效 ✓（★ 不引新素材 ✓ 与"点中了"同一个视觉语言 ✓）
      pcall(function()
        if p.r ~= nil and p.c ~= nil then
          self:fx(self:cell_id(p.r, p.c) .. ".face", M.EFFECTS.SELECT)
          self.dirty = true
        end
      end)
    end
  end

  -- ★★★★★ 2026-10-05 **A8：提示语到点就撤**（用户批准的方案甲 —— 只补读者/超时，不动写入点）。
  --
  --   为什么放在 `tick`、用 `self.now`：千星**没有客户端定时器 API**（官方客户端脚本
  --   文档里没有 setTimeout 这一类东西），而 `self.now` 是**本来就在每帧累加**的那根时间轴。
  --   ⚠️ `os.time` / `os.clock` 也在白名单里，但它们与"这一帧"不同源；用同一根轴最稳。
  --
  --   ⚠️ 必须置 `dirty`：出口控件的文字是**布局层每帧下发**的（见 `build_layout` 里的
  --      `hud.subtitle` 与 `home.title`），不置 dirty 就得等"整秒心跳"那一帧才变回去
  --      （表现成提示语多赖 0~1 秒）。
  --
  --   ⚠️ 判据是 `self.toast ~= nil` **且**有截止时刻：`toast_until` 是这一轮才有的字段，
  --      万一有人只写了 `self.toast`（没设截止时刻），这里**不该**把它清掉 ——
  --      那是"写入点漏了"的问题，不该由超时逻辑假装解决。
  if self.toast ~= nil and self.toast_until ~= nil and self.now >= self.toast_until then
    self.toast = nil
    self.toast_until = nil
    self.dirty = true
  end
  local elapsed = (self.core.elapsed or 0) + (dt or 0)
  self.core:set_elapsed(elapsed)
  -- ★ 2026-10-20（v282）：原来这里还有一句 `self:flush_pending_note()`（挂起的单击到点落成笔记）。
  --   "挂起"那套机制已随 v279 的键盘笔记修复一起消失 ⇒ 那一句是空跑，已删。
  -- ★★★★★ 2026-10-11 性能优化：**删掉「整秒心跳」那段死条件** ✗✓（零行为影响 ✓）
  --   ★ 原文（改之前）✗：
  --       local sec = math.floor(elapsed)
  --       if sec ~= (self._hud_sec or sec) then
  --         self._hud_sec = sec
  --         self.dirty = true
  --       end
  --   ★★ 它是**恒假**的 ✓ —— 判据自己把自己否掉了：
  --     `self._hud_sec` 的**唯一**赋值点就在这个 `if` 的**体内** ✓
  --     ⇒ 首次进入时 `self._hud_sec == nil` ⇒ 右边 `(nil or sec)` **就是 `sec`** ✓
  --     ⇒ `sec ~= sec` **恒假** ✓ ⇒ 体内永不执行 ✓ ⇒ `_hud_sec` **永远是 nil** ✓
  --   ★ 全仓只剩那两行出现过 `_hud_sec` ✓（`grep -n _hud_sec lua/*.lua` 实证 ✓）
  --   ★ 那"每秒重绘一次"到底靠谁 ✓：**`main.lua` 的 render 门** ✓
  --       `if sec ~= current.last_tick or current.controller.dirty then`
  --     ★ 那一份用 `current.last_tick`（会被真的赋值 ✓）⇒ **节拍由它供给** ✓
  --   ⚠️ 顺带更正一条会误导估算的旧注释 ✓：本文件别处写着
  --     「render 在真机上是**每帧**都跑的（`Controller:tick` 每帧 `self.dirty = true`）」✗
  --     —— 与本文件另一处「tick 不再无条件 `self.dirty = true`」**自相矛盾** ✓
  --     而实测口径（`engine_adapter_qianxing.lua` 里记的）是 **1.10 次/秒** ✓
  --     ⇒ 按"每帧"估 render 成本会**高估约 60 倍** ✗✓
  if #self.effects > 0 then self.dirty = true end
end



----------------------------------------------------------------------------
-- 布局规格
----------------------------------------------------------------------------

local function rect_of(t) return { x = t.x, y = t.y, w = t.w, h = t.h } end

-- ★★★★ 2026-10-01 **`pos_runtime` 沿子树继承**（用户实测定位的"最后一环"）。
--
--   用户实测结论：**运行时新建的控件看得见，编辑器里已有的看不见**。
--   差别就在这一步 —— 适配器 `respect_editor_rect` 会让脚本**完全不去碰**
--   存档里已有控件的位置/尺寸（连锚点都不设）：
--       if respect_editor_rect and not instantiated and not runtime_rect then return end
--   我原来只给 `home` / `select` 两个**容器**打了 `pos_runtime`，容器尺寸是修好了，
--   但**它们的子控件还留着编辑器里的锚点 + 偏移**（诊断读回来 (960,404)）——
--   在 1600×900 的父容器里 ⇒ 实际落到 (1760, 854) ⇒ **x 超出 1600 ⇒ 屏幕外**。
--   （子控件的 rect 从来没被下发过，所以我自己算的"应该在 (800,337)"一直没生效。）
--
--   ⇒ 一处改：父级标了 `pos_runtime`，**整棵子树都算"运行时控件"**。
--     以后再加子控件也不用逐个记得打标记（漏一个是必然会发生的）。
--
--   ⚠️ 必须**两个 `return nodes` 之前都调用**：`build_layout` 在"主页/选关"状态下
--      会**提前 return**（只 push 主页/选关那几棵子树）。我第一版只加在函数末尾，
--      结果主页状态根本跑不到 ⇒ 继承没生效（探针实测 `home.select` 仍是 false）。
-- ★★★★★★★★ 2026-10-16 **`false` 必须能拦住继承** ✗✓✓（一个 Lua 语义错，害了两处功能）
--
--   ★ 下面那句原文一直是 ✗：`if (not n.pos_runtime) and … then n.pos_runtime = true end`
--     ★★ 而 Lua 里 **`not false` 也是 `true`** ✓ ⇒ ★ **显式写 `false` 根本拦不住** ✗
--        （`not nil` 与 `not false` 在这句里**分不开** ✓ —— 这正是它的错处 ✓）
--   ⇒ ★ 后果（本轮在模拟器里量到的两处 ✓ 全是用户点名过的地方）：
--     · ★ `clues` 显式 `pos_runtime = false` ✗ ⇒ 仍从 `root(true)` 继承成 true ✓
--       ⇒ ★ `clues.bg` / `clues.grid` 也跟着被继承 ⇒ **脚本每帧把 400×544 的规划框
--         盖到编辑器那份 360×490 上** ✓ —— ★ 用户原话「网格视窗的大小我已经改了」✗
--         改不动就是这个原因 ✓
--     · ★ `clue.N` / `clue.N.backrop*` 同样 ✗（2026-10-05 就写着「不再给 pos_runtime，
--       位置归编辑器」✓ 而实际上一直被继承接管 ✓）
--   ⇒ ★ 判据改成 **`n.pos_runtime == nil`**（只有"没表态"的才继承 ✓）：
--     ★ `true` = 显式声明"脚本说了算"；★ `false` = 显式声明"编辑器说了算"；
--     ★ `nil` = 没表态 ⇒ 跟父级 ✓（原意 ✓）
--
--   ★ 顺带记下"这是继承来的"（`pos_runtime_inherited`）✗✓ ——
--     `geom_by_editor` 要用它把"继承"与"显式声明"分开（见 `render` 里那段 ✓）。
-- ★★★★★★★★ 2026-10-16 **v253：`inherit_pos_runtime` 整个函数【已删除】** ✗✓✓
--
--   ★ 用户指令 ✓：「★ **把所有失效的几何/文字脚本代码从脚本中删除**」✓
--
--   ★ 它原来干什么 ✗：把 `root`（显式 `pos_runtime = true`）的标记**沿子树继承**给每一个
--     规划内控件 ⇒ ★ 于是**每一个** `.gil` 里的控件都被判成"脚本说了算" ✓
--     ⇒ ★ 脚本每帧把规划里的位置/尺寸**盖回**编辑器那份 ✓ —— ★ 这正是本轮要删的"失效几何代码" ✓
--
--   ★ 为什么它现在是**死代码** ✗（不是"暂时不用"✓）：
--     · v248 起口径定为"几何归编辑器" ✓ ⇒ 继承出来的 `pos_runtime` **一律不再被采纳** ✓
--       （`render` 里那条 `geom_by_editor + pos_runtime_inherited ⇒ script_owns = false` ✓）
--     · v253 把 `render` 简化成**只看两件事** ✓（脚本建的控件 / 显式 `pos_runtime = true` ✓）
--       ⇒ ★ **"继承"这件事彻底不参与判断** ✓ ⇒ 本函数没有任何调用者 ✓
--
--   ⚠️ 删掉它**不会**让界面空白 ✗ —— 当年"界面空白"的**真因**是
--     ★ `.gil` 里的锚点/偏移落到了屏幕外 ✓，而 v248 已经把**几何交回编辑器** ✓
--     ⇒ ★ 现在"控件在哪"由编辑器那份说了算 ✓，不需要再靠继承去接管 ✓
--
--   ★ 现在的几何所有权（全项目就这一条 ✓，详见 `render` 那段头部注释 ✓）：
--     · ★ **脚本实例化的控件**（`adapter.instantiated`，例如 `cell.*`）⇒ 脚本摆 ✓
--     · ★ **显式 `pos_runtime = true` 的那几类**（房间名标签 / 选卡文字与附件 / 缩略图 /
--       确认卡与热区 ✓）⇒ 脚本摆 ✓（★ 它们必须按关卡数据或"卡片运行时矩形"每帧算 ✓）
--     · ★ **其余全部** ⇒ ★ 编辑器摆 ✓（适配层的 `respect_editor_rect` 是第二道闸 ✓）
--
--   ★ 为什么必须有"显式 `pos_runtime = true`"这一档 ✗（别顺手也删了 ✓）：
--     ★ 房间名标签 `room.label.*` **在 `.gil` 里** ✓ 但位置**必须每帧按房间外框算** ✓
--       ⇒ ★ 不做这一档 ⇒ 三个标签会被按在存档那份几何上、**中心完全重叠** ✓（历史上真发生过 ✓）

-- ★★★★★ 2026-10-05 **「老一套线索控件」的 id 判据（全项目唯一一份）**。
--
--   为什么必须收成一处：这份名单要同时被三个地方用 ——
--     · `build_layout`：网格视窗在用时，这一段**整段不发**（见下面那道守卫）；
--     · `build_layout` 收口：发完再扫一遍，规划里**绝不允许**残留老 id；
--     · `render`：切到网格视窗的那一帧，`_shown` / `_created` 里还留着老 id，
--       差集循环**必须跳过**它们（不许再 set_property、不许销毁）。
--   三处各写一份名单 = 必然漂移；漏掉一处就是"又按名字抓到已回收的列表项"。
--
--   ⚠️ 前缀用 **`clue.`（带点）**：`clues` / `clues.bg` / `clues.grid` 是"线索区"自己的
--      东西，不能被误伤（`clues` ≠ `clue.`）。
local function is_legacy_clue_id(id)
  if type(id) ~= "string" then return false end
  if id:sub(1, 5) == "clue." then return true end
  return id == "clues.up" or id == "clues.down" or id == "clues.track"
      or id == "clues.knob" or id == "clues.count" or id == "clues.more"
      or id == "clues.bar"
end

-- ★★★★ 2026-10-01 **屏幕隔离**（子控件不再靠父容器开关之后的必需品）。
--
--   背景：为了修"全屏容器把游戏自己的 UI 挡住、点不动"（用户报"卡死"），
--   我把 `home.*` / `select.*` 的**父级从 home/select 容器改挂到了 root** ——
--   因为证据表明 root 的子控件不会被裁（诊断三的探针挂在 root 下、用户确认看得见）。
--   容器随之缩成 1x1，不再覆盖屏幕。
--
--   ⇒ 副作用：**父容器的 `visible` 不再能开关子树**了。所以这里显式按屏幕藏：
--      · 关卡内（screen == nil）：藏 `home.` / `select.` 两棵子树
--      · 主页 / 选关：藏**关卡内控件**（下面 HIDE / PREFIX 那两组）+ **另一个屏幕的子树**
--
--   ⚠️ `HIDE` 那一组**只在"主页/选关"时生效** —— 里面的 `intro` / `modal` / `toast`
--      在关卡里是要显示的。我第一版没分组、无条件藏，会把教程和弹窗一起藏掉。
local function apply_screen_hide(nodes, screen)
  if nodes == nil then return end
  local HIDE, PREFIX = {}, {}
  if screen == nil then
    -- ★★★★★ 2026-10-03 **真机 bug 的真正根因就在这一行**（原来是 `{ "home.", "select." }`）。
    --
    --   日志（22:40，关卡内 `controller.screen = nil`）：
    --       home             visible=**true**     ← ★ home 容器在关卡里还亮着
    --       home.select      visible=**true**     ← ★ "选关"按钮跟着露出来
    --   ⇒ 玩家看到的"第二行几个格子上面压着返回菜单按钮、点了回选关"就是它。
    --
    --   为什么漏：前缀判断是 `id:sub(1, #PREFIX[k]) == PREFIX[k]`，
    --   原来那条 **带点**（`"home."`）⇒ 能匹配 `home.select`，
    --   **但匹配不到 `home` 自己**（不带点）⇒ `hide = false`
    --   ⇒ 走 `else` 被 `SetVisible(true)` ⇒ **父容器可见 ⇒ 四个子按钮全露**。
    --
    --   ⇒ 去掉那个点：`"home"` 同时匹配 `home` 自己和它全部子控件；`select` 同理。
    PREFIX = { "home", "select" }
  else
    HIDE = {
      topbar = true, toolbar = true, left = true, board = true, right = true,
      toast = true, modal = true, intro = true, clues = true,
      -- ★ 2026-10-11 `["action.back"] = true` 已去掉 ✓（★ 控件整颗删除 ⇒ 藏它没有意义 ✓）
      ["action.redo"] = true, ["action.hint"] = true,
      ["action.undo"] = true, ["action.submit"] = true, ["action.reveal"] = true,
    }
    -- ★ 2026-10-03 **图标（hex.*）只在关卡内显示**：
    --   主页/选关时把它们一起藏掉。关卡内不加进任何 HIDE/PREFIX ——
    --   那 5 个按键图标初始就是 visible=true，直接显示；
    --   确认卡的 hex.ok/hex.no 初始 visible=false，由 `sync_confirm()` 单独控制。
    -- ★★★★★ 2026-10-03 **修了一个真机 bug**：关卡界面里 `selbar`（选关按钮条，
    --   1500×700，覆盖整个棋盘区域）**没被藏掉** ⇒ 它的 4 个 `selbtn.*` 压在棋盘第二行上，
    --   而 `selbtn` 绑的是 `pick_level` ⇒ 玩家点到它们就"返回选关"。
    --   真机日志证据（22:00）：
    --      16. selbtn.2   160x160  可见=true     ← 关卡里还亮着
    --      17. selbtn.3 …  18. selbtn.1 …  19. selbtn.4 …
    --      20. tpl-container 150x150 可见=true  ← 模板引用控件也没藏
    --   ⇒ 三样都补进隐藏名单：`selbar`（容器本身）、`selbtn.`（它的子按钮）、`tpl-`（模板引用控件）。
    HIDE["selbar"] = true
    HIDE["tpl-container"] = true
    -- ★★★★★★★★ 2026-10-15 **关卡内那七颗命中层：改成【列具体 id】✗✓✓**（真机截图那件事的正解 ✓）
    --
    --   ★★★ 真机现象 ✓（用户 2026-10-15 截图 + 原话）：
    --     ★「**左右箭头没加上去，功能也没换绑到新的方块上**」✗
    --     ★ 截图里 4 张卡**在正确的位置**（几何已经修好了 ✓）★ 但**点了没反应** ✓
    --
    --   ★★ 根因 ✓（`tests/select_hit_visible.lua` 把它钉死了 ✓）：
    --     ★ 这一支的 `PREFIX` 名单里有 **`"hit."`** ✗ ——
    --       它本来是给**关卡内**那七颗 `hit.*`（光标检测区域）用的 ✓
    --     ★★ 而它**同时命中选关屏自己的 `hit.select.*`** ✗✗
    --       ⇒ ★ 选关屏**每帧**把这 7 个命中层 `visible = false` ✓
    --       ⇒ ★★★ **可视层（白卡）在、命中层被藏 ⇒ 点哪儿都没反应** ✓✓
    --     ★ 为什么一直没被发现 ✗：命中层**本来就是隐形的** ✓
    --       ⇒ ★ "被藏了"与"正常隐藏"在屏幕上**长得一模一样** ✓
    --       ⇒ ★ 只有"点击没反应"这一个可观察差异 ✓（用户正是这么报的 ✓）
    --
    --   ★★ 判据 ✓（可复跑 ✓）：
    --     `lua tests/select_hit_visible.lua`
    --       ★ 修前：7 条红 ✓（`hit.select.*` 实测 visible=false ✓ 而 `select.card.*` 是 true ✓）
    --       ★ 修后：0 条红 ✓
    --
    --   ★ 规矩 ✓（与 `KNOWN_ABSENT` 那条**同一类病** ✓）：
    --     ★★ **前缀只许给"整族都该藏"的族用** ✗ ——
    --       一旦族里出现**合法的例外**（这里是选关屏自己的命中层 ✓），
    --       就必须**列具体 id** ✓，否则那个例外会被静默吃掉 ✓✓
    for _, id in ipairs({ "hit.back", "hit.submit", "hit.redo", "hit.undo",
                          "hit.hint", "hit.ok", "hit.no" }) do
      HIDE[id] = true
    end
    -- ★★★★★ 2026-10-05 **`"cell."` 从这里删掉** ✗✓ —— 它就是「第一次进关墙/门不画」的根因 ✓
    --
    --   机制（本函数是**单向**的 ✗：只会 `visible = false` ✓ 从不写回 true ✓）：
    --     · 开局 `screen = "home"` ✓ 于是 `PREFIX` 命中 `"cell."` ✗
    --       ⇒ ★ 25 个 `cell.*` 全部 `visible = false` ✗✓
    --     · 而 `cell.*` 是格子的**根控件** ✗ ⇒ 它的 false 会**连坐全部子控件** ✓
    --       ⇒ ★★ `wall.*` / `door.*` / `face` **一律看不见** ✓✓
    --     · 之后进关卡 `screen = nil` ✓ ⇒ 本函数**不再藏** ✓
    --       但**已经设成 false 的 `cell.*` 它【不会写回 true】** ✗（单向的代价 ✓）
    --       ⇒ ★ 父级一直是 false ⇒ ★★ **墙/门永远不出现** ✓✓
    --
    --   ★★★ 用户的三条实测现象**全部对上** ✓✓：
    --     · 「破坏开局流程（`screen` 全程 `nil`）⇒ 直接正常」✓
    --       ⇒ 那时 PREFIX 只有 `{"home","select"}` ✓ **从不碰 `cell.*`** ✓
    --     · 「正常走流程 ⇒ 不画」✗
    --       ⇒ 开局必经 `home` → `select` ✓ 两趟都把 `cell.*` 设 false ✓
    --     · 「进别的关再回来就正常」✓
    --       ⇒ 那一趟 `screen` 是 `nil` ✓ 不再藏 ✓ 而规划把 `cell.*` 重发 true ✓
    --
    --   ★ 为什么删它是**安全**的：★ `cell.*` 的可见性**规划里已经按屏幕算好了** ✓
    --     · 主页/选关：规划给 `false` ✓（真机开局日志：`cell.1.1 visible=false` ✓）
    --     · 关卡内：规划给 `true` ✓（真机进关日志：`cell.1.1 visible=true` ✓）
    --     ⇒ ★★ 这一条**本来就是重复的** ✗ —— 重复的那份还会用"单向藏"覆盖规划 ✗✓
    --   ⚠️ 教训：★ 可见性【只能有一个权威】✗ —— 规划给了，屏幕层就不该再管 ✓
    -- ★ 2026-10-12 `"ruler"` 已从名单里删掉 ✓（行标/列标那套控件已废弃 ✓ 见文件内说明 ✓）
    -- ★★★★★★★★ 2026-10-15 **`"hit."` 从这里【删掉】** ✗✓✓（它吃掉了选关屏的命中层 ✓ 见上面那段 ✓）
    --   ★ 关卡内那七颗改为**列具体 id** ✓（上面刚加的那一圈 ✓）
    PREFIX = { "clue.", "hud.", "room.label.", "tray.", "action.", "hex.",
               "selbtn.", "tpl.",
               (screen == "home") and "select." or "home." }
    -- ⚠️ 这里**不需要**再补 `hit.select.` ✗ —— ★ 我第一版补了，随即核实是**多余的** ✓：
    --   ★ 本函数只遍历**本帧规划里的节点** ✓，而选关屏那整套（含 `hit.select.*`）
    --     **只在 `screen == "select"` 时才进规划** ✓（`build_layout` 的选关支路 ✓）
    --   ⇒ ★ 主页/关卡这两帧，它们**压根不在 `nodes` 里** ⇒ 本函数碰不到它们 ✓
    --   ★★ 那"切屏后它们怎么被藏" ✓：★ 由 `render` 的**差集**收口 ✓ ——
    --     「上一帧显示过、这一帧不在布局里」⇒ 一律 `visible = false` ✓
    --     （就在 `render` 里那两段 `if self._shown == nil then … else for pairs(self._shown)` ✓）
    --     ⇒ ★ 所以**不要**在这里叠一层死代码 ✓（本项目专门清过这种"两处负责一件事"✓）
  end
  for i = 1, #nodes do
    local id = nodes[i].id
    local hide = HIDE[id] == true
    if not hide then
      for k = 1, #PREFIX do
        if id:sub(1, #PREFIX[k]) == PREFIX[k] then hide = true break end
      end
    end
    -- ★ 容器自己也要收口：前缀 `home.` 匹配不到 `home` 本身。
    -- ★★★★ 2026-10-02 **容器不再跟着切屏显隐**（真机"选关点不动"的下一个假设）。
    --
    --   用户确认 `home`/`select` **是容器节点**（不是按钮）⇒ "全屏按钮吃点击"不成立，已撤回。
    --   回到日志里唯一还没解释的不对称：
    --     主页：点击有效  —— `home` 的 visible **从第一帧就是 true**
    --     选关：点击全废  —— `select` 是**运行中由 false 变 true**
    --   而两者的 bind / 坐标 / 尺寸都对，子控件也都在屏内。
    --   ⇒ 假设：引擎在 `SetVisible(false)` 时把容器标成"不可交互"，
    --     之后 `SetVisible(true)` **射线没有恢复** ⇒ 它的子控件收不到点击。
    --   ⇒ 让两个容器**恒为可见**，屏幕隔离完全交给"按前缀藏子控件"那套
    --     （`home.` / `select.` 前缀本来就覆盖了它们的全部子控件）。
    --
    --   ⚠️ 这会**故意**让 play_test 那三条断言（"主页/选关都藏了"）继续红 ——
    --      它们测的是"容器 visible=false"，而这一版**刻意不那样做**。
    --      真正要验的是"子控件有没有串屏"，那三条的附加信息里已经写了
    --      "关卡内的还可见 0 个" ⇒ 子控件层面是干净的。
    if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    -- ★★★★★ 2026-10-05 **改回【单向】：只藏，不负责显示** ✗✓ —— 双向那版【闯了祸】✓
    --
    --   我先前把它改成 `nodes[i].visible = not hide`（双向 ✗），以为"这一帧该显示"
    --   这个事实必须进 `nodes` ✓ —— ★ 结果真机上出现了**一排白方块** ✗✓
    --   （用户截图：顶部两处 + 右上两处 + 右侧一处 ✓ 位置正好是 `topbar` / `right`
    --     的图标位 ✓ 日志里 `图标设图 hex.*` 七条【全部成功】✓ ⇒ 图是设上了的 ✓
    --     ⇒ 白方块是它配对的 `hit.*`（透明点击区 ✓ 本身是白图块 ✓）✗）
    --
    --   为什么双向会闯祸：
    --     · `hit.*` / `hex.*` 的可见性有【两套来源】✗ ——
    --         ① 屏幕层（本函数 ✓：主页/选关藏 ✗ 关卡内不藏 ✓）
    --         ② **状态层**（例如"提交键只在能提交时亮"✗ 由别处按状态开关 ✓）
    --     · `hide == false` 时【什么都不做】⇒ 控件保持**状态层刚写过的值** ✓
    --     · 我改成【写 true】⇒ ★ **每帧把状态层覆盖成"可见"** ✗ ⇒ 白方块 ✓✓
    --
    --   ⇒ ★ 正确的分工：★ 本函数【只负责"藏"】✓；"该显示"由**节点的初值**
    --     （`build_layout` push 时给的 ✓）和**状态层**决定 ✓ —— 谁的状态谁负责 ✓
    --   ★ 而"藏过的东西永远回不来"那个真问题 ✗ ⇒ **已经由另外两处修好了** ✓：
    --     · `forget_visible`（差集藏完清账本 ✓ ⇒ 下次该显示时会【重发 true】✓）
    --     · `screen` 判对（构造时 `nil` ✓ + `start_other` 后置 `nil` ✓）
    --     ⇒ ★ 三处里这两处才是根治 ✓，本函数【不需要】也【不应该】双向 ✓✓
    if hide then nodes[i].visible = false end
  end
end
-- ★★★★★ 2026-10-05 **`split_by_name` 从 `build_layout` 里提出来，升成模块级函数**。
--
--   原来它是 `build_layout` 内部的局部函数，闭包里攥着那一帧的 `vm` ——
--   于是**只有那条路**能用它。而本轮新增的"网格视窗列表项填充"在 `render` 那条路上
--   （见 `Controller:_fill_grid_item`），同样需要"从线索文案里切出人名"。
--   ⇒ 一提就够：`vm` 由调用方传进来，两条路共用**同一份**切分逻辑。
--     （"同一件事两处实现必然漂移"是本项目反复踩到的病，能共用就绝不复制。）
--
--   返回：名字 / 前缀 / 后缀 / 该角色的 id / 头像名
local function split_by_name(vm, txt)
  if type(vm) ~= "table" or type(vm.tray) ~= "table" then return nil, txt, nil, nil, nil end
  local best, bestIt = nil, nil
  for _, it in ipairs(vm.tray) do
    local nm = tostring(it.name or it.short or it.id or "")
    if nm ~= "" and txt:find(nm, 1, true) then
      -- 取**最长匹配**，避免"保"抢先于"保安"
      if best == nil or #nm > #best then best, bestIt = nm, it end
    end
  end
  if best == nil then return nil, txt, nil, nil, nil end
  local at = txt:find(best, 1, true)
  local pre, post = txt:sub(1, at - 1), txt:sub(at + #best)
  return best, pre, post, bestIt and tostring(bestIt.id) or nil, bestIt and bestIt.portrait or nil
end

-- ★★★★★ 2026-10-05 **A8：提示语（`self.toast`）的出口文案** —— 全项目**唯一**读它的地方。
--
--   ★ 2026-10-18 更新（用户指令）：**关卡内那条出口已随 `hud.subtitle` 一起删掉**
--     （原话：「美术布局上目前没有副标题的位置了，把它当死代码处理吧」）⇒
--     **现在只剩一个出口**：`home.title`（主页的「商城 / 背包」之类的提示）。
--     ⇒ **关卡内的 toast 目前无处显示**（撤销 / 取消 / 回滚 / 揭示 / 提交与结案结果）。
--     这是已知的产品缺口，不是 bug；要补请**新开一个控件位**，别再往 `hud.subtitle` 接。
--
--   原始设计留档：2026-10-05 的"方案甲"要求**接一个已存在的控件当出口**，一个控件都不加
--   （`hud.toast` 已按参考图删掉，`layout-plan.json` 与存档里都没有它的记录 ⇒
--     写不存在的控件 = `set_property` 静默 no-op = 白做）。
--
--   ⚠️ 空串按"没有提示语"处理：出口控件的 `text` 不允许被清成空串之后还赖在计划里
--      （`nil` 时回落到控件本来的文案，见 `home.title` 那处 push）。
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

  -- ★★★★★★★★ 2026-10-22（v300）**家具美术：先把"分组 + 六层元素"算出来** ✗✓
  --
  --   为什么要在这里算（而不是在适配层逐格算）：
  --     · 跨格家具（第一关的桌子 (1,1)+(2,1)、第二关的 (1,2)+(1,3)）必须**整件只画一次**，
  --       而"哪几格是一件"是**棋盘层面**的信息（相邻同种 + 包围盒 + 锚点格），
  --       只有界面层手里有完整 `vm.cells`；适配层是按格收属性的，看不到全局；
  --     · 房间名标签要按"房间外框"摆位，同样是棋盘层面的事。
  --   ⇒ `lua/furn_art.lua` 只做数据和几何，这里把结果按格下发（`furn` / `furn_anchor`），
  --     并把标签节点一起 push 出去。绘图仍然只有适配层那一处实现（`_paint_obj`）。
  local furn_art = nil
  -- ★★★★★★★★ 2026-10-22（v302，第四轮）**家具改成"工具算出的图元拼法"** ✗✓
  --
  --   用户原话：「桌子椅子植物依然没有达到参考效果，仓库里有一个能兼容千星的外部图片网站，
  --     **你先用他把参考拼出来，再按结果文件拆解出正确拼法导入存档**」
  --   ⇒ 用 `qx-img.070077.xyz` 的本地引擎（1475505/Miliastra-toolbox-primitive-shape）把原作图标
  --      拟合成图元（每件 148~200 条，含旋转与逐图元 RGBA），结果文件由
  --      `_work/art-tools/gen_art_records.py` 拆成 `lua/furn_art_records.lua`。
  --   ⇒ 每件家具 = N 个图片控件，**格子模板的 12 层装不下** ⇒ 走"运行时实例化"（适配层 `_paint_furn_art`）。
  --   ⇒ 这里只负责把"哪一格放哪件、整件中心相对锚点格偏移多少"算出来；坐标换算在适配层做。
  --   ⚠️ 地毯例外：它是一块可站人的平面图形，仍走原来的 12 层矩形（`furn`），不生成几百个图元。
  local furn_recs = nil
  local level_id = nil        -- 当前关卡 id（静态烘焙按关卡切容器用）
  do
    local keys = {}
    for r = 1, vm.rows do
      keys[r] = {}
      for c = 1, vm.cols do
        keys[r][c] = Controller.object_key_of(vm, vm.cells[r][c]) or false
      end
    end
    -- 当前关卡对象（为了拿 `room_names`：关卡数据里可选填，没填就显示"区域N"）
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
    -- ★ v307：把"每格是什么件"一起带出来（烘焙模式要按件决定关不关旧图层）
    furn_art.kind_of = {}
    for r = 1, vm.rows do
      furn_art.kind_of[r] = {}
      for c = 1, vm.cols do
        local k = keys[r] and keys[r][c]
        furn_art.kind_of[r][c] = k and (k:match("^obj%.(.+)$") or k) or nil
      end
    end
    level_id = cur_lv and cur_lv.id or nil

    -- ── ★ v310：模板化家具 —— "锚点格 → 模板键 / 跨格数" ──────────────────────────
    --   模板里层数不受 12 层限制（一个模板引用控件只算一层，用户要求）。
    local TPL_KEY = {
      chair = "furn.chair", plant = "furn.plant", statue = "furn.statue",
      shelf = "furn.shelf",
      table = { ["1"] = "furn.table", h2 = "furn.table.h2", v2 = "furn.table.v2" },
    }
    local furn_tpl, furn_span, furn_offset = {}, {}, {}
    for r = 1, vm.rows do
      furn_tpl[r], furn_span[r], furn_offset[r] = {}, {}, {}
      for c = 1, vm.cols do furn_tpl[r][c], furn_span[r][c], furn_offset[r][c] = false, false, false end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if kind ~= "carpet" and p.anchor ~= nil then
        local variant = "1"
        if (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end
        local tk = TPL_KEY[kind]
        if type(tk) == "table" then tk = tk[variant] end
        if tk ~= nil then
          local b = p.box or { r1 = p.anchor.r, r2 = p.anchor.r, c1 = p.anchor.c, c2 = p.anchor.c }
          furn_tpl[p.anchor.r][p.anchor.c] = tk
          furn_span[p.anchor.r][p.anchor.c] = { r = p.span_r or 1, c = p.span_c or 1 }
          -- 整件中心相对锚点格中心（格）：实例就放在这个偏移上
          furn_offset[p.anchor.r][p.anchor.c] = {
            dx = (b.c1 + b.c2) * 0.5 - p.anchor.c,
            dy = (b.r1 + b.r2) * 0.5 - p.anchor.r,
          }
        end
      end
    end

    -- ── 图元拼法：把每件家具的"工具结果记录"按锚点格摆好 ────────────────────
    --   记录里的 dx/dy 是**相对整件包围盒中心**（格）；锚点格中心与整件中心差 (bcx-c, bcy-r) 格，
    --   所以逐条加上这个偏移，适配层就能"以格子中心为原点"直接画。
    furn_recs = {}
    for r = 1, vm.rows do
      furn_recs[r] = {}
      for c = 1, vm.cols do furn_recs[r][c] = nil end
    end
    for _, p in ipairs(furn_art.pieces or {}) do
      local kind = p.kind
      if M.FURN_BAKED then break end   -- 静态烘焙模式：不生成图元记录（由存档里的静态控件画）
      -- ★ 2026-10-22 第五轮（v303）**按件决定画法** ✗✓
      --   走工具图元（椭圆拟合）的：**椅子 / 植物 / 雕像** —— 形体圆润，用户已确认"椅子和植物对了"。
      --   走手搭层的：**桌子**（直角/直线，椭圆拟合会糊 ⇒ 本轮照原作再加工：圆角外形+桌沿+带黑边的腿）、
      --               **书架**（用户："书架现条扭曲…处理不了就退回上一版"——工具把层板/书脊拟合成旋转细椭圆，
      --                 在线宽只有 1~2px 的层板上必然扭 ⇒ 退回 v301 手搭 12 层）、
      --               **地毯**（可站人的平面图形，3 层矩形）。
      -- ★ v309：一律不生成图元记录（全部改手搭层）
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
            local ox = (b.c1 + b.c2) * 0.5 - anchor.c   -- 整件中心相对锚点格中心（格）
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

  -- ★★★★ 2026-10-01 **真机"界面空白"的最后一环：`root` 的尺寸是 0x0。**
  --
  --   真机诊断读回来：
  --     root       visible=true  位置=(0,10)  尺寸=**0x0**      <-- 所有东西都装在它里面
  --     home       visible=true  位置=(0,0)   尺寸=1600x900   （这一环上一版刚修好）
  --     home.title visible=true  位置=(960,195) 尺寸=1000x110
  --   ⇒ 子控件的尺寸和坐标都对，但父级 `root` 是 0×0 ⇒ **全被裁掉** ⇒ 屏幕上什么都没有。
  --
  --   `root` 是游戏自己的根节点，脚本原来**从来没给它设过尺寸**（布局里根本没 push 它），
  --   它在 .gil 里就是 0×0 —— 而 `respect_editor_rect` 又让脚本不去碰它。
  --   ⇒ 显式补一条：把 root 撑成整屏（`pos_runtime = true` 让它真的生效）。
  --     画布本身就是 1600×900，所以这是"恢复默认"而不是"改设计"。
  --
  --   ⚠️ 这条必须放在 `local nodes = {}` **之后** —— 我第一版插在它前面，
  --      dump_layout 当场报 `attempt to get length of a nil value (global 'nodes')`。
  nodes[#nodes + 1] = {
    id = "root", kind = "container", parent = nil, visible = true,
    rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height },
    -- ★ v306：静态烘焙的关卡名（适配层据此只显示 `fart.<关卡>` 一个容器）
    -- ★★★★★★★★ 2026-10-22（v309）**只有"关卡内"才显示烘焙图元** ✗✓（问题 1 的真因）
    --   旧写法只看 `level_id` ⇒ 主页/选关/结算时**关卡 id 还在** ⇒ 容器一直显示 ✗
    --   （用户：「主页/选关/结算能看到家具图元」）⇒ 非关卡内一律下发 `false` = 两个容器都藏 ✓
    -- ★★★★★★★★ 2026-10-22（v310）**模板化家具：当前关卡** ✗✓
    --   适配层据此：打开 `fart.furn` 容器（关卡内）/ 关掉（关卡外），并在切关时销毁上一关的模板实例。
    furn_level = (level_id and self.screen == nil) or false,
    -- ★ v306–v308 的静态烘焙（`fart.case_*`）保留回退开关，默认关
    baked_level = (M.FURN_BAKED and level_id and self.screen == nil) or false,
    pos_runtime = true,
  }
  
    -- ★★★ 2026-10-01：**家具图标的调色板条目**（⑤ 的阻碍在这里清掉）。
    --
    --   用途：格子模板里的 `obj` 子控件按 `cd.object` 换图。适配器的 `object` 分支
    --   走 `SetImage(obj.imageSource, 调色板[id])` —— 和头像卡 `portrait.*` 完全同一条路
    --   （那条路真机上已经工作：日志 `SetImage 后 tray.A imageType = Stretch`）。
    --
    --   素材**不用自己画**：直接用**游戏自带的 1543 个图片素材**的 id
    --   （目录 https://qx.070077.xyz/api/library/catalog 14 类，见 docs/美术素材从哪来-实地调查.md）。
    --   看过接触表后挑的：
    --     111051 = 一叠书页（书架）  111064 = 金色宝箱（展示柜）
    --     111050 = 包裹木箱（书桌）  106053 = 白底板（地毯 —— 本来就该是色块，靠染色上色）
    --
    --   ⚠️ 关卡里物件是**中文名做键**（`["书架"]`），界面层用 `object_key_of` 翻成
    --     `obj.<kind>`（写了 kind）或 `obj.<中文名>`（没写）—— 所以条目名必须是 obj.shelf 这种。
    --
    -- ★★★★★★★★ 2026-10-18 **删掉"运行时创建 obj.*"这一段** ✗✓✓
    --   用户定位（原话）：「你的脚本是实时创建 things，不要这样，在存档里创建好就行，
    --   **脚本里不要有创建控件这种操作，不然多次运行就必撞 id**」✓
    --   ★ 机制：这里往规划里塞 4 个 `obj.*` 节点 ⇒ 运行时 `create_control` 真的去建它们 ⇒
    --     建出来的控件 GUID 由引擎分配，**每跑一次就多一批** ⇒ 编辑器里"GUID 重复" ✓
    --   ★ 现在素材从哪来：★ **存档里的 `things` 素材区**（在编辑器里换图）✓
    --     兜底 = 脚本配置 `cfg.obj_art`（见 `Adapter:read_palette`，**控件优先**）✓
    --   ⇒ 规划里**一个 `obj.*` 都不再出现**（日志里那条"已知不需要：…/obj.*"也就干净了）✓
    local OBJECT_PALETTE_DISABLED = nil   -- 保留名字，避免别处 `local` 重名冲突（值为 nil = 不建）

    -- ★★★★★ 2026-10-03 **六个图标改走「官方素材 + 脚本创建」**（用户定稿的路线）
    --
    --   为什么换路线：外部资产（.gia 转存的）**只能挂服务器控件**、**尺寸生成时定死**、
    --   脚本还不能创建它 —— 前几轮就卡在这三条上。
    --   而**官方素材**（游戏自带 sprite）没有这些限制：脚本 `SetImage(src, imageId)` 设图、
    --   `imageColor` 乘算调色、`SetSizeDelta` 改尺寸、`SetAnchoredPosition` 摆位置，一条龙。
    --   （现成佐证：`cell.x` 一直用 `100101` 画叉，跑得好好的。）
    --
    --   ⇒ **编辑器里不用摆任何图标** —— 这里 push 出来，适配器建控件 + 设图。
    --
    --   素材 ID 全部来自官方「功能图标-单色」类（100101–100213，接触表 tools/qx/out/cat-3.png）：
    --     100109 弯钩返回箭头 ↰     100126 循环箭头 ↻       100120 放大镜
    --     100127 逆时针箭头 ↶       100110 向上箭头 ↑       100102 勾 ✓   100101 叉 ✗
    --
    --   ⚠️ `rect` 用的是**规划那套坐标（y 从**上**边算、与 LAYOUT 一致）**，
    --      与你在编辑器里看到的（左下角原点）是同一位置的两种显示，不要混。
    --      换算：编辑器 y = 900 − rect.y − rect.h
    --
    --   图标位置直接取自布局图（docs/布局图-关卡内-v3.png 的画法）：
    --     返回菜单 (60,48,62×62) · 确认卡两枚 (438/500,52,54×54)
    --     右上三键 (1448, 48/144/240, 70×70) · 右下放大镜 (1448, 694, 70×70)
    --   ⚠️⚠️ `rect` 用的是**设计空间 1920×1080**（规划会 ×5/6 缩放到画布 1600×900），
    --       而布局图量出来的是**画布空间**的值 ⇒ **这里要 ×6/5 换回设计空间**。
    --       （我第一次直接填了画布值，dump 出来 `hex.back` 只有 52×52、`cy=834`，
    --        比目标小了 17% —— 就是漏了这一步。）
    --       y 方向：布局图的 y 是**从上**算的，与 `rect.y` 同向，**不用翻转**；
    --       规划会自动把它转成画布的 `cy`（从下算）。
    local K = 6 / 5                                    -- 画布 → 设计空间
    local function D(v) return math.floor(v * K + 0.5) end
    -- ★★★★★ 2026-10-04 **给这 7 个图标绑上事件** —— 这才是"第 4 块：补齐控件"的第一刀。
    --
    --   之前它们只是**图片**：`build_layout` 里建了、位置对、图也设上了（真机 7 行回读全对），
    --   但 `nodes` 里**没有 `event` 字段** ⇒ 适配层不会给它们绑光标事件 ⇒
    --   画面上看得见、点下去什么都没发生。
    --
    --   而"确认状态机"（`self.pending` / `sync_confirm()` / `back_confirm` / `submit` /
    --   `restart` / `confirm_yes` / `confirm_no`）**代码早就写好了**，只差这 7 个入口。
    --
    --   ⚠️ 顺便消掉一处**重复设计**：`confirm.ok` / `confirm.no` 那对节点和
    --      `hex.ok` / `hex.no` **位置一模一样**（438/500, 52, 54×54），
    --      而后者是**运行时已经建好、图也设好**的那一套 ⇒ 保留 hex，删掉 confirm 那对。
    -- ★★★★★ 2026-10-04 **七图标改用"能点"的模板** —— 修"所有按键都没有功能反馈"。
    --
    --   真机日志（17:00，v044）每个图标一条：
    --       `控件 hex.back 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）`
    --   ⇒ 根因：这七个走的是 `cfg.prefab_icon`（**纯图片**客户端模板）——
    --     **图片控件收不到光标事件**（引擎自己这么回的）。上一轮给节点加 `event` 是
    --     **必要但不充分**：事件挂上去了，控件本身接不住。
    --
    --   出路就在同一份日志里：`selbtn.1` 点击成功（`事件=pick_level`），而
    --   `Adapter:ensure_widgets` 建它时用的是 **`cfg.cells.prefab`（格子模板）**，
    --   代码注释原文：「再在容器下建**按钮**（cell 模板 —— 真机验证过能实例化、**能收到点击**）」。
    --   ⇒ 所以这里**去掉 `icon_template = true`**，让它们退回 `cfg.cells.prefab`。
    --
    --   ⚠️ 当初改用纯图片模板是因为"格子模板会连带一整套子控件，画面上多出 7 个迷你格子"。
    --      这个副作用由**子控件默认隐藏**兜住：真机日志里 `wall.*` / `door.*` / `x` 全是
    --      `visible=false`，只有 `face` 会被点亮（`格子底图已点亮：25 个 face`）⇒
    --      每个键看起来就是"一张图"，和纯图片模板的观感一致。
    local ICON_ASSETS = {
      -- id           素材ID    x(画布) y(画布) w    h     事件动作        说明
      { "hex.back",   100109,   60,   48,  62,  62, "back_confirm" },  -- 返回菜单（弯钩箭头 ↰）→ 先问 ✓/✗
      { "hex.submit", 100110, 1448,   48,  70,  70, "submit"       },  -- 提交（向上箭头 ↑）→ 先问 ✓/✗
      { "hex.redo",   100126, 1448,  144,  70,  70, "restart"      },  -- 重置关卡（循环箭头 ↻）→ 先问 ✓/✗
      { "hex.undo",   100127, 1448,  240,  70,  70, "undo"         },  -- 撤回（逆时针箭头 ↶）→ 直接执行
      { "hex.hint",   100120, 1448,  694,  70,  70, "hint"         },  -- 提示（放大镜）→ 直接执行
      { "hex.ok",     100102,  438,   52,  54,  54, "confirm_yes"  },  -- 确认卡 ✓ → 执行 pending
      { "hex.no",     100101,  500,   52,  54,  54, "confirm_no"   },  -- 确认卡 ✗ → 取消
    }
    -- `build_layout` 每帧重建 ⇒ 直接把当前状态折进 `visible` 就够，不需要额外跨帧状态。
    --
    -- ★★★★★ 2026-10-04 **确认卡要出现在"被按下的那个键"旁边**（用户要求）。
    --   规划图上那对 ✓/✗ 画在 (438/500, 52)，旁边还有一行注解：
    --       `APPEARS WHEN SUBMIT / RESET / BACK IS PRESSED`
    --   —— 图里画在 BACK 旁边只是"以返回菜单为例"，**它跟着按下的键走**。
    --   而 SUBMIT / RESET 在右上角（x 1448）⇒ 固定在左上 438 就离得太远了。
    --   ⇒ 三个锚点：返回菜单放**右侧**（跟图上一致）；提交 / 重置关卡放**左侧**
    --     （右边已经贴到画布边缘 1600，放不下）。
    local CONFIRM_GAP = 8
    local CONFIRM_ANCHOR = {
      -- ★ 返回菜单这一档，锚点取**文字右边缘 + 8**，不是"方块右边缘 + 8"。
      --   判据是规划图：图上 ✓/✗ 外面那个虚线框在 **x 430..580**，而
      --   `BACK TO MENU` 文字到 **347** 结束、深色方块在 60..122 ⇒ 图里的确认卡
      --   是画在**整条「返回菜单」控件之后**的，不是紧贴那个方块。
      --   ⚠️ 我第一版取 `60+62+8 = 130` ⇒ 确认卡 (130..246) 正好压在
      --      `action.back` 文字 (133.5..346.5) 上，✓/✗ 会被挡住点不到。
      back    = { x = 347 + CONFIRM_GAP,                            y = 48  },  -- 文字右缘 + 8
      submit  = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 48  },  -- hex.submit 左侧
      restart = { x = 1448 - CONFIRM_GAP - 54 - CONFIRM_GAP - 54,   y = 144 },  -- hex.redo   左侧
    }
    local pend_action = (self.pending and self.pending.action) or nil
    -- ★★★★★★★★ 2026-10-16 **v250：锚点跟着「那颗键的运行时位置」走** ✗✓✓
    --   ★ 用户原话 ✓：「**勾叉确认卡用的是旧规划的位置，没到新位置的旁边**」✓
    --   ★ 真因 ✓：★ 下面那张 `CONFIRM_ANCHOR` 是**写死的** ✗ ——
    --     它是照**规划图**推的（`back` 取"返回菜单那行字的右缘 347+8" ✓）⇒
    --     ★ 一旦那颗键在编辑器里挪了（★ 现在键也归编辑器了 ✓）⇒ ★ 确认卡**不跟** ✗✓
    --   ★ 修法 ✓：★ **读运行时那颗键的真实矩形** ⇒ ★ 卡紧贴它、纵向居中 ✓；
    --     ★ 读不到（控件不在/引擎不给读）⇒ ★ 退回下面那张写死的表 ✓（不许因此不摆 ✓）
    --
    --   ⚠️⚠️ **单位必须是【画布】不是【设计】** ✗✓（★ 第一次写错了 ✓ 见下 ✓）：
    --     · ★ 静态表 `CONFIRM_ANCHOR` 那份是**画布**坐标 ✓（1448 / 48 / 54 … ✓
    --       与 `ICON_ASSETS` 同一套 ✓）—— ★ 而 `ICON_ASSETS` 的数值是**画布 px** ✓
    --       （★ `D()` 会乘 6/5 转成设计 ✓ 交给适配器 ✓）
    --     · ★ 所以本函数**也要给画布** ✓：`cx = 画布宽/2 + ax` ✓、`y = (画布高 − cy) − h/2` ✓
    --       ★ **不要再除 `scale`** ✗ —— 除了就变成"设计"，再进 `D()` 又乘 6/5 ⇒ **位置放大 1.2 倍** ✗✓
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
      local cx = cw * 0.5 + ax          -- 画布绝对 x（中心为原点）
      local cy = ch * 0.5 + ay          -- 画布绝对 y（中心为原点、y 向上）
      -- ★ 换算成"画布 px、左上原点"的矩形 ✓ —— 与静态表同一个坐标系 ✓✓
      return { x = cx - w * 0.5, y = (ch - cy) - h * 0.5, w = w, h = h }
    end
    local anchor = CONFIRM_ANCHOR[pend_action] or CONFIRM_ANCHOR.back
    do
      local kb = key_box_canvas(pend_action)
      if kb ~= nil then
        -- ★ 紧贴那颗键：★ 左边那颗（返回菜单）放**右侧** ✓；右边那两颗放**左侧** ✓
        --   （右边已经贴到画布边缘 1600，放不下 ✓ 与旧注释同一条理由 ✓）
        -- ★ 纵向**居中于那颗键** ✓（旧表是"顶对齐"，视觉上偏高 ✓）
        local cy2 = kb.y + (kb.h - 54) * 0.5
        if pend_action == "back" then
          anchor = { x = kb.x + kb.w + CONFIRM_GAP, y = cy2 }
        else
          anchor = { x = kb.x - CONFIRM_GAP - 54 - CONFIRM_GAP - 54, y = cy2 }
        end
      end
    end
    local icon_pending_on = (self.pending ~= nil)
    -- ★★★★★ 2026-10-04 **两件东西分开做：图标纯贴图 + 独立透明热区**（用户原本的构思，现已验证）
    --
    --   用户做了一次**对照实验**，把结论钉死了：
    --     同一个存档（178-清理旧控件）+ 旧脚本 v037（走 `prefab_icon` 纯图片模板）
    --       ⇒ 日志「图标设图 hex.back imageId=100109 → 回读 100109 **经 子控件** 调用成功=true」
    --       ⇒ **图标看得见**。
    --     而 v045 起换成 `cfg.cells.prefab`（格子模板）⇒ 图标全部消失。
    --   ⇒ 两条路各有各的硬伤，**谁也替代不了谁**：
    --       · 纯图片模板：**能渲染**，但图片控件**收不到光标事件**（引擎逐条报"不支持光标事件"）。
    --       · 格子模板  ：**能收点击**（`selbtn.*` 已验证），但它的 `face` 默认尺寸 0、得额外补尺寸。
    --   ⇒ 所以按用户原本的构思拆开：
    --       **贴图** = `hex.*`（纯图片模板，无事件）—— 负责"看得见"
    --       **热区** = `hit.*`（格子模板，无 image_id ⇒ face 不会被点亮 ⇒ 完全透明）—— 负责"点得动"
    --     反馈由 `self:fx("hex.*", …)` 打在**贴图**上（点击特效本来就是脚本驱动的）。
    --   ⚠️ 顺序要紧：热区**必须排在贴图之后**（后建的在上面）⇒ 射线落在热区上，
    --      不会被不能处理事件的图片控件吞掉。
    for i = 1, #ICON_ASSETS do
      local a = ICON_ASSETS[i]
      local is_confirm = (a[1] == "hex.ok" or a[1] == "hex.no")
      -- 确认卡的位置按锚点算；其余五个用各自在 `ICON_ASSETS` 里写死的坐标
      local ax, ay = a[3], a[4]
      if a[1] == "hex.ok" then ax, ay = anchor.x, anchor.y end
      if a[1] == "hex.no" then ax, ay = anchor.x + 54 + CONFIRM_GAP, anchor.y end
      -- ★★★★★★★★ 2026-10-16 **确认卡（✓/✗）显式交回脚本** ✗✓✓（★ 用户原话 ✓：
      --   「**提交和重置关卡的确认卡没有出现在对应按键旁边（这个就脚本接管吧）**」✓）
      --
      --   ★ 为什么它**必须**由脚本摆 ✗：★ 它的位置是**算出来的** ✓ ——
      --     跟着"刚按下的那颗键"走（见上面 `anchor` ✓）⇒ ★ 存档里**没有**一份能对应的固定坐标 ✗
      --   ★ 而 v248 起「继承来的 `pos_runtime` 不受理」⇒ ★ 它落回存档那份 ⇒
      --     ★ **✓/✗ 出现在别处**（用户看到的正是这个 ✓）✗
      --   ⇒ ★ 这两颗（**只这两颗**）显式写 `pos_runtime = true` ⇒ 脚本每帧按 `anchor` 摆 ✓
      local is_confirm_icon = (a[1] == "hex.ok" or a[1] == "hex.no")
      local vis = (not is_confirm) or icon_pending_on
      local rect = { x = D(ax), y = D(ay), w = D(a[5]), h = D(a[6]) }
      -- ① 贴图：纯图片模板，**不绑事件**
      --
      -- ★★★★★ 2026-10-04 **`parent` = `root`，而且真实父级也必须是 `root`** —— 修"位置还不对"。
      --
      --   两轮真机日志的**点击坐标**给出的结论（v050 与 v051 数值几乎一样 ⇒ 改规划父级无效）：
      --       `hit.hint 点击 (1573,195)`（规划 1483,171）⇒ 差 **(+90, +24)**
      --       `hit.undo 点击 (1585,638)`（规划 1483,625）⇒ 差 **(+102, +13)**
      --       `hit.back 点击 (178,850)`（规划 91,821）  ⇒ 差 **(+87, +29)**
      --   而 `stage` 自己的偏移正是 **(+100, +20)** ⇒ **运行时始终以 `root` 为参照**，
      --   真实父级 `stage` 又叠了自己那一层。⇒ 把**真实父级**也改成 `root`，两层才能抵消。
      --   ⚠️ 早前"挂 root 就看不见"的判断是**错的**：那时图标还在用**格子模板**
      --      （`face` 尺寸 0 ⇒ 什么都不画）。现在贴图已改回纯图片模板
      --      （日志：`图标设图 hex.* … 经 子控件 调用成功=true`）⇒ 挂 root 既可见、位置又对。
      --   对应地 `cfg.parent_of` 里 14 个 id 都写 "root"（适配器自动创建的默认父级是 stage）。
      nodes[#nodes + 1] = {
        id = a[1], kind = "button", parent = "root",
        visible = vis,
        image_id = a[2],
        imageType = "Stretch",
        icon_template = true,          -- ★ 走 cfg.prefab_icon（真机验证：图标看得见）
        rect = rect,
        -- ★ 确认卡那两颗（hex.ok / hex.no）**位置归脚本** ✓（理由见上面那段 ✓）
        pos_runtime = is_confirm_icon or nil,
      }
      -- ② 热区：格子模板、**不给 image_id**（所以 face 不会被点亮 ⇒ 完全透明），只负责收点击
      --
      -- ★★★★★★★★ 2026-10-16 **v250：确认卡的【热区】必须和图标同进退** ✗✓✓
      --   ★ 用户原话 ✓：「**它们的功能也丢失了，现在点不动**」✓
      --   ★ 真因 ✓：★ v249 只把**图标**（`hex.ok`/`hex.no`）交回脚本 ✗ ——
      --     ★ 而**点击落在热区**（`hit.ok`/`hit.no` ✓ 事件绑在它们身上 ✓）⇒
      --     ★ 热区仍是"归编辑器"⇒ 停在存档那份（= 旧的 back 锚点 355,48 ✗）⇒
      --     ★★ **看得见的 ✓/✗ 与能点的 ✓/✗ 分了家** ⇒ ★ 点不动 ✓✓
      --   ⇒ ★ 这一条：★ 与 `hex.ok/hex.no` **同一个开关同一个位置** ✓（`rect = rect` ✓ 上面就是同源 ✓）
      local is_confirm_hit = (a[1] == "hex.ok" or a[1] == "hex.no")
      nodes[#nodes + 1] = {
        id = "hit." .. a[1]:sub(5), kind = "button", parent = "root",
        visible = vis,
        event = { action = a[7] },
        icon_template = false,         -- 走 cfg.cells.prefab（真机验证：能收到点击）
        rect = rect,
        pos_runtime = is_confirm_hit or nil,
      }
    end
  -- ★ 每个节点都必须带**显式** visible：
  --   弹窗/教程的控件在编辑器里是一直存在的，开局由 render 统一藏起来；
  --   如果节点没有 visible 字段，增量渲染就永远不会把它重新显示出来
  --   （2026-09-26 踩过：指认面板出来了，但一直是隐藏的）。
  local function push(n)
    if n.visible == nil then n.visible = true end
    nodes[#nodes + 1] = n
    return n
  end
  local function btn(id, parent, r, text, event, style, enabled)
    return push({ id = id, kind = "button", parent = parent, rect = r, text = text,
                  style = style or "stamp", enabled = (enabled ~= false), event = event })
  end

  push({ id = "root", kind = "container", rect = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }, style = "screen" })

  -- ★★★★★ 2026-10-04 **把 `stage` 也写进规划** —— 它原来"不在计划里"，导致子控件偏移算错。
  --
  --   背景：适配器自动创建控件（`auto_create_only` 名单，如七个 `hex.*`）时，
  --   ⚠️ 2026-10-09 补：那份白名单**已删除**（`hex.*`/`hit.*` 搬进存档了 ✓
  --      见 `tools/gil/gen_icons.mjs` 与 `230-图标搬进存档.gil` ✓）
  --      ★ 但**下面这条决定仍然有效** ✓ —— `stage` 该留在规划里，与白名单无关：
  --      规划里的父子关系必须与**真实控件树**一致，否则中心点偏移算错 ✓
  --   真实父级默认是 **`stage`**；而规划里那七个图标的 `parent` 写的是 `root`。
  --   运行时下发的是「**规划**中心 − **规划父级**中心」，却挂在**真实父级**上解释
  --   ⇒ 差的正好是一个 `stage` 中心的位移：
  --       `stage` 在 (100,20)（棋盘中心 (900,470)）⇒ 整组右移 100、上移 20。
  --   真机实测（17:02 截图）：四图标全部右移 92px、被右边缘切掉。
  --
  --   两个方向都试过了：
  --     · 改 `cfg.parent_of` 挂到 `root` ⇒ 偏移对了，但 **7 个键在关卡里完全不显示**。
  --     · ⇒ 正解：**让"规划父级"和"真实父级"一致**，而不是把真实父级搬走 ——
  --       给 `stage` 补上这条规划节点，父级中心就有了正确来源。
  --   ⚠️ 这条 rect 必须和 `main.lua` 里强制的 `BOARD_W/H = 584`、`BOARD_X/Y = (100,20)`
  --      说的是同一个矩形（`L.board` 就是它），否则又会对不上。
  push({ id = "stage", kind = "container", parent = "root", rect = rect_of(L.board), style = "stage" })

  -- ===== 顶部工具条 =====
  -- ★★★★★ 2026-10-08 **`xxx` 白名单已撤** ✗✓（用户新方案 ✓ 更干净 ✓）
  --   ★ 用户方案 ✓：★ **把 `xxx` 建在"挂了脚本的客户端容器"【之外】** ✓
  --     ⇒ ★ **脚本根本看不见它** ✓ ⇒ ★ 不需要白名单 ✓ **也不需要每帧多查一遍树** ✓✓
  --   ★ 而且 ✓：★ **把它的图层设在整个客户端容器【之下】** ✓ ⇒ ★ 不与任何界面抢层序 ✓
  --   ★ 隔离仍然成立 ✓：★ 整个 2D 画布都在 3D 之上 ✓ ⇒ ★ 它压在 UI 之下、仍在 3D 之上 ✓
  --     ⇒ ★ 空白处触摸被它吃掉 ✓ **落在我们按钮上的触摸仍归按钮** ✓✓
  push({ id = "topbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "topbar" })
  -- 工具条容器：与 topbar 同区（视觉上仍是一条顶栏），只是树里分开，HUD 文字不再和按钮混杂。
  push({ id = "hud.title", kind = "text", parent = "topbar", rect = rect_of(L.title), text = vm.title, style = "title" })
  -- ★★★★★ 2026-10-18 **按用户指令移除 `hud.subtitle`（死代码）** ✗✓
  --
  --   用户原话：「**美术布局上目前没有副标题的位置了，把它当死代码处理吧**」✓
  --
  --   历史（为什么它曾经存在，留档备查）：
  --     · 2026-10-05 的 A8「方案甲」把**关卡内提示语（toast）**接到这条副标题行上
  --       （理由：`hud.title` 用户点名不许用；`hud.timer`/`hud.progress` 只有 ~125px 装不下；
  --        副标题行 717px、语义就是"对玩家说的一句话"）。当时的**硬条件**是"控件必须存在"。
  --     · 而该控件在 v251 那次改档里就没了（`371-v240` 有、`392.4-v251` 起无）⇒ 提示语一直被静默丢弃。
  --   ⇒ 现在**按美术结论收口**：没有副标题位 ⇒ 这条 push 是纯死代码，删掉。
  --     ⚠️ 随之消失的还有两样（**已如实告知用户**）：
  --        ① 关卡内 toast（撤销 / 取消 / 回滚 / 揭示 / 提交与结案结果）无处显示；
  --        ② `meta.announce` 那行「※ 线索中有一句假话 / 全部为真」（case_001 用的是 `"none"`）。
  --     ⇒ 以后要恢复**不要**再接回这里 —— 那个位置不留给文字了。
  --   ⚠️ `toast_text()` 本体**保留**：主页那条出口还在用它（见 `home.title` 的 push）✓


  -- 顶部工具条（1920 宽内排布：标题 32..512 / 计时步数 520..814 / 工具 840..1246 / 动作 1262..1828）
  --
  -- ★ 2026-09-27 结构修正：工具 / 操作按钮原来**直接挂在 `topbar` 下**，
  --   于是 `topbar` 里 HUD 文字（hud.title/subtitle/timer/moves）和
  --   tool.*/action.* 混在一起（用户反馈"hub 中混入了 action 和 tool"）。
  --   现在独立出一个 `toolbar` 容器：**topbar 只放 HUD 文字，按钮归 toolbar**。
  --   位置仍用**绝对 rect**（见 L56 的坐标换算注释：rect 是设计空间绝对坐标），
  --   所以改父级**不会移动任何控件**，只是树结构变干净。
  -- ★★ 2026-09-29（用户要求）：**删掉「放置 / X 标记 / 橡皮擦」三个工具按钮**。
  --
  --   理由（用户原话）：「因为放置，标记，橡皮擦，都已经有了合适的操作逻辑，
  --   这三个按钮可以删了」——
  --     · 放置：**双击 / 长按**格子
  --     · 标记：**单击**空格（未选人时切 ✗，选中人物时是预放置）
  --     · 橡皮擦：**单击已放置的格子**就是拿起
  --   三个动作全都有更直接的入口，工具按钮纯属多余（还占着工具条正中间）。
  --
  --   ⚠️ 保留 `Core.mode` 与键盘换工具的**能力**（`Tab` 轮盘仍可切换，
  --      `note` 模式仍可用）—— 删的只是这三个按钮，不是模式机制本身。
  --      这样"以后想加回按钮"或"给移动端留一条路"都不用重写逻辑。
  --
  --   注（踩过的坑）：**不能"干脆不 push"** ——
  --   渲染的差集逻辑只隐藏**曾经显示过**的控件，从没进过计划的控件不会被隐藏，
  --   按钮照样留在屏幕上（实测）。
  --   ⇒ 正确做法是**留在计划里，但 `visible = false`**，让渲染真的把它们藏掉。
  local function tool(id, label, mode, x)
    return push({ id = id, kind = "button", parent = "toolbar",
                  rect = { x = x, y = 26, w = 130, h = 52 }, text = label,
                  style = (vm.hud.mode == mode) and "tab.active" or "tab",
                  visible = (M.SHOW_TOOL_BUTTONS == true),
                  event = { action = "tool", mode = mode } })
  end
  -- ★★ 2026-09-29：用户已在编辑器里**删掉这三个控件**（存档记录 231 → 197）。
  --
  --   脚本必须跟着删，否则 `sub(id,"label")` 找不到子控件 ——
  --   真机日志里那 16 条"读回 nil"就是这个原因：
  --   **不是写入失败，是控件根本不存在**。
  --   （我上一版用 `visible=false` 想"藏起来"，但控件被删掉之后连藏都无从谈起。）
  --   要恢复：把 `M.SHOW_TOOL_BUTTONS` 设为 true **并且**在编辑器里把三个控件加回来。
  if M.SHOW_TOOL_BUTTONS then
    tool("tool.place",  "放置",  "place",  840)
    tool("tool.x",      "X 标记", "x",      978)
    tool("tool.eraser", "橡皮擦", "eraser", 1116)
  end

  -- ★★★ 2026-09-30：**「撤销 / 提交 / 揭示」挪到右侧竖排**（用户确定的映射，参考执律庭实习）。
  --
  --   用户给的排除逻辑：重做 → 已被「重置关卡」占用、提示 → 已被右下角放大镜占用
  --   ⇒ 剩下这三个放右侧三个六边形位置。
  --
  --   两处必须同源：
  --     · 这里（布局计划）—— 模拟器建树、编辑器搭建指南都读它
  --     · `.gil`（`tools/gil/move_side_buttons.mjs` 挪的）—— 真机实际几何
  --   因为 `cfg.respect_editor_rect = true`，真机上**以 `.gil` 为准**；
  --   计划这份是为了让模拟器/文档跟真机一致，别让两边说法不同。
  --
  --   注：父级从 `toolbar` 改成 `root` —— 右侧竖排的 y 已经超出 toolbar 的高度（104），
  --   挂在 toolbar 下会被裁掉。
  -- ★ 2026-10-18（优化组 · P0）：**「用基础图元拼六边形按钮底图」整段删除** ✗✓
  --
  --   删的是：`HEX_RECT/HEX_TRI` 常量 + `HEX_PARTS`（6 块拼片）+ `HEX_PREFAB` 开关 + `hex_bg()` 函数。
  --   判据（三条都要成立才算死代码）：
  --     ① `hex_bg(` 全文件 **0 个调用点**（只剩注释里的历史写法）；
  --     ② `HEX_PREFAB` 是 **常量 false**（2026-10-03 真机探针实测：
  --        `InstantiateClientUIControl(1073742333, root)` pcall 成功但**返回 nil** ⇒
  --        "按模板索引实例化素材"这条路走不通 ⇒ 之后改走「在编辑器里摆现成图片」
  --     ③ 三个目标的父控件（`action.back/redo/hint`）**已按用户指令从存档删除** ⇒
  --        底图节点就算建出来也是悬空节点（正是当年 T3 要避免的那种）。
  --   ⇒ 现在这三个按钮的外观**全部由存档里的 `hex.*` 图片控件承担**（`ICON_ASSETS` 那条路），
  --     脚本这一侧不再需要任何"拼图元"的代码 ✓
  --   ⚠️ 历史理由（六边形怎么拼、"两个三角会得到八角星"那条教训）已在 git 历史与
  --     `docs/外部资产-怎么用与我做了什么.md` 里，需要时能查回来 ✓
  -- ★★★★★ 2026-10-02 **右上三键 = 提交 / 重置关卡 / 撤销**（用户定稿，见 LAYOUT 尾部那段注释）
  --
  --   原来是「撤销 / 提交 / 揭示」竖排在右侧中部（x=1790, y=390/540/690）。
  --   现在按参考图挪到**右上角**，并把「揭示」换成**重置关卡**（从左上搬来）：
  --     上 → 下：提交 / 重置关卡 / 撤销
  --   右边缘 = `LAYOUT.side_key.right_edge`，**右下角那组（0/6 + 放大镜）也贴这条线**。
  -- ★ 2026-10-18（优化组 · P0）：`SK` / `sk_x` / `sk_y` 三个 local **已删除** ——
  --   它们唯一的使用点是上面那段被删掉的六边形底图（`hex_bg("action.back", sk_x + 55, sk_y[1] + 55, …)`）
  --   判据：删完 HEX 段后全文件对这三个名字的引用为 **0**（含注释）✓
  -- ★ 2026-10-18（优化组 · P0）：`if HEX_PREFAB then … end` **整段删除** ✗✓
  --   判据：`HEX_PREFAB` 自 2026-10-03 起是**常量 false**（原因写在下面墓碑里），
  --     而块内**两条分支都不建任何节点**（注释自己也写着"现在两条分支都不再建任何节点"）
  --     ⇒ 这段是恒假分支 + 空壳 ✓ 删掉零行为变化 ✓

  -- ★★★★★ 2026-10-04 **右上三键（提交 / 重置关卡 / 撤销）的旧文字按钮 —— 已删。**
  --
  --   用户反馈「右侧四键的位置不对」。实测两套键**重叠且动作重复**（画布中心）：
  --       action.submit (1541,833) 92x92  vs  hex.submit (1483,817) 70x70
  --       action.redo   (1541,708)        vs  hex.redo   (1483,721)
  --       action.undo   (1541,583)        vs  hex.undo   (1483,625)
  --       action.hint   (1541,126)        vs  hex.hint   (1483,171)
  --   布局图定稿的是**七个 `hex.*` 图标**（位置逐项吻合，且已经有素材图），
  --   而旧文字键偏右上 58px、还大一圈 ⇒ 画面上就是"两套键叠着"。
  --   ⇒ 留图上那套，删掉这四个旧节点。
  --   ⚠️ `action.redo` / `action.hint` 在用户存档里**真实存在**（编辑器摆的）——
  --      删掉计划节点后它们会落进"不在计划里"的名单，由 `Adapter:hide_unlisted` 收起。
  --
  --   （历史注释：`action.redo` 的父级必须与存档一致，否则运行时按「规划中心 − 规划父级中心」
  --     下发的偏移会落到错的父级上、整支偏 407px。这条仍然成立，只是该节点已删。）

  -- 提交 / 重置关卡 / 撤销 / 提示 的入口 = 上面 `ICON_ASSETS` 里的 `hex.submit` /
  -- `hex.redo` / `hex.undo` / `hex.hint`（已接上确认状态机）。

  -- ★ 删除（参考图里没有）：`action.reveal` 揭示 / `hud.score` / `hud.violations`
  --   / `hud.share` / `hud.toast`。删除方式 = **不再 push 这些节点** ——
  --   `layout_plan` 与 `build_layout` 同源，不再出现的节点在编辑器指南里也会消失。
  --   （`.gil` 里若还残留同名控件，`tools/gil/prune_nodes.mjs` 负责清掉。）
  --
  -- ★★★ 2026-09-30：**按参考图重排顶栏与右下角**（《派蒙的执律庭实习》局内 UI）。
  --
  --   参考图的四个位置：
  --     左上   「返回菜单 ↰」 + 「重置关卡 ↻」
  --     右下   「0/6」计数 + 一个**放大镜**
  --     右侧竖 三个深色六边形（= 我们的 撤销/提交/揭示，上一轮已挪好）
  --
  --   对照关系（用户给的排除逻辑：重做→重置关卡、提示→放大镜）：
  --     · `action.back`  ——「返回列表」，挪到**左上**
  --     · `action.redo`  —— 按钮改成**「重置关卡」**，动作换成 `restart`
  --       （`restart` 早就实现了：`core:reset()`。**重做没有消失** ——
  --        键盘快捷键里仍然保留 `redo`，只是这个**按钮**让给了"重置关卡"。）
  --     · `hud.progress` + `action.hint` —— 挪到**右下角**（计数 + 放大镜）
  --
  --   几何两处同源：这里（布局计划）+ `.gil`（`tools/gil/move_side_buttons.mjs`）。
  -- ★★★★★ 2026-10-02 **左上 = 返回菜单 + ✓/✗ 确认条；右下 = 进度 + 放大镜（右对齐）**
  --   用户定稿（`docs/布局图-关卡内-v3.png`）：
  --     · 左上只留「返回菜单」；`action.redo`（重置关卡）**已搬到右上第 2 个**
  --     · 它右边是 ✓ / ✗  —— **默认 visible=false**，点「返回菜单 / 提交 / 重置关卡」时出现
  --     · 右下 = `hud.progress`（0/6 计数）+ `action.hint`（放大镜 = 继承的提示功能）
  --       两者**右边缘与右上三键对齐**（同一列，右边缘 = L.side_key.right_edge）
  -- ★★★★★ 2026-10-04 **`action.back` 缩到"BACK TO MENU 文字"那一段** —— 它原来和两样东西重叠。
  --
  --   原来 `back_btn = {x=24, y=22, w=300, h=66}`（设计空间）⇒ 画布 x 20..270、y 826..881，
  --   而规划图 v3 上这两块是分开的：
  --     · 深色方块 + `<` 弯钩箭头   x 60..122、y 48..110   （画布）← 由 `hex.back` 负责
  --     · 文字 `BACK TO MENU`       x 134..347、y 64..84   （画布）← 这一块才是 `action.back`
  --   ⇒ 旧值把方块和文字**一起盖住**，于是和 `hex.back`(60..122) 重叠；
  --     更要命的是**确认卡**现在出现在 `hex.back` 右侧（x 130..246、y 798..852）
  --     ⇒ 旧 `action.back` 正好压在同一片区域上，✓/✗ 会被它挡住点不到。
  --   ⇒ 按图上文字的实际范围收窄：画布 x 134..347、y 64..84
  --     ⇒ 设计空间 x 161..416、y 77..101 ⇒ 取 {x=161, y=77, w=255, h=28}。
  -- ★★★★★★ 2026-10-11 **`action.back` 整颗删除** ✗✓✓
  --
  --   ★★ 用户指令 ✓（★ 分两步 ✓）：
  --     ①「**右下角有一个返回列表按键，它和左上角的返回箭头功能一模一样，
  --         都是连接弹窗，这是重复的东西，你把它删掉**」✓（★ 已删 `right` 那份 ✓）
  --     ②「**那个返回菜单也不要，一起删**」✓（★ 本次 ✓）
  --
  --   ★★★ 为什么可以整颗删 ✓：
  --     ★ **左上角的「返回箭头」是 `hex.back`** ✓ —— ★ 它是【图标】✓
  --        ★ 声明的事件是 `back_confirm` ✓ ⇒ ★ **点它先弹 ✓/✗ 确认条** ✓
  --        ★ 而确认条由 `main.lua` 的 `confirm_show()/confirm_hide()` 负责 ✓
  --     ★★ **⇒ 返回功能【完全由 `hex.back` 承担】✗ ⇒ `action.back` 是纯多余的文字块** ✓✓
  --
  --   ★★ 删掉的原文（★ 备查 ✓）：
  --     `local BK = L.back_btn`
  --     `push({ id = "action.back", kind = "button", parent = "topbar", visible = true,`
  --            `rect = { x = BK.x, y = BK.y, w = BK.w, h = BK.h },`
  --            `text = "返回菜单", event = { action = "back_confirm" }, style = "stamp.sm" })`
  --
  --   ★★★ 连带清理 ✓（★ 否则会变成"写不存在的控件"✗）：
  --     · `main.lua` L959 附近的【体检名单】里的 `"action.back"` ✓ 已去掉 ✓
  --     · `main.lua` L1262 附近的【对照组样本】里的 `"action.back"` ✓ 已去掉 ✓
  --     · `tests/prop_ledger.lua` 里"它有两个节点"那几条断言 ✓ 已按新意图更新 ✓
  --
  --   ⚠️ ★ 注意 ✓：★ **`hex.back` 才是返回箭头，别把它一起删了** ✗✓
  --      （★ 它的 id 在 `ICON_ASSETS` 里 ✓ 由脚本从模板建出来 ✓）


  -- ✓ / ✗ 确认条：**默认隐藏**（visible=false）。真正的显隐由 main.lua 的
  --   `confirm_show()/confirm_hide()` 每帧按 `pending_action` 决定 ——
  --   这里只负责"建出来 + 给个初始隐藏状态 + 绑事件"。
  -- ✓ / ✗ 确认条：**默认隐藏**（visible=false）。
  --   显隐规则：只有 `self.pending ~= nil`（点了 返回菜单 / 提交 / 重置关卡）时才出现。
  --   `build_layout` 是**每帧重建**的（见文件头"控件树每帧重建"那段）⇒
  --   直接把 `self.pending` 折进 `visible` 就够了，不需要额外的跨帧状态。
  -- ★★★★★ 2026-10-04 **这里原本还 push 了 `confirm.ok` / `confirm.no` 两个节点 —— 已删。**
  --
  --   为什么删：它们和上面 `ICON_ASSETS` 里的 `hex.ok` / `hex.no` **位置一模一样**
  --   （438/500, 52, 54×54 —— 都是从同一张布局图上量的），事件也一样
  --   （`confirm_yes` / `confirm_no`）⇒ **同一件事两处实现**。
  --   而 `hex.ok` / `hex.no` 是**运行时由脚本从模板建出来的**（真机日志：`图标设图 hex.ok
  --   imageId=100102 → 回读 100102` 成功），`confirm.ok` / `confirm.no` 在存档里**根本不存在**
  --   （真机日志：`confirm.no 读回 nil`）⇒ 保留能用的那套。
  --   ⇒ 确认键 = `hex.ok` / `hex.no`，显隐跟着 `self.pending` 走（见上面 ICON_ASSETS 那段）。

  -- 右下：计数。放大镜的入口 = `hex.hint`（图上那枚，已接 `hint` 动作）——
  --   旧的 `action.hint` 文字按钮已删（与本轮右上三键同样的理由：与 `hex.hint` 重叠且动作重复）。
  local RB = L.side_key.right_edge
  local PG = L.progress
  push({ id = "hud.progress", kind = "text", parent = "right",
         rect = { x = RB - 110 - PG.icon_gap - PG.num_w, y = PG.y, w = PG.num_w, h = PG.h },
         text = string.format("%d / %d", self:placed_count(vm), vm.piece_count),
         style = "stat" })

  -- ★★★★★ 2026-10-04 **计时器跟着标题进左边栏**（图上 TIMER 就在 TITLE 下面一行）。
  --   量图：字形带 x 60..343、y 190..217 ⇒ 中心 (201.5, 203.5) 画布
  --   ⇒ 设计空间中心 (242, 244) ⇒ 取 {x=72, y=216, w=340, h=56}
  push({ id = "hud.timer", kind = "text", parent = "topbar",
         rect = { x = 72, y = 216, w = 340, h = 56 },
         text = self:format_time(vm.hud.time), style = "stat" })

  -- ===== 左侧面板：头像卡 + 线索卡 + 图例 =====
  -- ★★★★★ 2026-10-02 用户定稿：**头像卡（tray）并进"滚动线索卡"** ——
  --   每张线索卡 = 头像 + 线索文本 + 字母徽章（见下面 `clue.<i>.face` 那段）。
  --   所以这里**不再单独建头像卡**：容器留着但 `visible = false`
  --   （老存档里还有这个控件名，留个空壳比直接删更稳，不会让"控件找不到"的报警刷屏）。
  -- ★ 2026-10-18（优化组 · C 类清理）：**头像卡容器 `tray` 与它的自适应布局整段删除** ✗✓
  --   判据：① `n_tray` 早在 2026-10-02 就被写成 **0**（头像卡并进滚动线索卡）⇒ 循环一次都不执行；
  --     ② 真机日志每一局都打「找不到头像卡容器（cfg.tray_parent，默认 tray）」；
  --     ③ `check_names` 里 `tray` 是 🔴 真缺（存档里从来没有）。
  --   ⚠️ `vm.tray`（嫌疑人列表）**保留** —— `placed_count` 还在用它 ✓
  --   ⚠️ 适配层 `apply_tray_layout` 那 110 行属下一批（要连 `_tray_btn_art` 与回归一起改）。

  -- ★★★★★ 2026-10-05 **父级必须是 `root`，不能写 `left`** —— 修"线索区跑到棋盘下面"。
  --
  --   真机日志（11:52）铁证：
  --       left = **找不到**                     ← 运行时根本没有 `left` 容器
  --       clues 位置=(47,-29)  尺寸=400x544     ← 位置整个跑偏（画面在棋盘下方）
  --       客户端 UI 根清单：root 子控件=22  └ clues  visible=true 400x544   ← **真实父级是 root**
  --   而规划里写的是 `parent = "left"` ✗ ⇒ 偏移按"真实父级(root)"解释、
  --   却拿一个**不存在的父级中心**去算 ⇒ 整块位置错掉 ✓
  --   （与之前 `hex.*` 那个 bug 完全同一个形状：**规划父级必须等于真实父级**。）
  -- ★★★★★ 2026-10-05 **`pos_runtime = false` = 整块线索区退出"脚本接管几何"** ——
  --   用户原话：「这个区域的位置大小都是原本摆好的，也不需要每关放缩，
  --   脚本只需要管可见性和交互就行了，其它的干涉都是只会增加错误的操作。」
  --
  --   机制（看 `inherit_pos_runtime`）：`pos_runtime` 会**沿子树向下继承**
  --     `if nodes[i].pos_runtime then pr[id]=true end`
  --     `if (not n.pos_runtime) and pr[n.parent] then n.pos_runtime = true end`
  --   ⇒ 显式写 `false` 时 `not n.pos_runtime` 为假 ⇒ **该节点不继承** ⇒
  --     它自己 + 它下面所有没显式标 `true` 的子控件（clues.bg / bar / track / knob /
  --     clue.N 及全部子控件）**统统退出脚本接管** ✓
  --   ⇒ 于是脚本对这块**只做两件事：显隐 + 交互**（正是用户要的），一个坐标都不碰 ✓
  push({ id = "clues", kind = "container", parent = "root", rect = rect_of(L.clues),
         style = "panel" })
  -- ★★★★★ 2026-10-05 **线索区大底板（`clues.bg`）** —— 用户在编辑器里摆的那张图，
  --   但它的名字不在规划里 ⇒ 脚本从没点亮它 ⇒ 真机日志（11:31）里它一直 `可见=false` ✗
  --   ⇒ 补一条规划节点（`kind = "container"`：只摆位置/显隐，**不设图不设色**，图与色归编辑器）。
  --   尺寸与容器同尺寸（画布 400×544）、挂在 `clues` 下、坐标相对父级 ⇒ (0,0) ✓
  --   ★★★★★★★★ 2026-10-16 **关于"网格视窗大小改不动"的结论（复核后写下 ✓）** ✗✓✓
  --     ★ 用户原话 ✓：「★ **网格视窗的大小我已经改了，你也让脚本按原样大小出就行**」✓
  --   ★★ 复核结果 ✓：★ **这里本来就已经是"原样出"** ✓ —— ★ 不用改 ✓
  --     · ★ 适配器 `set_property` 的 `rect` 分支 ✓：`respect_editor_rect ~= false`
  --       ★ 且控件不是脚本实例化的、也没有 `runtime_rect` ⇒ ★ **直接 `return true`** ✓
  --       （★ 源码原文：「★ **这是故意的空操作**（"位置归编辑器管"）✓」✓）
  --     · ★ 而这一条 `push` 带着 **`pos_runtime = false`** ✓（见下面 `clues.grid` 那条 ✓）
  --       ⇒ ★ **它进不了"位置归脚本管"的那一类** ✓ ⇒ ★ 尺寸/位置**一直归编辑器** ✓
  --   ★★ 所以"改不动"的真正原因不在这里 ✗ —— ★ 是 **`main.lua` 每帧强写 `stage`** ✓：
  --     ★ `stage` 是 `clues` 的**祖先** ✓，★ 而格子尺寸是按**父容器尺寸**算的 ✓
  --     ⇒ ★ `stage` 每帧被写回 584 ⇒ ★ 父级一变 ⇒ ★ 下级的几何跟着重算 ⇒ 你改的看不出来 ✓
  --   ⇒ ★★ 已在 `main.lua` 用 **`cfg.geom_by_editor`** 关掉那两处 ✓（本轮 ✓）
  push({ id = "clues.bg", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         -- ★★★★★ 2026-10-05 **补上 `visible`** ✗✓ —— 这是"线索区没出来"的**两个原因之一** ✓
         --
         --   症状（真机日志 `23:13:32` 的排行榜 ✓）：
         --     · `clues`      400x544  可见=**true**  ✓（父级亮着 ✓）
         --     · `clues.bg`   400x544  可见=**false** ✗  ← ★ 子控件黑着 ⇒ 屏幕上什么都没有 ✓
         --     · `clues.grid` 400x544  可见=**false** ✗（那一条见下面 `_grid_state` 处 ✓）
         --
         --   为什么：★ 上面 L2023 那句注释【自己就写着】「它的名字不在规划里 ⇒
         --     脚本从没点亮它」✗ —— 后来补了这条规划节点 ✓，★ **但没给 `visible`** ✗✓
         --     ⇒ 属性循环里 `visible = nil` ⇒ **不发这一条** ✗ ⇒ 它保持引擎初值（false ✗）
         --   ★ 而 `clues`（父容器 ✓）之所以亮：★ 它由 `apply_screen_hide` **显式写** ✓
         --     （HIDE 名单里有 `clues` ✓ 关卡内写 true ✓）—— ★ **而子控件不在那份名单里** ✗✓
         --     ⇒ ★★ 所以判据必须【与 `clues` 完全一致】✗：关卡内显示 ✓ 主页/选关藏 ✓
         visible = (self.screen == nil) })
  -- ★★★★★ 2026-10-05 **网格视窗 `clues.grid`（官方列表控件）—— 用户在编辑器里摆好的线索列表。**
  --
  --   为什么要有这条规划节点：**不在规划里的控件，脚本不认它**（不会点亮、不会按屏幕开关）
  --   —— `clues.bg` 就是因为漏了这条，真机上一直 `可见=false`（11:31 的日志）。
  --   网格视窗是同一类问题：它得**关卡里可见 / 主页·选关时不出现**。
  --
  --   显隐怎么来的（**与 `clues.bg` 完全同一套**，没有第二套机制）：
  --     · 关卡里：`clues` 与它自己都是 `visible=true` ⇒ 看得见；
  --     · 主页/选关：父级 `clues` 被判成 `visible=false`（`apply_screen_hide` 的 HIDE 名单里
  --       有 `clues`），子控件跟着父级一起不显示 —— 实测规划里 `clues.bg` 就是这个状态
  --       （主页那一屏 `clues(vis=false)` / `clues.bg(vis=true)`，屏幕上并没有露出底板）。
  --
  --   ⚠️ **故意不给它加"按屏幕翻自己的 visible"**：本项目已经验证过一次——
  --      「容器被 `SetVisible(false)` 之后，再 `SetVisible(true)` **射线不一定恢复**」
  --      （见 `home`/`select` 那段"容器恒为可见"的注释）。网格视窗的**点击**本来就是
  --      本轮最不确定的一环，不该再去承担这个额外风险 ⇒ 它自己的 visible **只在
  --      "这条路走不通"时翻一次 false**（见下面的表达式），其余时候恒为 true ✓
  --
  --   ★★ `pos_runtime = false` —— **一个坐标都不碰**（用户原话：「位置大小都是原本摆好的，
  --      脚本只需要管可见性和交互，其它的干涉都是只会增加错误的操作」）。
  --      机制：`pos_runtime` 只沿子树"向下继承 true"（见 `inherit_pos_runtime`），
  --      显式写 `false` ⇒ 不继承 ⇒ 适配器 `set_property("rect")` 走
  --      `respect_editor_rect` 那条分支直接 `return`（连锚点都不设）⇒ 几何完全归编辑器 ✓
  --
  --   ⚠️ 下面这个 `rect` **只是规划表要的字段**（`layout_plan`/`dump_layout` 会读它，
  --      缺了 `M.to_canvas(nil)` 会当场报错），**运行时永远不会下发**（见上一条）。
  --      取值按编辑器里量到的真实尺寸写：网格视窗 **400×544 画布** = 480×652.8 设计
  --      （与 `L.clues` 同一块区域，所以直接沿用 —— 存档核对：id 1073742420、父 `clues`）。
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **一行诊断：把 `_grid_state` 的【真实值】打出来** ✗✓
  --
  --   ★ 起因 ✓：★ 真机日志里 `clues.grid` **可见=false** ✗ 而【同一份日志】又说
  --     「网格视窗：找到 clues.grid ✓ … RefreshItems 回调 **7 次**」✓ ⇒ ★ 它明明成功了 ✓
  --   ★ 而我这一轮**把顺序那条排掉了** ✓：
  --     · `render` 里 **sync 先（L4103）· 规划后（L4105）** ✓ ⇒ ★ 同帧生效 ✓
  --     · `seen` 先收齐（L4137~4138）再算差集（L4168/4186）✓ ⇒ ★ 不是那个老坑 ✓
  --   ⇒ ★★ 所以只剩一种解释 ✓：★ **这一帧 `_grid_state` 真的是 `"off"`** ✗
  --     ★ 即：★ `sync_clue_grid` **判定失败了** ✗ —— ★ 而它的失败行（`_grid_fail`）
  --       ★ 因为 `_grid_log` **去重**，可能只打过一次、或者根本没进我看到的日志 ✓
  --   ★★ 这行日志的价值 ✓：★ **一次实测就能定死方向** ✓✓
  --     ★ 打出 `on` ⇒ ★ 那问题在**渲染层**（★ 我再去查差集 ✓）
  --     ★ 打出 `off`/`nil` ⇒ ★ 那问题在 **`sync_clue_grid` 判定失败** ✓
  --   ⚠️ `push` 是**每帧**跑的 ✗ ⇒ 必须**只打一次** ✓（用 `_grid_log` 的去重 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **这里原来有一处【死代码】诊断，已删** ✗✓（第 246 号提交留下的 ✓）
  --   ★ 原文是 `if self._grid_log ~= nil then self:_grid_log("state_value", …) end` ✗
  --   ★★ 而★ `_grid_log` **定义在 L3512** ✓ ★ 而这里在 **L2110** ✗
  --     ⇒ ★ **那一刻它是 `nil`** ✗ ⇒ ★ **守卫直接跳过** ✓ ⇒ ★ **从来没执行过** ✗
  --   ★★★ 第 247 号提交只把"能打出来的那版"改成了 `print` ✗ ★ **没删这一处** ✗
  --     ⇒ ★ 于是它一直躺在规划里 ✗ ★ **看起来像在工作 ✓ 其实是死的** ✓✓
  --   ⚠️ 教训 ✓：★ **改诊断的时候，要把旧的那份删掉** ✗
  --     ★ 本项目已经踩过同一形状两次 ✓（`erases` / 缩放表 都是"两处负责"✓）
  push({ id = "clues.grid", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h },
         -- 走不了网格视窗时（cfg.use_grid=false / 找不到控件 / 填内容失败）把它藏起来，
         -- 免得"老卡片回来了、但网格还盖在上面" —— 见 `Controller:sync_clue_grid`
         visible = (self._grid_state ~= "off"),
         -- ★ 2026-10-16 v253：原来这里还有一句 `pos_runtime = false` ✓ —— ★ 已删除 ✓
         --   （★ 现在只有"显式 `true`"才让脚本摆位置 ✓ ⇒ `false` 与"不写"完全等价 ✓ 是死代码 ✓）
         })
  -- ★★★★★ 2026-10-05 **网格视窗在用时，老的一套线索控件"整段不进规划"**。
  --
  --   真机证据（用户实测，每帧刷、永久刷）：
  --     attempt to call method 'imageSource' on an invalid object
  --       client_script:10043 set_property ← 6485 render ← 11832 on_update（start 时也来过一次）
  --   根因链条（已在代码里对上，不是猜的）：
  --     ① 列表项模板（1073742421）的子控件**名字和旧卡片一字不差**：
  --        `clue.1.backrop1` / `backrop2` / `face` / `who` / `what` / `letter`；
  --     ② 适配层 `Adapter:set_property` 第一步就是 `self:find(id)` —— 它按**名字**
  --        在客户端控件树上深度优先搜，**而且把首次命中缓存进 `self.controls[name]`**；
  --     ③ 网格视窗的列表项是**复用**的（官方：只加载可见范围内的列表项）⇒ 名字
  --        `clue.1.face` 抓到的很可能是**已经被回收的那一个列表项** ⇒ 句柄失效；
  --     ④ `clue.N.face` 这个节点带着 `image = ...` ⇒ 走 set_property 的 `image` 分支，
  --        里面那行 `local src = target.imageSource`（适配器 3347 行）**没有 pcall** ⇒ 抛错。
  --   ⇒ 所以旧写法（"照旧 push、只把 visible 改成 false"）根本挡不住：节点还在规划里，
  --     每帧照样 `set_property` 一次，`clue.N.face` 的 `image` 照样下发 ⇒ 每帧抛一次。
  --     更糟的是错误从 `render` 里抛 ⇒ **后面的节点全没处理** ⇒ 用户看到的两条连带症状：
  --     模板格子出不来、`clues.bg` 时有时无（都不是它们自己的问题）。
  --
  --   ⇒ 这一版的让位 = **从源头不发**：不建、不摆、不点亮、连动效都不排队。
  --     判据用 `is_legacy_clue_id`（本文件唯一一份名单，`render` 那边共用同一个函数）。
  --
  --   ⚠️ 下面这一大段的**缩进故意保持原样**（不退不进）：它只是被一个开关括起来，
  --      重排两百多行缩进会让"这一轮到底改了什么"完全看不出来 ⇒
  --      宁可用一个醒目的 `end` + 行尾注释来收口（Lua 不看缩进，语义完全一致）。
  local grid_on = (self._grid_state == "on")
  if grid_on then
    self:_grid_log("giveway", "网格视窗：老的一套线索控件**整段不进规划**（不建 / 不摆 / 不点亮 / "
      .. "连动效都不排队）—— 只藏起来不够：`clue.N.*` 这个名字会被按名字抓到已回收的列表项")
  end   -- ★ 2026-10-20（优化组 · C 类清理）：**`else` 分支（老线索卡兜底）已删除** ✗✓
        --   判据：真机日志 v276/v277「网格视窗：索引基准定为 0」「找到 clues.grid ✓」⇒ `grid_on` 恒真，
        --     这段 `else` 一次都不执行；而布局计划里仍残留 **48 个 `clue.*`**
        --     （就是每局那行「规划里有 40 个控件是【已知不需要】」的来源）。
        --   用户指令：「老计划里到目前还没实现的都不需要保留了」⇒ 删。
        --   ⚠️ `clues.bg` / `clues.grid` 是活的，**没动**；下面的「发完再扫一遍」第二道闸也**保留**
        --      （它是防回归哨兵：万一以后有人在守卫外面又 push 一个 `clue.*`，会被当场剔除 ✓）
        --   ⚠️ 要恢复旧卡片请从 git 历史取，**别**把 `else` 分支直接搬回来 ——
        --      它每帧按名字抓手柄会撞到"已回收的列表项"（当年那个每帧抛错的老 bug）✗

  -- ★★★★★ 2026-10-05 **收口：规划里绝不允许出现老一套的 id**（守卫之外的第二道闸）。
  --
  --   守卫管的是"这一段不发"；这里管的是"发完再扫一遍"——
  --   以后谁在守卫外面又加了一条 `clue.*` / `clues.up` 的 push，
  --   会被这里当场剔除**并打一行日志**，不会又变回"每帧按名字抓到已回收的列表项"。
  --   （两道闸共用一个判据 `is_legacy_clue_id`，不会漂移。）
  --
  --   为什么剔除还不够、必须连"名字"都不碰：见 `render` 里 `stale_legacy` 那段注释。
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

  -- 操作提示**按设备换文案** —— 同一套界面同时给 PC 键鼠和移动端触碰用，
  -- 但两边的"怎么操作"不一样，写在图例里免得玩家自己试。
  -- ★★ 2026-09-29：**图例文案按"按钮删掉之后"的新操作逻辑重写**。
  --
  --   为什么必须改脚本：**文字内容存不进 `.gil`**（已验证多次：`ruler.c.1` 显示 "C1"、
  --   `hud.title` 显示标题，但记录里只有控件自己的名字）——
  --   这是少数**只能走脚本**的事，正好落在《工作约定》里"必须走脚本"那一栏。
  --
  --   旧文案在说已经不存在的入口（「X工具」「橡皮擦」按钮），
  --   而真正该告诉玩家的是三条最高频动作：
  --     单击空格 = 划掉这格（✗，不需要先选工具）
  --     选中头像后单击 = 假设他在这里（预放置）
  --     双击 / 长按 = 正式放置；单击已放置的格 = 拿起
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
      -- ⚠️ 官方键事件是**语义事件 + 可重映射的「奇匠按键」**（见 KB_ACTIONS 注释），
      --    所以这里写"默认键"，并说明"以你自己的按键设置为准" —— 不能假定玩家
      --    按的一定是 ↑↓←→ / F / Space。
      .. "键盘(默认键)：方向键移动　F放置　空格笔记　Tab换工具　数字选人\n"
      .. "（键位可在按键设置里改，以你实际的为准）"
  elseif self.input_profile == "gamepad" then
    legend_text = "确认=笔记　按住=放置　肩键切换工具\n（手柄为兜底方案，推荐用键鼠或触屏）"
  end


  -- ===== 中央棋盘（含坐标尺）=====
  -- 格子几何按**当前关卡的实际 N** 自适应：
  -- 棋盘区大小固定，格子边长 = 可用边长 / N。这样 5×5 / 6×6 / 7×7 都能正确排布，
  -- 不需要为每个尺寸重摆一次编辑器布局（编辑器里按**最大的 N** 建够格子即可，
  -- 小尺寸关卡多出来的格子由界面层隐藏、位置由脚本运行时摆正）。
  local n = math.max(vm.rows, vm.cols)
  -- ⚠️ `L.ruler` 是**棋盘边框厚度**（**不是**已废弃的行标/列标功能 ✓）——
  --   格子几何按"可用边长 = 棋盘 − 两边各一份边框"算 ✓，这一条**必须保留** ✓
  --   （★ 2026-10-12：行标/列标那套控件已按用户要求**整段删除** ✓ 见本文件 LAYOUT 里的说明 ✓）
  local avail_w = L.board.w - 2 * L.ruler     -- ★ 边框**两边各一份**（原来只扣一边）
  local avail_h = L.board.h - 2 * L.ruler
  local pitch = math.floor(math.min(avail_w, avail_h) / n)
  local gap   = math.max(2, math.floor(pitch * 0.03))
  local cell  = pitch - gap
  local ruler = L.ruler
  local grid_w = n * pitch - gap
  local grid_h = n * pitch - gap
  local gx = L.board.x + ruler + math.floor((avail_w - grid_w) / 2)
  local gy = L.board.y + ruler + math.floor((avail_h - grid_h) / 2)
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-12 **【已删除】行标 / 列标（`ruler` 控件那套）** ✗✓（用户要求 ✓）
  --
  --   ★ 删掉的三处 ✓：
  --     ① 容器 `ruler`（`push({ id = "ruler" … })`）
  --     ② 列标 `ruler.c.1..cols`（`text = "C"..c`）
  --     ③ 行标 `ruler.r.1..rows`（`text = "R"..r`）
  --   ★ 为什么删 ✓：用户 2026-10-12 定案「**ruler 功能废弃**」✓
  --     ★ 而且它**从来就是哑的** ✗（本文件与 `main.lua` 的注释都记着：
  --       `apply_ruler_layout` **只对齐不创建** ⇒ `find("ruler")` 恒 nil ⇒ 一直 `return 0` ✓）
  --     ⇒ ★ 之前那几轮"抢救"（`ensure_ruler` 用模板引用控件把标签建出来）**一并删除** ✓
  --   ⚠️ **不要**把 `L.ruler` 常量一起删 ✗ —— 它是**边框厚度**，格子几何靠它 ✓（见上）
  --   ⚠️ 网格坐标 `gx` / `gy` 里那个 `ruler` 也只是**边框内缩** ✓ 与标签无关 ✓ 保留 ✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★★ 2026-09-30：**房间名标签**（参考《派蒙的执律庭实习》：每个房间在右下角写房间名，
  --   如 餐厅/厨房/前院/门廊/卧室）。
  --
  --   ⚠️ 关卡数据里**没有房间名**（`rooms` 字段都不存在，房间是从 `walls` 推导的）。
  --     所以这里**不编名字**，而是两级：
  --       · 关卡里写了 `room_names = { "餐厅", "厨房", ... }` ⇒ 用真名
  --       · 没写 ⇒ 显示中性的「区域 1 / 区域 2 …」（位置先占住，名字随时能补）
  --     等你在关卡里填上 `room_names`，这里**不用改一行代码**就会显示真名。
  --
  --   标签放在**房间外框的右下角那一格**里（和参考图的位置一致）。
  if n > 0 then
    -- ⚠️ 这里**不能用 `list`** —— 那是下面"选关界面"分支里的局部变量，
    --   本段在它**之前**执行（我第一版就踩了：`attempt to get length of a nil value`）。
    --   自己从 `self.opts.levels` 取一份。
    local lv_list = {}
    local opt_lv = self.opts.levels
    if type(opt_lv) == "function" then lv_list = opt_lv() or {}
    elseif type(opt_lv) == "table" then lv_list = opt_lv end
    local cur = nil
    local want = tostring(self.opts.current_level or "")
    for i = 1, #lv_list do
      if tostring(lv_list[i].id) == want then cur = lv_list[i] break end
    end
    -- ★ 2026-10-18（优化组 · C 类清理）：**房间名标签 `room.label.1..8` 整段删除** ✗✓
    --   判据：它们挂在 `board` 容器下，而 `board` 在存档里根本不存在 ⇒ 8 个标签**从来没建过**
    --     （`check_names` 里是 8 个 🔴 真缺）；`room_boxes` / `room_names` 仍由关卡数据提供，
    --     以后要做「房间名」时**另开新控件位**，别再复活 `room.label.*` 这套名字 ✓
  end   -- ★ 2026-10-18（**补回**）：这一行收的是上面 `if n > 0 then` ——
        --   它原来在 `room.label` 那段末尾，整段删除时被一起吃掉 ⇒ `loadfile` 当场报
        --   `'end' expected (to close 'function' at line 2109) near <eof>`、块深度不平衡 1 ✓

  -- ★ 2026-10-12 **行标尺（`ruler.r.*`）已按用户要求删除** ✗✓（连同容器与列标 ✓）
  --   理由见上面【已删除】那段长注释 ✓ —— ★ 而且它从来就是哑的（`apply_ruler_layout` 只对齐不创建 ✓）
  --
  -- ★★★★★★★★ 2026-10-17 **线索位置提示：选中第几张卡，就亮第几条线索允许的格** ✗✓✓
  --
  --   ★ 判据**只有一个**：`focused_clue` ✓（= 选中那个人配在第几行 ✓ 见 `_sync_clue_focus`）
  --     ⇒ 真机「点线索卡」与模拟器「点卡上的人像」两条输入**都汇到这里** ✓
  --       ⇒ ★ 不需要第二份"选中了哪张卡"的状态 ✓（本项目为"两份状态必然漂移"栽过多次 ✓）
  --   ★ 格子集合现算 ✓：`core:clue_hint(focused_clue)` 只读关卡静态数据（家具/墙/门）
  --     ⇒ **与当前摆位无关** ✓ ⇒ 玩家摆了几个棋子都不会改变提示 ✓
  --   ★ 刷新成本 ✓：`build_layout` 只在 `dirty` 时跑 ✓；属性账本按值去重 ✓
  --     ⇒ 稳态每帧零写入 ✓（与"房间色"同一条路 ✓）
  --   ★★ 2026-10-17 **显示方式改了** ✗✓：不再染格子颜色，而是开/关模板里的
  --     `cell.R.C` → `content` → **`hint`** 子控件（颜色在编辑器里，见上面那段注释 ✓）
  --     ⇒ 每格都发 `hint = true/false` ✓ 取消选中 / 换卡时上一批自然关掉 ✓
  local hint_set = nil
  do
    local fci = self.focused_clue
    -- ★★ 2026-10-18 **通用线索优先** ✓（点它时 `general_focus` 为真）
    --   它没有"卡号" ⇒ 不能走 `focused_clue`（那会把高亮给到第 1 张真卡 a ✗）
    -- ★★★ 2026-10-18 **只认卡号，不认标志** ✗✓（用户实测：点卡 a 亮的是通用线索那 5 格）
    --   原因：`general_focus` 标志残留 ⇒ 真卡也被当成通用线索 ✗
    --   ⇒ 判据改成**卡号越界**：通用卡号 = 卡片数 + 1（点击时设的）⇒ 不会和任何真卡撞号 ✓
    if fci ~= nil and fci > 0 and self.core ~= nil
       and (self.core.clues == nil or fci > #self.core.clues) then
      -- ★★ pcall + **一次性诊断**：能证明这条分支到底走没走到、提示集有几格 ✓
      pcall(function()
        local _gh = self.core:clue_hint_general(1)
        local _cnt = 0
        if _gh ~= nil and _gh.set ~= nil then for _ in pairs(_gh.set) do _cnt = _cnt + 1 end end
        if _cnt > 0 then hint_set = _gh.set end
      end)
      fci = nil
    end
    -- ★★ 2026-10-18 **卡号 0 = 通用线索** ✓（同一份 `focused_clue`，不另开旁路开关）
    if fci == 0 and self.core ~= nil and type(self.core.clue_hint_general) == "function" then
      -- ★★ 2026-10-18 **必须 pcall** ✗：这里抛错会把整个 build_layout 中断 ⇒
      --   卡片和棋盘**都不重绘** ⇒ 用户看到"卡片没有视觉变化" ✓ 正是这个形状
      pcall(function()
        local _g0 = self.core:clue_hint_general(1)   -- 卡号 0 = 通用线索
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
      -- ★★★★★★ 2026-10-11 **这一格最终下发哪个 `note` 值 —— 计算并如实打一行** ✗✓✓
      --
      --   ★ 为什么必须加 ✗：★ 用户报"修复没生效"✓ 而**设备日志只证明了两件事** ✓：
      --     · ★ 单射在跑 ✓（`写了 4 个槽位` ✓）
      --     · ★ `_row_letter` 在建 ✓（`标记来源记下 … who=B letter=A` ✓）
      --   ⇒ ★★ 中间【一格都没打】**"格子最后收到哪个值"** ✗
      --     ⇒ ★ 分不清三种情况 ✓：★ ① 值对但引擎没画 ✗ ★ ② 值错 ✗ ★ ③ 落了兜底 ✗
      --   ★ 这一行把三者一次分开 ✓：`cell(r,c)` ＋ `suspect` ＋ `src=letter/兜底` ＋ 值 ✓
      --   ★ 只在**有人的格子**打 ✓ ＋ ★ 每次填充最多 8 行 ✓（★ 稳态不刷屏 ✓）
      --   ⚠️ ★ 必须放在**这里**（循环体顶部 ✓）—— ★ 表构造器里不能写 `local` ✗
      --     （★ 我第一版放进 `push({…})` 里面 ✓ 症状：`unexpected symbol near 'local'` ✓）
      local _note_val = nil
      local _note_src = nil
      local _resolve = Controller.letter_of
      -- ★★★★★★★★ 2026-10-11 **放头像时【不再下发 `letter`】** ✗✓✓（★ 用户明确要求 ✓）
      --
      --   ★★★ 用户原话 ✓：「★ **放置头像的时候把 `letter` 也放下了，这个不用**」✓✓
      --   ★★ 也就是：★ **放人 = 只出头像 ✓ 不出字母** ✓✓
      --     ★ 格子上那三个子控件是 `face` / `note` / `x` ✓ ⇒ ★ **放人只动 `face`** ✓
      --   ★ 历史沿革（★ 说清楚，免得下一个人又把它加回来 ✗）：
      --     ★ 2026-10-10 用户要的是「★ **让 `letter` 取代铅笔笔记**」✓
      --       ⇒ ★ 那时把"放人也显示 `letter`"当成了同一件事 ✓
      --     ★★ 而 2026-10-11 的真机反馈把两件事**分开了** ✓：
      --       ★ **铅笔标记** ⇒ 显示那一行的 `letter` ✓（★ 要 ✓）
      --       ★ **正式放人** ⇒ **只要头像** ✗（★ 不要字母 ✓）
      --   ★★ 所以这一支**整段删掉** ✗ —— ★ 只留"打标记"那一条 ✓
      --     ★ 机制 ✓：★ `do_place` 本来就会把该格 `notes` 清空 ✓
      --       ⇒ ★ 下面 `mark_list_of` 拿到空集合 ⇒ 返 nil ⇒ ★ 下发 `false` ⇒
      --         ★ 适配器 `SetVisible(false)` ⇒ ★ **note 控件不显示** ✓✓
      --     ★（★ 这就是要的效果 ✓ —— ★ 不需要在这里额外写什么 ✓）
      --
      --   ⚠️ 别把 `letter_of` 一起删了 ✗：★ **打标记那条路还要它** ✓（见下面 ✓）
      if _note_val == nil then
        -- ★★★★★★ 2026-10-11 **标记列表走 `letter`** ✗✓✓（★ 这就是"取代铅笔笔记" ✓）
        --   ★ `core.notes[r][c]` 是 **`{ [人物id]=true }`** ✓ ⇒ ★ 这里把 id **换成 `letter`** ✓
        --     ★ 没配 `letter` 的人 ⇒ `mark_list_of` 内部**回退 id** ✓（★ 不会突然空白 ✓）
        _note_val = mark_list_of((self.core and self.core.notes and self.core.notes[r]
          and self.core.notes[r][c]) or cd.notes, vm, _resolve)
        if _note_val ~= nil then _note_src = "标记(letter)" end
      end
      -- ★★★★★★ 2026-10-11 **探针要"每次棋盘变化"重新武装** ✗✓✓
      --
      --   ★ 为什么 ✗：★ 第一版是"每个控制器实例最多 12 行" ✓
      --     ⇒ ★★ **开局那一刻就把额度用光** ✗ ⇒ ★ **之后落子一行都不打** ✓✓
      --     　（★ 这正是"我只看到开局、看不到落子"的机制 ✓）
      --   ★ 修法 ✓：★ 用"**有标记的格子数**"当签名 ✓ —— ★ 一变就**重新计数** ✓
      --     ⇒ ★ 落子/拿起/擦笔记都会重新开一段 ✓ ＋ ★ 每段仍有 12 行上限 ✓（★ 不刷屏 ✓）
      local _cnt = (cd.suspect ~= nil and 1 or 0) + (_note_val ~= nil and 1 or 0)
      self._note_src_sum = (self._note_src_sum or 0) + _cnt
      if (cd.suspect ~= nil or _note_val ~= nil) and (self._note_src_log or 0) < 12 and print then
        self._note_src_log = (self._note_src_log or 0) + 1
        local _shown = ""
        if type(_note_val) == "table" then _shown = table.concat(_note_val, " ")
        elseif _note_val ~= nil then _shown = tostring(_note_val) end
        -- ★★★ 2026-10-11 **三种情况给三种话** ✗✓✓（★ 一次就分得清 ✓）
        --   ★ 为什么必须分开 ✗：★ v168 那版**只在"有棋子"时打** ✓
        --     ⇒ ★ 用户那局【一行都没打】✓ ⇒ ★ 我只能推断"没有棋子" ✗ 不能确认 ✓
        --   ⇒ ★ 现在：★ ① 有棋子 ⇒ 打 ✓ ② 空格子但有标记 ⇒ **也打** ✓
        --     ⇒ ★★ 于是"格子上那个 `bav` 到底是棋子还是标记"**当场分开** ✓✓
        --   ★★★★★★ 2026-10-11 **措辞更正** ✗✓（★ 因为 `letter` 已经【取代】了铅笔笔记 ✓）
        --     ★ 旧措辞写着"这是旧笔记 ✗ **不是** letter 标记"✓
        --       ⇒ ★ **现在不对了** ✗ —— ★ 标记**就是**走 `letter` 显示的 ✓
        --       ⇒ ★★ 照旧写下去会**把人误导回"两套东西"** ✗✓（★ 这正是我前三轮犯的错 ✓）
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
      -- 键盘光标（PC）：只在真的用过方向键之后才高亮，纯鼠标玩家看不到它
      if self.kb_active and self.kb ~= nil and self.kb.r == r and self.kb.c == c then
        style = "cell.cursor"
      end
      push({
        id = self:cell_id(r, c),
        kind = "button",
        -- ★★★★★ 2026-10-06 **格子的父级从 `board` 改成 `stage`** ✗✓ —— 与真机一致 ✓
        --
        --   为什么（★ 模拟器 play 日志给的铁证 ✓）：
        --     · 模拟器：★「**stage 树上实际有 0 个子控件**」✗
        --       ⇒ ★ 因为计划把格子挂在 **`board`** 下 ✗ ⇒ 脚本按 `stage` 找 ⇒ **找不到** ✓
        --     · 真机：★「stage 树上实际有 **27** 个子控件」✓
        --       ⇒ ★ **真机里格子就是挂在 `stage` 下的** ✓
        --     · 且两边日志都说：★「`board` → **找不到控件**」✗
        --       ⇒ ★★ 即：★ **`board` 在真机上根本不存在** ✗ —— ★ 它只是计划里的历史层 ✓
        --   ⇒ ★★ 所以这一处**不是模拟器的毛病** ✗ —— ★ 是**计划的父子结构与真机不一致** ✓✓
        --     ★ 审计要模拟真机 ✓ ⇒ ★ 必须对齐真机 ✓（★ 而不是迁就模拟器 ✓）
        --   ⚠️ 同一个 `board` 还挂着 `ruler` / `room.label.*` ✗ ——
        --      ★ 它们同样在真机上取不到父级 ✓ 但那是**另一件事** ✗ ⇒ 本轮不动 ✓
        parent = "stage",
        rect = { x = gx + (c - 1) * (cell + gap), y = gy + (r - 1) * (cell + gap), w = cell, h = cell },
        style = style,
        -- ★★★★★ 2026-10-06 **格子的可见性由【规划】统一给** ✗✓ —— 用户说的"合并成一套" ✓
        --
        --   ★ "为什么只有第一关出问题"的答案 ✓（真机日志早就写着 ✓）：
        --     · 第一关：★「本次新建 **25** 个」✗ ← ★ 格子是【开局那一刻】建的 ✓
        --     · 第二关：★「本次新建 **0** 个」✓  ← ★ 复用已存在的 ✓
        --     ⇒ ★ 开局 `screen = "home"` ✗ ⇒ 屏幕层把 `cell.*` 藏掉 ✗
        --       ⇒ ★★ 第一关的格子【一出生就是 hidden】✗ 而屏幕层是**单向**的 ✗
        --          ⇒ **永无恢复** ✓✓（墙/门/底图全灭 ✓）
        --     ⇒ ★ 其它关的格子是【关卡内】建的 ✓ ⇒ 从没被藏过 ✓
        --       ⇒ ★★ 看起来"只有第一关坏"✗ —— 其实是**建格时机不同** ✓
        --     ★ 用户原话：「第一关的棋盘是项目最初的造物」✓
        --       「把第一关的显隐设置与其它关卡合并成一套」✓ —— ★ 判断正确 ✓
        --
        --   ⇒ ★★ 在这里显式给 `visible`：★ 规划**每一次产出都带上它** ✓
        --     · 关卡内（`screen == nil`）⇒ true ✓  ·  主页/选关 ⇒ false ✓
        --     ⇒ ★★★ **所有关卡、所有时机走同一条** ✓✓ —— 这就是"一套" ✓
        --   ⚠️ 不放在屏幕层 ✗（上次那样做过、失败了 ✗）—— 那是**单向**的 ✗
        --     ★ 而规划每一帧都重算 ✓ ⇒ 它才是**双向**且**唯一**的权威 ✓✓
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        -- ★★ 性能待办 ★ 标签 **PERF-2**（★ 2026-10-06 标记 ✓ **先不动** ✗ 等框架稳定再回来 ✓）
        --
        --   ★ 这是**每帧下发**给 25 个格子的那个 `visible` ✓
        --     （★ `layout_plan` 每帧重算 ✓ ⇒ 这一行每帧对 25 个格子各走一次属性下发 ✓）
        --   ★ **字段位置**：★ 就是下面这行 `visible = (self.screen == nil),` ✓
        --     ★ 同类还有 `clues.bg` 的 ★ **L2065** `visible = (self.screen == nil) })` ✓
        --   ★ **为什么归规划管** ✗：★ 屏幕层是**单向**的 ✗（★ 只藏不显 ✓ 上次那样做过、失败了 ✓）
        --     ★ 而规划每帧重算 ⇒ ★ 它是**双向且唯一**的权威 ✓ 见 L2547~2550 ✓
        --   ⇒ ★★ **要省成本，正确顺序** ✓：★ 先确认屏幕层的**对称性** ✓
        --     ★ 再把"每帧下发"改成"**状态变了才下发**"✗ —— ★ **不能直接删** ✓
        --   ★ 配套的那个是 ★ **PERF-1**（`engine_adapter_qianxing.lua` 的每帧重放 ✓）
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        visible = (self.screen == nil),
        -- ★★★★★ 2026-10-05 **格子不再推 `text`**（这一轮每帧成本第 (4) 条）。
        --
        --   真机证据（用户日志里「格子里的子控件清单」那句，**原话**）：
        --       cell.1.1 … 没有配的：**text** obj
        --   —— 格子上**根本没有文字子控件**（`obj` 也没有；`obj` 那一条已经由适配层
        --      按"没有物件就藏起来"处理掉了，是另一件事）。
        --
        --   而适配层 `set_property(id, "text", …)` 的三条路
        --   （① `label` 子控件 ② 控件自己就是文字控件 ③ 老的 `text` 子控件）
        --   **在格子上一条都走不通** ⇒ 必然 `return false`
        --   ⇒ `render` 把它当"这次没送到" ⇒ 按补发额度 `PROP_RETRY`(=3) 重试
        --   ⇒ **每关开头白跑 25 次 `find` + 75 次 `set_property`**
        --      （`tests/grid_cost.lua` 口径 [I] 实测：75 次失败写入 / 25 个格子 × 3 次），
        --      并且把「属性补发…已停止补发」的**前 5 条日志位置全部占掉** ——
        --      真正需要看的那几条（哪些控件本关没建）就此被挤出去。
        --
        --   ⇒ 不再推。格子上要显示的东西本来就靠 `image`（头像）/ `face` / `note` / `x`
        --     四样；**人名走的是线索卡**，从来没有靠过格子文字。
        --
        --   ⚠️ **将来若真的给格子配了文字子控件**：在 `entry_client_script.lua` 的
        --      `cfg.cells` 里加一行 `push_text = true` 即可恢复（`main.lua` 会把它转成
        --      `opts.push_cell_text`）—— **不用改代码**。
        --   ⚠️ **不要**改成"让适配层把这种情况判成 definitive miss、不再重发"：
        --      「`label` 子控件晚一步才进树」是真实存在的（见 `main.lua` 门控②那段
        --      以及适配层 `set_property` 的 text 分支注释），首帧"三条路都不通"与
        --      "这个控件永远没有文字"在**适配层看来长得一模一样** ⇒ 在那边一刀切
        --      会把已经修好的"第一次进关按钮没字"又放回来。
        text = (self.opts.push_cell_text == true and (cd.name or "")) or nil,
        -- ⚠️ 这里**只能传图片 ID（整数）**，不能传名字。
        --
        -- 真机 16:07 日志报过：`SetImage 失败：bad argument #3 to 'SetImage'
        -- (integer expected, got string)`。根因就是这行原来写的是
        --     `… portrait_of(vm, cd.suspect) or cd.object or nil`
        -- 而 `cd.object` 是**家具/物体的名字字符串**（例如「收银台」）。
        -- 当角色没配 `portrait` 时，`and/or` 表达式就掉到 `cd.object` 上，
        -- 于是名字被当成图片 ID 传进了 SetImage。
        --
        -- 现在只传 `portrait`。
        -- ★ 2026-09-26 起 `portrait` 支持**调色板素材名**（字符串）：
        --   例如 `portrait = "portrait.A"`，适配层会用调色板里的 source+id 去 SetImage。
        --   整数 ID 依然兼容。调色板见 engine_adapter_qianxing.lua 的 read_palette。
        -- ⚠️ 用 `false` 而不是 nil 当"这格没有人"：
        --   渲染循环是 `for k, v in pairs(n)` —— **Lua 里 `image = nil` 等于"这个键不存在"**，
        --   于是"人走了的格子"**永远不会下发 image** ⇒ 旧格的头像**永远不清**。
        --   这就是用户报的「换位后头像卡残留」。
        --   （和 `obj` 白块是**同一个 bug 形状** —— 我在同一个坑里摔了两次。）
        image = cd.suspect and Controller.portrait_of(vm, cd.suspect) or false,
        -- ★ 见 `note_list_of` 那段：适配器要**数组** ✓ 核心给的是**集合** ✗（不转 = 永远空串 = 永不显示）
        -- ★★★★★ 2026-10-07 **改用核心那份笔记表** ✗✓（真机探针：写入通道全通、但写进去的是 `1` ✗）
        --   ★ 探针铁证 ✓：★ `诊断NOTECH：写笔记通道=text  文本=1` ✓
        --     ★ `诊断NOTEV：回读text=1  visible=true  fontSize=36  fontColor=4278190080`（黑 ✓）
        --   ⇒ ★ **显示通路完全正常** ✓ ⇒ ★ 唯一的问题是**取的源表错了** ✓✓
        --   ★ 两份表的键不同 ✓：
        --     · 核心 `core.notes[r][c]` = ★ **`{ [人物id]=true }`** ⇒ 键**就是徽章字母** ✓（探针：`{V}` ✓）
        --     · 视图 `cd.notes`        = ★ 键是**数字** ✗ ⇒ `tostring(k)` 得到 `"1"` ✓（正是看到的那个 1 ✓）
        --   ⇒ ★ **以核心为准** ✓（视图那份只当兜底 ✓）
        -- ★★★★★ 2026-10-07 **笔记清空时要下发 `false`（不是 nil）** ✗✓ —— "清掉了但没重画" ✓
        --   ★ 元凶 ✓：★ `note_list_of` 在"没有笔记"时返回 **nil** ✓
        --     ⇒ ★ Lua 里 `notes = nil` 等于**这个键不存在** ✓ ⇒ **适配器永远收不到"该清空"** ✗
        --       ⇒ ★ 屏幕上的字母**留着不动** ✓ —— ★ 于是"正式放置清了笔记"你也看不出来 ✓✓
        --   ★ 项目自己早就吃过同一个坑 ✓（`image` 那条注释写着 ✓ `ui_controller.lua:2677~2680` ✓：
        --     「★ 用 `false` 而不是 nil 当"这格没有人"……否则**旧格的头像永远不清**」✓）
        --   ⇒ ★ 这里照办 ✓：★ 没有笔记时下发 **`false`** ✓ ⇒ 适配器 `txt = ""` ⇒ `SetVisible(false)` ✓
        -- ★★★★★★ 2026-10-11 **标记 = 那一行的 `letter`（★ 这就是"取代铅笔笔记" ✓）** ✗✓✓
        --   ★★★ 用户更正 ✓：「**我要的就是铅笔笔记用 `letter` 的标记** ✓
        --     ★ **不是增加一个 `letter` 功能** ✗ ★★ **而是让 `letter` 取代铅笔笔记的功能** ✓」
        --   ⇒ ★★ 所以这里**不是"多一条路"** ✗ —— ★ **是把笔记那条路的【显示】换掉** ✓：
        --     ★ 数据照旧是 `{ [人物id]=true }` ✓（★ 打标记的交互一个字没动 ✓）
        --     ★ **下发的字**改由 `letter_of(人物)` 决定 ✓（★ 在循环顶部算好 `_note_val` ✓）
        --   ★ 优先级（★ 两条路在显示上**自动统一** ✓）：
        --     ★ ① 这格有棋子 ⇒ **那个人的 `letter`** ✓（★ `do_place` 会清掉该格笔记 ✓）
        --     ★ ② 没有棋子但有标记 ⇒ **被标记那几个人各自的 `letter`** ✓
        --     ★ ③ 都没有 ⇒ `false` ✓（★ 明确"要清空" ✓ 不是 nil ✗ —— 见上面那段注释 ✓）
        --   ★ 没配 `letter` 的人 ⇒ `mark_list_of` 内部**回退人物 id** ✓（★ 与你"后面补"一致 ✓）
        notes = _note_val or false,
        room = cd.room,
        -- ★★ 2026-09-28 新增：**显式告诉适配层"这格有没有物件"**。
        --
        -- 为什么必须传：模板里有个 `obj` 子控件，是留给"物件图标"（书桌/地毯）的，
        --   而且 `layer_order` 故意把它排在 `face` **之上**。
        --   但我当初生成它时用的是**白色占位图**（106053），**而且没有任何代码去关它** ——
        --   于是它永远是"一块白板压在头像上"。
        --   空格看不出来（`face` 本来就是白图），**一放人就变成用户报的
        --   「人物头像上有异常遮挡」**（截图里 C3/R1、C4/R2、C4/R3 那三块白方块）。
        --   ⇒ 每格显式声明 `object`（没有物件就是 nil），适配层据此开关 `obj` 的显隐。
        -- ★★★ 2026-09-30：**物件传的是"素材键"，不是显示名**（为 ⑤ 家具图标铺路）。
        --
        --   关卡里的物件是**中文名做键**的：
        --       objects = { ["书架"] = { cells = {...}, kind = "shelf" }, ... }
        --   而适配层拿这个名字去 `assets` 调色板里查素材 ⇒ 素材名会变成 `obj.书架`。
        --   中文素材名不是不行，但**不好管理**（改名、跨语言、和图集对不上）。
        --   ⇒ 规则：物件定义里写了 `kind` 就用 `obj.<kind>`（ASCII 稳定键），
        --     没写就退回中文名（**不破坏现有数据** —— 老关卡一个字都不用改）。
        --
        --   ⚠️ 没物件时必须是 `false` 而不是 nil：
        --     渲染循环是 `for k, v in pairs(n)` —— Lua 里 `object = nil` 等于"这个键不存在"，
        --     于是没有物件的格子**永远不会下发 object** ⇒ `obj` 白块永远不被隐藏
        --     （这正是用户报的「人物头像上有异常遮挡」，我第一次没修掉）。
        -- ★★★★★★★★ 2026-10-22（v302，第四轮）家具改走**外部工具算出的图元拼法** ✗✓
        --
        --   历史：v300 是"一格 6 层"，v301 是"一格 12 层"，都被用户打回"没达到参考效果"。
        --   用户指定路线：「用外部图片网站把参考拼出来，再按结果文件拆解出正确拼法导入存档」
        --   ⇒ 现在 `furn` 只留给**地毯**（平面图形，3 层矩形，可站人）；
        --      其余家具走 `furn_art`：每件 148~200 条图元（工具结果），由适配层**运行时实例化**图片控件。
        -- ★ v307：烘焙模式下**旧家具图层要关掉**（否则两代产物叠在一起：旧椅子压在静态烘焙的椅子下面）。
        --   只保留"本来就是手搭这一代"的三类：桌子 / 书架 / 地毯。
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
        -- 图元拼法（只下发在**锚点格**上；记录已按整件中心→锚点格中心换算过）
        furn_art = (furn_recs and furn_recs[r] and furn_recs[r][c]) or false,
        -- ★★★★★★★★ 2026-10-22（v310，第十三轮）**模板化家具** ✗✓
        --   用户：「采用模板来手搭构建，模板里放多少层都可以（一个模板引用控件只算一层），
        --   然后像 cell 一样把模板创建出来」。
        --   锚点格下发模板键（如 "furn.chair" / "furn.table.h2"）与跨格数；适配层据此
        --   `InstantiateClientUIControl(模板源, fart.furn)` 并设尺寸/位置 ⇒ `furn` 手搭层可退掉。
        furn_tpl = (furn_tpl and furn_tpl[r] and furn_tpl[r][c]) or false,
        furn_span = (furn_span and furn_span[r] and furn_span[r][c]) or false,
        furn_offset = (furn_offset and furn_offset[r] and furn_offset[r][c]) or false,
        -- ★ 每格四边的墙 / 门：数据来自 core 的 `view()`（{up,down,left,right} 布尔表），
        --   适配层靠模板里固定的 `wall.*` / `door.*` 子控件 SetVisible 开关来实现 ——
        --   **不需要为每种墙型做模板**。
        walls = cd.walls,
        doors = cd.doors,
        -- ★ 房间染色：`imageColor` 是**读写**字段，所以"同一张底图 + 不同颜色区分房间"
        --   是零额外素材的做法。颜色表在下面 ROOM_COLORS。
        --
        -- ★★★★★★★★ 2026-10-16 **有棋子时不下发房间色** ✗✓✓（★ 用户报 ✓：
        --   「**棋盘染色把放置的头像也染色了，有没有办法能让头像不受底色影响**」✓）
        --
        --   ★ 为什么会被染 ✗：★ 头像与房间色**落在同一个控件上** ✓ ——
        --     · 头像：`image = portrait` ⇒ 适配层把图设到格子的 **`face`** ✓
        --     · 房间色：`tint = room_color` ⇒ 适配层 `local target = self:sub(id, "face")` ✓
        --       ⇒ ★ **同一个 `face`** ✗ ⇒ ★ `imageColor` 是**乘算** ⇒ 头像被乘上底色 ✓✓
        --   ⇒ 当时的权宜修法：**有棋子的格子，房间色下发白色**（= 不染色 ✓）✓
        --
        -- ★★★★★★★★ 2026-10-20（v283）**权宜修法撤掉：头像有了自己的层** ✗✓✓
        --   用户原话：「现在**家具图层会盖在放置的头像上**，把这个问题解决」✓
        --   ⇒ 模板补了一层 `portrait`（层序：face → hint → obj → **portrait** → wall …）✓
        --     · 头像走 `portrait`（在家具之上、墙之下）✓ ⇒ 不再和房间色抢同一个控件 ✓
        --     · 房间色**照旧落在 face**✓ ⇒ **有棋子的格子也保留房间色** ✓（以前会被白色顶掉 ✓）
        --   ⇒ 所以这里**不再按"有没有棋子"改颜色**，一律下发房间色 ✓
        --     ⚠️ 别把这一行改回去 —— 头像已经不画在 face 上了，白色只会让格子白一块 ✓
        -- ★★★★★★★★ 2026-10-17 **提示层：只发一个布尔** ✗✓（★ 见上面 `hint_set` 那段 ✓）
        --   ★ 用户已经在模板里做好了 `hint` 子控件（`content` 下，135×135，颜色已调好）✓
        --     ⇒ 脚本**只负责显示 / 隐藏** ✓ 颜色一个字都不写 ✓（`tint` 回到只管房间色 ✓）
        tint = Controller.room_color(cd.room),
        -- ★ 每格都发（true/false）⇒ 取消选中 / 换卡时自然把上一批关掉 ✓（账本按值去重 ✓）
      hint = (hint_set ~= nil and hint_set[r .. ":" .. c] == true),
        -- ★★★★★★★★ 2026-10-17 **格子边长（画布）直接告诉适配层** ✗✓
        --   用途：把"铺满型"子控件（`face` / `hint` / `obj`）钉成**和格子一样大**
        --   ★ 为什么由界面层给：`build_layout` 本来就算出了 `cell`（设计空间）✓
        --     比"让适配层去读控件尺寸"可靠得多 —— 读不到就整段静默跳过 ⇒ 溢出 ✓
        fit = math.floor(cell * M.SCALE + 0.5),
        occupiable = cd.occupiable,
        x_mark = cd.x,
        enabled = true,   -- 不可站人的格子也要能点（用于打 X / 提示原因）
        event = { action = "click", r = r, c = c },
      })
    end
  end

  -- ★★★★★★★★ 2026-10-22（v300）**房间名标签**（`labels` 容器下的 `label.1..7`）✗✓
  --
  --   原作每个房间角落写着房间名（BEDROOM/KITCHEN…），这是"平面图感"的一半。
  --   项目早期有一版 `room.label.*`，但挂在一个**存档里根本不存在的 `board`** 容器下 ⇒ 从来没显示过，
  --   v269 整段删掉时留了话："以后要做房间名，另开新控件位，别复活 room.label.*"。
  --   本版就按那句话另开：容器 `labels`（父 `root`、排在 `stage` 之后）+ 文本框 `label.1..7`。
  --
  --   摆位规则：按房间外框，**底边中点**、再往里收 0.38 格；
  --   名字来自关卡数据 `room_names = { "大屋", "内室", … }`（没填就显示"区域 N"）。
  --   ⚠️ 位置必须由脚本算（`pos_runtime = true`），否则 8 个标签会在编辑器里叠成一处。
  --   ⚠️ 但**节点每屏都要 push**（哪怕 visible=false）—— 否则离开关卡时没人把标签关掉。
  do
    -- ★ 先把 `labels` 容器本身写进计划：**位置换算必须知道父级中心**
    --   （适配层算的是 "节点中心 − 规划父级中心"；父级不在计划里就只能当 (0,0)，标签会整体偏移）。
    --   它的 rect 和 `root` 那条一样（整画布），因为存档里那个容器是"锚点居中、画布中心"的。
    -- ★ v306：**容器本身也要由脚本摆正** —— 存档里它是"700×700 @(0,0)"，那个 (0,0) 是画布
    --   左下角而不是画布中心 ⇒ 子控件会整体偏到屏幕外（真机上"房间名看不见"就是这个原因）。
    --   ⇒ 用 `pos_runtime` 强制把容器撑成**整画布、居中**（只有 1 个控件，代价极小）。
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
      -- ⚠️ 每个节点**必须有 rect**：布局计划会对每个节点做 `to_canvas(n.rect)`
      --   （没有 rect 就 "attempt to index a nil value" —— 本函数第一版就是这么崩的）。
      local rx, ry, rw, rh = 0, 0, 1, 1
      if lb ~= nil then
        -- 落在 `furn_art` 选好的那一格中心（优先"最后一行没有家具的格"），
        -- 这样字不会压在家具图案上（见 lua/furn_art.lua 的 pick_label_cell）。
        local ac = lb.cell or { r = lb.box.r2, c = lb.box.c1 }
        rw, rh = math.floor(cell * 2.2), math.floor(cell * 0.40)
        rx = math.floor(gx + (ac.c - 1) * pitch + cell * 0.5 - rw * 0.5)
        ry = math.floor(gy + (ac.r - 1) * pitch + cell * 0.5 - rh * 0.5)
      end
      node.rect = { x = rx, y = ry, w = rw, h = rh }
      push(node)
    end
  end

  -- ===== 右侧信息栏 =====
  push({ id = "right", kind = "container", parent = "root", rect = rect_of(L.right), style = "panel.right" })
  -- ⚠️ `hud.progress` **不在这里** —— 它已经挪到右下角和放大镜做伴了
  --   （见文件上半部分的"按参考图重排顶栏与右下角"）。
  --   我第一版忘了删这一份，于是**同名控件建了两个** —— 正是"同名两处必然漂移"的老毛病。
  -- ★★★★★ 2026-10-02 **按用户定稿删除**（参考图里没提到的按键全删）：
  --     `hud.score`（位置正确 N/M）、`hud.violations`（区域推断 + 违规）、
  --     `hud.share`（分享码）、`hud.toast`（提示条）—— 全部**不再 push**。
  --   原来那段还算了 `vm.structure`（区域推断文案），一并删掉 ——
  --   它是给 `hud.violations` 用的，没有控件就不必算。
  --   保留的右栏内容只有：`hud.progress`（右下角，与放大镜同排）——见上面那段。
  -- 顶部放不下的次级操作放这里（1920 内不会溢出）
  local rx = L.right.x + 20
  -- ★★ 2026-09-29：`action.howto` / `action.share` / `action.restart` 三个按钮
  --   **用户已在编辑器里删除** ⇒ 计划里同步移除，否则脚本会去写不存在的控件
  --   （真机日志里 `action.howto` 那几条"读回 nil"就是这么来的）。
  -- ★★★★★★ 2026-10-11 **删掉【右下角分叉出来的 `action.back` 克隆】** ✗✓✓
  --
  --   ★★ 用户报告 ✓（★ 原话 ✓）：「**右下角有一个返回列表按键，它和左上角的返回箭头
  --     功能一模一样，都是连接弹窗，这是重复的东西**」✓✓
  --
  --   ★ 分叉在哪 ✓：★ **同一个 id 被【声明了两次】** ✗
  --     ★ **① `push({ id = "action.back", parent = "topbar", … })`**（★ 上面 L2431 附近 ✓）
  --       ⇒ ★ **真身 ✓ 在【左上】** ✓（★ 与 `hex.back` ↰ 图标同属左上那一组 ✓）
  --     ★★ **② 就是原来这里：`btn("action.back", "right", …)`** ✗
  --       ⇒ ★ **克隆 ✗ 挂在【right】节点 ⇒ 画在右下角** ✓✓
  --
  --   ★★★ 为什么会长出来 ✓（★ 教训 ✓）：
  --     ★ 原来那行注释写着「**`action.back` 保留 —— 它还在你的存档里**」✗
  --     ★★ **它的前提早就变了** ✗ —— ★ 存档里 `action.back` 确实在 ✓，
  --        ★ **但它在 `topbar` 下（★ 已被 ① 声明过 ✓）** ✓
  --     ⇒ ★★★ **⇒ "存档里有 ⇒ 计划里也要声明" 这条推理【不成立】✗**
  --       ★ 因为**声明是【按 id】的 ✗ 不是按节点的** ✓ —— ★ 声明两次 ⇒ 两个节点 ✓✓
  --     ★★ **实测（★ `306.gil` ✓）**：★ 名字含 back 的记录 7 个 ✓，
  --        ★ **`action.back` 只有【1 个】✓ 挂在 `topbar` 下** ✗（★ `right` 下只有 `hud.progress` ✓）
  --        ⇒ ★★★ **⇒ 存档里【没有】克隆 ⇒ 克隆是【规划里多声明的那一次】造出来的** ✓✓
  --
  --   ★ 相关注释也要跟着改 ✓（★ 否则又是一次"注释里的前提悄悄失效"✗）：
  --     ★ 上面那行「`action.back` 保留 —— 它还在你的存档里」已随本次删除一并去掉 ✓
  --     ★★ **保留【左上】那一处声明（★ L2431 附近 ✓）** ✓ —— ★ 那是【唯一】的 `action.back` ✓
  --
  --   ⚠️ ★ 注意 ✓：★ **`main.lua` 里还有对 `action.back` 的引用** ✗
  --     （★ 键盘绑定表 ✓ 与另一处名单 ✓）⇒ ★★ **控件删了之后它们是"写不存在的控件"** ✓
  --     ★★★ **⇒ 待一并清理 ✓（★ 本次先只删克隆 ✓ 因为那是用户点名的那一件事 ✓）**

  -- ★★ 2026-09-29：**整块删掉底部操作条**（`actions` 容器 + 5 个按钮）。
  --
  --   用户在编辑器里把 `actions` 以及 `action.q.*` 全删了（存档记录 231 → 197）。
  --   这五个按钮的功能现在都有更直接的入口：
  --     · 放置工具 / 只写笔记 / 划掉这格 / 橡皮擦
  --         → 由「双击长按=放置、单击=✗、单击已放置格=拿起」承担
  --     · 指认凶手 → 顶部工具条的 `action.submit` 就是它
  --   ⇒ 计划里不再声明，脚本也就不会去写不存在的控件。
  --   （以后要做移动端大按钮，可以从 git 历史取回：提交 2f4b1ea）
  -- ★ 2026-10-18（优化组 · P0）：下面这两行空语句**已删除** ✗✓
  --   原文是 `local _ = L.actions` / `local _ = L.action_btn` —— 纯粹为了"压住未使用变量"
  --   （它俩零读零写，`L.actions` / `L.action_btn` 这两个 LAYOUT 键也没有别的读者）⇒ 死代码 ✓
  --   ⚠️ LAYOUT 里那两个键**暂时不动**：`dump_layout` 等工具按表遍历，删键要另做一轮核对。

  -- ★ 2026-10-18（优化组 · C 类清理）：**教程面板的 6 个控件声明整段删除** ✗✓
  --   （`intro` / `intro.dots` / `intro.title` / `intro.body` / `intro.skip` / `intro.next` 全部）
  --   ⇒ 规划里不再出现这 6 个名字 ⇒ `report_missing` 与 `check_names` 都少 6 项噪声 ✓
  -- ===== 弹窗 =====
  local modal = self.modal
  if modal then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    push({ id = "modal", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })

    -- ★★★★★★ 2026-10-12 **指认面板的渲染分支 —— 已整段删掉** ✗✓✓
    --   （原为这条 if 链的链首；删后 `result` 成为链首 ✓ 内容与原因见下一段的注释 ✓）
    --   ⚠️ 同样**故意不写出那三个事件的字面量** ✗（`check_actions` 连注释一起扫 ✓）

    -- ★★★★★★ 2026-10-12 **这里原来是【指认面板】的渲染分支 —— 已整段删掉** ✗✓
    --
    --   删掉的是：标题（「摆位成立。谁是盗窃者？」/「那同伙是谁？」）＋
    --   一排嫌疑人头像卡（`modal.suspect.<id>`，**靠 `it.portrait` 出图**）＋
    --   「他独自作案（没有同伙）」键 ＋ 「再看看」键 ✓
    --
    --   ★ 为什么连渲染一起删 ✓（而不是只断开入口）：
    --     ① 用户要求「删干净、一行不留」✓；
    --     ② 那排按钮**靠头像图** ✓ 而图在模拟器里是缺的 ⇒ 玩家「**看不到点哪**」✓
    --        ⇒ 留着就是一条永远点不准的路 ✓
    --     ③ 留着还会让 `layout_plan()` 继续把 `modal.suspect.*` 声明成"计划必需" ✓
    --        ⇒ **又是"计划有、存档没有、又没有创建路"** ⇒ 正是本轮刚修掉的那类静默缺失 ✗
    --
    --   ⇒ 所以它现在**从 `if` 变成链首**：`result` 成了这条 if 链的第一个分支 ✓
    if modal.kind == "result" then
      -- ★★★★★★ 2026-10-13 **通关弹窗的【专用底板】**（用户指令 ✓）✗✓✓
      --
      --   ★ 用户原话 ✓：「这样改会让**另一个需要用到 bg 的地方的图也被拉大** ✗，
      --     所以我才让你**新建一个，换一个名字，脚本里的引用也一起换成新名字**」✓✓
      --
      --   ★ 起因 ✓：`modal` 是**五个状态共用**的容器 ✓
      --     （`result` / `exit_menu` / `howto` / `levelselect` / `share` ✓）
      --     而它那个 `bg` 是**共用的底板** ✓ ⇒ 把那个拉大 ⇒ **别的弹窗也跟着变大** ✗
      --
      --   ⇒ 所以 ✓：★ 共用的 `bg` **一个字没动**（633×383 ✓）
      --     ★ 另建 `result.bg`（633×600 ✓ 在存档里是 `modal` 的**第 1 个子控件**
      --       ⇒ **画在最底层** ✓ 垫在四键与三行文字下面 ✓）
      --     ★ 本节点的 `states` **只有 `result`** ✓ ⇒ **只有通关弹窗会显示它** ✓
      --   ★ 图 id 与调色随克隆体一起带过来 ✓（`图=100001`，与共用底板一致 ✓
      --     —— 用户要求「素材引用和调色按这张就行」✓）
      --   ⚠️ 尺寸仍以**存档为准** ✓（`respect_editor_rect = true` ⇒ 脚本不覆盖你在编辑器里调的几何 ✓）
      push({ id = "result.bg", kind = "image", parent = "modal",
             rect = { x = mx, y = my, w = mw, h = mh }, image_id = 100001 })
      local got, total = self.core:score()
      -- ★★★★★★ 2026-10-12 **通关弹窗拉高 ＋ 三行文案上移到四键上方**（用户指令 ✓）✗✓
      --
      --   用户原话 ✓：「**拉高通关弹窗，然后把通关提示文本放到四键上方** ✓
      --     ★ **依次是恭喜破案，凶手分析，用时，分别居中放置** ✓ ★ **恭喜破案字号加大**」✓✓
      --
      --   ★ 版式（**设计空间 1920×1080**；`rect.y` = 从父控件【顶边】往下数 ✓）：
      --     弹窗 h **460 → 720** ✓（画布侧 600 ⇒ 居中后占 y 150..750，画布 900 装得下 ✓）
      --       恭喜破案   y=40   h=90
      --       凶手分析   y=140  h=110
      --       用时       y=262  h=44
      --       四键       y=350 / 446 / 542 / 638（pitch 96 不变 ✓ 638+72=710 ≤ 720 ✓）
      --
      --   ⚠️ **"居中"怎么实现的（如实记 ✗）**：本项目**没有任何对齐 API** ✓
      --     （`Align` / `Alignment` 在 `lua/` 里**零命中** ✓；适配器 `set_property`
      --       也只认 `key == "text"` 这一个文本字段 ✓）
      --     ⇒ 靠「**文本框铺满整幅、左右各留 30**」来居中 ✓
      --       引擎若在框内**默认居中**就正是要的效果 ✓
      --     ★ 若真机上看到**左对齐** ⇒ 需要接一个对齐属性（得先查到它的名字）✓
      --
      --   ⚠️ **"恭喜破案字号加大"【本轮没做】✗（如实说 ✓）**：
      --     文字节点的字号在当前适配器里**没有写入口** ✓ —— `set_property` 不认 fontSize ✓，
      --     而 `main.lua` 那个 `cfg.label_font_size` 只作用于**按钮的 label 子控件** ✓
      --     ⇒ 要做**得先给适配器加一条「独立文字节点的字号」通道** ✓（下一轮 ✓）
      --
      --   第二行 = **凶手分析**：`core` 给的那句正文去掉开头重复的「破案！」✓
      --     （标题已经说「恭喜破案」了，正文再喊一次就重了 ✓）
      local body = modal.message or ""
      if modal.win then body = body:gsub("^破案！", "") end
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 40, w = mw - 60, h = 90 },
             text = modal.win and "恭喜破案" or "没能找齐所有人", style = "modal.title" })
      -- ★★★★★★★★ 2026-10-16 **v252：分析标语挪进 `win` 区（每关一颗 `win.N`）** ✗✓✓
      --   ★ 用户原话 ✓：「★ **每关的通关弹窗的分析标语也像 clue 一样单独设一个对应区域放对应内容，
      --     ★ 父级叫 win，子控件叫 win.i(1,2,3等)**」✓
      --   ★ 为什么必须"每关一颗控件" ✗：★ 文字**存不进 `.gil`** ✓（`_probe_texts.mjs` 实测 ✓）
      --     ⇒ ★ 想让"每关各自一句"在编辑器里能改 ⇒ ★ **一颗控件只能放一句** ✓
      --     ⇒ ★ 所以先把**控件**建够（`win` ＋ `win.1..N` ✓ 已写进交付档 ✓）
      --   ★ 脚本只做两件事 ✓：★ ① **只显示当前那关那一颗** ✓ ② ★ 读不到内容才写兜底 ✓
      --     （"读不到才写"在适配层 ✓ `cfg.text_editor_first` 里已有 `win.1..4` ✓）
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
               visible = (win_idx == i),
               -- ★ 只给"当前那关"那一颗写兜底 ✓ —— ★ 别的关卡的内容**脚本不知道**（★ 那是编辑器的事 ✓）
               text = (win_idx == i) and body or nil,
               style = "modal.body" })
      end
      -- ★ 老的 `modal.body` **不再承担这句话** ✓ —— ★ 留着这条、但**藏起来** ✓
      --   （★ 不藏的话，编辑器里那份旧内容会跟新区域**叠一遍** ✗）
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 140, w = mw - 60, h = 110 },
             visible = false, style = "modal.body" })
      push({ id = "modal.stats", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 262, w = mw - 60, h = 44 },
             text = string.format("用时 %s · 误指认 %d 次 · 位置 %d/%d",
                                  -- ★ 2026-10-12 **定格值优先** ✓（用户：「用时不要走动，取胜利时的时间填入」✓）
                                  --   取不到才退回实时值 ✓（老路径不变 ✓）
                                  self:format_time(self.result_seconds or vm.hud.time),
                                  vm.hud.failed_accusations, got, total),
             style = "muted" })
      -- ★★★★★★ 2026-10-12 **胜利界面改成【四键**，与 `exit_menu` 同款**】** ✗✓✓
      --
      --   ★★ 用户指令 ✓（★ 原话 ✓）：
      --     「★ **和退出箭头一样的弹窗加四键** ✓，★ **只是功能不同** ✓：
      --       ★ **第一个键是下一关**（★ 跳转至下一关 ✓）
      --       ★ **第二个是退出至菜单**（★ 和退出箭头中那个完全一致 ✓）
      --       ★ **第三个是返回首页**（★ 回到开局界面 ✓）
      --       ★ **第四个存档并结算**（★ 尚未完全接线 ✗）」✓✓
      --
      --   ★★★ 四个动作【都已经存在】✓ ⇒ 本段只做【布局 ＋ 接线】✓：
      --     · `next_level`      ⇒ 本文件 L1546（`self.opts.on_next_level` ✓）
      --     · `exit_menu_go`    ⇒ 本文件 L1415 ✓
      --     · `home`            ⇒ 本文件 L1466（`self.screen = "home"; modal = nil` ✓）
      --     · `exit_menu_settle`⇒ 本文件 L1426 ✓（★ 待优化组补内部 ✓）
      --
      --   ★ 几何【直接复用 `exit_menu` 那一套】✓（★ 设计稿 B ✓ 用户 2026-10-09 拍板 ✓）：
      --     ★ 键 374×72 ✓ ★ 水平居中 `kx = mx + (mw−374)/2` ✓
      --     ★ 四个偏移 **50 / 146 / 242 / 338** ✓（★ 面板内上下对称 ✓）
      --   ★★ 面板内上方仍有 `modal.title` / `modal.body` / `modal.stats` ✓
      --     ⇒ ★ **统计那一行就是"结算"的信息** ✓（★ 用时 ／ 误指认 ／ 位置 ✓）
      -- ★★★★★★ 2026-10-12 **四键改用【独立 id 前缀 `result.`】** ✗✓✓
      --
      --   ★★ 起因（模拟器实测 ✓）：这四键原来叫 `modal.next/exit/home/settle` ✗，
      --     而 `exit_menu` 那一屏**也叫 `modal.exit` / `modal.settle`** ——
      --     同一个 id 在**两个状态里各有一套几何**（`y = my+50` vs `y = my+146`）✓
      --     ⇒ `layout_plan()` 是**并集**、只留第一次命中的那一套 ✗
      --     ⇒ 与本项目第 11 号历史 bug「自适应几何在并集里自相矛盾」**同形状** ✓
      --
      --   ★ 另外实测读数（v214，点击结算后）：
      --     `这些控件还没建（共 3 个）：modal.* ×3  modal.exit modal.home modal.settle`
      --     ⇒ 四键里**只有 `modal.next` 真的有控件** ✗ 玩家点不到另外三个 ✓
      --     ⇒ 病根：`cfg.auto_create = false`，而白名单只放行 `hex.*`/`hit.*` 14 个；
      --       **"计划里有、存档里没有、白名单里也没有"的控件没有任何一条被造出来的路** ✗
      --
      --   ⇒ ★ 修法（**分家，不是补丁**）✓：结算四键**不再复用 exit_menu 的 id** ✓
      --     两个界面本来就是两件事 ✓ 分家之后：
      --       · 并集冲突消失（缺口 2 ✓）
      --       · 四个 id 只属于 `result` 状态 ⇒ 进 plan 的 `states` 并集，
      --         由 `entry_client_script.lua` 的 `auto_create_only` 放行创建（缺口 1 ✓）
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("result.next", "modal", { x = kx, y = my + 350, w = kw, h = kh },
          "下一关", { action = "next_level" }, "stamp.primary")
      btn("result.exit", "modal", { x = kx, y = my + 446, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("result.home", "modal", { x = kx, y = my + 542, w = kw, h = kh },
          "返回首页", { action = "home" }, "stamp")
      btn("result.settle", "modal", { x = kx, y = my + 638, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary")
      -- ★ 胶囊底图：★ 与 `exit_menu` 同一张（107179 ✓ 日志里 `回读=107179` ✓）
      --   ★ 用自己的守卫 ✓ —— 不跟 `_exit_menu_art` 共用 ✗（★ 那个可能在这段之前已被置真 ✓）
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
    -- ★★★★★★★★ 2026-10-20（v282）**删掉一个"同条件空分支"的雷** ✗✓
    --
    --   这里到 2026-10-20 之前是这么写的：
    --       `elseif modal.kind == "share" then`   ← ①
    --         （一串注释，**没有一句代码**）
    --       ……几十行……
    --       `elseif modal.kind == "share" then`   ← ②
    --         真正的渲染（push `modal.title` / `modal.body` / 关闭键 …）
    --
    --   ★ 问题：**同一条 if 链里第二个同条件的 elseif 永远进不去** ⇒ ② 是**死码**。
    --     `tools/lua-tooling/out/selene-report.txt` 里唯一的 `Error`（`ifs_same_cond`，
    --     报在旧行号 3580 对 3499）就是这个。
    --   ★ 真危害不是"多几行"：`modal.kind == "share"` 的**入口按钮**已被用户要求删掉，
    --     但**链路还在**（`a == "accuse"` 仍会构造 share 弹窗、`opts.on_share` 仍被回调）。
    --     哪天有人把按钮加回来 ⇒ 命中 ① 这个**空支** ⇒ **弹窗什么都不显示**，
    --     而注释还会告诉他"渲染分支保留着呢、理由在下面" ⇒ 极难查。
    --   ⇒ 现在：① 删掉（它的注释合并到 ② 那支），② 变成唯一、可到达的 share 分支。
    elseif modal.kind == "exit_menu" then
      -- ★★★★★ 2026-10-09 **几何改为【设计稿 B】** ✗✓（用户 2026-10-09 拍板选 B ✓）
      --   ★ 设计稿 B（画布空间 1600×900）✓：
      --     · 键尺寸 **312×60** ★ 横间距（pitch）**80** ★ cx=800（面板水平居中 ✓）
      --     · 四个键的**中心** cy = **570 / 490 / 410 / 330** ✓（面板中心 450 ⇒ 上下对称 ✓）
      --   ★ 换算到**脚本空间**（1920×1080，`M.DESIGN`）✓：画布 × 1.2 ✓
      --     · w = 312×1.2 = **374** ✓ · h = 60×1.2 = **72** ✓ · pitch = 80×1.2 = **96** ✓
      --     · cx = 800×1.2 = **960** ⇒ x = 960 − 374/2 = **773** = `mx + (mw−374)/2` ✓
      --   ★★ `rect.y` 的语义（★ 本项目把 ①③ 写反过 ✗，这里写死讲清 ✓）：
      --     · **`y` = 从父控件【顶边】往下数的偏移** ✓（不是左下原点的 cy ✗）
      --     · 面板 `modal` 顶边 = `my + mh` ⇒ 目标中心 y 对应的偏移
      --       = `mh − (cy_script − my) − h/2`
      --     · 逐个算 ✓：exit 50 · save 146 · settle 242 · cancel 338
      --       （校验：my+mh−偏移−h/2 = 684 / 588 / 492 / 396 ⇒ ÷1.2 = 570/490/410/330 ✓ 与设计稿一致 ✓）
      --   ★ 为什么改脚本就够 ✓：`root` 带 `pos_runtime = true`
      --     ⇒ `inherit_pos_runtime`（本文件 :1361）**沿子树继承** ⇒ `modal` 与这四个键
      --     **都算"运行时控件"** ⇒ 适配器每帧下发脚本算出的几何 ✓
      --     ⇒ ★ `.gil` 里那套 480×56 **运行时不生效** ✓（★ 这正是「编辑器预览是 480×56、
      --        进关卡却是另一套」的由来 ✓ —— PLAN.md A4 说的「A/B 二选一」其实一直是 B 在跑 ✓）
      --   ⚠️ 存档 `.gil` 里的 480×56 与 `label` 的 559×20 **仍待同步**（见 `接手待办.md` A4 备注 ✓）
      local kw, kh = 374, 72
      local kx = mx + math.floor((mw - kw) / 2)
      btn("modal.exit", "modal", { x = kx, y = my + 50, w = kw, h = kh },
          "退出至菜单", { action = "exit_menu_go" }, "stamp")
      btn("modal.save", "modal", { x = kx, y = my + 146, w = kw, h = kh },
          "仅存档", { action = "exit_menu_save" }, "stamp")
      btn("modal.settle", "modal", { x = kx, y = my + 242, w = kw, h = kh },
          "存档并结算", { action = "exit_menu_settle" }, "stamp.primary")
      btn("modal.cancel", "modal", { x = kx, y = my + 338, w = kw, h = kh },
          "取消", { action = "close_modal" }, "tab")

      -- ★★★★★ 2026-10-07 **给四个键设【官方胶囊底图】** ✗✓（用户要求配图 ✓）
      --   ★ 为什么走脚本而不是改 `.gil`：`docs/官方素材方案-脚本一体化.md` 已论证
      --     「**官方素材 + 脚本 = 图 / 色 / 尺寸 / 位置全可运行时改**」⇒ 配图本来就该脚本做 ✓
      --     （团队连改 4 轮 `.gil` 记录数组都卡在手工下标上 ✗ 这条路整个绕开 ✓）
      --   ★ 素材：★ **`107179`**（760×152，两端全圆角、米白）—— 与用户截图里的胶囊按钮同形 ✓
      --     `set_image_deep` 会自己往下找带 `SetImage` 的子控件（= 按钮的 `bg` ✓），
      --     并沿用控件自己编辑器里配的图集（`bg` 的 imageSource = 官方图集 ✓）✓
      --   ★ 只做一次（每帧设图会白烧成本 ✓ 本项目对每帧成本敏感 ✓）。
      -- ★★★★★ 2026-10-07 **只给 `bg` 子控件设胶囊底图** ✗✓（用户要求配图 ✓）
      --   上一版用 `set_image_deep(按钮, …)`：它"找第一个带 SetImage 的子控件"
      --   ⇒ 真机很可能命中 `label`（文字控件也有 SetImage）⇒ **图盖在文字上 ⇒ 图文都没了**
      --   （对照：加它之前"有字无图" ✓ 加它之后"图文都没有" ✗ ⇒ 变量只有这一个 ✓）
      --   ⇒ 现在**显式指名 `bg`**（`Adapter:sub(id, "bg")` ✓ 它就是按钮的底图那一层 ✓）
      --   素材 ★ **107179**（760×152 · 两端全圆角米白）= 用户选定 ✓ 沿用控件自己的官方图集 ✓
      -- ★ 2026-10-08 **守卫【外面】的探针** ✓（★ 真机：里面那两条一行没打 ✗ ⇒ 根本没进来 ✓）
      --   ★ 要分清两种可能 ✓：★ ① `self.adapter` 此刻是 nil ✗ ★ ② `_exit_menu_art` 已被置真 ✗
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：胶囊底图a　原 L3019..L3028
      if (not self._exit_menu_art) and self.adapter ~= nil then
        self._exit_menu_art = true
        for _, bid in ipairs({ "modal.exit", "modal.save", "modal.settle", "modal.cancel" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          -- ★ 2026-10-08 探针：★ `bg` 取到没 ✓（★ 取不到 ⇒ 与 `assets` 同源 ✗ 按名取子控件 ✓）
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：胶囊底图b　原 L3035..L3040
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：胶囊底图c　原 L3043..L3048
          end
        end
      end
    elseif modal.kind == "share" then
      -- ★ 2026-10-05 **这一支目前没有入口按钮**（用户当天决定去掉「分享棋局」按钮）。
      --
      --   **故意留着**，不是忘了删：
      --     · 链路还在 —— `a == "accuse"` 分支仍会 `core:encode_state()` 并构造
      --       `{ kind = "share", code = ... }`，`opts.on_share` 也仍在回调；
      --     · 将来要接**真实分享**（真正的分享面板/复制码）时，只要再加回一个按钮即可，
      --       不必把这一屏重写一遍；
      --     · 代价是零 —— 它只在"别处主动构造 share 弹窗"时才可能出现，平时不进任何计划。
      --
      --   ★★★★★★★★ 2026-10-20（v282）**现在它是唯一一支 share 分支，而且真的会执行** ✗✓
      --     在这之前，这条 if 链里**上面还有一支同条件的空分支** ⇒ 这一支永远进不去（死码）。
      --     合并说明见上面 `exit_menu` 前面那段注释（含"为什么以前那么写很危险"）。
      --   ⚠️ 顺带记一条**没删的历史信息**：旧的两键版（`modal.again` 重玩本关 /
      --     `modal.next` 下一关）在 2026-10-12 就被四键版取代；「重玩本关」的 `restart`
      --     动作在 `exit_menu` 与键盘里仍然存在，只是这个界面不再放它 —— 用户当时点名的就是四个键。
      --   ⚠️ 下面这些 `push` 里的 id 集合要与 `layout_plan` 的 states 并集一致；改它们之前先看
      --     `entry_client_script.lua` 的 `auto_create_only`（否则真机会"计划有、存档没有"）。
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 30, w = mw - 60, h = 56 }, text = "分享棋局", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 110, w = mw - 60, h = 200 },
             text = "把这个码发给别人，对方可以还原你的棋盘：\n\n" .. tostring(modal.code), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "关闭",
          { action = "close_modal" }, "tab")

    elseif modal.kind == "levelselect" then
      -- ===== 选关 =====
      -- 关卡清单由 main.lua 通过 opts.levels 传进来（界面层不认识 Levels 模块）
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
      -- ★ 2026-10-18（优化组）：这里原来遍历 `M.INTRO`（教程 5 页）拼「玩法」弹窗正文 ——
      --   教程那套已按用户指令整套删除（后续重做）⇒ 正文改成固定文案，**不再引用任何教程数据** ✓
      text[#text + 1] = "玩法：把每个角色放到正确的位置上；摆满后点「提交」校验，通过即可指认凶手。"
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 100, w = mw - 60, h = 280 },
             text = table.concat(text, "\n\n"), style = "modal.body" })
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "知道了",
          { action = "close_modal" }, "tab")
    end
  end

  -- ★★★ 2026-09-29：**主页 / 选关的整屏切换**。
  --
  --   ⚠️ 两个容器**每一帧都要显式给可见性**，不能只在 `screen ~= nil` 时处理 ——
  --      我第一版在"进入关卡"（screen == nil）时直接 return 了，
  --      于是主页/选关控件**留在关卡画面上**（美术检查报"棋盘区域有 1 个多余控件"）。
  --      原因：这两个容器在 `.gil` 里默认是可见的（要给编辑器里能看见、能调），
  --      所以**运行时必须由脚本负责关掉**。
  -- ★★★★ 2026-10-01 **真机"卡死"的最终修法：容器不再覆盖屏幕**。
    --
    --   为什么：`home` / `select` 铺满 1600x900 之后就成了**全屏射线靶子** ——
    --   它把**游戏自己的 UI（退出按钮）**都盖住、点不到，用户报"只能选关进去、出不来了"。
    --
    --   改成 1x1 放在屏幕正中：**子控件是相对父级中心定位的**，父级中心没变
    --   （仍是屏幕中心 (800,450)）⇒ **子控件坐标一个都不用动**，
    --   而容器本身小到不可能挡住任何东西。
    --
    --   同时把 `home.*` / `select.*` 的**父级改挂到 `root`**（见下面各 push），
    --   所以容器缩水不会让子控件被裁 —— 而且有证据：诊断三那个探针控件就挂在 `root` 下、
    --   尺寸 600x300、用户确认**看得见** ⇒ root 的子控件不被裁。
    --
    --   ⚠️ 这两个常量（`FULL` 和 `FULLSCREEN`）**都要改** —— 我第一版只改了
    --      `FULLSCREEN`，而计划里取的是**第一次** push 的几何 ⇒ 白改一次。
    local FULL = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }
  push({ id = "home", kind = "container", parent = "root", rect = FULL,
         visible = (self.screen == "home"), pos_runtime = true })

  if self.screen ~= nil then
    -- ★★★ 2026-10-01：**改成"反向逻辑"**（原来是白名单，漏了一大片）。
    --
    --   旧写法是一张 9 个 id 的白名单：
    --     { topbar, toolbar, left, board, right, toast, modal, intro, action.back }
    --   于是 **clues / action.undo·submit·reveal·hint·redo / hud.\* / cell.\*** 全都没被藏
    --   ⇒ **主页上能同时看到棋盘格子、线索条、右侧三个按钮**。
    --   （布局审计工具 tools/sim/audit_layout.mjs 抓到的：
    --      home period 下 cell.1.1 / clue.1 / action.undo / hud.title 的 visible 都是 true。）
    --
    --   白名单每加一个新控件都得记得补一次，**必然会漏**（这次就漏了一片）
    --   ⇒ 反过来：**只保留 home / select 这几棵子树 + root**，其余一律藏。
    --     以后再加控件，默认就是"进入关卡才显示"，不会漏。
    -- ★★★ 2026-10-01 二次修正：**从"反向逻辑"改回"白名单"**。
    --
    --   我原来想用反向逻辑（只保留 home/select 子树，其余全藏）来根治"漏藏"，
    --   但真机实测结果是 **整个界面空白** —— 太危险了：
    --     · 它是**默认隐藏**：任何状态/顺序/时机上的意外，代价都是"全都看不见"
    --     · 白名单是**默认显示**：漏掉某个新控件，代价只是"多显示了一个" ——
    --       而且布局审计（tools/sim/audit_layout.mjs）能当场抓出来
    --   ⇒ **可恢复的错 > 不可恢复的错**，改回白名单，但这次写全。
    --
    --   白名单内容 = 关卡内才该出现的东西（按 id + 按前缀两类）。
    --   新增关卡内控件时**记得补一笔**，补完跑一次布局审计确认。
    -- ★★★★★ 2026-10-05 **这一段"内联白名单隐藏"整段删掉** —— 它和下面那次重复 push 一起，
    --   是"选关页/主页看着不动也在烧 CPU"的真正来源。
    --
    --   它错在哪（可复现，`tools/_probe_setvis.lua`）：
    --     判据写的是**全局 `screen`** —— `build_layout` 里根本没有这个局部变量
    --     ⇒ 恒为 nil ⇒ `hide = (nil ~= "home")` **恒真**
    --     ⇒ 它把上面刚 push 的 `home` / `select` **每一帧都改成 `visible=false`**；
    --     而紧接着（原 L2582-2585）又 push 了**第二份** `home` / `select`
    --     （`visible = (self.screen == …)`）把可见性"救"回来
    --     ⇒ 计划里从此有**两个同 id 的节点**，而属性账本 `self._props` 是**按 id** 记账的
    --     ⇒ 两个节点每帧互相覆盖，永远收敛不了：
    --         第 N 帧：节点1 写 visible=false（和上一帧节点2 写的 true 不同）
    --         第 N 帧：节点2 写 visible=true （和节点1 刚写的 false 不同）
    --         第 N+1 帧：一模一样再来一遍
    --   实测代价（选关页稳态 60 帧）：
    --     · `tools/_probe_setvis.lua`：`select.visible` **每帧真写 2 次**（true/false 各一）；
    --     · 而 `set_property` 的 visible 分支会置 `_subtree_dirty`（那是兜底隐藏的触发源）
    --       ⇒ **`enforce_hidden_subtrees` 每帧都被重新触发**（实测 65 帧跑 65 次）
    --       ⇒ 146 次 `SetVisible`/帧、1230 次 `GetChildren`/帧
    --         （`tests/grid_cost.lua` 的小树上同一件事是 6 次 / 62 次）。
    --
    --   为什么可以整段删：这两件事**都已经有一份正确的实现** ——
    --     · 函数末尾的 `apply_screen_hide(nodes, self.screen)`：判据是**参数** `screen`
    --       （就是这里想读却读不到的那个值），而且它的 HIDE/PREFIX 名单是这里内联版的
    --       **超集**（多 `selbar` / `tpl-container` / `hex.` / `hit.` / `selbtn.` / `tpl.`
    --        以及"另一个屏幕的前缀"）⇒ 内联这段能藏的，它全藏；
    --     · `home` / `select` 的可见性：上面那次 push 的
    --       `visible = (self.screen == "home"/"select")` 已经给对了。
    --   ⇒ 删除后**行为一字不变**，只是每帧那两笔互相打架的写入消失了。
    --     （"同一件事两处实现必然漂移"是本项目反复踩到的病 —— 这就是最新的一例。）
    -- ★★★★ 2026-10-01 **真机"卡死"的最终修法**：容器**不再铺满屏幕**。
    --
    --   为什么：`home` / `select` 铺满 1600x900 之后就成了**全屏射线靶子** ——
    --   它把**游戏自己的 UI（退出按钮）**都盖住、点不到，用户报"卡死"。
    --   改成 1x1 放在屏幕正中：**子控件是相对父级中心定位的**，
    --   父级中心没变（还是屏幕中心）⇒ **子控件坐标一个都不用动**，
    --   而容器本身小到不可能挡住任何东西。
    --
    --   为什么敢这么做：诊断三那个探针控件是**挂在 `root` 下面**的，用户确认看得见
    --   ⇒ 说明**子控件不会被父级尺寸裁掉**（`root` 是全屏、探针 600x300 正常显示）。
    -- ★★★★★ 2026-10-05 **原来这里还有一份 `home` / `select` 的重复 push —— 已删**（见上）。
    --
    --   它俩和上面那次 push **几何完全相同**（`FULLSCREEN` 与 `FULL` 都是 0,0,DESIGN 尺寸），
    --   存在的唯一作用就是把上面那段内联隐藏错判掉的可见性"救"回来。
    --   内联那段既然删了，这一份也就只剩坏处：
    --     · 计划里多两个同 id 节点 ⇒ `render` 的属性循环对一个控件发两遍；
    --     · 一旦两处 `visible` 写得不一样，就是上面那种"每帧互相覆盖"的无限打架。
    --   ⚠️ 以后要改这两个容器的几何/可见性，**只改上面那一处**（L2521-2525）。
    if self.screen == "home" then
      -- ★★★★★ 2026-10-05 **A8 的出口②= `home.title`** —— 主页那两条提示的唯一出口。
      --
      --   为什么主页要单独一个：`apply_screen_hide` 在主页/选关把**整片 `hud.` 前缀**藏掉
      --   （见那张 HIDE/PREFIX 表），所以「商城 / 背包」这两条提示**在主页上没有出口** ✗。
      --   而主页上**存在**的文本控件只有 `home.title` 和四个按钮的标签
      --   （实测 `208-补active.gil`：`home.title` / `home.select` / `home.continue` /
      --     `home.shop` / `home.bag` 各 1 条；`select.*` **一条都没有** ⇒
      --     选关页（「还没有游玩记录…」会切到那一屏）**没有任何出口**，那一条仍然看不到 ——
      --     已如实记在探针与本轮回复里，**不假装解决** ✗）。
      --   ⇒ 点「商城 / 背包」时，主页那行大字直接变成提示语；到点自动变回 `M.HOME_TITLE`。
      push({ id = "home.title", kind = "text", parent = "root", visible = true,
             text = self:toast_text() or M.HOME_TITLE,
             rect = { x = 460, y = 140, w = 1000, h = 110 } })
      -- 中列四键。用户要求：原左边的「选关」挪到**中列最上**，原位置（左下角）留空。
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
        local list = {}
        local lv = self.opts.levels
        if type(lv) == "function" then list = lv() or {}
        elseif type(lv) == "table" then list = lv end
        -- ★★★★★★ 2026-10-15 **每页 8 → 4**（用户 2026-10-15 定稿：「选关改为四关一页」✓）
        --
        --   ★ 为什么改 ✓：现在**只有 4 个关卡** ✓
        --     · `PER = 8` ⇒ `pages = 1` ⇒ `pg_visible = false` ⇒ **翻页键与页码整组隐藏** ✗
        --       ⇒ ★ 翻页做好了却**永远看不到**，看起来像"没做" ✓
        --     · `PER = 4` ⇒ 4 关正好 **1 页**、★ **第 5 关起就是 2 页** ⇒ 加一关即可验翻页 ✓
        --
        --   ★ 版面依据 ✓：设计空间 **1920×1080、左上原点、Y 向下** ✓
        --     （见 `docs/控件坐标表-1600x900.md` 表头 ✓ 所以下面的 `y = 950` 是在 1080 里 ✓ 没出界 ✓）
        local PER = 4
        local total = #list
        local pages = math.max(1, math.ceil(total / PER))
        local page = tonumber(self.select_page) or 1
        if page < 1 then page = 1 end
        if page > pages then page = pages end
        self.select_page = page          -- 夹紧后存回去，免得越界状态一直留着
        local lst_base = (page - 1) * PER
        -- ⚠️⚠️ `opts.levels` 在 main.lua 里传的是**表**（`levels = level_list`），不是函数！
        --   我第一版写成 `self.opts.levels()` ⇒ `attempt to call a table value (field 'levels')`
        --   ⇒ **build_layout 直接抛错、整个渲染崩掉**。
        --   ⚠️ 2026-10-01 又踩一次：我挪分页变量段时用 TrimStart 把这几行**吃掉了**，
        --      报 `attempt to get length of a nil value (global 'list')`。
        --      ⇒ 挪代码不要用 TrimStart 粗暴裁切，会连注释和相邻语句一起带走。

        push({ id = "select.title", kind = "text", parent = "root", visible = true, text = "选择关卡",
             rect = { x = 460, y = 80, w = 1000, h = 90 } })
      -- ★★★★★★ 2026-10-15 **返回键 = 视觉层 + 命中层（两层）** ✗✓
      --
      --   ★★ 根因 ✓（真机实测：「左上箭头出现了，**还没有功能**」✓）：
      --     `hex.*` 这类【图标】控件**收不到光标事件** ✗
      --     官方在 `ui_controller.lua:2101` 那轮就撞过并记下原话：
      --       「**控件 `hex.back` 不支持光标事件**（请用「预设按钮」或「光标检测区域」控件）」✓
      --     ⇒ ★ 所以关卡内一直是**两层**：`hex.back`（视觉 ✓）＋ `hit.back`（**光标检测区域** ✓ 吃点击 ✓）
      --     ⇒ ★ 我第一版只克隆了 `hex.back` ⇒ **图出来了、点不动** ✓ 完全对得上现象 ✓
      --
      --   ★ 现在的结构 ✓（都建进了存档 ✓）：
      --     · `select.back`    #1073742727  62×62  克隆自 `hex.back` ⇒ **只做视觉** ✓
      --     · `hit.select.back` #1073742730  62×62  克隆自 `hit.back` ⇒ ★ **事件绑在它身上** ✓
      --   ★ z 序 ✓：命中层的 ID **大于**视觉层 ⇒ 追加在后 ⇒ **压在上面** ✓
      --     （与关卡内 `hex.back` #502 → `hit.back` #509 的顺序一致 ✓）
      --   ★ 尺寸 = **62×62**，与关卡内那颗**一模一样** ✓（用户：「改到和关卡内一样」✓）
      --   ★ `text` 不写 ✓ ⇒ 露出箭头图；★ `home` 分支 L1539 只切屏、`modal=nil` ⇒ **不弹窗** ✓
      local BACK_RECT = { x = 60, y = 48, w = 62, h = 62 }
      push({ id = "select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT })
      push({ id = "hit.select.back", kind = "button", parent = "root", visible = true,
             rect = BACK_RECT,
             event = { action = "home" } })
        -- ★★★ 2026-10-01：**选关翻页**（关卡多于 8 个时才有意义）。
        -- ★★★★★★★★ 2026-10-15 **改成"永远显示 + 没得翻就变暗"** ✗✓✓（用户 2026-10-15 报的 ✓）
        --
        --   ★★ 用户原话 ✓：「**左右箭头没加上去**」✗ —— ★ 而他其实只有 **4 关** ✓
        --     而脚本是「四关一页」✓（`PER = 4` ✓）⇒ `pages = 1` ✓
        --     ⇒ ★ 旧写法 `pg_visible = (pages > 1)` ⇒ **整组隐藏** ✗
        --       ⇒ ★★ 玩家看到的选关屏**没有左右箭头** ✓（用户就是这么报的 ✓）
        --
        --   ★ 旧写法错在哪 ✗：★ 它把"**这一屏有没有这个控件**"和
        --     "**这个方向现在能不能翻**"当成了同一件事 ✓ —— 这两件事是两回事 ✓✓
        --
        --   ★ 新写法 ✓（两件事分开 ✓）：
        --     · ★ **可见性 = 这一屏有没有** ⇒ 选关屏**永远有**这两个箭头 ✓
        --     · ★ **可用性 = 这个方向能不能翻** ⇒ 不能翻的用 **变暗**（`imageColor` 乘算 ✓）
        --       ⇒ ★ 玩家一眼能看出"箭头在、但这边没页了" ✓
        --       ⇒ ★ 而点击**照旧一律绑上** ✓（`select_page` 那边已经夹紧了 ✓
        --         见上面 `if page < 1 then page = 1 end` ✓ ⇒ 点它也不会越界 ✓）
        --
        --   ★ 变暗用的是本工程**已经用过的两个值** ✓（不新发明 ✓）：
        --     · `0xFFFFFFFF` = 不透明白 = **原色** ✓（见适配层 `NORMAL_TINT` ✓）
        --     · `0x7FFFFFFF` = 50% 透明白 = **整体减淡** ✓（见适配层 `PLACED_TINT` ✓
        --       就是"已放置头像卡"那种变淡效果 ✓）
        --   ⚠️ 前提 ✓：`tint` 那条路**必须在真机上真的生效** ✗ ——
        --     它这次一起修了 ✓（原来 `tint` 只认 table **且要求全局 `Color()`**，
        --     而真机上 `Color()` 不存在 ⇒ 一直是空操作 ✓ 见适配层那一段 ✓）
        local ARROW = 62
        local PG_Y  = math.floor((1080 - ARROW) / 2)      -- 509
        local PR = { x = 60, y = PG_Y, w = ARROW, h = ARROW }
        local NX = { x = 1920 - 60 - ARROW, y = PG_Y, w = ARROW, h = ARROW }
        local NORMAL_TINT, DIM_TINT = 4294967295, 2147483647
        -- ★ 视觉层：**永远可见** ✓；不能翻的那一边变暗 ✓
        push({ id = "select.prev", kind = "button", parent = "root", visible = true,
               rect = PR, tint = (page > 1) and NORMAL_TINT or DIM_TINT })
        push({ id = "select.next", kind = "button", parent = "root", visible = true,
               rect = NX, tint = (page < pages) and NORMAL_TINT or DIM_TINT })
        -- ★ 命中层：**永远可见** ✓（否则点不动 ✓）；两个方向都绑上 ✓（夹紧在 `select_page` ✓）
        push({ id = "hit.select.prev", kind = "button", parent = "root", visible = true,
               rect = PR, event = { action = "select_page", delta = -1 } })
        push({ id = "hit.select.next", kind = "button", parent = "root", visible = true,
               rect = NX, event = { action = "select_page", delta = 1 } })
        -- ★ 页码：**永远显示** ✓ —— ★「第 1 / 1 页」正好解释"为什么箭头是暗的" ✓
        push({ id = "select.page", kind = "text", parent = "root", visible = true,
               text = string.format("第 %d / %d 页", page, pages),
               -- ★ 2026-10-14 宽度 60 → 130 ✗✓：`第 1 / 2 页` 按 24 号字约 110px 宽 ✓
               rect = { x = 895, y = 952, w = 130, h = 70 } })
      -- ⚠️⚠️ `opts.levels` 在 main.lua 里传的是**表**（`levels = level_list`），不是函数！
      --   我第一版写成 `self.opts.levels()` ⇒ `attempt to call a table value (field 'levels')`
      --   ⇒ **build_layout 直接抛错、整个渲染崩掉**，
      --   表现成"主页激活时画不出东西 / 提交后不弹指认面板"。
      --   我为此查了三轮（`and/or` 陷阱、屏幕默认值、优先级），**全是白费** ——
      --   真正的错误信息一直在运行日志里，我没去看。
      --   ⇒ 教训：**改完先看运行时报错，再谈推断**。
      local list = {}
      local lv = self.opts.levels
      if type(lv) == "function" then list = lv() or {}
      elseif type(lv) == "table" then list = lv end
              -- ★★★ 2026-10-01：**加分页**。
        --
        --   原来固定 `for i = 1, 8 do local it = list[i]` ⇒ **只有前 8 关能选**，
        --   第 9 关之后**根本没有卡片**（关卡多起来就是死路）。
        --   现在：8 个卡位不变，翻页只换"从第几个关卡开始"。
        --
        --   为什么不做滚动列表：卡片是 2 行 × 4 列的大格子（含棋盘缩略图），
        --   一屏正好 8 张；翻页比滚动更贴合"选关"这个动作。
        
        -- ★★★★★★ 2026-10-15 **卡位数必须跟 `PER` 一致** ✗✓（原来硬编码 8 ⇒ 和 PER 打架）
        --
        --   ★ 原来的形状 ✗：`PER` 与循环的 `8` **是两个独立的数** ✓
        --     · `lst_base = (page - 1) * PER` ⇒ 用 PER 算偏移 ✓
        --     · `for i = 1, 8 do`         ⇒ 却渲染 **8 个卡位** ✗
        --     ⇒ ★ 一旦 `PER ~= 8`（例如改成 4）：
        --       第 1 页画 `list[1..8]`、第 2 页画 `list[5..12]` ✗
        --       ⇒ **两页重叠四关、而且第 1~4 关翻不回去** ✗✗
        --
        --   ★ 现在 ✓：**一页 4 张、一行四个**（用户定「四关一页」✓）
        --     · 卡位 `i = 1 .. PER` ✓ 偏移 `lst_base + i` ✓ 两处**同一个数** ✓
        --     · `x` 沿用原来的 4 列算式（`160 + (i-1)*420`）✓ ⇒ 一行铺满 ✓
        --     · 不再换行（原来第 5 张起 `y += 240`）⇒ **y 固定** ✓
        -- ★★★★★★ 2026-10-15 **卡片几何改成"扑克牌形"** ✗✓（用户 2026-10-15 定稿 ✓）
        --
        --   用户原话：「把选项卡拉成**高大于宽的矩形（扑克牌形）**，面积不要太大，
        --             **高约屏幕高度的 40%**，宽同比缩放，**间距稍宽**」
        --
        --   ★ 算式 ✓（设计空间 1920×1080 ✓）：
        --     · 高 = **40% × 1080 = 432** ✓
        --     · 宽 = 按**扑克牌比例 ≈ 1 : 1.4** 反算 ⇒ 432 ÷ 1.4 ≈ **310** ✓
        --     · 间距 **60**（原来是 40 ⇒ "稍宽" ✓）⇒ 步长 = 310 + 60 = **370** ✓
        --     · 一行四张：总宽 = 4×310 + 3×60 = **1420** ⇒ 居中起点 = (1920−1420)/2 = **250** ✓
        --     · 纵向居中偏上（给底部翻页那行留位）⇒ y = **330**（300…不重要，330 更居中 ✓）
        -- ★★★★★★★★ 2026-10-16 **用户指令③：选关卡片缩到 90%** ✗✓✓
        --   ★ 原话 ✓：「★ **把棋盘，棋盘背景图，选关卡片的 xy 缩减到现在的 90%**」✓
        --   ★ 310/432 × 0.9 = **279 / 388.8** ✓；★ 间距 60 同步缩到 **54** ✓
        --     （★ 间距不缩的话，四张卡的总宽反而会外扩 ✗）
        local CARD_W, CARD_H = 279, 388.8
        local CARD_GAP        = 54                         -- ★ 2026-10-16：60 × 0.9
        local CARD_STEP       = CARD_W + CARD_GAP          -- 370
        local CARD_X0         = 250                        -- (1920 − (4*CARD_W + 3*CARD_GAP)) / 2
        local CARD_Y0         = 330
        for i = 1, PER do
          local it = list[lst_base + i]
        local r = { x = CARD_X0 + ((i - 1) % PER) * CARD_STEP, y = CARD_Y0,
                    w = CARD_W, h = CARD_H }
        -- ★★★★★★★★ 2026-10-16 **卡片本身与它的随件，统一用【编辑器那张卡】的框** ✗✓✓
        --   ★ 见 `editor_card_box` 的函数头 ✓（读不到就退回上面这个规划框 ✓）
        --   ⚠️ 卡片自己**不会被写**（`geom_by_editor` ⇒ 编辑器说了算 ✓）；
        --      这里的 `r` 只决定"随件画在哪" + "控件不存在时按什么建" ✓
        r = self:editor_card_box(ui_adapter, "select.card." .. i, r)
        if it ~= nil then
          -- ★★★ 2026-09-30：卡片改成**三段**（参考《派蒙的执律庭实习》的选关卡片：
          --   上面一条"关名"纸条、中间是**该关棋盘的缩略图**、下面一行"人数/进度"）。
          --   原来是一整块按钮 + 多行文字 —— 缩略图没地方放（文字会盖在它上面）。
          -- ★★★★★ 2026-10-15 **卡面素材 `100108` → `CARD_MAT`（`106053` 「底板」类）** ✗✓
          --   ★ 依据与取值见文件上方 `CARD_MAT` / `CARD_TINT` 那两段 ✓
          --   ★ 一句话 ✓：★ `100108` 是"横板/墙"那类基础形状 ⇒ 在 310×432 上画出来是**横条** ✗
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, image = CARD_MAT, tint = CARD_TINT })
          -- ★★★★★★ 2026-10-15 **卡的点击也走命中层** ✗✓（同上：`hex.*` 图标收不到光标事件 ✗）
          --   · 视觉：`select.card.N`（克隆自 `hex.back`，卡面图 = 「底板」类 `106053` ✓）310×432
          --   · 命中：`hit.select.card.N`（克隆自 `hit.back` ✓ 光标检测区域 ✓）同 rect ✓
          --   · ★ **事件绑在命中层** ✓（原来绑在 `select.card.N` 上 ⇒ **点不动** ✗）
          --   ★ z 序：命中层 ID 更大 ⇒ 追加在后 ⇒ 压在上面 ✓
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, event = { action = "pick_level", id = it.id } })
          local t = self:level_card_parts(it)
          -- ★★★★★★★★ 2026-10-16 **`.title` / `.info` 也必须显式 `pos_runtime = true`** ✗✓✓
          --   ★ 为什么 ✗：这两条原来**没表态** ⇒ 靠继承（旧代码里 `root` 是 true ⇒ 它们也是 true）
          --     —— ★ 而 v248 起「继承来的」不再受理（几何归编辑器 ✓）
          --     ⇒ ★ 于是它们停在**存档里那份 100% 的卡位**上 ✗
          --       ★ 实测（模拟器截图）：★ 关名跑到卡**上方**、人数行跑到卡**下方** ✓
          --   ★ 它们和缩略图是**同一类** ✓：★ 内容是每关算的（关名/进度/房间）⇒
          --     ★ **几何必须跟着这张卡走** ⇒ 显式声明"脚本说了算" ✓
          --   ⚠️ 卡**本身**（`select.card.N` / `hit.select.card.N`）**不加** ✓ ——
          --     它归编辑器 ✓，而上面那个 `r` 已经让它"算出来的位置" = 编辑器那份 ✓
          push({ id = "select.card." .. i .. ".title", kind = "text", parent = "root",
                 visible = true, text = t.title, style = "card.title",
                 rect = { x = r.x + 16, y = r.y + 10, w = r.w - 32, h = 34 },
                 pos_runtime = true })
          push({ id = "select.card." .. i .. ".info", kind = "text", parent = "root",
                 visible = true, text = t.info, style = "muted",
                 rect = { x = r.x + 16, y = r.y + r.h - 42, w = r.w - 32, h = 32 },
                 pos_runtime = true })
          self:push_room_thumb(push, "select.card." .. i, it, r, "select")
        else
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          -- ★ 命中层也要显式隐藏 ✓ —— 否则**空卡位上会留一个能吃点击的透明块** ✗
          push({ id = "hit.select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          -- 空卡片的三个附件也要显式隐藏 —— 否则上一屏的内容会**残留在空位上**
          -- ★ 与上面同口径：附件显式 `pos_runtime = true`（卡位变了它们也得跟着 ✓）
          for _, suf in ipairs({ ".title", ".info" }) do
            push({ id = "select.card." .. i .. suf, kind = "text", parent = "root", visible = false,
                   rect = { x = r.x, y = r.y, w = 1, h = 1 }, pos_runtime = true })
          end
          self:push_room_thumb(push, "select.card." .. i, nil, r, "select")
        end
      end
    end
    -- ★★★★★★★★ 2026-10-15 **「结算」按钮：主页 ＋ 选关屏共用一颗，摆在左下角** ✗✓✓
    --
    --   ★★ 用户原话 ✓：「**在首页和选关界面左下角也加一个结算按钮，
    --     不接存档线，只接结算**」✓
    --
    --   ★ 三件事说清楚 ✓：
    --     · ★ **一颗控件、两个屏幕都用** ✓（★ 位置一样 ⇒ 不需要两套 ✓）
    --       ⚠️ 但它**只在主页/选关进规划** ✓ ⇒ 关卡内由 `render` 的差集收口藏掉 ✓
    --          （★ 与选关屏那整套同一个机制 ✓ 见 `render` 里 `self._shown` 那段 ✓）
    --     · ★ **事件走"预设按钮"原生那条路** ✓ —— ★ 它不是 `hex.*` 图标 ✗
    --       （★ 玩家在主页点了这么多天的「选关」正是同一类控件 ✓ 已验证能点 ✓）
    --       ⇒ ★ **不需要命中层** ✓（那是给"收不到光标事件的图标"补的 ✗）
    --     · ★★ **"不接存档线"= 只发 SETTLE 信号、不落盘** ✓
    --       ★ 与弹窗里那颗「结算」的区别就在这 ✓（那颗是先存后结算 ✓ 见 `on_settle` ✓）
    --       ⇒ ★ 回调是**独立的一个** `opts.on_settle_only` ✓ ⇒ 由 `main.lua` 提供 ✓
    --
    --   ★ 几何 ✓（设计空间 1920×1080，左上原点 ✓）：x=60, y=960, 260×72 ✓
    --     · ★ 与选关屏的返回箭头**同一条左边距（60）** ✓
    --     · ★ 纵向落在底部那条带里（页面指示在 952…1022 ✓ 它是 960…1032 ✓）⇒ 不打架 ✓
    --     ⚠️ 真机上**以存档里那份为准** ✓（`respect_editor_rect = true` ✓）
    --       ⇒ ★ 这个 `rect` 是"脚本心里的位置" ✓ 存档那份由 `tools/gil/add_button.mjs` 写 ✓
    --   ★★★★★★★★ 2026-10-16 **收成【一颗】：一次 push，一个开关** ✗✓✓（用户点破 ✓）
    --
    --   ★★ 用户原话 ✓：「**其实应该算一颗，它们位置一样，功能一样，
    --     没有必要建两颗还要分别隐藏，建一颗只在进入关卡后隐藏就行了**」✓✓
    --
    --   ★ 他指的是我 10-15 那两版留下的形状 ✗：★ 这里当时是 **`if … push(可见) else push(不可见)`**
    --     ⇒ ★ 同一个 id **一次规划里出现两条节点** ✓（★ 两条 + 两套显隐 ⇒ 必然漂移 ✓
    --       本项目为此已经写过好几条教训：「**同一件事两处负责 ⇒ 必然漂移**」✓）
    --
    --   ★★ 而现在**真因已经查清**（v244／v245 ✓）⇒ 那条 `else` **本来就不需要** ✓：
    --     · ★ 它当初是为了"**别的屏幕上别让它吃点击**" ✓
    --     · ★ 而真因是 **锚点/轴心 NaN** ✗（★ 已由 `fill_button_floats.mjs` 补齐 ✓）
    --       ⇒ ★ 补齐之后它就是一颗**正常尺寸**的按钮 ✓ ⇒ ★ 不再需要"关射线"来兜 ✓
    --
    --   ★ 一条规则说清全部 ✓（★ 与用户那句话逐字对应 ✓）：
    --     ★ **在主页/选关 ⇒ 这颗控件整个开着（`visible` ＋ `raycast`）** ✓
    --     ★ **进关卡（以及其它任何屏）⇒ 整个关掉** ✓
    --   ★ 为什么 `visible = false` 就够**止住命中** ✓：
    --     ★ 引擎不为不可见控件派发光标事件 ✓；★ `raycast` 一起写只是**同一句话的另一半** ✓
    --     ★ 而且不靠"有人记得去关它"——★ 这一条**每帧都算**，屏幕一变就跟着变 ✓
    --   ★ 收口仍然有兜底 ✓：★ `render` 的差集（`self._shown`）看到它上一帧显示过、
    --     这一帧不在规划里 ⇒ **照样发一次 `visible = false`** ✓（那条路早就在 ✓）
    --   ★★★★★★★★ 2026-10-16 **用户指令①：挪到和「提示」同一个位置** ✗✓✓
    --     ★ 原话 ✓：「★ **把主页和选关界面那颗结算按钮挪到和提示一个位置**」✓
    --   ★ 提示那颗 = `hex.hint`（放大镜 ✓）—— ★ 它在存档里是 `pos[683,−279] size[70×70]` ✓
    --     ⇒ ★ 画布中心 = (800+683, 450−279) = **(1483, 171)** ✓
    --   ★ 反算回设计空间 ✓：x = 1483×6/5 = 1779.6 ⇒ 左上原点 x = 1779.6 − 35 = **1744.6** ✓
    --     ★ y = (450 − 171)×6/5 = 334.8 ⇒ 再减半高 36 ⇒ 左上原点 y = **298.8** ✓
    --     （★ 尺寸取与提示同款 70×70 → 设计 84×84 ✓）
    local show_settle = (self.screen == "home" or self.screen == "select")
    --   ⚠️ ★★ **本函数里 `settle.btn` 只许有这一条 push** ✗✓（2026-10-16 用户点破 ✓）
    push({ id = "settle.btn", kind = "button", parent = "root",
           visible = show_settle,
           text = "结算",
           rect = { x = 1744.6, y = 298.8, w = 84, h = 84 },
           raycast = show_settle,
           event = { action = "settle_only" } })
    -- ★★★★★★★★ 2026-10-16 **v253：这里原来调的 `inherit_pos_runtime(nodes)` 已删** ✗✓
    --   ★ 用户指令 ✓：「把所有失效的几何/文字脚本代码从脚本中删除」✓
    --   ★ 它为什么**失效** ✗：★ 它会把 `root` 的 `pos_runtime = true` **沿子树传给每一个规划控件**
    --     ⇒ ★ 每个控件都被判成"脚本接管几何" ✗ —— ★ 而 v248 起口径已经改成"归编辑器" ✓
    --     ⇒ ★ 现在 `render` 只看**两件事**：★ ① 控件是不是脚本建的 ✓ ② 有没有**显式**写
    --       `pos_runtime = true` ✓（★ 见那里的头部注释 ✓）⇒ ★ "继承"这件事**不再参与判断** ✓✓
    apply_screen_hide(nodes, self.screen)
    return nodes
  end

  -- （同上：关卡路径这一处的 `inherit_pos_runtime(nodes)` 也已随 v253 删除 ✓）
  apply_screen_hide(nodes, self.screen)

  return nodes
end
-- ────────────────────────────────────────────────────────────────────────
-- 布局计划：把 build_layout() 摊平成「画布空间」清单，
-- 供 ① 模拟器建树脚本 ② 编辑器搭建指南生成器 共用同一份数据。
-- 每项：{ id, kind, parent, style, cx, cy, w, h, text, visible, states }
-- cx/cy 就是编辑器「位置 X, Y」要填的数（pivot 设 0.5,0.5）。
--
-- ★ 必须**遍历所有界面状态**再取并集：弹窗（指认/结果/分享/玩法）和开屏教程
--   的控件只在对应状态下才出现在 build_layout() 里。如果只按开局那一屏生成，
--   编辑器里就会缺 modal.* / intro.* —— 脚本运行时按名字找不到，面板永远出不来。
-- ────────────────────────────────────────────────────────────────────────
-- 关卡卡片文字（murdoku 原作那种：关名 + 进度）。
-- ⚠️ 文字存不进 .gil，只能脚本写；进度拿不到就只显示关名 —— **不编数据**。
-- ★★★ 2026-09-30：**选关卡片显示什么**（参考《派蒙的执律庭实习》的卡片，
--   见 `docs/美术改造规格-参考执律庭实习.md` 第一节）。
--
--   参考图每张卡片 = **关名（米色纸条）+ 棋盘缩略图 + 「NxN　M名嫌疑人+1名受害人」**。
--   文字只能脚本写（存不进 `.gil`），所以这里生成：
--
--     案件 001 · 夜盗独行
--     5x5　4名嫌疑人+1名受害人
--     ★ 已破案 / · 进行中 / 未开始
--
--   ⚠️ 取值一律**从关卡数据里读**，读不到就**不写那一行** —— 不编数据
--   （比如 `size` 缺失就只显示关名，而不是硬写一个 "5x5"）。
-- ★★★ 2026-09-30：**选关卡片的三段内容**（参考《派蒙的执律庭实习》的卡片）。
--
--   卡片现在是"标题 / 缩略图 / 说明"三段，所以文字也拆成两块：
--     · `select.card.N.title` —— 关名（上面那条）
--     · `select.card.N.info`  —— 「NxN　M名嫌疑人+1名受害人」+ 进度（下面那行）
--   缩略图夹在中间（见 `push_room_thumb`）。
--
--   取值规则同前：**从关卡数据里读，读不到就不写那一行** —— 不编数据。
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
  if type(p) == "table" then
    local mark = "未开始"
    if p.cleared then mark = "★ 已破案"
    elseif p.started then mark = "· 进行中" end
    bits[#bits + 1] = mark
  end
  return { title = title, info = table.concat(bits, "　") }
end

-- 房间色块的配色（**只在这里定义一处**）。
--
--   为什么是"色块"而不是"逐格"：参考图的缩略图就是几块彩色区域。
--   逐格要 rows×cols 个控件（最多 49 个）× 8 张卡 = 392 个，太多；
--   色块只要"每关房间数"个（本项目每关 3 个）⇒ 8×6 = 48 个上限，可控。
--
--   ⚠️ 素材用的是**整数 id 106053（白）**，靠 `imageColor`（乘算着色）出颜色。
--     `assets` 里目前只有 9 张头像、**没有房间类素材**，所以不能写 "room.xxx"
--     这种调色板名（那只对 assets 里存在的名字有效）。
--     等美术资源齐了，把这里换成真实素材名即可（一行改）。
--   ★★★★★★★★ 2026-10-15 **这张颜色表原来【一个颜色都没上上去】** ✗✓✓（本轮查到 ✓）
--
--   ★★ 根因 ✓：★ 适配层的染色分支**只认 table** ✗ ——
--     `engine_adapter_qianxing.lua` 的 `elseif key == "tint"` 那一支：★ `… if target ~= nil and
--       **type(value) == "table"** then … end` ✓
--     ⇒ ★ 而这里原来是 **6 个裸整数**（`4285965944` 这种打包 ARGB）✗
--       ⇒ ★★ `type(value) == "table"` 为假 ⇒ **静默什么都不做** ✓（连一行警告都没有 ✗）
--   ★ 佐证 ✓：★ 同一份文件里**能用**的那张表是 `Controller.ROOM_COLORS`（**table 形式** ✓
--     见下方 `{ r = 214, g = 196, b = 160 }`）⇒ ★ 格子染色一直好使 ✓ 而缩略图一直没色 ✓
--   ★★ 顺带核到的第二件事 ✗：★ 那 6 个整数**解码出来也不是注释写的颜色** ✓
--     （实测：`4285965944` → r=118 g=166 b=120 是**绿色**，注释却写"暖米" ✓）
--     ⇒ ★ 说明它们**从来没被验证过** ✓（★ 因为压根没生效 ✓）
--   ⇒ ★★ 修法 ✓：★ **直接复用 `Controller.ROOM_COLORS`** ✓ ——
--     ★ 它本来就是"棋盘上这个房间是什么色"的那张表 ✓
--     ⇒ ★ 缩略图色块与棋盘房间色**从此同一个来源** ✓（★ 不会再各说各话 ✓）
local ROOM_MAX = 6          -- 一关最多画几个房间色块
local WHITE_MAT = 106053    -- 真机日志里确认过的白底素材 id（「底板」类 ✓ 可 Stretch ✓）

-- ★★★★★★★★ 2026-10-16 **卡片的"随件"以【编辑器里的卡】为准** ✗✓✓
--
--   ★ 起因 ✓：★ 这一轮把几何交回编辑器之后（`geom_by_editor` ✓），
--     `select.card.N` 用的是**编辑器里那份 208.98×291.6**（用户缩到 90% 的那一版 ✓），
--     ★ 而卡片上的**随件**——`select.card.N.title` / `.info` / `.room.M`（缩略图色块）——
--       是**按规划里那份 100% 的卡框**算出来的 ✗
--     ⇒ ★ 结果是"卡小了、字和缩略图还在原来那个大位置上" ⇒ 看起来像没修 ✓（比不修更糟 ✗）
--
--   ★★ 口径 ✓：★ **随件跟着编辑器那张卡走** ✓ ——
--     · 卡的**位置/尺寸**：读运行时（= 编辑器那份）✓
--     · 卡的**内容**（关名/进度/房间缩略图）：仍由脚本按关卡数据算 ✓（分页/换关都要变 ✓）
--     ⇒ ★ 两者用**同一个框**：随件算出来的坐标就永远落在卡里 ✓
--
--   ★ 换算链（与适配器 `rect` 分支**逐字同源**，不另造一套 ✓）：
--     设计坐标(1920×1080, 左上原点) --×scale--> 画布(左右/上下都 ×scale)
--     --父级中心--> 引擎的 anchoredPosition（Y 向上）
--     ⇒ 反着走一遍就得到"设计空间的框" ✓
--   ★ 父级中心为什么是画布中心：卡片的真实父级是 `root`，而 `root` 撑满画布 ✓
--     （实测佐证：规划 `settle.btn` = 设计 (1744.6,298.8,84,84) ⇒ 落屏 (689,166) ✓
--       与"父级中心 = (800,450)" 逐位吻合 ✓）
--   ★ 读不到（控件不在 / 引擎不给读）⇒ ★ **退回规划框** ✓（不许因此不摆 ✗）
--   ⚠️⚠️ **必须把适配器【当参数传进来】** ✗✓ —— 本轮踩过 ✓：
--     `Controller` 上**没有** `self.adapter` 这个字段 ✗（`main.lua:510` 的 `self.adapter = adapter`
--     设的是 **Murdoku 实例**，不是控制器 ✓）⇒ 我第一版写 `self.adapter` ⇒ **恒为 nil** ⇒
--     静默退回规划框 ⇒ 量出来的缩略图还在 100% 那张卡的位置上 ✓（看起来"没生效"✓）
--     ⇒ ★ `render(adapter, force)` 手里就有 ✓ 传下去即可（`build_layout(ui_adapter)` ✓）
function Controller:editor_card_box(a, id, plan_r)
  if a == nil or type(a.find) ~= "function" then return plan_r end
  local ctrl = nil
  pcall(function() ctrl = a:find(id) end)
  if ctrl == nil or ctrl.GetSizeDelta == nil or ctrl.GetAnchoredPosition == nil then return plan_r end
  local w, h, ax, ay = nil, nil, nil, nil
  pcall(function() w, h = ctrl:GetSizeDelta() end)
  pcall(function() ax, ay = ctrl:GetAnchoredPosition() end)
  -- ★ 2026-10-18 一次性诊断（用户报「选关界面只有一张卡」）：每张卡**只打一次** ✓
  --   ★ 判据：四张卡若**位置完全相同** ⇒ 编辑器里就是叠着的 ⇒ 脚本按规划格重排 ✓
  --           若**各不相同** ⇒ 叠的原因是别的（层级/父级换算），再换方向 ✓
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
  if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return plan_r end
  if type(ax) ~= "number" or type(ay) ~= "number" then return plan_r end
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

function Controller:push_room_thumb(push, cardId, it, cardRect, parent)
  -- 缩略图区域：卡片中间那块（上面留给标题、下面留给说明）
  local area = { x = cardRect.x + 24, y = cardRect.y + 50,
                 w = cardRect.w - 48, h = cardRect.h - 50 - 48 }
  local boxes = it and it.room_boxes or nil
  local sz = it and it.size or nil
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  for j = 1, ROOM_MAX do
    local id = cardId .. ".room." .. j
    local b = (type(boxes) == "table") and boxes[j] or nil
    if b ~= nil and rows and cols then
      -- 把"第几行第几列"按比例映射进缩略图区域（不依赖任何素材尺寸）
      local cw = area.w / cols
      local ch = area.h / rows
      local x = area.x + math.floor((b.c1 - 1) * cw)
      local y = area.y + math.floor((b.r1 - 1) * ch)
      local w = math.max(2, math.floor((b.c2 - b.c1 + 1) * cw))
      local h = math.max(2, math.floor((b.r2 - b.r1 + 1) * ch))
      -- ★ 位置按**每个关卡**的房间外框算 ⇒ 必须 `pos_runtime`（理由同房间名标签：
      --   否则会被 `respect_editor_rect` 按在存档里那一份几何上，
      --   8 张卡片的缩略图会**全挤成同一块**）。
      -- ★ 颜色 = **与棋盘上的房间色同一张表** ✓（`Controller.ROOM_COLORS` 是 table 形式 ✓
      --   而适配层的 `tint` 分支**只认 table** ✗ —— 原来传的是打包整数 ⇒ 一直没上色 ✓
      --   详见本函数上方 `ROOM_MAX` 那一段 ✓）
      local colors = Controller.ROOM_COLORS
      local tint = (type(colors) == "table" and #colors > 0)
        and colors[((j - 1) % #colors) + 1] or nil
      push({ id = id, kind = "button", parent = parent, visible = true,
             rect = { x = x, y = y, w = w, h = h },
             image = WHITE_MAT, tint = tint, pos_runtime = true })
    else
      -- 占位也给**真实尺寸**（沿用它上面的区域），只是隐藏 ——
      -- 原因同房间名标签：跨关卡取并集时"第一次出现"的几何会留下，
      -- 给 2×2 的话真机上色块会缩成一个点。
      push({ id = id, kind = "button", parent = parent, visible = false,
             rect = { x = area.x, y = area.y, w = math.max(2, math.floor(area.w / 4)),
                      h = math.max(2, math.floor(area.h / 4)) }, pos_runtime = true })
    end
  end
end

-- ★★★ 2026-09-30：**物件 → 素材键**（家具图标用）。
--
--   关卡里的物件是**中文名做键**的（`["书架"] = {...}`），而适配层拿这个名字
--   去 `assets` 调色板查素材 ⇒ 素材名会变成 `obj.书架`。中文素材名不好管理
--   （改名、跨语言、和图集对不上）。
--
--   ⇒ 规则：
--     · 物件定义里写了 `kind = "shelf"` ⇒ 用 `obj.shelf`（ASCII 稳定键，推荐）
--     · 没写 ⇒ 退回中文名（**不破坏现有数据**，老关卡一个字都不用改）
--
--   ⚠️ 一定要查"当前关卡"的物件表。`vm` 里只有**这一格是什么物件**（名字），
--     没有 kind —— kind 在关卡数据的 `objects` 里。
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

  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：level_card_text　原 L3504..L3531

function Controller:layout_plan()
  local saved_modal = self.modal   -- ★ 2026-10-18：intro 已删，不再保存 intro_page
  -- ★★★ 2026-09-30：**屏幕状态也要纳入枚举**。
  --   `layout_plan` 原来只枚举 8 种"关卡内"状态（intro / modal 各变体），
  --   **从不设置 `self.screen`** ⇒ 主页和选关的控件**永远进不了布局计划**
  --   ⇒ 模拟器建树时压根没有 `home.select` 这些控件：点不到、也没法验证。
  --   我为此查了半天"为什么点主页按钮没反应"，最后打印计划才发现控件不在里面。
  local saved_screen = self.screen
  local vm0 = self.core:view()
  local first_id = vm0.tray[1] and vm0.tray[1].id

  local states = {
    -- ★ 整屏状态排最前：编辑器/模拟器要按这份清单建控件
    { name = "home",              intro = 99, modal = nil, screen = "home" },
    { name = "select",            intro = 99, modal = nil, screen = "select" },

    { name = "board",             intro = 99, modal = nil, screen = nil },
    -- ★★★★★★ 2026-10-12 **指认相关的两个【计划状态】已删**（用户指令 ✓）✗✓
    --
    --   ★ 为什么必须删 ✓（不只是"好看"）：
    --     这份清单是**全状态并集的唯一来源** ✓ 它同时喂给
    --       · 模拟器控件树 · 编辑器搭建表 · 批量生成器 ✓
    --     ⇒ 留着它 ⇒ `modal.suspect.*` / `modal.no_accomplice` 会被**继续声明成"计划必需"** ✗
    --     ⇒ 而它们**存档里没有、也没有创建路** ⇒ **又变成"计划有、存档没有"的静默缺失** ✗
    --     ⇒ 正是本轮刚修掉的那一类病 ✓ 所以**必须连同计划一起删干净** ✓✓
    --
    --   ★ 判定链**一个字没动** ✓ —— `Core:accuse_verdict` 仍在，只是改成
    --     `do_submit()` 在 `res.ok` 时**直接调**它 ✓（答案由 `core.roles` 提供 ✓）
    { name = "result",            intro = 99,
      modal = { kind = "result", win = true, message = "（结果文案）" }, screen = nil },
    { name = "share",             intro = 99,
      modal = { kind = "share", code = "（分享码）" }, screen = nil },
    { name = "howto",             intro = 99, modal = { kind = "howto" }, screen = nil },
    { name = "levelselect",       intro = 99,
      modal = { kind = "levelselect" }, screen = nil },
    -- ★★★★★ 2026-10-09 **补 `exit_menu`（四键退出弹窗）** ✗✓
    --   ★ 为什么必须在这里 ✓：★ 本清单是**全状态并集**的唯一来源 ✓，它同时喂给
    --     · 模拟器控件树（`tools/sim/kit.mjs:23` 的 `loadPlan()` **直接读 `layout-plan.json`** 建树 ✓）
    --     · 编辑器搭建表（`docs/控件坐标表-1600x900.md`，由同一个 plan 生成 ✓）
    --     · 批量生成器（`tools/gil/gen_bulk.mjs` ✓）
    --   ★ 少了这一条会怎样 ✗（★ 实测 ✓）：★ `build_layout()` 里
    --     `elseif modal.kind == "exit_menu"`（本文件 :2958）那四个 `btn(...)`
    --     **永远不被 layout_plan 采集** ✗ ⇒ `layout-plan.json` 里**没有**
    --     `modal.exit / modal.save / modal.settle` ✗ ⇒
    --       · 模拟器建出来的树没有它们 ⇒ 适配器 `find()` 失败 ⇒
    --         真机/模拟器日志出现「这些控件还没建 ×3」✗（**8/13 与 15/15 两步审计就是这样红的** ✓）
    --       · 搭建表也不列它们 ⇒ **一旦照表重建界面，四键会被漏掉** ✗
    --   ★ 与 `kit.mjs:152-161` 记的是**同一种病** ✓：那一处是 `bg`/`label` 被写进 `.gil`
    --     却不在 plan 里 ⇒ 模拟器缺件；这一处是四个键本身不在 plan 里 ✓
    --     ⇒ ★ 修法统一：**让 plan 覆盖到真实存在的东西** ✓（而不是在模拟器里继续手工补件 ✓）
    --   ★ 为什么之前漏了 ✓：`docs/弹窗-线索汇总.md` §7 第 1 步列的 5 块里，
    --     入口分支 / 三动作 / 渲染分支 / DECOR 都补了，**唯独「计划状态 exit_menu」没补** ✓
    --   ⚠️ `modal.cancel` 本来就在 plan 里（被 accuse_thief / howto / levelselect 等
    --     6 个状态共用 ✓）⇒ ★ 它一直正常 ✓ —— 这正是「四个键只有一个好使」的出处 ✓
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
            -- ★ 2026-10-01：**图片素材/颜色/旋转也要进计划** —— 否则 sync_plan 建图片控件时
            --   拿不到 image_id，新控件会带上原型（wall.right）的图。
            --   链条：build_layout → **这里** → tools/dump_layout.lua → sync_plan.mjs，
            --   三处都要带（我漏了两处，image_id 一路是 undefined）。
            image_id = n.image_id, imageColor = n.imageColor, rot = n.rot,
            -- ★★★★★ 2026-10-04 **`event` 也必须进计划** —— 和上面 `image_id` 是**同一类链子问题**：
            --   这里是**再建一张新表**、字段写死，`build_layout` 里挂的 `event` 会被整片丢掉。
            --   后果：导出的规划表里 `event` 全是 nil（实测 **0 / 322**），
            --   于是"这个按钮点下去有没有动作"**完全无法核对** ——
            --   我这一轮给七个 `hex.*` 图标加了 `event`，导出来却仍是 `动作=undefined`，
            --   差点误判成"没设上"。只取 `action`（适配层就是按它分发）。
            action = n.event and n.event.action or nil,
            -- ★★★★★ 2026-10-05 **`event` 整表也必须进计划** ✗✓ —— 第 3 项"点格子没反应"的最后一环 ✓
            --
            --   为什么（**真机 vs 模拟器的唯一差别** ✓ 三段切开 + 静态定位出来的 ✓）：
            --     · **真机**：`build_layout()` 直接建控件 ⇒ `node.event` 是**完整表** ✓
            --       ⇒ `engine_adapter_qianxing.lua:816` 的守卫
            --         `if node.event ~= nil and (node.kind == "button" or node.kind == "cursor")`
            --         **放行** ✓ ⇒ `bind_input` 跑 ✓ ⇒ 格子上**有监听器** ✓
            --     · **模拟器**：`dump_layout` → 计划 JSON → `kit.mjs` 建树 ✗
            --       ⇒ 计划里原来**只有扁平的 `action`** ✗（实测 `"event"` **0 次** ✓）
            --       ⇒ `node.event == nil` ✗ ⇒ ★ **守卫拦掉** ✗ ⇒ **从不 `bind_input`** ✓
            --       ⇒ ★ **模拟器里任何控件都没有监听器** ✗ ⇒ 点击到不了脚本 ✗ ⇒ `0 / 5` ✓✓
            --   ★ 实测互证（两个独立代理 ✓）：
            --     · `[T3Q] _fire#` 在 4 次点击后出现 **0 次** ✓ ⇒ 点击根本没进 `_fire` ✓
            --     · 计划里 369 个节点**没有一个带 `event`** ✓
            --   ★★ 为什么这**不是**"放宽断言" ✗ —— ★ **是让模拟器【忠实还原真机】** ✓✓
            --     真机的节点本来就有 `event` ✓ ⇒ 计划也该有 ✓（否则模拟器测的是另一棵树 ✓）
            --   ⚠️ **`action` 必须保留** ✗ —— `sync_plan.mjs` 等消费者按它工作 ✓ 只是【再加】一个字段 ✓
            --   ⚠️ 参考：`image_id`（2026-10-01）与 `action`（2026-10-04）是**同一类链子问题** ✓
            --     ★ 这次是第三次：**`event` 的值为 nil** 与 **`event` 这个键不存在**，是两回事 ✗✓
            event = n.event,
        }
        byId[n.id] = prev
        order[#order + 1] = prev
      end
      prev.states[#prev.states + 1] = st.name
      -- 文案取「在某个状态里可见」的那一份
      if (n.visible ~= false) and prev.visible == false then
        prev.text = n.text
        prev.visible = true
      end
    end
  end

  self.modal, self.screen = saved_modal, saved_screen

  -- 初始可见性：只有「开局就该看见」的控件才是可见的，其余交给脚本按状态开关。
  -- （脚本每次 render 都会把 visible 同步过去，所以这里留 false 最安全。）
  for i = 1, #order do
    local it = order[i]
    local in_board = false
    for k = 1, #it.states do
      -- ★ 2026-10-12：`accuse_*` 两个状态名已随指认面板一起删 ✓（见上面 plan states 那段 ✓）
      if it.states[k] == "board" or it.states[k] == "result"
         or it.states[k] == "share" or it.states[k] == "howto" then in_board = true end
    end
    it.visible = in_board and it.visible
  end
  return order
end

-- ────────────────────────────────────────────────────────────────────────
-- 头像卡的「画布空间几何」。
--
-- 为什么要单独给适配层一份：头像卡的**列数按人数自适应**（保证只占 2 行），
-- 于是同一张 tray.A 在 5 人关和 7 人关里位置/尺寸都不一样。编辑器每个控件
-- 只能有一套几何，所以做法是「编辑器按最挤的情况静态摆好，运行时按本关
-- 实际人数重新摆正」—— 和棋盘格子同一套思路。
--
-- 这里算**画布绝对坐标**；适配层只负责换算成「相对父级中心的偏移」再应用，
-- 避免两处各自推导导致差 1px。
-- ────────────────────────────────────────────────────────────────────────
-- ★ 2026-10-18（优化组 · C 类清理）：**`Controller:tray_layout_canvas()` 已删除** ✗✓
--   它算的是"头像卡该摆哪"，而头像卡容器 `tray` 已在本次删除 ⇒ 恒返回 nil，
--   `main.lua` 里的调用点（`if adapter.apply_tray_layout and controller.tray_layout_canvas`）也跟着删，
--   ⇒ 真机日志里那行「找不到头像卡容器」不会再出现 ✓

function Controller:placed_count(vm)
  local n = 0
  for i = 1, #vm.tray do if vm.tray[i].placed then n = n + 1 end end
  return n
end

  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：violations_text　原 L3708..L3713

-- 房间染色表：同一张底图 + 不同 imageColor 就能区分房间 —— **零额外素材**。
--
-- 官方依据：`ClientUIImageControl.imageColor` 是 `ColorValue` 类型、**读写**、
-- Tweenable；ColorValue 由全局函数 `Color(r,g,b,a?)` 创建（0–255，a 可省略）。
-- 适配层会把它落到格子的 `face` 子控件上（见 set_property 的 "tint" 分支）。
--
-- 改这里就能换配色；不想要染色就把整张表清空（返回 nil → 适配层跳过）。
--
-- ★★★★★★★★ 2026-10-22（v299）**房间配色换成"室内木地板/石面"那一族** ✗✓
--
--   美术资源组这一轮的基准是原作 Murdoku 的截图：房间都是有「暖木/石面/草地」底色的
--   平面图，而不是高饱和色块。旧表（暖木 / 冷灰蓝 / 淡紫 / 淡绿 / 陶土 / 石板）里
--   第 3 个「淡紫」和第 2 个「冷灰蓝」放在室内像"卡通风"，与家具的木质棕/米白打架。
--   ⇒ 这一版把 6 个值统一**降饱和 + 偏暖**，并把「淡紫」换成「暖灰」——
--     这样 3 个房间并排时像一间屋子的三块地面。
--   证据：`_work/art-work/v7-*`（旧色）与 `v8-*`（新色）的整盘预览对照。
--   ⚠️ 这张表同时被「选关卡片缩略图」用（见 L4256 那段），所以换色两边一起变 —— 这是有意的。
Controller.ROOM_COLORS = {
  { r = 217, g = 205, b = 180 },   -- 1 暖米（木地板）
  { r = 195, g = 205, b = 212 },   -- 2 冷灰蓝（石材）
  { r = 212, g = 200, b = 188 },   -- 3 暖灰（灰泥）
  { r = 190, g = 207, b = 176 },   -- 4 淡绿（草地）
  { r = 224, g = 200, b = 176 },   -- 5 沙色
  { r = 198, g = 198, b = 210 },   -- 6 石板
}

-- 注意：这是**普通函数**不是方法（同 portrait_of 的坑）
function Controller.room_color(room)
  if type(room) ~= "number" then return nil end
  local t = Controller.ROOM_COLORS
  if type(t) ~= "table" or #t == 0 then return nil end
  return t[((room - 1) % #t) + 1]
end

-- ★★★★★★★★ 2026-10-11 **棋盘线的身份 = 行号（`row.<关>.<行>`）** ✗✓✓
--
--   ★★★ 用户 2026-10-11 拍板（★ 原话）：
--     「★ **如果非要这个机制，就把 `id` 设为 `letter`，或者 `row.i.j`**
--      ★ **如果不是必要机制就删了**
--      ★ **`who` 已经干扰了很多次了** ★ **你不要再陷进去了**」✓✓
--
--   ⇒ ★ 两条路里**选 `row.i.j`** ✓ —— ★ 理由是用户点名了它 ✓（★ 下面如实记代价 ✓）：
--     ★ `id` 那条路要求"第 i 行 ↔ 第 i 个棋子"**严格对齐** ✓
--       ★ 真关卡今天**恰好**对齐 ✓（★ 复核者实测：四关都是 `#clues == #pieces` ✓ 5/5/6/7 ✓）
--       ★★ 但它**不保证**以后还对 ✗：★ 夹具 `tests/fixtures.clue_level_case001()`
--         就是 **8 条线索 / 5 个棋子** ✓ ⇒ ★ 那种形状下行号 7、8 **没有对应棋子** ✓
--         ⇒ ★ 按「第 i 个棋子」落账会**丢掉两行** ✗
--     ★★ 按「行号」落账：★ **几行就几行，一个都不丢** ✓✓
--     ★ 而且 `letter.<关>.<行>` 与 `face.<关>.<行>` **本来就同行**
--       ⇒ ★ **两张表天然同键** ✓（★ 前几轮就栽在「两张表键不同」上）
--   ⚠️ ★ 如实记一笔 ✗（★ 复核者指出、我接受 ✓）：★ **"今天真关卡被迫这样"是不成立的** ✓
--     ★ 真关卡行数**正好等于**棋子数 ✓ ⇒ ★ 换那条路今天也能过 ✓
--     ★★ 所以这里的真正依据是**用户点名 `row.i.j`** ＋ **行号在数据上更稳** ✓
--       ★ **不是**"实测逼出来的" ✗ —— ★ 别再拿夹具那条当"实测"用 ✓
--
--   ★★ 于是整条链只剩一次换算 ✗：★ **棋子 → 行号** ✓
--     ★ 棋盘那一格给的是 `cd.suspect` = **棋子 id**
--       ★ 而 `row.<关>.<行>` 是按**行号**摆的 ⇒ ★ 必须换一下 ✓
--     ★ 依据 = ★ **`core.pieces` 自己的顺序**
--       （★ 不查 `who` ✗、不查卡片文字 ✗、不猜 ✗）
--     ★ 用户的口径：「★ **一人一条**」 ⇒ ★ 棋子 ↔ 线索 ↔ 行 一一对应 ✓
--     ★ 查不到 ⇒ **返 nil**（★ 宁可这一格不显示，也**不许瞎猜**）

-- 第 n 行（1 起）配的是哪个棋子 —— ★ 与 `row.<关>.<行>` 同一口径；查不到返 nil
--   ★ 缓存：★ 这条链**每帧**要跑（列表项填充）
--     ★ 而 `core:view()` 是一次**整视图重建**（本项目实测 ~0.2ms）
--     ★★ 每帧每张卡调一次 ⇒ 白烧 ⇒ ★ 按**关卡表身份**缓存一份
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

-- 棋子 id → 它配在第几行（1 起）—— ★ 棋盘读 `_row_letter` / `_row_face` 就走它
--   ★ 与 `_piece_at_row` 同一张缓存 ⇒ ★ 双向一致 ✓
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

-- 注意：这是**普通函数**不是方法，所以不能用 self:portrait_of(vm, id) 调用
-- （冒号调用会把 self 当第一个参数，vm 就变成控制器了 —— 这个坑已经踩过一次）
function Controller.portrait_of(vm, id)
  local _m = Controller._row_face
  if _m ~= nil then
    -- ★ 直查（★ 兼容"键就是 id"的老调用）
    local _hit = _m[tostring(id)]
    if _hit ~= nil then return _hit end
    -- ★★ 主路：★ **棋子 → 行号 → 那一行的 `face`**（★ `row.i.j` 那条）
    local n = Controller._pos_of_piece(Controller._piece_core, id)
    if n ~= nil then
      local _h2 = _m[n] or _m[tostring(n)]
      if _h2 ~= nil then return _h2 end
    end
  end
  -- ★ 旧路兜底：★ 关卡自己配的 `portrait`（★ 没有 `row.*` 的关卡走这条）
  if vm ~= nil and type(vm.tray) == "table" then
    for i = 1, #vm.tray do
      if vm.tray[i].id == id then return vm.tray[i].portrait end
    end
  end
  return nil
end

-- ★★★★★★ 2026-10-10 **标记的来源：那一行的 `letter`** ✗✓✓
--   ★★ 用户指令 ✓：「**像把内容填进 `clue` 的 `what` 一样，把 `letter` 的文本填进 `note` 里** ✓，
--     **和那个一样的路线**」✓✓
--   ★★ 一边是 `image`（头像 ✓）：`cd.suspect and Controller.portrait_of(vm, cd.suspect) or false` ✓
--     ★ 另一边（本函数 ✓）就是它 ✓ —— ★ **同构** ✓✓
--   ★ 值由单射带出来 ✓（★ `face` 是控件 ✗ 数据层到不了 ✓ ⇒ `letter` 同理 ✓）
-- ★★★★★★★★ 2026-10-11 **键 = 行号** ✗✓✓
--   ★ 入参 `id` 只有一个来源：★ `cd.suspect`（★ = `core.grid[r][c]` = 棋子 id）
--   ★★ 表里存的是 **行号**（★ `row.<关>.<行>` 那条线）
--     ⇒ ★ 这里先 **棋子 → 行号**（`_pos_of_piece`）再查 ✓
--   ★ 前几轮在这里翻车，全都是因为**擅自换了键**（`who` 文本）⇒ ★ 查表恒 miss
--   ★ 现在键与「用户配的那一行」**字面同一**（★ 就是他说的 `row.i.j`）✓
function Controller.letter_of(vm, id)
  local m = Controller._row_letter
  if m == nil then return nil end
  -- ★ 直查（★ 兼容"键就是 id"的老调用 ✓）
  local hit = m[tostring(id)]
  if hit ~= nil then return hit end
  -- ★★ 主路 ✓：★ **棋子 → 行号 → 那一行的 `letter`**（★ `row.i.j` 那条 ✓）
  local n = Controller._pos_of_piece(Controller._piece_core, id)
  if n == nil then return nil end
  return m[n] or m[tostring(n)]
end

----------------------------------------------------------------------------
-- ★★★★★ 2026-10-05 网格视窗（官方列表控件 `clues.grid`）—— 线索卡列表的正路
--
-- 用户的硬原则（原话）：
--   「位置大小都是原本摆好的，脚本只需要管可见性和交互，其它的干涉都是只会增加错误的操作」
-- ⇒ 本段代码**一个坐标都不碰**，只做四件事：**找控件 / 填内容 / 收点击 / 显隐**。
--   规划节点那条 `pos_runtime = false` 就是这条原则的落地（见 `build_layout` 里的注释）。
--
-- 已核对的事实（来自用户存档 `193.1.gil`，不再重复推导）：
--   · 网格视窗：id **1073742420**、名字 `clues.grid`、父 `clues`、400×544、局部 (20,20)
--   · 列表项模板：id **1073742421**（名 `clue`）、360×96，
--     子控件名 `clue.1.backrop1` / `clue.1.backrop2` / `clue.1.letter` /
--              `clue.1.what` / `clue.1.face` / `clue.1.who`
--   · 官方 API（`docs/api-cache/mhtakr07vej4.txt` 第 20 节 `ClientUIGridScrollerControl`）：
--       itemCount(只读) / itemPrefabIndex(读写) / scrollProgress(读写, Tweenable)
--       RefreshItems(itemCount, fun(control, index)) / GetItemIndex(control)
--       GetItemSize() / GetItemSpacing() / GetPadding() / ScrollToItemAt(index, align)
--     基础控件那边有：GetChild(name) / FindChild(path) / SetVisible / AddCursorEventListener
--   · 它是**客户端控件**（`ClientUI*`），和 `cell.*` 同一族 ⇒ 客户端脚本够得着。
--
-- ★ 三条官方语义决定了写法（都能在 API 缓存里查到）：
--   ① 「列表发生滚动时：对列表项内容进行刷新(触发回调)」
--      ⇒ 回调**会被反复进入**，而且是在我们那次 RefreshItems 之后很久（滚动时）。
--      ⇒ 回调里**只允许"按 index 现算"**：不许累加、不许假设只跑一次、
--        不许把"上一次填了什么"当输入（那是"复用列表项"最容易出的错）。
--   ② 「列表项索引以运行时传入和返回的 index 为准」
--      ⇒ 点到了哪一条，只能问 `grid:GetItemIndex(item)` 反查；
--        **不能**按兄弟序号（items 会被复用，顺序不稳定）。
--   ③ 回调的参数是 `(control, index)`，返回空 —— 内容全靠我们往子控件里写。
--
-- ⚠️ 已知**未验证**的能力（真机上要盯的两件事，见日志里的两行结论）：
--   · 列表项**能不能收到光标事件**（`AddCursorEventListener`）—— 官方没写死，
--     所以每一次调用都包 `pcall`，收不到就只失去"点列表项聚焦"这一个附加功能；
--   · **滚动由谁驱动**（引擎自身手势 / 还是脚本写 `scrollProgress`）—— 本轮不猜，
--     失败/不适用时把 `cfg.use_grid` 改回 false 就整体回到手写滚动。
----------------------------------------------------------------------------

-- 官方枚举的安全取值（与适配器里的 `E()` 同一个写法：缺失时返回 nil，调用点降级不崩）。
-- ⚠️ 离线测试里 `Enum` 是**全局 nil**（tests/board_bg.lua 故意不给），所以这里必须 nil-safe。
local function enum_at(path)
  local cur = Enum
  if cur == nil then return nil end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return nil end
  end
  return cur
end

-- 往一个控件写文字：文字控件才有 `text` 字段，写不进去不算错（返回 false 让调用方记账）。
--
-- ★ 空字符串**照写**（用户明确要求）：不写的话，"上一条残留的文字"会留在复用出来的
--   列表项上 —— 那是"滚动之后内容错位"的经典成因。空文字无害，残留有害。
local function write_control_text(ctrl, txt)
  if ctrl == nil or ctrl.text == nil then return false end
  local ok = pcall(function() ctrl.text = tostring(txt or "") end)
  return ok
end

-- 「这条结论只打一次」的小工具：能不能用、点了有没有反应，打一次就够，别每帧刷屏。
function Controller:_grid_log(key, msg)
  self._grid_logged = self._grid_logged or {}
  if self._grid_logged[key] then return end
  self._grid_logged[key] = true
  if print then print("[murdoku] " .. tostring(msg)) end
end

-- ★★★★★★★★ 2026-10-11 **把「第几行 → 哪个棋子 → 哪个字母」一次打全** ✗✓✓
--
--   ★★★ 为什么要它 ✗（★ 用户 2026-10-11 报"第三关 DEF 的 note 是 AAF" ✓）：
--     ★ 我离线复现过**第三关 7 行 7 棋子**那条链 ✓ ⇒ ★ 取的是**行号对应的行** ✓
--       （★ 探针：第4张卡 ⇒ D ⇒ `cell` note = 第4行配的那个字母 ✓）
--     ★★ 所以"字母不对"只剩下**一种**可能 ✗：
--       ★ **用户配的那一行的 `letter` 就不是他以为的那个** ✓✓
--         （★ 例如把第 1 关的行复制到第 3 关，只改了后面几行 ✓）
--     ★★★ 而脚本**只能照他配的显示** ✗ —— ★ 它**没有**办法知道"他想要 D" ✓
--   ⇒ ★ 所以正确的做法不是改代码 ✗ ★ 而是**把真相打出来** ✓：
--     ★ 一行一行列：★ `行号 / 棋子 / 字母`
--   ★ 他一看就能发现"第 4 行的 letter 写的是 A" ✓ ⇒ ★ **去编辑器改一个字** ✓✓
--   ★★ 只在**进关卡后第一次**打 ✓ ★ 每次填充最多打一次 ✓（★ 不刷屏 ✓）
--   ★ 读法 ✓：★ 若某行的 `棋子` 是 `?` ⇒ ★ 那一行的 **`who` 填的值既不等于棋子 id、
--     ★ 它也换不出棋子** ⇒ ★ **那一定是编辑器的配置问题** ✓（★ 脚本这时是诚实的 ✓）
function Controller:_dump_row_letter_map(lv_no, n)
  -- ★★ 判据必须是"`print` 在不在" ✗ —— ★ 不能写 `print ~= true` ✗✓
  --   ★ 我第一版就写成 `if print ~= true then return end` ✗
  --     ⇒ ★ 而 `print` 是**函数** ⇒ ★ **恒不等 true** ⇒ ★ **整段直接 return** ✓✓
  --       ⇒ ★ **一次都没打出来** ✓（★ 我实测过：输出里一行都没有 ✓）
  --   ★★ 教训 ✓：★ **"在线"和"能用"是两件事** ✗ —— ★ 要判的是"能不能调用" ✓
  if type(print) ~= "function" then return false end
  if self._row_map_dumped == true then return true end
  -- ★★★ 顺序很讲究 ✗（★ 我踩了两次 ✓）：★ **先确认有数据，再上闩锁** ✓
  --   ★ 我第一版先 `_row_map_dumped = true` ✗ ⇒ ★ 第一次调用时表还没建好 ⇒
  --     ★★ **闩锁上了、却什么都没打** ✗ ⇒ ★ **永远看不到那张表** ✓✓
  --   ★ 现在 ✓：★ 拿不到数据就**不闩** ✓ ⇒ ★ 下一次填充会**再试** ✓（★ 自带重试 ✓）
  local RT = rawget(Controller, "_row_text")
  local by = (type(RT) == "table") and RT[tostring(lv_no)] or nil
  if type(by) ~= "table" then return false end
  -- ★ 至少要有一行带 `letter` 才算"建好了" ✓（★ 否则等下一趟 ✓）
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

-- 网格视窗这条路上的**任何一步失败**都走这里：退回老路径（手写滚动），并且只报一次。
function Controller:_grid_fail(why)
  if self._grid_broken then return end
  self._grid_broken = true          -- 记住失败 ⇒ 以后不再重试（免得每帧刷同一句话）
  -- ★★★★★ 2026-10-05 **初值从 `"off"` 改成 `nil`** ✗✓ —— "线索区没出来"的**第二个原因** ✓
  --
  --   症状（真机日志 `23:13:32` 的排行榜 ✓）：
  --     · `clues.grid` 400x544 可见=**false** ✗ —— 而日志【同时】说
  --       「网格视窗：找到 clues.grid ✓ … RefreshItems 回调 7 次」✓ ⇒ ★ 它明明启用成功了 ✓
  --
  --   为什么：★ 规划里 `clues.grid` 的可见性是 `visible = (self._grid_state ~= "off")` ✓
  --     ⇒ ★ 只要 `_grid_state` 还是 `"off"` ✗ ⇒ **规划就把它写成 false** ✗✓
  --     ⇒ 而 `sync_clue_grid` 是**后面**才跑并把状态改掉的 ✓
  --     ⇒ ★★ 于是"启用成功之前的那些帧"它一直是 false ✗
  --        —— 而渲染的账本一旦记下 `visible=false`，之后没再变过就不会重发 ✗✓
  --
  --   ⇒ ★ 初值用 `nil`（= **还没判定** ✓）：`nil ~= "off"` 为真 ✓ ⇒ **规划先按"显示"给** ✓
  --     ★ 只有 `sync_clue_grid` **真的判定失败**时才会变成 `"off"` ✗ ⇒ 那时才藏 ✓✓
  --     ★ 这正是注释里那句"走不了网格视窗时把它藏起来"的原意 ✓ —— 原来那个 `"off"`
  --       把"还没判定"和"判定失败"**混成了同一个值** ✗（本项目反复踩的"两个状态一个值"✓）
  self._grid_state = nil
  self.dirty = true                 -- 让下一帧重画
  self:_grid_log("fail", "网格视窗：失败（" .. tostring(why)
    .. "）⇒ 退回老路径（手写滚动：▲▼ + 滚动条 + clue.N 卡片）")
end

-- ── 每帧渲染前调一次 ─────────────────────────────────────────────────────
-- 顺序：开关 → 找控件 → 取模板索引 → 设 itemPrefabIndex → RefreshItems 填内容。
-- 只有"这一步真的成了"才会把 `_grid_state` 置成 "on"，`build_layout` 据此让老的一套让位。
function Controller:sync_clue_grid(adapter)
  if adapter == nil or adapter.find == nil then return end

  -- ★★★★★★★★ 2026-10-11 **换关清表必须在【所有 early-return 之前】** ✗✓✓
  --
  --   ★★★ 为什么 ✗（★ 独立复核查出来的 ✓）：
  --     ★ 原来这一句在**后面**（`use_grid` 判断、`screen` 判断之后 ✓）
  --     ★★ 而下面 `cfg.use_grid == false` 那条路**直接 `return`** ✗
  --       ⇒ ★ 走老路径时**一次都不清表** ✓ ⇒ ★ 上一关的 `letter`/`face`/`row_text`
  --         会**带进新关卡** ✓✓（★ 那正是注释里说要防的那件事 ✓）
  --   ★ 今天为什么不发作 ✗：★ 默认 `use_grid = true` ✓（★ `main.lua` 的 `USE_GRID` ✓）
  --     ★★ 但"关掉网格回老路径"是这个项目**留着的一根退路** ✓
  --       ⇒ ★ 那条路上的坑不该留着 ✓
  --   ★ 开销 ✓：★ 一次字符串比较 ✓（★ 同一关内直接跳过 ✓ 本项目本来就是每帧调 ✓）
  self:_reset_row_maps_if_level_changed()

  -- ① 开关：默认**开**；只有显式 `false` 才完全不碰网格视窗
  local cfg = adapter.cfg
  if cfg ~= nil and cfg.use_grid == false then
    if self._grid_state == nil then
      self._grid_state = "off"
      self:_grid_log("off_cfg", "网格视窗：cfg.use_grid=false ⇒ 按配置走老路径（手写滚动）")
    end
    return
  end

  -- ② 只在**关卡里**碰它：主页/选关时这块区域整个是藏起来的（父级 `clues` 不可见），
  --    那时去 RefreshItems 既没意义、又可能因为"控件不可见 ⇒ 引擎不建列表项"而误判失败。
  -- ★★★★★ 2026-10-07 **"从别的屏回到关卡"时解开封死的网格判定** ✗✓
  --   用户实测（老问题 ✓）：
  --     · 退出至菜单 → 重进【同一关】⇒ 网格视窗**不渲染** ✗
  --     · 换一关进 ⇒ 正常 ✓   再换回来 ⇒ 正常 ✓   再退出重进 ⇒ 又不正常 ✗
  --   ⇒ 分水岭：**同一个控制器只改 `screen`** ✗  vs  **新控制器（`start_other`）** ✓
  --   机制：本函数下面的 `if self._grid_broken then return end` 是**永久闩锁** ✗ ——
  --     选关那一屏 `screen ~= nil` ⇒ 函数直接 return ✓ 但**之前**在关卡里若已判定失败，
  --     闩锁就留着了 ⇒ 重进同一关 ⇒ 永远 return ⇒ `_grid_state` 停在 "off"
  --     ⇒ 规划里 `clues.grid` 的 `visible` 恒为 false ⇒ **永不显示** ✓
  --   ⇒ 修法：★ **检测 `screen` 从"非 nil"跃迁到"nil"（= 刚进关卡）⇒ 允许重试一次** ✓
  --     换关走 `start_other` 是新建控制器 ⇒ 本来干净 ⇒ 不受影响 ✓
  if self.screen == nil and self._grid_last_screen ~= nil then
    self._grid_broken = nil
    self._grid_tries = 0
    self._grid_state = nil
    self._grid = nil
  end
  self._grid_last_screen = self.screen  if self.screen ~= nil then return end

  -- ★★★★★★ 2026-10-11 **换关时必须清掉上关带出来的两张表** ✗✓✓
  --
  --   ★★ 为什么必须清 ✗：★ `Controller._row_letter` / `_row_face` 是**模块级**的 ✓
  --     （★ 见 `portrait_of` / `letter_of` 那两段注释：★ 它们要能被静态函数读到 ✓
  --       ★ 所以**不能**挂在 `self` 上 ✗）
  --     ⇒ ★★ 而它们**跨控制器存活** ✗ —— ★ `start_other` 新建控制器 ✓
  --       ★ **这张表却是同一个** ✓✓
  --   ★ 不清会怎样 ✗（★ 两条都实测过 ✓）：
  --     ★ ① ★ **某一关的 `row.<关>` 是空的** ✓（例如第 4 关 —— ★ 它没有对应行 ✓）
  --       　⇒ ★ 那一关**一个 letter 都不写** ✓ ⇒ ★ **表里留着上一关的值** ✗
  --       　⇒ ★★ **那一关的人会显示【别的关】配的字母** ✓✓
  --     ★ ② ★ 同一个"人"在不同关配了不同字母 ⇒ ★ **先到先得** ✗
  --       　⇒ ★ **这一关看到的是上一关先写的那个** ✓（★ 而这一关本来配了别的 ✓）
  --   ⇒ ★★ 修法 ✓：★ **进关卡时按【关卡身份】清一次** ✓
  --     ★ 用签名（`level.id`）比对 ✓ ⇒ ★ 同一关内**不会被反复清** ✓（★ 否则每帧都清 ⇒ 永远空 ✗）
  --   ⚠️ ★ 为什么放在**这里**而不是 `new` ✗：★ `new` 是构造时 ✓ 那时还不知道进的是哪一关 ✓
  --     ★ 而 `screen` 从非 nil 变 nil 就是"**刚进关卡**"的那一刻 ✓（★ 本段上面就是它 ✓）
  self:_reset_row_maps_if_level_changed()

  -- ③ 已经失败过就不再重试（老路径接管；`_grid_state` 已经是 "off"）
  if self._grid_broken then return end

  -- ④ 找控件：先 `clues.grid`（存档里核对过的名字），找不到再用中文名兜一次
  local grid = self._grid
  if grid == nil then
    -- 前 120 次渲染每次都试（约 2 秒）：控件是存档里就有的，正常情况下第一次就能拿到；
    -- 万一 UI 树还没就绪，也给足重试机会。之后不再试，免得每帧白扫一遍控件树。
    if (self._grid_tries or 0) >= 120 then return end
    self._grid_tries = (self._grid_tries or 0) + 1
    pcall(function() grid = adapter:find("clues.grid") end)
    if grid == nil then
      -- 防御（一行）：万一编辑器里用了中文名「网格视窗」
      pcall(function() grid = adapter:find("网格视窗") end)
    end
    if grid == nil then
      self:_grid_log("missing", "网格视窗：找不到 `clues.grid`（也试过中文名「网格视窗」，"
        .. "已经试了 " .. tostring(self._grid_tries) .. " 次）⇒ 继续走老路径（手写滚动）")
      if self._grid_tries >= 120 then
        -- 试满就**判定"这一关没有网格视窗"**：把它按不可用处理（`clues.grid` 保持隐藏），
        -- 老路径独占这块区域 —— 免得"找不到 ⇒ 一直重试 + 网格和老卡片同时亮着"。
        self._grid_state = "off"
        self:_grid_log("missing_final", "网格视窗：试满 120 次仍拿不到控件 ⇒ 判定不可用，"
          .. "`clues.grid` 由脚本按不可见处理，老路径（手写滚动）接管")
      end
      return
    end
    self._grid = grid
  end

  -- ⑤ 列表项模板索引：**只从 cfg 取**，这里不写死数字
  --    （数字的唯一来源在 main.lua 的 `Murdoku.GRID_ITEM_PREFAB` —— 两处写死必然漂移）
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

  -- ⑥ 填内容：只在**条数变了**时重发 RefreshItems。
  --    官方写明滚动时引擎自己会再进回调 ⇒ 这里不必每帧重发
  --    （每帧重发会把滚动位置顶回去，而且纯属浪费）。
  --
  -- ★★★★★ 2026-10-05 **条数别再用 `core:view()` 去数** —— 那个守卫挡不住它。
  --
  --   实测（`tests/grid_cost.lua`）：`_grid_sig` 这道守卫**确实**挡住了重复的
  --   `itemPrefabIndex` 写入与 `RefreshItems`（300 帧里 grid_refresh=0），
  --   但它**挡不住**守卫之前那句 `self.core:view()`：整视图重建 **0.235 ms/次**，
  --   而 `render` 在真机上是**每帧**都跑的（`Controller:tick` 每帧 `self.dirty = true`，
  --   `Murdoku.on_update` 见 dirty 就重绘 —— 离线实测 300 帧 = 300 次 render）。
  --   ⇒ 白白每帧多花 0.235 ms（还要多制造一批垃圾表给 GC）。
  --   ⚠️ ★ 这段旧注释写着「条数与 `#vm.clues` **恒等**（`clue_results()` 对 `level.clues` 一对一映射）」
  --      ⇒ ★★ **那条前提在 2026-10-11 被打破了** ✗✓（★ 详见下面那段 ✓）
  -- ★★★★★★ 2026-10-11 **必须读 `core.clues`，不能读 `lv.clues`** ✗✓✓
  --
  --   ★★★ 用户报 ✓：「★ **网格视窗消失了** ✓
  --     ★ **这个部分不能坏** ✓ ★ **不然整个 `row` → `clues` → 棋盘的路线就断了**」✓✓
  --
  --   ★★ 我改出的事故 ✓（★ 本轮 ✓）：
  --     ★ 用户定「★ **`clues` 条数由棋盘容量决定**」✓ ⇒ ★ **真关卡的 `lv.clues` 就【空了】** ✓
  --       （★ 条数改由 `Core.new` 按容量生成到 **`self.clues`** ✓）
  --     ★★ 而这一行**还在读 `lv.clues`** ✗ ⇒ ★ **`n` 恒为 0** ✗✓
  --       ⇒ ★ `grid:RefreshItems(0, …)` ⇒ ★ **一个列表项都不建** ✓
  --       ⇒ ★★ **网格视窗整块消失** ✓✓
  --   ★ 旧注释还写着"条数与 `#vm.clues` **恒等**"✗ —— ★★ 那条**前提被这次改动打破了** ✗✓
  --     ★（★ 这正是本项目最怕的"注释里的前提悄悄失效" ✓ 而我正是踩它的那个人 ✓）
  --
  --   ★ 修法 ✓：★ **读核心那份 `core.clues`** ✓ ——
  --     ★ 它**永远是"这一关有几条"的权威** ✓（★ 手写的用你的 ✓ 没手写的按容量生成 ✓）
  --     ★★ 于是"条数与 `#vm.clues` 恒等"这条**重新成立** ✓ ✓
  local n = 0
  do
    local core = self.core
    if core ~= nil and type(core.clues) == "table" then
      n = #core.clues + ((type(core.general_clues) == "table" and #core.general_clues > 0) and 1 or 0)   -- ★ 有通用线索 ⇒ 列表多一条（在最上面）
    else
      -- ★ 兜底 ✓：★ 核心还没建起来 ⇒ ★ 退回读关卡数据 ✓（★ 老行为 ✓ 不崩 ✓）
      local lv = core and core.level
      n = #((lv and lv.clues) or {})
    end
  end
  -- ★ 2026-10-10 **记下总条数** ✓ —— 点击处理要用它算"溢出几项"✓
  --   ★ 为什么点击处理需要它 ✗：★ 那里只有 `GetItemIndex`（拿到的是**被点项的索引** ✓）
  --     ⇒ ★ 要判"这一项是不是空白占位项" ✓ 就得知道"一共几条、一屏几条" ✓
  --     ★ 一屏容量由 `_grid_visible_count()` 现算 ✓；总条数记在这里 ✓
  self._grid_blank_total = n
  local sig = tostring(n)
  -- ★ 2026-10-10 **先在原地刷新一遍，再走签名门** ✗✓
  --   ★ 这是"点一下弹回顶部"的治本一步 ✓：
  --     ★ 要刷新高亮/灰白时，只需对**记得的句柄**再跑一遍填充 ✓
  --     ⇒ ★ **不重发 `RefreshItems`** ✗ ⇒ ★ 引擎不会重置滚动 ✓✓
  --   ⚠️ 只有"待刷新"时才跑 ✓ ⇒ 稳态零成本 ✓
  if self._grid_refill_pending then
    self._grid_refill_pending = nil
    local _rn = self:_grid_refill_now(adapter, grid)
    if _rn > 0 then
      self._grid_refill_n = (self._grid_refill_n or 0) + 1
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：就地重填　原 L3913..L3917
    end
  end
  if self._grid_state == "on" and self._grid_sig == sig then return end

  local ok_set, set_err = pcall(function() grid.itemPrefabIndex = prefab end)
  if not ok_set then
    self:_grid_fail("设 itemPrefabIndex 失败：" .. tostring(set_err))
    return
  end
  -- 回读一份当证据（只读字段在某些实现上会滞后，所以**不作为失败依据**，只打进日志）
  local back = nil
  pcall(function() back = grid.itemPrefabIndex end)

  self._grid_calls = 0          -- 这一次 RefreshItems 里回调被进入了几次
  -- ⚠️ **不要重置 `_grid_base`**：它只在"这辈子第一次回调"时判定（那一次一定是列表顶端，
  --    因为列表刚建、还没滚动过）。重置的话，"条数变了但滚动位置还在中间"时会把
  --    中间那一项的 index 当成起点 ⇒ 0 起的那种实现会被误判成 1 起 ⇒ 整列错位一条。
  --
  -- ★ `_grid_in_refresh` 用来区分「回调是被**我们这次调用**带进来的」还是「引擎在滚动时
  --   自己重进的」 —— 后者是**本项目一个关键的未验证点**，见到就报一行（见 `_fill_grid_item`）。
  self._grid_in_refresh = true
  local ok_ref, ref_err = pcall(function()
    grid:RefreshItems(n, function(item, index)
      -- ★ 官方：滚动时**引擎会再进这个回调** ⇒ 这里再包一层 pcall：
      --   万一某一行出错，只该"这一次没填上"，**不该把引擎的滚动一起打断**。
      local ok_cb, cb_err = pcall(function() self:_fill_grid_item(adapter, grid, item, index) end)
      if not ok_cb then self._grid_cb_err = tostring(cb_err) end
    end)
  end)
  self._grid_in_refresh = false
  -- ★★ 把"行 → 棋子 → 字母"对照表打一次 ✓（★ 见 `_dump_row_letter_map` ✓）
  --
  --   ★★★ 为什么放在**这里** ✗（★ 我放错过两处，都实测过 ✓）：
  --     ★ ① 放进 `if wrote > 0 then` 里 ⇒ ★ 真机上 `wrote` 常常是 0 ⇒ **一次都不打** ✓
  --     ★ ② 放进单射那个 `if _row_need then … end` 块里 ⇒ ★ 同理可能整块不跑 ✓
  --     ★ ③ 放进 `_fill_grid_item` 主干 ⇒ ★ 那时 `_row_text` 可能才建到第 1 行 ✓
  --   ⇒ ★ 放在**这里** ✓：★ `RefreshItems` **刚把 n 项全回调完** ✓
  --     ⇒ ★ 7 行的表**已经建齐了** ✓ ⇒ ★ 一打就是完整的 7 行 ✓✓
  --   ★★ 自带"有数据才上闩锁"的重试 ✓ ⇒ ★ 第一趟没齐就等下一趟 ✓（★ 不刷屏 ✓）
  pcall(function() self:_dump_row_letter_map(self:_level_ordinal(), n) end)

  -- ★ 只读探针 ✓：数"视窗里物理上挂了多少个子控件"✗（= 引擎真的建了几个列表项 ✓）
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：探针·RefreshItems　原 L3950..L3957
  local calls = self._grid_calls or 0
  if (not ok_ref) or (calls == 0 and n > 0) then
    self:_grid_fail("RefreshItems " .. ((not ok_ref) and ("抛错：" .. tostring(ref_err))
      or ("一次回调都没进来（n=" .. tostring(n) .. "）")))
    return
  end

  self._grid_sig = sig
  -- ★★★★★★ 2026-10-10 **模板实况：把"存档里的位置"和"运行时的位置"对上** ✗✓✓
  --   ★★ 用户报 ✓：「**第壹周刊卡被画到 −2 这个问题又回来了**」✗
  --   ★ 我查了存档 ✓：★ `clue` 的 `pos=(0, 0)` ✓、★ `clues.grid` 也是 `(0,0)` ✓
  --     ⇒ ★★ **存档侧是对的** ✗ ⇒ ★ **那偏移只可能在【运行时】** ✓
  --   ★ 本行把三个关键控件的**运行时**尺寸/位置打出来 ✓：
  --     ★ 模板 `clue`（★ 它就是列表项的布局基准 ✓）
  --     ★ `clues.grid`（★ 视窗 ✓）★ `clues`（★ 容器 ✓）
  --   ⇒ ★ 一眼能看出：★ **谁在运行时被挪了** ✓（★ 存档说 0 而运行时不是 0 ⇒ 就是它 ✓）
  if not self._tpl_logged and print then
    self._tpl_logged = true
    for _, nm in ipairs({ "clue", "clues.grid", "clues" }) do
      local c = nil
      pcall(function() c = self:_find_by_name(nm) end)
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：模板实况　原 L3979..L3989
    end
  end
  self._grid_state = "on"

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-09 **几何探针：把引擎【自己算出来】的那几个数打出来** ✗✓
  --
  --   ★ 为什么需要它 ✓（用户原话 ✓）：
  --     「我能在线索卡可见区域内选中三个，而**第一行上方还有可选中内容**，
  --       滚轮列表**之上**的区域我选到了第四个人，也就是说**原本的填入方式有问题**，
  --       确实把线索**填到了不该有的地方**」✗
  --     ⇒ ★ 换成选关条就是"**填进去的关卡错位**" ✓ 同一个根 ✓
  --
  --   ★ 官方原文给的两条（`get_client_document("网格视窗控件")` ✓）：
  --     · ★「列表采用**复用列表**结构，出于性能考虑，**仅会加载处于可见范围内的列表项**」✓
  --       ⚠️⚠️ **2026-10-09 更正：我当初把这句【读错了】** ✗✓ —— 这条误读误导了好几轮 ✗
  --         原话（错 ✗）：「⇒ 引擎**自己就裁剪** ✓ ⇒ 所以"填多了不裁"**不是**原因 ✗」
  --         ★ 正解 ✓：这句讲的是「**加载**哪些项」（★ **性能机制** ✓）
  --           ⇒ ★ **它【不是】"会裁掉超出部分的显示/射线"** ✗
  --           ⇒ ★★ **我据此把"不裁"这条正确方向**排除掉了 ✗ ⇒ 白烧了好几轮真机 ✓
  --         ★ **官方真正表明立场的原文在【消息队列控件】那篇** ✓
  --           （`docs/api-cache/mhs1f7ibtc6c.txt:33-35` ✓ 资料员扫全部 44 篇找到的 ✓）：
  --             ★「消息队列数据的最大数量**超出消息队列控件的显示范围**时，
  --                在消息项素材组中添加的界面动效**无法被裁切**
  --                **不推荐**将消息队列的最大消息数量配置为**超出消息队列控件大小的值**」
  --           ⇒ ★★ **同一套 UI 系统的官方立场**：
  --             ① **超出部分不会被裁** ✗　② ★ **官方建议：别让数量超出控件尺寸** ✓✓
  --     · ★「**排列限制和预览数量**：将**预览数量**对应的列表项展示在界面中，
  --         以**模拟实际运行时**的效果」✓
  --       ⇒ ★ 存档里 `#80/511 = 5` 只是**编辑器预览数量** ✓ **不是运行时限制** ✗
  --
  --   ★★ 另一个更正 ✓（同一个坑 ✓）：我读存档时把 `/80/502` 等看成"**空消息**" ✗
  --     ★ 真相 ✓：那些是 **`wt=5`（32 位浮点）** ✓ —— ★ 值存在 `f` 字段里，
  --       **`payload` 长度天然是 0** ✗ ⇒ ★ **按字节数判空的打印器会把浮点叶子全显示成 `0B`** ✓
  --     ⇒ ★ **配置其实是【填好的】** ✓：`/80/502=(360,96)` `/503=(8,8)` `/504=(20,20)` `/505=(20,20)` ✓
  --       ★ 而且与真机 `GetItemSize/GetItemSpacing/GetPadding` **逐项吻合** ✓
  --       ★ `GetContentLength()=760` = `20+7×96+6×8+20` **分毫不差** ✓✓
  --     ⇒ ★ **教训** ✓：★「**打印出来是 `0B`」≠「字段是空的」** ✓ ——
  --       与"扫过文本了 ≠ 扫过内容了"**同一族** ✓ ⇒ 我把这条记进查证纪律了 ✓
  --
  --   ★ 而官方**没有**说明的两件（所以只能实测 ✓）：
  --     ① 列表项模板自己的**位置**算不算数？（模板 `clue` 实测在 `(-6, 212)` ✗ 不在 (0,0)）
  --     ② `scrollProgress` 归不归零？（★ 若用户滚过 ⇒ 列表上移 ⇒ "第一行"其实不是第一项）
  --
  --   ★★ 好在这几个官方接口**都能运行时读** ✓（`ClientUIGridScrollerControl` ✓）：
  --     `itemCount`(只读) · `scrollProgress`(读写) · `GetItemSize()` · `GetItemSpacing()`
  --     `GetPadding()` · `GetContentLength()` · `scrollDirection`(只读) · `layoutConstraint`(只读)
  --     `layoutConstraintFixedCount`(只读)
  --   ⇒ ★ **一次就能算出**"引擎认为内容有多长" vs "视窗有多高" ✓
  --     · 若 `GetContentLength()` == 视窗高 ⇒ ★ 内容没超 ⇒ 但用户看到了第 4 个人 ⇒ **错位** ✗
  --     · 若 `scrollProgress` ≠ 0 ⇒ ★ 列表被滚上去了 ⇒ **"第一行"不是第一项** ✓✓
  --     · 若 `GetItemSize()` ≠ 存档里的 360×96 ⇒ ★ 引擎用的不是存档那个尺寸 ⇒ 布点基准不同 ✓
  --   ⇒ ★ 这一行日志能一次分清上面三种 ✓ —— 别再猜 ✓
  -- ★ 2026-10-18（优化组 · P0）：**网格几何探针的"空壳"整段删除** ✗✓
  --   原文是一个 `if (self._grid_geom_log or 0) < 3 and print then … end`：
  --     里面只声明了 `_f` / `_one` / `_cg2` 三个**从未被读**的 local，
  --     外加一句"网格几何1/2/3 已删（原 L4060..L4077）"的注释 ⇒ 一段什么也不做的壳。
  --   判据：三个 local 在本文件**零引用**（只出现在这个 if 体内）⇒ 整块是死代码。
  --   ⚠️ 真正的网格体检另有实现（`_grid_*` 家族 + `tests/grid_cost.lua` 守着），不受影响。

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **绕过规划/账本，直接点亮 `clues.grid`** ✗✓ —— 真凶在此 ✓
  --
  --   ★ 为什么规划那条路不行（★ 诊断2 真机实测 ✓）：
  --     ★ 规划 `visible=**true**` ✓ · `在nodes=true` ✓ · `在seen=true` ✓ · `上帧在shown=true` ✓
  --     ★★ 而★ **读回 `visible=false`** ✗✗ ⇒ ★ **属性【发了也无效】** ✓✓
  --   ★★ 铁证（★ 同一份日志里 ✓）：★ 诊断二手动 `SetVisible(true)` ⇒ **回读仍 `false`** ✗✓
  --     ★ 而★ 构建标记自己写着 ✓：
  --       ★「要显示时**显式补 `SetActive(true)`**（★ 手写树漏写 `active` **会少一层可见性**）」✓✓
  --   ⇒ ★★★ 修法 ✓：★ **拿到句柄的那一刻直接调** ✗
  --     ★ 不走 `build_layout` / 不走账本 / 不等 30 帧 ✓ ⇒ ★ **没有可失效的中间层** ✓✓
  --   ⚠️ 每次 `sync_clue_grid` 成功都补一遍 ✓（★ 它自己有 `_grid_sig` 守卫 ⇒ 不是每帧 ✓）
  --   ★★ 顺带把 `pos_runtime = false` 那条也绕开 ✓（★ 那是几何 ✓ 这里只碰可见性 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
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
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：诊断3　原 L4104..L4109
    end
  end

  -- ★★★★★ 2026-10-05 **`RefreshItems` 成功 = 引擎刚往树里塞了列表项 ⇒ 控件名缓存作废。**
  --
  --   为什么要在这里触发：列表项（`clue.1.who` …）是**引擎**在 `RefreshItems` 里实例化的，
  --   不经过脚本的 `create_control` —— 也就是说，"新建控件"那条事件**看不见它们**。
  --   而这些列表项挂在 `clues.grid` 下面，`clues` 在主页/选关页是**藏起来的**
  --   （`apply_screen_hide`）：新实例化出来的列表项自己是 visible=true，
  --   必须靠兜底隐藏压下去（实测：选关页那一趟有 8 次 `SetVisible` 打在网格子树上）。
  --   ⇒ 一次刷新触发一次；`_grid_sig` 那道守卫保证**不是每帧**（300 帧里这里只进 0~1 次）。
  if adapter ~= nil and adapter.invalidate_lookups ~= nil then
    pcall(function() adapter:invalidate_lookups("grid_refresh:n=" .. tostring(n)) end)
  end

  -- 回调里抛过错 ⇒ 只报一次（不整体回退：那一条没填上而已；反复出现才值得关掉这条路）
  if self._grid_cb_err ~= nil then
    self:_grid_log("cberr", "网格视窗：列表项填充回调抛过异常（" .. tostring(self._grid_cb_err)
      .. "）—— 已按「这一次没填上」处理；反复出现就把 cfg.use_grid 改回 false")
  end

  -- ⑦ 一行**带证据**的结论（用户要的就是这一行，能据此判断链条走到哪一步）
  -- ★★ 2026-10-11 **把"绑了几个项"也打出来** ✗✓（★ 用户指定要能一眼看断点 ✓）
  --   ★ 为什么必须 ✗：★ 原来的"列表项点击=支持"**只证方法存在** ✓
  --     ★ 而 `_grid_bind_n` 是**真的走完绑定那一步的次数** ✓ ⇒ ★ 两者一起看才分得清 ✓✓
  --   ★ 读法 ✓：★ `绑=N` 且点卡片**没有**「卡片点击进来了」⇒ ★ 事件没到引擎派发那一步 ✓
  --     ★ `绑=0` ⇒ ★ **绑定根本没跑到**（★ 就是"提前 return"那一类 ✓）
  self:_grid_log("summary", string.format(
    "网格视窗：找到 clues.grid ✓ itemPrefabIndex=%s（回读 %s） n=%d RefreshItems 回调 %d 次；"
    .. "索引基准=%s；列表项点击=%s；★ 绑定次数=%s",
    tostring(prefab), tostring(back), n, calls,
    (self._grid_base == nil) and "?" or tostring(self._grid_base),
    (self._grid_click_ok == true) and "支持（用 GetItemIndex 反查索引）"
      or "不支持（列表项收不到光标事件 ⇒ 只能用老卡片的点击，聚焦仍可用）",
    tostring(self._grid_bind_n or 0)))
end

-- 列表项的子控件：模板里叫 `clue.1.<后缀>`（用户是**照着第 1 张卡**另存的模板）。
--   ⚠️ 引擎若按实例序号改名（`clue.<序号>.<后缀>`）也必须命中 ⇒ 四种名字依次试：
--      引擎给的 index → 换算后的位置 pos → 模板原样 `clue.1.*` → 裸名 `<后缀>`
--      （顺序 = 从最具体到最宽松；第一种命中就返回，不会串到别的子控件上）
--   返回值：命中的子控件 + **命中的是第几种名字**（1..4；0 = 都没命中）。
--   为什么要回传"第几种"：第 1/2 种的**名字里带 index** —— 万一引擎真的按序号改名，
--   同一个列表项被回收给别的 index 之后，旧句柄就指向错的子控件了。
--   第 3/4 种（`clue.1.*` / 裸名）与 index 无关 ⇒ 换 index 也还是同一个子控件。
--   缓存层（`_grid_item_child_cached`）就靠这个数决定"能不能跨 index 复用"。
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

-- ★★★★★ 2026-10-05 **列表项「子控件句柄」的记忆表**（这一轮卡顿的直接病根之一）。
--
--   用户硬证据（同一台设备对比两个包）：
--     · `191-位置交给编辑器.gil`（v058，**网格视窗之前**）：流畅 ✓
--     · 当前（v069，**带网格视窗**）：明显流畅，但"对比之前还是略有卡顿" ✗
--   ⇒ 回退是网格视窗那一轮引进来的（v067/v068 修的两条补发热路 + v069 收紧上限都没治好）。
--
--   离线实测（`tests/grid_cost.lua`，7 个可见列表项，与真机同形状的模板命名）：
--     **一次 RefreshItems 回调 = 54 次 `item:GetChild` + 7 次整视图重建 + 21 次文字写入**
--     （54 = 每个角色依次试名字，命中前平均要试 2.6 次 × 3 个角色 × 7 项）。
--   而官方写明「**列表发生滚动时：对列表项内容进行刷新(触发回调)**」
--   ⇒ 滚动期间这三个数就是**每帧**的开销：54 次引擎调用 + 7×0.235ms 的 Lua 重建
--     + 21 次文本重排 —— 真机表现正是"明显流畅，但对比之前还是略有卡顿"。
--
--   ⇒ 这里把"这个列表项的这个角色是哪个子控件"记下来，键 = **列表项控件身份**：
--     · 弱键（`__mode = "k"`）：引擎回收列表项之后条目自动释放，不会越攒越多；
--     · 控制器是**每关新建**的（`Murdoku.start` → `UIC.new`）⇒ 天然不会跨关缓存。
--
--   ⚠️ 两条复用规矩（都不是拍脑袋，各有一条理由）：
--     ① **同一个 index** ⇒ 引擎这一轮没回收过它 ⇒ 句柄一定还有效，直接用；
--     ② **命中第 3/4 种名字**（`clue.1.*` / 裸名，名字与 index 无关）⇒ 换 index 也还是它；
--     其余情况（index 变了、而当初是靠 `clue.<index>.*` 命中的）**必须重查** ——
--     那正是"引擎按序号改名"的实现下唯一会串到别处的组合。
--   ⚠️ **查不到不缓存**（照 `Adapter:sub` 那条"查不了 = 不存在"踩过一整天的教训）：
--     模板里少一个子控件时，下次回调还会再试，而不是永远当成"没有"。
function Controller:_grid_item_rec(item, index)
  if item == nil then return nil end
  local cache = self._grid_kids
  if cache == nil then
    cache = setmetatable({}, { __mode = "k" })      -- 弱键：列表项被回收后不攒着
    self._grid_kids = cache
  end
  local rec = cache[item]
  if rec == nil then
    rec = { idx = index, hit = {}, variant = {} }
    cache[item] = rec
  end
  return rec
end

-- ★★★★★ 2026-10-10 **单射：`assets/row.<关卡序>.<行序>`** ✗✓
--
--   ★★ 用户要求 ✓（原话 ✓）：
--     「我需要**一个区域让我指定第几关第几行填什么**」✓
--     「现在**第几关第几行怎么填是没有定式的**」✗
--     「先把这个**单射**做好了，有了这个**一一映射**再查显示问题会更方便」✓
--     「建立这个单射的过程中**说不定就顺手解决**这个问题了」✓✓
--   ★★ 已经建好的（存档实证 ✓）：
--     `assets` 的子控件 9 个 = **`row.1.1` … `row.1.5`** ＋ `portrait.A/B/V/D` ✓
--     ⇒ ★ **约定就是**：★ **`row.<关卡序>.<行序>`** ✓（★ 你建的 `row.1.*` = 第 1 关 ✓）
--   ★★ 用法（★ 完全由你在编辑器里定 ✓ 脚本不猜内容 ✗）：
--     · 在 `assets` 下放一个容器 ✓ 名字 `row.<关卡序>.<行序>` ✓
--     · ★ **在它里面放子控件，子控件的【名字】= 卡片上的槽位名** ✓：
--       `who` / `what` / `letter` / `face` / `backrop1` / `backrop2` / `gray` ✓
--     · ★ 文本控件 ⇒ 它的文字会写到卡片同名槽位 ✓
--     · ★ 图片控件 ⇒ 它的 `imageId`/`imageSource` 会写到卡片同名槽位 ✓
--     · ★ **没配的行 ⇒ 自动回落到现在的算法** ✓（★ 向后兼容 ✓ 不会因为没配就空着 ✓）
--   ★ 为什么这样最省 ✓：★ 内容全在**编辑器里可视化摆** ✓
--     ⇒ ★ 不需要脚本里写死任何"第几关第几行是什么" ✓✓
-- ★ 只读 ✓：本函数只**取**控件，不写任何东西 ✓
-- ★★★★★ 2026-10-10 **全树按名找控件** ✗✓ —— ★ `#503` 不全时的救命路 ✓
--
--   ★★ 用户实测 ✓：「我补的 **3.9 和 3.1 恢复原样了**」✗
--     ＋「**我导出的 `269` 重新导入是正常的**」✓
--   ⇒ ★ 读回实证 ✓：★ 这两行的 **`#503` 是空的** ✗（★ 子控件在，但没进子列表 ✓）
--     ⇒ ★ **`row:GetChildren()` 拿不到它们** ✓ ⇒ 单射一个槽位都写不到 ✓
--   ⇒ ★★ 而**名字是确定的** ✓：`<槽位>.<关>.<行>` ✓（★ `who.3.1` 这种 ✓）
--     ⇒ ★★★ **按名全树找一定能拿到** ✓✓
--   ★ 入口同 `_palette_child` ✓：★ `game.GetClientUIRoots()` ＋ 限深走树 ✓（★ 不用缓存句柄 ✗）
--   ★ 全程**只读** ✓ 每步单独 pcall ✓
-- ★★★★★★ 2026-10-10 **往下找【能设图】的控件** ✗✓✓
--
--   ★★★ 用户推断 ✓（很准 ✓）：「**现在的头像不是图片而是模板引用控件** ✓，
--     **所以是不是需要再往上追一层去读模板里的内容而不是只读控件内容**」✓✓
--
--   ★ 事实 ✓：★ `face.<关>.<行>` 是【**模板引用控件**】✗ —— ★ 不是图片控件 ✓
--     ⇒ ★ `face.imageId` / `face:SetImage` 对它**都不适用** ✗
--     ⇒ ★★ **真正的图在它引用的模板【里面】** ✓ ⇒ ★ **要往下钻** ✓
--   ★ 同理 ✓：★ **卡片那侧的 `face` 也是**（★ 同一个模板体系 ✓）⇒ ★ 两边都要钻 ✓✓
--   ★ 而我原来的"下钻"**只找 `text`** ✗ —— ★ 从未为图片钻过 ✓
--     （★ 日志那行 `★ 单射下钻失败：face 及其子孙【都没有 text】` 正是这个 ✓）
--
--   ★ 判据 ✓：★ 控件有 `SetImage` ✗ 或 `imageId` ✗ ⇒ ★ 就是它 ✓
--   ★ 广度优先 ✓ 最多下钻 4 层 ✓ 全程 pcall ✓
--   ★★★★★★ 2026-10-11 **广度优先原来只走了一层** ✗✓✓（★ 真 bug ✓ 已修 ✓）
--
--     ★ 原写法 ✓：`for qi = 1, #q do` ＋ 循环里 `q[#q + 1] = kk` ✗
--     ★★ Lua 的**数值 `for` 在进入时只求值一次上界** ✓（`#q` 被**冻结** ✗）
--       ⇒ ★ 队列就算在后面变长，`qi` 也不会再推进 ✓
--       ⇒ ★★ **只扫"根的直接子控件"这一层** ✗ —— ★ 注释写着"广度优先"✓ 实际不是 ✓✓
--     ★ 最小复现（本机 Lua 5.3 ✓）：`q={a}`／`for qi=1,#q do q[#q+1]=a end` ⇒ ★ 只迭代 1 次 ✓
--     ★ 影响面 ✓：★ 图片那条路（本函数 ✓）与文字那条路（我抄的同一个形状 ✗）都中 ✓
--       ⇒ ★ "`face` 的图在模板里面 ⇒ 要往下钻"这句话**从来没真正执行过** ✗✓
--     ★ 修法 ✓：★ 换成 `while qi <= #q do … qi = qi + 1 end` ✓
--       ★（或 `repeat` ＋ 显式计数 ✓）—— ★ 判据：**上界每轮重算** ✓✓
-- ★ 只读 ✓：本函数只**取**控件，不写任何东西 ✓
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

-- ★★★★★★ 2026-10-11 **读一个控件（或它模板里的那份）的文字** ✗✓✓
--
--   ★ 为什么要单独一个函数 ✗：★ 原来这段"读文字"被**抄了两份** ✓
--     （早期单射一处 ✓、末次单射一处 ✓）★ 而两处都只有一条路 ✓：
--     `pcall(function() txt = k.text end)` ✗ —— ★ `k.text` 是 nil 就全盘落空 ✓
--   ★ 与 `_find_image_holder` **完全同形** ✓：
--     ★ 图片那边早就知道"`face` 是模板引用控件 ✗ ⇒ 要往下钻" ✓
--     ★ 文字这边**同一个道理** ✓ —— ★ 用户配的那段字挂在【模板里那份】上 ✓
--       ⇒ ★ 引用控件的 `.text` **不保证**是那段字 ✓（★ 真机读不到就是这条 ✓）
--   ★ 三层判据（严 → 宽）✓：
--     ① ★ 自有 `.text` 非空 ⇒ 直接用 ✓（★ 普通文本框走这条 ✓）
--     ② ★ `FindChild("<槽位名>")` ⇒ ★ 引用出来的那份，**同名子控件** ✓
--        （★ 名实相符 ✓ —— 比"随便找第一个有 text 的子孙"准得多 ✗）
--     ③ ★ 广度优先找第一个 `text` 非空的后代 ✓（★ 兜底 ✓ 最多 4 层 / 60 个 ✓）
--   ★ 全程 pcall ✓ ★ 只读 ✓ ★ 不写任何东西 ✓
--   ★ 返回 **string** 或 **nil** ✓（★ 调用方只管 nil 与否 ✓）
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
  -- ★★★★★★ 2026-10-11 **必须用 `while`（不能 `for qi = 1, #q`）** ✗✓✓
  --   ★★ Lua 的数值 `for` **进入时只求值一次上界** ✓ ⇒ ★ 队列后面变长也不推进 ✓
  --     ⇒ ★ 那样"广度优先"实际**只扫一层** ✗（★ 本文件 `_find_image_holder` 就中过这条 ✓
  --       ★ 2026-10-11 同批修掉 ✓）
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
  -- ★★★★★ 2026-10-10 **换成"走树"，不再用 `adapter:find("root")`** ✗✓
  --
  --   ★★★ 真机日志（v129 ✓ 原文 ✓）证明单射没通的原因就是取不到：
  --     `★ 按名取：assets=false  portrait.<id>=false` ✗
  --     `★ 调色板里没有素材「portrait.B」。当前调色板：（空 —— 找不到 assets 容器？）` ✗
  --     而**同一份日志**里：★ `★ 调色板搜寻：第1层看到 assets` ✓
  --   ⇒ ★★ **"按名取"失败、"走树"成功** ✓ —— ★ 两条路的结果不一样 ✓✓
  --
  --   ★ 旧项目**早就记下了这件事** ✓（`docs/assets取不到-追查.md` §〇 **H8** ✓ 原话）：
  --     ★「`Adapter:invalidate_lookups()` **只清【负】缓存** ✗，
  --        **从不清 `self.controls`（命中缓存）** ✓；
  --        而 `Adapter:find()` 命中缓存**直接返回、从不校验句柄是否还活着** ✗。
  --        引擎在**传送 / 断线重连 / 容器隐藏再显示**时会**销毁并重建全部客户端控件** ✓
  --        ⇒ 之前缓存下来的 `root` 变成**陈旧句柄** ⇒ `GetChild("assets")` = nil ✓」
  --   ⇒ ★★ 我上一版正是走了这条**陈旧句柄**的路 ✗ ⇒ **必然取不到** ✓✓
  --
  --   ★ 修法 ✓：★ **照抄项目里那条走得通的路** ✓（`ui_controller.lua` 调色板那段 ✓）：
  --     ★ ① 入口用 **`game.GetClientUIRoots()`** ✓（★ 权威 ✓ 不是缓存句柄 ✗）
  --     ★ ② **限深走树**找 `assets` ✓（★ 每步单独 pcall ✓ 哪步失败看得见 ✓）
  --     ★ ③ 在 `assets` 的子控件里**按名精确匹配** ✓
  --   ★ 全程**只读** ✓ ★ 不写任何东西 ✓
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
    for i = 1, rn do search(roots[i], 0) end
  end
  if assets == nil then
    local r0 = nil
    pcall(function() r0 = self.adapter:find("root") end)
    if r0 ~= nil then search(r0, 0) end
  end
  if assets == nil then
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：单射取不到a　原 L4356..L4359
    return nil
  end
  -- ★ 在 assets 的子控件里按名精确找 ✓（★ 并打一份实际名字清单 ✓ 便于核对后缀 ✓）
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
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：单射取不到b　原 L4378..L4382
  return hit
end

-- ★ 取当前关卡的**序号**（1 起 ✓ 与 `row.1.*` 对上 ✓）。取不到 ⇒ nil ✓
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
    return c                                       -- 规矩①/②：可以直接复用
  end
  local hit, variant = self:_grid_item_child(item, index, pos, suffix)
  rec.idx = index
  rec.hit[suffix] = hit                            -- nil = 没找到 ⇒ 不缓存，下次再试
  rec.variant[suffix] = variant
  return hit
end

-- ★★★★★ 2026-10-05 **列表项的文字：按「关卡」算一次，回调里只查表**。
--
--   为什么可以缓存：`vm.clues[i].text` 由 `Core:clue_results()` 从**关卡数据**里算出来
--   （`def.text(ctx, cl)` 只读 ctx.name / cl.*，全都是关卡里写死的东西，与棋盘状态无关）
--   ⇒ 同一个关卡里这 7（或 N）条文案**一个字都不会变**。
--   实测代价：`Core:view()` 单次 **0.235 ms**（要造上百个表：每个格子 walls/doors/notes
--   + tray + 线索 + structure_report）—— 原来**每条线索调一次** ⇒ 一次回调白花 1.6 ms。
--   缓存键 = **关卡表身份 + 条数**（不拼字符串：`level` 是同一个 Lua 表对象，直接比引用）。
function Controller:_grid_text_payload()
  local core = self.core
  -- ★★ 静态函数（`letter_of` / `portrait_of`）拿不到 `self` ⇒ 这里把 core 挂到模块表上 ✓
  --   ★ 它们只读 `core.pieces`（★ 不建视图、不查控件 ✓）⇒ 这个引用是安全的 ✓
  Controller._piece_core = core
  local lv = core and core.level
  -- ★★ 2026-10-11 **条数取【核心那份】** ✗✓（★ 与 `sync_clue_grid` 同一处修正 ✓）
  --   ★ 原来读 `lv.clues` ✗ ⇒ ★ 真关卡**已空** ⇒ ★ `n` 恒 0 ✓
  --     ⇒ ★ 缓存键里的 `n` **失去意义** ✗（★ 只在"同关内条数变了"时才看得出差别 ✓）
  --   ★ 现在读 `core.clues` ✓ ⇒ ★ 键值随**真实条数**变 ✓✓
  local list = core and core.clues
  local n = #(list or {})
  local p = self._grid_text
  if p ~= nil and p.level == lv and p.n == n then return p end
  local vm = core:view() or {}
  -- ★★★★★★ 2026-10-11 **单射读到的 `row.*` 文本优先** ✗✓✓
  --
  --   ★★★ 用户报 ✓：「★ **网格视窗消失了** ✓ ★ **整个 `row` → `clues` → 棋盘的路线
  --     就断了**」✓✓ —— ★ 这是那条路线上的**第二处断点** ✓（★ 第一处是 `n` 恒 0 ✓）
  --   ★ 断在哪 ✗：★ 卡片的四样文字**从这里切 `vm.clues[i].text`** ✗
  --     ★★ 而现在 `clues` 是**槽位**（★ 没有 `who`/`what` ✗ 文案是占位 ✓）
  --       ⇒ ★ 切出来恒空 ⇒ ★★ **卡片一片空白** ✓（★ 用户的"路线断了"正是它 ✓）
  --   ⇒ ★ 修法 ✓：★ `_fill_grid_item` 那一趟**已经把 `row.<关>.<行>` 的四个槽位读过了** ✓
  --     ★ 它把文本按【关序 + 行号 + 槽位】记进 `Controller._row_text` ✓
  --     ★★ 这里**直接用那份** ✓ ⇒ ★ `who`/`what`/`letter`/`face` 四样全部就位 ✓✓
  --   ★ 顺序 ✓：★ **单射优先** ✓（★ 与 `_fill_grid_item` 里那条"用户配的优先于算法"同一口径 ✓）
  --     ★ 没配的行 ⇒ 退回原来的"从文案里切名字" ✓（★ 向后兼容 ✓ 不会更差 ✓）
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
    -- 与 `clue.N` 三个文字控件**完全同一份取值**（切分逻辑共用 `split_by_name`，不复制）
    --
    -- ★★★★★ 2026-10-06 **接上第 5 个返回值 `wportrait`** ✗✓ —— 网格视窗的头像要靠它 ✓
    --   起因：★ 用户建好模板后发现「★ **五张卡的头像都一样**」✗
    --   ★ 根因：★ `face` 是**图片控件** ✓ ★ 它**不会自己变** ✗ ⇒
    --     ★ 必须**逐个实例**写 `imageId` ✓ —— 而这里**原来没接 `wportrait`** ✗✓
    --   ★ 旧卡片（`clue.N.face`）一直在用第 5 个返回值 ✓（★ 见下面 `local who, pre, post, wid, wportrait = `
    --     ★ 那份 ✓）⇒ ★ 这里漏了 ✓ ⇒ ★ 于是网格视窗走的是"头像永远等于模板默认图" ✓
    local who, pre, post, wid, wportrait = split_by_name(vm, tostring(cl.text or ""))
    --   ⚠️ 文案里没有人名时（例如 `selftest_theft_5x5` 的线索）：`who == nil`、`pre` 是整条文案
    --      ⇒ 名字列留空、正文放**整条**（老路径在那种关卡上是整块不发、什么都看不到；
    --         新路这里按"名字为空、正文 = 全文"来填，线索本身必须看得见）。
    local rt = row_text and row_text[i] or nil
    items[i] = {
      who    = (rt and rt.who) or ((who ~= nil) and (tostring(pre or "") .. tostring(who)) or ""),
      what   = (rt and rt.what) or ((who ~= nil) and tostring(post or "") or tostring(pre or "")),
      letter = (rt and rt.letter) or tostring(wid or ""),
      -- ★ 头像素材名（★ 如 `portrait.A` ✓）★ `nil` 表示这一条没有对应角色 ⇒ **不要写图** ✓
      --   ★★ 单射侧配的 `face` 是**文本槽位** ✓ ⇒ 它给的是**素材名** ✓ 直接用 ✓
      portrait = (rt and rt.face) or wportrait,
      -- ★★★★★ 2026-10-09 **把【人物 id】也存进快照** ✗✓（★ 这是修我自己造成的一个回归 ✓）
      --
      --   ★ 为什么必须有这一项 ✓：填充那边要按 **id**（`A`/`B`/`D`/`V`）去查
      --     `core.placed[id]` 决定灰白 ✓ 而 `who` / `portrait` **都不保证是 id** ✗：
      --       · `items.who`  是**显示名**（`医生` ✓ 见 L4131 的拼接 ✓）
      --       · `items.portrait` 是**素材名**（`portrait.B` ✓）也可能取不到 ✓
      --     ⇒ ★ **只有视图记录的 `cl.who` 是 id** ✓（`ui_controller.lua:4211` 的老注释就写着这条 ✓
      --        `诊断CLUE` 也证明过：`值(type=at … who=V)` ✓ 是字母 ✓）
      --
      --   ★ 为什么存这里、而不是填充时现取 ✓：**这里本来就有一份 `vm` 在手** ✓
      --     存下来 ⇒ 填充时**零额外成本** ✓
      --     （我 2026-10-09 早先那版把填充里的 `core:view()` 删了 —— 动机是每次回调白烧
      --      14 次整视图重建 ✓ 但**删过头了** ✗：那个 `who` 是**唯一**能拿到 id 的来源 ✓
      --      于是 id 退化成显示名 ⇒ `core.placed["医生"]` 恒 nil ⇒ **灰白与选中反馈全没了** ✗
      --      正确修法 = **从这里拿**（已是 0 成本 ✓），而不是**不拿** ✓）
      --
      -- ★★★★★★ 2026-10-11 **`cl.who` 在槽位模型下恒 nil ⇒ 改用【那一行的 `who` 文本】** ✗✓✓
      --
      --   ★★★ 用户 2026-10-11 点破 ✓（★ 原话 ✓）：
      --     「★ **前面的模式不是已经说明了 `who` 不参与棋盘线吗** ✓
      --       ★ **怎么又开始纠结这个无关量了**」✓✓
      --   ★★ 对 ✓ —— 而且更关键的是他早就定过案 ✓：
      --     ★「★ **就是按旧逻辑** ✓ ★ **`face` 和 `letter` 怎么放是由点击指示的** ✓
      --       ★ **等于你只需要换素材来源** ✓ ★ **后面的逻辑一切照旧**」✓
      --     ★「★ **一切线索区的素材都来自对应的 `row`**」✓
      --     ★「★ 头像对应 `face` ✓ ★ 标记对应 `letter` ✓ ★ **`who`/`what` 不往棋盘填**」✓✓
      --   ★★★ 所以"旧逻辑"里的那个键 ✓ = ★ **`cl.who`** ✓
      --     ★ 它在**旧模型**下是"**人的 id**"（`A`/`B`/`V`/`D` ✓ 视图里就是这么记的 ✓）
      --     ★★ 而在**新模型**下 ★ **`cl.who` 恒 nil** ✗（★ 槽位没有 `who` ✓）✓
      --       ⇒ ★★★ **于是【三处都用不上它】** ✗✓：
      --         ★ ① `_row_letter[键]` ⇒ **一个键都没写进去** ✓
      --         ★ ② `_row_face[键]` ⇒ **同上** ✓
      --         ★ ③ 卡片点击 ⇒ 解析出的人 = **nil** ✓（★ 用户 v180 日志正是它 ✓）
      --       ⇒ ★★ **三处症状同源** ✓✓（★ 而我一直在追第 ③ 处 ✗）
      --   ⇒ ★★★ 修法 ✓：★ **键 = 那一行的 `who` 文本** ✓（★ `rt.who` ✓）
      --     ★ 为什么它才是对的 ✗：★ 用户在 `row` 里填的 `who` **就是他自己定义的键** ✓
      --       ★ 棋盘上要显示的 `letter` / `face` **都来自同一行** ✓ ⇒ ★ **它们天然同键** ✓✓
      --     ★★ **不能拿它去查 `core.names`** ✗ —— ★ 那是我上一版加的过滤 ✓
      --       ★ 它把"用户自己配的键"当成了"必须是游戏里的人物 id" ✗ ⇒ **永远对不上** ✓✓
      -- ★★★★★★★★ 2026-10-11 **`id` 改成【行号】（★ 与棋盘线同一把钥匙 ✓）** ✗✓✓
      --
      --   ★★★ 它原来是 **`rt.who`（那一行 `who` 槽的文本）** ✗✓
      --     ★ 上面那几段注释正是**上一轮**为它写的（★ "键 = 那一行的 `who` 文本" ✓）
      --     ★★ 而用户随后明确否掉了这条路 ✓：
      --       「★ **如果非要这个机制，就把 `id` 设为 `letter`，或者 `row.i.j`** ✓
      --        ★ **`who` 已经干扰了很多次了**」✓✓
      --   ★ 留着它的后果（★ 不是"风格问题" ✗ 是**真的会错** ✓）：
      --     ★ 每一个读 `items[i].id` 的地方都得**再猜一次它是什么** ✗ ——
      --       ★ 灰白那条路（`core.placed[?]`）要的是**棋子 id** ✓ ⇒ ★ 猜错就**永不开灰** ✓✓
      --         （★ 实测：夹具里 `who` 填 `W1` ⇒ `tonumber("W1")` = nil ⇒ 灰白找不到人 ✓）
      --     ★★ 而"行号"是**唯一**能被两处同时接受的形状 ✓：
      --       ★ 卡片侧：★ 行号 ↔ `row.<关>.<行>` ✓（要显示什么就用它查 `_row_text` ✓）
      --       ★ 棋盘侧：★ 行号 ↔ 棋子 id ✓（`_piece_at_row` / `_pos_of_piece` ✓）
      --   ⇒ ★ 修法 ✓：★ **`id` = 行号 `i`** ✓ —— ★ 不再从 `rt.who` / `cl.who` 取 ✗
      --     ★★ 于是"`who` 填什么"**彻底与这条链无关** ✓✓（★ 用户要的正是这个 ✓）
      id     = i,
    }
  end
  p = { level = lv, n = n, items = items }
  self._grid_text = p
  return p
end


-- ★★★★★ 2026-10-09 **用官方 getter 算出"一屏放得下几项"** ✓（只在第一次算，之后走缓存 ✓）
--
--   ★ 官方语义（`ClientUIGridScrollerControl` ✓ 我逐个核过 ✓）：
--     `GetItemSize()`      → `x, y`（列表项**宽、高** ✓）
--     `GetItemSpacing()`   → `x, y`（**水平、垂直**间距 ✓）
--     `GetPadding()`       → `top, bottom, left, right`（**上、下、左、右**内边距 ✓）
--     `GetContentLength()` → 滚动内容在滚动方向上的长度（**总长** ✓ 不是可见数 ✗）
--     `sizeDeltaY`         → 视窗自身高 ✓（基类字段 ✓）
--   ⇒ 纵向时：★ `可见数 = floor((视窗高 − 上边距 − 下边距) / (项高 + 纵间距))` ✓
--
--   ⚠️ **官方没有"可见项数"的现成接口** ✗ ⇒ 只能自己算 ✓（资料员也确认了这一点 ✓）
--   ⚠️ 任何一个数读不到 ⇒ 返回 `nil` ⇒ 调用方**什么都不做** ✓（宁可不修，也不能误关可见项 ✗）
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
  -- ★★★★★ 2026-10-09 **算术更正：一屏是 5 项，不是 4** ✗✓（资料员指出 ✓ 我复核 ✓）
  --   ⚠️ 我原来写 `floor((视窗高 − 上边距 − 下边距) / 每项占)` ✗ ⇒ 得 **4** ✗
  --     ★ **错在把 `padding.bottom` 也算进了"一屏"** ✗
  --   ★ 正解 ✓：`padding.bottom` 属于【内容末端】✓，**不约束列表顶端** ✓
  --     第 k 项（0 起）占 `[padTop + k×每项占 , +项高]` ✓
  --     ⇒ 装得下 ⇔ `padTop + k×每项占 + 项高 ≤ 视窗高` ✓
  --   ★ 代入真机数逐项核（`GetItemSize/Spacing/Padding` ＋ 视窗 544 ✓）：
  --       0: 20–116 ✓　1: 124–220 ✓　2: 228–324 ✓　3: 332–428 ✓
  --       ★ 4: 436–**532** ✓ **完整可见**（离底还剩 12 px ✓）
  --       ★ 5: 540–636 ✗ 只露 4 px　　6: 644–740 ✗ 完全在外
  --     ⇒ ★★ **一屏 5 项** ✓ ＋ **溢出 216 px** ⇒ ★ **第 5、6 项在外** ✓
  --       ⇒ ★ **正好是用户看到的"两张卡被放到区域外"** ✓✓
  local per = ih + (sy or 0)
  if per <= 0 or vh <= 0 then return nil end
  local n = 0
  while (pt or 0) + n * per + ih <= vh and n < 512 do n = n + 1 end
  if n < 1 then n = 1 end
  self._grid_vis_n = n
  -- ★ 2026-10-09 **同时记下"可见带半径"与"项高"** ✓ —— 位置判据要用 ✓
  --   ★ 为什么不能只用序号 ✗：真机实测 `scrollProgress=nil`（**只读字段全读不到** ✗）
  --     ⇒ 一旦滚动过，"可见区"就**不是**第 1..N 项 ✓ ⇒ 必须按**位置**判 ✓
  self._grid_band_h = vh / 2
  self._grid_item_h = ih
  self._grid_vis_why = "项高=" .. tostring(ih) .. " 纵间距=" .. tostring(sy)
    .. " 上边距=" .. tostring(pt) .. " 下边距=" .. tostring(pb)
    .. " 视窗高=" .. tostring(vh)
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：网格可见数/可见带　原 L4530..L4537
  return n
end

-- 可见带半径（视窗高的一半）—— `_grid_visible_count` 里顺便算好的 ✓
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：_grid_band　原 L4583..L4587

-- ★★★★★ 2026-10-10 **就地重填：不碰 `RefreshItems`，滚动位置完全不动** ✗✓
--
--   ★★ 用户新报的症状 ✓（★ 一条就把全串起来了 ✓）：
--     「**点第五张卡会弹回视窗顶部**」✗ ＋「后面的卡要么点不动，要么**一次点击选两张**」✗
--     ＋「其它关卡也有类似情况」✓
--
--   ★★ 根因（**一个根因，四个症状** ✓）：
--     ★ 点卡 / 放置 / 取消选中，都会 `self._grid_sig = nil` ✗（L573 / L609 / L5186 三处 ✓）
--     ⇒ ★ 下一帧 `sync_clue_grid` 见签名变了 ⇒ ★ **重发 `grid:RefreshItems(...)`** ✗
--     ⇒ ★★ **引擎收到 `RefreshItems` 会把滚动位置重置到顶部** ✗✓
--     ⇒ ★ 于是：
--         ① ★ **页面弹回顶部** ✓
--         ② ★ 可见的那一批卡**换人了** ⇒ ★ `GetItemIndex` 映射到**别的线索** ✓
--         ③ ⇒ ★ **点后面的卡"选错人 / 选两张"** ✓✓
--         ④ ⇒ ★ 看着像"点不动"（其实点到了别的卡 ✓）
--
--   ★ 那三处**为什么**要清签名 ✓：★ 为了让"灰白/高亮"立刻跟着状态刷新 ✓（原注释写得很清楚 ✓）
--     ★ 但网格这条路**代价太大** ✗ —— ★ 刷一次就把用户的滚动位置**丢掉** ✓
--
--   ⇒ ★★ 修法 ✓：★ **改成【就地重填】** ✓
--     · ★ 填充回调本来就会拿到列表项句柄 ✓ ⇒ ★ **把它们记下来** ✓（`_grid_seen` ✓）
--     · ★ 要刷新时 ⇒ ★ **直接对这些句柄再跑一遍 `_fill_grid_item`** ✓
--       ⇒ ★ **完全不碰 `RefreshItems`** ✗ ⇒ ★ **滚动位置一动不动** ✓✓
--     · ★ 三处改成置一个**待刷新标志** ✓ 由 `sync_clue_grid` 消费 ✓
--   ★ 这比"方案 2（每关一个视窗）"**简单得多** ✓ —— ★ 不动存档、不动视图数量 ✓
function Controller:_grid_refill_now(adapter, grid)
  if grid == nil then return 0 end
  local seen = self._grid_seen
  if seen == nil then return 0 end
  local n = 0
  self._grid_in_refresh = false          -- ★ 当作"引擎那趟"⇒ 正常填 ✓（不触发占位清空 ✓）
  for item, idx in pairs(seen) do
    pcall(function() self:_fill_grid_item(adapter, grid, item, idx) end)
    n = n + 1
  end
  self._grid_in_refresh = false
  return n
end

-- 填**一条**列表项。★ 无状态：内容全部由 `index` 现算（官方：滚动会重复进入回调）。
-- ★★★★★★ 2026-10-11 **把 `gray` 层的射线关掉（★ 与"有没有内容"无关 ✓）** ✗✓✓
--
--   ★★★ 为什么必须能【单独】调用 ✗（★ 协作方测绘的直接结论 ✓）：
--     ★ `gray` 是卡片里**最上层**的图片 ✓ ⇒ ★ **它挡在最上面吃点击** ✗
--     ★ 原来"关射线"那段写在 `_fill_grid_item` 里、且在 `cl == nil` 那个 `return` **之后** ✗
--       ⇒ ★★ **一旦 `cl` 为 nil ⇒ 射线没关 ⇒ `gray` 抢点击** ✓
--       ⇒ ★★★ **表现就是"点了跟没点一样"** ✓✓（★ 正是用户报的症状 ✓）
--   ⇒ ★ 抽成方法 ✓ ⇒ ★ **在函数最前面就能先关掉它** ✓ ⇒ ★ **与内容解耦** ✓✓
--   ★ 幂等 ✓：★ 按**列表项实例**记 `gray_noray` ✓ ⇒ ★ 每个实例只写一次字段 ✓
--     ★（★ 那段的原注释讲得很清楚：全局标志会让"只有第 1 个实例生效" ✗）
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

-- ★★★★ 2026-10-18 **通用线索卡**（列表第 1 项）✗✓
--   只点亮模板里新加的 gen.backrop / gen.title / gen.body 三件，
--   把四样卡片文字（who/what/letter/face）全部藏掉 —— 两张卡长得不一样 ✓
--   ★ 文字：本函数**不写文字**（用户定：内容源那边他自己填 ⇒ 先留空 ✓）
-- ★★★★ 2026-10-18 **本关有没有通用线索** —— 判据 = **内容源存在** ✓
--   用户实测：按 `core.general_clues` 判的两版都没生效（点通用卡仍然给 a 发高亮）
--   ⇒ 改用**用户实际配的东西**：存档里 `row.<关>.clue` 这个内容块存在 = 有通用线索 ✓
--     ★ 它由编辑器/存档决定，与 lua 关卡表是否声明无关 ⇒ 不会因为一处漏配整条链失效 ✓
--   ★ 兜底：内容源取不到时，仍看 `core.general_clues` ✓
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
  -- ★★★ 2026-10-18 **记下"通用线索那一项"的句柄** ✓
  --   点击时用句柄比对，**不再依赖 pos 算术、也不依赖 general_clues 查询** ✓
  --   （用户实测：按 pos==1 判时，点它仍然按第 1 张真卡 a 去高亮 ✗）
  self._general_item = item
  -- ★★★ 2026-10-18 **正文从内容源读** ✓（用户定：gen.title 的文本已在模板里填好，只差正文）
  --   内容源链路（存档实测）：`row.<关>.clue`（容器）→ 子控件 `clue.<关>.1`（文本框）
  --   读法照抄卡片四样那套：`_palette_child` 拿容器 → `FindChild(全名)` 拿文本框 → 取 `text` ✓
  --   写入：`item:FindChild("gen.body").text = 正文` ✓（与卡片 `who/what` 同一条路 ✓）
  --   ★ 什么都没配 ⇒ 不写（留空 ✓ 绝不写成立）
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
      if _txt ~= nil and _txt ~= "" then
        local _dst = nil
        pcall(function() _dst = item:FindChild("gen.body") end)
        -- ★★ 2026-10-18 走**正规文字链路** ✓（docs/线索区-内容填入规则.md §四：
        --   `write_control_text(ctrl, text)` —— **值变了才写**，与 who/what/letter 同一条路 ✓）
        --   我第一版直接 `_dst.text = _txt` 绕过了它 ⇒ 被签名门/属性账本盖掉 ✗
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
  for _, nm in ipairs({ "gen.backrop", "gen.title", "gen.body" }) do
    local c = child(nm)
    if c ~= nil then pcall(function() c:SetVisible(true) end) end
  end  -- ★★★★★ 2026-10-18 **通用卡的「标记」走普通卡同一条路** ✗✓
  --   用户实测：涂 gen.backrop 是「整块染色」✗ 不是描边
  --   为什么普通卡是描边：涂的是 backrop1（**下层**），backrop2 盖住中间 ⇒ 只剩边缘 ✓
  --   ⇒ 通用卡也涂 backrop1 ✓（它本来就在模板里、也在通用卡上可见 ✓）
  --   判定**绑在通用线索身份上**：general_focus 为真 ⇒ 亮；否则还原 ✓
  do
    local _cp = nil
    pcall(function() _cp = item:FindChild("backrop1") end)
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

  -- ★★★★★★ 2026-10-11 **先把"能点"这件事做完，再管内容** ✗✓✓
  --
  --   ★★★ 用户报 ✓：「★ **目前链路还是断的** ✓ ★ **放置行为等依旧不通**」✓
  --   ★ 协作方测绘的结论 ✓（`网格视窗-光标事件-实现测绘.md` ✓）：
  --     ★★ **绑点击原来在函数【最后一行】** ✓ ⇒ ★ **它前面任何一处 `return` 都会把它跳过** ✗✓
  --     ★ 而前面**确实有一处会真的触发** ✗：★ `cl == nil`（★ 见下面那段长注释 ✓）
  --   ⇒ ★★★ **修法** ✓：★ **把绑定提到最前面** ✓ ——
  --     ★ **"能不能点"与"有没有内容"彻底解耦** ✓✓
  --     ★ 语义 ✓：★ 内容没配好 ⇒ ★ 卡片是**空的** ✓ ★ **但照样能点** ✓✓
  --   ★ 幂等 ✓：★ `_grid_bind_item_click` 自带**弱键去重** ✓ ⇒ ★ 反复调用只绑一次 ✓
  --     ★（★ 见它内部的 `self._grid_bound[item]` ✓）
  --   ★ 成本 ✓：★ 已绑过的项 ⇒ 去重那一步就返回 ✓（★ 不再碰 `ensure_raycast` ✓）
  pcall(function() self:_grid_bind_item_click(adapter, grid, item) end)
  -- ★★ 同一条理由 ✓：★ **`gray` 的射线也要在这里就关** ✗✓
  --   ★ 它在原来那个位置（`cl` 判空之后 ✓）⇒ ★ 同样会被跳过 ✓
  --   ★★ 不关 ⇒ ★ 它挡在最上层**吃点击** ⇒ ★ **"点了跟没点一样"** ✓✓
  --   ★ 幂等 ✓：★ 按列表项实例记 `gray_noray` ✓ ⇒ 只写一次字段 ✓
  pcall(function() self:_grid_disable_gray_raycast(item, index, nil) end)

  -- ★★ 官方那句"列表发生滚动时：对列表项内容进行刷新(触发回调)"有**两种读法**
  --    （引擎自己重进 / 得靠脚本再调一次 RefreshItems）—— 这是本项目一个**未验证点**：
  --      · 引擎**会**重进 ⇒ 这里会打出一行（就靠它确认；此时列表项内容永远是对的）
  --       · 引擎**不会**重进 ⇒ 日志里没有这行 ⇒ 滚动后列表项会留着上一条的内容，
  --         下一轮就得改成"跟着 scrollProgress 变化再调一次 RefreshItems"
  --   区分办法：我们那次 `RefreshItems` 调用期间 `_grid_in_refresh = true`；
  --   回调从引擎那边进来时它是 false。
  if not self._grid_in_refresh then
    self._grid_scroll_cbs = (self._grid_scroll_cbs or 0) + 1
    self:_grid_log("scroll_cb", "网格视窗：滚动时引擎**会**重进 RefreshItems 回调 ✓（第 "
      .. tostring(self._grid_scroll_cbs) .. " 次）⇒ 列表项内容按 index 现算，滚动不会串内容")
    -- ★★★★★ 2026-10-05 **节流计数：这条路上的每帧开销现在已经是 0，但"引擎多久重进一次"
    --   只有真机能回答**（离线假环境是我们自己调的，测不出引擎的节奏）。
    --   重进满 60 / 600 / 3600 次时各报一行 —— 60 fps 下分别约等于 1 秒 / 10 秒 / 1 分钟。
    --   读法：
    --     · 只是滚动几秒就看到 `60` ⇒ 重进频率 ≈ 每秒几十次（滚动时才重进，符合官方描述）
    --     · 挂着不动也走到 `3600` ⇒ 引擎**每帧**都重进；此时每帧成本仍然是 0
    --       （`_grid_item_rec` / `_grid_text_payload` 把查找、视图重建、文字写入全免掉了）
    --     · 一行都不出现 ⇒ 引擎根本不重进 ⇒ 滚动后列表项会留着上一条的内容，
    --       下一轮得改成"跟着 scrollProgress 变化再调一次 RefreshItems"
    local hits = self._grid_scroll_cbs
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：网格视窗·重进累计　原 L4609..L4612
  end

  -- 索引基准：**第一次回调 = 列表最上面那一项** ⇒ 它的 index 就是基准（0 或 1）。
  --   为什么要判：官方只说"索引以运行时传入/返回的为准"，**没说从 0 还是从 1 起**
  --   （`clue.1` 这些控件名是 1 起，而 Unity 那套列表通常是 0 起）。
  --   判一次就够，之后滚动回调沿用它 —— 这样两种实现都能对上 `vm.clues`（1 起）。
  --
  -- ★★★★★★ 2026-10-11 **"第一次回调就是 index 0" ≠ "列表是 0 起"** ✗✓✓（真机日志定案 ✓）
  --
  --   ★★★ 用户 v178 真机日志 ✓（★ 原文 ✓ ★ 这是决定性证据 ✓）：
  --       `★ 卡片点击进来了 ✓（第 1 次）GetItemIndex=0  索引基准=0`
  --       `★ 卡片点击进来了 ✓（第 2 次）GetItemIndex=1  索引基准=0`
  --       `★ 卡片点击进来了 ✓（第 3 次）GetItemIndex=2  索引基准=0`
  --   ★★ 用户点的是**第 1 / 第 2 / 第 3 张卡** ✓ ★ 而引擎回读 `GetItemIndex` = **0 / 1 / 2** ✓✓
  --     ⇒ ★★★ **引擎的索引就是【本该用的那个序号】，只是 0 起** ✓
  --       ★ 我们要的 `pos` 是**1 起** ✓ ⇒ ★★ **`pos = index + 1`** ✓ ⇒ ★ **基准应当是 `1`** ✓✓
  --
  --   ★★★ 原来那一行的推理错在哪 ✗：
  --     ★ 它把「**第一次回调交来的 index 是 0**」当成「**列表是 0 起**」✓
  --     ★★ 而这两件事**不是一回事** ✓ —— ★ 前者只是"第一个交来的项恰好是第 0 号" ✓
  --     ★ 真正的定义 ✓：★ **基准 = 第 1 项（列表顶端那一项）的 index** ✓
  --       ★ 顶端那一项**无论怎么编码**，交出来的 index **就是基准** ✓
  --     ★ 所以判据应当是 `_grid_base = index`（**第一次交来的就是顶端** ✓），
  --       而**不是** `(index == 0) and 0 or 1` ✗
  --   ★ 旧判据的后果 ✓：★ 引擎 1 起（index 0 = 第 1 项）时判成基准 0 ✗
  --     ⇒ ★★ **`pos` 每一张都【错位一张】** ✓ ⇒ ★ **点第 1 张选中的是"位置 1"** ✓
  --       ⇒ ★★★ **点哪张都选不到那张上的人** ✓✓（★ 这正是"链路还是断的" ✓）
  if self._grid_base == nil then
    -- ★ 第一次回调交来的 index **就是**基准 ✓（★ 那一次一定是列表顶端 ✓）
    local fi = tonumber(index)
    if fi ~= nil then
      self._grid_base = fi
    else
      self._grid_base = 0        -- ★ 连 index 都没有（老实现）⇒ ★ 按 0 起 ✓ 与原来一致 ✓
    end
    if print then
      print("[murdoku] 网格视窗：**索引基准定为 " .. tostring(self._grid_base)
        .. "**（第一次回调交来的 index = " .. tostring(index)
        .. "）⇒ 之后 `pos = index − " .. tostring(self._grid_base) .. " + 1`")
    end
  end
  local pos = (tonumber(index) or self._grid_base) - self._grid_base + 1
  -- ★★★★ 2026-10-18 **通用线索占列表第 1 位** ✗✓
  --   用户：「通用线索…放在最上方，如果有通用线索则其它线索卡往下移」
  --   ⇒ 列表位置 `pos` 与"第几张真卡 / 第几行"从此**不是同一个数** ✓
  --     · pos == 1        ⇒ 通用线索卡（只点亮 gen.* 三件，四样卡片文字藏掉）
  --     · pos >= 2        ⇒ 第 (pos-1) 张真卡 ⇒ `row.<关>.<行>` 的行号**仍是 pos-1 起的 1** ✓
  --   ★ 这么写只用一个局部变量 `pos` 做减法，后面那一大段读 `row.<lv>.<pos>` 的代码
  --     **一个字都不用动** ✓（否则整段的行号都会错位一格 ✗）
  local _has_gen = false
  pcall(function() _has_gen = self:_has_general_clue() end)
  if _has_gen then
    if pos == 1 then
      pcall(function() self:_fill_general_item(adapter, item, index, pos) end)
      return
    end
    pos = pos - 1
    -- ★★★ 2026-10-18 **列表项会被引擎复用** ✗✓
    --   上一轮用 `self._general_item` 记句柄来判断"哪一项是通用线索" ✓
    --   但**同一个 item 句柄**滚动/回收后会拿去显示普通卡 ⇒ 标记还在 ⇒
    --   点那张**普通卡**也发 `focus_general` ⇒ 高亮派发错 ✗（用户实测）
    --   ⇒ 填普通卡时**就地清掉**这个标记 ✓（下次填成通用卡会重新设 ✓）
    if self._general_item == item then self._general_item = nil end   -- _general_item 清掉（复用护栏）
    -- ★★★ 2026-10-18 **普通卡必须把通用线索那三件藏掉** ✗✓    --   它们是**模板里的子控件** ⇒ 默认对**每一张卡**都可见 ✗    --   用户实测：「gen.backrop 会在所有线索卡上出现」✓ 修在这里 ✓
    for _, _nm in ipairs({ "gen.backrop", "gen.title", "gen.body" }) do
      pcall(function()
        local _cc = self:_grid_item_child_cached(item, index, pos, _nm)
        if _cc ~= nil then pcall(function() _cc:SetVisible(false) end) end
      end)
    end
  end
  -- ★ 2026-10-10 **记下句柄与它当时的 index** ✓ —— ★ 就地重填要用 ✓
  --   ★ 为什么要有它 ✗：★ 有了句柄就能【不重发 RefreshItems】而刷新内容 ✓
  --     ⇒ ★ **滚动位置才保得住** ✓✓（★ 这是"点一下弹回顶部"的治本一步 ✓）
  self._grid_seen = self._grid_seen or {}
  self._grid_seen[item] = index

  -- ★★★ 2026-10-11 **填充侧的定位探针** ✗✓（★ 用户 v179 那次的"同一张"到底是不是真的 ✓）
  --   ★ 要分清两种可能 ✗：
  --     ★ ① 引擎**只交来同一个 index**（★ 列表项全叠在一处 ✓ 本项目早有旁证 ✓）
  --       ⇒ ★ 那么"每次都算成 `pos=1`"**就是引擎的真实报告** ✓
  --         ★ 得靠**别的**办法定位（★ 比如按可见顺序自己排 ✓）
  --     ★ ② 引擎交来的 index 各不相同 ✓ ★ 而**点击时**反查坏了 ✓
  --       ⇒ ★ 用填充记录就能修好 ✓（★ 已改 ✓）
  --   ⇒ ★★ 这一行就是分水岭 ✓ ★ 最多 6 行 ✓
  if print and (self._grid_fill_pos_log or 0) < 6 then
    self._grid_fill_pos_log = (self._grid_fill_pos_log or 0) + 1
    print("[murdoku] ★ 填充定位 ✓：引擎交来 index=" .. tostring(index)
      .. "（基准 " .. tostring(self._grid_base) .. "）⇒ 填到 pos=" .. tostring(pos))
  end

  -- ★★★★★ 2026-10-10 **单射优先：用户在 `assets/row.<关>.<行>` 里指定的内容，优先于算法** ✗✓
  --   ★ 用户要求 ✓（原话 ✓）：「我需要一个区域让我**指定第几关第几行填什么**」✓
  --     「现在**第几关第几行怎么填是没有定式的**」✗
  --     「先把这个**单射**做好了，有了这个**一一映射**再查显示问题会更方便」✓
  --     「建立这个单射的过程中**说不定就顺手解决**这个问题了」✓
  --   ★ 有配 ⇒ **完全按你配的来** ✓（★ 算法一个字都不写 ✓）
  --   ★ 没配 ⇒ **回落到现有算法** ✓（★ 向后兼容 ✓ 没配的行不会空着 ✓）
  --   ★ 只在**我们那趟**做 ✓ —— ★ 引擎重进时不动内容 ✗（★ 那会覆盖引擎的刷新 ✓）
  --
  -- ★★★★★★★★ 2026-10-11 **门放宽一次：本关还没建快照时也补一趟** ✗✓✓
  --
  --   ★★★ 为什么 ✗（★ 独立复核查出来的 ✓）：★ 删掉"第二趟单射"之后 ✓
  --     ★★ `_grid_refill_now`（就地重填 ✓）那条路上 `_grid_in_refresh == false` ✗
  --       ⇒ ★ 它**不再跑这一趟** ✓ ⇒ ★ 那是删除带来的**唯一行为收窄** ✓✓
  --   ★ 今天为什么不发作 ✗：★ `row.*` 是**静态内容** ✓ ⇒ ★ 进关那次 `RefreshItems`
  --     已经把两张表建好了 ✓（★ 而 `do_place` 只改棋盘、不改 `row.*` ✓）
  --   ★★ 但它是个**真实收窄** ✗ ⇒ ★ 而且零覆盖 ✓（★ 复核者的破坏实验里，
  --      `clue_slots` 的 54 条断言对这条链**全盲** ✓）
  --   ★ 修法 ✓：★ **门加一条** ✗ —— ★ `或者【本关还没建快照】` ✓
  --     ★ 判据 ✓：★ `_row_letter[next(...)] == nil` ＝ 这一关**一条都没落账** ✓
  --       ★ 那说明"我们那趟"从没跑过（★ 或者这一关真的没配 ✓ 两者都该补一趟 ✓）
  --   ★★ 稳态成本 ✓：★ **零** ✗ —— ★ 只要**这一行**已经落过账，判据就假 ✓
  --     ★（★ 原来我写的是"**整张表**非空"✗ ⇒ ★ 一行落了账就**再也不会补别的行** ✓
  --        ★★ 复核者指出：那样"行 1 已落、行 2 缺"时补不上 ✓ —— 改成**按行**判 ✓✓）
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
        -- ★★★★★ 2026-10-10 **`#503` 不全时的兜底：四个槽位名【全树按名找】** ✗✓
        --   ★ 实证 ✓：`row.3.1` / `row.3.9` 的 `#503` 是空的 ✗ ⇒ `GetChildren()` 拿不到子控件 ✓
        --     ★ 而它们的**名字是确定的** ✓（`who.3.1` 这种 ✓）⇒ ★ **按名找一定能拿到** ✓✓
        --   ★ 只在这四个槽位、且 `GetChildren()` 没给全时才走 ✓ ⇒ 稳态零成本 ✓
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
          -- ★★★★★★ 2026-10-11 **本次 `row` 的收成，读到就当场落账（不跨块传值）** ✗✓✓
          --
          --   ★★★ 原写法（已修 ✗）：★ `self._row_letter_txt = nil` 写在**子控件循环【里】** ✓
          --     ⇒ ★ 每处理一个子控件就**清一次** ✓ ⇒ ★ 只有 `letter` 恰好是
          --       **最后一个**子控件时那个值才活到循环结束 ✓✓
          --   ★ 存档实测（只读探针 ✓ `tools/gil` 那份 `row.*` 子列表顺序 ✓）：
          --     ★ `letter` 在**最后一位**的只有 **1 / 20 行** ✗（★ `row.1.4` ✓）
          --       ★ 其余 19 行 ⇒ `letter` 后面还有 `who`/`what`/`face` ⇒ **清掉** ✓
          --     ⇒ ★★★ **`_row_letter` 恒空 ⇒ `letter_of` 恒 nil ⇒ 落兜底 ⇒
          --       用户看到"还是旧铅笔笔记"** ✓✓（★ 与真机现象逐字相符 ✓）
          --   ★ 修法 ✓：★ **不再设中间字段** ✗ —— ★ 读到 `letter` 就地写
          --     `Controller._row_letter[人物id]` ✓（★ 在 `slot == "letter"` 那个块里 ✓）
          --     ⇒ ★ 与子控件顺序**完全无关** ✓、也**不可能**再踩"跨块传值"那条坑 ✓✓
          for ci = 1, #kids do
            local k = kids[ci]
            local kn = nil
            pcall(function() kn = tostring(k.name) end)
            -- ★ 槽位名可能带自动后缀 ⇒ 取第一段 ✓（★ 项目注释提过"自动后缀算不一样"✓）
            local slot = kn
            -- ★★ 修正（用户示例实证 ✓）：子控件名是 `who.1.1` 这种带后缀的 ✗
            --   ⇒ ★ 槽位名 = **第一个点号之前** ✓（★ 我原来写"第一段非空白"✗ ⇒ 取到 `who.1.1` ⇒ 对不上卡片的 `who` ✓）
            -- ★ 护栏 ✓（★ 地图员提醒 ✓）：★ 每个 `pos` 开始处清掉残值 ✗
            --   ★ 否则某个 `pos` 没有 `letter` 槽位 ⇒ 会沿用【上一个 pos 的值】✗
            -- ★★★★★★ 2026-10-11 **护栏改到循环【外】** ✗✓✓
            --   ★ 原来这一行就在【这里】（循环里 ✓）⇒ ★ 它把**刚读到的** `letter` 清掉 ✓
            --     ⇒ ★ 这就是"标记填不进去"的真因之一 ✓（★ 详见循环开头那段 ✓）
            --   ⇒ ★ 现在：★ 清理只在循环前做一次 ✓ 循环里**只读不写** ✓
            if slot ~= nil then slot = string.match(slot, "^[^%.]+") end
            -- ★★ 本趟这一行 = `row.<关>.<行>` 的**行号**（★ 落账的键就是它）
            local _rowno = pos
            if slot ~= nil and slot ~= "" then
              -- ★★★★★★ 2026-10-10 **按完整名在【列表项下】找，并验证类型** ✗✓✓
              --   ★★★ 探针铁证 ✓（真机日志原文 ✓）：
              --     `★ 单射写入探针：slot=who  目标控件=who  写入=3.1  写前=  写后读回=`
              --     `⇒ ★★ 控件里【没变】`
              --   ⇒ ★ 两个结论 ✓：
              --     ★ ① **目标控件叫 `who`** ✗ —— ★ 不是卡片上的 `clue.<行>.who` ✓
              --     ★ ② **写前/写后都是空的** ✗ ⇒ ★ **那个控件没有 `text`** ✓
              --   ⇒ ★★ 所以是"**写对了名字、写错了控件**" ✓ ——
              --     ★ `_grid_item_child_cached` 按短名找 ⇒ ★ **命中了别处同名控件** ✗
              --   ⇒ 修法 ✓：
              --     ★ ① **先按【完整名】`clue.<行>.<槽位>` 在【列表项下】找** ✓
              --     ★ ② **再验证它确实是对的类型** ✓（★ 文本控件有 `text` ✓ / 图片控件有 `imageId` ✓）
              --     ★ ③ 短名兜底保留 ✓（★ 兼容老的模板命名 ✓）
              local dst = nil
              local full = "clue." .. tostring(pos) .. "." .. tostring(slot)
              pcall(function() dst = item:FindChild(full) end)
              if dst == nil then
                pcall(function() dst = item:FindChild(slot) end)
              end
              if dst == nil then
                dst = self:_grid_item_child_cached(item, index, pos, slot)
              end
              -- ★ 类型验证 ✓：不是文本控件、也不是图片控件 ⇒ **不用它** ✗
              if dst ~= nil then
                local okT, okI = false, false
                pcall(function() local _ = dst.text okT = true end)
                pcall(function() local _ = dst.imageId okI = true end)
                if not okT and not okI then
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：单射候选被否(早)　原 L4713..L4717
                  dst = nil
                end
              end
              if dst ~= nil then
                -- ★ 文本 ⇒ 写文字 ✓；★ 图片 ⇒ 成对写 imageSource + imageId ✓（项目铁律 ✓）
                local txt = nil
                pcall(function() txt = k.text end)
                -- ★★★★★★ 2026-10-10 **换源：`letter` 从【控件文本】取** ✗✓✓
                --   ★★★ 地图员第 5 轮实测 ✓：★ `clue_view[i]`（core L2386-2414）**只有 6 个字段** ✗ ——
                --     `index`/`type`/`text`/`satisfied`/`who`/`raw` ✓ ★★ **【没有 `letter`】** ✓
                --     ⇒ ★ `_cl.letter` 恒 nil ✗ ⇒ `_row_letter` 恒空 ✗ ⇒ `letter_of` 恒 nil ✗
                --     ⇒ ★★★ **落兜底 ⇒ 显示旧铅笔笔记 ⇒ 用户看到"还是旧脚本那套"** ✓✓
                --   ★ 用户的问题 ✓：「**当时填 `note` 的素材源到底在哪，查到了换源就行了**」✓
                --     ★ 旧源 = `core.notes[r][c]` 的键（★ 玩家手打的铅笔笔记 ✓）
                --     ★★ 新源 = ★ **`letter.<关>.<行>` 控件的【文本】** ✓（★ 用户配的那段 ✓）
                --   ★ 这里就是那个控件 ✓（★ `slot == "letter"` ⇒ `k` 就是它 ✓ `txt = k.text` ✓）
                -- ★★★★★★ 2026-10-10 **`k` 没有 `text` ⇒ 往下钻**（★ 与 `dst` 那套同因 ✓）✗✓✓
                --   ★★★ 用户实测 ✓：「**选中 `letter` 为 `a` 的卡，会填 `b`、`v`、`e`，也可能填 `a`**」✓
                --     ⇒ ★★ 填的是【人物 id】⇒ ★ **那正是 `core.notes` 的键** ✓
                --     ⇒ ★★★ **【旧 `note` 还在生效】** ✓✓ —— ★ 即 `letter_of` 返回 nil ⇒ 落兜底 ✓
                --   ★ 根因 ✓（★ 与当初"`who` 控件没有 `text`"同一个坑 ✓）：
                --     ★ `k` 是【row 侧】的槽位控件 ✗ ★ **它自己没有 `text`** ✗
                --     ⇒ ★ `txt = k.text` 取不到 ⇒ 上面记下的是 nil ✗ ⇒ `_row_letter` 恒空 ✓
                --   ★ 修法 ✓：★ `txt` 取不到 ⇒ **广度优先往下找第一个有 `text` 的子孙** ✓
                --     ★（★ 与 `dst` 那边"下钻找文本控件"完全一样 ✓）
                -- ★★★★★★ 2026-10-11 **四个槽位都要落账（不只 `letter`）** ✗✓✓
                --   ★★★ 用户报 ✓：「★ **网格视窗消失了** ✓
                --     ★ **这个部分不能坏** ✓ ★ **不然整个 `row` → `clues` → 棋盘的路线就断了**」✓✓
                --   ★ 断在哪 ✗（★ 我修 `n=0` 之后查出来的第二处 ✓）：
                --     ★ 卡片的文字（`who`/`what`/`letter`/`face`）走的是
                --       `_grid_text_payload()` ✓ ★ 而它**从 `vm.clues[i].text` 里切名字** ✗
                --     ★★ 现在 `clues` 是**槽位**（★ 没有 `who`/`what` ✗ 文案是"待填内容（槽位 N）"✓）
                --       ⇒ ★ 切出来恒空 ⇒ ★★ **卡片一片空白** ✓✓
                --     ★ 而这一趟**明明已经把 `row.<关>.<行>` 的四个槽位读到了** ✓
                --       —— ★★ 但只把 `letter` 落进了 `_row_letter`（★ 那是【按人物】的 ✓
                --          给棋盘标记用的 ✓）✗ ★ **`who`/`what` 读到手就丢了** ✓
                --   ⇒ ★★ 修法 ✓：★ **读到的文本按【关序 + 行号】也记一份** ✓
                --     ★ 于是 `_grid_text_payload()` 可以直接用它 ✓ ⇒ ★ 卡片四样就位 ✓✓
                --   ★ 为什么两个键都要 ✓（★ 别混 ✗）：
                --     ★ `_row_letter[人物id]` ⇒ ★ **棋盘上那一格显示的字母** ✓（★ 按人 ✓）
                --     ★ `_row_text[关][行][槽位]` ⇒ ★ **卡片上四样文字** ✓（★ 按行 ✓）
                local _slot_txt = self:_read_control_text(k, slot)
                if _slot_txt ~= nil then
                  local _lvn = self:_level_ordinal()
                  if _lvn ~= nil then
                    Controller._row_text = Controller._row_text or {}
                    local _by_lv = Controller._row_text[tostring(_lvn)]
                    if _by_lv == nil then _by_lv = {}; Controller._row_text[tostring(_lvn)] = _by_lv end
                    local _by_pos = _by_lv[pos]
                    if _by_pos == nil then _by_pos = {}; _by_lv[pos] = _by_pos end
                    -- ★ 只填一次 ✓（★ 与"先到先得"同规矩 ✓ 免得每帧被后来的空值冲掉 ✓）
                    if _by_pos[slot] == nil then _by_pos[slot] = tostring(_slot_txt) end
                    -- ★★ `_grid_text` 缓存要作废 ✓ —— ★ 它是在读到这些之前建的 ✓
                    --   （★ 不作废 ⇒ 卡片永远用那份空快照 ✓）
                    self._grid_text = nil
                  end
                end
                if slot == "letter" then
                  --   ★ 失败时**如实报一次** ✓（★ 不再静默 ✓）
                  local _lt = self:_read_control_text(k, slot)
                  -- ★★★★★★ 2026-10-11 **读到就【当场落账】** ✗✓✓（★ 这是第二个真因 ✓）
                  --
                  --   ★★★ 我第一版把它写成"存进循环外的一个局部变量 ✓ 循环后再落账" ✗
                  --     —— ★ **编译通过、但永远不生效** ✓✓（★ 本次踩到的第二个坑 ✓）
                  --   ★ 机制 ✓：★ Lua 的局部变量**只在自己的块里可见** ✗
                  --     ★ 我把"落账"写在**更深的块**里（`if dst ~= nil` 之内 ✗）
                  --       ⇒ ★ 那里的 `_row_letter` **不是那个局部** ✓
                  --       ⇒ ★ 它退化成**全局变量**（★ 恒 nil ✓）⇒ ★ 判据恒假 ⇒ 静默不落账 ✓
                  --     ⚠️ ★ **Lua 不会报错** ✗（全局读写合法 ✓）—— 与"注释当事实"同族：
                  --       ★ **"编译通过" ≠ "这段在跑"** ✓✓
                  --   ⇒ ★ 修法 ✓：★ **就在读过之后、同一个块里写目标表** ✓ ——
                  --     ★ 不跨块传值 ⇒ 这类坑**结构上不可能再出现** ✓✓
                  --   ★ 键取法 ✓：★ 用 `_grid_text_payload()` 的 `items[pos].id` ✓
                  --     ★ 它**就是** `cl.who`（人物 id ✓ 见 L4432 那段注释 ✓）
                  --     ★ 而且这个载荷是**按关卡记忆化**的 ✓ ⇒ ★ 每帧调用也只算一次 ✓（不new开销 ✓）
                  if _lt ~= nil then
                    -- ★★★★★★★★ 2026-10-11 **键 = 行号** ✗✓✓
                    --   ★ `row.<关>.<行>` 的 `<行>` 就是唯一身份 ✓
                    --     ★ 不查 `who` ★ 不查卡片文字 ★ 不猜（★ 用户的定稿）
                    --   ★ 与 `_row_face` **同一个键**（★ 两样本来就同行）
                    --   ★ 好处：★ **行数 ≠ 棋子数也不丢行** ✓（★ 实测 8 行 / 5 棋子）
                    local _pid = _rowno
                    if _pid ~= nil then
                      -- ★★★★★★★★ 2026-10-11 **"先到先得"整段删掉** ✗✓✓（★ 它把 `D`/`E` 吃掉了 ✓）
                      --
                      --   ★★★ 真机抓到的原文 ✓（★ 用户 2026-10-11 20:24 那份日志 ✓）：
                      --     `★ 同一个人的 letter 被配了两次 ✗：who=`4` 已记=`A`
                      --      这一行（`row.3.4`）=`D` ⇒ ★ 保留先记的那个 ✓` ✗
                      --     `★ 标记来源记下 ✓：`row.3.4` ⇒ who=`4` letter=`D`` ✓
                      --   ★★ 读法 ✓：★ **这一行【读到了 `D`】** ✗ —— ★ 然后被**丢掉**了 ✓✓
                      --     ⇒ ★ 第 4 行留下的是 `A`、第 5 行留下的是 `A`
                      --       ⇒ ★★ **棋盘上就是 `A`、`A`、`F`** ✓✓（★ 与用户报的**逐字相符** ✓）
                      --
                      --   ★★★ 为什么会这样 ✗（★ **是我不对** ✓）：
                      --     ★ 那段"先到先得"是**上一版**为 **`who` 文本键**写的 ✓
                      --       （★ 那时键 = 那一行的 `who` 文本 ✓ ★ 而**两行可以填同一个 `who`** ✗
                      --        ⇒ ★ 那才需要"谁先写谁赢" ✓ —— ★ `case_002` 里 4 个人各被点到两次 ✓）
                      --     ★★ 而**用户已经定稿：键 = 行号** ✓ ⇒ ★ **这个前提【不成立】了** ✗
                      --       ★ 行号是**唯一的** ⇒ ★ `_row_letter[行]` **只会有一个作者** ✓
                      --         ⇒ ★ "先到先得"**无事可做** ✗ ★ 只会**挡住正当的写入** ✓✓
                      --     ★★★ 更糟的是它还**跨命名空间**乱判 ✗：
                      --       ★ `_key = tonumber(_pid)` ✓ 而 `_pid` 现在是**行号**（数字 ✓）
                      --         ⇒ ★ `Controller._row_letter[4]` ✓
                      --       ★★ 而表里那个 `4` 可能是**上一关**留下的
                      --         （★ 或上一版按 `who` 写的 ✓）⇒ ★ 两个**不同的东西**共用一个格子 ✓
                      --         ⇒ ★ **判据看着在保护，其实在破坏** ✓✓
                      --
                      --   ⇒ ★★★ 修法 ✓：★ **无条件写**（按行号 ✓）——
                      --     ★ 一行一个字母 ✓ ★ 后读到的就是这一行的真值 ✓
                      --     ★★ 并**换一条真正该守的判据** ✗：★ **同一行被配了两个不同字母** ✓
                      --       （★ 那才是真冲突 ✓ 而且它**不可能**由跨关/跨命名空间误报 ✓）
                      Controller._row_letter = Controller._row_letter or {}
                      local _old = Controller._row_letter[_pid]
                      if _old ~= nil and tostring(_old) ~= tostring(_lt) then
                        -- ★ 同一行两个不同字母 ⇒ ★ 真冲突 ✓（★ 如实报一次 ✓）
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
                -- ★★★★★★ 2026-10-10 **`dst` 自己没有 `text` ⇒ 往下找【有 text 的子孙】** ✗✓✓
              --
              --   ★★★ 读到了根 ✓（`write_control_text` 的定义在 L3802 ✓）：
              --     `if ctrl == nil or ctrl.text == nil then return false end` ✗
              --   ⇒ ★★ **它要求 `ctrl.text ~= nil`，否则【静默返回 false，一个字都不写】** ✓
              --   ★ 而探针实测 ✓：★ `slot=who  目标控件=who  写前=  写后读回=`
              --     ⇒ ★ **`dst.text` 是空的** ✗ ⇒ ★ **`ctrl.text == nil` ⇒ 被挡住** ✓✓
              --   ⇒ ★★★ **所以 `who` 这个控件【不是文本控件】** ✓
              --     （★ 很可能是**容器** ✓ 文字在它的**子控件**里 ✓）
              --   ★★ 而这也解释了"当年算法也填不进去"✗ —— ★ **它同样被这一行挡住** ✓
              --
              --   ★ 用户提示 ✓（很准 ✓）：「**你没必要去猜往哪填** ✓
              --     **那套被删掉的填入方式确实把东西填进去了，你直接去读它的路径**」✓
              --   ⇒ ★ 读完发现：★ **它用的路径和我【一样】** ✓（`_grid_item_child_cached` ✓）
              --     ⇒ ★★ **所以问题不在"找哪个控件"** ✗ —— ★ **在那个控件【没有 text】** ✓
              --
              --   ⇒ 修法 ✓：★ **`dst` 没有 `text` ⇒ 广度优先找它下面第一个有 `text` 的** ✓
              --     ★ 找到就用它 ✓；找不到 ⇒ 如实报一次 ✓（★ 不再静默 ✓）
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
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：单射下钻失败(早)　原 L4765..L4771
                  else
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：单射下钻失败(早2)　原 L4773..L4777
                  end
                end
              end
              if type(txt) == "string" then
                  -- ★★★★★★ 2026-10-10 **照抄项目自己的写入器：`.text` 不行就试 `SetText`** ✗✓✓
                    --
                    --   ★★★ 用户让我"找和当时算法的差异"✓ —— 找到了 ✓：
                    --     ★ 项目自己的写入器（`engine_adapter_qianxing.lua:4603-4604` ✓）是这样写的：
                    --       `if c.text ~= nil then c.text = txt end`
                    --       `if type(c.SetText) == "function" then pcall(function() c:SetText(txt) end) end`
                    --     ⇒ ★★ **它会【再试 `SetText`】** ✓
                    --   ★ 而我用的 `write_control_text`（L3802 ✓）：
                    --       `if ctrl == nil or ctrl.text == nil then return false end` ✗
                    --     ⇒ ★★★ **`.text` 是 nil 就【直接放弃】，一个字都不写** ✓✓
                    --   ⇒ ★★ 这就是"旧路能填、我的路填不进去"的【全部差异】✓
                    --     ★ 探针也印证 ✓：`写前=` 与 `写后读回=` 都空 ⇒ 写被跳过 ✓
                    --   ⇒ 修法 ✓：★ **`.text` 与 `SetText` 两条都试** ✓（★ 与项目一致 ✓）
                    pcall(function() if dst.text ~= nil then dst.text = txt end end)
                    if type(dst.SetText) == "function" then pcall(function() dst:SetText(txt) end) end
                    -- ★★★★★★ 2026-10-10 **目标控件实况探针** ✗✓✓
                    --   ★★ 用户让我查"`who` 为什么没进去"✓ —— 存档侧查到一条硬差异 ✓：
                    --     ★ 卡片模板 `clue` 的 `who` **没有 `508`/`509`（水平/垂直对齐）** ✗
                    --       而 `letter` **有**（`508=1 509=1`✓）；`what` 也没有 ✓
                    --     ★ `row.1.1` 侧同理 ✓：★ `what.1.1` 有 `508/509` ✓、`who.1.1` **没有** ✗
                    --   ⇒ ★★ 怀疑 ✓：★ **`who` 的框/对齐不对 ⇒ 引擎不画** ✓
                    --     （★ 项目注释原话：「**运行时尺寸可能为 0 ⇒ 那时引擎不画**」✓）
                    --   ★ 本探针 ✅ 把运行时实况打出来 ✓：尺寸 / 位置 / 可见 / 读回 ✓
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：目标控件实况　原 L4805..L4819
                  wrote = wrote + 1
                end
                -- ★★★★★★ 2026-10-10 **图的来源要【往下钻一层】** ✗✓✓（★ 用户推断 ✓）
                --   ★ `face.*` 是**模板引用控件** ✗ ⇒ ★ 它自己没有 `imageId` ✓
                --     ⇒ ★ 真正的图在它引用的模板【里面】** ✓
                --   ★ 所以先把 `k` 钻到"能设图的那个"，再读它的 `imageId`/`imageSource` ✓
                --   ★ 钻不到 ⇒ 退回读 `k` 自己 ✓（★ 兼容"直接是图片控件"✓）
                local _kimg = self:_find_image_holder(k)
                if _kimg == nil then _kimg = k end
                local iid = nil
                pcall(function() iid = _kimg.imageId end)
                -- ★★★★★★ 2026-10-10 **把"谁 ⇒ 那一行的图"记下来** ✗✓✓
                --   ★★★ 为什么必须在这里记 ✓（★ 单射是【唯一摸到控件】的地方 ✓）：
                --     ★ `face` 是【控件】✗ —— 而 `Core:view`（数据层 ✓）**到不了控件** ✓
                --     ⇒ ★★ `view.clues[i].face` **永远是 nil** ✗（★ 实测：落兜底 ⇒ 报 `portrait.B` ✓）
                --     ⇒ ★★★ **只能由"已经读到控件"的单射把值【带出来】** ✓✓
                --   ★ 用户的设计 ✓：「**一切线索区的素材都来自对应的 `row`**」✓
                --     ★ 头像对应 `face` ✓　★ "谁" = 这一行线索的 `who` ✓（★ 棋子 id `A`/`B`/`V`/`D` ✓）
                --     ★ 取法 ✓：★ `self.core:view().clues[pos]`（★ `pos` = 线索序号 ✓）
                --   ★ 存模块级表 ✓（★ `portrait_of` 是静态函数 ✗ 拿不到 `self` ✓）
                --   ★ 下游 ✓：★ `portrait_of` 先查表 ⇒ 返回**数字 id** ✓
                --     ★ `resolve_asset`（adapter L3411 ✓）`tonumber` 直接过 ✓ ⇒ 后面【一切照旧】✓✓
                if iid ~= nil then
                  -- ★★★★★★★★ 2026-10-11 **键 = 行号（与 `letter` 同一把钥匙）** ✗✓✓
                  --   ★ 与本函数上方 `_row_letter` 的取法**完全一致**
                  --     ⇒ ★ **两张表不可能再不一致**（★ 前几轮就栽在这一条）
                  local _key_face = _rowno
                  if _key_face ~= nil then
                    Controller._row_face = Controller._row_face or {}
                    Controller._row_face[_key_face] = iid
                    -- ★★★★★★ 2026-10-10 **同一行也记下 `letter`** ✗✓✓（★ 用户：「像把内容填进 `clue` 的 `what` 一样，
                    --   把 `letter` 的文本填进 `note` 里，和那个一样的路线」✓✓）
                    --   ★ `letter` 的【数据侧已经是对的】✓：`_grid_text_payload` 的 `items[i].letter` ✓
                    --     （★ ui L4395 `letter = tostring(wid or "")` ✓ 而 `wid` 从卡片读 ✓ 卡片由单射填 ✓）
                    --   ⇒ ★★ 缺的只是"送到棋盘" ⇒ ★ 和 `face` 一样，在这里把它带出来 ✓✓
                    -- ★ 换源（地图员第5轮 ✓）：★ 用【`letter` 槽位的控件文本】✓ 而不是 `_cl.letter`（★ 它恒 nil ✗）
                    -- ★★★★★★ 2026-10-11 **落账点已挪到循环【外】** ✗✓✓
                    --   ★ 原来写在这里 ⇒ ★ 依赖"这次循环里刚记下的 `_row_letter_txt`" ✗
                    --     ★ 而它被**循环里的清理**冲掉过 ⇒ ★ 恒 nil ✓（★ 真因见循环开头 ✓）
                    --   ⇒ ★ 现在：★ 值存在局部 `_row_letter` 里 ✓
                    --     ★ 整个子控件循环跑完、在块末尾**按同一个键一次落账** ✓
                  end
                end
                if iid ~= nil then
                  local src = nil
                  pcall(function() src = k.imageSource end)
                  -- ★★★★★★ 2026-10-10 **图片用 `SetImage`，不用属性赋值** ✗✓✓（★ 同文字那次的模式 ✓）
                  --   ★ 项目自己的写入器（`engine_adapter_qianxing.lua:730-732` ✓）：
                  --     `local ok2 = pcall(function() target:SetImage(src, node.image_id) end)`
                  --     `if not ok2 then pcall(function() target:SetImage(node.image_id) end) end`
                  --   ★ 而我写的是 `dst.imageSource = src` ＋ `dst.imageId = iid` ✗
                  --   ★ 项目注释 ✓：「运行时新建的客户端控件，在"根节点"上 `SetImage` 直接返回 false、
                  --     `imageId` 一直是 0」⇒ ★ **属性赋值对图片不通** ✓
                  -- ★ 写入端同样要钻 ✓：★ 卡片的 `face` 也是**模板引用控件** ✗
                  --   ⇒ ★ 把 `dst` 钻到"能设图的那个" ✓；钻不到就用 `dst` 自己 ✓
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
        -- ★★★★★★ 2026-10-11 **落账已挪到"读到的那一处"** ✗✓✓
        --
        --   ★ 这里曾经放"循环后统一落账" ✗ —— ★ 那是**我第一版的错** ✓
        --     ★ 它把 `local _row_letter` 留在**浅块**、把落账写在**深块** ✗
        --       ⇒ ★ 深块里的同名标识符**不是那个局部** ⇒ ★ 退化成全局（恒 nil ✓）
        --       ⇒ ★ **编译通过、一句都不生效** ✗✓（★ Lua 不报错 ✓）
        --   ⇒ ★ 现在：★ 落账就在 `slot == "letter"` 那个块里 ✓
        --     ★ 见 L4432 `_grid_text_payload` 的 `items[pos].id` = `cl.who` ✓
        if (self._row_log or 0) < 6 and print then
          self._row_log = (self._row_log or 0) + 1
          print("[murdoku] ★ 单射命中：`row." .. tostring(lv_no) .. "." .. tostring(pos)
            .. "` ⇒ 写了 " .. tostring(wrote) .. " 个槽位 ✓（★ 内容【由你在编辑器里定】✓）")
        end
        -- ★★★★★ 2026-10-10 **【不做 return】—— 写了就写，其余留给算法** ✗✓
        --
        --   ★★ 用户实测两次，正好指到两个极端 ✓：
        --     · 「**子控件没改序号且重复两遍**」✗ ⇒ 那时是【无条件接管】✓
        --     · 「**我补的 3.9 和 3.1 恢复原样了**」✗ ⇒ 那时是【写了才接管，否则 return】✗
        --       ⇒ ★ 这两行的 `#503` 是空的 ✓ ⇒ 一个槽位都没写到 ⇒ **回落算法 ⇒ 内容被覆盖** ✓✓
        --       （★ 而用户说「**我导出的 `269` 重新导入是正常的**」✓
        --        ⇒ ★ **存档没坏** ✗ —— ★ **是我的脚本把它覆盖了** ✓）
        --
        --   ⇒ ★★★ 正解 ✓：★ **根本不要 `return`** ✗
        --     ★ 找到的槽位 ⇒ 写你配的内容 ✓
        --     ★ 找不到的（★ `#503` 不全 / 空行 ✓）⇒ **算法照常填** ✓
        --   ⇒ ★ **两个极端一起解决** ✓：不会整行空白 ✗ 也不会覆盖你已经填好的行 ✓✓
        --   ⚠️ 仍要防一件事 ✗：★ **写了内容的槽位别被后面的算法覆盖** ✓
        --     ⇒ ★ 下面用 `self._row_wrote` 记下"这一项这几个槽位是你配的" ✓
        --       ★ 由算法那几步跳过它们 ✓（★ 见各槽位写入处的判据 ✓）
        self._row_wrote = self._row_wrote or {}
        if wrote > 0 then self._row_wrote[pos] = true end
        -- ★ 写了 0 个 ⇒ ★ 不 return ✓ ⇒ 继续走算法 ✓（★ 这一行先别空白 ✓）
      end
    end
  end
  -- ★★★★★ 2026-10-10 **只读探针：记录引擎到底把哪几项交给我们** ✗✓
  --   ★ 用户要查清的正是这件事 ✓（日志显示 `n=15` 却只回调 7 次 ✗）
  --   ★ 官方：「仅会加载处于**可见范围**内的列表项」✓ —— ★ 那"可见范围"到底是几项 ✗
  --   ⇒ ★ 这里**只读** ✓ 不写任何功能开关 ✓（★ 上次的教训：探针不许改行为 ✗）
  self._grid_idx_seen = self._grid_idx_seen or {}
  if self._grid_idx_seen[pos] == nil then
    self._grid_idx_seen[pos] = 0
    self._grid_idx_n = (self._grid_idx_n or 0) + 1
    -- ★ 集合每变大一次就报一行 ✓ —— 这样能看到"引擎是逐步交出更多项，还是永远只有那几个"✓
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：探针·引擎交来的项　原 L4894..L4904
  end
  self._grid_idx_seen[pos] = self._grid_idx_seen[pos] + 1
  -- ★ 一次性汇总 ✓：每 600 次回调报一行"各项被回调的次数分布"✓
  self._grid_cb_total = (self._grid_cb_total or 0) + 1
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：探针·回调分布　原 L4909..L4917

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-09 **可见区外的列表项必须关掉射线 —— 而且要按【位置】判，不能按【序号】判** ✗✓
  --
  --   ★ 用户原话 ✓：「我能在线索卡可见区域内选中三个，而**第一行上方还有可选中内容**，
  --     滚轮列表**之上**的区域我选到了**第四个人**……确实把线索**填到了不该有的地方**」✗
  --     换选关条就是「**填进去的关卡错位**」✓
  --
  --   ★ ★★ 我第一版修**错了** ✗（v103 ⇒ 真机仍能点到 ✓ 用户反馈「高亮出现在第一张卡之上」✓）：
  --     我当时的判据是 **`pos > 可见数`** ✗ —— ★ **那是把"可见区"当成了"第 1..N 项"** ✗✓
  --     而真机日志给了反证 ✓：
  --       `★ 网格几何1: itemCount=nil  **scrollProgress=nil** …`
  --     ★ **只读字段全读不到** ✗ ⇒ 我**无法**知道滚动位置 ✗
  --     ⇒ ★ **列表一旦滚动，"可见区"就不是 1..4 项** ✗
  --       ⇒ 被滚到视窗**之上**的项，`pos` 可能很小，却**明明在可见区外** ✓
  --       ⇒ ★ 判决必须看 **这一项在哪儿**，而不是**它是第几项** ✓✓
  --
  --   ★ 官方字段（`ClientUIBaseControl` ✓ 读写 ✓）：
  --     `anchoredPositionX` / `anchoredPositionY` = **位置** ✓
  --     `sizeDeltaX` / `sizeDeltaY` = 尺寸 ✓
  --   ⇒ ★ 判据 ✓：列表项相对**网格视窗**（它的父级 ✓）的位置
  --       视窗高 `H` ⇒ 可见带 `y ∈ [−H/2, +H/2]`（pivot 0.5 ✓ 居中 ✓）
  --       项高 `h` ⇒ 一项**整块**都在带外 ⇔ `|y| > H/2 + h/2`
  --       ⇒ ★ `|y| > H/2 + h/2` ⇒ **完全在可见区外** ⇒ 关射线 ✓
  --     （★ 用"整块在外"而不是"中心在外" ✓ —— 宁可少关一点，也不要误关半露的可点项 ✗）
  --
  --   ★ 为什么是这个机制 ✓（资料员查证 ＋ 我复算 ✓）：
  --     ★ **官方【从未承诺】网格视窗会裁剪或屏蔽射线** ✗
  --     唯一相关的话是「列表采用复用列表结构，出于性能考虑，
  --     **仅会加载处于可见范围内的列表项**」✓ —— 那是**性能机制**，不是裁剪 ✗
  --     ⇒ 官方文档**没有**"裁剪/遮罩/屏蔽射线"的任何表述 ✓（资料员把 API 文档 grep 过 ✓
  --       10 处 `mask` 命中**全是图片控件**的 ✗）
  --
  --   ★ 数字全部实测确认 ✓（真机日志 ✓）：
  --     项高 96 · 纵间距 8 · 上/下边距 20/20 · 视窗 400×**544** ⇒ 可见 4 项 ✓
  --     内容总长 **`GetContentLength=760`** ✓（= 20+7×96+6×8+20 ✓ 我算的 760 ✓ **逐位吻合** ✓）
  --     ⇒ ★ 760 > 544 ⇒ **确实溢出 216 px** ⇒ 有 3 项在可见区外 ✓✓
  --
  --   ⚠️ 读不到位置就**什么都不做** ✓（宁可不修，也不能误关可见项 ✗）
  --   ★ 每次回调按**当前**位置现算 ✓ ⇒ 将来上了滚动，被滚进来的项**自动恢复** ✓
  --     （所以**不缓存"关过谁"** ✓ —— 与 `_fill_grid_item` 的无状态约定一致 ✓）
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：「按位置关射线」空壳（真机已否掉）　原 L5004..L5051

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-10 **超出容量的项 ⇒ 做成「空白 ＋ 不能点」** ✗✓ —— ★ 用户想的方案 ✓
  --
  --   ★ 用户原话 ✓：
  --     「我觉得还有一种等价方案 —— 之前本来就出现过**在列表上却没有填内容也不能选的卡**，
  --       那我们直接把**前两张卡换成这种设置**不就绕过了这个问题 ✓
  --       既然**避免不了溢出**，就放**两张空白且不能点的卡**不就行了」✓
  --
  --   ★★ 为什么这个方案**成立** ✓（三条官方事实拼起来 ✓）：
  --     ① 官方：★「网格视窗的列表采用**复用列表**结构，出于性能考虑，
  --          **仅会加载处于可见范围内的列表项**」✓
  --     ② 官方：★「网格视窗**列表发生滚动时**：对列表项内容进行刷新(**触发回调**)」✓
  --     ③ 实测：★ 引擎**确实会重进回调** ✓（真机累计 60 次 ✓）
  --     ⇒ ★★ **引擎只会为"进入可见范围"的项重进回调** ✓
  --     ⇒ ★★★ **所以：一开始把超出容量的项清空 ✓
  --        它们被滚进可见区时，引擎【会自动重进回调】把它们填回真实内容** ✓✓
  --        回到区外则不会 ← ⚠️ 见下面的"残留"说明 ✓
  --   ⇒ ★ **不需要 `ScrollToItemAt`** ✓ ★ **不需要知道滚动窗口** ✓
  --     ★ **引擎自己的滚动与滚动条全部保留** ✓ —— ★ 正合用户「还是自带的网格视窗更方便」✓
  --
  --   ★ 容量 ✓：`_grid_visible_count()` 现在算得对 ✓（真机数 ⇒ **5 项** ✓）
  --   ★ 溢出 ✓：7 项 − 5 = **2 项** ✓ ⇒ ★ **正是用户说的"两张卡"** ✓✓
  --
  --   ⚠️ **一处残留（如实说明 ✓）**：★ 滚出去的项**不会**再被回调 ⇒
  --     它的"可点"状态会**留着** ✗ ⇒ ★ 若用户滚下去又滚回来，先前被填实的那几项
  --     回到区外时**仍可点** ✗ —— ★ 比修之前好得多（**默认状态下完全不出现** ✓）
  --     但要**彻底**解决仍需脚本接管滚动（乙 ✓）
  --   ★ 只清**装饰与文字** ＋ **关射线** ✓ —— 不动几何、不动模板 ✓
  --
  --   ★★★★★ **关键设计点：只在【我们自己那趟】清，绝不在引擎重进时清** ✗✓
  --     ★ 我第一版写成"每趟都判 `pos > cap`"✗ ⇒ ★ **错** ✗：
  --       ★ 用户滚下去 ⇒ 第 6 项进入可见区 ⇒ 引擎重进回调 ⇒ `pos=6 > 5` ⇒
  --         ★ **被我又清一遍** ✗ ⇒ ★ **第 6 项永远显示不出来** ✗✗
  --     ⇒ ★ 正确 ✓：
  --       · `_grid_in_refresh == true`（**我们**调 `RefreshItems` ✓）⇒ ★ 超出容量的才清 ✓
  --       · `_grid_in_refresh == false`（**引擎**重进 ✓）⇒ ★ **一律正常填** ✓
  --         ⇒ ★ **滚进可见区的项自动恢复真实内容** ✓✓（这就是本方案能成立的关键 ✓）
  -- ★★★★★ 2026-10-10 **「空白占位项」整段已移除** ✗✓
  --
  --   ★ 它当初是为解决「多出的线索填不上」而加的 ✗ —— ★ 而那个前提**已被只读探针证伪** ✓：
  --     `★ 探针·本次 RefreshItems：传了 n=15 条；回调进来 7 次；视窗子控件 7 个`
  --     `★ 网格视窗：滚动时引擎**会**重进 RefreshItems 回调 ✓`
  --     `★ 探针·引擎交来的项：新增 pos=8 … 15` ✓✓
  --   ⇒ ★★ **滚动时引擎会【逐个交出】后面的项** ✓ ⇒ ★ **ListView 完全正常** ✓
  --   ⇒ ★ 用户也实测到「后续卡**依然被填上了头像**」✓ ⇒ ★ **填充没问题** ✓
  --   ⇒ ★ **所以不但不必「占位」，占位反而有害** ✗：它会清空本该正常的项 ✓
  --   ★ 教训 ✓：★ **先证明「坏」存在，再加补丁** ✗ —— ★ 猜个坏因就下补丁，补丁会自己制造症状 ✓
  --   ⚠️ `_grid_visible_count` / `_grid_band` **保留** ✓（只读、无害 ✓）

  -- ★★★★★ 2026-10-05 **文案查缓存表，不再"每条线索重建一次整视图"**。
  --
  --   改之前：这里每进一次回调就 `self.core:view()` 一次 ⇒ 一次回调 **7 次**整视图重建
  --   （实测单次 0.235 ms ⇒ 白花 1.6 ms），而回调在滚动时是**每帧**进来的。
  --   文案只跟关卡数据有关（见 `_grid_text_payload` 的注释）⇒ 算一次就够。
  local pay = self:_grid_text_payload()
  local cl = pay.items[pos]
  -- ★★★★★★ 2026-10-11 **`cl == nil` 不许提前 `return`** ✗✓✓
  --
  --   ★★★ 用户报 ✓：「★ **目前链路还是断的** ✓ ★ **放置行为等依旧不通**」✓
  --     ＋ ★ 他指的路 ✓：「★ **就是网格视窗的光标事件断了** ✓
  --       ★ **原本的光标事件是通的，损坏必然来自 `clues` 重构**」✓✓
  --
  --   ★★★ 协作方把实现逐行测绘出来了 ✓（`网格视窗-光标事件-实现测绘.md` ✓ 结论采信 ✓）：
  --     ★★ **断点就是这一行** ✗ —— ★ 它下面还有**两件必须做的事** ✓：
  --       ★ **① 把 `gray` 层的射线关掉** ✓（★ 否则 `gray` 盖在最上层**吃点击** ✓）
  --       ★ **② `self:_grid_bind_item_click(adapter, grid, item)`** ✓（★ **绑点击就在函数最后** ✓）
  --     ⇒ ★★★ **这一行一跳过 ⇒ 两件都不跑** ✓ ⇒ ★★ **卡片点不动 ＋ `gray` 抢点击** ✓✓
  --       ★ 而 `gray` 抢点击这一条**恰好解释了"点了跟没点一样"** ✓✓
  --
  --   ★ 为什么"理论上不会来"却真的会来 ✗（★ 这是本行的原注释 ✓ 而它错了 ✓）：
  --     ★★ `pos` 由 **`_grid_base`** 决定 ✓（`pos = index - _grid_base + 1` ✓）
  --     ★ 而 `_grid_base` 的判定挂在**一个前提**上 ✗：
  --       ★「**第一次回调一定是列表顶端**」✗（★ 见 L4884-4890 的注释 ✓）
  --     ★★ 这个前提**本项目自己后来证伪了** ✗（★ 多项叠在同一位置 ⇒ 一次射线命中全部 ✓）
  --       而且 **`_grid_base` 永不重置** ✗ ⇒ ★ **错一次 ⇒ 错一辈子** ✓✓
  --     ⇒ ★★ **`pos` 一整列错位 ⇒ `pay.items[pos]` 越界 ⇒ 本行 `return`** ✓✓
  --
  --   ⇒ ★★★ **修法（与协作方的"治标＋治本"两条一致 ✓）**：
  --     ★ **① 本处：不再提前 `return`** ✗ —— ★ 用**空壳记录**接着往下走 ✓
  --       　（★ 后面只用到 `cl.who/what/letter/id/portrait` ✓ **全部容得下空串** ✓）
  --     ★ **② `_grid_bind_item_click` 提到 `cl` 之前** ✓ ⇒ ★ **绑点击【与有没有文案无关】** ✓✓
  --   ★ 为什么这样最稳 ✓：★ **"能不能点"不该取决于"有没有内容"** ✓ ——
  --     ★ 内容没配好 ⇒ ★ 该"卡片是空的" ✗ ★ 不该"卡片点不动" ✗✓
  if cl == nil then
    -- ★ 空壳 ✓：★ 每个字段都是**中性值** ✓ ⇒ 后面的写入变成"写空串/不写" ✓ 不会报错 ✓
    cl = { who = "", what = "", letter = "", id = nil, portrait = nil }
  end
  local t_who, t_what, t_letter = cl.who, cl.what, cl.letter
  -- ★★★★★ 2026-10-07 **已正式放置 ⇒ 卡片盖一层灰白** ✗✓（用户新功能 ✓ 模板侧已加控件 `gray` ✓）
  --   ★ 分工（用户定的 ✓ 也是"能走控件就不走脚本"✓）：
  --     · ★ **模板**：★ 列表项模板 `clue`（1073742421）里加了一个**图片控件 `gray`** ✓
  --       ★ 它在同级里排**第 7/7 = 最上层** ✓ 尺寸/位置/颜色/20% 透明**全在编辑器里** ✓
  --     · ★ **脚本只做一件事** ✓：★ **按"这个人是否已正式放置"开/关它的可见性** ✓
  --   ★ 判据用 **`core.placed[cl.who]`** ✓（★ `cl.who` 就是人物 id ✓ 与徽章字母同一个 ✓）
  --   ★ 规矩：★ **与 `face`/文字同一套"值变了才写"** ✓ ⇒ 稳态零成本 ✓
  --   ⚠️ 列表项是复用的 ✓ ⇒ 每次填充都要按**当前 `pos`** 重新判 ✓（不能缓存上一次的结论 ✓）
  -- ★★★★★ 2026-10-07 **人物 id 要从【头像素材名】取** ✗✓（真机诊断一次命中 ✓）
  --   ★ 证据 ✓：★ `★ 灰白诊断：pos=3  who=老宅主  placed=false  找到gray=true` ✓
  --     ⇒ ★ `cl.who` 是**显示名**（老宅主 ✗）而不是 **id**（`V` ✓）
  --       ⇒ ★ `core.placed["老宅主"]` 恒为 nil ⇒ ★ **灰白永远不开** ✓✓
  --   ★ 而列表项本来就知道 id ✓：★ **头像素材名 `portrait.V`** ✓（★ 填充里用 `t_portrait` ✓）
  --     ⇒ ★ 去掉 `portrait.` 前缀就是 id ✓（★ 与 `who=V` / `who=D` 同一套字母 ✓）
  -- ★★★★★ 2026-10-07 **id 改用【核心视图】那条记录** ✗✓
  --   ★ 上一版从 `t_portrait` 取 ⇒ 真机仍是 `placed=false` ✗（★ 说明那个变量在这段作用域里不是 `portrait.X` 格式 ✓
  --     或索引对不上 ✓）⇒ ★ **不再猜变量** ✓
  --   ★ 权威来源 ✓：★ **`诊断CLUE` 早就证明** 视图里的线索记录有 **`who=V`**（★ id ✓ 不是显示名 ✓）
  --     ⇒ ★ 用 `self.core:view().clues[pos].who` ✓ 取不到再退回 `t_portrait` ⇒ 再退回 `cl.who` ✓
  -- ★★★★★ 2026-10-09 **删掉这里的 `core:view()` —— 它取到的值【一定会被覆盖】** ✗✓
  --   ★ 原文（三段的实际效果）✓：
  --       local _pid = nil
  --       pcall(function() local v = self.core:view() … if cc.who then _pid = cc.who end end)  ← 取一次视图
  --       if _pid == nil and t_portrait ~= "" then _pid = t_portrait 去掉前缀 end
  --       if t_portrait ~= "" then _pid = t_portrait 去掉前缀 end        ← ★ 无条件，把上面整个覆盖 ✗
  --     ⇒ ★ **第三个 `if` 无条件执行** ⇒ 第二个 `if` 与那个 `pcall` **全是白做的** ✓
  --       （`_pid` 最终**只由 `t_portrait` 决定** ✓）
  --   ★ 代价（实测 `tests/grid_cost.lua` ✓）：★ **每个列表项 2 次整视图重建** ✗
  --       · 一次回调 7 项 ⇒ `view=14` ✗ · 连续 5 次重进 ⇒ `view=70` ✗（**与重进次数线性增长** ✓）
  --       · 而 `core:view()` 单次 **0.175 ms**（`[F]` 段实测 ✓）⇒ 一次重进白烧 **≈2.5 ms** ✓
  --       · 更要命的是它**击穿了记忆表** ✗：文案快照本来让重进零成本（`文字写入=0` ✓），
  --         而这两次视图重建让"引擎每帧重进"变成**每帧 2.5ms** ✗（用户第五轮指示：负载最小 ✓）
  -- ★★★★★ 2026-10-09 **改回来了（我上一步删过头了 ✗）—— 顺序是【id 优先、素材名兜底】** ✗✓
  --
  --   ★ 我真机上看到的现象 ✓（用户 2026-10-09 18:03 那份日志）：
  --       `★ 灰白诊断：pos=1  who=医生  placed=false  找到gray=true  ★ id=医生  portrait=nil`
  --     ⇒ ★ **`id=医生`（显示名 ✗）** —— 而**之前**同一行是 `★ id=B` ✓
  --     ⇒ 用户侧表现：★ **「case_001 线索区的所有选中反馈都消失了」** ✗
  --
  --   ★ 根因（**是我不对** ✗）：我上一步的推理只对了一半 ✗
  --     我当时说「第三个 `if` 无条件覆盖 ⇒ 那个 `pcall(core:view())` 是白做的」——
  --     ★ **只有在 `t_portrait` 非空时才成立** ✗
  --     ★ 而 `t_portrait` **为空**时，那个 `pcall` 取到的 `cc.who` 会**留下来** ✓
  --       而它**是唯一的 id 来源**（视图记录的 `who` 是 `V`/`D` 这种**字母 id** ✓
  --       见 L4211 老注释与 `诊断CLUE` 的 `who=V` ✓）
  --     ⇒ ★ 我把"唯一能拿到 id 的那条路"删了 ⇒ id 退化成显示名
  --       ⇒ `core.placed["医生"]` 恒 nil ⇒ ★ **灰白 + 选中反馈全没** ✓
  --
  --   ★ 正确修法 ✓：**从 `_grid_text_payload` 的快照里拿 `cl.id`** ✓
  --     · 那份快照建的时候**本来就有一份 `vm` 在手**（L4114 `local vm = core:view()` ✓）
  --     · 所以取 `cl.who` 存下来是 **零额外成本** ✓
  --     ⇒ ★ 既**拿回了 id** ✓ 又**没有**把"每次回调 14 次整视图重建"带回来 ✓✓
  --   ★ 优先级（与 L4211 老注释一致 ✓）：**id（权威）→ 素材名去前缀 → `cl.who`（显示名，最后兜底）**
  --
  -- ★★★★★★★★ 2026-10-11 **这一行原来会在【数字】上取长度 ⇒ 每帧抛错** ✗✓✓
  --
  --   ★ 原文 ✓：★ `if _pid == nil or _pid == "" or #_pid > 2 then …` ✗
  --     ★★ 而 `cl.id` 现在是 **`i`（行号，数字）** ✓（★ 见 `_grid_text_payload` ✓）
  --       ⇒ ★ `#_pid` 作用在**数字**上 ⇒ **抛错** ✓✓：
  --         `attempt to get length of a number value (local '_pid')` ✗
  --   ★★★ 后果有多重 ✗（★ 这才是要害 ✓）：
  --     ★ 这一抛发生在 **`_fill_grid_item` 的回调里** ✓
  --       ⇒ ★★ **整张卡都填不上** ✓ ⇒ ★ 表现是「**线索区点击反馈全坏**」✓✓
  --         （★ 与真机 v104 那次事故**同一个形状** ✓ 见本文件"回调一次都没抛过异常"那条护栏 ✓）
  --   ★ 修法 ✓：★ **先按类型分流** ✗ —— ★ 数字 ⇒ 本来就是行号 ✓ 直接用 ✓
  --     ★ 字符串 ⇒ 才谈"长度/`@` 前缀"那两条老护栏 ✓
  local _pid = cl.id
  if type(_pid) == "string" then
    -- ★ 老护栏 ✓：空串、超长（显示名/素材名 ✓）、`@` 特殊角色（如 `@thief` ✓）都不算"人"
    if _pid == "" or #_pid > 2 then _pid = nil end
    if _pid ~= nil and _pid:sub(1, 1) == "@" then _pid = nil end
  end
  if _pid == nil then _pid = cl.who end
  if type(_pid) == "string" then
    if _pid == "" or #_pid > 2 or _pid:sub(1, 1) == "@" then _pid = nil end
  end
  -- ★★★★★★★★ 2026-10-11 **灰白层必须用【棋子 id】查 `core.placed`（键是棋子 id ✗ 不是行号）** ✗✓✓
  --
  --   ★★★ 这是我【自己引入的回归】✗✓（★ 独立复核者之外、由 `grid_cost` 的护栏抓出来的 ✓）：
  --     ★ v183 把棋盘线的键统一成**行号**之后 ✓ `cl.id` 也跟着变成**行号**了 ✓
  --       （★ 见 `_grid_text_payload` 里 `id = (rt and rt.who) or …` ✓
  --        ★ 而 `rt` 现在按行存 ⇒ ★ 那个 `id` 就是**第几行** ✓）
  --     ★★ 而 **`core.placed` 的键是【棋子 id】** ✗（★ `do_place` 里 `self.placed[who] = true` ✓
  --        ★ `who` = `core.selected` = 棋子 id ✓）
  --       ⇒ ★ `core.placed[行号]` **恒 nil** ✓ ⇒ ★★ **灰白层永远不开** ✓✓
  --     ★★★ 表现 ✓：★ **"线索区的选中/已放置反馈全消失"** ✗ ——
  --       ★ 这正是 `grid_cost` 的 H 段专门守着的那件事 ✓（★ 它 2026-10-09 就因同一个症状加过护栏 ✓）
  --   ⇒ ★ 修法 ✓：★ **行号 → 棋子 id** ✓（★ 与棋盘线**同一个换算** ✓ `_piece_at_row` ✓）
  --     ★ 判据 ✓：★ `cl.id` 是行号时就换 ✓；★ 若它**本来就是棋子 id**（老路径/手写线索 ✓）
  --       ⇒ ★ 换不出来 ⇒ **原样用它** ✓（★ 向后兼容 ✓ 不会更差 ✓）
  if _pid ~= nil then
    local _as_piece = Controller._piece_at_row(self.core, tonumber(_pid))
    if _as_piece ~= nil then _pid = _as_piece end
    -- ★ 顺带把"太长就不当 id"那条老护栏保留 ✓（★ 显示名/长文本一律不当 id ✓）
    --   ⚠️ ★ 先 `tostring` 再取长度 ✗ —— ★ `_pid` 现在是**行号（数字）** ✓
    --     ★★ 直接 `#_pid` ⇒ `attempt to get length of a number value` ✗✓
    --       （★ 真机与回归都当场抓到 ✓ 见 `grid_cost` 的"回调没抛过异常"那条 ✓）
    if type(_pid) == "string" and #_pid > 2 then _pid = nil end
  end
  local _placed_now = (_pid ~= nil) and self.core ~= nil and self.core.placed ~= nil
    and self.core.placed[_pid] == true
  local _cgray = self:_grid_item_child_cached(item, index, pos, "gray")
  -- ★ 2026-10-07 一次性诊断：★ "灰白没出现"到底是【没找到 `gray`】还是【placed 判错】✓
  --   ★ 真机反馈 ✓：★ 颜色在编辑器里都对 ✓ 但**没有卡变灰** ⇒ ★ 说明**脚本这侧没生效** ✓
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：灰白诊断　原 L5085..L5090
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：旧调色板残余 109 行 do（_pal 恒 nil）　原 L5183..L5291

  -- ★★★★★★ 2026-10-10 **旧调色板 `portrait.*` 全套【已删除，266 行】** ✗✓✓
  --
  --   ★★ 用户指令 ✓：「**旧的那套东西不要只是关掉，直接把它们从脚本里删干净，一行都不要留**」✓
  --
  --   ★ 删了什么 ✓（★ L5293..L5558 ✓）：
  --     ★ ① 调色板查找 `assets/portrait.<id>`（★ 190 行 ✓）
  --     ★ ② **旧的"头像贴图"覆盖段 45 行** ✗ ← ★★ 这就是"头像不上"的直接原因 ✓
  --        ★ 它拿【调色板的图】写卡片 `face` ✓，★ 而调色板已空 ⇒
  --        ★★ **它把单射写好的头像【盖掉】** ✗✓
  --
  --   ★★ 为什么以前删不掉 ✗（★ 两次失败的确切数据 ✓）：
  --     ★ 第 1 次删 L5308..L5512 ⇒ `luac: 5730: <eof> expected near end` ✗
  --     ★ 第 2 次删 L5293..L5513 ⇒ `luac: 5720: <eof> expected near end` ✗
  --     ★★★ 真因 ✓：★ **`do`(L5300) 的配对 `end` 在 L5558** ✗，
  --       ★ 而 **L5513 的 `end` 关的是 `if`(L5325)** ✓ ⇒ ★ 删到 5513 必然少关一个 `do` ✓✓
  --     ★ 由 `tools/lua_blocks.mjs` 机械判定 ✓（★ 先"去注释去字符串"再配对 ✓，
  --       自检"全文深度回到 0"✓），★ 并**干跑编译验证**过 ✓（★ 删 5293-5558 ⇒ luac 通过 ✓）
  --
  --   ★ 头像现在【唯一来源】✓：★ `assets/row.<关>.<行>/face.<关>.<行>` 的图 ✓
  --     ⇒ ★ 单射直连到卡片的 `face` ✓（★ 一对一 ✓）
  --     ★ 用户已换好控件 ✓：真机存档 `row.1.1/face.1.1` 的图片 id = `112042` ✓
  --
  --   ★ 存档侧已确认 ✓：★ `portrait.*` 记录 **0 个** ✓ ⇒ ★ 删除**不丢任何控件** ✓
  --
  --   ⚠️ ★ 地图员/工具负责人另发现一个**活 bug** ✗（★ 与被删段无关 ✓ 见 L5166 ✓）：
  --     ★ `t_portrait` 在 L5166 被使用，★ 而它的 `local` 声明在 L5585 ✗
  --     ⇒ ★ **词法作用域 ⇒ 5166 处解析成全局 ⇒ 恒为 nil** ✓
  --     ⇒ ★ 那个分支**永不执行** ✓ ⇒ ★ **"灰白层对不上"很可能有这一半原因** ✓
  --     ★（★ 待修 ✓ 不在本次删除范围 ✓）
  --
  --   ★ `_pal` 保留为 `nil` ✓ —— ★ 后面仍在读它的地方不会报错 ✓
  local _pal = nil
  if _cgray ~= nil then
    -- ★★★★★ 2026-10-07 **灰白图必须【不参与射线】** ✗✓（"预放置也像被取消选中"的真因 ✓）
    --   ★ 真机反馈 ✓：★ 灰白出来之后 ⇒ ★「★ **预放置也会取消选中，且要双击才能重新选中**」✗
    --   ★ 机制 ✓：★ `gray` 是卡片里**最上层**的图片 ✓ ⇒ ★ 它**挡在最上面吃点击** ✗
    --     ⇒ ★ 单击落在它身上 ⇒ **到不了卡片按钮** ⇒ ★ 表现就是"点不中/像没选中" ✓✓
    --   ⇒ ★ 这里把它的**射线与交互一起关掉** ✓ ⇒ ★ **点击穿透到卡片** ✓（★ 灰白只是视觉层 ✓）
    --   ⚠️ 只做一次（★ 记住做过 ✓ 免得每帧写字段 ✓）
    -- ⚠️⚠️ 2026-10-07 **必须【按列表项实例】记** ✗✓（我第一版用了全局标志 ⇒ 只有第 1 个实例做了 ✗）
    --   ★ 真机证据 ✓：★ 日志里那句"已关掉射线"**只出现一次**（紧跟 `pos=1` ✓）
    --     ⇒ ★ 其余 6 个实例（以及后来复用的）**射线还开着** ✗ ⇒ ★ **放置过的卡上抢点击依旧** ✓✓
    --   ★ 列表项是复用的 ✓ ⇒ 每个实例各记一份 ✓（挂在 `_grid_item_rec` 的缓存表上 ✓）
    -- ★★★★★★ 2026-10-11 **"关射线"这段已抽成 `_grid_disable_gray_raycast`** ✗✓✓
    --   ★ 原来它写在这里 ✗ ⇒ ★ 位置在 `cl == nil` 那个 `return` **之后** ✓
    --     ⇒ ★★ **跳过一次就永远不关** ⇒ ★ **`gray` 挡在最上层吃点击** ✓✓
    --   ★ 现在 ✓：★ 统一由函数**最前面**那次调用负责 ✓（★ 与"有没有内容"解耦 ✓）
    --     ★ 这里**不再重复** ✗ —— ★ 同一件事两处写 ⇒ ★ 又是"两套实现"的老坑 ✓
    --     ★（★ 用户 v177 日志里那句"已关掉射线"**照样出现** ✓ ⇒ ★ 说明原来那条路
    --        在他那次会话里**确实跑到了** ✓ —— ★ 所以"点不动"的原因不只在 `cl == nil` ✓
    --        这一点由新加的「卡片点击进来了」探针去定 ✓✓）
    --   ⚠️ 下面只留**可见性**那一半 ✓（★ 它依赖 `_placed_now` ✓ 与射线无关 ✓）
    local _rg = self:_grid_item_rec(item, index)
    if _rg ~= nil and _rg.gray ~= _placed_now then
      _rg.gray = _placed_now
      if _cgray.SetVisible then pcall(function() _cgray:SetVisible(_placed_now) end) end
      if _cgray.SetActive then pcall(function() _cgray:SetActive(_placed_now) end) end
    end
  end
  -- ★ 2026-10-10 已删（地图员干跑 PASS ✓）：local t_portrait 声明（★ 位置在使用之后 ✗ ⇒ 已删 ✓）　原 L5003..L5003

  -- ★ 子控件句柄走记忆表（改之前：一次回调 54 次 `item:GetChild`，滚动时每帧 54 次）
  local c_who    = self:_grid_item_child_cached(item, index, pos, "who")
  local c_what   = self:_grid_item_child_cached(item, index, pos, "what")
  local c_letter = self:_grid_item_child_cached(item, index, pos, "letter")
  -- ★ 2026-10-15：★ 高亮那一笔要的那个子控件 ✓（★ 与上面三个同一条取法 ✓
  --   ★ 取到就交给函数 ✓ 取不到函数自己再取一次 ✓ —— ★ 两种时机都对 ✓）
  local c_backrop1 = self:_grid_item_child_cached(item, index, pos, "backrop1")
  -- ★ 2026-10-10 已删（地图员干跑 PASS ✓）：死变量 c_face（★ 单射不走它 ✓ 按槽位名自己取 ✓）　原 L5009..L5009

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **头像：每个列表项实例要【各写各的 `imageId`】** ✗✓
  --
  --   ★ 起因（★ 用户实测 ✓）：★「★ **五张卡的头像都一样**」✗
  --   ★ 根因 ✓：★ `face` 是**图片控件** ✓ ★ 模板只有一份 ✓
  --     ⇒ ★★ **它不会自己变** ✗ —— ★ 必须**逐个实例**写 `imageId` ✓✓
  --     ★（★ 文字那三个早就在写 ✓ ⇒ ★ 所以文字会不同、头像不会 ✓ —— 正是用户看到的现象 ✓）
  --
  --   ★ 写图的两条规矩（★ 与适配器里那条正路一致 ✓，见 `engine_adapter_qianxing.lua` L18/L705 ✓）：
  --     ★ ① ★ **优先 `SetImage(img.imageSource, id)`** ✗ —— ★ 沿用**编辑器里配的来源** ✓
  --        ★ 兜底才 `SetImage(id)` ✓（★ 真机上 `SetImage(nil, id)` 会失败 ✓ 那条注释写着 ✓）
  --     ★ ② ★ **素材名要过 `adapter:resolve_asset`** ✓ —— ★ 它把 `portrait.A` 变成可用的 id ✓
  --        ⚠️ ★ **`nil` 时【绝不能调】** ✗ —— ★ `resolve_asset` 查不到会 `warn_once` **打报错** ✓
  --        （★ 那个警告注释在 `engine_adapter_qianxing.lua` L4019 ✓）
  --     ★ ③ ★ **只在"这一项换了代表哪条线索"时写** ✓ —— ★ 与文字同一套去重 ✓
  --        ★（`tv.idx ~= index` ✓）⇒ ★ 稳态零成本 ✓
  --   ★ 失败一律 `pcall` ✓ ⇒ ★ 图没设上只失去"头像不同" ✗ ★ 不会把引擎的滚动打断 ✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：旧 cl.portrait 写 face（★ 非 bug ✓ 只是删干净 ✓）　原 L5177..L5194

  -- ★★★★★ 2026-10-05 **文字只在"真的不一样"时才写**（写一次 = 引擎重排一次文本）。
  --
  --   改之前：一次回调无脑写 21 次（7 项 × 3 个角色），**内容一个字都没变也照写**
  --   ⇒ 滚动时每帧 21 次文本重排，纯浪费（"每帧重排文字"是 UI 卡顿最常见的来源）。
  --   ⚠️ 但「**空字符串照写**」这条规矩**必须保住**（用户明确要求）：复用出来的列表项上
  --      留着上一条的残留文字是"滚动之后内容错位"的经典成因 ⇒ 这里用 `tv.idx ~= index`
  --      来判断"这一项**换了代表哪条线索**"：换了就把三个角色**全部重写一遍**
  --      （哪怕新文字与旧文字相同），没换才逐字比较。既省掉稳态的 21 次，也不放过复用。
  local rec = self:_grid_item_rec(item, index)
  local tv = rec and rec.text
  if tv == nil or tv.idx ~= index then
    tv = { idx = index }
    if rec ~= nil then rec.text = tv end
  end
  if tv ~= nil then
    -- ★★★★★★ 2026-10-10 **算法不再填文案** ✗✓✓ —— ★ 用户要求 ✓
    --
    --   ★★ 用户原话 ✓（很准 ✓）：「**所以为什么不像我说的，把填文本的算法直接删了**？
    --     **与其和它竞争覆盖，不如让这一堆吃性能还干扰功能的废弃脚本直接消失**」✓
    --
    --   ★ 它现在的处境 ✓：
    --     ★ ① **功能上完全冗余** ✗ —— ★ 内容由 `assets/row.<关>.<行>` 提供 ✓
    --     ★ ② **每帧都在跑** ✗ —— ★ 引擎每帧重进回调 ⇒ ★ **每秒 60 次全量算法** ✓
    --     ★ ③ **它在和单射抢覆盖** ✗ —— ★ 逼我加"末次单射"这种补丁 ✓
    --   ⇒ ★★ 留着它只有坏处 ✓ ⇒ ★ **关掉** ✓
    --
    --   ★ 保留的部分 ✓（★ 这些不冲突 ✓）：
    --     ★ **`gray` 灰白层** ✓　★ **高亮** ✓　★ **列表项点击** ✓　★ **格子/棋盘** ✓
    --   ★ 想恢复 ✗：★ 把下面 `ALGO_TEXT` 改成 `true` 即可 ✓（一行 ✓）
  -- ★ 2026-10-10 已删（地图员死代码清单 ✓）：ALGO_TEXT 剩余死块　原 L5425..L5456
      end   -- ★ if ALGO_TEXT then 收尾 ✓

  -- 子控件找不到时**只报一次**（这条日志直接告诉你要在模板里补哪个名字）
  if c_who == nil or c_what == nil or c_letter == nil then
    self:_grid_log("childmiss", "网格视窗：列表项子控件 who/what/letter = "
      .. ((c_who ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_what ~= nil) and "有" or "**缺**") .. "/"
      .. ((c_letter ~= nil) and "有" or "**缺**")
      .. "（模板 1073742421 里应叫 `clue.1.who` / `clue.1.what` / `clue.1.letter`）")
  end


  -- 点击 → 聚焦（未验证能力，全程 pcall + 只报一次结论）
  -- ★★ 2026-10-11 **绑定已提到函数【最前面】** ✗✓（★ 原来就在这一行 ✓ 见开头那段注释 ✓）
  --   ★ 为什么必须提 ✗：★ 它前面的任何 `return` 都会把"绑点击"一起跳过 ✓
  --     ⇒ ★★ **卡片点不动** ✓（★ 而这一条恰好是用户报的"链路断了" ✓✓）
  --   ★ 保留这一行也**无害** ✓：★ `_grid_bind_item_click` 幂等 ✓（弱键去重 ✓）
  --     ★ 但**不再依赖它** ✗ —— ★ 判据在最前面就已经满足 ✓
  self._grid_bind_n = (self._grid_bind_n or 0) + 1
  -- ★ 2026-10-10 已删（地图员干跑 PASS ✓）：最后一条内联诊断（★ 地图员：整行可删 ✓）　原 L5277..L5277

  -- ★★★★★★★★ 2026-10-15（第二轮）**卡片高亮的【真机那一份】—— 在这里画** ✗✓✓
  --
  --   ★★★ 为什么第一轮没修好 ✗（★ 这一条是本轮最重要的发现 ✓）：
  --     ★ 第一轮把高亮改成**派生值** ✓ 但**派生的出口是 `clue.focus` 样式** ✗
  --     ★★ 而那个样式挂在 **老卡片 `clue.<n>` 节点**上 ✓ ★ 只有**老路径**会建它们 ✓
  --     ★★★ 真机上 `_grid_state == "on"` ✗（★ 诊断实测 ✓ 见 `render` 里那段 L7304 ✓）
  --       ⇒ ★ **老卡片那段整段不进规划** ✓ ⇒ ★ **`clue.focus` 在真机上根本没人读** ✓✓
  --     ⇒ ★★ 用户说"没修好"是**对的** ✓ —— ★ 我只修了模拟器走的那条路 ✗
  --
  --   ★★★ 真机上那张卡的视觉在哪 ✗：★ **网格视窗的列表项**
  --     （★ 模板 `clue` ✓ 子控件 `backrop1` / `backrop2` / `face` / `who` / `what` / `letter` ✓
  --      ★ 存档实证 ✓：`backrop1` 父=`clue` ✓ 尺寸 360x96 ✓）
  --   ★★ 而"谁被选中"原来**只有一处**写它 ✗：`_on_grid_item_click` 里那段**手动染色** ✓
  --     ⇒ ★ 那就是第一轮我删掉的那段 ✓ —— ★ 删掉是对的 ✗（★ 它是第二份状态 ✓）
  --     ★★★ 但我**没有给网格这条路补上替代** ✓ ⇒ ★ 真机上现在**连亮都不亮了** ✓✓
  --
  --   ⇒ ★★ 修法 ✓：★ **把这一笔画进【填充】里** ✗ ——
  --     ★ 填充是**引擎每帧会重进**的那条路 ✓
  --       （★ 见本函数开头"滚动时引擎会重进 RefreshItems 回调"那段实测 ✓）
  --     ★★ 判据**现算** ✓：★ `core.selected` ⇒ 行号 ⇒ 与 `pos` 比 ✓
  --       ⇒ ★★ **填充什么时候跑，高亮就什么时候对** ✓ ✓ **不需要任何人"记得去同步"** ✓✓
  --   ★ 与第一轮的关系 ✓：★ 那两处**都保留** ✓
  --     · ★ `clue.focus` 样式 → 老路径（★ 模拟器 / 没有网格视窗的机器 ✓）
  --     · ★ 这里 → 网格路径（★ 真机 ✓）
  --     ★★ 两条路**同一个判据**（`_clue_pos_of_person(core.selected)` ✓）⇒ 不会各说各话 ✓✓
  --   ★ 颜色 ✓：★ 沿用原来那个暖金 `4294956107` ✓（★ 与用户已经看惯的那一版**一模一样** ✓
  --     ★ 不借机改观感 ✗ —— ★ 这一轮只修"对不对" ✓ 不改"好不好看" ✓）
  self:_grid_paint_highlight(item, index, pos, c_backrop1)
end

-- ★★ 把"这一条卡是不是被选中的那条"画到列表项的 `backrop1` 上 ✓
--   ★ 状态存在**表里**（按列表项实例 ✓）⇒ 句柄失效时不至于写坏别人 ✓
--   ★ 还原用的原色**第一次读到就记住** ✓（★ 不每帧回读 ✓ —— 回读会把"已染的金色"当原色 ✓✓）
function Controller:_grid_paint_highlight(item, index, pos, c_backrop1)
  if item == nil then return false end
  local cp = c_backrop1
  if cp == nil then
    pcall(function() cp = self:_grid_item_child_cached(item, index, pos, "backrop1") end)
  end
  if cp == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec == nil then return false end
  -- ★ 判据现算 ✓（★ 与老路径的 `clue.focus` **同一个来源** ✓）
  local sel = self.core and self.core.selected or nil
  local want = nil
  if sel ~= nil then want = self:_clue_pos_of_person(sel) end
  local want_on = ((want ~= nil) and want == pos)
  -- ★ 目标一旦达成就是**幂等**的 ✓ ⇒ ★ 稳态每帧只做两次比较、一次都不写 ✓
  if rec.hl_pos == pos and rec.hl_on == want_on then return true end
  -- ★ 记住"这块底色本来是什么" ✓ —— ★ 只在第一次（或换了代表哪一条）时读 ✓
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

-- 给列表项挂点击。★ 列表项是**复用**的：同一个控件会先后代表不同线索 ⇒
--   回调里**不能**捕获 index，必须用 `GetItemIndex` 现查（见 `_on_grid_item_click`）。
--   重复挂监听会一次点击触发多遍 ⇒ 用一个**弱键表**按控件身份去重（控件回收后自动释放）。
function Controller:_grid_bind_item_click(adapter, grid, item)
  if item == nil or item.AddCursorEventListener == nil then
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：诊断GRID·光标　原 L5473..L5478
    return
  end
  -- ★★★★★ 2026-10-05 **列表项是"引擎运行时克隆出来的按钮"，它的 `raycastTarget` 必须就地开**
  --   （每帧成本第 (3) 条的有意补偿）。
  --
  --   为什么：`Adapter:enable_raycast` 原来**每 20 帧整树重扫**，顺带盖住了
  --   "引擎后来克隆出来的列表项"；收敛之后不再重扫 ⇒ 晚到的卡片**没人给它开这个字段**
  --   ⇒ 「卡片点不动」。这里补上，而且更强：绑定那一刻就开（原来最多晚 20 帧），
  --   成本 1 次字段读写（原来是一趟 ≈ 470 个 `GetChildren`）。
  --   ⚠️ 放在**去重判断之前**：回收复用的项也要过这一道（引擎有可能把字段重置回去）。
  --   ⚠️ 也放在 `enum_at` 那个提前 return **之前** —— 离线环境没有 Enum，
  --      但真机上这个字段照样得开，两件事不相干。
  if adapter ~= nil and adapter.ensure_raycast ~= nil then
    pcall(function() adapter:ensure_raycast(item) end)
  end
  self._grid_bound = self._grid_bound
    or setmetatable({}, { __mode = "k" })          -- 弱键：列表项被引擎回收后不会攒着
  if self._grid_bound[item] then
    self._grid_click_ok = true
    return
  end
  local click = enum_at("CursorEventType.CursorClick")
  if click == nil then return end                  -- 枚举缺失 ⇒ 静默降级（离线环境就是这条路）
  local ok = pcall(function()
    item:AddCursorEventListener(click, function()
      -- 引擎回调里再包一层：这里出错会打断引擎自己的点击/滚动派发
      pcall(function() self:_on_grid_item_click(adapter, grid, item) end)
    end)
  end)
  if ok then
    self._grid_bound[item] = true
    self._grid_click_ok = true
  end
end

-- ★★★★★★ 2026-10-11 **"这一项是哪一条" —— 用【填充时记下的 index】✓ 不问引擎** ✗✓✓
--
--   ★★★ 用户 v179 真机日志 ✓（★ 决定性证据 ✓ 原文 ✓）：
--       `★ 卡片点击进来了 ✓（第 1 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 2 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 3 次）GetItemIndex=0  索引基准=0`
--       `★ 卡片点击进来了 ✓（第 4 次）GetItemIndex=0  索引基准=0`
--   ★★ 用户点的是**不同的卡** ✓ ★ 而 `GetItemIndex` **四次都回 0** ✗✓
--     ⇒ ★★★ **`grid:GetItemIndex(item)` 在这台引擎上不可靠** ✓✓
--
--   ★★ 为什么不可靠 ✗（★ 本项目早有旁证 ✓）：
--     ★ ui L5969 那段注释写着 ✓：「★ **多个列表项控件物理上叠在同一个位置**」✓
--       （★ 与"所有项都读到同一个 `y=212`"吻合 ✓）
--     ★ 而列表项是**同一个引用被填到不同位置** ✓（★ 用户 2026-10-10 就怀疑过 ✓）
--     ⇒ ★ 反查要么拿不到、要么**拿到同一个值** ✗✓（★ 实测正是后者 ✓）
--
--   ★★★ 修法 ✓：★ **填充时引擎【亲手】把 index 交给了我们** ✓
--     ★ 那一次是**权威**的 ✓（★ 我们就是按它算 `pos` 去填内容的 ✓）
--     ★★ 记在 `self._grid_seen[item]` 里 ✓（★ 本来就有这张表 ✓ 就地重用 ✓）
--     ⇒ ★ **点击时直接查它** ✓ ★ **不再问引擎** ✗✓
--   ★ 兜底 ✓：★ 表里没有（★ 还没填过 ✓）⇒ ★ 才退回 `GetItemIndex` ✓
--     ★ 两个都拿不到 ⇒ ★ 返 nil ✓ ★ 调用方**宁可丢掉这次点击** ✓（★ 不聚焦错的那条 ✓）
function Controller:_grid_pos_of_item(grid, item)
  if item == nil then return nil end
  local raw = nil
  local seen = self._grid_seen
  if type(seen) == "table" then
    raw = seen[item]
    if raw ~= nil then
      -- ★ 表里存的是**引擎交来的原始 index** ✓ ⇒ 与填充时**同一个数** ✓
      local base = self._grid_base or 0
      local pos = tonumber(raw)
      if pos ~= nil then return pos - base + 1 end
    end
  end
  -- ★ 兜底：问引擎 ✓（★ 不可靠 ✓ 但总比没有好 ✓）
  -- ★★★★★★ 2026-10-15 **兜底：问引擎 —— 它到现在才真的能走到** ✗✓✓
  --
  --   ★★★ 下面这两行**原来关在上一段的 `if type(seen) == "table" then` 里** ✗✓
  --     ⇒ ★ `_grid_seen` 没建（★ 或表里没有这一项 ✓）时 ⇒ ★ **直接落到最后 `return nil`** ✓
  --       ⇒ ★ 调用方把这次点击**整条丢掉** ✓（★ "宁可丢掉，也不要聚焦到错误的一条" ✓）
  --     ★★ 于是**兜底那条路从来没被走到过** ✗ —— ★ 而注释写的意图正是"总比没有好" ✓✓
  --   ★ 为什么这次才露出来 ✗：★ 真机上列表项的句柄**基本都进过 `_grid_seen`** ✓
  --     （★ 每次填充回调都会 `self._grid_seen[item] = index` ✓）
  --     ★★ 而**离线 / 换代 / 滚动复用**之后拿到的 `item` 可能是引擎**另一个句柄** ✓
  --       ⇒ ★ 表里没有 ⇒ ★ **静默丢掉** ✓✓
  --   ★ 这是**作用域错位**（★ 本项目第 N 次同型 ✓）：★ 意图是"两个来源都试一遍" ✓
  --     ★★ 而代码把第二个来源**也关进了第一个来源的 `if` 里** ✓✓
  --   ★ 修法 ✓：★ **移到 `if` 外面** ✓ ⇒ ★ 与注释的意图一致 ✓✓
  --   ⚠️ ★ 顺序**不变** ✗：★ 仍然**先认填充记录** ✓（★ 那是权威 ✓ 引擎那侧不可靠 ✓）
  --     ⇒ ★ 只是"填充记录没有时"多给引擎一次机会 ✓ 不改变任何已有的正确定位 ✓
  local idx = nil
  pcall(function() idx = grid:GetItemIndex(item) end)
  if type(idx) == "number" then return idx - (self._grid_base or 0) + 1 end
  return nil
end

-- 点了某一条列表项 → 聚焦这条线索。
function Controller:_on_grid_item_click(adapter, grid, item)
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★★ 2026-10-11 **入口探针：证明"卡片真的点到了"** ✗✓✓（★ 用户指定 ✓）
  --
  --   ★★★ 用户 2026-10-11 的指令 ✓：「★ **查看 project 仓库并修复** ✓
  --     （★ 注 ✓：★ **原本的光标事件是通的** ✓
  --      ★ **损坏必然来自 `clues` 重构**）」✓✓
  --   ★ 为什么必须加这一条 ✗（★ 协作方测绘里点出的关键区分 ✓）：
  --     ★★ **`列表项点击=支持` 那行只证明 `AddCursorEventListener` 方法存在** ✗
  --       —— ★ 它**不证明**事件真的会来 ✓（★ 那行由 `_grid_click_ok` 打 ✓
  --          而 `_grid_click_ok` 在**挂监听成功**时就置 true ✓ ⇒ ★ **不代表收得到** ✓✓）
  --     ★★ 用户 v177 真机日志里**一条 `收到点击 → 控件 clue.N` 都没有** ✗
  --       ★ 而 `cell.*` 的点击**都到了** ✓
  --   ⇒ ★★ 这一行就是**分水岭** ✓ —— ★ 点一下卡片：
  --     · ★ **出现这行** ⇒ ★ 事件到手 ✓ ★ 断点在它后面（`GetItemIndex` / 越界 / `pid` ✓）
  --     · ★ **不出现** ⇒ ★ **事件根本没来** ✗ ★ 断点在**绑定或引擎侧** ✓✓
  --   ★ 最多 6 行 ✓（★ 用户嫌日志多 ✓）
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

  -- ★ 2026-10-07 **抢点击定位读数**（★ 一次定案 ✓ 最多 12 行 ✓）
  --   ★ 要分清三件事 ✓：
  --     ① ★ **回调有没有进来**（★ 进来 ⇒ 引擎把点击给了卡片 ✓ 没进来 ⇒ 被别的东西吃掉 ✗）
  --     ② ★ **该卡是不是"已放置"**（★ `gray` 是否可见 ✓）—— 你说的现象**只在放置过的卡上** ✓
  --     ③ ★ 读回 `gray` 的 `raycastTarget` / 可见性 ✓ ⇒ 看"关射线"到底生效没有 ✓
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：抢点击诊断　原 L5521..L5536

  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-10 **"空白占位项"的点击 ⇒ 直接忽略** ✗✓
  --
  --   ★ 用户两条纠正 ✓（都很关键 ✓）：
  --     ① 「**现在滚动坏了**」✗ —— ★ 根因是**我关掉了占位项的 `raycastTarget`/`interactable`** ✗
  --        ⇒ ★ 滚动依赖列表项 ⇒ **一关就滚不动** ✓✓
  --     ② 「按照**预览中从上到下的添加顺序**，应该关的是 **1、2 项**」✗
  --        ⇒ ★ 与"6、7"**正好相反** ✓ —— ★ 溢出的是**最前面两项** ✓
  --          ⇒ ★ 这也解释了用户先前那句「高亮出现在**第一张卡之上**」✓✓
  --
  --   ⇒ ★★ 所以改成**完全不碰射线** ✓（①）＋ **判据反过来** ✓（②）：
  --     · 填充时：**前 `溢出数` 项**做成空白 ✓（**不清射线** ✗）
  --     · 点击时：★ **这两项进来的点击直接 `return`** ✓ ⇒ ★ 效果同样是"不能点" ✓
  --       ★ 而**引擎的滚动完全不受影响** ✓✓
  --   ★ "溢出数" = 总条数 − 一屏容量 ✓（真机数：7 − 5 = **2** ✓）
  -- ★★★★★ 2026-10-10 **「空白占位项的点击忽略」也一并移除** ✗✓
  --   ★ 理由同上 ✓：探针已证明滚动时引擎会逐个交出后面的项 ✓
  --     ⇒ ★ 根本没有"永远填不上的项" ✗ ⇒ ★ 也就不需要忽略任何点击 ✓
  --   ★ 保留它反而会**误伤**：★ 把 pos 6..N 的正常点击也吃掉 ✗
  --     （★ 真机日志里"后面几张点不动"很可能就包括这一条 ✓）

  -- ★★★★★ 2026-10-10 **同一次点击只处理一次** ✗✓ —— ★ 这是"选中多张"的治本一步 ✓
  --
  --   ★★ 用户怀疑 ✓：「他们本身就是**同一个引用**，只是视觉上被填到了不同位置」
  --     ★ 方向对 ✓ 机制更狠 ✗：★ **一次点击会串进来【一串】列表项的回调** ✓
  --   ★ 真机日志（v117 ✓ 原文 ✓）：
  --       `GetItemIndex=7` ⇒ ★ **紧接着 index=8 也来了** ✗
  --       ⇒ `index=8` **又一次** ✗ ⇒ `index=9` ⇒ `index=11` ⇒ `index=13` ⇒ `index=14` ✗
  --     ⇒ ★★ **一次点击触发了五六个不同的列表项** ✓ ⇒ ★ **于是选了好几张** ✓✓
  --   ★ 根因 ✓：★ **多个列表项控件物理上叠在同一个位置** ✗
  --     （★ 与"所有项都读到同一个 `y=212`"**完全吻合** ✓ —— 它们都停在模板那个点 ✓）
  --     ⇒ ★ 一次射线命中**全部** ⇒ ★ 每个都回调一次 ✓
  --   ⇒ ★★ 修法 ✓：★ **同一次点击只认第一个** ✓（短窗去重 ✓ 不必知道谁在上面 ✗）
  --     ★ 窗口 0.05 秒 ✓ —— 同一次点击的连发都在内 ✓ 正常两次点击远大于它 ✓
  --   ⚠️ 这是**止血** ✓；★ 把"叠在一起"从根上解决要靠布局（记在 `接手待办.md` ✓）
  --     但它**足以让"点一下只选一个人"成立** ✓
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
  -- ★★★★★★ 2026-10-11 **不再问引擎"这一项是第几条"** ✗✓✓
  --
  --   ★ 原来这里 `idx = grid:GetItemIndex(item)` ✗
  --   ★★ 而用户 v179 真机日志证明它**四次都回 0**（★ 点的是不同的卡 ✓）
  --     ⇒ ★ **这台引擎上它不可靠** ✓ ⇒ ★ **于是每次点击都算成 `pos = 1`** ✓✓
  --       ⇒ ★ **高亮与选人都落在第 1 条上** ✓（★ 用户看到的"链路还是断的" ✓）
  --   ⇒ ★★ 改用 `_grid_pos_of_item` ✓ —— ★ **用填充时引擎亲手交来的那个 index** ✓✓
  --     ★（★ 那一次是权威的 ✓ ★ 我们就是按它算 `pos` 填内容的 ✓）
  -- ★★★★★ 2026-10-18 **通用线索：在最前面识别，不走 `pos` 那条路** ✗✓（日志定案）
  --   证据（用户 05:55 日志）：点它 ⇒ `GetItemIndex=0` ⇒ `_grid_pos_of_item` 拿不到位置 ⇒
  --     `pos` 非法 ⇒ **整条点击被丢掉**（连"点卡片定位"都不打印）⇒ 表现为"不可选" ✗
  --   ⇒ 用**填充时记下的句柄**在算 pos 之前就认出来 ✓
  --     （句柄是权威的 ✓；它被回收去显示普通卡时已在填充侧清掉 ✓）
  --   ★ `focused_clue` 给一个**合法正数但超出卡范围**的值（n+1）⇒ 没有卡会对上 ✓
  --     绘制侧把 `general_focus` 解释成通用线索（见 build_layout 那段）✓
  if item ~= nil and self._general_item == item then
    -- ★★★ 2026-10-18 **再点一次 = 取消选中** ✗✓（用户：通用线索没接取消选中）
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
  -- ★★★★★ 2026-10-18 **通用线索走【正常选中链路】，只是把卡号算成 0** ✗✓（用户定案）
  --   用户原话：「把相关拦截取消，高亮也补上」✓（拦了之后通用卡选不中 ⇒ 提示路径断 ✗）
  --   ⇒ 不再早退 ✗：它**和普通卡一样**参与选中，只是：
  --     · 卡号 = 0（通用卡不是任何人的卡 ⇒ `vm.clues[0]` 为 nil ⇒ 选人那步自然什么都不选 ✓）
  --     · 高亮绘制侧把 `focused_clue == 0` 解释成通用线索 ✓（见 `build_layout` 那段）
  --   ★ 真卡：列表第 k+1 项 ⇒ pos 减 1 得到卡号 k ✓（本次一并合进来，不再分两块）
  do
    local _hg = false
    pcall(function() _hg = self:_has_general_clue() end)
    if _hg and pos ~= nil then
      pos = pos - 1                -- 真卡：列表位置 −1 = 卡号 ✓（通用卡已在上面 return ✓）
    end
  end

  if type(pos) ~= "number" then
    -- 两个来源都拿不到 ⇒ 这一次点击**宁可丢掉**，也不要聚焦到错误的一条 ✓
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
  -- ★★★★★ 2026-10-07 **点卡片后强制重填一次** ✗✓（治"取消选中后高亮还在" ✓）
  --   ★ 真机反馈 ✓：★「★ **预放置的卡，取消选中后高亮还在**」✗
  --   ★ 机制 ✓：★ 高亮由**填充**按 `core.selected` 画 ✓（提交 371 ✓）
  --     ⇒ ★ 而"取消选中"这一步**不触发重填** ✗ ⇒ ★ 填充没机会把金色复原 ✓✓
  --   ⇒ ★ 这里清掉网格签名 ✓ ⇒ ★ 下一帧重填 ⇒ ★ **高亮立刻跟着选中状态走** ✓✓
  --     ★（★ 与"放置后重填"用的是同一招 ✓ 提交 363 ✓ 一套机制两处用 ✓）
  -- ★ 2026-10-10 **不再清签名** ✗✓ —— ★ 清签名会重发 RefreshItems
  --   ⇒ ★ 引擎会把**滚动位置重置到顶部** ✓（用户实测："点第五张卡弹回顶部"✗）
  --   ⇒ ★ 改成置"待刷新"标志 ✓ 由 `sync_clue_grid` **就地重填** ✓ ⇒ 滚动一动都不动 ✓
  self._grid_refill_pending = true
  -- ★★ 2026-10-11 **条数同样取【核心那份】** ✗✓（★ 本文件里第 **三** 处同类漏改 ✓）
  --   ★ 原来读 `self.core:view().clues` ✗ ⇒ ★ 槽位模型下**形状变了** ✓
  --     ★ 侥幸还没坏（★ 槽位数 = 容量 ✓ ⇒ `n` 仍等于条数 ✓）
  --     ★★ 但这是**同一个前提**（"视图的 `clues` 就是条数表"）✓ ⇒ ★ 该一并对齐 ✓
  --   ★ 用户报的"点卡片选中到棋盘断了"就是这条路 ✓ ⇒ ★ 这里错一位 ⇒ **整条点击作废** ✓
  local n = #((self.core and self.core.clues) or {})
  if pos < 1 or pos > n then return end

  -- ★ 走**和老卡片完全同一条**输入通路：`adapter.on_input` 是 main.lua 接的
  --   （`controller:on_input(event)` + 立刻渲染）⇒ 点列表项和点 `clue.N` 的后续行为
  --   （焦点切换、CLUE_IN 特效、重绘）一模一样，不会出现"两套焦点逻辑"。
  -- ★★★★★★★★ 2026-10-15 **这一段整段删掉：手动染色的高亮** ✗✓✓
  --
  --   ★ 它原来干什么 ✗：★ 点卡片时**手动**把那张卡的 `backrop1.imageColor` 染成暖金 ✓
  --     ★ 换项/取消时再还原 ✓ —— ★ 也就是**第二套"谁被选中"的表示** ✓✓
  --   ★★★ 为什么必须删 ✗（★ 用户报的两个症状都出自这一类 ✓）：
  --     ★ 它只在**点卡片**那一下被写 ✗ ★ 而 `core.selected` 还会被
  --       「拿起棋子 / 正式放置 / 切工具 / 撤销」改掉 ✓ ⇒ ★ **两套状态必然漂移** ✓✓
  --     ★★ 而真正的高亮**本来就有一条更好的路** ✓：
  --       ★ `clue.focus` 样式（`build_layout` 每帧按 `focused_clue` 重算 ✓）
  --       ⇒ ★ 那条路**每帧现算** ⇒ ★ 不会残留 ✓✓
  --   ★★ 保留的那条路 ✓：★ 点卡片 = ★ **选中卡上那个人** ✓（★ 下面那段一个字不动 ✓）
  --     ★ 高亮由 `_sync_clue_focus` 按选中**派生**出来 ✓（★ 见那个函数 ✓）
  --   ★ 用户要的语义 ✓（★ 原话 ✓）：「**像把内容填进 `clue` 的 `what` 一样**」——
  --     ★ 素材与身份都走**单射那条线** ✓ ★ 高亮同理：★ **跟着人走 ✗ 不跟着点走** ✓✓
  -- ★ 2026-10-10 已删的同类（★ 供对照 ✓）：诊断CLUE　原 L5654..L5669
  -- ★ 2026-10-07 一次性诊断：把该线索记录的【真实字段名】打出来（方案 A 取值失败 ⇒ 不猜了）
  -- ★ 2026-10-10 已删（地图员区间 ✓ 干跑 PASS ✓）：诊断CLUE　原 L5654..L5669
  -- ★★★★★ 2026-10-07 **方案 A：点线索卡 = 高亮这条 + 选中卡上那个人** ✗✓（用户确认走 A ✓）
  --
  --   为什么必须有：真机日志「★ **点 (第1行 第2列) 没生效：先点一个头像　当前工具=place　已选=nil**」✓
  --     ⇒ ★ **`selected` 一直是 nil** ⇒ ★ **铅笔笔记 / 预放置 / 正式放置【三者全被拦在这一步】** ✓
  --   根因：★ 老卡片里头像 `face` 是**按钮**（`push({id="clue."..i..".face", kind="button"})` ✓）
  --     点它才发 `suspect` ✓ 而**网格模式下列表项点击只发 `focus_clue`** ✗ ⇒ ★ **选人的手势丢了** ✓
  --   ⇒ 这里补上：★ **点卡片即选中卡上那个人** ✓（★ 一步完成"高亮 + 选人"✓）
  --   ★ 取值**防御式**：线索记录里人物字段可能叫 `person`/`who_id`/`id`/`key` ✓
  --     再兜一层"从头像素材名 `portrait.X` 里取 X" ✓ 取不到就不动作（绝不误选）✓
  local _sel_ok, _sel_err = pcall(function()
    local v2 = self.core:view() or {}
    local cl = (v2.clues or {})[pos]
    -- ★★★ 2026-10-11 **选人这一步也要探针** ✗✓（★ 否则"选中了没有"看不出来 ✓）
    --   ★ 用户 v179 日志里 ✓：★ 卡片点击**进来了** ✓ ★ 可格子仍报"先点一个头像" ✓
    --     ⇒ ★★ **说明 `suspect` 那一步没成功** ✓ —— ★ 而它是**静默**的 ✗（★ `pcall` 包着 ✓）
    --   ⇒ ★ 把三个值打出来 ✓：★ `pos` ✓ ★ `cl 是否为 nil` ✓ ★ 解析出的人 ✓✓
    if print and (self._grid_pick_log or 0) < 6 then
      self._grid_pick_log = (self._grid_pick_log or 0) + 1
      local _dbg_pid = nil
      pcall(function() _dbg_pid = self:_person_id_for_pos(pos) end)
      -- ★★★ 2026-10-11 **把解析器的【输入】也打出来** ✗✓（★ 用户 v180 日志的下一问 ✓）
      --   ★ 用户 v180 日志 ✓：★ `pos=1/2/3  cl=有  解析出的人=nil` ✓
      --     ⇒ ★★ **定位已经全对了** ✓ ★ 而**解析这一步是空的** ✓
      --   ★ 而解析有**两个输入** ✗：★ ① `_row_text[关][行].who`（★ 那一趟读到的 ✓）
      --     ★ ② `core.names`（★ id ⇄ 显示名 ✓）
      --   ⇒ ★★ 不打出来就分不清是"**没读到**"还是"**读到了但对不上名字**" ✓✓
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
      -- ★ 真字段名（真机探针实测 ✓）：★ `who` —— 值形如 `V` / `D` / `@thief`
      --   ⇒ `@` 开头的是【特殊角色】（如盗窃者），不是可选的"人"，跳过 ✓
      --
      -- ★★★★★★ 2026-10-11 **先问新路：单人射配的那个人** ✗✓✓
      --   ★ 槽位没有 `who` ✗ ⇒ ★ 只走老的取法 ⇒ **恒 nil ⇒ 永远选不中** ✓
      --   ★ 详见 `_person_id_for_pos` 那段长注释 ✓（★ 用户报的"选中到棋盘这一层断了" ✓）
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
        -- ★★★★★★★★ 2026-10-15 **这里【直接就选】，不再绕那条 `suspect` 事件** ✗✓✓
        --
        --   ★★★ 为什么不能绕 ✗（★ 我前后试了三版 ✓ 真正的原因在第二条 ✓）：
        --     ★ 它**自相矛盾** ✗：这条路先 `select_suspect` ✓ 紧接着又发一条
        --       `{action="suspect"}` ✓ ⇒ ★ `on_input` 收口处**又选一次** ✓✓
        --     ★★ 而 `select_suspect` 是**切换**（★ `murdoku_core.lua:1687` ✓）
        --       ⇒ ★★ **选上又被切掉** ✓（★ 实测：发事件前 `selected=V` ⇒ 之后就 `nil` ✓）
        --     ★★★ 我第一版拿 `focused_clue` 当判据时**看着是对的** ✗ ——
        --       ★ 因为高亮那份状态当时**正好是错的** ✓
        --       ⇒ ★★ **用一个有缺陷的状态当判据，把另一个缺陷抵消掉了** ✓✓
        --         ★（而那个"错"正是用户报的这件事本身 ✓ 见 `_sync_clue_focus` ✓）
        --
        --   ★★★ 第二条（★ 这一条决定"绕不绕" ✓）：★ **适配器的 `on_input` 是【单向】的** ✗✓
        --     ★ 依据 ✓（★ 本工程自己的架构文档写着 ✓）：★
        --       「引擎事件**只会进来**（`main.lua` 把它转给 `controller:on_input` ✓）；
        --         ★ 控制器**从不**"对着某个控件凭空发一个事件"」✓
        --     ★★ 所以"点卡片"这个**引擎手势**必须在这里把选中**做实** ✓
        --       ★ 绕那条 `suspect` 只是**转一圈回到自己** ✓ ⇒ ★ 净效果变成"切换" ✓✓
        --     ⚠️ 与下面那条 `focus_clue` 的**不对称是有意的** ✓：
        --       ★ 那一条**只播特效** ✓ ★ 而特效要 `adapter` ✓（本函数手里有这个参数 ✓）
        --       ⇒ ★ 它借 `on_input` 走一趟 ✓ —— ★ 那才叫"借道" ✓ 这条不是 ✓✓
        --
        --   ★★★ 第三条：★ 为什么不干脆**删掉** `focus_clue` 那一趟 ✗
        --     ★ 上位回归 `tests/clue_slots.lua` **正是断言那条事件发得出去** ✓
        --       （★ 用意是"点卡片这条链是通的" ✓ ★ 不许放宽 ✓ P8 ✓）
        --     ⇒ ★ 保留 ✓ ★ 只是它**不再承担任何状态** ✓（★ 见那个分支 ✓）
        --
        --   ★★ 分工定稿 ✓：★ **状态（选中）在这里定** ✓
        --     ★ **高亮由 `_sync_clue_focus` 派生** ✓ ★ 收口处再派生一次 ✓
        --     ⇒ ★ 全项目"高亮"只剩**一个**写点 ✓✓（P13 ✓）
        --
        --   ★ 三种情形 ✓（★ 互斥且穷尽 ✓）：
        --     · ★ 亮着 ∧ 选中的也是他 ⇒ ★ **取消**（"再点一次取消" ✓）
        --     · ★ 还不是他 ⇒ ★ **选中他** ✓
        --     · ★ 已经是他、但没亮着 ⇒ ★ **什么都不写** ✓（★ 高亮由派生自己跟上 ✓）
        --   ★★★ 2026-10-15（第二轮）**判据去掉 `lit`，只看"是不是他"** ✗✓✓
        --
        --   ★★ 为什么必须去掉 ✗（★ 第一轮它把真机那条路带偏了 ✓）：
        --     ★ `lit` 读的是 `focused_clue` ✓ —— ★ 而那个值**只在 `on_input` 收口处**派生 ✓
        --     ★★ 网格视图那条路（★ 真机 ✓）的视觉走的是**列表项 `backrop1`** ✗
        --       ⇒ ★ `focused_clue` 在真机上**可能一直是上一帧/别的值** ✓
        --     ★★★ 后果（★ 本轮实测 ✓）：★ 点"正亮着那张卡"时 `lit` 判**假** ✗
        --       ⇒ ★ 落进 `elseif not is_him`? 不 ✓ ★ 两边都不进 ⇒ **点了没反应** ✓
        --       ⇒ ★★ 或者更糟：★ 选中被**又选一次**/又切一次 ⇒ **与屏幕对不上** ✓✓
        --   ⇒ ★★ 新判据 ✓：★ **`is_him` 一条就够** ✓ ——
        --     · ★ 选中的就是他 ⇒ **取消** ✓（★ "再点一次取消" ✓）
        --     · ★ 不是他 ⇒ **选中他** ✓
        --     ★★ 两者都以 `core.selected` 为唯一依据 ✓ ⇒ ★ **在两条路上行为一致** ✓✓
        --   ★ 为什么这比"看谁亮着"更对 ✓：★ 亮着本来就是**从选中派生出来的** ✗
        --     ★ 拿派生值反过来当判据 = 把因果倒过来 ✓ ★ 那正是漂移的温床 ✓✓
        local is_him = (tostring(self.core.selected or "") == tostring(pid))
        if is_him then
          -- ★ 取消：★ 只调**一个**核心方法 ✓ ★ 高亮一个字都不写 ✗
          --   （★ 派生点只有 `_sync_clue_focus` ✓ ★ 真机那笔由填充每帧现算 ✓）
          self.core:select_suspect(pid)
        else
          -- ★ 走核心自己的入口 ✓（★ 不直接写 `core.selected` ✗ ——
          --   ★ 核心要顺带处理"橡皮擦/✗ 模式下选人会切回放置模式" ✓ 见 `select_suspect` ✓）
          self.core:select_suspect(pid)
        end
        -- ★★ 这里**不许**补发那条 `suspect` ✗ —— ★ 发了 = 再切换一次 ✓（见上面 ✓）
        self._grid_refill_pending = true
        self.dirty = true
      end
    end
  end)
  -- ★★★★★★★★ 2026-10-15 **这一段原来是【静默】的** ✗✓✓（★ P11：跳过就要出声 ✓）
  --
  --   ★★ 机制 ✓：★ 整段包在 `pcall` 里 ✓ ⇒ ★ 里面任何一处抛错 ⇒
  --     ★ **"选中卡上那个人"这一步整段不发生** ✗ ★ 而且**一个字都不报** ✓✓
  --   ★ 症状 ✓：★ 点卡片"看着有反应"（`focus_clue` 那半边照常 ✓）
  --     ★★ 而**人根本没被选上** ✓ ⇒ ★ 玩家报的「点卡片选不中人」✓✓
  --   ★ 这条本项目早该有 ✓（★ `_refuse` 那段注释写着同一个道理 ✓）：
  --     ★ **"没生效"必须能说出来** ✗ 否则分不清"没调用"和"调用了但抛了" ✓
  --   ★ 最多报 3 次 ✓（★ 不刷屏 ✓）
  if (not _sel_ok) and print then
    self._sel_err_log = (self._sel_err_log or 0) + 1
    if self._sel_err_log <= 3 then
      print("[murdoku] ⚠️ 点卡片**选人那一步抛了异常** ⇒ 这一步整段没生效（第 "
        .. tostring(self._sel_err_log) .. " 次，最多报 3 次）：" .. tostring(_sel_err))
    end
  end
local ev = { action = "focus_clue", index = pos, phase = "click" }
  -- ★★★ 2026-10-18 **通用线索发它自己的 action** ✓（只接提示 ✓ 不接 note / 放置）
  if self._general_click then
    ev = { action = "focus_general", phase = "click" }
    self._general_click = nil            -- 一次性：下一次点击重新判定 ✓
  end
  -- ★★ 2026-10-18 通用线索占列表第 1 项 ⇒ 它的点击**只发 focus_general**（只接提示，不接 note/放置）✓
  pcall(function()
    if item ~= nil and self._general_item == item then
      -- ★ 句柄比对 ✓：就是通用线索那一项 ⇒ 只发 focus_general
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

-- ★★★★★★ 2026-10-11 **"这一张卡对应哪个人" —— 单人射的第三条断点** ✗✓✓
--
--   ★★★ 用户报 ✓：「★ **网格视窗好了** ✓
--     ★ **但选中卡片后到棋盘这一层还是断的** ✓
--     ★ **放置也做不到** ✓ ★ **`note` 也标不上**」✓✓
--   ★ 症状链 ✓：★ 点卡片 ⇒ 应该**选中卡上那个人** ✓ ⇒ 再点格子才放得下 / 才标得上 ✓
--     ⇒ ★ **一行日志**：「★ 点 (第1行 第2列) 没生效：**先点一个头像**　当前工具=place　已选=nil」✓✓
--   ★★★ 根因 ✓：★ 点卡片那条路**从 `clue_view[i].who` 取人物 id** ✗
--     ★ 而 `Core:view()` 里就是 `who = cl.who` ✓ ★★ **槽位没有 `who`** ✗ ⇒ **恒 nil** ✓
--       ⇒ ★ 它**防御式地"取不到就不动作"** ✓（★ 本来是对的 ✓）
--       ⇒ ★★ 于是**永远不选中** ⇒ **放置与笔记【三者全被拦在这一步】** ✓✓
--   ★ 为什么不能直接在核心里写 `who` ✗：★ 核心里**没有 `row.*` 那份数据** ✓
--     ★ 那是**存档里的控件** ✓ ★ 只有 `ui_controller` 读得到 ✓（★ 见 `_row_text` ✓）
--   ⇒ ★★ 修法 ✓：★ **在这里把"卡上那个人"解析出来** ✓
--     ★ 来源 = `Controller._row_text[关][行].who` ✓（★ 那一趟读 `row.*` 时落账的 ✓）
--     ★★ 解析要**双向都认** ✓（★ 用户配的可能是 id `"B"` ✓ 也可能是显示名「前台姑娘」✓）
--       ① 先当 **id** 查 `core.names` ✓（★ 命中就用 ✓）
--       ② 再当**显示名**反查 ✓（★ `core.names[id] == 它` ⇒ 那个 id ✓）
--     ⇒ ★ **两种配法都能选中** ✓ ★ 都不命中 ⇒ **返 nil 不动作** ✓（★ 绝不误选 ✓）
--   ★ 没配 `row.*` 时 ✓：★ 退回老的 `cl.who` ✓（★ 手写线索的关卡照旧 ✓ 向后兼容 ✓）
--
--   ⚠️ ★★ **必须定义在【函数外面】** ✗✓（★ 我第一版就踩了 ✓）
--     ★ 我把它插在 `_grid_bind_item_click` 里那个 `local ev = {…}` 的**正上方** ✗
--     ⇒ ★ Lua 把 `function Controller:_person_id_for_pos(pos)` 解析成
--       **`local ev = function …`** ✓ ⇒ ★★ **它变成一个局部变量，根本不是方法** ✓✓
--       ⇒ ★ 表现：★ `Controller._person_id_for_pos == nil` ✓ ★ 调用处**报 nil** ✓
--     ★ `luac -p` **不报错** ✗（★ 语法完全合法 ✓）—— ★★ 与"编译通过 ≠ 这段在跑"同族 ✓
--     ★ 判据 ✓：★ **`function 名字` 前面不许有别的东西** ✗
function Controller:_person_id_for_pos(pos)
  local core = self.core
  if core == nil or pos == nil then return nil end
  -- ★★ 【棋盘线同一条路】★ 第 `pos` 行 ↔ 第 `pos` 个棋子 ✓
  --   ★ 与 `letter_of` / `portrait_of` 的换算**严格互逆**
  --     ⇒ ★ 「选了 A 却显示 B」结构上不可能 ✓
  local id = Controller._piece_at_row(core, pos)
  if id ~= nil then return id end
  -- ★ 退回老的「线索自带 who」（★ 手写线索的关卡走这条）
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

-- ★★★★★★★★ 2026-10-15 **卡片高亮的唯一判据 = `core.selected`** ✗✓✓
--
--   ★★★ 用户报的两个症状（★ 原话 ✓）：
--     ★ ①「**放置 v 后选择了 d，一不小心把 v 取消了，
--          点出来的标记是 v 的，但显示选择的 d，此时再长按放置，放的会是 v**」✗
--     ★ ②「**出现过 d 有选中高亮但没有选中行为的情况**」✗
--   ★★ 两者是**同一个形状** ✓ —— ★ **高亮与选中是两份状态 ⇒ 必然漂移** ✓✓
--
--   ★ 根因（★ 探针 `tests/_wip/repro_select_residue.lua` 实测复现 ✓）：
--     ★ `core.selected` 会在**好几条路**上被改 ✓：
--       · `tap_cell` 拿起棋子 ⇒ `self.selected = self.grid[r][c]`（`murdoku_core.lua:1913` ✓）
--       · `hold_cell` 正式放置完 ⇒ `self.selected = nil`（`:1961` ✓）
--       · `select_suspect` 自己 ✓ · `set_mode` 切到 ✗/橡皮擦 ⇒ 清空 ✓
--     ★★ 而**卡片高亮只在一个地方被写** ✗：`_on_grid_item_click`（点卡片那一下 ✓）
--       ⇒ ★ **凡是"选中变了但不是点卡片改的"，高亮就留在原地** ✓✓
--     ★★★ 用户那一步正好踩中 ✓：
--       ★ 选 D（high=D ✓ `selected=D` ✓）⇒ ★ **拿起 V** ⇒
--         ★ `selected` **变成 V** ✓ ★ 而高亮**还是 D** ✗
--       ⇒ ★ 屏幕说"选的是 D" ✗ ★ 而长按落子用的是 `core.selected` = **V** ✓✓
--         （★ 与用户原话逐字相符 ✓：「显示选择的 d」＋「放的会是 v」✓）
--
--   ★★★ 修法（★ 不是"多同步一处" ✗ —— 那是同一个错误再来一次 ✓）：
--     ★ **把高亮降级成【派生值】** ✗ ⇒ ★ 它**没有自己的一份状态** ✓ ⇒ ★ **结构上不可能漂移** ✓✓
--     ★ 判据一律现算 ✓：★ `focused_clue = 选中那个人配在第几行` ✓
--     ★ 与 `_person_id_for_pos` **严格互逆** ✓（★ 同一条 `_piece_at_row` 换算 ✓）
--       ⇒ ★ 两个方向都不会各说各话 ✓
--
--   ⚠️ ★ **放哪一层** ✗：★ 必须是**方法** ✓ 且定义在**函数外面** ✗
--     （★ 与 `_person_id_for_pos` 那次同一个坑 ✓ ——
--      ★ 写进别的函数体里会变成局部变量 ⇒ **静默失效** ✓ 见上面那段长注释 ✓）
--   ⚠️ ★ 按**行号**比 ✓ ★ 不按"卡片上显示的字母"比 ✗
--     （★ 字母是玩家配的素材 ✓ 可能是任意字符串 ✓ 甚至同一个人配了两次 ✓）
function Controller:_clue_pos_of_person(id)
  if id == nil then return nil end
  local core = self.core
  if core == nil then return nil end
  local pos = Controller._pos_of_piece(core, id)
  if pos == nil then return nil end
  -- ★★ 反向自查 ✓（★ 与 `_person_id_for_pos` 成对 ✓）：
  --   ★ 换回来必须还是同一个人 ✗ ⇒ ★ 对不上就**不设高亮** ✓（★ 绝不误亮 ✓）
  local back = Controller._piece_at_row(core, pos)
  if back == nil or tostring(back) ~= tostring(id) then return nil end
  return pos
end

-- 把卡片高亮拉回"选中是谁就是谁"。每个输入事件末尾调一次（★ 见 `on_input` ✓）。
--   ★ 只在**真的该变**的时候动手 ✓ ⇒ ★ 稳态成本 = 一次表查找 ✓
--   ★ 变了就清 `_grid_refill_pending` ⇒ ★ 由 `sync_clue_grid` **就地重填** ✓
--     ★★ 不重发 `RefreshItems` ✗ ⇒ ★ **滚动位置一动不动** ✓（★ 与放人/拿起同一条路 ✓）
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
    -- ★ 顺手丢掉**手动染色**留下的残迹 ✓
    --   ★ 机制 ✓：★ 高亮改由 `clue.focus` 样式（规划每帧重算 ✓）画 ✓
    --     ⇒ ★ 那个"点卡片时手动染的金色"**没有存在的必要** ✗ ⇒ ★ 留着就是第二份状态 ✓✓
    self._grid_focus_item, self._grid_focus_orig = nil, nil
    self._grid_focus_idx, self._grid_focus_pos = nil, nil
    self.focused_clue = want
    self._grid_refill_pending = true
    self.dirty = true
  end
  return changed
end

----------------------------------------------------------------------------
-- 增量渲染
----------------------------------------------------------------------------

-- ★★★★★ 2026-10-05 **写属性的唯一入口：一律包 `pcall`**。
--
--   为什么：真机上那个"每帧刷、永久刷"的报错就是 set_property 抛出来的
--     （`attempt to call method 'imageSource' on an invalid object`，
--       见 `build_layout` 里那段根因注释），而它是在 `render` **里面**抛的 ⇒
--     后面所有节点全没处理 ⇒ 连带症状一大串（模板格子出不来、`clues.bg` 时有时无）。
--   ⇒ 原则：**一个属性写不进去，只该少显示一样东西，绝不该把整帧渲染打断**。
--     适配层那边"句柄可能是引擎回收过的列表项"这件事我们管不了（不在本文件里），
--     但"它抛错会不会连累整帧"是我们能兜住的。
--
--   ⚠️ 报错**按 id + 键各报一次**，而且**最多只列 8 条**（第 9 条换成一句总结）：
--      一个坏句柄会每帧抛，不去重/不限量就是拿日志刷屏 —— 那正是用户这一轮最烦的事。
function Controller:_set_prop(adapter, id, key, value, nkey)
  -- ★★★★★ 2026-10-05 **多带一个 `nkey`：这把键就是属性账本那把 `node_key`。**
  --
  --   为什么要有它：`build_layout` 里**同一个 id 会出现在两个节点上**
  --   （`action.back`：一个挂 `topbar`、一个挂 `right`），而适配层的**事件表**
  --   原来是按控件 id 记的 ⇒ 两个节点轮流写同一格 ⇒ **后写的把先写的吃掉**
  --   （静默、不报错）。
  --   ⇒ 把账本**已经算好的**那把键原样传下去，适配层用它给每个规划节点各记一份。
  --   ⚠️ **不要**在适配层另造一套键（"一条规则两个权威"本项目刚在 BOM 上栽过）——
  --      这里传的就是 `render` 里 `local nkey = node_key(n)` 那一个值。
  --   ⚠️ 其它键（text/visible/...）用不到它，传了也只是忽略；留成可选参数，
  --      旧调用方（离线假适配器）少传一个参数照样跑。
  -- ★★★★★ 2026-10-05 **返回值从"没抛错"升级成"真的送到了"**。
  --
  --   为什么：适配层 `set_property` 在 `find(id) == nil` 时是**静默 no-op**（不抛错、也不写），
  --   而这里原来只回传 `pcall` 的结果 ⇒ **静默 no-op 也算成功** ⇒ 调用方（`render` 的
  --   增量账本）把这条属性记成"已下发" ⇒ 本关内**永不补发**，只能出关重进
  --   ⇒ 真机表现就是我们这一轮在查的"**第一次进关渲染得比第二次少**"。
  --   ⇒ 现在把适配层的判定原样往上传：`true` = 送达（可以记账），`false` = 没送到（可以补发）。
  --
  --   ⚠️ 兼容老适配器 / 离线假适配器：它们**不返回值**（`res == nil`）——
  --      这里只有**明确的 `false`** 才算失败。把"没返回值"当成失败，会让每个属性每帧重发
  --      （离线测试立刻炸：那是"查不了 = 不存在"的老坑）。
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
  -- ★★★★★ 2026-10-05 **切屏 / 换关 = "控件树这一代作废"的权威事件**（性能修复第 2 半）。
  --
  --   为什么要有这个事件：适配层现在有两处**按代缓存**的东西 ——
  --     · 控件名缓存（含**未命中**缓存，见 `Adapter:find` 上面那段注释）；
  --     · 兜底隐藏（`enforce_hidden_subtrees`，从"每帧扫"改成"事件驱动"）。
  --   两者的作废时机**完全一样**，所以只在这里判定一次、只调一个函数
  --   （`Adapter:invalidate_lookups`）—— 免得以后有人只改一处、另一处留成陈年老 bug。
  --
  --   判据用 (screen, level_id) 这一对：
  --     · `screen`：主页 / 选关 / 关卡内（nil）—— 切屏会整套换显示哪棵子树；
  --     · `level_id`：换关时 `cell.*` / `clue.*` 的**名字集合**整个换一代，
  --       而适配器**是跨关复用的**（`main.lua` 的 `prepared_adapter`），
  --       不做这一步的话，"上一关没有、这一关有"的控件会被负缓存判成不存在。
  --   ⚠️ 放在 `sync_clue_grid` **之前**：切屏那一帧的 `find` 本来就该重新搜树
  --      （这正是"缓存可能过期"的那一帧），顺序反了等于拿旧缓存去建新一帧。
  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter ~= nil and adapter.invalidate_lookups ~= nil then
        pcall(function()
          adapter:invalidate_lookups("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      -- ★★★★★ 2026-10-05 **换屏 / 换关也要"重新武装"射线开关那一趟**（每帧成本第 (3) 条）。
      --
      --   为什么必须在这里、而且**只在这里**：
      --     · 换屏/换关是**长出新控件**的权威事件（`home` / `select` 是第一次渲染时才
      --       `create_control` 的）——早停之后不重新武装，新屏幕的控件就**永远开不上
      --       `raycastTarget`** ⇒ 又回到"界面看得见、点哪儿都没反应"。
      --     · ⚠️ **不能**挂进 `invalidate_lookups`：那个函数还被 `create_control` /
      --       `destroy_control` **每个控件各调一次**（进关时几十次）⇒ 挂那儿等于
      --       "每建一个控件就重扫一趟整树"，白跑比改之前还多。
      --       所以复用的是**同一个判据块**（screen/level 换代），不是同一个函数。
      if adapter ~= nil and adapter.rearm_raycast ~= nil then
        pcall(function()
          adapter:rearm_raycast("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      -- ★★★★★ 2026-10-11 **换代也要重新武装「常驻光标」那一趟** ✗✓
      --   为什么必须在这里、而且**只在这里**（与上面 `rearm_raycast` 完全同一个理由 ✓）：
      --     常驻光标那一趟加了**收敛即停**的闩锁（`Adapter:enable_cursor` 的 `_cursor.done` ✓）
      --     而 `home` / `select` 是**第一次渲染时才 create_control** 的 ✓
      --     ⇒ 若收敛之后永久早停，进关卡后新建的容器**永远开不上 showCursor** ✗
      --       ⇒ 又回到"界面看得见、点哪儿都没反应" ✓（门控②那个老病 ✓）
      --   ⚠️ 同样**不能**挂进 `invalidate_lookups` ✗ —— 那个函数还被 `create_control` /
      --      `destroy_control` **每个控件各调一次**（进关时几十次 ✓）
      --      ⇒ 挂那儿等于"每建一个控件就重扫一趟"，白跑比不改还多 ✓
      --   ★ 复用的是**同一个换代判据块**（screen / level_id 变了 ✓），不是同一个函数 ✓
      if adapter ~= nil and adapter.rearm_cursor ~= nil then
        pcall(function()
          adapter:rearm_cursor("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
    end
  end

  -- ★★★★★ 2026-10-05 **网格视窗先探一步**（必须在 `build_layout` 之前）。
  --
  --   为什么必须在前面：`build_layout` 要按"这一关到底走哪条路"决定
  --   `clues.grid` 藏不藏、老卡片让不让位（见 `sync_clue_grid` 与那段收口的注释）。
  --   顺序反过来的话，会让位晚一帧 —— 表现成"进关第一帧两套线索叠在一起"。
  --
  --   它自己保证：任何一步失败都只报一次、并且退回老路径（`_grid_state = "off"`）。
  self:sync_clue_grid(adapter)

  -- ★★★★★★★★ 2026-10-16 **把适配器交给 `build_layout`** ✗✓
  --   ★ 理由：★ 选关卡片上的**随件**（关名/进度/房间缩略图）要**跟着编辑器那张卡**摆 ✓
  --     ⇒ 必须**读运行时**（`GetSizeDelta` / `GetAnchoredPosition`）⇒ 需要适配器 ✓
  --   ★ 为什么不在 `build_layout` 里写 `self.adapter` ✗：★ **控制器上没有这个字段** ✓
  --     （`main.lua:510` 的 `self.adapter = adapter` 设的是 **Murdoku 实例** ✓ 不是控制器 ✓
  --       —— ★ 本轮实测踩到：写 `self.adapter` ⇒ **恒 nil** ⇒ 静默退回规划框 ⇒ 看起来"没生效" ✓）
  --   ★ 外部调用 `controller:build_layout()`（`main.lua:671` 生成坐标表那条）不传 ⇒ nil ✓
  --     ⇒ ★ 那条路**本来就该用规划框** ✓（它要的是"编辑器里该填多少" ✓ 正好 ✓）
  local nodes = self:build_layout(adapter)

  -- ★★★★★ 2026-10-05 **网格视窗在用时，"老一套线索控件"的名字一个都不许再碰。**
  --
  --   为什么：适配层的 `find(name)` 是**按名字**深度优先搜的，而网格视窗的列表项模板
  --   子控件就叫 `clue.1.who` / `clue.1.face` …（用户是照着第 1 张卡另存的模板）
  --   ⇒ 碰这些名字 = 可能抓到**已经被回收的列表项** ⇒ 句柄失效 ⇒ 属性下发抛错
  --     （真机日志见 `build_layout` 里那段根因注释）。
  --
  --   为什么在 `render` 里还要再拦一道：**切换的那一帧**。
  --     `_grid_state` 是上一帧渲染末尾才可能从 nil 变成 "on" 的（`sync_clue_grid`
  --     要等 RefreshItems 真的回调成功），所以 `_shown` / `_created` 里可能还留着
  --     上一帧按老路径建过的 `clue.N` —— 差集循环会拿它们去"藏起来"，清理循环
  --     会拿它们去"销毁"（那会把网格视窗正在复用的列表项关掉/毁掉）。
  --   ⇒ 判据和 `build_layout` 共用 `is_legacy_clue_id`（一处定义，三处使用）。
  local grid_on = (self._grid_state == "on")
  local function stale_legacy(id) return grid_on and is_legacy_clue_id(id) end

  -- 设备档位（pc / touch / gamepad）只在第一次渲染时探一次，用来决定提示文案。
  -- 界面本身完全一样 —— 两种模式走的是同一套光标事件。
  if self.input_profile == nil then
    self.input_profile = "pc"
    if adapter ~= nil and adapter.input_profile ~= nil then
      pcall(function() self.input_profile = adapter:input_profile() end)
    end
  end

  -- ★★ 必须**先把本帧要显示的 id 收齐，再算差集**。
  --    2026-09-26 踩过的坑：差集循环写在收集 seen 之前，seen 一直是空表，
  --    于是"上一帧显示过的全部"每帧都被藏一遍；而增量渲染又因为
  --    `last["visible"] == n.visible` 判定"没变"不再显示回来 ——
  --    结果是**第一次渲染之后整个界面就再也不可见**（而且一个报错都没有）。
  local seen = {}
  for i = 1, #nodes do seen[nodes[i].id] = true end

  -- 弹窗/教程/多余格子这些控件**在编辑器里是一直存在的**，只是不该显示时
  -- 不出现在布局里。第一次渲染先把"除了当前布局以外"的全部藏起来；
  -- 之后每次只藏"上一次显示过、这一次不在布局里"的。
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 2026-10-06 **`forget_visible` 提到两个分支之外** ✗✓ —— 修 `clues.grid` 永远 false ✓
  --
  --   ★ 根因（★ 真机实测 ✓）：★ 同一件事**两处实现，只修了一处** ✗✓
  --     · **首帧**分支（下面 `if self._shown == nil then`）★ **有** `forget_visible` ✓
  --     · **"之后每次"**分支（`else` 里那个 `for pairs(self._shown)`）★ **没有** ✗✗
  --   ⇒ ★★ 后果（★ 与用户实测完全吻合 ✓）：
  --     ★ ① 主页/选关那一帧 ⇒ `clues.grid` 不在 `seen` ⇒ **差集主动发 `false`** ✗
  --        ★ **并记进账本**（`last["clues.grid….visible"] = false` ✓）
  --     ★ ② 进关卡 ⇒ 规划算出 `visible = **true**` ✓（★ 诊断实测 `_grid_state = on` ✓）
  --        ★★ 而属性循环有账本：★ `same_value(last[k], true)` ⇒ **判"没变"⇒ 不发** ✗✗
  --        ⇒ ★★★ **它永远停在 false** ✓✓ ⇒ ★ **父不可见 ⇒ 列表项再可见也不渲染** ✓
  --   ★ 真机铁证 ✓：★ 五个列表项 `visible=true` ✓ 而父 `clues.grid = false` ✗
  --   ★★ 这就是本项目第 N 次「**同一件事两处负责 ⇒ 必然漂移**」✓
  --     ★（`erases` / 上色 / 缩放表 / 关卡清单 / 显隐 …都是同一个形状 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
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
    -- ★★★★★ 2026-10-05 **藏完必须【清账本】** ✗✓ —— 这才是"永久丢失"的根治 ✓
    --
    --   为什么（与 `apply_screen_hide` 那处是一件事的两半 ✓）：
    --     · 差集在这里**主动发** `visible=false` ✗（走 `_set_prop` ✓ 会**记账** ✓）
    --     · 而"要显示"是靠属性循环发 `visible` ✓ —— 但它有账本：`last[k] == v` ⇒ **判"没变"就不发** ✗
    --     · ⇒ ★★ 账本里还留着"上次发过 `true`"✗ 而控件**已被差集藏掉** ✗
    --          ⇒ **再也不会发 `true`** ✗ ⇒ ★【永久丢失】✗✓
    --   ⇒ ★ 所以：**凡是主动藏掉的 id，就把它名下所有规划节点的 `last.visible` 置 nil** ✓
    --     ⇒ 下一帧"该显示"时账本认为"没发过"⇒ **重发 `true`** ✓✓
    --   ★ 症状对应（用户实测 ✓）：退出重进第一关没用 ✗（同一条路）·
    --     去一次别的关卡才行 ✓（切屏时 `clues` 重进 `seen` ⇒ 走"显示"那条路重发 ✓）
    --   ⚠️ 键格式 = `id \1 父容器 \1 出现序号`（见 `node_key` ✓）⇒ 用前缀匹配 ✓
    --     （与 `drop_props_of` 同一套写法 ✓ 不另造格式 ✓）
    -- ★ 旧位置那个同名 `forget_visible` 已提到上面（两分支共用）✓

    for i = 1, #all do
      if not seen[all[i].id] and not stale_legacy(all[i].id) then
        self:_set_prop(adapter, all[i].id, "visible", false)
        forget_visible(all[i].id)          -- ★ 藏了就忘掉"发过没有"⇒ 下次该显示时会重发 ✓
      end
    end
    -- ★ 上面只能藏住"当前这一关自己的布局里没有的"控件。
    --   但编辑器是照**所有关卡的最大并集**建的，多出来的控件（cell.6.6 / clue.12 /
    --   tray.F …）界面层根本不知道它们存在，只能让适配层去控件树上扫。
    --
    --   ⚠️ `hide_unlisted` **照旧要调**（即使网格视窗在跑）：它扫的是 `clues` 这一类
    --      托管容器的**直接子控件**，网格视窗的列表项挂在 `clues.grid` 下面、不在这一层，
    --      不会被误伤；而它正好负责把编辑器里遗留的老卡片（`clue.1..18` 本体）关掉。
    if adapter.hide_unlisted ~= nil then
      adapter:hide_unlisted(seen)
    end
  else
    for id in pairs(self._shown) do
      -- ⚠️ 切换帧：上一帧的老线索 id **不藏也不销毁**（名字现在归网格视窗的列表项所有）
      if not seen[id] and not stale_legacy(id) then
        self:_set_prop(adapter, id, "visible", false)
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        -- ★★ 2026-10-06 **这里原来【没有】`forget_visible`** ✗✓ —— ★ 就是 `clues.grid` 的病根 ✓
        --   ★ 首帧分支有 ✓ ★ 这条"每次"的道路没有 ✗ ⇒ ★ 藏了却把"发过 false"记在账本里 ✓
        --   ⇒ ★★ 下一帧规划要发 `true` 时 ⇒ ★ `same_value` 判"没变" ⇒ **不发** ✗✗
        --     ⇒ ★★★ **永久停在 false** ✓ ⇒ ★ 父不可见 ⇒ **列表项再可见也不渲染** ✓✓
        --   ★ 真机铁证 ✓：★ 五个列表项 `visible=true` ✓ 而 `clues.grid = false` ✗
        --   ★★ 同一件事两处实现、只修了一处 ✗ ⇒ ★ 这正是本项目反复踩的那条形状 ✓
        -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        forget_visible(id)               -- ★ 藏了就忘 ⇒ 下次该显示时会重发 ✓✓
      end
    end
  end
  self._shown = seen          -- 记住这一帧显示了什么，下一帧据此算差集

  -- ★★★★★ 2026-10-05 **"补发"这套规则只在这里实现一份**（属性循环和 rect 两条路共用）。
  --
  --   为什么必须**有上限**：规划里有 ~105 个"本关还没建"的控件（见 `layout_plan` 那句
  --   「这些控件还没建」），它们每一条属性都**必然**失败 —— 无上限重试就是
  --   "每帧白跑（`find` 是深度优先搜控件树）+ 日志刷屏"，正是这一轮最不该引入的回退。
  --   ⇒ 同一个 (控件, 属性) 最多补发 `PROP_RETRY` 次；到顶就**认输**：
  --     记账（`last[k] = v` ⇒ 下一帧不再看见它）+ **只报一次**。
  --   额度为什么是 **3**（⚠️ 这段注释原写「10」，与下面的代码 `PROP_RETRY = 3` **不一致** ——
  --   第一遍代码体检发现的注释/代码漂移，已按代码改正）：`render` 由 main.lua 的 tick 驱动
  --   （**每秒至少一次**，另加"有变化时"），所以 3 次 ≈ 几秒内 —— 覆盖"控件晚一步才进树"
  --   这种可恢复情形；而真不存在的控件最多也就白跑这 3 次。**它是常数，不会随时间增长。**
  --   ⚠️ 不要再把它调回 10：v066 真机实测过"~105 个本关没建的控件每个属性白补发 10 次"
  --      ⇒ 加载慢十倍 + 切屏卡顿（见下面 `select.pos_runtime` 那段事故记录）。
  local PROP_RETRY = 3
  -- 成功 ⇒ 清掉这个键的计数（额度不跨"属性变化"累积：这一关失败过几次，不该影响下一次）。
  local function retry_clear(id, key)
    if self._prop_retry ~= nil then
      self._prop_retry[tostring(id) .. "\1" .. tostring(key)] = nil
    end
  end
  -- 失败 ⇒ 记一次。返回 true = **还有额度，下一帧再试**；false = **认输，调用方该记账了**。
  --
  -- ★★★★★ 2026-10-05 **两种失败必须分开给额度** ✗✓（用户实测：**第一关渲染不齐、之后正常**）
  --
  --   为什么：真机日志（`日志_2026/10/05_22:18:35`）把区别指出来了 ——
  --     · **第一遍进关**：`棋盘格子：25 / 25 存在（★ 本次新建 25 个，模板索引 1073741876）` ✗
  --     · **之后任何一关**：`棋盘格子：25 / 25 存在（★ 本次新建 0 个，模板索引 nil）` ✓
  --   ⇒ ★★ 只有"**本次新建**"的那一次，模板子控件（`wall.*` / `door.*` / `note` / `x`）
  --      不是同一帧就绪 ✗ ⇒ `_apply_edges` 的 `self:sub()` 查不到 ⇒ 静默跳过 ✗
  --      ⇒ 补发 3 帧后认输 ⇒ ★ **第一关的墙/门永远不亮** ✗（之后的关卡复用已就绪的实例 ✓）
  --
  --   ⇒ 所以判据是**两种完全不同的失败**：
  --     ① ★ **控件本身不存在**（本关不建的 ~105 个 ✗）⇒ 必然永远失败 ⇒ **3 次就认输** ✓
  --        ★ 这个数字**不能动** ✗ —— v066 真机实测过 10 ⇒ **加载慢十倍 + 切屏卡顿** ✓
  --     ② ★ **控件在、只是它的模板子控件还没就绪** ✗ ⇒ ★ **它一定会就绪** ✓ ⇒ **值得多等一会儿** ✓
  --        ★ 额度用**时间**（`self.now` ✓ 秒）而不是帧数 ✗ —— 帧率在不同机器上含义不同 ✓
  --        ★ 而且**只在"控件存在"时才放宽** ✗ ⇒ 那 ~105 个不存在的控件仍走 3 次上限 ✓✓
  --
  --   ⚠️ 上限依然存在（`SUB_READY_SECONDS`）✗ ⇒ **不会变成每帧死循环** ✓
  local SUB_READY_SECONDS = 2.5   -- ★ 等子控件就绪：约 2.5 秒（足够覆盖模板实例化 ✓ 且有限 ✓）
  local function retry_more(id, key, why, exists)
    local rk = tostring(id) .. "\1" .. tostring(key)
    self._prop_retry = self._prop_retry or {}
    -- ★★ 账本**形状不变** ✗ —— `self._prop_retry[rk]` 仍然是**数字**（次数）✓
    --   ★ 首次失败的时刻**另存一张表** ✓（`self._prop_retry_t0`）
    --   ⚠️ 为什么不把数字换成表 ✗：`tests/prop_ledger.lua` 断言的就是这个数字 ✓
    --      第一版我改成了表 ⇒ 它立刻 13/0 → 11/2 ✗（**这就是退化的来源** ✓ 已改回 ✓）
    local n_try = (self._prop_retry[rk] or 0) + 1
    self._prop_retry[rk] = n_try
    if n_try == 1 then
      self._prop_retry_t0 = self._prop_retry_t0 or {}
      self._prop_retry_t0[rk] = self.now or 0
    end
    -- ★ ① 控件不存在 ⇒ 老规矩：3 次认输 ✓（性能红线，不许放宽 ✗）
    -- ★ ② **只有 `walls`/`doors`** 才配得上"等子控件" ✓✓ —— 见下
    --   ⚠️ 第一版我写成"只要控件在就放宽" ✗ ⇒ `prop_ledger` 立刻 13/0 → 11/2 ✗✓
    --     （`action.back` 也"存在 + 写失败" ✗ 但它的失败**不是**子控件没就绪 ✗
    --       —— 它是**两个规划节点抢同一个控件** ✓ ⇒ 被放宽后每帧重发 2.5 秒 ✗）
    --   ⇒ ★ **测试抓对了** ✓ ⇒ 收窄到**真正会"子控件晚一步就绪"的那两个键** ✓✓
    --     ★ 依据：`Adapter:_apply_edges` 的 `missing_sub` 只出现在 `wall.*` / `door.*` ✓
    --       （`engine_adapter_qianxing.lua:3670-3681`：取不到 `cell.<R>.<C>` 的
    --        `wall.<side>` / `door.<side>` 子控件 ⇒ 返回 false ✓）
    --     ★ 而 `label`/`bg` 之类走的是别的分支 ✓ 不在此列 ✓
    if exists == true and (key == "walls" or key == "doors") then
      local t0 = (self._prop_retry_t0 or {})[rk] or (self.now or 0)
      if (self.now or 0) - t0 < SUB_READY_SECONDS then return true end
    else
      if n_try < PROP_RETRY then return true end
    end
    -- ★ 认输也要留一句话：否则"这条属性到底补上没有"在日志里查不到 ——
    --   而这正是这一轮要回答的问题（第一次进关 vs 第二次进关的差别）。
    --   ⚠️ **不能每条都打**：那 ~105 个没建的控件的属性会一起走到这里 ⇒
    --      照 `prop_err` 的老规矩：**最多 5 条 + 一句汇总**。
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

  -- ★★★★★ 2026-10-05 **属性账本按「计划节点」记账，不按控件 id。**
  --
  --   为什么（这一轮实测抓到的真凶之一）：`build_layout` 里**同一个 id 会出现在两个节点上**
  --   （最典型：`action.back` —— 一个挂 `topbar`、一个挂 `right`，见 L1730 与 L2355）。
  --   而账本原来是 `self._props[n.id]`，**两个节点共用一份"上一帧发过什么"**
  --   ⇒ 节点1 写 `parent=topbar`、节点2 立刻写 `parent=right`（对同一个键来说永远"变了"）
  --   ⇒ 下一帧又是同样两笔，**永远收敛不了**：
  --     · 每帧白跑一次 `find`（深树存在性探测）+ 一次 `set_property`；
  --     · 实测（`tests/grid_cost.lua` [A1]/[E]）：稳态一次 render 里 **10 次搜空**
  --       全是这两个 `action.back`（300 帧 = 3000 次），`rect`/`text`/`style`/`parent`
  --       四个键每个都发两遍。
  --
  --   键 = `id \1 父容器 \1 同(id,父容器)的第几次出现`：
  --     · 带上**父容器**：`action.back` 的两个节点就此分开（各自记账、各自收敛）；
  --     · 带上**出现序号**：万一将来同一个 id 在同一父容器下也出现两次，仍然分得开；
  --     · 用 `\1` 作分隔符（本文件里 `_prop_retry` 已经用这个约定，且 id 里不可能有它）。
  --   ⚠️ `self._created` **仍然按 id** —— 一个 id 只对应**一个**引擎控件，
  --      `create_control` 只能跑一次；而**事件表**已经跟着账本一起改成按规划节点
  --      （`Adapter:set_property` 的 `key == "event"` 分支）——
  --      **本文件把这个 `nkey` 原样传下去**（见 `_set_prop` 的第 5 个参数），
  --      适配层不另造键。
  --   ⚠️ **点击派发改用「认领者」（B2，用户 2026-10-05 拍板 ✓）**：一个 id 只有一个引擎控件、
  --      只有一次绑定，所以只能派发**一份**事件 ⇒ "选哪一份"就是"这颗按钮是什么意思"的决定。
  --      适配层取 `event_claim[id]` = **第一个**给这个控件写 event 的规划节点（**先写的赢**），
  --      不再是"最后写的那个"（`event_latest` 已降级为**纯诊断记录**）。
  --      对 `action.back` 而言 = `topbar` 的那一份 = **`back_confirm`**（「返回菜单」）
  --      ⇒ **鼠标点它和点左上 ↰ 图标走同一条路：先弹 ✓/✗**
  --      （`ui_controller.lua:854` `a == "back_confirm"` ⇒ `self.pending = { action = "back" }`）。
  --      为什么：改之前是"最后写的赢" = `right` 的 `back` ⇒ **鼠标直接跳列表**，而 ↰ 图标
  --      却是 `back_confirm` **先弹 ✓/✗** ⇒ 同一颗按钮两种语义（自相矛盾 ✗）。
  --      三条硬证据与完整理由见 `lua/engine_adapter_qianxing.lua` 的 `Adapter.new`
  --      `self.event_claim` 那段（那里是这条规则的**唯一权威**）。
  local node_seq = {}
  local function node_key(n)
    local base = tostring(n.id) .. "\1" .. tostring(n.parent)
    local seq = (node_seq[base] or 0) + 1
    node_seq[base] = seq
    return base .. "\1" .. tostring(seq)
  end
  -- 控件离开计划时，把它名下**所有**计划节点的账本一起扔掉（前缀匹配，见上面的键格式）。
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
    if not self._created[n.id] then
      -- create_control 也包一层：它内部会 `find` 控件树，真机上"某个节点不提供方法"
      -- 这种事本项目已经踩过（`GetChildren` 那个坑）。建不出来只该少一样东西，
      -- **不该让整帧渲染停在这里**。
      local ok_c, err_c = pcall(function() adapter:create_control(n) end)
      if not ok_c then
        self:_grid_log("create_err:" .. tostring(n.id), "创建控件失败（已跳过这一条，不再每帧刷）：`"
          .. tostring(n.id) .. "` ← " .. tostring(err_c))
      end
      self._created[n.id] = true     -- 记上：免得每帧重试 + 重刷日志
      -- ★ 新的一生 ⇒ 补发额度也归零（见下面「认输」那段）。
      --   不清的话，"被销毁后又重建回来"的控件会**继承上一次的失败次数**，
      --   第一次没写进去就直接认输 —— 那就把这一轮修的毛病又放回来了。
      if self._prop_retry ~= nil then
        local pre = tostring(n.id) .. "\1"
        local stale = {}
        for rk in pairs(self._prop_retry) do
          if rk:sub(1, #pre) == pre then stale[#stale + 1] = rk end
        end
        for j = 1, #stale do self._prop_retry[stale[j]] = nil end
      end
    end
    -- ⚠️ 账本**必须在这里兜底建出来**（不能再放在上面 `if not self._created` 里面）：
    --    第二个同 id 节点永远不会进那个分支（`_created[id]` 已经是 true），
    --    照旧写法它的 `last` 就是 nil ⇒ 每个键都"变了" ⇒ 每帧重发，等于没修。
    local last = self._props[nkey]
    if last == nil then
      last = {}
      self._props[nkey] = last
    end
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
          -- ★★★★★ 2026-10-05 **只有"真的写进去了"才记账** —— 修"第一次进关画得少、第二次正常"。
          --
          --   真机证据（用户实测）：首次进关卡时门/墙 `visible` 读到 true 却**没画出来**，
          --   第二次进同一关（同样的数据）就正常了 —— 这正是"首关限定"的形状。
          --
          --   机制：适配层在 `find(id) == nil` 时是**静默 no-op**（不报错、也不写），
          --   而这里原来是**无条件** `last[k] = v` ⇒ 首次没送达的属性被记成"已下发"
          --   ⇒ **本关内永不重试** ⇒ 只有等下一关（控制器重建、`_props` 清空）才补上。
          --
          --   ⚠️ 但不能无脑每帧重试：规划里有 ~105 个"本关还没建"的控件（日志里那句
          --      「这些控件还没建」），无脑重试 = 每帧白跑 + 噪音 ⇒ **同一个 id.键 最多试
          --      N 次**，超了就认输（记账、不再试），既补上"晚一帧就绪"的控件，
          --      又不会变成性能回退。
          --   ⚠️ **适配器没有 `find` 时一律当作"存在"**（=退回旧行为）：
          --      假适配器（离线测试）就没有 find —— 把"查不了"当成"不存在"会让
          --      每个属性每帧都重写一遍（board_bg 立刻从 28/0 变 0/1 就是这条）。
          --      **查不了就别改变行为**是这里的唯一正确语义。
          local exists = true
          if type(adapter.find) == "function" then
            local e2, r2 = pcall(function() return adapter:find(n.id) end)
            if e2 then exists = (r2 ~= nil) end
          end
          -- ★★★★★ 2026-10-05 **"控件不在"时连 `set_property` 都不用发**。
          --
          --   理由（可证）：适配层 `set_property` 的第一步也是 `self:find(id)`，
          --   拿到 nil 就直接 `return false`（既不写、也不抛）—— 和上面这次探测
          --   **是同一个调用、同一个结果**（中间没有任何东西改控件树）。
          --   少发一次 = 少一遍**深度优先搜控件树**（真机上每个节点一次 pcall + 读 name）。
          --   实测（`tests/grid_cost.lua`，两个同名 `action.back` 规划节点 + 深树）：
          --   一次 render 从 20 次搜空（9360 次 `GetChildren`）降到 10 次（约 4700 次）。
          local ok = exists and self:_set_prop(adapter, n.id, k, v, nkey)
          if ok and exists then
            last[k] = v
            retry_clear(n.id, k)
          elseif not exists then
            -- ★★★★★ 2026-10-05 **控件根本不在本关 ⇒ 立即记账、绝不补发**。
            --
            --   真机实测（v066，用户报"进试玩加载慢了 10 倍不止、后续选关明显卡顿"）：
            --     属性补发 10 次仍未送达，已停止补发：`select.pos_runtime` / `select.visible` /
            --       `select.parent` / `select.kind` / `select.__rect`（控件一直没找到（find 返回 nil））
            --   ⇒ 规划里那 ~105 个"本关还没建"的控件，**每个属性都白补发了 10 次** ✗
            --     每次还要在深树里按名字搜一遍（adapter:find）⇒ 5000+ 次无效调用
            --     ⇒ 加载慢十倍 + 切屏卡顿。这是**我们的补发逻辑自己造成的**，必须掐掉。
            --   ⇒ 两种失败必须分开：
            --       · `exists == false`（控件不在）⇒ **记账、不补发** ✓（本行）
            --       · `exists == true` 但 `ok == false`（控件在，子控件没就绪/句柄失效）
            --         ⇒ 才补发 ✓（下面那支）—— 这才是"第一次进关画得少"要治的
            last[k] = v
          else
            -- 两种失败要**分开报**（下一份真机日志就靠这句区分假设）：
            --   · `exists == false` ⇒ 控件这次根本不在树上（首帧没就绪 / 本关没建）；
            --   · `exists == true` 但 `ok == false` ⇒ 控件在，是**里面那一步**没成
            --     （按钮的 label 子控件没就绪 / 墙门的 wall.* 子控件取不到）。
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            -- ★ 2026-10-05：**把 `exists` 传下去** ✗✓ —— `retry_more` 据此选额度：
            --   · `exists == false` ⇒ 控件不在 ⇒ 老规矩 3 次认输 ✓（性能红线 ✗ 不放宽）
            --   · `exists == true`  ⇒ 控件在、只是子控件没就绪 ✗ ⇒ **给它 2.5 秒等** ✓
            --     ★ 这正是"第一次进关（格子本次新建）画得少、之后再进正常"的治法 ✓
            if retry_more(n.id, k, why, exists) == false then
              last[k] = v          -- 认输：记账，免得每帧再看见它
            end
          end
        end
      end
    end
    local lr = last.__rect
    if force or not lr or lr.x ~= n.rect.x or lr.y ~= n.rect.y or lr.w ~= n.rect.w or lr.h ~= n.rect.h then
      -- ★★★ 2026-09-30：**「这个控件的位置由脚本说了算」**。
      --
      --   背景：适配器有 `respect_editor_rect`（**编辑器几何优先**）—— 只要是存档里
      --   已有的控件，脚本就不碰它的位置（这样你在编辑器里调的位置不会被覆盖）。
      --   例外只有"运行时实例化"的控件（`self.instantiated[id]`）。
      --
      --   而**房间名标签**（`room.label.*`）需要在运行时按每个房间的外框摆 ——
      --   它是存档里的控件（`sync_plan` 建进去的），但**位置必须每帧由脚本算**。
      --   原来的下场：三个标签全被按在存档里那一份几何上，**中心完全重叠**（都是 503,738），
      --   真机上就是三个字叠在一起。
      --
      --   ⚠️⚠️ 用 `runtime_rect`（**只跳过位置检查**），**不要**用 `adapter.instantiated`！
      --   我第一版复用了 `instantiated` —— 那个标记还管着"允不允许销毁控件"，
      --   于是房间标签/选卡色块在某次渲染里短暂不可见时被**真销毁**，再也回不来
      --   （表现为"测试里可见色块 0 块，单独探针却看到 3 块"）。
      -- ★★★★★★★★ 2026-10-16 **v253：几何所有权只剩【一条规则】** ✗✓✓
      --   ★ 用户指令 ✓：「★ **把所有失效的几何/文字脚本代码从脚本中删除**」✓
      --
      --   ★★ 唯一规则 ✓：★ **只有"脚本自己创建的控件"（`adapter.instantiated`）
      --     与"显式声明 `pos_runtime = true` 的那几颗"才由脚本摆位置** ✓
      --     ★ 其余全是 `.gil` 里存在的控件 ⇒ ★ **几何完全归编辑器** ✓
      --
      --   ★ 本条**取代**了 v248 那套三件套判断 ✗✓（★ 已按本轮指令删除 ✓）：
      --     · `cfg.geom_by_editor`（开关 ✓ 已删）
      --     · `pos_runtime` **沿子树继承** + `pos_runtime_inherited`（已删 ✓
      --       —— 它当年的作用就是"让每个规划控件都被判成脚本接管" ✗ 是**病根**本身 ✓）
      --     · `respect_editor_rect`（★ 这条**留着** ✓ —— 它在适配层是**第二道闸** ✓
      --       就算这里漏标记，适配层也不会去碰编辑器几何 ✓ 属于"防御"不是"死代码" ✓）
      --   ★ 为什么能这样简化 ✓：★ 三种老口径的**结论本来就是"归编辑器"** ✓
      --     ⇒ ★ 直接按"是不是脚本建的"判，比绕三个开关更准 ✓
      --
      --   ⚠️ 仍然必须由脚本摆的那几类（★ 别当死代码删 ✓ 见下面各条的 `pos_runtime = true`）：
      --     · ★ **房间名标签** `room.label.*`（按每个房间的外框每帧摆 ✓ 否则三个字叠一起 ✓）
      --     · ★ **选关卡的文字/附件/房间缩略图**（位置从**卡片自己的运行时矩形**推 ✓
      --       —— ★ 卡片归编辑器 ⇒ 它们必须**跟着卡片走** ✓ `editor_card_box` 就是干这个的 ✓）
      --     · ★ **确认卡** `hex.ok/no` 与热区 `hit.ok/no`（按**刚按下的那颗键**摆 ✓）
      --     · ★ **脚本实例化的格子** `cell.*`（没有"编辑器几何"可言 ✓）
      if adapter.instantiated and adapter.instantiated[n.id] then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      elseif n.pos_runtime == true then
        adapter.runtime_rect = adapter.runtime_rect or {}
        adapter.runtime_rect[n.id] = true
      end
      -- ★ 位置也一样：**写成功才记账**（和上面那段属性同一个道理）。
      --   ⚠️ `respect_editor_rect` 打开时适配层会**故意跳过**位置 —— 那属于"故意的空操作"，
      --      它返回 true ⇒ 不会变成每帧重发。
      --
      -- ★★★★★ 2026-10-05 **这里是 v067 漏掉的第二半**（真机实测：v067 之后仍然"没回归原速"）。
      --   日志只剩这一种补发：
      --     属性补发 10 次仍未送达，已停止补发：`select.__rect` /
      --       `obj.carpet.__rect` / `obj.shelf.__rect` / `obj.desk.__rect` / `obj.case.__rect`
      --   ⇒ 那 ~105 个"本关还没建"的控件，**每帧**都要重跑一次 `find`（深树按名搜）+ 写入 ✗
      --     ⇒ 持续卡顿、选关卡顿 —— 和逐属性那条是同一个病，只是走的是另一个分支。
      --   ⇒ 同样按 `exists` 分开：控件不在本关 ⇒ **立即记账、不补发** ✓
      local rect_exists = true
      if type(adapter.find) == "function" then
        local e3, r3 = pcall(function() return adapter:find(n.id) end)
        if e3 then rect_exists = (r3 ~= nil) end
      end
      -- ★ 与逐属性那条同一个道理（见上面那段注释）：控件不在 ⇒ 连 `set_property`
      --   都不发（它第一步也是 `find`，结果必然一样是 nil）。
      local rok = rect_exists and self:_set_prop(adapter, n.id, "rect", n.rect, nkey)
      if rok then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
        retry_clear(n.id, "__rect")
      elseif not rect_exists then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
      elseif retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
      end
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      if stale_legacy(id) then
        -- ★ 切换帧：这个 id 是上一帧按老路径建的，而这一帧网格视窗已经接管。
        --   **只清账本、不销毁** —— 那个名字现在归网格视窗的列表项所有，
        --   `destroy_control` 会按名字反查并把控件 `SetVisible(false)`（甚至在
        --   `instantiated` 名单里时**真销毁**）⇒ 等于把网格里的线索卡关掉/毁掉。
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
    -- ⚠️ 动效也走 pcall + 跳过老线索目标：`play_effect` 第一步同样是 `find(id)`，
    --    命中已回收的列表项时后面的 `read_pose`/`Tween` 都会在**渲染途中**抛错。
    if not stale_legacy(e.target) then
      pcall(function() adapter:play_effect(e.target, e.kind, e) end)
    end
  end
  self.effects = {}
  self.dirty = false
end

return M
