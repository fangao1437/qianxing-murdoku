// border_probe.mjs — fetch 9-slice border metadata for candidate ids.
// A sprite WITH a border json (and non-zero insets) is designed to be 9-sliced / stretched as a panel.
// Usage: node tools/qx/out/border_probe.mjs 106053 106001 ...
import fs from 'node:fs';
import path from 'node:path';

const BASE = process.env.QX_BASE || 'https://qx.070077.xyz';
const ids = process.argv.slice(2).map(Number).filter(Boolean);
const outDir = path.resolve('tools/qx/out/borders');
fs.mkdirSync(outDir, { recursive: true });

const results = [];
for (const id of ids) {
  const url = `${BASE}/api/library/border/${id}.json`;
  let rec = { id, url, ok: false };
  try {
    const r = await fetch(url);
    if (!r.ok) { rec.status = r.status; }
    else {
      const text = await r.text();
      fs.writeFileSync(path.join(outDir, `${id}.json`), text);
      rec.ok = true;
      rec.body = text.slice(0, 300);
    }
  } catch (e) { rec.error = e.message; }
  results.push(rec);
}
fs.writeFileSync(path.resolve('tools/qx/out/borders.json'), JSON.stringify(results, null, 1));
for (const r of results) console.log(r.ok ? `OK   ${r.id}  ${r.body}` : `MISS ${r.id}  status=${r.status ?? r.error}`);
