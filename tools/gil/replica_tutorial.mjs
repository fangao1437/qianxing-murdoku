// v352：按 mobile-1959 设计稿逐页复刻教程。棋盘直接解析设计 SVG；文字全部静态、多色。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  readGil, encodeMsg, cloneField, findChildListTop, asIdList, setChildList,
  stateBlocks, pairOf, pairValue, setPair, bigIds, textsOf,
} from "./gilread.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const P = (p) => path.isAbsolute(p) ? p : path.join(ROOT, p);
const IN = P(process.argv[2] || "571-教程设计对齐-v351.gil");
const OUT = P(process.argv[3] || "572-教程逐页复刻-v352.gil");
const g = readGil(IN);
const byName = new Map();
for (const r of g.recs) if (r.name && !byName.has(r.name)) byName.set(r.name, r);
let maxId = BigInt(g.maxId);
let serial = 0;
const added = [];
const protoHolders = new Map();

function holderOf(id) {
  const stack = [g.tree];
  while (stack.length) {
    const arr = stack.pop();
    for (let i = 0; arr && i < arr.length; i++) {
      const f = arr[i];
      if (!f.sub) continue;
      if ((bigIds(f.sub, [])[0] || {}).num === BigInt(id)) return { arr, index: i };
      stack.push(f.sub);
    }
  }
  throw new Error("record holder not found " + id);
}
function nodesAt(fields, pathArr) {
  let level = fields;
  for (let i = 0; i < pathArr.length; i++) {
    const hits = level.filter((f) => f.field === pathArr[i] && f.sub);
    if (i === pathArr.length - 1) return hits;
    level = hits.flatMap((f) => f.sub);
  }
  return [];
}
function cloneOne(kind, parentName, newName, w, h, sx, sy) {
  const protoName = kind === "container" ? "stage" : kind === "button" ? "result.next" : kind === "text" ? "hud.subtitle" : "clues.bg";
  const proto = byName.get(protoName);
  const parent = byName.get(parentName);
  if (!proto || !parent) throw new Error("missing proto/parent " + protoName + " / " + parentName);
  if (byName.has(newName)) throw new Error("duplicate " + newName);
  const cf = cloneField(proto.field);
  maxId += 1n;
  const nid = Number(maxId);
  bigIds(cf.sub, [])[0].num = maxId;
  const t = textsOf(cf.sub, []).find((q) => q.payload && q.payload.toString("utf8") === proto.name);
  if (!t) throw new Error("name leaf missing " + protoName);
  t.payload = Buffer.from(newName, "utf8"); t.len = t.payload.length;
  const blocks = []; stateBlocks(cf.sub, blocks);
  for (const b of blocks) {
    const size = pairOf(b, 505); if (size) setPair(size, w, h);
    const pos = pairOf(b, 504); if (pos) setPair(pos, sx - 800, 450 - sy);
  }
  const parentLeaf = cf.sub.find((f) => f.field === 504 && f.wt === 0);
  if (parentLeaf) parentLeaf.num = BigInt(parent.id);
  const inheritedChildren = findChildListTop(cf.sub);
  if (inheritedChildren) setChildList(inheritedChildren, []);
  let holder = protoHolders.get(protoName);
  if (!holder) { holder = holderOf(proto.id); protoHolders.set(protoName, holder); }
  holder.arr.splice(holder.index + 1, 0, cf);
  let cl = findChildListTop(parent.field.sub);
  if (!cl) { cl = { field: 503, wt: 2, sub: [], payload: Buffer.alloc(0), len: 0, s1: 0 }; parent.field.sub.push(cl); }
  const ids = (asIdList(cl.payload, true) || []).map(Number); ids.push(nid); setChildList(cl, ids);
  const rec = { name: newName, id: nid, field: cf, parentId: parent.id };
  byName.set(newName, rec); added.push(newName);
  return rec;
}
function art(rec, imageId, color, rotation) {
  for (const node of nodesAt(rec.field.sub, [505, 503, 84])) {
    for (const [field, value] of [[502, color >>> 0], [503, imageId], [504, 1]]) {
      let leaf = node.sub.find((f) => f.field === field && f.wt === 0);
      if (!leaf) { leaf = { field, wt: 0, num: 0n }; node.sub.push(leaf); }
      leaf.num = BigInt(value);
    }
  }
  if (rotation) {
    const blocks = []; stateBlocks(rec.field.sub, blocks);
    for (const b of blocks) {
      let f = b.sub.find((x) => x.field === 508);
      if (!f) { f = { field: 508, wt: 2, sub: [], len: 0, payload: null, isText: false }; b.sub.push(f); }
      f.sub = [{ field: 3, wt: 5, f: rotation }]; f.len = 5;
    }
  }
}
function textProps(rec, value, size, color, align = 0) {
  for (const node of nodesAt(rec.field.sub, [505, 503, 75])) {
    const setNum = (field, value2) => {
      let leaf = node.sub.find((f) => f.field === field && f.wt === 0);
      if (!leaf) { leaf = { field, wt: 0, num: 0n }; node.sub.push(leaf); }
      leaf.num = BigInt(value2 >>> 0);
    };
    setNum(504, color); setNum(512, Math.round(size)); setNum(513, Math.max(8, Math.round(size) - 2));
    setNum(508, align); setNum(509, 1);
    const adaptive = node.sub.find((f) => f.field === 502);
    if (adaptive) node.sub.splice(node.sub.indexOf(adaptive), 1);
    let txt = node.sub.find((f) => f.field === 510 && f.sub);
    if (!txt) { txt = { field: 510, wt: 2, sub: [], payload: Buffer.alloc(0), len: 0 }; node.sub.push(txt); }
    let leaf = txt.sub.find((f) => f.field === 501 && f.wt === 2);
    if (!leaf) { leaf = { field: 501, wt: 2, sub: null, payload: Buffer.alloc(0), len: 0, isText: true }; txt.sub.push(leaf); }
    leaf.payload = Buffer.from(value, "utf8"); leaf.len = leaf.payload.length; leaf.isText = true;
  }
}

const S = 1480 / 2268;
const X = (x) => 60 + (x - 36) * S;
const Y = (y) => 121 + (y - 36) * S;
const U = (v) => v * S;
const C = {
  panel: 0xFF0E1320, card: 0xFF151B28, card2: 0xFF111722, border: 0xFF28303F,
  text: 0xFFF3EDE0, text2: 0xFFBDB6A7, muted: 0xFF827C6D, body: 0xFFD3CCBD,
  gold: 0xFFFFCB7A, accent: 0xFFE8A23C, blue: 0xFF9ED8FF, green: 0xFF8FC08A,
  red: 0xFFD0553F, dark: 0xFF22180A, quote: 0xFFE9E2D3,
};
function rect(parent, name, sx, sy, w, h, color, image = 100001, rotation = 0) {
  const r = cloneOne("image", parent, name, Math.max(1, w), Math.max(1, h), sx, sy); art(r, image, color, rotation); return r;
}
function label(parent, name, value, sx, sy, w, h, size, color, align = 0) {
  // 千星文本框过矮/过窄会整段不渲染；保留中心，只扩大可绘制区域。
  w = Math.max(w, Math.ceil(size * 1.5));
  h = Math.max(h, Math.ceil(size * 2));
  const r = cloneOne("text", parent, name, w, h, sx, sy); textProps(r, value, size, color, align); return r;
}
function card(parent, name, sx, sy, w, h) {
  rect(parent, name + ".border", sx, sy, w, h, C.border, 107102);
  rect(parent, name, sx, sy, w - 2, h - 2, C.card, 107102);
}
function widthOf(text, size) {
  let n = 0;
  for (const ch of text) n += ch.charCodeAt(0) < 128 ? size * 0.56 : size;
  return n;
}
function rich(parent, name, segments, sx, sy, size, lineH = 24) {
  let x = sx;
  segments.forEach((seg, i) => {
    const [value, color = C.body] = seg;
    const w = widthOf(value, size) + 12;
    label(parent, name + "." + i, value, x + w / 2, sy, w, lineH, size, color);
    x += w;
  });
}
function circleLabel(parent, name, value, sx, sy, diameter, bg, fg, size) {
  rect(parent, name + ".bg", sx, sy, diameter, diameter, bg, 100002);
  label(parent, name, value, sx, sy, diameter, diameter, size, fg, 1);
}
function header(page, o) {
  const p = page;
  label(p, p + ".eyebrow", o.eyebrow, X(96) + 300, Y(91), 600, 28, 17, C.accent);
  label(p, p + ".title", o.title, X(96) + 330, Y(130), 660, 48, 27, C.text);
  if (o.sub) label(p, p + ".sub", o.sub, X(96) + 400, Y(174), 800, 30, 17, C.text2);
  if (o.cur) rich(p, p + ".stepnum", [["第 ", C.text2], [String(o.cur), C.gold], [" / " + o.total + " 步", C.text2]], X(1900), Y(111), 17, 30);
}
function stepper(page, items, cur) {
  if (!items) return;
  const totalW = 2148 * S, gap = 12 * S, w = Math.min(300 * S, (totalW - gap * (items.length - 1)) / items.length);
  const start = X(96) + (totalW - (w * items.length + gap * (items.length - 1))) / 2;
  items.forEach((item, i) => {
    const x = start + i * (w + gap) + w / 2, y = Y(261), active = i + 1 === cur, done = i + 1 < cur;
    rect(page, page + ".step." + (i + 1), x, y, w, U(66), active ? 0xFF3A2B19 : C.card2, 107102);
    circleLabel(page, page + ".stepn." + (i + 1), done ? "✓" : String(i + 1), x - w / 2 + U(32), y, U(38), active ? C.accent : done ? 0xFF29402B : C.card, active ? C.dark : done ? C.green : C.muted, 13);
    label(page, page + ".stept." + (i + 1), item, x + U(15), y, w - U(70), U(40), 13, active ? C.text : C.text2, 1);
  });
}
function stepCard(page, o, sx, sy, w, h) {
  card(page, page + ".main", sx, sy, w, h);
  const left = sx - w / 2 + U(28), top = sy - h / 2;
  rect(page, page + ".tagbg", left + U(70), top + U(30), U(140), U(38), 0xFF3A2B19, 107102);
  label(page, page + ".tag", o.tag, left + U(70), top + U(30), U(180), U(36), 17, C.gold, 1);
  label(page, page + ".heading", o.title, sx, top + U(91), w - U(56), U(58), 27, C.text);
  o.lines.forEach((segments, i) => rich(page, page + ".body." + i, segments, left, top + U(137) + i * U(34), 15, Math.max(26, U(32))));
}
function chipsCard(page, kicker, items, sx, sy, w, h) {
  card(page, page + ".chips", sx, sy, w, h);
  const left = sx - w / 2 + U(28), top = sy - h / 2;
  label(page, page + ".chipsk", kicker, left + 100, top + U(22), 200, U(24), 13, C.muted);
  let x = left;
  items.forEach((item, i) => {
    const [value, tone] = item, cw = widthOf(value, 13) + U(38), color = tone === "blue" ? C.blue : tone === "gold" ? C.gold : C.green;
    rect(page, page + ".chip." + i, x + cw / 2, top + U(66), cw, U(44), tone === "blue" ? 0xFF1B2B37 : tone === "gold" ? 0xFF392D1C : 0xFF203125, 107102);
    label(page, page + ".chipt." + i, value, x + cw / 2, top + U(66), cw - 4, U(36), 13, color, 1);
    x += cw + U(12);
  });
}
function noteCard(page, value, sx, sy, w, h) {
  card(page, page + ".note", sx, sy, w, h);
  const left = sx - w / 2 + U(28);
  circleLabel(page, page + ".notei", "i", left + U(14), sy, U(28), 0xFF1B2B37, C.blue, 13);
  label(page, page + ".notet", value, left + U(45) + (w - U(80)) / 2, sy, w - U(80), h - U(20), 13, C.text2);
}
function clueCard(page, o, sx, sy, w, h) {
  card(page, page + ".clue", sx, sy, w, h);
  const left = sx - w / 2 + U(28), top = sy - h / 2;
  label(page, page + ".cluek", "线索来源", left + 80, top + U(20), 160, U(24), 13, C.muted);
  circleLabel(page, page + ".clueface", o.letter, left + U(32), top + U(70), U(64), o.color || 0xFF5E6B8C, C.text, 17);
  label(page, page + ".cluename", o.name, left + U(82) + (w - U(130)) / 2, top + U(52), w - U(130), U(30), 14, C.muted);
  rich(page, page + ".cluesay", o.say, left + U(82), top + U(87), 14, Math.max(26, U(34)));
}
function footer(page, o) {
  label(page, page + ".skip", o.tag === "home" ? "稍后再看" : "跳过教程", X(96) + 100, Y(1005), 200, 30, 13, C.muted);
  if (o.cur > 1) {
    rect(page, page + ".prevbg", X(1950), Y(1005), U(180), U(66), 0xFF1B2230, 107102);
    label(page, page + ".prevtext", "上一步", X(1950), Y(1005), 130, 34, 13, C.text2, 1);
  }
  rect(page, page + ".nextbg", X(2150), Y(1005), U(190), U(66), C.accent, 107102);
  label(page, page + ".nexttext", o.tag === "home" ? "开始办案" : o.cur === o.total ? "开始试玩" : "下一步", X(2150), Y(1005), 150, 36, 13, C.dark, 1);
}
function legend(page, rooms) {
  const x = X(1936), top = Y(316);
  label(page, page + ".legendtitle", "图例", x + 50, top, 100, 26, 13, C.muted);
  const rows = rooms.map((r) => [r[0], r[1], "square"]).concat([["墙", 0xFF29282B, "square"], ["门", 0xFFDC5B28, "square"], ["棋子", C.text, "A"], ["候选", C.muted, "A?"], ["排除", C.red, "×"], ["笔记", C.text2, "b"], ["受害者", 0xFFBFE6F2, "V"], ["可站", C.green, "椅"], ["不可站", 0xFF6B5B49, "桌"]]);
  rows.forEach((row, i) => {
    const y = top + U(42) + i * U(35);
    if (row[2] === "square") rect(page, page + ".lg." + i, x + U(11), y, U(22), U(22), row[1], 107102);
    else circleLabel(page, page + ".lg." + i, row[2], x + U(15), y, U(30), row[2] === "×" ? C.panel : row[1], row[2] === "×" ? C.red : row[2] === "A?" ? C.muted : C.dark, 13);
    label(page, page + ".lgt." + i, row[0], x + U(45) + 50, y, 100, U(30), 13, C.text2);
  });
  label(page, page + ".coord", "坐标 =（行,列）\n行号自上而下，列号自左而右", x + U(85), top + U(42) + rows.length * U(35) + U(20), 190, U(68), 13, C.muted);
}

function colorOf(value, opacity) {
  if (!value || value === "none") return null;
  let rgb = value;
  if (value.startsWith("rgb(")) rgb = "#" + value.match(/[\d.]+/g).slice(0, 3).map((n) => Number(n).toString(16).padStart(2, "0")).join("");
  if (!rgb.startsWith("#")) return 0xFFFFFFFF;
  const alpha = Math.round(Math.max(0, Math.min(1, Number(opacity == null ? 1 : opacity))) * 255);
  return ((alpha << 24) | parseInt(rgb.slice(1), 16)) >>> 0;
}
function attrs(s) {
  const out = {}; for (const m of s.matchAll(/([\w-]+)="([^"]*)"/g)) out[m[1]] = m[2]; return out;
}
function cloneExisting(proto, parentName, newName, w, h, sx, sy) {
  const parent = byName.get(parentName);
  const cf = cloneField(proto.field);
  maxId += 1n;
  const nid = Number(maxId);
  bigIds(cf.sub, [])[0].num = maxId;
  const t = textsOf(cf.sub, []).find((q) => q.payload && q.payload.toString("utf8") === proto.name);
  if (t) { t.payload = Buffer.from(newName, "utf8"); t.len = t.payload.length; }
  const blocks = []; stateBlocks(cf.sub, blocks);
  for (const b of blocks) {
    const sizePair = pairOf(b, 505); if (sizePair) setPair(sizePair, w, h);
    const posPair = pairOf(b, 504); if (posPair) setPair(posPair, sx - 800, 450 - sy);
  }
  const parentLeaf = cf.sub.find((f) => f.field === 504 && f.wt === 0);
  if (parentLeaf) parentLeaf.num = BigInt(parent.id);
  const inherited = findChildListTop(cf.sub); if (inherited) setChildList(inherited, []);
  const holderKey = "existing:" + proto.id;
  let holder = protoHolders.get(holderKey);
  if (!holder) { holder = holderOf(proto.id); protoHolders.set(holderKey, holder); }
  holder.arr.splice(holder.index + 1, 0, cf);
  let cl = findChildListTop(parent.field.sub);
  const ids = (asIdList(cl.payload, true) || []).map(Number); ids.push(nid); setChildList(cl, ids);
  const rec = { name:newName, id:nid, field:cf, parentId:parent.id };
  byName.set(newName, rec);
  if (t) added.push(newName);
  return rec;
}
function childrenOf(rec) {
  const cl = findChildListTop(rec.field.sub);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  return ids.map((id) => g.recs.find((r) => Number(r.id) === Number(id))).filter(Boolean);
}
function existingFurniture(page, kind, cx, cy, w, h, bx, by, scale) {
  const things = byName.get("things");
  if (!things) throw new Error("project furniture references missing: things");
  const proto = childrenOf(things).find((r) => r.name === kind);
  if (!proto) throw new Error("project furniture reference missing things/" + kind);
  cloneExisting(proto, page, page + ".furn." + kind + "." + (++serial),
    Math.max(1, w * scale), Math.max(1, h * scale), bx(cx), by(cy));
}
function projectFurniture(page, tag, bx, by, scale) {
  const l1 = [
    ["furn.table.v2",676,262,108,216],["furn.plant",788,206,108,108],["furn.plant",676,654,108,108],["furn.plant",900,654,108,108],
    ["furn.rug.2",732,430,216,108],["furn.rug.2",1068,318,216,108],["furn.chair",788,542,108,108],["furn.chair",1012,654,108,108],
  ];
  const l2 = [
    ["furn.chair",667.5,197.5,89,89],["furn.table.h2",807,197.5,178,89],["furn.rug",946.5,197.5,89,89],["furn.statue",1132.5,197.5,89,89],
    ["furn.chair",946.5,290.5,89,89],["furn.plant",760.5,383.5,89,89],["furn.rug.2",900,383.5,178,89],
    ["furn.rug.3",667.5,616,89,178],["furn.plant",946.5,569.5,89,89],["furn.shelf",760.5,662.5,89,89],
    ["furn.plant",946.5,662.5,89,89],["furn.table.1",1039.5,662.5,89,89],
  ];
  for (const piece of tag === "l1" ? l1 : l2) existingFurniture(page, ...piece, bx, by, scale);
}
function board(page, id, sx, sy, size, sharedBase, mode) {
  const file = path.join(ROOT, "docs/tutorial-design/boards", id + ".svg");
  let svg = fs.readFileSync(file, "utf8").replace(/<defs>[\s\S]*?<\/defs>/g, "");
  const scale = size / 656, baseX = sx - size / 2, baseY = sy - size / 2;
  const bx = (v) => baseX + (Number(v) - 572) * scale, by = (v) => baseY + (Number(v) - 102) * scale;
  const bw = (v) => Number(v) * scale;
  let index = 0;
  const nextName = () => page + ".svg." + (++index);
  const closeGroup = svg.indexOf("</g>");
  const baseSvg = closeGroup >= 0 ? svg.slice(0, closeGroup) : svg;
  const overlaySvg = closeGroup >= 0 ? svg.slice(closeGroup + 4) : "";
  function renderSvg(source, baseOnly) {
  const target = baseOnly && sharedBase ? sharedBase : page;
  for (const m of source.matchAll(/<(rect|ellipse|circle|line|path|text)\b([^>]*)>(?:([^<]*)<\/\1>)?/g)) {
    const kind = m[1], a = attrs(m[2]), value = m[3] || "";
    if (baseOnly && id !== "home-1") {
      const roomCell = kind === "rect" && ["#D9CDB4","#C3CDD4","#D4C8BC","#BECFB0"].includes(a.fill);
      if (!roomCell && !(kind === "rect" && (a.x === "572" || a.x === "608"))) continue;
    }
    if (id === "home-1" && ((kind === "circle" && (Math.abs(Number(a.r) - 18.36) < 0.01 || Math.abs(Number(a.r) - 6.2424) < 0.01)) || (kind === "rect" && Math.abs(Number(a.width) - 18.36) < 0.01))) continue;
    if (kind === "rect") {
      const color = colorOf(a.fill, a.opacity); if (!color || Number(a.width) > 650 && a.x == null) continue;
      rect(target, nextName(), bx(a.x) + bw(a.width) / 2, by(a.y) + bw(a.height) / 2, bw(a.width), bw(a.height), color, a.rx ? 107102 : 100001);
    } else if (kind === "ellipse" || kind === "circle") {
      const color = colorOf(a.fill, a.opacity); if (!color) continue;
      const rx = kind === "circle" ? a.r : a.rx, ry = kind === "circle" ? a.r : a.ry;
      rect(target, nextName(), bx(a.cx), by(a.cy), bw(rx) * 2, bw(ry) * 2, color, 100002);
      if (a.stroke && a["stroke-dasharray"]) {
        // 候选虚线在设计里由文字和半透明圆共同表达；实色圆保留，避免自造虚线素材。
      }
    } else if (kind === "line") {
      const color = colorOf(a.stroke, a.opacity); if (!color) continue;
      const x1 = bx(a.x1), y1 = by(a.y1), x2 = bx(a.x2), y2 = by(a.y2);
      const len = Math.hypot(x2 - x1, y2 - y1), deg = Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI;
      rect(target, nextName(), (x1 + x2) / 2, (y1 + y2) / 2, len, Math.max(1, bw(a["stroke-width"])), color, 100001, -deg);
    } else if (kind === "path") {
      const color = colorOf(a.stroke, a.opacity); if (!color) continue;
      const nums = (a.d.match(/-?[\d.]+/g) || []).map(Number);
      for (let i = 0; i + 3 < nums.length; i += 4) {
        const x1 = bx(nums[i]), y1 = by(nums[i + 1]), x2 = bx(nums[i + 2]), y2 = by(nums[i + 3]);
        const len = Math.hypot(x2 - x1, y2 - y1), deg = Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI;
        rect(target, nextName(), (x1 + x2) / 2, (y1 + y2) / 2, len, Math.max(1, bw(a["stroke-width"])), color, 100001, -deg);
      }
    } else if (kind === "text") {
      const size2 = bw(a["font-size"]), color = colorOf(a.fill, a.opacity) || C.text;
      const w = Math.max(size2, widthOf(value, size2) + 8), h = size2 * 1.45;
      label(target, nextName(), value, bx(a.x), by(a.y) - size2 * 0.28, w, h, size2, color, 1);
    }
  }
  }
  if (sharedBase) {
    // 这一趟只负责「共享底图」：底图控件全部挂在 td.<tag>.board 上（每关一份）。
    // 家具由 tutorial_ui 在运行时从 things/furn.* 模板实例化，追加在同一块 board 的末尾，
    // 因此层序是：td.<tag>.bg < board 底图 < 地毯 < 家具 < 各页提示层（page 在 board 之后）。
    renderSvg(baseSvg, true);
    return;
  }
  if (mode === "overlay") {
    // v358：底图已由上面那趟共享底图提供，本页只复刻提示层。
    // 之前这里没有 sharedBase/mode 参数，13 页各自又画了一整套不透明格子底板，
    // 把 td.<tag>.board（底图 + 运行时家具）整块盖住 ⇒ 家具实例化了也看不见（真机"卡住"的根因）。
  } else {
    renderSvg(baseSvg, true);
  }
  renderSvg(overlaySvg, false);
  if (id === "home-1") {
    const pawns = [["A",676,206,C.text],["D",900,318,C.gold],["B",1124,430,C.text],["C",788,542,C.text],["V",1012,654,C.blue]];
    for (const [letter, x, y, color] of pawns) label(page, nextName(), letter, bx(x), by(y) - bw(8), bw(70), bw(70), bw(54), color, 1);
  }
  label(page, page + ".caption", "•  " + ({
    "home-1":"5×5 棋盘 · 三间屋 · 三扇门 · 5 枚棋子", "l1-1":"空盘：三间屋、三扇门", "l1-2":"选中 A，第 5 列亮起", "l1-3":"长按进度环 + 行/列将被划掉", "l1-4":"A 的 4 个可能格（A?）", "l1-5":"B/A 已放，3 个候选被划掉", "l1-6":"C 已放，(4,2) 被划掉", "l1-7":"D/V 互换的两种摆法，一种被划掉", "l1-8":"终局：金圈 D、蓝标 V", "l2-1":"6×6、四间屋；侧廊只有一扇门", "l2-2":"5 个地毯格先划掉", "l2-3":"第 3 列高亮 + 两个候选 + 红叉", "l2-4":"地毯已划掉，门是通道"
  })[id], sx, sy + size / 2 + U(25), size, U(32), 13, C.muted, 1);
}

const HOME_CARDS = [
  { title:"目标：摆满当事人，再指认", lines:[[["每名当事人（含 1 名受害者）"]],[["各占一格。全部摆好后，"]],[["指出谁是"],["盗窃者",C.gold],["；如果受害者"]],[["屋里还有别人，还要说清同伙。"]]]},
  { title:"每行、每列恰好一人", lines:[[["放下一个人，整行整列"]],[["会自动打叉。一行不能站两个，"]],[["一列也不能。"]]]},
  { title:"只能站「可站」的格子", lines:[[["椅子、地毯",C.blue],["可以站；"]],[["桌子、植物、书架、",C.gold]],[["雕像",C.gold],["不能站。"]]]},
  { title:"「旁边 / 隔壁」怎么算", lines:[[["只算上下左右贴着的格子："]],[["同屋直接算，跨屋必须中间有门",C.gold]],[["隔着墙不算。盗窃者也一定"]],[["落在受害者隔壁的屋里。"]]]},
  { title:"操作：轻点＝笔记，双击＝预放置，长按＝正式放下", lines:[[["点一张线索卡选中人。轻点格子＝铅笔笔记；"],["双击＝预放置",C.gold]],[["（先占位，可反悔）；"],["按住不放、进度环走完＝正式放下",C.gold],["。"]],[["放错了用右边的撤销。"]]]},
];
const L1 = [
  { tag:"第 1 / 8 步 · 认识", title:"三间屋、三扇门", lines:[[["左边是线索卡，中间是棋盘，右边是工具。棋盘 5×5，"]],[["三间屋：大屋、内室、外间；"],["粗线是墙，橙色是门",C.gold],["。"]],[["行号 1–5 从上往下，列号 1–5 从左往右。"]]], chips:["棋盘速览",[["5×5 · 5 人"],["三间屋"],["三扇门","blue"]]], note:"受害者也在这 5 个人里，别把他落下。", board:"l1-1" },
  { tag:"第 2 / 8 步 · 操作", title:"点一张卡，就选中卡上那个人", lines:[[["卡上写的是他的口供 —— 说的可能是别人。"]],[["选中后，话里提到的位置会在棋盘上"],["亮起来",C.gold],["。"]],[["再点一次取消选中。"]]], note:"卡上的人＝你要放下的人；卡上的话＝他的口供，可能说的是别人。", clue:{letter:"A",color:0xFFC96A5C,name:"卡 1 · 值班保安（A）",say:[["「收藏家 "],["在 第 5 列",C.gold],["」"]]}, board:"l1-2" },
  { tag:"第 3 / 8 步 · 操作", title:"轻点＝笔记，双击＝预放置，长按＝正式放下", lines:[[["轻点格子只留一个铅笔小字，不占位；"],["双击先把棋子预放在格子上",C.gold]],[["（可以反悔，不算正式落子）；按住不放、等进度环走完，"]],[["才真正落下大字母。放下后，这一行这一列会自动打叉。"]]], note:"放错了？撤销、重做、重置都在右边。", chips:["三种手势",[["轻点＝笔记"],["双击＝预放置"],["长按＝正式放下","gold"]]], board:"l1-3" },
  { tag:"第 4 / 8 步 · 推理", title:"地毯上只有一个人", lines:[[["卡 3 是清洁工的口供：「只有值班保安站在地毯上」。"]],[["地毯一共 4 格，所以保安只可能在这 4 格之一 ——"]],[["别人踩上地毯就破了这句话。"]]], clue:{letter:"C",color:0xFF6E9B62,name:"卡 3 · 夜班清洁工（C）",say:[["「只有 值班保安 站在 "],["地毯",C.gold],[" 上」"]]}, board:"l1-4" },
  { tag:"第 5 / 8 步 · 推理", title:"B 只能站 (2,2)，A 只能站 (3,1)", lines:[[["卡 5：「前台姑娘在桌子旁边」→ (2,2) 和 (3,1)。但 (3,1) 是地毯，"]],[["站上去就和卡 3「只有值班保安在地毯上」冲突，所以 "],["B = (2,2)",C.gold],["。"]],[["第 2 行、第 2 列被占 ⇒ A 的 (2,4)(2,5)(3,2) 出局 ⇒ "],["A = (3,1)",C.gold]]], chips:["已确定",[["B → (2,2)"],["A → (3,1)"],["线索来源：卡 3","blue"]]], clue:{letter:"V",color:0xFF4C8FA6,name:"卡 5 · 收藏家（受害者）",say:[["「前台姑娘 "],["在 桌子 旁边",C.gold],["」"]]}, board:"l1-5" },
  { tag:"第 6 / 8 步 · 推理", title:"清洁工只能站 (5,4)", lines:[[["卡 4 是古董商的口供：「夜班清洁工站在椅子上」。"]],[["椅子只有 (4,2) 和 (5,4)；(4,2) 和前台姑娘同列，"]],[["站不了 ⇒ "],["清洁工 = (5,4)",C.gold],["。"]]], chips:["已确定",[["C → (5,4)"],["(4,2) 同列，出局","blue"]]], clue:{letter:"D",color:0xFF8A6FB0,name:"卡 4 · 旧识古董商（D）",say:[["「夜班清洁工 站在 "],["椅子",C.gold],[" 上」"]]}, board:"l1-6" },
  { tag:"第 7 / 8 步 · 收口", title:"只剩两种摆法，用房间规则淘汰一种", lines:[[["卡 1「收藏家在第 5 列」+ 卡 2「古董商在植物旁边」。"]],[["前三个人已经钉死，只剩 D 与 V 互换的两种摆法。"]],[["把 D 换到外间 (4,3) 时，受害者相邻两屋里"],["「无辜人数最多的那间」",C.gold]],[["不是 D 所在的屋 ⇒ 这种摆法不成立。"]]], chips:["已确定",[["两种摆法"],["只留 D(1,3)、V(4,5)","gold"]]], clue:{letter:"A",color:0xFFC96A5C,name:"卡 1 · 值班保安（A）",say:[["「收藏家 在 "],["第 5 列",C.gold],["」"]]}, board:"l1-7" },
  { tag:"第 8 / 8 步 · 指认", title:"谁一直留着两格，谁就是盗窃者", lines:[[["摆位定死后回头看：A、B、C 全程各只有 1 个可能格，"]],[["只有 D 一直留着 2 格 —— "],["有选择余地的那个，就是盗窃者",C.gold],["。"]],[["受害者独处内室，屋里没有第二个人 ⇒ 无同伙。"]]], chips:["结论",[["盗窃者 = D","gold"],["同伙 = 无","blue"]]], note:"提交后：先校验摆位，再指认盗窃者、回答有没有同伙。", board:"l1-8" },
];
const L2 = [
  { tag:"第 1 / 4 步 · 复述", title:"还是那四步", lines:[[["① 每行每列恰好一人 ② 只能站椅子、地毯"]],[["③ 用线索把每个人的可能格收窄"]],[["④ 看门：只有门直接连通的两间才算相邻",C.gold],["。"]],[["这一关的侧廊只有一扇门，所以它只和大厅相邻。"]]], chips:["本关场地",[["6×6 · 6 人"],["四间屋"],["门才是通道","blue"]]], note:"门只决定「哪两间算相邻」，不改变房间本身的划分。", board:"l2-1" },
  { tag:"第 2 / 4 步 · 谎言", title:"最多一句假话，而且不一定告诉你", lines:[[["假话是"],["整条假",C.gold],["，不是半真半假；最多一条；受害者的话也可能落在这一条上。"]],[["另有一种「通用线索」不算谁的卡，比如本关的「地毯上没有人」"]],[["—— 它同样可能为假，但这一句是真的，先把 5 个地毯格划掉。"]]], chips:["规则",[["至多 1 句假话","gold"],["不会预告哪一句","blue"],["通用线索不算谁的卡"]]], clue:{letter:"?",color:0xFF827C6D,name:"通用线索 · 不占卡位",say:[["「地毯上没有人」"]]}, board:"l2-2" },
  { tag:"第 3 / 4 步 · 谎言", title:"「同一列的上方」这种话，永远不成立", lines:[[["先假设所有线索都为真。如果一种摆法都摆不出来，就说明必有一句假话。"]],[["再逐条假设它是假、摘掉它，看剩下能不能自洽 —— 能自洽的那一条就是假话。"]],[["像「某人在某人的同一列上方」这种形状的话，"],["天生就假",C.gold],["：每列只能站一个人。"]]], note:"图里的红虚线是讲解用的，游戏里不会画。", clue:{letter:"?",color:0xFF827C6D,name:"恒假句式",say:[["「A 在 B 的"],["同一列上方",C.gold],["」→ 一列一人，两侧不可能同时站人"]]}, board:"l2-3" },
  { tag:"第 4 / 4 步 · 收口", title:"说假话的人，就是盗窃者", lines:[[["摆满、提交；判题只校验硬冲突（同行同列、踩到家具），"]],[["不会告诉你是哪一句假、也不会说有几条不成立",C.blue],["。"]],[["找到那句假话之后，说这句话的人就是你要指认的人。"]]], chips:["本关要点",[["摆满 → 提交"],["判题不揭晓假话"],["指认盗窃者","gold"]]], clue:{letter:"V",color:0xFF4C8FA6,name:"受害者的话也可能为假",say:[["「我独自一人，且 "],["临时搬运工",C.gold],[" 在我下方的不同区域中」"]]}, board:"l2-4" },
];

for (const tag of ["home", "l1", "l2"]) {
  const root = "td." + tag;
  cloneOne("container", "root", root, 1600, 900, 800, 450);
  rect(root, root + ".bg", 800, 450, 1480, U(1008), C.panel, 107102);
  const pages = tag === "home" ? [null] : tag === "l1" ? L1 : L2;
  const sharedId = tag === "home" ? "home-1" : tag === "l1" ? "l1-1" : "l2-1";
  const sharedY = tag === "home" ? Y(240) + U(620) / 2 : Y(302) + U(620) / 2;
  cloneOne("container", root, root + ".board", 1600, 900, 800, 450);
  board(root + ".board", sharedId, X(1256) + U(620) / 2, sharedY, U(656), root + ".board");
  pages.forEach((o, k) => {
    const cur = k + 1, page = root + ".page." + cur;
    cloneOne("container", root, page, 1600, 900, 800, 450);
    const common = { eyebrow:tag === "home" ? "教程 · 玩法总览" : tag === "l1" ? "教程 · 第一关 · 案件 001《夜盗独行》" : "教程 · 第二关 · 案件 002《双影》", title:tag === "home" ? "先摆人，再指认" : tag === "l1" ? "操作与推理" : "复述与谎言", sub:tag === "home" ? "数独 × 推理：每行每列各站一人，靠线索收窄，最后揪出盗窃者" : null, cur:tag === "home" ? null : cur, total:pages.length };
    header(page, common);
    stepper(page, tag === "home" ? null : tag === "l1" ? ["认识棋盘","选人","放人","推理一","推理二","推理三","收口","指认"] : ["复习","假话","抓谎","收口"], cur);
    const boardId = tag === "home" ? "home-1" : o.board;
    const boardY = tag === "home" ? Y(240) + U(620) / 2 : Y(302) + U(620) / 2;
    board(page, boardId, X(1256) + U(620) / 2, boardY, U(656), null, "overlay");
    legend(page, tag === "l2" ? [["大厅",0xFFD9CDB4],["侧廊",0xFFC3CDD4],["库房",0xFFD4C8BC],["内室",0xFFBECFB0]] : [["大屋",0xFFD9CDB4],["内室",0xFFC3CDD4],["外间",0xFFD4C8BC]]);
    footer(page, { tag, cur, total:pages.length });
    const left = X(96) + U(1100) / 2, colW = U(1100);
    if (tag === "home") {
      const cardW = U(1078) / 2, cardH = U(224), gap = U(22), top = Y(240);
      HOME_CARDS.forEach((o2, i) => {
        const wide = i === 4, w = wide ? colW : cardW, cx = wide ? left : left - colW / 2 + cardW / 2 + (i % 2) * (cardW + gap);
        const cy = top + cardH / 2 + Math.floor(i / 2) * (cardH + gap), name = page + ".rule." + (i + 1);
        card(page, name, cx, cy, w, cardH);
        const left2 = cx - w / 2 + U(28), top2 = cy - cardH / 2;
        circleLabel(page, name + ".num", String(i + 1), left2 + U(23), top2 + U(40), U(46), 0xFF3A2B19, C.gold, 16);
        label(page, name + ".title", o2.title, left2 + U(65) + (w - U(100)) / 2, top2 + U(34), w - U(100), U(42), 18, C.text);
        o2.lines.forEach((segments, j) => rich(page, name + ".body." + j, segments, left2 + U(65), top2 + U(78) + j * U(34), 13, Math.max(24, U(32))));
      });
    } else {
      const top = Y(302), gap = U(22), heights = o.chips && o.clue ? [U(278),U(108),U(234)] : o.chips && o.note ? [U(330),U(130),U(116)] : o.note && o.clue ? [U(320),U(130),U(170)] : [U(408),U(212)];
      let y = top;
      stepCard(page, o, left, y + heights[0] / 2, colW, heights[0]); y += heights[0] + gap;
      if (o.chips) { chipsCard(page, o.chips[0], o.chips[1], left, y + heights[1] / 2, colW, heights[1]); y += heights[1] + gap; }
      if (o.note) noteCard(page, o.note, left, y + heights[o.chips ? 2 : 1] / 2, colW, heights[o.chips ? 2 : 1]);
      if (o.clue) clueCard(page, o.clue, left, y + heights[o.chips ? 2 : 1] / 2, colW, heights[o.chips ? 2 : 1]);
    }
  });
  // 共用按钮始终位于页面文字之上；文字本身随页面切换。
  cloneOne("button", root, root + ".btn.close", U(64), U(64), X(2200), Y(116));
  rect(root, root + ".closex", X(2200), Y(116), U(24), U(24), C.text2, 100151);
  cloneOne("button", root, root + ".btn.prev", U(180), U(66), X(1950), Y(1005));
  art(byName.get(root + ".btn.prev"), 107102, 0xFF1B2230);
  cloneOne("button", root, root + ".btn.next", U(190), U(66), X(2150), Y(1005));
  art(byName.get(root + ".btn.next"), 107102, C.accent);
  cloneOne("button", root, root + ".btn.skip", U(220), U(66), X(96) + U(110), Y(1005));
  art(byName.get(root + ".btn.skip"), 107102, 0x00111111);
}
fs.writeFileSync(OUT, g.pack(encodeMsg(g.tree)));
const check = readGil(OUT);
const names = new Set(check.recs.map((r) => r.name).filter(Boolean));
for (const name of added) if (!names.has(name)) throw new Error("missing after write " + name);
console.log("added", added.length, "controls; records", check.recs.length, "maxId", maxId.toString());
console.log("wrote", path.basename(OUT), fs.statSync(OUT).size);
