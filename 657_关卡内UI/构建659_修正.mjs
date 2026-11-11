// 659 · 裁剪失效回退 + 三键等距 + 线索区背景按设计图重做
//
// 输入：658_关卡内UI.gil（锁 SHA256，不覆盖）
// 输出：659_关卡内UI.gil + 659_构建审计.json
//
// 用户实机反馈：
//  1 裁剪没生效 → 真机上父级矩形裁剪对新建 clip 容器/模板实例子层不生效，旋转矩形溢出成碎片。
//    回退到用户上轮给的备选方案：只用**完全不溢出的矩形 + 三角形**拼近似渐变，
//    隐藏所有 clip 容器与旋转矩形渐变层。
//  2 右侧三键间隔不均匀（658 中心 152 / 247.5 / 336.5，间距 95.5 / 89）→ 改成等距 95：
//     152 / 247 / 342；**flag.* 六层 + 旗面 + hex.* 图标 + hit.* 点击区全部同步挪**。
//  3 线索区背景与设计图差异明显 → 根因是格纹纸挂 clues 组，被 clues 自身 365x490 矩形裁掉。
//    改挂 grp653.static.1.art641.game（1600x900、不裁剪，且绘制早于 clues 卡片），
//    并按设计图逐行扫描重定位：上 x60-478/y200-240、右 x443-477/y230-790、下 x100-430/y780-820。
//
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const INPUT = path.join(DIR, '658_关卡内UI.gil');
const OUTPUT = path.join(DIR, '659_关卡内UI.gil');
const BASE_SHA256 = 'ec077aa61702599e66da10991b05cf14904e1ffa3c8137e4346501018417009e';
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
if (sha(INPUT) !== BASE_SHA256) throw Error('658 基准 SHA256 不符：' + INPUT);
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
function touch(r) { if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function setGeomScreen(r, cx, cy, w, h) {
  const [px, py] = r.parentId ? absCenter(byId.get(r.parentId)) : [800, 450];
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - px, py - cy);
    setPair(pairOf(st, 505), w, h);
  }
  touch(r);
}
function shiftY(r, dy) {
  for (const st of states(r)) {
    const p = pairOf(st, 504);
    setPair(p, pairValue(p, 0), pairValue(p, 1) - dy);   // 存档 y 向上：屏幕下移 dy ⇒ 记录 y 减 dy
  }
  touch(r);
}
function retintRaw(r, v) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, v); touch(r);
}
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
const PROTO_IMG = 'td.home.page.1.help619.icon';
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
  const cl = findChildListTop(f.sub);
  if (cl) setChildList(cl, []);
  const r = { id, name, parentId: parent?.id ?? null, field: f };
  if (o.before || o.beforeId !== undefined) {
    const ref = o.beforeId !== undefined ? byId.get(o.beforeId) : byName.get(o.before);
    const idx = recTop.sub.findIndex(q => q === ref?.field);
    if (idx < 0) throw Error('参考记录不在 recTop ' + (o.before || o.beforeId));
    recTop.sub.splice(idx, 0, f);
  } else recTop.sub.push(f);
  const p = ns(f, [505, 503, 84])[0];
  if (p && o.color) { setNum(p, 502, colorOf(o.color)); setNum(p, 503, o.imageId ?? 100001); setNum(p, 504, 1); }
  setGeomScreen(r, o.cx, o.cy, o.w, o.h);
  setHiddenRecord(f, false);
  added.push(r); byName.set(name, r); byId.set(id, r);
  return r;
}
const push = (parent, name, o) => clone(parent, name, o);
function hide(r) { setHiddenRecord(r.field, true); hidden.push(r.name); touch(r); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }
const GRP = named('grp653.static.1.art641.game');

// ── 1. 裁剪失效：隐藏全部 clip 容器与旋转矩形渐变层 ────────────────────────
const bad = g.recs.filter(r => r.name && (
  /^art658\..*\.clip$/.test(r.name) ||      // 2 个裁剪容器
  /^art658\..*\.g\d+$/.test(r.name) ||      // 便利贴/红缎带的旋转渐变
  /^art658\.clue[12]\.grad\d+$/.test(r.name) || // 两套模板的旋转渐变
  /^art658\.help\.tab\.jag\./.test(r.name) ||   // 便利贴锯齿碎片
  /^art658\.clues\.grid\./.test(r.name)         // 被 clues 父矩形裁掉的格纹带
));
for (const r of bad) hide(r);
// 保留：clue*.bg 底色、clue*.rule 白线、clues.binding/dash、clues.page.edge、help.tab 票券底、ribbon 燕尾

// ── 2. 右侧三键等距 95px：152 / 247 / 342，六层+旗面+图标+点击区全同步 ─────
const shifts = { submit: 0, redo: -0.5, undo: +5.5 };
for (const [k, dy] of Object.entries(shifts)) {
  if (dy === 0 && k === 'submit') continue;
  for (const suffix of ['', '.shadow', '.outline', '.outline.tri.top', '.outline.tri.bottom',
    '.ribbon.tri.top', '.ribbon.tri.bottom']) {
    const n = suffix ? `art657.game.flag.${k}${suffix}` : `art641.game.flag.${k}`;
    shiftY(named(n), dy);
  }
  shiftY(named('hex.' + k), dy);   // 图标
  shiftY(named('hit.' + k), dy);   // ★ 点击区，用户特别要求不要漏
}

// ── 3. 线索区背景：格纹纸改挂 GRP（不裁剪、绘制早于 clues 卡片） ────────────
const BF = 'art657.game.notebook.frame';   // 插在白框之前 ⇒ 白框压住中央，只露四周
const GRID = '#FCFEF1', LINE = '#E4D2A8', DASH = '#E2AE3C';
// 上带 x60-478 / y200-240
push(GRP, 'art659.clues.grid.top.base', { cx: 269, cy: 220, w: 418, h: 40, color: GRID, before: BF });
for (let i = 1; i * 26 < 418; i++)
  push(GRP, `art659.clues.grid.top.v${i}`, { cx: 269 - 209 + i * 26, cy: 220, w: 2, h: 40, color: LINE, before: BF });
push(GRP, 'art659.clues.grid.top.h', { cx: 269, cy: 220, w: 418, h: 2, color: LINE, before: BF });
for (let i = 0; i < 12; i++)
  push(GRP, `art659.clues.grid.top.dash${i + 1}`, { cx: 65 + i * 34, cy: 234, w: 16, h: 3, color: DASH, before: BF });
// 右带 x443-477 / y230-790
push(GRP, 'art659.clues.grid.right.base', { cx: 460, cy: 510, w: 34, h: 560, color: GRID, before: BF });
for (let j = 1; j * 26 < 560; j++)
  push(GRP, `art659.clues.grid.right.h${j}`, { cx: 460, cy: 510 - 280 + j * 26, w: 34, h: 2, color: LINE, before: BF });
push(GRP, 'art659.clues.grid.right.v', { cx: 460, cy: 510, w: 2, h: 560, color: LINE, before: BF });
for (let i = 0; i < 12; i++)
  push(GRP, `art659.clues.grid.right.dash${i + 1}`, { cx: 460, cy: 245 + i * 45, w: 3, h: 16, color: DASH, before: BF });
// 下带 x100-430 / y780-820
push(GRP, 'art659.clues.grid.bottom.base', { cx: 265, cy: 800, w: 330, h: 40, color: GRID, before: BF });
for (let i = 1; i * 26 < 330; i++)
  push(GRP, `art659.clues.grid.bottom.v${i}`, { cx: 265 - 165 + i * 26, cy: 800, w: 2, h: 40, color: LINE, before: BF });
for (let i = 0; i < 9; i++)
  push(GRP, `art659.clues.grid.bottom.dash${i + 1}`, { cx: 110 + i * 34, cy: 800, w: 16, h: 3, color: DASH, before: BF });

// ── 4. 回退方案：完全不溢出的矩形台阶拼「左上亮红三角 + 多色渐变」 ──────────
// 卡片模板 330x85.4，中心 (800,450)；台阶全部落在模板矩形内，不依赖任何裁剪。
const TPL = [[1073742421, 'art659.clue1'], [1073742428, 'art659.clue2']];
for (const [tid, pre] of TPL) {
  const tpl = byId.get(tid);
  // 插在 658 的 .rule 白线之前 ⇒ 白线最后画，不被渐变盖住
  const rule = g.recs.find(r => r.name === `${pre.replace('art659', 'art658')}.rule`);
  if (!rule) throw Error('缺 658 模板白线 ' + pre);
  // 中调过渡带（先画）
  push(tpl, `${pre}.mid`, { cx: 800 + 20, cy: 450, w: 150, h: 85.4,
    color: '#68282A', beforeId: rule.id });
  // 左上亮红三角：6 段顶对齐矩形，高度线性递减 → 斜边阶梯近似（零溢出）
  for (let i = 0; i < 6; i++) {
    const h = 85.4 - i * 14.2, w = 13.5;
    push(tpl, `${pre}.hi${i + 1}`, {
      cx: 800 - 165 + (i + 0.5) * w, cy: 450 - (42.7 - h / 2),
      w, h, color: '#9D3033', beforeId: rule.id,
    });
  }
  // 右下暗部斜纹：3 段底对齐矩形，高度线性递增（最后画，不被 mid 盖住）
  for (let i = 0; i < 3; i++) {
    const h = 18 + i * 16, w = 42;
    push(tpl, `${pre}.lo${i + 1}`, {
      cx: 800 + 60 + i * w, cy: 450 + (42.7 - h / 2),
      w, h, color: '#611F23', beforeId: rule.id,
    });
  }
}
// 便利贴：3 段垂直色带（144x88 内，零溢出）
const tabCols = ['#C04712', '#A0300C', '#7A2109'];
tabCols.forEach((c, i) => push(GRP, `art659.help.tab.band${i + 1}`, {
  cx: 384 - 48 + i * 48, cy: 211, w: 48, h: 88, color: c,
  before: 'art658.help.tab.clip',   // 插在被隐藏的 clip 之前，仍会在票券底之后
}));
// 红缎带：3 段水平色带（80x60 内，零溢出）
const ribCols = ['#D2532F', '#B23928', '#8A241C'];
ribCols.forEach((c, i) => push(GRP, `art659.ribbon.band${i + 1}`, {
  cx: 440, cy: 350 - 20 + i * 20, w: 80, h: 20, color: c,
  before: 'art658.ribbon.clip',
}));

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

// ── 断言 + 落盘 ───────────────────────────────────────────────────────────
const police = byName.get('police-v12');
const bgIds = new Set([police.id, ...g.recs.filter(r => r.parentId === police.id).map(r => r.id)]);
const protect = /^(stage|board\.floors|board\.rugs|cell\.|clue$|letter$|what$|who$|face$|gray$|gen\.|hud\.|row\.|hex\.ok|hex\.no|hit\.ok|hit\.no)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protect.test(r.name)).map(r => r.id)]);
protectedIds.delete(1073742421); protectedIds.delete(1073742428);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '659 clip-fallback / even gaps / clue background',
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
    return true;
  },
});
const audit = {
  version: 1, name: '659 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '658_关卡内UI.gil', sha256: BASE_SHA256, records: 6639, scriptBytes: scriptBefore.length },
  output: { file: '659_关卡内UI.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  findings: {
    clipFailed: '真机确认父级矩形裁剪对新建 clip 容器/模板实例子层不生效，旋转矩形溢出成碎片；已隐藏所有 clip/g/grad/jag/clues.grid 层，改用完全不溢出的矩形台阶 + 色带（用户上轮给的备选方案）。',
    evenGaps: '右侧三键中心 152/247.5/336.5（间距 95.5/89）→ 152/247/342（等距 95）；flag 六层 + 旗面 + hex 图标 + hit 点击区全部同步。',
    clueBackground: '格纹纸原挂 clues 组，被 clues 自身 365x490 矩形裁掉 ⇒ 实机看不到。改挂 grp653.static.1.art641.game（1600x900 不裁剪、绘制早于卡片），按设计图扫描重定位上 x60-478/y200-240、右 x443-477/y230-790、下 x100-430/y780-820。',
  },
  counts: { recordsBefore: 6639, recordsAfter: expected.size,
    added: added.length, hidden: hidden.length, modified: modified.length },
  modified, hidden, addedLayers: added.map(r => ({ id: r.id, name: r.name })),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '659_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: 6639, recordsAfter: expected.size,
  added: added.length, hidden: hidden.length, modified: modified.length,
  scriptBytes: scriptBefore.length, status: 'APPLIED',
}, null, 2));
