import fs from 'node:fs'; import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url)); const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const { readGil, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } = await import(url(path.join(ROOT,'qianxing-murdoku/tools/gil/gilread.mjs')));
const { isHiddenRecord } = await import(url(path.join(ROOT,'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const g = readGil(path.join(ROOT,'qianxing-murdoku/684_结算收紧与教程配色/684_结算收紧与教程配色.gil'));
const byId = new Map(g.recs.map(r=>[r.id,r]));
const kids = r => { const cl = findChildListTop(r.field.sub||[]); return cl ? (asIdList(cl.payload,true)||[]).map(i=>byId.get(i)).filter(Boolean) : []; };
const geom = r => { const st=stateBlocks(r.field.sub,[])[0]; if(!st) return null; const p=pairOf(st,504),z=pairOf(st,505);
 return {pos:p?[pairValue(p,0),pairValue(p,1)]:null,size:z?[pairValue(z,0),pairValue(z,1)]:null}; };
console.log('===== id 1073741844 =====');
const p=byId.get(1073741844);
console.log(p ? [p.name,p.parentId,byId.get(p.parentId)?.name,JSON.stringify(geom(p)),'hidden='+isHiddenRecord(p.field),'子='+kids(p).length].join(' | ') : '记录不存在（模板画布或未导出节点）');
if (p) console.log('  子名:', kids(p).slice(0,50).map(k=>k.name).join(', '));
console.log('\n===== root 记录 =====');
const root=g.recs.find(r=>r.name==='root'); console.log('root id',root?.id,'父',root?.parentId,JSON.stringify(geom(root)),'子='+ (root?kids(root).length:0));
if(root) console.log('  子名(全部/前80):', kids(root).slice(0,80).map(k=>k.name).join(', '));
console.log('\n===== 所有 cell.r.c 记录的父分布 =====');
const m=new Map(); for(const r of g.recs){ if(/^cell\.\d+\.\d+$/.test(r.name||'')){const k=byId.get(r.parentId)?.name||String(r.parentId); m.set(k,(m.get(k)||0)+1);} }
console.log([...m.entries()]);
console.log('\n===== 名字含 board / cells / root / stage 的容器 =====');
for(const r of g.recs) if(/^(board|cells|root|stage|content|fart)/.test(r.name||'') && kids(r).length>0)
  console.log(' ',r.name.padEnd(28),'id='+r.id,'父='+ (byId.get(r.parentId)?.name||r.parentId),'子='+kids(r).length, JSON.stringify(geom(r)), 'hidden='+isHiddenRecord(r.field));
console.log('\n===== 候选：所有子数 >= 20 的记录 =====');
for(const r of g.recs){ const n=kids(r).length; if(n>=20) console.log(' ',r.name.padEnd(30),'id='+r.id,'父='+(byId.get(r.parentId)?.name||r.parentId),'子='+n); }
