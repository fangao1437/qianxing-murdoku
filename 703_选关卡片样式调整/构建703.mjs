// 703：以702_v2为输入，完整矩形图元 + 四块独立棋盘背景，原档保留。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilread.mjs'));
const W=await import(pathToFileURL(ROOT+'/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const INPUT=DIR+'/../702_选关渲染修复/702_选关渲染修复_v2.gil',OUTPUT=DIR+'/703_选关卡片样式调整.gil';
assert(!fs.existsSync(OUTPUT),'不覆盖已有703存档');
const g=R.readGil(INPUT),lua=fs.readFileSync(DIR+'/../dist/client_script.lua');assert.equal(W.markerOf(lua),'v703');
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const at=(f,ns)=>ns.reduce((x,n)=>x?.sub?.find(y=>y.field===n&&y.wt===2),f);
const image=r=>at(r.field.sub.find(f=>f.field===505&&f.sub?.some(x=>x.field===502&&x.num===96n)),[503,84]);
const pool=g.recs.find(r=>r.name==='select.thumb.pool');assert(pool?.childList);
const nodes=g.recs.filter(r=>/^select\.card\.\d+\.(cell|wall|door)\./.test(r.name));assert.equal(nodes.length,284);
for(const r of nodes){const f=image(r)?.sub?.find(f=>f.field===503&&f.wt===0);assert(f);f.num=100001n;}
const proto=g.recs.find(r=>r.name==='select.card.1.cell.1.1'),bg=g.recs.find(r=>r.name==='board.bg');
const dark=image(bg).sub.find(f=>f.field===502&&f.wt===0).num;assert.equal(dark,4281871675n);
const old=R.asIdList(pool.childList.payload,true),added=[];let max=g.maxId;
for(let i=1;i<=4;i++){
 const id=++max,name='select.card.'+i+'.boardbg',field=R.cloneField(proto.field);
 function remap(fs,depth=0){for(const f of fs){if(!(depth===0&&f.field===504)&&f.wt===0&&Number(f.num)===proto.id)f.num=BigInt(id);if(f.sub)remap(f.sub,depth+1);}}
 remap(field.sub);
 const n=R.textsOf(field.sub,[]).find(f=>f.payload.toString('utf8')===proto.name);assert(n);n.payload=Buffer.from(name);n.len=n.payload.length;
 field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(pool.id);
 const c=image({field}).sub.find(f=>f.field===502&&f.wt===0);assert(c);c.num=dark;
 g.recHolder.push(field);added.push({id,name});
}
R.setChildList(pool.childList,[...added.map(r=>r.id),...old]);
const allowed=new Set([pool.id,...nodes.map(r=>r.id)]);
const expected=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
const rep=W.writeGil(g,OUTPUT,{label:'703 选关纯色矩形、居中棋盘与底部案件标题',expectRecs:g.recs.length+4,expectMarker:'v703',assert(d){
 assert(W.findScriptLeaf(d).buf.equals(lua));
 for(const r of d.recs){if(!before.has(r.id))continue;assert(R.encodeMsg([r.field]).equals(expected.get(r.id)),'落盘字段不一致 '+r.name);if(!allowed.has(r.id))assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'白名单外改动 '+r.name);}
 const pp=d.recs.find(r=>r.id===pool.id);assert.deepEqual(R.asIdList(pp.childList.payload,true),[...added.map(r=>r.id),...old]);
 for(const a of added){const r=d.recs.find(r=>r.id===a.id);assert.equal(r.name,a.name);assert.equal(r.parentId,pool.id);assert.equal(image(r).sub.find(f=>f.field===503).num,100001n);}
 return true;
}});
fs.writeFileSync(DIR+'/703_内嵌Lua_703.lua',lua);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const audit={version:703,input:path.basename(INPUT),inputSha256:sha(g.src),output:path.basename(OUTPUT),sha256:sha(fs.readFileSync(OUTPUT)),records:rep.recs,added,changedExisting:allowed.size,unchangedExisting:g.recs.length-allowed.size,gridImage:100001,backgroundColor:Number(dark),notes:['格子使用cell模板的完整矩形资源100001','四块底板在缩略图池最前，沿用board.bg颜色','棋盘几何中心与卡片中心重合，底板每边比棋盘大卡宽2.2%','下方白边显示完整案件编号与名称，顶部规格隐藏','保留702_v2有限变换、700教程绑定与701迟到补发修复']};
fs.writeFileSync(DIR+'/703_构建审计.json',JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
