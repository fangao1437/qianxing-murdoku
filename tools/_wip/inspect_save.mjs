// tools/_wip/inspect_save.mjs —— 只读检查模拟器存档的结构（排查用）
//
// 为什么要单独一个文件（2026-10-06）：
//   我先前用 `pwsh` 里内联 `node -e "…"` 跑这些检查 ✗ ——
//   ★ **PowerShell 会把里面的引号吃掉** ✗ ⇒ 连续两次语法错 ✓
//   ⇒ ★ 凡是要带引号/正则的 node 片段，**一律写成文件再跑** ✓
//
// 用法：node tools/_wip/inspect_save.mjs [save 路径]
// 默认：sim-save/murdoku.save.json
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ⚠️ 必须用 `fileURLToPath` ✗ —— `new URL(import.meta.url).pathname` 会给中文路径
//   做 **URL 编码**（`新建文件夹` → `%E6%96%B0...` ✓）⇒ ENOENT ✓（第一次就踩了 ✓）
const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const file = process.argv[2] || path.join(root, 'sim-save', 'murdoku.save.json');

const raw = fs.readFileSync(file, 'utf8');
const s = JSON.parse(raw);

console.log('=== 存档：' + path.relative(root, file) + ' （' + (raw.length / 1048576).toFixed(2) + ' MB）===');
console.log('  顶层键: ' + Object.keys(s).join(' | '));

const sv = s.save || {};
console.log('  save.format = ' + JSON.stringify(sv.format));
console.log('  save.name   = ' + JSON.stringify(sv.name));
console.log('  save.assets = ' + Object.keys(sv.assets || {}).join(' | '));

// ── 脚本段（★ 判"内联 source 是不是当前 dist" ✓）────────────────────────
const scripts = (sv.assets && sv.assets.scripts) || s.scripts || [];
console.log('  脚本数 = ' + scripts.length);
for (const sc of scripts) {
  const src = sc.source || '';
  console.log('    guid=' + sc.guid + ' path=' + JSON.stringify(sc.path) +
    ' source长度=' + src.length + (src ? '' : '（空 ⇒ 试玩会回退读 path）'));
}

// ── 客户端模板（★ 这是"容器模板能不能实例化"的关键 ✗）──────────────────
const cl = (sv.assets && sv.assets.client) || null;
console.log('  --- save.assets.client ---');
console.log('    ' + JSON.stringify(cl).slice(0, 300));

// ── 在整份存档里找"客户端控件模板"的特征名 ✓ ─────────────────────────
const marks = ['模板标题', '模板图标', '确认按钮', '按钮文字', 'Lua实例化面板',
  '客户端控件模板', 'client-control-template'];
console.log('  --- 特征名出现位置（★ 用来定位客户端模板那一棵 ✓）---');
for (const m of marks) {
  const i = raw.indexOf('"' + m + '"');
  console.log('    ' + m.padEnd(26) + (i < 0 ? '✗ 不在存档里' : ('位置 ' + i)));
}

// ── 顶层各段体积（★ 判断客户端树藏在哪一段 ✓）────────────────────────
console.log('  --- 顶层各段体积（字符）---');
for (const k of Object.keys(s)) {
  let n = 0;
  try { n = JSON.stringify(s[k]).length; } catch (e) { n = -1; }
  console.log('    ' + k.padEnd(20) + n);
}

// ── tree 是哪一棵 ─────────────────────────────────────────────────────
console.log('  --- s.tree 前 4 项 ---');
for (const n of (s.tree || []).slice(0, 4)) {
  console.log('    id=' + n.id + ' guid=' + n.guid + ' name=' + JSON.stringify(n.name) +
    ' assetType=' + (n.assetType || '-'));
}
