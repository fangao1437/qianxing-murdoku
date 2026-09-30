--[[----------------------------------------------------------------------------
  levels/demo_selftest.lua —— 框架自检样例（偷窃版规则，不是关卡内容）

  这是一个**完全合法**的最小局，用来验证 v0.3 引擎的每一条新规则：
    · 5×5，5 枚棋子（4 名嫌疑人 + 1 名受害者，受害者也要摆）
    · 三个区域：R_A(第1-3行)、R_B(第4-5行左3列)、R_C(第4-5行右2列)
    · 门径：R_A↔R_B、R_B↔R_C（所以受害者所在区域 R_B 的相邻区域 = {R_A, R_C}）
    · 受害者 V 与 A 同在 R_B → k=2 → 必有同伙
    · 盗窃者 D 与同伙 C 都在 R_A；R_A 无辜人数 1 > R_C 的 0
      → 满足"挑无辜人数最多的相邻区域"
    · 线索共 7 条，第 7 条是**声明好的那句假话**

  你设计正式关卡时把这个文件删掉即可。
----------------------------------------------------------------------------]]--

return {
  id = "selftest_theft_5x5",
  name = "框架自检样例（偷窃版）",
  subtitle = "仅用于验证引擎与界面绑定",
  difficulty = "selftest",

  size = { rows = 5, cols = 5 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",   -- 相邻区域无辜人数不允许并列；特殊关卡可写 "allow"
  },

  -- 墙 = 区域边界
  walls = {
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 },   -- R_A | R_B
    { "h", 3, 4 }, { "h", 3, 5 },                  -- R_A | R_C
    { "v", 4, 3 }, { "v", 5, 3 },                  -- R_B | R_C
  },

  -- 门径 = 跨区域的可达通道（同样开在格边上；不改变区域划分）
  doors = {
    { "h", 3, 1 },   -- R_A ↔ R_B： (3,1) 与 (4,1) 之间
    { "v", 4, 3 },   -- R_B ↔ R_C： (4,3) 与 (4,4) 之间
  },

  -- ⚠️ Lua 的标识符只能是 ASCII，所以中文家具名必须写成 ["名"] = {...} 这种字符串键
  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["书桌"] = { cells = { { r = 1, c = 5 } }, occupiable = false, kind = "desk"   },
    ["地毯"] = { cells = { { r = 2, c = 1 }, { r = 2, c = 2 } }, occupiable = true,  kind = "carpet" },
  },
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "管家", portrait = "portrait.A" },
    { id = "B", name = "医生", portrait = "portrait.B" },
    { id = "C", name = "歌女", portrait = "portrait.C" },
    { id = "D", name = "伯爵", portrait = "portrait.D" },
    { id = "V", name = "老宅主", portrait = "portrait.V", is_victim = true },
  },

  victim = { id = "V", name = "老宅主" },

  -- 角色归属（答案的一部分）
  roles = {
    thief = "D",
    accomplice = "C",     -- 不写 = 本案没有同伙
  },

  -- 线索里至多一句假话；这里声明是第 7 条
  meta = {
    false_clue = 7,
    announce   = "one",   -- none | one | unknown（unknown = 不告诉玩家）
  },

  solution = {
    A = { r = 5, c = 3 },   -- 与受害者同区（R_B）
    B = { r = 3, c = 2 },   -- R_A
    C = { r = 2, c = 5 },   -- R_A（同伙）
    D = { r = 1, c = 4 },   -- R_A（盗窃者）
    V = { r = 4, c = 1 },   -- R_B（受害者）
  },

  clues = {
    { type = "at",     who = "B", r = 3, c = 2 },        -- 真
    { type = "at",     who = "A", r = 5, c = 3 },        -- 真
    { type = "at",     who = "V", r = 4, c = 1 },        -- 真
    { type = "at",     who = "D", r = 1, c = 4 },        -- 真
    { type = "in_row", who = "@thief", r = 1 },          -- 真（角色别名：盗窃者在第 1 行）
    { type = "in_col", who = "@accomplice", c = 5 },     -- 真（同伙在第 5 列）
    { type = "in_col", who = "B", c = 1 },               -- ★ 第 7 条：假话（B 实际在第 2 列）
  },
}
