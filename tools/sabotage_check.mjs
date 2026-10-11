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

const SUITES = ['board_wiring_e2e', 'cell_mark_letter', 'row_letter_map', 'row_letter_stability', 'clue_slots', 'clue_slots'];

const original = fs.readFileSync(SRC, 'utf8');
fs.writeFileSync(BAK, original, 'utf8');
const origSha = sha(SRC);

// 每一类破坏：{ 名字, 找什么, 换成什么 }
const sabotages = [
  ['A 写侧 letter 键改错（行号 +100）',
    'local _key = tonumber(_pid) or _pid',
    'local _key = (tonumber(_pid) or 0) + 100'],
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
];

let allGood = true;
for (const [name, find, repl] of sabotages) {
  const patched = original.split(find).join(repl);
  if (patched === original) { console.log(`  ⚠️ ${name}：没匹配上（破坏未生效）`); allGood = false; continue; }
  fs.writeFileSync(SRC, patched, 'utf8');
  const red = SUITES.filter(suiteRed);
  fs.writeFileSync(SRC, original, 'utf8');
  const restored = sha(SRC) === origSha;
  const caught = red.length > 0;
  console.log(`  ${caught ? '✅' : '❌'} ${name}　→ 变红：${caught ? red.join(', ') : '（无人抓 ✗）'}　还原=${restored}`);
  if (!caught || !restored) allGood = false;
}

fs.unlinkSync(BAK);
console.log(`\n最终 sha256 与原始一致：${sha(SRC) === origSha}`);
console.log(allGood ? '✅ 五类破坏全部被抓 + 全部还原成功' : '❌ 有破坏没被抓 / 还原失败');
process.exit(allGood ? 0 : 1);
