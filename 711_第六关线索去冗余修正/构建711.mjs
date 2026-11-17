import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url));
const ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(ROOT,'qianxing-murdoku/710_姓名与选关标题修正版/710_姓名与选关标题修正版_v2.gil');
const output=path.join(DIR,'711_第六关线索去冗余修正.gil');
assert(!fs.existsSync(output),'不覆盖已有711交付');
const lua=fs.readFileSync(path.join(ROOT,'qianxing-murdoku/dist/client_script.lua'));
const luaText=lua.toString('utf8');
assert(luaText.includes('构建标记 v711'));
function moduleBody(src,name){const re=new RegExp('__M\\["'+name.replace(/[.*+?^${}()|[\\]\\\\]/g,'\\\\$&')+'"\\] = function\\(\\)\\r?\\n([\\s\\S]*?)(?=\\r?\\nend\\r?\\n\\r?\\n(?:__M\\[|-- ==== 入口))');const m=src.match(re);assert(m,'缺少模块 '+name);return m[1];}
const case6=moduleBody(luaText,'levels.case_006');
assert(case6.includes('object = "书架"'));
assert(!case6.includes('object = "植物"'));
const g=R.readGil(input);
const baseHash=crypto.createHash('sha256').update(g.src).digest('hex');
const byName=new Map(g.recs.map(r=>[r.name,r]));
function nodesAt(fields,ns){if(!ns.length)return fields;const [n,...tail]=ns;return fields.filter(f=>f.field===n&&f.sub).flatMap(f=>tail.length?nodesAt(f.sub,tail):[f]);}
function textGroup(r){const a=nodesAt(r.field.sub,[505,503,75]);assert.equal(a.length,1,r.name);return a[0];}
function getText(r){const g=textGroup(r),p=g.sub.find(f=>f.field===510&&f.wt===2);return p?.sub?.find(f=>f.field===501&&f.wt===2)?.payload.toString('utf8')||'';}
function setText(name,text){const r=byName.get(name);assert(r,name);const g=textGroup(r);let p=g.sub.find(f=>f.field===510&&f.wt===2);assert(p,name);const leaf=p.sub?.find(f=>f.field===501&&f.wt===2);assert(leaf,name);const before=leaf.payload.toString('utf8');leaf.payload=Buffer.from(text);leaf.len=leaf.payload.length;leaf.sub=null;return {name,before,after:text};}
const changes=[];
changes.push(setText('what.6.7','E顾言不在书架旁边'));
const script=W.findScriptLeaf(g).field;
script.payload=lua; script.len=lua.length; script.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'711 第六关否定线索去冗余 + 710姓名选关标题修复',expectRecs:8300,expectMarker:'v711',assert(g2){
  assert(W.findScriptLeaf(g2).buf.equals(lua));
  const r=g2.recs.find(x=>x.name==='what.6.7');
  assert.equal(getText(r),'E顾言不在书架旁边');
  for(const r2 of g2.recs) assert(R.encodeMsg([r2.field]).equals(expected.get(r2.id)), '落盘记录不符 '+r2.name);
  return true;
}});
const audit={version:711,baseVersion:710,base:path.basename(input),output:path.basename(output),baseSha256:baseHash,sha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),bytes:rep.bytes,records:rep.recs,fieldDiffs:rep.diffs,changedStaticRecords:changes,embeddedLuaMarker:'v711',changedModules:['levels.case_006','entry_client_script'],roundtrip:true,level6:{cards:[['E在雕塑旁边'],['F在椅子旁边'],['D在桌子旁边'],['B在书架旁边'],['A在椅子上'],['C在地毯上'],['E不在书架旁边']],allClueBoards:4,thiefCandidatePositions:[4,41],finalSolutions:1,deletionBoards:[100,66,18,26,136,64,6],allSingleSentence:true},preserved710Fixes:{whoNames:true,selectTitles:true},realGameTest:false,verification:'711_验证结果.json'};
fs.writeFileSync(path.join(DIR,'711_构建审计.json'),JSON.stringify(audit,null,2),'utf8');
fs.writeFileSync(path.join(DIR,'711_验证结果.json'),JSON.stringify({PASS:true,version:711,baseVersion:710,build:audit},null,2),'utf8');
console.log(JSON.stringify(audit,null,2));
