// 669 · 恢复旧高亮方案：红色渐变放 backrop2，染色区保留在 backrop1
//
// 用户澄清：「把红色放在 backrop2，染色区还是 backrop1，注意核对控件位置」
// 实测 668 两套 clue 模板（模板局部坐标，中心 800,450）：
//   backrop1  cx=800 cy=450  330.0×85.4  #00FFFFFF   ← 染色区，脚本 _grid_paint_highlight 写 imageColor
//   backrop2  cx=800 cy=450  324.0×79.4  #00FFFFFF   ← 卡面，比染色区小 6px（上下左右各 3px）
//   art658.clueN.bg + art661.clueN.* 28 层 = 330.0×85.4 红色阶梯渐变（与 backrop1 同大）
//   art658.clueN.rule = 330×5 @ (800,410) 白线
//   who/what/letter 文本 = #FFFFFFFF 白字
//
// 关键：红色渐变原本 330×85.4，若原样放上去会把 backrop1 完全盖住 ⇒ 染色区失效。
// 本轮把渐变组按 backrop2 的 324×79.4 做仿射缩放（SX=324/330, SY=79.4/85.4，
// 中心相对 (800,450) 的偏移同比例缩放，rot 不变），使 backrop1 恰好露 3px 一圈。
//
// 层序（两套模板同步重排，recTop 与 childList 都改）：
//   backrop1 (染色区/描边 #FF56565E) → backrop2 (#FF611F23 渐变底色)
//   → art658.clueN.bg + 28 层阶梯渐变(324×79.4) → rule 白线 → 文字
// 普通态：红渐变卡 + 3px 描边；选中态：Lua 把 backrop1 染 HIGHLIGHT_TINT(0xFFFFD44B)，
//   只有露出的 3px 一圈变黄，卡面红渐变不变 —— 即 5xx 旧高亮方案。
//
// 基准：668_线索卡染色.gil（卡片区背后红底板已删、文字白、Lua 与 666 一致）
// 输出：669_旧高亮方案.gil + 669_构建审计.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/669_旧高亮方案');
const INPUT = path.join(ROOT, 'qianxing-murdoku/668_线索卡染色/668_线索卡染色.gil');
const OUTPUT = path.join(DIR, '669_旧高亮方案.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const DRY = process.argv.includes('--dry');

const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, setPair,
  findChildListTop, asIdList, setChildList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const recTop = g.tree.find(q => q.field === 9);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const origIds = new Set(g.recs.map(r => r.id));
const origParent = new Map(g.recs.map(r => [r.id, r.parentId]));
const danglingBefore = new Set([...origIds].filter(id =>
  origParent.get(id) != null && !origIds.has(origParent.get(id))));

const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const colorOf = hex => parseInt(hex.replace('#', ''), 16) >>> 0;
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
function screenGeom(r) {
  const st = states(r)[0], p = st && pairOf(st, 504), s = st && pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
const touched = new Set(), modified = [];
function touch(r) { touched.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function setGeom(r, cx, cy, w, h) {
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - 800, 450 - cy);
    setPair(pairOf(st, 505), w, h);
  }
  touch(r);
}
function retint(r, aarrggbb) {
  const p = ns(r.field, [505, 503, 84])[0];
  if (!p) throw Error('找不到图片块 ' + r.name);
  setNum(p, 502, colorOf(aarrggbb)); setNum(p, 504, 1);
  touch(r);
}
const SX = 324 / 330, SY = 79.4 / 85.4;
const TPL = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
if (TPL.length !== 2) throw Error('clue 模板数不符：' + TPL.length);
const moved = [];
const summary = [];

for (const root of TPL) {
  const kids = g.recs.filter(r => r.parentId === root.id);
  const b1 = kids.find(r => r.name === 'backrop1');
  const b2 = kids.find(r => r.name === 'backrop2');
  const bg = kids.find(r => /^art658\.clue\d+\.bg$/.test(r.name || ''));
  if (!b1 || !b2 || !bg) throw Error('模板缺 backrop1/backrop2/bg：' + root.id);
  const g1 = screenGeom(b1), g2 = screenGeom(b2);
  if (Math.abs(g1[2] - 330) > 0.01 || Math.abs(g2[2] - 324) > 0.01
      || Math.abs(g1[0] - g2[0]) > 0.01 || Math.abs(g1[1] - g2[1]) > 0.01)
    throw Error('控件位置与预期不符，停止构建：' + JSON.stringify({ g1, g2 }));

  // ① 染色区 backrop1：恢复旧档描边色；卡面 backrop2：渐变最暗底色
  retint(b1, 'FF56565E');
  retint(b2, 'FF611F23');

  // ② 红色阶梯渐变按 backrop2 尺寸仿射缩放（含白线），保证 backrop1 露 3px
  const grad = kids.filter(r => /^(art658\.clue\d+\.bg|art658\.clue\d+\.rule|art661\.clue\d+\.)/.test(r.name || ''));
  for (const r of grad) {
    const [cx, cy, w, h] = screenGeom(r);
    setGeom(r, 800 + (cx - 800) * SX, 450 + (cy - 450) * SY, w * SX, h * SY);
  }

  // ③ 层序：把 backrop1 → backrop2 移到渐变组之前（染色区在最下）
  const fields = [b1.field, b2.field];
  for (const f of fields) {
    const i = recTop.sub.indexOf(f);
    if (i < 0) throw Error('backrop 不在 recTop');
    recTop.sub.splice(i, 1);
  }
  const at = recTop.sub.indexOf(bg.field);
  if (at < 0) throw Error('bg 不在 recTop');
  recTop.sub.splice(at, 0, ...fields);

  // childList 同步（保持 b1 → b2 → bg 顺序）
  const cl = findChildListTop(root.field.sub);
  if (!cl) throw Error('模板缺 childList：' + root.id);
  const ids = (asIdList(cl.payload, true) || []).filter(id => ![b1.id, b2.id].includes(id));
  const j = ids.indexOf(bg.id);
  ids.splice(j < 0 ? 0 : j, 0, b1.id, b2.id);
  setChildList(cl, ids);
  touch(root);
  moved.push({ rootId: root.id, b1: b1.id, b2: b2.id, bg: bg.id });
  summary.push({
    rootId: root.id,
    backrop1: { cx: g1[0], cy: g1[1], w: g1[2], h: g1[3], color: 'FF56565E' },
    backrop2: { cx: g2[0], cy: g2[1], w: g2[2], h: g2[3], color: 'FF611F23' },
    outline: [(g1[2] - g2[2]) / 2, (g1[3] - g2[3]) / 2],
    scaledLayers: grad.length, scale: [SX, SY],
  });
}

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) {
  if (bgIds.has(id)) return; bgIds.add(id);
  for (const r of g.recs) if (r.parentId === id) walk(r.id);
})(g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE, records: g.recs.length,
    touched: touched.size, modified: modified.length, moved, summary }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '669 red gradient on backrop2, tint zone on backrop1',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (!touched.has(r.id) && beforeBytes.has(r.id)
          && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return '非目标记录被改动 ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field])))
        return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
    }
    const recTop2 = t.tree.find(q => q.field === 9);
    const idx = new Map(); recTop2.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const kids = t.recs.filter(q => q.parentId === root.id);
      const b1 = kids.find(q => q.name === 'backrop1'), b2 = kids.find(q => q.name === 'backrop2');
      const bg = kids.find(q => /^art658\.clue\d+\.bg$/.test(q.name || ''));
      if (!b1 || !b2 || !bg) return '模板控件缺失 #' + root.id;
      if (!(idx.get(b1.field) < idx.get(b2.field) && idx.get(b2.field) < idx.get(bg.field)))
        return '层序不是 backrop1 → backrop2 → 渐变组 #' + root.id;
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []) : [];
      const o1 = list.indexOf(b1.id), o2 = list.indexOf(b2.id), o3 = list.indexOf(bg.id);
      if (!(o1 >= 0 && o2 > o1 && o3 > o2)) return 'childList 层序不同步 #' + root.id;
      const ordered = list.filter(id => idx.has(t.recs.find(q => q.id === id)?.field));
      if (ordered.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === ordered[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});

const audit = {
  version: 1, name: '669 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '668_线索卡染色.gil', sha256: ACTUAL_BASE, records: g.recs.length, scriptBytes: scriptBefore.length },
  output: { file: '669_旧高亮方案.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    userClarification: '红色阶梯渐变放 backrop2（卡面 324×79.4），染色区仍是 backrop1（330×85.4，在下面、略大一圈露 3px），这才是要恢复的旧高亮方案。',
    measuredGeometry: 'backrop1 800,450 330×85.4；backrop2 800,450 324×79.4；原渐变组 330×85.4（与 backrop1 同大，会盖住染色区）。',
    scale: `渐变组按 backrop2 仿射缩放 SX=${SX.toFixed(6)} SY=${SY.toFixed(6)}，中心相对 (800,450) 偏移同比例，rot 不变；白线一并缩放。`,
    layerOrder: 'recTop 与 childList 同步重排为 backrop1 → backrop2 → bg + 28 层渐变 → rule → 文字。',
    result: '普通态红渐变卡 + 3px 描边；选中态 Lua 给 backrop1 写 0xFFFFD44B，只有 3px 一圈变黄，卡面红渐变不变。',
    kept: '白字 #FFFFFFFF、卡片区白色底板（静态红底板已隐藏）、内嵌 Lua、26 条文本、v19 背景子树全部保持 668 原样。',
  },
  counts: { recordsBefore: g.recs.length, recordsAfter: expected.size,
    modified: modified.length, touched: touched.size },
  summary, moved, modified,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '669_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256, records: expected.size,
  touched: touched.size, scriptBytes: scriptBefore.length, summary, status: 'APPLIED',
}, null, 2));
