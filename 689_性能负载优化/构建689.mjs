// 689 · 基于 688 的性能负载优化（基准 688 保留未改）
//   仅改内嵌 Lua：① 剥离纯空白行；② 5 处每帧同步链去冗余补丁。
//   存档记录表（7921 条）逐字节全同 688；补丁可反向逐字节还原 688。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const INPUT = path.join(ROOT, 'qianxing-murdoku/688_第4至7关接入/688_第4至7关接入.gil');
const OUTPUT = path.join(DIR, '689_性能负载优化.gil');
const LUA689 = path.join(DIR, '689_内嵌Lua_689.lua');
const DRY = process.argv.includes('--dry');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

if (fs.existsSync(OUTPUT) && !DRY && process.env.FORCE !== '1')
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);

const PATCH = JSON.parse(fs.readFileSync(path.join(DIR, '689_性能补丁.json'), 'utf8'));

// ── 空白行剥离 / 还原（可逆，索引由 688 原件重算，无需持久化） ──────────
function strip(s) {
  const kept = [], blanks = [];
  for (const ln of s.split('\n')) {
    if (/^[ \t\r]*$/.test(ln)) blanks.push([kept.length, ln]);
    else kept.push(ln);
  }
  const groups = new Map();
  for (const [k, txt] of blanks) { if (!groups.has(k)) groups.set(k, []); groups.get(k).push(txt); }
  return { text: kept.join('\n'), blanks: groups, removed: blanks.length, kept: kept.length };
}
function restore(s, groups) {
  const arr = s.split('\n');
  for (let k = arr.length; k >= 0; k--) {
    const items = groups.get(k);
    if (items) arr.splice(k, 0, ...items);
  }
  return arr.join('\n');
}
function locate(s, p) {
  let from = 0;
  if (p.anchor) {
    const a0 = s.indexOf(p.anchor);
    if (a0 < 0) throw Error('补丁参考锚点未找到：' + p.name);
    if (s.indexOf(p.anchor, a0 + p.anchor.length) >= 0) throw Error('补丁参考锚点不唯一：' + p.name);
    from = a0 + p.anchor.length;
  }
  const i0 = s.indexOf(p.start, from);
  if (i0 < 0) throw Error('补丁起点未找到：' + p.name);
  if (s.indexOf(p.start, i0 + p.start.length) >= 0) throw Error('补丁起点不唯一：' + p.name);
  const i1 = s.indexOf(p.endMarker, i0 + p.start.length);
  if (i1 < 0) throw Error('补丁终点未找到：' + p.name);
  return { i0, i1, old: s.slice(i0, i1) };
}
function noBlank(t) {
  const a = t.split('\n');
  if (a[a.length - 1] === '') a.pop();       // 末尾换行是行分隔符，不算空白行
  return a.every(ln => !/^[ \t\r]*$/.test(ln));
}

const g = readGil(INPUT);
const s688 = findScriptLeaf(g).buf.toString('utf8');
const baseSha = sha(INPUT);
const recBefore = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));

const st = strip(s688);
let s1 = st.text;
const olds = [];
for (const p of PATCH.patches) {
  if (!noBlank(p.new)) throw Error('补丁 new 含纯空白行，会破坏可逆性：' + p.name);
  const { i0, i1, old } = locate(s1, p);
  if (!noBlank(old)) throw Error('补丁 old 含纯空白行：' + p.name);
  olds.push(old);
  s1 = s1.slice(0, i0) + p.new + s1.slice(i1);
}
const s689 = s1;

// ── 反向逐字节还原 688 ──────────────────────────────────────────────────
let rev = s689;
for (let i = PATCH.patches.length - 1; i >= 0; i--) {
  const p = PATCH.patches[i];
  if (!rev.includes(p.new)) throw Error('反向补丁 new 缺失：' + p.name);
  rev = rev.replace(p.new, () => olds[i]);
}
rev = restore(rev, st.blanks);
if (rev !== s688) throw Error('反向补丁未能逐字节还原 688：' +
  Buffer.byteLength(rev) + ' vs ' + Buffer.byteLength(s688));
if (restore(st.text, st.blanks) !== s688) throw Error('空白行还原自检失败');

const script = Buffer.from(s689, 'utf8');
const leaf = findScriptLeaf(g).field;
leaf.payload = script; leaf.len = script.length;

const result = {
  base: { file: path.relative(ROOT, INPUT), sha256: baseSha, records: g.recs.length,
          scriptBytes: Buffer.byteLength(s688) },
  output: { scriptBytes: script.length, expectRecords: recBefore.size },
  strip: { blankLinesRemoved: st.removed, blankBytesRemoved: Buffer.byteLength(s688) - Buffer.byteLength(st.text) },
  patches: PATCH.patches.map(p => p.name),
  reversibility: { restoredTo688Bytes: true },
};
if (DRY) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

// ── 写档（writeGil 五道闸门） ───────────────────────────────────────────
writeGil(g, OUTPUT, {
  label: '689 性能负载优化', expectRecs: recBefore.size,
  assert(t) {
    const l = findScriptLeaf(t);
    if (!l.buf.equals(script)) return 'script mismatch';
    for (const r of t.recs) {
      const e = recBefore.get(r.id);
      if (!e || !e.equals(encodeMsg([r.field]))) return 'record mismatch ' + r.name;
    }
    return true;
  },
});

// ── 磁盘重读复核 ────────────────────────────────────────────────────────
const disk = readGil(OUTPUT);
let changedRecords = 0;
for (const r of disk.recs) {
  const e = recBefore.get(r.id);
  if (!e || !e.equals(encodeMsg([r.field]))) changedRecords++;
}
if (disk.recs.length !== recBefore.size) throw Error('记录数变化');
if (changedRecords) throw Error('记录表出现改动：' + changedRecords);
if (!findScriptLeaf(disk).buf.equals(script)) throw Error('磁盘内嵌 Lua 不一致');
fs.writeFileSync(LUA689, s689, 'utf8');

result.output.sha256 = sha(OUTPUT);
result.output.bytes = fs.statSync(OUTPUT).size;
result.output.recordsOnDisk = disk.recs.length;
result.output.changedRecords = changedRecords;
result.output.luaRoundtrip = true;
fs.writeFileSync(path.join(DIR, '689_构建审计.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
