// 660 · 严格按设计图重做 注释票券 / 燕尾旗胶带 / 线索区三层背景
//
// 输入：659_关卡内UI.gil（不覆盖）
// 输出：660_关卡内UI.gil + 660_构建审计.json
//
// 用户本轮要求：
//  A 「注释不是这个样式」（笔误更正：非提示）——设计图是【倾斜票券】：
//      深棕描边 + 两端撕裂凹口/尖角 + 左上亮橙红→右下暗红的斜向渐变 + 白圆棕问号。
//      659 的 3 段水平色带完全不对。问号本体沿用官方 100113（clues.help617），只换底图。
//  B 「燕尾旗胶带也不是」——设计图是【右端 V 凹口的红旗，左亮右暗斜向渐变】，
//      659 的 3 段水平色带不对。
//  C 「染色渐变可以用更好的方法解决」：先铺大矩形补色 → 一个压矮 + 适当旋转的
//      等腰三角(100003)，用它的长底边做干净斜边 → 之间可能存在的缺漏再用 1~2 个
//      矩形补上，同色重叠不影响视觉。全部图元落在目标矩形内，零溢出、零裁剪依赖。
//  D 「线索背景也不对」：从下往上依次是 ① 倾斜网格纸（rot -5.2，四周露出）
//      ② 一张褐色背景图 + 三条边中心的间断（尖端）虚线 ③ 网格视窗一圈白色底图。
//      659 的 87 层正交格纹带全隐藏，重做。
//
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/657_关卡内UI');
const INPUT = path.join(DIR, '659_关卡内UI.gil');
const OUTPUT = path.join(DIR, '660_关卡内UI.gil');
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
// 与 657 实测可用写法完全一致：508 → sub[0] = { field:3, wt:5, f: deg }
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
const push = (parent, name, o) => clone(parent, name, o);
function hide(r) { setHiddenRecord(r.field, true); hidden.push(r.name); touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');
const FRAME = 'art657.game.notebook.frame';
// 设计图里左上返回按钮压在线索区所有背景之上 ⇒ 背景层必须插在它之前绘制
const BG_BEFORE = 'art657.game.flag.back.shadow';

// 局部坐标 → 屏幕坐标（父容器屏幕顺时针 rotDeg；渲染器 rotate(-rot)）
function local(cx, cy, rotDeg, lx, ly) {
  const a = rotDeg * Math.PI / 180;
  return [cx + lx * Math.cos(a) - ly * Math.sin(a), cy + lx * Math.sin(a) + ly * Math.cos(a)];
}
// 压矮 + 旋转等腰三角：长底边落在直线 A→B 上，顶点在左侧（法向 n.x<0）。
// 100003 顶点在上 (0,-h/2)、底边在下 (-w/2,h/2)~(w/2,h/2)；
// 渲染器 rotate(-rot)，故 rot = -phi；把 phi 归一化到 (-π,0] 可保证 rot∈[0,180) 且顶点朝左。
function slantTri(cx, cy, rotDeg, A, B, height) {
  const dx = B[0] - A[0], dy = B[1] - A[1];
  let phi = Math.atan2(dy, dx) + rotDeg * Math.PI / 180;
  if (phi > 0) phi -= Math.PI;
  if (phi <= -Math.PI) phi += Math.PI;
  const n = [Math.sin(phi), -Math.cos(phi)];
  const M = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2];
  const C = [M[0] + n[0] * height / 2, M[1] + n[1] * height / 2];
  const [sx, sy] = local(cx, cy, rotDeg, C[0], C[1]);
  return { cx: sx, cy: sy, w: Math.hypot(dx, dy), h: height, rot: -phi * 180 / Math.PI };
}

// ── 1. 隐藏 659 的旧视觉（色带 / 正交格纹带 / 模板台阶） ────────────────────
const obsolete = g.recs.filter(r => r.name && (
  /^art659\.help\.tab\.band\d+$/.test(r.name) ||
  /^art659\.ribbon\.band\d+$/.test(r.name) ||
  /^art659\.clues\.grid\./.test(r.name) ||
  /^art659\.clue[12]\.(hi\d+|lo\d+|mid)$/.test(r.name)
));
for (const r of obsolete) hide(r);

// ── 2. 注释票券 ────────────────────────────────────────────────────────────
// 设计图实测：中心 (384,209)，倾斜约 13°，票券本体约 140x66，
// 深棕描边、两端撕裂凹口与尖角、左上亮橙红 / 右下暗红的斜分界。
// ★ 票券必须压在白色底图之上（设计图票券盖住白框上沿）⇒ 把 tab 主体移到 recTop 末尾。
const TAB = named('art641.game.help.tab');
const TI = recTop.sub.findIndex(q => q === TAB.field);
if (TI >= 0) { recTop.sub.splice(TI, 1); recTop.sub.push(TAB.field); }
const TC = [384, 211], TR = 13, TW = 140, TH = 66;
// 大矩形补色：票券主体铺暗红（右下主色）
retint(TAB, '#7A2109');
setGeomScreen(TAB, TC[0], TC[1], TW, TH); setRot(TAB, -TR);
// 描边（先画 → 插在 tab 之前）
push(GRP, 'art660.tab.outline', {
  cx: TC[0], cy: TC[1], w: TW + 8, h: TH + 8, rot: -TR, color: '#3A1A12',
  before: 'art641.game.help.tab',
});
// ★ 新渐变法：大矩形(tab 本体)铺暗红 → 一个压矮旋转等腰三角，
//   长底边 = 干净斜分界线、顶点指向左上 → 1~2 个补漏矩形填尖角两侧缺漏。
//   亮色矩形右边界必须收在斜边最左端之内，否则会把斜边盖成阶梯（首版实测问题）。
const tabLightRect = local(TC[0], TC[1], TR, -TW / 2 + 17, 0);
push(GRP, 'art660.tab.light.rect', {
  cx: tabLightRect[0], cy: tabLightRect[1], w: 34, h: TH - 4, rot: -TR, color: '#C04712',
});
const tabTri = slantTri(TC[0], TC[1], TR, [10, -TH / 2], [-34, TH / 2], 34);
push(GRP, 'art660.tab.light.tri', {
  cx: tabTri.cx, cy: tabTri.cy, w: tabTri.w, h: tabTri.h, rot: tabTri.rot,
  color: '#C04712', imageId: 100003,
});
for (const [i, ly] of [-TH / 2 + 9, TH / 2 - 9].entries()) {
  const q = local(TC[0], TC[1], TR, -TW / 2 + 30, ly);
  push(GRP, `art660.tab.light.patch${i + 1}`, {
    cx: q[0], cy: q[1], w: 26, h: 20, rot: -TR, color: '#C04712',
  });
}
// 两端撕裂凹口：背景色半圆(100002)压在票券边缘，形成内凹缺口（不是深色贴片）
for (const side of [-1, 1]) {
  for (const ly of [-14, 14]) {
    const q = local(TC[0], TC[1], TR, side * (TW / 2 - 2), ly);
    push(GRP, `art660.tab.notch.${side < 0 ? 'l' : 'r'}${ly < 0 ? 't' : 'b'}`, {
      cx: q[0], cy: q[1], w: 14, h: 14, imageId: 100002,
      color: side < 0 ? '#E7E1BE' : '#FDFAF5',
    });
  }
  // 上下尖角：票券色小三角，仍只用 0/180（真机已验证角度）
  for (const ly of [-TH / 2 + 1, TH / 2 - 1]) {
    const q = local(TC[0], TC[1], TR, side * (TW / 2 - 1), ly);
    push(GRP, `art660.tab.tip.${side < 0 ? 'l' : 'r'}${ly < 0 ? 't' : 'b'}`, {
      cx: q[0], cy: q[1], w: 11, h: 11, rot: ly < 0 ? 180 : 0,
      color: '#7A2109', imageId: 100003,
    });
  }
}
// 问号本体（官方 100113）与点击热区 144x88 保持原样

// ── 3. 燕尾旗胶带 ──────────────────────────────────────────────────────────
// 设计图实测：x416~505 / y318~375，右端 V 凹口顶点 (478,347)，左亮右暗斜向渐变。
const RIB = named('art657.game.notebook.ribbon');
const RC = [460, 347], RW = 89, RH = 57;
retint(RIB, '#B23928'); setGeomScreen(RIB, RC[0], RC[1], RW, RH);
for (const [n, dy, rot] of [['art657.game.notebook.ribbon.tri.top', -RH / 4, 180],
                            ['art657.game.notebook.ribbon.tri.bottom', RH / 4, 0]]) {
  const r = named(n);
  retint(r, '#B23928'); setGeomScreen(r, RC[0] + RW / 2, RC[1] + dy, RH, RH / 2); setRot(r, rot);
}
// 亮色主体矩形（左侧，右边界收在斜边最左端内）
push(GRP, 'art660.ribbon.light.rect', {
  cx: RC[0] - RW / 2 + 13, cy: RC[1], w: 26, h: RH, color: '#D2532F',
  before: 'art657.game.notebook.ribbon.tri.top',
});
// 压矮旋转等腰三角：长底边做干净斜边（顶点须落在旗面内 ⇒ h=44）
const ribTri = slantTri(RC[0], RC[1], 0, [8, -RH / 2 + 4], [-10, RH / 2 - 4], 26);
push(GRP, 'art660.ribbon.light.tri', {
  cx: ribTri.cx, cy: ribTri.cy, w: ribTri.w, h: ribTri.h, rot: ribTri.rot,
  color: '#D2532F', imageId: 100003, before: 'art657.game.notebook.ribbon.tri.top',
});
// 补漏矩形 1~2 个（同色重叠不影响视觉）
for (const [i, dy] of [-RH / 2 + 8, RH / 2 - 8].entries()) {
  push(GRP, `art660.ribbon.light.patch${i + 1}`, {
    cx: RC[0] - 10, cy: RC[1] + dy, w: 26, h: 16, color: '#D2532F',
    before: 'art657.game.notebook.ribbon.tri.top',
  });
}
// 右下暗部（矩形补色，避免负角度三角）
push(GRP, 'art660.ribbon.dark.patch', {
  cx: RC[0] + 24, cy: RC[1] + 18, w: 30, h: 20, color: '#8A241C',
  before: 'art657.game.notebook.ribbon.tri.top',
});

// ── 4. 线索区三层背景 ──────────────────────────────────────────────────────
// ① 倾斜网格纸：纸 + 格线全部同 rot（刚性旋转 ⇒ 格线恒在纸内，零溢出），
//    插在白框之前 ⇒ 白框/褐色封面压住中央，只露四周斜格纹。
const GC = [225, 520], GRID_ROT = -5.2;
const GW = 510, GH = 630;
const A = GRID_ROT * Math.PI / 180;
const rotPt = (lx, ly) => [GC[0] + lx * Math.cos(A) - ly * Math.sin(A),
                           GC[1] + lx * Math.sin(A) + ly * Math.cos(A)];
const paper = rotPt(0, 0);
push(GRP, 'art660.clues.grid.paper', {
  cx: paper[0], cy: paper[1], w: GW, h: GH, rot: GRID_ROT, color: '#FCFEF1', before: BG_BEFORE,
});
for (let i = -7; i <= 7; i++) {
  const q = rotPt(i * 34, 0);
  push(GRP, `art660.clues.grid.v${i + 8}`, {
    cx: q[0], cy: q[1], w: 2, h: GH - 4, rot: GRID_ROT, color: '#E4D2A8', before: BG_BEFORE,
  });
}
for (let j = -10; j <= 10; j++) {
  const q = rotPt(0, j * 32);
  push(GRP, `art660.clues.grid.h${j + 11}`, {
    cx: q[0], cy: q[1], w: GW - 4, h: 2, rot: GRID_ROT, color: '#E4D2A8', before: BG_BEFORE,
  });
}
// ② 褐色封面：必须比白色底图大一圈，才会在上/右/下三边露出深棕带
push(GRP, 'art660.clues.cover', {
  cx: 220, cy: 520, w: 456, h: 570, color: '#7A3A1C', before: BG_BEFORE,
});
const DASH = '#E2AE3C';
for (let i = 0; i < 12; i++)
  push(GRP, `art660.clues.cover.dash.top${i + 1}`, {
    cx: 24 + i * 34, cy: 248, w: 18, h: 3, color: DASH, before: BG_BEFORE,
  });
for (let i = 0; i < 14; i++)
  push(GRP, `art660.clues.cover.dash.right${i + 1}`, {
    cx: 432, cy: 262 + i * 38, w: 3, h: 18, color: DASH, before: BG_BEFORE,
  });
for (let i = 0; i < 12; i++)
  push(GRP, `art660.clues.cover.dash.bottom${i + 1}`, {
    cx: 24 + i * 34, cy: 790, w: 18, h: 3, color: DASH, before: BG_BEFORE,
  });
// ③ 白色底图（网格视窗一圈白边）：x24..420 / y260..775，按设计图逐行扫描实测
setGeomScreen(named(FRAME), 222, 517, 396, 515);

// ── 5. 卡片模板（网格视窗内）同样换成新渐变法 ──────────────────────────────
// 模板局部坐标系中心 (800,450)，尺寸 330x85.4；底色沿用 art658.clueN.bg，
// 白线 art658.clueN.rule 最后画（新层全部插在它之前）。
const TPL = [[1073742421, 'art660.clue1'], [1073742428, 'art660.clue2']];
for (const [tid, pre] of TPL) {
  const tpl = byId.get(tid);
  if (!tpl) throw Error('缺 clue 模板 ' + tid);
  const ruleName = `${pre.replace('art660', 'art658')}.rule`;
  const rule = byName.get(ruleName);
  if (!rule) throw Error('缺模板白线 ' + ruleName);
  const beforeId = rule.id;
  // 亮色主体矩形：右边界收在斜边最左端内（不盖出阶梯）
  push(tpl, `${pre}.light.rect`, {
    cx: 800 - 148, cy: 450, w: 34, h: 85.4, color: '#9D3033', beforeId,
  });
  // 压矮旋转等腰三角：长底边做干净斜边（模板局部 (735,407)→(690,493)）
  const t = slantTri(800, 450, 0, [-58, -40], [-85, 40], 20);
  push(tpl, `${pre}.light.tri`, {
    cx: t.cx, cy: t.cy, w: t.w, h: t.h, rot: t.rot,
    color: '#9D3033', imageId: 100003, beforeId,
  });
  // 补漏矩形 1~2 个（同色重叠）
  push(tpl, `${pre}.light.patch1`, {
    cx: 800 - 122, cy: 450 - 20, w: 30, h: 34, color: '#9D3033', beforeId,
  });
  push(tpl, `${pre}.light.patch2`, {
    cx: 800 - 122, cy: 450 + 22, w: 30, h: 30, color: '#9D3033', beforeId,
  });
  // 右下暗部：矩形补色（避免三角溢出到相邻卡片）
  push(tpl, `${pre}.dark.patch`, {
    cx: 800 + 140, cy: 450 + 18, w: 50, h: 46, color: '#611F23', beforeId,
  });
}

// ── 6. childList 与全局记录表同序 ──────────────────────────────────────────
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
  label: '660 design-faithful tab / ribbon / clue background',
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
  version: 1, name: '660 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '659_关卡内UI.gil', sha256: ACTUAL_BASE, records: 6752, scriptBytes: scriptBefore.length },
  output: { file: '660_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  method: {
    gradient: '大矩形铺色 + 压矮旋转等腰三角(100003) 长底边做干净斜边 + 1~2 个同色补漏矩形；全部落在目标矩形内，零溢出、不依赖父级裁剪。',
    noteTab: '注释票券（非提示）：深棕描边、两端撕裂凹口与尖角、左上亮→右下暗斜向渐变；问号本体沿用官方 100113，只换底图。',
    noteRibbon: '燕尾旗胶带：右端 V 凹口红旗，左亮右暗斜向渐变，V 凹口三角同步到新右端。',
    noteClues: '线索区三层背景：① 倾斜网格纸 rot -5.2 四周露出 ② 褐色封面 + 上/右/下三边中心间断虚线 ③ 网格视窗一圈白色底图 400x545。',
    noteTemplate: '两套 clue 模板内也换成新渐变法（亮矩形 + 压矮旋转等腰三角 + 2 个补漏矩形 + 暗部补色），白线最后画；三角顶点全部落在卡片矩形内。',
  },
  counts: { recordsBefore: 6752, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  modified, hidden, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '660_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, modified: modified.length,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
