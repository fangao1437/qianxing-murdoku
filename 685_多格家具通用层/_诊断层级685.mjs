// 685 · 诊断 684.gil 的顶层 / stage / cell 模板 / x 标记 / 家具容器层级
//   目的：找到「X 标记」所在容器与「stage（格子父）」的确切父子关系，
//   以便设计一个对所有跨格家具（任意 kind / span / 尺寸）通用的置顶标记层。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, findChildListTop, asIdList, encodeMsg } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const { isHiddenRecord } = await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const FILE = path.join(ROOT, 'qianxing-murdoku/684_结算收紧与教程配色/684_结算收紧与教程配色.gil');
const g = readGil(FILE);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const stOf = r => stateBlocks(r.field.sub, [])[0];
const geom = r => { const st = stOf(r); if (!st) return null;
  const p = pairOf(st, 504), z = pairOf(st, 505);
  return { pos: p ? [pairValue(p, 0), pairValue(p, 1)] : null,
           size: z ? [pairValue(z, 0), pairValue(z, 1)] : null }; };
const kidsOf = r => { const cl = findChildListTop(r.field.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  return ids.map(id => byId.get(id)).filter(Boolean); };
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const appearance = r => { const ip = ns(r.field, [505, 503, 84])[0];
  return ip ? { color: '#' + (num(ip, 502) ?? 0).toString(16).padStart(8, '0'), img: num(ip, 503) || 100001 } : null; };

const recTop = g.tree.find(q => q.field === 9);
const topCl = recTop ? findChildListTop(recTop.sub || []) : null;
const topIds = topCl ? (asIdList(topCl.payload, true) || []) : [];
console.log('===== ① recTop 顶层记录数 =====', g.recs.length, '字段9子数', recTop?.sub?.length);
console.log('  顶层 childList 条数', topIds.length);

// 关键容器
const KEY = /^(stage|things|board|content|cell\.|tpl|x$|furn|rug_layer|art657\.grid\.reuse|art685)/;
console.log('\n===== ② 关键容器 / 控件 =====');
for (const r of g.recs) {
  if (!r.name || !KEY.test(r.name)) continue;
  const kids = kidsOf(r);
  console.log(' ', r.name.padEnd(34), 'id=' + String(r.id).padEnd(12),
    '父=' + String(byId.get(r.parentId)?.name || r.parentId).padEnd(26),
    'hidden=' + isHiddenRecord(r.field), '子=' + String(kids.length).padStart(3),
    JSON.stringify(geom(r)), JSON.stringify(appearance(r)));
}

console.log('\n===== ③ 名字含 x / furn / rug / obj 的模板层（前 80） =====');
const tm = g.recs.filter(r => /(^|\.)(x|furn|rug_layer|obj\d*|portrait|face|note|content)$/.test(r.name || ''));
for (const r of tm.slice(0, 80))
  console.log(' ', r.name.padEnd(38), 'id=' + String(r.id).padEnd(12),
    '父=' + String(byId.get(r.parentId)?.name || r.parentId).padEnd(30),
    'hidden=' + isHiddenRecord(r.field), JSON.stringify(geom(r)), JSON.stringify(appearance(r)));

// 找 cell.1.1 及其完整子树
const c11 = byName.get('cell.1.1');
console.log('\n===== ④ cell.1.1 子树 =====', c11 ? 'id=' + c11.id : '未找到');
if (c11) {
  const walk = (r, d) => {
    if (d > 4) return;
    console.log('  ' + '  '.repeat(d) + r.name + ' [id=' + r.id + ' hidden=' + isHiddenRecord(r.field) + ']',
      JSON.stringify(geom(r)), JSON.stringify(appearance(r)));
    for (const k of kidsOf(r)) walk(k, d + 1);
  };
  walk(c11, 0);
}

// stage 直接子层（名字）
const stage = byName.get('stage');
console.log('\n===== ⑤ stage 直接子层 =====', stage ? 'id=' + stage.id : '未找到');
if (stage) {
  const ks = kidsOf(stage);
  console.log('  子数', ks.length);
  console.log('  ' + ks.slice(0, 60).map(k => k.name).join(', '));
}

// 内嵌 Lua 关键锚点
const s = findScriptLeaf(g).buf.toString('utf8');
console.log('\n===== ⑥ 内嵌 Lua =====', '字节', Buffer.byteLength(s));
for (const k of ['"rug_layer"', '"furn"', '"x"', 'furn_anchor', 'SetAsLastSibling', 'layer_order', 'enforce_layers', 'cell.%d.%d'])
  console.log('  ', k, '出现', s.split(k).length - 1, '次');
const i = s.indexOf('elseif key == "furn_anchor"');
console.log('  --- furn_anchor 片段 ---\n' + s.slice(i - 120, i + 480));
const j = s.indexOf('elseif key == "x_mark"');
console.log('  --- x_mark 片段 ---\n' + s.slice(j - 80, j + 260));
const k2 = s.indexOf('function Adapter:enforce_layers');
console.log('  --- enforce_layers 片段 ---\n' + s.slice(k2, k2 + 560));

// 导出 JSON 供后续脚本用
const dump = g.recs.filter(r => r.name && KEY.test(r.name)).map(r => ({
  name: r.name, id: r.id, parent: byId.get(r.parentId)?.name || r.parentId,
  hidden: isHiddenRecord(r.field), geom: geom(r), appearance: appearance(r),
  childNames: kidsOf(r).map(k => k.name), bytes: encodeMsg([r.field]).length,
}));
fs.writeFileSync(path.join(DIR, '685_层级清单.json'), JSON.stringify(dump, null, 1));
console.log('\n已导出 685_层级清单.json，共', dump.length, '条');
