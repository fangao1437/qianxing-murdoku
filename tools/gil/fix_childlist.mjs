// tools/gil/fix_childlist.mjs —— 按记录的**父级字段**重建某个容器的子列表
//
// 为什么需要它（2026-10-02）：
//   `sync_plan` 补控件时，如果父级当时还没建出来，就会**静默退回 `root`** ——
//   于是 `.gil` 里出现"记录的父级指向 `select`，但 `root` 的子列表里也列着它"这种**自相矛盾**，
//   实测后果是 `root` 子级数从 9 涨到 **42**（历史上 root 子级 37 那次就是"点不动复活"）。
//
//   这个工具做一件事：**以记录的父级字段为准**，重建指定容器的子列表 ——
//   顺序上尽量保留原列表（那是编辑器里的排序），只删掉不属于它的、补上漏掉的。
//
// 用法：
//   node tools/gil/fix_childlist.mjs --gil=<文件> [--node=root] [--out=<文件>]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, findChildListTop, setChildList, asIdList } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const arg = (k, d) => {
  const hit = process.argv.find((a) => a.startsWith('--' + k + '='));
  return hit ? hit.slice(k.length + 3) : d;
};
const P = (p) => (path.isAbsolute(p) ? p : path.resolve(ROOT, p));

const GIL = P(arg('gil'));
const NODE = arg('node', 'root');
const OUT = P(arg('out', arg('gil')));
if (!GIL) { console.error('用法: node tools/gil/fix_childlist.mjs --gil=<文件> [--node=root] [--out=<文件>]'); process.exit(1); }

const g = readGil(GIL);
const node = g.byName.get(NODE);
if (!node) { console.error('❌ 找不到容器 `' + NODE + '`'); process.exit(2); }

const lst = findChildListTop(node.field.sub);
if (!lst) { console.error('❌ `' + NODE + '` 没有子列表字段'); process.exit(3); }

const before = asIdList(lst).map(String);
// ★ 注意：JS 注释里别写那个"井号+数字"的字段名 —— 放到字符串里拼，避免某些调用方按注释解析
const PARENT_FIELD = 504;
const truth = g.recs
  .filter((r) => String(r.parentId) === String(node.id))
  .map((r) => String(r.id));
const nameOf = (id) => { const r = g.recs.find((x) => String(x.id) === id); return r ? (r.name || id) : id; };

console.log('  `' + NODE + '` 子列表：读到 ' + before.length + ' 个，按父级字段算得 ' + truth.length + ' 个');
const keep = before.filter((id) => truth.includes(id));
const dropped = before.filter((id) => !truth.includes(id));
for (const id of truth) if (!keep.includes(id)) keep.push(id);
if (dropped.length) console.log('  删掉不属于它的 ' + dropped.length + ' 个：' + dropped.map(nameOf).join(' '));
console.log('  修正后 ' + keep.length + ' 个：' + keep.map(nameOf).join(' '));

setChildList(lst, keep);
const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(OUT, buf);
console.log('  写出 ' + path.relative(ROOT, OUT) + '  ' + Math.round(buf.length / 1024) + ' KB');

// 复查（不能只信"我改了"）
const g2 = readGil(OUT);
const n2 = g2.byName.get(NODE);
const b2 = asIdList(findChildListTop(n2.field.sub)).map(String);
const t2 = g2.recs.filter((r) => String(r.parentId) === String(n2.id)).map((r) => String(r.id));
console.log('  ✅ 复查：子列表 ' + b2.length + ' 个 / 真值 ' + t2.length + ' 个 ⇒ ' + (b2.length === t2.length ? '一致' : '★仍不一致'));
for (const sub of ['select', 'left', 'board', 'clues', 'topbar', 'right']) {
  const r = g2.byName.get(sub);
  if (!r) continue;
  const l = findChildListTop(r.field.sub);
  const inList = l ? asIdList(l).length : 0;
  const real = g2.recs.filter((x) => String(x.parentId) === String(r.id)).length;
  if (inList !== real) console.log('  ⚠️ `' + sub + '` 也不一致：列表 ' + inList + ' / 真值 ' + real);
}
