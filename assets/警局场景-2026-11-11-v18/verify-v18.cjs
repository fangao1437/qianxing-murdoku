/* v18 GIA 根层 / 单元数 / 文本包含性 + 楔形拟合结果检查 */
const fs = require('fs');
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets/警局场景-2026-11-11-v18';
const vi = (b, p) => { let v = 0n, s = 0n, i = p; while (i < b.length) { const c = b[i++]; v |= BigInt(c & 127) << s; if (!(c & 128)) break; s += 7n } return [v, i] };
const F = (b) => { const o = []; let p = 0; while (p < b.length) { const [t, q] = vi(b, p); if (q >= b.length) break; p = q; const f = Number(t >> 3n), w = Number(t & 7n);
 if (w === 0) { const [v, r] = vi(b, p); o.push({ f, w, val: Number(v) }); p = r }
 else if (w === 2) { const [l, r] = vi(b, p); const L = Number(l); o.push({ f, w, len: L, d: b.subarray(r, r + L) }); p = r + L }
 else if (w === 5) { o.push({ f, w }); p += 4 } else if (w === 1) { o.push({ f, w }); p += 8 } else break } return o };
for (const f of ['murdoku-police-v18-text.gia', 'murdoku-police-v18-notext.gia']) {
  const p = DIR + '/' + f;
  if (!fs.existsSync(p)) { console.log(f, 'MISSING'); continue }
  const b = fs.readFileSync(p), L = b.readUInt32BE(16), body = b.subarray(20, 20 + L), top = F(body);
  const f4 = top.find(x => x.f === 4);
  const units = top.filter(x => x.f === 2).length;
  const gi = b.indexOf(Buffer.from('.gia'));
  console.log(`${f} | ${b.length}B | f4=${f4 ? 'YES ❌' : 'NO ✅'} | units=${units} | .gia+4=${gi >= 0 ? b.subarray(gi + 4, gi + 8).toString('hex') : '-'} | containsText=${b.toString('latin1').includes('POLICE TIME')}`);
}
const shadow = JSON.parse(fs.readFileSync(DIR + '/shadow-elements.json', 'utf8'));
console.log('shadow | parts=' + shadow.parts + ' | elements=' + shadow.elements.length +
  ' | colors=' + JSON.stringify([...new Set(shadow.elements.map(e => e.color))]));
const fit = JSON.parse(fs.readFileSync(DIR + '/wedge-fit.json', 'utf8'));
console.log('wedgeFit | polygon=' + JSON.stringify(fit.polygon) + ' | residualMAE=' + fit.residual.mae +
  ' | coverage=' + fit.verification.coverage + '% | overflow=' + fit.verification.overflowVertices +
  ' | elements=' + fit.elements.length);
for (const f of ['scene-v18.json', 'scene-v18-notext.json']) {
  const sc = JSON.parse(fs.readFileSync(DIR + '/' + f, 'utf8'));
  const sh = sc.elements.filter(e => ['#94391A', '#8F381A', '#873619', '#B44926', '#6C2D15'].includes(e.color));
  console.log(f, 'elements=' + sc.elements.length, 'triangles=' + sc.elements.filter(e => e.imageAssetId === 100003).length,
    'shadowShapeElements=' + sh.length + (sh.length === 114 ? ' ✅' : ' ❌'));
}
