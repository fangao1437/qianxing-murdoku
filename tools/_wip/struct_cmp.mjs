import fs from 'node:fs';
import { parseMsg, geomPairs, bigIds, texts, KNOWN_TYPES } from './tools/gil/gilread.mjs';
function recsOf(file) {
  const buf = fs.readFileSync(file);
  const bodyEnd = 20 + buf.readUInt32BE(16);
  const tree = { sub: parseMsg(buf, 20, bodyEnd, 0) };
  const out = [];
  (function walk(fs2) {
    for (const f of fs2) {
      if (!f.sub) continue;
      if (geomPairs(f.sub, []).length >= 2 && bigIds(f.sub, []).length >= 1) {
        let deeper = 0;
        for (const c of f.sub) if (c.sub && geomPairs(c.sub, []).length >= 2 && bigIds(c.sub, []).length >= 1) deeper++;
        if (deeper === 0) {
          let parent = null;
          (function s(fs3) { for (const g of fs3) { if (g.wt === 0 && g.field === 504 && parent === null) parent = Number(g.num); if (g.sub) s(g.sub); } })(f.sub);
          const strs = texts(f.sub, []);
          let name = null;
          for (const t of strs) { const s2 = t.payload.toString('utf8'); if (!KNOWN_TYPES.has(s2)) { name = s2; break; } }
          out.push({ name, id: Number(bigIds(f.sub, [])[0].num), parent });
        }
        continue;
      }
      walk(f.sub);
    }
  })(tree.sub);
  return out;
}
for (const file of ['208.1.gil', '210-弹窗四键控件.gil']) {
  const r = recsOf(file);
  const ids = r.map((x) => x.id);
  const idSet = new Set(ids);
  const orphans = r.filter((x) => x.parent !== null && x.parent !== 1 && !idSet.has(x.parent));
  console.log('  ' + file);
  console.log('    记录 ' + r.length + '   ID 段 ' + Math.min(...ids) + ' ~ ' + Math.max(...ids));
  console.log('    父不存在的控件 ' + orphans.length + (orphans.length ? ' → ' + orphans.slice(0, 8).map((o) => (o.name || '?') + '(父' + o.parent + ')').join(', ') : ' ✓'));
  const zero = r.filter((x) => x.id === 0 || !Number.isFinite(x.id));
  console.log('    ID 异常 ' + zero.length);
}
console.log('  ── 210 比 208.1 多出来的 ID 段 ──');
const a = recsOf('208.1.gil'); const b = recsOf('210-弹窗四键控件.gil');
const aIds = new Set(a.map((x) => x.id));
const nw = b.filter((x) => !aIds.has(x.id));
console.log('    新增 ' + nw.length + ' 条   ID ' + Math.min(...nw.map((x) => x.id)) + ' ~ ' + Math.max(...nw.map((x) => x.id)));
console.log('    208.1 的最大 ID = ' + Math.max(...a.map((x) => x.id)));