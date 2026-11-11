// 657 · 关卡内棋盘屏存档构建（合流版）
//
// 输入：656_首页设计/656_首页设计.gil（最新成果，锁 SHA256）
// 依据：GitHub 657 设计方案（关卡内UI规格_657.json / 657_构建方案.md）
// 输出：657_关卡内UI.gil + 657_构建审计.json + 657_关卡内UI.lua
//
// 与原 SPEC_ONLY 方案的差异（全部为「让实机真的按设计图出图」所必需，详见 657_构建报告.md）：
//   F1 坐标口径：规格把 1600x900 屏幕坐标直接写进记录的父相对位置字段。
//      art641.game / 其分类父 rel=(0,0) 没问题，但 clues rel=(-570,-61.1)、stage rel=(100,20) 会整体偏移。
//      本构建器统一用 setGeomScreen()，按父链真实中心换算。
//   F2 层序：规格把白框插在 clues.bg 之后 ⇒ 不透明白框会盖住暗红内页；且新增记录只 append 到
//      recTop 末尾却插到 childList 中间，违反「recTop 与父 childList 同序」。本构建器让新增层
//      统一挂 grp653.static.1.art641.game，按 recTop 索引重排 childList，描边层插在旗面之前。
//   F3 内页：clues.bg 保持原透明底板（运行时布局表会读它），暗红内页改由独立新层承担，
//      避免父坐标换算与运行时覆盖双重风险；backrop1/2 改 0x00FFFFFF（存档里 5 处透明控件
//      全用这个值，避免 0x00000000 触发引擎缺省色）。
//   F4 图标跟随：旗面加宽/下移后，hex.* 与 hit.* 同步移到新中心（否则图标留在旧窄条位置上）。
//   F5 形状：燕尾旗 V 凹口直接复制选关界面 647 轮真机配方（art647.select.back.* /
//      art647.select.settle.*：矩形 + 2 个 100003 三角 + 深色描边 + 106057 投影），
//      不用纯色菱形硬拼；红图钉补描边与渐变，便利贴按局部放大图修正到 (384,211) 144x88 rot -10。
//   F6 棋盘内框：board.bg 除改深紫外，几何也按设计图 (903.5,420,607,626) 对齐；
//      只改底色/不改格子（stage 下 cell.* 是运行时实例，几何独立）。
//   F7 保留项：police-v12 背景、棋盘内容、线索卡文本、hud 功能文字均 0 改动（方案默认口径）。
//   F8 网格纸零复制：把 656 首页 art656.home.grid.* 31 层重挂到 1 个新父 art657.grid.reuse
//      （零位移 1600x900，子层坐标不变），按优化轮 652/654 的父级整树门控方案，
//      Lua 只加父级显隐 + 父级坐标两条 ⇒ 同一套网格纸在 home / game 两屏各显现一次。
//   F9 问号帮助按钮：底板 art641.game.help.tab、本体 clues.help617、点击热区
//      clues.help627.hit 三者一起挪到便利贴位置；本体改透明但保留（脚本 help_visible 控制显隐）。
//   F10 右上三键按设计图逐列扫描留出约 10px 黑缝，图标与命中区同步跟随。
//
// 用法：
//   node 构建657_存档.mjs                 # 构建（输出已存在需 FORCE=1）
//   FORCE=1 node 构建657_存档.mjs         # 迭代重建
//   node 构建657_存档.mjs --dry-run       # 只打印计划
//
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '关卡内UI规格_657.json'), 'utf8'));
const INPUT = path.resolve(DIR, '../656_首页设计/656_首页设计.gil');
const OUTPUT = path.join(DIR, '657_关卡内UI.gil');
const BASE_SHA256 = '5b7da8b0e47f593f06e9ec6cd507f0c013566d7a9aa6975f57b1b7cca8d41dc6';
const APPLY = !process.argv.includes('--dry-run');

const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
if (sha(INPUT) !== BASE_SHA256) throw Error('656 基准 SHA256 不符：' + INPUT);
if (APPLY && fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代重建请加 FORCE=1：' + OUTPUT);
if (!APPLY) console.log('[DRY-RUN] 只打印计划，不写存档。\n');

const { readGil, stateBlocks, pairOf, pairValue, setPair, cloneField,
  ensureChildListTop, findChildListTop, asIdList, setChildList, textsOf, encodeMsg } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { writeGil, findScriptLeaf } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { setHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);

const g = readGil(INPUT);
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const byId = new Map(g.recs.map(r => [r.id, r]));
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
// 记录 r 在 1600x900 屏幕上的绝对中心（与离线渲染器同一套父链口径）
function absCenter(r, depth = 0) {
  if (!r || depth > 12) return [800, 450];
  if (centerCache.has(r.id)) return centerCache.get(r.id);
  const st = states(r)[0];
  const p = st && pairOf(st, 504);
  if (!p) return [800, 450];
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId), depth + 1) : [800, 450];
  const res = [px + pairValue(p, 0), py - pairValue(p, 1)];
  centerCache.set(r.id, res);
  return res;
}
// 把「屏幕中心坐标」写成该记录的父相对坐标（root 直属时退化为原 setGeom）
function setGeomScreen(r, cx, cy, w, h) {
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - px, py - cy);
    setPair(pairOf(st, 505), w, h);
  }
  if (!modified.includes(r.name)) modified.push(r.name);
}
function setRot(r, deg) {
  for (const st of states(r)) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }];
    rf.payload = null; rf.len = 5;
  }
  if (!modified.includes(r.name)) modified.push(r.name);
}
function retintRaw(r, value) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块：' + r.name);
  setNum(p, 502, value);
  if (!modified.includes(r.name)) modified.push(r.name);
}
const retint = (r, hex) => retintRaw(r, colorOf(hex));
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}

// ── 克隆新层 ───────────────────────────────────────────────────────────────
const PROTO_IMG = 'td.home.page.1.help619.icon';
const PROTO_TXT = 'td.l1.page.1.heading';
function clone(parent, name, o) {
  const proto = o.text ? byName.get(PROTO_TXT) : (o.proto ? byName.get(o.proto) : byName.get(PROTO_IMG));
  if (!proto) throw Error('缺克隆原型：' + (o.text ? PROTO_TXT : PROTO_IMG));
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
  if (o.before) {
    const ref = byName.get(o.before);
    const idx = recTop.sub.findIndex(q => q === ref?.field);
    if (idx < 0) throw Error('参考记录不在 recTop：' + o.before);
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
  added.push(r);
  byName.set(name, r); byId.set(id, r);
  return r;
}

// ── 1. 现有控件：写入 / 隐藏 ───────────────────────────────────────────────
function byIds(ids) { return ids.map(id => { const r = byId.get(id); if (!r) throw Error('缺 ID ' + id); return r; }); }
function byRange(a, b) { return g.recs.filter(r => r.id >= a && r.id <= b); }
function named(names) { return names.map(n => { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }); }

// 1a 线索卡底板透明（两套 clue 模板），露出新的暗红内页
for (const r of byIds([1073742422, 1073742429, 1073742423, 1073742430])) retintRaw(r, 0x00ffffff);

// 1b 641 旧笔记本 36 层只隐藏不删除（保护 653 分类父与 655 名字索引）
const oldNotebook = byRange(1073754826, 1073754861);
if (oldNotebook.length !== 36) throw Error('641 笔记本层数不符：' + oldNotebook.length);
for (const r of oldNotebook) { setHiddenRecord(r.field, true); hidden.push(r.name); }

// 1c 棋盘纸框 / 内框
const paper = byName.get('art641.game.boardframe.paper');
retint(paper, '#FAEFCC'); setGeomScreen(paper, 904, 409, 646, 732);
const shadow = byName.get('art641.game.boardframe.shadow');
retint(shadow, '#E5D2AA');                       // 深棕投影改淡，设计图只有轻微纸边
const bottom = byName.get('art641.game.boardbottom');
retint(bottom, '#FDFDE7'); setGeomScreen(bottom, 904, 754, 646, 42);
const boardBg = byName.get('board.bg');
retint(boardBg, '#382D3B'); setGeomScreen(boardBg, 903.5, 420, 607, 626);

// 1d 五个旗面（褐色、按设计图加宽/重定位）
const flags = SPEC.geometry.rightButtons;
const flagSpecs = {
  back:   { id: 1073754866, cx: 85,   cy: 157,   w: 116, h: 100 },
  // 设计图逐列扫描三个按钮是 y107-197 / 208-287 / 298-375，彼此有约 10px 黑缝；
  // 规格的 89px 等距会把三块连成一整片，这里按实测留缝并同步图标。
  submit: { id: 1073754867, cx: 1486,  cy: 151.5, w: 172, h: 89 },
  redo:   { id: 1073754868, cx: 1486,  cy: 248,   w: 172, h: 83 },
  undo:   { id: 1073754869, cx: 1486,  cy: 340,   w: 172, h: 83 },
  hint:   { id: 1073754870, cx: 1486,  cy: 731.5, w: 172, h: 77 },
};
for (const [k, s] of Object.entries(flagSpecs)) {
  const r = byId.get(s.id);
  retint(r, '#855244'); setGeomScreen(r, s.cx, s.cy, s.w, s.h);
}

// 1e 问号/注释按钮：底板、按钮本体、点击热区三者一起挪到设计图便利贴位置
const helpTab = byName.get('art641.game.help.tab');
retint(helpTab, '#B0340E'); setGeomScreen(helpTab, 384, 211, 144, 88); setRot(helpTab, -10);
// clues.help617 是脚本 help_visible() 控制显隐的按钮本体（100113 官方小红圈 ?），
// 既不能隐藏、也不能被拉成 144x88；改透明后视觉交给新增白圆+问号，位置仍随便利贴。
const helpBody = byName.get('clues.help617');
retintRaw(helpBody, 0x00ffffff); setGeomScreen(helpBody, 384, 211, 34, 34);
setGeomScreen(byName.get('clues.help627.hit'), 384, 211, 144, 88);   // 点击热区同步

// 1f 图标与命中区跟随新旗面中心（原方案默认不动，图标会留在旧窄条位置）
const iconMoves = {
  'hex.back': [70, 157, 64, 64], 'hit.back': [70, 157, 84, 96],
  'hex.submit': [1486, 151.5, 70, 70], 'hit.submit': [1486, 151.5, 84, 96],
  'hex.redo': [1486, 248, 70, 70], 'hit.redo': [1486, 248, 84, 96],
  'hex.undo': [1486, 340, 70, 70], 'hit.undo': [1486, 340, 84, 96],
  'hex.hint': [1486, 731.5, 70, 70], 'hit.hint': [1486, 731.5, 84, 96],
};
for (const [n, gm] of Object.entries(iconMoves)) setGeomScreen(byName.get(n), ...gm);

// ── 2. 新增层 ─────────────────────────────────────────────────────────────
const GRP = 'grp653.static.1.art641.game';
const grp = byName.get(GRP);
if (!grp) throw Error('缺父容器 ' + GRP);
const L = [];
const push = (name, o) => L.push({ name, parent: GRP, ...o });

// 2a 笔记本：白框 → 暗红内页 → 下段略暗 → 分隔线 → 行首方块 → 活页环
const BF = 'art657.game.notebook.frame';
push(BF, { cx: 209, cy: 513.5, w: 370, h: 515, color: '#FDFAEF' });
push('art657.game.notebook.page', { cx: 223.5, cy: 511, w: 325, h: 468, color: '#68252A' });
// 内页用三段渐进暗化代替一条硬分界（设计图是斜向渐变，纯色只能近似）
push('art657.game.notebook.page.mid', { cx: 223.5, cy: 511, w: 325, h: 156, color: '#652327' });
push('art657.game.notebook.page.lower', { cx: 223.5, cy: 667, w: 325, h: 156, color: '#611F23' });
const ruleY = [368, 463, 559, 654], rowY = [322.5, 415.5, 511, 606.5, 699.5], ringY = [322, 415, 511, 606, 699];
ruleY.forEach((cy, i) => push(`art657.game.notebook.rule.${i + 1}`, { cx: 223.5, cy, w: 325, h: 7, color: '#FDFAF5' }));
rowY.forEach((cy, i) => push(`art657.game.notebook.slot.${i + 1}`, { cx: 88, cy, w: 54, h: 72, color: '#2E1F1A' }));
ringY.forEach((cy, i) => push(`art657.game.notebook.ring.${i + 1}`, { cx: 15, cy, w: 38, h: 9, color: '#6C6962', imageId: 107102 }));
ringY.forEach((cy, i) => push(`art657.game.notebook.ringhole.${i + 1}`, { cx: 30, cy, w: 8, h: 11, color: '#262229', imageId: 100002 }));

// 2c 红色燕尾旗书签：同样复制选关 647 燕尾旗做法（矩形 + 2 个同色 100003 三角）
push('art657.game.notebook.ribbon', { cx: 440, cy: 350, w: 80, h: 60, color: '#B23928' });
push('art657.game.notebook.ribbon.tri.top', { cx: 480, cy: 335, w: 60, h: 30,
  color: '#B23928', imageId: 100003, deg: 180 });
push('art657.game.notebook.ribbon.tri.bottom', { cx: 480, cy: 365, w: 60, h: 30,
  color: '#B23928', imageId: 100003, deg: 0 });

// 2d 问号便利贴：白圆 + 棕色 ?
push('art657.game.sticker.q.dot', { cx: 384, cy: 211, w: 34, h: 34, color: '#FDFAF5', imageId: 100002 });
push('art657.game.sticker.q.mark', { cx: 384, cy: 211, w: 26, h: 40, text: '?', fontSize: 28, color: '#A8320C' });

// 2e 纸框上下两条格纹胶带（设计图 y43-106 / y733-775，正网格，仍用细线）
function grid(prefix, cx, cy, w, h, step, base, line, lineW = 2) {
  push(`${prefix}.base`, { cx, cy, w, h, color: base });
  for (let i = 1; i * step < w; i++) push(`${prefix}.v${i}`, { cx: cx - w / 2 + i * step, cy, w: lineW, h, color: line });
  for (let j = 1; j * step < h; j++) push(`${prefix}.h${j}`, { cx, cy: cy - h / 2 + j * step, w, h: lineW, color: line });
}
grid('art657.game.board.tape.top', 904, 74.5, 646, 63, 26, '#FDFDE7', '#E4D2A8');
grid('art657.game.board.tape.bottom', 904, 754, 646, 42, 26, '#FDFDE7', '#E4D2A8');

// 2f 红色圆形图钉（深色描边 + 红球 + 高光）
push('art657.game.pin.border', { cx: 1320, cy: 340, w: 126, h: 126, color: '#7A1512', imageId: 100002 });
push('art657.game.pin', { cx: 1320, cy: 340, w: 120, h: 120, color: '#AA0400', imageId: 100002 });
push('art657.game.pin.mid', { cx: 1312, cy: 332, w: 84, h: 84, color: '#BE1B12', imageId: 100002 });
push('art657.game.pin.hilite', { cx: 1303, cy: 323, w: 34, h: 22, color: '#D2402C', imageId: 100002 });

// 2g 燕尾旗：直接复制选关界面 647 轮真机验证过的配方
//   art647.select.back.*   （右端燕尾，用于左上返回）
//   art647.select.settle.* （左端燕尾，用于右上三键 / 右下放大镜）
// 配方 = 投影(106057) + 深色描边矩形 + 2 个 100003 等腰三角 + 旗面矩形(现有 flag.*) + 2 个同色三角。
// 三角 w=h、h=h/2，中心落在凹口侧边缘、上下各 h/4；等腰三角左右对称 ⇒ 水平镜像只需换边，rot 不变。
// 描边/投影插在 art641.game.flag.back 之前（先画），同色三角追加在末尾（后画）。
const FLAG_BROWN = '#855244', FLAG_EDGE = '#1E1210', BEFORE_FLAG = 'art641.game.flag.back';
for (const [k, s] of Object.entries(flagSpecs)) {
  const rightEdge = k === 'back';
  const edge = rightEdge ? s.cx + s.w / 2 : s.cx - s.w / 2;
  const OW = s.w + 14, OH = s.h + 12;
  const oEdge = rightEdge ? s.cx + OW / 2 : s.cx - OW / 2;
  const pre = `art657.game.flag.${k}`;
  L.push({ name: `${pre}.shadow`, parent: GRP, before: BEFORE_FLAG,
    cx: s.cx, cy: s.cy + 7.5, w: s.w, h: s.h + 5, colorRaw: 0x66000000, imageId: 106057 });
  L.push({ name: `${pre}.outline`, parent: GRP, before: BEFORE_FLAG,
    cx: s.cx, cy: s.cy, w: OW, h: OH, color: FLAG_EDGE });
  L.push({ name: `${pre}.outline.tri.top`, parent: GRP, before: BEFORE_FLAG,
    cx: oEdge, cy: s.cy - OH / 4, w: OH, h: OH / 2, color: FLAG_EDGE, imageId: 100003, deg: 180 });
  L.push({ name: `${pre}.outline.tri.bottom`, parent: GRP, before: BEFORE_FLAG,
    cx: oEdge, cy: s.cy + OH / 4, w: OH, h: OH / 2, color: FLAG_EDGE, imageId: 100003, deg: 0 });
  push(`${pre}.ribbon.tri.top`, { cx: edge, cy: s.cy - s.h / 4, w: s.h, h: s.h / 2,
    color: FLAG_BROWN, imageId: 100003, deg: 180 });
  push(`${pre}.ribbon.tri.bottom`, { cx: edge, cy: s.cy + s.h / 4, w: s.h, h: s.h / 2,
    color: FLAG_BROWN, imageId: 100003, deg: 0 });
}

console.log(`[layers] 展开 ${L.length} 层；父容器 ${GRP}`);
console.log(`[ops] 现有写入 ${modified.length} 条 / 隐藏 ${hidden.length} 条`);
if (!APPLY) {
  console.log('[dry-run] 前 12 层：');
  for (const o of L.slice(0, 12)) console.log('   ', o.name, `(${o.cx},${o.cy}) ${o.w}x${o.h}`, o.color || o.text || '');
  console.log(`[dry-run] 记录数 ${g.recs.length} -> ${g.recs.length + L.length}；未写盘。`);
  process.exit(0);
}

const modifiedExisting = [...modified];   // clone() 之后 modified 还会追加新层名，这里先留一份「现有控件」口径
const extraParents = new Set();
for (const o of L) clone(grp, o.name, o);

// ── 2i 复用首页网格纸：优化轮 652/654 的「父级整树显隐门控」成熟方案 ──────
// 不复制 31 层：只加 1 个父容器 art657.grid.reuse，把 656 首页 art656.home.grid.*
// （含 paper.edge）整体重挂进去。新旧父都是零位移 1600x900 容器 ⇒ 子层坐标一个都不用改。
// 新父插在 art641.home 之前：首页时最先画，关卡内时仍在 art641.game（棋盘纸框）之前画。
// Lua 只加两条：切屏时给这个父一条显隐门控 + 一条坐标 ⇒ 同一套网格纸在
// home / game 两屏各显现一次，静态叶 0 复制，运行时只多 2 次调用。
const gridLayers = g.recs.filter(r => r.name &&
  (/^art656\.home\.grid\./.test(r.name) || r.name === 'art656.home.paper.edge'));
// 1 paper + 24 竖线 + 4 横线 + 1 paper.edge = 30 层
if (gridLayers.length !== 30) throw Error('首页网格纸层数不符：' + gridLayers.length);
const oldParent = byName.get('grp653.static.1.art641.home');
const gridParent = clone(byName.get('root'), 'art657.grid.reuse', {
  proto: 'art641.game', before: 'art641.home', cx: 800, cy: 450, w: 1600, h: 900,
});
for (const r of gridLayers) {
  const top = r.field.sub;
  const p = top.find(q => q.field === 504 && q.wt === 0);
  if (p) p.num = BigInt(gridParent.id);
  else top.push({ field: 504, wt: 0, num: BigInt(gridParent.id) });
  r.parentId = gridParent.id;
  if (!modified.includes(r.name)) modified.push(r.name);
}
const oldCl = ensureChildListTop(oldParent);
const moved = new Set(gridLayers.map(r => r.id));
setChildList(oldCl, (asIdList(oldCl.payload, true) || []).filter(id => !moved.has(id)));
setChildList(ensureChildListTop(gridParent), gridLayers.map(r => r.id));
extraParents.add(oldParent.id); extraParents.add(gridParent.id);

// Lua 补丁：在 sync_art641() 的切屏分支末尾加「父级显隐 + 父级坐标」两条
const scriptLeaf = findScriptLeaf(g);
const s0 = scriptLeaf.buf.toString('utf8');
const ANCHOR = '    art641_screen = screen\n  end\nend';
if (s0.split(ANCHOR).length !== 2) throw Error('sync_art641 锚点不唯一');
const PATCH_TO = `    art641_screen = screen
    do
      local gp = adapter:find("art657.grid.reuse")
      if gp ~= nil then
        help_visible(gp, screen == "home" or screen == "game")
        local dx, dy = 0, 0
        if screen == "game" then dx, dy = 105, 46 end
        pcall(function() gp:SetAnchoredPosition(dx, dy) end)
      end
    end
  end
end`;
const scriptBuf = Buffer.from(s0.replace(ANCHOR, PATCH_TO), 'utf8');
scriptLeaf.field.payload = scriptBuf;
scriptLeaf.field.len = scriptBuf.length;
scriptLeaf.field.sub = null;
fs.writeFileSync(path.join(DIR, '657_关卡内UI.lua'), scriptBuf);

// ── 3. childList 与全局记录表同序 ──────────────────────────────────────────
const fieldIndex = new Map();
recTop.sub.forEach((f, i) => fieldIndex.set(f, i));
const touched = new Set([...added.map(r => r.parentId), ...extraParents]);
for (const pid of touched) {
  const parent = byId.get(pid);
  if (!parent) throw Error('父记录丢失 ' + pid);
  const cl = ensureChildListTop(parent);
  const orig = asIdList(cl.payload, true) || [];
  const ids = [...new Set([...orig, ...added.filter(r => r.parentId === pid).map(r => r.id)])];
  ids.sort((a, b) => (fieldIndex.get(byId.get(a)?.field) ?? 1e9) - (fieldIndex.get(byId.get(b)?.field) ?? 1e9));
  setChildList(cl, ids);
  if (!modified.includes(parent.name)) modified.push(parent.name);
}

// ── 4. 断言 + 唯一安全落盘通道 ────────────────────────────────────────────
const police = byName.get('police-v12');
const bgIds = new Set([police.id, ...g.recs.filter(r => r.parentId === police.id).map(r => r.id)]);
const protectedNames = /^(stage|board\.floors|board\.rugs|cell\.|clue$|letter$|what$|who$|face$|gray$|gen\.|hud\.|row\.|hex\.ok|hex\.no|hit\.ok|hit\.no)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protectedNames.test(r.name)).map(r => r.id)]);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '657 game-screen UI merged onto 656',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBuf)) return '内嵌 Lua 与补丁后期望不符';
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 ' + r.name;
      if (protectedIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '受保护记录被改动 ' + r.name;
    }
    const ids = new Set(t.recs.map(r => r.id));
    // 656 基准里本来就有 36 条「根级模板」的父 ID 指向模板容器（不在 recs 里），
    // 这是存档既有结构，不能算本轮新增的悬空引用；只要求「不新增悬空」。
    const baseIds = new Set(g.recs.map(r => r.id));
    const danglingBefore = new Set(g.recs.filter(r => r.parentId != null && !baseIds.has(r.parentId)).map(r => r.id));
    for (const r of t.recs)
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
    for (const r of added) if (!ids.has(r.id) || !ids.has(r.parentId)) return '新增层父引用异常 ' + r.name;
    for (const n of ['stage', 'board.floors', 'board.rugs', 'clues.grid', 'police-v12', 'root', 'home'])
      if (!t.recs.some(r => r.name === n)) return '功能控件丢失 ' + n;
    return true;
  },
});

const audit = {
  version: 1, name: '657 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '../656_首页设计/656_首页设计.gil', sha256: BASE_SHA256, records: 6421, scriptBytes: scriptBefore.length },
  script: { bytesBefore: scriptBefore.length, bytesAfter: scriptBuf.length,
    patch: 'sync_art641() 切屏分支末尾加父级显隐 help_visible + 父级坐标 SetAnchoredPosition(105,46)，反向替换即与 656 逐字节相同',
    compileCheck: '见 657_构建报告.md（Lua 5.4 loadfile）' },
  output: { file: '657_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  source: { github: 'fangao1437/qianxing-murdoku@8ff4f9d7 的 657_关卡内UI 方案（SPEC_ONLY）', spec: '关卡内UI规格_657.json' },
  fixes: {
    F1: 'setGeomScreen 按父链真实中心换算屏幕坐标（clues/stage 有非零偏移）',
    F2: '新增层统一挂 grp653.static.1.art641.game；recTop 与 childList 按索引同序重排；描边插在旗面之前',
    F3: 'clues.bg 保持透明；暗红内页由独立新层承担；backrop1/2 用 0x00FFFFFF',
    F4: 'hex.*/hit.* 图标与热区同步移到新旗面中心',
    F5: '燕尾旗按钮直接复制选关界面 647 轮真机配方（art647.select.back/settle：矩形 + 2 个 100003 三角 + 深色描边 + 106057 投影）；图钉补描边与渐变；便利贴修正到 (384,211) 144x88 rot -10',
    F6: 'board.bg 几何按设计图对齐到 (903.5,420,607,626)，只改底板不动格子',
    F7: 'police-v12 背景 / 棋盘内容 / 线索卡文本 / hud 功能文字 0 改动',
    F8: '网格纸零复制：复用 656 首页 art656.home.grid.* 31 层，整体重挂到 1 个新父 art657.grid.reuse（零位移容器，子层坐标不变）；按 652/654 父级整树门控方案，Lua 只加父级显隐 + 父级坐标两条，让同一套网格纸在 home / game 两屏各显现一次',
    F9: '问号帮助按钮底板 art641.game.help.tab + 本体 clues.help617 + 点击热区 clues.help627.hit 一起挪到便利贴位置；本体改透明保留（脚本 help_visible 控制显隐）',
    F10: '右上三键按设计图逐列扫描留约 10px 黑缝，图标 hex.* 与命中区 hit.* 同步跟随',
  },
  counts: { recordsBefore: 6421, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modifiedExisting: modifiedExisting.length },
  modifiedExisting, hidden,
  addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  backgroundUntouched: `police-v12 + ${bgIds.size - 1} 个直接子控件`,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '657_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: added.length, hidden: hidden.length, modified: modified.length,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
