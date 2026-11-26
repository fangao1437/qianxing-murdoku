// 从已发布的 733 原包派生，避免用旧主仓 bundle 覆盖七案内容。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
const workspace = fileURLToPath(new URL('../../', import.meta.url));
const source = path.join(workspace,'构建存档/733/733_商城购买与调查币显示修复.gil');
const out = process.argv[2] || path.join(workspace,'构建存档/734/734_双道具商城与背包.gil');
if (fs.existsSync(out)) throw Error('输出已存在，请指定新路径');
const game = loadTree(source);
if (createHash('sha256').update(game.src).digest('hex') !== '37d3746a7bd25dd02d11fb1da0035bba5101aacc115ba40df8650ff80a98f786') throw Error('基底与 733 发布包不符');
const leaf = findScriptLeaf(game);
let lua = leaf.buf.toString('utf8').replace(/\r\n/g,'\n');
function change(a,b){if(lua.split(a).length!==2) throw Error('733 脚本定位失败 '+a.slice(0,80));lua=lua.replace(a,()=>b);}
function section(a,b,text){const i=lua.indexOf(a),j=lua.indexOf(b,i+1);if(i<0||j<i) throw Error(a);change(lua.slice(i,j),text);}
lua=lua.replaceAll('构建标记 v733 / 独立商城与调查币模板','构建标记 v734 / 双道具商城与背包');
change('local ARCHIVE_VERSION = "M730"','local ARCHIVE_VERSION = "M734"');
change('earned*REWARD-e.bought*PRICE,e.bought-e.used','earned*REWARD-(e.bought+e.pos_bought)*PRICE,e.bought-e.used,e.pos_bought-e.pos_used');
change("mask=0,bought=0,used=0,last='-'","mask=0,bought=0,used=0,pos_bought=0,pos_used=0,last='-',pos_last='-'");
change('parts[1]~=ARCHIVE_VERSION and parts[1]~="M725"','parts[1]~=ARCHIVE_VERSION and parts[1]~="M730" and parts[1]~="M725"');
section('  if parts[1]==ARCHIVE_VERSION then','    first=5',`  if parts[1]==ARCHIVE_VERSION or parts[1]=='M730' then
    local mask,bought,used,last,pb,pu,pl
    if parts[1]=='M730' then
      mask,bought,used,last=parts[4]:match('^E(%d+),(%d+),(%d+),([%w_:%-]+)$')
      pb,pu,pl='0','0','-'
    else
      mask,bought,used,last,pb,pu,pl=tostring(parts[4]):match('^E(%d+),(%d+),(%d+),([%w_:%-]+),(%d+),(%d+),([%w_:%-]+)$')
    end
    econ={mask=tonumber(mask),bought=tonumber(bought),used=tonumber(used),last=last,pos_bought=tonumber(pb),pos_used=tonumber(pu),pos_last=pl}
    if not mask or econ.mask>127 or econ.bought+econ.pos_bought>11 or econ.used>econ.bought or econ.pos_used>econ.pos_bought or funds(econ)<0 or
      (econ.used==0 and last~='-') or (econ.used>0 and not last:match('^case_00[1-7]:[gn]:%d+:[01]$')) or
      (econ.pos_used==0 and pl~='-') or (econ.pos_used>0 and not pl:match('^case_00[1-7]:[%w_]+:%d+:%d+$')) then return nil,'经济记录无效' end
`);
change("parts[4]:match('^E", "tostring(parts[4]):match('^E");
change("string.format('E%d,%d,%d,%s',e.mask,e.bought,e.used,e.last)","string.format('E%d,%d,%d,%s,%d,%d,%s',e.mask,e.bought,e.used,e.last,e.pos_bought,e.pos_used,e.pos_last)");
change('local archive=slot and archive_decode(slot) or {records={}}',`local archive
  if slot then archive=archive_decode(slot) else archive={records={}} end
  if not archive then return nil,nil,'存档读取失败' end`);
change("local coins,tickets=funds(e)\n  return coins,tickets,a._save_pending and '核对存档中' or '',e.last",`local coins,tickets,positions=funds(e)
  return coins,tickets,a._save_pending and '核对存档中' or '',e.last,positions,e.pos_last`);
change("if c.screen~='shop' then return false,'请先确认商品' end",`if c.screen~='shop' or c.econ_pick~=target or (target~='position' and target~='clue') then return false,'请先确认商品' end`);
change('    e.bought=e.bought+1',`    if target=='position' then e.pos_bought=e.pos_bought+1 else e.bought=e.bought+1 end
  elseif op=='position' then
    local core=current.core
    if c.screen or c.modal or core.status~=Core.STATUS_PLAYING or not case_bit(current.level.id) then return false,'当前不能用券' end
    if not core.hint635_used or core.hint635_used.position<1 then return false,'请先使用免费揭示' end
    if e.pos_bought<=e.pos_used then return false,'位置揭示券不足' end
    local id=core.selected
    local p=id and core.solution[id]
    if not p or core:is_blocked(p.r,p.c) then return false,'请先选中可揭示的人物' end
    local cur=core.pos[id]
    if cur and core.placed[id] and cur.r==p.r and cur.c==p.c then return false,'该人物已在正确位置' end
    e.pos_last=table.concat({current.level.id,id,p.r,p.c},':')
    e.pos_used=e.pos_used+1`);
change('controller=c,op=op,last=e.last','controller=c,op=op,target=target,last=op==\'position\' and e.pos_last or e.last');
change("then c.econ_status='核验券已入包'",`then c.econ_status=(tx.target=='position' and '位置揭示券' or '线索核验券')..'已入包'
        elseif tx.op=='position' and not c.screen and not c.modal then
          local _,who,r,col=tx.last:match('^([^:]+):([^:]+):(%d+):(%d+)$')
          c.hint635={kind='message',text=(current.core.names[who] or who)..'在第'..r..'行第'..col..'列'}`);
change('if used.position>=1 then message("本关揭示位置次数已用完",true);return end',`if used.position>=1 then
      message('正在核对交易',false)
      local ok,msg=self.opts.trade('position')
      if not ok then message(msg,true) end
      return
    end`);
change('"揭示选中人物的所在位置（"..tostring(1-used.position).."/1）"','used.position>=1 and "使用位置揭示券 ×1" or "揭示选中人物的所在位置（1/1）"');
// Three pre-authored sibling buttons. Keep stable actions for the lifetime of a handle.
change('  if event.phase == "key" then\n    self:on_key(event)',`  if self.screen=='shop' or self.screen=='bag' then
    if a~='econ_position' and a~='econ_clue' and a~='econ_back' then return self.effects end
    if event.phase=='down' or event.phase=='up' or event.phase=='drag' then return self.effects end
    local pick=self.econ_pick
    if a=='econ_back' then
      if pick then self.econ_pick=nil else self.screen='home' end
      self.econ_status=nil
    elseif not pick then
      self.econ_pick=a=='econ_position' and 'position' or 'clue'
      self.econ_status=nil
    elseif self.screen=='shop' and a=='econ_clue' then
      local ok,msg=self.opts.trade('buy',pick)
      self.econ_status=msg
      if ok then self.econ_pick=nil end
    end
    self.dirty=true
    return self.effects
  end
  if event.phase == "key" then
    self:on_key(event)`);
section('    if self.screen == "home" then self.screen=a; self.econ_status=nil;', '  elseif a == "clue_up"',`    if self.screen == 'home' then self.screen=a; self.econ_pick=nil; self.econ_status=nil; self.dirty=true end
`);
section('      local is_shop = self.screen == "shop"','    elseif self.screen == "select" then',`      local shop=self.screen=='shop'
      local pick=self.econ_pick
      local coins,clues,pending,last,positions,pos_last=self.opts.wallet()
      local prefix='econ.'..self.screen..'.'
      local function rect(x,y,w,h) return {x=x,y=y,w=w,h=h} end
      local function label(key,text,box,style)
        push({id=prefix..key,parent='root',kind='text',visible=true,text=text,rect=box,style=style})
      end
      local function button(id,text,action,box,active)
        push({id=id,parent='root',kind='button',text=text,event={action=action},visible=active,enabled=active,rect=box,style='stamp'})
      end
      local locked=pending and pending~=''
      local pos=pick=='position'
      local name=pos and '位置揭示券' or '线索核验券'
      local qty=pos and positions or clues
      local function count(n) return n==nil and '读取中' or tostring(n) end
      push({id=prefix..'page',parent='root',kind='container',visible=true,rect=FULL})
      push({id=prefix..'panel',parent='root',kind='button',visible=true,rect=pick and rect(410,200,1100,660) or rect(260,135,1400,800),style='modal'})
      label('title',pick and (shop and '确认购买' or '道具详情') or (shop and '调查商城' or '我的背包'),rect(570,230,780,80),'modal.title')
      label('wallet','调查币  '..count(coins),rect(740,335,440,56),'modal.body')
      local status=self.econ_status or ''
      if pick then
        label('item',name..'   ×1',rect(570,415,780,64),'modal.body')
        label('price',pos and '揭示所选人物的正确行列' or '验证所选线索的真假',rect(530,495,860,54),'muted')
        status=status~='' and status or (shop and ('花费 6 调查币　·　已持有 '..count(qty)..' 张') or '在案件内选中目标，免费提示用完后即可用券')
      else
        label('item',shop and '选择要购买的调查道具' or '选择道具查看用法',rect(560,410,800,65),'modal.body')
        status=status~='' and status or (shop and '每张 6 调查币' or ((positions==0 and clues==0) and '背包为空，可到商城购买' or '在案件的提示菜单中使用'))
        if not shop and pos_last and pos_last~='-' then
          local case,id,r,c=pos_last:match('^case_00(%d):([^:]+):(%d+):(%d+)$')
          label('price','上次揭示：案件 '..case..' · '..id..' 在第'..r..'行第'..c..'列',rect(520,620,880,48),'muted')
        elseif not shop and last and last~='-' then
          label('price','上次线索核验：'..(last:sub(-1)=='1' and '真' or '假'),rect(520,620,880,48),'muted')
        end
      end
      label('status',locked and pending or status,rect(505,pick and 578 or 679,910,58),'muted')
      button('econ.shop.buy','位置揭示券'..(shop and '' or ' ×'..count(positions)),'econ_position',rect(505,510,420,85),not pick)
      button('econ.bag.back',pick and '确认购买' or ('线索核验券'..(shop and '' or ' ×'..count(clues))),'econ_clue',pick and rect(980,705,320,77) or rect(995,510,420,85),not pick or (shop and not locked))
      button('econ.shop.back',pick and (shop and '取消' or '返回背包') or '返回首页','econ_back',pick and rect(620,705,320,77) or rect(780,785,360,77),true)
`);
change('then node.raycast = node.event ~= nil end','then node.raycast = node.visible~=false and node.event ~= nil; node.pos_runtime=true end');
leaf.field.payload=Buffer.from(lua);
fs.mkdirSync(path.dirname(out),{recursive:true});
writeGil(game,out,{label:'734',expectMarker:'v734',expectDiffs:1,assert:g=>findScriptLeaf(g).buf.equals(leaf.field.payload)});
