// 651 -> 652：连续静态图层分类，精确路径查找，父级显隐。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg,cloneField,asIdList,setChildList,ensureChildListTop,textsOf,stateBlocks,pairOf,pairValue} from '../tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf} from '../tools/gil/gilwrite.mjs';
const HERE=path.dirname(fileURLToPath(import.meta.url));
const INPUT=path.join(HERE,'651_撕边修复.gil');
const OUTPUT=path.join(HERE,'652_分类整理优化.gil');
const LUA=path.join(HERE,'652_分类整理优化.lua');
const AUDIT=path.join(HERE,'652_分类整理审计.json');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const g=readGil(INPUT), original=readGil(INPUT);
assert.equal(hash(g.src),'c903960185d1c4b288f7a9d12a456297235120b8c6a33c9b264187db297a3440');
const old=new Map(original.recs.map(r=>[r.id,r]));
const byId=new Map(g.recs.map(r=>[r.id,r]));
const R=n=>{let r=g.recs.find(r=>r.name===n);assert(r,'missing '+n);return r;};
const kids=r=>r.childList?(asIdList(r.childList.payload,true)||[]):[];
const setKids=(r,ids)=>{setChildList(ensureChildListTop(r),ids);r.childList=r.field.sub.find(f=>f===ensureChildListTop(r));};
const groups=[],moved=new Set(),parents=new Set();
let max=g.maxId;
function remap(ff,from,to,depth=0){for(const f of ff){if(!(depth===0&&f.field===504)&&f.wt===0&&Number(f.num)===from)f.num=BigInt(to);if(f.sub)remap(f.sub,from,to,depth+1);}}
function addGroup(parent,name,ids){
  const proto=R('art641.game'); // 原生空容器：中心锚点/1600x900/无图片与射线组件
  const field=cloneField(proto.field),id=++max;
  remap(field.sub,proto.id,id);
  const nf=textsOf(field.sub,[]).find(f=>f.payload.toString('utf8')===proto.name);assert(nf);nf.payload=Buffer.from(name);nf.len=nf.payload.length;
  let pf=field.sub.find(f=>f.field===504&&f.wt===0);pf.num=BigInt(parent.id);
  // 新分类容器必须初始可见；原型 art641.game 自带初始隐藏标记。
  for(const b of field.sub.filter(f=>f.field===505)){
    const p503=b.sub?.find(f=>f.field===503),p14=p503?.sub?.find(f=>f.field===14),p17=p14?.sub?.find(f=>f.field===17);
    if(p17){p17.sub=[];p17.payload=Buffer.alloc(0);p17.len=0;p17.isText=false;}
  }
  const rec={id,name,parentId:parent.id,field};setKids(rec,ids);
  for(const st of stateBlocks(field.sub,[])){
    assert.equal(pairValue(pairOf(st,504),0),0);assert.equal(pairValue(pairOf(st,504),1),0);
    assert.equal(pairValue(pairOf(st,505),0),1600);assert.equal(pairValue(pairOf(st,505),1),900);
  }
  const siblings=kids(parent);const at=siblings.indexOf(ids[0]);assert(at>=0);assert.deepEqual(siblings.slice(at,at+ids.length),ids,'分组必须连续，禁止重排');
  setKids(parent,[...siblings.slice(0,at),id,...siblings.slice(at+ids.length)]);parents.add(parent.id);
  for(const cid of ids){const c=byId.get(cid);assert.equal(c.parentId,parent.id);c.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(id);c.parentId=id;moved.add(cid);}
  g.recHolder.push(field);g.recs.push(rec);byId.set(id,rec);groups.push({id,name,parent:parent.name,count:ids.length});
}
const board=R('art642.select.board');
let run=[],last=null;
for(const id of [...kids(board)]){const c=byId.get(id),key=c.name.match(/^art651\.select\.tear\.(tr|bl)\.(paper|white|joint)\./)?.slice(1).join('.');assert(key);if(last!==null&&key!==last){addGroup(board,'grp652.select.tear.'+last,run);run=[];}last=key;run.push(id);}
if(run.length)addGroup(board,'grp652.select.tear.'+last,run);
// 保留原有首尾顺序；不重挂交互、素材row、教程页或运行时动态控件。
const root=R('root');
const runtime=[];const paths=new Map();
function walk(r,p){const pp=[...p,r.name];runtime.push(r);paths.set(r.id,pp);for(const id of kids(r))walk(byId.get(id),pp);}
walk(root,[]);
let script=findScriptLeaf(original).buf.toString('utf8');
function replaceOnce(a,b){assert.equal(script.split(a).length,2,'替换必须唯一：'+a.slice(0,100));script=script.replace(a,b);}
const countNames=new Map();for(const r of runtime)countNames.set(r.name,(countNames.get(r.name)||0)+1);
const routes=runtime.filter(r=>r.name&&countNames.get(r.name)===1&&(r.parentId===root.id||script.includes('"'+r.name+'"')||script.includes("'"+r.name+"'")||/^td\.(home|l1|l2)\.page\.\d+$/.test(r.name)||/^row\./.test(r.name)));
const quote=s=>JSON.stringify(s);
// 只记录名字路径，不缓存跨帧引擎句柄。动态新建控件仍走原索引兜底。
const routeLua='local STATIC_PATH_652 = {\n'+routes.map(r=>'  ['+quote(r.name)+'] = {'+paths.get(r.id).map(quote).join(',')+'},').join('\n')+'\n}\n'+`local function path_lookup_652(roots, name)
  local route = STATIC_PATH_652[name]
  if route == nil then return nil end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(function() return cur.name end)
    if ok and rn == route[1] then
      for k = 2, #route do
        local parent = cur
        local good, child = pcall(function() return parent:GetChild(route[k]) end)
        if not good or child == nil then cur = nil; break end
        cur = child
      end
      if cur ~= nil then
        local good, actual = pcall(function() return cur.name end)
        if good and actual == name then return cur end
      end
    end
  end
  return nil
end
`;
replaceOnce('function Adapter:_build_name_index(roots)',routeLua+'\nfunction Adapter:_build_name_index(roots)');
replaceOnce('      local hit = self:_index_lookup(name, roots)','      local hit = path_lookup_652(roots, name)\n      if hit == nil then hit = self:_index_lookup(name, roots) end');
replaceOnce('  self:_build_name_index(roots)\n  self._idx_trust = true','  self._idx_trust = true');
replaceOnce('    util:_bind(name .. ".hit", function() end, hit)\n    help_visible(panel, want)\n    help_visible(hit, want)',`    -- 子级保持自身显示，父级负责整树门控；新句柄第一次绑定时初始化。
    if hit ~= nil and not util.bound[hit] then help_visible(hit, true) end
    util:_bind(name .. ".hit", function() end, hit)
    help_visible(panel, want)`);
replaceOnce('      touched = self:_set_visible_deep(box, show)',`      -- 保留旧版首次点亮后代的语义，以后只控制父容器。
      self._baked_prepared652 = self._baked_prepared652 or setmetatable({}, { __mode = "k" })
      if show and not self._baked_prepared652[box] then
        touched = self:_set_visible_deep(box, true)
        self._baked_prepared652[box] = true
      end`);
// 去掉剥注释留下的空白行；仅整行空白，Lua长字符串需要排除。
// 不改变源脚本的行结构，以便审计定位。
fs.writeFileSync(LUA,script);
const leaf=findScriptLeaf(g);leaf.field.payload=Buffer.from(script);leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
function visualFields(r){return encodeMsg(r.field.sub.filter(f=>!(f.field===504&&f.wt===0)&&f!==r.childList));}
function flattened(gx){const map=new Map(gx.recs.map(r=>[r.id,r]));const out=[];function visit(r){if(!groups.some(x=>x.id===r.id))out.push(r.id);for(const id of kids(r))visit(map.get(id));}visit(map.get(root.id));return out;}
const report=writeGil(g,OUTPUT,{label:'652 分类树与父级门控',expectRecs:original.recs.length+groups.length,expectMarker:'v635',quiet:true,assert:g2=>{
  assert.equal(g2.recs.length,expected.size);let unchanged=0;
  for(const r of g2.recs){assert(expected.get(r.id)?.equals(encodeMsg([r.field])),'磁盘记录不符 '+r.name);const prev=old.get(r.id);if(prev){assert(visualFields(prev).equals(visualFields(r)),'美术/交互字段变化 '+r.name);if(!moved.has(r.id)&&!parents.has(r.id)){assert(encodeMsg([prev.field]).equals(encodeMsg([r.field])));unchanged++;}}}
  const map=new Map(g2.recs.map(r=>[r.id,r]));for(const r of g2.recs)for(const id of kids(r)){assert(map.has(id),'断链 '+id);assert.equal(map.get(id).parentId,r.id,'双向父子不符 '+r.name);}
  assert.deepEqual(flattened(g2),flattened(original),'绘制深度优先序改变');
  assert(findScriptLeaf(g2).buf.equals(Buffer.from(script)),'脚本不一致');
  assert(g2.trailer.equals(original.trailer));
  // 顶层非控件/非脚本字段逐字节不变。
  const oldLeaf=findScriptLeaf(original).field,newLeaf=findScriptLeaf(g2).field;
  function nonUI(ff,scriptField){return ff.map(f=>{if(f.field===9)return null;function has(q){return q===scriptField||(q.sub||[]).some(has)}if(has(f))return null;return encodeMsg([f]).toString('hex');});}
  assert.deepEqual(nonUI(original.tree,oldLeaf),nonUI(g2.tree,newLeaf));
  return true;
}});
const data={base:path.basename(INPUT),inputSha256:hash(original.src),output:path.basename(OUTPUT),outputSha256:hash(report.g2.src),inputBytes:original.src.length,outputBytes:report.bytes,scriptBytesBefore:findScriptLeaf(original).len,scriptBytesAfter:Buffer.byteLength(script),recordsBefore:original.recs.length,recordsAfter:report.g2.recs.length,addedGroups:groups,movedControls:moved.size,changedParents:parents.size,retainedByteIdentical:original.recs.length-moved.size-parents.size,exactRoutes:routes.length,checks:{diskReread:true,roundtrip:true,allOriginalVisualAndInteractionFieldsUnchanged:true,flattenedOriginalDrawOrderUnchanged:true,noDanglingIds:true,bidirectionalTree:true,scriptEqualsDeliveredLua:true,trailerUnchanged:true,nonUiTopFieldsUnchanged:true},limitations:['离线验证不能代替实机视觉与点击验收','父级门控不减少引擎内部渲染成本的幅度，须实机量测','烘焙动态容器仍保留第一次后代显示初始化']};
fs.writeFileSync(AUDIT,JSON.stringify(data,null,2));console.log(JSON.stringify(data,null,2));
