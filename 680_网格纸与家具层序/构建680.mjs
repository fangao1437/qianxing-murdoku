// 680 · 基于 679 的两项修复（679 保留未改）
//   ① 网格纸没跟随下移：
//      679 改的是 art657.grid.reuse **父层** 504 y(-30)，但内嵌 Lua 的 sync_art641()
//      切屏时执行 gp:SetAnchoredPosition(105,46) 强制覆盖父坐标 ⇒ 真机父层位移失效。
//      ⇒ 改为：父层 504 y 恢复 0；把 Δy=+30 加到 **49 个子层** 的 504 y（减 30，y 向上为正）。
//        子层相对父的偏移不会被 Lua 覆盖 ⇒ 离线预览与真机一致下移 30。
//   ② 桌子挡住 X 标记（历史地毯同类，用户要求一并解决）：
//      cfg.cells.layer_order 从下到上是 face/hint/obj..obj12/portrait/wall/door/x/note，
//      **rug_layer 与 furn 两个容器没有排位** ⇒ enforce_layers 倒序 SetAsFirstSibling 后
//      未列出的容器留在最上层，盖住 x。历史 v283「家具盖住头像」正是靠插入 portrait 层解决。
//      ⇒ 在 obj12 之后、portrait 之前插入 "rug_layer", "furn" ⇒ 两者都排在 x 之下。
//      同步改 lua/entry_client_script.lua 源码以便未来 bundle 保留。
//
// 输入  ../679_棋盘居中与边缘/679_棋盘居中与边缘.gil（7431 条）
// 输出  680_网格纸与家具层序.gil（7431 条，0 新增 / 0 删除）
// 用法  FORCE=1 node 构建680.mjs   /   node 构建680.mjs --dry

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/680_网格纸与家具层序');
const INPUT = path.join(ROOT, 'qianxing-murdoku/679_棋盘居中与边缘/679_棋盘居中与边缘.gil');
const OUTPUT = path.join(DIR, '680_网格纸与家具层序.gil');
const SRC_LUA = path.join(ROOT, 'qianxing-murdoku/lua/entry_client_script.lua');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const url = p => pathToFileURL(p).href;
const { readGil, stateBlocks, pairOf, pairValue, setPair, cloneField, textsOf, encodeMsg,
  ensureChildListTop, findChildListTop, asIdList, setChildList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const scriptLeaf = findScriptLeaf(g);
const scriptBefore = scriptLeaf.buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const scriptOwner = g.recs.find(r => encodeMsg([r.field]).includes(scriptBefore.subarray(0, 64)));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));

function states(r) { return stateBlocks(r.field.sub, []); }
const modified = [], touchedIds = new Set();
function touch(r) { if (!r) return; touchedIds.add(r.id); if (r.name && !modified.includes(r.name)) modified.push(r.name); }
function named(n) { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; }

// ── ① 网格纸：49 子层下移 30，父层恢复 0 ────────────────────────────────
const SHIFT = 30;
const reuse = named('art657.grid.reuse');
const kids = g.recs.filter(r => r.parentId === reuse.id);
if (kids.length !== 49) throw Error('网格纸子层数量不符：' + kids.length);
const parentBefore = [];
for (const st of states(reuse)) {
  const p = pairOf(st, 504);
  parentBefore.push([pairValue(p, 0), pairValue(p, 1)]);
}
if (parentBefore.some(([, y]) => Math.abs(y + 30) > 0.01))
  throw Error('父层 504 y 不是 679 的 -30：' + JSON.stringify(parentBefore));
// 父恢复 0（Lua 会覆盖，存档里也保持与 678 一致，离线预览才不会重复下移）
for (const st of states(reuse)) {
  const p = pairOf(st, 504);
  setPair(p, pairValue(p, 0), 0);
}
touch(reuse);
const childBefore = {}, childAfter = {};
for (const k of kids) {
  const before = [], after = [];
  for (const st of states(k)) {
    const p = pairOf(st, 504);
    const x = pairValue(p, 0), y = pairValue(p, 1);
    before.push([x, y]);
    setPair(p, x, y - SHIFT);          // y 向上为正 ⇒ 下移 30 要减 30
    after.push([x, y - SHIFT]);
  }
  childBefore[k.name] = before[0]; childAfter[k.name] = after[0];
  touch(k);
}

// ── ② 内嵌 Lua：layer_order 插入 rug_layer / furn ────────────────────────
const s0 = scriptBefore.toString('utf8');
const ANCHOR = '        "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",\n';
if (s0.split(ANCHOR).length !== 2) throw Error('layer_order 锚点不唯一');
const PATCH = ANCHOR + '        "rug_layer", "furn",\n';
const s1 = s0.replace(ANCHOR, PATCH);
if (s1.length - s0.length !== PATCH.length - ANCHOR.length) throw Error('脚本补丁长度异常');
scriptLeaf.field.payload = Buffer.from(s1, 'utf8');
scriptLeaf.field.len = Buffer.byteLength(s1);
if (scriptOwner) touch(scriptOwner);
// 源码同步（未来 bundle 时保留）；dist 不重打包（与内嵌本就不同版本，避免巨变）
const src = fs.readFileSync(SRC_LUA, 'utf8');
const SRC_LINE = '        "obj7", "obj8", "obj9", "obj10", "obj11", "obj12",';
if (!src.includes(SRC_LINE)) throw Error('源码 layer_order 锚点缺失');
if (!src.includes('"rug_layer", "furn",')) {
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const srcPatch = SRC_LINE + eol
    + '        -- ★ 680：跨格家具容器必须排在 x 之下（历史 v283 插 portrait 同类修法）' + eol
    + '        --   未列入 layer_order 的容器会留在最上层，盖住 x 标记（地毯/桌子都出现过）。' + eol
    + '        "rug_layer", "furn",';
  const i = src.indexOf(SRC_LINE);
  const s2 = src.slice(0, i) + srcPatch + src.slice(i + SRC_LINE.length);
  if (s2 === src) throw Error('源码补丁未生效');
  fs.writeFileSync(SRC_LUA, s2, 'utf8');
  console.log('已同步源码 lua/entry_client_script.lua');
}

// ── 闸门 ─────────────────────────────────────────────────────────────────
// 网格纸：x/尺寸不变、y 精确 -30；父层恢复 0
for (const k of kids) {
  const b = childBefore[k.name], a = childAfter[k.name];
  if (Math.abs(a[0] - b[0]) > 0.01 || Math.abs(a[1] - (b[1] - SHIFT)) > 0.01)
    throw Error('网格纸子层平移断言失败 ' + k.name);
}
// 内嵌脚本：反向替换后与基准逐字节相同（证明只改了这一处）
const scriptOk = s1.replace(PATCH, ANCHOR) === s0
  && (s1.match(/"rug_layer", "furn",/g) || []).length === 1;
if (!scriptOk) throw Error('内嵌脚本补丁不干净');

// 既有成果（除 49 子层 + 父层 + 脚本记录）逐字节不变
const targetNames = new Set([...kids.map(k => k.name), 'art657.grid.reuse']);
const keep = g.recs.filter(r => r.name && !targetNames.has(r.name)
  && (/^(art675\.wax\.|art664\.tab\.(mid|hi)\.fit\d+$|art677\.ring\.|art678\.tab\.)/.test(r.name)
    || ['clues.help617', 'clues.help627.hit', 'art657.game.notebook.frame',
        'art658.clues.binding', 'art676.binding.mid', 'stage',
        'art641.game.boardframe.paper', 'art641.game.boardframe.shadow', 'art641.game.boardbottom',
        'art641.game.help.tab', 'art661.tab.outline'].includes(r.name))).map(r => r.name);
const keepBytes = new Map(keep.map(n => [n, beforeBytes.get(named(n).id)]));
for (const n of keep)
  if (!keepBytes.get(n).equals(encodeMsg([named(n).field]))) throw Error('既有成果被改动 ' + n);
if (keep.filter(n => /^art675\.wax\./.test(n)).length !== 240) throw Error('675 火漆层数不符');
if (keep.filter(n => /^art664\.tab\.(mid|hi)\.fit\d+$/.test(n)).length !== 23) throw Error('672 渐变三角数不符');

const bgIds = new Set();
(function walk(id) { if (bgIds.has(id)) return; bgIds.add(id); for (const r of g.recs) if (r.parentId === id) walk(r.id); })
  (g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const changed = [...byId.keys()].filter(id =>
  beforeBytes.has(id) && !beforeBytes.get(id).equals(encodeMsg([byId.get(id).field])));
const changedExtra = changed.filter(id => {
  const n = byId.get(id).name;
  return n && !targetNames.has(n) && n !== (scriptOwner && scriptOwner.name);
});
if (changedExtra.length) throw Error('非目标记录被改动：' + changedExtra.slice(0, 5).map(id => byId.get(id).name).join(','));
if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE,
    recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: 0, removed: 0, changed: changed.length,
    gridKids: kids.length, shift: SHIFT, scriptOnlyPatch: scriptOk,
    scriptBytes: [scriptBefore.length, Buffer.byteLength(s1)], keep: keep.length }, null, 2));
  process.exit(0);
}
const report = writeGil(g, OUTPUT, {
  label: '680 grid paper follow board shift (49 children) + rug_layer/furn below x in layer_order',
  expectRecs: expected.size,
  assert(t) {
    const leaf = findScriptLeaf(t);
    if (!leaf.buf.equals(Buffer.from(s1, 'utf8'))) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (bgIds.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    const rt = t.tree.find(q => q.field === 9);
    const idx = new Map(); rt.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    for (const n of keep) {
      const a = t.recs.find(q => q.name === n);
      if (!a || !beforeBytes.get(a.id).equals(encodeMsg([a.field]))) return '既有成果被改动 ' + n;
    }
    return true;
  },
});
const audit = {
  version: 1, name: '680 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '679_棋盘居中与边缘.gil', sha256: ACTUAL_BASE, records: beforeBytes.size, scriptBytes: scriptBefore.length },
  output: { file: '680_网格纸与家具层序.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size, scriptBytes: Buffer.byteLength(s1) },
  spec: {
    userFeedback: '棋盘背景的网格纸没有跟随下移；桌子的其中一格会挡住 x 标记，历史上地毯也出现过，查询历史一并解决',
    gridPaper: { rootCause: '内嵌 Lua sync_art641() 切屏时 gp:SetAnchoredPosition(105,46) 覆盖 art657.grid.reuse 父坐标，679 改父层无效',
      fix: '父层 504 y 恢复 0；49 个子层 504 y 各 -30（y 向上为正 ⇒ 下移 30），子层相对父偏移不会被 Lua 覆盖',
      kids: kids.length, shift: SHIFT, xUnchanged: true },
    xMark: { rootCause: 'layer_order 未列出 rug_layer / furn 容器 ⇒ enforce_layers 倒序 SetAsFirstSibling 后它们留在最上层，盖住 x',
      history: 'v283「家具盖住头像」正是靠在 layer_order 插入 portrait 层解决；v327 地毯按轴缩放；v315/v316 家具实例 SetSiblingIndex(地毯=1/家具=2)',
      fix: '在 obj12 之后、portrait 之前插入 "rug_layer", "furn" ⇒ 两个容器都排在 x 之下',
      patchOnly: scriptOk, srcSynced: true },
    keepUntouched: keep.length,
  },
  counts: { recordsBefore: beforeBytes.size, recordsAfter: expected.size,
    added: 0, removed: 0, changed: changed.length },
  changedNames: changed.map(id => byId.get(id).name || '#' + id),
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '680_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  recordsBefore: audit.counts.recordsBefore, recordsAfter: audit.counts.recordsAfter,
  added: 0, removed: 0, changed: changed.length, gridKids: kids.length,
  scriptOnlyPatch: scriptOk, scriptBytes: [scriptBefore.length, Buffer.byteLength(s1)], status: 'APPLIED' }, null, 2));
