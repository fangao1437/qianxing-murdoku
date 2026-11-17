// 699：恢复695父级显隐链路；698缩略图池按652原生分组方案收进一个容器。
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..');
const R=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const W=await import(pathToFileURL(path.join(ROOT,'qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs')));
const INPUT=path.join(DIR,'../698_首页与缩略图修复/698_首页与缩略图修复.gil'),OUTPUT=path.join(DIR,'699_教程与交互修复.gil');
if(fs.existsSync(OUTPUT))throw Error('699已存在，请勿覆盖版本存档');
const g=R.readGil(INPUT),lua=fs.readFileSync(path.join(DIR,'../dist/client_script.lua'));
assert.equal(W.markerOf(lua),'v699');assert(!lua.includes(Buffer.from('_popup_gated')),'不允许沿用698递归显隐');
const root=g.recs.find(r=>r.name==='root'),proto=g.recs.find(r=>r.name==='art641.game');
const pool=g.recs.filter(r=>/^select\.card\.\d+\.(cell|wall|door)\./.test(r.name||''));assert.equal(pool.length,284);
const ids=R.asIdList(root.childList.payload,true),poolSet=new Set(pool.map(r=>r.id)),ordered=ids.filter(id=>poolSet.has(id));
const first=ids.indexOf(ordered[0]);assert.deepEqual(ids.slice(first,first+284),ordered,'池必须连续，不允许更改绘制顺序');
const before=new Map(g.recs.map(r=>[r.id,R.encodeMsg([r.field])]));const id=g.maxId+1,name='select.thumb.pool';
const field=R.cloneField(proto.field);
function remap(list,depth=0){for(const f of list){if(!(depth===0&&f.field===504)&&f.wt===0&&Number(f.num)===proto.id)f.num=BigInt(id);if(f.sub)remap(f.sub,depth+1)}}remap(field.sub);
const nf=R.textsOf(field.sub,[]).find(f=>f.payload.toString('utf8')===proto.name);assert(nf);nf.payload=Buffer.from(name);nf.len=nf.payload.length;
field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(root.id);
// 原生容器起始可见；运行时选关页面负责父级门控。自身没有图片或射线组件。
for(const b of field.sub.filter(f=>f.field===505)){const p17=b.sub?.find(f=>f.field===503)?.sub?.find(f=>f.field===14)?.sub?.find(f=>f.field===17);if(p17){p17.sub=[];p17.payload=Buffer.alloc(0);p17.len=0;p17.isText=false}}
const group={id,name,parentId:root.id,field};R.setChildList(R.ensureChildListTop(group),ordered);
for(const st of R.stateBlocks(field.sub,[])){assert.equal(R.pairValue(R.pairOf(st,504),0),0);assert.equal(R.pairValue(R.pairOf(st,504),1),0);assert.equal(R.pairValue(R.pairOf(st,505),0),1600);assert.equal(R.pairValue(R.pairOf(st,505),1),900)}
R.setChildList(root.childList,[...ids.slice(0,first),id,...ids.slice(first+284)]);
for(const r of pool)r.field.sub.find(f=>f.field===504&&f.wt===0).num=BigInt(id);
g.recHolder.push(field);
const leaf=W.findScriptLeaf(g).field;leaf.payload=lua;leaf.len=lua.length;leaf.sub=null;
fs.writeFileSync(path.join(DIR,'699_内嵌Lua_699.lua'),lua);
const rep=W.writeGil(g,OUTPUT,{label:'699 恢复695父级门控',expectRecs:g.recs.length+1,expectMarker:'v699',assert(d){
 assert(W.findScriptLeaf(d).buf.equals(lua));const rt=d.recs.find(r=>r.name==='root');const out=R.asIdList(rt.childList.payload,true);assert.equal(out.length,98);
 assert.deepEqual(out.flatMap(x=>x===id?ordered:[x]),ids);assert.deepEqual(R.asIdList(d.recs.find(r=>r.id===id).childList.payload,true),ordered);
 for(const r of d.recs){if(!before.has(r.id))continue;if(r.id===root.id||poolSet.has(r.id))continue;assert(R.encodeMsg([r.field]).equals(before.get(r.id)),'旧控件变化 '+r.name)}
 for(const r of d.recs.filter(r=>poolSet.has(r.id)))assert.equal(r.parentId,id);
 return true;
}});
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const audit={version:699,base:path.basename(INPUT),baseSha256:sha(g.src),output:path.basename(OUTPUT),sha256:sha(fs.readFileSync(OUTPUT)),records:rep.recs,rootChildren:{before:ids.length,after:98},pool:{count:284,parent:name,groupId:id},oldControls:{unchangedExceptRootAndPoolParents:true,expandedOrderIdentical:true},changes:['恢复695教程模块、入口父级显隐与遮罩绑定链路','移除698递归显隐及子层保存/恢复拦截','284个缩略图元归入1个原生容器，保留全部图元与展开顺序','修复射线扫描前200项截断，保留显式raycast=false意图','保留698负索引TTL、UTF8短名与缩略图布局'],limits:['离线测试不证明真机输入命中或帧率','695正确由用户实机反馈；父级显隐依据652/655历史优化记录']};
fs.writeFileSync(path.join(DIR,'699_构建审计.json'),JSON.stringify(audit,null,2));console.log(JSON.stringify(audit,null,2));
