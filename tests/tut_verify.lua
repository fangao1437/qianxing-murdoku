--[[----------------------------------------------------------------------------
  tests/tut_verify.lua —— 教程控件自检模块（`lua/tut_verify.lua`）的离线回归

  钉七件事（另加一条附验）：
    ① 全绿：4/4，无 error 无 warning；日志原文 = `[tut] 自检 OK 4/4`
       （顺便证明 `GetSizeDelta` 返回**表** `{x=,y=}` 的模拟器桥接形态也能读）
    ② 缺一个：只报 1 条 `缺失`，其余照旧找到（found 3 / total 4）
    ③ 重名：三种注入能力都能判出来 —— `all`（精确条数）/ `roots`（自己走树）/
       **只给 find**（兜底查同级 + 一条"重名只查同级"的配置警告）
    ④ 父错：`父不对(期望 frame.panel 实际 frame.root)`，控件仍在 ⇒ found 不降
    ⑤ 尺寸：0 ⇒ `尺寸 0(0x600)`；小于 min_size ⇒ `尺寸不足(50x40 < 100x40)`
    ⑥ 期望可见却被隐藏：自身 `visible=false` ⇒ `不可见`；
       祖先被关 ⇒ `不可见(祖先 frame.root 隐藏)`（本项目"主页整个消失"就是这一层）
    ⑦ 零创建：假 `game.InstantiateClientUIControl` **0 次**调用；
       并且把 `game` 整个设成 nil 也照样能跑（模块不依赖真实 game、不造控件）
    ★ 附：内置 `TUTORIAL_EXPECT`（26 条 teach.*，三套）对"照 483 结构搭的真树"全绿

  跑法：lua tests/tut_verify.lua
  本机 lua.exe 是 5.4；沙箱语义按 5.3，另有闸：
    node tools/lua53check/check.cjs lua/tut_verify.lua --run
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua",
  package.path,
}, ";")

local Verify = require("tut_verify")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end
local function sec(t) print("\n== " .. t .. " ==") end

-- ── 假控件 ────────────────────────────────────────────────────────────────
-- 与 tests/tutorial_ui.lua 同一种做法（手搭假树），但补了三样自检要读的东西：
--   · `parent` / `GetParent()`（父级判据）
--   · `GetSizeDelta()`（尺寸判据；`_table_size` 用来复现模拟器桥接的 {x,y} 形态）
--   · `visible`（显隐判据，字段可读 —— 项目里验证过的写法）
local function ctrl(name, w, h)
  local x = {
    name = name,
    parent = nil,
    _kids = {},
    visible = true,
    active = true,
    _w = w or 100,
    _h = h or 100,
    _table_size = false,
  }
  x.GetChildren = function() return x._kids end
  x.GetChild = function(_, n)
    for _, k in ipairs(x._kids) do if k.name == n then return k end end
    return nil
  end
  x.GetParent = function() return x.parent end
  x.GetSizeDelta = function()
    if x._table_size then return { x = x._w, y = x._h } end
    return x._w, x._h
  end
  x.SetVisible = function(_, v) x.visible = v end
  return x
end

local function add(parent, ...)
  for _, k in ipairs({ ... }) do
    k.parent = parent
    parent._kids[#parent._kids + 1] = k
  end
  return parent
end

local function detach(child)
  local p = child.parent
  if p == nil then return end
  for i = #p._kids, 1, -1 do
    if p._kids[i] == child then table.remove(p._kids, i) end
  end
  child.parent = nil
end

-- ── 假"取控件"能力：和适配器同样的方法形态（`finder:find(name)`）────────────
local function find_in(node, name)
  if node == nil then return nil end
  if node.name == name then return node end
  for _, k in ipairs(node._kids) do
    local hit = find_in(k, name)
    if hit ~= nil then return hit end
  end
  return nil
end

local function all_in(node, name, out)
  out = out or {}
  if node == nil then return out end
  if node.name == name then out[#out + 1] = node end
  for _, k in ipairs(node._kids) do all_in(k, name, out) end
  return out
end

local function finder_for(root_ctrl)
  local f = { _root = root_ctrl }
  function f:find(name) return find_in(self._root, name) end
  function f:all(name) return all_in(self._root, name) end
  function f:roots() return { self._root } end
  return f
end

-- ── 迷你树 + 期望清单（用例 ①~⑦ 都用它，每条用例重新搭一棵）──────────────
local MINI_EXPECT = {
  { name = "frame.root",  parent = "root" },
  { name = "frame.panel", parent = "frame.root" },
  { name = "frame.btn",   parent = "frame.panel", visible = true },
  { name = "frame.tab",   parent = "frame.panel", visible = true, min_size = { w = 100, h = 40 } },
}

local function mini()
  local root_ctrl = ctrl("root", 1600, 900)
  local app       = ctrl("frame.root", 1600, 900)
  local panel     = ctrl("frame.panel", 800, 600)
  local btn       = ctrl("frame.btn", 60, 60)
  local tab       = ctrl("frame.tab", 100, 40)
  add(root_ctrl, app)
  add(app, panel)
  add(panel, btn, tab)
  return { root = root_ctrl, app = app, panel = panel, btn = btn, tab = tab }
end

-- ══════════════════════════════════════════════════════════════════════════
sec("① 全绿")
do
  local t = mini()
  t.panel._table_size = true          -- 模拟器桥接：GetSizeDelta() ⇒ {x=800, y=600}
  local f = finder_for(t.root)
  local res = Verify.run({ find = f, all = f, roots = f, expect = MINI_EXPECT })
  ok(res.ok == true, "① ok = true（errors=" .. #res.errors .. "）")
  ok(#res.errors == 0 and #res.warnings == 0, "① 没有 error / warning")
  ok(res.found == 4 and res.total == 4, "① found=4 total=4（实测 " .. res.found .. "/" .. res.total .. "）")
  local line = Verify.log(res)
  ok(line == "[tut] 自检 OK 4/4", "① 日志原文（实测 " .. tostring(line) .. "）")
end

-- ══════════════════════════════════════════════════════════════════════════
sec("② 缺一个")
do
  local t = mini()
  detach(t.btn)                       -- 叶子控件不在树里 ⇒ 只有它一条缺失
  local f = finder_for(t.root)
  local res = Verify.run({ find = f, all = f, expect = MINI_EXPECT })
  ok(res.ok == false, "② ok = false")
  ok(#res.errors == 1, "② 只有 1 条 error（实测 " .. #res.errors .. "）")
  ok(res.errors[1].name == "frame.btn" and res.errors[1].kind == "缺失",
    "② 报的是 frame.btn 缺失（实测 " .. tostring(res.errors[1] and res.errors[1].text) .. "）")
  ok(res.found == 3 and res.total == 4, "② found=3 total=4（实测 " .. res.found .. "/" .. res.total .. "）")
  local line = Verify.log(res)
  ok(line == "[tut] 自检 FAIL 1 项: frame.btn=缺失", "② 日志原文（实测 " .. tostring(line) .. "）")
end

-- ══════════════════════════════════════════════════════════════════════════
sec("③ 重名")
do
  -- ③a 注入 all：最准，能报精确条数
  local t = mini()
  add(t.panel, ctrl("frame.btn", 60, 60))          -- 同级第二份 frame.btn
  local f = finder_for(t.root)
  local res = Verify.run({ find = f, all = f, expect = MINI_EXPECT })
  ok(res.ok == false, "③a ok = false")
  ok(#res.errors == 1 and res.errors[1].kind == "重名",
    "③a 报重名（实测 " .. tostring(res.errors[1] and res.errors[1].text) .. "）")
  ok(res.errors[1].text == "frame.btn=重名(2 条)", "③a 条数是精确的 2 条")
  ok(res.found == 4, "③a 重名控件照样算 found（4/4）")
  Verify.log(res)

  -- ③b 注入 roots：没给 all 时自己走整棵树数
  local res2 = Verify.run({ find = f, roots = f, expect = MINI_EXPECT })
  ok(res2.ok == false and res2.errors[1] and res2.errors[1].kind == "重名",
    "③b 只给 roots 也能判重名（实测 " .. tostring(res2.errors[1] and res2.errors[1].text) .. "）")
  ok(res2.errors[1].text == "frame.btn=重名(2 条)", "③b roots 走树数出来的也是 2 条")

  -- ③c 只给 find：兜底查同级（能抓同级重名）+ 一条配置警告
  --   （这里用 check 而不是 run：顺带验一下警告行真的会打出来，不静默降级）
  local res3 = Verify.check({ find = f, expect = MINI_EXPECT })
  ok(res3.ok == false and res3.errors[1] and res3.errors[1].kind == "重名",
    "③c 只给 find（查同级）也抓到同级重名")
  local has_warn = false
  for i = 1, #res3.warnings do
    if res3.warnings[i].kind == "重名只查同级" then has_warn = true end
  end
  ok(has_warn == true, "③c 只给 find 时给出「重名只查同级」的警告（不静默降级）")
end

-- ══════════════════════════════════════════════════════════════════════════
sec("④ 父错")
do
  local t = mini()
  detach(t.btn)
  add(t.app, t.btn)                   -- 父级从 frame.panel 挪到 frame.root（控件仍在树上）
  local f = finder_for(t.root)
  local res = Verify.run({ find = f, all = f, expect = MINI_EXPECT })
  ok(res.ok == false and #res.errors == 1, "④ 只有 1 条 error（实测 " .. #res.errors .. "）")
  ok(res.errors[1].kind == "父不对",
    "④ 判据是「父不对」（实测 " .. tostring(res.errors[1] and res.errors[1].text) .. "）")
  ok(res.errors[1].text == "frame.btn=父不对(期望 frame.panel 实际 frame.root)",
    "④ 文案带期望值与实际值")
  ok(res.found == 4, "④ 控件还在树上 ⇒ found 仍是 4")
  Verify.log(res)
end

-- ══════════════════════════════════════════════════════════════════════════
sec("⑤ 尺寸")
do
  -- ⑤a 尺寸 0：不需要写 min_size 也要判红（477 骨架把整片教程裁没的就是这个）
  local t = mini()
  t.panel._w = 0
  local f = finder_for(t.root)
  local res = Verify.run({ find = f, all = f, expect = MINI_EXPECT })
  ok(res.ok == false and res.errors[1] and res.errors[1].kind == "尺寸 0",
    "⑤a 尺寸 0 判红（实测 " .. tostring(res.errors[1] and res.errors[1].text) .. "）")
  ok(res.errors[1].text == "frame.panel=尺寸 0(0x600)", "⑤a 文案带实际尺寸")
  Verify.log(res)

  -- ⑤b 小于 min_size
  local t2 = mini()
  t2.tab._w = 50
  local f2 = finder_for(t2.root)
  local res2 = Verify.run({ find = f2, all = f2, expect = MINI_EXPECT })
  ok(res2.ok == false and res2.errors[1] and res2.errors[1].kind == "尺寸不足",
    "⑤b 小于 min_size 判红（实测 " .. tostring(res2.errors[1] and res2.errors[1].text) .. "）")
  ok(res2.errors[1].text == "frame.tab=尺寸不足(50x40 < 100x40)", "⑤b 文案含实际/期望尺寸")
  Verify.log(res2)
end

-- ══════════════════════════════════════════════════════════════════════════
sec("⑥ 期望可见却被隐藏")
do
  -- ⑥a 自己 visible=false
  local t = mini()
  t.tab.visible = false
  local f = finder_for(t.root)
  local res = Verify.run({ find = f, all = f, expect = MINI_EXPECT })
  ok(res.ok == false and res.errors[1] and res.errors[1].kind == "不可见",
    "⑥a 自身隐藏判红（实测 " .. tostring(res.errors[1] and res.errors[1].text) .. "）")
  ok(res.errors[1].text == "frame.tab=不可见", "⑥a 文案 = frame.tab=不可见")
  Verify.log(res)

  -- ⑥b 自己 visible=true，但父级被关 ⇒ 画面上一样看不见（本项目"主页整个消失"那层）
  local t2 = mini()
  t2.app.visible = false
  local f2 = finder_for(t2.root)
  local res2 = Verify.run({ find = f2, all = f2, expect = MINI_EXPECT })
  ok(res2.ok == false, "⑥b 祖先隐藏判红")
  local hit = nil
  for i = 1, #res2.errors do
    if res2.errors[i].text == "frame.btn=不可见(祖先 frame.root 隐藏)" then hit = res2.errors[i] end
  end
  ok(hit ~= nil, "⑥b 文案指出是哪个祖先被关（实测 "
    .. tostring(res2.errors[1] and res2.errors[1].text) .. "）")
  Verify.log(res2)
end

-- ══════════════════════════════════════════════════════════════════════════
sec("⑦ 零创建")
do
  local created, destroyed = 0, 0
  local t = mini()
  local f = finder_for(t.root)

  -- 假 game：只要自检敢调创建/销毁接口，立刻记错并抛错
  _G.game = {
    InstantiateClientUIControl = function()
      created = created + 1
      error("禁止创建控件：自检必须是只读的")
    end,
    DestroyClientUIControl = function()
      destroyed = destroyed + 1
      error("禁止销毁控件：自检必须是只读的")
    end,
    GetClientUIRoots = function() return { t.root } end,
  }

  -- ⑦a 在"一调就报错"的假 game 上把全绿/判红的路径都跑一遍
  for i = 1, 4 do
    local res = Verify.run({ find = f, all = f, roots = f, expect = MINI_EXPECT })
    ok(res.ok == true, "⑦a 第 " .. i .. " 轮自检仍全绿（game 桩没影响结果）")
  end
  ok(created == 0, "⑦ 全程 0 次 InstantiateClientUIControl（实测 " .. created .. "）")
  ok(destroyed == 0, "⑦ 全程 0 次 DestroyClientUIControl（实测 " .. destroyed .. "）")

  -- ⑦b 把 game 整个摘掉：模块本来就不读 game，行为应当一模一样
  _G.game = nil
  local res2 = Verify.run({ find = f, all = f, expect = MINI_EXPECT })
  ok(res2.ok == true, "⑦b game = nil 也能自检（不依赖真实 game）")
  ok(Verify.log(res2) == "[tut] 自检 OK 4/4", "⑦b 日志与有 game 时一致")
end

-- ══════════════════════════════════════════════════════════════════════════
sec("★ 附：内置 TUTORIAL_EXPECT 对 teach.* 真树")
do
  -- 按 486（v290）的结构搭（名字 / 父级与 `tools/gil/gen_tutorial_teach.mjs` 的 add(...) 一致；
  --  ★ 子控件名都是**全名**：`teach.text.l1.body.1` 是它自己的名字；
  --  ★ 按钮里的图元（`icon` / `x`）是**按钮的子控件**，所以父级要写按钮名）
  local root_ctrl = ctrl("root", 1600, 900)
  local teach     = ctrl("teach", 1600, 900)
  local text      = ctrl("teach.text", 1600, 900)
  add(root_ctrl, teach)
  add(teach, text)

  for _, side in ipairs({ "home", "l1", "l2" }) do
    local panel = ctrl("teach." .. side, 1240, 780)
    add(teach, panel)
    local btn_prev  = ctrl("teach." .. side .. ".btn.prev", 180, 158)
    local btn_next  = ctrl("teach." .. side .. ".btn.next", 180, 158)
    local btn_close = ctrl("teach." .. side .. ".btn.close", 48, 48)
    add(panel,
      ctrl("bg", 1240, 780),                 -- 子控件记录（短名 bg；`teach.l1.bg` 只是路径写法）
      ctrl("page", 1120, 380),               -- 同上（page 的 bg 子控件这里略去，不影响判据）
      btn_prev, btn_next, btn_close,
      ctrl("teach." .. side .. ".btn.click", 180, 52))
    add(btn_prev, ctrl("teach." .. side .. ".btn.prev.icon", 40, 40))
    add(btn_next, ctrl("teach." .. side .. ".btn.next.icon", 40, 40))
    add(btn_close, ctrl("teach." .. side .. ".btn.close.x", 22, 22))
    -- v290 页标：三颗菱形，每颗两条记录（on 30×30 / off 24×24）
    for i = 1, 3 do
      add(panel,
        ctrl("teach." .. side .. ".dot." .. i .. ".on", 30, 30),
        ctrl("teach." .. side .. ".dot." .. i .. ".off", 24, 24))
    end

    local box = ctrl("teach.text." .. side, 1600, 900)
    add(text, box)
    add(box,
      ctrl("teach.text." .. side .. ".title", 820, 56),
      ctrl("teach.text." .. side .. ".subtitle", 820, 40),
      ctrl("teach.text." .. side .. ".body.1", 900, 260),
      ctrl("teach.text." .. side .. ".body.2", 900, 260),
      ctrl("teach.text." .. side .. ".body.3", 900, 260),
      ctrl("teach.text." .. side .. ".btn.prev", 160, 40),
      ctrl("teach.text." .. side .. ".btn.next", 160, 40),
      ctrl("teach.text." .. side .. ".btn.close", 48, 40),
      ctrl("teach.text." .. side .. ".btn.click", 160, 40))
  end

  local f = finder_for(root_ctrl)
  -- 不传 expect ⇒ 用模块内置的 62 条清单
  local res = Verify.run({ find = f, all = f, roots = f })
  ok(res.total == 62, "附：内置清单 62 条（实测 " .. res.total .. "）")
  ok(res.ok == true and res.found == 62,
    "附：内置清单对真树全绿（errors=" .. #res.errors .. " found=" .. res.found .. "）")
  if not res.ok then
    for i = 1, #res.errors do print("     " .. res.errors[i].text) end
  end
  ok(Verify.log(res) == "[tut] 自检 OK 62/62", "附：日志原文")
end

-- ══════════════════════════════════════════════════════════════════════════
sec("★ 附2：配置错误不许假绿")
do
  local t = mini()
  local f = finder_for(t.root)

  local res = Verify.run({ expect = MINI_EXPECT })          -- 忘了注入 find
  ok(res.ok == false and res.errors[1] and res.errors[1].kind == "配置错误",
    "附2：没注入 find ⇒ 配置错误（不许报平安）")

  local res2 = Verify.run({ find = f, expect = {} })        -- 空清单
  ok(res2.ok == false and res2.errors[1] and res2.errors[1].kind == "配置错误",
    "附2：空清单 ⇒ 配置错误（0/0 的绿是假绿）")
  Verify.log(res)
  Verify.log(res2)
end

-- ══════════════════════════════════════════════════════════════════════════
print(string.format("\ntut_verify: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
