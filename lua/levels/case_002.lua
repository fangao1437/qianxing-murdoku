--[[----------------------------------------------------------------------------
  levels/case_002.lua —— 第 3 关：**空白占位棋盘（内容待设计）**

  ★★★ 2026-10-18 用户定：「被填入了错误内容的第三关，清理成没有布局的棋盘，
    或者按原来的第三关还原都行。」
  ⇒ 这里选**空白占位**：6×6、6 枚棋子 A B C D E V、**没有任何家具 / 障碍**，
    只有两间房和一扇门（结构校验必须要有"受害者区域有门相邻区域"，
    所以不能真的只有一间房）。
  ⇒ 内容源是 `row.3.*`（6 行）—— 现在**不配内容**，等正式设计。

  ⚠️ 本关**故意没有线索** ⇒ `tools/validate_levels.lua` 的"唯一解"一项会报"未测"，
     那是**内容还没设计**，不是判据失效 ✓（与 selftest_theft_5x5 / case_003 同一个口径）
----------------------------------------------------------------------------]]--

return {
  id = "case_002",
  name = "案件 002 · 待设计",
  subtitle = "（第三关内容待设计）",
  difficulty = "normal",

  size = { rows = 6, cols = 6 },

  rules = {
    one_per_row  = true,
    one_per_col  = true,
    one_per_room = false,
    place_all    = true,
    tie_policy   = "forbid",
  },

  -- 只切两间房：第 1-3 行 / 第 4-6 行；其余留空
  walls = {
    { "h", 3, 1 }, { "h", 3, 2 }, { "h", 3, 3 },
    { "h", 3, 4 }, { "h", 3, 5 }, { "h", 3, 6 },
  },
  doors = {
    { "h", 3, 3 },   -- 上下两间房之间唯一的一扇门
  },

  -- ★ 空白棋盘：没有家具、没有障碍
  objects = {},
  blocked = {},
  water   = {},

  suspects = {
    { id = "A", name = "嫌疑人 A", portrait = "portrait.A", gender = "male" },
    { id = "B", name = "嫌疑人 B", portrait = "portrait.B", gender = "female" },
    { id = "C", name = "嫌疑人 C", portrait = "portrait.C", gender = "male" },
    { id = "D", name = "嫌疑人 D", portrait = "portrait.D", gender = "male" },
    { id = "E", name = "嫌疑人 E", portrait = "portrait.E", gender = "female" },
    { id = "V", name = "受害者 V", portrait = "portrait.V", is_victim = true },
  },
  victim = { id = "V", name = "受害者 V" },

  -- 占位答案（正式设计时整体替换）
  roles = {
    thief = "A",
  },

  meta = {
    false_clue = nil,
    announce   = "unknown",
  },

  -- 每行每列各一人：主对角线
  solution = {
    A = { r = 1, c = 1 },
    B = { r = 2, c = 2 },
    C = { r = 3, c = 3 },
    D = { r = 4, c = 4 },
    E = { r = 5, c = 5 },
    V = { r = 6, c = 6 },
  },
}
