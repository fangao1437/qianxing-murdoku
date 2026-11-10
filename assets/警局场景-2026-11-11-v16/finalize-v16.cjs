/* v16: 落地交付 + 48px 文字模拟预览 + 对比图 */
const fs = require('fs');
const { createCanvas, loadImage } = require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const TMP = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const ROOT = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets';
const DIR = ROOT + '/警局场景-2026-11-11-v16';
const DESIGN = 'D:/新建文件夹/miHoYo Launcher/_work/tmp-v16-ref/design-1600.png';
const boxes = [
  { x: 1365, y: 181, w: 480, h: 120, rot: 9 },
  { x: 330, y: 680, w: 480, h: 120, rot: -7.6 },
  { x: 1281, y: 807, w: 480, h: 120, rot: -7.6 },
];
(async () => {
  for (const [src, dst] of [
    ['police-v16.gia', 'murdoku-police-v16-text.gia'],
    ['police-v16-notext.gia', 'murdoku-police-v16-notext.gia'],
    ['police-v16.png', 'preview/police-v16.png'],
    ['police-v16-notext.png', 'preview/police-v16-notext.png'],
    ['scene-v16.json', 'scene-v16.json'],
    ['scene-v16-notext.json', 'scene-v16-notext.json'],
  ]) {
    const p = TMP + '/' + src;
    if (!fs.existsSync(p)) { console.log('MISSING', src); continue; }
    fs.copyFileSync(p, DIR + '/' + dst);
    console.log('copied', dst, fs.statSync(p).size + 'B');
  }
  const src = await loadImage(TMP + '/police-v16-notext.png');
  const s = createCanvas(src.width, src.height), sx = s.getContext('2d'); sx.drawImage(src, 0, 0);
  for (const b of boxes) {
    sx.save(); sx.translate(b.x, b.y); sx.rotate(-b.rot * Math.PI / 180);
    sx.font = '700 48px "Arial Black", Arial, sans-serif'; sx.textAlign = 'center'; sx.textBaseline = 'middle';
    sx.fillStyle = '#241309'; sx.fillText('POLICE TIME', 0, 0); sx.restore();
  }
  fs.writeFileSync(DIR + '/preview/police-v16-simulated.png', s.toBuffer('image/png'));

  const a = await loadImage(ROOT + '/警局场景-2026-11-11-v15/preview/police-v15-notext.png');
  const c = createCanvas(1600, 1800), q = c.getContext('2d');
  q.drawImage(a, 0, 0); q.drawImage(src, 0, 900);
  q.fillStyle = '#ffffff'; q.font = 'bold 30px sans-serif';
  q.fillText('v15 (flat opaque shadow / fang gap)', 20, 40);
  q.fillText('v16 (design-matched 0.82 dim / 2nd obtuse triangle)', 20, 940);
  fs.writeFileSync(DIR + '/preview/compare-v15-vs-v16.png', c.toBuffer('image/png'));

  if (fs.existsSync(DESIGN)) {
    const d = await loadImage(DESIGN);
    const c2 = createCanvas(1600, 1800), q2 = c2.getContext('2d');
    q2.drawImage(d, 0, 0); q2.drawImage(src, 0, 900);
    q2.fillStyle = '#ffffff'; q2.font = 'bold 30px sans-serif';
    q2.fillText('design 1920x1080 -> 1600x900', 20, 40); q2.fillText('v16', 20, 940);
    fs.writeFileSync(DIR + '/preview/design-vs-v16.png', c2.toBuffer('image/png'));
  }
  console.log('wrote simulated + 2 compare images');
})();
