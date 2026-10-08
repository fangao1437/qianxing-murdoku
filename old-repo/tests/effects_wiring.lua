--[[----------------------------------------------------------------------------
  tests/effects_wiring.lua —— 动效接线一致性回归

  为什么要有这个：
    ui_controller 里有一张语义表 M.EFFECTS（PLACE = "pop_tile" …），
    适配器里有一张实现表 EFFECTS（pop_tile = {dur/keys/…}）。
    两张表**分处两个文件**，靠字符串名字对上。

    名字对不上时的表现极其隐蔽：play_effect 查不到就 return，
    **不动、不报错、也不影响逻辑**，只有肉眼看画面才发现"这个动作没反馈"。
    历史上 portrait_slide_up 就是这么漏的（M.EFFECTS.VICTIM 指了它，
    EFFECTS 里却没有）。

  这个测试纯文本解析两个源文件做集合比对，不依赖游戏环境。

  跑法：lua tests/effects_wiring.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL  " .. msg)
  end
end

local function slurp(path)
  local fh, err = io.open(path, "rb")
  if not fh then
    print("  FAIL  读不了 " .. path .. "：" .. tostring(err))
    failed = failed + 1
    return nil
  end
  local t = fh:read("*a")
  fh:close()
  if t:sub(1, 3) == "\239\187\191" then t = t:sub(4) end
  return t
end

local ui_src = slurp(root .. "/lua/ui_controller.lua")
local ad_src = slurp(root .. "/lua/engine_adapter_qianxing.lua")

--------------------------------------------------------------------------------
-- ① ui_controller：抽出 M.EFFECTS 的所有字符串值
--      形如：  PLACE     = "pop_tile",
--------------------------------------------------------------------------------
local semantic = {}
do
  local body = ui_src and ui_src:match("M%.EFFECTS%s*=%s*{(.-)\n}")
  ok(body ~= nil, "在 ui_controller.lua 里找不到 M.EFFECTS 表")
  if body then
    for name, val in body:gmatch("([A-Z_]+)%s*=%s*\"([%w_]+)\"") do
      semantic[val] = name
    end
  end
  local n = 0
  for _ in pairs(semantic) do n = n + 1 end
  ok(n >= 10, "M.EFFECTS 只解析出 " .. n .. " 条，解析大概坏了")
end

--------------------------------------------------------------------------------
-- ② 适配器：逐行解析 EFFECTS 表
--      表项一律是**顶格两空格**缩进开头：
--        pop_tile     = { dur = 0.26, ease = "OutBack",  ch = "scale",
--                         keys = { ... } },
--      续行缩进更深，所以"恰好两空格 + 标识符 + ="就是一条新表项的开始。
--      （不能用 `\w+ = {` 全表扫：续行里的 `keys = {` 会被误当成表项名 —— 第一版就栽在这。）
--------------------------------------------------------------------------------
local entries, order = {}, {}
do
  local body = ad_src and ad_src:match("local EFFECTS%s*=%s*{(.-)\n}")
  ok(body ~= nil, "在 engine_adapter_qianxing.lua 里找不到 EFFECTS 表")
  if body then
    local cur = nil
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
      local name = line:match("^  ([%a_][%w_]*)%s*=%s*{")
      if name then
        cur = name
        entries[cur] = { text = line }
        order[#order + 1] = cur
      elseif cur ~= nil then
        entries[cur].text = entries[cur].text .. "\n" .. line
      end
    end
  end
  ok(#order >= 10, "EFFECTS 只解析出 " .. #order .. " 条，解析大概坏了")
end

--------------------------------------------------------------------------------
-- ③ 核心断言：界面层点名的每一条，适配器都得有实现
--------------------------------------------------------------------------------
do
  local missing = {}
  for val, name in pairs(semantic) do
    if entries[val] == nil then missing[#missing + 1] = name .. " -> " .. val end
  end
  table.sort(missing)
  ok(#missing == 0,
    "M.EFFECTS 有 " .. #missing .. " 条在适配器 EFFECTS 表里没有实现（会静默不动）：\n        "
    .. table.concat(missing, "\n        "))
end

--------------------------------------------------------------------------------
-- ④ 反向：实现了但没人调 —— 只提示，不算失败
--------------------------------------------------------------------------------
do
  local unused = {}
  for _, key in ipairs(order) do
    if semantic[key] == nil then unused[#unused + 1] = key end
  end
  if #unused > 0 then
    print("  note  以下动效已实现但当前没有语义名指向（备用，不算错）：")
    for _, k in ipairs(unused) do print("          " .. k) end
  end
end

--------------------------------------------------------------------------------
-- ⑤ 每条动效的参数得站得住
--      · build_timeline 要求关键帧 >= 2 个，否则直接返回空表 → 不动
--      · dur 必须 > 0，否则每段被压成 0.01s（等于没动画）
--      · ch 只能是 build_timeline 认识的通道
--------------------------------------------------------------------------------
local CHANNELS = { scale = true, pos_x = true, pos_y = true, rot = true }
do
  for _, key in ipairs(order) do
    local t = entries[key].text
    local dur = tonumber(t:match("dur%s*=%s*([%d%.]+)"))
    ok(dur ~= nil and dur > 0, key .. " 的 dur 缺失或不合法：" .. tostring(dur))

    local nkeys = 0
    for _ in t:gmatch("{%s*[%-%d%.]+%s*,") do nkeys = nkeys + 1 end
    ok(nkeys >= 2, key .. " 的关键帧只有 " .. nkeys .. " 个（build_timeline 需要 >= 2）")

    local ch = t:match("ch%s*=%s*\"([%w_]+)\"") or "scale"
    ok(CHANNELS[ch] == true, key .. " 用了 build_timeline 不认识的通道：" .. ch)
  end
end

print(string.format("effects_wiring: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
