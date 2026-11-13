// 683 · 独立结构校验（重新从磁盘读 682 / 683，不复用构建器内存状态）
//   node 校验683.mjs  → 683_结构校验.json  verdict = true
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
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '683_规格.json'), 'utf8'));
const A = path.join(REPO, SPEC.base.file);
const B = path.join(DIR, '683_弹窗细线与四键.gil');
const ga = readGil(A), gb = readGil(B);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const byId = new Map(gb.recs.map(r => [r.id, r]));
const byName = new Map(gb.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => byName.get(n);
const rt = gb.tree.find(f => f.field === 9);
const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
const hex = v => '#' + Number(BigInt.asUintN(32, BigInt(v))).toString(16).toUpperCase().padStart(8, '0');
const imgParts = r => {
  const out = [];
  const walk = (f, d = 0) => {
    if (d > 30) return;
    if (f.field === 84 && f.sub) out.push(f);
    if (f.sub) for (const s of f.sub) walk(s, d + 1);
  };
  walk(r.field); return out;
};
const fillOf = r => imgParts(r).map(p => p.sub.find(q => q.field === 502 && q.wt === 0)).find(Boolean);
const imgOf = r => imgParts(r).map(p => p.sub.find(q => q.field === 503 && q.wt === 0)).find(Boolean);
const geom = r => {
  const st = stateBlocks(r.field.sub, [])[0];
  if (!st) return null;
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return p && s ? { dx: pairValue(p, 0), dy: pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1) } : null;
};

const checks = [];
const ck = (name, ok, detail = '') => { checks.push({ name, ok: !!ok, detail }); return !!ok; };

// ① 基础
ck('记录数 7582 → 7621', ga.recs.length === 7582 && gb.recs.length === 7621,
  `${ga.recs.length} → ${gb.recs.length}`);
const setA = new Set(ga.recs.map(r => r.id)), setB = new Set(gb.recs.map(r => r.id));
const newIds = [...setB].filter(i => !setA.has(i)), goneIds = [...setA].filter(i => !setB.has(i));
ck('新增 40 / 删除 1', newIds.length === 40 && goneIds.length === 1,
  `+${newIds.length} / -${goneIds.length}`);
ck('无重复 ID', new Set(gb.recs.map(r => r.id)).size === gb.recs.length);
ck('内嵌 Lua 逐字节相同', findScriptLeaf(ga).buf.equals(findScriptLeaf(gb).buf),
  `${findScriptLeaf(gb).buf.length} B`);
ck('输入 682 SHA 与规格一致', sha(A) === SPEC.base.sha256);

// ② DECOR 名单（与内嵌 Lua 常量一致）
const luaSrc = fs.readFileSync(path.join(REPO, 'lua/engine_adapter_qianxing.lua'), 'utf8');
const decorBlock = luaSrc.match(/local DECOR = \{([\s\S]*?)\}/);
const decor = new Set([...decorBlock[1].matchAll(/(\w+)\s*=\s*true/g)].map(m => m[1]));
ck('DECOR 含 art/frame/label', ['art', 'frame', 'label'].every(k => decor.has(k)),
  [...decor].join(','));

// ③ 四键居中
const C = SPEC.fourKeysCenter;
const yOk = C.scope.every((n, i) => {
  const r = R(n); return r && Math.abs(geom(r).dy - C.afterY[i]) < 0.01;
});
ck('退出菜单四键 y = 120/40/-40/-120', yOk,
  C.scope.map(n => n + '=' + (R(n) ? geom(R(n)).dy : '?')).join(' '));
ck('倒计时已移到四键下方留白 y=-200（不被胶囊遮挡）',
  Math.abs(geom(R('modal.settle.countdown')).dy - (-200)) < 0.01);
const resultY = ['result.next', 'result.exit', 'result.home', 'result.settle'].map(n => geom(R(n)).dy);
ck('结算态四键保持 682 不变', resultY.join(',') === '-22,-102,-182,-262', resultY.join(','));

// ④ 胶囊：DECOR 容器 + 描边 + 填充同色
let capsOk = true, capDetail = [];
for (const bid of SPEC.capsule.buttons) {
  const btn = R(bid);
  const kids = gb.recs.filter(r => r.parentId === btn.id);
  const grp = kids.find(r => r.name === 'art');
  if (!grp || !decor.has(grp.name)) { capsOk = false; capDetail.push(bid + ':缺 DECOR 容器'); continue; }
  const sub = gb.recs.filter(r => r.parentId === grp.id);
  const outlines = sub.filter(r => /^art683\..*\.outline\./.test(r.name));
  const fills = sub.filter(r => /^art682\..*\.capsule\./.test(r.name));
  if (outlines.length !== 3 || fills.length !== 3) { capsOk = false; capDetail.push(bid + ':层数 ' + outlines.length + '/' + fills.length); continue; }
  const fc = fillOf(fills[0]), oc = fillOf(outlines[0]);
  if (!fc || hex(fc.num) !== '#FFFCECD4') { capsOk = false; capDetail.push(bid + ':填充色 ' + (fc && hex(fc.num))); }
  if (!oc || hex(oc.num) !== '#FF6C402E') { capsOk = false; capDetail.push(bid + ':描边色 ' + (oc && hex(oc.num))); }
  const label = kids.find(r => r.name === 'label');
  if (!label || !decor.has(label.name)) { capsOk = false; capDetail.push(bid + ':label 异常'); }
  const gm = geom(outlines[0]), fm = geom(fills[0]);
  if (Math.abs((gm.w - fm.w) - 4) > 0.01 || Math.abs((gm.h - fm.h) - 4) > 0.01) {
    capsOk = false; capDetail.push(bid + ':描边厚度不符');
  }
}
ck('8 组胶囊：DECOR 容器 / 3 层描边 / 首页同色填充 / label 豁免', capsOk, capDetail.join('; ') || '8/8 通过');

// ⑤ 边框细节与官方放大镜
let frameOk = true, frameDetail = [];
for (const F of SPEC.frames) {
  const popup = R(F.key);
  const rim = gb.recs.find(r => r.name === 'art' && r.parentId === popup.id);
  const fc = gb.recs.find(r => r.name === 'frame' && r.parentId === popup.id);
  const line = R('art683.' + F.key + '.frame.inner.line');
  const face = R('art683.' + F.key + '.frame.inner.face');
  const glass = R('art683.' + F.key + '.frame.glass');
  if (!rim || !fc || !line || !face || !glass) { frameOk = false; frameDetail.push(F.key + ':缺层'); continue; }
  if (!decor.has(rim.name) || !decor.has(fc.name)) { frameOk = false; frameDetail.push(F.key + ':容器非 DECOR'); }
  const gc = geom(glass), ic = geom(line), gim = imgOf(glass);
  if (!gim || Number(gim.num) !== 100120) { frameOk = false; frameDetail.push(F.key + ':放大镜不是 100120'); }
  const gcFill = fillOf(glass);
  if (!gcFill || hex(gcFill.num) !== '#FFF9EFC7') { frameOk = false; frameDetail.push(F.key + ':放大镜色'); }
  const rimFill = fillOf(rim), lineFill = fillOf(line), faceFill = fillOf(face);
  if (!rimFill || hex(rimFill.num) !== '#FF47271A') { frameOk = false; frameDetail.push(F.key + ':外圈细线色'); }
  if (!lineFill || hex(lineFill.num) !== '#FF6C402E') { frameOk = false; frameDetail.push(F.key + ':内圈细线色'); }
  if (!faceFill || hex(faceFill.num) !== '#FFFFF5D6') { frameOk = false; frameDetail.push(F.key + ':内页填充色'); }
  const gm = geom(rim), fm = geom(fc);
  if (Math.abs(gm.w - fm.w - 4) > 0.01 || Math.abs(gm.h - fm.h - 4) > 0.01) {
    frameOk = false; frameDetail.push(F.key + ':外圈细线厚度');
  }
  if (Math.abs((ic.w - geom(face).w) - 4) > 0.01) { frameOk = false; frameDetail.push(F.key + ':内圈线宽'); }
  if (Math.abs(gc.w - F.glass.w) > 0.01 || Math.abs(gc.dx - F.glass.dx) > 0.01) {
    frameOk = false; frameDetail.push(F.key + ':放大镜几何');
  }
  if (isHiddenRecord(glass.field) || isHiddenRecord(line.field) || isHiddenRecord(rim.field)) {
    frameOk = false; frameDetail.push(F.key + ':新增层被隐藏');
  }
  // 层序：rim 在 frame 之前；inner/glass 在 paper 之后
  const paper = R('art682.' + F.key + '.frame.paper');
  if (!(ord.get(rim.field) < ord.get(fc.field))) { frameOk = false; frameDetail.push(F.key + ':rim 层序'); }
  if (!(ord.get(paper.field) < ord.get(line.field) && ord.get(line.field) < ord.get(face.field) && ord.get(face.field) < ord.get(glass.field))) {
    frameOk = false; frameDetail.push(F.key + ':内页层序');
  }
}
ck('2 组边框：外圈深墨细线 / 内圈深色细线 / 100120 放大镜 / 层序', frameOk,
  frameDetail.join('; ') || '2/2 通过');

// ⑥ 首页杂质矩形
const IMP = SPEC.homeImpurity;
ck('杂质矩形已删除', !setB.has(IMP.id) && !gb.recs.some(r => r.name === IMP.name));
const treeBytes = encodeMsg(gb.tree);
const needle = Buffer.from(writeVarint(IMP.id));
ck('被删 ID 全文 0 引用', !treeBytes.includes(needle));
const gridParent = R(IMP.parent);
const cl = findChildListTop(gridParent.field.sub);
const clIds = cl ? (asIdList(cl.payload, true) || []) : [];
ck('grid.reuse childList 已去掉杂质 ID', !clIds.includes(IMP.id), `childList ${clIds.length} 项`);

// ⑦ childList / 层序 / 悬空父
let clOk = true, clDetail = [];
for (const r of gb.recs) {
  const c = findChildListTop(r.field.sub);
  if (!c) continue;
  const list = asIdList(c.payload, true) || [];
  const kids = gb.recs.filter(q => q.parentId === r.id);
  if (list.length !== kids.length) { clOk = false; clDetail.push(r.name + ' 数量 ' + list.length + '/' + kids.length); continue; }
  const sorted = [...list].sort((x, y) => (ord.get(byId.get(x)?.field) ?? 1e9) - (ord.get(byId.get(y)?.field) ?? 1e9));
  if (sorted.some((v, i) => v !== list[i])) clOk = false;
}
ck('所有 childList 与 recTop 同序且子集完整', clOk, clDetail.slice(0, 4).join('; ') || '全通过');
const danglingASet = new Set(ga.recs.filter(r => r.parentId != null && !setA.has(r.parentId)).map(r => r.id));
const newDangling = gb.recs.filter(r => r.parentId != null && !setB.has(r.parentId) && !danglingASet.has(r.id));
ck('新增悬空父引用 0（682 基线模板记录不算）', newDangling.length === 0,
  `682 基线 ${danglingASet.size} 条，683 新增 ${newDangling.length} 条`);

// ⑧ 旧记录改动白名单
const bytesA = new Map(ga.recs.map(r => [r.id, encodeMsg([r.field])]));
const bytesB = new Map(gb.recs.map(r => [r.id, encodeMsg([r.field])]));
const changed = [...bytesA.keys()].filter(id => bytesB.has(id) && !bytesA.get(id).equals(bytesB.get(id)));
const allowed = new Set();
for (const n of [...C.scope, 'modal.settle.countdown']) allowed.add(R(n).id);
for (const bid of SPEC.capsule.buttons) {
  allowed.add(R(bid).id);
  for (const s of ['body', 'left', 'right']) allowed.add(R('art682.' + bid + '.capsule.' + s).id);
}
for (const F of SPEC.frames) {
  allowed.add(R(F.key).id);
  allowed.add(gb.recs.find(r => r.name === 'frame' && r.parentId === R(F.key).id).id);
}
allowed.add(gridParent.id);
const rogue = changed.filter(id => !allowed.has(id));
ck('旧记录改动全部落在白名单（rogue=0）', rogue.length === 0,
  `改动 ${changed.length} 条，rogue ${rogue.length}`);

const verdict = checks.every(c => c.ok);
const out = {
  version: 683, verdict,
  base: { sha256: sha(A), records: ga.recs.length },
  output: { sha256: sha(B), bytes: fs.statSync(B).size, records: gb.recs.length },
  checks,
  summary: { passed: checks.filter(c => c.ok).length, total: checks.length,
    added: newIds.length, removed: goneIds.length, changedOldRecords: changed.length, rogue: rogue.length },
};
fs.writeFileSync(path.join(DIR, '683_结构校验.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify({ verdict, ...out.summary, failed: checks.filter(c => !c.ok).map(c => c.name + ' :: ' + c.detail) }, null, 2));
if (!verdict) process.exit(1);
