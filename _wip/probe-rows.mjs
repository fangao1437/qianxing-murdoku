// READ-ONLY probe: per-row child inventory of assets/row.* — names, duplicates,
// the person id (`who.*` text) and the mark text (`letter.*` text).
// usage: node _wip/probe-rows.mjs <gil>
import * as gil from "../tools/gil/gilread.mjs";

const g = gil.readGil(process.argv[2]);
const byId = new Map();
for (const r of g.recs.values()) byId.set(r.id, r);

function kids(r) {
  const cl = r && r.childList;
  if (!cl) return [];
  let ids = [];
  if (Buffer.isBuffer(cl.payload)) { try { ids = gil.asIdList(cl.payload) || []; } catch (e) { ids = []; } }
  return ids.map((i) => byId.get(i)).filter(Boolean);
}

// text under /505/503/75/510/501 (the control's own text box)
function ownText(r) {
  if (!r || !r.field || !r.field.sub) return null;
  let hit = null;
  (function walk(fs, path) {
    for (const f of fs) {
      const p = path + "/" + f.field;
      if (p === "/505/503/75/510/501" && f.isText) hit = f.payload.toString("utf8");
      if (f.sub) walk(f.sub, p);
    }
  })(r.field.sub, "");
  return hit;
}

const rows = [...g.byName.keys()].filter((n) => /^row\./.test(n)).sort();
console.log("rows: " + rows.length);
let dupTotal = 0;
for (const nm of rows) {
  const r = g.byName.get(nm);
  const ks = kids(r);
  const names = ks.map((k) => k.name);
  const seen = new Map();
  const dups = [];
  for (const n of names) {
    seen.set(n, (seen.get(n) || 0) + 1);
    if (seen.get(n) === 2) dups.push(n);
  }
  if (dups.length) dupTotal += dups.length;
  const parts = ks.map((k) => {
    const base = k.name.split(".")[0];
    const t = ownText(k);
    return k.name + (t != null ? "=" + JSON.stringify(t) : "-");
  });
  // childList vs actual: names recorded but whose #504 parent points elsewhere
  const orphans = ks.filter((k) => k.parentId !== r.id).map((k) => k.name + "(parent=" + k.parentId + ")");
  console.log(
    nm.padEnd(9) + " " + String(ks.length) + " kids" +
    (dups.length ? "  ★DUP=" + dups.join(",") : "") +
    (orphans.length ? "  ★ORPHAN=" + orphans.join(",") : "") +
    "   " + parts.join(" | ")
  );
}
console.log("---");
console.log("duplicate child names total: " + dupTotal);
