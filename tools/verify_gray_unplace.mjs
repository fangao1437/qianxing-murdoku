#!/usr/bin/env node
/**
 * verify_gray_unplace.mjs —— ★★ 破坏性验证：把 v188 之后补的两处"注销"信号去掉
 *   （= 用户报"取消放置之后 gray 不会恢复"的那一版 ✗），
 *   确认 `tests/gray_unplace.lua` **真的会红** ✓；然后**逐字节还原** ✓。
 *
 *   ⚠️ ★ 破坏必须**语法合法** ✗ ＋ ★ 必须确认**真的到位** ✗
 *     —— ★ 这两条我在长按那轮各踩过一次 ✓（见 `verify_longpress.mjs` 的注释 ✓）
 */
import fs from 'node:fs';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const REPO = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku';
const P = REPO + '/lua/ui_controller.lua';
const LUA = process.env.LOCALAPPDATA + '/Programs/Lua/bin/lua.exe';
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const orig = fs.readFileSync(P, 'utf8');
const origSha = sha(orig);

// 拿起那条路的重填信号（★ 变成永假 ✓ 语法不动 ✓）
const A = '      self._grid_refill_pending = true\n    else\n      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)';
const A_BAD = '      if false then self._grid_refill_pending = true end\n    else\n      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)';

let n = 0, cur = orig;
if (cur.includes(A)) { cur = cur.replace(A, A_BAD); n++; }
else console.error('✗ 锚点 A（拿起）没找到');
fs.writeFileSync(P, cur, 'utf8');

const b = spawnSync(LUA, ['tools/bundle_client_script.lua'], { cwd: REPO, encoding: 'utf8' });
let red = false, tail = '';
if (b.status !== 0) {
  console.error('✗ 打包失败 ⇒ 破坏语法不合法 ⇒ 结果无效');
  console.error(((b.stderr || '') + '').split('\n').slice(0, 4).join('\n'));
  red = true; tail = '(打包失败)';
} else {
  const bundle = fs.readFileSync(REPO + '/dist/client_script.lua', 'utf8');
  const reached = bundle.includes('if false then self._grid_refill_pending = true end');
  console.log('破坏数=' + n + '　进产物=' + reached);
  if (!reached) console.error('✗ 破坏没进产物 ⇒ 结果无效');
  const r = spawnSync(LUA, ['tests/gray_unplace.lua'], { cwd: REPO, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  red = r.status !== 0;
  tail = ((r.stdout || '') + '').split('\n').filter((l) => l.includes('FAIL') || l.includes('passed,')).slice(0, 4).join('\n');
}

fs.writeFileSync(P, orig, 'utf8');
spawnSync(LUA, ['tools/bundle_client_script.lua'], { cwd: REPO, encoding: 'utf8' });
const restored = sha(fs.readFileSync(P, 'utf8')) === origSha;

console.log('去掉「拿起 ⇒ 请求重填」⇒ gray_unplace 变红 = ' + (red ? '✅ 是（哨兵有效）' : '❌ 否（哨兵无效）'));
if (tail) console.log(tail.split('\n').map((l) => '    ' + l.trim()).join('\n'));
console.log('还原后逐字节相同 = ' + (restored ? '✅' : '❌'));
process.exit(red && restored ? 0 : 1);
