// 686 · 可视化：685（离场后 X 残留） vs 686（逐层收起 + 屏幕门控）
//   行 1 = 关卡内（两版都应显示 X）；行 2 = 离开关卡后（685 残留、686 全收起）
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { createCanvas } = require(path.join(ROOT, 'qianxing-murdoku-tool/node_modules/@napi-rs/canvas'));
const SIM = JSON.parse(fs.readFileSync(path.join(DIR, '686_行为模拟.json'), 'utf8'));

const MARKS = [[2, 2], [2, 4], [4, 1], [5, 5]];   // 关卡内点亮的 4 组
const PW = 330, PH = 268, GAP = 16, HEAD = 78, FOOT = 26;
const W = PW * 2 + GAP * 3, H = HEAD + (PH + GAP) * 2 + FOOT;
const canvas = createCanvas(W, H);
const c = canvas.getContext('2d');
c.fillStyle = '#F6F1E4'; c.fillRect(0, 0, W, H);
c.fillStyle = '#2A211B'; c.font = 'bold 21px "Microsoft YaHei",sans-serif';
c.fillText('686 · X 标记离场收起（父容器隐藏不级联，改为逐层关灯）', GAP + 2, 30);
c.font = '13px "Microsoft YaHei",sans-serif'; c.fillStyle = '#6A5A4A';
c.fillText('行为模拟由 lua.exe 真跑内嵌脚本函数得出：关卡内 12 个控件亮；离场后 685=12（残留）、686=0', GAP + 2, 54);
c.font = 'bold 15px "Microsoft YaHei",sans-serif';
c.fillStyle = '#A6321B'; c.fillText('① 685（残留）', GAP + 2, HEAD - 8);
c.fillStyle = '#2F6B4F'; c.fillText('② 686（已收起）', PW + GAP * 2 + 2, HEAD - 8);

const N = 5, CS = 38, GP = 3, BX = 20, BY = 26;
const cell = (r, col) => [BX + col * (CS + GP), BY + r * (CS + GP)];
function drawX(ox, oy, r, col) {
  c.save(); c.translate(ox + BX + col * (CS + GP) + CS / 2, oy + BY + r * (CS + GP) + CS / 2);
  for (const deg of [45, -45]) {
    c.save(); c.rotate(deg * Math.PI / 180);
    c.fillStyle = '#45494D'; c.fillRect(-14, -1.5, 28, 3); c.restore();
  }
  c.restore();
}
function drawBoard(ox, oy) {
  c.save(); c.translate(ox, oy);
  c.fillStyle = '#C08A3E'; c.fillRect(0, 0, PW, PH);
  c.fillStyle = '#D9C9A6'; c.fillRect(BX - 6, BY - 6, N * (CS + GP) - GP + 12, N * (CS + GP) - GP + 12);
  for (let r = 0; r < N; r++) for (let col = 0; col < N; col++) {
    const [x, y] = cell(r, col);
    c.fillStyle = '#FBF4E2'; c.fillRect(x, y, CS, CS);
    c.strokeStyle = '#B9A37B'; c.lineWidth = 1; c.strokeRect(x + .5, y + .5, CS - 1, CS - 1);
  }
  c.restore();
}
function drawLeaveScreen(ox, oy) {
  c.save(); c.translate(ox, oy);
  c.fillStyle = '#B8730F'; c.fillRect(0, 0, PW, PH);
  c.fillStyle = '#D68A16'; c.beginPath(); c.ellipse(PW / 2, 130, 150, 120, 0, 0, Math.PI * 2); c.fill();
  // 白卡片
  for (let i = 0; i < 3; i++) {
    const x = 42 + i * 82;
    c.fillStyle = '#FFFDF5'; c.fillRect(x, 70, 70, 116);
    c.fillStyle = '#8B3A22'; c.fillRect(x + 8, 80, 54, 96);
  }
  // 黄色方块
  c.fillStyle = '#FFE500'; c.fillRect(250, 42, 46, 62); c.fillRect(22, 176, 52, 60);
  c.fillRect(268, 176, 40, 44);
  // 红色连线
  c.strokeStyle = '#FF2B2B'; c.lineWidth = 3;
  c.beginPath(); c.moveTo(30, 58); c.lineTo(96, 30); c.lineTo(190, 26); c.lineTo(272, 62); c.lineTo(286, 172); c.stroke();
  c.fillStyle = '#FF5A2B';
  for (const [x, y] of [[30, 58], [96, 30], [190, 26], [272, 62], [286, 172]]) {
    c.beginPath(); c.arc(x, y, 5, 0, Math.PI * 2); c.fill();
  }
  c.font = 'bold 14px "Microsoft YaHei",sans-serif'; c.fillStyle = '#F5E6C8';
  c.fillText('结算 / 选关界面', 12, 22);
  c.restore();
}
function panel(side, row, is686, inLevel) {
  const ox = GAP + side * (PW + GAP), oy = HEAD + row * (PH + GAP);
  c.fillStyle = '#FFFFFF'; c.fillRect(ox, oy, PW, PH);
  c.strokeStyle = is686 ? '#A8C6B4' : '#D8B3A6'; c.lineWidth = 2;
  c.strokeRect(ox + 1, oy + 1, PW - 2, PH - 2);
  if (inLevel) drawBoard(ox, oy); else drawLeaveScreen(ox, oy);
  const show = inLevel || !is686;     // 686 离场后不画 X
  if (show) for (const [r, col] of MARKS) drawX(ox, oy, r - 1, col - 1);
  c.fillStyle = 'rgba(255,253,245,0.92)'; c.fillRect(ox + 2, oy + PH - 42, PW - 4, 40);
  c.font = 'bold 13px "Microsoft YaHei",sans-serif';
  c.fillStyle = is686 ? '#2F6B4F' : '#A6321B';
  const label = inLevel ? (is686 ? '关卡内：X 正常显示（12 个控件）' : '关卡内：X 正常显示（12 个控件）')
    : (is686 ? '离场后：192 个控件全部关灯，X=0' : '离场后：X 仍悬浮在新界面上（残留 12）');
  c.fillText(label, ox + 12, oy + PH - 24);
  c.font = '12px "Microsoft YaHei",sans-serif'; c.fillStyle = '#6A5A4A';
  c.fillText(inLevel ? '第 1 行 · 关卡内（棋盘）' : '第 2 行 · 离开关卡（结算 / 选关）', ox + 12, oy + PH - 8);
}
panel(0, 0, false, true);
panel(1, 0, true, true);
panel(0, 1, false, false);
panel(1, 1, true, false);
c.font = '12px "Microsoft YaHei",sans-serif'; c.fillStyle = '#6A5A4A';
c.fillText(`Lua 行为模拟：685 关卡内 ${SIM.v685.inLevel} / 离场 ${SIM.v685.afterLeave} / 抢先下发 ${SIM.v685.afterRace}；`
  + `686 关卡内 ${SIM.v686.inLevel} / 离场 ${SIM.v686.afterLeave} / 抢先下发 ${SIM.v686.afterRace}`,
  GAP + 2, H - 8);
const out = path.join(DIR, '686_对照_离场收起.png');
fs.writeFileSync(out, canvas.toBuffer('image/png'));
console.log('已生成', out, W + 'x' + H);
