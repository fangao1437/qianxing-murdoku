// tools/gil/merge_baseline.mjs —— **把 97 里的少数几条记录搬进 93**（重建回滚工具）
//
// 背景（2026-10-02）：
//   · `93.gil` = **重建前**的存档：编辑器里有全部界面控件（顶栏 / 线索条 / 维度尺 /
//     头像卡 / 选关卡片 / 家具 / 素材容器 `assets` …，共 283 个是 97 没有的）。
//   · `97.gil` = **重建后**的存档：只留 `home` + `stage` + 三个模板引用。
//   · 用户实测：97 的结构下"点不动"修好了，但**界面布局全没了**（脚本只有两个模板，
//     造出来是一堆白块）⇒ 用户要求**恢复到开始处理 bug 时的布局**。
//
//   ⇒ 正确解法：**以 93 为基底**（它有控件和素材）+ **把 97 独有的 3 条搬进来**
//     （`stage` / `tpl.stage` / `tpl-container`）—— 那 3 条是重建带来的新东西，
//     保留它们，以后"脚本创建"这条路仍然可用。
//
//   ⇒ 这样得到的存档：**布局是 93 的**（用户要的），**脚本是修好的**（能点）。
//
// 用法：
//   node tools/gil/merge_baseline.mjs --base=baseline/93-重建前-掩盖态.gil \
//        --add=97.gil --ids=stage,tpl.stage,tpl-container --out=完整界面105-恢复布局.gil

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, findChildListTop, setChildList, asIdList, encodeMsg } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };

const BASE = path.join(ROOT, argOf('base') || 'baseline/93-重建前-掩盖态.gil');
const ADD = path.join(ROOT, argOf('add') || '97.gil');
const OUT = path.join(ROOT, argOf('out') || '完整界面105-恢复布局.gil');
const IDS = (argOf('ids') || 'stage,tpl.stage,tpl-container').split(',').map((s) => s.trim()).filter(Boolean);

const g = readGil(BASE);
const a = readGil(ADD);

// 找基底里的 root
const rootRec = g.byName.get('root');
if (!rootRec) { console.error('❌ 基底里没有 root'); process.exit(2); }

// 基底已有的名字（避免重复）
const have = new Set();
for (const r of g.recs) { const n = String(r.name || ''); if (n) have.add(n); }

// 从 add 里挑要搬的记录
const moving = [];
for (const id of IDS) {
  const r = a.byName ? a.byName.get(id) : null;
  if (!r) { console.log('  ⚠️ 源存档里没有 `' + id + '`，跳过'); continue; }
  if (have.has(id)) { console.log('  ⚠️ 基底里已经有 `' + id + '`，跳过'); continue; }
  moving.push({ id, rec: r });
}
console.log('  要搬的记录：' + moving.map((m) => m.id).join(' '));

// ① 把每条记录的 #504 改成基底 root 的 id，并加进基底的 recs
const rootId = Number(rootRec.id);
// 把每条记录的 #504 改成基底 root 的 id（**只改第一个**，不管它在第几层 —— 记录自己的父级
// 就是第一个 #504；原来我写了 `depth === 0` 的限制，导致 `tpl-container` 的父级没改到、留在 id=1）
function fixParent(fields, state) {
  let n = 0;
  for (const f of fields) {
    if (f.wt === 0 && f.field === 504 && !state.done) { f.num = BigInt(rootId); state.done = true; n++; }
    else if (f.sub) n += fixParent(f.sub, state);
  }
  return n;
}
let n504 = 0;
for (const m of moving) {
  n504 += fixParent(m.rec.field.sub, { done: false });
  // 记录要 push 到 recHolder（项目注释写明：控件记录真正的家），不是 recs / tree
  g.recHolder.push(m.rec.field);
  console.log('  ✅ 搬入 `' + m.id + '`（id ' + m.rec.id + '）');
}
console.log('  ✅ 改写 #504 指向 root（' + n504 + ' 处）');

// ② 把它们的 id 加进 root 的子列表
const lst = findChildListTop(rootRec.field.sub);
if (!lst) { console.error('❌ 基底的 root 没有子列表'); process.exit(3); }
const cur = asIdList(lst).map((x) => String(x));
const addIds = moving.map((m) => String(m.rec.id)).filter((id) => !cur.includes(id));
setChildList(lst, cur.concat(addIds));
console.log('  ✅ root 子列表：' + cur.length + ' → ' + (cur.length + addIds.length) + ' 个');

// ③ 写出（pack 需要 body）
const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(OUT, buf);
console.log('  写出：' + path.basename(OUT) + '  ' + Math.round(buf.length / 1024) + ' KB');

// ④ 回读验证
const g2 = readGil(OUT);
console.log('  回读：记录 ' + g2.recs.length + ' 条');
for (const id of IDS) {
  const r = g2.byName ? g2.byName.get(id) : null;
  console.log('    ' + id + ' → ' + (r ? ('在，父级 id=' + r.parentId + (String(r.parentId) === String(rootId) ? ' ✅（= root）' : ' ⚠️')) : '**不在** ❌'));
}
