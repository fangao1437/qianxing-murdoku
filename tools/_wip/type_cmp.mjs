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
          let name = null; const types = [];
          for (const t of strs) { const s2 = t.payload.toString('utf8'); if (KNOWN_TYPES.has(s2)) types.push(s2); else if (name === null) name = s2; }
          out.push({ name, id: Number(bigIds(f.sub, [])[0].num), parent, types });
        }
        continue;
      }
      walk(f.sub);
    }
  })(tree.sub);
  return out;
}
const a = recsOf('208.1.gil');
const b = recsOf('210-弹窗四键控件.gil');
const am = new Map(a.map((r) => [r.name, r]));
console.log('  208.1 记录 ' + a.length + '   210 记录 ' + b.length);
for (const want of ['root','stage','clues','board','home','modal','modal.title','modal.exit','modal.cancel','home.select','action.back','hud.title']) {
  const ra = am.get(want);
  const rb = b.find((r) => r.name === want);
  console.log('  ' + want.padEnd(14) + ' 208=[' + (ra ? ra.types.join('|') : '缺') + ']   210=[' + (rb ? rb.types.join('|') : '缺') + ']');
}