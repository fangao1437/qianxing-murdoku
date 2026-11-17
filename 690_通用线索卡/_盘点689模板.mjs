// 690 · 只读盘点 689 的两套 clue 模板（层序 / gen.* 三件 / 字段结构）
// 用法：node _盘点689模板.mjs  → 打印摘要并写 690_模板盘点.json
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const INPUT = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_性能负载优化.gil');
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, findChildListTop, asIdList, cloneField } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const { isHiddenRecord, imageTriple } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const hex = v => v == null ? null : '0x' + (v >>> 0).toString(16).padStart(8, '0').toUpperCase();

function textOf(r) {
  const t = ns(r.field, [505, 503, 75])[0];
  if (!t) return null;
  let out = null;
  (function walk(f) {
    if (f.wt === 2 && f.payload && f.len > 0 && f.len < 200) {
      const s = f.payload.toString('utf8');
      if (/[\u4e00-\u9fa5A-Za-z]/.test(s) && s !== r.name) out = s;
    }
    for (const q of f.sub || []) walk(q);
  })(t);
  return out;
}
function desc(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const ip = imageTriple(r.field);
  const tp = ns(r.field, [505, 503, 75])[0];
  const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f ?? 0;
  return {
    name: r.name, id: r.id, hidden: isHiddenRecord(r.field), recIndex: order.get(r.field),
    pos: p ? [pairValue(p, 0), pairValue(p, 1)] : null,
    size: s ? [pairValue(s, 0), pairValue(s, 1)] : null,
    imageId: ip ? ip.id : null, imageColor: ip ? hex(ip.color) : null, imageType: ip ? ip.type : null,
    rot, textColor: tp ? hex(num(tp, 504)) : null, text: textOf(r),
  };
}
const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
const out = { input: INPUT, records: g.recs.length, maxId: String(g.maxId), templates: [] };
for (const root of TPL) {
  const kids = g.recs.filter(r => r.parentId === root.id).sort((a, b) => (order.get(a.field) ?? 1e9) - (order.get(b.field) ?? 1e9));
  const cl = findChildListTop(root.field.sub);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  out.templates.push({
    root: desc(root),
    childList: ids.map(id => byId.get(id)?.name ?? String(id)),
    children: kids.map(desc),
  });
}
fs.writeFileSync(path.join(DIR, '690_模板盘点.json'), JSON.stringify(out, null, 2));
for (const t of out.templates) {
  console.log('\n=== clue root', t.root.id, 'pos', t.root.pos, 'size', t.root.size, '===');
  console.log('childList:', t.childList.join(' | '));
  for (const c of t.children) {
    console.log(String(c.recIndex).padStart(5), c.hidden ? 'HID ' : 'VIS ', c.name.padEnd(28),
      String(c.id).padEnd(12), 'pos', JSON.stringify(c.pos), 'size', JSON.stringify(c.size),
      c.imageId ? `img=${c.imageId} ${c.imageColor}` : '', c.textColor ? `tc=${c.textColor}` : '',
      c.rot ? `rot=${c.rot}` : '', c.text ? `text=${JSON.stringify(c.text)}` : '');
  }
}
