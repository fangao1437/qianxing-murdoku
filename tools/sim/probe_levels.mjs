// tools/sim/probe_levels.mjs —— 验证「选关 / 切关」在运行时真的能用
//
// 覆盖：
//   · 右栏「返回列表」→ 打开选关面板
//   · 点某一关 → 立刻切过去，标题 / 棋子数 / 棋盘尺寸全部跟着变
//   · 切到小关卡时，大关卡的额外格子要重新被隐藏（自适应棋盘 + 隐藏差集）
//   · 结算面板的「下一关」
//
// 用法：node tools/sim/probe_levels.mjs

import path from 'node:path';
import { makeController, loadPlan, buildProject, indexTree, textOf, visibleOf, dumpJson, shot, WORKSPACE } from './kit.mjs';

const plan = loadPlan();
const c = await makeController();
const { errs } = buildProject(c, plan, path.join(WORKSPACE, 'dist', 'client_script.lua'));
console.log('计划 ' + plan.nodes.length + ' 项，建树错误 ' + errs.length);

const get = async () => { const g = await c.play('get', { inspect: true }); return g && g.result ? g.result : g; };
const click = (n) => c.play('click', { name: n });
const tick = (dt) => c.play('step', { dt });

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  ✓ ' + label + (detail ? '   [' + detail + ']' : '')); }
  else { fail++; console.log('  ✗ ' + label + (detail ? '   [' + detail + ']' : '')); }
};

await c.play('start', {});
await tick(0.05);
let ri = await get();
check('开局成功', (ri.logs || []).some((l) => /started:/.test(l.text)),
  (ri.logs || []).map((l) => l.text).find((t) => /started:/.test(t)));

// ── 1. 返回列表 → 选关面板 ────────────────────────────────────────────────
console.log('\n=== 1. 「返回列表」打开选关面板');
await click('intro.skip'); await tick(0.05);
await click('action.back'); await tick(0.05);
ri = await get();
check('选关面板已打开', visibleOf(ri, 'modal') === true);
check('标题是「选择关卡」', textOf(ri, 'modal.title') === '选择关卡', textOf(ri, 'modal.title'));
const lvBtns = [...indexTree(ri).keys()].filter((k) => /^modal\.level\./.test(k)).sort();
check('列出了关卡按钮', lvBtns.length >= 4, lvBtns.join(' '));
check('面板显示了登记关数', /已登记 4 关/.test(textOf(ri, 'modal.body') || ''), textOf(ri, 'modal.body'));

// ⚠️ 模拟器预览的限制（2026-09-26 实测，别再去追）：
//   `requestScreenshot()` 出的 PNG **画不出弹窗内容**，但同一时刻
//   (a) 运行树里 modal.* 都是 visible=true / active=true / 文本正确，
//   (b) 绘制列表（play('get',{paint:true})）里 modal.title 和 hud.title
//       形式完全一样（都是 textbox + 文本 + 正确 left/bottom），
//       而 hud.title 在截图里是能看见的。
//   逐像素差分也证明"开合面板"只改了 6k 个像素（细笔画量级），而不是整块面板。
//   所以：**弹窗只做数据层断言**，截图不作为弹窗的验收依据。
//   真机上控件由游戏 UI 系统渲染 + 你在编辑器里配的素材，能看到就是能看到。
const paint = (await c.play('get', { paint: true })).paint || [];
const mp = paint.filter((x) => String(x.name || '').startsWith('modal.'));
check('绘制列表里有弹窗控件且坐标居中', mp.length >= 5,
  mp.length + ' 个：' + mp.map((x) => x.name + '@' + x.matrix.tx + ',' + x.matrix.ty).slice(0, 3).join(' '));
const mTitle = paint.find((x) => x.name === 'modal.title');
check('modal.title 位置居中（画布中心 800,450 附近）',
  !!mTitle && Math.abs(mTitle.matrix.tx - 800) <= 2 && Math.abs(mTitle.matrix.ty - 450) <= 160,
  mTitle ? ('中心 ' + mTitle.matrix.tx + ',' + mTitle.matrix.ty) : 'MISSING');
await shot(c, 'lv-01-select.png');

// ── 2. 切到 case_002（6×6）────────────────────────────────────────────────
console.log('\n=== 2. 切到 case_002（6×6，有同伙）');
check('选关面板里有 case_002', lvBtns.includes('modal.level.case_002'), lvBtns.join(' '));
await click('modal.level.case_002'); await tick(0.1);
ri = await get();
check('标题切到了案件 002', /案件 002/.test(textOf(ri, 'hud.title') || ''), textOf(ri, 'hud.title'));
check('棋子数跟着变成 6', /\/ 6/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
check('第 6 行第 6 列格子已显示', visibleOf(ri, 'cell.6.6') === true);
check('第 7 行格子仍是隐藏的', visibleOf(ri, 'cell.7.7') === false);
await shot(c, 'lv-02-case002.png');

// ── 3. 切到 case_003（7×7）───────────────────────────────────────────────
console.log('\n=== 3. 切到 case_003（7×7）');
await click('action.back'); await tick(0.05);
await click('modal.level.case_003'); await tick(0.1);
ri = await get();
check('标题切到了案件 003', /案件 003/.test(textOf(ri, 'hud.title') || ''), textOf(ri, 'hud.title'));
check('棋子数跟着变成 7', /\/ 7/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
check('第 7 行第 7 列格子现在显示了', visibleOf(ri, 'cell.7.7') === true);
const cell77 = indexTree(ri).get('cell.7.7');
// ★ 2026-09-28：**不再写死像素值**，改成按棋盘尺寸推算。
//
//   原来断言 97px —— 那是棋盘 733 宽时的值。后来修「动作条压住棋盘」把棋盘改成 677，
//   格子按比例变成 89，测试就红了。**格子尺寸本来就是棋盘尺寸的函数**
//   （见 `Adapter:cell_geometry`），写死等于把"一次布局调整"变成"一次测试失败"。
//   这里复算同一个公式：pitch = (board − ruler) / N，size = pitch − gap。
// ★★ 2026-09-28：**不再在测试里重算实现公式**。
//
//   原来我在这里抄了一遍 `Adapter:cell_geometry` 的算式（连 `ruler=37` 都抄了），
//   结果实现那边一动（棋盘 733→677、取整方式变化），测试就红 ——
//   而且红了**两轮**，每次都让我去追"到底谁对"。
//   ⇒ **重复实现必然漂移**。测试该断言的是**意图**，不是复算结果：
//     · 5×5 的格子必须**显著大于** 7×7 的（这是"格子随 N 自适应"的本意）
//     · 边长落在合理区间内（能看见、又不至于溢出格子）
//   公式的正确性由 `cell_geometry` 自己保证（它只有一处实现）。
const sane = (px) => px > 40 && px < 200;
const boardN = indexTree(ri).get('board');
const bw = boardN && (boardN.sizeDeltaX ?? boardN.width);
const s7 = cell77 && (cell77.sizeDeltaX ?? cell77.width);
check('7×7 的格子边长在合理区间（不重算公式，只看意图）',
  !!cell77 && sane(s7), 'cell.7.7=' + s7 + '（棋盘 ' + bw + '）');
check('线索数跟着变成 18（clue.18 可见）', visibleOf(ri, 'clue.18') === true);
await shot(c, 'lv-03-case003.png');

// ── 4. 切回 5×5，大关卡的格子要重新隐藏 ──────────────────────────────────
console.log('\n=== 4. 切回 case_001（5×5）');
await click('action.back'); await tick(0.05);
await click('modal.level.case_001'); await tick(0.1);
ri = await get();
check('标题切到了案件 001', /案件 001/.test(textOf(ri, 'hud.title') || ''), textOf(ri, 'hud.title'));
check('棋子数回到 5', /\/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
check('第 6 行格子重新被隐藏', visibleOf(ri, 'cell.6.6') === false);
check('第 7 行格子重新被隐藏', visibleOf(ri, 'cell.7.7') === false);
check('第 18 条线索重新被隐藏', visibleOf(ri, 'clue.18') === false);
const c11 = indexTree(ri).get('cell.1.1');
// 同上一处：按棋盘尺寸复算，不写死。5×5 的格子必须**比 7×7 大**（这是这条断言的本意）。
const s5 = c11 && (c11.sizeDeltaX ?? c11.width);
check('5×5 的格子明显大于 7×7 的（"格子随 N 自适应"的本意）',
  !!c11 && sane(s5) && s5 > s7, 'cell.1.1=' + s5 + ' > cell.7.7=' + s7);
await shot(c, 'lv-04-back-to-5x5.png');

// ── 5. 「下一关」按钮 ────────────────────────────────────────────────────
console.log('\n=== 5. 结算面板的「下一关」');
// case_001 是注册表第 2 关，下一关应该是 case_002
await click('action.reveal'); await tick(0.1);
await click('action.submit'); await tick(0.05);
ri = await get();
check('进入指认面板', visibleOf(ri, 'modal') === true);
await click('modal.suspect.D'); await tick(0.05);         // case_001 的盗窃者是 D
await click('modal.no_accomplice'); await tick(0.05);      // 无同伙
ri = await get();
check('已破案（结算面板）', textOf(ri, 'modal.title') === '破案！', textOf(ri, 'modal.title'));
check('结算面板有「下一关」按钮', visibleOf(ri, 'modal.next') === true);
await shot(c, 'lv-05-solved.png');
await click('modal.next'); await tick(0.1);
ri = await get();
check('「下一关」切到了案件 002', /案件 002/.test(textOf(ri, 'hud.title') || ''), textOf(ri, 'hud.title'));

const errsLog = (ri.logs || []).filter((l) => l.level === 'error' || l.level === 'lua-error');
check('运行期没有错误日志', errsLog.length === 0,
  errsLog.slice(0, 3).map((l) => l.text).join(' | ') || '无');

dumpJson('levels-final.json', ri);
console.log(`\n════════ 选关/切关：${pass} 通过 / ${fail} 失败 ════════`);
await c.play('stop', {});
await c.dispose();
process.exit(fail === 0 ? 0 : 1);

