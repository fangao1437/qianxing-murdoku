// 672 · 按设计图重做几何构造（右侧梯形 + 中间异色三角区），描边改暗红
//
// 基准 671_文本与细线.gil（7044 条，每模板 4 个可见视觉层：backrop1/2 + hi + lo）
// 用户要求：保留「最少图元」目标，只多 3 个图元/模板：
//   ① 中间异色三角区：2 枚 100003 等腰三角
//      - mid1 等腰钝角三角：底边 = 目标区左边界 A→C，一条腰 C→P 沿右边界下段
//      - mid2 等腰三角：底边 = 右边界上段，顶点落在顶边左端 A（左上方）
//      两枚部分重叠 ⇒ 覆盖率 100% / 溢出 0，零拼接缝
//   ② 右侧梯形：只多 1 枚 100001 矩形（暗红），复用 671 的 lo 三角改形为主色遮盖三角
//      矩形先画、遮盖三角后画，三角底边 = 梯形左斜边 ⇒ 干净斜边、无竖直硬边
//   ③ 描边：backrop1 静态色 #56565E → 暗红 #491B1E；内嵌 Lua 与高亮色逐字节不变
// 黑色方块与噪点（设计稿占位/纹理）一律不引入。
//
// 输入  671_文本与细线/671_文本与细线.gil
// 输出  672_梯形与异色区/672_梯形与异色区.gil + 672_构建审计.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/672_梯形与异色区');
const INPUT = path.join(ROOT, 'qianxing-murdoku/671_文本与细线/671_文本与细线.gil');
const OUTPUT = path.join(DIR, '672_梯形与异色区.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const DRY = process.argv.includes('--dry');

const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf,
  findChildListTop, asIdList, setChildList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

// ── 设计图实测 → 卡面 324×79.4 映射 ──────────────────────────────────────
// 设计图 578×170；内卡 x14..572 / y20..160；噪点与黑色方块为设计稿占位，不复刻
// 中间异色区：左 x=269.3-0.389y、右 x=368-1.126y、顶 y=20，交点 y≈134
// 梯形左斜边：x=573-1.455y，从 (543.9,20) 到 (340.2,160)
const SX = 324 / 558, SY = 79.4 / 140;
const map = (xd, yd) => [638 + (xd - 14) * SX, 410.3 + (yd - 20) * SY];
const RECT = { x0: 638, y0: 410.3, x1: 962, y1: 489.7 };
const TARGET = { A: map(261.5, 20), B: map(345.5, 20), C: map(217.2, 134) };
const TRAP_LINE = { top: map(543.9, 20), bottom: map(340.2, 160) };

// 配色（高亮色由 Lua 写入，本脚本完全不碰 Lua）
const COLOR = {
  stroke: '#491B1E',   // 新：暗红描边（backrop1 静态色）
  main:   '#68262A',   // 不变：backrop2 主色，也是梯形遮盖三角颜色
  hi:     '#9D3033',   // 不变：左上亮红
  mid:    '#702830',   // 新：中间异色区（设计图实测）
  dark:   '#611F23',   // 不变：671 lo 的暗红，现用于梯形矩形
};

// 解析构造（数值验证：覆盖率 100%、溢出 0）——参数由设计图边界直接推导，避免舍入误差
// 100003 实测模型：本地顶点 (0,-h/2)、底边 y=+h/2，故 h = 顶点到底边的高；
// 中心 = 底边中点与顶点的中点；顶点方向 = (-sin rot, -cos rot)。
const cross = (a, b) => a[0] * b[1] - a[1] * b[0];
const sub = (p, q) => [p[0] - q[0], p[1] - q[1]];
const add = (p, q) => [p[0] + q[0], p[1] + q[1]];
const mul = (p, k) => [p[0] * k, p[1] * k];
const norm = p => Math.hypot(...p);
const unit = p => mul(p, 1 / norm(p));
const inRect = (p, eps = 0.05) => p[0] >= RECT.x0 - eps && p[0] <= RECT.x1 + eps
  && p[1] >= RECT.y0 - eps && p[1] <= RECT.y1 + eps;
function inTri(P, T) {
  const [a, b, c] = T;
  const d1 = cross([b[0] - a[0], b[1] - a[1]], [P[0] - a[0], P[1] - a[1]]);
  const d2 = cross([c[0] - b[0], c[1] - b[1]], [P[0] - b[0], P[1] - b[1]]);
  const d3 = cross([a[0] - c[0], a[1] - c[1]], [P[0] - c[0], P[1] - c[1]]);
  return (d1 >= -1e-6 && d2 >= -1e-6 && d3 >= -1e-6) || (d1 <= 1e-6 && d2 <= 1e-6 && d3 <= 1e-6);
}
function triParams(E1, E2, P) {
  const M = mul(add(E1, E2), 0.5), d = norm(sub(P, M)), n = mul(sub(P, M), 1 / d);
  return {
    cx: (M[0] + P[0]) / 2, cy: (M[1] + P[1]) / 2,
    w: norm(sub(E2, E1)), h: d,
    rot: Math.atan2(-n[0], -n[1]) * 180 / Math.PI,
    verts: [E1, E2, P],
  };
}
const [A, B, C] = [TARGET.A, TARGET.B, TARGET.C];
// ① mid1：等腰钝角三角，底边 = 左边界 A→C；一条腰 C→P1 沿右边界（C→B）方向
const uL = unit(sub(C, A)), nL = [uL[1], -uL[0]];
const ML = mul(add(A, C), 0.5);
const d1 = -cross(sub(B, C), sub(ML, C)) / cross(sub(B, C), nL);
const P1 = add(ML, mul(nL, d1));
// ② mid2：等腰三角，底边 = 右边界上段，顶点 P2 落在顶边左端 A（左上方）
const uR = unit(sub(C, B)), nR = [-uR[1], uR[0]];
const kR = (C[0] - B[0]) / (C[1] - B[1]);
const d2 = (A[0] - B[0] - kR * (A[1] - B[1])) / (nR[0] - kR * nR[1]);
const P2 = [A[0], A[1]], M2 = sub(P2, mul(nR, d2));
const s2 = (M2[0] - B[0]) / uR[0];
const E1 = sub(M2, mul(uR, s2)), E2 = add(M2, mul(uR, s2));
const MID1 = { tag: 'mid1', ...triParams(A, C, P1) };
const MID2 = { tag: 'mid2', ...triParams(E1, E2, P2) };
// ③ 梯形：遮盖三角底边 = 左斜边 TA→TB，顶点落在卡片上边 y0；矩形从该顶点 x 到右边界
const [TA, TB] = [TRAP_LINE.top, TRAP_LINE.bottom];
const uT = unit(sub(TB, TA)), vT = [uT[1], -uT[0]], nT = [-vT[0], -vT[1]];
const MT = mul(add(TA, TB), 0.5);
const dT = (MT[1] - RECT.y0) / (-nT[1]);
const PT = add(MT, mul(nT, dT));
const COVER = { tag: 'cover', ...triParams(TA, TB, PT) };
const TRAP_RECT = { cx: (PT[0] + RECT.x1) / 2, cy: (RECT.y0 + RECT.y1) / 2,
  w: RECT.x1 - PT[0], h: RECT.y1 - RECT.y0, rot: 0 };
// ④ 补角：斜边在 y>y_cross 后落在矩形左边界以左，需一枚很小的暗红等腰三角补到底边
//   （零溢出约束下，单个矩形 + 单个等腰三角无法把单斜边一直延伸到卡片下边）
const kT = (TB[0] - TA[0]) / (TB[1] - TA[1]);
const QY = RECT.y0 + (TA[0] - PT[0]) / (-kT);      // 斜边与矩形左边界的交点
const CORNER_Q = [PT[0], QY], CORNER_R = [PT[0], RECT.y1];
function fitCorner(tri) {
  const [q, b, r] = tri;
  const xs = tri.map(p => p[0]), ys = tri.map(p => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  const N = 70, pts = [], mask = [];
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    const P = [x0 + (i + 0.5) * (x1 - x0) / N, y0 + (j + 0.5) * (y1 - y0) / N];
    pts.push(P); mask.push(inTri(P, tri));
  }
  const total = mask.filter(Boolean).length, WORDS = Math.ceil(pts.length / 32);
  const tmask = new Uint32Array(WORDS);
  for (let k = 0; k < pts.length; k++) if (mask[k]) tmask[k >>> 5] |= 1 << (k & 31);
  const pc = v => { v = v - ((v >>> 1) & 0x55555555); v = (v & 0x33333333) + ((v >>> 2) & 0x33333333); return (((v + (v >>> 4)) & 0x0F0F0F0F) * 0x01010101) >>> 24; };
  const centroid = [(q[0] + b[0] + r[0]) / 3, (q[1] + b[1] + r[1]) / 3];
  const edges = [[q, b], [b, r], [r, q]];
  let best = null;
  for (const [e1, e2] of edges) {
    const L = norm(sub(e2, e1)), u = unit(sub(e2, e1));
    let n = [-u[1], u[0]];
    if (cross(sub(centroid, mul(add(e1, e2), 0.5)), n) < 0) n = mul(n, -1);
    for (let t = 0; t <= 1.0001; t += 0.1) {
      const M = add(e1, mul(sub(e2, e1), t));
      for (let s = L * 0.25; s <= L * 1.0001; s += L * 0.05)
        for (let d = 1; d <= 34; d += 1.5) {
          const E1 = sub(M, mul(u, s)), E2 = add(M, mul(u, s)), P = add(M, mul(n, d));
          if (![E1, E2, P].every(p => inRect(p))) continue;
          const T = [E1, E2, P], bits = new Uint32Array(WORDS);
          for (let k = 0; k < pts.length; k++) if (inTri(pts[k], T)) bits[k >>> 5] |= 1 << (k & 31);
          let hit = 0, extra = 0;
          for (let k = 0; k < WORDS; k++) { hit += pc(bits[k] & tmask[k]); extra += pc(bits[k] & ~tmask[k]); }
          const score = hit - 1.3 * extra;
          if (!best || score > best.score) best = { ...triParams(E1, E2, P), score, hit, extra, coverage: hit / total, extraRate: extra / total };
        }
    }
  }
  return best;
}
const CORNER = { tag: 'corner', ...fitCorner([CORNER_Q, TB, CORNER_R]) };

// ── 几何闸门（构建时硬校验） ──────────────────────────────────────────────
function triVertices(cx, cy, w, h, rot) {
  const a = -rot * Math.PI / 180;
  return [[0, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]]
    .map(([x, y]) => [cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)]);
}
for (const L of [MID1, MID2, COVER, CORNER]) {
  const v = triVertices(L.cx, L.cy, L.w, L.h, L.rot);
  // 集合比对（参数模型顶点顺序为 [顶点, 底边左, 底边右]，声明顺序为 [E1, E2, P]）
  const err = Math.max(...v.map(p => Math.min(...L.verts.map(q => Math.hypot(p[0] - q[0], p[1] - q[1])))));
  if (err > 0.15) throw Error(L.tag + ' 参数与三顶点不一致，最大误差 ' + err);
  if (!L.verts.every(p => inRect(p))) throw Error(L.tag + ' 顶点溢出卡片');
}
// 矩形零溢出
if (![[TRAP_RECT.cx - TRAP_RECT.w / 2, TRAP_RECT.cy - TRAP_RECT.h / 2],
      [TRAP_RECT.cx + TRAP_RECT.w / 2, TRAP_RECT.cy + TRAP_RECT.h / 2]].every(p => inRect(p)))
  throw Error('梯形矩形溢出卡片');
// 中间区覆盖率
let midTotal = 0, midHit = 0;
const mnx = Math.min(...[TARGET.A, TARGET.B, TARGET.C].map(p => p[0])), mxx = Math.max(...[TARGET.A, TARGET.B, TARGET.C].map(p => p[0]));
const mny = Math.min(...[TARGET.A, TARGET.B, TARGET.C].map(p => p[1])), mxy = Math.max(...[TARGET.A, TARGET.B, TARGET.C].map(p => p[1]));
for (let j = 0; j < 140; j++) for (let i = 0; i < 140; i++) {
  const P = [mnx + (i + 0.5) * (mxx - mnx) / 140, mny + (j + 0.5) * (mxy - mny) / 140];
  if (!inTri(P, [TARGET.A, TARGET.B, TARGET.C])) continue;
  midTotal++;
  if (inTri(P, MID1.verts) || inTri(P, MID2.verts)) midHit++;
}
const midCoverage = midHit / midTotal;
if (midCoverage < 0.999) throw Error('中间区两枚三角覆盖率不足：' + (midCoverage * 100).toFixed(2) + '%');
// 梯形一致性：可见暗红 = (矩形 ∪ 补角三角) ∧ ¬主色遮盖三角；目标暗红 = x ≥ 左斜边
let trapTotal = 0, trapOk = 0;
const inRectLayer = p => Math.abs(p[0] - TRAP_RECT.cx) <= TRAP_RECT.w / 2 && Math.abs(p[1] - TRAP_RECT.cy) <= TRAP_RECT.h / 2;
const Lx = y => TRAP_LINE.top[0] + (TRAP_LINE.bottom[0] - TRAP_LINE.top[0]) * (y - RECT.y0) / (RECT.y1 - RECT.y0);
for (let j = 0; j < 90; j++) for (let i = 0; i < 200; i++) {
  const P = [RECT.x0 + (i + 0.5) * 324 / 200, RECT.y0 + (j + 0.5) * 79.4 / 90];
  trapTotal++;
  const visible = (inRectLayer(P) || inTri(P, CORNER.verts)) && !inTri(P, COVER.verts);
  const target = P[0] >= Lx(P[1]);
  if (visible === target) trapOk++;
}
const trapAccuracy = trapOk / trapTotal;
if (trapAccuracy < 0.995) throw Error('梯形构造与设计图不符：' + (trapAccuracy * 100).toFixed(2) + '%');
if (CORNER.coverage < 0.90) throw Error('补角三角拟合不足：' + (CORNER.coverage * 100).toFixed(2) + '%');

// ── gil 读写工具 ─────────────────────────────────────────────────────────
const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recTop = g.tree.find(q => q.field === 9);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const origIds = new Set(g.recs.map(r => r.id));
const origParent = new Map(g.recs.map(r => [r.id, r.parentId]));
const danglingBefore = new Set([...origIds].filter(id =>
  origParent.get(id) != null && !origIds.has(origParent.get(id))));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
function screenGeom(r) {
  const st = states(r)[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
const added = [], hidden = [], touched = new Set(), modified = [];
function touch(r) { touched.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function retint(r, hex) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(hex)); setNum(p, 504, 1); touch(r);
}
function reshape(r, o) {
  for (const st of states(r)) {
    setPair(pairOf(st, 504), o.cx - 800, 450 - o.cy);
    setPair(pairOf(st, 505), o.w, o.h);
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: o.rot }]; rf.payload = null; rf.len = 5;
  }
  touch(r);
}
const PROTO = 'td.home.page.1.help619.icon';
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
let max = BigInt(g.maxId);
function cloneLayer(parent, name, o) {
  const proto = byName.get(o.proto || PROTO);
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  if (parent) f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = (function find(ff) { return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  const idx = recTop.sub.findIndex(q => q === byId.get(o.beforeId)?.field);
  if (idx < 0) throw Error('beforeId 不在 recTop ' + o.beforeId);
  recTop.sub.splice(idx, 0, f);
  const ip = ns(f, [505, 503, 84])[0];
  if (o.color) { setNum(ip, 502, colorOf(o.color)); setNum(ip, 503, o.imageId ?? 100001); setNum(ip, 504, 1); }
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  for (const st of states(r)) {
    setPair(pairOf(st, 504), o.cx - 800, 450 - o.cy);
    setPair(pairOf(st, 505), o.w, o.h);
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: o.rot || 0 }]; rf.payload = null; rf.len = 5;
  }
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}

// ── 两套 clue 模板 ───────────────────────────────────────────────────────
const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (TPL.length !== 2) throw Error('clue 模板数不符：' + TPL.length);
const summary = [];
let n = 0;
for (const root of TPL) {
  n++;
  const kids = g.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const hi = kids.find(r => r.name === `art671.clue${n}.hi`);
  const lo = kids.find(r => r.name === `art671.clue${n}.lo`);
  if (!b1 || !b2 || !hi || !lo) throw Error('671 层缺失 #' + root.id);
  const g1 = screenGeom(b1), g2 = screenGeom(b2);
  if (Math.abs(g1[2] - 330) > 0.01 || Math.abs(g2[2] - 324) > 0.01) throw Error('backrop 几何不符');
  const textKids = kids.filter(r => ['who', 'what', 'letter', 'face'].includes(r.name));
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  textKids.sort((a, b) => order.get(a.field) - order.get(b.field));
  const firstText = textKids[0];
  if (!firstText) throw Error('模板缺文本控件：' + root.id);

  // ① 描边：只改 backrop1 的静态色，Lua 写入的高亮色不变
  retint(b1, COLOR.stroke);
  // ② 复用 lo：改形为主色遮盖三角（底边 = 梯形左斜边），颜色与 backrop2 完全一致
  reshape(lo, COVER); retint(lo, COLOR.main);
  // ③ 梯形矩形：必须插在 lo 之前（矩形先画，遮盖三角后画）
  cloneLayer(root, `art672.clue${n}.trap`, {
    ...TRAP_RECT, color: COLOR.dark, imageId: 100001, beforeId: lo.id,
  });
  // ④ 中间异色区两枚三角：插在最早文本控件之前（671 层序教训）
  cloneLayer(root, `art672.clue${n}.mid1`, {
    ...MID1, color: COLOR.mid, imageId: 100003, beforeId: firstText.id,
  });
  cloneLayer(root, `art672.clue${n}.mid2`, {
    ...MID2, color: COLOR.mid, imageId: 100003, beforeId: firstText.id,
  });
  // ⑤ 补角三角：把梯形斜边一直补到卡片下边（零溢出、无竖直硬边）
  cloneLayer(root, `art672.clue${n}.corner`, {
    ...CORNER, color: COLOR.dark, imageId: 100003, beforeId: firstText.id,
  });
  summary.push({ rootId: root.id, firstText: firstText.name,
    backrop1: g1, backrop2: g2, hiKept: hi.name, loRepurposed: lo.name,
    added: [`art672.clue${n}.trap`, `art672.clue${n}.mid1`, `art672.clue${n}.mid2`, `art672.clue${n}.corner`] });
}

// ── childList 同步 ───────────────────────────────────────────────────────
const fieldIndex = new Map(); recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set(added.map(r => r.parentId))) {
  const p = byId.get(pid), cl = findChildListTop(p.field.sub);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids); touch(p);
}

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })(g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE, recordsBefore: beforeBytes.size,
    recordsAfter: expected.size, added: added.length, modified: modified.length,
    midCoverage, trapAccuracy, cornerCoverage: CORNER.coverage, cornerExtraRate: CORNER.extraRate, summary }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '672 trapezoid + two-triangle accent zone, dark red stroke, minimal primitives',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化（高亮色必须不变）';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touched.has(r.id) && !added.some(a => a.id === r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return '非目标记录被改动 ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const recTop2 = t.tree.find(q => q.field === 9);
    const idx = new Map(); recTop2.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const kids = t.recs.filter(q => q.parentId === root.id);
      const newArt = kids.filter(q => /^art672\./.test(q.name || '') && !isHiddenRecord(q.field));
      const texts = kids.filter(q => ['who', 'what', 'letter', 'face'].includes(q.name));
      const firstText = Math.min(...texts.map(q => idx.get(q.field)));
      if (newArt.length !== 4) return '新层数量不符 #' + root.id;
      if (newArt.some(q => idx.get(q.field) > firstText)) return '新层仍在文本之上 #' + root.id;
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '672 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '671_文本与细线.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '672_梯形与异色区.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    reference: '设计图 578×170（黑色方块与噪点为设计稿占位/纹理，不复刻）；实机线索卡 324×79.4 @ x638..962 / y410.3..489.7',
    mapping: { sx: SX, sy: SY, midLeft: 'x=269.3-0.389y', midRight: 'x=368-1.126y', midTop: 'y=20', midApex: 'y≈134', trapLeft: 'x=573-1.455y' },
    targetMidTriangle: TARGET, trapLeftLine: TRAP_LINE,
    construction: '中间异色区＝2 枚 100003 等腰三角（mid1 钝角三角底边=左边界、一条腰=右边界下段；mid2 顶点在左上方、底边=右边界上段），部分重叠、零溢出；右侧梯形＝1 枚 100001 暗红矩形 + 复用 671 的 lo 改为主色遮盖三角（底边=梯形左斜边）+ 1 枚极小暗红补角三角（把斜边补到卡片下边）。矩形先画、遮盖三角后画。',
    whyCorner: '零溢出约束下，等腰三角的右腰无法一直延伸到卡片下边；只有矩形时斜边会在 y≈468 折成竖线，底部露出 32.5px 竖直硬边（670 曾因同类硬边返工）。补角三角面积仅占卡面 0.14%，是单斜边梯形的最省补法。',
    colors: { ...COLOR, highlight: '由内嵌 Lua 写入，脚本逐字节未改 ⇒ 高亮色不变' },
    geometry: { mid1: MID1, mid2: MID2, trapRect: TRAP_RECT, coverTriangle: COVER, cornerTriangle: CORNER },
    gates: { midCoverage, trapAccuracy, cornerCoverage: CORNER.coverage, cornerExtraRate: CORNER.extraRate,
      allVerticesInside: true, samplesMid: midTotal, samplesTrap: trapTotal },
    guarantees: '边缘由 backrop2 矩形给出；所有图元顶点严格在 324×79.4 内；同色不透明重叠无缝；无安全矩形/补漏矩形 ⇒ 无竖直细线；新层全部插在最早文本控件之前；Lua 与 26 条文本零改动。',
    minimalPrimitives: '每模板可见视觉层 4 → 8（新增 4：1 矩形 + 3 三角，其中 lo 复用改形），仍仅为 670 拼接版 32 层的 25%，671 最少图元目标不破坏。',
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  visibleLayersPerTemplate: 8, previousVisibleLayersPerTemplate: 4,
  summary, modified, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '672_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, modified: modified.length,
  midCoverage: +(midCoverage * 100).toFixed(2), trapAccuracy: +(trapAccuracy * 100).toFixed(2),
  cornerCoverage: +(CORNER.coverage * 100).toFixed(2),
  visibleLayersPerTemplate: 8, scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
