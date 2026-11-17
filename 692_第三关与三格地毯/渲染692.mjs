// 692 · 离线示意：三格 L 形地毯新素材（层/颜色/尺寸全部从 692 .gil 实读）
//   左：furn.rug.4（L3a，缺右下，第3关）  中：furn.rug.5（L3b，缺左下，第7关）
//   右：旧做法——把 216×108 双格模板直接拉伸到 2×2（✗ 本轮未采用）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const { createCanvas, GlobalFonts } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const { readGil, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(TOOLS, 'gilread.mjs')).href);
const { imageTriple } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const FURN = JSON.parse(fs.readFileSync(path.join(DIR, '692_家具规格.json'), 'utf8'));
try { GlobalFonts.registerFromPath('C:/Windows/Fonts/simhei.ttf', 'CN'); } catch (_) {}
const F = s => s.replace('sans-serif', '"CN", sans-serif');
const rgba = v => `rgba(${(v >>> 16) & 255},${(v >>> 8) & 255},${v & 255},${((v >>> 24) & 255) / 255})`;
const g = readGil(path.join(DIR, '692_第三关与三格地毯.gil'));
const byId = new Map(g.recs.map(r => [r.id, r]));

function layersOf(tpl) {
  const src = g.recs.find(r => r.name === tpl && r.parentId === null);
  const content = g.recs.find(r => r.parentId === src.id);
  const cl = findChildListTop(content.field.sub);
  return (asIdList(cl.payload, true) || []).map(id => {
    const r = byId.get(id), st = stateBlocks(r.field.sub, [])[0];
    const p = pairOf(st, 504), s = pairOf(st, 505), tri = imageTriple(r.field);
    return { x: pairValue(p, 0), y: pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1),
             color: rgba(Number(tri.color)), imageId: tri.id };
  });
}
const W = 1080, H = 570, PAD = 30, CW = 320, CH = 320;
const canvas = createCanvas(W, H), ctx = canvas.getContext('2d');
ctx.fillStyle = '#F5F1E8'; ctx.fillRect(0, 0, W, H);
ctx.fillStyle = '#2A2118'; ctx.font = F('bold 22px sans-serif');
ctx.fillText('692 · 三格 L 形地毯：独立新建素材（层数据从 692 .gil 实读）', PAD, 36);
ctx.font = F('13px sans-serif'); ctx.fillStyle = '#5A4C3C';
ctx.fillText('2×2 画布 216×216，3 个独立 108×108 格位，各 3 圈；零溢出、无拉伸、官方图元 100001', PAD, 58);

const panels = [
  { tpl: 'furn.rug.4', title: 'furn.rug.4 · L3a（缺右下）', sub: '第3关 地毯 (3,2)(3,3)(4,2)' },
  { tpl: 'furn.rug.5', title: 'furn.rug.5 · L3b（缺左下）', sub: '第7关 地毯 (2,3)(2,4)(3,4)' },
];
panels.forEach((p, i) => {
  const ox = PAD + i * (CW + 30), oy = 88;
  ctx.fillStyle = '#FFFFFF'; ctx.fillRect(ox, oy, CW, CH);
  ctx.strokeStyle = '#B9AC97'; ctx.lineWidth = 1; ctx.strokeRect(ox, oy, CW, CH);
  // 2×2 参考格线
  ctx.strokeStyle = '#E2D9C6'; ctx.setLineDash([4, 4]);
  for (let k = 1; k < 2; k++) {
    ctx.beginPath(); ctx.moveTo(ox + CW / 2 * k, oy); ctx.lineTo(ox + CW / 2 * k, oy + CH); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(ox, oy + CH / 2 * k); ctx.lineTo(ox + CW, oy + CH / 2 * k); ctx.stroke();
  }
  ctx.setLineDash([]);
  const cx = ox + CW / 2, cy = oy + CH / 2, scale = CW / 216;
  for (const L of layersOf(p.tpl)) {
    ctx.fillStyle = L.color;
    ctx.fillRect(cx + (L.x - L.w / 2) * scale, cy - (L.y + L.h / 2) * scale,
                 L.w * scale, L.h * scale);
  }
  ctx.fillStyle = '#2A2118'; ctx.font = F('bold 15px sans-serif');
  ctx.fillText(p.title, ox, oy + CH + 24);
  ctx.fillStyle = '#6B5A44'; ctx.font = F('12px sans-serif');
  ctx.fillText(p.sub, ox, oy + CH + 44);
  ctx.fillText(`9 层 · ${FURN.newAssets[p.tpl].gate.noStretch ? '独立素材，未拉伸' : ''}`, ox, oy + CH + 62);
});
// 右：旧拉伸做法
const ox = PAD + 2 * (CW + 30), oy = 88;
ctx.fillStyle = '#FFFFFF'; ctx.fillRect(ox, oy, CW, CH);
ctx.strokeStyle = '#B9AC97'; ctx.strokeRect(ox, oy, CW, CH);
ctx.strokeStyle = '#E2D9C6'; ctx.setLineDash([4, 4]);
for (let k = 1; k < 2; k++) {
  ctx.beginPath(); ctx.moveTo(ox + CW / 2 * k, oy); ctx.lineTo(ox + CW / 2 * k, oy + CH); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(ox, oy + CH / 2 * k); ctx.lineTo(ox + CW, oy + CH / 2 * k); ctx.stroke();
}
ctx.setLineDash([]);
// 216×108 模板被纵向拉成 216×216：整块铺满、缺角丢失
const cols = ['#B89A62', '#DCC684', '#C9B072'];
cols.forEach((c, j) => {
  const inset = [0, 13, 22][j];
  ctx.fillStyle = rgba(parseInt('FF' + c.slice(1), 16));
  ctx.fillRect(ox + inset, oy + inset, CW - inset * 2, CH - inset * 2);
});
ctx.fillStyle = '#9A2A22'; ctx.font = F('bold 34px sans-serif');
ctx.fillText('✗', ox + CW / 2 - 14, oy + CH / 2 + 12);
ctx.fillStyle = '#2A2118'; ctx.font = F('bold 15px sans-serif');
ctx.fillText('旧做法：双格模板直接拉伸', ox, oy + CH + 24);
ctx.fillStyle = '#6B5A44'; ctx.font = F('12px sans-serif');
ctx.fillText('铺满 2×2、缺角丢失、比例失真', ox, oy + CH + 44);
ctx.fillText('本轮未采用', ox, oy + CH + 62);

ctx.fillStyle = '#5A4C3C'; ctx.font = F('12px sans-serif');
ctx.fillText('引用路线：源/母本/引用三件套 → things.childList → path_map → cfg.furn_tpl_prefab / canvas', PAD, H - 38);
ctx.fillText('→ TPL_KEY.carpet.L3a|L3b → furn_tpl → _spawn_furn_tpl → InstantiateClientUIControl', PAD, H - 20);
fs.writeFileSync(path.join(DIR, '692_示意_三格地毯.png'), canvas.toBuffer('image/png'));
console.log('已生成 692_示意_三格地毯.png');
