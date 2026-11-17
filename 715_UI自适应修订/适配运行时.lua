-- ADAPT715R BEGIN
-- TARGET_TABLE
local adapt715r = {elapsed=1,handles={},gen=nil,signature=nil,report=nil}
local function adapt715r_pair(c,method)
  if c==nil then return nil end
  local ok,x,y=pcall(function() return c[method](c) end)
  if not ok then return nil end
  if type(x)=='number' and type(y)=='number' then return x,y end
  if x~=nil then local good,a,b=pcall(function() return x.x or x.X,x.y or x.Y end);if good then return a,b end end
end
local function adapt715r_device()
  local ok,d=pcall(function() return game.GetDevice() end)
  if not ok or d==nil then return nil,'unavailable' end
  local name=tostring(d)
  pcall(function() name=tostring(d.Name or d.FullName or d) end)
  local low=string.lower(name)
  if low:find('mobilecontroller',1,true) or low:find('controller_mobile',1,true) then return 3,name end
  if low:find('mobile',1,true) or low:find('touch',1,true) then return 1,name end
  if low:find('controller',1,true) or low:find('gamepad',1,true) then return 2,name end
  if low:find('keyboard',1,true) or low=='pc' then return 0,name end
  local found=nil
  pcall(function()
    for _,v in ipairs({{'Keyboard',0},{'Mobile',1},{'Controller',2},{'MobileController',3}}) do
      if Enum and Enum.Device and d==Enum.Device[v[1]] then found=v[2] end
    end
  end)
  return found,name
end
local function sync_adapt715r(dt,force)
  if not adapter then return end
  local st=adapt715r; st.elapsed=st.elapsed+(dt or 0)
  if not force and st.elapsed<0.25 then return end
  st.elapsed=0
  local gen=adapter._lookup_gen or 0
  if gen~=st.gen then st.handles={};st.gen=gen;st.signature=nil end
  local function find(n)
    if st.handles[n]==nil then st.handles[n]=adapter:find(n) end
    return st.handles[n]
  end
  local ok,cw,ch=pcall(function() return game.GetUICanvasSize() end)
  if not ok or type(cw)~='number' or type(ch)~='number' or cw~=cw or ch~=ch or cw<=0 or ch<=0 or cw==math.huge or ch==math.huge then
    if st.report~='canvas-invalid' then print('[adapt715r] canvas-invalid; native platform coordinates retained');st.report='canvas-invalid' end
    return
  end
  local slot,device=adapt715r_device()
  if slot==nil then
    if st.report~='device:'..device then print('[adapt715r] unknown-device='..device..'; native platform coordinates retained');st.report='device:'..device end
    return
  end
  local w,h=cw,ch
  local mode='canvas'
  -- 固定画布无法推断屏幕比例。明确标识历史参考兜底，不能把它当实际测量。
  if (slot==1 or slot==3) and math.abs(cw-1600)<1 and math.abs(ch-900)<1 then w,h=1600,720;mode='mobile-reference-fallback' end
  local applied,missing,failed=0,0,0
  local eps=0.002
  for _,t in ipairs(ADAPT715R_TARGETS) do
    local c=find(t.name)
    if c==nil then missing=missing+1 else
      local p=t.base[slot] or t.base[0]
      local x,y=p[1]+(t.ax-.5)*(w-1600),p[2]+(t.ay-.5)*(h-720)
      local sx,sy=1,1
      if t.kind=='WAX' then
        -- 服务器整张背景按其画布满幅拉伸；火漆独立复制等价仿射变换。
        -- 与UI的移动端参考高度分开，不把720假作服务器背景画布高度。
        sx,sy=cw/1600,ch/900
        x,y=p[1]*sx,p[2]*sy
      end
      local good=pcall(function()
        local px,py=adapt715r_pair(c,'GetAnchoredPosition')
        if px==nil or math.abs(px-x)>eps or math.abs(py-y)>eps then c:SetAnchoredPosition(x,y) end
        if t.kind=='WAX' then
          local a,b=adapt715r_pair(c,'GetLocalScale')
          if a==nil or math.abs(a-sx)>eps or math.abs(b-sy)>eps then c:SetLocalScale(sx,sy,1) end
        end
      end)
      local px,py=adapt715r_pair(c,'GetAnchoredPosition')
      if good and px and math.abs(px-x)<eps and math.abs(py-y)<eps then applied=applied+1 else failed=failed+1 end
    end
  end
  -- 选关背景自身等比铺满，其余客户端树不参与缩放。
  local backdrop=find('art642.select.backdrop')
  if backdrop then
    local scale=math.max(cw/1600,ch/900)
    pcall(function()
      local a,b=adapt715r_pair(backdrop,'GetLocalScale')
      if a==nil or math.abs(a-scale)>eps or math.abs(b-scale)>eps then backdrop:SetLocalScale(scale,scale,1) end
    end)
  end
  local signature=string.format('%.3f/%.3f/%s/%s/%s/%s/%s/%s',cw,ch,device,mode,tostring(gen),applied,missing,failed)
  if signature~=st.signature then
    st.signature=signature
    print('[adapt715r] canvas='..cw..'x'..ch..' layout='..w..'x'..h..' device='..device..' slot='..slot..' mode='..mode..' applied='..applied..'/'..#ADAPT715R_TARGETS..' missing='..missing..' failed='..failed)
    for _,n in ipairs({'root','stage','modal','home.select'}) do
      local c=find(n);local x,y=adapt715r_pair(c,'GetAnchoredPosition');local a,b=adapt715r_pair(c,'GetSizeDelta');local sx,sy=adapt715r_pair(c,'GetLocalScale')
      print('[adapt715r-protected] '..n..' pos='..tostring(x)..','..tostring(y)..' size='..tostring(a)..','..tostring(b)..' scale='..tostring(sx)..','..tostring(sy))
    end
  end
end
-- ADAPT715R END
