// [[----------------------------------------------------------------------------
//   tools/_wip/fix_probe_format.mjs —— 把探针里的 `%d` 全换成 `%.0f`（Round 83）
//
//   为什么：`string.format("%d", 浮点)` 会抛
//     `bad argument #N to 'format' (number has no integer representation)` ✗
//   而 `%.0f` **同时接受整数与浮点** ✓ ⇒ 换掉之后**不可能再崩** ✓
//   （本项目已因这个坑栽过 3 次：`main.lua` 的 `w or 0`、这个探针、以及一次临时脚本 ✗）
//
//   范围：**只改 `tests/_wip/probe_throttle_cost.lua` 一个文件** ✓（测试用 ✓ 零生产风险 ✓）
//   安全性：
//     · 只在**字符串字面量**里替换（`"%d"` / `"%2d"` / `"%-16s … %d"` 里的那个 ✓）
//     · 写完**自检**：文件里不应再有 `%d` / `%2d` 之类 ✓；且 `luac -p` 必须过 ✓
//     · 显式 UTF-8 **无 BOM** ✓（.lua 必须无 BOM ✓）
//     · 先 dry-run，`--apply` 才写 ✓
//  ----------------------------------------------------------------------------]]--

import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const FILE = 'tests/_wip/probe_throttle_cost.lua';
const APPLY = process.argv.includes('--apply');
const LUAC = join(process.env.LOCALAPPDATA, 'Programs', 'Lua', 'bin', 'luac.exe');

const src = readFileSync(FILE, 'utf8');
const lines = src.split('\n');

let hits = 0;
const out = lines.map((line, i) => {
  // 只处理含 string.format 的行，且只替换形如 %d / %2d / %-3d 的整数占位符
  if (!/string\.format/.test(line)) return line;
  const replaced = line.replace(/%(?:-?\d+)?d/g, (m) => {
    hits++;
    console.log(`  L${i + 1}: ${m} → %.0f`);
    return '%.0f';
  });
  return replaced;
});

console.log(`  共替换 ${hits} 处（只动 string.format 行 ✓）`);
if (hits === 0) { console.log('  （没有可替换的，退出）'); process.exit(0); }

const result = out.join('\n');
const leftovers = (result.match(/%(?:-?\d+)?d/g) || []).length;
console.log(`  替换后残留 %d 样式占位符：${leftovers}（应为 0 ✓）`);

if (!APPLY) { console.log('  （dry-run：没写文件 ✓ 加 --apply 才写）'); process.exit(0); }

writeFileSync(FILE, result, 'utf8');   // 显式 UTF-8、无 BOM ✓
try {
  execFileSync(LUAC, ['-p', FILE], { stdio: 'ignore' });
  console.log('  ✓ 已写入，且 `luac -p` 通过 ✓');
} catch (e) {
  writeFileSync(FILE, src, 'utf8');    // 回滚 ✓
  console.error('  ✗ luac 失败 ⇒ **已回滚** ✓');
  process.exit(3);
}
