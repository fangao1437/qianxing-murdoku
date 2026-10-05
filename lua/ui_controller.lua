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
  local ok, why = core:hold_cell(r, c)
  if ok then
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
  local ok, why = core:pre_place(r, c)
  if ok then
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
    self.pending = { action = "back" }
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
    if ok then self:fx("hex.hint", M.EFFECTS.SELECT) end

  elseif a == "reveal" then
    -- 直接揭示答案（照 murdoku 的 Reveal，用于教学/放弃）
    core:reset()
    for id, p in pairs(core.solution) do
      core:select_suspect(id)
      core:hold_cell(p.r, p.c)
    end
    self.toast = "已揭示答案"

  -- ★ 2026-10-02：提交现在**先要 ✓ 确认**（见上面 confirm_yes 分支）⇒ 这里只留"真正执行"。
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
      self.screen = nil              -- ★ 点卡片 = 离开选关、进入关卡
      self.opts.on_pick_level(event.id)
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
      self.screen = "select"
    end
    self.dirty = true

  elseif a == "shop" or a == "bag" then
    -- 占位：具体内容等美术资源齐全后再设计（用户原话）。
    -- 给一句明确反馈，免得玩家以为按钮坏了。
    self.toast = (a == "shop") and "商城：美术资源就绪后开放" or "背包：美术资源就绪后开放"
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

function Controller:tick(dt)
  self.now = (self.now or 0) + (dt or 0)
  self.core:set_elapsed((self.core.elapsed or 0) + (dt or 0))
  self:flush_pending_note()      -- 挂起的单击到点就落成笔记
  self.dirty = true
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
    PREFIX = { "cell.", "clue.", "hud.", "room.label.", "ruler", "tray.", "action.", "hex.", "hit.",
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
    if hide then nodes[i].visible = false end
  end
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
  push({ id = "hud.subtitle", kind = "text", parent = "topbar",
         rect = { x = L.title.x, y = L.title.y + 48, w = L.title.w + 320, h = 30 },
         text = tostring(vm.subtitle or "") .. announce_text, style = "subtitle",
         visible = (vm.subtitle ~= nil or announce_text ~= "") })

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
        --   imageType 不在存档里（比过 wall.left/wall.right，只差 id），只能运行时设。
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
    hex_bg("action.redo", sk_x + 55, sk_y[2] + 55, SK.size)
    hex_bg("action.hint", sk_x + 55, sk_y[3] + 55, SK.size)
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
  push({ id = "hud.moves", kind = "text", parent = "topbar",
         rect = { x = 1390, y = 30, w = 150, h = 46 },  -- ★ 同上（原 664）
         text = string.format("%d 步", vm.hud.moves), style = "stat" })

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
  push({ id = "clues", kind = "container", parent = "root", rect = rect_of(L.clues), style = "panel" })
  -- ★★★★★ 2026-10-05 **线索区大底板（`clues.bg`）** —— 用户在编辑器里摆的那张图，
  --   但它的名字不在规划里 ⇒ 脚本从没点亮它 ⇒ 真机日志（11:31）里它一直 `可见=false` ✗
  --   ⇒ 补一条规划节点（`kind = "container"`：只摆位置/显隐，**不设图不设色**，图与色归编辑器）。
  --   尺寸与容器同尺寸（画布 400×544）、挂在 `clues` 下、坐标相对父级 ⇒ (0,0) ✓
  push({ id = "clues.bg", kind = "container", parent = "clues",
         rect = { x = L.clues.x, y = L.clues.y, w = L.clues.w, h = L.clues.h } })
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
  local function split_by_name(txt)
    if type(vm.tray) ~= "table" then return nil, txt, nil, nil, nil end
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
      -- ★★★★★ 2026-10-05 **不再给 `pos_runtime`** —— 用户："编辑器里的位置本来就是对的，
      --   脚本摆位置是纯粹的无效操作，还会出错"。不带这个标记 ⇒ 走「编辑器几何优先」
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

    local who, pre, post, wid, wportrait = split_by_name(tostring(cl.text or ""))    local tx = L.clues.x + PAD + FACE + PAD      -- 文字起点：让开左边的头像
    local tw = L.clues.w - 16 - (FACE + PAD * 2) - BADGE_W - PAD
    if who ~= nil then
      -- 头像（左边）：复用 `portrait.*` 调色板，**不引入新素材**
      -- （子控件的 y 也跟着卡片走 ⇒ 同样要 `pos_runtime`，理由见上面那段的注释）
      push({ id = "clue." .. i .. ".face", kind = "button", parent = "clue." .. i,
             rect = { x = L.clues.x + CLUE_PAD + 16.8, y = y + 36, w = FACE, h = FACE },
             image = wportrait, style = "portrait", visible = inWin })
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
        parent = "board",
        rect = { x = gx + (c - 1) * (cell + gap), y = gy + (r - 1) * (cell + gap), w = cell, h = cell },
        style = style,
        text = cd.name or "",
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
        notes = cd.notes,
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
             text = string.format("用时 %s · %d 步 · 误指认 %d 次 · 位置 %d/%d",
                                  self:format_time(vm.hud.time), vm.hud.moves, vm.hud.failed_accusations, got, total),
             style = "muted" })
      btn("modal.again", "modal", { x = mx + 40, y = my + mh - 88, w = 180, h = 60 }, "重玩本关",
          { action = "restart" }, "stamp")
      btn("modal.share", "modal", { x = mx + 240, y = my + mh - 88, w = 180, h = 60 }, "分享棋局",
          { action = "share" }, "stamp")
      btn("modal.next", "modal", { x = mx + 440, y = my + mh - 88, w = 200, h = 60 }, "下一关",
          { action = "next_level" }, "stamp.primary")

    elseif modal.kind == "share" then
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
    local HIDE = {
      topbar = true, toolbar = true, left = true, board = true, right = true,
      toast = true, modal = true, intro = true,
      clues = true,
      ["action.back"] = true, ["action.redo"] = true, ["action.hint"] = true,
      ["action.undo"] = true, ["action.submit"] = true, ["action.reveal"] = true,
    }
    local HIDE_PREFIX = { "cell.", "clue.", "hud.", "room.label.", "ruler", "tray.", "action." }
    for i = 1, #nodes do
      local id = nodes[i].id
      local hide = HIDE[id] == true
      if not hide then
        for k = 1, #HIDE_PREFIX do
          if id:sub(1, #HIDE_PREFIX[k]) == HIDE_PREFIX[k] then hide = true break end
        end
      end
      if id == "home" then hide = (screen ~= "home") end
    if id == "select" then hide = (screen ~= "select") end
    if hide then nodes[i].visible = false end
    end
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
    local FULLSCREEN = { x = 0, y = 0, w = M.DESIGN.width, h = M.DESIGN.height }
    push({ id = "home", kind = "container", parent = "root", rect = FULLSCREEN,
           visible = (self.screen == "home"), pos_runtime = true })
    push({ id = "select", kind = "container", parent = "root", rect = FULLSCREEN,
           visible = (self.screen == "select"), pos_runtime = true })
    if self.screen == "home" then
      push({ id = "home.title", kind = "text", parent = "root", visible = true, text = M.HOME_TITLE,
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
-- 增量渲染
----------------------------------------------------------------------------

function Controller:render(adapter, force)
  local nodes = self:build_layout()

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
  if self._shown == nil then
    local all = self:layout_plan()
    for i = 1, #all do
      if not seen[all[i].id] then
        adapter:set_property(all[i].id, "visible", false)
      end
    end
    -- ★ 上面只能藏住"当前这一关自己的布局里没有的"控件。
    --   但编辑器是照**所有关卡的最大并集**建的，多出来的控件（cell.6.6 / clue.12 /
    --   tray.F …）界面层根本不知道它们存在，只能让适配层去控件树上扫。
    if adapter.hide_unlisted ~= nil then
      adapter:hide_unlisted(seen)
    end
  else
    for id in pairs(self._shown) do
      if not seen[id] then
        adapter:set_property(id, "visible", false)
      end
    end
  end
  self._shown = seen          -- 记住这一帧显示了什么，下一帧据此算差集

  for i = 1, #nodes do
    local n = nodes[i]
    if not self._created[n.id] then
      adapter:create_control(n)
      self._created[n.id] = true
      self._props[n.id] = {}
    end
    local last = self._props[n.id]
    for k, v in pairs(n) do
      if k ~= "id" and k ~= "rect" then
        if not same_value(last[k], v) then
          adapter:set_property(n.id, k, v)
          last[k] = v
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
      adapter:set_property(n.id, "rect", n.rect)
      last.__rect = { x = n.rect.x, y = n.rect.y, w = n.rect.w, h = n.rect.h }
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      adapter:destroy_control(id)
      self._created[id] = nil
      self._props[id] = nil
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    adapter:play_effect(e.target, e.kind, e)
  end
  self.effects = {}
  self.dirty = false
end

return M
