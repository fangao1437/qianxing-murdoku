--[[----------------------------------------------------------------------------
  tests/_wip/tree_ref.lua —— ★★★ 存档真实控件树的【参考边表】（**自动生成，不要手改**）

  ★ 生成命令 ✓：node tools/gil/gen_tree_ref.mjs [存档.gil]
  ★ 来源存档 ✓：347.gil（★ 这是"真值" ✓）
  ★ 内容 ✓：每一条"父名 → 子名"的边 ＋ 它在存档里出现几次 ✓
  ★ 用途 ✓：探针搭完自己的树之后调 `tree_ref.check(root)` ⇒
    · 用到参考里**没有**的边 ⇒ **红**（造了假控件 ✓ 例如 `content/ruler.c.1` ✓）
    · 参考里有、这一趟没用到 ⇒ **不算错** ✓（探针只搭它要量的那部分 ✓）

  ★★★ 为什么必须有这个文件 ✗✓（★ 本项目规矩第 ④ 条 ✓）：
    2026-10-13 审计证明：手搭假树**漏了 8 个真实边控件** ⇒
    凭空造出 840 笔 `GetChild`/render 并**全记在 v192 头上** ⇒
    量出"972 → 132（−86%）"这条**不存在的战果** ✗✗
    ⇒ ★「探针包了产线那棵树」≠「那棵树是真的」✓ ⇒ 现在改成**自动对账** ✓
----------------------------------------------------------------------------]]--

local M = {}

-- ★ 参考边：{ 父名, 子名, 存档里出现次数 }
M.edges = {
  { "(根)", "111", 2 },
  { "(根)", "cell.1.1", 2 },
  { "(根)", "clue", 2 },
  { "(根)", "face", 2 },
  { "(根)", "face2", 2 },
  { "(根)", "face3", 2 },
  { "(根)", "face4", 2 },
  { "(根)", "face5", 2 },
  { "(根)", "face6", 2 },
  { "(根)", "face7", 2 },
  { "(根)", "face8", 2 },
  { "(根)", "face9", 2 },
  { "(根)", "hex", 2 },
  { "(根)", "letterA", 2 },
  { "(根)", "letterB", 2 },
  { "(根)", "letterC", 2 },
  { "(根)", "letterD", 2 },
  { "(根)", "letterE", 2 },
  { "(根)", "letterF", 1 },
  { "(根)", "letterG", 2 },
  { "(根)", "letterH", 2 },
  { "(根)", "letterV", 2 },
  { "(根)", "murdoku-btn-hex", 1 },
  { "(根)", "murdoku-card-frame", 1 },
  { "(根)", "murdoku-cell", 1 },
  { "(根)", "murdoku-clue-row", 1 },
  { "(根)", "murdoku-panel", 1 },
  { "(根)", "murdoku-tape", 1 },
  { "(根)", "root", 1 },
  { "(根)", "ruler", 2 },
  { "(根)", "tpl-container", 2 },
  { "action.back", "bg", 1 },
  { "action.back", "label", 1 },
  { "assets", "row.1.1", 1 },
  { "assets", "row.1.2", 1 },
  { "assets", "row.1.3", 1 },
  { "assets", "row.1.4", 1 },
  { "assets", "row.1.5", 1 },
  { "assets", "row.2.1", 1 },
  { "assets", "row.2.2", 1 },
  { "assets", "row.2.3", 1 },
  { "assets", "row.2.4", 1 },
  { "assets", "row.2.5", 1 },
  { "assets", "row.3.1", 1 },
  { "assets", "row.3.2", 1 },
  { "assets", "row.3.3", 1 },
  { "assets", "row.3.4", 1 },
  { "assets", "row.3.5", 1 },
  { "assets", "row.3.6", 1 },
  { "cell.1.1", "content", 2 },
  { "clue", "backrop1", 2 },
  { "clue", "backrop2", 2 },
  { "clue", "face", 2 },
  { "clue", "gray", 2 },
  { "clue", "letter", 2 },
  { "clue", "what", 2 },
  { "clue", "who", 2 },
  { "clues", "clues.bg", 1 },
  { "clues", "clues.grid", 1 },
  { "content", "door.down", 2 },
  { "content", "door.left", 2 },
  { "content", "door.right", 2 },
  { "content", "door.up", 2 },
  { "content", "face", 2 },
  { "content", "note", 2 },
  { "content", "wall.down", 2 },
  { "content", "wall.left", 2 },
  { "content", "wall.right", 2 },
  { "content", "wall.up", 2 },
  { "content", "x", 2 },
  { "home", "home.bag", 1 },
  { "home", "home.continue", 1 },
  { "home", "home.select", 1 },
  { "home", "home.shop", 1 },
  { "home", "home.title", 1 },
  { "home.bag", "bg", 1 },
  { "home.bag", "label", 1 },
  { "home.continue", "bg", 1 },
  { "home.continue", "label", 1 },
  { "home.select", "bg", 1 },
  { "home.select", "label", 1 },
  { "home.shop", "bg", 1 },
  { "home.shop", "label", 1 },
  { "modal", "bg", 1 },
  { "modal", "modal.again", 1 },
  { "modal", "modal.body", 1 },
  { "modal", "modal.cancel", 1 },
  { "modal", "modal.exit", 1 },
  { "modal", "modal.level.case_001", 1 },
  { "modal", "modal.level.case_002", 1 },
  { "modal", "modal.level.case_003", 1 },
  { "modal", "modal.level.selftest_theft_5x5", 1 },
  { "modal", "modal.next", 1 },
  { "modal", "modal.no_accomplice", 1 },
  { "modal", "modal.save", 1 },
  { "modal", "modal.settle", 1 },
  { "modal", "modal.stats", 1 },
  { "modal", "modal.suspect.A", 1 },
  { "modal", "modal.suspect.B", 1 },
  { "modal", "modal.suspect.C", 1 },
  { "modal", "modal.suspect.D", 1 },
  { "modal", "modal.suspect.E", 1 },
  { "modal", "modal.suspect.F", 1 },
  { "modal", "modal.suspect.V", 1 },
  { "modal", "modal.title", 1 },
  { "modal", "result.exit", 1 },
  { "modal", "result.home", 1 },
  { "modal", "result.next", 1 },
  { "modal", "result.settle", 1 },
  { "modal.again", "label", 1 },
  { "modal.cancel", "bg", 1 },
  { "modal.cancel", "label", 1 },
  { "modal.exit", "bg", 1 },
  { "modal.exit", "label", 1 },
  { "modal.level.case_001", "label", 1 },
  { "modal.level.case_002", "label", 1 },
  { "modal.level.case_003", "label", 1 },
  { "modal.level.selftest_theft_5x5", "label", 1 },
  { "modal.next", "label", 1 },
  { "modal.no_accomplice", "label", 1 },
  { "modal.save", "bg", 1 },
  { "modal.save", "label", 1 },
  { "modal.settle", "bg", 1 },
  { "modal.settle", "label", 1 },
  { "modal.suspect.A", "label", 1 },
  { "modal.suspect.B", "label", 1 },
  { "modal.suspect.C", "label", 1 },
  { "modal.suspect.D", "label", 1 },
  { "modal.suspect.E", "label", 1 },
  { "modal.suspect.F", "label", 1 },
  { "modal.suspect.V", "label", 1 },
  { "murdoku-btn-hex", "1", 1 },
  { "murdoku-btn-hex", "2", 1 },
  { "murdoku-btn-hex", "3", 1 },
  { "murdoku-card-frame", "1", 1 },
  { "murdoku-card-frame", "2", 1 },
  { "murdoku-card-frame", "3", 1 },
  { "murdoku-cell", "1", 1 },
  { "murdoku-cell", "2", 1 },
  { "murdoku-cell", "3", 1 },
  { "murdoku-clue-row", "1", 1 },
  { "murdoku-clue-row", "2", 1 },
  { "murdoku-clue-row", "3", 1 },
  { "murdoku-panel", "1", 1 },
  { "murdoku-panel", "2", 1 },
  { "murdoku-tape", "1", 1 },
  { "murdoku-tape", "2", 1 },
  { "result.exit", "bg", 1 },
  { "result.exit", "label", 1 },
  { "result.home", "bg", 1 },
  { "result.home", "label", 1 },
  { "result.next", "bg", 1 },
  { "result.next", "label", 1 },
  { "result.settle", "bg", 1 },
  { "result.settle", "label", 1 },
  { "right", "hud.progress", 1 },
  { "root", "assets", 1 },
  { "root", "clues", 1 },
  { "root", "hex.back", 1 },
  { "root", "hex.hint", 1 },
  { "root", "hex.no", 1 },
  { "root", "hex.ok", 1 },
  { "root", "hex.redo", 1 },
  { "root", "hex.submit", 1 },
  { "root", "hex.undo", 1 },
  { "root", "hit.back", 1 },
  { "root", "hit.hint", 1 },
  { "root", "hit.no", 1 },
  { "root", "hit.ok", 1 },
  { "root", "hit.redo", 1 },
  { "root", "hit.submit", 1 },
  { "root", "hit.undo", 1 },
  { "root", "home", 1 },
  { "root", "modal", 1 },
  { "root", "right", 1 },
  { "root", "stage", 1 },
  { "root", "toolbar", 1 },
  { "root", "topbar", 1 },
  { "root", "tpl.cell", 1 },
  { "root", "tpl.ruler", 1 },
  { "root", "tpl.stage", 1 },
  { "row.1.1", "face.1.1", 1 },
  { "row.1.1", "letter.1.1", 1 },
  { "row.1.1", "what.1.1", 1 },
  { "row.1.1", "who.1.1", 1 },
  { "row.1.2", "face.1.2", 1 },
  { "row.1.2", "letter.1.2", 1 },
  { "row.1.2", "what.1.2", 1 },
  { "row.1.2", "who.1.2", 1 },
  { "row.1.3", "face.1.3", 1 },
  { "row.1.3", "letter.1.3", 1 },
  { "row.1.3", "what.1.3", 1 },
  { "row.1.3", "who.1.3", 1 },
  { "row.1.4", "face.1.4", 1 },
  { "row.1.4", "letter.1.4", 1 },
  { "row.1.4", "what.1.4", 1 },
  { "row.1.4", "who.1.4", 1 },
  { "row.1.5", "face.1.5", 1 },
  { "row.1.5", "letter.1.5", 1 },
  { "row.1.5", "what.1.5", 1 },
  { "row.1.5", "who.1.5", 1 },
  { "row.2.1", "face.2.1", 1 },
  { "row.2.1", "letter.2.1", 1 },
  { "row.2.1", "what.2.1", 1 },
  { "row.2.1", "who.2.1", 1 },
  { "row.2.2", "face.2.2", 1 },
  { "row.2.2", "letter.2.2", 1 },
  { "row.2.2", "what.2.2", 1 },
  { "row.2.2", "who.2.2", 1 },
  { "row.2.3", "face.2.3", 1 },
  { "row.2.3", "letter.2.3", 1 },
  { "row.2.3", "what.2.3", 1 },
  { "row.2.3", "who.2.3", 1 },
  { "row.2.4", "face.2.4", 1 },
  { "row.2.4", "letter.2.4", 1 },
  { "row.2.4", "what.2.4", 1 },
  { "row.2.4", "who.2.4", 1 },
  { "row.2.5", "face.2.5", 1 },
  { "row.2.5", "letter.2.5", 1 },
  { "row.2.5", "what.2.5", 1 },
  { "row.2.5", "who.2.5", 1 },
  { "row.3.1", "face.3.1", 1 },
  { "row.3.1", "letter.3.1", 1 },
  { "row.3.1", "what.3.1", 1 },
  { "row.3.1", "who.3.1", 1 },
  { "row.3.2", "face.3.2", 1 },
  { "row.3.2", "letter.3.2", 1 },
  { "row.3.2", "what.3.2", 1 },
  { "row.3.2", "who.3.2", 1 },
  { "row.3.3", "face.3.3", 1 },
  { "row.3.3", "letter.3.3", 1 },
  { "row.3.3", "what.3.3", 1 },
  { "row.3.3", "who.3.3", 1 },
  { "row.3.4", "face.3.4", 1 },
  { "row.3.4", "letter.3.4", 1 },
  { "row.3.4", "what.3.4", 1 },
  { "row.3.4", "who.3.4", 1 },
  { "row.3.5", "face.3.5", 1 },
  { "row.3.5", "letter.3.5", 1 },
  { "row.3.5", "what.3.5", 1 },
  { "row.3.5", "who.3.5", 1 },
  { "row.3.6", "face.3.6", 1 },
  { "row.3.6", "letter.3.6", 1 },
  { "row.3.6", "what.3.6", 1 },
  { "row.3.6", "who.3.6", 1 },
  { "stage", "board.bg", 1 },
  { "topbar", "action.back", 1 },
  { "topbar", "hud.subtitle", 1 },
  { "topbar", "hud.timer", 1 },
  { "topbar", "hud.title", 1 },
}

-- 建索引：父名 子名 -> 次数
local idx = {}
for i = 1, #M.edges do
  local e = M.edges[i]
  idx[e[1] .. "\0" .. e[2]] = e[3]
end
M.count = #M.edges

local SEP = "\0"

-- ★★ 扫描一棵探针树 ⇒ 得到它用到的每条边（按名字 ✓ 与缩比无关 ✓）
--   fakes：父控件对象 → 名字（★ 引擎控件对象本身没有 .name ⇒ 靠调用方给表 ✓）
function M.scan(root, nameOf)
  local used = {}
  local function walk(c)
    if c == nil then return end
    local nm = nameOf(c)
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) ~= "table" then return end
    for i = 1, #kids do
      local k = kids[i]
      local kn = nameOf(k)
      if nm ~= nil and kn ~= nil then
        local key = nm .. SEP .. kn
        used[key] = (used[key] or 0) + 1
      end
      walk(k)
    end
  end
  walk(root)
  return used
end

-- ★★★ 对账：★ 返回 ok, 报告文本
--   ★ 只查一个方向 ✓：★ "探针用了参考里没有的边" ⇒ 红 ✓
--   ★ 反向不查 ✓：★ 探针只搭它要量的一部分 ✓ 要求全用上会把工具做成废的 ✓
--
--   ⚠️ opt.skipParents ✓：★ **合成父**的名字表 ✓ —— ★ 从这些父出发的边**不检查** ✓
--     ★ 为什么必须有这一条（★ 实测踩到 ✓）：★ 探针的根是**合成的** ✗
--       · ★ 真机：`cell.1.1` 是**根级控件**（★ `347.gil` 里 `父=null` ✓）⇒ 边是 `(根) → cell.1.1` ✓
--       · ★ 探针：`root → cell.1.1` ✗ —— ★ 这条边在存档里**不存在** ✓
--     ⇒ ★ 若不声明 ⇒ ★ 每个探针都会在"根"这一步误报 ✗ ⇒ ★ 对账器会被当成噪音而弃用 ✓
--     ⚠️ ★ 但**不许**把这条当后门 ✓：★ 只许列**真正合成**的那一层 ✓
--       —— ★ 真控件之间的父子关系**一律照查** ✓（★ `content → ruler.c.1` 那种假边躲不过 ✓）
function M.check(root, nameOf, label, opt)
  local skip = (opt and opt.skipParents) or nil
  local used = M.scan(root, nameOf)
  local bad, okn, skipped = {}, 0, 0
  for key, n in pairs(used) do
    local p, c = key:match("^(.-)" .. SEP .. "(.*)$")
    if skip ~= nil and skip[p] then
      skipped = skipped + 1
    elseif idx[key] == nil then
      bad[#bad + 1] = "      ✗ 假边：" .. tostring(p) .. " → " .. tostring(c)
        .. "（探针用了 " .. tostring(n) .. " 次，★ 存档里没有这条边）"
    else
      okn = okn + 1
    end
  end
  table.sort(bad)
  local ok = (#bad == 0)
  local msg = "  [对账] " .. tostring(label or "探针树") .. "：用到 " .. tostring(okn)
    .. " 条**存档里真实存在**的边"
    .. (skipped > 0 and ("（另有 " .. tostring(skipped) .. " 条挂在**声明过的合成父**下，按约定不查 ✓）") or "")
    .. (#bad == 0 and "　⇒ ★ 与存档一致 ✓" or ("　⇒ ★★ 有 " .. tostring(#bad) .. " 条假边 ✗"))
  if not ok then msg = msg .. "\n" .. table.concat(bad, "\n") end
  return ok, msg
end

return M
