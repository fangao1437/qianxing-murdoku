// tools/gil/fix_backrops.mjs —— 给 clue.i.backrop1/2 配「100001 + 调色」，并修 clue.2.backrop2 的高度
//
// 背景（2026-10-04）：用户在编辑器里给每张卡加了两张图做描边效果
//   backrop1（在下）= 描边色、backrop2（在上）= 填充色，
//   但**没有配图** ⇒ 记录里 #84 块只有 #502（source=4294967295），**没有 #503（图片 id）**。
//   ⚠️ 现成的 retint.mjs 用不了：它只"替换"已有字段，不"新建"（干跑 5 个全跳过）。
//
// 本脚本做四件事：
//   1) 每个 backrop 的 #84 块：#502 -> 4280097563（与 board.bg 同一来源），并**插入** #503 = 100001
//   2) 每个 backrop 的 4 个状态块里的颜色三元组（#1/#2/#3 float）-> 目标色
//        backrop1 = #56565E（描边）、backrop2 = #26262E（填充）
//   3) clue.2.backrop2 的尺寸 float 96 -> 90（四态），让四周描边都是 3px
//   4) 写出新 .gil（长度由 encodeMsg 自动重算）
//
// 用法：node tools/gil/fix_backrops.mjs --in=186.gil --out=186_fixed.gil [--probe]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg } from './gilread.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const argOf = (k) => { const a = argv.find((s) => s.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : null; };
const DRY = argv.includes('--probe');

const IN = argOf('in') || '186.gil';
const OUT = argOf('out') || '186_fixed.gil';
const SRC = 4280097563;          // 内置素材库的 imageSource（取自 board.bg）
const IMG = 100001;              // 基础形状-正四边形
const COL = { backrop1: [0.337255, 0.337255, 0.368627], backrop2: [0.149020, 0.149020, 0.180392] };

const g = readGil(path.join(ROOT, IN));
console.log(`基准：${IN}  控件记录 ${g.recs.length} 条`);

const F = (f) => f.field;
const sub = (f) => f.sub || [];
const isFloat = (f) => f.wt === 5;
const targets = g.recs.filter((r) => /^clue\.\d+\.backrop[12]$/.test(r.name || ''));
console.log(`目标控件：${targets.length} 个（${targets.map((r) => r.name).join(', ') || '无'}）`);

let imgFixed = 0, colFixed = 0, sizeFixed = 0;

// ── 1 & 2：图片字段 + 颜色
for (const r of targets) {
  const which = r.name.endsWith('backrop1') ? 'backrop1' : 'backrop2';
  // 递归找 #84 块（里面有 #502）
  const found = [];
  (function walk(fs) {
    for (const f of fs) {
      if (F(f) === 84 && sub(f).length) found.push(f);
      if (f.sub) walk(f.sub);
    }
  })(r.field.sub);
  for (const blk of found) {
    const kids = sub(blk);
    const src = kids.find((k) => F(k) === 502);
    let idf = kids.find((k) => F(k) === 503);
    if (src) { if (src.num !== SRC) { src.num = SRC; } imgFixed++; }
    if (!idf) { idf = { field: 503, wt: 0, num: IMG }; kids.push(idf); console.log(`  + ${r.name} 插入 #503=${IMG}`); }
    else if (idf.num !== IMG) idf.num = IMG;
  }
  // 颜色三元组：#501 下面有 3 个 float 子字段（field 1/2/3）
  (function walk(fs) {
    for (const f of fs) {
      const k = sub(f);
      if (F(f) === 501 && k.length === 3 && k.every(isFloat) && k.map(F).join(',') === '1,2,3') {
        const c = COL[which];
        k.forEach((x, i) => { x.num = c[i]; });
        colFixed++;
      }
      if (f.sub) walk(f.sub);
    }
  })(r.field.sub);
  // ── 3：clue.2.backrop2 的高度 96 -> 90
  if (r.name === 'clue.2.backrop2') {
    (function walk(fs) {
      for (const f of fs) {
        if (isFloat(f) && typeof f.num === 'number' && Math.abs(f.num - 96) < 0.01) { f.num = 90; sizeFixed++; }
        if (f.sub) walk(f.sub);
      }
    })(r.field.sub);
  }
}

console.log(`改图：${imgFixed} 处；颜色：${colFixed} 处；尺寸：${sizeFixed} 处`);
if (DRY) { console.log('（--probe 干跑，未写文件）'); process.exit(0); }

const body = encodeMsg(g.tree);
const out = g.pack(body);
fs.writeFileSync(path.join(ROOT, OUT), out);
console.log(`已写出 ${OUT}：${out.length} 字节（原 ${g.src.length}，差 ${out.length - g.src.length}）`);
