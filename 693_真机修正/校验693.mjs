// 693 · 独立结构校验器（不复用 构建693.mjs 的任何断言对象）
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const F691 = path.join(DIR, '../691_橙黄通用卡与真机修复/691_橙黄通用卡与真机修复.gil');
const F693 = path.join(DIR, '693_第三关与三格地毯.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '693_设计与补丁.json'), 'utf8'));
const TEXTS = JSON.parse(fs.readFileSync(path.join(DIR, '693_静态文本补丁.json'), 'utf8')).texts;
const FURN = JSON.parse(fs.readFileSync(path.join(DIR, '693_家具规格.json'), 'utf8'));
const L3 = JSON.parse(fs.readFileSync(path.join(DIR, '693_关卡数据.json'), 'utf8')).level3.lua;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(pathToFileURL(path.join(TOOLS, 'gilread.mjs')).href);
const { findScriptLeaf } = await import(pathToFileURL(path.join(TOOLS, 'gilwrite.mjs')).href);
const { isHiddenRecord, imageTriple } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const g0 = readGil(F691), g1 = readGil(F693);
const s691 = findScriptLeaf(g0).buf.toString('utf8');
const s693 = findScriptLeaf(g1).buf.toString('utf8');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
const tn = r => ns(r.field, [505, 503, 75, 510, 501])[0];
const tv = r => { const f = tn(r); return f && f.payload ? f.payload.toString('utf8') : null; };
const byId0 = new Map(g0.recs.map(r => [r.id, r]));
const byId1 = new Map(g1.recs.map(r => [r.id, r]));
const byName1 = new Map(g1.recs.filter(r => r.name).map(r => [r.name, r]));

// ── ① 基准与产物 ──────────────────────────────────────────────────────
ck('691 基准 SHA 前缀', sha(F691).startsWith('0fb6be5d437ffd'), sha(F691).slice(0, 16));
ck('691 记录数 7961', g0.recs.length === 7961, g0.recs.length);
ck('693 记录数 8007', g1.recs.length === 8007, g1.recs.length);
ck('691 原件未被覆盖', fs.statSync(F691).size === 7014646, fs.statSync(F691).size);
const AUD = JSON.parse(fs.readFileSync(path.join(DIR, '693_构建审计.json'), 'utf8'));
ck('产物 SHA 与构建审计一致', AUD.output.sha256 === sha(F693), sha(F693).slice(0, 16));
ck('693 内嵌 Lua 与落盘脚本一致', s693 === fs.readFileSync(path.join(DIR, '693_内嵌Lua_693.lua'), 'utf8'), 'ok');

// ── ② 逐记录比对（相对 691 增量） ─────────────────────────────────────
const m0 = new Map(g0.recs.map(r => [r.id, encodeMsg([r.field])]));
const ids0 = new Set(g0.recs.map(r => r.id));
const newRecs = g1.recs.filter(r => !ids0.has(r.id));
ck('新增记录 46 条', newRecs.length === 46, newRecs.length);
ck('新增 ID 无冲突且唯一', new Set(newRecs.map(r => r.id)).size === 46 &&
   newRecs.every(r => !ids0.has(r.id)), 'ok');
ck('旧记录 7961 条全部仍在', g0.recs.every(r => byId1.has(r.id)), 'ok');
const changed = g0.recs.filter(r => !m0.get(r.id).equals(encodeMsg([byId1.get(r.id).field])));
const allowed = new Set();
for (const [lv, rows] of Object.entries(TEXTS))
  for (const t of rows)
    for (const slot of ['letter', 'who', 'what']) {
      const r = byName1.get(`${slot}.${lv}.${t.slot}`);
      if (r) allowed.add(r.id);
    }
const thingsRec = byName1.get('things');
allowed.add(thingsRec.id);
const leafRec0 = findScriptLeaf(g0), leafRec1 = findScriptLeaf(g1);
// 内嵌 Lua 所在记录本身也是白名单
for (const r of g0.recs) if (encodeMsg([r.field]).equals(encodeMsg([leafRec0.field]))) allowed.add(r.id);
const rogue = changed.filter(r => !allowed.has(r.id));
// letter 字段值本就未变、部分 what 文本不含人名也未变 ⇒ 实际改动数 < 允许集大小是正常的；
// 判据是「所有改动都落在允许集内」+ rogue=0，而不是数量相等。
ck('改动记录均为白名单（文本/things/内嵌Lua）', changed.every(r => allowed.has(r.id)),
   `改动${changed.length} ⊆ 允许集${allowed.size}`);
ck('白名单外改动 rogue = 0', rogue.length === 0, rogue.slice(0, 6).map(r => r.name).join(','));

// ── ③ 三格地毯新素材 ──────────────────────────────────────────────────
const things0 = byId0.get(1073742795);
const cl0 = findChildListTop(things0.field.sub), cl1 = findChildListTop(thingsRec.field.sub);
const seq0 = asIdList(cl0.payload, true) || [], seq1 = asIdList(cl1.payload, true) || [];
ck('things.childList 11 → 13', seq0.length === 11 && seq1.length === 13, `${seq0.length}→${seq1.length}`);
for (const tpl of ['furn.rug.4', 'furn.rug.5']) {
  const spec = FURN.newAssets[tpl];
  const tplRecs = newRecs.filter(r => r.name === tpl);
  const src = tplRecs.find(r => r.parentId === null);
  const mama = tplRecs.find(r => r.parentId === 1073741844);
  const ref = tplRecs.find(r => r.parentId === thingsRec.id);
  ck(`${tpl} 三件套齐全`, tplRecs.length === 3 && !!src && !!mama && !!ref,
     `${tplRecs.length} 条 src=${src?.id} mama=${mama?.id} ref=${ref?.id}`);
  ck(`${tpl} 引用进入 things.childList`, !!ref && seq1.includes(ref.id), 'ok');
  ck(`${tpl} cfg.furn_tpl_prefab 指向新源`, s693.includes(`rug_${tpl.endsWith('4') ? '4' : '5'}    = ${src.id}`), src?.id);
  // referencedPrefabIndex 指向新源
  let prefabOk = false;
  (function walk(f) {
    if (f.wt === 0 && f.num != null && Number(f.num) === src.id) prefabOk = true;
    for (const q of f.sub || []) walk(q);
  })(ref.field);
  ck(`${tpl} 引用控件 referencedPrefabIndex 正确`, prefabOk, 'ok');
  for (const [tag, root] of [['源', src], ['母本', mama]]) {
    const contents = newRecs.filter(r => r.parentId === root.id);
    ck(`${tpl} ${tag} content 恰好 1 个`, contents.length === 1, contents.length);
    const c = contents[0];
    const st = stateBlocks(c.field.sub, [])[0];
    const geom = st ? [pairValue(pairOf(st, 505), 0), pairValue(pairOf(st, 505), 1)] : [];
    ck(`${tpl} ${tag} content 画布 216×216`, geom[0] === 216 && geom[1] === 216, geom.join('x'));
    const cl = findChildListTop(c.field.sub);
    const layers = (cl ? asIdList(cl.payload, true) : []) || [];
    ck(`${tpl} ${tag} 9 层`, layers.length === spec.layerCount, layers.length);
    let match = 0, zeroSpur = 0;
    layers.forEach((id, j) => {
      const r = byId1.get(id), L = spec.layers[j];
      if (!r || !L) return;
      const s = stateBlocks(r.field.sub, [])[0];
      if (!s) return;
      const g = [pairValue(pairOf(s, 504), 0), pairValue(pairOf(s, 504), 1),
                 pairValue(pairOf(s, 505), 0), pairValue(pairOf(s, 505), 1)];
      const tri = imageTriple(r.field);
      if (Math.abs(g[0] - L.x) < 0.01 && Math.abs(g[1] - L.y) < 0.01 &&
          Math.abs(g[2] - L.w) < 0.01 && Math.abs(g[3] - L.h) < 0.01 &&
          tri && tri.id === L.imageId &&
          Number(tri.color) === parseInt(L.color.replace('0x', ''), 16)) match++;
      if (Math.abs(g[0]) + g[2] / 2 <= 108.001 && Math.abs(g[1]) + g[3] / 2 <= 108.001) zeroSpur++;
    });
    ck(`${tpl} ${tag} 层几何/颜色/图元逐层匹配`, match === spec.layerCount, `${match}/${spec.layerCount}`);
    ck(`${tpl} ${tag} 零溢出`, zeroSpur === spec.layerCount, `${zeroSpur}/${spec.layerCount}`);
    ck(`${tpl} ${tag} 层未静态隐藏`,
       layers.every(id => !isHiddenRecord(byId1.get(id).field)), 'ok');
  }
  ck(`${tpl} 规格标注禁止拉伸`, spec.gate.noStretch === true && spec.gate.distinctAsset === true, 'ok');
}

// ── ④ 内嵌 Lua 补丁 ───────────────────────────────────────────────────
const P = SPEC.luaPatches.map(p => ({
  ...p,
  old: p.old.replace('__RUG4_PREFAB__', AUD.output.prefabIds['furn.rug.4'])
           .replace('__RUG5_PREFAB__', AUD.output.prefabIds['furn.rug.5']),
  new: p.new.replace('__RUG4_PREFAB__', AUD.output.prefabIds['furn.rug.4'])
           .replace('__RUG5_PREFAB__', AUD.output.prefabIds['furn.rug.5']),
}));
let missingNew = 0;
for (const p of P) if (!s693.includes(p.new)) missingNew++;
ck(`${P.length} 项补丁 new 文本全部落盘`, missingNew === 0, `missing=${missingNew}`);
const MODREPS = SPEC.moduleReplacements;
let back = s693;
for (let k = MODREPS.length - 1; k >= 0; k--) {
  const mr = MODREPS[k];
  const i0 = s691.indexOf(mr.marker), j0 = s691.indexOf('\nend', i0);
  const oldModule = s691.slice(i0, j0 + 4);
  const i1 = s693.indexOf(mr.marker), j1 = s693.indexOf('\nend', i1);
  ck(`${mr.name} 模块等于定稿`, s693.slice(i1, j1 + 4) === mr.newModule.trimEnd(), 'ok');
  back = back.replace(mr.newModule.trimEnd(), oldModule);
}
for (let i = P.length - 1; i >= 0; i--) back = back.split(P[i].new).join(P[i].old);
ck('Lua 补丁/双模块反向逐字节还原 691', back === s691,
   back === s691 ? 'ok' : `${back.length} vs ${s691.length}`);
ck('无 prefab 占位符残留', !s693.includes('__RUG4_PREFAB__') && !s693.includes('__RUG5_PREFAB__'), 'ok');
for (const [name, needle] of [
  ['TPL_KEY L3a/L3b', 'L3a = "furn.rug.4", L3b = "furn.rug.5"'],
  ['path_map 新素材', '["furn.rug.4"] = "root/things/furn.rug.4"'],
  ['cfg canvas 216×216', 'rug_4 = { 216, 216 }, rug_5 = { 216, 216 }'],
  ['cfg 等比不缩放', 'rug_4 = { x = 1, y = 1 }'],
  ['F.layout 识别 L 形', 'if not has["1:1"] then tri = "L3a"'],
  ['build_layout 采用 variant', 'p.variant == "L3a" or p.variant == "L3b"'],
  ['rug_cell_els 按边开放', 'local openL, openR = has(r, c - 1), has(r, c + 1)'],
  ['F.layout 传 cellset', 'F.rug_cell_els(b, cell[1], cell[2], cellset)'],
  ['_spawn 隐藏整块地毯（避免双绘）', 'or ckey=="rug_4" or ckey=="rug_5" then'],
  ['is_rug 纳入新 ckey', 'or ckey == "rug_4" or ckey == "rug_5"'],
]) ck(name, s693.includes(needle), needle.slice(0, 40));
// luac -p（ASCII 临时名）
let luacOk = false, luacErr = '';
try {
  const tmp = path.join(process.env.TEMP || '/tmp', `_v693_${process.pid}.lua`);
  fs.writeFileSync(tmp, s693, 'utf8');
  execFileSync('"C:/Users/18182/AppData/Local/Programs/Lua/bin/luac"', ['-p', tmp], { shell: true, stdio: 'pipe' });
  fs.rmSync(tmp, { force: true }); luacOk = true;
} catch (e) { luacErr = String(e.stderr || e.message).slice(0, 200); }
ck('luac -p 语法通过', luacOk, luacOk ? 'ok' : luacErr);

// ── ⑤ 静态文本 / 字母前缀口径 ─────────────────────────────────────────
let textOk = 0, textBad = [];
for (const [lv, rows] of Object.entries(TEXTS))
  for (const t of rows)
    for (const [slot, val] of [['letter', t.letter], ['who', t.who], ['what', t.what]]) {
      const r = byName1.get(`${slot}.${lv}.${t.slot}`);
      if (r && tv(r) === val) textOk++; else textBad.push(`${slot}.${lv}.${t.slot}`);
    }
ck('126 个静态文本字段逐条符合', textOk === 126, `ok=${textOk} bad=${textBad.slice(0, 5)}`);
const whoAll = Object.entries(TEXTS).flatMap(([lv, rows]) => rows.map(t => [lv, t]));
ck('who 区域为纯人名（无字母前缀）',
   whoAll.every(([lv, t]) => !/^[A-FV]/.test(t.who)), 'ok');
ck('所有人名 ≤4 字',
   Object.values(SPEC.names).every(m => Object.values(m).every(n => [...n].length <= 4)), 'ok');
ck('「我」前不加字母', whoAll.every(([lv, t]) => !/[A-FV]我/.test(t.what)), 'ok');
ck('卡面人名前加字母（抽查第4关）',
   TEXTS['4'][0].what.includes('我在D卷宗管理上方') && TEXTS['4'][4].what.includes('D卷宗管理在书架旁边'),
   TEXTS['4'][0].what + ' / ' + TEXTS['4'][4].what);
ck('第4关 A/D 姓名已对调',
   SPEC.names['4'].A === '夜巡值守' && SPEC.names['4'].D === '卷宗管理',
   `A=${SPEC.names['4'].A} D=${SPEC.names['4'].D}`);
ck('第4关 A/D 卡面内容顺序已互换',
   TEXTS['4'][0].what.startsWith('我在D') && TEXTS['4'][3].what === '我在椅子上',
   `槽1=${TEXTS['4'][0].what} 槽4=${TEXTS['4'][3].what}`);
ck('第4关互换声明为内容顺序互换', SPEC.level4.swapType.includes('内容顺序互换'), 'ok');

// ── ⑥ 1/2/4/5/6/7 关谜题零改动（归一化 name 后逐字节相同） ──────────
const norm = s => s.replace(/(name\s*=\s*)"[^"]*"/g, '$1"NAME"')
                   .replace(/(\["name"\]\s*=\s*)"[^"]*"/g, '$1"NAME"');
function module(src, lv) {
  const m = `__M["levels.case_${String(lv).padStart(3, '0')}"] = function()`;
  const i = src.indexOf(m), j = src.indexOf('\nend', i);
  return src.slice(i, j + 4);
}
// 第3/4 关整体替换（家具调整 / A/D 内容互换），其余关只缩短姓名
for (const lv of [1, 2, 5, 6, 7]) {
  const a = module(s691, lv), b = module(s693, lv);
  ck(`case_${String(lv).padStart(3, '0')} 除 name 外逐字节未变`, norm(a) === norm(b),
     `${a.length}→${b.length}`);
}
const m4a = module(s691, 4), m4b = module(s693, 4);
const triples = s => JSON.stringify([...s.matchAll(/\{"([vh])",\s*(\d+),\s*(\d+)\}/g)]
  .map(m => [m[1], Number(m[2]), Number(m[3])]));
ck('第4关墙/门与 691 相同', triples(m4a) === triples(m4b), 'ok');
ck('第4关答案站位与 691 相同',
   (m4a.match(/\["solution"\] = \{.*?\}\}/s) || [''])[0] ===
   (m4b.match(/\["solution"\] = \{.*?\}\}/s) || [''])[0], 'ok');
// 第3关：墙/门与 691 相同，家具按 v14 定稿
const m3_691 = module(s691, 3);
const walls691 = m3_691.match(/\["walls"\] = (\{.*?\}), \["doors"\]/s)?.[1];
const doors691 = m3_691.match(/\["doors"\] = (\{.*?\}), \["objects"\]/s)?.[1];
const parseTriple = s => [...s.matchAll(/\{"([vh])",\s*(\d+),\s*(\d+)\}/g)]
  .map(m => [m[1], Number(m[2]), Number(m[3])]);
ck('第3关 walls 与 691 相同',
   JSON.stringify(parseTriple(walls691 || '')) === JSON.stringify(L3.walls),
   `${parseTriple(walls691 || '').length} 段`);
ck('第3关 doors 与 691 相同',
   JSON.stringify(parseTriple(doors691 || '')) === JSON.stringify(L3.doors),
   `${parseTriple(doors691 || '').length} 段`);
ck('第3关 6 条线索 / 6 人答案', L3.clues.length === 6 && Object.keys(L3.solution).length === 6, 'ok');
ck('第3关 meta 不预告假卡', L3.meta.false_clue === undefined, JSON.stringify(L3.meta));
ck('第3关姓名为纯人名 ≤4 字',
   L3.suspects.every(s => !/^[A-FV]/.test(s.name) && [...s.name].length <= 4), 'ok');
const triCells = L3.objects['地毯'].cells;
ck('第3关地毯为三格 L 形', triCells.length === 3 &&
   new Set(triCells.map(c => `${c.r}:${c.c}`)).size === 3, JSON.stringify(triCells));
ck('第3关 V 房间只留 1 个书架', L3.objects['书架'].cells.length === 1,
   L3.objects['书架'].cells.length);
ck('第3关新增装饰家具 植物+雕塑',
   L3.objects['雕塑'].cells.length === 1 && L3.objects['植物'].cells.length === 2,
   `雕塑${L3.objects['雕塑'].cells.length} 植物${L3.objects['植物'].cells.length}`);
ck('第3关家具总格数仍为 12',
   Object.values(L3.objects).reduce((n, o) => n + o.cells.length, 0) === 12, 'ok');
const hp3 = Object.values(L3.hint_preview).filter(h => h.count > 0).length;
ck('第3关 hint_preview 部分线索有提示格', hp3 >= 3 && hp3 <= 5, `${hp3}/6`);

// ── 输出 ──────────────────────────────────────────────────────────────
const pass = checks.filter(c => c.pass).length, fail = checks.length - pass;
const out = { verdict: fail === 0, pass, fail, checks,
              note: '693 独立结构校验；基准 691（7961）→ 693（8007）' };
fs.writeFileSync(path.join(DIR, '693_结构校验.json'), JSON.stringify(out, null, 2));
for (const c of checks.filter(x => !x.pass)) console.log('FAIL:', c.name, '|', c.detail);
console.log(JSON.stringify({ verdict: out.verdict, pass, fail }, null, 2));
