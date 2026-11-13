// 684 · 独立结构校验（重新从磁盘读 683 / 684，不复用构建器内存状态）
//   node 校验684.mjs  → 684_结构校验.json  verdict = true
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList, writeVarint } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '684_规格.json'), 'utf8'));
const A = path.join(REPO, SPEC.base.file);
const B = path.join(DIR, '684_结算收紧与教程配色.gil');
const ga = readGil(A), gb = readGil(B);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const byId = new Map(gb.recs.map(r => [r.id, r]));
const byName = new Map(gb.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => byName.get(n);
const rt = gb.tree.find(f => f.field === 9);
const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
function imgParts(r) {
  const out = [];
  (function walk(f, d = 0) { if (d > 30) return; if (f.field === 84 && f.sub) out.push(f); if (f.sub) for (const s of f.sub) walk(s, d + 1); })(r.field);
  return out;
}
const fillOf = r => imgParts(r).map(p => p.sub.find(q => q.field === 502 && q.wt === 0)).find(Boolean);
const imgOf = r => imgParts(r).map(p => p.sub.find(q => q.field === 503 && q.wt === 0)).find(Boolean);
const geom = r => {
  const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? { dx: pairValue(p, 0), dy: pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1) } : null;
};
const checks = [];
const ck = (name, ok, detail = '') => { checks.push({ name, ok: !!ok, detail }); return !!ok; };

// ① 基础
ck('记录数 7621 → 7633', ga.recs.length === 7621 && gb.recs.length === 7633, `${ga.recs.length} → ${gb.recs.length}`);
const setA = new Set(ga.recs.map(r => r.id)), setB = new Set(gb.recs.map(r => r.id));
const newIds = [...setB].filter(i => !setA.has(i)), goneIds = [...setA].filter(i => !setB.has(i));
ck('新增 14 / 删除 2', newIds.length === 14 && goneIds.length === 2, `+${newIds.length} / -${goneIds.length}`);
ck('无重复 ID', new Set(gb.recs.map(r => r.id)).size === gb.recs.length);
ck('内嵌 Lua 逐字节相同', findScriptLeaf(ga).buf.equals(findScriptLeaf(gb).buf), `${findScriptLeaf(gb).buf.length} B`);
ck('输入 683 SHA 与规格一致', sha(A) === SPEC.base.sha256);

// ② 结算弹窗：按钮不溢出 / 文字不被裁
const RP = SPEC.resultPopup;
const yOk = RP.buttons.names.every((n, i) => R(n) && Math.abs(geom(R(n)).dy - RP.buttons.afterY[i]) < 0.01);
ck('结算四键 y = 12/-60/-132/-204', yOk,
  RP.buttons.names.map(n => n + '=' + (R(n) ? geom(R(n)).dy : '?')).join(' '));
const lastBottom = RP.buttons.afterY[3] - 32;   // 2px 描边外沿 64/2
ck('最后一个按钮描边底 -236 未越内页底 -285', lastBottom > -285,
  `底 ${lastBottom}，留白 ${(-285 - lastBottom) * -1}px`);
const lblOk = RP.labels.names.every(n => {
  const l = gb.recs.find(r => r.name === 'label' && r.parentId === R(n).id);
  return l && Math.abs(geom(l).w - RP.labels.widthAfter) < 0.01;
});
ck('4 个 result label 宽 125→312（5 字文本完整）', lblOk);
ck('结算倒计时移进内页 y=-258', Math.abs(geom(R(RP.countdown.name)).dy - RP.countdown.afterY) < 0.01);
ck('退出菜单四键保持 683 y=120/40/-40/-120',
  ['modal.exit', 'modal.save', 'modal.settle', 'modal.cancel'].map(n => geom(R(n)).dy).join(',') === '120,40,-40,-120');

// ③ 放大镜：删 100120 + 按 12.png 复刻
let glassOk = true, glassDetail = [];
for (const F of SPEC.glass.frames) {
  const face = R('art683.' + F.key + '.frame.inner.face');
  const ring = R('art684.' + F.key + '.frame.glass.ring');
  const hole = R('art684.' + F.key + '.frame.glass.hole');
  const handles = [0, 1, 2, 3, 4].map(j => R('art684.' + F.key + '.frame.glass.handle.' + j));
  if (gb.recs.some(r => r.name === 'art683.' + F.key + '.frame.glass')) { glassOk = false; glassDetail.push(F.key + ':100120 残留'); }
  if (!ring || !hole || handles.some(x => !x)) { glassOk = false; glassDetail.push(F.key + ':缺层'); continue; }
  const rc = fillOf(ring), hc = fillOf(hole);
  if (!rc || hex(rc.num) !== '#FFF9EFC7') { glassOk = false; glassDetail.push(F.key + ':外环色'); }
  if (!hc || hex(hc.num) !== '#FFFFF5D6') { glassOk = false; glassDetail.push(F.key + ':挖空色'); }
  if (Math.abs(geom(ring).w - F.ring) > 0.01 || Math.abs(geom(hole).w - F.hole) > 0.01) {
    glassOk = false; glassDetail.push(F.key + ':环尺寸');
  }
  if (Math.abs(geom(ring).dx - F.center[0]) > 0.01 || Math.abs(geom(ring).dy - F.center[1]) > 0.01) {
    glassOk = false; glassDetail.push(F.key + ':居中偏上位置');
  }
  if ([ring, hole, ...handles].some(x => {
    const im = imgOf(x); return !im || Number(im.num) !== 100002 || isHiddenRecord(x.field);
  })) { glassOk = false; glassDetail.push(F.key + ':图元/显隐'); }
  if (!(ord.get(face.field) < ord.get(ring.field) && ord.get(ring.field) < ord.get(hole.field) && ord.get(hole.field) < ord.get(handles[0].field))) {
    glassOk = false; glassDetail.push(F.key + ':层序');
  }
}
ck('2 组放大镜：100120 已删 / 粗环+挖空+5 段柄 / 12.png 色与位置 / 层序', glassOk,
  glassDetail.join('; ') || '2/2 通过');
const treeBytes = encodeMsg(gb.tree);
ck('被删 2 个 100120 层 ID 全文 0 引用',
  goneIds.every(id => !treeBytes.includes(Buffer.from(writeVarint(id)))), goneIds.join(','));

// ④ 首页教程五卡染色统一
const H = SPEC.homeTutorial;
let cardOk = true, cardDetail = [];
for (let i = 1; i <= 5; i++) {
  const c = fillOf(R('td.home.page.1.rule.' + i));
  const b = fillOf(R('td.home.page.1.rule.' + i + '.border'));
  const n = fillOf(R('td.home.page.1.rule.' + i + '.num.bg'));
  if (!c || hex(c.num) !== H.strictDesignColor.value) { cardOk = false; cardDetail.push('卡' + i + ' ' + (c && hex(c.num))); }
  if (!b || hex(b.num) !== '#FF6C402E') { cardOk = false; cardDetail.push('边框' + i); }
  if (!n || hex(n.num) !== '#FF47271A') { cardOk = false; cardDetail.push('编号' + i); }
}
ck('五卡统一 #FFC9AC6D（= 4.png #c9ac6d）+ 边框 #6C402E + 编号 #47271A', cardOk,
  cardDetail.join('; ') || '5/5 通过');

// ⑤ childList / 悬空父
let clOk = true, clDetail = [];
for (const r of gb.recs) {
  const c = findChildListTop(r.field.sub); if (!c) continue;
  const list = asIdList(c.payload, true) || [];
  const kids = gb.recs.filter(q => q.parentId === r.id);
  if (list.length !== kids.length) { clOk = false; clDetail.push(r.name + ' ' + list.length + '/' + kids.length); continue; }
  const sorted = [...list].sort((x, y) => (ord.get(byId.get(x)?.field) ?? 1e9) - (ord.get(byId.get(y)?.field) ?? 1e9));
  if (sorted.some((v, i) => v !== list[i])) clOk = false;
}
ck('所有 childList 与 recTop 同序且子集完整', clOk, clDetail.slice(0, 4).join('; ') || '全通过');
const danglingASet = new Set(ga.recs.filter(r => r.parentId != null && !setA.has(r.parentId)).map(r => r.id));
const newDangling = gb.recs.filter(r => r.parentId != null && !setB.has(r.parentId) && !danglingASet.has(r.id));
ck('新增悬空父引用 0（683 基线模板记录不算）', newDangling.length === 0,
  `683 基线 ${danglingASet.size} 条，684 新增 ${newDangling.length} 条`);

// ⑥ 旧记录改动白名单
const bytesA = new Map(ga.recs.map(r => [r.id, encodeMsg([r.field])]));
const bytesB = new Map(gb.recs.map(r => [r.id, encodeMsg([r.field])]));
const changed = [...bytesA.keys()].filter(id => bytesB.has(id) && !bytesA.get(id).equals(bytesB.get(id)));
const allowed = new Set();
for (const n of RP.buttons.names) { allowed.add(R(n).id); allowed.add(gb.recs.find(r => r.name === 'label' && r.parentId === R(n).id).id); }
allowed.add(R(RP.countdown.name).id);
allowed.add(R(H.unify.name).id);
for (const F of SPEC.glass.frames) {
  const popup = R(F.key);
  allowed.add(gb.recs.find(r => r.name === 'frame' && r.parentId === popup.id).id);
}
const rogue = changed.filter(id => !allowed.has(id));
ck('旧记录改动全部落在白名单（rogue=0）', rogue.length === 0,
  `改动 ${changed.length} 条，rogue ${rogue.length}`);

const verdict = checks.every(c => c.ok);
fs.writeFileSync(path.join(DIR, '684_结构校验.json'), JSON.stringify({
  version: 684, verdict,
  base: { sha256: sha(A), records: ga.recs.length },
  output: { sha256: sha(B), bytes: fs.statSync(B).size, records: gb.recs.length },
  checks,
  summary: { passed: checks.filter(c => c.ok).length, total: checks.length,
    added: newIds.length, removed: goneIds.length, changedOldRecords: changed.length, rogue: rogue.length },
}, null, 2));
console.log(JSON.stringify({ verdict, passed: checks.filter(c => c.ok).length, total: checks.length,
  added: newIds.length, removed: goneIds.length, changedOldRecords: changed.length, rogue: rogue.length,
  failed: checks.filter(c => !c.ok).map(c => c.name + ' :: ' + c.detail) }, null, 2));
if (!verdict) process.exit(1);
