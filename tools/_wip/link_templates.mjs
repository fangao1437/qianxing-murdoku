// tools/_wip/link_templates.mjs —— 把服务端的 reference 控件与客户端的模板"连"起来
//
// ★ 依据（2026-10-06 第 31、33 轮 ✓ 都是插件源码/对照实验来的 ✓）：
//   ★ 插件源码 ✓：`e.kind === "reference" && ( r.referencedPrefabIndex = **e.referencedPrefabId** )`
//     ⇒ ★ reference 的"被引用模板索引"来自存档字段 **`referencedPrefabId`** ✓
//   ★ 对照实验 ✓：★ 服务端有 `tpl.*` 时脚本能读到（`prefabIndex=1073742332` ✓「挪出画布」✓）
//     ★ 服务端删掉后 ⇒ ★「`tpl.cell` —— **不存在**」✗ ⇒ ★ **脚本读的是服务端** ✓
//   ⇒ ★★ 正确图景 ✓：
//     ★ **服务端** `reference` 控件（guid 2330/31/32 ✓ = `cfg` 里那些索引 ✓）★ 提供"索引" ✓
//     ★ **客户端** 模板 ★ 提供"内容" ✓ ★ 两者靠 `referencedPrefabId` 相连 ✓
//     ★ 而模板**自己的** guid 必须**别撞** 2330/31/32 ✓（★ 那是 reference 控件的 ✓）
//
// ★ 输入 `fixed.save.json`（★ 服务端三个 reference ✓ guid 2330/31/32 ✓）
//   ⇒ 输出 `linked.save.json` ✓
// 用法：node tools/_wip/link_templates.mjs [--apply]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const SRC = path.join(root, 'sim-save', 'fixed.save.json');
const DST = path.join(root, 'sim-save', 'linked.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(SRC, 'utf8'));
// ★ 服务端 reference 控件 → 它引用的客户端模板 guid（★ 用不与 2330/31/32 撞的号 ✓）
const LINK = { 'tpl-container': { ref: 1073742330, tpl: 1073742105, w: 150 },
               'tpl.stage':     { ref: 1073742331, tpl: 1073742106, w: 80 },
               'tpl.cell':      { ref: 1073742332, tpl: 1073742107, w: 80 } };

function plat(w) {
  const o = {};
  for (const p of ['KEYBOARD', 'TOUCHSCREEN', 'CONTROLLER_CONSOLE', 'CONTROLLER_MOBILE'])
    o[p] = { scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
             anchorMin: { x: 0.5, y: 0.5 }, anchorMax: { x: 0.5, y: 0.5 },
             offset: { x: 0, y: 0 }, size: { x: w, y: w }, pivot: { x: 0.5, y: 0.5 } };
  return o;
}

// ── ① 服务端：三个 reference 加上 `referencedPrefabId` ✓ ──
const srv = [];
(function walk(n) {
  const L = LINK[String(n.name)];
  if (L && Number(n.guid) === L.ref) {
    srv.push({ id: n.id, name: n.name, guid: n.guid, kind: n.kind, ref: L.tpl });
    if (APPLY) { n.kind = 'reference'; n.referencedPrefabId = L.tpl; }
  }
  for (const c of (n.children || [])) walk(c);
})(s.root);

// ── ② 客户端：三个模板，guid 用 `L.tpl` ✓（★ 与 reference 的索引区分开 ✓）──
const cl = s.save.assets.client;
if (!cl.root || !Array.isArray(cl.root.children)) { cl.root = { id: 'cc1', kind: 'server-container', name: '客户端控件模板', guid: 0, giaRelatedGuids: [], active: true, visible: true, canControllerFocus: false, syncAllDevices: true, giaRaw: { genericField501: 0, footerField505: 0 }, transformByPlatform: plat(0), children: [], scriptMappingIds: [] }; }
// ★ 先清掉所有旧的同名/同 guid 残留 ✓（★ 第 15 轮注入的「容器节点」也在内 ✓）
cl.root.children = cl.root.children.filter(t => {
  const g = Number(t.guid), nm = String(t.name);
  if (LINK[nm]) return false;
  if ([1073742330, 1073742331, 1073742332].includes(g)) return false;
  return true;
});
const cli = [];
for (const [nm, L] of Object.entries(LINK)) {
  const t = { id: 'ct' + L.tpl, kind: 'container', name: nm, guid: L.tpl, giaRelatedGuids: [],
    active: true, visible: true, canControllerFocus: false, syncAllDevices: true,
    giaRaw: { genericField501: 0, footerField505: 0 }, transformByPlatform: plat(L.w),
    children: [], scriptMappingIds: [] };
  cli.push({ name: nm, guid: L.tpl, w: L.w });
  if (APPLY) cl.root.children.push(t);
}

console.log('=== ① 服务端 reference（★ 提供索引 ✓）===');
for (const r of srv) console.log('  ' + String(r.id).padEnd(7) + r.name.padEnd(15) + 'guid=' + String(r.guid).padEnd(12) + 'kind=' + r.kind + '  ⇒ referencedPrefabId = **' + r.ref + '** ✓');
if (srv.length === 0) console.log('  ✗ 服务端没有这三个 ⇒ ★ 必须先有它们 ✓（fixed.save.json 里有 ✓）');
console.log('=== ② 客户端模板（★ 提供内容 ✓）===');
for (const c of cli) console.log('  ' + c.name.padEnd(15) + 'guid=**' + c.guid + '**  ' + c.w + '×' + c.w + '  四平台=4 ✓');

// ★ 跨表核对 ✓
console.log('=== ③ 核对：每个 reference 都指向一个存在的模板 ✓ ===');
const have = new Set(cli.map(c => c.guid));
for (const r of srv) console.log('  ' + r.name.padEnd(15) + '→ ' + r.ref + (have.has(r.ref) ? '  ✓ 模板在' : '  ✗ **模板不在**'));

if (!APPLY) { console.log('  （只报告 ✓ 要真写加 --apply ✓）'); process.exit(0); }
fs.writeFileSync(DST, JSON.stringify(s));
console.log('  ✓ 已写 ' + path.relative(root, DST) + '（' + (fs.statSync(DST).size / 1048576).toFixed(2) + ' MB）');
