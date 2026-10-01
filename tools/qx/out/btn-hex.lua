-- murdoku-btn-hex：超限素材组 Lua 绘制脚本
-- 图片数量：6；静态图片资产：2 种
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
local ROOT = {0.0,0.0,256.0,256.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0}
local ELEMENTS = {
    {100001,0.0,0.0,176.0,102.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,27,32,48,255},
    {100003,0.0,77.0,176.0,52.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,27,32,48,255},
    {100003,0.0,-77.0,176.0,52.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,180.0,27,32,48,255},
    {100001,0.0,0.0,156.0,90.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,43,51,72,255},
    {100003,0.0,67.0,156.0,46.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,0,43,51,72,255},
    {100003,0.0,-67.0,156.0,46.0,0.5,0.5,0.5,0.5,0.5,0.5,1.0,1.0,180.0,43,51,72,255},
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
-- MILIASTRA_EDITOR_SCENE_V1 eyJ2ZXJzaW9uIjoxLCJkcmF3aW5nSGFzaCI6IjcxZjhlMzA5YjNkMWUzYTJjOTc4NWZhOGY3NGVlNjY5ZTMxOGNlODc0YzM0ZjlkYmJkN2NmMDAwM2JjMmVkYmEiLCJzY2VuZSI6eyJjYW52YXMiOnsid2lkdGgiOjI1Ni4wLCJoZWlnaHQiOjI1Ni4wLCJiYWNrZ3JvdW5kIjoiIzAwMDAwMCJ9LCJlbGVtZW50cyI6W3siaWQiOiJlZGdlX21pZCIsIm5hbWUiOiIiLCJ0eXBlIjoicmVjdGFuZ2xlIiwieCI6MTI4LjAsInkiOjEyOC4wLCJ3aWR0aCI6MTc2LjAsImhlaWdodCI6MTAyLjAsInJvdGF0aW9uIjowLjAsImNvbG9yIjoiIzFiMjAzMCIsIm9wYWNpdHkiOjEuMCwiekluZGV4IjowLCJpc0JhY2tncm91bmQiOmZhbHNlLCJ0ZXh0Qm94IjpudWxsLCJpbWFnZUFzc2V0SWQiOm51bGwsImltYWdlVGludCI6ZmFsc2V9LHsiaWQiOiJlZGdlX3RvcCIsIm5hbWUiOiIiLCJ0eXBlIjoidHJpYW5nbGUiLCJ4IjoxMjguMCwieSI6NTEuMCwid2lkdGgiOjE3Ni4wLCJoZWlnaHQiOjUyLjAsInJvdGF0aW9uIjowLjAsImNvbG9yIjoiIzFiMjAzMCIsIm9wYWNpdHkiOjEuMCwiekluZGV4IjoxLCJpc0JhY2tncm91bmQiOmZhbHNlLCJ0ZXh0Qm94IjpudWxsLCJpbWFnZUFzc2V0SWQiOm51bGwsImltYWdlVGludCI6ZmFsc2V9LHsiaWQiOiJlZGdlX2JvdCIsIm5hbWUiOiIiLCJ0eXBlIjoidHJpYW5nbGUiLCJ4IjoxMjguMCwieSI6MjA1LjAsIndpZHRoIjoxNzYuMCwiaGVpZ2h0Ijo1Mi4wLCJyb3RhdGlvbiI6MTgwLjAsImNvbG9yIjoiIzFiMjAzMCIsIm9wYWNpdHkiOjEuMCwiekluZGV4IjoyLCJpc0JhY2tncm91bmQiOmZhbHNlLCJ0ZXh0Qm94IjpudWxsLCJpbWFnZUFzc2V0SWQiOm51bGwsImltYWdlVGludCI6ZmFsc2V9LHsiaWQiOiJmaWxsX21pZCIsIm5hbWUiOiIiLCJ0eXBlIjoicmVjdGFuZ2xlIiwieCI6MTI4LjAsInkiOjEyOC4wLCJ3aWR0aCI6MTU2LjAsImhlaWdodCI6OTAuMCwicm90YXRpb24iOjAuMCwiY29sb3IiOiIjMmIzMzQ4Iiwib3BhY2l0eSI6MS4wLCJ6SW5kZXgiOjMsImlzQmFja2dyb3VuZCI6ZmFsc2UsInRleHRCb3giOm51bGwsImltYWdlQXNzZXRJZCI6bnVsbCwiaW1hZ2VUaW50IjpmYWxzZX0seyJpZCI6ImZpbGxfdG9wIiwibmFtZSI6IiIsInR5cGUiOiJ0cmlhbmdsZSIsIngiOjEyOC4wLCJ5Ijo2MS4wLCJ3aWR0aCI6MTU2LjAsImhlaWdodCI6NDYuMCwicm90YXRpb24iOjAuMCwiY29sb3IiOiIjMmIzMzQ4Iiwib3BhY2l0eSI6MS4wLCJ6SW5kZXgiOjQsImlzQmFja2dyb3VuZCI6ZmFsc2UsInRleHRCb3giOm51bGwsImltYWdlQXNzZXRJZCI6bnVsbCwiaW1hZ2VUaW50IjpmYWxzZX0seyJpZCI6ImZpbGxfYm90IiwibmFtZSI6IiIsInR5cGUiOiJ0cmlhbmdsZSIsIngiOjEyOC4wLCJ5IjoxOTUuMCwid2lkdGgiOjE1Ni4wLCJoZWlnaHQiOjQ2LjAsInJvdGF0aW9uIjoxODAuMCwiY29sb3IiOiIjMmIzMzQ4Iiwib3BhY2l0eSI6MS4wLCJ6SW5kZXgiOjUsImlzQmFja2dyb3VuZCI6ZmFsc2UsInRleHRCb3giOm51bGwsImltYWdlQXNzZXRJZCI6bnVsbCwiaW1hZ2VUaW50IjpmYWxzZX1dLCJtZXRhIjp7InNvdXJjZVR5cGUiOiJlZGl0b3IiLCJzb3VyY2VOYW1lIjoiYnRuLWhleCIsIndhcm5pbmdzIjpbXX0sImxpYnJhcnkiOnsiYWN0aXZlQ2F0ZWdvcnkiOiLln7rnoYDlvaLnirYiLCJjYXRlZ29yaWVzIjpbeyJrZXkiOiJmdW5jdGlvbi1pY29uLW1vbm8iLCJsYWJlbCI6IuWKn+iDveWbvuaghy3ljZXoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6ImZ1bmN0aW9uLWljb24tY29sb3IiLCJsYWJlbCI6IuWKn+iDveWbvuaghy3lvanoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6ImdhbWVwbGF5LWljb24tbW9ubyIsImxhYmVsIjoi546p5rOV5Zu+5qCHLeWNleiJsiIsInN1cHBvcnRlZCI6ZmFsc2V9LHsia2V5IjoiZ2FtZXBsYXktaWNvbi1jb2xvciIsImxhYmVsIjoi546p5rOV5Zu+5qCHLeW9qeiJsiIsInN1cHBvcnRlZCI6ZmFsc2V9LHsia2V5Ijoib3JuYW1lbnQtbW9ubyIsImxhYmVsIjoi6KOF6aWw5Zu+5qGILeWNleiJsiIsInN1cHBvcnRlZCI6ZmFsc2V9LHsia2V5Ijoib3JuYW1lbnQtY29sb3IiLCJsYWJlbCI6IuijhemlsOWbvuahiC3lvanoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6ImZsb29yLW1vbm8iLCJsYWJlbCI6IuWcsOadvy3ljZXoibIiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6ImZsb29yLWNvbG9yIiwibGFiZWwiOiLlnLDmnb8t5b2p6ImyIiwic3VwcG9ydGVkIjpmYWxzZX0seyJrZXkiOiJiYXNpYy1zaGFwZSIsImxhYmVsIjoi5Z+656GA5b2i54q2Iiwic3VwcG9ydGVkIjp0cnVlfSx7ImtleSI6ImRpdmlkZXIiLCJsYWJlbCI6IuWIhuWJsue6vyIsInN1cHBvcnRlZCI6ZmFsc2V9LHsia2V5Ijoic2tpbGwtdGFsZW50IiwibGFiZWwiOiLmioDog73lpKnotYsiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6InNwZWNpYWwtY2hhcmFjdGVyIiwibGFiZWwiOiLnibnmrorlrZfnrKYiLCJzdXBwb3J0ZWQiOmZhbHNlfSx7ImtleSI6Iml0ZW0iLCJsYWJlbCI6IumBk+WFtyIsInN1cHBvcnRlZCI6ZmFsc2V9LHsia2V5IjoiY3JlYXRpb24iLCJsYWJlbCI6IumAoOeJqSIsInN1cHBvcnRlZCI6ZmFsc2V9XSwiYmFzZVNoYXBlUHJlc2V0cyI6W3sidHlwZSI6ImVsbGlwc2UiLCJjb2xvciI6IiMwZjc2NmUiLCJ3aWR0aCI6ODguMCwiaGVpZ2h0Ijo4OC4wfSx7InR5cGUiOiJyZWN0YW5nbGUiLCJjb2xvciI6IiNjMjQxMGMiLCJ3aWR0aCI6MTAyLjAsImhlaWdodCI6NzAuMH0seyJ0eXBlIjoidHJpYW5nbGUiLCJjb2xvciI6IiM3YzNhZWQiLCJ3aWR0aCI6OTYuMCwiaGVpZ2h0Ijo4Ni4wfSx7InR5cGUiOiJmb3VyX3BvaW50X3N0YXIiLCJjb2xvciI6IiMwZjRjODEiLCJ3aWR0aCI6OTAuMCwiaGVpZ2h0Ijo5MC4wfSx7InR5cGUiOiJmaXZlX3BvaW50X3N0YXIiLCJjb2xvciI6IiNiZTEyM2MiLCJ3aWR0aCI6OTIuMCwiaGVpZ2h0Ijo5Mi4wfSx7InR5cGUiOiJyaW5nIiwiY29sb3IiOiIjZjU5ZTBiIiwid2lkdGgiOjkyLjAsImhlaWdodCI6OTIuMH0seyJ0eXBlIjoidGV4dGJveCIsImNvbG9yIjoiI2ZmZmZmZiIsIndpZHRoIjoxODAuMCwiaGVpZ2h0Ijo0MC4wfV0sInNhdmVkSXRlbXMiOltdfX19
