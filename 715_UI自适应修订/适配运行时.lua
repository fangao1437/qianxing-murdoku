-- ADAPT715R BEGIN
-- TARGET_TABLE
local adapt715r = {elapsed=1,handles={},gen=nil,signature=nil,report=nil,backgroundNodes=nil}
local ADAPT715R_SELECT_BACKGROUND = {'art642.select.backdrop','art642.select.paper','art642.select.thread'}
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
  -- GetUICanvasSize 的单位未经过本机日志确认。只取比例，保持715的1600宽设计口径。
  -- 1280x576与1600x720必须产生同一组设计坐标，禁止直接用1280-1600造成+160右移。
  local w,h=1600,1600*ch/cw
  local mode='aspect-normalized-unverified'
  -- 固定画布无法推断屏幕比例。明确标识历史参考兜底，不能把它当实际测量。
  if (slot==1 or slot==3) and math.abs(cw-1600)<1 and math.abs(ch-900)<1 then w,h=1600,720;mode='mobile-reference-fallback' end
  -- 官方接口返回UI画布单位。背景使用原始画布尺寸，不套用普通UI的移动端定位兜底。
  local cover=math.max(cw/1600,ch/900)
  local applied,missing,failed=0,0,0
  local background=find('adapt715r.background')
  local background_ok=false
  if background then
    background_ok=pcall(function()
      background:SetAnchoredPosition(0,0)
      background:SetLocalScale(cover,cover,1)
    end)
    local a,b=adapt715r_pair(background,'GetLocalScale')
    background_ok=background_ok and a~=nil and math.abs(a-cover)<0.002 and math.abs(b-cover)<0.002
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
    local root_ok=set_visible(background,background_want) and set_visible(fill,background_want)
    visibility_ok=root_ok
    if background_want then
      if st.backgroundNodes==nil then
        local nodes={fill,background};local queue={background};local complete=true
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
        if complete and #nodes>=651 then st.backgroundNodes=nodes end
      end
      for _,c in ipairs(st.backgroundNodes or {}) do if not set_visible(c,true) then visibility_ok=false end end
    end
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
  -- v5：底纹/背景便签沿用cover；四张衬纸与白框共用卡片倍率。
  local cardScale=math.min(cover,cw/1120,ch/600)
  local fit=math.min(cw/1600,ch/900)
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
  transform('art642.select.board',0,0,1)
  local cardsOk=transform('art642.select.frames',0,0,cardScale)
  cardsOk=transform('art642.select.lighting',0,0,cardScale) and cardsOk
  for _,v in ipairs(ADAPT715R_TEARS) do
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
  local signature=string.format('%.3f/%.3f/%s/%s/%s/%s/%s/%s/%s/%s/%s',cw,ch,device,mode,tostring(gen),applied,missing,failed,tostring(background_ok),tostring(visibility_ok),tostring(select_applied))
  if signature~=st.signature then
    st.signature=signature
    print('[adapt715r-v5] background=client-cover wax=equivalent cover='..cover..' card_scale='..cardScale..' tear_scale='..fit..' background_ok='..tostring(background_ok)..' visibility_ok='..tostring(visibility_ok)..' select='..select_applied..'/8 select_failed='..select_failed..' canvas='..cw..'x'..ch..' layout='..w..'x'..h..' device='..device..' slot='..slot..' profile='..profile..' ratio='..actualRatio..' mode='..mode..' applied='..applied..'/'..#ADAPT715R_TARGETS..' missing='..missing..' failed='..failed)
    for _,n in ipairs({'root','stage','modal','home.select','clues','art641.game','art642.select.backdrop','adapt715r.background','adapt715r.background.fill'}) do
      local c=find(n);local x,y=adapt715r_pair(c,'GetAnchoredPosition');local a,b=adapt715r_pair(c,'GetSizeDelta');local sx,sy=adapt715r_pair(c,'GetLocalScale')
      local mnx,mny=adapt715r_pair(c,'GetAnchorMin');local mxx,mxy=adapt715r_pair(c,'GetAnchorMax')
      print('[adapt715r-v5-geometry] '..n..' pos='..tostring(x)..','..tostring(y)..' sizeDelta='..tostring(a)..','..tostring(b)..' scale='..tostring(sx)..','..tostring(sy)..' anchors='..tostring(mnx)..','..tostring(mny)..':'..tostring(mxx)..','..tostring(mxy))
    end
  end
end
-- ADAPT715R END
