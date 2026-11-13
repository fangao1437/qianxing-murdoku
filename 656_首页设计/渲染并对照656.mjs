// 656 离线渲染 + 设计图对照 / 差分
// 用法：node 渲染并对照656.mjs [输入.gil]
// 从磁盘记录反解几何/颜色/旋转/文本，按全局记录表顺序绘制；不依赖构建器内存状态。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const OUT = path.join(DIR, '预览');
fs.mkdirSync(OUT, { recursive: true });
const { createCanvas, loadImage } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '首页复刻规格_656.json'), 'utf8'));
const AUDIT = JSON.parse(fs.readFileSync(path.join(DIR, '656_构建审计.json'), 'utf8'));
const g = readGil(process.argv[2] || path.join(DIR, '656_首页设计.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const order = new Map();
recTop.sub.forEach((f, i) => { const r = g.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const HIDDEN = new Set(AUDIT.hidden);
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const f = p?.sub?.find(q => q.field === k && q.wt === 0); return f ? Number(f.num) : null; };

function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  if (!p || !s) return null;
  const rot = st.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
  return { cx: 800 + pairValue(p, 0), cy: 450 - pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1), rot };
}
const cache = new Map();
function absCenter(r, depth = 0) {
  if (cache.has(r.id)) return cache.get(r.id);
  const gm = geom(r);
  if (!gm) return [800, 450];
  let res;
  if (!r.parentId || depth > 12) res = [gm.cx, gm.cy];
  else {
    const p = byId.get(r.parentId);
    if (!p) res = [gm.cx, gm.cy];
    else {
      const [px, py] = absCenter(p, depth + 1);
      res = [px + (gm.cx - 800), py + (gm.cy - 450)];
    }
  }
  cache.set(r.id, res);
  return res;
}
function style(r) {
  const ip = ns(r.field, [505, 503, 84])[0], tp = ns(r.field, [505, 503, 75])[0];
  if (ip) {
    const c = num(ip, 502) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    const id = num(ip, 503) || 100001;
    const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
    return { kind: 'image', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`, alpha: a, imageId: id };
  }
  if (tp) {
    const c = num(tp, 504) ?? 0xffffffff, a = ((c >>> 24) & 255) / 255;
    const tf = ns(r.field, [505, 503, 75, 510, 501])[0];
    const txt = tf?.payload?.toString('utf8') || '';
    return { kind: 'text', rgba: `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${a})`,
      alpha: a, text: txt, size: num(tp, 512) || 24 };
  }
  return null;
}
const HOME = /^(art641\.home\.|art656\.home\.|home\.|art647\.home\.settle\.)/;
const HOME_PARENTS = new Set(['home', 'home.select', 'home.continue', 'home.shop', 'home.bag', 'home.tutorial627.hit']);
const layers = g.recs.filter(r => (HOME.test(r.name || '') || HOME_PARENTS.has(byId.get(r.parentId)?.name))
  && style(r) && geom(r) && geom(r).w > 1.5 && geom(r).h > 1.5 && !HIDDEN.has(r.name))
  .sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9))
  .map(r => ({ r, s: style(r) }));

function draw(cx, L, withText) {
  const gm = geom(L.r), [X, Y] = absCenter(L.r), s = L.s;
  if (s.kind === 'text' && !withText) return;
  cx.save(); cx.translate(X, Y); cx.rotate(-gm.rot * Math.PI / 180);
  cx.fillStyle = s.rgba;
  if (s.kind === 'text') {
    cx.font = `bold ${s.size}px "Microsoft YaHei","SimHei",sans-serif`;
    cx.textAlign = 'center'; cx.textBaseline = 'middle';
    cx.fillText(s.text, 0, 0);
  } else {
    const w = gm.w, h = gm.h, id = s.imageId;
    cx.beginPath();
    if (id === 100002) cx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
    else if (id === 100006) { cx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2); cx.ellipse(0, 0, w * 0.36, h * 0.36, 0, 0, Math.PI * 2, true); }
    else if (id === 100003) { cx.moveTo(0, -h / 2); cx.lineTo(-w / 2, h / 2); cx.lineTo(w / 2, h / 2); cx.closePath(); } // 等腰三角，尖端朝上（641-646 实机口径）
    else if (id === 107102) {
      // 引擎素材 107102 是 96² 近白圆角板（四角 r≈6），不是胶囊；误画成胶囊会在宽矩形顶边两角留假空洞
      const rad = Math.min(6, h / 2, w / 2);
      cx.moveTo(-w / 2 + rad, -h / 2);
      cx.arcTo(w / 2, -h / 2, w / 2, h / 2, rad); cx.arcTo(w / 2, h / 2, -w / 2, h / 2, rad);
      cx.arcTo(-w / 2, h / 2, -w / 2, -h / 2, rad); cx.arcTo(-w / 2, -h / 2, w / 2, -h / 2, rad);
      cx.closePath();
    }
    else if (id === 107179 || id === 107092) {
      const rad = Math.min(h / 2, w / 2);
      cx.moveTo(-w / 2 + rad, -h / 2);
      cx.arcTo(w / 2, -h / 2, w / 2, h / 2, rad); cx.arcTo(w / 2, h / 2, -w / 2, h / 2, rad);
      cx.arcTo(-w / 2, h / 2, -w / 2, -h / 2, rad); cx.arcTo(-w / 2, -h / 2, w / 2, -h / 2, rad);
      cx.closePath();
    } else cx.rect(-w / 2, -h / 2, w, h);
    cx.fill();
  }
  cx.restore();
}
function render(withText) {
  const cv = createCanvas(1600, 900), cx = cv.getContext('2d');
  for (const L of layers) draw(cx, L, withText);
  return cv;
}
const uiPure = render(false), uiFull = render(true);
fs.writeFileSync(path.join(OUT, '656_UI_纯视觉.png'), uiPure.toBuffer('image/png'));
fs.writeFileSync(path.join(OUT, '656_UI_含功能文字.png'), uiFull.toBuffer('image/png'));

// 完整首页预览：v12 背景（独立项目） + 656 UI
const bgFile = path.join(ROOT, 'qianxing-murdoku/assets/警局场景-2026-11-09-v12/preview/police-v12-simulated.png');
const bg = await loadImage(fs.existsSync(bgFile) ? bgFile :
  path.join(ROOT, 'qianxing-murdoku/assets/警局场景-2026-11-09-v12/preview/police-v12-notext.png'));
const full = createCanvas(1600, 900), fx = full.getContext('2d');
fx.drawImage(bg, 0, 0, 1600, 900); fx.drawImage(uiFull, 0, 0);
fs.writeFileSync(path.join(OUT, '656_完整首页预览.png'), full.toBuffer('image/png'));

// 设计图对照 / 叠合
const design = await loadImage(path.join(ROOT, '_work/home656/design_1600x900.png'));
const compare = createCanvas(1600, 900), ccx = compare.getContext('2d');
ccx.drawImage(design, 0, 0, 800, 450); ccx.drawImage(full, 800, 0, 800, 450);
ccx.fillStyle = '#fff'; ccx.font = 'bold 20px sans-serif';
ccx.fillText('设计图', 12, 26); ccx.fillText('656 复刻 + v12 背景', 812, 26);
fs.writeFileSync(path.join(OUT, '656_对照设计图.png'), compare.toBuffer('image/png'));
const overlay = createCanvas(1600, 900), ocx = overlay.getContext('2d');
ocx.drawImage(design, 0, 0); ocx.globalAlpha = 0.5; ocx.drawImage(uiPure, 0, 0);
fs.writeFileSync(path.join(OUT, '656_叠合核对.png'), overlay.toBuffer('image/png'));

// 差分：只在 656 UI 的不透明像素上比较，与设计图逐像素比 RGBA
const A = design ? (() => { const c = createCanvas(1600, 900), x = c.getContext('2d'); x.drawImage(design, 0, 0); return x.getImageData(0, 0, 1600, 900).data; })() : null;
const B = uiPure.getContext('2d').getImageData(0, 0, 1600, 900).data;
const regions = {
  '中央纸': [470, 110, 1130, 830], '面板与按钮': [540, 185, 1070, 725],
  '相机与教程圆': [40, 195, 480, 540], '便利贴与胶带': [1230, 270, 1600, 640],
};
const diff = {};
for (const [name, [x0, y0, x1, y1]] of Object.entries(regions)) {
  let n = 0, sum = 0, sumA = 0;
  for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
    const i = (y * 1600 + x) * 4, a = B[i + 3];
    if (a < 200) continue;
    n++; sumA += a;
    sum += Math.abs(A[i] - B[i]) + Math.abs(A[i + 1] - B[i + 1]) + Math.abs(A[i + 2] - B[i + 2]);
  }
  diff[name] = { coveredPx: n, maeRGB: n ? +(sum / (n * 3)).toFixed(2) : null };
}
fs.writeFileSync(path.join(OUT, '656_差分指标.json'), JSON.stringify({
  note: 'MAE 为 656 UI 不透明像素与设计图同位置 RGB 的平均绝对误差（0-255，越小越接近）；设计图自带渐变/高光/纹理，纯色复刻有固有误差。',
  regions: diff, layers: layers.length, hidden: AUDIT.hidden,
}, null, 2));
console.log(JSON.stringify({ layers: layers.length, hidden: AUDIT.hidden.length, diff }, null, 2));
