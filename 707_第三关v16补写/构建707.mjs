// 基于706补写第三关v16；卡序由本轮新口径验证结果决定。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url));
const ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(DIR,'../706_3567优化与第七关墙布局/706_3567优化与第七关墙布局.gil');
const output=path.join(DIR,'707_第三关v16补写.gil');
assert(!fs.existsSync(output),'不覆盖已有707');
const verification=JSON.parse(fs.readFileSync(path.join(DIR,'707_验证结果.json'),'utf8'));
assert(verification.PASS && verification.level3.mode==='teaching_all_true','第三关教学口径复验必须通过');
assert(verification.level6.mode==='teaching_all_true' && verification.level6.PASS,'第六关教学复核必须通过');
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
assert.equal(digest(fs.readFileSync(path.join(DIR,'../lua/levels/case_003.lua'))),verification.sourceSha256,'第三关源码已变，必须重新验证');
const texts=verification.reordered.display_cards.map(c=>c.join('、'));
const g=R.readGil(input),lua=fs.readFileSync(path.join(DIR,'../dist/client_script.lua'));
assert.equal(W.markerOf(lua),'v707');
const originalLua=W.findScriptLeaf(g).buf.toString('utf8');
function modules(s){const result=new Map();const re=/__M\["([^"]+)"\] = function\(\)\r?\n([\s\S]*?)(?=\r?\nend\r?\n\r?\n(?:__M\[|-- ==== 入口))/g;for(const hit of s.matchAll(re))result.set(hit[1],hit[2]);return result;}
const beforeModules=modules(originalLua),afterModules=modules(lua.toString('utf8'));
assert(beforeModules.has('levels.case_003')&&beforeModules.has('levels.case_007'));
assert.equal(afterModules.size,beforeModules.size);
for(const [name,body]of beforeModules)if(name!=='levels.case_003')assert.equal(afterModules.get(name),body,'计划外模块变化 '+name);
assert.notEqual(beforeModules.get('levels.case_003'),afterModules.get('levels.case_003'));
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])])),changed=[];
for(let i=0;i<texts.length;i++){
 const name=`what.3.${i+1}`,r=g.recs.find(r=>r.name===name);assert(r,name);
 const leaves=R.textsOf(r.field.sub,[]).filter(f=>f.payload.toString('utf8')!==name);assert.equal(leaves.length,1,name+'文本叶子不唯一');
 if(leaves[0].payload.toString('utf8')!==texts[i]){
  leaves[0].payload=Buffer.from(texts[i]);leaves[0].len=leaves[0].payload.length;leaves[0].sub=null;changed.push(r.id);
 }
}
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'707 第三关v16、新口径合法卡序与浅蓝提示',expectRecs:8300,expectDiffs:changed.length+1,expectMarker:'v707',assert(g2){
 assert(W.findScriptLeaf(g2).buf.equals(lua));
 for(const r of g2.recs){assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘记录不符 '+r.name);if(!changed.includes(r.id))assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'白名单外控件变化 '+r.name);}
 for(let i=0;i<texts.length;i++){const r=g2.recs.find(r=>r.name===`what.3.${i+1}`);assert(R.textsOf(r.field.sub,[]).some(f=>f.payload.toString('utf8')===texts[i]));}
 return true;
}});
const audit={version:707,input:path.basename(input),output:path.basename(output),sha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),bytes:rep.bytes,records:rep.recs,fieldDiffs:rep.diffs,changedStaticRecords:changed,changedStaticCount:changed.length,embeddedLuaMarker:rep.marker,cardTexts:texts,cardOrder:verification.card_order_1based,selfReferenceCards:verification.self_reference_cards,basis:verification.level3.basis,teachingLevels:[3,6],hintCounts:verification.runtime.checks.find(x=>x.level===3).hints.map(x=>x.count),unchangedModules:[...beforeModules.keys()].filter(x=>x!=='levels.case_003'),preserved:'706第5/6/7关及第7关墙位与缩略图数据',verification:'707_验证结果.json',roundtrip:true};
fs.writeFileSync(path.join(DIR,'707_构建审计.json'),JSON.stringify(audit,null,2),'utf8');
console.log(JSON.stringify(audit,null,2));
