// plate_survey.mjs — survey 底板 sprite candidates for use as a full-board dark base plate.
// Decodes PNG -> raw RGB(A) with ffmpeg, computes coverage / mean RGB / luminance / plainness.
//
// Usage: node tools/qx/out/plate_survey.mjs
// Output: console table (sorted by luminance asc) + tools/qx/out/plate_survey.json

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const FF = process.env.FFMPEG || 'C:/Users/18182/AppData/Local/Temp/ffs/node_modules/ffmpeg-static/ffmpeg.exe';
const TMP = path.resolve('tools/qx/out/.raw');
fs.mkdirSync(TMP, { recursive: true });

function probe(file) {
  // ffmpeg prints stream info to stderr and exits non-zero without an output; capture it.
  let err = '';
  try {
    execFileSync(FF, ['-hide_banner', '-i', file], { stdio: ['ignore', 'ignore', 'pipe'] });
  } catch (e) {
    err = (e.stderr || '').toString();
  }
  const m = err.match(/,\s*(\d+)x(\d+)[\s,]/);
  if (!m) throw new Error('cannot parse dimensions for ' + file + '\n' + err);
  return { w: +m[1], h: +m[2] };
}

function decode(file) {
  const { w, h } = probe(file);
  const raw = path.join(TMP, path.basename(file, '.png') + '.rgba');
  execFileSync(FF, ['-y', '-loglevel', 'error', '-i', file, '-f', 'rawvideo', '-pix_fmt', 'rgba', raw], { stdio: 'ignore' });
  const buf = fs.readFileSync(raw);
  fs.unlinkSync(raw);
  return { w, h, buf, px: w * h };
}

export function analyze(file) {
  const { w, h, buf, px } = decode(file);
  const need = px * 4;
  if (buf.length < need) throw new Error(`short raw buffer for ${file}: ${buf.length} < ${need}`);

  let cov = 0;              // alpha > 16
  let n = 0;                // alpha > 128  (measured set)
  let sr = 0, sg = 0, sb = 0, sa = 0;
  let sq = 0;               // sum of squared deviations across the 3 channels (pooled)
  let minL = 255, maxL = 0;

  // first pass: sums
  for (let i = 0; i < px; i++) {
    const a = buf[i * 4 + 3];
    if (a > 16) cov++;
    if (a > 128) { sr += buf[i * 4]; sg += buf[i * 4 + 1]; sb += buf[i * 4 + 2]; sa += a; n++; }
  }
  if (n === 0) return { file, w, h, px, coverage: +(cov / px).toFixed(4), n: 0, r: null, g: null, b: null, a: null, lum: null, std: null };

  const mr = sr / n, mg = sg / n, mb = sb / n;
  // second pass: pooled channel stddev (plainness) + luminance range
  for (let i = 0; i < px; i++) {
    if (buf[i * 4 + 3] <= 128) continue;
    const r = buf[i * 4], g = buf[i * 4 + 1], b = buf[i * 4 + 2];
    sq += (r - mr) ** 2 + (g - mg) ** 2 + (b - mb) ** 2;
    const l = 0.299 * r + 0.587 * g + 0.114 * b;
    if (l < minL) minL = l;
    if (l > maxL) maxL = l;
  }
  const std = Math.sqrt(sq / (3 * n));
  const lum = 0.299 * mr + 0.587 * mg + 0.114 * mb;

  return {
    file, id: +path.basename(file, '.png'), w, h, px,
    coverage: +(cov / px).toFixed(4),
    n,
    r: +mr.toFixed(1), g: +mg.toFixed(1), b: +mb.toFixed(1), a: +(sa / n).toFixed(1),
    lum: +lum.toFixed(1),
    std: +std.toFixed(1),
    lumMin: +minL.toFixed(1), lumMax: +maxL.toFixed(1),
  };
}

// ---- CLI ----
const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname.replace(/^\//, ''));
if (isMain || process.argv[1]?.endsWith('plate_survey.mjs')) {
  const dirs = process.argv.slice(2);
  const roots = dirs.length ? dirs : ['tools/qx/sprites/2', 'tools/qx/samples/mono'];
  let files = [];
  for (const d of roots) {
    if (!fs.existsSync(d)) { console.error('# missing dir (skipped): ' + d); continue; }
    for (const f of fs.readdirSync(d)) if (f.toLowerCase().endsWith('.png')) files.push(path.join(d, f));
  }
  console.error(`# ${files.length} candidate PNGs from: ${roots.join(', ')}`);

  const rows = [];
  for (const f of files) {
    try { rows.push(analyze(f)); }
    catch (e) { console.error('! ' + f + ': ' + e.message); }
  }
  rows.sort((a, b) => (a.lum ?? 999) - (b.lum ?? 999));

  const out = path.resolve('tools/qx/out/plate_survey.json');
  fs.writeFileSync(out, JSON.stringify({ generated: new Date().toISOString(), roots, rows }, null, 1));

  // console table: darkest first
  const pad = (s, n) => String(s).padEnd(n);
  console.log(pad('id', 8) + pad('size', 10) + pad('cover', 8) + pad('meanRGB', 16) + pad('lum', 7) + pad('std', 7) + 'lumRange  file');
  for (const r of rows.slice(0, 60)) {
    const size = `${r.w}x${r.h}`;
    const rgb = r.r === null ? '(no opaque px)' : `rgb(${r.r},${r.g},${r.b})`;
    console.log(pad(r.id ?? '?', 8) + pad(size, 10) + pad(r.coverage, 8) + pad(rgb, 16) + pad(r.lum ?? '-', 7) + pad(r.std ?? '-', 7) + pad(`${r.lumMin}-${r.lumMax}`, 14) + r.file);
  }
  console.error(`# wrote ${out} (${rows.length} rows)`);
}
