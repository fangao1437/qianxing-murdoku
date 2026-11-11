// 667 · 线索卡改白 + 恢复 5xx 旧描边/高亮方案（基于 666_线索换位.gil）
//
// 依据（用户口径 + 5xx 旧档实测）：
//   515 / 523 / 544 / 650 / 656 档的两套 clue 模板都是：
//     backrop1  330×85.4  #FF56565E  ← 染色层，画在卡下面、比卡面大 6px（露 3px 一圈）
//     backrop2  324×79.4  #FF26262E  ← 卡面
//   666 把这两层改成 #00FFFFFF 全透明，红底改由 art658/art661.clueN.* 绘制，
//   于是脚本 _grid_paint_highlight() 给 backrop1 写 HIGHLIGHT_TINT(0xFFFFD44B 不透明黄)
//   时整张卡透黄、描边失效；同时透明层让红底上沿露出白框，形成用户看到的
//   「选项卡红色区域上方一小段白色」。
//
// 本轮做法（不动层序、不动 childList、不动内嵌 Lua、不动任何文本）：
//   ① 隐藏红底：静态 art657.game.notebook.page + 两套模板的
//      art658.clueN.bg / art661.clueN.*（base + 4 组阶梯共 28 层）/ art658.clueN.rule 白线
//      ⇒ 卡片区露出白色底板 art657.game.notebook.frame(#FDFAEF)
//   ② 恢复旧方案：backrop1 → #FF56565E（染色层，在下、大一圈）；
//      backrop2 → #FFFDFAEF（白色卡面，与底板一致）
//      ⇒ 普通态白卡 + 3px 描边；选中态脚本把 backrop1 染黄，只有那一圈变黄，
//        符合《线索卡-设计规格》「选中态只改描边，外框尺寸不变」。
//
// 输入：666_线索换位/666_线索换位.gil（不覆盖）
// 输出：667_线索卡背景.gil + 667_构建审计.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/667_线索卡背景');
const INPUT = path.join(ROOT, 'qianxing-murdoku/666_线索换位/666_线索换位.gil');
const OUTPUT = path.join(DIR, '667_线索卡背景.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const DRY = process.argv.includes('--dry');

const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const origIds = new Set(g.recs.map(r => r.id));
const origParent = new Map(g.recs.map(r => [r.id, r.parentId]));
const danglingBefore = new Set([...origIds].filter(id =>
  origParent.get(id) != null && !origIds.has(origParent.get(id))));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt(hex.replace('#', ''), 16) >>> 0;   // 输入已是 AARRGGBB
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function retint(r, aarrggbb) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(aarrggbb));
  setNum(p, 504, 1);
  touched.add(r.id);
  if (r.name && !modified.includes(r.name)) modified.push(r.name);
}
// 卡片改白后 who/what/letter 原本是 #FFFFFFFF 纯白字会完全不可见，
// Lua 的 _fill_grid_item 不给它们设 fontColor（color_of_style 只作用于教程等 style 文本），
// 所以直接改存档文本控件的 504 字色即可，不动 Lua。
function retintText(r, aarrggbb) {
  const tp = ns(r.field, [505, 503, 75])[0];
  if (!tp) throw Error('找不到文本块 ' + r.name);
  setNum(tp, 504, colorOf(aarrggbb));
  touched.add(r.id);
  if (r.name && !modified.includes(r.name)) modified.push(r.name);
}
const hidden = [], modified = [], touched = new Set();
function hide(r) {
  if (isHiddenRecord(r.field)) return;
  setHiddenRecord(r.field, true);
  hidden.push(r.name); touched.add(r.id);
  if (r.name && !modified.includes(r.name)) modified.push(r.name);
}

// ── ① 静态红底：让用户说的「直接删了这个红底」生效（隐藏，保留历史记录） ──
const staticRed = g.recs.filter(r => /^art657\.game\.notebook\.page(\.mid|\.lower)?$/.test(r.name || ''));
for (const r of staticRed) hide(r);

// ── ② 两套 clue 模板 ───────────────────────────────────────────────────────
const tplRoots = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (tplRoots.length !== 2) throw Error('clue 模板数不符：' + tplRoots.length);
const tplSummary = [];
for (const root of tplRoots) {
  const kids = g.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1');
  const b2 = kids.find(r => r.name === 'backrop2');
  if (!b1 || !b2) throw Error('模板缺 backrop1/2：' + root.id);
  // 隐藏红底与白线（只处理当前可见层，已隐藏的历史层不动）
  const reds = kids.filter(r => /^(art658\.clue\d+\.bg|art658\.clue\d+\.rule|art661\.clue\d+\.)/.test(r.name || ''));
  for (const r of reds) hide(r);
  // 恢复 5xx 旧方案：染色层在下、略大一圈；卡面白色与底板一致
  retint(b1, 'FF56565E');   // 普通态描边色（515/523/544 原值）
  retint(b2, 'FFFDFAEF');   // 与 art657.game.notebook.frame 白底板同色
  // 白底可读性：角色名/正文改深棕、字母徽章按《线索卡-设计规格》改 #28241E
  for (const r of kids.filter(q => ['who', 'what', 'letter'].includes(q.name))) {
    retintText(r, r.name === 'letter' ? 'FF28241E' : 'FF3A2A22');
  }
  const st1 = stateBlocks(b1.field.sub, [])[0], st2 = stateBlocks(b2.field.sub, [])[0];
  const w1 = pairValue(pairOf(st1, 505), 0), h1 = pairValue(pairOf(st1, 505), 1);
  const w2 = pairValue(pairOf(st2, 505), 0), h2 = pairValue(pairOf(st2, 505), 1);
  tplSummary.push({ rootId: root.id, backrop1: { id: b1.id, w: w1, h: h1, color: 'FF56565E' },
    backrop2: { id: b2.id, w: w2, h: h2, color: 'FFFDFAEF' },
    outline: [(w1 - w2) / 2, (h1 - h2) / 2], hiddenReds: reds.filter(r => isHiddenRecord(r.field)).length });
}

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) {
  if (bgIds.has(id)) return; bgIds.add(id);
  for (const r of g.recs) if (r.parentId === id) walk(r.id);
})(g.recs.find(r => r.name === 'police-v19').id);
// 注意：who/what/letter 是 clue 模板的文本子控件，本轮要改字色，不能列进保护名单；
// 运行时实例叫 who.1.1 / what.1.1 / letter.1.1，由 cell. / row. 前缀覆盖。
const protect = /^(clues\.help617$|clues\.help627\.hit$|hex\.|hit\.|hud\.|board\.floors|board\.rugs|cell\.|face$|gray$|gen\.|row\.|art656\.home\.grid\.|art661\.clues\.grid\.)/;
const protectedIds = new Set([...bgIds, ...g.recs.filter(r => r.name && protect.test(r.name)).map(r => r.id)]);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));

if (DRY) {
  console.log(JSON.stringify({
    dry: true, baseSha256: ACTUAL_BASE, records: g.recs.length,
    hidden: hidden.length, modified: modified.length,
    staticRedHidden: staticRed.map(r => r.name), tplSummary,
  }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '667 white clue cards + restore 5xx backrop1/backrop2 outline scheme',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    let seen = 0;
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (protectedIds.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '受保护记录被改动 ' + r.name;
      if (!touched.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '非目标记录被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
      seen++;
    }
    if (seen !== expected.size) return '记录数不符';
    // 两套模板的 backrop1 必须仍在 backrop2 之前（染色层在下）
    const recTop = t.tree.find(q => q.field === 9);
    const idx = new Map(); recTop.sub.forEach((f, i) => idx.set(f, i));
    for (const r of t.recs.filter(q => q.name === 'backrop1')) {
      const root = t.recs.find(q => q.id === r.parentId);
      const b2 = t.recs.find(q => q.parentId === root.id && q.name === 'backrop2');
      if (idx.get(r.field) > idx.get(b2.field)) return '染色层跑到卡面之上 #' + root.id;
    }
    // childList 仍与全局记录表同序
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      if (!cl) continue;
      const list = (asIdList(cl.payload, true) || []).filter(id => idx.has(byId.get(id)?.field));
      if (list.some((id, i) => i > 0 && idx.get(byId.get(list[i - 1])?.field) > idx.get(byId.get(id)?.field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});

const audit = {
  version: 1, name: '667 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '666_线索换位.gil', sha256: ACTUAL_BASE, records: g.recs.length, scriptBytes: scriptBefore.length },
  output: { file: '667_线索卡背景.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    finding: '666 把两套 clue 模板的 backrop1/backrop2 改为 #00FFFFFF 全透明；层序本来就正确（染色层在下、330×85.4 比卡面 324×79.4 大 6px），只是颜色失效，导致脚本给 backrop1 写 HIGHLIGHT_TINT(0xFFFFD44B) 时整张卡透黄、描边消失，并在红底上沿露出白框形成「一小段白色」。',
    item1_white: '隐藏静态 art657.game.notebook.page 与两套模板的 art658.clueN.bg / art661.clueN.*(28层) / art658.clueN.rule，卡片区露出白色底板 art657.game.notebook.frame(#FDFAEF)。',
    item2_oldScheme: 'backrop1 → #FF56565E（515/523/544 旧档原色，染色层/描边）；backrop2 → #FFFDFAEF 白色卡面。普通态白卡 + 3px 描边；选中态 Lua 把 backrop1 染黄，只有那一圈变黄，符合《线索卡-设计规格》「选中态只改描边，外框尺寸不变」。',
    item3_readability: '附带修正：两套模板的 who/what 字色 #FFFFFFFF → #FF3A2A22、letter → #FF28241E，否则白底白字不可见；只改存档文本控件的 504 字色，不改文本内容和 Lua（_fill_grid_item 不覆盖这些控件字色）。',
    untouched: '内嵌 Lua、26 条 666 文本内容、控件几何/父子/childList、v19 背景子树均未改动；未动层序与记录数。',
  },
  counts: { recordsBefore: g.recs.length, recordsAfter: expected.size,
    hidden: hidden.length, modified: modified.length },
  tplSummary, hidden, modified,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '667_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256,
  records: expected.size, hidden: hidden.length, modified: modified.length,
  scriptBytes: scriptBefore.length, tplSummary, status: 'APPLIED',
}, null, 2));
