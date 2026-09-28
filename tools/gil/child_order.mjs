// tools/gil/child_order.mjs —— 打印某控件的**子控件列表顺序**（决定编辑器里的显示顺序/层级）
//
// 起因（2026-09-27）：用户截图里 `topbar` 的子节点显示顺序是**倒的**
// （规划里是 hud.title→hud.subtitle→…→action.reveal，编辑器里看到的是 action.reveal→…→hud.title）。
// 在【层级渲染(新)】模式下节点顺序 = 渲染顺序，所以顺序错了**会盖错**。
//
// 用法：
//   node tools/gil/child_order.mjs <存档.gil>                 # 只看 root / topbar
//   node tools/gil/child_order.mjs <存档.gil> <名字> [...]     # 看指定控件

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, asIdList } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const file = process.argv[2] || path.join(ROOT, '完整界面2.gil');
const targets = process.argv.slice(3).length ? process.argv.slice(3) : ['root', 'topbar'];

const g = readGil(file);
const byId = new Map(g.recs.map((r) => [r.id, r]));
console.log('文件：' + path.basename(file) + '（' + g.recs.length + ' 条记录）\n');

for (const t of targets) {
  const r = g.byName.get(t);
  if (!r) { console.log('[' + t + '] 找不到'); continue; }
  const ids = asIdList(r.childList ? r.childList.payload : Buffer.alloc(0), true) || [];
  console.log('[' + t + '] #' + r.id + '  子列表 ' + ids.length + ' 个（这就是编辑器里的显示顺序）：');
  if (!ids.length) { console.log('   （空）\n'); continue; }
  ids.forEach((i, k) => {
    const c = byId.get(i);
    console.log('   ' + String(k + 1).padStart(2) + '. ' + String(c ? c.name : '#' + i));
  });
  console.log('');
}
