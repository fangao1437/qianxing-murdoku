// 702：保留701记录结构和层序，只修选关内容非有限变换并替换客户端。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilread.mjs')),W=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const INPUT=DIR+'/../701_选关缩略图与关卡名修复/701_选关缩略图与关卡名修复.gil',OUTPUT=DIR+'/702_选关渲染修复_v2.gil';assert(!fs.existsSync(OUTPUT),'不覆盖已有702');
const g=R.readGil(INPUT),lua=fs.readFileSync(DIR+'/../dist/client_script.lua');assert.equal(W.markerOf(lua),'v702');const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const selected=n=>/^select\.card\.\d+\.(info|title|result)$/.test(n)||/^select\.card\.\d+\.(cell|wall|door)\./.test(n)||n==='select.thumb.pool';
const at=(f,ns)=>ns.reduce((x,n)=>x?.sub?.find(y=>y.field===n&&y.wt===2),f),changed=[],counts={controls:0,states:0,nonfinite:0};
for(const r of g.recs.filter(r=>selected(r.name))){const b=r.field.sub.find(f=>f.field===505&&f.sub?.some(x=>x.field===502&&x.num===12n));const states=at(b,[503,13,12])?.sub?.filter(x=>x.field===501).map(x=>x.sub?.find(y=>y.field===502));assert(states?.length===4,'四态变换缺失 '+r.name);let bad=0;
 for(const st of states){assert(st);const s=at(st,[501]);assert(s,'缩放缺失 '+r.name);for(const f of s.sub||[])if(f.wt===5&&!Number.isFinite(f.f))bad++;for(const k of [502,503,506])for(const f of at(st,[k])?.sub||[])if(f.wt===5&&!Number.isFinite(f.f))bad++;}
 if(!bad)continue;
 for(const st of states){const s=at(st,[501]);s.sub=[1,2,3].map(field=>({field,wt:5,f:1}));for(const k of [502,503,506]){const p=at(st,[k]);assert(p);R.setPair(p,.5,.5);}counts.states++;}
 // 图片组件 #85 的羽化等参数也继承了 NaN；逐路径取正常同类卡框的有限值。
 const comp=r.field.sub.find(f=>f.field===505&&f.sub?.some(x=>x.field===502&&x.num===97n));
 if(comp){
  const proto=g.recs.find(x=>x.name==='select.card.1');
  const ref=proto.field.sub.find(f=>f.field===505&&f.sub?.some(x=>x.field===502&&x.num===97n));
  const own=at(comp,[503,85]),good=at(ref,[503,85]);assert(own&&good);
  const repair=(f,p)=>{if(f.wt===5&&!Number.isFinite(f.f)){assert(p&&p.wt===5&&Number.isFinite(p.f),'正常图片参数没有有限对照');f.f=p.f;bad++;}for(const c of f.sub||[])repair(c,p?.sub?.find(s=>s.field===c.field&&s.wt===c.wt));};repair(own,good);
 }
 changed.push({id:r.id,name:r.name,nonfiniteBefore:bad});counts.controls++;counts.nonfinite+=bad;
}
assert.equal(changed.filter(r=>/\.(cell|wall|door)\./.test(r.name)).length,284);
const changedIds=new Set(changed.map(r=>r.id));const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const rep=W.writeGil(g,OUTPUT,{label:'702 选关非有限变换修复',expectRecs:g.recs.length,expectMarker:'v702',assert(d){assert(W.findScriptLeaf(d).buf.equals(lua));for(const r of d.recs){assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘记录偏离预期 '+r.name);if(!changedIds.has(r.id))assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'白名单外变动 '+r.name);}return true;}});
fs.writeFileSync(DIR+'/702_内嵌Lua_702_v2.lua',lua);const sha=b=>crypto.createHash('sha256').update(b).digest('hex');const audit={version:702,base:path.basename(INPUT),baseSha256:sha(g.src),output:path.basename(OUTPUT),sha256:sha(fs.readFileSync(OUTPUT)),records:rep.recs,counts,changed,unchangedOtherRecords:g.recs.length-changed.length,changes:['选关文字与图元四态缩放归一、锚点和轴心归中','运行时选关rect校正缩放并逐项回读，失败不缓存成功','保留700教程修复、701迟到补发、全部层序父链及七关行为'],limits:['695也含部分同类NaN，不能宣称全部坏值始于696','离线几何模型无法替代游戏像素验证']};fs.writeFileSync(DIR+'/702_构建审计_v2.json',JSON.stringify(audit,null,2));console.log(JSON.stringify({version:702,records:rep.recs,counts,sha256:audit.sha256}));
