#!/usr/bin/env node
/**
 * sabotage_check.mjs —— ★ 破坏性验证：故意把"棋盘接线"改坏，确认**回归会红**。
 *
 * 为什么必须做 ✗：绿灯只证明"现在没红"✓ —— ★ **不证明"坏掉会被抓到"** ✗
 *   （★ 本项目的独立复核者就抓到过一次"破坏没生效 ⇒ 5 套假绿" ✓）
 *
 * 做法 ✓：备份 → 改一处 → 跑指定套件 → **逐字节还原** → 核对 sha256 ✓
 * 判据 ✓：每一类破坏都**至少有一套变红** ✓；还原后**全部回到绿** ✓
 */
import fs from 'node:fs';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const REPO = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku';
const SRC = REPO + '/lua/ui_controller.lua';
const LUA = process.env.LOCALAPPDATA + '/Programs/Lua/bin/lua.exe';
const BAK = REPO + '/.sabotage_bak.lua';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const suiteRed = (t) => {
  try { execFileSync(LUA, ['tests/' + t + '.lua'], { cwd: REPO, stdio: 'pipe' }); return false; }
  catch { return true; }
};

const SUITES = ['board_wiring_e2e', 'cell_mark_letter', 'row_letter_map', 'row_letter_stability', 'clue_slots', 'selection_residue'];
// ★★★★★★★★ 2026-10-15 **这一套测的是【打包产物】，不是源码** ✗✓✓
//
//   ★★★ 为什么必须单独列出来 ✗：★ `tests/grid_cost.lua` 读的是
//     `dist/client_script.lua`（★ 默认参数 ✓ 见它的 §前置 ✓）
//   ★★ 而破坏是改**源码**的 ⇒ ★ **不重新打包 ⇒ 它测的还是旧包** ✓✓
//     ⇒ ★★ 表现就是把破坏**静默放过** ✗ —— ★ 正是 P7 里"破坏没到达被测代码"那一条 ✓
//   ★ 判据出处 ✓：★ 我第一次跑 `I` 就是"无人抓" ✓ ★ 重新打包之后立刻变红 ✓（实测过 ✓）
//   ⇒ ★ 所以这一类套件跑之前**必须先打包** ✓
const BUNDLED_SUITES = ['grid_cost'];
const bundleOnce = () => {
  try { execFileSync(LUA, ['tools/bundle_client_script.lua'], { cwd: REPO, stdio: 'pipe' }); return true; }
  catch { return false; }
};

const original = fs.readFileSync(SRC, 'utf8');
fs.writeFileSync(BAK, original, 'utf8');
const origSha = sha(SRC);

// 每一类破坏：{ 名字, 找什么, 换成什么 }
const sabotages = [
  // ★★ 2026-10-11 锚点更新 ✗✓ —— ★ 原来指的是 `local _key = tonumber(_pid) or _pid` ✓
  //   ★ 而**那一行在 v186 已经删掉了** ✗（★ 它正是"先到先得"那段"吃掉 D/E"的元凶 ✓）
  //   ★★ 于是这条破坏**静默失效** ✓ ⇒ ★ 报"破坏未生效" ✓
  //     ⇒ ★ 这个工具**自己发现了自己过期** ✓（★ 值得表扬的设计 ✓ 不是静默放过 ✓）
  //   ⇒ ★ 改成钉**现在那一行写入** ✓（★ 行号才是键 ✓）
  ['A 写侧 letter 键改错（行号 +100）',
    'Controller._row_letter[_pid] = tostring(_lt)',
    'Controller._row_letter[(_pid or 0) + 100] = tostring(_lt)'],
  ['B 写侧 face 键改错（行号 +100）',
    'local _key_face = _rowno',
    'local _key_face = (_rowno or 0) + 100'],
  ['C 查侧 棋子→行号 改错（+1）',
    'local n = Controller._pos_of_piece(Controller._piece_core, id)',
    'local n = (Controller._pos_of_piece(Controller._piece_core, id) or 0) + 1'],
  ['D letter_of 退回字符串键（主路失效）',
    '  return m[n] or m[tostring(n)]',
    '  return m[tostring(n)]'],
  ['E 换关不清棋子表（留下上一关的）',
    '    Controller._piece_core = nil\n    Controller._piece_id_cache = nil',
    '    -- (去掉清理)'],
  ['F 不补那一趟（`_row_need` 恒按 _grid_in_refresh）',
    '  local _row_need = (self._grid_in_refresh == true)\n  if not _row_need then\n    local m0 = rawget(Controller, "_row_letter")\n    _row_need = (type(m0) ~= "table") or (m0[pos] == nil)\n  end',
    '  local _row_need = (self._grid_in_refresh == true)'],
  ['G 补那一趟改成"整张表非空就算"（按行判退化成按表判）',
    '_row_need = (type(m0) ~= "table") or (m0[pos] == nil)',
    '_row_need = (type(m0) ~= "table") or (next(m0) == nil)'],
  // ★★★★★★★★ 2026-10-15 **新增：选中残留那一类** ✗✓✓
  //
  //   ★★★ 用户报的（★ 原话 ✓）：「**放置 v 后选择了 d，一不小心把 v 取消了，
  //     点出来的标记是 v 的，但显示选择的 d，此时再长按放置，放的会是 v**」✓
  //   ★★ 根因 ✓：★ 卡片高亮原来是**独立的一份状态** ✗
  //     ⇒ ★ "选中变了但不是点卡片改的"（★ 拿起棋子 ✓）⇒ ★ 高亮**留在原地** ✓✓
  //   ★ 修法 ✓：★ 高亮降级成**派生值** ✓（★ 唯一写点 = `_sync_clue_focus` ✓）
  //   ⇒ ★★ 这一条破坏 = **让那个派生恒等于"上一次的值"** ✗
  //     ⇒ ★ 高亮**再也不跟着选中走** ✓ ⇒ ★ `selection_residue` 必须变红 ✓✓
  //   ★ 判据出处 ✓：`tests/selection_residue.lua`
  //     （★ 它在**修复前**的代码上是 6 红 ✓ —— ★ 已实测 ✓ 能红能绿 ✓）
  ['H 选中残留：卡片高亮不再跟着 `core.selected` 派生',
    'local want = ((pos ~= nil) and pos > 0) and pos or nil',
    'local want = rawget(self, "_clue_sel_pos")'],
  // ★★★★★★★★ 2026-10-15 **新增：让"高亮"恒亮 / 恒灭（★ 打掉 P3 的反向半边）** ✗✓✓
  //
  //   ★★★ 为什么必须单独破坏这一下 ✗：
  //     ★ H 那条只能让**派生值**错 ✗ —— ★ 而 `grid_cost` 的 K 段是**自己推 `focused_clue`** ✓
  //       （★ 它直接调 `_on_grid_item_click` ✓）⇒ ★ 两条路径碰不到一起 ✓✓
  //     ★★ 所以"样式到底有没有被算成 `clue.focus`"这件事**没人打得到** ✗
  //   ⇒ ★ 把规划里那一行**钉死成 `clue`** ✓ —— ★ 也就是"**永远不高亮**" ✓
  //     ★ 一个"永不高亮"的实现 ⇒ ★ `grid_cost` 的 K 段必须红 ✓✓（P3 反向半边 ✓）
  ['I 高亮恒灭：规划里那一条永不取 `clue.focus`',
    'local style = (self.focused_clue == i) and "clue.focus"',
    'local style = false and "clue.focus"'],
];

let allGood = true;
// ★★★★★★★★ 2026-10-11 **锚点匹配要容忍 CRLF** ✗✓✓（★ 两个破坏静默失效过一次 ✓）
//
//   ★★★ 症状 ✓：★ E 与 F 报「**没匹配上（破坏未生效）**」✗
//     ★★ 而它们要找的代码**明明就在源码里** ✓ —— ★ 我逐行核过 ✓
//   ★ 根因 ✓：★ **本项目源码是 CRLF** ✗ ★ 而脚本里的跨行锚点写的是 `\n`（LF）✓
//     ⇒ ★ 多行锚点**永远匹配不上** ✓✓
//   ★★ 值得表扬 ✓：★ 这个工具**没有静默放过** ✗ —— ★ 它明说"没匹配上" ✓
//     ★ 这正是"**破坏必须确认到位**"那条纪律 ✓（★ 长按那轮我踩过同一个坑 ✓）
//   ⇒ ★ 修法 ✓：★ **把"源码"与"锚点"都归一成 LF 再比** ✗ ——
//     ★ 改完写盘时**统一用 LF** ✓ ★ 反正 Lua 不在乎 ✓（★ 还原时有原始字节 ✓）
const originalLF = original.replace(/\r\n/g, '\n');

// ★★★★★★★★ 2026-10-11 **"还原"必须【自己验一遍】，而且不许留下破坏痕迹** ✗✓✓
//
//   ★★★ 事故 ✓（★ 2026-10-11 本轮 ✓）：★ 跑完这轮之后，源码里**留着**一处破坏 ✗：
//     `if p ~= nil and false then p.dt = ... end` ✓
//     ⇒ ★★ 长按**全废**（★ 12 条断言红 ✓）★ 而**当时没报错** ✓✓
//   ★ 为什么会漏 ✗（★ 我没能复现，所以**不猜** ✓）：★ 关键是**它没被发现** ✓
//   ⇒ ★★ 两道护栏 ✓（★ 不依赖"哪一步出的错" ✓）：
//     ★ ① ★ 还原**写完就回读验** ✓ ★ 不一致 ⇒ **再写一次** ✓
//     ★ ② ★ 收尾**扫一遍"破坏标记"** ✗ —— ★ 只要源码里还剩 `and false` / `if false`
//       ★ 之类的痕迹 ⇒ ★ **大声报错** ✓✓（★ 这一类痕迹**本来就不该出现在源码里** ✓）
//   ★ 为什么 ② 有用 ✓：★ 所有破坏都是"**把某处改成永假**"的形状 ✓
//     ⇒ ★ 留没留下**一看就知道** ✓ ★ 不用理解当时发生了什么 ✓✓
function restoreAndVerify() {
  for (let i = 0; i < 3; i++) {
    fs.writeFileSync(SRC, original, 'utf8');
    if (sha(SRC) === origSha) return true;
  }
  return false;
}
const LEFTOVER = /\b(?:and|if)\s+false\b/;

for (const [name, find, repl] of sabotages) {
  const patched = originalLF.split(find).join(repl);
  if (patched === originalLF) { console.log(`  ⚠️ ${name}：没匹配上（破坏未生效）`); allGood = false; continue; }
  fs.writeFileSync(SRC, patched, 'utf8');
  // ★★ 先打包，再跑"读产物"的那几套 ✗（★ 否则破坏根本到不了被测代码 ✓ P7 ✓）
  const bundled = bundleOnce();
  if (!bundled) console.log('  ⚠️ 打包失败 —— 读产物的那几套本轮结果不可信 ✗');
  const red = SUITES.filter(suiteRed).concat(bundled ? BUNDLED_SUITES.filter(suiteRed) : []);
  const restored = restoreAndVerify();
  // ★ 还原之后**必须再打一次包** ✗ —— ★ 否则 `dist/` 里留着"被破坏过的产物" ✓✓
  //   （★ 后续别的套件/交付会拿到那份坏包 —— ★ 这与"源码留破坏"一样危险 ✓）
  const rebundled = bundleOnce();
  if (!restored || !rebundled) allGood = false;
  const caught = red.length > 0;
  console.log(`  ${caught ? '✅' : '❌'} ${name}　→ 变红：${caught ? red.join(', ') : '（无人抓 ✗）'}　还原=${restored}　重打包=${rebundled}`);
  if (!caught || !restored) allGood = false;
}

// ★ 收尾自检 ✓：源码里**不许留下任何"永假"痕迹** ✗
const finalSrc = fs.readFileSync(SRC, 'utf8');
const leftovers = finalSrc.split(/\r?\n/)
  .map((l, i) => [i + 1, l])
  .filter(([, l]) => LEFTOVER.test(l));
if (leftovers.length > 0) {
  console.error('\n✗✗ 源码里**还留着破坏痕迹** ✗ —— 这一轮的结果**全部作废** ✓');
  leftovers.slice(0, 6).forEach(([n, l]) => console.error(`    ${n}: ${l.trim()}`));
  console.error('   ★ 修法：git checkout -- lua/ui_controller.lua　然后重跑 ✓');
  allGood = false;
}

fs.unlinkSync(BAK);
console.log(`\n最终 sha256 与原始一致：${sha(SRC) === origSha}`);
console.log(`源码里没有残留破坏痕迹：${leftovers.length === 0}`);
console.log(allGood ? '✅ 全部破坏被抓 + 全部还原成功 + 源码干净' : '❌ 有破坏没被抓 / 还原失败 / 源码有残留');
process.exit(allGood ? 0 : 1);
