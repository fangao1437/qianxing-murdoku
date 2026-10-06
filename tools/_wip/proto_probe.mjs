import fs from 'node:fs';
import { parseMsg, geomPairs, bigIds, texts, stateBlocks, KNOWN_TYPES } from './tools/gil/gilread.mjs';
const buf = fs.readFileSync('208.1.gil');
const bodyEnd = 20 + buf.readUInt32BE(16);
const tree = { sub: parseMsg(buf, 20, bodyEnd, 0) };
const recs = [];
(function walk(fs) {
  for (const f of fs) {
    if (!f.sub) continue;
    if (geomPairs(f.sub, []).length >= 2 && bigIds(f.sub, []).length >= 1) {
      let deeper = 0;
      for (const c of f.sub) if (c.sub && geomPairs(c.sub, []).length >= 2 && bigIds(c.sub, []).length >= 1) deeper++;
      if (deeper === 0) {
        let parent = null;
        (function s(fs2) { for (const g of fs2) { if (g.wt === 0 && g.field === 504 && parent === null) parent = Number(g.num); if (g.sub) s(g.sub); } })(f.sub);
        const strs = texts(f.sub, []);
        let name = null;
        for (const t of strs) { const s2 = t.payload.toString('utf8'); if (!KNOWN_TYPES.has(s2)) { name = s2; break; } }
        recs.push({ name, id: Number(bigIds(f.sub, [])[0].num), parentId: parent, blocks: stateBlocks(f.sub, []).length });
+        continue;
      }
    }
    walk(f.sub);
  }
})(tree.sub);
for (const n of ['clues','root','home','stage','topbar','home.select','home.title','action.back','hud.title','label','selbtn.1','clues.bg','board.bg','tpl.cell'])
  { const r = recs.find((x) => x.name === n); console.log('  ' + n.padEnd(14) + (r ? ('#' + r.id + '  状态块=' + r.blocks) : '不存在')); }