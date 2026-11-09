// 654：保留弹窗遮罩，修复退出状态冲突，并将拦截按钮静音。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg,cloneField} from '../tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf} from '../tools/gil/gilwrite.mjs';
const HERE=path.dirname(fileURLToPath(import.meta.url));
const INPUT=path.join(HERE,'653_全树分类优化.gil');
const OUTPUT=path.join(HERE,'654_退出拦截修复.gil');
const LUA=path.join(HERE,'654_退出拦截修复.lua');
const AUDIT=path.join(HERE,'654_退出拦截审计.json');
const REPORT=path.join(HERE,'654_退出拦截修复报告.md');
const tags=['modal','confirm','home','l1','l2'];
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const ns=(f,ks)=>ks.reduce((a,k)=>a.flatMap(x=>(x.sub||[]).filter(y=>y.field===k)),[f]);
const original=readGil(INPUT),g=readGil(INPUT);
assert.equal(hash(original.src),'2be12c5f544cb866deeeba625f2ba09ff9254ada5b542bbb3742b99875cff9ec');
const targetNames=new Set(tags.flatMap(t=>['block640.'+t,'block640.'+t+'.hit']));
const before=new Map(original.recs.map(r=>[r.id,encodeMsg([r.field])]));
const scriptBefore=findScriptLeaf(g).buf.toString('utf8');
let script=scriptBefore;
function replaceOnce(oldText,newText){assert.equal(script.split(oldText).length,2,'脚本补丁必须唯一');script=script.replace(oldText,newText);}
replaceOnce('    on_back = function()\n      controller.modal = { kind = "levelselect" }\n      controller.dirty = true\n      Murdoku.flush_effects()\n    end,',
'    on_back = function()\n      -- 654: 退出至独立选关页，不能重新打开旧式选关弹窗。\n      controller.screen = "select"\n      controller.modal = nil\n      controller.pending = nil\n      controller:sync_confirm()\n      controller.dirty = true\n      Murdoku.flush_effects()\n    end,');
replaceOnce('    if spec.tag == "modal" then want = ctrl ~= nil and ctrl.modal ~= nil',
'    if spec.tag == "modal" then\n      want = ctrl ~= nil and ctrl.modal ~= nil\n      -- 654: 兼容旧退出状态；独立选关页不启用旧式选关遮罩。\n      if want and ctrl.modal.kind == "levelselect" and (ctrl.screen == "select" or ctrl.screen == "home") then want = false end');
replaceOnce('    help_visible(panel, want)\n    if want then',
'    -- 654: 父级统一控制整树显隐，子级保持可命中，避免与射线补扫互相覆盖。\n    want = not not want\n    if hit ~= nil then\n      pcall(function() if hit.clickAudioId ~= 0 then hit.clickAudioId = 0 end end)\n    end\n    help_visible(panel, want)\n    if want then');
const scriptField=findScriptLeaf(g).field;
scriptField.payload=Buffer.from(script);scriptField.len=scriptField.payload.length;
for(const tag of tags){
 const p=g.byName.get('block640.'+tag),h=g.byName.get('block640.'+tag+'.hit');assert(p&&h);assert.equal(h.parentId,p.id);
 const flags=ns(p.field,[505,503,14,17]);assert.equal(flags.length,1);
 flags[0].sub=[...(flags[0].sub||[]).filter(f=>f.field!==503),{field:503,wt:0,num:1n}];
 const buttons=ns(h.field,[505,503,81]);assert.equal(buttons.length,1);
 const audio=buttons[0].sub.find(f=>f.field===506&&f.wt===0);assert(audio);assert.equal(audio.num,50888n);audio.num=0n;
}
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const expectedBody=encodeMsg(g.tree);
function masked(f,isHit){const c=cloneField(f);for(const p of ns(c,isHit?[505,503,81]:[505,503,14,17]))p.sub=(p.sub||[]).filter(x=>x.field!==(isHit?506:503));return encodeMsg([c]);}
const rep=writeGil(g,OUTPUT,{label:'654 保留拦截与退出修复',expectRecs:original.recs.length,expectMarker:'v635',quiet:true,assert(d){
 assert(encodeMsg(d.tree).equals(expectedBody),'输出与定向修改结果不一致');
 assert(findScriptLeaf(d).buf.equals(Buffer.from(script)),'脚本落盘不一致');
 assert(d.trailer.equals(original.trailer));
 for(const r of d.recs){assert(expected.get(r.id)?.equals(encodeMsg([r.field])),'目标输出不一致 '+r.name);
  const old=original.recs.find(x=>x.id===r.id);assert(old);
  if(!targetNames.has(r.name)){assert(before.get(r.id).equals(encodeMsg([r.field])),'非目标控件变化 '+r.name);continue;}
  assert(masked(r.field,r.name.endsWith('.hit')).equals(masked(old.field,r.name.endsWith('.hit'))),'目标美术/层级字段变化 '+r.name);
 }
 for(const tag of tags){const p=d.recs.find(r=>r.name==='block640.'+tag),h=d.recs.find(r=>r.name===p.name+'.hit');
  assert(ns(p.field,[505,503,14,17]).every(f=>f.sub.some(x=>x.field===503&&x.num===1n)));
  assert(ns(h.field,[505,503,81]).every(f=>f.sub.some(x=>x.field===506&&x.num===0n)));
 }
 return true;
}});
fs.writeFileSync(LUA,findScriptLeaf(rep.g2).buf);
const audit={base:path.basename(INPUT),inputSha256:hash(original.src),output:path.basename(OUTPUT),outputSha256:hash(rep.g2.src),inputBytes:original.src.length,outputBytes:rep.bytes,recordsBefore:original.recs.length,recordsAfter:rep.g2.recs.length,retainedBlockers:tags.map(t=>'block640.'+t),removedRecords:0,changedControlRecords:10,nonTargetRecordsUnchanged:original.recs.length-10,scriptBytesBefore:Buffer.byteLength(scriptBefore),scriptBytesAfter:Buffer.byteLength(script),cause:'exit_menu_go 清空 modal 并切到 select 后，on_back 回调又设置 modal.kind=levelselect，导致 block640.modal 持续启用。',fixes:['on_back 统一进入独立选关页并清空 modal/pending','5组拦截父级默认隐藏，保留子级显示与几何层级','5个拦截按钮音效ID设为0','父级统一控制整树显隐，保留原有射线补扫和置顶顺序'],checks:{diskReread:true,roundtrip:true,expectedBodyExact:true,recordIdsUnchanged:true,nonTargetRecordsByteIdentical:true,targetArtGeometryHierarchyUnchanged:true,trailerUnchanged:true},limitation:'离线回归不替代实机点击命中、听感及视觉验收；0音效ID需实机确认静音。'};
fs.writeFileSync(AUDIT,JSON.stringify(audit,null,2));
fs.writeFileSync(REPORT,['# 654 退出拦截修复（保留弹窗遮罩）','','基于653。保留全部5组block640遮罩及10个控件，不删除拦截功能。','','## 原因','','退出动作先进入独立选关页并清空modal，但on_back回调紧接着设置旧式levelselect弹窗。sync_block640因此仍将全屏遮罩置为显示；这与退出日志中modal.level.case_004缺失同时出现。此前“653未引用block640”的判断已由源码证据纠正。','','## 修改','','- 退出回调统一进入select，清空modal和pending。','- 5组遮罩父级默认隐藏，子级默认显示保持不变，由父级整树门控。','- 保留原有弹窗、确认条、首页教程、第一关教程、第二关教程的遮罩开启条件与前后层序；旧式levelselect在独立选关/首页不启用遮罩。','- 5个拦截按钮音效ID从50888改为0；运行时再次确保为0。','- 父级显隐统一控制整树，子级射线与交互逻辑保持原样，避免与射线补扫互相覆盖。真实操作按钮音效未修改。','','## 结构校验','',`- 控件数量：${original.recs.length} → ${rep.g2.recs.length}，删除0个。`,`- 存档大小：${original.src.length} → ${rep.bytes}字节。`,`- ${original.recs.length-10}个非目标控件逐字节不变，10个目标控件除初始隐藏/音效外字段不变。`,'- 根列表、父子关系、几何、美术、原层序保持不变。','- 磁盘重读、往返编码、完整预期结果对比通过。','','## 验证边界','','尚未在游戏中实机验收。导入后重点验证退出→选关→其它关卡，以及弹窗/确认条/教程开启时背景不能点、前景按钮可用、关闭后背景恢复、拦截层空白处无点击音。','','SHA256：'+audit.outputSha256,''].join('\n'));
console.log(JSON.stringify(audit,null,2));
