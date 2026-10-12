// tools/_wip/probe_ptr_calib2.mjs —— 校准坐标点击 + 查 hex.back 是否可点
//   ★ 更正：字段名是 `logs` ✗ 不是 `log`（我第一版写错 ⇒ 静默 undefined ⇒ 假结论）
import path from 'node:path';
import { makeController, loadPlan, buildProject, visibleOf, WORKSPACE, enterLevel } from '../sim/kit.mjs';

const LUA_FILE = path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();
buildProject(c, plan, LUA_FILE);

const get = async () => { const g = await c.play('get', { inspect: true }); return g.result || g; };
const tick = async (dt) => { await c.play('step', { dt }); };
const ptr = async (type, x, y) => { await c.play('pointer', { type, x, y }); };
const clickName = async (nm) => { await c.play('click', { name: nm }); };
const nLogs = async (re) => (await get()).logs.filter((l) => re.test(String(l))).length;

await c.play('start', {});
await enterLevel(c, tick);

const nOf = (id) => plan.nodes.find((x) => x.id === id);

console.log('=== 对照A：cell.1.1 按名字点（play click）===');
const a0 = await nLogs(/收到点击 → 控件 `cell\.1\.1`/);
await clickName('cell.1.1'); await tick(0.15);
const a1 = await nLogs(/收到点击 → 控件 `cell\.1\.1`/);
console.log('  点击日志 ' + a0 + ' → ' + a1 + ' ⇒ ' + (a1 > a0 ? '★ play(click) 能通' : '不通'));

console.log('\n=== 对照B：cell.1.1 改用坐标点 ===');
const c11 = nOf('cell.1.1');
await ptr('down', c11.cx, c11.cy); await tick(0.05);
await ptr('up', c11.cx, c11.cy); await tick(0.15);
const b1 = await nLogs(/收到点击 → 控件 `cell\.1\.1`/);
console.log('  点击日志 ' + a1 + ' → ' + b1 + ' ⇒ ' + (b1 > a1 ? '★ 坐标点也能通 ⇒ 坐标空间正确' : '坐标点不通'));

console.log('\n=== 结论项：hex.back ===');
const hb = nOf('hex.back');
console.log('  规划 cx=' + hb.cx + ' cy=' + hb.cy);
const h0 = await nLogs(/hex\.back|back_confirm|exit_menu/);
await ptr('down', hb.cx, hb.cy); await tick(0.06);
await ptr('up', hb.cx, hb.cy); await tick(0.2);
const h1 = await nLogs(/hex\.back|back_confirm|exit_menu/);
let r = await get();
console.log('  hex.back 相关日志 ' + h0 + ' → ' + h1);
console.log('  modal=' + visibleOf(r, 'modal') + ' modal.exit=' + visibleOf(r, 'modal.exit'));
console.log('  ⇒ ' + (visibleOf(r, 'modal') === true ? '★ hex.back 是活的（坐标点能开到弹窗）' : 'hex.back 坐标点不动'));

// 再看所有"收到点击"日志，就知道点落到了谁身上
const hits = r.logs.filter((l) => /收到点击/.test(String(l)));
console.log('\n  全部「收到点击」日志（末 6 条）：');
for (const l of hits.slice(-6)) console.log('     ' + String(l).trim().slice(0, 150));
process.exit(0);
