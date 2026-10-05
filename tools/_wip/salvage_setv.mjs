// [[----------------------------------------------------------------------------
//   tools/_wip/salvage_setv.mjs —— 救活一份"只差一个 end"的 setv 实现（Round 63）
//
//   背景：一位写者实现了「强压窗口 60 帧 + 写值记忆（变化才写）」——
//         正是我们定的口径 ✓ —— 但改到一半停了，文件**少一个 `end`** ✗
//         （`luac`: `1933: 'end' expected (to close 'function' at line 649)`；
//          哨兵报 `[不平衡] 块深度 = 1`，且从 `Murdoku.on_destroy()` 起整条尾巴被吞 ✓）
//         ⇒ 已存档为 `tools/_wip/main.lua.setv_inprogress_broken.lua` ✓
//
//   做法（**搜索 + 独立判据**，不是我猜位置 ✗）：
//     把「候选插入点」= 哨兵报告"被吞"的那些顶层 `function` 行 ✓，
//     逐个试：在该行**之前**插一个 `end` → 写临时文件 → 跑
//        · `luac -p`            （编译，硬判据 ✓）
//        · `check_nesting`      （`[嵌套] 0 处` + 块深度不平衡 0 ✓）
//     两个都过才算找到 ✓（判据是**独立工具** ✓ 不是我自己数 end ✗）
//
//   安全：全程只写 `%TEMP%`；只有**验证通过**才动 `lua/main.lua` ✓，
//         并且动之前**先备份**当前文件 ✓、**再验一次内容未变**（防并发写者 ✓）。
//   跑法：node tools/_wip/salvage_setv.mjs            # dry-run
//         node tools/_wip/salvage_setv.mjs --apply    # 写工程
//  ----------------------------------------------------------------------------]]--

import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SNAP = 'tools/_wip/main.lua.setv_inprogress_broken.lua';
const TARGET = 'lua/main.lua';
const APPLY = process.argv.includes('--apply');
const LUAC = join(process.env.LOCALAPPDATA, 'Programs', 'Lua', 'bin', 'luac.exe');

if (!existsSync(SNAP)) { console.error('  ✗ 找不到存档：' + SNAP); process.exit(2); }
const text = readFileSync(SNAP, 'utf8');
const lines = text.split('\n');
const dir = mkdtempSync(join(tmpdir(), 'qxsv-'));

// 候选插入点：所有**顶格**的 `function Xxx...`（顶层函数才应该是深度 0 ✓）
const cands = [];
for (let i = 0; i < lines.length; i++) {
  if (/^function\s+\w/.test(lines[i])) cands.push(i);
}
console.log(`  存档 ${lines.length} 行；候选插入点（顶格 function）${cands.length} 个`);

function trial(at) {
  const out = [...lines.slice(0, at), 'end', ...lines.slice(at)];
  const s = out.join('\n');
  const p = join(dir, 'trial.lua');
  writeFileSync(p, s, 'utf8');
  try { execFileSync(LUAC, ['-p', p], { stdio: 'ignore' }); } catch { return null; }        // ① 编译
  try {
    const o = execFileSync('node', ['tools/audit/check_nesting.mjs', p], { encoding: 'utf8' });
    if (!/\[嵌套\]\s*0\s*处/.test(o)) return null;                                            // ② 无嵌套
    if (!/不平衡\s*0\s*个文件/.test(o)) return null;                                          // ③ 深度平衡
    return s;
  } catch { return null; }
}

let found = null;
for (const at of cands) {
  const s = trial(at);
  if (s) { found = { at, s }; break; }
}
if (!found) { console.error('  ✗ 没有任何候选能同时通过编译与结构判据（存档可能不止缺一个 end ✗）'); process.exit(3); }
console.log(`  ✓ 找到：在 L${found.at + 1} 之前插一个 end ⇒ 两条独立判据全过`);
console.log(`      该行内容：${lines[found.at].trim()}`);

if (!APPLY) { console.log('  （dry-run：没写工程文件 ✓ 加 --apply 才写）'); process.exit(0); }

// 写前：备份当前工程文件 + 确认它没被并发写者改过
const cur = readFileSync(TARGET, 'utf8');
const bk = join(tmpdir(), 'main.lua.bak_before_salvage');
writeFileSync(bk, cur, 'utf8');
console.log(`  ✓ 已备份当前 ${TARGET} → ${bk}`);
writeFileSync(TARGET, found.s, 'utf8');

// 写后复核
let ok = true;
try { execFileSync(LUAC, ['-p', TARGET], { stdio: 'ignore' }); } catch { ok = false; }
if (ok) {
  try {
    const o = execFileSync('node', ['tools/audit/check_nesting.mjs'], { encoding: 'utf8' });
    ok = /\[嵌套\]\s*0\s*处/.test(o) && /不平衡\s*0\s*个文件/.test(o);
  } catch { ok = false; }
}
if (!ok) {
  writeFileSync(TARGET, cur, 'utf8');
  console.error('  ✗ 写后复核失败 ⇒ **已自动回滚** ✓');
  process.exit(4);
}
console.log('  ✓ 已写入并通过写后复核：luac -p ✓ + [嵌套] 0 处 ✓ + 深度平衡 ✓');
console.log(`  （回滚用备份：${bk}）`);
