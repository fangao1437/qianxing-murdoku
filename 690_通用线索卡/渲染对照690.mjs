// 690 · 离线模拟：689 普通卡 / 690 普通卡 / 690 通用卡 / 690 通用卡选中
// 所有图元、颜色、文本色均从 .gil 实读；文字为占位说明（不含 UID）
// 用法：node 渲染对照690.mjs
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(TOOLS, 'gilread.mjs')).href);
const { isHiddenRecord, imageTriple } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '690_通用线索卡图元.json'), 'utf8'));
const G689 = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_性能负载优化.gil');
const G690 = path.join(DIR, '690_通用线索卡.gil');
const TPL_ID = 1073742421;
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const rgba = v => `rgba(${(v >>> 16) & 255},${(v >>> 8) & 255},${v & 255},${((v >>> 24) & 255) / 255})`;

function card(file, mode) {
  const g = readGil(file);
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const kids = g.recs.filter(r => r.parentId === TPL_ID && r.name);
  const isNormal = mode === 'normal';
  const picked = kids.filter(r => isNormal
    ? (/^(backrop1|backrop2|art671\.clue1\.|art672\.clue1\.)/.test(r.name) && !isHiddenRecord(r.field))
    : (r.name === 'gen.backrop' || /^gen690\./.test(r.name)));
  const layers = picked.map(r => {
    const st = stateBlocks(r.field.sub, [])[0];
    const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
    const ip = imageTriple(r.field);
    const tp = ns(r.field, [505, 503, 75])[0];
    const rot = st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0;
    return {
      name: r.name, o: order.get(r.field) ?? 1e9,
      x: p ? pairValue(p, 0) : 0, y: p ? pairValue(p, 1) : 0,
      w: s ? pairValue(s, 0) : 0, h: s ? pairValue(s, 1) : 0,
      color: ip ? (num(ip.node, 502) ?? 0) : 0, img: ip ? (num(ip.node, 503) || 100001) : 100001,
      rot, textColor: tp ? (num(tp, 504) ?? 0xFFFFFFFF) : null,
    };
  }).sort((a, b) => a.o - b.o);
  const text = {};
  for (const nm of ['who', 'what', 'letter', 'gen.title', 'gen.body', 'gen690.mark', 'gen690.badge']) {
    const r = kids.find(q => q.name === nm);
    const tp = r ? ns(r.field, [505, 503, 75])[0] : null;
    text[nm] = tp ? (num(tp, 504) ?? 0xFFFFFFFF) : 0xFFFFFFFF;
  }
  return { layers, text };
}
const A = card(G689, 'normal'), B = card(G690, 'normal'), C = card(G690, 'general');

function drawCard(ctx, cfg, selected, scale = 1) {
  ctx.save();
  ctx.translate(0, 0);
  for (const L of cfg.layers) {
    let v = L.color;
    if (selected && ((cfg === C && L.name === 'gen.backrop') || (cfg !== C && L.name === 'backrop1')))
      v = 0xFFFFD44B;
    ctx.save();
    ctx.translate(scale * L.x, -scale * L.y);
    ctx.rotate(-L.rot * Math.PI / 180);
    ctx.fillStyle = rgba(v);
    ctx.beginPath();
    const W = scale * L.w, H = scale * L.h;
    if (L.img === 100002) ctx.ellipse(0, 0, W / 2, H / 2, 0, 0, Math.PI * 2);
    else if (L.img === 100003) { ctx.moveTo(0, -H / 2); ctx.lineTo(-W / 2, H / 2); ctx.lineTo(W / 2, H / 2); ctx.closePath(); }
    else ctx.rect(-W / 2, -H / 2, W, H);
    ctx.fill(); ctx.restore();
  }
  ctx.restore();
}
function panel(cfg, selected, label, W = 400, H = 250) {
  const cv = createCanvas(W, H), ctx = cv.getContext('2d');
  ctx.fillStyle = '#FDFAEF'; ctx.fillRect(0, 0, W, H);
  const K = 1.05, cy = 92;
  ctx.save(); ctx.translate(W / 2, cy);
  drawCard(ctx, cfg, selected, K);
  // 文字
  const font = s => `${s}px "Microsoft YaHei",sans-serif`;
  const put = (txt, x, y, color, size, bold = false, align = 'center') => {
    ctx.fillStyle = rgba(color); ctx.font = `${bold ? 'bold ' : ''}${font(size)}`;
    ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.fillText(txt, K * x, -K * y);
  };
  if (cfg === C) {
    put('通用线索', -100, 28, cfg.text['gen.title'], 15, true);
    put('地毯上没有人', 14, -2, cfg.text['gen.body'], 17);
    put('公', -132.214, -9.5, cfg.text['gen690.mark'], 20, true);
    put('真', 140, -20, cfg.text['gen690.badge'], 22, true);
  } else {
    put('值班保安', -132, 28, cfg.text.who, 13, true);
    put('只有值班保安站在地毯上', 18, -0.5, cfg.text.what, 14);
    put('A', 140, -20, cfg.text.letter, 22, true);
  }
  ctx.restore();
  ctx.fillStyle = '#3A352C'; ctx.font = font(13); ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
  ctx.fillText(label, 12, H - 58);
  ctx.font = font(11); ctx.fillStyle = '#7A7365';
  ctx.fillText(cfg === C ? '靛蓝 + 金 · 双环「公」/ 徽「真」· 金色规则线' : '枣红 + 白字 · 头像 / 正文 / 字母徽', 12, H - 38);
  ctx.fillText(selected ? '选中：外框 3px 一圈黄（HIGHLIGHT_TINT 不变）' : '普通态', 12, H - 20);
  return cv;
}
// 硬闸门：689 普通卡 与 690 普通卡 的可见层逐字段一致
const norm = arr => arr.map(L => [L.name, L.x, L.y, L.w, L.h, L.img, L.color, L.rot].join('|'));
if (JSON.stringify(norm(A.layers)) !== JSON.stringify(norm(B.layers)))
  throw Error('690 的普通卡可见层与 689 不一致！');

const imgs = [
  ['689 · 普通线索卡（基准）', panel(A, false, '689 普通线索卡')],
  ['690 · 普通线索卡（零改动）', panel(B, false, '690 普通线索卡')],
  ['690 · 通用线索卡（新增）', panel(C, false, '690 通用线索卡')],
  ['690 · 通用线索卡（选中）', panel(C, true, '690 通用线索卡 · 选中')],
];
const W = imgs[0][1].width, H = imgs[0][1].height;
const tri = createCanvas(W * imgs.length, H + 40), tc = tri.getContext('2d');
tc.fillStyle = '#1E1E1E'; tc.fillRect(0, 0, tri.width, tri.height);
imgs.forEach(([label, cv], i) => {
  tc.drawImage(cv, i * W, 40);
  tc.fillStyle = '#EDEDED'; tc.font = 'bold 15px "Microsoft YaHei",sans-serif';
  tc.fillText(label, i * W + 12, 26);
});
fs.writeFileSync(path.join(DIR, '690_对照_通用线索卡.png'), tri.toBuffer('image/png'));

// 单卡放大预览
function zoom(cfg, selected, out) {
  const S = 2.6, cv = createCanvas(Math.round(360 * S), Math.round(140 * S)), ctx = cv.getContext('2d');
  ctx.fillStyle = '#FDFAEF'; ctx.fillRect(0, 0, cv.width, cv.height);
  ctx.save(); ctx.translate(cv.width / 2, cv.height / 2);
  drawCard(ctx, cfg, selected, S);
  const put = (txt, x, y, color, size, bold = false) => {
    ctx.fillStyle = rgba(color); ctx.font = `${bold ? 'bold ' : ''}${size}px "Microsoft YaHei",sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(txt, S * x, -S * y);
  };
  if (cfg === C) {
    put('通用线索', -100, 28, cfg.text['gen.title'], S * 15, true);
    put('地毯上没有人', 14, -2, cfg.text['gen.body'], S * 17);
    put('公', -132.214, -9.5, cfg.text['gen690.mark'], S * 20, true);
    put('真', 140, -20, cfg.text['gen690.badge'], S * 22, true);
  } else {
    put('值班保安', -132, 28, cfg.text.who, S * 13, true);
    put('只有值班保安站在地毯上', 18, -0.5, cfg.text.what, S * 14);
    put('A', 140, -20, cfg.text.letter, S * 22, true);
  }
  ctx.restore();
  fs.writeFileSync(path.join(DIR, out), cv.toBuffer('image/png'));
}
zoom(B, false, '690_预览_普通线索卡.png');
zoom(C, false, '690_预览_通用线索卡.png');
zoom(C, true, '690_预览_通用线索卡_选中.png');
console.log(JSON.stringify({
  normalLayers689: A.layers.length, normalLayers690: B.layers.length,
  generalLayers690: C.layers.length,
  normalLayersIdentical: true,
  outputs: ['690_对照_通用线索卡.png', '690_预览_普通线索卡.png', '690_预览_通用线索卡.png', '690_预览_通用线索卡_选中.png'],
}, null, 2));
