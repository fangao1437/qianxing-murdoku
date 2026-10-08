// tools/gil/check_names.mjs —— **对账**：脚本需要的控件名 vs 生成存档里实际有的
//
// 为什么需要这一步：Lua 脚本是按**名字**找控件的（`find` / `sub` / cfg 里的字面量）。
// 名字对不上 → 游戏里报"找不到控件"，而离线看不出来。所以导入前先对一遍账。
//
// 检查三件事：
//   ① 规划里 101 个非 cell.* 的名字，是否都在存档里；
//   ② 存档里多出来的（不算错，仅报告：原型、模板内部控件属正常）；
//   ③ cfg 点名的容器 + `tpl.cell` 的子控件（脚本运行时靠这些名字复制格子）。
//
// 用法：node tools/gil/check_names.mjs [存档.gil]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const GIL = process.argv[2] || path.join(ROOT, '完整界面.gil');
const PLAN = path.join(ROOT, 'tools', 'sim', 'out', 'layout-plan.json');

if (!fs.existsSync(GIL)) { console.error('缺存档：' + GIL); process.exit(1); }
if (!fs.existsSync(PLAN)) { console.error('缺规划：' + PLAN); process.exit(1); }

// 名字直接从存档里现算，**不要经过任何中间文件**（PowerShell 重定向会写成 UTF-16）
const gilNames = readGil(GIL).names;

const plan = JSON.parse(fs.readFileSync(PLAN, 'utf8'));
const planAll = plan.nodes.map((n) => n.id);
const planCell = planAll.filter((s) => /^cell\./.test(s));
const planKeep = planAll.filter((s) => !/^cell\./.test(s));

console.log('存档：' + path.basename(GIL));
console.log('  存档里的控件名 ' + gilNames.size + ' 个');
console.log('规划 ' + planAll.length + ' 个（其中 cell.* ' + planCell.length + ' 个由脚本运行时生成）');
console.log('  要对账的非 cell 名字 ' + planKeep.length + ' 个\n');

// ① 规划需要但存档缺失
const missing = planKeep.filter((s) => !gilNames.has(s));
console.log('① 规划需要但存档里【缺失】：' + missing.length + (missing.length ? '  ❌' : '  ✅'));
for (const s of missing) console.log('     ✗ ' + s);

// ② 存档多出来的
const extra = [...gilNames].filter((s) => !planAll.includes(s)).sort();
console.log('\n② 存档多出来的 ' + extra.length + ' 个（原型 / 模板内部控件属正常）：');
console.log('     ' + (extra.join(', ') || '（无）'));

// ③ cfg 点名 + tpl.cell 子控件
const NEED_CFG = ['root', 'board', 'tray', 'proto.btn', 'proto.text', 'tpl.cell',
  'face', 'note', 'x', 'text',
  'wall.up', 'wall.down', 'wall.left', 'wall.right',
  'door.up', 'door.down', 'door.left', 'door.right'];
console.log('\n③ cfg 点名 / 模板子控件（' + NEED_CFG.length + ' 个）：');
const bad3 = NEED_CFG.filter((s) => {
  const ok = gilNames.has(s);
  console.log('     ' + (ok ? '✅' : '❌') + ' ' + s);
  return !ok;
});

// ④ 运行时生成的格子名不该出现在存档里 —— 但 `cell.1.1` **例外**：
//    它是模板画布里的"模板根"（`tpl.cell` 引用的就是它，cfg.cells.prefab 指向它），
//    是作者手搭的，不是运行时生成的。第一版把它当误报，这里按"有没有 content 子控件"区分。
const g = readGil(GIL);
const tplRootIds = new Set(g.recs.filter((r) => /^cell\.1\.1$/.test(r.name || '')).map((r) => r.id));
const runtimeCellsInSave = [...gilNames].filter((s) => /^cell\.\d/.test(s) && s !== 'cell.1.1');
const tplOk = tplRootIds.size > 0;
console.log('\n④ 运行时格子名不该出现在存档里：' + (runtimeCellsInSave.length ? runtimeCellsInSave.join(', ') + ' ⚠️' : '无 ✅'));
console.log('   模板根 `cell.1.1`（作者手搭、`tpl.cell` 引用的那套）：' + (tplOk ? '存在 ✅ #' + [...tplRootIds].join(', #') : '不存在 ⚠️'));

const fatal = missing.length + bad3.length;
console.log('\n' + (fatal === 0
  ? '★ 对账通过：脚本需要的名字全部存在'
  : '❌ 对账失败：' + fatal + ' 个名字缺失 —— 导入后脚本会报"找不到控件"，先修这个'));
process.exit(fatal === 0 ? 0 : 2);
