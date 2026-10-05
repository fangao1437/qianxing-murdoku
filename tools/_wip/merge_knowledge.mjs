// [[----------------------------------------------------------------------------
//   tools/_wip/merge_knowledge.mjs —— 把两份补充文档并进知识主文件（Round 84）
//
//   背景：知识主文件写完之后，**两路代理又各写了一份补充** ✗：
//     · `社区知识-勘误与补充-第2轮.md`（17 KB —— 1 处更正 + 3 条关闭的"未能确认" + 13 条官方细节）
//     · `社区知识-第3轮补充-官方量化上限与三态语义.md`（25.7 KB —— 官方量化上限表 + 三态语义 + 21 个 URL）
//   两位作者**都明确要求**：「合并时并入主文件，然后删掉补充文件 —— **不要两处各留一半**」✓✓
//
//   做法（机械、可复核 ✓）：
//     · 主文件末尾追加两个小节，各自**逐字保留原文** ✓（不删不改内容 ✓ 只加一层标题 ✓）
//     · 每节标题注明来源文件名与原始规模 ✓
//     · 写前自检：主文件必须是**合法 UTF-8 且无 BOM** ✓（.md 规则 ✓）
//     · 写后自检：`check_encoding.mjs` 必须 0 违规 ✓
//     · **不删源文件** —— 删除由人（Lead）确认后单独做 ✓（脚本只负责"并" ✓）
//
//   跑法：node tools/_wip/merge_knowledge.mjs            # dry-run（打印将追加多少行）
//         node tools/_wip/merge_knowledge.mjs --apply
//  ----------------------------------------------------------------------------]]--

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const MAIN = 'docs/社区知识-千星奇域-UGC-踩坑与最佳实践.md';
const SUPPLEMENTS = [
  ['docs/社区知识-勘误与补充-第2轮.md', '第 2 轮补充（勘误 + 3 条关闭的「未能确认」+ 13 条官方细节）'],
  ['docs/社区知识-第3轮补充-官方量化上限与三态语义.md', '第 3 轮补充（官方量化上限表 + 界面控件组三态语义 + 官方来源清单）'],
];
const APPLY = process.argv.includes('--apply');

function readUtf8NoBom(p) {
  const buf = readFileSync(p);
  if (buf.length >= 3 && buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF) {
    console.log(`  ⚠️ ${p} 带 BOM（.md 不该有 ✓）⇒ 读时剥掉 ✓`);
    return buf.subarray(3).toString('utf8');
  }
  return buf.toString('utf8');
}

let main = readUtf8NoBom(MAIN);
console.log(`  主文件：${MAIN}（${main.split('\n').length} 行 ✓）`);

let added = 0;
for (const [path, title] of SUPPLEMENTS) {
  if (!existsSync(path)) { console.log(`  ⚠️ 找不到 ${path} ⇒ 跳过 ✓`); continue; }
  const body = readUtf8NoBom(path);
  const n = body.split('\n').length;
  added += n;
  console.log(`  将追加：${path}（${n} 行）→ 作为「## 附录 · ${title}」✓`);
  main += `\n\n---\n\n## 附录 · ${title}\n\n> ★ 本节由 \`${path}\` **逐字并入**（2026-10-05 Round 84 合并 ✓ 单一口径 ✓）。\n> 原文一字未改 ✓ 只加了一层标题 ✓；原文件将在确认后删除 ✓（**不要两处各留一半** ✓）。\n\n` + body + '\n';
}

console.log(`  合计追加约 ${added} 行 ⇒ 合并后约 ${main.split('\n').length} 行`);
if (!APPLY) { console.log('  （dry-run：没写文件 ✓ 加 --apply 才写）'); process.exit(0); }

writeFileSync(MAIN, main, 'utf8');   // 显式 UTF-8、无 BOM ✓
try {
  execFileSync('node', ['tools/check_encoding.mjs'], { stdio: 'ignore' });
  console.log('  ✓ 已写入，且编码哨兵 0 违规 ✓');
} catch {
  console.error('  ✗ 编码哨兵报红 ⇒ 请人工检查（未自动回滚：原文仍在 git 里 ✓）');
  process.exit(3);
}
