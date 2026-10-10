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
  stats  = { x = 1520, y = 26, w = 380, h = 46 },

  -- 左侧面板：头像卡 + 线索卡 + 图例
  --   ⚠️ 高度必须算够：tray_item_h * 行数 + 行距 不能超过 tray.h，
  --   否则最后一行卡片会**溢出容器**压到下面的线索上（2026-09-26 实测踩到过两次：
  --   先是 2 列 3 行压住线索，后来是 7 个角色排到第 3 行又压住一次）。
  --   现在卡片的**列数**会按人数自适应（见 build_layout），保证永远只占 2 行。
  left   = { x = 24, y = 128, w = 392, h = 880 },
  tray   = { x = 40, y = 148, w = 360, h = 218 },   -- 固定 2 行 × 104 + 10 = 218
  tray_item_w = 112, tray_item_h = 104,             -- tray_item_w 只是参考值，实际按列数均分
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
  clue_max_visible = 18,    -- 硬上限：仍要够 case_003 的 18 条线索（只是屏上同时只显示 5 行，其余靠滚动）
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
  cell   = 160,        -- 仅参考
  cell_gap = 4,        -- 仅参考
  wall_thickness = 10,

  -- 右侧信息栏
  right  = { x = 1420, y = 128, w = 460, h = 880 },

  -- 底部操作条（放在左侧面板底部与棋盘下方之间）
  actions = { x = 478, y = 944, w = 880, h = 120 },  -- y 944..1064，中心 x=918（与棋盘同）
  action_btn = { w = 168, h = 56, gap = 14 },

  modal = { w = 760, h = 460 },

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
  back_btn = { x = 161, y = 77, w = 255, h = 28 },
  confirm  = { x = 344, y = 22, size = 66, gap = 14 },
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
  ROOMWALL  = "roomwall",
}

-- 开屏教程（5 页：怎么破案 / 每行每列一人 / beside 的含义 / 单击双击的区别 / 提交判题）
M.INTRO = {
  { title = "怎么破案",        body = "读线索，把每个角色放到正确的位置上。\n摆满之后，与受害者单独共处一室的人就是凶手。" },
  { title = "每行每列只有一人", body = "每一行、每一列都恰好只能站一个人（受害者也算一个人）。" },
  { title = "“旁边”是什么意思", body = "旁边 = 上下左右四邻，而且必须在同一个房间里。\n隔着墙的不算旁边。" },
  { title = "单击写字，双击放置", body = "单击格子只会留下一个铅笔小字（笔记）。\n在同一格连着点两下，才会把人放上去。" },
  { title = "提交判题",        body = "摆满后点「提交」校验摆位，通过后即可指认凶手。\n拿不准的位置可以先打 X 标记。" },
}

----------------------------------------------------------------------------

local Controller = {}
Controller.__index = Controller
M.Controller = Controller

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
  self.intro_page = opts.skip_intro and (#M.INTRO + 1) or 1
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
local function note_list_of(set)
  if type(set) ~= "table" then return nil end
  local out = {}
  for kk, vv in pairs(set) do if vv then out[#out + 1] = tostring(kk) end end
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
  if res ~= nil and res.ok then
    self.modal = { kind = "accuse_thief" }
  end
  self.dirty = true
end

--- 真正执行"重置关卡"。
function Controller:do_restart()
  local core = self.core
  if core ~= nil and core.reset ~= nil then core:reset() end
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
--     {action="accuse", id=} | {action="close_modal"} | {action="intro_next"} | {action="intro_skip"}
--
--   为什么要双击：官方客户端脚本**只有 CursorClick，没有长按事件**，
--   与其自己造长按阈值，不如用「单击=笔记 / 双击=放置」这一套更明确的手感。
----------------------------------------------------------------------------

-- 双击窗口（秒）：两次单击落在这个窗口内、且在同一格 → 判定为双击
local DOUBLE_CLICK_SECONDS = 0.35

-- 长按窗口（秒）：按住不放超过这么久、且期间基本没移动 → 判定为长按
--
-- 为什么要它：官方**没有长按事件**，所以我们最初用"双击=放置"替代。
-- 但移动端双击不友好（要担心系统双击缩放、手指也容易抖），
-- 所以从 CursorDown/CursorUp 自己合成一个长按 —— **两种手势都触发同一个"放置"**：
--   · PC 键鼠：双击 / 长按按鼠标左键，随你喜欢
--   · 移动端：长按（更好按）
local LONG_PRESS_SECONDS = 0.45
-- 按下到抬起之间允许的位移（画布像素）。超过就当成"划动"，不算点/长按。
local TAP_MOVE_TOLERANCE = 24

function Controller:snapshot()
  self._gesture_snapshot = self.core:serialize()
end

-- 记录一次"某个键"的点击，返回这次是否构成双击
function Controller:is_double(key)
  self.now = self.now or 0
  local last = self.last_key
  if last and last.key == key and (self.now - last.t) <= DOUBLE_CLICK_SECONDS then
    self.last_key = nil
    return true
  end
  self.last_key = { key = key, t = self.now }
  return false
end

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

-- 把挂起的单击落成铅笔笔记（等过双击窗口才执行，免得抢在第二次点击前面）
function Controller:flush_pending_note()

  local p = self.pending_click
  if p == nil then return end
  if (self.now or 0) - p.t < DOUBLE_CLICK_SECONDS then return end
  self.pending_click = nil
  local ok, why = self.core:tap_cell(p.r, p.c)

  if ok then
    self:fx(self:cell_id(p.r, p.c), M.EFFECTS.NOTE)
    self.dirty = true
  else
    self:_refuse(p.r, p.c, why)
  end
end

-- 把当前选中的人放到 (r,c)（双击 / 长按 / 键盘回车 共用这一条路径）
function Controller:do_place(r, c)
  local core = self.core
  self.last_click = nil
  self.pending_click = nil
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
  self.pending_click = nil
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
  self._press = { r = r, c = c, t = self.now or 0, x = x, y = y }
  return false
end

function Controller:on_cell_up(r, c, x, y)
  local p = self._press
  self._press = nil
  if p == nil then return false end
  if p.r ~= r or p.c ~= c then return false end          -- 按在别处，不算
  local dt = (self.now or 0) - p.t
  if dt < LONG_PRESS_SECONDS then return false end         -- 还不够长
  -- 位移太大 = 划动，不算长按
  if p.x ~= nil and x ~= nil then
    local dx, dy = math.abs(x - p.x), math.abs(y - p.y)
    if dx > TAP_MOVE_TOLERANCE or dy > TAP_MOVE_TOLERANCE then return false end
  end
  local ok = self:do_place(r, c)
  print("[murdoku] ★ 放置分辨：抬起被判定为【长按】✓ 时长=" .. string.format("%.2f", dt))
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
  -- ★★★★★ 2026-10-07 **吃掉"点线索卡"带出来的那一次格子点击** ✗✓（治穿透 ✓）
  --   ★ 网格视窗不消费点击 ⇒ ★ 同一次指针事件会**先给列表项、再给棋盘** ✓
  --     ⇒ ★ 点卡片就会顺手点一下格子 ✓（真机日志两次可见 ✓ 见 `_on_grid_item_click` 处注释 ✓）
  --   ★ 这里用"刚点过卡片"的时间戳挡掉 ✓ 窗口 0.35 秒（= 双击窗口 ✓）
  --     ⚠️ 只挡**单击**这一路 ✓ 不影响双击放置/长按 ✓（它们走 down/up 判定，不经过这里 ✓）
  if self._grid_click_t ~= nil and (self.now or 0) - self._grid_click_t <= 0.35 then
    return
  end
  local core = self.core
  self.now = self.now or 0
  -- ★★★★★ 2026-10-07 **吃掉"点线索卡"带出来的那一次格子点击** ✗✓（治穿透 ✓）
  --   ★ 网格视窗不消费点击 ⇒ ★ 同一次指针事件**先给列表项、再给棋盘** ✓
  --     ⇒ ★ 点卡片就会顺手点一下格子 ✓（真机日志两轮都可见 ✓）
  --   ★ 这里用"刚点过卡片"的时间戳挡掉 ✓ 窗口 0.35 秒（= 双击窗口 ✓）
  --     ⚠️ 只挡**单击**这一路 ✓ 双击/长按走 down-up 判定，不经过这里 ✓ ⇒ 不受影响 ✓
  if self._grid_click_t ~= nil and (self.now or 0) - self._grid_click_t <= 0.35 then
    return
  end
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
    if last and last.r == r and last.c == c and (self.now - last.t) <= DOUBLE_CLICK_SECONDS then
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
  self.pending_click = nil
  local had = core.grid[r][c]
  local had_selected = core.selected          -- 要在 tap_cell **之前**取：它会改选中态
  local ok, why = core:tap_cell(r, c)
  -- ★ 2026-10-07 一次性诊断（★ 这次插在赋值【之后】✓ 上一版插在前面，打的是全局 nil ✗）
  --   核心 `tap_cell` 在 **place 模式**就已经是：★ 已有人 ⇒ 拿起 ✓ 没选人 ⇒ 切 ✗ ✓
  --     ★ **选了人 + 空格 ⇒ `toggle_note(selected)` = 铅笔笔记** ✓（`murdoku_core.lua:1910` ✓）
  --   ⇒ **不需要切模式** ✓ 所以这一段只做观测 ✓
  if (self._diag_tap2 or 0) < 6 then
    self._diag_tap2 = (self._diag_tap2 or 0) + 1
    local nt, sel = "?", "?"
    pcall(function()
      sel = tostring(core.selected)
      local row = core.notes and core.notes[r]
      local celln = row and row[c]
      if type(celln) == "table" then
        local ks = {}
        for k, v in pairs(celln) do if v then ks[#ks + 1] = tostring(k) end end
        nt = "{" .. table.concat(ks, ",") .. "}"
      else
        nt = tostring(celln)
      end
    end)
    print("[murdoku] ★ 诊断NOTE2：单击(" .. tostring(r) .. "," .. tostring(c) .. ")  occupied="
      .. tostring(occupied) .. "  selected=" .. sel .. "  返回 ok=" .. tostring(ok)
      .. " why=" .. tostring(why) .. "  该格笔记=" .. nt)
  end
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
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    -- 记下这一击做了什么，供"第二击撤销第一击"用
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = self.now,
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
      self.last_click = { r = r, c = c, t = self.now, did = "none" }
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
      self:on_cell_click(kb.r, kb.c)
      self.pending_click = { r = kb.r, c = kb.c, t = (self.now or 0) - DOUBLE_CLICK_SECONDS - 1 }
      self:flush_pending_note()
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
    if core:undo() then self:fx("hex.undo", M.EFFECTS.UNDO) end

  elseif a == "redo" then
    if core:redo() then self:fx("hex.redo", M.EFFECTS.UNDO) end

  elseif a == "hint" then
    local ok, msg = core:hint()
    self.toast = msg
    self.toast_until = self.now + M.TOAST_SECONDS   -- ★ A8：只补截止时刻，文案一行不动
    if ok then self:fx("hex.hint", M.EFFECTS.SELECT) end

  elseif a == "reveal" then
    -- 直接揭示答案（照 murdoku 的 Reveal，用于教学/放弃）
    core:reset()
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
  elseif a == "accuse_thief" then
    self.pending_thief = event.id
    self.modal = { kind = "accuse_accomplice", thief = event.id }

  elseif a == "accuse_no_accomplice" then
    self:finish_accuse(self.pending_thief, false, nil)

  elseif a == "accuse_pick_accomplice" then
    self:finish_accuse(self.pending_thief, true, event.id)

  elseif a == "accuse" then
    -- 兼容入口：只给盗窃者，同伙按关卡声明处理
  -- ★ 2026-10-02：重置关卡也要 ✓ 确认。
    local code = core:encode_state()
    self.share_code = code
    self.modal = { kind = "share", code = code }
    if self.opts.on_share then self.opts.on_share(code) end

  elseif a == "howto" then
    self.modal = { kind = "howto" }

  elseif a == "intro_next" then
    self.intro_page = (self.intro_page or 1) + 1
    if self.intro_page > #M.INTRO then
      self.intro_page = #M.INTRO + 1
      self.modal = nil
    end

  elseif a == "intro_skip" then
    self.intro_page = #M.INTRO + 1
    self.modal = nil

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

  elseif a == "focus_clue" then
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
      -- ★★ 2026-09-29 修（被"扫 `and nil or`"扫出来的真 bug）：
      --   原文是 `self.focused_clue = (self.focused_clue == ci) and nil or ci`
      --   —— Lua 里 `x and nil` **恒为 nil**，于是永远落到 `or ci`，
      --   结果 `focused_clue` **永远是 ci，再点一次永远取消不掉聚焦**。
      --   （和我在入口刚踩的那个是同一个坑；写成显式 if 就不会有这个问题。）
      if self.focused_clue == ci then
        self.focused_clue = nil       -- 再点一次 = 取消聚焦
      else
        self.focused_clue = ci
      end
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
  self:flush_pending_note()      -- 挂起的单击到点就落成笔记（成功时它自己置 dirty）
  local sec = math.floor(elapsed)
  if sec ~= (self._hud_sec or sec) then
    self._hud_sec = sec
    self.dirty = true
  end
  if #self.effects > 0 then self.dirty = true end
end

function Controller:is_intro_active() return (self.intro_page or 1) <= #M.INTRO end

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
local function inherit_pos_runtime(nodes)
  local pr = {}
  for i = 1, #nodes do
    if nodes[i].pos_runtime then pr[nodes[i].id] = true end
  end
  for _ = 1, 8 do
    local changed = false
    for i = 1, #nodes do
      local n = nodes[i]
      if (not n.pos_runtime) and n.parent ~= nil and pr[n.parent] then
        n.pos_runtime = true
        pr[n.id] = true
        changed = true
      end
    end
    if not changed then break end
  end
end

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
      ["action.back"] = true, ["action.redo"] = true, ["action.hint"] = true,
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
    PREFIX = { "clue.", "hud.", "room.label.", "ruler", "tray.", "action.", "hex.", "hit.",
               "selbtn.", "tpl.",
               (screen == "home") and "select." or "home." }
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
--   方案甲（用户批准）：**接一个已存在的控件当出口**，一个控件都不加、布局一行不动。
--   出口有两个（为什么是两个，见下面 `hud.subtitle` / `home.title` 两处的说明）：
--     · `hud.subtitle` —— 关卡内（撤销 / 取消 / 揭示 / 回滚 / 提交与结案结果…）；
--     · `home.title`   —— 主页（「商城 / 背包」是在主页点的，而主页上整片 `hud.` 前缀
--                         被 `apply_screen_hide` 藏掉 ⇒ 主页必须另有出口）。
--
--   ⚠️ 为什么**不**另找控件、也不加控件：`hud.toast` 已经按参考图删了 ——
--      `tools/sim/out/layout-plan.json` 里没有它，**存档里也没有它的记录**
--      （实测 `208-补active.gil`：`hud.toast` **0 条**；`hud.subtitle` / `hud.title` /
--        `hud.timer` / `hud.timer` / `hud.progress` 各 1 条；`legend` / `clues.more` /
--        `room.label.*` / `ruler.*` / `select.*` 也都是 0 条）
--      ⇒ 写一个**不存在**的控件 = `set_property` 静默 no-op = 这场修复白做 ✗。
--   ⚠️ 空串按"没有提示语"处理：出口控件的 `text` 不允许被清成空串之后还赖在计划里
--      （`nil` 时一律回落到控件本来的文案，见那两处 push）。
function Controller:toast_text()
  local t = self.toast
  if t == nil then return nil end
  t = tostring(t)
  if t == "" then return nil end
  return t
end

function Controller:build_layout()
  local vm = self.core:view()
  local L = M.LAYOUT
  local nodes = {}

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
    local OBJECT_PALETTE = {
      ["obj.shelf"]  = 111051,
      ["obj.case"]   = 111064,
      ["obj.desk"]   = 111050,
      ["obj.carpet"] = 106053,
    }
    --   ⚠️ 这里**不能用 `push`** —— `push` 是在下面才定义的局部函数，
    --     在 `local nodes = {}` 后面直接调它会拿到 nil。
    --     （我第一次就插在这里，dump_layout 当场报 `[C]: in ?`，
    --      连带 play_test 红了 3 条。）直接往 nodes 里塞，绕开这个顺序问题。
    for pid, pimg in pairs(OBJECT_PALETTE) do
      -- 父级是编辑器里的 `assets` 容器（`read_palette` 扫它的子控件）
      nodes[#nodes + 1] = {
        id = pid, kind = "button", parent = "assets", visible = false,
        image_id = pimg,
        rect = { x = 0, y = 0, w = 48, h = 48 },
      }
    end

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
    local anchor = CONFIRM_ANCHOR[pend_action] or CONFIRM_ANCHOR.back
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
      }
      -- ② 热区：格子模板、**不给 image_id**（所以 face 不会被点亮 ⇒ 完全透明），只负责收点击
      nodes[#nodes + 1] = {
        id = "hit." .. a[1]:sub(5), kind = "button", parent = "root",
        visible = vis,
        event = { action = a[7] },
        icon_template = false,         -- 走 cfg.cells.prefab（真机验证：能收到点击）
        rect = rect,
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
  push({ id = "toolbar", kind = "container", parent = "root", rect = rect_of(L.topbar), style = "toolbar" })
  push({ id = "hud.title", kind = "text", parent = "topbar", rect = rect_of(L.title), text = vm.title, style = "title" })
  local announce_text = ""
  if vm.meta_announce == "one" then
    announce_text = "　※ 线索中有一句假话"
  elseif vm.meta_announce == "none" then
    announce_text = "　※ 线索全部为真"
  end
  -- ★★★★★ 2026-10-05 **A8 的出口①（方案甲：接已存在的控件，布局一行不动）**。
  --
  --   为什么选中 `hud.subtitle`：
  --     · `hud.title` = 关卡标题 —— 用户点名**不许用**（覆盖它会破坏「重置后标题不变」）；
  --     · `hud.timer` / `hud.timer` / `hud.progress` 都是玩家**正在看的计数**（时间/步数/进度），
  --       而且只有 ~125px 宽 ⇒ 装不下「还没有游玩记录，先从「选关」开始吧」这种 17 字提示 ✗；
  --     · 本控件是 717px 宽的**副标题行**（标题下面那一行）—— 语义上就是"对玩家说的一句话"，
  --       而且**存档里真实存在**（`208-补active.gil` 有 `hud.subtitle` 记录 ✓
  --       —— 这是硬条件：控件不存在 ⇒ `set_property` 静默 no-op ⇒ 等于没修 ✗）。
  --   ⇒ 有提示语：文字换成提示语、并**强制可见**（有的关卡副标题为空、本来 `visible=false`）；
  --     提示语到点被 `tick` 清空 ⇒ 这里**自动回落到副标题本身**
  --     （`build_layout` 每帧重建 ⇒ 不需要"记住原文"的跨帧状态 ✓ 也不会留残字 ✗）。
  local toast_text = self:toast_text()
  push({ id = "hud.subtitle", kind = "text", parent = "topbar",
         rect = { x = L.title.x, y = L.title.y + 48, w = L.title.w + 320, h = 30 },
         text = toast_text or (tostring(vm.subtitle or "") .. announce_text), style = "subtitle",
         visible = (toast_text ~= nil) or (vm.subtitle ~= nil or announce_text ~= "") })

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
  -- ★★★ 2026-10-01：**右侧三个按钮的深色六边形底图**（参考图里就是六边形）。
  --
  --   数据来源：Miliastra Image Editor（https://qx.070077.xyz）的 **ELEMENTS 导出**。
  --   我在那个网站上用基础图元摆出六边形，导出 `.lua` 拿到坐标/颜色，
  --   再照搬到我们自己的界面里（不依赖"导入外部资产"那条路）。
  --   见 docs/外部资产-怎么用与我做了什么.md。
  --
  --   六边形的拼法（**这是实测出来的**）：
  --     中间一个矩形 + 上面一个三角 + 下面一个三角。
  --     ⚠️ 别想用"两个三角形"拼 —— 那会得到**八角星**，不是六边形（我踩过）。
  --
  --   图元用的是**游戏自带素材**：
  --     `100001` = 基础形状-矩形 / `100003` = 基础形状-三角
  --   这两个 id 我们**已经在用**（`wall.right`/`door.*` 就是 `100001`，真机正常），
  --   而且都在图片素材库的「基础形状」类里（6 个：100001~100006）。
  --
  --   ⚠️ 图片 id 必须在**存档里**写好（`tools/gil/sync_plan.mjs` 的 `setImageId`，
  --   路径 `/#505/#503/#84/#503`）—— 运行时 `SetImage` 换图**不可靠**：
  --   适配器里有实测记录，读回来的 `imageSource` 和存档里的不是同一个值，会配错图集。
  local HEX_RECT, HEX_TRI = 100001, 100003
  local HEX_PARTS = {
    -- { 图元, dx, dy, w, h, 旋转, 颜色(ARGB) }
    { HEX_RECT, 0,   0, 176, 102,   0, 0xFF1B2030 },   -- 描边·中
    { HEX_TRI,  0,  77, 176,  52,   0, 0xFF1B2030 },   -- 描边·上（编辑器里 y 向上）
    { HEX_TRI,  0, -77, 176,  52, 180, 0xFF1B2030 },   -- 描边·下
    { HEX_RECT, 0,   0, 156,  90,   0, 0xFF2B3348 },   -- 内芯·中
    { HEX_TRI,  0,  67, 156,  46,   0, 0xFF2B3348 },   -- 内芯·上
    { HEX_TRI,  0, -67, 156,  46, 180, 0xFF2B3348 },   -- 内芯·下
  }
  -- ★★★★★ 2026-10-03 **第一组：打开「六边形按钮素材」**（用户走完转存后的第一次接入）
  --
  --   为什么要打开：索引已按"从 .gil 读出的真实值"登记好
  --   （`murdoku-btn-hex = 1073742333`，见 `entry_client_script.lua` 的 `prefab_of`），
  --   而上一轮"实例化失败"的真正原因是**当时转存的是图片素材，不是客户端控件模板** ——
  --   这一次转存下来的就是控件模板（每个带 2~3 层图形子记录）⇒ 这条路通了。
  --
  --   ⚠️ 一个变量原则：**这一轮只开这个开关**，其它一律不动
  --   （坐标、锚点、可见性都保持基点的样子）。
  --
  --   底图挂在哪几个键上：**只挂 `.gil` 里真实存在的三个**
  --   —— 基点的存档里只有 `action.back`（返回列表）/ `action.redo`（重置关卡）/
  --      `action.hint`（放大镜）；`action.submit` / `action.undo` **还没有**，
  --      给不存在的键挂底图只会多出三个孤儿控件。
  -- ★★★★★ 2026-10-03 **改回 false** —— 真机探针（16:17）实测：
  --     `InstantiateClientUIControl(1073742333, root)` → **pcall 成功、但返回 nil**
  --   ⇒ 「按模板索引实例化素材」这条路**走不通**（与当初 1073742321 完全一样）。
  --
  --   用户实验得到的两条正确用法：
  --     ① **素材尺寸在"生成时就定好"** —— 之后改素材尺寸或图片尺寸都不会影响显示；
  --     ② **图片必须挂在客户端容器之外**（即只能是**服务器控件**）——
  --        客户端控件容器的子级里，图片加载不了外部资产。
  --
  --   ⇒ 正确做法 = **在编辑器里用「图片 → 静态引用」把素材放进一个控件**（用户的 `m`），
  --     再用 `tools/gil/clone_asset_image.mjs` **克隆那个现成控件**到需要的位置。
  --     —— 而不是让脚本去实例化索引。
  local HEX_PREFAB = false         -- false = 走"克隆现成素材控件"那条（见上面注释）
  local function hex_bg(btnId, cx, cy, size)
    local s = size / 256
    for i = 1, #HEX_PARTS do
      local p = HEX_PARTS[i]
      local w, h = math.floor(p[4] * s + 0.5), math.floor(p[5] * s + 0.5)
      push({
        id = btnId .. ".hex" .. i,
        kind = "button",
        parent = btnId,
        visible = true,
        image_id = p[1],                       -- 素材 id（存档里会写进 /#505/#503/#84/#503）
        imageColor = p[7],                     -- 乘算着色
        -- ★ 真机日志显示：sync_plan 克隆出来的图元是 imageType=Basic（按原始像素铺），
        --   而正常工作的 bg/face 都是 Stretch。Basic 时若素材本身很小，画出来就等于看不见
        --   （这很可能就是「截图上什么都没有」的原因）。
        -- ★★★★★ 2026-10-09 **「imageType 不在存档里」这条【已被证伪】** ✗✓
        --   ⚠️ 原文（错 ✗）：「比过 wall.left/wall.right，只差 id ⇒ 只能运行时设」
        --   ★ 实测：它**就在存档里**，路径 **`/505/503/84/504`**（`=1` ⇒ Stretch ✓
        --     官方枚举 `Basic=0/Stretch=1` ＋ proto3 省略 0 ✓）
        --     · `229` 里 44 条带图片描述组的记录中 5 条写了它、值恒为 1
        --     · 那 5 条**恰好**是真机日志里 `type=Enum.ImageType.Stretch id=100108` 的那 5 条 ✓
        --   ★ 当年为什么没比出来 ✗：`wall.left`/`wall.right` **恰好都缺**这个叶子
        --     ⇒ 那次比对**结构上就看不见它** ✓（又一个"抽样看不到 ≠ 不存在" ✓）
        --   ⇒ ★ **两条路都通**：存档能带（`tools/gil/fix_btn_bg_type.mjs` ✓ 产物 `234` ✓），
        --     运行时也能设（下面这个字段 ✓）⇒ **双保险**，但别再当"只能运行时" ✗
        --   ⚠️⚠️ **2026-10-09 更正：别把它当成"没图"的原因** ✗
        --     用户实测否掉了：「**功能图标的图片形式就是基础**，大多数图片也只有基础一种，
        --     **基础和拉伸绝大多数情况下没有差别**」✓
        --     ⇒ ★ 我犯的是「**把相关当因果**」✗ ⇒ 四键"没图也没字"的真因**仍待查** ✓
        imageType = "Stretch",
        rect = {
          x = cx + math.floor(p[2] * s + 0.5) - math.floor(w / 2),
          y = cy + math.floor(p[3] * s + 0.5) - math.floor(h / 2),
          w = w, h = h,
        },
        rot = p[6],
        pos_runtime = false,                   -- 固定几何，编辑器说了算
      })
    end
  end
  -- ★★★★★ 2026-10-02 **右上三键 = 提交 / 重置关卡 / 撤销**（用户定稿，见 LAYOUT 尾部那段注释）
  --
  --   原来是「撤销 / 提交 / 揭示」竖排在右侧中部（x=1790, y=390/540/690）。
  --   现在按参考图挪到**右上角**，并把「揭示」换成**重置关卡**（从左上搬来）：
  --     上 → 下：提交 / 重置关卡 / 撤销
  --   右边缘 = `LAYOUT.side_key.right_edge`，**右下角那组（0/6 + 放大镜）也贴这条线**。
  local SK = L.side_key
  local sk_x = SK.right_edge - SK.size
  local sk_y = { SK.top, SK.top + SK.size + SK.gap, SK.top + (SK.size + SK.gap) * 2 }
  -- 六边形底图（三个键各一层）
  if HEX_PREFAB then
    -- ★ 第一组：只给"存档里真实存在"的三个键挂底图。
    --   ⚠️ 坐标故意留 `nil` —— 由适配器按 `cfg.parent_of` 把它实例化到**父控件**身上，
    --      位置跟着父控件走。写死 `sk_x/sk_y`（右上角那套）会和 `.gil` 里
    --      `action.back`/`action.redo` 的真实位置（在 `topbar` 里）对不上 ⇒ 底图飘在别处。
    -- ★ 2026-10-04：只留 `action.back` —— `action.redo` / `action.hint` **已从存档里删掉**
    --   （它们与 `hex.redo` / `hex.hint` 重叠且动作重复，用户已批准清理旧控件）。
    --   父控件没了，这两枚底图节点也就没有意义，一并去掉。
    local btns = {
      { "action.back" },
    }
    for i = 1, #btns do
      local b = btns[i]
      push({
        id = b[1] .. ".hexbg", kind = "button", parent = b[1], visible = true,
        rect = { x = 0, y = 0, w = 110, h = 110 },
        pos_runtime = true,          -- 位置跟着父控件（按钮）走
      })
    end
  else
    hex_bg("action.back", sk_x + 55, sk_y[1] + 55, SK.size)
    -- ★★★★★ 2026-10-05 **删掉这两行：`action.redo` / `action.hint` 的六边形底图** ✗
    --
    --   为什么删（真 bug ✓）：
    --     `hex_bg(parent, …)` 会给 `parent` 建 6 个子节点（`parent..".hex1"`…`".hex6"` ✓）。
    --     但 **`action.redo` 与 `action.hint` 这两个父节点，已经在下面 L1718-1740 被删掉了**
    --     （2026-10-04「旧文字按钮 —— 已删」✓ —— 它们的功能改由 `hex.redo`/`hex.hint`
    --      贴图节点 + `hit.redo`/`hit.hint` 热区承担 ✓）。
    --   ⇒ 于是计划里**凭空多了 12 个"父级不存在"的悬空节点** ✗
    --   ⇒ 后果（实测）：模拟器的 `kit.mjs:74`
    --       `parentId = (n.parent && idOf[n.parent]) || canvasRoot.id`
    --     **静默回落到画布根** ✗ ⇒ 父级中心算错 ⇒ 那 12 个 button 又被补上
    --     `bg`(白图 `100108`) + `label` ⇒ ★ **模拟器里凭空多出 12 个白块** ✗✓
    --   ⇒ 这**不改变**任何一条断言的通过/失败条数 ✓，但它**持续污染**所有几何类、
    --     "多余控件"类的断言 ✗（例如 `verify_art.mjs` 的「棋盘区域没有多余控件」✓）
    --
    --   ⚠️ **`action.back` 那一行必须保留** ✓ —— 它是**确实存在于计划里**的父节点
    --     （`layout-plan.json` 实测有 `action.back` 与 `action.back.hex1..6` ✓✓）。
    --   依据：`docs/计划与脚本漂移-根因调查.md` 的 **T3** 条 ✓（提交 `73dd2d8` ✓）
  end

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
  local BK = L.back_btn
  push({ id = "action.back", kind = "button", parent = "topbar", visible = true,
         rect = { x = BK.x, y = BK.y, w = BK.w, h = BK.h },
         text = "返回菜单", event = { action = "back_confirm" }, style = "stamp.sm" })

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
  push({ id = "left", kind = "container", parent = "root", rect = rect_of(L.left), style = "panel.left" })
  -- ★★★★★ 2026-10-02 用户定稿：**头像卡（tray）并进"滚动线索卡"** ——
  --   每张线索卡 = 头像 + 线索文本 + 字母徽章（见下面 `clue.<i>.face` 那段）。
  --   所以这里**不再单独建头像卡**：容器留着但 `visible = false`
  --   （老存档里还有这个控件名，留个空壳比直接删更稳，不会让"控件找不到"的报警刷屏）。
  push({ id = "tray", kind = "container", parent = "left", rect = rect_of(L.tray),
         style = "tray", visible = false })
  -- 头像卡的**列数自适应**：保证永远只占 2 行。
  --   踩过的坑：写死 3 列时，7 个角色的关卡会排到第 3 行，
  --   而 tray 容器只有 2 行高 —— 卡片溢出容器、压住了下面的线索。
  --   规则：per_row = max(3, ceil(人数 / 2))，卡片宽度按剩余宽度均分。
  local gx = L.tray_gap_x or 12
  local gy = L.tray_gap_y or 10
  -- ★★★ 2026-10-02：**清零** —— 头像卡已并进线索卡，不再单独摆（见上面 tray 那段注释）。
  local n_tray = 0
  local per_row = math.max(L.tray_per_row or 3, math.ceil(n_tray / 2))
  local item_w = math.floor((L.tray.w - (per_row - 1) * gx) / per_row)
  local item_h = L.tray_item_h
  for i = 1, n_tray do
    local it = vm.tray[i]
    local col = (i - 1) % per_row
    local row = math.floor((i - 1) / per_row)
    push({
      id = "tray." .. tostring(it.id),
      kind = "button",
      parent = "tray",
      rect = { x = L.tray.x + col * (item_w + gx),
               y = L.tray.y + row * (item_h + gy),
               w = item_w, h = item_h },
      text = it.name,
      image = it.portrait,
      style = it.selected and "portrait.selected" or (it.placed and "portrait.placed" or "portrait"),
      state = { selected = it.selected, placed = it.placed, is_victim = it.is_victim },
      event = { action = "suspect", id = it.id },
    })
  end

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
         style = "panel", pos_runtime = false })
  -- ★★★★★ 2026-10-05 **线索区大底板（`clues.bg`）** —— 用户在编辑器里摆的那张图，
  --   但它的名字不在规划里 ⇒ 脚本从没点亮它 ⇒ 真机日志（11:31）里它一直 `可见=false` ✗
  --   ⇒ 补一条规划节点（`kind = "container"`：只摆位置/显隐，**不设图不设色**，图与色归编辑器）。
  --   尺寸与容器同尺寸（画布 400×544）、挂在 `clues` 下、坐标相对父级 ⇒ (0,0) ✓
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
         pos_runtime = false })
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
  else
  -- ── 走**老路径**（cfg.use_grid=false / 找不到网格视窗 / 填内容失败）：
  --    下面这一段（到 2095 行那个 `end` 为止）才是手写滚动的那一套，照旧照发 ──
  -- ★ 2026-10-05 **滚动条点击区 `clues.bar`** —— 用户新做的隐形热区（画布 24×520），
  --   规划里原来没有它 ⇒ 脚本不认它（"还没建"名单里反过来没有它才怪 ✗）。
  --   位置：条心 x = 464 画布、纵向与卡片区同高 ⇒ 设计 x = (464−16)×6/5 ≈ 537.6、
  --   y/h 与卡片块一致（用 L.clues 的行距算）。⚠️ 等真机日志回来再微调。
  push({ id = "clues.bar", kind = "button", parent = "clues",
         rect = { x = L.clues.x + 480, y = L.clues.y, w = 28.8, h = L.clue_row_h * 5 - 12 },
         visible = true })
  local shown = math.min(#vm.clues, L.clue_max_visible)
  local rows = L.clue_rows or 9
  -- ★ 滚动位置：0 表示从第 1 条开始。**所有 `shown` 条控件都照旧建出来**
  --   （保证任何一条都能滚到 —— 少建控件就等于线索看不见，关卡不可解）。
  local total = shown
  local maxscroll = math.max(0, total - rows)
  self.clue_scroll = self.clue_scroll or 0
  -- 焦点线索自动滚进视野 —— **只在焦点"变化时"做一次**。
  --
  --   ⚠️ 我第一版是每帧都做，结果：只要之前点过某条线索（`focused_clue` 有值），
  --   **每一帧都把滚动位置拽回那条线索** ⇒ ↑/↓ 点了完全没用（探针点了 40 次没动）。
  --   ⇒ 记住"上次为哪个焦点滚过"，只有真的换焦点时才自动滚。
  if self.focused_clue ~= nil and self.focused_clue > 0
     and self._clue_focus_seen ~= self.focused_clue then
    self._clue_focus_seen = self.focused_clue
    if self.focused_clue <= self.clue_scroll then self.clue_scroll = self.focused_clue - 1 end
    if self.focused_clue > self.clue_scroll + rows then self.clue_scroll = self.focused_clue - rows end
  end
  if self.clue_scroll < 0 then self.clue_scroll = 0 end
  if self.clue_scroll > maxscroll then self.clue_scroll = maxscroll end

  -- ↑ / ↓ 两个按钮 + 一条滚动条（引擎**没有滚轮事件**，这是最实在的做法）
  local ARROW = 34
  local top = L.clues.y
  local bottom = L.clues.y + rows * L.clue_row_h
  push({ id = "clues.up", kind = "button", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - ARROW - 6, y = top + 2, w = ARROW, h = ARROW },
         text = "▲", event = { action = "clue_up" },
         style = "tab", visible = (maxscroll > 0) })
  push({ id = "clues.down", kind = "button", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - ARROW - 6, y = bottom - ARROW - 2, w = ARROW, h = ARROW },
         text = "▼", event = { action = "clue_down" },
         style = "tab", visible = (maxscroll > 0) })
  -- 滚动条：轨道 + 滑块（比例条，纯展示；拖动留给真机验证后再加）
  push({ id = "clues.track", kind = "container", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - 8, y = top + ARROW + 6, w = 4, h = bottom - top - 2 * ARROW - 12 },
         style = "panel", visible = (maxscroll > 0) })
  if maxscroll > 0 then
    local trackTop = top + ARROW + 6
    local trackH = bottom - top - 2 * ARROW - 12
    local knobH = math.max(24, math.floor(trackH * rows / total))
    local knobY = trackTop + math.floor((trackH - knobH) * self.clue_scroll / maxscroll)
    -- 滚动条滑块：y 随 `clue_scroll` 变 ⇒ 位置必须由脚本说了算
    -- （和线索卡同一个道理，见下面 `clue.N` 那段的注释）
    push({ id = "clues.knob", kind = "container", parent = "clues",
           rect = { x = L.clues.x + L.clues.w - 8, y = knobY, w = 4, h = knobH },
           style = "tab.active", visible = true, pos_runtime = true })
  end
  -- 计数（"3–11 / 18"），让玩家知道自己是第几条
  push({ id = "clues.count", kind = "text", parent = "clues",
         rect = { x = L.clues.x + L.clues.w - 120, y = top + 2, w = 78, h = ARROW },
         text = string.format("%d-%d / %d",
           maxscroll > 0 and (self.clue_scroll + 1) or 1,
           math.min(self.clue_scroll + rows, total), total),
         style = "muted", visible = (maxscroll > 0) })

  -- 线索卡"刷出来"的动效：每条只弹一次。
  -- 为什么不在生成时直接 fx：这条线索控件可能在**同一帧里刚被创建**，
  -- 而 effects 是在 render 末尾（控件都建完之后）才统一交给适配器播的，
  -- 所以在这里排队是安全的。控制器每个关卡重建一次 → 表随关卡自然重置。
  self._clue_fx = self._clue_fx or {}
  -- ★★★ 2026-09-30：**线索卡拆成「名字 + 内容」两个控件**（参考《派蒙的执律庭实习》：
  --   卡片上的人名/关键字是**红色**的，正文是白色）。
  --
  --   为什么必须拆控件、不能"行内标红"：官方**没有富文本**（查过 API 缓存），
  --   也没有文字宽度测量 ⇒ 无法在一行里给某几个字换色。
  --   ⇒ 做法：**名字占固定宽度的第一列**（`clue.<i>.who`，红色），
  --     正文从固定 x 起（`clue.<i>.what`，常规色）。这样不需要测量宽度。
  --
  --   ⚠️ 切分依据：线索文案里**一定含角色名**（核心的 `text` 用 `ctx.name(...)` 拼的）。
  --     从 `vm.tray` 里找"哪个名字出现在这条文案里"，找到就切；找不到就整条当正文
  --     （**不硬造关键字** —— 宁可不高亮，也不显示编出来的名字）。
  local WHO_W = 99.6    -- 名字列宽（设计）= 画布 83 ★ 2026-10-05 由 132 改
  -- ★★★ 2026-09-30：**卡片左边一个头像、右边一个字母徽章**（参考《派蒙的执律庭实习》：
  --   线索卡是"人物头像 + 线索文字 + 右侧字母（B/C/D）"）。
  --   头像复用已有的 `portrait.*` 调色板（`vm.tray` 里每项都带 `portrait` 字段），
  --   **不引入新素材**；徽章就是嫌疑人的字母 id（A/B/C/D/V）。
  local FACE = 66        -- 头像边长（设计）= 画布 55 ★ 2026-10-05 由 40 改
  local BADGE_W = 40.8   -- 徽章宽（设计）= 画布 34 ★ 2026-10-05 由 30 改
  local PAD = 16.8       -- 卡片内边距（设计）= 画布 14 ★ 2026-10-05 由 8 改

  -- 返回 名字 / 前缀 / 后缀 / 该角色的 id / 头像名
  --
  -- ★ 2026-10-05：**实现已提到模块级**（见 `split_by_name` 上面那段注释）——
  --   网格视窗的列表项填充要用**同一份**切分逻辑，所以这里不再各写一份：
  --   直接调模块级那份，`vm` 显式传进去。
  --
  --   ⚠️ 不能在这里写 `local function split_by_name(txt) return split_by_name(vm, txt) end`
  --      —— 同名 local 在它自己的函数体里就已经生效 ⇒ 变成**无限递归**
  --      （Lua 里 `local function f() ... f() ... end` 指的就是新的那个 f）。

  for i = 1, shown do
    local cl = vm.clues[i]
    -- 这一条落在窗口的第几行（不在窗口里就整条隐藏 —— 但**控件仍然存在**，能滚到）
    local slot = i - self.clue_scroll
    local inWin = (slot >= 1 and slot <= rows)
    local y = L.clues.y + 15 + (slot - 1) * L.clue_row_h   -- +15 设计 = 上内边距 12.5 画布
    -- ★★★★★ 2026-10-05：行高由 `clue_row_h − 6` 改成 **`− 12`**，宽度由 `L.clues.w − 16` 改成
    --   **`CLUE_W`（= 432 设计 = 360 画布）** —— 为了跟用户在编辑器里摆的卡片对齐。
    --   真机日志（11:31）证明旧值把用户的版面冲掉了：`clue.N 367x91`
    --     · 367 = (L.clues.w − 16) × 5/6 = 440 × 5/6
    --     ·  91 = (clue_row_h − 6) × 5/6 = 109 × 5/6
    --   现在：432 × 5/6 = **360** ✓、115.2 × 5/6 = **96** ✓ —— 与编辑器里的一致。
    local h = L.clue_row_h - 12
    local CLUE_W = 432
    local CLUE_PAD = 16.8   -- 左内边距：设计 16.8 = 画布 14 ✓（用户在编辑器里就是这么留的）
    local style = (self.focused_clue == i) and "clue.focus"
                  or (cl.satisfied and "clue.ok" or "clue")
    -- 整行保留（作为卡片底板 + 点击热区）；文字子控件浮在它上面
    --
    -- ★★★ 2026-09-30：**线索卡整块都要 `pos_runtime`**。
    --   它的 y 随**滚动位置**（`clue_scroll`）每帧变 ⇒ 位置必须由脚本说了算。
    --   否则会被 `respect_editor_rect`（编辑器几何优先）按在存档里那一份几何上：
    --   滚动时**卡片纹丝不动**，只有 visible 在变 —— 真机上表现为「滚了但位置没动，
    --   内容在同一个地方换」。这正是房间名标签那个 bug 的同一个形状。
    push({
      id = "clue." .. i,
      kind = "text",
      parent = "clues",
      rect = { x = L.clues.x + CLUE_PAD, y = y, w = CLUE_W, h = h },
      text = cl.text,
      style = style,
      visible = inWin,
      event = { action = "focus_clue", index = i },
      -- ★★★★★ 2026-10-05 **不再给 `pos_runtime`** —— 用户：「编辑器里的位置本来就是对的，
      --   脚本摆位置是纯粹的无效操作，还会出错」。不带这个标记 ⇒ 走「编辑器几何优先」
      --   （代码里 `pos_runtime = false` 那条注释就是这个意思）⇒ 脚本完全不碰坐标 ✓
    })
    -- ★★★★★ 2026-10-05 **两张卡片底图（backrop1 在下 / backrop2 在上）**
    --
    --   用户在编辑器里给每张卡加了两张图，靠"描边色 + 填充色"叠出边框效果。
    --   真机日志（11:31）显示它们**在关卡里也是 visible=false** ✗：
    --       clue.1..5           可见=true      ← 卡片本体在规划里，被点亮
    --       clue.N.backrop1/2   可见=false     ← 不在规划里 ⇒ 脚本从没把它们点亮
    --   ⇒ 在规划里补上这两条（`kind = "container"`：只摆位置/显隐，**不设图、不设文字**，
    --      图片和颜色完全由你在编辑器里配好、脚本不碰）✓
    --
    --   尺寸：backrop2 比 backrop1 四边各小 3.6 设计（= 3 画布）⇒ 露出 3px 描边 ✓
    push({ id = "clue." .. i .. ".backrop1", kind = "container", parent = "clue." .. i,
           rect = { x = L.clues.x + CLUE_PAD, y = y, w = CLUE_W, h = h },
           visible = inWin })
    push({ id = "clue." .. i .. ".backrop2", kind = "container", parent = "clue." .. i,
           rect = { x = L.clues.x + CLUE_PAD + 3.6, y = y + 3.6, w = CLUE_W - 7.2, h = h - 7.2 },
           visible = inWin })

    local who, pre, post, wid, wportrait = split_by_name(vm, tostring(cl.text or ""))
    local tx = L.clues.x + PAD + FACE + PAD      -- 文字起点：让开左边的头像
    local tw = L.clues.w - 16 - (FACE + PAD * 2) - BADGE_W - PAD
    if who ~= nil then
      -- 头像（左边）：复用 `portrait.*` 调色板，**不引入新素材**
      -- （子控件的 y 也跟着卡片走 ⇒ 同样要 `pos_runtime`，理由见上面那段的注释）
      -- ★★★★★ 2026-10-05 **加 `event` —— 这是"点格子没反应"的真修** ✓✗
      --
      --   为什么必须加（实测三段切开 ✓ 见 `docs/点格子没反应-三段切开结论.md` ✓）：
      --     ★ **鼠标侧【没有任何控件发 `suspect` 事件】** ✗ —— 计划里 `"action":"suspect"` 实测 **0 次** ✓
      --     ⇒ `core.selected` 恒为 `nil` ✗ ⇒ `Core:pre_place` 直接返回「**先点一个头像**」✗
      --     ⇒ ★ **单击不落笔记、双击不放置、步数不动** ✗ ⇒ 观感就是"点格子没反应" = `0 / 5` ✓
      --   为什么是这里 ✓：唯一的生产者（原来那个 `for i = 1, n_tray` 里的 `{action="suspect"}` ✓）
      --     **已经死了** ✗ —— `:1870` 那句 `local n_tray = 0`（2026-10-02 头像并进线索卡 ✓）
      --     ⇒ 那个循环**一次都不跑** ✗；而本控件（`clue.<i>.face` = **卡片上的头像** ✓）
      --     **正好就是现在唯一的头像** ✓ ⇒ ★ 让它承担"点一下选这个人" ✓✓
      --   ★ 与 `:1889` 同一个口径 ✓：**`wid` 有值才给** ✓ 没值就不给（不制造无主事件 ✓）
      --   ⚠️ **只加 `event`，不动 rect/尺寸/样式** ✗ —— 布局一个字没变 ✓
      push({ id = "clue." .. i .. ".face", kind = "button", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 16.8, y = y + 36, w = FACE, h = FACE },
             image = wportrait, style = "portrait", visible = inWin,
             event = (wid ~= nil and wid ~= "") and { action = "suspect", id = wid } or nil })
      -- 名字（红）：正文第一列
      push({ id = "clue." .. i .. ".who", kind = "text", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 16.8, y = y + 2.4, w = 99.6, h = 31.2 },
             text = tostring(pre or "") .. who, style = "clue.who", visible = inWin })
      -- 内容：从固定 x 起（不测量宽度也能对齐）
      push({ id = "clue." .. i .. ".what", kind = "text", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 124.8, y = y + 19.2, w = 242.4, h = 67.2 },
             text = tostring(post or ""), style = "clue.what", visible = inWin })
      -- 字母徽章（右边）：就是嫌疑人的字母 id（A/B/C/D/V），参考图那样
      -- ★★★★★ 2026-10-05 **无条件发勋章节点**（原来写成 `if wid ~= nil and wid ~= "" then`）。
      --   后果：像 `selftest_theft_5x5` 这种**线索文本里没有人名**的关卡，`wid` 为空
      --   ⇒ 整个勋章节点都不发 ⇒ 真机上**所有勋章都不出现** ✗（用户实测：所有勋章都没出现）
      --   现在：永远发，文字为空也发（空文字无害，控件本身还在、背景/描边照常显示）。
      if true then
        push({ id = "clue." .. i .. ".badge", kind = "text", parent = "clue." .. i,
               rect = { x = L.clues.x + CLUE_PAD + 400.8, y = y + 64.8, w = 40.8, h = 33.6 },
               text = wid, style = "clue.who", visible = inWin })
        -- ★ 2026-10-05 **同一徽章再发一份，名字用 `letter`** —— 用户在编辑器里把它命名成
        --   `clue.N.letter`，而规划里叫 `badge` ⇒ 名字对不上就写不进去、**字母不显示** ✗
        --   两份都发（同 rect 同文字）：谁存在谁被点亮，另一个只是"还没建"的无害条目 ✓
        push({ id = "clue." .. i .. ".letter", kind = "text", parent = "clue." .. i,
               rect = { x = L.clues.x + CLUE_PAD + 400.8, y = y + 64.8, w = 40.8, h = 33.6 },
               text = wid, style = "clue.who", visible = inWin })
      end
    end
    if inWin and not self._clue_fx[i] and not self:is_intro_active() and self.modal == nil then
      self._clue_fx[i] = true
      self:fx("clue." .. i, M.EFFECTS.CLUE_IN)
    end
  end
  push({ id = "clues.more", kind = "text", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y + rows * L.clue_row_h, w = L.clues.w, h = 30 },
         text = string.format("还有 %d 条线索", math.max(0, #vm.clues - shown)),
         style = "muted", visible = (#vm.clues > shown) })
  end   -- ← 老一套线索控件到此为止：网格视窗在用时**整段跳过**（见上面那道守卫的长注释）

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

  push({ id = "legend", kind = "text", parent = "left", rect = rect_of(L.legend),
         text = legend_text,
         style = "muted" })

  -- ===== 中央棋盘（含坐标尺）=====
  push({ id = "board", kind = "container", parent = "root", rect = rect_of(L.board), style = "board" })
  -- 格子几何按**当前关卡的实际 N** 自适应：
  -- 棋盘区大小固定，格子边长 = 可用边长 / N。这样 5×5 / 6×6 / 7×7 都能正确排布，
  -- 不需要为每个尺寸重摆一次编辑器布局（编辑器里按**最大的 N** 建够格子即可，
  -- 小尺寸关卡多出来的格子由界面层隐藏、位置由脚本运行时摆正）。
  local n = math.max(vm.rows, vm.cols)
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
  -- ★ 2026-09-27 结构修正：坐标尺原来**直接挂在 `board` 下**，和运行时生成的 49 个格子
  --   挤在同一个节点里（board 子树一度有 63 个子控件），树里根本找不到 ruler。
  --   现在独立成一个 `ruler` 容器（占位与 board 相同）。位置仍用**绝对 rect**，
  --   所以改父级**不会移动任何控件**。
  push({ id = "ruler", kind = "container", parent = "board", rect = rect_of(L.board), style = "ruler" })
  -- 列标尺
  for c = 1, vm.cols do
    push({ id = "ruler.c." .. c, kind = "text", parent = "ruler",
           rect = { x = gx + (c - 1) * (cell + gap), y = L.board.y, w = cell, h = ruler - 6 },
           text = "C" .. c, style = "ruler" })
  end
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
    local boxes = cur and cur.room_boxes or {}
    local names = cur and cur.room_names or nil
    local step = cell + gap
    for j = 1, math.min(#boxes, 8) do
      local b = boxes[j]
      local nm = (type(names) == "table" and names[j]) or ("区域 " .. j)
      -- 右下角那一格的位置；标签占该格的右下 3/4，字号由样式控制
      local lx = gx + (b.c2 - 1) * step + math.floor(cell * 0.18)
      local ly = gy + (b.r2 - 1) * step + math.floor(cell * 0.55)
      push({ id = "room.label." .. j, kind = "text", parent = "board",
             rect = { x = lx, y = ly, w = math.floor(cell * 0.82), h = math.floor(cell * 0.42) },
             text = tostring(nm), style = "room.label", visible = true,
             -- ★ 位置每帧由脚本按房间外框算 ⇒ 必须显式声明"脚本说了算"，
             --   否则会被 `respect_editor_rect`（编辑器几何优先）按在存档里那一份几何上，
             --   三个标签**中心重叠**（真机上是三个字叠在一起，模拟器里 box 完全相同）。
             pos_runtime = true })
    end
    for j = #boxes + 1, 8 do
      -- ⚠️ 占位**也要给真实尺寸**，不能给 2×2。
      --
      --   原因：`layout_plan` 是把**所有关卡**的布局取**并集**（为了让编辑器一次建够控件）。
      --   如果本关房间少、把 `room.label.4` 推成 2×2 隐藏，而并集里"第一次出现"的就是它，
      --   那这个控件的几何就**永久是 2×2** —— 真机上房间名会缩成一个小点。
      --   （我第一版就是这么写的，模拟器里 `room.label.1` 的 box 是 2×2。）
      --   ⇒ 占位沿用**最后一个真实房间**的几何，只是 `visible=false`。
      local last = boxes[#boxes]
      local lx = gx
      local ly = gy
      local lw = math.floor(cell * 0.82)
      local lh = math.floor(cell * 0.42)
      if last ~= nil then
        lx = gx + (last.c2 - 1) * step + math.floor(cell * 0.18)
        ly = gy + (last.r2 - 1) * step + math.floor(cell * 0.55)
      end
      push({ id = "room.label." .. j, kind = "text", parent = "board", visible = false,
             rect = { x = lx, y = ly, w = lw, h = lh }, pos_runtime = true })
    end
  end

  -- 行标尺
  for r = 1, vm.rows do
    push({ id = "ruler.r." .. r, kind = "text", parent = "ruler",
           rect = { x = L.board.x, y = gy + (r - 1) * (cell + gap), w = ruler - 6, h = cell },
           text = "R" .. r, style = "ruler" })
  end
  for r = 1, vm.rows do
    for c = 1, vm.cols do
      local cd = vm.cells[r][c]
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
        notes = note_list_of((self.core and self.core.notes and self.core.notes[r]
          and self.core.notes[r][c]) or cd.notes) or false,
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
        object = Controller.object_key_of(vm, cd) or false,
        -- ★ 每格四边的墙 / 门：数据来自 core 的 `view()`（{up,down,left,right} 布尔表），
        --   适配层靠模板里固定的 `wall.*` / `door.*` 子控件 SetVisible 开关来实现 ——
        --   **不需要为每种墙型做模板**。
        walls = cd.walls,
        doors = cd.doors,
        -- ★ 房间染色：`imageColor` 是**读写**字段，所以"同一张底图 + 不同颜色区分房间"
        --   是零额外素材的做法。颜色表在下面 ROOM_COLORS。
        tint = Controller.room_color(cd.room),
        occupiable = cd.occupiable,
        x_mark = cd.x,
        enabled = true,   -- 不可站人的格子也要能点（用于打 X / 提示原因）
        event = { action = "click", r = r, c = c },
      })
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
  --   ⚠️ `action.back` 保留 —— 它还在你的存档里。
  btn("action.back", "right", { x = rx + 324, y = L.right.y + 680, w = 116, h = 52 }, "返回列表",
      { action = "back" }, "tab")

  -- ★★ 2026-09-29：**整块删掉底部操作条**（`actions` 容器 + 5 个按钮）。
  --
  --   用户在编辑器里把 `actions` 以及 `action.q.*` 全删了（存档记录 231 → 197）。
  --   这五个按钮的功能现在都有更直接的入口：
  --     · 放置工具 / 只写笔记 / 划掉这格 / 橡皮擦
  --         → 由「双击长按=放置、单击=✗、单击已放置格=拿起」承担
  --     · 指认凶手 → 顶部工具条的 `action.submit` 就是它
  --   ⇒ 计划里不再声明，脚本也就不会去写不存在的控件。
  --   （以后要做移动端大按钮，可以从 git 历史取回：提交 2f4b1ea）
  local _ = L.actions    -- 布局表里的坐标先留着，方便将来恢复
  local _ = L.action_btn

  -- ===== 开屏教程 =====
  if self:is_intro_active() then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    local page = M.INTRO[self.intro_page]
    push({ id = "intro", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })
    push({ id = "intro.dots", kind = "text", parent = "intro",
           rect = { x = mx + 40, y = my + 30, w = mw - 80, h = 36 },
           text = string.format("第 %d / %d 页", self.intro_page, #M.INTRO), style = "muted" })
    push({ id = "intro.title", kind = "text", parent = "intro",
           rect = { x = mx + 40, y = my + 80, w = mw - 80, h = 60 }, text = page.title, style = "modal.title" })
    push({ id = "intro.body", kind = "text", parent = "intro",
           rect = { x = mx + 40, y = my + 160, w = mw - 80, h = 180 }, text = page.body, style = "modal.body" })
    btn("intro.skip", "intro", { x = mx + 40, y = my + mh - 90, w = 180, h = 60 }, "跳过",
        { action = "intro_skip" }, "tab")
    btn("intro.next", "intro", { x = mx + mw - 240, y = my + mh - 90, w = 200, h = 60 },
        (self.intro_page >= #M.INTRO) and "开始破案" or "下一页", { action = "intro_next" }, "stamp.primary")
  end

  -- ===== 弹窗 =====
  local modal = self.modal
  if modal and not self:is_intro_active() then
    local mw, mh = L.modal.w, L.modal.h
    local mx, my = math.floor((M.DESIGN.width - mw) / 2), math.floor((M.DESIGN.height - mh) / 2)
    push({ id = "modal", kind = "panel", parent = "root", rect = { x = mx, y = my, w = mw, h = mh }, style = "modal" })

    if modal.kind == "accuse_thief" or modal.kind == "accuse_accomplice" then
      local is_acc = (modal.kind == "accuse_accomplice")
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 26, w = mw - 60, h = 56 },
             text = is_acc and "那同伙是谁？" or "摆位成立。谁是盗窃者？",
             style = "modal.title" })
      local per = 3
      for i = 1, #vm.tray do
        local it = vm.tray[i]
        if not (is_acc and it.id == modal.thief) then
          local col = (i - 1) % per
          local row = math.floor((i - 1) / per)
          push({ id = "modal.suspect." .. tostring(it.id), kind = "button", parent = "modal",
                 rect = { x = mx + 40 + col * 232, y = my + 110 + row * 128, w = 212, h = 110 },
                 text = it.name, image = it.portrait, style = "portrait",
                 event = is_acc and { action = "accuse_pick_accomplice", id = it.id }
                                 or { action = "accuse_thief", id = it.id } })
        end
      end
      if is_acc then
        btn("modal.no_accomplice", "modal",
            { x = mx + 40, y = my + mh - 88, w = 280, h = 60 }, "他独自作案（没有同伙）",
            { action = "accuse_no_accomplice" }, "stamp")
      end
      btn("modal.cancel", "modal", { x = mx + mw - 200, y = my + mh - 88, w = 160, h = 60 }, "再看看",
          { action = "close_modal" }, "tab")

    elseif modal.kind == "result" then
      local got, total = self.core:score()
      push({ id = "modal.title", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 40, w = mw - 60, h = 60 },
             text = modal.win and "破案！" or "没能找齐所有人", style = "modal.title" })
      push({ id = "modal.body", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 120, w = mw - 60, h = 120 }, text = modal.message or "", style = "modal.body" })
      push({ id = "modal.stats", kind = "text", parent = "modal",
             rect = { x = mx + 30, y = my + 250, w = mw - 60, h = 40 },
             text = string.format("用时 %s · 误指认 %d 次 · 位置 %d/%d",
                                  self:format_time(vm.hud.time), vm.hud.failed_accusations, got, total),
             style = "muted" })
      btn("modal.again", "modal", { x = mx + 40, y = my + mh - 88, w = 180, h = 60 }, "重玩本关",
          { action = "restart" }, "stamp")
      -- ★ 2026-10-05 **「分享棋局」按钮已删掉**（用户指令：「去掉分享」）。
      --   这里原来是一个 `modal.share` 按钮（文字「分享棋局」，事件名就是 `share`），
      --   但 `share` **从来没有分发分支** ⇒ 按下去没反应（`check_actions` 改前报的 2 个死 action 之一）。
      --   ⚠️ 这段注释里**故意不写出那条事件的完整字面量**：`check_actions.mjs` 是**逐行正则扫源码**，
      --      连注释一起扫（`action\s*=\s*"..."`）⇒ 注释里写出旧代码的字面量会被当成"又发了一次"，
      --      于是它又会红。要复现旧行为，看 `versions/` 里的历史版本即可。
      --   渲染分支 `modal.kind == "share"` **保留**，理由写在下面那一段注释里。
      --   ⚠️ `modal.again` / `modal.next` 的坐标与文字**一个字都没动**。
      btn("modal.next", "modal", { x = mx + 440, y = my + mh - 88, w = 200, h = 60 }, "下一关",
          { action = "next_level" }, "stamp.primary")

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
      if (self._art_gate_log or 0) < 6 then
        self._art_gate_log = (self._art_gate_log or 0) + 1
        -- ★★★★★ 2026-10-08 **渲染分支置标记** ✗✓（★ 本行已证"弹窗开着时每帧都跑" ✓ 真机日志可证 ✓）
        --   ★ 为什么只置标记 ✓：★ 这里的 `self.adapter` **是 nil** ✗（★ 真机连打 6 次全 false ✓）
        --     ⇒ ★ 本处**只报告"弹窗此刻开着"** ✓ ★ 读 `bg` 的活儿交给"拿得到 adapter"的那一侧 ✓
        --   ★ 标记 = 一个递增计数 ＋ 最近一次的时间戳 ✓（★ 两侧靠它对齐 ✓）
        self._modal_seen = (self._modal_seen or 0) + 1
        print("[murdoku] ★ 胶囊底图：到守卫  adapter=" .. tostring(self.adapter ~= nil)
          .. "  闩锁=" .. tostring(self._exit_menu_art))
      end
      if (not self._exit_menu_art) and self.adapter ~= nil then
        self._exit_menu_art = true
        for _, bid in ipairs({ "modal.exit", "modal.save", "modal.settle", "modal.cancel" }) do
          local bg = nil
          pcall(function() bg = self.adapter:sub(bid, "bg") end)
          -- ★ 2026-10-08 探针：★ `bg` 取到没 ✓（★ 取不到 ⇒ 与 `assets` 同源 ✗ 按名取子控件 ✓）
          if (self._art_log or 0) < 8 then
            self._art_log = (self._art_log or 0) + 1
            local _sz = "?"
            pcall(function() _sz = tostring(bg and (bg.sizeDelta and (bg.sizeDelta.x .. "x" .. bg.sizeDelta.y) or "无sizeDelta")) end)
            print("[murdoku] ★ 胶囊底图：bid=" .. tostring(bid) .. "  bg=" .. tostring(bg ~= nil) .. "  size=" .. _sz)
          end
          if bg ~= nil and self.adapter.set_image_deep ~= nil then
            pcall(function() self.adapter:set_image_deep(bg, 107179, nil, nil, "弹窗胶囊") end)
          if (self._art_log2 or 0) < 8 then
            self._art_log2 = (self._art_log2 or 0) + 1
            local _rb = nil
            pcall(function() _rb = tostring(bg and bg.imageId) end)
            print("[murdoku] ★ 胶囊底图：设图后回读 imageId=" .. tostring(_rb))
          end
          end
        end
      end
    elseif modal.kind == "share" then
      -- ★ 2026-10-05 **这一支目前没有入口按钮**（用户当天决定去掉「分享棋局」按钮，
      --   见上面 `modal.kind == "result"` 里那段删除说明）。
      --
      --   **故意留着**，不是忘了删：
      --     · 链路还在 —— `a == "accuse"` 分支仍会 `core:encode_state()` 并构造
      --       `{ kind = "share", code = ... }`，`opts.on_share` 也仍在回调；
      --     · 将来要接**真实分享**（真正的分享面板/复制码）时，只要再加回一个按钮即可，
      --       不必把这一屏重写一遍；
      --     · 代价是零 —— 它只在"别处主动构造 share 弹窗"时才可能出现，平时不进任何计划。
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
      for i = 1, #M.INTRO do
        text[#text + 1] = string.format("%d. %s —— %s", i, M.INTRO[i].title,
                                        M.INTRO[i].body:gsub("\n", " "))
      end
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
  push({ id = "select", kind = "container", parent = "root", rect = FULL,
         visible = (self.screen == "select"), pos_runtime = true })

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
        local PER = 8
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
      push({ id = "select.back", kind = "button", parent = "root", visible = true,
             rect = { x = 120, y = 950, w = 260, h = 80 },
             text = "返回主页", event = { action = "home" } })
        -- ★★★ 2026-10-01：**选关翻页**（关卡多于 8 个时才有意义）。
        --   只有一页时整组隐藏（`visible=false`），不占视觉。
        local pg_visible = (pages > 1)
        if pg_visible then
          push({ id = "select.prev", kind = "button", parent = "root",
                 visible = (page > 1), text = "上一页",
                 rect = { x = 700, y = 950, w = 220, h = 80 },
                 event = { action = "select_page", delta = -1 } })
          push({ id = "select.next", kind = "button", parent = "root",
                 visible = (page < pages), text = "下一页",
                 rect = { x = 1000, y = 950, w = 220, h = 80 },
                 event = { action = "select_page", delta = 1 } })
          push({ id = "select.page", kind = "text", parent = "root", visible = true,
                 text = string.format("第 %d / %d 页", page, pages),
                 rect = { x = 930, y = 955, w = 60, h = 70 } })
        else
          push({ id = "select.prev", kind = "button", parent = "root", visible = false,
                 rect = { x = 700, y = 950, w = 220, h = 80 } })
          push({ id = "select.next", kind = "button", parent = "root", visible = false,
                 rect = { x = 1000, y = 950, w = 220, h = 80 } })
          push({ id = "select.page", kind = "text", parent = "root", visible = false,
                 rect = { x = 930, y = 955, w = 60, h = 70 } })
        end
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
        
        for i = 1, 8 do
          local it = list[lst_base + i]
        local r = { x = 160 + ((i - 1) % 4) * 420, y = 240 + math.floor((i - 1) / 4) * 240,
                    w = 380, h = 200 }
        if it ~= nil then
          -- ★★★ 2026-09-30：卡片改成**三段**（参考《派蒙的执律庭实习》的选关卡片：
          --   上面一条"关名"纸条、中间是**该关棋盘的缩略图**、下面一行"人数/进度"）。
          --   原来是一整块按钮 + 多行文字 —— 缩略图没地方放（文字会盖在它上面）。
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = true,
                 rect = r, event = { action = "pick_level", id = it.id } })
          local t = self:level_card_parts(it)
          push({ id = "select.card." .. i .. ".title", kind = "text", parent = "root",
                 visible = true, text = t.title, style = "card.title",
                 rect = { x = r.x + 16, y = r.y + 10, w = r.w - 32, h = 34 } })
          push({ id = "select.card." .. i .. ".info", kind = "text", parent = "root",
                 visible = true, text = t.info, style = "muted",
                 rect = { x = r.x + 16, y = r.y + r.h - 42, w = r.w - 32, h = 32 } })
          self:push_room_thumb(push, "select.card." .. i, it, r, "select")
        else
          push({ id = "select.card." .. i, kind = "button", parent = "root", visible = false,
                 rect = r })
          -- 空卡片的三个附件也要显式隐藏 —— 否则上一屏的内容会**残留在空位上**
          for _, suf in ipairs({ ".title", ".info" }) do
            push({ id = "select.card." .. i .. suf, kind = "text", parent = "root", visible = false,
                   rect = { x = r.x, y = r.y, w = 1, h = 1 } })
          end
          self:push_room_thumb(push, "select.card." .. i, nil, r, "select")
        end
      end
    end
    -- ⚠️ **主页/选关这条提前 return 之前也必须调** —— 否则这两个屏幕的子树
    --    拿不到继承过来的 `pos_runtime`，子控件继续用编辑器里的锚点+偏移
    --    ⇒ 实际落到屏幕外（就是"界面空白"的直接原因）。
    apply_screen_hide(nodes, self.screen)
      inherit_pos_runtime(nodes)
    return nodes
  end

  -- ★★★★ 2026-10-01 **界面空白的最后一环（用户实测定位）**：
  --   `pos_runtime` 必须**沿子树继承** —— 详见函数外 `inherit_pos_runtime` 的注释。
  --   这一处是**关卡路径**的收口；主页/选关那条提前 return 之前也调了一次。
  apply_screen_hide(nodes, self.screen)
    inherit_pos_runtime(nodes)

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
local ROOM_TINT = {
  4285965944,   -- 暖米（餐厅一类）
  4282326293,   -- 淡蓝（厨房一类）
  4285241469,   -- 草绿（前院一类）
  4290036043,   -- 浅紫
  4291078505,   -- 浅橙
  4291603827,   -- 灰蓝（兜底/第 6 个房间）
}
local ROOM_MAX = 6          -- 一关最多画几个房间色块
local WHITE_MAT = 106053    -- 真机日志里确认过的白底素材 id

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
      push({ id = id, kind = "button", parent = parent, visible = true,
             rect = { x = x, y = y, w = w, h = h },
             image = WHITE_MAT, tint = ROOM_TINT[(j - 1) % #ROOM_TINT + 1], pos_runtime = true })
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

function Controller:level_card_text(it)
  local name = tostring(it.name or it.id)
  local lines = { name }

  -- 第二行：网格尺寸 + 人数（都能读到才写）
  local sz = it.size
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local total = type(it.suspects) == "table" and #it.suspects or nil
  if rows and cols and total and total >= 2 then
    -- `suspects` 里**含受害人**（case_001 是 A/B/C/D + V）⇒ 嫌疑人数 = total − 1
    lines[#lines + 1] = string.format("%dx%d　%d名嫌疑人+1名受害人", cols, rows, total - 1)
  elseif rows and cols then
    lines[#lines + 1] = string.format("%dx%d", cols, rows)
  end

  -- 第三行：进度（只有真的查得到记录才写）
  local p = self.opts.progress and self.opts.progress(it.id) or nil
  if type(p) == "table" then
    local mark = "未开始"
    if p.cleared then mark = "★ 已破案"
    elseif p.started then mark = "· 进行中" end
    if type(p.best) == "string" and p.best ~= "" then mark = mark .. "　" .. p.best end
    lines[#lines + 1] = mark
  end

  return table.concat(lines, "\n")
end

function Controller:layout_plan()
  local saved_intro, saved_modal = self.intro_page, self.modal
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
    { name = "intro",             intro = 1,  modal = nil, screen = nil },
    { name = "board",             intro = 99, modal = nil, screen = nil },
    { name = "accuse_thief",      intro = 99, modal = { kind = "accuse_thief" }, screen = nil },
    { name = "accuse_accomplice", intro = 99,
      modal = { kind = "accuse_accomplice", thief = first_id }, screen = nil },
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
    self.intro_page = st.intro
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

  self.intro_page, self.modal, self.screen = saved_intro, saved_modal, saved_screen

  -- 初始可见性：只有「开局就该看见」的控件才是可见的，其余交给脚本按状态开关。
  -- （脚本每次 render 都会把 visible 同步过去，所以这里留 false 最安全。）
  for i = 1, #order do
    local it = order[i]
    local in_board = false
    for k = 1, #it.states do
      if it.states[k] == "board" or it.states[k] == "intro" or it.states[k] == "accuse_thief"
         or it.states[k] == "accuse_accomplice" or it.states[k] == "result"
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
function Controller:tray_layout_canvas()
  local L = M.LAYOUT
  local vm = self.core:view()
  local n = #vm.tray
  if n == 0 then return nil end

  local gx = L.tray_gap_x or 12
  local gy = L.tray_gap_y or 10
  local per_row = math.max(L.tray_per_row or 3, math.ceil(n / 2))
  local item_w = math.floor((L.tray.w - (per_row - 1) * gx) / per_row)
  local item_h = L.tray_item_h

  local tray_cv = M.to_canvas(rect_of(L.tray))
  local items = {}
  for i = 1, n do
    local col = (i - 1) % per_row
    local row = math.floor((i - 1) / per_row)
    local cv = M.to_canvas({
      x = L.tray.x + col * (item_w + gx),
      y = L.tray.y + row * (item_h + gy),
      w = item_w, h = item_h,
    })
    items[#items + 1] = {
      id = "tray." .. tostring(vm.tray[i].id),
      cx = cv.cx, cy = cv.cy, w = cv.w, h = cv.h,
    }
  end
  return { tray_cx = tray_cv.cx, tray_cy = tray_cv.cy, per_row = per_row, items = items }
end

function Controller:placed_count(vm)
  local n = 0
  for i = 1, #vm.tray do if vm.tray[i].placed then n = n + 1 end end
  return n
end

function Controller:violations_text(vm)
  if #vm.violations == 0 then return "当前没有硬性冲突" end
  local lines = {}
  for i = 1, #vm.violations do lines[#lines + 1] = "· " .. vm.violations[i].text end
  return table.concat(lines, "\n")
end

-- 房间染色表：同一张底图 + 不同 imageColor 就能区分房间 —— **零额外素材**。
--
-- 官方依据：`ClientUIImageControl.imageColor` 是 `ColorValue` 类型、**读写**、
-- Tweenable；ColorValue 由全局函数 `Color(r,g,b,a?)` 创建（0–255，a 可省略）。
-- 适配层会把它落到格子的 `face` 子控件上（见 set_property 的 "tint" 分支）。
--
-- 改这里就能换配色；不想要染色就把整张表清空（返回 nil → 适配层跳过）。
Controller.ROOM_COLORS = {
  { r = 214, g = 196, b = 160 },   -- 1 暖木色
  { r = 178, g = 200, b = 208 },   -- 2 冷灰蓝
  { r = 206, g = 178, b = 200 },   -- 3 淡紫
  { r = 190, g = 206, b = 176 },   -- 4 淡绿
  { r = 220, g = 190, b = 170 },   -- 5 陶土
  { r = 186, g = 190, b = 210 },   -- 6 石板
}

-- 注意：这是**普通函数**不是方法（同 portrait_of 的坑）
function Controller.room_color(room)
  if type(room) ~= "number" then return nil end
  local t = Controller.ROOM_COLORS
  if type(t) ~= "table" or #t == 0 then return nil end
  return t[((room - 1) % #t) + 1]
end

-- 注意：这是**普通函数**不是方法，所以不能用 self:portrait_of(vm, id) 调用
-- （冒号调用会把 self 当第一个参数，vm 就变成控制器了 —— 这个坑已经踩过一次）
function Controller.portrait_of(vm, id)
  if not vm or not vm.tray then return nil end
  for i = 1, #vm.tray do
    if vm.tray[i].id == id then return vm.tray[i].portrait end
  end
  return nil
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
  --   条数与 `#vm.clues` **恒等**（`Core:clue_results()` 对 `level.clues` 一对一映射），
  --   所以直接数关卡数据即可，一个字节的语义都没变。
  local lv = self.core and self.core.level
  local n = #((lv and lv.clues) or {})
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
      if (self._grid_refill_log or 0) < 3 and print then
        self._grid_refill_log = (self._grid_refill_log or 0) + 1
        print("[murdoku] ★ 就地重填：" .. tostring(_rn) .. " 个列表项（★ **不碰 RefreshItems** ✓ "
          .. "⇒ 滚动位置不动 ✓）")
      end
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

  -- ★ 只读探针 ✓：数"视窗里物理上挂了多少个子控件"✗（= 引擎真的建了几个列表项 ✓）
  if print then
    local nk = nil
    pcall(function() local kids = grid:GetChildren() if type(kids) == "table" then nk = #kids end end)
    print("[murdoku] ★ 探针·本次 RefreshItems：传了 **n=" .. tostring(n) .. "** 条；"
      .. "回调进来 **" .. tostring(self._grid_calls or 0) .. "** 次；"
      .. "视窗子控件 **" .. tostring(nk) .. "** 个"
      .. "　⇒ ★ 三者不等就是线索所在 ✓（★ 官方：只为**可见范围内**的项回调 ✓）")
  end
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
      if c ~= nil then
        local sz, ps, vis = nil, nil, nil
        pcall(function() local w, h = c:GetSizeDelta() sz = tostring(w) .. "x" .. tostring(h) end)
        pcall(function() local x, y = c:GetAnchoredPosition() ps = tostring(x) .. "," .. tostring(y) end)
        pcall(function() vis = tostring(c.visible) end)
        print("[murdoku] ★ 模板实况：`" .. nm .. "`  尺寸=" .. tostring(sz)
          .. "  位置=" .. tostring(ps) .. "  visible=" .. tostring(vis)
          .. "　（★ 存档里 clue=(0,0) ✓ clues.grid=(0,0) ✓ clues=(-570,-61.1) ✓）")
      else
        print("[murdoku] ★ 模板实况：`" .. nm .. "` **运行时找不到** ✗")
      end
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
  if (self._grid_geom_log or 0) < 3 and print then
    self._grid_geom_log = (self._grid_geom_log or 0) + 1
    local _f = function(fn)
      local vals = nil
      pcall(function() vals = { fn() } end)
      if vals == nil then return "读不到" end
      local out = {}
      for i = 1, #vals do out[i] = tostring(vals[i]) end
      return table.concat(out, ",")
    end
    local _one = function(k)
      local v = nil
      pcall(function() v = cg[k] end)
      return tostring(v)
    end
    local _cg2 = grid
    if _cg2 == nil then pcall(function() _cg2 = adapter:find("clues.grid") end) end
    if _cg2 ~= nil then
      local _sz = "读不到"
      pcall(function() _sz = tostring(_cg2.sizeDeltaX) .. "×" .. tostring(_cg2.sizeDeltaY) end)
      print("[murdoku] ★ 网格几何1（引擎自己算的）: "
        .. "itemCount=" .. _one("itemCount")
        .. "  **scrollProgress=" .. _one("scrollProgress") .. "**"
        .. "  itemSize=" .. _f(function() return _cg2:GetItemSize() end)
        .. "  spacing=" .. _f(function() return _cg2:GetItemSpacing() end)
        .. "  padding=" .. _f(function() return _cg2:GetPadding() end))
      print("[murdoku] ★ 网格几何2: **GetContentLength=" .. _f(function() return _cg2:GetContentLength() end)
        .. "**  视窗自身 sizeDelta=" .. _sz
        .. "  scrollDirection=" .. _one("scrollDirection")
        .. "  layoutConstraint=" .. _one("layoutConstraint")
        .. "  fixedCount=" .. _one("layoutConstraintFixedCount"))
      print("[murdoku] ★ 网格几何3（读法）: 内容长度 > 视窗尺寸 ⇒ 有得滚 ✓；"
        .. "**scrollProgress ≠ 0 ⇒ 列表已上移 ⇒ 你看到的「第一行」不是第一项** ✗；"
        .. "itemSize 与存档里的 360×96 不一致 ⇒ 引擎用的不是存档那个尺寸")
    end
  end

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
      if print ~= nil then
        print("[murdoku] ★ 诊断3：直接点 `clues.grid` ⇒ SetVisible=" .. tostring(ok_v)
          .. " SetActive=" .. tostring(ok_a)
          .. "　**回读 visible=" .. tostring(back) .. "**"
          .. "　⇒ 回读 true 就说明规划那条路是多余的；回读仍 false ⇒ 引擎不接受，要换招 ✗")
      end
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
  self:_grid_log("summary", string.format(
    "网格视窗：找到 clues.grid ✓ itemPrefabIndex=%s（回读 %s） n=%d RefreshItems 回调 %d 次；"
    .. "索引基准=%s；列表项点击=%s",
    tostring(prefab), tostring(back), n, calls,
    (self._grid_base == nil) and "?" or tostring(self._grid_base),
    (self._grid_click_ok == true) and "支持（用 GetItemIndex 反查索引）"
      or "不支持（列表项收不到光标事件 ⇒ 只能用老卡片的点击，聚焦仍可用）"))
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
  for qi = 1, #q do
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
    if (self._pc_log or 0) < 3 and print then
      self._pc_log = (self._pc_log or 0) + 1
      print("[murdoku] ★ 单射取不到：**走树没找到 `assets`** ✗（★ 不是按名取的问题 ✓）")
    end
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
  if hit == nil and (self._pc_miss or 0) < 4 and print then
    self._pc_miss = (self._pc_miss or 0) + 1
    print("[murdoku] ★ 单射取不到：想要 `" .. tostring(name) .. "` ✗，assets 下实际是："
      .. table.concat(seen, " , ") .. "　（★ 对照看是不是**后缀/大小写**不一样 ✓）")
  end
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
  local lv = core and core.level
  local list = lv and lv.clues
  local n = #(list or {})
  local p = self._grid_text
  if p ~= nil and p.level == lv and p.n == n then return p end
  local vm = core:view() or {}
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
    items[i] = {
      who    = (who ~= nil) and (tostring(pre or "") .. tostring(who)) or "",
      what   = (who ~= nil) and tostring(post or "") or tostring(pre or ""),
      letter = tostring(wid or ""),
      -- ★ 头像素材名（★ 如 `portrait.A` ✓）★ `nil` 表示这一条没有对应角色 ⇒ **不要写图** ✓
      portrait = wportrait,
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
      id     = (cl.who ~= nil) and tostring(cl.who) or nil,
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
  if print then
    print("[murdoku] ★ 网格可见数：一屏放得下 **" .. tostring(n) .. " 项**（"
      .. tostring(self._grid_vis_why) .. "）"
      .. "　⇒ ★ 可见区【之外】的项会被关掉射线 ✓（官方**没有**裁剪承诺 ✗）")
    print("[murdoku] ★ 网格可见带：**|y| ≤ " .. tostring(vh / 2 + ih / 2)
      .. "** 才算在可见区（视窗半高 " .. tostring(vh / 2) .. " ＋ 半个项高 " .. tostring(ih / 2)
      .. "）⇒ 超出就关射线 ✓　（★ 按**位置**判，不按序号 ✗ —— 因为 `scrollProgress` 读不到 ✓）")
  end
  return n
end

-- 可见带半径（视窗高的一半）—— `_grid_visible_count` 里顺便算好的 ✓
function Controller:_grid_band(grid)
  if self._grid_band_h ~= nil then return self._grid_band_h end
  self:_grid_visible_count(grid)
  return self._grid_band_h
end

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
function Controller:_fill_grid_item(adapter, grid, item, index)
  self._grid_calls = (self._grid_calls or 0) + 1
  if item == nil then return end

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
    if (hits == 60 or hits == 600 or hits == 3600) and print then
      print("[murdoku] 网格视窗：引擎重进回调累计 " .. tostring(hits)
        .. " 次（60 ≈ 每帧重进时的一秒）—— 仅用于确认重进频率，每帧成本已为 0")
    end
  end

  -- 索引基准：**第一次回调 = 列表最上面那一项** ⇒ 它的 index 就是基准（0 或 1）。
  --   为什么要判：官方只说"索引以运行时传入/返回的为准"，**没说从 0 还是从 1 起**
  --   （`clue.1` 这些控件名是 1 起，而 Unity 那套列表通常是 0 起）。
  --   判一次就够，之后滚动回调沿用它 —— 这样两种实现都能对上 `vm.clues`（1 起）。
  if self._grid_base == nil then
    self._grid_base = (tonumber(index) == 0) and 0 or 1
  end
  local pos = (tonumber(index) or self._grid_base) - self._grid_base + 1
  -- ★ 2026-10-10 **记下句柄与它当时的 index** ✓ —— ★ 就地重填要用 ✓
  --   ★ 为什么要有它 ✗：★ 有了句柄就能【不重发 RefreshItems】而刷新内容 ✓
  --     ⇒ ★ **滚动位置才保得住** ✓✓（★ 这是"点一下弹回顶部"的治本一步 ✓）
  self._grid_seen = self._grid_seen or {}
  self._grid_seen[item] = index

  -- ★★★★★ 2026-10-10 **单射优先：用户在 `assets/row.<关>.<行>` 里指定的内容，优先于算法** ✗✓
  --   ★ 用户要求 ✓（原话 ✓）：「我需要一个区域让我**指定第几关第几行填什么**」✓
  --     「现在**第几关第几行怎么填是没有定式的**」✗
  --     「先把这个**单射**做好了，有了这个**一一映射**再查显示问题会更方便」✓
  --     「建立这个单射的过程中**说不定就顺手解决**这个问题了」✓
  --   ★ 有配 ⇒ **完全按你配的来** ✓（★ 算法一个字都不写 ✓）
  --   ★ 没配 ⇒ **回落到现有算法** ✓（★ 向后兼容 ✓ 没配的行不会空着 ✓）
  --   ★ 只在**我们那趟**做 ✓ —— ★ 引擎重进时不动内容 ✗（★ 那会覆盖引擎的刷新 ✓）
  if self._grid_in_refresh == true then
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
          for ci = 1, #kids do
            local k = kids[ci]
            local kn = nil
            pcall(function() kn = tostring(k.name) end)
            -- ★ 槽位名可能带自动后缀 ⇒ 取第一段 ✓（★ 项目注释提过"自动后缀算不一样"✓）
            local slot = kn
            -- ★★ 修正（用户示例实证 ✓）：子控件名是 `who.1.1` 这种带后缀的 ✗
            --   ⇒ ★ 槽位名 = **第一个点号之前** ✓（★ 我原来写"第一段非空白"✗ ⇒ 取到 `who.1.1` ⇒ 对不上卡片的 `who` ✓）
            if slot ~= nil then slot = string.match(slot, "^[^%.]+") end
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
                  if (self._row_bad or 0) < 6 and print then
                    self._row_bad = (self._row_bad or 0) + 1
                    print("[murdoku] ★ 单射候选被否：`" .. full .. "` 与 `" .. tostring(slot)
                      .. "` 都不对 ✗（★ 找到的控件既没有 `text` 也没有 `imageId` ✓ ⇒ 丢弃 ✓）")
                  end
                  dst = nil
                end
              end
              if dst ~= nil then
                -- ★ 文本 ⇒ 写文字 ✓；★ 图片 ⇒ 成对写 imageSource + imageId ✓（项目铁律 ✓）
                local txt = nil
                pcall(function() txt = k.text end)
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
                    if (self._row_deep or 0) < 6 and print then
                      self._row_deep = (self._row_deep or 0) + 1
                      local _fn = nil
                      pcall(function() _fn = tostring(_found.name) end)
                      print("[murdoku] ★ 单射下钻：`" .. tostring(slot)
                        .. "` 本身没有 `text` ✗ ⇒ 用它下面的 `" .. tostring(_fn) .. "` ✓")
                    end
                  else
                    if (self._row_notext or 0) < 4 and print then
                      self._row_notext = (self._row_notext or 0) + 1
                      print("[murdoku] ★ 单射下钻失败：`" .. tostring(slot)
                        .. "` 及其子孙【都没有 `text`】✗ ⇒ 写不进去 ✓（★ 这一条要报给你 ✓）")
                    end
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
                    if (self._who_probe or 0) < 8 and print then
                      self._who_probe = (self._who_probe or 0) + 1
                      local _nm2, _sz, _pos2, _vis, _rb = nil, nil, nil, nil, nil
                      pcall(function() _nm2 = tostring(dst.name) end)
                      pcall(function() local w, h = dst:GetSizeDelta() _sz = tostring(w) .. "x" .. tostring(h) end)
                      pcall(function() local x, y = dst:GetAnchoredPosition() _pos2 = tostring(x) .. "," .. tostring(y) end)
                      pcall(function() _vis = tostring(dst.visible) end)
                      pcall(function() _rb = tostring(dst.text) end)
                      print("[murdoku] ★ 目标控件实况：`" .. tostring(_nm2) .. "`"
                        .. "  尺寸=" .. tostring(_sz)
                        .. "  位置=" .. tostring(_pos2)
                        .. "  visible=" .. tostring(_vis)
                        .. "  写后 text=" .. tostring(_rb)
                        .. "　（★ 尺寸为 0 / 位置在框外 ⇒ 引擎不画 ✓）")
                    end
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
    if print then
      local ks = {}
      for k in pairs(self._grid_idx_seen) do ks[#ks + 1] = k end
      table.sort(ks)
      local lo, hi = ks[1], ks[#ks]
      print("[murdoku] ★ 探针·引擎交来的项：**新增 pos=" .. tostring(pos) .. "** "
        .. "⇒ 累计见过 **" .. tostring(self._grid_idx_n) .. " 项**（范围 " .. tostring(lo)
        .. "~" .. tostring(hi) .. "）"
        .. "　总条数=" .. tostring(self._grid_blank_total or "?")
        .. "　★ 若这里**一直不涨** ⇒ 引擎只为固定的几项回调 ✗ ⇒ 多出的线索永远填不上 ✓")
    end
  end
  self._grid_idx_seen[pos] = self._grid_idx_seen[pos] + 1
  -- ★ 一次性汇总 ✓：每 600 次回调报一行"各项被回调的次数分布"✓
  self._grid_cb_total = (self._grid_cb_total or 0) + 1
  if self._grid_cb_total % 600 == 0 and print then
    local ks = {}
    for k in pairs(self._grid_idx_seen) do ks[#ks + 1] = k end
    table.sort(ks)
    local parts = {}
    for i = 1, #ks do parts[i] = tostring(ks[i]) .. "×" .. tostring(self._grid_idx_seen[ks[i]]) end
    print("[murdoku] ★ 探针·回调分布（累计 " .. tostring(self._grid_cb_total) .. " 次）："
      .. table.concat(parts, " ") .. "　★ 总条数=" .. tostring(self._grid_blank_total or "?"))
  end

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
  do
    -- ★★★★★ 2026-10-09 **只在【引擎重进回调】时判位置** ✗✓ —— 这一轮的真正修法 ✓
    --
    --   ★ 真机实测（v105 ✓ 日志原文 ✓）：
    --       `★ 列表项位置：pos=1  y=211.99996948242` … `pos=7  y=211.99996948242`
    --     ★ **七项读出【同一个值】** ✗ ⇒ 我的位置判据**当场失效** ✓
    --   ★ 而那个 212 不是巧合 ✓：
    --       `clues` 容器 y=-61.1 高=544 ⇒ 上边 = **+210.90** ✓
    --     ⇒ ★ `212` ≈ **容器的上边缘** ✓ ⇒ 它其实是**第一格该在的地方** ✓
    --   ★★ 结论 ✓：★ **`RefreshItems` 期间引擎【还没布局】**
    --     ⇒ 那时每个列表项都还停在**模板/上一帧**的位置 ✗ ⇒ **读位置毫无意义** ✓✓
    --     ⇒ ★ 我上一轮那个探针上限 **8 行** ✗ ⇒ **八行全被"我们自己那趟"占满** ✓
    --       ⇒ ★ **从没打印过布局之后的位置** ✓（所以一直看不出问题在哪 ✓）
    --
    --   ★ 修法 ✓：★ **用 `_grid_in_refresh` 分开两种时机** ✓ —— 项目里早就有这个标志 ✓
    --     · `_grid_in_refresh == true`  ⇒ 是**我们**在调 `RefreshItems` ⇒ ★ **不判** ✗（位置是旧的）
    --     · `_grid_in_refresh == false` ⇒ 是**引擎**重进（官方：滚动时会重进 ✓ 日志已证实 ✓）
    --       ⇒ ★ **这时布局已完成** ✓ ⇒ **判位置** ✓
    --   ★ 时机上也正好 ✓：引擎**滚动时**必然重进 ✓
    --     ⇒ 滚出可见区的项**当场被关射线** ✓、滚回来的**当场恢复** ✓✓
    -- ★★★★★ 2026-10-09 **位置判据【已被真机彻底否掉】⇒ 关闭它** ✗✓（只留一条诊断 ✓）
    --
    --   ★ 真机实测（v106 ✓ 日志原文 ✓）——★ **布局之后仍然七项同一个值**：
    --       `★ 列表项位置【引擎重进·布局后 ✓】：pos=1  y=211.99996948242  ⇒ 在可见区内 ✓`
    --       `pos=2 … pos=7  全部 y=211.99996948242` ✗
    --     ⇒ ★ **`anchoredPositionY` 在【复用的列表项】上恒等于模板的位置** ✓
    --       （模板 `clue` 在 `y=212` ✓ 存档实测 ✓）⇒ **它不反映布局** ✗
    --
    --   ★★ 于是本轮定下来的**可靠事实**只有三条 ✓：
    --     ✓ `GetItemIndex(item)` **又准又稳** ✓（真机 `GetItemIndex=1/2/3` ✓ 绝对序号 ✓）
    --     ✓ 引擎**滚动时会重进回调** ✓（已证实 ✓）
    --     ✓ **可见数能算**（`GetItemSize`/`Spacing`/`Padding` ＋ 视窗高 ⇒ 4 项 ✓）
    --   ★★ 而拿不到的：✗ **滚动位置**（`scrollProgress` 恒 `nil` ✓ 只读字段全读不到 ✓）
    --     ✗ **列表项的真实位置**（恒为模板值 ✗）
    --     ⇒ ★★ **从脚本【无法】知道"哪一项在可见区内"** ✗ —— **这是硬限制** ✓
    --
    --   ⇒ ★ 所以这段"按位置关射线"的逻辑**永远不会生效** ✗（七项永远判为"在可见区内" ✓）
    --     ⇒ ★ **关掉它** ✓ —— 它每帧白算一遍位置与比较，还占着 `pcall` ✗
    --     ⇒ ★ **要真正解决"上面还能点到"**，必须走**结构方案**（二选一，见 `接手待办.md` ✓）：
    --         甲 · **让视窗容得下全部内容**（不滚动 ⇒ 没有"区外" ✓）—— 改存档 ✓
    --         乙 · **由脚本接管滚动**（`scrollProgress` 是**读写** ✓ ＋ `interactable=false` 关掉引擎自己滚 ✓）
    --              ⇒ ★ 那时脚本**自己知道**窗口 ✓ ⇒ 能算 ✓ ＋ 顺带就是用户要的**滚动条** ✓
    if (self._grid_pos_note or 0) < 1 and print then
      self._grid_pos_note = (self._grid_pos_note or 0) + 1
      print("[murdoku] ★ 位置判据已关闭：真机实测**布局后**七项仍读同一个 y（=模板位置 ✗）"
        .. "⇒ **脚本无法知道哪一项在可见区内** ✓ 改用【超出容量的项做成空白且不可点】✓")
    end
  end

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
  if cl == nil then return end        -- 超出本关线索数（理论上不会来）⇒ 什么都不写
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
  local _pid = cl.id
  if _pid == nil or _pid == "" then
    if t_portrait ~= nil and t_portrait ~= "" then
      _pid = tostring(t_portrait):gsub("^portrait%.", "")
    end
  end
  if _pid == nil or _pid == "" or #_pid > 2 then _pid = cl.id or cl.who end
  if type(_pid) == "string" and _pid:sub(1, 1) == "@" then _pid = nil end   -- 特殊角色（如 @thief）不算人
  local _placed_now = (_pid ~= nil) and self.core ~= nil and self.core.placed ~= nil
    and self.core.placed[_pid] == true
  local _cgray = self:_grid_item_child_cached(item, index, pos, "gray")
  -- ★ 2026-10-07 一次性诊断：★ "灰白没出现"到底是【没找到 `gray`】还是【placed 判错】✓
  --   ★ 真机反馈 ✓：★ 颜色在编辑器里都对 ✓ 但**没有卡变灰** ⇒ ★ 说明**脚本这侧没生效** ✓
  if (self._gray_log or 0) < 4 then
    self._gray_log = (self._gray_log or 0) + 1
    print("[murdoku] ★ 灰白诊断：pos=" .. tostring(pos) .. "  who=" .. tostring(cl.who)
      .. "  placed=" .. tostring(_placed_now) .. "  找到gray=" .. tostring(_cgray ~= nil)
      .. "  ★ id=" .. tostring(_pid) .. "  portrait=" .. tostring(t_portrait))
  end
  do
    -- ★★★★★ 2026-10-07 **高亮跟【选中】走，且只染"被选中的那张"** ✗✓（用户两条反馈 ✓）
    --   ★ 反馈① ✓：★「★ **描边又变亮了**」✗ —— ★ 我上一版在"未聚焦"时**写死了白色** ✗
    --     ⇒ ★ 等于给每一张卡提亮描边 ✓（★ 项目注释 `ui_controller.lua:4325` 早记过这个坑 ✓）
    --   ★ 反馈② ✓：★「★ **再次单击取消选中后高亮还在**」✗
    --     ⇒ ★ 因为我按 **`focused_clue`（聚焦）** 染色 ✓ 而 **聚焦 ≠ 选中** ✗
    --   ★ 修法 ✓：★ **① 只在被选中时染** ✓ **② 其余情况复原"原来读到的颜色"** ✓（★ 不写白 ✓）
    --     ★ ③ ★ 原色**只在第一次**记 ✓（★ 免得把金色当原色 ✓）
    local _cbp2 = self:_grid_item_child_cached(item, index, pos, "backrop1")
    local _rg2 = self:_grid_item_rec(item, index)
    if _cbp2 ~= nil and _rg2 ~= nil then
      -- ★★★ 2026-10-07 **比的是【人物 id】不是 `cl.who`（那是显示名 ✗）** ✓
      --   ★ 真机教训 ✓：★ 填充里 `cl.who = 老宅主` ✗（显示名 ✓）而 `core.selected = "V"` ✓
      --     ⇒ ★ 拿它比永远不等 ⇒ ★ **重填后高亮不再画 ⇒ 预放置丢高亮** ✗（用户回报 ✓）
      --   ★ id 的权威来源 ✓：★ **视图记录 `self.core:view().clues[pos].who`** ✓（★ 与 `诊断CLUE` 一致 ✓）
      -- ★ 2026-10-09 **不再为这一处单独取视图** ✗✓ —— 上面 `_pid` **已经算好了同一个值** ✓
      --   （原来这里又 `self.core:view()` 一次 ⇒ **每项第 2 次整视图重建** ✗ 实测 `view=14/7 项` ✓）
      --   ★ 语义不变 ✓：`_pid` 与这里原来取的 `v.clues[pos].who` **等价** ✓
      --     （而且 `_pid` 还多做了"去掉 `portrait.` 前缀"和"跳过 `@` 特殊角色"两步 ✓ 更稳 ✓）
      local _pid2 = _pid
      local _sel = (_pid2 ~= nil) and self.core ~= nil and self.core.selected == _pid2
      -- ★★★★★ 2026-10-10 **改成【看当前颜色】的无状态判定** ✗✓
      --   ★★ 真机 bug（用户回报 ✓）：「**点一个人选两张**」✗ —— ★ 实为「**两张卡同时高亮**」✓
      --     ★ 触发条件 ✓：★ **线索条数 > 5 的关卡** ✓（⇒ 列表会滚动 ✓）
      --   ★★ 根因（我读代码读出来的 ✓ 不是猜 ✓）：
      --     原写法是 ★ `elseif _rg2.tint == "sel" then 还原` ✗
      --     ★ 而 `_rg2 = self:_grid_item_rec(item, index)` ✓ —— ★ **它是按 `(item, index)` 缓存的** ✗
      --     ⇒ ★ 列表项被**回收给另一条线索**时 `index` 变了 ✓
      --       ⇒ ★ **拿到一份【全新的记录】** ✓ ⇒ `_rg2.tint == nil` ✗
      --       ⇒ ★★ **`elseif` 进不去 ⇒ 【还原永远不执行】** ✗✓
      --       ⇒ ★ **那张卡就一直留着金色** ✓ ⇒ ★ **两张卡同时高亮** ✓✓
      --   ★ 为什么"条数 > 5"才会出现 ✓：★ 条数少时列表**不滚动** ⇒ 列表项**不被回收** ⇒ 记录不会错位 ✓
      --
      --   ⇒ ★★ 修法 ✓：★ **判定不再依赖任何"按 index 缓存"的状态** ✗
      --     · 取**当前实际颜色** ✓ ⇒ ★ 它就是"这张卡现在是不是金的"的唯一真相 ✓
      --     · 是金色而**这一项不该高亮** ⇒ ★ **无条件还原** ✓（不再问"记录记没记着"✗）
      --     · 原色从哪来 ✓：★ 先看记录 ✓；记录没有（新记录 ✗）⇒ ★ **回落到模板的原色** ✓✓
      -- ★★★★★ 2026-10-10 **彻底无状态：每次填充都【显式写】颜色** ✗✓
      --
      --   ★★ 用户 A/B 对照（★ 最强证据 ✓）：
      --     · 较早那版：★ 视觉上两张卡高亮 ✗ 但**点 e 出 e、点 v 出 v** ✓ ⇒ 事件独立 ✓
      --     · 258 那版：★ **选谁都是 e** ✗ ⇒ ★ 那才真是一张 ✓（那是另一个回归 ✓ 已回退 ✓）
      --   ⇒ ★★ **"两张高亮"是【纯视觉】问题** ✓
      --
      --   ★★ 用户指示 ✓：「**基于 257 修复视觉问题就行了**」✓
      --   ★ 而 257 的形状是：★ 还原**依赖**"当前颜色 == 金色"这个比对 ✗
      --     ⇒ ★ 若引擎读回来的颜色 ≠ 写进去的值 ✗（★ 被规范化 / 带 alpha ✓）
      --       ⇒ ★ **比对永远不成立 ⇒ 永不还原** ✗ ⇒ ★ 高亮留在控件上 ✓
      --       ⇒ ★ 而它此时已代表**另一条线索** ✓ ⇒ ★ **"两张卡同时高亮"** ✓✓
      --   ★ 我上一版改成"按控件记我涂过"✗ ⇒ ★ **用户实测更糟（三张同一张 ✗）** ✓
      --     ⇒ ★ 说明**记状态**这条路本身就不稳 ✓（★ 记的东西总有机会和实际脱节 ✗）
      --
      --   ⇒ ★★★ **正解：不记任何状态** ✓ —— ★ **每次填充【无条件】写一次颜色** ✓：
      --     · 选中 ⇒ 写高亮色 ✓　· 没选中 ⇒ 写原色 ✓
      --     ★ 写的是"这一项此刻该是什么颜色" ✓ ⇒ **不可能粘 ✓ 不可能漏 ✓**
      --   ★ 原色从**模板**取一次并缓存 ✓（★ 模板是这一切的源头 ✓ 与 index 无关 ✓）
      --   ⚠️ 模板读不到 ⇒ 用 **`4294967295`（白）** 兜底 ✓
      --     （★ 项目老注释说"复原不写白"✗ —— ★ 那是指"别把白色当成某些卡的原色"✓
      --      而 `backrop1` 是**乘算着色** ✓ 白 = 不着色 = 原样 ✓ ⇒ 兜底安全 ✓）
      local HL = 4294956107          -- ★ 高亮色（暖金 ✓ 乘算着色 ✓）
      if self._clue_tpl_tint == nil then
        local _tpl = nil
        -- ★★★★★ 2026-10-10 **改走"按名全树找"** ✗✓ —— `adapter:find` 是陈旧句柄 ✓
        --   ★ 真机实证 ✓：★ 所有 `backrop1` 被刷成白色 ✗ 而不是 `26262E` ✓
        --     ⇒ ★ 就是这里取不到 ⇒ 用白兜底 ⇒ 把原色盖掉 ✓✓
        pcall(function() _tpl = self:_find_by_name("clue") end)
        local _tbp = nil
        -- ★★★★★★ 2026-10-10 **这里原来还是 `adapter:sub`** ✗✓✓ —— ★ 这就是"描边变亮"的根 ✓
        --   ★★★ 症状 ✓（用户报 ✓）：「**描边颜色 131 还正常，134 就变亮了**」✗
        --   ★ 上一步 `_tpl` 已经改走"按名全树找"了 ✓ —— ★ **而紧接着这一行【又用陈旧句柄】** ✗
        --     ⇒ ★★ `adapter:sub("clue","backrop1")` **必然取不到** ✓
        --     ⇒ `_tbp` = nil ⇒ `_clue_tpl_tint` = nil ⇒ ★ **不还原** ✓
        --     ⇒ ★★★ **而高亮金 `4294956107` 已经写上去了 ⇒ 【永久残留】** ✓✓
        --   ⇒ ★★ **"变亮" = 高亮金残留** ✓ —— ★ 不是颜色被改坏 ✓，是**没被还原** ✓
        --   ★ 修法 ✓：★ **改成"按名全树找 `backrop1`"** ✓（★ 与 `_tpl` 同一条路 ✓）
        --     ★ 卡片模板的子控件名就是 `backrop1` ✓（★ 不带 `clue.1.` 前缀 ✓ —— 实测过 ✓）
        if _tpl ~= nil then pcall(function() _tbp = self:_find_by_name("backrop1") end) end
        if _tbp ~= nil then pcall(function() self._clue_tpl_tint = _tbp.imageColor end) end
        -- ★★★★★ 2026-10-10 **取不到就【什么都不写】** ✗✓✓
        --   ★ 这里原来写的是「`self._clue_tpl_tint = 4294967295`」（★ 白 ✓）✗
        --     ⇒ ★ **把编辑器里的原色（如 `26262E`）整个盖成白** ✓✓
        --   ⇒ ★ 现在**不兜底** ✗ —— ★ 拿不到原色 ⇒ 后面那步不写 ✓ ⇒ 原色保持 ✓
        --   ⚠️ 代价 ✓：★ 万一某次取不到模板 ⇒ 高亮**不会**被还原 ✓
        --     ★ 但**宁可留着高亮，也不该把底图刷白** ✗（★ 白是可见的破坏 ✓）
      end
      -- ★★★★★ 2026-10-10 **只在【确实拿到原色】时才写** ✗✓✓
      --   ★ `_sel` ⇒ 写高亮 ✓（★ 高亮色是常量 ✓ 不依赖取到什么 ✓）
      --   ★ 非 `_sel` ⇒ ★ **只有 `_clue_tpl_tint` 有值才写** ✓
      --     ★ 没有值 ⇒ **一个字都不写** ✗ ⇒ ★ 编辑器里的原色保持 ✓✓
      --   ★ 这条是"所有 backrop1 变白"的直接修复 ✓
      -- ★★★★★★ 2026-10-10 **写色三步：高亮 ✓ / 还原 ✓ / 都没有 ⇒ 不写** ✗✓✓
      --   ★ 现在 `_clue_tpl_tint` 走树了 ✓ ⇒ 正常情况下【一定拿得到】✓ ⇒ 高亮会被正常还原 ✓
      --   ⚠️ 万一还是拿不到（★ 例：模板还没实例化 ✓）⇒ ★ **不写** ✗：
      --     ★ **宁可这一次不点亮** ✓，★ **也不要把金色永久留在卡上** ✗✓
      --     ★（★ 这是"变亮"那一类问题的**兜底原则** ✓ 与"别拿白色顶替"同一条 ✓）
      if _sel and self._clue_tpl_tint ~= nil then
        pcall(function() _cbp2.imageColor = HL end)
      elseif (not _sel) and self._clue_tpl_tint ~= nil then
        pcall(function() _cbp2.imageColor = self._clue_tpl_tint end)
      else
        -- ★ 没拿到原色 ⇒ 高亮也不点 ✗（★ 免得留下不可还原的金色 ✓）
        if (self._tint_skip or 0) < 3 and print then
          self._tint_skip = (self._tint_skip or 0) + 1
          print("[murdoku] ★ 染色跳过：取不到模板原色 ✗ ⇒ 这一次【不点亮】"
            .. "（★ 免得留下不可还原的金色 ✓ 这是\"变亮\"的兜底 ✓）")
        end
      end
    end
  end

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
    local _rg_pre = self:_grid_item_rec(item, index)
    if _rg_pre == nil or _rg_pre.gray_noray ~= true then
      if _rg_pre ~= nil then _rg_pre.gray_noray = true end
      if _cgray.raycastTarget ~= nil then pcall(function() _cgray.raycastTarget = false end) end
      if _cgray.blockRaycast ~= nil then pcall(function() _cgray.blockRaycast = false end) end
      if _cgray.interactable ~= nil then pcall(function() _cgray.interactable = false end) end
      print("[murdoku] 灰白层 `gray`：已关掉射线与交互（点击照常落在卡片上）")
    end
    local _rg = self:_grid_item_rec(item, index)
    if _rg ~= nil and _rg.gray ~= _placed_now then
      _rg.gray = _placed_now
      if _cgray.SetVisible then pcall(function() _cgray:SetVisible(_placed_now) end) end
      if _cgray.SetActive then pcall(function() _cgray:SetActive(_placed_now) end) end
    end
  end
  local t_portrait = cl.portrait        -- ★ 头像素材名（★ 如 `portrait.A` ✓；★ nil ⇒ 不写图 ✓）

  -- ★ 子控件句柄走记忆表（改之前：一次回调 54 次 `item:GetChild`，滚动时每帧 54 次）
  local c_who    = self:_grid_item_child_cached(item, index, pos, "who")
  local c_what   = self:_grid_item_child_cached(item, index, pos, "what")
  local c_letter = self:_grid_item_child_cached(item, index, pos, "letter")
  local c_face   = self:_grid_item_child_cached(item, index, pos, "face")

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
  if c_face ~= nil and t_portrait ~= nil and t_portrait ~= "" then
    -- ★ 自己取一次记录表 ✓ —— ★ 不依赖下面文字那段的 `rec` ✓（★ 那段在这之后才定义 ✓）
    local rec_f = self:_grid_item_rec(item, index)
    local fv = rec_f and rec_f.face
    if fv == nil or fv.idx ~= index or fv.name ~= t_portrait then
      local want = t_portrait
      local id = nil
      pcall(function()
        if adapter ~= nil and adapter.resolve_asset ~= nil then id = adapter:resolve_asset(want) end
      end)
      if id ~= nil then
        local ok_img = false
        pcall(function() ok_img = c_face:SetImage(c_face.imageSource, id) end)
        if not ok_img then pcall(function() ok_img = c_face:SetImage(id) end) end
        if rec_f ~= nil then rec_f.face = { idx = index, name = want, ok = ok_img } end
      end
    end
  end

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
      local ALGO_TEXT = false
      if ALGO_TEXT then
      -- ★★★★★★ 2026-10-10 **算法不再填文案** ✗✓✓ —— ★ 用户要求 ✓
      --   ★★ 用户原话 ✓：「**与其和它竞争覆盖，不如让这一堆吃性能还干扰功能的废弃脚本直接消失**」✓
      --   ⇒ 它现在：★ 功能冗余 ✗ ＋ **每帧跑 60 次** ✗ ＋ **和单射抢覆盖** ✗ ⇒ ★ 关掉 ✓
      --   ★ 保留 ✓：★ `gray` 灰白 ✓　★ 高亮 ✓　★ 点击 ✓　★ 格子/棋盘 ✓
      --   ★ 想恢复 ✗：★ `ALGO_TEXT` 改 `true` ✓（一行 ✓）
        local ALGO_TEXT = false
        if ALGO_TEXT then
        if tv.who    ~= t_who    then if write_control_text(c_who, t_who)       then tv.who    = t_who    end end
        if tv.what   ~= t_what   then if write_control_text(c_what, t_what)     then tv.what   = t_what   end end
        if tv.letter ~= t_letter then if write_control_text(c_letter, t_letter) then tv.letter = t_letter end end
      else
        -- 理论上到不了（`_grid_item_rec` 对非 nil 的 item 一定给得出记录）；兜底照旧写。
        write_control_text(c_who, t_who)
        write_control_text(c_what, t_what)
        write_control_text(c_letter, t_letter)
      end
        end   -- ★ if ALGO_TEXT then 收尾 ✓
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
  -- ★★★★★★ 2026-10-10 **末次单射：放在填充的最后** ✗✓✓
  --
  --   ★★ 用户判断正确 ✓（原话 ✓）：「**是不是先得把原来那套填入删了，不然新内容进不来**」✓
  --   ★ 实测 ✓：★ 卡片上还是"原来脚本自动填入的那些内容"✗
  --   ★ 根因 ✓：★ 原来的单射块在 `pos` 算完后、**算法之前** ✗
  --     ⇒ ★ **算法随后把 `who`/`what`/`letter`/`face` 又写了一遍** ✓
  --     ⇒ ★★ **你配的内容被覆盖** ✓✓
  --   ⇒ ★ 修法 ✓：★ **保留原来的块**（★ 它负责"计数/日志"✓）
  --     ★ 并**在这里再跑一次** ✓ ⇒ ★ **你配的最终生效** ✓
  --   ⚠️ 两次都只在**我们那趟**（`_grid_in_refresh == true` ✓）—— ★ 引擎重进时一次都不跑 ✓
  --   ⚠️ 锚点教训 ✓：★ 我两次想"移动"这个块都没移成 ✗（★ 锚点不匹配 ✓）
  --     ⇒ ★ 改用"**在确定的位置再跑一次**" ✓ —— ★ 不改动已有代码 ✗ 风险最小 ✓✓
  do
    if true then   -- ★★★★★ 2026-10-10 **去掉了 `_grid_in_refresh == true` 限定** ✗✓✓
      --   ★★★ 这是"内容依旧没变化"的最后一道坎 ✓
      --     ★ 真机日志 ✓：`★ 网格视窗：引擎重进回调累计 60 次（≈ 每秒 60 次）`
      --     ⇒ ★★ **引擎【每帧】重进 `RefreshItems`** ✓
      --       ★ 而重进时 `_grid_in_refresh == false` ✗ ⇒ ★ **我的末次单射不跑** ✓
      --       ★ 但**算法每帧都在跑** ✗ ⇒ ★ **它每帧把卡片刷回算法的文字** ✓✓✓
      --     ⇒ ★★ 所以末次单射**只在第一帧有效**，第二帧就被盖掉 ✓
      --   ⇒ ★ 修法 ✓：★ **末次单射【不限定哪一趟】** ✓ —— ★ 每次填充都跑 ✓
      --     ★ 为什么安全 ✗：它**只读 `assets/row.*`** ✓、**只写卡片子控件** ✓
      --       ★ **不碰引擎的列表项** ✗ ✓、**不碰滚动** ✗ ✓、**不调 `RefreshItems`** ✗ ✓
      --     ⚠️ 而**前面那个"早期"块仍保留 `_grid_in_refresh` 限定** ✓
      --       （★ 它只负责计数/日志 ✓ 每帧跑会刷屏 ✓）
      local lv_no = self:_level_ordinal()
      if lv_no ~= nil then
        local rc = self:_palette_child("row." .. tostring(lv_no) .. "." .. tostring(pos))
        if rc ~= nil then
          local wrote2 = 0
          local kids = nil
          pcall(function() kids = rc:GetChildren() end)
          if type(kids) == "table" then
            for ci = 1, #kids do
              local k = kids[ci]
              local kn = nil
              pcall(function() kn = tostring(k.name) end)
              local slot = kn
              if slot ~= nil then slot = string.match(slot, "^[^%.]+") end
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
                  if (self._row_bad or 0) < 6 and print then
                    self._row_bad = (self._row_bad or 0) + 1
                    print("[murdoku] ★ 单射候选被否：`" .. full .. "` 与 `" .. tostring(slot)
                      .. "` 都不对 ✗（★ 找到的控件既没有 `text` 也没有 `imageId` ✓ ⇒ 丢弃 ✓）")
                  end
                  dst = nil
                end
              end
                if dst ~= nil then
                  local txt = nil
                  pcall(function() txt = k.text end)
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
                    if (self._row_deep or 0) < 6 and print then
                      self._row_deep = (self._row_deep or 0) + 1
                      local _fn = nil
                      pcall(function() _fn = tostring(_found.name) end)
                      print("[murdoku] ★ 单射下钻：`" .. tostring(slot)
                        .. "` 本身没有 `text` ✗ ⇒ 用它下面的 `" .. tostring(_fn) .. "` ✓")
                    end
                  else
                    if (self._row_notext or 0) < 4 and print then
                      self._row_notext = (self._row_notext or 0) + 1
                      print("[murdoku] ★ 单射下钻失败：`" .. tostring(slot)
                        .. "` 及其子孙【都没有 `text`】✗ ⇒ 写不进去 ✓（★ 这一条要报给你 ✓）")
                    end
                  end
                end
              end
              if type(txt) == "string" then
                    -- ★★★★★ 2026-10-10 **探针：写入前后各读一次** ✗✓（★ 一次定案 ✓）
                    --   ★ 现象 ✓：日志说"写了 2 个槽位"✓ 但画面上看不到 ✗
                    --   ⇒ ★ 三种可能 ✓：① 写到错的控件 ✗ ② 写了但被属性挡住 ✗ ③ 引擎重画 ✗
                    --   ★ 本探针把三者分开 ✓：★ 目标控件名 / 写入值 / 写后读回 ✓
                    local _dn, _before, _after = nil, nil, nil
                    pcall(function() _dn = tostring(dst.name) end)
                    pcall(function() _before = dst.text end)
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
                    pcall(function() _after = dst.text end)
                    if (self._row_probe or 0) < 12 and print then
                      self._row_probe = (self._row_probe or 0) + 1
                      print("[murdoku] ★ 单射写入探针：slot=" .. tostring(slot)
                        .. "  目标控件=" .. tostring(_dn)
                        .. "  写入=" .. tostring(txt)
                        .. "  写前=" .. tostring(_before)
                        .. "  写后读回=" .. tostring(_after)
                        .. (tostring(_after) == tostring(txt) and "  ⇒ ★ 控件里【确实变了】✓（那问题在渲染层 ✓）"
                            or "  ⇒ ★★ 控件里【没变】**（写没进去 ✓ 或写错控件 ✓）"))
                    end
                    wrote2 = wrote2 + 1
                  end
                  -- ★★★★★★ 2026-10-10 **图的来源要【往下钻一层】** ✗✓✓（★ 用户推断 ✓）
                  --   ★ `face.*` 是**模板引用控件** ✗ ⇒ ★ 它自己没有 `imageId` ✓
                  --     ⇒ ★ 真正的图在它引用的模板【里面】** ✓
                  --   ★ 所以：★ 先把 `k` 钻到"能设图的那个控件"，再读它的 `imageId`/`imageSource` ✓
                  --   ★ 钻不到 ⇒ 退回读 `k` 自己 ✓（★ 兼容"直接是图片控件"的老做法 ✓）
                  local _kimg = self:_find_image_holder(k)
                  if _kimg == nil then _kimg = k end
                  local iid = nil
                  pcall(function() iid = _kimg.imageId end)
                  if iid ~= nil then
                    local src = nil
                    pcall(function() src = k.imageSource end)
-- ★★★★★★ 2026-10-10 **图片用 `SetImage`，不用属性赋值** ✗✓✓
                    --
                    --   ★★★ 与文字那次【同一个模式】✓（★ 用户再次指对 ✓）：
                    --     ★ 项目自己的图片写入器（`engine_adapter_qianxing.lua:730-732` ✓）：
                    --       `pcall(function() src = target.imageSource end)`
                    --       `local ok2 = pcall(function() target:SetImage(src, node.image_id) end)`
                    --       `if not ok2 then pcall(function() target:SetImage(node.image_id) end) end`
                    --     ⇒ ★★ **它用【专用方法 `SetImage`】** ✓
                    --   ★ 而我写的是 ★ `dst.imageSource = src` ＋ `dst.imageId = iid` ✗
                    --     ⇒ ★★ **属性赋值对图片【不通】** ✓
                    --   ★ 项目注释也写着 ✓（L936-937 ✓）：
                    --     「**运行时新建的客户端控件，在"根节点"上 `SetImage` 直接返回 false、
                    --       `imageId` 一直是 0**」✓
                    --   ⇒ 修法 ✓：★ **`SetImage(src, id)` ⇒ 不行试 `SetImage(id)` ⇒
                    --     最后才退回属性赋值** ✓（★ 与项目一致 ✓ 且留了退路 ✓）
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
                    wrote2 = wrote2 + 1
                  end
                end
              end
            end
          end
          if wrote2 > 0 and (self._row_log2 or 0) < 8 and print then
            self._row_log2 = (self._row_log2 or 0) + 1
            print("[murdoku] ★ 单射【末次】生效：`row." .. tostring(lv_no) .. "." .. tostring(pos)
              .. "` ⇒ 覆盖 " .. tostring(wrote2) .. " 个槽位 ✓（★ 你配的最终生效 ✓）")
          end
        end
      end
    end
  end
  self:_grid_bind_item_click(adapter, grid, item)
      self._grid_bind_n = (self._grid_bind_n or 0) + 1
      if self._grid_bind_n == 1 then print("[murdoku] ★ 诊断GRID：正在给列表项绑点击（第 1 个）") end
end

-- 给列表项挂点击。★ 列表项是**复用**的：同一个控件会先后代表不同线索 ⇒
--   回调里**不能**捕获 index，必须用 `GetItemIndex` 现查（见 `_on_grid_item_click`）。
--   重复挂监听会一次点击触发多遍 ⇒ 用一个**弱键表**按控件身份去重（控件回收后自动释放）。
function Controller:_grid_bind_item_click(adapter, grid, item)
  if item == nil or item.AddCursorEventListener == nil then
    if self._grid_bind_n == nil then
      self._grid_bind_n = 0
      local nm2 = "?"
      pcall(function() nm2 = tostring(item.name) end)
      print("[murdoku] ★ 诊断GRID：列表项【不支持光标事件】⇒ 点击绑不上！item=" .. nm2 .. "（AddCursorEventListener=" .. tostring(item ~= nil and item.AddCursorEventListener ~= nil) .. "）")
    end
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

-- 点了某一条列表项 → 聚焦这条线索。
function Controller:_on_grid_item_click(adapter, grid, item)
  -- ★ 2026-10-07 **抢点击定位读数**（★ 一次定案 ✓ 最多 12 行 ✓）
  --   ★ 要分清三件事 ✓：
  --     ① ★ **回调有没有进来**（★ 进来 ⇒ 引擎把点击给了卡片 ✓ 没进来 ⇒ 被别的东西吃掉 ✗）
  --     ② ★ **该卡是不是"已放置"**（★ `gray` 是否可见 ✓）—— 你说的现象**只在放置过的卡上** ✓
  --     ③ ★ 读回 `gray` 的 `raycastTarget` / 可见性 ✓ ⇒ 看"关射线"到底生效没有 ✓
  if (self._clk_log or 0) < 12 then
    self._clk_log = (self._clk_log or 0) + 1
    local _i, _rt, _vis = "?", "?", "?"
    -- ★ 2026-10-07 修读数：★ `GetItemIndex` 是**网格**的方法（★ 不是列表项自己的 ✓）
    --   ★ 真机证据 ✓：★ 上一版打出 `index=?` ✓ ⇒ ★ 我调错对象了 ✓
    pcall(function() _i = tostring(grid:GetItemIndex(item)) end)
    if _i == "?" then pcall(function() _i = tostring(item:GetItemIndex()) end) end
    local _g = nil
    pcall(function() _g = self:_grid_item_child_cached(item, nil, 0, "gray") end)
    if _g ~= nil then
      pcall(function() _rt = tostring(_g.raycastTarget) end)
      pcall(function() _vis = tostring(_g.visible) end)
    end
    print("[murdoku] ★ 抢点击诊断：回调进来了 ✓ 列表项index=" .. _i
      .. "  gray存在=" .. tostring(_g ~= nil) .. " gray可见=" .. _vis .. " gray射线=" .. _rt)
  end

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
  -- ★ 官方：「列表项索引以运行时传入和返回的 index 为准」⇒ **只能反查**。
  --   按兄弟序号取是错的：列表项会被复用，兄弟顺序不稳定（用户也专门点了这一条）。
  local idx = nil
  pcall(function() idx = grid:GetItemIndex(item) end)
    if not self._grid_idx_log then self._grid_idx_log = 0 end
    if self._grid_idx_log < 5 then
      self._grid_idx_log = self._grid_idx_log + 1
      print("[murdoku] ★ 诊断GRID：列表项被点到了 ✓ GetItemIndex=" .. tostring(idx))
    end
  if type(idx) ~= "number" then
    -- 反查失败 ⇒ 这一次点击**宁可丢掉**，也不要聚焦到错误的一条（聚焦错了会误导推理）
    self:_grid_log("noindex", "网格视窗：GetItemIndex 读不到索引 ⇒ 这一次点击忽略（不改焦点）")
    return
  end
  local pos = idx - (self._grid_base or 1) + 1
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
  local n = #((self.core:view() or {}).clues or {})
  if pos < 1 or pos > n then return end

  -- ★ 走**和老卡片完全同一条**输入通路：`adapter.on_input` 是 main.lua 接的
  --   （`controller:on_input(event)` + 立刻渲染）⇒ 点列表项和点 `clue.N` 的后续行为
  --   （焦点切换、CLUE_IN 特效、重绘）一模一样，不会出现"两套焦点逻辑"。
    -- ★★★★★ 2026-10-07 **网格选中视觉（只染聚焦那条）** ✗✓
  --   上一版两个错（用户实测：★"没有点击高亮，但描边更亮了"✓）：
  --     ① 给**未聚焦**的项也写了白色 ⇒ **整排描边变亮** ✗
  --     ② 染色写在**填充回调**里 ⇒ 而填充只在"数据变化/滚动"时跑 ⇒ **点击后不重填 ⇒ 高亮永不出现** ✗
  --   ⇒ 现在：★ **在点击处直接染** ✓ **只染聚焦那条** ✓ **换项/取消时恢复原色** ✓
  local function _bp_get(it, ix, px)
    local c2 = nil
    pcall(function() c2 = self:_grid_item_child_cached(it, ix, px, "backrop1") end)
    return c2
  end
  local turning_on = (self.focused_clue ~= pos)
  local prev_item, prev_idx, prev_pos = self._grid_focus_item, self._grid_focus_idx, self._grid_focus_pos
  if prev_item ~= nil then
    local pc = _bp_get(prev_item, prev_idx or 0, prev_pos or 0)
    if pc ~= nil then
      local oc = self._grid_focus_orig
      if oc ~= nil then pcall(function() pc.imageColor = oc end) end
    end
    self._grid_focus_item, self._grid_focus_orig = nil, nil
  end
  if turning_on then
    local c2 = _bp_get(item, idx, pos)
    if c2 ~= nil then
      local cur = nil
      pcall(function() cur = c2.imageColor end)
      self._grid_focus_orig = cur
      self._grid_focus_item, self._grid_focus_idx, self._grid_focus_pos = item, idx, pos
      pcall(function() c2.imageColor = 4294956107 end)   -- ★ 暖金（乘算着色）
    end
  end
  -- ★ 2026-10-07 一次性诊断：把该线索记录的【真实字段名】打出来（方案 A 取值失败 ⇒ 不猜了）
  if (self._diag_clue or 0) < 3 then
    self._diag_clue = (self._diag_clue or 0) + 1
    local ks, vs = {}, {}
    pcall(function()
      local v3 = self.core:view() or {}
      local c3 = (v3.clues or {})[pos]
      if c3 ~= nil then
        for k, v in pairs(c3) do
          ks[#ks + 1] = tostring(k)
          if type(v) ~= "table" then vs[#vs + 1] = tostring(k) .. "=" .. tostring(v) end
        end
      end
    end)
    print("[murdoku] ★ 诊断CLUE：pos=" .. tostring(pos) .. "  字段名=[" .. table.concat(ks, ",")
      .. "]  值(" .. table.concat(vs, " ") .. ")")
  end
  -- ★★★★★ 2026-10-07 **方案 A：点线索卡 = 高亮这条 + 选中卡上那个人** ✗✓（用户确认走 A ✓）
  --
  --   为什么必须有：真机日志「★ **点 (第1行 第2列) 没生效：先点一个头像　当前工具=place　已选=nil**」✓
  --     ⇒ ★ **`selected` 一直是 nil** ⇒ ★ **铅笔笔记 / 预放置 / 正式放置【三者全被拦在这一步】** ✓
  --   根因：★ 老卡片里头像 `face` 是**按钮**（`push({id="clue."..i..".face", kind="button"})` ✓）
  --     点它才发 `suspect` ✓ 而**网格模式下列表项点击只发 `focus_clue`** ✗ ⇒ ★ **选人的手势丢了** ✓
  --   ⇒ 这里补上：★ **点卡片即选中卡上那个人** ✓（★ 一步完成"高亮 + 选人"✓）
  --   ★ 取值**防御式**：线索记录里人物字段可能叫 `person`/`who_id`/`id`/`key` ✓
  --     再兜一层"从头像素材名 `portrait.X` 里取 X" ✓ 取不到就不动作（绝不误选）✓
  pcall(function()
    local v2 = self.core:view() or {}
    local cl = (v2.clues or {})[pos]
    if cl ~= nil then
      -- ★ 真字段名（真机探针实测 ✓）：★ `who` —— 值形如 `V` / `D` / `@thief`
      --   ⇒ `@` 开头的是【特殊角色】（如盗窃者），不是可选的"人"，跳过 ✓
      local pid = cl.who or cl.person or cl.who_id or cl.id
      if type(pid) == "string" and pid:sub(1, 1) == "@" then pid = nil end
      if pid == nil then
        local pn = cl.portrait or cl.face or cl.asset
        if pn ~= nil then pid = tostring(pn):gsub("^portrait%.", "") end
      end
      if pid ~= nil then
        local ev2 = { action = "suspect", id = pid }
        if type(self.adapter) == "table" and type(self.adapter.on_input) == "function" then
          self.adapter.on_input(ev2)
        else
          self:on_input(ev2)
        end
      end
    end
  end)
local ev = { action = "focus_clue", index = pos, phase = "click" }
  if adapter ~= nil and type(adapter.on_input) == "function" then
    adapter.on_input(ev)
  else
    self:on_input(ev)
  end
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

  local nodes = self:build_layout()

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
      if n.pos_runtime then
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
