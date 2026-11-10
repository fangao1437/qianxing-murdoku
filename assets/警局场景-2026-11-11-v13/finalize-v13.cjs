/* v13: 把临时目录的导出结果落到交付目录 + 48px 粗体文字模拟预览 + 对比图 */
const fs = require('fs');
const { createCanvas, loadImage } = require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const TMP = 'C:/Users/18182/AppData/Local/Temp/wb-art-build';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/assets/警局场景-2026-11-11-v13';
const boxes = [
  { x: 1365, y: 181, w: 480, h: 120, rot: 9 },
  { x: 330, y: 680, w: 480, h: 120, rot: -7.6 },
  { x: 1281, y: 807, w: 480, h: 120, rot: -7.6 },
];
(async () => {
  // 1. 结果文件（与 v12 同格式同命名口径）
  for (const [src, dst] of [
    ['police-v13.gia', 'murdoku-police-v13-text.gia'],
    ['police-v13-notext.gia', 'murdoku-police-v13-notext.gia'],
    ['police-v13.png', 'preview/police-v13.png'],
    ['police-v13-notext.png', 'preview/police-v13-notext.png'],
    ['scene-v13.json', 'scene-v13.json'],
    ['scene-v13-notext.json', 'scene-v13-notext.json'],
  ]) {
    const p = TMP + '/' + src;
    if (!fs.existsSync(p)) { console.log('MISSING', src); continue; }
    fs.copyFileSync(p, DIR + '/' + dst);
    console.log('copied', dst, fs.statSync(p).size + 'B');
  }

  // 2. 模拟文字预览（预览器把文本框画成固定小字）
  const src = await loadImage(TMP + '/police-v13-notext.png');
  const s = createCanvas(src.width, src.height), sx = s.getContext('2d'); sx.drawImage(src, 0, 0);
  for (const b of boxes) {
    sx.save(); sx.translate(b.x, b.y); sx.rotate(-b.rot * Math.PI / 180);
    sx.font = '700 48px "Arial Black", Arial, sans-serif'; sx.textAlign = 'center'; sx.textBaseline = 'middle';
    sx.fillStyle = '#241309'; sx.fillText('POLICE TIME', 0, 0); sx.restore();
  }
  fs.writeFileSync(DIR + '/preview/police-v13-simulated.png', s.toBuffer('image/png'));

  // 3. v12(当前 API 同口径基线) vs v13 并排
  const a = await loadImage(TMP + '/baseline-v12-api.png');
  const b = await loadImage(TMP + '/police-v13-notext.png');
  const c = createCanvas(1600, 1800), q = c.getContext('2d');
  q.drawImage(a, 0, 0); q.drawImage(b, 0, 900);
  q.fillStyle = '#ffffff'; q.font = 'bold 30px sans-serif';
  q.fillText('v12 (baseline)', 20, 40); q.fillText('v13', 20, 940);
  fs.writeFileSync(DIR + '/preview/compare-v12-vs-v13.png', c.toBuffer('image/png'));
  console.log('wrote simulated preview + compare');
})();
