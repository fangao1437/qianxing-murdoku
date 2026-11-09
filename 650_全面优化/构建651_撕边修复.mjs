// 651 · 按设计图重建选关撕纸边（在 650_优化版.gil 之上，只换美术图元）
//
// 输入（哈希锁定）：650_全面优化/650_优化版.gil
// 输出（不覆盖输入）：650_全面优化/651_撕边修复.gil
// 轨迹：651_设计图白边轨迹.json（由 提取设计图白边轨迹.mjs 从 1920x1080 设计图逐列/逐行提取）
//
// 为什么重建：650 的撕边由「166 段旋转白线 + 133 片局部补色盖板 + 5 条桥接」拼成，
//   离线渲染与实机一致，但存在两类问题：
//   ① 折点处旋转长条互相错位，纸片露出方形台阶/黑色咬口，白线也接不上；
//   ② 盖板只向 board 侧加宽，白边整体外移且过粗，两端未延伸到画面边缘。
// 本版不再补丁叠补丁：按设计图白边中心线，用「扫描实色纸片 + 首尾外推的连续白线
//   + 折点方块接头」三层重建，白线与纸片共用同一条轮廓，转角与两端天然连续。
//
// 硬约束：内嵌 Lua 字节不变；除 art647/649/650.select.tear.* 之外的控件逐字节不变；
//   功能控件/命中区/教程/v12 资产/红绳层序/结算与首页均不动；非控件脚本区与文件尾不变。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const INPUT = path.join(HERE, '650_优化版.gil');
const OUTPUT = path.join(HERE, '651_撕边修复.gil');
const TRACE = path.join(HERE, '651_设计图白边轨迹.json');
const REPORT = path.join(HERE, '651_撕边修复数据.json');
const SHA = '393db254fc7635361c0fc8269190c886d7d77ced45bb337a8b19599a2a0c4a22';
const hash = b => crypto.createHash('sha256').update(b).digest('hex');

const { readGil, cloneField, ensureChildListTop, findChildListTop,
  asIdList, setChildList, textsOf, encodeMsg, stateBlocks, setPair, pairOf } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { writeGil, findScriptLeaf } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { setHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);

const g = readGil(INPUT);
assert.equal(hash(g.src), SHA, '输入不是本次审计的 650_优化版');
const original = readGil(INPUT);
const scriptBuf = Buffer.from(findScriptLeaf(g).buf);
const by = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => { const r = by.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const recTop = g.tree.find(q => q.field === 9);
const oldRecords = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
let max = BigInt(g.maxId);
const S = 5 / 6;                     // 设计坐标 1920x1080 → 画布 1600x900
const PAPER = '#FFB36E45';          // 647 实测设计图纸片色
const WHITE = '#FFF6E6C4';          // 647/649/650 同一白边色
const WHITE_W = 8;                  // 设计图白线平均 5.5px，留真机取整余量
const EXT = 5;                      // 白线段两端各延长，保证段间重叠
const JOINT = WHITE_W + 3;          // 折点补缝方块边长
const PAPER_STEP = 3.5;
const SAMPLE = 7;

// ── 通用工具 ────────────────────────────────────────────────────────────────
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function setBox(r, x, y, w, h) {     // 设计 px（允许负坐标，用于出画面外）
  const X = x * S, Y = y * S, W = w * S, H = h * S;
  for (const st of stateBlocks(r.field.sub, [])) {
    const p = pairOf(st, 504), s = pairOf(st, 505);
    if (!p || !s) throw Error('原型状态块缺几何字段');
    setPair(p, X + W / 2 - 800, 450 - Y - H / 2);
    setPair(s, W, H);
  }
}
function setRotation(r, deg) {
  for (const st of stateBlocks(r.field.sub, [])) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }]; rf.payload = null; rf.len = 5;
  }
}
function setImageAll(r, imageId, argb) {
  // 图片属性叶子挂在 r.field 的 505→503→84 上（与 650 的 addFresh 同路径），
  // 不是 stateBlocks 内部的几何 505；遍历所有含 84 的分支，避免多状态显示不一致。
  let n = 0;
  for (const p505 of (r.field.sub || []).filter(q => q.field === 505))
    for (const p503 of (p505.sub || []).filter(q => q.field === 503))
      for (const leaf of (p503.sub || []).filter(q => q.field === 84)) {
        setNum(leaf, 502, argb); setNum(leaf, 503, imageId); setNum(leaf, 504, 1); n++;
      }
  assert(n > 0, '未找到图片属性叶子');
}
function childIds(r) { const pc = findChildListTop(r.field.sub); return pc ? asIdList(pc.payload, true) : []; }
function setIds(r, ids) { setChildList(ensureChildListTop(r), ids); }
const added = [];
function cloneKeep(proto, parent, name) {
  const f = cloneField(proto.field), id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nf) throw Error('克隆原型缺名字叶子：' + proto.name);
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = findChildListTop(f.sub); if (cl) setChildList(cl, []);
  recTop.sub.push(f);
  setIds(parent, [...childIds(parent), id]);
  setHiddenRecord(f, false);
  const r = { id, name, parentId: parent.id, field: f };
  added.push(r); by.set(name, r);
  return r;
}
function addRect(parent, name, x, y, w, h, color, rot = 0) {
  const r = cloneKeep(R('td.home.page.1.help619.icon'), parent, name);
  setBox(r, x, y, w, h);
  setRotation(r, rot);
  setImageAll(r, 100001, parseInt(color.slice(1), 16));
  return r;
}

// ── ① 删除 650 全部旧撕边层 ────────────────────────────────────────────────
const OLD = /^art(?:647|649|650)\.select\.tear\./;
const doomed = g.recs.filter(r => OLD.test(r.name || ''));
assert.equal(doomed.length, 720, '旧撕边层数与 650 审计不符');
const doomedIds = new Set(doomed.map(r => r.id));
const doomedFields = new Set(doomed.map(r => r.field));
for (let i = recTop.sub.length - 1; i >= 0; i--) if (doomedFields.has(recTop.sub[i])) recTop.sub.splice(i, 1);
for (const r of doomed) { g.recs.splice(g.recs.indexOf(r), 1); by.delete(r.name); }
// 父级 childList 清理（board 715 层 + buttons 5 条桥接）；这两个父记录字节会变
const changedParents = new Set(doomed.map(r => r.parentId));
for (const pid of changedParents) {
  const p = g.recs.find(r => r.id === pid);
  assert(p, '旧撕边父级丢失 ' + pid);
  setIds(p, childIds(p).filter(id => !doomedIds.has(id)));
}
// 剩余记录中不得残留对被删记录的引用
function scanRefs(fields, owner = null) {
  for (const f of fields) {
    if (f.wt === 0 && f.num != null && doomedIds.has(Number(f.num))) throw Error('残留整数引用 ' + f.field);
    if (f.wt === 2 && f.payload && !f.isText && !f.sub) {
      const list = asIdList(f.payload, true);
      if (list?.some(id => doomedIds.has(id))) throw Error('残留 packed 引用 ' + f.field);
    }
    if (f.sub) scanRefs(f.sub, owner);
  }
}
scanRefs(g.tree);
const board = R('art642.select.board');
assert.equal(childIds(board).length, 0, 'board 应只剩非撕边层（650 中 board 全为撕边层）');

// ── ② 设计图白边轨迹：首尾外推 + 等弧长重采样 ──────────────────────────────
const trace = JSON.parse(fs.readFileSync(TRACE, 'utf8'));
assert.equal(trace.design[0], 1920); assert.equal(trace.design[1], 1080);
const EXTEND = 64;
function prepare(raw, axis) {
  const pts = raw.map(p => [p[0], p[1]]);
  const head = pts.slice(0, 8), tail = pts.slice(-8);
  const unit = (a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy) || 1; return [dx / L, dy / L]; };
  const u0 = unit(head[0], head[head.length - 1]), u1 = unit(tail[0], tail[tail.length - 1]);
  const first = [pts[0][0] - u0[0] * EXTEND, pts[0][1] - u0[1] * EXTEND];
  const last = [pts[pts.length - 1][0] + u1[0] * EXTEND, pts[pts.length - 1][1] + u1[1] * EXTEND];
  const all = [first, ...pts, last];
  assert(all.every((p, i) => i === 0 || p[axis === 'x' ? 0 : 1] >= all[i - 1][axis === 'x' ? 0 : 1]), '轨迹非单调');
  return all;
}
const trAll = prepare(trace.tr, 'x'), blAll = prepare(trace.bl, 'y');
function at(pts, key, v) {                 // 线性插值；超出端点按端点斜率外推
  const k = key === 'x' ? 0 : 1, o = 1 - k;
  if (v <= pts[0][k]) { const s = (pts[1][o] - pts[0][o]) / (pts[1][k] - pts[0][k]); return pts[0][o] + s * (v - pts[0][k]); }
  if (v >= pts[pts.length - 1][k]) { const a = pts[pts.length - 2], b = pts[pts.length - 1]; return b[o] + (b[o] - a[o]) / (b[k] - a[k]) * (v - b[k]); }
  let lo = 0, hi = pts.length - 1;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (pts[m][k] <= v) lo = m; else hi = m; }
  const a = pts[lo], b = pts[hi], t = (v - a[k]) / (b[k] - a[k] || 1);
  return a[o] + (b[o] - a[o]) * t;
}
function resample(pts, step) {
  const out = [pts[0].slice()];
  let acc = 0;
  for (let i = 1; i < pts.length; i++) {
    let a = out[out.length - 1], b = pts[i];
    let d = Math.hypot(b[0] - a[0], b[1] - a[1]);
    while (acc + d >= step) {
      const t = (step - acc) / d;
      const np = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      out.push(np); a = np; d = Math.hypot(b[0] - a[0], b[1] - a[1]); acc = 0;
    }
    acc += d;
  }
  const last = pts[pts.length - 1];
  if (Math.hypot(last[0] - out[out.length - 1][0], last[1] - out[out.length - 1][1]) > 1) out.push(last.slice());
  return out;
}
const trPts = resample(trAll, SAMPLE), blPts = resample(blAll, SAMPLE);

// ── ③ 纸片扫描填充（轮廓内侧，实色，不透明；白线之前全部画完） ────────────
const counts = { paperTR: 0, paperBL: 0, whiteTR: 0, whiteBL: 0, joint: 0 };
for (let x = 1430, i = 0; x <= 1920; x += PAPER_STEP, i++) {
  const h = at(trAll, 'x', x) + 80 + WHITE_W / 2 + 2;
  if (h > 0.5) { addRect(board, `art651.select.tear.tr.paper.${i}`, x, -80, PAPER_STEP + 0.9, h, PAPER); counts.paperTR++; }
}
for (let y = 800, i = 0; y <= 1080; y += PAPER_STEP, i++) {
  const w = at(blAll, 'y', y) + 80 + WHITE_W / 2 + 2;
  if (w > 0.5) { addRect(board, `art651.select.tear.bl.paper.${i}`, -80, y, w, PAPER_STEP + 0.9, PAPER); counts.paperBL++; }
}

// ── ④ 连续白线 + 折点接头 ─────────────────────────────────────────────────
function whiteLine(tag, pts) {
  const seq = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const a = pts[i], b = pts[i + 1], dx = b[0] - a[0], dy = b[1] - a[1];
    const len = Math.hypot(dx, dy);
    if (len < 0.01) continue;
    const L = len + 2 * EXT, cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2;
    const rot = -Math.atan2(dy, dx) * 180 / Math.PI;
    addRect(board, `art651.select.tear.${tag}.white.${i}`, cx - L / 2, cy - WHITE_W / 2, L, WHITE_W, WHITE, rot);
    seq.push(rot);
    if (tag === 'tr') counts.whiteTR++; else counts.whiteBL++;
  }
  // 折点（含两端）：角度差大于 10° 或端点处补一个正方形接头，消除 V 形黑缝
  const angles = pts.slice(0, -1).map((p, i) => Math.atan2(pts[i + 1][1] - p[1], pts[i + 1][0] - p[0]) * 180 / Math.PI);
  for (let i = 0; i < pts.length; i++) {
    let da = 0;
    if (i > 0) { let x = angles[i - 1] - (angles[i] ?? angles[i - 1]); while (x > 180) x -= 360; while (x < -180) x += 360; da = Math.abs(x); }
    if (i === 0 || i === pts.length - 1 || da > 10) {
      addRect(board, `art651.select.tear.${tag}.joint.${i}`, pts[i][0] - JOINT / 2, pts[i][1] - JOINT / 2, JOINT, JOINT, WHITE);
      counts.joint++;
    }
  }
}
whiteLine('tr', trPts);
whiteLine('bl', blPts);
const newTotal = counts.paperTR + counts.paperBL + counts.whiteTR + counts.whiteBL + counts.joint;
assert.equal(added.length, newTotal);

// ── ⑤ 写档 + 逐项校验 ─────────────────────────────────────────────────────
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const rep = writeGil(g, OUTPUT, {
  label: '651 tear rebuild from design trace on top of 650 optimized',
  expectRecs: expected.size, expectMarker: 'v635', quiet: true,
  assert: g2 => {
    if (!findScriptLeaf(g2).buf.equals(scriptBuf)) return 'script changed unexpectedly';
    for (const r of g2.recs) {
      // 父记录（board / buttons）与全部新增层用构建后的期望字节；其余保留记录用输入档字节
      const exp = (oldRecords.has(r.id) && !changedParents.has(r.id)) ? oldRecords.get(r.id) : expected.get(r.id);
      if (!exp?.equals(encodeMsg([r.field]))) return 'record mismatch ' + r.name;
    }
    const ids = new Set(g2.recs.map(r => r.id));
    for (const r of g2.recs) if (r.childList) for (const id of asIdList(r.childList.payload, true) || [])
      assert(ids.has(id), '残留断链');
    for (let i = 0; i < original.tree.length; i++) {
      const f = original.tree[i];
      if (f.field !== 9 && f.field !== 50) assert(encodeMsg([f]).equals(encodeMsg([g2.tree[i]])), '非控件/脚本区发生变化');
    }
    assert(g2.trailer.equals(original.trailer), '文件尾变化');
    return true;
  },
});
const disk = readGil(OUTPUT);
const names = new Set(disk.recs.map(r => r.name).filter(Boolean));
for (const r of added) assert(names.has(r.name), '磁盘缺新层 ' + r.name);
for (const n of ['police-v12', 'art647.home.settle.ribbon', 'settle.btn', 'hit.select.prev', 'hit.select.next',
  'art647.select.diamond.left', 'art647.select.diamond.right', 'art650.select.cord.8', 'td.home.page.1.help619.icon'])
  assert(names.has(n), '关键控件丢失 ' + n);
assert(![...names].some(n => OLD.test(n)), '旧撕边层残留');
assert(findScriptLeaf(disk).buf.equals(scriptBuf), '磁盘脚本与输入不一致');
assert.equal(disk.recs.length, g.recs.length + added.length);

const result = {
  base: '650_优化版.gil', baseSha256: SHA,
  output: path.basename(OUTPUT), outputSha256: hash(rep.g2.src),
  inputBytes: g.src.length, outputBytes: rep.bytes,
  records: { before: original.recs.length, removed: doomed.length, added: added.length, after: disk.recs.length },
  scriptBytesUnchanged: scriptBuf.length,
  retainedRecordBytesUnchanged: original.recs.length - doomed.length - changedParents.size,
  changedParentRecords: [...changedParents],
  designTrace: { design: trace.design, trPoints: trace.tr.length, blPoints: trace.bl.length,
    extendDesignPx: EXTEND, resampleStepDesignPx: SAMPLE },
  rebuild: { whiteWidthDesignPx: WHITE_W, segmentOverlapDesignPx: EXT, jointSizeDesignPx: JOINT,
    paperStepDesignPx: PAPER_STEP, trSegments: trPts.length - 1, blSegments: blPts.length - 1,
    layers: counts },
  layerOrder: 'board 子列表与全局记录表同序：tr/bl 纸片 → tr/bl 白线 → 折点接头',
  checks: { inputShaLocked: true, scriptUnchanged: true, retainedRecordsByteIdentical: true,
    nonUiNonScriptFieldsUnchanged: true, trailerUnchanged: true, noDanglingChildIds: true,
    noOldTearLayers: true, noExternalRefsToRemoved: true, diskReread: true },
};
fs.writeFileSync(REPORT, JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
