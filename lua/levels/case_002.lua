--[[----------------------------------------------------------------------------
  levels/case_002.lua —— 案件 002《双影》

  主题：6×6，6 枚棋子（5 名嫌疑人 + 1 名受害者）。**本案没有同伙。**

  ── 本关教什么 ──────────────────────────────────────────────────────────
    ① 相邻定义：受害者 V 所在区域**只有一扇门**，所以它只与一个区域相邻。
       玩家必须先看清门，才能判断"盗窃者应该在哪一间"。
    ② 谎言：全部线索为真时**无解** ⇒ 一定有人说谎；
       逐条剔除后**只有 D 的那条**能留下自洽摆位 ⇒ 说谎者是 D。
    ③ 盗窃者判据（设计层，**尚未落进 core**）：
       **当盗窃者只剩一个可选位置时，他会说谎。**

  ── 空间结构（★ 四个区域）──────────────────────────────────────────────
    R1 = 第 1-3 行 × 第 1-4 列（12 格）
    R2 = 第 1-3 行 × 第 5-6 列 ＋ (4,6)（7 格）      ← 受害者 V 所在区域
    R3 = (4,1)(4,2)(4,3) (5,1)(5,2)(5,3) (6,1)..(6,4)（10 格）
    R4 = (4,4)(4,5) (5,4)(5,5)(5,6) (6,5)(6,6)（7 格）

    墙 = 区域边界：
      v,1,4 / v,2,4 / v,3,4    R1 | R2
      v,4,5                    R4 | R2（(4,5) 与 (4,6) 之间）
      h,3,1 .. h,3,5           R1 | (R3 ∪ R4)
      h,4,6                    R2 | R4（(4,6) 与 (5,6) 之间）
      v,4,3 / v,5,3            R3 | R4（第 4、5 行 第3列与第4列之间）
      v,6,4                    R3 | R4（(6,4) 与 (6,5) 之间）
    墙 = 区域内部的隔断（只做造型，不改变划分）：
      h,5,4                    R4 内部：(5,4) 与 (6,4) 之间

    门（★ 全场只有一扇）：
      v,2,4                    R1 ↔ R2 —— **受害者那间屋唯一的门**

    ⇒ Adj(R1) = {R2}　Adj(R2) = {R1}　Adj(R3) = {}　Adj(R4) = {}
      R3 与 R4 都没有门 ⇒ 它们与谁都不相邻（本关强调"相邻"就靠这个对比）。

  ── 家具（★ 桌子/植物/书架/雕塑【不能站人】，椅子/地毯【可以站人】）
    椅子 (1,1) (2,4)          occupiable = true
    地毯 (1,4) (3,3)(3,4) (5,1)(6,1)   occupiable = true
    桌子 (1,2)(1,3) (6,5)     occupiable = false
    植物 (3,2) (5,4)(6,4)     occupiable = false
    书架 (6,2)                occupiable = false
    雕塑 (1,6)                occupiable = false

  ── 线索（2026-10-17 定稿 v5）──────────────────────────────────────────
    ★ 卡序 = 棋子序 A,B,C,D,E,V（这一关说话人不变）：
        卡 1 a：画廊助理 在 桌子 旁边
        卡 2 b：有两人坐在椅子上
        卡 3 c：夜班门卫 在 书架 旁边
        卡 4 d：随行记者 在 夜班门卫 的上方（同一列）  ← ★ 本案唯一的假话
        卡 5 e：只有 随行记者 在 植物 旁边
        卡 6 v：我独自一人，且 临时搬运工 在我下方的不同区域中
    ★ 通用线索（不属于任何人的卡）：地毯上没有人
      ⇒ 走 `general_clues`，只参与求解/校验，**不占卡位**。
    ★ 顺序【必须】与卡序一致（`Core:clue_hint` 的入参就是卡号）。
    ★ `false_clue = 4`（d）＋ `announce = "unknown"`：
      ⇒ `allowed_false = 1`（求解允许一句假话），但**不告诉玩家**是哪一句。
----------------------------------------------------------------------------]]--

return {
  id = "case_002",
  name = "案件 002 · 双影",
  subtitle = "侧廊只留一个人的痕迹，大厅里却站着两位 —— 谁在说谎？",
  difficulty = "normal",

  size = { rows = 6, cols = 6 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },

  -- 墙 = 区域边界 ＋ 区域内造型隔断
  walls = {
    { "v", 1, 4 }, { "v", 2, 4 }, { "v", 3, 4 },   -- R1 | R2
    { "v", 4, 5 },                                 -- R4 | R2（(4,5) 与 (4,6) 之间）
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 }, { "h", 3, 4 }, { "h", 3, 5 },  -- R1 | R3∪R4
    { "h", 4, 6 },                                 -- R2 | R4
    { "v", 4, 3 }, { "v", 5, 3 },                  -- R3 | R4
    { "v", 6, 4 },                                 -- R3 | R4
    { "h", 5, 4 },                                 -- R4 内部造型（(5,4) 与 (6,4) 之间）
  },

  -- 门径 = 跨区域通道（与墙同粒度；不改变区域划分）
  doors = {
    { "v", 2, 4 },   -- R1 ↔ R2：★ 受害者所在区域唯一的门
    -- ★ 2026-10-18 用户指定补两扇（原话：「给第二关第一列的三四行之间的那堵墙、
    --   和第四行三四列之间的那堵墙加上门」）：
    { "h", 3, 1 },   -- R1 ↔ R3：(3,1) 与 (4,1) 之间
    { "v", 4, 3 },   -- R3 ↔ R4：(4,3) 与 (4,4) 之间
  },

  objects = {
    -- `kind` = 家具图标的素材键（界面层翻成 `obj.<kind>`，见 ui_controller.object_key_of）
    ["椅子"] = { cells = { { r = 1, c = 1 }, { r = 2, c = 4 } }, occupiable = true,  kind = "chair"  },
    ["地毯"] = { cells = { { r = 1, c = 4 }, { r = 3, c = 3 }, { r = 3, c = 4 },
                           { r = 5, c = 1 }, { r = 6, c = 1 } }, occupiable = true,  kind = "carpet" },
    ["桌子"] = { cells = { { r = 1, c = 2 }, { r = 1, c = 3 }, { r = 6, c = 5 } },
                 occupiable = false, kind = "table" },
    ["植物"] = { cells = { { r = 3, c = 2 }, { r = 5, c = 4 }, { r = 6, c = 4 } },
                 occupiable = false, kind = "plant" },
    ["书架"] = { cells = { { r = 6, c = 2 } }, occupiable = false, kind = "shelf" },
    ["雕塑"] = { cells = { { r = 1, c = 6 } }, occupiable = false, kind = "statue" },
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

  -- 角色归属：只有盗窃者。★ 本案不写 accomplice ⇒ 没有同伙
  roles = {
    thief = "D",
  },

  -- 线索：**按卡序**（卡 i ↔ 线索 i ↔ 第 i 枚棋子）
  clues = {
    { type = "beside_object", who = "B", object = "桌子" },                  -- a
    { type = "n_on_object",   object = "椅子", n = 2 },                      -- b
    { type = "beside_object", who = "A", object = "书架" },                  -- c
    { type = "above",         a = "E", b = "A" },                            -- d（唯一假话）
    { type = "only_beside",   who = "E", object = "植物" },                  -- e
    { type = "alone_and_below_in_other_room", who = "V", a = "C", b = "V" }, -- v
  },

  -- 通用线索：不是任何人的卡（设计图里那格"通用线索"）
  general_clues = {
    { type = "nobody_on_object", object = "地毯" },
  },

  -- 有没有假话不直接告诉玩家 —— `announce = "unknown"`
  meta = {
    false_clue = 4,
    announce   = "unknown",
  },

  solution = {
    B = { r = 1, c = 1 },   -- R1（椅子）
    D = { r = 2, c = 4 },   -- R1（椅子）★ 盗窃者
    V = { r = 3, c = 6 },   -- R2（受害者，独处一区）
    C = { r = 4, c = 5 },   -- R4
    A = { r = 5, c = 2 },   -- R3
    E = { r = 6, c = 3 },   -- R3
  },

  --[[ 设计备注：为什么不用 left_of / right_of / above / below 当常规线索
       这四种判定是「**同一行**且列更小 / **同一列**且行更小」
       （见 murdoku_core.lua 的 ctx.is_left_of / ctx.is_above）。
       本工程开了 one_per_row + one_per_col，任意两人**不可能同行同列**，
       所以这四个线索在本作里**永远为假**。
       d 的那句「e 在 a 的上方」正是利用这一点：它恒假，所以它是天然的假话候选；
       但玩家**不能靠这一点**直接排除它（其它线索同样可能假），
       要靠"逐条剔除 + 只剩一个可选位置"两步才能锁定。 ]]
}
