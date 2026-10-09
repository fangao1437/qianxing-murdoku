// tools/gil/inspect_gil.mjs —— **只读体检**：一个 `.gil` 跑一遍，把"出货前必须看的事实"全打出来
//
// ════════════════════════════════════════════════════════════════════════════
// ★★★ 为什么要有它（2026-10-10 lead 要求 ✓）
// ════════════════════════════════════════════════════════════════════════════
//   ★ lead 原话 ✓：「★ **用户正在测 `296`** ⇒ ★ 若回报"还是 −2" ✗，
//     我**要立刻能判断**是 `blk[0]` 不够、还是别的原因 ✓」
//   ⇒ ★★ 所以本工具把每次出货后**最常被问的几件事**一次打全 ✓：
//     ① 记录数 / 体长 / 尾部 ✓（文件是否是完整的那一份 ✓）
//     ② ★ **内嵌脚本的构建标记** ✓（★ 是不是 v148 ✓ —— 2026-10-10 就栽在这 ✓）
//     ③ ★★ **`clue` 的 4 个状态块【逐个】的位置与尺寸** ✓
//        （★ 用户说"还是从 −2 开始填"时，一眼看出是哪个块没归零 ✓）
//     ④ ★★ **`assets` 的子控件名单** ✓：名字 / id / 父引用 / 是否登记进子列表 ✓
//        （★ "`assets` 取不到"是这轮最耗时的坑 ✓ ⇒ ★ 这里把它固化成可复读的事实 ✓）
//     ⑤ ★ **`row.*` 各自的子列表条数** ✓（★ 齐全不齐全 ✓）
//   ★ **本工具只读** ✓ —— ★ 绝不写任何文件 ✓（★ 也不要给它加"顺手修一下"的功能 ✗）
//
// 用法：
//   node tools/gil/inspect_gil.mjs "296-模板归零+脚本v148.gil"
//   node tools/gil/inspect_gil.mjs <存档> --json          # 机器可读
//   node tools/gil/inspect_gil.mjs <存档> --quiet         # 只打结论
//
// 退出码：★ **0 = 体检完成**（★ 只读工具，不因"发现异常"而失败 ✓ —— 异常用 ⚠️/❌ 标出 ✓）
//          2 = 用法错 / 文件读不了
//
// ★ 复用：`assetsReport(g)` / `assertAssets(g)` 可被别的工具 import ✓
//   （★ `gen_palette.mjs` 就是这么用的 ✓ —— ★ 避免"assets 检查"被抄成第二份 ✗）

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } from './gilread.mjs';
import { findScriptLeaf, markerOf } from './gilwrite.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

// ── 可复用：`assets` 子控件体检（★ 这就是 lead 要的"固化成工具" ✓）──────────
/**
 * @returns {{ok:boolean, id:number|null, list:number[], entries:Array, problems:string[]}}
 */
export function assetsReport(g) {
  const problems = [];
  const a = g.recs.find((r) => r.name === 'assets');
  if (!a) return { ok: false, id: null, list: [], entries: [], problems: ['存档里没有名为 assets 的记录 ✗'] };
  const cl = findChildListTop(a.field.sub);
  if (!cl) problems.push('assets 顶层没有子列表字段（#503）✗ ⇒ 编辑器眼里它是空容器 ✗');
  const list = cl ? (asIdList(cl.payload, true) || []) : [];
  const entries = [];
  for (const id of list) {
    const r = g.recs.find((x) => x.id === id);
    if (!r) { problems.push('子列表里的 id ' + id + ' 找不到对应记录 ✗'); entries.push({ id, name: null }); continue; }
    const hasDeeper = g.recs.some((x) => x.parentId === id);
    entries.push({ id, name: r.name, parentId: r.parentId, isChild: hasDeeper });
    if (r.parentId !== a.id) problems.push('子控件 ' + (r.name || '#' + id) + ' 的父引用 #504 = ' + r.parentId + '，应为 assets ' + a.id + ' ✗');
  }
  // 反向：挂了 assets 当父、却没登记进子列表的
  for (const r of g.recs) {
    if (r.parentId === a.id && !list.includes(r.id)) problems.push('记录 ' + (r.name || '#' + r.id) + ' 声明父为 assets，但没登记进 assets 子列表 ✗');
  }
  return { ok: problems.length === 0, id: a.id, list, entries, problems };
}

/** 给写工具用的断言：`writeGil({ assert: (g2) => assertAssets(g2, ['portrait.A', …]) })` */
export function assertAssets(g, expectNames = []) {
  const rep = assetsReport(g);
  if (!rep.ok) return rep.problems[0];
  for (const n of expectNames) {
    const hit = rep.entries.find((e) => e.name === n);
    if (!hit) return 'assets 子列表里找不到 ' + n + ' ✗';
  }
  return true;
}

// ── 主流程 ────────────────────────────────────────────────────────────────
function main() {
  const argv = process.argv.slice(2);
  const file = argv.find((s) => !s.startsWith('--'));
  const JSON_OUT = argv.includes('--json');
  const QUIET = argv.includes('--quiet');
  if (!file) { console.error('用法: node tools/gil/inspect_gil.mjs <存档.gil> [--json] [--quiet]'); process.exit(2); }
  const fp = path.isAbsolute(file) ? file : path.resolve(ROOT, file);
  if (!fs.existsSync(fp)) { console.error('找不到文件：' + fp); process.exit(2); }

  const g = readGil(fp);
  const out = { file: path.basename(fp), bytes: g.src.length, recs: g.recs.length, body: g.hdr[4] };
  const L = [];
  const p = (s) => { if (!QUIET) L.push(s); };

  p('文件：' + out.file + '（' + out.bytes + ' 字节，体 ' + out.body + '，尾部 ' + g.trailer.length + 'B）');
  p('记录：' + out.recs + ' 条');

  // ② 内嵌脚本 + 构建标记
  const leaf = findScriptLeaf(g);
  const marker = leaf ? markerOf(leaf.buf) : null;
  out.script = leaf ? { bytes: leaf.len, path: leaf.path, marker } : null;
  p('');
  p('── ② 内嵌脚本 ──');
  p('  ' + (leaf ? leaf.len + ' 字节 @' + leaf.path + '　★ 构建标记 = ' + (marker || '（找不到 ✗）') : '（没有内嵌脚本 ✗）'));
  try {
    const dist = path.join(ROOT, 'dist', 'client_script.lua');
    const src = path.join(ROOT, 'lua', 'entry_client_script.lua');
    const dm = fs.existsSync(dist) ? markerOf(fs.readFileSync(dist)) : null;
    const sm = fs.existsSync(src) ? markerOf(fs.readFileSync(src)) : null;
    out.markers = { embedded: marker, dist: dm, source: sm };
    p('  对照：源码 ' + (sm || '?') + '　dist ' + (dm || '?'));
    if (marker && dm && marker !== dm) p('  ❌ 内嵌脚本(' + marker + ') ≠ dist(' + dm + ') ⇒ 这份存档里的脚本不是当前版本 ✗');
    else if (marker && dm) p('  ✅ 与 dist 一致 ✓');
  } catch (e) { p('  （对照失败：' + e.message + '）'); }

  // ③ clue 的 4 个状态块（★ 用户报"还是 −2"时看这里 ✓）
  p('');
  p('── ③ clue 各状态块（★ 用户报"还是从负数开始填"就看这里 ✓）──');
  const clues = g.recs.filter((r) => r.name === 'clue');
  out.clues = [];
  if (!clues.length) p('  （没有名为 clue 的记录 ✗）');
  for (const r of clues) {
    const o = []; stateBlocks(r.field.sub, o);
    const blocks = o.map((blk, i) => {
      const pp = pairOf(blk, 504), ss = pairOf(blk, 505);
      return { i, pos: [pairValue(pp, 0), pairValue(pp, 1)], size: [pairValue(ss, 0), pairValue(ss, 1)] };
    });
    out.clues.push({ id: r.id, parentId: r.parentId, blocks });
    p('  clue #' + r.id + '（父 ' + r.parentId + '）状态块 ' + blocks.length + ' 个：');
    blocks.forEach((b) => p('     blk[' + b.i + '] pos=(' + b.pos[0] + ', ' + b.pos[1] + ')  size=(' + b.size[0] + ', ' + b.size[1] + ')' + (b.pos[0] === 0 && b.pos[1] === 0 ? '  ← 已归零 ✓' : '')));
  }

  // ④ assets
  p('');
  p('── ④ assets 子控件（★ "取不到"那个坑，固化在这里 ✓）──');
  const ar = assetsReport(g);
  out.assets = { id: ar.id, count: ar.list.length, entries: ar.entries, ok: ar.ok };
  p('  assets #' + ar.id + ' 子列表 ' + ar.list.length + ' 项');
  for (const e of ar.entries) {
    p('     ' + String(e.name || '#' + e.id).padEnd(14) + ' #' + String(e.id).padEnd(12)
      + ' 父=' + String(e.parentId).padEnd(12) + (e.parentId === ar.id ? '✓' : '✗'));
  }
  for (const pr of ar.problems) p('  ❌ ' + pr);
  if (ar.ok) p('  ✅ assets 子列表自洽（每项都有记录、父引用正确、无"声明了却没登记"的 ✓）');

  // ⑤ row.* 子列表
  p('');
  p('── ⑤ row.* 子列表条数 ──');
  const rows = g.recs.filter((r) => r.name && r.name.startsWith('row.')).sort((a, b) => a.name.localeCompare(b.name, 'zh'));
  out.rows = rows.map((r) => {
    const cl = findChildListTop(r.field.sub);
    const ids = cl ? (asIdList(cl.payload, true) || []) : null;
    return { name: r.name, id: r.id, parentId: r.parentId, childCount: ids ? ids.length : null };
  });
  if (!rows.length) p('  （没有 row.* 记录）');
  else {
    const counts = {};
    for (const x of out.rows) counts[String(x.childCount)] = (counts[String(x.childCount)] || 0) + 1;
    p('  共 ' + rows.length + ' 个；子列表条数分布：' + Object.entries(counts).map(([k, v]) => k + ' 项×' + v).join('、'));
    const empty = out.rows.filter((x) => !x.childCount);
    if (empty.length) p('  ⚠️ 子列表为空的 row（' + empty.length + ' 个）：' + empty.map((x) => x.name).join('、'));
    else p('  ✅ 每个 row 都有非空子列表 ✓');
  }

  // ⑥ 结论
  p('');
  p('── ⑥ 结论 ──');
  const zero = out.clues.filter((c) => c.blocks[0] && c.blocks[0].pos[0] === 0 && c.blocks[0].pos[1] === 0);
  p('  clue 记录 ' + out.clues.length + ' 个，其中 blk[0] 已归零的 ' + zero.length + ' 个'
    + (zero.length === out.clues.length ? ' ✓' : ' ⚠️（其余仍未归零）'));
  p('  脚本标记 ' + (marker || '?') + '　assets 子控件 ' + ar.list.length + ' 项' + (ar.ok ? ' ✓' : ' ❌')
    + '　row.* ' + out.rows.length + ' 个');

  if (JSON_OUT) console.log(JSON.stringify(out, null, 1));
  else console.log(L.join('\n'));
}

// ★ 只有"直接跑本文件"才执行主流程 ✓（被 import 时不要跑 ✗）
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) main();
