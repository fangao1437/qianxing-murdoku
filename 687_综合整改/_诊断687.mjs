// 687 · 诊断：从 686 存档读出四类问题相关的全部控件
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const REPO = path.resolve('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku');
const url = p => pathToFileURL(p).href;
const G = await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { setHiddenRecord, isHiddenRecord } = await import(url(path.resolve('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const FILE = path.join(REPO, '686_X标记离场收起/686_X标记离场收起.gil');
const g = G.readGil(FILE);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);

function info(r) {
  const sts = G.stateBlocks(r.field.sub, []);
  const geo = sts.map(st => {
    const p = G.pairOf(st, 504), s = G.pairOf(st, 505);
    return p && s ? [G.pairValue(p, 0), G.pairValue(p, 1), G.pairValue(s, 0), G.pairValue(s, 1)] : null;
  });
  const imgs = ns(r.field, [505, 503, 84]).map(p => {
    const c = p.sub.find(x => x.field === 502 && x.wt === 0);
    const im = p.sub.find(x => x.field === 503 && x.wt === 0);
    const use = p.sub.find(x => x.field === 504 && x.wt === 0);
    return { color: c ? hex(c.num) : null, imageId: im ? Number(im.num) : null, useTint: use ? Number(use.num) : null };
  });
  const texts = G.textsOf(r.field.sub, []).map(t => t.payload?.toString('utf8')).filter(t => t && t !== r.name);
  const cl = G.findChildListTop(r.field.sub);
  const kids = cl ? (G.asIdList(cl.payload, true) || []).map(id => byId.get(id)?.name || id) : [];
  return {
    id: r.id, name: r.name, parent: r.parentId != null ? (byId.get(r.parentId)?.name ?? r.parentId) : null,
    geo, imgs, texts, hidden: isHiddenRecord(r.field), kids: kids.length,
  };
}

const out = { file: FILE, records: g.recs.length, maxId: String(g.maxId) };
const groups = {
  settle: n => /settle/i.test(n),
  close: n => /close/i.test(n),
  gridReuse: n => n === 'art657.grid.reuse' || n.startsWith('art656.home.grid') || n.startsWith('art663.grid') || n === 'art656.home.paper.edge',
  popup: n => /^(modal|win|result|help617|hint635|td\.home|art641\.(home|select)|art642\.select)/.test(n),
};
for (const [k, f] of Object.entries(groups)) {
  out[k] = g.recs.filter(r => r.name && f(r.name)).map(info);
}
// 网格纸 49 子层（按 parentId 精确）
const reuse = byName.get('art657.grid.reuse');
out.gridChildren = g.recs.filter(r => r.parentId === reuse.id).map(info);
out.gridParent = info(reuse);
// 所有 close 的父容器信息
out.closeParents = [...new Set(out.close.map(c => c.parent))].map(p => {
  const r = typeof p === 'number' ? byId.get(p) : byName.get(p);
  return r ? info(r) : p;
});
// 顶层弹窗容器候选：名字本身是容器且含 close 子层
out.popupContainers = g.recs.filter(r => r.name && g.recs.some(c => c.parentId === r.id && /close/i.test(c.name || '')))
  .map(r => ({ ...info(r), closeNames: g.recs.filter(c => c.parentId === r.id && /close/i.test(c.name || '')).map(c => c.name) }));

fs.writeFileSync(path.join(REPO, '687_综合整改/_诊断687.json'), JSON.stringify(out, null, 2));
console.log('records', g.recs.length);
console.log('settle', out.settle.length, 'close', out.close.length, 'gridChildren', out.gridChildren.length,
  'popup', out.popup.length, 'popupContainers', out.popupContainers.length);
console.log('\n=== close 控件 ===');
for (const c of out.close) console.log(c.name.padEnd(38), 'parent=' + String(c.parent).padEnd(30), 'geo=' + JSON.stringify(c.geo[0]), 'imgs=' + JSON.stringify(c.imgs[0] || {}), 'hidden=' + c.hidden, 'texts=' + JSON.stringify(c.texts));
console.log('\n=== close 父容器 ===');
for (const p of out.popupContainers) console.log(p.name.padEnd(38), 'geo=' + JSON.stringify(p.geo[0]), 'close=' + JSON.stringify(p.closeNames));
console.log('\n=== settle 相关 ===');
for (const c of out.settle) console.log(c.name.padEnd(46), 'parent=' + String(c.parent).padEnd(28), 'geo=' + JSON.stringify(c.geo[0]), 'imgs=' + JSON.stringify(c.imgs[0] || {}), 'hidden=' + c.hidden, 'texts=' + JSON.stringify(c.texts));
console.log('\n=== 网格纸父 ===', JSON.stringify(out.gridParent.geo[0]), 'kids=', out.gridParent.kids);
console.log('=== 网格纸子层 y 分布 ===');
const ys = out.gridChildren.map(c => c.geo[0] && c.geo[0][1]);
console.log('count', ys.length, 'min', Math.min(...ys), 'max', Math.max(...ys), 'sample', JSON.stringify(out.gridChildren.slice(0, 6).map(c => [c.name, c.geo[0]])));
