// 从664直接构建；不读取665的文本、规则或脚本。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg} from '../../qianxing-murdoku-tool/project-tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf,markerOf} from '../../qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url));
const base=path.resolve(dir,'../657_关卡内UI/664_关卡内UI.gil');
const output=path.join(dir,'666_线索换位.gil');
if(fs.existsSync(output))throw Error('输出已存在，禁止覆盖');
const g=readGil(base),baseScript=findScriptLeaf(g).buf.toString('utf8');
const maps={1:[3,5,4,2,1],2:[3,1,2,4,5,6]}; // 新槽位 -> 664旧槽位
const ns=(f,ks)=>ks.reduce((a,k)=>a.flatMap(x=>(x.sub||[]).filter(y=>y.field===k)),[f]);
const tn=r=>ns(r.field,[505,503,75,510,501])[0];
const originals=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const textOriginals=new Map(g.recs.filter(tn).map(r=>[r.id,tn(r).payload.toString('utf8')]));
const edits=[];
function setText(r,t){const f=tn(r);if(!f)throw Error('非文本 '+r.name);const old=f.payload.toString('utf8');if(t===old)return;f.payload=Buffer.from(t);f.len=f.payload.length;f.sub=null;edits.push({id:r.id,name:r.name,old,text:t});}
function R(n){const rs=g.recs.filter(r=>r.name===n);if(rs.length!==1)throw Error('名称不唯一 '+n);return rs[0];}
function set(n,t){setText(R(n),t);}
function chair(s){return s.replace(/站在(\s*)椅子/g,'坐在$1椅子');}
// 只移动正文；卡槽人物、字母、头像、父子结构不动。
for(const [lv,map]of Object.entries(maps))for(let i=0;i<map.length;i++)set(`what.${lv}.${i+1}`,chair(textOriginals.get(R(`what.${lv}.${map[i]}`).id)));
for(const r of g.recs){const f=tn(r);if(f)setText(r,chair(f.payload.toString('utf8')));}
const tutorial={
 'td.l1.page.2.caption':'•  选中 V，第 5 列亮起',
 'td.l1.page.2.clueface':'V',
 'td.l1.page.2.cluename':'卡 5 · 收藏家（V）',
 'td.l1.page.4.body.0.0':'卡 1 是保安提供的线索：「只有值班保安站在地毯上」。',
 'td.l1.page.4.clueface':'A',
 'td.l1.page.4.cluename':'卡 1 · 值班保安（A）',
 'td.l1.page.5.body.0.0':'卡 2：「前台姑娘在桌子旁边」→ (2,2) 和 (3,1)。',
 'td.l1.page.5.body.1.0':'但 (3,1) 是地毯，站上去就和卡 1「只有值班保安在地毯上」冲突，',
 'td.l1.page.5.clueface':'B',
 'td.l1.page.5.cluename':'卡 2 · 前台姑娘（B）；卡 1 · 值班保安（A）',
 'td.l1.page.6.body.0.0':'卡 3 是清洁工提供的线索：「夜班清洁工坐在椅子上」。',
 'td.l1.page.6.clueface':'C',
 'td.l1.page.6.cluename':'卡 3 · 夜班清洁工（C）',
 'td.l1.page.6.cluesay.0':'「夜班清洁工 坐在 ',
 'td.l2.page.3.caption':'假设 c、e 为真：E? 为局部候选，须再排除',
 'td.l2.page.3.lgt.0':'假设 c、d、e 真',
 'td.l2.page.3.lgt.1':'c：两椅有人',
 'td.l2.page.4.rewrite617.3':'易得线索 c、d、e 无法同时成立，故其中必有假线索，'
};
for(const [n,t]of Object.entries(tutorial))set(n,t);
// 在原始内嵌脚本上仅置换两段clues，保留其它所有关卡字段。
let script=baseScript;
for(const [lv,map]of Object.entries(maps)){
 const tag=`__M["levels.case_00${lv}"] = function()`;
 const start=script.indexOf(tag),end=script.indexOf('\n__M[',start+tag.length);
 if(start<0||end<0)throw Error('缺少模块 '+tag);
 const segment=script.slice(start,end);
 const hit=segment.match(/(  clues = \{\r?\n)([\s\S]*?)(  \},)/);
 if(!hit)throw Error('缺少线索表');
 const lines=hit[2].match(/[^\n]*\n/g)||[];
 if(lines.length!==map.length||lines.some(x=>!/^\s*\{ type = /.test(x)))throw Error('线索格式变化');
 const replacement=hit[1]+map.map(i=>lines[i-1]).join('')+hit[3];
 script=script.slice(0,start)+segment.replace(hit[0],replacement)+script.slice(end);
}
// 引擎自动文本针对椅子使用坐姿，不影响on_object验证条件或其它家具措辞。
const chairOld='text = function(ctx, cl) return string.format("%s 站在 %s 上", ctx.name(cl.who), cl.object) end,';
const chairNew='text = function(ctx, cl) return string.format(cl.object == "椅子" and "%s 坐在 %s 上" or "%s 站在 %s 上", ctx.name(cl.who), cl.object) end,';
if(script.split(chairOld).length!==2)throw Error('椅子文本入口不唯一');
script=script.replace(chairOld,chairNew);
const scriptBuf=Buffer.from(script);fs.writeFileSync(path.join(dir,'client_script.lua'),scriptBuf);
const leaf=findScriptLeaf(g).field;leaf.payload=scriptBuf;leaf.len=scriptBuf.length;leaf.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const changed=new Set(edits.map(x=>x.id));
for(const r of g.recs)if(!changed.has(r.id)&&!originals.get(r.id).equals(expected.get(r.id)))throw Error('非目标记录变动 '+r.name);
const rep=writeGil(g,output,{label:'666：664原文线索换位',quiet:true,expectRecs:6976,expectDiffs:changed.size+1,expectMarker:markerOf(baseScript),assert(g2){
 if(!findScriptLeaf(g2).buf.equals(scriptBuf))return '脚本不匹配';
 for(const r of g2.recs)if(!encodeMsg([r.field]).equals(expected.get(r.id)))return '记录不匹配 '+r.name;
 return true;
}});
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const audit={base:'664',discarded:'665（未读取）',output:'666',maps,records:rep.g2.recs.length,changedTextRecords:changed.size,fieldDifferences:rep.diffs,unchangedRecords:6976-changed.size,geometryAndParentListsUnchanged:true,roundtrip:true,embeddedScriptMatches:true,baseSha256:sha(base),outputSha256:sha(output),edits};
fs.writeFileSync(path.join(dir,'666_构建审计.json'),JSON.stringify(audit,null,2));
console.log(JSON.stringify({...audit,edits:undefined},null,2));
