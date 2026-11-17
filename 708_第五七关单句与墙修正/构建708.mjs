// 基于707写入已验证的单句关卡，保留其他存档记录。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(DIR,'../707_第三关v16补写/707_第三关v16补写.gil');
const output=path.join(DIR,'708_第五七关单句与墙修正.gil');
assert(!fs.existsSync(output),'不覆盖已有708');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const src=path.join(ROOT,'murdoku-project/第三四关内容设计');
const designs=JSON.parse(fs.readFileSync(path.join(src,'current_design_v16.json'),'utf8'));
const reports=JSON.parse(fs.readFileSync(path.join(src,'verification_v16.json'),'utf8'));
const check=JSON.parse(fs.readFileSync(path.join(DIR,'708_验证结果.json'),'utf8'));
assert(check.PASS,'完整验证未通过');
for(const [rel,sha] of Object.entries(check.sourceHashes))assert.equal(hash(fs.readFileSync(path.join(ROOT,rel))),sha,'验证后文件变化 '+rel);
for(const level of [3,5,6,7]){
 const d=designs.find(x=>x.level===level),r=reports.find(x=>x.level===level);
 assert(r?.PASS);assert.deepEqual(r.cards,d.cards);assert.deepEqual(r.objects,d.objects);assert.deepEqual(r.target,d.target);
 if([3,6].includes(level))assert.equal(r.mode,'teaching_all_true');
}
const g=R.readGil(input),lua=fs.readFileSync(path.join(DIR,'../dist/client_script.lua'));
assert.equal(W.markerOf(lua),'v708');
function modules(s){const result=new Map();const re=/__M\["([^"]+)"\] = function\(\)\r?\n([\s\S]*?)(?=\r?\nend\r?\n\r?\n(?:__M\[|-- ==== 入口))/g;for(const hit of s.matchAll(re))result.set(hit[1],hit[2]);return result;}
const beforeModules=modules(W.findScriptLeaf(g).buf.toString('utf8')),afterModules=modules(lua.toString('utf8'));
const allowedModules=new Set(['levels.case_005','levels.case_007','ui_controller']);
assert.equal(afterModules.size,beforeModules.size);
for(const [name,body]of beforeModules)if(!allowedModules.has(name))assert.equal(afterModules.get(name),body,'计划外模块变化 '+name);
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])])),changed=[];
for(const level of [5,7]){
 const d=designs.find(x=>x.level===level);
 for(let i=0;i<d.display_cards.length;i++){
  const text=d.display_cards[i].join('、'),name=`what.${level}.${i+1}`,r=g.recs.find(r=>r.name===name);assert(r,name);
  const leaves=R.textsOf(r.field.sub,[]).filter(f=>f.payload.toString('utf8')!==name);assert.equal(leaves.length,1);
  if(leaves[0].payload.toString('utf8')!==text){const f=leaves[0];f.payload=Buffer.from(text);f.len=f.payload.length;f.sub=null;changed.push(r.id);}
 }
}
const script=W.findScriptLeaf(g).field;script.payload=lua;script.len=lua.length;script.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'708 第五七关单句卡、通用线索与墙修正',expectRecs:8300,expectDiffs:changed.length+1,expectMarker:'v708',assert(g2){
 assert(W.findScriptLeaf(g2).buf.equals(lua));
 for(const r of g2.recs)assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘记录不符 '+r.name);
 return true;
}});
const audit={version:708,input:path.basename(input),output:path.basename(output),sha256:hash(fs.readFileSync(output)),bytes:rep.bytes,records:rep.recs,fieldDiffs:rep.diffs,changedStaticRecords:changed,embeddedLuaMarker:rep.marker,changedModules:[...beforeModules.keys()].filter(k=>beforeModules.get(k)!==afterModules.get(k)),roundtrip:true,verification:'708_验证结果.json',cards:designs.filter(d=>[5,7].includes(d.level)).map(d=>({level:d.level,cards:d.display_cards,general:d.general_clues,hints:d.hint_preview})),wallRemoved:['h',3,4],roomPartitionUnchanged:true,realGameTest:false};
fs.writeFileSync(path.join(DIR,'708_构建审计.json'),JSON.stringify(audit,null,2),'utf8');
console.log(JSON.stringify(audit,null,2));
