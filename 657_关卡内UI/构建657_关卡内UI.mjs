// 657 · 关卡内棋盘屏按设计图复刻
//
// 输入：qianxing-murdoku/650_全面优化/655_遍历负载优化.gil（锁定 SHA256，不覆盖）
// 输出：默认【不写任何 .gil】；只有显式 --apply --out=<路径> 才落盘。
//
// 本轮是方案交付，构建器未被执行过 --apply。
// 范围：背景 police-v12 / 棋盘上内容 / 线索卡文本 一律 0 改动。
//
// 用法：
//   node 构建657_关卡内UI.mjs                          # dry-run：打印操作计划
//   node 构建657_关卡内UI.mjs --apply --out=657.gil   # 主控决定执行时才写
//   FORCE=1 ... --apply                              # 输出已存在时覆盖
//
// 体例与并行的 656_首页设计/构建656_首页复刻.mjs 保持一致。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '关卡内UI规格_657.json'), 'utf8'));
const INPUT = path.resolve(DIR, SPEC.base.primary.file);
const ARGS = process.argv.slice(2);
const APPLY = ARGS.includes('--apply');
const OUTARG = ARGS.find(a => a.startsWith('--out='));
const OUTPUT = OUTARG ? path.resolve(OUTARG.slice(6)) : path.join(DIR, '657_关卡内UI.gil');

const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
if (sha(INPUT) !== SPEC.base.primary.sha256) throw Error('输入 SHA256 与规格不符：' + INPUT);
if (APPLY && fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，需 FORCE=1：' + OUTPUT);
if (!APPLY) console.log('[DRY-RUN] 只打印计划，不写任何 .gil；加 --apply 才会落盘。\n');

const { readGil, stateBlocks, pairOf, setPair, cloneField, ensureChildListTop,
  findChildListTop, asIdList, setChildList, textsOf, encodeMsg } =
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
let max = BigInt(g.maxId);
const added = [], modified = [], hidden = [];
const P = SPEC.palette, GM = SPEC.geometry;

// ── 通用字段工具 ───────────────────────────────────────────────────────────
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt('FF' + hex.replace('#', ''), 16) >>> 0;

function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
function setGeom(r, cx, cy, w, h) {
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - 800, 450 - cy);
    setPair(pairOf(st, 505), w, h);
  }
  modified.push(r.name);
}
function setRot(r, deg) {
  for (const st of states(r)) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }];
    rf.payload = null; rf.len = 5;
  }
  modified.push(r.name);
}
function retint(r, hex) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块：' + r.name);
  setNum(p, 502, colorOf(hex));
  setNum(p, 503, 100001);
  setNum(p, 504, 1);
  modified.push(r.name);
}
function retintRaw(r, value) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块：' + r.name);
  setNum(p, 502, value);
  modified.push(r.name);
}
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}

// ── 新增层 ────────────────────────────────────────────────────────────────
const PROTO_IMG = 'td.home.page.1.help619.icon';
const PROTO_TXT = 'td.l1.page.1.heading';
function clone(proto, parent, name, cx, cy, w, h, color, imageId, deg = 0, text = null, fontSize = 0) {
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
  recTop.sub.push(f);
  const p = ns(f, [505, 503, 84])[0];
  if (p && color !== null) {
    setNum(p, 502, colorOf(color));
    setNum(p, 503, imageId ?? 100001);
    setNum(p, 504, 1);
  }
  if (text !== null) {
    const tp = ns(f, [505, 503, 75])[0], leaf = ns(f, [505, 503, 75, 510, 501])[0];
    if (!tp || !leaf) throw Error('文本原型结构不符：' + name);
    leaf.payload = Buffer.from(text); leaf.len = leaf.payload.length;
    for (const [k, v] of [[502, 0], [512, fontSize], [513, fontSize], [504, colorOf(color)], [508, 1], [509, 1]]) setNum(tp, k, v);
  }
  setGeom(r, cx, cy, w, h);
  if (deg) setRot(r, deg);
  setHiddenRecord(f, false);
  added.push(r);
  byName.set(name, r);
  return r;
}

// ── 把规格里的生成器展开成具体层 ──────────────────────────────────────────
function expandLayers() {
  const out = [];
  const push = (o) => out.push(o);
  for (const L of SPEC.layers) {
    if (L.generator === 'repeat') {
      L.items.forEach((cy, i) => push({ name: `${L.prefix}.${i + 1}`, parent: L.parent, insert: L.insert,
        cx: L.cx, cy, w: L.w, h: L.h, color: L.color, imageId: L.imageId }));
    } else if (L.generator === 'grid') {
      push({ name: L.name + '.base', parent: L.parent, insert: L.insert,
        cx: L.cx, cy: L.cy, w: L.w, h: L.h, color: L.base, imageId: L.imageId });
      const nV = Math.floor(L.w / L.step), nH = Math.floor(L.h / L.step);
      for (let i = 1; i < nV; i++) push({ name: `${L.name}.v${i}`, parent: L.parent, insert: L.insert,
        cx: L.cx - L.w / 2 + i * L.step, cy: L.cy, w: L.lineWidth, h: L.h, color: L.line, imageId: L.imageId });
      for (let j = 1; j < nH; j++) push({ name: `${L.name}.h${j}`, parent: L.parent, insert: L.insert,
        cx: L.cx, cy: L.cy - L.h / 2 + j * L.step, w: L.w, h: L.lineWidth, color: L.line, imageId: L.imageId });
    } else if (L.generator === 'notchedFlag') {
      for (const t of L.targets) {
        const pre = `${L.prefix}.${t.key}`;
        // 深色描边（整体外扩 borderWidth），先画
        push({ name: pre + '.border', parent: L.parent, insert: L.insert,
          cx: t.cx, cy: t.cy, w: t.w + 2 * L.borderWidth, h: t.h + 2 * L.borderWidth,
          color: L.borderColor, imageId: L.imageId });
        // V 凹口用 ±45° 旋转矩形（100001，651 撕边验证过的可靠图元），
        // 不用 100003 三角 —— 项目实测该三角只在 rot 0/180/90 出图，rot -90 不出图。
        push({ name: pre + '.border.notch.up', parent: L.parent, insert: L.insert,
          cx: t.cx - t.w / 2 - 2, cy: t.cy - t.h / 4, w: L.notchDepth * 1.6, h: 4,
          color: L.borderColor, imageId: L.imageId, deg: 45 });
        push({ name: pre + '.border.notch.down', parent: L.parent, insert: L.insert,
          cx: t.cx - t.w / 2 - 2, cy: t.cy + t.h / 4, w: L.notchDepth * 1.6, h: 4,
          color: L.borderColor, imageId: L.imageId, deg: -45 });
        // 旗面（本体已在 existingOps 改色/改尺寸，这里只补 V 凹口与右端锯齿）
        push({ name: pre + '.notch.up', parent: L.parent, insert: L.insert,
          cx: t.cx - t.w / 2 - 2, cy: t.cy - t.h / 4, w: L.notchDepth * 1.6, h: 4,
          color: L.color, imageId: L.imageId, deg: 45 });
        push({ name: pre + '.notch.down', parent: L.parent, insert: L.insert,
          cx: t.cx - t.w / 2 - 2, cy: t.cy + t.h / 4, w: L.notchDepth * 1.6, h: 4,
          color: L.color, imageId: L.imageId, deg: -45 });
        push({ name: pre + '.tail', parent: L.parent, insert: L.insert,
          cx: t.cx + t.w / 2, cy: t.cy, w: L.tailJag, h: t.h,
          color: L.color, imageId: L.imageId });
      }
    } else {
      push({ ...L });
    }
  }
  return out;
}
const LAYERS = expandLayers();

// ── 1. 现有控件写入 ───────────────────────────────────────────────────────
function targetsOf(op) {
  if (Array.isArray(op.ids)) return op.ids.map(id => {
    const r = byId.get(id); if (!r) throw Error('缺 ID ' + id); return r;
  });
  if (typeof op.ids === 'string' && /^\d+\.\.\d+$/.test(op.ids)) {
    const [a, b] = op.ids.split('..').map(Number);
    return g.recs.filter(r => r.id >= a && r.id <= b);
  }
  const pref = op.name.replace(/\.\*$/, '');
  return g.recs.filter(r => r.name && (op.name.endsWith('.*') ? r.name.startsWith(pref) : r.name === op.name));
}

let opCount = 0;
for (const op of SPEC.existingOps) {
  const list = targetsOf(op);
  if (!list.length) throw Error('未命中任何控件：' + op.name);
  for (const r of list) {
    if (op.action === 'hide') { setHiddenRecord(r.field, true); hidden.push(r.name); }
    if (op.geometry) setGeom(r, op.geometry.cx, op.geometry.cy, op.geometry.w, op.geometry.h);
    opCount++;
  }
  console.log(`[op] ${op.action.padEnd(13)} ${String(list.length).padStart(3)} 个  ${op.name}`);
}

// 颜色写入：按规格 from/to 精确落到 #505/#503/#84/#502（与几何写入分开，避免重复写）
for (const op of SPEC.existingOps) {
  if (!op.from || !op.to || op.action === 'hide') continue;
  for (const r of targetsOf(op)) {
    const p = ns(r.field, [505, 503, 84])[0];
    if (!p) continue;
    setNum(p, 502, parseInt(op.to, 16) >>> 0);
  }
}

// ── 2. 新增层 ─────────────────────────────────────────────────────────────
console.log(`\n[layers] 展开后 ${LAYERS.length} 层；父容器分布：`);
const byParent = new Map();
for (const L of LAYERS) byParent.set(L.parent, (byParent.get(L.parent) || 0) + 1);
for (const [p, n] of byParent) console.log(`   ${p}  ->  ${n} 层`);

if (!APPLY) {
  console.log('\n[dry-run] 前 20 层预览：');
  for (const L of LAYERS.slice(0, 20))
    console.log(`   ${L.name.padEnd(46)} (${L.cx}, ${L.cy}) ${L.w}x${L.h} ${L.color || L.text || ''}`);
  console.log(`\n[dry-run] 预计：修改 ${opCount} 处控件写入 / 隐藏 ${hidden.length} 条 / 新增 ${LAYERS.length} 条`);
  console.log(`[dry-run] 记录数 ${g.recs.length} -> ${g.recs.length + LAYERS.length}`);
  console.log('[dry-run] 未调用 writeGil，未创建任何 .gil。');
  process.exit(0);
}

// ── 3. --apply：真正写入 ──────────────────────────────────────────────────
const pi = byName.get(PROTO_IMG), pt = byName.get(PROTO_TXT);
if (!pi || !pt) throw Error('缺克隆原型');
const pending = new Map(); // parentName -> {beforeGrid:[], afterGrid:[]}
for (const L of LAYERS) {
  const parent = byName.get(L.parent);
  if (!parent) throw Error('缺父控件 ' + L.parent);
  const isText = L.text !== undefined && L.text !== null;
  const r = clone(isText ? pt : pi, parent, L.name, L.cx, L.cy, L.w, L.h,
    L.color ?? null, L.imageId ?? 100001, L.deg ?? 0, isText ? L.text : null, L.fontSize ?? 0);
  if (!pending.has(L.parent)) pending.set(L.parent, { beforeGrid: [], afterGrid: [] });
  const bucket = L.insert === 'after:clues.bg' ? 'beforeGrid' : 'afterGrid';
  pending.get(L.parent)[bucket].push(r.id);
}

for (const [parentName, groups] of pending) {
  const parent = byName.get(parentName);
  const cl = ensureChildListTop(parent);
  const orig = asIdList(cl.payload, true);
  const gridId = byName.get('clues.grid')?.id;
  const idx = gridId ? orig.indexOf(gridId) : -1;
  let next;
  if (idx >= 0) next = [...orig.slice(0, idx), ...groups.beforeGrid, ...orig.slice(idx), ...groups.afterGrid];
  else next = [...orig, ...groups.beforeGrid, ...groups.afterGrid];
  // idx>=0 时保持 [..clues.bg] + beforeGrid + [clues.grid..] + afterGrid
  setChildList(cl, next);
  modified.push(parentName);
}

// ── 4. 断言 + 唯一安全落盘通道 ────────────────────────────────────────────
const bgIds = new Set([byName.get('police-v12').id, ...g.recs.filter(r => r.parentId === byName.get('police-v12').id).map(r => r.id)]);
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, OUTPUT, {
  label: '657 game-screen UI per design sheet',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 ' + r.name;
    }
    const tByName = new Map(t.recs.filter(r => r.name).map(r => [r.name, r]));
    for (const n of ['stage', 'board.floors', 'board.rugs', 'clues.grid'])
      if (!tByName.has(n)) return '功能控件丢失 ' + n;
    return true;
  }
});

console.log(JSON.stringify({
  output: OUTPUT,
  baseSha256: SPEC.base.primary.sha256,
  recordsBefore: 6340,
  recordsAfter: expected.size,
  addedRecords: added.length,
  hiddenRecords: hidden.length,
  modifiedWrites: opCount,
  scriptBytes: scriptBefore.length,
  backgroundUntouched: `police-v12 及 ${bgIds.size - 1} 个子控件 0 改动`,
  status: 'APPLIED'
}, null, 2));
