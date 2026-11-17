// 694 · 基于 693 最小增量写档（地毯渲染修复 + 第3关删装饰植物）
//   只改内嵌 Lua 的 script leaf：2 项可逆补丁 + 1 处 case_003 模块替换。
//   零新增记录、零静态文本改动；693 的三格 L 形新素材三件套原样保留。
// 用法：node 构建694.mjs --dry   /   FORCE=1 node 构建694.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const P693 = path.join(DIR, '../693_真机修正');
const INPUT = path.join(P693, '693_第三关与三格地毯.gil');
const OUTPUT = path.join(DIR, '694_地毯渲染修复.gil');
const LUA694 = path.join(DIR, '694_内嵌Lua_694.lua');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '694_设计与补丁.json'), 'utf8'));
const FURN = JSON.parse(fs.readFileSync(path.join(DIR, '694_家具规格.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const s693 = findScriptLeaf(g).buf.toString('utf8');
const s693Ref = fs.readFileSync(path.join(P693, '693_内嵌Lua_693.lua'), 'utf8');
if (s693 !== s693Ref) throw Error('693 .gil 内嵌 Lua 与交付副本不一致');
const EXPECT = recBefore.size;

// ── A Lua 补丁（可逆） ─────────────────────────────────────────────────
const P = SPEC.luaPatches;
function applyPatches(src) {
  let s = src;
  for (const p of P) {
    const n = s.split(p.old).length - 1;
    if (n !== p.count) throw Error(`补丁 ${p.name} 锚点数应为 ${p.count}，实得 ${n}`);
    s = s.replace(p.old, p.new);
  }
  return s;
}
function revertPatches(s) {
  for (let i = P.length - 1; i >= 0; i--) s = s.replace(P[i].new, P[i].old);
  return s;
}
let s = applyPatches(s693);

// ── B case_003 模块整体替换 ────────────────────────────────────────────
const MR = SPEC.moduleReplacements[0];
const i = s.indexOf(MR.marker);
if (i < 0) throw Error('case_003 模块未找到');
const j = s.indexOf('\nend', i);
if (j < 0) throw Error('case_003 模块结束未找到');
const oldModule = s.slice(i, j + 4);
const newModule = MR.newModule.trimEnd();
s = s.slice(0, i) + newModule + s.slice(j + 4);
function revertAll(s2) { return revertPatches(s2.replace(newModule, oldModule)); }
if (revertAll(s) !== s693) throw Error('Lua 补丁无法逐字节反向还原 693');

// ── C 内容硬闸门 ──────────────────────────────────────────────────────
if (!s.includes('return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,'))
  throw Error('地毯整块模板路径未恢复');
if (s.includes('res.cell[cell[1]][cell[2]].els = F.rug_cell_els'))
  throw Error('逐格 rug_cell_els 未关闭');
if (!s.includes('or ckey=="rug_4" or ckey=="rug_5" then'))
  throw Error('L3a/L3b 新素材未纳入地毯分支');
const i3 = s.indexOf(MR.marker), j3 = s.indexOf('\nend', i3);
const mod3 = s.slice(i3, j3 + 4);
if (mod3.includes('{["r"] = 1, ["c"] = 6}')) throw Error('第3关右上角植物未删');
if (!mod3.includes('["雕塑"]')) throw Error('第3关雕塑丢失');
if (!mod3.includes('["kind"] = "carpet"')) throw Error('第3关三格地毯丢失');
for (const t of ['furn.rug.4', 'furn.rug.5'])
  if (!s.includes(`["${t}"] = "root/things/${t}"`)) throw Error('path_map 缺 ' + t);

const script = Buffer.from(s, 'utf8');
const result = {
  version: 694,
  base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA, records: EXPECT,
          luaBytes: Buffer.byteLength(s693) },
  output: { expectRecords: EXPECT, added: 0, changedExisting: 1,
            luaBytes: script.length },
  lua: { patches: P.length, modulesReplaced: [MR.name], reversible: true },
  carpet: { templates: SPEC.carpetRender.templates, path: SPEC.carpetRender.path,
            perCellEls: SPEC.carpetRender.perCellEls },
  level3: { plantRemoved: '1,6', furniture: SPEC.level3.furniture },
  texts: { changed: 0, note: '694 静态文本零改动（卡序与人名保持不变）' },
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── D 写档（五闸） ────────────────────────────────────────────────────
const leaf = findScriptLeaf(g).field;
leaf.payload = script; leaf.len = script.length;
const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '694 地毯渲染修复', expectRecs: EXPECT,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(script)) return '内嵌 Lua 不一致';
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录不一致 #' + r.id + ' ' + r.name;
    }
    return true;
  },
});

// ── E 磁盘重读二次复核 ────────────────────────────────────────────────
const disk = readGil(OUTPUT);
const diskLua = findScriptLeaf(disk).buf.toString('utf8');
if (disk.recs.length !== EXPECT) throw Error('磁盘记录数不符');
if (diskLua !== s) throw Error('磁盘内嵌 Lua 不一致');
if (revertAll(diskLua) !== s693) throw Error('磁盘 Lua 无法反向还原 693');
let rogue = 0, scriptRecs = 0;
for (const r of disk.recs) {
  const b = recBefore.get(r.id);
  if (b && !b.equals(encodeMsg([r.field]))) {
    // 唯一允许变动的是 script leaf 所在记录
    scriptRecs++;
    if (scriptRecs > 1) rogue++;
  }
}
if (rogue) throw Error('出现白名单外旧记录改动 ' + rogue);
fs.writeFileSync(LUA694, diskLua, 'utf8');
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.rogue = rogue;
result.output.changedRecords = scriptRecs;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '694_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
