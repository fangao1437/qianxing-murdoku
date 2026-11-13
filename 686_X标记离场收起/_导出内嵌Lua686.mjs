import fs from 'node:fs'; import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR=path.dirname(fileURLToPath(import.meta.url)), ROOT=path.resolve(DIR,'../..'), url=p=>pathToFileURL(p).href;
const {readGil}=await import(url(path.join(ROOT,'qianxing-murdoku/tools/gil/gilread.mjs')));
const {findScriptLeaf}=await import(url(path.join(ROOT,'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const g=readGil(path.join(DIR,'686_X标记离场收起.gil'));
const s=findScriptLeaf(g).buf.toString('utf8');
fs.writeFileSync(path.join(DIR,'686_内嵌Lua_686.lua'),s,'utf8');
console.log('字节',Buffer.byteLength(s));
