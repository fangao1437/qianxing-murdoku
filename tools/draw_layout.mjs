// tools/draw_layout.mjs —— 直接生成「关卡内 UI 布局示意图」PNG（1600×900）
//
// 为什么不用 SVG / PowerShell：
//   2026-10-02 试过 SVG + headless Edge（viewBox 缩放不可控、出图错位）、
//   也试过 PowerShell + System.Drawing（中文引号 + `$( )` 嵌套反复把解析器打断）。
//   ⇒ 这里用 Node **自己画像素 + 自己编码 PNG**：零依赖、零解析坑、所见即所得。
//
// 布局依据：
//   ① 项目规划 `tools/sim/out/layout-plan.json`（= M.LAYOUT 的 cx/cy/w/h，设计空间 1920×1080、Y 向上）
//   ② 参考 murdoku.com/play/ 的操作框架：棋盘居中、嫌疑人在一侧、线索在另一侧、动作按钮集中在一栏

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'docs', '布局图-关卡内-拟.png');

const W = 1600, H = 900, K = 1;   // ★ 规划坐标**已经是画布空间**（1600×900、Y 向上）⇒ 不用缩放

// ── 极简画布（RGB）────────────────────────────────────────────────────
const px = Buffer.alloc(W * H * 3, 255);
function fillRect(x, y, w, h, c) {
  const x0 = Math.max(0, Math.round(x)), y0 = Math.max(0, Math.round(y));
  const x1 = Math.min(W, Math.round(x + w)), y1 = Math.min(H, Math.round(y + h));
  for (let yy = y0; yy < y1; yy++) {
    for (let xx = x0; xx < x1; xx++) {
      const i = (yy * W + xx) * 3;
      px[i] = c[0]; px[i + 1] = c[1]; px[i + 2] = c[2];
    }
  }
}
function strokeRect(x, y, w, h, c, t = 2) {
  fillRect(x, y, w, t, c); fillRect(x, y + h - t, w, t, c);
  fillRect(x, y, t, h, c); fillRect(x + w - t, y, t, h, c);
}
function hLine(x, y, w, c, t = 1) { fillRect(x, y, w, t, c); }
function vLine(x, y, h, c, t = 1) { fillRect(x, y, t, h, c); }

// 5×7 点阵字（ASCII，够画标签用；中文用"色块 + 编号"代替，见下）
const FONT = {
  '0': ['01110','10001','10011','10101','11001','10001','01110'],
  '1': ['00100','01100','00100','00100','00100','00100','01110'],
  '2': ['01110','10001','00001','00010','00100','01000','11111'],
  '3': ['11111','00010','00100','00010','00001','10001','01110'],
  '4': ['00010','00110','01010','10010','11111','00010','00010'],
  '5': ['11111','10000','11110','00001','00001','10001','01110'],
  '6': ['00110','01000','10000','11110','10001','10001','01110'],
  '7': ['11111','00001','00010','00100','01000','01000','01000'],
  '8': ['01110','10001','10001','01110','10001','10001','01110'],
  '9': ['01110','10001','10001','01111','00001','00010','01100'],
  'A': ['01110','10001','10001','11111','10001','10001','10001'],
  'B': ['11110','10001','10001','11110','10001','10001','11110'],
  'C': ['01110','10001','10000','10000','10000','10001','01110'],
  'D': ['11110','10001','10001','10001','10001','10001','11110'],
  'E': ['11111','10000','10000','11110','10000','10000','11111'],
  'F': ['11111','10000','10000','11110','10000','10000','10000'],
  'G': ['01110','10001','10000','10111','10001','10001','01111'],
  'H': ['10001','10001','10001','11111','10001','10001','10001'],
  'I': ['01110','00100','00100','00100','00100','00100','01110'],
  'J': ['00111','00010','00010','00010','00010','10010','01100'],
  'K': ['10001','10010','10100','11000','10100','10010','10001'],
  'L': ['10000','10000','10000','10000','10000','10000','11111'],
  'M': ['10001','11011','10101','10101','10001','10001','10001'],
  'N': ['10001','11001','10101','10011','10001','10001','10001'],
  'O': ['01110','10001','10001','10001','10001','10001','01110'],
  'P': ['11110','10001','10001','11110','10000','10000','10000'],
  'Q': ['01110','10001','10001','10001','10101','10010','01101'],
  'R': ['11110','10001','10001','11110','10100','10010','10001'],
  'S': ['01111','10000','10000','01110','00001','00001','11110'],
  'T': ['11111','00100','00100','00100','00100','00100','00100'],
  'U': ['10001','10001','10001','10001','10001','10001','01110'],
  'V': ['10001','10001','10001','10001','10001','01010','00100'],
  'W': ['10001','10001','10001','10101','10101','11011','10001'],
  'X': ['10001','10001','01010','00100','01010','10001','10001'],
  'Y': ['10001','10001','01010','00100','00100','00100','00100'],
  'Z': ['11111','00001','00010','00100','01000','10000','11111'],
  ' ': ['00000','00000','00000','00000','00000','00000','00000'],
  '.': ['00000','00000','00000','00000','00000','01100','01100'],
  ':': ['00000','01100','01100','00000','01100','01100','00000'],
  '/': ['00001','00010','00010','00100','01000','01000','10000'],
  '(': ['00010','00100','01000','01000','01000','00100','00010'],
  ')': ['01000','00100','00010','00010','00010','00100','01000'],
  '-': ['00000','00000','00000','11111','00000','00000','00000'],
  '+': ['00000','00100','00100','11111','00100','00100','00000'],
  '=': ['00000','00000','11111','00000','11111','00000','00000'],
  '?': ['01110','10001','00001','00110','00100','00000','00100'],
  '!': ['00100','00100','00100','00100','00100','00000','00100'],
  '#': ['01010','01010','11111','01010','11111','01010','01010'],
  '*': ['00000','10101','01110','11111','01110','10101','00000'],
  '>': ['01000','00100','00010','00001','00010','00100','01000'],
  '<': ['00010','00100','01000','10000','01000','00100','00010'],
};
function text(s, x, y, scale, c) {
  let cx = x;
  for (const ch of String(s).toUpperCase()) {
    const g = FONT[ch];
    if (!g) { cx += 6 * scale; continue; }
    for (let r = 0; r < 7; r++) {
      for (let col = 0; col < 5; col++) {
        if (g[r][col] === '1') fillRect(cx + col * scale, y + r * scale, scale, scale, c);
      }
    }
    cx += 6 * scale;
  }
  return cx;
}
function textW(s, scale) { return String(s).length * 6 * scale; }

// 画一个"中文标签块"：不依赖字体，用色块 + 编号 + 拼音/英文名
function labelCN(cn, en, x, y, scale, color) {
  const end = text(en, x, y, scale, color);
  return end;
}

// ── 配色 ─────────────────────────────────────────────────────────────
const C = {
  bg:     [247, 249, 252],
  top:    [214, 228, 245],
  left:   [226, 238, 224],
  clue:   [236, 244, 236],
  tray:   [214, 232, 255],
  board:  [255, 252, 235],
  cell:   [255, 243, 205],
  right:  [250, 228, 228],
  btn:    [255, 214, 153],
  ink:    [34, 48, 63],
  sub:    [90, 110, 130],
  edge:   [120, 140, 160],
  thin:   [170, 190, 210],
  dash:   [205, 218, 232],
  white:  [255, 255, 255],
};
const RX = (x) => Math.round(x * K);
const RY = (y) => Math.round(900 - y);   // ★ 画布 Y 向上 ⇒ 翻转；X 不翻转、不缩放
function box(cx, cy, w, h, fill, edge = C.edge, t = 2) {
  const x = RX(cx - w / 2), y = RY(cy + h / 2), ww = Math.round(w * K), hh = Math.round(h * K);
  fillRect(x, y, ww, hh, fill);
  if (edge) strokeRect(x, y, ww, hh, edge, t);
  return { x, y, w: ww, h: hh };
}

// ── 开始画 ───────────────────────────────────────────────────────────
fillRect(0, 0, W, H, C.bg);
// 中线与安全框
for (let x = 0; x < W; x += 12) fillRect(x, H / 2, 6, 1, C.dash);
for (let y = 0; y < H; y += 12) fillRect(W / 2, y, 1, 6, C.dash);

// 标题
text('LEVEL UI LAYOUT  (PROPOSED)  1600x900', 24, 16, 3, C.ink);
text('BASED ON: LAYOUT-PLAN.JSON  +  MURDOKU.COM/PLAY FRAMEWORK', 24, 46, 2, C.sub);

// ① 顶栏
const tb = box(800, 857, 1600, 87, C.top);
text('1  TOPBAR  1600x87', tb.x + 10, tb.y + 10, 2, C.ink);
text('LEFT: LEVEL NAME   CENTER: TIMER / MOVES   RIGHT: BACK / RESET', tb.x + 10, tb.y + 32, 2, C.sub);
// 顶栏里的元素
let hx = tb.x + 40;
text('TITLE  (TEXT)', hx, tb.y + 56, 2, C.ink);
text('TIMER 00:33', tb.x + 520, tb.y + 56, 2, C.ink);
text('MOVES 0', tb.x + 760, tb.y + 56, 2, C.ink);
fillRect(tb.x + 1020, tb.y + 44, 120, 30, C.btn); strokeRect(tb.x + 1020, tb.y + 44, 120, 30, C.thin, 1);
text('BACK', tb.x + 1030, tb.y + 52, 2, C.ink);
fillRect(tb.x + 1160, tb.y + 44, 120, 30, C.btn); strokeRect(tb.x + 1160, tb.y + 44, 120, 30, C.thin, 1);
text('RESET', tb.x + 1170, tb.y + 52, 2, C.ink);
fillRect(tb.x + 1300, tb.y + 44, 150, 30, C.btn); strokeRect(tb.x + 1300, tb.y + 44, 150, 30, C.thin, 1);
text('HINT', tb.x + 1310, tb.y + 52, 2, C.ink);

// ② 左栏
const lf = box(183, 427, 327, 733, C.left);
text('2  LEFT PANEL  327x733', lf.x + 10, lf.y + 8, 2, C.ink);

// 图例
const lg = box(183, 105, 300, 63, C.clue, C.thin, 1);
text('LEGEND  (SUSPECT / FURNITURE)', lg.x + 8, lg.y + 8, 2, C.sub);

// 线索
const cl = box(183, 365, 300, 433, C.clue, C.thin, 1);
text('3  CLUES  300x433', cl.x + 8, cl.y + 6, 2, C.ink);
for (let i = 0; i < 7; i++) {
  const yy = cl.y + 28 + i * 30;
  fillRect(cl.x + 8, yy, 26, 22, C.btn); strokeRect(cl.x + 8, yy, 26, 22, C.thin, 1);
  text('CLUE ' + (i + 1) + '  WHO + WHAT + BADGE', cl.x + 40, yy + 4, 2, C.sub);
}
text('UP / DOWN  (SCROLL)', cl.x + 8, cl.y + cl.h - 20, 2, C.sub);

// 头像卡
const tr = box(183, 686, 300, 182, C.tray, C.thin, 1);
text('4  TRAY  300x182  (SUSPECTS A..V)', tr.x + 8, tr.y + 6, 2, C.ink);
for (let i = 0; i < 7; i++) {
  const xx = tr.x + 10 + i * 40;
  fillRect(xx, tr.y + 30, 34, 40, C.btn); strokeRect(xx, tr.y + 30, 34, 40, C.thin, 1);
  text(String.fromCharCode(65 + i), xx + 10, tr.y + 44, 2, C.ink);
}
text('CLICK = SELECT    THEN CLICK CELL = PLACE', tr.x + 10, tr.y + 84, 2, C.sub);
text('MAX 2 ROWS, COLUMNS AUTO', tr.x + 10, tr.y + 110, 2, C.sub);
text('DOUBLE CLICK = PLACE NOW', tr.x + 10, tr.y + 136, 2, C.sub);

// ③ 棋盘
const bd = box(765, 458, 677, 677, C.board);
text('5  BOARD  677x677  (5x5 / 6x6 / 7x7 AUTO)', bd.x + 10, bd.y + 8, 2, C.ink);
const pad = 40, n = 5, gap = 6;
const cs = Math.floor((bd.w - pad * 2 - gap * (n - 1)) / n);
for (let r = 0; r < n; r++) {
  for (let c = 0; c < n; c++) {
    const xx = bd.x + pad + c * (cs + gap);
    const yy = bd.y + pad + 12 + r * (cs + gap);
    fillRect(xx, yy, cs, cs, C.cell); strokeRect(xx, yy, cs, cs, C.thin, 1);
    if (r === 2 && c === 2) { text('X', xx + cs / 2 - 6, yy + cs / 2 - 8, 3, [200, 60, 60]); }
  }
}
text('EACH CELL: FACE + X + NOTE + WALL/DOOR EDGES', bd.x + pad, bd.y + bd.h - 26, 2, C.sub);
text('CLICK = X OUT     SELECT+CLICK = PLACE     DOUBLE = PLACE', bd.x + pad, bd.y + bd.h - 8, 2, C.sub);

// ④ 右栏
const rt = box(1375, 427, 383, 733, C.right);
text('6  RIGHT PANEL  383x733', rt.x + 10, rt.y + 8, 2, C.ink);
const rows = [
  'PROGRESS   0 / 5 CORRECT',
  'SCORE',
  'VIOLATIONS  WHICH CLUES BROKEN',
  'SHARE',
  'TOAST  (HINT TEXT)',
  '--- ACTIONS ---',
  'HINT     (MAGNIFIER)',
  'UNDO',
  'RESET LEVEL',
  'REVEAL',
  'SUBMIT   (FILL BOARD FIRST)',
  'BACK TO SELECT',
];
let iy = rt.y + 34;
for (const t of rows) {
  fillRect(rt.x + 12, iy, rt.w - 24, 28, C.btn); strokeRect(rt.x + 12, iy, rt.w - 24, 28, C.thin, 1);
  text(t, rt.x + 20, iy + 8, 2, C.ink);
  iy += 34;
}

// ⑤ 坐标尺
text('7  RULER: A..G / 1..7 TICKS AROUND BOARD', bd.x, bd.y - 20, 2, C.sub);

// 分区图例
let lyy = 700;   // ★ 挪到左下角外侧，别压左栏标题
const bxs = [
  ['TOPBAR / STATUS', C.top],
  ['CLUE AREA', C.clue],
  ['SUSPECT TRAY', C.tray],
  ['BOARD / CELLS', C.cell],
  ['RIGHT PANEL', C.right],
];
for (const [name, col] of bxs) {
  fillRect(lf.x + 6, lyy, 22, 12, col); strokeRect(lf.x + 6, lyy, 22, 12, C.thin, 1);
  text(name, lf.x + 34, lyy + 2, 1, C.sub);
  lyy += 18;
}

// ── 编码 PNG ─────────────────────────────────────────────────────────
function crc32(buf) {
  let c, crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    c = (crc ^ buf[i]) & 0xFF;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) {
  raw[y * (W * 3 + 1)] = 0;
  px.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3);
}
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(OUT, png);
console.log('  OK 写出 ' + path.relative(ROOT, OUT) + '  ' + Math.round(png.length / 1024) + ' KB  ' + W + 'x' + H);
