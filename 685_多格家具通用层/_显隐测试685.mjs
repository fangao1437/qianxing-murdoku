import path from 'node:path'; import {fileURLToPath,pathToFileURL} from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(DIR,'../..'),url=p=>pathToFileURL(p).href;
const {readGil,cloneField}=await import(url(path.join(ROOT,'qianxing-murdoku/tools/gil/gilread.mjs')));
const {isHiddenRecord,setHiddenRecord}=await import(url(path.join(ROOT,'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const g=readGil(path.join(ROOT,'qianxing-murdoku/684_结算收紧与教程配色/684_结算收紧与教程配色.gil'));
const byId=new Map(g.recs.map(r=>[r.id,r]));
const x=g.recs.find(r=>r.name==='x'&&byId.get(r.parentId)?.name==='content');
const s0=g.recs.find(r=>r.name==='x.stroke.0');
for(const [tag,r] of [['x',x],['stroke.0',s0]]){
  const f=cloneField(r.field);
  try{ setHiddenRecord(f,true); console.log(tag,'setHidden OK, isHidden=',isHiddenRecord(f)); }
  catch(e){ console.log(tag,'setHidden FAIL:',e.message); }
}
