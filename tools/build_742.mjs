// 从 741 v3 派生。坐标以设计稿缩放到 1920×1080 后的色块交界为准。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {loadTree,findScriptLeaf,writeGil} from './gil/gilwrite.mjs';
import {cloneField,asIdList,setChildList,pairOf,pairValue,setPair,textsOf,writeVarint} from './gil/gilread.mjs';
const repo=fileURLToPath(new URL('../',import.meta.url));
const base=path.join(repo,'741_调查背包/741_调查背包_v3.gil');
const out=path.resolve(process.argv[2]||path.join(repo,'../构建存档/742/742_调查背包美术还原_v12.gil'));
assert(!fs.existsSync(out),'输出文件已存在');
const g=loadTree(base), count=g.recs.length, leaf=findScriptLeaf(g), prefix='econ.bag741.';
assert.equal(createHash('sha256').update(g.src).digest('hex'),'088ac42f4760245112090e92287aaf4fc8616ac086c27af0c05f3213427a4f0f');
const F=(p,n)=>p?.sub?.find(f=>f.field===n);
const comp=(r,n)=>r.sub.filter(f=>f.field===505).map(f=>F(F(f,503),n)).find(Boolean);
const source=g.byName.get(prefix+'desk');
const root=g.recs.find(r=>r.id===source.parentId);
const children=asIdList(root.childList.payload,true).map(Number);
const art=[];
function shape(name,x,y,w,h,color,asset=100001,angle=0,visible='true'){assert(w>0&&h>0,name);art.push({name,x,y,w,h,color,asset,angle,visible})}
// 每边一枚原生等腰三角：外半边给出斜率，内半边埋入同色中央矩形。
// 侧面内部无旋转对角拼边；三角形尖端处的两条外轮廓自然会合。
function trap(name, top, bottom, leftTop, rightTop, leftBottom, rightBottom, color) {
  const left = Math.max(leftTop, leftBottom), right = Math.min(rightTop, rightBottom);
  for (const [side, axis, delta, tipAtTop] of [
    ['l', left, Math.abs(leftTop-leftBottom), leftTop === left],
    ['r', right, Math.abs(rightTop-rightBottom), rightTop === right],
  ]) {
    if (delta > 0) shape(`${name}.${side}`, axis-delta, top, 2*delta, bottom-top, color, 100003, tipAtTop ? 0 : 180);
  }
  shape(name, left, top, right-left, bottom-top, color);
}
function roundBox(name,x,y,w,h,top,bottom,col){shape(name+'.body',x,y+top,w,h-top-bottom,col);for(const [key,r,yy] of [['t',top,y],['b',bottom,y+h-bottom]]){shape(name+'.'+key,x+r,yy,w-2*r,r,col);for(const [i,xx] of [x,x+w-2*r].entries())shape(name+'.'+key+i,xx,key==='t'?yy:yy-r,2*r,2*r,col,100002)}}
shape('desk',-1920,-1080,5760,3240,'3D2518');
// 背景板以各自局部坐标绘制，先放右板，左板压住交会处。
function board(name,ox,oy,deg,parts){const a=deg*Math.PI/180;for(const [key,x,y,w,h,c] of parts){const u=x+w/2,v=y+h/2;shape(name+'.'+key,ox+u*Math.cos(a)-v*Math.sin(a)-w/2,oy+u*Math.sin(a)+v*Math.cos(a)-h/2,w,h,c,100001,-deg)}}
board('right',1211,323,6.1,[['edge',0,0,1470,732,'251B01'],['face',5,5,1460,722,'3B3D2B']]);
board('left',-62,345,-8.18,[['edge',0,0,1232,686,'251B01'],['band',5,5,1222,676,'3B3D2B'],['face',5,5,1222,398,'23241A'],['gold.top',25,32,1165,3,'7A5D19'],['gold.base',25,358,1165,3,'7A5D19'],['gold.left',25,32,3,329,'7A5D19'],['gold.end',1187,3,3,358,'7A5D19']]);
// 外皮连续铺到箱身后方。内层逐层提前止口，形成从亮内衬到下沿的折面。
trap('lid.edge', -193,169,-149,2069, 145,1775,'682703');
trap('lid.rim', -186,153,-131,2051, 143,1777,'934621');
trap('lid.wall', -167,145,-88,2008, 154,1766,'996035');
trap('lid.wall.light', -162,137,-72,1975, 160,1750,'B07841');
trap('lid.lining.bevel', -150,133,245,1675, 163,1757,'C28D54');
trap('lid.lining', -144,124,254,1666, 174,1746,'D6A86A');
// 短斜角把折口收进外皮；接合底色由 lid.edge 一直承托到箱身下方。
trap('lid.turn', 139,153,155,1765, 169,1751,'A96C3A');
trap('lid.turn.light', 139,144,162,1758, 169,1751,'BF8750');
for (const [i,x] of [425,1361].entries()) {
  const hinge=`hinge${i}`;
  trap(hinge+'.seat',143,168,x+4,x+130,x,x+134,'733916');
  shape(hinge+'.pin',x+6,149,122,11,'504438');
  for (const [j,offset,width] of [[0,9,30],[1,43,48],[2,95,30]]) {
    shape(`${hinge}.knuckle${j}`,x+offset,148,width,12,'766956');
    shape(`${hinge}.glint${j}`,x+offset+2,149,width-4,3,'A29073');
  }
}
roundBox('shell',139,160,1642,892,12,106,'682703');roundBox('hide',146,167,1628,877,8,99,'B36B47');
roundBox('inner',153,173,1610,816,7,56,'682703');roundBox('wall',160,180,1596,802,4,51,'AD6837');
// 左侧两行共用三列。在给定的箱口宽度内等分，格底和隔板都从同一个起点计算。
const gridLeft=160,gridRight=1118,ribWidth=32,inset=26,depth=42;
const opening=(gridRight-gridLeft-2*ribWidth)/3, pitch=opening+ribWidth;
const floorWidth=opening-inset, floorLeft=gridLeft+inset, upperFloorY=180+depth, upperFloorH=541-upperFloorY;
for(const [row,top,bottom] of [[0,180,541],[1,576,982]])for(let col=0;col<3;col++){
 const key=`slot${row}${col}`,left=gridLeft+col*pitch,x=left+inset,y=top+depth,h=bottom-y;
 // 侧壁垫在后壁之下。后壁左边从格口斜收到格底，两面共用一条折线。
 const curvedCorner=row===1 && col===0;
 shape(key+'.side',left,top,inset+1,bottom-top-(curvedCorner?36:0),'BC7946');
 trap(key+'.back',top,y,left,left+opening,x,left+opening,'995C35');
 // 后壁下沿的一笔落在格底以内，选中时仍露出壁面。
 shape(key+'.crease',x,y-3,floorWidth,4,'885331');
 if(row===1&&col===0){
   const r=36;
   shape(key+'.corner',x,bottom-2*r,2*r,2*r,'D6A86A',100002);
   shape(key+'.lower',x+r,bottom-r-1,floorWidth-r,r+1,'D6A86A');
   shape(key+'.floor',x,y,floorWidth,h-r,'D6A86A');
 }else shape(key+'.floor',x,y,floorWidth,h,'D6A86A');
 if(row===0&&col<2){
   const selected=`pick~=nil and slotOf[pick]==${col}`;
   shape(key+'.select.edge',x,y,floorWidth,h,'794426',100001,0,selected);
   shape(key+'.select.brass',x+5,y+5,floorWidth-10,h-10,'C48A3B',100001,0,selected);
   shape(key+'.select.face',x+9,y+9,floorWidth-18,h-18,'F8D891',100001,0,selected);
 }
}
shape('shelf.edge',153,541,997,35,'682703');shape('shelf.face',160,548,982,20,'B36B47');
for(const [i,x] of [gridLeft+opening,gridLeft+pitch+opening,gridRight].entries()){shape('rib'+i,x,180,32,802,'682703');shape('rib'+i+'.leather',x+7,180,17,802,'B36B47')}
shape('bin.back',1150,180,605,29,'9D613B');shape('bin.left',1150,180,19,802,'C68147');shape('bin.floor',1169,211,527,771,'D6A86A');
for(const [i,x] of [428,1374].entries()){roundBox('tab'+i,x,989,118,55,5,7,'742C03');roundBox('tab'+i+'.skin',x+5,989,108,55,3,6,'D6A86A');shape('tab'+i+'.hole',x+48,1006,22,22,'68422B',100002)}
// 复用原静态控件的 ID，额外图元才克隆。保留便签、返回旗、道具及热区。
const lua=leaf.buf.toString(), re=/^      push\(\{id='econ\.bag741\.([^']+)'[^\n]+$/gm;
const matches=[...lua.matchAll(re)],persistent=k=>/^(paper\.|return\.|item\.|title$|meta$|desc$|usage$|history$|qty\.|hit\.)/.test(k);
const old=matches.filter(m=>!persistent(m[1])).map(m=>g.byName.get(prefix+m[1]));assert(old.every(Boolean));assert(art.length>=old.length);
const used=new Set();function walk(arr,fn){for(const f of arr){fn(f);if(f.sub)walk(f.sub,fn)}}walk(g.tree,f=>{if(f.wt===0)used.add(Number(f.num))});let next=1073782000;
function states(r){return F(comp(r,13),12).sub.filter(f=>f.field===501).map(f=>F(f,502))}
const fix=n=>Math.round(n*1000)/1000;
function place(r,x,y,w,h){for(const s of states(r)){assert(setPair(pairOf(s,504),(x+w/2-960)*5/6,(540-y-h/2)*5/6));assert(setPair(pairOf(s,505),w*5/6,h*5/6))}}
function clone(key){const r=cloneField(source.field);while(used.has(next))next++;const id=next++;const bytes=writeVarint(source.id),name=prefix+'art742.'+key;walk(r.sub,f=>{if(f.wt===0&&Number(f.num)===source.id)f.num=BigInt(id);else if(!f.sub&&f.payload?.equals(bytes)){f.payload=writeVarint(id);f.len=f.payload.length}});const nf=textsOf(r.sub,[]).find(f=>f.payload.toString()===source.name);nf.payload=Buffer.from(name);nf.len=nf.payload.length;source.holder.push(r);return {field:r,id,name}}
const entries=[],ids=[],fields=[];
for(const [i,s] of art.entries()){const r=old[i]||clone(s.name),f=r.field;const [x,y,w,h]=[s.x,s.y,s.w,s.h].map(fix);place(f,x,y,w,h);for(const st of states(f)){const rot=F(st,508);rot.sub=s.angle?[{field:3,wt:5,f:s.angle}]:[];rot.payload=null;rot.len=s.angle?5:0}const img=comp(f,84);F(img,502).num=BigInt('0xff'+s.color);F(img,503).num=BigInt(s.asset);ids.push(r.id);fields.push(f);entries.push(`      push({id='${r.name}',parent='econ.ui742',kind='image',rect={x=${x},y=${y},w=${w},h=${h}},visible=${s.visible}})`)}
const oldIds=new Set(old.map(r=>r.id)),start=children.findIndex(id=>oldIds.has(id));const order=children.filter(id=>!oldIds.has(id));order.splice(start,0,...ids);
// 商城与背包共用一个满设计画布父级，父级缩放后视觉和点击热区保持同位。
const pageIds=new Set(g.recs.filter(r=>r.name?.startsWith('econ.shop736.')||r.name?.startsWith('econ.bag741.')).map(r=>r.id));
for(const id of ids)pageIds.add(id);
const pageOrder=order.filter(id=>pageIds.has(id));assert(pageOrder.length===pageIds.size,'商城/背包节点未全部进入根序列');
const groupProto=g.byName.get('art641.home');assert(groupProto&&groupProto.childList,'缺少可复用的容器记录 art641.home');
const groupField=cloneField(groupProto.field);while(used.has(next))next++;const groupId=next++;const groupName='econ.ui742';
walk(groupField.sub,f=>{if(f.wt===0&&Number(f.num)===groupProto.id)f.num=BigInt(groupId);else if(!f.sub&&f.payload?.equals(writeVarint(groupProto.id))){f.payload=writeVarint(groupId);f.len=f.payload.length}});
const groupText=textsOf(groupField.sub,[]).find(f=>f.payload?.toString()===groupProto.name);assert(groupText);groupText.payload=Buffer.from(groupName);groupText.len=groupText.payload.length;
const groupParent=F(groupField,504);assert(groupParent);groupParent.num=BigInt(root.id);const groupChild=F(groupField,503);assert(groupChild);setChildList(groupChild,pageOrder);
const group={id:groupId,name:groupName,parentId:root.id,field:groupField,childList:groupChild};place({sub:groupField.sub},0,0,1920,1080);for(const state of states(groupField)){
  for(const key of [502,503,506]) assert(setPair(pairOf(state,key),0.5,0.5));
}
groupProto.holder.push(groupField);
for(const r of g.recs){if(!pageIds.has(r.id))continue;const parent=F(r.field,504);assert(parent,r.name);parent.num=BigInt(groupId);r.parentId=groupId;}
for(const f of fields){const parent=F(f,504);assert(parent);parent.num=BigInt(groupId);}
const groupStart=order.findIndex(id=>pageIds.has(id));assert(groupStart>=0);const rootOrder=order.filter(id=>!pageIds.has(id));rootOrder.splice(groupStart,0,groupId);setChildList(root.childList,rootOrder);
// 保持序列化记录的绘制顺序也与子列表一致，尤其是新增的皮边和铰链。
const holder=source.holder, fieldSet=new Set(fields), firstIndex=holder.findIndex(f=>fieldSet.has(f));
const kept=holder.filter(f=>!fieldSet.has(f));kept.splice(firstIndex,0,...fields);holder.splice(0,holder.length,...kept);
// 原稿右侧裁区原点 (3780,580)。底纸上沿在 x=220/1550 处为 y=79/128，
// 屏幕坐标顺时针约 2.11°，控件 Z 角取负。两纸均约 1593×2400 原稿像素。
const sheets=[
 {key:'paper.under',x:1189.6,y:210.4,w:490.5,h:739,angle:-2.11,color:'987B54'},
 {key:'paper.top',x:1189.7,y:223,w:490.2,h:739.6,angle:0,color:'F6E7D2'},
];
let script=lua.replace(re,(line,k)=>persistent(k)?line:'');
for(const {key,x,y,w,h,angle,color} of sheets){
 const name=prefix+key, sheet=g.byName.get(name).field;
 place(sheet,x,y,w,h);
 for(const state of states(sheet)){
   const rotation=F(state,508);
   rotation.sub=[{field:3,wt:5,f:angle}];rotation.payload=null;rotation.len=5;
 }
 F(comp(sheet,84),502).num=BigInt('0xff'+color);
 const [entry]=matches.filter(m=>m[1]===key);
 assert(entry && script.includes(entry[0]),name);
 script=script.replace(entry[0],entry[0].replace(/rect=\{[^}]+\}/,`rect={x=${x},y=${y},w=${w},h=${h}}`));
}
// 商城名称缝线沿矩形周长排布，各边的起止留白各为半个间隔。
function patchOnce(before,after){assert.equal(script.split(before).length,2,before);script=script.replace(before,()=>after)}
function shopRect(n,x,y,w,h){
 const name='econ.shop736.s'+n, f=g.byName.get(name).field;
 const line=script.split('\n').find(l=>l.includes(`push({id='${name}',`));assert(line,name);
 const rect=[x,y,w,h].map(fix);place(f,...rect);
 for(const state of states(f)){const rot=F(state,508);rot.sub=[];rot.payload=null;rot.len=0}
 patchOnce(line,line.replace(/rect=\{[^}]+\}/,`rect={x=${rect[0]},y=${rect[1]},w=${rect[2]},h=${rect[3]}}`));
}
const stitchGap=16,left=1272,right=1724,top=140,bottom=204;
for(let i=0;i<9;i++)for(let j=0;j<2;j++){
 const pitch=(right-left)/9;
 shopRect(43+2*i+j,left+i*pitch+stitchGap/2,(j?bottom:top)-1.5,pitch-stitchGap,3);
}
for(let i=0;i<2;i++)for(let j=0;j<2;j++){
 const pitch=(bottom-top)/2;
 shopRect(61+2*i+j,(j?right:left)-1.5,top+i*pitch+stitchGap/2,3,pitch-stitchGap);
}
shopRect(77,1474.5,42,62,62);
shopRect(78,1479.5,47,52,52);
// 在独立棋盘预演，库存与落子编码到同一笔交易。回执只确认，不重复落子。
patchOnce('function Core:hint()',`function Core:preview_ticket_hint()
  local trial=setmetatable({},getmetatable(self))
  for k,v in pairs(self) do trial[k]=v end
  for k,v in pairs(placement_snapshot(self)) do trial[k]=v end
  trial.history={};for i,v in ipairs(self.history) do trial.history[i]=v end
  trial.redo_stack={}
  local ok,msg=trial:hint()
  if not ok then return nil,msg end
  return trial
end
function Core:hint()`);
const feedback=script.slice(script.indexOf('    self.hint635=nil\n    self:_clear_verdict()'),script.indexOf('  elseif action=="clue" then',script.indexOf('    used.position=used.position+1')));
assert(feedback.trim().endsWith('self:fx("hex.hint",M.EFFECTS.SELECT)'));
patchOnce(feedback,'    self:finish_position_hint()\n');
patchOnce('function Controller:hint635_action(action)',`function Controller:finish_position_hint()\n${feedback}end\nfunction Controller:hint635_action(action)`);
const saveEntry=script.match(/    local entry=\{level_id=id, elapsed=[^\n]+\n[^\n]+checkpoint=checkpoint_code\(current\)\}/)[0];
patchOnce(saveEntry,'    local entry=board_entry(current,id,solved,result)');
patchOnce('function Murdoku.trade(op,target)',`local function board_entry(session,id,solved,result)\n    local core=session.core\n${saveEntry.replace('local entry=','return ').replace('checkpoint_code(current)','checkpoint_code(session)')}\nend\nfunction Murdoku.trade(op,target)`);
patchOnce("    e.pos_last=table.concat",`    local trial,msg=core:preview_ticket_hint()
    if not trial then return false,msg end
    local level_id=current.level.id
    archive.records[level_id]=board_entry({core=trial,level=current.level,controller=c},level_id,false,nil)
    archive.recent=level_id
    e.pos_last=table.concat`);
patchOnce('  a._trade730={controller=c,op=op',`  if op=='position' then
    local ok,msg=current.core:hint()
    if not ok then return false,msg end
    local entry=archive.records[archive.recent]
    p.moves,p.elapsed,p.solved=entry.moves,entry.elapsed,entry.solved
    c:dismiss_action_confirm()
    c:finish_position_hint()
  end
  a._trade730={controller=c,op=op`);
const receipt=script.match(/        elseif tx.op=='position'[^\n]+\n[^\n]+\n[^\n]+/)[0];assert(receipt.includes('在第'));patchOnce(receipt,'');
script=script.replaceAll('选中一名人物，揭示其正确行列。','选中一名人物，将其棋子摆到正确位置。');
// 所有商城/背包节点统一挂到响应式父级，避免视觉层与点击热区分别缩放。
script=script.replace(/^(      push\(\{id='econ\.(?:shop736|bag741)\.[^\n]+)$/gm,line=>line.replace("parent='root'","parent='econ.ui742'"));
const groupEntry="      push({id='econ.ui742',parent='root',kind='container',rect={x=0,y=0,w=1920,h=1080},visible=true})";
function insertBeforeNode(name,lines){
  const anchor=`      push({id='${name}',`;
  assert.equal(script.split(anchor).length,2,`缺少唯一的页面插入点 ${name}`);
  script=script.replace(anchor,()=>lines.join('\n')+'\n'+anchor);
}
insertBeforeNode('econ.shop736.s0',[groupEntry]);
insertBeforeNode(prefix+matches.find(m=>persistent(m[1]))[1],[groupEntry,...entries]);
for(const line of entries) assert.equal(script.split(line).length,2,'背包美术未唯一注册：'+line);
// 道具、数量和点击区域随实测格子移动，游戏行为仍由原控制器负责。
const cellStart=script.indexOf('      local function cellX(key)');
const cellEnd=script.indexOf('      local pick=',cellStart);assert(cellStart>=0&&cellEnd>cellStart);
script=script.slice(0,cellStart)+`      local function cellX(key) return ${floorLeft}+(slotOf[key] or 0)*${pitch} end
      local function cellY(key) return ${upperFloorY} end
      local function cellWidth(key) return ${floorWidth} end
`+script.slice(cellEnd);
script=script.replace(re,(line,k)=>{
 if(!/^(item\.|qty\.|hit\.(clue|position)$)/.test(k))return line;
 const geometry=/rect=\{x=cellX\('([^']+)'\)\+\(([-.\d]+)\),y=cellY\('[^']+'\)\+\(([-.\d]+)\),w=([-.\d]+),h=([-.\d]+)\}/;
 const m=line.match(geometry);assert(m,k);const [,name,dx,dy,w,h]=m,key=`'${name}'`;
 if(k.startsWith('hit.'))return line.replace(geometry,`rect={x=cellX(${key}),y=cellY(${key}),w=cellWidth(${key}),h=${upperFloorH}}`);
 // 两格以同一比例围绕各自格心排列图标及数量。
 const scale=`(cellWidth(${key})/308)`;
 return line.replace(geometry,`rect={x=cellX(${key})+(${dx})*${scale},y=cellY(${key})+${upperFloorH/2}+(${fix(+dy-187)})*${scale},w=${w}*${scale},h=${h}*${scale}}`);
});
// 适配层按根控件路径查找，重挂后补充商城/背包的静态路径前缀。
script=script.replace('      route = "root/" .. name','      route = (name:match("^econ%.shop736%.") or name:match("^econ%.bag741%.")) and "root/econ.ui742/" .. name or "root/" .. name');
const runtime=`
-- ECON742 RESPONSIVE BEGIN
local econ742={elapsed=1,page=nil,gen=-1,signature=nil}
local function sync_econ742(dt,force)
  if not adapter then return end
  local cur=Murdoku and Murdoku.current()
  local ctrl=cur and cur.controller
  local page=ctrl and ctrl.screen or 'home'
  local active=page=='shop' or page=='bag'
  local st=econ742
  st.elapsed=st.elapsed+(dt or 0)
  local gen=adapter._lookup_gen or 0
  local pageChanged=page~=st.page or gen~=st.gen
  if not force and not pageChanged and st.elapsed<0.25 then return end
  st.elapsed=0;st.page=page;st.gen=gen
  local group=adapter:find('econ.ui742')
  if not group then return end
  local ok,cw,ch=pcall(function() return game.GetUICanvasSize() end)
  if not ok or type(cw)~='number' or type(ch)~='number' or cw<=0 or ch<=0 then return end
  local logicalW=1600
  local logicalH=logicalW*ch/cw
  -- 16:9 到 20:9 平滑引入上下边距，超宽设备沿用上限，避免按钮持续变小。
  local wide=math.max(0,math.min(1,(cw/ch*9-16)/4))
  local blend=wide*wide*(3-2*wide)
  local scale=math.min(1,logicalH/900)*(1-0.10*blend)
  -- 保持中心锚定：上部按键自然内收，下部按钮也有等量余地。
  local applied=pcall(function()
    if group.SetLocalScale then group:SetLocalScale(scale,scale,1) end
    if group.SetAnchoredPosition then group:SetAnchoredPosition(0,0) end
    if group.SetVisible then group:SetVisible(active) end
    if group.SetActive then group:SetActive(active) end
  end)
  local signature=table.concat({page,cw,ch,scale,tostring(active)},'/')
  if applied and st.signature~=signature then
    st.signature=signature
    print('[econ742] '..signature)
  end
end
-- ECON742 RESPONSIVE END
`;
const runtimeAnchor='local art641_cache = nil';assert(script.includes(runtimeAnchor));script=script.replace(runtimeAnchor,runtime+'\n'+runtimeAnchor);
script=script.replace('  sync_adapt715r(dt, false)','  sync_adapt715r(dt, false)\n  sync_econ742(dt, false)');
// 返回菜单和胜利共用一枚画布级遮罩，沿用购买确认的实际透明度和超铺几何。
const shadeProto=g.byName.get('econ.shop736.s148'), modal=g.byName.get('modal');
const shade=cloneField(shadeProto.field), shadeName='game742.shade';
while(used.has(next))next++;const shadeId=next++;
walk(shade.sub,f=>{if(f.wt===0&&Number(f.num)===shadeProto.id)f.num=BigInt(shadeId);else if(!f.sub&&f.payload?.equals(writeVarint(shadeProto.id))){f.payload=writeVarint(shadeId);f.len=f.payload.length}});
const shadeText=textsOf(shade.sub,[]).find(f=>f.payload.toString()===shadeProto.name);
shadeText.payload=Buffer.from(shadeName);shadeText.len=shadeText.payload.length;
F(shade,504).num=BigInt(root.id);holder.splice(holder.indexOf(modal.field),0,shade);
assert(rootOrder.includes(modal.id));setChildList(root.childList,[...rootOrder.filter(id=>id!==modal.id),shadeId,modal.id]);
patchOnce('    push({ id = "modal", kind = "panel"',`    push({ id = "game742.shade", parent = "root", kind = "image", rect = {x=-1920,y=-1080,w=5760,h=3240},
           visible = modal.kind == "exit_menu" or (modal.kind == "result" and modal.win == true) })
    push({ id = "modal", kind = "panel"`);
// 记录仍只领过普通档的关卡；无此后缀的历史奖励一律视为已足额发放。
patchOnce('local LEGACY_PRICE,REWARD=6,10','local LEGACY_PRICE=6');
patchOnce(`local function claim(e,id)
  local bit=case_bit(id)
  if bit and math.floor(e.mask/bit)%2==0 then e.mask=e.mask+bit; return true end
end`, `local function claim(e,id,outcome)
  local bit=case_bit(id)
  if not bit or (outcome~='success' and outcome~='perfect') then return end
  local ordinary=e.ordinary or 0
  if math.floor(e.mask/bit)%2==0 then
    e.mask=e.mask+bit
    if outcome=='success' then e.ordinary=ordinary+bit end
  elseif outcome=='perfect' and math.floor(ordinary/bit)%2==1 then
    e.ordinary=ordinary-bit
  end
end`);
patchOnce('earned=earned+math.floor(e.mask/2^i)%2','earned=earned+10*(math.floor(e.mask/2^i)%2)-5*(math.floor((e.ordinary or 0)/2^i)%2)');
patchOnce('return earned*REWARD-', 'return earned-');
patchOnce('claim(archive.econ,id)',"claim(archive.econ,id,'perfect')");
patchOnce('if result then claim(wallet,id) end','if result then claim(wallet,id,result.outcome) end');
patchOnce('local mask,bought,used,last,pb,pu,pl,old_clues','local mask,bought,used,last,pb,pu,pl,old_clues\n    local ordinary=0');
patchOnce("if field:sub(-1)=='P' then field=field:sub(1,-2) end",`if field:sub(-1)=='P' then field=field:sub(1,-2) end
      ordinary=tonumber(field:match('N(%d+)$')) or 0
      field=field:gsub('N%d+$','')`);
patchOnce('econ={pos_first=parts','econ={ordinary=ordinary,pos_first=parts');
patchOnce('if not mask or econ.mask>127',`if ordinary>127 then return nil,'经济记录无效' end
    for i=0,6 do if mask and math.floor(ordinary/2^i)%2>math.floor(econ.mask/2^i)%2 then return nil,'经济记录无效' end end
    if not mask or econ.mask>127`);
patchOnce("e.pos_last,e.old_clues)..(e.pos_first", "e.pos_last,e.old_clues)..((e.ordinary or 0)>0 and ('N'..string.format('%d',e.ordinary)) or '')..(e.pos_first");
// 每次进入棋盘锁定库存与累计消耗。用确认后的消耗差显示本次入场已用张数。
patchOnce('function Murdoku.wallet()',`function Murdoku.begin_ticket_visit()
  local a=current.adapter
  current.ticket_entry=nil
  if not a._archive_ready then return end
  local slot=a._save_pending or a._confirmed
  local archive={records={}}
  if slot then archive=archive_decode(slot) end
  if not archive then return end
  local e=purse(archive)
  local _,clues,positions=funds(e)
  current.ticket_entry={clues=clues,positions=positions,used=e.used,pos_used=e.pos_used}
end
function Murdoku.wallet()`);
patchOnce('e.last,positions,e.pos_last,e.pos_first\nend','e.last,positions,e.pos_last,e.pos_first,e.used,e.pos_used\nend');
patchOnce('  current = self\n','  current = self\n  if not controller.screen then Murdoku.begin_ticket_visit() end\n');
patchOnce('    on_hint_saved = function()', '    on_ticket_restart = Murdoku.begin_ticket_visit,\n    on_hint_saved = function()');
patchOnce('  self.core.hint635_used=nil','  if self.opts.on_ticket_restart then self.opts.on_ticket_restart() end\n  self.core.hint635_used=nil');
patchOnce('if not controller._continue_requested then controller:do_restart() end','if controller._continue_requested then Murdoku.begin_ticket_visit() else controller:do_restart() end');
patchOnce('  current.core=restored; c.core=restored; c._false_clues=marks','  current.core=restored; c.core=restored; c._false_clues=marks\n  Murdoku.begin_ticket_visit()');
patchOnce('  a._archive_ready=true\n  local c=current.controller','  a._archive_ready=true\n  if not current.controller.screen and not current.ticket_entry then Murdoku.begin_ticket_visit() end\n  local c=current.controller');
patchOnce("  if op=='buy' then\n", "  if op~='buy' and not current.ticket_entry then Murdoku.begin_ticket_visit() end\n  if op=='buy' then\n");
patchOnce('  local title="提示"',`  local function stock(totalUsed,entryUsed,total)
    if totalUsed==nil or entryUsed==nil then return '（…/…）' end
    return '（'..math.max(0,totalUsed-entryUsed)..'/'..total..'）'
  end
  if state and state.kind=='menu' and (used.clue>=2 or used.position>=1) then
    local a=cur.adapter
    if not cur.ticket_entry then Murdoku.begin_ticket_visit() end
    local entry=cur.ticket_entry
    if not h.stockClue or h.stockSlot~=a._confirmed or h.stockEntry~=entry or h.stockReady~=a._archive_ready then
      local _,_,_,_,_,_,_,usedClues,usedPositions=Murdoku.wallet()
      h.stockClue=stock(usedClues,entry and entry.used,entry and entry.clues)
      h.stockPosition=stock(usedPositions,entry and entry.pos_used,entry and entry.positions)
      h.stockSlot=a._confirmed; h.stockReady=a._archive_ready; h.stockEntry=entry
    end
    signature=signature..h.stockClue..h.stockPosition
  end
  local title="提示"`);
patchOnce('"使用位置揭示券 ×1"','("使用位置揭示券"..(h.stockPosition or "（…/…）"))');
patchOnce('"使用核验券 ×1"','("使用核验券"..(h.stockClue or "（…/…）"))');
// 左旗复用右旗每个部件的镜像几何，保留左旗三角方向与返回箭头资源。
const geometryChecks=[];
function hudPair(st,key){return [0,1].map(i=>pairValue(pairOf(st,key),i))}
function mirrorHud(dest,ref){
  const dst=g.byName.get(dest),src=g.byName.get(ref);
  assert.equal(dst.states.length,4,dest);
  for(const [i,state] of dst.states.entries()){
    const other=src.states[i], [x,y]=hudPair(other,504), size=hudPair(other,505);
    assert(setPair(pairOf(state,504),-x,y));
    assert(setPair(pairOf(state,505),...size));
    geometryChecks.push({dest,i,position:[-x,y],size});
  }
}
for(const part of ['shadow','outline','outline.tri.top','outline.tri.bottom','ribbon','ribbon.tri.top','ribbon.tri.bottom']){
  const game=(key)=>part==='ribbon'?`art641.game.flag.${key}`:`art657.game.flag.${key}.${part}`;
  mirrorHud(game('back'),game('submit'));
  mirrorHud(`art647.select.back.${part}`,game('submit'));
}
for(const [dest,ref] of [['hex.back','hex.submit'],['select.back','hex.submit'],['hit.back','hit.submit'],['hit.select.back','hit.submit']]){
  mirrorHud(dest,ref);
  const target=(key)=>script.split('\n').find(line=>line.includes(`{name="${key}",kind=`));
  const before=target(dest),right=target(ref);
  assert(before&&right,dest);
  patchOnce(before,before.slice(0,before.indexOf('base='))+right.slice(right.indexOf('base=')).replace(/(\[\d\]=\{)([\d.]+)/g,'$1-$2'));
}
// 布局描述亦以存档坐标的 6/5 倍映射到设计画布，点击框独立于图标。
const submit=g.byName.get('hex.submit').states[0];
const [sx,sy]=hudPair(submit,504), [iw,ih]=hudPair(submit,505);
const [hw,hh]=hudPair(g.byName.get('hit.submit').states[0],505);
const cx=800-sx,cy=450-sy;
const canvasRect=(w,h)=>`{ x = ${Math.round((cx-w/2)*1.2)}, y = ${Math.round((cy-h/2)*1.2)}, w = ${Math.round(w*1.2)}, h = ${Math.round(h*1.2)} }`;
patchOnce('100109,   60,   48,  62,  62','100109, '+[cx-iw/2,cy-ih/2,iw,ih].map(fix).join(', '));
patchOnce('icon_template = false,          \n        rect = rect,',`icon_template = false,          \n        rect = a[1]=='hex.back' and ${canvasRect(hw,hh)} or rect,`);
patchOnce('local BACK_RECT = { x = 60, y = 48, w = 62, h = 62 }','local BACK_RECT = '+canvasRect(iw,ih));
patchOnce('rect = BACK_RECT,\n             event',`rect = ${canvasRect(hw,hh)},\n             event`);
script=script.replaceAll('构建标记 v741 / 调查背包 v3','构建标记 v742 / 调查背包美术还原 v12');leaf.field.payload=Buffer.from(script);
fs.mkdirSync(path.dirname(out),{recursive:true});writeGil(g,out,{label:'742 背包美术 v12',expectMarker:'v742',expectRecs:count+art.length-old.length+2,assert:b=>{assert(findScriptLeaf(b).buf.equals(leaf.field.payload));const saved=b.recs.find(r=>r.id===root.id);const rootIds=asIdList(saved.childList.payload,true).map(Number);assert(rootIds.includes(groupId));assert.equal(b.byName.get(groupName).parentId,root.id);for(const [i,id] of ids.entries()){const f=b.recs.find(r=>r.id===id).field;assert.equal(Number(F(comp(f,84),503).num),art[i].asset);assert.equal(states(f).length,4)}for(const {key,angle,color} of sheets){const sheet=b.byName.get(prefix+key).field;assert.equal(Number(F(comp(sheet,84),503).num),100001);assert.equal(F(comp(sheet,84),502).num,BigInt('0xff'+color));for(const st of states(sheet))assert(Math.abs(F(F(st,508),3).f-angle)<0.0001,key)}for(const {dest,i,position,size} of geometryChecks){const st=b.byName.get(dest).states[i];assert.deepEqual(hudPair(st,504),position,dest);assert.deepEqual(hudPair(st,505),size,dest)}console.log('返回键回读通过',geometryChecks.length,'组状态');const t=spawnSync('lua',[path.join(repo,'tests/shop_cold_render.lua')],{input:findScriptLeaf(b).buf,encoding:'utf8'});assert.equal(t.status,0,t.stderr||t.error?.message);console.log(t.stdout.trim());return true}});console.log(out,`美术图元 ${art.length}，复用 ${old.length}，新增 ${art.length-old.length}，响应式父级 ${groupName}`);
