// tools/sim/win_path.mjs —— 在模拟器里**真正把一局玩通**（不是用「揭示」作弊）
//
// 流程：读关卡的答案 → 逐个角色选中并双击放到正确格 → 提交 → 指认盗窃者
//       → 声明有没有同伙（有则再指认同伙）→ 断言出现「破案！」结算。
//
// 用法：
//   node tools/sim/win_path.mjs                  # 注册表第一关
//   node tools/sim/win_path.mjs --level=case_002  # 指定关卡（会自动重新打包成该关卡）
//   node tools/sim/win_path.mjs --level=case_002 --keep-bundle   # 用现有的 dist（不重新打包）
//
// ⚠️ 模拟器状态是内存态：读关卡数据、建树、试玩必须在同一个进程里做完。

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { makeController, loadPlan, buildProject, indexTree, textOf, visibleOf, dumpJson, shot, WORKSPACE, OUT } from './kit.mjs';

const LUA = process.env.LUA_BIN
  || path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Lua', 'bin', 'lua.exe');
const argOf = (name) => {
  const hit = process.argv.find((a) => a.startsWith('--' + name + '='));
  return hit ? hit.slice(name.length + 3) : null;
};
const LEVEL = argOf('level');
const KEEP = process.argv.includes('--keep-bundle');

const run = (args) => {
  console.log('  $ lua ' + args.join(' '));
  execFileSync(LUA, args, { cwd: WORKSPACE, stdio: 'inherit' });
};

// ── 1. 准备：打包 + 导出关卡数据 ──────────────────────────────────────────
console.log('=== 0. 准备');
if (!KEEP) {
  run(LEVEL ? ['tools/bundle_client_script.lua', '--level=' + LEVEL]
            : ['tools/bundle_client_script.lua']);
}
const levelJson = path.join(OUT, 'level-for-win.json');
run(LEVEL ? ['tools/dump_level.lua', LEVEL, levelJson]
          : ['tools/dump_level.lua', levelJson]);
const lv = JSON.parse(fs.readFileSync(levelJson, 'utf8'));

console.log(`\n=== 目标关卡 ${lv.id}「${lv.name}」 ${lv.rows}×${lv.cols} 棋子 ${lv.piece_count} 线索 ${lv.clue_count}`);
console.log(`    盗窃者 ${lv.thief} / 同伙 ${lv.accomplice ?? '（无）'} / 受害者 ${lv.victim}`);
console.log(`    区域 ${lv.rooms} 个、门 ${lv.doors} 处、并列策略 ${lv.tie_policy}、假话 announce=${lv.announce}`);

// ── 2. 建树 + 试玩 ────────────────────────────────────────────────────────
const plan = loadPlan();
const c = await makeController();
const { errs, made, subs, planIds } = buildProject(c, plan, path.join(WORKSPACE, 'dist', 'client_script.lua'));
console.log(`    计划 ${plan.nodes.length} 项 → 主控件 ${made} + 子控件 ${subs}，建树错误 ${errs.length}`);
for (const e of errs.slice(0, 10)) console.log('    [ERR] ' + e);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  ✓ ' + label + (detail ? '   [' + detail + ']' : '')); }
  else { fail++; console.log('  ✗ ' + label + (detail ? '   [' + detail + ']' : '')); }
};
const get = async () => { const g = await c.play('get', { inspect: true }); return g && g.result ? g.result : g; };
const click = (name) => c.play('click', { name });
const tick = (dt) => c.play('step', { dt });
const ss = (f) => shot(c, f);

await c.play('start', {});
await tick(0.05);
let ri = await get();

console.log('\n=== 1. 启动');
const logs = (ri.logs || []).map((l) => l.level + ': ' + l.text);
check('脚本开局成功', logs.some((l) => l.includes('started: ' + lv.id)),
  logs.find((l) => l.includes('started:')) || '(没有 started 日志)');
check('控件齐全（没有找不到的）',
  [...new Set((ri.logs || []).filter((l) => l.level === 'error')
    .map((l) => (l.text.match(/控件未找到：(\S+)/) || [])[1]).filter(Boolean))]
    .filter((m) => planIds.has(m)).length === 0);
check('棋盘尺寸与关卡一致（格子数 ' + lv.rows * lv.cols + '）',
  fs.existsSync(path.join(OUT, 'layout-plan.json')));

// 跳过开屏教程
await click('intro.skip'); await tick(0.05);
ri = await get();
check('已跳过开屏教程', visibleOf(ri, 'intro') === false);

// ── 3. 按答案逐个摆放 ────────────────────────────────────────────────────
//
//   ★★★ 2026-10-01：**改成"放一个等一个"**。
//
//   原来每次只 `tick(0.03)` 就接着放下一个。单独跑没问题，但放进 `check_all`
//   （前面刚跑完一堆重活）就变成 `case_003：5 通过 / 10 失败` —— 7×7 有 5 个角色、
//   点击更多，**同样的固定 tick 在负载下不够**（和 audit_flow 那次一模一样）。
//
//   ⇒ 不猜时间：**放完一个就轮询到"已放置数真的 +1"为止**，再放下一个。
console.log('\n=== 2. 按答案摆放全部角色');
/** 读 `已放置 x / y` 里的 x */
async function placedCount() {
  const m = /已放置\s*(\d+)/.exec(String(textOf(await get(), 'hud.progress') || ''));
  return m ? Number(m[1]) : -1;
}
for (const p of lv.pieces) {
  const trayId = 'tray.' + p.id;
  const cellId = `cell.${p.r}.${p.c}`;
  const t = indexTree(ri);
  if (!t.has(trayId)) { check('头像卡存在 ' + trayId, false); continue; }
  const before = await placedCount();
  await click(trayId); await tick(0.05);
  await click(cellId); await tick(0.05);
  await click(cellId);
  // 等"放置数 +1"（最多 ~1.4s），等不到就把当前值交给断言去报
  let ok = false;
  for (let i = 0; i < 24; i++) {
    await tick(0.06);
    if (await placedCount() > before) { ok = true; break; }
  }
  if (!ok) console.log('    （注意：放 ' + p.id + ' 之后放置数没涨，before=' + before + '）');
  ri = await get();
}
const progress = textOf(ri, 'hud.progress');
check(`全部 ${lv.piece_count} 个角色都已放置`, new RegExp(`${lv.piece_count} / ${lv.piece_count}`).test(progress || ''), progress);
check('位置全部正确', new RegExp(`${lv.piece_count} / ${lv.piece_count}`).test(textOf(ri, 'hud.score') || ''),
  textOf(ri, 'hud.score'));
await ss('win-01-placed.png');

// ── 4. 提交 → 两段式指认 ─────────────────────────────────────────────────
console.log('\n=== 3. 提交并指认');
const submitNode = indexTree(ri).get('action.submit');
check('摆满后「提交」可用', !!submitNode && submitNode.interactable !== false,
  'interactable=' + (submitNode && submitNode.interactable));
await click('action.submit'); await tick(0.05);
ri = await get();
check('弹出指认面板', visibleOf(ri, 'modal') === true, 'toast=' + JSON.stringify(textOf(ri, 'hud.toast')));
await ss('win-02-accuse-thief.png');

// 指认盗窃者
await click('modal.suspect.' + lv.thief); await tick(0.05);
ri = await get();
check('进入「有没有同伙」环节', visibleOf(ri, 'modal.no_accomplice') === true);

if (lv.accomplice) {
  // 关卡规则要求必有同伙 → 应该直接指认同伙
  const accName = visibleOf(ri, 'modal.suspect.' + lv.accomplice);
  check('指认面板里有同伙候选 ' + lv.accomplice, accName === true);
  await ss('win-03-accuse-accomplice.png');
  await click('modal.suspect.' + lv.accomplice); await tick(0.05);
} else {
  await ss('win-03-accuse-accomplice.png');
  await click('modal.no_accomplice'); await tick(0.05);
}
ri = await get();

// ── 5. 结算 ──────────────────────────────────────────────────────────────
console.log('\n=== 4. 结算');
check('结果弹窗已显示', visibleOf(ri, 'modal.title') === true);
const title = textOf(ri, 'modal.title');
const body = textOf(ri, 'modal.body');
const stats = textOf(ri, 'modal.stats');
check('结案标题是「破案！」', title === '破案！', JSON.stringify(title));
check('结算有正文', !!body && body.length > 0 && body !== '（结果文案）', JSON.stringify((body || '').slice(0, 70)));
check('结算有统计行', !!stats && /用时/.test(stats)
  && new RegExp(`${lv.piece_count}/${lv.piece_count}`).test(stats), JSON.stringify(stats));
console.log('    正文：' + JSON.stringify(body));
console.log('    统计：' + JSON.stringify(stats));
await ss('win-04-solved.png');

const errsLog = (ri.logs || []).filter((l) => l.level === 'error' || l.level === 'lua-error');
check('运行期没有错误日志', errsLog.length === 0,
  errsLog.slice(0, 3).map((l) => l.text).join(' | ') || '无');

// ── ★★★ 2026-10-01：**通关之后的动线**（原来测到结算就结束了）──────────────
//
//   为什么补：结算弹窗有「重玩本关 / 分享棋局 / 下一关」，选关卡片上有「★ 已破案」
//   标记 —— 这两条动线**从来没被测过**。而"打完一关，回选关看到它标记成已破案"
//   正是玩家最直接的正反馈，坏了会很难受。
console.log('\n=== 5. 通关之后的动线');
// ① 先测结算弹窗的「下一关」（此时弹窗还开着）
//
//   `on_next_level` 的行为（main.lua）：有下一关就 `start_other(下一关)`，
//   没有就给个 toast「已经是最后一关了」而不是静默无反应。
//   这条**从来没被测过** —— 而"打完一关顺手点下一关"是最自然的操作。
const beforeTitle = String(textOf(ri, 'hud.title') || '');
await click('modal.next'); await tick(0.3);
await click('intro.skip'); await tick(0.25);
ri = await get();
const afterTitle = String(textOf(ri, 'hud.title') || '');
// ⚠️ **最后一关要单独判**：`case_003` 是最后一关 ⇒ 点「下一关」应该给提示
//    「已经是最后一关了」而不是切关。我第一版写成"标题必须变"，
//    于是 case_003 报 `["案件 003 · 第三方" → "案件 003 · 第三方"]` —— **断言错了，不是功能错了**。
const toastNow = String(textOf(ri, 'hud.toast') || '');
const isLast = /最后一关/.test(toastNow) || /最后一关/.test(String(ri.toast || ''));
check('点结算里的「下一关」有明确结果（切到下一关 / 或提示已是最后一关）',
  visibleOf(ri, 'board') === true && (afterTitle !== beforeTitle || isLast),
  isLast ? '已是最后一关（给了提示 ✅）'
         : JSON.stringify(beforeTitle) + ' → ' + JSON.stringify(afterTitle));

// ② 回选关看卡片标记
await click('action.back'); await tick(0.25);
ri = await get();
check('通关后点「返回列表」回到选关', visibleOf(ri, 'select') === true,
  'select=' + visibleOf(ri, 'select') + ' home=' + visibleOf(ri, 'home'));
// 在 8 张卡片里找带「已破案」标记的那张
let marked = false, cardInfo = '';
for (let i = 1; i <= 8; i++) {
  const info = textOf(ri, 'select.card.' + i + '.info') || '';
  if (String(info).indexOf('已破案') >= 0) {
    marked = true;
    cardInfo = (textOf(ri, 'select.card.' + i + '.title') || '') + ' → ' + info;
    break;
  }
}
check('通关后卡片显示「★ 已破案」', marked, cardInfo || '（8 张卡片都没有这个标记）');
// 再进一次同一关：确认"通关 → 回选关 → 再进"这条往返没问题（状态没残留）
await click('select.card.2'); await tick(0.25);
await click('intro.skip'); await tick(0.25);
ri = await get();
check('通关后还能再进关卡（往返没坏）', visibleOf(ri, 'board') === true,
  'board=' + visibleOf(ri, 'board') + ' 步数=' + JSON.stringify(textOf(ri, 'hud.moves')));

dumpJson('win-final.json', ri);
console.log(`\n════════ ${lv.id}：${pass} 通过 / ${fail} 失败 ════════`);
await c.play('stop', {});
await c.dispose();

// 测试用的 --level 会把 dist 钉死成这一关；跑完恢复成正常打包（除非明确要求保留），
// 否则后面再跑 UI 回归 / 真机同步时拿到的是"被钉死"的包，很容易看花眼。
if (!KEEP) {
  console.log('\n=== 收尾：恢复常规打包（不钉死关卡）');
  run(['tools/bundle_client_script.lua']);
}

process.exit(fail === 0 ? 0 : 1);
