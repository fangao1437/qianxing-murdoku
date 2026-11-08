const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W = 1600, H = 900, BASE = '#B64A20';
function scene(parts) {
  const els = []; let z = 0;
  const add = o => els.push(Object.assign({ id: 'e' + (++z), rotation: 0, opacity: 1, zIndex: z - 1, isBackground: false }, o));
  add({ type: 'image', x: 800, y: 450, width: W, height: H, color: BASE, imageAssetId: 100001, imageType: 'stretch', imageTint: true });
  for (const p of parts) add(Object.assign({ type: 'image', imageType: 'stretch', imageTint: true }, p));
  return { canvas: { width: W, height: H, background: BASE }, elements: els, meta: { sourceType: 'editor', sourceName: 'bgtest3', warnings: [] } };
}
const soft = (x, y, w, h, op) => ({ x, y, width: w, height: h, color: '#000000', imageAssetId: 106056, opacity: op });
const vig = (x, y, w, h, op) => ({ x, y, width: w, height: h, color: '#000000', imageAssetId: 106060, opacity: op });
const C = (r, op) => [soft(0, 0, r, r, op), soft(1600, 0, r, r, op), soft(0, 900, r, r, op), soft(1600, 900, r, r, op)];
const V = {
  m: [soft(1750, 450, 700, 2000, 0.8), ...C(300, 0.72)],
  n: [soft(1700, 450, 900, 1900, 0.62), ...C(340, 0.75)],
  o: [soft(1780, 450, 800, 1700, 0.85), ...C(320, 0.78), vig(800, 450, 2600, 1500, 0.1)],
  p: [soft(1720, 450, 760, 2000, 0.72), ...C(360, 0.70), vig(800, 450, 2400, 1400, 0.1)],
  q: [soft(1750, 450, 850, 1800, 0.72), ...C(320, 0.75)],
  r: [soft(1800, 450, 700, 2000, 0.85), ...C(280, 0.8), vig(800, 450, 3000, 1700, 0.12)],
  s: [soft(1700, 450, 800, 2000, 0.68), soft(1500, 450, 1400, 2000, 0.18), ...C(320, 0.75)],
  t: [soft(1760, 450, 720, 2000, 0.78), ...C(300, 0.75), vig(800, 450, 2600, 1500, 0.08)],
};
(async () => {
  for (const [k, parts] of Object.entries(V)) {
    const r = await fetch('https://qx.070077.xyz/api/export/png', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ scene: scene(parts) }) });
    const b = Buffer.from(await r.arrayBuffer());
    console.log(k, r.status, b.length);
    if (r.ok) fs.writeFileSync(OUT + '/bgtest-' + k + '.png', b);
  }
})();
