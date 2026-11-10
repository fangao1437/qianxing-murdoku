/* v14: 落地交付文件 + 48px 粗体文字模拟预览 + v13/v14 对比图 */
const fs = require('fs');
const { createCanvas, loadImage } = require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const TMP = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets/警局场景-2026-11-11-v14';
const boxes = [
  { x: 1365, y: 181, w: 480, h: 120, rot: 9 },
  { x: 330, y: 680, w: 480, h: 120, rot: -7.6 },
  { x: 1281, y: 807, w: 480, h: 120, rot: -7.6 },
];
(async () => {
  for (const [src, dst] of [
    ['police-v14.gia', 'murdoku-police-v14-text.gia'],
    ['police-v14-notext.gia', 'murdoku-police-v14-notext.gia'],
    ['police-v14.png', 'preview/police-v14.png'],
    ['police-v14-notext.png', 'preview/police-v14-notext.png'],
    ['scene-v14.json', 'scene-v14.json'],
    ['scene-v14-notext.json', 'scene-v14-notext.json'],
  ]) {
    const p = TMP + '/' + src;
    if (!fs.existsSync(p)) { console.log('MISSING', src); continue; }
    fs.copyFileSync(p, DIR + '/' + dst);
    console.log('copied', dst, fs.statSync(p).size + 'B');
  }
  const src = await loadImage(TMP + '/police-v14-notext.png');
  const s = createCanvas(src.width, src.height), sx = s.getContext('2d'); sx.drawImage(src, 0, 0);
  for (const b of boxes) {
    sx.save(); sx.translate(b.x, b.y); sx.rotate(-b.rot * Math.PI / 180);
    sx.font = '700 48px "Arial Black", Arial, sans-serif'; sx.textAlign = 'center'; sx.textBaseline = 'middle';
    sx.fillStyle = '#241309'; sx.fillText('POLICE TIME', 0, 0); sx.restore();
  }
  fs.writeFileSync(DIR + '/preview/police-v14-simulated.png', s.toBuffer('image/png'));

  // v13 离线导出 vs v14；另存 v13 实机 vs v14
  const a = await loadImage(DIR.replace('v14', 'v13') + '/preview/police-v13-notext.png');
  const b = src;
  const c = createCanvas(1600, 1800), q = c.getContext('2d');
  q.drawImage(a, 0, 0); q.drawImage(b, 0, 900);
  q.fillStyle = '#ffffff'; q.font = 'bold 30px sans-serif';
  q.fillText('v13 (before)', 20, 40); q.fillText('v14 (native primitives)', 20, 940);
  fs.writeFileSync(DIR + '/preview/compare-v13-vs-v14.png', c.toBuffer('image/png'));

  const live = await loadImage('C:/Users/18182/AppData/Local/Temp/v13shot/s3-live-1600.png');
  const c2 = createCanvas(1600, 1800), q2 = c2.getContext('2d');
  q2.drawImage(live, 0, 0); q2.drawImage(b, 0, 900);
  q2.fillStyle = '#ffffff'; q2.font = 'bold 30px sans-serif';
  q2.fillText('v13 LIVE (user screenshot)', 20, 40); q2.fillText('v14', 20, 940);
  fs.writeFileSync(DIR + '/preview/compare-v13live-vs-v14.png', c2.toBuffer('image/png'));
  console.log('wrote simulated + compares');
})();
