--[[----------------------------------------------------------------------------
  levels/case_001.lua —— 第 1 关：案件 001《夜盗·独行》（5×5，5 枚棋子）

  ★★★ 2026-10-18 **归位**：第 1 关就该是这套**真正的第一关内容** ✓
    （之前槽 1 被框架自检关占着，而这里是双影；现在换回来了）
  ⇒ 内容源 = `row.1.*`（5 枚棋子 ⇒ row.1.1 … row.1.5）✓
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
