// 667 盘点：对比 5xx 旧档与 666 的线索卡「染色层 / 描边层」实现
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));
const FILES = {
  '515': ROOT + '/qianxing-murdoku/515-一二关美术-v310.gil',
  '523': ROOT + '/qianxing-murdoku/523-一二关美术-v315.gil',
  '544': ROOT + '/qianxing-murdoku/544-一二关美术-v327.gil',
  '650': ROOT + '/qianxing-murdoku/650_全面优化/650_优化版.gil',
  '656': ROOT + '/qianxing-murdoku/656_首页设计/656_首页设计.gil',
  '666': ROOT + '/qianxing-murdoku/666_线索换位/666_线索换位.gil',
};
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const out = {};
for (const [ver, file] of Object.entries(FILES)) {
  if (!fs.existsSync(file)) { console.log(ver, 'MISSING', file); continue; }
  const g = readGil(file);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const rows = g.recs.map(r => {
    const st = stateBlocks(r.field.sub, [])[0];
    const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
    const ip = ns(r.field, [505, 503, 84])[0];
    const c = ip ? num(ip, 502) : null;
    return {
      o: order.get(r.field) ?? -1, id: r.id, name: r.name || '',
      parent: byId.get(r.parentId)?.name || (r.parentId ? '#' + r.parentId : 'ROOT'),
      hidden: isHiddenRecord(r.field),
      cx: p ? +(800 + pairValue(p, 0)).toFixed(1) : 0,
      cy: p ? +(450 - pairValue(p, 1)).toFixed(1) : 0,
      w: s ? +pairValue(s, 0).toFixed(1) : 0,
      h: s ? +pairValue(s, 1).toFixed(1) : 0,
      color: c === null ? '-' : '#' + (c >>> 0).toString(16).padStart(8, '0').toUpperCase(),
      img: ip ? num(ip, 503) : null,
    };
  });
  // 线索卡相关：名字含 clue / backrop / card / 卡 / 染色 / outline / border / hi / select
  const clue = rows.filter(r => /clue|backrop|card|染色|描边|outline|border/i.test(r.name));
  // 两个 clue 模板根 + 其子层（按父名含 clue / 直接是模板 id）
  const tplRoots = clue.filter(r => /^clue\d?$/i.test(r.name));
  const tplIds = new Set(tplRoots.map(r => r.id));
  const layers = rows.filter(r => tplIds.has(r.id) || /clue\d?\.|backrop|art6\d\d\.clue/i.test(r.name));
  out[ver] = { total: g.recs.length, clueCount: clue.length, tplRoots: tplRoots.map(r => r.name + '#' + r.id), layers };
  console.log('\n========== ' + ver + ' recs=' + g.recs.length + ' clue层=' + clue.length + ' 模板=' + JSON.stringify(tplRoots.map(r => r.name)) + ' ==========');
  const fmt = r => [String(r.o).padStart(5), r.hidden ? 'H' : ' ', r.name.padEnd(42),
    `${String(r.cx).padStart(6)},${String(r.cy).padStart(6)} ${String(r.w).padStart(6)}x${String(r.h).padStart(6)}`,
    r.color.padEnd(11), 'img=' + String(r.img).padEnd(7), r.parent].join(' ');
  // 只打印模板内部层（最有价值），按层序
  layers.sort((a, b) => a.o - b.o);
  layers.slice(0, 70).forEach(r => console.log(fmt(r)));
  if (layers.length > 70) console.log('... 共 ' + layers.length + ' 层');
}
fs.writeFileSync(path.join(ROOT, 'qianxing-murdoku/666_线索换位/_667_盘点.json'), JSON.stringify(out, null, 2));
console.log('\n→ _667_盘点.json');
