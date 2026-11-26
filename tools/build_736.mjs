// 736：在735活动画布上追加商城图层，复用其玩家存档及交易。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadTree,findScriptLeaf,writeGil} from './gil/gilwrite.mjs';
import {cloneField,textsOf,stateBlocks,pairOf,setPair,asIdList,setChildList,writeVarint} from './gil/gilread.mjs';
const base=fileURLToPath(new URL('../../构建存档/',import.meta.url));
const out=path.join(base,'736/736_调查商城.gil');
assert(!fs.existsSync(out));
const g=loadTree(path.join(base,'735/735_调查币图标与双券存档.gil'));
const root=g.recs.find(r=>r.id===g.byName.get('econ.shop.coin').parentId);
const order=asIdList(root.childList.payload,true).map(Number);
const entries=[];
const ink='6D0701',paper='ECE2CC',cream='F1E2AE',brick='A54E2D',wood='66341F',gold='DA9347',brown='3B2317',sand='E7D0B2';
let group='all';
function add(kind,key,x,y,w,h,attrs={}){entries.push({kind,key,x,y,w,h,group,...attrs});}
function shape(x,y,w,h,color,material=100001,rot=0){add('image','s'+entries.length,x,y,w,h,{color,material,rot});}
function frame(x,y,w,h,color,border=ink,t=5){shape(x,y,w,h,border);shape(x+t,y+t,w-2*t,h-2*t,color);}
function label(key,x,y,w,h,value,color=brown,size=26){add('text',key,x,y,w,h,{value,color,size});}
function hit(action,x,y,w,h){add('cursor','hit.'+action,x,y,w,h,{action});}
// 1920×1080，按6236×3508原图色块比例换算。
shape(0,0,1920,1080,brown);frame(57,96,1807,938,gold);frame(570,52,780,106,gold);shape(575,102,770,58,gold);
frame(113,173,1039,802,brick);frame(1187,173,622,802,paper);
const slots=[];
for(let row=0;row<3;row++)for(let col=0;col<3;col++){
  const x=145+col*329,y=203+row*251;slots.push([x,y]);frame(x,y,308,229,wood);shape(x+5,y+5,13,219,'4F2C20');
}
frame(1254,124,488,96,cream);for(let i=0;i<13;i++){shape(1272+i*35,139,20,3,'CDA16D');shape(1272+i*35,202,20,3,'CDA16D');}
shape(1239,268,214,187,sand);shape(1244,495,495,367,sand);
for(const x of [1255,1717])for(const y of [506,841])shape(x,y,10,10,'CDAD86');
frame(1237,902,211,87,'AD3C2A');frame(1530,902,211,87,'AD3C2A');
frame(1508,42,313,62,'8A614A');shape(1465,33,81,81,ink,100002);shape(1470,38,71,71,'E8B357',100002);
add('image','currency',1481,49,49,49,{material:100002,color:'F1CB78',currency:true});
frame(29,33,157,88,brick);shape(164,56,57,47,brown,100003,90);label('return',42,42,107,60,"'↶'",cream,42);
label('shopname',645,64,630,84,"'调查商城'",brown,35);
// 纸束与查证手册共用同一图形定义，预览缩放时不改变比例。
function icon(key,cx,cy,k){
 function p(x,y,w,h,c,m=100001,r=0){shape(cx+x*k,cy+y*k,w*k,h*k,c,m,r);}
 if(key==='position'){
 p(-53,-65,98,130,'AA937B',100001,10);p(-49,-70,97,136,'F2D69F');
 for(const [x,y,w] of [[-37,-47,46],[-37,-37,63],[-31,-20,32],[-38,26,43],[-37,37,62],[-37,48,30]])p(x,y,w,3,'D4AC73');
 p(-1,-70,5,136,'9E4A32');p(-50,-4,99,5,'9E4A32',100001,-7);p(0,-14,23,12,'9E4A32',100002,30);p(3,-12,15,6,'F2D69F',100002,30);p(3,-1,24,4,'9E4A32',100001,-30);
 }else{
 p(-53,-70,105,142,'604322');p(-47,53,95,15,'EAD6A7');p(-52,-69,100,124,'8D6937');p(-44,-61,82,107,'D3A65C');p(-41,-58,76,101,'8D6937');p(-38,-58,3,101,'AE844A');p(47,-37,12,13,'EBC16C');p(-20,-34,47,47,'4F381F',100002);p(-15,-29,37,37,'8D6937',100002);p(17,7,9,31,'4F381F',100001,40);
 }}
icon('position',299,313,1.2);icon('clue',628,313,1.2);
for(const [i,key] of ['position','clue'].entries()){group=key;const [x,y]=slots[i];shape(x+5,y+5,298,5,'F2C970');shape(x+5,y+219,298,5,'F2C970');icon(key,1346,362,1.03);}
group='all';label('wallet',1543,45,251,53,'count(coins)',cream,31);label('name',1269,146,459,51,"name or '道具名称'",brown,32);
label('price',1468,280,255,65,"pick and '6 调查币' or ''",brown,29);label('owned',1468,356,255,62,"pick and ('持有 '..count(qty)..' 张') or ''",wood,23);
label('desc',1262,535,461,197,"pick and (pos and '选中一名人物，揭示其正确行列。' or '选中一条线索，核验其真假。') or '选择左侧的道具查看用途。'",brown,25);
label('status',1262,726,461,116,"(pending~='' and pending) or self.econ_status or (pick and '本案免费提示用完后可使用。' or '')",wood,21);
label('cancel',1247,914,191,60,"'取消'",cream,30);label('purchase',1540,914,191,60,"'购买'",cream,30);
group='browse';hit('position',145,203,308,229);hit('clue',474,203,308,229);hit('leave',29,33,157,88);hit('clear',1237,902,211,87);hit('purchase',1530,902,211,87);
group='confirm';shape(0,0,1920,1080,'AA251B14');frame(551,322,818,430,paper);label('question',598,370,724,85,"'购买'..(name or '')..'？'",brown,34);label('amount',608,472,704,61,"'花费 6 调查币　·　购买 1 张'",wood);frame(641,596,276,81,'94674B');frame(1003,596,276,81,'AD3C2A');label('no',651,608,256,54,"'我再想想'",cream);label('yes',1013,608,256,54,"'确认购买'",cream);hit('no',641,596,276,81);hit('yes',1003,596,276,81);
const leaf=findScriptLeaf(g);let lua=leaf.buf.toString('utf8').replaceAll('\r\n','\n');
function patch(a,b){assert.equal(lua.split(a).length,2,a);lua=lua.replace(a,()=>b);}
function field(parent,n){return parent.sub?.find(f=>f.field===n);}
function component(rec,n){return rec.sub.filter(f=>f.field===505).map(f=>field(field(f,503)||{},n)).find(Boolean);}
function num(obj,k,v){let f=field(obj,k);if(!f)obj.sub.push(f={field:k,wt:0});f.num=BigInt(v);}
function walk(list,fn){for(const f of list){fn(f);if(f.sub)walk(f.sub,fn);}}
let next=1073770000;const taken=new Set();walk(g.tree,f=>{if(f.wt===0)taken.add(Number(f.num));});
const nodes=[];
for(const e of entries){
 const name='econ.shop736.'+e.key;assert(!g.byName.has(name));const proto=g.byName.get({image:'art647.home.settle.yellow',text:'econ.shop.title',cursor:'hit.select.card.1'}[e.kind]);assert(proto&&!proto.childList);
 const rec=cloneField(proto.field);while(taken.has(next))next++;const id=next++;const old=writeVarint(proto.id);
 walk(rec.sub,f=>{if(f.wt===0&&Number(f.num)===proto.id)f.num=BigInt(id);else if(!f.sub&&f.wt===2&&f.payload?.equals(old)){f.payload=writeVarint(id);f.len=f.payload.length;}});
 const nm=textsOf(rec.sub,[]).filter(f=>f.payload.toString()===proto.name);assert.equal(nm.length,1);nm[0].payload=Buffer.from(name);nm[0].len=nm[0].payload.length;
 field(rec,504).num=BigInt(root.id);
 const hide=field(component(rec,14),17);hide.sub=[{field:503,wt:0,num:1n}];
 for(const state of stateBlocks(rec.sub,[])){for(const a of [502,503,506])setPair(pairOf(state,a),.5,.5);setPair(pairOf(state,504),(e.x+e.w/2-960)*5/6,(540-e.y-e.h/2)*5/6);setPair(pairOf(state,505),e.w*5/6,e.h*5/6);const rot=field(state,508);if(rot){rot.sub=e.rot?[{field:3,wt:5,f:e.rot}]:[];rot.payload=null;rot.len=e.rot?5:0;}}
 if(e.kind==='image'){const im=component(rec,84);num(im,502,parseInt(e.color.length===6?'FF'+e.color:e.color,16));num(im,503,e.material);num(im,504,1);}
 if(e.kind==='text'){const t=component(rec,75);for(const f of [501,512,513])num(t,f,e.size);num(t,504,parseInt('FF'+e.color,16));}
 proto.holder.push(rec);order.push(id);
 const visible={all:'true',position:"pick=='position'",clue:"pick=='clue'",browse:'not confirm',confirm:'confirm'}[e.group];
 nodes.push(`      push({id='${name}',parent='root',kind='${e.kind}',rect={x=${e.x},y=${e.y},w=${e.w},h=${e.h}},visible=${visible}${e.value?',text='+e.value:''}${e.action?`,event={action='store_${e.action}'}`:''}${e.currency?',shop_currency=true':''}})`);
}
setChildList(root.childList,order);
patch('    elseif self.screen == "shop" or self.screen == "bag" then',`    elseif self.screen == 'shop' then
      local pick=self.econ_pick
      local confirm=self.shop_confirm==true and pick~=nil
      local coins,clues,pending,_,positions=self.opts.wallet()
      pending=pending or ''
      local pos=pick=='position'
      local name=pick and (pos and '位置揭示券' or '线索核验券')
      local qty=pos and positions or clues
      local function count(v) return v==nil and '读取中' or tostring(v) end
${nodes.join('\n')}
    elseif self.screen == 'bag' then`);
patch("  if self.screen=='shop' or self.screen=='bag' then",`  if self.screen=='shop' then
    if event.phase=='down' or event.phase=='up' or event.phase=='drag' then return self.effects end
    if self.shop_confirm then
      if a=='store_no' then self.shop_confirm=false
      elseif a=='store_yes' and self.econ_pick then
        local ok,msg=self.opts.trade('buy',self.econ_pick)
        self.shop_confirm=false; self.econ_status=msg
      end
    elseif a=='store_leave' then self.screen='home';self.econ_pick=nil;self.econ_status=nil
    elseif a=='store_clear' then self.econ_pick=nil;self.econ_status=nil
    elseif a=='store_clue' or a=='store_position' then self.econ_pick=a=='store_clue' and 'clue' or 'position';self.econ_status=nil
    elseif a=='store_purchase' then
      local coins,_,pending=self.opts.wallet()
      if not self.econ_pick then self.econ_status='请先选择道具'
      elseif pending and pending~='' then self.econ_status=pending
      elseif not coins or coins<6 then self.econ_status='调查币不足'
      else self.shop_confirm=true end
    end
    self.dirty=true;return self.effects
  end
  if self.screen=='bag' then`);
patch('  if key == "settle_shift" then',`  if key=='shop_currency' and id=='econ.shop736.currency' then
    local src=E('ImageSource.Currency')
    if src==nil then return false end
    local ok=pcall(function() ctrl:SetImage(src,1115684865) end)
    return ok
  end
  if key == "settle_shift" then`);
lua=lua.replaceAll('构建标记 v735 / 调查币图标与双券存档','构建标记 v736 / 调查商城');leaf.field.payload=Buffer.from(lua);
fs.mkdirSync(path.dirname(out),{recursive:true});
writeGil(g,out,{label:'736',expectMarker:'v736',expectRecs:g.recs.length+entries.length,expectDiffs:3,assert:b=>entries.every(e=>b.byName.get('econ.shop736.'+e.key)?.parentId===root.id)&&findScriptLeaf(b).buf.equals(leaf.field.payload)});
