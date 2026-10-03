// tools/qx/make_icons.mjs —— **一次性生成最终版 6 个图标素材的 scene JSON**
//
// 用户要求（2026-10-03）：
//   「现在的素材尺寸不对，你先按要求生成需要的素材，直接按最终版图标要求来设计，
//     返回菜单，重置关卡，提示以及勾叉确认卡已经有图标了，你抄下来调整尺寸即可，
//     提交和撤销两个键你参考常见设计自己设计出来，然后把六个素材存到对应地址后
//     把位置和设置要求给我」
//
// ⇒ 这一版**统一按 256×256 画布、纯白几何图形**（与参考图里的白图标风格一致），
//   尺寸留足（图标约占画布 70%），这样**在编辑器里生成时按需要的像素尺寸缩放**即可 ——
//   用户实测：**素材尺寸在"生成时"就定死，之后改素材/图片尺寸都无效**，
//   所以画布做大一点、内容居中，方便以后按不同目标尺寸重新导出。
//
// 六个图标：
//   hex-back     返回菜单      ←「抄」参考图的返回箭头（左向箭头 + 竖臂）
//   hex-redo     重置关卡      ←「抄」参考图的环形箭头
//   hex-hint     提示(放大镜)  ←「抄」参考图的放大镜
//   hex-confirm  勾叉确认卡    ←「抄」参考图的 ✓ / ✗ 双键卡
//   hex-submit   提交          ← 自己设计：向上箭头（通用「提交/上传」语义）
//   hex-undo     撤销          ← 自己设计：逆时针弧形箭头（通用「撤销」语义）
//
// 用法：node tools/qx/make_icons.mjs            # 只写 scene JSON
//       node tools/qx/make_icons.mjs --export   # 顺便调 API 导出 .gia

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SCENES = path.join(ROOT, 'tools', 'qx', 'scenes');
const W = 256, H = 256;
const WHITE = '#FFFFFF';
const DARK = '#232838';      // 与现有 btn-hex 的内芯色一致
const DARK2 = '#1B2030';     // 描边色

/** 画布中心 128,128；下面所有坐标都按"中心点 + 尺寸"写，方便调 */
const el = (id, type, x, y, width, height, color, rotation = 0, opacity = 1, zIndex = 0) =>
  ({ id, type, x, y, width, height, rotation, color, opacity, zIndex });

/** 三角底边默认朝上；`rot` 用来转向（0=上 90=右 180=下 270=左） */
const tri = (id, x, y, w, h, rot, color = WHITE, z = 0) => el(id, 'triangle', x, y, w, h, color, rot, 1, z);
const rect = (id, x, y, w, h, rot = 0, color = WHITE, z = 0) => el(id, 'rectangle', x, y, w, h, color, rot, 1, z);
const ring = (id, x, y, d, color = WHITE, z = 0) => el(id, 'ring', x, y, d, d, color, 0, 1, z);
const box = (id, x, y, w, h, rot = 0, color = WHITE, z = 0) => el(id, 'textbox', x, y, w, h, color, rot, 1, z);

const scene = (name, elements) => ({
  canvas: { width: W, height: H, background: '#00000000' },
  elements,
  meta: { sourceType: 'editor', sourceName: name, warnings: [] },
});

const icons = {};

// ── 1) 返回菜单：左向箭头 + 右侧竖臂（像 ↩）────────────────────────────
icons['hex-back'] = scene('murdoku-hex-back', [
  // ★ 2026-10-03 微调：第一版太细长（缩略图里像"⌐"）。现在把箭头尖加大、杆加粗、
  //   竖臂缩短并和横杆右端对齐 —— 目标是在 64×64 也一眼认得出是「返回」。
  rect('bar',   132, 128, 150, 38, 0),                    // 横杆（加粗 30→38）
  tri ('head',   60, 128, 92, 92, 270),                   // 箭头尖（70→92，朝左）
  rect('stem',  188,  92,  38,  96, 0),                   // 竖臂（114→96，与杆同粗、右端对齐）
]);

// ── 2) 重置关卡：圆环 + 顶部缺口处的箭头（↻）────────────────────────────
icons['hex-redo'] = scene('murdoku-hex-redo', [
  ring('ring',  128, 132, 168, WHITE, 0),                 // 环
  tri ('head',  196,  48, 62, 62, 90),                    // 箭头（朝右）
  rect('gap',   128,  48, 132, 26, 0, '#00000000', 0),    // 占位：缺口（透明，仅用于示意）
]);

// ── 3) 提示：放大镜（镜框 + 45° 手柄）──────────────────────────────────
icons['hex-hint'] = scene('murdoku-hex-hint', [
  ring('lens',  110, 108, 132),                           // 镜框
  rect('grip',  180, 178, 34, 96, 45),                    // 手柄（45°）
]);

// ── 4) 勾叉确认卡：深色卡片 + ✓ + ✗ ────────────────────────────────────
icons['hex-confirm'] = scene('murdoku-hex-confirm', [
  rect('card',  128, 128, 236, 108, 0, DARK, 0),          // 深色卡底
  rect('card2', 128, 128, 224,  96, 0, DARK2, 1),         // 内芯（做出 6px 描边感）
  // ✓（用两个旋转矩形拼）
  rect('ok1',    76, 134, 20, 52, -45, WHITE, 2),
  rect('ok2',    98, 116, 20, 76,  45, WHITE, 2),
  // ✗（两个 ±45° 矩形）
  rect('no1',   184, 128, 20, 76,  45, WHITE, 2),
  rect('no2',   184, 128, 20, 76, -45, WHITE, 2),
]);

// ── 5) 提交：向上箭头（↑）—— 通用「提交/上传」语义 ───────────────────────
icons['hex-submit'] = scene('murdoku-hex-submit', [
  rect('shaft', 128, 152, 34, 116, 0),                    // 杆
  tri ('head',  128,  62, 92, 84, 0),                     // 箭头（朝上）
]);

// ── 6) 撤销：逆时针弧形箭头（↶）—— 与"重置"的顺时针环区分开 ──────────────
icons['hex-undo'] = scene('murdoku-hex-undo', [
  ring('ring',  128, 132, 168, WHITE, 0),                 // 弧身
  tri ('head',   60,  48, 62, 62, 270),                   // 箭头（朝左，表示逆时针）
]);

fs.mkdirSync(SCENES, { recursive: true });
for (const [name, sc] of Object.entries(icons)) {
  const p = path.join(SCENES, name + '.json');
  fs.writeFileSync(p, JSON.stringify(sc, null, 2), 'utf8');
  console.log('  ✅ ' + path.relative(ROOT, p) + '  （' + sc.elements.length + ' 个图元）');
}
console.log('  共 ' + Object.keys(icons).length + ' 个图标 scene 已写出');
