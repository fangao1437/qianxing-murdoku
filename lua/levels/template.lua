--[[----------------------------------------------------------------------------
  levels/template.lua —— 关卡模板（偷窃版规则 v0.3；复制这个文件改就是新关卡）

  流程：
    1. 复制成 levels/<你的关卡id>.lua
    2. 按 docs/规则规格-偷窃版.md 填字段
    3. 在 levels/init.lua 的 LIST 里登记一行
    4. 跑 lua tools/validate_levels.lua 自检（格式 / 结构 R3R4 / 假话 / 唯一解）

  ⚠️ 两个实测踩到的坑：
    · Lua 标识符只能是 ASCII —— 中文家具名必须写 ["书架"] = {...}，不能写 书架 = {...}
      （后者会报 unexpected symbol near '<\228>'）
    · 家具名/角色名这类"值"用普通字符串即可：object = "书架"

  字段速查（详细语义见 docs/规则规格-偷窃版.md、docs/关卡数据格式.md 第 12 节）：
    size      棋盘 N×N，N 必须等于棋子总数（含受害者）
    walls     区域边界（房间靠墙划分）
    doors     跨区域通道（靠它定义"区域相邻"）
    objects   家具；occupiable=false 的家具所在格不能站人
    roles     thief（必有 1 人）+ accomplice（0 或 1 人）
    meta      false_clue（哪条线索是假的）+ announce（是否告诉玩家）
    clues     线索；who / a / b 可写 @thief / @accomplice / @victim
----------------------------------------------------------------------------]]--

return {
  id = "your_level_id",
  name = "关卡名",
  subtitle = "副标题（可空）",
  difficulty = "normal",

  size = { rows = 5, cols = 5 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",   -- 相邻区域无辜人数并列：forbid（默认判非法）/ allow（特殊关卡）
  },

  -- 区域边界（墙）
  walls = {
    -- { "h", 3, 1 },   -- (3,1) 与 (4,1) 之间是墙
  },

  -- 跨区域门径（"区域相邻" = 有门直连、且不经过第三个区域）
  doors = {
    -- { "h", 3, 1 },   -- (3,1) 与 (4,1) 之间有门
  },

  -- 家具 / 物体
  objects = {
    -- ["书桌"] = { cells = { { r = 1, c = 5 } }, occupiable = false },   -- 不能站人
    -- ["地毯"] = { { r = 2, c = 2 }, { r = 2, c = 4 } },                 -- 不写就是可站
  },
  blocked = {},
  water   = {},

  -- 棋子：嫌疑人与受害者都要摆上棋盘
  suspects = {
    -- { id = "A", name = "管家", gender = "male" },
    -- { id = "V", name = "老宅主", is_victim = true },
  },

  victim = { id = "V", name = "老宅主" },

  -- 角色归属：盗窃者必有 1 人；不写 accomplice 表示本案没有同伙
  roles = {
    thief = "A",
    -- accomplice = "B",
  },

  -- 假话声明（至多一条；粒度 = 整条线索）
  meta = {
    -- false_clue = 7,      -- 第 7 条线索是假的；不写 = 本关全是真话
    announce = "unknown",   -- none | one | unknown（unknown = 不告诉玩家，需自行推断）
  },

  solution = {
    -- A = { r = 1, c = 1 },
    -- V = { r = 4, c = 1 },
  },

  clues = {
    -- { type = "at",     who = "A",            r = 1, c = 1 },
    -- { type = "in_row", who = "@thief",       r = 1 },        -- 盗窃者在第 1 行
    -- { type = "in_col", who = "@accomplice",  c = 5 },        -- 同伙在第 5 列
  },
}
