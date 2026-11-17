// 694 · 离线示意：地毯整块模板渲染恢复（层/颜色/尺寸从 694 .gil 实读）
//   左：furn.rug.4（L3a 缺右下，第3关）  中：furn.rug.5（L3b 缺左下，第7关）
//   右：693 断开 vs 694 恢复的渲染链路对照
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
try { GlobalFonts.registerFromPath('C:/Windows/Fonts/simhei.ttf', 'CN'); } catch (_) {}
const F = s => s.replace('sans-serif', '"CN", sans-serif');
const rgba = v => `rgba(${(v >>> 16) & 255},${(v >>> 8) & 255},${v & 255},${((v >>> 24) & 255) / 255})`;
const g = readGil(path.join(DIR, '694_地毯渲染修复.gil'));
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
const W = 1080, H = 610, PAD = 30, CW = 320, CH = 320;
const canvas = createCanvas(W, H), ctx = canvas.getContext('2d');
ctx.fillStyle = '#F5F1E8'; ctx.fillRect(0, 0, W, H);
ctx.fillStyle = '#2A2118'; ctx.font = F('bold 22px sans-serif');
ctx.fillText('694 · 地毯恢复整块模板渲染（层数据从 694 .gil 实读）', PAD, 36);
ctx.font = F('13px sans-serif'); ctx.fillStyle = '#5A4C3C';
ctx.fillText('2×2 画布 216×216，9 层「按边开放」，整块 L 形、边框只沿外围；真机由 _spawn_whole_rug 一次性实例化', PAD, 58);

const panels = [
  { tpl: 'furn.rug.4', title: 'furn.rug.4 · L3a（缺右下）', sub: '第3关 地毯 (3,2)(3,3)(4,2)' },
  { tpl: 'furn.rug.5', title: 'furn.rug.5 · L3b（缺左下）', sub: '第7关 地毯 (2,3)(2,4)(3,4)' },
];
panels.forEach((p, i) => {
  const ox = PAD + i * (CW + 30), oy = 88;
  ctx.fillStyle = '#FFFFFF'; ctx.fillRect(ox, oy, CW, CH);
  ctx.strokeStyle = '#B9AC97'; ctx.lineWidth = 1; ctx.strokeRect(ox, oy, CW, CH);
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
  ctx.fillText('9 层 · 独立素材、未拉伸、内部无格线', ox, oy + CH + 62);
});

// 右：渲染链路对照
const ox = PAD + 2 * (CW + 30), oy = 88;
ctx.fillStyle = '#FFFFFF'; ctx.fillRect(ox, oy, CW, CH);
ctx.strokeStyle = '#B9AC97'; ctx.strokeRect(ox, oy, CW, CH);
const box = (x, y, w, h, fill, stroke) => {
  ctx.fillStyle = fill; ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.strokeRect(x, y, w, h);
};
const bx = ox + 16, bw = CW - 32;
box(bx, oy + 14, bw, 40, '#EFE7D5', '#B9AC97');
ctx.fillStyle = '#2A2118'; ctx.font = F('bold 13px sans-serif');
ctx.fillText('F.layout → TPL_KEY → furn_tpl / span / offset', bx + 8, oy + 38);
ctx.fillStyle = '#5A4C3C'; ctx.font = F('12px sans-serif');
ctx.fillText('↓', ox + CW / 2 - 4, oy + 72);
box(bx, oy + 78, bw, 44, '#DCE8D2', '#7A9A62');
ctx.fillStyle = '#2A2118'; ctx.font = F('bold 13px sans-serif');
ctx.fillText('694 OK：_spawn_whole_rug', bx + 8, oy + 96);
ctx.font = F('12px sans-serif'); ctx.fillStyle = '#3D5A2E';
ctx.fillText('→ board.rugs → 整块模板实例化（显示）', bx + 8, oy + 114);
box(bx, oy + 134, bw, 44, '#F3D9D4', '#B97A70');
ctx.fillStyle = '#7A2A22'; ctx.font = F('bold 13px sans-serif');
ctx.fillText('693 FAIL：隐藏 rug 实例 + return false', bx + 8, oy + 152);
ctx.font = F('12px sans-serif');
ctx.fillText('逐格 els 又被 _furn_tpl_ok 跳过，所以全空白', bx + 8, oy + 170);
ctx.fillStyle = '#5A4C3C'; ctx.font = F('12px sans-serif');
ctx.fillText('两关地毯变体：L3a / L3b', bx + 2, oy + 206);
ctx.fillText('单格 / h2 / v2 同样恢复整块模板', bx + 2, oy + 226);
ctx.fillText('逐格 rug_cell_els：694 已关闭（无双绘）', bx + 2, oy + 246);
ctx.fillText('第3关右上角 (1,6) 装饰植物：已删', bx + 2, oy + 270);
ctx.fillStyle = '#2A2118'; ctx.font = F('bold 15px sans-serif');
ctx.fillText('693 断开 / 694 恢复', ox, oy + CH + 24);
ctx.fillStyle = '#6B5A44'; ctx.font = F('12px sans-serif');
ctx.fillText('实测：5 个 rug 变体 693 全 false / 694 全 true', ox, oy + CH + 44);
ctx.fillText('与桌椅/书架/植物/雕塑同一条素材引用路线', ox, oy + CH + 62);

ctx.fillStyle = '#5A4C3C'; ctx.font = F('12px sans-serif');
ctx.fillText('引用链：源/母本/引用三件套 → things.childList → path_map → cfg.furn_tpl_prefab / canvas', PAD, H - 58);
ctx.fillText('→ TPL_KEY.carpet.L3a|L3b → build_layout.furn_tpl → _spawn_furn_tpl → _spawn_whole_rug', PAD, H - 40);
ctx.fillText('注：本图为离线示意（层色/尺寸从 .gil 实读），真机尺寸与像素对齐仍待导入后复核。', PAD, H - 20);
fs.writeFileSync(path.join(DIR, '694_示意_地毯渲染.png'), canvas.toBuffer('image/png'));
console.log('已生成 694_示意_地毯渲染.png');
