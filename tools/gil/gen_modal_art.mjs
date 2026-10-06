// tools/gil/gen_modal_art.mjs —— 弹窗四键：**整份克隆同类控件的底图** + 填 label 文案
//
// 为什么不能"自己填图对"（2026-10-07 用户反馈"按钮点到了但图不出来"）：
//   逐字段比对了真机能显示的 `home.select.bg` 与我上一轮**自己拼**的 `bg`：
//     · 图对**不同**：home.select.bg = source **4281536672** / id **100108**
//                    我那份（抄 clues.bg）= source 4279900704 / id 100001      ← 张冠李戴
//     · 我那份还**少 4 条字段路径**，其中包括 `#505/#503/#84/#504`（imageType 那一类）
//       以及 `home.select.bg` 顶层的**第二个 `#502`**（重复字段，不是同一个东西）
//   ⇒ 结论：**整份克隆同类控件的记录**（按钮抄按钮、面板抄面板），不要跨类拼字段。
//
// 用法：
//   node tools/gil/gen_modal_art.mjs --in=213-弹窗四键.gil --out=214-弹窗配图.gil [--probe]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, cloneField, setPair, pairOf, stateBlocks, textsOf,
  findChildListTop, ensureChildListTop, setChildList, asIdList, writeVarint,
} from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const DRY = argv.includes('--probe');
const BASE = argOf('in') || path.join(ROOT, '213-弹窗四键.gil');
const OUT = argOf('out') || path.join(ROOT, '214-弹窗配图.gil');
const BGP = argOf('bg-proto') || 'home.select/bg';   // **同类控件的底图**（真机能显示的那份）
// ⚠️ `byName` 是按**记录自己的名字**索引的：`home.select.bg` 这条记录的 `name` 其实是 **`bg`**
//    （它的父才是 `home.select`）⇒ 必须按「父名/子名」两级查，不能按点号路径查。

// 严格按用户文本，从上到下
const KEYS = [
  { name: 'modal.exit',   text: '退出至菜单', cy: 500 },
  { name: 'modal.save',   text: '仅存档',     cy: 430 },
  { name: 'modal.settle', text: '存档并结算', cy: 360 },
  { name: 'modal.cancel', text: '取消',       cy: 290 },
];
const W = 480, H = 56;

const g = readGil(BASE);
const [BGP_PARENT, BGP_CHILD] = BGP.split('/');
const bgParent = g.byName.get(BGP_PARENT);
const proto = bgParent ? g.recs.find((r) => r.parentId === bgParent.id && r.name === BGP_CHILD) : null;
if (!proto) { console.error('找不到底图原型 ' + BGP + '（按 父名/子名 查）'); process.exit(1); }
const panel = g.byName.get('modal');
const pc = stateBlocks(panel.field.sub, [])[0];
const pv = (b, no, i) => { const p = pairOf(b, no); if (!p || !p.sub) return 0; const h = p.sub.find((x) => x.field === (i === 0 ? 501 : 502) && x.wt === 5); return h ? h.f : 0; };
const pcx = 800 + pv(pc, 504, 0), pcy = 450 + pv(pc, 504, 1);
console.log('基准 ' + path.basename(BASE) + '（' + g.recs.length + ' 条）  底图原型 ' + BGP + ' #' + proto.id);
console.log('  原型图对：source=' + (() => { let v = '?'; (function w(fs, p) { for (const f of fs) { const q = p + '/' + f.field; if (f.wt === 0 && f.field === 502 && q.endsWith('/84')) v = String(f.num); if (f.sub) w(f.sub, q); } })(proto.field.sub, ''); return v; })()
  + '  id=' + (() => { let v = '?'; (function w(fs, p) { for (const f of fs) { const q = p + '/' + f.field; if (f.wt === 0 && f.field === 503 && q.endsWith('/84')) v = String(f.num); if (f.sub) w(f.sub, q); } })(proto.field.sub, ''); return v; })());

let nextId = Math.max(...g.recs.map((r) => r.id)) + 1;
const newBg = [];
// ⚠️ **必须倒序处理**：`rec.index` 是读入时在 holder 里的下标，插入一条会让它**后面**的记录
//    下标整体 +1 ⇒ 正序插入会把后面的记录插进别的记录中间（记录被劈开）。
//    倒序（从数组尾部往头部插）不会影响还没处理的下标。第一版就是正序，被 check_childlist_top 抓到。
for (const k of [...KEYS].reverse()) {
  const rec = g.byName.get(k.name);
  if (!rec) { console.error('找不到 ' + k.name); process.exit(2); }
  const lst = ensureChildListTop(rec, null);
  let ids = asIdList(lst.payload, true) || [];

  // ① 换掉旧 bg（上一轮自己拼的那份：图对是面板的、还缺字段）
  const old = g.recs.find((r) => r.parentId === rec.id && r.name === 'bg');
  if (old) { const h = old.holder; const at = h.indexOf(old.field); if (at >= 0) h.splice(at, 1); ids = ids.filter((x) => x !== old.id); console.log('  ' + k.name + '：换掉旧 bg #' + old.id); }

  // ② **整份克隆**同类控件的底图记录：只改 ID / 父 / 名 / 几何，别的字段一律原样搬
  const clone = cloneField(proto.field);
  const nid = nextId++;
  (function fix(fs) { for (const f of fs) { if (f.wt === 0 && Number(f.num) === proto.id) f.num = BigInt(nid); else if (f.wt === 2 && f.sub === null && !f.isText && f.payload && f.payload.length >= 1 && f.payload.length <= 8) { const a = asIdList(f.payload, false); if (a && a.length === 1 && a[0] === proto.id) { f.payload = writeVarint(nid); f.len = f.payload.length; } } if (f.sub) fix(f.sub); } })(clone.sub);
  let pOk = false;
  (function fp(fs) { for (const f of fs) { if (!pOk && f.wt === 0 && f.field === 504 && Number(f.num) === proto.parentId) { f.num = BigInt(rec.id); pOk = true; } if (f.sub) fp(f.sub); } })(clone.sub);
  const nf = textsOf(clone.sub, []).find((t) => t.payload.toString('utf8') === proto.name);
  let nOk = false; if (nf) { nf.payload = Buffer.from('bg', 'utf8'); nf.len = nf.payload.length; nOk = true; }
  let geo = 0;
  for (const b of stateBlocks(clone.sub, [])) { setPair(pairOf(b, 504), 0, 0); setPair(pairOf(b, 505), W, H); geo++; }
  if (!pOk || !nOk || geo !== 4) { console.error('  ❌ ' + k.name + ' 底图克隆不完整 父' + pOk + ' 名' + nOk + ' 几何' + geo); process.exit(3); }
  rec.holder.splice(rec.index + 1, 0, clone);
  setChildList(lst, [nid, ...ids]);                       // 第 1 位：垫在 label 之下
  newBg.push({ k, rec, nid, clone });

  // ③ 几何：四键本身（同尺寸同列）
  let g2 = 0;
  for (const b of stateBlocks(rec.field.sub, [])) { if (setPair(pairOf(b, 504), 0, k.cy - pcy)) g2++; setPair(pairOf(b, 505), W, H); }
  if (g2 !== 4) { console.error('  ❌ ' + k.name + ' 四状态几何只改 ' + g2); process.exit(4); }

  // ④ 文案：写进 label 子控件的第一个"非名字"文本字段
  const lab = g.recs.find((r) => r.parentId === rec.id && r.name === 'label');
  let tOk = false;
  if (lab) (function put(fs) { for (const f of fs) { if (f.wt === 2 && f.isText && f.payload && f.payload.toString('utf8') !== 'label' && f.len > 0 && f.len <= 64) { f.payload = Buffer.from(k.text, 'utf8'); f.len = f.payload.length; tOk = true; return; } if (f.sub) put(f.sub); } })(lab.field.sub);
  console.log('  ' + k.name.padEnd(13) + 'bg #' + nid + '  文案「' + k.text + '」' + (tOk ? '✅ 写入' : '⚠️ label 里没有可写的文本字段'));
}
if (DRY) { console.log('--probe：不写文件'); process.exit(0); }
fs.writeFileSync(OUT, g.pack(encodeMsg(g.tree)));
console.log('输出：' + OUT + '  ' + fs.statSync(OUT).size + ' 字节  记录 ' + readGil(OUT).recs.length);
