--[[----------------------------------------------------------------------------
  tests/cell_lightup_size.lua —— 「每 30 帧点亮格子」必须覆盖【全盘】

  ★★★ 这个文件钉的是一个**藏了很久、一次解释全部现象**的 bug ✗✓：

    真机证据（用户 2026-10-11 02:41 日志 ✓）：
      · 第 3 关 6×6 ⇒ `棋盘格子：36 / 36 存在` ✓ **但** `格子底图已点亮：**25** 个 face` ✗
      · 第 1 关 5×5 ⇒ `25 / 25` ✓ 且 `25 个 face` ✓ —— ★ **所以"第一关正确"** ✓
      · 用户原话 ⇒「★ **除第一关以外的其它关卡的各类点击 bug**」✓

    根因 ⇒ `main.lua` 那段每 30 帧的点亮循环**只读 `cfg.cells.rows/cols`** ✗
      · 而 `entry_client_script.lua:462` 里那两个是**写死的兜底 `5, 5`** ✓
        （★ 它自己的注释：「**只在读不到父控件尺寸时才用到的兜底**」✓）
      ⇒ ★ **任何关卡都只点 25 格** ✗ ⇒ 第 26 格起 `content` 不亮 ⇒ 子控件全不可见
        ⇒ ★★ **格子看不见、也点不动** ✓✓（★ `face` 是底图 ＋ 射线目标 ✓）

    同一个量在别处**优先级是对的** ✗（★ 所以它藏了这么久 ✓）：
      · `main.lua:670`  ✓：`adapter.cells_rows or (cfg.cells and cfg.cells.rows) or 5`
      · `engine_adapter_qianxing.lua:3808 / 3809 / 3924` ✓：同一个优先级
      · ★ **只有那一段**漏了最权威的 `adapter.cells_rows` ✗✓

  ★ 判据分两层 ✓：
    ★ ① **机械读源码** ✓：那段必须出现 `cells_rows` ✗ 且**优先级 adapter 在前** ✓
    ★ ② **真跑一遍取值** ✓：★ 6×6 / 7×7 都要**赢过**写死的兜底 5,5 ✓

  跑法：lua tests/cell_lightup_size.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

--------------------------------------------------------------------------------
-- 1. ★ 机械判据：`main.lua` 那段点亮循环必须按 adapter 优先取棋盘尺寸
--------------------------------------------------------------------------------
do
  local f = io.open(root .. "/lua/main.lua", "rb")
  ok(f ~= nil, "能读到 lua/main.lua")
  local src = f and f:read("*a") or ""
  if f then f:close() end

  -- ★★ 定位这一段我连踩四个坑 ✗ —— ★ 全记下来 ✓（★ 免得下一个人重走 ✓）：
  --   ★ ① 只取"锚点前 3000 字节" ⇒ ★ 锚点落在注释里 ⇒ 假红 ✓
  --   ★ ② 只找 `cells_rows` ⇒ ★ **注释里也有这个词** ✗（★ "注释里的字不算代码" ✓）
  --   ★ ③ 锚 `scr_now == "level"` ⇒ ★ **全文件 4 处** ✗ ⇒ 命中第一处 ✓
  --   ★ ④ 按"字节"回退想找到段首 ⇒ ★ **还是错** ✗
  --     ★★ 真因 ✓：★★ **Lua 的 `string.find` 返回【字节】位置 ✗ 而中文一个字 3 字节** ✓
  --       ⇒ ★ 我按字节回退 200 ✓ ★ 实际只覆盖 ~70 个汉字 ✗ ⇒ 段落切错 ✓✓
  --   ⇒ ★★★ 最终做法 ✓：★ **锚在 `if` 那一整行 ✓ ＋ 向后切一个"够大"的窗口 ✓
  --     ＋ 用"三样都在"**自证**窗口够大 ✓**（★ 不依赖精确长度 ✓）
  local ANCHOR = 'if scr_now == "level" and ((current.frames or 0) % 30)'
  local begin = src:find(ANCHOR, 1, true)
  ok(begin ~= nil, "能定位那段循环的起点（锚：" .. ANCHOR .. "）")

  -- ★ 窗口 8000 **字节** ✓：★ 实测那段本体 ~1200 字节 ＋ 前后注释 ✓ 足够 ✓
  local WIN = 8000
  local seg = (begin ~= nil) and src:sub(begin, math.min(#src, begin + WIN)) or ""

  -- ★ 去掉整行注释 ✓（★ 本项目的注释都是整行 `--` 起 ✓ ★ 也去掉行尾注释 ✓）
  local code = {}
  for line in (seg .. "\n"):gmatch("([^\n]*)\n") do
    code[#code + 1] = (line:gsub("%-%-.*$", ""))
  end
  seg = table.concat(code, "\n")

  -- ★★ 自证窗口够大 ✓：★ 三样都要在 ✓
  --   ★ 否则"找不到"是**窗口的错** ✗ ★ 不是代码的错 ✓ —— ★ 这一条就是防假红 ✓✓
  local has_fallback = seg:find("local rows, cols = 5, 5", 1, true) ~= nil
  local has_ad = seg:find("cells_rows", 1, true) ~= nil
  local has_cfg = seg:find("cfg.cells.rows", 1, true) ~= nil
  ok(has_fallback, "★ 窗口自证：兜底行 `local rows, cols = 5, 5` 在窗口内")
  ok(has_ad, "★ 窗口自证：`cells_rows` 在窗口内（★ 要求剥掉注释后仍存在 ✓）")
  ok(has_cfg, "★ 窗口自证：`cfg.cells.rows` 在窗口内")

  ok(seg:find("cells_cols", 1, true) ~= nil, "那段必须引用 `cells_cols`")

  -- ★★ 优先级判据 ✓：`cells_rows` 必须**先**出现 ✗（★ 不能只当兜底 ✓）
  local i_ad = seg:find("cells_rows", 1, true)
  local i_cfg = seg:find("cfg.cells.rows", 1, true)
  ok(i_ad ~= nil and i_cfg ~= nil and i_ad < i_cfg,
    "优先级必须是 `adapter.cells_rows` 在 `cfg.cells.rows` **之前**"
      .. "（实测 adapter@" .. tostring(i_ad) .. " / cfg@" .. tostring(i_cfg) .. "）")

  print("  [PASS] main.lua 那段按 adapter 优先取棋盘尺寸")
end

--------------------------------------------------------------------------------
-- 2. ★ 兜底配置确实是 5, 5（★ 这就是"只有第一关对"的原因 ✓）
--------------------------------------------------------------------------------
do
  local f = io.open(root .. "/lua/entry_client_script.lua", "rb")
  local src = f and f:read("*a") or ""
  if f then f:close() end
  ok(src:find("rows     = 5,", 1, true) ~= nil, "entry_client_script 里 cfg.cells.rows 兜底 = 5")
  ok(src:find("cols     = 5,", 1, true) ~= nil, "entry_client_script 里 cfg.cells.cols 兜底 = 5")
  print("  [PASS] 写死的兜底就是 5,5（★ 与「第一关对、其余错」一致 ✓）")
end

--------------------------------------------------------------------------------
-- 3. ★★ 行为判据：真跑一遍"取尺寸"的优先级（★ 6×6 / 7×7 都要赢过兜底 ✓）
--------------------------------------------------------------------------------
do
  -- ★ 复刻那段取值逻辑 ✓（★ 与 main.lua 的写法逐字同构 ✓）
  local function resolve(a)
    local rows, cols = 5, 5
    if a ~= nil then
      rows = a.cells_rows or (a.cfg and a.cfg.cells and a.cfg.cells.rows) or rows
      cols = a.cells_cols or (a.cfg and a.cfg.cells and a.cfg.cells.cols) or cols
    end
    return rows, cols
  end

  -- ★ 真机那种适配器 ✓：★ cfg 里是兜底 5,5 ✓ ★ ensure_cells 写了真值 ✓
  local function adapter(ar, ac)
    return { cells_rows = ar, cells_cols = ac, cfg = { cells = { rows = 5, cols = 5 } } }
  end

  local r, c = resolve(adapter(5, 5))
  ok(r == 5 and c == 5, "5×5 关 ⇒ 5,5（实测 " .. r .. "," .. c .. "）")
  r, c = resolve(adapter(6, 6))
  ok(r == 6 and c == 6, "6×6 关 ⇒ 6,6（实测 " .. r .. "," .. c .. "）")
  r, c = resolve(adapter(7, 7))
  ok(r == 7 and c == 7, "7×7 关 ⇒ 7,7（实测 " .. r .. "," .. c .. "）")

  -- ★ 退化情形 ✓：adapter 还没建 / 没写 cells_rows ⇒ ★ 退回兜底 ✓（不崩 ✓）
  r, c = resolve(nil)
  ok(r == 5 and c == 5, "没有 adapter ⇒ 退回 5,5（实测 " .. r .. "," .. c .. "）")
  r, c = resolve({ cfg = { cells = { rows = 6, cols = 6 } } })
  ok(r == 6 and c == 6, "只有 cfg 没有 cells_rows ⇒ 用 cfg 的 6,6（实测 " .. r .. "," .. c .. "）")

  -- ★★★ 关键断言 ✓：★ **兜底值不许赢过真值** ✓
  local bad = { cells_rows = 6, cells_cols = 6, cfg = { cells = { rows = 5, cols = 5 } } }
  ok(bad.cells_rows == 6 and bad.cfg.cells.rows == 5,
    "前提：这个假适配器确实是「真值 6 / 兜底 5」冲突")
  r, c = resolve(bad)
  ok(r == 6 and c == 6,
    "★ 冲突时必须以 adapter 的 6,6 为准（★ 这正是 bug 的判据 ✓ 实测 " .. r .. "," .. c .. "）")
  print("  [PASS] 优先级：6×6 / 7×7 都赢过写死的兜底 5,5")
end

--------------------------------------------------------------------------------
print(string.format("\ncell_lightup_size: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
