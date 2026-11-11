// 664 · 基于 663_关卡内UI.gil 的三项实机反馈整改（增量构建，不覆盖任何旧档）
//
// 输入：663_关卡内UI.gil
// 输出：664_关卡内UI.gil + 664_构建审计.json
//
// ① 彻底删除「无旋转网格纸」art657.game.board.tape.* 共 53 条记录
//    （从 recTop + 父 childList 一起移除，不是隐藏；全仓核查无其它运行时引用），
//    并把「白底板 + 倾斜斜网格纸」统一沿 y 平移 +10.5，使上下超出棋盘对称：
//      棋盘深紫内框实测 y=107..732；
//      boardframe.paper 43..775（上64/下43）→ 53.5..785.5（上53.5/下53.5）
//      art656.home.grid.paper 34..784（上73/下52）→ 44.5..794.5（上62.5/下62.5）
//    平移不改大小/颜色/角度，沿用 663 对第二张网格纸的保留约束。
//
// ② 注释票券「严格按设计图」：
//    设计图 6236×3508 原 PNG 逐点采样 → 3 级 45° 斜向阶梯
//      #8C2800(28.0%) 底/右半 → #AF3200(26.2%) 中阶 → #CB4C19(10.1%) 左上亮阶
//    分界（票券局部坐标）lx+ly<18 / lx+ly<−42；调用仓库
//      qianxing-murdoku-tool/art/tools/fit-primitive-shape.mjs
//    拟合成 23 枚 100003 等腰三角（coverage=100%、overflowVertices=0），
//    rot 归一化到 [0,360) 写入。边缘改为「深棕凹口 + 票券色尖齿」的撕纸边。
//
// ③ 拍立得火漆「严格按设计图」：
//    设计图水平剖面实测：外圈亮红 #B40806 / 最亮 #D70601、主体 #AA0400；
//    补 12 枚亮红环带椭圆 + 2 枚左右强亮 + 2 层中心压印，
//    替换 663 的两条竖长 glow 与单块 inner。
//
// v19 背景资产仍为独立内容：police-v19 子树零改动；内嵌 Lua 零改动。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/657_关卡内UI');
const INPUT = path.join(DIR, '663_关卡内UI.gil');
const OUTPUT = path.join(DIR, '664_关卡内UI.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const DRY = process.argv.includes('--dry');

const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf, encodeMsg,
  ensureChildListTop, asIdList, setChildList } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const { setHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const FIT = JSON.parse(fs.readFileSync(path.join(DIR, '664_色阶图元.json'), 'utf8'));

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
const added = [], hidden = [], modified = [], removed = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
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
    rf.sub = [{ field: 3, wt: 5, f: deg }];
    rf.payload = null; rf.len = 5;
  }
  touch(r);
}
function retint(r, hex, imageId = null) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(hex));
  if (imageId !== null) { setNum(p, 503, imageId); setNum(p, 504, 1); }
  touch(r);
}
const PROTO_IMG = 'td.home.page.1.help619.icon';
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
let max = BigInt(g.maxId);
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
  const cl = (function find(ff) { return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true)); })(f);
  if (cl) setChildList(cl, []);
  let idx = -1;
  if (o.before) idx = recTop.sub.findIndex(q => q === byName.get(o.before)?.field);
  else if (o.after) idx = recTop.sub.findIndex(q => q === byName.get(o.after)?.field) + 1;
  if (idx < 0) idx = recTop.sub.length;
  recTop.sub.splice(idx, 0, f);
  const p = ns(f, [505, 503, 84])[0];
  if (p && o.color) { setNum(p, 502, colorOf(o.color)); setNum(p, 503, o.imageId ?? 100001); setNum(p, 504, 1); }
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  setGeomScreen(r, o.cx, o.cy, o.w, o.h);
  if (o.rot !== undefined) setRot(r, o.rot);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r); touch(r);
  return r;
}
function hide(r) { setHiddenRecord(r.field, true); hidden.push(r.name); touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');
const T = FIT.ticket;
const rotPt = (lx, ly) => {
  const a = -T.rot * Math.PI / 180;   // 渲染器 ctx.rotate(-rot) ⇒ 屏幕 +13°
  return [T.cx + lx * Math.cos(a) - ly * Math.sin(a), T.cy + lx * Math.sin(a) + ly * Math.cos(a)];
};

// ══════════════════════════════════════════════════════════════════════════
// ① 真删无旋转格纹胶带 + 底板/斜网格纸上下对称
// ══════════════════════════════════════════════════════════════════════════
const TAPE = g.recs.filter(r => /^art657\.game\.board\.tape\./.test(r.name || ''));
const tapeIds = new Set(TAPE.map(r => r.id));
if (TAPE.length !== 53) throw Error('tape 层数不符，期望 53 实得 ' + TAPE.length);
if (g.recs.some(r => tapeIds.has(r.parentId))) throw Error('tape 仍有子记录，不能真删');
for (const r of TAPE) {
  const i = recTop.sub.findIndex(q => q === r.field);
  if (i < 0) throw Error('tape 记录不在 recTop ' + r.name);
  recTop.sub.splice(i, 1);
  g.recs.splice(g.recs.indexOf(r), 1);
  byId.delete(r.id); byName.delete(r.name);
  removed.push(r.name);
}

// 统一沿 y 平移 +10.5：白底板 53.5/53.5 对称、斜网格纸 62.5/62.5 对称
const SHIFT = /^(art641\.game\.boardframe\.|art656\.home\.grid\.|art656\.home\.paper\.edge$|art663\.grid\.h)/;
let shifted = 0;
for (const r of g.recs.filter(q => q.name && SHIFT.test(q.name))) {
  const gm = screenGeom(r);
  if (!gm) continue;
  setGeomScreen(r, gm[0], gm[1] + 10.5, gm[2], gm[3]);
  shifted++;
}

// ══════════════════════════════════════════════════════════════════════════
// ② 票券：3 级斜向阶梯（拟合图元）+ 撕纸凹口/尖齿边
// ══════════════════════════════════════════════════════════════════════════
retint(named('art641.game.help.tab'), '#8C2800');        // 底色 / 右半（设计图 28.0%）
retint(named('art661.tab.outline'), '#592520');           // 设计图深棕描边
for (const n of ['art661.tab.light.rect', 'art661.tab.light.tri',
                 'art661.tab.light.patch1', 'art661.tab.light.patch2']) hide(named(n));
// 663 的 16 枚外凸浅齿改造为真正的「锯齿撕边」：
//   edge  = 背景色矩形（与票券同 rot / 同高），盖掉两端各 ~13px 的票券边缘；
//   tooth = 票券色圆齿，把边缘推回来形成 4 枚齿，齿间露出背景色 ⇒ 内凹缺口。
// 背景色按两端真实背景取值：左白格纹纸、右橙黄底；矩形不出票券上下边，不会在背景上留色带。
const edgeNames = g.recs.filter(r => /^art663\.tab\.edge\./.test(r.name || '')).map(r => r.name);
const toothNames = g.recs.filter(r => /^art663\.tab\.tooth\./.test(r.name || '')).map(r => r.name);
const NOTCH_LY = [-24, -8, 8, 24];
edgeNames.forEach((n, i) => {
  const r = named(n), side = i < 4 ? -1 : 1;
  // 矩形右/左边界正好收在票券边缘（±70），不在背景上留下色带
  const [x, y] = rotPt(side * (T.w / 2 - 10), 0);
  setGeomScreen(r, x, y, 20, T.h);
  retint(r, side < 0 ? '#FDF6DC' : '#E7B53C', 100001);
  setRot(r, T.rot);
});
toothNames.forEach((n, i) => {
  const r = named(n), side = i < 4 ? -1 : 1;
  const [x, y] = rotPt(side * (T.w / 2 - 8), NOTCH_LY[i % 4]);
  setGeomScreen(r, x, y, 21, 21);
  retint(r, side < 0 ? '#AF3200' : '#8C2800', 100002);
  setRot(r, 0);
});
// 拟合三角：中阶先画、亮阶后画；rot 归一化到 [0,360)（360° 周期等价，避开负角）
let fitCount = 0;
for (const step of FIT.steps) {
  for (const e of step.elements) {
    const rot = ((e.rotation % 360) + 360) % 360;
    clone(GRP, `art664.tab.${step.tag}.fit${String(++fitCount).padStart(2, '0')}`, {
      cx: e.x, cy: e.y, w: e.width, h: e.height, rot,
      color: step.color, imageId: 100003,
      before: 'art661.ribbon.mid.rect',
    });
  }
}
// 凹口/尖齿原在 art661.tab.outline 之前（图层更下）会被描边与色阶盖住；
// 移到拟合三角之后，才能作为票券最上层的撕纸边显示。
const edgeFields = [...edgeNames, ...toothNames].map(n => named(n).field);
for (const f of edgeFields) {
  const i = recTop.sub.indexOf(f);
  if (i >= 0) recTop.sub.splice(i, 1);
}
const insertAt = recTop.sub.indexOf(byName.get('art661.ribbon.mid.rect').field);
if (insertAt < 0) throw Error('找不到票券层序参考点');
recTop.sub.splice(insertAt, 0, ...edgeFields);

// ══════════════════════════════════════════════════════════════════════════
// ③ 火漆：亮红外环 + 左右强亮 + 中心压印
// ══════════════════════════════════════════════════════════════════════════
for (const n of ['art663.wax.glow.l', 'art663.wax.glow.r', 'art663.wax.inner']) hide(named(n));
const WX = 1326, WY = 342, N = 16;
// 663 的 12 瓣深色外沿是「花朵轮廓」的根因：12 枚同色椭圆收拢到同一中心
// 重叠成一枚完美圆（半径 53），轮廓改由它决定，只留主体瓣的极浅起伏 + 顶部鼓包。
for (const r of g.recs.filter(q => /^art663\.wax\.edge\./.test(q.name || ''))) {
  setGeomScreen(r, WX, WY, 106, 106);
  setRot(r, 0);
}
// 主体改为 8 瓣浅起伏（设计图实测 6~8 个不规则凸起），其余 4 枚收进内部只补色
const lobeRecs = g.recs.filter(q => /^art663\.wax\.lobe\./.test(q.name || ''));
lobeRecs.forEach((r, i) => {
  if (i < 8) {
    const a = 2 * Math.PI * i / 8 - Math.PI / 2;
    setGeomScreen(r, WX + 32 * Math.cos(a), WY + 32 * Math.sin(a), 42, 42);
  } else setGeomScreen(r, WX, WY, 40, 40);
  setRot(r, 0);
});
const WAX_BEFORE = 'art657.game.flag.hint.ribbon.tri.bottom';
// 亮红环带：R=42 / d=18 / 16 瓣 ⇒ 相邻距 16.4 < 18 连成连续环，
// 外沿半径 51 与主体齐平（不额外外凸，避免花朵轮廓），内沿 33 被中心主体盖住。
for (let i = 0; i < N; i++) {
  const a = 2 * Math.PI * i / N - Math.PI / 2;
  clone(GRP, `art664.wax.ring.${i}`, {
    cx: WX + 42 * Math.cos(a), cy: WY + 42 * Math.sin(a), w: 18, h: 18,
    color: '#B40806', imageId: 100002, before: WAX_BEFORE,
  });
}
// 设计图火漆顶部中央有一枚明显的鼓包（封蜡滴落不均）
clone(GRP, 'art664.wax.top.lobe', {
  cx: WX, cy: WY - 46, w: 30, h: 30, color: '#B40806', imageId: 100002, before: WAX_BEFORE,
});
clone(GRP, 'art664.wax.center', {
  cx: WX, cy: WY, w: 84, h: 84, color: '#AA0400', imageId: 100002, before: WAX_BEFORE,
});
// 左右最亮（设计图 #D70601 只出现在水平两端）
for (const [tag, dx] of [['l', -46], ['r', 46]])
  clone(GRP, `art664.wax.hot.${tag}`, {
    cx: WX + dx, cy: WY, w: 14, h: 26, color: '#D70601', imageId: 100002, before: WAX_BEFORE,
  });
// 中心压印：亮边 + 略暗内芯
clone(GRP, 'art664.wax.stamp.rim', {
  cx: WX, cy: WY, w: 68, h: 60, color: '#B40806', imageId: 100002, before: WAX_BEFORE,
});
clone(GRP, 'art664.wax.stamp.core', {
  cx: WX, cy: WY, w: 56, h: 50, color: '#A60400', imageId: 100002, before: WAX_BEFORE,
});

// ── childList：真删 + 新增都要与全局记录表同序 ─────────────────────────────
const fieldIndex = new Map();
recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
for (const pid of new Set([...added.map(r => r.parentId), GRP.id])) {
  const p = byId.get(pid);
  if (!p) throw Error('父记录丢失 ' + pid);
  const cl = ensureChildListTop(p);
  const orig = (asIdList(cl.payload, true) || []).filter(id => !tapeIds.has(id));
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids);
  touch(p);
}

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) {
  if (bgIds.has(id)) return; bgIds.add(id);
  for (const r of g.recs) if (r.parentId === id) walk(r.id);
})(named('police-v19').id);
const protect = /^(clues\.help617$|clues\.help627\.hit$|hex\.|hit\.|hud\.|board\.floors|board\.rugs|cell\.|letter$|what$|who$|face$|gray$|gen\.|row\.|art661\.clues\.grid\.)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protect.test(r.name)).map(r => r.id)]);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));

if (DRY) {
  console.log(JSON.stringify({
    dry: true, baseSha256: ACTUAL_BASE, recordsBefore: beforeBytes.size,
    recordsAfter: expected.size, removed: removed.length, added: added.length,
    hidden: hidden.length, modified: modified.length, shifted,
    fitTriangles: fitCount, tapeIdsInChildList: 0,
  }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '664 remove unused grid tape / symmetric board / ticket gradient / wax texture',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    if ([...tapeIds].some(id => ids.has(id))) return 'tape 记录未从控件树删除';
    let seen = 0;
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (protectedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '受保护记录被改动 ' + r.name;
      if (!touchedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '非目标记录被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
      seen++;
    }
    if (seen !== expected.size) return '记录数不符 ' + seen + ' != ' + expected.size;
    return true;
  },
});

const audit = {
  version: 1, name: '664 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '663_关卡内UI.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '664_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    item1_delete: 'art657.game.board.tape.* 53 条（top 27 / bottom 26）从 recTop 与父 childList 真删；全仓核查无其它运行时引用、无子记录。',
    item1_symmetry: '棋盘深紫内框实测 y=107..732；统一 y+10.5 后 boardframe.paper 53.5..785.5（上53.5/下53.5）、art656.home.grid.paper 44.5..794.5（上62.5/下62.5），大小/颜色/角度不变。',
    item2_ticket: '设计图 6236×3508 原 PNG 逐点采样：#8C2800 28.0% / #AF3200 26.2% / #CB4C19 10.1%；分界（局部）lx+ly<18 与 <−42；fit-primitive-shape.mjs 生成 23 枚 100003，coverage 100%、overflow 0，rot 归一化 [0,360)。边缘用「背景色矩形盖掉两端各 13px + 4 枚票券色圆齿推回」形成内凹锯齿撕边（左 #FDF6DC 白格纹 / 右 #E7B53C 橙黄）。',
    item3_wax: '设计图剖面：外圈亮红 #B40806、左右最亮 #D70601、主体 #AA0400；663 的 12 瓣深色外沿收拢成一枚 106 圆（消除花朵轮廓），新增 16 枚亮环（R=42/d=18，外沿半径 51 不出轮廓）+ 顶部鼓包 + 84 主体 + 2 枚强亮 + 2 层压印，隐藏 663 的 glow.l/r 与 inner。',
    ignored: 'v19 背景资产为独立内容，police-v19 子树零改动；内嵌 Lua 零改动。',
  },
  counts: {
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    removed: removed.length, added: added.length, hidden: hidden.length,
    modified: modified.length, shifted,
  },
  fit: FIT.steps.map(s => ({ tag: s.tag, color: s.color, D: s.D, elements: s.elements.length,
    coverage: s.verification.coverage, overflowVertices: s.verification.overflowVertices })),
  removed, modified, hidden, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '664_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  removed: removed.length, added: added.length, hidden: hidden.length,
  modified: modified.length, shifted, fitTriangles: fitCount,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
