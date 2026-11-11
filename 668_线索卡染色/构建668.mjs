// 668 · 撤销 667 对「卡片本身」的误改，只保留「删掉卡片区背后那块大红底板」
//
// 用户口径（本轮）：
//   「线索卡本身的染色不要删，把原来那个阶梯渐变红色素材放在 backrop1 的位置，文本颜色改回来」
// 上一轮把「删红底」误解成连卡片模板里的阶梯渐变一起隐藏，导致 667 实机变成全白卡 + 深字。
// 正确理解：要删的是 **卡片区背后那块静态大红底板** art657.game.notebook.page，
//   卡片本身仍应是 666 的红色阶梯渐变，文字仍是白色。
//
// 「阶梯渐变素材放在 backrop1 的位置」：666 的两套 clue 模板层序本来就是
//   art658.clueN.bg(23) + art661.clueN.* 28 层(42..69) → rule(70) → backrop1(71) → backrop2(72)
//   即整套阶梯渐变紧邻 backrop1 之前；backrop1/backrop2 为 #00FFFFFF 透明，
//   脚本 _grid_paint_highlight() 给 backrop1 写 HIGHLIGHT_TINT 时整张卡染黄。
//   保持该层序 = 渐变素材位于 backrop1 位置，且高亮仍能覆盖整张卡；若把 backrop1 移到
//   渐变之下，染黄反而会被 28 层渐变盖住。故本轮不移动层序。
//
// 因此 668 = 666 + 仅隐藏 art657.game.notebook.page 一条记录。
// 基准选择 666 而非 667：666 的 Lua / 26 条文本 / 控件几何与 667 逐字节相同，
//   从 666 重建等价于完整撤销 667 的卡片改动，风险最低、改动面最小。
//
// 输入：666_线索换位.gil（不覆盖）
// 输出：668_线索卡染色.gil + 668_构建审计.json

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
const ROOT = 'D:/新建文件夹/miHoYo Launcher';
const DIR = path.join(ROOT, 'qianxing-murdoku/668_线索卡染色');
const INPUT = path.join(ROOT, 'qianxing-murdoku/666_线索换位/666_线索换位.gil');
const OUTPUT = path.join(DIR, '668_线索卡染色.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const ACTUAL_BASE = sha(INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
const DRY = process.argv.includes('--dry');

const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, findChildListTop, asIdList } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilread.mjs'));
const { writeGil, findScriptLeaf } =
  await import(url(ROOT + '/qianxing-murdoku/tools/gil/gilwrite.mjs'));
const { setHiddenRecord, isHiddenRecord } =
  await import(url(ROOT + '/qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js'));

const g = readGil(INPUT);
const scriptBefore = findScriptLeaf(g).buf;
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const origIds = new Set(g.recs.map(r => r.id));
const origParent = new Map(g.recs.map(r => [r.id, r.parentId]));
const danglingBefore = new Set([...origIds].filter(id =>
  origParent.get(id) != null && !origIds.has(origParent.get(id))));

// ── 唯一改动：隐藏卡片区背后那块静态大红底板 ────────────────────────────────
const target = g.recs.filter(r => r.name === 'art657.game.notebook.page');
if (target.length !== 1) throw Error('静态底板记录数不符：' + target.length);
const rec = target[0];
if (isHiddenRecord(rec.field)) throw Error('静态底板在 666 里已经是隐藏态，请复核基准');
setHiddenRecord(rec.field, true);
const changedIds = new Set([rec.id]);

// 卡片模板的阶梯渐变 / backrop / 文字色全部保持 666 原样（不触碰）
const tplRoots = g.recs.filter(r => r.name === 'clue' && g.recs.some(q => q.parentId === r.id && q.name === 'backrop1'));
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const tplSummary = tplRoots.map(root => {
  const kids = g.recs.filter(r => r.parentId === root.id);
  const grad = kids.filter(r => /^art661\.clue/.test(r.name || '') && !isHiddenRecord(r.field));
  const bg = kids.find(r => /^art658\.clue\d+\.bg$/.test(r.name || ''));
  const b1 = kids.find(r => r.name === 'backrop1');
  const b2 = kids.find(r => r.name === 'backrop2');
  const ip = r => ns(r.field, [505, 503, 84])[0];
  const tp = r => ns(r.field, [505, 503, 75])[0];
  return {
    rootId: root.id, visibleGradientLayers: grad.length,
    bgVisible: !isHiddenRecord(bg.field), bgColor: (num(ip(bg), 502) >>> 0).toString(16).toUpperCase(),
    backrop1: (num(ip(b1), 502) >>> 0).toString(16).toUpperCase(),
    backrop2: (num(ip(b2), 502) >>> 0).toString(16).toUpperCase(),
    textColors: Object.fromEntries(['who', 'what', 'letter'].map(n => {
      const r = kids.find(q => q.name === n);
      return [n, (num(tp(r), 504) >>> 0).toString(16).toUpperCase()];
    })),
  };
});

// ── 断言 + 落盘 ─────────────────────────────────────────────────────────────
const bgIds = new Set();
(function walk(id) {
  if (bgIds.has(id)) return; bgIds.add(id);
  for (const r of g.recs) if (r.parentId === id) walk(r.id);
})(g.recs.find(r => r.name === 'police-v19').id);
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));

if (DRY) {
  console.log(JSON.stringify({ dry: true, baseSha256: ACTUAL_BASE, records: g.recs.length,
    changed: [...changedIds], tplSummary }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '668 keep clue card gradient, remove only the static red backdrop',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBefore)) return '内嵌 Lua 发生变化';
    const ids = new Set(t.recs.map(r => r.id));
    let diff = 0, seen = 0;
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
      if (beforeBytes.has(r.id) && !beforeBytes.get(r.id).equals(encodeMsg([r.field]))) diff++;
      if (bgIds.has(r.id) && beforeBytes.get(r.id)?.equals(encodeMsg([r.field])) === false)
        return 'v19 背景被改动 ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id))
        return '新增悬空父引用 ' + r.name;
      seen++;
    }
    if (diff !== 1) return '本轮应只有 1 条记录变化，实得 ' + diff;
    if (seen !== expected.size) return '记录数不符';
    const recTop = t.tree.find(q => q.field === 9);
    const idx = new Map(); recTop.sub.forEach((f, i) => idx.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      if (!cl) continue;
      const list = (asIdList(cl.payload, true) || []).filter(id => idx.has(t.recs.find(q => q.id === id)?.field));
      if (list.some((id, i) => i > 0 && idx.get(t.recs.find(q => q.id === list[i - 1]).field) > idx.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});

const audit = {
  version: 1, name: '668 build audit', date: new Date().toISOString().slice(0, 10),
  base: { file: '666_线索换位.gil', sha256: ACTUAL_BASE, records: g.recs.length, scriptBytes: scriptBefore.length },
  output: { file: '668_线索卡染色.gil', sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size, records: expected.size },
  spec: {
    correction: '撤销 667 误把卡片本身的阶梯渐变染色一起隐藏的改动；只保留上轮「删掉卡片区背后大红底板」的要求。',
    onlyChange: '隐藏 art657.game.notebook.page 一条记录 ⇒ 卡片区背景露出白色底板 art657.game.notebook.frame(#FDFAEF)。',
    cardKept: '两套 clue 模板的 art658.clueN.bg + art661.clueN.*(28 层阶梯渐变) + rule 白线 + backrop1/backrop2(#00FFFFFF) + who/what/letter(#FFFFFFFF 白字) 全部保持 666 原样。',
    backrop1Position: '666 层序中渐变组(23..69) → rule(70) → backrop1(71) → backrop2(72)，渐变素材本就紧邻 backrop1 之前；保持该层序使脚本 _grid_paint_highlight 给 backrop1 写 HIGHLIGHT_TINT 时整张卡染黄，染色不会被 28 层渐变盖住。',
    untouched: '内嵌 Lua、26 条 666 文本、控件几何/父子/childList、层序、v19 背景子树均未改动。',
  },
  counts: { recordsBefore: g.recs.length, recordsAfter: expected.size, changed: 1 },
  hidden: ['art657.game.notebook.page'], tplSummary,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '668_构建审计.json'),
  JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
console.log(JSON.stringify({
  output: OUTPUT, sha256: audit.output.sha256, records: expected.size,
  changed: 1, scriptBytes: scriptBefore.length, tplSummary, status: 'APPLIED',
}, null, 2));
