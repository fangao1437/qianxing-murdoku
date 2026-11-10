/* v19: 落地交付 + 48px 文字模拟预览 + 对比图 */
const fs = require('fs');
const { createCanvas, loadImage } = require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const TMP = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const ROOT = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets';
const DIR = ROOT + '/警局场景-2026-11-11-v19';
const DESIGN = 'D:/新建文件夹/miHoYo Launcher/_work/tmp-v16-ref/design-1600.png';
const boxes = [
  { x: 1365, y: 181, w: 480, h: 120, rot: 9 },
  { x: 330, y: 680, w: 480, h: 120, rot: -7.6 },
  { x: 1281, y: 807, w: 480, h: 120, rot: -7.6 },
];
(async () => {
  for (const [src, dst] of [
    ['police-v19.gia', 'murdoku-police-v19-text.gia'],
    ['police-v19-notext.gia', 'murdoku-police-v19-notext.gia'],
    ['police-v19.png', 'preview/police-v19.png'],
    ['police-v19-notext.png', 'preview/police-v19-notext.png'],
    ['scene-v19.json', 'scene-v19.json'],
    ['scene-v19-notext.json', 'scene-v19-notext.json'],
  ]) {
    const p = TMP + '/' + src;
    if (!fs.existsSync(p)) { console.log('MISSING', src); continue; }
    fs.copyFileSync(p, DIR + '/' + dst);
    console.log('copied', dst, fs.statSync(p).size + 'B');
  }
  const src = await loadImage(TMP + '/police-v19-notext.png');
  const s = createCanvas(src.width, src.height), sx = s.getContext('2d'); sx.drawImage(src, 0, 0);
  for (const b of boxes) {
    sx.save(); sx.translate(b.x, b.y); sx.rotate(-b.rot * Math.PI / 180);
    sx.font = '700 48px "Arial Black", Arial, sans-serif'; sx.textAlign = 'center'; sx.textBaseline = 'middle';
    sx.fillStyle = '#241309'; sx.fillText('POLICE TIME', 0, 0); sx.restore();
  }
  fs.writeFileSync(DIR + '/preview/police-v19-simulated.png', s.toBuffer('image/png'));

  const a = await loadImage(ROOT + '/警局场景-2026-11-11-v18/preview/police-v18-notext.png');
  const c = createCanvas(1600, 1800), q = c.getContext('2d');
  q.drawImage(a, 0, 0); q.drawImage(src, 0, 900);
  q.fillStyle = '#ffffff'; q.font = 'bold 30px sans-serif';
  q.fillText('v18 (flat shadow / no tape shade / no lower edge)', 20, 40);
  q.fillText('v19 (design-exact shadow / tape shade / lower hard edge)', 20, 940);
  fs.writeFileSync(DIR + '/preview/compare-v18-vs-v19.png', c.toBuffer('image/png'));

  if (fs.existsSync(DESIGN)) {
    const d = await loadImage(DESIGN);
    const c2 = createCanvas(1600, 1800), q2 = c2.getContext('2d');
    q2.drawImage(d, 0, 0); q2.drawImage(src, 0, 900);
    q2.fillStyle = '#ffffff'; q2.font = 'bold 30px sans-serif';
    q2.fillText('design 1920x1080 -> 1600x900', 20, 40); q2.fillText('v19', 20, 940);
    fs.writeFileSync(DIR + '/preview/design-vs-v19.png', c2.toBuffer('image/png'));

    // 阴影区三联：设计 / v18 / v19
    const box = [900, 40, 1500, 760];
    const trim = im => { const cv = createCanvas(box[2] - box[0], box[3] - box[1]); cv.getContext('2d').drawImage(im, -box[0], -box[1]); return cv; };
    const c3 = createCanvas(600, 2160), q3 = c3.getContext('2d');
    q3.drawImage(trim(d), 0, 0); q3.drawImage(trim(a), 0, 720); q3.drawImage(trim(src), 0, 1440);
    fs.writeFileSync(DIR + '/preview/shadow-design-v18-v19.png', c3.toBuffer('image/png'));

    // 楔形三联（顶部+下半段区域）：设计 / v18 / v19
    const wbox = [390, 210, 490, 720];
    const trimW = im => { const cv = createCanvas(wbox[2] - wbox[0], wbox[3] - wbox[1]); cv.getContext('2d').drawImage(im, -wbox[0], -wbox[1]); return cv; };
    const c4 = createCanvas(300, 1530), q4 = c4.getContext('2d');
    q4.drawImage(trimW(d), 0, 0); q4.drawImage(trimW(a), 0, 510); q4.drawImage(trimW(src), 0, 1020);
    fs.writeFileSync(DIR + '/preview/wedge-design-v18-v19.png', c4.toBuffer('image/png'));
  }
  console.log('wrote simulated + 4 compare images');
})();
