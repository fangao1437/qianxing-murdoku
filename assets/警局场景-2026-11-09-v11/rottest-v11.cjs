const fs = require('fs');
const OUT = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
function sc(rot) {
  return { canvas: { width: 1600, height: 900, background: '#101010' }, elements: [
    { id: 'e0', type: 'image', x: 800, y: 450, width: 1600, height: 900, rotation: 0, color: '#101010', opacity: 1, zIndex: 0, isBackground: false, imageAssetId: 100001, imageType: 'stretch', imageTint: true },
    { id: 'e1', type: 'image', x: 800, y: 450, width: 500, height: 340, rotation: rot, color: '#FFFFFF', opacity: 1, zIndex: 1, isBackground: false, imageAssetId: 100001, imageType: 'stretch', imageTint: true },
  ], meta: { sourceType: 'editor', sourceName: 'rottest', warnings: [] } };
}
(async () => {
  for (const r of [8, -8, 14, -14]) {
    const res = await fetch('https://qx.070077.xyz/api/export/png', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ scene: sc(r) }) });
    const b = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(OUT + '/rottest-' + (r > 0 ? 'p' : 'n') + Math.abs(r) + '.png', b);
    console.log(r, res.status, b.length);
  }
})();
