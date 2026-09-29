// tools/sim/play_test.mjs —— 在模拟器里跑通「偷窃版」完整交互
//
// 前置：lua tools/dump_layout.lua   （生成 tools/sim/out/layout-plan.json）
//       lua tools/bundle_client_script.lua
// 运行：node tools/sim/play_test.mjs
//
// 模拟器自带自动化接口（在插件 bundle 里挖出来的）：
//   play('click', {name})     按**控件名**点预设按钮（内部 SimulateCursorClick）
//   play('pointer',{type,x,y}) 按坐标点：type = down | up | click | move
//   play('step', {dt})        推进时间
//   play('get', {inspect:true}) 读运行树 / 日志
//
// ⚠️ 模拟器状态是**内存态**：建树和试玩必须在同一个进程里做完。

import fs from 'node:fs';
import path from 'node:path';
import { makeController, loadPlan, buildProject, indexTree, textOf, childOf, childText, visibleOf, dumpJson, shot, WORKSPACE, OUT } from './kit.mjs';

const LUA_FILE = process.argv[2] || path.join(WORKSPACE, 'dist', 'client_script.lua');
const plan = loadPlan();
const c = await makeController();

const { errs, made, subs, planIds } = buildProject(c, plan, LUA_FILE);
console.log('计划 ' + plan.nodes.length + ' 项 → 主控件 ' + made + ' + 子控件 ' + subs + '，建树错误 ' + errs.length);
for (const e of errs.slice(0, 15)) console.log('  [ERR] ' + e);
dumpJson('ui-project.json', c.get());

// ── 小工具 ────────────────────────────────────────────────────────────────
let step = 0;
const get = async () => {
  const g = await c.play('get', { inspect: true });
  return g && g.result ? g.result : g;
};
const click = async (name) => { await c.play('click', { name }); };
const tick = async (dt) => { await c.play('step', { dt }); };
const ss = async (file) => { const o = await shot(c, file); console.log('    截图 ' + file); return o; };

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  ✓ ' + label + (detail ? '   [' + detail + ']' : '')); }
  else { fail++; console.log('  ✗ ' + label + (detail ? '   [' + detail + ']' : '')); }
};

// ── 1. 启动 ───────────────────────────────────────────────────────────────
console.log('\n=== 1. 试玩启动');
await c.play('start', {});
await tick(0.05);
let ri = await get();
dumpJson('t01-start.json', ri);
const logs1 = (ri.logs || []).map((l) => l.level + ': ' + l.text);
check('脚本 OnInit 执行', logs1.some((l) => l.includes('OnInit done')));
check('脚本开局成功', logs1.some((l) => l.includes('started:')), logs1.find((l) => l.includes('started:')));
const missing = new Set((ri.logs || []).filter((l) => l.level === 'error')
  .map((l) => (l.text.match(/控件未找到：(\S+)/) || [])[1]).filter(Boolean));
check('计划内控件没有找不到的', [...missing].filter((m) => planIds.has(m)).length === 0,
  [...missing].filter((m) => planIds.has(m)).join(' ') || '无');

// ── 2. 开屏教程（intro）───────────────────────────────────────────────────
console.log('\n=== 2. 开屏教程');
let names = indexTree(ri);
check('intro 面板已显示', names.has('intro'));
check('intro 有 5 页', (ri.tree && true) && (() => {
  const t = indexTree(ri).get('intro.dots');
  return t && /1 \/ 5/.test(t.text || '');
})(), textOf(ri, 'intro.dots'));
await ss('t02-intro.png');

// 翻页 / 跳过
await click('intro.next'); await tick(0.05);
ri = await get();
check('翻到第 2 页', /2 \/ 5/.test(textOf(ri, 'intro.dots') || ''), textOf(ri, 'intro.dots'));
await click('intro.skip'); await tick(0.05);
ri = await get();
check('跳过后 intro 隐藏', visibleOf(ri, 'intro') === false);
check('棋盘的弹窗是隐藏的', visibleOf(ri, 'modal') === false);
dumpJson('t03-board.json', ri);
await ss('t03-board.png');

// ── 3. 单击 = 铅笔笔记 ────────────────────────────────────────────────────
console.log('\n=== 3. 单击格子 = 铅笔笔记');
const probe = async (label) => {
  const r = await get();
  const cell = indexTree(r).get('cell.2.2');
  console.log('    [' + label + '] 步数=' + textOf(r, 'hud.moves')
    + ' 进度=' + textOf(r, 'hud.progress')
    + ' 格内文字=' + JSON.stringify(cell && cell.text)
    + ' notes=' + JSON.stringify((cell && cell.notes) || null)
    + ' note控件=' + JSON.stringify(childText(r, 'cell.2.2', 'note')));
  return r;
};
// 3a) 没选头像时单击应当什么都不做（回归守卫）
await click('cell.2.2'); await tick(0.5);
ri = await probe('3a 没选头像单击后');
check('没选头像时单击不产生笔记', !childText(ri, 'cell.2.2', 'note'), JSON.stringify(childText(ri, 'cell.2.2', 'note')));

// 3b) 选了头像再单击 → 等过双击窗口才落成笔记
await click('tray.A'); await tick(0.05);
ri = await probe('3b 选中头像后');
await click('cell.2.2');
await tick(0.05);
ri = await probe('3b 单击后 0.05s');
// ★★ 2026-09-29 改（用户报"没选标记按钮、直接单击棋盘做 ✗ 有明显延迟"）：
//   **单击立即生效，不再挂起等双击窗口。**
//   旧断言锁的是"挂起"这个**内部机制**（单击后 0.05s 还没落笔记）——
//   机制一改就红，而用户真正要的"点了马上有反应"从来没被断言过。
//   ⇒ 现在直接断言**可感知的行为**：0.05 秒内笔记就该出现。
const noteNow = childText(ri, 'cell.2.2', 'note');
check('单击后 0.05s 内笔记就出现（不再有 0.35s 延迟）',
  !!noteNow && noteNow.length > 0, JSON.stringify(noteNow));
await tick(0.45);                       // 越过 DOUBLE_CLICK_SECONDS = 0.35
ri = await probe('3b 过了双击窗口');
const note = childText(ri, 'cell.2.2', 'note');
check('等待之后笔记仍在（没有被延迟处理覆盖）', !!note && note.length > 0, JSON.stringify(note));
check('笔记不改动步数', textOf(ri, 'hud.moves') === '0 步', textOf(ri, 'hud.moves'));
dumpJson('t03b-note.json', ri);
await ss('t03b-note.png');

// ── 4. 双击 = 放置 ────────────────────────────────────────────────────────
console.log('\n=== 4. 双击放置');
ri = await get();
check('头像卡 A 文案正确', textOf(ri, 'tray.A') === '管家', '文案=' + JSON.stringify(textOf(ri, 'tray.A')));
await ss('t04-selected.png');

await click('cell.1.3'); await tick(0.05);
await click('cell.1.3'); await tick(0.05);
ri = await get();
check('双击后放置成功（已放置 1/5）', /1 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
check('步数 +1', /1/.test(textOf(ri, 'hud.moves') || ''), textOf(ri, 'hud.moves'));
await ss('t05-placed.png');

// 再放一个
await click('tray.B'); await tick(0.03);
await click('cell.3.1'); await tick(0.05);
await click('cell.3.1'); await tick(0.05);
ri = await get();
check('第二个角色放置成功（2/5）', /2 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));

// ── 5. 撤销 / 重做 ────────────────────────────────────────────────────────
console.log('\n=== 5. 撤销 / 重做');
await click('action.undo'); await tick(0.05);
ri = await get();
check('撤销一次 → 退回 1/5', /1 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
await click('action.redo'); await tick(0.05);
ri = await get();
check('重做一次 → 回到 2/5', /2 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));

// ── 6. X 标记工具 ─────────────────────────────────────────────────────────
console.log('\n=== 6. X 标记工具');
await click('action.q.x'); await tick(0.05);
await click('cell.4.4'); await tick(0.05);
ri = await get();
const xNode = childOf(ri, 'cell.4.4', 'x');
check('X 标记已显示', !!xNode && xNode.visible !== false, 'visible=' + (xNode && xNode.visible));
await ss('t06-xmark.png');

// 切回放置模式
await click('action.q.place'); await tick(0.05);

// ── 7. 未摆满时提交按钮应当是禁用的 ───────────────────────────────────────
console.log('\n=== 7. 未摆满时「提交」应禁用');
ri = await get();
const submitNode = indexTree(ri).get('action.submit');
check('提交按钮不可交互（框架不给"点一下看报错"的机会）',
  !!submitNode && submitNode.interactable === false, 'interactable=' + (submitNode && submitNode.interactable));
check('提交文案提示要先摆满', /先摆满/.test(textOf(ri, 'action.submit') || ''), textOf(ri, 'action.submit'));
check('此时没有指认面板', visibleOf(ri, 'modal') === false);

// ── 8. 揭示答案 → 提交 → 指认 ─────────────────────────────────────────────
console.log('\n=== 8. 揭示 → 提交 → 两段式指认');
await click('action.reveal'); await tick(0.1);
ri = await get();
check('揭示后摆满（5/5）', /5 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
await ss('t07-revealed.png');

await click('action.submit'); await tick(0.05);
ri = await get();
check('提交通过 → 弹出指认面板', visibleOf(ri, 'modal') === true, 'toast=' + JSON.stringify(textOf(ri, 'hud.toast')));
{
  const t = indexTree(ri);
  const dbg = [];
  for (const k of ['modal', 'modal.title', 'modal.suspect.A', 'modal.cancel', 'modal.no_accomplice']) {
    const n = t.get(k);
    dbg.push(k + '=' + (n ? String(n.visible) : 'MISSING'));
  }
  console.log('    [调试] ' + dbg.join('  '));
  const errs = (ri.logs || []).filter((l) => l.level === 'error' || l.level === 'lua-error');
  for (const l of errs.slice(-6)) console.log('      [' + l.level + '] ' + l.text);
  for (const l of (ri.logs || []).filter((l) => /\[dbg\]/.test(l.text)).slice(-14)) {
    console.log('      [dbg] ' + l.text + '   @t=' + l.time);
  }
}
await ss('t08-accuse.png');

// 指认第一个嫌疑人
const susNames = [...indexTree(ri).keys()].filter((k) => /^modal\.suspect\./.test(k));
check('指认面板列出了嫌疑人按钮', susNames.length > 0, susNames.join(' '));
if (susNames.length) {
  await click(susNames[0]); await tick(0.05);
  ri = await get();
  check('选完盗窃者 → 进入同伙判定', visibleOf(ri, 'modal.no_accomplice') === true,
    '按钮=' + [...indexTree(ri).keys()].filter((k) => /^modal\./.test(k)).slice(0, 8).join(' '));
  await ss('t09-accomplice.png');
  await click('modal.no_accomplice'); await tick(0.05);
  ri = await get();
  check('结案（独自作案）→ 出现结果面板',
    !!textOf(ri, 'modal.body'), JSON.stringify((textOf(ri, 'modal.body') || '').slice(0, 60)));
  await ss('t10-result.png');
}

// ── 9. 收尾 ───────────────────────────────────────────────────────────────
dumpJson('t99-final.json', ri);
const errsLog = (ri.logs || []).filter((l) => l.level === 'error');
console.log('\n运行期 error 日志 ' + errsLog.length + ' 条');
for (const l of errsLog.slice(0, 10)) console.log('  [error] ' + l.text);

console.log('\n════════ 结果：' + pass + ' 通过 / ' + fail + ' 失败 ════════');
await c.play('stop', {});
await c.dispose();
process.exit(fail === 0 ? 0 : 1);
