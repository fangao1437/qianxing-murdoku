// 从700保留全部真实控件，仅替换客户端脚本。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs'))),W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const INPUT=path.join(DIR,'../700_启动与教程点击修复/700_启动与教程点击修复.gil'),OUTPUT=path.join(DIR,'701_选关缩略图与关卡名修复.gil');assert(!fs.existsSync(OUTPUT),'拒绝覆盖已有701存档');
const g=R.readGil(INPUT),lua=fs.readFileSync(path.join(DIR,'../dist/client_script.lua'));assert.equal(W.markerOf(lua),'v701');
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const rep=W.writeGil(g,OUTPUT,{label:'701 选关缩略图与关卡名补发修复',expectRecs:g.recs.length,expectMarker:'v701',assert(d){assert(W.findScriptLeaf(d).buf.equals(lua));for(const r of d.recs)assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'控件记录发生变化 '+r.name);return true;}});
fs.writeFileSync(path.join(DIR,'701_内嵌Lua_701.lua'),lua);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');const audit={version:701,base:path.basename(INPUT),baseSha256:sha(g.src),output:path.basename(OUTPUT),sha256:sha(fs.readFileSync(OUTPUT)),records:rep.recs,allControlRecordsUnchanged:true,changes:['选关内容未找到时不缓存成功，句柄出现后清除旧属性并重新绑定/下发','选关内容属性失败不再在三次后假定成功','缩略图池及图元使用真实固定父级路径，不为每项重扫全树','原生选关文本直接写入并读回，明确深棕字色与字号'],limits:['已复现迟到加载缺陷，尚不能断言这是用户截图的全部成因','保留700教程修复、父级门控、284图元与全部七关数据','未操作游戏或验证真机视觉']};fs.writeFileSync(path.join(DIR,'701_构建审计.json'),JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
