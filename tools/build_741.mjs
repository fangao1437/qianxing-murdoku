import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
const lib=pathToFileURL(process.cwd()+'/qianxing-murdoku/tools/gil/');
const {loadTree,findScriptLeaf,writeGil}=await import(new URL('gilwrite.mjs',lib));
const {cloneField,asIdList,setChildList,pairOf,setPair,textsOf,writeVarint}=await import(new URL('gilread.mjs',lib));
const g=loadTree('构建存档/740/740_调查商城定价与控件优化_v2.gil');
const out='构建存档/741/741_调查背包.gil'; assert(!fs.existsSync(out));
const leaf=findScriptLeaf(g);let lua=leaf.buf.toString();const original=lua;
const shop='econ.shop736.',prefix='econ.bag741.';
const root=g.recs.find(r=>r.id===g.byName.get(shop+'s0').parentId);
const order=asIdList(root.childList.payload,true).map(Number), oldCount=g.recs.length;
const F=(p,n)=>p?.sub?.find(f=>f.field===n);
const component=(rec,n)=>rec.sub.filter(f=>f.field===505).map(f=>F(F(f,503),n)).find(Boolean);
const taken=new Set();function walk(fields,cb){for(const f of fields){cb(f);if(f.sub)walk(f.sub,cb)}}walk(g.tree,f=>{if(f.wt===0)taken.add(Number(f.num))});let next=1073771000;
const nodes=[],names=[];
function add(key,box,{proto='s9',color,asset,angle,kind='image',size,text,vis='true',action}={}){
 const src=g.byName.get(shop+proto);assert(src&&!src.childList,proto);const r=cloneField(src.field);const name=prefix+key;
 assert(!g.byName.has(name)&&!names.includes(name));names.push(name);
 while(taken.has(next))next++;const id=next++;const old=writeVarint(src.id);
 walk(r.sub,f=>{if(f.wt===0&&Number(f.num)===src.id)f.num=BigInt(id);else if(!f.sub&&f.wt===2&&f.payload?.equals(old)){f.payload=writeVarint(id);f.len=f.payload.length}});
 const nf=textsOf(r.sub,[]).filter(f=>f.payload.toString()===src.name);assert.equal(nf.length,1);nf[0].payload=Buffer.from(name);nf[0].len=nf[0].payload.length;
 const [x,y,w,h]=box.map(n=>Math.round(n*10000)/10000); const states=F(component(r,13),12).sub.filter(f=>f.field===501).map(f=>F(f,502));assert.equal(states.length,4);
 for(const s of states){assert(setPair(pairOf(s,504),(x+w/2-960)*5/6,(540-y-h/2)*5/6));assert(setPair(pairOf(s,505),w*5/6,h*5/6));if(angle!==undefined){const rot=F(s,508);rot.sub=angle?[{field:3,wt:5,f:angle}]:[];rot.payload=null;rot.len=angle?5:0}}
 function num(obj,n,v){const f=F(obj,n);if(f)f.num=BigInt(v);else obj.sub.push({field:n,wt:0,num:BigInt(v)})}
 if(kind==='image'){const im=component(r,84);if(color)num(im,502,'0xff'+color);if(asset)num(im,503,asset)}
 if(kind==='text'){const t=component(r,75);for(const n of [501,512,513])num(t,n,size);num(t,504,'0xff'+color)}
 const hide=F(component(r,14),17);hide.sub=[{field:503,wt:0,num:1n}];
 src.holder.push(r);order.push(id);nodes.push(`      push({id='${name}',parent='root',kind='${kind}',rect={x=${x},y=${y},w=${w},h=${h}},visible=${vis}${text?',text='+text:''}${action?`,event={action='${action}'}`:''}})`);
}
function rect(k,x,y,w,h,c,a=0,vis='true'){add(k,[x,y,w,h],{color:c,asset:100001,angle:a,vis})}
function disc(k,x,y,d,c){add(k,[x,y,d,d],{color:c,asset:100002,angle:0})}
function label(k,b,text,size,color,vis='true'){add(k,b,{proto:'name',kind:'text',text,size,color,vis})}
function hit(k,box,action,vis='true'){add('hit.'+k,box,{proto:'hit.leave',kind:'cursor',action,vis})}
// 设计画布 1920×1080。桌面超铺，内胆与纸张按原图的测量坐标等比换算。
rect('desk',-1920,-1080,5760,3240,'3D2518');rect('desk.left',-155,183,970,643,'251B01',8);rect('desk.left.face',-149,189,958,631,'3B3D2B',8);rect('desk.right',1360,463,840,870,'3B3D2B',-14);
rect('lid.edge',130,-170,1655,468,'682703');rect('lid.leather',138,-169,1639,455,'B36B47');rect('lid.lining',157,-163,1601,423,'D6A86A');
function rounded(k,x,y,w,h,r,c){rect(k+'.middle',x+r,y,w-2*r,h,c);rect(k+'.cross',x,y+r,w,h-2*r,c);for(const [i,dx,dy] of [[0,0,0],[1,w-2*r,0],[2,0,h-2*r],[3,w-2*r,h-2*r]])disc(k+'.corner'+i,x+dx,y+dy,r*2,c)}
rounded('case',138,160,1644,885,27,'682703');rounded('leather',146,168,1628,868,22,'B36B47');
rect('inner.seam',153,175,1611,815,'682703');rect('left.wall',160,182,983,801,'B36B47');rect('right.wall',1170,182,586,801,'AD6837');rect('center.edge',1143,182,27,801,'682703');rect('center.lip',1148,182,15,801,'CB8D5C');
for(const [row,y] of [194,599].entries())for(const [col,x] of [169,498,827].entries()){
 const k=`slot.${row}.${col}`;rect(k+'.shadow',x,y,308,374,'AD6837');rect(k+'.floor',x+9,y+14,299,360,'D6A86A');
 if(!row&&col>0)rect(k+'.selected',x+9,y+14,299,360,'E8BD7F',0,col===1?'pick==\'clue\'':'pick==\'position\'');
}
rect('right.floor',1182,197,562,774,'D6A86A');
for(const [i,x] of [442,1406].entries()){rect('clasp.'+i+'.edge',x,989,73,65,'682703');rect('clasp.'+i+'.strap',x+5,991,63,57,'DBAE74');disc('clasp.'+i+'.stud',x+28,1010,17,'68422B')}
rect('paper.under',1199,229,496,732,'D8BD95',-2);rect('paper.top',1190,224,490,739,'F6E7D2');rect('paper.label',1239,270,382,94,'E8D7BF');rect('paper.body',1241,498,385,426,'E8D7BF');
for(const [i,x,y] of [[0,1249,506],[1,1606,506],[2,1249,903],[3,1606,903]])rect('paper.pin'+i,x,y,12,12,'D1BA9D');
const itemLines=original.split('\n').filter(l=>l.includes(`push({id='${shop}`));
for(const line of itemLines){const key=line.match(/shop736\.([^']+)'/)[1];const n=Number(key.match(/^s(\d+)/)?.[1]);const flag=key.startsWith('flag.')||key==='s82';if(!flag&&!(n>=85&&n<=105))continue;
 const coords=line.match(/rect=\{x=([^,]+),y=([^,]+),w=([^,]+),h=([^}]+)\}/).slice(1).map(Number);const [x,y,w,h]=coords;
 if(flag){add('return.'+key,coords,{proto:key});continue}
 const clue=n>=98,m=1.57;const cx=clue?656:985;add('item.'+key,[cx+(x-(clue?628:299))*m,376+(y-313)*m,w*m,h*m],{proto:key,vis:clue?'hasClue':'hasPos'});
}
const ink='493321',muted='785A41';
label('title',[1239,268,382,100],"pick and (pick=='clue' and '线索核验券' or '位置揭示券') or '调查背包'",32,ink);
label('meta',[1214,376,442,93],"pick and ('持有 '..tostring(pick=='clue' and clues or positions)..' 张') or ('调查币　'..(coins==nil and '读取中' or tostring(coins)))",25,muted);
label('desc',[1261,539,345,163],"pick=='clue' and '选中一条线索，核验其真假。' or pick=='position' and '选中一名人物，揭示其正确行列。' or (pending~='' and pending) or (clues==nil or positions==nil) and '正在读取背包…' or (hasClue or hasPos) and '选择左侧的道具查看用途。' or '背包为空，可到调查商城购买道具。'",25,ink);
label('usage',[1261,701,345,117],"pick and '本案免费提示用完后，可在提示菜单中用券。' or ''",22,muted,'pick~=nil');
label('history',[1261,820,345,77],'history',18,muted,"history~=''");
for(const [k,x,qty,vis] of [['clue',498,'clues','hasClue'],['position',827,'positions','hasPos']]){label('qty.'+k,[x+193,500,102,62],"'×'..tostring("+qty+" or 0)",24,ink,vis);hit(k,[x,194,308,374],'econ_'+k,vis)}hit('return',[29,30,198,100],'econ_back');
setChildList(root.childList,order);
function section(a,b,to){const i=lua.indexOf(a),j=lua.indexOf(b,i+1);assert(i>=0&&j>i&&lua.indexOf(a,i+1)===-1,a);lua=lua.slice(0,i)+to+lua.slice(j)}
section("  if self.screen=='bag' then",'  if event.phase == "key" then',`  if self.screen=='bag' then
    if event.phase=='down' or event.phase=='up' or event.phase=='drag' then return self.effects end
    if a=='econ_back' then
      self.screen='home'; self.econ_pick=nil; self.econ_status=nil
    elseif a=='econ_clue' or a=='econ_position' then
      local _,clues,_,_,positions=self.opts.wallet()
      local target=a=='econ_clue' and 'clue' or 'position'
      if (target=='clue' and (clues or 0)>0) or (target=='position' and (positions or 0)>0) then self.econ_pick=target end
    else return self.effects end
    self.dirty=true; return self.effects
  end
`);
section("    elseif self.screen == 'bag' then",'    elseif self.screen == "select" then',`    elseif self.screen == 'bag' then
      local coins,clues,pending,last,positions,pos_last=self.opts.wallet()
      pending=pending or ''
      local hasClue,hasPos=(clues or 0)>0,(positions or 0)>0
      local pick=(hasClue and self.econ_pick=='clue' and 'clue') or (hasPos and self.econ_pick=='position' and 'position') or nil
      local history=''
      if pick~='clue' and pos_last and pos_last~='-' then
        local c,id,r,col=pos_last:match('^case_00(%d):([^:]+):(%d+):(%d+)$')
        if c then history='上次揭示：案件 '..c..' · '..id..' 第'..r..'行第'..col..'列' end
      end
      if history=='' and pick~='position' and last and last~='-' then history='上次线索核验：'..(last:sub(-1)=='1' and '真' or '假') end
${nodes.join('\n')}
`);
lua=lua.replace("set_visible(fill,page~='shop')","set_visible(fill,page~='shop' and page~='bag')").replaceAll('构建标记 v740 / 圆底还原与全局缓存优化 v2','构建标记 v741 / 调查背包');
// 旧预制面板退出规划后显式设置存档隐藏初值，防止冷启动残留。
for(const r of g.recs.filter(r=>/^econ\.bag\.|^econ\.shop\.(buy|back)$/.test(r.name))){const flag=F(component(r.field,14),17);assert(flag);flag.sub=[{field:503,wt:0,num:1n}];}
leaf.field.payload=Buffer.from(lua);const stage=fileURLToPath(new URL('stage.gil',import.meta.url));
writeGil(g,stage,{label:'741 调查背包',expectMarker:'v741',expectRecs:oldCount+nodes.length,assert:b=>{
 const bytes=findScriptLeaf(b).buf;assert(bytes.equals(leaf.field.payload));const saved=b.recs.find(r=>r.id===root.id);assert.deepEqual(asIdList(saved.childList.payload,true).map(Number),order);
 for(const name of names){const r=b.byName.get(name);assert.equal(r.parentId,root.id);assert.equal(F(F(component(r.field,14),17),503).num,1n)}
 for(const file of ['qianxing-murdoku/tests/shop_cold_render.lua',fileURLToPath(new URL('bag-test.lua',import.meta.url))]){const p=spawnSync('lua',[file],{input:bytes,encoding:'utf8'});assert.equal(p.status,0,p.stderr||p.error?.message);console.log(p.stdout.trim())}return true;
}});fs.mkdirSync(path.dirname(out),{recursive:true});fs.copyFileSync(stage,out,fs.constants.COPYFILE_EXCL);console.log('已导出',out,'背包图层和热区',nodes.length);
