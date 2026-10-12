// tools/_wip/probe_back_ptr.mjs —— `hex.back` 用【坐标点击】能不能通
//   目的：分清 "模拟器 play('click') 只支持预设按钮"（环境边界）
//         vs "hex.back 真的点不动"（产品 bug）

import path from 'node:path';
import { makeController, loadPlan, buildProject, visibleOf, WORKSPACE, enterLevel } from '../sim/kit.mjs';

const LUA_FILE = path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();
buildProject(c, plan, LUA_FILE);

const get = async () => { const g = await c.play('get', { inspect: true }); return g && g.result ? g.result : g; };
const tick = async (dt) => { await c.play('step', { dt }); };
const ptr = async (type, x, y) => { await c.play('pointer', { type, x, y }); };

const st = async (tag) => {
  const r = await get();
  const logs = (r.log || []).filter((l) => /hex\.back|back_confirm|退出|弹窗|exit_menu|收到点击/.test(String(l)));
  console.log('--- ' + tag + ' ---');
  console.log('   modal=' + visibleOf(r, 'modal') + ' modal.exit=' + visibleOf(r, 'modal.exit')
    + ' select=' + visibleOf(r, 'select') + ' board=' + visibleOf(r, 'board'));
  for (const l of logs.slice(-5)) console.log('     log: ' + String(l).trim().slice(0, 170));
  return r;
};

await c.play('start', {});
await enterLevel(c, tick);
await st('进关后');

// hex.back 的规划矩形（画布空间，原点左下）
const n = plan.nodes.find((x) => x.id === 'hex.back');
console.log('\nhex.back 规划：' + JSON.stringify(n && { cx: n.cx, cy: n.cy, w: n.w, h: n.h }));

console.log('\n=== 坐标点击 hex.back（先 down 再 up = 一次玩家点击）===');
if (n && n.cx != null) {
  await ptr('down', n.cx, n.cy); await tick(0.05);
  await ptr('up', n.cx, n.cy); await tick(0.15);
  await st('坐标点击之后');
  const r2 = await get();
  console.log('  ⇒ modal 打开？ ' + (visibleOf(r2, 'modal') === true ? '★ 是（说明 hex.back 是活的）' : '否（点不动）'));
  if (visibleOf(r2, 'modal') === true) {
    const e = plan.nodes.find((x) => x.id === 'modal.exit');
    if (e && e.cx != null) {
      console.log('\n=== 再坐标点击 modal.exit ===');
      await ptr('down', e.cx, e.cy); await tick(0.05);
      await ptr('up', e.cx, e.cy); await tick(0.2);
      const r3 = await st('点 modal.exit 之后');
      console.log('  ⇒ 回到选关？ ' + (visibleOf(r3, 'select') === true ? '★ 是 ★★ 返回链路完整' : '否'));
    }
  }
} else {
  console.log('  规划里没有 hex.back 的坐标');
}
process.exit(0);
