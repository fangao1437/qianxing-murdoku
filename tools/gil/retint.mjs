// tools/gil/retint.mjs —— 把指定控件的**子控件图片**换成另一个素材（source+id 成对）
//
// 为什么单独做个工具：
//   我在 gen_btn_art.mjs 里把"克隆 + 改图"写成了从零生成，
//   但**用户的存档里已经有一个 assets 调色板容器**（portrait.*）——
//   重新生成会把它丢掉。所以后期的颜色调整要能**在现有存档上原地改**。
//
// 用法：
//   node tools/gil/retint.mjs --in=a.gil --out=b.gil --parent-prefix=tray. --child=face --src=4281536672 --id=100108
//   node tools/gil/retint.mjs --in=a.gil --out=b.gil --names=tool.place,action.undo --child=bg --id=100108
//
// ⚠️ 只改 id 的前提是**新 id 与旧 id 属于同一个 source**（同一个图集）。
//    换到别的图集必须连 --src 一起给，否则会出现"属性变了、画面没变"（我踩过三版）。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, asIdList } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const DRY = argv.includes('--probe');

const BASE = argOf('in');
const OUT = argOf('out') || BASE;
const CHILD = argOf('child') || 'bg';
const NEW_ID = Number(argOf('id') || 100108);
const NEW_SRC = argOf('src') ? Number(argOf('src')) : null;
const NAMES = argOf('names') ? argOf('names').split(',').map((s) => s.trim()).filter(Boolean) : null;
const PREFIX = argOf('parent-prefix');

if (!BASE) { console.error('必须给 --in='); process.exit(1); }
const g = readGil(BASE);
console.log('基准：' + path.basename(BASE) + '  控件记录 ' + g.recs.length + ' 条');

// ── 目标控件 ──────────────────────────────────────────────────────────────
let parents;
if (NAMES) {
  parents = NAMES.map((n) => g.byName.get(n)).filter(Boolean);
} else if (PREFIX) {
  parents = g.recs.filter((r) => r.name && r.name.startsWith(PREFIX));
} else {
  console.error('要给 --names= 或 --parent-prefix=');
  process.exit(1);
}
console.log('目标父控件：' + parents.length + ' 个（找子控件 `' + CHILD + '`）');

const IMG_ID_PATH = [505, 503, 84, 503];
const IMG_SRC_PATH = [505, 503, 84, 502];

/** 逐层保留全部候选 —— 记录里有多个 #505 块，只取第一个会走断 */
function fieldsAtPath(fields, p) {
  let level = [fields];
  for (let i = 0; i < p.length; i++) {
    const hits = [];
    for (const list of level) for (const f of list) if (f.field === p[i]) hits.push(f);
    if (!hits.length) return [];
    if (i === p.length - 1) return hits;
    level = hits.map((f) => f.sub).filter(Boolean);
    if (!level.length) return [];
  }
  return [];
}

let changed = 0, skipped = 0;
for (const p of parents) {
  const kid = g.recs.find((r) => r.parentId === p.id && r.name === CHILD);
  if (!kid) { skipped++; continue; }
  const idF = fieldsAtPath(kid.field.sub, IMG_ID_PATH).filter((f) => f.wt === 0)[0];
  if (!idF) { skipped++; console.log('  ⚠️ ' + p.name + '.' + CHILD + ' 没有图片 id 字段'); continue; }
  const before = Number(idF.num);
  idF.num = BigInt(NEW_ID);
  if (NEW_SRC !== null) {
    const srcF = fieldsAtPath(kid.field.sub, IMG_SRC_PATH).filter((f) => f.wt === 0)[0];
    if (srcF) srcF.num = BigInt(NEW_SRC);
  }
  if (before !== NEW_ID) changed++;
}
console.log('改图：' + changed + ' 个，跳过（无该子控件/无图片字段）：' + skipped);

if (changed === 0) { console.log('\n无需改动'); process.exit(0); }
if (DRY) { console.log('\n--probe：不写文件'); process.exit(0); }

const body = encodeMsg(g.tree);
const buf = g.pack(body);
fs.writeFileSync(OUT, buf);

// 自检
const g2 = readGil(OUT);
let ok = 0;
for (const p of parents) {
  const kid = g2.recs.find((r) => r.parentId === p.id && r.name === CHILD);
  if (!kid) continue;
  const idF = fieldsAtPath(kid.field.sub, IMG_ID_PATH).filter((f) => f.wt === 0)[0];
  if (idF && Number(idF.num) === NEW_ID) ok++;
}
console.log('\n输出：' + path.basename(OUT) + '  ' + buf.length + ' 字节');
console.log('  头 ' + [0, 4, 8, 12, 16].map((o) => buf.readUInt32BE(o)).join(', '));
const tr = buf.subarray(buf.length - g.trailer.length);
console.log('  尾 ' + tr.toString('hex') + (tr.equals(g.trailer) ? '  ✅' : '  ❌')
  + '   记录 ' + g2.recs.length + '（原 ' + g.recs.length + '）');
console.log('  ' + (ok === changed ? '✅' : '❌') + ' 读回验证：' + ok + '/' + changed + ' 个已改成 id=' + NEW_ID);
process.exit(ok === changed ? 0 : 4);
