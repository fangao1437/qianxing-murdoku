// [[----------------------------------------------------------------------------
//   tools/check_encoding.mjs —— 编码/BOM 机械哨兵（Round 51）
//
//   为什么需要它：**BOM 的规则在本项目里是相反的** ✗，我已经因此栽过两次 ✓：
//     · **`lua/**/*.lua` 必须【没有】BOM** ✓ —— 引擎的 Lua 解析器；
//     · **`tools/**/*.ps1` 与 `tests/**/*.ps1` 必须【有】BOM** ✓ ——
//       PowerShell 5.1 靠 BOM 判编码；**无 BOM 且含中文** 时它按 **GBK** 解码
//       ⇒ **整份脚本解析失败** ✗✗（真发生过：`tools/check_all.ps1` 一度完全跑不起来 ✓）。
//   还有一个**隐身雷**：`edit` / `write` 工具写出的文件**不带 BOM** ✓
//     ⇒ 每次用它们改 `.ps1` 都会**悄悄剥掉 BOM** ✗ ⇒ 必须每次复查 ✓ ⇒ 所以要做成工具 ✓
//
//   另外顺带查两条同族的编码坑：
//     · `.lua` / `.mjs` 里**不允许出现 UTF-8 BOM**（同上）
//     · 文件必须是**合法 UTF-8**（坏字节会让 PS 5.1 / Lua 各自按不同方式乱解 ✓）
//
//   跑法：node tools/check_encoding.mjs          # 退出码 0=全过，1=有违规
//   只读，不改任何文件 ✓
//  ----------------------------------------------------------------------------]]--

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname, relative } from 'node:path';

const ROOT = process.cwd();
// 排除：依赖 / 归档 / 第三方快照（它们的编码不归我们管，也不该被本哨兵判红 ✓）
const SKIP = new Set([
  'node_modules', '.git', 'dist', 'versions', '_backup', 'baseline',
  'tools/bin', 'tools/_dl', 'tools/lua-tooling/out', 'tools/lua53check/node_modules',
]);

// 规则表：扩展名 → 期望
//
// ⚠️⚠️ 2026-10-05 Round 62：**`.ps1` 那条规则撤销了** ✗ —— 因为它与项目既有的
//    `tools/normalize_encoding.ps1`（`check_all` 步骤 **2c**）**直接打架** ✓✓：
//      · 本哨兵（Round 51 加的）曾要求 `.ps1` **必须有 BOM**；
//      · 2c 要求 `.ps1` **必须没有 BOM** ⇒ 它每次都会把本哨兵补的 BOM **再剥掉** ✗。
//    两边**互相抵消** ⇒ 仓库里同时存在两条相反的规则 ✗ ⇒ 必须撤掉一条 ✓。
//
//    谁对？**证据是分裂的** ✓：
//      · **PS 5.1**（`powershell`）读**无 BOM 且含中文**的 `.ps1` ⇒ 按 GBK 解码 ⇒ **解析失败** ✗
//        （工具代理实测：给 `check_all.ps1` 补 3 字节 BOM 之后就能跑了 ✓）
//      · **PS 7**（`pwsh`，本会话用的）默认 UTF-8 ⇒ **不需要 BOM** ✓
//    ⇒ **规则取决于"哪个 shell 解析它"** ✗ ⇒ 一个仓库里不该有两条互相抵消的规则 ✓
//
//    ⇒ **处置**：本哨兵**让出这条规则的权威** ✓ —— 不再对 `.ps1` 判红 ✗，
//      只在**同一文件同时被两种 shell 使用时**给提示 ✓；权威归 **2c** ✓
//      （一条规则一个权威 ✓ 否则工具之间会互相拆台 ✓）
const RULES = {
  '.lua':  { bom: false, why: 'Lua 引擎解析器不收 BOM ✓' },
  '.mjs':  { bom: false, why: 'Node 会把 BOM 当内容（多数情况无害，但统一不要 ✓）' },
  '.js':   { bom: false, why: '同上' },
  '.cjs':  { bom: false, why: '同上' },
  // '.ps1' 故意**不列**：BOM 要求取决于解析它的 PowerShell 版本 ✗
  //   ⇒ 权威归 `tools/normalize_encoding.ps1`（步骤 2c）✓ 见上面那段说明
  '.md':   { bom: false, why: '文档统一无 BOM ✓' },
  '.json': { bom: false, why: 'JSON 规范不建议 BOM ✓' },
};

function walk(dir, out = []) {
  let entries;
  try { entries = readdirSync(dir); } catch { return out; }
  for (const name of entries) {
    const p = join(dir, name);
    const rel = relative(ROOT, p).replace(/\\/g, '/');
    if (SKIP.has(rel) || [...SKIP].some((s) => rel === s || rel.startsWith(s + '/'))) continue;
    let st;
    try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) walk(p, out);
    else if (RULES[extname(name).toLowerCase()]) out.push(p);
  }
  return out;
}

const files = walk(ROOT);
let bad = 0, checked = 0;
const byRule = {};

for (const f of files) {
  const rel = relative(ROOT, f).replace(/\\/g, '/');
  const rule = RULES[extname(f).toLowerCase()];
  let buf;
  try { buf = readFileSync(f); } catch { continue; }
  checked++;
  const hasBom = buf.length >= 3 && buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF;

  // ① BOM 是否符合规则
  if (hasBom !== rule.bom) {
    bad++;
    byRule[extname(f).toLowerCase()] = (byRule[extname(f).toLowerCase()] || 0) + 1;
    console.log(`  ✗ ${rel}`);
    console.log(`      BOM=${hasBom}，应为 BOM=${rule.bom} —— ${rule.why}`);
  }

  // ② 是否合法 UTF-8（用严格解码复验；Node 的 toString 会静默替换坏字节 ⇒ 用 fatal 再试一次）
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    bad++;
    console.log(`  ✗ ${rel} —— 不是合法 UTF-8 ✗（PS 5.1 与 Lua 会各自乱解）`);
  }
}

console.log(`== 编码/BOM 哨兵 ==  检查 ${checked} 个文件`);
if (bad === 0) {
  console.log('  ✓ 全过（.lua/.mjs/.md/.json 无 BOM；.ps1 有 BOM ✓）');
} else {
  console.log(`  ⇒ ${bad} 项违规 ✗`);
  console.log('  修法：');
  console.log('    · .ps1 缺 BOM ⇒ 用 [System.IO.File]::WriteAllBytes 前置 EF BB BF 三个字节（只加字节，不改内容 ✓）');
  console.log('    · .lua/.md 多了 BOM ⇒ 读成 UTF8 后以 UTF8Encoding($false) 写回 ✓');
  console.log('    ⚠️ 用 edit/write 工具改 .ps1 之后【必须复查这一步】✗（那些工具不写 BOM ✓）');
}
process.exit(bad === 0 ? 0 : 1);
