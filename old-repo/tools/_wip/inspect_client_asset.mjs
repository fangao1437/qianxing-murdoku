// tools/_wip/inspect_client_asset.mjs —— 查存档里「客户端控件模板」资产的完整结构
//
// 起因（2026-10-06 ✓）：
//   play 日志：★「容器模板 **1073742330** 实例化失败」✗
//   ⇒ 要在模拟器里造一个容器模板 ✓
//   ★ 但 `addTemplate` 的实现要求 `meta.assetType === "client-control-template"` ✗
//     ★ 而本会话是 `server-control-template` ✗ ⇒ ★ 只能直接改【客户端资产】✓
//   ⇒ ★ 得先知道客户端资产长什么样 ✓（★ 上一轮只看了前 300 字符 ⇒ 看不到全部键 ✗）
//
// 用法：node tools/_wip/inspect_client_asset.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const FILE = path.join(root, 'sim-save', 'murdoku.save.json');
const s = JSON.parse(fs.readFileSync(FILE, 'utf8'));

const cl = (s.save && s.save.assets && s.save.assets.client) || null;
console.log('=== save.assets.client ===');
if (!cl) { console.log('  ✗ 没有 client 资产'); process.exit(0); }
console.log('  ★ 完整键（' + Object.keys(cl).length + ' 个）: ' + Object.keys(cl).join(' | '));
for (const k of Object.keys(cl)) {
  const v = cl[k];
  const kind = Array.isArray(v) ? ('数组 ' + v.length) : typeof v;
  console.log('    ' + k.padEnd(16) + kind.padEnd(10) + JSON.stringify(v).slice(0, 120));
}

// 客户端资产里的模板（★ 每个模板一个顶层子节点 ✓ 期望能按 guid 找 ✓）
const r = cl.root;
if (r) {
  console.log('  --- client.root ---');
  console.log('    id=' + r.id + ' kind=' + r.kind + ' name=' + JSON.stringify(r.name) +
    ' guid=' + r.guid + ' 子节点=' + ((r.children || []).length));
  for (const c of (r.children || []).slice(0, 10)) {
    console.log('      ' + String(c.name).padEnd(18) + ' kind=' + String(c.kind).padEnd(12) +
      ' guid=' + c.guid + ' 子节点=' + ((c.children || []).length));
  }
}

// 目标索引 1073742330 在整份存档里出现过吗
const raw = fs.readFileSync(FILE, 'utf8');
console.log('=== 目标索引 ===');
console.log('  "1073742330" 出现 ' + (raw.split('1073742330').length - 1) + ' 次');
console.log('  已知的模板索引候选：1073741876(cfg.cells) · 1073741965(cell.1.1) · 1073742330(待造)');

// 顺便：客户端资产里现有 guid 一览（★ 便于挑一个改 ✓）
const guids = [];
(function walk(n, d) {
  if (!n || d > 8) return;
  if (n.guid) guids.push(n.guid);
  for (const c of (n.children || [])) walk(c, d + 1);
})(r, 0);
console.log('  client 资产里的 guid: ' + guids.join(', '));
