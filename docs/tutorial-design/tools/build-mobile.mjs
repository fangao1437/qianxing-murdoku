// 移动端 19.5:9（2340×1080）教程逐页设计图
// 输入：_work/tutorial-design/boards/*.svg（千星美术管线产物）
// 输出：_work/tutorial-design/mobile/*.html + *.png
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve("_work/tutorial-design");
const OUT = path.join(ROOT, "mobile");
fs.mkdirSync(OUT, { recursive: true });
const board = (id) => fs.readFileSync(path.join(ROOT, "boards", `${id}.svg`), "utf8");

const CSS = `
:root{
  --ink:#0A0D15; --bg1:#111622; --bg2:#0B0F18;
  --card:rgba(255,255,255,.032); --card2:rgba(255,255,255,.012);
  --line:rgba(255,255,255,.085); --line2:rgba(255,255,255,.16);
  --text:#F3EDE0; --text2:#BDB6A7; --muted:#827C6D;
  --accent:#E8A23C; --accent2:#FFCB7A; --blue:#9ED8FF; --green:#8FC08A; --red:#D0553F;
  --fA:#C96A5C; --fB:#5E8CC0; --fC:#6E9B62; --fD:#8A6FB0; --fE:#C08B4A; --fV:#4C8FA6;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:2340px;height:1080px;overflow:hidden}
body{font-family:"Noto Sans SC","Source Han Sans SC","Microsoft YaHei",sans-serif;color:var(--text);
  background:radial-gradient(1000px 700px at 10% 0%,rgba(255,240,200,.55),rgba(255,240,200,0) 62%),
             radial-gradient(900px 700px at 95% 10%,rgba(200,190,255,.45),rgba(200,190,255,0) 64%),
             radial-gradient(1000px 800px at 70% 105%,rgba(160,200,250,.45),rgba(160,200,250,0) 64%),
             linear-gradient(152deg,#FFF7E8,#EFF3FF 48%,#DCE5F8);}
.screen{position:relative;width:2340px;height:1080px;overflow:hidden}
.popup{position:absolute;inset:36px;border-radius:30px;background:linear-gradient(165deg,#151A27,#0E1220 60%,#0B0F18);
  border:1px solid rgba(255,255,255,.09);box-shadow:0 40px 100px rgba(10,14,26,.55)}
.scrim{position:absolute;inset:0;background:rgba(8,11,18,.32)}
.glow{position:absolute;border-radius:50%;filter:blur(1px);opacity:.4}
.glow.a{width:900px;height:900px;right:-260px;top:-380px;background:radial-gradient(circle,rgba(255,220,150,.22),rgba(255,220,150,0) 68%)}
.glow.b{width:1000px;height:800px;left:-320px;bottom:-420px;background:radial-gradient(circle,rgba(130,170,240,.18),rgba(130,170,240,0) 68%)}
/* header */
.head{position:absolute;left:96px;right:96px;top:84px;height:140px;display:flex;align-items:flex-start}
.eyebrow{font-size:20px;font-weight:700;letter-spacing:2.4px;color:var(--accent);margin-bottom:12px}
.h-title{font-size:46px;font-weight:800;letter-spacing:1px;line-height:1.1}
.h-sub{font-size:21px;color:var(--text2);margin-top:14px;letter-spacing:.5px}
.head-right{margin-left:auto;display:flex;align-items:center;gap:22px;padding-top:6px}
.stepnum{font-size:21px;font-weight:800;color:var(--text2);letter-spacing:.5px}
.stepnum b{color:var(--accent2);font-size:26px}
.close{width:64px;height:64px;border-radius:50%;border:1px solid var(--line2);display:flex;align-items:center;justify-content:center;
  font-size:28px;color:var(--text2);background:rgba(255,255,255,.03)}
/* stepper */
.stepper{position:absolute;left:96px;right:96px;top:228px;height:66px;display:flex;gap:12px;justify-content:center}
.step{flex:0 1 300px;height:66px;border-radius:16px;border:1px solid var(--line);background:rgba(255,255,255,.022);
  display:flex;align-items:center;gap:14px;padding:0 20px;color:var(--text2);font-size:19px;font-weight:700;min-width:0}
.step .n{width:38px;height:38px;border-radius:50%;border:1px solid var(--line2);display:flex;align-items:center;justify-content:center;
  font-size:17px;font-weight:800;color:var(--muted);flex:0 0 auto}
.step .t{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.step.on{border-color:rgba(232,162,60,.55);background:linear-gradient(90deg,rgba(232,162,60,.18),rgba(232,162,60,.04));color:var(--text)}
.step.on .n{background:var(--accent);border-color:var(--accent);color:#22180A}
.step.done .n{background:rgba(143,192,138,.16);border-color:rgba(143,192,138,.5);color:#A9D6A2}
/* body */
.body{position:absolute;left:96px;right:96px;top:302px;height:664px;display:flex;gap:60px}
.col-text{width:1100px;display:flex;flex-direction:column;gap:22px;min-width:0}
.col-text .step-card{justify-content:flex-start;flex:1 1 auto}
.board-col{width:620px;display:flex;flex-direction:column;gap:14px}
.legend-col{width:340px;display:flex;flex-direction:column;gap:18px}
/* card face（统一成首页那张图的卡面） */
.card{background:linear-gradient(180deg,var(--card),var(--card2));border:1px solid var(--line);border-radius:20px;padding:24px 28px;display:flex;flex-direction:column;justify-content:center}
.card .row{display:flex;gap:20px;align-items:flex-start}
.num{width:46px;height:46px;border-radius:50%;flex:0 0 auto;display:flex;align-items:center;justify-content:center;
  background:rgba(232,162,60,.16);border:1px solid rgba(232,162,60,.45);color:var(--accent2);font-size:21px;font-weight:800}
.card h3{font-size:29px;font-weight:800;letter-spacing:.3px;margin-bottom:8px;line-height:1.3}
.card p{font-size:22px;line-height:1.78;color:#D3CCBD}
.card p b{color:var(--accent2);font-weight:700}
.card p em{font-style:normal;color:var(--blue);font-weight:700}
.card .kicker{font-size:16px;font-weight:700;letter-spacing:2px;color:var(--muted);margin-bottom:12px}
.step-card .tag{align-self:flex-start;display:inline-flex;align-items:center;height:38px;padding:0 16px;border-radius:19px;font-size:16px;font-weight:800;
  color:var(--accent2);background:rgba(232,162,60,.14);border:1px solid rgba(232,162,60,.35);margin-bottom:14px}
.step-card h2{font-size:39px;font-weight:800;line-height:1.3;letter-spacing:.4px;margin-bottom:12px}
.step-card p{font-size:22.5px}
.clue-row{display:flex;gap:18px;align-items:center}
.face{width:64px;height:64px;border-radius:50%;flex:0 0 auto;display:flex;align-items:center;justify-content:center;
  font-size:26px;font-weight:800;color:#FFF8EC;background:var(--fc,#5E6B8C);box-shadow:inset 0 0 0 3px rgba(255,255,255,.24)}
.clue-name{font-size:20px;color:var(--muted);font-weight:700;letter-spacing:.5px}
.clue-say{font-size:23px;color:#E9E2D3;line-height:1.5;margin-top:4px}
.clue-say b{color:var(--accent2)}
.chips{display:flex;gap:12px;flex-wrap:wrap}
.chip{height:44px;padding:0 18px;border-radius:22px;display:flex;align-items:center;gap:8px;font-size:18px;font-weight:700;
  background:rgba(143,192,138,.10);border:1px solid rgba(143,192,138,.38);color:#B6DDB0}
.chip.blue{background:rgba(158,216,255,.09);border-color:rgba(158,216,255,.32);color:#BEE3F8}
.chip.gold{background:rgba(240,181,74,.11);border-color:rgba(240,181,74,.4);color:#FFD79A}
.note{display:flex;gap:14px;align-items:flex-start;font-size:20px;color:var(--text2);line-height:1.6}
.note .k{width:28px;height:28px;border-radius:50%;flex:0 0 auto;display:flex;align-items:center;justify-content:center;
  background:rgba(158,216,255,.12);border:1px solid rgba(158,216,255,.35);color:var(--blue);font-size:15px;font-weight:800}
/* board */
.board-card{border-radius:20px;overflow:hidden;border:1px solid var(--line2);box-shadow:0 26px 60px rgba(4,6,12,.5)}
.board-card svg{width:100%;height:auto;display:block}
.caption{font-size:17px;color:var(--muted);display:flex;gap:10px;align-items:center}
.caption i{width:8px;height:8px;border-radius:50%;background:var(--accent);display:block}
/* legend */
.legend-col .kicker{font-size:16px;font-weight:700;letter-spacing:2px;color:var(--muted)}
.lg{display:flex;flex-direction:column;gap:11px;font-size:18px;color:var(--text2);font-weight:600}
.lg .row{display:flex;align-items:center;gap:12px}
.lg i{width:22px;height:22px;border-radius:5px;display:block}
.lg b{width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:800;flex:0 0 auto}
.lg .gpawn{background:#F2EDE3;color:#2A241C}
.lg .gghost{background:transparent;color:#9A9080;border:2px dashed #8A8272;font-size:12px}
.lg .gx{color:var(--red);font-size:22px}
.lg .gnote{background:transparent;color:#A9A392;font-size:16px}
.lg .gv{background:#BFE6F2;color:#2C5A6B}
.lg .gchair{background:#8FC08A;color:#1C2A18}
.lg .gblock{background:#6B5B49;color:#F2EDE3}
.coord{font-size:17px;color:var(--muted);border-left:2px solid rgba(232,162,60,.4);padding-left:12px;line-height:1.6}
/* footer */
.foot{position:absolute;left:96px;right:96px;top:972px;height:72px;display:flex;align-items:center;gap:18px}
.skip{font-size:20px;font-weight:700;color:var(--muted);margin-right:auto}
.btn{height:66px;padding:0 36px;border-radius:33px;font-size:22px;font-weight:800;display:flex;align-items:center;gap:12px}
.btn.ghost{background:rgba(255,255,255,.04);border:1px solid var(--line2);color:var(--text2)}
.btn.primary{background:linear-gradient(180deg,#F3B963,#E39A2F);color:#2A1B06;box-shadow:0 10px 26px rgba(227,154,47,.28)}
.btn .k{font-size:17px;font-weight:700;opacity:.55}
/* home grid */
.rules{display:grid;grid-template-columns:1fr 1fr;gap:22px;flex:1 1 auto;grid-template-rows:1fr 1fr 1fr}
.rules .card.wide{grid-column:1 / span 2}
.body.home .col-text{width:1100px}
.body.home .board-col{width:620px}
/* pages */
.pages{position:absolute;left:60px;right:60px;top:36px;height:140px;display:flex;align-items:flex-start}
.pager{display:flex;gap:10px;align-items:center;margin-top:14px}
.pager i{width:12px;height:12px;border-radius:50%;background:rgba(255,255,255,.16)}
.pager i.on{width:42px;border-radius:6px;background:var(--accent)}
`;

const face = (letter, color) => `<span class="face" style="--fc:${color}">${letter}</span>`;

const LEGEND = (rooms) => `
<div class="legend-col">
  <div class="kicker">图例</div>
  <div class="lg">
    ${rooms.map(([name, color]) => `<div class="row"><i style="background:${color}"></i>${name}</div>`).join("")}
    <div class="row"><i style="background:#29282B"></i>墙</div>
    <div class="row"><i style="background:#DC5B28"></i>门</div>
  </div>
  <div class="lg">
    <div class="row"><b class="gpawn">A</b>棋子</div>
    <div class="row"><b class="gghost">A?</b>候选</div>
    <div class="row"><b class="gx">✕</b>排除</div>
    <div class="row"><b class="gnote">b</b>笔记</div>
    <div class="row"><b class="gv">V</b>受害者</div>
    <div class="row"><b class="gchair">椅</b>可站</div>
    <div class="row"><b class="gblock">桌</b>不可站</div>
  </div>
  <div class="coord">坐标 =（行,列）<br>行号自上而下，列号自左而右</div>
</div>`;

const header = (o) => `
<div class="head">
  <div>
    <div class="eyebrow">${o.eyebrow}</div>
    <div class="h-title">${o.title}</div>
    ${o.sub ? `<div class="h-sub">${o.sub}</div>` : ""}
  </div>
  <div class="head-right">
    ${o.stepNo ? `<div class="stepnum">第 <b>${o.stepNo.i}</b> / ${o.stepNo.n} 步</div>` : ""}
    <div class="close">✕</div>
  </div>
</div>`;

const stepper = (items, cur) => `<div class="stepper">${items.map((t, k) => `
  <div class="step ${k + 1 === cur ? "on" : k + 1 < cur ? "done" : ""}">
    <span class="n">${k + 1 < cur ? "✓" : k + 1}</span><span class="t">${t}</span>
  </div>`).join("")}</div>`;

const ruleCard = (n, t, b) => `<div class="card"><div class="row"><div class="num">${n}</div>
  <div><h3>${t}</h3><p>${b}</p></div></div></div>`;

const stepCard = (o) => `<div class="card step-card">
  <div class="tag">${o.tag}</div>
  <h2>${o.title}</h2>
  <p>${o.body}</p>
</div>`;

const clueCard = (o) => `<div class="card">
  <div class="kicker">${o.kicker || "线索来源"}</div>
  <div class="clue-row">${face(o.letter, o.color)}
    <div><div class="clue-name">${o.name}</div><div class="clue-say">${o.say}</div></div>
  </div></div>`;

const chipsCard = (kicker, items) => `<div class="card">
  <div class="kicker">${kicker}</div>
  <div class="chips">${items.map(([t, cls]) => `<span class="chip ${cls || ""}">${t}</span>`).join("")}</div></div>`;

const noteCard = (txt) => `<div class="card"><div class="note"><span class="k">i</span><span>${txt}</span></div></div>`;

const LEGEND_L1 = [["大屋", "#D9CDB4"], ["内室", "#C3CDD4"], ["外间", "#D4C8BC"]];
const LEGEND_L2 = [["大厅", "#D9CDB4"], ["侧廊", "#C3CDD4"], ["库房", "#D4C8BC"], ["内室", "#BECFB0"]];

const page = (o) => `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>${o.name}</title><style>${CSS}</style></head>
<body><div class="screen">
  <div class="scrim"></div><div class="popup"></div>
  <div class="glow a"></div><div class="glow b"></div>
  ${header(o)}
  ${o.stepper ? stepper(o.stepper, o.cur) : ""}
  <div class="body ${o.noStepper ? "home" : ""}" ${o.noStepper ? 'style="top:240px;height:716px"' : ""}>
    <div class="col-text">${o.cards}</div>
    <div class="board-col">
      <div class="board-card">${board(o.board)}</div>
      <div class="caption"><i></i>${o.caption}</div>
    </div>
    ${LEGEND(o.rooms)}
  </div>
  <div class="foot">
    <div class="skip">${o.skip || "跳过教程"}</div>
    ${o.prev ? `<div class="btn ghost">${o.prev}</div>` : ""}
    <div class="btn primary">${o.next}</div>
  </div>
</div></body></html>`;

/* ---------------- 首页（1 页） ---------------- */
const HOME = page({
  name: "首页教程",
  eyebrow: "教程 · 玩法总览",
  title: "先摆人，再指认",
  sub: "数独 × 推理：每行每列各站一人，靠线索收窄，最后揪出盗窃者",
  noStepper: true,
  board: "home-1",
  caption: "5×5 棋盘 · 三间屋 · 三扇门 · 5 枚棋子",
  rooms: LEGEND_L1,
  skip: "稍后再看",
  next: "开始办案",
  cards: `<div class="rules">
    ${ruleCard(1, "目标：摆满当事人，再指认", "每名当事人（含 1 名受害者）各占一格。全部摆好后，指出谁是<b>盗窃者</b>；如果受害者屋里还有别人，还要说清有没有同伙。")}
    ${ruleCard(2, "每行、每列恰好一人", "放下一个人，整行整列会自动打叉。一行不能站两个，一列也不能。")}
    ${ruleCard(3, "只能站「可站」的格子", "<em>椅子、地毯</em>可以站；<b>桌子、植物、书架、雕像</b>不能站。")}
    ${ruleCard(4, "「旁边 / 隔壁」怎么算", "只算上下左右贴着的格子：<b>同屋直接算，跨屋必须中间有门</b>，隔着墙不算。盗窃者也一定落在受害者隔壁的屋里。")}
    ${ruleCard(5, "操作：轻点＝笔记，双击＝预放置，长按＝正式放下", "点一张线索卡选中人。轻点格子＝铅笔笔记；<b>双击＝预放置</b>（先占位，可反悔）；<b>按住不放、进度环走完＝正式放下</b>。放错了用右边的撤销。").replace('<div class="card">', '<div class="card wide">')}
  </div>`,
});

/* ---------------- 第一关（8 页） ---------------- */
const L1_STEPS = ["认识棋盘", "选人", "放人", "推理一", "推理二", "推理三", "收口", "指认"];
const l1 = (i, cards, extra) => page({
  name: `第一关 · 第 ${i} 步`,
  eyebrow: "教程 · 第一关 · 案件 001《夜盗独行》",
  title: "操作与推理",
  stepNo: { i, n: 8 },
  stepper: L1_STEPS,
  cur: i,
  cards,
  board: extra.board,
  caption: extra.caption,
  rooms: LEGEND_L1,
  skip: "跳过教程",
  prev: i > 1 ? "上一步" : "",
  next: i < 8 ? "下一步" : "开始试玩",
});

const L1 = [
  l1(1,
    stepCard({ tag: "第 1 / 8 步 · 认识", title: "三间屋、三扇门", body: "左边是线索卡，中间是棋盘，右边是工具。棋盘 5×5，三间屋：大屋、内室、外间；粗线是墙，橙色是门。行号 1–5 从上往下，列号 1–5 从左往右。" })
    + chipsCard("棋盘速览", [["5×5 · 5 人"], ["三间屋"], ["三扇门", "blue"]])
    + noteCard("受害者也在这 5 个人里，别把他落下。"),
    { board: "l1-1", caption: "空盘：三间屋、三扇门" }),
  l1(2,
    stepCard({ tag: "第 2 / 8 步 · 操作", title: "点一张卡，就选中卡上那个人", body: "卡上写的是他的口供 —— 说的可能是别人。选中后，话里提到的位置会在棋盘上亮起来。再点一次取消选中。" })
    + noteCard("卡上的人＝你要放下的人；卡上的话＝他的口供，可能说的是别人。")
    + clueCard({ letter: "A", color: "var(--fA)", name: "卡 1 · 值班保安（A）", say: "「收藏家 <b>在 第 5 列</b>」" }),
    { board: "l1-2", caption: "选中 A，第 5 列亮起" }),
  l1(3,
    stepCard({ tag: "第 3 / 8 步 · 操作", title: "轻点＝笔记，双击＝预放置，长按＝正式放下", body: "轻点格子只留一个铅笔小字，不占位；<b>双击先把棋子预放在格子上</b>（可以反悔，不算正式落子）；按住不放、等进度环走完，才真正落下大字母。放下后，这一行这一列会自动打叉。" })
    + noteCard("放错了？撤销、重做、重置都在右边。")
    + chipsCard("三种手势", [["轻点＝笔记"], ["双击＝预放置"], ["长按＝正式放下", "gold"]]),
    { board: "l1-3", caption: "长按进度环 + 行/列将被划掉" }),
  l1(4,
    stepCard({ tag: "第 4 / 8 步 · 推理", title: "地毯上只有一个人", body: "卡 3 是清洁工的口供：「只有值班保安站在地毯上」。地毯一共 4 格，所以保安只可能在这 4 格之一 —— 别人踩上地毯就破了这句话。" })
    + clueCard({ letter: "C", color: "var(--fC)", name: "卡 3 · 夜班清洁工（C）", say: "「只有 值班保安 站在 地毯 上」" }),
    { board: "l1-4", caption: "A 的 4 个可能格（A?）" }),
  l1(5,
    stepCard({ tag: "第 5 / 8 步 · 推理", title: "B 只能站 (2,2)，A 只能站 (3,1)", body: "卡 5：「前台姑娘在桌子旁边」→ (2,2) 和 (3,1)。但 (3,1) 是地毯，站上去就和卡 3「只有值班保安在地毯上」冲突，所以 B = (2,2)。第 2 行、第 2 列被占 ⇒ A 的 (2,4)(2,5)(3,2) 出局 ⇒ A = (3,1)。" })
    + chipsCard("已确定", [["B → (2,2)"], ["A → (3,1)"], ["线索来源：卡 3", "blue"]])
    + clueCard({ letter: "V", color: "var(--fV)", name: "卡 5 · 收藏家（受害者）", say: "「前台姑娘 <b>在 桌子 旁边</b>」" }),
    { board: "l1-5", caption: "B/A 已放，3 个候选被划掉" }),
  l1(6,
    stepCard({ tag: "第 6 / 8 步 · 推理", title: "清洁工只能站 (5,4)", body: "卡 4 是古董商的口供：「夜班清洁工站在椅子上」。椅子只有 (4,2) 和 (5,4)；(4,2) 和前台姑娘同列，站不了 ⇒ 清洁工 = (5,4)。" })
    + chipsCard("已确定", [["C → (5,4)"], ["(4,2) 同列，出局", "blue"]])
    + clueCard({ letter: "D", color: "var(--fD)", name: "卡 4 · 旧识古董商（D）", say: "「夜班清洁工 站在 椅子 上」" }),
    { board: "l1-6", caption: "C 已放，(4,2) 被划掉" }),
  l1(7,
    stepCard({ tag: "第 7 / 8 步 · 收口", title: "只剩两种摆法，用房间规则淘汰一种", body: "卡 1「收藏家在第 5 列」+ 卡 2「古董商在植物旁边」。前三个人已经钉死，只剩 D 与 V 互换的两种摆法。把 D 换到外间 (4,3) 时，受害者相邻两屋里「无辜人数最多的那间」不是 D 所在的屋 ⇒ 这种摆法不成立。" })
    + chipsCard("已确定", [["两种摆法"], ["只留 D(1,3)、V(4,5)", "gold"]])
    + clueCard({ letter: "A", color: "var(--fA)", name: "卡 1 · 值班保安（A）", say: "「收藏家 在 第 5 列」" }),
    { board: "l1-7", caption: "D/V 互换的两种摆法，一种被划掉" }),
  l1(8,
    stepCard({ tag: "第 8 / 8 步 · 指认", title: "谁一直留着两格，谁就是盗窃者", body: "摆位定死后回头看：A、B、C 全程各只有 1 个可能格，只有 D 一直留着 2 格 —— 有选择余地的那个，就是盗窃者。受害者独处内室，屋里没有第二个人 ⇒ 无同伙。" })
    + chipsCard("结论", [["盗窃者 = D", "gold"], ["同伙 = 无", "blue"]])
    + noteCard("提交后：先校验摆位，再指认盗窃者、回答有没有同伙。"),
    { board: "l1-8", caption: "终局：金圈 D、蓝标 V" }),
];

/* ---------------- 第二关（4 页） ---------------- */
const L2_STEPS = ["复习", "假话", "抓谎", "收口"];
const l2 = (i, cards, extra) => page({
  name: `第二关 · 第 ${i} 步`,
  eyebrow: "教程 · 第二关 · 案件 002《双影》",
  title: "复述与谎言",
  stepNo: { i, n: 4 },
  stepper: L2_STEPS,
  cur: i,
  cards,
  board: extra.board,
  caption: extra.caption,
  rooms: LEGEND_L2,
  skip: "跳过教程",
  prev: i > 1 ? "上一步" : "",
  next: i < 4 ? "下一步" : "开始试玩",
});

const L2 = [
  l2(1,
    stepCard({ tag: "第 1 / 4 步 · 复述", title: "还是那四步", body: "① 每行每列恰好一人 ② 只能站椅子、地毯 ③ 用线索把每个人的可能格收窄 ④ 看门：只有门直接连通的两间才算相邻。这一关的侧廊只有一扇门，所以它只和大厅相邻。" })
    + chipsCard("本关场地", [["6×6 · 6 人"], ["四间屋"], ["门才是通道", "blue"]])
    + noteCard("门只决定「哪两间算相邻」，不改变房间本身的划分。"),
    { board: "l2-1", caption: "6×6、四间屋；侧廊只有一扇门" }),
  l2(2,
    stepCard({ tag: "第 2 / 4 步 · 谎言", title: "最多一句假话，而且不一定告诉你", body: "假话是整条假，不是半真半假；最多一条；受害者的话也可能落在这一条上。另有一种「通用线索」不算谁的卡，比如本关的「地毯上没有人」—— 它同样可能为假，但这一句是真的，先把 5 个地毯格划掉。" })
    + chipsCard("规则", [["至多 1 句假话", "gold"], ["不会预告哪一句", "blue"], ["通用线索不算谁的卡"]])
    + clueCard({ letter: "?", color: "var(--muted)", name: "通用线索 · 不占卡位", say: "「地毯上没有人」" }),
    { board: "l2-2", caption: "5 个地毯格先划掉" }),
  l2(3,
    stepCard({ tag: "第 3 / 4 步 · 谎言", title: "「同一列的上方」这种话，永远不成立", body: "先假设所有线索都为真。如果一种摆法都摆不出来，就说明必有一句假话。再逐条假设它是假、摘掉它，看剩下能不能自洽 —— 能自洽的那一条就是假话。像「某人在某人的同一列上方」这种形状的话，天生就假：每列只能站一个人，不可能有两个。" })
    + noteCard("图里的红虚线是讲解用的，游戏里不会画。")
    + clueCard({ letter: "?", color: "var(--muted)", name: "恒假句式", say: "「A 在 B 的<b>同一列上方</b>」→ 一列一人，两侧不可能同时站人" }),
    { board: "l2-3", caption: "第 3 列高亮 + 两个候选 + 红叉" }),
  l2(4,
    stepCard({ tag: "第 4 / 4 步 · 收口", title: "说假话的人，就是盗窃者", body: "摆满、提交；判题只校验硬冲突（同行同列、踩到家具），不会告诉你是哪一句假、也不会说有几条不成立。找到那句假话之后，说这句话的人就是你要指认的人。" })
    + chipsCard("本关要点", [["摆满 → 提交"], ["判题不揭晓假话"], ["指认盗窃者", "gold"]])
    + clueCard({ letter: "V", color: "var(--fV)", name: "受害者的话也可能为假", say: "「我独自一人，且 <b>临时搬运工</b> 在我下方的不同区域中」" }),
    { board: "l2-4", caption: "地毯已划掉，门是通道" }),
];

const files = [];
files.push(["01-home", HOME]);
L1.forEach((html, k) => files.push([`0${k + 2}-l1-step${k + 1}`, html]));
L2.forEach((html, k) => files.push([`1${k}-l2-step${k + 1}`, html]));

for (const [name, html] of files) fs.writeFileSync(path.join(OUT, `${name}.html`), html, "utf8");
console.log("pages:", files.length);
