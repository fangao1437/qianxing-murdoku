-- ★★ 2026-10-18 **测试夹具：冻结的旧关卡内容**（从提交 e0531ef 取出，逐字节照抄）
--   为什么冻结：第 2 关已经换成真正的 6×6 内容 ⇒
--   那些「测特性」的套件（clue_hint / input_logic / simple_level）
--   不该跟着**已交付内容**一起漂 ✓
--   ★ 只给测试用，**不要**注册进 levels/init.lua ✗
--[[----------------------------------------------------------------------------
  levels/case_001.lua —— 案件 001《夜盗·独行》

  主题：深夜盗窃案。5×5，5 枚棋子（4 名嫌疑人 + 1 名受害者）。
  教学点：**受害者独处一区（k=1）→ 本案没有同伙**，盗窃者单独作案。

  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_A = 第 1-3 行 × 第 1-3 列（9 格）            ← 盗窃者藏在这里
    R_B = 右侧 L 形：(1,4)(1,5)(2,4)(2,5)(3,4)(3,5)(4,5)(5,5)（8 格）
                                                    ← 受害者所在区域
    R_C = 第 4-5 行 × 第 1-4 列（8 格）

    墙： v,1..3,3（R_A|R_B）、h,3,1..3（R_A|R_C）、h,3,4（R_B|R_C）、
         v,4,4 与 v,5,4（R_C|R_B）
    门： v,2,3（R_A↔R_B）、h,3,2（R_A↔R_C）、h,3,4（R_B↔R_C）

    所以 Adj(R_B) = {R_A, R_C} —— **两个**候选区域，R3 才是真约束。

  ── 为什么这样摆（R3 的自洽性）──────────────────────────────────────────
    受害者 V 在 (4,5)，R_B 内只有它一人 → k=1 → 没有同伙。
    四名嫌疑人分布：R_A 三人（含盗窃者）、R_C 一人。
      inno(R_A) = 2（除盗窃者外的两人）
      inno(R_C) = 1
    → 唯一最大是 R_A，所以盗窃者必在 R_A ✔（R3）

  ── 每行每列恰好一人 ────────────────────────────────────────────────────
    列：R_A 占 1/2/3，R_C 占 4，受害者占 5 → 行 1..5 各一人。

  ── 家具（2026-10-17 第一关定稿 v2）────────────────────────────────────
    桌子 (1,1)(2,1)                     occupiable = false
    植物 (1,2)(5,1)(5,3)                occupiable = false
    地毯 (3,1)(3,2)(2,4)(2,5)           occupiable = true
    椅子 (4,2)(5,4)                     occupiable = true

  ── 线索（2026-10-17 定稿）──────────────────────────────────────────────
    ★ 卡序 = 棋子序 A,B,C,D,V；**说话人 ≠ 线索主体**（按用户给的置换）：
        卡 1 A 说「收藏家 在第 5 列」        ← 原 v 的线索
        卡 2 B 说「旧识古董商 在 植物 旁边」  ← 原 d
        卡 3 C 说「只有 值班保安 站在 地毯 上」← 原 a
        卡 4 D 说「夜班清洁工 站在 椅子 上」  ← 原 c
        卡 5 V 说「前台姑娘 在 桌子 旁边」    ← 原 b
    ★ 推理只依赖「有哪些事实」，与谁说无关 ⇒ 摆位/唯一性不受影响。
    ★ 顺序【必须】与卡序一致：界面用 `focused_clue`（= 第几张卡）去取
      `Core:clue_hint`（= 第几条线索）⇒ 错一位就会亮错格子。
    证据：`lua verify_case001.lua`（设计期，2 个摆位 → 模糊规则 → 唯一解）
          `lua tools/validate_levels.lua` 会对本关报「2 个解 ✓ 不是 bug」——
          因为**模糊规则还没有落进 `core:solve`**（见 docs/回执-线索卡位置提示-2026-10-17.md）
----------------------------------------------------------------------------]]--

return {
  id = "case_001",
  name = "案件 001 · 夜盗独行",
  subtitle = "保险库内室只留下一个人的痕迹 —— 是独自作案，还是有人替他望风？",
  difficulty = "easy",

  size = { rows = 5, cols = 5 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",   -- 相邻区域无辜人数不允许并列
  },

  -- 墙 = 区域边界
  walls = {
    { "v", 1, 3 }, { "v", 2, 3 }, { "v", 3, 3 },   -- R_A | R_B
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 },   -- R_A | R_C
    { "h", 3, 4 },                                 -- R_B | R_C
    { "v", 4, 4 }, { "v", 5, 4 },                  -- R_C | R_B
  },

  -- 门径 = 跨区域通道（与墙同粒度；不改变区域划分）
  doors = {
    { "v", 2, 3 },   -- R_A ↔ R_B：(2,3) 与 (2,4)
    { "h", 3, 2 },   -- R_A ↔ R_C：(3,2) 与 (4,2)
    { "h", 3, 4 },   -- R_B ↔ R_C：(3,4) 与 (4,4)
  },

  -- ⚠️ Lua 标识符只能是 ASCII，中文家具名必须写成 ["名"] = {...}
  -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
  objects = {
    ["桌子"] = { cells = { { r = 1, c = 1 }, { r = 2, c = 1 } },
                 occupiable = false, kind = "table"  },
    ["植物"] = { cells = { { r = 1, c = 2 }, { r = 5, c = 1 }, { r = 5, c = 3 } },
                 occupiable = false, kind = "plant"  },
    ["地毯"] = { cells = { { r = 3, c = 1 }, { r = 3, c = 2 }, { r = 2, c = 4 }, { r = 2, c = 5 } },
                 occupiable = true,  kind = "carpet" },
    ["椅子"] = { cells = { { r = 4, c = 2 }, { r = 5, c = 4 } },
                 occupiable = true,  kind = "chair"  },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "值班保安", portrait = "portrait.A",   gender = "male" },
    { id = "B", name = "前台姑娘", portrait = "portrait.B",   gender = "female" },
    { id = "C", name = "夜班清洁工", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "旧识古董商", portrait = "portrait.D", gender = "male" },
    { id = "V", name = "收藏家", portrait = "portrait.V",     is_victim = true },
  },

  victim = { id = "V", name = "收藏家" },

  -- 答案的一半：角色归属（不写 accomplice = 本案没有同伙）
  roles = {
    thief = "D",
  },

  -- 线索：**按卡序**（卡 i ↔ 线索 i ↔ 第 i 枚棋子）
  clues = {
    { type = "in_col",         who = "V", c = 5 },                -- 卡 1（A 说）：收藏家 在第 5 列
    { type = "beside_object",  who = "D", object = "植物" },       -- 卡 2（B 说）：旧识古董商 在 植物 旁边
    { type = "only_on_object", who = "A", object = "地毯" },       -- 卡 3（C 说）：只有 值班保安 站在 地毯 上
    { type = "on_object",      who = "C", object = "椅子" },       -- 卡 4（D 说）：夜班清洁工 站在 椅子 上
    { type = "beside_object",  who = "B", object = "桌子" },       -- 卡 5（V 说）：前台姑娘 在 桌子 旁边
  },

  -- 至多一句假话：本关五句全部为真（announce = "none" ⇒ 界面显示「线索全部为真」）
  meta = {
    false_clue = nil,
    announce   = "none",
  },

  solution = {
    D = { r = 1, c = 3 },   -- R_A（盗窃者）
    A = { r = 3, c = 1 },   -- R_A（地毯）
    B = { r = 2, c = 2 },   -- R_A
    C = { r = 5, c = 4 },   -- R_C（椅子）
    V = { r = 4, c = 5 },   -- R_B（受害者，独处一区）
  },

}
