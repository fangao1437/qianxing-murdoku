// 663 · 基于 662v19.gil 的五项画面调整（增量构建，不覆盖任何旧档）
//
// 输入：662v19.gil（v19 背景资产导入后的最新存档，UI 层与 662 一致）
// 输出：663_关卡内UI.gil + 663_构建审计.json
//
// 五项（用户口径）：
//   ① 注释按钮底图 → 设计图撕票券：加大到 145×88、深棕描边、两端 3 枚大圆弧撕边、亮部换 #B13201
//   ② 线索区活页扣 → 5 组粗弧形金属环（上缘高光 / 下缘暗带 / 末端圆头），替换原 38×9 扁条
//   ③ 棋盘下第一张（图层更上的 boardframe 纸框）→ 设计图白色底板 #FDFCE7；
//      第二张（图层更下的 art656.home.grid 斜网格纸）大小/颜色/角度全部不动，只补 19 条缺失横线
//   ④ 拍立得火漆 → 隐藏原完美圆形图钉，用 8 瓣扇贝椭圆 + 暗边 + 亮环 + 内圈构造不规则封蜡
//   ⑤ 线索卡背后 → 一整块纯色底板 #68262A；隐藏 3 段渐变与 4 条静态白线（消除滚动负反馈）
//
// 方法（本机 GitHub v15《美术资产-原生图形构造与v12-v15演进》）：
//   同色不透明图元重叠无缝；不用父级裁剪；不用竖条扫描斜边；新增层一律 append 到静态根
//   或 art657.grid.reuse，childList 与全局记录表同序；落盘只走 writeGil() 六道闸。
// 口径：1600×900 屏幕坐标（左上原点、y 向下）；v19 背景资产为独立内容，其差异忽略且零改动。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/657_关卡内UI');
const INPUT = path.join(DIR, '662v19.gil');
const OUTPUT = path.join(DIR, '663_关卡内UI.gil');
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
const added = [], hidden = [], modified = [], touchedIds = new Set();
function touch(r) {
  if (!r) return;
  touchedIds.add(r.id);
  if (r.name && !modified.includes(r.name)) modified.push(r.name);
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
  const cl = (function find(ff) {
    return ff.sub?.find(q => q.wt === 2 && q.payload && asIdList(q.payload, true));
  })(f);
  if (cl) setChildList(cl, []);
  let idx = -1;
  if (o.before) idx = recTop.sub.findIndex(q => q === byName.get(o.before)?.field);
  else if (o.after) idx = recTop.sub.findIndex(q => q === byName.get(o.after)?.field) + 1;
  if (idx < 0) idx = recTop.sub.length;
  recTop.sub.splice(idx, 0, f);
  const p = ns(f, [505, 503, 84])[0];
  if (p && o.color) {
    setNum(p, 502, colorOf(o.color));
    setNum(p, 503, o.imageId ?? 100001);
    setNum(p, 504, 1);
  }
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  setGeomScreen(r, o.cx, o.cy, o.w, o.h);
  if (o.rot) setRot(r, o.rot);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r);
  touch(r);
  return r;
}
function hide(r) { setHiddenRecord(r.field, true); hidden.push(r.name); touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');
const REUSE = named('art657.grid.reuse');
const rotPt = (cx, cy, deg, lx, ly) => {
  const a = deg * Math.PI / 180;
  return [cx + lx * Math.cos(a) - ly * Math.sin(a), cy + lx * Math.sin(a) + ly * Math.cos(a)];
};

// ══════════════════════════════════════════════════════════════════════════
// ① 注释按钮底图 —— 设计图撕票券
//    1600×900 实测：票券 145×88 @(384,211) rot −13；深棕描边 #3A1A12；
//    主体 #8B2800、左下亮部 #B13201；两端各 3 枚圆弧撕边；白色 ? 与热区逐字节不动。
// ══════════════════════════════════════════════════════════════════════════
// 设计图票券与实机基线的尺寸基本一致（140×66 rot −13），本轮只重做「底图形状」：
// 撕边 + 配色，不放大票券本体，避免包围盒比设计图高一大截。
const TAB = { cx: 384, cy: 211, w: 140, h: 66, rot: -13 };
setGeomScreen(named('art661.tab.outline'), TAB.cx, TAB.cy, 146, 72);
setGeomScreen(named('art641.game.help.tab'), TAB.cx, TAB.cy, TAB.w, TAB.h);
const LX = 1, LY = 1;
for (const n of ['art661.tab.light.rect', 'art661.tab.light.tri',
                 'art661.tab.light.patch1', 'art661.tab.light.patch2']) {
  const r = named(n), st = states(r)[0];
  const p = pairOf(st, 504), s = pairOf(st, 505);
  const cx = 800 + pairValue(p, 0), cy = 450 - pairValue(p, 1);
  const w = pairValue(s, 0), h = pairValue(s, 1);
  setGeomScreen(r, TAB.cx + (cx - TAB.cx) * LX, TAB.cy + (cy - TAB.cy) * LY, w * LX, h * LY);
  retint(r, '#A83408');
}
for (const n of ['art661.tab.notch.l1', 'art661.tab.notch.l2', 'art661.tab.notch.l3',
                 'art661.tab.notch.r1', 'art661.tab.notch.r2', 'art661.tab.notch.r3',
                 'art661.tab.tip.lt', 'art661.tab.tip.lb', 'art661.tab.tip.rt', 'art661.tab.tip.rb'])
  hide(named(n));
// 撕边：每端 4 枚小椭圆，间距 22 < 直径 22/26 ⇒ 连成连续浅锯齿；
// 中心收进票券边缘 8px、半径 11~13 ⇒ 只外凸 3~5px，避免变成大圆齿或分离圆点。
const TOOTH_LY = [-24, -8, 8, 24];
for (const [di, d, color, before] of [
  [26, 26, '#3A1A12', 'art661.tab.outline'],
  [22, 22, '#8B2800', 'art661.tab.light.rect'],
]) {
  for (const side of [-1, 1]) {
    const s = side < 0 ? 'l' : 'r';
    TOOTH_LY.forEach((ly, i) => {
      // 渲染器用 ctx.rotate(-gm.rot)，gm.rot = −13 ⇒ 屏幕实际顺时针 +13°；
      // 故此处角度取 −TAB.rot，否则齿会沿反方向跑到票券角外变成孤立圆点。
      const [x, y] = rotPt(TAB.cx, TAB.cy, -TAB.rot, side * (TAB.w / 2 - 4), ly);
      clone(GRP, `art663.tab.${di === 26 ? 'edge' : 'tooth'}.${s}${i}`, {
        cx: x, cy: y, w: d, h: d, color, imageId: 100002, before,
      });
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ② 线索区活页扣 —— 5 组粗弧形金属环
//    设计图：从左侧深棕装订条伸出、末端圆润、上缘浅灰高光 / 下缘深棕暗带。
// ══════════════════════════════════════════════════════════════════════════
for (let k = 1; k <= 5; k++) {
  hide(named(`art657.game.notebook.ring.${k}`));
  hide(named(`art657.game.notebook.ringhole.${k}`));
}
const RING_Y = [322, 415, 511, 606, 699];
for (let i = 0; i < RING_Y.length; i++) {
  const y = RING_Y[i], tag = i + 1;
  // 弧钩：主条左高右低（rot −14），末端圆头下坠 y+9，上缘浅灰高光 / 下缘深棕暗带
  const layers = [
    ['outer', 16, y,     46, 24, '#241710', -14],
    ['hi',    14, y - 7, 34,  7, '#6C6962', -14],
    ['shade', 18, y + 6, 38,  8, '#3B1C14', -14],
    ['tip',   36, y + 9, 18, 18, '#241710', -14],
  ];
  for (const [k, cx, cy, w, h, c, rot] of layers)
    clone(GRP, `art663.ring.${tag}.${k}`, {
      cx, cy, w, h, color: c, imageId: 100002, rot,
      before: 'art657.game.board.tape.top.base',
    });
}

// ══════════════════════════════════════════════════════════════════════════
// ③ 棋盘下两张纸
//    第一张（图层更上）= art641.game.boardframe.paper：改设计图白色底板 #FDFCE7，阴影淡化。
//    第二张（图层更下）= art656.home.grid.*：645×750 / #F8E0A8 / −5.2° 全部原样保留，
//      只补 y=186..723 区间缺失的 19 条横线（原有 h0..h3 只有顶 2 条 + 底 2 条）。
// ══════════════════════════════════════════════════════════════════════════
retint(named('art641.game.boardframe.paper'), '#FDFCE7');
retint(named('art641.game.boardframe.shadow'), '#FBF3D8');
const GRID_ROT = -5.199999809265137;
let afterGrid = 'art656.home.grid.h3';
for (let k = 1; k <= 19; k++) {
  const y = 156.2 + 29.84 * k;
  const x = 828.9 - 0.091 * (y - 126.4);
  const name = `art663.grid.h${String(k + 3).padStart(2, '0')}`;
  clone(REUSE, name, {
    proto: 'art656.home.grid.h1',
    cx: x, cy: y, w: 645, h: 2, rot: GRID_ROT, color: '#E8D098',
    after: afterGrid,
  });
  afterGrid = name;
}

// ══════════════════════════════════════════════════════════════════════════
// ④ 拍立得火漆 —— 8 瓣扇贝封蜡（原生 100002 椭圆同色重叠，零裁剪）
//    实测轮廓 x1273..1379 / y292..392 @1600 口径 ⇒ 中心 (1326,342)、外径 ~106。
// ══════════════════════════════════════════════════════════════════════════
for (const n of ['art657.game.pin.border', 'art657.game.pin',
                 'art657.game.pin.mid', 'art657.game.pin.hilite']) hide(named(n));
const WX = 1326, WY = 342, N = 12;
const WAX_BEFORE = 'art657.game.flag.hint.ribbon.tri.bottom';
const waxRing = (prefix, R, d, color) => {
  for (let i = 0; i < N; i++) {
    const a = 2 * Math.PI * i / N - Math.PI / 2;
    clone(GRP, `${prefix}.${i}`, {
      cx: WX + R * Math.cos(a), cy: WY + R * Math.sin(a),
      w: d, h: d, color, imageId: 100002, before: WAX_BEFORE,
    });
  }
};
// 12 瓣 + R=32 / d=38~42 ⇒ 相邻瓣大幅重叠，轮廓接近圆、只留很浅的起伏（设计图实测轮廓
// 逐行宽度 37→127→44 近似圆形），避免 8 瓣大半径造成的花朵/齿轮感。
waxRing('art663.wax.edge', 32, 42, '#8E0600');   // 暗色外沿
waxRing('art663.wax.lobe', 32, 38, '#AA0400');   // 浅起伏主体
clone(GRP, 'art663.wax.core', {
  cx: WX, cy: WY, w: 92, h: 92, color: '#AA0400', imageId: 100002, before: WAX_BEFORE,
});
// 设计图的亮红只集中在左右两侧外缘，不是一整圈同心环
clone(GRP, 'art663.wax.glow.l', {
  cx: WX - 33, cy: WY, w: 16, h: 66, color: '#AE0603', imageId: 100002, rot: -10, before: WAX_BEFORE,
});
clone(GRP, 'art663.wax.glow.r', {
  cx: WX + 33, cy: WY, w: 16, h: 66, color: '#AE0603', imageId: 100002, rot: 10, before: WAX_BEFORE,
});
clone(GRP, 'art663.wax.inner', {
  cx: WX, cy: WY, w: 60, h: 48, color: '#A60400', imageId: 100002, before: WAX_BEFORE,
});

// ══════════════════════════════════════════════════════════════════════════
// ⑤ 线索卡背后 —— 一整块纯色底板
//    隐藏 3 段渐变与 4 条静态白线（它们把内页切成 5 张"静态红卡"，滚动时不跟随内容）。
//    模板内的卡片底色/白线仍随卡片实例滚动，保留。
// ══════════════════════════════════════════════════════════════════════════
retint(named('art657.game.notebook.page'), '#68262A');
hide(named('art657.game.notebook.page.mid'));
hide(named('art657.game.notebook.page.lower'));
for (let k = 1; k <= 4; k++) hide(named(`art657.game.notebook.rule.${k}`));

// ── childList 与全局记录表同序 ───────────────────────────────────────────────
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

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) {
  if (bgIds.has(id)) return; bgIds.add(id);
  for (const r of g.recs) if (r.parentId === id) walk(r.id);
})(named('police-v19').id);
const protect = /^(clues\.help617$|clues\.help627\.hit$|hex\.|hit\.|hud\.|board\.floors|board\.rugs|cell\.|letter$|what$|who$|face$|gray$|gen\.|row\.|art656\.home\.grid\.|art661\.clues\.grid\.)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protect.test(r.name)).map(r => r.id)]);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));

if (DRY) {
  console.log(JSON.stringify({
    dry: true, baseSha256: ACTUAL_BASE, recordsBefore: g.recs.length,
    recordsAfter: expected.size, added: added.length, hidden: hidden.length,
    modified: modified.length, protectedIds: protectedIds.size,
    scriptBytes: scriptBefore.length,
    groups: {
      tab: added.filter(r => r.name.startsWith('art663.tab')).length,
      ring: added.filter(r => r.name.startsWith('art663.ring')).length,
      grid: added.filter(r => r.name.startsWith('art663.grid')).length,
      wax: added.filter(r => r.name.startsWith('art663.wax')).length,
    },
  }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '663 five visual adjustments on 662v19',
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
  version: 1, name: '663 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '662v19.gil', sha256: ACTUAL_BASE, records: g.recs.length, scriptBytes: scriptBefore.length },
  output: { file: '663_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    coordinate: '1600x900 屏幕坐标；设计图 1920x1080 → ×0.8333；实机 1604x960 → crop(2,38)',
    fiveItems: [
      '① 注释票券：保持 140×66 @(384,211) rot−13 / 描边 146×72 #3A1A12（与设计图、基线同尺寸），主体 #8B2800、亮部 #A83408；两端各 4 枚重叠小椭圆连成连续浅锯齿撕边；? 本体与热区逐字节不动',
      '② 活页扣：5 组弧形金属环（outer/hi/shade/tip 各 1 枚 100002 椭圆，rot −14、末端圆头下坠），色 #241710/#6C6962/#3B1C14，替换原 38×9 扁条与环孔',
      '③ 棋盘下第一张（图层更上 boardframe.paper）→ #FDFCE7 白色底板，shadow → #FBF3D8；第二张 art656.home.grid 大小/颜色/角度零改动，仅补 19 条横线 h04..h22（step 29.84，x=828.9−0.091(y−126.4)）',
      '④ 火漆：中心 (1326,342)，12 瓣浅起伏（R=32/d=38~42）+ 暗沿 + 左右亮红弧 + 淡压印共 28 层 100002；原 4 层完美圆图钉隐藏',
      '⑤ 线索卡背后：page 统一 #68262A 纯色，隐藏 page.mid/page.lower 与 4 条静态白线，消除 5 张静态红卡的滚动负反馈',
    ],
    method: '本机 GitHub v15《美术资产-原生图形构造与v12-v15演进》：同色不透明图元重叠无缝、不用父级裁剪、childList 与全局记录表同序、落盘走 writeGil 六道闸。',
    ignored: 'v19 背景资产 (murdoku-police-v19-text.gia) 为独立内容，其差异忽略；police-v19 子树 649 条零改动。',
  },
  counts: {
    recordsBefore: g.recs.length, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length,
  },
  addedByGroup: {
    tab: added.filter(r => r.name.startsWith('art663.tab')).length,
    ring: added.filter(r => r.name.startsWith('art663.ring')).length,
    grid: added.filter(r => r.name.startsWith('art663.grid')).length,
    wax: added.filter(r => r.name.startsWith('art663.wax')).length,
  },
  protectedRecords: protectedIds.size,
  modified, hidden, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '663_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, modified: modified.length,
  addedByGroup: audit.addedByGroup, scriptBytes: scriptBefore.length,
  protectedRecords: protectedIds.size, status: 'APPLIED',
}, null, 2));
