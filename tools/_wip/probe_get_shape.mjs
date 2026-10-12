// tools/_wip/probe_get_shape.mjs —— 先搞清 play('get',{inspect:true}) 到底返回什么
import path from 'node:path';
import { makeController, loadPlan, buildProject, WORKSPACE, enterLevel } from '../sim/kit.mjs';

const LUA_FILE = path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();
buildProject(c, plan, LUA_FILE);

const raw = async () => c.play('get', { inspect: true });
const tick = async (dt) => { await c.play('step', { dt }); };
const clickName = async (nm) => { await c.play('click', { name: nm }); };

await c.play('start', {});
await enterLevel(c, tick);

const g = await raw();
console.log('顶层键 = ' + JSON.stringify(Object.keys(g)));
if (g.result) console.log('result 键 = ' + JSON.stringify(Object.keys(g.result)));
const r = g.result || g;
for (const k of Object.keys(r)) {
  const v = r[k];
  const t = Array.isArray(v) ? 'array[' + v.length + ']' : typeof v;
  console.log('  ' + k + ' : ' + t + (typeof v === 'string' ? ' = ' + v.slice(0, 80) : ''));
}
// 找哪里装着日志
for (const k of Object.keys(r)) {
  const v = r[k];
  if (Array.isArray(v) && v.length && typeof v[0] === 'string') {
    console.log('\n候选日志字段：' + k + '（' + v.length + ' 条），末 6 条：');
    for (const l of v.slice(-6)) console.log('   ' + String(l).slice(0, 150));
  }
}
console.log('\n=== 点一次 cell.1.1 再看 ===');
await clickName('cell.1.1'); await tick(0.15);
const g2 = await raw();
const r2 = g2.result || g2;
for (const k of Object.keys(r2)) {
  const v = r2[k];
  if (Array.isArray(v) && v.length && typeof v[0] === 'string') {
    console.log('  ' + k + ' 末 4 条：');
    for (const l of v.slice(-4)) console.log('     ' + String(l).slice(0, 150));
  }
}
process.exit(0);
