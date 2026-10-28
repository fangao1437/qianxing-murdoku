--[[----------------------------------------------------------------------------
  tests/tutorial_ui.lua —— 玩法说明浮层（`teach.*`）的离线回归（v290）

  钉这些事（全部双向）：
    ① 构造与字段：tag / pages / page / open / inited / bound
    ② init：绑 `teach.lN.btn.prev|next|close|**click**` **四个**键；**root 与 text 一起藏**；只跑一次
    ③ open_ui / close：面板与文本区域**一起**显隐；只显示当前页正文
    ④ 翻页：body 跟着切；`go` **夹紧** 1..pages（0→1、99→pages、数字字符串也认）
    ⑤ `go` **只切 body 与页标**：不把 root / text 打开；`M["goto"]` 是同一个函数
    ⑥ 按钮回调真的接上了：点 prev / next / close / **click** 有效
    ⑦ 双实例（l1 / l2）**互不干扰**：翻页 / 显隐 / 关闭 / 页标都各管各的
    ⑧ `pages` 由入口传、**不写死 3**：pages 小的时候多出来的 body / dot 不归模块管
    ⑨ 缺控件只降级不崩：空树 / 只有 root 的树，init 与所有方法都不许抛错
    ⑩ **页标是两套图互斥显隐**（v290 新增）：第 page 页那颗 `dot.i.on` 可见、其余 `dot.i.off` 可见；
       且全程**没有任何一处写文字**、**没有创建/销毁控件**（用户要求做成可验证）。
    ⑪ **脚本从未写过任何 text**：
       假控件装了会记账的 text setter（`.text=` 与 `SetText` 都记），跑完断言写入次数 = 0；
       另挂一个"一调就记错"的假 `game.InstantiateClientUIControl`，断言创建次数 = 0。

  跑法：lua tests/tutorial_ui.lua
  本机 lua.exe 是 5.4；沙箱语义按 5.3（`goto` 是保留字 —— 所以 API 用 `go`）。
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua",
  package.path,
}, ";")

local Tutorial = require("tutorial_ui")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end
local function sec(t) print("\n== " .. t .. " ==") end

-- ── 记账器 ────────────────────────────────────────────────────────────────
local text_writes = 0     -- 脚本（以及任何东西）写 text 的次数
local bind_calls  = 0     -- AddCursorEventListener 被调用次数
local created     = 0     -- game.InstantiateClientUIControl 被调用次数
local destroyed   = 0     -- game.DestroyClientUIControl 被调用次数

-- ── 假控件 ────────────────────────────────────────────────────────────────
-- 与旧版同款（手搭假树的项目惯例），多了三样：
--   ① `text` 不在表里 ⇒ 任何 `.text = ...` 都走 __newindex 被记账（用例⑩）
--   ② `SetText` 也记账（用例⑩）
--   ③ `GetChild` 是**精确名匹配**（与官方文档一致：按"名称为 name 的直接子控件"）
local function ctrl(name, kids)
  local x = { name = name, _kids = kids or {}, visible = true, active = true }
  setmetatable(x, {
    __newindex = function(t, k, v)
      if k == "text" then text_writes = text_writes + 1 end
      rawset(t, k, v)
    end,
  })
  x.GetChildren = function() return x._kids end
  x.GetChild = function(_, n)
    for _, k in ipairs(x._kids) do if k.name == n then return k end end
    return nil
  end
  x.SetVisible = function(_, v) x.visible = v end
  x.SetActive = function(_, v) x.active = v end
  x.SetText = function(_, v)
    text_writes = text_writes + 1
    rawset(x, "_text", v)
  end
  x.AddCursorEventListener = function(_, _, cb)
    bind_calls = bind_calls + 1
    rawset(x, "_click", cb)
  end
  return x
end

local function add(parent, ...)
  for _, k in ipairs({ ... }) do
    k.parent = parent
    parent._kids[#parent._kids + 1] = k
  end
  return parent
end

-- 从树里摘掉一个控件（用来造"控件缺失"的场景，例如页标没进树）
local function detach(child)
  if child == nil or child.parent == nil then return end
  local kids = child.parent._kids
  for i = #kids, 1, -1 do
    if kids[i] == child then table.remove(kids, i) end
  end
  child.parent = nil
end

-- ── 按 486（v290）的结构搭假树（名字与存档逐字一致）────────────────────────
local function make_tree()
  local root_ctrl = ctrl("root")
  local teach = ctrl("teach")
  add(root_ctrl, teach)

  local function one_set(tag)
    local l = ctrl("teach." .. tag)
    add(teach, l)
    add(l, ctrl("bg"), ctrl("page"))      -- 生成器里这是**子控件记录**（短名 bg / page）
    add(l,
      ctrl("teach." .. tag .. ".btn.prev", { ctrl("bg"), ctrl("teach." .. tag .. ".btn.prev.icon") }),
      ctrl("teach." .. tag .. ".btn.next", { ctrl("bg"), ctrl("teach." .. tag .. ".btn.next.icon") }),
      ctrl("teach." .. tag .. ".btn.close", { ctrl("bg"), ctrl("teach." .. tag .. ".btn.close.x") }),
      ctrl("teach." .. tag .. ".btn.click", { ctrl("bg") }))
    -- v290 页标：三颗菱形，每颗两条记录（当前页 on / 其它 off）
    for i = 1, 3 do
      add(l, ctrl("teach." .. tag .. ".dot." .. i .. ".on"),
        ctrl("teach." .. tag .. ".dot." .. i .. ".off"))
    end
    return l
  end

  local l1 = one_set("l1")
  local l2 = one_set("l2")

  local text = ctrl("teach.text")
  add(teach, text)
  for _, side in ipairs({ "l1", "l2" }) do
    local box = ctrl("teach.text." .. side)
    add(text, box)
    add(box, ctrl("teach.text." .. side .. ".title"))
    add(box, ctrl("teach.text." .. side .. ".subtitle"))
    for i = 1, 3 do
      add(box, ctrl("teach.text." .. side .. ".body." .. i))
    end
    add(box,
      ctrl("teach.text." .. side .. ".btn.prev"),
      ctrl("teach.text." .. side .. ".btn.next"),
      ctrl("teach.text." .. side .. ".btn.close"),
      ctrl("teach.text." .. side .. ".btn.click"))
  end

  return { root = root_ctrl, teach = teach, l1 = l1, l2 = l2, text = text }
end

-- ── 假适配器：find = 全树按名 DFS；sub = 父.GetChild(子名)（精确名）─────────
local TREE = make_tree()
local adapter = {}
function adapter:find(name)
  local hit = nil
  local function walk(n)
    if hit ~= nil or n == nil then return end
    if n.name == name then hit = n; return end
    for _, k in ipairs(n._kids) do walk(k) end
  end
  walk(TREE.root)
  return hit
end
function adapter:sub(parent_name, child_name)
  local p = self:find(parent_name)
  if p == nil then return nil end
  return p:GetChild(child_name)
end

local function count_bound(inst)
  local n = 0
  for _ in pairs(inst.bound) do n = n + 1 end
  return n
end

-- ── 环境：Enum（绑定要用）+ 一调就记错的假 game ────────────────────────────
_G.Enum = { CursorEventType = { CursorClick = "click" } }
_G.game = {
  InstantiateClientUIControl = function()
    created = created + 1
    error("禁止创建控件：教程浮层的控件全在存档里")
  end,
  DestroyClientUIControl = function()
    destroyed = destroyed + 1
    error("禁止销毁控件")
  end,
}

-- ══════════════════════════════════════════════════════════════════════════
sec("① 构造与字段")
local l1 = Tutorial.new(adapter, { tag = "l1", root = "teach.l1", text = "teach.text.l1", pages = 3 })
ok(l1.tag == "l1", "① tag = l1（实测 " .. tostring(l1.tag) .. "）")
ok(l1.pages == 3, "① pages = 3（入口传的，不写死）")
ok(l1.page == 1 and l1.open == false and l1.inited == false, "① 初始 page=1 / open=false / inited=false")
ok(type(l1.bound) == "table" and count_bound(l1) == 0, "① bound 是空表")

-- ══════════════════════════════════════════════════════════════════════════
sec("② init：绑四键 + root/text 一起藏 + 只跑一次")
local bind0 = bind_calls
l1:init()
ok(l1.inited == true, "② inited = true")
ok(l1.page == 1, "② page 回到 1")
ok(TREE.l1.visible == false, "② 面板 teach.l1 已隐藏")
ok(TREE.text:GetChild("teach.text.l1").visible == false, "② 文本区域 teach.text.l1 已隐藏（和面板一起）")
ok(count_bound(l1) == 4, "② bound 里 4 个按钮（实测 " .. count_bound(l1) .. "）")
ok(bind_calls - bind0 == 4, "② 只绑了 4 次（实测 " .. (bind_calls - bind0) .. "）")
for _, n in ipairs({ "prev", "next", "close", "click" }) do
  local btn = adapter:find("teach.l1.btn." .. n)
  ok(type(btn and btn._click) == "function", "② teach.l1.btn." .. n .. " 绑上了点击回调")
end
l1:init()                                   -- 再 init 一次
ok(bind_calls - bind0 == 4, "② 重复 init 不重复绑定（实测 " .. (bind_calls - bind0) .. " 次）")
ok(l1.inited == true and count_bound(l1) == 4, "② 重复 init 后状态不变")

-- 正文控件取法：存档里的子控件名是全名
local b1 = adapter:find("teach.text.l1.body.1")
local b2 = adapter:find("teach.text.l1.body.2")
local b3 = adapter:find("teach.text.l1.body.3")
ok(b1 ~= nil and b2 ~= nil and b3 ~= nil, "② 三页正文控件都在树里")

-- v290 页标控件：每颗点两条记录
local function dot(i, which) return adapter:find("teach.l1.dot." .. i .. "." .. which) end
local dots_ok = true
for i = 1, 3 do
  if dot(i, "on") == nil or dot(i, "off") == nil then dots_ok = false end
end
ok(dots_ok, "② 三颗页标的 on/off 六条记录都在树里")

-- ══════════════════════════════════════════════════════════════════════════
sec("③ open_ui / close：root 与 text 一起显隐")
l1:open_ui()
ok(l1.open == true, "③ open = true")
ok(TREE.l1.visible == true, "③ 面板 teach.l1 显示")
ok(TREE.text:GetChild("teach.text.l1").visible == true, "③ 文本区域 teach.text.l1 显示")
ok(b1.visible == true and b2.visible == false and b3.visible == false,
  "③ 只显示第 1 页正文（b1=true b2=false b3=false）")
l1:close()
ok(l1.open == false, "③ close 后 open = false")
ok(TREE.l1.visible == false and TREE.text:GetChild("teach.text.l1").visible == false,
  "③ close 把面板与文本区域一起藏")
-- ══════════════════════════════════════════════════════════════════════════
sec("④ 翻页与夹紧")
l1:open_ui()
l1:next()
ok(l1.page == 2 and b2.visible == true and b1.visible == false and b3.visible == false,
  "④ next ⇒ 第 2 页，只有 body.2 可见")
l1:next(); l1:next()
ok(l1.page == 3, "④ 到第 3 页后不再加（实测 " .. l1.page .. "）")
l1:prev(); l1:prev(); l1:prev()
ok(l1.page == 1, "④ 到第 1 页后不再减（实测 " .. l1.page .. "）")
l1:go(0)
ok(l1.page == 1, "④ go(0) 夹紧到 1")
l1:go(99)
ok(l1.page == 3, "④ go(99) 夹紧到 pages")
l1:go("2")
ok(l1.page == 2, "④ go(\"2\") 认数字字符串")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑤ go 只切 body；goto 别名")
ok(Tutorial["goto"] == Tutorial.go, "⑤ M[\"goto\"] 与 M.go 是同一个函数")
l1:close()                                  -- root/text 先藏起来
l1:go(2)
ok(l1.open == false, "⑤ go 不改 open 状态")
ok(TREE.l1.visible == false and TREE.text:GetChild("teach.text.l1").visible == false,
  "⑤ go 不把 root / text 打开（只切 body）")
ok(b2.visible == true and b1.visible == false, "⑤ body 跟着 go 切")
ok(l1["goto"](l1, 3) == l1 and l1.page == 3, "⑤ inst[\"goto\"](inst, n) 是 go 的别名")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑥ 按钮回调")
l1:go(3)
adapter:find("teach.l1.btn.prev")._click()
ok(l1.page == 2, "⑥ 点 prev ⇒ 2（实测 " .. l1.page .. "）")
adapter:find("teach.l1.btn.next")._click()
ok(l1.page == 3, "⑥ 点 next ⇒ 3（实测 " .. l1.page .. "）")
adapter:find("teach.l1.btn.close")._click()
ok(l1.open == false and TREE.l1.visible == false, "⑥ 点 close ⇒ 收起")
-- v290：底部「点击继续」是**同一条 next()**
l1:open_ui(); l1:go(1)
adapter:find("teach.l1.btn.click")._click()
ok(l1.page == 2 and l1.open == true, "⑥ 点 btn.click ⇒ 等价 next()（第 2 页，且不会关掉）")
adapter:find("teach.l1.btn.click")._click(); adapter:find("teach.l1.btn.click")._click()
ok(l1.page == 3, "⑥ 末页再点 btn.click 只夹紧（实测 " .. l1.page .. "）")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑦ 双实例互不干扰（两关各一套）")
local l2 = Tutorial.new(adapter, { tag = "l2", root = "teach.l2", text = "teach.text.l2", pages = 3 })
l2:init()
ok(l2.inited == true and TREE.l2.visible == false, "⑦ l2 init 后自己也藏着")
l1:open_ui(); l1:go(2)
l2:open_ui(); l2:go(3)
ok(l1.page == 2 and l2.page == 3, "⑦ 各自页码：l1=2 / l2=3")
local l2b1 = adapter:find("teach.text.l2.body.1")
local l2b2 = adapter:find("teach.text.l2.body.2")
local l2b3 = adapter:find("teach.text.l2.body.3")
ok(l2b3.visible == true and l2b1.visible == false and l2b2.visible == false,
  "⑦ l2 只有 body.3 可见")
ok(b2.visible == true and b3.visible == false, "⑦ l1 仍是 body.2 可见（没被 l2 改到）")
ok(TREE.l1.visible == true and TREE.l2.visible == true, "⑦ 两个面板都显示")
l2:close()
ok(TREE.l2.visible == false and TREE.text:GetChild("teach.text.l2").visible == false,
  "⑦ 关 l2 只藏 l2")
ok(TREE.l1.visible == true and TREE.text:GetChild("teach.text.l1").visible == true,
  "⑦ l1 不受影响")
l2:go(1)
adapter:find("teach.l1.btn.next")._click()
ok(l1.page == 3 and l2.page == 1, "⑦ 点 l1 的 next 只动 l1（l1=3 / l2=1）")
ok(l2b1.visible == true and l2b3.visible == false, "⑦ l2 的 body 也跟着自己的 go(1)")

-- v290 页标也各管各的：l1 停在第 3 页 ⇒ l1 第 3 颗 on；l2 停在第 1 页 ⇒ l2 第 1 颗 on
local function dot2(i, which) return adapter:find("teach.l2.dot." .. i .. "." .. which) end
ok(dot(3, "on").visible == true and dot(1, "on").visible == false and dot(1, "off").visible == true,
  "⑦ l1 页标跟着自己的第 3 页（dot.3.on 亮、dot.1.off 亮）")
ok(dot2(1, "on").visible == true and dot2(3, "on").visible == false and dot2(3, "off").visible == true,
  "⑦ l2 页标跟着自己的第 1 页（没被 l1 改到）")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑧ pages 由入口传（不写死 3；多余 body / dot 不归模块管）")
TREE = make_tree()
local l1b = Tutorial.new(adapter, { tag = "l1b", root = "teach.l1", text = "teach.text.l1", pages = 2 })
l1b:init()
local nb1 = adapter:find("teach.text.l1.body.1")
local nb2 = adapter:find("teach.text.l1.body.2")
local nb3 = adapter:find("teach.text.l1.body.3")
nb3.visible = true                          -- 故意让"多出来的那页"是显示状态
local nd3on = adapter:find("teach.l1.dot.3.on")
nd3on.visible = true                        -- 多出来的那颗点也故意亮着
l1b:open_ui()
ok(l1b.pages == 2, "⑧ pages = 2（模块照传进来的值走）")
ok(nb1.visible == true and nb2.visible == false, "⑧ 前两页照常按当前页切")
ok(nb3.visible == true, "⑧ pages 之外的 body.3 保持原状（模块不碰）")
ok(nd3on.visible == true, "⑧ pages 之外的 dot.3 也保持原状（模块不碰）")
l1b:go(99)
ok(l1b.page == 2 and nb2.visible == true, "⑧ go(99) 夹紧到 pages=2")
ok(nb3.visible == true, "⑧ 夹紧后仍不碰 body.3")
ok(nd3on.visible == true, "⑧ 夹紧后仍不碰 dot.3")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑨ 缺控件只降级不崩")
-- ⑨a 空树：init 不置 inited；所有方法都可以直接调（一抛错这里就整测试红）
local empty = {}
function empty:find() return nil end
function empty:sub() return nil end
local bare = Tutorial.new(empty, { tag = "bare", root = "teach.l1", text = "teach.text.l1", pages = 3 })
bare:init()
ok(bare.inited == false, "⑨a 根控件不在树里 ⇒ init 不置 inited（等下一帧）")
bare:open_ui(); bare:close(); bare:go(2); bare:next(); bare:prev()
ok(bare.inited == false and bare.page == 2, "⑨a 空树上所有方法都不抛错（page 夹紧照常）")

-- ⑨b 只有 root 的树：init 能成，但按钮 / 正文都缺 ⇒ 只降级
TREE = make_tree()
local partial = Tutorial.new(adapter, { tag = "partial", root = "teach", text = "teach.text", pages = 3 })
partial:init()
ok(partial.inited == true, "⑨b root（teach）在 ⇒ init 成功")
ok(count_bound(partial) == 0, "⑨b teach 下没有 btn.* ⇒ 一个都没绑上（不崩）")
partial:open_ui(); partial:close(); partial:go(2); partial:next(); partial:prev()
ok(partial.page == 2 and partial.open == false, "⑨b 缺按钮 / 缺正文时所有方法都不抛错")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑩ 页标：两套图互斥显隐（v290 新增）")
TREE = make_tree()
local l1c = Tutorial.new(adapter, { tag = "dots", root = "teach.l1", text = "teach.text.l1", pages = 3 })
local function d(i, which) return adapter:find("teach.l1.dot." .. i .. "." .. which) end
-- 起始故意把状态摆错：全 off 亮、全 on 灭 ⇒ open 之后必须被纠正
for i = 1, 3 do d(i, "on").visible = false; d(i, "off").visible = true end
l1c:init()
l1c:open_ui()
ok(d(1, "on").visible == true and d(1, "off").visible == false,
  "⑩ 第 1 页：dot.1.on 亮、dot.1.off 灭")
ok(d(2, "on").visible == false and d(2, "off").visible == true, "⑩ 第 1 页：第 2 颗仍是 off")
ok(d(3, "on").visible == false and d(3, "off").visible == true, "⑩ 第 1 页：第 3 颗仍是 off")
l1c:next()
ok(d(1, "on").visible == false and d(1, "off").visible == true, "⑩ next 后第 1 颗转 off")
ok(d(2, "on").visible == true and d(2, "off").visible == false, "⑩ next 后第 2 颗转 on")
l1c:go(3)
ok(d(3, "on").visible == true and d(3, "off").visible == false, "⑩ go(3) 后第 3 颗 on")
ok(d(1, "on").visible == false and d(2, "on").visible == false, "⑩ go(3) 后前两颗都 off（只有一颗亮）")
-- 页标不写文字、不创建（记账户已经在全程记账，这里只补"点没被动过打字"）
local n_on = 0
for i = 1, 3 do if d(i, "on").visible then n_on = n_on + 1 end end
ok(n_on == 1, "⑩ 任何时刻只有一颗 on 可见（实测 " .. n_on .. "）")

-- 页标缺失时只降级：把三颗点从树里摘掉，翻页照常、不崩
TREE = make_tree()
for i = 1, 3 do
  detach(adapter:find("teach.l1.dot." .. i .. ".on"))
  detach(adapter:find("teach.l1.dot." .. i .. ".off"))
end
local l1d = Tutorial.new(adapter, { tag = "nodots", root = "teach.l1", text = "teach.text.l1", pages = 3 })
l1d:init(); l1d:open_ui(); l1d:next()
ok(l1d.page == 2 and adapter:find("teach.text.l1.body.2").visible == true,
  "⑩ 没有页标控件时翻页照常（只降级，不崩）")

-- ══════════════════════════════════════════════════════════════════════════
sec("⑪ 零创建 + 从未写 text")
-- 取正文的两条路都验一遍（模块优先 find，sub 只兜底）
TREE = make_tree()
ok(adapter:sub("teach.text.l1", "body.1") == nil,
  "⑪ 短名 body.1 取不到（存档里子控件名是全名，预期行为）")
ok(adapter:sub("teach.text.l1", "teach.text.l1.body.1") ~= nil,
  "⑪ 全名用 sub 能取到（GetChild 精确名匹配）")
ok(adapter:find("teach.text.l1.body.1") ~= nil,
  "⑪ 全名用 find 能取到（模块优先走这条）")

-- 兜底路径：万一 find 查不到 body（例如缓存/失效代异常），sub(全名) 还得能救回来
TREE = make_tree()
local sub_only = {}
function sub_only:find(name)
  if string.find(name, ".body.", 1, true) then return nil end   -- 假装 find 查不到 body
  return adapter:find(name)
end
function sub_only:sub(parent_name, child_name)
  return adapter:sub(parent_name, child_name)
end
local fb = Tutorial.new(sub_only, { tag = "fallback", root = "teach.l1", text = "teach.text.l1", pages = 3 })
fb:init()
fb:open_ui()
local fb1 = adapter:find("teach.text.l1.body.1")
local fb2 = adapter:find("teach.text.l1.body.2")
ok(fb1.visible == true and fb2.visible == false,
  "⑪ find 取不到 body 时，sub(全名) 兜底仍能切页（只显示当前页）")

local script_text_writes = text_writes
ok(script_text_writes == 0,
  "⑪ 全程脚本 0 次写 text（.text= 与 SetText 合计 " .. script_text_writes .. " 次）")

-- 记账器自检：证明它不是死计数器（否则上面那个 0 毫无意义）
local probe = ctrl("probe")
probe.text = "编辑器填的内容"
ok(text_writes == script_text_writes + 1, "⑪ 记账器是活的：.text= 会被记到")
probe:SetText("再来一次")
ok(text_writes == script_text_writes + 2, "⑪ 记账器是活的：SetText 会被记到")

ok(created == 0, "⑪ 全程 0 次 InstantiateClientUIControl（实测 " .. created .. "）")
ok(destroyed == 0, "⑪ 全程 0 次 DestroyClientUIControl（实测 " .. destroyed .. "）")

-- ══════════════════════════════════════════════════════════════════════════
print(string.format("\ntutorial_ui: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
