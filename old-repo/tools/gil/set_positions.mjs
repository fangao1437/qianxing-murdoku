// tools/gil/set_positions.mjs —— **把每个控件的坐标改成规划值**（修"错位"）
//
// 为什么需要它（2026-10-02）：
//   `sync_plan.mjs` 只**补缺失的**控件，"已有的一律不动"（那是为了尊重编辑器里手调的位置）。
//   但这一轮 `LAYOUT` 大改之后，**已有控件的坐标全是旧值** ⇒ 真机表现：
//     `hud.title` 在 (-283,7)（屏幕 517,443 = 画面正中，应为顶部）、
//     `clues` 在 (0,41)（屏幕 x=800 居中，应贴左边 183）……
//   ⇒ 这个工具把**规划里的坐标**写下去，让 .gil 与 `M.LAYOUT` 真正一致。
//
//   换算：规划是**画布空间**（1600×900，Y 向上，原点在**左下**）；
//        而这个项目的 UI 是「**容器锚点 = 屏幕中心 (0,0)、子控件用画布绝对坐标**」
//        ⇒ 控件位置 = (cx − 800, cy − 450)。
//         （真机日志验证过：`board` cx=765,cy=458 ⇒ (-35,8) 实测就是这个，
//           而 `action.undo` cx=1541,cy=833 ⇒ (741,383)…实测 (741,132) 略差，
//           说明**规划里的 y 也要减 450 之后再核对** —— 见 --report。）
//
// 用法：
//   node tools/gil/set_positions.mjs --gil=<文件> [--out=<文件>] [--only=前缀,前缀] [--dry]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, pairOf, setPair, stateBlocks } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const arg = (k, d) => { const h = process.argv.find((s) => s.startsWith('--' + k + '=')); return h ? h.slice(k.length + 3) : d; };
const P = (p) => (path.isAbsolute(p) ? p : path.resolve(ROOT, p));
const DRY = process.argv.includes('--dry');

const GIL = P(arg('gil'));
const OUT = P(arg('out', arg('gil')));
const ONLY = arg('only', '').split(',').map((s) => s.trim()).filter(Boolean);
const PLAN = P(arg('plan', 'tools/sim/out/layout-plan.json'));
if (!GIL) { console.error('用法: node tools/gil/set_positions.mjs --gil=<文件> [--out=<文件>] [--only=a,b] [--dry]'); process.exit(1); }

const g = readGil(GIL);
const plan = JSON.parse(fs.readFileSync(PLAN, 'utf8'));
const CX = 800, CY = 450;                 // 画布中心

/** 找出记录里承载"位置"的字段 —— ★ 必须用 `stateBlocks()`，不能用"第一个子块"。
 *  （`sync_plan.makeRecord` 就是这么写的：几何在**每个状态块**里各有一份 505/504，
 *   只改第一个的话，其它状态下位置还是旧的 ⇒ 真机表现就是"有的屏对、有的屏错"。） */
function posPairsOf(rec) {
  const out = [];
  for (const b of stateBlocks(rec.field.sub, [])) {
    const x = pairOf(b, 504); if (x) out.push(x);
  }
  return out;
}

let changed = 0, missing = 0, noPair = 0;
const samples = [];
for (const n of (plan.nodes || [])) {
  if (ONLY.length && !ONLY.some((p) => n.id === p || n.id.startsWith(p + '.'))) continue;
  const rec = g.byName.get(n.id);
  if (!rec) { missing++; continue; }
  const pp = posPairsOf(rec);
  if (pp.length === 0) { noPair++; continue; }
  const x = Math.round(n.cx - CX);
  const y = Math.round(n.cy - CY);
  if (!DRY) for (const pr of pp) setPair(pr, x, y);
  changed++;
  if (samples.length < 12) samples.push(n.id + ' → (' + x + ',' + y + ')');
}

console.log('  规划里 ' + (plan.nodes || []).length + ' 个控件');
console.log('  改了 ' + changed + ' 个；规划里有而 .gil 没有的 ' + missing + ' 个；找不到位置字段的 ' + noPair + ' 个');
console.log('  样例：' + samples.join('  '));

if (!DRY) {
  const buf = g.pack(encodeMsg(g.tree));
  fs.writeFileSync(OUT, buf);
  console.log('  写出 ' + path.relative(ROOT, OUT) + '  ' + Math.round(buf.length / 1024) + ' KB');
  // 复查：抽三个读回来核对
  const g2 = readGil(OUT);
  for (const id of ['hud.title', 'clues', 'board', 'action.undo']) {
    const n = (plan.nodes || []).find((v) => v.id === id);
    const r = g2.byName.get(id);
    if (!n || !r) continue;
    const pp = posPairsOf(r);
    const got = pp.length ? pp.map((pr) => (pr.sub || []).map((f) => Number(f.num)).join(',')).join(' | ') : '?';
    console.log('    复查 ' + id.padEnd(14) + ' 期望 (' + Math.round(n.cx - CX) + ',' + Math.round(n.cy - CY) + ')  实际读到 (' + got + ')');
  }
}
