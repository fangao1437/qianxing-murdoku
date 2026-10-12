// tools/_wip/probe_lp.mjs —— 长按探针自检：引擎到底有没有派发 CursorDown / CursorUp
//   ★ 别用 play('click',{name})（那是 SimulateCursorClick，走预设按钮那条路）
//   ★ 用 play('pointer') 直达坐标 ⇒ 这才是真机的手指路径

import path from 'node:path';
import { makeController, loadPlan, buildProject, WORKSPACE, enterLevel } from '../sim/kit.mjs';

const LUA_FILE = path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();
buildProject(c, plan, LUA_FILE);

const get = async () => { const g = await c.play('get', { inspect: true }); return g.result || g; };
const tick = async (dt) => { await c.play('step', { dt }); };
const ptr = async (type, x, y) => { await c.play('pointer', { type, x, y }); };

await c.play('start', {});
await enterLevel(c, tick);

// 取 cell.1.3 的画布绝对中心
const paint = (await c.play('get', { paint: true })).paint || [];
const p = paint.find((x) => x.name === 'cell.1.3');
console.log('cell.1.3 画布中心 = ' + (p ? JSON.stringify({ x: p.matrix.tx, y: p.matrix.ty }) : '(取不到)'));
if (!p) { process.exit(2); }
const X = p.matrix.tx, Y = p.matrix.ty;

const lpLines = async () => (await get()).logs.filter((l) => /长按探针/.test(String(l)));

console.log('\n=== 按下 → 停 0.4 秒（跨过 0.28 阈值）→ 抬起 ===');
await ptr('down', X, Y); await tick(0.05);
let r = await get();
console.log('  按下后 长按探针条数 = ' + (await lpLines()).length);
await tick(0.40);
await ptr('up', X, Y); await tick(0.15);
r = await get();

console.log('\n--- 长按探针日志 ---');
for (const l of await lpLines()) console.log('  ' + String(l).trim().slice(0, 190));
console.log('\n--- 全仓里与长按/放置有关的日志 ---');
for (const l of r.logs.filter((l) => /长按|放置分辨|抬起|pre_place|hold_cell|_press/.test(String(l)))) {
  console.log('  ' + String(l).trim().slice(0, 190));
}
process.exit(0);
