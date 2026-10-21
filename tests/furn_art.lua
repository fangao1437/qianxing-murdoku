--[[----------------------------------------------------------------------------
  tests/furn_art.lua —— 第二轮家具美术（v300）的离线断言

  ★ 为什么要有这一套（2026-10-22 用户打回第一版之后）：
    判词两条：① 家具"像色块"，要接近原作那种带深色描边的平面图标；
              ② **跨格家具不许拆成两格**（第一关桌子 (1,1)+(2,1)、第二关 (1,2)+(1,3)）。
    修法：`lua/furn_art.lua` 把相邻同种格**连通分组**，整件美术只画在**锚点格**（右下格），
          元素允许越出格子；地毯按"整块包围盒"逐格切矩形；房间名标签按房间外框摆。
    本用例钉住四件事：
      A 分组：L 形/两格/单格各自的件数、包围盒、锚点
      B 元素：每件 ≤ 6 层（模板只有 6 层）、竖放要交换轴、跨格元素真的越出 ±0.5
      C 地毯：两格切片能拼成一整块（左格内面偏右、右格内面偏左、且都在各自格内）
      D 适配层：`furn` 六层照画 / `furn_anchor` 把格子抬到最上层 / 空格子六层全藏

  跑法：lua tests/furn_art.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path,
}, ";")

local F = require("furn_art")
local Ad = require("engine_adapter_qianxing")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

-- ── 假 view：照 case_001 的 5×5 摆（桌子竖着两格、地毯横着两格、椅子/植物各一格）
local function make_vm()
  local keys = {
    { "obj.table", "obj.plant", false, false, false },   -- r1
    { "obj.table", false, false, "obj.carpet", "obj.carpet" }, -- r2
    { "obj.carpet", "obj.carpet", false, false, false }, -- r3
    { false, "obj.chair", false, false, false },         -- r4
    { "obj.plant", false, "obj.plant", "obj.chair", false }, -- r5
  }
  -- 房间号：R1 = 第1-3行 第1-3列；R2 = 第1-3行 第4-5列；R3 = 第4-5行 全部
  local rooms = {}
  for r = 1, 5 do
    rooms[r] = {}
    for c = 1, 5 do
      if r <= 3 then rooms[r][c] = (c <= 3) and 1 or 2
      else rooms[r][c] = 3 end
    end
  end
  local vm = { rows = 5, cols = 5, cells = {}, object_defs = {
    ["桌子"] = { kind = "table" }, ["植物"] = { kind = "plant" },
    ["地毯"] = { kind = "carpet" }, ["椅子"] = { kind = "chair" },
  } }
  for r = 1, 5 do
    vm.cells[r] = {}
    for c = 1, 5 do
      vm.cells[r][c] = { r = r, c = c, room = rooms[r][c], object = keys[r][c] }
    end
  end
  return vm, keys
end

--------------------------------------------------------------------------------
-- A 分组
--------------------------------------------------------------------------------
print("== A 分组 ==")
local vm, keys = make_vm()
local view = F.layout(vm, keys, { "大屋", "内室", "外间" })

-- 桌子 (1,1)+(2,1)：竖着两格 ⇒ 锚点 = (2,1)
local tbl = view.cell[2][1]
ok(tbl ~= nil and type(tbl.els) == "table", "A1 竖两格桌子：元素落在锚点格 (2,1)")
ok(view.cell[1][1].els == false, "A2 另一格 (1,1) 不再画家具（不会出现两张小桌子）")
ok(tbl.anchor == true, "A3 跨格家具的锚点格要标记 anchor=true")
ok(view.cell[4][2].anchor == false, "A4 单格家具不需要 anchor")
ok(#tbl.els <= 12, "A5 跨格桌子的层数 ≤ 12（模板 obj..obj12），实际 " .. tostring(#tbl.els))
-- 第 2 个元素 = 黑描边。第三轮起**横桌竖桌各一套变体**，竖放用 v2 ⇒ 高 > 宽（不再交换坐标轴）
local outline = tbl.els[2]
ok(outline.h > outline.w, "A6 竖放桌子用 v2 变体：描边元素高 > 宽：" ..
  string.format("%.2f x %.2f", outline.w, outline.h))
ok(math.abs((outline.dy or 0) + 0.5) < 0.01, "A7 竖放时锚点格中心在整件中心下方半格（dy = -0.5）")
ok(outline.h > 1.5, "A8 跨格元素允许 > 1 格（h = " .. string.format("%.2f", outline.h) .. "）")
-- 变体选择要能被看见（离线预览/日志据此核对"横竖是否各用各的"）
do
  local chosen = table.concat(view.chosen or {}, " ")
  ok(chosen:find("table@2,1%[v2%]") ~= nil, "A8b 竖放桌子选中的是 v2 变体（chosen=" .. chosen .. "）")
  ok(chosen:find("chair@4,2%[1%]") ~= nil, "A8c 单格椅子选中的是单格变体")
end
-- 阴影层：用户明确"其它家具的细节保留（包括阴影）"⇒ 五件的第 1 层都必须是柔光投影
do
  local has_shadow = true
  for _, kind in ipairs({ "table", "chair", "plant", "shelf", "statue" }) do
    local e = F.ART[kind] and F.ART[kind]["1"] and F.ART[kind]["1"][1]
    if e == nil or e.id ~= 106056 then has_shadow = false end
  end
  ok(has_shadow, "A8d 五件家具的第 1 层都是柔光投影（106056）")
end
-- 横放 vs 竖放确实是两套数据（不是同一份交换轴）
do
  local h2els = F.ART.table["h2"]
  local v2els = F.ART.table["v2"]
  local h2 = h2els[2]
  local v2 = v2els[2]
  ok(h2.w > h2.h and v2.h > v2.w, "A8e 长桌两套变体朝向相反（h2 宽>高 / v2 高>宽）")
  ok(#h2els > 0 and #v2els > 0, "A8f 长桌横竖两套变体都存在")
end

-- 椅子单格：元素居中在本格
local chair = view.cell[4][2]
ok(chair ~= nil and type(chair.els) == "table" and #chair.els <= 12, "A9 单格椅子有元素且 ≤ 6 层")
local max_off = 0
for _, e in ipairs(chair.els) do
  max_off = math.max(max_off, math.abs(e.dx or 0), math.abs(e.dy or 0))
end
ok(max_off < 0.5, "A10 单格家具的元素都在本格内（最大偏移 " .. string.format("%.2f", max_off) .. "）")

--------------------------------------------------------------------------------
-- B 地毯：两格切片拼成一整块
--------------------------------------------------------------------------------
print("== B 地毯 ==")
local rug1 = view.cell[2][4]
local rug2 = view.cell[2][5]
ok(rug1.anchor == false and rug2.anchor == false, "B1 地毯不需要抬层（可站人）")
local function find_rect(els)
  local found = nil
  for _, e in ipairs(els) do
    -- 取"内面"那一层：宽度在 0.3..0.99 之间（外框是 1.0）
    if (e.w or 0) > 0.3 and (e.w or 0) < 0.99 then found = found or e end
  end
  return found
end
local i1, i2 = find_rect(rug1.els), find_rect(rug2.els)
ok(i1 ~= nil and i2 ~= nil, "B2 两格地毯都有内面元素")
ok((i1.dx or 0) > 0.05, "B3 左格的内面偏右（贴向右边邻格，dx=" .. string.format("%.2f", i1.dx or 0) .. "）")
ok((i2.dx or 0) < -0.05, "B4 右格的内面偏左（贴向左边邻格，dx=" .. string.format("%.2f", i2.dx or 0) .. "）")
ok(#rug1.els >= 2 and #rug1.els <= 6, "B5 地毯每格元素数在 2..6")
-- 内面不许越出本格（地毯不溢出，否则会盖住邻格的人/笔记）
local out1 = math.abs(i1.dx or 0) + (i1.w or 1) / 2
ok(out1 <= 0.58, "B6 地毯内面基本不出格（" .. string.format("%.2f", out1) .. " ≤ 0.58）")

--------------------------------------------------------------------------------
-- C 房间外框 / 标签
--------------------------------------------------------------------------------
print("== C 房间名 ==")
ok(#view.labels == 3, "C1 三个房间三条标签，实际 " .. tostring(#view.labels))
ok(view.labels[1].text == "大屋" and view.labels[3].text == "外间", "C2 标签用的是关卡里的 room_names")
local b1 = view.labels[1].box
ok(b1.r1 == 1 and b1.r2 == 3 and b1.c1 == 1 and b1.c2 == 3, "C3 R1 外框 = 第1-3行 × 第1-3列")
local vm2, keys2 = make_vm()
local no_names = F.layout(vm2, keys2, nil)
ok(no_names.labels[1].text == "区域 1", "C4 关卡没填 room_names 时回退成「区域 N」")

--------------------------------------------------------------------------------
-- D 适配层：furn 六层 / furn_anchor / 空格子全藏
--------------------------------------------------------------------------------
print("== D 适配层 ==")
local function ctrl(name, kids, fields)
  local x = { name = name, _kids = kids or {} }
  for k, v in pairs(fields or {}) do x[k] = v end
  x.GetChildren = function() return x._kids end
  x.GetChild = function(_, n)
    for _, k in ipairs(x._kids) do if k.name == n then return k end end
    return nil
  end
  x.FindChild = x.GetChild
  x.SetVisible = function(_, v) x.visible = v end
  x.SetActive = function(_, v) x.active = v end
  x.SetImage = function(_, src, id) x.imageSource = src; x.imageId = id end
  x.SetLocalScale = function() end
  x.GetSizeDelta = function() return x.sizeDeltaX, x.sizeDeltaY end
  x.SetSizeDelta = function(_, w, h) x.sizeDeltaX, x.sizeDeltaY = w, h end
  x.SetAnchoredPosition = function(_, px, py) x.anchoredPositionX, x.anchoredPositionY = px, py end
  x.SetAnchorMin = function() end
  x.SetAnchorMax = function() end
  x.SetPivot = function() end
  x.SetAsLastSibling = function(self) self.__last = (self.__last or 0) + 1 return true end
  if x.visible == nil then x.visible = true end
  if x.active == nil then x.active = true end
  return x
end

local CELL = 108
local layers = {}
for i = 1, 12 do
  local nm = (i == 1) and "obj" or ("obj" .. i)
  layers[i] = ctrl(nm, {}, { imageId = 100001, imageColor = 4294967295, visible = false })
end
local content = ctrl("content", layers)
local cell = ctrl("cell.1.1", { content })
cell.kind = "button"
cell.sizeDeltaX, cell.sizeDeltaY = CELL, CELL
local rootCtl = ctrl("root", { cell })
_G.game = { GetClientUIRoots = function() return { rootCtl } end }
local a = Ad.new({ cells = { rows = 5, cols = 5 } })

local els = view.cell[2][1].els
local r1 = a:set_property("cell.1.1", "furn", els)
ok(r1 == true, "D1 set_property(cell,'furn',els) 返回 true")
local vis = 0
for i = 1, #els do if layers[i] and layers[i].visible then vis = vis + 1 end end
ok(vis == #els, "D2 十二层里该用的部件都点亮了（" .. vis .. "/" .. #els .. "）")
if #els < 12 then
  ok(layers[#els + 1].visible == false, "D3 没用到的第 " .. (#els + 1) .. " 层必须藏着（共 12 层）")
else
  ok(true, "D3 元素正好用满 12 层（无多余层可藏）")
end
ok(layers[1].imageId == els[1].id, "D4 第 1 层图 = 元素表第 1 个 id")
ok(layers[1].imageColor == els[1].color, "D5 第 1 层色 = 元素表第 1 个色")
ok(math.abs(layers[1].sizeDeltaX - els[1].w * CELL) < 0.5, "D6 第 1 层宽度按格子比例缩放")
ok(math.abs(layers[1].anchoredPositionY + (els[1].dy or 0) * CELL) < 0.5,
   "D7 dy 正 = 向下 ⇒ anchoredPosition.y 取负")

local r2 = a:set_property("cell.1.1", "furn_anchor", true)
ok(r2 == true and cell.__last == 1, "D8 furn_anchor 真的把格子 SetAsLastSibling 了")
a:set_property("cell.1.1", "furn", false)
local any_vis = false
for i = 1, 6 do if layers[i].visible then any_vis = true end end
ok(any_vis == false, "D9 没有家具时六层全藏（白板不许压头像/笔记）")

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- E 图元拼法家具（v302，第四轮：外部拼图工具的结果文件拆解 → 运行时实例化）
--------------------------------------------------------------------------------
print("== E 图元拼法（外部工具结果） ==")

local Recs = require("furn_art_records")

-- E1 数据模块本身的合法性：形状 id 只能是三个基础形状；尺寸/偏移有限；条数在预算内
do
  local kinds = { "chair", "table", "plant", "statue" }   -- 书架 v303 起退回手搭，不在这份数据里
  local bad = nil
  local total = 0
  local min_n, max_n = 1e9, 0
  for _, kind in ipairs(kinds) do
    local set = Recs[kind]
    if type(set) ~= "table" then bad = bad or (kind .. " 缺整组") end
    for variant, list in pairs(set or {}) do
      if type(list) ~= "table" or #list < 80 then
        bad = bad or (kind .. "/" .. variant .. " 图元太少")
      end
      total = total + #list
      if #list < min_n then min_n = #list end
      if #list > max_n then max_n = #list end
      for _, e in ipairs(list) do
        if e[1] ~= 100001 and e[1] ~= 100002 and e[1] ~= 100003 then
          bad = bad or (kind .. " 出现非基础形状 id=" .. tostring(e[1]))
        end
        if type(e[2]) ~= "number" or e[2] <= 0 or e[2] > 3 then bad = bad or (kind .. " w 非法") end
        if type(e[3]) ~= "number" or e[3] <= 0 or e[3] > 3 then bad = bad or (kind .. " h 非法") end
        if math.abs(e[4]) > 1.5 or math.abs(e[5]) > 1.5 then bad = bad or (kind .. " 偏移越界") end
        if type(e[6]) ~= "number" then bad = bad or (kind .. " rot 非数字") end
      end
    end
  end
  ok(bad == nil, "E1 图元数据合法（id/尺寸/偏移/旋转）" .. tostring(bad or ""))
  -- v303：书架退回手搭 + 丢了越界/极细图元 ⇒ 总量按"四件"重算（>700 仍远够用）
  ok(total > 700, "E2 图元总量够（" .. total .. " 条，> 700）")
  ok(min_n >= 100 and max_n <= 260, "E3 每件图元数在 100..260（实际 " .. min_n .. ".." .. max_n .. "）")
  ok(#Recs.table["h2"] > 0 and #Recs.table["v2"] > 0, "E4 长桌横放/竖放两套数据都在")
  -- v303：书架**退回手搭 12 层**（用户允许）；数据里不应再有 shelf 组
  ok(Recs.shelf == nil, "E4b 书架不再走工具图元（退回手搭）")
  -- v303：桌子/书架/地毯走手搭层 ⇒ `furn` 里必须有它们的元素
  do
    local vm2, keys2 = make_vm()
    local view2 = F.layout(vm2, keys2, { "大屋", "内室", "外间" })
    local tbl_els = view2.cell[2] and view2.cell[2][1] and view2.cell[2][1].els
    ok(type(tbl_els) == "table" and #tbl_els >= 8, "E4c 桌子在手搭层里有元素（" .. tostring(tbl_els and #tbl_els) .. " 层）")
    local outline = tbl_els and tbl_els[2]
    ok(outline ~= nil and outline.h > outline.w, "E4d 竖放长桌用手搭 v2 变体（描边高>宽）")
    ok(F.ART.shelf ~= nil and F.ART.shelf["1"] ~= nil, "E4e 书架手搭数据仍在（12 层）")
  end
end

-- E5 适配层：`furn_art` 分支要按记录**逐个实例化**并配置（图/色/尺寸/位置/旋转）
do
  local made = {}
  local function mkctrl(nm)
    local x = { name = nm, _kids = {} }
    x.GetChild = function(self, n)
      for _, k in ipairs(self._kids) do if k.name == n then return k end end
      return nil
    end
    x.GetChildren = function(self) return self._kids end
    x.SetVisible = function(self, v) self.visible = v end
    x.SetActive = function(self, v) self.active = v end
    x.SetImage = function(self, src, id) self.imageSource = src; self.imageId = id end
    x.SetSizeDelta = function(self, w, h) self.sizeDeltaX, self.sizeDeltaY = w, h end
    x.SetAnchoredPosition = function(self, px, py) self.anchoredPositionX, self.anchoredPositionY = px, py end
    x.SetAnchorMin = function() end
    x.SetAnchorMax = function() end
    x.SetPivot = function() end
    x.SetLocalRotation = function(self, rx, ry, rz) self.rotX, self.rotY, self.rotZ = rx, ry, rz end
    x.SetLocalScale = function() end
    x.GetSizeDelta = function() return self.sizeDeltaX, self.sizeDeltaY end
    if x.visible == nil then x.visible = true end
    if x.active == nil then x.active = true end
    return x
  end

  local furn = mkctrl("furn")
  local content = mkctrl("content")
  content._kids = { furn }
  local cell = mkctrl("cell.1.1")
  cell._kids = { content }
  cell.kind = "button"
  cell.sizeDeltaX, cell.sizeDeltaY = 108, 108
  local rootCtl = mkctrl("root")
  rootCtl._kids = { cell }

  local inst = 0
  _G.Enum = { ImageSource = { StaticReference = 0 }, ImageType = { Basic = 0, Stretch = 1 } }
  _G.game = {
    GetClientUIRoots = function() return { rootCtl } end,
    InstantiateClientUIControl = function(prefab, parent)
      inst = inst + 1
      local c = mkctrl("prim." .. inst)
      parent._kids[#parent._kids + 1] = c
      made[#made + 1] = c
      return c
    end,
  }
  local a2 = Ad.new({ cells = { rows = 5, cols = 5 }, furn_prim_prefab = 1073746302, furn_prim_cap = 6 })
  local recs = Recs.chair["1"]
  local r = a2:set_property("cell.1.1", "furn_art", recs)
  ok(r == true, "E5 set_property(cell,'furn_art',recs) 返回 true")
  ok(inst == 6, "E6 按上限实例化了 6 个控件（实际 " .. inst .. "）")
  local k1 = made[1]
  ok(k1 ~= nil and k1.imageId == recs[1][1], "E7 第 1 个控件图的 id = 记录里的 id")
  ok(k1.imageColor == recs[1][7], "E8 第 1 个控件的 imageColor = 记录里的 colorARGB")
  ok(math.abs(k1.sizeDeltaX - recs[1][2] * 108) < 0.5, "E9 尺寸按格宽换算（w×cell）")
  ok(math.abs(k1.anchoredPositionX - recs[1][4] * 108) < 0.5, "E10 dx → anchoredPosition.x")
  ok(math.abs(k1.anchoredPositionY + recs[1][5] * 108) < 0.5, "E11 dy（向下为正）→ anchoredPosition.y 取负")
  local saw_rot = false
  for i = 1, 6 do
    local rot = recs[i] and recs[i][6] or 0
    if rot ~= 0 and made[i] ~= nil then
      saw_rot = true
      ok(math.abs(made[i].rotZ - rot) < 0.5, "E12 旋转角原样传给 SetLocalRotation(0,0,rot)（第 " .. i .. " 条）")
      break
    end
  end
  ok(saw_rot, "E13 图元里确实有带旋转的（工具结果含旋转）")

  -- 换成"没有家具" ⇒ 已实例化的控件要藏起来（不销毁，切关时复用）
  a2:set_property("cell.1.1", "furn_art", false)
  local any_vis = false
  for i = 1, #made do if made[i].visible then any_vis = true end end
  ok(any_vis == false, "E14 没有家具时所有已生成控件都藏起来")
end


--------------------------------------------------------------------------------
-- F 静态烘焙模式（v306）：`baked_level` 只切 `fart.<关卡>` 两个容器的显隐
--------------------------------------------------------------------------------
print("== F 静态烘焙 ==")
do
  local function mk(name)
    local x = { name = name, _kids = {} }
    x.GetChild = function(self, n)
      for _, k in ipairs(self._kids) do if k.name == n then return k end end
      return nil
    end
    x.GetChildren = function(self) return self._kids end
    x.SetVisible = function(self, v) self.visible = v end
    x.SetActive = function(self, v) self.active = v end
    if x.visible == nil then x.visible = true end
    return x
  end
  local b1 = mk("fart.case_001")
  local b2 = mk("fart.case_002")
  b1.visible, b2.visible = false, false
  local rootCtl = mk("root")
  rootCtl._kids = { b1, b2 }
  _G.game = { GetClientUIRoots = function() return { rootCtl } end }
  local a3 = Ad.new({ cells = { rows = 5, cols = 5 } })

  ok(a3:set_property("root", "baked_level", "case_001") == true, "F1 baked_level 属性被接受")
  ok(b1.visible == true, "F2 当前关卡的烘焙容器打开（case_001）")
  ok(b2.visible == false, "F3 另一关的烘焙容器保持隐藏（case_002）")

  a3:set_property("root", "baked_level", "case_002")
  ok(b1.visible == false and b2.visible == true, "F4 切关时两个容器对调（case_002 开、case_001 关）")

  a3:set_property("root", "baked_level", false)
  ok(b1.visible == false and b2.visible == false, "F5 烘焙模式关掉时两个容器都隐藏")
end

print(string.format("\nfurn_art: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
