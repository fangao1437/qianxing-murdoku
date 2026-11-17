// 696 · 独立结构校验器（不复用构建器断言）
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, asIdList, findChildListTop, stateBlocks, pairOf, pairValue } =
  await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const F695 = path.join(DIR, '../695_地毯原型注册与改名/695_地毯原型注册与改名.gil');
const F696 = path.join(DIR, '696_凹角与选关缩略图.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '696_设计与补丁.json'), 'utf8'));
const FURN = JSON.parse(fs.readFileSync(path.join(DIR, '696_家具规格.json'), 'utf8'));
const A = readGil(F695), B = readGil(F696);
const checks = [];
const ck = (g, n, ok, d) => checks.push({ group: g, name: n, pass: !!ok, detail: String(d ?? '') });

const C = SPEC.cornerPatch;
const CONTENT_IDS = C.patches.map(p => p.content);
const NEW_IDS = C.patches.map((p, k) => 1073760757 + k);

// ── ① 规模 ────────────────────────────────────────────────────────────
ck('规模', '记录数 8007 → 8011（+4）', A.recs.length === 8007 && B.recs.length === 8011,
   `${A.recs.length} → ${B.recs.length}`);
ck('规模', '输出字节 ≠ 695', fs.statSync(F696).size !== fs.statSync(F695).size,
   `${fs.statSync(F695).size} → ${fs.statSync(F696).size}`);

// ── ② 4 条凹角补片 ───────────────────────────────────────────────────
function geomOf(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  const p = pairOf(st, 504), s = pairOf(st, 505);
  return { x: pairValue(p, 0), y: pairValue(p, 1), w: pairValue(s, 0), h: pairValue(s, 1) };
}
function colorOf(r) {
  const ns = (fs, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [fs]);
  const p = ns({ sub: r.field.sub }, [505, 503, 84])[0];
  if (!p || !p.sub) return null;
  const c = p.sub.find(x => x.field === 502 && x.wt === 0);
  const i = p.sub.find(x => x.field === 503 && x.wt === 0);
  return { color: c && Number(c.num) >>> 0, imageId: i && Number(i.num) };
}
C.patches.forEach((p, k) => {
  const id = NEW_IDS[k];
  const r = B.recs.find(x => Number(x.id) === id);
  ck('凹角补片', `${p.template} ${p.copy} 角片 #${id} 存在且父正确`,
     !!r && String(r.parentId) === String(p.content), r ? `${r.name} parent=${r.parentId}` : 'MISSING');
  if (!r) return;
  const g = geomOf(r);
  ck('凹角补片', `#${id} 几何中心 (${p.x},${p.y}) / ${C.size}²`,
     Math.abs(g.x - p.x) < 0.01 && Math.abs(g.y - p.y) < 0.01
     && Math.abs(g.w - C.size) < 0.01 && Math.abs(g.h - C.size) < 0.01, JSON.stringify(g));
  const c = colorOf(r);
  ck('凹角补片', `#${id} 深棕外框色 + 图元 100001`,
     c && c.color === parseInt(C.color.replace('0x', ''), 16) && c.imageId === 100001, JSON.stringify(c));
  const i504 = r.field.sub.findIndex(f => f.field === 504 && f.wt === 0);
  const i505 = r.field.sub.findIndex(f => f.field === 505);
  ck('凹角补片', `#${id} #504 与既有模板同构（在第一个 #505 之前）`,
     i504 >= 0 && (i505 < 0 || i504 < i505), `${i504}/${i505}`);
});
CONTENT_IDS.forEach((cid, k) => {
  const r = B.recs.find(x => Number(x.id) === cid);
  const cl = r && findChildListTop(r.field.sub);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  ck('凹角补片', `content #${cid} childList 9 → 10 且含角片`,
     ids.length === 10 && ids[9] === NEW_IDS[k], ids.slice(-3).join(','));
});
ck('凹角补片', '家具规格 layerCount 同步为 10',
   FURN.newAssets['furn.rug.4'].layerCount === 10 && FURN.newAssets['furn.rug.5'].layerCount === 10, 'ok');
ck('凹角补片', '两套角片分别位于缺右下 / 缺左下象限',
   C.patches[0].x > 0 && C.patches[2].x < 0 && C.patches.every(p => p.y < 0), 'ok');

// ── ③ 695 的结构修复与人名全部保留 ───────────────────────────────────
const n9 = g => g.tree.find(f => f.field === 9);
const rootList = g => n9(g).sub.find(f => f.field === 501 && f.wt === 2 && asIdList(f.payload, true) !== null);
const protoRoot = g => n9(g).sub.filter(f => f.field === 502)
  .find(f => f.sub && f.sub.some(x => x.field === 501 && Number(x.num) === 1073741844));
const mamaList = g => protoRoot(g).sub.find(f => f.field === 503 && f.wt === 2 && asIdList(f.payload, true) !== null);
const rl = asIdList(rootList(B).payload, true), ml = asIdList(mamaList(B).payload, true);
ck('695 保留', '/9/501 仍为 45 项且含两个新源', rl.length === 45
   && rl.includes(1073760711) && rl.includes(1073760734), String(rl.length));
ck('695 保留', '原型根 #503 仍为 35 项且含两个新母本', ml.length === 35
   && ml.includes(1073760712) && ml.includes(1073760735), String(ml.length));
const things = B.recs.find(r => r.name === 'things');
const tcl = findChildListTop(things.field.sub);
ck('695 保留', 'things.childList 13 项', (asIdList(tcl.payload, true) || []).length === 13, 'ok');
const L695 = findScriptLeaf(A).buf.toString('utf8'), L696 = findScriptLeaf(B).buf.toString('utf8');
ck('695 保留', '誊写员仍在、墨绿誊写已无',
   L696.includes('["name"] = "誊写员"') && !L696.includes('墨绿誊写'), 'ok');
ck('695 保留', '整块模板路径与诊断日志仍在',
   L696.includes('return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,')
   && L696.includes('地毯模板实例化失败：ckey='), 'ok');

// ── ④ Lua 补丁内容 ───────────────────────────────────────────────────
for (const [nm, needle] of [
  ['P1 ui_list 补 room_grid', 'room_grid = room_grid'],
  ['P2 每格底色', 'cardId .. ".cell." .. r .. "." .. c'],
  ['P2 墙线', 'line(".wall." .. k, x, y, ww, hh, INK)'],
  ['P2 门线', 'line(".door." .. d'],
  ['P2 旧房间块收起', 'visible = false, rect = { x = area.x, y = area.y, w = 1, h = 1 }'],
  ['P3 底部关卡名', 'text = t.short, style = "card.name"'],
  ['P3 顶部规格信息', 'text = t.info, style = "card.title"'],
  ['P4 短名提取', '^案件%s*%d+%s*·%s*([^·]+)'],
  ['P5 深棕字色', 'if value == "card.name" then return 0xFF4A2E1C end'],
]) ck('Lua 补丁', nm + ' 存在', L696.includes(needle), needle.slice(0, 50));
ck('Lua 补丁', '5 项补丁反向还原 695 逐字节一致', (() => {
  let s = L696;
  for (const p of [...SPEC.luaPatches].reverse()) s = s.replace(p.new, p.old);
  return s === L695;
})(), 'ok');

// ── ⑤ 白名单外零改动 ─────────────────────────────────────────────────
const before = new Map(A.recs.map(r => [r.id, encodeMsg([r.field])]));
const changed = B.recs.filter(r => {
  const b = before.get(r.id);
  return b && !b.equals(encodeMsg([r.field]));
}).map(r => Number(r.id));
ck('零改动', '旧记录变动恰为 4 个 content',
   changed.length === 4 && CONTENT_IDS.every(id => changed.includes(id)), changed.join(','));
ck('零改动', '白名单外零改动（rogue=0）',
   changed.every(id => CONTENT_IDS.includes(id)), changed.join(','));
ck('零改动', '其余 8003 条旧记录逐字节相同', A.recs.length - changed.length === 8003,
   String(A.recs.length - changed.length));

// ── ⑥ 全树反向逐字节还原 695 ─────────────────────────────────────────
{
  const d9 = n9(B), dScript = findScriptLeaf(B).field;
  const dCls = CONTENT_IDS.map(cid => findChildListTop(B.recs.find(r => Number(r.id) === cid).field.sub));
  const dNew = d9.sub.filter(f => {
    const t = f.sub && f.sub.find(x => x.field === 501 && x.wt === 0);
    return t && NEW_IDS.includes(Number(t.num));
  });
  const aCls = CONTENT_IDS.map(cid => findChildListTop(A.recs.find(r => Number(r.id) === cid).field.sub));
  const save = { script: Buffer.from(dScript.payload), cls: dCls.map(x => Buffer.from(x.payload)) };
  dScript.payload = Buffer.from(findScriptLeaf(A).field.payload); dScript.len = dScript.payload.length;
  dCls.forEach((cl, k) => { cl.payload = Buffer.from(aCls[k].payload); cl.len = cl.payload.length; });
  dNew.forEach(f => { const i = d9.sub.indexOf(f); if (i >= 0) d9.sub.splice(i, 1); });
  const body695 = A.src.subarray(20, 20 + A.hdr[4]);
  ck('反向还原', '全部改动回退后重编码 == 695 body（逐字节）',
     encodeMsg(B.tree).equals(body695), `${encodeMsg(B.tree).length}/${body695.length}`);
  dScript.payload = save.script; dScript.len = save.script.length;
  dCls.forEach((cl, k) => { cl.payload = save.cls[k]; cl.len = save.cls[k].length; });
  C.patches.forEach((p, k) => {
    const proto = B.recs.find(r => Number(r.id) === p.cloneFrom);
    const at = d9.sub.indexOf(proto.field);
    d9.sub.splice(at + 1, 0, dNew[k]);
  });
  ck('反向还原', '696 body 重编码与落盘字节一致',
     encodeMsg(B.tree).equals(B.src.subarray(20, 20 + B.hdr[4])), 'ok');
}

// ── ⑦ 外部闸门 ───────────────────────────────────────────────────────
try {
  const out = execFileSync(process.execPath, [path.join(TOOLS, 'roundtrip.mjs'), F696],
                           { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  ck('外部闸门', 'roundtrip 逐字节往返 PASS', /逐字节完全一致/.test(out), out.trim().slice(-120));
} catch (e) { ck('外部闸门', 'roundtrip 逐字节往返 PASS', false, String(e.stdout || e.message).slice(0, 200)); }
{
  const tmp = path.join(os.tmpdir(), `gil696_syntax_${process.pid}.lua`);
  fs.writeFileSync(tmp, L696, 'utf8');
  try {
    execFileSync('"C:/Users/18182/AppData/Local/Programs/Lua/bin/luac"', ['-p', tmp],
                 { stdio: ['ignore', 'pipe', 'pipe'], shell: true, timeout: 60000 });
    ck('外部闸门', 'luac -p 内嵌 Lua 语法 PASS', true, 'ok');
  } catch (e) { ck('外部闸门', 'luac -p 内嵌 Lua 语法 PASS', false, String(e.stderr || e.message).slice(0, 200)); }
  finally { fs.rmSync(tmp, { force: true }); }
}

const failed = checks.filter(c => !c.pass);
const out = { version: 696, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length, newRecordIds: NEW_IDS, changedRecordIds: changed, checks };
fs.writeFileSync(path.join(DIR, '696_结构校验.json'), JSON.stringify(out, null, 2));
console.log(`696 结构校验 ${out.pass}/${out.total} PASS`);
for (const f of failed) console.log('  FAIL:', f.group, f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
