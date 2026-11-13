// 685 · 导出 684 内嵌 Lua 全文 + 打印所有待补丁锚点的精确片段
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const { readGil } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const g = readGil(path.join(ROOT, 'qianxing-murdoku/684_结算收紧与教程配色/684_结算收紧与教程配色.gil'));
const s = findScriptLeaf(g).buf.toString('utf8');
fs.writeFileSync(path.join(DIR, '685_内嵌Lua_684.lua'), s, 'utf8');
console.log('已导出 685_内嵌Lua_684.lua，字节', Buffer.byteLength(s));
const show = (label, needle, before = 150, after = 520) => {
  const i = s.indexOf(needle);
  console.log('\n===== ' + label + ' @ ' + i + ' =====');
  if (i < 0) { console.log('  !! 未找到'); return; }
  console.log(s.slice(Math.max(0, i - before), i + after));
};
show('furn_anchor 分支', 'key == "furn_anchor"', 200, 620);
show('x_mark 分支', 'key == "x_mark"', 200, 340);
show('enforce_layers 函数', 'function Adapter:enforce_layers', 60, 520);
show('layer_order 表', 'layer_order = {', 60, 900);
show('furn_try_all 调用', '_furn_try_all()', 500, 400);
show('cell_offset 函数', 'function Adapter:cell_offset', 60, 700);
show('cell_geometry 函数', 'function Adapter:cell_geometry', 60, 620);
show('ensure_cells 末尾 / cells_ok', 'self.cells_ok = true', 300, 500);
console.log('\n===== 所有 SetAsLastSibling 上下文 =====');
let p = -1;
while ((p = s.indexOf('SetAsLastSibling', p + 1)) >= 0) {
  console.log('  @' + p + '  ' + s.slice(Math.max(0, p - 110), p + 90).replace(/\n/g, ' | '));
}
