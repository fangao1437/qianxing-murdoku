--[[ 模板探针（v311）：回答两个问题
     ① 模板里的"模板引用控件"（第二层）能不能正常展开/实例化？
     ② 客户端脚本能不能在运行时改"模板引用控件"引用的模板？

     结果全部打到日志，前缀 `[tplprobe]`。用户导入存档 → 把这几行日志发回来即可。

     调用时机：main 的 OnUpdate 里"格子已建出来"之后跑一次（OnInit 时格子还没建，找不到实例）。
     ⚠️ 已知坑（integrator 实测）：cell.1.1/content 下有**两个**叫 `furn` 的控件——
        母本 content 里是**模板引用控件**（referencedPrefabIndex 有值），
        源 content 里是旧空容器（referencedPrefabIndex = nil）。
        ⇒ 这里按「名字是 furn **且** referencedPrefabIndex ~= nil」来找。
]]
local M = {}

local function P(...)
  local parts = { "[tplprobe]" }
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  print(table.concat(parts, " "))
end

local function name_of(c)
  if c == nil then return nil end
  local n = nil
  pcall(function() n = c.name end)
  return n
end

local function kids_of(c)
  local k = nil
  if c ~= nil and c.GetChildren ~= nil then pcall(function() k = c.GetChildren() end) end
  return type(k) == "table" and k or {}
end

local function ref_of(c)
  if c == nil then return nil end
  local v = nil
  pcall(function() v = c.referencedPrefabIndex end)
  return v
end

local function walk(c, depth, out, maxdepth)
  if c == nil then return end
  maxdepth = maxdepth or 4
  local t = nil
  pcall(function() t = typeof(c) end)
  local line = string.rep("  ", depth) .. tostring(name_of(c)) .. "  [" .. tostring(t) .. "]"
  local r = ref_of(c)
  if r ~= nil then line = line .. "  ref=" .. tostring(r) end
  out[#out + 1] = line
  if depth >= maxdepth then return end
  local ks = kids_of(c)
  for i = 1, #ks do walk(ks[i], depth + 1, out, maxdepth) end
end

-- 找"cell.1.1 那一格里、名字为 furn 且有引用值的"模板引用控件
local function find_ref(root, depth)
  if root == nil or depth > 30 then return nil end
  if name_of(root) == "furn" and ref_of(root) ~= nil then return root end
  local ks = kids_of(root)
  for i = 1, #ks do
    local r = find_ref(ks[i], depth + 1)
    if r ~= nil then return r end
  end
  return nil
end

local function find_by_name(root, name, depth)
  if root == nil or depth > 30 then return nil end
  if name_of(root) == name then return root end
  local ks = kids_of(root)
  for i = 1, #ks do
    local r = find_by_name(ks[i], name, depth + 1)
    if r ~= nil then return r end
  end
  return nil
end

function M.run(cfg)
  cfg = cfg or {}
  local g = _G.game
  if g == nil then P("没有 game，跳过") return end
  P("===== 开始（build=" .. tostring(cfg.build_marker or "?") .. "）=====")

  local roots = {}
  if g.GetClientUIRoots ~= nil then pcall(function() roots = g.GetClientUIRoots() end) end
  P("客户端根数量:", tostring(#roots))

  -- ① 引用控件：读 + 试写 ------------------------------------------------
  local ref = nil
  for i = 1, #roots do
    ref = find_ref(roots[i], 0)
    if ref ~= nil then break end
  end
  if ref == nil and g.GetClientUIControl ~= nil then
    pcall(function() ref = g.GetClientUIControl(1073747082) end)
  end
  P("找到模板引用控件:", tostring(ref ~= nil))
  if ref ~= nil then
    local t = nil pcall(function() t = typeof(ref) end)
    P("typeof =", tostring(t), " name=", tostring(name_of(ref)))
    local v0 = ref_of(ref)
    P("referencedPrefabIndex 回读 =", tostring(v0))

    -- 目标：furn.plant 的**源** GUID（integrator 实测：引用值指向模板源）
    local target = tonumber(cfg.tpl_probe_plant_src)
    if target ~= nil and target > 0 then
      local ok, err = pcall(function() ref.referencedPrefabIndex = target end)
      P("直接赋值 = " .. tostring(target) .. "  ok=" .. tostring(ok) .. "  err=" .. tostring(err))
      local v1 = ref_of(ref)
      P("赋值后回读 =", tostring(v1), " 改变了吗:", tostring(v1 ~= v0))
    end

    for _, m in ipairs({ "SetReferencedPrefabIndex", "SetPrefabIndex", "SetTemplateIndex",
                         "SetTemplate", "ChangeTemplate", "SetReference", "SetPrefab" }) do
      local mt = nil pcall(function() mt = typeof(ref[m]) end)
      P("候选方法 " .. m .. " =>", tostring(mt))
    end
  end

  -- ② 嵌套模板：实例化 + 递归打印子树 -------------------------------------
  local nest = tonumber(cfg.tpl_probe_nest_src)
  if nest ~= nil and nest > 0 then
    local parent = nil
    for i = 1, #roots do
      local b = find_by_name(roots[i], cfg.tpl_probe_parent or "board", 0)
      if b ~= nil then parent = b break end
    end
    if parent == nil and #roots > 0 then parent = roots[1] end
    P("嵌套模板实例化：prefab=" .. tostring(nest) .. " parent=" .. tostring(name_of(parent)))
    local ok, obj = pcall(g.InstantiateClientUIControl, nest, parent)
    if not ok or obj == nil then
      P("实例化失败 ok=" .. tostring(ok) .. " obj=" .. tostring(obj))
    else
      pcall(function() obj.name = "tplprobe.nest" end)
      P("实例化成功，name=" .. tostring(name_of(obj)))
      local lines = {}
      walk(obj, 0, lines, 4)
      for i = 1, math.min(#lines, 40) do P("树 " .. lines[i]) end
      P("子树控件数（含自身）:", tostring(#lines))
      local ks = kids_of(obj)
      P("直接子控件数:", tostring(#ks))
      for i = 1, math.min(#ks, 8) do
        local t2 = nil pcall(function() t2 = typeof(ks[i]) end)
        local v2 = ref_of(ks[i])
        P("子[" .. i .. "] name=" .. tostring(name_of(ks[i])) .. " type=" .. tostring(t2)
          .. " ref=" .. tostring(v2) .. " children=" .. tostring(#kids_of(ks[i])))
      end
    end
  else
    P("没配 cfg.tpl_probe_nest_src，跳过嵌套实例化测试")
  end

  P("===== 结束 =====")
end

return M
