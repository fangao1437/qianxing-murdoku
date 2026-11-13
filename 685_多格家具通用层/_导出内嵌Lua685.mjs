// 导出 685.gil 的内嵌 Lua，供 luac -p 语法体检
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const { readGil } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const g = readGil(path.join(DIR, '685_多格家具通用层.gil'));
const s = findScriptLeaf(g).buf.toString('utf8');
fs.writeFileSync(path.join(DIR, '685_内嵌Lua_685.lua'), s, 'utf8');
console.log('已导出，字节', Buffer.byteLength(s));
