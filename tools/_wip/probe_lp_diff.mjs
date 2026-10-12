// tools/_wip/probe_lp_diff.mjs —— 差分判定：模拟器到底派发哪些光标事件
//   同一个控件上分别绑 CursorClick / CursorDown / CursorUp / CursorDrag，
//   然后**用坐标按下+抬起** ⇒ 看哪几个回调被调到。
//   ★ 判据：Click 到了而 Down/Up 没到 ⇒ 模拟器只发 Click ⇒ 长按离线测不了（环境边界）

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
const paint = (await c.play('get', { paint: true })).paint || [];
const p = paint.find((x) => x.name === 'cell.1.3');
const X = p.matrix.tx, Y = p.matrix.ty;
console.log('cell.1.3 中心 = ' + X + ',' + Y);

// 直接问运行树：这个控件上到底有几类监听？——先看引擎是否暴露
const before = (await get()).logs.length;
console.log('\n=== 坐标按下 → 0.05s → 抬起 ===');
await ptr('down', X, Y); await tick(0.05);
await ptr('up', X, Y); await tick(0.15);

const r = await get();
const lines = r.logs.slice(before).map((l) => String(l).trim());
console.log('新增日志 ' + lines.length + ' 条：');
for (const l of lines.slice(0, 25)) console.log('  ' + l.slice(0, 180));

console.log('\n=== 结论判据 ===');
console.log('  若「长按探针[down …]」出现 ⇒ 引擎**会**派发 CursorDown（长按机制有输入）');
console.log('  若只出现点击相关日志、没有 down/up 探针 ⇒ 模拟器不发 down/up ⇒ 长按离线测不了');
process.exit(0);
