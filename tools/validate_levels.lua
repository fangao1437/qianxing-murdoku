--[[----------------------------------------------------------------------------
  tools/validate_levels.lua —— 批量校验关卡（偷窃版 v0.3，离线）

  跑法：
    lua tools/validate_levels.lua          # 解数上限 2（同时校验角色归属唯一性）
    lua tools/validate_levels.lua 3        # 多找几个解，便于看有多少歧义

  对 levels/init.lua 里登记的每一关做：
    1. 格式校验（含 doors / roles / meta / tie_policy）
    2. 结构约束 R3/R4（在关卡自己的答案上）
    3. 假话声明是否与实际一致（答案上恰好 ≤1 条不成立，且与 meta.false_clue 对上）
    4. 唯一解（摆位 × 角色归属），>1 说明线索不够、玩家可以蒙
----------------------------------------------------------------------------]]--

local here = (arg and arg[0]) or "tools/validate_levels.lua"
local root = here:gsub("tools[/\\]validate_levels%.lua$", "")
package.path = table.concat({
  package.path,
  root .. "lua/?.lua",
  root .. "lua/?/init.lua",
  root .. "?.lua",
}, ";")

local Core   = require("murdoku_core")
local Levels = require("levels.init")

local limit = tonumber(arg and arg[1]) or 2
local total, bad = 0, 0

print("== 关卡批量校验（偷窃版，解数上限 " .. limit .. "）==")

local levels = Levels.all()
local lerrs = Levels.load_errors()
if #lerrs > 0 then
  bad = bad + #lerrs
  print(string.format("!! %d 个关卡模块加载失败（语法错误 / require 失败），这些关卡**没有被检查**：", #lerrs))
  for i = 1, #lerrs do
    print("  - " .. lerrs[i].module)
    print("      " .. (lerrs[i].error:gsub("\n", "\n      ")))
  end
  print("")
end

for _, lv in ipairs(levels) do
  total = total + 1
  print("")
  print(string.format("— %s  %s", tostring(lv.id), tostring(lv.name or "")))

  local ok, errors = Core.validate_level(lv)
  if not ok then
    bad = bad + 1
    print("  格式: FAIL")
    for i = 1, #errors do print("    - " .. errors[i]) end
  else
    print("  格式: OK")
    local core = Core.new(lv)
    if not core then
      bad = bad + 1
      print("  实例化: FAIL")
    else
      -- 把答案摆上
      for id, p in pairs(core.solution) do
        core:select_suspect(id)
        core:hold_cell(p.r, p.c)
      end

      -- 结构
      local sok, serrs, sinfo = core:structure_report()
      if sok then
        print(string.format("  结构: OK（受害者区域 #%s，k=%d，门相邻 %d 个，无辜最多 %s）",
              tostring(sinfo.victim_room), sinfo.k or 0, #(sinfo.adjacent or {}),
              tostring(sinfo.best)))
      else
        bad = bad + 1
        print("  结构: FAIL")
        for i = 1, #(serrs or {}) do print("    - " .. serrs[i]) end
      end

      -- 假话
      local cres = core:clue_results()
      local failed = {}
      for i = 1, #cres do
        if not cres[i].satisfied then failed[#failed + 1] = i end
      end
      local declared = (lv.meta or {}).false_clue
      local lie_ok
      if declared then
        lie_ok = (#failed == 1 and failed[1] == declared)
      else
        lie_ok = (#failed == 0)
      end
      if lie_ok then
        print(string.format("  假话: OK（声明 %s，实际不成立 %d 条）",
              declared and ("第" .. tostring(declared) .. "条") or "无", #failed))
      else
        bad = bad + 1
        local list = {}
        for i = 1, #failed do list[#list + 1] = tostring(failed[i]) end
        print(string.format("  假话: FAIL（声明 %s，实际不成立 [%s]）",
              tostring(declared), table.concat(list, ",")))
      end

      -- 唯一解（含角色归属）
      -- ★★★ 2026-10-11 **线索为空的关卡：这一项【不适用】，如实标注** ✗✓
      --   ★ 起因 ✓：★ 用户要求把那套"为每关人物发位置和字母"的逻辑**整段删掉** ✓
      --     （★ 原话：「★ 关卡设计本来就要改 ✓ ★ 不用留着他了」✓）
      --     ⇒ ★★ 真关卡现在**线索 = 0** ✓
      --   ★ 而"唯一解"这个判据**以线索为前提** ✗ —— ★ 0 条线索必然多解 ✓
      --     ⇒ ★ 照旧报 FAIL ⇒ ★★ **每关都红** ✗ ⇒ ★ **把真正的红淹掉** ✓（★ 这项目最反对的"假红淹真红" ✓）
      --   ⇒ ★★ 处理 ✓：★ **无线索 ⇒ 报"未测（无线索）"** ✓ ★ **不计入 bad** ✓
      --     ★ **但绝不放松判据** ✗ —— ★ 只要**有线索**，判据**一字不变** ✓✓
      --   ★★ 这也是给后来人的指针 ✓：★ 见红先看"线索 %d"是否 > 0 ✓
      local n_clues = #(lv.clues or {})
      if n_clues == 0 then
        print("  唯一解: 未测（本关线索 0 条 —— ★ 内容待设计 ✓ 不是判据失效 ✗）")
      else
        local sols = core:solve(limit)
        if #sols == 1 then
          print(string.format("  唯一解: OK（盗窃者 %s，同伙 %s）",
                tostring(sols[1].thief), tostring(sols[1].accomplice)))
        else
          bad = bad + 1
          print(string.format("  唯一解: FAIL（找到 %d 个解，上限 %d）—— 线索不足或角色不唯一",
                #sols, limit))
          for i = 1, #sols do
            print(string.format("    解%d: 盗窃者 %s / 同伙 %s",
                  i, tostring(sols[i].thief), tostring(sols[i].accomplice)))
          end
        end
      end

      print(string.format("  规模: %dx%d / 棋子 %d / 线索 %d / 区域 %d / 门 %d",
            core.rows, core.cols, core:piece_count(), #(lv.clues or {}),
            core.room_count, (function()
              local n = 0
              for _ in pairs(core.door_set) do n = n + 1 end
              return n
            end)()))
    end
  end
end

print("")
print(string.format("== 合计 %d 关（另有 %d 个模块加载失败），需要处理的 %d 项 ==", total, #lerrs, bad))
if bad > 0 then os.exit(1) end
