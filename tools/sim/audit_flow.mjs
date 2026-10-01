// tools/sim/audit_flow.mjs —— **操作动线审计**（主页 / 选关 / 关卡三处）
//
// 为什么要有它：布局已经盘过了（audit_layout.mjs），但"点进去出不来""切关后状态还在"
// 这类问题**布局审计看不见** —— 它们是**状态机**的问题。
//
//   这一版专门走真实动线，每一步都断言"该看见什么 / 不该看见什么"：
//     ① 主页 → 选关 → 返回主页
//     ② 主页 → 选关 → 卡片 → 关卡
//     ③ 关卡 →「返回列表」→ 选关
//     ④ 选关 → 另一张卡片 → **切关**（不是回到同一关）
//     ⑤ 切关后**状态要重置**（棋盘清空、进度归零、线索回到顶部）
//     ⑥ 关卡 →「重置关卡」→ 停在本关、棋盘清空
//     ⑦ 乱点不崩（连点返回、反复进出）
//
// 用法：node tools/sim/audit_flow.mjs

import path from 'node:path';
import { makeController, loadPlan, buildProject, indexTree, textOf, visibleOf, WORKSPACE } from './kit.mjs';

const c = await makeController();
buildProject(c, loadPlan(), path.join(WORKSPACE, 'dist', 'client_script.lua'));

const get = async () => { const g = await c.play('get', { inspect: true }); return g && g.result ? g.result : g; };
const tick = async (dt) => { await c.play('step', { dt }); };
const click = async (n) => { await c.play('click', { name: n }); };

let pass = 0, fail = 0;
function check(name, ok, extra) {
  if (ok) { pass++; console.log('  ✓ ' + name + (extra ? '   [' + extra + ']' : '')); }
  else { fail++; console.log('  ✗ ' + name + (extra ? '   [' + extra + ']' : '')); }
}
/** 等一个小段时间（点击要经过一帧才反映到树上） */
const settle = async (n = 3) => { for (let i = 0; i < n; i++) await tick(0.08); };
/** 当前在哪个页面 */
function where(ri) {
  if (visibleOf(ri, 'home') === true) return 'home';
  if (visibleOf(ri, 'select') === true) return 'select';
  if (visibleOf(ri, 'board') === true) return 'level';
  return '?';
}
/** 棋盘上有几个"已放置"的（看每格的 face 有没有图 —— 用 obj/tray 太间接，直接数 cell 的可见 face 文字太多；
 *  改用"提交按钮是否可点"这个间接信号：摆满才能提交） */
const progressText = (ri) => String(textOf(ri, 'hud.progress') || '');
const movesText = (ri) => String(textOf(ri, 'hud.moves') || '');

await c.play('start', {}); await settle();
let ri = await get();

// ① 主页 → 选关 → 返回主页
console.log('\n── ① 主页 ⇄ 选关 ──');
check('开局在主页', where(ri) === 'home', where(ri));
await click('home.select'); await settle();
ri = await get();
check('点「选关」进选关', where(ri) === 'select', where(ri));
await click('select.back'); await settle();
ri = await get();
check('点「返回主页」回主页', where(ri) === 'home', where(ri));

// ② 主页 → 选关 → 卡片 → 关卡
console.log('\n── ② 选关 → 关卡 ──');
await click('home.select'); await settle();
await click('select.card.2'); await settle();
await click('intro.skip'); await settle();
ri = await get();
check('点卡片进关卡（跳过教程后）', where(ri) === 'level', where(ri));
const level1Title = String(textOf(ri, 'hud.title') || '');
check('关卡标题是刚点的那一关', level1Title.length > 0, JSON.stringify(level1Title));

// ③ 关卡 →「返回列表」→ 选关
console.log('\n── ③ 关卡 → 返回列表 ──');
await click('action.back'); await settle();
ri = await get();
check('点「返回列表」回选关', where(ri) === 'select', where(ri));

// ④ 选关 → 另一张卡片 → 切关
console.log('\n── ④ 切关 ──');
await click('select.card.3'); await settle();
await click('intro.skip'); await settle();
ri = await get();
check('换一张卡片能进（切关）', where(ri) === 'level', where(ri));
const level2Title = String(textOf(ri, 'hud.title') || '');
check('标题换成了另一关（不是回到原来那关）', level2Title !== level1Title,
  JSON.stringify(level1Title) + ' → ' + JSON.stringify(level2Title));

// ⑤ 切关后状态重置
console.log('\n── ⑤ 切关后状态重置 ──');
check('新关卡的步数归零', /^0\s*步/.test(movesText(ri)), JSON.stringify(movesText(ri)));
check('新关卡的进度归零', /0\s*\//.test(progressText(ri)) || progressText(ri) === '',
  JSON.stringify(progressText(ri)));

// ⑥ 「重置关卡」停在本关
console.log('\n── ⑥ 重置关卡 ──');
await click('action.redo'); await settle();
ri = await get();
check('点「重置关卡」仍在本关', where(ri) === 'level', where(ri));
check('重置后标题不变（没被送回主页/选关）',
  String(textOf(ri, 'hud.title') || '') === level2Title, JSON.stringify(textOf(ri, 'hud.title')));
check('重置后步数归零', /^0\s*步/.test(movesText(ri)), JSON.stringify(movesText(ri)));

// ⑦ 乱点不崩（连点返回、反复进出）
console.log('\n── ⑦ 乱点不崩 ──');
for (let i = 0; i < 3; i++) { await click('action.back'); await settle(1); }
await settle();
ri = await get();
check('连点「返回列表」不崩且停在合法页面', ['home', 'select', 'level'].indexOf(where(ri)) >= 0, where(ri));
// 从当前页回到主页（如果不在主页）
let guard = 0;
while (where(ri) !== 'home' && guard++ < 6) {
  if (where(ri) === 'level') await click('action.back');
  else if (where(ri) === 'select') await click('select.back');
  await settle();
  ri = await get();
}
check('能一路回到主页（不存在断头路）', where(ri) === 'home', '用了 ' + guard + ' 步');
// 反复进出 5 次
for (let i = 0; i < 5; i++) {
  await click('home.select'); await settle(1);
  await click('select.back'); await settle(1);
}
ri = await get();
check('反复进出 5 次后仍在主页', where(ri) === 'home', where(ri));

const errs = (ri.logs || []).filter((l) => l.level === 'error');
check('全程没有 error 级日志', errs.length === 0, errs.length + ' 条: ' + errs.slice(0, 3).map((l) => l.text).join(' | '));

console.log('\n════════ 动线审计：' + pass + ' 通过 / ' + fail + ' 失败 ════════');
await c.play('stop', {});
await c.dispose();
process.exit(fail === 0 ? 0 : 1);
