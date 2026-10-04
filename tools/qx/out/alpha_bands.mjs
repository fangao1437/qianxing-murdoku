// alpha_bands.mjs — alpha distribution + per-band mean RGB, to detect translucent halos.
// Usage: node tools/qx/out/alpha_bands.mjs 107003 107239 107241 107062
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const FF = process.env.FFMPEG || 'C:/Users/18182/AppData/Local/Temp/ffs/node_modules/ffmpeg-static/ffmpeg.exe';
const TMP = path.resolve('tools/qx/out/.raw');
fs.mkdirSync(TMP, { recursive: true });

function probe(file) {
  let err = '';
  try { execFileSync(FF, ['-hide_banner', '-i', file], { stdio: ['ignore', 'ignore', 'pipe'] }); }
  catch (e) { err = (e.stderr || '').toString(); }
  const m = err.match(/,\s*(\d+)x(\d+)[\s,]/);
  return { w: +m[1], h: +m[2] };
}

const bands = [
  ['a=0', (a) => a === 0],
  ['1-16', (a) => a > 0 && a <= 16],
  ['17-128', (a) => a > 16 && a <= 128],
  ['129-254', (a) => a > 128 && a <= 254],
  ['a=255', (a) => a === 255],
];

for (const id of process.argv.slice(2)) {
  const file = path.resolve(`tools/qx/sprites/2/${id}.png`);
  if (!fs.existsSync(file)) { console.log(`${id}: MISSING`); continue; }
  const { w, h } = probe(file);
  const raw = path.join(TMP, `${id}.rgba`);
  execFileSync(FF, ['-y', '-loglevel', 'error', '-i', file, '-f', 'rawvideo', '-pix_fmt', 'rgba', raw], { stdio: 'ignore' });
  const buf = fs.readFileSync(raw); fs.unlinkSync(raw);
  const px = w * h;
  const stat = bands.map(() => ({ n: 0, r: 0, g: 0, b: 0 }));
  for (let i = 0; i < px; i++) {
    const a = buf[i * 4 + 3];
    for (let bi = 0; bi < bands.length; bi++) {
      if (bands[bi][1](a)) { const s = stat[bi]; s.n++; s.r += buf[i * 4]; s.g += buf[i * 4 + 1]; s.b += buf[i * 4 + 2]; break; }
    }
  }
  console.log(`\n${id}  ${w}x${h}  (${px} px)`);
  bands.forEach(([name], i) => {
    const s = stat[i];
    const pct = ((s.n / px) * 100).toFixed(2);
    const rgb = s.n ? `rgb(${(s.r / s.n).toFixed(1)},${(s.g / s.n).toFixed(1)},${(s.b / s.n).toFixed(1)})` : '-';
    console.log(`  alpha ${name.padEnd(8)} ${String(s.n).padStart(8)} px  ${pct.padStart(6)}%   ${rgb}`);
  });
  // corners (0,0) and center
  const at = (x, y) => { const i = (y * w + x) * 4; return `rgba(${buf[i]},${buf[i + 1]},${buf[i + 2]},${buf[i + 3]})`; };
  console.log(`  corner(0,0)=${at(0, 0)}  center=${at(w >> 1, h >> 1)}  corner(w-1,h-1)=${at(w - 1, h - 1)}`);
}
