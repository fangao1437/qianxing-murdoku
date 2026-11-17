// 697 · 基于 696 最小增量写档
//   R1 4 条凹角补片几何中心内收（只改 stateBlocks 的 #504 位置对）
//   P1 内嵌 Lua：棋盘缩略图正方形居中
//   零新增/删除记录、零静态文本改动
// 用法：node 构建697.mjs --dry   /   FORCE=1 node 构建697.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const P696 = path.join(DIR, '../696_凹角与选关缩略图');
const INPUT = path.join(P696, '696_凹角与选关缩略图.gil');
const OUTPUT = path.join(DIR, '697_凹角内收与缩略图居中.gil');
const LUA696 = fs.readFileSync(path.join(P696, '696_内嵌Lua_696.lua'), 'utf8');
const LUA697 = fs.readFileSync(path.join(DIR, '697_内嵌Lua_697.lua'), 'utf8');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '697_设计与补丁.json'), 'utf8'));
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, setPair, pairValue } =
  await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const g = readGil(INPUT);
const BASE_SHA = sha(INPUT);
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const EXPECT = recBefore.size;
const BODY696 = g.src.subarray(20, 20 + g.hdr[4]);
const scriptField = findScriptLeaf(g).field;
if (findScriptLeaf(g).buf.toString('utf8') !== LUA696) throw Error('696 .gil 内嵌 Lua 与交付副本不一致');

// ── R1 角片内收 ───────────────────────────────────────────────────────
const moves = SPEC.cornerMoves;
const geoms = [];
for (const m of moves) {
  const r = g.recs.find(x => Number(x.id) === m.id);
  if (!r) throw Error('角片记录缺失 #' + m.id);
  const st = stateBlocks(r.field.sub, [])[0];
  if (!st) throw Error('角片缺几何状态块 #' + m.id);
  const p = pairOf(st, 504), s = pairOf(st, 505);
  const old = { x: pairValue(p, 0), y: pairValue(p, 1),
                w: pairValue(s, 0), h: pairValue(s, 1) };
  if (Math.abs(old.x - m.old[0]) > 0.01 || Math.abs(old.y - m.old[1]) > 0.01)
    throw Error('角片基线坐标不符 #' + m.id + ' ' + JSON.stringify(old));
  if (Math.abs(old.w - 12.96) > 0.01 || Math.abs(old.h - 12.96) > 0.01)
    throw Error('角片尺寸不是 12.96² #' + m.id);
  geoms.push({ r, st, p, old });
  setPair(p, m.new[0], m.new[1]);
}
scriptField.payload = Buffer.from(LUA697, 'utf8'); scriptField.len = scriptField.payload.length;

// ── 反向逐字节还原 696 ────────────────────────────────────────────────
function revert() {
  for (const o of geoms) setPair(o.p, o.old.x, o.old.y);
  scriptField.payload = Buffer.from(LUA696, 'utf8'); scriptField.len = scriptField.payload.length;
}
function apply() {
  for (const o of geoms) {
    const m = moves[geoms.indexOf(o)];
    setPair(o.p, m.new[0], m.new[1]);
  }
  scriptField.payload = Buffer.from(LUA697, 'utf8'); scriptField.len = scriptField.payload.length;
}
if (encodeMsg(g.tree).equals(BODY696)) throw Error('★ 改动没有写进编码树');
revert();
if (!encodeMsg(g.tree).equals(BODY696)) throw Error('★ 反向还原 696 未能逐字节一致');
apply();

const result = {
  version: 697,
  base: { file: path.relative(ROOT, INPUT), sha256: BASE_SHA, records: EXPECT,
          luaBytes: Buffer.byteLength(LUA696) },
  output: { expectRecords: EXPECT, added: 0, removed: 0, luaBytes: Buffer.byteLength(LUA697) },
  corner: { moves, note: SPEC.cornerPatch.note },
  lua: { patches: SPEC.luaPatches.length, reversible: true, revertToBase: '逐字节一致' },
  selectThumb: SPEC.selectThumb,
  texts: { changed: 0, note: '697 静态文本零改动' },
  puzzle: { note: '谜题数据零改动；695 注册修复、696 缩略图框架全部保留' },
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

const expected = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '697 凹角内收与缩略图居中', expectRecs: EXPECT,
  assert(t) {
    if (findScriptLeaf(t).buf.toString('utf8') !== LUA697) return '内嵌 Lua 不一致';
    for (const m of moves) {
      const r = t.recs.find(x => Number(x.id) === m.id);
      if (!r) return '角片缺失 #' + m.id;
      const p = pairOf(stateBlocks(r.field.sub, [])[0], 504);
      if (Math.abs(pairValue(p, 0) - m.new[0]) > 0.01 || Math.abs(pairValue(p, 1) - m.new[1]) > 0.01)
        return '角片坐标未内收 #' + m.id;
    }
    for (const r of t.recs) {
      const want = expected.get(r.id);
      if (want && !want.equals(encodeMsg([r.field]))) return '写后记录不一致 #' + r.id;
    }
    return true;
  },
});

const disk = readGil(OUTPUT);
if (disk.recs.length !== EXPECT) throw Error('磁盘记录数不符');
if (findScriptLeaf(disk).buf.toString('utf8') !== LUA697) throw Error('磁盘 Lua 不一致');
// 磁盘版反向还原 696
{
  const dScript = findScriptLeaf(disk).field;
  const save = Buffer.from(dScript.payload);
  dScript.payload = Buffer.from(LUA696, 'utf8'); dScript.len = dScript.payload.length;
  const dg = moves.map(m => {
    const r = disk.recs.find(x => Number(x.id) === m.id);
    const p = pairOf(stateBlocks(r.field.sub, [])[0], 504);
    return { p, x: pairValue(p, 0), y: pairValue(p, 1) };
  });
  dg.forEach((o, k) => setPair(o.p, moves[k].old[0], moves[k].old[1]));
  if (!encodeMsg(disk.tree).equals(BODY696)) throw Error('磁盘版无法反向逐字节还原 696');
  dScript.payload = save; dScript.len = save.length;
  dg.forEach((o, k) => setPair(o.p, moves[k].new[0], moves[k].new[1]));
}
const changedIds = disk.recs.filter(r => {
  const b = recBefore.get(r.id);
  return b && !b.equals(encodeMsg([r.field]));
}).map(r => Number(r.id));
result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.changedExisting = changedIds.length;
result.output.changedRecordIds = changedIds;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '697_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
