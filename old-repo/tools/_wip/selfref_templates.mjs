// tools/_wip/selfref_templates.mjs —— 复刻真机的"自引用"：reference.ref 与模板 guid 同号
//
// ★ 依据（2026-10-06 第 36 轮 ✓ 真机运行日志 ✓）：
//   ★ 脚本已经**读到了** `tpl.cell  prefabIndex=1073742332  **ref=1073742107（引用的模板）**` ✓✓
//     ⇒ ★ `referencedPrefabId` 这条链路**已被证实有效** ✓
//   ★ 而实例化 `cfg.stage.prefab = 1073742330` 时它报的仍是 **1073742330** ✗
//     ⇒ ★★ 说明它用的是 **控件的 prefabIndex** ✗ 而 `cfg` 里的值必须是 **ref 值** ✓
//   ★ 真机 `cfg.stage.prefab = 1073742330` ✓ ⇒ ★★ 那真机的 ref 值**就等于控件自己的索引** ✓
//     ⇒ ★★★ **自引用**：`tpl-container`(2330) 引用模板 **2330** ✓
//   ⇒ ★ 所以模拟器侧：★ **客户端模板的 guid 也改成 2330/31/32** ✓ 且 ref 同号 ✓
//
// ★ 输入 `linked.save.json` ⇒ 输出 `selfref.save.json` ✓
// 用法：node tools/_wip/selfref_templates.mjs [--apply]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const SRC = path.join(root, 'sim-save', 'linked.save.json');
const DST = path.join(root, 'sim-save', 'selfref.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(SRC, 'utf8'));
// ★ 名字 → 目标号（★ reference 的 guid 与模板 guid 用同一个 ✓）
const T = { 'tpl-container': 1073742330, 'tpl.stage': 1073742331, 'tpl.cell': 1073742332 };

// ① 客户端：三个模板的 guid 改成目标号 ✓
const cl = s.save.assets.client;
const rows = [];
for (const t of (cl.root.children || [])) {
  const g = T[String(t.name)];
  if (g === undefined) continue;
  const good = !!(t.transformByPlatform && Object.keys(t.transformByPlatform).length === 4);
  rows.push({ id: t.id, name: t.name, from: t.guid, to: g, fourPlat: good, kind: t.kind });
  if (APPLY) { t.guid = g; t.kind = 'container'; }
}

// ② 服务端：三个 reference 的 referencedPrefabId 改成同号 ✓
const srv = [];
(function walk(n) {
  const g = T[String(n.name)];
  if (g !== undefined && n.kind === 'reference') {
    srv.push({ id: n.id, name: n.name, guid: n.guid, was: n.referencedPrefabId, to: g });
    if (APPLY) n.referencedPrefabId = g;
  }
  for (const c of (n.children || [])) walk(c);
})(s.root);

console.log('=== ① 客户端模板（★ guid → 与 reference 同号 ✓）===');
for (const r of rows) console.log('  ' + String(r.name).padEnd(15) + String(r.from).padEnd(12) + '→ **' + r.to + '**  ' + r.kind + '  四平台=' + r.fourPlat);
console.log('=== ② 服务端 reference（★ referencedPrefabId → 同号 ✓ = 自引用 ✓）===');
for (const r of srv) console.log('  ' + String(r.name).padEnd(15) + 'guid=' + String(r.guid).padEnd(12) + 'ref ' + r.was + ' → **' + r.to + '**');

// ③ 冲突自查 ✓
const cg = {}; for (const t of (cl.root.children || [])) { const k = Number(t.guid); cg[k] = (cg[k] || 0) + 1; }
console.log('=== ③ 客户端重复 guid = ' + Object.entries(cg).filter(([, v]) => v > 1).length + '（★ 应 0 ✓）===');

if (!APPLY) { console.log('  （只报告 ✓ 要真写加 --apply ✓）'); process.exit(0); }
fs.writeFileSync(DST, JSON.stringify(s));
console.log('  ✓ 已写 ' + path.relative(root, DST) + '（' + (fs.statSync(DST).size / 1048576).toFixed(2) + ' MB）');
