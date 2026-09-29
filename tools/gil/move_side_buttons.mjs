// tools/gil/move_side_buttons.mjs —— 把「撤销 / 提交 / 揭示」挪到**右侧竖排**（参考执律庭实习）
//
// 背景：用户确定的映射（2026-09-30）——
//   重做 → 已被「重置关卡」占用、提示 → 已被右下角放大镜占用
//   ⇒ 剩下 **撤销 / 提交 / 揭示** 放右侧三个六边形位置。
//
// 为什么走"直改控件"而不是脚本：见 `docs/工作约定-优先直改控件.md` ——
//   几何是静态数据，改 `.gil` 一步到位；走脚本要"创建→找→设→每帧维持"，环节多、易错。
//
// ⚠️ 关键（踩过两次）：**记录里的 `#504` 才是真正的父级引用**，
//   只改父控件的子列表、不改 `#504` ⇒ 编辑器里看不到这个控件。
//   本工具**两处都改**。
//
// 用法：
//   node tools/gil/move_side_buttons.mjs --in=完整界面33-主页可用.gil --out=完整界面34.gil

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, setPair, pairOf, stateBlocks,
  findChildList, setChildList, asIdList,
} from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const IN = argOf('in') || path.join(ROOT, '完整界面33-主页可用.gil');
const OUT = argOf('out') || path.join(ROOT, '完整界面34-右侧三按钮.gil');

// 设计坐标（1920×1080）。右侧竖排、贴着右边留 20px 边距、整体垂直居中。
const X = 1790, W = 110, H = 110;
const TARGETS = [
  { id: 'action.undo',   y: 390 },
  { id: 'action.submit', y: 540 },
  { id: 'action.reveal', y: 690 },
];

const g = readGil(IN);
const byId = new Map(g.recs.map((r) => [r.id, r]));
const rootRec = g.byName.get('root');
if (!rootRec) { console.error('❌ 找不到 root'); process.exit(3); }

// ── 工具函数 ──────────────────────────────────────────────────────────────
function setGeom(fields, x, y, w, h) {
  let n = 0;
  for (const b of stateBlocks(fields, [])) {
    const p5 = pairOf(b, 505);
    if (p5) { setPair(p5, w, h); n++; }
    const p4 = pairOf(b, 504);
    if (p4) { setPair(p4, x, y); n++; }
  }
  return n;
}

function ensureChildList(rec) {
  let l = findChildList(rec.field.sub, true);
  if (!l) {
    const src = g.recs.map((r) => findChildList(r.field.sub, true)).find(Boolean);
    if (src) {
      const f = JSON.parse(JSON.stringify({ field: src.field }));
      // 用 cloneField 更稳，但这里手搓一个最小结构也行：直接复用同字段号
      rec.field.sub.push({ field: src.field, wt: 2, sub: null, num: 0n, payload: Buffer.alloc(0), len: 0, isText: false });
      l = findChildList(rec.field.sub, true);
    }
  }
  return l;
}

function listOf(rec) {
  const l = ensureChildList(rec);
  return l ? (asIdList(l.payload, true) || []) : [];
}
function setList(rec, ids) {
  const l = ensureChildList(rec);
  if (l) setChildList(l, ids);
}

// 把 `#504` 改成新的父级（**这是编辑器认的那个**）
function setParentField(rec, parentId) {
  let done = false;
  (function walk(fs) {
    for (const f of fs) {
      if (f.wt === 0 && f.field === 504) { f.num = BigInt(parentId); done = true; return true; }
    }
    return false;
  })(rec.field.sub);
  return done;
}

// ── 挪动 ──────────────────────────────────────────────────────────────────
const moved = [];
for (const t of TARGETS) {
  const rec = g.byName.get(t.id);
  if (!rec) { console.log('  ⚠️ 找不到 ' + t.id + '（跳过）'); continue; }
  const oldParent = byId.get(rec.parentId);
  const oldName = oldParent ? oldParent.name : '?';

  // ① 从旧父级的子列表里摘掉
  if (oldParent) {
    const ids = listOf(oldParent).filter((i) => i !== rec.id);
    setList(oldParent, ids);
  }
  // ② 改 `#504` 指向 root
  setParentField(rec, rootRec.id);
  rec.parentId = rootRec.id;
  // ③ 加进 root 的子列表
  const rids = listOf(rootRec);
  if (!rids.includes(rec.id)) { rids.push(rec.id); setList(rootRec, rids); }
  // ④ 几何
  const n = setGeom(rec.field.sub, X, t.y, W, H);

  moved.push({ id: t.id, from: oldName, pairs: n });
  console.log('  ✅ ' + t.id.padEnd(16) + ' ' + oldName + ' → root   位置=(' + X + ',' + t.y + ') 尺寸=' + W + 'x' + H + '  改了 ' + n + ' 组坐标');
  if (n < 4) console.log('     ⚠️ 坐标组数不足 4（可能有字段没找到），请回读确认');
}

const body = encodeMsg(g.tree);
const outBuf = g.pack(body);
fs.writeFileSync(OUT, outBuf);

// ── 回读验证（**必须**：只看"写成功"不够）──────────────────────────────
const g2 = readGil(OUT);
const b2 = new Map(g2.recs.map((r) => [r.id, r]));
const tr = outBuf.subarray(outBuf.length - g.trailer.length);
console.log('\n输出：' + path.basename(OUT));
console.log('  文件 ' + outBuf.length + '（+' + (outBuf.length - g.src.length) + '）');
console.log('  尾 ' + tr.toString('hex') + (tr.equals(g.trailer) ? '  ✅' : '  ❌')
  + '   控件记录 ' + g2.recs.length + '（+' + (g2.recs.length - g.recs.length) + '）');

let bad = 0;
for (const t of TARGETS) {
  const r = g2.byName.get(t.id);
  if (!r) { bad++; console.log('  ❌ ' + t.id + ' 丢了'); continue; }
  const p = b2.get(r.parentId);
  let pos = '?', size = '?';
  for (const b of stateBlocks(r.field.sub, [])) {
    const p4 = pairOf(b, 504), p5 = pairOf(b, 505);
    if (p4) pos = (p4.f ? p4.f : p4).sub ? 'x' : pos;
  }
  const ok = p && p.name === 'root';
  if (!ok) bad++;
  console.log('  ' + (ok ? '✅' : '❌') + ' ' + t.id.padEnd(16) + '父级=' + (p ? p.name : '?'));
}
console.log('\n' + (bad === 0 ? '★ 三个按钮都挪到 root 下了（编辑器里能看到）' : '❌ 有 ' + bad + ' 个没挂对'));
process.exit(bad === 0 ? 0 : 4);
