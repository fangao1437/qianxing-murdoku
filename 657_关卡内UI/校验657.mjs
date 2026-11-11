// 657 结构校验：与 656 基准逐记录比对，确认背景资产 / 内嵌 Lua / 功能控件未被破坏
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const { readGil, encodeMsg, findChildListTop, asIdList, stateBlocks, pairOf, pairValue } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const A = readGil(path.join(DIR, '../656_首页设计/656_首页设计.gil'));
const B = readGil(path.join(DIR, '657_关卡内UI.gil'));
const enc = r => encodeMsg([r.field]).toString('hex');
const ma = new Map(A.recs.map(r => [r.id, r])), mb = new Map(B.recs.map(r => [r.id, r]));
const added = [...mb.keys()].filter(id => !ma.has(id));
const removed = [...ma.keys()].filter(id => !mb.has(id));
const changed = [...ma.keys()].filter(id => mb.has(id) && enc(ma.get(id)) !== enc(mb.get(id)));

function descendants(g, rootName) {
  const byParent = new Map();
  for (const r of g.recs) { const k = r.parentId ?? 0; if (!byParent.has(k)) byParent.set(k, []); byParent.get(k).push(r.id); }
  const root = g.recs.find(r => r.name === rootName); if (!root) return [];
  const out = new Set([root.id]), q = [root.id];
  while (q.length) for (const c of byParent.get(q.shift()) || []) if (!out.has(c)) { out.add(c); q.push(c); }
  return [...out];
}
const bgA = new Set(descendants(A, 'police-v12')), bgB = new Set(descendants(B, 'police-v12'));
const bgChanged = changed.filter(id => bgA.has(id) || bgB.has(id));
const bgAdded = added.filter(id => bgB.has(id));
const bgRemoved = removed.filter(id => bgA.has(id));

const s0 = findScriptLeaf(A).buf.toString('utf8'), s1 = findScriptLeaf(B).buf.toString('utf8');
const PATCH_FROM = '    art641_screen = screen\n  end\nend';
const PATCH_TO = `    art641_screen = screen
    do
      local gp = adapter:find("art657.grid.reuse")
      if gp ~= nil then
        help_visible(gp, screen == "home" or screen == "game")
        local dx, dy = 0, 0
        if screen == "game" then dx, dy = 105, 46 end
        pcall(function() gp:SetAnchoredPosition(dx, dy) end)
      end
    end
  end
end`;
const scriptPatchOnly = s1.replace(PATCH_TO, PATCH_FROM) === s0;

function hidden(r) {
  const walk = f => {
    if (!f.sub) return false;
    if (f.field === 17 && f.wt === 2 && f.sub && f.sub.some(x => x.field === 503 && Number(x.num) === 1)) return true;
    return f.sub.some(walk);
  };
  return (r.field.sub || []).some(walk);
}
const AUDIT = JSON.parse(fs.readFileSync(path.join(DIR, '657_构建审计.json'), 'utf8'));
const hiddenState = Object.fromEntries(AUDIT.hidden.map(n => {
  const r = B.recs.find(q => q.name === n);
  return [n, r ? hidden(r) : 'MISSING'];
}));
const recTop = B.tree.find(q => q.field === 9);
const order = new Map(); recTop.sub.forEach((f, i) => { const r = B.recs.find(q => q.field === f); if (r) order.set(r.id, i); });
const newRecs = added.map(id => mb.get(id));
// art657.grid.reuse 是首页网格纸的复用父容器，按设计挂 root；其余新层都挂 game 分类父
const wrongParent = newRecs.filter(r => r.name !== 'art657.grid.reuse'
  && mb.get(r.parentId)?.name !== 'grp653.static.1.art641.game').map(r => r.name);
const hiddenNew = newRecs.filter(hidden).map(r => r.name);
// 所有受影响父的 childList 是否与全局记录表同序
let orderOk = true;
for (const pid of new Set(newRecs.map(r => r.parentId))) {
  const p = mb.get(pid), cl = findChildListTop(p?.field?.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []).filter(id => order.has(id)) : [];
  if (ids.some((id, i) => i > 0 && order.get(ids[i - 1]) > order.get(id))) orderOk = false;
}
// 关键功能控件
const keys = ['root', 'home', 'home.select', 'stage', 'board.bg', 'board.floors', 'board.rugs',
  'clues', 'clues.bg', 'clues.grid', 'clues.help617', 'clues.help627.hit',
  'police-v12', 'hud.title', 'hud.timer', 'hex.back', 'hex.submit', 'hex.redo', 'hex.undo', 'hex.hint',
  'hit.back', 'hit.submit', 'hit.redo', 'hit.undo', 'hit.hint', 'art641.game.help.tab'];
const missing = keys.filter(n => !B.recs.some(r => r.name === n));
// 图标 / 热区 / 旗面三者中心一致
function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? [800 + pairValue(p, 0), 450 - pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)] : null;
}
const pairs = ['back', 'submit', 'redo', 'undo', 'hint'];
const centerMismatch = pairs.filter(k => {
  const h = geom(B.recs.find(r => r.name === 'hex.' + k));
  const t = geom(B.recs.find(r => r.name === 'hit.' + k));
  const f = geom(B.recs.find(r => r.name === 'art641.game.flag.' + k));
  // 返回箭头按设计图本来就偏旗面左侧约 15px（x27-143 旗面 / 白箭头偏左），放宽这一项
  const dx = k === 'back' ? 20 : 1;
  return !h || !t || !f || Math.abs(h[0] - f[0]) > dx || Math.abs(h[1] - f[1]) > 1
    || Math.abs(t[0] - f[0]) > dx || Math.abs(t[1] - f[1]) > 1;
});
const helpGeom = {
  tab: geom(B.recs.find(r => r.name === 'art641.game.help.tab')),
  body: geom(B.recs.find(r => r.name === 'clues.help617')),
  hit: geom(B.recs.find(r => r.name === 'clues.help627.hit')),
};
const helpAligned = helpGeom.tab && helpGeom.body && helpGeom.hit
  && Math.abs(helpGeom.tab[0] - helpGeom.body[0]) < 1 && Math.abs(helpGeom.tab[1] - helpGeom.body[1]) < 1
  && Math.abs(helpGeom.tab[0] - helpGeom.hit[0]) < 1 && Math.abs(helpGeom.tab[2] - helpGeom.hit[2]) < 1;

const report = {
  base: '656_首页设计.gil', output: '657_关卡内UI.gil',
  recordsBefore: A.recs.length, recordsAfter: B.recs.length,
  added: added.length, removed: removed.length, changedExisting: changed.length,
  changedExistingNames: changed.map(id => ma.get(id).name || ('#' + id)),
  policeV12: { descendantsBefore: bgA.size, descendantsAfter: bgB.size,
    changed: bgChanged.length, added: bgAdded.length, removed: bgRemoved.length,
    untouched: bgChanged.length + bgAdded.length + bgRemoved.length === 0 },
  script: { patchOnly: scriptPatchOnly, bytesBefore: Buffer.byteLength(s0), bytesAfter: Buffer.byteLength(s1),
    note: '仅一处补丁：sync_art641() 切屏分支加 art657.grid.reuse 父级显隐 + 父级坐标；反向替换后与 656 逐字节相同' },
  hiddenRecords: { count: AUDIT.hidden.length, allEffective: Object.values(hiddenState).every(v => v === true) },
  newLayers: { count: newRecs.length, wrongParent, hiddenButShouldBeVisible: hiddenNew,
    childListFollowsRecordOrder: orderOk },
  keyControlsMissing: missing,
  iconHitCentersAligned: centerMismatch.length === 0, centerMismatch,
  helpButtonAligned: helpAligned, helpGeom,
  verdict: (bgChanged.length + bgAdded.length + bgRemoved.length === 0) && scriptPatchOnly
    && removed.length === 0 && missing.length === 0 && wrongParent.length === 0
    && hiddenNew.length === 0 && orderOk && centerMismatch.length === 0 && helpAligned
    && Object.values(hiddenState).every(v => v === true),
};
fs.writeFileSync(path.join(DIR, '657_结构校验.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (!report.verdict) process.exitCode = 1;
