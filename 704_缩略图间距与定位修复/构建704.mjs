// 704：保留703全部控件记录，只更新内嵌客户端脚本。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilread.mjs'));
const W=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const INPUT=DIR+'/../703_选关卡片样式调整/703_选关卡片样式调整.gil',OUTPUT=DIR+'/704_缩略图间距与定位修复.gil';
assert(!fs.existsSync(OUTPUT),'不覆盖已有704存档');
const g=R.readGil(INPUT),lua=fs.readFileSync(DIR+'/../dist/client_script.lua');assert.equal(W.markerOf(lua),'v704');
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const rep=W.writeGil(g,OUTPUT,{label:'704 等宽格缝与门墙定位修复',expectRecs:8300,expectMarker:'v704',assert(d){
 assert(W.findScriptLeaf(d).buf.equals(lua));assert.equal(d.recs.length,before.size);
 for(const r of d.recs)assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'控件记录意外变动 '+r.name);
 return true;
}});
fs.writeFileSync(DIR+'/704_内嵌Lua_704.lua',lua);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const audit={version:704,input:path.basename(INPUT),output:path.basename(OUTPUT),sha256:sha(fs.readFileSync(OUTPUT)),records:rep.recs,unchangedControlRecords:before.size,gapCanvasPx:2,wallCanvasPx:3,doorCanvasPx:5,notes:['同一关格宽、步长为整数画布单位','所有格子、底板共用卡框精确中心，不逐控件取整','门墙共用格缝中心线','纯色矩形、底部案件名、教程与迟到补发修复保留','未验证游戏实机像素及真实输入']};
fs.writeFileSync(DIR+'/704_构建审计.json',JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
