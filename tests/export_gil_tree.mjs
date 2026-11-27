// tests/export_gil_tree.mjs —— 从指定 .gil 导出真实 UI 控件树为 Lua 模块（供 tests/perf_verify_748.lua 等离线高仿真验证使用）
// 用法：node tests/export_gil_tree.mjs [gilPath] [outLuaPath]
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { loadTree } from '../tools/gil/gilwrite.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const gilPath = path.resolve(process.argv[2] || path.join(repo, '747_交互闭环与尾部消峰/747_交互闭环与尾部消峰.gil'));
const outPath = path.resolve(process.argv[3] || path.join(os.tmpdir(), 'murdoku_gil_tree.lua'));

const g = loadTree(gilPath);
const byId = new Map();
for (const r of g.recs) {
  byId.set(r.id, { id: r.id, name: r.name || '', parent: r.parentId ?? null, kids: [] });
}
const roots = [];
for (const n of byId.values()) {
  if (n.parent != null && byId.has(n.parent)) {
    byId.get(n.parent).kids.push(n);
  } else {
    roots.push(n);
  }
}

const esc = (s) => JSON.stringify(String(s || ''));
const lines = ['return {'];
function emit(node, indent) {
  const kpart = node.kids.length ? '' : '}';
  lines.push(`${indent}{id=${node.id},name=${esc(node.name)},kids={${kpart}`);
  if (node.kids.length) {
    for (const k of node.kids) emit(k, indent + ' ');
    lines.push(`${indent}}},`);
  } else {
    lines[lines.length - 1] += '},';
  }
}
for (const r of roots) emit(r, ' ');
lines.push('}');

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
console.log(`EXPORTED_TREE recs=${g.recs.length} roots=${roots.length} out=${outPath}`);
