#!/usr/bin/env node
/**
 * verify_longpress_sentinel.mjs —— ★ 破坏性验证：把长按的时钟改回"累加时钟"（= 修复前 ✗），
 * 确认新加的那条判据**真的会红** ✓；然后**逐字节还原** ✓。
 */
import fs from 'node:fs';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const REPO = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku';
const P = REPO + '/lua/ui_controller.lua';
const LUA = process.env.LOCALAPPDATA + '/Programs/Lua/bin/lua.exe';

const orig = fs.readFileSync(P, 'utf8');
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const shaFile = () => sha(fs.readFileSync(P, 'utf8'));

// 找 gesture_now 整个函数体，换成"只用 self.now"
const lines = orig.split('\n');
const a = lines.findIndex((l) => l.startsWith('local function gesture_now(self)'));
if (a < 0) { console.error('✗ 找不到 gesture_now'); process.exit(2); }
let b = -1;
for (let i = a + 1; i < lines.length; i++) if (/^end\s*$/.test(lines[i])) { b = i; break; }
if (b < 0) { console.error('✗ 找不到 gesture_now 的收尾'); process.exit(3); }

const patched = lines.slice(0, a).concat([
  'local function gesture_now(self)',
  '  if self ~= nil and type(rawget(self, "now")) == "number" then return rawget(self, "now") end',
  '  return 0',
  'end',
], lines.slice(b + 1)).join('\n');

fs.writeFileSync(P, patched, 'utf8');
let red = false;
try { execFileSync(LUA, ['tests/input_logic.lua'], { cwd: REPO, stdio: 'pipe' }); }
catch { red = true; }
fs.writeFileSync(P, orig, 'utf8');

console.log(`改回「累加时钟」⇒ input_logic 变红 = ${red ? '✅ 是（哨兵有效）' : '❌ 否（哨兵无效）'}`);
console.log(`还原后逐字节相同 = ${shaFile() === sha(orig) ? '✅' : '❌'}`);
process.exit(red && shaFile() === sha(orig) ? 0 : 1);
