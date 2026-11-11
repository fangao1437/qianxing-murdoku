// 667 线索区离线模拟：666 基线（红卡/整张黄） vs 667（白卡/3px 描边/只黄一圈）
// 把 clue 模板的可见视觉层实例化到 5 行，模拟首行选中（backrop1 写 HIGHLIGHT_TINT）。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const OUT = DIR;
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const TPL_ID = 1073742421;
const ROWS = [322.5, 415.5, 511, 606.5, 699.5];
const CARD_X = 223.5;
const WHO = ['值班保安', '前台姑娘', '夜班清洁', '旧识古董', '收藏家'];
const WHAT = ['只有值班保安站在地毯上', '前台姑娘在桌子旁边', '夜班清洁工坐在椅子上',
              '旧识古董商在植物旁边', '收藏家在第五列'];
const LETTER = ['A', 'B', 'C', 'D', 'V'];

function layersOf(file) {
  const g = readGil(file);
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const kids = g.recs.filter(r => r.parentId === TPL_ID && r.name
    && /^(art658\.clue1\.|art661\.clue1\.|backrop1$|backrop2$|art658\.clue1\.rule)/.test(r.name)
    && !isHiddenRecord(r.field));
  const vis = kids.map(r => {
    const st = stateBlocks(r.field.sub, [])[0];
    const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
    const ip = ns(r.field, [505, 503, 84])[0];
    const c = ip ? (num(ip, 502) ?? 0) : 0;
    const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
    return {
      name: r.name, o: order.get(r.field) ?? 1e9,
      cx: p ? 800 + pairValue(p, 0) : 800, cy: p ? 450 - pairValue(p, 1) : 450,
      w: s ? pairValue(s, 0) : 0, h: s ? pairValue(s, 1) : 0,
      rgb: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${((c >>> 24) & 255) / 255})`,
      img: ip ? (num(ip, 503) || 100001) : 100001, rot,
    };
  }).sort((a, b) => a.o - b.o);
  const text = Object.fromEntries(['who', 'what', 'letter'].map(n => {
    const r = g.recs.find(q => q.parentId === TPL_ID && q.name === n);
    const tp = r ? ns(r.field, [505, 503, 75])[0] : null;
    const c = tp ? (num(tp, 504) ?? 0xFFFFFFFF) : 0xFFFFFFFF;
    return [n, '#' + (c & 0xffffff).toString(16).padStart(6, '0').toUpperCase()];
  }));
  return { vis, text };
}

function render(cfg, selectedRow = -1, W = 420, H = 560) {
  const cv = createCanvas(W, H), cx = cv.getContext('2d');
  cx.fillStyle = '#FDFAEF'; cx.fillRect(0, 0, W, H);   // 白色底板
  const X0 = 20, Y0 = 20;                              // 视窗左上（对应 1600 口径 x=45,y=260）
  ROWS.forEach((rowCy, i) => {
    cx.save();
    cx.beginPath(); cx.rect(X0, Y0 + (rowCy - 279.8), 330, 85.4); cx.clip();
    for (const L of cfg.vis) {
      const x = X0 + (L.cx - 800) + 165, y = Y0 + (rowCy - 279.8) + (L.cy - 450) + 42.7;
      let rgb = L.rgb;
      if (selectedRow === i && L.name === 'backrop1') rgb = 'rgba(255,212,75,1)';  // 0xFFFFD44B
      cx.save(); cx.translate(x, y); cx.rotate(-L.rot * Math.PI / 180);
      cx.fillStyle = rgb; cx.beginPath();
      if (L.img === 100002) cx.ellipse(0, 0, L.w / 2, L.h / 2, 0, 0, Math.PI * 2);
      else if (L.img === 100003) { cx.moveTo(0, -L.h / 2); cx.lineTo(-L.w / 2, L.h / 2); cx.lineTo(L.w / 2, L.h / 2); cx.closePath(); }
      else cx.rect(-L.w / 2, -L.h / 2, L.w, L.h);
      cx.fill(); cx.restore();
    }
    cx.restore();
    // 文字（简化占位，颜色取自存档文本控件）
    const rowY = Y0 + (rowCy - 279.8);
    cx.fillStyle = cfg.text.who; cx.font = 'bold 12px "Microsoft YaHei",sans-serif';
    cx.fillText(WHO[i], X0 + 18, rowY + 20);
    cx.fillStyle = cfg.text.what; cx.font = '14px "Microsoft YaHei",sans-serif';
    cx.fillText(WHAT[i], X0 + 84, rowY + 48);
    cx.fillStyle = cfg.text.letter; cx.font = 'bold 20px "Microsoft YaHei",sans-serif';
    cx.textAlign = 'right'; cx.fillText(LETTER[i], X0 + 315, rowY + 58); cx.textAlign = 'left';
  });
  return cv;
}

const A = layersOf(path.join(ROOT, 'qianxing-murdoku/667_线索卡背景/667_线索卡背景.gil'));
const B = layersOf(path.join(DIR, '668_线索卡染色.gil'));
console.log('666 可见层', A.vis.length, A.vis.map(x => x.name).slice(0, 6), '文字色', A.text);
console.log('667 可见层', B.vis.length, B.vis.map(x => x.name), '文字色', B.text);

const imgs = [
  ['667 白卡·首行选中', render(A, 0)],
  ['668 普通态（红渐变回来）', render(B, -1)],
  ['668 首行选中（整张染色）', render(B, 0)],
];
const W = imgs[0][1].width, H = imgs[0][1].height;
const tri = createCanvas(W * 3, H + 38), tc = tri.getContext('2d');
tc.fillStyle = '#1E1E1E'; tc.fillRect(0, 0, tri.width, tri.height);
imgs.forEach(([label, cv], i) => {
  tc.drawImage(cv, i * W, 38);
  tc.fillStyle = '#EDEDED'; tc.font = 'bold 17px "Microsoft YaHei",sans-serif';
  tc.fillText(label, i * W + 10, 25);
});
fs.writeFileSync(path.join(OUT, '668_对照_线索区.png'), tri.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '668_预览_普通态.png'), imgs[1][1].toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '668_预览_选中态.png'), imgs[2][1].toBuffer('image/png'));
// 实机局部 vs 667 选中态
(async () => {
  const real = await loadImage(path.join(ROOT, 'qianxing-murdoku/666_线索换位/667_实机_线索区.png'));
  const rw = 300, rh = Math.round(real.height * rw / real.width);
  const c2 = createCanvas(rw + W, Math.max(rh, H) + 38), c = c2.getContext('2d');
  c.fillStyle = '#1E1E1E'; c.fillRect(0, 0, c2.width, c2.height);
  c.drawImage(real, 0, 38, rw, rh); c.drawImage(imgs[2][1], rw, 38);
  c.fillStyle = '#EDEDED'; c.font = 'bold 17px "Microsoft YaHei",sans-serif';
  c.fillText('666 实机', 10, 25); c.fillText('668 选中态（离线模拟）', rw + 10, 25);
  fs.writeFileSync(path.join(OUT, '668_对照_实机vs668.png'), c2.toBuffer('image/png'));
  console.log('输出完成');
})();
