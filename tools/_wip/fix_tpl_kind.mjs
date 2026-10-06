// tools/_wip/fix_tpl_kind.mjs —— 把服务端三个 tpl.* 的 kind 改成 reference
//
// ★ 依据（2026-10-06 第 31 轮 ✓ 从插件 `index.js` 直接读出来的 ✓）：
//   ★ `pt = { …, container:"容器节点", …, **reference:"模板引用控件"**, … }` ✓
//   ★ `ii = ["server-container","container","textbox","cursor","**reference**","grid",
//            "image","button","textwindow","keyhint","animation","fullscreen"]` ✓
//   ★ 而脚本 play 日志原话：★「已把 **1 个模板引用控件**挪出画布」✓
//     ⇒ ★★ 它认的就是 `reference` ✓ —— 而我写成了 `container` ✗ ⇒ **类型错了** ✓
//
// ★ 输入 `PINNED-main-good.json`（★ 服务端三节点的 guid **已是真机值** 1073742330/31/32 ✓
//   —— ★ 因为它是第 29 轮"让开"之前钉的 ✓）⇒ 输出 `fixed.save.json` ✓
//
// 用法：node tools/_wip/fix_tpl_kind.mjs [--apply]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const SRC = path.join(root, 'sim-save', 'PINNED-main-good.json');
const DST = path.join(root, 'sim-save', 'fixed.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(SRC, 'utf8'));
const WANT = { 'tpl-container': 1073742330, 'tpl.stage': 1073742331, 'tpl.cell': 1073742332 };
const log = [];

(function walk(n) {
  const nm = String(n.name);
  if (WANT[nm] !== undefined && n.kind !== 'reference') {
    log.push({ id: n.id, name: nm, guid: n.guid, from: n.kind, to: 'reference', wantGuid: WANT[nm] });
    if (APPLY) n.kind = 'reference';
  }
  for (const c of (n.children || [])) walk(c);
})(s.root);

console.log('=== 服务端三个 tpl.* 现状 ===');
for (const l of log) {
  console.log('  ' + String(l.id).padEnd(7) + l.name.padEnd(15) + 'guid=' + String(l.guid).padEnd(12) +
    'kind ' + l.from + ' → **reference** ✓' + (Number(l.guid) === l.wantGuid ? '' : '  ⚠️ guid 不是真机值（应 ' + l.wantGuid + '）'));
}
if (log.length === 0) console.log('  ✓ 已经是 reference（或找不到）');

// ★ 复核：三者在不在、guid 对不对 ✓
const byName = {};
(function w(n) { byName[n.name] = n; for (const c of (n.children || [])) w(c); })(s.root);
console.log('=== 复核 ===');
for (const [nm, g] of Object.entries(WANT)) {
  const n = byName[nm];
  console.log('  ' + nm.padEnd(15) + (n ? ('存在 ✓ guid=' + n.guid + ' kind=' + n.kind + (Number(n.guid) === g ? ' ✓' : ' ✗应' + g)) : '**不存在** ✗'));
}

if (!APPLY) { console.log('  （只报告 ✓ 要真写加 --apply ✓）'); process.exit(0); }
fs.writeFileSync(DST, JSON.stringify(s));
console.log('  ✓ 已写 ' + path.relative(root, DST) + '（' + (fs.statSync(DST).size / 1048576).toFixed(2) + ' MB）');
console.log('  ★ 下一步：load 它 ⇒ play start ⇒ 判据「选关按钮（脚本创建）：新建 4 个」');
