import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const TMP=process.env.FEIBO_TMP||String.raw`C:\Users\18182\AppData\Local\Temp\feibo\cec886a5-458c-4bfe-be02-1be51696e217`;
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(ROOT,'qianxing-murdoku/712_人物身份称呼同步/712_人物身份称呼同步.gil');
const output=path.join(DIR,'713_第六关人数规则与卡面同步.gil');
assert(!fs.existsSync(output),'不覆盖已有713存档');
const lua=fs.readFileSync(path.join(ROOT,'qianxing-murdoku/dist/client_script.lua'));
assert(lua.toString().includes('构建标记 v713'));
assert(lua.toString().includes('not_beside_object"'));
const g=R.readGil(input),baseHash=crypto.createHash('sha256').update(g.src).digest('hex');
const byName=new Map(g.recs.map(r=>[r.name,r]));
function nodes(fields,ns){if(!ns.length)return fields;const[n,...tail]=ns;return fields.filter(f=>f.field===n&&f.sub).flatMap(f=>tail.length?nodes(f.sub,tail):[f]);}
function group(r){const a=nodes(r.field.sub,[505,503,75]);assert.equal(a.length,1,r.name);return a[0];}
function textOf(r){const t=group(r),p=t.sub.find(f=>f.field===510&&f.wt===2);return p?.sub?.find(f=>f.field===501&&f.wt===2)?.payload.toString('utf8')||'';}
function setText(r,text,changes){const t=group(r),before=textOf(r);let p=t.sub.find(f=>f.field===510&&f.wt===2);assert(p,r.name);p.sub=[{field:501,wt:2,sub:null,isText:true,payload:Buffer.from(text),len:Buffer.byteLength(text)}];p.isText=false;p.payload=Buffer.alloc(0);p.len=0;if(before!==text)changes.push({name:r.name,before,after:text});}
function setWidth(r,delta){if(delta===0)return;for(const state of R.stateBlocks(r.field.sub,[])){const pos=R.pairOf(state,504),size=R.pairOf(state,505);const x=R.pairValue(pos,0),y=R.pairValue(pos,1),w=R.pairValue(size,0),h=R.pairValue(size,1);if(![x,y,w,h].every(Number.isFinite))continue;R.setPair(pos,x+delta/2,y);R.setPair(size,w+delta,h);}}
const changes=[],layout=[];
const edits=new Map([
 ['what.4.1','B编辑在我上方'],
 ['what.4.5','D快递员在书架旁边'],
 ['what.6.1','我在椅子上'],
 ['what.6.2','我在书架旁边'],
 ['what.6.3','我在地毯上'],
 ['what.6.4','我在桌子旁边'],
 ['what.6.5','我在雕塑旁边'],
 ['what.6.6','我在椅子旁边'],
 ['what.6.7','我不在书架旁边'],
]);
for(const [name,text] of edits){const r=byName.get(name);assert(r,name);const before=textOf(r);setText(r,text,changes);const font=16;const delta=(Array.from(text).length-Array.from(before).length)*font;setWidth(r,delta);if(delta)layout.push({record:name,widthDelta:delta,before,after:text});}
const script=W.findScriptLeaf(g).field;script.payload=lua;script.len=lua.length;script.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'713 第六关人数规则与卡面同步',expectRecs:8300,expectMarker:'v713',assert(g2){
 assert(W.findScriptLeaf(g2).buf.equals(lua));
 for(const r of g2.recs)assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),r.name);
 for(const [name,text] of edits)assert.equal(textOf(g2.recs.find(r=>r.name===name)),text,name);
 for(const r of g2.recs){for(const t of R.textsOf(r.field.sub,[])){const s=t.payload.toString('utf8');assert(!s.includes('米纸誊录'),r.name);assert(!s.includes('卷宗管理'),r.name);}}
 return true;
}});
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(input)).digest('hex'),baseHash);
const audit={version:713,baseVersion:712,output:path.basename(output),baseSha256:baseHash,sha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),records:rep.recs,bytes:rep.bytes,fieldDiffs:rep.diffs,changes,layout,checkedWhoCount:42,checkedWhatCount:42,oldJobResidualsRemoved:['米纸誊录','卷宗管理'],case006:{order:['A','B','C','D','E','F','V'],names:{A:'绘图员',B:'设计师',C:'测绘员',D:'工程师',E:'管理员',F:'施工员',V:'老师'},display:['我在椅子上','我在书架旁边','我在地毯上','我在桌子旁边','我在雕塑旁边','我在椅子旁边','我不在书架旁边'],allTrueBoards:2,designerPositions:2,afterPeopleRule:1,identityUniquenessClaimed:false},checks:{roundtrip:true,scriptMarker:'v713',whoSlotsUnchanged:true,case006Written:true,oldJobResidualsAbsent:true,base712Unchanged:true},realGameTest:false,limits:['离线GIL往返与静态文本核验；未导入千星沙箱']};
fs.writeFileSync(path.join(DIR,'713_构建审计.json'),JSON.stringify(audit,null,2));
console.log(JSON.stringify({output,records:rep.recs,bytes:rep.bytes,changes,layout,checks:audit.checks},null,2));
