local ADAPT715R_SELECT_CARDS={'art642.select.paper','art642.select.thread','art642.select.lighting','art642.select.frames'}
local adapt715r={elapsed=1,handles={}}
local function sync_adapt715r(dt,force)
  if not adapter then return end
  local st=adapt715r
  local gen=adapter._lookup_gen or 0
  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.page=nil end
  local function find(name)
    if not st.handles[name] then st.handles[name]=adapter:find(name) end
    return st.handles[name]
  end
  local cur=Murdoku and Murdoku.current()
  local page=(cur and cur.controller and cur.controller.screen) or 'home'
  local selecting=page=='select'
  local function set_visible(c,want)
    if not c then return false end
    local ok,matched=pcall(function()
      local wrote=false
      if c.SetActive then c:SetActive(want);wrote=true end
      if c.SetVisible then c:SetVisible(want);wrote=true end
      local a,v=c.active,c.visible
      return wrote and (a==want or v==want) and a~=not want and v~=not want
    end)
    return ok and matched
  end
  local pageChanged=page~=st.page
  st.elapsed=st.elapsed+(dt or 0)
  if not force and not pageChanged and st.elapsed<.25 then return end
  st.elapsed=0
  local bg=find('adapt715r.background')
  local fill=find('adapt715r.background.fill')
  local base=find('art647.select.bg.base')
  local visible=set_visible(base,selecting)
  local bgWanted=page=='home' or page=='game'
  visible=set_visible(bg,bgWanted) and visible
  visible=set_visible(fill,true) and visible
  if fill then pcall(function() fill.imageColor=selecting and ADAPT715R_SELECT_COLOR or ADAPT715R_HOME_COLOR end) end
  if bg and not st.leaves then
    local ok,children=pcall(function() return bg:GetChildren() end)
    if ok and type(children)=='table' and #children==649 then st.leaves=children;st.leafState=nil end
  end
  if st.leaves and (st.leafState~=bgWanted or force) then
    local done=true
    for _,c in ipairs(st.leaves) do done=set_visible(c,bgWanted) and done end
    if done then st.leafState=bgWanted end
  end
  st.page=page -- 控件延迟出现时，按 0.25 秒刷新重试。
  local ok,cw,ch=pcall(function() return game.GetUICanvasSize() end)
  local function valid(x) return type(x)=='number' and x>0 and x<math.huge end
  if not ok or not valid(cw) or not valid(ch) then return end
  local slot=adapt715r_device()
  local w,h=1600,1600*ch/cw
  if not valid(h) then return end
  adapter._adapt715_canvas={physical_w=cw,physical_h=ch,w=w,h=h,unit=1}
  cw,ch=w,h
  local fit=math.min(w/1600,h/900)
  local cover=fit -- 同步原版火漆父级与场景，不裁主体。
  local cardScale=math.min(math.max(w/1600,h/900),w/1120,h/600)
  local eps=.002
  local function transform(name,x,y,s)
    local c=find(name)
    if not c then return false end
    local ok=pcall(function() c:SetAnchoredPosition(x,y);c:SetLocalScale(s,s,1) end)
    local a,b=adapt715r_pair(c,'GetLocalScale')
    local px,py=adapt715r_pair(c,'GetAnchoredPosition')
    return ok and a and b and px and py and math.abs(a-s)<eps and math.abs(b-s)<eps and math.abs(px-x)<eps and math.abs(py-y)<eps
  end
  transform('adapt715r.background',0,0,fit)
  transform('art642.select.backdrop',0,0,fit)
  local applied,missing,failed=0,0,0
  if slot~=nil then
  -- V12_TARGETS
  end
  -- V12_CARDS
  local signature=table.concat({page,w,h,tostring(slot),tostring(st.leafState),tostring(visible),missing,failed},'/')
  if st.signature~=signature then
    st.signature=signature
    print('[adapt715-v13] '..signature..' art='..fit..' cards='..cardScale..' leaves='..tostring(st.leaves and #st.leaves or 0))
  end
end
