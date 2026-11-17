// 从699保留全部控件，仅替换经过验证的客户端脚本。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs'))),W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const INPUT=path.join(DIR,'../699_教程与交互修复/699_教程与交互修复.gil'),OUTPUT=path.join(DIR,'700_启动与教程点击修复.gil');assert(!fs.existsSync(OUTPUT),'拒绝覆盖已有700存档');
const g=R.readGil(INPUT),lua=fs.readFileSync(path.join(DIR,'../dist/client_script.lua'));assert.equal(W.markerOf(lua),'v700');
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const rep=W.writeGil(g,OUTPUT,{label:'700 教程延迟加载与按钮绑定修复',expectRecs:g.recs.length,expectMarker:'v700',assert(d){assert(W.findScriptLeaf(d).buf.equals(lua));for(const r of d.recs)assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'控件记录发生变化 '+r.name);return true;}});
fs.writeFileSync(path.join(DIR,'700_内嵌Lua_700.lua'),lua);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');const audit={version:700,base:path.basename(INPUT),baseSha256:sha(g.src),output:path.basename(OUTPUT),sha256:sha(fs.readFileSync(OUTPUT)),records:rep.recs,allControlRecordsUnchanged:true,changes:['教程根内直接补查迟到按钮，绕过尚未刷新的名称索引','必需按钮成功绑定后才标记初始化完成；缺项或绑定失败由后续帧重试','打开前确保初始化完成，保留父级门控、缩略图及全局索引优化','初始化日志确认必需按钮已绑定，并记录教程关闭'],limits:['仅离线验证，不证明真机射线命中或帧率']};fs.writeFileSync(path.join(DIR,'700_构建审计.json'),JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
