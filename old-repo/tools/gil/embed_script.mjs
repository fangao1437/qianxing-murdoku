// tools/gil/embed_script.mjs —— 把**当前客户端脚本**写进 .gil（做到"导入即最新"）
//
// 背景（2026-09-27 踩到）：用户导入我生成的 .gil 后，关卡目录里出现的是**导出那一刻的旧脚本**
//   （实测 353.3KB，而我当时的最新是 368KB）→ 跑的是旧代码，新加的诊断一行都没有，
//   于是白排查了整轮。根因：.gil 里**内嵌了一份脚本副本**，导入时游戏把它解出来。
//
// 定位方式见 tools/gil/find_script.mjs：脚本是树里唯一那个"超大叶子文本字段"
//   （实测路径 `/#50/#1/#5`，361795 字节）。
//
// 用法：
//   node tools/gil/embed_script.mjs --probe
//   node tools/gil/embed_script.mjs --in=完整界面3.gil --out=完整界面4.gil

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const DRY = argv.includes('--probe');

const BASE = argOf('in') || path.join(ROOT, '完整界面3.gil');
const OUT = argOf('out') || path.join(ROOT, '完整界面4.gil');
const SCRIPT = argOf('script') || path.join(ROOT, 'dist', 'client_script.lua');

for (const [k, p] of Object.entries({ 存档: BASE, 脚本: SCRIPT })) {
  if (!fs.existsSync(p)) { console.error('缺' + k + '：' + p); process.exit(1); }
}

const g = readGil(BASE);
const want = fs.readFileSync(SCRIPT);
console.log('存档：' + path.basename(BASE) + '（' + g.src.length + ' 字节）');
console.log('脚本：' + path.basename(SCRIPT) + '（' + want.length + ' 字节）');

// ── 找"内嵌脚本"字段：树里最大的、像 Lua 的叶子文本 ──────────────────────
const cands = [];
(function walk(fields, pathStr) {
  for (const f of fields) {
    const here = pathStr + '/#' + f.field;
    if (f.wt === 2 && f.sub === null && f.payload && f.payload.length > 2000) {
      const s = f.payload.toString('utf8');
      const bad = (s.match(/\uFFFD/g) || []).length;
      if (bad < f.payload.length * 0.01 && /function\s|local\s/.test(s)) {
        cands.push({ field: f, path: here, len: f.payload.length });
      }
    }
    if (f.sub) walk(f.sub, here);
  }
})(g.tree, '');
cands.sort((a, b) => b.len - a.len);

if (!cands.length) {
  console.error('\n❌ 没找到内嵌脚本（>2000 字节的 Lua 文本字段）。');
  console.error('   要么这份 .gil 里没有脚本，要么编码方式与我预期不同 —— 先跑 find_script.mjs 看清单。');
  process.exit(2);
}
const target = cands[0];
console.log('内嵌脚本字段：' + target.path + '  现 ' + target.len + ' 字节 → 新 ' + want.length
  + ' 字节（' + (want.length >= target.len ? '+' : '') + (want.length - target.len) + '）');
if (cands.length > 1) {
  console.log('  （另有 ' + (cands.length - 1) + ' 个候选：'
    + cands.slice(1, 4).map((c) => c.path + '=' + c.len).join(', ') + ' —— 只替换最大的那个）');
}

if (target.len === want.length && target.field.payload.equals(want)) {
  console.log('\n★ 内容已经是最新的，无需改动。');
  process.exit(0);
}

if (DRY) { console.log('\n--probe：不写文件'); process.exit(0); }

// ── 替换 + 重编码（长度前缀由编码器全部重算）──────────────────────────────
target.field.payload = want;
target.field.len = want.length;
target.field.isText = true;

const body = encodeMsg(g.tree);
const outBuf = g.pack(body);
fs.writeFileSync(OUT, outBuf);

// ── 自检：重新读一遍，确认内嵌脚本 == dist ────────────────────────────────
const g2 = readGil(OUT);
let check = null;
(function walk(fields, pathStr) {
  for (const f of fields) {
    const here = pathStr + '/#' + f.field;
    if (here === target.path && f.payload && f.payload.length > 2000) { check = f.payload; return; }
    if (f.sub) walk(f.sub, here);
  }
})(g2.tree, '');

console.log('\n输出：' + path.basename(OUT));
console.log('  体 ' + body.length + '（原 ' + g.hdr[4] + '，' + (body.length - g.hdr[4] >= 0 ? '+' : '') + (body.length - g.hdr[4]) + '）  文件 ' + outBuf.length);
console.log('  头 ' + [0, 4, 8, 12, 16].map((o) => outBuf.readUInt32BE(o)).join(', '));
const tr = outBuf.subarray(outBuf.length - g.trailer.length);
console.log('  尾 ' + tr.toString('hex') + (tr.equals(g.trailer) ? '  ✅' : '  ❌'));
console.log('  重新解析 ✅ 控件记录 ' + g2.recs.length + '（原 ' + g.recs.length + '）');

const same = check !== null && check.equals(want);
console.log('  ' + (same ? '✅' : '❌') + ' 内嵌脚本 == dist/client_script.lua（'
  + (check ? check.length : 0) + ' 字节）');
console.log('\n' + (same ? '★ 导入这个存档就是最新脚本，不需要再手动同步' : '❌ 自检不通过，先别用'));
process.exit(same ? 0 : 3);
