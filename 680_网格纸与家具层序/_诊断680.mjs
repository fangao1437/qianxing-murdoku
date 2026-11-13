// 680 · ① 检查 679 内嵌 Lua 的 sync_art641 网格纸父坐标补丁
//        ② 列出 art657.grid.reuse 的 49 个子层（相对父偏移）
//        ③ 列出 cell 模板子控件顺序（找 X 标记与家具 obj 的层序）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, asIdList, findChildListTop } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const FILE = path.join(ROOT, 'qianxing-murdoku/679_棋盘居中与边缘/679_棋盘居中与边缘.gil');
const g = readGil(FILE);
const byId = new Map(g.recs.map(r => [r.id, r]));

// ① 内嵌 Lua
const s = findScriptLeaf(g).buf.toString('utf8');
console.log('===== ① 内嵌 Lua =====', '字节', Buffer.byteLength(s));
for (const k of ['art657.grid.reuse', 'SetAnchoredPosition(dx', '105, 46', 'sync_art641', 'help_visible(gp'])
  console.log('  ', k, '出现', s.split(k).length - 1, '次');
const i = s.indexOf('art657.grid.reuse');
if (i >= 0) console.log('--- 片段 ---\n' + s.slice(Math.max(0, i - 420), i + 420) + '\n---');

// ② art657.grid.reuse 子层
const reuse = g.recs.find(r => r.name === 'art657.grid.reuse');
const kids = g.recs.filter(r => r.parentId === reuse.id);
console.log('===== ② art657.grid.reuse 直接子层', kids.length, '=====');
const stOf = r => stateBlocks(r.field.sub, [])[0];
const geomRel = r => { const st = stOf(r); if (!st) return null;
  const p = pairOf(st, 504), z = pairOf(st, 505);
  return p && z ? [pairValue(p, 0), pairValue(p, 1), pairValue(z, 0), pairValue(z, 1)] : null; };
console.log('  父自身 504/505:', JSON.stringify(geomRel(reuse)));
for (const k of kids.slice(0, 6)) console.log('  ', k.name, JSON.stringify(geomRel(k)));
console.log('  ... 共', kids.length);

// ③ cell 模板子控件顺序
console.log('===== ③ cell 模板 / x 标记 / obj 层序 =====');
const cells = g.recs.filter(r => /^(cell|tpl\.cell|tpl-container)/.test(r.name || ''));
for (const c of cells.slice(0, 20)) {
  const cl = findChildListTop(c.field.sub);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  console.log('  ', c.name.padEnd(24), 'id=' + c.id, '父=' + (byId.get(c.parentId)?.name || c.parentId),
    '子=' + ids.length, ids.slice(0, 14).map(id => byId.get(id)?.name || '#' + id).join(','));
}
// 名字含 x / obj / furn / rug 的模板层
const tmpl = g.recs.filter(r => /^(x\.|obj|furn|rug|portrait|face|content|cell\.)/.test(r.name || ''));
console.log('  模板相关记录', tmpl.length);
for (const r of tmpl.slice(0, 40))
  console.log('   ', r.name.padEnd(26), 'id=' + r.id, '父=' + (byId.get(r.parentId)?.name || r.parentId),
    'hidden=' + isHiddenRecord(r.field), JSON.stringify(geomRel(r)));
fs.writeFileSync(path.join(DIR, '680_子层清单.json'), JSON.stringify({
  reuseSelf: geomRel(reuse), kids: kids.map(k => ({ name: k.name, id: k.id, geom: geomRel(k) })),
  tmpl: tmpl.map(r => ({ name: r.name, id: r.id, parent: byId.get(r.parentId)?.name || r.parentId, geom: geomRel(r) })),
}, null, 1));
