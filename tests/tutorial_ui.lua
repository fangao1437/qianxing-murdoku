-- v352：静态 13 页教程控制器回归。
local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({ root .. "/lua/?.lua", root .. "/?.lua", package.path }, ";")
local Tutorial = require("tutorial_ui")
local passed, failed = 0, 0
local function ok(v, msg) if v then passed = passed + 1 else failed = failed + 1; print("FAIL " .. msg) end end
local writes, created = 0, 0
local function ctrl(name)
  local x = { name = name, visible = true, active = true, fontColor = "STATIC" }
  setmetatable(x, { __newindex = function(t, k, v) if k == "text" or k == "fontColor" then writes = writes + 1 end; rawset(t, k, v) end })
  x.SetVisible = function(_, v) rawset(x, "visible", v) end
  x.SetActive = function(_, v) rawset(x, "active", v) end
  x.SetText = function() writes = writes + 1 end
  x.AddCursorEventListener = function(_, _, cb) x.click = cb end
  return x
end
local nodes = {}
local function add(name) local c = ctrl(name); nodes[name] = c; return c end
add("teach"); add("teach.text")
for _, spec in ipairs({ { "home", 1 }, { "l1", 8 }, { "l2", 4 } }) do
  local tag, pages = spec[1], spec[2]
  add("td." .. tag)
  add("td." .. tag .. ".board")
  for i = 1, pages do add("td." .. tag .. ".page." .. i) end
  for _, b in ipairs({ "prev", "next", "close", "skip" }) do add("td." .. tag .. ".btn." .. b) end
end
local adapter = {}
function adapter:find(name) return nodes[name] end
function adapter:_furn_prefab_map()
  return { table_v2=1, plant=2, rug_2=3, chair=4, table_h2=5, rug=6, statue=7, rug_3=8, shelf=9, table=10 }
end
function adapter:_furn_scale_layers(obj, fx, fy) obj.fx, obj.fy = fx, fy end
_G.Enum = { CursorEventType = { CursorClick = "click" } }
_G.game = { InstantiateClientUIControl = function(prefab, parent)
  created = created + 1
  local obj = ctrl("tutorial.furniture." .. created)
  obj.prefab, obj.parent = prefab, parent
  return obj
end }
local home = Tutorial.new(adapter, { tag = "home", root = "td.home", pages = 1 })
local l1 = Tutorial.new(adapter, { tag = "l1", root = "td.l1", pages = 8 })
local l2 = Tutorial.new(adapter, { tag = "l2", root = "td.l2", pages = 4 })
home:init(); l1:init(); l2:init()
ok(home.inited and l1.inited and l2.inited, "三套初始化")
ok(not nodes["td.home"].visible and not nodes["td.l1"].visible and not nodes["td.l2"].visible, "初始化全部隐藏")
ok(not nodes["teach"].visible and not nodes["teach.text"].visible, "旧教程树不再显示")
ok(nodes["td.l1.page.1"].visible and not nodes["td.l1.page.2"].visible, "第一关只显示第一页")
ok(not nodes["td.l1.btn.prev"].visible and nodes["td.l1.btn.next"].visible, "第一页无上一页")
l1:open_ui(); l1:go(5)
ok(nodes["td.l1"].visible and nodes["td.l1.page.5"].visible and not nodes["td.l1.page.1"].visible, "打开并切到第五页")
ok(nodes["td.l1.btn.prev"].visible, "第五页有上一页")
l1:next(); ok(l1.page == 6 and nodes["td.l1.page.6"].visible, "下一页")
l1:prev(); ok(l1.page == 5 and nodes["td.l1.page.5"].visible, "上一页")
l1:go(0); ok(l1.page == 1, "下界夹紧")
l1:go(99); ok(l1.page == 8, "上界夹紧")
l1:next(); ok(not nodes["td.l1"].visible and not l1.open, "末页下一步关闭并开始试玩")
l2:open_ui(); l2:go(3)
ok(nodes["td.l2.page.3"].visible and not nodes["td.l2.page.1"].visible, "第二关独立翻页")
ok(not nodes["td.l1"].visible, "第二关操作不重开第一关")
home:open_ui(); home:next(); ok(not nodes["td.home"].visible, "首页开始办案关闭")
l2:open_ui(); nodes["td.l2.btn.close"].click(); ok(not nodes["td.l2"].visible, "关闭按钮")
l2:open_ui(); nodes["td.l2.btn.skip"].click(); ok(not nodes["td.l2"].visible, "跳过按钮")
ok(writes == 0, "运行时不写文字或字色")
ok(created == 20, "两关运行时各创建一套家具，共20件")
ok(l1.furniture and l1.furniture[1] and l1.furniture[1].parent == nodes["td.l1.board"], "第一关家具挂到共享棋盘")
ok(l2.furniture and l2.furniture[2] and math.abs(l2.furniture[2].fx - 178 * (1480 / 2268) / 216) < 0.0001, "多格家具按模板画布整树缩放")
l1:open_ui(); ok(created == 20, "重复打开不重复实例化")
print(string.format("tutorial_ui: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
