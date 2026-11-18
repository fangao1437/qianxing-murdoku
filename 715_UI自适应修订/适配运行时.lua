-- ADAPT715R BEGIN
-- TARGET_TABLE
local adapt715r = {elapsed=1,handles={},gen=nil,signature=nil,report=nil,backgroundNodes=nil}
local ADAPT715R_SELECT_BACKGROUND = {'art642.select.backdrop'}
local ADAPT715R_SELECT_CARDS = {'art642.select.paper','art642.select.thread','art642.select.lighting','art642.select.frames'}
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
local ADAPT715R_PROFILES = {
  [0] = {{name='PC 16:9',ratio=16/9},{name='PC 21:9',ratio=21/9}},
  [1] = {{name='触屏 16:9',ratio=16/9},{name='触屏 19.5:9',ratio=19.5/9},{name='触屏 4:3',ratio=4/3}},
  [2] = {{name='主机手柄 16:9',ratio=16/9},{name='主机手柄 21:9',ratio=21/9}},
  [3] = {{name='移动手柄 16:9',ratio=16/9},{name='移动手柄 19.5:9',ratio=19.5/9},{name='移动手柄 4:3',ratio=4/3}},
}
local function adapt715r_profile(slot,cw,ch)
  local list=ADAPT715R_PROFILES[slot] or ADAPT715R_PROFILES[0]
  local ratio=cw/ch
  local best,bestd=list[1],math.huge
  for _,p in ipairs(list) do local d=math.abs(ratio-p.ratio);if d<bestd then best,bestd=p,d end end
  return best.name,ratio
end
local function sync_adapt715r(dt,force)
  if not adapter then return end
  local st=adapt715r; st.elapsed=st.elapsed+(dt or 0)
  if not force and st.elapsed<0.25 then return end
  st.elapsed=0
  local gen=adapter._lookup_gen or 0
  if gen~=st.gen then st.handles={};st.gen=gen;st.signature=nil;st.backgroundNodes=nil end
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
  local profile,actualRatio=adapt715r_profile(slot,cw,ch)
  -- v12：沿用v3的1600宽设计口径，只以API宽高比计算可见高度。
  -- 相同比例的1280x576、1600x720、1920x864必须得到相同设计坐标。
  -- 不再把移动端固定成720高：4:3为1200、16:10为1000，背景同时补足上下。
  -- 这是基于v3实机对照的映射候选；API若固定返回16:9仍无法推断真实屏幕。
  local physicalW,physicalH=cw,ch
  local unit=1
  local w,h=1600,1600*ch/cw
  local mode='v3-design-width-aspect-height'
  local root=find('root')
  if not root then return end
  -- 保留原生root变换；不写回根尺寸、缩放和位置，避免改变宿主映射。
  local rw,rh=adapt715r_pair(root,'GetSizeDelta')
  local rsx,rsy=adapt715r_pair(root,'GetLocalScale')
  local rx,ry=adapt715r_pair(root,'GetAnchoredPosition')
  local rminx,rminy=adapt715r_pair(root,'GetAnchorMin')
  local rmaxx,rmaxy=adapt715r_pair(root,'GetAnchorMax')
  local rpx,rpy=adapt715r_pair(root,'GetPivot')
  local function near(a,b,eps)
    return type(a)=='number' and a==a and math.abs(a-b)<eps
  end
  local root_ready=near(rw,0,.01) and near(rh,0,.01)
    and near(rsx,unit,.002) and near(rsy,unit,.002)
    and near(rx,0,.01) and near(ry,0,.01)
    and near(rminx,0,.002) and near(rminy,0,.002)
    and near(rmaxx,1,.002) and near(rmaxy,1,.002)
    and near(rpx,.5,.002) and near(rpy,.5,.002)
  if not root_ready then
    if st.report~='root-transform-pending' then
      print('[adapt715r-v12] root-transform-pending; retry next refresh')
      st.report='root-transform-pending'
    end
    return
  end
  if st.report=='root-transform-pending' then st.report=nil end
  -- cfg中的1600x900仍是原始设计坐标转换的原点，不能改成物理像素。
  -- editor_card_box与动态rect仍在同一原生UI空间；不附加根缩放。
  adapter._adapt715_canvas={physical_w=physicalW,physical_h=physicalH,w=w,h=h,unit=unit}
  cw,ch=w,h
  local cover=math.max(w/1600,h/900)
  local applied,missing,failed=0,0,0
  local background=find('adapt715r.background')
  local background_ok=false
  if background then
    background_ok=pcall(function()
      background:SetAnchoredPosition(0,0)
      background:SetLocalScale(cover,cover,1)
    end)
    local a,b=adapt715r_pair(background,'GetLocalScale')
    background_ok=background_ok and a~=nil and b~=nil and math.abs(a-cover)<0.002 and math.abs(b-cover)<0.002
  end
  -- v6：背景树按页面互斥。原 v5 每帧把完整背景树强制打开，导致选关/弹窗状态串层。
  -- 页面根层仍由原有 sync_art641 / 渲染器负责；适配层只管理自己新增的完整背景。
  local visibility_ok=true
  local fill=find('adapt715r.background.fill')
  local cur=Murdoku.current();local ctrl=cur and cur.controller
  local page=(ctrl and ctrl.screen) or 'game'
  local background_want=(page=='game' or page=='home')
  local function set_visible(c,want)
    if not c then return false end
    return pcall(function()
      if c.SetActive then c:SetActive(want) end
      if c.SetVisible then c:SetVisible(want) end
    end)
  end
  if background and fill then
    -- v8：首层不透明底色跨页面常驻，选关不再关闭兜底。
    local root_ok=set_visible(background,background_want) and set_visible(fill,true)
    visibility_ok=root_ok
    pcall(function()
      fill.imageColor=page=='select' and ADAPT715R_SELECT_COLOR or ADAPT715R_HOME_COLOR
      fill:SetAnchorMin(0,0);fill:SetAnchorMax(1,1);fill:SetPivot(.5,.5)
      fill:SetSizeDelta(0,0);fill:SetAnchoredPosition(0,0);fill:SetLocalScale(1,1,1)
    end)
    if st.backgroundNodes==nil then
      local nodes={background};local queue={background};local complete=true
      for i=1,2 do
        local nextq={}
        for _,parent in ipairs(queue) do
          local good,children=pcall(function() return parent:GetChildren() end)
          if good and type(children)=='table' then
            for _,child in ipairs(children) do nodes[#nodes+1]=child;nextq[#nextq+1]=child end
          else complete=false end
        end
        queue=nextq
      end
      if complete and #nodes>=650 then st.backgroundNodes=nodes end
    end
    -- 不依赖父隐藏级联，离开背景页逐层关闭；重新进入逐层恢复。
    for _,c in ipairs(st.backgroundNodes or {}) do if not set_visible(c,background_want) then visibility_ok=false end end
  else visibility_ok=false end
  local eps=0.002
  for _,t in ipairs(ADAPT715R_TARGETS) do
    local c=find(t.name)
    if c==nil then missing=missing+1 else
      local p=t.base[slot] or t.base[0]
      local x,y=p[1]+(t.ax-.5)*(w-1600),p[2]+(t.ay-.5)*(h-720)
      local sx,sy=1,1
      if t.kind=='WAX' then
        -- 火漆与整张背景保持独立父级；两棵树均以画布中心为原点。
        -- 子图元含相对背景中心的原始偏移，所以父级缩放同时变换位置与大小。
        sx,sy=cover,cover
        x,y=p[1]*cover,p[2]*cover
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
      local scale_ok=true
      if t.kind=='WAX' then
        local a,b=adapt715r_pair(c,'GetLocalScale')
        scale_ok=a~=nil and math.abs(a-sx)<eps and math.abs(b-sy)<eps
      end
      if good and scale_ok and px and math.abs(px-x)<eps and math.abs(py-y)<eps then applied=applied+1 else failed=failed+1 end
    end
  end
  -- v12：底纹独立cover；便签纸、连线、衬纸、白框及动态卡片共同限幅。
  -- 不能只限制卡片而让纸张继续放大，否则达到上限后又会分离。
  local cardScale=cover
  local cardMax=math.min(w/1120,h/600)
  if cardMax>0 then cardScale=math.min(cardScale,cardMax) end
  local fit=math.min(cover,math.min(w/1600,h/900))
  local select_applied,select_failed=0,0
  local function transform(name,x,y,s)
    local c=find(name);if not c then select_failed=select_failed+1;return false end
    local good=pcall(function() c:SetAnchoredPosition(x,y);c:SetLocalScale(s,s,1) end)
    local a,b=adapt715r_pair(c,'GetLocalScale');local px,py=adapt715r_pair(c,'GetAnchoredPosition')
    good=good and a and b and px and py and math.abs(a-s)<eps and math.abs(b-s)<eps and math.abs(px-x)<eps and math.abs(py-y)<eps
    if good then select_applied=select_applied+1 else select_failed=select_failed+1 end
    return good
  end
  for _,name in ipairs(ADAPT715R_SELECT_BACKGROUND) do transform(name,0,0,cover) end
  local selectBase=find('art647.select.bg.base')
  if selectBase then
    -- 构建时已移到root底层；按真实父容器拉伸，不用API数值缩窄底色。
    pcall(function()
      selectBase:SetAnchorMin(0,0);selectBase:SetAnchorMax(1,1);selectBase:SetPivot(.5,.5)
      selectBase:SetAnchoredPosition(0,0)
      selectBase:SetSizeDelta(4,4)
      selectBase:SetLocalScale(1,1,1)
    end)
    set_visible(selectBase,page=='select')
  end

  transform('art642.select.board',0,0,1)
  local cardsOk=true
  for _,name in ipairs(ADAPT715R_SELECT_CARDS) do
    cardsOk=transform(name,0,0,cardScale) and cardsOk
  end
  -- 撕边组已重挂到art641.select末尾；显隐逐叶处理，不依赖父级级联。
  for _,v in ipairs(ADAPT715R_TEARS) do
    local group=find(v.name)
    if group then
      set_visible(group,page=='select')
      pcall(function() group:SetAsLastSibling() end)
      local good,children=pcall(function() return group:GetChildren() end)
      if good and type(children)=='table' then
        for _,child in ipairs(children) do set_visible(child,page=='select') end
      end
    end
    local sign=v.side=='tr' and 1 or -1
    transform(v.name,sign*(cw-1600*fit)/2,sign*(ch-900*fit)/2,fit)
  end
  if cardsOk then
    if adapter._select715_scale~=cardScale or adapter._select715_gen~=gen then
      adapter._select715_scale=cardScale;adapter._select715_gen=gen
      local cur=Murdoku.current();local controller=cur and cur.controller
      if controller then controller.dirty=true;controller._props={} end
    end
    -- 正文属性可能被翻页重新写入；依据当前文字重算字号，不从上次字号累乘。
    for i=1,4 do
      for _,suffix in ipairs({'info','title','result'}) do
        local c=find('select.card.'..i..'.'..suffix)
        if c then pcall(function()
          local size=16*cardScale
          if suffix~='result' then
            local units=0;for ch in tostring(c.text or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do units=units+(#ch==1 and .55 or 1) end
            size=math.min(18,math.max(10,math.floor((182-6)/math.max(1,units))))*cardScale
          end
          c.adaptiveFontSize=false;c.minimumFontSize=size;c.fontSize=size
        end) end
      end
    end
  end
  local signature=string.format('%.3f/%.3f/%s/%s/%s/%s/%s/%s/%s/%s/%s/%.5f/%.5f',cw,ch,device,mode,tostring(gen),applied,missing,failed,tostring(background_ok),tostring(visibility_ok),tostring(select_applied),cover,cardScale)
  if signature~=st.signature then
    st.signature=signature
    print('[adapt715r-v12] background=client-cover wax=equivalent cover='..cover..' card_scale='..cardScale..' tear_scale='..fit..' background_ok='..tostring(background_ok)..' visibility_ok='..tostring(visibility_ok)..' select='..select_applied..'/12 select_failed='..select_failed..' reported_ui='..physicalW..'x'..physicalH..' unit='..unit..' canvas='..cw..'x'..ch..' layout='..w..'x'..h..' device='..device..' slot='..slot..' profile='..profile..' ratio='..actualRatio..' mode='..mode..' applied='..applied..'/'..#ADAPT715R_TARGETS..' missing='..missing..' failed='..failed)
    for _,n in ipairs({'root','stage','modal','home.select','clues','art641.game','art642.select.backdrop','art642.select.paper','art642.select.thread','art642.select.frames','art642.select.lighting','adapt715r.background','adapt715r.background.fill'}) do
      local c=find(n);local x,y=adapt715r_pair(c,'GetAnchoredPosition');local a,b=adapt715r_pair(c,'GetSizeDelta');local sx,sy=adapt715r_pair(c,'GetLocalScale')
      local mnx,mny=adapt715r_pair(c,'GetAnchorMin');local mxx,mxy=adapt715r_pair(c,'GetAnchorMax')
      print('[adapt715r-v12-geometry] '..n..' pos='..tostring(x)..','..tostring(y)..' sizeDelta='..tostring(a)..','..tostring(b)..' scale='..tostring(sx)..','..tostring(sy)..' anchors='..tostring(mnx)..','..tostring(mny)..':'..tostring(mxx)..','..tostring(mxy))
    end
  end
end
-- ADAPT715R END
