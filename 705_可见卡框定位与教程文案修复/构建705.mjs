// 705：以704为基线，更新脚本及两关教程末页文字，其余控件原样保留。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilread.mjs'));
const W=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const INPUT=DIR+'/../704_缩略图间距与定位修复/704_缩略图间距与定位修复.gil',OUTPUT=DIR+'/705_可见卡框定位与教程文案修复.gil';
assert(!fs.existsSync(OUTPUT),'不覆盖已有705存档');
const g=R.readGil(INPUT),lua=fs.readFileSync(DIR+'/../dist/client_script.lua');assert.equal(W.markerOf(lua),'v705');
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])])),changed=[];
for(const name of ['td.l1.page.8.nexttext','td.l2.page.4.nexttext']){
 const r=g.recs.find(r=>r.name===name);assert(r,name);
 const matches=R.textsOf(r.field.sub,[]).filter(f=>f.payload.toString('utf8')==='开始试玩');assert.equal(matches.length,1);
 matches[0].payload=Buffer.from('开始办案');matches[0].len=matches[0].payload.length;matches[0].sub=null;changed.push(r.id);
}
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const rep=W.writeGil(g,OUTPUT,{label:'705 可见白框定位、门墙等宽5与开始办案文案',expectRecs:8300,expectMarker:'v705',assert(d){
 assert(W.findScriptLeaf(d).buf.equals(lua));assert.equal(d.recs.length,before.size);
 for(const r of d.recs){assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘记录不一致 '+r.name);if(!changed.includes(r.id))assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'白名单外变动 '+r.name);}
 for(const id of changed)assert(R.textsOf(d.recs.find(r=>r.id===id).field.sub,[]).some(f=>f.payload.toString('utf8')==='开始办案'));
 return true;
}});
fs.writeFileSync(DIR+'/705_内嵌Lua_705.lua',lua);
const audit={version:705,input:path.basename(INPUT),output:path.basename(OUTPUT),sha256:crypto.createHash('sha256').update(fs.readFileSync(OUTPUT)).digest('hex'),records:rep.recs,changedControlRecords:changed,unchangedControlRecords:before.size-changed.length,visualReference:'art647.select.card.N.paper',gapCanvasPx:2,wallCanvasPx:5,doorCanvasPx:5,notes:['基于实际白色卡框及其父链计算视觉位置','保留原有点击事件、教程绑定和迟到属性补发','仅更改两关末页nexttext文本；控件层级与几何数据未改','未操作游戏，未验证真实像素和鼠标命中']};
fs.writeFileSync(DIR+'/705_构建审计.json',JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
