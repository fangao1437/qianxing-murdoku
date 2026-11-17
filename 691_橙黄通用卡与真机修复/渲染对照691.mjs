// 691 · 离线模拟：橙黄通用卡 / 普通卡 / 7×7 补齐 / 地毯对齐 / 门裁剪
// 卡面图元与颜色从 .gil 实读；其余为设计示意（不含 UID）
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
const F689 = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_性能负载优化.gil');
const F691 = path.join(DIR, '691_橙黄通用卡与真机修复.gil');
const TPL_ID = 1073742421;
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const rgba = v => `rgba(${(v >>> 16) & 255},${(v >>> 8) & 255},${v & 255},${((v >>> 24) & 255) / 255})`;

function card(file, mode) {
  const g = readGil(file);
  const recTop = g.tree.find(q => q.field === 9);
  const order = new Map(); recTop.sub.forEach((f, i) => order.set(f, i));
  const kids = g.recs.filter(r => r.parentId === TPL_ID && r.name);
  const picked = kids.filter(r => mode === 'normal'
    ? (/^(backrop1|backrop2|art671\.clue1\.|art672\.clue1\.)/.test(r.name) && !isHiddenRecord(r.field))
    : (r.name === 'gen.backrop' || /^gen691\./.test(r.name)));
  const layers = picked.map(r => {
    const st = stateBlocks(r.field.sub, [])[0];
    const p = st && pairOf(st, 504), s = st && pairOf(st, 505);
    const ip = imageTriple(r.field);
    return { name: r.name, o: order.get(r.field) ?? 1e9,
      x: p ? pairValue(p, 0) : 0, y: p ? pairValue(p, 1) : 0,
      w: s ? pairValue(s, 0) : 0, h: s ? pairValue(s, 1) : 0,
      color: ip ? (num(ip.node, 502) ?? 0) : 0, img: ip ? (num(ip.node, 503) || 100001) : 100001,
      rot: st?.sub.find(q => q.field === 508)?.sub?.[0]?.f || 0 };
  }).sort((a, b) => a.o - b.o);
  const text = {};
  for (const nm of ['who', 'what', 'letter', 'gen.title', 'gen.body']) {
    const r = kids.find(q => q.name === nm);
    const tp = r ? ns(r.field, [505, 503, 75])[0] : null;
    text[nm] = tp ? (num(tp, 504) ?? 0xFFFFFFFF) : 0xFFFFFFFF;
  }
  return { layers, text };
}
const N689 = card(F689, 'normal'), N691 = card(F691, 'normal'), G691 = card(F691, 'general');

function drawCard(ctx, cfg, selected, scale) {
  for (const L of cfg.layers) {
    let v = L.color;
    if (selected && ((cfg === G691 && L.name === 'gen.backrop') || (cfg !== G691 && L.name === 'backrop1')))
      v = 0xFFFFD44B;
    ctx.save(); ctx.translate(scale * L.x, -scale * L.y); ctx.rotate(-L.rot * Math.PI / 180);
    ctx.fillStyle = rgba(v); ctx.beginPath();
    const W = scale * L.w, H = scale * L.h;
    if (L.img === 100002) ctx.ellipse(0, 0, W / 2, H / 2, 0, 0, Math.PI * 2);
    else if (L.img === 100003) { ctx.moveTo(0, -H / 2); ctx.lineTo(-W / 2, H / 2); ctx.lineTo(W / 2, H / 2); ctx.closePath(); }
    else ctx.rect(-W / 2, -H / 2, W, H);
    ctx.fill(); ctx.restore();
  }
}
function panel(cfg, selected, label, sub) {
  const W = 420, H = 220, cv = createCanvas(W, H), ctx = cv.getContext('2d');
  ctx.fillStyle = '#FDFAEF'; ctx.fillRect(0, 0, W, H);
  ctx.save(); ctx.translate(W / 2, 78);
  drawCard(ctx, cfg, selected, 1.05);
  const put = (txt, x, y, color, size, bold) => {
    ctx.fillStyle = rgba(color); ctx.font = `${bold ? 'bold ' : ''}${size}px "Microsoft YaHei",sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(txt, 1.05 * x, -1.05 * y);
  };
  if (cfg === G691) {
    put('通用线索', -100, 28, cfg.text['gen.title'], 15, true);
    put('地毯上没有人', 0, -0.4, cfg.text['gen.body'], 17);
  } else {
    put('值班保安', -132, 28, cfg.text.who, 13, true);
    put('只有值班保安站在地毯上', 18, -0.5, cfg.text.what, 14);
    put('A', 140, -20, cfg.text.letter, 22, true);
  }
  ctx.restore();
  ctx.fillStyle = '#3A352C'; ctx.font = 'bold 13px "Microsoft YaHei",sans-serif';
  ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic'; ctx.fillText(label, 12, H - 45);
  ctx.font = '11px "Microsoft YaHei",sans-serif'; ctx.fillStyle = '#7A7365';
  ctx.fillText(sub, 12, H - 26);
  ctx.fillText(selected ? '选中：外框 3px 一圈黄' : '普通态', 12, H - 10);
  return cv;
}
const imgs = [
  ['689 普通线索卡（枣红基准）', panel(N689, false, '普通线索卡', '枣红 + 白字 · 头像 / 正文 / 字母徽')],
  ['691 普通线索卡（零改动）', panel(N691, false, '普通线索卡', '枣红 + 白字 · 头像 / 正文 / 字母徽')],
  ['691 通用线索卡（橙黄）', panel(G691, false, '通用线索卡', '橙黄 + 深棕字 · 只有标题与正文 · 头像/字母位留白')],
  ['691 通用线索卡（选中）', panel(G691, true, '通用线索卡 · 选中', '橙黄 + 深棕字 · 只有标题与正文 · 头像/字母位留白')],
];
const W = imgs[0][1].width, H = imgs[0][1].height;
const tri = createCanvas(W * imgs.length, H + 40), tc = tri.getContext('2d');
tc.fillStyle = '#1E1E1E'; tc.fillRect(0, 0, tri.width, tri.height);
imgs.forEach(([label, cv], i) => {
  tc.drawImage(cv, i * W, 40);
  tc.fillStyle = '#EDEDED'; tc.font = 'bold 15px "Microsoft YaHei",sans-serif';
  tc.fillText(label, i * W + 12, 26);
});
fs.writeFileSync(path.join(DIR, '691_对照_线索卡.png'), tri.toBuffer('image/png'));

// 单卡放大
function zoom(cfg, selected, out) {
  const S = 2.6, cv = createCanvas(Math.round(360 * S), Math.round(140 * S)), ctx = cv.getContext('2d');
  ctx.fillStyle = '#FDFAEF'; ctx.fillRect(0, 0, cv.width, cv.height);
  ctx.save(); ctx.translate(cv.width / 2, cv.height / 2);
  drawCard(ctx, cfg, selected, S);
  const put = (txt, x, y, color, size, bold) => {
    ctx.fillStyle = rgba(color); ctx.font = `${bold ? 'bold ' : ''}${size}px "Microsoft YaHei",sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(txt, S * x, -S * y);
  };
  if (cfg === G691) {
    put('通用线索', -100, 28, cfg.text['gen.title'], S * 15, true);
    put('地毯上没有人', 0, -0.4, cfg.text['gen.body'], S * 17);
  } else {
    put('值班保安', -132, 28, cfg.text.who, S * 13, true);
    put('只有值班保安站在地毯上', 18, -0.5, cfg.text.what, S * 14);
    put('A', 140, -20, cfg.text.letter, S * 22, true);
  }
  ctx.restore(); fs.writeFileSync(path.join(DIR, out), cv.toBuffer('image/png'));
}
zoom(N691, false, '691_预览_普通线索卡.png');
zoom(G691, false, '691_预览_通用线索卡.png');
zoom(G691, true, '691_预览_通用线索卡_选中.png');

// ── 三张修复示意 ──────────────────────────────────────────────────────────
function gridBoard(n, title, seg) {
  const S = 62, P = 40, cv = createCanvas(P * 2 + n * S, P * 2 + n * S + 46), ctx = cv.getContext('2d');
  ctx.fillStyle = '#FDFAEF'; ctx.fillRect(0, 0, cv.width, cv.height);
  ctx.fillStyle = '#2A2233'; ctx.fillRect(P - 12, P - 12, n * S + 24, n * S + 24);
  for (let r = 1; r <= n; r++) for (let c = 1; c <= n; c++) {
    const x = P + (c - 1) * S, y = P + (r - 1) * S;
    ctx.fillStyle = (r <= 6 && c <= 6) ? '#D9CEB8' : '#E8C86A';
    ctx.fillRect(x, y, S - 2, S - 2);
    if (r > 6 || c > 6) {
      ctx.strokeStyle = '#9A4A18'; ctx.lineWidth = 2; ctx.strokeRect(x + 2, y + 2, S - 6, S - 6);
    }
    ctx.strokeStyle = '#4A4038'; ctx.lineWidth = 1; ctx.strokeRect(x, y, S - 2, S - 2);
  }
  if (seg) seg(ctx, P, S);
  ctx.fillStyle = '#3A352C'; ctx.font = 'bold 14px "Microsoft YaHei",sans-serif';
  ctx.fillText(title, P, cv.height - 24);
  ctx.font = '11px "Microsoft YaHei",sans-serif'; ctx.fillStyle = '#7A7365';
  ctx.fillText('金色描边格 = 691 新增的 13 条 floor.cell（含 face），运行时由 _sync_floor 摆到格中心', P, cv.height - 8);
  return cv;
}
const floorImg = gridBoard(7, '7×7 地板补齐：36 → 49', null);
fs.writeFileSync(path.join(DIR, '691_示意_7x7地板补齐.png'), floorImg.toBuffer('image/png'));

const carpetImg = gridBoard(6, '地毯对齐（第7关 L 形：逐格方块，不再跨格）', (ctx, P, S) => {
  const cells = [[2, 3], [2, 4], [3, 4]];
  for (const [r, c] of cells) {
    const x = P + (c - 1) * S, y = P + (r - 1) * S;
    ctx.fillStyle = '#D9C08A'; ctx.fillRect(x + 6, y + 6, S - 14, S - 14);
    ctx.strokeStyle = '#5A4634'; ctx.lineWidth = 2; ctx.strokeRect(x + 6, y + 6, S - 14, S - 14);
  }
});
fs.writeFileSync(path.join(DIR, '691_示意_地毯对齐.png'), carpetImg.toBuffer('image/png'));

const doorImg = gridBoard(7, '第6关门裁剪：9 → 5（每对区域只留一个通道）', (ctx, P, S) => {
  const dropped = [['h', 3, 4], ['h', 3, 6], ['h', 4, 2], ['v', 4, 2]];
  const kept = [['h', 3, 3], ['v', 3, 4], ['h', 3, 5], ['h', 4, 1], ['v', 7, 2]];
  const draw = (arr, color, dash) => {
    ctx.strokeStyle = color; ctx.lineWidth = 5; ctx.setLineDash(dash);
    for (const [k, r, c] of arr) {
      const x = P + (c - 1) * S, y = P + (r - 1) * S;
      ctx.beginPath();
      if (k === 'h') { ctx.moveTo(x + S * 0.3, y + S - 1); ctx.lineTo(x + S * 0.7, y + S - 1); }
      else { ctx.moveTo(x + S - 1, y + S * 0.3); ctx.lineTo(x + S - 1, y + S * 0.7); }
      ctx.stroke();
    }
    ctx.setLineDash([]);
  };
  draw(dropped, '#9A9A9A', [4, 3]);
  draw(kept, '#E2622F', []);
});
fs.writeFileSync(path.join(DIR, '691_示意_门裁剪.png'), doorImg.toBuffer('image/png'));

// 硬闸门：689 与 691 的普通卡可见层逐字段一致
const norm = arr => arr.map(L => [L.name, L.x, L.y, L.w, L.h, L.img, L.color, L.rot].join('|'));
if (JSON.stringify(norm(N689.layers)) !== JSON.stringify(norm(N691.layers)))
  throw Error('691 的普通卡可见层与 689 不一致！');
console.log(JSON.stringify({ normalLayersIdentical: true,
  generalLayers: G691.layers.length,
  outputs: ['691_对照_线索卡.png', '691_预览_普通线索卡.png', '691_预览_通用线索卡.png',
    '691_预览_通用线索卡_选中.png', '691_示意_7x7地板补齐.png', '691_示意_地毯对齐.png', '691_示意_门裁剪.png'],
}, null, 2));
