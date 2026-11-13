// 基于680定向修复：教程纯数字行列标尺、房间号的真实棋盘定位。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)), ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku/tools/gil/gilread.mjs'));
const {writeGil,findScriptLeaf}=await import(pathToFileURL(ROOT+'/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const O=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));
const INPUT=ROOT+'/qianxing-murdoku/680_网格纸与家具层序/680_网格纸与家具层序.gil';
const OUTPUT=DIR+'/681_标尺与房间号.gil';
if(fs.existsSync(OUTPUT))throw Error('681输出已存在');
const g=R.readGil(INPUT), before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])])), originalIds=new Set(before.keys());
const named=n=>{const r=g.recs.find(r=>r.name===n);if(!r)throw Error('缺记录 '+n);return r};
const leaf=findScriptLeaf(g), oldScript=leaf.buf.toString('utf8');
function replaceOne(s,a,b){if(s.split(a).length!==2)throw Error('锚点不唯一 '+a.slice(0,90));return s.replace(a,b)}
const layout=`  -- 681：标注直接使用 stage 的真实格子坐标，所有屏均下发显隐。
  do
    local in_level = (self.screen == nil or self.screen == "level")
    for i = 1, 7 do
      for _, axis in ipairs({ "r", "c" }) do
        local visible = in_level and i <= ((axis == "r") and vm.rows or vm.cols)
        push({ id = "ruler." .. axis .. "." .. i, kind = "textbox", parent = "stage",
          rect = { x = 0, y = 0, w = 1, h = 1 }, visible = visible, text = tostring(i),
          board_annotation = { axis = axis, index = i, n = n, visible = visible } })
      end
      local lb = (in_level and furn_art.labels) and furn_art.labels[i] or nil
      local ac = lb and (lb.cell or { r = lb.box.r2, c = lb.box.c1 }) or { r = 1, c = 1 }
      push({ id = "label." .. i, kind = "textbox", parent = "stage",
        rect = { x = 0, y = 0, w = 1, h = 1 }, visible = (lb ~= nil),
        text = lb and (tostring(lb.room) .. "号房间") or "",
        board_annotation = { axis = "room", r = ac.r, c = ac.c, n = n, visible = (lb ~= nil) } })
    end
  end
`;
const adapterMethods=`-- 681：标尺/房间号统一按 cell_geometry 与 cell_offset 定位。
function Adapter:sync_board_annotations()
  for id, a in pairs(self._board_annotations or {}) do
    local ctrl = self:find(id)
    if ctrl ~= nil then
      if a.visible then
        local size, pitch, margin, pw, ph = self:cell_geometry(a.n)
        local x, y, w, h
        if a.axis == "c" then
          x, y = self:cell_offset(1, a.index, a.n)
          y = ph / 2 - margin + 16
          w, h = 30, 26
        elseif a.axis == "r" then
          x, y = self:cell_offset(a.index, 1, a.n)
          x = margin - pw / 2 - 18
          w, h = 30, 26
        else
          x, y = self:cell_offset(a.r, a.c, a.n)
          y = y - size * 0.30
          w, h = size * 0.92, 24
        end
        if ctrl.SetAnchorMin then ctrl:SetAnchorMin(0.5, 0.5) end
        if ctrl.SetAnchorMax then ctrl:SetAnchorMax(0.5, 0.5) end
        if ctrl.SetPivot then ctrl:SetPivot(0.5, 0.5) end
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(x, y)
        ctrl.adaptiveFontSize = false
        ctrl.fontSize = (a.axis == "room") and 16 or 20
        ctrl.fontColor = (a.axis == "room") and 0xFF3A3A36 or 0xFFCBBFA6
        if ctrl.SetActive then ctrl:SetActive(true) end
        if ctrl.SetAsLastSibling then ctrl:SetAsLastSibling() end
      end
      if ctrl.SetVisible then ctrl:SetVisible(a.visible == true) end
    end
  end
end

`;
function patchController(s){
 const start=s.indexOf('    push({ id = "labels", kind = "container", parent = "root", pos_runtime = true,');
 if(start<0)throw Error('无房间标签区段');
 const end=s.indexOf('\n  end',s.indexOf('      push(node)',start))+7;
 if(end<start)throw Error('无标签区段结尾');
 // 保留外层 do 之前的注释，只替换旧 do 的正文（含原来的 end）。
 s=s.slice(0,start)+layout.replace(/^  --[^\n]*\n  do\n/,'')+s.slice(end);
 if(s.includes('  if batched then pcall(function() adapter:end_furn_batch() end) end')) {
   s=replaceOne(s,'  if batched then pcall(function() adapter:end_furn_batch() end) end',
   '  if batched then pcall(function() adapter:end_furn_batch() end) end\n  if ok and adapter and adapter.sync_board_annotations then adapter:sync_board_annotations() end');
 } else {
   s=replaceOne(s,'function Controller:render(adapter, force)','function Controller:_render_681(adapter, force)');
   const at=s.lastIndexOf('return M');if(at<0)throw Error('无控制器导出');
   s=s.slice(0,at)+`function Controller:render(adapter, force)\n  self:_render_681(adapter, force)\n  if adapter and adapter.sync_board_annotations then adapter:sync_board_annotations() end\nend\n\n`+s.slice(at);
 }
 return s;
}
function patchAdapter(s){
 s=replaceOne(s,'function Adapter:cell_offset(r, c, n)',adapterMethods+'function Adapter:cell_offset(r, c, n)');
 s=replaceOne(s,'function Adapter:set_property(id, key, value, nkey)',`function Adapter:set_property(id, key, value, nkey)
  if key == "board_annotation" then
    if self:find(id) == nil then return false end
    self._board_annotations = self._board_annotations or {}
    self._board_annotations[id] = value
    return true
  end
  -- 标注 rect 不走旧设计画布换算；由渲染末尾统一按 stage 定位。
  if key == "rect" and (id:match("^ruler%.[rc]%.%d+$") or id:match("^label%.%d+$")) then return true end
`);
 return s;
}
let script=patchAdapter(patchController(oldScript));
// 旧路径改为直接stage；新增路径供655快速查找表使用。
for(let i=1;i<=7;i++)script=replaceOne(script,`["label.${i}"] = "root/labels/grp653.static.1.labels/label.${i}"`,`["label.${i}"] = "root/stage/label.${i}"`);
script=replaceOne(script,'  ["tpl.ruler"] = "root/tpl.ruler",',
 '  ["tpl.ruler"] = "root/tpl.ruler",\n'+Array.from({length:7},(_,j)=>['r','c'].map(a=>`  ["ruler.${a}.${j+1}"] = "root/stage/ruler.${a}.${j+1}",`).join('\n')).join('\n'));
leaf.field.payload=Buffer.from(script);leaf.field.len=leaf.field.payload.length;
const stage=named('stage'), oldGroup=named('grp653.static.1.labels');
for(let i=1;i<=7;i++){
 const r=named('label.'+i); r.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(stage.id);r.parentId=stage.id;
}
const digits=named('td.home.page.1.svg.59');
const recTop=g.tree.find(f=>f.field===9);
let alloc=Math.max(...g.recs.map(r=>r.id))+1;
function walk(f,fn){fn(f);for(const c of f.sub||[])walk(c,fn)}
for(let i=1;i<=7;i++)for(const a of ['r','c']){
 const id=alloc++, name=`ruler.${a}.${i}`, f=R.cloneField(digits.field);
 walk(f,x=>{if(x.wt===0&&x.num===BigInt(digits.id))x.num=BigInt(id);if(x.isText&&x.payload){const t=x.payload.toString();if(t===digits.name||t==='1'){x.payload=Buffer.from(t===digits.name?name:String(i));x.len=x.payload.length}}});
 f.sub.find(x=>x.field===504&&x.wt===0).num=BigInt(stage.id);
 O.setHiddenRecord(f,true);
 for(const st of R.stateBlocks(f.sub,[])){
  for(const k of [502,503,506]){const p=R.pairOf(st,k);if(p)R.setPair(p,0.5,0.5)}
  R.setPair(R.pairOf(st,504),0,0);R.setPair(R.pairOf(st,505),30,26);
 }
 recTop.sub.push(f);
}
g.recs=R.recordsOf(g.tree);
// 只更新两个受影响容器的显式子列表，按记录表顺序排序。
for(const r of [oldGroup,stage]){
 const ids=g.recs.filter(c=>c.parentId===r.id).map(c=>c.id);
 R.setChildList(R.ensureChildListTop(r),ids);
}
// 源码同步同一补丁；不将版本不同的dist整体覆盖到存档。
const ctrlPath=ROOT+'/qianxing-murdoku/lua/ui_controller.lua';
const adapterPath=ROOT+'/qianxing-murdoku/lua/engine_adapter_qianxing.lua';
const ctrl=fs.readFileSync(ctrlPath,'utf8').replace(/\r\n/g,'\n');
const ad=fs.readFileSync(adapterPath,'utf8').replace(/\r\n/g,'\n');
const ctrlPatched=patchController(ctrl), adPatched=patchAdapter(ad);
// 写文件前先确认源脚本和内嵌脚本都成功完成锚点匹配。
fs.writeFileSync(ctrlPath,ctrlPatched);fs.writeFileSync(adapterPath,adPatched);
fs.writeFileSync(process.env.FEIBO_TMP+'/681.lua',script);
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const report=writeGil(g,OUTPUT,{label:'681 numeric rulers + room labels',expectRecs:before.size+14,assert(t){
 if(!findScriptLeaf(t).buf.equals(Buffer.from(script)))return '脚本不符';
 for(const r of t.recs)if(!expected.get(r.id)?.equals(R.encodeMsg([r.field])))return '记录回读不符 '+r.name;
 return true;
}});
const changed=g.recs.filter(r=>originalIds.has(r.id)&&!before.get(r.id).equals(R.encodeMsg([r.field]))).map(r=>r.name||'#'+r.id);
const audit={input:path.basename(INPUT),inputSha256:crypto.createHash('sha256').update(fs.readFileSync(INPUT)).digest('hex'),output:path.basename(OUTPUT),sha256:crypto.createHash('sha256').update(fs.readFileSync(OUTPUT)).digest('hex'),records:[before.size,g.recs.length],added:14,removed:0,changed,scriptBytes:[Buffer.byteLength(oldScript),Buffer.byteLength(script)],notes:['ruler沿用td.home.page.1.svg.59纯数字文本样式','label.1..7直挂stage，实际格子坐标定位并在家具批次结束后抬到顶层','源码已同步；dist/client_script.lua保留旧版，未重新bundle']};
fs.writeFileSync(process.env.FEIBO_TMP+'/681-audit.json',JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
