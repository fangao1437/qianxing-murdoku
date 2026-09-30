// tools/gil/sync_plan.mjs —— **按布局计划把缺失的控件补进 .gil**
//
// 为什么要有它：
//   美术改造的 ②③⑤⑥ 都要"往 .gil 里加新控件"（线索卡的标红子控件、滚动列表、
//   右侧按钮、家具图标…）。每次手写一个一次性脚本既慢又容易漏掉那串必须遵守的坑。
//   这个工具把"加控件"这件事**标准化**：
//     · 从 `tools/sim/out/layout-plan.json`（`lua tools/dump_layout.lua` 生成）读要有什么
//     · 和现有 .gil 对比，**只补缺的**，已有的一律不动（尊重你在编辑器里调的位置）
//
// ★ 必须遵守的坑（本会话踩了一整天才摸清，这里逐条落实）：
//   1. 新记录写进 **`g.recHolder`**（本工程是子消息 `/#9`），**不是 `g.tree`**
//      —— 写错地方编辑器根本读不到，导入后记录全没；写顶层还会让文件导不进去。
//   2. 容器必须克隆**真正的容器原型**（`#505/#78`），克隆按钮（`#80`）会被编辑器忽略。
//   3. 父级要**同时**改记录里的 `#504` **和**父控件的子列表 —— 只改一边编辑器看不到。
//   4. 子列表只在**顶层**找/建（`findChildListTop`/`ensureChildListTop`），
//      且新建时插在 `#502` 之后（与 `board` 同构）。
//   5. 坐标用 `setPair` 的**稀疏编码**（0 分量不写），与引擎一致。
//
// 用法：
//   node tools/gil/sync_plan.mjs --gil=38.gil --out=完整界面40.gil [--dry]
//     --dry   只看会补哪些，不写文件

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, stateBlocks, pairOf, setPair,
  findChildListTop, ensureChildListTop, setChildList, asIdList,
} from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const DRY = argv.includes('--dry');
const GIL = argOf('gil') || path.join(ROOT, '38.gil');
const OUT = argOf('out') || path.join(ROOT, '完整界面40-计划同步.gil');
const PLAN = argOf('plan') || path.join(ROOT, 'tools/sim/out/layout-plan.json');

const g = readGil(GIL);
const plan = JSON.parse(fs.readFileSync(PLAN, 'utf8'));
const byId = new Map(g.recs.map((r) => [r.id, r]));
const byName = g.byName;

// ── 选原型：容器用容器、其它用按钮/文本 ────────────────────────────────────
const protoBox = g.byName.get('intro') || g.byName.get('modal') || g.byName.get('board');
const protoBtn = g.byName.get('action.undo') || g.byName.get('action.hint');
const protoText = g.byName.get('modal.title') || g.byName.get('hud.title') || g.byName.get('intro.title');
if (!protoBox || !protoBtn) { console.error('❌ 找不到原型（需要 intro/modal/board 与 action.undo/action.hint）'); process.exit(3); }

// ── 克隆（字段深拷贝 + 重写 ID / 父级 / 名字）──────────────────────────────
let nextId = g.maxId + 1;
function deepField(f) {
  const c = { field: f.field, wt: f.wt, sub: null, num: f.num, len: f.len, isText: f.isText,
              payload: f.payload ? Buffer.from(f.payload) : Buffer.alloc(0) };
  if (f.sub) c.sub = f.sub.map(deepField);
  return c;
}
function walkFields(fs, fn) { for (const f of fs) { fn(f); if (f.sub) walkFields(f.sub, fn); } }

function setName(fs, text) {
  const buf = Buffer.from(text, 'utf8');
  let done = false;
  // ⚠️ 名字埋在 `#505 / #12 / #501`（`#505` 在一条记录里出现**很多次**：
  //    名字、位置、尺寸、状态各一个；只有带 `#12` 的那个才是名字）。
  //    我第一版递归进 `#12` 时把"正在找名字"的记号重置成了 false ⇒ **永远找不到** ⇒
  //    新记录全部沿用了原型的名字（回读时才报"回读不到 clue.1.who"）。
  //    ⇒ 记号要**一路带下去**，只有碰到 `#501` 且是文本字段时才落笔。
  (function visit(list, inName) {
    for (const f of list) {
      if (done) return;
      if (f.sub) { visit(f.sub, inName || f.field === 505); continue; }
      if (inName && f.field === 501 && f.wt === 2) {
        f.payload = buf; f.len = buf.length; f.isText = true; done = true; return;
      }
    }
  })(fs, false);
  return done;
}

/** 克隆一个原型记录（**只克隆它自己，不带子控件** —— 我们要的是"空壳"） */
function makeRecord(proto, name, parentRec, x, y, w, h) {
  const id = nextId++;
  const field = deepField(proto.field);
  // ① 本记录自己的 ID
  let first501 = false;
  walkFields(field.sub, (f) => { if (!first501 && f.wt === 0 && f.field === 501) { f.num = BigInt(id); first501 = true; } });
  // ② 其它指向原型 ID 的地方也改（`#502/#11/#501`、`#505/#503/#504/#4`）
  walkFields(field.sub, (f) => {
    if (f.wt === 0 && f.field === 501 && f !== null && Number(f.num) === proto.id) f.num = BigInt(id);
    if (f.wt === 0 && f.field === 4 && Number(f.num) === proto.id) f.num = BigInt(id);
  });
  // ③ 父级 `#504`
  let setP = false;
  walkFields(field.sub, (f) => { if (!setP && f.wt === 0 && f.field === 504) { f.num = BigInt(parentRec.id); setP = true; } });
  // ④ 名字
  setName(field.sub, name);
  // ⑤ 清空子列表（原型自带的子控件我们不要 —— 否则会飘在界面上）
  const cl = findChildListTop(field.sub);
  if (cl) setChildList(cl, []);
  // ⑥ 几何
  let n = 0;
  for (const b of stateBlocks(field.sub, [])) {
    const p5 = pairOf(b, 505); if (p5) { setPair(p5, w, h); n++; }
    const p4 = pairOf(b, 504); if (p4) { setPair(p4, x, y); n++; }
  }

  const rec = { id, name, parentId: parentRec.id, field: null, holder: null, index: -1 };
  // ⚠️⚠️ **字段号必须用原型记录的**，不能写 0！
  //   我第一版写成 `{ field: 0, wt: 2, sub: field.sub }` —— 字段号 0 在 protobuf 里**非法**，
  //   编码出来 tag=2，整个文件解析成 **0 条记录**（回读验证当场报"34 个全丢了"）。
  //   记录在 `.gil` 里是**带字段号的重复字段**（本工程是 `#9`），必须照抄原型那个号。
  rec.field = { field: proto.field.field, wt: 2, sub: field.sub, num: 0n,
                payload: Buffer.alloc(0), len: 0, isText: false };
  byId.set(id, rec);
  byName.set(name, rec);

  // ⑦ 挂进父级子列表
  const pl = ensureChildListTop(parentRec, findChildListTop(protoBox.field.sub));
  const ids = asIdList(pl.payload, true) || [];
  ids.push(id);
  setChildList(pl, ids);

  // ⑧ 写进正确的容器
  g.recHolder.push(rec.field);
  return { rec, pairs: n };
}

// ── 对比计划，补缺失的 ─────────────────────────────────────────────────────
// 只补"叶子界面控件"：容器/按钮/文本。层级按计划里的 parent 递归解析。
const planNodes = plan.nodes || [];
const planById = new Map(planNodes.map((n) => [n.id, n]));
const created = [], skipped = [];

// 计划里的坐标是**画布空间**（1600×900），而 .gil 里存的是**设计空间**（1920×1080）
const SX = 1920 / 1600, SY = 1080 / 900;
const toDesign = (n) => ({
  x: Math.round((n.cx - n.w / 2) * SX), y: Math.round((n.cy - n.h / 2) * SY),
  w: Math.round(n.w * SX), h: Math.round(n.h * SY),
});

function parentRecOf(pid) {
  if (!pid) return g.byName.get('root');
  return g.byName.get(pid) || g.byName.get('root');
}
function parentPlanId(pid) {
  const p = planById.get(pid);
  return p ? p.parent : 'root';
}

for (const n of planNodes) {
  if (byName.has(n.id)) { continue; }                    // 已有 ⇒ 不动（尊重编辑器）
  // 只处理我们关心的几类；`cell.*` / `tray.*` 等由脚本运行时生成，不进 .gil
  if (/^(cell\.|ruler|tray\.|portrait\.|hud\.|toast|fx\.)/.test(n.id)) { skipped.push(n.id); continue; }
  if (n.kind !== 'container' && n.kind !== 'button' && n.kind !== 'text' && n.kind !== 'cursor') {
    skipped.push(n.id); continue;
  }
  // 父级也得存在（先建父再建子 —— 计划里父一般排在前面）
  const pid = parentPlanId(n.id);
  const parentRec = g.byName.get(pid) || g.byName.get('root');
  if (!g.byName.get(pid) && pid !== 'root') { skipped.push(n.id + '(父 ' + pid + ' 不在)'); continue; }

  const proto = n.kind === 'container' ? protoBox
              : (n.kind === 'text' && protoText ? protoText : protoBtn);
  const d = toDesign(n);
  const r = makeRecord(proto, n.id, parentRec, d.x, d.y, d.w, d.h);
  created.push({ id: n.id, kind: n.kind, parent: parentRec.name, rect: d, pairs: r.pairs });
}

console.log('  存档 ' + path.basename(GIL) + '  记录 ' + g.recs.length + ' → 新增 ' + created.length);
for (const c of created.slice(0, 40)) {
  console.log('    + ' + c.id.padEnd(26) + c.kind.padEnd(10) + '父=' + String(c.parent).padEnd(12)
    + JSON.stringify(c.rect) + (c.pairs >= 4 ? '' : '  ⚠️ 坐标组数 ' + c.pairs));
}
if (created.length > 40) console.log('    …还有 ' + (created.length - 40) + ' 个');
if (skipped.length) console.log('    跳过（脚本运行时生成 / 不需要进 .gil）：' + skipped.slice(0, 12).join(' ') + (skipped.length > 12 ? ' …' : ''));

if (DRY) { console.log('  --dry：不写文件'); process.exit(0); }

fs.writeFileSync(OUT, g.pack(encodeMsg(g.tree)));
console.log('\n输出：' + path.basename(OUT) + '  ' + fs.statSync(OUT).size + ' 字节');

// ── 回读验证（**必须**：只看"写成功"不算数）────────────────────────────────
const g2 = readGil(OUT);
const holderCount = new Map();
{
  const paths = new Map();
  (function walk(fields, p) { for (const f of fields) if (f.sub) { paths.set(f.sub, p + '/#' + f.field); walk(f.sub, p + '/#' + f.field); } })(g2.tree, '');
  for (const r of g2.recs) { const p = paths.get(r.holder) || '(顶层)'; holderCount.set(p, (holderCount.get(p) || 0) + 1); }
}
console.log('  回读：记录 ' + g2.recs.length + '；记录分布 ' + [...holderCount].map(([p, n]) => p + '=' + n).join(' '));
const topLevel = holderCount.get('(顶层)') || 0;
console.log('  ' + (topLevel === 0 ? '✅ 所有记录都在子消息里（编辑器读得到）' : '❌ 有 ' + topLevel + ' 条跑到了顶层，编辑器读不到'));
let missing = 0;
for (const c of created) if (!g2.byName.has(c.id)) { missing++; console.log('    ❌ 回读不到 ' + c.id); }
console.log('  ' + (missing === 0 ? '✅ 新增的 ' + created.length + ' 个控件回读全在' : '❌ 有 ' + missing + ' 个丢了'));
process.exit(missing === 0 && topLevel === 0 ? 0 : 4);
