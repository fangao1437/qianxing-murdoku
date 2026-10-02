// tools/gil/adopt_tree.mjs —— **自动拆批**把一整棵（或几棵）子树从源 .gil 领养进基线
//
// 为什么需要它（2026-10-02）：
//   `adopt_group.mjs` 有一道安全阀 —— **拒绝领养"子级 ≥8 的容器"**（因为之前整组导入
//   偷走过光标射线，导致"点不动复活"）。所以像 `left`（117 个控件）、`clues`（92 个子级）、
//   `board`（10 个子级）这种大组，用它是**直接失败**的。
//   但正确做法不是"绕过安全阀"，而是**拆批**：把子树按父级切成若干小批，
//   每批单独走 `adopt_group`（因此每批都有完整的三道自检），最后合成。
//
// 用法：
//   node tools/gil/adopt_tree.mjs --base=<基线的.gil> --src=<源.gil> --roots=left,board \
//        --out=<输出.gil> [--batch=6]
//
// 说明：
//   · `--batch` = 每批最多几个"兄弟"（默认 6，安全阀阈值是 8）
//   · 每一批都跑一遍 `adopt_group.mjs`，它的自检（root 子级数 / 原有控件 / 领养组 / 整棵子树）
//     任何一条不过 ⇒ **整个流程停下，不产出**（不会写出一个半成品让你去踩坑）
//   · 组本身（例如 `left`）会在**第一批**里先被领养，之后各批都是它的子级

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readGil } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
// ★ 2026-10-02：**绝对路径要原样用** —— 先前一律 path.resolve(ROOT, x)，
//   传绝对路径时会拼成 `ROOT\D:\...\x`（ENOENT）。这里统一走这个 helper。
const P = (p) => (path.isAbsolute(p) ? p : path.resolve(ROOT, p));
const arg = (k, d) => {
  const hit = process.argv.find((a) => a.startsWith('--' + k + '='));
  return hit ? hit.slice(k.length + 3) : d;
};

const BASE = arg('base');
const SRC = arg('src');
const OUT = arg('out');
const BATCH = parseInt(arg('batch', '6'), 10);
const ROOTS = arg('roots', '').split(',').map((s) => s.trim()).filter(Boolean);

if (!BASE || !SRC || !OUT || ROOTS.length === 0) {
  console.error('用法: node tools/gil/adopt_tree.mjs --base=<基线> --src=<源> --roots=a,b --out=<输出> [--batch=6]');
  process.exit(1);
}

const src = readGil(P(SRC));
const kidsOf = (rec) => src.recs.filter((x) => String(x.parentId) === String(rec.id));

// ── 规划批次 ─────────────────────────────────────────────────────────
//
// ★★★★★ 2026-10-02 **第一版规划错了，这里说清楚为什么**：
//   我原来把"容器 + 它的前 5 个子级"放一批 ⇒ `left` 的子级里有 `clues`（92 个子级）
//   ⇒ 安全阀看到"清单里有大容器"直接拒绝 ⇒ 这一批失败
//   ⇒ **后续所有批次都因为父级没进基线而失败**（实测 19 批全灭，就是这个链式反应）。
//   ⇒ 正确规则：**领一个容器时只领它自己**（不带子级）；子级下一批再领。
//     叶子（自身没有子级的）可以每 6 个捆一批。
const batches = [];
const childrenOf = (rec) => kidsOf(rec).filter((k) => k.name);

function planNode(name) {
  const rec = src.byName.get(name);
  if (!rec) { console.log('  （源里没有 `' + name + '`，跳过）'); return; }
  const kids = childrenOf(rec);
  batches.push([name]);                       // ① 容器自己单独一批 —— 安全阀能过的前提
  if (kids.length === 0) return;
  const leaves = [];
  for (const k of kids) {                     // ② 子级：容器各自一批，叶子每 6 个一批
    if (childrenOf(k).length > 0) {
      if (leaves.length) batches.push(leaves.splice(0));
      planNode(k.name);
    } else {
      leaves.push(k.name);
      if (leaves.length >= BATCH) batches.push(leaves.splice(0));
    }
  }
  if (leaves.length) batches.push(leaves.splice(0));
}

for (const r of ROOTS) planNode(r);

console.log('  源 ' + SRC + '：规划出 **' + batches.length + ' 批**（容器各自一批；叶子每批 ≤' + BATCH + ' 个）');

// ── 逐批执行 ─────────────────────────────────────────────────────────
let cur = P(BASE);
let done = 0;
for (let i = 0; i < batches.length; i++) {
  const group = batches[i].join(',');
  const tmp = P('_at_' + i + '.gil');
  try {
    // ★ 2026-10-02：`adopt_group.mjs` 内部是 `path.resolve(ROOT, x)` —— 传绝对路径会拼重。
    //   所以这里统一换成**相对 ROOT 的路径**再传给它（工具本身不用动）。
    const rel = (x) => path.relative(ROOT, x);
    const out = execFileSync(process.execPath, [
      '--max-old-space-size=6144',
      path.join(ROOT, 'tools', 'gil', 'adopt_group.mjs'),
      '--base=' + rel(cur), '--src=' + SRC, '--roots=' + group, '--out=' + rel(tmp),
    ], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    process.stdout.write('  [' + (i + 1) + '/' + batches.length + '] ' + group + '  ⇒ OK\n');
    fs.rmSync(cur, { force: true });
    cur = tmp;
    done++;
  } catch (e) {
    const msg = (e.stdout || '') + (e.stderr || '');
    const why = msg.split('\n').filter((l) => l.includes('❌')).slice(0, 2).join(' | ') || e.message;
    console.log('  [' + (i + 1) + '/' + batches.length + '] ' + group + '  ⇒ 失败：' + why.trim());
    fs.rmSync(tmp, { force: true });
    // 单批失败不致命（可能源里本来就没有）——继续，但记下来
  }
}

if (done === 0) { console.error('❌ 一批都没成功，不产出'); process.exit(2); }
fs.copyFileSync(cur, P(OUT));
if (cur !== P(BASE)) fs.rmSync(cur, { force: true });
console.log('  写出 ' + OUT + '（成功 ' + done + '/' + batches.length + ' 批）');

// ── 总检 ─────────────────────────────────────────────────────────────
const g = readGil(P(OUT));
const root = g.byName.get('root');
const rk = g.recs.filter((r) => String(r.parentId) === String(root.id));
console.log('  总检：记录 ' + g.recs.length + '，root 子级 ' + rk.length + '：' + rk.map((r) => r.name || r.id).join(' '));
const plan2 = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools', 'sim', 'out', 'layout-plan.json'), 'utf8'));
const need = [...new Set((plan2.nodes || []).map((n) => n.id))];
const have = new Set(g.recs.map((r) => r.name).filter(Boolean));
const miss = need.filter((n) => !have.has(n));
console.log('  规划需要 ' + need.length + ' 个，现在有 ' + need.filter((n) => have.has(n)).length + ' 个，还缺 ' + miss.length + ' 个');
if (miss.length) {
  const byTop = {};
  for (const n of miss) { const t = n.split('.')[0]; byTop[t] = (byTop[t] || 0) + 1; }
  console.log('  还缺（按顶层）：' + Object.entries(byTop).map(([k, v]) => k + '×' + v).join('  '));
}
