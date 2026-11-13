// 把 .gil 导出成 murdoku-pro/tools/perf_faithful/fake_engine.lua 能加载的树。
// 仓库里 export_tree.mjs 依赖的 murdoku-pro/tools/gil/gilread.mjs 本机缺失（历史记录不齐），
// 这里改用 qianxing-murdoku/tools/gil/gilread.mjs，并补齐它需要的 states / index。
// 用法：node 导出控件树656.mjs <存档.gil> <输出 tree.lua>
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, stateBlocks } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const file = process.argv[2], out = process.argv[3];
if (!file || !out) { console.error('用法：node 导出控件树656.mjs <存档.gil> <输出.lua>'); process.exit(2); }
const g = readGil(file);
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
for (const r of g.recs) { r.states = stateBlocks(r.field.sub, []); r.index = order.get(r.id) ?? 1e9; }
const kids = new Map();
for (const r of g.recs) {
  if (r.parentId == null) continue;
  const k = String(r.parentId);
  if (!kids.has(k)) kids.set(k, []);
  kids.get(k).push(r);
}
for (const a of kids.values()) a.sort((x, y) => x.index - y.index);
const floats = f => (f && f.sub ? f.sub.filter(x => x.wt === 5).map(x => x.f) : []);
function geom(r) {
  const st = (r.states || [])[0];
  if (!st || !st.sub) return [0, 0, 0, 0];
  const p = floats(st.sub.find(x => x.field === 504));
  const s = floats(st.sub.find(x => x.field === 505));
  return [s[0] || 0, s[1] || 0, p[0] || 0, p[1] || 0];
}
const esc = s => String(s ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
const num = v => (Number.isFinite(v) ? +v.toFixed(3) : 0);
function dump(top) {
  const rows = [];
  (function walk(r, p) {
    const i = rows.length + 1;
    const [w, h, x, y] = geom(r);
    rows.push(`{"${esc(r.name)}",${p},${r.id},${num(w)},${num(h)},${num(x)},${num(y)}}`);
    for (const c of kids.get(String(r.id)) || []) walk(c, i);
  })(top, 0);
  return rows;
}
const tops = g.recs.filter(r => r.parentId == null);
const root = tops.find(r => r.name === 'root');
const parts = [`root = {\n${dump(root).join(',\n')}\n}`];
const tpl = [];
for (const t of tops) { if (t === root) continue; tpl.push(`[${t.id}] = {\n${dump(t).join(',\n')}\n}`); }
parts.push(`templates = {\n${tpl.join(',\n')}\n}`);
parts.push(`template_by_name = {\n${tops.filter(t => t !== root && t.name).map(t => `["${esc(t.name)}"]=${t.id}`).join(',\n')}\n}`);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `-- generated from ${path.basename(file)}\nreturn {\n${parts.join(',\n')}\n}\n`);
console.log(JSON.stringify({ file, out, rootNodes: dump(root).length, templates: tpl.length, records: g.recs.length }));
