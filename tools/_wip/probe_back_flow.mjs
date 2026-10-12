// tools/_wip/probe_back_flow.mjs —— 「退出关卡 → 回选关」卡在哪一步
//   跑法：node tools/_wip/probe_back_flow.mjs
import path from 'node:path';
import { makeController, loadPlan, buildProject, visibleOf, WORKSPACE, enterLevel } from '../sim/kit.mjs';

const LUA_FILE = path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();
const { errs } = buildProject(c, plan, LUA_FILE);
console.log('建树错误 ' + errs.length);

const get = async () => { const g = await c.play('get', { inspect: true }); return g && g.result ? g.result : g; };
const click = async (name) => { await c.play('click', { name }); };
const tick = async (dt) => { await c.play('step', { dt }); };

const snap = async (tag) => {
  const r = await get();
  const lines = (r.log || []).filter((l) => /弹窗|exit_menu|pending|确认|screen|回到|返回|收到点击/.test(String(l)));
  console.log('\n--- ' + tag + ' ---');
  console.log('  visible: board=' + visibleOf(r, 'board') + ' select=' + visibleOf(r, 'select')
    + ' home=' + visibleOf(r, 'home') + ' modal=' + visibleOf(r, 'modal'));
  console.log('  modal.exit=' + visibleOf(r, 'modal.exit') + ' save=' + visibleOf(r, 'modal.save')
    + ' settle=' + visibleOf(r, 'modal.settle') + ' cancel=' + visibleOf(r, 'modal.cancel')
    + ' confirm.ok=' + visibleOf(r, 'confirm.ok') + ' hex.back=' + visibleOf(r, 'hex.back'));
  for (const l of lines.slice(-8)) console.log('    log: ' + String(l).trim().slice(0, 170));
  return r;
};

await c.play('start', {});
await enterLevel(c, tick);
await snap('进关后');

console.log('\n=== 点 hex.back ===');
await click('hex.back');
await tick(0.08);
await snap('点 hex.back 之后');

console.log('\n=== 逐一点候选按钮 ===');
for (const nm of ['modal.exit', 'modal.cancel', 'confirm.ok']) {
  const r0 = await get();
  console.log('  试 ' + nm + '（当前 visible=' + visibleOf(r0, nm) + '）');
  await click(nm);
  await tick(0.12);
  const r = await snap('点了 ' + nm);
  if (visibleOf(r, 'select') === true) { console.log('  ** ' + nm + ' 成功回到选关'); break; }
}

const fin = await get();
console.log('\n=== 末尾 ===');
console.log('  board=' + visibleOf(fin, 'board') + ' select=' + visibleOf(fin, 'select') + ' home=' + visibleOf(fin, 'home'));
