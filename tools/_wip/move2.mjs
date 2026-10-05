// [[----------------------------------------------------------------------------
//   tools/_wip/move2.mjs —— 嵌套搬移（Round 48，**以独立判据搜索**）
//
//   与上一版（move_nested_methods.mjs，失败 ✗）的区别：
//     上一版**自己算深度** ✗（正则漏掉「if … then 后面还有注释」的行 ⇒ 深度全错
//       却因为"两边同样错"骗过了自检 ✗✗ —— 同源错误互相掩盖）。
//     这一版**不算深度** ✓，改成：
//       ① 只按**内容**定位两段的起点（`function Adapter:apply_ruler_layout` / `diagnose_overlap`）
//       ② 段的**结束行用"搜索 + 独立判据"确定**：
//          对每个候选结束行，生成结果 → 写进**临时副本** → 跑
//            · `luac -p`           （编译，硬判据 ✓）
//            · `check_nesting`     （[嵌套] 0 处 + 深度平衡 ✓）
//          两个都过才算找到 ✓ —— 判据是**独立工具**，不是我自己数的 ✓
//       ③ 插入点也是内容锚定：`return moved` 之后紧邻的那个 `^end$` ✓
//       ④ 全程只写 `%TEMP%`，**最后一步才**写工程文件 ✓
//
//   跑法：node tools/_wip/move2.mjs            # dry-run：只搜索并报告找到的范围
//         node tools/_wip/move2.mjs --apply    # 写工程文件（写前再验一次）
//  ----------------------------------------------------------------------------]]--

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const FILE = 'lua/engine_adapter_qianxing.lua';
const APPLY = process.argv.includes('--apply');
const LUAC = join(process.env.LOCALAPPDATA, 'Programs', 'Lua', 'bin', 'luac.exe');

const text = readFileSync(FILE, 'utf8');
const lines = text.split('\n');
const dir = mkdtempSync(join(tmpdir(), 'qxmove-'));

const startA = lines.findIndex((l) => l.startsWith('function Adapter:apply_ruler_layout'));
const startB = lines.findIndex((l) => l.startsWith('function Adapter:diagnose_overlap'));
if (startA < 0 || startB < 0 || startA > startB) { console.error('  ✗ 定位失败'); process.exit(2); }

// 插入点：`return moved` 之后紧邻的 `^end$`
const rm = lines.findIndex((l, i) => i > startB && l.trim() === 'return moved');
let insertAfter = -1;
for (let i = rm + 1; i < lines.length; i++) if (lines[i].trim() === 'end') { insertAfter = i; break; }
if (rm < 0 || insertAfter < 0) { console.error('  ✗ 找不到插入锚点（return moved / 其后的 end）'); process.exit(2); }
console.log(`  段起点：A=L${startA + 1}  B=L${startB + 1}　插入锚点=L${insertAfter + 1}`);

function build(endA, endB) {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    if ((i >= startA && i <= endA) || (i >= startB && i <= endB)) continue;
    out.push(lines[i]);
    if (i === insertAfter) {
      out.push('', ...lines.slice(startA, endA + 1), '', ...lines.slice(startB, endB + 1));
    }
  }
  return out.join('\n');
}

// 候选区间：函数体不可能短于 20 行、长于 220 行
const candA = [], candB = [];
for (let e = startA + 20; e <= Math.min(startA + 220, startB - 1); e++) candA.push(e);
for (let e = startB + 20; e <= Math.min(startB + 220, insertAfter - 1); e++) candB.push(e);
console.log(`  候选：A ${candA.length} 个结束行 × B ${candB.length} 个 = ${candA.length * candB.length} 组合`);

function trial(endA, endB) {
  const s = build(endA, endB);
  const p = join(dir, 'trial.lua');
  writeFileSync(p, s, 'utf8');
  try { execFileSync(LUAC, ['-p', p], { stdio: 'ignore' }); } catch { return null; }   // 判据①：编译
  try {
    const out = execFileSync('node', ['tools/audit/check_nesting.mjs', p], { encoding: 'utf8' });
    if (!/\[嵌套\]\s*0\s*处/.test(out)) return null;                                    // 判据②：无嵌套
    if (!/不平衡\s*0\s*个文件/.test(out)) return null;                                  // 判据③：深度平衡
    return s;
  } catch { return null; }
}

let found = null, tries = 0;
outer:
for (const eA of candA) {
  for (const eB of candB) {
    tries++;
    const s = trial(eA, eB);
    if (s) { found = { eA, eB, s }; break outer; }
  }
}
console.log(`  试了 ${tries} 个组合`);
if (!found) { console.error('  ✗ 没找到任何满足判据的组合（原样退出，未写工程文件）'); process.exit(3); }
console.log(`  ✓ 找到：A=L${startA + 1}..L${found.eA + 1}（${found.eA - startA + 1} 行）　B=L${startB + 1}..L${found.eB + 1}（${found.eB - startB + 1} 行）`);
console.log(`  ✓ 该组合：luac -p 通过 + [嵌套] 0 处 + 深度平衡`);

if (!APPLY) { console.log('  （dry-run：没写工程文件 ✓ 加 --apply 才写）'); process.exit(0); }

// 写前再验一次（防并发写者改过文件）
const now = readFileSync(FILE, 'utf8');
if (now !== text) { console.error('  ✗ 文件在我读取后被改过，原样退出（不覆盖别人的改动）'); process.exit(4); }
writeFileSync(FILE, found.s, 'utf8');
console.log(`  ✓ 已写入 ${FILE}（UTF-8 无 BOM）`);
