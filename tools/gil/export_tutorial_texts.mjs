// 从最终 .gil 回读并导出教程文本填写清单，避免生成器与编辑器填写内容不一致。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readGil } from "./gilread.mjs";
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const IN = path.resolve(process.argv[2]);
const OUT = path.resolve(process.argv[3] || path.join(ROOT, "docs/tutorial-design/教程文本填写清单-v353"));
const g = readGil(IN);
function nodesAt(fields, pathArr) {
  let level = fields;
  for (let i = 0; i < pathArr.length; i++) {
    const hits = level.filter((f) => f.field === pathArr[i] && f.sub);
    if (i === pathArr.length - 1) return hits;
    level = hits.flatMap((f) => f.sub);
  }
  return [];
}
const rows = [];
for (const rec of g.recs) {
  if (!rec.name || !rec.name.startsWith("td.")) continue;
  for (const node of nodesAt(rec.field.sub, [505, 503, 75])) {
    const textNode = node.sub.find((f) => f.field === 510 && f.sub);
    const textLeaf = textNode && textNode.sub.find((f) => f.field === 501 && f.wt === 2);
    const text = textLeaf && textLeaf.payload ? textLeaf.payload.toString("utf8") : "";
    if (!text) continue;
    const num = (field) => {
      const leaf = node.sub.find((f) => f.field === field && f.wt === 0);
      return leaf ? Number(leaf.num) : 0;
    };
    const match = rec.name.match(/^td\.(home|l1|l2)\.page\.(\d+)/);
    if (!match) continue;
    const tag = match[1], page = Number(match[2]);
    rows.push({ tag, page, name:rec.name, text, size:num(512), color:"0x" + (num(504) >>> 0).toString(16).toUpperCase().padStart(8,"0") });
  }
}
const tagOrder = { home:0, l1:1, l2:2 };
rows.sort((a,b) => tagOrder[a.tag]-tagOrder[b.tag] || a.page-b.page || a.name.localeCompare(b.name, "zh-CN", { numeric:true }));
const csvCell = (v) => '"' + String(v).replaceAll('"', '""') + '"';
const csv = ["﻿页面,控件名,要填写的文本,字号,字色"];
for (const r of rows) csv.push([`${r.tag} 第${r.page}页`,r.name,r.text,r.size,r.color].map(csvCell).join(","));
fs.mkdirSync(OUT, { recursive:true });
fs.writeFileSync(path.join(OUT, "教程文本填写清单-v353.csv"), csv.join("\n") + "\n", "utf8");
const titles = { home:"首页教程", l1:"第一关教程", l2:"第二关教程" };
const md = ["# 教程文本填写清单（v353）", "", `共 ${rows.length} 个含文本控件。以下内容直接从最终存档回读；多色正文已拆成多个控件，请逐行填写，不要合并。`, ""];
for (const tag of ["home","l1","l2"]) {
  const pages = [...new Set(rows.filter((r) => r.tag === tag).map((r) => r.page))];
  for (const page of pages) {
    md.push(`## ${titles[tag]} · 第 ${page} 页`, "", "| 控件名 | 要填写的文本 | 字号 | 字色 |", "|---|---|---:|---|");
    for (const r of rows.filter((x) => x.tag === tag && x.page === page)) {
      const text = r.text.replaceAll("|", "\\|").replaceAll("\n", "<br>");
      md.push(`| \`${r.name}\` | ${text} | ${r.size} | \`${r.color}\` |`);
    }
    md.push("");
  }
}
fs.writeFileSync(path.join(OUT, "教程文本填写清单-v353.md"), md.join("\n"), "utf8");
console.log("exported", rows.length, "text controls to", OUT);
