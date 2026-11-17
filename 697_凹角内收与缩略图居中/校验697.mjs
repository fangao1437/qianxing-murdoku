// 697 · 独立结构校验器
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
const F696 = path.join(DIR, '../696_凹角与选关缩略图/696_凹角与选关缩略图.gil');
const F697 = path.join(DIR, '697_凹角内收与缩略图居中.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '697_设计与补丁.json'), 'utf8'));
const FURN = JSON.parse(fs.readFileSync(path.join(DIR, '697_家具规格.json'), 'utf8'));
const A = readGil(F696), B = readGil(F697);
const checks = [];
const ck = (g, n, ok, d) => checks.push({ group: g, name: n, pass: !!ok, detail: String(d ?? '') });

function geom(r) {
  const st = stateBlocks(r.field.sub, [])[0];
  return { x: pairValue(pairOf(st, 504), 0), y: pairValue(pairOf(st, 504), 1),
           w: pairValue(pairOf(st, 505), 0), h: pairValue(pairOf(st, 505), 1) };
}
function color(r) {
  const ns = (fs, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [fs]);
  const p = ns({ sub: r.field.sub }, [505, 503, 84])[0];
  const c = p && p.sub.find(x => x.field === 502 && x.wt === 0);
  return c ? Number(c.num) >>> 0 : null;
}

// ① 规模
ck('规模', '记录数 8011 不变', A.recs.length === 8011 && B.recs.length === 8011,
   `${A.recs.length} → ${B.recs.length}`);
ck('规模', '输出字节 ≠ 696', fs.statSync(F697).size !== fs.statSync(F696).size,
   `${fs.statSync(F696).size} → ${fs.statSync(F697).size}`);

// ② 角片内收：轮廓不凸出
for (const m of SPEC.cornerMoves) {
  const rb = B.recs.find(x => Number(x.id) === m.id);
  const ra = A.recs.find(x => Number(x.id) === m.id);
  const gb = rb && geom(rb), ga = ra && geom(ra);
  ck('角片内收', `#${m.id} 坐标 (${m.old}) → (${m.new})`,
     ga && Math.abs(ga.x - m.old[0]) < 0.01 && Math.abs(ga.y - m.old[1]) < 0.01
     && gb && Math.abs(gb.x - m.new[0]) < 0.01 && Math.abs(gb.y - m.new[1]) < 0.01,
     ga ? `${ga.x},${ga.y} → ${gb.x},${gb.y}` : 'MISSING');
  ck('角片内收', `#${m.id} 尺寸仍 12.96²、颜色仍深棕`,
     gb && Math.abs(gb.w - 12.96) < 0.01 && Math.abs(gb.h - 12.96) < 0.01
     && color(rb) === 0xFFB89A62, gb ? JSON.stringify(gb) : 'MISSING');
  // 不凸出判据：缺角象限恒在 y<0（L3a 右下 / L3b 左下），
  // 角片矩形必须完整落在 y≥0 的上半部，即 L 形内侧，绝不侵占空白格。
  const g = gb;
  const inL = g.y - g.h / 2 >= -0.01 && g.y + g.h / 2 <= 12.97
           && ((m.template === 'furn.rug.4' && g.x + g.w / 2 <= 0.01)
            || (m.template === 'furn.rug.5' && g.x - g.w / 2 >= -0.01));
  ck('角片内收', `#${m.id} 角片完全落在 L 形内侧（不凸出、不侵占缺角格）`,
     inL, JSON.stringify(g));
  ck('角片内收', `#${m.id} 父 content 未变`,
     [1073760714, 1073760715, 1073760737, 1073760738].includes(Number(rb.parentId)),
     `parent=${rb.parentId}`);
}
for (const cid of [1073760714, 1073760715, 1073760737, 1073760738]) {
  const r = B.recs.find(x => Number(x.id) === cid);
  const cl = findChildListTop(r.field.sub);
  ck('角片内收', `content #${cid} childList 仍 10 项`,
     (asIdList(cl.payload, true) || []).length === 10, 'ok');
}
ck('角片内收', '家具规格角片坐标同步内收',
   FURN.newAssets['furn.rug.4'].layers.some(L => L.part === '凹角封口' && L.x === -6.48 && L.y === 6.48)
   && FURN.newAssets['furn.rug.5'].layers.some(L => L.part === '凹角封口' && L.x === 6.48 && L.y === 6.48), 'ok');

// ③ Lua 补丁
const L696 = findScriptLeaf(A).buf.toString('utf8'), L697 = findScriptLeaf(B).buf.toString('utf8');
ck('Lua 补丁', '网格边长取 min 并在区域居中',
   L697.includes('local side = math.min(gw, gh)')
   && L697.includes('local gx = area.x + (area.w - side) * 0.5')
   && L697.includes('local gy = area.y + (area.h - side) * 0.5'), 'ok');
ck('Lua 补丁', '旧的铺满式 gx/gy 已移除',
   !L697.includes('local gx, gy = area.x + pad, area.y + pad'), 'ok');
ck('Lua 补丁', '1 项补丁反向逐字节还原 696', (() => {
  let s = L697;
  for (const p of [...SPEC.luaPatches].reverse()) s = s.replace(p.new, p.old);
  return s === L696;
})(), 'ok');
for (const needle of ['cardId .. ".cell." .. r .. "." .. c', 'text = t.short, style = "card.name"',
                      'if value == "card.name" then return 0xFF4A2E1C end',
                      '["name"] = "誊写员"', 'return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,'])
  ck('695/696 保留', needle.slice(0, 46), L697.includes(needle), 'ok');
const n9 = g => g.tree.find(f => f.field === 9);
const rootList = g => n9(g).sub.find(f => f.field === 501 && f.wt === 2 && asIdList(f.payload, true) !== null);
const proto = g => n9(g).sub.filter(f => f.field === 502)
  .find(f => f.sub && f.sub.some(x => x.field === 501 && Number(x.num) === 1073741844));
ck('695 保留', '/9/501 45 项、原型根 #503 35 项',
   asIdList(rootList(B).payload, true).length === 45
   && asIdList(proto(B).sub.find(f => f.field === 503 && f.wt === 2 && asIdList(f.payload, true) !== null).payload, true).length === 35, 'ok');

// ④ 白名单外零改动
const before = new Map(A.recs.map(r => [r.id, encodeMsg([r.field])]));
const changed = B.recs.filter(r => {
  const b = before.get(r.id);
  return b && !b.equals(encodeMsg([r.field]));
}).map(r => Number(r.id));
const MOVE_IDS = SPEC.cornerMoves.map(m => m.id);
ck('零改动', '记录变动恰为 4 条角片',
   changed.length === 4 && MOVE_IDS.every(id => changed.includes(id)), changed.join(','));
ck('零改动', '白名单外零改动（rogue=0）', changed.every(id => MOVE_IDS.includes(id)), 'ok');
ck('零改动', '其余 8007 条记录逐字节相同', B.recs.length - changed.length === 8007, 'ok');

// ⑤ 全树反向逐字节还原 696
{
  const dScript = findScriptLeaf(B).field;
  const save = Buffer.from(dScript.payload);
  dScript.payload = Buffer.from(L696, 'utf8'); dScript.len = dScript.payload.length;
  const ps = MOVE_IDS.map(id => {
    const r = B.recs.find(x => Number(x.id) === id);
    return pairOf(stateBlocks(r.field.sub, [])[0], 504);
  });
  // 直接改浮点对的 #501/#502（setPair 重建后两分量都非零，字段数不变，len 不变）
  ps.forEach((p, k) => {
    const m = SPEC.cornerMoves[k];
    const vals = p.sub.filter(x => x.wt === 5);
    vals[0].f = m.old[0]; vals[1].f = m.old[1];
  });
  const body696 = A.src.subarray(20, 20 + A.hdr[4]);
  ck('反向还原', '角片坐标 + script leaf 回退后重编码 == 696 body（逐字节）',
     encodeMsg(B.tree).equals(body696), `${encodeMsg(B.tree).length}/${body696.length}`);
  dScript.payload = save; dScript.len = save.length;
  ps.forEach((p, k) => {
    const m = SPEC.cornerMoves[k];
    const vals = p.sub.filter(x => x.wt === 5);
    vals[0].f = m.new[0]; vals[1].f = m.new[1];
  });
  ck('反向还原', '697 body 重编码与落盘字节一致',
     encodeMsg(B.tree).equals(B.src.subarray(20, 20 + B.hdr[4])), 'ok');
}

// ⑥ 外部闸门
try {
  const out = execFileSync(process.execPath, [path.join(TOOLS, 'roundtrip.mjs'), F697],
                           { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  ck('外部闸门', 'roundtrip 逐字节往返 PASS', /逐字节完全一致/.test(out), out.trim().slice(-90));
} catch (e) { ck('外部闸门', 'roundtrip 逐字节往返 PASS', false, String(e.stdout || e.message).slice(0, 200)); }
{
  const tmp = path.join(os.tmpdir(), `gil697_syntax_${process.pid}.lua`);
  fs.writeFileSync(tmp, L697, 'utf8');
  try {
    execFileSync('"C:/Users/18182/AppData/Local/Programs/Lua/bin/luac"', ['-p', tmp],
                 { stdio: ['ignore', 'pipe', 'pipe'], shell: true, timeout: 60000 });
    ck('外部闸门', 'luac -p 内嵌 Lua 语法 PASS', true, 'ok');
  } catch (e) { ck('外部闸门', 'luac -p 内嵌 Lua 语法 PASS', false, String(e.stderr || e.message).slice(0, 200)); }
  finally { fs.rmSync(tmp, { force: true }); }
}

const failed = checks.filter(c => !c.pass);
const out = { version: 697, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length, changedRecordIds: changed, checks };
fs.writeFileSync(path.join(DIR, '697_结构校验.json'), JSON.stringify(out, null, 2));
console.log(`697 结构校验 ${out.pass}/${out.total} PASS`);
for (const f of failed) console.log('  FAIL:', f.group, f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
