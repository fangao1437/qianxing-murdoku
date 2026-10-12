// tools/_wip/probe_ptr_calib.mjs —— 校准：坐标点击到底能不能通？
//   对照组：cell.1.1（已知 play('click') 能通）+ hex.back（疑似点不动）

import path from 'node:path';
import { makeController, loadPlan, buildProject, visibleOf, WORKSPACE, enterLevel } from '../sim/kit.mjs';

const LUA_FILE = path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();
buildProject(c, plan, LUA_FILE);

const get = async () => { const g = await c.play('get', { inspect: true }); return g && g.result ? g.result : g; };
const tick = async (dt) => { await c.play('step', { dt }); };
const ptr = async (type, x, y) => { await c.play('pointer', { type, x, y }); };
const clickName = async (nm) => { await c.play('click', { name: nm }); };

await c.play('start', {});
await enterLevel(c, tick);

const nOf = (id) => plan.nodes.find((x) => x.id === id);
for (const id of ['cell.1.1', 'hex.back', 'home.select', 'select.back']) {
  const n = nOf(id);
  console.log(id + ' => ' + (n ? JSON.stringify({ cx: n.cx, cy: n.cy, w: n.w, h: n.h }) : '(不在规划里)'));
}

// 对照 A：cell.1.1 用 play('click') 已知能通
console.log('\n=== 对照A：cell.1.1 按名字点 ===');
await clickName('cell.1.1'); await tick(0.15);
let r = await get();
let hits = (r.log || []).filter((l) => /收到点击 → 控件 `cell\.1\.1`/.test(String(l)));
console.log('  收到点击日志 ' + hits.length + ' 条 ⇒ ' + (hits.length > 0 ? '★ play(click) 能通' : '不通'));

// 对照 B：同一个 cell.1.1 改用坐标点
const c11 = nOf('cell.1.1');
console.log('\n=== 对照B：cell.1.1 用坐标点 (' + c11.cx + ',' + c11.cy + ') ===');
const before = (await get()).log.length;
await ptr('down', c11.cx, c11.cy); await tick(0.05);
await ptr('up', c11.cx, c11.cy); await tick(0.15);
r = await get();
const after = (r.log || []).filter((l) => /收到点击 → 控件 `cell\.1\.1`/.test(String(l)));
console.log('  累计收到点击日志 ' + after.length + ' 条（之前 ' + hits.length + '）⇒ '
  + (after.length > hits.length ? '★ 坐标点能通 ⇒ 坐标空间正确' : '坐标点不通 ⇒ 坐标空间有问题'));

// 然后才敢下结论：hex.back
const hb = nOf('hex.back');
console.log('\n=== 结论项：hex.back 用坐标点 (' + hb.cx + ',' + hb.cy + ') ===');
await ptr('down', hb.cx, hb.cy); await tick(0.05);
await ptr('up', hb.cx, hb.cy); await tick(0.2);
r = await get();
const hbLogs = (r.log || []).filter((l) => /hex\.back|back_confirm|收到点击/.test(String(l)));
for (const l of hbLogs.slice(-6)) console.log('     log: ' + String(l).trim().slice(0, 170));
console.log('  modal=' + visibleOf(r, 'modal') + ' ⇒ ' + (visibleOf(r, 'modal') === true ? 'hex.back 是活的' : 'hex.back 点不动'));
process.exit(0);
