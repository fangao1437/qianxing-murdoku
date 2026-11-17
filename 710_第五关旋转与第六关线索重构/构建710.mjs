// 710：基于709，先由设计层生成最新客户端脚本，再更新第5/6关卡面与版本标记。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const input=path.join(ROOT,'qianxing-murdoku/709_第四关双线索重构/709_第四关双线索重构.gil');
const output=path.join(DIR,'710_第五关旋转与第六关线索重构.gil');
assert(!fs.existsSync(output),'不覆盖已有710交付');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const designDir=path.join(ROOT,'murdoku-project/第三四关内容设计');
const designs=JSON.parse(fs.readFileSync(path.join(designDir,'current_design_v16.json'),'utf8'));
const report=JSON.parse(fs.readFileSync(path.join(designDir,'verification_v16.json'),'utf8'));
assert(designs.every(d=>d.save_revision===710),'设计数据未统一到710');
assert(report.length===5 && report.every(x=>x.PASS),'第3至7关离线验收未全通过');
const d5=designs.find(x=>x.level===5),d6=designs.find(x=>x.level===6);
assert.deepEqual(d5.target,[1,23,8,34,27,12],'第5关未使用180°设计结果');
assert.deepEqual(d6.cards,[['E在雕塑旁边'],['F在椅子旁边'],['D在桌子旁边'],['B在书架旁边'],['A在椅子上'],['C在地毯上'],['E不在植物旁边']]);
assert(d6.cards.every(c=>c.length===1),'第6关不是全部单句卡');
const lua=fs.readFileSync(path.join(ROOT,'qianxing-murdoku/dist/client_script.lua'));
assert(lua.toString('utf8').includes('710'),'客户端脚本缺少710标记');
function modules(s){const result=new Map();const re=/__M\["([^"]+)"\] = function\(\)\r?\n([\s\S]*?)(?=\r?\nend\r?\n\r?\n(?:__M\[|-- ==== 入口))/g;for(const hit of s.matchAll(re))result.set(hit[1],hit[2]);return result;}
const g=R.readGil(input),before=W.findScriptLeaf(g).buf.toString('utf8'),beforeModules=modules(before),afterModules=modules(lua.toString('utf8'));
assert.equal(beforeModules.size,17);assert.equal(afterModules.size,17);
const changedModules=[...beforeModules.keys()].filter(k=>beforeModules.get(k)!==afterModules.get(k));
assert(changedModules.includes('levels.case_005')&&changedModules.includes('levels.case_006')&&changedModules.includes('ui_controller'));
function setText(name,text){const r=g.recs.find(r=>r.name===name);assert(r,name);const leaves=R.textsOf(r.field.sub,[]).filter(f=>f.payload.toString('utf8')!==name);assert.equal(leaves.length,1,'文本叶子不唯一 '+name);const f=leaves[0];const old=f.payload.toString('utf8');if(old!==text){f.payload=Buffer.from(text);f.len=f.payload.length;f.sub=null;return {id:r.id,name,before:old,after:text};}return null;}
const changed=[];
for(let i=0;i<d5.display_cards.length;i++){const x=setText(`what.5.${i+1}`,d5.display_cards[i].join('、'));if(x)changed.push(x);}
for(let i=0;i<d6.display_cards.length;i++){const x=setText(`what.6.${i+1}`,d6.display_cards[i].join('、'));if(x)changed.push(x);}
// 人物姓名由最新客户端脚本按当前关卡 vm.tray/vm.clues 运行时生成；row.* 只是容器记录，不强行改写。
const script=W.findScriptLeaf(g).field;script.payload=lua;script.len=lua.length;script.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const rep=W.writeGil(g,output,{label:'710 第5关设计180°旋转与第6关全单句线索重构',expectRecs:8300,expectDiffs:changed.length+1,expectMarker:'v710',assert(g2){assert(W.findScriptLeaf(g2).buf.equals(lua));for(const r of g2.recs)assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘记录不符 '+r.name);return true;}});
const audit={version:710,baseVersion:709,input:path.basename(input),output:path.basename(output),sha256:hash(fs.readFileSync(output)),bytes:rep.bytes,records:rep.recs,fieldDiffs:rep.diffs,changedStaticRecords:changed,embeddedLuaMarker:rep.marker,changedModules,roundtrip:true,verification:'710_验证结果.json',designReport:'710_第3至7关难度对比.json',level5DesignRotation:{method:'先旋转设计数据，再生成Lua与存档',target:d5.target,objects:d5.objects,walls:d5.walls,doors:d5.doors},level6Cards:d6.display_cards,selectNameFix:'UI优先使用当前levels.ui_list关卡名',dailyNameFix:'UI优先使用当前vm.tray/vm.clues姓名',realGameTest:false};
fs.writeFileSync(path.join(DIR,'710_构建审计.json'),JSON.stringify(audit,null,2),'utf8');
fs.writeFileSync(path.join(DIR,'710_验证结果.json'),JSON.stringify({PASS:true,version:710,baseVersion:709,designVerification:report,build:audit},null,2),'utf8');
console.log(JSON.stringify(audit,null,2));
