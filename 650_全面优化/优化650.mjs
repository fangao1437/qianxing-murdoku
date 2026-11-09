import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg,asIdList,setChildList} from '../tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf,markerOf} from '../tools/gil/gilwrite.mjs';

// 输入锁定650；只在本文件所在目录生成优化产物，不覆盖原存档、lua源文件或dist。
const HERE=path.dirname(fileURLToPath(import.meta.url));
const INPUT=path.resolve(HERE,'../存档/近30版/650.gil');
const OUTPUT=path.join(HERE,'650_优化版.gil');
const LUA=path.join(HERE,'650_client_优化.lua');
const SHA='22e9eb9073e54b73fd117f5719e7f1953872e1bfb9edf162bff95487aaeba978';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const g=readGil(INPUT);assert.equal(hash(g.src),SHA,'输入不是本次审计的650');
const leaf=findScriptLeaf(g);assert.equal(markerOf(leaf.buf),'v635');
const source=leaf.buf.toString('utf8');let text=source.replace(/\r\n/g,'\n');
const edits=[];
function replaceExact(old,value,label,count=1){
 const actual=text.split(old).length-1;assert.equal(actual,count,`${label}: 修改点数量不符`);
 text=text.split(old).join(value);edits.push({label,count});
}
function removeRange(start,end,label){
 const a=text.indexOf(start);assert(a>=0,label+'开始缺失');const b=text.indexOf(end,a+start.length);assert(b>a,label+'结束缺失');
 const old=text.slice(a,b);replaceExact(old,'\n'.repeat((old.match(/\n/g)||[]).length),label);
}
// 只删除旧teach专用的自检；td.*的新教程、家具、按钮、触发判据均保留。
removeRange('__M["tut_verify"] = function()','__M["tpl_probe"] = function()','移除旧teach自检模块');
removeRange('__M["tpl_probe"] = function()','__M["levels.init"] = function()','移除配置已关闭的模板探针模块');
removeRange('local function verify_tutorial_once(tag)','-- ★ v292：','移除旧teach自检入口');
replaceExact('local tutorial_checked = {}      -- tag → 已经跑过自检','', '移除旧自检记账');
replaceExact('local tutorial_wait = {}         -- tag → 等了多少帧','', '移除旧自检等待记账');
const initStart='      if not inst.inited then\n        -- ★ 兜底：根容器迟迟没进树';
const ia=text.indexOf(initStart),ie=text.indexOf('\n    end\n  end',ia);assert(ia>0&&ie>ia);
replaceExact(text.slice(ia,ie),'','移除旧teach自检调度');
replaceExact('  self:_visible("teach", false)\n  self:_visible("teach.text", false)','', '移除被裁剪旧教程的隐藏查找');
replaceExact('  teach = true, help617 = true,','  help617 = true,','移除旧教程显隐豁免');
removeRange('  if (current.frames or 0) % 300 == 0 then   -- 还原（原条件）','  -- ★★★★★ 2026-10-05 **在这里关掉上面那个','移除无输出且无功能的每300帧只读诊断');
removeRange('local function sync_art642()','-- 648: 结算按钮改用独立美术层','移除零调用的旧642美术同步函数');
replaceExact('local art642_settle_original = nil\nlocal art642_selected = false','', '移除642死函数专用状态');
replaceExact('local TPL_PROBE_DONE = false   -- v311 模板探针只跑一次','', '移除关闭的探针记账');
removeRange('  -- ★ 2026-10-22（v311/v312）**模板探针**：','  if LOAD_ERR ~= nil or Murdoku == nil then return end\n  -- ★ v284：','移除关闭的模板探针调度');
// 每次从权威根表取新句柄，无跨帧缓存；目标未找到或类型异常立即回原DFS。
const dfs='    for i = 1, rn do search(roots[i], 0) end\n  end\n  if assets == nil then';
const direct=`    for i = 1, rn do
      local nm = nil
      pcall(function() nm = roots[i].name end)
      if nm == "root" then
        local direct = nil
        pcall(function() direct = roots[i]:GetChild("assets") end)
        local valid = false
        pcall(function() valid = direct ~= nil and direct.name == "assets" end)
        if valid then assets = direct; break end
      end
    end
    if assets == nil then
      for i = 1, rn do search(roots[i], 0) end
    end
  end
  if assets == nil then`;
replaceExact(dfs,direct,'权威根表直接访问唯一assets，失败走原DFS',2);
// 实时回读后跳过相同状态；读取失败时仍执行原写入，各pcall保持独立。
const oldVisible=`local function help_visible(c, v)
  if c == nil then return end
  pcall(function() if c.SetVisible then c:SetVisible(v) else c.visible = v end end)
  if v then pcall(function() if c.SetActive then c:SetActive(true) end end) end
end`;
const newVisible=`local function help_visible(c, v)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c.visible end)
  if actual ~= v then
    pcall(function() if c.SetVisible then c:SetVisible(v) else c.visible = v end end)
  end
  if v then
    local active = nil
    pcall(function() active = c.active end)
    if active ~= true then pcall(function() if c.SetActive then c:SetActive(true) end end) end
  end
end`;
replaceExact(oldVisible,newVisible,'遮罩与教程显隐实时回读守卫');
const helper=`local function write_art_color650(c, key, want)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c[key] end)
  if actual ~= want then pcall(function() c[key] = want end) end
end
`;
replaceExact('local art647_tint_key = nil',helper+'local art647_tint_key = nil','美术颜色写入实时回读守卫');
replaceExact('  if cd then pcall(function() cd.textColor = 0x00FFFFFF end) end','  write_art_color650(cd, "textColor", 0x00FFFFFF)','倒计时颜色跳过重复写');
replaceExact('    if c then pcall(function() c.imageColor = ready and e[2] or e[3] end) end','    write_art_color650(c, "imageColor", ready and e[2] or e[3])','结算美术颜色跳过重复写');
replaceExact('  if dl then pcall(function() dl.imageColor = (page > 1) and NORMAL or DIM end) end','  write_art_color650(dl, "imageColor", (page > 1) and NORMAL or DIM)','左箭头颜色跳过重复写');
replaceExact('  if dr then pcall(function() dr.imageColor = (page < pages) and NORMAL or DIM end) end','  write_art_color650(dr, "imageColor", (page < pages) and NORMAL or DIM)','右箭头颜色跳过重复写');
replaceExact('      local ok = pcall(function() ctrl.showCursor = true end)','      local ok = pcall(function() if ctrl.showCursor ~= true then ctrl.showCursor = true end end)','光标开关跳过重复写');
// 词法去注释，保持所有字符串、每个换行及非注释词法token不变。
function lexLua(s){
 const tokens=[],comments=[];let i=0;
 const longAt=p=>{const m=/^\[(=*)\[/.exec(s.slice(p,p+100));return m?{open:m[0],close:']'+m[1]+']'}:null;};
 while(i<s.length){
  if(/\s/.test(s[i])){i++;continue;}
  const a=i;
  if(s.startsWith('--',i)){
   const lo=longAt(i+2);if(lo){const end=s.indexOf(lo.close,i+2+lo.open.length);assert(end>=0,'长注释未闭合');i=end+lo.close.length;}
   else{const end=s.indexOf('\n',i);i=end<0?s.length:end;}
   comments.push([a,i]);continue;
  }
  const lo=longAt(i);if(lo){const end=s.indexOf(lo.close,i+lo.open.length);assert(end>=0,'长字符串未闭合');i=end+lo.close.length;}
  else if(s[i]==='"'||s[i]==="'"){const quote=s[i++];while(i<s.length){if(s[i]==='\\'){i+=2;continue;}if(s[i++]===quote)break;}}
  else {const id=/^[A-Za-z_][A-Za-z_0-9]*/.exec(s.slice(i));const num=/^(?:0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?|\d+(?:\.(?!\.)\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/.exec(s.slice(i));const op=/^(?:\.\.\.|\.\.|==|~=|<=|>=|::|\/\/|<<|>>)/.exec(s.slice(i));i+=(id?.[0]||num?.[0]||op?.[0]||s[i]).length;}
  tokens.push(s.slice(a,i));
 }
 return {tokens,comments};
}
const beforeStrip=text;const parsed=lexLua(beforeStrip);let stripped='',last=0;for(const [a,b]of parsed.comments){stripped+=text.slice(last,a)+' '+text.slice(a,b).replace(/[^\r\n]/g,'');last=b;}stripped+=text.slice(last);
assert.deepEqual(lexLua(stripped).tokens,parsed.tokens,'去注释改变了词法token');
assert.equal(stripped.split('\n').length,beforeStrip.split('\n').length,'去注释改变行数');
text=stripped;fs.writeFileSync(LUA,text,'utf8');
// 精确裁剪旧teach完整子树；保留控件ID、顺序及所有可视属性不变。
const root=g.recs.find(r=>r.name==='root'),teach=g.recs.find(r=>r.name==='teach');assert(root&&teach&&teach.parentId===root.id);
assert.equal(g.recs.filter(r=>r.name==='assets').length,1);assert.equal(g.recs.find(r=>r.name==='assets').parentId,root.id);
const remove=new Set();function collect(r){assert(!remove.has(r.id),'父子循环');remove.add(r.id);for(const c of g.recs.filter(c=>c.parentId===r.id))collect(c);}collect(teach);assert.equal(remove.size,334);
const owners=new Map(g.recs.map(r=>[r.field,r]));let allowedRootRefs=0;
function checkRefs(fields,owner=null){for(const f of fields){const o=owners.get(f)||owner;if(o&&remove.has(o.id))continue;
 if(f.wt===0&&remove.has(Number(f.num)))throw new Error('旧教程仍有外部整数引用');
 if(f.wt===2&&f.payload&&!f.isText&&!f.sub){const list=asIdList(f.payload,true);if(list?.some(id=>remove.has(id))){assert(o===root&&f===root.childList,'旧教程仍有外部packed引用');allowedRootRefs++;}}
 if(f.sub)checkRefs(f.sub,o);
 }}checkRefs(g.tree);assert.equal(allowedRootRefs,1);
const oldRecords=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const childIds=asIdList(root.childList.payload,true);setChildList(root.childList,childIds.filter(id=>!remove.has(id)));
const holders=new Set(g.recs.filter(r=>remove.has(r.id)).map(r=>r.holder));for(const holder of holders){for(let i=holder.length-1;i>=0;i--)if(g.recs.some(r=>remove.has(r.id)&&r.field===holder[i]))holder.splice(i,1);}
leaf.field.payload=Buffer.from(text,'utf8');leaf.field.len=leaf.field.payload.length;leaf.field.sub=null;
const expectedRoot=encodeMsg([root.field]);
const rep=writeGil(g,OUTPUT,{label:'650全面优化',expectRecs:6453,expectMarker:'v635',quiet:true,assert:(g2)=>{
 assert.equal(g2.recs.length,g.recs.length-remove.size);
 for(const r of g2.recs){assert(!remove.has(r.id));const expected=r.id===root.id?expectedRoot:oldRecords.get(r.id);assert(expected?.equals(encodeMsg([r.field])),`保留控件发生变化:${r.name}`);}
 const ids=new Set(g2.recs.map(r=>r.id));for(const r of g2.recs){if(r.childList){for(const id of asIdList(r.childList.payload,true)||[])assert(ids.has(id),'残留断链');}}
 const original=readGil(INPUT);for(let i=0;i<original.tree.length;i++){const f=original.tree[i];if(f.field!==9&&f.field!==50)assert(encodeMsg([f]).equals(encodeMsg([g2.tree[i]])),'非控件/脚本区发生变化');}
 assert(findScriptLeaf(g2).buf.equals(Buffer.from(text)),'脚本回读不符');assert(g2.trailer.equals(g.trailer));return true;
}});
const result={inputBytes:g.src.length,outputBytes:rep.bytes,savedBytes:g.src.length-rep.bytes,savedPercent:(g.src.length-rep.bytes)/g.src.length*100,inputSha256:SHA,outputSha256:hash(rep.g2.src),originalRecords:g.recs.length,optimizedRecords:rep.recs,removedControls:remove.size,removedControlBytes:g.recs.filter(r=>remove.has(r.id)).reduce((n,r)=>n+oldRecords.get(r.id).length,0),originalScriptBytes:leaf.buf.length,optimizedScriptBytes:Buffer.byteLength(text),commentBytesRemoved:Buffer.byteLength(beforeStrip)-Buffer.byteLength(text),marker:'v635',variant:'650_优化版（源标记v635）',edits,checks:{inputRoundtrip:true,outputRoundtrip:true,retainedRecordBytesUnchanged:rep.recs-1,rootOnlyChildListChanged:true,nonUiAndScriptFieldsUnchanged:true,commentTokenEquivalence:true,removedControlsNoExternalRefs:true,trailerUnchanged:true},removedIds:[...remove]};
fs.writeFileSync(path.join(HERE,'优化审计数据.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({...result,removedIds:undefined,edits:edits.map(x=>x.label)},null,2));
