// READ-ONLY probe: pretty-print the whole field tree of a named control.
// usage: node _wip/probe-dump.mjs <gil> <name> [maxDepth]
import * as gil from "../tools/gil/gilread.mjs";

const file = process.argv[2];
const name = process.argv[3];
const maxDepth = Number(process.argv[4] || 12);
const g = gil.readGil(file);
const r = g.byName.get(name);
if (!r) { console.log("NOT FOUND " + name); process.exit(1); }

function walk(fields, depth, path) {
  for (const f of fields) {
    const pad = "  ".repeat(depth);
    const p = path + "/" + f.field;
    if (f.isText) {
      console.log(pad + f.field + " STR " + JSON.stringify(f.payload.toString("utf8")));
    } else if (f.sub) {
      console.log(pad + f.field + " MSG (" + f.sub.length + ")");
      if (depth < maxDepth) walk(f.sub, depth + 1, p);
    } else if (f.wt === 5) {
      console.log(pad + f.field + " F32 " + f.f);
    } else if (f.wt === 0) {
      console.log(pad + f.field + " VARINT " + f.num);
    } else {
      console.log(pad + f.field + " wt" + f.wt + " b(" + (f.payload ? f.payload.length : 0) + ") " +
        (f.payload ? f.payload.toString("hex").slice(0, 60) : ""));
    }
  }
}

console.log("== " + name + " #" + r.id + " parent=" + r.parentId);
walk(r.field.sub, 0, "");
