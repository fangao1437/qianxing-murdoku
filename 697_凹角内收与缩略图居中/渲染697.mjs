// 697 · 离线示意图（纯 node 生成 PNG，颜色/尺寸从 696 规格与 gil 实读）
//   左：三格地毯凹角顶点「补片前 / 补片后」
//   右：选关卡片棕色区域的棋盘缩略图 + 下方白色边缘的关卡名条
import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const W = 1040, H = 470;
const C = {
  bg: [245, 239, 226], paper: [252, 251, 247], brown: [92, 55, 31],
  edge: [184, 154, 98], inner: [220, 198, 132], fill: [201, 176, 114],
  ink: [32, 38, 44], gold: [220, 91, 41], name: [74, 46, 28],
  room: [[217, 205, 180], [195, 205, 212], [212, 200, 188], [190, 207, 176]],
  shadow: [198, 184, 160], white: [255, 255, 255],
};
const rows = Array.from({ length: H }, () => {
  const r = Buffer.alloc(W * 3);
  for (let x = 0; x < W; x++) { r[x * 3] = C.bg[0]; r[x * 3 + 1] = C.bg[1]; r[x * 3 + 2] = C.bg[2]; }
  return r;
});
function rect(x, y, w, h, col) {
  x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
  for (let yy = Math.max(0, y); yy < Math.min(H, y + h); yy++) {
    const r = rows[yy];
    for (let xx = Math.max(0, x); xx < Math.min(W, x + w); xx++) {
      r[xx * 3] = col[0]; r[xx * 3 + 1] = col[1]; r[xx * 3 + 2] = col[2];
    }
  }
}
// ── 左：L 形地毯（3 格 × 3 圈） ───────────────────────────────────────
function carpet(ox, oy, cell, mode) {
  const b = Math.max(4, Math.round(cell * 0.12)), b2 = Math.max(4, Math.round(cell * 0.16));
  // 深色底：左上 / 右上 / 左下 三格
  rect(ox, oy, cell * 2, cell, C.edge);
  rect(ox, oy + cell, cell, cell, C.edge);
  // 内面（浅金）：按边开放，横条 + 竖条
  rect(ox + b, oy + b, cell * 2 - b * 2, cell - b * 2, C.inner);
  rect(ox + b, oy + b, cell - b * 2, cell * 2 - b * 2, C.inner);
  // 内框（中金填充）
  rect(ox + b2, oy + b2, cell * 2 - b2 * 2, cell - b2 * 2, C.fill);
  rect(ox + b2, oy + b2, cell - b2 * 2, cell * 2 - b2 * 2, C.fill);
  // 696 凸块（弃用）：角片在缺角象限，轮廓凸出；697 内收：角片移到 L 形内侧凹角顶点
  if (mode === 'bulge') {
    rect(ox + cell, oy + cell, b, b, C.edge);
  } else {
    rect(ox + cell, oy + cell, cell, cell, C.bg);       // 缺角格完整留白，不凸出
    rect(ox + cell - b, oy + cell - b, b, b, C.edge);   // 内侧转角块
  }
  // 缺角象限其余部分保持背景
  rect(ox + cell + b, oy + cell, cell - b, cell, C.bg);
  rect(ox + cell, oy + cell + b, cell, cell - b, C.bg);
}
carpet(60, 90, 78, 'bulge');
carpet(300, 90, 78, 'inner');
// 分隔线
rect(530, 40, 2, 390, [214, 202, 182]);

// ── 右：4 张选关卡片 ──────────────────────────────────────────────────
const cardW = 106, cardH = 150, gap = 10, x0 = 560, y0 = 100;
for (let k = 0; k < 4; k++) {
  const ox = x0 + k * (cardW + gap), oy = y0 + (k % 2) * 8;
  rect(ox + 3, oy + 4, cardW, cardH, C.shadow);
  rect(ox, oy, cardW, cardH, C.paper);                       // 白纸
  rect(ox + 7, oy + 24, cardW - 14, cardH - 45, C.brown);    // 棕色 inner
  // 棋盘缩略图：6×6 格房间底色 + 格线，家具省略
  // 697：棋盘正方形并居中，棕色区域上下留白
  const iw = cardW - 14, ih = cardH - 45;
  const side = Math.min(iw - 10, ih - 10);
  const gx = ox + 7 + (iw - side) / 2, gy = oy + 24 + (ih - side) / 2;
  const cw = side / 6, ch = side / 6;
  for (let r = 0; r < 6; r++) for (let c = 0; c < 6; c++) {
    const room = (Math.floor(r / 2) + Math.floor(c / 3) + k) % 4;
    rect(gx + cw * c + 0.5, gy + ch * r + 0.5, cw - 1, ch - 1, C.room[room]);
  }
  // 墙（深墨细条）：四关位置各不相同
  const vcol = 2 + (k % 3), hrow = 3 + ((k + 1) % 2);
  rect(gx + cw * vcol - 1, gy, 2, ch * hrow, C.ink);
  rect(gx, gy + ch * hrow - 1, cw * vcol, 2, C.ink);
  rect(gx + cw * (vcol + 1) - 1, gy + ch * hrow, 2, ch * (6 - hrow), C.ink);
  // 门（橙红短条）
  rect(gx + cw * vcol - 2, gy + ch * (hrow - 2 + 0.2), 4, ch * 0.5, C.gold);
  rect(gx + cw * (vcol - 1.8), gy + ch * hrow - 2, cw * 0.5, 4, C.gold);
  // 顶部白色边缘：规格信息（浅灰细条）
  rect(ox + 10, oy + 9, cardW - 20, 3, [206, 192, 172]);
  // 下方白色边缘：关卡名（深棕文字条）
  rect(ox + 12, oy + cardH - 15, cardW - 24 - (k * 6), 5, C.name);
}

// ── PNG 编码 ──────────────────────────────────────────────────────────
const raw = Buffer.concat(rows.map(r => Buffer.concat([Buffer.from([0]), r])));
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.concat([t, data]);
  let crc = ~0;
  for (const byte of crcBuf) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xEDB88320 & -(crc & 1));
  }
  const c = Buffer.alloc(4); c.writeUInt32BE((~crc) >>> 0);
  return Buffer.concat([len, t, data, c]);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
]);
const out = path.join(DIR, '697_示意_凹角与缩略图.png');
fs.writeFileSync(out, png);
console.log('示意图已生成：' + out + '（' + W + '×' + H + '，' + png.length + ' B）');
