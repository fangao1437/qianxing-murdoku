// 663 盘点：只读导出 662v19.gil 中与五项调整相关的控件记录
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = ROOT + '/qianxing-murdoku/657_关卡内UI';
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(process.argv[2] || DIR + '/662v19.gil');
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => order.set(f, i));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
function info(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const rf = st?.sub?.find(q => q.field === 508);
  const ip = ns(r.field, [505, 503, 84])[0];
  const c = ip ? num(ip, 502) : null;
  return {
    order: order.get(r.field) ?? -1, id: r.id, name: r.name,
    parent: r.parentId, parentName: byId.get(r.parentId)?.name ?? null,
    hidden: isHiddenRecord(r.field),
    cx: p ? +(800 + pairValue(p, 0)).toFixed(2) : null,
    cy: p ? +(450 - pairValue(p, 1)).toFixed(2) : null,
    w: s ? +pairValue(s, 0).toFixed(2) : null,
    h: s ? +pairValue(s, 1).toFixed(2) : null,
    rot: rf?.sub?.[0]?.f ?? 0,
    color: c === null ? null : '#' + (c >>> 0).toString(16).padStart(8, '0').toUpperCase(),
    imageId: ip ? num(ip, 503) : null,
    states: stateBlocks(r.field.sub, []).length,
  };
}

const GROUPS = {
  help: /help|tab|票券|note|question/i,
  ring: /ring|ringhole|装订/i,
  grid: /grid|paper|tape|boardframe/i,
  pin: /pin|wax|seal|火漆|图钉/i,
  clue: /clue|backrop|clues\.bg|notebook/i,
};
const all = g.recs.map(info).sort((a, b) => a.order - b.order);
const out = { total: g.recs.length, maxId: g.maxId, recTopCount: recTop.sub.length, groups: {} };
for (const [key, re] of Object.entries(GROUPS)) {
  out.groups[key] = all.filter(r => r.name && re.test(r.name));
}
// 线索卡区域所有静态层（父为 clues 或静态根，且几何落在 x<560, y150..800）
out.clueStatic = all.filter(r => r.order >= 0 && r.cx !== null && r.cx < 600 && r.cy > 130 && r.cy < 820
  && !r.hidden && /art6|clue|backrop/.test(r.name || ''));
fs.writeFileSync(DIR + '/_663_盘点.json', JSON.stringify(out, null, 2));
for (const [k, v] of Object.entries(out.groups)) {
  console.log('\n===== ' + k + ' (' + v.length + ') =====');
  for (const r of v) console.log(
    String(r.order).padStart(5), r.hidden ? 'H' : ' ', String(r.id).padStart(11),
    (r.name || '').padEnd(42), `${String(r.cx).padStart(7)},${String(r.cy).padStart(7)} ${String(r.w).padStart(7)}x${String(r.h).padStart(7)}`,
    'rot=' + String(r.rot).padStart(7), (r.color || '').padEnd(11), 'img=' + r.imageId, 'p=' + (r.parentName || r.parent));
}
console.log('\nclueStatic', out.clueStatic.length, 'total', out.total, 'recTop', out.recTopCount, 'maxId', out.maxId);
