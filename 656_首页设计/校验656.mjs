// 656 结构校验：与 655 逐记录比对，确认背景资产/脚本/功能控件未被破坏
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(ROOT, 'qianxing-murdoku/650_全面优化/655_遍历负载优化.gil'));
const B = readGil(path.join(DIR, '656_首页设计.gil'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));
// police-v12 及全部后代
function descendants(g, rootName) {
  const byParent = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byParent.has(k)) byParent.set(k, []); byParent.get(k).push(r.id); }
  const root = g.recs.find(r => r.name === rootName); if (!root) return [];
  const out = new Set([root.id]), q = [root.id];
  while (q.length) for (const c of byParent.get(q.shift()) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v12')), bgB = new Set(descendants(B, 'police-v12'));
const bgChanged = changed.filter(id => bgA.has(id) || bgB.has(id));
const bgAdded = added.filter(id => bgB.has(id));
const bgRemoved = removed.filter(id => bgA.has(id));
// 内嵌脚本：本轮只允许两处定向补丁（删首页四键旧素材引用路线），反向应用后必须逐字节回到 655
const s0 = findScriptLeaf(A).buf.toString('utf8');
const s1 = findScriptLeaf(B).buf.toString('utf8');
const PATCH_A_FROM = '      "modal.exit", "modal.save", "modal.settle", "modal.cancel",\n      "home.select", "home.continue", "home.shop", "home.bag",\n';
const PATCH_A_TO = '      "modal.exit", "modal.save", "modal.settle", "modal.cancel",\n';
const PATCH_B_FROM = 'if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") then';
const PATCH_B_TO = 'if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") and not id:match("^home%.") then';
const restored = s1.replace(PATCH_B_TO, PATCH_B_FROM).replace(PATCH_A_TO, PATCH_A_FROM);
const scriptPatchesOnly = restored === s0;
const routeBlock = s => s.slice(s.indexOf('local STATIC_PATH_655 = {'), s.indexOf('local function path_lookup_655'));
const staticPathTableUnchanged = routeBlock(s0) === routeBlock(s1);
// 删除的 4 个 bg：记录不存在、父 childList 干净、全文件 0 次 id 引用
const deadIds = new Set(removed.map(id => ma.get(id)).filter(r => r && r.name === 'bg').map(r => r.id));
const deadNames = [...deadIds].map(id => {
  const parent = A.recs.find(r => r.id === ma.get(id).parentId);
  return (parent?.name || '?') + '/bg';
});
let dangling = 0;
const scan = f => {
  if (f.wt === 0 && f.num !== undefined && deadIds.has(Number(f.num))) dangling++;
  if (f.payload && !f.isText) { const arr = asIdList(f.payload, true); if (arr) for (const x of arr) if (deadIds.has(x)) dangling++; }
  if (f.sub) f.sub.forEach(scan);
};
B.tree.forEach(scan);
const deletedBgClean = deadIds.size === 4 && dangling === 0 &&
  deadNames.every(n => { const p = B.recs.find(r => r.name === n.split('/')[0]); const c = p && findChildListTop(p.field.sub);
    return !B.recs.some(r => r.parentId === p?.id && r.name === 'bg'); });
// 隐藏位
function hidden(r) {
  const walk = f => {
    if (!f.sub) return false;
    if (f.field === 17 && f.wt === 2 && f.sub && f.sub.some(x => x.field === 503 && Number(x.num) === 1)) return true;
    return f.sub.some(walk);
  };
  return (r.field.sub || []).some(walk);
}
const AUDIT = JSON.parse(fs.readFileSync(path.join(DIR, '656_构建审计.json'), 'utf8'));
const hiddenState = Object.fromEntries(AUDIT.hidden.map(n => {
  const r = B.recs.find(q => q.name === n);
  return [n, r ? hidden(r) : 'MISSING'];
}));
// 新增层可见 / 父级 / recTop 与 childList 顺序一致
const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const parentName = new Set(['grp653.static.1.art641.home', 'home']);
const newRecs = added.map(id => mb.get(id));
const wrongParent = newRecs.filter(r => !parentName.has(ma.get(r.parentId)?.name ?? mb.get(r.parentId)?.name)).map(r => r.name);
const hiddenNew = newRecs.filter(hidden).map(r => r.name);
const parent = mb.get(B.recs.find(r => r.name === 'grp653.static.1.art641.home').id);
const cl = findChildListTop(parent.field.sub), ids = cl ? asIdList(cl.payload, true) : [];
const homeIds = ids.filter(id => order.has(id));
const orderOk = homeIds.every((id, i) => i === 0 || order.get(homeIds[i - 1]) < order.get(id));
// 关键功能控件
const keys = ['home', 'home.title', 'home.select', 'home.continue', 'home.shop', 'home.bag',
  'home.tutorial627.bg', 'home.tutorial627.ring', 'home.tutorial627.label', 'home.tutorial627.hit',
  'art647.home.settle.ribbon', 'police-v12', 'root'];
const missing = keys.filter(n => !B.recs.some(r => r.name === n));
const report = {
  base: '655_遍历负载优化.gil', output: '656_首页设计.gil',
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changedExisting: changed.length,
  changedExistingNames: changed.map(id => ma.get(id).name || ('#' + id)).filter(Boolean),
  policeV12: { descendantsBefore: bgA.size, descendantsAfter: bgB.size,
    changed: bgChanged.length, added: bgAdded.length, removed: bgRemoved.length, untouched: bgChanged.length + bgAdded.length + bgRemoved.length === 0 },
  script: { patchesOnly: scriptPatchesOnly, staticPathTable655Unchanged: staticPathTableUnchanged,
    bytesBefore: Buffer.byteLength(s0), bytesAfter: Buffer.byteLength(s1),
    note: '仅两处补丁：入口层胶囊守卫名单去掉首页四键；btn_list 收集排除 home.*。反向应用后与 655 逐字节相同。' },
  deletedBg: { expected: 4, names: deadNames, danglingReferences: dangling, clean: deletedBgClean },
  hiddenRecords: hiddenState,
  newLayers: { count: newRecs.length, wrongParent, hiddenButShouldBeVisible: hiddenNew,
    childListFollowsRecordOrder: orderOk, homeGroupChildren: homeIds.length },
  keyControlsMissing: missing,
  verdict: (bgChanged.length + bgAdded.length + bgRemoved.length === 0) && scriptPatchesOnly
    && staticPathTableUnchanged && deletedBgClean && removed.length === deadIds.size
    && missing.length === 0 && wrongParent.length === 0 && hiddenNew.length === 0 && orderOk
    && Object.values(hiddenState).every(v => v === true),
};
fs.writeFileSync(path.join(DIR, '656_结构校验.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (!report.verdict) process.exitCode = 1;
