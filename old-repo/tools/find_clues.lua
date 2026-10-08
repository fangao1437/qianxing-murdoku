--[[----------------------------------------------------------------------------
  tools/find_clues.lua —— 线索自动搜索器

  用途：你把**空间结构 + 答案 + 角色归属**设计好，线索交给它搜。
  它会从几十种线索原子里挑一小组，使得
      「至多一条假话 + R3/R4 结构约束」
  在（摆位 × 角色归属）空间里**只有唯一解**，并且刚好等于你设计的答案。
  输出可直接粘进关卡文件的 `clues = { ... }`（含 `meta.false_clue`）。

  跑法：
    lua tools/find_clues.lua lua/levels/case_003.lua
    lua tools/find_clues.lua lua/levels/case_003.lua 9       # 指定目标线索条数
    lua tools/find_clues.lua lua/levels/case_003.lua 9 1234  # 固定随机种子（可复现）

  关卡文件的要求：
    · 必须已经有 walls / doors / objects / suspects / victim / solution / roles
    · clues 可以是空表（本工具会填）或已有内容（会作为"必留线索"保留在前）
    · meta.false_clue 会被本工具重写

  ⚠️ 搜索是**启发式**的：找不到就多跑几次（换种子）或加线索条数上限。
     它保证的是"**找到的解一定合法**"（每一条都经过 validate_level + solve 复核），
     而不是"一定能找到"。
----------------------------------------------------------------------------]]--

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local Core = require("murdoku_core")

-- ── 参数 ──────────────────────────────────────────────────────────────────
local level_path = arg and arg[1]
if not level_path then
  io.stderr:write("用法：lua tools/find_clues.lua <level.lua> [目标条数] [随机种子]\n")
  os.exit(1)
end
local target_clues = tonumber(arg and arg[2]) or 9
local seed = tonumber(arg and arg[3]) or os.time()

-- 用一个确定性 RNG（不用 math.randomseed，便于复现）
local rng_state = seed % 2147483647
if rng_state <= 0 then rng_state = rng_state + 2147483646 end
local function rnd()
  rng_state = (rng_state * 16807) % 2147483647
  return rng_state / 2147483647
end
local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.floor(rnd() * i) + 1
    t[i], t[j] = t[j], t[i]
  end
  return t
end

print(string.format("== 线索搜索器 ==  目标 %d 条  种子 %d", target_clues, seed))

-- ── 载入关卡 ──────────────────────────────────────────────────────────────
local chunk, lerr = loadfile(level_path)
if not chunk then
  io.stderr:write("加载失败：" .. tostring(lerr) .. "\n")
  os.exit(1)
end
local level = chunk()
if type(level) ~= "table" then
  io.stderr:write("关卡文件必须 return 一个 table\n")
  os.exit(1)
end

-- 允许关卡先留空 clues / meta.false_clue —— 本工具就是来填它们的，
-- 所以构造 Core 之前先把这两样按"合法"处理，免得 validate_level 直接拦下来。
local saved_meta = level.meta
if level.meta ~= nil then
  local fc = level.meta.false_clue
  if fc == nil or fc == 0 or fc > #(level.clues or {}) then
    level.meta = nil
  end
end

local core, verrs = Core.new(level)
if not core then
  io.stderr:write("关卡数据有误：" .. table.concat(verrs or {}, " / ") .. "\n")
  os.exit(1)
end
level.meta = saved_meta          -- 搜索过程里会临时改写 core.level.meta

print(string.format("关卡 %s  %d×%d  棋子 %d  区域 %d",
  tostring(level.id), core.rows, core.cols, core:piece_count(), core.room_count))

if #(level.clues or {}) > 0 then
  print(string.format("（关卡里已有 %d 条线索，会作为「必留」保留在最前面）", #level.clues))
end

-- ── 摆上答案，取结构信息 ──────────────────────────────────────────────────
for id, p in pairs(core.solution) do
  core:select_suspect(id)
  core:hold_cell(p.r, p.c)
end
local sok, serrs, sinfo = core:structure_report()
if not sok then
  io.stderr:write("结构约束不成立，先改关卡的空间/答案：\n")
  for i = 1, #serrs do io.stderr:write("  - " .. serrs[i] .. "\n") end
  os.exit(1)
end
print(string.format("结构 OK：受害者区域 #%s，k=%d，门相邻 %d 个，无辜最多 %s",
  tostring(sinfo.victim_room), sinfo.k or 0, #(sinfo.adjacent or {}), tostring(sinfo.best)))
print("")

-- ── 角色别名 ──────────────────────────────────────────────────────────────
local ALIAS = { thief = "@thief", accomplice = "@accomplice", victim = "@victim" }
local ids = {}          -- 全部角色 id（含受害者）
for i = 1, #core.pieces do ids[#ids + 1] = core.pieces[i].id end
local role_of = {}
for role, rid in pairs(level.roles or {}) do role_of[rid] = role end
if core.victim_id then role_of[core.victim_id] = "victim" end

-- 一个角色 id 允许出现在线索里的"写法"：真名 + 它扮演的角色别名
local function ways(id)
  local out = { id }
  local role = role_of[id]
  if role and ALIAS[role] then out[#out + 1] = ALIAS[role] end
  return out
end

-- ── 判定一个线索在"当前答案"下是否成立 ────────────────────────────────────
-- 做法：把线索临时塞进 core.level.clues，用 clue_results 一次性拿到 text + satisfied
local function probe(clue)
  local save = core.level.clues
  local saved_meta = core.level.meta
  core.level.clues = { clue }
  core.level.meta = nil
  local res = core:clue_results()
  core.level.clues = save
  core.level.meta = saved_meta
  local r = res[1]
  return r and r.satisfied or false, r and r.text or "?"
end
local function text_of(clue)
  local _, t = probe(clue)
  return t
end

-- ── 候选线索池 ────────────────────────────────────────────────────────────
local cands = {}
local function add(clue)
  local sat, txt = probe(clue)          -- 只探一次，别调两遍
  clue.__text = txt
  clue.__sat = sat
  cands[#cands + 1] = clue
end

local pos = core.solution
local rows, cols = core.rows, core.cols

for i = 1, #ids do
  local a = ids[i]
  local pa = pos[a]
  for wi = 1, #ways(a) do
    local w = ways(a)[wi]
    if pa then
      add({ type = "at", who = w, r = pa.r, c = pa.c })
      for r = 1, rows do
        if r ~= pa.r then add({ type = "not_at", who = w, r = r, c = pa.c }) end
      end
    end
    -- 行/列：只加"真"的那些，避免池子被假线索淹没
    if pa then
      add({ type = "in_row", who = w, r = pa.r })
      add({ type = "in_col", who = w, c = pa.c })
    end
  end
  -- 独处类
  add({ type = "alone_in_room", who = a })
  add({ type = "corner_room", who = a })
  add({ type = "with_victim", who = a })
end

-- 两两之间
for i = 1, #ids do
  for j = 1, #ids do
    if i ~= j then
      local a, b = ids[i], ids[j]
      local wa, wb = ways(a)[1], ways(b)[1]
      add({ type = "same_room", a = wa, b = wb })
      add({ type = "different_room", a = wa, b = wb })
      add({ type = "beside", a = wa, b = wb })
      add({ type = "not_beside", a = wa, b = wb })
      add({ type = "left_of", a = wa, b = wb })
      add({ type = "right_of", a = wa, b = wb })
      add({ type = "above", a = wa, b = wb })
      add({ type = "below", a = wa, b = wb })
      add({ type = "in_front_of", a = wa, b = wb })
      add({ type = "alone_with", a = wa, b = wb })
      add({ type = "with_only", a = wa, b = wb })
      -- 角色别名版本（身份推理的主力）
      local ra, rb = role_of[a], role_of[b]
      if ra and ALIAS[ra] then
        add({ type = "same_room", a = ALIAS[ra], b = wb })
        add({ type = "beside", a = ALIAS[ra], b = wb })
        add({ type = "left_of", a = ALIAS[ra], b = wb })
        add({ type = "right_of", a = ALIAS[ra], b = wb })
        add({ type = "above", a = ALIAS[ra], b = wb })
        add({ type = "below", a = ALIAS[ra], b = wb })
      end
      if rb and ALIAS[rb] then
        add({ type = "same_room", a = wa, b = ALIAS[rb] })
        add({ type = "beside", a = wa, b = ALIAS[rb] })
      end
      for d = 2, rows do add({ type = "distance", a = wa, b = wb, d = d }) end
    end
  end
end

-- 角色身份类：只允许"不是某个角色"（排除法），以及受害者是谁
for i = 1, #ids do
  local a = ids[i]
  add({ type = "not_role", who = a, role = "thief" })
  add({ type = "not_role", who = a, role = "accomplice" })
  if role_of[a] == "victim" then
    add({ type = "is_role", who = a, role = "victim" })
  end
end

-- 去重（同 type + 同参数的只留一条）
local seen_key, pool = {}, {}
for i = 1, #cands do
  local c = cands[i]
  local parts = { c.type }
  local keys = {}
  for k in pairs(c) do
    if k:sub(1, 2) ~= "__" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(c[k]) end
  local key = table.concat(parts, "|")
  if not seen_key[key] then seen_key[key] = true; pool[#pool + 1] = c end
end
print(string.format("候选线索池：%d 条（其中答案下成立 %d 条）", #pool, (function()
  local n = 0
  for i = 1, #pool do if pool[i].__sat then n = n + 1 end end
  return n
end)()))

-- ── 求解：给定线索集合，看有几个解（上限 2 就够判断唯一性） ────────────────
local solve_calls = 0
local function count_solutions(clues, allowed)
  solve_calls = solve_calls + 1
  local save = core.level.clues
  local save_meta = core.level.meta
  core.level.clues = clues
  core.level.meta = { false_clue = (allowed > 0) and 1 or nil }
  local sols = core:solve(2)
  core.level.clues = save
  core.level.meta = save_meta
  return sols
end

-- ── 贪心挑选 ──────────────────────────────────────────────────────────────
-- 策略：
--   1) 先选一条**假线索**（答案下不成立、但看起来合理）
--   2) 再一条条加"真线索"，每次都挑"能把解数压得最低"的那条
--   3) 到只剩 1 个解就停；到上限还没唯一就换种子重来

local keep = {}
for i = 1, #(level.clues or {}) do keep[#keep + 1] = level.clues[i] end

local function strip(c)          -- 去掉内部字段，得到干净的线索表
  local out = {}
  for k, v in pairs(c) do if k:sub(1, 2) ~= "__" then out[k] = v end end
  return out
end

local best_result = nil

for attempt = 1, 6 do
  local false_pool = {}
  for i = 1, #pool do
    if not pool[i].__sat then false_pool[#false_pool + 1] = pool[i] end
  end
  if #false_pool == 0 then
    io.stderr:write("答案下没有任何假线索候选 —— 这条线索池有问题\n")
    os.exit(1)
  end
  shuffle(false_pool)

  for fi = 1, math.min(#false_pool, 12) do
    local false_clue = false_pool[fi]
    -- ★ 假线索必须排在**最后一条**：关卡用 meta.false_clue = 序号 声明是哪条，
    --   而玩家看到的顺序就是 clues 的顺序 —— 放最后既好读，也让序号 = 条数。
    local trues = {}
    for i = 1, #keep do trues[#trues + 1] = keep[i] end
    local remaining = {}
    for i = 1, #pool do
      if pool[i].__sat and pool[i] ~= false_clue then remaining[#remaining + 1] = pool[i] end
    end
    remaining = shuffle(remaining)

    local function assemble(extra)
      local out = {}
      for i = 1, #trues do out[#out + 1] = trues[i] end
      if extra then out[#out + 1] = extra end
      out[#out + 1] = strip(false_clue)
      return out
    end

    local ok = false
    while (#trues + 1) < target_clues do
      local best, best_n = nil, nil
      -- 每次只看一部分候选（够用且快很多）
      local scan = math.min(#remaining, 60)
      for i = 1, scan do
        local trial = assemble(strip(remaining[i]))
        local sols = count_solutions(trial, 1)
        local n = #sols
        if best_n == nil or n < best_n then best, best_n = i, n end
        if n == 1 then break end
      end
      if best == nil then break end
      trues[#trues + 1] = strip(remaining[best])
      table.remove(remaining, best)
      if best_n == 1 then ok = true; break end
    end

    if ok then
      local chosen = assemble()
      -- 复核：真·唯一解 + 假话声明与实际一致
      local sols = count_solutions(chosen, 1)
      local uniq = (#sols == 1
        and sols[1].thief == level.roles.thief
        and (sols[1].accomplice or nil) == (level.roles.accomplice or nil))
      if uniq then
        local saved = core.level.clues
        local saved_meta = core.level.meta
        core.level.clues = chosen
        core.level.meta = { false_clue = #chosen }
        local res = core:clue_results()
        local failed = {}
        for i = 1, #res do if not res[i].satisfied then failed[#failed + 1] = i end end
        core.level.clues = saved
        core.level.meta = saved_meta
        if #failed == 1 and failed[1] == #chosen then
          best_result = chosen
          print(string.format("\n★ 第 %d 次尝试找到唯一解：%d 条线索（第 %d 条是假话）",
            attempt, #chosen, #chosen))
          break
        end
      end
    end
    if best_result then break end
  end
  if best_result then break end
  print(string.format("  第 %d 次尝试没找到，换一批候选…", attempt))
end

if not best_result then
  io.stderr:write(string.format(
    "\n没找到。建议：①提高目标条数（现在 %d）②换个种子（现在 %d）"
    .. "③把空间结构做得更「紧」（区域划分/门径让相邻区域的无辜人数差距更明显）\n",
    target_clues, seed))
  os.exit(1)
end

-- ── 输出 ──────────────────────────────────────────────────────────────────
local order = { "type", "who", "a", "b", "r", "c", "d", "role", "object", "n", "room" }
local function fmt(c)
  local parts = {}
  for i = 1, #order do
    local k = order[i]
    if c[k] ~= nil then
      local v = c[k]
      if type(v) == "string" then v = string.format("%q", v) end
      parts[#parts + 1] = k .. " = " .. v
    end
  end
  return "    { " .. table.concat(parts, ", ") .. " },"
end

print("\n---------------- 粘进关卡文件的内容 ----------------\n")
print(string.format("  meta = {"))
print(string.format("    false_clue = %d,        -- 第 %d 条", #best_result, #best_result))
print(string.format("    announce   = \"%s\",", (level.meta and level.meta.announce) or "one"))
print(string.format("  },"))
print("")
print("  clues = {")
for i = 1, #best_result do
  local c = best_result[i]
  local _, t = probe(c)
  print(fmt(c) .. string.format("   -- %d. %s%s", i, t, i == #best_result and "   ★ 假话" or ""))
end
print("  },")
print("")
print("-----------------------------------------------------")
print(string.format("求解调用 %d 次。改完记得跑：lua tools/validate_levels.lua 3", solve_calls))
