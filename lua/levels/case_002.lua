--[[----------------------------------------------------------------------------
  levels/case_002.lua —— 案件 002《双影》

  主题：6×6，6 枚棋子（4 名嫌疑人 + 1 名受害者 + 1 名同伙）。
  教学点：**受害者与他人同区（k≥2）→ 必然有且只有一个同伙**，
          而且同伙一定和盗窃者待在同一个区域。

  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_T = 第 1-4 行 × 第 1-4 列（16 格）        ← 盗窃者与同伙都藏在这里
    R_V = 第 5-6 列 × 第 1-6 行（12 格）        ← 受害者所在区域
    R_C = 第 5-6 行 × 第 1-4 列（8 格）         ← 另一条通往 R_V 的路（答案里是空的）

    墙： v,1..6,4（第 4 列与第 5 列之间）、h,4,1..4（第 4 行与第 5 行之间）
    门： v,2,4（R_T↔R_V）、v,5,4（R_C↔R_V）、h,4,1（R_T↔R_C）

    Adj(R_V) = {R_T, R_C} —— 两个候选区域，R3 才是真约束。

  ── 为什么这样摆（R3/R4 的自洽性）──────────────────────────────────────
    受害者 V 与随行记者 E 同在 R_V → k=2 → **必有同伙** ✔（R4）
    六枚棋子分布：R_T 四人（盗窃者 D + 同伙 C + 两名无辜 A/B）、R_V 两人、R_C 零人。
      inno(R_T) = 2
      inno(R_C) = 0        （R_C 空着 —— "那个区没人"本身就是有用的观察）
    → 唯一最大是 R_T，所以盗窃者与同伙必在 R_T ✔（R3）

  ── 每行每列恰好一人 ────────────────────────────────────────────────────
    答案：D(1,1) C(2,4) A(3,3) B(4,2) V(5,6) E(6,5)
          行 1..6 各一次、列 1..6 各一次。

  ★★★ 2026-10-11 **线索表已删** ✗✓（★ 用户原话 ✓）：
    「★ **原本那套为每关人物发位置和字母的逻辑直接删了** ✓
     ★ **关卡设计本来就要改** ✓ ★ **不用留着他了**」✓
  ⇒ ★★ 原来那套"报位置 ＋ 发字母"的线索**整段删掉** ✓
    ★ **`meta.false_clue` 一并作废** ✓（★ 它按序号指线索 ✓ 线索没了它就没意义 ✓）
  ⇒ ★★★ **本关现在【没有线索】** ✓ —— ★ **等新设计** ✓
    ★ 关卡本体（`walls`/`doors`/`objects`/`roles`/`solution`/`size`）**一个字没动** ✓✓
  ⚠️ ★ 已知后果 ✓（★ 不是 bug ✗）：★ `tools/validate_levels.lua` 的**唯一解**闸门
    会报「找到 3 个解」✓ —— ★ 那是**内容还没设计** ✓ ★ 不是逻辑坏了 ✓

----------------------------------------------------------------------------]]--

return {
  id = "case_002",
  name = "案件 002 · 双影",
  subtitle = "内室里留下了两个人的痕迹 —— 这一次，他身边还有别人。",
  difficulty = "normal",

  size = { rows = 6, cols = 6 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },

  -- 墙 = 区域边界
  walls = {
    { "v", 1, 4 }, { "v", 2, 4 }, { "v", 3, 4 },   -- R_T | R_V
    { "v", 4, 4 }, { "v", 5, 4 }, { "v", 6, 4 },   -- R_C | R_V
    { "h", 4, 1 }, { "h", 4, 2 }, { "h", 4, 3 }, { "h", 4, 4 },  -- R_T | R_C
  },

  -- 门径
  doors = {
    { "v", 2, 4 },   -- R_T ↔ R_V：(2,4) 与 (2,5)
    { "v", 5, 4 },   -- R_C ↔ R_V：(5,4) 与 (5,5)
    { "h", 4, 1 },   -- R_T ↔ R_C：(4,1) 与 (5,1)
  },

  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["书架"]   = { cells = { { r = 5, c = 1 }, { r = 6, c = 1 } }, occupiable = false, kind = "shelf"  },
    ["展示柜"] = { cells = { { r = 5, c = 4 } }, occupiable = false, kind = "case"   },
    ["地毯"]   = { cells = { { r = 6, c = 3 }, { r = 6, c = 4 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "夜班门卫", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "画廊助理", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "临时搬运工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "鉴定师", portrait = "portrait.D",     gender = "male" },
    { id = "E", name = "随行记者", portrait = "portrait.E",   gender = "female" },
    { id = "V", name = "馆长", portrait = "portrait.V",       is_victim = true },
  },

  victim = { id = "V", name = "馆长" },

  -- 角色归属：盗窃者 + 同伙（本案必有同伙，因为 k=2）
  roles = {
    thief      = "D",
    accomplice = "C",
  },

  meta = {
    false_clue = nil,   -- ★ 线索表已删 ⇒ 假话声明一并作废 ✓
    announce   = "one",
  },

  solution = {
    D = { r = 1, c = 1 },   -- R_T（盗窃者）
    C = { r = 2, c = 4 },   -- R_T（同伙，与盗窃者同区）
    A = { r = 3, c = 3 },   -- R_T
    B = { r = 4, c = 2 },   -- R_T
    V = { r = 5, c = 6 },   -- R_V（受害者）
    E = { r = 6, c = 5 },   -- R_V（与受害者同区 → k=2 → 必有同伙）
  },


  --[[ 设计备注：为什么不用 left_of / right_of / above / below
       这四种线索的判定是「**同一行**且列更小 / **同一列**且行更小」
       （见 murdoku_core.lua 的 ctx.is_left_of / ctx.is_above）。
       本工程开了 one_per_row + one_per_col，任意两人**不可能同行同列**，
       所以这四个线索在本作里**永远为假**。
       要表达"谁在谁左边"请用 col_offset / row_offset（它们不要求同行同列）。 ]]
}

