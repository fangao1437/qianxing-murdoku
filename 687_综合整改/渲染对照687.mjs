// 687 · 四项整改的矢量对照图（数值全部取自 686/687 .gil 与内嵌 Lua）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const W = 1440, H = 1080;
const cv = createCanvas(W, H), c = cv.getContext('2d');
const F = '"Microsoft YaHei",sans-serif';
c.fillStyle = '#F7F2E7'; c.fillRect(0, 0, W, H);
c.fillStyle = '#2A211B'; c.font = 'bold 28px ' + F;
c.fillText('687 · 四项整改对照（686 → 687）', 34, 44);
c.font = '15px ' + F; c.fillStyle = '#6A5A4A';
c.fillText('倒计时跟随换位 · 恢复未启用结算变灰 · 首页网格纸回设计位（双屏分开） · 弹窗小叉统一', 34, 70);

const PW = 672, PH = 452, GAP = 28, LEFT = 34, TOP = 96;
function panel(col, row, title, sub) {
  const x = LEFT + col * (PW + GAP), y = TOP + row * (PH + GAP);
  c.fillStyle = '#FFFFFF'; c.fillRect(x, y, PW, PH);
  c.strokeStyle = '#D8CBB4'; c.lineWidth = 1.5; c.strokeRect(x + .5, y + .5, PW - 1, PH - 1);
  c.fillStyle = '#3B2C22'; c.font = 'bold 19px ' + F; c.fillText(title, x + 16, y + 30);
  c.fillStyle = '#8A7863'; c.font = '13px ' + F; c.fillText(sub, x + 16, y + 52);
  return { x, y };
}
function tag(x, y, text, color, bg) {
  c.font = 'bold 14px ' + F;
  const w = c.measureText(text).width + 16;
  c.fillStyle = bg; c.fillRect(x, y - 18, w, 24);
  c.fillStyle = color; c.fillText(text, x + 8, y);
}
function capsule(cx, cy, w, h, fill, stroke, text) {
  const r = h / 2;
  c.beginPath();
  c.moveTo(cx - w / 2 + r, cy - h / 2); c.lineTo(cx + w / 2 - r, cy - h / 2);
  c.arc(cx + w / 2 - r, cy, r, -Math.PI / 2, Math.PI / 2);
  c.lineTo(cx - w / 2 + r, cy + h / 2);
  c.arc(cx - w / 2 + r, cy, r, Math.PI / 2, 3 * Math.PI / 2);
  c.closePath();
  c.fillStyle = fill; c.fill();
  if (stroke) { c.strokeStyle = stroke; c.lineWidth = 2.5; c.stroke(); }
  c.fillStyle = '#47271A'; c.font = 'bold 17px ' + F; c.textAlign = 'center';
  c.fillText(text, cx, cy + 6); c.textAlign = 'left';
}

// ── ① 退出菜单弹窗：倒计时 -200 → -95 ────────────────────────────────────
{
  const p = panel(0, 0, '① 结算倒计时跟随换位', '683 四键整体 -108，倒计时却被单独甩到 -200；687 回到 682 的相对位置 -95');
  for (let v = 0; v < 2; v++) {
    const ox = p.x + 24 + v * 320, oy = p.y + 74;
    const bw = 290, bh = 350, s = 0.52;
    c.fillStyle = '#FFF5D6'; c.fillRect(ox, oy, bw, bh);
    c.strokeStyle = '#6C402E'; c.lineWidth = 3; c.strokeRect(ox + 1.5, oy + 1.5, bw - 3, bh - 3);
    tag(ox + 8, oy + 22, v === 0 ? '686' : '687', '#FFFFFF', v === 0 ? '#A6321B' : '#2F6B4F');
    const cx = ox + bw / 2, cy = oy + bh / 2;
    const ys = [120, 40, -40, -120];
    ys.forEach((yy, i) => {
      const down = i === 3 ? 30 : 0;   // 真机 cancel.settle_shift=30 让位
      capsule(cx, cy - (yy - down) * s, 220, 32, '#FCECD4', '#6C402E',
        ['退出至菜单', '仅存档', '存档并结算', '取消'][i]);
    });
    const cdY = v === 0 ? -200 : -95;
    const txt = v === 0 ? '56秒后可结算  y=-200' : '56秒后可结算  y=-95';
    c.font = 'bold 14px ' + F; c.textAlign = 'center';
    const tw = c.measureText(txt).width;
    c.fillStyle = 'rgba(255,245,214,0.92)'; c.fillRect(cx - tw / 2 - 5, cy - cdY * s - 12, tw + 10, 20);
    c.fillStyle = v === 0 ? '#A6321B' : '#2F6B4F';
    c.fillText(txt, cx, cy - cdY * s + 3);
    c.textAlign = 'left';
    c.strokeStyle = v === 0 ? '#A6321B' : '#2F6B4F'; c.setLineDash([5, 4]); c.lineWidth = 1.5;
    c.beginPath(); c.moveTo(cx - 110, cy - cdY * s + 14); c.lineTo(cx + 110, cy - cdY * s + 14); c.stroke();
    c.setLineDash([]);
    c.fillStyle = '#8A7863'; c.font = '12px ' + F;
    c.fillText(v === 0 ? '离「存档并结算」80px，孤零零在底部' : '夹在结算键与让位后的取消键之间，各留 5px',
      ox + 10, oy + bh + 22);
  }
}

// ── ② 未启用结算变灰 ────────────────────────────────────────────────────
{
  const p = panel(1, 0, '② 未启用结算的变灰染色', '683 后按钮子层只剩 art + label，Lua 找 bg 染灰失效；687 沿 art 容器染 6 层');
  const sim = JSON.parse(fs.readFileSync(path.join(DIR, '687_行为模拟.json'), 'utf8'));
  for (let v = 0; v < 2; v++) {
    const ox = p.x + 24 + v * 320, oy = p.y + 96;
    const disabled = v === 0 ? false : true;
    tag(ox, oy, v === 0 ? '686 禁用态（未变灰）' : '687 禁用态（已变灰）', '#FFFFFF', v === 0 ? '#A6321B' : '#2F6B4F');
    // 6 层示意：3 描边 + 3 填充
    const fill = disabled ? '#686B70' : '#FCECD4';
    const stroke = disabled ? '#686B70' : '#6C402E';
    capsule(ox + 140, oy + 90, 250, 62, fill, stroke, '存档并结算');
    c.fillStyle = '#8A7863'; c.font = '13px ' + F;
    c.fillText('lua.exe 真跑 enabled=false：', ox, oy + 160);
    c.fillStyle = v === 0 ? '#A6321B' : '#2F6B4F'; c.font = 'bold 22px ' + F;
    c.fillText((v === 0 ? sim.tint.v686.gray : sim.tint.v687.gray) + ' / 6 层染灰', ox, oy + 190);
    c.fillStyle = '#8A7863'; c.font = '13px ' + F;
    c.fillText(v === 0 ? 'self:sub(id,"bg") = nil ⇒ 无层被染' : '启用后 3 描边 #6C402E + 3 胶囊 #FCECD4 复原', ox, oy + 216);
  }
  c.fillStyle = '#6A5A4A'; c.font = '13px ' + F;
  c.fillText('灰值沿用原 Lua 0xFF686B70；SETTLE_ART_TINT（右下角结算票券 20 层）本来就生效，未动', p.x + 24, p.y + PH - 30);
}

// ── ③ 首页网格纸 ────────────────────────────────────────────────────────
{
  const p = panel(0, 1, '③ 首页网格纸回设计图位置', '共享 48 层静态不动；sync_art641 只给 home/select 父偏移 +40.5，game 仍 (105,46)');
  for (let v = 0; v < 2; v++) {
    const ox = p.x + 24 + v * 320, oy = p.y + 74;
    const bw = 280, bh = 300;
    c.fillStyle = '#A9531F'; c.fillRect(ox, oy, bw, bh);
    tag(ox + 8, oy + 22, v === 0 ? '686 首页（额外下移）' : '687 首页（设计位）', '#FFFFFF', v === 0 ? '#A6321B' : '#2F6B4F');
    const cardW = 170, cardH = 226, cardX = ox + (bw - cardW) / 2, cardY = oy + 52;
    // 网格纸：645×750 按 0.30 缩放 = 194×225；纸中心相对卡片中心
    const gW = 194, gH = 225;
    const gCx = cardX + cardW / 2 - 2;
    const gCy = cardY + cardH / 2 + (v === 0 ? 12 : 0);   // 686 相对设计位下移 ≈40.5 存档单位
    c.save(); c.translate(gCx, gCy); c.rotate(-5.2 * Math.PI / 180);
    c.fillStyle = '#F0DCA6'; c.fillRect(-gW / 2, -gH / 2, gW, gH);
    c.strokeStyle = '#E0C68C'; c.lineWidth = 1;
    for (let i = -gW / 2; i <= gW / 2; i += 12) { c.beginPath(); c.moveTo(i, -gH / 2); c.lineTo(i, gH / 2); c.stroke(); }
    for (let j = -gH / 2; j <= gH / 2; j += 12) { c.beginPath(); c.moveTo(-gW / 2, j); c.lineTo(gW / 2, j); c.stroke(); }
    c.restore();
    c.fillStyle = '#FFF5D6'; c.fillRect(cardX, cardY, cardW, cardH);
    c.strokeStyle = '#6C402E'; c.lineWidth = 1.5; c.strokeRect(cardX + .5, cardY + .5, cardW - 1, cardH - 1);
    c.fillStyle = '#C9AC6D'; c.fillRect(cardX + 16, cardY + 16, cardW - 32, cardH - 32);
    // 设计图目标线
    c.strokeStyle = '#2F6B4F'; c.setLineDash([6, 4]); c.lineWidth = 2;
    c.beginPath(); c.moveTo(ox + 6, gCy - gH / 2 + (v === 0 ? -12 : 0)); c.lineTo(ox + bw - 6, gCy - gH / 2 + (v === 0 ? -12 : 0)); c.stroke();
    c.setLineDash([]);
    c.fillStyle = '#8A7863'; c.font = '12px ' + F;
    c.fillText(v === 0 ? '686：顶部几乎不露 / 父偏移 (0, 0)' : '687：露出量回设计图 / 父偏移 (0, 40.5)',
      ox + 8, oy + bh + 22);
  }
  c.fillStyle = '#6A5A4A'; c.font = '12px ' + F;
  c.fillText('656 设计位 paper 504 y=-5；679=-15.5；680 为 game 屏下移 30 ⇒ 686=-45.5', p.x + 24, p.y + PH - 40);
  c.fillText('真机 home 抬回 40.5，game 仍 (105,46) 零变化；静态 48 层逐字节不动', p.x + 24, p.y + PH - 20);
}

// ── ④ 小叉统一 ──────────────────────────────────────────────────────────
{
  const p = panel(1, 1, '④ 所有弹窗右上角小叉统一', '提示弹窗 hint635.* 的叉 20×20 / 热区 36×36 为基准；help617 已是基准不动');
  const drawX = (cx, cy, size, hit, color, label, sub) => {
    c.strokeStyle = '#B9A88E'; c.setLineDash([5, 4]); c.lineWidth = 1.5;
    c.strokeRect(cx - hit / 2, cy - hit / 2, hit, hit); c.setLineDash([]);
    c.strokeStyle = color; c.lineWidth = Math.max(3, size * 0.16); c.lineCap = 'round';
    c.beginPath(); c.moveTo(cx - size / 2, cy - size / 2); c.lineTo(cx + size / 2, cy + size / 2);
    c.moveTo(cx + size / 2, cy - size / 2); c.lineTo(cx - size / 2, cy + size / 2); c.stroke();
    c.fillStyle = '#3B2C22'; c.font = 'bold 15px ' + F; c.textAlign = 'center';
    c.fillText(label, cx, cy + hit / 2 + 24); c.textAlign = 'left';
    c.fillStyle = '#8A7863'; c.font = '12px ' + F; c.textAlign = 'center';
    c.fillText(sub, cx, cy + hit / 2 + 44); c.textAlign = 'left';
  };
  drawX(p.x + 120, p.y + 170, 15.66 * 2.2, 41.76 * 2.2, '#47271A', '686 教程弹窗', '叉 15.66 / 热区 41.76');
  drawX(p.x + 350, p.y + 170, 20 * 2.2, 46.10 * 2.2, '#47271A', '687 教程弹窗', '叉 20 / 热区 46.10');
  drawX(p.x + 565, p.y + 170, 20 * 2.2, 36 * 2.2, '#291A16', '提示弹窗（基准）', '叉 20 / 热区 36（未改）');
  c.fillStyle = '#6A5A4A'; c.font = '13px ' + F;
  c.fillText('X 放大 Δ=4.338624，热区同步放大同一 Δ（保持点击余量）；td.home / td.l1 / td.l2 三套 13 页教程各 4 状态同改', p.x + 24, p.y + 300);
  c.fillText('没有右上角小叉的弹窗（modal / result / win 等）按「没有的忽略」不新增', p.x + 24, p.y + 326);
  tag(p.x + 24, p.y + 380, '统一后 6 个 X 全部 20×20', '#FFFFFF', '#2F6B4F');
}

const out = path.join(DIR, '687_对照_四项整改.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(out, W + 'x' + H);
