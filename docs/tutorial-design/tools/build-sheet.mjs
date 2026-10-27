import fs from "node:fs";
import path from "node:path";
const ROOT = path.resolve("_work/tutorial-design");
const slides = JSON.parse(fs.readFileSync(path.join(ROOT, "slides.json"), "utf8"));
const svg = (id) => fs.readFileSync(path.join(ROOT, "boards", `${id}.svg`), "utf8").replace("<svg ", '<svg class="bs" ').replace(/width="[^"]*" height="[^"]*"/, "");

const groups = [
  { key: "home", label: "教程 1 · 首页教程：玩法总览", sub: "示意盘：5×5、三间屋、两扇门、5 枚棋子", cols: 3 },
  { key: "l1", label: "教程 2 · 第一关教程：操作与推理（8 步）", sub: "真实案件 001 棋盘：每步只改棋子 / 高亮 / 标记，棋盘与家具不动", cols: 4 },
  { key: "l2", label: "教程 3 · 第二关教程：复述与谎言（4 步）", sub: "真实案件 002 棋盘：6×6、四间屋；每步只改高亮与标记", cols: 4 },
];

const section = (g) => `<section><h2>${g.label}</h2><div class="sub">${g.sub}</div>
  <div class="grid cols-${g.cols}">${slides[g.key].map((s, i) => `
    <figure><div class="frame">${svg(s.id)}</div>
      <figcaption><b>${String(i + 1).padStart(2, "0")}</b><span>${s.title}</span></figcaption>
      <div class="cap">${s.caption}</div></figure>`).join("")}
  </div></section>`;

const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>教程棋盘图 · 全步骤</title>
<style>
 html,body{margin:0;background:#0b0d14;color:#f2ecde;font-family:"Noto Sans SC","Source Han Sans SC","Microsoft YaHei",sans-serif}
 .page{width:1600px;padding:40px 44px 56px}
 h1{font-size:30px;margin:0 0 6px;letter-spacing:.5px}
 .lead{font-size:13.5px;color:#a9a392;line-height:1.7;margin-bottom:26px}
 .lead b{color:#f0b54a}
 section{margin-bottom:34px}
 h2{font-size:19px;margin:0 0 4px;color:#f0b54a;letter-spacing:.5px}
 .sub{font-size:12.5px;color:#8b8474;margin-bottom:14px}
 .grid{display:grid;gap:16px}
 .cols-3{grid-template-columns:repeat(3,1fr)}
 .cols-4{grid-template-columns:repeat(4,1fr)}
 figure{margin:0;background:#141821;border:1px solid #2a3145;border-radius:12px;padding:10px}
 .frame{border-radius:9px;overflow:hidden;background:#141018}
 .bs{width:100%;height:auto;display:block}
 figcaption{display:flex;gap:8px;align-items:baseline;margin-top:9px;font-size:12.5px;line-height:1.4}
 figcaption b{color:#f0b54a;font-size:12px;letter-spacing:1px;flex:0 0 auto}
 figcaption span{font-weight:700;color:#f2ecde}
 .cap{font-size:11px;color:#a9a392;line-height:1.55;margin-top:4px}
 .foot{font-size:11.5px;color:#7c7668;border-top:1px solid #242b3d;padding-top:14px;line-height:1.8}
</style></head><body><div class="page">
<h1>三屏教程 · 逐步棋盘图</h1>
<div class="lead">由千星美术管线生成：<b>art_build_spec</b>（简化家具 10 个模板 / 42 层）→ <b>art_slice</b>（真实关卡布局切件）→ <b>art_preview</b>（地板 + 家具）→ 叠加墙 / 门 / 行列号 / 棋子 / 高亮 / 标记。<br>
棋盘几何与游戏一致：1600×900 画布、棋盘外框 584×584、5×5 格宽 108px、6×6 格宽 89px。图中房间配色取自工程 <code>Controller.ROOM_COLORS</code>。</div>
${groups.map(section).join("")}
<div class="foot">说明：图中家具是「简化家具规格」，只保留 3–6 层（生产模板为 9–12 层、雕像压缩版 381 块），用于教程配图；所有层仍只使用官方基础图元 100001 / 100002 / 107102 / 106056。<br>
图中「A?」「D?」等虚线圆是候选位（假设），不是已放置的棋子；红色 × 表示该候选被排除。</div>
</div></body></html>`;

fs.writeFileSync(path.join(ROOT, "pages", "04-boards.html"), html, "utf8");
console.log("sheet html written");
