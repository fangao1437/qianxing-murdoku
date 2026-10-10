--[[----------------------------------------------------------------------------
  levels/case_003.lua —— 案件 003《第三方》

  主题：7×7，7 枚棋子（5 名嫌疑人 + 1 名受害者 + 1 名同伙）。**目前最大的一关**，
  也是第一关用来自证"棋盘是自适应的"（格子边长 = 可用边长 ÷ 7 ≈ 97px，编辑器不用重摆）。

  教学点：把前面两条合起来用 ——
    · k=3（受害者身边有两个人）→ **必有同伙**（R4）
  ★★★ 2026-10-11 **线索表已删** ✗✓（★ 用户原话 ✓）：
    「★ **原本那套为每关人物发位置和字母的逻辑直接删了** ✓
     ★ **关卡设计本来就要改** ✓ ★ **不用留着他了**」✓
  ⇒ ★★ 原来那套"报位置 ＋ 发字母"的线索**整段删掉** ✓
    ★ **`meta.false_clue` 一并作废** ✓（★ 它按序号指线索 ✓ 线索没了它就没意义 ✓）
  ⇒ ★★★ **本关现在【没有线索】** ✓ —— ★ **等新设计** ✓
    ★ 关卡本体（`walls`/`doors`/`objects`/`roles`/`solution`/`size`）**一个字没动** ✓✓
  ⚠️ ★ 已知后果 ✓（★ 不是 bug ✗）：★ `tools/validate_levels.lua` 的**唯一解**闸门
    会报「找到 3 个解」✓ —— ★ 那是**内容还没设计** ✓ ★ 不是逻辑坏了 ✓


  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_T = 第 1-4 行 × 第 1-4 列（16 格，容量 min(4,4)=4）
    R_V = 第 5-7 列 × 第 1-7 行（21 格，容量 min(7,3)=3）  ← 受害者所在区域
    R_C = 第 5-7 行 × 第 1-4 列（12 格，容量 min(3,4)=3）  ← 答案里是空的

    墙： v,1..7,4（第 4 列与第 5 列之间）、h,4,1..4（第 4 行与第 5 行之间）
    门： v,2,4（R_T↔R_V）、v,5,4（R_C↔R_V）、h,4,1（R_T↔R_C）

    Adj(R_V) = {R_T, R_C} —— 两个候选区域，R3 才是真约束。

  ── 计数验算（见 docs/关卡设计手册.md 第二节）────────────────────────────
    无辜总数 = 7 − 1(受害者) − 1(盗窃者) − 1(同伙) = 4
    a(在 R_V) + b(在 R_T) + c(在 R_C) = 4，要求 a ≥ 1 且 b > c
    取 a=2、b=2、c=0：
      R_V：受害者 + 2 名无辜 = 3 人（容量 3，正好放满）
      R_T：盗窃者 + 同伙 + 2 名无辜 = 4 人（容量 4，正好放满）
      R_C：0 人
    → inno(R_T)=2 > inno(R_C)=0，唯一最大 ✔（R3）

  ── 行列 ────────────────────────────────────────────────────────────────
    答案：D(1,1) C(2,4) A(3,2) B(4,3) V(5,6) E(6,5) F(7,7)
          行 1..7、列 1..7 各一次。

----------------------------------------------------------------------------]]--

return {
  id = "case_003",
  name = "案件 003 · 第三方",
  subtitle = "内室里挤了三个人 —— 谁是被害者，谁只是恰好路过？",
  difficulty = "hard",

  size = { rows = 7, cols = 7 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },

  -- 墙 = 区域边界
  walls = {
    { "v", 1, 4 }, { "v", 2, 4 }, { "v", 3, 4 }, { "v", 4, 4 },   -- R_T | R_V
    { "v", 5, 4 }, { "v", 6, 4 }, { "v", 7, 4 },                  -- R_C | R_V
    { "h", 4, 1 }, { "h", 4, 2 }, { "h", 4, 3 }, { "h", 4, 4 },   -- R_T | R_C
  },

  -- 门径
  doors = {
    { "v", 2, 4 },   -- R_T ↔ R_V：(2,4) 与 (2,5)
    { "v", 5, 4 },   -- R_C ↔ R_V：(5,4) 与 (5,5)
    { "h", 4, 1 },   -- R_T ↔ R_C：(4,1) 与 (5,1)
  },

  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["书架"]   = { cells = { { r = 6, c = 1 }, { r = 7, c = 1 } }, occupiable = false, kind = "shelf"  },
    ["展示柜"] = { cells = { { r = 5, c = 4 } }, occupiable = false, kind = "case"   },
    ["地毯"]   = { cells = { { r = 6, c = 3 }, { r = 7, c = 3 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "值夜保安", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "布展助理", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "外聘搬运工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "首席鉴定师", portrait = "portrait.D", gender = "male" },
    { id = "E", name = "跟拍记者", portrait = "portrait.E",   gender = "female" },
    -- F 的图已由用户补上（portrait.F / id=112011）
    { id = "F", name = "赞助人", portrait = "portrait.F",     gender = "male" },
    { id = "V", name = "老馆员", portrait = "portrait.V",     is_victim = true },
  },

  victim = { id = "V", name = "老馆员" },

  roles = {
    thief      = "D",
    accomplice = "C",
  },

  -- 不告诉玩家本关有没有假话 —— 让他自己从矛盾里推
  meta = {
    false_clue = nil,   -- ★ 线索表已删 ⇒ 假话声明一并作废 ✓
    announce   = "unknown",
  },

  solution = {
    D = { r = 1, c = 1 },   -- R_T（盗窃者）
    C = { r = 2, c = 4 },   -- R_T（同伙）
    A = { r = 3, c = 2 },   -- R_T
    B = { r = 4, c = 3 },   -- R_T
    V = { r = 5, c = 6 },   -- R_V（受害者）
    E = { r = 6, c = 5 },   -- R_V
    F = { r = 7, c = 7 },   -- R_V
  },


  --[[ 设计备注：为什么不用 left_of / right_of / above / below
       这四种要求"同一行/同一列"才能成立（见 murdoku_core.lua 的 ctx.is_left_of /
       is_above），而本作开了 one_per_row + one_per_col，所以它们**永远为假**。
       要表达相对位置用 col_offset / row_offset。 ]]
}
