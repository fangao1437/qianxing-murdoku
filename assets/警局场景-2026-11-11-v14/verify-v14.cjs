/* v14 GIA 根层 / 单元数 / 文本包含性检查 */
const fs = require('fs');
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets/警局场景-2026-11-11-v14';
const vi = (b, p) => { let v = 0n, s = 0n, i = p; while (i < b.length) { const c = b[i++]; v |= BigInt(c & 127) << s; if (!(c & 128)) break; s += 7n } return [v, i] };
const F = (b) => { const o = []; let p = 0; while (p < b.length) { const [t, q] = vi(b, p); if (q >= b.length) break; p = q; const f = Number(t >> 3n), w = Number(t & 7n);
 if (w === 0) { const [v, r] = vi(b, p); o.push({ f, w, val: Number(v) }); p = r }
 else if (w === 2) { const [l, r] = vi(b, p); const L = Number(l); o.push({ f, w, len: L, d: b.subarray(r, r + L) }); p = r + L }
 else if (w === 5) { o.push({ f, w }); p += 4 } else if (w === 1) { o.push({ f, w }); p += 8 } else break } return o };
for (const f of ['murdoku-police-v14-text.gia', 'murdoku-police-v14-notext.gia']) {
  const p = DIR + '/' + f;
  if (!fs.existsSync(p)) { console.log(f, 'MISSING'); continue }
  const b = fs.readFileSync(p), L = b.readUInt32BE(16), body = b.subarray(20, 20 + L), top = F(body);
  const f4 = top.find(x => x.f === 4);
  const units = top.filter(x => x.f === 2).length;
  const gi = b.indexOf(Buffer.from('.gia'));
  console.log(`${f} | ${b.length}B | f4=${f4 ? 'YES ❌' : 'NO ✅'} | units=${units} | .gia+4=${gi >= 0 ? b.subarray(gi + 4, gi + 8).toString('hex') : '-'} | containsText=${b.toString('latin1').includes('POLICE TIME')}`);
}
