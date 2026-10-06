// tools/_wip/rekey_client_templates.mjs —— 让客户端模板拿到 1073742330/31/32
//
// ★ 依据（2026-10-06 第 31~32 轮 ✓ 从插件源码读出来的 ✓）：
//   ★ `e.kind === "reference" && (r.referencedPrefabIndex = **e.referencedPrefabId**)` ✓
//     ⇒ ★ reference 控件的"被引用模板索引"来自存档字段 **`referencedPrefabId`** ✓
//   ★ 而 ★ `cfg.stage.prefab = 1073742330` 要的是 ★ **被引用模板的索引** ✓（脚本注释 ✓）
//   ⇒ ★★ 所以 **1073742330 应该是【客户端模板】的索引** ✓✓
//   ★★ 而服务端那三个（n2001/n2002/n2003）**占着** 1073742330/31/32 ✗ ⇒ ★ `setControlGuid` 报"已被占用" ✓
//     ★ 且服务端**改不了 guid** ✗（「仅客户端控件…允许修改索引」✓）
//   ⇒ ★★★ 那就 ★ **把服务端那三个删掉** ✓ —— ★ 它们只是我第 20 轮"猜"出来的 ✗
//     真机里 1073742330 是 **模板层的一个模板** ✓（`who.mjs`：`tpl-container` 父=1 ✓）
//
// ★ 输入 `PINNED-main-good.json` ⇒ 输出 `rekeyed.save.json` ✓
// 用法：node tools/_wip/rekey_client_templates.mjs [--apply]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const SRC = path.join(root, 'sim-save', 'PINNED-main-good.json');
const DST = path.join(root, 'sim-save', 'rekeyed.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(SRC, 'utf8'));
const WANT = { 'tpl-container': 1073742330, 'tpl.stage': 1073742331, 'tpl.cell': 1073742332 };

// ── ① 删掉服务端那三个占位节点（★ 它们不是真机里的东西 ✗ 是我第 20 轮猜的 ✓）──
let removed = [];
(function walk(n) {
  if (!Array.isArray(n.children)) return;
  n.children = n.children.filter(c => {
    if (WANT[String(c.name)] !== undefined && c.kind !== 'container') { removed.push(c.name + '(' + c.guid + ')'); return false; }
    if (WANT[String(c.name)] !== undefined) { removed.push(c.name + '(' + c.guid + ')'); return false; }
    return true;
  });
  for (const c of n.children) walk(c);
})(s.root);

// ── ② 客户端资产里把三个模板的 guid 设成真机值 ✓ ──
const cl = s.save && s.save.assets && s.save.assets.client;
const rows = [];
if (cl && cl.root && Array.isArray(cl.root.children)) {
  for (const t of cl.root.children) {
    const nm = String(t.name);
    if (WANT[nm] === undefined) continue;
    rows.push({ id: t.id, name: nm, from: t.guid, to: WANT[nm], kind: t.kind, hasTp: !!t.transformByPlatform });
    if (APPLY) { t.guid = WANT[nm]; t.kind = 'container'; }
  }
  // ★ 缺的补上（★ 形状照 addTemplate 造出来的 ✓ 四平台必须齐 ✓）
  // ★★★ 去重（2026-10-06 第 32 轮补 ✓）：
  //   ★ 第 15 轮注入过一个名叫「容器节点」、guid 1073742330、**没有四平台**的旧节点 ✗
  //   ★ 而它与我新建的 `tpl-container` **抢同一个 guid** ✗ ⇒ ★ `ke()` 会因**重复 id/guid** 出问题 ✓
  //   ⇒ ★ 规则：★ **同 guid 者只留"有四平台"的那个** ✓（★ 合法形状优先 ✓）
  const seen = new Map();
  cl.root.children = cl.root.children.filter(t => {
    const g = Number(t.guid);
    const good = !!(t.transformByPlatform && Object.keys(t.transformByPlatform).length === 4);
    const prev = seen.get(g);
    if (prev === undefined) { seen.set(g, good); return true; }
    if (prev === true && good === false) { rows.push({ id: t.id, name: t.name, from: g, to: '(删除·重复且无四平台)', kind: t.kind, hasTp: false }); return false; }
    if (prev === false && good === true) { rows.push({ id: 'prev', name: '旧同 guid 节点', from: g, to: '(删除·被替换)', kind: '-', hasTp: false }); return true; }
    rows.push({ id: t.id, name: t.name, from: g, to: '(删除·重复)', kind: t.kind, hasTp: good });
    return false;
  }).filter((t, i, a) => {
    // 第二遍：把"被替换"的那个真正删掉 ✓
    const g = Number(t.guid);
    const good = !!(t.transformByPlatform && Object.keys(t.transformByPlatform).length === 4);
    return a.findIndex(x => Number(x.guid) === g && !!(x.transformByPlatform && Object.keys(x.transformByPlatform).length === 4)) === i || good;
  });

  for (const [nm, g] of Object.entries(WANT)) {
    if (cl.root.children.some(t => String(t.name) === nm)) continue;
    const t = { id: 'c' + g, kind: 'container', name: nm, guid: g, giaRelatedGuids: [],
      active: true, visible: true, canControllerFocus: false, syncAllDevices: true,
      giaRaw: { genericField501: 0, footerField505: 0 }, transformByPlatform: {}, children: [], scriptMappingIds: [] };
    for (const p of ['KEYBOARD', 'TOUCHSCREEN', 'CONTROLLER_CONSOLE', 'CONTROLLER_MOBILE']) {
      t.transformByPlatform[p] = { scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
        anchorMin: { x: 0.5, y: 0.5 }, anchorMax: { x: 0.5, y: 0.5 }, offset: { x: 0, y: 0 },
        size: { x: g === 1073742330 ? 150 : 80, y: g === 1073742330 ? 150 : 80 }, pivot: { x: 0.5, y: 0.5 } };
    }
    rows.push({ id: t.id, name: nm, from: '(新建)', to: g, kind: 'container', hasTp: true });
    if (APPLY) cl.root.children.push(t);
  }
}

console.log('=== ① 删除服务端占位（★ ' + removed.length + ' 个 ✓）===');
for (const r of removed) console.log('  ✗ 删掉 ' + r);
console.log('=== ② 客户端模板 guid ===');
for (const r of rows) console.log('  ' + String(r.id).padEnd(8) + r.name.padEnd(15) + String(r.from).padEnd(12) + '→ **' + r.to + '**  kind=' + r.kind + ' 四平台=' + r.hasTp);
if (rows.length === 0) console.log('  ✗ 客户端里没有这三个（★ 需先 addTemplate ✓）');

if (!APPLY) { console.log('  （只报告 ✓ 要真写加 --apply ✓）'); process.exit(0); }
fs.writeFileSync(DST, JSON.stringify(s));
console.log('  ✓ 已写 ' + path.relative(root, DST) + '（' + (fs.statSync(DST).size / 1048576).toFixed(2) + ' MB）');
console.log('  ★ 下一步：load 它 ⇒ play start ⇒ 判据「选关按钮（脚本创建）：新建 4 个」');
