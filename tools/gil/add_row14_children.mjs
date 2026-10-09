// tools/gil/add_row14_children.mjs —— 补 `row.1.4` 缺的 `what` / `letter`（★ 只加不改 ✓）
//
// ★ 依据（修好读法后的实测 ✓）：
//   `row.1.4` 的 `#503` **只有 2 项**（`who.1.4` / `face.1.4`）✗
//   ⇒ ★ 这是**另一类失败（真丢）** ✗ —— 与 `3.1`/`3.9` 的"读不到"不同 ✓
//   ⇒ ★ 从 `row.1.5` 的 `what.1.5` / `letter.1.5` 克隆两份 ✓ 改名 ✓ 改父级 ✓
//
// ★ 做法照 `gen_palette.mjs`（项目里跑通过的那套 ✓）：
//   ★ 克隆**字段对象** ✓ ★ 改 `#501`/`#504`/名字 ✓ ★ **插进 holder 数组** ✓ ★ 父级 `#503` 写全 ✓
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, cloneField, findChildListTop, setChildList, asIdList, bigIds, textsOf,
} from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const P = (p) => (path.isAbsolute(p) ? p : path.resolve(ROOT, p));
const argv = process.argv.slice(2);
const arg = (k, d) => { const h = argv.find((s) => s.startsWith('--' + k + '=')); return h ? h.slice(k.length + 3) : d; };
const IN = arg('in'), OUT = arg('out', IN);
if (!IN) { console.error('用法: --in=<存档> [--out=]'); process.exit(1); }

const g = readGil(P(IN));
const target = g.recs.find((r) => r.name === 'row.1.4');
if (!target) { console.error('✗ 找不到 row.1.4'); process.exit(2); }
const cl = findChildListTop(target.field.sub);
if (!cl) { console.error('✗ row.1.4 没有 #503'); process.exit(2); }
const have = (asIdList(cl.payload, true) || []).map((id) => (g.recs.find((x) => String(x.id) === String(id)) || {}).name);
console.log('  row.1.4 现有子控件: ' + have.join(', '));

function holderOf(id) {
  const stack = [g.tree];
  while (stack.length) {
    const arr = stack.pop();
    if (!Array.isArray(arr)) continue;
    for (let i = 0; i < arr.length; i++) {
      const f = arr[i];
      if (f.sub) {
        if (((bigIds(f.sub, [])[0] || {}).num) === BigInt(id)) return { arr, index: i };
        stack.push(f.sub);
      }
    }
  }
  return null;
}

let maxId = 0n;
for (const r of g.recs) if (BigInt(r.id) > maxId) maxId = BigInt(r.id);

const ids = (asIdList(cl.payload, true) || []).slice();
let made = 0;
for (const slot of ['what', 'letter']) {
  if (have.includes(slot + '.1.4')) { console.log('  ↷ ' + slot + '.1.4 已存在，跳过'); continue; }
  const proto = g.recs.find((r) => r.name === slot + '.1.5');
  if (!proto) { console.error('✗ 找不到原型 ' + slot + '.1.5'); process.exit(2); }
  const h = holderOf(proto.id);
  if (!h) { console.error('✗ 找不到 ' + slot + '.1.5 的 holder'); process.exit(2); }
  const cf = cloneField(h.arr[h.index]);
  const bid = bigIds(cf.sub, [])[0];
  if (!bid) { console.error('✗ 克隆体没有 #501'); process.exit(2); }
  const newId = maxId + BigInt(made + 1);
  bid.num = newId;
  const newName = slot + '.1.4';
  const txt = textsOf(cf.sub, []).find((t) => t.payload && t.payload.toString('utf8') === slot + '.1.5');
  if (txt) txt.payload = Buffer.from(newName, 'utf8');
  else console.log('  ⚠️ 没找到名字字段（' + slot + '.1.5）—— 名字可能没改 ✗');
  const pf = cf.sub.find((x) => x.field === 504 && x.wt === 0);
  if (!pf) { console.error('✗ 克隆体没有 #504'); process.exit(2); }
  pf.num = BigInt(target.id);
  h.arr.splice(h.index + 1, 0, cf);          // ★ 插进树 ✓
  const rec = { id: Number(newId), name: newName, parentId: target.id, field: null, holder: null, index: -1 };
  rec.field = { field: proto.field.field, wt: 2, sub: cf.sub, num: 0n, payload: Buffer.alloc(0), len: 0, isText: false };
  g.recs.push(rec);
  g.byName.set(newName, rec);
  ids.push(Number(newId));
  made++;
  console.log('  ✅ 建了 ' + newName + '  #' + newId + '（原型 ' + slot + '.1.5 #' + proto.id + '）');
}
if (made === 0) { console.log('  没有要建的，不写文件 ✓'); process.exit(0); }
setChildList(cl, ids);                        // ★ 父级 #503 写全 ✓（只写一次 ✓）
console.log('  row.1.4 的 #503 → ' + ids.length + ' 项');

const buf = g.pack(encodeMsg(g.tree));
fs.writeFileSync(P(OUT), buf);
console.log('  写出 ' + path.basename(P(OUT)));

// 回读复核 ✓
const g2 = readGil(P(OUT));
const t2 = g2.recs.find((r) => r.name === 'row.1.4');
const cl2 = findChildListTop(t2.field.sub);
const names = (asIdList(cl2.payload, true) || []).map((id) => (g2.recs.find((x) => String(x.id) === String(id)) || {}).name).sort();
console.log('  回读 row.1.4 子控件: ' + names.join(', '));
const want = ['face.1.4', 'letter.1.4', 'what.1.4', 'who.1.4'].sort();
console.log(JSON.stringify(names) === JSON.stringify(want) ? '  ★★ 补齐 ✓✓' : '  ❌ 还不对');
console.log('⚠️ 交付前必须跑：node tools/gil/roundtrip.mjs ' + path.basename(P(OUT)));
