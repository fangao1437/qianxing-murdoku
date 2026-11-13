// 685 · 离线可视化：模拟「锚点格被 SetAsLastSibling 抬到 stage 内最上、家具越界」的绘制顺序
//   左列 = 684（X 画在格内，被越界家具盖住）
//   右列 = 685（X 画在 stage 末尾标记层，恒在最上）
//   四行 = 4 种不同 kind/span/scale 的多格家具，证明方案与家具参数无关
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));

const CASES = [
  { label: '横桌 1×2',        span_r: 1, span_c: 2, scale: 1.0 },
  { label: '竖桌 2×1',        span_r: 2, span_c: 1, scale: 1.0 },
  { label: '大地毯 2×2',      span_r: 2, span_c: 2, scale: 1.0 },
  { label: '加长桌 1×3 ×1.25', span_r: 1, span_c: 3, scale: 1.25 },
];
const AR = 2, AC = 2;                       // 锚点格（0 基，第 3 行第 3 列）
const N = 5, CS = 40, GAP = 3, BX = 22, BY = 34;
const PW = 300, PH = 264, GAPX = 16, HEAD = 76, FOOT = 26;
const W = PW * 2 + GAPX * 3, H = HEAD + (PH + GAPX) * CASES.length + FOOT;
const canvas = createCanvas(W, H);
const c = canvas.getContext('2d');
c.fillStyle = '#F6F1E4'; c.fillRect(0, 0, W, H);
c.fillStyle = '#2A211B'; c.font = 'bold 22px "Microsoft YaHei",sans-serif';
c.fillText('685 · 多格家具通用构造法：X 标记层（stage 末尾）', GAPX + 4, 32);
c.font = '14px "Microsoft YaHei",sans-serif'; c.fillStyle = '#6A5A4A';
c.fillText('模拟真机绘制顺序：锚点格被抬到 stage 内最上，家具越出格线；X 位置与家具种类/尺寸无关', GAPX + 4, 56);
c.font = 'bold 16px "Microsoft YaHei",sans-serif';
c.fillStyle = '#A6321B'; c.fillText('① 684 · X 画在格内（被盖住）', GAPX + 4, HEAD - 8);
c.fillStyle = '#2F6B4F'; c.fillText('② 685 · X 画在标记层（恒可见）', PW + GAPX * 2 + 4, HEAD - 8);

const cellRect = (r, col) => [BX + col * (CS + GAP), BY + r * (CS + GAP)];
function drawBoard(ox, oy) {
  c.save(); c.translate(ox, oy);
  c.fillStyle = '#D9C9A6'; c.fillRect(BX - 6, BY - 6, N * (CS + GAP) - GAP + 12, N * (CS + GAP) - GAP + 12);
  for (let r = 0; r < N; r++) for (let col = 0; col < N; col++) {
    const [x, y] = cellRect(r, col);
    c.fillStyle = '#FBF4E2'; c.fillRect(x, y, CS, CS);
    c.strokeStyle = '#B9A37B';
    c.lineWidth = 1; c.strokeRect(x + 0.5, y + 0.5, CS - 1, CS - 1);
  }
  // 锚点格虚线框
  const [ax, ay] = cellRect(AR, AC);
  c.save(); c.setLineDash([4, 3]); c.strokeStyle = '#C06A2A'; c.lineWidth = 2;
  c.strokeRect(ax - 1, ay - 1, CS + 2, CS + 2); c.restore();
  c.fillStyle = '#C06A2A'; c.font = '11px "Microsoft YaHei",sans-serif';
  c.fillText('锚点', ax + 8, ay + CS - 5);
  c.restore();
}
function drawX(ox, oy, r, col, dim) {
  c.save(); c.translate(ox + BX + col * (CS + GAP) + CS / 2, oy + BY + r * (CS + GAP) + CS / 2);
  c.globalAlpha = dim ? 0.32 : 1;
  for (const deg of [45, -45]) {
    c.save(); c.rotate(deg * Math.PI / 180);
    c.fillStyle = '#45494D'; c.fillRect(-15, -1.6, 30, 3.2); c.restore();
  }
  c.restore();
}
function drawFurniture(ox, oy, spec) {
  const r0 = AR - (spec.span_r - 1), c0 = AC - (spec.span_c - 1);
  const [x0, y0] = cellRect(r0, c0);
  const w = spec.span_c * CS + (spec.span_c - 1) * GAP;
  const h = spec.span_r * CS + (spec.span_r - 1) * GAP;
  const ex = (spec.scale - 1) * w / 2, ey = (spec.scale - 1) * h / 2;
  c.save(); c.translate(ox, oy);
  c.fillStyle = 'rgba(28,18,12,0.30)';
  c.fillRect(x0 - ex + 4, y0 - ey + 5, w + 2 * ex, h + 2 * ey);
  c.fillStyle = '#8C6A45'; c.fillRect(x0 - ex, y0 - ey, w + 2 * ex, h + 2 * ey);
  c.fillStyle = '#B08A5C'; c.fillRect(x0 - ex + 3, y0 - ey + 3, w + 2 * ex - 6, 6);
  c.fillStyle = '#5E452B'; c.fillRect(x0 - ex + 3, y0 - ey + h + 2 * ey - 7, w + 2 * ex - 6, 4);
  c.strokeStyle = '#3B2A1B'; c.lineWidth = 2;
  c.strokeRect(x0 - ex + 1, y0 - ey + 1, w + 2 * ex - 2, h + 2 * ey - 2);
  c.restore();
}

CASES.forEach((spec, i) => {
  const oy = HEAD + i * (PH + GAPX);
  const r0 = Math.max(0, AR - (spec.span_r - 1));
  const c0 = Math.max(0, AC - (spec.span_c - 1));
  // X 放在家具包围盒左上角那一格（越界格，非锚点格）
  const xr = r0, xc = c0;
  for (let side = 0; side < 2; side++) {
    const ox = GAPX + side * (PW + GAPX);
    c.fillStyle = '#FFFFFF'; c.fillRect(ox, oy, PW, PH);
    c.strokeStyle = side === 0 ? '#D8B3A6' : '#A8C6B4'; c.lineWidth = 2;
    c.strokeRect(ox + 1, oy + 1, PW - 2, PH - 2);
    drawBoard(ox, oy);
    // 684：X 画在格内 ⇒ 在家具之前
    if (side === 0) drawX(ox, oy, xr, xc, false);
    drawFurniture(ox, oy, spec);
    // 685：X 画在 stage 末尾标记层 ⇒ 在家具之后（且每帧复位）
    if (side === 1) drawX(ox, oy, xr, xc, false);
    c.font = 'bold 13px "Microsoft YaHei",sans-serif';
    c.fillStyle = side === 0 ? '#A6321B' : '#2F6B4F';
    c.fillText(side === 0 ? 'X 被越界家具盖住（不可见）' : 'X 完整可见（标记层置顶）', ox + 14, oy + PH - 26);
    c.font = '12px "Microsoft YaHei",sans-serif'; c.fillStyle = '#6A5A4A';
    c.fillText(`第 ${i + 1} 组：${spec.label} · span ${spec.span_r}×${spec.span_c} · scale ${spec.scale}`,
      ox + 14, oy + PH - 8);
  }
});
c.font = '12px "Microsoft YaHei",sans-serif'; c.fillStyle = '#6A5A4A';
c.fillText('左＝684（格内 X 先于家具）；右＝685（标记层置顶）。四组参数互异，结论一致。',
  GAPX + 4, H - 8);
const out = path.join(DIR, '685_对照_多格家具X覆盖.png');
fs.writeFileSync(out, canvas.toBuffer('image/png'));
console.log('已生成', out, W + 'x' + H);
