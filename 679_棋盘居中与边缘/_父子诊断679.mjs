// 679 · 打印棋盘相关层的父子关系，找可整体平移的父容器
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const g = readGil(path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口/678_注释卡真缺口.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));
const names = ['board.bg', 'board.floors', 'board.rugs', 'art641.game.boardframe.paper',
  'art641.game.boardframe.shadow', 'art641.game.boardbottom', 'art656.home.grid.paper',
  'art657.grid.reuse', 'art656.home.paper.edge', 'grp653.static.1.art641.game', 'board'];
for (const n of names) {
  const r = g.recs.find(q => q.name === n);
  if (!r) { console.log(n.padEnd(36), '缺失'); continue; }
  const chain = []; let cur = r, d = 0;
  while (cur && d++ < 8) { chain.push(cur.name || '#' + cur.id); cur = cur.parentId ? byId.get(cur.parentId) : null; }
  const kids = g.recs.filter(q => q.parentId === r.id);
  console.log(n.padEnd(36), 'id=' + r.id, '父链:', chain.join(' ← '), '| 直接子层', kids.length,
    kids.length ? '例:' + kids.slice(0, 5).map(k => k.name).join(',') : '');
}
// 所有名字含 cell 的可见层（运行时模板？）
const cells = g.recs.filter(r => /cell/.test(r.name || ''));
console.log('\n名字含 cell 的记录', cells.length, '例:', cells.slice(0, 12).map(r => r.name + '(父=' + (byId.get(r.parentId)?.name || r.parentId) + ')').join(' | '));
