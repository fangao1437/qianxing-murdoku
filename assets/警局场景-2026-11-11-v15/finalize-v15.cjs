/* v15: 落地交付 + 48px 文字模拟预览 + v14/v15 对比图 */
const fs = require('fs');
const { createCanvas, loadImage } = require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const TMP = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets/警局场景-2026-11-11-v15';
const boxes = [
  { x: 1365, y: 181, w: 480, h: 120, rot: 9 },
  { x: 330, y: 680, w: 480, h: 120, rot: -7.6 },
  { x: 1281, y: 807, w: 480, h: 120, rot: -7.6 },
];
(async () => {
  for (const [src, dst] of [
    ['police-v15.gia', 'murdoku-police-v15-text.gia'],
    ['police-v15-notext.gia', 'murdoku-police-v15-notext.gia'],
    ['police-v15.png', 'preview/police-v15.png'],
    ['police-v15-notext.png', 'preview/police-v15-notext.png'],
    ['scene-v15.json', 'scene-v15.json'],
    ['scene-v15-notext.json', 'scene-v15-notext.json'],
  ]) {
    const p = TMP + '/' + src;
    if (!fs.existsSync(p)) { console.log('MISSING', src); continue; }
    fs.copyFileSync(p, DIR + '/' + dst);
    console.log('copied', dst, fs.statSync(p).size + 'B');
  }
  const src = await loadImage(TMP + '/police-v15-notext.png');
  const s = createCanvas(src.width, src.height), sx = s.getContext('2d'); sx.drawImage(src, 0, 0);
  for (const b of boxes) {
    sx.save(); sx.translate(b.x, b.y); sx.rotate(-b.rot * Math.PI / 180);
    sx.font = '700 48px "Arial Black", Arial, sans-serif'; sx.textAlign = 'center'; sx.textBaseline = 'middle';
    sx.fillStyle = '#241309'; sx.fillText('POLICE TIME', 0, 0); sx.restore();
  }
  fs.writeFileSync(DIR + '/preview/police-v15-simulated.png', s.toBuffer('image/png'));

  const a = await loadImage(DIR.replace('v15', 'v14') + '/preview/police-v14-notext.png');
  const c = createCanvas(1600, 1800), q = c.getContext('2d');
  q.drawImage(a, 0, 0); q.drawImage(src, 0, 900);
  q.fillStyle = '#ffffff'; q.font = 'bold 30px sans-serif';
  q.fillText('v14 (square vignette / sharp seam)', 20, 40); q.fillText('v15 (official radial vignette / soft seam)', 20, 940);
  fs.writeFileSync(DIR + '/preview/compare-v14-vs-v15.png', c.toBuffer('image/png'));
  console.log('wrote simulated + compare');
})();
