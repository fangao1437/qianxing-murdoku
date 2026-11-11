// 670 · 按 backrop2 尺寸重新生成零溢出阶梯渐变，消除毛刺/漏底色/顶部白带
//
// 669 的问题：把 661 那套针对 330×85.4 精算的 28 层 fillRegion 图元做非等比缩放
//   (SX=0.9818, SY=0.9297)，三角斜边角度与补漏矩形位置全部失配 ⇒
//   ① 部分图元溢出卡片边界 → 黄描边内侧毛刺；② 部分区域未铺满 → 漏暗底色；
//   ③ art658.clueN.rule 白线落在卡片顶边 → 设计图没有的白带。
//
// 本轮：隐藏 669 那 30 层（含白线），用 661 的 fillRegion 算法针对
//   **324×79.4**（x638..962 / y410.3..489.7，中心 800,450）重新生成一整套：
//   base 铺满整卡 + 4 级 45° 斜向阶梯，每级自带「零溢出顶点 + 覆盖率≥99%」自检。
//   ⇒ 拼接图元全部落在卡内、边缘平直、整卡不漏底色。
//
// 基准：669_旧高亮方案.gil
// 输出：670_渐变收敛.gil + 670_构建审计.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/670_渐变收敛');
const INPUT = path.join(ROOT, 'qianxing-murdoku/669_旧高亮方案/669_旧高亮方案.gil');
const OUTPUT = path.join(DIR, '670_渐变收敛.gil');
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
function hide(r) {
  if (isHiddenRecord(r.field)) return;
  setHiddenRecord(r.field, true); hidden.push(r.name); touch(r);
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
  if (!proto) throw Error('缺原型 ' + (o.proto || PROTO));
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nf) throw Error('找不到名字字段 ' + proto.name);
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  if (parent) f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = (function find(ff) { return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  let idx = -1;
  if (o.beforeId !== undefined) idx = recTop.sub.findIndex(q => q === byId.get(o.beforeId)?.field);
  else if (o.before) idx = recTop.sub.findIndex(q => q === byName.get(o.before)?.field);
  if (idx < 0) idx = recTop.sub.length;
  recTop.sub.splice(idx, 0, f);
  const ip = ns(f, [505, 503, 84])[0];
  if (ip && o.color) { setNum(ip, 502, colorOf(o.color)); setNum(ip, 503, o.imageId ?? 100001); setNum(ip, 504, 1); }
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  for (const st of states(r)) {
    setPair(pairOf(st, 504), o.cx - 800, 450 - o.cy);
    setPair(pairOf(st, 505), o.w, o.h);
  }
  if (o.rot) {
    for (const st of states(r)) {
      let rf = st.sub.find(q => q.field === 508);
      if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
      rf.sub = [{ field: 3, wt: 5, f: o.rot }]; rf.payload = null; rf.len = 5;
    }
  }
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}

// ── 661 的凸多边形 / 零溢出几何工具（原样复用） ─────────────────────────────
const rotPt = (cx, cy, deg, lx, ly) => {
  const a = deg * Math.PI / 180;
  return [cx + lx * Math.cos(a) - ly * Math.sin(a), cy + lx * Math.sin(a) + ly * Math.cos(a)];
};
function inPoly(poly, x, y) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
  }
  return c;
}
function inside(poly, x, y, eps = 0.75) {
  if (inPoly(poly, x, y)) return true;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [ax, ay] = poly[j], [bx, by] = poly[i];
    const vx = bx - ax, vy = by - ay, L2 = vx * vx + vy * vy;
    if (!L2) continue;
    let t = ((x - ax) * vx + (y - ay) * vy) / L2;
    t = Math.max(0, Math.min(1, t));
    if (Math.hypot(x - (ax + t * vx), y - (ay + t * vy)) <= eps) return true;
  }
  return false;
}
function polyRight(poly, y) {
  let best = -Infinity;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y)) { const x = (xj - xi) * (y - yi) / (yj - yi) + xi; if (x > best) best = x; }
  }
  return best;
}
function localOf(s, x, y) {
  const dx = x - s.cx, dy = y - s.cy, a = s.rot * Math.PI / 180;
  return [dx * Math.cos(a) - dy * Math.sin(a), dx * Math.sin(a) + dy * Math.cos(a)];
}
function inShape(s, x, y) {
  const [lx, ly] = localOf(s, x, y);
  if (s.img === 100003) {
    const A = [0, -s.h / 2], B = [-s.w / 2, s.h / 2], C = [s.w / 2, s.h / 2];
    const cr = (p, q, r) => (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]);
    const d1 = cr(A, B, [lx, ly]), d2 = cr(B, C, [lx, ly]), d3 = cr(C, A, [lx, ly]);
    return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
  }
  return Math.abs(lx) <= s.w / 2 + 0.01 && Math.abs(ly) <= s.h / 2 + 0.01;
}
function vertices(s) {
  const loc = s.img === 100003
    ? [[0, -s.h / 2], [-s.w / 2, s.h / 2], [s.w / 2, s.h / 2]]
    : [[-s.w / 2, -s.h / 2], [s.w / 2, -s.h / 2], [s.w / 2, s.h / 2], [-s.w / 2, s.h / 2]];
  const a = -s.rot * Math.PI / 180;
  return loc.map(([x, y]) => [s.cx + x * Math.cos(a) - y * Math.sin(a), s.cy + x * Math.sin(a) + y * Math.cos(a)]);
}
function coverage(poly, shapes, step = 2) {
  let n = 0, hit = 0;
  const xs = poly.map(p => p[0]), ys = poly.map(p => p[1]);
  for (let y = Math.min(...ys); y <= Math.max(...ys); y += step)
    for (let x = Math.min(...xs); x <= Math.max(...xs); x += step) {
      if (!inPoly(poly, x, y)) continue;
      n++; if (shapes.some(s => inShape(s, x, y))) hit++;
    }
  return n ? hit / n : 1;
}
function bandPoly(rect, k, D) {
  const { x0, y0, x1, y1 } = rect, h = y1 - y0;
  const xb = x0 + D - k * h;
  if (xb <= x0) {
    const yb = Math.min(y1, y0 + D / k);
    return { poly: [[x0, y0], [x0 + D, y0], [x0, yb]], A: [x0 + D, y0], B: [x0, yb], xb: null };
  }
  return { poly: [[x0, y0], [x0 + D, y0], [xb, y1], [x0, y1]], A: [x0 + D, y0], B: [xb, y1], xb };
}
const regionStats = [];
function fillRegion(o) {
  const { parent, prefix, poly, A, B, color, x0, xb, beforeId } = o;
  const shapes = [];
  const put = (s, suffix, img) => {
    s.img = img || 100001;
    cloneLayer(parent, `${prefix}.${suffix}`, {
      cx: s.cx, cy: s.cy, w: s.w, h: s.h, rot: s.rot || 0,
      color, imageId: s.img, beforeId,
    });
    shapes.push(s);
  };
  const y0 = Math.min(...poly.map(p => p[1])), y1 = Math.max(...poly.map(p => p[1]));
  if (xb != null && xb > x0 + 1)
    put({ cx: (x0 + xb) / 2, cy: (y0 + y1) / 2, w: xb - x0, h: y1 - y0, rot: 0 }, 'rect');
  const dx = B[0] - A[0], dy = B[1] - A[1], L = Math.hypot(dx, dy);
  const M = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2];
  let n = [-dy / L, dx / L];
  const cxg = poly.reduce((s, p) => s + p[0], 0) / poly.length;
  const cyg = poly.reduce((s, p) => s + p[1], 0) / poly.length;
  if ((cxg - M[0]) * n[0] + (cyg - M[1]) * n[1] < 0) n = [-n[0], -n[1]];
  let rot = Math.atan2(-n[0], -n[1]) * 180 / Math.PI;
  if (rot < 0) rot += 360;
  if (rot >= 180) throw Error(prefix + ' triangle rotation out of safe range: ' + rot.toFixed(2));
  let lo = 0, hi = L;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (inPoly(poly, M[0] + n[0] * mid, M[1] + n[1] * mid)) lo = mid; else hi = mid;
  }
  const h = lo * 0.985;
  put({ cx: M[0] + n[0] * h / 2, cy: M[1] + n[1] * h / 2, w: L, h, rot }, 'tri', 100003);
  for (const band of [10, 6, 4, 3, 2, 1]) {
    const holes = [];
    for (let y = y0; y <= y1; y += 2) for (let x = x0; x <= Math.max(...poly.map(p => p[0])); x += 2)
      if (inPoly(poly, x, y) && !shapes.some(s => inShape(s, x, y))) holes.push([x, y]);
    if (!holes.length) break;
    for (let ya = y0; ya < y1; ya += band) {
      const yb = Math.min(ya + band, y1);
      const pts = holes.filter(p => p[1] >= ya && p[1] < yb);
      if (!pts.length) continue;
      const minx = Math.min(...pts.map(p => p[0]));
      let xr = Infinity;
      for (let y = ya; y <= yb; y += 1) xr = Math.min(xr, polyRight(poly, y));
      xr -= 0.4;
      if (xr <= minx + 0.6) continue;
      const corners = [[minx, ya], [xr, ya], [minx, yb], [xr, yb]];
      if (!corners.every(([x, y]) => inside(poly, x, y))) continue;
      put({ cx: (minx + xr) / 2, cy: (ya + yb) / 2, w: xr - minx, h: yb - ya, rot: 0 }, `patch${shapes.length}`);
    }
  }
  {
    const rest = [];
    for (let y = y0; y <= y1; y += 1) for (let x = x0; x <= Math.max(...poly.map(p => p[0])); x += 1)
      if (inPoly(poly, x, y) && !shapes.some(s => inShape(s, x, y))) rest.push([x, y]);
    if (rest.length) {
      const minx = Math.min(...rest.map(p => p[0])) - 0.5;
      const miny = Math.min(...rest.map(p => p[1])) - 0.5;
      const maxy = Math.max(...rest.map(p => p[1])) + 0.5;
      let xr = Math.max(...rest.map(p => p[0])) + 0.5;
      for (let y = miny; y <= maxy; y += 0.5) xr = Math.min(xr, polyRight(poly, y) - 0.1);
      const corners = [[minx, miny], [xr, miny], [minx, maxy], [xr, maxy]];
      if (xr > minx + 0.2 && corners.every(([x, y]) => inside(poly, x, y)))
        put({ cx: (minx + xr) / 2, cy: (miny + maxy) / 2, w: xr - minx, h: maxy - miny, rot: 0 }, `patch${shapes.length}`);
    }
  }
  const bad = shapes.flatMap((s, i) => vertices(s).filter(([x, y]) => !inside(poly, x, y))
    .map(([x, y]) => `#${i}(${x.toFixed(1)},${y.toFixed(1)})`));
  const cov = coverage(poly, shapes);
  const holes = [];
  for (let y = y0; y <= y1; y += 2) for (let x = x0; x <= Math.max(...poly.map(p => p[0])); x += 2)
    if (inPoly(poly, x, y) && !shapes.some(s => inShape(s, x, y))) holes.push([x, y]);
  regionStats.push({ name: prefix, shapes: shapes.length, coverage: +cov.toFixed(4),
    overflow: bad.length > 0, triRot: +rot.toFixed(2), bad: bad.slice(0, 6), holes: holes.length });
  if (bad.length) throw Error(prefix + ' 图元溢出 ' + bad.slice(0, 6).join(' '));
  if (cov < 0.99) throw Error(prefix + ' 覆盖率不足 ' + (cov * 100).toFixed(2) + '%');
  return shapes.length;
}

// ── 目标矩形：严格等于 backrop2 的 324×79.4 ────────────────────────────────
const RECT = { x0: 638, y0: 410.3, x1: 962, y1: 489.7 }; // 中心 800,450
const K = 1;
const S = 324 / 330;
const STEPS = [
  ['s300', 300 * S, '#68262A'],
  ['s250', 250 * S, '#70272E'],
  ['s200', 200 * S, '#68262A'],
  ['s095', 95 * S, '#9D3033'],
];

const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (TPL.length !== 2) throw Error('clue 模板数不符：' + TPL.length);
const summary = [];
let tplNo = 0;
for (const root of TPL) {
  tplNo++;
  const kids = g.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1'), b2 = kids.find(r => r.name === 'backrop2');
  const who = kids.find(r => r.name === 'who');
  const g1 = screenGeom(b1), g2 = screenGeom(b2);
  if (Math.abs(g1[2] - 330) > 0.01 || Math.abs(g2[2] - 324) > 0.01
      || Math.abs(g1[0] - g2[0]) > 0.01) throw Error('backrop 位置与预期不符，停止构建');
  // ① 隐藏 669 缩放过的 30 层（含顶部白线 rule）
  const old = kids.filter(r => /^(art658\.clue\d+\.bg|art658\.clue\d+\.rule|art661\.clue\d+\.)/.test(r.name || ''));
  if (old.length !== 30) throw Error('旧渐变层数不符：' + old.length);
  for (const r of old) hide(r);
  // ② base 铺满整卡（与 backrop2 同色，兜底不漏底色）
  cloneLayer(root, `art670.clue${tplNo}.base`, {
    cx: 800, cy: 450, w: 324, h: 79.4, color: '#611F23', beforeId: who.id,
  });
  // ③ 4 级 45° 斜向阶梯，每级零溢出 + 覆盖率自检
  let layerCount = 1;
  for (const [tag, D, color] of STEPS) {
    const b = bandPoly(RECT, K, D);
    layerCount += fillRegion({ parent: root, prefix: `art670.clue${tplNo}.${tag}`,
      poly: b.poly, A: b.A, B: b.B, color, x0: RECT.x0, xb: b.xb, beforeId: who.id });
  }
  summary.push({ rootId: root.id, hiddenOld: old.length, newLayers: layerCount,
    rect: RECT, backrop1: [g1[2], g1[3]], backrop2: [g2[2], g2[3]] });
}

// ── childList 同步（新增层与全局记录表同序） ────────────────────────────────
const fieldIndex = new Map(); recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set(added.map(r => r.parentId))) {
  const p = byId.get(pid);
  const cl = findChildListTop(p.field.sub);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids); touch(p);
}

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })(g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE, recordsBefore: beforeBytes.size,
    recordsAfter: expected.size, added: added.length, hidden: hidden.length,
    regionStats, summary }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '670 regenerate zero-overflow gradient at backrop2 size, remove white strip',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
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
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});
const minCov = Math.min(...regionStats.map(r => r.coverage));
const audit = {
  version: 1, name: '670 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '669_旧高亮方案.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '670_渐变收敛.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    problem: '669 把 661 针对 330×85.4 精算的 28 层 fillRegion 图元非等比缩放，三角斜边与补漏矩形失配 ⇒ 图元溢出(毛刺)、局部漏暗底色；art658.clueN.rule 白线落在卡片顶边 ⇒ 设计图没有的白带。',
    fix: '隐藏 669 那 30 层(含白线)，用 661 的 fillRegion 针对 324×79.4 重新生成：base 铺满整卡 + 4 级 45° 斜向阶梯，每级「零溢出顶点 + 覆盖率≥99%」自检。',
    rect: RECT, scaleForD: S, steps: STEPS.map(([t, D, c]) => ({ tag: t, D: +D.toFixed(2), color: c })),
    guarantee: '所有拼接图元顶点都在 324×79.4 矩形内；边缘由 base 矩形与各级安全矩形给出，平直无毛刺；base 与 backrop2 同色 #611F23 兜底，整卡不漏底色。',
    kept: 'backrop1 #FF56565E 染色区(选中只染 3px 一圈)、backrop2 #FF611F23、白字、白色底板、内嵌 Lua、26 条文本、v19 背景子树全部保持 669 原样。',
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  regionStats, minCoverage: minCov, allZeroOverflow: regionStats.every(r => !r.overflow),
  summary, hidden, modified, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '670_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length,
  regions: regionStats.length, minCoverage: minCov, allZeroOverflow: audit.allZeroOverflow,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
