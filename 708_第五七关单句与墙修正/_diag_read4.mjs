import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '..', '..');
const R = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil/gilread.mjs')));
const g = R.readGil(path.join(DIR, '708_第五七关单句与墙修正.gil'));
console.log('总记录数', g.recs.length);
for (const r of g.recs) {
  if (r.name && /^what\.4\./.test(r.name)) {
    const leaves = R.textsOf(r.field.sub, []);
    console.log(r.name, '=>', JSON.stringify(leaves.map(f => f.payload.toString('utf8'))));
  }
}
