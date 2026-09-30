// tools/gil/exp_import.mjs —— **导入失败原因的二分实验**
//
// 背景（2026-09-30）：
//   用户导入我生成的 `完整界面36` **导不进去**；而 `35.1.gil`（用户自己在编辑器里
//   建了两个容器后导出的）**能导入**。
//   两个文件我都验过：大端文件头 ✅、体长 ✅、尾 `00000679` ✅、往返逐字节无损 ✅、
//   记录关系自洽（唯一的 `cell.1.1` 不一致在你自己的文件里也有）✅。
//   ⇒ 我自己的所有检查都"通过"，但工具有可能**本身就是问题源**，
//     所以改用**单点差异的对照实验**来定位：一次只改一个地方，看哪一步开始导不进去。
//
// 产出四个文件：
//   A 原样复制                     —— 基线，应该能导入
//   B 只改一个**已有**控件的坐标    —— 检验"我的写盘本身会不会坏文件"
//   C 只**加 1 条**新记录          —— 检验"新增记录"
//   D = 完整界面36（已知导不进）    —— 对照
//
// 用法：node tools/gil/exp_import.mjs [--base=<文件>]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, stateBlocks, pairOf, setPair,
  findChildList, asIdList, setChildList,
} from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const SRC = argOf('base') || path.join(ROOT, '35.1.gil');

// 深拷贝一个字段子树（**不能**用 JSON —— 里面有 BigInt 和 Buffer）
function deepField(f) {
  const c = {
    field: f.field, wt: f.wt, sub: null,
    num: f.num, len: f.len, isText: f.isText,
    payload: f.payload ? Buffer.from(f.payload) : Buffer.alloc(0),
  };
  if (f.sub) c.sub = f.sub.map(deepField);
  return c;
}
function walkFields(fs, fn) {
  for (const f of fs) { fn(f); if (f.sub) walkFields(f.sub, fn); }
}
function setNum(fs, fieldNo, value) {
  let hit = false;
  walkFields(fs, (f) => { if (!hit && f.wt === 0 && f.field === fieldNo) { f.num = BigInt(value); hit = true; } });
  return hit;
}
function setLeafText(fs, text) {
  // 名字在 `#505/#12/#501`，是一个 length-delimited 字段
  const buf = Buffer.from(text, 'utf8');
  let done = false;
  const visit = (list, inName) => {
    for (const f of list) {
      if (done) return;
      if (f.field === 505 && f.sub) { visit(f.sub, true); continue; }
      if (inName && f.field === 501 && f.wt === 2) { f.payload = buf; f.len = buf.length; f.isText = true; done = true; return; }
      if (f.sub) visit(f.sub, false);
    }
  };
  visit(fs, false);
  return done;
}

console.log('  基准文件：' + path.basename(SRC) + '  ' + fs.statSync(SRC).size + ' 字节');

// ── A：原样复制 ────────────────────────────────────────────────────────────
const A = path.join(ROOT, 'A.gil');
fs.copyFileSync(SRC, A);
console.log('  A ' + path.basename(A) + '  ' + fs.statSync(A).size + ' 字节');

// ── B：只改一个**已有**控件的坐标（不加记录、不改结构）────────────────────
{
  const g = readGil(SRC);
  const h = g.byName.get('home');
  let n = 0;
  for (const b of stateBlocks(h.field.sub, [])) {
    const p4 = pairOf(b, 504);
    if (p4) { setPair(p4, 1, 1); n++; }   // (0,0) → (1,1)，肉眼看不出的位移
  }
  const B = path.join(ROOT, 'B.gil');
  fs.writeFileSync(B, g.pack(encodeMsg(g.tree)));
  console.log('  B ' + path.basename(B) + '  ' + fs.statSync(B).size + ' 字节（改了 ' + n + ' 组坐标）');
}

// ── C：只**加 1 条**新记录（克隆 action.undo，挂到 home 下）────────────────
{
  const g = readGil(SRC);
  const home = g.byName.get('home');
  const proto = g.byName.get('action.undo');
  const newId = g.maxId + 1;

  const field = deepField(proto.field);
  setNum(field.sub, 501, newId);                 // 自己的 ID
  setNum(field.sub, 504, home.id);               // 父级引用
  const named = setLeafText(field.sub, 'home.probe');
  if (!named) console.log('    ⚠️ 没找到名字字段，名字可能没改成功');

  g.recHolder.push(field);   // ★ 必须和现有记录同处（详见 gilread.mjs 的 recHolder）
  const cl = findChildList(home.field.sub, true);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  ids.push(newId);
  setChildList(cl, ids);

  const C = path.join(ROOT, 'C.gil');
  fs.writeFileSync(C, g.pack(encodeMsg(g.tree)));
  console.log('  C ' + path.basename(C) + '  ' + fs.statSync(C).size + ' 字节（新 id=' + newId
    + '，名字改了=' + named + '）');

  // 回读自检：新记录在不在、父级对不对
  const g2 = readGil(C);
  const r = g2.recs.find((x) => x.id === newId);
  console.log('    回读：' + (r ? '记录在 ✅ 名字=' + JSON.stringify(r.name) + ' 父级=' + (g2.recs.find((x) => x.id === r.parentId) || {}).name : '❌ 记录丢了'));
}
console.log('  D 完整界面36-用你建的容器.gil  ' + fs.statSync(path.join(ROOT, '完整界面36-用你建的容器.gil')).size + ' 字节');
