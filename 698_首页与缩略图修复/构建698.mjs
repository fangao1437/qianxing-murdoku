// 698：从不可变697基线生成，实际控件池、索引与弹窗显隐修复。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url));
const ROOT=path.resolve(DIR,'../..');
const TMP='C:/Users/18182/AppData/Local/Temp/feibo/dc8b3f22-b61a-4842-b219-754f2e124c5d/698-repair';
fs.mkdirSync(TMP,{recursive:true});
const tools=path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil');
const R=await import(pathToFileURL(path.join(tools,'gilread.mjs')));
const W=await import(pathToFileURL(path.join(tools,'gilwrite.mjs')));
const input=path.join(DIR,'../697_凹角内收与缩略图居中/697_凹角内收与缩略图居中.gil');
const output=path.join(DIR,'698_首页与缩略图修复.gil');
const luaPath=path.join(DIR,'698_内嵌Lua_698.lua');
if(fs.existsSync(output)&&!process.argv.includes('--replace'))throw Error('698已存在，明确指定--replace才能重建');
const g=R.readGil(input),original=W.findScriptLeaf(g).buf;
let lua=original.toString('utf8');
const patches=[];
function replace(oldText,newText,label){if(lua.split(oldText).length!==2)throw Error('补丁锚点不唯一 '+label);lua=lua.replace(oldText,newText);patches.push({label,oldText,newText});}
replace('  if walked or self._idx_trust then return nil end\n  idx = self:_build_name_index(roots)\n  return idx[name]',`  -- 698：有效索引中的缺项也是有效结果；不为每个缺失名字重新扫描。
  -- TTL/结构代数负责刷新，失效句柄则单独重建一次。
  if hit ~= nil and not walked then
    idx = self:_build_name_index(roots)
    return idx[name]
  end
  return nil`,'有效负索引复用');
// 缺项不再永久冻结：保留1秒重试，支持客户端迟到控件。
replace('    elseif old ~= false and self.clock >= old then\n      self._misses[name] = false', '    elseif old == false or self.clock >= old then\n      self._misses[name] = self.clock + ttl','缺失控件可恢复');
replace('  local short = string.match(title, "^案件%s*%d+%s*·%s*([^·]+)")\n             or string.match(title, "·%s*(.+)$") or title',`  -- UTF-8 的中点必须整体匹配，不能放进按字节匹配的字符集合。
  local short = title
  local first = string.find(title, "·", 1, true)
  if first then
    short = string.sub(title, first + #"·")
    local next_sep = string.find(short, "·", 1, true)
    if next_sep then short = string.sub(short, 1, next_sep - 1) end
    short = string.gsub(short, "^%s+", "")
  end`,'UTF8短名');
replace('self:push_room_thumb(push, "select.card." .. i, it, r, "select")','self:push_room_thumb(push, "select.card." .. i, it, r, "root")','缩略图真实父级');
replace('self:push_room_thumb(push, "select.card." .. i, nil, r, "select")','self:push_room_thumb(push, "select.card." .. i, nil, r, "root")','空卡真实父级');
// 每次都输出固定池，缺少的节点明确隐藏，杜绝末页/不同尺寸残留。
replace('  if not rows or not cols or rows < 1 or cols < 1 then return end\n  -- 697：',`  local emit, used = push, {}
  push = function(n)
    used[n.id] = true
    n.raycast = false
    emit(n)
  end
  local function hide_unused()
    for _, suffix in ipairs(Controller.THUMB_POOL or {}) do
      local id = cardId .. suffix
      if not used[id] then
        emit({ id = id, kind = "image", parent = parent, visible = false,
          raycast = false, rect = { x = area.x, y = area.y, w = 1, h = 1 }, pos_runtime = true })
      end
    end
  end
  if not rows or not cols or rows < 1 or cols < 1 then hide_unused(); return end
  -- 697：`,'固定池隐藏尾项');
replace('end\nfunction Controller.object_key_of(vm, cd)', '  hide_unused()\nend\nfunction Controller.object_key_of(vm, cd)','池收尾');
replace('function Controller:_render_impl(adapter, force)\n  do',`function Controller:_render_impl(adapter, force)
  -- 首页/选关先关闭弹窗整棵子树，不依赖后续全界面布局的隐藏顺序。
  if self.screen ~= nil and self.modal == nil and self._popup_guard_screen ~= self.screen then
    if adapter and adapter.hide_screen_popups then adapter:hide_screen_popups() end
    self._popup_guard_screen = self.screen
  elseif self.screen == nil or self.modal ~= nil then
    self._popup_guard_screen = nil
  end
  do`,'弹窗优先收起');
replace('    local all = self:layout_plan()\n    for i = 1, #all do',`    local all = self:layout_plan()
    if adapter.prefetch then
      local names = {}
      for i = 1, #all do names[#names+1] = all[i].id end
      adapter:prefetch(names)
    end
    for i = 1, #all do`,'首帧批量查找');
const gate=`-- 698：子控件可见性独立；保存期望状态，重开弹窗时恢复装饰层。
function Adapter:hide_screen_popups()
  for _, name in ipairs({ "modal", "block640.modal", "block640.confirm" }) do
    self:set_property(name, "visible", false)
  end
end
function Adapter:_popup_visibility(ctrl, visible)
  self._popup_saved = self._popup_saved or {}
  self._popup_gated = self._popup_gated or {}
  if visible then
    if self._popup_gated[ctrl] then
      for child, rec in pairs(self._popup_saved) do
        if rec.root == ctrl then
          if child.SetVisible then child:SetVisible(rec.visible) end
          self._popup_saved[child] = nil
        end
      end
      self._popup_gated[ctrl] = nil
    end
  elseif not self._popup_gated[ctrl] then
    local visited = {}
    local function hide(parent, depth)
      if depth > 20 or visited[parent] then return end
      visited[parent] = true
      local ok, children = pcall(function() return parent:GetChildren() end)
      if ok and type(children) == "table" then
        for _, child in ipairs(children) do
          local v = true
          pcall(function() v = child.visible ~= false end)
          self._popup_saved[child] = { root = ctrl, visible = v }
          if child.SetVisible then child:SetVisible(false) end
          hide(child, depth+1)
        end
      end
    end
    hide(ctrl, 0)
    self._popup_gated[ctrl] = true
  end
end
`;
replace('function Adapter:set_property(id, key, value, nkey)',gate+'function Adapter:set_property(id, key, value, nkey)','弹窗子树门控');
replace('  elseif key == "visible" then\n    -- ★ 686：',`  elseif key == "visible" then
    if id == "modal" or id == "block640.modal" or id == "block640.confirm" then
      self:_popup_visibility(ctrl, value == true)
    end
    local saved = self._popup_saved and self._popup_saved[ctrl]
    if saved then
      saved.visible = value == true
      value = false
    end
    -- ★ 686：`,'维护门控期间子层意图');
replace('构建标记 v635 / 2026-11-05 / 正式版635：选中人物揭示与线索验证','构建标记 v698 / 2026-11-16 / 首页显隐与静态缩略图修复','构建标记');
// 用真实关卡布局确定所有格/墙/门名，而非假设数量。
const prefix=lua.slice(0,lua.indexOf('local FORCE_LEVEL = nil'));
const manifestProbe=`
local UI=__require('ui_controller');local LV=__require('levels.init')
local set={}
for _,it in ipairs(LV.ui_list()) do
 UI.Controller:push_room_thumb(function(n)
  local suffix=n.id:sub(#'select.card.1'+1)
  if not suffix:match('^%.room%.') then set[suffix]=true end
 end,'select.card.1',it,{x=250,y=330,w=279,h=388.8},'root')
end
local out={};for k in pairs(set) do out[#out+1]=k end;table.sort(out)
for _,k in ipairs(out) do print(k) end
`;
fs.writeFileSync(TMP+'/manifest.lua',prefix+manifestProbe);
const suffixes=execFileSync('C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe',[TMP+'/manifest.lua'],{encoding:'utf8',timeout:120000}).trim().split(/\r?\n/).filter(s=>/^\.(cell|wall|door)\./.test(s)).sort((a,b)=>{const rank=s=>s.startsWith('.cell.')?0:s.startsWith('.wall.')?1:2;return rank(a)-rank(b)||a.localeCompare(b,'en',{numeric:true});});
if(suffixes.length<40)throw Error('控件池规模异常');
replace('local ROOM_MAX = 6', 'Controller.THUMB_POOL = {\n'+suffixes.map(s=>'  '+JSON.stringify(s)+',').join('\n')+'\n}\nlocal ROOM_MAX = 6','控件池规格');
// 补丁可逆性：逐项回退后必须还原697完整脚本。
let reverse=lua;for(const p of [...patches].reverse())reverse=reverse.replace(p.newText,p.oldText);
if(reverse!==original.toString('utf8'))throw Error('Lua无法反向还原697');
fs.writeFileSync(luaPath,lua);
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const root=g.recs.find(r=>r.name==='root');
const proto=g.recs.find(r=>r.name==='select.card.1.room.1');
if(!root||!proto||proto.childList)throw Error('纯色图层原型异常');
const rootList=R.findChildListTop(root.field.sub),oldKids=R.asIdList(rootList.payload,true);
const added=[];let max=g.maxId;
function walk(f,fn){fn(f);for(const s of f.sub||[])walk(s,fn)}
function child(f,n){return f.sub?.find(x=>x.field===n&&x.wt===2)}
function tag(f,a,b){return f.sub?.some(x=>x.field===501&&x.num===BigInt(a))&&f.sub?.some(x=>x.field===502&&x.num===BigInt(b))}
function setHidden(f){const blk=f.sub.find(x=>x.field===505&&tag(x,4,86));const p=child(child(blk,503),14);const p17=child(p,17);if(!p17)throw Error('可见性字段缺失');p17.sub=[{field:503,wt:0,num:1n}];p17.payload=R.encodeMsg(p17.sub);p17.len=p17.payload.length;p17.isText=false;}
for(let card=1;card<=4;card++)for(const suffix of suffixes){
 const f=R.cloneField(proto.field),id=++max,name='select.card.'+card+suffix;
 let renamed=0;
 walk(f,x=>{if(x.wt===0&&Number(x.num)===proto.id)x.num=BigInt(id);if(x.isText&&x.payload?.toString('utf8')===proto.name){x.payload=Buffer.from(name);x.len=x.payload.length;renamed++;}});
 if(renamed!==1)throw Error('重命名异常 '+name);
 f.sub.find(x=>x.field===504&&x.wt===0).num=BigInt(root.id);
 for(const st of R.stateBlocks(f.sub,[])){
  R.setPair(R.pairOf(st,504),0,0);R.setPair(R.pairOf(st,505),1,1);
  for(const k of [502,503,506])R.setPair(R.pairOf(st,k),0.5,0.5);
 }
 setHidden(f);
 g.recHolder.push(f);added.push({id,name,card});
}
// 放到卡片之后、点击检测层之前，维持底色→格→墙→门的绘制顺序。
const poolIds=added.map(a=>a.id);
const hit=g.recs.find(r=>r.name==='hit.select.card.1');
const at=hit?oldKids.indexOf(hit.id):-1;
R.setChildList(rootList,at<0?[...oldKids,...poolIds]:[...oldKids.slice(0,at),...poolIds,...oldKids.slice(at)]);
const leaf=W.findScriptLeaf(g).field;leaf.payload=Buffer.from(lua);leaf.len=leaf.payload.length;
const report=W.writeGil(g,output,{label:'698 首页与缩略图修复',expectRecs:g.recs.length+added.length,expectMarker:'v698',assert(d){
 if(!W.findScriptLeaf(d).buf.equals(Buffer.from(lua)))return 'Lua未写入';
 for(const a of added){const rs=d.recs.filter(r=>r.name===a.name);if(rs.length!==1||rs[0].id!==a.id||rs[0].parentId!==root.id)return '池控件缺失或父级错误 '+a.name;}
 return true;
}});
const disk=report.g2;
const changed=disk.recs.filter(r=>before.has(r.id)&&!before.get(r.id).equals(R.encodeMsg([r.field]))).map(r=>({id:r.id,name:r.name}));
if(changed.some(r=>r.id!==root.id))throw Error('白名单外已有控件发生变化 '+JSON.stringify(changed));
const audit={version:698,base:{file:path.basename(input),sha256:crypto.createHash('sha256').update(g.src).digest('hex')},output:{file:path.basename(output),sha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),records:disk.recs.length,bytes:fs.statSync(output).size},patches:patches.map(p=>p.label),luaReversible:true,changedExisting:changed,pool:{perCard:suffixes.length,total:added.length,suffixes,added},notes:['保留697地毯角片与全部七关数据','已有控件仅root子列表变化；内嵌脚本变化','静态池默认隐藏；auto_create仍为false','离线回放不等于游戏内实测']};
fs.writeFileSync(path.join(DIR,'698_构建审计.json'),JSON.stringify(audit,null,2));
console.log(JSON.stringify({output,records:audit.output.records,added:added.length,changedExisting:changed,patches:audit.patches},null,2));
