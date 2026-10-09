// tools/gil/clone_rows.mjs —— 按用户示例 `row.1.1` 克隆出其余 row（★ 整棵子树 ✓ 不是叶子 ✗）
//
// ════════════════════════════════════════════════════════════════════════════
// ★ 用户规格（2026-10-10 ✓ 原话 ✓）
// ════════════════════════════════════════════════════════════════════════════
//   「两张 backrop 和 gray 是**模板内的**，且**不存在差异性，不需要建** ✓
//     只需要建**另外四个**就行 ✓」（★ 即 `who` / `what` / `face` / `letter` ✓）
//   「我会做一个**示例**，然后剩下的多个**由你直接通过编辑 gil 建**」✓
//   「file 在 `261.gil`」✓
//   「face 和 letter 是**模板引用控件**，会引用图片和字母徽章 ✓
//     **这个你可以不引用** ✓；我这么建只是为了省事 ✓」
//   「who、what 你**也不用填内容**」✓
//   「你把 **1.1-1.5、2.1-2.6、3.1-3.9** 建出来，**我自己去填内容**」✓
//
// ★ 用户示例的结构（`261.gil` 实测 ✓）：
//     row.1.1  #1073742516  pos=(0,0) size=150x150
//       who.1.1     #1073742539  size=100x40    ← ★ 文本 ✓
//       letter.1.1  #1073742522  size=80x80     ← ★ 文本（用户做成模板引用 ✓ 我不引用 ✓）
//       what.1.1    #1073742493  size=100x40    ← ★ 文本 ✓
//       face.1.1    #1073742521  size=80x80     ← ★ 图片 ✓
//
//   ★★ 注意 ✓：**子控件名带 `.1.1` 后缀** ✗ ⇒
//     ★ 脚本侧取槽位名必须**取第一个点号之前** ✓（★ 我 v124 写成"第一段非空白"✗ ⇒ 对不上 ✓）
//
// ★ 做法 ✓：**追加记录** ✓（append-only ✓ 项目允许的最安全那档 ✓）
//   · 每个新 row = 原型子树的**深拷贝** ✓，id 全部换新 ✓
//   · `#501`（自身 id）与 `#504`（父级 id）在每份拷贝里重写 ✓
//   · 名字按 `<槽位>.<关>.<行>` 重命名 ✓
//   · **子树内部的子列表**指向新 id ✓（★ 不重写就会指回原型 ✗）
//   · 新 row 挂进 `assets` 的子列表 ✓
//
// 用法：
//   node tools/gil/clone_rows.mjs --base=261.gil --out=262-rows.gil --spec="1.2,1.3,1.4,1.5,2.1,2.2,2.3,2.4,2.5,2.6,3.1,3.2,3.3,3.4,3.5,3.6,3.7,3.8,3.9"

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, findChildListTop, ensureChildListTop, setChildList, asIdList,
} from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const arg = (k, d) => {
  const h = process.argv.find((s) => s.startsWith('--' + k + '='));
  return h ? h.slice(k.length + 3).replace(/^"|"$/g, '') : d;
};
const P = (p) => (path.isAbsolute(p) ? p : path.resolve(ROOT, p));

const BASE = arg('base');
const OUT = arg('out');
const PROTO = arg('proto', 'row.1.1');
const PARENT = arg('parent', 'assets');
const SPEC = arg('spec', '');
if (!BASE || !OUT || !SPEC) {
  console.error('用法: --base=<含原型的.gil> --out=<输出.gil> --spec="1.2,1.3,..."');
  process.exit(1);
}

const g = readGil(P(BASE));
const proto = g.recs.find((r) => r.name === PROTO);
if (!proto) { console.error('❌ 找不到原型 `' + PROTO + '`'); process.exit(2); }
const parent = g.recs.find((r) => r.name === PARENT);
if (!parent) { console.error('❌ 找不到父级 `' + PARENT + '`'); process.exit(2); }
console.log('  原型 `' + PROTO + '` #' + proto.id + '　父级 `' + PARENT + '` #' + parent.id);

// ── 深拷贝一个 field 子树（★ 值也拷 ✓ 不共享引用 ✗）
const deepField = (f) => ({
  field: f.field, wt: f.wt, num: f.num ?? 0n,
  payload: f.payload ? Buffer.from(f.payload) : Buffer.alloc(0),
  len: f.len ?? 0, isText: !!f.isText,
  sub: f.sub ? f.sub.map(deepField) : null,
});
const walkFields = (fs, fn) => { for (const f of fs) { fn(f); if (f.sub) walkFields(f.sub, fn); } };

// ── 取/改"名字"（第一个 wt=2 且 isText 的字段 ✓ 与 clone_asset_image 同一套 ✓）
const setName = (fs, text) => {
  let done = false;
  walkFields(fs, (f) => {
    if (done) return;
    if (f.wt === 2 && f.isText) { f.payload = Buffer.from(text, 'utf8'); f.len = f.payload.length; done = true; }
  });
  return done;
};
const getName = (rec) => rec.name;

// ── 收集原型子树（★ 含自身 ✓ 深度优先 ✓）
const subtree = [];
const collect = (rec) => {
  subtree.push(rec);
  g.recs.filter((r) => r.parentId === rec.id).forEach(collect);
};
collect(proto);
console.log('  原型子树 ' + subtree.length + ' 条：' + subtree.map((r) => r.name).join(', '));

let nextId = Math.max(...g.recs.map((r) => Number(r.id))) + 1;
const specs = SPEC.split(',').map((s) => s.trim()).filter(Boolean);
let made = 0, madeRecs = 0;

for (const sp of specs) {
  const [lv, rw] = sp.split('.');
  if (!lv || !rw) { console.log('  ⚠️ 跳过格式不对的 `' + sp + '`'); continue; }
  // ① 给子树里每条记录分一个新 id
  const idMap = new Map();
  for (const rec of subtree) idMap.set(String(rec.id), nextId++);

  for (const rec of subtree) {
    const newId = idMap.get(String(rec.id));
    const isRoot = (rec.id === proto.id);
    // ② 新名字：★ `<槽位>.<关>.<行>` ✓（★ 槽位 = 原型名字的第一个点号之前 ✓）
    const slot = String(rec.name || '').split('.')[0];
    const newName = isRoot ? ('row.' + sp) : (slot + '.' + sp);
    const field = deepField(rec.field);
    // ③ 重写 #501（自身 id）与 #504（父级 id）——★ 各只改**第一个** ✓
    let selfDone = false;
    walkFields(field.sub, (f) => {
      if (!selfDone && f.field === 501 && f.wt === 0) { f.num = BigInt(newId); selfDone = true; }
    });
    let parDone = false;
    const newParentId = isRoot ? parent.id : idMap.get(String(rec.parentId));
    walkFields(field.sub, (f) => {
      if (!parDone && f.field === 504 && f.wt === 0) { f.num = BigInt(newParentId); parDone = true; }
    });
    // ④ 换名字
    setName(field.sub, newName);
    // ⑤ 子树内部的**子列表**指向新 id ✓（★ 不重写就指回原型 ✗）
    const cl = findChildListTop(field.sub);
    if (cl && rec.field) {
      const protoCl = findChildListTop(rec.field.sub);
      const oldKids = protoCl ? asIdList(protoCl).map(String) : [];
      const newKids = oldKids.map((oid) => idMap.get(oid)).filter((v) => v !== undefined).map(String);
      setChildList(cl, newKids);
    }
    const nr = {
      id: newId, name: newName, parentId: newParentId,
      field: null, holder: null, index: -1, fieldNum: rec.fieldNum,
    };
    nr.field = { field: rec.field.field, wt: 2, sub: field.sub, num: 0n, payload: Buffer.alloc(0), len: 0, isText: false };
    g.recHolder.push(nr.field);
    g.recs.push(nr);
    g.byName.set(newName, nr);
    madeRecs++;
  }
  // ⑥ 把新 row 挂进 `assets`
  const rootNewId = idMap.get(String(proto.id));
  const pl = ensureChildListTop(parent, findChildListTop(proto.field.sub));
  if (pl) {
    const cur = asIdList(pl).map(String);
    if (!cur.includes(String(rootNewId))) { cur.push(String(rootNewId)); setChildList(pl, cur); }
  }
  made++;
  console.log('  ✅ row.' + sp + '  id=' + rootNewId);
}

if (made === 0) { console.error('❌ 一份都没建，不写文件'); process.exit(3); }
const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(P(OUT), buf);
console.log('  写出 ' + path.basename(P(OUT)) + '  ' + Math.round(buf.length / 1024) + ' KB（row ' + made + ' 个 / 记录 ' + madeRecs + ' 条）');

// ── 回读自检 ✓
const g2 = readGil(P(OUT));
let bad = 0;
for (const sp of specs) {
  for (const pre of ['row', 'who', 'what', 'face', 'letter']) {
    const nm = pre + '.' + sp;
    const r = g2.recs.find((x) => x.name === nm);
    if (!r) { console.log('  ❌ 回读找不到 ' + nm); bad++; }
  }
}
const a2 = g2.recs.find((r) => r.name === PARENT);
const kids2 = g2.recs.filter((r) => r.parentId === a2.id);
console.log('  assets 子控件 ' + kids2.length + ' 个');
console.log(bad ? ('  ❌ 回读有 ' + bad + ' 个不对') : '  ★ 回读全部就位 ✅');
console.log('⚠️ 交付前必须跑：node tools/gil/roundtrip.mjs ' + path.basename(P(OUT)));
