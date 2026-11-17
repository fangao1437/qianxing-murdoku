import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const oldNames=[['李晨','林晓','周凯','陈宇','赵宁'],['王磊','苏晴','高远','许航','唐悦','顾宁'],['陆川','沈妍','程远','叶宁','顾晨','何川'],['韩松','林悦','宋杰','陆宁','方晓','周老师'],['梁晨','许宁','赵越','周然','沈琳','林叔'],['何明','苏禾','陈放','林涛','顾言','周宁','吴老师'],['江宁','叶青','陈墨','林浩','苏然','周叔']];
const newNames=[['保安','前台小姐','快递员','顾客','店长'],['服务员','收银员','厨师','快递员','顾客','经理'],['摄影师','导游','游客','雕刻家','清洁工','馆长'],['印刷工','编辑','装订工','快递员','校对员','老板'],['保安','值班员','鉴定师','摄影师','管理员','馆长'],['绘图员','设计师','测绘员','工程师','管理员','施工员','老师'],['管理员','读者','作家','编辑','清洁工','馆长']];
const mapping=oldNames.flatMap((list,i)=>list.map((old,j)=>({level:i+1,id:j===list.length-1?'V':String.fromCharCode(65+j),old,new:newNames[i][j]})));
const replaceMap=new Map([['夜班周凯','快递员'],...mapping.map(x=>[x.old,x.new])]);
const regex=new RegExp([...replaceMap.keys()].sort((a,b)=>b.length-a.length).join('|'),'g');
const replace=s=>s.replace(regex,x=>replaceMap.get(x));
const input=path.join(ROOT,'qianxing-murdoku/711_第六关线索去冗余修正/711_第六关线索去冗余修正.gil');
const output=path.join(DIR,'712_人物身份称呼同步.gil');assert(!fs.existsSync(output),'不覆盖已有交付');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const g=R.readGil(input),baseHash=hash(g.src),script=W.findScriptLeaf(g),oldScript=script.buf.toString('utf8');
const lua=fs.readFileSync(path.join(ROOT,'qianxing-murdoku/dist/client_script.lua'));assert.equal(W.markerOf(lua),'v712');
function modules(s){return new Map([...s.matchAll(/__M\["([^"]+)"\] = function\(\)\r?\n([\s\S]*?)(?=\r?\nend\r?\n\r?\n(?:__M\[|-- ==== 入口))/g)].map(m=>[m[1],m[2]]));}
const oldModules=modules(oldScript),newModules=modules(lua.toString());assert.equal(oldModules.size,17);assert.equal(newModules.size,17);
for(const [name,body] of oldModules)assert.equal(newModules.get(name).replace(/\r\n/g,'\n'),replace(body).replace(/\r\n/g,'\n'),'除了人物称呼不应改动模块 '+name);
function nodes(fields,ns){const [n,...tail]=ns;return fields.filter(f=>f.field===n&&f.sub).flatMap(f=>tail.length?nodes(f.sub,tail):[f]);}
function textLeaf(r){return nodes(r.field.sub,[505,503,75,510,501])[0];}
function getText(r){const group=nodes(r.field.sub,[505,503,75])[0];return group?R.textsOf([group],[]).map(f=>f.payload.toString('utf8')).join(''):'';}
const byName=new Map(g.recs.map(r=>[r.name,r]));
const changes=[],originalText=new Map(g.recs.map(r=>[r.name,getText(r)]));
const seen=new Set();
for(const r of g.recs){for(const leaf of R.textsOf(r.field.sub,[])){if(leaf===script.field||seen.has(leaf))continue;seen.add(leaf);const before=leaf.payload.toString('utf8'),after=replace(before);if(after===before)continue;assert.notEqual(before,r.name,'不得更改控件标识');leaf.payload=Buffer.from(after);leaf.len=leaf.payload.length;leaf.sub=null;changes.push({record:r.name,before,after});}}
// 教程彩色分段按字符增加量平移后续片段，左边界与字号保持不变。
const layouts=[];const groups=new Map();
for(const r of g.recs){const m=(r.name||'').match(/^(td\.l[12]\.page\.\d+\.(?:cluesay|body\.\d+))\.(\d+)$/);if(!m)continue;const a=groups.get(m[1])||[];a.push(r);groups.set(m[1],a);}
for(const [prefix,records]of groups){records.sort((a,b)=>Number(a.name.split('.').at(-1))-Number(b.name.split('.').at(-1)));let offset=0;
 for(const r of records){const before=originalText.get(r.name),after=getText(r);const tg=nodes(r.field.sub,[505,503,75])[0];const font=Number(tg?.sub.find(f=>f.field===512)?.num||16);const delta=(Array.from(after).length-Array.from(before).length)*font;
 if(offset||delta){for(const state of R.stateBlocks(r.field.sub,[])){const pos=R.pairOf(state,504),size=R.pairOf(state,505);const x=R.pairValue(pos,0),y=R.pairValue(pos,1),w=R.pairValue(size,0),h=R.pairValue(size,1);if(![x,y,w,h].every(Number.isFinite))continue;R.setPair(pos,x+offset+delta/2,y);R.setPair(size,w+delta,h);layouts.push({record:r.name,shift:offset,widthDelta:delta,width:w+delta,height:h});}}offset+=delta;}}
script.field.payload=lua;script.field.len=lua.length;script.field.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'712 常见身份称呼及教程同步',expectRecs:8300,expectMarker:'v712',assert(g2){
 assert(W.findScriptLeaf(g2).buf.equals(lua));
 for(const r of g2.recs)assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘内容 '+r.name);
 for(let i=0;i<newNames.length;i++)for(let j=0;j<newNames[i].length;j++){const r=g2.recs.find(r=>r.name===`who.${i+1}.${j+1}`);assert.equal(getText(r),newNames[i][j]);}
 for(const r of g2.recs)for(const t of R.textsOf(r.field.sub,[])){const text=t.payload.toString('utf8');for(const row of mapping)assert(!text.includes(row.old),'旧姓名残留 '+r.name+' '+row.old);}
 for(const c of changes)assert.equal(getText(g2.recs.find(r=>r.name===c.record)),c.after,'静态文本 '+c.record);
 for(let i=1;i<=4;i++){const n=`select.card.${i}.info`;assert.equal(getText(g2.recs.find(r=>r.name===n)),originalText.get(n));}
 return true;
}});
assert.equal(hash(fs.readFileSync(input)),baseHash);
const audit={version:712,baseVersion:711,output:path.basename(output),records:rep.g2.recs.length,bytes:rep.bytes,sha256:hash(fs.readFileSync(output)),baseSha256:baseHash,mapping,staticTextChanges:changes,tutorialLayoutChanges:layouts,counts:{characters:42,who:changes.filter(x=>x.record.startsWith('who.')).length,what:changes.filter(x=>x.record.startsWith('what.')).length,tutorial:changes.filter(x=>x.record.startsWith('td.')).length},checks:{roundtrip:true,oldNamesAbsent:true,all17ModulesOnlyNamesChanged:true,allWhoSlotsMatched:true,selectTitlesPreserved:true,base711Unchanged:true},realGameTest:false};
fs.writeFileSync(path.join(DIR,'712_命名同步审计.json'),JSON.stringify(audit,null,2));
console.log(JSON.stringify({output,counts:audit.counts,layoutChanges:layouts.length,checks:audit.checks}));
