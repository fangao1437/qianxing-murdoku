// READ-ONLY probe: for each named control, list the "type name" strings (the
// Chinese control-type labels) and every short text field with its field path.
// usage: node _wip/probe-types.mjs <gil> <name> [<name>...]
import * as gil from "../tools/gil/gilread.mjs";

const args = process.argv.slice(2);
const file = args[0];
const names = args.slice(1);
const g = gil.readGil(file);

function walk(fields, path, out) {
  for (const f of fields) {
    const p = path + "/" + f.field;
    if (f.isText) out.push([p, f.payload.toString("utf8")]);
    if (f.sub) walk(f.sub, p, out);
  }
}

for (const nm of names) {
  const r = g.byName.get(nm);
  if (!r) { console.log("== " + nm + ": NOT FOUND"); continue; }
  const out = [];
  walk(r.field.sub, "", out);
  console.log("== " + nm + " #" + r.id + " parent=" + r.parentId);
  for (const [p, s] of out) {
    console.log("   " + p + "  " + JSON.stringify(s));
  }
}
