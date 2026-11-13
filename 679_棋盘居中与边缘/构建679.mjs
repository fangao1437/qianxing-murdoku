// 679 · 基于 678 的两项整改（678 保留未改；本轮不新增/删除任何记录）
//   ① 注释卡边缘「颜色连贯性 + 形状」：
//      主体齿改 672 渐变 mid 同色 #AF3200（与亮部连贯）、描边改浅 #6B2A12（消除深棕粗带）；
//      齿尖由尖三角改圆润椭圆、齿纵向 16→20（≈齿距 22）⇒ 凹口成浅 V 形、齿连成波浪带；
//      中央矩形 142/148 → 144/150（缩进 9→8px，渐变最左 -70 仍留 2px 余量）。
//   ② 棋盘移动端 y 居中：移动端 1280×576 ⇒ k=0.8、可见原图区 y∈[90,810]、中心 450；
//      棋盘主体中心 y≈420 ⇒ 下移 Δy=+30；只改 5 个根层（stage 带动 36 枚 floor.cell，
//      art657.grid.reuse 带动 49 枚网格层），x 全部不变。
//
// 输入  ../678_注释卡真缺口/678_注释卡真缺口.gil（7431 条）
// 输出  679_棋盘居中与边缘.gil（7431 条，0 新增 / 0 删除）
// 用法  FORCE=1 node 构建679.mjs   /   node 构建679.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/679_棋盘居中与边缘');
const INPUT = path.join(ROOT, 'qianxing-murdoku/678_注释卡真缺口/678_注释卡真缺口.gil');
const OUTPUT = path.join(DIR, '679_棋盘居中与边缘.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '679_规格.json'), 'utf8'));
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, setPair, encodeMsg, findChildListTop, asIdList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  if (!p.sub) p.sub = [];
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
const cache = new Map();
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (cache.has(r.id)) return cache.get(r.id);
  const st = states(r)[0], p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  cache.set(r.id, res); return res;
}
function screenGeom(r) {
  const st = states(r)[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  if (!p || !s) return null;
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  return [px + pairValue(p, 0), py - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)];
}
function setGeomScreen(r, cx, cy, w, h) {
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - px, py - cy);
    setPair(pairOf(st, 505), w, h);
  }
  cache.delete(r.id); touch(r);
}
function setRot(r, deg) {
  for (const st of states(r)) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }]; rf.payload = null; rf.len = 5;
  }
  touch(r);
}
const modified = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }

// ── ① 注释卡齿层：几何 / 颜色 / img / rot ─────────────────────────────────
for (const e of SPEC.ticket.teeth) {
  const r = named(e.name);
  if (isHiddenRecord(r.field)) throw Error('齿层被隐藏 ' + e.name);
  const ip = ns(r.field, [505, 503, 84])[0];
  if (!ip) throw Error('缺图片块 ' + e.name);
  setNum(ip, 502, colorOf(e.color));
  setNum(ip, 503, e.img);
  setNum(ip, 504, 1);
  setGeomScreen(r, e.cx, e.cy, e.w, e.h);
  setRot(r, e.rot);
}
// 中央矩形：宽度微调 + 描边改色
for (const m of SPEC.ticket.rectModify) {
  const r = named(m.name), gm = screenGeom(r);
  setGeomScreen(r, gm[0], gm[1], m.w, m.h);
  setRot(r, -13);
  if (m.color) {
    const ip = ns(r.field, [505, 503, 84])[0];
    if (!ip) throw Error('缺图片块 ' + m.name);
    setNum(ip, 502, colorOf(m.color)); setNum(ip, 504, 1);
  }
}

// ── ② 棋盘根层：y +30，x 不变 ───────────────────────────────────────────
const SHIFT = SPEC.board.shiftY;
const boardBefore = {}, boardAfter = {};
for (const b of SPEC.board.roots) {
  const r = named(b.name), gm = screenGeom(r);
  if (!gm) throw Error('缺几何 ' + b.name);
  boardBefore[b.name] = gm.map(v => +v.toFixed(2));
  setGeomScreen(r, gm[0], gm[1] + SHIFT, gm[2], gm[3]);
  boardAfter[b.name] = screenGeom(r).map(v => +v.toFixed(2));
}
// 断言 x 与尺寸逐条不变
for (const b of SPEC.board.roots) {
  const a = boardBefore[b.name], c = boardAfter[b.name];
  if (Math.abs(a[0] - c[0]) > 0.01 || Math.abs(a[2] - c[2]) > 0.01 || Math.abs(a[3] - c[3]) > 0.01
      || Math.abs(c[1] - a[1] - SHIFT) > 0.01) throw Error('棋盘平移断言失败 ' + b.name);
}

// ── 闸门 ─────────────────────────────────────────────────────────────────
// 既有成果（除本轮 31 条目标层）逐字节不变
const targetNames = new Set([
  ...SPEC.ticket.teeth.map(e => e.name),
  ...SPEC.ticket.rectModify.map(m => m.name),
  ...SPEC.board.roots.map(b => b.name),
]);
const keep = g.recs.filter(r => r.name && !targetNames.has(r.name)
  && (/^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art677\.ring\.|art678\.tab\.)/.test(r.name)
    || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame',
        'art658.clues.binding', 'art676.binding.mid'].includes(r.name))).map(r => r.name);
const keepBytes = new Map(keep.map(n => [n, beforeBytes.get(named(n).id)]));
for (const n of keep)
  if (!keepBytes.get(n).equals(encodeMsg([named(n).field]))) throw Error('既有成果被改动 ' + n);
if (keep.filter(n => /^art675\.wax\./.test(n)).length !== 240) throw Error('675 火漆层数不符');
if (keep.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n)).length !== 23) throw Error('672 渐变三角数不符');
if (keep.filter(n => /^art677\.ring\./.test(n)).length !== 72) throw Error('677 环记录数不符（8 组 × 9 层，含 8 条隐藏的 tipHi）');
// 零溢出
const Z = SPEC.ticket.gates;
if (!Z.zeroSpur || Z.mainOut !== 0 || Z.gradOut !== 0) throw Error('零溢出闸门未通过');
// 改动集合：必须恰好等于目标层
const changed = [...byId.keys()].filter(id =>
  beforeBytes.has(id) && !beforeBytes.get(id).equals(encodeMsg([byId.get(id).field])));
const changedNames = changed.map(id => byId.get(id).name || '#' + id);
const unexpected = changedNames.filter(n => !targetNames.has(n));
if (unexpected.length) throw Error('非目标记录被改动：' + unexpected.slice(0, 5).join(','));
if (changed.length !== targetNames.size) throw Error(`改动数不符 ${changed.length} vs ${targetNames.size}`);

const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: 0, removed: 0, changed: changed.length, unexpected: unexpected.length,
    zeroSpur: Z.zeroSpur, boardShift: SHIFT, keep: keep.length }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '679 board y-centered for mobile (+30) + ticket edge color/roundness refinement',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touchedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return '非目标记录被改动 ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const rt = t.tree.find(q => q.field === 9);
    const idx = new Map(); rt.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    for (const n of keep) {
      const a = t.recs.find(q => q.name === n);
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '既有成果被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '679 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '678_注释卡真缺口.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '679_棋盘居中与边缘.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    userFeedback: '注释卡边缘颜色连贯性与形状仍与设计图有明显差异；移动端棋盘总体偏上（该图非最新美术，只用于位置判断，预览可信）',
    ticket: { geometry: SPEC.ticket.geometry, gates: SPEC.ticket.gates, teeth: SPEC.ticket.teeth.length,
      rectModify: SPEC.ticket.rectModify, safety: SPEC.ticket.safety },
    board: { ...SPEC.board, before: boardBefore, after: boardAfter, xUnchanged: true },
    keepUntouched: keep.length,
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: 0, removed: 0, changed: changed.length, unexpected: unexpected.length },
  changedNames,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '679_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: 0, removed: 0, changed: changed.length, unexpected: unexpected.length,
  zeroSpur: Z.zeroSpur, boardShift: SHIFT, scriptBytes: scriptBefore.length, status: 'APPLIED' }, null, 2));
