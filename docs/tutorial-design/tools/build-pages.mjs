import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve("_work/tutorial-design");
const PAGES = path.join(ROOT, "pages");
fs.mkdirSync(PAGES, { recursive: true });

const board = (id) =>
  fs.readFileSync(path.join(ROOT, "boards", `${id}.svg`), "utf8")
    .replace("<svg ", '<svg class="board-svg" ')
    .replace(/width="[^"]*" height="[^"]*"/, "");

const face = (letter, color) => `<span class="face" style="--fc:${color}">${letter}</span>`;

const CSS = `
:root{
  --ink:#0B0E16; --panel:#171C2B; --panel2:#1D2335; --panel3:#242B40;
  --line:rgba(255,255,255,.075); --line2:rgba(255,255,255,.14);
  --text:#F3EDE0; --text2:#B9B3A4; --muted:#827C6D;
  --accent:#E8A23C; --accent2:#FFCB7A; --gold:#F0B54A;
  --blue:#9ED8FF; --green:#8FC08A; --red:#D0553F;
  --fA:#C96A5C; --fB:#5E8CC0; --fC:#6E9B62; --fD:#8A6FB0; --fE:#C08B4A; --fV:#4C8FA6;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1600px;height:900px;overflow:hidden}
body{font-family:"Noto Sans SC","Source Han Sans SC","Microsoft YaHei",sans-serif;color:var(--text);background:#080A10;-webkit-font-smoothing:antialiased}
.screen{position:relative;width:1600px;height:900px;overflow:hidden}
/* ---------- 千星奇域风底：暖光 + 星环 ---------- */
.game-bg{position:absolute;inset:0;
  background:
    radial-gradient(880px 620px at 10% 6%, rgba(255,241,196,.92), rgba(255,241,196,0) 70%),
    radial-gradient(760px 560px at 92% 14%, rgba(203,193,255,.72), rgba(203,193,255,0) 72%),
    radial-gradient(920px 720px at 66% 102%, rgba(168,206,255,.62), rgba(168,206,255,0) 72%),
    linear-gradient(152deg,#FFF9EC 0%,#F2F5FF 46%,#DFE7FA 100%);}
.orb{position:absolute;border-radius:50%;filter:blur(2px);opacity:.5}
.orb.a{width:520px;height:520px;left:-140px;top:-160px;background:radial-gradient(circle at 40% 40%,#FFF3C4,#FFE9A8 45%,rgba(255,233,168,0) 70%)}
.orb.b{width:620px;height:620px;right:-180px;top:-200px;background:radial-gradient(circle at 50% 50%,rgba(160,150,235,.55),rgba(160,150,235,0) 70%)}
.orb.c{width:700px;height:520px;left:38%;bottom:-300px;background:radial-gradient(circle at 50% 50%,rgba(120,170,240,.45),rgba(120,170,240,0) 70%)}
.deco{position:absolute;inset:0;opacity:.55}
/* ---------- 顶部条 ---------- */
.topbar{position:absolute;left:0;top:0;right:0;height:88px;display:flex;align-items:center;gap:18px;padding:0 34px;
  background:linear-gradient(180deg,rgba(255,252,244,.86),rgba(255,252,244,0));}
.back{width:44px;height:44px;border-radius:50%;background:rgba(255,255,255,.72);border:1px solid rgba(60,50,40,.16);
  display:flex;align-items:center;justify-content:center;color:#4A4034;font-size:26px;line-height:1;padding-bottom:4px}
.case{font-size:22px;font-weight:700;color:#2E2A24;letter-spacing:.5px}
.timer{font-size:19px;font-weight:700;color:#6B6154;font-variant-numeric:tabular-nums}
.top-right{margin-left:auto;display:flex;gap:12px}
.chipbtn{height:40px;padding:0 18px;border-radius:20px;background:rgba(23,28,43,.82);border:1px solid rgba(255,255,255,.16);
  color:#F3EDE0;font-size:14px;font-weight:700;display:flex;align-items:center;gap:8px}
/* ---------- 棋盘 ---------- */
.board-wrap{position:absolute;left:572px;top:104px;width:656px;filter:drop-shadow(0 26px 48px rgba(30,40,70,.28))}
.board-svg{width:100%;height:auto;display:block;border-radius:14px}
/* ---------- 右侧工具 ---------- */
.toolbar{position:absolute;right:56px;top:196px;display:flex;flex-direction:column;gap:20px}
.tool{width:62px;height:62px;border-radius:50%;background:rgba(255,255,255,.82);border:1px solid rgba(60,50,40,.14);
  display:flex;align-items:center;justify-content:center;box-shadow:0 8px 18px rgba(40,50,80,.12)}
.tool svg{width:26px;height:26px;stroke:#4A4034;fill:none;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}
.tool.primary{background:linear-gradient(180deg,#F6C26A,#E39A2F);border-color:#C9832A}
.tool.primary svg{stroke:#3A2708}
.hintbar{position:absolute;left:700px;bottom:34px;height:40px;padding:0 20px;border-radius:20px;
  background:rgba(23,28,43,.82);color:#E9E2D3;font-size:14px;display:flex;align-items:center;gap:14px;
  box-shadow:0 10px 24px rgba(10,14,26,.3)}
.hintbar b{color:var(--accent2);font-weight:700}
/* ---------- 教程抽屉 ---------- */
.drawer{position:absolute;left:20px;top:34px;width:538px;height:832px;border-radius:22px;overflow:hidden;
  background:linear-gradient(180deg,#1B2132 0%,#141926 62%,#11151F 100%);
  border:1px solid var(--line);box-shadow:0 34px 80px rgba(8,10,18,.55), inset 0 1px 0 rgba(255,255,255,.06);
  display:flex;flex-direction:column}
.drawer::before{content:"";position:absolute;left:0;right:0;top:0;height:4px;
  background:linear-gradient(90deg,var(--accent),#C97F22 60%,rgba(200,127,34,0))}
.d-head{padding:22px 24px 12px;display:flex;align-items:flex-start;gap:14px}
.eyebrow{font-size:11.5px;letter-spacing:1.5px;color:var(--accent);font-weight:700;margin-bottom:7px}
.d-title{font-size:26px;font-weight:800;letter-spacing:.4px}
.d-sub{font-size:12px;color:var(--muted);margin-top:6px;letter-spacing:.3px}
.close{margin-left:auto;width:32px;height:32px;border-radius:50%;border:1px solid var(--line2);color:var(--text2);
  display:flex;align-items:center;justify-content:center;font-size:15px;background:rgba(255,255,255,.03)}
.rail{padding:2px 14px 6px;display:flex;flex-direction:column;gap:1px}
.rail .r{display:flex;align-items:center;gap:11px;height:34px;padding:0 10px;border-radius:8px;color:var(--text2);font-size:12.8px}
.rail .r .n{width:22px;height:22px;border-radius:50%;border:1px solid var(--line2);display:flex;align-items:center;justify-content:center;
  font-size:11.5px;font-weight:700;color:var(--muted);flex:0 0 auto}
.rail .r .done{background:rgba(143,192,138,.18);border-color:rgba(143,192,138,.5);color:#A9D6A2}
.rail .r.on{background:linear-gradient(90deg,rgba(232,162,60,.2),rgba(232,162,60,.04));color:var(--text);
  box-shadow:inset 2px 0 0 var(--accent)}
.rail .r.on .n{background:var(--accent);border-color:var(--accent);color:#22180A}
.d-body{padding:4px 24px 0;flex:1;display:flex;flex-direction:column;gap:10px;min-height:0}
.step-tag{display:inline-flex;align-items:center;gap:8px;align-self:flex-start;height:24px;padding:0 11px;border-radius:12px;
  background:rgba(232,162,60,.14);border:1px solid rgba(232,162,60,.35);color:var(--accent2);font-size:11.5px;font-weight:700}
.step-title{font-size:21px;font-weight:800;line-height:1.35;letter-spacing:.2px}
.step-text{font-size:14.4px;line-height:1.8;color:#D8D2C4}
.step-text b{color:var(--accent2);font-weight:700}
.step-text em{font-style:normal;color:var(--blue);font-weight:700}
.clue{margin-top:auto;border-radius:13px;background:linear-gradient(180deg,#232A3E,#1B2131);border:1px solid var(--line2);
  padding:11px 13px;display:flex;gap:11px;align-items:flex-start}
.clue .face{width:34px;height:34px;font-size:15px}
.clue .meta{font-size:11.5px;color:var(--muted);letter-spacing:.4px}
.clue .who{font-size:13px;font-weight:700;color:var(--text);margin:2px 0 4px}
.clue .say{font-size:13.5px;line-height:1.65;color:#E4DDCE}
.clue .say b{color:var(--accent2)}
.face{width:34px;height:34px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex:0 0 auto;
  font-weight:800;font-size:14px;color:#FFF8EC;background:var(--fc);
  box-shadow:inset 0 0 0 2px rgba(255,255,255,.28), 0 2px 6px rgba(0,0,0,.25)}
.solved{display:flex;gap:8px;flex-wrap:wrap}
.flow{display:flex;align-items:center;gap:7px;font-size:11.5px;color:var(--text2);flex-wrap:wrap}
.flow span{padding:5px 10px;border-radius:9px;border:1px solid var(--line2);background:rgba(255,255,255,.03);font-weight:700}
.flow i{color:var(--muted);font-style:normal}
.flow span.hot{border-color:rgba(232,162,60,.45);background:rgba(232,162,60,.12);color:var(--accent2)}
.pill{height:26px;padding:0 11px;border-radius:13px;font-size:12px;font-weight:700;display:flex;align-items:center;gap:7px;
  background:rgba(143,192,138,.12);border:1px solid rgba(143,192,138,.4);color:#B6DDB0}
.pill.blue{background:rgba(158,216,255,.1);border-color:rgba(158,216,255,.35);color:#BEE3F8}
.pill.gold{background:rgba(240,181,74,.12);border-color:rgba(240,181,74,.4);color:#FFD79A}
.d-foot{height:70px;padding:0 24px;display:flex;align-items:center;gap:10px;border-top:1px solid var(--line);
  background:linear-gradient(180deg,rgba(255,255,255,.015),rgba(255,255,255,0))}
.skip{margin-right:auto;font-size:12.5px;color:var(--muted);font-weight:700}
.btn{height:38px;padding:0 18px;border-radius:19px;font-size:13.5px;font-weight:800;display:flex;align-items:center;gap:8px}
.btn.ghost{background:rgba(255,255,255,.04);border:1px solid var(--line2);color:var(--text2)}
.btn.primary{background:linear-gradient(180deg,#F3B963,#E39A2F);color:#2A1B06;box-shadow:0 6px 16px rgba(227,154,47,.28)}
.btn .k{font-size:11px;opacity:.6;font-weight:700}
.page-dots{display:flex;gap:6px;align-items:center;margin-left:10px}
.page-dots i{width:6px;height:6px;border-radius:50%;background:rgba(255,255,255,.18)}
.page-dots i.on{width:18px;border-radius:3px;background:var(--accent)}
/* ---------- 首页：选关底 + 居中面板 ---------- */
.scrim{position:absolute;inset:0;background:radial-gradient(900px 600px at 50% 42%,rgba(8,11,18,.42),rgba(8,11,18,.72))}
.selmock{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center}
.selmock .t{font-size:34px;font-weight:800;color:#3A332A;margin-top:46px;letter-spacing:2px}
.selmock .s{font-size:14px;color:#8A8172;margin-top:8px;letter-spacing:1px}
.cards{display:flex;gap:34px;margin-top:44px}
.lcard{width:300px;height:400px;border-radius:18px;background:linear-gradient(180deg,#FFFDF6,#F1EADB);
  border:1px solid rgba(70,60,45,.14);box-shadow:0 26px 60px rgba(40,50,80,.22);padding:16px;display:flex;flex-direction:column;gap:10px}
.lcard .thumb{height:250px;border-radius:12px;overflow:hidden;background:#141018}
.lcard .thumb svg{width:100%;height:auto;display:block}
.lcard .nm{font-size:18px;font-weight:800;color:#332C23}
.lcard .mt{font-size:12.5px;color:#8A8172}
.lcard .go{margin-top:auto;height:40px;border-radius:20px;background:linear-gradient(180deg,#F3B963,#E39A2F);color:#2A1B06;
  font-size:14px;font-weight:800;display:flex;align-items:center;justify-content:center}
.pager{display:flex;gap:10px;margin-top:26px}
.pager i{width:9px;height:9px;border-radius:50%;background:rgba(70,60,45,.22)}
.pager i.on{width:24px;border-radius:5px;background:#C9832A}
/* ---------- 首页教程面板 ---------- */
.panel{position:absolute;left:170px;top:50px;width:1260px;height:800px;border-radius:24px;overflow:hidden;
  background:linear-gradient(180deg,#1B2133 0%,#141926 58%,#10141E 100%);
  border:1px solid var(--line);box-shadow:0 40px 100px rgba(6,8,14,.6), inset 0 1px 0 rgba(255,255,255,.06);
  display:flex;flex-direction:column}
.panel::before{content:"";position:absolute;left:0;right:0;top:0;height:4px;
  background:linear-gradient(90deg,var(--accent),#C97F22 55%,rgba(200,127,34,0))}
.p-head{padding:30px 40px 18px;display:flex;align-items:flex-start}
.p-head .eyebrow{margin-bottom:9px}
.p-title{font-size:34px;font-weight:800;letter-spacing:.6px}
.p-sub{font-size:14px;color:var(--text2);margin-top:9px;letter-spacing:.3px}
.p-body{flex:1;display:flex;gap:38px;padding:6px 40px 0;min-height:0}
.rules{width:556px;display:flex;flex-direction:column;gap:12px}
.rule{display:flex;gap:13px;padding:12px 15px;border-radius:14px;background:rgba(255,255,255,.028);border:1px solid var(--line)}
.rule .num{width:28px;height:28px;border-radius:50%;flex:0 0 auto;display:flex;align-items:center;justify-content:center;
  background:rgba(232,162,60,.16);border:1px solid rgba(232,162,60,.45);color:var(--accent2);font-size:14px;font-weight:800}
.rule h4{font-size:16.5px;font-weight:800;margin-bottom:5px;letter-spacing:.2px}
.rule p{font-size:13.5px;line-height:1.7;color:#CFC9BA}
.rule p b{color:var(--accent2)}
.rule p em{font-style:normal;color:var(--blue);font-weight:700}
.rightcol{flex:1;display:flex;flex-direction:column;gap:10px;min-width:0;align-items:center}
.board-card{width:490px;border-radius:16px;overflow:hidden;border:1px solid var(--line2);background:#141018;box-shadow:0 18px 40px rgba(0,0,0,.35)}
.board-card svg{width:100%;height:auto;display:block}
.bcap{display:flex;align-items:center;gap:10px;font-size:12.5px;color:var(--muted)}
.bcap .dotk{width:8px;height:8px;border-radius:50%;background:var(--accent)}
.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--text2);justify-content:center}
.legend span{display:flex;align-items:center;gap:7px}
.legend i{width:14px;height:14px;border-radius:4px;display:block}
.room-legend{position:absolute;left:572px;top:786px;width:656px;display:flex;align-items:center;justify-content:center;gap:18px;
  font-size:12.5px;color:rgba(46,40,32,.78);font-weight:700}
.room-legend span{display:flex;align-items:center;gap:7px}
.room-legend i{width:13px;height:13px;border-radius:4px;display:block;box-shadow:0 0 0 1px rgba(0,0,0,.12)}
.blegend{display:flex;flex-direction:column;gap:5px;align-items:center}
.blegend.float{position:absolute;left:572px;top:764px;width:656px}
.blegend.on-light .lrow{color:rgba(46,40,32,.8)}
.blegend .lrow{display:flex;flex-wrap:wrap;gap:11px;justify-content:center;font-size:11px;color:var(--text2);font-weight:600}
.blegend span{display:flex;align-items:center;gap:5px;white-space:nowrap}
.blegend i{width:11px;height:11px;border-radius:3px;display:block;box-shadow:0 0 0 1px rgba(0,0,0,.1)}
.blegend b{font-weight:800;font-size:10px;width:16px;height:16px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex:0 0 auto}
.blegend .gpawn{background:#F2EDE3;color:#2A241C}
.blegend .gghost{background:transparent;color:#9A9080;border:1.5px dashed #8A8272;font-size:8.5px}
.blegend .gx{background:transparent;color:#D0553F;font-size:12px}
.blegend .gnote{background:transparent;color:#A9A392;font-size:10px}
.blegend .gv{background:#BFE6F2;color:#2C5A6B}
.blegend .gchair{background:#8FC08A;color:#1C2A18}
.blegend .gblock{background:#6B5B49;color:#F2EDE3}
.blegend.on-light .gpawn{background:#3A3226;color:#F2EDE3}
.p-foot{height:74px;padding:0 40px;display:flex;align-items:center;gap:14px;border-top:1px solid var(--line);
  background:linear-gradient(180deg,rgba(255,255,255,.014),rgba(255,255,255,0))}
.p-foot .tip{font-size:13px;color:var(--text2);margin-right:auto}
.p-foot .tip b{color:var(--accent2)}
`;

const stars = (() => {
  let s = 7, out = "";
  const rnd = () => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648;
  for (let i = 0; i < 90; i++) {
    const x = rnd() * 1600, y = rnd() * 900, r = rnd() * 1.8 + 0.5, o = rnd() * 0.5 + 0.2;
    out += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${r.toFixed(1)}" fill="#8FA6D8" opacity="${o.toFixed(2)}"/>`;
  }
  return `<svg class="deco" viewBox="0 0 1600 900" xmlns="http://www.w3.org/2000/svg">${out}
    <circle cx="1290" cy="230" r="250" fill="none" stroke="#B9C6EE" stroke-width="1.2" opacity=".5"/>
    <circle cx="1290" cy="230" r="320" fill="none" stroke="#C9D3F2" stroke-width="1" opacity=".35"/>
    <circle cx="1290" cy="230" r="390" fill="none" stroke="#D5DDF5" stroke-width="1" opacity=".22"/>
    <path d="M 140 760 q 180 -60 360 -20 q 200 44 380 -18 q 170 -56 360 6" fill="none" stroke="#CBD8F2" stroke-width="2" opacity=".5"/>
  </svg>`;
})();

const toolIcon = (d) => `<svg viewBox="0 0 24 24">${d}</svg>`;

const HOME = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>首页教程</title><style>${CSS}</style></head>
<body><div class="screen">
  <div class="game-bg"><div class="orb a"></div><div class="orb b"></div><div class="orb c"></div>${stars}</div>
  <div class="selmock">
    <div class="t">选择关卡</div>
    <div class="s">三起案件 · 一局 5–6 人 · 每局 10 分钟</div>
    <div class="cards">
      <div class="lcard"><div class="thumb">${board("l1-1").replace('class="board-svg"', 'class="board-svg" style="width:268px;margin:-140px 0 0 -150px"')}</div><div class="nm">案件 001 · 夜盗独行</div><div class="mt">5×5 · 5 人 · 入门</div><div class="go">继续办案</div></div>
      <div class="lcard"><div class="thumb">${board("l2-1").replace('class="board-svg"', 'class="board-svg" style="width:268px;margin:-140px 0 0 -150px"')}</div><div class="nm">案件 002 · 双影</div><div class="mt">6×6 · 6 人 · 有一句假话</div><div class="go">开始</div></div>
      <div class="lcard" style="opacity:.55"><div class="thumb" style="display:flex;align-items:center;justify-content:center;color:#7C7768;font-size:13px">第 3 关<br>待解锁</div><div class="nm">案件 003</div><div class="mt">7×7 · 7 人</div><div class="go" style="background:#DDD5C4;color:#8A8172">未解锁</div></div>
    </div>
    <div class="pager"><i class="on"></i><i></i></div>
  </div>
  <div class="scrim"></div>
  <div class="panel">
    <div class="p-head">
      <div>
        <div class="eyebrow">教程 · 玩法总览</div>
        <div class="p-title">先摆人，再指认</div>
        <div class="p-sub">数独 × 推理：每行每列各站一人，靠线索收窄，最后揪出盗窃者</div>
      </div>
      <div class="close" style="margin-left:auto">✕</div>
    </div>
    <div class="p-body">
      <div class="rules">
        <div class="rule"><div class="num">1</div><div><h4>目标：摆满当事人，再指认</h4>
          <p>每名当事人（含 1 名受害者）各占一格。全部摆好后，指出谁是<b>盗窃者</b>；如果受害者屋里还有别人，还要说清有没有同伙。</p></div></div>
        <div class="rule"><div class="num">2</div><div><h4>每行、每列恰好一人</h4>
          <p>放下一个人，整行整列会自动打叉。一行不能站两个，一列也不能。</p></div></div>
        <div class="rule"><div class="num">3</div><div><h4>只能站「可站」的格子</h4>
          <p><em>椅子、地毯</em>可以站；<b>桌子、植物、书架、雕像</b>不能站。</p></div></div>
        <div class="rule"><div class="num">4</div><div><h4>「旁边 / 隔壁」怎么算</h4>
          <p>只算上下左右贴着的格子：<b>同屋直接算，跨屋必须中间有门</b>，隔着墙不算。盗窃者也一定落在受害者隔壁的屋里。</p></div></div>
        <div class="rule"><div class="num">5</div><div><h4>操作：点卡 → 笔记 → 长按放下</h4>
          <p>点一张线索卡选中人；轻点格子只写铅笔笔记；按住不放，进度环走完才真正放下。放错了用右边的撤销。</p></div></div>
      </div>
      <div class="rightcol">
        <div class="board-card">${board("home-1")}</div>
        <div class="bcap"><i class="dotk"></i>5×5 棋盘 · 三间屋 · 三扇门 · 坐标 =（行,列）</div>
        <div class="blegend">
          <div class="lrow"><span><i style="background:#D9CDB4"></i>大屋</span><span><i style="background:#C3CDD4"></i>内室</span><span><i style="background:#D4C8BC"></i>外间</span><span><i style="background:#29282B"></i>墙</span><span><i style="background:#DC5B28"></i>门</span></div>
          <div class="lrow"><span><b class="gpawn">A</b>棋子</span><span><b class="gghost">A?</b>候选</span><span><b class="gx">✕</b>排除</span><span><b class="gnote">b</b>笔记</span><span><b class="gv">V</b>受害者</span><span><b class="gchair">椅</b>可站</span><span><b class="gblock">桌</b>不可站</span></div>
        </div>
      </div>
    </div>
    <div class="p-foot">
      <div class="tip">第一关教程会带你走一遍完整推理，<b>随时可以跳过</b></div>
      <div class="page-dots"><i class="on"></i></div>
      <div class="btn ghost">稍后再看</div>
      <div class="btn primary">开始办案</div>
    </div>
  </div>
</div></body></html>`;

const L1 = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>第一关教程</title><style>${CSS}</style></head>
<body><div class="screen">
  <div class="game-bg"><div class="orb a"></div><div class="orb b"></div><div class="orb c"></div>${stars}</div>
  <div class="topbar">
    <div class="back">‹</div>
    <div class="case">案件 001 · 夜盗独行</div>
    <div class="timer">01:14</div>
    <div class="top-right"><div class="chipbtn">退出</div></div>
  </div>
  <div class="board-wrap">${board("l1-5")}</div>
  <div class="toolbar">
    <div class="tool">${toolIcon('<path d="M9 14 4 9l5-5"/><path d="M4 9h9a6 6 0 0 1 0 12h-3"/>')}</div>
    <div class="tool">${toolIcon('<path d="m15 14 5-5-5-5"/><path d="M20 9h-9a6 6 0 0 0 0 12h3"/>')}</div>
    <div class="tool">${toolIcon('<path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v4h-4"/>')}</div>
    <div class="tool">${toolIcon('<path d="m5 13 4 4L19 7"/>')}</div>
  </div>
  <div class="blegend float on-light">
    <div class="lrow"><span><i style="background:#D9CDB4"></i>大屋</span><span><i style="background:#C3CDD4"></i>内室</span><span><i style="background:#D4C8BC"></i>外间</span><span><i style="background:#29282B"></i>墙</span><span><i style="background:#DC5B28"></i>门</span></div>
    <div class="lrow"><span><b class="gpawn">A</b>棋子</span><span><b class="gghost">A?</b>候选</span><span><b class="gx">✕</b>排除</span><span><b class="gnote">b</b>笔记</span><span><b class="gv">V</b>受害者</span><span><b class="gchair">椅</b>可站</span><span><b class="gblock">桌</b>不可站</span></div>
  </div>
  <div class="drawer">
    <div class="d-head">
      <div>
        <div class="eyebrow">教程 · 第一关 · 案件 001《夜盗独行》</div>
        <div class="d-title">操作与推理</div>
        <div class="d-sub">8 步走完一遍，就能自己破案</div>
      </div>
      <div class="close">✕</div>
    </div>
    <div class="rail">
      <div class="r done"><span class="n">✓</span>认识棋盘：三间屋、三扇门</div>
      <div class="r done"><span class="n">✓</span>选人：点一张线索卡</div>
      <div class="r done"><span class="n">✓</span>放人：轻点写笔记，长按放下</div>
      <div class="r done"><span class="n">✓</span>推理 1：地毯上只有一个人</div>
      <div class="r on"><span class="n">5</span>推理 2：桌子旁只剩一格</div>
      <div class="r"><span class="n">6</span>推理 3：剩下的椅子</div>
      <div class="r"><span class="n">7</span>收口：两种摆法只差一步</div>
      <div class="r"><span class="n">8</span>指认：谁一直留着两格</div>
    </div>
    <div class="d-body">
      <div class="step-tag">第 5 / 8 步 · 推理</div>
      <div class="step-title">B 只能站 (2,2)，A 只能站 (3,1)</div>
      <div class="step-text">卡 5 是收藏家的口供：「前台姑娘 <b>在桌子旁边</b>」。桌子旁只有 (2,2) 和 (3,1) —— 但 (3,1) 是地毯，站上去就和卡 3「只有值班保安在地毯上」冲突，所以前台姑娘 <em>= (2,2)</em>。<br>第 2 行被占，保安的 (2,4)(2,5) 出局；第 2 列被占，(3,2) 也出局 ⇒ <em>保安 = (3,1)</em>。</div>
      <div class="solved"><span class="pill">B → (2,2)</span><span class="pill">A → (3,1)</span><span class="pill blue">线索来源：卡 3</span></div>
      <div class="clue">
        ${face("V", "var(--fV)")}
        <div><div class="meta">卡 5 · 收藏家（受害者）</div><div class="say">「前台姑娘 <b>在 桌子 旁边</b>」</div></div>
      </div>
    </div>
    <div class="d-foot">
      <div class="skip">跳过教程</div>
      <div class="btn ghost">上一步</div>
      <div class="btn primary">下一步 <span class="k">5 / 8</span></div>
    </div>
  </div>
</div></body></html>`;

const L2 = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>第二关教程</title><style>${CSS}</style></head>
<body><div class="screen">
  <div class="game-bg"><div class="orb a"></div><div class="orb b"></div><div class="orb c"></div>${stars}</div>
  <div class="topbar">
    <div class="back">‹</div>
    <div class="case">案件 002 · 双影</div>
    <div class="timer">02:03</div>
    <div class="top-right"><div class="chipbtn">退出</div></div>
  </div>
  <div class="board-wrap">${board("l2-3")}</div>
  <div class="toolbar">
    <div class="tool">${toolIcon('<path d="M9 14 4 9l5-5"/><path d="M4 9h9a6 6 0 0 1 0 12h-3"/>')}</div>
    <div class="tool">${toolIcon('<path d="m15 14 5-5-5-5"/><path d="M20 9h-9a6 6 0 0 0 0 12h3"/>')}</div>
    <div class="tool">${toolIcon('<path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v4h-4"/>')}</div>
    <div class="tool">${toolIcon('<path d="m5 13 4 4L19 7"/>')}</div>
  </div>
  <div class="blegend float on-light">
    <div class="lrow"><span><i style="background:#D9CDB4"></i>大厅</span><span><i style="background:#C3CDD4"></i>侧廊</span><span><i style="background:#D4C8BC"></i>库房</span><span><i style="background:#BECFB0"></i>内室</span><span><i style="background:#29282B"></i>墙</span><span><i style="background:#DC5B28"></i>门</span></div>
    <div class="lrow"><span><b class="gpawn">A</b>棋子</span><span><b class="gghost">A?</b>候选</span><span><b class="gx">✕</b>排除</span><span><b class="gnote">b</b>笔记</span><span><b class="gv">V</b>受害者</span><span><b class="gchair">椅</b>可站</span><span><b class="gblock">桌</b>不可站</span></div>
  </div>
  <div class="drawer">
    <div class="d-head">
      <div>
        <div class="eyebrow">教程 · 第二关 · 案件 002《双影》</div>
        <div class="d-title">复述与谎言</div>
        <div class="d-sub">多一条规则：线索里可能有一句假话</div>
      </div>
      <div class="close">✕</div>
    </div>
    <div class="rail">
      <div class="r done"><span class="n">✓</span>复述：四步推理法</div>
      <div class="r done"><span class="n">✓</span>新规则：至多一句假话</div>
      <div class="r on"><span class="n">3</span>抓谎：先当全真，再逐条摘</div>
      <div class="r"><span class="n">4</span>收口：说假话的人就是盗窃者</div>
    </div>
    <div class="d-body">
      <div class="step-tag">第 3 / 4 步 · 谎言</div>
      <div class="step-title">「同一列的上方」这种话，永远不成立</div>
      <div class="step-text">先假设所有线索都为真。如果一种摆法都摆不出来，就说明<b>必有一句假话</b>。<br>再逐条假设它是假、摘掉它，看剩下能不能自洽 —— 能自洽的那一条就是假话。<br>像「某人在某人的<em>同一列上方</em>」这种形状的话，天生就假：每列只能站一个人，不可能有两个。<br><span style="color:var(--muted);font-size:12px">图里的红虚线是讲解用的，游戏里不会画。</span></div>
      <div class="solved"><span class="pill gold">至多 1 句假话</span><span class="pill blue">不会预告哪一句</span><span class="pill">通用线索不算谁的卡</span></div>
      <div class="flow"><span>假设全真</span><i>→</i><span>摆不出</span><i>→</i><span>逐条摘</span><i>→</i><span class="hot">找自洽的那条</span></div>
      <div class="clue">
        ${face("?", "var(--muted)")}
        <div><div class="meta">恒假句式</div><div class="say">「A 在 B 的<b>同一列上方</b>」→ 一列一人，两侧不可能同时站人</div></div>
      </div>
    </div>
    <div class="d-foot">
      <div class="skip">跳过教程</div>
      <div class="btn ghost">上一步</div>
      <div class="btn primary">下一步 <span class="k">3 / 4</span></div>
    </div>
  </div>
</div></body></html>`;

fs.writeFileSync(path.join(PAGES, "01-home.html"), HOME, "utf8");
fs.writeFileSync(path.join(PAGES, "02-level1.html"), L1, "utf8");
fs.writeFileSync(path.join(PAGES, "03-level2.html"), L2, "utf8");
console.log("pages written", ["01-home.html", "02-level1.html", "03-level2.html"]);
