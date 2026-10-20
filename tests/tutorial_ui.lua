--[[----------------------------------------------------------------------------
  tests/tutorial_ui.lua —— 玩法说明浮层（`tut.*`）的离线回归（v284）

  钉五件事（全部双向）：
    ① `init` 之后：整片收起、页码「第 1 / 3 页」、只有第 1 页可见
    ② `next` / `prev`：页码与页片同步变；**边界夹紧**（3 不再加、1 不再减）
    ③ 页签选中态：当前页 `state.sel` 亮、`state.off` 灭；其它页反过来
    ④ `open_ui` / `close`：整片显隐正确
    ⑤ ★ **一个控件都不许创建**（用户规矩：脚本里不要有创建控件这种操作）
       ⇒ 假 `game.InstantiateClientUIControl` 一被调用就判红

  跑法：lua tests/tutorial_ui.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({ root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path }, ";")

local Tutorial = require("tutorial_ui")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

-- ── 假控件 ────────────────────────────────────────────────────────────────
local function ctrl(name, kids)
  local x = { name = name, _kids = kids or {}, visible = true, active = true, text = nil }
  x.GetChildren = function() return x._kids end
  x.GetChild = function(_, n) for _, k in ipairs(x._kids) do if k.name == n then return k end end return nil end
  x.FindChild = x.GetChild
  x.SetVisible = function(_, v) x.visible = v end
  x.SetActive = function(_, v) x.active = v end
  x.SetText = function(_, t) x.text = t end
  x.AddCursorEventListener = function(_, _, cb) x._click = cb end
  return x
end

-- 页签：text / plate / state.sel / state.off
local function make_tab(i)
  return ctrl("tut.tab.p" .. i, { ctrl("text"), ctrl("plate"), ctrl("state.sel"), ctrl("state.off") })
end
-- 页片：bg / label
local function make_page(i)
  return ctrl("tut.page.p" .. i, { ctrl("bg"), ctrl("label") })
end

local title = ctrl("tut.hud.title")
local pager = ctrl("tut.hud.pager")
local btnPrev = ctrl("tut.btn.prev", { ctrl("text"), ctrl("plate") })
local btnNext = ctrl("tut.btn.next", { ctrl("text"), ctrl("plate") })
local btnReset = ctrl("tut.btn.reset", { ctrl("text"), ctrl("plate") })
local btnClose = ctrl("tut.btn.close", { ctrl("text"), ctrl("plate") })
local tabs = { make_tab(1), make_tab(2), make_tab(3) }
local pages = { make_page(1), make_page(2), make_page(3) }
local screen = ctrl("tut.screen.demo", { title, pager, tabs[1], tabs[2], tabs[3], btnPrev, btnNext, btnReset, btnClose, pages[1], pages[2], pages[3] })
local appRoot = ctrl("tut.app.root", { screen })
local gameRoot = ctrl("root", { appRoot })

-- ── 假适配器：find 走活树；sub 先 find 再 GetChild ────────────────────────
local function walk(nodes, fn)
  for _, n in ipairs(nodes or {}) do fn(n); walk(n._kids, fn) end
end
local adapter = {}
function adapter:find(name)
  local hit = nil
  walk({ gameRoot }, function(n) if not hit and n.name == name then hit = n end end)
  return hit
end
function adapter:sub(parentName, childName)
  local p = self:find(parentName)
  if p == nil then return nil end
  return p:GetChild(childName)
end

-- ── ⑤ 反例探针：任何"创建控件"都判红 ──────────────────────────────────────
local created = 0
_G.game = {
  InstantiateClientUIControl = function() created = created + 1; error("不许创建控件") end,
  DestroyClientUIControl = function() end,
}
_G.Enum = { CursorEventType = { CursorClick = "click" } }

local t = Tutorial.new(adapter)
t:init()
ok(t.inited == true, "① init 后 inited = true")
ok(appRoot.visible == false, "① init 后整片收起（app.root 不可见）")
ok(pager.text == "第 1 / 3 页", "① 页码 = 第 1 / 3 页（实测 " .. tostring(pager.text) .. "）")
ok(pages[1].visible == true and pages[2].visible == false and pages[3].visible == false,
  "① 只有第 1 页可见")
ok(title.text == Tutorial.PAGES[1].title, "① 标题是第 1 页的标题")
ok(pages[1]:GetChild("label").text == Tutorial.PAGES[1].body, "① 第 1 页正文已写入（.gil 存不下文字，必须运行时写）")

-- ② 翻页 + 边界
t:open_ui()
ok(appRoot.visible == true, "④ open_ui 后可见")
t:next()
ok(t.page == 2 and pager.text == "第 2 / 3 页", "② next ⇒ 第 2 页")
ok(pages[2].visible == true and pages[1].visible == false, "② 页片跟着换（双向：2 可见 / 1 不可见）")
t:next(); t:next()
ok(t.page == 3, "② 到第 3 页后不再加（实测 " .. t.page .. "）")
t:prev(); t:prev(); t:prev()
ok(t.page == 1, "② 到第 1 页后不再减（实测 " .. t.page .. "）")

-- ③ 页签选中态
t:go_page(2)
ok(tabs[2]:GetChild("state.sel").visible == true and tabs[2]:GetChild("state.off").visible == false,
  "③ 当前页签：sel 亮 / off 灭")
ok(tabs[1]:GetChild("state.sel").visible == false and tabs[1]:GetChild("state.off").visible == true,
  "③ 非当前页签：sel 灭 / off 亮")

-- ④ reset / close
t:reset()
ok(t.page == 1 and pager.text == "第 1 / 3 页", "④ reset ⇒ 回到第 1 页")
t:close()
ok(appRoot.visible == false, "④ close 后不可见")

-- ⑤ 没创建任何控件
ok(created == 0, "⑤ 全程没有调用 InstantiateClientUIControl（实测 " .. created .. " 次）")

-- 按钮回调真的绑上了（点一下 Close 能收起）
t:open_ui()
ok(type(btnClose._click) == "function", "④ 关闭按钮绑上了点击回调")
if type(btnClose._click) == "function" then
  btnClose._click()
  ok(appRoot.visible == false, "④ 点关闭按钮 ⇒ 整片收起")
end

print(string.format("\ntutorial_ui: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
