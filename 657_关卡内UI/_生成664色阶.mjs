// 664：用仓库 fit-primitive-shape.mjs 把设计图票券的 3 级 45° 斜向阶梯
// 拟合成零溢出的 100003 等腰三角图元，输出 664_色阶图元.json 供构建器消费。
//
// 设计图逐点采样（6236×3508 原 PNG）得到的票券主色：
//   #8C2800 28.0% 底/右半   #AF3200 26.2% 中阶/左半   #CB4C19 10.1% 亮阶/左上角
// 分界在票券局部坐标为 45° 斜线 lx + ly = D：
//   中阶 lx+ly < 18      亮阶 lx+ly < −42
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOL = path.join(ROOT, 'qianxing-murdoku-tool/art/tools/fit-primitive-shape.mjs');
const OUT = path.join(DIR, '预览');
const T = { cx: 384, cy: 211, w: 140, h: 66, rot: -13 };
const A = -T.rot * Math.PI / 180;                 // 渲染器 ctx.rotate(-rot) ⇒ 屏幕 +13°
const toScreen = (lx, ly) => [T.cx + lx * Math.cos(A) - ly * Math.sin(A), T.cy + lx * Math.sin(A) + ly * Math.cos(A)];
const toLocal = (x, y) => {
  const dx = x - T.cx, dy = y - T.cy;
  return [dx * Math.cos(A) + dy * Math.sin(A), -dx * Math.sin(A) + dy * Math.cos(A)];
};
// 票券局部矩形（顺时针）
const RECT = [[-70, -33], [70, -33], [70, 33], [-70, 33]].map(([a, b]) => toScreen(a, b));
// Sutherland–Hodgman：用 lx+ly < D 裁凸多边形
function cut(poly, D) {
  const f = p => { const [lx, ly] = toLocal(p[0], p[1]); return lx + ly - D; };
  const out = [];
  for (let i = 0; i < poly.length; i++) {
    const p = poly[i], q = poly[(i + 1) % poly.length], fp = f(p), fq = f(q);
    if (fp <= 0) out.push(p);
    if ((fp < 0 && fq > 0) || (fp > 0 && fq < 0)) {
      const t = fp / (fp - fq);
      out.push([p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]);
    }
  }
  return out;
}
const r2 = v => Math.round(v * 1000) / 1000;
const STEPS = [
  { tag: 'mid', D: 18, color: '#AF3200' },
  { tag: 'hi', D: -42, color: '#CB4C19' },
];
const result = { ticket: T, ticketRect: RECT.map(p => p.map(r2)), steps: [] };
for (const s of STEPS) {
  const poly = cut(RECT, s.D).map(p => p.map(r2));
  if (poly.length < 3) throw Error(s.tag + ' 裁剪后不足 3 点');
  const polyFile = path.join(OUT, `_664_poly_${s.tag}.json`);
  const fitFile = path.join(OUT, `_664_fit_${s.tag}.json`);
  fs.writeFileSync(polyFile, JSON.stringify(poly));
  const log = execFileSync(process.execPath, [TOOL,
    `--poly=${polyFile}`, `--color=${s.color}`, `--out=${fitFile}`,
    '--max-depth=7', '--target=0.9995', '--min-coverage=99.9'], { encoding: 'utf8' });
  const fit = JSON.parse(fs.readFileSync(fitFile, 'utf8'));
  const rots = fit.elements.map(e => e.rotation);
  const cov = fit.verification;
  console.log(`[${s.tag}] poly=${poly.length}点 elements=${fit.elements.length}`,
    `coverage=${cov.coverage}% overflow=${cov.overflowVertices}`,
    `rot=[${Math.min(...rots).toFixed(1)}, ${Math.max(...rots).toFixed(1)}]`,
    `negRot=${rots.filter(r => r < 0).length}`);
  result.steps.push({ ...s, D: s.D, polygon: poly, elements: fit.elements,
    verification: { coverage: cov.coverage, overflowVertices: cov.overflowVertices, sampled: cov.sampled } });
}
fs.writeFileSync(path.join(DIR, '664_色阶图元.json'), JSON.stringify(result, null, 2));
console.log('\n总图元', result.steps.reduce((n, s) => n + s.elements.length, 0),
  '→ 664_色阶图元.json');
