// [[----------------------------------------------------------------------------
//   tools/_wip/unnest_fix.mjs —— 原子修 `main.lua` 的节流嵌套（Round 59）
//
//   问题：`if (frames % 300 == 0)`（**L1495**）的 `end` 位置错了 ✗ ⇒
//         它把 `if (frames % 30 == 0)`（**L1592**）套住了 ⇒ 注释写"每 30 帧"实际**每 300 帧** ✗
//   处方（坐标由 `check_nesting --depths` 权威确定 ✓）：
//     ① 在 **L1592** 之前插一个 `end`  ⇒ 关掉那个 `%300` 的 if
//     ② 删掉 **L1696** 的 `end`        ⇒ 它原本关的就是那个 if（删掉后 %30 块回到 OnUpdate 顶层）
//     ⚠️ 两处**必须一起改** ✗ —— 只改一处会让块深度 ±1 ⇒ 编译不过 ✓
//
//   安全性（本项目在这一点上栽过 6 次 ✗）：
//     · **原子**：读写各一次，中途不落半成品 ✓
//     · **改前校验锚点内容**（行号可能漂移 ✓ 内容不匹配就直接退出，不动文件 ✓）
//     · **改后用独立判据验证**：`luac -p`（编译 ✓）+ `check_nesting`（[节流嵌套] 0 处 ✓）
//     · **验证失败 ⇒ 自动回滚**到原文 ✓（不留坏状态 ✓）
//     · 写回**显式 UTF-8 无 BOM** ✓（.lua 必须无 BOM ✓）
//   跑法：node tools/_wip/unnest_fix.mjs            # dry-run（只校验锚点与推演，不写）
//         node tools/_wip/unnest_fix.mjs --apply    # 真改（带自动回滚）
//  ----------------------------------------------------------------------------]]--

import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const FILE = 'lua/main.lua';
const APPLY = process.argv.includes('--apply');
const LUAC = join(process.env.LOCALAPPDATA, 'Programs', 'Lua', 'bin', 'luac.exe');

const original = readFileSync(FILE, 'utf8');
const lines = original.split('\n');

// ---- 锚点（换算成 0-based）----
const A = 1592 - 1;   // 插 `end` 的位置：这一行之前
const B = 1696 - 1;   // 要删掉的 `end`

function fail(msg) { console.error('  ✗ ' + msg + '　（未改文件 ✓）'); process.exit(2); }

// ---- 改前校验：内容必须对得上（防行号漂移 ✗）----
if (!/^\s*if scr_now\s*==/.test(lines[A]) || !/%\s*30/.test(lines[A]))
  fail(`L${A + 1} 不是那个 %30 的 if：${JSON.stringify(lines[A])}`);
if (lines[B].trim() !== 'end')
  fail(`L${B + 1} 不是单独一个 end：${JSON.stringify(lines[B])}`);
// L1495 必须是那个 %300 的 if（旁证 ✓）
if (!/%\s*300/.test(lines[1495 - 1]))
  fail(`L1495 不是 %300 的 if：${JSON.stringify(lines[1495 - 1])}`);

console.log(`  锚点校验通过 ✓`);
console.log(`    L1495  %300 的 if   ：${lines[1494].trim()}`);
console.log(`    L${A + 1}  插 end 于其前：${lines[A].trim()}`);
console.log(`    L${B + 1}  删这个 end    ：${JSON.stringify(lines[B])}`);

// ---- 直接构造改后文本（先删后插，避免索引位移 ✗）----
const out = lines.slice();
out.splice(B, 1);                 // 删 L1696
out.splice(A, 0, '    end');      // 在 L1592 前插一个 end（缩进 4 格，与 d1 的 if 对齐 ✓）
const result = out.join('\n');

if (!APPLY) { console.log('  （dry-run：没写文件 ✓ 加 --apply 才写）'); process.exit(0); }

// ---- 写 → 验证 → 失败回滚 ----
writeFileSync(FILE, result, 'utf8');
const check = () => {
  try { execFileSync(LUAC, ['-p', FILE], { stdio: 'ignore' }); } catch { return '编译不过 ✗'; }
  try {
    const o = execFileSync('node', ['tools/audit/check_nesting.mjs'], { encoding: 'utf8' });
    if (!/\[节流嵌套\]\s*0\s*处/.test(o)) return '仍有 [节流嵌套] ✗';
    if (!/不平衡\s*0\s*个文件/.test(o)) return '块深度不平衡 ✗';
    return null;
  } catch { return 'check_nesting 跑失败'; }
};
const bad = check();
if (bad) {
  writeFileSync(FILE, original, 'utf8');
  console.error(`  ✗ 验证失败（${bad}）⇒ **已自动回滚**到原文 ✓ 文件现在是好的 ✓`);
  process.exit(3);
}
console.log('  ✓ 已写入并通过两条独立判据：luac -p 编译 ✓ + [节流嵌套] 0 处 ✓ + 深度平衡 ✓');
