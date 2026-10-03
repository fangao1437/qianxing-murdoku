// tools/qx/make_icons.mjs —— 生成最终版 6 个图标素材的 scene JSON
//
// ★★ 2026-10-03 第二版：**按昨天的布局图（docs/布局图-关卡内-v3.png）实际尺寸重做**，
//    并且**每个图标都配深色底色**（用户：「很明显太大了，你按昨天的布局图去量尺寸，
//    同时配上底色，不要只有形状」）。
//
// 尺寸与配色**逐项来自 `tools/draw_layout_v2.mjs`**（那张布局图就是这个脚本画的）：
//     function iconBox(x, y, s, glyph) {
//       fillRect(x, y, s, s, C.iconBg);          // 底色
//       strokeRect(x, y, s, s, [90,90,95], 2);   // 2px 描边
//       text(glyph, …);                          // 图形
//     }
//     C.iconBg = [30,30,34] = #1E1E22      C.iconOn = [245,245,245] = #F5F5F5
//
//     ① 返回菜单   iconBox(60,  48, **62**, '<')
//     ② ✓/✗ 确认卡 dashedRect(430, 46, **150×66**)，里面 iconBox(438,52,**54**,'Y') / (500,52,**54**,'X')
//     ③ 右上三键   iconBox(1448, 48 / 144 / 240, **70**)
//     ④ 放大镜     iconBox(1448, 694, **70**)
//
// ⚠️ **画布尺寸就取真实显示尺寸** —— 因为用户实测「素材尺寸在生成时就定死，
//    之后改素材/图片尺寸都无效」，所以必须按最终要显示的像素数生成。
//
// 用法：node tools/qx/make_icons.mjs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SCENES = path.join(ROOT, 'tools', 'qx', 'scenes');

const BG = '#1E1E22';        // 底（来自布局图 C.iconBg）
const FG = '#F5F5F5';        // 图形（来自布局图 C.iconOn）
const ED = '#5A5A5F';        // 描边（布局图 strokeRect 用的 [90,90,95]）

/** 画布按真实尺寸走；坐标以画布中心为基准算 */
const S = { back: 62, key: 70, card: [150, 66], ok: 54 };

const mkEl = (id, type, x, y, w, h, color, rotation = 0, zIndex = 0) =>
  ({ id, type, x, y, width: w, height: h, rotation, color, opacity: 1, zIndex });

/** 底板 + 2px 描边（照抄 iconBox 的画法；用两个矩形做出"描边"效果） */
function plate(w, h, z0 = 0) {
  return [
    mkEl('edge', 'rectangle', w / 2, h / 2, w, h, ED, 0, z0),             // 外描边
    mkEl('base', 'rectangle', w / 2, h / 2, w - 4, h - 4, BG, 0, z0 + 1), // 内底
  ];
}
const tri = (id, x, y, w, h, rot, z) => mkEl(id, 'triangle', x, y, w, h, FG, rot, z);
const rect = (id, x, y, w, h, rot, z) => mkEl(id, 'rectangle', x, y, w, h, FG, rot, z);
const ring = (id, x, y, d, z) => mkEl(id, 'ring', x, y, d, d, FG, 0, z);

const scene = (name, w, h, elements) => ({
  canvas: { width: w, height: h, background: '#00000000' },
  elements,
  meta: { sourceType: 'editor', sourceName: name, warnings: [] },
});

const icons = {};

// ── ① 返回菜单 62×62：左箭头 + 右侧竖臂（↩）──────────────────────────
{
  const w = S.back, h = S.back, cx = w / 2, cy = h / 2, z = 2;
  icons['hex-back'] = scene('murdoku-hex-back', w, h, [
    ...plate(w, h),
    rect('bar',  cx - 1, cy + 2, 34, 9, 0, z + 1),        // 横杆
    tri ('head', cx - 17, cy + 2, 20, 22, 270, z + 2),    // 箭头尖（朝左）
    rect('stem', cx + 14, cy - 6, 9, 22, 0, z + 1),       // 竖臂
  ]);
}

// ── ② 勾叉确认卡 150×66：底 + ✓ + ✗（照布局图：两枚 54 的键位）──────────
{
  const w = S.card[0], h = S.card[1], k = S.ok;
  const okX = 8, noX = w - 8 - k, ky = (h - k) / 2;
  icons['hex-confirm'] = scene('murdoku-hex-confirm', w, h, [
    ...plate(w, h),
    // 两枚键位底
    mkEl('okBase', 'rectangle', okX + k / 2, ky + k / 2, k - 4, k - 4, ED, 0, 2),
    mkEl('noBase', 'rectangle', noX + k / 2, ky + k / 2, k - 4, k - 4, ED, 0, 2),
    // ✓（两段旋转矩形）
    rect('ok1', okX + 18, ky + 30, 8, 20, -45, 3),
    rect('ok2', okX + 29, ky + 23, 8, 30,  45, 3),
    // ✗（两段 ±45°）
    rect('no1', noX + 27, ky + 27, 8, 30,  45, 3),
    rect('no2', noX + 27, ky + 27, 8, 30, -45, 3),
  ]);
}

// ── ③ 提交 70×70：向上箭头 ↑ ──────────────────────────────────────────
{
  const w = S.key, h = S.key, cx = w / 2, cy = h / 2, z = 2;
  icons['hex-submit'] = scene('murdoku-hex-submit', w, h, [
    ...plate(w, h),
    rect('shaft', cx, cy + 6, 9, 30, 0, z + 1),
    tri ('head',  cx, cy - 14, 24, 22, 0, z + 2),
  ]);
}

// ── ④ 重置关卡 70×70：圆环 + 顺时针箭头（↻）────────────────────────────
{
  const w = S.key, h = S.key, cx = w / 2, cy = h / 2, z = 2;
  icons['hex-redo'] = scene('murdoku-hex-redo', w, h, [
    ...plate(w, h),
    ring('ring', cx, cy + 2, 44, z + 1),                   // 环
    tri ('head', cx + 20, cy - 19, 18, 18, 90, z + 2),     // 箭头（朝右）
  ]);
}

// ── ⑤ 撤销 70×70：逆时针弧形箭头（↶）—— 与"重置"的顺时针区分 ────────────
{
  const w = S.key, h = S.key, cx = w / 2, cy = h / 2, z = 2;
  icons['hex-undo'] = scene('murdoku-hex-undo', w, h, [
    ...plate(w, h),
    ring('ring', cx, cy + 2, 44, z + 1),
    tri ('head', cx - 20, cy - 19, 18, 18, 270, z + 2),    // 箭头（朝左）
  ]);
}

// ── ⑥ 提示（放大镜）70×70 ──────────────────────────────────────────────
{
  const w = S.key, h = S.key, cx = w / 2, cy = h / 2, z = 2;
  icons['hex-hint'] = scene('murdoku-hex-hint', w, h, [
    ...plate(w, h),
    ring('lens', cx - 4, cy - 4, 36, z + 1),               // 镜框
    rect('grip', cx + 13, cy + 13, 9, 22, 45, z + 2),      // 手柄
  ]);
}

fs.mkdirSync(SCENES, { recursive: true });
for (const [name, sc] of Object.entries(icons)) {
  const p = path.join(SCENES, name + '.json');
  fs.writeFileSync(p, JSON.stringify(sc, null, 2), 'utf8');
  console.log('  ✅ ' + name.padEnd(14) + sc.canvas.width + '×' + sc.canvas.height
    + '  图元 ' + sc.elements.length);
}
console.log('  共 ' + Object.keys(icons).length + ' 个（画布=最终显示尺寸，含深色底 + 2px 描边）');
