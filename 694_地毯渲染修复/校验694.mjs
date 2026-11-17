// 694 · 独立结构校验：693 → 694 只改内嵌 Lua，其余逐字节未动
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const P693 = path.join(DIR, '../693_真机修正');
const F693 = path.join(P693, '693_第三关与三格地毯.gil');
const F694 = path.join(DIR, '694_地毯渲染修复.gil');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '694_设计与补丁.json'), 'utf8'));
const K694 = JSON.parse(fs.readFileSync(path.join(DIR, '694_关卡数据.json'), 'utf8'));
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, findChildListTop, asIdList } =
  await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });

const a = readGil(F693), b = readGil(F694);
const s693 = findScriptLeaf(a).buf.toString('utf8');
const s694 = findScriptLeaf(b).buf.toString('utf8');
const byName = g => new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
// 与 638/693 同款字段选择器：文本正文在 505/503/75/510/501，记录名不在这一层
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
const tn = r => { const f = ns(r.field, [505, 503, 75, 510, 501])[0];
                  return f && f.payload ? f.payload.toString('utf8') : null; };

// ── ① 整体：记录数 / 原件 / rogue ─────────────────────────────────────
ck('694 记录数 = 693（8007）', b.recs.length === a.recs.length && b.recs.length === 8007,
   `${a.recs.length} → ${b.recs.length}`);
const A = new Map(a.recs.map(r => [r.id, encodeMsg([r.field])]));
let changed = [], missing = [];
for (const r of b.recs) {
  const old = A.get(r.id);
  if (!old) { missing.push(r.name); continue; }
  if (!old.equals(encodeMsg([r.field]))) changed.push(r.name || '#' + r.id);
}
ck('无新增/丢失记录', missing.length === 0, missing.slice(0, 5));
// script leaf 挂在 g.tree 上、不属于任何 g.recs 记录 ⇒ 记录层应零变动
ck('所有 g.recs 记录逐字节未变（rogue=0）', changed.length === 0,
   `${changed.length} 条：${changed.slice(0, 4).join(', ')}`);
ck('内嵌 Lua 确实已改（693 ≠ 694）', s693 !== s694, 'ok');
ck('693 内嵌 Lua SHA 与规格一致',
   crypto.createHash('sha256').update(s693).digest('hex') === SPEC.base.sha256Lua, 'ok');

// ── ② Lua 补丁可逆性 ─────────────────────────────────────────────────
for (const p of SPEC.luaPatches) {
  ck(`补丁落盘：${p.name}`, s694.includes(p.new) && !s694.includes(p.old), 'ok');
}
const MR = SPEC.moduleReplacements[0];
const i0 = s693.indexOf(MR.marker), j0 = s693.indexOf('\nend', i0);
const oldModule = s693.slice(i0, j0 + 4);
let back = s694.replace(MR.newModule.trimEnd(), oldModule);
for (let k = SPEC.luaPatches.length - 1; k >= 0; k--)
  back = back.replace(SPEC.luaPatches[k].new, SPEC.luaPatches[k].old);
ck('Lua 补丁 + 模块替换可反向逐字节还原 693', back === s693,
   back === s693 ? 'ok' : `${back.length} vs ${s693.length}`);

// ── ③ 地毯渲染路径 ───────────────────────────────────────────────────
ck('rug 分支恢复整块模板 _spawn_whole_rug',
   /or ckey=="rug_4" or ckey=="rug_5" then[\s\S]{0,400}?return self:_spawn_whole_rug\(/.test(s694), 'ok');
ck('逐格 rug_cell_els 已关闭', !s694.includes('res.cell[cell[1]][cell[2]].els = F.rug_cell_els'), 'ok');
ck('691 的「隐藏所有 rug 实例」已移除', !s694.includes('if string.find(k,"|rug",1,true) and o and o.SetVisible'), 'ok');
ck('地毯分支不再 return false',
   !/or ckey=="rug_5" then[\s\S]{0,300}?return false/.test(s694), 'ok');
for (const t of ['furn.rug.4', 'furn.rug.5']) {
  ck(`path_map 注册 ${t}`, s694.includes(`["${t}"] = "root/things/${t}"`), 'ok');
  ck(`cfg.furn_tpl_prefab 含 ${t.replace('furn.', '')}`,
     new RegExp(`rug_${t.slice(-1)}\\s*=\\s*1073\\d+`).test(s694), 'ok');
  ck(`cfg.furn_tpl_canvas 含 ${t.replace('furn.', '')} 216×216`,
     new RegExp(`rug_${t.slice(-1)}\\s*=\\s*\\{\\s*216,\\s*216\\s*\\}`).test(s694), 'ok');
}
ck('TPL_KEY 注册 L3a/L3b', s694.includes('L3a = "furn.rug.4", L3b = "furn.rug.5"'), 'ok');
ck('F.layout 仍给三格地毯打 L3a/L3b variant',
   s694.includes('tri = "L3a"') && s694.includes('tri = "L3b"'), 'ok');
// .gil 里新素材三件套仍完整
const bName = byName(b);
for (const t of ['furn.rug.4', 'furn.rug.5']) {
  const fam = b.recs.filter(r => r.name === t);
  ck(`${t} 三件套仍完整（3 条）`, fam.length === 3, fam.length);
  const src = fam.find(r => r.parentId == null);
  const kids = src ? b.recs.filter(r => r.parentId === src.id) : [];
  ck(`${t} 源 content = 1`, kids.length === 1, kids.length);
  if (kids.length) {
    const cl = findChildListTop(kids[0].field.sub);
    ck(`${t} content 仍为 9 层`, (asIdList(cl.payload, true) || []).length === 9,
       (asIdList(cl.payload, true) || []).length);
  }
}
const things = bName.get('things');
ck('things.childList 仍为 13 项（含两套新素材）',
   (asIdList(findChildListTop(things.field.sub).payload, true) || []).length === 13, 'ok');

// ── ④ 第3关：装饰植物删除 ────────────────────────────────────────────
const i3 = s694.indexOf(MR.marker), j3 = s694.indexOf('\nend', i3);
const mod3 = s694.slice(i3, j3 + 4);
const L3 = K694.level3.lua;
ck('case_003 模块等于定稿新模块', mod3 === MR.newModule.trimEnd(), 'ok');
ck('第3关植物只剩 (1,1)',
   L3.objects['植物'].cells.length === 1 &&
   L3.objects['植物'].cells[0].r === 1 && L3.objects['植物'].cells[0].c === 1,
   JSON.stringify(L3.objects['植物'].cells));
ck('case_003 Lua 里已无 (1,6) 植物', !mod3.includes('{["r"] = 1, ["c"] = 6}'), 'ok');
ck('第3关 V 房间：1 书架 (1,5)',
   L3.objects['书架'].cells.length === 1 && L3.objects['书架'].cells[0].r === 1 &&
   L3.objects['书架'].cells[0].c === 5, JSON.stringify(L3.objects['书架'].cells));
ck('第3关 V 房间：1 雕塑 (2,6)',
   L3.objects['雕塑'].cells.length === 1 && L3.objects['雕塑'].cells[0].r === 2 &&
   L3.objects['雕塑'].cells[0].c === 6, JSON.stringify(L3.objects['雕塑'].cells));
ck('第3关三格 L 形地毯格数 = 3', L3.objects['地毯'].cells.length === 3,
   JSON.stringify(L3.objects['地毯'].cells));
ck('第3关家具格总数 = 11',
   Object.values(L3.objects).reduce((n, o) => n + o.cells.length, 0) === 11, 'ok');
ck('第3关答案/墙/门与 693 相同',
   JSON.stringify(L3.solution) === JSON.stringify(
     JSON.parse(fs.readFileSync(path.join(P693, '693_关卡数据.json'), 'utf8')).level3.lua.solution) &&
   JSON.stringify(L3.walls) === JSON.stringify(
     JSON.parse(fs.readFileSync(path.join(P693, '693_关卡数据.json'), 'utf8')).level3.lua.walls), 'ok');
ck('第3关 hint_preview 与 693 相同（(1,6) 邻格均不可站）',
   JSON.stringify(L3.hint_preview) === JSON.stringify(
     JSON.parse(fs.readFileSync(path.join(P693, '693_关卡数据.json'), 'utf8')).level3.lua.hint_preview), 'ok');

// ── ⑤ 静态文本与人名：694 零改动 ─────────────────────────────────────
const aName = byName(a);
let same = 0, diff = [];
for (const lv of [1, 2, 3, 4, 5, 6, 7])
  for (let slot = 1; slot <= 7; slot++)
    for (const k of ['letter', 'who', 'what']) {
      const n = `${k}.${lv}.${slot}`;
      const ra = aName.get(n), rb = bName.get(n);
      if (!ra && !rb) continue;
      const va = ra ? tn(ra) : null, vb = rb ? tn(rb) : null;
      if (va === vb) same++; else diff.push(n);
    }
ck('1~7 关静态文本逐字与 693 相同', diff.length === 0, `${same} 条，差异 ${diff.join(',')}`);
ck('who 区无字母前缀、人名 ≤4 字',
   [1, 2, 3, 4, 5, 6, 7].every(lv => [1, 2, 3, 4, 5, 6, 7].every(slot => {
     const r = bName.get(`who.${lv}.${slot}`);
     if (!r) return true;
     const t = tn(r);
     return t && !/^[A-FV]/.test(t) && t.length <= 4;
   })), 'ok');
// 第4关 A/D 内容互换仍生效
ck('第4关 A/D 姓名对调仍生效',
   s694.includes('["id"] = "A", ["name"] = "夜巡值守"') &&
   s694.includes('["id"] = "D", ["name"] = "卷宗管理"'), 'ok');

// ── ⑥ 输出 ───────────────────────────────────────────────────────────
const failed = checks.filter(c => !c.pass);
const out = { version: 694, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length, checks, baseSha: crypto.createHash('sha256')
                .update(fs.readFileSync(F693)).digest('hex'),
              outputSha: crypto.createHash('sha256').update(fs.readFileSync(F694)).digest('hex') };
fs.writeFileSync(path.join(DIR, '694_结构校验.json'), JSON.stringify(out, null, 2));
console.log(`694 结构校验 ${out.pass}/${out.total} PASS`);
for (const f of failed) console.log('  FAIL:', f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
