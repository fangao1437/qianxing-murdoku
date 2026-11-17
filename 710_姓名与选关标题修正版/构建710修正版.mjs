import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const TMP=process.env.FEIBO_TMP||'C:/Users/18182/AppData/Local/Temp/feibo/d68890ff-e923-480f-bb43-9e49c03e665e';
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(ROOT,'qianxing-murdoku/710_第五关旋转与第六关线索重构/710_第五关旋转与第六关线索重构.gil');
const output=path.join(DIR,'710_姓名与选关标题修正版_v2.gil');
assert(!fs.existsSync(output),'不覆盖已有修正版');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const g=R.readGil(input),originalHash=sha(g.src),byName=new Map(g.recs.map(r=>[r.name,r]));
const lua=fs.readFileSync(path.join(ROOT,'qianxing-murdoku/dist/client_script.lua'));
assert(lua.toString().includes('710修正版2：who实际写入 + 选关标题文本框修复'));
function modules(s){const result=new Map();const re=/__M\["([^"]+)"\] = function\(\)\r?\n([\s\S]*?)(?=\r?\nend\r?\n\r?\n(?:__M\[|-- ==== 入口))/g;for(const hit of s.matchAll(re))result.set(hit[1],hit[2]);return result;}
const old=modules(W.findScriptLeaf(g).buf.toString()),now=modules(lua.toString());
assert.equal(old.size,17);assert.equal(now.size,17);
const changedModules=[...old.keys()].filter(k=>old.get(k)!==now.get(k));
assert.deepEqual(changedModules.slice().sort(),['engine_adapter_qianxing','ui_controller']);
for(let i=1;i<=7;i++)assert.equal(old.get(`levels.case_${String(i).padStart(3,'0')}`),now.get(`levels.case_${String(i).padStart(3,'0')}`));
const exportFile=path.join(TMP,'export_names.lua');
fs.writeFileSync(exportFile,lua.toString().slice(0,lua.toString().indexOf('local FORCE_LEVEL = nil'))+`\nfor i=1,7 do local lv=__require(string.format('levels.case_%03d',i));print('LEVEL\\t'..i..'\\t'..lv.name);for pos,p in ipairs(lv.suspects) do print('WHO\\t'..i..'\\t'..pos..'\\t'..p.id..'\\t'..p.name)end end\n`);
const data=execFileSync('lua',[exportFile],{encoding:'utf8',cwd:ROOT,timeout:30000}).trim().split(/\r?\n/).map(s=>s.split('\t'));
const names=data.filter(x=>x[0]==='WHO'),levels=data.filter(x=>x[0]==='LEVEL');assert.equal(names.length,42);assert.equal(levels.length,7);
function nodesAt(fields,ns){if(!ns.length)return fields;const [n,...tail]=ns;return fields.filter(f=>f.field===n&&f.sub).flatMap(f=>tail.length?nodesAt(f.sub,tail):[f]);}
function group(r){const a=nodesAt(r.field.sub,[505,503,75]);assert.equal(a.length,1,r.name);return a[0];}
function num(t,n,v){let f=t.sub.find(f=>f.field===n&&f.wt===0);if(!f){f={field:n,wt:0,num:0n};t.sub.push(f);}f.num=BigInt(v);}
function textOf(r){const t=group(r),p=t.sub.find(f=>f.field===510&&f.wt===2);return p?.sub?.find(f=>f.field===501&&f.wt===2)?.payload.toString('utf8')||'';}
const changes=[];
function setText(r,text){const t=group(r),before=textOf(r);let p=t.sub.find(f=>f.field===510&&f.wt===2);if(!p){p={field:510,wt:2,sub:[],payload:Buffer.alloc(0),len:0,isText:false};t.sub.push(p);}p.sub=[{field:501,wt:2,sub:null,isText:true,payload:Buffer.from(text),len:Buffer.byteLength(text)}];p.isText=false;p.payload=Buffer.alloc(0);p.len=0;if(before!==text)changes.push({name:r.name,before,after:text});}
for(const [,lv,pos,id,name]of names){const r=byName.get(`who.${lv}.${pos}`);assert(r);const lr=byName.get(`letter.${lv}.${pos}`);assert(lr);assert.equal(textOf(lr),id,'发言人编号不符');setText(r,name);}
const titleMetrics=[];
for(let slot=1;slot<=4;slot++){
 const r=byName.get(`select.card.${slot}.info`),paper=byName.get(`art647.select.card.${slot}.paper`);assert(r&&paper);
 setText(r,levels[slot-1][2].split('·').at(-1).trim());
 const t=group(r);num(t,504,0xFF4A2E1C);num(t,512,18);num(t,513,18);num(t,508,1);num(t,509,1);
 const st=R.stateBlocks(paper.field.sub,[])[0],p=R.pairOf(st,504),z=R.pairOf(st,505),x=R.pairValue(p,0),y=R.pairValue(p,1),w=R.pairValue(z,0),h=R.pairValue(z,1);
 for(const s of R.stateBlocks(r.field.sub,[])){R.setPair(R.pairOf(s,504),x,y-h*.41);R.setPair(R.pairOf(s,505),w*.91,h*.15);}
 titleMetrics.push({slot,width:w*.91,height:h*.15,fontSize:18});assert(h*.15>=36);
}
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'710修正版2：who与选关标题',expectRecs:8300,expectMarker:'v710',assert(g2){assert(W.findScriptLeaf(g2).buf.equals(lua));for(const r of g2.recs)assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),r.name);for(const [,lv,pos,id,name]of names)assert.equal(textOf(g2.recs.find(r=>r.name===`who.${lv}.${pos}`)),name);return true;}});
assert.equal(sha(fs.readFileSync(input)),originalHash);
const audit={version:710,revision:2,base:path.basename(input),output:path.basename(output),baseSha256:originalHash,sha256:sha(fs.readFileSync(output)),bytes:rep.bytes,records:rep.recs,fieldDiffs:rep.diffs,changes,checkedWhoCount:names.length,changedModules,allSevenLevelModulesUnchanged:true,titleMetrics,roundtrip:true,realGameTest:false,causes:['列表填充计算新文本后没有写入who/what/letter','选关文字18号而框高28.58，小于本地实测要求的两倍字号'],verification:'710修正版_验证结果.json',limits:['离线回放模拟控件API；本轮未操作游戏、未做真机导入']};
fs.writeFileSync(path.join(DIR,'710修正版_构建审计.json'),JSON.stringify(audit,null,2));
console.log(JSON.stringify({output,checkedWhoCount:names.length,changedWhoCount:changes.filter(x=>x.name.startsWith('who.')).length,staticTitles:4,titleMetrics,records:rep.recs,changedModules},null,2));
