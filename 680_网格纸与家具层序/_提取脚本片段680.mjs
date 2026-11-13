// 680 · 提取 679 内嵌 Lua 的 layer_order 片段，确认插入 "furn" 的锚点
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const g = readGil(path.join(ROOT, 'qianxing-murdoku/679_棋盘居中与边缘/679_棋盘居中与边缘.gil'));
const s = findScriptLeaf(g).buf.toString('utf8');
const i = s.indexOf('layer_order = {');
console.log('layer_order 起点', i);
console.log(s.slice(i, i + 1500));
console.log('\n===== 关键行出现次数 =====');
for (const k of ['"obj12",', '"portrait",', '"x",', '"furn",', 'layer_order = {'])
  console.log(k, s.split(k).length - 1);
