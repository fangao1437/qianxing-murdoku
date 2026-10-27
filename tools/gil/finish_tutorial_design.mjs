// v351：把教程文字色板写入存档，并补齐缩略棋盘的墙、门和项目家具引用。
// 用法：node tools/gil/finish_tutorial_design.mjs [570-教程色板-v350.gil] [571-教程设计对齐-v351.gil]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  readGil, encodeMsg, cloneField, findChildListTop, asIdList, setChildList,
  stateBlocks, pairOf, setPair, bigIds, textsOf,
} from "./gilread.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const P = (p) => (path.isAbsolute(p) ? p : path.join(ROOT, p));
const IN = P(process.argv[2] || "570-教程色板-v350.gil");
const OUT = P(process.argv[3] || "571-教程设计对齐-v351.gil");
const g = readGil(IN);
const byName = new Map();
for (const r of g.recs) if (typeof r.name === "string" && !byName.has(r.name)) byName.set(r.name, r);
let maxId = BigInt(g.maxId);
const expectedColors = new Map();
const addedNames = [];

function nodesAt(fields, pathArr) {
  let level = fields;
  for (let i = 0; i < pathArr.length; i++) {
    const hits = level.filter((f) => f.field === pathArr[i] && f.sub);
    if (i === pathArr.length - 1) return hits;
    level = hits.flatMap((f) => f.sub);
  }
  return [];
}

function setTextColor(name, argb) {
  const rec = byName.get(name);
  if (!rec) throw new Error("missing text control " + name);
  const nodes = nodesAt(rec.field.sub, [505, 503, 75]);
  if (!nodes.length) throw new Error("missing text config " + name);
  for (const node of nodes) {
    let leaf = node.sub.find((f) => f.field === 504 && f.wt === 0);
    if (!leaf) {
      leaf = { field: 504, wt: 0, num: 0n };
      node.sub.push(leaf);
    }
    leaf.num = BigInt(argb >>> 0);
  }
  expectedColors.set(name, argb >>> 0);
}

const C = {
  title: 0xFFF3EDE0, subtitle: 0xFFE8A23C, clueLead: 0xFFFFCB7A,
  body: 0xFFD3CCBD, clue: 0xFFE9E2D3, note: 0xFFBDB6A7,
  button: 0xFFBDB6A7, legend: 0xFFBDB6A7, badge: 0xFF22180A,
};
let colored = 0;
for (const tag of ["home", "l1", "l2"]) {
  const base = "teach.text." + tag;
  const entries = [
    [".title", C.title], [".subtitle", C.subtitle],
    [".body.1", C.clueLead], [".body.1b", C.body], [".body.2", C.clue], [".body.3", C.note],
    [".btn.prev", C.button], [".btn.next", C.button],
  ];
  for (let i = 1; i <= 9; i++) entries.push([".legend." + i, C.legend]);
  for (const [suffix, color] of entries) { setTextColor(base + suffix, color); colored++; }
}
for (let i = 1; i <= 5; i++) {
  const base = "teach.text.home.card." + i;
  setTextColor(base + ".num", C.badge);
  setTextColor(base + ".title", C.title);
  setTextColor(base + ".body", C.body);
  colored += 3;
}

function holderOf(id) {
  const stack = [g.tree];
  while (stack.length) {
    const arr = stack.pop();
    if (!Array.isArray(arr)) continue;
    for (let i = 0; i < arr.length; i++) {
      const f = arr[i];
      if (f.sub) {
        if ((bigIds(f.sub, [])[0] || {}).num === BigInt(id)) return { arr, index: i };
        stack.push(f.sub);
      }
    }
  }
  return null;
}

function resolve(name) {
  if (byName.has(name)) return byName.get(name);
  if (name.includes("/")) {
    const split = name.lastIndexOf("/");
    const parent = byName.get(name.slice(0, split));
    const childName = name.slice(split + 1);
    if (parent) {
      const cl = findChildListTop(parent.field.sub);
      const ids = cl ? (asIdList(cl.payload, true) || []) : [];
      return ids.map((id) => g.recs.find((r) => Number(r.id) === Number(id)))
        .find((r) => r && r.name === childName);
    }
  }
  return null;
}

function setImage(rec, imageId, argb) {
  for (const node of nodesAt(rec.sub, [505, 503, 84])) {
    for (const [field, value] of [[502, argb], [503, imageId], [504, 1]]) {
      let leaf = node.sub.find((f) => f.field === field && f.wt === 0);
      if (!leaf) { leaf = { field, wt: 0, num: 0n }; node.sub.push(leaf); }
      leaf.num = BigInt(value >>> 0);
    }
  }
}

function cloneOne(protoName, parentName, newName, w, h, x, y, art) {
  const proto = resolve(protoName);
  const parent = byName.get(parentName);
  if (!proto) throw new Error("no proto " + protoName);
  if (!parent) throw new Error("no parent " + parentName);
  if (byName.has(newName)) throw new Error("duplicate name " + newName);
  const cf = cloneField(proto.field);
  const idLeaf = bigIds(cf.sub, [])[0];
  if (!idLeaf) throw new Error("no id leaf " + protoName);
  maxId += 1n;
  const nid = Number(maxId);
  idLeaf.num = maxId;
  const text = textsOf(cf.sub, []).find((q) => q.payload && q.payload.toString("utf8") === proto.name);
  if (!text) throw new Error("no name leaf " + protoName);
  text.payload = Buffer.from(newName, "utf8");
  text.len = text.payload.length;
  const blocks = [];
  stateBlocks(cf.sub, blocks);
  for (const b of blocks) {
    const size = pairOf(b, 505); if (size) setPair(size, w, h);
    const pos = pairOf(b, 504); if (pos) setPair(pos, x, y);
  }
  const parentLeaf = cf.sub.find((f) => f.field === 504 && f.wt === 0);
  if (parentLeaf) parentLeaf.num = BigInt(parent.id);
  if (art) setImage(cf, art.imageId, art.color);
  const holder = holderOf(proto.id);
  if (!holder) throw new Error("no record holder " + protoName);
  holder.arr.splice(holder.index + 1, 0, cf);
  let cl = findChildListTop(parent.field.sub);
  if (!cl) {
    cl = { field: 503, wt: 2, sub: [], payload: Buffer.alloc(0), len: 0, s1: 0 };
    parent.field.sub.push(cl);
  }
  const ids = (asIdList(cl.payload, true) || []).map(Number);
  ids.push(nid);
  setChildList(cl, ids);
  byName.set(newName, { name: newName, id: nid, field: cf, parentId: parent.id });
  addedNames.push(newName);
}

const levels = [
  {
    tag: "l1", rows: 5, cols: 5, pitch: 84,
    walls: [["v",1,3],["v",2,3],["v",3,3],["h",3,1],["h",3,2],["h",3,3],["h",3,4],["v",4,4],["v",5,4]],
    doors: [["v",2,3],["h",3,2],["h",3,4]],
    furniture: [
      ["furn.table.v2",1,1,2,1], ["furn.plant",1,2], ["furn.plant",5,1], ["furn.plant",5,3],
      ["furn.rug.2",3,1,3,2], ["furn.rug.2",2,4,2,5], ["furn.chair",4,2], ["furn.chair",5,4],
    ],
  },
  {
    tag: "l2", rows: 6, cols: 6, pitch: 68,
    walls: [["v",1,4],["v",2,4],["v",3,4],["v",4,5],["h",3,1],["h",3,2],["h",3,3],["h",3,4],["h",3,5],["h",4,6],["v",4,3],["v",5,3],["v",6,4],["h",5,4]],
    doors: [["v",2,4],["h",3,1],["v",4,3]],
    furniture: [
      ["furn.chair",1,1], ["furn.chair",2,4], ["furn.rug",1,4], ["furn.rug",3,3], ["furn.rug",3,4],
      ["furn.rug",5,1], ["furn.rug",6,1], ["furn.table.h2",1,2,1,3], ["furn.table.1",6,5],
      ["furn.plant",3,2], ["furn.plant",5,4], ["furn.plant",6,4], ["furn.shelf",6,2], ["furn.statue",1,6],
    ],
  },
];

const boardCX = 1100, boardCY = 460;
const px = (screenX) => screenX - 800;
const py = (screenY) => 450 - screenY;
let made = 0;
for (const L of levels) {
  const parent = "teach." + L.tag;
  L.furniture.forEach((f, index) => {
    const [kind, r1, c1, r2 = r1, c2 = c1] = f;
    const cx = boardCX + ((c1 + c2) / 2 - (L.cols + 1) / 2) * L.pitch;
    const cy = boardCY + ((r1 + r2) / 2 - (L.rows + 1) / 2) * L.pitch;
    const w = (c2 - c1 + 1) * L.pitch - 12;
    const h = (r2 - r1 + 1) * L.pitch - 12;
    cloneOne("things/" + kind, parent, parent + ".furn." + (index + 1), w, h, px(cx), py(cy));
    made++;
  });
  for (const [kind, list, color, thickness] of [["wall", L.walls, 0xFF29282B, 5], ["door", L.doors, 0xFFDC5B28, 8]]) {
    list.forEach(([dir, r, c], index) => {
      const vertical = dir === "v";
      const x = vertical ? boardCX + (c - L.cols / 2) * L.pitch : boardCX + (c - (L.cols + 1) / 2) * L.pitch;
      const y = vertical ? boardCY + (r - (L.rows + 1) / 2) * L.pitch : boardCY + (r - L.rows / 2) * L.pitch;
      const length = L.pitch - (kind === "door" ? 22 : 0);
      const w = vertical ? thickness : length;
      const h = vertical ? length : thickness;
      cloneOne(parent + ".clue", parent, parent + "." + kind + "." + (index + 1), w, h, px(x), py(y), { imageId: 100001, color });
      made++;
    });
  }

  // 层序：地板 → 家具 → 头像 → 墙 → 门；其余面板控件保持在前。
  const rec = byName.get(parent);
  const cl = findChildListTop(rec.field.sub);
  const ids = (asIdList(cl.payload, true) || []).map(Number);
  const priority = (id) => {
    const own = byName.get(id);
    const old = own || g.recs.find((r) => Number(r.id) === Number(id));
    const n = old && old.name || "";
    if (n.includes(".board.")) return 10;
    if (n.includes(".furn.")) return 20;
    if (n.includes(".av.")) return 30;
    if (n.includes(".wall.")) return 40;
    if (n.includes(".door.")) return 50;
    return 0;
  };
  const rank = new Map(ids.map((id, i) => [id, i]));
  ids.sort((a, b) => priority(a) - priority(b) || rank.get(a) - rank.get(b));
  setChildList(cl, ids);
}

fs.writeFileSync(OUT, g.pack(encodeMsg(g.tree)));
const check = readGil(OUT);
if (check.recs.length !== g.recs.length + made) throw new Error("record count mismatch");
const checkByName = new Map(check.recs.filter((r) => r.name).map((r) => [r.name, r]));
for (const [name, expected] of expectedColors) {
  const nodes = nodesAt(checkByName.get(name).field.sub, [505, 503, 75]);
  if (!nodes.length || nodes.some((node) => {
    const leaf = node.sub.find((f) => f.field === 504 && f.wt === 0);
    return !leaf || (Number(leaf.num) >>> 0) !== expected;
  })) throw new Error("font color readback mismatch " + name);
}
for (const name of addedNames) if (!checkByName.has(name)) throw new Error("added control missing " + name);
console.log("verified", colored, "text colors and", made, "new controls after disk readback");
console.log("colored", colored, "text controls; added", made, "board controls; records", check.recs.length);
console.log("wrote", path.basename(OUT), fs.statSync(OUT).size);
