// 663 盘点 2：按层序输出关键区域可见/隐藏层，生成可读文本
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = ROOT + '/qianxing-murdoku/657_关卡内UI';
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));
const g = readGil(DIR + '/662v19.gil');
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const rows = g.recs.map(r => {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const rf = st?.sub?.find(q => q.field === 508), ip = ns(r.field, [505, 503, 84])[0];
  const c = ip ? num(ip, 502) : null;
  return {
    o: order.get(r.field) ?? -1, id: r.id, name: r.name || '',
    p: byId.get(r.parentId)?.name || (r.parentId ? '#' + r.parentId : 'ROOT'),
    h: isHiddenRecord(r.field) ? 'H' : ' ',
    cx: p ? +(800 + pairValue(p, 0)).toFixed(1) : 0, cy: p ? +(450 - pairValue(p, 1)).toFixed(1) : 0,
    w: s ? +pairValue(s, 0).toFixed(1) : 0, h2: s ? +pairValue(s, 1).toFixed(1) : 0,
    rot: rf?.sub?.[0]?.f ?? 0,
    c: c === null ? '-' : '#' + (c >>> 0).toString(16).padStart(8, '0').toUpperCase(),
    img: ip ? num(ip, 503) : '-',
  };
}).sort((a, b) => a.o - b.o);

const line = r => [String(r.o).padStart(5), r.h, r.name.padEnd(46),
  `${String(r.cx).padStart(7)},${String(r.cy).padStart(7)} ${String(r.w).padStart(7)}x${String(r.h2).padStart(7)}`,
  'r=' + String(r.rot).padStart(7), r.c.padEnd(11), 'img=' + String(r.img).padEnd(7), r.p].join(' ');

const sets = {
  '01 两套网格纸': /^(art661\.clues\.grid|art656\.home\.grid|art657\.grid\.reuse|art660\.clues\.grid|art641\.game\.boardframe|art657\.game\.board\.tape)/,
  '02 线索卡/底板': /^(art6\d\d\.clue|art658\.clue|art659\.clue|art660\.clue|art661\.clue|backrop|clues\.bg|clues\.grid|clues$|clue$|art657\.game\.notebook)/,
  '03 图钉火漆': /^(art657\.game\.pin|art6\d\d\.wax|art6\d\d\.seal)/,
  '04 票券邻域': /^(art641\.game\.help|art657\.game\.help|art658\.help|art659\.help|art660\.help|art661\.help|clues\.help)/,
};
let out = `TOTAL recs=${g.recs.length} recTop=${recTop.sub.length} maxId=${g.maxId}\n`;
for (const [k, re] of Object.entries(sets)) {
  const v = rows.filter(r => re.test(r.name));
  out += `\n========== ${k} (${v.length}) ==========\n` + v.map(line).join('\n') + '\n';
}
// 票券/线索区附近全部可见静态层（按 order 范围）
const near = rows.filter(r => r.o >= 3280 && r.o <= 3460);
out += `\n========== 票券邻域全部层 order 3280..3460 (${near.length}) ==========\n` + near.map(line).join('\n') + '\n';
const near2 = rows.filter(r => r.o >= 6780 && r.o <= 6901);
out += `\n========== 尾部全部层 order 6780..6901 (${near2.length}) ==========\n` + near2.map(line).join('\n') + '\n';
fs.writeFileSync(DIR + '/_663_盘点.txt', out);
console.log('written', out.length, 'bytes');
for (const [k, re] of Object.entries(sets)) console.log(k, rows.filter(r => re.test(r.name)).length);
