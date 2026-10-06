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
import { makeController, loadPlan, buildProject, indexTree, textOf, childOf, childText, visibleOf, dumpJson, shot, WORKSPACE, OUT , enterLevel} from './kit.mjs';

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
// ★★★★★ 2026-10-02：**三个"危险键"现在要 ✓ 确认**
//   （返回菜单 / 提交 / 重置关卡 —— 见 lua/ui_controller.lua 的 confirm_* 状态机）。
//   这个包装就是玩家实际的两步：先点它（冒出 ✓/✗），再点 ✓。
const clickConfirm = async (name) => {
  await click(name); await tick(0.05);
  await click('confirm.ok'); await tick(0.08);
};
const ss = async (file) => { const o = await shot(c, file); console.log('    截图 ' + file); return o; };

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  ✓ ' + label + (detail ? '   [' + detail + ']' : '')); }
  else { fail++; console.log('  ✗ ' + label + (detail ? '   [' + detail + ']' : '')); }
};

// ── 1. 启动 ───────────────────────────────────────────────────────────────
console.log('\n=== 1. 试玩启动');
await c.play('start', {}); await enterLevel(c, tick);

// ── 0. 主页四键（用户要求的布局：中列最上是「选关」）──────────────────────
//
// ⚠️ 这一步在文件里**排在"1. 试玩启动"之后、但 `let ri` 之前** ⇒
//    不能给 `ri` 赋值（会撞上 `let` 的暂时性死区：Cannot access 'ri' before initialization）。
//    ⇒ 块内用自己的局部变量 `r0`，结束时把状态传回外层的 `ri`（那时 `ri` 已可用）。
console.log('\n=== 0. 主页四键');
{
  let r0 = await get();
  const t = indexTree(r0);
  const has = (n) => !!t.get(n);
  check('主页容器在', has('home'));
  check('四键齐全', has('home.select') && has('home.continue') && has('home.shop') && has('home.bag'));
  check('选关键在最上（用户要求：原左下角那个挪到中列最上）',
    textOf(r0, 'home.select') === '选关', textOf(r0, 'home.select'));
  check('第二键是「从存档点开始」',
    textOf(r0, 'home.continue') === '从存档点开始', textOf(r0, 'home.continue'));
  // ★ 选关卡片的内容（参考《派蒙的执律庭实习》）：关名 + 「NxN　M名嫌疑人+1名受害人」
  //
  //   ⚠️ 卡片现在是**三段**：`select.card.N.title`（关名）/ 中间是**棋盘缩略图**
  //   （`select.card.N.room.1..6`）/ 下面是 `select.card.N.info`（人数+进度）。
  //   所以文字**不在** `select.card.N` 上了 —— 第一版我断言在卡片的 `text` 上，会红。
  //
  //   ⚠️ 也别写死 `select.card.1` —— 第 1 张是 `demo_selftest`，没有 size/suspects。
  {
    await click('home.select'); await tick(0.25);
    const r9 = await get();
    const idx9 = indexTree(r9);
    let caseCard = null, title = '', info = '';
    for (const [nm] of idx9) {
      const m = /^(select\.card\.\d+)\.info$/.exec(nm);
      if (!m) continue;
      const t = textOf(r9, m[1] + '.title') || '';
      const f = textOf(r9, nm) || '';
      if (/案件/.test(t) && /\d+x\d+/.test(f)) { caseCard = m[1]; title = t; info = f; break; }
    }
    check('卡片有关名（三段式里的 title）', caseCard !== null,
      caseCard ? caseCard + ' → ' + JSON.stringify(title) : '（没找到）');
    check('卡片 info 有网格尺寸 NxN', /\d+x\d+/.test(info), JSON.stringify(info.slice(0, 70)));
    check('卡片 info 有人数（M名嫌疑人+1名受害人）', /名嫌疑人\+1名受害人/.test(info),
      JSON.stringify(info.slice(0, 70)));
    // 缩略图：至少有一条房间色块可见
    //
    //   ⚠️ 用**重试**而不是"睡固定时间再读一次"：
    //   我先后试过"复用旧快照"和"重新取一次"，都报 0 块，而单独探针明明看到
    //   `room.1/2/3 visible=true`。多次 tick 之后总会同步上 ——
    //   与其猜"睡多久才够"，不如**轮询到出现为止**（有上限，不会挂死）。
    let rooms = 0;
    if (caseCard) {
      for (let attempt = 0; attempt < 8 && rooms === 0; attempt++) {
        const rr = await get();
        for (let j = 1; j <= 6; j++) if (visibleOf(rr, caseCard + '.room.' + j) === true) rooms++;
        if (rooms === 0) await tick(0.1);
      }
    }
    check('卡片中间画出了棋盘缩略图（房间色块）', rooms >= 1,
      caseCard ? caseCard + ' 可见色块 ' + rooms + ' 块' : '（没找到案件卡）');
    await click('select.back'); await tick(0.2);
    r0 = await get();
  }
  // ★ 2D/3D 输入隔离（目标 ⑤）：适配期会打一行"已屏蔽穿透 N 个"。
  //   ⚠️ 模拟器**不暴露** `disableKeyEventPassthrough` 这些字段（读过，没有），
  //   所以这里断言的是**那行日志** —— 而 `seal_container` **只在字段存在且写入成功时才计数**，
  //   于是"N ≥ 1"就等价于"这些字段在运行时是可设的"。这是在模拟器里能拿到的最强证据。
  {
    const sealLog = (r0.logs || []).map((l) => (typeof l === 'string' ? l : (l.text || '')))
      .find((s) => /输入隔离.*屏蔽穿透/.test(s)) || '';
    const n = Number((sealLog.match(/屏蔽穿透\s*(\d+)\s*个/) || [])[1] || 0);
    check('主页/选关容器已设「屏蔽按键事件穿透」（目标 ⑤）', n >= 2, sealLog || '（没打这行日志）');
  }
  // 商城 / 背包：占位按钮，点了给一句明确提示（美术资源齐了再设计）
  await click('home.shop'); await tick(0.1);
  r0 = await get();
  check('商城是占位（点了有明确提示，不是静默无反应）',
    /商城/.test(textOf(r0, 'hud.toast') || ''), textOf(r0, 'hud.toast'));
  // 「从存档点开始」：**有记录就进那一关；没有记录就老实说并送去选关** —— 不能装死。
  //
  //   ⚠️ 不要断言"一定是无记录分支"：模拟器的局内存档**会跨测试运行保留**，
  //   所以跑过一遍之后就有记录了（我第一版写死了"无记录"，第二轮就假红）。
  //   断言真正的要求：**点了必有明确结果**，两种情况都算过。
  await click('home.continue'); await tick(0.3);
  r0 = await get();
  {
    const wentIn = visibleOf(r0, 'board') === true;
    const toSelect = visibleOf(r0, 'select') === true;
    const toasted = /游玩记录/.test(textOf(r0, 'hud.toast') || '');
    check('「从存档点开始」点了必有明确结果（进关 / 提示并去选关）',
      wentIn || (toSelect && toasted),
      'board=' + visibleOf(r0, 'board') + ' select=' + toSelect
      + ' toast=' + JSON.stringify(textOf(r0, 'hud.toast')));
  }
  // 收尾：不管刚才进了关还是停在选关，都退回主页，别把状态留给后面的步骤
  if (visibleOf(r0, 'board') === true) { await clickConfirm('action.back'); await tick(0.2); r0 = await get(); }
  if (visibleOf(r0, 'select') === true) { await click('select.back'); await tick(0.2); }
}

// ★ 关键收尾：上面几步把界面**留在了主页**（点过 商城 / 从存档点开始 / 返回主页）。
//   后面的步骤全都假定"已经在关卡里"，所以这里必须**重新走一遍进关流程**。
//   （我第一版漏了这步 ⇒ 界面停在主页 ⇒ 游戏 UI 被整片隐藏 ⇒
//     后面"提交后不弹指认面板"又红了一次。屏幕状态是全局的，副作用要自己收干净。）
await enterLevel(c, tick);
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
await click('clue.1.face'); await tick(0.05);
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
check('线索卡 1 存在于树里', textOf(ri, 'tray.A') === '管家', '文案=' + JSON.stringify(textOf(ri, 'tray.A')));
await ss('t04-selected.png');

await click('cell.1.3'); await tick(0.05);
await click('cell.1.3'); await tick(0.05);
ri = await get();
check('双击后放置成功（已放置 1/5）', /1 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
check('步数 +1', /1/.test(textOf(ri, 'hud.moves') || ''), textOf(ri, 'hud.moves'));
await ss('t05-placed.png');

// 再放一个
await click('clue.2.face'); await tick(0.03);
await click('cell.3.1'); await tick(0.05);
await click('cell.3.1'); await tick(0.05);
ri = await get();
check('第二个角色放置成功（2/5）', /2 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));

// ── 5. 撤销 / 重做 ────────────────────────────────────────────────────────
console.log('\n=== 5. 撤销 / 重做');
await click('action.undo'); await tick(0.05);
ri = await get();
check('撤销一次 → 退回 1/5', /1 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
// ★★★ 2026-09-30：**这个按钮的语义变了**（按用户给的映射：重做 → 重置关卡）。
//   参考图左上角是「返回菜单 ↰ + 重置关卡 ↻」，所以 `action.redo` 这个**按钮**
//   改成 `restart`（`core:reset()`，早就实现了）。
//   **重做没有消失** —— 键盘快捷键里仍然有 `redo`，只是这个按钮让给了「重置关卡」。
//   ⇒ 断言从「重做回到 2/5」改成「重置关卡把进度清零」。
await clickConfirm('action.redo'); await tick(0.1);
ri = await get();
check('「重置关卡」把棋盘清空（0/5）', /0 \/ 5/.test(textOf(ri, 'hud.progress') || ''),
  textOf(ri, 'hud.progress'));
// ★★★ 2026-10-05 改判（依据，不是放宽）：原来断言「`action.redo` 的文案就是重置关卡」——
//   而 `action.redo` 这个**旧文字按钮已被按设计删除** ✗，断言永远红。
//   依据（lua/ui_controller.lua，行号为实际文件行号）：
//     · `ui_controller.lua:1718-1729`「**右上三键（提交 / 重置关卡 / 撤销）的旧文字按钮 —— 已删。**」
//       —— 实测两套键**重叠且动作重复**，留图上那套 `hex.*`（位置逐项吻合、且已有素材图）。
//     · `ui_controller.lua:1698-1700`：连底图也只留给 `action.back` ——
//       `action.redo` / `action.hint` **已从存档里删掉**（与 `hex.redo` / `hex.hint` 重叠且动作重复）。
//     · `ui_controller.lua:1734-1735`：入口 = `hex.submit` / `hex.redo` / `hex.undo` / `hex.hint`。
//   实测：`layout-plan.json` 里 `action.redo` = 0。
//   ⇒ 反转成哨兵（**不是删断言**）：旧文字键**重新出现就是红** ✓，并顺带确认替代品在。
//   判据来源：用户 2026-10-05 授权「以建议为准」✓（见 `docs/L3基线-模拟器四步失败清单.md` §6）。
//
//   ⚠️ 「重置关卡」的功能并没有消失 —— 它现在是 `hex.redo`（`ui_controller.lua:1407` 的 `restart`）。
//     纯图片图标键在模拟器里**读不到文案**，所以这里锁「**控件在 + 素材图对**」这个可验证的等价事实 ✓
//     （`action.hint`（放大镜）同理 ⇒ `hex.hint`，`ui_controller.lua:1409` 的 `hint`）。
const OLD_TEXT_KEYS = [
  ['action.redo', 'hex.redo', 100126],   // 重置关卡
  ['action.hint', 'hex.hint', 100120],   // 放大镜（提示）
  ['action.undo', 'hex.undo', 100127],   // 撤销
  ['action.submit', 'hex.submit', 100110],  // 提交
  ['action.reveal', null, null],         // 揭示 —— 按参考图**没有接替者**
];
for (const [oldId, newId, imgId] of OLD_TEXT_KEYS) {
  check('旧文字按钮 ' + oldId + ' 按设计不存在（若出现 ⇒ 已删控件被加回来了）',
    !plan.nodes.some((n) => n.id === oldId),
    plan.nodes.some((n) => n.id === oldId) ? '★ 它又出现了' : '计划里没有 ✓');
  if (newId) {
    const nn = plan.nodes.find((n) => n.id === newId);
    check('接替它的 ' + newId + ' 在（素材图 ' + imgId + '）',
      !!nn && Number(nn.image_id) === imgId, nn ? 'image_id=' + nn.image_id : '（没有）');
  }
}
// 「返回列表」应该挪到了左上角（参考图的位置）——这里只验它在、文案对
check('左上角有「返回菜单」按钮', textOf(ri, 'action.back') === '返回菜单',
  JSON.stringify(textOf(ri, 'action.back')));
// 右下角：计数 + 放大镜（参考图的 0/6 + 🔍）
// ★ 2026-10-05 改判（依据，不是放宽）：原来断言「`action.hint` 的文案就是放大镜」——
//   而旧的 `action.hint` **文字按钮已按设计删除** ✗（`ui_controller.lua:1796-1797`：
//   「放大镜的入口 = `hex.hint`（图上那枚，已接 `hint` 动作）—— 旧的 `action.hint` 文字按钮已删
//   （与本轮右上三键同样的理由：与 `hex.hint` 重叠且动作重复）」）。
//   实测：`layout-plan.json` 里 `action.hint` = 0。
//   ⇒ 反转成哨兵：`action.hint` **重新出现就是红** ✓；它的接替者 `hex.hint` 已在上面的
//     `OLD_TEXT_KEYS` 循环里锁过（控件在 + 素材图 100120 对）✓
check('右下角旧文字「放大镜」按钮 action.hint 按设计不存在（入口已改成 hex.hint）',
  !plan.nodes.some((n) => n.id === 'action.hint'),
  plan.nodes.some((n) => n.id === 'action.hint') ? '★ 它又出现了' : '计划里没有 ✓');
await shot(c, 't05-reset.png');

// ── 6. X 标记（单击空格直接切 ✗）────────────────────────────────────────────
// 切回放置模式
await click('action.q.place'); await tick(0.05);

// ── 7. 未摆满时「提交」应当是禁用的 ───────────────────────────────────────
console.log('\n=== 7. 未摆满时「提交」应禁用');
ri = await get();
// ★ 2026-10-05 改判（依据，不是放宽）：原来断言 `action.submit`「不可交互 + 文案提示要先摆满」——
//   而 `action.submit` **已按设计删除** ✗（`ui_controller.lua:1718-1729`：旧文字键与 `hex.submit`
//   重叠且动作重复，已删；`ui_controller.lua:1734-1735`：提交入口 = `hex.submit`）。
//   实测：`layout-plan.json` 里 `action.submit` = 0；运行树里 `interactable=undefined`（读不到，
//   因为**控件不存在**，不是「没有禁用」）。
//   ⇒ 反转成哨兵：`action.submit` **重新出现就是红** ✓；接替者 `hex.submit`
//     已在上面的 `OLD_TEXT_KEYS` 循环里锁过（控件在 + 素材图 100110 对）✓
check('旧文字「提交」按钮 action.submit 按设计不存在（提交入口已改成 hex.submit）',
  !plan.nodes.some((n) => n.id === 'action.submit'),
  plan.nodes.some((n) => n.id === 'action.submit') ? '★ 它又出现了' : '计划里没有 ✓');
check('此时没有指认面板', visibleOf(ri, 'modal') === false);

// ── 8. 揭示答案 → 提交 → 指认 ─────────────────────────────────────────────
console.log('\n=== 8. 揭示 → 提交 → 两段式指认');ri = await get();
check('揭示后摆满（5/5）', /5 \/ 5/.test(textOf(ri, 'hud.progress') || ''), textOf(ri, 'hud.progress'));
await ss('t07-revealed.png');

await clickConfirm('action.submit'); await tick(0.05);
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

// ══ 附加：X 标记（放在最后，因为它需要"干净状态"，必须先重启本关）══
console.log('\n=== 6. X 标记（单击空格直接切 ✗，不再需要工具按钮）');
// ★★ 2026-09-29：`action.q.x` 已随底部操作条一起删除（用户要求）。
//   新的操作逻辑：**未选人物时单击空格 = 直接切 ✗**，不需要先选工具。
//
//   ⚠️ 前置状态问题：第 4 步「双击预放置」按设计**不会取消选中**，所以此刻仍有角色被选中；
//   而「选中人物时单击空格」是**预放置**、不是 ✗。
//   ⇒ 不再去猜当前选中态（试过按缩放找选中卡片，不可靠），
//     直接**重启本关**拿到干净状态再验证 —— 断言不该依赖上文残留的隐式状态。
await c.play('start', {}); await enterLevel(c, tick); await tick(0.2);
ri = await get();
await click('cell.4.4'); await tick(0.05);
ri = await get();
const xNode = childOf(ri, 'cell.4.4', 'x');
check('X 标记已显示', !!xNode && xNode.visible !== false, 'visible=' + (xNode && xNode.visible));
await ss('t06-xmark.png');

  check('结案（独自作案）→ 出现结果面板',
    !!textOf(ri, 'modal.body'), JSON.stringify((textOf(ri, 'modal.body') || '').slice(0, 60)));
  await ss('t10-result.png');
}

// ── 8b. 「从存档点开始」的完整闭环（2026-09-30）────────────────────────────
//
//   必须放在**玩过一关之后** —— 因为「从存档点开始」读的正是"最近游玩记录"，
//   而记录是在点卡片切关时落盘的（`Murdoku.remember_level`）。
//   开机时测只能测到"没有记录"那条分支（第 0 节已经测过）。
console.log('\n=== 8b. 从存档点开始（玩过之后）');
{
  // 退出关卡 → 应该回到**整屏选关**（用户要求，参考原作）
  await clickConfirm('action.back'); await tick(0.2);
  let r3 = await get();
  check('退出关卡回到选关界面（不是弹窗、也不是主页）',
    visibleOf(r3, 'select') === true, 'select=' + visibleOf(r3, 'select'));
  await click('select.back'); await tick(0.2);
  r3 = await get();
  check('「返回主页」能回主页', visibleOf(r3, 'home') === true);
  // 现在应该**有**游玩记录了 ⇒ 点「从存档点开始」应当直接进关，而不是提示"没有记录"
  await click('home.continue'); await tick(0.3);
  r3 = await get();
  check('有记录时「从存档点开始」直接进关',
    visibleOf(r3, 'board') === true && visibleOf(r3, 'home') === false,
    'board=' + visibleOf(r3, 'board') + ' home=' + visibleOf(r3, 'home')
    + ' toast=' + JSON.stringify(textOf(r3, 'hud.toast')));
}

// ── 8c. 棋盘上的房间名标签（参考《派蒙的执律庭实习》：每个房间右下角写房间名）────
//
//   ⚠️ 关卡数据里**没有房间名**，所以显示的是中性的「区域 N」——这是**有意为之**：
//     宁可显示占位，也不编一个假名字。关卡里写了 `room_names = {...}` 就会自动变真名。
{
  // 回到关卡里（上面 8b 已经把界面停在关卡里了）
  const k = indexTree(ri).get('room.label.1');
  const txt = textOf(ri, 'room.label.1') || '';
  check('棋盘上有房间名标签', !!k && k.visible === true, 'visible=' + (k ? k.visible : 'NA'));
  check('房间名是「区域 N」占位（关卡没写 room_names 时不编名字）',
    /^区域 \d+$/.test(txt.trim()), JSON.stringify(txt));
  // 几何必须是**真实尺寸**，不能是 2×2 的小点
  //   （跨关卡取并集时，"第一次出现"的那份几何会留下 —— 占位给 2×2 就会永久缩成小点）
  const w = k && k.box && k.box.width;
  check('房间名标签有真实尺寸（不是 2×2 占位）', typeof w === 'number' && w > 20,
    '宽=' + w);
  // ★ 更关键的一条：**标签不许重叠**。
  //
  //   踩过的坑：`room.label.*` 是存档里的控件，而适配器有 `respect_editor_rect`
  //   （编辑器几何优先）⇒ 三个标签**全被按在存档里那一份几何上**，中心完全重合
  //   （模拟器里三个 box 一模一样，真机上是三个字叠在一起）。
  //   ⇒ 给这类节点加了显式标记 `pos_runtime = true`，走"运行时实例化"同一条路。
  {
    const spots = [];
    for (let j = 1; j <= 8; j++) {
      const kk = indexTree(ri).get('room.label.' + j);
      if (!kk || kk.visible !== true || !kk.box) continue;
      spots.push(kk.box.left + ',' + kk.box.bottom);
    }
    const uniq = new Set(spots);
    check('房间名标签彼此不重叠（每个房间一个位置）', uniq.size === spots.length,
      spots.length + ' 个可见标签，位置 ' + uniq.size + ' 个：' + spots.join(' '));
  }
}

// ── 9. 收尾 ───────────────────────────────────────────────────────────────
dumpJson('t99-final.json', ri);
const errsLog = (ri.logs || []).filter((l) => l.level === 'error');
console.log('\n运行期 error 日志 ' + errsLog.length + ' 条');
for (const l of errsLog.slice(0, 10)) console.log('  [error] ' + l.text);

// ── ★★★ 2026-10-01：**三个页面各自该显示什么** ─────────────────────────────
//
//   为什么加这条：原来藏屏幕用的是一张**9 个 id 的白名单**
//   （topbar/toolbar/left/board/right/toast/modal/intro/action.back），//   ⇒ 主页上会**同时看到棋盘格子、线索条、右侧三个按钮**。
//
//   已改成反向逻辑（只留 home/select 子树 + root）。这条断言锁的是
//   **用户一眼能看到的东西**：每个页面只出现该页面的控件。
{
  // ★ 2026-10-05 改判（依据，不是放宽）：名单里原来写的是 `action.undo` ——
  //   而这个**旧文字按钮已按设计删除** ✗ ⇒ 这条断言原来锁的是一个**不存在的控件**
  //   `vis(r,'action.undo')` 恒为 false ⇒ 恒过 ⇒ 等于**什么也没测** ✗，是最坏的那种「假绿」）。
  //   依据：`ui_controller.lua:1718-1729`（旧文字键与 `hex.*` 重叠且动作重复，已删）+
  //         `ui_controller.lua:1734-1735`（入口 = `hex.submit` / `hex.redo` / `hex.undo` / `hex.hint`）。
  //   实测：`layout-plan.json` 里 `action.undo` = 0，`hex.undo` 在（visible=true, w=h=70, 素材 100127）。
  //   ⇒ 换成它**真正的接替者 `hex.undo`** ✓ —— 这不是放宽，是把一条恒真断言**变回真断言**：
  //     主页/选关时 `hex.*` 必须藏起来（`ui_controller.lua:1213-1216`「图标（hex.*）只在关卡内显示」），
  //     一旦脚本漏藏 ⇒ **这条会红** ✓（原来那条永远红不了）。
  const LEVEL_ONLY = ['board', 'clues', 'topbar', 'right', 'cell.1.1', 'hex.undo', 'hud.title'];
  const vis = (ri2, id) => visibleOf(ri2, id) === true;
  await c.play('start', {}); await tick(0.35);
  let r = await get();
  check('主页：只显示主页（关卡内的东西都藏起来）',
    vis(r, 'home') && !vis(r, 'select') && LEVEL_ONLY.every((id) => !vis(r, id)),
    'home=' + vis(r, 'home') + '，关卡内的还可见 ' + LEVEL_ONLY.filter((id) => vis(r, id)).length + ' 个');
  await click('home.select'); await tick(0.35);
  r = await get();
  check('选关：只显示选关',
    vis(r, 'select') && !vis(r, 'home') && LEVEL_ONLY.every((id) => !vis(r, id)),
    'select=' + vis(r, 'select') + '，关卡内的还可见 ' + LEVEL_ONLY.filter((id) => vis(r, id)).length + ' 个');
  await click('select.card.2'); await tick(0.3);
  await click('intro.skip'); await tick(0.3);
  r = await get();
  // ★ 2026-10-05：明细里原来报的是 `action.undo=` —— 同一个已删控件的残留，一并换成 `hex.undo` ✓
  check('关卡内：关卡的 UI 都在，主页/选关都藏了',
    !vis(r, 'home') && !vis(r, 'select') && vis(r, 'board') && vis(r, 'clues') && vis(r, 'hex.undo'),
    'board=' + vis(r, 'board') + ' clues=' + vis(r, 'clues') + ' hex.undo=' + vis(r, 'hex.undo'));
}

console.log('\n════════ 结果：' + pass + ' 通过 / ' + fail + ' 失败 ════════');
await c.play('stop', {});
await c.dispose();
process.exit(fail === 0 ? 0 : 1);
