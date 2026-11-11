// 658 · 基于 657改.gil（用户已关掉网格视窗滚动条）的六项修正
//
// 输入：657改.gil（锁 SHA256，不覆盖）
// 输出：658_关卡内UI.gil + 658_构建审计.json
//
// 用户实机/设计图对照提出的六点：
//  1 提示按钮（问号帮助）的素材没保留原素材 → 恢复 clues.help617 的官方 100113，
//    只改底图和位置；隐藏我上一轮自绘的 sticker.q.dot / sticker.q.mark。
//  2 除提示外其它按钮底图偏大 → 量 art647.select.back/settle 的旗面与三角尺寸并照做。
//  3 提示按钮底图与设计图明显不符 → 便利贴重做成票券（锯齿边 + 斜向多色渐变）。
//  4 线索区网格纸 / 笔记本样式没做 → 在 clues 内补格纹纸窄带、深棕装订条、黄色虚线；
//    内页斜向渐变放进 clue 模板（见 5）。
//  5 燕尾旗胶布 / 选项卡渐变没做 → 查到「引擎按父级矩形裁剪」(v284 回执真机验证)，
//    故用单个旋转矩形/三角形 + 父级裁剪做多色斜向渐变；网格视窗内的选项卡
//    在两套 clue 模板里拼。红缎带同样补斜向渐变。
//  6 设计图里的黑框只是头像预留位示意 → 隐藏 5 个 notebook.slot.*。
//
// 用法：
//   node 构建658_改进.mjs
//   FORCE=1 node 构建658_改进.mjs
//
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const INPUT = path.join(DIR, '657改.gil');
const OUTPUT = path.join(DIR, '658_关卡内UI.gil');
const BASE_SHA256 = 'bf3b6e8a36ba8ed68a1a4cbdb32d40615755eb8945a91f592f6db9a07b0941ee';
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
if (sha(INPUT) !== BASE_SHA256) throw Error('657改.gil SHA256 不符：' + INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const { readGil, stateBlocks, pairOf, pairValue, setPair, cloneField,
  ensureChildListTop, findChildListTop, asIdList, setChildList, textsOf, encodeMsg } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { writeGil, findScriptLeaf } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { setHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const recTop = g.tree.find(q => q.field === 9);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
let max = BigInt(g.maxId);
const added = [], modified = [], hidden = [];

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
const centerCache = new Map();
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (centerCache.has(r.id)) return centerCache.get(r.id);
  const st = states(r)[0], p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  centerCache.set(r.id, res); return res;
}
function touch(r) { if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function setGeomScreen(r, cx, cy, w, h) {
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - px, py - cy);
    setPair(pairOf(st, 505), w, h);
  }
  touch(r);
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
function retintRaw(r, value) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块：' + r.name);
  setNum(p, 502, value); touch(r);
}
const retint = (r, hex) => retintRaw(r, colorOf(hex));
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
const PROTO_IMG = 'td.home.page.1.help619.icon';
const PROTO_TXT = 'td.l1.page.1.heading';
function clone(parent, name, o) {
  const proto = o.text ? byName.get(PROTO_TXT) : (o.proto ? byName.get(o.proto) : byName.get(PROTO_IMG));
  if (!proto) throw Error('缺克隆原型：' + (o.proto || PROTO_IMG));
  const f = cloneField(proto.field);
  const id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nf) throw Error('找不到名字字段：' + proto.name);
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  if (parent) f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = findChildListTop(f.sub);
  if (cl) setChildList(cl, []);
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  if (o.before || o.beforeId !== undefined) {
    const ref = o.beforeId !== undefined ? byId.get(o.beforeId) : byName.get(o.before);
    const idx = recTop.sub.findIndex(q => q === ref?.field);
    if (idx < 0) throw Error('参考记录不在 recTop：' + (o.before || o.beforeId));
    recTop.sub.splice(idx, 0, f);
  } else recTop.sub.push(f);
  const p = ns(f, [505, 503, 84])[0];
  if (p && (o.color || o.colorRaw !== undefined)) {
    setNum(p, 502, o.colorRaw !== undefined ? o.colorRaw : colorOf(o.color));
    setNum(p, 503, o.imageId ?? 100001);
    setNum(p, 504, 1);
  }
  if (o.text) {
    const tp = ns(f, [505, 503, 75])[0], leaf = ns(f, [505, 503, 75, 510, 501])[0];
    if (!tp || !leaf) throw Error('文本原型结构不符：' + name);
    leaf.payload = Buffer.from(o.text); leaf.len = leaf.payload.length;
    for (const [k, v] of [[502, 0], [512, o.fontSize || 28], [513, o.fontSize || 28],
      [504, colorOf(o.color)], [508, 1], [509, 1]]) setNum(tp, k, v);
  }
  setGeomScreen(r, o.cx, o.cy, o.w, o.h);
  if (o.deg !== undefined) setRot(r, o.deg);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r);
  return r;
}
const push = (parent, name, o) => clone(parent, name, o);
function hide(r) { setHiddenRecord(r.field, true); hidden.push(r.name); touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }

// ── 1. 提示按钮：恢复官方素材，只换底图和位置 ─────────────────────────────
const helpBody = named('clues.help617');
retintRaw(helpBody, 0xffffffff);              // 恢复 100113 官方「红圈白 ?」素材
setGeomScreen(helpBody, 384, 211, 40, 40);   // 只换位置与显示尺寸，imageId 不动
hide(named('art657.game.sticker.q.dot'));    // 撤掉我上一轮自绘的白圆
hide(named('art657.game.sticker.q.mark'));   // 撤掉我上一轮自绘的 ? 文本
// 热区保持上一轮已对齐的 (384,211,144,88)

// ── 2. 其它按钮：量选关界面 art647.select.back/settle 后照做 ───────────────
// 选关 settle 配方（左端燕尾，用于右上三键 + 右下放大镜），中心 (1484.6,732.1)
// 选关 back   配方（右端燕尾，用于左上返回），中心 (105.8,148.8)
const SEL = {
  settle: {
    center: [1484.6, 732.1],
    ribbon:  [1504.4, 732.1, 134.6, 79.2],
    outline: [1503.2, 732.1, 148.7, 90.8],
    oTop:    [1428.8, 709.4,  90.8, 45.4, 180],
    oBot:    [1428.8, 754.8,  90.8, 45.4, 0],
    rTop:    [1437.1, 712.3,  79.2, 39.6, 180],
    rBot:    [1437.1, 751.9,  79.2, 39.6, 0],
    shadow:  [1491.3, 739.6, 174.2, 79.2],
  },
  back: {
    center: [105.8, 148.8],
    ribbon:  [85.4, 148.8, 139.2, 79.2],
    outline: [86.3, 148.8, 152.7, 90.8],
    oTop:    [162.7, 126,    78,   45.4, 180],
    oBot:    [162.7, 171.5,  78,   45.4, 0],
    rTop:    [155,   129,    68,   39.6, 180],
    rBot:    [155,   168.5,  68,   39.6, 0],
    shadow:  [85.4,  156.3, 139.2, 84.2],
  },
};
// 目标中心：右上三键 / 放大镜按设计图逐列扫描，返回按钮按设计图 x27-143/y107-207
const TARGETS = {
  submit: { recipe: 'settle', center: [1484.6, 152] },
  redo:   { recipe: 'settle', center: [1484.6, 247.5] },
  undo:   { recipe: 'settle', center: [1484.6, 336.5] },
  hint:   { recipe: 'settle', center: [1484.6, 732.1] },
  back:   { recipe: 'back',   center: [85, 157], scale: 0.78 },
};
function applyRecipe(key, t) {
  const S = SEL[t.recipe], k = t.scale || 1;
  const [dx, dy] = [t.center[0] - S.center[0], t.center[1] - S.center[1]];
  const T = (a) => {
    const cx = t.center[0] + (a[0] - S.center[0]) * k;
    const cy = t.center[1] + (a[1] - S.center[1]) * k;
    return [cx, cy, a[2] * k, a[3] * k, a[4]];
  };
  const layers = {
    ribbon: T(S.ribbon), outline: T(S.outline), oTop: T(S.oTop), oBot: T(S.oBot),
    rTop: T(S.rTop), rBot: T(S.rBot), shadow: T(S.shadow),
  };
  // 现有 6 层 + 旗面矩形，全部改几何，不新增记录
  setGeomScreen(named(`art641.game.flag.${key}`), ...layers.ribbon.slice(0, 4));
  setGeomScreen(named(`art657.game.flag.${key}.shadow`), ...layers.shadow.slice(0, 4));
  setGeomScreen(named(`art657.game.flag.${key}.outline`), ...layers.outline.slice(0, 4));
  for (const [suffix, arr] of [['outline.tri.top', layers.oTop], ['outline.tri.bottom', layers.oBot],
    ['ribbon.tri.top', layers.rTop], ['ribbon.tri.bottom', layers.rBot]]) {
    const r = named(`art657.game.flag.${key}.${suffix}`);
    setGeomScreen(r, ...arr.slice(0, 4));
    setRot(r, arr[4]);
  }
  // 图标与热区同步到新旗面中心
  const hx = layers.ribbon[0], hy = layers.ribbon[1];
  const icon = byName.get('hex.' + key), hit = byName.get('hit.' + key);
  if (icon) setGeomScreen(icon, hx, hy, 64, 64);
  if (hit) setGeomScreen(hit, hx, hy, 84, 96);
}
for (const [key, t] of Object.entries(TARGETS)) applyRecipe(key, t);

// ── 3. 提示按钮底图：票券（锯齿边 + 斜向多色渐变） ────────────────────────
const GRP = byName.get('grp653.static.1.art641.game');
const tab = named('art641.game.help.tab');
retint(tab, '#A0300C'); setGeomScreen(tab, 384, 211, 144, 88); setRot(tab, -10);
// 裁剪能力已查证：docs/回执-教程UI并入-v284.md「引擎按父级矩形裁剪」（真机验证），
// 图片控件另有 enableMask / fillType+fillAmount，网格视窗也自带裁切。
// ⇒ 用「固定尺寸父容器 + 单个旋转矩形」做多色斜向渐变，溢出自动裁掉，不拼碎块。
function clippedGradient(host, name, cx, cy, w, h, colors, deg, before, beforeId) {
  const clip = push(host, `${name}.clip`, {
    proto: 'art641.game', cx, cy, w, h, colorRaw: 0x00ffffff,
    ...(beforeId !== undefined ? { beforeId } : { before }),
  });
  colors.forEach((c, i) => {
    const off = (i - (colors.length - 1) / 2) * (w / colors.length) * 0.75;
    push(clip, `${name}.g${i + 1}`, {
      cx: cx + off * Math.cos(deg * Math.PI / 180),
      cy: cy + off * Math.sin(deg * Math.PI / 180),
      w: w * 0.75, h: h * 0.8, color: c, deg,   // 收在裁剪框内，不产生碎片
    });
  });
  return clip;
}
// 票券左右两端各 2 个同色小锯齿（不再用一堆深色碎三角）
for (const [side, x] of [['l', 314], ['r', 454]]) for (let i = 0; i < 2; i++)
  push(GRP, `art658.help.tab.jag.${side}${i + 1}`, { cx: x, cy: 190 + i * 42, w: 12, h: 12,
    color: '#A0300C', deg: 45 });
clippedGradient(GRP, 'art658.help.tab', 384, 211, 144, 88,
  ['#C04712', '#A0300C', '#7A2109'], -28);

// ── 4. 线索区格纹纸 / 装订条 ──────────────────────────────────────────────
const clues = named('clues');
// 深棕竖直装订条：必须与活页环同父且先画，否则 clues 组会盖住活页环
push(GRP, 'art658.clues.binding', { cx: 20, cy: 513.5, w: 40, h: 535,
  color: '#2E1A12', before: 'art657.game.notebook.ring.1' });
for (let i = 0; i < 12; i++)
  push(GRP, `art658.clues.binding.dash${i + 1}`, { cx: 20, cy: 270 + i * 44, w: 2, h: 12,
    color: '#E2AE3C', before: 'art657.game.notebook.ring.1' });
// 白框四周露出的格纹纸窄带（上 / 右 / 下）：按设计图采样上移到 y204-226、下移到 y760-780
const bands = [
  ['top', 209, 215, 400, 22], ['right', 412, 513.5, 26, 535], ['bottom', 209, 770, 400, 20],
];
for (const [k, cx, cy, w, h] of bands) {
  push(clues, `art658.clues.grid.${k}.base`, { cx, cy, w, h, color: '#FCFEF1', before: 'clues.bg' });
  const vertical = k === 'right';
  const n = vertical ? Math.floor(h / 20) : Math.floor(w / 20);
  for (let i = 1; i < n; i++) {
    const o = { color: '#E4D2A8', before: 'clues.bg' };
    if (vertical) Object.assign(o, { cx, cy: cy - h / 2 + i * 20, w, h: 2 });
    else Object.assign(o, { cx: cx - w / 2 + i * 20, cy, w: 2, h });
    push(clues, `art658.clues.grid.${k}.l${i}`, o);
  }
}
// 笔记本内页右边缘的橙色竖线（设计图 x~386）
push(clues, 'art658.clues.page.edge', { cx: 388, cy: 511, w: 5, h: 468,
  color: '#D2551F', before: 'clues.bg' });

// ── 5. 选项卡渐变：在两套 clue 模板里拼（网格视窗实例化项会自带父级裁剪） ──
const TPL_IDS = [1073742421, 1073742428];
for (const tid of TPL_IDS) {
  const tpl = byId.get(tid);
  if (!tpl || tpl.name !== 'clue') throw Error('clue 模板丢失 ' + tid);
  const pre = `art658.clue${tid === TPL_IDS[0] ? '1' : '2'}`;
  const backropId = tid === TPL_IDS[0] ? 1073742422 : 1073742429;  // 两套模板的 backrop1 同名，按 ID 定位
  // 底色 = 设计图内页主色实测 (104,38,42) #68282A
  push(tpl, `${pre}.bg`, { cx: 800, cy: 450, w: 330, h: 85.4, color: '#68282A', beforeId: backropId });
  // 多色斜向渐变：设计图采样 亮红(157,48,51) / 主色(104,38,42) / 暗(97,31,35)
  // 亮红只占左上小块，主色与暗色覆盖其余；溢出 330x85.4 的部分由父级/网格视窗裁切
  const cols = ['#9D3033', '#68282A', '#611F23'];
  cols.forEach((c, i) => {
    const off = (i - 1) * 42;
    push(tpl, `${pre}.grad${i + 1}`, { cx: 800 - 72 + off, cy: 450 - off * 0.42,
      w: 150, h: 62, color: c, deg: 28, beforeId: backropId });
  });
  // 行间白分隔线（模板底部 5px，卡片叠起来就是设计图的白线）
  push(tpl, `${pre}.rule`, { cx: 800, cy: 450 - 40, w: 330, h: 5,
    color: '#FDFAF5', beforeId: backropId });
}
// 红缎带（燕尾旗胶布）同样用裁剪容器做斜向多色渐变
clippedGradient(GRP, 'art658.ribbon', 440, 350, 80, 60,
  ['#D2532F', '#B23928', '#8A241C'], 26);

// ── 6. 设计图黑框只是头像预留位示意 → 隐藏 ───────────────────────────────
for (let i = 1; i <= 5; i++) hide(named(`art657.game.notebook.slot.${i}`));

// ── childList 与全局记录表同序 ────────────────────────────────────────────
const fieldIndex = new Map();
recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
const touched = new Set(added.map(r => r.parentId));
for (const pid of touched) {
  const parent = byId.get(pid);
  if (!parent) throw Error('父记录丢失 ' + pid);
  const cl = ensureChildListTop(parent);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids);
  touch(parent);
}

// ── 断言 + 唯一安全落盘通道 ───────────────────────────────────────────────
const police = byName.get('police-v12');
const bgIds = new Set([police.id, ...g.recs.filter(r => r.parentId === police.id).map(r => r.id)]);
const protect = /^(stage|board\.floors|board\.rugs|cell\.|clue$|letter$|what$|who$|face$|gray$|gen\.|hud\.|row\.|hex\.ok|hex\.no|hit\.ok|hit\.no)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protect.test(r.name)).map(r => r.id)]);
// 两套 clue 模板本身要新增子层 ⇒ childList 必然变化，属预期；其子控件（文本/素材）仍受保护
protectedIds.delete(1073742421);
protectedIds.delete(1073742428);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '658 six-point fixes on 657改',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 ' + r.name;
      if (protectedIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '受保护记录被改动 ' + r.name;
    }
    const ids = new Set(t.recs.map(r => r.id));
    const baseIds = new Set(g.recs.map(r => r.id));
    const danglingBefore = new Set(g.recs.filter(r => r.parentId != null && !baseIds.has(r.parentId)).map(r => r.id));
    for (const r of t.recs)
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
    for (const r of added) if (!ids.has(r.id) || !ids.has(r.parentId)) return '新增层父引用异常 ' + r.name;
    for (const n of ['stage', 'board.floors', 'board.rugs', 'clues.grid', 'police-v12', 'root', 'home', 'clues.help617'])
      if (!t.recs.some(r => r.name === n)) return '功能控件丢失 ' + n;
    return true;
  },
});

const audit = {
  version: 1, name: '658 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '657改.gil', sha256: BASE_SHA256, records: 6537, scriptBytes: scriptBefore.length },
  output: { file: '658_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  findings: {
    clip: 'docs/回执-教程UI并入-v284.md 明确「引擎按父级矩形裁剪」（真机验证）；docs/7.1-脚本API速查.md 另有图片控件 enableMask / fillType+fillAmount；docs/research-raw/bs-control-support.md 记网格视窗有裁切。故采用单旋转矩形 + 父级裁剪做多色斜向渐变，不拼碎块。',
    sizes: 'art647.select.back.ribbon 139.2x79.2、settle.ribbon 134.6x79.2；三角 68x39.6 / 79.2x39.6，描边 152.7x90.8 / 148.7x90.8，投影 139.2x84.2 / 174.2x79.2。关卡内按钮按该配方平移（返回按钮按设计图缩到 0.78）。',
    hintMaterial: 'clues.help617 恢复 0xffffffff / imageId 100113；隐藏自绘 sticker.q.*；底图与热区位置不变。',
    clueTemplate: '两套 clue 模板各加 1 底色 + 3 旋转渐变 + 1 行间白线，共 10 层；插在 backrop1 之前，卡片文本/头像仍在其上。',
    noBlackSlots: 'notebook.slot.1..5 隐藏（设计图黑框是头像预留位示意）。',
  },
  counts: { recordsBefore: 6537, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  modified, hidden, addedLayers: added.map(r => ({ id: r.id, name: r.name, parent: byId.get(r.parentId)?.name })),
  backgroundUntouched: `police-v12 + ${bgIds.size - 1} 个直接子控件`,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '658_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, modified: modified.length,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
