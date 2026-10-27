--[[----------------------------------------------------------------------------
  lua/tut_verify.lua —— 教程控件（`teach.*`）运行期自检 · v2（2026-10-21）

  为什么要有这个文件（要解决的具体事故）：
    「教程 UI 并入存档」这条线反复返工，而失败形态**全都是静默的**：
      · 控件没进树   ⇒ `find` 拿到 nil ⇒ 上游 pcall 降级（少一块）⇒ 玩家看到空白；
      · 同名控件多条 ⇒ 编辑器报「界面控件里的开关控件GUID重复」，
        脚本 `find` 取到哪一条**看遍历顺序**；
      · 父级挂错     ⇒ 控件在，但被父级的 0×0 / 隐藏 / 裁剪吃掉；
      · 尺寸 0       ⇒ 引擎按父级矩形裁剪 ⇒ 整片教程被裁没（477 骨架踩过这个坑）；
      · 该显示却没显示 ⇒ `tutorial:open_ui()` 明明调过，画面还是一片空。
    ⇒ 本模块把「教程控件树应该长什么样」写成一张**期望清单**，在运行期逐条核对，
      用**一行日志**把结论喊出来（真机日志首屏就能看到），而不是等人看画面猜。

  ★★★ 本模块**绝不创建任何控件**（用户明确要求：脚本里不要有创建控件这种操作）★★★
    具体到代码：本文件里**没有**、也**不许**出现下面这些调用 ——
      · `game.InstantiateClientUIControl(...)`（按模板索引造控件）
      · 任何 `game.*ClientUIControl*` 的创建 / 克隆接口
      · 控件自己的 `Clone()` / `Instantiate()` 之类
    **为什么这条必须是硬的**：自检的唯一用途是「**证明存档里已经有这棵树**」。
    一旦自检自己能造控件，它就会把"缺控件"验成"通过"（临时造一个补上再核对）
    ⇒ 自检变成**假绿发生器**，比没有自检更糟。所以：
      · 取控件的能力由调用方**注入**（`find`），模块连 `game` 全局都不读；
      · 离线测试里挂一个"一调就报错"的假 `game.InstantiateClientUIControl`，
        跑完断言调用次数 = **0**（`tests/tut_verify.lua` 用例 ⑦）。

  ★ 只读：除了 `M.log` 的那一行 `print`，本模块**不写任何控件属性**
    （不改尺寸 / 显隐 / 文本 / 父级 / 层级）⇒ 可以随时反复跑，没有副作用。

  ★ 依赖：无。不 require、不用 io/os/debug，Lua 5.3 语法。
    （本地 lua.exe 是 5.4，沙箱是 5.3 —— 本文件两边都能过：
      `node tools/lua53check/check.cjs lua/tut_verify.lua --run`）

  ────────────────────────────────────────────────────────────────────────────
  API（详见 docs/脚本侧检查-教程控件-2026-10-21.md）：
    M.run(opts)    -> res            纯计算，不打日志
    M.log(res)     -> line           打**一行**结论（OK / FAIL），返回这行原文
    M.check(opts)  -> res            run + log；有警告时再补一行警告
    M.TUTORIAL_EXPECT                内置清单（62 条 `teach.*`，来自 486 的生成器结构）

    opts = {
      find  = function(name) -> ctrl|nil   必填（也接受带 `:find(name)` 的对象，例如适配器）
      all   = function(name) -> {ctrl,...} 可选：同名**全部**控件（判重名最准）
      roots = function() -> {root,...}     可选：客户端控件树根表；没给 all 时用它自己走树
      expect = { {name=, parent=, visible=, min_size=}, ... }   可选（默认 TUTORIAL_EXPECT）
    }
    res = {
      ok = boolean,                 -- 没有 error 就是 true
      errors = { {name=, kind=, text=}, ... },     -- 每条都带控件名
      warnings = { {name=, kind=, text=}, ... },
      found = number,               -- 找得到的期望条目数（重名也算找到）
      total = number,               -- 期望清单条目数
    }
----------------------------------------------------------------------------]]--

local M = {}

M.VERSION = "v3-2026-10-21"     -- v3：清单换成 486/v290 的 62 条（页标 / 按钮图元 / 副标题 / 点击继续）

-- ─────────────────────────────────────────────────────────────────────────────
-- 内置期望清单：教程控件（`teach.*`）62 条
--
-- 名字 / 父级的来源（两个独立来源对上了，不是猜的）：
--   ① `lua/tutorial_ui.lua` 头部那张控件表（模块实际按这些名字取控件）；
--   ② `tools/gil/gen_tutorial_teach.mjs` 里每条 `add({ name=…, parent=… })`
--      （存档里的控件名**就是全名**：`teach.text.l1.body.1` 是自己的名字，
--        所以这里按全名登记；父级 = 生成器里那份 parent 链）。
--   ★ v290 新增的 36 条（三套 × 12）全部来自 `486-教程teach-v290.gil`：
--     页标 `dot.i.on/.off`（6）、`btn.click`（1）、`btn.prev.icon` / `btn.next.icon` / `btn.close.x`（3）、
--     文本区 `subtitle` / `btn.click`（2）。
--
-- 字段（都可选，除 name）：
--   name      string              控件名（**必须与存档逐字一致**，改名两处一起改）
--   parent    string              期望父控件名
--   visible   boolean             true ⇒ 必须可见；false ⇒ 必须隐藏（按 warning 处理）
--   min_size  number | {w=,h=}    最小尺寸（不写就只查"尺寸 0"）
--
-- ★ 这里**故意不写 visible / min_size**：
--   · 显隐随运行时状态变（open_ui / close / 翻页 / 页标高亮）；
--   · 尺寸以**编辑器实测**为准，写死会在换画布 / 换分辨率时变成假警报。
--   要加就在调用处传自己的清单（`run{ expect = {...} }`），或用
--   `{ name = "teach", parent = "root", min_size = { w = 1200, h = 700 } }` 这种写法。
--   ⚠️ 但"尺寸 0"是**无条件**查的（哪怕没写 min_size）—— 那正是把整片教程裁没的坑。
-- ─────────────────────────────────────────────────────────────────────────────
M.TUTORIAL_EXPECT = (function()
  local out = {
    { name = "teach", parent = "root" },
    { name = "teach.text", parent = "teach" },
  }
  -- ★ 三套各自独立（首页 home / 第一关 l1 / 第二关 l2）——每套都查按钮、页标、图元与三页正文
  for _, tag in ipairs({ "home", "l1", "l2" }) do
    local base = "teach." .. tag
    local txt = "teach.text." .. tag
    local list = {
      { name = base, parent = "teach" },
      { name = base .. ".btn.prev", parent = base },
      { name = base .. ".btn.next", parent = base },
      { name = base .. ".btn.close", parent = base },
      -- v290：底部「点击继续」按钮（等价 next()）
      { name = base .. ".btn.click", parent = base },
      -- v290：按钮里的图元（箭头 / 关闭小 x）—— 父级是**按钮**，不是面板
      { name = base .. ".btn.prev.icon", parent = base .. ".btn.prev" },
      { name = base .. ".btn.next.icon", parent = base .. ".btn.next" },
      { name = base .. ".btn.close.x", parent = base .. ".btn.close" },
      -- 文本区
      { name = txt, parent = "teach.text" },
      { name = txt .. ".body.1", parent = txt },
      { name = txt .. ".body.2", parent = txt },
      { name = txt .. ".body.3", parent = txt },
      -- v290：副标题 + 「点击继续」的按钮字
      { name = txt .. ".subtitle", parent = txt },
      { name = txt .. ".btn.click", parent = txt },
    }
    -- v290：三颗菱形页标，每颗两条记录（当前页 on / 其它页 off）
    for i = 1, 3 do
      list[#list + 1] = { name = base .. ".dot." .. i .. ".on", parent = base }
      list[#list + 1] = { name = base .. ".dot." .. i .. ".off", parent = base }
    end
    for _, e in ipairs(list) do out[#out + 1] = e end
  end
  return out
end)()

-- ─────────────────────────────────────────────────────────────────────────────
-- 小工具
-- ─────────────────────────────────────────────────────────────────────────────

-- 日志里打数字一律 `%.0f`，**绝不用 `%d`**：
--   本项目的真机事故 —— `GetSizeDelta()` / `GetUICanvasSize()` 给回来的是**浮点**，
--   而 Lua 5.3 的 `string.format("%d", 108.0)` 直接抛
--   `bad argument #2 to 'format' (number has no integer representation)`。
--   自检本来就是为了"出事时喊一句"，它自己绝不能因为格式化而抛。
local function num(v)
  if type(v) ~= "number" then return tostring(v) end
  if v ~= v then return "nan" end          -- NaN（math.isnan 不可假设存在）
  return string.format("%.0f", v)
end

-- 一行日志的纪律：任何注入回来的错误字符串都可能带换行 → 压成一行再截断，
-- 否则 FAIL 那行会被拆散，真机首屏就看不全了。
local function oneline(s)
  s = tostring(s == nil and "" or s):gsub("[\r\n]+", " ")
  if #s > 80 then s = s:sub(1, 80) .. "…" end
  return s
end

local function push_err(res, name, kind, detail)
  local text = tostring(name) .. "=" .. tostring(kind)
  if detail ~= nil and detail ~= "" then text = text .. "(" .. oneline(detail) .. ")" end
  res.errors[#res.errors + 1] = { name = tostring(name), kind = tostring(kind), text = text }
  return text
end

local function push_warn(res, name, kind, detail)
  local text = tostring(name) .. "=" .. tostring(kind)
  if detail ~= nil and detail ~= "" then text = text .. "(" .. oneline(detail) .. ")" end
  res.warnings[#res.warnings + 1] = { name = tostring(name), kind = tostring(kind), text = text }
  return text
end

-- 两个"转调"小函数：让 pcall 能带着变参去调（Lua 5.3 里 `...` 不能出现在
-- 非变参的嵌套闭包里 —— 踩过：`pcall(function() return fn(v, ...) end)` 直接编译不过）。
local function call_vararg(target, ...) return target(...) end
local function call_method(fn, self, ...) return fn(self, ...) end

-- 注入值 → "调用它就会返回值" 的普通函数。两种写法都认：
--   · 普通函数                      → 直接调（`find(name)`）
--   · 表（带同名方法，例如适配器）   → 冒号调（`Adapter:find(name)`）
-- 返回 nil = 这个能力没注入（只有 find 是必填的）。
local function make_callable(v, method_names)
  if type(v) == "function" then
    return function(...)
      local ok, a, b = pcall(call_vararg, v, ...)
      if not ok then return nil, tostring(a) end
      return a, b
    end
  end
  if type(v) == "table" then
    for i = 1, #method_names do
      local m = method_names[i]
      local okm, fn = pcall(function() return v[m] end)
      if okm and type(fn) == "function" then
        return function(...)
          local ok, a, b = pcall(call_method, fn, v, ...)
          if not ok then return nil, tostring(a) end
          return a, b
        end
      end
    end
  end
  return nil
end

local function ctrl_name(c)
  local nm
  pcall(function() nm = c.name end)
  if type(nm) == "string" and nm ~= "" then return nm end
  return "?"
end

-- 可见性：项目里**验证过可读**的写法就是 `ctrl.visible`（字段，不是方法）。
-- 读不到（没这字段 / 抛错）时返回 nil + 原因 —— 只降级成警告，不判红：
-- 不同控件类型暴露的字段可能不一样，凭这个报错会变成假警报。
local function read_visible(c)
  local v
  local ok = pcall(function() v = c.visible end)
  if not ok then return nil, "visible 读取抛错" end
  if v == nil then return nil, "控件没暴露 visible" end
  if v == true then return true end
  if v == false then return false end
  return (v and true or false)             -- 非布尔但可当真值用的，按真处理
end

-- 尺寸：项目里的两种形态都要认（**不许发明新接口**）：
--   · 真机：`local w, h = ctrl:GetSizeDelta()`，返回浮点数；
--   · 模拟器桥接：返回**表** `{x=w, y=h}`（main.lua:92 与适配器 L130 都写了这个分支）。
local function read_size(c)
  local fn = nil
  pcall(function() fn = c.GetSizeDelta end)
  if type(fn) ~= "function" then return nil, nil, "控件没有 GetSizeDelta" end
  local a, b
  local ok = pcall(function() a, b = c:GetSizeDelta() end)
  if not ok then return nil, nil, "GetSizeDelta 抛错" end
  if type(a) == "table" then a, b = a.x, a.y end
  local w, h = tonumber(a), tonumber(b)
  if w == nil or h == nil then return nil, nil, "GetSizeDelta 返回值不是数字" end
  return w, h
end

-- 父控件：项目里的读法（main.lua:1231-1233 同款）——
-- 先读字段 `parent`，读不到再试 `GetParent()`。
local function read_parent(c)
  local up
  pcall(function() up = c.parent end)
  if up == nil then pcall(function() up = c:GetParent() end) end
  return up
end

-- 往上找"第一个明确被隐藏的祖先"，返回它的名字（找不到 → nil）。
-- 为什么要查祖先：本项目踩过 —— 控件自己 visible=true，父级被关掉，
-- 画面上依然什么都没有（"主页整个消失"就是这么来的）。
local function hidden_ancestor(c, max_depth)
  local cur = read_parent(c)
  local d = 0
  while cur ~= nil and d < (max_depth or 8) do
    local vis
    pcall(function() vis = cur.visible end)
    if vis == false then return ctrl_name(cur) end
    cur = read_parent(cur)
    d = d + 1
  end
  return nil
end

-- 整棵（多根）树里数这个名字出现几次（重名判据的兜底路）。
-- 只靠项目里验证过的两个读法：`ctrl.name` 与 `ctrl:GetChildren()`。
local function count_in_tree(roots, want)
  local n = 0
  local function walk(c, depth)
    if c == nil or depth > 24 then return end
    local nm
    pcall(function() nm = c.name end)
    if nm == want then n = n + 1 end
    local kids
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  if type(roots) == "table" then
    for i = 1, #roots do walk(roots[i], 0) end
  end
  return n
end

-- 只给 find 时的兜底：在**同一个父级**下数同名子控件。
-- （存档并入 / 手工复制 造成的重名，绝大多数就是同级两份。）
local function count_siblings(c, want)
  local up = read_parent(c)
  if up == nil then return nil end
  local kids
  pcall(function() kids = up:GetChildren() end)
  if type(kids) ~= "table" then return nil end
  local n = 0
  for i = 1, #kids do
    local nm
    pcall(function() nm = kids[i].name end)
    if nm == want then n = n + 1 end
  end
  return n
end

local function parse_min(v)
  if type(v) == "number" then return v, v end
  if type(v) == "table" then
    local w = v.w or v.width or v[1]
    local h = v.h or v.height or v[2]
    if h == nil then h = w end
    if type(w) == "number" and type(h) == "number" then return w, h end
  end
  return nil, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- M.run —— 逐条核对，返回结构化结果（不打日志）
-- ─────────────────────────────────────────────────────────────────────────────
function M.run(opts)
  if type(opts) ~= "table" then opts = {} end

  local res = { ok = false, errors = {}, warnings = {}, found = 0, total = 0 }

  local find = make_callable(opts.find, { "find", "Find" })
  if find == nil then
    push_err(res, "(opts.find)", "配置错误", "必须注入 find(name) 或带 :find 的对象")
    return res
  end

  local expect = opts.expect
  if expect == nil then expect = M.TUTORIAL_EXPECT end
  if type(expect) ~= "table" then
    push_err(res, "(opts.expect)", "配置错误", "期望清单必须是数组")
    return res
  end
  res.total = #expect
  if res.total == 0 then
    -- 空清单 ⇒ 0/0 的"全绿"是假绿，必须判红（自检最怕的就是报平安）
    push_err(res, "(opts.expect)", "配置错误", "期望清单为空")
    return res
  end

  -- 判重名的三档能力：all（最准）> roots（自己走树）> 只查同级（兜底）
  local all = make_callable(opts.all, { "all", "find_all", "FindAll" })
  local roots = make_callable(opts.roots, { "roots", "get_roots", "GetRoots" })
  local dupe_mode = "siblings"
  if all ~= nil then
    dupe_mode = "all"
  elseif roots ~= nil then
    dupe_mode = "roots"
  else
    push_warn(res, "(配置)", "重名只查同级",
      "注入 all(名)->列表 或 roots()->根表 才能查全树的重名")
  end

  local seen = {}
  for i = 1, #expect do
    local e = expect[i]
    local name = nil
    if type(e) == "table" then name = e.name end

    if type(name) ~= "string" or name == "" then
      push_warn(res, "(expect[" .. i .. "])", "清单条目没名字", "跳过")
    elseif seen[name] then
      push_warn(res, name, "清单重复登记", "同一名字只查一次")
    else
      seen[name] = true

      local ctrl, ferr = find(name)
      if ferr ~= nil then
        push_err(res, name, "取控件抛错", ferr)
      elseif ctrl == nil then
        push_err(res, name, "缺失")
      else
        res.found = res.found + 1

        -- ① 重名：同名多条 ⇒ 脚本取到哪一条不确定（编辑器报 GUID 重复就是这个）
        local ndup = nil
        if dupe_mode == "all" then
          local list = all(name)
          if type(list) == "table" then ndup = #list end
        elseif dupe_mode == "roots" then
          local rs = roots()
          if type(rs) == "table" then ndup = count_in_tree(rs, name) end
        else
          ndup = count_siblings(ctrl, name)
        end
        if ndup ~= nil and ndup > 1 then
          push_err(res, name, "重名", ndup .. " 条")
        end

        -- ② 父级：挂错父级 ⇒ 被父级的 0×0 / 隐藏 / 裁剪吃掉
        if type(e.parent) == "string" and e.parent ~= "" then
          local up = read_parent(ctrl)
          local actual = nil
          if up ~= nil then actual = ctrl_name(up) end
          if actual ~= e.parent then
            push_err(res, name, "父不对",
              "期望 " .. e.parent .. " 实际 " .. tostring(actual or "(无父控件)"))
          end
        end

        -- ③ 尺寸：0 尺寸是被"按父级矩形裁剪"吃掉的元凶；min_size 是可选的下限
        local w, h, why = read_size(ctrl)
        if w == nil then
          push_warn(res, name, "读不到尺寸", why)
        elseif w <= 0 or h <= 0 then
          push_err(res, name, "尺寸 0", num(w) .. "x" .. num(h))
        else
          local mw, mh = parse_min(e.min_size)
          if mw ~= nil and (w < mw - 0.01 or h < mh - 0.01) then
            push_err(res, name, "尺寸不足",
              num(w) .. "x" .. num(h) .. " < " .. num(mw) .. "x" .. num(mh))
          end
        end

        -- ④ 显隐：期望可见却看不见（含"自己可见但祖先被关"这一层）
        if e.visible == true then
          local vis, vwhy = read_visible(ctrl)
          if vis == nil then
            push_warn(res, name, "读不到可见性", vwhy)
          elseif vis == false then
            push_err(res, name, "不可见")
          else
            local anc = hidden_ancestor(ctrl, 8)
            if anc ~= nil then
              push_err(res, name, "不可见", "祖先 " .. anc .. " 隐藏")
            end
          end
        elseif e.visible == false then
          local vis = read_visible(ctrl)
          if vis == true then
            -- "该藏没藏"只是多显示一块，不影响功能 ⇒ 警告
            push_warn(res, name, "该藏没藏")
          end
        end
      end
    end
  end

  res.ok = (#res.errors == 0)
  return res
end

-- ─────────────────────────────────────────────────────────────────────────────
-- M.log —— 一行结论（真机日志首屏要能一眼看到）
--   通过：[tut] 自检 OK 14/14
--   失败：[tut] 自检 FAIL 2 项: frame.btn=缺失; frame.tab=父不对(期望 frame.panel 实际 frame.root)
--   只 print，不 printerr：这不是引擎错误，是"存档和脚本对不上"的诊断。
-- ─────────────────────────────────────────────────────────────────────────────
local MAX_ERR_ITEMS = 8      -- 一行太长真机日志会被截断；多出来的只报条数

function M.log(res)
  if type(res) ~= "table" then return nil end

  local line
  if res.ok then
    line = string.format("[tut] 自检 OK %d/%d", res.found or 0, res.total or 0)
  else
    local errs = res.errors or {}
    local parts = {}
    local shown = 0
    for i = 1, #errs do
      shown = shown + 1
      if i <= MAX_ERR_ITEMS then
        parts[#parts + 1] = tostring(errs[i].text or errs[i].name or "?")
      end
    end
    if shown > MAX_ERR_ITEMS then
      parts[#parts + 1] = "…另有 " .. (shown - MAX_ERR_ITEMS) .. " 项"
    end
    line = "[tut] 自检 FAIL " .. shown .. " 项: " .. table.concat(parts, "; ")
  end

  if print then print(line) end
  return line
end

-- ─────────────────────────────────────────────────────────────────────────────
-- M.check —— run + log（入口最省事的一行式接线）
--   警告单独一行，最多列 3 条：警告不判红，但"重名只查了同级"这种话
--   必须出现在日志里，否则又是一次静默降级。
-- ─────────────────────────────────────────────────────────────────────────────
function M.check(opts)
  local res = M.run(opts)
  M.log(res)

  local ws = res.warnings or {}
  if #ws > 0 and print then
    local parts = {}
    for i = 1, math.min(#ws, 3) do
      parts[#parts + 1] = tostring(ws[i].text or "?")
    end
    local tail = ""
    if #ws > 3 then tail = "（另有 " .. (#ws - 3) .. " 条）" end
    print("[tut] 自检 警告 " .. #ws .. " 条: " .. table.concat(parts, "; ") .. tail)
  end
  return res
end

return M
