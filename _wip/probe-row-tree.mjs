// READ-ONLY probe: dump the subtree of one or more named controls.
// usage: node _wip/probe-row-tree.mjs <gil> <name> [depth]
import * as gil from "../tools/gil/gilread.mjs";

const args = process.argv.slice(2);
const file = args[0];
const target = args[1];
const depth = Number(args[2] || 4);

const g = gil.readGil(file);
const byId = new Map();
for (const r of g.recs.values ? g.recs.values() : []) byId.set(r.id, r);

export function kidsOf(r) {
  const cl = r && r.childList;
  if (!cl) return [];
  let ids = [];
  if (Buffer.isBuffer(cl.payload)) { try { ids = gil.asIdList(cl.payload) || []; } catch (e) { ids = []; } }
  if (!ids.length && cl.sub) { try { ids = gil.asIdList(cl.sub) || []; } catch (e) { ids = []; } }
  return (ids || []).map((i) => byId.get(i)).filter(Boolean);
}

function desc(f, d) {
  const pad = "  ".repeat(d);
  const head = pad + "#" + f.field + " wt=" + f.wt;
  if (f.isText) return head + " text=" + JSON.stringify(f.payload.toString("utf8"));
  if (f.payload && Buffer.isBuffer(f.payload)) return head + " b=" + f.payload.length + " hex=" + f.payload.toString("hex").slice(0, 32);
  return head + (f.sub ? " msg(" + f.sub.length + ")" : "");
}

function show(r, d, max, sub) {
  const pad = "  ".repeat(d);
  console.log(pad + (r.name || "?") + " #" + r.id + " parent=" + r.parentId + " names=" + JSON.stringify(r.names));
  if (sub) {
    for (const f of r.field.sub) console.log(desc(f, d + 1));
    if (d >= max) return;
    for (const k of kidsOf(r)) show(k, d + 1, max, sub);
  }
}

if (target === "--list") {
  console.log([...g.byName.keys()].sort().join("\n"));
} else {
  const r = g.byName.get(target);
  if (!r) {
    console.log("no record named " + target);
  } else {
    show(r, 0, depth, true);
  }
}
