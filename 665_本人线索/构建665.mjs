import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readGil,encodeMsg} from '../tools/gil/gilread.mjs';
import {writeGil,findScriptLeaf} from '../tools/gil/gilwrite.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url));
const input=path.join(dir,'../657_关卡内UI/664_关卡内UI.gil'),output=path.join(dir,'665_本人线索.gil');
if(fs.existsSync(output))throw Error('output exists');
const data=JSON.parse(fs.readFileSync(path.join(dir,'线索设计665.json'),'utf8'));
const patch=JSON.parse(fs.readFileSync(path.join(dir,'教学文字665.json'),'utf8'));
const g=readGil(input),before=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])])),changed=new Set(),texts=[];
const ns=(f,ks)=>ks.reduce((a,k)=>a.flatMap(x=>(x.sub||[]).filter(y=>y.field===k)),[f]);
const tn=r=>ns(r.field,[505,503,75,510,501])[0];
function text(r,t){const f=tn(r);if(!f)throw Error('missing text '+r.name);const old=f.payload.toString('utf8');if(old===t)return;f.payload=Buffer.from(t);f.len=f.payload.length;f.sub=null;changed.add(r.id);texts.push({name:r.name,old,text:t});}
for(let l=1;l<=4;l++)for(let i=1;i<=data[l-1].texts.length;i++){
 const rr=g.recs.filter(r=>r.name===`what.${l}.${i}`);if(rr.length!==1)throw Error('ambiguous card');text(rr[0],data[l-1].texts[i-1]);
 const speaker=data[l-1].cards[i-1].speaker; // speaker metadata is asserted by Lua separately
}
for(const [name,t]of Object.entries(patch)){const rows=g.recs.filter(r=>r.name===name);if(!rows.length)throw Error('missing tutorial '+name);for(const r of rows)text(r,t);}
const script=fs.readFileSync(path.join(dir,'client_script.lua'));const leaf=findScriptLeaf(g).field;leaf.payload=script;leaf.len=script.length;leaf.sub=null;
const expected=new Map(g.recs.map(r=>[r.id,encodeMsg([r.field])]));
const rep=writeGil(g,output,{quiet:true,label:'665 self clues',expectRecs:g.recs.length,assert(g2){if(!findScriptLeaf(g2).buf.equals(script))return 'script mismatch';for(const r of g2.recs)if(!encodeMsg([r.field]).equals(expected.get(r.id)))return 'record mismatch '+r.name;return true;}});
const untouched=g.recs.filter(r=>!changed.has(r.id));for(const r of untouched)if(!before.get(r.id).equals(expected.get(r.id)))throw Error('unrelated change '+r.name);
const audit={base:'664',output:'665',records:rep.g2.recs.length,changedTextRecords:changed.size,unchangedRecords:untouched.length,geometryAndParentListsUnchanged:true,embeddedScriptMatches:true,roundtrip:true,sha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'),texts};
fs.writeFileSync(path.join(dir,'665_构建审计.json'),JSON.stringify(audit,null,2));console.log(JSON.stringify({...audit,texts:undefined}));
