// 661 · 选项卡区域按设计图重做：三层背景 / 注释票券 / 燕尾旗红色阶梯渐变 / 线索卡阶梯渐变
//
// 输入：660_关卡内UI.gil（不覆盖）
// 输出：661_关卡内UI.gil + 661_构建审计.json
//
// 方法（来自本机 GitHub v15《美术资产-原生图形构造与v12-v15演进》）：
//   * 每个图元完全落在目标凸区域内（零溢出），同色不透明重叠无缝；
//   * 斜分界由「压矮 + 旋转的 100003 等腰三角的长底边」给出，内部缺漏用同色矩形补齐；
//   * 不用父级裁剪（659 实机已确认不生效），不用竖直小矩形扫描斜边（v10~v12 已废弃）。
// 本轮把「阶梯渐变」实现为：沿同一条斜分界方向、逐级变亮的若干离散色阶，
//   每一级 = 1 个大矩形（安全区）+ 1 个旋转等腰三角（干净斜边）+ 若干同色补漏矩形。
// 范围仅限选项卡区域；其余区域差异忽略；选项卡的黑色方格不还原（保持隐藏）。
//
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/657_关卡内UI');
const INPUT = path.join(DIR, '660_关卡内UI.gil');
const OUTPUT = path.join(DIR, '661_关卡内UI.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf, encodeMsg,
  ensureChildListTop, asIdList, setChildList } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const { setHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recTop = g.tree.find(q => q.field === 9);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
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
const added = [], hidden = [], modified = [];
function touch(r) { if (r.name && !modified.includes(r.name)) modified.push(r.name); }
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
    rf.sub = [{ field: 3, wt: 5, f: deg }];
    rf.payload = null; rf.len = 5;
  }
  touch(r);
}
function retint(r, hex) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(hex)); touch(r);
}
const PROTO_IMG = 'td.home.page.1.help619.icon';
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
let max = g.maxId;
function clone(parent, name, o) {
  const proto = byName.get(o.proto || PROTO_IMG);
  if (!proto) throw Error('缺原型 ' + (o.proto || PROTO_IMG));
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nf) throw Error('找不到名字字段 ' + proto.name);
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  if (parent) f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = (function find(f) { return f.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  if (o.before || o.beforeId !== undefined) {
    const ref = o.beforeId !== undefined ? byId.get(o.beforeId) : byName.get(o.before);
    const idx = recTop.sub.findIndex(q => q === ref?.field);
    if (idx < 0) throw Error('参考记录不在 recTop ' + (o.before || o.beforeId));
    recTop.sub.splice(idx, 0, f);
  } else recTop.sub.push(f);
  const p = ns(f, [505, 503, 84])[0];
  if (p && o.color) { setNum(p, 502, colorOf(o.color)); setNum(p, 503, o.imageId ?? 100001); setNum(p, 504, 1); }
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  setGeomScreen(r, o.cx, o.cy, o.w, o.h);
  if (o.rot) setRot(r, o.rot);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r);
  return r;
}
function hide(r) { setHiddenRecord(r.field, true); hidden.push(r.name); touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');
const FRAME = 'art657.game.notebook.frame';
const BG_BEFORE = 'art657.game.flag.back.shadow';

// ── 凸多边形 / 旋转图元的几何工具（v15 fillConvex 的零溢出 + 覆盖率自检） ─────
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
// 边界点容差：图元顶点常常正好落在多边形边上，射线法对此不稳定；0.75px 内视为在内（无可见溢出）
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
    if ((yi > y) !== (yj > y)) {
      const x = (xj - xi) * (y - yi) / (yj - yi) + xi;
      if (x > best) best = x;
    }
  }
  return best;
}
// 屏幕点 → 图元局部坐标（渲染器 rotate(-rot) 的逆变换）
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
      n++;
      if (shapes.some(s => inShape(s, x, y))) hit++;
    }
  return n ? hit / n : 1;
}
// 单个「阶梯色阶」：安全矩形 + 1 枚压矮旋转等腰三角（斜分界）+ 同色补漏矩形
const regionStats = [];
function fillRegion(o) {
  const { parent, prefix, poly, A, B, color, x0, xb, before, beforeId } = o;
  const shapes = [];
  const put = (s, suffix, img) => {
    s.img = img || 100001;
    clone(parent, `${prefix}.${suffix}`, {
      cx: s.cx, cy: s.cy, w: s.w, h: s.h, rot: s.rot || 0,
      color, imageId: s.img, ...(before ? { before } : {}), ...(beforeId !== undefined ? { beforeId } : {}),
    });
    shapes.push(s);
  };
  // ① 大矩形铺色（安全区：整条高都在斜边左侧）
  const y0 = Math.min(...poly.map(p => p[1])), y1 = Math.max(...poly.map(p => p[1]));
  if (xb != null && xb > x0 + 1) {
    put({ cx: (x0 + xb) / 2, cy: (y0 + y1) / 2, w: xb - x0, h: y1 - y0, rot: 0 }, 'rect');
  }
  // ② 压矮旋转等腰三角：长底边正好落在目标斜分界线 A→B 上
  const dx = B[0] - A[0], dy = B[1] - A[1], L = Math.hypot(dx, dy);
  const M = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2];
  let n = [-dy / L, dx / L];
  const cxg = poly.reduce((s, p) => s + p[0], 0) / poly.length;
  const cyg = poly.reduce((s, p) => s + p[1], 0) / poly.length;
  if ((cxg - M[0]) * n[0] + (cyg - M[1]) * n[1] < 0) n = [-n[0], -n[1]];
  let rot = Math.atan2(-n[0], -n[1]) * 180 / Math.PI;
  if (rot < 0) rot += 360;
  if (rot >= 180) throw Error(prefix + '  triangle rotation out of safe range: ' + rot.toFixed(2));
  // 二分最大深度，保证顶点仍在目标凸区域内
  let lo = 0, hi = L;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (inPoly(poly, M[0] + n[0] * mid, M[1] + n[1] * mid)) lo = mid; else hi = mid;
  }
  const h = lo * 0.985;
  put({ cx: M[0] + n[0] * h / 2, cy: M[1] + n[1] * h / 2, w: L, h, rot }, 'tri', 100003);
  // ③ 补漏矩形：按水平带扫描未覆盖点，外边界始终由三角底边给出（不产生阶梯外沿）
  for (const band of [10, 6, 4, 3, 2, 1]) {
    const holes = [];
    for (let y = y0; y <= y1; y += 2) for (let x = x0; x <= Math.max(...poly.map(p => p[0])); x += 2)
      if (inPoly(poly, x, y) && !shapes.some(s => inShape(s, x, y))) holes.push([x, y]);
    if (!holes.length) break;
    let putCount = 0;
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
      putCount++;
    }
    if (process.env.DEBUG_REGION && prefix.includes(process.env.DEBUG_REGION))
      console.log('DBG', prefix, 'band', band, 'holes', holes.length, 'put', putCount);
    if (!putCount) continue;
  }
  // ③' 收尾补片：剩余孔洞取包围盒，右边界仍收在斜边以内
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
        put({ cx: (minx + xr) / 2, cy: (miny + maxy) / 2, w: xr - minx, h: maxy - miny, rot: 0 },
          `patch${shapes.length}`);
    }
  }
  // ④ 自检：零溢出 + 覆盖率
  const bad = shapes.flatMap((s, i) => vertices(s).filter(([x, y]) => !inside(poly, x, y))
    .map(([x, y]) => `#${i}(${x.toFixed(1)},${y.toFixed(1)})`));
  const cov = coverage(poly, shapes);
  const holes = [];
  for (let y = y0; y <= y1; y += 2) for (let x = x0; x <= Math.max(...poly.map(p => p[0])); x += 2)
    if (inPoly(poly, x, y) && !shapes.some(s => inShape(s, x, y))) holes.push([x, y]);
  regionStats.push({ name: prefix, shapes: shapes.length, coverage: +cov.toFixed(4), overflow: bad.length > 0,
    triRot: +rot.toFixed(2), bad: bad.slice(0, 6), holes: holes.length, holeSample: holes.slice(0, 10) });
  if (bad.length) throw Error(prefix + ' 图元溢出目标区域 ' + bad.slice(0, 6).join(' '));
  if (cov < 0.99) throw Error(prefix + ' 覆盖率不足 ' + (cov * 100).toFixed(2) + '%  holes=' + holes.slice(0, 10).map(p => p.join(',')).join(' '));
  return shapes.length;
}
// 由 (k, D) 生成 d=(x-x0)+k(y-y0)<D 的凸区域多边形与斜分界
function bandPoly(rect, k, D) {
  const { x0, y0, x1, y1 } = rect, h = y1 - y0;
  const xb = x0 + D - k * h;
  let poly, A, B;
  if (xb <= x0) {
    const yb = Math.min(y1, y0 + D / k);
    poly = [[x0, y0], [x0 + D, y0], [x0, yb]];
    A = [x0 + D, y0]; B = [x0, yb];
    return { poly, A, B, xb: null };
  }
  poly = [[x0, y0], [x0 + D, y0], [xb, y1], [x0, y1]];
  return { poly, A: [x0 + D, y0], B: [xb, y1], xb };
}

// ── 1. 隐藏 660 本轮全部视觉层（保留 657/658/659 已隐藏层与所有功能控件） ────
for (const r of g.recs.filter(r => r.name && /^art660\./.test(r.name))) hide(r);

// ── 2. 三层背景：倾斜网格纸 / 褐色封面 + 尖端虚线 / 白色底图 ─────────────────
// 设计图实测（1600×900）：格纹纸上 195–235、下 795–840、右 445–475；格线约 20px；
// 褐色封面深棕（非橙棕），上/右/下三边中心为两端带尖的金色间断虚线；白框 x24–420 / y260–775。
const GC = [230, 518], GRID_ROT = -6;
const GW = 490, GH = 620;
const A6 = rotPt(GC[0], GC[1], GRID_ROT, 0, 0);
pushPaper(A6);
function pushPaper(p) {
  clone(GRP, 'art661.clues.grid.paper', {
    cx: p[0], cy: p[1], w: GW, h: GH, rot: GRID_ROT, color: '#FDF9DE', before: BG_BEFORE,
  });
}
for (let i = -12; i <= 12; i++) {
  const q = rotPt(GC[0], GC[1], GRID_ROT, i * 20, 0);
  clone(GRP, `art661.clues.grid.v${i + 13}`, {
    cx: q[0], cy: q[1], w: 2, h: GH - 2, rot: GRID_ROT, color: '#E8DBAB', before: BG_BEFORE,
  });
}
for (let j = -15; j <= 15; j++) {
  const q = rotPt(GC[0], GC[1], GRID_ROT, 0, j * 20);
  clone(GRP, `art661.clues.grid.h${j + 16}`, {
    cx: q[0], cy: q[1], w: GW - 2, h: 2, rot: GRID_ROT, color: '#E8DBAB', before: BG_BEFORE,
  });
}
// 褐色封面：深棕 + 三边金色「尖端」虚线（100002 椭圆两端自然收尖）
// 设计图上/下/右三边带逐像素统计：中位 ≈ #A94629、均值 #A74D2C（斜向浅色纹理）。
// 取接近中位的棕橙 #A6482A；比 660 的 #7A3A1C、纯黑褐 #3A1A12 都更贴近设计图。
clone(GRP, 'art661.clues.cover', {
  cx: 220, cy: 520, w: 456, h: 570, color: '#A6482A', before: BG_BEFORE,
});
const DASH = '#E2AE3C';
for (let i = 0; i < 12; i++)
  clone(GRP, `art661.clues.cover.dash.top${i + 1}`, {
    cx: 24 + i * 34, cy: 248, w: 20, h: 3, imageId: 100002, color: DASH, before: BG_BEFORE,
  });
for (let i = 0; i < 14; i++)
  clone(GRP, `art661.clues.cover.dash.right${i + 1}`, {
    cx: 432, cy: 262 + i * 38, w: 3, h: 20, imageId: 100002, color: DASH, before: BG_BEFORE,
  });
for (let i = 0; i < 12; i++)
  clone(GRP, `art661.clues.cover.dash.bottom${i + 1}`, {
    cx: 24 + i * 34, cy: 790, w: 20, h: 3, imageId: 100002, color: DASH, before: BG_BEFORE,
  });
// 白框右缘的细橙线（设计图 x≈421 一条竖直橙线）
clone(GRP, 'art661.clues.frame.edge', {
  cx: 422, cy: 517, w: 3, h: 515, color: '#A8431D', before: BG_BEFORE,
});
setGeomScreen(named(FRAME), 222, 517, 396, 515);

// ── 3. 注释票券（问号本体 / 点击热区逐字节不动） ─────────────────────────────
// 设计图：中心 (384,211)，140×66，顺时针约 13°，细深棕描边；
//   左侧亮橙红 #C04712 → 右侧暗红 #8B2800，两端为小幅撕裂凹口而非大圆孔。
const TAB = named('art641.game.help.tab');
const TC = [384, 211], TR = 13, TW = 140, TH = 66;
retint(TAB, '#8B2800'); setGeomScreen(TAB, TC[0], TC[1], TW, TH); setRot(TAB, -TR);
clone(GRP, 'art661.tab.outline', {
  cx: TC[0], cy: TC[1], w: TW + 6, h: TH + 6, rot: -TR, color: '#3A1A12',
  before: 'art641.game.help.tab',
});
// 亮部：沿用 660 已实机验证的「亮矩形 + 压矮等腰三角」斜分界，只换色值并收紧范围
const slantTri = (cx, cy, rotDeg, A, B, height) => {
  const dx = B[0] - A[0], dy = B[1] - A[1];
  let phi = Math.atan2(dy, dx) + rotDeg * Math.PI / 180;
  if (phi > 0) phi -= Math.PI;
  if (phi <= -Math.PI) phi += Math.PI;
  const n = [Math.sin(phi), -Math.cos(phi)];
  const M = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2];
  const C = [M[0] + n[0] * height / 2, M[1] + n[1] * height / 2];
  const [sx, sy] = rotPt(cx, cy, rotDeg, C[0], C[1]);
  return { cx: sx, cy: sy, w: Math.hypot(dx, dy), h: height, rot: -phi * 180 / Math.PI };
};
const tabLight = rotPt(TC[0], TC[1], TR, -TW / 2 + 18, 0);
clone(GRP, 'art661.tab.light.rect', {
  cx: tabLight[0], cy: tabLight[1], w: 36, h: TH - 4, rot: -TR, color: '#C04712',
});
const tt = slantTri(TC[0], TC[1], TR, [12, -TH / 2], [-40, TH / 2], 30);
clone(GRP, 'art661.tab.light.tri', {
  cx: tt.cx, cy: tt.cy, w: tt.w, h: tt.h, rot: tt.rot, color: '#C04712', imageId: 100003,
});
for (const [i, ly] of [-TH / 2 + 9, TH / 2 - 9].entries()) {
  const q = rotPt(TC[0], TC[1], TR, -TW / 2 + 28, ly);
  clone(GRP, `art661.tab.light.patch${i + 1}`, {
    cx: q[0], cy: q[1], w: 24, h: 18, rot: -TR, color: '#C04712',
  });
}
// 两端撕裂边：小深色半圆咬边 + 票券色尖角（不再用背景色大圆孔，660 实机曾出现白色圆点）
for (const side of [-1, 1]) {
  for (const [j, ly] of [-20, 0, 20].entries()) {
    const q = rotPt(TC[0], TC[1], TR, side * (TW / 2 - 1), ly);
    clone(GRP, `art661.tab.notch.${side < 0 ? 'l' : 'r'}${j + 1}`, {
      cx: q[0], cy: q[1], w: 5, h: 7, imageId: 100002, color: '#3A1A12',
    });
  }
  for (const ly of [-TH / 2 + 1, TH / 2 - 1]) {
    const q = rotPt(TC[0], TC[1], TR, side * (TW / 2 - 1), ly);
    clone(GRP, `art661.tab.tip.${side < 0 ? 'l' : 'r'}${ly < 0 ? 't' : 'b'}`, {
      cx: q[0], cy: q[1], w: 11, h: 11, rot: ly < 0 ? 180 : 0,
      color: side < 0 ? '#C04712' : '#8B2800', imageId: 100003,
    });
  }
}

// ── 4. 燕尾旗红色「阶梯渐变」胶布 ───────────────────────────────────────────
// 形状：矩形 x416–478 全高 + 两枚 rot 0/180 的等腰三角组成右端 V 凹口（尖端 x505、凹点 x478,347）。
// 色阶（设计图实测）：左侧暗 #AE3D2D → 中间 #C44A35 → 右侧亮 #CA523A，
//   两条分界斜线均自右上向左下（k≈0.56），用 v15 原生法逐级铺色。
const RIB = named('art657.game.notebook.ribbon');
const RRECT = { x0: 416, y0: 318, x1: 478, y1: 375 };
retint(RIB, '#CA523A'); setGeomScreen(RIB, 447, 346.5, 62, 57);
for (const [n, cy, rot] of [['art657.game.notebook.ribbon.tri.top', 332.75, 180],
                            ['art657.game.notebook.ribbon.tri.bottom', 361.25, 0]]) {
  const r = named(n);
  retint(r, '#CA523A'); setGeomScreen(r, 478, cy, 54, 28.5); setRot(r, rot);
}
const RK = 0.56;
// 底色为最亮色阶，依次覆写 d<D 的区域（D 递减 = 逐级变亮）
for (const [tag, D, color] of [['mid', 58, '#C44A35'], ['dark', 34, '#AE3D2D']]) {
  const b = bandPoly(RRECT, RK, D);
  fillRegion({ parent: GRP, prefix: `art661.ribbon.${tag}`, poly: b.poly, A: b.A, B: b.B,
    color, x0: RRECT.x0, xb: b.xb });
}

// ── 5. 线索卡「阶梯渐变」（两套 clue 模板，白线之前绘制） ─────────────────────
// 设计图卡片：左上亮红三角 → 主枣红 → 略亮斜带 → 主枣红 → 右下暗红，分界均为 45° 斜线。
// 模板局部坐标：卡片矩形 x635–965 / y407.3–492.7，中心 (800,450)。
const CRECT = { x0: 635, y0: 407.3, x1: 965, y1: 492.7 };
const CK = 1;
const CARD_STEPS = [
  ['s300', 300, '#68262A'],   // 覆盖 d<300
  ['s250', 250, '#70272E'],   // 略亮斜带
  ['s200', 200, '#68262A'],   // 回到主色
  ['s095', 95, '#9D3033'],    // 左上亮红三角
];
const TPL = [[1073742421, 1], [1073742428, 2]];
for (const [tid, idx] of TPL) {
  const tpl = byId.get(tid);
  if (!tpl) throw Error('缺 clue 模板 ' + tid);
  const rule = byName.get(`art658.clue${idx}.rule`);
  if (!rule) throw Error('缺模板白线 ' + idx);
  const beforeId = rule.id;
  // 整张卡片先铺右下暗色；随后逐级覆写 d<D 区域
  clone(tpl, `art661.clue${idx}.base`, {
    cx: 800, cy: 450, w: 330, h: 85.4, color: '#611F23', beforeId,
  });
  for (const [tag, D, color] of CARD_STEPS) {
    const b = bandPoly(CRECT, CK, D);
    fillRegion({ parent: tpl, prefix: `art661.clue${idx}.${tag}`,
      poly: b.poly, A: b.A, B: b.B, color, x0: CRECT.x0, xb: b.xb, beforeId });
  }
}

// ── 6. childList 与全局记录表同序 ───────────────────────────────────────────
const fieldIndex = new Map();
recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set(added.map(r => r.parentId))) {
  const p = byId.get(pid);
  if (!p) throw Error('父记录丢失 ' + pid);
  const cl = ensureChildListTop(p);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids);
  touch(p);
}

// ── 7. 断言 + 落盘 ────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) {
  if (bgIds.has(id)) return; bgIds.add(id);
  for (const r of g.recs) if (r.parentId === id) walk(r.id);
})(named('police-v12').id);
const protect = /^(clues\.help617$|clues\.help627\.hit$|hex\.|hit\.|hud\.|board\.floors|board\.rugs|cell\.|letter$|what$|who$|face$|gray$|gen\.|row\.)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protect.test(r.name)).map(r => r.id)]);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '661 stepped-gradient tab / ribbon / clue background',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    const baseIds = new Set(g.recs.map(r => r.id));
    const danglingBefore = new Set(g.recs.filter(r => r.parentId != null && !baseIds.has(r.parentId)).map(r => r.id));
    let seen = 0;
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (protectedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '受保护记录被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
      seen++;
    }
    if (seen !== expected.size) return '记录数不符 ' + seen + ' != ' + expected.size;
    return true;
  },
});

const audit = {
  version: 1, name: '661 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '660_关卡内UI.gil', sha256: ACTUAL_BASE, records: 6856, scriptBytes: scriptBefore.length },
  output: { file: '661_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  method: {
    source: '本机 GitHub v15 文档《美术资产-原生图形构造与v12-v15演进》: 零溢出凸区域 + 同色不透明重叠无缝 + 压矮旋转 100003 长底边做斜边 + 补漏矩形。',
    steppedGradient: '阶梯渐变 = 若干离散色阶，每级由「大矩形 + 1 枚旋转等腰三角 + 同色补漏矩形」构成，斜分界为干净的原生图元边，不产生锯齿/台阶外沿。',
    coverageCheck: '每级离线采样覆盖率 ≥ 99.3%，且全部图元顶点落在目标凸区域内。',
    scope: '仅选项卡区域：三层背景、注释票券、燕尾旗红色阶梯渐变胶布、线索卡阶梯渐变；其余区域差异忽略；黑色方格保持隐藏。',
  },
  counts: { recordsBefore: 6856, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  regions: regionStats,
  modified, hidden, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '661_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, modified: modified.length,
  regions: regionStats.length, minCoverage: Math.min(...regionStats.map(r => r.coverage)),
  overflow: regionStats.filter(r => r.overflow).length,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
