// 672 线索区离线模拟：671 基线 vs 672 普通态 vs 672 选中态 vs 672 + 设计图目标轮廓
// 层全部从 .gil 实读（含 100001 矩形与 100003 三角），文字为占位说明
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { isHiddenRecord } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const audit = JSON.parse(fs.readFileSync(path.join(DIR, '672_构建审计.json'), 'utf8'));
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
    && /^(art670\.clue1\.|art671\.clue1\.|art672\.clue1\.|backrop1$|backrop2$)/.test(r.name)
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

function render(cfg, selectedRow = -1, withTarget = false, W = 420, H = 560) {
  const cv = createCanvas(W, H), cx = cv.getContext('2d');
  cx.fillStyle = '#FDFAEF'; cx.fillRect(0, 0, W, H);
  const X0 = 20, Y0 = 20;
  ROWS.forEach((rowCy, i) => {
    cx.save();
    cx.beginPath(); cx.rect(X0, Y0 + (rowCy - 279.8), 330, 85.4); cx.clip();
    for (const L of cfg.vis) {
      const x = X0 + (L.cx - 800) + 165, y = Y0 + (rowCy - 279.8) + (L.cy - 450) + 42.7;
      let rgb = L.rgb;
      if (selectedRow === i && L.name === 'backrop1') rgb = 'rgba(255,212,75,1)';  // 0xFFFFD44B：高亮色不变
      cx.save(); cx.translate(x, y); cx.rotate(-L.rot * Math.PI / 180);
      cx.fillStyle = rgb; cx.beginPath();
      if (L.img === 100002) cx.ellipse(0, 0, L.w / 2, L.h / 2, 0, 0, Math.PI * 2);
      else if (L.img === 100003) { cx.moveTo(0, -L.h / 2); cx.lineTo(-L.w / 2, L.h / 2); cx.lineTo(L.w / 2, L.h / 2); cx.closePath(); }
      else cx.rect(-L.w / 2, -L.h / 2, L.w, L.h);
      cx.fill(); cx.restore();
    }
    cx.restore();
    if (withTarget && i === 0) {
      // 设计图目标轮廓（黄线）：中间异色三角 + 梯形左斜边
      const X = p => X0 + (p[0] - 638), Y = p => Y0 + (rowCy - 279.8) + (p[1] - 410.3);
      cx.strokeStyle = '#FFD44B'; cx.lineWidth = 1;
      const T = audit.spec.targetMidTriangle;
      cx.beginPath(); [T.A, T.B, T.C].forEach((q, j) => j ? cx.lineTo(X(q), Y(q)) : cx.moveTo(X(q), Y(q))); cx.closePath(); cx.stroke();
      const L = audit.spec.trapLeftLine;
      cx.beginPath(); cx.moveTo(X(L.top), Y(L.top)); cx.lineTo(X(L.bottom), Y(L.bottom)); cx.stroke();
    }
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

const A = layersOf(path.join(ROOT, 'qianxing-murdoku/671_文本与细线/671_文本与细线.gil'));
const B = layersOf(path.join(DIR, '672_梯形与异色区.gil'));
console.log('671 可见层', A.vis.length, A.vis.map(x => x.name).join(', '));
console.log('672 可见层', B.vis.length, B.vis.map(x => x.name).join(', '));
console.log('文字色', B.text);
const imgs = [
  ['671 基线（灰描边 / 右下小三角）', render(A, -1)],
  ['672 普通态（暗红描边 / 梯形 / 异色区）', render(B, -1)],
  ['672 首行选中（高亮色不变）', render(B, 0)],
  ['672 + 设计图目标轮廓（黄线）', render(B, -1, true)],
];
const W = imgs[0][1].width, H = imgs[0][1].height;
const tri = createCanvas(W * imgs.length, H + 38), tc = tri.getContext('2d');
tc.fillStyle = '#1E1E1E'; tc.fillRect(0, 0, tri.width, tri.height);
imgs.forEach(([label, cv], i) => {
  tc.drawImage(cv, i * W, 38);
  tc.fillStyle = '#EDEDED'; tc.font = 'bold 15px "Microsoft YaHei",sans-serif';
  tc.fillText(label, i * W + 10, 25);
});
fs.writeFileSync(path.join(OUT, '672_对照_线索区.png'), tri.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '672_预览_普通态.png'), imgs[1][1].toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '672_预览_选中态.png'), imgs[2][1].toBuffer('image/png'));
console.log('输出完成');
