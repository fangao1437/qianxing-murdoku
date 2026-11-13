// 673 诊断：盘点 672 存档中「注释票券」与「拍立得火漆/红色底图圆扣」的全部相关记录
// 输出 673_盘点.json：名字 / id / 父 / 隐藏 / 几何 / imageId / 颜色 / recTop 层序
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const FILE = ROOT + '/qianxing-murdoku/672_梯形与异色区/672_梯形与异色区.gil';
const g = readGil(FILE);
const recTop = g.tree.find(q => q.field === 9);
const order = new Map(recTop.sub.map((f, i) => [f, i]));
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);

function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  const rf = st?.sub?.find(q => q.field === 508);
  if (!p || !s) return null;
  return {
    cx: +(800 + pairValue(p, 0)).toFixed(2), cy: +(450 - pairValue(p, 1)).toFixed(2),
    w: +pairValue(s, 0).toFixed(2), h: +pairValue(s, 1).toFixed(2),
    rot: rf?.sub?.[0]?.f != null ? +rf.sub[0].f.toFixed(3) : null,
  };
}
function art(r) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) return null;
  const c = p.sub?.find(q => q.field === 502), i = p.sub?.find(q => q.field === 503);
  return {
    color: c?.num != null ? '#' + (Number(c.num & 0xFFFFFFn)).toString(16).padStart(6, '0').toUpperCase() : null,
    imageId: i?.num != null ? Number(i.num) : null,
  };
}
const KEY = /(tab|wax|seal|pin|help|sticker|dot|hint|art66[1-4]|art657\.game\.flag)/i;
const rows = g.recs.filter(r => r.name && KEY.test(r.name)).map(r => ({
  name: r.name, id: r.id, parentId: r.parentId,
  hidden: isHiddenRecord(r.field), order: order.get(r.field) ?? null,
  geom: geom(r), ...(art(r) || {}),
})).sort((a, b) => (a.order ?? 1e9) - (b.order ?? 1e9));

const hiddenAll = g.recs.filter(r => isHiddenRecord(r.field)).length;
const out = {
  file: FILE, records: g.recs.length, recTopFields: recTop.sub.length,
  hiddenAll, relatedCount: rows.length,
  byPrefix: Object.fromEntries(['art641.game.help.tab', 'art661.tab', 'art663.tab', 'art664.tab',
    'art663.wax', 'art664.wax', 'art657.game.flag', 'clues.help'].map(p =>
    [p, rows.filter(r => r.name.startsWith(p)).length])),
  rows,
};
fs.writeFileSync(ROOT + '/qianxing-murdoku/673_注释按钮与底图/673_盘点.json', JSON.stringify(out, null, 2));
console.log(JSON.stringify({ records: out.records, recTopFields: out.recTopFields,
  hiddenAll, relatedCount: out.relatedCount, byPrefix: out.byPrefix }, null, 2));
