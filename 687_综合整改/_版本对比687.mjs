// 687 · 跨版本对比结算相关控件几何 + 列出 686 结算按钮子层
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const REPO = path.resolve('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku');
const url = p => pathToFileURL(p).href;
const G = await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const files = {
  656: '656_首页设计/656_首页设计.gil',
  666: '666_线索换位/666_线索换位.gil',
  679: '679_棋盘居中与边缘/679_棋盘居中与边缘.gil',
  680: '680_网格纸与家具层序/680_网格纸与家具层序.gil',
  682: '682_弹窗边框与提示样式/682_弹窗边框与提示样式.gil',
  683: '683_弹窗细线与四键/683_弹窗细线与四键.gil',
  684: '684_结算收紧与教程配色/684_结算收紧与教程配色.gil',
  685: '685_多格家具通用层/685_多格家具通用层.gil',
  686: '686_X标记离场收起/686_X标记离场收起.gil',
};
// 若文件名不同，自动在目录里找唯一 .gil
function resolve(rel) {
  if (fs.existsSync(path.join(REPO, rel))) return path.join(REPO, rel);
  const d = path.join(REPO, path.dirname(rel));
  const f = fs.readdirSync(d).filter(x => x.endsWith('.gil'));
  return f.length ? path.join(d, f[0]) : null;
}
const names = [
  'settle.btn', 'settle.btn.countdown',
  'art647.home.settle.yellow', 'art647.home.settle.text',
  'modal.exit', 'modal.save', 'modal.settle', 'modal.cancel', 'modal.settle.countdown',
  'result.next', 'result.exit', 'result.home', 'result.settle', 'result.settle.countdown',
];
const out = {};
for (const [v, rel] of Object.entries(files)) {
  const f = resolve(rel);
  if (!f) { out[v] = { error: 'missing ' + rel }; continue; }
  const g = G.readGil(f);
  const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
  const row = {};
  for (const n of names) {
    const r = byName.get(n);
    if (!r) { row[n] = null; continue; }
    const st = G.stateBlocks(r.field.sub, [])[0];
    const p = G.pairOf(st, 504), s = G.pairOf(st, 505);
    row[n] = p && s ? [G.pairValue(p, 0), G.pairValue(p, 1), G.pairValue(s, 0), G.pairValue(s, 1)] : null;
  }
  out[v] = { file: path.relative(REPO, f), row };
}
fs.writeFileSync(path.join(REPO, '687_综合整改/_版本对比687.json'), JSON.stringify(out, null, 2));
for (const n of names) {
  console.log('\n' + n);
  for (const [v, o] of Object.entries(out)) console.log('  ' + v, o.row ? JSON.stringify(o.row[n]) : o.error);
}
// 686：modal.settle / result.settle 子层清单
const g = G.readGil(resolve(files[686]));
const byId = new Map(g.recs.map(r => [r.id, r]));
for (const pn of ['modal.settle', 'result.settle', 'settle.btn', 'td.home', 'help617', 'hint635.menu']) {
  const p = g.recs.find(r => r.name === pn);
  if (!p) continue;
  const kids = g.recs.filter(r => r.parentId === p.id);
  console.log('\n子层 ' + pn + ' (' + kids.length + '):', kids.map(r => r.name).join(', '));
}
