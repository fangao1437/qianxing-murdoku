-- v14：以下函数在适配刷新时被调用，所有长度使用 1600 宽设计空间。
local function adapt14_background(w,h,transform)
  -- 原画 y=45..862 为有效区域。各边保留两个设计单位的采样余量。
  local scene=math.max((w+4)/1600,(h+4)/817)
  local shift=3.5*scene
  transform('adapt715r.background',0,shift,scene)
  transform('art642.select.backdrop',0,0,math.max((w+4)/1600,(h+4)/900))
  return scene,shift
end

local PHOTO14={ -- PHOTO_ROWS
}
local function adapt14_photo(find,transform,scene,shift,foreground,page)
  local board=find('stage')
  local bx,by=adapt715r_pair(board,'GetAnchoredPosition')
  local dx,dy=0,0
  if page=='game' and type(bx)=='number' and type(by)=='number' then dx,dy=bx-100,by+10 end
  -- 拍立得与火漆的共同变换以棋盘原中心 (100,-10) 为基点。
  local ox=dx+100*(1-foreground)
  local oy=dy-10*(1-foreground)
  for _,p in ipairs(PHOTO14) do
    transform(p[1],(ox+p[2]*foreground)/scene,(oy+p[3]*foreground-shift)/scene,foreground*p[4]/scene)
  end
  transform('adapt715r.WAX.12',ox,oy,foreground)
end

local function adapt14_corner(w,h,side)
  local scale=math.min(1.12,w/1600,h/900)
  local sign=side=='tr' and 1 or -1
  return sign*(w-1600*scale)/2,sign*(h-900*scale)/2,scale
end

local function adapt14_cards(w,h)
  -- 左右各为翻页控件保留 140，另留 16 空隙。四卡实际最外缘距中心 480。
  return math.min(math.max(w/1600,h/900),(w/2-156)/480,h/600)
end
local function adapt14_pagers(find,transform,w)
  for _,v in ipairs({{'left','adapt715r.LM.19','hit.select.prev',-1},{'right','adapt715r.RM.20','hit.select.next',1}}) do
    local art=find('art647.select.diamond.'..v[1])
    local hit=find(v[3])
    local x,y=adapt715r_pair(art,'GetAnchoredPosition')
    local hw,hh=adapt715r_pair(hit,'GetSizeDelta')
    if x and y and hw and hh and hw>0 and hh>0 then
      local center=v[4]*(w/2-12-hw/2)
      transform(v[2],center-x,0,1)
      transform(v[3],center,y,1)
    end
  end
end
