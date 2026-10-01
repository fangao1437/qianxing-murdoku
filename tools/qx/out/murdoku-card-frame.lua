-- murdoku-card-frame：超限素材组 Lua 绘制脚本
-- 图片数量：3；静态图片资产：1 种
-- 1. 准备一个客户端图片控件，设为「仅存为模板」。关闭模板遮罩/羽化。
-- 2. 必填：将下面 IMAGE_PREFAB_ID = 0 改为该图片控件的「控件模板索引ID」。
--    不是图片资产ID；只填这一处，脚本会自动切换每个图元的静态图片。
-- 3. 挂载：创建专用空客户端容器节点，将本文件作为客户端脚本挂到该节点。
--    进入运行预览即绘制（OnStart）。脚本会设置该节点尺寸，请不要挂在已有界面的根节点上。
-- 可选：BASE_SCALE 缩放；OFFSET_X/Y 平移（Y向上）。自定义图片需在当前关卡可用。
-- 保留键鼠布局；不转换嵌套组、文本、动态引用及组遮罩。

local IMAGE_PREFAB_ID = 0 -- 必填：客户端图片控件模板索引ID
local BASE_SCALE = 1
local OFFSET_X = 0
local OFFSET_Y = 0
-- 数据顺序：图片资产,x,y,w,h,pivotX,pivotY,anchorMinX,anchorMinY,anchorMaxX,anchorMaxY,scaleX,scaleY,rotZ,r,g,b,a
local ROOT = {0.0,0.0,512.0,512.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0}
local ELEMENTS = {
    {100001,0.0,0.0,480.0,480.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,43,47,58,255},
    {100001,0.0,-20.0,424.0,400.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,58,64,80,255},
    {100001,0.0,204.0,400.0,64.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,232,223,200,255},
}

local created = {}
local function Clear()
    for i = #created, 1, -1 do
        game.DestroyClientUIControl(created[i])
    end
    created = {}
end

function OnStart()
    Clear()
    if type(IMAGE_PREFAB_ID) ~= "number" or IMAGE_PREFAB_ID <= 0 or IMAGE_PREFAB_ID % 1 ~= 0 then
        printerr("[GIA绘制] 请填写 IMAGE_PREFAB_ID：客户端图片控件模板索引ID")
        return
    end
    local parent = script.object
    if parent == nil then return end
    parent:SetAnchorMin(0.5, 0.5)
    parent:SetAnchorMax(0.5, 0.5)
    parent:SetPivot(ROOT[5], ROOT[6])
    parent:SetSizeDelta(ROOT[3], ROOT[4])
    parent:SetLocalScale(ROOT[11] * BASE_SCALE, ROOT[12] * BASE_SCALE, 1)
    parent:SetLocalRotation(0, 0, ROOT[13])
    parent:SetAnchoredPosition(OFFSET_X, OFFSET_Y)
    local ok, err = pcall(function()
        for _, item in ipairs(ELEMENTS) do
            local image = game.InstantiateClientUIControl(IMAGE_PREFAB_ID, parent)
            if image == nil then error("图片模板无法实例化，请确认已设为仅存为模板") end
            table.insert(created, image)
            image:SetImage(Enum.ImageSource.StaticReference, item[1])
            -- imageType 仅部分图片支持，保留不支持该属性的静态图片。
            pcall(function() image.imageType = Enum.ImageType.Stretch end)
            image:SetAnchorMin(item[8], item[9])
            image:SetAnchorMax(item[10], item[11])
            image:SetPivot(item[6], item[7])
            image:SetSizeDelta(item[4], item[5])
            image:SetLocalScale(item[12], item[13], 1)
            image:SetLocalRotation(0, 0, item[14])
            image:SetAnchoredPosition(item[2], item[3])
            image.imageColor = Color.FromRGBA(item[15], item[16], item[17], item[18])
            image:SetAsLastSibling()
        end
    end)
    if not ok then
        Clear()
        printerr("[GIA绘制] " .. tostring(err))
    end
end

function OnDestroy()
    Clear()
end

-- 编辑器回导数据：保留图元名称、文本框与素材库，请勿删除。
-- MILIASTRA_EDITOR_SCENE_V1 eyJ2ZXJzaW9uIjoxLCJkcmF3aW5nSGFzaCI6IjFjMjFhMzhiN2Q1NmVmZTAyMTYwZDRmYmUwYmNlNGU1YTNmMTRjYjQ3Mjg0NjQ5YTQyOTU0MmYxMzA5N2M0YmEiLCJzY2VuZSI6eyJjYW52YXMiOnsid2lkdGgiOjUxMi4wLCJoZWlnaHQiOjUxMi4wLCJiYWNrZ3JvdW5kIjoiIzAwMDAwMCJ9LCJlbGVtZW50cyI6W3siaWQiOiJjYXJkIiwibmFtZSI6IiIsInR5cGUiOiJyZWN0YW5nbGUiLCJ4IjoyNTYuMCwieSI6MjU2LjAsIndpZHRoIjo0ODAuMCwiaGVpZ2h0Ijo0ODAuMCwicm90YXRpb24iOjAuMCwiY29sb3IiOiIjMmIyZjNhIiwib3BhY2l0eSI6MS4wLCJ6SW5kZXgiOjAsImlzQmFja2dyb3VuZCI6ZmFsc2UsInRleHRCb3giOm51bGwsImltYWdlQXNzZXRJZCI6bnVsbCwiaW1hZ2VUaW50IjpmYWxzZX0seyJpZCI6ImlubmVyIiwibmFtZSI6IiIsInR5cGUiOiJyZWN0YW5nbGUiLCJ4IjoyNTYuMCwieSI6Mjc2LjAsIndpZHRoIjo0MjQuMCwiaGVpZ2h0Ijo0MDAuMCwicm90YXRpb24iOjAuMCwiY29sb3IiOiIjM2E0MDUwIiwib3BhY2l0eSI6MS4wLCJ6SW5kZXgiOjEsImlzQmFja2dyb3VuZCI6ZmFsc2UsInRleHRCb3giOm51bGwsImltYWdlQXNzZXRJZCI6bnVsbCwiaW1hZ2VUaW50IjpmYWxzZX0seyJpZCI6InN0cmlwIiwibmFtZSI6IiIsInR5cGUiOiJyZWN0YW5nbGUiLCJ4IjoyNTYuMCwieSI6NTIuMCwid2lkdGgiOjQwMC4wLCJoZWlnaHQiOjY0LjAsInJvdGF0aW9uIjowLjAsImNvbG9yIjoiI2U4ZGZjOCIsIm9wYWNpdHkiOjEuMCwiekluZGV4IjoyLCJpc0JhY2tncm91bmQiOmZhbHNlLCJ0ZXh0Qm94IjpudWxsLCJpbWFnZUFzc2V0SWQiOm51bGwsImltYWdlVGludCI6ZmFsc2V9XSwibWV0YSI6eyJzb3VyY2VUeXBlIjoiZWRpdG9yIiwic291cmNlTmFtZSI6ImNhcmQtZnJhbWUiLCJ3YXJuaW5ncyI6W119LCJsaWJyYXJ5Ijp7ImFjdGl2ZUNhdGVnb3J5Ijoi5Z+656GA5b2i54q2IiwiY2F0ZWdvcmllcyI6W3sia2V5IjoiZnVuY3Rpb24taWNvbi1tb25vIiwibGFiZWwiOiLlip/og73lm77moIct5Y2V6ImyIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJmdW5jdGlvbi1pY29uLWNvbG9yIiwibGFiZWwiOiLlip/og73lm77moIct5b2p6ImyIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJnYW1lcGxheS1pY29uLW1vbm8iLCJsYWJlbCI6IueOqeazleWbvuaghy3ljZXoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6ImdhbWVwbGF5LWljb24tY29sb3IiLCJsYWJlbCI6IueOqeazleWbvuaghy3lvanoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6Im9ybmFtZW50LW1vbm8iLCJsYWJlbCI6IuijhemlsOWbvuahiC3ljZXoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6Im9ybmFtZW50LWNvbG9yIiwibGFiZWwiOiLoo4XppbDlm77moYgt5b2p6ImyIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJmbG9vci1tb25vIiwibGFiZWwiOiLlnLDmnb8t5Y2V6ImyIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJmbG9vci1jb2xvciIsImxhYmVsIjoi5Zyw5p2/LeW9qeiJsiIsInN1cHBvcnRlZCI6ZmFsc2V9LHsia2V5IjoiYmFzaWMtc2hhcGUiLCJsYWJlbCI6IuWfuuehgOW9oueKtiIsInN1cHBvcnRlZCI6dHJ1ZX0seyJrZXkiOiJkaXZpZGVyIiwibGFiZWwiOiLliIblibLnur8iLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6InNraWxsLXRhbGVudCIsImxhYmVsIjoi5oqA6IO95aSp6LWLIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJzcGVjaWFsLWNoYXJhY3RlciIsImxhYmVsIjoi54m55q6K5a2X56ymIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJpdGVtIiwibGFiZWwiOiLpgZPlhbciLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6ImNyZWF0aW9uIiwibGFiZWwiOiLpgKDniakiLCJzdXBwb3J0ZWQiOmZhbHNlfV0sImJhc2VTaGFwZVByZXNldHMiOlt7InR5cGUiOiJlbGxpcHNlIiwiY29sb3IiOiIjMGY3NjZlIiwid2lkdGgiOjg4LjAsImhlaWdodCI6ODguMH0seyJ0eXBlIjoicmVjdGFuZ2xlIiwiY29sb3IiOiIjYzI0MTBjIiwid2lkdGgiOjEwMi4wLCJoZWlnaHQiOjcwLjB9LHsidHlwZSI6InRyaWFuZ2xlIiwiY29sb3IiOiIjN2MzYWVkIiwid2lkdGgiOjk2LjAsImhlaWdodCI6ODYuMH0seyJ0eXBlIjoiZm91cl9wb2ludF9zdGFyIiwiY29sb3IiOiIjMGY0YzgxIiwid2lkdGgiOjkwLjAsImhlaWdodCI6OTAuMH0seyJ0eXBlIjoiZml2ZV9wb2ludF9zdGFyIiwiY29sb3IiOiIjYmUxMjNjIiwid2lkdGgiOjkyLjAsImhlaWdodCI6OTIuMH0seyJ0eXBlIjoicmluZyIsImNvbG9yIjoiI2Y1OWUwYiIsIndpZHRoIjo5Mi4wLCJoZWlnaHQiOjkyLjB9LHsidHlwZSI6InRleHRib3giLCJjb2xvciI6IiNmZmZmZmYiLCJ3aWR0aCI6MTgwLjAsImhlaWdodCI6NDAuMH1dLCJzYXZlZEl0ZW1zIjpbXX19fQ==
