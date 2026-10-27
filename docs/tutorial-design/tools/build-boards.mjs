// 教程棋盘配图合成器：art_preview 的基础棋盘 SVG + 墙/门/行列号/棋子/高亮/标注
// 输入：_work/tutorial-design/{base-*.svg, layout-*.json, slice-*.json, slides.json, spec-tutorial-furniture.json}
// 输出：_work/tutorial-design/boards/<id>.svg + boards-manifest.json
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve("_work/tutorial-design");
const OUT = path.join(ROOT, "boards");
fs.mkdirSync(OUT, { recursive: true });

const readJson = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
const spec = readJson(path.join(ROOT, "spec-tutorial-furniture.json"));
const slides = readJson(path.join(ROOT, "slides.json"));

const WALL = "#29282B";
const DOOR = "#DC5B28";
const HOT = "#F2A03D";
const TINT = "#9ED8FF";
const RED = "#D0553F";
const INK = "#1B1410";

const BASES = {
  demo: { layout: "layout-demo.json", slice: "slice-demo.json", svg: "base-demo.svg" },
  level1: { layout: "layout-level1.json", slice: "slice-level1.json", svg: "base-level1.svg" },
  level2: { layout: "layout-level2.json", slice: "slice-level2.json", svg: "base-level2.svg" },
};

const cache = {};
function loadBase(key) {
  if (cache[key]) return cache[key];
  const b = BASES[key];
  const layout = readJson(path.join(ROOT, b.layout));
  const slice = readJson(path.join(ROOT, b.slice));
  const svgText = fs.readFileSync(path.join(ROOT, b.svg), "utf8");
  const open = svgText.indexOf(">") + 1;
  const inner = svgText.slice(open, svgText.lastIndexOf("</svg>")).replace(/<text[\s\S]*?<\/text>/g, "");
  const geo = slice.geometry; // {n,pitch,cell,gx,gy}
  cache[key] = { layout, slice, inner, geo, frame: layout.frame };
  return cache[key];
}

const num = (v) => Math.round(v * 100) / 100;

function buildBoard(slide) {
  const base = loadBase(slide.base);
  const { geo, layout, slice, inner } = base;
  const { gx, gy, cell, pitch, n } = geo;
  const frame = layout.frame;
  const M = 36;
  const view = [frame.x - M, frame.y - M, frame.size + 2 * M, frame.size + 2 * M];

  const cx = (c) => gx + (c - 1) * pitch + cell / 2;
  const cy = (r) => gy + (r - 1) * pitch + cell / 2;
  const cellX = (c) => gx + (c - 1) * pitch;
  const cellY = (r) => gy + (r - 1) * pitch;

  const out = [];
  const clipId = `boardClip-${slide.id}`;
  out.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${view[2]}" height="${view[3]}" viewBox="${view.join(" ")}" font-family="Noto Sans SC, Source Han Sans SC, Microsoft YaHei, sans-serif">`);
  out.push(`<defs>
    <clipPath id="${clipId}"><rect x="${frame.x}" y="${frame.y}" width="${frame.size}" height="${frame.size}" rx="6"/></clipPath>
  </defs>`);
  // 0) 整张板的底：让行列号与边框落在深色底上（否则会被浅色页面背景吞掉）
  out.push(`<rect x="${view[0]}" y="${view[1]}" width="${view[2]}" height="${view[3]}" rx="16" fill="#141018"/>`);
  // 1) 基础棋盘（地板 + 家具），裁到棋盘区
  out.push(`<g clip-path="url(#${clipId})">${inner}</g>`);

  const roomRects = {};
  for (let r = 1; r <= n; r++) {
    for (let c = 1; c <= n; c++) {
      const id = Number(layout.cells[r - 1][c - 1]);
      const rr = roomRects[id] || (roomRects[id] = { r0: 99, r1: 0, c0: 99, c1: 0, count: 0 });
      rr.r0 = Math.min(rr.r0, r); rr.r1 = Math.max(rr.r1, r);
      rr.c0 = Math.min(rr.c0, c); rr.c1 = Math.max(rr.c1, c);
      rr.count++;
    }
  }

  // 2) 底色叠加
  const overlays = [];
  if (slide.tintRoom != null && roomRects[slide.tintRoom]) {
    const rr = roomRects[slide.tintRoom];
    overlays.push(`<rect x="${cellX(rr.c0)}" y="${cellY(rr.r0)}" width="${(rr.c1 - rr.c0 + 1) * pitch - 4}" height="${(rr.r1 - rr.r0 + 1) * pitch - 4}" fill="${TINT}" opacity="0.17" rx="5"/>`);
  }
  if (slide.tintCol) {
    overlays.push(`<rect x="${cellX(slide.tintCol)}" y="${cellY(1)}" width="${cell}" height="${n * pitch - 4}" fill="${TINT}" opacity="0.3"/>`);
  }
  (slide.tintCells || []).forEach(([r, c]) => {
    overlays.push(`<rect x="${cellX(c)}" y="${cellY(r)}" width="${cell}" height="${cell}" fill="${TINT}" opacity="0.32"/>`);
  });
  if (slide.bandRow) {
    overlays.push(`<rect x="${cellX(1)}" y="${cellY(slide.bandRow)}" width="${n * pitch - 4}" height="${cell}" fill="${HOT}" opacity="0.12"/>`);
    overlays.push(`<rect x="${cellX(1) + 1}" y="${cellY(slide.bandRow) + 1}" width="${n * pitch - 6}" height="${cell - 2}" fill="none" stroke="${HOT}" stroke-width="2" stroke-dasharray="7 6" opacity="0.75" rx="3"/>`);
  }
  if (slide.bandCol) {
    overlays.push(`<rect x="${cellX(slide.bandCol)}" y="${cellY(1)}" width="${cell}" height="${n * pitch - 4}" fill="${HOT}" opacity="0.12"/>`);
    overlays.push(`<rect x="${cellX(slide.bandCol) + 1}" y="${cellY(1) + 1}" width="${cell - 2}" height="${n * pitch - 6}" fill="none" stroke="${HOT}" stroke-width="2" stroke-dasharray="7 6" opacity="0.75" rx="3"/>`);
  }

  // 3) 墙 + 门
  const doors = new Set((layout.doors || []).map((d) => `${d.dir},${d.r},${d.c}`));
  const doorW = cell * 0.46;
  const walls = [];
  const vSeg = (r, c) => {
    const x = gx + c * pitch - 2;
    const y1 = gy + (r - 1) * pitch;
    const y2 = y1 + cell;
    if (doors.has(`v,${r},${c}`)) {
      const a = y1 + (cell - doorW) / 2;
      walls.push(`<line x1="${x}" y1="${y1}" x2="${x}" y2="${a}" stroke="${WALL}" stroke-width="9" stroke-linecap="butt"/>`);
      walls.push(`<line x1="${x}" y1="${y2 - (cell - doorW) / 2}" x2="${x}" y2="${y2}" stroke="${WALL}" stroke-width="9" stroke-linecap="butt"/>`);
      walls.push(`<rect x="${x - 6}" y="${a}" width="12" height="${doorW}" rx="3" fill="${slide.doorsHot ? HOT : DOOR}" opacity="${slide.doorsHot ? 1 : 0.95}"/>`);
      if (slide.doorsHot) walls.push(`<rect x="${x - 13}" y="${a - 4}" width="26" height="${doorW + 8}" rx="8" fill="${HOT}" opacity="0.22"/>`);
    } else {
      walls.push(`<line x1="${x}" y1="${y1}" x2="${x}" y2="${y2}" stroke="${WALL}" stroke-width="9" stroke-linecap="butt"/>`);
    }
  };
  const hSeg = (r, c) => {
    const y = gy + r * pitch - 2;
    const x1 = gx + (c - 1) * pitch;
    const x2 = x1 + cell;
    if (doors.has(`h,${r},${c}`)) {
      const a = x1 + (cell - doorW) / 2;
      walls.push(`<line x1="${x1}" y1="${y}" x2="${a}" y2="${y}" stroke="${WALL}" stroke-width="9" stroke-linecap="butt"/>`);
      walls.push(`<line x1="${x2 - (cell - doorW) / 2}" y1="${y}" x2="${x2}" y2="${y}" stroke="${WALL}" stroke-width="9" stroke-linecap="butt"/>`);
      walls.push(`<rect x="${a}" y="${y - 6}" width="${doorW}" height="12" rx="3" fill="${slide.doorsHot ? HOT : DOOR}" opacity="${slide.doorsHot ? 1 : 0.95}"/>`);
      if (slide.doorsHot) walls.push(`<rect x="${a - 4}" y="${y - 13}" width="${doorW + 8}" height="26" rx="8" fill="${HOT}" opacity="0.22"/>`);
    } else {
      walls.push(`<line x1="${x1}" y1="${y}" x2="${x2}" y2="${y}" stroke="${WALL}" stroke-width="9" stroke-linecap="butt"/>`);
    }
  };
  (layout.walls || []).forEach((w) => (w.dir === "v" ? vSeg(w.r, w.c) : hSeg(w.r, w.c)));
  // 门必须画在墙上：若某扇门所在边没登记为墙，也补一段（本仓库数据里门边都是墙）
  (layout.doors || []).forEach((d) => {
    const known = (layout.walls || []).some((w) => w.dir === d.dir && w.r === d.r && w.c === d.c);
    if (!known) (d.dir === "v" ? vSeg(d.r, d.c) : hSeg(d.r, d.c));
  });
  // 外框
  walls.push(`<rect x="${gx - 4.5}" y="${gy - 4.5}" width="${(n - 1) * pitch + cell + 9}" height="${(n - 1) * pitch + cell + 9}" fill="none" stroke="${WALL}" stroke-width="9" rx="2"/>`);

  // 4) 行列号（房间名不画在棋盘上：真实工程里房间名贴在外框底边，教程配图空间不够，改由界面图例说明）
  const labels = [];
  for (let c = 1; c <= n; c++) {
    labels.push(`<text x="${cx(c)}" y="${gy - 14}" font-size="21" font-weight="700" fill="#CBBFA6" text-anchor="middle">${c}</text>`);
  }
  for (let r = 1; r <= n; r++) {
    labels.push(`<text x="${gx - 20}" y="${cy(r) + 7}" font-size="21" font-weight="700" fill="#CBBFA6" text-anchor="middle">${r}</text>`);
  }

  // 5) 状态标记
  const marks = [];
  const xMark = (r, c, color = "#4A3A2C", op = 0.82) => {
    const d = cell * 0.2;
    marks.push(`<path d="M ${cx(c) - d} ${cy(r) - d} L ${cx(c) + d} ${cy(r) + d} M ${cx(c) + d} ${cy(r) - d} L ${cx(c) - d} ${cy(r) + d}" stroke="${color}" stroke-width="6.5" stroke-linecap="round" opacity="${op}"/>`);
  };
  (slide.blockedX || []).forEach(([r, c]) => xMark(r, c));
  (slide.strikeCells || []).forEach(([r, c]) => xMark(r, c, RED, 1));
  (slide.ghostX || []).forEach(([r, c]) => xMark(r, c, "#8B7A64", 0.24));
  (slide.checks || []).forEach(([r, c]) => {
    const x = cellX(c) + cell - 15, y = cellY(r) + 15;
    marks.push(`<circle cx="${x}" cy="${y}" r="12" fill="#6E9B62"/><path d="M ${x - 5} ${y} l 3.5 4 l 7 -8" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>`);
  });
  if (slide.conflict) {
    const [a, b] = slide.conflict;
    marks.push(`<line x1="${cx(a[1])}" y1="${cy(a[0])}" x2="${cx(b[1])}" y2="${cy(b[0])}" stroke="${RED}" stroke-width="5" stroke-dasharray="9 7" opacity="0.9"/>`);
    const mx = (cx(a[1]) + cx(b[1])) / 2, my = (cy(a[0]) + cy(b[0])) / 2;
    marks.push(`<circle cx="${mx}" cy="${my}" r="16" fill="${RED}"/><text x="${mx}" y="${my + 6}" font-size="18" font-weight="800" fill="#FFFFFF" text-anchor="middle">×</text>`);
  }
  if (slide.sameRoom) {
    const [r, c] = slide.sameRoom;
    marks.push(`<rect x="${cellX(c) - 12}" y="${cellY(r) - 12}" width="${cell + 24}" height="${2 * pitch + cell + 12}" fill="none" stroke="#7FA8C9" stroke-width="3" stroke-dasharray="8 7" rx="10" opacity="0.85"/>`);
  }
  if (slide.strikeLine) {
    const [a, b] = slide.strikeLine;
    marks.push(`<line x1="${cx(a[1])}" y1="${cy(a[0])}" x2="${cx(b[1])}" y2="${cy(b[0])}" stroke="${RED}" stroke-width="4" stroke-dasharray="9 8" opacity="0.75"/>`);
    const mx = cx(a[1]), my = (cy(a[0]) + cy(b[0])) / 2;
    marks.push(`<circle cx="${mx}" cy="${my}" r="15" fill="${RED}"/><text x="${mx}" y="${my + 6}" font-size="17" font-weight="800" fill="#FFFFFF" text-anchor="middle">×</text>`);
  }

  // 6) 棋子 / 幽灵 / 笔记
  const pieces = [];
  (slide.ghosts || []).forEach((g) => {
    const isQ = g.t === "?";
    const label = isQ ? "?" : `${g.t}?`;
    const r = cell * 0.375;
    pieces.push(`<circle cx="${cx(g.c)}" cy="${cy(g.r)}" r="${r}" fill="${isQ ? "#FFF7E6" : "#F2EDE3"}" opacity="0.58" stroke="${isQ ? HOT : "#6D6659"}" stroke-width="2.5" stroke-dasharray="7 6"/>`);
    pieces.push(`<text x="${cx(g.c)}" y="${cy(g.r) + cell * 0.16}" font-size="${cell * (isQ ? 0.4 : 0.38)}" font-weight="800" fill="${isQ ? "#B4761F" : "#5B5245"}" text-anchor="middle" opacity="0.9">${label}</text>`);
    if (g.strike) xMark(g.r, g.c, RED, 1);
  });
  (slide.pawns || []).forEach((p) => {
    const tone = p.tone || "plain";
    const fill = tone === "victim" ? "#BFE6F2" : tone === "thief" ? "#F7DFAE" : "#EFE6D2";
    const stroke = tone === "victim" ? "#2C5A6B" : tone === "thief" ? "#8A5A16" : "#241D15";
    const r = cell * 0.17;
    pieces.push(`<circle cx="${cx(p.c)}" cy="${cy(p.r)}" r="${r}" fill="${fill}" stroke="${stroke}" stroke-width="3"/>`);
    pieces.push(`<circle cx="${cx(p.c)}" cy="${cy(p.r) - r * 0.18}" r="${r * 0.34}" fill="${stroke}" opacity="0.75"/>`);
    pieces.push(`<rect x="${cx(p.c) - r * 0.5}" y="${cy(p.r) + r * 0.3}" width="${r}" height="${r * 0.55}" rx="${r * 0.22}" fill="${stroke}" opacity="0.6"/>`);
    if (tone === "victim") pieces.push(`<text x="${cx(p.c)}" y="${cy(p.r) + cell * 0.42}" font-size="15" font-weight="700" fill="#2C5A6B" text-anchor="middle">受害者</text>`);
    if (tone === "thief") pieces.push(`<text x="${cx(p.c)}" y="${cy(p.r) + cell * 0.42}" font-size="15" font-weight="700" fill="#8A5A16" text-anchor="middle">盗窃者？</text>`);
  });
  (slide.letters || []).forEach((l) => {
    const tone = l.tone || "plain";
    const isV = tone === "victim", isT = tone === "thief";
    if (isT) pieces.push(`<rect x="${cellX(l.c) + 3}" y="${cellY(l.r) + 3}" width="${cell - 6}" height="${cell - 6}" fill="none" stroke="#F0B54A" stroke-width="4.5" rx="9"/>`);
    if (isV) pieces.push(`<circle cx="${cx(l.c)}" cy="${cy(l.r)}" r="${cell * 0.4}" fill="#2C4F5E" stroke="#8FD0E8" stroke-width="2.5"/>`);
    pieces.push(`<text x="${cx(l.c)}" y="${cy(l.r) + cell * 0.17}" font-size="${cell * 0.5}" font-weight="800" fill="${isV ? "#DFF3FA" : isT ? "#FFD98A" : "#FFFFFF"}" stroke="${INK}" stroke-width="7" paint-order="stroke" text-anchor="middle">${l.t}</text>`);
    if (isV) pieces.push(`<text x="${cx(l.c)}" y="${cy(l.r) + cell * 0.42}" font-size="14.5" font-weight="700" fill="#8FD0E8" stroke="${INK}" stroke-width="4" paint-order="stroke" text-anchor="middle">受害者</text>`);
    if (isT) pieces.push(`<text x="${cx(l.c)}" y="${cy(l.r) + cell * 0.42}" font-size="14.5" font-weight="700" fill="#FFD98A" stroke="${INK}" stroke-width="4" paint-order="stroke" text-anchor="middle">盗窃者</text>`);
  });
  (slide.notes || []).forEach((nt) => {
    pieces.push(`<text x="${cx(nt.c)}" y="${cy(nt.r) + cell * 0.3}" font-size="${cell * 0.28}" font-weight="700" fill="#3B3025" opacity="0.9" text-anchor="middle">${nt.t}</text>`);
  });
  if (slide.hold) {
    const rr = cell * 0.43;
    const circ = 2 * Math.PI * rr;
    pieces.push(`<circle cx="${cx(slide.hold.c)}" cy="${cy(slide.hold.r)}" r="${rr}" fill="none" stroke="#1B1410" stroke-width="10" opacity="0.18"/>`);
    pieces.push(`<circle cx="${cx(slide.hold.c)}" cy="${cy(slide.hold.r)}" r="${rr}" fill="none" stroke="${HOT}" stroke-width="7" stroke-linecap="round" stroke-dasharray="${num(circ * (slide.hold.progress ?? 0.7))} ${num(circ)}" transform="rotate(-90 ${cx(slide.hold.c)} ${cy(slide.hold.r)})"/>`);
  }
  (slide.ringCells || []).forEach(([r, c]) => {
    pieces.push(`<rect x="${cellX(c) + 4}" y="${cellY(r) + 4}" width="${cell - 8}" height="${cell - 8}" fill="none" stroke="${HOT}" stroke-width="4" rx="10"/>`);
  });

  // 7) 编号徽标 / 标签
  const badges = [];
  (slide.callouts || []).forEach((b) => {
    const x = cellX(b.c) + cell - 6, y = cellY(b.r) + 8;
    badges.push(`<circle cx="${x}" cy="${y}" r="15" fill="${HOT}" stroke="${INK}" stroke-width="3"/>`);
    badges.push(`<text x="${x}" y="${y + 6}" font-size="17" font-weight="800" fill="${INK}" text-anchor="middle">${b.n}</text>`);
  });
  if (slide.tag) {
    const t = slide.tag;
    const len = t.text.length;
    const w = 15 + len * 13;
    const x = cx(t.c) + (t.place === "left" ? -cell * 0.75 - w : cell * 0.5);
    const y = cy(t.r) - 14;
    badges.push(`<rect x="${x}" y="${y}" width="${w}" height="30" rx="8" fill="#FFF8E9" stroke="${HOT}" stroke-width="2"/>`);
    badges.push(`<text x="${x + w / 2}" y="${y + 21}" font-size="15" font-weight="700" fill="#4A3316" text-anchor="middle">${t.text}</text>`);
  }

  out.push(overlays.join(""), walls.join(""), labels.join(""), marks.join(""), pieces.join(""), badges.join(""));
  out.push(`<rect x="${frame.x + 1}" y="${frame.y + 1}" width="${frame.size - 2}" height="${frame.size - 2}" fill="none" stroke="#000000" stroke-opacity="0.55" stroke-width="2" rx="6"/>`);
  out.push("</svg>");

  // 统计
  const layerByKey = {};
  Object.entries(spec.templates).forEach(([k, t]) => (layerByKey[k] = t.layerCount));
  let furnLayers = 0;
  const pieceList = [];
  (slice.pieces || []).forEach((p) => {
    furnLayers += layerByKey[p.templateKey] || 0;
    pieceList.push({ name: `${p.name}@${p.anchor.r},${p.anchor.c}`, template: p.templateKey, layers: layerByKey[p.templateKey] || 0 });
  });
  const overlayCount =
    overlays.length + walls.length + labels.length + marks.length + pieces.length + badges.length;
  return {
    svg: out.join("\n"),
    report: {
      id: slide.id,
      base: slide.base,
      rows: n,
      cols: n,
      furniturePieces: (slice.pieces || []).length,
      furnitureLayers: furnLayers,
      wallSegments: (layout.walls || []).length,
      doorSegments: (layout.doors || []).length,
      overlayPrimitives: overlayCount,
      totalPrimitives: furnLayers + overlayCount,
      pieces: pieceList,
    },
  };
}

const manifest = [];
for (const group of ["home", "l1", "l2"]) {
  for (const slide of slides[group]) {
    const { svg, report } = buildBoard(slide);
    fs.writeFileSync(path.join(OUT, `${slide.id}.svg`), svg, "utf8");
    report.group = group;
    report.title = slide.title;
    manifest.push(report);
  }
}
fs.writeFileSync(path.join(ROOT, "boards-manifest.json"), JSON.stringify({ boards: manifest }, null, 2), "utf8");
console.log(JSON.stringify(manifest.map((m) => ({ id: m.id, pieces: m.furniturePieces, furnLayers: m.furnitureLayers, overlay: m.overlayPrimitives, total: m.totalPrimitives })), null, 2));
