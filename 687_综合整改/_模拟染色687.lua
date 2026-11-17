
local kids = {}
local function mk(n) return { name=n, imageColor=0xFF123456 } end
for _, q in ipairs({"art683.modal.settle.outline.body","art683.modal.settle.outline.left",
  "art683.modal.settle.outline.right","art682.modal.settle.capsule.body",
  "art682.modal.settle.capsule.left","art682.modal.settle.capsule.right"}) do
  kids[#kids+1] = mk(q)
end
local art = { GetChildren=function(self) return kids end }
local self = { sub=function(self,id,child) if child=="art" then return art end return nil end }
local ctrl = { interactable=true }
local function run_enabled(self, ctrl, id, key, value)
  if key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
      -- ★ 687：682/683 把胶囊与描边收进名为 art 的 DECOR 容器后，bg 子层已不存在，
      --   上面的染色够不到按钮 ⇒ 未启用结算时不再变灰。这里沿 art 容器逐层恢复/置灰。
      --   颜色口径：启用 outline=#FF6C402E / capsule=#FFFCECD4；禁用统一 #FF686B70。
      local art = self:sub(id, "art")
      if art ~= nil then
        local kids = nil
        pcall(function() kids = art:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do
            local k = kids[i]
            if k ~= nil then
              local nm = nil
              pcall(function() nm = k.name end)
              local outline = (type(nm) == "string" and nm:find("outline") ~= nil)
              pcall(function()
                if k.imageColor ~= nil then
                  k.imageColor = value and (outline and 0xFF6C402E or 0xFFFCECD4) or 0xFF686B70
                end
              end)
            end
          end
        end
      end
    end
  end

end
local function count(want, outlineOnly)
  local n = 0
  for _, k in ipairs(kids) do
    local isOutline = k.name:find("outline") ~= nil
    if (not outlineOnly or isOutline) and k.imageColor == want then n = n + 1 end
  end
  return n
end
run_enabled(self, ctrl, "modal.settle", "enabled", false)
local gray = count(0xFF686B70, false)
run_enabled(self, ctrl, "modal.settle", "enabled", true)
local outline = count(0xFF6C402E, true)
local capsule = count(0xFFFCECD4, false)
print(string.format('%d %d %d', gray, outline, capsule))
