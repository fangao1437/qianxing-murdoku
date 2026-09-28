// tools/gil/check_children.mjs —— 列出指定控件的子控件（用来确认美术到底有没有写进存档）
//
// 用法：node tools/gil/check_children.mjs <存档.gil> [名字...]

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const file = process.argv[2] || path.join(ROOT, '完整界面7.gil');
const names = process.argv.slice(3).length
  ? process.argv.slice(3)
  : ['tool.place', 'tool.x', 'action.undo', 'action.submit', 'tray.A', 'modal.suspect.A', 'intro.next'];

const g = readGil(file);
console.log('文件：' + path.basename(file) + '  记录 ' + g.recs.length + ' 条\n');
for (const n of names) {
  const r = g.byName.get(n);
  if (!r) { console.log('  ' + n.padEnd(20) + ' **不存在**'); continue; }
  const kids = g.recs.filter((x) => x.parentId === r.id)
    .map((x) => {
      const b = x.states && x.states[0];
      let sz = '';
      if (b) {
        const p = b.sub.find((y) => y.field === 505);
        if (p && p.sub) {
          const w = (p.sub.find((y) => y.field === 501) || {}).f;
          const h = (p.sub.find((y) => y.field === 502) || {}).f;
          if (typeof w === 'number') sz = ' ' + Math.round(w) + 'x' + Math.round(h);
        }
      }
      return (x.name || '?') + sz;
    });
  console.log('  ' + n.padEnd(20) + ' 子控件 ' + kids.length + ' 个：' + (kids.join('  ') || '**（无）**'));
}
