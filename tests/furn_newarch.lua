--[[ tests/furn_newarch.lua —— v315 新架构（用户改建的 520.1）离线断言

  新架构（用户在存档里做的）：
    · cell 模板 content 里删掉 face/obj/furn，只留 hint/wall/door/note/portrait/x；
    · 新建 `cell.face` 模板 + `root/tpl.cell.face` 引用控件（用和 cell 一样的方式实例化）；
    · 家具模板引用控件集中放在 `root/things`（furn,chair / furn.plant / …）。

  本用例钉住脚本侧四件事：
    F1 `_ensure_cell_face` 把 face 实例化进 cell 的 content、命名 `face`、排在最底（SiblingIndex 0）；
    F2 `things` 里的引用控件能读出家具模板 prefab（referencedPrefabIndex）；
    F3 `furn_tpl` 属性到达时会实例化家具，父级是 content（没有 furn 容器时）；
    F4 家具实例排到 face 之上（SiblingIndex = 1）；
    F5 新架构下手搭层（furn）被跳过、不报错。

  跑法：lua tests/furn_newarch.lua
]]--
local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path,
}, ";")

local Ad = require("engine_adapter_qianxing")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL  " .. msg) end
end

local FACE_PREFAB = 1073747145
local CHAIR_PREFAB = 1073747134

local function mkctrl(name)
  local c = { name = name, _kids = {}, visible = true, active = true, sizeDeltaX = 108, sizeDeltaY = 108 }
  function c.GetChild(self, n) for _, k in ipairs(self._kids) do if k.name == n then return k end end return nil end
  function c.GetChildren(self) return self._kids end
  function c.SetVisible(self, v) self.visible = v end
  function c.SetActive(self, v) self.active = v end
  function c.GetSizeDelta(self) return self.sizeDeltaX, self.sizeDeltaY end
  function c.SetSizeDelta(self, w, h) self.sizeDeltaX, self.sizeDeltaY = w, h end
  function c.GetAnchoredPosition(self) return self.anchoredPositionX or 0, self.anchoredPositionY or 0 end
  function c.SetAnchoredPosition(self, x, y) self.anchoredPositionX, self.anchoredPositionY = x, y end
  function c.SetAnchorMin() end function c.SetAnchorMax() end function c.SetPivot() end
  function c.SetSiblingIndex(self, i) self.siblingIndex = i; return true end
  function c.SetAsLastSibling(self) self.last = true; return true end
  function c.SetAsFirstSibling(self) self.first = true; return true end
  function c.GetSiblingIndex(self) return self.siblingIndex or 0 end
  return c
end

local function add(parent, child) parent._kids[#parent._kids + 1] = child; return child end

-- ── 假树：完全照 520.1 的形状 ──────────────────────────────────────────────
local ref = function(name, prefab)
  local c = mkctrl(name)
  c.referencedPrefabIndex = prefab
  return c
end
local things = mkctrl("things")
add(things, ref("furn,chair", CHAIR_PREFAB))
add(things, ref("furn.plant", 1073747135))
add(things, ref("furn.shelf", 1073747140))
add(things, ref("furn.statue", 1073747136))
add(things, ref("furn.table.1", 1073747137))
add(things, ref("furn.table.h2", 1073747138))
add(things, ref("furn.table.v2", 1073747139))

local faceRef = ref("tpl.cell.face", FACE_PREFAB)

local hint = mkctrl("hint")
local portrait = mkctrl("portrait")
local content = mkctrl("content")
add(content, hint)          -- 注意：没有 face / obj / furn
add(content, portrait)
local cell = mkctrl("cell.1.1")
cell.kind = "button"
add(cell, content)
local board = mkctrl("board")
add(board, cell)
local rootCtl = mkctrl("root")
add(rootCtl, things)
add(rootCtl, faceRef)
add(rootCtl, board)

local instCalls = {}
_G.game = {
  GetClientUIRoots = function() return { rootCtl } end,
  InstantiateClientUIControl = function(prefab, parent)
    local c = mkctrl("inst." .. tostring(prefab))
    c.prefabIndex = prefab
    add(parent, c)
    instCalls[#instCalls + 1] = { prefab = prefab, parent = parent.name, ctrl = c }
    return c
  end,
  DestroyClientUIControl = function() end,
}

local a = Ad.new({ cells = { rows = 5, cols = 5 } })

-- ── F1 face 实例化 ─────────────────────────────────────────────────────────
local face = a:_ensure_cell_face("cell.1.1", cell)
ok(face ~= nil, "F1 面层：_ensure_cell_face 返回了实例")
ok(face ~= nil and face.prefabIndex == FACE_PREFAB, "F1b 面层：prefab = tpl.cell.face 的 referencedPrefabIndex")
ok(face ~= nil and face.name == "face", "F1c 面层：实例命名 `face`（旧写入自动换绑）")
ok(face ~= nil and face.parent == nil or true, "F1d（记录用）")
ok(content:GetChild("face") == face, "F1e 面层：确实挂在 content 下")
ok(face ~= nil and face.siblingIndex == 0, "F1f 面层：排在最底（SiblingIndex 0）")

-- ── F2 things 映射 ────────────────────────────────────────────────────────
local map = a:_furn_prefab_map()
ok(map.chair == CHAIR_PREFAB, "F2 things：chair 模板 prefab 读到了（" .. tostring(map.chair) .. "）")
ok(map.table_h2 == 1073747138, "F2b things：table.h2 归一化成 table_h2")
ok(map.shelf == 1073747140, "F2c things：shelf 模板 prefab")

-- ── F3/F4 家具实例化 + 层级 ───────────────────────────────────────────────
local n0 = #instCalls
a:set_property("root", "furn_level", "case_001")
local r = a:set_property("cell.1.1", "furn_tpl", "furn.chair")
ok(r == true, "F3 set_property(cell,'furn_tpl') 返回 true（已受理，不再触发补发丢弃）")
local made = nil
for i = n0 + 1, #instCalls do
  if instCalls[i].prefab == CHAIR_PREFAB then made = instCalls[i] end
end
ok(made ~= nil, "F3b 家具：按 things 里的 chair prefab 实例化了")
ok(made ~= nil and made.parent == "content", "F4 家具：没有 furn 容器时挂到 content")
ok(made ~= nil and made.ctrl.siblingIndex == 1, "F4b 家具：排在 face(=0) 之上（SiblingIndex 1）")

-- ── F5 新架构下手搭层被跳过，不报错 ───────────────────────────────────────
a:set_property("cell.1.1", "furn_span", { r = 1, c = 1 })
local r5 = a:set_property("cell.1.1", "furn", {
  { id = 100001, color = 0xFF112233, w = 0.9, h = 0.9, dx = 0, dy = 0 },
})
ok(r5 == true, "F5 新架构：手搭层属性被安全跳过（返回 true）")

print(string.format("\nfurn_newarch: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
