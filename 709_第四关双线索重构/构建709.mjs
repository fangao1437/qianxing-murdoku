// 基于708，仅替换第4关A/B卡、对应提示与版本标记。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(DIR,'../708_第五七关单句与墙修正/708_第五七关单句与墙修正.gil');
const output=path.join(DIR,'709_第四关双线索重构.gil');
assert(!fs.existsSync(output),'不覆盖已有709交付');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const check=JSON.parse(fs.readFileSync(path.join(DIR,'709_验证结果.json'),'utf8'));
assert(check.PASS && check.verification.length===5 && check.verification.every(x=>x.PASS));
assert.equal(check.split_proof.combined_without_original,0);
assert(check.split_proof.first_without_original>0 && check.split_proof.second_without_original>0);
for(const [rel,sha] of Object.entries(check.sourceHashes))assert.equal(hash(fs.readFileSync(path.join(ROOT,rel))),sha,'验证后源文件变化 '+rel);
const d=JSON.parse(fs.readFileSync(path.join(ROOT,'murdoku-project/第三四关内容设计/current_design_v16.json'),'utf8')).find(x=>x.level===4);
const g=R.readGil(input),lua=fs.readFileSync(path.join(DIR,'../dist/client_script.lua'));
assert.equal(W.markerOf(lua),'v709');
function modules(s){const result=new Map();const re=/__M\["([^"]+)"\] = function\(\)\r?\n([\s\S]*?)(?=\r?\nend\r?\n\r?\n(?:__M\[|-- ==== 入口))/g;for(const hit of s.matchAll(re))result.set(hit[1],hit[2]);return result;}
const beforeText=W.findScriptLeaf(g).buf.toString('utf8'),afterText=lua.toString('utf8');
const beforeModules=modules(beforeText),afterModules=modules(afterText);
assert.equal(beforeModules.size,17);assert.equal(afterModules.size,17);
for(const [name,body]of beforeModules)if(name!=='levels.case_004')assert.equal(afterModules.get(name),body,'计划外模块变化 '+name);
const norm=s=>s.replace(/构建标记 v(?:708|709) \/ 2026-11-17 \/ [^\r\n]*?=====/g,'构建标记 SAME =====').replace(beforeModules.get('levels.case_004'),'LEVEL4').replace(afterModules.get('levels.case_004'),'LEVEL4');
assert.equal(norm(beforeText),norm(afterText),'模块外出现非版本标记变化');
const changed=[];
for(let i=0;i<6;i++){
 const name=`what.4.${i+1}`,r=g.recs.find(r=>r.name===name);assert(r,name);
 const leaves=R.textsOf(r.field.sub,[]).filter(f=>f.payload.toString('utf8')!==name);assert.equal(leaves.length,1);
 const text=d.display_cards[i].join('、'),old=leaves[0].payload.toString('utf8');
 if(old!==text){assert(i<2,'其他卡文案变化');const f=leaves[0];f.payload=Buffer.from(text);f.len=f.payload.length;f.sub=null;changed.push({id:r.id,name,before:old,after:text});}
}
assert.equal(changed.length,2);
const script=W.findScriptLeaf(g).field;script.payload=lua;script.len=lua.length;script.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'709 第四关双线索重构（基于708）',expectRecs:8300,expectDiffs:3,expectMarker:'v709',assert(g2){
 assert(W.findScriptLeaf(g2).buf.equals(lua));
 for(const r of g2.recs)assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘记录不符 '+r.name);
 return true;
}});
const audit={version:709,baseVersion:708,input:path.basename(input),output:path.basename(output),sha256:hash(fs.readFileSync(output)),bytes:rep.bytes,records:rep.recs,fieldDiffs:rep.diffs,changedStaticRecords:changed,embeddedLuaMarker:rep.marker,changedModules:['levels.case_004'],roundtrip:true,verification:'709_验证结果.json',cards:d.display_cards,hints:d.hint_preview,geometryUnchanged:true,realGameTest:false,renumberedFrom:609,historical609Overwritten:false};
fs.writeFileSync(path.join(DIR,'709_构建审计.json'),JSON.stringify(audit,null,2),'utf8');
console.log(JSON.stringify(audit,null,2));
