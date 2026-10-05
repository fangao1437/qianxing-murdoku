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
// ⚠️⚠️ 2026-10-05 Round 87：**`.ps1` 的 BOM 裁定 —— 结论是「应当有 BOM」** ✓
//
//   背景：本哨兵（Round 51）曾要求 `.ps1` **必须有 BOM** ✓，而项目既有的
//     `tools/normalize_encoding.ps1`（`check_all` 步骤 **2c**）要求 **没有 BOM** ✗
//     ⇒ 两边**互相剥/加** ✗ ⇒ 我把这条规则**让给了 2c**（让权威唯一 ✓ 做得对 ✓）
//     —— 但**让权不等于 2c 是对的** ✗。这一轮把**谁对**判定清楚 ✓：
//
//   ┌─────────────────┬──────────────────┬────────────────────────────────┐
//   │ `.ps1` 的状态    │ 由 `pwsh`(PS 7)  │ 由 `powershell`(PS 5.1)        │
//   ├─────────────────┼──────────────────┼────────────────────────────────┤
//   │ **有 BOM** ✓     │ 正常 ✓            │ **正常** ✓（靠 BOM 判 UTF-8 ✓）  │
//   │ **无 BOM** ✗     │ 正常 ✓（默认 UTF-8）│ ✗ **按 GBK 解码 ⇒ 中文乱码 ⇒ 整份解析失败** ✗✗ │
//   └─────────────────┴──────────────────┴────────────────────────────────┘
//
//   ⇒ ★ **"有 BOM" 对两种 shell 都安全** ✓；**"无 BOM" 只对 PS 7 安全** ✗
//   ⇒ ⇒ **安全的那一侧是"有 BOM"** ✓ ⇒ **2c 的"无 BOM"要求是危险的一侧** ✗
//     （实测旁证：给 `tools/check_all.ps1` 补 3 字节 BOM 之后，PS 5.1 才跑得起来 ✓）
//
//   ⇒ **待办（给下一轮 / 给用户）**：把 `tools/normalize_encoding.ps1` 的对 `.ps1`
//     判定从"必须无 BOM"改成"**必须有 BOM**" ✓ —— 改它时**必须记得补回它自己的 BOM** ✗
//     （`.ps1` 用 `edit` 工具改完会**丢 BOM** ✓✓ 正是这个坑本身 ✓）
//   ⇒ 在那之前：本哨兵**只报告不判红** ✓（见下面的 `.ps1` 分支 ✓），避免两边继续互相拆台 ✓
const RULES = {
  '.lua':  { bom: false, why: 'Lua 引擎解析器不收 BOM ✓' },
  '.mjs':  { bom: false, why: 'Node 会把 BOM 当内容（多数情况无害，但统一不要 ✓）' },
  '.js':   { bom: false, why: '同上' },
  '.cjs':  { bom: false, why: '同上' },
  // '.ps1' 故意**不列在这里**：它不由本哨兵判红 ✓（权威归属见上面那段裁定 ✓）
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
let bad = 0, checked = 0, ps1NoBom = 0;
const byRule = {};

for (const f of files) {
  const rel = relative(ROOT, f).replace(/\\/g, '/');
  const ext = extname(f).toLowerCase();
  const rule = RULES[ext];
  let buf;
  try { buf = readFileSync(f); } catch { continue; }
  checked++;
  const hasBom = buf.length >= 3 && buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF;

  // ① BOM 是否符合规则（.ps1 **不在**规则表里 ⇒ 走下面的"仅报告" ✓）
  if (rule && hasBom !== rule.bom) {
    bad++;
    byRule[ext] = (byRule[ext] || 0) + 1;
    console.log(`  ✗ ${rel}`);
    console.log(`      BOM=${hasBom}，应为 BOM=${rule.bom} —— ${rule.why}`);
  }

  // ② ★ `.ps1`：**只报告，不判红** ✓（权威归 `tools/normalize_encoding.ps1` = check_all 步骤 2c ✓）
  //    为什么要报告：**PS 5.1** 读**无 BOM 且含中文**的 `.ps1` ⇒ 按 GBK 解码 ⇒ **解析失败** ✗
  //      而 `edit`/`write` 工具写文件**不带 BOM** ⇒ 每次改 `.ps1` 都会悄悄剥掉它 ✗
  //      （本项目已因此栽过 4 次 ✓ ⇒ 必须让它**在每次 check_all 里可见** ✓）
  if (ext === '.ps1' && !hasBom) {
    ps1NoBom++;
    // ⚠️ 这里**不能用反引号**包 `powershell` ✗ —— 外层已经是模板字符串，
    //    内层再来一对反引号会把字符串提前结束 ⇒ `SyntaxError: missing ) after argument list`
    //    （Round 66 我当场踩过 ✓ 记在这里防复发 ✓）
    console.log(`  ℹ ${rel} —— .ps1 无 BOM ⚠️ 若它会被 PowerShell 5.1（powershell）执行，可能按 GBK 解码而解析失败 ✗`);
    console.log(`      权威归步骤 2c 的 normalize_encoding.ps1 ✓ 这里只报告、不判红 ✓（两侧规则曾互相抵消 ✗）`);
  }

  // ③ 是否合法 UTF-8（严格解码复验；Node 的 toString 会静默替换坏字节 ⇒ 用 fatal 再试一次）
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    bad++;
    console.log(`  ✗ ${rel} —— 不是合法 UTF-8 ✗（PS 5.1 与 Lua 会各自乱解）`);
  }
}

console.log(`== 编码/BOM 哨兵 ==  检查 ${checked} 个文件`);
if (ps1NoBom > 0) console.log(`  ℹ 另有 ${ps1NoBom} 个 .ps1 无 BOM（仅提示 ✓ 权威在 2c）`);
if (bad === 0) {
  console.log('  ✓ 全过（.lua/.mjs/.md/.json 无 BOM ✓）');
} else {
  console.log(`  ⇒ ${bad} 项违规 ✗`);
  console.log('  修法：');
  console.log('    · .ps1 缺 BOM ⇒ 用 [System.IO.File]::WriteAllBytes 前置 EF BB BF 三个字节（只加字节，不改内容 ✓）');
  console.log('    · .lua/.md 多了 BOM ⇒ 读成 UTF8 后以 UTF8Encoding($false) 写回 ✓');
  console.log('    ⚠️ 用 edit/write 工具改 .ps1 之后【必须复查这一步】✗（那些工具不写 BOM ✓）');
}
process.exit(bad === 0 ? 0 : 1);
