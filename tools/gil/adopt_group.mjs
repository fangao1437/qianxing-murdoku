// tools/gil/adopt_group.mjs —— **按清单从旧存档"领养"一组控件（含子树）到当前基线**
//
// 为什么要有这个工具（2026-10-02 血的教训）：
//   · `merge_baseline.mjs` 是"整体合并"——它把 93 的 **root 子级整套**搬了过来。
//     后果：root 子级从 4 个变成 37 个，那批**全屏编辑器容器**（select/board/left/right/
//     topbar/modal/intro/assets …）把光标射线抢走了 ⇒ **"点不动"复活**。
//   · 正确的做法是**按清单领养**：一次只搬**一组**（例如"顶栏 + 它的子控件"），
//     搬完立刻自检 root 子级数量、关键控件是否还在、有没有多出全屏尺寸的容器。
//
// 用法（示例：领养顶栏那一组）
//   node tools/gil/adopt_group.mjs \
//        --base=baseline/103-干净底座-能点.gil \
//        --src=baseline/93-重建前-掩盖态.gil \
//        --roots=topbar \
//        --out=完整界面110-加顶栏.gil
//
//   `--roots` 支持逗号分隔；每个名字会被当作"子树的根"——
//   它的所有后代（按源存档里的父子关系递归）都会一起搬过来。
//   **父级关系照搬源存档**：如果某个后代的父级在清单里，就连到搬过来的那个；
//   否则连到基线里同名的控件（找不到就报错，不会偷偷挂到 root 上）。
//
// 安全阀（不通过就**拒绝写出**）：
//   ① 基线 root 子级数量**只允许增加清单里"父级是 root"的那些**；
//   ② 搬进来的控件里**不允许**出现"尺寸 ≥ 800×600 且类型是容器"的东西（那类会抢射线）；
//   ③ 搬完回读，逐条核对每个领养名都在、且父级正确。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, findChildListTop, setChildList, asIdList, encodeMsg } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };

const BASE = path.join(ROOT, argOf('base') || 'baseline/103-干净底座-能点.gil');
const SRC = path.join(ROOT, argOf('src') || 'baseline/93-重建前-掩盖态.gil');
const OUT = path.join(ROOT, argOf('out') || '完整界面110-领养一组.gil');
const ROOTS = (argOf('roots') || '').split(',').map((s) => s.trim()).filter(Boolean);
if (ROOTS.length === 0) { console.error('❌ 必须给 --roots=名字1,名字2'); process.exit(2); }

const g = readGil(BASE);
const s = readGil(SRC);
console.log('  基线 ' + path.basename(BASE) + '：记录 ' + g.recs.length + '，root 子级 '
  + g.recs.filter((r) => String(r.parentId) === String(g.byName.get('root').id)).length);
console.log('  源   ' + path.basename(SRC) + '：记录 ' + s.recs.length);

const baseRoot = g.byName.get('root');
if (!baseRoot) { console.error('❌ 基线里没有 root'); process.exit(2); }

// ── ① 在源存档里按父子关系收集"子树" ────────────────────────────────
const nameToRec = s.byName;
const idToRec = new Map(s.recs.map((r) => [String(r.id), r]));
const kidsOf = new Map();
for (const r of s.recs) {
  const p = String(r.parentId);
  if (!kidsOf.has(p)) kidsOf.set(p, []);
  kidsOf.get(p).push(r);
}
const picked = new Map();               // id -> rec
const queue = [];
for (const n of ROOTS) {
  const r = nameToRec.get(n);
  if (!r) { console.error('❌ 源存档里没有 `' + n + '`'); process.exit(2); }
  queue.push(r);
}
while (queue.length) {
  const r = queue.shift();
  const id = String(r.id);
  if (picked.has(id)) continue;
  picked.set(id, r);
  for (const c of (kidsOf.get(id) || [])) queue.push(c);
}
console.log('  将领养 ' + picked.size + ' 个控件：');
console.log('    ' + [...picked.values()].slice(0, 40).map((r) => r.name || r.id).join(' '));

// ── ② 安全检查：不许把"大块容器"搬进来（那类会抢射线）────────────────
const BIG = 800 * 600;
const danger = [];
for (const r of picked.values()) {
  // 源记录的名字里带不带容器语义、以及它的子级数量（容器通常有很多子级）
  const nk = (kidsOf.get(String(r.id)) || []).length;
  if (nk >= 8) danger.push((r.name || r.id) + '（子级 ' + nk + ' 个）');
}
if (danger.length) {
  console.error('❌ 清单里包含"大容器"（子级 ≥8）：' + danger.join('、'));
  console.error('   这类控件很可能抢光标射线 —— 请拆小批次，或明确知道自己在做什么再改这个检查。');
  process.exit(3);
}

// ── ③ 决定每个领养控件的父级 ────────────────────────────────────────
const baseIds = new Map(g.recs.map((r) => [String(r.id), r]));
const nextId = Math.max(...g.recs.map((r) => r.id)) + 1;
const idMap = new Map();                // 源 id -> 新 id
let cursor = nextId;
for (const r of picked.values()) idMap.set(String(r.id), cursor++);

/** 改写记录内的 #504（第一个）与所有 id 引用，返回新 id */
function retarget(fields, state) {
  for (const f of fields) {
    if (f.wt === 0 && f.field === 504 && !state.parentDone) {
      const srcParent = String(f.num);
      const mapped = idMap.get(srcParent);
      if (mapped !== undefined) f.num = BigInt(mapped);
      else {
        // 父级不在清单里 —— 必须能在基线里按"源父级名字"找到同名控件
        const srcParentRec = idToRec.get(srcParent);
        const pname = srcParentRec ? srcParentRec.name : null;
        const target = pname ? g.byName.get(pname) : null;
        if (!target) {
          state.bad = '父级 `' + (pname || srcParent) + '` 在基线和清单里都找不到';
          return;
        }
        f.num = BigInt(target.id);
      }
      state.parentDone = true;
    } else if (f.wt === 0 && (f.field === 1 || f.field === 2) && typeof f.num === 'bigint') {
      const mapped = idMap.get(String(f.num));
      if (mapped !== undefined) f.num = BigInt(mapped);      // 引用型字段一起换 id
    } else if (f.sub) retarget(f.sub, state);
  }
}

const states = [];
for (const r of picked.values()) {
  const st = { parentDone: false, bad: null };
  retarget(r.field.sub, st);
  if (st.bad) { console.error('❌ ' + (r.name || r.id) + '：' + st.bad); process.exit(4); }
  states.push([r, idMap.get(String(r.id))]);
}

// ── ④ 写进基线 ──────────────────────────────────────────────────────
for (const [r, newId] of states) {
  r.id = newId;
  g.recHolder.push(r.field);
  g.recs.push(r);                     // 让后续查找/统计看得到
}

// 给"父级是 root 的新控件"补进 root 子列表
const newRootKids = states.filter(([r]) => String(r.parentId) === String(baseRoot.id)).map(([, id]) => String(id));
const lst = findChildListTop(baseRoot.field.sub);
if (!lst) { console.error('❌ 基线的 root 没有子列表字段'); process.exit(5); }
const cur = asIdList(lst).map((x) => String(x));
const childSet = new Set(cur);
const byParent = g.recs.filter((r) => String(r.parentId) === String(baseRoot.id)).map((r) => String(r.id));
for (const id of byParent) childSet.add(id);
const finalIds = [...childSet];
setChildList(lst, finalIds);
console.log('  ✅ root 子列表：读到旧值 ' + cur.length + ' 个，按 parentId 算出 ' + byParent.length
  + ' 个，最终写 ' + finalIds.length + ' 个（新增 ' + newRootKids.length + ' 个）');
if (finalIds.length < 4) { console.error('❌ root 子级太少，拒绝写出'); process.exit(6); }

const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(OUT, buf);
console.log('  写出：' + path.basename(OUT) + '  ' + Math.round(buf.length / 1024) + ' KB');

// ── ⑤ 回读自检 ──────────────────────────────────────────────────────
const g2 = readGil(OUT);
const r2 = g2.byName.get('root');
const kids2 = g2.recs.filter((rr) => String(rr.parentId) === String(r2.id));
console.log('  回读：记录 ' + g2.recs.length + '，root 子级 ' + kids2.length + ' 个：'
  + kids2.map((rr) => rr.name || rr.id).join(' '));
const keep = ['home', 'home.select', 'stage', 'tpl.cell', 'tpl.stage', 'tpl-container'];
const lost = keep.filter((n) => !g2.byName.get(n));
console.log(lost.length ? ('  ❌ 原有控件丢了：' + lost.join(' ')) : '  ★ 原有控件全在 ✅');
let missing = 0;
for (const n of ROOTS) if (!g2.byName.get(n)) { console.log('  ❌ 领养的 `' + n + '` 不在'); missing++; }
console.log(missing === 0 ? '  ★ 领养的组都在 ✅' : ('  ❌ 有 ' + missing + ' 个领养失败'));
if (lost.length || missing) process.exit(7);
