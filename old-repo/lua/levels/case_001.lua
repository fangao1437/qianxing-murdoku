--[[----------------------------------------------------------------------------
  levels/case_001.lua —— 案件 001《夜盗·独行》

  主题：深夜盗窃案。5×5，5 枚棋子（4 名嫌疑人 + 1 名受害者）。
  教学点：**受害者独处一区（k=1）→ 本案没有同伙**，盗窃者单独作案。
          玩家必须自己推断出"没有同伙"，而不是被直接告知。

  ── 空间结构（三个区域）────────────────────────────────────────────────
    R_A = 第 1-3 行 × 第 1-3 列（9 格）            ← 盗窃者藏在这里
    R_B = 右侧 L 形：(1,4)(1,5)(2,4)(2,5)(3,4)(3,5)(4,5)(5,5)（8 格）
                                                    ← 受害者所在区域
    R_C = 第 4-5 行 × 第 1-4 列（8 格）

    墙： v,1..3,3（R_A|R_B）、h,3,1..3（R_A|R_C）、h,3,4（R_B|R_C）、
         v,4,4 与 v,5,4（R_C|R_B）
    门： v,2,3（R_A↔R_B）、h,3,2（R_A↔R_C）、h,3,4（R_B↔R_C）

    所以 Adj(R_B) = {R_A, R_C} —— **两个**候选区域，R3 才是真约束。

  ── 为什么这样摆（R3/R4 的自洽性）──────────────────────────────────────
    受害者 V 在 (5,5)，R_B 内只有它一人 → k=1 → 同伙可有可无。
    四名嫌疑人分布：R_A 三人（含盗窃者）、R_C 一人。
      inno(R_A) = 2（除盗窃者外的两人）
      inno(R_C) = 1
    → 唯一最大是 R_A，所以盗窃者必在 R_A  ✔（R3）
    → 若硬说有同伙：同伙在 R_A 会让 inno 变成 1，与 R_C 并列（tie_policy=forbid 直接非法）；
      同伙在 R_C 又违反"同伙与盗窃者同区"。**结构本身就排除了同伙** ✔（R4）

  ── 每行每列恰好一人 ────────────────────────────────────────────────────
    列：R_A 占 1/2/3，R_C 占 4，受害者占 5 → 行 1..5 各一人。

  线索设计（8 条，第 8 条是那句假话）：
    · 全开线索指向 @thief（角色别名）→ 身份靠推理而不是靠报名字
    · 第 8 条故意说错的列，玩家要么把它当假话，要么就得推翻别的线索
  本关只用了 8 条，也不是由 find_clues.lua 生成的（那个工具是暴力搜索，很慢，
  留给"怎么都想不出来"的时候当兜底用）。
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
  objects = {
    -- ★ 2026-09-30：物件多了个**可选**的 `kind` —— **家具图标的素材键**。
    --   界面层会把它翻成 `obj.shelf` / `obj.case` / `obj.carpet`，
    --   去 `assets` 调色板里查图（见 `ui_controller.object_key_of`）。
    --   不写 kind 也能跑（退回中文名 `obj.书架`），只是素材名不好管理。
    --   等家具素材配好，在 assets 里放 obj.shelf / obj.case / obj.carpet 即可显示。
    ["书架"]   = { cells = { { r = 5, c = 1 } }, occupiable = false, kind = "shelf"  },
    ["展示柜"] = { cells = { { r = 5, c = 3 } }, occupiable = false, kind = "case"   },
    ["地毯"]   = { cells = { { r = 4, c = 2 } }, occupiable = true,  kind = "carpet" },
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

  -- 至多一句假话；announce = "unknown" → 不告诉玩家本关有没有假话，让他自己推
  meta = {
    false_clue = 8,
    announce   = "unknown",
  },

  solution = {
    D = { r = 1, c = 3 },   -- R_A（盗窃者）
    A = { r = 3, c = 1 },   -- R_A
    B = { r = 2, c = 2 },   -- R_A
    C = { r = 5, c = 4 },   -- R_C
    V = { r = 4, c = 5 },   -- R_B（受害者，独处一区）
  },

  clues = {
    { type = "at",         who = "V",       r = 4, c = 5 },   -- 受害者就在保险库内室
    { type = "in_col",     who = "@thief",  c = 3 },          -- 盗窃者在第 3 列
    { type = "in_row",     who = "@thief",  r = 1 },          -- 盗窃者在第 1 行
    { type = "in_row",     who = "C",       r = 5 },          -- 清洁工在第 5 行
    { type = "in_col",     who = "B",       c = 2 },          -- 前台姑娘在第 2 列
    { type = "same_room",  a = "A", b = "B" },                -- 保安与前台在同一区
    { type = "in_row",     who = "A",       r = 3 },          -- 保安在第 3 行
    { type = "in_col",     who = "A",       c = 4 },          -- ★ 第 8 条：假话（保安实际在第 1 列）
  },
}
